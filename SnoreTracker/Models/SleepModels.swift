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

    /// 每小时呼噜次数（参考医学 AHI 指标）
    var snoringEventsPerHour: Double {
        guard duration > 3600 / 10 else { return 0 }   // 不足6分钟不计算
        let completed = snoringEvents.filter { $0.endTime != nil }.count
        return Double(completed) / (duration / 3600)
    }

    private func pctLevel(_ p: Double) -> Int {
        switch p {
        case 0..<5:   return 0
        case 5..<15:  return 1
        case 15..<30: return 2
        default:      return 3
        }
    }

    private func cphLevel(_ c: Double) -> Int {
        switch c {
        case 0..<5:   return 0
        case 5..<15:  return 1
        case 15..<30: return 2
        default:      return 3
        }
    }

    /// 综合评分：取「时间占比」与「每小时频次」两项中较差的等级
    var snoringScore: String {
        switch max(pctLevel(snoringPercentage), cphLevel(snoringEventsPerHour)) {
        case 0:  return "优秀"
        case 1:  return "良好"
        case 2:  return "一般"
        default: return "较差"
        }
    }

    var snoringScoreColor: String {
        // Mirror the same dual-metric logic as snoringScore so color matches the label.
        switch max(pctLevel(snoringPercentage), cphLevel(snoringEventsPerHour)) {
        case 0:  return "green"
        case 1:  return "blue"
        case 2:  return "orange"
        default: return "red"
        }
    }
}
