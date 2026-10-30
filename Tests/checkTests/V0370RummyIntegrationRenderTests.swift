import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// 아잉 큐브 0.3.70 통합 — 판 조작감(P) + 받침대·내 차례(R)를 한 창에 겹쳐 굽는다.
// 두 갈래는 각자 다른 그릇에서 렌더했다(P = 창 전체 · R = 판 화면만). 여기서는 **창 전체**(위 띠 머리글 · 판 확대 기본)에
// R 의 표시(테두리 빛 · 배지 · [완료] 안 초 · 랙 묶음 띠 · N/30)를 함께 그린다. 렌더는 `CHECK_SNAPSHOT_DIR/final/rummy370-final-*.png`.

private let iNow = Date(timeIntervalSince1970: 1_800_000_000)
private let iMe = ChessPlayerFace(name: "영식", avatarURL: nil, characterID: "shiba")
private let iPeople: [(id: String, name: String, character: String)] = [
    ("00000000-0000-4000-8000-0000000000a1", "영식", "shiba"), ("00000000-0000-4000-8000-0000000000b2", "민수", "fox"),
    ("00000000-0000-4000-8000-0000000000c3", "준호", "cat"), ("00000000-0000-4000-8000-0000000000d4", "서연", "bear"),
]
private let iTable = [["C3", "C4", "C5", "C6", "C7"], ["A7", "B7", "D7"], ["A4", "A5", "A6", "A7"], ["B10", "C10", "D10"],
                      ["D1", "D2", "D3"], ["A11", "A12", "A13"]]
private let iLayout = [[0, 0], [216, 0], [376, 0], [552, 0], [0, 72], [136, 72]]
/// 받침대(면, 줄, 반 칸): 딱 붙인 런 하나 · 그룹 하나 · 낱장.
private let iRack: [(String, Int, Int)] = [
    ("A8", 0, 0), ("A9", 0, 2), ("A10", 0, 4), ("B12", 0, 7), ("C12", 0, 9), ("D12", 0, 11),
    ("B2", 0, 14), ("J", 0, 17), ("D9", 0, 19), ("A5", 1, 0), ("B11", 1, 3), ("C1", 1, 6), ("D4", 1, 9),
]

private func iEditor(table: [[String]], layout: [[Int]], rack: [(String, Int, Int)], initialDone: Bool) -> RummyTurnEditor {
    let entries = rack.compactMap { e in RummyFace(text: e.0).map { RummyRackEntry(face: $0, slot: RummyRackSlot(row: e.1, halfCol: e.2)) } }
    return RummyTurnEditor(table: table.map { $0.compactMap(RummyFace.init(text:)) }, rack: entries.map(\.face),
                           initialDone: initialDone,
                           tableLayout: RummyLayout(layout.map { RummyPoint(x: $0[0], y: $0[1]) }), rackEntries: entries)
}

private func iMatch(table: [[String]], layout: [[Int]], rack: [String], initialDone: Bool, deadlineIn: Double) throws -> RummyMatchState {
    let nowMs = iNow.timeIntervalSince1970 * 1000
    let seats: [[String: Any]] = iPeople.enumerated().map { index, person in
        ["seat_no": index, "user_id": person.id, "display_name": person.name, "avatar_url": NSNull(),
         "character": person.character, "state": "playing", "rack_count": [rack.count, 9, 14, 12][index],
         "initial_done": index == 0 ? initialDone : true, "timeout_streak": 0]
    }
    let state: [String: Any] = [
        "id": "7e7e0000-0000-4000-8000-000000000371", "status": "active", "host_id": iPeople[0].id, "stake": 5,
        "is_public": false, "seat_count": 4, "max_seats": 4, "server_now_ms": nowMs, "seq": 30, "seats": seats,
        "my_seat_no": 0, "my_rack": rack, "my_initial_done": initialDone, "table": table, "table_layout": layout,
        "pool_count": 38, "turn_seat_no": 0, "turn_started_ms": nowMs - (60 - deadlineIn) * 1000,
        "turn_deadline_ms": nowMs + deadlineIn * 1000, "grace_ms": 2000, "consecutive_passes": 0,
    ]
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(RummyMatchState.self, from: JSONSerialization.data(withJSONObject: state))
}

private enum IError: Error { case render }

@MainActor
private func iBitmap(_ view: some View) throws -> NSBitmapImageRep {
    let renderer = ImageRenderer(content: view.fixedSize())
    renderer.scale = 2
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff) else { throw IError.render }
    return bitmap
}

