import CheckCore
import CheckMobileShared
import Foundation

// 위젯 3종의 값·순수 계산·문구(SPEC-ios §4). 플랫폼 무관 — macOS `swift test` 로 검증하고, iOS 화면(`Widgets/`)은 이 값만 그린다.
// 위젯은 앱이 쓴 스냅샷(`WidgetSnapshot`)만 읽는다. 네트워크는 할 일 체크 인텐트의 todo_sync 한 번뿐이다(`WidgetTodoToggle`).

// MARK: - 종류 · 문구

/// 위젯 kind(갤러리·타임라인 새로고침의 이름). 바꾸면 사용자가 홈 화면에 둔 위젯이 사라진다 — 고정한다.
package enum AingWidgetKind {
    package static let workingNow = "AingWorkingNow"
    package static let myToday = "AingMyToday"
    package static let todos = "AingTodos"
    package static let all = [workingNow, myToday, todos]
}

package enum AingWidgetText {
    package static let signedOut = "앱에서 로그인해 주세요"
    package static let noData = "앱을 열면 채워져요"
    /// 소속 없는 사용자의 "내 오늘"(앱 지금 탭의 "팀에 속해 있지 않아요"와 같은 뜻 — 앱을 열어도 채워지지 않는다).
    package static let noTeam = "맥 앱에서 팀에 참여하면 보여요"

    package static let workingTitle = "지금 근무 중"
    package static let workingEmpty = "지금 근무 중인 사람이 없어요"
    package static let teammate = "우리 팀"
    package static func people(_ count: Int) -> String { "\(count)명" }
    package static func morePeople(_ count: Int) -> String { "외 \(count)명" }

    package static let workingOnMac = "맥에서 근무 중"
    package static let notWorking = "근무 안 함"
    package static let today = "오늘"
    package static let thisWeek = "이번 주"
    package static func weekGoalSpoken(_ percent: Int) -> String { "이번 주 목표 \(percent)%" }

    package static let todoTitle = "오늘 할 일"
    package static let todoEmpty = "오늘 할 일이 비어 있어요"
    package static let todoEmptyHint = "앱에서 추가해 보세요"
    package static let todoMarkDone = "완료로 표시"
    package static let todoMarkUndone = "완료 취소"
    package static func todoRemaining(_ count: Int) -> String { "남은 \(count)개" }
    package static func more(_ count: Int) -> String { "외 \(count)개" }

    // 위젯 갤러리
    package static let workingGalleryName = "지금 근무 중"
    package static let workingGalleryDescription = "지금 근무 중인 사람을 우리 팀부터 보여 줘요."
    package static let myTodayGalleryName = "내 오늘"
    package static let myTodayGalleryDescription = "오늘 누적과 이번 주 목표를 보여 줘요."
    package static let todoGalleryName = "오늘 할 일"
    package static let todoGalleryDescription = "체크하면 앱을 열지 않아도 완료로 표시돼요."
}

// MARK: - 서식

package enum AingWidgetFormat {
    /// 오른쪽 아래 "N분 전"(스냅샷을 만든 시각 기준). 미래(시계 차)는 "방금".
    package static func ago(from generatedAt: Date, now: Date) -> String {
        let seconds = now.timeIntervalSince(generatedAt)
        if seconds < 60 { return "방금" }
        if seconds < 3600 { return "\(Int(seconds / 60))분 전" }
        if seconds < 86_400 { return "\(Int(seconds / 3600))시간 전" }
        return "\(Int(seconds / 86_400))일 전"
    }

    /// "3시간 25분"(멈춘 시간 표시 · VoiceOver).
    package static func hoursMinutes(_ seconds: Int) -> String {
        let s = max(0, seconds)
        let hours = s / 3600, minutes = (s % 3600) / 60
        if hours == 0 { return "\(minutes)분" }
        return "\(hours)시간 \(minutes)분"
    }

    /// 소수 한 자리 시간(내림) "24.8" — 앱 카드와 같은 규칙.
    package static func hoursOneDecimal(_ seconds: Int) -> String {
        let tenths = max(0, seconds) * 10 / 3600
        return "\(tenths / 10).\(tenths % 10)"
    }

    /// 목표 퍼센트(반올림 · 0~999, 맥 `GoalPercentFormatter` 와 같은 식).
    package static func percent(workedSeconds: Int, goalSeconds: Int) -> Int {
        let raw = Int((Double(max(0, workedSeconds)) / Double(max(1, goalSeconds)) * 100).rounded())
        return min(999, max(0, raw))
    }
}

