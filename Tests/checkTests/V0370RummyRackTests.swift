import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// 아잉 큐브 0.3.70 레인 R — 받침대 끼워 넣기 · 랙 묶음 표시 · 정렬 뒤 뽑은 타일 · 내 차례 표시(감사 #2 #3 #10 #7).
// 규칙 단위 시험 + 판 화면 렌더(오프스크린, `CHECK_SNAPSHOT_DIR` 아래 `v370-rack/` 에 굽는다).

private func r70Faces(_ texts: String) -> [RummyFace] {
    texts.split(separator: " ").compactMap { RummyFace(text: String($0)) }
}

/// 받침대 자리를 그대로 준 편집기. `entries` = "면@줄,반칸" 목록.
private func r70Editor(_ entries: [(String, Int, Int)], table: [[String]] = [], initialDone: Bool = true) -> RummyTurnEditor {
    let faces = entries.compactMap { RummyFace(text: $0.0) }
    let rackEntries = entries.compactMap { entry in
        RummyFace(text: entry.0).map { RummyRackEntry(face: $0, slot: RummyRackSlot(row: entry.1, halfCol: entry.2)) }
    }
    return RummyTurnEditor(table: table.map { $0.compactMap(RummyFace.init(text:)) }, rack: faces,
                           initialDone: initialDone, rackEntries: rackEntries)
}

private func r70ID(_ editor: RummyTurnEditor, _ face: String, nth: Int = 0) -> Int {
    editor.rack.filter { $0.face.text == face }[nth].id
}

/// 받침대 모양 글자("면@줄,반칸" 화면 순).
private func r70Shape(_ editor: RummyTurnEditor) -> [String] {
    editor.rack.compactMap { tile in
        editor.rackLayout.slot(of: tile.id).map { "\(tile.face.text)@\($0.row),\($0.halfCol)" }
    }
}

private func r70Invariants(_ editor: RummyTurnEditor, count: Int) -> [String] {
    var bad: [String] = []
    let layout = editor.rackLayout
    if editor.rack.count != count || layout.slots.count != count { bad.append("타일 수 \(layout.slots.count) ≠ \(count)") }
    if editor.rack.map(\.id) != layout.readingOrder { bad.append("화면 순서 ≠ 자리") }
    for (id, slot) in layout.slots {
        if slot.halfCol < 0 || slot.halfCol + RummyRackLayout.tileSpan > RummyRackLayout.halfColumnsPerRow || slot.row < 0 {
            bad.append("줄 밖 \(id) \(slot)")
        }
        for (other, o) in layout.slots where other > id && o.row == slot.row && abs(o.halfCol - slot.halfCol) < RummyRackLayout.tileSpan {
            bad.append("겹침 \(id)·\(other)")
        }
    }
    return bad
}

