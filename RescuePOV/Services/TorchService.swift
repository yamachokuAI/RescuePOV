import Foundation
import AVFoundation

/// 背面LEDカメラトーチの制御およびSOSモールス信号発信
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
    
    /// 光通信用: 他の状態を変えずにトーチを直接ON/OFF
    public func setTorchDirect(on: Bool) {
        setTorch(on: on)
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
