import Foundation

// 아잉 마작 스토어 — 혼자 연습판(혼자 + 봇 셋, SPEC §4.5 '연습판' · CC-02 · D40). 리버시 `ReversiStoreAI.swift` 함수 목록을
// 이름만 바꿨다 — start(beginPractice) · restart · handlePracticeClock · 사람 동작(practiceAct/practiceAnswer) · 멈춤/재개
// (syncPracticePause) · 버림(discardPracticeGame) · 화면 값 옮기기(commitPractice) · 봇 차례(schedulePracticeTurnIfNeeded) ·
// 봇 수 반영(applyPracticeBotMove) · 사람 시계(schedulePracticeClock).
//
// ── 칸이 따로다(CC-02) ──
// 연습판은 `practice` 칸 안에서만 돈다. 판 권위는 엔진(`MahjongTableEngine`, 갈래 E — 세션의 internal 칸)이고, 화면이 보는 것은
// 엔진 `payload(for: 사람 자리)` 를 옮긴 `practice.payload` 뿐이다(`table` 한 길). 서버 `match` 를 건드리지 않고 루비·기록·미션·
// 네트워크는 0 이다. 루비 판이 서면(`matchDidChange`) 연습판을 버린다 — 판이 언제나 이긴다.
//
// ── 봇은 메인 밖에서(CC-09) ──
// 봇 결정은 `Task.detached(priority: .userInitiated)` 에서 `MahjongBot.decide` — 입력은 메인에서 만든 그 자리 시야 사본(값),
// 결과는 세대·판 id·국·seq·대기 자리가 그대로일 때만 메인에서 적용한다(늦은 결과는 버린다). 취소되면 봇에게 '마감이 지났다'고
// 알려 1단 결과로 곧바로 돌아오게 한다(`reset` 뒤 봇이 바로 돌아온다). 보여 주는 생각 시간은 `MahjongBot.thinkSeconds`,
// 창·쯔모 멈춤은 서버와 같은 꼴 0.5~1.0초, 국 결과 쉬는 시간은 7초 + 4초 × (화료자 − 1)(D48).
//
// ── 멈춤 ──
// 창이 탁자를 보이지 않으면(숨김·가림 둘 다 — `isWindowShowingTable` 하나), 방을 보고 있으면(`showRoom`), 방장인데 서버 방에
// 넷째가 앉았으면 판 전체가 멈춘다(봇도 안 둔다). 사람 시계·울기 안내 시계는 멈춘 만큼 뒤로 민다.
//
// ── 시간 ──
// '실전처럼 5+20'(`timed`)일 때만 `MahjongClock` 으로 사람 결정 마감을 잰다(마감 + 유예 1초에 시간 초과 — 엔진이 쯔모기리·넘김·
// 자동 화료). '넉넉히'에서는 시간 초과가 없고, 론 아닌 울기 프롬프트만 5초 뒤 안내 한 줄 · 30초 뒤 저절로 넘긴다(CC-28).
// 연습판의 ms 칸(started·deadline·server_now·at_ms)은 서버 ms 공간에 둔다 — 화면이 서버 판과 같은 한 길(`serverClockOffset`)로
// 기기 시각을 얻게.

/// 봇 한 수 계산(동기·순수) — 스토어가 `Task.detached` 안에서 부른다. 셋째 인자는 '이 계산이 취소됐나'.
package typealias MahjongPracticeBotDecide =
    @Sendable (_ view: MahjongStatePayload, _ seed: UInt64, _ isCancelled: @escaping @Sendable () -> Bool) -> MahjongBotMove

