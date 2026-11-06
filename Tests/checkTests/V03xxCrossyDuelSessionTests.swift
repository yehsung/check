import Foundation
import Testing
@testable import CheckCore

// 1:1 길건너 판 구동기(`CrossyDuelSession`) 계약 — SPEC v1.3 §8.1 · §3.1 · §10.2 C 줄. **모양이 아니라 결과를 잰다.**
// 각 시험의 첫 줄 주석은 "없으면 어떤 결함이 초록으로 통과하는가"이고, 단언마다 결함 변이에서 갈리는 기준선 짝을 함께 둔다.
// 판 시계는 단조 초(스토어 `uptime`)를 숫자로 넣는다 — 벽시계를 읽는 길이 없다.

private let csSeed = 20_261_106

/// 판 시작(로컬 단조 100초)을 아는 세션.
private func csStarted(goal: Int = 100, at start: TimeInterval = 100) -> CrossyDuelSession {
    var session = CrossyDuelSession(seed: csSeed, goal: goal)
    session.syncStart(startAtMs: 10_000, serverNowMs: 10_000 - (start - 50) * 1000, localNow: 50)
    return session
}

/// 시작 풀밭(0~2줄)에서 앞으로 한 칸 뛰고 착지할 때까지 민다 — 점수가 1 오른다(풀밭이라 죽지 않는다).
private func csHop(_ session: inout CrossyDuelSession, from t: TimeInterval) -> TimeInterval {
    session.forward()
    let landed = t + 0.2
    session.advance(to: landed)
    return landed
}

@Suite("V03xx 길건너 1:1 — 판 구동기(CrossyDuelSession)")
struct V03xxCrossyDuelSessionTests {

    @Test("syncStart: 서버 시작을 단조 시계로 옮기고 가장 이른 추정을 남긴다 · 당기면 endAt·graceEndAt 도 따라온다(CC-17)")
    func syncStartKeepsEarliestAndEndFollows() {
        // 없으면: endAt 을 저장 칸으로 두면 잠자기 뒤 startAt 이 당겨져도 3분 얼림이 옛 시각에 남아 판이 늦게 언다.
        var session = CrossyDuelSession(seed: csSeed)
        session.syncStart(startAtMs: 13_000, serverNowMs: 10_000, localNow: 500)
        #expect(session.startAt == 503)
        #expect(session.endAt == TimeInterval(683))
        #expect(session.graceEndAt == TimeInterval(685))
        // 더 늦은 추정(지연이 큰 응답)은 무시 — 기준선: 덮어쓰는 변이면 504 가 된다.
        session.syncStart(startAtMs: 13_000, serverNowMs: 10_000, localNow: 501)
        #expect(session.startAt == 503)
        // 더 이른 추정은 받는다 — endAt 이 같이 당겨진다(저장 칸 변이면 683 그대로).
        session.syncStart(startAtMs: 13_000, serverNowMs: 10_000, localNow: 499)
        #expect(session.startAt == 502)
        #expect(session.endAt == 682)
        #expect(session.countdownRemaining(at: 500) == 2)
        #expect(session.remaining(at: 600) == 82)
    }

    @Test("advance: 시작 전엔 .ready · 시작에 begin · 1/30초 조각으로 흘린다(한 걸음 0.5초 변이는 1/30초만 흐른다)")
    func advanceStepsInThirtiethSlices() {
        // 없으면: 엔진이 dt 를 1/30 으로 자르므로 0.5초를 한 번에 넘기면 판 시간이 0.033초만 흐른다(MX:69) — 차가 멎어 보인다.
        var session = csStarted()
        session.advance(to: 99)
        #expect(session.started == false)
        #expect(session.game.phase == .ready)
        session.advance(to: 100.5)
        #expect(session.started)
        #expect(session.game.phase == .running)
        #expect(abs(session.game.elapsed - 0.5) < 1e-6)
        // 같은 시각이면 멱등.
        session.advance(to: 100.5)
        #expect(abs(session.game.elapsed - 0.5) < 1e-6)
        // 기준선: 엔진에 0.5초를 한 걸음으로 넣으면 1/30초만 흐른다.
        var raw = CrossyGame(seed: UInt64(csSeed), rules: .duel)
        raw.begin()
        raw.step(dt: 0.5)
        #expect(abs(raw.elapsed - 1.0 / 30) < 1e-6)
    }

