import SwiftUI
import CheckCore

// MARK: - 아잉 큐브 창 루트 (설계서 §5)
//
// 화면 넷(phase): 로비(방 포함) · 판 · 결과 · 규칙(덮개). init 모양은 테트리스 `TetrisDuelPanel(store:me:safety:)` 와 같다.
//
// ── 이 화면이 지키는 것 ──
//  · **판정은 화면에서 다시 만들지 않는다.** 무효 세트 테두리 = `editor.analysis(ofMeld:).valid`(남의 작업 판은
//    `RummyRules.analyze`), [완료] = `editor.canSubmit`, 첫 등록 진행 = `editor.initialPoints`. 화면은 그 답을 칠할 뿐이다.
//  · 숨은 정보는 서버가 이미 걷었다 — 화면은 `my_rack`(편집기)과 남의 `rack_count` 만 본다.
//  · 초 단위 값(남은 초)은 잎 뷰(`RummyCountdownLeaf`)만 읽는다 — 창 루트가 매초 다시 그려지지 않게(스토어 규약 ⑦).
//  · 사용자 문구 중 **서버 응답·판정 이유 문구는 스토어 `notice` 한 곳**에서 온다. 여기 `RummyText` 는 화면 고정 글자뿐이다.
//
// ── 렌더 주입구(preview) ──
// 스토어는 서버 권위라 상태를 밖에서 못 넣는다(`private(set)`). 렌더 시험은 `previewLobby`·`previewMatch`·`previewEditor`·
// `previewNow` 를 넘겨 그 값으로 그린다(테트리스 `previewXxx` 와 같은 방식). 앱은 전부 nil 이다.

/// 화면 고정 글자 — 서버 응답 문구는 여기 두지 않는다(스토어 `notice`). 판정 이유 한 줄은 설계서 §4.3 표
/// (`RummyNoticeText.reason`)를 그대로 빌려 쓴다(`myTurnStatus`).
enum RummyText {
    static let title = "아잉 큐브"
    static let subtitle = "2~4명이 숫자 타일로 묶음을 만들어 랙을 먼저 비우는 게임"
    static let rulesButton = "규칙"
    static let rulesTitle = "아잉 큐브 규칙"
    static let close = "닫기"
    static let usersTab = "사람"
    static let rankTab = "순위"
    static let publicRoomsTitle = "공개 방"
    static let noPublicRooms = "지금 열린 공개 방이 없어요"
    static let peopleCaptionNoRoom = "[초대]를 누르면 탁자가 열리고 바로 불러요"
    static let peopleCaptionHost = "초대할 사람을 골라요"
    static let peopleCaptionGuest = "방장만 초대할 수 있어요"
    static let emptyUsers = "함께할 사람이 아직 없어요"
    static let loadingUsers = "사람 목록을 불러오는 중…"
    static let join = "참가"
    static let decline = "거절"
    static let invite = "초대"
    static let invited = "초대함"
    static let joined = "참가함"
    static let createTitle = "방 만들기"
    static let createButton = "방 만들기"
    static let stakeLabel = "판돈"
    static let publicLabel = "공개 방"
    static let publicOn = "누구나 참가"
    static let publicOff = "초대한 사람만"
    static let createHint = "판돈은 시작할 때 모두에게서 걷고, 등수대로 나눠 가져요."
    static let myRoomTitle = "내 방"
    static let start = "시작"
    static let leave = "나가기"
    static let forfeit = "기권"
    static let emptySeat = "빈자리"
    static let hostTag = "방장"
    static let invitedTag = "초대 중"
    static let joinedTag = "참가"
    static let startHintHost = "2명 이상 모이면 시작할 수 있어요"
    static let startHintGuest = "방장이 시작하기를 기다리고 있어요"
    static let invitesTitle = "받은 초대"
    static let noInvites = "받은 초대가 없어요"
    static let recordTitle = "내 전적"
    static let rankHeader = "1등 많은 순"
    static let emptyRanking = "아직 끝난 판이 없어요"
    static let undo = "되돌리기"
    static let sortNumber = "777"
    static let sortColor = "789"
    static let draw = "뽑기"
    static let pass = "넘기기"
    static let submit = "완료"
    static let beforeInitial = "등록 전"
    static let myTurn = "내 차례예요 — 타일을 끌어 판에 놓으세요"
    static let newMeld = "새 세트"
    static let toLobby = "로비로"
    static let remainingTiles = "남은 타일"
    static let updateRequired = "앱을 업데이트해 주세요"
    static let serverMissing = "아잉 큐브를 아직 열 수 없어요"
    static let forfeitTitle = "기권할까요?"
    static let forfeitDetail = "기권하면 꼴찌가 되고 판돈을 잃어요. 남은 사람끼리 계속해요."
    static let closeRoomTitle = "방을 닫을까요?"
    static let closeRoomDetail = "방장이 나가면 방이 닫히고 모두 로비로 돌아가요."
    static let leaveRoomTitle = "방에서 나갈까요?"
    static let leaveRoomDetail = "판이 시작되기 전이라 루비는 그대로예요."
    static let keepPlaying = "계속하기"