/// 연습판 장부(관찰 대상 아님 — 스토어 본문에 한 줄로 붙는다. 저장 프로퍼티는 확장에 못 둔다).
@MainActor
package final class MahjongPracticeRuntime {
    /// 기본 봇: 실제 시계 + 계산 상한 200ms. 취소되면 시계가 마감을 말해 2단 보기를 접는다.
    package nonisolated static let standardDecide: MahjongPracticeBotDecide = { view, seed, isCancelled in
        var rng = GomokuAISplitMix64(seed: seed)
        let deadline = ContinuousClock.now + MahjongBot.computeBudget
        return MahjongBot.decide(
            view: view, rng: &rng, deadline: deadline,
            now: { isCancelled() ? deadline : ContinuousClock.now }, policy: .standard)
    }

    /// 시험 주입점: 봇 결정.
    package var decide: MahjongPracticeBotDecide = MahjongPracticeRuntime.standardDecide
    /// 보여 주는 시간(봇 생각 · 창·쯔모 멈춤 · 국 결과 쉬는 시간 · 보조 쯔모기리 지연) 배율. 시험은 0.
    package var delayScale: Double = 1
    /// 패산(0~135 순열). 시험은 고정한다.
    package var makeWall: () -> [Int] = { Array(0..<136).shuffled() }
    /// 사람 자리(0~3) — "내 자리는 무작위예요". 시험은 고정한다.
    package var pickHumanSeat: () -> Int = { Int.random(in: 0..<4) }
    /// 봇 난수 씨앗.
    package var nextSeed: () -> UInt64 = { UInt64.random(in: .min ... .max) }
    /// 창·쯔모 멈춤(초) — 서버 멈춤과 같은 꼴.
    package var pauseSeconds: () -> TimeInterval = { Double.random(in: 0.5...1.0) }

    /// 판이 바뀔 때마다(시작·버림·멈춤·새 차례 예약) 오른다. 늦게 끝난 봇 결정을 버리는 기준.
    package private(set) var generation = 0
    /// 봇 결정을 맡긴 횟수 · 버린 늦은 결과 수(진단·시험 지점).
    package private(set) var botCalls = 0
    package internal(set) var droppedBotMoves = 0
    var botTask: Task<Void, Never>?
    var stepTask: Task<Void, Never>?
    var clockTask: Task<Void, Never>?

    package init() {}

    func bump() -> Int {
        generation &+= 1
        return generation
    }

    func noteBotCall() { botCalls += 1 }

    func cancelTasks() {
        botTask?.cancel()
        botTask = nil
        stepTask?.cancel()
        stepTask = nil
        clockTask?.cancel()
        clockTask = nil
    }
}

extension MahjongStore {
    /// '넉넉히' 연습판에서 론 아닌 울기 프롬프트를 저절로 넘기기까지(초, CC-28 설계 상수).
    nonisolated static let practiceIdleCallPassSeconds: TimeInterval = 30
    /// '넉넉히' 연습판에서 울기 안내 한 줄을 띄우기까지(초).
    nonisolated static let practiceIdleCallHintSeconds: TimeInterval = 5

    /// 국 결과 쉬는 시간(초) = 7 + 4 × (화료자 − 1)(D48 — 서버 `next_hand_at` 과 같다).
    nonisolated static func practiceHandRestSeconds(winners: Int) -> TimeInterval {
        7 + 4 * Double(max(winners - 1, 0))
    }

    // MARK: 동작(표면)

    /// 연습판을 연다(연습 세대만 올리고 서버 표를 건드리지 않는다). 루비 판이 진행 중이면 열지 않는다.
    package func startPractice(format: MahjongFormat, timed: Bool) {
        if let current = match?.match, current.matchStatus == .active { return }
        beginPractice(format: format, timed: timed)
    }

    /// 같은 설정으로 새 연습판.
    package func restartPractice() {
        guard let current = practice else { return }
        startPractice(format: current.format, timed: current.timed)
    }

    /// 연습판을 닫는다. 서버 방이 있으면 방이 선다.
    package func endPractice() {
        discardPracticeGame()
        if showsPractice { showsPractice = false }
        recomputePhase()
    }

    /// 띠의 [방 보기] — 연습은 그대로 두고(멈춘 채) 방을 본다.
    package func showRoom() {
        if showsPractice { showsPractice = false }
        syncPracticePause()
        recomputePhase()
    }

