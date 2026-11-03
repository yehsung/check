import CryptoKit
import Foundation
import Testing
@testable import CheckCore

// 아잉 마작 손 계산(역·부·점수)·점수표·화료 정산을 판정 코퍼스(cases.json — rules.md MJ-nn 의 정답지)와 맞춘다.
//
// 코퍼스는 `Fixtures/mahjong/cases.json`(mj/research/cases.json 의 바이트 그대로 — md5 를 잰다). 사례는 **id 로 집는다**.
// 천화·지화의 흔한 로마자는 상표 시험 패턴과 같은 글자라(SPEC D5) 이 저장소의 코드에는 쓰지 않는다 — 별칭 표
// `Fixtures/mahjong/corpus_alias.json` 을 읽어 코퍼스의 깃발 키·역 id·사례 id 를 `heavenly`·`earthly` 로 바꾼 뒤 쓴다.
// 비교는 reference.py `_sub` 와 같다: 기대값에 있는 키만 본다. 결과는 reference `_hand_view` 꼴로 그려 견준다
// (honba_bonus 는 Swift 의 정수 합을 쯔모 여부로 `{ron:n}`·`{from_each:n}` 사전에 되돌린다 · 역만의 fu 0 은 null).

/// 코퍼스·대조 손 읽기 — 마작 규칙 시험 파일들이 같이 쓴다(MahjongHand·RulesCorpus·Xval·Contract).
enum MahjongCorpus {
    /// JSON 값(Sendable — 정적 캐시에 담으려고 Any 를 한 번 옮긴다).
    indirect enum Value: Equatable, Sendable, CustomStringConvertible {
        case null, bool(Bool), number(Double), string(String), array([Value]), object([String: Value])

        init(_ any: Any) {
            switch any {
            case let n as NSNumber where CFGetTypeID(n) == CFBooleanGetTypeID(): self = .bool(n.boolValue)
            case let n as NSNumber: self = .number(n.doubleValue)
            case let s as String: self = .string(s)
            case let a as [Any]: self = .array(a.map(Value.init))
            case let o as [String: Any]: self = .object(o.mapValues(Value.init))
            default: self = .null
            }
        }

        subscript(_ key: String) -> Value? {
            if case .object(let o) = self { return o[key] }
            return nil
        }

        var int: Int? { if case .number(let d) = self { return Int(exactly: d) }; return nil }
        var string: String? { if case .string(let s) = self { return s }; return nil }
        var bool: Bool? { if case .bool(let b) = self { return b }; return nil }
        var array: [Value]? { if case .array(let a) = self { return a }; return nil }
        var object: [String: Value]? { if case .object(let o) = self { return o }; return nil }
        var isNull: Bool { self == .null }

        var description: String {
            switch self {
            case .null: "null"
            case .bool(let b): "\(b)"
            case .number(let d): Int(exactly: d).map { "\($0)" } ?? "\(d)"
            case .string(let s): "\"\(s)\""
            case .array(let a): "[" + a.map(\.description).joined(separator: ",") + "]"
            case .object(let o): "{" + o.keys.sorted().map { "\($0):\(o[$0]!.description)" }.joined(separator: ",") + "}"
            }
        }
    }

    static let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/mahjong")