    @Test("따라잡기 상한 1초 — 넘는 간격은 버린다(잘게 민 판은 5초가 다 흐른다)")
    func catchUpIsCappedAtOneSecond() {
        // 없으면: 잠자기 뒤 한 번에 수십 초를 흘려 그 사이 차에 치인 죽음이 쌓이고 부활 대기가 겹친다(설계 결정 — 테트리스 30초와 다름).
        var jumped = csStarted()
        jumped.advance(to: 100)
        jumped.advance(to: 105)
        #expect(abs(jumped.game.elapsed - 1.0) < 1e-6)
        #expect(abs(jumped.droppedSeconds - 4.0) < 1e-6)
        var stepped = csStarted()
        var t: TimeInterval = 100
        while t < 105 - 1e-9 {
            t += 0.05
            stepped.advance(to: t)
        }
        #expect(abs(stepped.game.elapsed - 5.0) < 1e-3)
        #expect(stepped.droppedSeconds == 0)
    }

    @Test("3분 얼림: endAt 뒤엔 시계·입력이 멎는다(얼기 전엔 같은 입력이 뛴다)")
    func freezesAtEndAndIgnoresInput() {
        // 없으면: 상한 뒤에도 점수가 올라 서버(유예 2초 밖은 안 센다)와 화면 숫자가 갈린다.
        var live = csStarted()
        live.advance(to: 100.2)
        let before = live.game.hopCount
        live.forward()
        #expect(live.game.hopCount == before + 1)       // 기준선: 판 중 입력은 뛴다

        var frozen = csStarted()
        frozen.advance(to: 100.2)
        frozen.advance(to: 280.5)
        #expect(frozen.finished)
        let elapsed = frozen.game.elapsed
        let hops = frozen.game.hopCount
        frozen.forward()
        frozen.input(.left)
        frozen.advance(to: 290)
        #expect(frozen.game.hopCount == hops)
        #expect(frozen.game.elapsed == elapsed)
        #expect(frozen.remaining(at: 290) == 0)
    }

