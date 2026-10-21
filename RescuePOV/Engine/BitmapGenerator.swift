import UIKit

/// POV残像表示の方向モード
public enum POVDirection: String, CaseIterable, Identifiable {
    case horizontal = "横振り（左右スイング）"
    case vertical = "縦振り（上下スイング）"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .horizontal: return "arrow.left.and.right"
        case .vertical: return "arrow.up.and.down"
        }
    }
}

/// POV用にテキストを「絶対に潰れないクッキリスライスマトリクス」に変換するジェネレータ
public final class BitmapGenerator {
    public static let shared = BitmapGenerator()
    
    // 定番レスキュー＆パーティー文字の超精密5x7ドットビットマップ辞書（黒の隙間が保証される）
    public let dotFont: [Character: [UInt8]] = [
        "H": [0b1111111, 0b0001000, 0b0001000, 0b0001000, 0b1111111],
        "E": [0b1111111, 0b1001001, 0b1001001, 0b1001001, 0b1000001],
        "L": [0b1111111, 0b0000001, 0b0000001, 0b0000001, 0b0000001],
        "P": [0b1111111, 0b1001000, 0b1001000, 0b1001000, 0b0110000],
        "S": [0b0100110, 0b1001001, 0b1001001, 0b1001001, 0b0110010],
        "O": [0b0111110, 0b1000001, 0b1000001, 0b1000001, 0b0111110],
        "K": [0b1111111, 0b0001000, 0b0010100, 0b0100010, 0b1000001],
        "A": [0b0111111, 0b1001000, 0b1001000, 0b1001000, 0b0111111],
        "B": [0b1111111, 0b1001001, 0b1001001, 0b1001001, 0b0110110],
        "C": [0b0111110, 0b1000001, 0b1000001, 0b1000001, 0b0100010],
        "D": [0b1111111, 0b1000001, 0b1000001, 0b1000001, 0b0111110],
        "F": [0b1111111, 0b1001000, 0b1001000, 0b1001000, 0b1000000],
        "G": [0b0111110, 0b1000001, 0b1000001, 0b1001001, 0b0101110],
        "I": [0b1000001, 0b1000001, 0b1111111, 0b1000001, 0b1000001],
        "J": [0b0000010, 0b0000001, 0b1000001, 0b1111110, 0b1000000],
        "M": [0b1111111, 0b0100000, 0b0010000, 0b0100000, 0b1111111],
        "N": [0b1111111, 0b0100000, 0b0010000, 0b0001000, 0b1111111],
        "R": [0b1111111, 0b1001000, 0b1001100, 0b1001010, 0b0110001],
        "T": [0b1000000, 0b1000000, 0b1111111, 0b1000000, 0b1000000],
        "U": [0b1111110, 0b0000001, 0b0000001, 0b0000001, 0b1111110],
        "V": [0b1111100, 0b0000010, 0b0000001, 0b0000010, 0b1111100],
        "W": [0b1111111, 0b0000010, 0b0001100, 0b0000010, 0b1111111],
        "X": [0b1100011, 0b0010100, 0b0001000, 0b0010100, 0b1100011],
        "Y": [0b1100000, 0b0010000, 0b0001111, 0b0010000, 0b1100000],
        "Z": [0b1000011, 0b1000101, 0b1001001, 0b1010001, 0b1100001],
        "1": [0b0010001, 0b0100001, 0b1111111, 0b0000001, 0b0000001],
        "0": [0b0111110, 0b1000001, 0b1000001, 0b1000001, 0b0111110],
        "2": [0b0100011, 0b1000101, 0b1001001, 0b1010001, 0b0100001],
        "3": [0b0100010, 0b1000001, 0b1001001, 0b1001001, 0b0110110],
        "4": [0b0001100, 0b0010100, 0b0100100, 0b1111111, 0b0000100],
        "5": [0b1110010, 0b1001001, 0b1001001, 0b1001001, 0b1000110],
        "6": [0b0111110, 0b1001001, 0b1001001, 0b1001001, 0b0110010],
        "7": [0b1000000, 0b1000111, 0b1001000, 0b1010000, 0b1100000],
        "8": [0b0110110, 0b1001001, 0b1001001, 0b1001001, 0b0110110],
        "9": [0b0100001, 0b1001001, 0b1001001, 0b1001001, 0b0111110],
        "!": [0b0000000, 0b1011111, 0b0000000],
        "?": [0b0100000, 0b1000000, 0b1001101, 0b0110000],
        " ": [0b0000000, 0b0000000]
    ]
    
