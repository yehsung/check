// 원본: 없음 — W2-e 대결 재개 골든 `duel/resume`(G §2-3 W2-e ② · C§5.2 G7 의 스토어 몫 · §8-3 `duel` 폴더). 원본 스토어는
// Sources/CheckCore/TetrisDuelStore.swift · TetrisDuelStoreGame.swift @ 1b8260d. Kotlin 대조: multiplatform/core/stores/src/commonTest/…/tetris/
// TetrisDuelResumeGoldenTest.kt.
import CheckGoldenSupport
import Foundation
import Testing
@testable import CheckCore

// 대결 재개 골든(스토어 몫). W1-a `tetris/duel` 은 **세션**(TetrisDuelSession) 대본이고, 이 골든은 그 위의 **스토어 깔때기**를 잰다:
//   · `resumePoint(me:startAtMs:)` — 서버의 내 행에서 재개 출발점을 고르는 순수 판정(표).
//   · `applyState` 흐름 — 같은 판을 처음 보는 프로세스가 서버 행에서 판을 다시 세우는가(재개) / 새 판으로 여는가, 늦은 응답 가드 넷,
//     서버 seq 따라잡기, 상대 공격 누계 차분, 끝남·접기, 그리고 그 사이 `tick`·입력 문이 판을 어떻게 미는가.
// 스토어는 호스트 없이(host == nil) 돈다 — 네트워크를 한 건도 내지 않는다(perform 이 nil). 그래서 내 user id 를 모르고, 승자 칸이 있으면
// 결과는 언제나 `lost` 다(스토어 규칙 그대로 — 무승부는 result 글자로 가른다). 시계는 둘 다 주입한다: 벽시계 고정 · 단조 시계는 단계가 준다.
// 판 루프는 재운다(gameLoopStepSeconds 3600 — Kotlin 은 무한). 단계 결과마다 스토어 끝 상태를 덤프한다(아래 `dump`).

@MainActor
@Suite("GoldenExport duel — 대결 재개(스토어): resumePoint 표 · applyState 흐름(재개 · 새 판 · 가드 · 끝남)")
struct GoldenExportDuel {
    static let store = "Sources/CheckCore/TetrisDuelStore.swift"
    static let storeGame = "Sources/CheckCore/TetrisDuelStoreGame.swift"
    static let session = "Sources/CheckCore/TetrisDuelSession.swift"
    static let board = "Sources/CheckCore/TetrisDuelBoard.swift"
    static let engine = "Sources/CheckCore/TetrisGame.swift"
    static let wire = "Sources/CheckCore/TetrisWire.swift"

    /// 벽시계(1970 기준 초 — SessionClock.demoInstant 와 같은 2026-09-17 14:05 KST).
    static let wallBase: Double = 1_789_621_500
    /// 서버 시계는 기기보다 0.4초 앞이다(오프셋 측정이 덤프에 남는다).
    static let serverAheadMs: Double = 400
    static var serverNowMs: Double { (wallBase * 1000) + serverAheadMs }

    static let me = "aaaaaaaa-0000-4000-8000-000000000001"
    static let peer = "bbbbbbbb-0000-4000-8000-000000000002"
    static let other = "cccccccc-0000-4000-8000-000000000003"

    /// 판 글자 견본(W1-a duelSample 과 같은 모양 — 아래 5행에 조각·방해 줄).
    static let sample = String(repeating: ".", count: 150) + "..IJLOSTZ." + "G.GGGGGGGG" + "ZZ.TTTOO.I" + "GGGG.GGGGG" + "LJLJ.SSZZI"
    static let peerBoard = String(repeating: ".", count: 170) + "T........." + "GGGGG.GGGG" + "SSZZ.IIIIJ"
    static let empty = String(repeating: ".", count: 200)

    // MARK: 재료