    static func record(games: Int?, wins: Int?) -> String {
        "판 수 \(games ?? 0) · 1등 \(wins ?? 0)"
    }

    static func stake(_ stake: Int?) -> String { "판돈 \(stake ?? 0)" }

    static func seats(_ joined: Int, max: Int) -> String { "\(joined)/\(max)명" }

    static func roomOf(_ name: String) -> String { "\(name)님의 방" }

    static func inviteFrom(_ name: String) -> String { "\(name)님이 초대했어요" }

    static func rackCount(_ count: Int?) -> String { "\(count ?? 0)장" }

    static func pool(_ count: Int?) -> String { "더미 \(count ?? 0)장" }

    static func placing(_ name: String) -> String { "\(name)님이 놓는 중" }

    static func turnOf(_ name: String) -> String { "\(name)님 차례예요" }

    static func initialProgress(_ points: Int) -> String { "첫 등록 \(points)/30점" }

    /// 로비 사람 목록 머리 — 방이 없으면 방장이 되는 법, 내가 방장이면 고르라는 말, 남의 방이면 못 한다는 말.
    static func peopleCaption(inRoom: Bool, amHost: Bool) -> String {
        guard inRoom else { return peopleCaptionNoRoom }
        return amHost ? peopleCaptionHost : peopleCaptionGuest
    }

