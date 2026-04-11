import SwiftUI

@main
struct SnoreTrackerApp: App {
    @StateObject private var store = SleepStore()
    @StateObject private var sessionManager: SleepSessionManager

    init() {
        // 先建 store，再把 store 传给 sessionManager
        let s = SleepStore()
        _store = StateObject(wrappedValue: s)
        _sessionManager = StateObject(wrappedValue: SleepSessionManager(store: s))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(sessionManager)
                .preferredColorScheme(.dark)  // 强制深色模式，配合设计
        }
    }
}
