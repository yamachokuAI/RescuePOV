import UIKit
import SwiftUI

/// レスキュー表示カラー
public enum POVColor: String, CaseIterable, Identifiable {
    case white = "レスキューホワイト"
    case red = "エマージェンシーレッド"
    case yellow = "ハイビズイエロー"
    case cyan = "ネオンシアン"
    
    public var id: String { rawValue }
    
    public var uiColor: UIColor {
        switch self {
        case .white: return UIColor(white: 1.0, alpha: 1.0)
        case .red: return UIColor(red: 1.0, green: 0.15, blue: 0.15, alpha: 1.0)
        case .yellow: return UIColor(red: 1.0, green: 0.95, blue: 0.0, alpha: 1.0)
        case .cyan: return UIColor(red: 0.0, green: 0.95, blue: 1.0, alpha: 1.0)
        }
    }
    
    public var swiftUIColor: Color {
        Color(uiColor: uiColor)
    }
}

/// CADisplayLinkによる超高速POVスリットレンダラーUIView
public final class POVCanvasView: UIView {
    public var slices: [[Bool]] = []
    public var direction: POVDirection = .horizontal
    public var slitColor: UIColor = .white
    public var slitWidthRatio: CGFloat = 0.22 // スリット幅比率（残像がクリアに見える最適比率）
    
    private var displayLink: CADisplayLink?
    private var currentSliceIndex: Int = -1
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        isOpaque = true
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        backgroundColor = .black
        isOpaque = true
    }
    
    public func startRendering() {
        stopRendering()
        let link = CADisplayLink(target: self, selector: #selector(renderFrame))
        if #available(iOS 15.0, *) {
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        }
        link.add(to: .main, forMode: .common)
        self.displayLink = link
    }
    
    public func stopRendering() {
        displayLink?.invalidate()
        displayLink = nil
        currentSliceIndex = -1
        setNeedsDisplay()
    }
    
    @objc private func renderFrame() {
        let detector = MotionDetector.shared
        
        // 往路（forward）中はスライスカラムを表示、復路（backward）は消灯
        guard detector.currentPhase == .forward, !slices.isEmpty else {
            if currentSliceIndex != -1 {
                currentSliceIndex = -1
                setNeedsDisplay()
            }
            return
        }
        
        let count = slices.count
        let progress = detector.strokeProgress
        let targetIndex = min(Int(progress * Double(count)), count - 1)
        
        if targetIndex != currentSliceIndex {
            currentSliceIndex = targetIndex
            setNeedsDisplay()
        }
    }
    
    public override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        
        // 背景黒
        ctx.setFillColor(UIColor.black.cgColor)
        ctx.fill(rect)
        
        guard currentSliceIndex >= 0, currentSliceIndex < slices.count else {
            return
        }
        
        let slice = slices[currentSliceIndex]
        let dotCount = slice.count
        guard dotCount > 0 else { return }
        
        ctx.setFillColor(slitColor.cgColor)
        
        switch direction {
        case .horizontal:
            // 横振りの場合: 画面中央に極細のLED縦スリットを描画（白残像防止）
            let slitWidth: CGFloat = 6.0
            let startX = (rect.width - slitWidth) / 2.0
            let dotHeight = rect.height / CGFloat(dotCount)
            let activeDotH = dotHeight * 0.75 // 上下に隙間を空けてLEDの粒感を出す
            
            for (idx, isOn) in slice.enumerated() {
                if isOn {
                    let y = CGFloat(idx) * dotHeight + (dotHeight - activeDotH) / 2.0
                    let dotRect = CGRect(x: startX, y: y, width: slitWidth, height: activeDotH)
                    let path = UIBezierPath(roundedRect: dotRect, cornerRadius: 2.0)
                    ctx.addPath(path.cgPath)
                    ctx.fillPath()
                }
            }
            
        case .vertical:
            // 縦振りの場合: 画面中央に極細のLED横スリットを描画
            let slitHeight: CGFloat = 6.0
            let startY = (rect.height - slitHeight) / 2.0
            let dotWidth = rect.width / CGFloat(dotCount)
            let activeDotW = dotWidth * 0.75
            
            for (idx, isOn) in slice.enumerated() {
                if isOn {
                    let x = CGFloat(idx) * dotWidth + (dotWidth - activeDotW) / 2.0
                    let dotRect = CGRect(x: x, y: startY, width: activeDotW, height: slitHeight)
                    let path = UIBezierPath(roundedRect: dotRect, cornerRadius: 2.0)
                    ctx.addPath(path.cgPath)
                    ctx.fillPath()
                }
            }
        }
    }
    
    deinit {
        stopRendering()
    }
}

/// SwiftUIラッパー
public struct POVCanvasRepresentable: UIViewRepresentable {
    public let slices: [[Bool]]
    public let direction: POVDirection
    public let color: UIColor
    
    public init(slices: [[Bool]], direction: POVDirection, color: UIColor) {
        self.slices = slices
        self.direction = direction
        self.color = color
    }
    
    public func makeUIView(context: Context) -> POVCanvasView {
        let view = POVCanvasView()
        view.slices = slices
        view.direction = direction
        view.slitColor = color
        view.startRendering()
        return view
    }
    
    public func updateUIView(_ uiView: POVCanvasView, context: Context) {
        uiView.slices = slices
        uiView.direction = direction
        uiView.slitColor = color
    }
}
