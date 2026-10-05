import UIKit
import SwiftUI

/// レスキュー＆フェスティバル表示カラー（日常 ✕ 非常時: 100%全モード最大光束発光）
public enum POVColor: String, CaseIterable, Identifiable {
    case white = "レスキューホワイト"
    case red = "エマージェンシーレッド"
    case yellow = "ハイビズイエロー"
    case cyan = "ネオンシアン"
    case magenta = "パーティーマゼンタ"
    case green = "エメラルドグリーン"
    case orange = "サンセットアンバー"
    
    public var id: String { rawValue }
    
    public var uiColor: UIColor {
        switch self {
        case .white: return UIColor(white: 1.0, alpha: 1.0)
        case .red: return UIColor(red: 1.0, green: 0.05, blue: 0.05, alpha: 1.0)
        case .yellow: return UIColor(red: 1.0, green: 1.0, blue: 0.0, alpha: 1.0)
        case .cyan: return UIColor(red: 0.0, green: 1.0, blue: 1.0, alpha: 1.0)
        case .magenta: return UIColor(red: 1.0, green: 0.0, blue: 0.85, alpha: 1.0)
        case .green: return UIColor(red: 0.0, green: 1.0, blue: 0.35, alpha: 1.0)
        case .orange: return UIColor(red: 1.0, green: 0.60, blue: 0.0, alpha: 1.0)
        }
    }
    
    public var swiftUIColor: Color {
        Color(uiColor: uiColor)
    }
}

/// CADisplayLinkによる超高速POVスリットレンダラーUIView
public final class POVCanvasView: UIView {
    public var slices: [[Bool]] = []
    public var rawText: String = "HELP"
    public var direction: POVDirection = .horizontal
    public var slitColor: UIColor = .white
    public var slitWidth: CGFloat = 35.0 // デフォルト35px（高光量かつE文字判別可能バランス）
    public var isDiagonal: Bool = false  // 画面対角線を使った特大文字モード
    public var activeDotRatio: CGFloat = 0.82 // 縦ドット発光比率（0.82で隙間18%確保し、E文字潰れを根絶）
    
