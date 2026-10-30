import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// v0.3.69 아잉 큐브 **3판 판 화면(U3)** — 놓기 미리보기(붙을 끝 자석 · 끼울 자리 캐럿 · 새 묶음 점선) · 놓은 타일이 손을 놓은
// 자리에서 들어갈 자리로 미끄러지기 · 가운데를 빼도 남은 타일은 제자리.
//
// 사용자 원문(10-30): "7장 연속으로 있는데 중간꺼 뺐으면 양옆으로 3장씩이니까 이어진 상태 남아있어야지 … 가까이 배치하면 … 자동으로
// 붙게 … 붙을 수 있는 조합에다가 카드 추가해서 배치할땐 알맞는 위치로 자동으로 배치되게". 규칙은 편집기(K3)가 정하고, 여기서는
// 화면이 그 규칙을 **놓기 전에 보이고 놓은 뒤 튀지 않게** 그리는가를 잰다. 렌더는 `CHECK_SNAPSHOT_DIR/stills/rummy3-*.png`.
// 각 시험의 첫 줄 주석은 "없으면 어떤 결함이 초록으로 통과하는가" 다. 픽셀 단언은 **한 값만 바꾼 기준선**과 견준다.

// MARK: - 픽스처

private let v3Now = Date(timeIntervalSince1970: 1_800_000_000)
private let v3Me = ChessPlayerFace(name: "영식", avatarURL: nil, characterID: "shiba")
private let v3People: [(id: String, name: String, character: String)] = [
    ("00000000-0000-4000-8000-0000000000a1", "영식", "shiba"), ("00000000-0000-4000-8000-0000000000b2", "민수", "fox"),
]

/// 7장 런(가운데 빼기·끝에 붙이기) · 그룹 · 4장 런(위에 놓아 끼우기).
private let v3Table: [[String]] = [["C3", "C4", "C5", "C6", "C7", "C8", "C9"], ["A7", "B7", "D7"], ["A4", "A5", "A6", "A7"]]
private let v3Layout: [[Int]] = [[120, 120], [560, 120], [160, 340]]
private let v3Rack: [String] = ["C10", "A3", "B2", "D9", "J", "B11", "D4"]

private func v3Faces(_ texts: [String]) -> [RummyFace] { texts.compactMap(RummyFace.init(text:)) }

private func v3Match() throws -> RummyMatchState {
    let nowMs = v3Now.timeIntervalSince1970 * 1000
    let seats: [[String: Any]] = v3People.enumerated().map { index, person in
        ["seat_no": index, "user_id": person.id, "display_name": person.name, "avatar_url": NSNull(),
         "character": person.character, "state": "playing", "rack_count": [7, 9][index], "initial_done": true,
         "timeout_streak": 0]
    }
    let state: [String: Any] = [
        "id": "7e7e0000-0000-4000-8000-000000000369", "status": "active", "host_id": v3People[0].id, "stake": 5,
        "is_public": false, "seat_count": 2, "max_seats": 4, "server_now_ms": nowMs, "seq": 30, "seats": seats,
        "my_seat_no": 0, "my_rack": v3Rack, "my_initial_done": true, "table": v3Table, "table_layout": v3Layout,
        "pool_count": 40, "turn_seat_no": 0, "turn_started_ms": nowMs - 12_000, "turn_deadline_ms": nowMs + 48_000,
        "grace_ms": 2000, "consecutive_passes": 0, "last_event": ["kind": "timeout_penalty", "seat_no": 1, "count": 1,
                                                                    "at_ms": nowMs - 13_000],
    ]
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(RummyMatchState.self, from: JSONSerialization.data(withJSONObject: state))
}

private func v3Editor() -> RummyTurnEditor {
    RummyTurnEditor(table: v3Table.map(v3Faces), rack: v3Faces(v3Rack), initialDone: true,
                    tableLayout: RummyLayout(v3Layout.map { RummyPoint(x: $0[0], y: $0[1]) }))
}

private func v3ID(_ editor: RummyTurnEditor, _ text: String, onTable: Bool) -> Int {
    (onTable ? editor.melds.flatMap { $0 } : editor.rack).first { $0.face.text == text }!.id
}

// MARK: - 렌더 도우미

private enum V3Error: Error { case render }

@MainActor
private func v3Bitmap(_ view: some View) throws -> NSBitmapImageRep {
    let renderer = ImageRenderer(content: view.fixedSize())
    renderer.scale = 2
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff) else { throw V3Error.render }
    return bitmap
}

