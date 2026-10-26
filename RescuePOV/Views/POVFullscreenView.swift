import SwiftUI

/// POV発光パターンプリセット
public enum POVPattern: String, CaseIterable, Identifiable {
    case sharpWide = "精細極太(推奨)"    // 実機テストで最も見やすかった黄金比（幅44px・隙間保証）
    case diagonalGiant = "対角線 特大"   // 画面対角線全長を活用
    case superBright = "超爆光"         // 遠距離・悪天候用最大光束
    case ultraSharp = "超精細シャープ"   // 至近距離・輪郭確認用
    
    public var id: String { rawValue }
    
    public var defaultSlitWidth: CGFloat {
        switch self {
        case .sharpWide: return 44.0
        case .diagonalGiant: return 42.0
        case .superBright: return 56.0
        case .ultraSharp: return 24.0
        }
    }
    
    public var isDiagonal: Bool {
        return self == .diagonalGiant
    }
    
    public var activeDotRatio: CGFloat {
        switch self {
        case .sharpWide: return 0.80 // 隙間20%確保で太スリットでもE文字の横棒がくっきり黒抜け！
        case .diagonalGiant: return 0.82
        case .superBright: return 0.76
        case .ultraSharp: return 0.86
        }
    }
    
    public var description: String {
        switch self {
        case .sharpWide: return "実機検証ベスト！左右抑え持ち最適化＆最大光量"
        case .diagonalGiant: return "画面対角線をフル活用して文字高さを最大化"
        case .superBright: return "遠距離・悪天候用の最大光束モデル"
        case .ultraSharp: return "EやPの隙間を精密に判別するモデル"
        }
    }
}

/// フルスクリーンPOV空中文字表示画面
public struct POVFullscreenView: View {
    @Environment(\.dismiss) private var dismiss
    public var onDismiss: (() -> Void)? = nil
    
    @State private var currentText: String
    private let initialText: String
    let direction: POVDirection
    let color: POVColor
    let mirrorForViewer: Bool
    
    @StateObject private var motionDetector = MotionDetector.shared
    @ObservedObject private var voiceService = VoiceRescueService.shared
    @ObservedObject private var cloudService = SupabaseCloudService.shared
    @ObservedObject private var locationService = LocationService.shared
    
    @State private var previousBrightness: CGFloat = 0.5
    @State private var slices: [[Bool]] = []
    @State private var showInitialGuide: Bool = true
    @State private var isTestFlash: Bool = false
    @State private var hasTriggeredEmergency: Bool = false
    @State private var isShowingTrainingSheet: Bool = false
    
    // 残像のボケ・箱化を防ぐための適正スリット幅（常に爆光90pxに固定）
    private let slitWidthSetting: CGFloat = 90.0
    private let activeDotRatio: CGFloat = 1.0
    @State private var manualShowControls: Bool = false
    
    /// 水平時、またはタップ時にのみコントロールUIを表示
    private var isControlsVisible: Bool {
        motionDetector.isDeviceHorizontal || manualShowControls
    }
    
    public init(
        text: String = "HELP",
        direction: POVDirection = .horizontal,
        color: POVColor = .white,
        mirrorForViewer: Bool = true,
        onDismiss: (() -> Void)? = nil
    ) {
        self._currentText = State(initialValue: text)
        self.initialText = text
        self.direction = direction
        self.color = color
        self.mirrorForViewer = mirrorForViewer
        self.onDismiss = onDismiss
    }
    