// MARK: - 내 오늘 · 이번 주(시각 투영)

/// 스냅샷의 "나"를 타임라인 칸의 시각으로 옮긴 값. 앱이 스냅샷을 쓴 뒤로 흐른 시간을 위젯이 스스로 더한다.
///
/// - 근무 중이고 세션 시작 시각이 있으면 **센다**(오늘·이번 주 모두). 연결이 끊긴 세션은 앱이 시작 시각을 싣지 않아 멈춘 값이다.
/// - 스냅샷 뒤 KST 자정이 지났으면 오늘은 0 부터(근무 중이면 자정부터 센다). 주(월요일 0시)도 같다.
/// - 스냅샷이 12시간 넘게 낡았으면 세지 않는다 — 앱을 안 연 사이 맥 세션이 끝났을 수 있는데 끝없이 늘어나는 숫자는 거짓말이다
///   (그 시점 값에서 멈추고, 오른쪽 아래 "N시간 전"이 낡았다는 사실을 말한다).
package struct AingWidgetMe: Equatable, Sendable {
    package static let maxTickingAge: TimeInterval = 12 * 3600

    package let isWorking: Bool
    package let isTicking: Bool
    package let todaySeconds: Int
    package let weekSeconds: Int
    package let goalHours: Int

    package init(me: WidgetSnapshot.Me, generatedAt: Date, at date: Date) {
        let age = max(0, date.timeIntervalSince(generatedAt))
        let canTick = me.working && me.sessionStartedAt != nil
        let ticking = canTick && age < Self.maxTickingAge
        // 더할 시간: 세는 동안은 흐른 만큼, 낡아서 멈췄으면 12시간 지점까지, 원래 멈춘 값이면 0.
        let elapsed = canTick ? Int(min(age, Self.maxTickingAge)) : 0
        let start = me.sessionStartedAt ?? generatedAt

        // 스냅샷과 칸이 다른 날(주)이면 스냅샷의 누적은 지난 날(주) 몫이다 — 세는 중이면 경계부터 새로 세고, 아니면 0(모른다).
        let dayStart = TeamWeeklyGoal.koreanDayStart(for: date)
        if TeamWeeklyGoal.koreanDayStart(for: generatedAt) == dayStart {
            todaySeconds = max(0, me.todaySeconds) + elapsed
        } else {
            todaySeconds = ticking ? max(0, Int(date.timeIntervalSince(max(start, dayStart)))) : 0
        }
        let weekStart = TeamWeeklyGoal.koreanWeekStart(for: date)
        if TeamWeeklyGoal.koreanWeekStart(for: generatedAt) == weekStart {
            weekSeconds = max(0, me.weekSeconds) + elapsed
        } else {
            weekSeconds = ticking ? max(0, Int(date.timeIntervalSince(max(start, weekStart)))) : 0
        }
        isWorking = me.working
        isTicking = ticking
        goalHours = max(0, me.goalHours)
    }

    package var goalSeconds: Int { max(1, goalHours) * 3600 }
    package var progress: Double { min(1, Double(weekSeconds) / Double(goalSeconds)) }
    package var percent: Int { AingWidgetFormat.percent(workedSeconds: weekSeconds, goalSeconds: goalSeconds) }
    package var isGoalComplete: Bool { weekSeconds >= goalSeconds }

    /// `Text(timerInterval:)` 의 시작점(= 칸 시각 − 오늘 누적). 세는 중일 때만.
    package func timerStart(at date: Date) -> Date? {
        isTicking ? date.addingTimeInterval(-Double(todaySeconds)) : nil
    }

    /// "24.8/40시간"
    package var weekCaption: String { "\(AingWidgetFormat.hoursOneDecimal(weekSeconds))/\(goalHours)시간" }
}