/// 창 화면 한 장(scale 2). 첫 두 장은 다르게 나온다(실측) — 굳힌 뒤 둘째 장을 쓴다.
@MainActor
private func v3Render(_ editor: RummyTurnEditor, drag: RummyPreviewDrag? = nil, name: String? = nil) throws -> NSBitmapImageRep {
    let panel = RummyPanel(store: RummyStore(), me: { v3Me }, clipsOverflowInsteadOfScroll: true, previewMatch: try v3Match(),
                           previewEditor: editor, previewNow: v3Now, previewMyUserID: UUID(uuidString: v3People[0].id),
                           previewDrag: drag)
        .environment(\.colorScheme, .dark)
        .environment(\.rummyBoardZoomPreview, false)   // 0.3.70 기본은 [판 확대] — 이 시험들은 전체 보기 좌표로 잰다
    _ = try v3Bitmap(panel)
    let bitmap = try v3Bitmap(panel)
    if let name { MiniGameSnapshots.save(bitmap, name: "rummy3-\(name).png", sub: "stills") }
    return bitmap
}

private func v3Count(_ bitmap: NSBitmapImageRep, near target: (Int, Int, Int), tolerance: Int, in rect: CGRect,
                     scale: CGFloat = 2) -> Int {
    guard let data = bitmap.bitmapData, bitmap.samplesPerPixel >= 3 else { return -1 }
    let bpr = bitmap.bytesPerRow, spp = bitmap.samplesPerPixel
    let x0 = max(0, Int(rect.minX * scale)), x1 = min(bitmap.pixelsWide - 1, Int(rect.maxX * scale))
    let y0 = max(0, Int(rect.minY * scale)), y1 = min(bitmap.pixelsHigh - 1, Int(rect.maxY * scale))
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

/// 두 장이 `r` 안에서 다른 픽셀 비율.
private func v3Diff(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep, in r: CGRect, threshold: Int = 24) -> Double {
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

private let v3Working = (89, 224, 161)

private typealias W = RummyWindowLayout
private let v3L = RummyMatchLayout.standard
private let v3Canvas = RummyCanvasTransform.fit(viewport: v3L.table.size)

/// 판 화면 좌표 → 창 좌표.
private func v3Win(_ rect: CGRect) -> CGRect {
    rect.offsetBy(dx: W.matchBodyOrigin.x, dy: W.matchBodyOrigin.y)   // 0.3.70: 판 화면은 머리글 없음
}

/// 논리 판 사각형 → 창 좌표.
private func v3Board(_ r: RummyRect) -> CGRect {
    v3Win(v3Canvas.rect(r).offsetBy(dx: v3L.table.minX, dy: v3L.table.minY))
}

/// 논리 판 점 → 판 화면 좌표(끌기 주입구가 받는 좌표).
private func v3Pointer(_ logical: CGPoint) -> CGPoint {
    let s = v3Canvas.toScreen(logical)
    return CGPoint(x: s.x + v3L.table.minX, y: s.y + v3L.table.minY)
}

/// 논리 x 의 세로 띠(묶음 높이 + 위아래 여유) — 창 좌표.
private func v3Band(x: Int, y: Int, half: CGFloat = 3) -> CGRect {
    let r = v3Board(RummyRect(x: x, y: y, width: 0, height: RummyTableLayout.tileHeight))
    return CGRect(x: r.minX - half, y: r.minY - 4, width: half * 2, height: r.height + 8)
}

/// 타일 한 장 안쪽(테두리·상자 선을 빼고 면만) — 창 좌표.
private func v3TileInside(set frame: RummyRect, slot: Int) -> CGRect {
    v3Board(RummyRect(x: frame.x + slot * RummyTableLayout.tileWidth, y: frame.y, width: RummyTableLayout.tileWidth,
                      height: RummyTableLayout.tileHeight)).insetBy(dx: 4, dy: 5)
}

// MARK: - 순수: 편집기 답 → 그릴 값

@Suite("아잉 큐브 3판 놓기 미리보기 값(순수)")
struct V0369RummyV3PreviewValueTests {
    @Test("붙기 = 대상 끝 자석 + 블록 칸 · 끼우기 = 정렬된 자리 캐럿(놓은 슬롯이 아니라) · 빈 곳 = 점선 · 받침대 = 없음")
    func plansMapToPictures() throws {
        // 없으면: 끝 가까이 끌어도 어디 붙을지 안 보이거나, 캐럿이 놓은 슬롯에 서서 실제로 들어갈 자리(맨 앞)와 어긋난다.
        let editor = v3Editor()
        let ids = editor.melds.map { $0.map(\.id) }
        let frames = editor.tableLayout.frames
        let c10 = v3ID(editor, "C10", onTable: false)
        let attach = RummyBoardPreview.make(editor.previewDrop([c10], to: .newMeldAt(RummyPoint(x: 414, y: 120))),
                                            blockCount: 1, meldTileIDs: ids, frames: frames, dragged: [c10])
        #expect(attach == .attach(set: 0, side: .right, slots: RummyRect(x: 400, y: 120, width: 40, height: 56),
                                  landing: RummyRect(x: 120, y: 120, width: 320, height: 56), valid: true))

        let a3 = v3ID(editor, "A3", onTable: false)
        let insert = RummyBoardPreview.make(editor.previewDrop([a3], to: .meld(2, index: 2)),
                                            blockCount: 1, meldTileIDs: ids, frames: frames, dragged: [a3])
        #expect(insert == .insert(set: 2, caretX: 160, landing: RummyRect(x: 120, y: 340, width: 200, height: 56),
                                  valid: true), "A3 를 A5·A6 사이에 놓아도 맨 앞에 끼워진다 — 캐럿도 맨 앞")

        let ghost = RummyBoardPreview.make(editor.previewDrop([a3], to: .newMeldAt(RummyPoint(x: 700, y: 500))),
                                           blockCount: 1, meldTileIDs: ids, frames: frames, dragged: [a3])
        guard case .ghost(let rect)? = ghost else { Issue.record("빈 곳인데 점선이 아니다: \(String(describing: ghost))"); return }
        #expect(rect.width == 40 && rect.height == 56)

        #expect(RummyBoardPreview.make(editor.previewDrop([a3], to: .rackSlot(RummyRackSlot(row: 0, halfCol: 0))),
                                       blockCount: 1, meldTileIDs: ids, frames: frames, dragged: [a3]) == nil)
        let tableTile = v3ID(editor, "C5", onTable: true)
        #expect(RummyBoardPreview.make(editor.previewDrop([tableTile], to: .rackSlot(RummyRackSlot(row: 0, halfCol: 0))),
                                       blockCount: 1, meldTileIDs: ids, frames: frames, dragged: [tableTile]) == nil,
                "판 타일을 받침대로(R-14) — 거절이면 미리보기도 없다")
    }

    @Test("캐럿은 손에 든 타일(제자리에 흐리게 남은 것)을 건너뛴 자리에 선다")
    func caretSkipsDraggedTiles() {
        // 없으면: 같은 묶음 안에서 옮길 때 캐럿이 흐린 빈칸 쪽으로 한 칸 어긋난다.
        let landing = RummyDropPreview.Landing(set: 0, faces: [], frame: RummyRect(x: 0, y: 0, width: 160, height: 56),
                                               blockStart: 1, valid: false)
        let preview = RummyDropPreview(plan: .insert(set: 0, index: 1), landing: landing)
        let frames = [RummyRect(x: 100, y: 40, width: 160, height: 56)]
        let skipped = RummyBoardPreview.make(preview, blockCount: 1, meldTileIDs: [[11, 12, 13, 14]], frames: frames,
                                             dragged: [12])
        let plain = RummyBoardPreview.make(preview, blockCount: 1, meldTileIDs: [[11, 12, 13, 14]], frames: frames,
                                           dragged: [99])
        #expect(skipped == .insert(set: 0, caretX: 180, landing: landing.frame, valid: false))
        #expect(plain == .insert(set: 0, caretX: 140, landing: landing.frame, valid: false))
        let end = RummyBoardPreview.make(RummyDropPreview(plan: .insert(set: 0, index: 3), landing: landing), blockCount: 1,
                                         meldTileIDs: [[11, 12, 13, 14]], frames: frames, dragged: [12])
        #expect(end == .insert(set: 0, caretX: 260, landing: landing.frame, valid: false), "맨 끝이면 마지막 타일 오른쪽")
    }
}

