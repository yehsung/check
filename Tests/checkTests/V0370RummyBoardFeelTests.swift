import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// v0.3.70 아잉 큐브 **판 조작감**(플레이 감사 #1 · #8 · #9 + 그룹 순서). 사용자 원문(0.3.69 를 해 보고): "전체적으로 게임 플레이
// 관점에서 고쳐야될게 많아".
//   ① 판 타일이 작다(23×33pt) — 판 화면 머리글을 위 띠로 옮겨 판 칸을 높이고 [판 확대]를 기본으로(끄는 동안은 변환을 굳힌다).
//   ② 길게 누르기 0.5초 · ⌥ 없이 쪼개기(누른 타일에서 가까운 끝까지) · 규칙 창 '조작' 칸.
//   ③ 길어진 묶음이 막히면 옆으로(왼쪽 먼저) → 그래도 막히면 막은 이웃을 비켜 놓는다(만지던 묶음은 제자리) · 꽉 찬 판에서 구석에 겹치지 않는다.
//   ④ 받은 묶음이 맞는 세트가 되면 R-09 표시 순서로(그룹 색 순 · 런의 조커 자리) — 확정 전후가 같다.
// 각 시험의 첫 줄 주석은 "없으면 어떤 결함이 초록으로 통과하는가" 다. 렌더는 `CHECK_SNAPSHOT_DIR/stills/rummy370-*.png`.

private func pf(_ text: String) -> [RummyFace] { text.split(separator: " ").map { RummyFace(text: String($0))! } }
private func pp(_ x: Int, _ y: Int) -> RummyPoint { RummyPoint(x: x, y: y) }
private func pEditor(_ sets: [String], at points: [RummyPoint], rack: String, initialDone: Bool = true) -> RummyTurnEditor {
    RummyTurnEditor(table: sets.map(pf), rack: rack.isEmpty ? [] : pf(rack), initialDone: initialDone,
                    tableLayout: RummyLayout(points.map { Optional($0) }))
}
private func pTexts(_ e: RummyTurnEditor) -> [String] { e.submissionTable.map { $0.map(\.text).joined(separator: " ") } }
private func pRack(_ e: RummyTurnEditor, _ text: String) -> Int { e.rack.first { $0.face.text == text }!.id }
private func pTable(_ e: RummyTurnEditor, _ text: String) -> Int { e.melds.flatMap { $0 }.first { $0.face.text == text }!.id }

/// 확정 뒤 판(서버가 돌려준 판으로 다시 선 편집기 = R-09 표시 순서)과 지금 작업 판의 묶음 순서가 같은가.
private func pSameAfterConfirm(_ e: RummyTurnEditor) -> Bool {
    let confirmed = RummyTurnEditor(table: e.submissionTable, rack: [], initialDone: true, tableLayout: e.submissionLayout)
    return confirmed.melds.map { $0.map(\.face) } == e.melds.map { $0.map(\.face) } && confirmed.points == e.points
}

@Suite("v0.3.70 아잉 큐브 판 조작감 — 쪼개기 규칙 · 표시 순서 · 비켜 놓기(편집기)")
struct V0370RummyBoardEditTests {
    @Test("길게 누르기 구간: 오른쪽 절반 = 그 타일부터 끝 · 왼쪽 절반 = 처음부터 그 타일 · 정확히 가운데 = 묶음 전체")
    func pickRangeIsNearerEnd() {
        // 없으면: ⌥ 를 모르는 사람은 런을 못 쪼개고(묶음 전체만 집힌다), 짝수 장에서 경계가 흔들리는 결함이 초록이 된다.
        let five = (0..<5).map { RummyTableEdit.pickRange(count: 5, pressed: $0) }
        #expect(five == [0..<1, 0..<2, 0..<5, 3..<5, 4..<5])
        let four = (0..<4).map { RummyTableEdit.pickRange(count: 4, pressed: $0) }
        #expect(four == [0..<1, 0..<2, 2..<4, 3..<4])
        #expect(RummyTableEdit.pickRange(count: 1, pressed: 0) == 0..<1)
        #expect(RummyTableEdit.pickRange(count: 2, pressed: 1) == 1..<2)
        #expect(RummyTableEdit.pickRange(count: 3, pressed: 3).isEmpty && RummyTableEdit.pickRange(count: 3, pressed: -1).isEmpty)

        let e = pEditor(["A1 A2 A3 A4 A5 A6 A7"], at: [pp(100, 100)], rack: "B9")
        let ids = e.melds[0].map(\.id)
        #expect(e.meldChunk(for: pTable(e, "A6")) == Array(ids[5...]))
        #expect(e.meldChunk(for: pTable(e, "A2")) == Array(ids[...1]))
        #expect(e.meldChunk(for: pTable(e, "A4")) == ids)
        #expect(e.meldChunk(for: pRack(e, "B9")).isEmpty, "받침대 타일은 판 덩어리가 아니다")
    }