    /// 연습으로 돌아가기.
    package func showPractice() {
        guard practice != nil else { return }
        if !showsPractice { showsPractice = true }
        syncPracticePause()
        recomputePhase()
    }

    /// 사람 시계가 다 됐으면 대신 둔다 · '넉넉히' 울기 안내/저절로 넘김 · 보조 쯔모기리(시계 작업이 깨어나 부른다 — 시험은 `now` 를
    /// 넣어 직접 부른다).
    package func handlePracticeClock(now: Date) {
        guard var session = practice, var engine = session.engine, !session.isPaused, !engine.isFinished,
              let decision = engine.decision(for: session.humanSeat) else { return }
        let human = session.humanSeat
        if session.timed, let started = session.humanStartedAt,
           now >= MahjongClock.deadline(started: started, bankMs: session.bankMs)
            .addingTimeInterval(Double(MahjongClock.graceMs) / 1_000) {
            engine.nowMs = practiceServerMs(now)
            let events = engine.timeout(seat: human)
            session.bankMs = 0
            session.engine = engine
            foldTwoStageInputs()
            if events.contains(where: { $0.kind == "win" }) {
                setNotice(nil)
            } else if case .turn = decision {
                setNotice(MahjongNoticeText.timeoutDiscarded)
            } else {
                setNotice(MahjongNoticeText.timeoutPassed)
            }
            commitPractice(session)
            return
        }
        if !session.timed, case .call(let call) = decision, !call.ron, let prompt = session.callPromptAt {
            if now >= prompt.addingTimeInterval(Self.practiceIdleCallPassSeconds) {
                engine.nowMs = practiceServerMs(now)
                _ = engine.call(seat: human, .pass)
                session.engine = engine
                foldTwoStageInputs()
                if notice == MahjongNoticeText.practiceIdleCallHint { setNotice(nil) }
                commitPractice(session)
                return
            }
            if now >= prompt.addingTimeInterval(Self.practiceIdleCallHintSeconds), !session.hintShown {
                session.hintShown = true
                practice = session
                setNotice(MahjongNoticeText.practiceIdleCallHint)
            }
        }
        if let due = session.aidDueAt, now >= due {
            session.aidDueAt = nil
            practice = session
            if case .turn(let turn) = decision, let drawn = session.payload.myDrawn, turn.discard.contains(drawn) {
                practiceAct(.discard(drawn))
                return
            }
        }
        schedulePracticeClock()
    }

    // MARK: 스토어 본문의 앞머리 분기가 부르는 문(사람 동작)

    /// 패를 누름(본문 `discard` 의 연습 갈래). 리치 무장이면 리치 선언 버림, 자리 비움이면 돌아오기.
    func practiceDiscard(_ tile: MahjongTile) {
        guard let session = practice, let engine = session.engine else { return }
        if engine.isAway(session.humanSeat) {
            practiceComeBack()
            return
        }
        guard case .turn(let turn)? = session.payload.myDecision else { return }
        if riichiArmed {
            guard turn.riichi.contains(tile) else { return }
            practiceAct(.riichi(tile))
        } else {
            guard turn.discard.contains(tile) else { return }
            practiceAct(.discard(tile))
        }
    }

    /// 연습판 울기(본문 `call` 의 연습 갈래) — 2단 입력은 서버 판과 같은 규칙(`chooseCallTiles`).
    func practiceCall(_ kind: MahjongClaimKind, tiles: [MahjongTile]) {
        guard case .call(let call)? = practice?.payload.myDecision, call.answered == nil,
              let chosen = chooseCallTiles(kind, tiles: tiles, call: call) else { return }
        // 엔진에는 엔진이 준 조합 그대로(순서 포함)를 돌려준다.
        let option = Self.options(of: kind, in: call).first { $0.sorted() == chosen } ?? chosen
        switch kind {
        case .ron: practiceAnswer(.ron)
        case .pon: practiceAnswer(.pon(option))
        case .minkan: practiceAnswer(.minkan(option))
        case .chi: practiceAnswer(.chi(option))
        }
    }

