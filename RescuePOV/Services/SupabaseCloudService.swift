import Foundation
import UIKit
import Combine

/// Supabase Cloud リアルタイム同期サービス
/// 外部ライブラリに依存せず、URLSessionでSupabase REST APIと直接通信
public final class SupabaseCloudService: ObservableObject {
    public static let shared = SupabaseCloudService()
    
    private let supabaseUrl = "https://dmnaowybbmacwadfiofu.supabase.co/rest/v1"
    private let supabaseAnonKey = "sb_publishable_pJsAhOpYaWHWfGcwChGAcw_-b3JhO7C"
    
    public let deviceId: String
    private var commandPollingTimer: Timer?
    
    @Published public var lastSentTimestamp: Date?
    @Published public var isSyncing: Bool = false
    @Published public var isEmailSent: Bool = false
    @Published public var lastGeneratedPasscode: String = ""
    
    // 緊急送信先メールアドレス（デフォルトはユーザー本人のGmail）
    @Published public var emergencyRecipientEmail: String {
        didSet {
            UserDefaults.standard.set(emergencyRecipientEmail, forKey: "emergency_recipient_email")
        }
    }
    
    private let vercelApiUrl = "https://rescuepov.vercel.app/api/send-sos-email"
    
    // 遠隔コマンド受信時のコールバック（文字の書き換え等）
    public var onRemoteTextReceived: ((String, String?) -> Void)?
    
    private init() {
        if let savedEmail = UserDefaults.standard.string(forKey: "emergency_recipient_email"), !savedEmail.isEmpty {
            self.emergencyRecipientEmail = savedEmail
        } else {
            self.emergencyRecipientEmail = "naohiko.yamada@gmail.com"
        }
        
        if let vendorId = UIDevice.current.identifierForVendor?.uuidString {
            self.deviceId = "iPhone-" + String(vendorId.prefix(6))
        } else {
            self.deviceId = "iPhone-RescuePOV"
        }
    }
    
    /// 緊急救難イベントをSupabaseに発信し、同時にGmailから緊急SOSメールを自動配信
    public func publishRescueEvent(
        latitude: Double?,
        longitude: Double?,
        altitude: Double?,
        situation: String?,
        targetText: String,
        color: String,
        batteryLevel: Int?
    ) {
        // 位置情報が渡されていない場合はLocationServiceから即時取得を試行
        let finalLat = latitude ?? LocationService.shared.latitude
        let finalLon = longitude ?? LocationService.shared.longitude
        let finalAlt = altitude ?? LocationService.shared.altitude
        
        // ランダムな6桁ワンタイムパスコードを発行
        let passcode = String(format: "%06X", Int.random(in: 0x100000...0xFFFFFF))
        self.lastGeneratedPasscode = passcode
        
        guard let url = URL(string: "\(supabaseUrl)/rescue_events") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        
        let payload: [String: Any?] = [
            "device_id": deviceId,
            "latitude": finalLat,
            "longitude": finalLon,
            "altitude": finalAlt,
            "situation": situation ?? "rescue_sos",
            "target_text": targetText,
            "color": color,
            "battery_level": batteryLevel ?? Int(UIDevice.current.batteryLevel * 100),
            "is_active": true,
            "passcode": passcode
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload.compactMapValues { $0 })
        } catch {
            return
        }
        
        self.isSyncing = true
        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            DispatchQueue.main.async {
                self?.isSyncing = false
                if let httpResp = response as? HTTPURLResponse, (200...299).contains(httpResp.statusCode) {
                    self?.lastSentTimestamp = Date()
                }
            }
        }.resume()
        
        // Vercel経由でご自身のGmailから緊急救難メールを自動送信！
        triggerEmergencyEmail(
            passcode: passcode,
            latitude: finalLat,
            longitude: finalLon,
            altitude: finalAlt,
            situation: situation,
            targetText: targetText,
            batteryLevel: batteryLevel
        )
    }
    
    /// Vercel APIを叩き、ユーザーのGmailから緊急SOSメールを送信
    public func triggerEmergencyEmail(
        passcode: String,
        latitude: Double?,
        longitude: Double?,
        altitude: Double?,
        situation: String?,
        targetText: String,
        batteryLevel: Int?
    ) {
        guard let url = URL(string: vercelApiUrl) else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any?] = [
            "toEmail": emergencyRecipientEmail,
            "recipientName": "ご家族・緊急連絡先",
            "passcode": passcode,
            "latitude": latitude,
            "longitude": longitude,
            "altitude": altitude,
            "situation": situation ?? "rescue_sos",
            "targetText": targetText,
            "batteryLevel": batteryLevel ?? Int(UIDevice.current.batteryLevel * 100)
        ]
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: body.compactMapValues { $0 }) else { return }
        request.httpBody = jsonData
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let httpResp = response as? HTTPURLResponse, (200...299).contains(httpResp.statusCode) {
                    self?.isEmailSent = true
                    print("✅ Emergency SOS Email Sent Successfully via Gmail!")
                } else {
                    print("⚠️ Failed to send SOS Email: \(String(describing: error))")
                }
            }
        }.resume()
    }
    
    /// 遠隔コマンド（Web/Macからの文字変更要求）の監視を開始
    public func startListeningRemoteCommands() {
        stopListeningRemoteCommands()
        // 3秒周期で未実行の遠隔指示をポーリング
        commandPollingTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.checkRemoteCommands()
        }
    }
    
    public func stopListeningRemoteCommands() {
        commandPollingTimer?.invalidate()
        commandPollingTimer = nil
    }
    
    private func checkRemoteCommands() {
        let endpoint = "\(supabaseUrl)/mcp_commands?target_device_id=eq.\(deviceId)&is_executed=eq.false&order=created_at.desc&limit=1"
        guard let url = URL(string: endpoint) else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self, let data = data, error == nil else { return }
            do {
                if let jsonArray = try JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                   let firstCmd = jsonArray.first,
                   let cmdId = firstCmd["id"] as? String,
                   let payload = firstCmd["payload"] as? [String: Any],
                   let text = payload["text"] as? String {
                    
                    let color = payload["color"] as? String
                    DispatchQueue.main.async {
                        self.onRemoteTextReceived?(text, color)
                    }
                    self.markCommandExecuted(id: cmdId)
                }
            } catch {}
        }.resume()
    }
    
    private func markCommandExecuted(id: String) {
        guard let url = URL(string: "\(supabaseUrl)/mcp_commands?id=eq.\(id)") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["is_executed": true])
        URLSession.shared.dataTask(with: request).resume()
    }
}
