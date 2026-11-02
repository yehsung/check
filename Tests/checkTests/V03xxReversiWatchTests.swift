import Foundation
import Testing
@testable import check
@testable import CheckCore

// 아잉 뒤집기 관전·순위 — 스토어 확장(`ReversiStoreWatch` · `ReversiStoreRanking`) 계약. 갈래 C2.
// 하네스는 `V03xxReversiStoreTests.swift` 것을 쓴다. 응답 본문은 서버 픽스처 원문(관전자 D 가 부른 watch · watch_live).
//
// 지키는 것: 관전 세대(나간 뒤 늦게 온 응답이 관전을 되살리지 않는다) · watch_live → watch 한 번 접기 · 깃발 셋이 서로 다른
// 사실을 말한다(`watchUnavailable` · `spectatorCountUnavailable` · `rankingUnavailable`) · 두 스위치(관전 · 순위)가 따로 막는다.

/// 관전 픽스처의 판 id(원문에서 읽는다 — 다시 뽑으면 바뀐다).
private func rvWatchID() throws -> String {
    let state = try rvState("reversi_watch_live__ok")
    return try #require(state.match?.id)
}

@Suite("아잉 뒤집기 관전·순위 — 세대 · 접기 · 깃발 분리")
@MainActor
struct V03xxReversiWatchTests {

    @Test(.gomokuDefaultsCleanup)
    func watch_live_는_판과_관전자_수를_세운다() async throws {
        // 없으면: 관전 응답의 흑·백·판·관전자 수가 화면 값으로 안 옮겨지거나, 관전자 수가 0 으로 남아도 초록이다.
        #expect(try rvViewer("reversi_watch_live__ok") == "b0000000-0000-4000-8000-000000000004")
        let id = try rvWatchID()
        let (store, host) = makeReversiStore("watch-live", me: "b0000000-0000-4000-8000-000000000004", handler: rvHandler([
            "reversi_watch_live": [try rvText("reversi_watch_live__ok")],
        ]))
        store.spectatorFeaturesEnabled = true
        store.isWindowVisible = true
        store.startWatching(matchID: id)
        await rvWait { store.spectating?.blackUser != nil }
        let watch = try #require(store.spectating)
        let row = try #require(try rvState("reversi_watch_live__ok").match)   // 흑백은 무작위 — 원문에서 읽는다
        #expect(watch.blackUser?.id == row.black)
        #expect(watch.whiteUser?.id == row.white)
        #expect(Set([row.black, row.white].compactMap { $0 }) == [rvA, rvB])
        #expect(watch.board == .start)
        #expect(watch.turn == .black)
        #expect(watch.deadline != nil)
        #expect(watch.isFinished == false)
        #expect(store.spectatorCount == 1)
        #expect(store.phase == .lobby)                              // 관전은 phase 가 아니다
        #expect(store.match == nil)
        #expect(store.spectatorCountUnavailable == false)
        let body = try #require(GomokuStubProtocol.calls(host: host, rpc: "reversi_watch_live").first?.json)
        #expect(body["p_match_id"] as? String == id)
        #expect(body["p_since_seq"] as? Int == 0)
        #expect(GomokuStubProtocol.count(host: host, rpc: "reversi_state") == 0)   // 참가자 RPC 를 대신 부르지 않는다
    }

    @Test(.gomokuDefaultsCleanup)
    func watch_live_가_없으면_watch_로_한_번_접고_관전_입구는_안_잠근다() async throws {
        // 없으면: 관전자 수 함수만 없는 서버에서 "관전자 수가 없다" 는 이유로 관전 입구가 통째로 잠기거나(깃발 겸업),
        // 접힌 뒤에도 폴링마다 404 를 한 번씩 더 쏴도 초록이다.
        let id = try rvWatchID()
        let (store, host) = makeReversiStore("watch-fold", me: "b0000000-0000-4000-8000-000000000004", handler: rvHandler([
            "reversi_watch": [try rvText("reversi_watch__ok")],
        ]))
        store.spectatorFeaturesEnabled = true
        store.isWindowVisible = true
        store.startWatching(matchID: id)
        await rvWait { store.spectating?.blackUser != nil }
        #expect(store.spectatorCountUnavailable)
        #expect(store.watchUnavailable == false)
        #expect(store.rankingUnavailable == false)
        #expect(store.spectatorCount == 0)
        #expect(store.spectating?.board == .start)
        await store.refreshWatch()
        #expect(GomokuStubProtocol.count(host: host, rpc: "reversi_watch_live") == 1)   // 접힌 뒤엔 다시 안 묻는다
        #expect(GomokuStubProtocol.count(host: host, rpc: "reversi_watch") == 2)
    }

