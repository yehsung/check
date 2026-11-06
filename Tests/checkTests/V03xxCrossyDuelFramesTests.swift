import Foundation
import Testing
@testable import CheckCore

// 1:1 길건너 판 표시 프레임(SPEC v1.3 §3.4 B0~B7 · §8.4 · B6 Swift 목록) — 순수 장부(`CrossyDuelFrameLink`)와 스토어 전 과정(스텁 채널).
// **프레임은 표시 전용**이다 — 판정·루비는 서버 값만(B0). 각 시험의 첫 줄 주석은 "없으면 어떤 결함이 초록으로 통과하는가"이고,
// 단언마다 결함 변이에서 갈리는 기준선 짝을 함께 둔다.

private let cfMe = "00000000-0000-0000-0000-0000000000a1"
private let cfRival = "00000000-0000-0000-0000-0000000000b2"
private let cfMatch = "c0de0000-0000-4000-8000-0000000000cd"
private let cfTopic = "crossy_duel:\(cfMatch)"
private let cfNoJitter: @Sendable (Double) -> Double = { $0 }

private func cfFrame(seq: Int = 1, frame: Int, score: Int, deaths: Int = 0, heard: Int = 100,
                     sender: String = cfRival) -> CrossyDuelFrame {
    CrossyDuelFrame(sender: sender, seq: seq, frame: frame, score: score, deaths: deaths, heardAgoMs: heard)
}

