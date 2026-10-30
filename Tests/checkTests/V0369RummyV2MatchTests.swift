import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// v0.3.69 아잉 큐브 **2판 판 화면** — 배치 B · 자유 배치 캔버스 · 반 칸 받침대 · 묶음째 집기 · 4색 타일 · 그림 로더.
//
// 순수 기하(칸 자리 · 캔버스 변환 · 받침대 슬롯 · 놓을 자리 판정 · 자리 배치 · 그림 판정)는 값으로 묻고, 화면은 ImageRenderer(scale 2)로
// `CHECK_SNAPSHOT_DIR/stills-match/rummy2-*.png` 에 굽는다(사람이 직접 연다). 렌더 단언은 "그 자리에 그 잉크가 있는가"를
// **한 값만 바꾼 기준선**과 견준다. 각 시험의 첫 줄 주석은 "없으면 어떤 결함이 초록으로 통과하는가" 다.

// MARK: - 픽스처

private let mvNow = Date(timeIntervalSince1970: 1_800_000_000)
private var mvNowMs: Double { mvNow.timeIntervalSince1970 * 1000 }
private let mvMe = ChessPlayerFace(name: "영식", avatarURL: nil, characterID: "shiba")
private let mvMatchID = "7e7e0000-0000-4000-8000-000000000069"
private let mvPeople: [(id: String, name: String, character: String)] = [
    ("00000000-0000-4000-8000-0000000000a1", "영식", "shiba"), ("00000000-0000-4000-8000-0000000000b2", "민수", "fox"),
    ("00000000-0000-4000-8000-0000000000c3", "준호", "squirrel"), ("00000000-0000-4000-8000-0000000000d4", "서연", "ghost"),
]

/// 자유 배치 판(묶음 8개) — 흩어진 자리.
private let mvTable: [[String]] = [["A3", "A4", "A5"], ["B7", "C7", "D7"], ["C9", "C10", "C11", "C12"], ["A10", "B10", "C10"],
                                   ["D1", "D2", "D3"], ["B4", "B5", "B6", "B7"], ["A11", "B11", "D11"], ["C1", "C2", "C3"]]
private let mvLayout: [[Int]] = [[24, 16], [232, 40], [520, 8], [96, 152], [400, 176], [680, 120], [160, 320], [560, 360]]
private let mvRack: [String] = ["A6", "B2", "B9", "B10", "B11", "C5", "D1", "D13", "J", "A12", "C3", "A7", "D7", "C7"]

private func mvFaces(_ texts: [String]) -> [RummyFace] { texts.compactMap(RummyFace.init(text:)) }

private func mvMatch(turn: Int = 0, table: [[String]] = mvTable, layout: [[Int]]? = mvLayout,
                     draft: [[String]]? = nil, draftLayout: [[Int]]? = nil) throws -> RummyMatchState {
    let seats: [[String: Any]] = mvPeople.enumerated().map { index, person in
        ["seat_no": index, "user_id": person.id, "display_name": person.name, "avatar_url": NSNull(),
         "character": person.character, "state": "playing", "rack_count": [14, 9, 14, 12][index],
         "initial_done": index != 2, "timeout_streak": index == 3 ? 1 : 0]
    }
    var state: [String: Any] = [
        "id": mvMatchID, "status": "active", "host_id": mvPeople[0].id, "stake": 5, "is_public": false, "seat_count": 4,
        "max_seats": 4, "server_now_ms": mvNowMs, "seq": 21, "seats": seats, "my_seat_no": 0, "my_rack": mvRack,
        "my_initial_done": true, "table": table, "pool_count": 38, "turn_seat_no": turn,
        "turn_started_ms": mvNowMs - 18_000, "turn_deadline_ms": mvNowMs + 42_000, "grace_ms": 2000,
        "consecutive_passes": 0, "last_event": ["kind": "draw", "seat_no": 3, "count": 1, "at_ms": mvNowMs - 19_000],
    ]
    if let layout { state["table_layout"] = layout }
    if let draft {
        var d: [String: Any] = ["table": draft, "draft_seq": 4, "at_ms": mvNowMs - 2_000]
        if let draftLayout { d["layout"] = draftLayout }
        state["draft"] = d
    }
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(RummyMatchState.self, from: JSONSerialization.data(withJSONObject: state))
}

private func mvEditor(table: [[String]] = mvTable, layout: [[Int]]? = mvLayout, rack: [String] = mvRack) -> RummyTurnEditor {
    RummyTurnEditor(table: table.map(mvFaces), rack: mvFaces(rack), initialDone: true,
                    tableLayout: layout.map { RummyLayout($0.map { RummyPoint(x: $0[0], y: $0[1]) }) })
}

private func mvTileID(_ editor: RummyTurnEditor, _ text: String) -> Int {
    (editor.rack + editor.melds.flatMap { $0 }).first { $0.face.text == text }!.id
}

// MARK: - 렌더 도우미

private enum MVError: Error { case render }

@MainActor
private func mvBitmap(_ view: some View) throws -> NSBitmapImageRep {
    let renderer = ImageRenderer(content: view.fixedSize())
    renderer.scale = 2
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff) else { throw MVError.render }
    return bitmap
}

