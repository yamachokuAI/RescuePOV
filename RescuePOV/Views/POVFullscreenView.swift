import SwiftUI

/// フルスクリーンPOV空中文字表示画面
public struct POVFullscreenView: View {
    @Environment(\.dismiss) private var dismiss
    
    let text: String
    let direction: POVDirection
    let color: POVColor
    let mirrorForViewer: Bool
    
    @StateObject private var motionDetector = MotionDetector.shared
    
    @State private var previousBrightness: CGFloat = 0.5
    @State private var slices: [[Bool]] = []
    @State private var showInitialGuide: Bool = true
    @State private var isTestFlash: Bool = false
    @State private var slitWidth: CGFloat = 45.0 // デフォルト45px（高光量スリット）
    @State private var manualShowControls: Bool = false
    
    /// 水平時、またはタップ時にのみコントロールUIを表示
    private var isControlsVisible: Bool {
        motionDetector.isDeviceHorizontal || manualShowControls
    }
    
    public init(
        text: String,
        direction: POVDirection,
        color: POVColor,
        mirrorForViewer: Bool = true
    ) {
        self.text = text
        self.direction = direction
        self.color = color
        self.mirrorForViewer = mirrorForViewer
    }
    
    public var body: some View {
        ZStack {
            // 背景黒（完全な漆黒）
            Color.black.ignoresSafeArea()
            
            // CADisplayLink＋位置同期による高光量スリット残像キャンバス
            POVCanvasRepresentable(
                slices: slices,
                direction: direction,
                color: isTestFlash ? UIColor.white : color.uiColor,
                slitWidth: slitWidth
            )
            .ignoresSafeArea()
            
            // テスト発光フラッシュオーバーレイ
            if isTestFlash {
                Color.white.ignoresSafeArea()
            }
            
            // 突入時の初期ガイド（振りを検知するかタップで即消去）
            if showInitialGuide && !motionDetector.isMotionActive {
                VStack(spacing: 16) {
                    Image(systemName: direction.iconName)
                        .font(.system(size: 64, weight: .bold))
                        .foregroundColor(.yellow)
                    
                    Text("【救難POVモード準備完了】")
                        .font(.title2.bold())
                        .foregroundColor(.white)
                    
                    Text("iPhoneの画面を相手に向け\n頭上で腕を左右に大きくしっかり振ってください！")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                    
                    Text("表示文字: 「\(text)」")
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
                .padding(26)
                .background(RoundedRectangle(cornerRadius: 20).fill(Color.black.opacity(0.9)))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.yellow.opacity(0.6), lineWidth: 2)
                )
                .padding(.horizontal, 30)
                .transition(.opacity.combined(with: .scale))
            }
            
            // 【操作UIオーバーレイ】
            // 携帯を頭上に掲げて振っている時は完全消灯（不透明度0.0）
            // 手元で水平にした時だけフワッと再表示
            VStack {
                // 上部バー
                HStack {
                    Button(action: {
                        dismiss()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark.circle.fill")
                            Text("戻る")
                        }
                        .font(.subheadline.bold())
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color(white: 0.25, opacity: 0.85)))
                        .foregroundColor(.white)
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
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.orange.opacity(0.85)))
                        .foregroundColor(.black)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 12)
                
                Spacer()
                
                // 水平時に現れる光量・スリット調整パネル
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "sun.max.fill")
                            .foregroundColor(.yellow)
                        Text("スリット幅・光量調整")
                            .font(.subheadline.bold())
                            .foregroundColor(.white)
                        Spacer()
                        Text(String(format: "%.0f px", slitWidth))
                            .font(.subheadline.monospacedDigit().bold())
                            .foregroundColor(.yellow)
                    }
                    
                    HStack(spacing: 12) {
                        Text("細部重視\n(15px)")
                            .font(.system(size: 9))
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                        
                        Slider(value: $slitWidth, in: 10...120, step: 5)
                            .tint(.yellow)
                        
                        Text("超爆光\n(120px)")
                            .font(.system(size: 9))
                            .foregroundColor(.yellow)
                            .multilineTextAlignment(.center)
                    }
                    
                    HStack(spacing: 8) {
                        Image(systemName: "iphone.radiowaves.left.and.right")
                            .foregroundColor(.green)
                        Text("携帯を立てて頭上で振ると全ボタンが自動消灯します（残像妨害防止）")
                            .font(.system(size: 11))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    .padding(.top, 2)
                    
                    Divider().background(Color.white.opacity(0.2))
                    
                    // ステータス表示
                    HStack {
                        Circle()
                            .fill(motionDetector.isEmitting ? Color.green : Color.gray)
                            .frame(width: 8, height: 8)
                        
                        Text(motionDetector.isEmitting ? "高速中央ゾーン発光中" : "端部減速域・消灯中")
                            .font(.caption2.bold())
                            .foregroundColor(.white.opacity(0.9))
                        
                        Spacer()
                        
                        Text(String(format: "位置: %.0f%% (振れ幅: %.0f°)", motionDetector.strokeProgress * 100.0, motionDetector.strokeAngleRange))
                            .font(.caption2.monospacedDigit())
                            .foregroundColor(.green)
                    }
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 18).fill(Color(white: 0.12, opacity: 0.92)))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.white.opacity(0.15), lineWidth: 1)
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .opacity(isControlsVisible ? 1.0 : 0.0)
            .animation(.easeInOut(duration: 0.22), value: isControlsVisible)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if showInitialGuide {
                withAnimation { showInitialGuide = false }
            } else {
                // 水平時以外でも、タップで手動トグル可能（非常時安全策）
                withAnimation(.easeInOut(duration: 0.2)) {
                    manualShowControls.toggle()
                }
            }
        }
        .statusBar(hidden: true)
        .onAppear {
            previousBrightness = UIScreen.main.brightness
            UIScreen.main.brightness = 1.0
            UIApplication.shared.isIdleTimerDisabled = true
            
            // 5x7高密度ドットフォントによるスライスマトリクス生成
            self.slices = BitmapGenerator.shared.generateSlices(
                text: text,
                direction: direction,
                targetSlices: 36,
                sliceResolution: 24,
                mirrorForViewer: mirrorForViewer
            )
            motionDetector.start(direction: direction)
            
            // 1.8秒後にガイドを自動フェードアウト
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
    
    private func flashScreen() {
        isTestFlash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.isTestFlash = false
        }
    }
}