    @Test(.gomokuDefaultsCleanup)
    func 관전_함수가_없으면_입구를_잠그고_순위_깃발은_안_건드린다() async throws {
        // 없으면: [관전] 칩이 활성인 채 누를 때마다 404 를 반복하거나, 관전 404 하나로 멀쩡한 순위표가 "준비 중" 이 돼도 초록이다.
        let id = try rvWatchID()
        let (store, host) = makeReversiStore("watch-missing", me: "b0000000-0000-4000-8000-000000000004",
                                             handler: rvHandler([:]))
        store.spectatorFeaturesEnabled = true
        store.isWindowVisible = true
        store.startWatching(matchID: id)
        await rvWait { store.watchUnavailable }
        #expect(store.watchUnavailable)
        #expect(store.spectating == nil)
        #expect(store.notice == ReversiNoticeText.unavailable)
        #expect(store.rankingUnavailable == false)
        let before = GomokuStubProtocol.calls(host: host).count
        store.startWatching(matchID: id)                            // 문 앞에서 막힌다
        #expect(store.spectating == nil)
        #expect(GomokuStubProtocol.calls(host: host).count == before)
        // 순위 주기가 잠금을 한 번 풀어 준다(서버가 올라오면 저절로 열린다).
        await store.pollSpectatorFeatures(at: Date().addingTimeInterval(120))
        #expect(store.watchUnavailable == false)
    }

    @Test(.gomokuDefaultsCleanup)
    func 관전_세대_나간_뒤_늦게_온_응답은_관전을_되살리지_않는다() async throws {
        // 없으면: [나가기] 직후 늦게 온 관전 응답이 로비 위에 남의 판을 다시 세우거나, 같은 판에 다시 들어간 뒤 **첫 입장 때의**
        // 늦은 옛 응답이 새 응답을 덮어 판이 한 수 전으로 되돌아가도 초록이다(세대만이 이 둘째 경우를 막는다 —
        // 판 id 는 같고 관전도 서 있다).
        let id = try rvWatchID()
        let old = try rvText("reversi_watch_live__ok")                    // 수 0
        // 한 수 뒤의 같은 판(관전 모양): 원문 move__ok 의 state 에서 판 id 를 관전 판으로, 참가자 칸을 비운다 — 바꾼 칸: 그 여섯.
        let newer = try rvMutatedState("reversi_move__ok") { state in
            var match = state["match"] as! [String: Any]
            match["id"] = id
            state["match"] = match
            for key in ["my_color", "opponent", "ruby_balance", "my_auto_streak", "opponent_auto_streak"] { state[key] = NSNull() }
            state["legal_moves"] = [Int]()
        }
        // 첫 요청은 느리고(옛 판), 다음 요청은 빠르다(새 판).
        let handler: GomokuStubProtocol.Handler = { rpc, _, index in
            guard rpc == "reversi_watch_live" else { return GomokuStubProtocol.Reply(status: 404, body: rvPGRST202(rpc)) }
            return index == 0 ? GomokuStubProtocol.Reply(body: old, delay: 0.6) : GomokuStubProtocol.Reply(body: newer)
        }
        let (store, host) = makeReversiStore("watch-generation", me: "b0000000-0000-4000-8000-000000000004", handler: handler)
        store.spectatorFeaturesEnabled = true
        store.isWindowVisible = true
        store.startWatching(matchID: id)
        await rvWait { GomokuStubProtocol.count(host: host, rpc: "reversi_watch_live") == 1 }
        store.stopWatching()
        #expect(store.spectating == nil)
        store.startWatching(matchID: id)                               // 같은 판에 곧바로 다시
        await rvWait { store.spectating?.moveCount == 1 }
        #expect(store.spectating?.moveCount == 1)
        try await Task.sleep(for: .milliseconds(900))                 // 첫 입장의 늦은 응답(수 0)이 도착할 시간
        #expect(GomokuStubProtocol.count(host: host, rpc: "reversi_watch_live") == 2)
        #expect(store.spectating?.moveCount == 1)
        #expect(store.spectating?.board[19] != nil)
        // 나간 뒤에 온 응답은 관전을 되살리지 않는다.
        let (gone, goneHost) = makeReversiStore("watch-generation-leave", me: "b0000000-0000-4000-8000-000000000004",
                                                handler: rvHandler(["reversi_watch_live": [old]],
                                                                   delays: ["reversi_watch_live": 0.3]))
        gone.spectatorFeaturesEnabled = true
        gone.isWindowVisible = true
        gone.startWatching(matchID: id)
        await rvWait { GomokuStubProtocol.count(host: goneHost, rpc: "reversi_watch_live") == 1 }
        gone.leaveWatch()
        try await Task.sleep(for: .milliseconds(600))
        #expect(gone.spectating == nil)
        #expect(gone.spectatorCount == 0)
    }

