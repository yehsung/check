import Foundation
import Testing
@testable import check

// v0.3.28 — 1:1 오목 **대국 채팅** 코어(모델·서비스·스토어) 계약.
//
// 관례는 V0327GomokuStoreTests 그대로다: 호스트별 스텁(테스트마다 고유 호스트라 병렬 스위트가 서로의 기록·응답을
// 안 덮는다) · 대기 상한은 벽시계가 아니라 **재개 횟수** · `WorkTimerStore` 를 `_` 로 버리지 않는다(오목 스토어가
// 약참조라 해제되면 요청이 한 건도 안 나간다) · UserDefaults 스위트는 `.gomokuDefaultsCleanup` 이 지운다.
//
// 여기서 지키는 것은 다섯이다:
//  ① 채팅은 `isBusy` 를 쓰지 않는다 — 채팅 왕복이 착수·기권을 잠그면 한 수 30초짜리 판에서 그건 곧 패배다.
//  ② 실패해도 자동 재전송하지 않고, 초안은 **성공했을 때만** 비운다.
//  ③ 늦게 온 응답과 구멍은 착수와 같은 겹으로 막는다(번호 역행은 버리고, 구멍은 since 0 으로 한 번 전체 재요청).
//  ④ 상대가 껐거나 옛 버전이면 **앱이 말한다** — 조용히 삼키지 않는다.
//  ⑤ 판이 바뀌면 대화·초안·음소거를 비운다.
//
// 스텁이 못 잡는 것(서버 정규화·실제 배달·음소거된 상대 화면)은 통합자의 두 계정 e2e 몫이다.

// MARK: - 픽스처

private let me = "00000000-0000-0000-0000-0000000000a1"
private let rival = "00000000-0000-0000-0000-0000000000b2"
private let matchID = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
private let otherMatchID = "11112222-3333-4444-5555-666677778888"

private func jsonText(_ object: Any) -> String {
    String(decoding: try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
}

private func nowMs() -> Double { Date().timeIntervalSince1970 * 1000 }

private func bodyValue(_ body: String, _ key: String) -> Any? {
    ((try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? [String: Any])?[key]
}

private func sinceChat(_ body: String) -> Int? { bodyValue(body, "p_since_chat_seq") as? Int }

/// 서버 `chat[]` 한 줄.
private func chatRow(
    _ seq: Int, _ body: String, mine: Bool = false, kind: String = "text", createdMs: Double? = nil
) -> [String: Any] {
    ["seq": seq, "kind": kind, "body": body, "mine": mine, "created_ms": createdMs ?? nowMs()]
}

/// gomoku_state 의 ok 묶음. 채팅 키는 **넣을 때만** 실린다 — 안 실은 응답(채팅을 모르는 서버)도 그대로 디코드돼야 한다.
private func statePayload(
    id: String = matchID,
    matchStatus: String = "active",
    myColor: String = "black",
    turn: String? = "black",
    moveCount: Int = 0,
    chat: [[String: Any]]? = nil,
    chatSeq: Int? = nil,
    myMuted: Bool? = nil,
    opponentMuted: Bool? = nil,
    chatCapable: Bool? = nil,
    chatMaxLen: Int? = nil,
    serverNowMs: Double? = nil
) -> [String: Any] {
    var payload: [String: Any] = [
        "status": "ok",
        "match": [
            "id": id,
            "status": matchStatus,
            "stake": 5,
            "black": myColor == "black" ? me : rival,
            "white": myColor == "black" ? rival : me,
            "challenger": rival,
            "opponent": me,
            "move_count": moveCount,
            "turn": turn ?? NSNull(),
            "deadline_ms": NSNull(),
            "result": matchStatus == "finished" ? "white_win" : NSNull(),
            "end_reason": matchStatus == "finished" ? "resign" : NSNull(),
            "winner": NSNull(),
            "invite_expires_ms": NSNull()
        ],
        "moves": [],
        "my_color": myColor,
        "opponent": ["user_id": rival, "display_name": "라이벌", "avatar_url": NSNull(), "character": "aing"],
        "ruby_balance": NSNull(),
        "server_now_ms": serverNowMs ?? NSNull()
    ]
    if let chat { payload["chat"] = chat }
    if let chatSeq { payload["chat_seq"] = chatSeq }
    if let myMuted { payload["my_muted"] = myMuted }
    if let opponentMuted { payload["opponent_muted"] = opponentMuted }
    if let chatCapable { payload["chat_capable"] = chatCapable }
    if let chatMaxLen { payload["chat_max_len"] = chatMaxLen }
    return payload
}

private func reply(_ object: [String: Any], delay: TimeInterval = 0) -> GomokuStubProtocol.Reply {
    GomokuStubProtocol.Reply(body: jsonText(object), delay: delay)
}

private func decodePayload(_ object: [String: Any]) -> GomokuStatePayload {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try! decoder.decode(GomokuStatePayload.self, from: Data(jsonText(object).utf8))
}

@MainActor
private func makeChatStore(
    _ label: String,
    handler: @escaping GomokuStubProtocol.Handler = { _, _, _ in nil }
) -> (WorkTimerStore, GomokuStore, String) {
    let host = "v0328-c-\(label)-\(UUID().uuidString.prefix(8))".lowercased()
    GomokuStubProtocol.register(host: host, handler: handler)
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!,
        anonKey: "anon-test-key",
        session: GomokuStubProtocol.session()
    )
    let defaults = GomokuTestDefaults.make("v0328-chat")
    let store = WorkTimerStore(
        service: service,
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: defaults,
        workspaceNotifications: nil
    )
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: me)
    ChatTestRetention.stores.append(store)
    return (store, store.gomoku, host)
}

