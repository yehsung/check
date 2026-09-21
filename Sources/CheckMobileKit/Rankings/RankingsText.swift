import CheckCore
import CheckMobileShared
import Foundation

/// 순위 탭 문구와 순수 서식(플랫폼 무관 — macOS `swift test` 가 값으로 검증한다).
///
/// 맥과 뜻이 같은 문장은 **맥 문장 그대로** 옮겼다(출처를 줄마다 적는다). 맥 문구는 맥 앱 타깃(`Sources/check`)에 있어
/// 폰이 import 할 수 없다 — 코어로 옮기면 맥 파일을 고쳐야 해서 이 탭 범위를 넘는다(보고의 "기반 수정 요청" 후보).
package enum RankingsText {
    // MARK: 세그먼트

    package static func segmentTitle(_ board: AingRoute.RankingsBoard) -> String {
        switch board {
        case .league: return "팀 리그"
        case .tokens: return "AI 토큰"
        case .minigame: return "미니게임"
        }
    }

    /// 큰 제목 아래 한 줄(시안 B 05·06): 판마다 기간과 마감을 말한다.
    package static func boardSubtitle(_ board: AingRoute.RankingsBoard) -> String {
        switch board {
        case .league: return "이번 주 · 월요일 0시에 새로 시작해요"
        case .tokens: return "이번 달 · 1일에 새로 시작해요"
        case .minigame: return "오늘 · 자정에 마감해요"
        }
    }

    // MARK: 공통

    /// 맥 `TokenBoardEmptyMessage.loading` · `InsightsEmptyMessage.loading` 과 같은 문장.
    package static let loading = "불러오는 중…"
    /// 맥 `PanelRetryButton` 의 글자.
    package static let retry = MobileLoadText.retry

    // MARK: 팀 리그 (맥 LeaderboardPanel · LeaderboardRow)

    /// 섹션 머리 제목. 이번 주는 **"팀별 이번 주"** 로 예전과 한 글자도 다르지 않다(`displayTitle` 이 "이번 주"를 낸다).
    /// 과거 주는 "팀별 9월 14일 주", 해가 다르면 "팀별 2025년 12월 29일 주" — 맥 `LeaderboardPanel` 과 같은 조립이다.
    package static func leagueTitle(week weekKey: String, now: Date) -> String {
        "팀별 \(TeamLeagueWeekNavigator.displayTitle(weekKey, now: now))"
    }

    /// 주 이동 알약이 보이스오버에 읽어 주는 칸 이름("이번 주" · "9월 14일 주").
    package static func leagueWeekName(week weekKey: String, now: Date) -> String {
        TeamLeagueWeekNavigator.displayTitle(weekKey, now: now)
    }
    package static let leagueCaption = "1인당 평균 근무시간 순이에요"
    /// 맥 `LeaderboardEmptyMessage.filteredOut`.
    package static let leagueFilteredOut = "아직 이번 주 근무한 팀이 없어요"
    package static let leagueFailed = "리그를 불러오지 못했어요"
    /// 맥 `LeaderboardRow` 의 칩.
    package static let myTeamChip = "우리 팀"

    /// "평균 12시간 30분" — 맥 `LeaderboardRow` 의 메인 숫자.
    package static func leagueAverage(_ entry: TeamLeaderboardEntry) -> String {
        "평균 \(MenuBarStatusFormatter.hoursMinutes(entry.averageSeconds))"
    }

    /// "각자 목표 40시간 · 총 51시간 12분 · 4명 · 2명 근무중" — 맥 `LeaderboardRow.caption` 과 같은 문장.
    /// 과거 주는 마지막 조각만 참여 인원으로 갈린다("… · 5명 중 4명 참여") — **'근무중' 조각이 사라진다**.
    /// workingCount 는 '지금 근무 중'이라 과거 주엔 언제나 0 이고, 값이 0 인지 따지지 않고 **주 판정으로** 끊는다.
    package static func leagueCaption(_ entry: TeamLeaderboardEntry, now: Date = Date()) -> String {
        let total = MenuBarStatusFormatter.hoursMinutes(entry.totalSeconds)
        // 과거 판정은 **행이 스스로** 한다(맥 LeaderboardRow.caption 과 같은 자리·같은 규약).
        guard entry.isPastWeek(now: now) else {
            return "각자 목표 \(entry.weeklyGoalHours)시간 · 총 \(total) · \(entry.memberCount)명 · \(entry.workingCount)명 근무중"
        }
        return "각자 목표 \(entry.weeklyGoalHours)시간 · 총 \(total) · \(leagueParticipation(entry))"
    }

    /// 과거 주 조각: "5명 중 4명 참여" · participantCount 가 없으면 "5명 중 참여 인원 모름"(맥 CheckComponents.swift:404-405 와 글자 동일).
    /// 옛 서버에서 workingCount 로 대신하지 않는다 — 0 을 적느니 모른다고 적는다.
    package static func leagueParticipation(_ entry: TeamLeaderboardEntry) -> String {
        entry.participantCount.map { "\(entry.memberCount)명 중 \($0)명 참여" }
            ?? "\(entry.memberCount)명 중 참여 인원 모름"
    }

    /// 목록 위 메타 줄 오른쪽 보조 글자(시안 B 05 — 행의 큰 숫자가 무엇의 평균인지). **머리 오른쪽은 주 이동 알약이 쓴다** —
    /// 제목 + 이 힌트 + 알약을 한 줄에 두면 SE(가용 335pt)에서 연도형 제목·큰 글자가 제목을 두 줄로 꺾는다.
    package static let leagueAverageHint = "1인당 평균"

    /// 행 오른쪽 끝 큰 숫자 "25시간 07분"(머리가 '1인당 평균'이라 "평균" 을 떼었다). 이번 주 기록이 없는 팀(내 팀만 남는다)은 "—".
    package static func leagueValue(_ entry: TeamLeaderboardEntry) -> String {
        entry.averageSeconds > 0 ? MenuBarStatusFormatter.hoursMinutes(entry.averageSeconds) : noValue
    }

    /// 막대 끝 퍼센트 "63%" — 기록 없는 팀은 "—"(0% 로 지어내지 않는다).
    package static func leaguePercentText(_ entry: TeamLeaderboardEntry) -> String {
        entry.averageSeconds > 0 ? "\(leaguePercent(entry))%" : noValue
    }

    /// 부제 조각: 인원 "5명".
    package static func leagueMembers(_ entry: TeamLeaderboardEntry) -> String {
        "\(entry.memberCount)명"
    }

    /// 부제 조각: 근무 상태 "3명 근무 중"(앞에 초록 점) · "근무 중 없음" · 이번 주 기록이 없으면 "이번 주 기록 없음".
    package static func leagueWorking(_ entry: TeamLeaderboardEntry) -> String {
        if entry.workingCount > 0 { return "\(entry.workingCount)명 근무 중" }
        return entry.totalSeconds > 0 ? "근무 중 없음" : "이번 주 기록 없음"
    }

    /// 부제 조각: 1인 목표 "목표 40시간".
    package static func leagueGoal(_ entry: TeamLeaderboardEntry) -> String {
        "목표 \(entry.weeklyGoalHours)시간"
    }

    /// 부제 한 줄 "5명 · 3명 근무 중 · 목표 40시간"(화면은 근무 중 앞에 초록 점을 끼운다). 구분점은 늘 두 조각 **사이**에만.
    ///
    /// 과거 주는 '근무 중' 조각을 **아예 뺀다**("5명 중 4명 참여 · 목표 40시간") — working_count 는 '지금 근무 중'이라
    /// 과거 주엔 늘 0 이고, 두면 기록이 멀쩡한 팀에도 "근무 중 없음"이 붙는다. 값이 0 인지 따지지 않고 **주 판정으로** 끊는다.
    package static func leagueSubtitle(_ entry: TeamLeaderboardEntry, now: Date = Date()) -> String {
        guard entry.isPastWeek(now: now) else {
            return [leagueMembers(entry), leagueWorking(entry), leagueGoal(entry)].joined(separator: " · ")
        }
        return [leagueParticipation(entry), leagueGoal(entry)].joined(separator: " · ")
    }

    /// 막대 색 뜻: 달성 = 초록 · '우리 팀' = 게이지 그라디언트(이 판에서 그라디언트는 우리 팀만) · 나머지 = 진행 파랑.
    package enum LeagueBarKind: Equatable, Sendable { case done, gauge, accent }

    package static func leagueBarKind(_ entry: TeamLeaderboardEntry, isMyTeam: Bool) -> LeagueBarKind {
        if entry.goal.isComplete { return .done }
        return isMyTeam ? .gauge : .accent
    }

    /// 숫자가 없는 칸.
    package static let noValue = "—"

    /// 게이지 퍼센트(맥 `LeaderboardRow.percent` — 0~100 클램프된 진행률을 반올림).
    package static func leaguePercent(_ entry: TeamLeaderboardEntry) -> Int {
        Int((entry.goal.progress * 100).rounded())
    }

    /// 빈 목록 문구(맥 `LeaderboardEmptyMessage.text` 와 같은 갈림 + 폰의 진행중·실패 구분).
    ///
    /// 과거 주 갈림은 맥 `LeaderboardEmptyMessage.text(isPastWeek:…)` 와 같은 순서다. **과거 주 빈 문장은 그 주 키로
    /// `hasLoaded == true` 일 때만** 나온다 — 취소·로드 전은 "불러오는 중…"이다(그 문장은 사실 주장이라 통신 실패가
    /// 과거 사실로 둔갑하면 안 된다). 이번 주 갈림은 한 글자도 안 바뀐다.
    package static func leagueEmpty(hasLoaded: Bool, isLoading: Bool, hasFailed: Bool, unfilteredCount: Int, isPastWeek: Bool = false) -> String {
        guard isPastWeek else {
            if unfilteredCount > 0 { return leagueFilteredOut }
            if hasFailed { return leagueFailed }
            if !hasLoaded || isLoading { return loading }
            return leagueFilteredOut
        }
        if isLoading { return loading }
        if hasFailed { return leaguePastFailed }
        if !hasLoaded { return loading }
        return leaguePastFilteredOut
    }

    // MARK: 팀 리그 — 지난 6주 보기 (v0.3.37 · 맥 LeaderboardEmptyMessage · LeagueWeekNote 와 글자 동일)

    /// 과거 주 빈 목록(맥 `LeaderboardEmptyMessage.pastFilteredOut`). "아직"도 "이번 주"도 과거 주엔 틀린 말이다.
    package static let leaguePastFilteredOut = "그 주엔 근무한 팀이 없었어요"
    /// 과거 주 실패(맥 `LeaderboardEmptyMessage.loadFailed`). **이번 주 문구(`leagueFailed`)는 건드리지 않는다.**
    /// 폰의 `tokenFailed`·`miniGameFailed` 와도 같은 글자라, 이 화면에서 '리그를…' 쪽이 오히려 예외다(후속 통일 후보).
    package static let leaguePastFailed = "순위를 불러오지 못했어요"

    package static func leagueFailedText(isPastWeek: Bool) -> String { isPastWeek ? leaguePastFailed : leagueFailed }

    /// 과거 주 보조 줄(맥 `LeagueWeekNote.pastWeek`). 인원은 1인당 평균의 **분모**라 뜻이 바뀌는 유일한 칸이다.
    package static let leagueWeekBasis = "인원은 그 주 기준이에요"
    /// 내 팀이 그 주 표에 아예 없을 때(맥 `LeagueWeekNote.myTeamMissing`).
    package static let leagueMyTeamMissing = "그 주엔 아직 우리 팀이 없었어요"

    /// 과거 주 보조 줄. **한 줄만 그린다**(맥 `LeagueWeekNote.text` 와 같은 배타 선택) — 내 팀이 그 주 표에 아예 없으면
    /// 그 답이 **먼저**다("왜 우리 팀이 안 보이지?"). 이번 주는 nil(줄 내용이 비고 자리만 남는다).
    ///
    /// **목표·팀 이름·센터가 현재값이라는 사실은 화면에 한 글자도 쓰지 않는다** — 사용자가 감지할 수 없는 차이고,
    /// 셋 중 하나만 고백하면 나머지 둘이 과거값인 척하게 되어 오히려 덜 정확하다(맥과 같은 결정).
    package static func leagueWeekNote(isPastWeek: Bool, myTeamMissing: Bool) -> String? {
        guard isPastWeek else { return nil }
        return myTeamMissing ? leagueMyTeamMissing : leagueWeekBasis
    }

    /// 주 이동 알약 라벨(맥 `IconButton` help 와 같은 글자).
    package static let previousWeek = "이전 주"
    package static let nextWeek = "다음 주"
    /// 비활성 화살표가 보이스오버에 읽어 주는 **막힌 사유**. 6주 상한은 눈으로 추론할 수 없는 제품 규칙이라 말로 해야 한다.
    package static let noEarlierWeek = "6주 전까지만 볼 수 있어요"
    package static let noLaterWeek = "이번 주가 가장 최근이에요"
    /// 토큰 판 비활성 ▸ 의 사유(공용 부품이라 같이 붙는다 — 달은 과거 하한이 없어 ◂ 쪽 사유가 없다).
    package static let noLaterMonth = "이번 달이 가장 최근이에요"

    // MARK: AI 토큰 (맥 TokenBoardPanel · TokenBoardRowView · TokenBoardEmptyMessage)

    /// "9월 AI 토큰 소모량" — 맥 머리글과 같은 문장(연도가 다르면 "2025년 12월").
    package static func tokenTitle(month: String, now: Date) -> String {
        "\(TokenBoardMonthNavigator.displayTitle(month, now: now)) AI 토큰 소모량"
    }

    package static let tokenNoUploads = "아직 이번 달 소모량을 올린 사용자가 없어요"
    package static let tokenNoPastRecords = "이 달에는 기록이 없어요"
    package static let tokenFailed = "순위를 불러오지 못했어요"
    package static let meChip = "나"
    package static let privateChip = "비공개"
    package static let previousMonth = "이전 달"
    package static let nextMonth = "다음 달"

    /// 맥 `TokenBoardEmptyMessage.text` 와 같은 갈림(로그인 전 fallback 은 폰에 없다 — 로드 전은 "불러오는 중…").
    package static func tokenEmpty(hasLoaded: Bool, isLoading: Bool, hasFailed: Bool, isCurrentMonth: Bool) -> String {
        guard hasLoaded else {
            return hasFailed && !isLoading ? tokenFailed : loading
        }
        return isCurrentMonth ? tokenNoUploads : tokenNoPastRecords
    }

    /// "1,234,567 토큰"(축약 없이 전체 숫자).
    package static func tokenTotal(_ entry: TokenBoardEntry) -> String {
        "\(TokenNumberFormatter.grouped(entry.total)) 토큰"
    }

    /// 행 오른쪽 끝 큰 숫자 — **억/만 한 단위 체계**(비평 "한 행에 단위 체계가 둘"): "50.1억" · "638만" · "8,432".
    /// 이름 밑 도구 줄(`toolUsageLabel`)과 같은 축약(`TokenNumberFormatter.compactKorean`)이라 한 행 안의 숫자가 같은 말로 읽힌다.
    /// 1의 자리까지의 정확한 값은 보이스오버(`tokenRowAccessibility` — `tokenTotal`)가 읽는다. 말줄임이 아니라 단위 축약이다.
    package static func tokenTotalCompact(_ entry: TokenBoardEntry) -> String {
        TokenNumberFormatter.compactKorean(entry.total)
    }

    /// "오늘 +1.8억" — 이번 달 보드에서만(같은 억/만 체계).
    package static func tokenTodayCompact(_ entry: TokenBoardEntry, todayKey: String) -> String {
        "오늘 +\(TokenNumberFormatter.compactKorean(entry.todayDelta(currentDate: todayKey)))"
    }

    /// 비교 막대 길이(1등 = 1). 1등이 0 이면 전부 0. 막대가 없던 행에서 1위와 5위의 785배 차이가 숫자 길이로만 보였다.
    package static func tokenBarFraction(total: Int, top: Int) -> Double {
        guard top > 0 else { return 0 }
        return min(1, max(0, Double(total) / Double(top)))
    }

    /// "오늘 +12,345 토큰" — 이번 달 보드에서만(과거 달에는 '오늘'이 없다).
    package static func tokenToday(_ entry: TokenBoardEntry, todayKey: String) -> String {
        "오늘 +\(TokenNumberFormatter.grouped(entry.todayDelta(currentDate: todayKey))) 토큰"
    }

    // MARK: 미니게임 (맥 CheckMiniGameWindowView · MiniGameChampionCard · MiniGameRankRow)

    package static let miniGameRankTitle = "오늘 순위"
    package static let miniGameEmpty = "아직 기록이 없어요 — 첫 기록의 주인공이 되세요"
    package static let miniGameFailed = "순위를 불러오지 못했어요"
    package static let yesterdayChampion = "어제 1등"
    /// 자정 상품(루비). 맥 `CheckMiniGameWindowView.rubyPrizes` · 서버 `ruby_prize_amounts()` 와 **짝인 상수**.
    package static let rubyPrizes = [20, 10, 5]
    /// 자정 상품 정족수. 맥 `prizeQuorum` · 서버 `minigame_prize_quorum()` 과 짝.
    package static let prizeQuorum = 5
    package static var prizeCaption: String {
        "자정에 1·2·3등에게 루비 \(rubyPrizes[0])·\(rubyPrizes[1])·\(rubyPrizes[2])"
    }
    package static var awardedChip: String { "루비 +\(rubyPrizes[0]) 받음" }

    /// 맥 `quorumCaption` 과 같은 문장.
    package static func quorumCaption(players: Int) -> String {
        if players >= prizeQuorum { return "오늘 \(players)명 참여 · 지급 조건 충족" }
        if players == 0 { return "오늘은 아직 아무도 안 했어요 · \(prizeQuorum)명부터 지급" }
        return "오늘 \(players)명 참여 · \(prizeQuorum)명부터 지급"
    }

    /// "953점" — 자리수 구분 없이(맥 주석: 만점 "1,000점" 방지).
    package static func score(_ value: Int) -> String {
        String(value) + "점"
    }

    package static func miniGameEmptyText(hasLoaded: Bool, hasFailed: Bool) -> String {
        if hasFailed, !hasLoaded { return miniGameFailed }
        if !hasLoaded { return loading }
        return miniGameEmpty
    }

    /// 순위 행 보이스오버 한 줄: "3위, 민트, 서울센터, 953점, 나".
    package static func miniGameRowAccessibility(rank: Int, entry: MiniGameBoardEntry, isMe: Bool) -> String {
        var parts = ["\(rank)위", entry.name]
        if let center = entry.center { parts.append("\(center)센터") }
        parts.append(score(entry.bestScore))
        if isMe { parts.append(meChip) }
        return parts.joined(separator: ", ")
    }

    package static func tokenRowAccessibility(rank: Int, entry: TokenBoardEntry, isMe: Bool, isPrivate: Bool, todayKey: String?) -> String {
        var parts = ["\(rank)위", entry.name]
        if isMe { parts.append(meChip) }
        if isPrivate { parts.append(privateChip) }
        parts.append(tokenTotal(entry))
        if let label = entry.toolUsageLabel { parts.append(label) }
        if let todayKey { parts.append(tokenToday(entry, todayKey: todayKey)) }
        return parts.joined(separator: ", ")
    }

    /// 행 보이스오버 한 줄. **주 이름은 넣지 않는다** — 6행이 같은 말을 여섯 번 한다(그 말은 보조 줄이 한 번만 한다).
    package static func leagueRowAccessibility(rank: Int, entry: TeamLeaderboardEntry, isMyTeam: Bool, now: Date = Date()) -> String {
        var parts = ["\(rank)위", entry.name]
        if isMyTeam { parts.append(myTeamChip) }
        parts.append(leagueAverage(entry))
        parts.append("목표 대비 \(leaguePercent(entry))%")
        parts.append(leagueCaption(entry, now: now))
        return parts.joined(separator: ", ")
    }
}
