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
    
    // 背面ライト・先行メトロノーム用（人間の反応時間100msを見越して折り返し前に合図）
    @Published public var isMetronomeTorchEnabled: Bool = true
    private var hasFiredMetronomeForCurrentHalf: Bool = false
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
    
    /// 純粋な時間メトロノーム（2倍速）で表示シーケンスを回し、人間が背面ライトの点滅リズムに動きを合わせる方式
    private func processDeviceMotion(_ motion: CMDeviceMotion, direction: POVDirection) {
        let now = Date()
        let dt = min(now.timeIntervalSince(lastUpdateTime), 0.05)
        lastUpdateTime = now
        
        // 端末の姿勢（メニュー表示用の水平判定・上下逆さま判定のみに使用し、発光タイミングは一切ズラさない）
        let gravity = motion.gravity
        let rx = motion.rotationRate.x
        let ry = motion.rotationRate.y
        let rz = motion.rotationRate.z
        let gyroMag = sqrt(rx * rx + ry * ry + rz * rz)
        self.swingIntensity = gyroMag
        self.currentGyroZ = rz
        
        let isFlat = (gravity.z < -0.70) && (abs(gravity.x) < 0.40) && (abs(gravity.y) < 0.45)
        let isQuiet = gyroMag < 0.35
        
        if isQuiet {
            self.isUpsideDown = gravity.y > 0.40
        }
        
        if isFlat && isQuiet {
            horizontalStabilizeCounter += 1
            if horizontalStabilizeCounter >= 10 {
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
        
        // モード選択の反映（勝手にスリット幅が変わらないよう .auto 時は常に .wide 固定）
        if selectedRangeMode == .auto {
            if activeRangeMode != .wide {
                activeRangeMode = .wide
            }
        } else if activeRangeMode != selectedRangeMode {
            activeRangeMode = selectedRangeMode
        }
        
        if activeRangeMode == .zeroStatic {
            self.isEmitting = true
            return
        }
        
        // =========================================================================
        // 🔔 【純粋2倍速メトロノーム・シーケンス再生（センサーによる位置ズレ完全ゼロ）】
        // 従来の片道0.38秒（往復0.76秒）を「2倍速」の片道0.19秒（往復0.38秒 = 2.63Hz）に固定！
        // 手首30cmモード選択時はさらに高速な片道0.12秒（往復0.24秒 = 4.16Hz）で駆動。
        // =========================================================================
        let isCompact = (selectedRangeMode == .compactSnap)
        let halfDuration: Double = isCompact ? 0.12 : 0.19
        let fullCycleDuration: Double = halfDuration * 2.0
        
        self.roundTripDuration = fullCycleDuration
        self.swingFrequencyHz = 1.0 / fullCycleDuration
        
        // 経過時間から現在のサイクル位置（0.0 〜 2.0）を算出（0.0〜1.0が往路、1.0〜2.0が復路）
        let totalElapsed = now.timeIntervalSince(lastTurnTime)
        let cyclePos = totalElapsed.truncatingRemainder(dividingBy: fullCycleDuration) / halfDuration
        
        let newPhase: SwingPhase = (cyclePos < 1.0) ? .forward : .backward
        let halfLinearProgress: Double = (cyclePos < 1.0) ? cyclePos : (cyclePos - 1.0)
        
        // 折り返し（0.0 または 1.0 を跨いだ瞬間）に背面ライトを0.01秒間ピカッと閃光させる！
        if newPhase != self.currentPhase {
            self.currentPhase = newPhase
            if isMetronomeTorchEnabled {
                TorchService.shared.pulseMetronome(level: 1.0, duration: 0.01)
            }
        }
        
        // 単振動（人の腕の振り）に合わせたコサインカーブ進行度 (0.0 -> 1.0)
        let cosineProgress = (1.0 - cos(.pi * halfLinearProgress)) / 2.0
        
        // 以前うまくいっていた初期仕様と同じく、中央70%（手首モード時は90%）の区間でくっきり発光
        let effectiveRatio: Double = isCompact ? 0.90 : 0.70
        let paddingRatio: Double = (1.0 - effectiveRatio) / 2.0
        let mappedProgress = (cosineProgress - paddingRatio) / effectiveRatio
        
        if mappedProgress >= 0.0 && mappedProgress <= 1.0 {
            self.isEmitting = true
            self.strokeProgress = mappedProgress
        } else {
            // 両端の折り返し瞬間（15%ずつ）はきっちり消灯し、背面ライトの閃光ポイントと分離する
            self.isEmitting = false
            self.strokeProgress = mappedProgress < 0.0 ? 0.0 : 1.0
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

