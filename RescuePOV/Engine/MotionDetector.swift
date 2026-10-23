import Foundation
import CoreMotion
import Combine
import QuartzCore

/// スイングの状態
public enum SwingPhase {
    case forward   // 往路（文字スキャン発光中）
    case backward  // 復路（ブランク/消灯区間）
}

/// 振れ幅と疲労度に応じたマルチアダプティブ・スイングモード
public enum POVDisplayRangeMode: String, CaseIterable, Identifiable {
    case auto = "AI自動適応（推奨）"
    case compactSnap = "手首30cm浮き出しホログラム"
    case wide = "頭上ワイド（60〜100cm）"
    case semiCircle = "半円形（180度アーチ）"
    case fullCircle = "真円形（360度風車）"
    case zeroStatic = "ゼロスイング（0cm静止・全画面文字ストロボ）"
    
    public var id: String { rawValue }
    
    public var shortTitle: String {
        switch self {
        case .auto: return "AI自動"
        case .compactSnap: return "30cm浮き出し"
        case .wide: return "ワイド"
        case .semiCircle: return "半円アーチ"
        case .fullCircle: return "360度真円"
        case .zeroStatic: return "0cm静止ストロボ"
        }
    }
    
    public var iconName: String {
        switch self {
        case .auto: return "sparkles"
        case .compactSnap: return "hand.raised.fill"
        case .wide: return "arrow.left.and.right"
        case .semiCircle: return "arc"
        case .fullCircle: return "circle"
        case .zeroStatic: return "bolt.fill"
        }
    }
    
    public var description: String {
        switch self {
        case .auto: return "腕の疲労に合わせて、ワイド ⇄ 30cm手首 ⇄ 0cm静止ストロボをAIがリアルタイムに自動選択。"
        case .compactSnap: return "腕を上げずに手首の高速スナップ（約25〜35cm）だけで、文字が空間に立体的に浮き出るモード。"
        case .wide: return "頭上で大きく左右に振り、遠方の救助者やヘリに向けて文字を大展開するモード。"
        case .semiCircle: return "180度の半円アーチを描くように振り、長文を空中にマッピングするモード。"
        case .fullCircle: return "スマホを円形（風車のように）回し続け、360度全方位に文字を投影するモード。"
        case .zeroStatic: return "体力が尽きて振れなくなった時、画面全体を使って一文字ずつ超高輝度ストロボ点滅させるモード。"
        }
    }
}

/// 端末の角速度・姿勢から「物理空間位置」をリアルタイム算出し、
/// 空間座標に1対1で文字スライスを同期表示する位置駆動型モーションディテクタ
public final class MotionDetector: ObservableObject {
    public static let shared = MotionDetector()
    
    public let motionManager = CMMotionManager()
    
    // 公開プロパティ
    @Published public private(set) var currentPhase: SwingPhase = .forward
    @Published public private(set) var isEmitting: Bool = false                 // スリット発光中フラグ
    @Published public private(set) var isDeviceHorizontal: Bool = false         // 端末が手元で水平に保たれているか（ボタン表示用）
    @Published public private(set) var isUpsideDown: Bool = false               // 端末が上下逆さまに持たれているか（電源ボタン誤押し回避）
    @Published public private(set) var strokeProgress: Double = 0.0             // 現在のスイングにおける進行度 (0.0: 振り始め ... 1.0: 振り終わり)
    @Published public private(set) var swingIntensity: Double = 0.0             // 振りの勢い（角速度 rad/s または G）
    @Published public private(set) var currentAngleDegrees: Double = 0.0        // 現在の空間角度（度）
    @Published public private(set) var currentGyroZ: Double = 0.0               // リアルタイム角速度 (rad/s)
    @Published public private(set) var strokeAngleRange: Double = 95.0          // 学習されたスイング振れ幅（度）
    @Published public private(set) var isMotionActive: Bool = false
    @Published public private(set) var isOverheadSwinging: Bool = false         // 頭上で振っていることを検知（自動POV開始用）
    @Published public private(set) var isRealtimeOverheadSync: Bool = false     // 頭上リアルタイム同期中（X:距離維持、Y:往復時間短縮に追従）
    @Published public private(set) var roundTripDuration: Double = 0.60         // リアルタイム往復時間（秒）
    @Published public private(set) var swingFrequencyHz: Double = 1.66          // リアルタイムスイング周波数（Hz）
    