    /// 차례 동작 한 번(사람).
    func practiceAct(_ action: MahjongTurnAction) {
        practiceHumanStep { .act(seat: $0, action) }
    }

    /// 울기 답 한 번(사람).
    func practiceAnswer(_ answer: MahjongCallAnswer) {
        practiceHumanStep { .call(seat: $0, answer) }
    }

    /// [돌아왔어요] — 자리 비움(실전처럼에서 시간 초과 연속 3)에서 돌아온다.
    func practiceComeBack() {
        guard let session = practice, let engine = session.engine, engine.isAway(session.humanSeat) else { return }
        practiceHumanStep { .back(seat: $0) }
    }

    // MARK: 내부

    /// 사람 걸음 하나 — 멈춘 동안은 받지 않는다. 실패한 걸음도 따라잡기는 남으므로 늘 옮겨 적는다.
    private func practiceHumanStep(_ make: (Int) -> MahjongEngineStep) {
        guard var session = practice, var engine = session.engine, !session.isPaused, !engine.isFinished else { return }
        let now = clock()
        if session.timed, let started = session.humanStartedAt {
            session.bankMs = MahjongClock.charge(started: started, arrived: now, bankMs: session.bankMs).bankLeft
        }
        engine.nowMs = practiceServerMs(now)
        let result = engine.step(make(session.humanSeat))
        session.engine = engine
        switch result {
        case .success:
            foldTwoStageInputs()
            if notice != nil { setNotice(nil) }
        case .failure:
            setNotice(MahjongNoticeText.notAnOption)
        }
        commitPractice(session)
    }

    private func beginPractice(format: MahjongFormat, timed: Bool) {
        let runtime = practiceRuntime
        runtime.cancelTasks()
        let generation = runtime.bump()
        let human = min(max(runtime.pickHumanSeat(), 0), 3)
        var bot = 0
        let seats: [MahjongStateUser?] = (0..<4).map { seat in
            if seat == human {
                return MahjongStateUser(
                    userId: myUserID ?? Self.practiceHumanID, displayName: MahjongNoticeText.practiceMe, avatarUrl: nil,
                    character: nil, center: nil)
            }
            bot += 1
            return MahjongStateUser(
                userId: "\(MahjongStatePayload.practiceIDPrefix)bot-\(bot)",
                displayName: MahjongNoticeText.practiceBotName(bot), avatarUrl: nil,
                character: ShopWire.robotCharacterID, center: nil)
        }
        let id = MahjongStatePayload.practiceIDPrefix + UUID().uuidString.lowercased()
        var engine = MahjongTableEngine(format: format, seats: seats)
        engine.matchID = id
        let now = clock()
        engine.nowMs = practiceServerMs(now)
        _ = engine.deal(wall: runtime.makeWall())
        guard engine.phase != .idle else { return }   // 패산이 순열이 아니다 — 판을 세우지 않는다
        var session = MahjongPracticeSession(
            matchID: id, format: format, timed: timed, humanSeat: human, generation: generation,
            payload: engine.payload(for: human, since: 0, now: now))
        session.engine = engine
        if !isWindowShowingTable {
            session.isPaused = true
            session.pausedAt = now
        }
        practice = session
        foldTwoStageInputs()
        setNotice(nil)
        if !showsPractice { showsPractice = true }
        commitPractice(session)
    }

    /// 사람 자리에 로그인 사용자가 없을 때 쓰는 id(연습판은 로그인 없이도 연다).
    nonisolated static let practiceHumanID = "\(MahjongStatePayload.practiceIDPrefix)me"

    /// 연습판을 버린다(루비 판이 섰다 · 연습 끝내기 · 리셋). `showsPractice` 는 부르는 쪽이 정한다.
    func discardPracticeGame() {
        practiceRuntime.cancelTasks()
        _ = practiceRuntime.bump()
        if practice != nil { practice = nil }
    }

