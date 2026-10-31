// 원본: Sources/CheckCore/RummyTableLayout.swift @ 1a5eeca6 (골든 생성기 — 아잉 큐브 판 배치)
import CheckGoldenSupport
import Foundation
import Testing
@testable import CheckCore

// 아잉 큐브 판 배치 골든(rummy/table-layout): 모든 클라가 같은 판을 그려야 하므로 place · snap · freeSpot · firstFree · refit · clampInside · sanitize · 판정 표를 비트로 잰다.
// 판은 정수뿐이다. 같은 면의 묶음 순서를 섞어 넣은 경우(내용 순 채우기)를 일부러 포함한다.

@Suite("GoldenExport rummy — 판 배치(rummy/table-layout)")
struct GoldenExportRummyTableLayout {
    private typealias T = GoldenRummyText

    private func obstacles(_ r: inout GoldenRummyRNG, count: Int) -> [RummyRect] {
        (0..<count).map { _ in
            RummyTableLayout.frame(at: RummyPoint(x: r.range(-40, 1040), y: r.range(-40, 680)), tiles: r.range(1, 13))
        }
    }

    @Test("rummy/table-layout — place · snap · freeSpot · firstFree · refit · clampInside · sanitize · 판정 표")
    func tableLayout() {
        var cases: [GoldenJSON] = []
        var r = GoldenRummyRNG(seed: 0x7AB1_E000)

        // 상수.
        cases.append([
            "id": "constants", "kind_": "constants", "canvasWidth": .int(RummyTableLayout.canvasWidth), "canvasHeight": .int(RummyTableLayout.canvasHeight),
            "tileWidth": .int(RummyTableLayout.tileWidth), "tileHeight": .int(RummyTableLayout.tileHeight), "grid": .int(RummyTableLayout.grid), "clearance": .int(RummyTableLayout.clearance),
        ])

        // place: 빈 판 · 묶음 수 다름 · 범위 밖 점 당기기 · 섞은 순서 · 꽉 찬 판.
        func addPlace(_ id: String, _ sets: [[RummyFace]], _ layout: RummyLayout?) {
            let points = RummyTableLayout.place(sets: sets, layout: layout)
            let table = RummyTableLayout(sets: sets, layout: layout)
            #expect(table.points == points)
            cases.append([
                "id": .string(id), "kind_": "place", "sets": .string(T.sets(sets)),
                "layout": layout.map { .string(T.points($0.points)) } ?? .null,
                "points": .string(T.points(points)),
                "sanitized": .string(T.points(RummyTableLayout.sanitize(layout, setCount: sets.count))),
                "frames": .string(T.rects(table.frames)),
            ])
        }
        let sample = ["A1 A2 A3", "B7 C7 D7", "C9 C10 C11 C12", "A5 B5 C5 D5 ", "J A5 A6"].map(T.faces)
        addPlace("place-empty", [], nil)
        addPlace("place-nil", sample, nil)
        addPlace("place-shuffled", [sample[3], sample[0], sample[4], sample[2], sample[1]], nil)
        addPlace("place-wrong-length", sample, RummyLayout([RummyPoint(x: 8, y: 8)]))
        addPlace("place-partial", sample, RummyLayout([RummyPoint(x: 100, y: 100), nil, nil, RummyPoint(x: 500, y: 300), nil]))
        addPlace("place-clamp", sample, RummyLayout([RummyPoint(x: 999, y: 640), RummyPoint(x: 1000, y: 0), RummyPoint(x: 0, y: 640), nil, nil]))
        addPlace("place-overlap-kept", sample, RummyLayout([RummyPoint(x: 100, y: 100), RummyPoint(x: 100, y: 100), RummyPoint(x: 120, y: 110), nil, nil]))
        addPlace("place-same-faces", [T.faces("A1 A2 A3"), T.faces("A1 A2 A3"), T.faces("A1 A2 A3")], nil)
        for i in 0..<36 {
            let crowded = i % 6 == 0
            let sets = (0..<(crowded ? r.range(14, 30) : r.range(0, 8))).map { _ in r.meld() }
            let layout: RummyLayout?
            switch r.below(4) {
            case 0: layout = nil
            case 1:
                layout = RummyLayout(sets.map { _ in r.below(3) == 0 ? nil : RummyPoint(x: r.range(0, 1000), y: r.range(0, 640)) })
            case 2:
                layout = RummyLayout(sets.map { _ in RummyPoint(x: r.range(0, 1000), y: r.range(0, 640)) })
            default:
                layout = RummyLayout((0..<r.range(0, 4)).map { _ in RummyPoint(x: r.range(0, 1000), y: r.range(0, 640)) })
            }
            addPlace("place-r\(i)", sets, layout)
        }

        // 빈자리 찾기 · 스냅 · 길이 변화 · 안으로 당기기.
        for i in 0..<110 {
            let count = i % 9 == 0 ? r.range(30, 70) : r.range(0, 14)
            let among = obstacles(&r, count: count)
            let point = RummyPoint(x: r.range(-120, 1120), y: r.range(-80, 720))
            let tiles = r.range(1, 26)
            cases.append([
                "id": .string("spot-\(i)"), "kind_": "spot", "among": .string(T.rects(among)), "point": .string(T.point(point)), "tiles": .int(tiles),
                "firstFree": .string(T.point(RummyTableLayout.firstFree(tiles: tiles, among: among))),
                "snap": .string(T.point(RummyTableLayout.snap(point, tiles: tiles, among: among))),
                "freeSpot": RummyTableLayout.freeSpot(point, tiles: tiles, among: among).map { .string(T.point($0)) } ?? .null,
                "refit": .string(T.point(RummyTableLayout.refit(point, tiles: tiles, among: among))),
                "clampInside": .string(T.point(RummyTableLayout.clampInside(point, tiles: tiles))),
                "clear": .bool(RummyTableLayout.isClear(RummyTableLayout.frame(at: point, tiles: tiles), among: among)),
            ])
        }
        // 판이 정말로 꽉 찬 경우(freeSpot nil · firstFree 대체 · 폭이 캔버스를 넘는 묶음).
        let wall = [RummyRect(x: 0, y: 0, width: 1000, height: 640)]
        for (i, tiles) in [1, 13, 25, 26, 40].enumerated() {
            let point = RummyPoint(x: 300, y: 300)
            cases.append([
                "id": .string("spot-wall-\(i)"), "kind_": "spot", "among": .string(T.rects(wall)), "point": .string(T.point(point)), "tiles": .int(tiles),
                "firstFree": .string(T.point(RummyTableLayout.firstFree(tiles: tiles, among: wall))),
                "snap": .string(T.point(RummyTableLayout.snap(point, tiles: tiles, among: wall))),
                "freeSpot": RummyTableLayout.freeSpot(point, tiles: tiles, among: wall).map { .string(T.point($0)) } ?? .null,
                "refit": .string(T.point(RummyTableLayout.refit(point, tiles: tiles, among: wall))),
                "clampInside": .string(T.point(RummyTableLayout.clampInside(point, tiles: tiles))),
                "clear": .bool(RummyTableLayout.isClear(RummyTableLayout.frame(at: point, tiles: tiles), among: wall)),
            ])
        }

        // 판정 표(두 사각형 · 점).
        for i in 0..<50 {
            let a = RummyRect(x: r.range(-50, 1050), y: r.range(-50, 690), width: r.range(1, 8) * 40, height: 56)
            let b = RummyRect(x: a.x + r.range(-400, 400), y: a.y + r.range(-120, 120), width: r.range(1, 8) * 40, height: 56)
            let p = RummyPoint(x: a.x + r.range(-10, a.width + 10), y: a.y + r.range(-10, 66))
            cases.append([
                "id": .string("rect-\(i)"), "kind_": "rect", "a": .string(T.rect(a)), "b": .string(T.rect(b)), "p": .string(T.point(p)),
                "fits": .bool(RummyTableLayout.fits(a)), "overlaps": .bool(RummyTableLayout.overlaps(a, b)), "contains": .bool(a.contains(p)),
                "accepts": .bool(RummyTableLayout.acceptsWire(x: p.x, y: p.y)),
            ])
        }

        // 묶음 찾기 · 타일 사각형 · 스냅(자기 빼기) — 값 타입 쪽 메서드.
        let shown = RummyTableLayout(sets: sample, layout: nil)
        for i in 0..<30 {
            let p = RummyPoint(x: r.range(0, 700), y: r.range(0, 200))
            let set = r.range(-1, sample.count)
            let tile = r.range(-1, 5)
            let excluding: Int? = r.flip() ? nil : r.below(sample.count)
            cases.append([
                "id": .string("query-\(i)"), "kind_": "query", "p": .string(T.point(p)), "set": .int(set), "tile": .int(tile), "excluding": excluding.map { .int($0) } ?? .null,
                "setIndex": shown.setIndex(at: p).map { .int($0) } ?? .null,
                "frame": shown.frame(of: set).map { .string(T.rect($0)) } ?? .null,
                "tileFrame": shown.tileFrame(set: set, tile: tile).map { .string(T.rect($0)) } ?? .null,
                "snap": .string(T.point(shown.snap(p, tiles: 3, excluding: excluding))),
            ])
        }

        goldenEmit(GoldenFile(
            golden: "rummy/table-layout",
            equivalence: .bit,
            swiftSources: ["Sources/CheckCore/RummyTableLayout.swift", "Sources/CheckCore/RummyRules.swift"],
            spec: [
                "kind_": "constants · place(sets·layout → points, sanitized, frames) · spot(among·point·tiles → firstFree·snap·freeSpot·refit·clampInside·clear) · rect(판정) · query(RummyTableLayout(sets: sample) 의 setIndex·frame·tileFrame·snap).",
                "query": "표본 판 = [A1 A2 A3 / B7 C7 D7 / C9 C10 C11 C12 / A5 B5 C5 D5 / J A5 A6], 배치 nil 로 자동 배치. tiles = 3.",
                "text": "점 'x,y' · 점 목록 공백 구분(빈 칸 '-') · 사각형 'x,y,w,h'(목록 공백 구분) · 묶음 목록 'A1 A2|B1'.",
            ],
            cases: cases
        ))
    }
}
