import CheckCore
import Foundation

// 오목 **순위표 절**(0.3.41 폰)의 문구. 공용 `GamesText.swift` 를 같이 고치면 네 갈래가 한 파일에서 부딪히므로
// `extension GomokuPhoneText` 로 여기에 더한다.
//
// **맥과 같은 뜻이면 같은 문장이다** — 출처는 맥 `GomokuText` 의 순위 절(`Sources/check/GomokuPanel.swift` "MARK: 순위표 (0.3.41)").
// 폰에서 처음 쓴 줄만 `// 폰` 으로 적는다.
//
// 이 파일은 `#if os(iOS)` 로 감싸지 않는다 — 뷰가 아니고 SwiftUI 를 쓰지 않는다. 그래서 **맥 스위트가 이 문구를 값으로 잴 수 있다**
// (`GamesText.swift` 와 같은 관례. 폰 뷰는 맥 스위트가 못 보니 문구만이라도 보이는 쪽에 둔다).
extension GomokuPhoneText {
    // MARK: 순위표 머리

    package static let rankTitle = "오목 순위"
    /// 절 **아래** 캡션 — 승점의 뜻. 같은 승점·승수면 더 많이 둔 쪽이 위(무승부 desc)라는 서열까지는 말하지 않는다(맥과 같다).
    package static let rankCaption = "승점 = 승 − 패"
    /// 전적 기준시각(컷)이 있으면 머리 오른쪽 캡션 — "10월 1일부터". 컷은 서버 순간 그대로의 **달력 값**이고 카운트다운이 아니다
    /// (코어 `GomokuStoreRanking.rankingBoard(from:)` — 기기 시계 보정 없음).
    package static func rankSince(_ date: Date) -> String {
        // ko_KR 의 FormatStyle 은 "10. 1." 을 낸다(맥 실측) — 달력 성분으로 직접 조립한다(그레고리력).
        //
        // 시간대는 **KST 로 못 박는다.** 전에는 `Calendar(identifier: .gregorian)` 을 그냥 써서 **기기 시간대**로 조립했는데,
        // 컷은 서버가 정한 KST 자정(전적 초기화 2026-10-01 00:00 KST)이라 비KST 기기에서는 하루 밀려 "9월 30일부터"가 됐다.
        // 전원 한국이라 눈에 안 띈 것일 뿐이고, 여행·기기 설정 하나로 틀린 달력 값을 보게 된다.
        // 공용 KST 달력을 쓴다(`TeamWeeklyGoal.kstCalendar` — 폰의 다른 절도 이걸 쓴다. `firstWeekday` 는 주 경계용이라
        // 달·일 성분에는 영향이 없다).
        let parts = TeamWeeklyGoal.kstCalendar.dateComponents([.month, .day], from: date)
        return "\(parts.month ?? 0)월 \(parts.day ?? 0)일부터"
    }
    /// 컷이 없다(응답 `record_since_ms` 가 null = `-infinity`) — 기간이 통째다. 폰
    package static let rankWholePeriod = "전체 기간"

    // MARK: 숫자

    /// 승점의 부호 있는 짧은 꼴("+9" · "−3" · "0"). 음수 기호는 루비 변화(`rubyDelta`)와 같은 '−'(U+2212) 다.
    package static func signedPoints(_ points: Int) -> String {
        if points > 0 { return "+\(points)" }
        if points < 0 { return "−\(-points)" }
        return "0"
    }

    /// "승점 +4".
    package static func points(_ points: Int) -> String { "승점 \(signedPoints(points))" }

    /// "6승 2패 1무" — ★ **승점만 띄우지 않는다**(사용자 지시). 순위 행과 내 순위 줄이 같은 이 표를 쓴다.
    /// `record(_ record: GomokuRecord?)` 와 뜻이 같은 문장이고(`GamesText.swift`), 순위 응답은 `GomokuRecord` 가 아니라 세 숫자로 온다.
    package static func record(wins: Int, losses: Int, draws: Int) -> String { "\(wins)승 \(losses)패 \(draws)무" }

    // MARK: 내 순위 줄

    package static let myRankTitle = "내 순위"
    /// 0판이면 순위가 없다(서버가 `me.rank` 를 null 로 준다 — 순위판에서 0판인 사람은 빠진다).
    package static let outOfRank = "순위 밖"