    // 疲労対応・マルチレンジモード
    @Published public var selectedRangeMode: POVDisplayRangeMode = .auto        // 選択されたレンジモード
    @Published public private(set) var activeRangeMode: POVDisplayRangeMode = .wide // 現在実効中のモード
    @Published public private(set) var staticCharIndex: Int = 0                 // 0cm静止ストロボ時の文字インデックス
    @Published public private(set) var isStaticFlashVisible: Bool = true        // 0cmストロボの点滅パルス
    public var staticTextLength: Int = 4                                        // 表示対象文字列長（一文字送り用）
    
    // キャリブレーション保持
    @Published public var userAsymmetryRatio: Double = 1.0                     // 往路/復路の非対称比
    @Published public var isUserCalibrated: Bool = false                       // キャリブレーション済みフラグ
    
    // モード設定
    @Published public var invertSwingDirection: Bool = false                    // 左右スイング判定の反転
    @Published public var strokeSensitivity: Double = 1.0                       // 振り幅感度調整 (0.7〜1.5)
    
    // 発光ウィンドウ設定（両端の文字まで100%完全表示: Hの左端〜Pの右端まで全域発光）
    public var windowStartRatio: Double = 0.0                                  // スイング開始端から即座に発光
    public var windowEndRatio: Double = 1.0                                    // スイング終了端まで完全発光維持
    
    // 内部トラッキング用
    public private(set) var currentTheta: Double = 0.0
    private var swingStartTheta: Double = 0.0   // 現在のスイング開始時の角度
    private var leftTurnAngle: Double = -0.80   // 左端（rad）約 -46度
    private var rightTurnAngle: Double = 0.85   // 右端（rad）約 +49度
    public private(set) var learnedStrokeWidth: Double = 1.65 // 平均振れ幅（rad）約 95度
    private var lastGyroZ: Double = 0.0
    private var lastUpdateTime: Date = Date()
    private var isCalibrated: Bool = false
    private var lastTurnTime: Date = Date()
    private var horizontalStabilizeCounter: Int = 0
    private var swingTriggerCounter: Int = 0
    private var quietTimeCounter: Double = 0.0 // 静止継続時間（秒）
    
    // 0cm静止ストロボ用タイマー
    private var staticStrobeTimer: Timer?
    
    // シミュレーション（センサー未搭載環境）用
    private var simulationTimer: Timer?
    private var simulationPhase: Double = 0.0
    
    // 新規追加: 平行移動（加速度）のトラッキング用
    private var lateralVelocity: Double = 0.0
    
    // 新規追加: 円形（風車）モードのトラッキング用
    public var isWindmillMode: Bool = false
    private var continuousRotationTheta: Double = 0.0
    private init() {
        loadCalibration()
        startStaticStrobeTimer()
    }
    
    /// ユーザー個人のスイング・ヒステリシス計測結果を反映・保存
    public func saveCalibration(asymmetryRatio: Double, strokeWidthRad: Double) {
        self.userAsymmetryRatio = asymmetryRatio
        self.learnedStrokeWidth = max(min(strokeWidthRad, 2.5), 0.8)
        self.strokeAngleRange = self.learnedStrokeWidth * (180.0 / .pi)
        self.isUserCalibrated = true
        UserDefaults.standard.set(asymmetryRatio, forKey: "user_asymmetry_ratio")
        UserDefaults.standard.set(strokeWidthRad, forKey: "user_stroke_width_rad")
        UserDefaults.standard.set(true, forKey: "is_user_calibrated")
    }
    
    /// 保存済みキャリブレーションのロード
    public func loadCalibration() {
        if UserDefaults.standard.bool(forKey: "is_user_calibrated") {
            let ratio = UserDefaults.standard.double(forKey: "user_asymmetry_ratio")
            let width = UserDefaults.standard.double(forKey: "user_stroke_width_rad")
            if ratio > 0.3 && ratio < 3.0 {
                self.userAsymmetryRatio = ratio
            }
            if width > 0.6 && width < 3.0 {
                self.learnedStrokeWidth = width
                self.strokeAngleRange = width * (180.0 / .pi)
            }
            self.isUserCalibrated = true
        }
    }
    