    @Test("그룹에 꽂기 = 표시 순서 자리(색 A→D) · 기존 타일 제자리(왼쪽으로 늘어남) · 확정 뒤 판과 같다")
    func groupInsertsAtDisplaySlot() {
        // 없으면: 오른끝에 꽂힌 A5 가 확정 뒤 서버 표시 순서(A5 B5 C5 D5)로 왼끝으로 튀는 결함이 초록이 된다.
        var e = pEditor(["B5 C5 D5"], at: [pp(300, 200)], rack: "A5")
        let a5 = pRack(e, "A5")
        let preview = e.previewDrop([a5], to: .meld(0, index: 3))
        let ok1 = e.moveBlock([a5], to: .meld(0, index: 3))
        #expect(ok1)
        #expect(pTexts(e) == ["A5 B5 C5 D5"] && e.points == [pp(260, 200)], "\(pTexts(e)) \(e.points)")
        #expect(preview?.plan == .insert(set: 0, index: 0))
        #expect(preview?.landing?.frame == RummyRect(x: 260, y: 200, width: 160, height: 56))
        #expect(pSameAfterConfirm(e))

        // 만드는 중(2장 · 무효)에도 표시 순서 자리 — 맞는 세트가 되는 순간 다시 섞이지 않는다.
        var build = pEditor([], at: [], rack: "C7 A7 B7")
        let ok2 = build.moveBlock([pRack(build, "C7")], to: .newMeldAt(pp(400, 296)))
        #expect(ok2)
        let start = build.points[0]
        let ok3 = build.moveBlock([pRack(build, "A7")], to: .meld(0, index: 1))
        #expect(ok3)
        #expect(pTexts(build) == ["A7 C7"] && build.points == [pp(start.x - 40, start.y)], "C7 제자리, A7 은 왼쪽")
        let ok4 = build.moveBlock([pRack(build, "B7")], to: .meld(0, index: 2))
        #expect(ok4)
        #expect(pTexts(build) == ["A7 B7 C7"] && build.points == [pp(start.x - 40, start.y)])
        #expect(pSameAfterConfirm(build))
    }

    @Test("런의 조커 자리 = 확정 뒤 자리(R-07): 앞에 꽂아도 A5-A7 뒤 · A11-A13 은 앞 · 받침대 덩어리를 새 묶음으로 내도 표시 순서")
    func runJokerTakesConfirmedSlot() {
        // 없으면: 작업 중엔 조커가 왼끝(4 자리)에 있다가 [완료] 뒤 서버 표시 순서로 오른끝(8 자리)에 튀는 결함이 초록이 된다.
        var low = pEditor(["A5 A6 A7"], at: [pp(300, 200)], rack: "J")
        let ok5 = low.moveBlock([pRack(low, "J")], to: .meld(0, index: 0))
        #expect(ok5)
        #expect(pTexts(low) == ["A5 A6 A7 J"] && low.points == [pp(300, 200)], "A5 제자리, 조커는 8 자리")
        #expect(pSameAfterConfirm(low))

        var high = pEditor(["A11 A12 A13"], at: [pp(300, 200)], rack: "J")
        let preview = high.previewDrop([pRack(high, "J")], to: .meld(0, index: 3))
        let ok6 = high.moveBlock([pRack(high, "J")], to: .meld(0, index: 3))
        #expect(ok6)
        #expect(pTexts(high) == ["J A11 A12 A13"] && high.points == [pp(260, 200)], "13 다음이 없으니 조커는 10 자리")
        #expect(preview?.landing?.blockStart == 0 && preview?.landing?.faces == pf("J A11 A12 A13"))
        #expect(pSameAfterConfirm(high))

        var rack = pEditor([], at: [], rack: "B7 A7 C7")
        let ok7 = rack.moveBlock(rack.rack.map(\.id), to: .newMeldAt(pp(200, 200)))
        #expect(ok7)
        #expect(pTexts(rack) == ["A7 B7 C7"] && pSameAfterConfirm(rack))
    }

