import CheckCore
import Foundation

/// 폰 1:1 테트리스(1.0.11) 문구 표.
///
/// ── 어디까지가 이 표의 몫인가 ───────────────────────────────────────────────────────────────
/// **안내·결과 사유는 코어가 쥔다**(`TetrisDuelNoticeText` — 신청·취소·수락·기권 응답과 결과 카드의 사유 한 줄).
/// 맥과 폰이 같은 서버 응답을 같은 말로 옮겨야 하므로 그 표를 **다시 쓰지 마라.**
/// 이 표는 **화면에 붙는 글자**(제목·탭·버튼·라벨·빈 상태·규칙)만 쥔다.
///
/// ── 맥 `TetrisDuelText` 와 갈리는 곳은 셋이다 ──────────────────────────────────────────────
/// ① **조작**: 맥은 키 표(← → ↓ ↑ X Z C 스페이스), 폰은 제스처 + 버튼 셋이다(솔로 폰 테트리스와 같은 조작).
/// ② **판을 떠나는 일의 뜻이 반대다.** 맥은 "창을 가리거나 내려도 판은 계속 흘러가요" 가 **안심**이고(D10),
///    폰은 앱을 나가면 판 루프가 멎어 15초 침묵으로 **진다**(서버 D5). 그래서 같은 자리의 문장이 **경고**다.
///    맥 문장을 폰에 옮기면 그대로 거짓말이 된다 — `leaveWarning` 이 그 자리를 대신한다.
/// ③ 입구가 카드다(게임 탭) — 칩·보조 줄·보이스오버 힌트가 체스 카드와 같은 꼴로 더 있다.
///
/// 레인 규약: 키를 더할 때는 **자기 절 끝**에만 더한다(로비 레인·대결 레인이 같은 줄을 고치지 않게).
/// 이 파일에 `#if os(iOS)` 를 두지 마라 — 맥 스위트가 값으로 재는 자리라야 폰 화면의 글자가 검증된다.
package enum TetrisPhoneText {

    // MARK: - 공용 (두 절이 함께 쓴다)

    package static let title = "1:1 테트리스"
    /// 게임 탭 카드 부제 · 로비 머리글 부제(맥과 같은 한 줄 — 승부 방식을 먼저 말한다).
    package static let subtitle = "공격형 · 먼저 꼭대기까지 쌓이면 져요"
    package static let cardSubtitle = subtitle
    /// 게임 탭 카드의 보이스오버 힌트(막히지 않았을 때).
    package static let cardOpenHint = "1:1 테트리스 대결 화면을 열어요"
    package static let close = "닫기"

    /// 판돈 줄. 이기면 **순이익**(판돈 − 수수료, `DuelFee.winnerNet`) — 결과 카드의 루비 변화와 같은 숫자다.
    package static func stakeLine(_ stake: Int) -> String { "\(stake) · 이기면 +\(DuelFee.winnerNet(stake: stake))" }
    package static func challengeWithStake(_ stake: Int) -> String { "\(stake) 걸고 신청하기" }
    package static func stakePromptTitle(name: String) -> String { "\(name)님에게 신청" }
    package static let stakePromptCaption = "판돈을 고르세요"

    package static func record(wins: Int, losses: Int, draws: Int) -> String { "\(wins)승 \(losses)패 \(draws)무" }

    package static func record(_ record: TetrisDuelRecord?) -> String {
        guard let record else { return self.record(wins: 0, losses: 0, draws: 0) }
        return self.record(wins: record.wins, losses: record.losses, draws: record.draws)
    }

    package static func points(_ value: Int) -> String { "승점 \(value >= 0 ? "+" : "")\(value)" }

    /// 남은 초(신청 TTL · 준비 대기). 음수는 0 으로.
    package static func remainingSeconds(_ seconds: Int) -> String { "\(max(0, seconds))초 남음" }

    /// 규칙 보기. 공격 표 · 가속 · 침묵 · 판돈은 **설계서 결정 그대로**다(D2 · D5 · D7 · D4).
    /// ★ "연결" 항목이 맥과 다르다(머리말 ②) — 폰은 앱을 나가면 진다.
    package static let rulesTitle = "1:1 테트리스 규칙"
    package static let rules: [(title: String, detail: String)] = [
        ("공격", "2줄을 한 번에 지우면 상대에게 방해 줄 1줄, 3줄은 2줄, 4줄은 4줄을 보내요. "
            + "들어올 방해 줄이 있으면 내가 보낼 줄이 먼저 그것을 지워요."),
        ("방해 줄", "줄을 지우지 못한 채 조각이 굳으면 아래에서 회색 줄이 올라와요. 판 왼쪽 빨간 막대가 들어올 줄이에요."),
        ("승부", "먼저 꼭대기까지 쌓이는 쪽이 져요. 2분이 지나면 떨어지는 속도가 점점 빨라져요."),
        ("조작", "판을 좌우로 끌어 옮기고, 아래로 끌어 내려요. 판을 톡 누르면 회전해요. "
            + "아래 버튼으로 \(holdButton) · \(rotateCounterButton) 회전 · \(hardDropButton)를 해요."),
        ("앱을 나가면", "판 중에 앱을 나가면 판이 멈춰서 15초 뒤에 져요. 대결이 끝날 때까지 앱을 켜 두세요."),
        ("판돈", "수락하는 순간 두 사람 모두 판돈을 걸어요. 이기면 판돈만큼 더 받고(수수료 \(DuelFee.percent)% 빼고), "
            + "무승부면 돌려받아요. 30초 안에 둘 다 들어오지 않아도 돌려받아요.")
    ]

    // MARK: - 로비 (레인 B)

    package static let usersTab = "상대 고르기"
    package static let rankTab = "순위"
    package static let lobbyCaption = "근무 중이 아니어도 신청하고 받을 수 있어요"
    package static let emptyUsers = "지금 대결할 수 있는 사람이 없어요"
    package static let loadingUsers = "상대 목록을 불러오고 있어요"
    // ★ **불러오기 실패 문구·[다시 시도] 버튼을 이 표에 두지 마라.** 폰은 공용 부품 한 벌이 쥔다
    //   (`MobileComponentRules.retry` · `.checkConnection` · `LoadFailureRow` · `EmptyStateView`) —
    //   `IntegrationFixTests.designConsistencyContracts` 가 그 리터럴이 CheckMobileKit 안에서 **한 파일에만**
    //   있는지 센다. 맥 표에는 `reloadUsers`·`usersLoadFailed` 가 있지만 폰에 옮기면 그 단언이 빨개진다.
    /// 상대 목록을 불러오지 못했다(한 번도 못 받았을 때만 그린다 — `MobileLoadKnowledge`).
    ///
    /// ★ 값이 **맥 표와 다르다**: 맥 `TetrisDuelText.usersLoadFailed` 는 공용 연결 안내
    ///   (`TetrisDuelNoticeText.checkConnection`)를 그대로 쓰는데, 폰에서 그 문장은 공용 부품 한 벌이 쥐고
    ///   (`MobileComponentRules`) **CheckMobileKit 안에서 한 파일에만** 있어야 한다. [다시 시도] 글자도 여기
    ///   없다 — `LoadFailureRow` 가 공용 글자로 그린다.
    package static let usersLoadFailed = "상대 목록을 불러오지 못했어요"
    package static let challenge = "신청"
    package static let needsUpdate = "앱 업데이트 필요"
    package static let inMatch = "대결 중"
    package static let working = "근무 중"
    package static let focused = "집중 모드"

    package static let stakeTitle = "판돈"
    package static let incomingTitle = "받은 신청"
    package static let incomingChip = "받은 신청"
    package static func incomingMore(_ count: Int) -> String { "외 \(count)건" }
    package static let outgoingTitle = "보낸 신청"
    package static let outgoingLine = "보낸 신청의 답을 기다리고 있어요"
    package static let noIncoming = "받은 신청이 없어요"
    package static let accept = "수락"
    package static let decline = "거절"
    package static let cancel = "취소"
    /// 칩도 보조 줄도 없을 때의 카드 한 줄(= 할 일을 말한다).
    package static let idleLine = "사람을 골라 대결을 신청해 보세요"

    package static let recordTitle = "내 전적"
    package static let liveTitle = "지금 대결 중"
    package static let noLive = "지금 진행 중인 대결이 없어요"
    package static let myMatch = "내 판"

    package static let rankLoading = "순위를 불러오고 있어요"
    package static let rankEmpty = "아직 순위가 없어요"
    package static let rankSoon = "순위는 곧 열려요"
    package static let rankHelp = "승점 = 승 − 패"

    package static func rankSince(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일부터"
        return formatter.string(from: date)
    }

    // ── 상대 한 줄 (레인 B 가 더했다) ───────────────────────────────────────────────────────────

    package static let notWorking = "근무 안 함"

    /// 상대 한 줄의 두 자리. **한 함수가 둘을 같이 고른다** — 자리마다 따로 고르면 같은 문장이 한 줄에 두 번
    /// 나오고(체스 헤드리스 실측 D4) 근무 축이 덮인다.
    package struct OpponentRow: Equatable, Sendable {
        package let subtitle: String
        package let buttonTitle: String

        package init(subtitle: String, buttonTitle: String) {
            self.subtitle = subtitle
            self.buttonTitle = buttonTitle
        }
    }

    /// 부제는 **늘 근무 축**, 버튼은 **막힌 까닭 하나**다. 버튼이 말할 수 있는 까닭은 하나뿐이라, 겹치는 갈래
    /// (옛 버전 + 대결 중 + 집중)에서 버튼이 못 말한 축을 부제 꼬리로 보낸다 — 그러지 않으면 축 하나가 사라진다.
    ///
    /// 서열은 **옛 버전이 먼저**다(체스와 같은 근거): 상대가 앱을 올릴 때까지 서버가 `target_outdated` 로 거절하는,
    /// 가장 오래 가는 막힘이다. 서버 `capable` 이 nil 로 와도 코어가 false 로 읽으므로(`TetrisDuelStore.user(from:)`)
    /// **모르는 상대는 불가로 그린다** — 신청해서 거절을 받는 것보다 낫다.
    ///
    /// ★ 버튼이 [신청]인 것과 코어의 `canBeChallenged` 가 **같은 집합**이어야 한다(테스트가 16 갈래를 다 센다).
    ///   갈리면 눌리는 버튼이 서버 거절을 받거나, 신청할 수 있는 사람에게 회색 알약이 선다.
    package static func opponentRow(for user: TetrisDuelUser) -> OpponentRow {
        let work = user.isWorking ? working : notWorking
        var tail: [String] = []
        let button: String
        if !user.isCapable {
            button = needsUpdate
            if user.inMatch { tail.append(inMatch) }
            if user.isFocused { tail.append(focused) }
        } else if user.inMatch {
            button = inMatch
            if user.isFocused { tail.append(focused) }
        } else if user.isFocused {
            button = focused
        } else {
            button = challenge
        }
        return OpponentRow(subtitle: ([work] + tail).joined(separator: " · "), buttonTitle: button)
    }

    package static func peopleCount(_ count: Int) -> String { "\(count)명" }
    package static func liveCount(_ count: Int) -> String { "\(count)판" }
    /// [신청] 버튼의 보이스오버 힌트 — 누르면 **바로 신청이 나가지 않는다**(판돈 시트가 먼저다).
    package static func challengeHint(name: String) -> String { "\(name)님에게 판돈을 골라 신청해요" }
    /// 머리 두 칸 왼쪽(내 전적)의 보이스오버 — 제목과 값이 한 요소로 합쳐지므로 무슨 전적인지 말한다.
    package static func myRecordAccessibility(_ record: TetrisDuelRecord?) -> String {
        "내 1:1 테트리스 전적 \(self.record(record))"
    }

    // ── 신청 카드 ─────────────────────────────────────────────────────────────────────────────

    package static func incomingTitle(name: String) -> String { "\(name)님의 신청" }
    package static func outgoingTitle(name: String) -> String { "\(name)님에게 신청했어요" }

    /// 받은 신청 절 머리의 오른쪽 한 줄. ★ **초를 박지 않는다** — 서버가 `invite_ttl_seconds` 로 말하고 코어가
    /// 그 값을 쥔다(`TetrisDuelStore.inviteTTLSeconds`). 상수를 베끼면 서버가 TTL 을 바꾼 날 화면만 옛 숫자다.
    package static func inviteTtlHint(ttlSeconds: Int) -> String { "\(ttlSeconds)초 안에 응답하세요" }

    /// ★ 신청만 한 상태를 말하는 줄. "신청하면 빠져요" 로 적으면 **거짓**이다 — 신청은 0원도 움직이지 않고
    /// 응답이 없으면 그대로 사라진다. 빠지는 순간은 **수락**이다(서버 §2.4 `tetris_respond`).
    package static func stakeNotHeldYet(ttlSeconds: Int) -> String {
        "신청만 해서는 루비가 빠지지 않아요 · \(ttlSeconds)초 안에 응답이 없으면 신청이 사라져요"
    }

    package static func remaining(_ seconds: Double) -> String { "\(Int(max(0, seconds).rounded(.up)))초" }
    /// "42초 남음"(받은·보낸 신청 부제 · 준비 대기).
    package static func remainingPhrase(_ seconds: Double) -> String { "\(remaining(seconds)) 남음" }
    /// 남은 초의 보이스오버("남은 시간 42초") — 화면 글자와 어순이 다르다.
    package static func remainingAccessibility(_ seconds: Double) -> String { "남은 시간 \(remaining(seconds))" }

    // ── 판돈 고르기 ───────────────────────────────────────────────────────────────────────────

    /// 고를 수 있는 판돈 셋(3 · 5 · 10). 집합의 주인은 서버(`stakes`)이고 앱 값과 갈리면 진실은 거절한 쪽에 있다.
    package static let stakes = TetrisDuelStake.allCases.map(\.rawValue)
    /// "이기면 +4" — 판돈 칸 아래 줄(꼬리 `stakeGainSuffix` 와 달리 앞 가운뎃점이 없다).
    package static func stakeGain(_ stake: Int) -> String { "이기면 +\(DuelFee.winnerNet(stake: stake))" }
    package static func stakeGainSuffix(_ stake: Int) -> String { " · 이기면 +\(DuelFee.winnerNet(stake: stake))" }
    package static func stakePromptChosen(_ stake: Int) -> String { "판돈 \(stakeLine(stake))" }
    /// 루비가 모자라 못 고르는 판돈의 이유 한 줄. 정본은 앱의 다른 화면과 **같은 말**이다.
    package static let stakeShortfall = CheckCoreShared.shortfallNotice(need: nil, have: nil)
    /// 판돈이 **언제** 빠지는지(주어가 '수락'이다) — 오목·체스와 같은 한 문장.
    package static let stakeCaption = GomokuPhoneText.stakeCaption
    package static let selected = "선택됨"
    package static func stakeOptionAccessibility(_ stake: Int) -> String { "판돈 루비 \(stake)" }

    package static let myRubyTitle = "내 루비"
    /// 값을 아직 모르는 숫자 칸(루비 잔액 미러가 비었다).
    package static let unknownNumber = "–"
    /// 한 줄 안에서 토막을 잇는 머리("· 루비가 모자라요").
    package static let bulletPrefix = "· "

    // ── 지금 대결 중 ──────────────────────────────────────────────────────────────────────────

    /// "테트라이벌 vs 구름빵" — 로비 "지금 대결 중" 한 줄. 관전은 **없다**(D8) 이므로 누를 것이 없는 줄이다.
    package static func liveRow(_ a: String, _ b: String) -> String { "\(a) vs \(b)" }

    // ── 순위 탭 ──────────────────────────────────────────────────────────────────────────────

    package static let rankTitle = "테트리스 순위"
    /// 절 아래 캡션(승점의 뜻) — `rankHelp` 과 같은 한 문장이다(두 벌로 적지 않는다).
    package static var rankCaption: String { rankHelp }
    /// 0판인 사람은 순위판에 안 낀다(서버가 아예 안 준다). 빈 순위를 사고로 읽지 않게 하는 줄이다.
    package static let rankZeroGamesNote = "한 판도 대결하지 않으면 순위에 들어가지 않아요"
    package static let rankEmptyHint = "첫 대결이 끝나면 순위가 올라와요"
    package static let rankLoadFailed = "순위를 불러오지 못했어요"
    /// 실패 줄 **아래** 한 줄 — 원인이 둘(연결·구버전 거절)인데 뷰가 가릴 수 없으므로 단정하지 않는다.
    package static let rankLoadFailedHint = "계속 안 되면 앱을 업데이트해 주세요"
    package static let myRankTitle = "내 순위"
    package static let outOfRank = "순위 밖"
    /// 컷이 없다(응답 `record_since_ms` 가 null) — 기간이 통째다.
    package static let rankWholePeriod = "전체 기간"
    /// 접힌 상태에서 보여 주는 행 수 · 펼쳤을 때의 상한(서버도 100행까지 준다 — D11).
    package static let rankCollapsedRows = 5
    package static let rankRowLimit = 100
    package static func rankSeeAll(total: Int) -> String { "전체 보기 · \(peopleCount(total))" }
    package static let rankCollapse = "접기"

    /// 목록 밖 내 순위 한 줄 — "12위 · 승점 +4 · 6승 2패 1무"(0판이면 "순위 밖 · 0승 0패 0무").
    package static func myRankLine(_ mine: TetrisDuelMyRank) -> String {
        let line = record(wins: mine.wins, losses: mine.losses, draws: mine.draws)
        guard let rank = mine.rank else { return "\(outOfRank) · \(line)" }
        return "\(rank)위 · \(points(mine.points)) · \(line)"
    }

    /// 순위 한 행의 보이스오버 — "3위, 나, 민트별, 승점 +4, 6승 2패 1무".
    ///
    /// ★ 행은 **순위 · 이름 · 승점 · 승 · 패 · 무를 다 말한다**(체스·오목과 같은 사용자 지시). 순위 원을
    ///   `accessibilityHidden` 으로 두므로 묶기가 아니라 조립한 라벨을 쓴다.
    package static func rankRowAccessibility(_ entry: TetrisDuelRankEntry, isMe: Bool) -> String {
        var parts = ["\(entry.rank)위"]
        if isMe { parts.append(me) }
        parts.append(entry.user.displayName)
        parts.append(points(entry.points))
        parts.append(record(wins: entry.wins, losses: entry.losses, draws: entry.draws))
        return parts.joined(separator: ", ")
    }

    // MARK: - 대결 (레인 C)

    package static let me = "나"
    package static let elapsedTitle = "경과"
    /// 2분이 지나 가속이 걸렸다(D7 — 레벨 바닥이 1 을 넘었다).
    package static let speedUp = "속도 올라가는 중"
    package static func speedLevel(_ level: Int) -> String { "레벨 \(level)" }
    package static let connectionTrouble = "연결 확인 중"
    package static let opponentSilent = "상대 연결 확인 중"
    package static let linesTitle = "지운 줄"
    package static let attackTitle = "보낸 공격"
    package static let incomingLinesTitle = "들어올 줄"
    package static let ready = "준비 완료"
    package static let notReady = "들어오는 중"
    package static let finishedPresence = "대결 끝"
    package static let waitingTitle = "상대를 기다리는 중"
    package static func waitingSubtitle(seconds: Int) -> String { "\(max(0, seconds))초 안에 둘 다 들어오면 시작해요" }
    /// 맥은 "창을 열어 두세요", 폰은 앱이다.
    package static let waitingAction = "앱을 켜 둔 채 기다려 주세요"
    package static let startingSoon = "곧 시작해요"
    package static let playingNow = "대결 중"
    package static let toppedOutTitle = "꼭대기에 닿았어요"
    package static let toppedOutSubtitle = "결과를 기다리는 중"

    /// ★ 판 위에 **늘 보이는 한 줄**(머리말 ②). 규칙 시트에만 두면 안 된다 — 판 중에 전화가 와서 나가는 사람은
    ///   규칙을 읽지 않는다. 판돈이 걸린 판을 조용히 잃는 길을 글자 없이 두지 않는 것이 이 줄의 일이다.
    package static let leaveWarning = "판 중에 앱을 나가면 져요"

    package static let resign = "기권"
    package static let confirmResign = "기권하기"
    package static let keepPlaying = "계속하기"
    package static let resignWarning = "기권하면 판돈을 잃어요"
    package static let backToLobby = "로비로"

    package static let controlsTitle = "조작"
    /// 조작 안내(솔로 폰과 같은 제스처·버튼). **정지는 없다** — 대결은 멈출 수 없다.
    package static let controls: [(gesture: String, action: String)] = [
        ("좌우로 끌기", "이동"), ("톡 누르기", "회전"), ("아래로 끌기", "빨리 내리기"),
        ("[" + holdButton + "]", holdButton),
        ("[" + rotateCounterButton + "]", rotateCounterButton + " 회전"),
        ("[" + hardDropButton + "]", hardDropButton)
    ]

    package static func outcomeTitle(_ outcome: TetrisDuelOutcome?) -> String {
        switch outcome {
        case .won?: return "이겼어요"
        case .lost?: return "졌어요"
        case .draw?: return "무승부예요"
        case nil: return "대결이 끝났어요"
        }
    }

    /// 판 시계 글자(`m:ss`). 음수는 0 으로.
    package static func clock(_ seconds: Double) -> String {
        let whole = Int(max(0, seconds).rounded(.down))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }

    /// 루비 증감 글자(+N / −N / 0).
    package static func rubyDelta(_ value: Int) -> String { value > 0 ? "+\(value)" : "\(value)" }

    // ── 대결 절 (레인 C 가 더한 자리 — 판 화면·캔버스가 읽는다) ──────────────────────────────

    /// 판 위 글자 겹. 솔로 캔버스와 **같은 말**이고(두 판이 같은 그림이어야 한다) 자리는 코어 배치 표가 정한다.
    package static let holdLabel = "홀드"
    package static let nextLabel = "다음"
    /// 값 자리는 자기설명형이다 — 폰은 8pt 캡션을 못 쓴다(iOS 캡션 하한 10pt · 캔버스 머리말 ②).
    package static func levelValue(_ level: Int) -> String { "Lv " + String(level) }
    package static func linesValue(_ lines: Int) -> String { String(lines) + "줄" }
    /// 판 밑 밴드·상대 줄의 들어올 줄(미터와 같은 빨강으로 쓴다).
    package static func incomingLines(_ lines: Int) -> String { incomingLinesTitle + " " + String(lines) }

    package static let myBoardLabel = "내 판"
    package static let opponentBoardLabel = "상대 판"

    /// 조작 버튼 세 개의 **글자**. `controls` 표의 꺾쇠 안 말과 **같아야 한다**(규칙 시트와 버튼이 갈리면
    /// 같은 버튼을 두 이름으로 부르게 된다 — 테스트가 그 둘을 묶어 둔다).
    ///
    /// ★ **솔로 표를 가리킨다**(글자를 베끼지 않는다). 같은 기기의 같은 버튼이 화면에 따라 "반시계"와 "반대로"
    ///   두 이름으로 불리면, 솔로로 배운 사람이 대결에서 버튼을 다시 찾는다. 솔로 말이 먼저 나갔으니
    ///   (v0.3.38 · 1.0.x) 그쪽이 기준이다. 가리키면 **나중에 솔로 말이 바뀌어도 둘이 갈라지지 않는다** —
    ///   베껴 두면 한쪽만 고쳐질 자리다(통합에서 실제로 갈라져 있었다).
    package static let holdButton = GamesMiniGameText.tetrisHold
    package static let rotateCounterButton = GamesMiniGameText.tetrisRotateCounterClockwise
    package static let hardDropButton = GamesMiniGameText.tetrisHardDrop
    /// 홀드를 이미 쓴 조각(버튼의 보이스오버 값).
    package static let holdSpent = "이미 썼어요"

    /// 기권 확인 시트 제목(본문은 `resignWarning` · 버튼은 `confirmResign`/`keepPlaying`).
    package static let resignConfirmTitle = "기권할까요?"
}