    /// キャリブレーションをデフォルト（非対称比1.0・振れ幅約95度）に戻す
    public func resetCalibration() {
        UserDefaults.standard.removeObject(forKey: "user_asymmetry_ratio")
        UserDefaults.standard.removeObject(forKey: "user_stroke_width_rad")
        UserDefaults.standard.removeObject(forKey: "is_user_calibrated")
        self.userAsymmetryRatio = 1.0
        self.learnedStrokeWidth = 1.65
        self.strokeAngleRange = 1.65 * (180.0 / .pi)
        self.isUserCalibrated = false
    }
    
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
        isRealtimeOverheadSync = false
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
            // ジャイロ（回転）の抽出
            let gx = motion.gravity.x
            let gy = motion.gravity.y
            let gz = motion.gravity.z
            let rx = motion.rotationRate.x
            let ry = motion.rotationRate.y
            let rz = motion.rotationRate.z
            let rotationGyro = -(rx * gx + ry * gy + rz * gz)
            
            // 加速度（平行移動）の抽出
            // スマホの姿勢に依存せず、常に重力に直交する「左右」の加速度を計算
            let rightAccel = motion.userAcceleration.x * (-gy) + motion.userAcceleration.y * gx
            self.lateralVelocity += rightAccel * dt
            self.lateralVelocity *= 0.85 // ドリフトを防ぐリーキー積分器
            
            // センサーフュージョン（回転 + 平行移動）
            // これにより、手首を固定して肩幅でスライドさせただけでも正確にスイングを検知可能！
            rawGyro = rotationGyro + (self.lateralVelocity * 3.0)
            
