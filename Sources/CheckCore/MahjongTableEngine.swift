import Foundation

// 아잉 마작 판 진행 엔진 — 갈래 E(SPEC §4.2 · §3.7 (c)(i) · §6.2). 직접 작성.
// 연습판은 서버 없이 한 판 전체를 기기 안에서 돌린다. 이 엔진은 SQL 결정 엔진(§3.7)·파이썬 참조 `MJ/fixtures/table_ref.py` 와
// **같은 판 흐름·같은 사건 순서**를 내고, 사람 자리 화면·봇은 `payload(for:)` 투영(§3.6 state 모양, 같은 거르기)만 받는다.
// 판정(역·점수·정산·국 끝)은 갈래 R 의 `MahjongScoring`·`MahjongRules` 를 그대로 부른다 — 이 파일들이 새로 정하는 것은 흐름뿐이다.
//
// 걸음(= 서버 RPC 하나, replay 의 걸음 약속 — table_ref 머리 · replay.json `notation.step_order`):
//  · 걸음 = begin + apply. begin: 걸음 번호 +1 → (back 만) 비움을 먼저 푼다 → 따라잡기. apply: 동작(act·call·timeout·away).
//  · 따라잡기는 '때가 된' 일만 한다 — 앞 걸음에서 생긴 쯔모(창이 열리자마자 닫혀 멈춤을 기다리던 것) · 앞 걸음에서 끝난 국의 다음 배패
//    (줄 세운 패산이 있을 때) · 자리 비움 자리의 차례(지금). 이 걸음에서 생긴 쯔모·배패는 다음 걸음이고, 네 자리가 모두 비면 바로 한다.
//  · 창이 마지막 필요한 답(call · 울기 창 timeout · 비움)으로 닫히면 그 걸음 안에서 바로 쯔모한다. 대명깡 영상 쯔모는 울기 확정 걸음 안에서.
//  · 연습판 스토어는 멈춤(0.5~1.0초)이 지나면 `step(.wait)`(= 서버 state 호출)로 미룬 쯔모를 일으킨다 — 시계·멈춤은 바깥이 쥔다.
//  · 실패한 걸음(.failure)도 begin 의 따라잡기는 남는다(서버도 따라잡기 뒤 `illegal` 을 돌려준다). 그 사건은 `payload(since:)` 로 읽는다.
//
// 시간: 엔진은 시계를 읽지 않는다. 사건의 `at_ms` 는 바깥이 넣는 `nowMs`(시간 주입), state 의 `server_now_ms` 는 `payload(now:)`.
// 결정의 시계 칸(started·deadline·bank)은 0/nil(SPEC §4.2) — 5+20 시계는 스토어가 쥔다.
// 숨은 정보: 엔진 안 상태는 모듈 안(internal)에만 있고 `package` 로 새지 않는다. 반환 사건 목록은 **서버 사건 표 원문**(뽑은 패·자동
// 버림 표지 포함)이라 화면·봇에 그대로 넘기지 않는다 — 화면·봇은 `payload(for:)` 만 읽는다.

/// 엔진 판 단계. 서버 내부 phase(§3.7 (a))와 짝 — `turn` · `claim` · `draw_wait` · `hand_end`, 판 끝, 배패 전.
package nonisolated enum MahjongEnginePhase: Equatable, Sendable {
    /// 첫 배패 전.
    case idle
    /// 그 자리 차례 결정(쯔모 뒤·울기 뒤·영상 뒤).
    case turn(Int)
    /// 울기 창(창 번호) — 선택지 있는 자리들의 답을 기다린다.
    case claim(Int)
    /// 창은 닫혔고 그 자리 쯔모를 다음 걸음으로 미뤘다(서버 `draw_wait` — 멈춤).
    case drawWait(Int)
    /// 국 결과를 보여 주는 중.
    case handEnd(MahjongHandResult)
    case finished

    /// state 의 공개 phase 이름(§3.6 — claim·draw_wait 는 둘 다 "wait").
    package var wireName: String {
        switch self {
        case .idle: "room"
        case .turn: "turn"
        case .claim, .drawWait: "wait"
        case .handEnd: "hand_end"
        case .finished: "finished"
        }
    }
}

