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

    // w15 재디자인(시안 B 위젯 보드)
    /// 내 오늘 상태 줄(초상 옆 굵은 글자 — 색이 상태를 말한다).
    package static let stateWorking = "근무 중"
    package static let stateDisconnected = "연결 끊김"
    package static let todayAccumulated = "오늘 누적"
    /// 세지 않는 값이 한 시간 넘게 낡았을 때 "오늘 누적" 자리에 — 어느 값이 언제 것인지(비평: '2분 전'이 어느 값의 것인지 모호).
    package static func asOf(_ ago: String) -> String { "\(ago) 기준" }
    /// "이번 주 24.8/40시간"
    package static func weekLine(_ caption: String) -> String { "\(thisWeek) \(caption)" }
    /// 지금 근무 중 M 왼쪽 기둥 머리(좁은 칸 — "지금"을 뺀다).
    package static let workingShortTitle = "근무 중"
    package static func teammates(_ count: Int) -> String { "우리 팀 \(count)" }
    package static func otherTeams(_ count: Int) -> String { "다른 팀 \(count)" }
    package static let workingEmptyTitle = "아직 아무도 없어요"
    package static let workingEmptyHint = "맥에서 근무를 시작하면 여기에 떠요"
    /// 로그아웃 칸의 둘째 줄 — 어떤 위젯인지 말한다(비평: 5종이 같은 경고 아이콘 한 줄이라 종류를 알 수 없었다).
    package static let signedOutWorkingHint = "로그인하면 지금 근무 중인 사람이 떠요"
    package static let signedOutTodoHint = "로그인하면 여기서 바로 체크해요"
    /// 할 일 L 빈 상태 본문(머리 "오늘 할 일"과 같은 말을 되풀이하지 않는다 — 비평).
    package static let todoEmptyLarge = "적어 둔 일이 없어요"

    package static let todoTitle = "오늘 할 일"
    package static let todoEmpty = "오늘 할 일이 비어 있어요"
    package static let todoEmptyHint = "앱에서 추가해 보세요"
    package static let todoMarkDone = "완료로 표시"
    package static let todoMarkUndone = "완료 취소"
    package static let todoAddInApp = "앱에서 추가"
    package static func todoRemaining(_ count: Int) -> String { "남은 \(count)개" }
    package static func more(_ count: Int) -> String { "외 \(count)개" }
    /// "5개 중 1개 완료"
    package static func todoProgress(total: Int, done: Int) -> String { "\(total)개 중 \(done)개 완료" }
    /// 여러 조각을 " · " 로 잇는다(빈 조각은 뺀다).
    package static func joined(_ parts: [String?]) -> String {
        parts.compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    // 위젯 갤러리
    package static let workingGalleryName = "지금 근무 중"
    package static let workingGalleryDescription = "지금 근무 중인 사람을 우리 팀부터 보여 줘요."
    package static let myTodayGalleryName = "내 오늘"
    package static let myTodayGalleryDescription = "내 캐릭터와 오늘 누적, 이번 주 목표를 보여 줘요."
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

    /// 경과 시간 "4:10"(시:분, 내림 — 지금 근무 중 M 의 우리 팀 칸). 미래 시작(시계 차)은 "0:00".
    package static func elapsedClock(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return "\(seconds / 3600):" + String(format: "%02d", (seconds % 3600) / 60)
    }

    /// "9월 17일 목"(KST — 할 일 L 머리).
    package static func dayLabel(_ date: Date) -> String {
        let calendar = TeamWeeklyGoal.kstCalendar
        let parts = calendar.dateComponents([.month, .day, .weekday], from: date)
        let weekdays = ["일", "월", "화", "수", "목", "금", "토"]
        let weekday = weekdays[((parts.weekday ?? 1) - 1 + 7) % 7]
        return "\(parts.month ?? 1)월 \(parts.day ?? 1)일 \(weekday)"
    }
}

// MARK: - 칸 배치 수(시안 B 위젯 보드)

package enum AingWidgetLayout {
    /// 지금 근무 중 S 얼굴 더미 · 이름 줄.
    package static let workingSmallFaces = 3
    /// 지금 근무 중 M 사람 칸(2열 × 3행, 열 먼저).
    package static let workingMediumRows = 3
    package static let workingMediumColumns = 2
    package static var workingMediumCells: Int { workingMediumRows * workingMediumColumns }
    /// M 왼쪽 숫자 기둥 폭. 시안 96 에서 84 로 줄였다 — 402pt 기기 중형(349.7pt) 사람 칸이 90pt 라 "민트 4:10" 이 "… 4:10" 으로 접혔다(실측).
    package static let workingMediumColumnWidth: Double = 84
    /// 오늘 할 일 M 3줄(줄 34pt) · L 5줄(줄 46pt — 위젯에서도 손가락 크기 44pt 를 지킨다).
    package static let todoRowsMedium = 3
    package static let todoRowsLarge = 5
    package static let todoRowHeightMedium: Double = 34
    package static let todoRowHeightLarge: Double = 46
    /// 줄 사이 구분선이 시작하는 곳(체크 원 22 + 틈 10 — 글자 시작점).
    package static let todoSeparatorInset: Double = 32
}