    static func load(_ name: String) -> Value {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(name)),
              let any = try? JSONSerialization.jsonObject(with: data) else { return .null }
        return Value(any)
    }

    static func md5(_ name: String) -> String {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(name)) else { return "" }
        return Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// 별칭 표(코퍼스 글자 → 저장소 글자). 시험 코드에는 그 글자를 쓰지 않는다 — 파일에서만 온다.
    static let alias: [String: String] = load("corpus_alias.json").object?.compactMapValues(\.string) ?? [:]

    /// 별칭 적용: 객체 키와 **글자 전체가 같은** 문자열 값을 바꾼다(제목·근거 같은 긴 글은 건드리지 않는다).
    static func applyAlias(_ v: Value) -> Value {
        switch v {
        case .string(let s): return .string(alias[s] ?? s)
        case .array(let a): return .array(a.map(applyAlias))
        case .object(let o):
            var out: [String: Value] = [:]
            for (k, x) in o { out[alias[k] ?? k] = applyAlias(x) }
            return .object(out)
        default: return v
        }
    }

    /// 사례 id 의 별칭(대소문자 무시 — 사례 id 는 대문자).
    static func aliasID(_ id: String) -> String {
        var out = id
        for (from, to) in alias { out = out.replacingOccurrences(of: from, with: to.uppercased(), options: .caseInsensitive) }
        return out
    }

    /// 사례 하나(별칭 적용 뒤).
    struct Case: Sendable {
        let id: String
        let type: String
        let input: Value
        let expected: Value
    }

    static let document: Value = load("cases.json")

    static let cases: [Case] = (document["cases"]?.array ?? []).compactMap { raw in
        guard let id = raw["id"]?.string, let type = raw["type"]?.string, let input = raw["input"], let expected = raw["expected"] else { return nil }
        return Case(id: aliasID(id), type: type, input: applyAlias(input), expected: applyAlias(expected))
    }

    static func cases(ofType type: String) -> [Case] { cases.filter { $0.type == type } }

    static func byID(_ id: String) -> Case? { cases.first { $0.id == id } }

    /// reference `_sub`: 기대값에 있는 키만 비교한다. 다르면 차이 글 목록.
    static func diffs(_ expected: Value, _ actual: Value?, path: String = "") -> [String] {
        switch expected {
        case .object(let e):
            guard case .object(let a)? = actual else { return ["\(path): \(actual?.description ?? "<없음>") (객체 기대)"] }
            return e.keys.sorted().flatMap { diffs(e[$0]!, a[$0], path: "\(path).\($0)") }
        case .array(let e) where e.first.map({ $0.array != nil || $0.object != nil }) ?? false:
            guard case .array(let a)? = actual, a.count == e.count else {
                return ["\(path): \(actual?.description ?? "<없음>") ≠ \(expected)"]
            }
            return zip(e, a).enumerated().flatMap { i, pair in diffs(pair.0, pair.1, path: "\(path)[\(i)]") }
        default:
            return expected == actual ? [] : ["\(path): \(actual?.description ?? "<없음>") ≠ \(expected)"]
        }
    }

    // MARK: - 문자열 → 패 id

    /// 여러 문자열을 **한 산에서** 집듯 id 를 배정한다(reference physical_ids 에 taken 을 이어 넘기는 것과 같다).
    /// 표시패처럼 손과 같은 id 를 다시 쓸 수 없어 실패하면 nil.
    static func tiles(_ texts: [String]) -> [[MahjongTile]]? {
        var sizes: [Int] = []
        for text in texts {
            guard let one = MahjongTiles.parse(text) else { return nil }
            sizes.append(one.count)
        }
        guard let all = MahjongTiles.parse(texts.joined()) else { return nil }
        var out: [[MahjongTile]] = []
        var at = 0
        for n in sizes {
            out.append(Array(all[at..<(at + n)]))
            at += n
        }
        return out
    }

    static func tile(_ token: String) -> MahjongTile? { MahjongTiles.parse(token)?.first }

    /// 문자열 → 종류 목록(id 배정 없이 — reference `parse`+`kind`). 꼴·후리텐 사례는 `5555s` 처럼 물리 패로는 없는 손도 쓴다
    /// (보통 5 넷 — 종류 판정만 하므로 reference 도 id 를 매기지 않는다). 글자가 틀리면 nil.
    static func kindList(_ text: String) -> [Int]? {
        var digits: [Int] = []
        var out: [Int] = []
        for ch in text where ch != " " {
            if let d = ch.wholeNumberValue, ch.isASCII { digits.append(d); continue }
            guard let offset = MahjongTiles.suitOffset(ch), !digits.isEmpty else { return nil }
            for d in digits {
                if ch == "z" && !(1...7).contains(d) { return nil }
                out.append(offset + (d == 0 ? 5 : d) - 1)
            }
            digits.removeAll()
        }
        return digits.isEmpty ? out : nil
    }

    static func kinds(_ text: String) -> [Int] { kindList(text) ?? [] }

    /// 문자열 → 34칸 장수(id 배정 없이).
    static func counts(_ text: String) -> [Int] {
        var c = [Int](repeating: 0, count: 34)
        for k in kinds(text) { c[k] += 1 }
        return c
    }

    static func wind(_ v: Value?) -> MahjongWind { v?.string.flatMap(MahjongWind.init(rawValue:)) ?? .east }

    /// 코퍼스 hand 입력 → 손 계산 입력. 표시패는 손 다음 id 를 쓰고, 겹치면 따로 배정한다(도라는 종류로만 센다).
    static func context(_ input: Value) -> MahjongWinContext? {
        let closedText = input["closed"]?.string ?? ""
        guard let winText = input["win"]?.string else { return nil }
        let meldValues = input["melds"]?.array ?? []
        let meldTexts = meldValues.map { $0["tiles"]?.string ?? "" }
        let doraText = input["dora"]?.string ?? "", uraText = input["ura"]?.string ?? ""
        let handTexts = [closedText, winText] + meldTexts
        var groups: [[MahjongTile]]
        if let joint = tiles(handTexts + [doraText, uraText]) {
            groups = joint
        } else {
            guard let hand = tiles(handTexts), let dora = MahjongTiles.parse(doraText), let ura = MahjongTiles.parse(uraText) else { return nil }
            groups = hand + [dora, ura]
        }
        guard groups[1].count == 1 else { return nil }
        var melds: [MahjongMeld] = []
        for (i, m) in meldValues.enumerated() {
            guard let type = m["type"]?.string.flatMap(MahjongMeldType.init(rawValue:)) else { return nil }
            melds.append(MahjongMeld(type: type, tiles: groups[2 + i], called: nil, fromSeat: nil))
        }
        func flag(_ key: String) -> Bool { input[key]?.bool ?? false }
        return MahjongWinContext(
            closed: groups[0], melds: melds, win: groups[1][0], tsumo: flag("tsumo"),
            seatWind: wind(input["seat_wind"]), roundWind: wind(input["round_wind"]),
            riichi: flag("riichi"), doubleRiichi: flag("double_riichi"), ippatsu: flag("ippatsu"), rinshan: flag("rinshan"),
            chankan: flag("chankan"), haitei: flag("haitei"), houtei: flag("houtei"),
            heavenly: flag(MahjongYaku.heavenly.rawValue), earthly: flag(MahjongYaku.earthly.rawValue),
            doraIndicators: groups[groups.count - 2], uraIndicators: groups[groups.count - 1],
            honba: input["honba"]?.int ?? 0, kyoutaku: input["kyoutaku"]?.int ?? 0
        )
    }

    // MARK: - Swift 결과 → reference 꼴

    static func points(_ p: MahjongPoints) -> Value {
        var o: [String: Value] = [:]
        if let v = p.ron { o["ron"] = .number(Double(v)) }
        if let v = p.fromDealer { o["from_dealer"] = .number(Double(v)) }
        if let v = p.fromChild { o["from_child"] = .number(Double(v)) }
        if let v = p.fromEach { o["from_each"] = .number(Double(v)) }
        return .object(o)
    }

    static func n(_ x: Int) -> Value { .number(Double(x)) }

    /// reference `_hand_view` 꼴. 형식 오류는 `{error: true}`.
    static func view(_ result: Result<MahjongScore, MahjongInputError>, tsumo: Bool) -> Value {
        guard case .success(let s) = result else { return .object(["error": .bool(true)]) }
        guard s.agari else { return .object(["agari": .bool(false), "reason": s.reason.map(Value.string) ?? .null]) }
        let honba: Value = tsumo ? .object(["from_each": n(s.honbaBonus / 3)]) : .object(["ron": n(s.honbaBonus)])
        return .object([
            "agari": .bool(true),
            "yaku": .array(s.yaku.map { .array([.string($0.yaku.rawValue), n($0.han)]) }),
            "yakuman": n(s.yakuman), "dora": n(s.dora), "aka": n(s.aka), "ura": n(s.ura), "han": n(s.han),
            "fu": s.yakuman > 0 ? .null : n(s.fu), "limit": .string(s.limit), "base": n(s.base), "points": points(s.points),
            "honba_bonus": honba, "kyoutaku_bonus": n(s.kyoutakuBonus), "total": n(s.total),
            "wait": s.wait.map(Value.string) ?? .null, "form": s.form.map(Value.string) ?? .null,
        ])
    }

    static func evaluate(_ input: Value) -> (MahjongWinContext?, Result<MahjongScore, MahjongInputError>?) {
        guard let ctx = context(input) else { return (nil, nil) }
        return (ctx, MahjongScoring.evaluate(ctx))
    }

    static func pao(_ v: Value?) -> MahjongPao? {
        guard let v, let seat = v["seat"]?.int, let yaku = v["yaku"]?.string.flatMap(MahjongYaku.init(rawValue:)) else { return nil }
        return MahjongPao(seat: seat, yaku: yaku)
    }
}