/// 창 화면 한 장(1240×700 · scale 2). 첫 두 장은 다르게 나온다(실측) — 굳힌 뒤 둘째 장을 쓴다.
@MainActor
private func mvRender(match: RummyMatchState, editor: RummyTurnEditor?, drag: RummyPreviewDrag? = nil,
                      zoom: Bool? = nil, art: RummyArtStyle = .automatic, reactions: [RummyReactionBubble]? = nil,
                      name: String? = nil) throws -> NSBitmapImageRep {
    let panel = RummyPanel(store: RummyStore(), me: { mvMe }, clipsOverflowInsteadOfScroll: true, previewMatch: match,
                           previewEditor: editor, previewNow: mvNow, previewMyUserID: UUID(uuidString: mvPeople[0].id),
                           previewDrag: drag, previewReactions: reactions)
        .environment(\.rummyBoardZoomPreview, zoom)
        .environment(\.rummyArtStyle, art)
        .environment(\.colorScheme, .dark)
    _ = try mvBitmap(panel)
    let bitmap = try mvBitmap(panel)
    if let name { MiniGameSnapshots.save(bitmap, name: "rummy2-\(name).png", sub: "stills-match") }
    return bitmap
}

private func mvCount(_ bitmap: NSBitmapImageRep, near target: (Int, Int, Int), tolerance: Int = 18, in rect: CGRect) -> Int {
    guard let data = bitmap.bitmapData, bitmap.samplesPerPixel >= 3 else { return -1 }
    let bpr = bitmap.bytesPerRow, spp = bitmap.samplesPerPixel
    let x0 = max(0, Int(rect.minX * 2)), x1 = min(bitmap.pixelsWide - 1, Int(rect.maxX * 2))
    let y0 = max(0, Int(rect.minY * 2)), y1 = min(bitmap.pixelsHigh - 1, Int(rect.maxY * 2))
    guard x0 <= x1, y0 <= y1 else { return 0 }
    var hits = 0
    for y in y0...y1 {
        for x in x0...x1 {
            let o = y * bpr + x * spp
            if abs(Int(data[o]) - target.0) <= tolerance, abs(Int(data[o + 1]) - target.1) <= tolerance,
               abs(Int(data[o + 2]) - target.2) <= tolerance { hits += 1 }
        }
    }
    return hits
}

private func mvDiff(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep, in r: CGRect, threshold: Int = 24) -> Double {
    guard let da = a.bitmapData, let db = b.bitmapData, a.pixelsWide == b.pixelsWide, a.pixelsHigh == b.pixelsHigh
    else { return 1 }
    let spp = a.samplesPerPixel, bpr = a.bytesPerRow
    let x0 = max(0, Int(r.minX * 2)), x1 = min(a.pixelsWide - 1, Int(r.maxX * 2))
    let y0 = max(0, Int(r.minY * 2)), y1 = min(a.pixelsHigh - 1, Int(r.maxY * 2))
    var differ = 0, total = 0
    for y in y0...y1 {
        for x in x0...x1 {
            total += 1
            let o = y * bpr + x * spp
            for c in 0..<3 where abs(Int(da[o + c]) - Int(db[o + c])) > threshold {
                differ += 1
                break
            }
        }
    }
    return total == 0 ? 0 : Double(differ) / Double(total)
}

private func mvRGB(_ rgb: RummyTilePalette.RGB) -> (Int, Int, Int) { (rgb.r, rgb.g, rgb.b) }
private let mvAccent = (84, 171, 255)
private let mvWorking = (89, 224, 161)

private typealias W = RummyWindowLayout
private let mvL = RummyMatchLayout.standard
/// 판 화면 좌표 → 창 좌표.
private func mvWin(_ rect: CGRect) -> CGRect {
    rect.offsetBy(dx: W.contentPadding, dy: W.contentPadding + W.headerHeight + W.headerSpacing)
}
private func mvWin(_ point: CGPoint) -> CGPoint {
    CGPoint(x: point.x + W.contentPadding, y: point.y + W.contentPadding + W.headerHeight + W.headerSpacing)
}
/// 논리 판 사각형 → 창 좌표(전체 맞춤 또는 확대).
private func mvBoard(_ r: RummyRect, _ canvas: RummyCanvasTransform = .fit(viewport: mvL.table.size)) -> CGRect {
    mvWin(canvas.rect(r).offsetBy(dx: mvL.table.minX, dy: mvL.table.minY))
}
/// 판 화면 좌표의 받침대 자리 → 창 좌표.
private func mvRackSlot(_ slot: RummyRackSlot, rows: Int = 2) -> CGRect {
    mvWin(RummyRackGeometry(height: mvL.rackHeight, rowCount: rows).frame(slot).offsetBy(dx: mvL.rack.minX, dy: mvL.rack.minY))
}

/// 틀 바깥 3pt ~ 안쪽 3pt 띠의 빨간 잉크.
private func mvRedRing(_ bitmap: NSBitmapImageRep, _ frame: CGRect) -> Int {
    let invalid = mvRGB(RummyTilePalette.invalid)
    let outer = frame.insetBy(dx: -5, dy: -5)
    let bands = [CGRect(x: outer.minX, y: outer.minY, width: outer.width, height: 5),
                 CGRect(x: outer.minX, y: outer.maxY - 5, width: outer.width, height: 5),
                 CGRect(x: outer.minX, y: outer.minY, width: 5, height: outer.height),
                 CGRect(x: outer.maxX - 5, y: outer.minY, width: 5, height: outer.height)]
    return bands.reduce(0) { $0 + mvCount(bitmap, near: invalid, tolerance: 40, in: $1) }
}

