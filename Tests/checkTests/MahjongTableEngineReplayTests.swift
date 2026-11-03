import CryptoKit
import Foundation
import Testing
@testable import CheckCore

// 아잉 마작 판 진행 Swift(갈래 E)를 판 진행 코퍼스 replay.json(schema `mahjong-replay/1`, 갈래 P1 의 table_ref.py 가 만든 정답지)과 맞춘다.
// SPEC §6.2 '세 구현 대조' 의 Swift 몫 — 같은 대본(걸음)을 엔진에 넣어 사건 요약 · 국 결과 · 점수 · advance · 판 끝 · (손으로 짠 경계
// 레코드만) 걸음마다 결정까지 원문과 같아야 한다. 패산은 레코드가 박은 그대로(무작위 없음).
// 기본 게이트 = 저장소 안 `Fixtures/mahjong/replay.json` — 원본에서 손으로 짠 경계 레코드 55(국 48 · 게임 7) + 무작위 국 표본 10 만 남긴
// 게이트 표본(T, 579KB · 머리 `subset_of` 에 원본 md5). 전부(368 — 국 461 · 걸음 33,829)는 저장소 밖 원본을
// `MAHJONG_REPLAY_ALL=1 MAHJONG_REPLAY_PATH=<MJ/fixtures/replay.json>` 로 준다(경로가 없으면 건너뜀 — 원본 md5 를 잰다).

enum MahjongReplay {
    typealias V = MahjongCorpus.Value

    static let fileName = "replay.json"
    /// P1 이 만든 원본 md5(MJ/reports/P1.md) — 저장소 밖 전부 파일.
    static let sourceMD5 = "59763ce6822a78940842b29637f2d26b"
    /// 저장소 안 게이트 표본 md5(T 가 원본에서 뽑았다 — 다시 뽑으면 이 줄도).
    static let gateMD5 = "1e49eed551d0aa63ed391be0c865ef92"

    nonisolated(unsafe) static let document: [String: Any] = {
        guard let data = try? Data(contentsOf: MahjongCorpus.folder.appendingPathComponent(fileName)),
              let any = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return any
    }()

    /// 전부 파일 경로(`MAHJONG_REPLAY_PATH`) — 저장소 밖. 없으면 nil.
    static var fullPath: String? { ProcessInfo.processInfo.environment["MAHJONG_REPLAY_PATH"] }
    static var fullEnabled: Bool {
        ProcessInfo.processInfo.environment["MAHJONG_REPLAY_ALL"] == "1" && fullPath.map(FileManager.default.fileExists) == true
    }

    nonisolated(unsafe) static let records: [[String: Any]] = document["records"] as? [[String: Any]] ?? []

    static let ids: [String] = records.compactMap { $0["id"] as? String }

    static func record(_ id: String) -> [String: Any]? { records.first { $0["id"] as? String == id } }

    static let craftedIDs: [String] = records.filter { $0["origin"] as? String == "crafted" }.compactMap { $0["id"] as? String }
    static let randomIDs: [String] = records.filter { $0["origin"] as? String == "random" }.compactMap { $0["id"] as? String }
    /// 기본 게이트의 무작위 표본: 게이트 파일의 무작위 레코드 전부(원본 무작위 국 열의 0·30·60…번째 — 뽑기는 파일이 이미 했다).
    static let sampleRandomIDs: [String] = randomIDs

    // MARK: 대본

    static func tiles(_ any: Any?) -> [MahjongTile] {
        ((any as? [Any]) ?? []).compactMap { ($0 as? NSNumber)?.intValue }.compactMap(MahjongTile.init(id:))
    }

