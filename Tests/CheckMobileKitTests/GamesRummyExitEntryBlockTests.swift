@testable import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

// 안드로이드 운영 시험에서 나온 값: **앱에서 기권 직후 오목·체스·테트리스 입구가 몇 초 이상 '아잉 큐브 하는 중'으로 막혀 보였다.**
// 폰(iOS)에서 같은 틈을 값으로 잰다. 입구 셋은 막히면 안 되고, 카드(`hasActiveRummyMatch`)가 낡은 로비로 말하는 틈은 그 넓이를 못 박는다.

@MainActor
@Suite(.serialized) struct GamesRummyExitEntryBlockTests {
    private static let stateJSON: (Int, String) -> String = { nowMs, seat in
        #"{"status":"ok","state":\#(RummyWireJSON.state(nowMs: nowMs, status: "active", mySeatState: seat, turnSeat: 1))}"#
    }

    /// 판 중인 사람 하나 — 로비가 그 판 id 를 말하고, 그 판을 들고 있고, 이 기기가 손댔다. 입구 셋이 막힌 것이 기준선이다.
    private func playing(label: String) async -> RummyWireHarness {
        let harness = RummyWireHarness(label: label)
        harness.serveLobby(activeMatchID: RummyWireHarness.matchID)
        harness.server.setDefault("rummy_state", json: Self.stateJSON(harness.nowMs, "playing"))
        await harness.signIn()
        await harness.rummy.refreshLobby()
        harness.rummy.markEngaged(RummyWireHarness.matchUUID)
        await harness.barrier()
        #expect(harness.rummy.match?.id == RummyWireHarness.matchUUID, "전제: 판을 들고 있지 않다")
        #expect(harness.rummy.activeMatchID == RummyWireHarness.matchUUID)
        Self.expectBlocked(harness.games, "전제: 판 중인데 입구가 열려 있다")
        return harness
    }

    private static func expectBlocked(_ games: GamesStore, _ note: Comment) {
        #expect(games.chessEntryBlock == .rummy, note)
        #expect(games.gomokuEntryBlock == .rummy, note)
        #expect(games.tetrisEntryBlock == .rummy, note)
    }

    private static func expectOpen(_ games: GamesStore, _ note: Comment) {
        #expect(games.chessEntryBlock == nil, note)
        #expect(games.gomokuEntryBlock == nil, note)
        #expect(games.tetrisEntryBlock == nil, note)
    }

    @Test("나가기 직후: 로비를 다시 읽기 전(낡은 me.active_match_id)에도 세 입구가 열린다 — 이때 카드는 아직 '판 진행 중'이다(틈)")
    func leavingOpensEveryEntryBeforeTheLobbyIsReread() async {
        let harness = await playing(label: "rummy-exit-stale")
        let games = harness.games
        let lobbyBefore = harness.count("rummy_lobby")

        await harness.rummy.leaveForExit(reason: .windowClosed)

        #expect(harness.count("rummy_leave") == 1)
        #expect(harness.count("rummy_lobby") == lobbyBefore, "전제: 로비를 다시 읽었다 — 낡은 값을 못 잰다")
        #expect(harness.rummy.lobby?.me?.activeMatchId == RummyWireHarness.matchUUID, "전제: 로비 값이 낡아 있지 않다")
        #expect(harness.rummy.match == nil && harness.rummy.activeMatchID == nil)
        #expect(!games.hasLiveRummyMatch)
        Self.expectOpen(games, "기권 직후 낡은 로비 값으로 입구가 막혔다")

        // 카드의 틈: 입구는 열렸는데 카드 줄은 낡은 로비 값으로 아직 판이 흐른다고 말한다.
        #expect(games.hasActiveRummyMatch, "틈이 닫혔다 — 이 줄과 답의 사실을 고쳐라")
        #expect(GamesRummyCard.line(games) == .activeMatch)
        #expect(GamesRummyCard.chip(games) == GamesRummyText.activeChip)

        // 틈이 닫히는 때: 다음 로비 응답.
        harness.serveLobby()
        await GamesRummyExit.settleAfterLeaving(harness.rummy)
        #expect(harness.count("rummy_lobby") == lobbyBefore + 1)
        #expect(!games.hasActiveRummyMatch, "로비를 다시 읽었는데 카드가 판 진행 중이다")
        #expect(GamesRummyCard.line(games) == .record)
        Self.expectOpen(games, "로비를 다시 읽은 뒤 입구가 막혔다")
        await harness.tearDown()
    }