    private init() {}
    
    /// 1文字分のドットマトリクス（7行 x N列）を取得（0cm全画面ストロボ描画用）
    /// フラッシュモードと完全に一致する字体を画面いっぱいに描画するために使用
    public func getSingleCharMatrix(char: Character) -> [[Bool]] {
        let upper = Character(char.uppercased())
        if let pattern = dotFont[upper] {
            var matrix: [[Bool]] = [] // [col][row]
            for col in pattern {
                var colDots: [Bool] = []
                for row in 0..<7 {
                    let isOn = ((col >> (6 - row)) & 1) == 1
                    colDots.append(isOn)
                }
                matrix.append(colDots)
            }
            return matrix
        }
        
        // 日本語等の場合は1文字を7行x7列のラスタライズマトリクスへ変換
        return rasterizeSingleChar(char: char, resolution: 7)
    }
    
    /// テキストを2次元ブール配列（スライスのリスト）に変換します
    /// - Parameters:
    ///   - letterSpacing: 文字間隔（nil時は手首モード=0, 通常モード=1ドットに自動超圧縮）
    ///   - edgeMargin: 頂点・端部の余白スライス数（デフォルト0: 頂点の真っ暗ゾーンを完全撤廃）
    public func generateSlices(
        text: String,
        direction: POVDirection,
        targetSlices: Int = 48,
        sliceResolution: Int = 20,
        mirrorForViewer: Bool = true,
        isCondensed: Bool = false,
        letterSpacing: Double? = nil,
        edgeMargin: Int = 2 // エッジ切れ(P->F)を防ぐための極小安全マージン
    ) -> [[Bool]] {
        guard !text.isEmpty else {
            return Array(repeating: Array(repeating: false, count: sliceResolution), count: targetSlices)
        }
        
        let upper = text.uppercased()
        let canUseDotFont = upper.allSatisfy { dotFont[$0] != nil }
        let effectiveSpacing: Double = letterSpacing ?? (isCondensed ? 0.7 : 1.1)
        
        if canUseDotFont {
            return generateFromDotFont(
                text: upper,
                direction: direction,
                targetSlices: targetSlices,
                sliceResolution: sliceResolution,
                mirrorForViewer: mirrorForViewer,
                isCondensed: isCondensed,
                letterSpacing: effectiveSpacing,
                edgeMargin: edgeMargin
            )
        } else {
            return generateFromRaster(
                text: text,
                direction: direction,
                targetSlices: targetSlices,
                sliceResolution: sliceResolution,
                mirrorForViewer: mirrorForViewer,
                isCondensed: isCondensed,
                letterSpacing: effectiveSpacing,
                edgeMargin: edgeMargin
            )
        }
    }
    
    /// ドットフォントによる確実なシャープ描画（文字潰れ・白残像ゼロ ＆ 頂点暗黒ゾーン撤廃）
    private func generateFromDotFont(
        text: String,
        direction: POVDirection,
        targetSlices: Int,
        sliceResolution: Int,
        mirrorForViewer: Bool,
        isCondensed: Bool,
        letterSpacing: Double,
        edgeMargin: Int
    ) -> [[Bool]] {
        var rawCols: [[Bool]] = []
        
        // 頂点の真っ暗な部分を完全撤廃（デフォルト0列）
        for _ in 0..<edgeMargin {
            rawCols.append([Bool](repeating: false, count: 7))
        }
        
        let chars = Array(text)
        for (charIndex, char) in chars.enumerated() {
            if let pattern = dotFont[char] {
                // 30cm手首スナップ用: 5列パターンから[先頭, 中央, 末尾]の3列を抽出し、超スリム縦長フォント化
                let activePattern = pattern

                
                for col in activePattern {
                    var colDots: [Bool] = []
                    for row in 0..<7 {
                        let isOn = ((col >> (6 - row)) & 1) == 1
                        colDots.append(isOn)
                    }
                    // 列を拡張して隙間を広げる（太いスリットでも箱化しないように物理距離を稼ぐ）
                    rawCols.append(colDots)
                    if !isCondensed {
                        rawCols.append(colDots)
                        rawCols.append(colDots) // フルスイング時は3倍に拡張
                    }
                    // 手首モード(isCondensed)時は物理距離が短いため拡張しない（1倍のまま）
                }
                
                // 文字間スペース（残像によるくっつきを防ぐため確保、文字数とモードで自動調整）
                if charIndex < chars.count - 1 {
                    let spaces = isCondensed ? 0 : (chars.count > 5 ? 1 : 2)
                    for _ in 0..<max(0, spaces) {
                        rawCols.append([Bool](repeating: false, count: 7))
                    }
                }
            }
        }
        
        // 後方マージン（デフォルト0列）
        for _ in 0..<edgeMargin {
            rawCols.append([Bool](repeating: false, count: 7))
        }
        
        // 縦方向の解像度（7ドット ➔ sliceResolution ドット）へスケールアップ
        var resultSlices: [[Bool]] = []
        for col in rawCols {
            var scaledCol: [Bool] = []
            for y in 0..<sliceResolution {
                let srcY = Int(Double(y) / Double(sliceResolution) * 7.0)
                let clampedSrcY = min(max(srcY, 0), 6)
                scaledCol.append(col[clampedSrcY])
            }
            resultSlices.append(scaledCol)
        }
        
        // 【反転修正】ユーザーのフィードバックにより、表示が逆だったためロジックをシンプルに反転
        if !mirrorForViewer {
            resultSlices.reverse()
        }
        
        return resultSlices
    }
    
