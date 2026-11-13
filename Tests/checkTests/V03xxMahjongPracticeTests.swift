@testable import CheckCore
import Foundation
import Testing

// 아잉 마작 연습판 시험(갈래 C3 — SPEC §4.5 '연습판' · §6.3 C 줄 V03xxMahjongPracticeTests). 엔진(E)·봇(B) 위에 선 스토어 몸통을
// 잰다: 네트워크 0 · 칸 나눔(table 한 길) · 루비 판이 서면 버림 · 창이 숨거나 가려지면 판 전체 멈춤 · 늦은 봇 결정 버림 · 시간
// ('넉넉히' 시간 초과 없음 / '실전처럼' 5+20) · 방과 연습 따로(CC-02 ①②③) · 봇 격리(CC-09) · '넉넉히' 울기 안내·넘김(CC-28) · 보조.
// 봇 결정·패산·자리·시계는 고정하고 보여 주는 시간은 0(`delayScale`). 스텁 서버·기기 손잡이는 V03xxMahjongStoreTests 의 것을 쓴다.
// 각 시험 첫 줄 주석은 "없으면 어떤 결함이 초록인가". 느린 실측(봇이 200ms 를 꽉 쓰는 판의 메인 간격)은 `MAHJONG_BOT_SLOW=1`.

/// 고정 패산(SplitMix 씨앗).
func mjPracticeWall(_ seed: UInt64) -> [Int] {
    var rng = GomokuAISplitMix64(seed: seed)
    var wall = Array(0..<136)
    wall.shuffle(using: &rng)
    return wall
}

/// 쯔모기리 봇(뽑은 패를 버리고 울기는 늘 넘김) — 흐름이 씨앗만으로 정해진다.
func mjTsumogiriMove(_ view: MahjongStatePayload) -> MahjongBotMove {
    switch view.myDecision {
    case .turn(let turn)?:
        if let drawn = view.myDrawn, turn.discard.contains(drawn) { return .act(.discard(drawn)) }
        return turn.discard.last.map { .act(.discard($0)) } ?? .none
    case .call(let call)?:
        return .call(windowId: call.windowId, .pass)
    case nil:
        return .none
    }
}

let mjTsumogiriDecide: MahjongPracticeBotDecide = { view, _, _ in mjTsumogiriMove(view) }

/// 봇 결정 문 — 부른 횟수 · 메인 스레드 여부를 적고, 막아 두면 풀릴 때까지(취소를 따르면 취소에도) 돌아오지 않는다.
final class MJBotGate: @unchecked Sendable {
    private let lock = NSLock()
    private var callCount = 0
    private var releasedUpTo = 0
    private var blockingAll: Bool
    private var mainThreadCalls = 0
    let honorsCancel: Bool

    init(blocking: Bool, honorsCancel: Bool = true) {
        blockingAll = blocking
        self.honorsCancel = honorsCancel
    }

    var calls: Int { lock.withLock { callCount } }
    var callsOnMainThread: Int { lock.withLock { mainThreadCalls } }

    /// n 번째 부름까지 풀어 준다.
    func release(upTo n: Int) { lock.withLock { releasedUpTo = max(releasedUpTo, n) } }
    /// 모두 풀고 앞으로는 막지 않는다.
    func openAll() { lock.withLock { blockingAll = false } }

    private func enter(onMain: Bool) -> Int {
        lock.withLock {
            callCount += 1
            if onMain { mainThreadCalls += 1 }
            return callCount
        }
    }

    private func isBlocked(_ n: Int) -> Bool { lock.withLock { blockingAll && n > releasedUpTo } }

    var decide: MahjongPracticeBotDecide {
        { [self] view, _, isCancelled in
            let n = enter(onMain: Thread.isMainThread)
            while isBlocked(n) {
                if honorsCancel, isCancelled() { break }
                usleep(300)
            }
            return mjTsumogiriMove(view)
        }
    }
}

/// 연습판 손잡이: 봇·패산·자리·씨앗 고정, 보여 주는 시간 0.
@MainActor
func mjConfigurePractice(
    _ store: MahjongStore, humanSeat: Int, wallSeed: UInt64, decide: @escaping MahjongPracticeBotDecide = mjTsumogiriDecide
) {
    let runtime = store.practiceRuntime
    runtime.decide = decide
    runtime.delayScale = 0
    runtime.makeWall = { mjPracticeWall(wallSeed) }
    runtime.pickHumanSeat = { humanSeat }
    runtime.nextSeed = { 42 }
    runtime.pauseSeconds = { 0.75 }
}

