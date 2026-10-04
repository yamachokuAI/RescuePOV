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
    
    @State private var previousBrightness: CGFloat = 0.5
    @State private var slices: [[Bool]] = []
    @State private var showInitialGuide: Bool = true
    @State private var isTestFlash: Bool = false
    
    // 最大光量固定（実機テスト検証ベストの44px高輝度・隙間保証モデル）
    private let slitWidth: CGFloat = 44.0
    private let activeDotRatio: CGFloat = 0.80
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
            
            // CADisplayLink＋位置同期による高光量スリット残像キャンバス（往復両方向同期・端から端まで全発光）
            POVCanvasRepresentable(
                slices: slices,
                rawText: currentText,
                direction: direction,
                color: isTestFlash ? UIColor.white : color.uiColor,
                slitWidth: slitWidth,
                isDiagonal: false,
                activeDotRatio: activeDotRatio
            )
            .ignoresSafeArea()
            
            // テスト発光フラッシュオーバーレイ
            if isTestFlash {
                Color.white.ignoresSafeArea()
            }
            
            // 突入時の初期ガイド（振りを検知するかタップで即消去）
            if showInitialGuide && !motionDetector.isMotionActive {
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
            
            // 【操作UIオーバーレイ】
            // 携帯を頭上に掲げて振っている時は完全消灯（不透明度0.0）
            // 手元で水平にした時だけフワッと再表示
            VStack {
                // 上部バー
                HStack(spacing: 10) {
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
                    
                    // 文字クイック切替（ワンタップで即変更）
                    HStack(spacing: 6) {
                        ForEach(["HELP", "SOS", "OK"], id: \.self) { word in
                            Button(action: {
                                currentText = word
                                rebuildSlices()
                            }) {
                                Text(word)
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .background(Capsule().fill(currentText == word ? Color.red : Color(white: 0.2)))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // 点灯テストボタン
                    Button(action: {
                        flashScreen()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "lightbulb.fill")
                            Text("テスト点灯")
                        }
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.orange.opacity(0.85)))
                        .foregroundColor(.black)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 12)
                
                Spacer()
                
                // 水平時に現れるコントロールパネル
                VStack(spacing: 12) {
                    // 【疲労対策・振れ幅マルチモード セレクター】
                    VStack(alignment: .leading, spacing: 6) {
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
                        
                        Picker("振れ幅モード", selection: $motionDetector.selectedRangeMode) {
                            ForEach(POVDisplayRangeMode.allCases) { mode in
                                Text(mode.shortTitle).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        
                        Text(motionDetector.selectedRangeMode.description)
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.8))
                            .lineLimit(2)
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.cyan.opacity(0.12)))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.cyan.opacity(0.3), lineWidth: 1))
                    
                    Divider().background(Color.white.opacity(0.15))
                    
                    // 【電源ボタン誤押し対策カード】
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
                                        .font(.system(size: 9).bold())
                                        .foregroundColor(.green)
                                }
                            }
                            
                            Text("① iPhoneを【上下逆さま】（充電口を上）にして左右を握ると、サイドボタンに触れずに安全に振れます。（自動180度反転対応）\n② 設定 > アクセシビリティ >「アクセスガイド」をトリプルクリックで開始すると、サイドボタンをOSレベルで完全無効化できます。")
                                .font(.system(size: 9.5))
                                .foregroundColor(.white.opacity(0.85))
                                .lineSpacing(2)
                        }
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.orange.opacity(0.15)))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.orange.opacity(0.35), lineWidth: 1))
                    
                    Divider().background(Color.white.opacity(0.15))
                    
                    // 【叫び声音声リアルタイム同期設定カード】
                    VStack(alignment: .leading, spacing: 6) {
                        Toggle(isOn: $voiceService.isVoiceSyncEnabled) {
                            HStack(spacing: 6) {
                                Image(systemName: "mic.badge.waveform.fill")
                                    .foregroundColor(voiceService.isVoiceSyncEnabled ? .yellow : .gray)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("叫び声・音声リアルタイム文字反映")
                                        .font(.caption.bold())
                                        .foregroundColor(.white)
                                    Text(voiceService.isVoiceSyncEnabled ? "叫んだ声（HELP、たすけて等）で空中文字を自動上書き" : "オフ（選択した文字を固定表示）")
                                        .font(.system(size: 9))
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .tint(.yellow)
                        .onChange(of: voiceService.isVoiceSyncEnabled) { _, enabled in
                            if enabled {
                                voiceService.startListening()
                            } else {
                                voiceService.stopListening()
                                currentText = initialText
                                rebuildSlices()
                            }
                        }
                        
                        if voiceService.isVoiceSyncEnabled {
                            HStack {
                                Text("マイク状態: \(voiceService.statusMessage)")
                                    .font(.system(size: 9))
                                    .foregroundColor(.yellow.opacity(0.9))
                                Spacer()
                                if voiceService.isShouting {
                                    Text("🗣 大声を検知中")
                                        .font(.system(size: 9).bold())
                                        .foregroundColor(.red)
                                }
                            }
                        }
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.yellow.opacity(0.12)))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.yellow.opacity(0.3), lineWidth: 1))
                    
                    Divider().background(Color.white.opacity(0.15))
                    
                    // リアルタイムステータス ＆ 頭上同期モニター
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
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 18).fill(Color(white: 0.12, opacity: 0.94)))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
                .padding(.horizontal, 14)
                .padding(.bottom, 20)
            }
            .opacity(isControlsVisible ? 1.0 : 0.0)
            .animation(.easeInOut(duration: 0.22), value: isControlsVisible)
        }
        .contentShape(Rectangle())
        // 頭上に掲げてスイングしている間は画面タッチを完全無効化（がっしり握った時の誤タッチ防止）
        .allowsHitTesting(isControlsVisible || showInitialGuide)
        .onTapGesture {
            if showInitialGuide {
                withAnimation { showInitialGuide = false }
            } else {
                withAnimation(.easeInOut(duration: 0.2)) {
                    manualShowControls.toggle()
                }
            }
        }
        .statusBar(hidden: true)
        .onAppear {
            previousBrightness = UIScreen.main.brightness
            UIScreen.main.brightness = 1.0 // 常に最大光量
            UIApplication.shared.isIdleTimerDisabled = true
            
            rebuildSlices()
            motionDetector.start(direction: direction)
            
            // 音声認識サービスのリスニング開始＆コールバック登録（画面に余計な警報は一切出さず静かに文字反映）
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
        .onChange(of: motionDetector.activeRangeMode) { _, _ in
            rebuildSlices()
        }
        .onDisappear {
            UIScreen.main.brightness = previousBrightness
            UIApplication.shared.isIdleTimerDisabled = false
            motionDetector.stop()
            voiceService.stopListening()
            voiceService.onTextRecognized = nil
            voiceService.onResetRequested = nil
        }
    }
    
    private func rebuildSlices() {
        self.motionDetector.staticTextLength = max(1, currentText.count)
        let isCondensed = (motionDetector.activeRangeMode == .compactSnap)
        self.slices = BitmapGenerator.shared.generateSlices(
            text: currentText,
            direction: direction,
            targetSlices: isCondensed ? 24 : 36, // 30cm手首モード時は空間凝縮24スライス
            sliceResolution: 28,
            mirrorForViewer: mirrorForViewer,
            isCondensed: isCondensed
        )
    }
    
    private func flashScreen() {
        isTestFlash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.isTestFlash = false
        }
    }
}
