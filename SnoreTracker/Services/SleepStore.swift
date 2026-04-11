import Foundation
import Combine

class SleepStore: ObservableObject {
    @Published var sessions: [SleepSession] = []

    private let storageURL: URL = {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("sleep_sessions.json")
    }()

    init() {
        load()
    }

    func save() {
        do {
            let data = try JSONEncoder().encode(sessions)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("SleepStore save error: \(error)")
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }
        do {
            let data = try Data(contentsOf: storageURL)
            sessions = try JSONDecoder().decode([SleepSession].self, from: data)
        } catch {
            print("SleepStore load error: \(error)")
        }
    }

    func addSession(_ session: SleepSession) {
        sessions.insert(session, at: 0)
        save()
    }

    func updateSession(_ session: SleepSession) {
        if let idx = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[idx] = session
            save()
        }
    }

    func deleteSession(_ session: SleepSession) {
        // Delete all associated recording files
        for event in session.snoringEvents {
            if let url = event.recordingURL {
                try? FileManager.default.removeItem(at: url)
            }
        }
        sessions.removeAll { $0.id == session.id }
        save()
    }
}
