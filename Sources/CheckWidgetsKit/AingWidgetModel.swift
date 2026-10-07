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
    /// v0.3.45 — AI 구독 리밋(전용 위젯 1종). v0.3.46 부터 **미디움 한 칸만** 지원한다.
    package static let aiLimits = "AingAILimits"
    package static let all = [workingNow, myToday, todos, aiLimits]
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
    package static let limitsGalleryName = "AI 리밋"
    package static let limitsGalleryDescription = "클로드·코덱스·안티그래비티의 5시간·주간 사용률을 보여 줘요."

    // MARK: AI 리밋(v0.3.45 — 토큰 축과 다른 새 축)

    package static let limitsTitle = "AI 리밋"
    /// 아직 한 번도 못 받았다 — 앱을 열면 폰이 서버에서 받아 싣는다.
    package static let limitsNoData = noData
    /// 받았는데 연동한 도구가 없다. **"앱을 열면"이 아니다** — 앱을 열어도 채워지지 않는다(맥이 자격증명을 읽는다).
    package static let limitsNoProviders = "맥 앱에서 AI 도구에 로그인하면 보여요"
    package static let limitsSignedOutHint = "로그인하면 AI 사용률이 떠요"
    /// 5시간 창 라벨(좁은 칸).
    package static let limitsFiveHour = "5시간"
    package static let limitsWeekly = "주간"
    package static let limitsTokenTitle = "AI 토큰"
    package static let limitsTokenToday = "오늘"
    package static let limitsTokenRecent = "12주"

    /// "3시간 뒤 초기화" — 절대 시각을 칸 시각으로 **투영한** 글자(남은 초를 스냅샷에 싣지 않는 까닭).
    package static func limitsResetIn(_ remaining: String) -> String { "\(remaining) 뒤 초기화" }
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

    /// AI 리밋 칸 수. **미디움 한 종류뿐이다**(v0.3.46 사용자 지시: "스몰과 라지 버전 다 없애고. 미디움 버전만
    /// 똑바로 만들어."). 제공자가 셋뿐이라 상한이 곧 전부다 — 넷째 제공자가 생기면 이 수가 먼저 늘어야 한다.
    package static let limitRowsMedium = 3
    /// 로고 마크 크기(줄 머리 · 승인된 값 20pt — 왼쪽 92pt 칸에 [마크 20][이름]이 들어간다).
    package static let limitTileSize: Double = 20
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

// MARK: - AI 리밋(시각 투영)