/// 서버 없는 스토어 하나(창은 탁자를 보이는 중, 실제 시계 작업은 끔 — `handlePracticeClock(now:)` 를 직접 밟는다).
@MainActor
func mjPracticeStore(
    humanSeat: Int, wallSeed: UInt64, decide: @escaping MahjongPracticeBotDecide = mjTsumogiriDecide,
    clock: MJClock = MJClock()
) -> MahjongStore {
    let store = MahjongStore(clock: { clock.now })
    store.timersEnabled = false
    mjConfigurePractice(store, humanSeat: humanSeat, wallSeed: wallSeed, decide: decide)
    store.windowDidShow()
    return store
}

/// 사람 한 수: 결정이 오기를 기다려 차례면 뽑은 패를, 울기면 넘김. 결정이 없으면(판 끝 등) 거짓.
@MainActor
@discardableResult
func mjPracticeHumanMove(_ store: MahjongStore) async -> Bool {
    await mjWait { store.myDecision != nil || store.phase == .finished }
    switch store.myDecision {
    case .turn(let turn)?:
        let tile = store.table?.myDrawn.flatMap { turn.discard.contains($0) ? $0 : nil } ?? turn.discard.last
        guard let tile else { return false }
        await store.discard(tile)
        return true
    case .call?:
        await store.passCall()
        return true
    case nil:
        return false
    }
}

/// 연습판 진행 표지(엔진 seq).
@MainActor
func mjPracticeSeq(_ store: MahjongStore) -> Int? { store.practice?.payload.match?.seq }

@MainActor
@Suite("아잉 마작 연습판 — 칸 나눔 · 네트워크 0 · 멈춤 · 늦은 봇 · 시간 · 방과 연습 따로", .serialized)
struct V03xxMahjongPracticeTests {
    @Test("ai- 판 · 네트워크 0 — 봇 셋과 사람이 몇 바퀴 둬도 서버 호출 0 · match 는 비어 있다", .gomokuDefaultsCleanup)
    func practiceMakesNoNetworkCalls() async throws {
        // 없으면: 연습판이 서버 경로(state·act·call·lobby)를 부르거나 match 칸에 들어가 루비 판과 섞인다(CC-02 · UX:401-402).
        let server = MJServer()
        let d = mjDevice("practice-net", server: server)
        let s = d.store
        mjConfigurePractice(s, humanSeat: 2, wallSeed: 11, decide: MahjongPracticeRuntime.standardDecide)   // 실제 봇
        s.windowDidShow()
        s.startPractice(format: .tonpuu, timed: false)
        var moves = 0
        while moves < 4, await mjPracticeHumanMove(s) { moves += 1 }
        #expect(moves == 4)
        #expect(GomokuStubProtocol.calls(host: d.stub).isEmpty, "연습판은 서버를 부르지 않는다")
        let practice = try #require(s.practice)
        #expect(practice.matchID.hasPrefix(MahjongStatePayload.practiceIDPrefix))
        #expect(s.match == nil && s.isPractice && s.phase == .playing)
        #expect(s.practiceRuntime.botCalls >= 6, "봇 셋이 실제로 뒀다")
        #expect(practice.payload.rubyBalance == nil && practice.payload.match?.stake ?? 0 == 0)
    }