    public var body: some View {
        ZStack {
            // 背景黒（完全な漆黒）
            Color.black.ignoresSafeArea()
            
            // CADisplayLink＋位置同期による高光量スリット残像キャンバス
            POVCanvasRepresentable(
                slices: slices,
                rawText: currentText,
                direction: direction,
                color: isTestFlash ? UIColor.white : color.uiColor,
                slitWidth: slitWidthSetting,
                isDiagonal: false,
                activeDotRatio: activeDotRatio
            )
            .ignoresSafeArea()
            
            // 背景タップ専用透明レイヤー（コントロールパネルの裏側に配置）
            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .onTapGesture {
                    if showInitialGuide {
                        withAnimation { showInitialGuide = false }
                    } else {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            manualShowControls.toggle()
                        }
                    }
                }
            
            // テスト発光フラッシュオーバーレイ
            if isTestFlash {
                Color.white.ignoresSafeArea()
            }
            
            // 突入時の初期ガイド
            if showInitialGuide && !motionDetector.isMotionActive {
                initialGuideOverlay
                    .onTapGesture {
                        withAnimation { showInitialGuide = false }
                    }
            }
            
            // 操作UIオーバーレイ（コントロールパネル自身のタップを100%確実に処理）
            if isControlsVisible {
                controlsOverlay
            }
        }
        .statusBar(hidden: true)
        .sheet(isPresented: $isShowingTrainingSheet) {
            SamplingView()
        }
        .onAppear {
            setupOnAppear()
        }
        .onChange(of: motionDetector.isEmitting) { _, emitting in
            if emitting && !hasTriggeredEmergency {
                triggerEmergencyBroadcast()
            }
        }
        .onChange(of: motionDetector.activeRangeMode) { _, _ in
            rebuildSlices()
        }
        .onDisappear {
            cleanupOnDisappear()
        }
    }
    
    // MARK: - サブビュー分割（型推論タイムアウト防止）
    
    @ViewBuilder
    private var initialGuideOverlay: some View {
        VStack(spacing: 14) {
            Image(systemName: direction.iconName)
                .font(.system(size: 60, weight: .bold))
                .foregroundColor(.yellow)
            
            Text("【救難POVスタンバイ完了】")
                .font(.title2.bold())
                .foregroundColor(.white)
            
            Text("iPhoneの画面を相手に向け\n頭上で腕を左右に大きくしっかり振ってください！")
                .font(.headline)
                .multilineTextAlignment(.center)
                .foregroundColor(.white)
                .padding(.horizontal, 20)
            
            Text("表示文字: 「\(currentText)」")
                .font(.title3.bold())
                .foregroundColor(.red)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.white))
            
            Text("※振っている間は不要な光漏れを防ぐため全ボタンが自動消灯します。\n手元で水平に戻すと操作メニューが現れます。")
                .font(.caption2)
                .multilineTextAlignment(.center)
                .foregroundColor(.gray)
                .padding(.horizontal)
        }
        .padding(24)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color.black.opacity(0.92)))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.yellow.opacity(0.6), lineWidth: 2)
        )
        .padding(.horizontal, 24)
        .transition(.opacity.combined(with: .scale))
    }
    
    @ViewBuilder
    private var controlsOverlay: some View {
        VStack {
            topBarView
            Spacer()
        }
        .opacity(isControlsVisible ? 1.0 : 0.0)
        .animation(.easeInOut(duration: 0.22), value: isControlsVisible)
    }
    
    @ViewBuilder
    private var topBarView: some View {
        HStack {
            Button(action: {
                if let onDismiss = onDismiss {
                    onDismiss()
                } else {
                    dismiss()
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "xmark.circle.fill")
                    Text("戻る")
                }
                .font(.caption.bold())
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color(white: 0.25, opacity: 0.85)))
                .foregroundColor(.white)
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 12)
    }
    
    @ViewBuilder
    private var rangeModeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "figure.walk.motion")
                    .foregroundColor(.cyan)
                Text("疲労対応・振れ幅モード")
                    .font(.caption.bold())
                    .foregroundColor(.white)
                Spacer()
                Text(motionDetector.activeRangeMode.shortTitle)
                    .font(.system(size: 9.5).bold())
                    .foregroundColor(.cyan)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.cyan.opacity(0.2)))
            }
            
            // 振れ幅モード切替ボタン（確実に反応する高感度ボタン）
            HStack(spacing: 4) {
                ForEach(POVDisplayRangeMode.allCases) { mode in
                    Button(action: {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        motionDetector.selectedRangeMode = mode
                        rebuildSlices()
                    }) {
                        Text(mode.shortTitle)
                            .font(.system(size: 9.5, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(motionDetector.selectedRangeMode == mode ? Color.cyan : Color.white.opacity(0.12))
                            )
                            .foregroundColor(motionDetector.selectedRangeMode == mode ? .black : .white)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            Text(motionDetector.selectedRangeMode.description)
                .font(.system(size: 9))
                .foregroundColor(.white.opacity(0.8))
                .lineLimit(2)
            
            Divider().background(Color.white.opacity(0.15))
            
            // 文字間隔セレクター（確実に反応する高感度ボタン）
            HStack(spacing: 6) {
                Image(systemName: "sun.max.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.yellow)
                Text("AUTO BRIGHTNESS & SPACING ACTIVE")
                    .font(.system(size: 10).bold())
                    .foregroundColor(.yellow)
                Spacer()
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.cyan.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.cyan.opacity(0.3), lineWidth: 1))
    }
    
    // 削除: slitWidthButtonとletterSpacingButton
    
    @ViewBuilder
    private var safetyCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: motionDetector.isUpsideDown ? "arrow.up.and.down.circle.fill" : "hand.raised.slash.fill")
                .foregroundColor(motionDetector.isUpsideDown ? .green : .orange)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("電源ボタン誤押し対策（実機セーフティ）")
                        .font(.caption.bold())
                        .foregroundColor(.white)
                    Spacer()
                    if motionDetector.isUpsideDown {
                        Text("上下逆さま検知中 (180°自動正立)")
                            .font(.system(size: 9.5).bold())
                            .foregroundColor(.green)
                    }
                }
                
                Text("① iPhoneを【上下逆さま】（充電口を上）にして左右を握ると、サイドボタンに触れずに安全に振れます。\n② 設定 > アクセシビリティ >「アクセスガイド」をトリプルクリックで開始すると、サイドボタンをOSレベルで完全無効化できます。")
                    .font(.system(size: 9.5))
                    .foregroundColor(.white.opacity(0.85))
                    .lineSpacing(2)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.15)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.35), lineWidth: 1))
    }
    
    @ViewBuilder
    private var emailStatusCard: some View {
        HStack(spacing: 10) {
            Image(systemName: cloudService.isEmailSent ? "envelope.badge.shield.half.filled.fill" : (cloudService.isSyncing ? "arrow.triangle.2.circlepath" : "envelope.fill"))
                .font(.title3)
                .foregroundColor(cloudService.isEmailSent ? .green : (cloudService.isSyncing ? .yellow : .orange))
            
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(cloudService.isEmailSent ? "緊急SOSメール送信完了" : (cloudService.isSyncing ? "救難信号・メール発信中..." : "救難メール待機中"))
                        .font(.caption.bold())
                        .foregroundColor(.white)
                    Spacer()
                    if !cloudService.lastGeneratedPasscode.isEmpty {
                        Text("🔑 \(cloudService.lastGeneratedPasscode)")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .foregroundColor(.yellow)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.yellow.opacity(0.2)))
                    }
                }
                
                Text("通知先: \(cloudService.emergencyRecipientEmail.isEmpty ? cloudService.senderGmail + " (未登録のため本人控え)" : cloudService.emergencyRecipientEmail)（暗号合鍵付きGPS地図リンク送信済み）")
                    .font(.system(size: 9))
                    .foregroundColor(.white.opacity(0.75))
                    .lineLimit(1)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.red.opacity(0.15)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.red.opacity(0.35), lineWidth: 1))
    }
    
    @ViewBuilder
    private var motionMonitorCard: some View {
        VStack(spacing: 4) {
            HStack {
                Circle()
                    .fill(motionDetector.isEmitting ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
                
                Text(motionDetector.isEmitting ? "往復同期発光中" : "端部減速・消灯中")
                    .font(.caption2.bold())
                    .foregroundColor(.white.opacity(0.9))
                
                Spacer()
                
                if motionDetector.isRealtimeOverheadSync {
                    Text("頭上リアルタイム同期中⚡️")
                        .font(.system(size: 9).bold())
                        .foregroundColor(.yellow)
                }
            }
            
            HStack {
                Text(String(format: "往復時間(Y): %.2fs ｜ 周波数: %.1fHz", motionDetector.roundTripDuration, motionDetector.swingFrequencyHz))
                    .font(.system(size: 9.5).monospacedDigit().bold())
                    .foregroundColor(.cyan)
                Spacer()
                Text(String(format: "振れ幅(X): %.0f° (位置: %.0f%%)", motionDetector.strokeAngleRange, motionDetector.strokeProgress * 100.0))
                    .font(.system(size: 9.5).monospacedDigit())
                    .foregroundColor(.green)
            }
        }
    }
    
    @ViewBuilder
    private var trainingButton: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            isShowingTrainingSheet = true
        }) {
            HStack(spacing: 6) {
                Image(systemName: "waveform.path.ecg")
                Text("スイング同期練習モード（光の玉＆全画面パルス）")
                    .font(.caption.bold())
            }
            .foregroundColor(.cyan)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.cyan.opacity(0.15)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.cyan.opacity(0.3), lineWidth: 1))
        }
    }
    
    @ViewBuilder
    private var bottomControlPanel: some View {
        VStack(spacing: 12) {
            rangeModeCard
            Divider().background(Color.white.opacity(0.15))
            safetyCard
            Divider().background(Color.white.opacity(0.15))
            emailStatusCard
            Divider().background(Color.white.opacity(0.15))
            motionMonitorCard
            Divider().background(Color.white.opacity(0.15))
            trainingButton
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(white: 0.12, opacity: 0.94)))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .padding(.horizontal, 14)
        .padding(.bottom, 20)
    }
    
    private func setupOnAppear() {
        previousBrightness = UIScreen.main.brightness
        UIScreen.main.brightness = 1.0 // 常に最大光量
        UIApplication.shared.isIdleTimerDisabled = true
        
        rebuildSlices()
        motionDetector.start(direction: direction)
        
        // GPS位置情報のリクエスト
        locationService.requestLocation()
        
        // SOS発信＆Gmail自動送信のトリガー
        triggerEmergencyBroadcast()
        
        // 遠隔からの救難文字書き換え（Webダッシュボードから被災者に届くメッセージ）の監視開始
        cloudService.startListeningRemoteCommands()
        cloudService.onRemoteTextReceived = { newText, _ in
            DispatchQueue.main.async {
                self.currentText = newText
                self.rebuildSlices()
            }
        }
        
        // 音声認識サービスのリスニング開始＆コールバック登録
        voiceService.onTextRecognized = { recognized in
            self.currentText = recognized
            self.rebuildSlices()
        }
        
        voiceService.onResetRequested = {
            self.currentText = self.initialText
            self.rebuildSlices()
        }
        
        if voiceService.isVoiceSyncEnabled {
            voiceService.startListening()
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.easeOut(duration: 0.3)) {
                self.showInitialGuide = false
            }
        }
    }
    
    private func cleanupOnDisappear() {
        UIScreen.main.brightness = previousBrightness
        UIApplication.shared.isIdleTimerDisabled = false
        motionDetector.stop()
        voiceService.stopListening()
        voiceService.onTextRecognized = nil
        voiceService.onResetRequested = nil
        cloudService.stopListeningRemoteCommands()
        cloudService.onRemoteTextReceived = nil
    }
    
    /// 緊急救難信号をSupabaseに発信し、登録Gmail宛てにリアルタイム地図＋パスコード付きSOSメールを自動配信
    private func triggerEmergencyBroadcast() {
        guard !hasTriggeredEmergency else { return }
        hasTriggeredEmergency = true
        
        cloudService.publishRescueEvent(
            latitude: locationService.latitude,
            longitude: locationService.longitude,
            altitude: locationService.altitude,
            situation: HybridIntelligenceEngine.shared.currentSituation.rawValue,
            targetText: currentText,
            color: color.rawValue,
            batteryLevel: Int(UIDevice.current.batteryLevel * 100)
        )
    }
    
    private func rebuildSlices() {
        self.motionDetector.staticTextLength = max(1, currentText.count)
        // AI自動モードで勝手に文字が細く（暗く）なるのを防ぎ、明示的に手首モードを選んだ時のみ凝縮する
        let isCondensed = (motionDetector.selectedRangeMode == .compactSnap)
        self.slices = BitmapGenerator.shared.generateSlices(
            text: currentText,
            direction: direction,
            targetSlices: isCondensed ? 20 : 32,
            sliceResolution: 28,
            mirrorForViewer: mirrorForViewer,
            isCondensed: isCondensed,
            edgeMargin: 0
        )
    }
    
    private func flashScreen() {
        isTestFlash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.isTestFlash = false
        }
    }
}