    static func player(id: String, seq: Int?, board: String?, lines: Int? = nil, sent: Int? = nil, applied: Int? = nil,
                       pending: Int? = nil, lastSeenMs: Double? = nil, ready: Bool? = nil, topped: Bool? = nil,
                       name: String? = nil) -> GoldenJSON {
        var members: [String: GoldenJSON] = ["id": .string(id)]
        if let name { members["display_name"] = .string(name) }
        if let seq { members["seq"] = .int(seq) }
        if let board { members["board"] = .string(board) }
        if let lines { members["lines"] = .int(lines) }
        if let sent { members["garbage_sent"] = .int(sent) }
        if let applied { members["garbage_applied"] = .int(applied) }
        if let pending { members["pending"] = .int(pending) }
        if let lastSeenMs { members["last_seen_ms"] = .int(Int(lastSeenMs)) }
        if let ready { members["ready"] = .bool(ready) }
        if let topped { members["topped_out"] = .bool(topped) }
        return .object(members)
    }

    static func payload(id: String = "match-a", status: String, stake: Int? = 5, seed: Int? = 77, startAtMs: Double? = nil,
                        serverNowMs: Double? = GoldenExportDuel.serverNowMs, me: GoldenJSON? = nil, opponent: GoldenJSON? = nil,
                        extra: [String: GoldenJSON] = [:]) -> GoldenJSON {
        var members: [String: GoldenJSON] = ["match_id": .string(id), "status": .string(status)]
        if let stake { members["stake"] = .int(stake) }
        if let seed { members["seed"] = .int(seed) }
        if let startAtMs { members["start_at_ms"] = .int(Int(startAtMs)) }
        if let serverNowMs { members["server_now_ms"] = .int(Int(serverNowMs)) }
        if let me { members["me"] = me }
        if let opponent { members["opponent"] = opponent }
        for (key, value) in extra { members[key] = value }
        return .object(members)
    }

    static func decodePayload(_ json: GoldenJSON) throws -> TetrisStatePayload {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(TetrisStatePayload.self, from: try json.canonicalData())
    }

    // MARK: 단계

    enum Step {
        case apply(GoldenJSON, receivedAt: Double)
        case tick(Double)
        /// 입력 문 하나(단조 시계를 그 시각에 둔 뒤 부른다).
        case input(String, at: Double)
        /// 창을 정말 닫았다(끝난 판 접기).
        case close

        var json: GoldenJSON {
            switch self {
            case .apply(let payload, let at): return ["op": "apply", "payload": payload, "receivedAtBits": .bits(at)]
            case .tick(let now): return ["op": "tick", "nowBits": .bits(now)]
            case .input(let key, let at): return ["op": "input", "key": .string(key), "uptimeBits": .bits(at)]
            case .close: return ["op": "close"]
            }
        }
    }

    static func runInput(_ key: String, on store: TetrisDuelStore) {
        switch key {
        case "left": store.setLeftHeld(true); store.setLeftHeld(false)
        case "right": store.setRightHeld(true); store.setRightHeld(false)
        case "moveLeftOne": store.moveLeftOneCell()
        case "moveRightOne": store.moveRightOneCell()
        case "softDropOne": _ = store.softDropOneCell()
        case "rotateCW": store.rotate(clockwise: true)
        case "rotateCCW": store.rotate(clockwise: false)
        case "hold": store.hold()
        case "hardDrop": store.hardDrop()
        default: preconditionFailure("모르는 입력 \(key)")
        }
    }

    // MARK: 덤프 (Kotlin 이 같은 칸을 같은 표기로 만든다 — spec.dump)

    static let letters: [Character] = ["i", "j", "l", "o", "s", "t", "z"]

    static func date(_ d: Date?) -> GoldenJSON { d.map { .bits($0.timeIntervalSince1970) } ?? .null }

    static func phaseName(_ p: TetrisDuelPhase) -> String {
        switch p {
        case .lobby: return "lobby"
        case .ready: return "ready"
        case .countdown: return "countdown"
        case .playing: return "playing"
        case .finished: return "finished"
        }
    }

    static func gamePhase(_ p: TetrisGame.Phase) -> GoldenJSON {
        switch p {
        case .ready: return ["kind": "ready"]
        case .running: return ["kind": "running"]
        case .lineClear(let left): return ["kind": "lineClear", "remainingBits": .bits(left)]
        case .are(let left): return ["kind": "are", "remainingBits": .bits(left)]
        case .over(let hold): return ["kind": "over", "holdBits": .bits(hold)]
        case .result: return ["kind": "result"]
        }
    }