    /// 내 차례 상태 줄(알림 `notice` 가 없을 때). 첫 등록 전에는 진행 점수(판 묶음을 건드렸으면 그 이유),
    /// 첫 등록 뒤 판을 바꿨는데 [완료]가 꺼져 있으면 꺼진 이유(§4.3 표), 아니면 끌어 놓으라는 말.
    static func myTurnStatus(_ editor: RummyTurnEditor) -> String {
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

    static func seconds(_ value: Int) -> String { "\(value)초" }

    static func clock(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    static func rank(_ rank: Int?) -> String { rank.map { "\($0)등" } ?? "—" }

    static func score(_ score: Int?) -> String {
        guard let score else { return "점수 —" }
        return score > 0 ? "점수 +\(score)" : "점수 \(score)"
    }

    static func net(_ value: Int) -> String {
        value > 0 ? "+\(value)" : (value < 0 ? "−\(-value)" : "0")
    }

    static func timeouts(_ streak: Int) -> String { "시간 초과 \(streak)/3" }

    /// 등수별 분배 표(설계서 §0 결정 — 2인 [2,0] · 3인 [2,1,0] · 4인 [3,1,0,0] × 판돈). 안내 글자 전용이다 —
    /// 실제 분배는 서버 `rummy_payouts` 가 정하고 결과 화면은 서버 값(`payout`)만 쓴다.
    static let splitTable: [Int: [Int]] = [2: [2, 0], 3: [2, 1, 0], 4: [3, 1, 0, 0]]

    static func split(seatCount: Int?, stake: Int?) -> String {
        guard let seatCount, let stake, let shares = splitTable[seatCount] else { return "" }
        return shares.enumerated().filter { $0.element > 0 }
            .map { "\($0.offset + 1)등 \($0.element * stake)" }.joined(separator: " · ")
    }

    static func endReason(_ reason: RummyEndReason?, winner: String?) -> String {
        switch reason {
        case .rackEmpty: return winner.map { "\($0)님이 랙을 비웠어요" } ?? "랙을 비운 사람이 나왔어요"
        case .blocked: return "더미가 비고 모두 넘겨서 끝났어요"
        case .lastStanding: return winner.map { "\($0)님 혼자 남아 끝났어요" } ?? "혼자 남아 끝났어요"
        case .unknown, nil: return "판이 끝났어요"
        }
    }

    static func lastEvent(_ event: RummyLastEvent?, name: String?) -> String? {
        guard let event, let kind = event.kind, let name else { return nil }
        switch kind {
        case "play": return "\(name)님이 \(event.count ?? 0)장 냈어요"
        case "draw": return "\(name)님이 1장 뽑았어요"
        case "pass": return "\(name)님이 넘겼어요"
        case "timeout_play": return "\(name)님 시간 초과 — 놓던 판으로 확정"
        // v3(R-19 v1.3): 바꿨는데 틀린 시간 초과도 되돌리고 1장 — 서버가 count 1 을 보낸다(옛 판 기록이면 그 장수 그대로).
        case "timeout_penalty": return "\(name)님 시간 초과 — 되돌리고 \(event.count ?? 1)장 뽑음"
        case "timeout_draw": return "\(name)님 시간 초과 — 1장 뽑음"
        case "forfeit": return "\(name)님이 기권했어요"
        default: return nil
        }
    }

    /// 규칙 시트 — 예시 타일과 함께(그림은 우리 것).
    static let rules: [(title: String, detail: String, example: [String])] = [
        ("그룹", "같은 숫자, 서로 다른 색 3~4장.", ["A7", "B7", "C7"]),
        ("런", "같은 색으로 이어지는 숫자 3장 이상(13 다음 1로는 안 이어져요).", ["C3", "C4", "C5", "C6"]),
        ("첫 등록", "내 랙의 타일만으로 만든 새 묶음 합이 30점 이상이어야 해요. 그 전엔 판 묶음을 건드릴 수 없어요.",
         ["B10", "C10", "D10"]),
        ("조커", "아잉이 타일은 어떤 숫자·색으로도 쓰여요. 판의 조커를 가져오면 이번 차례에 판에 다시 써야 해요.",
         ["A5", "J", "A7"]),
        ("판 조작", "첫 등록 뒤엔 판의 묶음을 나누고 합치고 옮겨도 돼요. 끝날 때 모든 묶음이 맞고 내 타일을 1장 이상 "
            + "냈어야 해요. 판에 있던 타일은 랙으로 가져올 수 없어요.", []),
        ("조작", "끌면 한 장 · 0.5초 길게 눌러 끌면 덩어리(판에선 누른 타일에서 가까운 끝까지) · 묶음 왼쪽 손잡이로 묶음째 "
            + "옮기기 · 묶음 끝 가까이 놓으면 붙기 · 묶음 위에 놓으면 맞는 자리에 끼우기 · 묶음 가운데를 빼면 둘로 나뉘어요.", []),
        // 0.3.70 통합: 받침대 손맛(끼워 넣기 · 랙 묶음 밑줄 · 정렬 유지)도 규칙 창 한 곳에서 — 2열 격자의 빈칸을 채운다.
        ("받침대", "타일 사이에 놓으면 끼워 넣고 오른쪽을 밀어요. 딱 붙여 놓은 맞는 묶음엔 밑줄과 점수가 떠요. "
            + "777·789로 정렬해 두면 새로 뽑은 타일도 그 정렬 자리로 들어가요.", []),
        ("시간 60초", "시간이 지나면 놓던 판이 맞으면 그대로 확정돼요. 틀렸거나 아무것도 안 놓았으면 되돌리고 1장 뽑아요. "
            + "시간 초과가 3번 이어지면 기권이에요.", []),
        ("끝과 점수", "누군가 랙을 비우면 끝나요(더미가 비고 모두 넘겨도 끝). 남은 타일 합만큼 잃고(아잉이 30점), "
            + "이긴 사람이 그만큼 얻어요.", ["D12", "J"]),
        ("등수 분배", "판돈 × 2명 2·0 · 3명 2·1·0 · 4명 3·1·0·0. 기권은 꼴찌예요. 새로 생기는 루비는 없어요.", []),
    ]
}

/// 로비 왼쪽 열의 탭.
enum RummyLobbyTab: Equatable { case users, ranking }

/// 렌더 시험이 띄우는 덮개.
enum RummyPreviewOverlay: Equatable { case rules, confirmLeave, closeForfeit, finalBoard, outdatedExpanded }

/// 한 장면에 그릴 값 — 스토어 또는 렌더 주입구에서 한 번에 모은다.
struct RummyScene {
    var phase: RummyStore.Phase
    var availability: RummyStore.Availability
    var lobby: RummyLobby?
    var match: RummyMatchState?
    var editor: RummyTurnEditor?
    var isMyTurn: Bool
    var otherDraft: [[RummyFace]]?
    var notice: String?
    var isWorking: Bool
    var ranking: RummyRanking?
    var myUserID: UUID?
    /// 렌더 시험의 고정 시각(nil = 실제 시계).
    var fixedNow: Date?
    var isPreview: Bool
    /// 마지막으로 안 내 루비 잔액(스토어 `rubyBalance` — 판 중에도 남는다). nil 이면 로비 `me.ruby_balance`.
    var rubyBalance: Int? = nil

    /// 머리글 💎 칸 — 판 중엔 로비가 없어도(렌더·늦은 로비) 스토어가 마지막으로 안 잔액을 보인다.
    var shownRubyBalance: Int? { rubyBalance ?? lobby?.me?.rubyBalance }

    var mySeat: RummyMatchSeat? {
        guard let match, let mine = match.mySeatNo else { return nil }
        return match.seats?.first { $0.seatNo == mine }
    }

    var turnSeat: RummyMatchSeat? {
        guard let match, let turn = match.turnSeatNo else { return nil }
        return match.seats?.first { $0.seatNo == turn }
    }

    /// 내 방 — 들고 있는 forming 판 state 가 먼저, 없으면 로비 me.room(`RummyStore.shownRoom` 한 곳이 정한다).
    /// 로비 me.room 만 보면 만들기·참가·초인종이 phase 를 방으로 바꿔도 30초 로비 폴링까지 '방 만들기' 카드에 머문다.
    /// 내가 방장인가는 방장 id 와 내 id(세션) 또는 판 state 의 내 자리로 가린다.
    var myRoom: RummyRoom? { RummyStore.shownRoom(match: match, lobby: lobby) }

    var amHost: Bool {
        if let match, let hostID = match.hostId, let mySeat { return mySeat.userId == hostID }
        guard let hostID = myRoom?.host?.id, let myUserID else { return false }
        return hostID == myUserID
    }

    /// 남의 차례에 보일 판 — 그 사람 작업 판, 없으면 확정 판.
    var othersBoard: [[RummyFace]] { otherDraft ?? match?.table ?? [] }

    /// 앵커 없는 자리의 B 배치 방위(반응 말풍선 기본 자리).
    func compass(of seatNo: Int) -> RummySeatCompass {
        RummySeatCompass.of(seatNo: seatNo, mySeatNo: match?.mySeatNo,
                            seatNos: (match?.seats ?? []).compactMap(\.seatNo))
    }

    func name(of seatNo: Int?) -> String? {
        guard let seatNo, let seat = match?.seats?.first(where: { $0.seatNo == seatNo }) else { return nil }
        return seat.displayName ?? "?"
    }
}

// MARK: - 창 루트

struct RummyPanel: View {
    let store: RummyStore
    /// 내 얼굴을 읽는 문(앱 배선이 WorkTimerStore 에서 읽는다 — 체스·테트리스와 같은 얼굴 값).
    var me: @MainActor () -> ChessPlayerFace = { ChessPlayerFace.fallback }
    /// 사람 아바타의 캐릭터 한 표를 읽는 곳. nil 이면 이니셜로 떨어진다.
    var safety: WorkTimerStore? = nil
    /// 스냅샷 전용: 목록을 ScrollView 대신 클립으로 그린다(ImageRenderer 는 ScrollView 안을 못 그린다). 앱은 false.
    var clipsOverflowInsteadOfScroll: Bool = false
    /// 스냅샷 전용 주입구(앱은 전부 nil).
    var previewPhase: RummyStore.Phase? = nil
    var previewLobby: RummyLobby? = nil
    var previewMatch: RummyMatchState? = nil
    var previewEditor: RummyTurnEditor? = nil
    var previewRanking: RummyRanking? = nil
    var previewNow: Date? = nil
    var previewNotice: String? = nil
    var previewMyUserID: UUID? = nil
    var previewLobbyTab: RummyLobbyTab? = nil
    var previewOverlay: RummyPreviewOverlay? = nil
    /// 스냅샷 전용: 이 타일을 이 자리(판 화면 좌표)로 끌고 있는 장면.
    var previewDrag: RummyPreviewDrag? = nil
    /// 스냅샷 전용: 이 반응 말풍선들을 띄운 장면(2판 ⑧).
    var previewReactions: [RummyReactionBubble]? = nil
    /// 스냅샷 전용: 머리글 루비 잔액(스토어가 마지막으로 안 값 자리).
    var previewRubyBalance: Int? = nil

    @State private var lobbyTab: RummyLobbyTab = .users
    @State private var confirmLeave = false
    /// 방 없이 누른 [초대] · [한 판 더] 의 부를 사람 줄(2판 — 방이 서면 한 사람씩 초대).
    @State private var inviteQueue = RummyInviteQueue()
    /// 창 닫기 확인(창 컨트롤러가 환경으로 준다 — 렌더·시험은 없다).
    @Environment(RummyExitPrompt.self) private var exitPrompt: RummyExitPrompt?

    private var isPreview: Bool {
        previewPhase != nil || previewLobby != nil || previewMatch != nil || previewEditor != nil
    }

    private var activeTab: RummyLobbyTab { previewLobbyTab ?? lobbyTab }

    private var sessionUserID: UUID? {
        safety?.session.flatMap { UUID(uuidString: $0.userID) }
    }

    /// 한 장면의 값. 주입구가 하나라도 있으면 주입 값으로만 그린다(스토어 값과 섞지 않는다).
    private var scene: RummyScene {
        if isPreview {
            let match = previewMatch
            let phase = previewPhase ?? Self.phase(for: match)
            let mine = match?.mySeatNo
            let myTurn = match?.status == .active && mine != nil && match?.turnSeatNo == mine
            return RummyScene(
                phase: phase, availability: .available, lobby: previewLobby, match: match, editor: previewEditor,
                isMyTurn: myTurn, otherDraft: myTurn ? nil : match?.draft?.table, notice: previewNotice,
                isWorking: false, ranking: previewRanking, myUserID: previewMyUserID, fixedNow: previewNow,
                isPreview: true, rubyBalance: previewRubyBalance)
        }
        return RummyScene(
            phase: store.phase, availability: store.availability, lobby: store.lobby, match: store.match,
            editor: store.editor, isMyTurn: store.isMyTurn, otherDraft: store.otherDraft, notice: store.notice,
            isWorking: store.isWorking, ranking: store.ranking, myUserID: sessionUserID, fixedNow: nil,
            isPreview: false, rubyBalance: store.rubyBalance ?? store.host?.rubyBalance)
    }

    /// 주입된 판 state 의 status 로 화면을 고른다(렌더 전용 — 앱은 스토어 phase 가 정한다).
    static func phase(for match: RummyMatchState?) -> RummyStore.Phase {
        switch match?.status {
        case .forming: return .room
        case .active: return .playing
        case .finished: return .finished
        default: return .lobby
        }
    }

    var body: some View {
        let scene = scene
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: RummyWindowLayout.headerSpacing) {
                // 0.3.70: 판 화면은 머리글을 판의 위 띠로 옮긴다(판 칸이 머리글 높이만큼 커진다 — `matchBodyHeight`).
                if !Self.isMatchScreen(scene) {
                    RummyHeader(scene: scene, onRules: { store.rulesShown = true },
                                onForfeit: { confirmLeave = true },
                                reactionButton: scene.match == nil ? nil : RummyReactionButton(store: store))
                        .frame(height: RummyWindowLayout.headerHeight)
                }
                content(scene)
                    .frame(width: RummyWindowLayout.innerWidth,
                           height: Self.isMatchScreen(scene) ? RummyWindowLayout.matchBodyHeight : RummyWindowLayout.bodyHeight,
                           alignment: .topLeading)
            }
            .padding(RummyWindowLayout.contentPadding)
            // 반응 말풍선 — 자리 앵커(`rummyReactionAnchor`) 위에, 덮개들 아래.
            .rummyReactionLayer(bubbles: reactionBubbles, compass: { scene.compass(of: $0) }, fixedNow: scene.fixedNow)
            // 덮개는 한 번에 하나.
            if let decision = exitPrompt?.pending ?? (previewOverlay == .closeForfeit ? .confirmForfeit : nil) {
                RummyExitConfirmOverlay(decision: decision, onConfirm: { exitPrompt?.confirm() },
                                        onCancel: { exitPrompt?.cancel() })
            } else if store.rulesShown || previewOverlay == .rules {
                RummyRulesOverlay(onClose: { store.rulesShown = false })
            } else if confirmLeave || previewOverlay == .confirmLeave {
                RummyConfirmOverlay(scene: scene,
                                    onConfirm: { confirmLeave = false; store.leave() },
                                    onCancel: { confirmLeave = false })
            }
        }
        .frame(width: RummyWindowLayout.contentSize.width, height: RummyWindowLayout.contentSize.height,
               alignment: .topLeading)
        .background(CheckTheme.background)
        .foregroundStyle(CheckTheme.primaryText)
        // 툴팁 말풍선 레이어 — 창 루트 하나(새 창 루트에는 이 한 줄이 반드시 있어야 말풍선이 뜬다).
        .checkTooltipLayer()
        // 사람 아바타의 캐릭터 한 표. nil 이면 빈 표 = 모르는 사람은 착용값·그마저 없으면 이니셜.
        .appUserAvatarCharacters(from: safety)
        // 기권·나가기 확인은 **그 화면에서 연 것**만 산다.
        .onChange(of: store.phase) { _, _ in confirmLeave = false; exitPrompt?.cancel() }
        .rummyInviteQueue(inviteQueue, store: store)
        .onChange(of: store.match?.id) { _, _ in confirmLeave = false }
        .onChange(of: lobbyTab) { _, tab in
            if tab == .ranking { store.refreshRanking() }
        }
    }