    /// 연습판의 ms 칸은 서버 ms 공간에 둔다(화면은 `serverClockOffset` 한 길로 기기 시각을 얻는다).
    func practiceServerMs(_ date: Date) -> Double {
        (date.timeIntervalSince1970 - serverClockOffset) * 1_000
    }

    /// 사람 결정의 정체성(시계 칸 제외 — 멈췄다 이어 가며 시작 시각을 밀어도 같은 결정이다).
    nonisolated static func practiceAnchor(_ decision: MahjongDecision?, handIndex: Int) -> String? {
        switch decision {
        case .turn(let turn)?: return "\(handIndex)#turn#\(turn.decisionSeq)"
        case .call(let call)?: return "\(handIndex)#call#\(call.windowId)"
        case nil: return nil
        }
    }

    /// 엔진 값을 화면 값으로 옮기고 다음 일을 예약한다. 새 사람 결정이면 시계·안내·2단 입력을 새로 잡는다.
    func commitPractice(_ value: MahjongPracticeSession) {
        var session = value
        guard let engine = session.engine else { return }
        let now = clock()
        // 국이 바뀌면 예비를 다시 20초(국 안 회복 없음 — MJ-53).
        if session.bankHandIndex != engine.handIndex {
            session.bankHandIndex = engine.handIndex
            session.bankMs = MahjongClock.bankFullMs
        }
        let decision = engine.decision(for: session.humanSeat)
        let anchor = Self.practiceAnchor(decision, handIndex: engine.handIndex)
        let isNewDecision = anchor != session.humanAnchor
        if isNewDecision {
            session.humanAnchor = anchor
            session.humanStartedAt = decision == nil ? nil : (session.pausedAt ?? now)
            if case .call(let call)? = decision, !call.ron {
                session.callPromptAt = session.pausedAt ?? now
            } else {
                session.callPromptAt = nil
            }
            session.hintShown = false
            session.aidDueAt = nil
            foldTwoStageInputs()
            if notice == MahjongNoticeText.practiceIdleCallHint { setNotice(nil) }
        }
        if case .claim(let window) = engine.phase {
            if session.windowID != window {
                session.windowID = window
                session.claimReadyAt = (session.pausedAt ?? now)
                    .addingTimeInterval(practiceRuntime.pauseSeconds() * practiceRuntime.delayScale)
            }
        } else {
            session.windowID = nil
            session.claimReadyAt = nil
        }
        let previous = practice?.payload
        session.payload = practicePayload(session, engine: engine, now: now)
        practice = session
        if let previous { noteMotion(previous: previous, next: session.payload) }
        recomputePhase()
        if isNewDecision { runPracticeAids() }
        schedulePracticeTurnIfNeeded()
    }

    /// 엔진 투영 + 연습 시계(실전처럼일 때만 사람 결정에 시작·마감·예비를 싣는다 — 엔진 결정의 시계 칸은 0).
    func practicePayload(_ session: MahjongPracticeSession, engine: MahjongTableEngine, now: Date) -> MahjongStatePayload {
        var payload = engine.payload(for: session.humanSeat, since: 0, now: now)
        payload.serverNowMs = practiceServerMs(now)
        guard session.timed, let started = session.humanStartedAt, let decision = payload.myDecision else { return payload }
        let startedMs = practiceServerMs(started)
        let bank = session.bankMs
        let deadlineMs = startedMs + Double(MahjongClock.baseMs + bank)
        switch decision {
        case .turn(var turn):
            turn.startedMs = startedMs
            turn.deadlineMs = deadlineMs
            turn.bankMs = bank
            payload.myDecision = .turn(turn)
        case .call(var call):
            call.startedMs = startedMs
            call.deadlineMs = deadlineMs
            call.bankMs = bank
            payload.myDecision = .call(call)
        }
        return payload
    }