@Suite("0.3.70 아잉 큐브 받침대 — 끼워 넣기 · 랙 묶음 · 첫 등록 합")
struct V0370RummyRackTests {
    @Test("끼워 넣기: 붙은 타일 사이·타일 위에 놓으면 오른쪽을 밀어 끼운다 · 빈칸이면 그 자리 그대로")
    func insertsBetweenAttachedTiles() {
        // 없으면: 랙의 5 7 사이에 6 을 놓아도 가장 가까운 빈칸으로 튀어 7 을 먼저 옮겨야 하는 결함(감사 #2)이 초록이 된다.
        let base = r70Editor([("A5", 0, 0), ("A7", 0, 2), ("B1", 0, 4), ("A6", 1, 0)])
        var between = base
        let moved1 = between.moveBlock([r70ID(base, "A6")], to: .rackSlot(RummyRackSlot(row: 0, halfCol: 1)))
        #expect(moved1)
        #expect(r70Shape(between) == ["A5@0,0", "A6@0,2", "A7@0,4", "B1@0,6"])
        // 7 위에 놓아도(왼쪽 5 와 닿는다) 5 와 7 사이.
        var onto = base
        let moved2 = onto.moveBlock([r70ID(base, "A6")], to: .rackSlot(RummyRackSlot(row: 0, halfCol: 2)))
        #expect(moved2)
        #expect(r70Shape(onto) == r70Shape(between))
        // 맨 앞 타일 위 = 그 앞.
        var front = base
        let moved3 = front.moveBlock([r70ID(base, "A6")], to: .rackSlot(RummyRackSlot(row: 0, halfCol: 0)))
        #expect(moved3)
        #expect(r70Shape(front) == ["A6@0,0", "A5@0,2", "A7@0,4", "B1@0,6"])
        // 빈칸이면 옛 규칙 그대로(바로 그 자리).
        var free = base
        let moved4 = free.moveBlock([r70ID(base, "A6")], to: .rackSlot(RummyRackSlot(row: 0, halfCol: 11)))
        #expect(moved4)
        #expect(r70Shape(free) == ["A5@0,0", "A7@0,2", "B1@0,4", "A6@0,11"])
        // 여러 장 한 덩어리도 같은 규칙(순서 그대로).
        var block = r70Editor([("A5", 0, 0), ("A8", 0, 2), ("A6", 1, 0), ("A7", 1, 2)])
        let moved5 = block.moveBlock([r70ID(block, "A6"), r70ID(block, "A7")], to: .rackSlot(RummyRackSlot(row: 0, halfCol: 1)))
        #expect(moved5)
        #expect(r70Shape(block) == ["A5@0,0", "A6@0,2", "A7@0,4", "A8@0,6"])
    }

    @Test("끼워 넣기: 미는 타일은 필요한 만큼만 — 빈칸은 반 칸까지 줄되 다른 덩어리끼리 붙지 않는다 · 왼쪽·오른쪽 덩어리 고르기")
    func pushKeepsChunksApart() {
        // 없으면: 끼운 덩어리가 옆 덩어리와 붙어 한 덩어리가 되거나(랙 묶음 점수가 사라진다), 밀 필요 없는 먼 타일까지 움직이는 결함이 초록이 된다.
        var editor = r70Editor([("A1", 0, 0), ("A2", 0, 2), ("A3", 0, 4), ("B5", 0, 9), ("C7", 0, 13), ("D1", 1, 0), ("D2", 1, 2)])
        let moved6 = editor.moveBlock([r70ID(editor, "D1")], to: .rackSlot(RummyRackSlot(row: 0, halfCol: 2)))
        #expect(moved6)
        #expect(r70Shape(editor).prefix(6) == ["A1@0,0", "D1@0,2", "A2@0,4", "A3@0,6", "B5@0,9", "C7@0,13"])
        let moved7 = editor.moveBlock([r70ID(editor, "D2")], to: .rackSlot(RummyRackSlot(row: 0, halfCol: 2)))
        #expect(moved7)
        #expect(r70Shape(editor) == ["A1@0,0", "D2@0,2", "D1@0,4", "A2@0,6", "A3@0,8", "B5@0,11", "C7@0,14"])

        // A1-A3 | 반 칸 | B9-B11: A3 끝에 닿게 놓으면 왼쪽 덩어리에 붙고 오른쪽은 반 칸 떨어진 채 밀린다.
        let two = r70Editor([("A1", 0, 0), ("A2", 0, 2), ("A3", 0, 4), ("B9", 0, 7), ("B10", 0, 9), ("B11", 0, 11),
                             ("A4", 1, 0), ("B8", 1, 4)])
        var left = two
        let moved8 = left.moveBlock([r70ID(two, "A4")], to: .rackSlot(RummyRackSlot(row: 0, halfCol: 6)))
        #expect(moved8)
        #expect(r70Shape(left).prefix(7) == ["A1@0,0", "A2@0,2", "A3@0,4", "A4@0,6", "B9@0,9", "B10@0,11", "B11@0,13"])
        #expect(left.rackMelds.map(\.points) == [10, 30])
        // 오른쪽 덩어리 첫 타일 자리에 놓으면 그 앞에 붙는다(왼쪽과는 반 칸).
        var right = two
        let moved9 = right.moveBlock([r70ID(two, "B8")], to: .rackSlot(RummyRackSlot(row: 0, halfCol: 7)))
        #expect(moved9)
        #expect(r70Shape(right).prefix(7) == ["A1@0,0", "A2@0,2", "A3@0,4", "B8@0,7", "B9@0,9", "B10@0,11", "B11@0,13"])
        #expect(right.rackMelds.map(\.points) == [6, 38])
    }

