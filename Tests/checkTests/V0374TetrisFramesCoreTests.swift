import Foundation
import Testing
@testable import CheckCore

// 테트리스 대결 Broadcast 전환 — 공용 코어의 **순수 부분**(명세 docs/plan/tetris-broadcast/SPEC.md §16 단위 항목).
// 판 표시 프레임 장부(`TetrisFrameLink`) · 프레임 본문(`TetrisFrame`) · Phoenix 송수신 조립(`RealtimeFrame`) · 와이어(`TetrisWire`) ·
// 보고 주기 인자(`TetrisDuelSession.reportReason(at:heartbeat:)`). 스토어 배선 · 실제 소켓 · 두 대 왕복은 여기서 재지 않는다
// (스텁이 못 잡는 것 — 메모리 stub-tests-hide-roundtrip-bugs). 시계는 전부 주입(로컬 단조 초)이고 지터는 항등이다.
//
// 각 시험의 첫 줄 주석은 **"없으면 어떤 결함이 초록으로 통과하는가"** 다(관례). 조건 하나를 지워도 다른 조건이 같은 결론(1초)을 내
// 시험이 초록인 일을 막으려고, 주기만 보지 않고 **어느 조건이 떨어졌는지**(`conditions(at:)` 의 칸)와 **되살아나는 데 프레임 몇 장이
// 드는지**를 함께 잰다.

private let fcMe = "00000000-0000-4000-8000-0000000000a1"
private let fcRival = "00000000-0000-4000-8000-0000000000b2"
private let fcThird = "00000000-0000-4000-8000-0000000000c3"
private let fcMatch = "7e7e0000-0000-4000-8000-000000000374"
private let fcTopic = "tetris:" + fcMatch
private let fcBase = 1_800_000_000_000
private func fcIdentity(_ ceiling: Double) -> Double { ceiling }

/// 상대가 보낸 프레임 한 장(판은 빈 판 — 모양 검사를 통과하는 가장 단순한 값).
private func fcFrame(f: Int, s: Int = 1, g: Int = 0, h: Int = 0, sender: String = fcRival,
                     board: String = TetrisDuelBoard.emptyText, lines: Int = 0, pending: Int = 0) -> TetrisFrame {
    TetrisFrame(sender: sender, seq: s, frame: f, board: board, lines: lines, attackSent: g, pending: pending, heardAgoMs: h)
}

/// 서버가 켜고(`state.frames`) 소켓이 join 된 링크.
private func fcJoinedLink(at t: TimeInterval = 0) -> TetrisFrameLink {
    var link = TetrisFrameLink(me: fcMe, opponent: fcRival, frameBase: fcBase)
    link.noteServerFrames(TetrisFramesRow(on: true, topic: fcTopic))
    let open = link.socketCommand(at: t, matchStartedAt: nil, jitter: fcIdentity)
    #expect(open == .connect(topic: fcTopic, refreshToken: false), "전제: 서버가 켜면 곧바로 연다")
    #expect(link.apply(.joined, at: t, jitter: fcIdentity) == .none)
    #expect(link.socket == .joined)
    return link
}

/// 상대 프레임을 1초 간격으로 `count` 장 받는다(h 는 0 — 상대가 내 프레임을 듣는다). 다음 프레임 번호를 돌려준다.
@discardableResult
private func fcFeed(_ link: inout TetrisFrameLink, count: Int, from t: TimeInterval, f: Int, s: Int = 1,
                    g: Int = 0, h: Int = 0) -> Int {
    var next = f
    for i in 0..<count {
        #expect(link.receive(fcFrame(f: next, s: s, g: g, h: h), at: t + Double(i)) == nil, "프레임 f=\(next) 를 버렸다")
        next += 1
    }
    return next
}

/// 서버 켬 · join · 프레임 3장(1·2·3초) → 3초 체크포인트에 올라선 링크. 마지막 프레임은 3초에 받았다.
private func fcSteadyLink() -> (link: TetrisFrameLink, nextF: Int) {
    var link = fcJoinedLink()
    let next = fcFeed(&link, count: 3, from: 1, f: 100)
    #expect(link.reportInterval(at: 3) == TetrisFrameLink.checkpointSeconds, "전제: 프레임 3장이면 3초다")
    return (link, next)
}

/// 와이어를 한 번 지난 본문(정수는 NSNumber 로, 불리언은 CFBoolean 으로) — 받는 쪽이 실제로 보는 모양이다.
private func fcWire(_ payload: [String: Any]) -> [String: Any] {
    let data = try! JSONSerialization.data(withJSONObject: payload)
    return try! JSONSerialization.jsonObject(with: data) as! [String: Any]
}

private func fcJSON(_ text: String) -> [String: Any] {
    (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] ?? [:]
}

private func fcDecode(_ payload: [String: Any]) -> TetrisFrameRejection? {
    switch TetrisFrame.decode(payload: fcWire(payload)) {
    case .success: return nil
    case .failure(let rejection): return rejection
    }
}

@Suite("v0.3.74 테트리스 프레임 — 공용 코어(순수)")
struct V0374TetrisFramesCoreTests {

    // MARK: - §5 조건 7개 → 보고 주기

    @Test("조건 7 — 상승은 프레임 3장 연속: 1·2장은 1초(조건 1~6 은 이미 참) · 3장째 3초")
    func checkpointNeedsThreeSteadyFrames() {
        // 없으면: 프레임 한 장만 와도 3초로 올라 한쪽 방향 단절·첫 쓰기 거절을 확인하기 전에 보고가 준다.
        var link = fcJoinedLink()
        #expect(link.reportInterval(at: 0.5) == 1, "프레임이 오기 전에 3초다")
        link.receive(fcFrame(f: 100), at: 1)
        var c = link.conditions(at: 1)
        #expect(c.serverOn && c.joined && c.heardRecently && c.opponentHearsMe && c.reportsHealthy && c.noWatchers)
        #expect(!c.steady && link.reportInterval(at: 1) == 1)
        link.receive(fcFrame(f: 101), at: 2)
        #expect(link.reportInterval(at: 2) == 1, "2장으로 3초에 올랐다(3장 연속이 아니다)")
        link.receive(fcFrame(f: 102), at: 3)
        c = link.conditions(at: 3)
        #expect(c.steady && c.allHold)
        #expect(link.reportInterval(at: 3) == 3 && TetrisFrameLink.checkpointSeconds == 3 && TetrisFrameLink.fallbackSeconds == 1)
    }

    @Test("조건 1 — 서버 스위치가 꺼지면 즉시 1초 · 다시 켜져도 프레임 3장을 새로 모은다")
    func serverSwitchOffFallsBackImmediately() {
        // 없으면: 롤백 1단계(서버 스위치)가 이미 3초에 올라선 판을 못 내린다 — 앱 업데이트 없이 되돌린다는 약속이 깨진다.
        var (link, f) = fcSteadyLink()
        link.noteServerFrames(nil)
        #expect(link.reportInterval(at: 3.1) == 1)
        #expect(!link.conditions(at: 3.1).serverOn && link.conditions(at: 3.1).joined, "다른 조건이 아니라 조건 1 이 떨어뜨려야 한다")
        // 꺼진 동안 온 프레임은 연속에 안 친다.
        f = fcFeed(&link, count: 3, from: 4, f: f)
        #expect(link.reportInterval(at: 6) == 1)
        link.noteServerFrames(TetrisFramesRow(on: true, topic: fcTopic))
        #expect(link.reportInterval(at: 6.1) == 1, "다시 켜지자마자 3초다(3장을 다시 모으지 않았다)")
        f = fcFeed(&link, count: 2, from: 7, f: f)
        #expect(link.reportInterval(at: 8) == 1)
        fcFeed(&link, count: 1, from: 9, f: f)
        #expect(link.reportInterval(at: 9) == 3)
        // on 이 거짓이거나 토픽이 없으면 꺼짐이다.
        link.noteServerFrames(TetrisFramesRow(on: false, topic: fcTopic))
        #expect(!link.conditions(at: 9).serverOn)
        link.noteServerFrames(TetrisFramesRow(on: true, topic: nil))
        #expect(!link.conditions(at: 9).serverOn)
    }

