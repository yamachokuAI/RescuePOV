import UIKit
import AVFoundation

public final class MagicImageGenerator {
    
    public static func generateImage(for element: MagicElement, size: CGSize = CGSize(width: 800, height: 400)) -> UIImage {
        // XcodeのAssets.xcassetsからユーザーの静止画画像を読み込む
        // 命名規則: "pov_fire", "pov_water", "pov_thunder", "pov_grass"
        let imageName: String
        switch element {
        case .fire: imageName = "pov_fire"
        case .water: imageName = "pov_water"
        case .thunder: imageName = "pov_thunder"
        case .grass: imageName = "pov_grass"
        }
        
        if let customImage = UIImage(named: imageName) {
            return customImage
        }
        
        // 画像ファイルが存在しない場合のフォールバック（プログラム描画）
        UIGraphicsBeginImageContextWithOptions(size, true, 0)
        guard let ctx = UIGraphicsGetCurrentContext() else { return UIImage() }
        
        ctx.setFillColor(UIColor.black.cgColor)
        ctx.fill(CGRect(origin: .zero, size: size))
        
        switch element {
        case .fire:
            drawFire(in: ctx, size: size)
        case .water:
            drawWater(in: ctx, size: size)
        case .thunder:
            drawThunder(in: ctx, size: size)
        case .grass:
            drawGrass(in: ctx, size: size)
        }
        
        let image = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
        UIGraphicsEndImageContext()
        return image
    }
    
    private static func drawFire(in ctx: CGContext, size: CGSize) {
        // 超極太の炎（赤と黄色の太い波）
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        
        ctx.setLineWidth(120)
        ctx.setStrokeColor(UIColor.red.cgColor)
        for i in 0..<6 {
            let x = CGFloat(i) * (size.width / 5.0)
            ctx.move(to: CGPoint(x: x, y: size.height + 50))
            ctx.addLine(to: CGPoint(x: x + CGFloat.random(in: -100...100), y: size.height * 0.2))
            ctx.strokePath()
        }
        
        ctx.setLineWidth(60)
        ctx.setStrokeColor(UIColor.yellow.cgColor)
        for i in 0..<6 {
            let x = CGFloat(i) * (size.width / 5.0)
            ctx.move(to: CGPoint(x: x, y: size.height + 50))
            ctx.addLine(to: CGPoint(x: x + CGFloat.random(in: -50...50), y: size.height * 0.4))
            ctx.strokePath()
        }
    }
    
    private static func drawWater(in ctx: CGContext, size: CGSize) {
        // 超極太の水（シアンと白の太い横波）
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        
        ctx.setLineWidth(100)
        ctx.setStrokeColor(UIColor.cyan.cgColor)
        for i in 0..<5 {
            let y = CGFloat(i) * (size.height / 4.0)
            ctx.move(to: CGPoint(x: -50, y: y))
            ctx.addLine(to: CGPoint(x: size.width + 50, y: y + CGFloat.random(in: -100...100)))
            ctx.strokePath()
        }
        
        ctx.setLineWidth(40)
        ctx.setStrokeColor(UIColor.white.cgColor)
        for i in 0..<5 {
            let y = CGFloat(i) * (size.height / 4.0)
            ctx.move(to: CGPoint(x: -50, y: y + 20))
            ctx.addLine(to: CGPoint(x: size.width + 50, y: y + CGFloat.random(in: -50...50)))
            ctx.strokePath()
        }
    }
    
    private static func drawThunder(in ctx: CGContext, size: CGSize) {
        // 超極太の雷（黄色と白の太いギザギザ）
        ctx.setLineCap(.square)
        ctx.setLineJoin(.miter)
        
        ctx.setLineWidth(100)
        ctx.setStrokeColor(UIColor.yellow.cgColor)
        for i in 0..<4 {
            let x = CGFloat(i) * (size.width / 3.0)
            ctx.move(to: CGPoint(x: x, y: -50))
            ctx.addLine(to: CGPoint(x: x + CGFloat.random(in: -100...100), y: size.height * 0.5))
            ctx.addLine(to: CGPoint(x: x + CGFloat.random(in: -100...100), y: size.height + 50))
            ctx.strokePath()
        }
        
        ctx.setLineWidth(40)
        ctx.setStrokeColor(UIColor.white.cgColor)
        for i in 0..<4 {
            let x = CGFloat(i) * (size.width / 3.0)
            ctx.move(to: CGPoint(x: x, y: -50))
            ctx.addLine(to: CGPoint(x: x + CGFloat.random(in: -50...50), y: size.height * 0.5))
            ctx.addLine(to: CGPoint(x: x + CGFloat.random(in: -50...50), y: size.height + 50))
            ctx.strokePath()
        }
    }
    
    private static func drawGrass(in ctx: CGContext, size: CGSize) {
        // 超極太の草（黄緑の太い渦巻きと巨大な丸）
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        
        ctx.setLineWidth(120)
        ctx.setStrokeColor(UIColor.green.cgColor)
        for i in 0..<4 {
            let x = CGFloat(i) * (size.width / 3.0)
            ctx.move(to: CGPoint(x: x, y: size.height + 50))
            ctx.addLine(to: CGPoint(x: x + CGFloat.random(in: -150...150), y: size.height * 0.5))
            ctx.addLine(to: CGPoint(x: x + CGFloat.random(in: -150...150), y: -50))
            ctx.strokePath()
        }
        
        // 巨大な葉っぱの代わりの円
        ctx.setFillColor(UIColor(red: 0.5, green: 1.0, blue: 0.0, alpha: 1.0).cgColor)
        for _ in 0..<8 {
            let x = CGFloat.random(in: 0...size.width)
            let y = CGFloat.random(in: 0...size.height)
            ctx.fillEllipse(in: CGRect(x: x - 60, y: y - 60, width: 120, height: 120))
        }
    }
}

public final class AudioManager {
    public static let shared = AudioManager()
    private var audioPlayer: AVAudioPlayer?
    
    private init() {}
    
    /// 魔法の属性に応じた音を再生します
    public func playMagicSound(for element: MagicElement) {
        let soundName: String
        switch element {
        case .fire: soundName = "sound_fire"
        case .water: soundName = "sound_water"
        case .thunder: soundName = "sound_thunder"
        case .grass: soundName = "sound_grass"
        }
        
        // Bundle内から .m4a ファイルを探す
        guard let url = Bundle.main.url(forResource: soundName, withExtension: "m4a") else {
            print("Audio file '\(soundName).m4a' not found in bundle. Make sure it's added to the target!")
            return
        }
        
        DispatchQueue.global(qos: .background).async {
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [])
                try AVAudioSession.sharedInstance().setActive(true)
                
                let player = try AVAudioPlayer(contentsOf: url)
                player.numberOfLoops = -1 // 無限ループ
                player.prepareToPlay()
                player.play()
                
                DispatchQueue.main.async {
                    self.audioPlayer = player
                }
                
            } catch {
                print("Failed to load or play audio: \(error.localizedDescription)")
            }
        }
    }
    
    public func stopMagicSound() {
        audioPlayer?.stop()
    }
}