    /// 멈춤을 다시 잰다: 창이 탁자를 안 보임(숨김·가림) · 방을 보는 중 · 방장 + 넷째 착석. 멈추면 봇·시계 작업을 모두 거두고,
    /// 이어 가면 사람 시계·안내 시계·창 멈춤을 멈춘 만큼 뒤로 민다.
    func syncPracticePause() {
        guard var session = practice else { return }
        let shouldPause = !(isWindowShowingTable && showsPractice) || session.roomHold
        guard shouldPause != session.isPaused else { return }
        let now = clock()
        if shouldPause {
            session.isPaused = true
            session.pausedAt = now
            practice = session
            practiceRuntime.cancelTasks()
            _ = practiceRuntime.bump()
            return
        }
        let paused = session.pausedAt.map { max(0, now.timeIntervalSince($0)) } ?? 0
        session.humanStartedAt = session.humanStartedAt?.addingTimeInterval(paused)
        session.callPromptAt = session.callPromptAt?.addingTimeInterval(paused)
        session.claimReadyAt = session.claimReadyAt?.addingTimeInterval(paused)
        session.aidDueAt = session.aidDueAt?.addingTimeInterval(paused)
        session.isPaused = false
        session.pausedAt = nil
        commitPractice(session)
    }

    /// 연습 중 서버 방(CC-02): **방장**이 보는 방에 넷째가 앉은 순간 연습을 멈춘다(띠 강조 "4명이 모였어요 [시작]").
    /// 방이 넷이 아니게 되면 풀린다. 멤버는 띠 강조만(멈추지 않는다).
    func syncPracticeRoomHold(old: MahjongStatePayload?) {
        guard var session = practice else { return }
        let room = match?.match
        let gathered = room?.matchStatus == .forming && Self.joinedCount(match) >= 4
        var hold = session.roomHold
        if !gathered {
            hold = false
        } else if !hold, isHost, let room, old?.match?.id == room.id, old?.match?.matchStatus == .forming,
                  Self.joinedCount(old) < 4 {
            hold = true
        }
        guard hold != session.roomHold else { return }
        session.roomHold = hold
        practice = session
        syncPracticePause()
    }

    /// 사람 보조(결정마다 한 번 — 연습판은 늘 이 기기 판): 자동 화료 · 울지 않음(국마다 꺼짐) · 쯔모기리(결정 + 0.5~1.0초).
    private func runPracticeAids() {
        guard var session = practice, !session.isPaused, let engine = session.engine,
              let decision = session.payload.myDecision, let anchor = session.humanAnchor else { return }
        let handKey = "\(session.matchID)#\(engine.handIndex)"
        if aids.noCalls {
            if let marked = noCallsHandKey, marked != handKey {
                noCallsHandKey = nil
                aids.noCalls = false
            } else if noCallsHandKey == nil {
                noCallsHandKey = handKey
            }
        }
        switch decision {
        case .turn(let turn):
            if aids.autoWin, turn.tsumo {
                practiceAidHop(anchor) { $0.practiceAct(.tsumo) }
                return
            }
            guard aids.tsumogiri, !turn.tsumo, turn.ankan.isEmpty, turn.kakan.isEmpty, turn.riichi.isEmpty,
                  let drawn = session.payload.myDrawn, turn.discard.contains(drawn) else { return }
            session.aidDueAt = clock().addingTimeInterval(aidJitter() * practiceRuntime.delayScale)
            practice = session
        case .call(let call):
            if aids.autoWin, call.ron {
                practiceAidHop(anchor) { $0.practiceAnswer(.ron) }
            } else if aids.noCalls, !call.ron {
                practiceAidHop(anchor) { $0.practiceAnswer(.pass) }
            }
        }
    }

    /// 보조 동작은 다음 차례로 미뤄 보낸다(옮겨 적기 도중에 다시 들어가지 않게) — 그 사이 결정이 바뀌었으면 안 보낸다.
    private func practiceAidHop(_ anchor: String, _ body: @escaping @MainActor (MahjongStore) -> Void) {
        Task { @MainActor [weak self] in
            guard let self, self.practice?.humanAnchor == anchor, self.practice?.isPaused == false else { return }
            body(self)
        }
    }