/// 차례 동작(= `mahjong_act` 의 p_action·p_tiles).
package nonisolated enum MahjongTurnAction: Equatable, Hashable, Sendable {
    case discard(MahjongTile)
    /// 리치 선언패를 버린다.
    case riichi(MahjongTile)
    case tsumo
    /// 네 장.
    case ankan([MahjongTile])
    /// 퐁에 더하는 한 장.
    case kakan(MahjongTile)
    case kyuushu

    /// 서버 p_action 글자.
    package var wireAction: String {
        switch self {
        case .discard: "discard"
        case .riichi: "riichi"
        case .tsumo: "tsumo"
        case .ankan: "ankan"
        case .kakan: "kakan"
        case .kyuushu: "kyuushu"
        }
    }

    package var tiles: [MahjongTile] {
        switch self {
        case .discard(let t), .riichi(let t), .kakan(let t): [t]
        case .ankan(let ts): ts
        case .tsumo, .kyuushu: []
        }
    }
}

/// 울기 창 답(= `mahjong_call` 의 p_action·p_tiles — 손에서 내는 패).
package nonisolated enum MahjongCallAnswer: Equatable, Hashable, Sendable {
    case ron
    case pass
    /// 손에서 내는 두 장.
    case pon([MahjongTile])
    /// 손에서 내는 세 장.
    case minkan([MahjongTile])
    /// 손에서 내는 두 장.
    case chi([MahjongTile])

    package var wireAction: String {
        switch self {
        case .ron: "ron"
        case .pass: "pass"
        case .pon: "pon"
        case .minkan: "minkan"
        case .chi: "chi"
        }
    }

    package var tiles: [MahjongTile] {
        switch self {
        case .ron, .pass: []
        case .pon(let ts), .minkan(let ts), .chi(let ts): ts
        }
    }
}

/// 걸음이 받아지지 않은 까닭(서버 status 어휘와 짝 — not_your_turn · illegal …).
package nonisolated enum MahjongActError: Error, Equatable, Sendable {
    /// 첫 배패 전.
    case notDealt
    /// 국이 끝나 다음 배패 전이거나 판이 끝났다.
    case over
    /// 그 자리 몫 결정이 없다(= not_your_turn).
    case notYourTurn
    /// 고를 수 없는 패·동작(= illegal).
    case illegal
    /// 자리 비움 자리의 직접 동작·이미 비운 자리의 away·비우지 않은 자리의 back.
    case awayState
    /// 패산이 0~135 순열이 아니다.
    case badWall
}

/// 자리 비움 이유(= 서버 away_reason).
package nonisolated enum MahjongAwayReason: String, Equatable, Sendable, CaseIterable {
    case timeouts, leave
    case accountDeleted = "account_deleted"
}

/// 걸음 하나(= 서버 RPC 하나, replay 대본 op 하나).
package nonisolated enum MahjongEngineStep: Equatable, Sendable {
    case act(seat: Int, MahjongTurnAction)
    case call(seat: Int, MahjongCallAnswer)
    /// 그 자리 결정의 마감이 지났다(MJ-54 · SPEC §2.3 K-1 — 론·쯔모 선택지가 있으면 자동 화료).
    case timeout(seat: Int)
    /// 판 중 [나가기]·계정 삭제 등(자기 차례 시간 초과 연속 3 은 엔진이 스스로 건다).
    case away(seat: Int, MahjongAwayReason)
    /// [돌아왔어요] — 따라잡기보다 먼저 푼다(CS-15).
    case back(seat: Int)
    /// 누군가의 state 호출 — 때가 된 일만 돈다(미룬 쯔모·다음 배패·자리 비움 차례).
    case wait
}

