import SwiftUI
import UIKit

/// シェイクによる「Undo Typing（取り消し）」アラートをアプリ全体で完全無効化するAppDelegate
final class RescuePOVAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil
    ) -> Bool {
        application.applicationSupportsShakeToEdit = false
        return true
    }
}

/// UIWindowレベルでシェイクイベント（.motionShake）を握り潰し、システムダイアログの表示を根本遮断
extension UIWindow {
    open override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        if motion == .motionShake {
            // POVスイング中に「Undo Typing（シェイクで取り消し）」が出るのを完全に阻止
            return
        }
        super.motionEnded(motion, with: event)
    }
}

@main
struct RescuePOVApp: App {
    @UIApplicationDelegateAdaptor(RescuePOVAppDelegate.self) var appDelegate
    
    init() {
        // iPhoneを激しく振った際に「Undo Typing（シェイクで取り消し）」アラートが出るのを完全無効化
        UIApplication.shared.applicationSupportsShakeToEdit = false
    }
    
    var body: some Scene {
        WindowGroup {
            MainDashboardView()
                .onAppear {
                    UIApplication.shared.applicationSupportsShakeToEdit = false
                }
        }
    }
}