/// 창 한 장(scale 2, 앱 기본 [판 확대]). 첫 두 장은 다르게 나온다 — 굳힌 뒤 둘째 장.
@MainActor
private func iRender(_ editor: RummyTurnEditor, table: [[String]], layout: [[Int]], initialDone: Bool = true,
                     deadlineIn: Double = 42, cues: RummyCuePreview?, overlay: RummyPreviewOverlay? = nil,
                     drag: RummyPreviewDrag? = nil, name: String) throws -> NSBitmapImageRep {
    let match = try iMatch(table: table, layout: layout, rack: editor.rack.map(\.face.text), initialDone: initialDone,
                           deadlineIn: deadlineIn)
    let panel = RummyPanel(store: RummyStore(), me: { iMe }, clipsOverflowInsteadOfScroll: true,
                           previewMatch: match, previewEditor: editor, previewNow: iNow,
                           previewMyUserID: UUID(uuidString: iPeople[0].id), previewOverlay: overlay, previewDrag: drag)
        .environment(\.rummyCuePreview, cues)
        .environment(\.colorScheme, .dark)
    _ = try iBitmap(panel)
    let bitmap = try iBitmap(panel)
    MiniGameSnapshots.save(bitmap, name: "rummy370-final-\(name).png", sub: "final")
    return bitmap
}

/// 판 논리 점 → 판 화면 좌표(앱 기본 [판 확대] 변환).
private func iScreen(_ x: CGFloat, _ y: CGFloat, table: [[String]], layout: [[Int]]) -> CGPoint {
    let L = RummyMatchLayout.standard
    let frames = RummyTableLayout(sets: table.map { $0.compactMap(RummyFace.init(text:)) },
                                  layout: RummyLayout(layout.map { RummyPoint(x: $0[0], y: $0[1]) })).frames
    let s = RummyCanvasTransform.zoom(viewport: L.table.size, content: frames).toScreen(CGPoint(x: x, y: y))
    return CGPoint(x: s.x + L.table.minX, y: s.y + L.table.minY)
}

/// 두 그림의 `rect`(창 pt) 안에서 채널 차가 `threshold` 를 넘는 픽셀 비율.
private func iDiff(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep, in rect: CGRect, threshold: Int = 28) -> Double {
    guard let da = a.bitmapData, let db = b.bitmapData, a.pixelsWide == b.pixelsWide, a.pixelsHigh == b.pixelsHigh
    else { return 1 }
    let spp = a.samplesPerPixel, bpr = a.bytesPerRow
    let x0 = max(0, Int(rect.minX * 2)), x1 = min(a.pixelsWide - 1, Int(rect.maxX * 2))
    let y0 = max(0, Int(rect.minY * 2)), y1 = min(a.pixelsHigh - 1, Int(rect.maxY * 2))
    guard x0 <= x1, y0 <= y1 else { return 0 }
    var changed = 0, total = 0
    for y in y0...y1 {
        for x in x0...x1 {
            let i = y * bpr + x * spp
            total += 1
            if (0..<3).contains(where: { abs(Int(da[i + $0]) - Int(db[i + $0])) > threshold }) { changed += 1 }
        }
    }
    return Double(changed) / Double(max(total, 1))
}