    @Test("조건 2 — 소켓이 닫히면 즉시 1초 · 다시 join 해도 프레임 3장을 새로 모은다")
    func socketCloseFallsBackImmediately() {
        // 없으면: 소켓이 죽은 채 3초 보고가 이어져 상대 표시가 3초로 벌어진다(Realtime 전체 장애 행).
        var (link, f) = fcSteadyLink()
        #expect(link.apply(.closed(code: nil), at: 3.2, jitter: fcIdentity) == .disconnect)
        #expect(link.reportInterval(at: 3.2) == 1)
        let c = link.conditions(at: 3.2)
        #expect(!c.joined && c.serverOn && c.heardRecently && c.opponentHearsMe, "조건 2 만 떨어져야 한다")
        #expect(link.socketCommand(at: 4.2, matchStartedAt: 0, jitter: fcIdentity) == .connect(topic: fcTopic, refreshToken: false))
        #expect(link.apply(.joined, at: 4.3, jitter: fcIdentity) == .none)
        f = fcFeed(&link, count: 2, from: 4.5, f: f)
        #expect(link.reportInterval(at: 5.5) == 1, "다시 붙자마자 3초다")
        fcFeed(&link, count: 1, from: 6.5, f: f)
        #expect(link.reportInterval(at: 6.5) == 3)
    }

    @Test("조건 3 — 상대 프레임을 받은 지 2.5초까지 3초 · 넘으면 즉시 1초 · 틈 뒤 프레임은 1장부터 다시 센다")
    func silenceBeyondTwoAndAHalfSecondsFallsBack() {
        // 없으면: 상대 프레임이 끊겨도 3초 보고가 이어져 상대 판이 최대 3초 옛것으로 남는다(사용자 제약 "2초로 늘리지 않는다").
        var (link, f) = fcSteadyLink()       // 마지막 프레임 3초
        #expect(link.reportInterval(at: 5.5) == 3, "경계 2.5초는 포함이다")
        #expect(link.reportInterval(at: 5.51) == 1)
        let c = link.conditions(at: 5.51)
        #expect(!c.heardRecently && c.opponentHearsMe && c.steady, "조건 3 만 떨어져야 한다")
        // 3초 틈 뒤 첫 프레임: 연속이 끊겼다.
        f = fcFeed(&link, count: 1, from: 6.0, f: f)
        #expect(link.reportInterval(at: 6.0) == 1)
        f = fcFeed(&link, count: 1, from: 7.0, f: f)
        #expect(link.reportInterval(at: 7.0) == 1)
        fcFeed(&link, count: 1, from: 8.0, f: f)
        #expect(link.reportInterval(at: 8.0) == 3)
    }

    @Test("조건 4 — 상대의 h 가 0~2500 일 때만 3초 · -1(못 들음)·2501 은 즉시 1초 · 되살리려면 3장")
    func oneWayLinkFallsBack() {
        // 없으면: 한쪽 방향만 살아 있는 판(상대는 내 프레임을 못 듣는다)에서 나는 3초로 줄여 상대 표시가 3초로 벌어진다.
        var (link, f) = fcSteadyLink()
        link.receive(fcFrame(f: f, h: 2_500), at: 4)
        f += 1
        #expect(link.reportInterval(at: 4) == 3, "경계 2500 은 포함이다")
        link.receive(fcFrame(f: f, h: 2_501), at: 5)
        f += 1
        #expect(link.reportInterval(at: 5) == 1)
        let c = link.conditions(at: 5)
        #expect(!c.opponentHearsMe && c.heardRecently && c.joined, "조건 4 만 떨어져야 한다(조건 7 은 그 결과로 0)")
        link.receive(fcFrame(f: f, h: -1), at: 6)
        f += 1
        #expect(link.reportInterval(at: 6) == 1 && !link.conditions(at: 6).opponentHearsMe)
        f = fcFeed(&link, count: 2, from: 7, f: f)
        #expect(link.reportInterval(at: 8) == 1, "좋은 프레임 2장으로 3초에 올랐다")
        fcFeed(&link, count: 1, from: 9, f: f)
        #expect(link.reportInterval(at: 9) == 3)
    }

    @Test("조건 5 — 보고 실패 streak 가 0 이 아니면 즉시 1초 · 실패 중 온 프레임은 안 친다 · 회복 뒤 3장")
    func reportFailureFallsBack() {
        // 없으면: 공격 보고가 실패·멎었는데 재시도가 3초 뒤로 밀린다 — makeReport 가 실패 전에 누계를 올려 재시도가 "공격" 사유로 안 잡힌다(§6).
        var (link, f) = fcSteadyLink()
        link.noteReportFailureStreak(1)
        #expect(link.reportInterval(at: 3.1) == 1)
        #expect(!link.conditions(at: 3.1).reportsHealthy && link.conditions(at: 3.1).heardRecently)
        f = fcFeed(&link, count: 3, from: 4, f: f)
        #expect(link.reportInterval(at: 6) == 1, "실패 중에도 3초다")
        link.noteReportFailureStreak(0)
        #expect(link.reportInterval(at: 6.1) == 1, "실패 중 받은 프레임으로 회복하자마자 3초다")
        f = fcFeed(&link, count: 2, from: 7, f: f)
        #expect(link.reportInterval(at: 8) == 1)
        f = fcFeed(&link, count: 1, from: 9, f: f)
        #expect(link.reportInterval(at: 9) == 3)
        // 프레임 사이에 실패했다 곧바로 회복해도(다음 프레임 전) 다시 3장이다.
        link.noteReportFailureStreak(2)
        link.noteReportFailureStreak(0)
        #expect(link.reportInterval(at: 9.5) == 1, "프레임 사이의 실패를 놓쳤다")
        _ = f
    }

    @Test("조건 6 — 관전자가 붙으면 즉시 1초(D2) · 떠나도 프레임 3장")
    func watchersFallBack() {
        // 없으면: 관전자가 보는 판의 DB 판이 3초 옛것이 된다(관전은 DB 를 읽는다 — tetris_watch_live).
        var (link, f) = fcSteadyLink()
        link.noteWatchers(1)
        #expect(link.reportInterval(at: 3.1) == 1)
        #expect(!link.conditions(at: 3.1).noWatchers && link.conditions(at: 3.1).reportsHealthy)
        f = fcFeed(&link, count: 3, from: 4, f: f)
        #expect(link.reportInterval(at: 6) == 1)
        link.noteWatchers(0)
        #expect(link.reportInterval(at: 6.1) == 1)
        f = fcFeed(&link, count: 2, from: 7, f: f)
        #expect(link.reportInterval(at: 8) == 1)
        fcFeed(&link, count: 1, from: 9, f: f)
        #expect(link.reportInterval(at: 9) == 3)
    }

    // MARK: - 프레임 시각표