    /// 목록 밖 내 순위 한 줄 — "12위 · 승점 +4 · 6승 2패 1무"(0판이면 "순위 밖 · 0승 0패 0무"). 폰
    /// 맥은 머리글 캡슐 한 줄(`GomokuText.myRank`)이고 폰은 절 안의 제 칸이라 전적까지 이 줄이 들고 있다.
    package static func myRankLine(_ mine: GomokuMyRank) -> String {
        let record = record(wins: mine.wins, losses: mine.losses, draws: mine.draws)
        guard let rank = mine.rank else { return "\(outOfRank) · \(record)" }
        return "\(rank)위 · \(points(mine.points)) · \(record)"
    }

    // MARK: 상태 분기

    /// 판을 둔 사람이 아무도 없다. **전적 초기화(2026-10-01 00:00 KST) 직후에는 이 절 전체가 이 문장이다** — 의도된 신호다.
    package static let noRanking = "아직 전적이 없어요"
    /// 그 신호가 사고로 보이지 않게 덧붙이는 한 줄. 폰
    package static let noRankingHint = "첫 판이 끝나면 순위가 올라와요"
    /// 서버에 순위 함수가 아직 없다(PGRST202 — 앱이 db push 보다 먼저 나간 창). **실패가 아니라 '곧'** 이다.
    package static let rankingUnavailable = "순위는 곧 열려요"
    /// 폰: 맥은 연결 안내 한 문장이지만 폰은 절마다 "무엇을 못 불러왔나" + 공용 [다시 시도]로 말한다(`MobileLoadText` 규칙).
    package static let rankingLoadFailed = "순위를 불러오지 못했어요"
    /// 실패 줄 **아래** 한 줄. 폰
    ///
    /// 이 깃발(`rankingLoadFailed`)에는 원인이 둘 들어온다: 연결·5xx 같은 **다시 시도가 먹는** 실패와, 구버전 앱이라 서버가
    /// `unsupported_client` 로 거절해 **영영 같은 답이 오는** 경우(`GomokuStoreRanking.swift:57` 이 둘을 같은 깃발로 접고,
    /// 스토어가 status 를 넘겨 주지 않아 **뷰는 둘을 가릴 수 없다**). 그래서 원인을 단정하지 않고, 버튼이 안 먹을 때 남는
    /// 나머지 한 길을 같이 말한다 — 전에는 [다시 시도] 버튼만 있어 눌러도 같은 거절이 오는 경로에서 원인이 숨었다.
    package static let rankingLoadFailedHint = "계속 안 되면 앱을 업데이트해 주세요"

    // MARK: 접었다 펴기

    /// 접힌 상태에서 보여 주는 행 수. 로비엔 이미 절이 다섯 개여서, 100행을 그대로 펼치면 관전 입구인 "지금 대결 중"이 묻힌다. 폰
    package static let rankCollapsedRows = 5
    /// 펼쳤을 때의 상한. 서버도 100행까지만 주지만(`gomoku_ranking`), 화면이 서버 값을 믿지 않고 스스로 자른다. 폰
    package static let rankRowLimit = 100
    /// "전체 보기 · 23명". 폰
    package static func rankSeeAll(total: Int) -> String { "전체 보기 · \(peopleCount(total))" }
    package static let rankCollapse = "접기"

    // MARK: 보이스오버

    /// 순위 한 행 — "3위, 솜사탕, 서울센터, 승점 +4, 6승 2패 1무".
    ///
    /// 행을 `children: .combine` 으로 묶지 **않는** 이유: 순위 원(`RankBadge`)이 `accessibilityHidden(true)` 라
    /// 묶으면 **순위가 안 읽힌다**(`Components/MobileRankComponents.swift` — 숫자는 눈으로만 있는 셈이 된다).
    /// 공용 `ChampionRow` 도 같은 이유로 `children: .ignore` + 조립한 라벨을 쓴다.
    package static func rankRowAccessibility(_ entry: GomokuRankEntry, isMe: Bool) -> String {
        var parts = ["\(entry.rank)위"]
        if isMe { parts.append(me) }
        parts.append(entry.user.displayName)
        // `GomokuUser.center` 는 이미 화면 글자("서울")다 — 공용 `CenterBadge` 와 같은 꼴로 읽는다.
        if let center = entry.user.center, !center.isEmpty { parts.append("\(center)센터") }
        parts.append(points(entry.points))
        parts.append(record(wins: entry.wins, losses: entry.losses, draws: entry.draws))
        return parts.joined(separator: ", ")
    }
}
