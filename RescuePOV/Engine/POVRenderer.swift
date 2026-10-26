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
        case .white:
            // True Tone / Night Shift下でも青・緑・赤のすべてのサブピクセルを100%最大駆動させるDisplayP3純白
            return UIColor(displayP3Red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
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
    public var imageSlices: [CGImage] = []
    public var rawText: String = "HELP"
    public var direction: POVDirection = .horizontal
    public var slitColor: UIColor = .white
    public var slitWidth: CGFloat = 35.0 // デフォルト35px（高光量かつE文字判別可能バランス）
    public var isDiagonal: Bool = false  // 画面対角線を使った特大文字モード
    public var diagonalAngle: CGFloat? = nil // 草魔法などの回転方向に応じたカスタム角度
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
        guard detector.isEmitting, (!slices.isEmpty || !imageSlices.isEmpty) else {
            if currentSliceIndex != -1 {
                currentSliceIndex = -1
                setNeedsDisplay()
            }
            return
        }
        
        let count = !imageSlices.isEmpty ? imageSlices.count : slices.count
        let progress = detector.strokeProgress
        
        // 往路・復路で空間上の同じ絶対位置に同じ文字スライスを発光させる
        let targetIndex: Int
        if detector.currentPhase == .forward {
            targetIndex = min(Int(progress * Double(count)), count - 1)
        } else {
            targetIndex = min(Int((1.0 - progress) * Double(count)), count - 1)
        }
        
        // フルカラーCGモード時は、1/120秒（1フレーム約8.3mm）ごとの連続パン（像の移動）を毎フレーム滑らかに描画更新する
        if !imageSlices.isEmpty {
            currentSliceIndex = max(0, targetIndex)
            setNeedsDisplay()
        } else if targetIndex != currentSliceIndex {
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
            if !imageSlices.isEmpty {
                // フルカラー画像モード（魔法バトル等）では、静止時の文字ストロボを完全に排除（無効化）
                // これにより「FIRE」などの文字が表示される現象を防ぐ
                return
            }
            drawZeroStaticStrobe(in: rect, ctx: ctx)
            return
        }
        
        guard currentSliceIndex >= 0, currentSliceIndex < (!imageSlices.isEmpty ? imageSlices.count : slices.count) else {
            return
        }
        
        // 【フルカラー画像モード：スリット窓固定 ＋ 内部像の120Hz連続パン（動画スクロール）方式】
        if !imageSlices.isEmpty {
            // 手首モード（compactSnap）時は手首の狭い振れ幅に合わせてスリット幅を最適化、通常時は90pxフル幅
            let effectiveSlitWidth: CGFloat = (detector.selectedRangeMode == .compactSnap)
            ? max(slitWidth * 0.45, 36.0)
            : slitWidth
            
            // 往路(左→右)と復路(右→左)で空間上の同じ位置に像がロックされるよう連続空間座標(0.0〜1.0)を算出
            let rawProgress = CGFloat(detector.strokeProgress)
            let spatialProgress = (detector.currentPhase == .forward) ? rawProgress : (1.0 - rawProgress)
            
            ctx.saveGState()
            // CoreGraphicsは左下原点のためY軸を反転
            ctx.translateBy(x: 0, y: rect.height)
            ctx.scaleBy(x: 1.0, y: -1.0)
            
            // 24分割スライスを連結した全体仮想キャンバス幅（画面中を像が左→右、右→左へ連続パンする）
            // スリット窓(90px)は画面中央に固定し、クリッピングマスクとして機能させる
            if isDiagonal || diagonalAngle != nil {
                let diagLength = hypot(rect.width, rect.height)
                let angle = diagonalAngle ?? atan2(rect.width, rect.height)
                ctx.translateBy(x: rect.midX, y: rect.midY)
                ctx.rotate(by: -angle)
                
                let slitRect = CGRect(x: -effectiveSlitWidth / 2.0, y: -diagLength / 2.0, width: effectiveSlitWidth, height: diagLength)
                ctx.clip(to: slitRect)
                
                // 24分割されたスライス群を仮想空間に並べ、現在の空間位置に合わせて窓の中を連続パンさせる
                let totalVirtualWidth = effectiveSlitWidth * CGFloat(imageSlices.count) * 0.45
                let panOffsetX = -effectiveSlitWidth / 2.0 - spatialProgress * (totalVirtualWidth - effectiveSlitWidth)
                let singleSliceW = totalVirtualWidth / CGFloat(imageSlices.count)
                
                for (i, sliceImg) in imageSlices.enumerated() {
                    let drawX = panOffsetX + CGFloat(i) * singleSliceW
                    if drawX + singleSliceW >= slitRect.minX && drawX <= slitRect.maxX {
                        ctx.draw(sliceImg, in: CGRect(x: drawX, y: -diagLength / 2.0, width: singleSliceW + 1.0, height: diagLength))
                    }
                }
            } else {
                switch direction {
                case .horizontal:
                    // 炎・水（横振り）：中央に90pxの縦スリット窓を開け、中の像を左右に連続パンさせる
                    let primaryStartX = (rect.width - effectiveSlitWidth) / 2.0
                    let slitRect = CGRect(x: primaryStartX, y: 0, width: effectiveSlitWidth, height: rect.height)
                    ctx.clip(to: slitRect)
                    
                    let totalVirtualWidth = effectiveSlitWidth * CGFloat(imageSlices.count) * 0.45
                    let panOffsetX = primaryStartX - spatialProgress * (totalVirtualWidth - effectiveSlitWidth)
                    let singleSliceW = totalVirtualWidth / CGFloat(imageSlices.count)
                    
                    for (i, sliceImg) in imageSlices.enumerated() {
                        let drawX = panOffsetX + CGFloat(i) * singleSliceW
                        if drawX + singleSliceW >= slitRect.minX && drawX <= slitRect.maxX {
                            ctx.draw(sliceImg, in: CGRect(x: drawX, y: 0, width: singleSliceW + 1.0, height: rect.height))
                        }
                    }
                    
                case .vertical:
                    // サンダー（縦振り）：中央に90pxの横（水平）スリット窓を開け、中の像を上下に連続パンさせる
                    let primaryStartY = (rect.height - effectiveSlitWidth) / 2.0
                    let slitRect = CGRect(x: 0, y: primaryStartY, width: rect.width, height: effectiveSlitWidth)
                    ctx.clip(to: slitRect)
                    
                    let totalVirtualHeight = effectiveSlitWidth * CGFloat(imageSlices.count) * 0.45
                    let panOffsetY = primaryStartY - spatialProgress * (totalVirtualHeight - effectiveSlitWidth)
                    let singleSliceH = totalVirtualHeight / CGFloat(imageSlices.count)
                    
                    for (i, sliceImg) in imageSlices.enumerated() {
                        let drawY = panOffsetY + CGFloat(i) * singleSliceH
                        if drawY + singleSliceH >= slitRect.minY && drawY <= slitRect.maxY {
                            ctx.draw(sliceImg, in: CGRect(x: 0, y: drawY, width: rect.width, height: singleSliceH + 1.0))
                        }
                    }
                }
            }
            
            ctx.restoreGState()
            return
        }
        
        let slice = slices[currentSliceIndex]
        let dotCount = slice.count
        guard dotCount > 0 else { return }
        
        ctx.setFillColor(slitColor.cgColor)
        ctx.saveGState()
        
        let isUpsideDown = detector.isUpsideDown
        
        // 【光量激減・色ボケ防止】
        // 4.0pxに縮小すると有機ELのサブピクセル応答遅延で色割れ＆光量不足になるため、
        // 通常・AI自動時は常に90.0pxフル幅（手動で30cmモードを選んだ時のみ32px）で100%純白発光させる
        let effectiveSlitWidth: CGFloat
        if detector.selectedRangeMode == .compactSnap {
            effectiveSlitWidth = 32.0
        } else {
            effectiveSlitWidth = slitWidth // 90.0px
        }
        
        // 【電源ボタン誤押し回避: 上下逆さま持ち自動対応（安全設計）】
        let activeSlice = isUpsideDown ? Array(slice.reversed()) : slice
        
        if isDiagonal || diagonalAngle != nil {
            // 【対角線特大文字モード（改良版）】
            // 画面中心を原点に対角線の角度に回転させ、対角線全長（約950pt）を使って文字を巨大描画！
            let diagLength = hypot(rect.width, rect.height)
            let angle = diagonalAngle ?? atan2(rect.width, rect.height)
            
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
                let actualWidth = effectiveSlitWidth
                let primaryStartX = (rect.width - actualWidth) / 2.0
                let dotHeight = rect.height / CGFloat(dotCount)
                let activeDotH = dotHeight * 1.05 // 隙間を完全に無くし、オーバーラップさせて爆光を確保
                
                // 主スリット（Primary Slit）の照射
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
    public let imageSlices: [CGImage]
    public let rawText: String
    public let direction: POVDirection
    public let color: UIColor
    public let slitWidth: CGFloat
    public let isDiagonal: Bool
    public let diagonalAngle: CGFloat?
    public let activeDotRatio: CGFloat
    
    public init(
        slices: [[Bool]] = [],
        imageSlices: [CGImage] = [],
        rawText: String = "HELP",
        direction: POVDirection,
        color: UIColor,
        slitWidth: CGFloat = 35.0,
        isDiagonal: Bool = false,
        diagonalAngle: CGFloat? = nil,
        activeDotRatio: CGFloat = 0.82
    ) {
        self.slices = slices
        self.imageSlices = imageSlices
        self.rawText = rawText
        self.direction = direction
        self.color = color
        self.slitWidth = slitWidth
        self.isDiagonal = isDiagonal
        self.diagonalAngle = diagonalAngle
        self.activeDotRatio = activeDotRatio
    }
    
    public func makeUIView(context: Context) -> POVCanvasView {
        let view = POVCanvasView()
        view.slices = slices
        view.imageSlices = imageSlices
        view.rawText = rawText
        view.direction = direction
        view.slitColor = color
        view.slitWidth = slitWidth
        view.isDiagonal = isDiagonal
        view.diagonalAngle = diagonalAngle
        view.activeDotRatio = activeDotRatio
        view.startRendering()
        return view
    }
    
    public func updateUIView(_ uiView: POVCanvasView, context: Context) {
        uiView.slices = slices
        uiView.imageSlices = imageSlices
        uiView.rawText = rawText
        uiView.direction = direction
        uiView.slitColor = color
        if uiView.slitWidth != slitWidth {
            uiView.slitWidth = slitWidth
        }
        if uiView.isDiagonal != isDiagonal {
            uiView.isDiagonal = isDiagonal
        }
        if uiView.diagonalAngle != diagonalAngle {
            uiView.diagonalAngle = diagonalAngle
        }
        if uiView.activeDotRatio != activeDotRatio {
            uiView.activeDotRatio = activeDotRatio
        }
    }
}