// MARK: - 캐릭터 기분 · 이니셜 원(위젯은 앱 부품을 링크하지 않는다 — 같은 규칙을 여기 둔다)

/// 초상 표정·링의 뜻(앱 `CharacterMood` 와 같은 표 — `WidgetDesignTests` 가 대조).
package enum AingWidgetMood: String, CaseIterable, Sendable {
    /// 근무 중 — 웃음 + 초록 링·발광.
    case working
    /// 연결 끊김 — 웃음 + 앰버 링.
    case lost
    /// 근무 안 함 — 시무룩 + 청회색 링.
    case off
    /// 빈 상태·로그아웃의 아잉 — 링 없이 받침만.
    case plain

    package init(_ state: WidgetSnapshot.WorkState) {
        switch state {
        case .working: self = .working
        case .disconnected: self = .lost
        case .off: self = .off
        }
    }

    package var expression: AingCharacterArt.Expression {
        self == .off ? .negative : .neutral
    }

    /// 링 두께(pt) — 시안 `max(2, 지름 × 0.04)`(앱과 같은 식).
    package static func ringWidth(diameter: Double) -> Double {
        max(2, (diameter * 0.04).rounded(.toNearestOrEven))
    }

    package static let ringGap: Double = 2
}

package enum AingWidgetInitial {
    /// 첫 글자(공백뿐이면 "?") — 앱 `InitialAvatar.initial(of:)` 와 같다.
    package static func letter(of name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "?" : String(trimmed.prefix(1))
    }

    /// 이름 → 색 칸(맥 `CheckTheme.avatarColor(for:)` 해시: 유니코드 스칼라 합 mod 6).
    package static func paletteIndex(for seed: String) -> Int {
        let sum = seed.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return abs(sum) % AingWidgetPalette.avatarInks.count
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
    /// 근무 상태 3갈래(옛 스냅샷은 working 깃발로 — `WidgetSnapshot.Me.resolvedStatus`).
    package let status: WidgetSnapshot.WorkState
    package let isTicking: Bool
    package let todaySeconds: Int
    package let weekSeconds: Int
    package let goalHours: Int
    /// 스냅샷이 칸 시각보다 몇 초 낡았나(0 이상).
    package let ageSeconds: TimeInterval

    package init(me: WidgetSnapshot.Me, generatedAt: Date, at date: Date) {
        let age = max(0, date.timeIntervalSince(generatedAt))
        ageSeconds = age
        status = me.resolvedStatus
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

    package var mood: AingWidgetMood { AingWidgetMood(status) }

    /// 상태 줄 글자(색은 화면이 상태로 고른다).
    package var stateTitle: String {
        switch status {
        case .working: return AingWidgetText.stateWorking
        case .disconnected: return AingWidgetText.stateDisconnected
        case .off: return AingWidgetText.notWorking
        }
    }

    /// 초상 옆 둘째 줄. 세는 값은 늘 지금 값이라 "오늘 누적", 멈춘 값이 한 시간 넘게 낡았으면 "3시간 전 기준" —
    /// 시안은 신선도 표기를 뺐다(비평: 칸 안에 '2분 전'이 어느 값의 것인지 모호). 낡은 멈춘 값만 말한다.
    package func stateSubtitle(generatedAt: Date, now: Date) -> String {
        guard !isTicking, ageSeconds >= 3600 else { return AingWidgetText.todayAccumulated }
        return AingWidgetText.asOf(AingWidgetFormat.ago(from: generatedAt, now: now))
    }
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

    package let teammateCount: Int

    package init(_ working: [WidgetSnapshot.WorkingPerson], limit: Int) {
        let ordered = working.filter(\.teammate) + working.filter { !$0.teammate }
        total = ordered.count
        shown = Array(ordered.prefix(max(0, limit)))
        hiddenCount = max(0, total - shown.count)
        teammateCount = working.filter(\.teammate).count
    }

    package var otherCount: Int { total - teammateCount }

    /// 얼굴 더미 아래 이름 줄 "민트 · 보리 · 라임".
    package var namesLine: String {
        shown.map(\.name).joined(separator: " · ")
    }

    /// 지금 근무 중 S 아래 줄 왼쪽 "우리 팀 3 · 외 3명"(우리 팀 0명이면 "외 N명"만, 둘 다 없으면 nil).
    package var smallFooter: String? {
        let text = AingWidgetText.joined([
            teammateCount > 0 ? AingWidgetText.teammates(teammateCount) : nil,
            hiddenCount > 0 ? AingWidgetText.morePeople(hiddenCount) : nil,
        ])
        return text.isEmpty ? nil : text
    }

    /// M 사람 칸 오른쪽 작은 글자: 우리 팀은 경과 시간 "4:10", 다른 팀은 센터("서울"), 모르면 nil.
    package static func detail(_ person: WidgetSnapshot.WorkingPerson, now: Date) -> String? {
        if person.teammate, let started = person.startedAt {
            return AingWidgetFormat.elapsedClock(from: started, to: now)
        }
        return CenterLabel.display(person.center)
    }

    /// M 은 **열 먼저** 채운다(시안: 왼쪽 열 우리 팀 · 오른쪽 열 다른 팀). 한 열 `rows` 칸.
    package func columns(rows: Int) -> [[WidgetSnapshot.WorkingPerson]] {
        let size = max(1, rows)
        return stride(from: 0, to: shown.count, by: size).map { Array(shown[$0..<min(shown.count, $0 + size)]) }
    }
}

// MARK: - 오늘 할 일(고르기)

package struct AingWidgetTodos: Equatable, Sendable {
    package let rows: [WidgetSnapshot.TodoPreview]
    /// 스냅샷 안의 미완료 수(위젯이 체크한 줄도 반영된다).
    package let remaining: Int
    package let hiddenCount: Int

    package let total: Int
    package let doneCount: Int

    package init(_ previews: [WidgetSnapshot.TodoPreview], limit: Int) {
        rows = Array(previews.prefix(max(0, limit)))
        remaining = previews.filter { !$0.isCompleted }.count
        hiddenCount = max(0, previews.count - rows.count)
        total = previews.count
        doneCount = total - remaining
    }

    /// M 머리 오른쪽 "남은 4개 · 외 2개"(아래 줄에 따로 두지 않는다 — 줄 세 개가 칸을 채운다).
    package var mediumTrailing: String {
        AingWidgetText.joined([AingWidgetText.todoRemaining(remaining), hiddenCount > 0 ? AingWidgetText.more(hiddenCount) : nil])
    }

    /// L 머리 둘째 줄 "9월 17일 목 · 5개 중 1개 완료".
    package func largeSubtitle(at date: Date) -> String {
        AingWidgetText.joined([AingWidgetFormat.dayLabel(date), AingWidgetText.todoProgress(total: total, done: doneCount)])
    }

    /// L 아래 줄 왼쪽 "2분 전" 또는 "외 1개 · 2분 전".
    package func largeFooter(ago: String) -> String {
        AingWidgetText.joined([hiddenCount > 0 ? AingWidgetText.more(hiddenCount) : nil, ago])
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

// MARK: - 예시 데이터(갤러리 미리보기 · 자리 표시)

/// 지어낸 예시(실사용자 이름 아님) — 시안 B 위젯 보드와 같은 장면.
package enum AingWidgetSamples {
    package static func snapshot(now: Date) -> WidgetSnapshot {
        WidgetSnapshot(
            generatedAt: now.addingTimeInterval(-120),
            me: .init(working: true, sessionStartedAt: now.addingTimeInterval(-13_620), todaySeconds: 18_480, weekSeconds: 89_280, goalHours: 40, status: .working),
            working: [
                // 얼굴 = 착용 캐릭터(하늘은 캐릭터를 모르는 사람 — 이니셜로 선다).
                .init(name: "민트", center: "seoul", teammate: true, startedAt: now.addingTimeInterval(-15_000), characterID: "shiba"),
                .init(name: "보리", center: "busan", teammate: true, startedAt: now.addingTimeInterval(-10_320), characterID: "aing"),
                .init(name: "라임", center: "seoul", teammate: true, startedAt: now.addingTimeInterval(-5_700), characterID: "jellyfish"),
                .init(name: "모래", center: "seoul", teammate: false, startedAt: nil, characterID: "ghost"),
                .init(name: "코랄", center: "busan", teammate: false, startedAt: nil, characterID: "squirrel"),
                .init(name: "하늘", center: nil, teammate: false, startedAt: nil),
            ],
            todosPreview: [
                .init(id: "5A0F2D8E-1B4E-4B7A-9E0B-3E8E2A6D2C11", title: "디자인 리뷰 피드백 반영하기", isCompleted: false, carryOverDays: 0),
                .init(id: "6B1F2D8E-1B4E-4B7A-9E0B-3E8E2A6D2C12", title: "주간 회고 초안 쓰기", isCompleted: false, carryOverDays: 1),
                .init(id: "7C2F2D8E-1B4E-4B7A-9E0B-3E8E2A6D2C13", title: "팀 회의 안건 정리", isCompleted: false, carryOverDays: 3),
                .init(id: "8D3F2D8E-1B4E-4B7A-9E0B-3E8E2A6D2C14", title: "점심 전에 PR 올리기", isCompleted: true, carryOverDays: 0),
                .init(id: "9E4F2D8E-1B4E-4B7A-9E0B-3E8E2A6D2C15", title: "온보딩 문서 링크 모으기", isCompleted: false, carryOverDays: 9),
            ],
            characterID: "fox"
        )
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