// MARK: - 렌더

@MainActor
@Suite("아잉 큐브 3판 판 화면 렌더", .serialized)
struct V0369RummyV3MatchRenderTests {
    @Test("7장 런 가운데를 빼면 — 양옆 3장씩이 **화면에서 그대로** 남는다 · 기준선 = 뺀 자리는 바뀐다")
    func middleRemovalKeepsBothSides() throws {
        // 없으면: 편집기는 3+3 으로 나눴는데 화면이 남은 타일을 왼쪽으로 당겨 그리거나(묶음 HStack 재배치) 상자를 하나로 그린다.
        let before = v3Editor()
        var after = before
        let c6 = v3ID(after, "C6", onTable: true)
        let moved1 = after.moveBlock([c6], to: .newMeldAt(RummyPoint(x: 600, y: 420)))
        #expect(moved1)
        #expect(after.melds.map { $0.map(\.face.text) }.prefix(3) == [["C3", "C4", "C5"], ["C7", "C8", "C9"], ["A7", "B7", "D7"]])
        let still = try v3Render(before, name: "split-before")
        let split = try v3Render(after, name: "split-middle")
        let run = RummyRect(x: 120, y: 120, width: 280, height: 56)
        for slot in [0, 1, 2, 4, 5, 6] {
            let d = v3Diff(still, split, in: v3TileInside(set: run, slot: slot))
            #expect(d < 0.03, "남은 \(slot)번 타일이 움직였다(다른 픽셀 \(d))")
        }
        let gone = v3Diff(still, split, in: v3TileInside(set: run, slot: 3))
        #expect(gone > 0.3, "기준선: 뺀 가운데 자리는 바뀌어야 한다(\(gone))")
    }