    @Test("끼워 넣기: 줄 끝을 넘치면 넘친 덩어리를 다음 줄 맨 앞으로 흘린다(한 줄보다 길면 넘친 타일부터) · 다음 줄은 반 칸 떼고 밀린다")
    func overflowFlowsToNextRow() {
        // 없으면: 꽉 찬 줄에 끼우면 타일이 겹치거나 줄 밖으로 나가거나, 덩어리가 두 줄로 찢기는 결함이 초록이 된다.
        var entries: [(String, Int, Int)] = [("C1", 0, 0), ("C2", 0, 2)]
        for n in 1...13 { entries.append(("A\(n)", 0, 6 + (n - 1) * 2)) }   // 6..30, 줄 끝까지
        entries += [("D9", 1, 0), ("B5", 1, 6)]
        var editor = r70Editor(entries)
        let moved10 = editor.moveBlock([r70ID(editor, "B5")], to: .rackSlot(RummyRackSlot(row: 0, halfCol: 10)))
        #expect(moved10)
        let shape = r70Shape(editor)
        #expect(shape.prefix(2) == ["C1@0,0", "C2@0,2"])
        // A1 A2 B5 A3 … A13 (14장 = 28 반 칸)이 통째로 다음 줄 맨 앞, D9 는 반 칸 떼고 29.
        #expect(shape[2] == "A1@1,0" && shape[3] == "A2@1,2" && shape[4] == "B5@1,4" && shape[5] == "A3@1,6")
        #expect(shape.last == "D9@1,29")
        #expect(r70Invariants(editor, count: 17).isEmpty)

        // 한 줄을 꽉 채운 16장 덩어리에 끼우면 넘친 마지막 한 장만 다음 줄로(덩어리가 한 줄보다 길다).
        var full: [(String, Int, Int)] = []
        let colors = ["A", "B"]
        for i in 0..<16 { full.append(("\(colors[i / 8])\(i % 8 + 1)", 0, i * 2)) }
        full += [("D9", 1, 0), ("C5", 1, 8)]
        var packed = r70Editor(full)
        let moved11 = packed.moveBlock([r70ID(packed, "C5")], to: .rackSlot(RummyRackSlot(row: 0, halfCol: 4)))
        #expect(moved11)
        let packedShape = r70Shape(packed)
        #expect(packedShape[2] == "C5@0,4" && packedShape[15] == "B7@0,30")
        #expect(packedShape[16] == "B8@1,0" && packedShape[17] == "D9@1,3")
        #expect(r70Invariants(packed, count: 18).isEmpty)
    }

