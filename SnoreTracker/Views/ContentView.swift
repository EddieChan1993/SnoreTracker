import SwiftUI

struct ContentView: View {
    @EnvironmentObject var sessionManager: SleepSessionManager
    @EnvironmentObject var themeManager: ThemeManager

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("监测", systemImage: "moon.stars.fill") }

            ReportsView()
                .tabItem { Label("报告", systemImage: "chart.bar.fill") }

            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape.fill") }
        }
        .tint(themeManager.current.accent)
        .onChange(of: themeManager.selectedThemeID) { _, _ in
            applyTabBarAppearance()
        }
        .onAppear {
            applyTabBarAppearance()
        }
    }

    private func applyTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = themeManager.current.tabBarBackground
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}
