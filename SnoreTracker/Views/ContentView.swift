import SwiftUI

struct ContentView: View {
    @EnvironmentObject var sessionManager: SleepSessionManager

    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("监测", systemImage: "moon.stars.fill")
                }

            ReportsView()
                .tabItem {
                    Label("报告", systemImage: "chart.bar.fill")
                }

            SettingsView()
                .tabItem {
                    Label("设置", systemImage: "gearshape.fill")
                }
        }
        .tint(Color(hex: "6B9FFF"))
        // Dark tab bar
        .onAppear {
            let appearance = UITabBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = UIColor(red: 0.06, green: 0.08, blue: 0.15, alpha: 1)
            UITabBar.appearance().standardAppearance = appearance
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
    }
}
