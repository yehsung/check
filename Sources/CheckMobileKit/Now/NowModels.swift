import CheckCore
import Foundation

// 지금 탭의 값·순수 계산·문구(SPEC-ios §3.2). 화면 없이 값으로 검증한다(`NowStoreTests`).
// 플랫폼 무관 — macOS `swift test` 가 이 파일을 그대로 돈다.

// MARK: - 문구

/// 지금 탭 문구. 맥과 뜻이 같은 문장은 맥 글자 그대로 옮겼다(할 일 보드 `TodoBoardStrings` · 목표 편집 `updateTeamGoal`).
package enum NowText {
    package static let title = "지금"

    // 내 상태
    package static let workingOnMac = "맥에서 근무 중"
    package static let notWorking = "근무 안 함"
    /// 맥 팀 카드 `PresenceChip` 의 stale 문구와 같다.
    package static let connectionLost = "연결 끊김"
    package static let todayLabel = "오늘 누적"
    package static let noTeamTitle = "팀에 속해 있지 않아요"
    package static let noTeamBody = "맥 앱에서 팀에 참여하면 근무 시간과 주간 목표가 여기에 보여요"
    package static let loadFailed = "지금 상태를 불러오지 못했어요. 아래로 당겨 다시 시도해 주세요"
    /// 네트워크 실패 띠 — 탭 공용 문장(`MobileLoadText.checkConnection`). 절마다 [다시 시도]가 곁에 있다.
    package static let networkFailed = MobileLoadText.checkConnection

    // 주간 목표(맥 `updateTeamGoal` 문구)
    package static let goalEdit = "주간 목표 수정"
    package static let goalSheetTitle = "주간 목표"
    package static let goalStepperLabel = "1인당 주간 목표"
    /// 개인 목표가 아니라 **팀 전체의 1인당 목표**다(ios-inventory §9-4). 권한은 맥과 같다 — 팀원 누구나.
    package static let goalExplain = "팀 전체의 1인당 목표가 함께 바뀌어요. 팀원 누구나 바꿀 수 있어요."
    package static let goalSave = "목표 저장"
    package static let goalSaved = "주간 목표 변경됨"
    package static let goalFailed = "목표 변경 실패"
    package static let close = "닫기"

    // 오늘 할 일(맥 `TodoBoardStrings` 와 같은 뜻은 같은 글자)
    package static let todoTitle = "오늘 할 일"
    package static let todoPlaceholder = "할 일 추가"
    package static let todoEditPlaceholder = "할 일 수정"
    package static let todoAdd = "추가"
    package static let todoEmptyTitle = "오늘 할 일이 비어 있어요"
    package static let todoEmptyHint = "위 칸에 적고 완료를 누르면 추가돼요"
    package static let todoDeleted = "삭제됨"
    package static let todoUndo = "되돌리기"
    package static let todoFooter = "내 계정에 저장돼 다른 기기와 맞춰져요"
    package static let todoMarkDone = "완료로 표시"
    package static let todoMarkUndone = "완료 취소"
    package static let todoDelete = "삭제"
    package static let todoEdit = "수정"

    package static func todoOldSection(count: Int) -> String { "오래된 항목 (\(count))" }
    package static func todoRemaining(count: Int) -> String { "남은 \(count)개" }
    package static func todoCounter(current: Int) -> String { "\(current)/\(TodoRules.maxTitleLength)" }

    /// 불러오기가 끝났는데 팀 상태를 모를 때(스피너 대신).
    package static let statusUnavailableTitle = "내 상태를 불러오지 못했어요"
    package static let workingUnavailable = "근무 중인 사람을 불러오지 못했어요"
    package static let retry = MobileLoadText.retry

    // 지금 근무 중
    /// 머리글. 모를 때(nil)는 숫자를 숨긴다 — 불러오지 못했는데 "0"이면 아무도 일하지 않는다는 말이 된다.
    package static func workingTitle(count: Int?) -> String {
        guard let count else { return "지금 근무 중" }
        return "지금 근무 중 \(count)"
    }
    package static let ourTeam = "우리 팀"
    package static let otherTeams = "다른 팀"
    package static let workingEmpty = "지금 근무 중인 사람이 없어요"
    package static let workingChip = "근무 중"
}

// MARK: - 팀 소속

/// `fetchOwnMembership` 의 결과(주 팀 하나).
package struct NowMembership: Equatable, Sendable {
    package var teamID: String
    package var teamName: String
    package var goalHours: Int
    package var role: String

    package init(teamID: String, teamName: String, goalHours: Int, role: String) {
        self.teamID = teamID
        self.teamName = teamName
        self.goalHours = goalHours
        self.role = role
    }
}

// MARK: - 내 상태 카드