    @Test("끼워 넣기 퍼즈: 무작위 놓기 3,000번 — 잃음·겹침·줄 밖 없음 · 옮기지 않은 타일 순서 그대로 · 미리보기 = 실제")
    func insertFuzz() {
        // 없으면: 드문 자리(줄 끝 · 3줄째 · 덩어리 경계)에서 타일이 사라지거나 포개지는 결함이 초록이 된다.
        var seed: UInt64 = 0x7037_0000
        func next(_ upper: Int) -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int((seed >> 33) % UInt64(upper))
        }
        let faces = ["A1", "A2", "A3", "A4", "A5", "B1", "B2", "B3", "B4", "C7", "C8", "C9", "D10", "D11", "D12", "J",
                     "A9", "B9", "C9", "D9", "A13", "B13", "C13", "D1", "D2", "D3", "A6", "B6"]
        var bad: [String] = []
        for round in 0..<60 {
            let count = 8 + next(faces.count - 8)
            var entries: [(String, Int, Int)] = []
            for i in 0..<count { entries.append((faces[i], 0, 0)) }
            var editor = RummyTurnEditor(table: [], rack: entries.compactMap { RummyFace(text: $0.0) }, initialDone: true)
            for step in 0..<50 {
                let ids = editor.rack.map(\.id)
                let start = next(ids.count)
                let length = min(1 + next(3), ids.count - start)
                let moving = Array(ids[start..<(start + length)])
                let target = RummyRackSlot(row: next(3), halfCol: next(31))
                let preview = editor.rackLayoutAfterDrop(moving, at: target)
                let others = editor.rack.map(\.id).filter { !moving.contains($0) }
                let accepted = editor.moveBlock(moving, to: .rackSlot(target))
                if !accepted { bad.append("거절 \(round)/\(step)") }
                if preview != editor.rackLayout { bad.append("미리보기 ≠ 실제 \(round)/\(step)") }
                if editor.rack.map(\.id).filter({ !moving.contains($0) }) != others { bad.append("순서 바뀜 \(round)/\(step)") }
                bad += r70Invariants(editor, count: count).map { "\($0) \(round)/\(step)" }
                if bad.count > 5 { break }
            }
        }
        #expect(bad.isEmpty, "\(bad.prefix(5))")
    }

    @Test("랙 묶음: 딱 붙인 덩어리가 그대로 맞는 묶음(3장 이상)일 때만 · 빈칸에서 끊김 · 덩어리를 쪼개 보지 않는다(힌트 아님)")
    func rackMeldsCountOnlyWhatIMade() {
        // 없으면: 붙여 둔 묶음이 맞는지 판에 꺼내 봐야 알거나(감사 #3), 반대로 화면이 정답 묶음을 찾아 주는 힌트가 되는 결함이 초록이 된다.
        let editor = r70Editor([
            ("A7", 0, 0), ("A8", 0, 2), ("A9", 0, 4),                 // 런 24
            ("B10", 0, 7), ("C10", 0, 9), ("D10", 0, 11),             // 그룹 30
            ("B2", 0, 14), ("B4", 0, 16),                             // 2장 — 아님
            ("J", 0, 19), ("D5", 0, 21), ("D6", 0, 23),               // 조커 런 — 점수는 서버 R-08 그대로(5-6-7 = 18)
            ("C1", 1, 0), ("C2", 1, 2), ("C3", 1, 4), ("C9", 1, 6),   // 이어 붙였지만 덩어리 전체는 아님 — 쪼개 보지 않는다
            ("A11", 1, 10), ("A12", 1, 13), ("A13", 1, 15),           // 반 칸 끊김 — 아님
        ])
        #expect(editor.rackMelds.map(\.points) == [24, 30, 18])
        #expect(editor.rackMelds.map(\.kind) == [.run, .group, .run])
        #expect(editor.rackMeldPoints == 72)
        #expect(editor.rackMelds[0].tileIDs == [r70ID(editor, "A7"), r70ID(editor, "A8"), r70ID(editor, "A9")])
        #expect(editor.initialPlanPoints == nil)   // 첫 등록 뒤엔 안 보인다
    }

    @Test("첫 등록 합 = 판에 새로 놓은 맞는 묶음 + 랙 묶음 — 랙에서 판으로 옮겨도 합이 그대로")
    func initialPlanCombinesTableAndRack() throws {
        // 없으면: 랙 묶음을 판에 내려놓을수록 '랙 묶음 합'이 줄어 30 에 가까운지 거꾸로 읽히는 결함이 초록이 된다.
        var editor = r70Editor([("A7", 0, 0), ("A8", 0, 2), ("A9", 0, 4), ("B10", 0, 7), ("C10", 0, 9), ("D10", 0, 11), ("B2", 1, 0)],
                               table: [["C3", "C4", "C5"]], initialDone: false)
        let before = try #require(editor.initialPlanPoints)
        #expect(before.table == 0 && before.rack == 54)
        let group = [r70ID(editor, "B10"), r70ID(editor, "C10"), r70ID(editor, "D10")]
        let moved12 = editor.moveBlock(group, to: .newMeldAt(RummyPoint(x: 400, y: 300)))
        #expect(moved12)
        let after = try #require(editor.initialPlanPoints)
        #expect(after.table == 30 && after.rack == 24 && after.table + after.rack == before.table + before.rack)
        // 판의 무효 묶음은 0점(진행 막대와 같다).
        let moved13 = editor.moveBlock([r70ID(editor, "B2")], to: .newMeldAt(RummyPoint(x: 700, y: 500)))
        #expect(moved13)
        #expect(editor.initialPlanPoints?.table == 30)
        #expect(RummyCueText.plan(table: 30, rack: 24) == "랙 묶음 24 + 판 30 = 54 / 30")
        #expect(RummyCueText.plan(table: 0, rack: 24) == "랙 묶음 합 24 / 30")
    }

}