        case .vertical:
            // 縦振り時も「X軸/Y軸回転 + 上下平行移動（加速度）」のセンサーフュージョンを適用
            let verticalAccel = motion.userAcceleration.y + motion.userAcceleration.z
            self.lateralVelocity += verticalAccel * dt
            self.lateralVelocity *= 0.85
            let dominantRotation = abs(motion.rotationRate.x) >= abs(motion.rotationRate.y)
            ? motion.rotationRate.x
            : motion.rotationRate.y
            rawGyro = dominantRotation + (self.lateralVelocity * 3.0)
        }
        
        let gyro = invertSwingDirection ? -rawGyro : rawGyro
        self.currentGyroZ = gyro
        self.swingIntensity = abs(gyro)
        
        // 1. 水平検知＆上下逆さま検知（電源ボタン誤押し回避）
        let gravity = motion.gravity
        let isFlat = (gravity.z < -0.70) && (abs(gravity.x) < 0.40) && (abs(gravity.y) < 0.45)
        let isQuiet = self.swingIntensity < 0.45 // 静止または微動
        
        // 疲労・振れ幅に応じたAI自動レンジモード切り替え
        if isQuiet {
            quietTimeCounter += dt
            if quietTimeCounter >= 1.0 { // 1秒以上静止＝疲労または狭所
                if selectedRangeMode == .auto {
                    if activeRangeMode != .zeroStatic {
                        activeRangeMode = .zeroStatic
                    }
                }
            }
        } else {
            quietTimeCounter = 0.0
            if selectedRangeMode == .auto {
                // スイング振幅と角速度から30cm手首スナップ vs ワイドを瞬時判定
                if learnedStrokeWidth < 0.70 { // 約40度未満＝手首30cm浮き出しスナップ
                    if activeRangeMode != .compactSnap {
                        activeRangeMode = .compactSnap
                    }
                } else {
                    if activeRangeMode != .wide {
                        activeRangeMode = .wide
                    }
                }
            }
        }
        
        // 手動選択されている場合はそのモードを強制適用
        if selectedRangeMode != .auto && activeRangeMode != selectedRangeMode {
            activeRangeMode = selectedRangeMode
            if selectedRangeMode == .fullCircle {
                self.isWindmillMode = true
            } else if selectedRangeMode == .semiCircle {
                self.isWindmillMode = false
                self.learnedStrokeWidth = 1.0 // 広めに固定
            } else {
                self.isWindmillMode = false
            }
            
            // 30cm手首モードに切り替わった時は、手首の振れ幅（約18度=0.32rad）に即座にプリセット
            if activeRangeMode == .compactSnap && (learnedStrokeWidth > 0.60 || learnedStrokeWidth < 0.18) {
                learnedStrokeWidth = 0.32
                strokeAngleRange = 18.3
            }
        }
        
        if isQuiet {
            // 静止時にのみ上下逆さま判定を更新（激しく振っている最中の遠心力による画面反転バグを根絶）
            self.isUpsideDown = gravity.y > 0.40
        }
        
        // 頭上スイング＆円形（風車）モード自動検知
        let isOverhead = !isFlat && (abs(gravity.y) > 0.30 || abs(gravity.z) < 0.70)
        let isFastSwing = self.swingIntensity > 0.8
        
        if isOverhead {
            // 風車モード（円形スイング）の検知: 同一方向に継続して360度以上回転しているか
            if gyro > 2.0 { // 右回転
                continuousRotationTheta += gyro * dt
                if continuousRotationTheta > 2 * .pi {
                    self.isWindmillMode = true
                }
            } else if gyro < -2.0 { // 左回転
                continuousRotationTheta += gyro * dt
                if continuousRotationTheta < -2 * .pi {
                    self.isWindmillMode = true
                }
            } else {
                // 回転が止まるか逆転したらリセット
                if abs(gyro) < 0.5 {
                    continuousRotationTheta = 0.0
                    self.isWindmillMode = false
                }
            }
            
            if isFastSwing {
                swingTriggerCounter += 1
                if swingTriggerCounter >= 4 { // 約0.04秒で即座に反応
                    if !self.isOverheadSwinging {
                        self.isOverheadSwinging = true
                    }
                    self.isRealtimeOverheadSync = true
                }
            }
        } else if isFlat && isQuiet {
            swingTriggerCounter = 0
            continuousRotationTheta = 0.0
            self.isWindmillMode = false
            if self.isOverheadSwinging {
                self.isOverheadSwinging = false
            }
            self.isRealtimeOverheadSync = false
        }
        
        if isFlat && isQuiet {
            horizontalStabilizeCounter += 1
            if horizontalStabilizeCounter >= 10 { // 100Hzで約0.1秒維持で確定
                if !self.isDeviceHorizontal {
                    self.isDeviceHorizontal = true
                }
            }
        } else {
            horizontalStabilizeCounter = 0
            if self.isDeviceHorizontal {
                self.isDeviceHorizontal = false
            }
        }
        
        // 2. 角度（空間位置）の台形積分: theta += gyro * dt
        currentTheta += (gyro + lastGyroZ) * 0.5 * dt
        self.currentAngleDegrees = currentTheta * (180.0 / .pi)
        
        // 3. 折り返し（ゼロクロス）の検出（超高速レスポンス版）
        // 手首30cmモード時は、手首の素早い「返し」（4〜8Hz、往復0.12〜0.2秒）に遅延ゼロで瞬時追従するため
        // 不感帯ヒステリシスを極小の0.08rad/sに設定し、ゼロクロス直後に即座に折り返しを確定
        let isCompact = (activeRangeMode == .compactSnap)
        let turnHysteresis = isCompact ? 0.08 : 0.06
        
        if currentPhase == .backward && gyro > turnHysteresis && lastGyroZ <= turnHysteresis {
            // 左端到達 → 正方向（往路）への瞬時反転
            handleTurnaround(isMovingPositive: true, turnaroundTheta: currentTheta, currentGyro: gyro, now: now)
        } else if currentPhase == .forward && gyro < -turnHysteresis && lastGyroZ >= -turnHysteresis {
            // 右端到達 → 負方向（復路）への瞬時反転
            handleTurnaround(isMovingPositive: false, turnaroundTheta: currentTheta, currentGyro: gyro, now: now)
        }
        
        // 4. 【描画マッピング: 円形モード or PLL仮想振り子】
        let isRecentlySwinging = now.timeIntervalSince(lastTurnTime) < max(self.roundTripDuration * 1.5, 0.45)
        
        if self.isWindmillMode {
            // 円形（風車）モード：ジャイロの絶対角度（360度ループ）で文字を空間に全方位固定する
            // 360度 (2π) を1周期として、0.0〜1.0 にシームレスにマッピング
            self.isEmitting = true
            self.currentPhase = gyro > 0 ? .forward : .backward
            
            // continuousRotationThetaは無限に増減するので、2πで割った余りを使う
            var wrappedTheta = continuousRotationTheta.truncatingRemainder(dividingBy: 2 * .pi)
            if wrappedTheta < 0 { wrappedTheta += 2 * .pi } // 0〜2πに正規化
            
            self.strokeProgress = wrappedTheta / (2 * .pi)
            
        } else {
            // 従来のPLL仮想振り子による究極の描画安定化
            if gyro > turnHysteresis {
                self.currentPhase = .forward
            } else if gyro < -turnHysteresis {
                self.currentPhase = .backward
            }
            
            if isRecentlySwinging && activeRangeMode != .zeroStatic {
                let halfTrip = max(self.roundTripDuration / 2.0, 0.04)
                let elapsed = now.timeIntervalSince(lastTurnTime)
                
                // 1. 時間ベースの予測進行度
                let linearProgress = min(elapsed / halfTrip, 1.0)
                let timeBasedProgress = (1.0 - cos(.pi * linearProgress)) / 2.0
                
                // 2. 物理角度ベースのダイレクト進行度（手首の急加速に遅れゼロで追従するため、16ms分の角速度位相進み補償をプラス）
                let predictedTheta = currentTheta + gyro * 0.016
                let safeStrokeWidth = max(learnedStrokeWidth, isCompact ? 0.22 : 0.45)
                let angleDelta = abs(predictedTheta - swingStartTheta)
                let angleBasedProgress = min(max(angleDelta / safeStrokeWidth, 0.0), 1.0)
                
                // 手首モード（isCompact）時は角度ダイレクト追従を75%優先して遅れを根絶！通常時も45%ブレンドしてキレを向上
                let idealProgress = isCompact
                ? (angleBasedProgress * 0.75 + timeBasedProgress * 0.25)
                : (angleBasedProgress * 0.45 + timeBasedProgress * 0.55)
                
                // 中央の有効描画幅（padding）を適用して、手首モードでは端から端まで95%即座に発光
                let effectiveRatio = isCompact ? 0.95 : 0.76
                let paddingRatio = (1.0 - effectiveRatio) / 2.0
                let mappedProgress = (idealProgress - paddingRatio) / effectiveRatio
                
                if mappedProgress >= 0.0 && mappedProgress <= 1.0 {
                    self.isEmitting = true
                    self.strokeProgress = mappedProgress
                } else {
                    self.isEmitting = false
                    self.strokeProgress = mappedProgress < 0.0 ? 0.0 : 1.0
                }
            } else if activeRangeMode == .zeroStatic {
                self.isEmitting = true
            } else {
                self.isEmitting = false
                self.strokeProgress = 0.0
            }
        }
        
        lastGyroZ = gyro
    }
    
    /// スイングの折り返し処理（振れ幅の自動学習とリアルタイム周期適応）
    private func handleTurnaround(isMovingPositive: Bool, turnaroundTheta: Double, currentGyro: Double, now: Date) {
        let interval = now.timeIntervalSince(lastTurnTime)
        let isCompact = (activeRangeMode == .compactSnap)
        
        // 手首スナップ（4〜8Hzの超高速往復）に完全追従する極小インターバル（20ms〜）
        let dynamicMinInterval = isCompact
            ? max(0.020, min(0.065, 0.18 / max(abs(currentGyro), 1.0)))
            : max(0.050, min(0.14, 0.45 / max(abs(currentGyro), 1.0)))
        guard interval > dynamicMinInterval else { return }
        
        // リアルタイム往復時間（Y: 往復時間）の計測と更新
        let halfDuration = interval
        let measuredRoundTrip = halfDuration * 2.0
        if measuredRoundTrip >= 0.06 && measuredRoundTrip <= 2.5 {
            let alpha = measuredRoundTrip < self.roundTripDuration ? 0.60 : 0.40
            self.roundTripDuration = self.roundTripDuration * (1.0 - alpha) + measuredRoundTrip * alpha
            self.swingFrequencyHz = 1.0 / max(self.roundTripDuration, 0.06)
        }
        
        lastTurnTime = now
        
        let minAllowedWidth = isCompact ? 0.14 : 0.38
        let maxAllowedWidth = isCompact ? 1.50 : 2.50
        
        if isMovingPositive {
            // 「右→左」から「左→右」への切り返し（左端に到達！往路スタート）
            leftTurnAngle = turnaroundTheta
            swingStartTheta = turnaroundTheta
            let width = abs(rightTurnAngle - leftTurnAngle)
            if width > minAllowedWidth && width < maxAllowedWidth {
                let widthAlpha = isCompact ? 0.45 : 0.35 // 手首モード時は素早く振れ幅に適応
                learnedStrokeWidth = learnedStrokeWidth * (1.0 - widthAlpha) + width * widthAlpha
                strokeAngleRange = learnedStrokeWidth * (180.0 / .pi)
            }
        } else {
            // 「左→右」から「右→左」への切り返し（右端に到達！復路スタート）
            rightTurnAngle = turnaroundTheta
            swingStartTheta = turnaroundTheta
            let width = abs(rightTurnAngle - leftTurnAngle)
            if width > minAllowedWidth && width < maxAllowedWidth {
                let widthAlpha = isCompact ? 0.45 : 0.35
                learnedStrokeWidth = learnedStrokeWidth * (1.0 - widthAlpha) + width * widthAlpha
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
            
            // 頭上高速スイングを模したダイナミック速度（往復時間Yが約0.38秒に短縮、X:距離は一定）
            let speedFactor: Double = self.isOverheadSwinging ? 0.16 : 0.09
            self.simulationPhase += speedFactor
            let s = sin(self.simulationPhase)
            let c = cos(self.simulationPhase)
            
            // 往復時間と周波数のシミュレーション値
            let simDuration = (2.0 * .pi / (speedFactor * 60.0))
            self.roundTripDuration = simDuration
            self.swingFrequencyHz = 1.0 / simDuration
            self.currentGyroZ = c * (self.isOverheadSwinging ? 6.2 : 3.5)
            self.swingIntensity = abs(self.currentGyroZ)
            
            // 往復の進行度（X: 距離は一定振れ幅50°を維持）
            let rawProgress = (s + 1.0) / 2.0
            self.currentPhase = c > 0 ? .forward : .backward
            
            // 往路も復路も中央域で同期発光
            if rawProgress >= self.windowStartRatio && rawProgress <= self.windowEndRatio && abs(c) > 0.25 {
                self.isEmitting = true
                let mapped = (rawProgress - self.windowStartRatio) / (self.windowEndRatio - self.windowStartRatio)
                self.strokeProgress = min(max(mapped, 0.0), 1.0)
            } else {
                self.isEmitting = false
                self.strokeProgress = 0.0
            }
            self.currentAngleDegrees = s * 50.0
        }
    }
    
    /// 頭上スイング自動検知トリガーのリセット
    public func resetOverheadTrigger() {
        self.isOverheadSwinging = false
        self.isRealtimeOverheadSync = false
        self.swingTriggerCounter = 0
    }
    
    /// 0cm静止ストロボ用の自動一文字送りタイマー（0.36秒周期）
    public func startStaticStrobeTimer() {
        staticStrobeTimer?.invalidate()
        staticStrobeTimer = Timer.scheduledTimer(withTimeInterval: 0.36, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            if self.activeRangeMode == .zeroStatic {
                // 文字の切り替わりに一瞬ブラックアウトを挟み、ストロボ残像効果を最大化
                self.isStaticFlashVisible = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
                    self.staticCharIndex = (self.staticCharIndex + 1) % max(1, self.staticTextLength)
                    self.isStaticFlashVisible = true
                }
            }
        }
    }
}