    static func cellsText(_ cells: [[TetrisDuelCell]]) -> String {
        cells.map { row in
            String(row.map { cell -> Character in
                switch cell {
                case .empty: return "."
                case .garbage: return "G"
                case .piece(let p): return TetrisDuelBoard.letter(for: p)
                }
            })
        }.joined(separator: "/")
    }

    static func dump(_ store: TetrisDuelStore) -> GoldenJSON {
        var out: [String: GoldenJSON] = [
            "phase": .string(phaseName(store.phase)),
            "notice": store.notice.map(GoldenJSON.string) ?? .null,
            "spectatorCount": .int(store.spectatorCount),
            "heldMySeq": .int(store.heldMySeq),
            "heldOpponentSeq": .int(store.heldOpponentSeq),
            "opponentAttackTotal": .int(store.opponentAttackTotal),
            "opponentLastSeenAtBits": date(store.opponentLastSeenAt),
            "activeMatchID": store.activeMatchID.map(GoldenJSON.string) ?? .null,
            "rubyBalance": store.rubyBalance.map(GoldenJSON.int) ?? .null,
            "serverClockOffsetBits": .bits(store.serverClockOffset),
            "duelMatchID": store.duelMatchID.map(GoldenJSON.string) ?? .null,
            "dismissed": .array(store.dismissedMatchIDs.sorted().map(GoldenJSON.string)),
        ]
        if let match = store.match {
            out["match"] = [
                "id": .string(match.id),
                "stake": .int(match.stake),
                "seed": match.seed.map(GoldenJSON.int) ?? .null,
                "opponentID": .string(match.opponent.id),
                "opponentName": .string(match.opponent.displayName),
                "acceptedAtBits": date(match.acceptedAt),
                "readyDeadlineBits": date(match.readyDeadline),
                "startAtBits": date(match.startAt),
                "maxEndBits": date(match.maxEnd),
                "finishedAtBits": date(match.finishedAt),
                "meReady": .bool(match.meReady),
                "isFinished": .bool(match.isFinished),
                "outcome": match.outcome.map { o -> GoldenJSON in
                    switch o {
                    case .won: return "won"
                    case .lost: return "lost"
                    case .draw: return "draw"
                    }
                } ?? .null,
                "endReason": match.endReason.map { GoldenJSON.string($0.rawValue) } ?? .null,
                "rubyDelta": match.rubyDelta.map(GoldenJSON.int) ?? .null,
                "opponentBoard": [
                    "hasBoard": .bool(match.opponentBoard.hasBoard),
                    "lines": .int(match.opponentBoard.lines),
                    "attackSent": .int(match.opponentBoard.attackSent),
                    "pending": .int(match.opponentBoard.pending),
                    "toppedOut": .bool(match.opponentBoard.toppedOut),
                    "ready": .bool(match.opponentBoard.ready),
                    "cells": .string(cellsText(match.opponentBoard.cells)),
                ],
            ]
        } else {
            out["match"] = .null
        }
        if let stats = store.myStats {
            out["myStats"] = [
                "lines": .int(stats.lines), "attackSent": .int(stats.attackSent), "pendingGarbage": .int(stats.pendingGarbage),
                "levelFloor": .int(stats.levelFloor), "toppedOut": .bool(stats.toppedOut),
            ]
        } else {
            out["myStats"] = .null
        }
        if let duel = store.duel {
            let g = duel.game
            out["duel"] = [
                "seed": .int(duel.seed),
                "seq": .int(duel.seq),
                "garbageApplied": .int(duel.garbageApplied),
                "started": .bool(duel.started),
                "finished": .bool(duel.finished),
                "startAtBits": duel.startAt.map(GoldenJSON.bits) ?? .null,
                "simulatedBits": .bits(duel.simulated),
                "droppedSecondsBits": .bits(duel.droppedSeconds),
                "lastReportAtBits": duel.lastReportAt.map(GoldenJSON.bits) ?? .null,
                "reportedAttackSent": .int(duel.reportedAttackSent),
                "isLive": .bool(duel.isLive),
                "toppedOut": .bool(duel.toppedOut),
                "board": .string(TetrisDuelBoard.encode(g)),
                "active": g.active.map { a -> GoldenJSON in
                    ["piece": .string(String(letters[a.piece.rawValue])), "rotation": .int(a.rotation.rawValue),
                     "column": .int(a.column), "row": .int(a.row)]
                } ?? .null,
                "next": .string(String(g.next.prefix(5).map { letters[$0.rawValue] })),
                "held": .string(g.heldPiece.map { String(letters[$0.rawValue]) } ?? "-"),
                "holdUsed": .bool(g.holdUsed),
                "score": .int(g.score),
                "lines": .int(g.lines),
                "attackSentTotal": .int(g.attackSentTotal),
                "pendingGarbage": .array(g.pendingGarbage.map(GoldenJSON.int)),
                "levelFloor": .int(g.levelFloor),
                "phase": gamePhase(g.phase),
                "elapsedBits": .bits(g.elapsed),
            ]
        } else {
            out["duel"] = .null
        }
        return .object(out)
    }