// MARK: - 렌더

private let r70Now = Date(timeIntervalSince1970: 1_800_000_000)
private var r70NowMs: Double { r70Now.timeIntervalSince1970 * 1000 }
private let r70Me = "00000000-0000-4000-8000-0000000000a1"
private let r70Seats: [(String, String, String, Int)] = [
    (r70Me, "영식", "shiba", 11), ("00000000-0000-4000-8000-0000000000b2", "민수", "fox", 9),
    ("00000000-0000-4000-8000-0000000000c3", "준호", "squirrel", 14),
]

private func r70Match(turn: Int = 0, initialDone: Bool = true, deadlineIn: Double = 42) throws -> RummyMatchState {
    let seats: [[String: Any]] = r70Seats.enumerated().map { index, seat in
        ["seat_no": index, "user_id": seat.0, "display_name": seat.1, "avatar_url": NSNull(), "character": seat.2,
         "state": "playing", "rack_count": seat.3, "initial_done": index == 0 ? initialDone : true, "timeout_streak": 0]
    }
    let state: [String: Any] = [
        "id": "7e7e0000-0000-4000-8000-000000000370", "status": "active", "host_id": r70Me, "stake": 5,
        "is_public": false, "seat_count": seats.count, "max_seats": 4, "server_now_ms": r70NowMs, "seq": 7,
        "seats": seats, "my_seat_no": 0, "my_rack": [], "my_initial_done": initialDone,
        "table": [["A3", "A4", "A5"], ["B7", "C7", "D7"]], "pool_count": 38, "turn_seat_no": turn,
        "turn_started_ms": r70NowMs - (60 - deadlineIn) * 1000, "turn_deadline_ms": r70NowMs + deadlineIn * 1000,
        "grace_ms": 2000, "consecutive_passes": 0, "last_event": NSNull(),
    ]
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(RummyMatchState.self, from: JSONSerialization.data(withJSONObject: state))
}

private enum R70Error: Error { case render }

@MainActor
private func r70Bitmap(_ view: some View) throws -> NSBitmapImageRep {
    let renderer = ImageRenderer(content: view.fixedSize())
    renderer.scale = 2
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff) else { throw R70Error.render }
    return bitmap
}

