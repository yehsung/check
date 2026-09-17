import CheckCore
import Foundation

/// 나 탭 문구와 순수 규칙(플랫폼 무관 — macOS `swift test` 가 값으로 검증한다).
///
/// 맥과 뜻이 같은 문장·규칙은 **맥 것을 그대로** 옮겼고 출처를 적었다. 맥 쪽은 맥 앱 타깃(`Sources/check`)에 있어 폰이 import 할 수
/// 없다 — 코어로 옮기려면 맥 파일을 고쳐야 해서 이 탭 범위를 넘는다. `MeTextParityTests` 가 맥 소스에 같은 문장이 남아 있는지 되묻는다.
package enum MeText {
    // MARK: 공통

    package static let loading = "불러오는 중…"
    /// 머리 카드 제목: 별명·이메일을 아직 모른다(맥 `GomokuPlayerFace.fallback` 과 같은 "나").
    package static let meFallbackName = "나"
    package static let retry = MobileLoadText.retry
    package static let noTeam = "팀 없음"

    // MARK: 기록 (맥 InsightsPanel · InsightsEmptyMessage · GoalPercentFormatter)

    package static let recordsTitle = "기록"
    package static let retroTitle = "지난주 회고"
    package static let metGoalChip = "목표 달성"
    /// 맥 `InsightsEmptyMessage.noRetro`.
    package static let noRetro = "지난주 근무 기록이 없어요"
    package static let recordsFailed = "기록을 불러오지 못했어요"
    package static let heatmapTitle = "지난주 근무 리듬"
    package static let workGrassTitle = "최근 12주 근무"
    package static let tokenGrassTitle = "최근 12주 AI 토큰"
    package static let dayNames = ["월", "화", "수", "목", "금", "토", "일"]

    /// 맥 `InsightsEmptyMessage.text` 와 같은 갈림. nil 이면 본문(회고·잔디·히트맵)을 그린다.
    package static func recordsPlaceholder(hasLoaded: Bool, hasFailed: Bool, totalSeconds: Int, hasTokenGrass: Bool) -> String? {
        if !hasLoaded { return hasFailed ? recordsFailed : loading }
        if totalSeconds == 0, !hasTokenGrass { return hasFailed ? recordsFailed : noRetro }
        return nil
    }

    /// "지난주 32시간 10분".
    package static func retroTotal(_ retro: WeeklyRetro) -> String {
        "지난주 \(MenuBarStatusFormatter.hoursMinutes(retro.totalSeconds))"
    }

    /// 맥 `InsightsPanel.goalLine`.
    package static func retroGoalLine(_ retro: WeeklyRetro) -> String {
        let goalText = MenuBarStatusFormatter.hoursMinutes(retro.goalSeconds)
        if retro.metGoal {
            return "목표 \(goalText) 달성 — 잘하셨어요"
        }
        let percent = shortfallPercent(workedSeconds: retro.totalSeconds, goalSeconds: retro.goalSeconds)
        let remain = max(0, retro.goalSeconds - retro.totalSeconds)
        return "목표 \(goalText) 중 \(percent)% · \(MenuBarStatusFormatter.hoursMinutes(remain)) 부족"
    }

    /// 맥 `InsightsPanel.deltaLine`.
    package static func retroDeltaLine(_ retro: WeeklyRetro) -> String? {
        guard retro.previousWeekSeconds > 0 else { return nil }
        let delta = retro.deltaSeconds
        if delta == 0 { return "전주와 같아요" }
        let sign = delta > 0 ? "+" : "-"
        return "전주 대비 \(sign)\(MenuBarStatusFormatter.hoursMinutes(abs(delta)))"
    }

    /// 맥 `InsightsPanel.detailLine`.
    package static func retroDetailLine(_ retro: WeeklyRetro) -> String {
        var parts = ["세션 \(retro.sessionCount)회"]
        if let day = retro.busiestDayIndex, day >= 0, day < dayNames.count, retro.busiestDaySeconds > 0 {
            parts.append("가장 많이 일한 날 \(dayNames[day])요일 \(MenuBarStatusFormatter.hoursMinutes(retro.busiestDaySeconds))")
        }
        return parts.joined(separator: " · ")
    }

    package static func retroProgress(_ retro: WeeklyRetro) -> Double {
        let goal = max(1, retro.goalSeconds)
        return min(1, max(0, Double(retro.totalSeconds) / Double(goal)))
    }

    /// "가장 활발한 시간: 화요일 14시"(맥 `peakText`).
    package static func peakLine(_ heatmap: WorkRhythmHeatmap) -> String? {
        guard let peak = heatmap.peakSlot, peak.day >= 0, peak.day < dayNames.count else { return nil }
        return "가장 활발한 시간: \(dayNames[peak.day])요일 \(peak.hour)시"
    }

    /// 맥 `GoalPercentFormatter.percent`.
    package static func percent(workedSeconds: Int, goalSeconds: Int) -> Int {
        let worked = max(0, workedSeconds)
        let goal = max(1, goalSeconds)
        let raw = Int((Double(worked) / Double(goal) * 100).rounded())
        return min(999, max(0, raw))
    }

    /// 맥 `GoalPercentFormatter.shortfallPercent` — 미달 문맥에서 100 으로 반올림돼 "100% · 18분 부족"이 되지 않게 99 로 묶는다.
    package static func shortfallPercent(workedSeconds: Int, goalSeconds: Int) -> Int {
        min(99, percent(workedSeconds: workedSeconds, goalSeconds: goalSeconds))
    }

    /// 개인 기록 조회 창의 시작(맥 `WorkTimerStore.insightsWindowStart`): min(회고 비교선 = 그 전주 월요일, 잔디 = 12주 전 월요일).
    package static func insightsWindowStart(now: Date) -> Date {
        let fallback = TeamWeeklyGoal.koreanWeekStart(for: now)
        let retroStart = WorkInsightsWeekWindow.lastWeek(now: now)?.previousStart ?? fallback
        let gridStart = WorkDailyGrid.windowStart(now: now, weeks: WorkDailyGrid.defaultWeeks) ?? fallback
        return min(retroStart, gridStart)
    }

    // MARK: 잔디 · 히트맵 격자 (맥 ContributionGridView · WorkRhythmHeatmapGrid 의 순수 함수)

    /// 잔디 단계 수(맥 `dailyGridLevels`).
    package static let gridLevels = 4

    /// 맥 `ContributionGridView.level`: 0 이면 0단계, 분모의 1/levels 마다 한 단계 올림(올림 나눗셈), 상한 levels.
    package static func gridLevel(value: Int, denominator: Int, levels: Int = gridLevels) -> Int {
        guard value > 0, levels > 0 else { return 0 }
        guard denominator > 0 else { return levels }
        return min(levels, (value * levels + denominator - 1) / denominator)
    }

    /// 맥 `ContributionGridView.opacity` — 히트맵(0.20 + 0.80 × 농도)과 같은 사다리.
    package static func gridOpacity(level: Int, levels: Int = gridLevels) -> Double {
        guard level > 0, levels > 0 else { return 0 }
        return 0.20 + 0.80 * Double(min(level, levels)) / Double(levels)
    }

    /// 맥 `WorkRhythmHeatmapGrid.intensity` — 한 칸 3600초가 가장 진하다.
    package static func heatmapIntensity(seconds: Int) -> Double {
        guard seconds > 0 else { return 0 }
        return min(1, max(0, Double(seconds) / 3_600))
    }

    /// 맥 `ContributionGridView.monthLabels`: 주 열마다 그 주 일요일의 달이 앞 열과 다르면 그 달, 같으면 nil.
    package static func monthLabels(weekStart: Date, weeks: Int) -> [Int?] {
        let calendar = TeamWeeklyGoal.kstCalendar
        guard weeks > 0 else { return [] }
        func monthOfSunday(week: Int) -> Int? {
            calendar.date(byAdding: .day, value: week * WorkRhythmHeatmap.dayCount + WorkRhythmHeatmap.dayCount - 1, to: weekStart)
                .map { calendar.component(.month, from: $0) }
        }
        var previous = monthOfSunday(week: -1)
        return (0..<weeks).map { week in
            let current = monthOfSunday(week: week)
            defer { previous = current }
            return current != previous ? current : nil
        }
    }

    /// 잔디 보이스오버 요약: "최근 12주 근무, 기록한 날 34일, 합계 210시간 05분".
    package static func workGrassAccessibility(_ grid: WorkDailyGrid) -> String {
        let days = grid.seconds.flatMap { $0 }.filter { $0 > 0 }.count
        return "\(workGrassTitle), 근무한 날 \(days)일, 합계 \(MenuBarStatusFormatter.hoursMinutes(grid.totalSeconds))"
    }

    package static func tokenGrassAccessibility(_ grid: TokenDailyGrid) -> String {
        let days = grid.tokens.flatMap { $0 }.filter { $0 > 0 }.count
        return "\(tokenGrassTitle), 쓴 날 \(days)일, 합계 \(TokenNumberFormatter.compactKorean(grid.totalTokens)) 토큰"
    }

    // MARK: 캐릭터 · 상점 (맥 ShopText · WorkTimerStore 상점 문구)

    package static let charactersTitle = "캐릭터"
    package static let shopTitle = "상점"
    package static let pickerTitle = "캐릭터 고르기"
    package static let pickerCaption = "맥의 오버레이·메뉴바와 울트라 찌르기에 나오는 내 캐릭터예요."
    /// 맥 `WorkTimerStore.alreadyOwnedNotice`.
    package static let alreadyOwned = "이미 갖고 있어요"
    /// 맥 `WorkTimerStore.pickSomethingNotice`.
    package static let pickSomething = "살 것을 골라 주세요"
    package static let bought = "샀어요!"
    package static let buyFailed = "구매 실패"
    package static let buyAction = "구매하기"
    package static let owned = "보유"
    package static let equipped = "착용 중"
    /// 착용값 조회 실패(요약 줄 — 루트는 당겨서 새로고침이 다시 묻는다).
    package static let equippedLoadFailed = "착용 정보를 불러오지 못했어요"
    /// 머리 카드: 프로필 조회가 한 번도 성공하지 못했다(곁에 [다시 시도]).
    package static let headerLoadFailed = "프로필을 불러오지 못했어요"
    package static let characterSaved = "캐릭터를 바꿨어요"
    package static let characterSaveFailed = "캐릭터 저장 실패"
    package static let characterNotOwned = "안 산 캐릭터예요 — 상점에서 살 수 있어요"
    package static let goToShop = "상점 가기"
    package static let shopFailed = "상점을 불러오지 못했어요"

    /// 맥 `ShopText.cardPrice`.
    package static func cardPrice(owned: Bool, price: Int?) -> String {
        if owned { return MeText.owned }
        guard let price else { return "—" }
        return "\(max(0, price))"
    }

    package static func lockedCharacter(_ name: String) -> String {
        "\(name)\(particle(name, withFinal: "은", withoutFinal: "는")) 아직 없어요 — 상점에서 살 수 있어요"
    }

    package static func purchaseConfirmTitle(name: String) -> String {
        "\(name)\(particle(name, withFinal: "을", withoutFinal: "를")) 살까요?"
    }

    /// 받침에 따라 조사를 고른다("유령을" · "여우를"). 한글 음절이 아니면(영문 id 등) 받침 없는 쪽.
    package static func particle(_ word: String, withFinal: String, withoutFinal: String) -> String {
        guard let last = word.unicodeScalars.last, (0xAC00...0xD7A3).contains(last.value) else { return withoutFinal }
        return (last.value - 0xAC00) % 28 == 0 ? withoutFinal : withFinal
    }

    package static func purchaseConfirmMessage(price: Int, balance: Int) -> String {
        "루비 \(price)개를 써요 · 남는 루비 \(max(0, balance - price))개"
    }

    // MARK: 프로필 (맥 WorkTimerStore.updateDisplayName · CheckSettingsView 별명)

    package static let profileTitle = "프로필"
    package static let displayNameLabel = "별명"
    /// 맥 설정 창 별명 설명과 같은 문장.
    package static let displayNameHelp = "팀 목록과 순위판에 보이는 이름이에요. 한 번 바꾸면 일주일 동안 다시 못 바꿔요."
    package static let displayNameSave = "저장"
    package static let displayNameEmpty = "별명을 입력해 주세요"
    package static let displayNameTaken = "이미 쓰고 있는 별명이에요"
    package static let displayNameInvalid = "지금은 별명을 바꿀 수 없어요"
    package static let displayNameNetwork = "연결이 불안정해요. 잠시 후 다시 시도해 주세요"
    package static let displayNameSaved = "별명을 바꿨어요"
    package static let avatarChange = "사진 바꾸기"
    /// 맥 `performAvatarUpdate` 의 문장.
    package static let avatarSaved = "프로필 사진 변경됨"
    package static let avatarFailed = "사진 업로드 실패"
    package static let avatarUnreadable = "사진을 읽지 못했어요 — 다른 사진을 골라 주세요"
    package static let avatarUploading = "올리는 중…"
    /// 서버 쿨타임(7일). 맥 `WorkTimerStore.displayNameCooldownSeconds`.
    package static let displayNameCooldownSeconds: TimeInterval = 7 * 24 * 3600

    package static func displayNameTooLong(_ maxLength: Int) -> String {
        "별명은 \(maxLength)자까지 쓸 수 있어요"
    }

    /// 맥 `WorkTimerStore.normalizedDisplayName` — 서버 normalize_display_name() 의 거울(NFC · 제어/서식 문자 제거(ZWJ 유지) · 연속 공백 1칸 · 앞뒤 공백 제거).
    package static func normalizedDisplayName(_ raw: String) -> String {
        let composed = raw.precomposedStringWithCanonicalMapping
        let kept = composed.unicodeScalars.filter { scalar in
            if scalar == "\u{200D}" { return true }
            let category = scalar.properties.generalCategory
            return category != .control && category != .format
        }
        return String(String.UnicodeScalarView(kept))
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    /// 서버가 세는 길이(코드포인트).
    package static func displayNameLength(_ raw: String) -> Int {
        normalizedDisplayName(raw).unicodeScalars.count
    }

    /// 맥 `displayNameUnlockDate` — '마지막 변경 + 7일'이 속한 KST 날짜의 00:00.
    package static func displayNameUnlockDate(changedAt: Date) -> Date {
        TeamWeeklyGoal.koreanDayStart(for: changedAt.addingTimeInterval(displayNameCooldownSeconds))
    }

    /// 맥 `displayNameCooldownMessage` 와 같은 문장.
    package static func displayNameCooldownMessage(availableAt: Date) -> String {
        let c = TeamWeeklyGoal.kstCalendar.dateComponents([.month, .day], from: availableAt)
        return "일주일에 한 번만 바꿀 수 있어요 · \(c.month ?? 1)월 \(c.day ?? 1)일부터"
    }

    // MARK: 제보 (코어 FeedbackText 를 그대로 쓰고, 폰만의 문장만 여기)

    package static let feedbackTitle = "제보"
    package static let feedbackReplyBadge = "새 답장"
    package static let feedbackKindLabel = "종류"

    /// "iOS 0.1.0 (1) · iOS 18.2 정보가 함께 전송돼요" — 자동으로 실리는 것을 밝히는 한 줄(맥 `FeedbackText.autoAttachNotice` 의 폰판).
    /// 진단 줄(실시간·work_tick)은 폰에서 싣지 않는다(SPEC-ios-build §2 D5+D7).
    package static func feedbackAutoAttach(appVersion: String, osVersion: String) -> String {
        "\(appVersion) · \(osVersion) 정보가 함께 전송돼요"
    }

    /// 맥 `FeedbackFailure.notice` 와 같은 갈림(원문 서버 예외는 절대 보여 주지 않는다).
    package static func feedbackFailure(_ error: Error, fallback: String, schemaMissing: String? = nil) -> String {
        guard let serviceError = error as? SupabaseWorkServiceError else { return fallback }
        switch serviceError {
        case .authMessage(let message):
            let upper = message.uppercased()
            if upper.contains("FEEDBACK_RATE_LIMIT") { return FeedbackText.rateLimited }
            if upper.contains("FEEDBACK_FORBIDDEN") { return FeedbackText.forbidden }
            return fallback
        case .rateLimited:
            return FeedbackText.rateLimited
        case .databaseSchemaMissing:
            return schemaMissing ?? fallback
        default:
            return fallback
        }
    }

    /// 맥 `sortedForFeedbackList`: 미해결 먼저 → 최신순(모르면 뒤) → id.
    package static func sortedFeedback(_ reports: [FeedbackReport]) -> [FeedbackReport] {
        reports.sorted { lhs, rhs in
            if lhs.status.isOpen != rhs.status.isOpen { return lhs.status.isOpen }
            switch (lhs.createdAt, rhs.createdAt) {
            case let (l?, r?) where l != r: return l > r
            case (nil, .some): return false
            case (.some, nil): return true
            default: break
            }
            return lhs.id < rhs.id
        }
    }

    // MARK: 설정 (맥 CheckSettingsView "내 정보")

    package static let settingsTitle = "설정"
    package static let privacySection = "공개 설정"
    package static let tokenPublicTitle = "AI 토큰 사용량 공개"
    package static let tokenPublicDetail = "끄면 AI 토큰 순위판에서 내 사용량이 다른 사람에게 보이지 않아요."
    package static let miniGamePublicTitle = "미니게임 순위 공개"
    package static let miniGamePublicDetail = "끄면 내 최고기록이 순위표에 안 보이고 올라가지도 않아요."
    package static let privacySaveFailed = "공개 설정을 저장하지 못했어요 — 잠시 뒤 다시 시도해 주세요"
    /// 공개 설정을 한 번도 못 읽었다(스위치가 꺼져 있는 이유 · 폰만의 문장).
    /// 공용 `LoadFailureRow` 가 [다시 시도]를 곁에 둔다 — 문장에 할 일을 또 적지 않는다(탭 사이 실패 문구 맞춤).
    package static let privacyLoadFailed = "공개 설정을 불러오지 못했어요"

    package static let pushSection = "알림"
    /// 종류별 토글 아래 한 줄(제목은 `PushKind.settingTitle` — 설명 시트와 같은 이름).
    package static func pushDetail(_ kind: PushKind) -> String {
        switch kind {
        case .message: return "누가 메시지를 보내면 알려 줘요."
        case .gomokuInvite: return "1:1 오목 대결 신청이 오면 알려 줘요."
        case .feedbackReply: return "보낸 제보에 답장이 오면 알려 줘요."
        }
    }
    package static let pushPrefsUnknown = "알림 종류 설정을 아직 못 읽었어요 — 잠시 뒤 다시 열어 주세요"
    package static let openSystemSettings = "설정 앱에서 켜기"

    // MARK: 화면 모드 (폰만의 문장 — 기기 설정, 서버에 올리지 않는다)

    package static let appearanceSection = "화면 모드"
    /// 위젯은 iOS 가 홈 화면 모드로 그린다 — 앱 설정을 따르지 않는다는 것을 칸 아래 한 줄로 밝힌다.
    package static let appearanceWidgetNote = "위젯은 이 설정과 상관없이 아이폰 설정을 따라요."

    package static func appearanceTitle(_ mode: MobileAppearanceMode) -> String {
        switch mode {
        case .system: return "시스템 설정 따르기"
        case .light: return "라이트"
        case .dark: return "다크"
        }
    }

    package static func appearanceSymbol(_ mode: MobileAppearanceMode) -> String {
        switch mode {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }

    package static let teamSection = "팀"
    package static let inviteCodeTitle = "팀 코드"
    package static let inviteCodeShare = "팀 코드 공유"
    package static let inviteCodeMissing = "팀 코드를 아직 못 읽었어요"

    package static func inviteShareMessage(teamName: String?, code: String) -> String {
        let team = teamName.map { "「\($0)」 " } ?? ""
        return "aing-check \(team)팀 코드: \(code)\n맥 앱에서 가입할 때 이 코드를 입력하면 같은 팀이 돼요."
    }

    package static let accountSection = "계정"
    package static let signOut = "로그아웃"
    package static let signOutConfirmTitle = "로그아웃할까요?"
    package static let signOutConfirmMessage = "이 폰에서만 로그아웃돼요. 맥은 그대로예요."
    package static let signingOut = "로그아웃하는 중…"

    package static func versionLine(version: String, build: Int) -> String {
        "aing-check iOS \(version) (\(build))"
    }
}

/// 설정 화면의 알림 권한 머리 줄(권한 값은 푸시 코디네이터 `authorization` — 나 탭이 따로 읽지 않는다).
extension PushAuthorizationStatus {
    package var meTitle: String {
        switch self {
        case .unknown: return "알림 권한 확인 중…"
        case .notDetermined: return "알림 허용을 아직 정하지 않았어요"
        case .denied: return "알림이 꺼져 있어요"
        case .authorized: return "알림이 켜져 있어요"
        case .provisional: return "알림이 조용히 와요"
        case .ephemeral: return "알림이 켜져 있어요"
        }
    }

    package var meDetail: String? {
        switch self {
        case .denied: return "설정 앱 › aing-check › 알림에서 켤 수 있어요."
        case .notDetermined: return "허용하면 아래 종류별로 고를 수 있어요."
        case .provisional: return "알림 센터에만 조용히 쌓여요. 설정 앱에서 배너로 바꿀 수 있어요."
        case .unknown, .authorized, .ephemeral: return nil
        }
    }
}