    private var reactionBubbles: [RummyReactionBubble] {
        if isPreview { return previewReactions ?? [] }
        return store.reactionFeed.map(RummyReactionBubble.init)
    }

    /// 판 화면(머리글 없이 본문이 창을 채운다)인가 — `content` 가 `RummyMatchView` 를 그리는 조건과 같다.
    static func isMatchScreen(_ scene: RummyScene) -> Bool {
        scene.phase == .playing && scene.match != nil
    }

    private func lobby(_ scene: RummyScene) -> RummyLobbyView {
        RummyLobbyView(store: store, scene: scene, tab: activeTab, onSelectTab: { lobbyTab = $0 },
                       onLeaveRoom: { confirmLeave = true },
                       clipsOverflowInsteadOfScroll: clipsOverflowInsteadOfScroll, me: me(),
                       calling: inviteQueue.pending, onInvite: { inviteQueue.invite($0, store: store) },
                       showsOutdated: previewOverlay == .outdatedExpanded)
    }

    @ViewBuilder
    private func content(_ scene: RummyScene) -> some View {
        switch scene.phase {
        case .lobby, .room:
            lobby(scene)
        case .playing:
            if let match = scene.match {
                RummyMatchView(store: store, scene: scene, match: match, me: me(),
                               clipsOverflowInsteadOfScroll: clipsOverflowInsteadOfScroll,
                               previewDrag: previewDrag, onForfeit: { confirmLeave = true })
            } else {
                lobby(scene)
            }
        case .finished:
            if let match = scene.match {
                RummyResultView(store: store, scene: scene, match: match,
                                onPlayAgain: { inviteQueue.createAndInvite($0, store: store) },
                                startsWithBoard: previewOverlay == .finalBoard)
            } else {
                lobby(scene)
            }
        }
    }
}