    private var displayLink: CADisplayLink?
    private var currentSliceIndex: Int = -1
    private var lastStaticCharIndex: Int = -1
    
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
        lastStaticCharIndex = -1
        setNeedsDisplay()
    }
    
    @objc private func renderFrame() {
        let detector = MotionDetector.shared
        
        // 【モード1: 0cmゼロスイング（静止・全画面一文字ストロボ）】
        // 振るスペースがない時・疲弊して振れなくなった時
        if detector.activeRangeMode == .zeroStatic {
            if lastStaticCharIndex != detector.staticCharIndex || currentSliceIndex != -999 {
                lastStaticCharIndex = detector.staticCharIndex
                currentSliceIndex = -999 // 0cmストロボ描画フラグ
                setNeedsDisplay()
            }
            return
        }
        
        // 【モード2 & 3: スイングモード（30cm手首浮き出し or ワイド）】
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
        
        let detector = MotionDetector.shared
        
        // 【幅0cmモード: ゼロスイング・全画面一文字ストロボ発光】
        if detector.activeRangeMode == .zeroStatic {
            drawZeroStaticStrobe(in: rect, ctx: ctx)
            return
        }
        
        guard currentSliceIndex >= 0, currentSliceIndex < slices.count else {
            return
        }
        
        let slice = slices[currentSliceIndex]
        let dotCount = slice.count
        guard dotCount > 0 else { return }
        
        ctx.setFillColor(slitColor.cgColor)
        ctx.saveGState()
        
        let isUpsideDown = detector.isUpsideDown
        
        // 【手首30cm浮き出しモード時のスリット幅最適化】
        // 手首の狭いスナップ（振れ幅約25〜35cm）では、スリットを14pxに絞ることで空間にクッキリ浮き出る
        let effectiveSlitWidth: CGFloat
        if detector.activeRangeMode == .compactSnap {
            effectiveSlitWidth = 14.0
        } else {
            effectiveSlitWidth = slitWidth
        }
        
        // 【電源ボタン誤押し回避: 上下逆さま持ち自動対応（安全設計）】
        let activeSlice = isUpsideDown ? Array(slice.reversed()) : slice
        
        if isDiagonal {
            // 【対角線特大文字モード（改良版）】
            // 画面中心を原点に対角線の角度に回転させ、対角線全長（約950pt）を使って文字を巨大描画！
            let diagLength = hypot(rect.width, rect.height)
            let angle = atan2(rect.width, rect.height) // 約24度
            
            ctx.translateBy(x: rect.midX, y: rect.midY)
            ctx.rotate(by: -angle)
            
            let actualWidth = max(effectiveSlitWidth, 6.0)
            let startX = -actualWidth / 2.0
            let startY = -diagLength / 2.0
            let dotHeight = diagLength / CGFloat(dotCount)
            let activeDotH = dotHeight * activeDotRatio
            
            for (idx, isOn) in activeSlice.enumerated() {
                if isOn {
                    let y = startY + CGFloat(idx) * dotHeight + (dotHeight - activeDotH) / 2.0
                    let dotRect = CGRect(x: startX, y: y, width: actualWidth, height: activeDotH)
                    let path = UIBezierPath(roundedRect: dotRect, cornerRadius: min(actualWidth * 0.15, 6.0))
                    ctx.addPath(path.cgPath)
                    ctx.fillPath()
                }
            }
            
        } else {
            switch direction {
            case .horizontal:
                // 【モード別最適化: 30cm手首スナップ vs 頭上大振り超爆光照射】
                let actualWidth: CGFloat
                let primaryStartX: CGFloat
                
                if detector.activeRangeMode == .compactSnap {
                    // 【30cm手首スナップモード: 重なり防止・中央アンカー固定 ＆ 高精細24pxスリット】
                    // 手首の素早い角速度（15〜25度）をそのまま空間に射影するため、スリットは画面中央にガッチリ固定！
                    // これにより、S・O・Sの各文字が空間に等間隔に並び、特定箇所への重なりを根絶！
                    actualWidth = 24.0
                    primaryStartX = (rect.width - actualWidth) / 2.0
                } else {
                    // 【頭上大振りワイドモード: 140px超爆光スリット ＆ 画面中央固定 ＆ 光束ブースト】
                    // 腕の高速大振り（秒速数メートル）でも暗くならないよう、スリット幅を140px（画面幅の約36%）へ超拡大！
                    // 画面内ローリング走査を廃止して画面中央に固定することで、物理スイングの露光時間を最大化！
                    // 人間の網膜に届く光子（フォトン量）を3倍以上に増幅し、夜空で圧倒的な眩しさの爆光文字を照射！
                    actualWidth = 140.0
                    primaryStartX = (rect.width - actualWidth) / 2.0
                }
                
                let dotHeight = rect.height / CGFloat(dotCount)
                let activeDotH = dotHeight * 0.92 // ドット高さを92%まで広げて最大光束化（隙間8%で文字判別性担保）
                
                // 1. 主スリット（Primary Slit）の超爆光照射
                ctx.setFillColor(slitColor.cgColor)
                for (idx, isOn) in activeSlice.enumerated() {
                    if isOn {
                        let y = CGFloat(idx) * dotHeight + (dotHeight - activeDotH) / 2.0
                        let dotRect = CGRect(x: primaryStartX, y: y, width: actualWidth, height: activeDotH)
                        let path = UIBezierPath(roundedRect: dotRect, cornerRadius: min(actualWidth * 0.15, 10.0))
                        ctx.addPath(path.cgPath)
                        ctx.fillPath()
                    }
                }
                
                // 2. 頭上ワイドモード時: 隣接スライスを画面左右に補助同時照射（空間フォトン・ブースト）
                // 遠距離やヘリコプターからでも肉眼で強烈に認識できる爆光度を実現
                if detector.activeRangeMode == .wide {
                    let sideWidth = actualWidth * 0.40
                    let leftStartX = max(4.0, primaryStartX - sideWidth - 12.0)
                    let rightStartX = min(rect.width - sideWidth - 4.0, primaryStartX + actualWidth + 12.0)
                    
                    // 進行方向に応じた前後スライスの補助発光（輝度75%）
                    let prevIndex = (detector.currentPhase == .forward) ? currentSliceIndex - 1 : currentSliceIndex + 1
                    let nextIndex = (detector.currentPhase == .forward) ? currentSliceIndex + 1 : currentSliceIndex - 1
                    
                    if prevIndex >= 0 && prevIndex < slices.count {
                        let prevSlice = isUpsideDown ? Array(slices[prevIndex].reversed()) : slices[prevIndex]
                        ctx.setFillColor(slitColor.withAlphaComponent(0.75).cgColor)
                        for (idx, isOn) in prevSlice.enumerated() {
                            if isOn {
                                let y = CGFloat(idx) * dotHeight + (dotHeight - activeDotH) / 2.0
                                let dotRect = CGRect(x: leftStartX, y: y, width: sideWidth, height: activeDotH)
                                let path = UIBezierPath(roundedRect: dotRect, cornerRadius: min(sideWidth * 0.15, 6.0))
                                ctx.addPath(path.cgPath)
                                ctx.fillPath()
                            }
                        }
                    }
                    
                    if nextIndex >= 0 && nextIndex < slices.count {
                        let nextSlice = isUpsideDown ? Array(slices[nextIndex].reversed()) : slices[nextIndex]
                        ctx.setFillColor(slitColor.withAlphaComponent(0.75).cgColor)
                        for (idx, isOn) in nextSlice.enumerated() {
                            if isOn {
                                let y = CGFloat(idx) * dotHeight + (dotHeight - activeDotH) / 2.0
                                let dotRect = CGRect(x: rightStartX, y: y, width: sideWidth, height: activeDotH)
                                let path = UIBezierPath(roundedRect: dotRect, cornerRadius: min(sideWidth * 0.15, 6.0))
                                ctx.addPath(path.cgPath)
                                ctx.fillPath()
                            }
                        }
                    }
                }
                
            case .vertical:
                // 縦振りの場合: 画面中央から進行方向へY軸プログレッシブ走査
                let actualHeight = max(effectiveSlitWidth, 6.0)
                let dotWidth = rect.width / CGFloat(dotCount)
                let activeDotW = dotWidth * activeDotRatio
                
                let progress = detector.strokeProgress
                let rollingProgress: CGFloat = (detector.currentPhase == .forward) ? CGFloat(0.12 + 0.76 * progress) : CGFloat(0.88 - 0.76 * progress)
                let primaryStartY = rect.height * rollingProgress - actualHeight / 2.0
                
                ctx.setFillColor(slitColor.cgColor)
                for (idx, isOn) in activeSlice.enumerated() {
                    if isOn {
                        let x = CGFloat(idx) * dotWidth + (dotWidth - activeDotW) / 2.0
                        let dotRect = CGRect(x: x, y: primaryStartY, width: activeDotW, height: actualHeight)
                        let path = UIBezierPath(roundedRect: dotRect, cornerRadius: min(actualHeight * 0.15, 6.0))
                        ctx.addPath(path.cgPath)
                        ctx.fillPath()
                    }
                }
            }
        }
        
        ctx.restoreGState()
    }
    
    /// 幅0cmモード: ゼロスイング・全画面一文字ストロボ発光
    /// フラッシュモード（POV）と完全に同じ5x7ドットフォント字体を使用し、
    /// 画面の上下端・左右端を目一杯に使って縦長大迫力ストロボ点滅させる
    private func drawZeroStaticStrobe(in rect: CGRect, ctx: CGContext) {
        let detector = MotionDetector.shared
        guard detector.isStaticFlashVisible else { return } // ストロボ暗転パルス
        
        let chars = Array(rawText.isEmpty ? "HELP" : rawText)
        let charIndex = detector.staticCharIndex % max(1, chars.count)
        let currentChar = chars[charIndex]
        
        // フラッシュモードと全く同じドットマトリクス（列数 x 7行）を取得
        let matrix = BitmapGenerator.shared.getSingleCharMatrix(char: currentChar)
        let colCount = matrix.count
        let rowCount = 7
        guard colCount > 0 else { return }
        
        ctx.saveGState()
        
        // 上下逆さま持ち（充電口が上）の場合は相手から正立して読めるよう180度回転
        if detector.isUpsideDown {
            ctx.translateBy(x: rect.midX, y: rect.midY)
            ctx.rotate(by: .pi)
            ctx.translateBy(x: -rect.midX, y: -rect.midY)
        }
        
        // 画面の上下（Y軸）を100%目一杯フル活用（上下マージン0）
        let dotH = rect.height / CGFloat(rowCount)
        let activeDotH = dotH * 0.88 // 隙間12%確保（フラッシュモードと同等のシャープなドット感）
        
        // 横幅（X軸）も画面幅の92%を使って目一杯広げ、縦長迫力表示
        let totalDrawingWidth = rect.width * 0.92
        let dotW = totalDrawingWidth / CGFloat(colCount)
        let activeDotW = dotW * 0.86 // 横方向の隙間14%確保
        let startX = (rect.width - totalDrawingWidth) / 2.0
        
        ctx.setFillColor(slitColor.cgColor)
        
        for (colIdx, colDots) in matrix.enumerated() {
            let x = startX + CGFloat(colIdx) * dotW + (dotW - activeDotW) / 2.0
            for (rowIdx, isOn) in colDots.enumerated() {
                if isOn && rowIdx < rowCount {
                    let y = CGFloat(rowIdx) * dotH + (dotH - activeDotH) / 2.0
                    let dotRect = CGRect(x: x, y: y, width: activeDotW, height: activeDotH)
                    // フラッシュモードと同じ質感の角丸LEDブロック
                    let path = UIBezierPath(roundedRect: dotRect, cornerRadius: min(activeDotW * 0.2, 8.0))
                    ctx.addPath(path.cgPath)
                    ctx.fillPath()
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
    public let rawText: String
    public let direction: POVDirection
    public let color: UIColor
    public let slitWidth: CGFloat
    public let isDiagonal: Bool
    public let activeDotRatio: CGFloat
    
    public init(
        slices: [[Bool]],
        rawText: String = "HELP",
        direction: POVDirection,
        color: UIColor,
        slitWidth: CGFloat = 35.0,
        isDiagonal: Bool = false,
        activeDotRatio: CGFloat = 0.82
    ) {
        self.slices = slices
        self.rawText = rawText
        self.direction = direction
        self.color = color
        self.slitWidth = slitWidth
        self.isDiagonal = isDiagonal
        self.activeDotRatio = activeDotRatio
    }
    
    public func makeUIView(context: Context) -> POVCanvasView {
        let view = POVCanvasView()
        view.slices = slices
        view.rawText = rawText
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
        uiView.rawText = rawText
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
