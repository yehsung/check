@testable import CheckCore
import Foundation
import Testing
@testable import CheckMobileKit

// 안드로이드 독립 검토에서 건너온 지적 둘. 서버의 접속 증거는 쓰기와 하트비트뿐이고 state 읽기는 아니다 —
// 복귀 때 읽기만 하고 주기를 기다리면 마지막 하트비트에서 80~90초 사이에 돌아온 사람이 기권될 수 있다.
// 시험 시계는 멈춰 있고 주기는 1시간이다. 나간 건수는 곧 '주기를 안 기다리고 나간 것'이다.
@MainActor
@Suite(.serialized) struct V1016RummyHeartbeatTests {
    private let waits = GamesWaitBudget()

    private func beating(_ label: String, status: String = "active", mySeatState: String = "playing") async -> RummyWireHarness {
        let harness = RummyWireHarness(label: label)
        harness.serveLobby()
        await harness.signIn()
        let state = RummyWireJSON.state(nowMs: harness.nowMs, status: status, mySeatState: mySeatState, turnSeat: 1)
        harness.server.setDefault("rummy_state", json: #"{"status":"ok","state":\#(state)}"#)
        harness.rummy.heartbeatSeconds = 3_600
        harness.rummy.heartbeatEnabled = true
        return harness
    }

    private func returnsFromBackground(_ harness: RummyWireHarness) {
        harness.games.appDidEnterBackground()
        harness.games.appDidBecomeActive()
    }

    @Test("판을 든 순간 1건: 시계가 멈추고 주기가 1시간이어도 나간다 · 그 뒤로는 안 나간다")
    func firstTickIsImmediate() async {
        let harness = await beating("beat-first")
        harness.rummy.markEngaged(RummyWireHarness.matchUUID)
        harness.apply()
        #expect(await waits.wait { harness.count("rummy_heartbeat") >= 1 }, "앱을 새로 켠 직후 첫 전송이 주기만큼 늦는다")
        await harness.barrier()
        #expect(harness.count("rummy_heartbeat") == 1)
        await harness.tearDown()
    }

    @Test("앱 복귀 — 큐브 화면 밖: 곧바로 1건")
    func returnHiddenSendsOne() async {
        let harness = await beating("beat-back-hidden")
        harness.rummy.markEngaged(RummyWireHarness.matchUUID)
        harness.apply()
        #expect(await waits.wait { harness.count("rummy_heartbeat") == 1 })
        #expect(!harness.games.isRummyScreenVisible)
        returnsFromBackground(harness)
        #expect(await waits.wait { harness.count("rummy_heartbeat") == 2 }, "돌아왔는데 읽기만 하고 다음 주기를 기다린다")
        await harness.barrier()
        #expect(harness.count("rummy_heartbeat") == 2)
        await harness.tearDown()
    }

    @Test("앱 복귀 — 큐브 화면 위: 곧바로 1건")
    func returnVisibleSendsOne() async {
        let harness = await beating("beat-back-visible")
        harness.games.rummyScreenDidAppear()
        harness.rummy.markEngaged(RummyWireHarness.matchUUID)
        harness.apply()
        #expect(await waits.wait { harness.count("rummy_heartbeat") == 1 })
        #expect(harness.games.isRummyScreenVisible)
        returnsFromBackground(harness)
        #expect(await waits.wait { harness.count("rummy_heartbeat") == 2 }, "돌아왔는데 읽기만 하고 다음 주기를 기다린다")
        await harness.barrier()
        #expect(harness.count("rummy_heartbeat") == 2)
        await harness.tearDown()
    }

    @Test("앱 복귀 0건: 놀던 기기(화면 안팎) · 하트비트를 쉬는 방")
    func returnSendsNothingWhenNotHolding() async {
        let idle = await beating("beat-back-idle")
        idle.apply()
        returnsFromBackground(idle)
        await idle.barrier()
        idle.games.rummyScreenDidAppear()
        returnsFromBackground(idle)
        await idle.barrier()
        #expect(idle.rummy.heartbeatMatchID == nil)
        #expect(idle.count("rummy_heartbeat") == 0, "놀던 기기가 하트비트를 보냈다")
        await idle.tearDown()

        let room = await beating("beat-back-room", status: "forming", mySeatState: "joined")
        room.rummy.markEngaged(RummyWireHarness.matchUUID)
        room.apply(status: "forming", mySeatState: "joined")
        #expect(room.rummy.phase == .room && room.rummy.roomHeartbeatHeld)
        returnsFromBackground(room)
        await room.barrier()
        #expect(room.count("rummy_heartbeat") == 0, "화면 밖 방이 복귀 한 번에 살아나 모르는 사이 판돈이 걷힌다")
        await room.tearDown()
    }

    @Test("문구: 90초는 마지막 하트비트부터라 실제로는 최대 10초 짧다 — 사람에겐 1분으로 말한다")
    func copySaysOneMinute() throws {
        #expect(GamesRummyText.backgroundWarning == "앱을 1분 넘게 내리면 기권될 수 있어요")
        let forfeit = try #require(GamesRummyText.rules.first { $0.title == "기권" })
        #expect(forfeit.detail.contains("1분 안에 돌아오면 이어서 해요"))
        for rule in GamesRummyText.rules {
            #expect(!rule.detail.contains("90초"), "규칙에 90초가 남았다: \(rule.title)")
        }
    }
}
