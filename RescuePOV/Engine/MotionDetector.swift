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
    case zeroStatic = "ゼロスイング（0cm静止・全画面文字ストロボ）"
    
    public var id: String { rawValue }
    
    public var shortTitle: String {
        switch self {
        case .auto: return "AI自動"
        case .compactSnap: return "30cm浮き出し"
        case .wide: return "ワイド"
        case .zeroStatic: return "0cm静止ストロボ"
        }
    }
    
    public var iconName: String {
        switch self {
        case .auto: return "sparkles"
        case .compactSnap: return "hand.raised.fill"
        case .wide: return "arrow.left.and.right"
        case .zeroStatic: return "bolt.fill"
        }
    }
    
    public var description: String {
        switch self {
        case .auto: return "腕の疲労に合わせて、ワイド ⇄ 30cm手首 ⇄ 0cm静止ストロボをAIがリアルタイムに自動選択。"
        case .compactSnap: return "腕を上げずに手首の高速スナップ（約25〜35cm）だけで、文字が空間に立体的に浮き出るモード。"
        case .wide: return "頭上で大きく左右に振り、遠方の救助者やヘリに向けて文字を大展開するモード。"
        case .zeroStatic: return "体力が尽きて振れなくなった時、画面全体を使って一文字ずつ超高輝度ストロボ点滅させるモード。"
        }
    }
}

/// 端末の角速度・姿勢から「物理空間位置」をリアルタイム算出し、
/// 空間座標に1対1で文字スライスを同期表示する位置駆動型モーションディテクタ
public final class MotionDetector: ObservableObject {
    public static let shared = MotionDetector()
    
    private let motionManager = CMMotionManager()
    
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
            rawGyro = motion.rotationRate.z
        case .vertical:
            rawGyro = motion.rotationRate.x
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
        }
        
        if isQuiet {
            // 静止時にのみ上下逆さま判定を更新（激しく振っている最中の遠心力による画面反転バグを根絶）
            self.isUpsideDown = gravity.y > 0.40
        }
        
        // 頭上スイング自動検知（頭上に掲げて左右に振ると自動でPOVフルスクリーン発光開始＆リアルタイム速度同期）
        let isOverhead = !isFlat && (abs(gravity.y) > 0.30 || abs(gravity.z) < 0.70)
        let isFastSwing = self.swingIntensity > 0.8
        
        if isOverhead && isFastSwing {
            swingTriggerCounter += 1
            if swingTriggerCounter >= 4 { // 約0.04秒で即座に反応
                if !self.isOverheadSwinging {
                    self.isOverheadSwinging = true
                }
                self.isRealtimeOverheadSync = true
            }
        } else if isFlat && isQuiet {
            swingTriggerCounter = 0
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
        
        // 3. 折り返し（ゼロクロス）の検出
        // 高速頭上スイング時は角速度の閾値を動的適応させて瞬時に折り返しをキャッチ
        let zeroThreshold = self.isRealtimeOverheadSync ? 0.08 : 0.05
        if (lastGyroZ <= zeroThreshold && gyro > zeroThreshold) || (lastGyroZ >= -zeroThreshold && gyro < -zeroThreshold) {
            handleTurnaround(isMovingPositive: gyro > 0, turnaroundTheta: currentTheta, currentGyro: gyro, now: now)
        }
        
        // 4. 【疲労適応 ＆ Hの左端からPの右端まで全域100%発光】
        // 30cm手首モード時は手首の狭い振れ幅（最小0.15rad=約8.6度）に完全追従。ワイドモード時は0.38rad。
        let minClampWidth = (activeRangeMode == .compactSnap) ? 0.15 : 0.38
        let width = max(learnedStrokeWidth * strokeSensitivity, minClampWidth)
        let minEmitSpeed = (activeRangeMode == .compactSnap) ? 0.08 : 0.15 // 手首の微小スイングでも即座に発光
        
        if gyro > minEmitSpeed {
            // 往路（左から右へのスイング）: swingStartTheta(左端)からの進行
            self.currentPhase = .forward
            let strokeDelta = max(currentTheta - swingStartTheta, 0.0)
            let rawProgress = min(max(strokeDelta / width, 0.0), 1.0)
            
            self.isEmitting = true
            self.strokeProgress = rawProgress // 0.0(Hの左端) 〜 1.0(Pの右端)まで欠けなく全域発光
            
        } else if gyro < -minEmitSpeed {
            // 復路（右から左へのスイング）: swingStartTheta(右端)からの進行
            self.currentPhase = .backward
            let strokeDelta = max(swingStartTheta - currentTheta, 0.0)
            let rawProgress = min(max(strokeDelta / width, 0.0), 1.0)
            
            self.isEmitting = true
            self.strokeProgress = rawProgress // 0.0(Pの右端) 〜 1.0(Hの左端)まで欠けなく全域発光
            
        } else {
            // 完全停止域（折り返しの極小瞬間）
            self.isEmitting = false
            self.strokeProgress = 0.0
        }
        
        lastGyroZ = gyro
    }
    
    /// スイングの折り返し処理（振れ幅の自動学習とリアルタイム周期適応）
    private func handleTurnaround(isMovingPositive: Bool, turnaroundTheta: Double, currentGyro: Double, now: Date) {
        let interval = now.timeIntervalSince(lastTurnTime)
        
        // 手首スナップ（4〜6Hzの超高速往復）に完全追従する動的チャタリング防止インターバル
        let dynamicMinInterval = (activeRangeMode == .compactSnap)
            ? max(0.035, min(0.09, 0.28 / max(abs(currentGyro), 1.0)))
            : max(0.050, min(0.14, 0.45 / max(abs(currentGyro), 1.0)))
        guard interval > dynamicMinInterval else { return }
        
        // リアルタイム往復時間（Y: 往復時間）の計測と更新（手首高速往復に対応し下限0.08sへ拡大）
        let halfDuration = interval
        let measuredRoundTrip = halfDuration * 2.0
        if measuredRoundTrip >= 0.08 && measuredRoundTrip <= 2.5 {
            let alpha = measuredRoundTrip < self.roundTripDuration ? 0.60 : 0.40
            self.roundTripDuration = self.roundTripDuration * (1.0 - alpha) + measuredRoundTrip * alpha
            self.swingFrequencyHz = 1.0 / max(self.roundTripDuration, 0.08)
        }
        
        lastTurnTime = now
        
        let minAllowedWidth = (activeRangeMode == .compactSnap) ? 0.14 : 0.35
        
        if isMovingPositive {
            // 「右→左」から「左→右」への切り返し（左端に到達！往路スタート）
            leftTurnAngle = turnaroundTheta
            swingStartTheta = turnaroundTheta
            let width = abs(rightTurnAngle - leftTurnAngle)
            // 手首30cmスイング（0.15 rad〜）から頭上大振り（〜2.5 rad）まで、直近の振れ幅にリアルタイム追従して文字をギュッと収める
            if width > minAllowedWidth && width < 2.5 {
                let widthAlpha = 0.35 // 振れ幅変化に機敏に適応
                learnedStrokeWidth = learnedStrokeWidth * (1.0 - widthAlpha) + width * widthAlpha
                strokeAngleRange = learnedStrokeWidth * (180.0 / .pi)
            }
        } else {
            // 「左→右」から「右→左」への切り返し（右端に到達！復路スタート）
            rightTurnAngle = turnaroundTheta
            swingStartTheta = turnaroundTheta
            let width = abs(rightTurnAngle - leftTurnAngle)
            if width > minAllowedWidth && width < 2.5 {
                let widthAlpha = 0.35
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