    // MARK: 흐름

    static func run(_ steps: [Step]) throws -> [GoldenJSON] {
        let store = TetrisDuelStore(host: nil)
        store.clock = { Date(timeIntervalSince1970: wallBase) }
        var now: TimeInterval = 0
        store.uptime = { now }
        store.gameLoopStepSeconds = 3600
        store.pollStepSeconds = 3600
        var results: [GoldenJSON] = []
        for step in steps {
            var record: [String: GoldenJSON] = [:]
            switch step {
            case .apply(let json, let at):
                now = at
                let outcome = store.applyState(try decodePayload(json), receivedAt: at)
                record["apply"] = .string(outcome == .applied ? "applied" : "ignored")
            case .tick(let t):
                now = t
                store.tick(now: t)
            case .input(let key, let at):
                now = at
                runInput(key, on: store)
            case .close:
                store.windowDidClose()
            }
            record["state"] = dump(store)
            results.append(.object(record))
        }
        store.stopGameLoop()
        return results
    }

    static var flows: [(String, [Step])] {
        let start = serverNowMs - 40_000
        let resumeMe = player(id: me, seq: 12, board: sample, lines: 9, sent: 7, applied: 4, pending: 2,
                              lastSeenMs: start + 35_000, ready: true)
        let resumePeer = player(id: peer, seq: 20, board: peerBoard, lines: 3, sent: 9, applied: 1, pending: 0,
                                lastSeenMs: serverNowMs - 600, ready: true, name: "구름빵")
        let stalePeer = player(id: peer, seq: 19, board: empty, lines: 2, sent: 8, applied: 1, pending: 0,
                               lastSeenMs: serverNowMs - 1600, ready: true, name: "구름빵")
        let laterMe = player(id: me, seq: 14, board: sample, lines: 10, sent: 7, applied: 9, pending: 0,
                             lastSeenMs: start + 41_000, ready: true)
        let laterPeer = player(id: peer, seq: 22, board: peerBoard, lines: 5, sent: 12, applied: 1, pending: 1,
                               lastSeenMs: serverNowMs + 1000, ready: true, name: "구름빵")
        let finishedExtra: [String: GoldenJSON] = [
            "winner": .string(peer.uppercased()), "result": "opponent_win", "end_reason": "topout",
            "ruby_balance": 120, "finished_at_ms": .int(Int(serverNowMs + 2000)), "watchers": 2,
        ]
        let countdownStart = serverNowMs + 3000
        let readyMe = player(id: me, seq: 0, board: nil, ready: false)
        let readyPeer = player(id: peer, seq: 0, board: nil, ready: true, name: "달토끼")
        let readyMe2 = player(id: me, seq: 1, board: empty, lastSeenMs: serverNowMs - 200, ready: true)
        return [
            ("flow-resume", [
                .apply(payload(status: "active", startAtMs: start, me: resumeMe, opponent: resumePeer,
                               extra: ["accepted_at_ms": .int(Int(start - 10_000)), "ready_deadline_ms": .int(Int(start + 20_000)),
                                       "max_end_ms": .int(Int(start + 480_000)), "watchers": 3]), receivedAt: 100),
                .tick(100.5),
                .input("hardDrop", at: 100.6),
                .apply(payload(status: "active", startAtMs: start, me: resumeMe, opponent: stalePeer), receivedAt: 100.7),
                .apply(payload(status: "active", startAtMs: start, me: laterMe, opponent: laterPeer), receivedAt: 101),
                .tick(102),
                .input("rotateCW", at: 102.1),
                .input("moveLeftOne", at: 102.2),
                .tick(103.25),
                .apply(payload(status: "finished", startAtMs: start, me: laterMe, opponent: laterPeer, extra: finishedExtra),
                       receivedAt: 104),
                .tick(105),
                .close,
                .apply(payload(status: "finished", startAtMs: start, me: laterMe, opponent: laterPeer, extra: finishedExtra),
                       receivedAt: 106),
            ]),
            ("flow-countdown", [
                .apply(payload(id: "match-b", status: "active", stake: 3, seed: 1_234_567, me: readyMe, opponent: readyPeer), receivedAt: 200),
                .tick(200.5),
                .apply(payload(id: "match-b", status: "active", stake: 3, seed: 1_234_567, startAtMs: countdownStart,
                               me: readyMe2, opponent: readyPeer), receivedAt: 201),
                .tick(202),
                .input("left", at: 202.5),
                .tick(204.05),
                .input("moveRightOne", at: 204.1),
                .input("rotateCCW", at: 204.2),
                .input("hold", at: 204.3),
                .input("softDropOne", at: 204.4),
                .input("right", at: 204.5),
                .input("hardDrop", at: 204.6),
                .tick(206),
                .apply(payload(id: "match-b", status: "finished", stake: 3, seed: 1_234_567, startAtMs: countdownStart,
                               me: readyMe2, opponent: readyPeer, extra: ["result": "draw", "end_reason": "time_cap"]), receivedAt: 207),
            ]),
            ("flow-resume-rejected", [
                // 시작 전 하트비트만 받은 행(last_seen ≤ start) — 새 판이고 누계는 서버 값에서 잇는다.
                .apply(payload(id: "match-c", status: "active", seed: 42, startAtMs: serverNowMs - 5000,
                               me: player(id: me, seq: 5, board: sample, applied: 3, lastSeenMs: serverNowMs - 5000, ready: true),
                               opponent: player(id: peer, seq: 2, board: empty, sent: 6, ready: true)), receivedAt: 300),
                .tick(301),
                // 다른 판이 진행 중인데 지나간 판의 늦은 응답 — 무시(구동기는 그대로).
                .apply(payload(id: "match-d", status: "active", seed: 9, startAtMs: serverNowMs - 1000,
                               me: player(id: me, seq: 3, board: sample, lastSeenMs: serverNowMs, ready: true)), receivedAt: 301.5),
                // 모르는 status — 아무것도 바꾸지 않는다.
                .apply(payload(id: "match-c", status: "paused"), receivedAt: 302),
                // 끝남 → 같은 판의 진행 중 응답(끝나기 전에 읽힌 옛 스냅숏) — 무시.
                .apply(payload(id: "match-c", status: "finished", seed: 42, startAtMs: serverNowMs - 5000,
                               me: player(id: me, seq: 9, board: sample, ready: true),
                               extra: ["result": "draw", "end_reason": "disconnect", "winner": .null]), receivedAt: 303),
                .apply(payload(id: "match-c", status: "active", seed: 42, startAtMs: serverNowMs - 5000,
                               me: player(id: me, seq: 10, board: sample, ready: true)), receivedAt: 304),
                // 깨진 판 글자 + 판 시작 뒤 보고 — 새 판(깨진 판을 지어내지 않는다).
                .apply(payload(id: "match-e", status: "active", seed: 7, startAtMs: serverNowMs - 9000,
                               me: player(id: me, seq: 4, board: String(sample.dropLast()), applied: 2, lastSeenMs: serverNowMs - 1000,
                                           ready: true),
                               opponent: player(id: other, seq: 1, board: "X" + String(empty.dropFirst()), sent: 1)), receivedAt: 305),
                .tick(306),
                // 판이 사라졌다(declined 는 신청 갈래 — 들고 있던 판이면 판을 내린다).
                .apply(payload(id: "match-e", status: "declined"), receivedAt: 307),
            ]),
        ]
    }