/// 리밋 줄 하나(제공자 하나). 값·캡션·표시여부는 **전부 코어 규칙**(`AILimitFreshnessRule`)이 만든다 —
/// 위젯이 퍼센트를 다시 반올림하거나 나이를 다시 세면 맥·폰·위젯이 같은 숫자를 다르게 말한다.
package struct AingWidgetLimitRow: Equatable, Sendable, Identifiable {
    package let provider: AILimitProvider
    package var id: String { provider.rawValue }
    /// 5시간 창(크게). 그 창이 없으면 nil — 지어내 0% 로 그리지 않는다.
    package let fiveHour: AILimitDisplay?
    package let weekly: AILimitDisplay?
    /// 맥이 이 제공자에게서 값을 받은 시각. **머리의 나이 글자가 이 값으로 선다**(v0.3.45 P2).
    ///
    /// 왜 들고 다니는가: 머리는 예전에 `snapshot.generatedAt`(= 폰이 파일을 쓴 시각)으로 나이를 적었다.
    /// 그 값은 리밋이 안 바뀌어도 `NowStore.touchWidgetSnapshot` 이 60초마다 '지금'으로 옮기므로,
    /// 맥이 몇 시간 자고 있어도 머리는 **'방금'**이라고 적었다 — 낡음을 알릴 수단이 리밋의 나이를 말한 적이
    /// 없었던 것이다. `AILimitDisplay` 에는 관측 시각이 없고(나이는 리셋 축과 섞인 `claimAge` 뿐이다)
    /// 그 축을 머리 글자로 쓰면 "리셋 경계가 오래전"이 "관측이 오래됨"으로 읽힌다. 그래서 원본 시각을 싣는다.
    package let observedAt: Date?

    package init(provider: AILimitProvider, fiveHour: AILimitDisplay?, weekly: AILimitDisplay?, observedAt: Date? = nil) {
        self.provider = provider
        self.fiveHour = fiveHour
        self.weekly = weekly
        self.observedAt = observedAt
    }

    /// 그 열이 그릴 값. **nil = 그 창이 이 계정에 아예 없다** → 칸을 `없음` 으로 비운다
    /// (`AILimitColumnText.absentValueText`). 판정 불가(기기 시계 어긋남)는 값이 있는 쪽이고 글자가 `—` 다 —
    /// **두 사실을 같은 글자로 말하지 않는다**(승인된 문법 ⑤).
    ///
    /// ## 왜 '대표 창 고르기'가 사라졌나 (v0.3.46)
    /// v0.3.45 는 줄마다 대표 창 하나를 크게 세웠고, 그래서 "어느 창을 머리로 세우나"라는 선택이 필요했다.
    /// 그 선택이 틀리면 5시간 창이 **없는** 계정(안티그래비티 실측)에서 숫자가 사라지거나 주간 8% 가 옆 줄의
    /// 5시간 27% 와 같은 창으로 읽혔다. 승인된 새 문법(한 줄 안에 두 열이 **나란히**)에는 그 선택이 **아예
    /// 없다** — 창마다 자기 칸이 있고, 열 머리가 카드 맨 위에서 어느 칸이 어느 창인지 한 번 말한다.
    /// 고를 것이 없으면 틀릴 수도 없다. 폰 `AILimitDisplayRow.display(_:)` 와 **같은 규칙**이다.
    package func display(_ window: AILimitWindow) -> AILimitDisplay? {
        let value = window == .fiveHour ? fiveHour : weekly
        guard let value, value.isVisible else { return nil }
        return value
    }

    /// 그릴 숫자가 하나도 없는 줄(두 창이 다 없다). 만드는 쪽이 이미 걸러 내지만, 걸러짐이 느슨해지는 날
    /// 두 칸이 `없음 · 없음` 인 빈 줄이 서지 않게 뷰도 이 깃발을 본다.
    package var hasAnyWindow: Bool { fiveHour != nil || weekly != nil }

    /// 색 대신 쓰는 식별자(틴트 모드는 색을 버린다).
    package var name: String { provider.displayName }
    package var compactName: String { provider.compactName }
}

/// 리밋 위젯이 그릴 것.
package enum AingWidgetLimitsState: Equatable, Sendable {
    /// 스냅샷에 리밋 칸이 아직 없다(옛 스냅샷 · 앱을 한 번도 안 열었다) → "앱을 열면 채워져요".
    case noData
    /// 받았는데 연동한 도구가 하나도 없다 → "맥 앱에서 AI 도구에 로그인하면 보여요".
    /// **noData 와 뜻이 다르다** — 앱을 열어도 채워지지 않는다. 두 안내를 섞으면 맥을 쓰지 않는 사용자가
    /// 앱을 몇 번이고 열게 된다.
    case noProviders
    case limits(AingWidgetLimits)

    package init(snapshot: WidgetSnapshot, at date: Date) {
        guard let panel = snapshot.aiLimits else {
            self = .noData
            return
        }
        let limits = AingWidgetLimits(panel: panel, at: date)
        self = limits.rows.isEmpty ? .noProviders : .limits(limits)
    }
}