// MARK: - 머리글

private struct RummyHeader: View {
    let scene: RummyScene
    let onRules: () -> Void
    let onForfeit: () -> Void
    var reactionButton: RummyReactionButton? = nil

    var body: some View {
        HStack(spacing: 12) {
            RummyTileView(face: .joker, size: .table)
                .scaleEffect(0.82)
                .frame(width: 34, height: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(RummyText.title).font(.title3.weight(.bold))
                Text(RummyText.subtitle)
                    .font(.caption)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            if scene.phase == .playing || scene.phase == .finished, let match = scene.match {
                HStack(spacing: 5) {
                    RubyIcon(size: 13)
                    Text(RummyText.stake(match.stake)).monospacedDigit()
                }
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(Capsule().fill(Color.white.opacity(0.06)))
                .overlay(Capsule().stroke(CheckTheme.border, lineWidth: 1))
            } else {
                HStack(spacing: 5) {
                    Image(systemName: "flag.checkered")
                    Text(RummyText.record(games: scene.lobby?.me?.games, wins: scene.lobby?.me?.wins)).monospacedDigit()
                }
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(Capsule().fill(Color.white.opacity(0.06)))
                .overlay(Capsule().stroke(CheckTheme.border, lineWidth: 1))
            }
            RubyBalanceChip(balance: scene.shownRubyBalance, large: true)
                .checkTooltip("내 루비")
            if let reactionButton { reactionButton }
            TetrisDuelActionButton(title: RummyText.rulesButton, icon: "book.fill", style: .outline,
                                   height: 30, action: onRules)
            if scene.phase == .playing, scene.mySeat?.state == .playing {
                TetrisDuelActionButton(title: RummyText.forfeit, icon: "flag.fill", tint: CheckTheme.danger,
                                       style: .outline, height: 30, action: onForfeit)
            }
        }
    }
}

// MARK: - 남은 시간 잎 뷰

/// 남은 초 — **잎 뷰**만 시계를 읽는다. `fixedNow` 가 있으면(렌더 시험) 그 시각으로 한 번만 그린다.
struct RummyCountdownLeaf: View {
    let remaining: (Date) -> TimeInterval?
    let fixedNow: Date?
    let label: (Int) -> String
    var urgentBelow: Int = 10
    /// 색 문턱을 직접 줄 때(0.3.70 — 자리 카드 초는 [완료] 안 초·차례 링과 같은 문턱: 10초 이하 주황, 5초 이하 빨강).
    var tint: ((Int) -> Color?)? = nil