    @Test("연습판도 table 한 길 — 단추·결정 키·단계가 연습 payload 에서 나온다 · 사람 자리는 고른 자리")
    func practiceDrawsThroughTable() async throws {
        // 없으면: 화면이 연습판을 따로 그리는 길을 두거나(두 길이 어긋난다), 결정 키가 서버 match 에서 나와 2단 입력이 안 접힌다.
        let s = mjPracticeStore(humanSeat: 0, wallSeed: 5)
        s.startPractice(format: .hanchan, timed: false)
        let practice = try #require(s.practice)
        #expect(s.table == practice.payload && s.match == nil)
        #expect(practice.format == .hanchan && practice.humanSeat == 0 && !practice.timed && !practice.isPaused)
        #expect(practice.payload.mySeat == 0)
        guard case .turn(let turn)? = s.myDecision else { Issue.record("친(사람)의 첫 차례가 없다"); return }
        #expect(s.myDecision == practice.payload.myDecision)
        #expect(s.decisionKey?.matchID == practice.matchID && s.decisionKey?.kind == "turn")
        #expect((practice.payload.myHand?.count ?? 0) + (practice.payload.myDrawn == nil ? 0 : 1) == 14)
        #expect(!turn.discard.isEmpty && s.phase == .playing && s.isPractice)
        // 기준선: 연습을 닫으면 table 은 match(없음)로 돌아가고 단계는 로비.
        s.endPractice()
        #expect(s.table == nil && s.practice == nil && s.phase == .lobby)
    }

    @Test("루비 판이 서면 연습판을 버린다 — 방(forming)은 버리지 않는다(기준선) · 날던 봇 결과는 되살리지 못한다",
          .gomokuDefaultsCleanup)
    func rubyMatchDiscardsPractice() async throws {
        // 없으면: 루비 판이 선 뒤에도 연습 탁자가 남아 서버 판 차례를 놓치거나, 늦은 봇 결과가 버린 연습판을 되살린다(UX:403).
        let server = MJServer()
        let d = mjDevice("practice-ruby", server: server)
        let s = d.store
        let gate = MJBotGate(blocking: true, honorsCancel: false)
        mjConfigurePractice(s, humanSeat: 2, wallSeed: 3, decide: gate.decide)
        s.windowDidShow()
        s.startPractice(format: .tonpuu, timed: false)
        await mjWait { gate.calls == 1 }
        let inFlight = try #require(s.practiceRuntime.botTask)
        s.applyState(try MJFixture.state("mahjong_state__room_three"))
        #expect(s.practice != nil && s.showsPractice && s.phase == .playing, "기준선: 방(forming)은 연습판을 버리지 않는다")
        s.applyState(try MJFixture.state("mahjong_state__their_turn"))
        #expect(s.practice == nil && !s.showsPractice && s.notice == MahjongNoticeText.practiceClosed)
        #expect(s.table == s.match && s.match?.match?.matchStatus == .active && s.phase == .playing)
        #expect(s.practiceRuntime.botTask == nil)
        gate.release(upTo: 1)
        await inFlight.value
        #expect(s.practice == nil && s.practiceRuntime.droppedBotMoves == 1, "늦은 봇 결과는 버린다")
        // 루비 판이 진행 중이면 연습판을 열지 않는다.
        s.startPractice(format: .tonpuu, timed: false)
        #expect(s.practice == nil && !s.showsPractice)
    }