@MainActor
@Suite("v0.3.70 아잉 큐브 통합 렌더 — 판 조작감 + 받침대·내 차례를 한 창에", .serialized)
struct V0370RummyIntegrationRenderTests {
    @Test("내 차례 시작: 위 띠 머리글(P)과 받침대 빛·배지·[완료] 안 초(R)가 한 창에 — 표시가 머리글 칸을 덮지 않는다")
    func turnStartOnNewWindow() throws {
        // 없으면: 머리글을 위 띠로 옮긴 창(P)에서 R 의 '내 차례' 배지·테두리 빛이 머리글 칸을 가리거나 안 그려지는 결함이 초록이 된다.
        let editor = iEditor(table: iTable, layout: iLayout, rack: iRack, initialDone: true)
        let none = try iRender(editor, table: iTable, layout: iLayout, deadlineIn: 8, cues: RummyCuePreview(turnGlow: nil),
                               name: "turn-none")
        let start = try iRender(editor, table: iTable, layout: iLayout, deadlineIn: 8,
                                cues: RummyCuePreview(turnGlow: .pulse, turnBadge: true), name: "turn-start")
        _ = try iRender(editor, table: iTable, layout: iLayout, cues: RummyCuePreview(turnGlow: .steady), name: "board-default")
        let L = RummyMatchLayout.standard
        let o = RummyWindowLayout.matchBodyOrigin
        // 받침대 둘레에 빛이 생겼다.
        let rack = L.rack.offsetBy(dx: o.x, dy: o.y)
        #expect(iDiff(none, start, in: CGRect(x: rack.minX - 8, y: rack.minY - 8, width: rack.width + 16, height: 10)) > 0.05,
                "받침대 위 테두리 빛이 안 보인다")
        // 판 가운데 배지가 생겼다.
        let table = L.table.offsetBy(dx: o.x, dy: o.y)
        #expect(iDiff(none, start, in: CGRect(x: table.midX - 40, y: table.midY - 12, width: 80, height: 24)) > 0.2,
                "판 가운데 '내 차례' 배지가 안 보인다")
        // 위 띠 머리글 칸(루비·반응 · 규칙·기권)은 그대로다.
        for chrome in [L.chromeLeft, L.chromeRight] {
            #expect(iDiff(none, start, in: chrome.offsetBy(dx: o.x, dy: o.y)) < 0.01, "머리글 칸이 바뀌었다 \(chrome)")
        }
    }

    @Test("판 길게 눌러 쪼개기: 오른쪽 절반 타일을 누르면 거기서 끝까지만 들린다(확대 기본 판)")
    func liftSplitOnZoomedBoard() throws {
        // 없으면: 확대 기본 판에서 누른 타일 쪽 토막이 아니라 묶음 전체가 들리는 결함이 초록이 된다(그림 확인용).
        let editor = iEditor(table: iTable, layout: iLayout, rack: iRack, initialDone: true)
        let c6 = try #require(editor.melds[0].first { $0.face.text == "C6" }?.id)
        #expect(editor.meldChunk(for: c6).count == 2)
        _ = try iRender(editor, table: iTable, layout: iLayout, cues: RummyCuePreview(turnGlow: .steady),
                        drag: RummyPreviewDrag(liftedTileID: c6), name: "lift-split")
        _ = try iRender(editor, table: iTable, layout: iLayout, cues: RummyCuePreview(turnGlow: .steady),
                        drag: RummyPreviewDrag(tileID: c6, point: iScreen(440, 300, table: iTable, layout: iLayout), block: true),
                        name: "lift-split-drag")
    }

    @Test("그룹 끼우기 확정 전후: 오른끝에 끌어도 표시 순서 자리 → 놓은 판 = 확정 뒤 판(묶음 순서·자리)")
    func groupInsertBeforeAfterConfirm() throws {
        // 없으면: 놓을 때는 오른끝, 확정 뒤에는 왼끝으로 튀는 결함이 초록이 된다(창 전체 렌더로 확인).
        let table = iTable + [["B5", "C5", "D5"]]
        let layout = iLayout + [[400, 220]]
        var editor = iEditor(table: table, layout: layout, rack: iRack, initialDone: true)
        let a5 = try #require(editor.rack.first { $0.face.text == "A5" }?.id)
        _ = try iRender(editor, table: table, layout: layout, cues: RummyCuePreview(turnGlow: .steady),
                        drag: RummyPreviewDrag(tileID: a5, point: iScreen(400 + 3 * 40 - 6, 248, table: table, layout: layout)),
                        name: "group-insert-drag")
        let moved = editor.moveBlock([a5], to: .meld(6, index: 3))
        #expect(moved)
        #expect(editor.melds[6].map(\.face.text) == ["A5", "B5", "C5", "D5"])
        _ = try iRender(editor, table: table, layout: layout, cues: RummyCuePreview(turnGlow: .steady), name: "group-insert-dropped")
        let confirmedTable = editor.submissionTable.map { $0.map(\.text) }
        let confirmedLayout = editor.submissionLayout.points.map { p in [p?.x ?? 0, p?.y ?? 0] }
        let confirmed = RummyTurnEditor(table: editor.submissionTable, rack: editor.rack.map(\.face), initialDone: true,
                                        tableLayout: editor.submissionLayout)
        #expect(confirmed.melds.map { $0.map(\.face) } == editor.melds.map { $0.map(\.face) } && confirmed.points == editor.points)
        _ = try iRender(confirmed, table: confirmedTable, layout: confirmedLayout, cues: RummyCuePreview(turnGlow: nil),
                        name: "group-insert-confirmed")
    }

    @Test("남은 토막 확정 전후(0.3.70 검증): A3 J A5 A6 에서 A3 을 빼면 남은 토막이 바로 표시 순서 A5 A6 J — 놓은 판 = 확정 뒤 판")
    func leftoverRunBeforeAfterConfirm() throws {
        // 없으면: 남은 토막이 J A5 A6 그대로 남았다가 확정 뒤 판에서 조커가 왼끝 → 오른끝으로 튀는 결함이 초록이 된다(창 전체 렌더).
        let table = iTable + [["A3", "J", "A5", "A6"]]
        let layout = iLayout + [[400, 220]]
        var editor = iEditor(table: table, layout: layout, rack: iRack, initialDone: true)
        _ = try iRender(editor, table: table, layout: layout, cues: RummyCuePreview(turnGlow: .steady), name: "leftover-before")
        let a3 = try #require(editor.melds[6].first { $0.face.text == "A3" }?.id)
        let moved = editor.moveBlock([a3], to: .newMeldAt(RummyPoint(x: 640, y: 400)))
        #expect(moved)
        #expect(editor.melds[6].map(\.face.text) == ["A5", "A6", "J"])
        // A5 · A6 은 제자리(480 · 520), 조커만 오른끝(560)으로.
        #expect(editor.points[6] == RummyPoint(x: 480, y: 220))
        _ = try iRender(editor, table: table, layout: layout, cues: RummyCuePreview(turnGlow: .steady), name: "leftover-dropped")
        let confirmed = RummyTurnEditor(table: editor.submissionTable, rack: editor.rack.map(\.face), initialDone: true,
                                        tableLayout: editor.submissionLayout)
        #expect(confirmed.melds.map { $0.map(\.face) } == editor.melds.map { $0.map(\.face) } && confirmed.points == editor.points)
        _ = try iRender(confirmed, table: editor.submissionTable.map { $0.map(\.text) },
                        layout: editor.submissionLayout.points.map { p in [p?.x ?? 0, p?.y ?? 0] },
                        cues: RummyCuePreview(turnGlow: nil), name: "leftover-confirmed")
    }

    @Test("첫 등록 전: 랙 묶음 띠 + '랙 묶음 a + 판 b = N / 30' 꼬리표 · 정렬 뒤 뽑은 타일 빛남 · 규칙 창 '조작'")
    func rackCuesAndRulesOnNewWindow() throws {
        // 없으면: 새 창 배치(P)에서 랙 묶음 띠·꼬리표·뽑은 타일 빛이 받침대 밖으로 밀리거나 잘리는 결함이 초록이 된다(그림 확인용).
        var plan = iEditor(table: iTable, layout: iLayout, rack: iRack, initialDone: false)
        let group = plan.rack.filter { ["B12", "C12", "D12"].contains($0.face.text) }.map(\.id)
        let placed = plan.moveBlock(group, to: .newMeldAt(RummyPoint(x: 400, y: 220)))
        #expect(placed)
        let points = try #require(plan.initialPlanPoints)
        #expect(points.table == 36 && points.rack == 27)
        _ = try iRender(plan, table: iTable, layout: iLayout, initialDone: false, cues: RummyCuePreview(turnGlow: .steady),
                        name: "rack-plan")

        var sorted = iEditor(table: iTable, layout: iLayout, rack: iRack, initialDone: true)
        sorted.sortRack(.color)
        let fresh = try #require(sorted.rack.first { $0.face.text == "D9" }?.id)
        _ = try iRender(sorted, table: iTable, layout: iLayout,
                        cues: RummyCuePreview(turnGlow: .steady, freshTileIDs: [fresh], sortMode: .color), name: "fresh-draw")

        let rules = try iRender(sorted, table: iTable, layout: iLayout, cues: RummyCuePreview(turnGlow: .steady),
                                overlay: .rules, name: "rules")
        #expect(rules.pixelsWide == Int(RummyWindowLayout.contentSize.width * 2))
        // 규칙 창 한 곳에 판 조작(P)과 받침대(R)가 함께 — 받침대 손맛이 규칙 창에서 빠지면 빨강.
        let titles = RummyText.rules.map(\.title)
        #expect(titles.contains("조작") && titles.contains("받침대"))
        #expect(RummyText.rules.first { $0.title == "받침대" }.map { $0.detail.contains("끼워") && $0.detail.contains("밑줄") } == true)
    }
}