    var body: some View {
        if let fixedNow {
            text(at: fixedNow)
        } else {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                text(at: context.date)
            }
        }
    }

    @ViewBuilder
    private func text(at date: Date) -> some View {
        if let left = remaining(date) {
            let seconds = max(0, Int(left.rounded(.up)))
            Text(label(seconds))
                .monospacedDigit()
                .foregroundStyle(tint.map { $0(seconds) ?? CheckTheme.primaryText }
                    ?? (seconds <= urgentBelow ? CheckTheme.danger : CheckTheme.primaryText))
        }
    }
}

extension RummyScene {
    /// 차례 남은 초 — 앱은 스토어(서버 시계 보정), 렌더는 주입 state 의 마감과 고정 시각.
    @MainActor
    func turnRemaining(_ store: RummyStore) -> (Date) -> TimeInterval? {
        if isPreview {
            let deadline = match?.turnDeadlineMs
            return { date in deadline.map { $0 / 1000 - date.timeIntervalSince1970 } }
        }
        return { date in store.turnRemaining(at: date) }
    }

    /// 방 남은 시간 — 같은 갈래.
    @MainActor
    func roomRemaining(_ store: RummyStore) -> (Date) -> TimeInterval? {
        if isPreview {
            let expires = myRoom?.expiresAtMs ?? match?.expiresAtMs
            return { date in expires.map { $0 / 1000 - date.timeIntervalSince1970 } }
        }
        return { date in store.roomRemaining(at: date) }
    }
}

