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
    /// - Parameter isCondensed: 30cm手首スナップ用。文字幅をギュッと縦長スリムに凝縮し、狭い空間にクッキリ収める
    public func generateSlices(
        text: String,
        direction: POVDirection,
        targetSlices: Int = 48,
        sliceResolution: Int = 20,
        mirrorForViewer: Bool = true,
        isCondensed: Bool = false
    ) -> [[Bool]] {
        guard !text.isEmpty else {
            return Array(repeating: Array(repeating: false, count: sliceResolution), count: targetSlices)
        }
        
        let upper = text.uppercased()
        let canUseDotFont = upper.allSatisfy { dotFont[$0] != nil }
        
        if canUseDotFont {
            return generateFromDotFont(
                text: upper,
                direction: direction,
                targetSlices: targetSlices,
                sliceResolution: sliceResolution,
                mirrorForViewer: mirrorForViewer,
                isCondensed: isCondensed
            )
        } else {
            return generateFromRaster(
                text: text,
                direction: direction,
                targetSlices: targetSlices,
                sliceResolution: sliceResolution,
                mirrorForViewer: mirrorForViewer,
                isCondensed: isCondensed
            )
        }
    }
    
    /// ドットフォントによる確実なシャープ描画（文字潰れ・白残像ゼロ）
    private func generateFromDotFont(
        text: String,
        direction: POVDirection,
        targetSlices: Int,
        sliceResolution: Int,
        mirrorForViewer: Bool,
        isCondensed: Bool
    ) -> [[Bool]] {
        var rawCols: [[Bool]] = []
        
        // 30cm手首スナップ用: マージンと文字間を極限まで引き締める
        let marginCols = isCondensed ? 1 : 4
        let spaceCols = isCondensed ? 1 : 3
        
        for _ in 0..<marginCols {
            rawCols.append([Bool](repeating: false, count: 7))
        }
        
        for char in text {
            if let pattern = dotFont[char] {
                // 30cm手首スナップ用: 5列パターンから[先頭, 中央, 末尾]の3列を抽出し、超スリム縦長フォント化
                let activePattern: [UInt8]
                if isCondensed && pattern.count >= 3 {
                    let midIdx = pattern.count / 2
                    let lastIdx = pattern.count - 1
                    activePattern = [pattern[0], pattern[midIdx], pattern[lastIdx]]
                } else {
                    activePattern = pattern
                }
                
                for col in activePattern {
                    var colDots: [Bool] = []
                    for row in 0..<7 {
                        let isOn = ((col >> (6 - row)) & 1) == 1
                        colDots.append(isOn)
                    }
                    rawCols.append(colDots)
                }
                
                // 文字間スペース（30cm手首用は1列に凝縮）
                for _ in 0..<spaceCols {
                    rawCols.append([Bool](repeating: false, count: 7))
                }
            }
        }
        
        // 後方マージン
        for _ in 0..<marginCols {
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
        
        if mirrorForViewer {
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
        isCondensed: Bool
    ) -> [[Bool]] {
        let charCount = max(text.count, 1)
        // isCondensed時は1文字あたりのスライス幅を通常の約半分（8スライス）に凝縮
        let slicePerChar = isCondensed ? 8 : 14
        let dynamicWidth = max(targetSlices, charCount * slicePerChar + (isCondensed ? 4 : 10))
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
        
        let fontSize = CGFloat(height) * (isCondensed ? 0.90 : 0.78)
        let font: UIFont
        if let hiragino = UIFont(name: "HiraginoSans-W8", size: fontSize) {
            font = hiragino
        } else {
            font = UIFont.systemFont(ofSize: fontSize, weight: .heavy)
        }
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.white,
            .kern: isCondensed ? 0.5 : 3.5
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
