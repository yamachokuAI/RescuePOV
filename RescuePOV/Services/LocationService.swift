import Foundation
import CoreLocation

/// 救助要請用GPS位置情報サービス
public final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    public static let shared = LocationService()
    
    private let locationManager = CLLocationManager()
    
    @Published public private(set) var latitude: Double?
    @Published public private(set) var longitude: Double?
    @Published public private(set) var altitude: Double?
    @Published public private(set) var accuracy: Double?
    @Published public private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined
    
    public override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
    }
    
    public func requestLocation() {
        if authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
        locationManager.startUpdatingLocation()
    }
    
    public func stopUpdating() {
        locationManager.stopUpdatingLocation()
    }
    
    // CLLocationManagerDelegate
    public func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        self.authorizationStatus = manager.authorizationStatus
        if authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways {
            locationManager.startUpdatingLocation()
        }
    }
    
    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        self.latitude = location.coordinate.latitude
        self.longitude = location.coordinate.longitude
        self.altitude = location.altitude
        self.accuracy = location.horizontalAccuracy
    }
    
    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("位置情報取得エラー: \(error.localizedDescription)")
    }
    
    /// 度分秒表記（遭難・無線報告用）
    public var formattedDMS: String {
        guard let lat = latitude, let lon = longitude else {
            return "位置情報取得中..."
        }
        
        let latDirection = lat >= 0 ? "北緯" : "南緯"
        let lonDirection = lon >= 0 ? "東経" : "西経"
        
        let latStr = formatToDMS(abs(lat))
        let lonStr = formatToDMS(abs(lon))
        
        return "\(latDirection) \(latStr) / \(lonDirection) \(lonStr)"
    }
    
    /// 10進数表記（地図アプリ用）
    public var formattedDecimal: String {
        guard let lat = latitude, let lon = longitude else {
            return "--"
        }
        return String(format: "%.5f, %.5f", lat, lon)
    }
    
    private func formatToDMS(_ value: Double) -> String {
        let degrees = Int(value)
        let minutesNotTruncated = (value - Double(degrees)) * 60.0
        let minutes = Int(minutesNotTruncated)
        let seconds = (minutesNotTruncated - Double(minutes)) * 60.0
        return String(format: "%d°%02d'%04.1f\"", degrees, minutes, seconds)
    }
}