/// 판 화면만(창 머리글 없이 — 좌표 = `RummyMatchLayout.standard`). 첫 두 장이 다르게 나오므로 굳힌 뒤 둘째 장.
@MainActor
private func r70Render(_ editor: RummyTurnEditor, match: RummyMatchState, cues: RummyCuePreview?,
                       drag: RummyPreviewDrag? = nil, name: String? = nil) throws -> NSBitmapImageRep {
    let layout = RummyMatchLayout.standard
    let myTurn = match.turnSeatNo == match.mySeatNo
    let scene = RummyScene(phase: .playing, availability: .available, lobby: nil, match: match, editor: editor,
                           isMyTurn: myTurn, otherDraft: nil, notice: nil, isWorking: false, ranking: nil,
                           myUserID: UUID(uuidString: r70Me), fixedNow: r70Now, isPreview: true)
    let view = RummyMatchView(store: RummyStore(), scene: scene, match: match,
                              me: ChessPlayerFace(name: "영식", avatarURL: nil, characterID: "shiba"),
                              clipsOverflowInsteadOfScroll: true, previewDrag: drag)
        .environment(\.rummyCuePreview, cues)
        .environment(\.rummyArtStyle, .drawn)
        .frame(width: layout.size.width, height: layout.size.height)
        .background(CheckTheme.panel)
        .environment(\.colorScheme, .dark)
    _ = try r70Bitmap(view)
    let bitmap = try r70Bitmap(view)
    if let name { MiniGameSnapshots.save(bitmap, name: "rummy370-\(name).png", sub: "v370-rack") }
    return bitmap
}

