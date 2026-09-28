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
    public var slitWidth: CGFloat = 35.0 // デフォルト35px（高光量かつE文字判別可能バランス）
    public var isDiagonal: Bool = false  // 画面対角線を使った特大文字モード
    public var activeDotRatio: CGFloat = 0.82 // 縦ドット発光比率（0.82で隙間18%確保し、E文字潰れを根絶）
    
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
            // 120Hz ProMotion ディスプレイを最大限活用
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 120, maximum: 120, preferred: 120)
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
        
        // 往路・復路ともに最高速中間域（isEmitting == true）で同期発光
        guard detector.isEmitting, !slices.isEmpty else {
            if currentSliceIndex != -1 {
                currentSliceIndex = -1
                setNeedsDisplay()
            }
            return
        }
        
        let count = slices.count
        let progress = detector.strokeProgress
        
        // 往路・復路で空間上の同じ絶対位置に同じ文字スライスを発光させる
        // 往路（左から右へのスイング）:
        //   左端 (progress 0.0) -> 文字の左端 (index 0)
        //   右端 (progress 1.0) -> 文字の右端 (index count - 1)
        // 復路（右から左へのスイング）:
        //   右端 (progress 0.0) -> 文字の右端 (index count - 1)
        //   左端 (progress 1.0) -> 文字の左端 (index 0)
        // これにより、往復両方で空間の全く同じ位置・全く同じ向きで完全に一致する（「E」が「ヨ」にならない）
        let targetIndex: Int
        if detector.currentPhase == .forward {
            targetIndex = min(Int(progress * Double(count)), count - 1)
        } else {
            targetIndex = min(Int((1.0 - progress) * Double(count)), count - 1)
        }
        
        if targetIndex != currentSliceIndex {
            currentSliceIndex = targetIndex
            setNeedsDisplay()
        }
    }
    
    public override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        
        // 背景は完全な漆黒
        ctx.setFillColor(UIColor.black.cgColor)
        ctx.fill(rect)
        
        guard currentSliceIndex >= 0, currentSliceIndex < slices.count else {
            return
        }
        
        let slice = slices[currentSliceIndex]
        let dotCount = slice.count
        guard dotCount > 0 else { return }
        
        ctx.setFillColor(slitColor.cgColor)
        ctx.saveGState()
        
        let detector = MotionDetector.shared
        let isUpsideDown = detector.isUpsideDown
        
        // 【電源ボタン誤押し回避: 上下逆さま持ち自動対応】
        // iPhoneを上下逆さま（充電口を上）にして左右をがっしり握った場合、
        // 描画を180度回転させて空中の文字を正立させる
        if isUpsideDown {
            ctx.translateBy(x: rect.midX, y: rect.midY)
            ctx.rotate(by: .pi)
            ctx.translateBy(x: -rect.midX, y: -rect.midY)
        }
        
        if isDiagonal {
            // 【対角線特大文字モード（改良版）】
            // 画面中心を原点に対角線の角度に回転させ、対角線全長（約950pt）を使って文字を巨大描画！
            let diagLength = hypot(rect.width, rect.height)
            let angle = atan2(rect.width, rect.height) // 約24度
            
            ctx.translateBy(x: rect.midX, y: rect.midY)
            ctx.rotate(by: -angle)
            
            let actualWidth = max(slitWidth, 8.0)
            let startX = -actualWidth / 2.0
            let startY = -diagLength / 2.0
            let dotHeight = diagLength / CGFloat(dotCount)
            let activeDotH = dotHeight * activeDotRatio
            
            for (idx, isOn) in slice.enumerated() {
                if isOn {
                    let y = startY + CGFloat(idx) * dotHeight + (dotHeight - activeDotH) / 2.0
                    let dotRect = CGRect(x: startX, y: y, width: actualWidth, height: activeDotH)
                    let path = UIBezierPath(roundedRect: dotRect, cornerRadius: min(actualWidth * 0.15, 6.0))
                    ctx.addPath(path.cgPath)
                    ctx.fillPath()
                }
            }
            
        } else {
            // 【通常垂直スリットモード（左右がっしり抑え持ち最適化・超巨大縦スケール）】
            switch direction {
            case .horizontal:
                // 横振りの場合: 画面中央に高光量LED縦スリットを描画（画面の上端から下端まで100%フル活用）
                let actualWidth = max(slitWidth, 8.0)
                let startX = (rect.width - actualWidth) / 2.0
                let dotHeight = rect.height / CGFloat(dotCount)
                let activeDotH = dotHeight * activeDotRatio // 隙間を確保してEの文字潰れを完全に防止
                
                for (idx, isOn) in slice.enumerated() {
                    if isOn {
                        let y = CGFloat(idx) * dotHeight + (dotHeight - activeDotH) / 2.0
                        let dotRect = CGRect(x: startX, y: y, width: actualWidth, height: activeDotH)
                        let path = UIBezierPath(roundedRect: dotRect, cornerRadius: min(actualWidth * 0.15, 6.0))
                        ctx.addPath(path.cgPath)
                        ctx.fillPath()
                    }
                }
                
            case .vertical:
                // 縦振りの場合: 画面中央に高光量LED横スリットを描画
                let actualHeight = max(slitWidth, 8.0)
                let startY = (rect.height - actualHeight) / 2.0
                let dotWidth = rect.width / CGFloat(dotCount)
                let activeDotW = dotWidth * activeDotRatio
                
                for (idx, isOn) in slice.enumerated() {
                    if isOn {
                        let x = CGFloat(idx) * dotWidth + (dotWidth - activeDotW) / 2.0
                        let dotRect = CGRect(x: x, y: startY, width: activeDotW, height: actualHeight)
                        let path = UIBezierPath(roundedRect: dotRect, cornerRadius: min(actualHeight * 0.15, 6.0))
                        ctx.addPath(path.cgPath)
                        ctx.fillPath()
                    }
                }
            }
        }
        
        ctx.restoreGState()
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
    public let slitWidth: CGFloat
    public let isDiagonal: Bool
    public let activeDotRatio: CGFloat
    
    public init(
        slices: [[Bool]],
        direction: POVDirection,
        color: UIColor,
        slitWidth: CGFloat = 35.0,
        isDiagonal: Bool = false,
        activeDotRatio: CGFloat = 0.82
    ) {
        self.slices = slices
        self.direction = direction
        self.color = color
        self.slitWidth = slitWidth
        self.isDiagonal = isDiagonal
        self.activeDotRatio = activeDotRatio
    }
    
    public func makeUIView(context: Context) -> POVCanvasView {
        let view = POVCanvasView()
        view.slices = slices
        view.direction = direction
        view.slitColor = color
        view.slitWidth = slitWidth
        view.isDiagonal = isDiagonal
        view.activeDotRatio = activeDotRatio
        view.startRendering()
        return view
    }
    
    public func updateUIView(_ uiView: POVCanvasView, context: Context) {
        uiView.slices = slices
        uiView.direction = direction
        uiView.slitColor = color
        if uiView.slitWidth != slitWidth {
            uiView.slitWidth = slitWidth
        }
        if uiView.isDiagonal != isDiagonal {
            uiView.isDiagonal = isDiagonal
        }
        if uiView.activeDotRatio != activeDotRatio {
            uiView.activeDotRatio = activeDotRatio
        }
    }
}
