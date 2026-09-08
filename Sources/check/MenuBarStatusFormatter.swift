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
    /// 메뉴바 라벨 하나(아이콘 + 글자)가 차지해도 되는 최대 폭(pt).
    ///
    /// 메뉴바 오른쪽은 다른 앱과 나눠 쓰는 공간이고, 이 앱은 그중 한 칸을 상시 점유한다. 최장 라벨은
    /// 근무 중 "23:59"(monospacedDigit 5칸)이고, 그 폭을 상수로 고정해 다음 사람이 라벨을 더 길게
    /// 바꾸면 테스트가 먼저 막게 한다.
    /// (**예산을 키워서 통과시키면 메뉴바에서 잘린다.**)
    static let maxLabelWidth: CGFloat = 82

    static func title(for snapshot: WorkStatusSnapshot) -> String {
        // 동기화 대기가 먼저다. 큐에 근무 조작이 남아 있다는 사실이 시계보다 급하다.
        if snapshot.pendingSync {
            return "대기"
        }

        switch snapshot.status {
        case .working:
            // 제목은 **항상 시:분**(titleDuration)이다 — duration(MM:SS) 을 쓰면 첫 1시간 동안 초가 보여
            // 티커를 1초로 묶는다(v0.2.43 배터리 3번, 사용자 결정).
            return titleDuration(snapshot.elapsedSeconds)
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

    /// **메뉴바 제목·캐릭터 라벨 전용** 근무 시간 표기 — 항상 `HH:MM`(초는 내림). 5분 → "00:05", 1시간 23분 → "01:23".
    ///
    /// v0.2.43 부터 시:분이다(사용자 결정, 배터리 3번). 두 상시 표면(메뉴바·캐릭터)이 초를 보이지 않아야 팝오버가 닫힌
    /// 동안 티커를 분 경계 60초로 늦출 수 있다 — 첫 1시간에 MM:SS 를 남겨 두면 그 시간 내내 1초 틱이 필요해 감속의
    /// 뜻이 없다(WorkTimerStore.nextTickDelay). 팝오버 **안**의 오늘 시계·팀원 "현재 …" 는 여전히 `duration` 이다.
    static func titleDuration(_ seconds: Int) -> String {
        let safeSeconds = max(0, seconds)
        let hours = safeSeconds / 3600
        let minutes = (safeSeconds % 3600) / 60
        return String(format: "%02d:%02d", hours, minutes)
    }

    /// 팝오버 안 근무 시간 표기 — 1시간 미만 MM:SS(초가 흐른다), 이상 HH:MM. 팝오버 오늘 시계(displayNow 로 매초)와
    /// 팀원 목록 "현재 …" 가 쓴다. 메뉴바 제목은 이 함수가 아니라 `titleDuration` 이다(위 주석).
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