/// "내 오늘" 위젯이 그릴 것.
package enum AingWidgetMyTodayState: Equatable, Sendable {
    /// 앱이 아직 내 상태를 한 번도 못 받았다 → "앱을 열면 채워져요".
    case noData
    /// 팀 소속이 없다 → "맥 앱에서 팀에 참여하면 보여요". 앱은 **목표 0시간인 me** 로 싣는다(`NowStore.widgetNoTeamMe`) —
    /// 스냅샷 모양에 소속 칸이 없어서다. 서버 목표는 1~168 이라 소속 있는 사용자의 me 는 0 이 아니다.
    case noTeam
    case me(AingWidgetMe)

    package init(snapshot: WidgetSnapshot, at date: Date) {
        guard let me = snapshot.me else {
            self = .noData
            return
        }
        if me.goalHours <= 0 {
            self = .noTeam
            return
        }
        self = .me(AingWidgetMe(me: me, generatedAt: snapshot.generatedAt, at: date))
    }
}

// MARK: - 지금 근무 중(고르기)

/// 우리 팀 먼저(앱이 준 순서 유지), 그다음 다른 팀. `limit` 명만 보이고 나머지는 "외 N명".
package struct AingWidgetWorking: Equatable, Sendable {
    package let total: Int
    package let shown: [WidgetSnapshot.WorkingPerson]
    package let hiddenCount: Int

    package init(_ working: [WidgetSnapshot.WorkingPerson], limit: Int) {
        let ordered = working.filter(\.teammate) + working.filter { !$0.teammate }
        total = ordered.count
        shown = Array(ordered.prefix(max(0, limit)))
        hiddenCount = max(0, total - shown.count)
    }
}

// MARK: - 오늘 할 일(고르기)

package struct AingWidgetTodos: Equatable, Sendable {
    package let rows: [WidgetSnapshot.TodoPreview]
    /// 스냅샷 안의 미완료 수(위젯이 체크한 줄도 반영된다).
    package let remaining: Int
    package let hiddenCount: Int

    package init(_ previews: [WidgetSnapshot.TodoPreview], limit: Int) {
        rows = Array(previews.prefix(max(0, limit)))
        remaining = previews.filter { !$0.isCompleted }.count
        hiddenCount = max(0, previews.count - rows.count)
    }

    /// "어제" · "3일 전"(코어 규칙과 같은 문구).
    package static func carryBadge(_ preview: WidgetSnapshot.TodoPreview) -> String? {
        TodoRules.carryBadge(days: preview.carryOverDays)
    }
}

// MARK: - 타임라인 계획

/// 15분 타임라인(SPEC-ios §4). 칸은 1분 간격 16개 — "N분 전"과 세는 시간·링이 분마다 맞는다.
/// 위젯 새로고침 예산은 **타임라인 요청 수**에 걸리지 칸 수에 걸리지 않는다.
package enum AingWidgetTimelinePlan {
    package static let refreshInterval: TimeInterval = 15 * 60
    package static let entryStep: TimeInterval = 60

    package static func entryDates(now: Date) -> [Date] {
        stride(from: 0, through: refreshInterval, by: entryStep).map { now.addingTimeInterval($0) }
    }

    package static func nextReload(now: Date) -> Date {
        now.addingTimeInterval(refreshInterval)
    }
}

// MARK: - 설정

package enum AingWidgetConfig {
    /// anon 키 — 위젯 확장 **자기 번들**의 `CheckConfig.plist`(ios/project.yml 의 위젯 타깃 생성 단계가 앱과 같은 키로 만든다).
    /// 예전에는 확장 번들에 파일이 없어 앱 번들(PlugIns 두 단계 위)을 거슬러 읽었다 — 통합(w4/int)에서 확장도 파일을 싣게 하고 우회를 걷어냈다.
    /// 없으면 nil(키 없는 빌드 — 인텐트는 파일에만 남기고 앱이 active 때 올린다).
    package static func anonKey(bundle: Bundle = .main) -> String? {
        SupabaseConfig.anonKey(environment: [:], bundle: bundle)
    }
}