    /// 지금 판에서 다음 일을 맡긴다: 봇 차례 · 봇 울기 답(창 멈춤 뒤) · 미룬 쯔모(멈춤 뒤) · 자리 비움 차례 · 다음 국(쉬는 시간 뒤).
    /// 사람 차례면 시계만 건다. 멈춘 동안은 아무것도 맡기지 않는다.
    func schedulePracticeTurnIfNeeded() {
        let runtime = practiceRuntime
        runtime.botTask?.cancel()
        runtime.botTask = nil
        runtime.stepTask?.cancel()
        runtime.stepTask = nil
        let generation = runtime.bump()
        defer { schedulePracticeClock() }
        guard let session = practice, let engine = session.engine, !session.isPaused else { return }
        let human = session.humanSeat
        let scale = runtime.delayScale
        switch engine.phase {
        case .idle, .finished:
            return
        case .handEnd(let result):
            let rest = Self.practiceHandRestSeconds(winners: result.wins?.count ?? 0) * scale
            schedulePracticeStep(.nextHand, after: rest, generation: generation)
        case .drawWait:
            schedulePracticeStep(.wait, after: runtime.pauseSeconds() * scale, generation: generation)
        case .turn(let seat):
            if engine.isAway(seat) {
                schedulePracticeStep(.wait, after: runtime.pauseSeconds() * scale, generation: generation)
            } else if seat != human {
                schedulePracticeBot(seat: seat, notBefore: nil, generation: generation)
            }
        case .claim:
            let pending = engine.pendingSeats
            if let seat = pending.first(where: { $0 != human }) {
                schedulePracticeBot(seat: seat, notBefore: session.claimReadyAt, generation: generation)
            } else if pending.isEmpty {
                schedulePracticeStep(.wait, after: 0, generation: generation)
            }
        }
    }

    enum PracticeStep { case wait, nextHand }

    private func schedulePracticeStep(_ kind: PracticeStep, after seconds: TimeInterval, generation: Int) {
        practiceRuntime.stepTask = Task { @MainActor [weak self] in
            if seconds > 0 { try? await Task.sleep(for: .seconds(seconds)) }
            guard !Task.isCancelled, let self, self.practiceRuntime.generation == generation,
                  var session = self.practice, var engine = session.engine, !session.isPaused else { return }
            self.practiceRuntime.stepTask = nil
            let before = (engine.seq, engine.phase)
            engine.nowMs = self.practiceServerMs(self.clock())
            switch kind {
            case .wait: _ = engine.step(.wait)
            case .nextHand: _ = engine.startNextHand(wall: self.practiceRuntime.makeWall())
            }
            session.engine = engine
            // 아무 일도 안 일어났으면 다시 맡기지 않는다(0초 걸음이 제자리를 도는 일을 막는다 — 흐름 결함의 안전망).
            if engine.seq == before.0, engine.phase == before.1 {
                self.practice = session
                return
            }
            self.commitPractice(session)
        }
    }