/// 오목 스토어는 WorkTimerStore 를 **약참조**한다 — 튜플에서 버리면 곧바로 해제되어 요청이 한 건도 안 나간다.
@MainActor
private enum ChatTestRetention {
    static var stores: [WorkTimerStore] = []
}

/// 상한은 벽시계가 아니라 **재개 횟수**다(5ms 한 번 = 한 차례). 전체 스위트에서는 렌더 테스트가 메인 액터를
/// 수십 초씩 쥐어, 벽시계 상한이 스토어의 Task 가 차례를 받기도 전에 끝난다.
@MainActor
private func chatWait(_ timeout: TimeInterval = 60, _ condition: @MainActor () -> Bool) async {
    for _ in 0..<Int(timeout * 200) {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
}

private let diagnosticWords = [
    "서버", "상태", "동기화", "토큰", "세션", "RPC", "status", "_", "오류", "에러", "unknown", "실패", "stale"
]

private let allStatuses: [GomokuRPCStatus] = [
    .ok, .unauthorized, .unsupportedClient, .invalid, .blackout, .notWorking, .targetNotWorking, .targetFocused,
    .targetOutdated, .busy, .targetBusy, .alreadyPending, .insufficient, .notFound, .notPending, .expired, .notActive,
    .timeout, .notYourTurn, .stale, .forbidden, .flood, .unknown
]

// MARK: - 1. 본문 모양 · 문구 표

@Test(.gomokuDefaultsCleanup)
func 채팅_RPC_둘은_p_protocol_2_와_p_snake_키를_싣는다() async throws {
    #expect(GomokuWire.protocolVersion == 2, "채팅 게이트(gomoku_chat_protocol)가 2 다")
    let host = "v0328-c-shape-\(UUID().uuidString.prefix(8))".lowercased()
    GomokuStubProtocol.register(host: host) { _, _, _ in GomokuStubProtocol.Reply(body: #"{"status":"ok"}"#) }
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!, anonKey: "anon-test-key", session: GomokuStubProtocol.session())

    _ = try await service.gomokuChatSend(accessToken: "t", matchID: matchID, kind: .quick, body: "gg")
    _ = try await service.gomokuChatMute(accessToken: "t", matchID: matchID, muted: true)
    _ = try await service.gomokuState(accessToken: "t", matchID: matchID, sinceSeq: 4, sinceChatSeq: 7)

    let send = try #require(GomokuStubProtocol.calls(host: host, rpc: "gomoku_chat_send").first).json
    #expect(Set(send.keys) == ["p_protocol", "p_match_id", "p_kind", "p_body"])
    #expect(send["p_protocol"] as? Int == 2)
    #expect(send["p_match_id"] as? String == matchID)
    // 빠른 문구는 **코드**가 간다(한국어 문구는 앱만 갖는다).
    #expect(send["p_kind"] as? String == "quick" && send["p_body"] as? String == "gg")

    let mute = try #require(GomokuStubProtocol.calls(host: host, rpc: "gomoku_chat_mute").first).json
    #expect(Set(mute.keys) == ["p_protocol", "p_match_id", "p_muted"])
    #expect(mute["p_muted"] as? Bool == true && mute["p_protocol"] as? Int == 2)

    let state = try #require(GomokuStubProtocol.calls(host: host, rpc: "gomoku_state").first).json
    #expect(Set(state.keys) == ["p_protocol", "p_match_id", "p_since_seq", "p_since_chat_seq"])
    #expect(state["p_since_seq"] as? Int == 4 && state["p_since_chat_seq"] as? Int == 7)
}

@Test(.gomokuDefaultsCleanup)
func 채팅_응답은_status_만_필수이고_모르는_status_는_접는다() throws {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let bare = try decoder.decode(GomokuChatResponse.self, from: Data(#"{"status":"ok"}"#.utf8))
    #expect(bare.status == .ok)
    #expect(bare.chatSeq == nil && bare.opponentMuted == nil && bare.muted == nil)
    let widened = try decoder.decode(GomokuChatResponse.self, from: Data(#"{"status":"brand_new"}"#.utf8))
    #expect(widened.status == .unknown)
    #expect(throws: (any Error).self) {
        try decoder.decode(GomokuChatResponse.self, from: Data(#"{"chat_seq":3}"#.utf8))
    }
    // 채팅 키가 없는 상태 묶음(채팅을 모르는 0.3.27 서버)도 그대로 디코드된다 — 창이 죽지 않는다.
    let old = decodePayload(statePayload())
    #expect(old.chat == nil && old.chatSeq == nil && old.chatCapable == nil)
    let fresh = decodePayload(statePayload(chat: [chatRow(1, "안녕")], chatSeq: 1, myMuted: true, chatCapable: false))
    #expect(fresh.chat?.count == 1 && fresh.chatSeq == 1)
    #expect(fresh.myMuted == true && fresh.chatCapable == false)
    #expect(fresh.chat?.first?.createdMs != nil, "시각은 epoch 밀리초 Double 로 읽는다")
}

@Test(.gomokuDefaultsCleanup)
func 채팅_안내는_사용자_어휘이고_도배는_카운트다운_없이_접힌다() {
    #expect(GomokuNoticeText.chat(.ok) == nil, "성공은 글이 뜨는 것으로 답한다")
    #expect(GomokuNoticeText.chatMute(.ok) == nil)
    #expect(GomokuNoticeText.chat(.flood) == GomokuNoticeText.chat(.invalid), "도배는 invalid 와 같은 한 줄이다")
    #expect(GomokuNoticeText.chat(.notActive) == GomokuNoticeText.finishedMatch)
    #expect(GomokuNoticeText.chat(.notFound) == GomokuNoticeText.finishedMatch)
    #expect(GomokuNoticeText.chat(.unsupportedClient) == GomokuNoticeText.updateMine)
    #expect(GomokuNoticeText.chat(.unauthorized) == GomokuNoticeText.signInAgain)
    #expect(GomokuNoticeText.chatTooLong(100) == "채팅은 100자까지예요")
    #expect(GomokuNoticeText.chatTooLong(80) == "채팅은 80자까지예요", "숫자는 거절한 쪽이 말한 값이다")
    #expect(GomokuNoticeText.chatOpponentOutdated == "상대는 옛 버전이라 채팅을 못 받아요")
    #expect(GomokuNoticeText.chatMutedByOpponent == "상대가 채팅을 껐어요")
    #expect(GomokuNoticeText.chatMutedByMe == "상대 말을 껐어요")

    var texts = [
        GomokuNoticeText.chatMutedByMe, GomokuNoticeText.chatMutedByOpponent, GomokuNoticeText.chatOpponentOutdated,
        GomokuNoticeText.chatUnknownQuick, GomokuNoticeText.chatTooLong(100)
    ]
    for status in allStatuses {
        texts.append(contentsOf: [GomokuNoticeText.chat(status), GomokuNoticeText.chatMute(status)].compactMap { $0 })
    }
    for text in texts {
        #expect(!text.isEmpty)
        for word in diagnosticWords {
            #expect(!text.contains(word), "안내 문구에 진단 어휘 '\(word)': \(text)")
        }
        // 남은 초를 세면 그건 이름만 다른 쿨타임이다(메시지에서 없앤 바로 그것).
        #expect(!text.contains("초 "), "카운트다운 어휘: \(text)")
        #expect(!text.contains("초 뒤"), "카운트다운 어휘: \(text)")
    }
}

@Test(.gomokuDefaultsCleanup)
func 빠른_문구_여덟은_코드와_한국어가_일대일이다() {
    #expect(GomokuQuickPhrase.allCases.count == 8)
    #expect(Set(GomokuQuickPhrase.allCases.map(\.rawValue))
        == ["hi", "gg", "nice", "hurry", "sorry", "think", "oops", "rematch"])
    #expect(GomokuQuickPhrase.hi.text == "안녕하세요")
    #expect(GomokuQuickPhrase.rematch.text == "한 판 더 할까요?")
    let texts = GomokuQuickPhrase.allCases.map(\.text)
    #expect(Set(texts).count == 8, "같은 문구가 두 코드에 붙으면 상대는 어느 쪽인지 알 수 없다")
    for text in texts {
        #expect(!text.isEmpty)
        #expect(!text.contains("_"))
    }
}

// MARK: - 2. 증분 · 구멍 · 늦은 응답

@MainActor
@Test(.gomokuDefaultsCleanup)
func 채팅은_받은_번호부터_묻고_구멍이_나면_한_번_전체를_받는다() async {
    let (_, gomoku, host) = makeChatStore("incremental") { rpc, body, _ in
        guard rpc == "gomoku_state" else { return nil }
        if sinceChat(body) == 0 {
            return reply(statePayload(
                chat: [chatRow(1, "안녕", mine: true), chatRow(2, "반가워요"), chatRow(3, "두세요", mine: true)],
                chatSeq: 3))
        }
        // since 1 을 물었는데 2가 빠진 채 3만 온다(구멍) → 처음부터 다시 받아야 한다.
        return reply(statePayload(chat: [chatRow(3, "두세요", mine: true)], chatSeq: 3))
    }
    gomoku.applyState(decodePayload(statePayload(chat: [chatRow(1, "안녕", mine: true)], chatSeq: 1)))
    #expect(gomoku.chatSeq == 1)
    #expect(gomoku.chat.map(\.seq) == [1])

    await gomoku.refreshMatch()

    let sinces = GomokuStubProtocol.calls(host: host, rpc: "gomoku_state").map { sinceChat($0.body) }
    #expect(sinces == [1, 0], "들고 있는 번호부터 묻고, 구멍이 나면 0 으로 한 번 더 받는다")
    #expect(gomoku.chat.map(\.seq) == [1, 2, 3], "구멍 난 대화를 그리면 2번 줄이 영영 안 보인다")
    #expect(gomoku.chat.map(\.body) == ["안녕", "반가워요", "두세요"])
    #expect(gomoku.chat.map(\.isMine) == [true, false, true], "내 말·상대 말 판정은 서버가 한다")
    #expect(gomoku.chatSeq == 3)
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 음소거_중에는_번호가_건너뛰어도_구멍이_아니다() async {
    let (_, gomoku, host) = makeChatStore("muted-gap") { rpc, _, _ in
        guard rpc == "gomoku_state" else { return nil }
        // 상대 줄(2·3)은 서버가 걸러 내고 내 줄(4)만 온다 — 번호가 뛰지만 정상이다.
        return reply(statePayload(chat: [chatRow(4, "혼잣말", mine: true)], chatSeq: 4, myMuted: true))
    }
    gomoku.applyState(decodePayload(statePayload(
        chat: [chatRow(1, "안녕", mine: true)], chatSeq: 1, myMuted: true)))
    #expect(gomoku.isMuted)

    await gomoku.refreshMatch()

    #expect(GomokuStubProtocol.count(host: host, rpc: "gomoku_state") == 1, "가려진 줄을 구멍으로 읽어 다시 물었다")
    #expect(gomoku.chat.map(\.seq) == [1, 4])
    #expect(gomoku.chatSeq == 4, "다음 since 는 마지막 줄이 아니라 서버 발급 번호다")
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 번호가_역행하는_늦은_응답은_대화도_음소거도_되돌리지_못한다() {
    let (_, gomoku, _) = makeChatStore("stale-chat")
    gomoku.applyState(decodePayload(statePayload(
        chat: [chatRow(1, "안녕", mine: true), chatRow(2, "반가워요"), chatRow(3, "네")],
        chatSeq: 3, myMuted: true, opponentMuted: true, chatCapable: false)))
    #expect(gomoku.chat.count == 3)

    // 조회 → 음소거 → 음소거 응답 → 조회 응답 순서로 늦게 도착한 옛 스냅숏.
    gomoku.applyState(decodePayload(statePayload(
        chat: [chatRow(1, "안녕", mine: true)], chatSeq: 1,
        myMuted: false, opponentMuted: false, chatCapable: true)))

    #expect(gomoku.chat.map(\.seq) == [1, 2, 3], "옛 스냅숏이 대화를 잘라 냈다")
    #expect(gomoku.chatSeq == 3)
    #expect(gomoku.isMuted, "옛 스냅숏이 방금 켠 음소거를 풀었다")
    #expect(gomoku.isOpponentMuted)
    #expect(gomoku.opponentChatCapable == false)
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 채팅_키가_없는_응답은_들고_있는_대화를_지우지_않는다() {
    let (_, gomoku, _) = makeChatStore("no-chat-keys")
    gomoku.applyState(decodePayload(statePayload(chat: [chatRow(1, "안녕", mine: true)], chatSeq: 1)))
    #expect(gomoku.chat.count == 1)
    // 쓰기 RPC 가 싣는 state 묶음(gomoku__state)에는 채팅 키가 없다 — 그것을 "대화가 비었다"로 읽으면 안 된다.
    gomoku.applyState(decodePayload(statePayload(moveCount: 1)))
    #expect(gomoku.chat.map(\.seq) == [1])
    #expect(gomoku.chatSeq == 1)
}

// MARK: - 3. 보내기

@MainActor
@Test(.gomokuDefaultsCleanup)
func 실패한_채팅은_초안을_남기고_자동으로_다시_보내지_않는다() async {
    let (_, gomoku, host) = makeChatStore("send") { rpc, _, index in
        switch rpc {
        case "gomoku_chat_send":
            if index == 0 { return reply(["status": "invalid", "chat_max_len": 100]) }
            return reply(["status": "ok", "chat_seq": 1, "opponent_muted": true, "chat_capable": false,
                          "server_now_ms": nowMs()])
        case "gomoku_state":
            return reply(statePayload(chat: [chatRow(1, "안녕하세요", mine: true)], chatSeq: 1,
                                      opponentMuted: true, chatCapable: false))
        default:
            return nil
        }
    }
    gomoku.applyState(decodePayload(statePayload(chat: [], chatSeq: 0)))
    gomoku.chatDraft = "안녕하세요"
    #expect(gomoku.canSendChatNow)

    gomoku.sendChatDraft()
    await chatWait { !gomoku.isSendingChat }

    #expect(gomoku.chatDraft == "안녕하세요", "실패한 글은 사용자 것이다 — 비우지 않는다")
    #expect(gomoku.chatNotice == GomokuNoticeText.chatBlocked)
    #expect(GomokuStubProtocol.count(host: host, rpc: "gomoku_chat_send") == 1, "실패를 자동으로 다시 보냈다")
    #expect(GomokuStubProtocol.count(host: host, rpc: "gomoku_state") == 0, "실패에는 다시 읽지 않는다")
    #expect(gomoku.chat.isEmpty)

    gomoku.sendChatDraft()
    await chatWait { !gomoku.isSendingChat && !gomoku.chat.isEmpty }

    #expect(gomoku.chatDraft == "", "성공했을 때만 비운다")
    #expect(gomoku.chatNotice == nil)
    // 낙관 삽입이 아니라 서버가 정규화한 줄을 다시 받아 그린다.
    #expect(gomoku.chat.map(\.body) == ["안녕하세요"])
    #expect(gomoku.chat.first?.isMine == true)
    let body = GomokuStubProtocol.calls(host: host, rpc: "gomoku_chat_send").last?.json ?? [:]
    #expect(body["p_kind"] as? String == "text" && body["p_body"] as? String == "안녕하세요")
    // 상대가 껐다·못 받는 버전이다를 **보낸 사람이 안다**(조용히 삼키지 않는다).
    #expect(gomoku.isOpponentMuted)
    #expect(gomoku.opponentChatCapable == false)
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 채팅_전송은_착수를_잠그지_않는다() async throws {
    let (_, gomoku, host) = makeChatStore("not-busy") { rpc, _, _ in
        switch rpc {
        case "gomoku_chat_send":
            return reply(["status": "ok", "chat_seq": 1], delay: 0.4)
        case "gomoku_move":
            return reply(["status": "ok"])
        case "gomoku_state":
            return reply(statePayload(chat: [chatRow(1, "잠깐", mine: true)], chatSeq: 1))
        default:
            return nil
        }
    }
    gomoku.applyState(decodePayload(statePayload(turn: "black", chat: [], chatSeq: 0)))
    gomoku.chatDraft = "잠깐"

    gomoku.sendChatDraft()
    #expect(gomoku.isSendingChat, "전송 깃발은 누른 그 순간 선다")
    #expect(gomoku.isBusy == false, "채팅이 착수·기권 버튼을 잠갔다")
    #expect(gomoku.canSendChatNow == false, "왕복 중엔 두 번째 전송을 막는다")

    // 채팅이 도는 동안에도 수를 둘 수 있어야 한다 — 이것이 isBusy 를 안 쓰는 이유 전부다.
    await gomoku.place(GomokuPoint(x: 7, y: 7)!)
    #expect(GomokuStubProtocol.count(host: host, rpc: "gomoku_move") == 1, "채팅 때문에 착수가 막혔다")

    await chatWait { !gomoku.isSendingChat }
    #expect(gomoku.isBusy == false)

    // 배선은 소스로도 못 박는다(주석을 걷어낸 뒤 — 안 그러면 설명을 지워야만 초록이 된다).
    let code = gomokuCollapsed(V0317ShopTests.stripped(try V0317ShopTests.source("GomokuStore.swift")))
    #expect(gomokuBody(of: "private func sendChat(", in: code)?.contains("isBusy") == false)
    #expect(gomokuBody(of: "func setChatMuted(", in: code)?.contains("isBusy") == false)
    #expect(gomokuBody(of: "var canSendChatNow", in: code)?.contains("isBusy") == false)
    #expect(gomokuBody(of: "func refreshMatch(id rawID: String?)", in: code)?.contains("sinceChatSeq: sinceChat") == true)
    #expect(gomokuBody(of: "func applyState(", in: code)?.contains("applyChat(") == true)
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 채팅_길이는_코드포인트_눈금이고_상한을_넘으면_보내지_않는다() async {
    let (_, gomoku, host) = makeChatStore("length")
    gomoku.applyState(decodePayload(statePayload(chat: [], chatSeq: 0)))
    #expect(gomoku.chatMaxLength == 100)

    gomoku.chatDraft = String(repeating: "가", count: 100)
    #expect(gomoku.chatDraftLength == 100)
    #expect(gomoku.canSendChatNow)

    gomoku.chatDraft = String(repeating: "가", count: 101)
    #expect(gomoku.chatDraftLength == 101)
    #expect(gomoku.canSendChatNow == false)
    gomoku.sendChatDraft()
    #expect(gomoku.chatNotice == "채팅은 100자까지예요")
    #expect(GomokuStubProtocol.count(host: host, rpc: "gomoku_chat_send") == 0, "확정으로 거절당할 글을 내보냈다")

    // 자소가 아니라 **코드포인트**다(자소로 세면 화면은 여유가 있다는데 서버만 거절한다).
    gomoku.chatDraft = "👨‍👩‍👧‍👦"
    #expect(gomoku.chatDraft.count == 1 && gomoku.chatDraftLength == 7)
    // NFD 로 들어온 한글도 정규화 뒤 서버와 같은 눈금이 된다(안 하면 서버가 6으로 센다).
    gomoku.chatDraft = "한글".decomposedStringWithCanonicalMapping
    #expect(gomoku.chatDraftLength == 2)
    // 공백·폭 0 채움 문자만 있는 입력은 빈 것이다 — 말없이 무시한다.
    gomoku.chatDraft = "  \u{3164}\n "
    #expect(gomoku.canSendChatNow == false)
    gomoku.chatNotice = nil
    gomoku.sendChatDraft()
    #expect(gomoku.chatNotice == nil, "헛친 ↩ 에 안내를 띄우면 사용자가 혼난다")
    #expect(GomokuStubProtocol.count(host: host, rpc: "gomoku_chat_send") == 0)

    // 서버가 상한을 말하면 그 숫자로 재고 그 숫자로 말한다.
    gomoku.applyState(decodePayload(statePayload(chat: [], chatSeq: 0, chatMaxLen: 80)))
    #expect(gomoku.chatMaxLength == 80)
    gomoku.chatDraft = String(repeating: "가", count: 90)
    #expect(gomoku.canSendChatNow == false)
    gomoku.sendChatDraft()
    #expect(gomoku.chatNotice == "채팅은 80자까지예요")
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 빠른_문구는_코드로_가고_초안을_건드리지_않으며_모르는_코드도_지우지_않는다() async {
    let (_, gomoku, host) = makeChatStore("quick") { rpc, _, _ in
        switch rpc {
        case "gomoku_chat_send":
            return reply(["status": "ok", "chat_seq": 2])
        case "gomoku_state":
            return reply(statePayload(
                chat: [chatRow(1, "gg", mine: true, kind: "quick"),
                       chatRow(2, "brand_new_code", kind: "quick")],
                chatSeq: 2))
        default:
            return nil
        }
    }
    gomoku.applyState(decodePayload(statePayload(chat: [], chatSeq: 0)))
    gomoku.chatDraft = "쓰던 말"

    gomoku.sendQuick(.gg)
    await chatWait { !gomoku.isSendingChat && gomoku.chat.count == 2 }

    let body = GomokuStubProtocol.calls(host: host, rpc: "gomoku_chat_send").first?.json ?? [:]
    #expect(body["p_kind"] as? String == "quick")
    #expect(body["p_body"] as? String == "gg", "서버로 가는 것은 코드다 — 한국어 문구가 아니다")
    #expect(gomoku.chatDraft == "쓰던 말", "빠른 문구가 쓰던 말을 지웠다")
    #expect(gomoku.chat.first?.quick == .gg)
    #expect(gomoku.chat.first?.body == "잘 뒀어요", "코드를 문구로 펴는 표는 앱이 갖는다")
    // 서버가 표를 넓힌 날 옛 앱이 만나는 코드 — 줄을 **지우지 않고** 한 문장으로 접는다(소실은 오배달보다 나쁘다).
    #expect(gomoku.chat.last?.quick == nil)
    #expect(gomoku.chat.last?.body == GomokuNoticeText.chatUnknownQuick)
}

// MARK: - 4. 음소거

@MainActor
@Test(.gomokuDefaultsCleanup)
func 음소거는_서버_값으로_켜고_그_판_대화를_처음부터_다시_받는다() async {
    let (_, gomoku, host) = makeChatStore("mute") { rpc, _, _ in
        switch rpc {
        case "gomoku_chat_mute":
            return reply(["status": "ok", "muted": true, "server_now_ms": nowMs()])
        case "gomoku_state":
            // 껐으니 상대 줄(1)은 서버가 걸러 내고 내 줄만 온다.
            return reply(statePayload(chat: [chatRow(2, "그럼", mine: true)], chatSeq: 2, myMuted: true))
        default:
            return nil
        }
    }
    gomoku.applyState(decodePayload(statePayload(
        chat: [chatRow(1, "약올리기"), chatRow(2, "그럼", mine: true)], chatSeq: 2)))
    #expect(gomoku.chat.count == 2)
    #expect(gomoku.isMuted == false)

    gomoku.setChatMuted(true)
    await chatWait { !gomoku.isSendingChat }

    #expect(gomoku.isMuted)
    #expect(GomokuStubProtocol.calls(host: host, rpc: "gomoku_chat_mute").first?.json["p_muted"] as? Bool == true)
    #expect(sinceChat(GomokuStubProtocol.calls(host: host, rpc: "gomoku_state").first?.body ?? "") == 0,
            "가려짐은 서버가 정한다 — 그 판 대화를 처음부터 다시 받아야 한다")
    #expect(gomoku.chat.map(\.seq) == [2], "끈 뒤에는 상대 말이 화면에서 사라진다")
    #expect(gomoku.chatNotice == nil, "토글과 대화 자리의 한 줄이 이미 말한다")
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 상대가_껐거나_옛_버전이면_상태로_남아_화면이_말한다() {
    let (_, gomoku, _) = makeChatStore("tell")
    gomoku.applyState(decodePayload(statePayload(
        chat: [], chatSeq: 0, opponentMuted: true, chatCapable: false)))
    #expect(gomoku.isOpponentMuted, "입력창 위 '상대가 채팅을 껐어요'의 근거")
    #expect(gomoku.opponentChatCapable == false, "'상대는 옛 버전이라 채팅을 못 받아요'의 근거")
    // 그래도 보내는 길은 막지 않는다 — 왜 안 보이는지 말해 주는 것이 잠그는 것보다 낫다.
    gomoku.chatDraft = "안녕"
    #expect(gomoku.canSendChatNow)
}

// MARK: - 5. 판이 바뀌면 비운다

@MainActor
@Test(.gomokuDefaultsCleanup)
func 판이_바뀌면_대화와_초안과_음소거를_비운다() async {
    let (store, gomoku, _) = makeChatStore("switch")
    gomoku.applyState(decodePayload(statePayload(
        chat: [chatRow(1, "안녕", mine: true)], chatSeq: 1,
        myMuted: true, opponentMuted: true, chatCapable: false, chatMaxLen: 80)))
    gomoku.chatDraft = "쓰던 말"
    #expect(gomoku.chat.count == 1)

    gomoku.applyState(decodePayload(statePayload(id: otherMatchID, chat: [], chatSeq: 0)))

    #expect(gomoku.chat.isEmpty, "앞 판의 말이 새 판에 섞였다")
    #expect(gomoku.chatDraft == "", "앞 판에 쓰던 말이 새 판 입력칸에 남았다")
    #expect(gomoku.chatSeq == 0)
    #expect(gomoku.isMuted == false && gomoku.isOpponentMuted == false)
    #expect(gomoku.opponentChatCapable)
    #expect(gomoku.chatMaxLength == 100)

    // [로비로]도 같다.
    gomoku.applyState(decodePayload(statePayload(
        id: otherMatchID, matchStatus: "finished", turn: nil, chat: [chatRow(1, "잘 뒀어요")], chatSeq: 1)))
    gomoku.chatDraft = "한 판 더"
    #expect(gomoku.chat.count == 1, "끝난 판에서도 인사할 수 있다(결과 화면 채팅)")
    gomoku.backToLobby()
    #expect(gomoku.chat.isEmpty && gomoku.chatDraft == "")

    // 로그아웃도 같다.
    gomoku.applyState(decodePayload(statePayload(chat: [chatRow(1, "안녕")], chatSeq: 1, myMuted: true)))
    gomoku.chatDraft = "x"
    gomoku.isSendingChat = true
    store.signOut()
    #expect(gomoku.chat.isEmpty)
    #expect(gomoku.chatDraft == "")
    #expect(gomoku.chatSeq == 0)
    #expect(gomoku.isMuted == false)
    #expect(gomoku.isSendingChat == false)
    #expect(gomoku.chatNotice == nil)
}