    /// 日本語など自由入力用の高コントラスト・文字間隙間保証ラスタライズ
    private func generateFromRaster(
        text: String,
        direction: POVDirection,
        targetSlices: Int,
        sliceResolution: Int,
        mirrorForViewer: Bool,
        isCondensed: Bool,
        letterSpacing: Double,
        edgeMargin: Int
    ) -> [[Bool]] {
        let charCount = max(text.count, 1)
        let slicePerChar = isCondensed ? 6 : (letterSpacing < 1.0 ? 8 : 10)
        let dynamicWidth = max(targetSlices, charCount * slicePerChar + edgeMargin * 2)
        let width = dynamicWidth
        let height = sliceResolution
        
        let colorSpace = CGColorSpaceCreateDeviceGray()
        var rawData = [UInt8](repeating: 0, count: width * height)
        
        guard let context = CGContext(
            data: &rawData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return Array(repeating: Array(repeating: false, count: height), count: width)
        }
        
        context.setFillColor(gray: 0.0, alpha: 1.0)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        
        UIGraphicsPushContext(context)
        context.saveGState()
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1.0, y: -1.0)
        
        let fontSize = CGFloat(height) * (isCondensed ? 0.92 : 0.82)
        let font: UIFont
        if let hiragino = UIFont(name: "HiraginoSans-W8", size: fontSize) {
            font = hiragino
        } else {
            font = UIFont.systemFont(ofSize: fontSize, weight: .heavy)
        }
        