    /// 대본 한 걸음 → 엔진 걸음.
    static func step(_ raw: [String: Any]) -> MahjongEngineStep? {
        guard let seat = (raw["seat"] as? NSNumber)?.intValue, let op = raw["op"] as? String else { return nil }
        let action = raw["action"] as? String
        let ts = tiles(raw["tiles"])
        switch op {
        case "act":
            let a: MahjongTurnAction? = switch action {
            case "discard": ts.first.map(MahjongTurnAction.discard)
            case "riichi": ts.first.map(MahjongTurnAction.riichi)
            case "tsumo": .tsumo
            case "ankan": .ankan(ts)
            case "kakan": ts.first.map(MahjongTurnAction.kakan)
            case "kyuushu": .kyuushu
            default: nil
            }
            return a.map { .act(seat: seat, $0) }
        case "call":
            let a: MahjongCallAnswer? = switch action {
            case "ron": .ron
            case "pass": .pass
            case "pon": .pon(ts)
            case "minkan": .minkan(ts)
            case "chi": .chi(ts)
            default: nil
            }
            return a.map { .call(seat: seat, $0) }
        case "timeout": return .timeout(seat: seat)
        case "away": return action.flatMap(MahjongAwayReason.init(rawValue:)).map { .away(seat: seat, $0) }
        case "back": return .back(seat: seat)
        case "wait": return .wait
        default: return nil
        }
    }

    // MARK: 엔진 → 요약(notation.events · result · decisions 모양)

    static func ints(_ xs: [Int]) -> V { .array(xs.map { .number(Double($0)) }) }
    static func idList(_ ts: [MahjongTile]?) -> V { ints((ts ?? []).map(\.id)) }
    static func num(_ x: Int?) -> V { x.map { .number(Double($0)) } ?? .null }

    static func summary(_ e: MahjongEvent) -> V {
        let k = V.string(e.kind)
        switch e.kind {
        case "deal":
            return .array([k, num(e.dealerSeat), num(e.handIndex), num(e.round), num(e.handNo), num(e.honba), num(e.kyotaku),
                           num(e.dora?.first?.id)])
        case "draw": return .array([k, num(e.seat), num(e.tile?.id), .bool(e.rinshan ?? false)])
        case "discard":
            return .array([k, num(e.seat), num(e.tile?.id), .bool(e.tsumogiri ?? false), .bool(e.riichi ?? false), .bool(e.isAutoDiscard)])
        case "call": return .array([k, num(e.seat), .string(e.type ?? ""), idList(e.tiles), num(e.called?.id), num(e.fromSeat)])
        case "kan": return .array([k, num(e.seat), .string(e.type ?? ""), idList(e.tiles)])
        case "dora": return .array([k, .null, num(e.indicator?.id)])
        case "riichi": return .array([k, num(e.seat)])
        case "win": return .array([k, .null, ints(e.seats ?? []), num(e.fromSeat)])
        case "hand_draw": return .array([k, .null, .string(e.reason ?? "")])
        case "scores": return .array([k, .null, ints(e.deltas ?? []), ints(e.scoresAfter ?? [])])
        case "away": return .array([k, num(e.seat), .bool(e.on ?? false), e.reason.map(V.string) ?? .null])
        case "end": return .array([k, .null, .string(e.endReason ?? "")])
        default: return .array([k])
        }
    }

    static func result(_ r: MahjongHandResult, kyotakuAfter: Int) -> V {
        let wins: [V] = (r.wins ?? []).map { w in
            .object([
                "seat": num(w.seat), "from_seat": num(w.fromSeat), "win_tile": num(w.winTile?.id), "hand": idList(w.hand),
                "melds": .array((w.melds ?? []).map { .array([.string($0.type), idList($0.tiles)]) }),
                "yaku": .array((w.yaku ?? []).map { .array([.string($0.id), num($0.han)]) }),
                "yakuman": num(w.yakuman), "han": num(w.han),
                // 역만의 부는 reference 가 null, Swift 는 0(R2 보고 — 같은 뜻).
                "fu": (w.yakuman ?? 0) > 0 && w.fu == 0 ? .null : num(w.fu),
                "limit": .string(w.limit ?? ""), "dora": num(w.dora), "aka": num(w.aka), "ura": num(w.ura),
                "ura_indicators": w.uraIndicators.map { idList($0) } ?? .null,
                "pao": w.pao.map { V.object(["seat": num($0.seat), "yaku": .string($0.yaku ?? "")]) } ?? .null,
            ])
        }
        return .object([
            "kind": .string(r.kind), "reason": r.reason.map(V.string) ?? .null, "wins": .array(wins),
            "tenpai": ints((r.tenpai ?? []).map(\.seat)), "nagashi": ints(r.nagashi ?? []), "bonus_to": num(r.bonusTo),
            "deltas": ints(r.deltas ?? []), "scores_after": ints(r.scoresAfter ?? []), "renchan": .bool(r.renchan ?? false),
            "kyotaku_after": num(kyotakuAfter),
        ])
    }