    @Test(.gomokuDefaultsCleanup)
    func 관전_스위치가_꺼져_있으면_한_건도_안_나가고_내_판이_서면_관전은_내려간다() async throws {
        // 없으면: 관전을 그리지도 않는 기기가 관전을 당기거나, 내 판이 열렸는데 남의 판 관전이 그 위에 남아도 초록이다.
        let id = try rvWatchID()
        let (off, offHost) = makeReversiStore("watch-off", me: rvA, handler: rvHandler([
            "reversi_watch_live": [try rvText("reversi_watch_live__ok")],
        ]))
        off.isWindowVisible = true
        off.startWatching(matchID: id)
        #expect(off.spectating == nil)
        #expect(GomokuStubProtocol.calls(host: offHost).isEmpty)

        let (store, _) = makeReversiStore("watch-yield", me: rvA, handler: rvHandler([
            "reversi_watch_live": [try rvText("reversi_watch_live__ok")],
        ]))
        store.spectatorFeaturesEnabled = true
        store.isWindowVisible = true
        store.startWatching(matchID: id)
        await rvWait { store.spectating?.blackUser != nil }
        #expect(store.spectatorCount == 1)
        store.applyState(try rvState("reversi_state__their_turn"))
        #expect(store.spectating == nil)
        #expect(store.match?.id == rvMainMatch)
        #expect(store.spectatorCount == 0)                          // 내 판의 관전자 수(원문 0)로 바뀐다
    }

    @Test(.gomokuDefaultsCleanup)
    func 못_보는_판은_안내_한_줄과_함께_내려간다() async throws {
        // 없으면: 끝난 지 오래된 판·숨김 격리 판을 누르면 빈 "관전 중" 화면이 2초 폴링을 영영 돌아도 초록이다.
        #expect(try rvViewer("reversi_watch__not_found") == "b0000000-0000-4000-8000-000000000004")
        let (store, _) = makeReversiStore("watch-gone", me: "b0000000-0000-4000-8000-000000000004", handler: rvHandler([
            "reversi_watch_live": [try rvText("reversi_watch__not_found")],
        ]))
        store.spectatorFeaturesEnabled = true
        store.isWindowVisible = true
        store.startWatching(matchID: rvMainMatch)
        await rvWait { store.notice != nil }
        #expect(store.spectating == nil)
        #expect(store.notice == ReversiNoticeText.watchGone)
    }

    // MARK: 순위

    @Test(.gomokuDefaultsCleanup)
    func 순위는_스위치가_켜져야_나가고_서버_순서_그대로_선다() async throws {
        // 없으면: 순위를 그리지 않는 기기가 60초마다 순위를 당기거나, 순위·순서·승점을 앱이 다시 매겨도 초록이다.
        #expect(try rvViewer("reversi_ranking__ok") == rvA)
        let (store, host) = makeReversiStore("ranking", me: rvA, handler: rvHandler([
            "reversi_ranking": [try rvText("reversi_ranking__ok")],
        ]))
        await store.refreshRanking()
        #expect(GomokuStubProtocol.count(host: host, rpc: "reversi_ranking") == 0)
        #expect(store.ranking == nil)
        store.rankingEnabled = true
        await store.refreshRanking()
        let board = try #require(store.ranking)
        #expect(board.entries.map(\.id) == [rvB, rvA])
        #expect(board.entries.map(\.rank) == [1, 2])
        #expect(board.entries.map(\.points) == [2, -2])
        #expect(board.me == ReversiMyRank(rank: 2, wins: 1, losses: 3, draws: 2, points: -2))
        #expect(board.recordSince == nil)
        // 로비 전적과 맞을 때만 머리글에 낸다(한쪽이 늦으면 nil).
        #expect(store.myRankConsistentWithRecord?.rank == 2)
        store.record = ReversiRecord(wins: 2, losses: 3, draws: 2)
        #expect(store.myRankConsistentWithRecord == nil)
        store.record = ReversiRecord(wins: 1, losses: 3, draws: 2)
        #expect(store.myRankConsistentWithRecord?.rank == 2)
    }

    @Test(.gomokuDefaultsCleanup)
    func 순위_함수가_없으면_순위_깃발만_선다() async throws {
        // 없으면: 순위 404 가 관전 입구까지 잠그거나(깃발 겸업), 서버가 올라온 뒤에도 순위가 "준비 중" 으로 남아도 초록이다.
        let (store, _) = makeReversiStore("ranking-missing", me: rvA, handler: rvHandler([:]))
        store.rankingEnabled = true
        await store.refreshRanking()
        #expect(store.rankingUnavailable)
        #expect(store.watchUnavailable == false)
        #expect(store.spectatorCountUnavailable == false)
        #expect(store.notice == nil)                                 // 순위 실패는 대국 안내를 가리지 않는다
        store.applyRanking(try rvDecode(ReversiRankingResponse.self, try rvText("reversi_ranking__ok")))
        #expect(store.rankingUnavailable == false)
    }
}
