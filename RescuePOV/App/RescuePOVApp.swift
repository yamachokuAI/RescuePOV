import SwiftUI

@main
struct RescuePOVApp: App {
    @State private var isInDashboard: Bool = false
    
    var body: some Scene {
        WindowGroup {
            if isInDashboard {
                MainDashboardView()
            } else {
                // アプリ起動直後は即座に救難POV（HELP・最大光量・往復同期）が全画面でスタンバイ
                POVFullscreenView(
                    text: "HELP",
                    direction: .horizontal,
                    color: .white,
                    onDismiss: {
                        withAnimation {
                            isInDashboard = true
                        }
                    }
                )
            }
        }
    }
}