    /// `resumePoint(me:startAtMs:)` 표 — (id, me 행 JSON, startAtMs).
    static var resumeCases: [(String, GoldenJSON?, Double?)] {
        let start = 1_789_621_000_000.0
        return [
            ("ok", player(id: me, seq: 12, board: sample, lines: 9, sent: 7, applied: 4, pending: 2, lastSeenMs: start + 35_250), start),
            ("ok-defaults", player(id: me, seq: 1, board: empty, lastSeenMs: start + 1), start),
            ("no-row", nil, start),
            ("seq-zero", player(id: me, seq: 0, board: sample, lastSeenMs: start + 5000), start),
            ("seq-missing", player(id: me, seq: nil, board: sample, lastSeenMs: start + 5000), start),
            ("board-missing", player(id: me, seq: 3, board: nil, lastSeenMs: start + 5000), start),
            ("board-short", player(id: me, seq: 3, board: String(sample.dropLast()), lastSeenMs: start + 5000), start),
            ("board-bad-letter", player(id: me, seq: 3, board: "x" + String(sample.dropFirst()), lastSeenMs: start + 5000), start),
            ("start-missing", player(id: me, seq: 3, board: sample, lastSeenMs: start + 5000), nil),
            ("last-seen-missing", player(id: me, seq: 3, board: sample), start),
            ("last-seen-equal", player(id: me, seq: 3, board: sample, lastSeenMs: start), start),
            ("last-seen-before", player(id: me, seq: 3, board: sample, lastSeenMs: start - 1), start),
            ("negative-counts", player(id: me, seq: 2, board: sample, lines: -3, sent: -1, applied: -2, pending: -4,
                                       lastSeenMs: start + 999), start),
        ]
    }