    @Test("창이 숨거나 가려지면 판 전체가 멈춘다(봇도) · 다시 보이면 이어 간다 · 방 보기도 멈춤")
    func hiddenOrOccludedWindowPausesWholeTable() async throws {
        // 없으면: 가려진 창(전체 화면 앱)에서 봇이 계속 둬 사람이 못 본 사이 판이 흘러간다(UX:408 · CC-29 · V2-01).
        let gate = MJBotGate(blocking: true)
        let s = mjPracticeStore(humanSeat: 2, wallSeed: 9, decide: gate.decide)
        s.startPractice(format: .tonpuu, timed: false)
        await mjWait { gate.calls == 1 }
        let seq = mjPracticeSeq(s)
        s.windowOcclusionDidChange(visible: false)
        #expect(s.practice?.isPaused == true && s.practiceRuntime.botTask == nil)
        gate.release(upTo: 1)
        await mjWait { s.practiceRuntime.droppedBotMoves == 1 }
        try? await Task.sleep(for: .milliseconds(15))
        #expect(gate.calls == 1 && mjPracticeSeq(s) == seq, "가려진 동안 봇이 두지 않는다")
        // 다시 보이면 이어 간다(기준선 — 멈춤이 없으면 위 두 줄이 갈린다).
        gate.openAll()
        s.windowOcclusionDidChange(visible: true)
        #expect(s.practice?.isPaused == false)
        await mjWait { s.myDecision != nil }
        #expect(gate.calls > 1 && mjPracticeSeq(s) != seq && s.myDecision != nil)
        // 숨김도 같다.
        s.windowDidHide()
        #expect(s.practice?.isPaused == true)
        s.windowDidShow()
        #expect(s.practice?.isPaused == false)
        // 띠의 [방 보기]도 멈춘다 — 연습으로 돌아오면 이어 간다.
        s.showRoom()
        #expect(s.practice?.isPaused == true && !s.showsPractice && s.phase == .lobby)
        await s.discard(try #require(s.practice?.payload.myHand?.first))
        #expect(!s.showsPractice && s.practice?.isPaused == true, "방을 보는 동안 연습판 동작은 받지 않는다")
        s.showPractice()
        #expect(s.practice?.isPaused == false && s.isPractice && s.phase == .playing)
    }

    @Test("늦은 봇 결정은 버린다 — 다시 시작한 판의 같은 자리·같은 결정에 옛 결과가 들어가지 않는다")
    func lateBotDecisionIsDropped() async throws {
        // 없으면: 다시 시작·멈춤 사이에 끝난 옛 봇 계산이 새 판에 한 수를 더 둔다(리버시 ReversiStoreAI 세대 가드와 같다).
        let gate = MJBotGate(blocking: true, honorsCancel: false)
        let s = mjPracticeStore(humanSeat: 2, wallSeed: 21, decide: gate.decide)
        s.startPractice(format: .tonpuu, timed: false)
        await mjWait { gate.calls == 1 }
        let oldID = s.practice?.matchID
        s.restartPractice()
        await mjWait { gate.calls == 2 }
        let fresh = try #require(s.practice)
        #expect(fresh.matchID != oldID)
        let seq = mjPracticeSeq(s)
        gate.release(upTo: 1)   // 옛 판의 결과(같은 패산·같은 자리 — 새 판에도 그대로 둘 수 있는 수)
        await mjWait { s.practiceRuntime.droppedBotMoves == 1 }
        #expect(s.practiceRuntime.droppedBotMoves == 1 && mjPracticeSeq(s) == seq, "옛 결과가 새 판을 움직이지 않는다")
        gate.release(upTo: 2)   // 기준선: 새 판의 결과는 들어간다
        await mjWait { mjPracticeSeq(s) != seq }
        #expect(mjPracticeSeq(s) != seq)
    }

    @Test("'넉넉히'면 시간 초과가 없다 — '실전처럼'이면 5+20: 25.9초 받음 · 26.1초 시간 초과(쯔모기리) · 다음 결정 예비 0")
    func untimedHasNoTimeoutTimedHasFivePlusTwenty() async throws {
        // 없으면: '넉넉히' 연습판이 5초 박자로 패를 버려 처음 하는 사람이 당하거나, '실전처럼'이 시계를 안 재 연습이 안 된다(카드 ⑦).
        let clock = MJClock()
        let t0 = clock.now
        let loose = mjPracticeStore(humanSeat: 0, wallSeed: 13, clock: clock)
        loose.startPractice(format: .tonpuu, timed: false)
        let looseKey = loose.decisionKey
        guard case .turn(let looseTurn)? = loose.myDecision else { Issue.record("첫 차례 없음"); return }
        #expect(looseTurn.startedMs == 0 && looseTurn.deadlineMs == 0, "넉넉히는 시계 칸을 싣지 않는다")
        loose.handlePracticeClock(now: t0.addingTimeInterval(3_600))
        #expect(loose.decisionKey == looseKey && loose.notice == nil)

        let timed = mjPracticeStore(humanSeat: 0, wallSeed: 13, clock: clock)
        timed.startPractice(format: .tonpuu, timed: true)
        guard case .turn(let turn)? = timed.myDecision else { Issue.record("첫 차례 없음"); return }
        #expect(turn.bankMs == 20_000 && turn.deadlineMs - turn.startedMs == 25_000)
        #expect(timed.nextPracticeClockDate() == t0.addingTimeInterval(26))
        timed.handlePracticeClock(now: t0.addingTimeInterval(25.9))
        #expect(timed.decisionKey?.anchor == turn.decisionSeq, "마감 + 유예 안은 받는다")
        timed.handlePracticeClock(now: t0.addingTimeInterval(26.1))
        #expect(timed.notice == MahjongNoticeText.timeoutDiscarded)
        #expect(timed.practice?.payload.seats?[0].discards?.count == 1, "시간 초과는 엔진이 쯔모기리한다")
        clock.now = t0.addingTimeInterval(27)
        await mjWait { timed.myDecision != nil }
        let next: (bank: Int, span: Double)? = switch timed.myDecision {
        case .turn(let t)?: (t.bankMs, t.deadlineMs - t.startedMs)
        case .call(let c)?: (c.bankMs, c.deadlineMs - c.startedMs)
        case nil: nil
        }
        #expect(next?.bank == 0 && next?.span == 5_000, "예비는 국 안에서 회복하지 않는다")
    }

    @Test("실전처럼 — 창이 가려진 동안 사람 시계도 멈춘다(멈춘 만큼 뒤로 민다)")
    func timedClockFreezesWhilePaused() async throws {
        // 없으면: 다른 창을 잠깐 본 사이 연습판 예비가 녹아 돌아오자마자 시간 초과가 난다(봇은 멈췄는데 시계만 흐른다).
        let clock = MJClock()
        let t0 = clock.now
        let s = mjPracticeStore(humanSeat: 0, wallSeed: 13, clock: clock)
        s.startPractice(format: .tonpuu, timed: true)
        let key = s.decisionKey
        clock.now = t0.addingTimeInterval(4)
        s.windowOcclusionDidChange(visible: false)
        clock.now = t0.addingTimeInterval(64)
        s.windowOcclusionDidChange(visible: true)
        s.handlePracticeClock(now: t0.addingTimeInterval(80))
        #expect(s.decisionKey?.anchor == key?.anchor && s.notice == nil, "멈춘 60초는 세지 않는다(4 + 16 < 26)")
        #expect(s.nextPracticeClockDate() == t0.addingTimeInterval(86))
        s.handlePracticeClock(now: t0.addingTimeInterval(86.1))
        #expect(s.notice == MahjongNoticeText.timeoutDiscarded)
    }

    @Test("방과 연습 따로 ① — 방 3/4 + 연습 중 넷째 착석: 방장은 canStart · 연습 멈춤 · 띠 강조 / 멤버는 띠만(기준선)",
          .gomokuDefaultsCleanup)
    func fourthSeatPausesPracticeForHost() async throws {
        // 없으면: 넷이 모였는데 방장이 연습판에 빠져 [시작]을 못 보거나, 멤버의 연습까지 멈춰 이유 없이 판이 선다(CC-02).
        let server = MJServer()
        let a = mjDevice("practice-host", server: server)
        let s = a.store
        mjConfigurePractice(s, humanSeat: 0, wallSeed: 17)
        s.windowDidShow()
        s.applyState(try MJFixture.state("mahjong_state__room_three"))
        s.startPractice(format: .tonpuu, timed: false)
        #expect(s.isPractice && s.roomBand?.joined == 3 && s.roomBand?.readyToStart == false && !s.canStart)
        #expect(s.practice?.isPaused == false)
        s.applyState(try MJFixture.state("mahjong_state__room_four"))
        #expect(s.canStart && s.isHost && s.roomBand?.readyToStart == true && s.roomBand?.joined == 4)
        #expect(s.practice?.isPaused == true && s.notice == MahjongNoticeText.fourGathered)
        #expect(s.isPractice && s.phase == .playing, "연습 탁자는 그대로 — 띠가 [시작]을 알린다")
        // 넷이 아니게 되면 풀린다.
        s.applyState(try MJFixture.state("mahjong_state__room_three"))
        #expect(s.practice?.isPaused == false)

        let b = mjDevice("practice-member", me: mjB, server: server)
        let m = b.store
        mjConfigurePractice(m, humanSeat: 0, wallSeed: 17)
        m.windowDidShow()
        m.applyState(try MJFixture.state("mahjong_state__room_three"))
        m.startPractice(format: .tonpuu, timed: false)
        m.applyState(try MJFixture.state("mahjong_state__room_four_b"))
        #expect(!m.isHost && !m.canStart && m.roomBand?.readyToStart == true)
        #expect(m.practice?.isPaused == false, "멤버는 띠 강조만")
    }

    @Test("방과 연습 따로 ② — 연습 중 판 시작 초인종: 로비를 거치지 않고 그 판 state 1회 → 연습 버림 · active",
          .gomokuDefaultsCleanup)
    func startSignalDuringPracticeReadsMatchState() async throws {
        // 없으면: 연습 중이라 초인종이 로비만 읽어 판이 선 것을 30초 폴링까지 모르거나(차례 놓침), 연습판이 판 위에 남는다(CC-02).
        let server = MJServer()
        let a = mjDevice("practice-signal", server: server)
        let s = a.store
        mjConfigurePractice(s, humanSeat: 0, wallSeed: 19)
        s.windowDidShow()
        s.applyState(try MJFixture.state("mahjong_state__room_four"))
        s.startPractice(format: .tonpuu, timed: false)
        #expect(s.isPractice)
        server.set("mahjong_state", try MJFixture.text("mahjong_state__their_turn"))
        #expect(GomokuStubProtocol.calls(host: a.stub).isEmpty)
        await mjRing(s)
        // 첫 호출이 그 판 state 이고 state 는 한 번 — (판이 선 뒤의 로비 다시 읽기는 판돈 차감 몫으로 그 뒤에 온다.)
        #expect(GomokuStubProtocol.calls(host: a.stub).first?.rpc == "mahjong_state", "로비를 거치지 않는다")
        #expect(a.count("state") == 1)
        #expect(s.practice == nil && !s.showsPractice && s.match?.match?.matchStatus == .active)
        #expect(s.notice == MahjongNoticeText.practiceClosed && s.phase == .playing)
    }

    @Test("방과 연습 따로 ③ — 연습 시작 전에 나간 방 응답이 늦게 와도 연습 화면 유지(기준선: 연습이 없으면 방이 선다)",
          .gomokuDefaultsCleanup)
    func lateRoomResponseKeepsPracticeScreen() async throws {
        // 없으면: 방 조회 응답이 연습 탁자를 덮어 방 화면으로 튄다(연습 시작이 서버 칸을 건드리거나 단계가 match 를 먼저 본다).
        let server = MJServer()
        let a = mjDevice("practice-late", server: server)
        let s = a.store
        mjConfigurePractice(s, humanSeat: 0, wallSeed: 23)
        s.windowDidShow()
        server.enqueue("mahjong_state", try MJFixture.text("mahjong_state__room_three"), delay: 0.03)
        let request = Task { @MainActor in await s.refreshMatch(id: mjRoom) }
        await mjWait { a.count("state") == 1 }
        s.startPractice(format: .tonpuu, timed: false)
        await request.value
        #expect(s.match?.match?.matchStatus == .forming, "방은 match 칸에 따로 선다")
        #expect(s.isPractice && s.phase == .playing && s.table == s.practice?.payload && s.roomBand?.joined == 3)

        let b = mjDevice("practice-late-base", server: server)
        b.store.windowDidShow()
        server.enqueue("mahjong_state", try MJFixture.text("mahjong_state__room_three"), delay: 0.03)
        await b.store.refreshMatch(id: mjRoom)
        #expect(b.store.phase == .room && b.store.table == b.store.match, "기준선: 연습이 없으면 방이 선다")
    }

    @Test("봇 격리 — 봇 결정은 메인 스레드 밖에서 돈다(기준선: 같은 결정 함수를 메인에서 부르면 메인이다)")
    func botDecidesOffMainThread() async throws {
        // 없으면: @MainActor 스토어 안 Task {} 가 봇을 메인에서 돌려 상한 200ms 가 그대로 화면 멈칫이 된다(CC-09).
        let gate = MJBotGate(blocking: false)
        let s = mjPracticeStore(humanSeat: 2, wallSeed: 29, decide: gate.decide)
        s.startPractice(format: .tonpuu, timed: false)
        await mjWait { s.myDecision != nil }
        #expect(gate.calls >= 2 && gate.callsOnMainThread == 0)
        let view = try #require(s.practice?.payload)
        _ = gate.decide(view, 1, { false })   // 기준선: 메인에서 부르면 메인으로 센다
        #expect(gate.callsOnMainThread == 1)
    }

    @Test("reset 뒤 봇이 100ms 안에 돌아온다 — 200ms 를 꽉 쓰는 느린 봇도 취소를 받고 곧바로")
    func resetReturnsBotPromptly() async throws {
        // 없으면: 로그아웃·계정 바뀜 뒤에도 봇 계산이 200ms 씩 돌고, 취소가 봇에 안 닿아 리셋이 느린 봇을 기다린다(CC-09).
        let s = mjPracticeStore(humanSeat: 2, wallSeed: 31, decide: Self.slowDecide)
        s.startPractice(format: .tonpuu, timed: false)
        await mjWait { s.practiceRuntime.botCalls == 1 }
        try? await Task.sleep(for: .milliseconds(5))
        let task = try #require(s.practiceRuntime.botTask)
        let started = ContinuousClock.now
        s.reset()
        await task.value
        let took = ContinuousClock.now - started
        #expect(took < .milliseconds(100), "봇이 돌아오기까지 \(took)")
        #expect(s.practice == nil && !s.showsPractice && s.practiceRuntime.droppedBotMoves == 1)
    }

    /// 느린 봇: 계산 상한(200ms)까지 바쁘게 돈 뒤(취소되면 곧바로) 1단 결과.
    static let slowDecide: MahjongPracticeBotDecide = { view, seed, isCancelled in
        var rng = GomokuAISplitMix64(seed: seed)
        let deadline = ContinuousClock.now + MahjongBot.computeBudget
        while !isCancelled(), ContinuousClock.now < deadline {}
        return MahjongBot.decide(view: view, rng: &rng, deadline: deadline, now: { deadline }, policy: .standard)
    }

    @Test("'넉넉히' 론 아닌 울기 프롬프트 — 5초 뒤 안내 한 줄 · 30초 뒤 저절로 넘김(그 전은 그대로)")
    func idleCallPromptHintsThenPasses() async throws {
        // 없으면: 처음 하는 사람이 치·퐁 프롬프트 앞에서 판이 멈춘 줄 안다 — 봇은 기다리고 시간 초과는 없다(CC-28).
        let (seed, prompt) = try #require(Self.callPromptScenario(), "울기 프롬프트 장면을 못 찾았다")
        let clock = MJClock()
        let t0 = clock.now
        let s = mjPracticeStore(humanSeat: 0, wallSeed: seed, clock: clock)
        s.startPractice(format: .tonpuu, timed: false)
        var window: Int?
        for _ in 0..<(prompt + 4) {
            await mjWait { s.myDecision != nil }
            if case .call(let call)? = s.myDecision, !call.ron {
                window = call.windowId
                break
            }
            guard await mjPracticeHumanMove(s) else { break }
        }
        let windowID = try #require(window)
        guard case .call(let call)? = s.myDecision else { Issue.record("프롬프트 없음"); return }
        #expect(!call.ron && call.startedMs == 0)
        s.handlePracticeClock(now: t0.addingTimeInterval(4.9))
        #expect(s.notice == nil)
        s.handlePracticeClock(now: t0.addingTimeInterval(5))
        #expect(s.notice == MahjongNoticeText.practiceIdleCallHint)
        s.handlePracticeClock(now: t0.addingTimeInterval(29.9))
        #expect(s.decisionKey?.anchor == windowID, "30초 전에는 넘기지 않는다")
        s.handlePracticeClock(now: t0.addingTimeInterval(30))
        #expect(s.decisionKey?.anchor != windowID || s.decisionKey?.kind != "call")
        #expect(s.notice == nil, "넘기면 안내도 내린다")
    }

    /// 쯔모기리 넷(사람 = 0번)으로 엔진만 돌려 사람에게 론 아닌 울기 프롬프트가 처음 서는 씨앗과 그때까지 사람 차례 수(+1).
    static func callPromptScenario() -> (seed: UInt64, humanMoves: Int)? {
        for seed in UInt64(1)...60 {
            var engine = MahjongTableEngine(format: .tonpuu, seats: [nil, nil, nil, nil])
            _ = engine.deal(wall: mjPracticeWall(seed))
            var humanMoves = 0
            for _ in 0..<160 {
                switch engine.phase {
                case .turn(let seat):
                    let view = engine.payload(for: seat, since: 0, now: Date(timeIntervalSince1970: 0))
                    guard case .act(let action) = mjTsumogiriMove(view) else { return nil }
                    if seat == 0 { humanMoves += 1 }
                    _ = engine.act(seat: seat, action)
                case .claim:
                    if case .call(let call)? = engine.decision(for: 0) {
                        if !call.ron { return (seed, humanMoves + 1) }
                    }
                    for seat in engine.pendingSeats { _ = engine.call(seat: seat, .pass) }
                case .drawWait:
                    _ = engine.step(.wait)
                default:
                    break
                }
                if case .handEnd = engine.phase { break }
                if engine.isFinished { break }
            }
        }
        return nil
    }

    @Test("보조 쯔모기리 — 연습판에서도 뽑은 패를 대신 버린다(기준선: 보조를 끄면 그대로)")
    func tsumogiriAidWorksInPractice() async throws {
        // 없으면: 보조 칸이 서버 판에서만 돌아 연습판에서 켠 쯔모기리가 아무 일도 안 한다(§4.5 보조 — 루비 판에서도 같다).
        let clock = MJClock()
        let t0 = clock.now
        let off = mjPracticeStore(humanSeat: 0, wallSeed: 13, clock: clock)
        off.startPractice(format: .tonpuu, timed: false)
        guard case .turn(let turn)? = off.myDecision else { Issue.record("첫 차례 없음"); return }
        try #require(!turn.tsumo && turn.riichi.isEmpty && turn.ankan.isEmpty && turn.kakan.isEmpty)
        off.handlePracticeClock(now: t0.addingTimeInterval(2))
        #expect(off.practice?.payload.seats?[0].discards?.isEmpty ?? true)

        let on = mjPracticeStore(humanSeat: 0, wallSeed: 13, clock: clock)
        on.aids.tsumogiri = true
        on.startPractice(format: .tonpuu, timed: false)
        let drawn = try #require(on.practice?.payload.myDrawn)
        on.handlePracticeClock(now: t0.addingTimeInterval(2))
        #expect(on.practice?.payload.seats?[0].discards?.map(\.tile) == [drawn])
    }
}

// MARK: - 느린 실측(MAHJONG_BOT_SLOW=1)

@MainActor
final class MJMainGapMeter {
    var last = ContinuousClock.now
    var maxGap: Duration = .zero
    var running = true