    @Test("끝 가까이 끄는 중 — 붙을 끝에 자석(초록 = 붙으면 맞는 세트) · 기준선 = 같은 타일을 빈 곳으로")
    func magnetAtAttachEnd() throws {
        // 없으면: 끝 24 안으로 끌어 놓으면 붙는데, 놓기 전엔 아무 표시가 없어 "붙을까?"를 놓아 봐야 안다.
        let editor = v3Editor()
        let c10 = v3ID(editor, "C10", onTable: false)
        let near = try v3Render(editor, drag: RummyPreviewDrag(tileID: c10, point: v3Pointer(CGPoint(x: 434, y: 148))),
                                name: "drag-magnet")
        let far = try v3Render(editor, drag: RummyPreviewDrag(tileID: c10, point: v3Pointer(CGPoint(x: 820, y: 560))))
        let seam = v3Band(x: 400, y: 120, half: 4)
        let green = v3Count(near, near: v3Working, tolerance: 45, in: seam)
        let baseline = v3Count(far, near: v3Working, tolerance: 45, in: seam)
        #expect(green > baseline + 60, "붙을 끝(오른끝)에 자석 막대가 없다(\(baseline) → \(green))")
        // 자석 배지는 끝 위쪽에 — 손에 든 타일에 가려지지 않는 자리.
        let top = v3Board(RummyRect(x: 400, y: 120, width: 0, height: 0))
        let badge = CGRect(x: top.minX - 12, y: top.minY - 30, width: 24, height: 24)
        #expect(v3Count(near, near: v3Working, tolerance: 45, in: badge) > v3Count(far, near: v3Working, tolerance: 45, in: badge) + 40,
                "자석 배지가 없다")
    }

    @Test("3판 검증 — 첫 등록 전 판 묶음(A4-A7) 위로 A3 을 끌면 세트는 맞아도 초록 체크가 없다(낼 수 없다) · 기준선 = 등록 뒤 같은 끌기")
    func noGreenCheckBeforeInitialOnTableSet() throws {
        // 없으면: 첫 등록 전 판 묶음에 꽂는 미리보기가 초록 체크(맞음)를 띄워, 놓고 [완료]를 눌러야 '판 묶음을 건드렸다'로 막히는 결함이 초록이 된다.
        func render(initialDone: Bool) throws -> NSBitmapImageRep {
            let editor = RummyTurnEditor(table: v3Table.map(v3Faces), rack: v3Faces(v3Rack), initialDone: initialDone,
                                         tableLayout: RummyLayout(v3Layout.map { RummyPoint(x: $0[0], y: $0[1]) }))
            let a3 = v3ID(editor, "A3", onTable: false)
            return try v3Render(editor, drag: RummyPreviewDrag(tileID: a3, point: v3Pointer(CGPoint(x: 236, y: 368))))
        }
        let after = try render(initialDone: true)
        let before = try render(initialDone: false)
        // 놓은 뒤 윤곽 120…320 · y 340 — 체크 배지는 오른쪽 위 모서리.
        let corner = v3Board(RummyRect(x: 320, y: 340, width: 0, height: 0))
        let badge = CGRect(x: corner.minX - 6, y: corner.minY - 20, width: 26, height: 26)
        let green = v3Count(after, near: v3Working, tolerance: 45, in: badge)
        let gated = v3Count(before, near: v3Working, tolerance: 45, in: badge)
        #expect(green > 40, "기준선(등록 뒤)에 체크 배지가 없다 — 재는 자리가 틀렸다(\(green))")
        #expect(gated < green / 4, "첫 등록 전인데 판 묶음에 꽂는 미리보기가 초록 체크다(\(green) → \(gated))")
    }

    @Test("묶음 위로 끄는 중 — 캐럿은 놓은 슬롯(A5|A6)이 아니라 들어갈 자리(맨 앞)에 · 놓은 뒤 윤곽은 왼쪽으로 늘어난다")
    func caretAtSortedSlot() throws {
        // 없으면: 옛 미리보기처럼 손 밑 슬롯에 캐럿이 서서, 놓으면 다른 자리(맨 앞)로 들어가는 것이 "튄다"로 보인다.
        let editor = v3Editor()
        let a3 = v3ID(editor, "A3", onTable: false)
        // A4·A5·A6·A7 (x 160…320) 의 A5|A6 경계 = 240.
        let over = try v3Render(editor, drag: RummyPreviewDrag(tileID: a3, point: v3Pointer(CGPoint(x: 236, y: 368))),
                                name: "drag-caret")
        let still = try v3Render(editor)
        let front = v3Band(x: 160, y: 340, half: 3)
        let dropSlot = v3Band(x: 240, y: 340, half: 3)
        let atFront = v3Count(over, near: v3Working, tolerance: 45, in: front)
        #expect(atFront > v3Count(still, near: v3Working, tolerance: 45, in: front) + 40, "맨 앞 캐럿이 없다(\(atFront))")
        // 손에 든 타일이 놓은 슬롯을 덮는다 — 그 위아래로 삐져나온 캐럿 머리(띠 위 끝)로 잰다.
        let slotHead = CGRect(x: dropSlot.minX, y: dropSlot.minY - 6, width: dropSlot.width, height: 8)
        let frontHead = CGRect(x: front.minX, y: front.minY - 6, width: front.width, height: 8)
        #expect(v3Count(over, near: v3Working, tolerance: 45, in: frontHead)
                > v3Count(over, near: v3Working, tolerance: 45, in: slotHead) + 10, "캐럿이 놓은 슬롯 쪽에 섰다")
        // 놓은 뒤 윤곽(120…320)이 지금 묶음 왼쪽(120…160)까지 — 점선 띠.
        let grown = v3Board(RummyRect(x: 120, y: 340, width: 40, height: 56))
        let lip = CGRect(x: grown.minX - 6, y: grown.minY - 8, width: grown.width, height: 6)
        #expect(v3Count(over, near: v3Working, tolerance: 45, in: lip) > v3Count(still, near: v3Working, tolerance: 45, in: lip) + 8,
                "놓은 뒤 늘어날 자리 윤곽이 없다")
    }

    @Test("붙은 직후 · 끼운 직후 — 한 묶음(8장 런 · 5장 런)이고 빨간 테두리가 없다 · 기존 타일은 제자리")
    func attachedAndInserted() throws {
        // 없으면: 놓은 타일이 따로 새 묶음(빨간 1장)으로 남거나, 앞에 끼울 때 기존 4장이 오른쪽으로 밀려 그려진다.
        let before = v3Editor()
        var editor = before
        let moved2 = editor.moveBlock([v3ID(editor, "C10", onTable: false)], to: .newMeldAt(RummyPoint(x: 414, y: 120)))
        #expect(moved2)
        let moved3 = editor.moveBlock([v3ID(editor, "A3", onTable: false)], to: .meld(2, index: 2))
        #expect(moved3)
        #expect(editor.melds.map { $0.map(\.face.text) } == [["C3", "C4", "C5", "C6", "C7", "C8", "C9", "C10"],
                                                             ["A7", "B7", "D7"], ["A3", "A4", "A5", "A6", "A7"]])
        #expect(editor.tableLayout.frame(of: 2) == RummyRect(x: 120, y: 340, width: 200, height: 56))
        let still = try v3Render(before)
        let landed = try v3Render(editor, name: "attached")
        let a4 = RummyRect(x: 160, y: 340, width: 160, height: 56)
        for slot in 0..<4 {
            #expect(v3Diff(still, landed, in: v3TileInside(set: a4, slot: slot)) < 0.03, "끼운 뒤 기존 \(slot)번 타일이 밀렸다")
        }
        // 상자 테두리 띠(타일 바깥 1~5pt)만 — A 잉크(빨강)가 무효색과 가까워 타일 면은 재지 않는다. 기준선 = 붙기 전 1장 새 묶음.
        let red = RummyTilePalette.invalid
        func ring(_ bitmap: NSBitmapImageRep, _ r: RummyRect) -> Int {
            let outer = v3Board(r).insetBy(dx: -5, dy: -5)
            let bands = [CGRect(x: outer.minX, y: outer.minY, width: outer.width, height: 4),
                         CGRect(x: outer.minX, y: outer.maxY - 4, width: outer.width, height: 4)]
            return bands.reduce(0) { $0 + v3Count(bitmap, near: (red.r, red.g, red.b), tolerance: 40, in: $1) }
        }
        var lone = before
        let moved4 = lone.moveBlock([v3ID(lone, "C10", onTable: false)], to: .newMeldAt(RummyPoint(x: 700, y: 500)))
        #expect(moved4)
        let loneFrame = try #require(lone.tableLayout.frame(of: 3))
        let alone = try v3Render(lone)
        #expect(ring(alone, loneFrame) > 40, "기준선: 1장 새 묶음은 빨간 테두리여야 한다(\(ring(alone, loneFrame)))")
        #expect(ring(landed, RummyRect(x: 120, y: 120, width: 320, height: 56)) < 20, "붙은 런이 무효로 칠해졌다")
    }
}