/// 제공자 줄들 + 기존 토큰 사용량(다른 축 — 한 바에 섞지 않는다).
package struct AingWidgetLimits: Equatable, Sendable {
    /// 제공자 **고정 순서**(Claude → Codex → 안티그래비티). 연동 유무로 재배열하면 "어제는 Codex 가 위였는데"가 된다.
    package let rows: [AingWidgetLimitRow]
    /// 오늘 쓴 AI 토큰. nil = 모른다 → L 의 토큰 줄을 **그리지 않는다**(0 은 "안 썼다"는 거짓이다).
    package let todayTokens: Int?
    package let recentTokens: Int?

    package init(panel: WidgetSnapshot.AILimitPanel, at date: Date) {
        rows = panel.providers
            // ★ 모르는 제공자는 **버린다**. 서버가 네 번째를 더하는 날 구버전 위젯이 조용히 'claude' 로 접으면
            //   남의 사용률이 내 Claude 줄에 그려진다(열거값 확장 함정).
            .compactMap { row -> AingWidgetLimitRow? in
                guard let provider = AILimitProvider(rawValue: row.provider) else { return nil }
                // ★ 유령 행 게이트를 **칸 시각으로 다시** 지난다(v0.3.45 P2). 폰은 서버 응답을 받는 순간
                //   이 문턱을 적용하지만, 패널은 **앱이 열릴 때만** 다시 써지고 위젯은 그 파일을 몇 시간·며칠
                //   뒤의 칸에서 그린다(리밋 위젯은 지평 밖 칸까지 깐다). 그래서 "쓸 때는 안 유령이었지만
                //   그릴 때는 유령"인 창이 열렸고, 그 창에서 위젯은 로그아웃한 제공자를 `0% · 초기화됨` 으로
                //   그렸다. 문턱은 폰과 **같은 상수 하나**다(`AILimitGhostRow` — 모듈이 달라 두 벌로 적으면 갈린다).
                guard !AILimitGhostRow.isGhost(observedAt: row.observedAt, now: date) else { return nil }
                var windows: [AILimitWindowSnapshot] = []
                if let percent = row.fiveHourPercent {
                    windows.append(AILimitWindowSnapshot(
                        window: .fiveHour, usedPercent: percent, resetsAt: row.fiveHourResetsAt,
                        observedAt: row.observedAt, source: .server
                    ))
                }
                if let percent = row.weeklyPercent {
                    windows.append(AILimitWindowSnapshot(
                        window: .weekly, usedPercent: percent, resetsAt: row.weeklyResetsAt,
                        observedAt: row.observedAt, source: .server
                    ))
                }
                guard !windows.isEmpty else { return nil }
                let snapshot = AILimitProviderSnapshot(provider: provider, windows: windows)
                func display(_ window: AILimitWindow) -> AILimitDisplay? {
                    guard snapshot.window(window) != nil else { return nil }
                    let value = AILimitFreshnessRule.display(provider: snapshot, window: window, now: date)
                    return value.isVisible ? value : nil
                }
                return AingWidgetLimitRow(
                    provider: provider, fiveHour: display(.fiveHour), weekly: display(.weekly),
                    observedAt: row.observedAt
                )
            }
            .sorted { $0.provider.sortOrder < $1.provider.sortOrder }
        todayTokens = panel.todayTokens
        recentTokens = panel.recentTokens
    }

    /// 보이는 줄 중 **가장 낡은** 관측 시각. 머리의 나이 글자가 이 값으로 선다.
    ///
    /// 왜 가장 낡은 쪽인가: 머리는 "이 칸에 적힌 숫자들을 얼마나 믿을 수 있나" 하나를 말한다. 가장 최신을
    /// 고르면 켜져 있는 맥 하나가 3일 묵은 다른 줄의 낡음을 가린다 — 조합값의 신뢰도는 **가장 낡은 기여자**가
    /// 정한다는 코어 규칙(`AILimitFreshnessRule.combine`)과 같은 방향이다.
    package var oldestObservedAt: Date? {
        rows.compactMap(\.observedAt).min()
    }

    /// 머리에 적을 나이 글자("3시간 전"). 관측 시각을 모르면 nil(= 글자를 적지 않는다 — 폰이 파일을 쓴 시각을
    /// 리밋의 나이처럼 적지 않는다).
    package func observationAgeText(now: Date) -> String? {
        oldestObservedAt.map { AingWidgetFormat.ago(from: $0, now: now) }
    }

    /// 미디움이 그릴 줄들(상한까지).
    package func shown(limit: Int) -> [AingWidgetLimitRow] {
        Array(rows.prefix(max(0, limit)))
    }

    /// 토큰 줄을 그릴 수 있나(모르면 줄을 만들지 않는다).
    package var hasTokens: Bool { todayTokens != nil }
}

