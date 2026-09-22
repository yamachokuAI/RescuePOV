import SwiftUI

/// フルスクリーンPOV空中文字表示画面
public struct POVFullscreenView: View {
    @Environment(\.dismiss) private var dismiss
    
    let text: String
    let direction: POVDirection
    let color: POVColor
    let mode: POVDisplayMode
    let mirrorForViewer: Bool
    
    @StateObject private var motionDetector = MotionDetector.shared
    @StateObject private var spatialTracker = SpatialMotionTracker.shared
    
    @State private var previousBrightness: CGFloat = 0.5
    @State private var slices: [[Bool]] = []
    @State private var showInitialGuide: Bool = true
    @State private var isTestFlash: Bool = false
    
    public init(
        text: String,
        direction: POVDirection,
        color: POVColor,
        mode: POVDisplayMode = .spatialWindow,
        mirrorForViewer: Bool = true
    ) {
        self.text = text
        self.direction = direction
        self.color = color
        self.mode = mode
        self.mirrorForViewer = mirrorForViewer
    }
    
    public var body: some View {
        ZStack {
            // 背景黒
            Color.black.ignoresSafeArea()
            
            // モードに応じたレンダラーの切り替え
            if mode == .spatialWindow {
                // 【新方式】角度連動・空間固定バーチャルウィンドウ
                SpatialWindowCanvasView(
                    text: text,
                    direction: direction,
                    color: isTestFlash ? .white : color,
                    mirrorForViewer: mirrorForViewer
                )
                .ignoresSafeArea()
            } else {
                // 【従来方式】CADisplayLinkによるスリット残像キャンバス
                POVCanvasRepresentable(
                    slices: slices,
                    direction: direction,
                    color: isTestFlash ? UIColor.white : color.uiColor
                )
                .ignoresSafeArea()
            }
            
            // テスト発光フラッシュオーバーレイ
            if isTestFlash {
                Color.white.ignoresSafeArea()
            }
            
            // 突入時の分かりやすい開始ガイド（2.2秒後に自動消滅、またはタップで即消去）
            if showInitialGuide {
                VStack(spacing: 16) {
                    Image(systemName: mode == .spatialWindow ? "gyroscope" : direction.iconName)
                        .font(.system(size: 64, weight: .bold))
                        .foregroundColor(.yellow)
                    
                    Text("【\(mode.shortTitle)モード開始】")
                        .font(.title2.bold())
                        .foregroundColor(.white)
                    
                    Text(mode == .spatialWindow
                         ? "iPhoneの画面を相手に向け\n頭上で腕を左右にゆったりと振ってください"
                         : "iPhoneの画面を相手に向け\n腕を左右に大きく素早く振ってください！")
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
                    
                    Text("（タップするとすぐ開始します）")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .padding(30)
                .background(RoundedRectangle(cornerRadius: 20).fill(Color.black.opacity(0.85)))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.yellow.opacity(0.5), lineWidth: 2)
                )
                .padding(.horizontal, 30)
                .transition(.opacity.combined(with: .scale))
            }
            
            // 常時表示の最小限操作バー
            VStack {
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
                        .background(Capsule().fill(Color(white: 0.2, opacity: 0.7)))
                        .foregroundColor(.white)
                    }
                    
                    Spacer()
                    
                    // 空間固定モード時: センター再調整ボタン
                    if mode == .spatialWindow {
                        Button(action: {
                            spatialTracker.recenter()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "scope")
                                Text("中心補正")
                            }
                            .font(.caption.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Color.blue.opacity(0.8)))
                            .foregroundColor(.white)
                        }
                    }
                    
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
                        .background(Capsule().fill(Color.orange.opacity(0.8)))
                        .foregroundColor(.black)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 12)
                
                Spacer()
                
                // 下部ステータス
                HStack(spacing: 12) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 8, height: 8)
                    
                    Text("モード: \(mode.shortTitle)")
                        .font(.caption2.bold())
                        .foregroundColor(.white.opacity(0.9))
                    
                    Spacer()
                    
                    if mode == .spatialWindow {
                        Text(String(format: "傾き: %+.0f°", spatialTracker.currentAngleDegrees))
                            .font(.caption2.monospacedDigit())
                            .foregroundColor(.yellow)
                    } else {
                        Text(String(format: "位置: %.0f%% (振れ幅: %.0f°)", motionDetector.strokeProgress * 100.0, motionDetector.strokeAngleRange))
                            .font(.caption2.monospacedDigit())
                            .foregroundColor(.green)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.black.opacity(0.6)))
                .padding(.bottom, 20)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if showInitialGuide {
                withAnimation { showInitialGuide = false }
            } else {
                flashScreen()
            }
        }
        .statusBar(hidden: true)
        .onAppear {
            previousBrightness = UIScreen.main.brightness
            UIScreen.main.brightness = 1.0
            UIApplication.shared.isIdleTimerDisabled = true
            
            if mode == .spatialWindow {
                spatialTracker.start(direction: direction)
            } else {
                // スライスマトリクス生成
                self.slices = BitmapGenerator.shared.generateSlices(
                    text: text,
                    direction: direction,
                    targetSlices: 36,
                    sliceResolution: 24,
                    mirrorForViewer: mirrorForViewer
                )
                motionDetector.start(direction: direction)
            }
            
            // 2.0秒後にガイドを自動フェードアウト
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.easeOut(duration: 0.4)) {
                    self.showInitialGuide = false
                }
            }
        }
        .onDisappear {
            UIScreen.main.brightness = previousBrightness
            UIApplication.shared.isIdleTimerDisabled = false
            if mode == .spatialWindow {
                spatialTracker.stop()
            } else {
                motionDetector.stop()
            }
        }
    }
    
    private func flashScreen() {
        isTestFlash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            self.isTestFlash = false
        }
    }
}
