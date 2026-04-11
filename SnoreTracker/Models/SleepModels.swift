import Foundation

struct SnoringEvent: Codable, Identifiable {
    let id: UUID
    let startTime: Date
    var endTime: Date?
    let recordingFilename: String

    var duration: TimeInterval {
        (endTime ?? Date()).timeIntervalSince(startTime)
    }

    var recordingURL: URL? {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent(recordingFilename)
    }
}

struct SleepSession: Codable, Identifiable {
    let id: UUID
    let startTime: Date
    var endTime: Date?
    var snoringEvents: [SnoringEvent]

    var duration: TimeInterval {
        (endTime ?? Date()).timeIntervalSince(startTime)
    }

    var totalSnoringTime: TimeInterval {
        snoringEvents.filter { $0.endTime != nil }.reduce(0) { $0 + $1.duration }
    }

    var snoringPercentage: Double {
        guard duration > 0 else { return 0 }
        return min(totalSnoringTime / duration * 100, 100)
    }

    var snoringScore: String {
        switch snoringPercentage {
        case 0..<5:   return "优秀"
        case 5..<15:  return "良好"
        case 15..<30: return "一般"
        default:      return "较差"
        }
    }

    var snoringScoreColor: String {
        switch snoringPercentage {
        case 0..<5:   return "green"
        case 5..<15:  return "blue"
        case 15..<30: return "orange"
        default:      return "red"
        }
    }
}
