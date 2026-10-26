import Foundation
import Speech
import AVFoundation
import Combine

/// 叫び声・音声認識によりPOV文字をリアルタイムに上書き更新するサービス
/// - 日本語(ja-JP)と英語(en-US)の認識器を同時に走らせ、信頼度とキーワード一致で良い方を採用する
///   （キーボード言語や端末設定に依存しない）
/// - 一定時間発話がなければ onResetRequested で最初の文字（HELP等）へ戻す
public final class VoiceRescueService: ObservableObject {
    public static let shared = VoiceRescueService()
    
    // 公開プロパティ
    @Published public var isVoiceSyncEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(isVoiceSyncEnabled, forKey: "is_voice_sync_enabled")
            if !isVoiceSyncEnabled && isListening {
                stopListening()
            }
        }
    }
    
    @Published public var autoResetToDefault: Bool = true {
        didSet {
            UserDefaults.standard.set(autoResetToDefault, forKey: "voice_auto_reset_to_default")
        }
    }
    
    @Published public var resetDelaySeconds: Double = 5.0 {
        didSet {
            UserDefaults.standard.set(resetDelaySeconds, forKey: "voice_reset_delay_seconds")
        }
    }
    
    @Published public private(set) var isListening: Bool = false
    @Published public private(set) var recognizedText: String = ""
    @Published public private(set) var isShouting: Bool = false
    @Published public private(set) var audioLevel: Float = 0.0
    @Published public private(set) var permissionGranted: Bool = false
    @Published public private(set) var statusMessage: String = "待機中"
    
    /// true: 認識した文をそのまま返す（光通信用）。false: 救難キーワードへ正規化し5文字に丸める（POV用）
    public var useFullPhrase: Bool = false
    /// フルフレーズ時の最大文字数（末尾を優先）
    public var maxCharacters: Int = 16
    
    // コールバック: 新しい叫び声/音声が認識された時、呼び出し元に通知
    public var onTextRecognized: ((String) -> Void)?
    // コールバック: 自動リセット時間経過時に元の文字へ戻す通知
    public var onResetRequested: (() -> Void)?
    
    private var audioEngine = AVAudioEngine()
    
    /// 認識チャンネル（言語ごとに1本）
    private final class Channel {
        let locale: String
        let recognizer: SFSpeechRecognizer
        var request: SFSpeechAudioBufferRecognitionRequest?
        var task: SFSpeechRecognitionTask?
        var latestText: String = ""
        var latestConfidence: Float = 0
        var latestDate: Date = .distantPast
        init(locale: String, recognizer: SFSpeechRecognizer) {
            self.locale = locale
            self.recognizer = recognizer
        }
    }
    private var channels: [Channel] = []
    
    /// 古いセッションからの遅延コールバックを無視するためのトークン
    private var sessionToken: Int = 0
    
    private var resetTimer: Timer?
    private var shoutDebounceTimer: Timer?
    private var consecutiveLoudCount: Int = 0
    private var lastAppliedText: String = ""
    
    private init() {
        if UserDefaults.standard.object(forKey: "is_voice_sync_enabled") != nil {
            self.isVoiceSyncEnabled = UserDefaults.standard.bool(forKey: "is_voice_sync_enabled")
        }
        if UserDefaults.standard.object(forKey: "voice_auto_reset_to_default") != nil {
            self.autoResetToDefault = UserDefaults.standard.bool(forKey: "voice_auto_reset_to_default")
        }
        let savedDelay = UserDefaults.standard.double(forKey: "voice_reset_delay_seconds")
        if savedDelay > 0 {
            self.resetDelaySeconds = savedDelay
        }
    }
    
    /// マイク及び音声認識の権限をリクエスト
    public func requestPermissions(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { authStatus in
            if #available(iOS 17.0, *) {
                AVAudioApplication.requestRecordPermission { recordGranted in
                    DispatchQueue.main.async {
                        let granted = (authStatus == .authorized) && recordGranted
                        self.permissionGranted = granted
                        completion(granted)
                    }
                }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { recordGranted in
                    DispatchQueue.main.async {
                        let granted = (authStatus == .authorized) && recordGranted
                        self.permissionGranted = granted
                        completion(granted)
                    }
                }
            }
        }
    }
    
    /// 使用する認識言語（日本語＋英語＋端末言語）
    private func makeChannels() -> [Channel] {
        var identifiers = ["ja-JP", "en-US"]
        if let device = Locale.preferredLanguages.first {
            let normalized = Locale(identifier: device).identifier.replacingOccurrences(of: "_", with: "-")
            if !identifiers.contains(where: { $0.hasPrefix(String(normalized.prefix(2))) }) {
                identifiers.append(normalized)
            }
        }
        var result: [Channel] = []
        for id in identifiers {
            if let recognizer = SFSpeechRecognizer(locale: Locale(identifier: id)), recognizer.isAvailable {
                result.append(Channel(locale: id, recognizer: recognizer))
            }
        }
        if result.isEmpty, let fallback = SFSpeechRecognizer() {
            result.append(Channel(locale: "default", recognizer: fallback))
        }
        return result
    }
    
    /// リアルタイム音声認識＆叫び声リスニングの開始
    public func startListening() {
        guard isVoiceSyncEnabled else { return }
        guard !isListening else { return }
        
        // 権限確認 (iOS 17対応)
        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        let isAudioGranted: Bool
        if #available(iOS 17.0, *) {
            isAudioGranted = (AVAudioApplication.shared.recordPermission == .granted)
        } else {
            isAudioGranted = (AVAudioSession.sharedInstance().recordPermission == .granted)
        }
        
        guard speechStatus == .authorized, isAudioGranted else {
            requestPermissions { [weak self] granted in
                if granted {
                    self?.startListening()
                } else {
                    self?.statusMessage = "マイク・音声認識の権限が必要です"
                }
            }
            return
        }
        
        beginSession()
    }
    
    /// 認識セッションの開始（トークンを更新して古いコールバックを無効化）
    private func beginSession() {
        sessionToken += 1
        let token = sessionToken
        teardownRecognition()
        
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker, .allowBluetooth])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            
            // 古いフォーマットキャッシュによる "format mismatch" クラッシュを防ぐため、毎回新しいAVAudioEngineを生成
            let newEngine = AVAudioEngine()
            self.audioEngine = newEngine
            let inputNode = newEngine.inputNode
            
            // ハードウェア入力が有効かチェック（0Hzや0chの異常時はクラッシュさせず安全にスキップ）
            let hwFormat = inputNode.inputFormat(forBus: 0)
            guard hwFormat.sampleRate > 0, hwFormat.channelCount > 0 else {
                statusMessage = "マイク入力フォーマット待機中..."
                return
            }
            
            channels = makeChannels()
            for channel in channels {
                let request = SFSpeechAudioBufferRecognitionRequest()
                request.shouldReportPartialResults = true
                channel.request = request
                channel.latestText = ""
                channel.latestConfidence = 0
                channel.latestDate = .distantPast
                channel.task = channel.recognizer.recognitionTask(with: request) { [weak self, weak channel] result, error in
                    guard let self = self, let channel = channel, token == self.sessionToken else { return }
                    
                    if let result = result {
                        let transcription = result.bestTranscription
                        let segs = transcription.segments
                        let conf: Float = segs.isEmpty ? 0 : segs.map { $0.confidence }.reduce(0, +) / Float(segs.count)
                        DispatchQueue.main.async {
                            guard token == self.sessionToken else { return }
                            channel.latestText = transcription.formattedString
                            channel.latestConfidence = conf
                            channel.latestDate = Date()
                            self.evaluateChannels()
                        }
                    }
                    
                    if error != nil || (result?.isFinal ?? false) {
                        // 文末・タイムアウト時は新しいセッションで連続リスニングを維持
                        DispatchQueue.main.async {
                            guard token == self.sessionToken, self.isListening, self.isVoiceSyncEnabled else { return }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                guard token == self.sessionToken, self.isListening else { return }
                                self.restartSessionKeepingTimers()
                            }
                        }
                    }
                }
            }
            
            inputNode.removeTap(onBus: 0)
            // format に nil を渡すことで、48000Hz / 44100Hz など現在のハードウェアのネイティブフォーマットに自動一致させ、クラッシュを完全防止
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] (buffer: AVAudioPCMBuffer, when: AVAudioTime) in
                guard let self = self else { return }
                for channel in self.channels {
                    channel.request?.append(buffer)
                }
                self.analyzeAudioLevel(buffer: buffer)
            }
            
            newEngine.prepare()
            try newEngine.start()
            
            isListening = true
            statusMessage = "叫び声・音声を待機中..."
        } catch {
            statusMessage = "マイク開始エラー: \(error.localizedDescription)"
            stopListening()
        }
    }
    
    /// 認識タスクのみを破棄（タイマーは維持）
    private func teardownRecognition() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.reset()
        for channel in channels {
            channel.request?.endAudio()
            channel.request = nil
            channel.task?.cancel()
            channel.task = nil
        }
        channels = []
    }
    
    /// 無音リセットタイマーを保ったまま認識セッションだけ再起動
    private func restartSessionKeepingTimers() {
        guard isListening else { return }
        beginSession()
    }
    
    /// リアルタイム音声認識の停止
    public func stopListening() {
        sessionToken += 1 // 進行中コールバックを全て無効化
        resetTimer?.invalidate()
        resetTimer = nil
        shoutDebounceTimer?.invalidate()
        shoutDebounceTimer = nil
        
        teardownRecognition()
        
        isListening = false
        isShouting = false
        audioLevel = 0.0
        lastAppliedText = ""
        statusMessage = "停止中"
    }
    
    /// 各言語の認識結果から、信頼度とキーワード一致で最良の候補を選ぶ
    private func evaluateChannels() {
        let now = Date()
        var best: (text: String, score: Float)? = nil
        
        for channel in channels {
            guard now.timeIntervalSince(channel.latestDate) < 2.0 else { continue }
            let cleaned = cleanRescueText(channel.latestText.trimmingCharacters(in: .whitespacesAndNewlines))
            guard !cleaned.isEmpty else { continue }
            
            // 救難キーワード以外は「意味のある文字列」かつ一定の信頼度がある時だけ採用（環境音の誤認識対策）
            let isKeyword = isKnownRescueKeyword(cleaned)
            if !isKeyword {
                guard isMeaningfulText(cleaned), channel.latestConfidence >= 0.35 else { continue }
            }
            
            var score = channel.latestConfidence
            if isKeyword { score += 1.0 }
            // 信頼度がまだ無い途中結果は、新しいものを少し優遇
            score += Float(max(0, 1.0 - now.timeIntervalSince(channel.latestDate))) * 0.05
            
            if best == nil || score > best!.score {
                best = (cleaned, score)
            }
        }
        
        guard let chosen = best else { return }
        applyRecognized(chosen.text)
    }
    
    private func isKnownRescueKeyword(_ text: String) -> Bool {
        ["HELP", "SOS", "たすけて", "ココ", "OK"].contains(text)
    }
    
    /// 記号・長音「ー」・相づち（あ/え/ん/uh/um…）だけの結果や1文字だけの結果を除外
    private func isMeaningfulText(_ text: String) -> Bool {
        let fillers: Set<String> = ["あ", "え", "ん", "う", "お", "あー", "えー", "うー", "んー", "えっと", "あの", "uh", "um", "ah", "oh", "hm", "hmm", "the", "a"]
        if fillers.contains(text.lowercased()) { return false }
        let letters = text.filter { $0.isLetter || $0.isNumber }
        // 「ー」「ｰ」「〜」等は isLetter になる場合があるため除外してから数える
        let core = letters.filter { $0 != "ー" && $0 != "ｰ" && $0 != "っ" && $0 != "ッ" }
        return core.count >= 2
    }
    
    /// 認識結果をPOV文字へ反映し、無音リセットタイマーを再設定
    private func applyRecognized(_ cleaned: String) {
        recognizedText = cleaned
        statusMessage = "叫び声を検知: 「\(cleaned)」"
        
        if cleaned != lastAppliedText {
            lastAppliedText = cleaned
            onTextRecognized?(cleaned)
        }
        
        if autoResetToDefault {
            resetTimer?.invalidate()
            resetTimer = Timer.scheduledTimer(withTimeInterval: resetDelaySeconds, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                self.lastAppliedText = ""
                self.onResetRequested?()
                self.statusMessage = "待機中（元の文字に復帰）"
            }
        }
    }
    
    /// オーディオバッファから音量（RMS）を計算して叫び声を判定
    private func analyzeAudioLevel(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = UInt(buffer.frameLength)
        guard frameLength > 0 else { return }
        
        var sum: Float = 0.0
        for i in 0..<Int(frameLength) {
            let sample = channelData[i]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(frameLength))
        
        DispatchQueue.main.async {
            self.audioLevel = min(max(rms * 5.0, 0.0), 1.0)
            
            // 遭難時の「叫び声」しきい値判定（周囲の風音・衣擦れ音より大きな大声）
            if rms > 0.08 {
                self.consecutiveLoudCount += 1
                if self.consecutiveLoudCount >= 2 {
                    self.isShouting = true
                    self.shoutDebounceTimer?.invalidate()
                    self.shoutDebounceTimer = Timer.scheduledTimer(withTimeInterval: 1.2, repeats: false) { [weak self] _ in
                        self?.isShouting = false
                    }
                }
            } else {
                self.consecutiveLoudCount = max(self.consecutiveLoudCount - 1, 0)
            }
        }
    }
    
    /// 認識テキストをPOV表示に適した形に整形
    private func cleanRescueText(_ text: String) -> String {
        guard !text.isEmpty else { return "" }
        if useFullPhrase {
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.count > maxCharacters ? String(t.suffix(maxCharacters)) : t
        }
        // 直近の叫び（最後のフレーズ）を優先取得
        let components = text.components(separatedBy: CharacterSet(charactersIn: " 、。！？!?,\n"))
            .filter { !$0.isEmpty }
        
        guard let lastWord = components.last else { return text }
        
        let upper = lastWord.uppercased()
        
        // よく叫ばれる言葉の標準化
        if upper.contains("HELP") || upper.contains("ヘルプ") {
            return "HELP"
        }
        if upper.contains("SOS") || upper.contains("エスオーエス") {
            return "SOS"
        }
        if upper.contains("たすけて") || upper.contains("助けて") || upper.contains("タスケテ") {
            return "たすけて"
        }
        if upper.contains("ここ") || upper.contains("ココ") {
            return "ココ"
        }
        if upper.contains("OK") || upper.contains("オーケー") {
            return "OK"
        }
        
        // 文字数が長すぎる場合は空中POVで視認しやすいよう先頭5文字程度に制限
        if lastWord.count > 5 {
            return String(lastWord.prefix(5))
        }
        return lastWord
    }
}
