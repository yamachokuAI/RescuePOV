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
    
    // 定番レスキュー文字の超精密5x7ドットビットマップ辞書（黒の隙間が保証される）
    private let dotFont: [Character: [UInt8]] = [
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
        "T": [0b1000000, 0b1000000, 0b1111111, 0b1000000, 0b1000000],
        "1": [0b0010001, 0b0100001, 0b1111111, 0b0000001, 0b0000001],
        "0": [0b0111110, 0b1000001, 0b1000001, 0b1000001, 0b0111110],
        "9": [0b0100001, 0b1001001, 0b1001001, 0b1001001, 0b0111110],
        "!": [0b0000000, 0b1011111, 0b0000000, 0b0000000, 0b0000000],
        "?": [0b0100000, 0b1000000, 0b1001101, 0b0110000, 0b0000000],
        " ": [0b0000000, 0b0000000, 0b0000000]
    ]
    
    private init() {}
    
    /// テキストを2次元ブール配列（スライスのリスト）に変換します
    public func generateSlices(
        text: String,
        direction: POVDirection,
        targetSlices: Int = 48,
        sliceResolution: Int = 20,
        mirrorForViewer: Bool = true
    ) -> [[Bool]] {
        guard !text.isEmpty else {
            return Array(repeating: Array(repeating: false, count: sliceResolution), count: targetSlices)
        }
        
        let upper = text.uppercased()
        
        // 1. 全ての文字がドットフォント辞書に含まれるか確認
        let canUseDotFont = upper.allSatisfy { dotFont[$0] != nil }
        
        if canUseDotFont {
            return generateFromDotFont(
                text: upper,
                direction: direction,
                targetSlices: targetSlices,
                sliceResolution: sliceResolution,
                mirrorForViewer: mirrorForViewer
            )
        } else {
            return generateFromRaster(
                text: text,
                direction: direction,
                targetSlices: targetSlices,
                sliceResolution: sliceResolution,
                mirrorForViewer: mirrorForViewer
            )
        }
    }
    
    /// ドットフォントによる確実なシャープ描画（文字潰れ・白残像ゼロ）
    private func generateFromDotFont(
        text: String,
        direction: POVDirection,
        targetSlices: Int,
        sliceResolution: Int,
        mirrorForViewer: Bool
    ) -> [[Bool]] {
        var rawCols: [[Bool]] = []
        
        // 前後マージン（消灯列）
        let marginCols = 4
        for _ in 0..<marginCols {
            rawCols.append([Bool](repeating: false, count: 7))
        }
        
        for char in text {
            if let pattern = dotFont[char] {
                for col in pattern {
                    var colDots: [Bool] = []
                    for row in 0..<7 {
                        let isOn = ((col >> (6 - row)) & 1) == 1
                        colDots.append(isOn)
                    }
                    rawCols.append(colDots)
                }
                // 文字間スペース（3列の完全消灯黒）
                rawCols.append([Bool](repeating: false, count: 7))
                rawCols.append([Bool](repeating: false, count: 7))
                rawCols.append([Bool](repeating: false, count: 7))
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
                // 画面の縦中央に文字を配置（上下に余白）
                let marginY = 3
                let activeHeight = sliceResolution - marginY * 2
                if y >= marginY && y < (marginY + activeHeight) {
                    let srcY = Int(Double(y - marginY) / Double(activeHeight) * 7.0)
                    let clampedSrcY = min(max(srcY, 0), 6)
                    scaledCol.append(col[clampedSrcY])
                } else {
                    scaledCol.append(false)
                }
            }
            resultSlices.append(scaledCol)
        }
        
        // 観察者（対向者）視点に合わせて左右反転
        if mirrorForViewer {
            resultSlices.reverse()
        }
        
        return resultSlices
    }
    
    /// 日本語など自由入力用の高コントラストラスタライズ
    private func generateFromRaster(
        text: String,
        direction: POVDirection,
        targetSlices: Int,
        sliceResolution: Int,
        mirrorForViewer: Bool
    ) -> [[Bool]] {
        let width = targetSlices
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
        
        // 細めのウェイトにして線が太りすぎないように調整
        let fontSize = CGFloat(height) * 0.70
        let font = UIFont.systemFont(ofSize: fontSize, weight: .bold)
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor.white
        ]
        
        let attributedString = NSAttributedString(string: text, attributes: attributes)
        let textSize = attributedString.size()
        
        let drawX = max((CGFloat(width) - textSize.width) / 2.0, 2.0)
        let drawY = (CGFloat(height) - textSize.height) / 2.0
        
        attributedString.draw(at: CGPoint(x: drawX, y: drawY))
        
        context.restoreGState()
        UIGraphicsPopContext()
        
        var slices: [[Bool]] = []
        let threshold: UInt8 = 160 // 閾値を高めにして細くクッキリした線だけを抽出
        
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
}
