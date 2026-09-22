import SwiftUI

/// スイングの周期と進行度をリアルタイムに視覚化するコンポーネント
public struct MotionVisualizer: View {
    @ObservedObject var detector = MotionDetector.shared
    let direction: POVDirection
    
    public init(direction: POVDirection) {
        self.direction = direction
    }
    
    public var body: some View {
        VStack(spacing: 8) {
            HStack {
                Label(
                    title: { Text("スイングセンサー同期") },
                    icon: { Image(systemName: "waveform.path.ecg") }
                )
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
                
                Spacer()
                
                Text(String(format: "振れ幅: %.0f°", detector.strokeAngleRange))
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.yellow)
            }
            
            // スイングゲージ
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // 背景レール
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color(white: 0.15))
                    
                    // 往路の進行度バー
                    if detector.currentPhase == .forward {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(
                                LinearGradient(
                                    colors: [.green.opacity(0.8), .green],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(geo.size.width * CGFloat(detector.strokeProgress), 8))
                    }
                }
            }
            .frame(height: 12)
            
            HStack {
                Text(detector.currentPhase == .forward ? "【文字描画中（往路）】" : (detector.currentPhase == .backward ? "【消灯待機（復路）】" : "静止中 - 振ってください"))
                    .font(.caption2.bold())
                    .foregroundColor(detector.currentPhase == .forward ? .green : .secondary)
                
                Spacer()
                
                Text("角速度: \(String(format: "%.1f rad/s", detector.swingIntensity))")
                    .font(.caption2.monospacedDigit())
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(white: 0.1)))
    }
}
