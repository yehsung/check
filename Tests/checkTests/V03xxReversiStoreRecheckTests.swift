import Foundation
import Testing
@testable import check
@testable import CheckCore

// 아잉 뒤집기 스토어 — 적대 재검증(VR)에서 나온 두 결함의 회귀 시험. 하네스는 `V03xxReversiStoreTests.swift` 것(makeReversiStore ·
// rvHandler · 픽스처 원문)을 그대로 쓴다. 각 시험 안에 결과가 갈리는 기준선을 같이 둔다.
//  · ① 없으면: 창이 가려진(전체 화면 앱 · 다른 스페이스) 뒤에도, 취소된 폴링 걸음이 날던 조회가 끝나자 남은 걸음(로비)을 새로 낸다.
//  · ② 없으면: 쓰기 응답과 겹친 로비(`predatesWrite`)가 내 보낸 신청의 **수락**을 거절로 읽고, 이미 시작된 판을 안 연다 —
//    내 30초가 화면 없이 흘러 자동 착수를 맞는다.

@Suite("아잉 뒤집기 스토어 — 적대 재검증 회귀(가린 창 폴링 걸음 · 쓰기와 겹친 로비의 수락)")
@MainActor
struct V03xxReversiStoreRecheckTests {
    // MARK: ① 가려진 창 — 취소된 폴링 걸음은 남은 걸음(로비)을 새로 내지 않는다

    /// V2-03 수정은 날던 조회를 폴링 작업의 취소 밖(`outsidePolling`)으로 뺐다. 주석은 "폴링은 멈추고 날던 조회만 끝까지 간다".
    /// 그런데 취소된 폴링 걸음(`pollTick`)은 그 조회가 끝난 뒤에도 **남은 걸음을 계속 밟는다** — 걸음 사이 가드는
    /// `isWindowVisible` 만 보고 `isWindowOccluded` · 취소를 안 본다. 그래서 창이 **가려진**(전체 화면 앱 · 다른 스페이스) 뒤에
    /// 새 조회(로비)가 나간다(머리말 ③ "폴링은 창이 보일 때만"). ★ V2-03 이 만든 결함은 아니다 — 로비 걸음만 고치기 전 모양
    /// (`await refreshLobby()` 를 취소된 작업 안에서 직접)으로 되돌려도 스텁이 그 요청을 받는다(VR 실험, 로비 1건). 걸음 사이 가드에
    /// `!isWindowOccluded` 를 더하면 초록이 된다(VR 실험). 즉 앞부터 있던 구멍이고, `outsidePolling` 주석("날던 조회만")이 넘겨짚는다.
    /// 창을 **내리면**(최소화 · 빨간 점) `isWindowVisible` 가드가 막는다 — 결과가 갈리는 기준선.
    @Test(.gomokuDefaultsCleanup)
    func 가려진_뒤에는_취소된_폴링_걸음이_로비를_새로_내지_않는다() async throws {
        try #require(try rvViewer("reversi_lobby__outgoing") == rvA, "보낸 신청 로비 원문의 시청자가 A 가 아니다")
        try #require(try rvViewer("reversi_state__pending") == rvA, "pending 상태 원문의 시청자가 A 가 아니다")
        func make(_ label: String) throws -> (ReversiStore, String) {
            let (store, host) = makeReversiStore(label, me: rvA, handler: rvHandler(
                ["reversi_state": [try rvText("reversi_state__pending")],
                 "reversi_lobby": [try rvText("reversi_lobby__outgoing")]],
                delays: ["reversi_state": 0.5]))
            store.applyLobby(try rvDecode(ReversiLobbyResponse.self, try rvText("reversi_lobby__outgoing")))
            store.isWindowVisible = true
            store.lastLobbyRequestAt = .distantPast
            store.lastOutgoingRequestAt = .distantPast
            store.pollStepSeconds = 0.02
            return (store, host)
        }

        // 기준선: 보낸 신청 조회(0.5초)가 나는 중 창을 **내린다** → 남은 걸음(로비)은 안 나간다.
        let (base, baseHost) = try make("vr-occl-base")
        try #require(base.outgoing != nil && base.phase == .lobby, "준비: 로비 · 보낸 신청 하나")
        base.startPolling()
        await rvWait { GomokuStubProtocol.count(host: baseHost, rpc: "reversi_state") == 1 }
        try #require(GomokuStubProtocol.count(host: baseHost, rpc: "reversi_state") == 1, "준비: 폴링이 보낸 신청 조회를 냈다")
        base.windowDidHide()
        await rvWait(300) { false }          // 날던 조회(0.5초)가 끝나고 남은 걸음이 돌 시간
        #expect(GomokuStubProtocol.count(host: baseHost, rpc: "reversi_lobby") == 0,
                "기준선: 창을 내린 뒤에는 남은 걸음이 로비를 부르지 않는다")

