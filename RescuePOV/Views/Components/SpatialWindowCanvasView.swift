import SwiftUI

/// 傾き角度に応じて文字列を逆方向にスライドさせ、
/// 空中の定位置に文字を固定表示するバーチャルウィンドウキャンバス
public struct SpatialWindowCanvasView: View {
    let text: String
    let direction: POVDirection
    let color: POVColor
    let mirrorForViewer: Bool
    
    @ObservedObject private var tracker = SpatialMotionTracker.shared
    
    public init(
        text: String,
        direction: POVDirection,
        color: POVColor,
        mirrorForViewer: Bool
    ) {
        self.text = text
        self.direction = direction
        self.color = color
        self.mirrorForViewer = mirrorForViewer
    }
    
    public var body: some View {
        GeometryReader { proxy in
            let screenSize = proxy.size
            
            ZStack {
                Color.black.ignoresSafeArea()
                
                // 空間上の仮想看板（横長/縦長に配置された巨大文字列）
                contentView(screenSize: screenSize)
                    .offset(x: calculateOffsetX(screenSize: screenSize),
                            y: calculateOffsetY(screenSize: screenSize))
            }
        }
        .drawingGroup() // GPUアクセラレーションで60/120fps超低遅延レンダリング
    }
    
    // スライドオフセットの算出
    // スマホが左に振れた（tracker.normalizedOffset < 0）とき、文字を右にスライドして相殺
    private func calculateOffsetX(screenSize: CGSize) -> CGFloat {
        guard direction == .horizontal else { return 0 }
        
        // 振り幅に応じた移動レンジ（画面幅の約 2.2倍）
        let travelRange = screenSize.width * 2.2
        // 相手に画面を向けている場合、端末が動く方向と逆（-normalizedOffset）にスライド
        let offset = -tracker.normalizedOffset * travelRange
        return offset
    }
    
    private func calculateOffsetY(screenSize: CGSize) -> CGFloat {
        guard direction == .vertical else { return 0 }
        
        let travelRange = screenSize.height * 2.2
        let offset = tracker.normalizedOffset * travelRange
        return offset
    }
    
    @ViewBuilder
    private func contentView(screenSize: CGSize) -> some View {
        let displayColor = color.swiftUIColor
        
        switch direction {
        case .horizontal:
            // 横振り: 横に文字を大きく間隔を空けて配置
            HStack(spacing: screenSize.width * 0.45) {
                ForEach(Array(text.enumerated()), id: \.offset) { index, char in
                    Text(String(char))
                        .font(.system(size: min(screenSize.height * 0.65, 380), weight: .heavy, design: .rounded))
                        .foregroundColor(displayColor)
                        // 暗闇で遠方からでも目立つ強烈な発光グロー効果
                        .shadow(color: displayColor, radius: 25)
                        .shadow(color: displayColor.opacity(0.8), radius: 10)
                        .frame(width: screenSize.width * 0.85)
                }
            }
            .scaleEffect(x: mirrorForViewer ? 1.0 : -1.0, y: 1.0)
            
        case .vertical:
            // 縦振り: 縦に文字を配置
            VStack(spacing: screenSize.height * 0.35) {
                ForEach(Array(text.enumerated()), id: \.offset) { index, char in
                    Text(String(char))
                        .font(.system(size: min(screenSize.width * 0.75, 320), weight: .heavy, design: .rounded))
                        .foregroundColor(displayColor)
                        .shadow(color: displayColor, radius: 25)
                        .shadow(color: displayColor.opacity(0.8), radius: 10)
                        .frame(height: screenSize.height * 0.7)
                }
            }
            .scaleEffect(x: 1.0, y: mirrorForViewer ? 1.0 : -1.0)
        }
    }
}
