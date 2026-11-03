import CheckCore
import Foundation

/// 폰 아잉 큐브(1.0.16) 문구 표 — 맥 `RummyText`·`RummyLobbyText`·`RummyMatchText`·`RummyResultText`·`RummyCueText`·`RummyExitText` 를 **터치 기준으로 다시 쓴 것**.
///
/// ── 어디까지가 이 표의 몫인가 ──
/// **서버 응답·판정 이유 문구는 코어가 쥔다**(`RummyNoticeText`, 스토어 `notice`). 맥과 폰이 같은 응답을 같은 말로 옮겨야 하므로 다시 쓰지 마라.
/// 이 표는 화면에 붙는 글자(제목·탭·버튼·라벨·빈 상태·규칙)만 쥔다.
///
/// ── 맥과 갈리는 곳 ──
/// ① 입력 낱말: 맥의 끌기·⌥·마우스·창 낱말이 없다(손가락으로 끌기 · 꾹 누르기 · 벌리기). `GamesRummyWiringTests` 가 글자로 잰다.
/// ② 떠나는 일: 맥은 "창을 닫으면 기권", 폰은 "[나가기]를 누르면 기권"이다. 앱을 내리는 것은 기권이 아니다(서버 90초 끊김 규칙 — 사용자 결정 기본값).
/// ③ 시간 초과는 **되돌리고 1장**이다(`rummy-mobile-handoff.md` 의 3장은 낡았다).
/// ④ 등수 분배는 순수익으로 말한다(2명 +판돈/−판돈 · 3명 +판돈/0/−판돈 · 4명 +판돈×2/0/−판돈/−판돈). 실제 분배는 서버 값(`payout`)만 쓴다.
///
/// 레인 규약: 키를 더할 때는 **자기 절 끝**에만 더한다(로비·판·결과 레인이 같은 줄을 고치지 않게).
/// 이 파일에 `#if os(iOS)` 를 두지 마라 — 맥 스위트가 값으로 재는 자리라야 폰 화면의 글자가 검증된다.
package enum GamesRummyText {

    // MARK: - 공용

    package static let title = "아잉 큐브"
    package static let subtitle = "2~4명이 숫자 타일로 묶음을 만들어 랙을 먼저 비우는 게임"
    package static let cardSubtitle = subtitle
    /// 게임 탭 카드의 보이스오버 힌트(막히지 않았을 때).
    package static let cardOpenHint = "아잉 큐브 화면을 열어요"
    package static let rulesButton = "규칙"
    package static let close = "닫기"
    package static let me = "나"
    package static let hostTag = "방장"
    package static let leave = "나가기"
    package static let keepPlaying = "계속하기"

    /// 값으로 자리를 맞추는 글자들.
    package static func seconds(_ value: Int) -> String { "\(value)초" }
    package static func clock(_ seconds: Int) -> String { String(format: "%d:%02d", seconds / 60, seconds % 60) }
    package static func stake(_ stake: Int?) -> String { "판돈 \(stake ?? 0)" }
    package static func seats(_ joined: Int, max: Int) -> String { "\(joined)/\(max)명" }
    package static func rackCount(_ count: Int?) -> String { "\(count ?? 0)장" }
    package static func pool(_ count: Int?) -> String { "더미 \(count ?? 0)장" }
    package static func rank(_ rank: Int?) -> String { rank.map { "\($0)등" } ?? "—" }
    package static func net(_ value: Int) -> String { value > 0 ? "+\(value)" : (value < 0 ? "−\(-value)" : "0") }
    package static func score(_ score: Int?) -> String {
        guard let score else { return "점수 —" }
        return "점수 \(net(score))"
    }

    // MARK: - 게임 탭 카드

    package static let activeChip = "판 진행 중"
    package static let roomChip = "방에 있어요"
    package static func incomingChip(_ count: Int) -> String { "받은 초대 \(count)" }
    package static let idleLine = "사람을 불러 탁자를 열어 보세요"
    package static let recordTitle = "내 전적"
    package static func record(games: Int?, wins: Int?) -> String { "판 수 \(games ?? 0) · 1등 \(wins ?? 0)" }

    // MARK: - 로비(레인 A)

    package static let usersTab = "사람"
    package static let rankTab = "순위"
    package static let newTable = "새 탁자"
    package static let myTable = "내 탁자"
    package static let openTable = "탁자 열기"
    package static let readyHeader = "초대 가능"
    /// 방 안에서는 이 절에 이미 앉은 사람·초대한 사람도 든다 — '초대 가능 N명' 이 사실이 아니다.
    package static let peopleHeader = "사람"
    package static let busyHeader = "지금은 바빠요"
    package static let invite = "초대"
    package static let invited = "초대함"
    package static let joined = "참가함"
    package static let join = "참가"
    package static let decline = "거절"
    package static let calling = "부르는 중"
    /// 의자 카드와 사람 행이 같은 낱말을 쓴다(`invited` · `joined`).
    package static let waitingAnswer = invited
    package static let seated = joined
    package static let take = "앉기"
    package static let emptySeat = "빈자리"
    package static let joinEmpty = "받은 초대나 열린 공개 탁자가 생기면 이 화면 맨 위에 떠요"
    package static let emptyUsers = "함께할 사람이 아직 없어요"
    package static let loadingUsers = "사람 목록을 불러오는 중…"
    package static let stakeLabel = "판돈"
    package static let publicLabel = "공개 방"
    package static let publicOn = "누구나 참가"
    package static let publicOff = "초대한 사람만"
    package static let createHint = "판돈은 시작할 때 모두에게서 걷고, 등수대로 나눠 가져요."
    package static let peopleCaptionNoRoom = "[초대]를 누르면 탁자가 열리고 바로 불러요"
    package static let peopleCaptionHost = "초대할 사람을 골라요"
    package static let peopleCaptionGuest = "방장만 초대할 수 있어요"
    package static let outdatedHint = "새 버전이면 같이 할 수 있어요"
    package static let recordLabel = "내 전적"
    package static let rankHeader = "1등 많은 순"
    package static let emptyRanking = "아직 끝난 판이 없어요"
    package static func outdatedFold(_ count: Int, expanded: Bool) -> String {
        expanded ? "업데이트가 필요한 사람 \(count)명 접기" : "업데이트가 필요한 사람 \(count)명"
    }
    package static func called(by name: String) -> String { "\(name)님이 불렀어요" }
    package static func publicTable(of name: String) -> String { "\(name)님의 공개 탁자" }
    package static func freeSeats(_ count: Int) -> String { "빈자리 \(count)" }
    package static func stakeCaption(_ stake: Int) -> String { "판돈 \(stake) · 끝나면 등수대로 · 한 차례 60초" }
    package static func peopleCaption(inRoom: Bool, amHost: Bool) -> String {
        guard inRoom else { return peopleCaptionNoRoom }
        return amHost ? peopleCaptionHost : peopleCaptionGuest
    }
    package static let joinHeader = "받은 초대 · 공개 탁자"
    package static let myRuby = "내 루비"
    package static let unknownNumber = "—"
    package static let selected = "선택됨"
    package static let stakeShortfall = "루비가 모자라요"
    package static let usersLoadFailed = "사람 목록을 불러오지 못했어요"
    package static let statusOutdated = "업데이트 필요"
    package static let statusInMatch = "게임 중"
    package static let statusFocus = "집중"
    package static let statusWorking = "근무 중"
    package static let statusIdle = "쉬는 중"
    package static let roomFullShort = "가득 찼어요"
    package static let inviteSheetTitle = "새 탁자"
    package static func people(_ count: Int) -> String { "\(count)명" }
    package static func places(_ count: Int) -> String { "\(count)곳" }
    package static func peopleTabWithInvites(_ count: Int) -> String { "\(usersTab) · 초대 \(count)" }
    package static func inviteSheetPrompt(name: String) -> String { "\(name)님을 부를 탁자를 열어요" }
    package static func openAndCall(stake: Int) -> String { "판돈 \(stake) 탁자 열고 부르기" }
    package static func stakeOption(_ stake: Int) -> String { "판돈 \(stake)" }
    package static func inviteHint(name: String) -> String { "\(name)님을 탁자로 불러요" }
    /// 고른 판돈이 잔액을 넘었다 — 왜 막혔는지 + 무엇을 하면 풀리는지(폰엔 호버 툴팁이 없다).
    package static func stakeShort(stake: Int, balance: Int) -> String {
        "판돈 \(stake)에 루비가 모자라요(내 루비 \(balance)). 판돈을 낮춰 보세요."
    }
    /// 참가 행 라벨(접근성) — 초대는 누가 불렀는지, 공개 방은 빈자리.
    package static func joinableAccessibility(title: String, stake: Int, seats: String) -> String {
        "\(title), 판돈 \(stake), \(seats)"
    }
    package static let rankLoadFailed = "순위를 불러오지 못했어요"
    package static let rankLoading = "순위를 불러오는 중…"
    package static let myRankTitle = "내 순위"
    package static let rankCollapse = "접기"
    package static let rankEmptyHint = "판을 끝내면 순위에 올라요"
    package static func rankSeeAll(total: Int) -> String { "전체 보기 (\(total))" }
    package static func rankWins(_ wins: Int?) -> String { "1등 \(wins ?? 0)" }
    package static func rankGames(_ games: Int?) -> String { "판 수 \(games ?? 0)" }
    /// 순위표의 자리 — 'N위'. 판 등수 'N등'(`rank`)과 가른다: 한 줄에 '2등 · 1등 5' 로 붙으면 두 뜻이 섞인다(폰의 다른 순위도 '위'다).
    package static func ladderRank(_ rank: Int?) -> String { rank.map { "\($0)위" } ?? unknownNumber }
    package static func myRankLine(rank: Int?, games: Int?, wins: Int?) -> String {
        "\(ladderRank(rank)) · \(record(games: games, wins: wins))"
    }
    package static func rankRowAccessibility(rank: Int?, name: String, isMe: Bool, games: Int?, wins: Int?) -> String {
        "\(ladderRank(rank)), \(name)\(isMe ? ", \(me)" : ""), \(record(games: games, wins: wins))"
    }

    // MARK: - 방(레인 A)

    package static let start = "시작"
    package static let startHintHost = "2명 이상 모이면 시작할 수 있어요"
    package static let startHintGuest = "방장이 시작하기를 기다리고 있어요"
    package static func startWith(_ players: Int) -> String { "\(players)명으로 시작" }
    package static func pot(stake: Int, players: Int) -> String { "\(stake) × \(players)명 = \(stake * players)" }
    package static func closesIn(_ seconds: Int) -> String { "\(clock(seconds)) 뒤 닫혀요" }
    package static let emptyChairInvite = "초대"
    package static let startBlockedShort = "루비가 모자라 시작할 수 없어요"
    /// 탁자 가운데의 상금(판돈 × 인원).
    package static func potTotal(stake: Int, players: Int) -> String { "\(stake * players)" }
    package static func potFormula(stake: Int, players: Int) -> String { "판돈 \(stake) × \(players)명" }
    /// 등수 분배 — **순수익**이다(2명 +판돈/−판돈 · 3명 +판돈/0/−판돈 · 4명 +판돈×2/0/−판돈/−판돈). 안내 글자 전용이고 실제 분배는 서버 값(`payout`)만 쓴다.
    /// 탁자 가운데가 좁아(320pt 기기 112pt) 한 줄씩 낸다. 4명의 3·4등은 같은 값이라 한 줄로 합친다.
    package static func splitLines(players: Int, stake: Int) -> [String] {
        switch players {
        case ...2: return ["1등 \(net(stake))", "2등 \(net(-stake))"]
        case 3: return ["1등 \(net(stake))", "2등 \(net(0))", "3등 \(net(-stake))"]
        default: return ["1등 \(net(stake * 2))", "2등 \(net(0))", "3·4등 \(net(-stake))"]
        }
    }
    /// 의자 한 칸 라벨(접근성).
    package static func chairAccessibility(name: String, tag: String?) -> String {
        tag.map { "\(name), \($0)" } ?? name
    }

    // MARK: - 판(레인 B)

    package static let submit = "완료"
    package static let draw = "뽑기"
    package static let pass = "넘기기"
    package static let undo = "되돌리기"
    package static let sortNumber = "777"
    package static let sortColor = "789"
    package static let react = "반응"
    /// 반응 단추 기호. `face.smiling` 은 다크에서 채운 흰 원으로 보여 옆 기호와 무게가 어긋난다.
    package static let reactionSymbol = "smiley"
    package static let rotating = "화면을 가로로 돌리고 있어요"
    package static let zoomFull = "전체 보기"
    package static let zoomDefault = "크게 보기"
    package static let myTurnBadge = "내 차례"
    package static let myTurn = "내 차례예요 — 타일을 끌어 판에 놓아요"
    package static let forfeitTag = "기권"
    package static let disconnectedTag = "끊김"
    package static let beforeInitial = "등록 전"
    package static func turnOf(_ name: String) -> String { "\(name)님 차례예요" }
    package static func placing(_ name: String) -> String { "\(name)님이 놓는 중" }
    package static func initialProgress(_ points: Int) -> String { RummyNoticeText.initialProgress(points) }
    package static func potLine(stake: Int?, seats: Int?) -> String { "판돈 \(stake ?? 0) × \(seats ?? 0)명" }
    package static func timeouts(_ streak: Int) -> String { "시간 초과 \(streak)/3" }
    /// 화면 밖 묶음 배지(◀ 2 · 2 ▶)의 보이스오버 글자.
    package static func offscreenLeft(_ count: Int) -> String { "왼쪽 화면 밖 묶음 \(count)개" }
    package static func offscreenRight(_ count: Int) -> String { "오른쪽 화면 밖 묶음 \(count)개" }
    package static func offscreen(_ side: GamesRummyViewport.Side, count: Int) -> String {
        switch side {
        case .left: return offscreenLeft(count)
        case .right: return offscreenRight(count)
        case .up: return "위쪽 화면 밖 묶음 \(count)개"
        case .down: return "아래쪽 화면 밖 묶음 \(count)개"
        }
    }
    /// 첫 등록 전 받침대 계획 한 줄(맥 `RummyCueText.plan`).
    package static func plan(table: Int, rack: Int) -> String {
        table > 0 ? "랙 묶음 \(rack) + 판 \(table) = \(table + rack) / 30" : "랙 묶음 합 \(rack) / 30"
    }
    /// 내 차례 상태 줄(알림 `notice` 가 없을 때 — 맥 `RummyText.myTurnStatus` 와 같은 서열).
    package static func myTurnStatus(_ editor: RummyTurnEditor) -> String {
        let reason = editor.reason
        if !editor.initialDone {
            if reason == .initialTableTouched, let why = RummyNoticeText.reason(reason, initialPoints: nil) { return why }
            return initialProgress(editor.initialPoints)
        }
        if reason != .ok, editor.isChanged,
           let why = RummyNoticeText.reason(reason, initialPoints: editor.initialPoints) {
            return why
        }
        return myTurn
    }
    /// 직전 사건 한 줄(맥 `RummyText.lastEvent` — 서버 `last_event.kind`).
    package static func lastEvent(_ event: RummyLastEvent?, name: String?) -> String? {
        guard let event, let kind = event.kind, let name else { return nil }
        switch kind {
        case "play": return "\(name)님이 \(event.count ?? 0)장 냈어요"
        case "draw": return "\(name)님이 1장 뽑았어요"
        case "pass": return "\(name)님이 넘겼어요"
        case "timeout_play": return "\(name)님 시간 초과 — 놓던 판으로 확정"
        case "timeout_penalty": return "\(name)님 시간 초과 — 되돌리고 \(event.count ?? 1)장 뽑음"
        case "timeout_draw": return "\(name)님 시간 초과 — 1장 뽑음"
        case "forfeit": return "\(name)님이 기권했어요"
        default: return nil
        }
    }

    /// 남의 차례 동안의 상태 줄(이 기기가 손댄 판). 서버 90초 끊김 규칙을 바꾸지 않고 알리기만 한다 — 4명이면 내 차례가 최대 3분 뒤라 그 사이 앱을 내리기 쉽다.
    /// 90초는 내린 시각이 아니라 마지막 하트비트(10초 주기)부터 재므로 실제로는 최대 10초 짧다. 그래서 사람에겐 '1분'으로 말한다.
    package static let backgroundWarning = "앱을 1분 넘게 내리면 기권될 수 있어요"
    /// 내 자리가 기권·끝난 뒤 남의 판을 보는 동안의 상태 줄.
    package static let spectating = "기권한 판을 보고 있어요"
    /// 보이스오버 — 끌기 대안(타일 고르기 → 판에 놓기)은 이번 판 범위 밖이다. 라벨만 읽어 준다.
    package static let leaveHint = "판을 나가요. 판 중이면 기권돼요."
    package static let sortNumberName = "같은 숫자끼리 정렬"
    package static let sortColorName = "색별로 이어지게 정렬"
    package static func boardSummary(melds: Int, tiles: Int) -> String { "판 묶음 \(melds)개, 타일 \(tiles)장" }
    package static func rackSummary(_ count: Int) -> String { "내 받침대 \(count)장" }
    package static func seatSummary(name: String, count: Int?, isTurn: Bool, tags: [String]) -> String {
        ([name, rackCount(count)] + (isTurn ? ["차례"] : []) + tags).joined(separator: ", ")
    }

    // MARK: - 다른 기기 판(레인 B)

    /// 같은 계정의 다른 기기가 하는 판을 이 폰이 읽기만 하는 동안의 안내 카드.
    package static let elsewhereTitle = "다른 기기에서 하는 판이에요"
    package static let elsewhereDetail = "여기서 판에 타일을 놓거나 반응을 보내면 이 폰에서 이어서 하게 돼요."

    // MARK: - 결과(레인 C)

    package static let resultTitle = "결과"
    package static let playAgain = "한 판 더"
    package static let finalBoard = "최종 판"
    package static let ranks = "등수"
    package static let toLobby = "나가기"
    package static let emptyBoard = "판에 놓인 묶음이 없어요"
    package static let remainingTiles = "남은 타일"
    package static func remainingCount(_ count: Int) -> String { "\(remainingTiles) \(count)장" }
    /// 머리 카드의 내 등수. 기권이면 까닭을 앞에 말한다.
    package static func myResult(rank: Int?, forfeited: Bool) -> String {
        forfeited ? "\(forfeitTag) · \(self.rank(rank))" : self.rank(rank)
    }
    package static func resultRowAccessibility(rank: Int?, name: String, isMe: Bool, forfeited: Bool, score: Int?, net: Int, rackCount: Int) -> String {
        var parts = [self.rank(rank), name]
        if isMe { parts.append(me) }
        if forfeited { parts.append(forfeitTag) }
        parts.append(self.score(score))
        parts.append("루비 \(self.net(net))")
        if rackCount > 0 { parts.append(remainingCount(rackCount)) }
        return parts.joined(separator: ", ")
    }
    /// `winnerIsMe` = 내가 이겼다 — 내 이름을 남처럼 부르지 않는다.
    package static func endReason(_ reason: RummyEndReason?, winner: String?, winnerIsMe: Bool = false) -> String {
        switch reason {
        case .rackEmpty:
            if winnerIsMe { return "랙을 비웠어요" }
            return winner.map { "\($0)님이 랙을 비웠어요" } ?? "랙을 비운 사람이 나왔어요"
        case .blocked: return "더미가 비고 모두 넘겨서 끝났어요"
        case .lastStanding:
            if winnerIsMe { return "혼자 남아 끝났어요" }
            return winner.map { "\($0)님 혼자 남아 끝났어요" } ?? "혼자 남아 끝났어요"
        case .unknown, nil: return "판이 끝났어요"
        }
    }

    // MARK: - 나가기 확인

    package static let forfeitTitle = "판을 나갈까요?"
    package static let forfeitDetail = "나가면 기권돼 꼴찌가 되고 판돈을 잃어요."
    package static let forfeitConfirm = "기권하고 나가기"
    package static let closeRoomTitle = "방이 닫혀요"
    package static let closeRoomDetail = "방장이 나가면 방이 닫히고 모두 로비로 돌아가요. 루비는 그대로예요."
    package static let closeRoomConfirm = "방 닫고 나가기"

    // MARK: - 방에서 탭으로 떠나기

    package static let tabExitHintGuest = "다른 탭으로 가면 방에서 나가요"
    package static let tabExitHintHost = "다른 탭으로 가면 방을 닫을지 먼저 물어봐요"
    package static let tabLeftNotice = "탭을 옮겨서 방에서 나왔어요"
    /// 방 화면에서만 말한다(`isRummyLeaveUnconfirmed`). 코어 `notice` 에 넣지 마라: 그 줄은 판 화면도 읽어, 그새 시작되면 [나가기](= 기권)를 권하게 된다.
    package static let leaveUnconfirmedNotice = "방에서 나오지 못했어요. 아직 자리가 남아 있어요. 연결을 확인하고 [나가기]를 눌러 주세요."
    package static let leaveUnconfirmedDetail = "나오지 못했어요 · 아직 자리가 있어요"

    // MARK: - 규칙(레인 C)

    package static let rulesTitle = "아잉 큐브 규칙"
    /// 규칙 시트 — 예시 타일과 함께(그림은 우리 것). 맥 규칙 창과 같은 내용을 터치로 다시 쓴다.
    package static let rules: [(title: String, detail: String, example: [String])] = [
        ("그룹", "같은 숫자, 서로 다른 색 3~4장.", ["A7", "B7", "C7"]),
        ("런", "같은 색으로 이어지는 숫자 3장 이상(13 다음 1로는 안 이어져요).", ["C3", "C4", "C5", "C6"]),
        ("첫 등록", "내 랙의 타일만으로 만든 새 묶음 합이 30점 이상이어야 해요. 그 전엔 판 묶음을 건드릴 수 없어요.",
         ["B10", "C10", "D10"]),
        ("조커", "아잉이 타일은 어떤 숫자·색으로도 쓰여요. 판의 조커를 가져오면 이번 차례에 판에 다시 써야 해요.",
         ["A5", "J", "A7"]),
        ("판 조작", "첫 등록 뒤엔 판의 묶음을 나누고 합치고 옮겨도 돼요. 끝날 때 모든 묶음이 맞고 내 타일을 1장 이상 "
            + "냈어야 해요. 판에 있던 타일은 랙으로 가져올 수 없어요.", []),
        ("조작", "끌면 한 장 · 0.5초 꾹 누른 채 끌면 덩어리(판에선 누른 타일에서 가까운 끝까지) · 묶음 왼쪽 손잡이로 묶음째 "
            + "옮기기 · 묶음 끝 가까이 놓으면 붙기 · 묶음 위에 놓으면 맞는 자리에 끼우기 · 묶음 가운데를 빼면 둘로 나뉘어요.", []),
        ("판 보기", "빈 펠트를 끌면 판이 밀려요. 두 손가락으로 벌리면 크게 보고, 오른쪽 열 위쪽 버튼으로 한눈에 봐요. "
            + "화면 밖 묶음은 가장자리 배지가 알려 줘요.", []),
        ("받침대", "타일 사이에 놓으면 끼워 넣고 오른쪽을 밀어요. 딱 붙여 놓은 맞는 묶음엔 밑줄과 점수가 떠요. "
            + "777·789로 정렬해 두면 새로 뽑은 타일도 그 정렬 자리로 들어가요.", []),
        ("시간 60초", "시간이 지나면 놓던 판이 맞으면 그대로 확정돼요. 틀렸거나 아무것도 안 놓았으면 되돌리고 1장 뽑아요. "
            + "시간 초과가 3번 이어지면 기권이에요.", []),
        ("기권", "뒤로 단추로 판을 나가거나 시간 초과가 3번 이어지면 기권이고 꼴찌예요. 남은 사람끼리 계속해요. "
            + "앱을 잠깐 내려도 바로 기권은 아니에요 — 1분 안에 돌아오면 이어서 해요.", []),
        ("끝과 점수", "누군가 랙을 비우면 끝나요(더미가 비고 모두 넘겨도 끝). 남은 타일 합만큼 잃고(아잉이 30점), "
            + "이긴 사람이 그만큼 얻어요.", ["D12", "J"]),
        ("등수 분배", "판돈 N 기준 2명 +N·−N · 3명 +N·0·−N · 4명 +2N·0·−N·−N. 기권은 꼴찌예요. 새로 생기는 루비는 없어요.", []),
    ]

    // MARK: - 반응(레인 C)

    package static let reactionTitle = "반응 보내기"
    package static func reactionAccessibility(name: String, sticker: String) -> String { "\(name)님의 반응 \(sticker)" }
}