    @Test("[나가기] 확인 길 전체: 끝나면 입구가 열리고 카드가 판 진행 중을 말하지 않는다 · 로비 읽기가 실패하면 입구는 열린 채 카드만 다음 응답까지 틀린다")
    func confirmingLeavesNothingBehind() async {
        let harness = await playing(label: "rummy-exit-confirm")
        harness.serveLobby()
        #expect(await GamesRummyExit.confirm(asked: .confirmForfeit, rummy: harness.rummy))
        Self.expectOpen(harness.games, "확인 길 끝에 입구가 막혔다")
        #expect(!harness.games.hasActiveRummyMatch)
        await harness.tearDown()

        let failed = await playing(label: "rummy-exit-confirm-fail")
        failed.server.setDefault("rummy_lobby") { _ in .networkFailure() }
        #expect(await GamesRummyExit.confirm(asked: .confirmForfeit, rummy: failed.rummy))
        Self.expectOpen(failed.games, "로비 읽기가 실패했다고 입구가 막혔다")
        #expect(failed.games.hasActiveRummyMatch, "틈이 닫혔다 — 이 줄과 답의 사실을 고쳐라")
        #expect(GamesRummyCard.line(failed.games) == .activeMatch)
        failed.serveLobby()
        await failed.rummy.refreshLobby()
        #expect(!failed.games.hasActiveRummyMatch)
        await failed.tearDown()
    }

    @Test("나간 뒤 도착한 로비가 그 판 id 를 말해도(나가기 전에 나간 조회 · 서버에 아직 안 닿은 기권) 접은 판으로 입구를 막지 않는다 · 안 접은 판은 그대로 막는다")
    func aLateLobbyDoesNotReblockAFoldedMatch() async {
        let harness = await playing(label: "rummy-exit-late")
        let games = harness.games
        await harness.rummy.leaveForExit(reason: .windowClosed)
        Self.expectOpen(games, "전제: 나간 직후 입구가 막혔다")

        // 서버는 아직 그 판에 내 자리가 있다고 답한다.
        await harness.rummy.refreshLobby()
        #expect(harness.rummy.match == nil, "접은 판을 다시 끌어왔다")
        #expect(harness.rummy.lobby?.me?.activeMatchId == RummyWireHarness.matchUUID, "전제: 로비가 그 판을 말하지 않는다")
        Self.expectOpen(games, "접은 판의 늦은 로비로 입구가 다시 막혔다")
        // 카드의 틈은 여기서도 열려 있다: 로비가 그 판을 말하는 동안 '판 진행 중'이다.
        #expect(games.hasActiveRummyMatch, "틈이 닫혔다 — 이 줄과 답의 사실을 고쳐라")
        #expect(GamesRummyCard.line(games) == .activeMatch)
        await harness.tearDown()

        // 기준선: 접지 않은 판은 id 만 알아도 막는다(닫는 쪽으로 틀린다).
        let unfolded = RummyWireHarness(label: "rummy-exit-late-baseline")
        unfolded.serveLobby(activeMatchID: RummyWireHarness.matchID)
        unfolded.server.setDefault("rummy_state") { _ in .networkFailure() }
        await unfolded.signIn()
        await unfolded.rummy.refreshLobby()
        #expect(unfolded.rummy.match == nil)
        Self.expectBlocked(unfolded.games, "접지 않은 판인데 id 만 아는 틈에 입구가 열렸다")
        await unfolded.tearDown()
    }

    @Test("서버가 시간 초과로 기권시켜 내 자리가 forfeit 인 판을 들었다: 낡은 로비 id 가 남아도 세 입구가 열린다 · 그 판이 흐르는 동안 카드는 '판 진행 중'이다")
    func aTimedOutSeatDoesNotBlock() async {
        let harness = await playing(label: "rummy-exit-timeout")
        let games = harness.games

        guard let forfeited = harness.decodedState(mySeatState: "forfeit", seq: 4) else {
            Issue.record("state 픽스처가 와이어와 어긋난다")
            return
        }
        #expect(harness.rummy.applyState(forfeited) == .applied, "전제: 기권 state 를 안 들었다")
        #expect(harness.rummy.activeMatchID == RummyWireHarness.matchUUID, "전제: 낡은 id 가 지워졌다")
        #expect(harness.rummy.lobby?.me?.activeMatchId == RummyWireHarness.matchUUID)
        #expect(RummyExitPolicy.mySeat(harness.rummy)?.state == .forfeit)
        #expect(!games.hasLiveRummyMatch)
        Self.expectOpen(games, "시간 초과로 기권된 자리가 입구를 막았다")
        #expect(games.hasActiveRummyMatch, "틈이 닫혔다 — 이 줄과 답의 사실을 고쳐라")
        #expect(GamesRummyCard.line(games) == .activeMatch)

        // 로비가 '없음'으로 새로 와도(서버 v_active 는 playing 자리만 본다) 들고 있는 판은 그대로다 — 입구는 열리고 카드 값도 그대로다.
        harness.server.setDefault("rummy_state", json: Self.stateJSON(harness.nowMs, "forfeit"))
        harness.serveLobby()
        await harness.rummy.refreshLobby()
        #expect(harness.rummy.activeMatchID == nil)
        #expect(harness.rummy.match?.id == RummyWireHarness.matchUUID)
        Self.expectOpen(games, "로비를 새로 읽은 뒤 기권 자리가 입구를 막았다")
        #expect(games.hasActiveRummyMatch, "틈이 닫혔다 — 이 줄과 답의 사실을 고쳐라")
        await harness.tearDown()
    }
}
