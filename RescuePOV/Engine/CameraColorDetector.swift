import AVFoundation
import UIKit

public final class CameraColorDetector: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    public static let shared = CameraColorDetector()
    
    @Published public var detectedElement: MagicElement? = nil
    @Published public var isRunning: Bool = false
    
    private var lightHistory: [Bool] = []
    private var detectedColorCounts: [MagicElement: Int] = [:]
    
    private let captureSession = AVCaptureSession()
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "com.rescuepov.cameraColorQueue")
    
    public override init() {
        super.init()
        setupSession()
    }
    
    private func setupSession() {
        captureSession.sessionPreset = .low // 解像度は最低で良い（色だけ欲しいので）
        
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera) else {
            return
        }
        
        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
        }
        
        if captureSession.canAddOutput(videoDataOutput) {
            captureSession.addOutput(videoDataOutput)
            videoDataOutput.setSampleBufferDelegate(self, queue: sessionQueue)
            // 32BGRAフォーマット指定
            videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
            videoDataOutput.alwaysDiscardsLateVideoFrames = true
        }
    }
    
    public func start() {
        guard !captureSession.isRunning else { return }
        sessionQueue.async {
            self.captureSession.startRunning()
            DispatchQueue.main.async {
                self.isRunning = true
                self.lightHistory.removeAll()
                self.detectedColorCounts.removeAll()
                self.detectedElement = nil
            }
        }
    }
    
    public func stop() {
        guard captureSession.isRunning else { return }
        sessionQueue.async {
            self.captureSession.stopRunning()
            DispatchQueue.main.async {
                self.isRunning = false
                self.detectedElement = nil
            }
        }
    }
    
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
        
        let buffer = baseAddress.assumingMemoryBound(to: UInt8.self)
        
        var totalR: Int = 0
        var totalG: Int = 0
        var totalB: Int = 0
        var brightPixelCount: Int = 0
        
        // ピクセルを間引いてサンプリング（高速化）
        let step = 8
        for y in stride(from: 0, to: height, by: step) {
            let rowOffset = y * bytesPerRow
            for x in stride(from: 0, to: width, by: step) {
                let pixelOffset = rowOffset + x * 4
                let b = Int(buffer[pixelOffset])
                let g = Int(buffer[pixelOffset + 1])
                let r = Int(buffer[pixelOffset + 2])
                
                // 明るいピクセル（相手のPOV発光）のみを抽出
                let luma = (r * 299 + g * 587 + b * 114) / 1000
                if luma > 180 { // 閾値（真っ暗闇の中で光っているピクセル）
                    totalR += r
                    totalG += g
                    totalB += b
                    brightPixelCount += 1
                }
            }
        }
        
        let isLightDetected = brightPixelCount > 10
        var currentElement: MagicElement? = nil
        
        if isLightDetected {
            let avgR = CGFloat(totalR) / CGFloat(brightPixelCount) / 255.0
            let avgG = CGFloat(totalG) / CGFloat(brightPixelCount) / 255.0
            let avgB = CGFloat(totalB) / CGFloat(brightPixelCount) / 255.0
            
            let color = UIColor(red: avgR, green: avgG, blue: avgB, alpha: 1.0)
            var hue: CGFloat = 0
            var saturation: CGFloat = 0
            var brightness: CGFloat = 0
            var alpha: CGFloat = 0
            
            color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
            
            if hue > 0.9 || hue <= 0.1 {
                currentElement = .fire
            } else if hue > 0.1 && hue <= 0.2 {
                currentElement = .thunder
            } else if hue > 0.2 && hue <= 0.4 {
                currentElement = .grass
            } else {
                currentElement = .water
            }
        }
        
        DispatchQueue.main.async {
            self.lightHistory.append(isLightDetected)
            // 約1秒間（30フレーム）の履歴を保持
            if self.lightHistory.count > 30 {
                self.lightHistory.removeFirst()
            }
            
            if let el = currentElement {
                self.detectedColorCounts[el, default: 0] += 1
            }
            
            // 光通信復調 (Demodulation): POVスイング特有の「点滅パターン」を検証
            var transitions = 0
            var wasLight = false
            for light in self.lightHistory {
                if light && !wasLight {
                    transitions += 1
                }
                wasLight = light
            }
            
            // 最低2回の点滅（振りの往復に相当）がないと、壁などの不正な定常光とみなして無効化
            if transitions >= 2 {
                if let best = self.detectedColorCounts.max(by: { $0.value < $1.value })?.key {
                    self.detectedElement = best
                }
            }
        }
    }
}