    @Test("duel/resume — resumePoint 표 13 · applyState 흐름 셋(재개 · 카운트다운 · 거절·가드)")
    func resume() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        var cases: [GoldenJSON] = []
        for (id, row, startAtMs) in Self.resumeCases {
            let decoded = try row.map { try decoder.decode(TetrisPlayerRow.self, from: try $0.canonicalData()) }
            let point = TetrisDuelStore.resumePoint(me: decoded, startAtMs: startAtMs)
            cases.append([
                "id": .string("resume-\(id)"),
                "me": row ?? .null,
                "startAtMs": startAtMs.map { .int(Int($0)) } ?? .null,
                "point": point.map { p -> GoldenJSON in
                    ["seq": .int(p.seq), "board": .string(p.board), "lines": .int(p.lines), "garbageSent": .int(p.garbageSent),
                     "garbageApplied": .int(p.garbageApplied), "pending": .int(p.pending), "elapsedBits": .bits(p.elapsedSeconds)]
                } ?? .null,
            ])
        }
        for (id, steps) in Self.flows {
            cases.append([
                "id": .string(id),
                "steps": .array(steps.map(\.json)),
                "results": .array(try Self.run(steps)),
            ])
        }
        goldenEmit(GoldenFile(
            golden: "duel/resume",
            equivalence: .bit,
            swiftSources: [Self.store, Self.storeGame, Self.session, Self.board, Self.engine, Self.wire],
            spec: [
                "store": "TetrisDuelStore(host: nil) — 네트워크 0. clock = wallBase 고정, uptime = 단계가 준 시각, 판 루프·폴링은 재운다",
                "wallBase": .bits(Self.wallBase),
                "payload": "TetrisStatePayload 를 snake_case JSON 으로 싣는다(JSONDecoder convertFromSnakeCase · Kotlin @SerialName)",
                "steps": "apply(payload, receivedAt) → applyState · tick(now) → tick(now:) · input(key, at) → 입력 문(left/right = 누름+뗌) · close → windowDidClose()",
                "results": "단계마다 { apply?: applied|ignored, state: dump }",
                "dump": "phase · notice · match(…, opponentBoard.cells 20행 '/') · myStats · duel(세션 칸 + 엔진 판 TetrisDuelBoard.encode · active · next 5 · …) · 장부(heldMySeq …)",
                "outcome": "host 가 없어 내 user id 를 모른다 → 승자 칸이 있으면 lost(스토어 규칙), result 'draw' 면 draw",
                "resume-*": "TetrisDuelStore.resumePoint(me:startAtMs:) — 판 시작 뒤 보고만 재개 출발점(null = 새 판)",
            ],
            cases: cases
        ))
    }
}
