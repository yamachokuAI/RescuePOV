import Foundation
import CoreMotion
import Combine
import SwiftUI

/// 空間固定表示の動作モード
public enum POVDisplayMode: String, CaseIterable, Identifiable {
    case spatialWindow = "空間固定スライド（推奨）"
    case classicSlit = "高速スリットPOV（従来）"
    
    public var id: String { rawValue }
    
    public var shortTitle: String {
        switch self {
        case .spatialWindow: return "空間固定"
        case .classicSlit: return "スリット残像"
        }
    }
    
    public var description: String {
        switch self {
        case .spatialWindow:
            return "傾き角連動で文字を空中の定位置に固定。残像に頼らず遠方からでも圧倒的にくっきり視認できます。"
        case .classicSlit:
            return "1列ずつ点滅させて網膜の残像で文字を結像させる方式。"
        }
    }
}

/// ジャイロ・姿勢センサーで端末の傾き角をリアルタイム追従し、
/// 空間固定ウィンドウ表示のためのオフセットを計算するトラッカー
public final class SpatialMotionTracker: ObservableObject {
    public static let shared = SpatialMotionTracker()
    
    private let motionManager = CMMotionManager()
    
    // 公開プロパティ
    /// 空間上の正規化オフセット (-1.0: 左端, 0.0: 中央, +1.0: 右端)
    @Published public private(set) var normalizedOffset: CGFloat = 0.0
    /// 現在の検出傾き角度（度数法）
    @Published public private(set) var currentAngleDegrees: Double = 0.0
    /// 振りの勢い・角速度
    @Published public private(set) var angularSpeed: Double = 0.0
    /// センサーがアクティブかどうか
    @Published public private(set) var isTracking: Bool = false
    
    // 設定
    /// フルストロークに対応する最大振り角（ラジアン）: デフォルト約30度 (0.52 rad)
    public var maxSwingAngleRadians: Double = 0.52
    
    // 内部追従パラメータ
    private var centerAngle: Double = 0.0
    private var isCalibrated: Bool = false
    private var simulationTimer: Timer?
    private var simulationPhase: Double = 0.0
    private var lastUpdateTime: Date = Date()
    
    private init() {}
    
    /// トラッキング開始
    public func start(direction: POVDirection = .horizontal) {
        stop()
        isTracking = true
        isCalibrated = false
        centerAngle = 0.0
        
        if motionManager.isDeviceMotionAvailable {
            motionManager.deviceMotionUpdateInterval = 1.0 / 60.0 // 60Hz
            motionManager.showsDeviceMovementDisplay = true
            
            motionManager.startDeviceMotionUpdates(
                using: .xArbitraryZVertical,
                to: .main
            ) { [weak self] motion, error in
                guard let self = self, let motion = motion else { return }
                self.processDeviceMotion(motion, direction: direction)
            }
        } else {
            // シミュレータまたはセンサー未搭載時の自動スイープ（プレビュー用）
            startSimulation()
        }
    }
    
    /// トラッキング停止
    public func stop() {
        if motionManager.isDeviceMotionActive {
            motionManager.stopDeviceMotionUpdates()
        }
        simulationTimer?.invalidate()
        simulationTimer = nil
        isTracking = false
        normalizedOffset = 0.0
        currentAngleDegrees = 0.0
    }
    
    /// 端末の姿勢データを解析し、正規化オフセットを算出
    private func processDeviceMotion(_ motion: CMDeviceMotion, direction: POVDirection) {
        // 横振りの場合: 画面法線/ロール角（左右の傾き）
        // 縦振りの場合: ピッチ角（上下の傾き）
        let rawAngle: Double
        let rawRotationRate: Double
        
        switch direction {
        case .horizontal:
            rawAngle = motion.attitude.roll
            rawRotationRate = motion.rotationRate.z
        case .vertical:
            rawAngle = motion.attitude.pitch
            rawRotationRate = motion.rotationRate.x
        }
        
        // 初回は現在角度を中心としてキャリブレーション
        if !isCalibrated {
            centerAngle = rawAngle
            isCalibrated = true
        } else {
            // 振りの中心がずれないよう、非常にゆるやかな指数平滑で中心を自動補正
            centerAngle = centerAngle * 0.985 + rawAngle * 0.015
        }
        
        let delta = rawAngle - centerAngle
        self.currentAngleDegrees = delta * (180.0 / .pi)
        self.angularSpeed = abs(rawRotationRate)
        
        // 最大振り角度で正規化 (-1.0 ... +1.0)
        let normalized = delta / maxSwingAngleRadians
        let clamped = CGFloat(min(max(normalized, -1.2), 1.2))
        
        self.normalizedOffset = clamped
    }
    
    /// シミュレーション（センサーがない場合）
    private func startSimulation() {
        simulationTimer?.invalidate()
        simulationPhase = 0.0
        
        simulationTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            guard let self = self, self.isTracking else { return }
            self.simulationPhase += 0.08
            let val = sin(self.simulationPhase)
            self.normalizedOffset = CGFloat(val)
            self.currentAngleDegrees = val * 30.0
        }
    }
    
    /// 振りの中心（ニュートラル位置）を手動で即座に再設定
    public func recenter() {
        isCalibrated = false
    }
}