    /// advance 는 뜻으로 맞춘다 — `extension` 칸이 없으면 거짓(reference 는 연장 판정 갈래에서만 그 칸을 싣는다).
    static func advanceMatches(_ expected: V?, _ got: MahjongAdvance) -> String? {
        guard let e = expected else { return "advance 없음" }
        let next: V = got.next.map { .object(["round": num($0.round), "hand": num($0.hand), "honba": num($0.honba)]) } ?? .null
        let pairs: [(String, V, V)] = [
            ("end", e["end"] ?? .null, .bool(got.end)),
            ("reason", e["reason"] ?? .null, got.reason.map(V.string) ?? .null),
            ("next", e["next"] ?? .null, next),
            ("extension", e["extension"] ?? .bool(false), .bool(got.isExtension)),
        ]
        for (key, a, b) in pairs where a != b { return "advance.\(key): \(a) ≠ \(b)" }
        return nil
    }

    static func final(_ f: MahjongTableEngine.FinalRecord?) -> V {
        guard let f else { return .null }
        return .object(["end_reason": .string(f.endReason), "order": ints(f.order), "ranks": ints(f.ranks),
                        "final_scores": ints(f.finalScores), "kyotaku": num(f.kyotaku)])
    }

    static func decision(_ d: MahjongDecision?) -> V {
        switch d {
        case .turn(let t)?:
            return .object(["kind": .string("turn"), "discard": idList(t.discard), "riichi": idList(t.riichi), "tsumo": .bool(t.tsumo),
                            "ankan": .array(t.ankan.map { idList($0) }), "kakan": idList(t.kakan), "kyuushu": .bool(t.kyuushu)])
        case .call(let c)?:
            return .object(["kind": .string("call"), "window_kind": .string(c.windowKind), "tile": num(c.tile.id),
                            "from_seat": num(c.fromSeat), "ron": .bool(c.ron), "pon": .array(c.pon.map { idList($0) }),
                            "minkan": .array(c.minkan.map { idList($0) }), "chi": .array(c.chi.map { idList($0) })])
        case nil:
            return .null
        }
    }

    /// 첫 차이(table_ref first_diff 꼴).
    static func firstDiff(_ a: V, _ b: V, _ path: String) -> String? {
        switch (a, b) {
        case (.object(let x), .object(let y)):
            for key in Set(x.keys).union(y.keys).sorted() {
                guard let xa = x[key], let yb = y[key] else { return "\(path).\(key): 한쪽에만 있음" }
                if let d = firstDiff(xa, yb, "\(path).\(key)") { return d }
            }
            return nil
        case (.array(let x), .array(let y)):
            for (i, (xa, yb)) in zip(x, y).enumerated() {
                if let d = firstDiff(xa, yb, "\(path)[\(i)]") { return d }
            }
            return x.count == y.count ? nil : "\(path): 길이 \(x.count) ≠ \(y.count)"
        default:
            return a == b ? nil : "\(path): \(a) ≠ \(b)"
        }
    }

    // MARK: 재생

    struct Run {
        var engine: MahjongTableEngine
        var events: [MahjongEvent] = []
        var decisions: [V] = []
        var failure: String?
    }