    func start() -> Task<Void, Never> {
        last = ContinuousClock.now
        return Task { @MainActor in
            while self.running {
                let now = ContinuousClock.now
                self.maxGap = max(self.maxGap, now - self.last)
                self.last = now
                try? await Task.sleep(for: .milliseconds(2))
            }
        }
    }
}

@MainActor
@Suite("아잉 마작 연습판 — 봇 격리 실측(느림)", .serialized)
struct V03xxMahjongPracticeSlowTests {
    nonisolated static var slow: Bool { ProcessInfo.processInfo.environment["MAHJONG_BOT_SLOW"] == "1" }

    @Test(.enabled(if: V03xxMahjongPracticeSlowTests.slow))
    func botFullBudgetKeepsMainResponsive() async throws {
        // 없으면: 봇이 200ms 를 꽉 쓰는 판에서 메인 액터가 그만큼 멈춰 화면이 멈칫한다(CC-09). 기준선: 같은 봇을 메인에서 ≥ 200ms.
        let s = mjPracticeStore(humanSeat: 1, wallSeed: 37, decide: V03xxMahjongPracticeTests.slowDecide)
        let meter = MJMainGapMeter()
        let ticker = meter.start()
        s.startPractice(format: .tonpuu, timed: false)
        await mjWait(5) { s.practiceRuntime.botCalls >= 1 }
        await mjWait(5) { s.myDecision != nil }
        meter.running = false
        await ticker.value
        #expect(s.practiceRuntime.botCalls >= 1 && meter.maxGap < .milliseconds(50), "메인 최대 간격 \(meter.maxGap)")

        let base = MJMainGapMeter()
        let baseTicker = base.start()
        try? await Task.sleep(for: .milliseconds(10))
        let view = try #require(s.practice?.payload)
        _ = V03xxMahjongPracticeTests.slowDecide(view, 1, { false })   // 기준선: 메인에서 그대로
        try? await Task.sleep(for: .milliseconds(10))
        base.running = false
        await baseTicker.value
        #expect(base.maxGap >= .milliseconds(200), "기준선 메인 최대 간격 \(base.maxGap)")
        print("C3 SLOW 메인 최대 간격: 봇 분리 \(meter.maxGap) · 메인에서 \(base.maxGap)")
    }
}