    @Test("시각표 — 시작 전·탑아웃 뒤(live 거짓)·join 전·서버 끔·끝난 판엔 없음 · 첫 장 곧바로 · 그 뒤 1초")
    func frameScheduleGates() {
        // 없으면: 카운트다운 중이나 탑아웃 뒤에도 프레임이 나가 이벤트 한도를 태운다(탑아웃은 RPC 로 곧바로 간다).
        var joined = fcJoinedLink()
        #expect(!joined.frameDue(at: 10, live: false, attackSent: 0), "카운트다운·탑아웃 뒤에 보낸다")
        #expect(joined.frameDue(at: 10, live: true, attackSent: 0), "살아 있는 판의 첫 프레임이 곧바로 안 나간다")
        var notJoined = TetrisFrameLink(me: fcMe, opponent: fcRival, frameBase: fcBase)
        notJoined.noteServerFrames(TetrisFramesRow(on: true, topic: fcTopic))
        _ = notJoined.socketCommand(at: 0, matchStartedAt: nil, jitter: fcIdentity)
        #expect(notJoined.socket == .connecting && !notJoined.frameDue(at: 10, live: true, attackSent: 0), "join 전에 보낸다")
        var off = fcJoinedLink()
        off.noteServerFrames(nil)
        #expect(!off.frameDue(at: 10, live: true, attackSent: 0), "서버가 끈 판에 보낸다")
        var done = fcJoinedLink()
        #expect(done.finish() == .disconnect)
        #expect(!done.frameDue(at: 10, live: true, attackSent: 0), "끝난 판에 보낸다")

        let first = joined.makeFrame(at: 10, seq: 4, board: TetrisDuelBoard.emptyText, lines: 0, attackSent: 0, pending: 0)
        #expect(first.frame == fcBase && first.sender == fcMe && first.seq == 4 && first.version == 1)
        #expect(!joined.frameDue(at: 10.99, live: true, attackSent: 0))
        #expect(joined.frameDue(at: 11.0, live: true, attackSent: 0))
        let second = joined.makeFrame(at: 11, seq: 4, board: TetrisDuelBoard.emptyText, lines: 0, attackSent: 0, pending: 0)
        #expect(second.frame == fcBase + 1, "프레임 번호가 1씩 오르지 않는다")
    }

    @Test("시각표 — 공격 누계가 늘면 1초를 안 기다린다(최소 0.25초) · 같은 누계로는 다시 곧바로 안 보낸다")
    func attackFramesGoEarly() {
        // 없으면: 공격 표시가 최대 1초 늦거나(즉시 가지 없음), 같은 누계로 0.25초마다 프레임이 나간다(기준 갱신 없음).
        var link = fcJoinedLink()
        _ = link.makeFrame(at: 20, seq: 1, board: TetrisDuelBoard.emptyText, lines: 0, attackSent: 0, pending: 0)
        #expect(!link.frameDue(at: 20.24, live: true, attackSent: 4), "최소 간격 0.25초를 안 지켰다")
        #expect(link.frameDue(at: 20.25, live: true, attackSent: 4))
        let attack = link.makeFrame(at: 20.25, seq: 2, board: TetrisDuelBoard.emptyText, lines: 4, attackSent: 4, pending: 0)
        #expect(attack.attackSent == 4 && attack.lines == 4)
        #expect(!link.frameDue(at: 20.6, live: true, attackSent: 4), "같은 누계로 또 곧바로 보낸다")
        #expect(link.frameDue(at: 21.25, live: true, attackSent: 4))
    }

    @Test("시각표 — 10초 판 루프(1/16초 걸음): 공격 없으면 1초마다 · 공격이 매 걸음이면 0.25초마다 · 어떤 1초 창에도 4장 이하")
    func frameRateStaysWithinTheCap() {
        // 없으면: 판 루프 걸음마다 프레임이 나가 초당 이벤트(프로젝트 전체 한도 100)를 판 하나가 16씩 태운다.
        // 걸음은 2진수로 딱 떨어지는 1/16초다(실제 판 루프는 약 0.05초) — 경계(0.25 · 1.0)가 부동소수 오차 없이 맞아야 장수를 못 박는다.
        func run(_ link: inout TetrisFrameLink, attackEveryTick: Bool) -> [TimeInterval] {
            var sent: [TimeInterval] = []
            for i in 0...160 {
                let t = 30 + Double(i) / 16
                let attack = attackEveryTick ? i : 0
                if link.frameDue(at: t, live: true, attackSent: attack) {
                    _ = link.makeFrame(at: t, seq: 1, board: TetrisDuelBoard.emptyText, lines: 0, attackSent: attack, pending: 0)
                    sent.append(t)
                }
            }
            return sent
        }
        func maxInAnyWindow(_ times: [TimeInterval]) -> Int {
            times.map { start in times.filter { $0 >= start && $0 < start + 1.0 - 1e-9 }.count }.max() ?? 0
        }
        var calm = fcJoinedLink()
        let calmTimes = run(&calm, attackEveryTick: false)
        let calmGaps = zip(calmTimes.dropFirst(), calmTimes).map { $0 - $1 }
        #expect(calmTimes.count == 11, "10초에 \(calmTimes.count)장(기대 11 — 0초 포함 1초마다)")
        #expect(calmGaps.allSatisfy { $0 == 1.0 }, "간격 \(calmGaps)")

        var busy = fcJoinedLink()
        let busyTimes = run(&busy, attackEveryTick: true)
        let busyGaps = zip(busyTimes.dropFirst(), busyTimes).map { $0 - $1 }
        #expect(busyGaps.allSatisfy { $0 == 0.25 }, "간격 \(busyGaps)")
        #expect(maxInAnyWindow(busyTimes) == 4 && busyTimes.count == 41, "\(busyTimes.count)장 · 창 최대 \(maxInAnyWindow(busyTimes))")
    }

    @Test("시각표 — 초당 4장 상한은 최소 간격과 따로 선다(간격을 1/16초로 줄여도 1초 창에 4장)")
    func perSecondCapIsIndependentOfTheGap() {
        // 없으면: D9(하드드롭마다 프레임)로 간격을 줄이는 날 상한도 같이 사라진다 — 상한이 간격에서 파생된 값일 뿐이면 이 시험이 빨갛다.
        var link = fcJoinedLink()
        link.minFrameGapSeconds = 1.0 / 16
        var sent: [TimeInterval] = []
        for i in 0...32 {
            let t = 40 + Double(i) / 16
            if link.frameDue(at: t, live: true, attackSent: i) {
                _ = link.makeFrame(at: t, seq: 1, board: TetrisDuelBoard.emptyText, lines: 0, attackSent: i, pending: 0)
                sent.append(t)
            }
        }
        // 처음 넷은 1/16초 간격(간격을 줄인 효과) · 다섯째는 첫 장에서 정확히 1초 뒤 — 그 사이 12걸음은 상한이 막았다.
        #expect(sent == [40, 40.0625, 40.125, 40.1875, 41, 41.0625, 41.125, 41.1875, 42], "보낸 시각 \(sent)")
    }

    @Test("h — 상대 프레임을 받은 적 없으면 -1 · 받았으면 그 뒤 흐른 ms")
    func heardAgoIsMeasuredFromTheLastAcceptedFrame() {
        // 없으면: 상대의 조건 4 가 영영 거짓이거나(언제나 -1) 언제나 참이다(언제나 0) — 양방향 확인이 죽는다.
        var link = fcJoinedLink()
        #expect(link.makeFrame(at: 1, seq: 1, board: TetrisDuelBoard.emptyText, lines: 0, attackSent: 0, pending: 0).heardAgoMs == -1)
        link.receive(fcFrame(f: 100), at: 5)
        #expect(link.makeFrame(at: 5.3, seq: 1, board: TetrisDuelBoard.emptyText, lines: 0, attackSent: 0, pending: 0).heardAgoMs == 300)
        link.receive(fcFrame(f: 99), at: 6)   // 버린 프레임은 h 의 기준을 안 옮긴다
        #expect(link.makeFrame(at: 7, seq: 1, board: TetrisDuelBoard.emptyText, lines: 0, attackSent: 0, pending: 0).heardAgoMs == 2_000)
        // 대문자 uuid 로 만들어도 `u` 는 소문자다(Postgres uuid 와 같은 꼴).
        var upper = TetrisFrameLink(me: fcMe.uppercased(), opponent: fcRival.uppercased(), frameBase: 7)
        #expect(upper.makeFrame(at: 0, seq: 0, board: TetrisDuelBoard.emptyText, lines: 0, attackSent: 0, pending: 0).sender == fcMe)
        #expect(upper.receive(fcFrame(f: 1), at: 0) == nil, "상대 uuid 를 대소문자로 가른다")
    }

