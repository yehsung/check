import Foundation
import Testing
@testable import CheckCore

// 아잉 마작 규칙 Swift 를 reference.py 와 무작위 손으로 대조한다(SPEC §6.2 — 갈래 P 의 make_xval.py 가 만든 `mahjong-xval/1`).
// 기본 게이트 = `Fixtures/mahjong/xval-hands.json`(화료 300 · 13장 꼴 120 · 울기 꼴 60, mj/fixtures 의 바이트 그대로).
// 큰 파일(화료 5,000 · 13장 꼴 2,000 · 울기 꼴 1,000)은 저장소 밖 — `MAHJONG_XVAL_DEEP=1 MAHJONG_XVAL_PATH=<파일>` 일 때만 돈다.
// 입력은 패 id 그대로(문자열 아님), 역 id 는 파일에서 이미 별칭이 적용돼 있다.

enum MahjongXval {
    typealias V = MahjongCorpus.Value

    /// 대조 키(파일 머리 notation.compare). 그 밖의 키(total_base·dealer·tsumo·kazoe)는 reference 내부 값.
    static let compareKeys: Set<String> = ["agari", "reason", "yaku", "yakuman", "han", "fu", "limit", "base", "points", "honba_bonus",
                                           "kyoutaku_bonus", "total", "dora", "aka", "ura", "wait", "form"]

    static let gate: V = MahjongCorpus.load("xval-hands.json")

    static func tiles(_ v: V?) -> [MahjongTile] { (v?.array ?? []).compactMap { $0.int.flatMap(MahjongTile.init(id:)) } }

    static func context(_ i: V) -> MahjongWinContext? {
        guard let win = i["win"]?.int.flatMap(MahjongTile.init(id:)) else { return nil }
        var melds: [MahjongMeld] = []
        for m in i["melds"]?.array ?? [] {
            guard let type = m["type"]?.string.flatMap(MahjongMeldType.init(rawValue:)) else { return nil }
            melds.append(MahjongMeld(type: type, tiles: tiles(m["tiles"]), called: nil, fromSeat: nil))
        }
        func flag(_ key: String) -> Bool { i[key]?.bool ?? false }
        return MahjongWinContext(
            closed: tiles(i["closed"]), melds: melds, win: win, tsumo: flag("tsumo"),
            seatWind: MahjongCorpus.wind(i["seat_wind"]), roundWind: MahjongCorpus.wind(i["round_wind"]),
            riichi: flag("riichi"), doubleRiichi: flag("double_riichi"), ippatsu: flag("ippatsu"), rinshan: flag("rinshan"),
            chankan: flag("chankan"), haitei: flag("haitei"), houtei: flag("houtei"),
            heavenly: flag(MahjongYaku.heavenly.rawValue), earthly: flag(MahjongYaku.earthly.rawValue),
            doraIndicators: tiles(i["dora"]), uraIndicators: tiles(i["ura"]),
            honba: i["honba"]?.int ?? 0, kyoutaku: i["kyoutaku"]?.int ?? 0
        )
    }

    /// 화료 레코드 대조 — (건수, 화료 수, 차이 글).
    static func checkWins(_ records: [V]) -> (count: Int, agari: Int, failures: [String]) {
        var failures: [String] = []
        var agari = 0
        for r in records {
            let id = r["id"]?.string ?? "?"
            guard let input = r["input"], let ctx = context(input), case .object(let full)? = r["expect"] else {
                failures.append("\(id): 레코드를 못 읽음"); continue
            }
            let expected = V.object(full.filter { compareKeys.contains($0.key) })
            let result = MahjongScoring.evaluate(ctx)
            if case .success(let s) = result, s.agari { agari += 1 }
            let d = MahjongCorpus.diffs(expected, MahjongCorpus.view(result, tsumo: ctx.tsumo))
            if !d.isEmpty { failures.append("\(id): " + d.joined(separator: " | ")) }
        }
        return (records.count, agari, failures)
    }

    /// 꼴 레코드 대조(shanten · waits · tenpai).
    static func checkShapes(_ records: [V]) -> (count: Int, tenpai: Int, failures: [String]) {
        var failures: [String] = []
        var tenpai = 0
        for r in records {
            let id = r["id"]?.string ?? "?"
            let counts = MahjongTiles.counts34(tiles(r["closed"]))
            let melds = r["n_melds"]?.int ?? 0
            let waits = MahjongHand.waits(counts, melds: melds)
            if !waits.isEmpty { tenpai += 1 }
            let got: V = .object(["shanten": .number(Double(MahjongHand.shanten(counts, melds: melds))),
                                  "waits": .array(waits.map { .number(Double($0)) }), "tenpai": .bool(!waits.isEmpty)])
            let d = MahjongCorpus.diffs(r["expect"] ?? .null, got)
            if !d.isEmpty { failures.append("\(id): " + d.joined(separator: " | ")) }
        }
        return (records.count, tenpai, failures)
    }