package enum AingWidgetLimitFormat {
    /// "3시간 뒤 초기화" — **절대 시각**을 칸 시각으로 투영한다. 이미 지났거나 모르면 nil
    /// (그때는 값 쪽 캡션이 "초기화됨"을 말한다 — 두 자리가 같은 말을 되풀이하지 않게).
    package static func resetIn(_ resetsAt: Date?, now: Date) -> String? {
        guard let resetsAt else { return nil }
        let remaining = resetsAt.timeIntervalSince(now)
        guard remaining > 0 else { return nil }
        return AingWidgetText.limitsResetIn(remainingText(remaining))
    }

    /// 남은 시간 글자: 60초 미만 "1분" · 1시간 미만 "N분" · 1일 미만 "N시간" · 그 위 "N일"(전부 내림, 0 은 없다).
    package static func remainingText(_ seconds: TimeInterval) -> String {
        if seconds < 3_600 { return "\(max(1, Int(seconds / 60)))분" }
        if seconds < 86_400 { return "\(Int(seconds / 3_600))시간" }
        return "\(Int(seconds / 86_400))일"
    }

    /// 토큰 수 축약("196.6억") — 좁은 위젯 칸 전용. 앱 카드와 **같은 함수**를 거친다.
    package static func tokens(_ value: Int) -> String {
        TokenNumberFormatter.compactKorean(value)
    }
}

// MARK: - 미디움 칸의 배치 예산 (순수 — 170pt 안에 들어가는지를 테스트가 값으로 잰다)