    @Test("reportDue 표: 준비 문 · 시작 모름 1초 · 카운트다운 3초 · 변화 2초 · 정체 3초 · 0.25초 틈 · 비행 중 대기")
    func reportDueTable() {
        // 없으면: 간격이 하나라도 어긋나면 DB 부하(§3.3)가 늘거나 15초 침묵 패가 난다 — 표의 경계를 전부 잰다.
        var session = CrossyDuelSession(seed: csSeed)
        #expect(session.reportDue(now: 10, reportMs: 2000, heartbeatMs: 3000, windowVisible: false) == nil)
        #expect(session.reportDue(now: 10, reportMs: 2000, heartbeatMs: 3000, windowVisible: true) == .ready)
        let ready = session.makeReport(.ready, at: 10)
        #expect(ready == CrossyDuelReportBody(seq: 1, score: 0, deaths: 0))
        // 비행 중이면 기다린다(시작 모름 1초가 지나도).
        #expect(session.reportDue(now: 11.5, reportMs: 2000, heartbeatMs: 3000, windowVisible: true) == nil)
        session.reportSettled()
        // 준비 뒤 시작 모름 = 1초 하트비트(CC-18) — 0.9초엔 없음.
        #expect(session.reportDue(now: 10.9, reportMs: 2000, heartbeatMs: 3000, windowVisible: true) == nil)
        #expect(session.reportDue(now: 11.0, reportMs: 2000, heartbeatMs: 3000, windowVisible: true) == .heartbeat)
        _ = session.makeReport(.heartbeat, at: 11)
        session.reportSettled()
        // 시작을 알면(카운트다운) 하트비트는 3초 — 기준선: 시작 모름 1초가 남는 변이는 12.0 에 낸다.
        session.syncStart(startAtMs: 20_000, serverNowMs: 15_000, localNow: 11)   // start = 16
        #expect(session.reportDue(now: 12.0, reportMs: 2000, heartbeatMs: 3000, windowVisible: true) == nil)
        #expect(session.reportDue(now: 13.9, reportMs: 2000, heartbeatMs: 3000, windowVisible: true) == nil)
        #expect(session.reportDue(now: 14.0, reportMs: 2000, heartbeatMs: 3000, windowVisible: true) == .heartbeat)
        _ = session.makeReport(.heartbeat, at: 14)
        session.reportSettled()
        // 판 중 점수 변화 — 2초 간격(1.9초엔 없음), 변화 없으면 3초.
        session.advance(to: 16.1)
        let landed = csHop(&session, from: 16.1)
        #expect(session.game.score == 1)
        #expect(session.reportDue(now: 15.9, reportMs: 2000, heartbeatMs: 3000, windowVisible: true) == nil)
        #expect(session.reportDue(now: 16.0, reportMs: 2000, heartbeatMs: 3000, windowVisible: true) == .change)
        // 프레임 확인됨이면 변화 보고를 내지 않고 체크포인트(여기선 3초)만.
        #expect(session.reportDue(now: 16.0, reportMs: 2000, heartbeatMs: 3000, windowVisible: true,
                                  changeReportsSuppressed: true) == nil)
        #expect(session.reportDue(now: 17.0, reportMs: 2000, heartbeatMs: 3000, windowVisible: true,
                                  changeReportsSuppressed: true) == .heartbeat)
        let change = session.makeReport(.change, at: max(landed, 16))
        #expect(change.seq == 4 && change.score == 1)
        session.reportSettled()
        // 0.25초 틈 — 0.2초 뒤엔 무엇도 없다.
        #expect(session.reportDue(now: 16.4, reportMs: 2000, heartbeatMs: 3000, windowVisible: true) == nil)
    }

    @Test("값 자르기: report_ms 500 → 1000 · heartbeat < report → report · 5000 상한 · 키 없으면 2000/3000")
    func intervalsAreClamped() {
        // 없으면: 서버(또는 위조 응답)가 report_ms 100 을 주면 클라가 초당 10번 보고해 Nano DB 를 친다.
        func pair(_ r: Int?, _ h: Int?) -> [Int] {
            let c = CrossyDuelSession.clampedIntervals(reportMs: r, heartbeatMs: h)
            return [c.reportMs, c.heartbeatMs]
        }
        #expect(pair(500, 3000) == [1000, 3000])
        #expect(pair(2000, 1000) == [2000, 2000])
        #expect(pair(9000, 9000) == [5000, 5000])
        #expect(pair(nil, nil) == [2000, 3000])
        // reportDue 도 자른 값으로 판정한다 — 500 을 그대로 쓰는 변이는 0.5초 뒤 change 를 낸다.
        var session = csStarted(at: 0)
        session.advance(to: 0.25)
        _ = session.makeReport(.ready, at: 0.25)
        session.reportSettled()
        _ = csHop(&session, from: 0.25)
        #expect(session.reportDue(now: 0.75, reportMs: 500, heartbeatMs: 3000, windowVisible: true) == nil)
        #expect(session.reportDue(now: 1.25, reportMs: 500, heartbeatMs: 3000, windowVisible: true) == .change)
    }

    @Test("goal 은 비행 중 보고를 기다리지 않는다 — 하트비트가 2초째 나가 있어도 0.25초 뒤 goal(CC-3)")
    func goalSkipsInFlightReport() {
        // 없으면: 테트리스 `guard !reportInFlight` 를 베끼면 goal 기록이 하트비트 왕복만큼 늦어 먼저 닿고도 진다.
        var session = csStarted(goal: 2, at: 0)
        session.advance(to: 0.25)
        _ = session.makeReport(.ready, at: 0.25)            // 나가 있다(답 없음)
        let t = csHop(&session, from: 0.25)
        _ = csHop(&session, from: t)
        #expect(session.game.score == 2)
        #expect(session.inFlight)
        #expect(session.reportDue(now: 0.45, reportMs: 2000, heartbeatMs: 3000, windowVisible: true) == nil)  // 0.25초 틈 전
        #expect(session.reportDue(now: 0.5, reportMs: 2000, heartbeatMs: 3000, windowVisible: true) == .goal)
        let body = session.makeReport(.goal, at: 0.5)
        #expect(body.score == 2 && body.seq == 2)
        // goal 은 한 번 — 그 뒤 비행 중이면 하트비트도 기다린다.
        #expect(session.reportDue(now: 3.5, reportMs: 2000, heartbeatMs: 3000, windowVisible: true) == nil)
        session.reportSettled()
        // 결과가 올 때까지 하트비트는 계속(NOTES §8-2 waitingForResult).
        #expect(session.reportDue(now: 3.5, reportMs: 2000, heartbeatMs: 3000, windowVisible: true) == .heartbeat)
        // 기준선: 점수가 목표 미만이면 같은 자리에서 goal 이 없다.
        var short = csStarted(goal: 3, at: 0)
        short.advance(to: 0.25)
        _ = short.makeReport(.ready, at: 0.25)
        _ = csHop(&short, from: 0.25)
        #expect(short.reportDue(now: 0.5, reportMs: 2000, heartbeatMs: 3000, windowVisible: true) == nil)
    }

    @Test("cap 은 얼림 순간 곧바로(비행 중이어도) · postGrace 는 grace_end + 0.25초에 한 번 · 3초 멈춤은 버림 판정")
    func capPostGraceAndStall() {
        // 없으면: 3분 끝 보고가 비행 중 하트비트 뒤로 밀려 유예 2초 밖에 닿으면 마지막 점수가 안 센다.
        var session = csStarted(at: 0)
        session.advance(to: 0.1)
        _ = session.makeReport(.ready, at: 179.5)
        #expect(session.reportDue(now: 179.9, reportMs: 2000, heartbeatMs: 3000, windowVisible: true) == nil)
        session.advance(to: 180)
        #expect(session.finished)
        #expect(session.reportDue(now: 180.0, reportMs: 2000, heartbeatMs: 3000, windowVisible: true) == .cap)
        _ = session.makeReport(.cap, at: 180)
        // 3초 멈춤: 2.9초는 아직, 3.0초면 버릴 때(스토어가 실패 한 번으로 센다).
        #expect(session.reportStalled(at: 182.9) == false)
        #expect(session.reportStalled(at: 183.0))
        session.reportSettled()
        #expect(session.reportStalled(at: 190) == false)
        // grace_end(182) + 0.25 전엔 없음 · 뒤엔 postGrace 한 번.
        #expect(session.reportDue(now: 182.2, reportMs: 2000, heartbeatMs: 3000, windowVisible: true) == nil)
        #expect(session.reportDue(now: 182.25, reportMs: 2000, heartbeatMs: 3000, windowVisible: true) == .postGrace)
        _ = session.makeReport(.postGrace, at: 182.25)
        session.reportSettled()
        #expect(session.reportDue(now: 183.0, reportMs: 2000, heartbeatMs: 3000, windowVisible: true) == nil)
        #expect(session.reportDue(now: 185.25, reportMs: 2000, heartbeatMs: 3000, windowVisible: true) == .heartbeat)
    }

    @Test("재개: resume → advance → 첫 보고 p_score ≥ 서버 me.score(재개 없이 새로 세운 판은 0) · 다시 begin 하지 않는다(CC-2)")
    func resumeKeepsServerScore() {
        // 없으면: 판 중 앱을 다시 켜면 빈 판(점수 0)에서 다시 시작해 다음 보고가 서버 단조 가드에 걸리거나 점수를 잃는다.
        var resumed = csStarted(at: 0)
        resumed.resume(score: 37, deaths: 2, seq: 5)
        #expect(resumed.started)
        resumed.advance(to: 60)
        resumed.advance(to: 60.5)
        #expect(resumed.game.score == 37)
        #expect(resumed.game.deaths == 2)
        #expect(abs(resumed.game.elapsed - 0.5) < 1e-6)            // 재개 직후 따라잡지 않는다(그 시각부터 흐른다)
        let first = resumed.makeReport(.heartbeat, at: 60.5)
        #expect(first.score >= 37 && first.seq == 6)
        // 기준선: resume 없이 같은 씨앗으로 세운 판의 첫 보고는 0 이다.
        var fresh = csStarted(at: 0)
        fresh.advance(to: 60.5)
        do { let result = fresh.makeReport(.heartbeat, at: 60.5); #expect(result.score == 0) }
    }

    @Test("서버 점수가 로컬보다 크면 그 줄로 다시 세운다(CC-22) · 같거나 작으면 그대로")
    func catchUpRestoresToServerRow() {
        // 없으면: 재개 경합으로 로컬 엔진이 서버보다 뒤처지면 다음 보고가 단조 가드(stale)에 막혀 막대가 영영 멈춘다.
        var session = csStarted(at: 0)
        session.advance(to: 1)
        let same = session.catchUp(serverScore: 0, serverDeaths: 0)
        #expect(same == false)                                                    // 기준선: 같으면 그대로
        let ahead = session.catchUp(serverScore: 48, serverDeaths: 3)
        #expect(ahead)
        #expect(session.game.score == 48)
        #expect(session.game.player.row == 48)
        #expect(session.game.deaths == 3)
        let behind = session.catchUp(serverScore: 40, serverDeaths: 3)
        #expect(behind == false)
        #expect(session.game.score == 48)
        // 시작 전 판은 건드리지 않는다.
        var waiting = csStarted(at: 100)
        let early = waiting.catchUp(serverScore: 10, serverDeaths: 0)
        #expect(early == false)
        #expect(waiting.game.score == 0)
    }

    @Test("벽시계를 −5초 돌려도 판이 흐른다 — 스토어 tick 은 단조 시계만 읽는다(CC-1)")
    @MainActor
    func wallClockJumpDoesNotStallTheMatch() {
        // 없으면: 판 시계를 `Date` 로 몰면 사용자가 시계를 뒤로 돌린 5초 동안 판이 멎는다(그 사이 상대만 달린다).
        var wall = Date(timeIntervalSince1970: 1_800_000_000)
        var up: TimeInterval = 100
        let store = CrossyDuelStore(clock: { wall }, uptime: { up })
        store.gameLoopStepSeconds = 3_600
        store.match = CrossyDuelMatchState(id: "m", stake: 3, seed: csSeed, opponent: CrossyDuelUser(id: "o", displayName: "상대"))
        var session = CrossyDuelSession(seed: csSeed)
        session.syncStart(startAtMs: 1_000, serverNowMs: 1_000, localNow: 100)
        store.duel = session
        store.duelMatchID = "m"
        store.tick()
        wall = wall.addingTimeInterval(-5)
        up += 1
        store.tick()
        #expect(abs((store.duel?.game.elapsed ?? 0) - 1.0) < 1e-6)
        #expect(store.phase == .playing)
    }
}
