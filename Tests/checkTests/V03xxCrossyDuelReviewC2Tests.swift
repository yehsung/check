import Foundation
import Testing
@testable import check
@testable import CheckCore

// 적대 검토 RV-C2(길건너 1:1 맥 클라, 통합 가지 feat/crossy-duel cdec0511)의 재현 시험을 옮겼다(수리 갈래 — RV-C-2 · 3 · 4 고침 뒤 초록).
// 고치기 전(cdec0511)에는 RV-C-2 · RV-C-3 · RV-C-4 가 빨갛고 대조 둘은 초록이었다(검토 로그 rv2.log).
// 시험대는 C 의 `CDRig`(V03xxCrossyDuelStoreTests.swift — 흉내 서버 · 주입 시계 둘 · 스텁 채널)를 그대로 빌린다.
// 각 시험은 결과를 잰다(스토어가 실제로 든 값 · 화면 잎이 실제로 읽는 값). 기준선은 결과가 다른 입력이다.

/// 흉내 서버 상태 jsonb 를 고쳐 응답처럼 옮긴다(루비 · 서버 시각 · 상태를 시험이 정한다).
@MainActor
private func rvc2Apply(_ rig: CDRig, _ edit: (inout [String: Any]) -> Void) -> CrossyDuelStore.StateApplyOutcome {
    var state = rig.server.state()
    edit(&state)
    return rig.store.applyState(try! cdDecode(CrossyDuelStatePayload.self, cdJSON(state)), receivedAt: rig.clock.uptime)
}

@MainActor
@Suite("V03xx 1:1 길건너 — 적대 검토 RV-C2 재현(늦은 루비 · 준비 단계 시계 · 닫힌 받은 신청)")
struct CrossyDuelReviewC2Tests {