    /// 레코드 대본을 엔진에 넣는다. each 는 첫 배패 뒤와 걸음마다(성공한 걸음 뒤) 엔진을 본다.
    static func run(_ rec: [String: Any], each: ((MahjongTableEngine, Int) -> Void)? = nil) -> Run {
        let id = rec["id"] as? String ?? "?"
        let format = (rec["format"] as? String).flatMap(MahjongFormat.init(rawValue:)) ?? .tonpuu
        let scores = ((rec["scores"] as? [Any]) ?? []).compactMap { ($0 as? NSNumber)?.intValue }
        func int(_ key: String) -> Int { (rec[key] as? NSNumber)?.intValue ?? 0 }
        let engine = MahjongTableEngine(format: format, seats: [nil, nil, nil, nil], startScores: scores, round: int("round"),
                                        handNo: int("hand_no"), honba: int("honba"), kyotaku: int("kyotaku"))
        var run = Run(engine: engine)
        let walls: [[Int]] = rec["kind"] as? String == "game"
            ? ((rec["walls"] as? [[Any]]) ?? []).map { $0.compactMap { ($0 as? NSNumber)?.intValue } }
            : [((rec["wall"] as? [Any]) ?? []).compactMap { ($0 as? NSNumber)?.intValue }]
        guard let first = walls.first else { run.failure = "\(id): 패산 없음"; return run }
        run.engine.enqueueWalls(Array(walls.dropFirst()))
        let dealt = run.engine.deal(wall: first)
        guard !dealt.isEmpty else { run.failure = "\(id): 배패 실패"; return run }
        run.events += dealt
        each?(run.engine, -1)
        let expect = rec["expect"] as? [String: Any] ?? [:]
        let wantDecisions = expect["decisions"] != nil
        let script = rec["script"] as? [[String: Any]] ?? []
        for (i, raw) in script.enumerated() {
            guard let op = step(raw) else { run.failure = "\(id): 걸음 \(i) 을 못 읽음"; return run }
            var seen: MahjongDecision?? = .none
            var hook: ((MahjongTableEngine) -> Void)?
            let seat = (raw["seat"] as? NSNumber)?.intValue ?? 0
            if wantDecisions, ["act", "call", "timeout"].contains(raw["op"] as? String ?? "") {
                hook = { seen = .some($0.decision(for: seat)) }
            }
            switch run.engine.step(op, onReady: hook) {
            case .success(let evs):
                run.events += evs
            case .failure(let e):
                run.failure = "\(id): 걸음 \(i) \(raw["op"] ?? "")/\(raw["action"] ?? "") 거부 — \(e)"
                return run
            }
            if case .some(let d) = seen { run.decisions.append(.array([.number(Double(i)), .number(Double(seat)), decision(d)])) }
            each?(run.engine, i)
        }
        return run
    }

    /// 레코드 하나를 맞춰 차이 글(없으면 nil).
    static func check(_ rec: [String: Any]) -> String? {
        let id = rec["id"] as? String ?? "?"
        let r = run(rec)
        if let f = r.failure { return f }
        let e = r.engine
        if !e.wallQueue.isEmpty { return "\(id): 쓰지 않은 패산 \(e.wallQueue.count)" }
        let expect = V(rec["expect"] ?? NSDictionary())
        let events = V.array(r.events.map(summary))
        if let d = firstDiff(expect["events"] ?? .null, events, "\(id).events") { return d }
        let records: [MahjongTableEngine.HandRecord] = e.hands
        if rec["kind"] as? String == "hand" {
            guard records.count == 1, e.stage == .handEnd || e.stage == .finished else { return "\(id): 국이 끝나지 않음(\(e.stage))" }
            let h = records[0]
            if let d = firstDiff(expect["result"] ?? .null, result(h.result, kyotakuAfter: h.kyotakuAfter), "\(id).result") { return d }
            if let d = advanceMatches(expect["advance"], h.advance) { return "\(id): \(d)" }
        } else {
            guard e.stage == .finished else { return "\(id): 판이 끝나지 않음(\(e.stage))" }
            let hs = expect["hands"]?.array ?? []
            guard hs.count == records.count else { return "\(id): 국 수 \(hs.count) ≠ \(records.count)" }
            for (i, (want, h)) in zip(hs, records).enumerated() {
                if let d = firstDiff(want["result"] ?? .null, result(h.result, kyotakuAfter: h.kyotakuAfter), "\(id).hands[\(i)].result") { return d }
                if let d = advanceMatches(want["advance"], h.advance) { return "\(id).hands[\(i)]: \(d)" }
            }
        }
        if let d = firstDiff(expect["final"] ?? .null, final(e.finalRecord), "\(id).final") { return d }
        if let want = expect["decisions"], let d = firstDiff(want, .array(r.decisions), "\(id).decisions") { return d }
        return nil
    }
}

