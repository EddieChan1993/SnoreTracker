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

        // 在首次渲染前设好深色背景，防止启动/关闭动画出现白色角落
        let savedID = UserDefaults.standard.string(forKey: "selectedThemeID") ?? "dark"
        let theme   = AppTheme.all.first { $0.id == savedID } ?? .dark
        UIWindow.appearance().backgroundColor = theme.tabBarBackground
        let tabBar = UITabBarAppearance()
        tabBar.configureWithOpaqueBackground()
        tabBar.backgroundColor = theme.tabBarBackground
        UITabBar.appearance().standardAppearance   = tabBar
        UITabBar.appearance().scrollEdgeAppearance = tabBar
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
