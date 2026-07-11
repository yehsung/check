import Foundation

struct WorkStatusSnapshot: Equatable {
    var status: WorkStatus
    var elapsedSeconds: Int
    var pendingSync: Bool = false

    var isWorking: Bool {
        status == .working
    }

    var localizedStatus: String {
        if pendingSync {
            return "동기화 대기"
        }

        switch status {
        case .working:
            return "근무중"
        case .offWork:
            return "근무종료"
        }
    }
}

enum WorkStatus: Equatable {
    case working
    case offWork

    var localizedStatus: String {
        switch self {
        case .working:
            return "근무중"
        case .offWork:
            return "근무종료"
        }
    }
}

enum MenuBarStatusFormatter {
    static func title(for snapshot: WorkStatusSnapshot) -> String {
        if snapshot.pendingSync {
            return "대기"
        }

        switch snapshot.status {
        case .working:
            return duration(snapshot.elapsedSeconds)
        case .offWork:
            return "오프"
        }
    }

    static func symbolName(for snapshot: WorkStatusSnapshot) -> String {
        if snapshot.pendingSync {
            return "exclamationmark.icloud.fill"
        }

        switch snapshot.status {
        case .working:
            return "figure.run.circle.fill"
        case .offWork:
            return "pause.circle.fill"
        }
    }

    static func duration(_ seconds: Int) -> String {
        let safeSeconds = max(0, seconds)
        let hours = safeSeconds / 3600
        let minutes = (safeSeconds % 3600) / 60

        if hours > 0 {
            return String(format: "%02d:%02d", hours, minutes)
        }

        let secs = safeSeconds % 60
        return String(format: "%02d:%02d", minutes, secs)
    }

    static func hoursMinutes(_ seconds: Int) -> String {
        let safeSeconds = max(0, seconds)
        let hours = safeSeconds / 3600
        let minutes = (safeSeconds % 3600) / 60
        return "\(hours)시간 \(String(format: "%02d", minutes))분"
    }
}