        // 본 갈래(고치기 전엔 빨강): 같은 순간 창이 **가려진다** → 폴링 작업은 멈췄는데(pollTask nil) 남은 걸음이 로비를 새로 부른다.
        let (store, host) = try make("vr-occl")
        try #require(store.outgoing != nil && store.phase == .lobby, "준비: 로비 · 보낸 신청 하나")
        store.startPolling()
        await rvWait { GomokuStubProtocol.count(host: host, rpc: "reversi_state") == 1 }
        try #require(GomokuStubProtocol.count(host: host, rpc: "reversi_state") == 1, "준비: 폴링이 보낸 신청 조회를 냈다")
        store.windowOcclusionDidChange(visible: false)
        #expect(store.pollTask == nil, "가려지면 폴링 작업은 멈춘다")
        await rvWait(300) { GomokuStubProtocol.count(host: host, rpc: "reversi_lobby") > 0 }
        #expect(GomokuStubProtocol.count(host: host, rpc: "reversi_lobby") == 0,
                "가려진 창에서 취소된 폴링 걸음이 로비 요청을 새로 냈다(날던 조회만 끝까지 간다는 계약과 다르다)")
    }

    // MARK: ② 쓰기와 겹친 로비 — 보낸 신청의 수락을 수락으로 읽는다

    /// V2-06 수정은 쓰기 응답보다 먼저 나간 로비(`predatesWrite`)의 **잔액 · 진행 판 id 만** 덮지 않는다. 그런데 같은 응답의
    /// 신청 목록은 그대로 옮기고(`applyLobbyInvites`), 보낸 신청이 사라진 까닭(수락이냐 거절이냐)을 **옛 `activeMatchID`** 로 가른다
    /// (`becameMatch`). 그래서 내 보낸 신청 X 가 수락된 직후 읽힌 로비(보낸 신청 없음 · 진행 판 X)가 날던 중에 이 기기의 아무 쓰기
    /// (다른 신청 거절 등)가 먼저 돌아오면: ① "상대가 신청을 받지 않았어요" 를 띄우고 ② 보낸 신청 카드를 걷어 5초 폴링도 끊고
    /// ③ 진행 판 꼬리(`refreshMatch(active)`)도 안 낸다 — 이미 시작된 판의 내 30초가 화면 없이 흐른다(다음 30초 로비 폴링까지).
    /// 기준선: 같은 로비가 쓰기와 안 겹치면 거절 안내 없이 그 판을 읽어 연다.
    @Test(.gomokuDefaultsCleanup)
    func 쓰기와_겹친_로비도_보낸_신청의_수락을_수락으로_읽고_판을_연다() async throws {
        try #require(try rvViewer("reversi_lobby__outgoing") == rvA, "보낸 신청 로비 원문의 시청자가 A 가 아니다")
        try #require(try rvViewer("reversi_state__their_turn") == rvA, "진행 판 상태 원문의 시청자가 A 가 아니다")
        let seeded = try rvDecode(ReversiLobbyResponse.self, try rvText("reversi_lobby__outgoing"))
        let sent = try #require(seeded.me?.outgoing?.matchId?.lowercased(), "보낸 신청 원문에 match_id 가 없다")
        // 수락 직후의 로비 = 보낸 신청 없음 · 진행 판 = 그 신청 id(서버가 수락 때 신청 행을 active 로 바꾼다 — 같은 id).
        let accepted = try rvMutated("reversi_lobby__outgoing") { top in
            var me = top["me"] as? [String: Any] ?? [:]
            me["outgoing"] = NSNull()
            me["active_match_id"] = sent
            top["me"] = me
        }
        // 그 판의 상태(A 시점 원문의 id 만 그 신청 id 로).
        let started = try rvMutatedState("reversi_state__their_turn") { state in
            var match = state["match"] as? [String: Any] ?? [:]
            match["id"] = sent
            state["match"] = match
        }
        func make(_ label: String) throws -> (ReversiStore, String) {
            let (store, host) = makeReversiStore(label, me: rvA, handler: rvHandler(
                ["reversi_lobby": [accepted],
                 "reversi_state": [started],
                 "reversi_respond": [try rvText("reversi_respond__declined")]],
                delays: ["reversi_lobby": 0.4]))
            store.applyLobby(seeded)
            return (store, host)
        }

        // 기준선: 쓰기와 안 겹친 로비 → 거절 안내 없음 · 진행 판 id = X · 그 판을 읽어 연다.
        let (base, baseHost) = try make("vr-predates-base")
        try #require(base.outgoing?.id == sent, "준비: 보낸 신청 X")
        await base.refreshLobby()
        await rvWait { base.match?.id == sent }
        #expect(base.notice != ReversiNoticeText.inviteDeclined, "기준선: 수락된 신청에 거절 안내가 서면 안 된다")
        #expect(base.activeMatchID == sent)
        #expect(GomokuStubProtocol.count(host: baseHost, rpc: "reversi_state") == 1, "기준선: 진행 판 꼬리 조회 1번")
        #expect(base.match?.id == sent && base.phase == .playing, "기준선: 시작된 판이 열린다")

        // 본 갈래(고치기 전엔 빨강): 같은 로비가 날던 중 이 기기에서 다른 받은 신청을 거절한다(쓰기 응답이 먼저 온다 → writeRevision +1).
        let (store, host) = try make("vr-predates")
        try #require(store.outgoing?.id == sent, "준비: 보낸 신청 X")
        let lobby = Task { await store.refreshLobby() }
        await rvWait { GomokuStubProtocol.count(host: host, rpc: "reversi_lobby") == 1 }
        await store.respond(inviteID: "0c60135e-0000-4000-8000-0000000000ff", accept: false)
        try #require(GomokuStubProtocol.count(host: host, rpc: "reversi_respond") == 1, "준비: 거절(쓰기) 응답이 로비보다 먼저 왔다")
        try #require(GomokuStubProtocol.count(host: host, rpc: "reversi_lobby") == 1, "준비: 로비는 아직 1번(날던 중)")
        await lobby.value
        await rvWait(300) { store.match?.id == sent }
        #expect(store.notice != ReversiNoticeText.inviteDeclined,
                "수락된 내 신청을 '상대가 신청을 받지 않았어요' 로 알렸다(옛 activeMatchID 로 becameMatch 를 갈랐다)")
        #expect(store.activeMatchID == sent, "진행 판 id 를 못 받았다(predatesWrite 로 버림)")
        #expect(GomokuStubProtocol.count(host: host, rpc: "reversi_state") == 1,
                "진행 판 꼬리 조회를 안 냈다 — 이미 시작된 판이 화면 없이 흐른다")
        #expect(store.match?.id == sent, "시작된 판이 안 열렸다(보낸 신청 카드도 걷혀 5초 폴링마저 없다: outgoing \(String(describing: store.outgoing?.id)))")
    }
}
