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
    
    // 遠隔コマンド受信時のコールバック（文字の書き換え等）
    public var onRemoteTextReceived: ((String, String?) -> Void)?
    
    private init() {
        if let vendorId = UIDevice.current.identifierForVendor?.uuidString {
            self.deviceId = "iPhone-" + String(vendorId.prefix(6))
        } else {
            self.deviceId = "iPhone-RescuePOV"
        }
    }
    
    /// 緊急救難イベントをSupabaseに発信（非同期・バックグラウンド実行）
    public func publishRescueEvent(
        latitude: Double?,
        longitude: Double?,
        altitude: Double?,
        situation: String?,
        targetText: String,
        color: String,
        batteryLevel: Int?
    ) {
        guard let url = URL(string: "\(supabaseUrl)/rescue_events") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        
        let payload: [String: Any?] = [
            "device_id": deviceId,
            "latitude": latitude,
            "longitude": longitude,
            "altitude": altitude,
            "situation": situation ?? "rescue_sos",
            "target_text": targetText,
            "color": color,
            "battery_level": batteryLevel ?? Int(UIDevice.current.batteryLevel * 100),
            "is_active": true
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