@Suite struct MahjongTableEngineReplayTests {
    // 없으면: 픽스처가 P 원본과 달라지거나(옮기다 잘림) 머리 약속(시간 초과 자동 화료·레코드 수)이 엔진 상수와 어긋나도 아무도 모른다.
    @Test func fixtureIsTheP1SourceAndShapesAsDeclared() throws {
        #expect(MahjongCorpus.md5(MahjongReplay.fileName) == MahjongReplay.gateMD5)
        let doc = MahjongReplay.document
        #expect(doc["schema"] as? String == "mahjong-replay/1")
        #expect((doc["timeout_auto_win"] as? Bool) == MahjongRules.timeoutAutoWin)
        #expect(doc["alias_md5"] as? String == MahjongCorpus.md5("corpus_alias.json"))
        let subset = try #require(doc["subset_of"] as? [String: Any])
        #expect(subset["md5"] as? String == MahjongReplay.sourceMD5 && subset["records"] as? Int == 368)
        #expect(MahjongReplay.records.count == 65)
        #expect(MahjongReplay.craftedIDs.count == 55)
        #expect(Set(MahjongReplay.ids).count == MahjongReplay.ids.count)
        #expect(MahjongReplay.sampleRandomIDs.count == 10)
    }

    // 없으면: 경계 국(더블론·창깡·영상·사깡·리치 성립 울림·후리텐·시간 초과 자동 화료·자리 비움 …)의 사건 순서·결과·결정 목록이
    // 파이썬 참조와 갈라져도 초록으로 지나간다.
    @Test(arguments: MahjongReplay.craftedIDs)
    func craftedRecordReplaysExactly(_ id: String) throws {
        let rec = try #require(MahjongReplay.record(id))
        let diff = MahjongReplay.check(rec)
        #expect(diff == nil, "\(diff ?? "")")
    }

    // 없으면: 손으로 짜지 않은 흔한 국(울기 섞인 무작위 정책)의 흐름이 갈라져도 경계 레코드만으로는 못 잡는다.
    @Test(arguments: MahjongReplay.sampleRandomIDs)
    func sampledRandomRecordReplaysExactly(_ id: String) throws {
        let rec = try #require(MahjongReplay.record(id))
        let diff = MahjongReplay.check(rec)
        #expect(diff == nil, "\(diff ?? "")")
    }

    // 없으면: 무작위 국 300 · 동풍전 10 · 반장전 3 의 긴 흐름(남입·서입·토비·오라스)이 갈라져도 기본 게이트는 표본만 본다.
    @Test(.enabled(if: MahjongReplay.fullEnabled, "MAHJONG_REPLAY_ALL=1 MAHJONG_REPLAY_PATH=<저장소 밖 replay.json> 이 있어야 돈다"))
    func everyRecordReplaysExactly() throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: try #require(MahjongReplay.fullPath)))
        #expect(Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined() == MahjongReplay.sourceMD5)
        let doc = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let all = doc["records"] as? [[String: Any]] ?? []
        // 게이트 표본은 원본의 부분집합이다(같은 id 의 레코드가 바이트 값까지 같다).
        let byID = Dictionary(all.map { ($0["id"] as? String ?? "", $0) }, uniquingKeysWith: { a, _ in a })
        for rec in MahjongReplay.records {
            let id = rec["id"] as? String ?? ""
            #expect(byID[id].map { NSDictionary(dictionary: $0).isEqual(to: rec) } == true, "\(id): 게이트 표본이 원본과 다르다")
        }
        var failures: [String] = []
        var hands = 0
        var steps = 0
        for rec in all {
            if let d = MahjongReplay.check(rec) { failures.append(d) }
            hands += rec["kind"] as? String == "game" ? ((rec["walls"] as? [Any])?.count ?? 0) : 1
            steps += (rec["script"] as? [Any])?.count ?? 0
        }
        #expect(failures.isEmpty, "\(failures.count) mismatch: \(failures.prefix(5).joined(separator: " || "))")
        #expect(all.count == 368)
        #expect(hands == 461)
        #expect(steps == 33_829)
    }
}