// MARK: - 순수 기하

@Suite("아잉 큐브 2판 판 화면 기하(순수)")
struct V0369RummyV2MatchTests {
    @Test("칸 자리 — 위 띠 · 가운데 셋 · 아래 셋이 겹치지 않고 본문 안 · 받침대는 그림 비율(타일 0.31H)")
    func layoutAddsUp() {
        // 없으면: 상수 하나를 바꾼 것이 판·받침대를 겹치게 하거나 버튼 열을 창 밖으로 민다.
        let L = mvL
        let body = CGRect(origin: .zero, size: L.size)
        let all = [L.potCard, L.topSeat, L.poolCard, L.leftSeat, L.table, L.rightSeat, L.mySeat, L.rack, L.actions]
        for (i, a) in all.enumerated() {
            #expect(body.contains(a), "칸 \(i) 가 본문 밖 \(a)")
            for b in all[(i + 1)...] { #expect(!a.intersects(b), "칸이 겹친다 \(a) · \(b)") }
        }
        #expect(L.rackHeight == (RummyTileSize.rack.size.height / RummyRackArtMetrics.tileHeight).rounded())
        #expect(L.rack.width >= RummyTileSize.rack.size.width * 16, "받침대 한 줄에 16장이 안 든다")
        #expect(L.actions.width >= 300, "버튼 열이 좁다(\(L.actions.width))")
        #expect(L.actions.contains(L.drawButton))
        // 판은 전체 맞춤에서도 타일이 22pt 이상(읽히는 크기).
        #expect(RummyCanvasTransform.fit(viewport: L.table.size).scale * 40 >= 22)
        // 창 레이아웃 호환 값(CheckRummyWindow 항등식이 쓴다).
        #expect(RummyRackGeometry.tile == RummyTileSize.rack.size && RummyRackGeometry.rows == 2)
    }

    @Test("캔버스 변환 — 맞춤은 캔버스 전체를 칸 안에 · 왕복이 제자리 · 확대는 묶음을 하나도 안 자르고 더 크게")
    func canvasTransform() {
        // 없으면: 그린 묶음과 누르는 묶음이 어긋나거나, [판 확대] 가 묶음을 칸 밖으로 잘라 안 보이게 한다.
        let viewport = mvL.table.size
        let fit = RummyCanvasTransform.fit(viewport: viewport)
        let whole = fit.rect(RummyRect(x: 0, y: 0, width: 1000, height: 640))
        #expect(CGRect(origin: .zero, size: viewport).insetBy(dx: -0.5, dy: -0.5).contains(whole))
        for p in [CGPoint(x: 0, y: 0), CGPoint(x: 517, y: 233), CGPoint(x: 1000, y: 640)] {
            let back = fit.toLogical(fit.toScreen(p))
            #expect(abs(back.x - p.x) < 0.001 && abs(back.y - p.y) < 0.001)
        }
        let layout = RummyTableLayout(sets: mvTable.map(mvFaces),
                                      layout: RummyLayout(mvLayout.map { RummyPoint(x: $0[0], y: $0[1]) }))
        let small = Array(layout.frames.prefix(3))
        let zoom = RummyCanvasTransform.zoom(viewport: viewport, content: small)
        #expect(zoom.scale > fit.scale * 1.2, "묶음 셋인데 확대가 안 된다(\(fit.scale) → \(zoom.scale))")
        #expect(zoom.scale <= 1.0001)
        let view = CGRect(origin: .zero, size: viewport).insetBy(dx: -0.5, dy: -0.5)
        for frame in small { #expect(view.contains(zoom.rect(frame)), "확대가 묶음 \(frame) 을 잘랐다") }
        // ★ 기준선: 묶음이 판 끝까지 퍼져 있으면 확대해도 맞춤보다 작아지지 않고, 그래도 다 보인다.
        let spread = RummyCanvasTransform.zoom(viewport: viewport, content: layout.frames + [RummyRect(x: 900, y: 580, width: 80, height: 56)])
        #expect(spread.scale >= fit.scale - 0.0001)
        for frame in layout.frames { #expect(view.contains(spread.rect(frame))) }
    }

    @Test("받침대 슬롯 — 그린 자리에서 다시 고른 슬롯이 제자리 · 기준선 0.44H/0.76H · 줄이 넘치면 줄여 담는다")
    func rackSlots() {
        // 없으면: 받침대 위 놓기가 반 칸씩 밀리거나 다른 줄로 가고, 3번째 줄 타일이 받침대 밖에 그려진다.
        let g = RummyRackGeometry(height: mvL.rackHeight)
        #expect(abs(g.rowBottom(0) - 0.44 * g.height) < 0.01 && abs(g.rowBottom(1) - 0.76 * g.height) < 0.01)
        for row in 0..<2 {
            for half in stride(from: 0, through: 30, by: 1) {
                let slot = RummyRackSlot(row: row, halfCol: half)
                let f = g.frame(slot)
                #expect(g.slot(tileLeft: f.minX + 3, centerY: f.midY, tiles: 1) == slot)
                #expect(f.maxX <= mvL.rack.width - g.sideInset + 0.5, "타일이 받침대 구간 밖 \(slot)")
            }
        }
        // 묶음은 끝에서 잘린다(3장이면 반 칸 26 이 마지막).
        #expect(g.slot(tileLeft: 9999, centerY: g.rowCenter(1), tiles: 3) == RummyRackSlot(row: 1, halfCol: 26))
        let three = RummyRackGeometry(height: mvL.rackHeight, rowCount: 3)
        #expect(three.tileSize.height < g.tileSize.height)
        #expect(three.frame(RummyRackSlot(row: 0, halfCol: 0)).minY >= 0)
        #expect(three.frame(RummyRackSlot(row: 2, halfCol: 30)).maxY <= 0.77 * g.height)
    }

    @Test("상대 자리 — 나 다음부터 왼쪽 → 위 → 오른쪽 · 둘이면 위 · 셋이면 왼·오른")
    func seatArrangement() {
        // 없으면: 차례 도는 방향과 화면 둘레가 반대가 되거나, 2인 판에서 상대가 옆 칸에 붙어 위가 비어 보인다.
        #expect(RummySeatArrangement.arrange(seatNos: [0, 1, 2, 3], mine: 0) == RummySeatArrangement(left: 1, top: 2, right: 3))
        #expect(RummySeatArrangement.arrange(seatNos: [0, 1, 2, 3], mine: 2) == RummySeatArrangement(left: 3, top: 0, right: 1))
        #expect(RummySeatArrangement.arrange(seatNos: [0, 1, 2], mine: 1) == RummySeatArrangement(left: 2, top: nil, right: 0))
        #expect(RummySeatArrangement.arrange(seatNos: [0, 1], mine: 1) == RummySeatArrangement(left: nil, top: 0, right: nil))
    }

    @Test("놓을 자리 — 받침대 = 반 칸 슬롯 · 묶음 위 = 끼울 자리 · 빈 곳 = 왼쪽 위 · 남의 차례면 판 닫힘 · 손잡이 = 오프셋")
    func dropResolver() {
        // 없으면: 판 빈 곳에 놓은 묶음이 손 자리와 동떨어진 곳에 생기거나, 남의 차례에 판으로 요청이 나간다.
        let L = mvL
        let canvas = RummyCanvasTransform.fit(viewport: L.table.size)
        let table = RummyTableLayout(sets: mvTable.map(mvFaces), layout: RummyLayout(mvLayout.map { RummyPoint(x: $0[0], y: $0[1]) }))
        let rack = RummyRackGeometry(height: L.rackHeight)
        func screen(_ logical: CGPoint) -> CGPoint {
            let p = canvas.toScreen(logical)
            return CGPoint(x: p.x + L.table.minX, y: p.y + L.table.minY)
        }
        // 묶음 2(C9..C12 @ 520,8)의 셋째 타일 오른쪽 반 → 끼울 자리 3.
        let onMeld = screen(CGPoint(x: 520 + 40 * 2 + 30, y: 30))
        #expect(RummyDropResolver.target(pointer: onMeld, grabIndex: 0, count: 1, layout: L, canvas: canvas, table: table,
                                         rack: rack, isMyTurn: true) == .meld(2, index: 3))
        // 빈 곳(논리 300,500)에 한 장 → 그 타일 가운데가 손 자리.
        let empty = screen(CGPoint(x: 300, y: 500))
        #expect(RummyDropResolver.target(pointer: empty, grabIndex: 0, count: 1, layout: L, canvas: canvas, table: table,
                                         rack: rack, isMyTurn: true) == .newMeldAt(RummyPoint(x: 280, y: 472)))
        // 셋 묶음을 둘째 장으로 잡았으면 왼쪽 위는 한 장 반 왼쪽.
        #expect(RummyDropResolver.target(pointer: empty, grabIndex: 1, count: 3, layout: L, canvas: canvas, table: table,
                                         rack: rack, isMyTurn: true) == .newMeldAt(RummyPoint(x: 240, y: 472)))
        // 자기 묶음을 통째로 끌면 자기 위는 '빈 곳'(위치 이동).
        let onSelf = screen(CGPoint(x: 30, y: 30))
        #expect(RummyDropResolver.target(pointer: onSelf, grabIndex: 0, count: 3, layout: L, canvas: canvas, table: table,
                                         rack: rack, isMyTurn: true, skipMeld: 0) == .newMeldAt(RummyPoint(x: 10, y: 2)))
        // 받침대: 앞줄 둘째 칸 자리 → 반 칸 2.
        let slotFrame = rack.frame(RummyRackSlot(row: 1, halfCol: 2))
        let onRack = CGPoint(x: L.rack.minX + slotFrame.midX, y: L.rack.minY + slotFrame.midY)
        #expect(RummyDropResolver.target(pointer: onRack, grabIndex: 0, count: 1, layout: L, canvas: canvas, table: table,
                                         rack: rack, isMyTurn: false) == .rackSlot(RummyRackSlot(row: 1, halfCol: 2)))
        // 남의 차례엔 판이 닫힌다 · 판 밖(위 띠)은 없음.
        #expect(RummyDropResolver.target(pointer: empty, grabIndex: 0, count: 1, layout: L, canvas: canvas, table: table,
                                         rack: rack, isMyTurn: false) == nil)
        #expect(RummyDropResolver.target(pointer: CGPoint(x: L.topSeat.midX, y: 10), grabIndex: 0, count: 1, layout: L,
                                         canvas: canvas, table: table, rack: rack, isMyTurn: true) == nil)
        // 손잡이: 잡은 오프셋을 뺀 왼쪽 위 · 캔버스 밖으로 안 나간다.
        #expect(RummyDropResolver.setTarget(pointer: empty, grab: CGPoint(x: -7, y: 28), tiles: 3, layout: L, canvas: canvas)
                == RummyPoint(x: 307, y: 472))
        #expect(RummyDropResolver.clampedTopLeft(CGPoint(x: 990, y: 700), tiles: 3) == RummyPoint(x: 880, y: 584))
    }

    @Test("그림 판정 — 200+쓸 그림 = 바꿈 · 304·실패 = 그대로 · 404 = 번들로 · 번들 사본 둘 다 들어 있다")
    @MainActor
    func artOutcome() throws {
        // 없으면: 서버가 엉뚱한 그림(정사각 받침대 · 빈 응답)을 주면 받침대가 찌그러지거나, 지운 그림이 캐시에 영영 남는다.
        let rack = try #require(RummyArt.bundledImage(.rack), "번들 받침대 사본이 없다")
        let felt = try #require(RummyArt.bundledImage(.table), "번들 펠트 사본이 없다")
        #expect(RummyArt.isAcceptable(rack, kind: .rack) && RummyArt.isAcceptable(felt, kind: .table))
        #expect(!RummyArt.isAcceptable(felt, kind: .rack), "정사각 그림을 받침대로 받았다")
        let tiff = try #require(rack.tiffRepresentation)
        let rackPNG = try #require(NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]))
        #expect(RummyArt.outcome(status: 200, data: rackPNG, kind: .rack) == .replace)
        #expect(RummyArt.outcome(status: 200, data: Data("nope".utf8), kind: .rack) == .keep)
        #expect(RummyArt.outcome(status: 304, data: Data(), kind: .rack) == .keep)
        #expect(RummyArt.outcome(status: 404, data: Data(), kind: .table) == .revert)
        #expect(RummyArt.outcome(status: 500, data: rackPNG, kind: .rack) == .keep)
        // 시험 중 저장소는 캐시를 안 읽고 번들 사본으로 선다(운영에 안 닿는다).
        let art = RummyArt()
        #expect(art.rackSlices != nil && art.table != nil)
        #expect(RummyArt.remoteURL(.rack).absoluteString.hasSuffix("/storage/v1/object/public/game-art/rummy/rack.png"))
    }

    @Test("받침대 모션 키 — 차례가 바뀌어 id 가 새로 붙어도 같은 면은 같은 키")
    func rackMotionKeys() {
        // 없으면: 남이 낼 때마다 내 받침대 타일이 전부 새 뷰로 갈려 깜박인다(정렬·뽑기 모션도 끊긴다).
        let a = mvEditor()
        let b = mvEditor(table: Array(mvTable.prefix(2)), layout: Array(mvLayout.prefix(2)))
        let ka = RummyRackGeometry.motionKeys(a.rack), kb = RummyRackGeometry.motionKeys(b.rack)
        #expect(a.rack.map(\.id) != b.rack.map(\.id), "기준선: 판 장수가 다르면 받침대 id 가 달라야 한다")
        #expect(a.rack.map { ka[$0.id]! } == b.rack.map { kb[$0.id]! })
    }
}