@Suite("아잉 마작 손 계산 코퍼스 — hand 93 · score_table 33 · settle_win 9 (cases.json, id 로)")
struct MahjongScoringCorpusTests {
    // 없으면: 시험이 읽는 코퍼스가 원본(mj/research/cases.json)과 갈라져도, 또는 별칭이 빠져 천화 사례가 조용히 빠져도 초록이다.
    @Test("코퍼스 모양 — 바이트 그대로(md5) · schema · 235 사례 · 갈래별 수 · 별칭 적용")
    func corpusShape() {
        #expect(MahjongCorpus.md5("cases.json") == "faf35270fb9c8453cceeb5808311a6ab", "mj/research/cases.json 바이트 그대로")
        #expect(MahjongCorpus.md5("corpus_alias.json") == "a805df6deb75bb8776ef720693ac00ec")
        #expect(MahjongCorpus.document["schema"]?.string == "mahjong-cases/1")
        #expect(MahjongCorpus.cases.count == 235)
        var byType: [String: Int] = [:]
        for c in MahjongCorpus.cases { byType[c.type, default: 0] += 1 }
        #expect(byType == ["hand": 93, "score_table": 33, "advance": 22, "shape": 11, "claim": 11, "abortive": 10, "settle_win": 9,
                           "exhaustive": 9, "furiten": 8, "kuikae": 8, "dora": 8, "riichi": 7, "riichi_ankan": 3, "rank": 3])
        #expect(Set(MahjongCorpus.cases.map(\.id)).count == 235, "id 가 겹치지 않는다")
        // 별칭: 표가 두 칸이고, 바꾼 뒤에는 그 글자가 깃발 키·역 id·사례 id 어디에도 없다(기준선: 바꾸기 전 원문에는 있다).
        #expect(MahjongCorpus.alias.count == 2 && Set(MahjongCorpus.alias.values) == ["heavenly", "earthly"])
        let raw = (MahjongCorpus.document["cases"]?.array ?? []).map(\.description).joined()
        let aliased = MahjongCorpus.cases.map { "\($0.id)\($0.input)\($0.expected)" }.joined()
        for from in MahjongCorpus.alias.keys {
            #expect(raw.localizedCaseInsensitiveContains(from), "기준선: 원문에는 있다")
            #expect(!aliased.localizedCaseInsensitiveContains(from), "별칭 적용 뒤 0")
        }
        #expect(MahjongCorpus.byID("YM-HEAVENLY") != nil && MahjongCorpus.byID("YM-EARTHLY") != nil)
    }

    // 없으면: 역·부·점수·해석 고르기(X-01·X-02)·형식 오류 가운데 하나가 reference 와 갈려도 서버(SQL 쌍둥이)와 맞춰 볼 정답이 없다.
    @Test("hand 93 — 역·판·부·상한·지불·본장·공탁·대기·꼴 · 형식 오류 2건은 .failure")
    func handCases() {
        let cases = MahjongCorpus.cases(ofType: "hand")
        #expect(cases.count == 93)
        var failures: [String] = []
        var errors = 0
        for c in cases {
            let (ctx, result) = MahjongCorpus.evaluate(c.input)
            guard let ctx, let result else { failures.append("\(c.id): 입력을 패 id 로 못 바꿈"); continue }
            if c.expected["error"] != nil { errors += 1 }
            let d = MahjongCorpus.diffs(c.expected, MahjongCorpus.view(result, tsumo: ctx.tsumo))
            if !d.isEmpty { failures.append("\(c.id): " + d.joined(separator: " | ")) }
        }
        #expect(errors == 2)
        #expect(failures.isEmpty, "\(failures.count)건: \(failures.prefix(8).joined(separator: "\n"))")
    }

    // 없으면: 천화(MJ-36 — 14장 중 가장 높은 화료패)를 화료패 하나로만 재면 천화+순정 구련보등이 천화 하나로 떨어진다.
    @Test("천화 — 14장 중 가장 높은 해석(MJ-36) · 기준선: 깃발을 끄면 같은 손이 다른 결과")
    func heavenlyPicksBest() throws {
        let c = try #require(MahjongCorpus.byID("YM-HEAVENLY-CHUUREN"))
        let ctx = try #require(MahjongCorpus.context(c.input))
        let score = try MahjongScoring.evaluate(ctx).get()
        #expect(score.yaku.map(\.yaku) == [.heavenly, .junseiChuuren] && score.yakuman == 3)
        var off = ctx
        off.heavenly = false
        let plain = try MahjongScoring.evaluate(off).get()
        #expect(plain.yaku.map(\.yaku) == [.chuuren], "기준선: 원래 화료패(9m)로는 순정이 아니다")
    }

    // 없으면: 상한 경계(만관 절상 없음·헤아림 역만)나 친/자·쯔모/론 지불 반올림이 갈려도 모른다.
    @Test("score_table 33 — 기본점·상한·지불(본장 제외)")
    func scoreTable() {
        let cases = MahjongCorpus.cases(ofType: "score_table")
        #expect(cases.count == 33)
        var failures: [String] = []
        for c in cases {
            let i = c.input
            guard let han = i["han"]?.int, let fu = i["fu"]?.int, let dealer = i["dealer"]?.bool, let tsumo = i["tsumo"]?.bool else {
                failures.append("\(c.id): 입력"); continue
            }
            let r = MahjongScoring.scoreOf(han: han, fu: fu, dealer: dealer, tsumo: tsumo, yakuman: i["yakuman"]?.int ?? 0)
            let view: MahjongCorpus.Value = .object(["base": MahjongCorpus.n(r.base), "limit": .string(r.limit),
                                                     "points": MahjongCorpus.points(r.points), "total": MahjongCorpus.n(r.total)])
            let d = MahjongCorpus.diffs(c.expected, view)
            if !d.isEmpty { failures.append("\(c.id): " + d.joined(separator: " | ")) }
        }
        #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
    }

    // 없으면: 책임 지불(MJ-42)·동시 론의 본장·공탁 상가 취득(MJ-25)·친 쯔모 본장이 reference 와 갈려도 모른다.
    @Test("settle_win 9 — 화료 하나 · 책임 지불 · 더블론·트리플론")
    func settleWin() {
        let cases = MahjongCorpus.cases(ofType: "settle_win")
        #expect(cases.count == 9)
        var failures: [String] = []
        for c in cases {
            let i = c.input
            let dealer = i["dealer"]?.int ?? 0, honba = i["honba"]?.int ?? 0, kyoutaku = i["kyoutaku"]?.int ?? 0
            let view: MahjongCorpus.Value
            if let winners = i["winners"]?.array {
                var wins: [(seat: Int, score: MahjongScore, pao: MahjongPao?)] = []
                for w in winners {
                    guard let seat = w["seat"]?.int, let hand = w["hand"], case .success(let s)? = MahjongCorpus.evaluate(hand).1 else { continue }
                    wins.append((seat, s, MahjongCorpus.pao(w["pao"])))
                }
                guard wins.count == winners.count, let discarder = i["discarder"]?.int else { failures.append("\(c.id): 입력"); continue }
                let r = MahjongRules.settleRonMulti(discarder: discarder, dealer: dealer, wins: wins, honba: honba, kyoutaku: kyoutaku)
                view = .object(["deltas": .array(r.deltas.map(MahjongCorpus.n)), "bonus_to": MahjongCorpus.n(r.bonusTo), "renchan": .bool(r.renchan)])
            } else {
                guard let winner = i["winner"]?.int, let hand = i["hand"], case .success(let s)? = MahjongCorpus.evaluate(hand).1 else {
                    failures.append("\(c.id): 입력"); continue
                }
                let d = MahjongRules.settleWin(winner: winner, dealer: dealer, score: s, discarder: i["discarder"]?.int, honba: honba,
                                               kyoutaku: kyoutaku, pao: MahjongCorpus.pao(i["pao"]), getsBonus: true)
                view = .object(["deltas": .array(d.map(MahjongCorpus.n))])
            }
            let d = MahjongCorpus.diffs(c.expected, view)
            if !d.isEmpty { failures.append("\(c.id): " + d.joined(separator: " | ")) }
        }
        #expect(failures.isEmpty, "\(failures.joined(separator: "\n"))")
    }

    // 없으면: 해석이 여럿일 때 고르는 순서(X-01 역만 먼저 · X-02 역 순번 사전순)가 서버와 갈려 같은 손의 역 표시가 기기마다 다르다.
    @Test("해석 고르기 — X-01 역만 먼저(사암각 vs 헤아림) · X-02 판·부 같으면 역 순번 · 기준선: 판만 보면 헤아림")
    func interpretationOrder() throws {
        let c = try #require(MahjongCorpus.byID("X-01-SUUANKOU-OVER-KAZOE"))
        let score = try MahjongScoring.evaluate(try #require(MahjongCorpus.context(c.input))).get()
        #expect(score.yaku.map(\.yaku) == [.suuankou] && score.yakuman == 1 && score.limit == "yakuman")
        // 기준선: 같은 손을 쯔모 아닌 론으로 바꾸면 사암각이 깨져(론 커쯔는 밝다) 헤아림(일반 역 + 도라 13판 이상)이 된다.
        var ron = try #require(MahjongCorpus.context(c.input))
        ron.tsumo = false
        let kazoe = try MahjongScoring.evaluate(ron).get()
        #expect(kazoe.yakuman == 0 && kazoe.han >= 13 && kazoe.limit == "yakuman", "\(kazoe.yaku) \(kazoe.han)")
    }
}