    @Test("길어져 오른쪽이 막히면 왼쪽으로 늘어난다 · 양쪽이 막히면 만지던 묶음은 제자리, 막은 이웃이 가장 가까운 빈자리로")
    func grownMeldExtendsLeftThenNudgesNeighbor() {
        // 없으면: A4 를 붙인 A1-A4 가 판 반대편 빈자리로 순간이동하는(옛 refit) 결함이 초록이 된다.
        var left = pEditor(["A1 A2 A3", "B9 C9 D9"], at: [pp(200, 0), pp(336, 0)], rack: "A4")
        let preview = left.previewDrop([pRack(left, "A4")], to: .meld(0, index: 3))
        let ok8 = left.moveBlock([pRack(left, "A4")], to: .meld(0, index: 3))
        #expect(ok8)
        #expect(pTexts(left) == ["A1 A2 A3 A4", "B9 C9 D9"])
        #expect(left.points == [pp(160, 0), pp(336, 0)], "\(left.points)")
        #expect(preview?.landing?.frame == RummyRect(x: 160, y: 0, width: 160, height: 56))

        var both = pEditor(["B1 B2 B3", "A1 A2 A3", "B9 C9 D9"], at: [pp(40, 0), pp(200, 0), pp(336, 0)], rack: "A4")
        let ok9 = both.moveBlock([pRack(both, "A4")], to: .meld(1, index: 3))
        #expect(ok9)
        #expect(pTexts(both) == ["B1 B2 B3", "A1 A2 A3 A4", "B9 C9 D9"])
        #expect(both.points == [pp(40, 0), pp(200, 0), pp(376, 0)], "\(both.points)")
        // 결정성: 같은 입력이면 같은 판(작업 배치로 나가는 값).
        var again = pEditor(["B1 B2 B3", "A1 A2 A3", "B9 C9 D9"], at: [pp(40, 0), pp(200, 0), pp(336, 0)], rack: "A4")
        _ = again.moveBlock([pRack(again, "A4")], to: .meld(1, index: 3))
        #expect(again.submissionLayout == both.submissionLayout)
        let frames = both.tableLayout.frames
        for i in frames.indices { for j in frames.indices where i < j { #expect(!RummyTableLayout.overlaps(frames[i], frames[j])) } }
    }

    @Test("꽉 찬 판: 새 묶음이 왼쪽 아래 구석에 겹치지 않고 놓은 자리에 선다(빈자리가 있으면 가장 가까운 빈자리)")
    func fullBoardKeepsDropPoint() {
        // 없으면: 판이 차면 새 묶음이 (0, 584) 구석에 남의 묶음 밑으로 겹쳐 안 보이는 결함이 초록이 된다.
        var sets: [String] = []
        var points: [RummyPoint] = []
        for row in 0..<9 {
            for (x, faces) in [(0, "A1 A2 A3 A4 A5 A6"), (256, "B1 B2 B3 B4 B5 B6"), (512, "C1 C2 C3 C4 C5 C6"), (768, "D1 D2 D3 D4 D5")] {
                sets.append(faces)
                points.append(pp(x, row * 72))
            }
        }
        var e = pEditor(sets, at: points, rack: "B9")
        #expect(RummyTableLayout.freeSpot(pp(500, 300), tiles: 1, among: e.tableLayout.frames) == nil, "판이 꽉 차지 않았다")
        let preview = e.previewDrop([pRack(e, "B9")], to: .newMeldAt(pp(500, 300)))
        let ok10 = e.moveBlock([pRack(e, "B9")], to: .newMeldAt(pp(500, 300)))
        #expect(ok10)
        #expect(e.points.last == pp(500, 300), "\(String(describing: e.points.last))")
        #expect(preview?.plan == .newSet(pp(500, 300)))
        #expect(Array(e.points.dropLast()) == points, "비킬 자리가 없는 이웃은 그대로")

        // 빈자리가 있으면 예전처럼 가장 가까운 빈자리(스냅).
        var roomy = pEditor(["A1 A2 A3"], at: [pp(0, 0)], rack: "B9")
        let ok11 = roomy.moveBlock([pRack(roomy, "B9")], to: .newMeldAt(pp(130, 4)))
        #expect(ok11)
        #expect(roomy.points.last == pp(136, 0))
    }
}

// MARK: - 판 칸 크기(순수 산식)

@MainActor
@Suite("v0.3.70 아잉 큐브 판 조작감 — 판 칸 크기 · 위 띠 머리글")
struct V0370RummyBoardSizeTests {
    private func tileHeight(_ t: RummyCanvasTransform) -> CGFloat { CGFloat(RummyTableLayout.tileHeight) * t.scale }

    @Test("판 칸이 머리글 높이만큼 커졌다: 전체 보기 판 타일 33 → 37pt 이상 · [판 확대](기본)는 흔한 판에서 40pt 이상")
    func boardTilesAreBigger() {
        // 없으면: 판 타일이 23×33pt 그대로라 숫자가 작고 손잡이·붙기 여유가 손가락에 안 맞는 결함이 초록이 된다.
        let L = RummyMatchLayout.standard
        let old = RummyMatchLayout(size: CGSize(width: RummyWindowLayout.innerWidth, height: RummyWindowLayout.bodyHeight))
        #expect(L.size.height == old.size.height + RummyWindowLayout.headerHeight + RummyWindowLayout.headerSpacing)
        #expect(L.table.height == old.table.height + 52)
        let fitOld = tileHeight(.fit(viewport: old.table.size)), fitNew = tileHeight(.fit(viewport: L.table.size))
        #expect(fitOld < 33 && fitNew >= 37, "전체 보기 \(fitOld) → \(fitNew)")

        // 흔한 판: 자동 배치로 12묶음(위에서부터 줄을 채운다) — 확대하면 40pt 이상.
        let sets: [[RummyFace]] = (1...12).map { n in
            let c = ["A", "B", "C", "D"][n % 4]
            return pf("\(c)\(n % 10 + 1) \(c)\(n % 10 + 2) \(c)\(n % 10 + 3)")
        }
        let layout = RummyTableLayout(sets: sets, layout: nil)
        let zoom = tileHeight(.zoom(viewport: L.table.size, content: layout.frames))
        #expect(zoom >= 40, "12묶음 판 확대 \(zoom)")
        // 시작 판(묶음 없음 · 셋)은 최대 56pt.
        #expect(tileHeight(.zoom(viewport: L.table.size, content: [])) == 56)
    }

    @Test("위 띠 머리글 칸은 판돈·위쪽 상대·더미 카드와 안 겹치고 버튼 둘이 든다")
    func chromeFitsTopBand() {
        // 없으면: 옮긴 [규칙]·[기권]이 위쪽 상대 카드나 더미 카드를 덮는 결함이 초록이 된다.
        let L = RummyMatchLayout.standard
        for chrome in [L.chromeLeft, L.chromeRight] {
            #expect(chrome.width >= 170)
            for card in [L.potCard, L.topSeat, L.poolCard] { #expect(!chrome.intersects(card)) }
            #expect(!chrome.intersects(L.table))
        }
    }

    @Test("길게 누르기는 0.5초")
    func liftDelay() {
        // 없으면: 천천히 누르는 사람이 한 장을 집으려다 덩어리째 집는 0.35초가 그대로인 결함이 초록이 된다.
        #expect(RummyMatchView.liftDelay == 0.5)
        #expect(RummyText.rules.contains { $0.title == "조작" && $0.detail.contains("0.5초") && $0.detail.contains("손잡이") })
    }
}

// MARK: - 렌더

private let rNow = Date(timeIntervalSince1970: 1_800_000_000)
private let rMe = ChessPlayerFace(name: "영식", avatarURL: nil, characterID: "shiba")
private let rPeople: [(id: String, name: String, character: String)] = [
    ("00000000-0000-4000-8000-0000000000a1", "영식", "shiba"), ("00000000-0000-4000-8000-0000000000b2", "민수", "fox"),
    ("00000000-0000-4000-8000-0000000000c3", "준호", "cat"), ("00000000-0000-4000-8000-0000000000d4", "서연", "bear"),
]
private let rRack = ["C10", "A3", "B2", "D9", "J", "B11", "D4", "A12", "C1", "A5"]

private func rMatch(table: [[String]], layout: [[Int]]) throws -> RummyMatchState {
    let nowMs = rNow.timeIntervalSince1970 * 1000
    let seats: [[String: Any]] = rPeople.enumerated().map { index, person in
        ["seat_no": index, "user_id": person.id, "display_name": person.name, "avatar_url": NSNull(),
         "character": person.character, "state": "playing", "rack_count": [9, 9, 14, 12][index], "initial_done": true,
         "timeout_streak": 0]
    }
    let state: [String: Any] = [
        "id": "7e7e0000-0000-4000-8000-000000000370", "status": "active", "host_id": rPeople[0].id, "stake": 5,
        "is_public": false, "seat_count": 4, "max_seats": 4, "server_now_ms": nowMs, "seq": 30, "seats": seats,
        "my_seat_no": 0, "my_rack": rRack, "my_initial_done": true, "table": table, "table_layout": layout,
        "pool_count": 38, "turn_seat_no": 0, "turn_started_ms": nowMs - 12_000, "turn_deadline_ms": nowMs + 48_000,
        "grace_ms": 2000, "consecutive_passes": 0,
    ]
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(RummyMatchState.self, from: JSONSerialization.data(withJSONObject: state))
}

private enum RError: Error { case render }

@MainActor
private func rBitmap(_ view: some View) throws -> NSBitmapImageRep {
    let renderer = ImageRenderer(content: view.fixedSize())
    renderer.scale = 2
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff) else { throw RError.render }
    return bitmap
}

/// 창 한 장(scale 2) — 첫 두 장은 다르게 나온다(실측). 굳힌 뒤 둘째 장. `zoom` nil = 앱 기본.
@MainActor
private func rRender(table: [[String]], layout: [[Int]], zoom: Bool?, overlay: RummyPreviewOverlay? = nil,
                     drag: (face: String, point: CGPoint)? = nil, name: String) throws -> NSBitmapImageRep {
    let faces = table.map { $0.compactMap(RummyFace.init(text:)) }
    let editor = RummyTurnEditor(table: faces, rack: rRack.compactMap(RummyFace.init(text:)), initialDone: true,
                                 tableLayout: RummyLayout(layout.map { RummyPoint(x: $0[0], y: $0[1]) }))
    let preview = drag.map { d in RummyPreviewDrag(tileID: editor.rack.first { $0.face.text == d.face }!.id, point: d.point) }
    let panel = RummyPanel(store: RummyStore(), me: { rMe }, clipsOverflowInsteadOfScroll: true,
                           previewMatch: try rMatch(table: table, layout: layout), previewEditor: editor, previewNow: rNow,
                           previewMyUserID: UUID(uuidString: rPeople[0].id), previewOverlay: overlay, previewDrag: preview)
        .environment(\.colorScheme, .dark)
        .environment(\.rummyBoardZoomPreview, zoom)
    _ = try rBitmap(panel)
    let bitmap = try rBitmap(panel)
    MiniGameSnapshots.save(bitmap, name: "rummy370-\(name).png", sub: "stills")
    return bitmap
}

/// 판 칸 안 타일 바탕색(흰 몸통) 픽셀 수.
private func rTilePixels(_ bitmap: NSBitmapImageRep) -> Int {
    guard let data = bitmap.bitmapData, bitmap.samplesPerPixel >= 3 else { return -1 }
    let L = RummyMatchLayout.standard
    let o = RummyWindowLayout.matchBodyOrigin
    let r = L.table.offsetBy(dx: o.x, dy: o.y)
    let body = RummyTilePalette.bodyTop
    let bpr = bitmap.bytesPerRow, spp = bitmap.samplesPerPixel
    var hits = 0
    for y in Int(r.minY * 2)..<min(bitmap.pixelsHigh, Int(r.maxY * 2)) {
        for x in Int(r.minX * 2)..<min(bitmap.pixelsWide, Int(r.maxX * 2)) {
            let i = y * bpr + x * spp
            if abs(Int(data[i]) - body.r) <= 12, abs(Int(data[i + 1]) - body.g) <= 12, abs(Int(data[i + 2]) - body.b) <= 12 {
                hits += 1
            }
        }
    }
    return hits
}

private let rFewTable = [["C3", "C4", "C5", "C6", "C7"], ["A7", "B7", "D7"], ["A4", "A5", "A6", "A7"], ["B10", "C10", "D10"],
                         ["D1", "D2", "D3"], ["A11", "A12", "A13"]]
private let rFewLayout = [[0, 0], [216, 0], [376, 0], [552, 0], [0, 72], [136, 72]]

@MainActor
@Suite("v0.3.70 아잉 큐브 판 조작감 — 렌더(판 기본 확대 · 위 띠 머리글 · 규칙 '조작')")
struct V0370RummyBoardRenderTests {
    @Test("판 기본은 [판 확대] — 같은 판을 전체 보기보다 크게 그린다(한 값만 바꾼 기준선: 확대 켬/끔)")
    func defaultIsZoomed() throws {
        // 없으면: 기본이 전체 보기라 판 타일이 작게 남는 결함이 초록이 된다.
        let byDefault = try rRender(table: rFewTable, layout: rFewLayout, zoom: nil, name: "board-default")
        let fit = try rRender(table: rFewTable, layout: rFewLayout, zoom: false, name: "board-fit")
        let a = rTilePixels(byDefault), b = rTilePixels(fit)
        #expect(Double(a) > Double(b) * 1.5, "기본 \(a) · 전체 보기 \(b)")
    }

    @Test("그룹 B5 C5 D5 오른끝 위로 A5 를 끌면 캐럿·윤곽이 왼끝(표시 순서 자리)에 선다 — 놓은 뒤와 확정 뒤가 같은 자리")
    func groupCaretAtDisplaySlot() throws {
        // 없으면: 미리보기는 오른끝인데 놓으면 왼끝으로 가는(또는 확정 뒤 튀는) 결함이 초록이 된다.
        let L = RummyMatchLayout.standard
        let canvas = RummyCanvasTransform.fit(viewport: L.table.size)
        func screen(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            let s = canvas.toScreen(CGPoint(x: x, y: y))
            return CGPoint(x: s.x + L.table.minX, y: s.y + L.table.minY)
        }
        let bitmap = try rRender(table: [["B5", "C5", "D5"]], layout: [[400, 200]], zoom: false,
                                 drag: ("A5", screen(400 + 3 * 40 - 6, 228)), name: "drag-group-display-slot")
        guard let data = bitmap.bitmapData else { Issue.record("비트맵 없음"); return }
        let o = RummyWindowLayout.matchBodyOrigin
        func green(atLogicalX x: CGFloat) -> Int {
            let top = screen(x, 210), bottom = screen(x, 246)
            var hits = 0
            for py in Int((top.y + o.y) * 2)..<Int((bottom.y + o.y) * 2) {
                for px in Int((top.x + o.x - 3) * 2)..<Int((top.x + o.x + 3) * 2) {
                    let i = py * bitmap.bytesPerRow + px * bitmap.samplesPerPixel
                    if abs(Int(data[i]) - 89) <= 30, abs(Int(data[i + 1]) - 224) <= 30, abs(Int(data[i + 2]) - 161) <= 30 { hits += 1 }
                }
            }
            return hits
        }
        let left = green(atLogicalX: 400), right = green(atLogicalX: 520)
        #expect(left > 20 && left > right * 3, "캐럿이 왼끝에 없다(왼 \(left) · 오른 \(right))")
    }

    @Test("규칙 창에 '조작' 칸 · 판 화면 위 띠에 [규칙]·[기권] (렌더 저장)")
    func rulesAndChrome() throws {
        // 없으면: 규칙 창이 창 밖으로 넘치거나 위 띠의 [규칙]이 안 그려지는 결함이 초록이 된다.
        let rules = try rRender(table: rFewTable, layout: rFewLayout, zoom: nil, overlay: .rules, name: "rules")
        let plain = try rRender(table: rFewTable, layout: rFewLayout, zoom: nil, name: "board-default")
        #expect(rules.pixelsWide == Int(RummyWindowLayout.contentSize.width * 2))
        // [규칙]·[기권] 버튼 칸에 무언가 그려졌다(바탕과 다른 픽셀).
        guard let data = plain.bitmapData else { Issue.record("비트맵 없음"); return }
        let o = RummyWindowLayout.matchBodyOrigin
        let r = RummyMatchLayout.standard.chromeRight.offsetBy(dx: o.x, dy: o.y)
        let bg = (Int(data[0]), Int(data[1]), Int(data[2]))
        var ink = 0
        for y in Int(r.minY * 2)..<Int(r.maxY * 2) {
            for x in Int(r.minX * 2)..<Int(r.maxX * 2) {
                let i = y * plain.bytesPerRow + x * plain.samplesPerPixel
                if abs(Int(data[i]) - bg.0) + abs(Int(data[i + 1]) - bg.1) + abs(Int(data[i + 2]) - bg.2) > 60 { ink += 1 }
            }
        }
        #expect(ink > 400, "위 띠 오른쪽 칸이 비었다(\(ink))")
    }
}
