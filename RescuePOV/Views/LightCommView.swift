import SwiftUI
import AVFoundation

/// 背面LEDフラッシュによる光通信トランシーバー画面（送信＝トーチ点滅 / 受信＝カメラ復調）
public struct LightCommView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var tx = LightCommTransmitter.shared
    @ObservedObject private var rx = LightCommReceiver.shared
    @ObservedObject private var voice = VoiceRescueService.shared
    
    private enum Mode: String, CaseIterable, Identifiable {
        case send, receive
        var id: String { rawValue }
    }
    
    private enum SendKind: String, CaseIterable, Identifiable {
        case preset, freeText
        var id: String { rawValue }
    }
    
    @State private var mode: Mode = .send
    @State private var sendKind: SendKind = .preset
    @State private var selectedWord: LightCommWord = LightCommCodec.words[0]
    
    // 自由文字
    @State private var freeText: String = "HELP"
    @State private var baseText: String = "HELP"
    @State private var isVoiceInputOn: Bool = false
    @State private var voiceDebounce: DispatchWorkItem? = nil
    @FocusState private var isTextFocused: Bool
    
    public init() {}
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    modePicker
                    if mode == .send {
                        sendSection
                    } else {
                        receiveSection
                    }
                    protocolNote
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.black.ignoresSafeArea())
            .navigationTitle(L.pick("光通信トランシーバー", "Light Comm"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(L.t("閉じる")) {
                        stopAll()
                        dismiss()
                    }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button(L.t("完了")) { isTextFocused = false }
                        .fontWeight(.bold)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onDisappear { stopAll() }
    }
    
    private func stopAll() {
        stopVoiceInput()
        tx.stop()
        rx.stop()
    }
    
    // MARK: - モード切替
    @ViewBuilder
    private var modePicker: some View {
        Picker("", selection: $mode) {
            Text(L.pick("送信（ライト点滅）", "Send (flash)")).tag(Mode.send)
            Text(L.pick("受信（カメラ）", "Receive (camera)")).tag(Mode.receive)
        }
        .pickerStyle(.segmented)
        .onChange(of: mode) { _, newMode in
            stopAll()
            if newMode == .receive { rx.start() }
        }
    }
    
    // MARK: - 送信
    @ViewBuilder
    private var sendSection: some View {
        VStack(spacing: 14) {
            Picker("", selection: $sendKind) {
                Text(L.pick("定型語（速い・確実）", "Preset words")).tag(SendKind.preset)
                Text(L.pick("自由文字・音声", "Free text / voice")).tag(SendKind.freeText)
            }
            .pickerStyle(.segmented)
            .onChange(of: sendKind) { _, _ in
                stopVoiceInput()
                tx.stop()
            }
            
            if sendKind == .preset {
                presetSendSection
            } else {
                freeTextSendSection
            }
        }
    }
    
    @ViewBuilder
    private var presetSendSection: some View {
        VStack(spacing: 14) {
            Text(L.pick("送る言葉を選んでください", "Choose a message to send"))
                .font(.subheadline.bold())
                .foregroundColor(.white.opacity(0.85))
                .frame(maxWidth: .infinity, alignment: .leading)
            
            wordGrid
            sendStatusCard
            presetSendButton
        }
    }
    
    @ViewBuilder
    private var wordGrid: some View {
        let columns = [GridItem(.adaptive(minimum: 104), spacing: 8)]
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(LightCommCodec.words) { word in
                wordChip(word)
            }
        }
    }
    
    @ViewBuilder
    private func wordChip(_ word: LightCommWord) -> some View {
        let isSelected = (word == selectedWord)
        let fill = isSelected ? Color.cyan.opacity(0.4) : Color.white.opacity(0.08)
        let stroke = isSelected ? Color.white : Color.white.opacity(0.2)
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            selectedWord = word
            if tx.isSending { tx.start(word: word) }
        }) {
            VStack(spacing: 2) {
                Text(word.en)
                    .font(.system(size: 12, weight: .black, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(word.ja)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(stroke, lineWidth: isSelected ? 1.6 : 0.8))
            .foregroundColor(.white)
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private var presetSendButton: some View {
        let sending = tx.isSending
        Button(action: {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            if sending { tx.stop() } else { tx.start(word: selectedWord) }
        }) {
            sendButtonLabel(sending: sending)
        }
    }
    
    @ViewBuilder
    private func sendButtonLabel(sending: Bool) -> some View {
        HStack {
            Image(systemName: sending ? "stop.circle.fill" : "flashlight.on.fill")
            Text(sending ? L.pick("送信を停止", "Stop") : L.pick("背面ライトで送信開始", "Start sending with torch"))
        }
        .font(.headline.bold())
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 14).fill(sending ? Color.red : Color.orange))
        .foregroundColor(.white)
    }
    
    // MARK: 自由文字送信
    @ViewBuilder
    private var freeTextSendSection: some View {
        VStack(spacing: 14) {
            freeTextField
            freeTextInfo
            voiceInputRow
            sendStatusCard
            freeTextSendButton
        }
    }
    
    @ViewBuilder
    private var freeTextField: some View {
        HStack(spacing: 8) {
            Image(systemName: "pencil.and.outline")
                .foregroundColor(.cyan)
            TextField(L.pick("送りたい文字（英数字・ひらがな推奨）", "Text to send"), text: $freeText)
                .focused($isTextFocused)
                .submitLabel(.send)
                .font(.system(size: 17, weight: .bold, design: .monospaced))
                .onSubmit {
                    isTextFocused = false
                    baseText = freeText
                    if tx.isSending { tx.start(text: freeText) }
                }
            if !freeText.isEmpty {
                Button(action: { freeText = "" }) {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.white.opacity(0.5))
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.12)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.cyan.opacity(0.4), lineWidth: 1))
    }
    
    @ViewBuilder
    private var freeTextInfo: some View {
        let trimmed = freeText.trimmingCharacters(in: .whitespacesAndNewlines)
        let sent = LightCommCodec.transmittedText(trimmed)
        let bits = trimmed.isEmpty ? 0 : LightCommCodec.textFrame(trimmed).count
        let seconds = Double(bits) * LightCommCodec.textBitDuration
        VStack(alignment: .leading, spacing: 3) {
            Text(L.pick("実際に送る文字: 「\(sent)」", "Will send: \"\(sent)\""))
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(.white.opacity(0.9))
            Text(L.pick("1周 約\(Int(seconds.rounded()))秒（長い文ほど時間がかかります・最大約24シンボル）。カタカナはひらがなに、漢字は長くなります。", "About \(Int(seconds.rounded())) s per cycle. Longer text takes longer."))
                .font(.system(size: 10))
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    @ViewBuilder
    private var voiceInputRow: some View {
        Button(action: toggleVoiceInput) {
            HStack(spacing: 8) {
                Image(systemName: isVoiceInputOn ? "mic.fill" : "mic.slash")
                VStack(alignment: .leading, spacing: 2) {
                    Text(isVoiceInputOn ? L.pick("音声入力 ON（話すと自動で送信文字に反映）", "Voice input ON") : L.pick("音声入力 OFF（タップで開始）", "Voice input OFF (tap)"))
                        .font(.system(size: 13, weight: .bold))
                    Text(L.pick("5秒間話さないと元の文字（\(baseText)）に戻ります", "Returns to \"\(baseText)\" after 5 s of silence"))
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.7))
                }
                Spacer()
                if isVoiceInputOn {
                    voiceLevelBar
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 14).fill(isVoiceInputOn ? Color.red.opacity(0.35) : Color.white.opacity(0.08)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(isVoiceInputOn ? Color.red : Color.white.opacity(0.2), lineWidth: 1.2))
            .foregroundColor(.white)
        }
        .buttonStyle(.plain)
    }
    
    @ViewBuilder
    private var voiceLevelBar: some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Color.white.opacity(0.15)).frame(width: 46, height: 6)
            Capsule().fill(Color.green).frame(width: 46 * CGFloat(voice.audioLevel), height: 6)
        }
    }
    
    @ViewBuilder
    private var freeTextSendButton: some View {
        let sending = tx.isSending
        Button(action: {
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
            isTextFocused = false
            if sending {
                tx.stop()
            } else {
                baseText = freeText
                tx.start(text: freeText)
            }
        }) {
            sendButtonLabel(sending: sending)
        }
    }
    
    // MARK: 音声入力（リアルタイム文字化→光通信、5秒無音で元の語句へ）
    private func toggleVoiceInput() {
        if isVoiceInputOn { stopVoiceInput() } else { startVoiceInput() }
    }
    
    private func startVoiceInput() {
        isTextFocused = false
        baseText = freeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "HELP" : freeText
        voice.isVoiceSyncEnabled = true
        voice.useFullPhrase = true
        voice.maxCharacters = 16
        voice.resetDelaySeconds = 5.0
        voice.autoResetToDefault = true
        
        voice.onTextRecognized = { recognized in
            freeText = recognized
            // 話している途中で毎回送信し直さず、認識が1.2秒安定してから送信に反映
            voiceDebounce?.cancel()
            let work = DispatchWorkItem {
                if isVoiceInputOn { tx.start(text: recognized) }
            }
            voiceDebounce = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
        }
        voice.onResetRequested = {
            voiceDebounce?.cancel()
            freeText = baseText
            if isVoiceInputOn { tx.start(text: baseText) }
        }
        
        isVoiceInputOn = true
        if !tx.isSending { tx.start(text: baseText) }
        voice.startListening()
    }
    
    private func stopVoiceInput() {
        guard isVoiceInputOn else { return }
        isVoiceInputOn = false
        voiceDebounce?.cancel()
        voice.onTextRecognized = nil
        voice.onResetRequested = nil
        voice.stopListening()
        voice.useFullPhrase = false
    }
    
    // MARK: - 共通: 送信状況
    @ViewBuilder
    private var bitIndicatorRow: some View {
        let bits = currentFrameBits
        HStack(spacing: 1) {
            ForEach(0..<bits.count, id: \.self) { i in
                bitCell(index: i, value: bits[i], count: bits.count)
            }
        }
    }
    
    private var currentFrameBits: [Bool] {
        if sendKind == .preset {
            return LightCommCodec.frame(for: selectedWord.id)
        }
        let trimmed = freeText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? [] : LightCommCodec.textFrame(trimmed)
    }
    
    @ViewBuilder
    private func bitCell(index: Int, value: Bool, count: Int) -> some View {
        let isCurrent = tx.isSending && tx.currentBitIndex == index
        let isPreamble = index < LightCommCodec.preamble.count
        let base: Color = isPreamble ? .orange : .cyan
        let h: CGFloat = count > 40 ? 12 : 18
        RoundedRectangle(cornerRadius: 2)
            .fill(value ? base.opacity(0.85) : base.opacity(0.15))
            .frame(height: h)
            .overlay(RoundedRectangle(cornerRadius: 2).stroke(isCurrent ? Color.white : Color.clear, lineWidth: 1.5))
    }
    
    @ViewBuilder
    private var sendStatusCard: some View {
        VStack(spacing: 8) {
            HStack {
                Circle()
                    .fill(tx.currentBitOn ? Color.yellow : Color.gray.opacity(0.4))
                    .frame(width: 18, height: 18)
                    .shadow(color: tx.currentBitOn ? .yellow : .clear, radius: 8)
                Text(tx.isSending
                     ? L.pick("送信中: \(tx.sendingLabel)（\(tx.sentFrames)周送信）", "Sending: \(tx.sendingLabel) (\(tx.sentFrames) cycles)")
                     : L.pick("待機中", "Idle"))
                    .font(.footnote.bold())
                    .lineLimit(1)
                Spacer()
            }
            bitIndicatorRow
            HStack {
                Text(L.pick("橙=プリアンブル ／ 水色=データ＋ハミングパリティ", "Orange = preamble / Cyan = data + Hamming parity"))
                    .font(.system(size: 9))
                    .foregroundColor(.gray)
                Spacer()
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.10)))
    }
    
    // MARK: - 受信
    @ViewBuilder
    private var receiveSection: some View {
        VStack(spacing: 14) {
            decodedCard
            cameraPreviewCard
            sensitivityCard
            waveformCard
            receiveStatusCard
            receiveControlButton
        }
    }
    
    @ViewBuilder
    private var decodedCard: some View {
        VStack(spacing: 6) {
            if let t = rx.decodedText {
                Text(t.text)
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .foregroundColor(.green)
                    .minimumScaleFactor(0.4)
                    .lineLimit(2)
                Text(L.pick("自由文字を受信（\(t.repeats)周）", "Free text received (\(t.repeats) cycles)"))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.7))
            } else if let result = rx.decoded {
                Text(result.word.localized)
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundColor(.green)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                Text("[\(result.word.en)]  ID \(result.word.id)")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7))
            } else {
                Text(L.pick("— 受信待ち —", "— waiting —"))
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.4))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(white: 0.10)))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke((rx.decoded == nil && rx.decodedText == nil) ? Color.white.opacity(0.1) : Color.green.opacity(0.7), lineWidth: 1.4))
    }
    
    @ViewBuilder
    private var cameraPreviewCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L.pick("カメラ映像（黄色い枠の中の一番明るい点を読み取ります）", "Camera (the brightest spot inside the yellow box is measured)"))
                .font(.caption2.bold())
                .foregroundColor(.cyan)
            ZStack {
                CameraPreviewView(session: rx.session)
                    .aspectRatio(3.0 / 4.0, contentMode: .fit)
                    .frame(maxHeight: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                roiOverlay
            }
            .frame(maxWidth: .infinity)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.08)))
    }
    
    @ViewBuilder
    private var roiOverlay: some View {
        GeometryReader { geo in
            let w = min(geo.size.width, geo.size.height * 0.75)
            let h = w / 0.75
            Rectangle()
                .stroke(Color.yellow, lineWidth: 2)
                .frame(width: w * 0.5, height: h * 0.5)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .frame(maxHeight: 280)
        .allowsHitTesting(false)
    }
    
    @ViewBuilder
    private var sensitivityCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L.pick("受光感度", "Sensitivity"))
                    .font(.caption.bold())
                    .foregroundColor(.white)
                Spacer()
                Text(String(format: "明るさ %.2f", rx.currentLevel))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.yellow)
            }
            Slider(value: $rx.sensitivity, in: 0...1)
                .tint(.cyan)
            Text(L.pick("相手が点灯した時に波形がほぼ1.0に張り付く→下げる／消灯時でも高いまま→下げる／点灯しても低い→上げる。点灯と消灯で波形が大きく上下するのが目標です。", "Goal: the waveform should swing widely between on and off. Lower it if it stays saturated, raise it if on-state is too dim."))
                .font(.system(size: 10))
                .foregroundColor(.gray)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.10)))
    }
    
    @ViewBuilder
    private var waveformCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L.pick("受光波形（黄線=しきい値）", "Received waveform (yellow = threshold)"))
                .font(.caption2.bold())
                .foregroundColor(.cyan)
            LightWaveformView(levels: rx.recentLevels, threshold: rx.threshold)
                .frame(height: 90)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.08)))
    }
    
    @ViewBuilder
    private var receiveStatusCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(rx.statusMessage)
                .font(.footnote.bold())
                .foregroundColor(.white)
            Text(String(format: "コントラスト %.2f（0.10以上が必要）", rx.contrast))
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(white: 0.10)))
    }
    
    @ViewBuilder
    private var receiveControlButton: some View {
        Button(action: {
            if rx.isRunning { rx.stop() } else { rx.start() }
        }) {
            HStack {
                Image(systemName: rx.isRunning ? "stop.circle.fill" : "camera.viewfinder")
                Text(rx.isRunning ? L.pick("受信を停止", "Stop receiving") : L.pick("カメラ受信を開始", "Start receiving"))
            }
            .font(.headline.bold())
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 14).fill(rx.isRunning ? Color.red : Color.blue))
            .foregroundColor(.white)
        }
    }
    
    // MARK: - 説明
    @ViewBuilder
    private var protocolNote: some View {
        Text(L.pick(
            "光通信は背面LEDの点滅だけで送ります（遠距離向け）。定型語は英単語IDの共通言語で、受信側が端末の言語に翻訳して表示します。自由文字はそのまま送ります。どちらも誤り訂正（ハミング）＋連送の多数決で、欠けた点滅を補います。\n\n【Mac実験】Macで http://localhost:8000/mac_lightcomm.html を開くと、画面点滅での送信／Webカメラでの受信を試せます。",
            "Messages are sent only by the rear LED flash (long range). Preset words use a common English ID translated on the receiver; free text is sent as is. Both use Hamming error correction and repeated-frame voting.\n\n[Mac test] Open http://localhost:8000/mac_lightcomm.html on a Mac to send via screen flash / receive via webcam."))
            .font(.system(size: 10.5))
            .foregroundColor(.white.opacity(0.55))
            .lineSpacing(3)
            .padding(.top, 4)
    }
}

/// 受光した明るさの波形グラフ
struct LightWaveformView: View {
    let levels: [Double]
    let threshold: Double
    
    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height
            let ty = h - CGFloat(threshold) * h
            var th = Path()
            th.move(to: CGPoint(x: 0, y: ty))
            th.addLine(to: CGPoint(x: w, y: ty))
            ctx.stroke(th, with: .color(.yellow.opacity(0.8)), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            
            guard levels.count > 1 else { return }
            var path = Path()
            for (i, v) in levels.enumerated() {
                let x = w * CGFloat(i) / CGFloat(max(levels.count - 1, 1))
                let y = h - CGFloat(min(max(v, 0), 1)) * h
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            ctx.stroke(path, with: .color(.cyan), lineWidth: 1.6)
        }
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black))
    }
}

/// 受信用カメラのプレビュー表示
struct CameraPreviewView: UIViewRepresentable {
    let session: AVCaptureSession
    
    final class PreviewUIView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
    
    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.backgroundColor = .black
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }
    
    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        uiView.previewLayer.session = session
    }
}
