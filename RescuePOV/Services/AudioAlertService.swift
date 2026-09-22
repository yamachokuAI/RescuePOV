import Foundation
import AVFoundation

/// 非常用レスキューホイッスルおよび大音量警報サイレン合成サービス
public final class AudioAlertService: ObservableObject {
    public static let shared = AudioAlertService()
    
    @Published public private(set) var isPlaying: Bool = false
    @Published public var alertMode: AlertMode = .whistle
    
    public enum AlertMode: String, CaseIterable, Identifiable {
        case whistle = "レスキューホイッスル (3kHz)"
        case siren = "救助サイレン"
        
        public var id: String { rawValue }
    }
    
    private var audioEngine: AVAudioEngine?
    private var sourceNode: AVAudioSourceNode?
    private var phase: Double = 0.0
    private var sampleRate: Double = 44100.0
    private var timeSeconds: Double = 0.0
    
    private init() {}
    
    /// 警報音の再生/停止切り替え
    public func toggleAlert() {
        if isPlaying {
            stop()
        } else {
            start()
        }
    }
    
    public func start() {
        stop()
        
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.duckOthers])
            try session.setActive(true)
        } catch {
            print("オーディオセッション初期化エラー: \(error)")
        }
        
        let engine = AVAudioEngine()
        let format = engine.outputNode.outputFormat(forBus: 0)
        sampleRate = format.sampleRate > 0 ? format.sampleRate : 44100.0
        phase = 0.0
        timeSeconds = 0.0
        
        let srcNode = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self = self else { return noErr }
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            
            for frame in 0..<Int(frameCount) {
                let t = self.timeSeconds + Double(frame) / self.sampleRate
                let sample: Float
                
                switch self.alertMode {
                case .whistle:
                    // 3回吹いて休む（レスキュー国際標準合図: 吹鳴 吹鳴 吹鳴 ... 休止）
                    let cycle = fmod(t, 2.0) // 2秒周期
                    let isBlowing = (cycle < 0.4) || (cycle >= 0.5 && cycle < 0.9) || (cycle >= 1.0 && cycle < 1.4)
                    
                    if isBlowing {
                        // 2850Hzの鋭い笛の音 + 微小な周波数ゆらぎ
                        let freq = 2850.0 + 150.0 * sin(2.0 * .pi * 8.0 * t)
                        self.phase += 2.0 * .pi * freq / self.sampleRate
                        if self.phase > 2.0 * .pi { self.phase -= 2.0 * .pi }
                        // 矩形波と正弦波のブレンドで鋭いホイッスルの音色
                        sample = Float(sin(self.phase) * 0.7 + (sin(self.phase) > 0 ? 0.2 : -0.2))
                    } else {
                        sample = 0.0
                    }
                    
                case .siren:
                    // 600Hz 〜 1400Hz の周期的な急上昇サイレン
                    let cycle = fmod(t, 0.8) / 0.8 // 0.8秒で一周期
                    let freq = 600.0 + 800.0 * cycle
                    self.phase += 2.0 * .pi * freq / self.sampleRate
                    if self.phase > 2.0 * .pi { self.phase -= 2.0 * .pi }
                    sample = Float(sin(self.phase) * 0.85)
                }
                
                for buffer in ablPointer {
                    let buf: UnsafeMutableBufferPointer<Float> = UnsafeMutableBufferPointer(buffer)
                    buf[frame] = sample
                }
            }
            
            self.timeSeconds += Double(frameCount) / self.sampleRate
            return noErr
        }
        
        engine.attach(srcNode)
        engine.connect(srcNode, to: engine.mainMixerNode, format: format)
        
        do {
            try engine.start()
            self.audioEngine = engine
            self.sourceNode = srcNode
            self.isPlaying = true
        } catch {
            print("オーディオエンジン開始エラー: \(error)")
        }
    }
    
    public func stop() {
        if let engine = audioEngine, engine.isRunning {
            engine.stop()
        }
        audioEngine = nil
        sourceNode = nil
        isPlaying = false
    }
    
    deinit {
        stop()
    }
}