/// 서버가 켰고 join 까지 된 장부(판 시작 0초).
private func cfJoinedLink(checkpointMs: Int? = 3000) -> CrossyDuelFrameLink {
    var link = CrossyDuelFrameLink(me: cfMe, opponent: cfRival, frameBase: 1_000)
    link.noteServerFrames(CrossyDuelFramesRow(on: true, topic: cfTopic), reportMs: 1000, checkpointMs: checkpointMs)
    do { let result = link.socketCommand(at: 0, matchStartedAt: 0, jitter: cfNoJitter); #expect(result == .connect(topic: cfTopic, refreshToken: false)) }
    do { let result = link.apply(.joined, at: 0.1, jitter: cfNoJitter); #expect(result == .none) }
    return link
}

/// 확인 조건을 모두 채운다(상대 프레임 3장 — 각 0.5초 간격 · h 100).
private func cfConfirmed() -> CrossyDuelFrameLink {
    var link = cfJoinedLink()
    for i in 0..<3 { link.receive(cfFrame(frame: 10 + i, score: 5), at: 1 + Double(i) * 0.5) }
    return link
}

@Suite("V03xx 길건너 1:1 — 판 표시 프레임(장부 · 스토어)")
struct V03xxCrossyDuelFramesTests {

    // MARK: 본문

    @Test("본문: 키 한 짝(payload ↔ decode) · 모르는 v · 깨진 칸 · sc 0…100 밖 · d 음수 · 덧붙은 id 무시")
    func payloadRoundTripAndRejections() throws {
        // 없으면: 보내는 키와 받는 키가 어긋나도(`sc` 대 `score`) 두 맥이 서로의 프레임을 조용히 버려 언제나 대체 길이다.
        let frame = cfFrame(seq: 3, frame: 77, score: 42, deaths: 2, heard: -1)
        var payload = frame.payload
        payload["id"] = "realtime-added"
        #expect(try CrossyDuelFrame.decode(payload: payload).get() == frame)
        var unknown = payload
        unknown["v"] = 2
        #expect(CrossyDuelFrame.decode(payload: unknown) == .failure(.unknownVersion))
        var over = payload
        over["sc"] = 101
        #expect(CrossyDuelFrame.decode(payload: over) == .failure(.outOfRange))
        var edge = payload
        edge["sc"] = 100
        #expect((try? CrossyDuelFrame.decode(payload: edge).get())?.score == 100)      // 기준선: 100 은 받는다
        var negative = payload
        negative["d"] = -1
        #expect(CrossyDuelFrame.decode(payload: negative) == .failure(.outOfRange))
        var broken = payload
        broken["sc"] = "42"
        #expect(CrossyDuelFrame.decode(payload: broken) == .failure(.malformed))
        var heard = payload
        heard["h"] = -2
        #expect(CrossyDuelFrame.decode(payload: heard) == .failure(.malformed))
    }

    // MARK: 확인 조건

    @Test("확인 조건 경계: ③ 2.5초(2.51 은 아님) · ④ h ∈ [0, 2500](2501 · −1 은 아님) · ① 서버 끔 · ② join 전 · ⑤ 실패")
    func conditionBoundaries() {
        // 없으면: 문턱이 하나라도 느슨하면 상대가 내 프레임을 못 듣는데도 3초 체크포인트로 내려가 상대 화면의 내 막대가 멎는다.
        var link = cfConfirmed()
        #expect(link.conditions(at: 2.0).allHold)
        #expect(link.conditions(at: 2.0 + 2.5).heardRecently)
        #expect(link.conditions(at: 2.0 + 2.51).heardRecently == false)
        #expect(link.reportInterval(at: 2.0 + 2.51) == 1.0)                  // 내려가면 곧바로 대체 길
        link.receive(cfFrame(frame: 20, score: 5, heard: 2500), at: 3)
        #expect(link.conditions(at: 3).opponentHearsMe)
        link.receive(cfFrame(frame: 21, score: 5, heard: 2501), at: 3.5)
        #expect(link.conditions(at: 3.5).opponentHearsMe == false)
        #expect(link.conditions(at: 3.5).allHold == false)
        link.receive(cfFrame(frame: 22, score: 5, heard: -1), at: 4)
        #expect(link.conditions(at: 4).opponentHearsMe == false)

        var off = cfConfirmed()
        off.noteServerFrames(nil, reportMs: 1000, checkpointMs: 3000)          // 1차 서버 · 스위치 꺼짐
        #expect(off.conditions(at: 2).serverOn == false)
        #expect(off.changeReportsSuppressed(at: 2) == false)

        var unjoined = CrossyDuelFrameLink(me: cfMe, opponent: cfRival, frameBase: 0)
        unjoined.noteServerFrames(CrossyDuelFramesRow(on: true, topic: cfTopic), reportMs: 1000, checkpointMs: 3000)
        _ = unjoined.socketCommand(at: 0, matchStartedAt: 0, jitter: cfNoJitter)
        for i in 0..<3 { unjoined.receive(cfFrame(frame: 10 + i, score: 5), at: 1 + Double(i) * 0.5) }
        #expect(unjoined.conditions(at: 2).joined == false)
        #expect(unjoined.conditions(at: 2).steady == false)

        var failing = cfConfirmed()
        failing.noteReportFailureStreak(1)
        #expect(failing.conditions(at: 2).reportsHealthy == false)
        #expect(failing.reportInterval(at: 2) == 1.0)
    }

    @Test("3장 히스테리시스(2장으론 아님) · 내려갈 땐 즉시 · 2.5초 넘게 벌어진 프레임은 1장부터 다시 센다")
    func hysteresisUpAndImmediateDown() {
        // 없으면: 첫 프레임 한 장에 3초로 올라가면 끊겼다 붙는 채널에서 체크포인트·대체 길을 오락가락한다.
        var link = cfJoinedLink()
        link.receive(cfFrame(frame: 10, score: 1), at: 1)
        link.receive(cfFrame(frame: 11, score: 1), at: 1.5)
        #expect(link.conditions(at: 1.5).steady == false)
        #expect(link.reportInterval(at: 1.5) == 1.0)
        link.receive(cfFrame(frame: 12, score: 1), at: 2)
        #expect(link.conditions(at: 2).steady)
        #expect(link.reportInterval(at: 2) == 3.0)
        #expect(link.changeReportsSuppressed(at: 2))
        // 즉시 하강: 보고 실패 하나면 곧바로 1초, 회복해도 3장을 다시 모아야 한다.
        link.noteReportFailureStreak(1)
        #expect(link.reportInterval(at: 2.1) == 1.0)
        link.noteReportFailureStreak(0)
        #expect(link.reportInterval(at: 2.2) == 1.0)
        link.receive(cfFrame(frame: 13, score: 1), at: 2.5)
        link.receive(cfFrame(frame: 14, score: 1), at: 3)
        #expect(link.conditions(at: 3).steady == false)
        link.receive(cfFrame(frame: 15, score: 1), at: 3.5)
        #expect(link.conditions(at: 3.5).steady)
        // 3초 벌어진 프레임은 1장부터.
        link.receive(cfFrame(frame: 16, score: 1), at: 6.6)
        #expect(link.steadyStreak == 1)
    }

    @Test("멈춤 10초: 판 시작 뒤 증거 0이면 9.9초엔 그대로 · 10초에 닫고 재시도 · 증거가 있으면 그 뒤 10초")
    func evidenceTimeoutClosesSocket() {
        // 없으면: 쓰기가 거절된(ack:false) 채널에 판 끝까지 프레임을 쓰고, 그동안 확인이 안 되니 DB 1초 보고와 둘 다 낸다.
        var link = cfJoinedLink()
        do { let result = link.socketCommand(at: 9.9, matchStartedAt: 0, jitter: cfNoJitter); #expect(result == .none) }
        do { let result = link.socketCommand(at: 10.0, matchStartedAt: 0, jitter: cfNoJitter); #expect(result == .disconnect) }
        #expect(link.socket == .retrying(at: 11.0))
        // 증거(③④)가 있으면 기준이 그 시각으로 밀린다.
        var heard = cfJoinedLink()
        heard.receive(cfFrame(frame: 10, score: 1, heard: 200), at: 8)
        do { let result = heard.socketCommand(at: 17.9, matchStartedAt: 0, jitter: cfNoJitter); #expect(result == .none) }
        do { let result = heard.socketCommand(at: 18.0, matchStartedAt: 0, jitter: cfNoJitter); #expect(result == .disconnect) }
        // h 가 −1(상대가 나를 못 듣는다)인 프레임은 증거가 아니다.
        var deaf = cfJoinedLink()
        deaf.receive(cfFrame(frame: 10, score: 1, heard: -1), at: 8)
        do { let result = deaf.socketCommand(at: 10.0, matchStartedAt: 0, jitter: cfNoJitter); #expect(result == .disconnect) }
        // 카운트다운 전(시작 모름)엔 멈춤 시계가 돌지 않는다.
        var waiting = cfJoinedLink()
        do { let result = waiting.socketCommand(at: 60, matchStartedAt: nil, jitter: cfNoJitter); #expect(result == .none) }
    }

    @Test("재시도 1·2·4초 최대 3회 → 소진 · unauthorized 는 재시도 없음 · rate limit 도 멈춤")
    func retriesThenStop() {
        // 없으면: 끊긴 판마다 무한 재조인으로 서버 인가 검사(찌르기 조인과 같은 정책 경로)를 두드린다.
        var link = cfJoinedLink()
        var now: TimeInterval = 1
        var delays: [TimeInterval] = []
        for _ in 0..<3 {
            do { let result = link.apply(.closed(code: nil), at: now, jitter: cfNoJitter); #expect(result == .disconnect) }
            guard case .retrying(let at) = link.socket else {
                Issue.record("재시도 상태가 아니다: \(link.socket)")
                return
            }
            delays.append(at - now)
            do { let result = link.socketCommand(at: at - 0.01, matchStartedAt: nil, jitter: cfNoJitter); #expect(result == .none) }
            do { let result = link.socketCommand(at: at, matchStartedAt: nil, jitter: cfNoJitter); #expect(result == .connect(topic: cfTopic, refreshToken: false)) }
            now = at + 0.5
        }
        #expect(delays == [1, 2, 4])
        do { let result = link.apply(.closed(code: nil), at: now, jitter: cfNoJitter); #expect(result == .disconnect) }
        #expect(link.socket == .stopped(.exhausted))
        do { let result = link.socketCommand(at: now + 100, matchStartedAt: nil, jitter: cfNoJitter); #expect(result == .none) }

        var refused = cfJoinedLink()
        do { let result = refused.apply(.joinRejected(.unauthorized), at: 1, jitter: cfNoJitter); #expect(result == .disconnect) }
        #expect(refused.socket == .stopped(.unauthorized))
        #expect(refused.retriesUsed == 0)
        var limited = cfJoinedLink()
        _ = limited.apply(.joinRejected(.unknown("ClientJoinRateLimitReached: Too many joins")), at: 1, jitter: cfNoJitter)
        #expect(limited.socket == .stopped(.rateLimited))
        // 만료 토큰은 한 번만 — 새 토큰을 받은 뒤 연다.
        var expired = cfJoinedLink()
        _ = expired.apply(.joinRejected(.expiredToken), at: 1, jitter: cfNoJitter)
        do { let result = expired.socketCommand(at: 2, matchStartedAt: nil, jitter: cfNoJitter); #expect(result == .connect(topic: cfTopic, refreshToken: true)) }
        _ = expired.apply(.joinRejected(.expiredToken), at: 3, jitter: cfNoJitter)
        #expect(expired.socket == .stopped(.exhausted))
    }

    @Test("되감김 없음: 끝나지 않은 판은 max(프레임 sc, DB) — DB 40 < 프레임 52 → 52 · DB 60 → 60 · 끝난 장부는 DB")
    func mergedScoreNeverRewinds() {
        // 없으면: 체크포인트(3초) 응답의 DB 점수가 프레임보다 옛것이라 상대 점이 뒤로 튄다.
        var link = cfConfirmed()
        link.receive(cfFrame(frame: 30, score: 52), at: 3)
        #expect(link.mergedOpponentScore(db: 40) == 52)
        #expect(link.mergedOpponentScore(db: 60) == 60)
        let fresh = CrossyDuelFrameLink(me: cfMe, opponent: cfRival, frameBase: 0)
        #expect(fresh.mergedOpponentScore(db: 40) == 40)                  // 기준선: 프레임이 없으면 DB
        _ = link.finish()
        #expect(link.mergedOpponentScore(db: 40) == 40)
        do { let result = link.receive(cfFrame(frame: 31, score: 99), at: 4); #expect(result == .matchFinished) }
    }

    @Test("받기 순서: f 가 크거나 s 가 크면 받는다 · 둘 다 아니면 stale · 남의 프레임 · 재개한 프로세스(f 큼, s 같음)는 받는다")
    func receiveOrderingAndResume() {
        // 없으면: (s, f) 사전식으로 비교하면 재개한 상대의 첫 프레임(s 가 옛 값 이하)을 영영 버려 표시가 멎는다.
        var link = cfJoinedLink()
        do { let result = link.receive(cfFrame(seq: 4, frame: 1_000, score: 10), at: 1); #expect(result == nil) }
        do { let result = link.receive(cfFrame(seq: 4, frame: 1_000, score: 11), at: 1.5); #expect(result == .stale) }
        do { let result = link.receive(cfFrame(seq: 4, frame: 999, score: 11), at: 1.6); #expect(result == .stale) }
        do { let result = link.receive(cfFrame(seq: 5, frame: 999, score: 11), at: 1.7); #expect(result == nil) }      // s 가 크면 f 가 작아도
        do { let result = link.receive(cfFrame(seq: 3, frame: 5_000, score: 12), at: 1.8); #expect(result == nil) }    // 재개: 새 프로세스 f(벽시계)
        #expect(link.mergedOpponentScore(db: 0) == 12)
        do { let result = link.receive(cfFrame(frame: 6_000, score: 13, sender: cfMe), at: 1.9); #expect(result == .notOpponent) }
        do { let result = link.receive(cfFrame(frame: 6_001, score: 101), at: 2.0); #expect(result == .outOfRange) }
        #expect(link.mergedOpponentScore(db: 0) == 12)
        // 보내는 쪽: f 는 장부 시작값(벽시계 ms)에서 +1 씩.
        var sender = CrossyDuelFrameLink(me: cfMe.uppercased(), opponent: cfRival, frameBase: 1_800_000_000_000)
        let a = sender.makeFrame(at: 1, seq: 2, score: 3, deaths: 0)
        let b = sender.makeFrame(at: 2, seq: 2, score: 3, deaths: 0)
        #expect(a.frame == 1_800_000_000_000 && b.frame == a.frame + 1)
        #expect(a.sender == cfMe)
        #expect(a.heardAgoMs == -1)
    }

    @Test("보내기 상한: 바뀌면 직전 뒤 0.5초 틈(0.49 는 아님) · 안 바뀌면 1초 · join 전 · 판 흐르기 전엔 안 보낸다")
    func frameRateLimits() {
        // 없으면: 매 착지마다 보내면 판당 초당 이벤트가 8 을 넘어 프로젝트 전체 한도(초당 100)를 테트리스와 나눠 쓰지 못한다(B7).
        var link = cfJoinedLink()
        #expect(link.frameDue(at: 1, live: false, changed: true) == false)
        #expect(link.frameDue(at: 1, live: true, changed: true))
        _ = link.makeFrame(at: 1, seq: 1, score: 1, deaths: 0)
        #expect(link.changedSinceLastFrame(score: 1, deaths: 0) == false)
        #expect(link.changedSinceLastFrame(score: 2, deaths: 0))
        #expect(link.frameDue(at: 1.49, live: true, changed: true) == false)
        #expect(link.frameDue(at: 1.5, live: true, changed: true))
        #expect(link.frameDue(at: 1.99, live: true, changed: false) == false)
        #expect(link.frameDue(at: 2.0, live: true, changed: false))
        var connecting = CrossyDuelFrameLink(me: cfMe, opponent: cfRival, frameBase: 0)
        connecting.noteServerFrames(CrossyDuelFramesRow(on: true, topic: cfTopic))
        _ = connecting.socketCommand(at: 0, matchStartedAt: 0, jitter: cfNoJitter)
        #expect(connecting.frameDue(at: 1, live: true, changed: true) == false)
    }

    @Test("간격: 확인됨이면 체크포인트 3초 · 변화 보고 0 / 대체 길이면 report_ms 1초 · 체크포인트는 [2000, 5000] · 키 없으면 3000")
    func checkpointVersusFallbackIntervals() {
        // 없으면: 확인된 판도 변화마다 DB 에 쓰면 B7 의 DB 절감(판당 분당 96 → 40)이 없고, 확인 안 된 판을 3초로 두면 막대가 늦다.
        let confirmed = cfConfirmed()
        #expect(confirmed.reportInterval(at: 2) == 3.0)
        #expect(confirmed.changeReportsSuppressed(at: 2))
        var fallback = cfJoinedLink()
        fallback.receive(cfFrame(frame: 10, score: 1), at: 1)
        #expect(fallback.reportInterval(at: 1) == 1.0)
        #expect(fallback.changeReportsSuppressed(at: 1) == false)
        var tight = cfJoinedLink(checkpointMs: 500)
        #expect(tight.checkpointMs == 2000)
        tight.noteServerFrames(CrossyDuelFramesRow(on: true, topic: cfTopic), reportMs: 1000, checkpointMs: 9000)
        #expect(tight.checkpointMs == 5000)
        tight.noteServerFrames(CrossyDuelFramesRow(on: true, topic: cfTopic), reportMs: 1000, checkpointMs: nil)
        #expect(tight.checkpointMs == 3000)
        // 토픽 가드: `crossy_duel:` 가 아닌 토픽은 꺼짐(찌르기 채널에 싣지 않는다 — B1).
        #expect(CrossyDuelFramesRow(on: true, topic: "poke:\(cfMe)").activeTopic == nil)
        #expect(CrossyDuelFramesRow(on: true, topic: "crossy_duel:").activeTopic == nil)
        #expect(CrossyDuelFramesRow(on: false, topic: cfTopic).activeTopic == nil)
        #expect(CrossyDuelFramesRow(on: true, topic: cfTopic).activeTopic == cfTopic)
    }

    // MARK: 스토어 전 과정(스텁 채널)

    @Test("스토어: 열기 → join → 프레임 → 트랙 = max(프레임, DB) → 확인되면 변화 보고 0 · 3초 체크포인트 → 끊김 → 대체 길 1초")
    @MainActor
    func storeFlowWithStubChannel() async {
        // 없으면: 장부가 맞아도 스토어가 응답·판 루프·소켓 사건에 잇지 않으면 실제 앱은 언제나 1초 DB 보고이거나(헛수고) 끊긴 뒤에도
        //   3초에 머문다(막대 멎음).
        let rig = CDRig.make("frames-flow", frames: .on)
        let store = rig.store
        await rig.startPlaying()
        let channel = rig.channel
        #expect(channel.connects.count == 1)
        #expect(channel.connects.first?.topic == "crossy_duel:\(CDRig.matchID)")
        #expect(store.frameSocketOpen)
        channel.deliver(.transport(.joined))
        #expect(store.frameLink?.socket == .joined)
        // 판 중 프레임을 보낸다(점수 0 · 첫 장 — h 는 아직 −1).
        rig.clock.advance(0.1)
        store.tick()
        #expect(channel.sent.count == 1)
        #expect(channel.sent.first?["u"] as? String == CDRig.me)
        #expect(channel.sent.first?["h"] as? Int == -1)
        // 상대 프레임을 0.5초마다 받으며 판을 민다.
        var frameNo = 50
        func pump(_ seconds: TimeInterval, score: Int) async {
            var left = seconds
            while left > 1e-9 {
                let dt = min(0.5, left)
                rig.clock.advance(dt)
                left -= dt
                channel.deliver(.frame(CrossyDuelFrame(sender: CDRig.rival, seq: 1, frame: frameNo, score: score,
                                                       deaths: 0, heardAgoMs: 200)))
                frameNo += 1
                store.tick()
                await rig.settle()
            }
        }
        let lastReportAt = store.duel?.lastSent?.at ?? 0
        await pump(1.5, score: 52)                                     // 3장 — 확인
        #expect(store.raceSnapshot()?.opponentScore == 52)
        #expect(store.match?.opponentScore == 0)                       // 표시 전용 — 판 상태(서버 값)는 그대로
        #expect(store.frameChangeReportsSuppressed(at: rig.clock.uptime))
        // 확인됨: 점수가 바뀌어도 체크포인트(직전 보고 + 3초) 전엔 보고 0 · 3초에 한 번.
        let reportsBefore = rig.reportCount
        rig.hop()
        await pump(lastReportAt + 2.9 - rig.clock.uptime, score: 52)
        #expect(store.duel?.game.score == 1)
        #expect(rig.reportCount == reportsBefore)
        await pump(0.15, score: 52)
        #expect(rig.reportCount == reportsBefore + 1)
        #expect(channel.sent.count >= 3)
        // 끊김 → 곧바로 대체 길: 점수 변화가 1초 뒤 보고된다(기준선: 확인 중엔 위처럼 0).
        channel.deliver(.transport(.closed(code: nil)))
        #expect(store.frameSocketOpen == false)
        #expect(store.frameChangeReportsSuppressed(at: rig.clock.uptime) == false)
        let afterDrop = rig.reportCount
        rig.hop()
        rig.clock.advance(1.1)
        store.tick()
        await rig.settle()
        #expect(rig.reportCount == afterDrop + 1)
        #expect(store.duel?.game.score == 2)
        // 재시도(1초) 소켓이 다시 열린다 → 끝난 판 응답에서 곧바로 닫는다 · 트랙은 굳힌 값.
        #expect(channel.connects.count == 2)
        #expect(store.frameSocketOpen)
        rig.server.finish(winner: CDRig.rival, reason: "goal", finalMe: 2, finalOpponent: 100)
        rig.clock.advance(3.1)
        store.tick()
        await rig.settle()
        #expect(store.match?.isFinished == true)
        #expect(store.frameSocketOpen == false)
        #expect(channel.disconnects == 2)
        #expect(store.raceSnapshot()?.opponentScore == 100)
        #expect(store.match?.outcome == .loss)
    }

    @Test("키가 없으면(1차 서버 · frames null) 소켓을 열지 않고 대체 길 report_ms 로 돈다 — 켜진 판은 연다(기준선)")
    @MainActor
    func missingFramesKeyFallsBack() async {
        // 없으면: 1차 서버 응답(키 없음)을 '켜짐'으로 잘못 읽거나 nil 을 못 견디면 판이 열리지 않는다.
        let off = CDRig.make("frames-missing", frames: .missing)
        await off.startPlaying()
        #expect(off.channel.connects.isEmpty)
        #expect(off.store.frameSocketOpen == false)
        #expect(off.store.frameReportInterval(at: off.clock.uptime) == 2.0)      // 1차 서버 기본 report_ms 2000
        let before = off.reportCount
        off.hop()
        off.clock.advance(2.0)
        off.store.tick()
        await off.settle()
        #expect(off.reportCount == before + 1)
        let on = CDRig.make("frames-on-baseline", frames: .on)
        await on.startPlaying()
        #expect(on.channel.connects.count == 1)
    }
}