// MARK: - 모션: 놓은 자리에서 출발

@MainActor
@Suite("아잉 큐브 3판 놓은 타일 모션")
struct V0369RummyV3ArrivalTests {
    private func canvas(arrivals: [Int: CGPoint], reduceMotion: Bool) -> some View {
        let size = CGSize(width: 500, height: 320)
        let faces = v3Faces(["C3", "C4", "C5"])
        let meld = RummyBoardMeld(id: "e1", tiles: faces.enumerated().map { RummyBoardTile(id: $0 + 1, face: $1, highlighted: false) },
                                  frame: RummyRect(x: 560, y: 400, width: 120, height: 56), invalid: false)
        return RummyTableCanvasView(
            melds: [meld], transform: .fit(viewport: size), size: size, editable: false, draggingTileIDs: [],
            liftedTileIDs: [], movingSet: nil, preview: nil, arrivals: arrivals, recentTileIDs: [1],
            reduceMotion: reduceMotion, onTileDrag: { _, _ in }, onTileDragEnd: { _, _ in }, onHandleDrag: { _, _ in },
            onHandleDragEnd: { _, _ in })
            .environment(\.colorScheme, .dark)
    }

    @Test("출발 장면은 손을 놓은 자리에 그린다(다음 장면부터 제자리로 미끄러짐) · 동작 줄이기면 바로 제자리")
    func arrivalStartsAtDropPoint() throws {
        // 없으면: 놓는 순간 타일이 떠 있던 자리에서 사라지고 들어갈 자리에 '뿅' 나타난다(맞는 자리로 옮겨진 걸 못 본다).
        let start = CGPoint(x: 120, y: 100)
        let arriving = try v3Bitmap(canvas(arrivals: [1: start], reduceMotion: false))
        _ = try v3Bitmap(canvas(arrivals: [:], reduceMotion: false))
        let settled = try v3Bitmap(canvas(arrivals: [:], reduceMotion: false))
        let reduced = try v3Bitmap(canvas(arrivals: [1: start], reduceMotion: true))
        MiniGameSnapshots.save(arriving, name: "rummy3-arrival-start.png", sub: "stills")
        let transform = RummyCanvasTransform.fit(viewport: CGSize(width: 500, height: 320))
        let from = transform.rect(RummyRect(x: 120, y: 100, width: 40, height: 56)).insetBy(dx: 3, dy: 3)
        let to = transform.rect(RummyRect(x: 560, y: 400, width: 40, height: 56)).insetBy(dx: 3, dy: 3)
        #expect(v3Diff(arriving, settled, in: from) > 0.3, "출발 자리에 타일이 없다")
        #expect(v3Diff(arriving, settled, in: to) > 0.3, "출발 장면인데 이미 제자리에 있다")
        let whole = CGRect(x: 0, y: 0, width: 500, height: 320)
        #expect(v3Diff(reduced, settled, in: whole) < 0.002, "동작 줄이기인데 출발 자리에서 그렸다")
    }
}