/// 내 상태 카드 한 장의 값(시각 `now` 기준 — 뷰가 1초마다 다시 만든다).
package struct NowMyCard: Equatable, Sendable {
    /// 맥에서 근무 중인가(서버 `work_statuses.status`).
    package var isWorking: Bool
    /// 근무 중인데 생존신호가 끊겼다(맥 팀 카드의 "연결 끊김"). 시간은 마지막 신호에서 멈춘다.
    package var isStale: Bool
    /// 진행 중 세션의 서버 시작 시각(근무 중일 때만).
    package var sessionStartedAt: Date?
    package var todaySeconds: Int
    package var weekSeconds: Int
    package var goalHours: Int

    package var goalSeconds: Int { max(1, goalHours) * 3600 }
    package var progress: Double { TeamWeeklyGoal(workedSeconds: weekSeconds, goalSeconds: goalSeconds).progress }
    package var isGoalComplete: Bool { weekSeconds >= goalSeconds }
    package var percent: Int { NowFormat.percent(workedSeconds: weekSeconds, goalSeconds: goalSeconds) }

    /// "이번 주 24.8시간 · 목표 40시간 · 62%"(SPEC-ios §3.2).
    package var weekLine: String {
        "이번 주 \(NowFormat.hoursOneDecimal(weekSeconds))시간 · 목표 \(goalHours)시간 · \(percent)%"
    }
}

// MARK: - 지금 근무 중 한 사람

/// "지금 근무 중" 한 줄. 우리 팀은 경과 시간이 있고, 다른 팀은 근무 여부만 있다(서버가 시간을 주지 않는다 — ios-inventory §9-1).
package struct NowWorkingPerson: Identifiable, Equatable, Sendable {
    package var id: String
    package var name: String
    package var avatarURL: URL?
    /// 센터 서버값(표시는 `CenterLabel` 한 곳).
    package var center: String?
    package var isTeammate: Bool
    /// 우리 팀만: 서버 세션 시작 시각.
    package var startedAt: Date?
    /// 우리 팀만: 이 시각의 경과(초). stale 이면 마지막 신호에서 멈춘 값.
    package var elapsedSeconds: Int?
    package var isStale: Bool

    package init(
        id: String, name: String, avatarURL: URL?, center: String?, isTeammate: Bool,
        startedAt: Date?, elapsedSeconds: Int?, isStale: Bool
    ) {
        self.id = id
        self.name = name
        self.avatarURL = avatarURL
        self.center = center
        self.isTeammate = isTeammate
        self.startedAt = startedAt
        self.elapsedSeconds = elapsedSeconds
        self.isStale = isStale
    }
}

// MARK: - 시간 계산(순수)

/// 폰이 세는 오늘·이번 주(서버 세션 시각 기준). 맥 `TeamMemberStatus` 의 live 계산을 쓰되, **오늘은 KST 자정으로 자른다** —
/// 코어 `liveTodayDurationSeconds` 는 진행 세션을 시작 시각부터 통째로 더해 자정을 넘긴 세션이 어제 몫까지 오늘로 센다.
///
/// **신호 끊김(stale) 판정 시각 `presenceAt`** 은 화면 시각 `now` 와 따로 받는다. 맥은 30초마다 자기 팀 상태를 다시 읽어
/// "지금 − 마지막 신호 > 90초"를 now 로 재도 되지만, 폰은 60초마다(또 background 에서 돌아와서야) 받는다 — now 로 재면
/// 받을 때 29초 묵은 신호가 다음 응답 직전 몇 초 동안, background 에서 돌아온 직후에는 응답이 올 때까지 "연결 끊김"으로
/// 뒤집히고 오늘 누적이 마지막 신호 지점으로 뒤로 뛴다(now-verify R1·R2). 스토어가 판정 시각을 고른다(`NowStore.presenceJudgedAt`).
package enum NowTimeMath {
    /// 오늘 누적(초). `fetchedAt` = 그 행을 받은 시각 — 받은 뒤 자정이 지났으면 서버가 준 "오늘 끝난 세션 합"은 어제 몫이라 버린다.
    package static func todaySeconds(_ member: TeamMemberStatus, fetchedAt: Date, now: Date, presenceAt: Date? = nil) -> Int {
        let dayStart = TeamWeeklyGoal.koreanDayStart(for: now)
        let closed = TeamWeeklyGoal.koreanDayStart(for: fetchedAt) == dayStart ? member.todayDurationSeconds : 0
        return max(0, closed) + currentContribution(member, windowStart: dayStart, now: now, presenceAt: presenceAt)
    }

    /// 이번 주 누적(초). 받은 뒤 주가 바뀌었으면 지난 주 합은 버린다.
    package static func weekSeconds(_ member: TeamMemberStatus, fetchedAt: Date, now: Date, presenceAt: Date? = nil) -> Int {
        let weekStart = TeamWeeklyGoal.koreanWeekStart(for: now)
        let closed = TeamWeeklyGoal.koreanWeekStart(for: fetchedAt) == weekStart ? member.weeklyDurationSeconds : 0
        return max(0, closed) + currentContribution(member, windowStart: weekStart, now: now, presenceAt: presenceAt)
    }

    /// 진행 세션의 [windowStart, 끝] 기여. 끝은 살아 있으면 now, 신호가 끊겼으면 마지막 신호(맥 규칙과 같다).
    /// 끊김 판정은 `presenceAt`(없으면 now) 에서 한다.
    package static func currentContribution(_ member: TeamMemberStatus, windowStart: Date, now: Date, presenceAt: Date? = nil) -> Int {
        guard member.status == .working, let started = member.currentSessionStartedAt else { return 0 }
        let end: Date
        if isStale(member, now: presenceAt ?? now) {
            end = member.lastSeenAt ?? member.updatedAt ?? started
        } else {
            end = now
        }
        return max(0, Int(min(end, now).timeIntervalSince(max(started, windowStart))))
    }

    /// 진행 세션 경과(초 — 우리 팀 "지금 근무 중" 줄). 끊겼으면 마지막 신호에서 멈춘 값, 아니면 now 까지.
    package static func elapsedSeconds(_ member: TeamMemberStatus, now: Date, presenceAt: Date? = nil) -> Int {
        guard member.status == .working, let started = member.currentSessionStartedAt else { return 0 }
        if case .staleWorking(let frozen) = member.presence(now: presenceAt ?? now) { return frozen }
        return max(0, Int(now.timeIntervalSince(started)))
    }

    package static func isStale(_ member: TeamMemberStatus, now: Date) -> Bool {
        if case .staleWorking = member.presence(now: now) { return true }
        return false
    }
}

