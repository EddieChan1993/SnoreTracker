import SwiftUI

@main
struct SnoreTrackerApp: App {
    @StateObject private var store: SleepStore
    @StateObject private var sessionManager: SleepSessionManager
    @StateObject private var themeManager = ThemeManager()

    init() {
        let s = SleepStore()
        _store          = StateObject(wrappedValue: s)
        _sessionManager = StateObject(wrappedValue: SleepSessionManager(store: s))
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