/// 「AI 리밋」 위젯 **미디움**(364×170pt)의 가로·세로 예산.
///
/// ## 왜 미디움 하나뿐인가 (2026-10-06 사용자 지시)
/// *"스몰과 라지 버전 다 없애고. 미디움 버전만 똑바로 만들어."* — 스몰은 한 제공자만 세워 "어느 제공자의 어느
/// 창인지"를 먼저 말해야 했고(두 열 문법과 어긋난다), 라지는 같은 세 줄을 띄워 놓아 아래가 비었다.
/// `.systemSmall`·`.systemLarge` 는 `supportedFamilies` 에서 **지웠다**(위젯은 아직 출시 전이라
/// 이미 추가한 사용자가 없다 — iOS 1.0.3/build 13 에 없다).
///
/// ## 가로 (왼쪽부터)
/// ```
///  [이름 칸 92] 8 [5시간 바(남는 폭) 5 숫자 62] 10 [주간 바(남는 폭) 5 숫자 62]
/// ```
/// 두 바는 `maxWidth: .infinity` 로 **같은 몫**을 받으므로 두 칸의 폭이 언제나 같고, 그래서 열 머리 글자의
/// 오른쪽 끝이 자기 열 숫자 칸의 오른쪽 끝과 **구조적으로** 맞는다(기기마다 칸 폭이 달라 — 402pt 기기는 364,
/// 375pt 기기는 329 — 간격을 상수로 적을 수 없다).
///
/// ## 세로 — ★ 제공자가 **1~2개뿐인 사람도 아래가 비지 않게**
/// 줄 높이를 상수로 두면 제공자 하나인 사람의 칸은 아래 60pt 가 통째로 빈다(라지가 그래서 못생겼다).
/// 그래서 **줄 높이가 남는 자리를 나눠 갖는다**: 줄 수가 적으면 줄이 높아지고 바도 같이 두꺼워진다
/// (내용이 칸 전체에 고르게 퍼진다 — 아래쪽만 비지 않는다).
package struct AingWidgetLimitsMediumBudget: Equatable, Sendable {
    /// WidgetKit 이 주는 기본 안쪽 여백(다른 세 위젯·미리보기 카탈로그와 같은 16pt).
    package static let contentMargin: Double = 16
    /// 402pt 기기의 미디움 칸(미리보기 카탈로그 `mediumSize`).
    package static let referenceSize = (width: 364.0, height: 170.0)
    /// 가장 좁은 기기(375pt)의 미디움 칸 — 가로 예산의 하한을 여기서 잰다.
    package static let narrowSize = (width: 329.0, height: 155.0)

    // 가로
    package static let nameColumnWidth: Double = 92
    /// 마크 한 변의 **상한**(승인된 값 20pt). 좁은 기기에서는 줄 높이가 이 값을 깎는다(`markSide`).
    package static let maxMarkSide = AingWidgetLayout.limitTileSize
    package static let markGap: Double = 6
    package static let nameGap: Double = 8
    package static let barValueGap: Double = 5
    package static let columnGap: Double = 10
    package static let valueWidth: Double = 62

    // 세로
    package static let headerHeight: Double = 18
    package static let headerGap: Double = 6
    /// 열 머리 줄(11pt 글자 한 줄).
    package static let columnHeaderHeight: Double = 13
    package static let separatorHeight: Double = 1
    /// 토큰 줄 묶음(위 간격 + 구분선 + 간격 + 글자 한 줄).
    package static let tokenBlockHeight: Double = 7 + 0.5 + 6 + 16
    /// 줄이 아무리 높아져도 바는 이보다 두꺼워지지 않는다(두꺼운 캡슐은 막대가 아니라 알약으로 보인다).
    package static let maxBarHeight: Double = 8
    package static let minBarHeight: Double = 5
    /// 바가 이보다 좁아지면 "조금 썼다"가 "안 썼다"로 보인다(= 이 설계의 하한).
    package static let minimumBarWidth: Double = 20
    /// 마크를 이보다 작게 줄이지 않는다(그 아래로 가면 세 제공자가 모양으로 안 갈린다).
    package static let minMarkSide: Double = 14

    package let innerWidth: Double
    package let innerHeight: Double
    package let providerCount: Int
    package let hasTokens: Bool

    /// 칸의 **안쪽**(WidgetKit 여백을 이미 뺀) 크기로 만든다 — 뷰는 `GeometryReader` 가 준 크기를 그대로 준다.
    /// 기기마다 칸이 다르다(402pt → 364×170 · 375pt → 329×155). 기준 칸 숫자만 믿으면 좁은 기기에서
    /// 세 줄 + 토큰 줄이 **칸을 넘긴다**(실측 계산: 375pt 기기의 안쪽 높이는 123pt 뿐이다).
    package init(innerWidth: Double, innerHeight: Double, providerCount: Int, hasTokens: Bool) {
        self.innerWidth = innerWidth
        self.innerHeight = innerHeight
        self.providerCount = max(0, providerCount)
        self.hasTokens = hasTokens
    }

    /// 칸 크기(여백 포함)로 만드는 편의 — 테스트가 `364×170` 처럼 **칸 숫자**로 재게 한다.
    package static func family(width: Double, height: Double, providerCount: Int, hasTokens: Bool) -> Self {
        Self(innerWidth: width - contentMargin * 2, innerHeight: height - contentMargin * 2,
             providerCount: providerCount, hasTokens: hasTokens)
    }

    /// 바를 뺀 가로 고정분.
    package static var fixedWidth: Double {
        nameColumnWidth + nameGap + barValueGap * 2 + valueWidth * 2 + columnGap
    }

    /// 바 하나의 폭 = 남는 것을 둘로 나눈다(**산식**이다 — 숫자 칸이나 간격을 고치면 바가 따라 줄어야 한다).
    package var barWidth: Double { (innerWidth - Self.fixedWidth) / 2 }

    /// 한 칸(바 + 간격 + 숫자)의 폭. 두 칸은 **언제나 같다**.
    package var cellWidth: Double { barWidth + Self.barValueGap + Self.valueWidth }

    /// 제공자 줄들이 쓸 수 있는 높이.
    package var rowsAreaHeight: Double {
        innerHeight - Self.headerHeight - Self.headerGap - Self.columnHeaderHeight
            - (hasTokens ? Self.tokenBlockHeight : 0)
    }

    /// 줄 하나의 높이 — 남는 자리를 **나눠 갖는다**(줄이 적으면 높아진다 = 아래가 비지 않는다).
    package var rowHeight: Double {
        guard providerCount > 0 else { return 0 }
        return (rowsAreaHeight - Double(providerCount - 1) * Self.separatorHeight) / Double(providerCount)
    }

    /// 마크 한 변 — 줄 높이에 **갇힌다**. 좁은 기기에서 세 줄이 각 18pt 로 줄어드는데 마크를 20pt 로 두면
    /// 줄이 칸을 밀어내 토큰 줄이 바깥으로 나간다(또는 SwiftUI 가 조용히 압축한다).
    package var markSide: Double {
        guard providerCount > 0 else { return Self.maxMarkSide }
        return min(Self.maxMarkSide, max(Self.minMarkSide, rowHeight - 3))
    }

    /// 이름 글자가 쓸 수 있는 폭.
    package var nameTextWidth: Double { Self.nameColumnWidth - markSide - Self.markGap }

    /// 바 두께 — 줄 높이에 비례하되 상·하한 안에서(줄이 높아지면 바도 조금 두꺼워져 빈 느낌이 줄어든다).
    package var barHeight: Double {
        min(Self.maxBarHeight, max(Self.minBarHeight, rowHeight * 0.18))
    }

    /// 쓰는 높이의 합 — 칸(innerHeight)을 넘지 않아야 한다. 테스트가 이 값을 잰다.
    package var usedHeight: Double {
        guard providerCount > 0 else { return Self.headerHeight }
        return Self.headerHeight + Self.headerGap + Self.columnHeaderHeight
            + Double(providerCount) * rowHeight + Double(providerCount - 1) * Self.separatorHeight
            + (hasTokens ? Self.tokenBlockHeight : 0)
    }

    /// 줄 하나가 **마크를 담을 수 있나**(줄 높이가 마크보다 커야 한다 — 아니면 SwiftUI 가 조용히 압축한다).
    package var rowFitsMark: Bool { providerCount == 0 || rowHeight >= markSide }
}

