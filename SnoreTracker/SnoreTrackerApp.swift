import SwiftUI
import UIKit

@main
struct SnoreTrackerApp: App {
    @StateObject private var store: SleepStore
    @StateObject private var sessionManager: SleepSessionManager
    @StateObject private var themeManager = ThemeManager()

    init() {
        let s = SleepStore()
        _store          = StateObject(wrappedValue: s)
        _sessionManager = StateObject(wrappedValue: SleepSessionManager(store: s))
        // 防止打开/关闭 app 时出现白色过渡帧（UIWindow 默认背景为白色）
        UIWindow.appearance().backgroundColor = UIColor(red: 0.039, green: 0.059, blue: 0.118, alpha: 1)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(sessionManager)
                .environmentObject(themeManager)
                .preferredColorScheme(.dark)
        }
    }
}