    // MARK: - 순서 · 재개

    @Test("순서 — 중복·뒤집힘은 버리고 표시 불변 · f 가 크면 받는다 · 시계를 돌려 f 가 작아도 s 가 크면 받는다")
    func orderingRule() {
        // 없으면: 늦게 닿은 옛 프레임이 상대 판을 되감거나, 시계를 뒤로 돌린 상대의 프레임을 판 끝까지 버린다.
        var link = fcJoinedLink()
        #expect(link.receive(fcFrame(f: 100, s: 5, g: 1), at: 1) == nil)
        #expect(link.receive(fcFrame(f: 101, s: 5, g: 2, lines: 3), at: 2) == nil)
        let kept = link
        #expect(link.receive(fcFrame(f: 101, s: 5, g: 2, lines: 3), at: 2.1) == .stale, "중복을 받았다")
        #expect(link.receive(fcFrame(f: 100, s: 5, g: 9, lines: 1), at: 2.2) == .stale, "뒤집힌 옛 프레임을 받았다")
        #expect(link == kept, "버린 프레임이 장부를 바꿨다")
        #expect(link.lastFrame?.lines == 3)
        // 시계를 뒤로 돌린 상대: f 는 작지만 s 가 크다.
        #expect(link.receive(fcFrame(f: 50, s: 6), at: 3) == nil)
        #expect(link.lastFrame?.frame == 50 && link.lastFrame?.seq == 6)
    }

    @Test("재개 첫 프레임 — 다시 연 프로세스의 s 가 옛 프레임 이하여도 f(벽시계 시작)로 첫 장부터 통과")
    func resumedSenderPassesOnItsFirstFrame() {
        // 없으면((s, f) 사전식 · 프로세스마다 f=1): 재개한 상대의 프레임이 최대 2보고 동안 버려져 상대 판이 멈춘다(§4).
        var sender = TetrisFrameLink(me: fcRival, opponent: fcMe, frameBase: 1_800_000_000_000)
        var receiver = fcJoinedLink()
        for i in 0..<5 {
            let frame = sender.makeFrame(at: Double(i), seq: 7, board: TetrisDuelBoard.emptyText, lines: i, attackSent: 0, pending: 0)
            #expect(receiver.receive(frame, at: Double(i)) == nil)
        }
        // 앞 프로세스의 마지막 보고(seq 7)가 저장되지 못했다 — 재개한 프로세스는 DB 의 seq 5 에서 잇는다. 5초 뒤 새 링크.
        var resumed = TetrisFrameLink(me: fcRival, opponent: fcMe, frameBase: 1_800_000_005_000)
        let first = resumed.makeFrame(at: 10, seq: 5, board: TetrisDuelBoard.emptyText, lines: 2, attackSent: 0, pending: 0)
        #expect(first.seq < 7)
        #expect(receiver.receive(first, at: 10) == nil, "재개 첫 프레임을 버렸다")
        #expect(receiver.lastFrame?.lines == 2)
    }

    // MARK: - 깨진 프레임

    @Test("깨진 프레임 거부 — 판 글자 수·글자 집합 · v · 타입(문자열·불리언·소수·음수·누락) · 모르는 키 id 는 무시")
    func malformedFramesAreRejected() {
        // 없으면: 깨진 판이 상대 화면에 그려지거나(200글자 아님), `true` 가 1 로 읽혀 위조 프레임이 순서 판정을 통과한다.
        var link = TetrisFrameLink(me: fcRival, opponent: fcMe, frameBase: 1_800_000_000_000)
        let good = link.makeFrame(at: 0, seq: 3, board: TetrisDuelBoard.emptyText, lines: 2, attackSent: 1, pending: 4).payload
        #expect(fcDecode(good) == nil)
        if case .success(let frame) = TetrisFrame.decode(payload: fcWire(good)) {
            #expect(frame.seq == 3 && frame.lines == 2 && frame.attackSent == 1 && frame.pending == 4 && frame.heardAgoMs == -1)
        } else {
            Issue.record("정상 프레임을 버렸다")
        }
        func with(_ key: String, _ value: Any?) -> [String: Any] {
            var payload = good
            payload[key] = value
            return payload
        }
        let empty = TetrisDuelBoard.emptyText
        let cases: [(String, [String: Any], TetrisFrameRejection?)] = [
            ("v 2", with("v", 2), .unknownVersion),
            ("v 문자열", with("v", "1"), .malformed),
            ("v 없음", with("v", nil), .malformed),
            ("b 199", with("b", String(empty.dropLast())), .invalidBoard),
            ("b 201", with("b", empty + "."), .invalidBoard),
            ("b 모르는 글자", with("b", "X" + String(empty.dropFirst())), .invalidBoard),
            ("b 소문자", with("b", "i" + String(empty.dropFirst())), .invalidBoard),
            ("b 숫자", with("b", 5), .malformed),
            ("s 문자열", with("s", "5"), .malformed),
            ("f 불리언", with("f", true), .malformed),
            ("g 소수", with("g", 1.5), .malformed),
            ("l 음수", with("l", -1), .malformed),
            ("h -2", with("h", -2), .malformed),
            ("p 없음", with("p", nil), .malformed),
            ("u 빈 글자", with("u", ""), .malformed),
            ("u 숫자", with("u", 7), .malformed),
            ("realtime 이 덧붙인 id", with("id", "abc"), nil),
            ("h -1 은 정상", with("h", -1), nil),
        ]
        for (label, payload, expected) in cases {
            #expect(fcDecode(payload) == expected, "\(label): \(String(describing: fcDecode(payload)))")
        }
    }