// MARK: - 불러오기 상태

/// 우리 팀 상태(내 카드 · 지금 근무 중)를 화면이 어떻게 그릴지.
/// - loading: 이 세대에서 새로고침이 아직 한 번도 끝나지 않았다(스피너).
/// - failed: 시도는 끝났는데 팀 상태를 모른다(오프라인 · 5xx) — 스피너를 남기지 않고 "불러오지 못했어요"를 보인다.
///   다시 시도하는 동안에도 failed 를 유지한다(60초 주기마다 스피너 ↔ 실패 줄이 깜빡이지 않게 — 당겨서 새로고침 표시가 진행을 말한다).
/// - loaded: 팀 상태를 받았거나 소속 없음이 확정됐다.
package enum NowLoadState: Equatable, Sendable {
    case loading
    case failed
    case loaded
}

// MARK: - 서식(순수)

package enum NowFormat {
    /// 시·분·초 "3:25:07"(오늘 누적 큰 숫자).
    package static func clock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }

    /// 시:분 "2:05"(우리 팀 경과).
    package static func hoursMinutes(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return String(format: "%d:%02d", s / 3600, (s % 3600) / 60)
    }

    /// 소수 한 자리 시간 "24.8". **내림**이다 — 39.96시간을 "40.0"으로 올려 목표를 채운 것처럼 보이지 않게.
    package static func hoursOneDecimal(_ seconds: Int) -> String {
        let tenths = max(0, seconds) * 10 / 3600
        return "\(tenths / 10).\(tenths % 10)"
    }

    /// 목표 퍼센트(맥 `GoalPercentFormatter.percent` 와 같은 식 — 반올림 · 0~999).
    package static func percent(workedSeconds: Int, goalSeconds: Int) -> Int {
        let worked = max(0, workedSeconds)
        let goal = max(1, goalSeconds)
        let raw = Int((Double(worked) / Double(goal) * 100).rounded())
        return min(999, max(0, raw))
    }

    /// VoiceOver 용 "3시간 25분".
    package static func spokenDuration(_ seconds: Int) -> String {
        let s = max(0, seconds)
        let hours = s / 3600, minutes = (s % 3600) / 60
        if hours == 0 { return "\(minutes)분" }
        return "\(hours)시간 \(minutes)분"
    }
}

// MARK: - 할 일 입력(순수 — 맥 `TodoDraftInput` 과 같은 규칙)

package enum NowTodoDraft {
    /// 새 입력을 반영할지. 지우는 방향은 늘 통과, 늘리는 방향은 100자(코드 포인트 1000)까지 — 넘으면 **변경을 되돌린다**
    /// (잘라 넣지 않는다: 붙여넣은 문장 끝이 소리 없이 사라지면 "분명 적었는데 없어졌다"가 된다).
    package static func accepted(current: String, proposed: String) -> String {
        if proposed.count <= current.count, proposed.unicodeScalars.count <= current.unicodeScalars.count { return proposed }
        return TodoRules.titleFitsLimits(proposed) ? proposed : current
    }

    /// 카운터 "92/100". 90자 전에는 nil(숫자가 아예 안 뜬다).
    package static func counterText(_ text: String) -> String? {
        guard text.count >= TodoRules.counterVisibleFrom else { return nil }
        return NowText.todoCounter(current: text.count)
    }
}

/// 할 일 한 줄의 화면 값.
package struct NowTodoRow: Identifiable, Equatable, Sendable {
    package var id: UUID
    package var title: String
    package var isDone: Bool
    /// "어제" · "3일 전"(오늘 만든 것은 nil).
    package var carryBadge: String?
    package var carryOverDays: Int
}