// MARK: - 렌더

@MainActor
@Suite(.serialized)
struct V0369RummyV2MatchRenderTests {
    @Test("타일 4색 — 빨강·파랑·검정·주황 잉크가 서로 갈리고 표식은 숫자보다 작다 · 조커는 아잉이 + 네 색 점")
    func fourColorTiles() throws {
        // 없으면: 두 색이 판에서 안 갈리거나(파스텔), 표식이 숫자만큼 커서 숫자를 가린다.
        let faces = mvFaces(["A7", "B7", "C7", "D7", "J"])
        let size = RummyTileSize.rack.size
        let row = HStack(spacing: 10) {
            ForEach(Array(faces.enumerated()), id: \.offset) { _, face in RummyTileView(face: face, size: .rack) }
        }
        .padding(10)
        .background(Color(red: 0.13, green: 0.11, blue: 0.27))
        _ = try mvBitmap(row)
        let bitmap = try mvBitmap(row)
        MiniGameSnapshots.save(bitmap, name: "rummy2-tiles.png", sub: "stills-match")
        func rect(_ i: Int) -> CGRect {
            CGRect(x: 10 + CGFloat(i) * (size.width + 10), y: 10, width: size.width, height: size.height).insetBy(dx: 4, dy: 4)
        }
        for color in 0..<4 {
            let ink = mvRGB(RummyTilePalette.inks[color])
            let mine = mvCount(bitmap, near: ink, tolerance: 22, in: rect(color))
            #expect(mine > 120, "색 \(color) 타일에 제 잉크가 \(mine)px")
            for other in 0..<4 where other != color {
                let leak = mvCount(bitmap, near: ink, tolerance: 22, in: rect(other))
                #expect(leak < mine / 6, "색 \(color) 잉크가 색 \(other) 타일에도 \(leak)px — 두 색이 안 갈린다")
            }
        }
        #expect(RummyTileSize.rack.markSize < RummyTileSize.rack.numberFont / 2, "색 표식이 숫자 절반보다 크다")
        for color in 0..<4 {
            #expect(mvCount(bitmap, near: mvRGB(RummyTilePalette.inks[color]), tolerance: 30, in: rect(4)) > 2, "조커에 색 \(color) 점이 없다")
        }
        #expect(RummyJokerFace.faceImage != nil)
    }

