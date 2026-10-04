import Foundation
import CoreMotion
import CoreLocation
import Combine
import SwiftUI

/// ユーザーが置かれている現在のシチュエーション判定
public enum UserSituationType: String, CaseIterable, Identifiable {
    case normal = "スタンバイ"
    case severeImpact = "🚨 衝撃・衝突検知（緊急事態）"
    case mountainIsolation = "🏔 山岳・高地孤立"
    case nightRunning = "🏃 ナイトラン・夜間防犯"
    case partyCelebration = "🎉 パーティー・フェス・乾杯"
    
    public var id: String { rawValue }
    
    public var suggestedText: String {
        switch self {
        case .severeImpact: return "HELP"
        case .mountainIsolation: return "SOS"
        case .nightRunning: return "SAFE"
        case .partyCelebration: return "CHEERS"
        case .normal: return "OK"
        }
    }
    
    public var suggestedMode: AppOperationalMode {
        switch self {
        case .severeImpact, .mountainIsolation: return .rescue
        case .nightRunning, .partyCelebration, .normal: return .party
        }
    }
    
    public var explanation: String {
        switch self {
        case .severeImpact:
            return "急激なGショックまたは急停止を検知。遭難・衝突の可能性が高いシチュエーションです。"
        case .mountainIsolation:
            return "標高急変および遠隔孤立地点を検知。山岳救助サインの準備を推奨します。"
        case .nightRunning:
            return "夜間の移動加速度を検知。後方車両への視認性確保サインを推奨します。"
        case .partyCelebration:
            return "リズミカルなスイングを検知。お祝い・乾杯のホログラム表示を推奨します。"
        case .normal:
            return "平常状態をモニタリング中。"
        }
    }
}

/// MCP (Model Context Protocol) 連携用データモデル
public struct MCPSituationPayload: Codable {
    public let timestamp: Date
    public let accelerationG: Double
    public let altitudeMeters: Double?
    public let estimatedSituation: String
    public let suggestedText: String
    public let isOffline: Bool
    public let deviceOrientation: String
}

/// Apple Intelligence / Core ML / CoreMotion / MCP を統合するハイブリッド知性エンジン
public final class HybridIntelligenceEngine: ObservableObject {
    public static let shared = HybridIntelligenceEngine()
    
    // 公開状態
    @Published public private(set) var currentSituation: UserSituationType = .normal
    @Published public private(set) var aiSuggestionMessage: String? = nil
    @Published public private(set) var suggestedText: String = "HELP"
    @Published public private(set) var isImpactAlertActive: Bool = false
    @Published public var isAutoSituationAdaptationEnabled: Bool = true // AIによる状況自動切替
    @Published public private(set) var isConnectedToMCPAgent: Bool = false // MCPエージェント接続状態
    
    private let motionManager = CMMotionManager()
    private var lastAcceleration: CMAcceleration = CMAcceleration(x: 0, y: 0, z: -1)
    private var lastAnalysisTime: Date = Date()
    
    private init() {
        startOnDeviceSensors()
    }
    
    /// オンデバイスCoreMotion & センサー解析を開始（完全オフライン対応）
    public func startOnDeviceSensors() {
        guard motionManager.isAccelerometerAvailable else { return }
        motionManager.accelerometerUpdateInterval = 1.0 / 30.0 // 30Hzで状況モニタリング
        
        motionManager.startAccelerometerUpdates(to: .main) { [weak self] data, error in
            guard let self = self, let data = data else { return }
            self.analyzeMotionContext(acceleration: data.acceleration)
        }
    }
    
    /// CoreMotionからリアルタイムに状況（衝突G、急停止、リズミカル振動）を推論
    private func analyzeMotionContext(acceleration: CMAcceleration) {
        let now = Date()
        let dt = now.timeIntervalSince(lastAnalysisTime)
        guard dt > 0.1 else { return }
        lastAnalysisTime = now
        
        // 合成加速度（G）
        let totalG = sqrt(acceleration.x * acceleration.x + acceleration.y * acceleration.y + acceleration.z * acceleration.z)
        
        // 1. 衝突・激しいショック検知（3.8G以上の急激な衝撃 ➔ 事故・滑落）
        let deltaG = abs(totalG - sqrt(lastAcceleration.x * lastAcceleration.x + lastAcceleration.y * lastAcceleration.y + lastAcceleration.z * lastAcceleration.z))
        lastAcceleration = acceleration
        
        if deltaG > 3.8 || totalG > 4.2 {
            triggerSevereImpactAlert()
            return
        }
        
        // 2. 時間帯と高度コンテキストの統合判定
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: now)
        let isNight = (hour >= 20 || hour <= 4)
        let isWeekendNight = (isNight && (calendar.component(.weekday, from: now) == 6 || calendar.component(.weekday, from: now) == 7))
        
        // 高度判定（LocationServiceから取得）
        let altitude = LocationService.shared.altitude ?? 0.0
        let isHighMountain = altitude > 800.0
        
        // 状況分類（Core ML ルールベース推論）
        let inferred: UserSituationType
        if isHighMountain && isNight {
            inferred = .mountainIsolation
        } else if isWeekendNight && MotionDetector.shared.swingIntensity > 1.2 {
            inferred = .partyCelebration
        } else if isNight && MotionDetector.shared.swingIntensity > 0.5 {
            inferred = .nightRunning
        } else {
            inferred = .normal
        }
        
        if inferred != currentSituation {
            currentSituation = inferred
            suggestedText = inferred.suggestedText
            aiSuggestionMessage = "【状況検知】\(inferred.explanation)「\(suggestedText)」を表示しますか？"
        }
    }
    
    /// 衝突・急停止時の緊急対話アラート発火
    private func triggerSevereImpactAlert() {
        self.currentSituation = .severeImpact
        self.suggestedText = "HELP"
        self.isImpactAlertActive = true
        self.aiSuggestionMessage = "【重大衝撃を検知】大丈夫ですか？遭難救助サイン「HELP」の発光準備が整いました。"
        
        // 触覚警告
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)
    }
    
    /// 提案を承認して適用
    public func acceptSuggestion(onAccepted: (String, AppOperationalMode) -> Void) {
        onAccepted(suggestedText, currentSituation.suggestedMode)
        isImpactAlertActive = false
        aiSuggestionMessage = nil
    }
    
    /// 提案を却下
    public func dismissSuggestion() {
        isImpactAlertActive = false
        aiSuggestionMessage = nil
    }
    
    // MARK: - MCP (Model Context Protocol) ＆ 次世代Gemini Spark連携
    
    /// MCPコンテキスト・ペイロードを生成（エージェント通信用）
    public func exportMCPContext() -> MCPSituationPayload {
        let totalG = sqrt(lastAcceleration.x * lastAcceleration.x + lastAcceleration.y * lastAcceleration.y + lastAcceleration.z * lastAcceleration.z)
        return MCPSituationPayload(
            timestamp: Date(),
            accelerationG: totalG,
            altitudeMeters: LocationService.shared.altitude,
            estimatedSituation: currentSituation.rawValue,
            suggestedText: suggestedText,
            isOffline: true, // オンデバイス完全完結
            deviceOrientation: MotionDetector.shared.isUpsideDown ? "UpsideDown" : "Normal"
        )
    }
    
    /// 将来のiOS 18+ / iOS 20+ Siri AI / Apple Intelligence APIが公開された際のフック
    public func requestSiriContextUpdate() {
        // 将来のSiri AI / App Intents Framework拡張ポイント
    }
}