    @Test("깨진 프레임 거부 — 상대가 아닌 u · 깨진 JSON · 다른 토픽 · 본문이 객체가 아님 · 버린 프레임은 장부 불변")
    func foreignAndBrokenTextIsIgnored() {
        // 없으면: 제3자(같은 토픽에 쓸 수 없지만 u 는 위조 가능)의 판이 상대 자리에 그려지거나, 깨진 텍스트가 링크를 흔든다.
        var link = fcJoinedLink()
        let before = link
        #expect(link.receive(fcFrame(f: 100, sender: fcThird), at: 1) == .notOpponent)
        #expect(link.receive(fcFrame(f: 100, sender: fcMe), at: 1) == .notOpponent, "내 프레임(self:false 위반 · 에코)을 상대 것으로 받았다")
        #expect(link == before)
        let wire = RealtimeFrame.broadcast(channel: fcTopic, event: TetrisFrame.event, payload: fcFrame(f: 1).payload,
                                           ref: "3", joinRef: "1")
        #expect(RealtimeFrame.decodeBroadcastPayload(text: String(wire.dropLast()), channel: fcTopic) == nil, "깨진 JSON")
        #expect(RealtimeFrame.decodeBroadcastPayload(text: wire, channel: "tetris:00000000-0000-4000-8000-000000000999") == nil,
                "다른 판의 토픽")
        let notObject = #"{"topic":"realtime:\#(fcTopic)","event":"broadcast","payload":{"type":"broadcast","event":"frame","payload":"x"}}"#
        #expect(RealtimeFrame.decodeBroadcastPayload(text: notObject, channel: fcTopic) == nil)
        let reply = #"{"topic":"realtime:\#(fcTopic)","event":"phx_reply","ref":"1","payload":{"status":"ok","response":{}}}"#
        #expect(RealtimeFrame.decodeBroadcastPayload(text: reply, channel: fcTopic) == nil)
    }

    // MARK: - Phoenix 송수신 · 기존 decode 계약

    @Test("송신 봉투 — vsn 1.0.0 객체형 · 받는 쪽이 같은 프레임으로 되읽는다 · 기존 decode 는 여전히 이름만(.broadcast(event:))")
    func broadcastEnvelopeRoundTripsWithoutTouchingDecode() throws {
        // 없으면: 새 함수가 기존 decode 의 `.broadcast(event:)` 계약을 바꾸거나(초인종 경로 전체), 보낸 봉투를 받는 쪽이 못 읽는다.
        var sender = TetrisFrameLink(me: fcRival, opponent: fcMe, frameBase: 1_800_000_000_000)
        let frame = sender.makeFrame(at: 0, seq: 9, board: "IJLOSTZG.." + String(TetrisDuelBoard.emptyText.dropFirst(10)),
                                     lines: 12, attackSent: 5, pending: 2)
        let text = RealtimeFrame.broadcast(channel: fcTopic, event: TetrisFrame.event, payload: frame.payload, ref: "7", joinRef: "1")
        let object = fcJSON(text)
        #expect(object["topic"] as? String == "realtime:" + fcTopic && object["event"] as? String == "broadcast")
        #expect(object["ref"] as? String == "7" && object["join_ref"] as? String == "1")
        let envelope = try #require(object["payload"] as? [String: Any])
        #expect(envelope["type"] as? String == "broadcast" && envelope["event"] as? String == "frame")
        let body = try #require(envelope["payload"] as? [String: Any])
        #expect(Set(body.keys) == ["v", "u", "s", "f", "b", "l", "g", "p", "h"], "키 \(body.keys.sorted())")

        // 받는 쪽: 이름과 본문 → 같은 프레임.
        let parsed = try #require(RealtimeFrame.decodeBroadcastPayload(text: text, channel: fcTopic))
        #expect(parsed.event == "frame")
        #expect(try TetrisFrame.decode(payload: parsed.payload).get() == frame)
        // 기존 decode: 이름만 넘긴다(바뀌면 초인종 링이 흔들린다). 다른 토픽은 여전히 nil.
        #expect(RealtimeFrame.decode(text: text, channel: fcTopic, joinRef: "1") == .broadcast(event: "frame"))
        #expect(RealtimeFrame.decode(text: text, channel: "poke:me", joinRef: "1") == nil)
        // V0360 의 초인종 프레임은 그대로 이름만.
        let poke = #"{"topic":"realtime:poke:me","event":"broadcast","payload":{"event":"tetris","type":"broadcast","payload":{"v":1,"m":"x","s":4,"id":"y"}}}"#
        #expect(RealtimeFrame.decode(text: poke, channel: "poke:me", joinRef: "1") == .broadcast(event: "tetris"))
        // 판 토픽 join 도 기존 함수 그대로: private · self:false · ack:false.
        let join = fcJSON(RealtimeFrame.join(channel: fcTopic, accessToken: "tok", isPrivate: true, ref: "1"))
        let config = try #require((join["payload"] as? [String: Any])?["config"] as? [String: Any])
        let broadcast = try #require(config["broadcast"] as? [String: Any])
        #expect(join["topic"] as? String == "realtime:" + fcTopic && config["private"] as? Bool == true)
        #expect(broadcast["self"] as? Bool == false && broadcast["ack"] as? Bool == false)
    }

    // MARK: - p_protocol 은 보고에만 2

    @Test("p_protocol — tetris_report 만 프레임 켠 기기에서 2 · 다른 요청과 기본값은 1 · 키 집합 불변")
    func framesProtocolOnlyOnReports() throws {
        // 없으면: protocolVersion 상수를 올려 아홉 요청이 2 를 싣거나, 프레임을 못 여는 기기가 2 를 보내 상대가 헛되이 소켓을 연다.
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        func keys(_ value: some Encodable) throws -> [String: Any] {
            try JSONSerialization.jsonObject(with: encoder.encode(value)) as? [String: Any] ?? [:]
        }
        let report = TetrisDuelReport(seq: 7, board: TetrisDuelBoard.emptyText, lines: 3, garbageSent: 2,
                                      garbageApplied: 1, pending: 4, toppedOut: false)
        let plain = try keys(TetrisReportRequest(matchID: fcMatch, report: report))
        let capable = try keys(TetrisReportRequest(matchID: fcMatch, report: report, framesCapable: true))
        let notCapable = try keys(TetrisReportRequest(matchID: fcMatch, report: report, framesCapable: false))
        #expect(plain["p_protocol"] as? Int == 1 && notCapable["p_protocol"] as? Int == 1)
        #expect(capable["p_protocol"] as? Int == 2)
        #expect(Set(capable.keys) == Set(plain.keys) && plain.count == 9)
        #expect(TetrisWire.protocolVersion == 1 && TetrisWire.framesProtocolVersion == 2)
        #expect(try keys(TetrisProtocolRequest())["p_protocol"] as? Int == 1)
        #expect(try keys(TetrisChallengeRequest(pOpponent: fcRival, pStake: 3))["p_protocol"] as? Int == 1)
        #expect(try keys(TetrisMatchRequest(pMatchId: fcMatch))["p_protocol"] as? Int == 1)
        #expect(try keys(TetrisRespondRequest(pMatchId: fcMatch, pAccept: true))["p_protocol"] as? Int == 1)
    }

    @MainActor
    @Test("p_protocol — 서비스 호출이 플래그를 본문까지 옮긴다 · 응답의 frames 를 서비스 디코더(snake→camel)가 읽는다")
    func serviceCarriesTheFlagAndDecodesFrames() async throws {
        // 없으면: 요청 타입은 맞는데 서비스 함수가 플래그를 버려(호출 자리) 서버 frames_v 가 영영 0 — 프레임이 한 번도 안 켜진다.
        let host = "v0374-tf-\(UUID().uuidString.prefix(8))".lowercased()
        GomokuStubProtocol.register(host: host) { rpc, _, _ in
            switch rpc {
            case "tetris_report", "tetris_state":
                return GomokuStubProtocol.Reply(body: #"{"status":"ok","state":{"match_id":"\#(fcMatch)","status":"active","watchers":0,"frames":{"on":true,"topic":"\#(fcTopic)","later":1}}}"#)
            default:
                return nil
            }
        }
        let service = SupabaseWorkService(projectURL: URL(string: "http://\(host)")!, anonKey: "anon-test-key",
                                          session: GomokuStubProtocol.session())
        let report = TetrisDuelReport(seq: 1, board: TetrisDuelBoard.emptyText, lines: 0, garbageSent: 0,
                                      garbageApplied: 0, pending: 0, toppedOut: false)
        let capable = try await service.tetrisReport(accessToken: "tok", matchID: fcMatch, report: report, framesCapable: true)
        _ = try await service.tetrisReport(accessToken: "tok", matchID: fcMatch, report: report)
        _ = try await service.tetrisState(accessToken: "tok", matchID: fcMatch)
        let reports = GomokuStubProtocol.calls(host: host, rpc: "tetris_report").map { $0.json["p_protocol"] as? Int }
        #expect(reports == [2, 1], "보고 본문 p_protocol \(reports)")
        #expect(GomokuStubProtocol.calls(host: host, rpc: "tetris_state").first?.json["p_protocol"] as? Int == 1)
        #expect(capable.state?.frames == TetrisFramesRow(on: true, topic: fcTopic))
        #expect(capable.state?.frames?.activeTopic == fcTopic)
    }

    // MARK: - state.frames 디코드

    @Test("state.frames — 없음(옛 서버)·null 은 nil · 모르는 키 무시 · 깨진 칸은 꺼짐이고 상태 디코드는 안 죽는다 · poke: 토픽은 꺼짐")
    func framesRowDecodesDefensively() throws {
        // 없으면: frames 칸 하나가 깨져 오면 판 상태 디코드가 통째로 throw 해 대결 창이 죽는다(TetrisWire 머리말 ①).
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        func state(_ framesJSON: String?) throws -> TetrisStatePayload {
            let tail = framesJSON.map { #","frames":\#($0)"# } ?? ""
            let json = #"{"status":"ok","state":{"match_id":"m","status":"active"\#(tail)}}"#
            let response = try decoder.decode(TetrisActionResponse.self, from: Data(json.utf8))
            return try #require(response.state)
        }
        #expect(try state(nil).frames == nil)
        #expect(try state("null").frames == nil)
        let on = try state(#"{"on":true,"topic":"\#(fcTopic)","extra":[1,2]}"#)
        #expect(on.frames?.activeTopic == fcTopic && on.matchId == "m")
        #expect(try state(#"{"on":false,"topic":"\#(fcTopic)"}"#).frames?.activeTopic == nil)
        #expect(try state(#"{"on":true}"#).frames?.activeTopic == nil)
        let brokenOn = try state(#"{"on":"yes","topic":"\#(fcTopic)"}"#)
        #expect(brokenOn.status == "active" && brokenOn.frames?.activeTopic == nil, "깨진 on 을 켜짐으로 읽었다")
        let notObject = try state(#""on""#)
        #expect(notObject.status == "active" && notObject.frames?.activeTopic == nil)
        #expect(try state(#"{"on":true,"topic":"poke:\#(fcMe)"}"#).frames?.activeTopic == nil, "프레임을 poke: 채널에 쓴다")
        #expect(try state(#"{"on":true,"topic":"tetris:"}"#).frames?.activeTopic == nil)
    }

    // MARK: - 공격 힌트(§6)

    @Test("힌트 — g 가 DB 누계보다 큰 상태 1초 뒤 한 번 · 같은 g 는 판 끝까지 다시 없음 · 새 g 는 다시 1초 · DB 가 따라잡으면 없음")
    func hintFiresOncePerAttackValue() {
        // 없으면: 조작한 클라(서버 상한으로 g > DB 가 영구)가 상대에게 매초 tetris_state 를 부르게 하거나, 프레임이 보고 커밋보다
        // 먼저 닿을 때마다 공격당 조회가 두 배가 된다(1초 대기 없음).
        var link = fcJoinedLink()
        link.receive(fcFrame(f: 100, g: 4), at: 10)
        // shouldHintSync 는 참을 돌려주며 장부를 적는다(mutating) — #expect 안에서 부를 수 없어 먼저 받는다.
        let early = link.shouldHintSync(at: 10.99, opponentAttackTotal: 0)
        let onTime = link.shouldHintSync(at: 11.0, opponentAttackTotal: 0)
        #expect(!early, "1초를 안 기다렸다")
        #expect(onTime)
        var hints = 0
        var f = 101
        for i in 0..<120 {                         // 같은 g 로 2분 — 위조·서버 상한·상대 보고 실패가 이어지는 동안
            let t = 11.5 + Double(i)
            link.receive(fcFrame(f: f, g: 4), at: t)
            f += 1
            if link.shouldHintSync(at: t + 0.5, opponentAttackTotal: 0) { hints += 1 }
        }
        #expect(hints == 0, "같은 g 로 \(hints)번 더 조회했다")
        // 새 공격 값 — 다시 1초를 잰다.
        link.receive(fcFrame(f: f, g: 6), at: 200)
        f += 1
        let newEarly = link.shouldHintSync(at: 200.5, opponentAttackTotal: 4)
        let newOnTime = link.shouldHintSync(at: 201.0, opponentAttackTotal: 4)
        #expect(!newEarly && newOnTime)
        // ring 이 제때 와 DB 가 따라잡았으면 조회하지 않는다.
        link.receive(fcFrame(f: f, g: 8), at: 300)
        let caughtUp = link.shouldHintSync(at: 302, opponentAttackTotal: 8)
        let ahead = link.shouldHintSync(at: 302, opponentAttackTotal: 9)
        #expect(!caughtUp && !ahead, "DB 가 이미 따라잡았는데 조회한다")
        // 끝난 판에서는 없다.
        var done = fcJoinedLink()
        done.receive(fcFrame(f: 1, g: 3), at: 0)
        _ = done.finish()
        let afterFinish = done.shouldHintSync(at: 5, opponentAttackTotal: 0)
        #expect(!afterFinish)
    }

    @Test("힌트 — 앞 힌트가 풀리기 전(DB 누계가 그 값에 못 닿았다)에는 새 g 로도 다시 없음 · 프레임마다 g 를 올리는 위조도 판당 한 번 · 풀리면 다음 공격은 다시 1초")
    func hintWaitsUntilThePreviousHintResolves() {
        // 없으면(11-03 검토 F1): '같은 g 에 한 번' 은 g 를 프레임마다 1씩 올리는 위조를 못 막는다 — 값이 늘 새롭고, 판 루프는 다음 프레임이
        // 닿기 전(tick → pump)에 1초를 채워, 피해자가 판 끝까지 거의 매초 tetris_state 를 친다(사본 프로브: 15초에 13번).
        var link = fcJoinedLink()
        var hints = 0
        var f = 100
        for i in 0..<120 {                         // 2분 — 상대가 g 를 101, 102, 103 … 으로 1초마다 올린다. DB 는 0 그대로(서버 상한).
            let t = 10 + Double(i)
            link.receive(fcFrame(f: f, g: 101 + i), at: t)
            f += 1
            if link.shouldHintSync(at: t + 0.5, opponentAttackTotal: 0) { hints += 1 }
            if link.shouldHintSync(at: t + 1.0, opponentAttackTotal: 0) { hints += 1 }   // 다음 프레임보다 먼저 묻는 걸음
        }
        #expect(hints == 1, "프레임마다 올리는 위조 g 에 \(hints)번 물었다(판당 한 번이어야 한다)")
        #expect(link.hintedAttack == 101, "전제: 첫 값(101)에 한 번 물었다")
        // DB 가 그 값에 닿으면(안 일어나지만 — 서버 상한) 그때 다시 1초 뒤 한 번.
        link.receive(fcFrame(f: f, g: 400), at: 300)
        let afterResolve = link.shouldHintSync(at: 301, opponentAttackTotal: 101)
        #expect(afterResolve, "앞 힌트가 풀렸는데 새 값을 안 물었다")
        // 정직한 판: 힌트로 읽은 응답이 그 값을 싣고 오면(DB ≥ 앞 힌트) 다음 공격은 다시 1초 뒤 한 번.
        var honest = fcJoinedLink()
        honest.receive(fcFrame(f: 1, g: 4), at: 0)
        let a = honest.shouldHintSync(at: 1, opponentAttackTotal: 0)
        honest.receive(fcFrame(f: 2, g: 8), at: 5)
        let blocked = honest.shouldHintSync(at: 6, opponentAttackTotal: 2)      // 힌트 4 가 아직 안 풀렸다(DB 2)
        let resolved = honest.shouldHintSync(at: 6, opponentAttackTotal: 4)     // DB 가 4 에 닿았다 — 풀렸다
        #expect(a && !blocked && resolved, "정직한 판의 다음 공격 힌트가 막혔다(또는 안 풀린 힌트가 새 값을 열었다)")
    }

    // MARK: - 멈춤 10초

    @Test("멈춤 — 판 시작 뒤 10초 동안 증거(h 0~2500 프레임)가 없으면 닫는다 · 카운트다운 중엔 시계가 안 돈다 · h=-1 프레임은 증거가 아니다")
    func noEvidenceForTenSecondsClosesTheSocket() {
        // 없으면: 쓰기가 거절된(ack:false 라 모른다) 소켓이나 듣지 않는 상대에게 판 끝까지 프레임을 쓴다(§5 · §15 인가 풀).
        var link = fcJoinedLink(at: 0)                 // 카운트다운 중에 join
        #expect(link.socketCommand(at: 2.9, matchStartedAt: nil, jitter: fcIdentity) == .none, "시작 전에 멈춤 시계가 돈다")
        let start: TimeInterval = 3
        // 상대 프레임은 오지만 상대가 내 프레임을 못 듣는다(h=-1) — 쓰기만 거절된 판의 모양.
        for i in 0..<10 { link.receive(fcFrame(f: 100 + i, h: -1), at: start + Double(i)) }
        #expect(link.socketCommand(at: start + 9.99, matchStartedAt: start, jitter: fcIdentity) == .none)
        #expect(link.socketCommand(at: start + 10, matchStartedAt: start, jitter: fcIdentity) == .disconnect,
                "h=-1 프레임을 증거로 셌다")
        #expect(link.socket == .retrying(at: start + 10 + 1) && link.retriesUsed == 1)
        #expect(link.reportInterval(at: start + 10) == 1)
    }

    @Test("멈춤 — 증거가 끊긴 지 10초면 닫는다 · 다시 연 연결은 그 시도 시각부터 잰다 · join 이 매달려도 닫는다")
    func evidenceGapClosesAndReconnectRestartsTheClock() {
        // 없으면: 판 중간에 상대가 듣기를 멈춘 소켓이 판 끝까지 남고, 다시 연 연결이 옛 기준으로 곧바로 다시 닫혀 재시도를 태운다.
        var link = fcJoinedLink(at: 0)
        let start: TimeInterval = 3
        fcFeed(&link, count: 5, from: start, f: 100)   // 증거 3…7초
        #expect(link.socketCommand(at: 16.99, matchStartedAt: start, jitter: fcIdentity) == .none)
        #expect(link.socketCommand(at: 17, matchStartedAt: start, jitter: fcIdentity) == .disconnect)
        #expect(link.socketCommand(at: 18, matchStartedAt: start, jitter: fcIdentity) == .connect(topic: fcTopic, refreshToken: false))
        // join 이 오지 않는다(매달림) — 그 시도 시각(18)부터 10초.
        #expect(link.socketCommand(at: 27.99, matchStartedAt: start, jitter: fcIdentity) == .none, "옛 증거 기준으로 곧바로 닫았다")
        #expect(link.socketCommand(at: 28, matchStartedAt: start, jitter: fcIdentity) == .disconnect)
        #expect(link.socket == .retrying(at: 30) && link.retriesUsed == 2)
    }

    // MARK: - 재시도 사유별

    @Test("재시도 — 끊김은 지터 1·2·4초로 판당 3회 · 넷째 끊김에서 멈춤 · 성공해도 예산은 안 돌아온다 · 지터 바닥 0.25초")
    func lostSocketsRetryThreeTimesPerMatch() {
        // 없으면: Realtime·DB 정지 중 join 이 판 끝까지 이어져 인가 풀 2를 두드린다(§10).
        var link = fcJoinedLink(at: 0)
        var t: TimeInterval = 10
        for attempt in 1...3 {
            #expect(link.apply(.closed(code: nil), at: t, jitter: fcIdentity) == .disconnect)
            let wait = Double(1 << (attempt - 1))
            #expect(link.socket == .retrying(at: t + wait), "\(attempt)번째 대기")
            #expect(link.socketCommand(at: t + wait - 0.01, matchStartedAt: 0, jitter: fcIdentity) == .none)
            #expect(link.socketCommand(at: t + wait, matchStartedAt: 0, jitter: fcIdentity) == .connect(topic: fcTopic, refreshToken: false))
            #expect(link.apply(.joined, at: t + wait, jitter: fcIdentity) == .none)
            t += wait + 1
        }
        #expect(link.apply(.heartbeatTimedOut, at: t, jitter: fcIdentity) == .disconnect)
        #expect(link.socket == .stopped(.exhausted) && link.retriesUsed == 3)
        #expect(link.socketCommand(at: t + 100, matchStartedAt: 0, jitter: fcIdentity) == .none, "예산을 다 쓰고 또 연다")
        #expect(link.reportInterval(at: t + 100) == 1)
        // 지터는 주입이고 바닥 0.25초다.
        var jittered = fcJoinedLink(at: 0)
        _ = jittered.apply(.closed(code: nil), at: 5, jitter: { _ in 0 })
        #expect(jittered.socket == .retrying(at: 5.25))
    }

    @Test("재시도 — RLS 거절(.unauthorized)은 재시도 없음 · 판 끝까지 1초")
    func unauthorizedNeverRetries() {
        // 없으면: 재시도로 절대 안 낫는 거절을 1·2·4초로 세 번 더 두드린다(정책 미배포·제3자 판).
        var link = fcJoinedLink(at: 0)
        let denied = #"{"topic":"realtime:\#(fcTopic)","event":"phx_reply","ref":"1","payload":{"status":"error","response":{"reason":"Unauthorized: You do not have permissions to read from this Channel topic: \#(fcTopic)"}}}"#
        let event = RealtimeFrame.decode(text: denied, channel: fcTopic, joinRef: "1")
        #expect(event == .joinRejected(.unauthorized))
        #expect(link.apply(event!, at: 1, jitter: fcIdentity) == .disconnect)
        #expect(link.socket == .stopped(.unauthorized) && link.retriesUsed == 0)
        #expect(link.socketCommand(at: 60, matchStartedAt: 0, jitter: fcIdentity) == .none)
    }

    @Test("재시도 — 만료 토큰은 토큰을 새로 받아 한 번만(재시도 예산 안에서) · 두 번째 만료는 멈춤")
    func expiredTokenRetriesOnceWithAFreshToken() {
        // 없으면: 만료 토큰으로 같은 거절을 세 번 받거나, 갱신 없이 다시 열어 같은 이유로 실패한다.
        var link = fcJoinedLink(at: 0)
        #expect(link.apply(.joinRejected(.expiredToken), at: 1, jitter: fcIdentity) == .disconnect)
        #expect(link.socket == .retrying(at: 2) && link.retriesUsed == 1)
        #expect(link.socketCommand(at: 2, matchStartedAt: 0, jitter: fcIdentity) == .connect(topic: fcTopic, refreshToken: true),
                "토큰을 새로 받으라고 하지 않았다")
        #expect(link.apply(.joinRejected(.expiredToken), at: 2.5, jitter: fcIdentity) == .disconnect)
        #expect(link.socket == .stopped(.exhausted))
        // 만료 재시도 뒤의 일반 재시도는 갱신을 다시 시키지 않는다.
        var other = fcJoinedLink(at: 0)
        _ = other.apply(.joinRejected(.expiredToken), at: 1, jitter: fcIdentity)
        _ = other.socketCommand(at: 2, matchStartedAt: 0, jitter: fcIdentity)
        _ = other.apply(.joined, at: 2, jitter: fcIdentity)
        _ = other.apply(.closed(code: nil), at: 3, jitter: fcIdentity)
        #expect(other.socketCommand(at: 5, matchStartedAt: 0, jitter: fcIdentity) == .connect(topic: fcTopic, refreshToken: false))
    }

    @Test("재시도 — system 오류 \"Too many messages per second\" 면 그 판은 다시 잇지 않는다 · 뒤따르는 phx_close 는 두 번 안 센다")
    func rateLimitStopsReconnectsForTheMatch() {
        // 없으면: 프로젝트 전체 이벤트 한도에 닿은 채 다시 이어 초인종까지 같이 닫히게 만든다(§15).
        var link = fcJoinedLink(at: 0)
        let system = #"{"topic":"realtime:\#(fcTopic)","event":"system","payload":{"status":"error","message":"Too many messages per second","extension":"system"}}"#
        let event = RealtimeFrame.decode(text: system, channel: fcTopic, joinRef: "1")
        #expect(event == .joinRejected(.unknown("Too many messages per second")), "기존 decode 계약(system 오류 → joinRejected)이 바뀌었다")
        #expect(link.apply(event!, at: 1, jitter: fcIdentity) == .disconnect)
        #expect(link.socket == .stopped(.rateLimited))
        let close = RealtimeFrame.decode(text: #"{"topic":"realtime:\#(fcTopic)","event":"phx_close","payload":{}}"#,
                                         channel: fcTopic, joinRef: "1")
        #expect(close == .closed(code: nil))
        #expect(link.apply(close!, at: 1.1, jitter: fcIdentity) == .none)
        #expect(link.socket == .stopped(.rateLimited) && link.retriesUsed == 0)
        #expect(link.socketCommand(at: 60, matchStartedAt: 0, jitter: fcIdentity) == .none)
        // 이름 없는 끊김은 한도가 아니다(재시도를 탄다) — 위 0 이 뜻을 가지려면.
        #expect(TetrisFrameCloseCause.classify(.joinRejected(.unknown("connection reset"))) == .lost)
        #expect(TetrisFrameCloseCause.classify(.joinRejected(.unknown("Too many joins per second"))) == .rateLimited)
    }

    @Test("서버 스위치 끔 → 소켓 닫고 대기 · 재시도 예산은 안 씀 · 다시 켜면 새로 연다")
    func serverSwitchClosesWithoutSpendingRetries() {
        // 없으면: 롤백 스위치가 내려도 소켓이 남아(연결 누수) 정책이 거절할 토큰 갱신을 보내거나, 스위치 한 번에 재시도를 태운다.
        var link = fcJoinedLink(at: 0)
        link.noteServerFrames(nil)
        #expect(link.socketCommand(at: 1, matchStartedAt: 0, jitter: fcIdentity) == .disconnect)
        #expect(link.socket == .idle && link.retriesUsed == 0)
        #expect(link.socketCommand(at: 2, matchStartedAt: 0, jitter: fcIdentity) == .none)
        link.noteServerFrames(TetrisFramesRow(on: true, topic: fcTopic))
        #expect(link.socketCommand(at: 3, matchStartedAt: 0, jitter: fcIdentity) == .connect(topic: fcTopic, refreshToken: false))
    }

    @Test("끝난 판 — finish 가 곧바로 닫는다 · 다시 안 연다 · 늦게 온 프레임은 버린다 · 판·줄은 마지막으로 받은 프레임")
    func finishedMatchClosesAndFreezesTheFrameLedger() {
        // 없으면: 끝난 판 가지(applyState 는 discardDuel 을 안 부른다)에서 소켓이 결과를 접을 때까지 남는다 — 피크 연결 누수(§10).
        var (link, _) = fcSteadyLink()
        link.receive(fcFrame(f: 200, s: 9, lines: 40), at: 4)
        #expect(link.finish() == .disconnect)
        #expect(link.socket == .stopped(.finished))
        #expect(link.socketCommand(at: 5, matchStartedAt: 0, jitter: fcIdentity) == .none)
        #expect(link.receive(fcFrame(f: 201, s: 9, lines: 44), at: 5) == .matchFinished)
        let db = TetrisOpponentDisplay(board: nil, lines: 38, pending: 0, attackSent: 10)
        #expect(link.mergedDisplay(dbSeq: 8, db: db).lines == 40, "끝난 판의 줄 수가 DB 의 옛값으로 줄었다")
        // 끝난 판의 보낸 공격 수는 DB(정산 정본) — 위조 g 가 결과 화면에 남지 않는다(11-03 검토 F5). 판 중에는 max(표시).
        var forged = fcJoinedLink()
        forged.receive(fcFrame(f: 1, s: 9, g: 50), at: 1)
        #expect(forged.mergedDisplay(dbSeq: 8, db: db).attackSent == 50, "전제: 판 중엔 두 값의 max 다")
        _ = forged.finish()
        #expect(forged.mergedDisplay(dbSeq: 8, db: db).attackSent == 10, "장부가 끝났는데 공격 수가 DB 가 아니다")
        #expect(forged.mergedDisplay(dbSeq: 8, db: db).lines == 0, "끝난 판도 줄은 프레임 규칙이다")
        var idle = TetrisFrameLink(me: fcMe, opponent: fcRival, frameBase: 1)
        #expect(idle.finish() == .none, "열지 않은 소켓을 닫으라고 한다")
    }

    // MARK: - §4 병합

    @Test("병합 — 프레임 s ≥ DB seq 면 판·줄·대기 줄은 프레임 · 공격은 max · DB seq 가 크면 DB · 프레임 없으면 DB")
    func mergeKeepsTheNewerSource() {
        // 없으면: 체크포인트 응답(최대 3초 옛것)이 상대 판을 되감아 매 3초마다 판이 뒤로 튄다.
        var link = fcJoinedLink()
        let dbBoard = "G" + String(TetrisDuelBoard.emptyText.dropFirst())
        let db = TetrisOpponentDisplay(board: dbBoard, lines: 5, pending: 1, attackSent: 6)
        #expect(link.mergedDisplay(dbSeq: 10, db: db) == db, "프레임이 없는데 DB 를 바꿨다")
        let frameBoard = "I" + String(TetrisDuelBoard.emptyText.dropFirst())
        link.receive(fcFrame(f: 1, s: 10, g: 4, board: frameBoard, lines: 7, pending: 3), at: 1)
        let same = link.mergedDisplay(dbSeq: 10, db: db)
        #expect(same == TetrisOpponentDisplay(board: frameBoard, lines: 7, pending: 3, attackSent: 6), "같은 seq 에서 \(same)")
        #expect(link.mergedDisplay(dbSeq: 9, db: db).board == frameBoard)
        #expect(link.mergedDisplay(dbSeq: 11, db: db) == db, "DB 가 더 새로운데 프레임이 이겼다")
        link.receive(fcFrame(f: 2, s: 10, g: 9, board: frameBoard, lines: 7, pending: 3), at: 2)
        #expect(link.mergedDisplay(dbSeq: 10, db: db).attackSent == 9)
    }

    // MARK: - 보고 주기 인자

    @Test("reportReason(heartbeat:) — 기본 1초 그대로 · 3초를 넣으면 하트비트 줄만 3초 · 준비·공격·탑아웃은 그대로 곧바로 · [1, 3]초로 자른다")
    func reportReasonTakesTheIntervalOnlyForHeartbeats() {
        // 없으면: 인자가 공격 분기까지 늦추거나(공격 보고가 3초 밀린다), 0·30 같은 값이 판 루프 걸음마다 보고 · 15초 침묵 패를 만든다.
        var s = TetrisDuelSession(seed: 4, startedGame: TetrisGame(
            seed: 4, board: TetrisGame.boardFixture(bottomRows: Array(repeating: "IIIIIIIII.", count: 4)),
            active: TetrisGame.ActivePiece(piece: .i, rotation: .right, column: 7, row: TetrisGame.spawnRow)), startAt: 0)
        #expect(s.reportReason(at: 1, heartbeat: 3) == .ready, "준비가 인자에 밀렸다")
        _ = s.makeReport(at: 10)
        #expect(s.reportReason(at: 11) == .heartbeat, "기본값이 1초가 아니다")
        #expect(s.reportReason(at: 11, heartbeat: 3) == nil)
        #expect(s.reportReason(at: 12.99, heartbeat: 3) == nil)
        #expect(s.reportReason(at: 13, heartbeat: 3) == .heartbeat)
        #expect(s.reportReason(at: 11, heartbeat: 0) == .heartbeat && s.reportReason(at: 10.5, heartbeat: 0) == nil, "1초 밑으로 내려갔다")
        #expect(s.reportReason(at: 13, heartbeat: 30) == .heartbeat, "3초 위로 늘어났다")
        #expect(s.reportReason(at: 11, heartbeat: .nan) == .heartbeat && s.reportReason(at: 11, heartbeat: .infinity) == .heartbeat)
        s.hardDrop()
        #expect(s.game.attackSentTotal == 4)
        #expect(s.reportReason(at: 10.25, heartbeat: 3) == .attack, "공격이 체크포인트에 밀렸다")
        #expect(TetrisDuelSession.checkpointSeconds == 3 && TetrisFrameLink.checkpointSeconds == TetrisDuelSession.checkpointSeconds)
    }
}