    /// RV-C-2(돈 · 늦은 응답): 정산된 판의 루비(이김 → 잔액 105)를 **정산 전에 만들어진** 응답이 늦게 닿아 되감는다.
    /// `applyState` 는 늦은 응답 가드(끝난 판의 진행 중 스냅숏 → .ignored)보다 **앞에서** `applyRuby` 를 부르고,
    /// `applyLobby` 는 순서 가드가 아예 없다 — 둘 다 server_now_ms 가 더 옛 값인데도 잔액(스토어 · 호스트 미러)을 덮는다.
    @Test("RV-C-2: 정산 뒤 닿은 옛 상태(.ignored)·옛 로비가 루비 잔액을 되감지 않는다(기준선: 더 새 응답은 덮는다)")
    func staleResponsesDoNotRewindRuby() async {
        let rig = CDRig.make("rv2-ruby")
        let store = rig.store
        let t0 = rig.clock.nowMs
        // 진행 중(수락 때 판돈 5 를 낸 잔액 95) — 이 응답은 정산 **전** 서버가 만든 것이다.
        rig.server.edit { $0.me.ready = true; $0.me.seq = 4; $0.me.score = 60; $0.startAtMs = t0 - 60_000 }
        var older = rig.server.state()
        older["ruby_balance"] = 95
        older["server_now_ms"] = t0
        #expect(store.applyState(try! cdDecode(CrossyDuelStatePayload.self, cdJSON(older)), receivedAt: rig.clock.uptime)
                == .applied)
        #expect(store.rubyBalance == 95)
        // 정산(이김 +10 → 105). 서버 시각 t0 + 2초.
        rig.server.finish(winner: CDRig.me, reason: "goal", finalMe: 100, finalOpponent: 60)
        #expect(rvc2Apply(rig) { $0["ruby_balance"] = 105; $0["server_now_ms"] = t0 + 2_000 } == .applied)
        #expect(store.match?.isFinished == true)
        #expect(store.rubyBalance == 105)
        #expect(store.host?.rubyBalance == 105)
        // ① 늦게 닿은 옛 상태(진행 중 · 서버 시각 t0) — 판 값은 버려진다(.ignored). 루비도 버려져야 한다.
        let late = store.applyState(try! cdDecode(CrossyDuelStatePayload.self, cdJSON(older)), receivedAt: rig.clock.uptime)
        #expect(late == .ignored)
        #expect(store.rubyBalance == 105, "버린 옛 상태가 루비 잔액을 되감았다: \(store.rubyBalance ?? -1)")
        #expect(store.host?.rubyBalance == 105, "버린 옛 상태가 앱 루비 미러를 되감았다: \(store.host?.rubyBalance ?? -1)")
        // ② 늦게 닿은 옛 로비(서버 시각 t0 − 1초 · 잔액 95).
        let staleLobby = cdJSON([
            "status": "ok", "server_now_ms": t0 - 1_000, "stakes": [3, 5, 10], "goal": 100, "max_duration_seconds": 180,
            "me": ["ruby_balance": 95, "wins": NSNull(), "losses": NSNull(), "draws": NSNull(),
                   "active_match_id": NSNull(), "incoming": [] as [Any], "outgoing": NSNull()] as [String: Any],
            "users": [] as [Any],
        ])
        await store.applyLobby(try! cdDecode(CrossyDuelLobbyResponse.self, staleLobby))
        #expect(store.rubyBalance == 105, "정산 전 로비가 늦게 닿아 루비 잔액을 되감았다: \(store.rubyBalance ?? -1)")
        // 기준선: 더 새 응답(서버 시각 t0 + 4초 · 잔액 110)은 덮는다.
        #expect(rvc2Apply(rig) { $0["ruby_balance"] = 110; $0["server_now_ms"] = t0 + 4_000 } == .applied)
        #expect(store.rubyBalance == 110)
    }

    /// RV-C-3(표시): 준비 단계(수락됨 · 시작 시각 모름)의 경주 띠 남은 시간이 "0:00" 이다 — 끝난 판의 굳힌 글자와 같다.
    /// 잎(`CrossyDuelRaceBandLeaf`)은 `store.raceSnapshot() ?? fallback(match)` 를 읽는데, 판이 있으면 raceSnapshot 이 nil 을
    /// 돌려주는 일이 없어 "준비 단계 — 남은 시간 3:00" 이라 적힌 fallback 은 죽은 길이다. raceSnapshot 의 remaining 은
    /// 시작 시각을 모르면 nil → 띠가 `remaining ?? 0` 으로 "0:00" 을 그린다. 다른 기기(물러난 쪽)는 판 내내 "0:00".
    @Test("RV-C-3: 준비 단계 경주 띠 남은 시간은 3:00(fallback 의 뜻) — 0:00 이 아니다(기준선: 카운트다운은 3:00)")
    func readyPhaseClockIsNotZero() async {
        let rig = CDRig.make("rv2-clock")
        let store = rig.store
        rig.server.edit { $0.opponent.ready = false }
        #expect(rig.applyServerState() == .applied)
        #expect(store.phase == .ready)
        let match = try! #require(store.match)
        let intended = CrossyDuelText.clock(CrossyDuelRaceBandLeaf.fallback(match).remaining ?? 0)
        #expect(store.raceSnapshot()?.remaining == 180)
        #expect(intended == "3:00")
        // 잎이 실제로 고르는 값(`store.raceSnapshot() ?? fallback`)과 띠가 그리는 글자(`isFinished ? 0 : remaining ?? 0`).
        let leafSnapshot = store.raceSnapshot() ?? CrossyDuelRaceBandLeaf.fallback(match)
        let drawn = CrossyDuelText.clock(match.isFinished ? 0 : (leafSnapshot.remaining ?? 0))
        #expect(drawn == intended, "준비 단계 경주 띠가 '\(drawn)' 을 그린다(끝난 판의 굳힌 글자와 같다)")
        // 기준선: 시작 시각이 오면(카운트다운) 3:00.
        store.lastLobbyRequestAt = rig.clock.deviceWall
        store.windowDidShow()
        await rig.settle()
        rig.server.edit { $0.opponent.ready = true; $0.startAtMs = rig.clock.nowMs + 3_000 }
        #expect(rig.applyServerState() == .applied)
        store.tick()
        #expect(store.phase == .countdown)
        let countdown = store.raceSnapshot()
        #expect(CrossyDuelText.clock(countdown?.remaining ?? 0) == "3:00")
    }

    /// RV-C-4(배너 · 메뉴바 점): 내가 보낸 신청이 수락돼 판이 서는 순간, 서버는 두 사람의 **다른** 대기 신청을 전부 닫는다
    /// (`respond` 가 받는 쪽에서만 로컬 카드를 걷는다 — 이 기기는 보낸 쪽). 보낸 쪽 기기에는 닫힌 받은 신청이 남아
    /// 판 내내(만료 60초까지) 메뉴바 점 · 사이드바 점 · 팝오버 배너([수락])가 선다. 판 중에는 로비 폴링이 없다(phase != lobby).
    @Test("RV-C-4: 보낸 신청이 판이 되면 닫힌 다른 받은 신청이 화면 값에 남지 않는다(기준선: 판 전엔 보인다)")
    func challengerDropsClosedIncomingWhenMatchStarts() async {
        let rig = CDRig.make("rv2-incoming")
        let store = rig.store
        let other = "00000000-0000-0000-0000-0000000000c3"
        // 받은 신청 하나(C → 나, 다른 판 id) + 내가 보낸 신청 하나(나 → 라이벌).
        let incoming: [String: Any] = ["match_id": "c0de0000-0000-4000-8000-0000000000ee",
                                       "from": ["id": other, "display_name": "씨"], "stake": 3,
                                       "expires_at_ms": rig.clock.nowMs + 50_000]
        rig.script.stand("crossy_duel_lobby", cdLobby(
            clock: rig.clock, incoming: [incoming],
            outgoing: cdInvite(peerKey: "to", clock: rig.clock, stake: 5)))
        await store.refreshLobby()
        #expect(store.visibleIncoming?.peer.id == other)                // 기준선: 판 전엔 보인다
        #expect(store.outgoing?.id == CDRig.matchID)
        // 보낸 신청 5초 조회가 수락된 판을 데려온다(서버는 이 순간 C 의 신청도 닫았다).
        store.lastLobbyRequestAt = rig.clock.deviceWall
        store.windowDidShow()
        rig.clock.advance(5)
        await store.pollTick(at: rig.clock.deviceWall)
        #expect(store.match?.id == CDRig.matchID)
        #expect(store.phase == .ready)
        #expect(store.visibleIncoming == nil, "판이 선 순간 닫힌 받은 신청을 걷지 않았다")
        // 서버 사실: 이제 받은 신청은 없고 진행 판이 있다(로비를 다시 읽으면 걷힌다 — 걷을 기회가 있는지가 결함의 갈림).
        rig.script.stand("crossy_duel_lobby", cdLobby(clock: rig.clock, active: CDRig.matchID))
        // 초인종(수락 · 시작)은 진행 중 판이면 그 판 상태만 읽는다 — 로비를 다시 읽지 않는다.
        store.handleSignal()
        if let task = store.syncTask { await task.value }
        #expect(store.visibleIncoming == nil,
                "닫힌 받은 신청이 판 중에 남았다(메뉴바 점 · 팝오버 [수락] 배너): \(store.visibleIncoming?.peer.displayName ?? "")")
    }

    /// RV-C-3 의 둘째 자리: 다른 기기로 물러난 쪽(my_device other — 판 구동기 없음)은 판 내내 "0:00" 이었다.
    /// 끝 시각을 알면 기기 시계로 센 남은 시간(시작 60초 뒤 → 2:00)을 그린다. 끝난 판은 0:00 으로 굳힌다(기준선).
    @Test("RV-C-3: 다른 기기로 물러난 쪽 경주 띠 남은 시간은 끝 시각에서 센다(기준선: 끝난 판은 0:00)")
    func otherDeviceClockCountsFromEnd() async {
        let rig = CDRig.make("rv2-clock-other")
        let store = rig.store
        rig.server.edit { $0.myDevice = "other"; $0.me.ready = true; $0.startAtMs = rig.clock.nowMs - 60_000 }
        #expect(rig.applyServerState() == .applied)
        #expect(store.playingElsewhere)
        let remaining = store.raceSnapshot()?.remaining ?? -1
        #expect(abs(remaining - 120) < 0.5, "다른 기기 쪽 남은 시간: \(remaining)")
        #expect(CrossyDuelText.clock(remaining) == "2:00")
        rig.server.finish(winner: CDRig.rival, reason: "goal", finalMe: 40, finalOpponent: 100)
        #expect(rig.applyServerState() == .applied)
        #expect(store.raceSnapshot()?.remaining == 0)
    }

    /// 대조-B(잠자기): 판 중 잠자기(벽시계 +30초 · 단조 시계 0) 뒤 첫 응답이 시작 시각을 당겨 남은 시간이 실제 경과를
    /// 따른다(≈146.5초) — 단조 시계만 믿으면 176.5초. **통과가 기대값**.
    @Test("대조-B: 잠자기 30초 뒤 첫 응답에서 남은 시간이 실제 경과로 당겨진다")
    func sleepPullsStartEarlier() async {
        let rig = CDRig.make("rv2-sleep")
        let store = rig.store
        await rig.startPlaying()
        // 잠자기: 벽(서버) 시계만 30초 흐르고 단조 시계는 멈춘다.
        rig.clock.wall = rig.clock.wall.addingTimeInterval(30)
        rig.clock.uptime += 3
        rig.clock.wall = rig.clock.wall.addingTimeInterval(3)
        store.tick()
        await rig.settle()
        let remaining = store.raceSnapshot()?.remaining ?? -1
        #expect(abs(remaining - 146.5) < 1.5, "잠자기 뒤 남은 시간이 실제 경과를 안 따른다: \(remaining)")
    }

    /// 대조-A(돈 · 판정 시각): goal 보고가 55P03 으로 끊기면 같은 goal 을 0.25초 뒤에 다시 낸다 — 하트비트(3초)를
    /// 기다리지 않고 실패로도 안 센다(대체 길 판). 이 시험은 **통과가 기대값**이다(검토가 지나간 자리의 대조).
    @Test("대조-A: 55P03 goal → 0.25초 뒤 같은 goal 재전송 · connectionTrouble 아님")
    func goalLockTimeoutRetriesImmediately() async {
        let rig = CDRig.make("rv2-goal-55p03")
        let store = rig.store
        await rig.startPlaying()
        // 엔진을 99 줄로 세우고 한 칸 → 100.
        var duel = try! #require(store.duel)
        _ = duel.catchUp(serverScore: 99, serverDeaths: 0)
        store.duel = duel
        rig.clock.advance(1)
        store.tick()
        await rig.settle()
        let before = rig.reportCount
        rig.script.enqueue("crossy_duel_report", #"{"code":"55P03","message":"canceling statement due to lock timeout"}"#,
                           status: 500)
        store.forward()
        rig.clock.advance(0.3)
        store.tick()
        await rig.settle()
        #expect(rig.reportCount == before + 1)
        #expect(rig.reportBodies.last?["p_score"] as? Int == 100)
        rig.clock.advance(0.3)
        store.tick()
        await rig.settle()
        #expect(rig.reportCount == before + 2, "55P03 뒤 goal 재전송이 0.25초 안에 안 나갔다")
        #expect(rig.reportBodies.last?["p_score"] as? Int == 100)
        #expect(!store.connectionTrouble)
    }
}
