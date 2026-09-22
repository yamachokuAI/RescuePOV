import Foundation
import CoreMotion
import Combine
import QuartzCore

/// スイングの状態
public enum SwingPhase {
    case forward   // 往路（文字スキャン発光中）
    case backward  // 復路（ブランク/消灯区間）
}

/// 端末の角速度・姿勢から「物理空間位置」をリアルタイム算出し、
/// 空間座標に1対1で文字スライスを同期表示する位置駆動型モーションディテクタ
public final class MotionDetector: ObservableObject {
    public static let shared = MotionDetector()
    
    private let motionManager = CMMotionManager()
    
    // 公開プロパティ
    @Published public private(set) var currentPhase: SwingPhase = .forward
    @Published public private(set) var strokeProgress: Double = 0.0             // 空間位置の進行度 (0.0: 左端 ... 1.0: 右端)
    @Published public private(set) var swingIntensity: Double = 0.0             // 振りの勢い（角速度 rad/s または G）
    @Published public private(set) var currentAngleDegrees: Double = 0.0        // 現在の空間角度（度）
    @Published public private(set) var strokeAngleRange: Double = 95.0          // 学習されたスイング振れ幅（度）
    @Published public private(set) var isMotionActive: Bool = false
    
    // モード設定
    @Published public var invertSwingDirection: Bool = false                    // 左右スイング判定の反転
    @Published public var strokeSensitivity: Double = 1.0                       // 振り幅感度調整 (0.7〜1.5)
    
    // 内部トラッキング用
    private var currentTheta: Double = 0.0
    private var leftTurnAngle: Double = -0.80   // 左端（rad）約 -46度
    private var rightTurnAngle: Double = 0.85   // 右端（rad）約 +49度
    private var learnedStrokeWidth: Double = 1.65 // 平均振れ幅（rad）約 95度
    private var lastGyroZ: Double = 0.0
    private var lastUpdateTime: Date = Date()
    private var isCalibrated: Bool = false
    private var lastTurnTime: Date = Date()
    
    // シミュレーション（センサー未搭載環境）用
    private var simulationTimer: Timer?
    private var simulationPhase: Double = 0.0
    
    private init() {}
    
    /// モーション検知を開始（100Hz高精度位置トラッキング）
    public func start(direction: POVDirection) {
        stop()
        
        isMotionActive = true
        currentTheta = 0.0
        lastGyroZ = 0.0
        lastUpdateTime = Date()
        lastTurnTime = Date()
        isCalibrated = false
        
        if motionManager.isDeviceMotionAvailable {
            motionManager.deviceMotionUpdateInterval = 1.0 / 100.0 // 100Hz高精度トラッキング
            motionManager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { [weak self] motion, error in
                guard let self = self, let motion = motion, self.isMotionActive else { return }
                self.processDeviceMotion(motion, direction: direction)
            }
        } else {
            startSimulation()
        }
    }
    
    /// モーション検知を停止
    public func stop() {
        if motionManager.isDeviceMotionActive {
            motionManager.stopDeviceMotionUpdates()
        }
        simulationTimer?.invalidate()
        simulationTimer = nil
        isMotionActive = false
        strokeProgress = 0.0
        swingIntensity = 0.0
    }
    
    /// 100Hzで角速度から端末の物理空間位置（X座標・角度）を直接算出
    private func processDeviceMotion(_ motion: CMDeviceMotion, direction: POVDirection) {
        let now = Date()
        let dt = min(now.timeIntervalSince(lastUpdateTime), 0.05)
        lastUpdateTime = now
        
        // 横振りの場合: Z軸角速度 (rad/s) が腕の振り角度とダイレクトに比例
        // 縦振りの場合: X軸角速度
        let rawGyro: Double
        switch direction {
        case .horizontal:
            rawGyro = motion.rotationRate.z
        case .vertical:
            rawGyro = motion.rotationRate.x
        }
        
        let gyro = invertSwingDirection ? -rawGyro : rawGyro
        self.swingIntensity = abs(gyro)
        
        // 角度（空間位置）の台形積分: theta += gyro * dt
        currentTheta += (gyro + lastGyroZ) * 0.5 * dt
        self.currentAngleDegrees = currentTheta * (180.0 / .pi)
        
        // 折り返し（ゼロクロス）の検出
        // gyroが正負を跨いだ瞬間 ＝ スイングの端で停止した瞬間
        if (lastGyroZ <= 0.05 && gyro > 0.05) || (lastGyroZ >= -0.05 && gyro < -0.05) {
            handleTurnaround(isMovingPositive: gyro > 0, turnaroundTheta: currentTheta, now: now)
        }
        
        // 【位置に応じた動作】
        // gyro > 0: 左から右へ移動中（往路） ＝ 画面を空間位置に合わせて発光！
        // gyro < 0: 右から左へ戻る（復路） ＝ 画面を消灯（残像ブレ防止）
        if gyro > 0.3 {
            self.currentPhase = .forward
            
            // 物理空間位置の算出 (0.0: 左端 ... 1.0: 右端)
            let width = max(learnedStrokeWidth * strokeSensitivity, 0.8)
            let relativeAngle = currentTheta - leftTurnAngle
            let progress = relativeAngle / width
            
            // 空間位置 [0.0 ... 1.0] にダイレクト連動
            self.strokeProgress = min(max(progress, 0.0), 1.0)
            
        } else if gyro < -0.3 {
            // 復路は消灯
            self.currentPhase = .backward
            self.strokeProgress = 0.0
        }
        
        lastGyroZ = gyro
    }
    
    /// スイングの折り返し処理（振れ幅の自動学習とドリフト除去）
    private func handleTurnaround(isMovingPositive: Bool, turnaroundTheta: Double, now: Date) {
        let interval = now.timeIntervalSince(lastTurnTime)
        guard interval > 0.15 else { return } // 150ms以内のチャタリングノイズ除去
        lastTurnTime = now
        
        if isMovingPositive {
            // 「右→左」から「左→右」への切り返し（左端に到達！）
            leftTurnAngle = turnaroundTheta
            let width = abs(rightTurnAngle - leftTurnAngle)
            if width > 0.7 && width < 2.5 {
                learnedStrokeWidth = learnedStrokeWidth * 0.7 + width * 0.3
                strokeAngleRange = learnedStrokeWidth * (180.0 / .pi)
            }
        } else {
            // 「左→右」から「右→左」への切り返し（右端に到達！）
            rightTurnAngle = turnaroundTheta
            let width = abs(rightTurnAngle - leftTurnAngle)
            if width > 0.7 && width < 2.5 {
                learnedStrokeWidth = learnedStrokeWidth * 0.7 + width * 0.3
                strokeAngleRange = learnedStrokeWidth * (180.0 / .pi)
            }
        }
    }
    
    /// シミュレーション（机上・プレビュー用）
    private func startSimulation() {
        simulationTimer?.invalidate()
        simulationPhase = 0.0
        
        simulationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self = self, self.isMotionActive else { return }
            self.simulationPhase += 0.09
            let s = sin(self.simulationPhase)
            let c = cos(self.simulationPhase)
            
            if c > 0 {
                // 往路
                self.currentPhase = .forward
                self.strokeProgress = (s + 1.0) / 2.0
            } else {
                // 復路
                self.currentPhase = .backward
                self.strokeProgress = 0.0
            }
            self.currentAngleDegrees = s * 50.0
        }
    }
}