    /// 봇 한 자리의 결정을 메인 밖에 맡긴다. 끝나면 세대·판 id·국·seq·대기 자리가 그대로일 때만 반영한다.
    private func schedulePracticeBot(seat: Int, notBefore: Date?, generation: Int) {
        guard let session = practice, let engine = session.engine else { return }
        let runtime = practiceRuntime
        let now = clock()
        let view = engine.payload(for: seat, since: 0, now: now)   // 메인에서 만든 그 자리 시야 사본(값)
        let matchID = session.matchID
        let seq = engine.seq
        let hand = engine.handIndex
        let decide = runtime.decide
        let seed = runtime.nextSeed()
        let scale = runtime.delayScale
        let hold = max(0, notBefore?.timeIntervalSince(now) ?? 0)
        runtime.noteBotCall()
        runtime.botTask = Task { @MainActor [weak self] in
            let started = ContinuousClock.now
            let search = Task.detached(priority: .userInitiated) {
                decide(view, seed) { Task.isCancelled }
            }
            let move = await withTaskCancellationHandler {
                await search.value
            } onCancel: {
                search.cancel()
            }
            var rng = GomokuAISplitMix64(seed: seed ^ 0x9E37_79B9_7F4A_7C15)
            let think = MahjongBot.thinkSeconds(for: move, view: view, rng: &rng) * scale
            let spent = ContinuousClock.now - started
            let remaining = max(think, hold) - (Double(spent.components.seconds) + Double(spent.components.attoseconds) / 1e18)
            if remaining > 0 { try? await Task.sleep(for: .seconds(remaining)) }
            guard let self else { return }
            guard !Task.isCancelled, self.practiceRuntime.generation == generation, let current = self.practice,
                  current.matchID == matchID, !current.isPaused, let live = current.engine, live.seq == seq,
                  live.handIndex == hand, live.pendingSeats.contains(seat)
            else {
                self.practiceRuntime.droppedBotMoves += 1
                return
            }
            self.practiceRuntime.botTask = nil
            self.applyPracticeBotMove(move, seat: seat)
        }
    }

    /// 봇 수를 엔진에 넣는다. 규칙 밖이면(엔진 거절 — 자체 대국 0 건) 판이 멈추지 않게 버림(마지막 후보)·넘김으로 대신 둔다.
    private func applyPracticeBotMove(_ move: MahjongBotMove, seat: Int) {
        guard var session = practice, var engine = session.engine else { return }
        engine.nowMs = practiceServerMs(clock())
        var applied = false
        switch move {
        case .act(let action):
            if case .success = engine.act(seat: seat, action) { applied = true }
        case .call(let windowID, let answer):
            if case .claim(let live) = engine.phase, live == windowID, case .success = engine.call(seat: seat, answer) {
                applied = true
            }
        case .none:
            break
        }
        if !applied, let decision = engine.decision(for: seat) {
            switch decision {
            case .turn(let turn):
                if let tile = turn.discard.last { _ = engine.act(seat: seat, .discard(tile)) }
            case .call:
                _ = engine.call(seat: seat, .pass)
            }
        }
        session.engine = engine
        commitPractice(session)
    }

    /// 사람 시계 작업을 (다시) 건다 — 실전처럼 마감 · '넉넉히' 울기 안내/넘김 · 보조 쯔모기리. 실제 타이머는 `timersEnabled` 일 때만.
    func schedulePracticeClock() {
        let runtime = practiceRuntime
        runtime.clockTask?.cancel()
        runtime.clockTask = nil
        guard timersEnabled, let due = nextPracticeClockDate() else { return }
        let generation = runtime.generation
        let delay = max(0, due.timeIntervalSince(clock())) + 0.02
        runtime.clockTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self, self.practiceRuntime.generation == generation else { return }
            self.practiceRuntime.clockTask = nil
            self.handlePracticeClock(now: self.clock())
        }
    }

    /// 다음으로 사람 시계가 깨어날 때.
    func nextPracticeClockDate() -> Date? {
        guard let session = practice, !session.isPaused, let engine = session.engine,
              engine.decision(for: session.humanSeat) != nil else { return nil }
        var dates: [Date] = []
        if let due = session.aidDueAt { dates.append(due) }
        if session.timed, let started = session.humanStartedAt {
            dates.append(MahjongClock.deadline(started: started, bankMs: session.bankMs)
                .addingTimeInterval(Double(MahjongClock.graceMs) / 1_000))
        } else if let prompt = session.callPromptAt {
            dates.append(prompt.addingTimeInterval(
                session.hintShown ? Self.practiceIdleCallPassSeconds : Self.practiceIdleCallHintSeconds))
        }
        return dates.min()
    }
}
