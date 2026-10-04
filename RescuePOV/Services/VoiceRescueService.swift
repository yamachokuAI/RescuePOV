import Foundation
import Speech
import AVFoundation
import Combine

/// 叫び声・音声認識によりPOV文字をリアルタイムに上書き更新するサービス
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
    
    @Published public var resetDelaySeconds: Double = 6.0 {
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
    
    // コールバック: 新しい叫び声/音声が認識された時、呼び出し元に通知
    public var onTextRecognized: ((String) -> Void)?
    // コールバック: 自動リセット時間経過時に元の文字へ戻す通知
    public var onResetRequested: (() -> Void)?
    
    private var audioEngine = AVAudioEngine()
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    
    private var resetTimer: Timer?
    private var shoutDebounceTimer: Timer?
    private var consecutiveLoudCount: Int = 0
    
    private init() {
        // 設定読み込み
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
        
        // 日本語環境を第一優先、不可なら英語または端末デフォルト
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP")) ?? SFSpeechRecognizer()
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
    
    /// リアルタイム音声認識＆叫び声リスニングの開始
    public func startListening() {
        guard isVoiceSyncEnabled else { return }
        guard !isListening else { return }
        
        // 既存タスクの確実なクリーンアップ
        stopListening()
        
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
        
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
            
            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            guard let recognitionRequest = recognitionRequest else {
                statusMessage = "音声認識リクエストの作成に失敗しました"
                return
            }
            recognitionRequest.shouldReportPartialResults = true
            
            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            
            inputNode.removeTap(onBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] (buffer: AVAudioPCMBuffer, when: AVAudioTime) in
                guard let self = self else { return }
                self.recognitionRequest?.append(buffer)
                self.analyzeAudioLevel(buffer: buffer)
            }
            
            audioEngine.prepare()
            try audioEngine.start()
            
            isListening = true
            statusMessage = "叫び声・音声を待機中..."
            
            recognitionTask = speechRecognizer?.recognitionTask(with: recognitionRequest) { [weak self] result, error in
                guard let self = self else { return }
                
                if let result = result {
                    let transcribedString = result.bestTranscription.formattedString
                    self.processTranscribedText(transcribedString)
                }
                
                if error != nil || (result?.isFinal ?? false) {
                    // エラーまたは文末時に自動再開（連続リスニングを維持）
                    if self.isListening && self.isVoiceSyncEnabled {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            if self.isListening {
                                self.restartListeningSilently()
                            }
                        }
                    }
                }
            }
        } catch {
            statusMessage = "マイク開始エラー: \(error.localizedDescription)"
            stopListening()
        }
    }
    
    /// リアルタイム音声認識の停止
    public func stopListening() {
        resetTimer?.invalidate()
        resetTimer = nil
        shoutDebounceTimer?.invalidate()
        shoutDebounceTimer = nil
        
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        
        isListening = false
        isShouting = false
        audioLevel = 0.0
        statusMessage = "停止中"
    }
    
    /// 音声認識タスクを静かに再起動して連続リスニングを維持
    private func restartListeningSilently() {
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isListening = false
        
        startListening()
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
    
    /// 認識されたテキストを整理してPOV用テキストに変換
    private func processTranscribedText(_ rawText: String) {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        
        // 救難で叫ばれる代表的な単語の正規化・強調
        let cleaned = cleanRescueText(trimmed)
        guard !cleaned.isEmpty else { return }
        
        DispatchQueue.main.async {
            self.recognizedText = cleaned
            self.statusMessage = "叫び声を検知: 「\(cleaned)」"
            
            // コールバック通知（リアルタイムに文字反映）
            self.onTextRecognized?(cleaned)
            
            // 自動復帰タイマーのセット（叫び声が止んだ後に元の文字に戻す設定の場合）
            if self.autoResetToDefault {
                self.resetTimer?.invalidate()
                self.resetTimer = Timer.scheduledTimer(withTimeInterval: self.resetDelaySeconds, repeats: false) { [weak self] _ in
                    self?.onResetRequested?()
                    self?.statusMessage = "待機中（元の文字に復帰）"
                }
            }
        }
    }
    
    /// 認識テキストをPOV表示に適した形に整形
    private func cleanRescueText(_ text: String) -> String {
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
        
        // 文字数が長すぎる場合は空中POVで視認しやすいよう先頭4〜5文字程度に制限
        if lastWord.count > 5 {
            return String(lastWord.prefix(5))
        }
        return lastWord
    }
}
