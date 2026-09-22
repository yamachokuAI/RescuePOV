import Foundation
import CoreMotion
import Combine
import UIKit

/// 1サンプル分のモーションデータフレーム
public struct MotionSamplePoint: Codable {
    public let timestamp: TimeInterval
    public let accelX: Double
    public let accelY: Double
    public let accelZ: Double
    public let gyroX: Double
    public let gyroY: Double
    public let gyroZ: Double
    public let estimatedVelocityX: Double
    
    public var csvLine: String {
        String(format: "%.3f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f,%.4f",
               timestamp, accelX, accelY, accelZ, gyroX, gyroY, gyroZ, estimatedVelocityX)
    }
}

/// 往復スイングのヒステリシス解析結果
public struct HysteresisProfile: Codable {
    public var forwardPeakAccel: Double = 0.0     // 往路（右→左など）のピーク加速度
    public var backwardPeakAccel: Double = 0.0    // 復路のピーク加速度
    public var forwardDuration: TimeInterval = 0.25
    public var backwardDuration: TimeInterval = 0.25
    public var asymmetryRatio: Double = 1.0       // 往路と復路の非対称比率 (forward / backward)
    public var normalizedForwardCurve: [Double] = [] // 0.0〜1.0区間の速度進行比率プロファイル
}

/// 実機で10往復スイングを100Hz高精度サンプリングし、
/// ヒステリシス曲線を計測・解析するサンプラー
public final class MotionSampler: ObservableObject {
    public static let shared = MotionSampler()
    
    private let motionManager = CMMotionManager()
    
    @Published public private(set) var isRecording: Bool = false
    @Published public private(set) var sampleCount: Int = 0
    @Published public private(set) var detectedSwings: Int = 0
    @Published public private(set) var targetSwings: Int = 10
    @Published public private(set) var currentAccelX: Double = 0.0
    @Published public private(set) var statusMessage: String = "未計測（10往復計測を開始できます）"
    @Published public private(set) var profile: HysteresisProfile?
    
    public private(set) var samples: [MotionSamplePoint] = []
    
    private var startTime: Date = Date()
    private var lastIntegralTime: Date = Date()
    private var runningVelocityX: Double = 0.0
    private var lastSign: Double = 0.0
    
    private init() {}
    
    /// サンプリングを開始（100Hz）
    public func startSampling(targetSwings: Int = 10) {
        stopSampling()
        
        self.targetSwings = targetSwings
        self.samples.removeAll()
        self.sampleCount = 0
        self.detectedSwings = 0
        self.runningVelocityX = 0.0
        self.isRecording = true
        self.startTime = Date()
        self.lastIntegralTime = Date()
        self.statusMessage = "計測中: 左右に大きく10往復振ってください"
        
        guard motionManager.isDeviceMotionAvailable else {
            self.statusMessage = "エラー: 端末のモーションセンサーが利用できません"
            self.isRecording = false
            return
        }
        
        motionManager.deviceMotionUpdateInterval = 1.0 / 100.0 // 100Hz高精度サンプリング
        motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] motion, error in
            guard let self = self, let motion = motion, self.isRecording else { return }
            self.recordSample(motion)
        }
    }
    
    /// サンプリング停止
    public func stopSampling() {
        if motionManager.isDeviceMotionActive {
            motionManager.stopDeviceMotionUpdates()
        }
        isRecording = false
    }
    
    private func recordSample(_ motion: CMDeviceMotion) {
        let now = Date()
        let dt = now.timeIntervalSince(lastIntegralTime)
        lastIntegralTime = now
        
        let t = now.timeIntervalSince(startTime)
        
        // 重力を除いた純粋な手の振り加速度（userAcceleration）
        let ax = motion.userAcceleration.x
        let ay = motion.userAcceleration.y
        let az = motion.userAcceleration.z
        
        let gx = motion.rotationRate.x
        let gy = motion.rotationRate.y
        let gz = motion.rotationRate.z
        
        // 簡易速度積分（高周波パスフィルタ付き）
        runningVelocityX = (runningVelocityX + ax * 9.8 * dt) * 0.96
        
        let sample = MotionSamplePoint(
            timestamp: t,
            accelX: ax,
            accelY: ay,
            accelZ: az,
            gyroX: gx,
            gyroY: gy,
            gyroZ: gz,
            estimatedVelocityX: runningVelocityX
        )
        
        samples.append(sample)
        sampleCount = samples.count
        currentAccelX = ax
        
        // スイング回数（符号反転ピーク）の簡易カウント
        let sign = ax > 0.4 ? 1.0 : (ax < -0.4 ? -1.0 : 0.0)
        if sign != 0 && sign != lastSign {
            if lastSign != 0 {
                detectedSwings += 1
                if detectedSwings >= targetSwings * 2 { // 往復＝2スイング
                    finishSampling()
                    return
                }
            }
            lastSign = sign
        }
    }
    
    private func finishSampling() {
        stopSampling()
        analyzeHysteresis()
        statusMessage = "計測完了！ \(sampleCount)サンプル取得（ヒステリシス解析済み）"
    }
    
    /// 取得したサンプルからヒステリシス（往路・復路の非対称性と速度曲線）を解析
    public func analyzeHysteresis() {
        guard samples.count > 50 else { return }
        
        var forwardAccels: [Double] = []
        var backwardAccels: [Double] = []
        
        for s in samples {
            if s.accelX > 0.1 {
                forwardAccels.append(s.accelX)
            } else if s.accelX < -0.1 {
                backwardAccels.append(abs(s.accelX))
            }
        }
        
        let maxFwd = forwardAccels.max() ?? 1.0
        let maxBwd = backwardAccels.max() ?? 1.0
        let ratio = maxFwd / max(maxBwd, 0.001)
        
        var newProfile = HysteresisProfile()
        newProfile.forwardPeakAccel = maxFwd
        newProfile.backwardPeakAccel = maxBwd
        newProfile.asymmetryRatio = ratio
        
        // 速度曲線の正規化サンプル（30点）
        var normalized: [Double] = []
        let step = max(samples.count / 30, 1)
        for i in stride(from: 0, to: min(samples.count, 30 * step), by: step) {
            normalized.append(samples[i].estimatedVelocityX)
        }
        newProfile.normalizedForwardCurve = normalized
        
        self.profile = newProfile
    }
    
    /// 計測した全サンプルのCSVテキストを生成
    public func exportCSV() -> String {
        var csv = "timestamp_sec,accel_x_g,accel_y_g,accel_z_g,gyro_x_rad,gyro_y_rad,gyro_z_rad,velocity_x_ms\n"
        for s in samples {
            csv += s.csvLine + "\n"
        }
        return csv
    }
    
    /// サンプリング結果の要約レポート（チャット貼り付け用テキスト）
    public func summaryReport() -> String {
        guard let p = profile else { return "データがまだ計測されていません" }
        return """
        【スイング・ヒステリシス解析結果】
        ・サンプル総数: \(sampleCount) 件 (100Hz)
        ・検出スイング数: \(detectedSwings / 2) 往復
        ・往路（右）ピーク加速度: \(String(format: "%.2f G", p.forwardPeakAccel))
        ・復路（左）ピーク加速度: \(String(format: "%.2f G", p.backwardPeakAccel))
        ・非対称比率（往/復）: \(String(format: "%.2f", p.asymmetryRatio))
        """
    }
}