// MARK: - 덮개

private struct RummyOverlayScrim<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            CheckTheme.panelElevated.opacity(0.94)
            content
        }
        .frame(width: RummyWindowLayout.contentSize.width, height: RummyWindowLayout.contentSize.height)
    }
}

/// 규칙 시트 — 그룹·런·첫 등록·조커·판 조작·조작·받침대·시간·끝과 점수·등수 분배를 예시 타일로.
private struct RummyRulesOverlay: View {
    let onClose: () -> Void

    var body: some View {
        RummyOverlayScrim {
            VStack(alignment: .leading, spacing: 12) {
                Text(RummyText.rulesTitle).font(.headline)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 16, alignment: .top),
                                    GridItem(.flexible(), spacing: 16, alignment: .top)],
                          alignment: .leading, spacing: 12) {
                    ForEach(RummyText.rules, id: \.title) { rule in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(rule.title).font(.callout.weight(.bold)).foregroundStyle(CheckTheme.accent)
                                Text(rule.detail)
                                    .font(.caption)
                                    .foregroundStyle(CheckTheme.secondaryText)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            if !rule.example.isEmpty {
                                HStack(spacing: 2) {
                                    ForEach(Array(rule.example.enumerated()), id: \.offset) { _, text in
                                        if let face = RummyFace(text: text) {
                                            RummyTileView(face: face, size: .table)
                                        }
                                    }
                                }
                                .padding(5)
                                .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(Color.white.opacity(0.06)))
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.04)))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(CheckTheme.border, lineWidth: 1))
                    }
                }
                TetrisDuelActionButton(title: RummyText.close, style: .outline, height: 32, fullWidth: true,
                                       action: onClose)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(22)
            .frame(width: 980, alignment: .leading)
            .tetrisDuelCard(padding: 0)
        }
    }
}