/// 틴트·투명 모드에서 **열 색이 사라진다**는 사실을 값으로 들고 있는 타입.
///
/// 시스템이 색을 통째로 버리는 모드(`widgetRenderingMode == .accented`)에서는 두 열의 바가 **같은 흰색**이
/// 된다 — 색은 세 단서(열 머리 글자 · 색 · 좌우 자리) 가운데 하나이고, 그 모드에서 남는 둘이 짝을 말한다.
/// ★ 그래서 열 머리 글자는 **어느 모드에서나 그려야 한다**(틴트에서 머리를 빼면 단서가 자리 하나로 줄어든다).
///
/// 왜 Bool 이 아니라 열거값인가: 뷰는 iOS 전용이라 맥 스위트가 색 분기를 한 줄도 재지 못한다. 분기의 **결과**를
/// 순수한 값으로 내놓으면 "틴트에서 두 열이 같은 잉크가 된다"를 테스트가 직접 되묻을 수 있다.
package enum AingWidgetLimitInk: Equatable, Sendable {
    /// 원색: 열마다 다른 색(5시간 파랑 · 주간 보라).
    case column(AILimitColumnWindow)
    /// 틴트·투명: 색이 없다 — 흰색 하나로 그린다.
    case accentedWhite

    package static func bar(window: AILimitWindow, accented: Bool) -> AingWidgetLimitInk {
        accented ? .accentedWhite : .column(AILimitColumnPalette.column(windowRawValue: window.rawValue))
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

/// 「AI 리밋」 위젯**만의** 타임라인. 다른 세 위젯의 계획(`AingWidgetTimelinePlan`)은 **건드리지 않는다.**
///
/// ## 왜 리밋만 다른가 (2026-10-07 실증한 P1)
/// 리밋의 열화(30분 넘으면 하한 + "이상", 리셋 뒤 0%)는 **엔트리 시각이 흘러야만** 일어난다 — 규칙은 순수
/// 함수고 `now` 는 칸이 준다. 그런데 지평이 15분이면 마지막 칸이 '스냅샷 나이 + 15분'에서 멈춘다. 위젯이
/// 새로고침 예산을 다 쓴 날(시스템이 재적재를 안 줄 때) 그 마지막 칸이 **그대로 남아** 2시간이 지나도
/// `.recent` 등급으로 `27%` 를 **등호로** 그린다. 헤더의 "N분 전"도 같이 얼어 낡음을 알릴 수단마저 멈춘다.
///
/// 다른 세 위젯은 이 함정을 안 밟는다: 그들이 그리는 것은 '우리 서버가 센 사실'(근무 중 인원 · 오늘 시간 ·
/// 할 일)이라 늦게 반영되어도 **그 시각의 참**이다. 리밋은 **원격 자원의 현재값**을 등호로 단정하는 자리라
/// 같은 지평을 물려받으면 안 된다.
///
/// 그래서 지평 **밖** 칸을 함께 깐다. 재적재가 한 번도 안 와도 규칙이 스스로 하한으로 떨어지고, 캡션이 늙고,
/// 리셋을 지난 창은 0% 로 간다. 칸은 공짜다 — 새로고침 예산은 **타임라인 요청 수**에 걸리지 칸 수에 걸리지 않는다.
package enum AingWidgetLimitsTimelinePlan {
    /// 지평 안쪽(분 단위)과 재적재 요청 주기는 다른 위젯과 **같다** — "N분 전"이 분마다 맞아야 한다.
    package static let refreshInterval = AingWidgetTimelinePlan.refreshInterval
    package static let entryStep = AingWidgetTimelinePlan.entryStep

    /// 지평 밖 칸(초). 고른 자리는 규칙의 **경계**들이다:
    ///  · 1800 = `recentWithin` — 여기서 숫자가 하한이 되고 "이상"이 붙는다(가장 중요한 한 칸).
    ///  · 3600 · 7200 · 14400 · 28800 — 캡션의 "N시간 전"이 계속 늙는다.
    ///  · 86460 = `staleWithin` + 1분 — `.ancient` 로 넘어가 캡션 단위가 '일'로 바뀐다.
    /// 더 멀리는 깔지 않는다: 하루를 넘겼으면 그 뒤로 더 늙어도 사용자가 읽는 뜻("아주 오래된 하한")이 같다.
    package static let farEntryOffsets: [TimeInterval] = [1_800, 3_600, 7_200, 14_400, 28_800, 86_460]

    /// 칸들: 지평 안쪽 1분 간격 + 지평 밖 꼬리.
    package static func entryDates(now: Date) -> [Date] {
        AingWidgetTimelinePlan.entryDates(now: now) + farEntryOffsets.map { now.addingTimeInterval($0) }
    }

    /// 재적재 요청 시각은 다른 위젯과 같다(지평 밖 칸은 **보험**이지 새 주기가 아니다 — 시스템이 예산을 주면
    /// 15분 뒤에 새 스냅샷으로 다시 깔린다).
    package static func nextReload(now: Date) -> Date {
        AingWidgetTimelinePlan.nextReload(now: now)
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
            characterID: "fox",
            // AI 리밋 예시: 세 제공자가 **서로 다른 모양**이다 — Claude 는 두 창 다, Codex 는 5시간이 0%(그 경우
            // 리셋 시각은 서버가 투영해 주는 가짜라 맥이 nil 로 접어 올린다 — 실측 §2), 안티그래비티는 주간만.
            // 한 모양만 넣으면 갤러리 미리보기가 '다 있는 사람'의 화면만 보여 준다.
            aiLimits: WidgetSnapshot.AILimitPanel(
                providers: [
                    .init(provider: "claude", fiveHourPercent: 27, fiveHourResetsAt: now.addingTimeInterval(9_300),
                          weeklyPercent: 60, weeklyResetsAt: now.addingTimeInterval(450_000), observedAt: now.addingTimeInterval(-120)),
                    .init(provider: "codex", fiveHourPercent: 0, fiveHourResetsAt: nil,
                          weeklyPercent: 56, weeklyResetsAt: now.addingTimeInterval(352_000), observedAt: now.addingTimeInterval(-300)),
                    .init(provider: "antigravity", weeklyPercent: 8, weeklyResetsAt: now.addingTimeInterval(540_000),
                          observedAt: now.addingTimeInterval(-600)),
                ],
                todayTokens: 12_345_678,
                recentTokens: 19_658_964_272
            )
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
