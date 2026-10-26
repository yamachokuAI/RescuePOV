import Foundation
import AVFoundation

/// 背面LEDカメラトーチの制御およびSOSモールス信号発信・メトロノーム同期パルス
public final class TorchService: ObservableObject {
    public static let shared = TorchService()
    
    @Published public private(set) var isTorchOn: Bool = false
    @Published public private(set) var isSOSActive: Bool = false
    
    private var sosTimer: Timer?
    private var sosSequence: [Bool] = [] // true: 点灯, false: 消灯
    private var currentStepIndex: Int = 0
    
    private init() {
        buildSOSSequence()
    }
    
    /// SOSモールスシーケンスの構築 (・: 1単位, ー: 3単位, 間隔: 1単位)
    private func buildSOSSequence() {
        var seq: [Bool] = []
        let dot = [true, false]
        let dash = [true, true, true, false]
        let charGap = [false, false] // 文字間 (計3単位の休止)
        let wordGap = [false, false, false, false, false, false] // 単語間休止
        
        // S: ・ ・ ・
        seq.append(contentsOf: dot)
        seq.append(contentsOf: dot)
        seq.append(contentsOf: dot)
        seq.append(contentsOf: charGap)
        
        // O: ー ー ー
        seq.append(contentsOf: dash)
        seq.append(contentsOf: dash)
        seq.append(contentsOf: dash)
        seq.append(contentsOf: charGap)
        
        // S: ・ ・ ・
        seq.append(contentsOf: dot)
        seq.append(contentsOf: dot)
        seq.append(contentsOf: dot)
        seq.append(contentsOf: wordGap)
        
        self.sosSequence = seq
    }
    
    /// 常時点灯の切り替え
    public func toggleTorch() {
        if isSOSActive { stopSOS() }
        setTorch(on: !isTorchOn)
    }
    
    /// SOSモールス信号点滅の開始 / 停止
    public func toggleSOS() {
        if isSOSActive {
            stopSOS()
        } else {
            startSOS()
        }
    }
    
    public func startSOS() {
        stopSOS()
        isSOSActive = true
        currentStepIndex = 0
        
        // 1単位時間 = 120ms (高速で注意を惹くリズム)
        sosTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let state = self.sosSequence[self.currentStepIndex]
            self.setTorch(on: state)
            self.currentStepIndex = (self.currentStepIndex + 1) % self.sosSequence.count
        }
    }
    
    public func stopSOS() {
        sosTimer?.invalidate()
        sosTimer = nil
        isSOSActive = false
        setTorch(on: false)
    }
    
    /// 光通信や直接制御用
    public func setTorchDirect(on: Bool) {
        setTorch(on: on)
    }
    
    private let metronomeQueue = DispatchQueue(label: "com.rescuepov.metronome.flash", qos: .userInteractive)
    
    /// POVスイング端点メトロノーム用：最大光量（1.0）で0.01秒間（10ms：前回の1/10）だけ超短パルス閃光させる
    public func pulseMetronome(level: Float = 1.0, duration: TimeInterval = 0.01) {
        guard !isTorchOn, !isSOSActive else { return }
        
        metronomeQueue.async { [weak self] in
            guard let self = self, !self.isTorchOn, !self.isSOSActive else { return }
            guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
            
            do {
                try device.lockForConfiguration()
                let maxLevel = AVCaptureDevice.maxAvailableTorchLevel
                let safeLevel = max(0.01, min(level, maxLevel))
                try device.setTorchModeOn(level: safeLevel)
                device.unlockForConfiguration()
            } catch {
                return
            }
            
            // 正確に0.01秒（10,000マイクロ秒）後に消灯
            let microSec = UInt32(max(1_000, min(duration * 1_000_000, 100_000)))
            usleep(microSec)
            
            guard !self.isTorchOn, !self.isSOSActive else { return }
            do {
                try device.lockForConfiguration()
                device.torchMode = .off
                device.unlockForConfiguration()
            } catch {}
        }
    }
    
    private func setTorch(on: Bool) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else {
            DispatchQueue.main.async { self.isTorchOn = on }
            return
        }
        
        do {
            try device.lockForConfiguration()
            if on {
                try device.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel)
            } else {
                device.torchMode = .off
            }
            device.unlockForConfiguration()
            DispatchQueue.main.async { self.isTorchOn = on }
        } catch {
            print("トーチ設定エラー: \(error.localizedDescription)")
        }
    }
    
    deinit {
        stopSOS()
    }
}