/// 두 그림의 `rect`(pt) 안에서 채널 차가 `threshold` 를 넘는 픽셀 비율.
private func r70Diff(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep, in rect: CGRect, threshold: Int = 28) -> Double {
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

/// 첫 등록 전 받침대(맞는 덩어리 둘 + 아닌 것).
private func r70PlanEditor() -> RummyTurnEditor {
    r70Editor([("A7", 0, 0), ("A8", 0, 2), ("A9", 0, 4), ("B10", 0, 7), ("C10", 0, 9), ("D10", 0, 11),
               ("B2", 0, 14), ("B4", 0, 16), ("J", 0, 19), ("D5", 0, 21), ("D6", 0, 23),
               ("C1", 1, 0), ("C3", 1, 2), ("A12", 1, 6), ("B12", 1, 8), ("C12", 1, 10)],
              table: [["A3", "A4", "A5"], ["B7", "C7", "D7"]], initialDone: false)
}

@Suite("0.3.70 아잉 큐브 받침대 · 내 차례 — 렌더", .serialized)
@MainActor
struct V0370RummyRackRenderTests {
    private let L = RummyMatchLayout.standard

    @Test("[완료] 안 남은 초 색 문턱 = 차례 링(10초 이하 주황 · 5초 이하 빨강) · 밑줄 띠 자리는 덩어리 폭 안쪽")
    func cueGeometry() throws {
        #expect(RummySubmitSeconds.tint(seconds: 11) == nil)
        #expect(RummySubmitSeconds.tint(seconds: 10) == CheckTheme.pending)
        #expect(RummySubmitSeconds.tint(seconds: 5) == CheckTheme.danger)
        let editor = r70Editor([("A7", 0, 4), ("A8", 0, 6), ("A9", 0, 8)])
        let geometry = RummyRackGeometry()
        let meld = try #require(editor.rackMelds.first)
        let bar = try #require(RummyRackMeldMarks.frame(of: meld, layout: editor.rackLayout, geometry: geometry))
        let first = geometry.frame(RummyRackSlot(row: 0, halfCol: 4)), last = geometry.frame(RummyRackSlot(row: 0, halfCol: 8))
        #expect(bar.minX > first.minX && bar.maxX < last.maxX)
        #expect(bar.minY < first.maxY && bar.maxY > first.maxY)   // 타일 아랫단과 선반 턱에 걸친다
    }

    @Test("랙 묶음 밑줄 띠 + 점수 · 첫 등록 전 '랙 묶음 합' 꼬리표는 받침대 위 난간에만 그려진다")
    func rackMeldMarksRender() throws {
        // 없으면: 랙 묶음 표시가 계산만 되고 화면에 안 나오거나 판·버튼 칸을 덮는 결함이 초록이 된다.
        let match = try r70Match(initialDone: false)
        var editor = r70PlanEditor()
        #expect(editor.rackMelds.map(\.points) == [24, 30, 18, 36])
        let marked = try r70Render(editor, match: match, cues: RummyCuePreview(turnGlow: nil), name: "rack-melds")
        // 기준선: 같은 타일을 반 칸씩 떼어 둔 받침대(덩어리 없음 — 밑줄이 빠진다).
        let spaced = r70Editor(editor.rack.enumerated().map { i, t in (t.face.text, i / 10, (i % 10) * 3) },
                               table: [["A3", "A4", "A5"], ["B7", "C7", "D7"]], initialDone: false)
        #expect(spaced.rackMelds.isEmpty)
        let bar = try #require(RummyRackMeldMarks.frame(of: editor.rackMelds[0], layout: editor.rackLayout,
                                                        geometry: RummyRackGeometry()))
        let barRect = bar.offsetBy(dx: L.rack.minX, dy: L.rack.minY)
        let noMarks = try r70Render(r70Editor(editor.rack.map { t in
            (t.face.text, editor.rackLayout.slot(of: t.id)!.row, editor.rackLayout.slot(of: t.id)!.halfCol)
        }, table: [["A3", "A4", "A5"], ["B7", "C7", "D7"]], initialDone: true), match: try r70Match(initialDone: true),
            cues: RummyCuePreview(turnGlow: nil))
        // 같은 배치 · 첫 등록 뒤에도 밑줄은 있다(묶음 표시는 늘) — 꼬리표만 사라진다.
        #expect(r70Diff(marked, noMarks, in: barRect) < 0.05)
        let unmarked = try r70Render(spaced, match: match, cues: RummyCuePreview(turnGlow: nil))
        #expect(r70Diff(marked, unmarked, in: barRect.insetBy(dx: 0, dy: 3)) > 0.3, "밑줄 띠가 안 보인다")
        let tagRect = CGRect(x: L.rack.maxX - 300, y: L.rack.minY, width: 300, height: 20)
        #expect(r70Diff(marked, noMarks, in: tagRect) > 0.08, "첫 등록 전 꼬리표가 안 보인다")
        // 판 칸·버튼 칸은 그대로.
        #expect(r70Diff(marked, noMarks, in: L.table.insetBy(dx: 0, dy: 40)) < 0.01)
        // 판에 새 묶음을 놓으면 꼬리표가 '랙 + 판'.
        let moved14 = editor.moveBlock([r70ID(editor, "A12"), r70ID(editor, "B12"), r70ID(editor, "C12")],
                                 to: .newMeldAt(RummyPoint(x: 420, y: 420)))
        #expect(moved14)
        _ = try r70Render(editor, match: match, cues: RummyCuePreview(turnGlow: .steady), name: "rack-plan-with-table")
    }

    @Test("내 차례: 받침대 테두리 펄스 → 은은함 · '내 차례' 배지 · [완료] 안 남은 초(8초 = 주황)")
    func turnCuesRender() throws {
        // 없으면: 내 차례가 와도 왼쪽 아래 작은 카드 테두리만 바뀌어 초를 흘리는 결함(감사 #7)이 초록이 된다.
        let match = try r70Match(deadlineIn: 8)
        let editor = r70Editor([("A7", 0, 0), ("A8", 0, 2), ("A9", 0, 4), ("B2", 0, 7), ("C5", 1, 0)])
        let none = try r70Render(editor, match: match, cues: RummyCuePreview(turnGlow: nil))
        let pulse = try r70Render(editor, match: match, cues: RummyCuePreview(turnGlow: .pulse, turnBadge: true), name: "turn-pulse")
        let steady = try r70Render(editor, match: match, cues: RummyCuePreview(turnGlow: .steady), name: "turn-steady")
        let border = CGRect(x: L.rack.minX - 4, y: L.rack.minY - 4, width: L.rack.width + 8, height: 12)
        #expect(r70Diff(pulse, none, in: border) > 0.2, "펄스 테두리가 안 보인다")
        #expect(r70Diff(steady, none, in: border) > 0.1, "은은한 테두리가 안 보인다")
        let badge = CGRect(x: L.table.midX - 50, y: L.table.midY - 12, width: 100, height: 24)
        #expect(r70Diff(pulse, steady, in: badge) > 0.3, "'내 차례' 배지가 안 보인다")
        // 남의 차례면 [완료] 안 초가 없다.
        let other = try r70Render(editor, match: try r70Match(turn: 1, deadlineIn: 8), cues: RummyCuePreview(turnGlow: nil))
        let submit = CGRect(x: L.actions.maxX - 70, y: L.actions.minY + 8, width: 60, height: 26)
        #expect(r70Diff(none, other, in: submit) > 0.1, "[완료] 안 남은 초가 안 보인다")
    }

    @Test("끼워 넣기 미리보기: 붙은 타일 사이로 끌면 이웃이 비켜 서고 점선이 그 자리 · 뽑은 타일 빛남 · 정렬 선택 표시")
    func insertPreviewAndFreshRender() throws {
        // 없으면: 끄는 동안 어디로 끼워질지 안 보여(옛 '가장 가까운 빈칸' 점선) 놓은 뒤에야 알게 되는 결함이 초록이 된다.
        let match = try r70Match()
        let editor = r70Editor([("A5", 0, 0), ("A7", 0, 2), ("A8", 0, 4), ("B1", 0, 7), ("A6", 1, 4), ("C9", 1, 8)])
        let geometry = RummyRackGeometry()
        // A6 를 A5 와 A7 사이(반 칸 1)에 — 손 = 타일 가운데.
        let wanted = geometry.frame(RummyRackSlot(row: 0, halfCol: 1))
        let point = CGPoint(x: L.rack.minX + wanted.midX, y: L.rack.minY + wanted.midY)
        let a6 = r70ID(editor, "A6")
        let still = try r70Render(editor, match: match, cues: RummyCuePreview(turnGlow: nil))
        let dragging = try r70Render(editor, match: match, cues: RummyCuePreview(turnGlow: nil),
                                     drag: RummyPreviewDrag(tileID: a6, point: point), name: "insert-preview")
        // 이웃이 비켜 선다: B1 은 반 칸 떨어진 다른 덩어리라 반 칸 7 → 9(손에 든 타일이 닿지 않는 자리에서 잰다).
        let b1Lands = geometry.frame(RummyRackSlot(row: 0, halfCol: 9)).offsetBy(dx: L.rack.minX, dy: L.rack.minY)
        #expect(r70Diff(still, dragging, in: b1Lands.insetBy(dx: 2, dy: 6)) > 0.2, "이웃이 비켜 서지 않는다")
        let after = try #require(editor.rackLayoutAfterDrop([a6], at: RummyRackSlot(row: 0, halfCol: 1)))
        #expect(after.slot(of: a6) == RummyRackSlot(row: 0, halfCol: 2))
        #expect(after.slot(of: r70ID(editor, "B1")) == RummyRackSlot(row: 0, halfCol: 9))
        // 뽑은 타일 3초 빛남 + 789 선택 표시.
        let c9 = r70ID(editor, "C9")
        let fresh = try r70Render(editor, match: match, cues: RummyCuePreview(turnGlow: nil, freshTileIDs: [c9], sortMode: .color),
                                  name: "fresh-draw")
        let c9Frame = geometry.frame(RummyRackSlot(row: 1, halfCol: 8)).offsetBy(dx: L.rack.minX, dy: L.rack.minY)
        #expect(r70Diff(still, fresh, in: c9Frame.insetBy(dx: -6, dy: -6)) > 0.08, "뽑은 타일 빛이 안 보인다")
    }
}