    static var deepEnabled: Bool { ProcessInfo.processInfo.environment["MAHJONG_XVAL_DEEP"] == "1" }
}

@Suite("아잉 마작 무작위 대조 — xval-hands.json(reference.py 결과) 전부 · DEEP 은 저장소 밖")
struct MahjongXvalTests {
    // 없으면: 대조 파일이 P 의 생성물과 갈라지거나(손으로 고침) 다른 생성기·참조 판으로 바뀌어도 '전부 일치'가 무엇과의 일치인지 모른다.
    @Test("파일 머리 — 바이트 그대로(md5) · schema · 게이트 300/120/60 · 참조 md5 = SPEC 머리")
    func header() {
        let g = MahjongXval.gate
        #expect(MahjongCorpus.md5("xval-hands.json") == "a5776f3bda850cf1ef4bcb59dc500fb5")
        #expect(g["schema"]?.string == "mahjong-xval/1" && g["subset"]?.string == "gate")
        #expect(g["reference_md5"]?.string == "4d30ca7e27ed7c3e69d9f88b6739aa3f")
        #expect(g["win"]?.array?.count == 300 && g["shape13"]?.array?.count == 120 && g["shape_meld"]?.array?.count == 60)
    }

    // 없으면: 역 22꼴·역만·치또이·국사·책임 없는 지불 등 코퍼스 235 가 덮지 않는 조합에서 reference 와 갈려도 모른다.
    @Test("화료 300 — reference evaluate 와 대조 키 전부 일치(역 없음 24 포함)")
    func wins() {
        let r = MahjongXval.checkWins(MahjongXval.gate["win"]?.array ?? [])
        #expect(r.count == 300)
        #expect(r.agari == 276, "기준선: 화료 276 · 역 없음 24(전부 같은 답으로 초록이 아니다)")
        #expect(r.failures.isEmpty, "\(r.failures.count)건: \(r.failures.prefix(6).joined(separator: "\n"))")
    }

    // 없으면: 13장 꼴(4장 쥔 손 31 포함)의 샹텐·대기가 reference 와 갈려도 코퍼스 shape 11 만으로는 모른다.
    @Test("13장 꼴 120 — shanten · waits · tenpai 일치")
    func shape13() {
        let r = MahjongXval.checkShapes(MahjongXval.gate["shape13"]?.array ?? [])
        #expect(r.count == 120 && r.tenpai == 33)
        #expect(r.failures.isEmpty, "\(r.failures.count)건: \(r.failures.prefix(6).joined(separator: "\n"))")
    }

    // 없으면: 울기 수(1~4)가 든 꼴에서 몸통 수·치또이/국사 끄기가 reference 와 갈려도 모른다.
    @Test("울기 꼴 60 — shanten · waits · tenpai 일치")
    func shapeMeld() {
        let r = MahjongXval.checkShapes(MahjongXval.gate["shape_meld"]?.array ?? [])
        #expect(r.count == 60 && r.tenpai == 29)
        #expect(r.failures.isEmpty, "\(r.failures.count)건: \(r.failures.prefix(6).joined(separator: "\n"))")
    }

    // 느린 그물(SPEC §6.1): 저장소 밖 큰 파일 전부. 켰는데 파일이 없으면 빨강(건너뜀으로 초록이 되지 않게).
    @Test("DEEP — MAHJONG_XVAL_PATH 의 화료 5,000 · 13장 꼴 2,000 · 울기 꼴 1,000 전부", .enabled(if: MahjongXval.deepEnabled))
    func deep() throws {
        let path = try #require(ProcessInfo.processInfo.environment["MAHJONG_XVAL_PATH"], "MAHJONG_XVAL_PATH 가 없다")
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let file = MahjongCorpus.Value(try JSONSerialization.jsonObject(with: data))
        #expect(file["schema"]?.string == "mahjong-xval/1" && file["reference_md5"]?.string == "4d30ca7e27ed7c3e69d9f88b6739aa3f")
        let wins = MahjongXval.checkWins(file["win"]?.array ?? [])
        let s13 = MahjongXval.checkShapes(file["shape13"]?.array ?? [])
        let sm = MahjongXval.checkShapes(file["shape_meld"]?.array ?? [])
        #expect(wins.count == 5_000 && s13.count == 2_000 && sm.count == 1_000)
        let failures = wins.failures + s13.failures + sm.failures
        #expect(failures.isEmpty, "\(failures.count)건: \(failures.prefix(8).joined(separator: "\n"))")
    }
}
