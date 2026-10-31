import CheckCore
import Foundation

/// 폰 아잉 큐브(1.0.17) 문구 표 — 맥 `RummyText`·`RummyLobbyText`·`RummyMatchText`·`RummyResultText`·`RummyCueText`·`RummyExitText` 를 **터치 기준으로 다시 쓴 것**.
///
/// ── 어디까지가 이 표의 몫인가 ──
/// **서버 응답·판정 이유 문구는 코어가 쥔다**(`RummyNoticeText`, 스토어 `notice`). 맥과 폰이 같은 응답을 같은 말로 옮겨야 하므로 다시 쓰지 마라.
/// 이 표는 화면에 붙는 글자(제목·탭·버튼·라벨·빈 상태·규칙)만 쥔다.
///
/// ── 맥과 갈리는 곳 ──
/// ① 입력 낱말: 맥의 끌기·⌥·마우스·창 낱말이 없다(손가락으로 끌기 · 꾹 누르기 · 벌리기). `GamesRummyTextTests` 가 글자로 잰다.
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
    #if DEBUG
    /// 자리표시 화면 한 줄. **Debug 에만 있다** — 뒤 레인이 다 채우지 않으면 Release 가 컴파일되지 않는다(저장소 메모 '임시 자리표시가 게이트를 지난다'). 마지막 레인이 이 함수를 지운다.
    package static func placeholder(_ lane: String) -> String { "자리표시 — \(lane)" }
    #endif

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
        return score > 0 ? "점수 +\(score)" : "점수 \(score)"
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
    package static let newTableHint = "[초대]를 누르거나 탁자를 열어요"
    package static let openTable = "탁자 열기"
    package static let readyHeader = "초대 가능"
    package static let busyHeader = "지금은 바빠요"
    package static let invite = "초대"
    package static let invited = "초대함"
    package static let joined = "참가함"
    package static let join = "참가"
    package static let decline = "거절"
    package static let calling = "부르는 중"
    package static let waitingAnswer = "답 기다리는 중"
    package static let seated = "앉음"
    package static let take = "앉기"
    package static let emptySeat = "빈자리"
    package static let joinEmpty = "받은 초대나 열린 공개 탁자가 생기면 여기에 떠요"
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

    // MARK: - 방(레인 A)

    package static let start = "시작"
    package static let startHintHost = "2명 이상 모이면 시작할 수 있어요"
    package static let startHintGuest = "방장이 시작하기를 기다리고 있어요"
    package static func startWith(_ players: Int) -> String { "\(players)명으로 시작" }
    package static func pot(stake: Int, players: Int) -> String { "\(stake) × \(players)명 = \(stake * players)" }
    package static func closesIn(_ seconds: Int) -> String { "\(clock(seconds)) 뒤 닫혀요" }

    // MARK: - 판(레인 B)

    package static let submit = "완료"
    package static let draw = "뽑기"
    package static let pass = "넘기기"
    package static let undo = "되돌리기"
    package static let sortNumber = "777"
    package static let sortColor = "789"
    package static let react = "반응"
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

    // MARK: - 다른 기기 판(레인 B)

    /// 같은 계정의 다른 기기가 하는 판을 이 폰이 읽기만 하는 동안의 안내 카드.
    package static let elsewhereTitle = "다른 기기에서 하는 판이에요"
    package static let elsewhereDetail = "여기서 타일을 옮기면 이 폰에서 이어서 하게 돼요."

    // MARK: - 결과(레인 C)

    package static let resultTitle = "결과"
    package static let playAgain = "한 판 더"
    package static let finalBoard = "최종 판"
    package static let ranks = "등수"
    package static let toLobby = "나가기"
    package static let emptyBoard = "판에 놓인 묶음이 없어요"
    package static let remainingTiles = "남은 타일"
    package static func endReason(_ reason: RummyEndReason?, winner: String?) -> String {
        switch reason {
        case .rackEmpty: return winner.map { "\($0)님이 랙을 비웠어요" } ?? "랙을 비운 사람이 나왔어요"
        case .blocked: return "더미가 비고 모두 넘겨서 끝났어요"
        case .lastStanding: return winner.map { "\($0)님 혼자 남아 끝났어요" } ?? "혼자 남아 끝났어요"
        case .unknown, nil: return "판이 끝났어요"
        }
    }

    // MARK: - 나가기 확인

    package static let forfeitTitle = "나가면 기권돼요"
    package static let forfeitDetail = "나가면 기권돼요. 판돈은 판 끝에 등수대로 정산돼요."
    package static let forfeitConfirm = "기권하고 나가기"
    package static let closeRoomTitle = "방이 닫혀요"
    package static let closeRoomDetail = "방장이 나가면 방이 닫히고 모두 로비로 돌아가요. 루비는 그대로예요."
    package static let closeRoomConfirm = "방 닫고 나가기"

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
        ("판 보기", "빈 펠트를 끌면 판이 밀려요. 두 손가락으로 벌리면 크게 보고, [전체 보기]로 한눈에 봐요. "
            + "화면 밖 묶음은 양쪽 가장자리 배지가 알려 줘요.", []),
        ("받침대", "타일 사이에 놓으면 끼워 넣고 오른쪽을 밀어요. 딱 붙여 놓은 맞는 묶음엔 밑줄과 점수가 떠요. "
            + "777·789로 정렬해 두면 새로 뽑은 타일도 그 정렬 자리로 들어가요.", []),
        ("시간 60초", "시간이 지나면 놓던 판이 맞으면 그대로 확정돼요. 틀렸거나 아무것도 안 놓았으면 되돌리고 1장 뽑아요. "
            + "시간 초과가 3번 이어지면 기권이에요.", []),
        ("기권", "[나가기]를 고르거나 시간 초과가 3번 이어지면 기권이고 꼴찌예요. 남은 사람끼리 계속해요. "
            + "앱을 잠깐 내려도 바로 기권은 아니에요 — 90초 안에 돌아오면 이어서 해요.", []),
        ("끝과 점수", "누군가 랙을 비우면 끝나요(더미가 비고 모두 넘겨도 끝). 남은 타일 합만큼 잃고(아잉이 30점), "
            + "이긴 사람이 그만큼 얻어요.", ["D12", "J"]),
        ("등수 분배", "판돈 N 기준 2명 +N·−N · 3명 +N·0·−N · 4명 +2N·0·−N·−N. 기권은 꼴찌예요. 새로 생기는 루비는 없어요.", []),
    ]

    // MARK: - 반응(레인 C)

    package static let reactionTitle = "반응 보내기"
}