/// 기권·나가기 확인 — 판이면 기권, 방이면 (방장) 방 닫기 / 나가기.
private struct RummyConfirmOverlay: View {
    let scene: RummyScene
    let onConfirm: () -> Void
    let onCancel: () -> Void

    private var copy: (title: String, detail: String, button: String) {
        if scene.phase == .playing { return (RummyText.forfeitTitle, RummyText.forfeitDetail, RummyText.forfeit) }
        if scene.amHost { return (RummyText.closeRoomTitle, RummyText.closeRoomDetail, RummyText.leave) }
        return (RummyText.leaveRoomTitle, RummyText.leaveRoomDetail, RummyText.leave)
    }

    var body: some View {
        RummyOverlayScrim {
            VStack(alignment: .leading, spacing: 12) {
                Text(copy.title).font(.headline)
                Text(copy.detail)
                    .font(.callout)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    TetrisDuelActionButton(title: RummyText.keepPlaying, style: .outline, height: 34, fullWidth: true,
                                           action: onCancel)
                        .keyboardShortcut(.cancelAction)
                    TetrisDuelActionButton(title: copy.button, tint: CheckTheme.danger, height: 34, fullWidth: true,
                                           action: onConfirm)
                }
            }
            .padding(22)
            .frame(width: 400, alignment: .leading)
            .tetrisDuelCard(padding: 0)
        }
    }
}

// MARK: - 공용 조각

/// 스크롤 칸. 스냅샷에서는 **클립 갈래**로 그린다 — ImageRenderer 는 ScrollView 안을 못 그린다.
struct RummyScrollBox<Content: View>: View {
    var axis: Axis.Set = .vertical
    let clips: Bool
    @ViewBuilder let content: Content

    var body: some View {
        if clips {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
        } else {
            ScrollView(axis, showsIndicators: false) {
                content.frame(maxWidth: axis == .vertical ? .infinity : nil, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

/// 작은 상태 칩.
struct RummyChip: View {
    let text: String
    var tint: Color = CheckTheme.secondaryText

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold))
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .frame(height: 18)
            .background(Capsule().fill(tint.opacity(0.14)))
            .overlay(Capsule().stroke(tint.opacity(0.4), lineWidth: 1))
    }
}