        let kernValue: CGFloat = CGFloat(letterSpacing * 2.0 - 2.0) // 0.7-> -0.6, 1.1-> 0.2, 1.5-> 1.0
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.white,
            .kern: kernValue
        ]
        
        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributedString.size()
        
        let drawX = max((CGFloat(width) - textSize.width) / 2.0, 2.0)
        let drawY = (CGFloat(height) - textSize.height) / 2.0
        
        attributedString.draw(at: CGPoint(x: drawX, y: drawY))
        
        context.restoreGState()
        UIGraphicsPopContext()
        
        var slices: [[Bool]] = []
        let threshold: UInt8 = 130
        
        for x in 0..<width {
            let colX = mirrorForViewer ? (width - 1 - x) : x
            var colDots: [Bool] = []
            for y in 0..<height {
                let pixel = rawData[y * width + colX]
                colDots.append(pixel > threshold)
            }
            slices.append(colDots)
        }
        
        return slices
    }
    
    /// 120Hz OLED向けに「黒締め（0%完全漆黒）」＆「最大輝度ブースト」を施した
    /// 連続パン（空間スクロール）用の単一マスターCGImageを生成します
    public func generatePOVContinuousImage(
        from image: UIImage,
        direction: POVDirection = .horizontal
    ) -> CGImage? {
        return preparePOVOptimizedCGImage(from: image, rotate90ForVertical: direction == .vertical)
    }
    
    /// フルカラー画像(UIImage)をPOV残像向けに超高輝度・高コントラスト化し、
    /// 24分割に凝縮した帯(CGImage)のリストを生成します
    public func generateColorSlices(
        from image: UIImage,
        direction: POVDirection = .horizontal,
        targetSlices: Int = 24
    ) -> [CGImage] {
        guard let processedCGImage = preparePOVOptimizedCGImage(from: image, rotate90ForVertical: direction == .vertical) else {
            return []
        }
        
        let width = processedCGImage.width
        let height = processedCGImage.height
        var slices: [CGImage] = []
        
        switch direction {
        case .horizontal:
            // 24分割の窓として切り出しつつ、各スライスが連続パンの窓幅を持つように切り出す
            let windowWidth = max(1, width / targetSlices)
            for i in 0..<targetSlices {
                let x = min(i * windowWidth, max(0, width - windowWidth))
                let rect = CGRect(x: x, y: 0, width: windowWidth, height: height)
                if let cropped = processedCGImage.cropping(to: rect) {
                    slices.append(cropped)
                }
            }
        case .vertical:
            let windowHeight = max(1, height / targetSlices)
            for i in 0..<targetSlices {
                let y = min(i * windowHeight, max(0, height - windowHeight))
                let rect = CGRect(x: 0, y: y, width: width, height: windowHeight)
                if let cropped = processedCGImage.cropping(to: rect) {
                    slices.append(cropped)
                }
            }
        }
        return slices
    }
    
    /// 120Hz 有機EL（OLED）端末向けに、上下の黒余白を自動カットして画面の上から下まで100%拡大し、
    /// 黒締め＆最大輝度ブーストを施すプリプロセッサ
    private func preparePOVOptimizedCGImage(from image: UIImage, rotate90ForVertical: Bool) -> CGImage? {
        let workSize = CGSize(width: 720, height: 480)
        let width = Int(workSize.width)
        let height = Int(workSize.height)
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var tempRaw = [UInt8](repeating: 0, count: width * height * 4)
        
        guard let tempCtx = CGContext(
            data: &tempRaw,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return image.cgImage
        }
        
        // 1. まず元画像をそのまま展開して、光っている部分の「上端(minY)〜下端(maxY)」を検出する
        tempCtx.setFillColor(UIColor.black.cgColor)
        tempCtx.fill(CGRect(origin: .zero, size: workSize))
        UIGraphicsPushContext(tempCtx)
        // アスペクト比を維持しつつ横幅いっぱいに拡大（端は見切れてOK）
        let imgSize = image.size
        let scale = max(workSize.width / max(imgSize.width, 1), workSize.height / max(imgSize.height, 1)) * 1.15
        let scaledW = imgSize.width * scale
        let scaledH = imgSize.height * scale
        let drawOrigin = CGPoint(x: (workSize.width - scaledW) / 2.0, y: (workSize.height - scaledH) / 2.0)
        image.draw(in: CGRect(origin: drawOrigin, size: CGSize(width: scaledW, height: scaledH)))
        UIGraphicsPopContext()
        
        var minY = height
        var maxY = 0
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                let maxC = max(Int(tempRaw[offset]), max(Int(tempRaw[offset + 1]), Int(tempRaw[offset + 2])))
                if maxC >= 80 {
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                }
            }
        }
        
        // 2. 検出した上下の有効領域（minY...maxY）を切り出し、画面の端から端（高さ100%）まで引き伸ばす
        let croppedTempImage: CGImage?
        if maxY > minY, let fullCG = tempCtx.makeImage() {
            let cropRect = CGRect(x: 0, y: minY, width: width, height: max(1, maxY - minY + 1))
            croppedTempImage = fullCG.cropping(to: cropRect)
        } else {
            croppedTempImage = tempCtx.makeImage()
        }
        
        // 3. 最終キャンバス（サンダーの縦振り時は90度回転サイズ）に端から端まで100%拡大描画
        let finalSize = rotate90ForVertical ? CGSize(width: 480, height: 720) : CGSize(width: 720, height: 480)
        let fWidth = Int(finalSize.width)
        let fHeight = Int(finalSize.height)
        var rawData = [UInt8](repeating: 0, count: fWidth * fHeight * 4)
        
        guard let ctx = CGContext(
            data: &rawData,
            width: fWidth,
            height: fHeight,
            bitsPerComponent: 8,
            bytesPerRow: fWidth * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ), let srcCG = croppedTempImage else {
            return image.cgImage
        }
        
        ctx.setFillColor(UIColor.black.cgColor)
        ctx.fill(CGRect(origin: .zero, size: finalSize))
        
        if rotate90ForVertical {
            // サンダー（縦振り）時：90度回転して横幅・縦幅を端から端までフル充填
            ctx.saveGState()
            ctx.translateBy(x: finalSize.width / 2.0, y: finalSize.height / 2.0)
            ctx.rotate(by: .pi / 2.0)
            ctx.draw(srcCG, in: CGRect(x: -finalSize.height / 2.0, y: -finalSize.width / 2.0, width: finalSize.height, height: finalSize.width))
            ctx.restoreGState()
        } else {
            // 炎・水・草：携帯の長い方の高さを上から下まで100%使ってフル充填
            ctx.draw(srcCG, in: CGRect(origin: .zero, size: finalSize))
        }
        
        // 4. OLED黒締め（輝度80未満は完全消灯0%）＆ 発光部の最大輝度ブースト
        for y in 0..<fHeight {
            for x in 0..<fWidth {
                let offset = (y * fWidth + x) * 4
                let r = Int(rawData[offset])
                let g = Int(rawData[offset + 1])
                let b = Int(rawData[offset + 2])
                let maxC = max(r, max(g, b))
                
                if maxC < 80 {
                    rawData[offset] = 0
                    rawData[offset + 1] = 0
                    rawData[offset + 2] = 0
                } else {
                    let boost = 255.0 / Double(maxC)
                    rawData[offset] = UInt8(min(255.0, Double(r) * boost * 1.25))
                    rawData[offset + 1] = UInt8(min(255.0, Double(g) * boost * 1.25))
                    rawData[offset + 2] = UInt8(min(255.0, Double(b) * boost * 1.25))
                }
            }
        }
        
        return ctx.makeImage()
    }
    
    /// 画像(UIImage)を2次元ブール配列（スライスのリスト）に変換します
    public func generateSlices(
        from image: UIImage,
        targetSlices: Int = 32,
        sliceResolution: Int = 28
    ) -> [[Bool]] {
        let size = CGSize(width: targetSlices, height: sliceResolution)
        UIGraphicsBeginImageContextWithOptions(size, true, 1.0)
        
        guard let ctx = UIGraphicsGetCurrentContext() else {
            UIGraphicsEndImageContext()
            return Array(repeating: Array(repeating: false, count: sliceResolution), count: targetSlices)
        }
        
        ctx.setFillColor(UIColor.black.cgColor)
        ctx.fill(CGRect(origin: .zero, size: size))
        
        image.draw(in: CGRect(origin: .zero, size: size))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        guard let cgImage = resizedImage?.cgImage else {
            return Array(repeating: Array(repeating: false, count: sliceResolution), count: targetSlices)
        }
        
        let width = cgImage.width
        let height = cgImage.height
        let colorSpace = CGColorSpaceCreateDeviceGray()
        var rawData = [UInt8](repeating: 0, count: width * height)
        
        guard let context = CGContext(data: &rawData, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width, space: colorSpace, bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
            return Array(repeating: Array(repeating: false, count: sliceResolution), count: targetSlices)
        }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        var slices: [[Bool]] = Array(repeating: Array(repeating: false, count: height), count: width)
        
        for x in 0..<width {
            for y in 0..<height {
                let byteIndex = y * width + x
                let pixelVal = rawData[byteIndex]
                slices[x][y] = pixelVal > 40 // 閾値調整（少しでも明るければ光らせる）
            }
        }
        
        return slices
    }
    
    /// 日本語等の単一文字を7x7のドットマトリクスへラスタライズ（0cm全画面ストロボ描画用）
    private func rasterizeSingleChar(char: Character, resolution: Int = 7) -> [[Bool]] {
        let width = resolution
        let height = resolution
        let colorSpace = CGColorSpaceCreateDeviceGray()
        var rawData = [UInt8](repeating: 0, count: width * height)
        
        guard let context = CGContext(
            data: &rawData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return Array(repeating: Array(repeating: false, count: height), count: width)
        }
        
        context.setFillColor(gray: 0.0, alpha: 1.0)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        
        UIGraphicsPushContext(context)
        context.saveGState()
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1.0, y: -1.0)
        
        let font = UIFont.systemFont(ofSize: CGFloat(height) * 0.95, weight: .black)
        let attr: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.white
        ]
        let str = NSAttributedString(string: String(char), attributes: attr)
        let size = str.size()
        str.draw(at: CGPoint(x: (CGFloat(width) - size.width) / 2.0, y: (CGFloat(height) - size.height) / 2.0))
        
        context.restoreGState()
        UIGraphicsPopContext()
        
        var matrix: [[Bool]] = []
        for x in 0..<width {
            var col: [Bool] = []
            for y in 0..<height {
                let pixel = rawData[y * width + x]
                col.append(pixel > 120)
            }
            matrix.append(col)
        }
        return matrix
    }
}