    @Test("내 차례 — 펠트 위 자유 배치 묶음 · 무효 묶음 빨간 테두리는 편집기 판정 그대로 · 받침대 타일 · 차례 링 · 기준선 = 남의 차례")
    func myTurn() throws {
        // 없으면: 묶음이 서버 배치와 다른 자리에 그려지거나, 무효 테두리가 판정과 따로 놀거나, 받침대가 비어 보인다.
        var editor = mvEditor()
        let b2 = mvTileID(editor, "B2")
        let moved = editor.move(b2, to: .meld(1, index: nil))
        #expect(moved, "B2 를 그룹 7 에 못 놓았다")
        let mine = try mvRender(match: try mvMatch(turn: 0), editor: editor, name: "my-turn")
        let other = try mvRender(match: try mvMatch(turn: 1), editor: editor, name: "other-turn-table")
        let layout = editor.tableLayout
        for index in editor.melds.indices {
            let frame = mvBoard(try #require(layout.frame(of: index)))
            let body = mvCount(mine, near: mvRGB(RummyTilePalette.bodyTop), tolerance: 12, in: frame)
            #expect(body > 150, "묶음 \(index) 자리에 타일 몸체가 \(body)px")
            let red = mvRedRing(mine, frame)
            if editor.analysis(ofMeld: index).valid {
                #expect(red < 40, "맞는 묶음 \(index) 에 빨간 테두리 \(red)px")
            } else {
                #expect(red > 250, "무효 묶음 \(index) 에 빨간 테두리가 \(red)px")
            }
        }
        // ★ 기준선: 남의 차례(작업 판 없음)엔 확정 판 — 무효 테두리가 없다.
        let confirmed = RummyTableLayout(sets: mvTable.map(mvFaces), layout: RummyLayout(mvLayout.map { RummyPoint(x: $0[0], y: $0[1]) }))
        for frame in confirmed.frames { #expect(mvRedRing(other, mvBoard(frame)) < 40) }
        // 받침대 첫 타일 자리에 몸체.
        let first = try #require(editor.rack.first.flatMap { editor.rackLayout.slot(of: $0.id) })
        #expect(mvCount(mine, near: mvRGB(RummyTilePalette.bodyTop), tolerance: 12, in: mvRackSlot(first)) > 100)
        // 내 자리 카드(왼쪽 아래)에 차례 링(파랑) — 기준선엔 없다.
        let card = mvWin(mvL.mySeat)
        let ringMine = mvCount(mine, near: mvAccent, tolerance: 26, in: card)
        let ringOther = mvCount(other, near: mvAccent, tolerance: 26, in: card)
        #expect(ringMine > ringOther + 300, "내 차례 링이 안 보인다(\(ringOther) → \(ringMine))")
        // [완료] 초록은 canSubmit 그대로.
        let submit = mvWin(CGRect(x: mvL.actions.minX, y: mvL.actions.minY, width: mvL.actions.width, height: RummyMatchLayout.submitHeight))
        let green = mvCount(mine, near: mvWorking, tolerance: 24, in: submit)
        #expect(editor.canSubmit ? green > 800 : green < 600, "[완료] 가 판정(\(editor.canSubmit))과 다르게 보인다(\(green)px)")
    }

    @Test("남의 차례 — 그 사람 작업 판(새 묶음 노란 링)과 배치 · 'OO님이 놓는 중' · 기준선 = 작업 판 없음")
    func othersDraft() throws {
        // 없으면: 남이 판을 주무르는 것이 안 보이거나, 남이 옮긴 자리가 아니라 자동 자리에 그려진다.
        let draft = mvTable + [["B9", "B10", "B11"]]
        let draftLayout = mvLayout + [[760, 480]]
        let drafting = try mvRender(match: try mvMatch(turn: 1, draft: draft, draftLayout: draftLayout), editor: mvEditor(),
                                    name: "other-turn-draft")
        let plain = try mvRender(match: try mvMatch(turn: 1), editor: mvEditor())
        let newMeld = mvBoard(RummyRect(x: 760, y: 480, width: 120, height: 56))
        let tiles = mvCount(drafting, near: mvRGB(RummyTilePalette.bodyTop), tolerance: 12, in: newMeld)
        let none = mvCount(plain, near: mvRGB(RummyTilePalette.bodyTop), tolerance: 12, in: newMeld)
        #expect(tiles > 150 && none < 10, "작업 판의 새 묶음이 그 자리에 없다(작업 \(tiles) · 확정 \(none))")
        let ring = mvCount(drafting, near: mvRGB(RummyTilePalette.highlight), tolerance: 30, in: newMeld.insetBy(dx: -4, dy: -4))
        #expect(ring > 40, "남이 이번 차례에 낸 타일에 노란 링이 없다(\(ring)px)")
        let tag = mvWin(CGRect(x: mvL.table.maxX - 220, y: mvL.table.maxY - 44, width: 220, height: 44))
        #expect(mvCount(drafting, near: mvAccent, tolerance: 26, in: tag) > 100, "'놓는 중' 꼬리표가 없다")
        #expect(mvDiff(drafting, plain, in: tag) > 0.01)
    }

    @Test("길게 눌러 들어 올림 — 이어진 덩어리(B9·B10·B11) 파랑 테두리 + 장수 뱃지 · 기준선 = 안 누름")
    func liftedBlock() throws {
        // 없으면: 길게 눌러도 무엇이 집혔는지 안 보여, 끌어 봐야 한 장만 따라오는지 셋이 따라오는지 안다.
        var editor = mvEditor()
        editor.sortRack(.color)
        let b10 = mvTileID(editor, "B10")
        let chain = editor.rackChain(around: b10)
        #expect(chain.count >= 3, "색 정렬 뒤 B9·B10·B11 이 이어진 덩어리가 아니다(\(chain.count))")
        let lifted = try mvRender(match: try mvMatch(turn: 0), editor: editor, drag: RummyPreviewDrag(liftedTileID: b10),
                                  name: "lifted-block")
        let plain = try mvRender(match: try mvMatch(turn: 0), editor: editor, name: "sorted-789")
        for id in chain {
            let slot = try #require(editor.rackLayout.slot(of: id))
            let rect = mvRackSlot(slot).insetBy(dx: -4, dy: -8)
            let blue = mvCount(lifted, near: mvAccent, tolerance: 26, in: rect)
            let base = mvCount(plain, near: mvAccent, tolerance: 26, in: rect)
            #expect(blue > base + 60, "집힌 타일 \(id) 에 들어 올림 테두리가 없다(\(base) → \(blue))")
            // 장수 뱃지가 타일 얼굴(숫자 칸)을 가리지 않는다 — 10-30 사용자 지적: 누른 타일에 단 뱃지가 이웃 숫자를 덮었다.
            let face = mvRackSlot(slot).insetBy(dx: 5, dy: 6)
            let inside = mvCount(lifted, near: mvAccent, tolerance: 26, in: face)
            let insideBase = mvCount(plain, near: mvAccent, tolerance: 26, in: face)
            #expect(inside <= insideBase + 25, "장수 뱃지가 타일 \(id) 얼굴을 가린다(\(insideBase) → \(inside))")
        }
    }

    @Test("정렬 직후 — 777 은 같은 숫자 단위 사이 반 칸 · 789 는 같은 색 연속 단위 사이 반 칸")
    func sortedHalfGaps() throws {
        // 없으면: 다른 조합끼리 딱 붙어 정렬돼(요구 8) 어디까지가 한 조합인지 안 보인다.
        for mode in [RummyRackSort.number, .color] {
            var editor = mvEditor()
            editor.sortRack(mode)
            let order = editor.rackLayout.readingOrder
            var gaps = 0
            for (a, b) in zip(order, order.dropFirst()) {
                guard let sa = editor.rackLayout.slot(of: a), let sb = editor.rackLayout.slot(of: b), sa.row == sb.row else { continue }
                #expect(sb.halfCol - sa.halfCol >= 2, "겹친 타일")
                if sb.halfCol - sa.halfCol == 3 { gaps += 1 }
            }
            #expect(gaps >= 2, "\(mode) 정렬에 반 칸 틈이 \(gaps)개뿐")
            if mode == .number { _ = try mvRender(match: try mvMatch(turn: 0), editor: editor, name: "sorted-777") }
        }
    }

    @Test("묶음째 끌기 — 판 빈 곳 위에서 스냅 자리 점선 · 판 타일을 받침대로 끌면 빨간 테두리(R-14) · 기준선 = 받침대 타일")
    func dragBlockAndRefusal() throws {
        // 없으면: 놓기 전에 어디 놓일지 안 보이거나, 판에 있던 타일을 받침대로 가져갈 수 있는 것처럼 보인다.
        var editor = mvEditor()
        editor.sortRack(.color)
        let b10 = mvTileID(editor, "B10")
        let canvas = RummyCanvasTransform.fit(viewport: mvL.table.size)
        let logical = CGPoint(x: 820, y: 520)
        let screen = canvas.toScreen(logical)
        let point = CGPoint(x: screen.x + mvL.table.minX, y: screen.y + mvL.table.minY)
        let dragging = try mvRender(match: try mvMatch(turn: 0), editor: editor,
                                    drag: RummyPreviewDrag(tileID: b10, point: point, block: true), name: "drag-block-table")
        let still = try mvRender(match: try mvMatch(turn: 0), editor: editor)
        let n = editor.rackChain(around: b10).count
        let grab = editor.rackChain(around: b10).firstIndex(of: b10) ?? 0
        let wanted = RummyPoint(x: Int((logical.x - (CGFloat(grab) + 0.5) * 40).rounded()), y: Int((logical.y - 28).rounded()))
        let ghost = mvBoard(RummyTableLayout.frame(at: editor.tableLayout.snap(wanted, tiles: n), tiles: n))
        // 손에 든 묶음이 점선 대부분을 덮는다 — 위 테두리(손 위로 삐져나온 띠)에서 잰다.
        let ghostBand = CGRect(x: ghost.minX - 3, y: ghost.minY - 4, width: ghost.width + 6, height: 5)
        let blue = mvCount(dragging, near: mvAccent, tolerance: 30, in: ghostBand)
        #expect(blue > mvCount(still, near: mvAccent, tolerance: 30, in: ghostBand) + 40, "새 묶음 스냅 자리 점선이 없다(\(blue))")

        let tableTile = editor.melds[0][0].id
        let rackTile = editor.rack[0].id
        let overRack = CGPoint(x: mvL.rack.midX, y: mvL.rack.midY)
        let refused = try mvRender(match: try mvMatch(turn: 0), editor: editor,
                                   drag: RummyPreviewDrag(tileID: tableTile, point: overRack), name: "drag-refused")
        let allowed = try mvRender(match: try mvMatch(turn: 0), editor: editor, drag: RummyPreviewDrag(tileID: rackTile, point: overRack))
        let edge = mvWin(CGRect(x: mvL.rack.minX, y: mvL.rack.minY, width: mvL.rack.width, height: 8))
        let invalid = mvRGB(RummyTilePalette.invalid)
        let redRefused = mvCount(refused, near: invalid, tolerance: 40, in: edge)
        let redAllowed = mvCount(allowed, near: invalid, tolerance: 40, in: edge)
        #expect(redRefused > redAllowed + 300, "판 타일을 받침대로 끌었는데 거절 표시가 없다(\(redAllowed) → \(redRefused))")
    }

    @Test("판 확대 · 그린 폴백 — 확대는 같은 묶음을 더 크게 · 그림이 없어도 펠트와 받침대가 그려진다")
    func zoomAndFallback() throws {
        // 없으면: [판 확대] 가 아무것도 안 바꾸거나, 그림을 못 받은 기기에서 판과 받침대가 빈 검정으로 나온다.
        let few = Array(mvTable.prefix(3)), fewLayout = Array(mvLayout.prefix(3))
        let editor = mvEditor(table: few, layout: fewLayout)
        let fit = try mvRender(match: try mvMatch(turn: 1, table: few, layout: fewLayout), editor: editor, name: "board-fit")
        let zoomed = try mvRender(match: try mvMatch(turn: 1, table: few, layout: fewLayout), editor: editor, zoom: true,
                                  name: "board-zoomed")
        let layout = RummyTableLayout(sets: few.map(mvFaces), layout: RummyLayout(fewLayout.map { RummyPoint(x: $0[0], y: $0[1]) }))
        let zoom = RummyCanvasTransform.zoom(viewport: mvL.table.size, content: layout.frames)
        let first = try #require(layout.frame(of: 0))
        let bigger = mvCount(zoomed, near: mvRGB(RummyTilePalette.bodyTop), tolerance: 12, in: mvBoard(first, zoom))
        let smaller = mvCount(fit, near: mvRGB(RummyTilePalette.bodyTop), tolerance: 12, in: mvBoard(first))
        #expect(bigger > smaller * 3 / 2, "확대했는데 묶음이 안 커졌다(\(smaller) → \(bigger))")

        let drawn = try mvRender(match: try mvMatch(turn: 0), editor: mvEditor(), art: .drawn, name: "my-turn-drawn-art")
        let painted = try mvRender(match: try mvMatch(turn: 0), editor: mvEditor())
        let rackBody = mvWin(CGRect(x: mvL.rack.minX + 20, y: mvL.rack.maxY - 22, width: mvL.rack.width - 40, height: 14))
        #expect(mvDiff(drawn, painted, in: rackBody) > 0.05, "그린 폴백이 그림과 같다 — 주입이 안 먹었다")
        // 폴백도 받침대 몸체(남색)와 판 펠트(남보라)가 있다 — 배경(창)보다 밝고 파랗다.
        func blueness(_ b: NSBitmapImageRep, _ r: CGRect) -> Int {
            guard let d = b.bitmapData else { return 0 }
            let x = Int(r.midX * 2), y = Int(r.midY * 2), o = y * b.bytesPerRow + x * b.samplesPerPixel
            return Int(d[o + 2]) - Int(d[o])
        }
        #expect(blueness(drawn, rackBody) > 15, "폴백 받침대가 남색이 아니다")
        #expect(blueness(drawn, mvWin(CGRect(x: mvL.table.minX + 30, y: mvL.table.maxY - 60, width: 4, height: 4))) > 10,
                "폴백 펠트가 남보라가 아니다")
    }

    @Test("판 위 반응 말풍선 — 자리 카드 앵커(위 자리는 오른쪽, 왼·오른 자리는 판 쪽, 내 자리는 위) · 기준선 = 말풍선 없음")
    func matchReactionBubbles() throws {
        // 없으면: 판 자리 카드에 앵커가 없어 말풍선이 방위 기본값(창 가장자리)에 떠 누가 보냈는지 안 읽히는 결함이 초록이 된다.
        let match = try mvMatch(turn: 1)
        let bubbles = [
            RummyReactionBubble(id: 1, seatNo: 1, sticker: .heart, isMine: false, receivedAt: mvNow.addingTimeInterval(-0.6)),
            RummyReactionBubble(id: 2, seatNo: 2, sticker: .surprised, isMine: false, receivedAt: mvNow.addingTimeInterval(-0.8)),
            RummyReactionBubble(id: 3, seatNo: 0, sticker: .joy, isMine: true, receivedAt: mvNow.addingTimeInterval(-1)),
        ]
        let reacted = try mvRender(match: match, editor: mvEditor(), reactions: bubbles, name: "reactions")
        let plain = try mvRender(match: match, editor: mvEditor())
        #expect(mvDiff(reacted, plain, in: mvWin(CGRect(origin: .zero, size: mvL.size))) > 0.004, "말풍선이 안 그려졌다")
        // 내 말풍선은 내 자리 카드 위쪽 띠(판 왼쪽 아래)에 선다.
        let aboveMine = mvWin(CGRect(x: mvL.mySeat.minX, y: mvL.mySeat.minY - 70, width: mvL.mySeat.width, height: 70))
        #expect(mvDiff(reacted, plain, in: aboveMine) > 0.03, "내 말풍선이 내 자리 위에 없다")
    }
}
