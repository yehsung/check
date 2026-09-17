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

    // MARK: 공통

    /// 맥 `TokenBoardEmptyMessage.loading` · `InsightsEmptyMessage.loading` 과 같은 문장.
    package static let loading = "불러오는 중…"
    /// 맥 `PanelRetryButton` 의 글자.
    package static let retry = MobileLoadText.retry

    // MARK: 팀 리그 (맥 LeaderboardPanel · LeaderboardRow)

    package static let leagueTitle = "팀별 이번 주"
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
    package static func leagueCaption(_ entry: TeamLeaderboardEntry) -> String {
        "각자 목표 \(entry.weeklyGoalHours)시간 · 총 \(MenuBarStatusFormatter.hoursMinutes(entry.totalSeconds)) · \(entry.memberCount)명 · \(entry.workingCount)명 근무중"
    }

    /// 게이지 퍼센트(맥 `LeaderboardRow.percent` — 0~100 클램프된 진행률을 반올림).
    package static func leaguePercent(_ entry: TeamLeaderboardEntry) -> Int {
        Int((entry.goal.progress * 100).rounded())
    }

    /// 빈 목록 문구(맥 `LeaderboardEmptyMessage.text` 와 같은 갈림 + 폰의 진행중·실패 구분).
    package static func leagueEmpty(hasLoaded: Bool, isLoading: Bool, hasFailed: Bool, unfilteredCount: Int) -> String {
        if unfilteredCount > 0 { return leagueFilteredOut }
        if hasFailed { return leagueFailed }
        if !hasLoaded || isLoading { return loading }
        return leagueFilteredOut
    }

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

    package static func leagueRowAccessibility(rank: Int, entry: TeamLeaderboardEntry, isMyTeam: Bool) -> String {
        var parts = ["\(rank)위", entry.name]
        if isMyTeam { parts.append(myTeamChip) }
        parts.append(leagueAverage(entry))
        parts.append("목표 대비 \(leaguePercent(entry))%")
        parts.append(leagueCaption(entry))
        return parts.joined(separator: ", ")
    }
}
