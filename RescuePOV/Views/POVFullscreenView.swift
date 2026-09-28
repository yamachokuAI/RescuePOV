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
    let direction: POVDirection
    let color: POVColor
    let mirrorForViewer: Bool
    
    @StateObject private var motionDetector = MotionDetector.shared
    
    @State private var previousBrightness: CGFloat = 0.5
    @State private var slices: [[Bool]] = []
    @State private var showInitialGuide: Bool = true
    @State private var isTestFlash: Bool = false
    
    // 表示パラメータ（パターン連動: 実機ベストの精細極太44pxをデフォルト設定）
    @State private var selectedPattern: POVPattern = .sharpWide
    @State private var slitWidth: CGFloat = 44.0
    @State private var isDiagonal: Bool = false
    @State private var activeDotRatio: CGFloat = 0.80
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
