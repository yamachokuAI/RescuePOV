import SwiftUI

/// POV発光パターンプリセット
public enum POVPattern: String, CaseIterable, Identifiable {
    case balanced = "バランス(推奨)"
    case diagonalGiant = "対角線 特大"
    case superBright = "超爆光"
    case sharp = "精細シャープ"
    
    public var id: String { rawValue }
    
    public var defaultSlitWidth: CGFloat {
        switch self {
        case .balanced: return 32.0
        case .diagonalGiant: return 38.0
        case .superBright: return 55.0
        case .sharp: return 20.0
        }
    }
    
    public var isDiagonal: Bool {
        return self == .diagonalGiant
    }
    
    public var activeDotRatio: CGFloat {
        switch self {
        case .balanced: return 0.82
        case .diagonalGiant: return 0.82
        case .superBright: return 0.78
        case .sharp: return 0.86
        }
    }
    
    public var description: String {
        switch self {
        case .balanced: return "光量と文字のシャープさの最適バランス"
        case .diagonalGiant: return "画面対角線をフル活用して文字高さを最大化"
        case .superBright: return "遠距離・悪天候用の最大光束モデル"
        case .sharp: return "EやPの隙間を確実に判別する精細モデル"
        }
    }
}

/// フルスクリーンPOV空中文字表示画面
public struct POVFullscreenView: View {
    @Environment(\.dismiss) private var dismiss
    public var onDismiss: (() -> Void)? = nil
    
    @State private var currentText: String
    let direction: POVDirection
    let color: POVColor
    let mirrorForViewer: Bool
    
    @StateObject private var motionDetector = MotionDetector.shared
    
    @State private var previousBrightness: CGFloat = 0.5
    @State private var slices: [[Bool]] = []
    @State private var showInitialGuide: Bool = true
    @State private var isTestFlash: Bool = false
    
    // 表示パラメータ（パターン連動）
    @State private var selectedPattern: POVPattern = .balanced
    @State private var slitWidth: CGFloat = 32.0
    @State private var isDiagonal: Bool = false
    @State private var activeDotRatio: CGFloat = 0.82
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
        self.direction = direction
        self.color = color
        self.mirrorForViewer = mirrorForViewer
        self.onDismiss = onDismiss
    }
    
    public var body: some View {
        ZStack {
            // 背景黒（完全な漆黒）
            Color.black.ignoresSafeArea()
            
            // CADisplayLink＋位置同期による高光量スリット残像キャンバス（往復両方向同期）
            POVCanvasRepresentable(
                slices: slices,
                direction: direction,
                color: isTestFlash ? UIColor.white : color.uiColor,
                slitWidth: slitWidth,
                isDiagonal: isDiagonal,
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
                    // パターン選択セグメント
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("表示パターン（4種類）")
                                .font(.caption.bold())
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(selectedPattern.description)
                                .font(.caption2)
                                .foregroundColor(.yellow)
                        }
                        
                        Picker("パターン", selection: $selectedPattern) {
                            ForEach(POVPattern.allCases) { pat in
                                Text(pat.rawValue).tag(pat)
                            }
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: selectedPattern) { newPattern in
                            applyPattern(newPattern)
                        }
                    }
                    
                    Divider().background(Color.white.opacity(0.15))
                    
                    // スリット幅微調整
                    HStack {
                        Image(systemName: "sun.max.fill")
                            .foregroundColor(.yellow)
                        Text("スリット幅・光量微調整")
                            .font(.caption.bold())
                            .foregroundColor(.white)
                        Spacer()
                        Text(String(format: "%.0f px", slitWidth))
                            .font(.caption.monospacedDigit().bold())
                            .foregroundColor(.yellow)
                    }
                    
                    Slider(value: $slitWidth, in: 12...120, step: 2)
                        .tint(.yellow)
                    
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.left.arrow.right")
                            .foregroundColor(.cyan)
                        Text("左右両方向（往路・復路）完全同期発光中 ｜ 掲げると全UI自動消灯")
                            .font(.system(size: 10))
                            .foregroundColor(.white.opacity(0.85))
                    }
                    
                    Divider().background(Color.white.opacity(0.15))
                    
                    // リアルタイムステータス
                    HStack {
                        Circle()
                            .fill(motionDetector.isEmitting ? Color.green : Color.gray)
                            .frame(width: 8, height: 8)
                        
                        Text(motionDetector.isEmitting ? "往復同期発光中" : "端部減速・消灯中")
                            .font(.caption2.bold())
                            .foregroundColor(.white.opacity(0.9))
                        
                        Spacer()
                        
                        Text(String(format: "位置: %.0f%% (振れ幅: %.0f° / 速度: %.1f)", motionDetector.strokeProgress * 100.0, motionDetector.strokeAngleRange, motionDetector.swingIntensity))
                            .font(.caption2.monospacedDigit())
                            .foregroundColor(.green)
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
            
            applyPattern(selectedPattern)
            rebuildSlices()
            motionDetector.start(direction: direction)
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                withAnimation(.easeOut(duration: 0.3)) {
                    self.showInitialGuide = false
                }
            }
        }
        .onDisappear {
            UIScreen.main.brightness = previousBrightness
            UIApplication.shared.isIdleTimerDisabled = false
            motionDetector.stop()
        }
    }
    
    private func applyPattern(_ pattern: POVPattern) {
        self.slitWidth = pattern.defaultSlitWidth
        self.isDiagonal = pattern.isDiagonal
        self.activeDotRatio = pattern.activeDotRatio
    }
    
    private func rebuildSlices() {
        self.slices = BitmapGenerator.shared.generateSlices(
            text: currentText,
            direction: direction,
            targetSlices: 36,
            sliceResolution: 28, // 7分割等幅マッピング（Eの横線間隙間を2倍確保）
            mirrorForViewer: mirrorForViewer
        )
    }
    
    private func flashScreen() {
        isTestFlash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.isTestFlash = false
        }
    }
}
