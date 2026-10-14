import UIKit
import QuartzCore
import SwiftUI

public final class POVMagicCanvasView: UIView {
    public var magicImage: CGImage?
    public var slitWidth: CGFloat = 35.0
    
    private var displayLink: CADisplayLink?
    
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
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 120, maximum: 120, preferred: 120)
        }
        link.add(to: .main, forMode: .common)
        self.displayLink = link
    }
    
    public func stopRendering() {
        displayLink?.invalidate()
        displayLink = nil
        setNeedsDisplay()
    }
    
    @objc private func renderFrame() {
        let detector = MotionDetector.shared
        
        guard detector.isEmitting, let _ = magicImage else {
            // Nothing to draw
            setNeedsDisplay()
            return
        }
        
        setNeedsDisplay()
    }
    
    public override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        
        ctx.setFillColor(UIColor.black.cgColor)
        ctx.fill(rect)
        
        let detector = MotionDetector.shared
        guard let image = magicImage else { return }
        
        if !detector.isEmitting {
            // 中心に細い白い線を引いて「発光準備OK（振れば魔法が出る状態）」であることを知らせる
            ctx.setFillColor(UIColor.white.cgColor)
            let staticWidth: CGFloat = 4.0
            ctx.fill(CGRect(x: (rect.width - staticWidth) / 2.0, y: 0, width: staticWidth, height: rect.height))
            return
        }
        
        let progress = detector.strokeProgress // 0.0 to 1.0
        
        // 画像から現在のプログレスに応じた縦スライスを切り出す
        let imageWidth = CGFloat(image.width)
        let imageHeight = CGFloat(image.height)
        
        let sliceWidth = max(imageWidth / 32.0, 1.0) // 画像を約32分割した薄いスライスを抽出
        var xOffset = progress * imageWidth
        
        // Forward/Backwardで進行方向を反転させる (鏡文字防止)
        if detector.currentPhase == .backward {
            xOffset = (1.0 - progress) * imageWidth
        }
        
        xOffset = min(max(xOffset, 0), imageWidth - sliceWidth)
        
        let cropRect = CGRect(x: xOffset, y: 0, width: sliceWidth, height: imageHeight)
        guard let croppedImage = image.cropping(to: cropRect) else { return }
        
        // 画面中央に極細のスリットを描画 (真のPOV効果を生むため、太すぎると流れる映像になってしまう)
        let effectiveSlitWidth: CGFloat = detector.activeRangeMode == .compactSnap ? max(slitWidth * 0.30, 4.0) : slitWidth
        let drawRect = CGRect(
            x: (rect.width - effectiveSlitWidth) / 2.0,
            y: 0,
            width: effectiveSlitWidth,
            height: rect.height
        )
        
        // CGContextは上下反転しているため補正
        ctx.saveGState()
        ctx.translateBy(x: 0, y: rect.height)
        ctx.scaleBy(x: 1.0, y: -1.0)
        
        ctx.draw(croppedImage, in: drawRect)
        
        ctx.restoreGState()
    }
}

public struct POVMagicCanvasRepresentable: UIViewRepresentable {
    let element: MagicElement
    let slitWidth: CGFloat
    
    public func makeUIView(context: Context) -> POVMagicCanvasView {
        let view = POVMagicCanvasView()
        let uiImage = MagicImageGenerator.generateImage(for: element)
        view.magicImage = getCGImage(from: uiImage)
        view.slitWidth = slitWidth
        view.startRendering()
        return view
    }
    
    private func getCGImage(from image: UIImage) -> CGImage? {
        if let cg = image.cgImage { return cg }
        UIGraphicsBeginImageContextWithOptions(image.size, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: image.size))
        let drawnImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return drawnImage?.cgImage
    }
    
    public func updateUIView(_ uiView: POVMagicCanvasView, context: Context) {
        uiView.slitWidth = slitWidth
        if uiView.magicImage != nil {
            // Element changes? Note: element is fixed per casting session in our UI.
        }
    }
}