/// 연습판·replay 판 진행 엔진. 순수 값(시계·멈춤은 바깥이 쥔다).
package nonisolated struct MahjongTableEngine: Sendable {
    /// 자기 차례 시간 초과가 이만큼 이어지면 자리 비움(= `mahjong_away_after_timeouts()`, §3.7 (b)).
    package static let awayAfterTimeouts = 3
    /// [나가기] 뒤 [돌아왔어요]가 받아지기까지(§3.6 `my_away.back_ready_ms`).
    package static let backCooldownMs: Double = 10_000
    /// state 사건 꼬리 상한(§3.6 — 최대 80).
    package static let eventPageLimit = 80

    package let format: MahjongFormat
    /// state `match.id`(연습판은 `"ai-"` 머리).
    package var matchID: String = MahjongStatePayload.practiceIDPrefix + "practice"
    /// 판돈(연습판 0 — 루비 없음).
    package var stake: Int = 0
    /// 시간 주입 — 이 뒤에 나는 사건의 `at_ms`.
    package var nowMs: Double = 0
    /// 자리마다 사람(봇 포함, 없으면 nil).
    package var users: [MahjongStateUser?]

    // MARK: 판 상태(모듈 안에만 — 숨은 정보)

    var stage: Stage = .idle
    var round: Int
    var handNo: Int
    var honba: Int
    var kyotaku: Int
    var points: [Int]
    var seatState: [Seat]
    var handIndexValue = 0
    var seqValue = 0
    var log: [MahjongEvent] = []
    var hands: [HandRecord] = []
    var finalRecord: FinalRecord?
    var wallQueue: [[Int]] = []
    var stepNo = 0
    var handEndStep = 0
    var opening = false
    var nextHand: MahjongAdvance.Next?
    var showsLastHand = false
    var windowSerial = 0
    var decisionSeqValue = 0

    // MARK: 국 상태

    var wall: [Int] = []
    var ptr = 53
    var kans = 0
    var kanSeats: [Int] = []
    var rinshanUsed = 0
    var timer = MahjongDoraTimer()
    var firstUninterrupted = true
    var firstDiscards: [Int] = []
    var window: Window?
    var pendingDraw: PendingDraw?
    var turnSeat = 0
    var turnRinshan = false

    /// seats = 자리 0~3 사람(모자라면 nil 로 채운다). startScores 합 + 1000 × kyotaku 는 100000 이 정상(엔진은 막지 않는다).
    /// round·handNo·honba·kyotaku 는 replay 처럼 판 중간에서 시작할 때만(연습판은 기본값).
    package init(
        format: MahjongFormat, seats: [MahjongStateUser?], startScores: [Int] = [25000, 25000, 25000, 25000],
        round: Int = 0, handNo: Int = 0, honba: Int = 0, kyotaku: Int = 0
    ) {
        self.format = format
        var u = Array(seats.prefix(4))
        while u.count < 4 { u.append(nil) }
        users = u
        self.round = round
        self.handNo = handNo
        self.honba = honba
        self.kyotaku = kyotaku
        points = startScores.count == 4 ? startScores : [25000, 25000, 25000, 25000]
        seatState = (0..<4).map { Seat(no: $0) }
    }

    // MARK: - 공개 표면(SPEC §4.2)

    /// 첫 국 배패(MJ-08 정본 배치). wall = 136 id 순열. 배패 전에만 받는다(다음 국은 `startNextHand`).
    package mutating func deal(wall: [Int]) -> [MahjongEvent] {
        guard stage == .idle, Self.isPermutation(wall) else { return [] }
        let start = log.count
        dealHand(wall)
        return Array(log[start...])
    }

    /// 다음 국 패산을 줄 세운다 — 국이 끝난 다음 걸음의 따라잡기가 꺼내 배패한다(replay 게임 레코드 · 서버 흐름).
    /// 줄이 비면 국 끝에서 멈추고 `startNextHand(wall:)` 를 기다린다.
    package mutating func enqueueWalls(_ walls: [[Int]]) {
        wallQueue.append(contentsOf: walls.filter(Self.isPermutation))
    }

    package var phase: MahjongEnginePhase {
        switch stage {
        case .idle: .idle
        case .turn: .turn(turnSeat)
        case .claim: .claim(window?.id ?? windowSerial)
        case .draw: .drawWait(pendingDraw?.seat ?? turnSeat)
        case .handEnd:
            .handEnd(hands.last?.result ?? MahjongHandResult(handIndex: handIndexValue, kind: "abortive"))
        case .finished: .finished
        }
    }

    /// = 서버 my_decision(시계 칸은 0/nil). 자리 비움 자리·답한 울기 창은 nil.
    package func decision(for seat: Int) -> MahjongDecision? {
        guard (0..<4).contains(seat), !seatState[seat].away else { return nil }
        switch stage {
        case .turn where turnSeat == seat:
            let o = turnOptions(seat)
            return .turn(.init(
                seq: seqValue, decisionSeq: decisionSeqValue, startedMs: 0, deadlineMs: 0, bankMs: 0,
                discard: Self.tiles(o.discard), riichi: Self.tiles(o.riichi), tsumo: o.tsumo,
                ankan: o.ankan.map(Self.tiles), kakan: Self.tiles(o.kakan), kyuushu: o.kyuushu
            ))
        case .claim:
            guard let w = window, let o = w.options[seat], w.answers[seat] == nil else { return nil }
            return .call(.init(
                windowId: w.id, windowKind: w.kind.rawValue, tile: Self.tile(w.tile), fromSeat: w.from,
                startedMs: 0, deadlineMs: 0, bankMs: 0, ron: o.ron, pon: o.pon.map(Self.tiles),
                minkan: o.minkan.map(Self.tiles), chi: o.chi.map(Self.tiles)
            ))
        default:
            return nil
        }
    }

    package mutating func act(seat: Int, _ action: MahjongTurnAction) -> Result<[MahjongEvent], MahjongActError> {
        step(.act(seat: seat, action))
    }

    package mutating func call(seat: Int, _ answer: MahjongCallAnswer) -> Result<[MahjongEvent], MahjongActError> {
        step(.call(seat: seat, answer))
    }

    /// 그 자리 결정의 시간 초과 — `MahjongRules.timeoutAction` 으로 대신 둔다(v1.0.1 K-1: 론·쯔모 선택지가 있으면 자동 화료,
    /// 자리 비움 자리는 화료하지 않는다). 그 자리 결정이 없으면 [].
    package mutating func timeout(seat: Int) -> [MahjongEvent] {
        (try? step(.timeout(seat: seat)).get()) ?? []
    }

    /// 다음 국 배패(국 끝에서만 — 판이 끝났으면 []).
    package mutating func startNextHand(wall: [Int]) -> [MahjongEvent] {
        guard stage == .handEnd, Self.isPermutation(wall) else { return [] }
        let start = log.count
        startNext(wall)
        return Array(log[start...])
    }

    /// 걸음 하나(begin + apply). onReady 는 따라잡기 뒤·동작 전의 엔진을 본다(act·call·timeout·away — replay 결정 대조용).
    package mutating func step(
        _ op: MahjongEngineStep, onReady: ((MahjongTableEngine) -> Void)? = nil
    ) -> Result<[MahjongEvent], MahjongActError> {
        if stage == .idle { return .failure(.notDealt) }
        if stage == .finished { return .failure(.over) }
        let seat: Int?
        switch op {
        case .act(let s, _), .call(let s, _), .timeout(let s), .away(let s, _), .back(let s): seat = s
        case .wait: seat = nil
        }
        if let seat, !(0..<4).contains(seat) { return .failure(.notYourTurn) }
        if case .back(let s) = op, !seatState[s].away { return .failure(.awayState) }
        let start = log.count
        // begin
        stepNo += 1
        if case .back(let s) = op {
            seatState[s].away = false
            seatState[s].awayReason = nil
            seatState[s].awaySinceMs = nil
            seatState[s].streak = 0
            emit("away", seat: s) { $0.on = false }
        }
        catchup()
        // apply
        switch op {
        case .back, .wait:
            return .success(Array(log[start...]))
        default:
            break
        }
        if stage == .handEnd || stage == .finished { return .failure(.over) }
        onReady?(self)
        let applied: Result<Void, MahjongActError>
        switch op {
        case .act(let s, let action):
            guard stage == .turn, turnSeat == s else { return .failure(.notYourTurn) }
            guard !seatState[s].away else { return .failure(.awayState) }
            applied = doAct(s, action)
            if case .success = applied { seatState[s].streak = 0 }
        case .call(let s, let answer):
            guard stage == .claim, let w = window, w.options[s] != nil, w.answers[s] == nil else { return .failure(.notYourTurn) }
            guard !seatState[s].away else { return .failure(.awayState) }
            applied = self.answer(s, answer)
            if case .success = applied { seatState[s].streak = 0 }
        case .timeout(let s):
            applied = doTimeout(s)
        case .away(let s, let reason):
            guard !seatState[s].away else { return .failure(.awayState) }
            markAway(s, reason)
            applied = .success(())
        case .back, .wait:
            applied = .success(())
        }
        switch applied {
        case .success: return .success(Array(log[start...]))
        case .failure(let e): return .failure(e)
        }
    }

    /// 사람 결정을 기다리는 자리(자리 비움 자리는 따라잡기가 처리한다 — 봇·자체 대국 몰기용).
    package var pendingSeats: [Int] {
        switch stage {
        case .turn:
            return seatState[turnSeat].away ? [] : [turnSeat]
        case .claim:
            guard let w = window else { return [] }
            return w.order.filter { w.options[$0] != nil && w.answers[$0] == nil }
        default:
            return []
        }
    }

    package var scores: [Int] { points }
    package var seq: Int { seqValue }
    package var handIndex: Int { handIndexValue }
    package var isFinished: Bool { stage == .finished }
    /// 자리 비움 칩(공개).
    package func isAway(_ seat: Int) -> Bool { (0..<4).contains(seat) && seatState[seat].away }

    // MARK: - state 투영(§3.6 — 그 자리에 보일 것만)

    /// §3.6 모양 그대로. seat = 보는 자리(nil = 자리 없는 사람 — 공개 칸만). since = 이 seq 뒤 사건만(최대 80, 가장 최근 것).
    package func payload(for seat: Int?, since: Int, now: Date) -> MahjongStatePayload {
        let viewer = seat.flatMap { (0..<4).contains($0) ? $0 : nil }
        let dealt = stage != .idle
        var m = MahjongStateMatch(id: matchID)
        m.status = stage == .finished ? "finished" : "active"
        m.stake = stake
        m.format = format.rawValue
        m.isPublic = false
        m.seq = seqValue
        m.endReason = finalRecord?.endReason
        m.phase = phase.wireName
        if dealt {
            m.handIndex = handIndexValue
            m.round = round
            m.handNo = handNo
            m.honba = honba
            m.kyotaku = kyotaku
            m.dealerSeat = handNo
            m.`extension` = round > (format == .tonpuu ? 0 : 1)
            m.wallRemaining = liveLeft
            m.doraIndicators = Self.tiles(indicators)
            m.kanCount = kans
        }
        m.turnSeat = stage == .turn ? turnSeat : nil
        m.baseMs = MahjongClock.baseMs
        m.bankFullMs = MahjongClock.bankFullMs
        m.graceMs = MahjongClock.graceMs

        let pay = MahjongRules.payouts(stake: stake)
        var rows: [MahjongStateSeat] = []
        for n in 0..<4 {
            let s = seatState[n]
            var row = MahjongStateSeat(seatNo: n)
            row.user = users[n]
            row.wind = Self.windLetters[(n - handNo + 4) % 4]
            row.isDealer = n == handNo
            row.score = points[n]
            row.handCount = s.hand.count + (s.drawn == nil ? 0 : 1)
            row.melds = wireMelds(of: n)
            row.discards = s.discards.map {
                MahjongDiscard(tile: Self.tile($0.tile), tsumogiri: $0.tsumogiri, riichi: $0.riichi, taken: $0.taken)
            }
            row.riichi = s.riichi
            row.away = s.away
            row.deleted = false
            if let fin = finalRecord {
                row.finalRank = fin.ranks[n]
                row.finalScore = fin.finalScores[n]
                row.payout = pay[max(0, min(3, fin.ranks[n] - 1))]
            }
            rows.append(row)
        }
        var p = MahjongStatePayload(match: m, members: [], seats: dealt ? rows : [])
        if let v = viewer {
            let s = seatState[v]
            p.mySeat = v
            p.myHand = Self.tiles(s.hand.sorted())
            p.myDrawn = s.drawn.map(Self.tile)
            p.myWaits = s.waits
            p.myFuriten = s.furiten.kinds(s.waits).map(\.rawValue)
            p.myDecision = decision(for: v)
            if s.away {
                var a = MahjongAwayState()
                a.reason = s.awayReason?.rawValue
                a.sinceMs = s.awaySinceMs
                a.backReadyMs = (s.awaySinceMs ?? nowMs) + (s.awayReason == .leave ? Self.backCooldownMs : 0)
                p.myAway = a
            }
        }
        let fresh = log.filter { $0.seq > since }
        p.events = fresh.suffix(Self.eventPageLimit).map { Self.visible($0, to: viewer) }
        p.lastHand = showsLastHand ? hands.last?.result : nil
        p.reactions = []
        p.serverNowMs = now.timeIntervalSince1970 * 1000
        return p
    }

    /// 사건 한 줄을 보는 자리에 맞게 거른다 — 뽑은 패·자동 버림 표지(priv)는 그 자리 주인에게만(§3.6).
    static func visible(_ event: MahjongEvent, to viewer: Int?) -> MahjongEvent {
        var e = event
        let owner = viewer != nil && e.seat == viewer
        if !owner {
            if e.kind == "draw" { e.tile = nil }
            e.priv = nil
        }
        return e
    }

    /// 부로(원문 꼴). 가깡 창이 열린 동안의 그 퐁은 더한 패까지 가깡으로 보인다(선언은 공개 — kan 사건과 같은 모양).
    func wireMelds(of n: Int) -> [MahjongWireMeld] {
        var melds = seatState[n].melds
        if let w = window, w.kind == .kakan, w.from == n, let i = w.kakanMeld, melds.indices.contains(i) {
            melds[i].type = .kakan
            melds[i].tiles = (melds[i].tiles + [w.tile]).sorted()
        }
        return melds.map { MahjongWireMeld($0.meld) }
    }

    // MARK: - 작은 도우미

    static let windLetters = ["E", "S", "W", "N"]

    static func tile(_ id: Int) -> MahjongTile {
        // 엔진 안 패 id 는 늘 0~135(패산을 순열로 확인한 뒤에만 배패한다).
        MahjongTile(id: id)!
    }

    static func tiles(_ ids: [Int]) -> [MahjongTile] { ids.map(tile) }

    static func isPermutation(_ wall: [Int]) -> Bool {
        wall.count == 136 && wall.sorted() == Array(0..<136)
    }
}
