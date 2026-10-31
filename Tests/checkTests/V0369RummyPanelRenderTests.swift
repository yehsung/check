import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// v0.3.69 아잉 큐브 **화면** 렌더 — 타일 그림 · 로비(방 없음 · 방장 방 · 초대 받음) · 내 차례(무효 세트 포함 · 끌기 거절) ·
// 남의 차례 작업 판 · 결과 · 규칙.
//
// 전부 ImageRenderer(scale 2)로 그리고 `CHECK_SNAPSHOT_DIR/stills/rummy-*.png` 에 남긴다(사람이 직접 열어 본다 —
// 디자인 작업에서 초록 테스트는 아무것도 증명하지 않는다). 단언은 **"그 자리에 그 잉크가 있는가"** 이고, 언제나
// 같은 장면에서 한 값만 바꾼 **기준선**과 견준다(기준선이 같은 입력이면 그 단언은 영원히 초록이다).
//
// 스토어는 서버 권위라 상태를 밖에서 못 넣는다 — 패널의 렌더 주입구(`previewLobby`·`previewMatch`·`previewEditor`·
// `previewNow`)로 그린다. 와이어 값은 §3.5·§3.7 JSON 을 그대로 디코드해 만든다(서버가 보내는 모양 그대로).
//
// ★ 판정 의존 단언(무효 테두리 · [완료] · 첫 등록 진행)은 **편집기의 답을 먼저 묻고** 그 답대로 잉크를 잰다 —
//   규칙 구현(R 갈래)이 들어오기 전(자리표시 = 모두 무효)에도, 들어온 뒤에도 같은 시험이 같은 뜻으로 돈다.

// MARK: - 픽스처

private let rpNow = Date(timeIntervalSince1970: 1_800_000_000)
private var rpNowMs: Double { rpNow.timeIntervalSince1970 * 1000 }
private let rpMe = ChessPlayerFace(name: "영식", avatarURL: nil, characterID: "shiba")

private let uMe = "00000000-0000-4000-8000-0000000000a1"
private let uMinsu = "00000000-0000-4000-8000-0000000000b2"
private let uJunho = "00000000-0000-4000-8000-0000000000c3"
private let uSeoyeon = "00000000-0000-4000-8000-0000000000d4"
private let uHaneul = "00000000-0000-4000-8000-0000000000e5"
private let uOld = "00000000-0000-4000-8000-0000000000f6"
private let uFocus = "00000000-0000-4000-8000-000000000107"
private let roomA = "7e7e0000-0000-4000-8000-0000000000aa"
private let roomB = "7e7e0000-0000-4000-8000-0000000000bb"
private let matchID = "7e7e0000-0000-4000-8000-000000000068"

private let rpNames: [String: (String, String)] = [
    uMe: ("영식", "shiba"), uMinsu: ("민수", "fox"), uJunho: ("준호", "squirrel"), uSeoyeon: ("서연", "ghost"),
    uHaneul: ("하늘", "aing"), uOld: ("옛버전", "fox"), uFocus: ("집중왕", "aing"),
]

private func rpDecode<T: Decodable>(_ type: T.Type, _ object: [String: Any]) throws -> T {
    let data = try JSONSerialization.data(withJSONObject: object)
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(T.self, from: data)
}

private func rpPerson(_ id: String) -> [String: Any] {
    ["id": id, "display_name": rpNames[id]!.0, "avatar_url": NSNull(), "character": rpNames[id]!.1]
}

private func rpUser(_ id: String, working: Bool = true, inMatch: Bool = false, capable: Bool = true,
                    focus: Bool = false) -> [String: Any] {
    rpPerson(id).merging(["is_working": working, "in_match": inMatch, "capable": capable, "focus_mode": focus],
                         uniquingKeysWith: { $1 })
}

private func rpRoom(_ id: String, host: String, stake: Int = 5, isPublic: Bool = false, expiresIn: Double = 522,
                    seats: [(String, String, Int?)]) -> [String: Any] {
    ["id": id, "host": rpPerson(host), "stake": stake, "is_public": isPublic,
     "expires_at_ms": rpNowMs + expiresIn * 1000, "max_seats": 4,
     "seats": seats.map { seat in
         ["user_id": seat.0, "display_name": rpNames[seat.0]!.0, "avatar_url": NSNull(),
          "character": rpNames[seat.0]!.1, "state": seat.1, "seat_no": seat.2.map { $0 as Any } ?? NSNull()] as [String: Any]
     }]
}

private func rpLobby(room: [String: Any]? = nil, invites: [[String: Any]] = [],
                     publicRooms: [[String: Any]] = []) throws -> RummyLobby {
    try rpDecode(RummyLobby.self, [
        "status": "ok", "server_now_ms": rpNowMs, "stakes": [3, 5, 10], "turn_seconds": 60, "room_ttl_seconds": 600,
        "me": ["ruby_balance": 42, "games": 12, "wins": 4, "room": room.map { $0 as Any } ?? NSNull(), "active_match_id": NSNull()],
        "invites": invites, "public_rooms": publicRooms,
        "users": [rpUser(uMinsu), rpUser(uJunho), rpUser(uSeoyeon, working: false), rpUser(uHaneul, inMatch: true),
                  rpUser(uFocus, focus: true), rpUser(uOld, capable: false)],
    ])
}

/// 판 자리 — (id, rack_count, initial_done, state, timeout_streak).
private typealias RPSeat = (id: String, rack: Int, initial: Bool, state: String, streak: Int)

private let rpPlaySeats: [RPSeat] = [
    (uMe, 11, true, "playing", 0), (uMinsu, 9, true, "playing", 1),
    (uJunho, 14, false, "playing", 0), (uSeoyeon, 12, true, "playing", 0),
]

/// 확정 판(세 세트) · 내 랙 11장.
private let rpTable: [[String]] = [["A3", "A4", "A5"], ["B7", "C7", "D7"], ["C9", "C10", "C11", "C12"]]
private let rpRack: [String] = ["A6", "B2", "B9", "B10", "B11", "C5", "D1", "D13", "J", "A12", "C3"]

private func rpMatch(status: String = "active", turn: Int = 0, table: [[String]] = rpTable,
                     draft: [[String]]? = nil, seats: [RPSeat] = rpPlaySeats, rack: [String]? = rpRack,
                     finals: [(rank: Int, score: Int, payout: Int, winner: Bool, rack: [String])]? = nil,
                     endReason: String? = nil) throws -> RummyMatchState {
    let seatRows: [[String: Any]] = seats.enumerated().map { index, seat in
        var row: [String: Any] = [
            "seat_no": index, "user_id": seat.id, "display_name": rpNames[seat.id]!.0, "avatar_url": NSNull(),
            "character": rpNames[seat.id]!.1, "state": seat.state, "rack_count": seat.rack,
            "initial_done": seat.initial, "timeout_streak": seat.streak,
        ]
        if let finals {
            let f = finals[index]
            row["final_rank"] = f.rank
            row["final_score"] = f.score
            row["payout"] = f.payout
            row["is_winner"] = f.winner
            row["final_rack"] = f.rack
        }
        return row
    }
    var state: [String: Any] = [
        "id": matchID, "status": status, "host_id": uMe, "stake": 5, "is_public": false, "seat_count": seats.count,
        "max_seats": 4, "server_now_ms": rpNowMs, "seq": 17, "seats": seatRows, "my_seat_no": 0,
        "my_rack": rack.map { $0 as Any } ?? NSNull(), "my_initial_done": true, "table": table, "pool_count": 38,
        "turn_seat_no": turn, "turn_started_ms": rpNowMs - 18_000, "turn_deadline_ms": rpNowMs + 42_000,
        "grace_ms": 2000, "consecutive_passes": 0,
        "last_event": ["kind": "draw", "seat_no": 3, "count": 1, "at_ms": rpNowMs - 19_000],
    ]
    if let draft { state["draft"] = ["table": draft, "draft_seq": 4, "at_ms": rpNowMs - 2_000] }
    if let endReason {
        state["end_reason"] = endReason
        state["finished_at_ms"] = rpNowMs
    }
    return try rpDecode(RummyMatchState.self, state)
}

private func rpFaces(_ texts: [String]) -> [RummyFace] { texts.compactMap(RummyFace.init(text:)) }

private func rpEditor(table: [[String]] = rpTable, rack: [String] = rpRack, initialDone: Bool = true) -> RummyTurnEditor {
    RummyTurnEditor(table: table.map(rpFaces), rack: rpFaces(rack), initialDone: initialDone)
}

// MARK: - 렌더 도우미

private enum RPError: Error { case render }

@MainActor
private func rpBitmap(_ view: some View) throws -> NSBitmapImageRep {
    let renderer = ImageRenderer(content: view.fixedSize())
    renderer.scale = 2
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff) else { throw RPError.render }
    return bitmap
}

/// 창 화면 한 장(1240×700 · scale 2). 첫 두 장은 다르게 나온다(실측) — 한 번 굳힌 뒤 둘째 장을 쓴다.
@MainActor
private func rpRender(store: RummyStore = RummyStore(), lobby: RummyLobby? = nil, match: RummyMatchState? = nil,
                      editor: RummyTurnEditor? = nil, phase: RummyStore.Phase? = nil, tab: RummyLobbyTab? = nil,
                      overlay: RummyPreviewOverlay? = nil, drag: RummyPreviewDrag? = nil, notice: String? = nil,
                      ranking: RummyRanking? = nil, name: String? = nil) throws -> NSBitmapImageRep {
    let panel = RummyPanel(store: store, me: { rpMe }, clipsOverflowInsteadOfScroll: true, previewPhase: phase,
                           previewLobby: lobby, previewMatch: match, previewEditor: editor, previewRanking: ranking,
                           previewNow: rpNow, previewNotice: notice, previewMyUserID: UUID(uuidString: uMe),
                           previewLobbyTab: tab, previewOverlay: overlay, previewDrag: drag)
        .environment(\.colorScheme, .dark)
    _ = try rpBitmap(panel)
    let bitmap = try rpBitmap(panel)
    if let name { MiniGameSnapshots.save(bitmap, name: "rummy-\(name).png", sub: "stills") }
    return bitmap
}

/// `rect`(pt) 안에서 `target` 과 채널마다 `tolerance` 안쪽인 픽셀 수.
private func rpCount(_ bitmap: NSBitmapImageRep, near target: (Int, Int, Int), tolerance: Int = 18,
                     in rect: CGRect) -> Int {
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

/// 두 그림의 `rect` 안에서 채널 차가 `threshold` 를 넘는 픽셀 비율.
private func rpDiff(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep, in rect: CGRect? = nil, threshold: Int = 24) -> Double {
    guard let da = a.bitmapData, let db = b.bitmapData, a.pixelsWide == b.pixelsWide, a.pixelsHigh == b.pixelsHigh
    else { return 1 }
    let spp = a.samplesPerPixel, bpr = a.bytesPerRow
    let r = rect ?? CGRect(x: 0, y: 0, width: Double(a.pixelsWide) / 2, height: Double(a.pixelsHigh) / 2)
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

/// 노란 상자 감지 — `TextField`·`Picker`·`Toggle` 이 섞이면 ImageRenderer 가 그 자리를 노란 상자(255,204,0)로 그린다.
private func rpYellowBoxes(_ bitmap: NSBitmapImageRep) -> Int {
    rpCount(bitmap, near: (255, 204, 0), tolerance: 12,
            in: CGRect(x: 0, y: 0, width: Double(bitmap.pixelsWide) / 2, height: Double(bitmap.pixelsHigh) / 2))
}

private func rpRGB(_ rgb: RummyTilePalette.RGB) -> (Int, Int, Int) { (rgb.r, rgb.g, rgb.b) }

private let rpAccent = (84, 171, 255)
private let rpWorking = (89, 224, 161)
private let rpDanger = (255, 115, 117)

// ── 창 안 자리(pt) — 레이아웃 상수에서만 나온다 ──
private typealias L = RummyWindowLayout
private var rpBodyOrigin: CGPoint { CGPoint(x: L.contentPadding, y: L.contentPadding + L.headerHeight + L.headerSpacing) }

private func rpInBody(_ rect: CGRect) -> CGRect { rect.offsetBy(dx: rpBodyOrigin.x, dy: rpBodyOrigin.y) }

// 로비·방·결과 렌더는 2판에서 `V0369RummyV2LobbyTests.swift` 로 옮겼다(탁자 배치 · 받을 것 한 줄 · 한 판 더 · 최종 판).

// MARK: - 규칙(판 화면·타일 그림은 2판 `V0369RummyV2MatchRenderTests`, 로비·방·결과는 `V0369RummyV2LobbyTests`)

@MainActor
@Suite(.serialized)
struct V0369RummyPanelRenderTests {
    // MARK: 규칙

    @Test("규칙 — 시트에 예시 타일(네 색) · 기준선 = 시트 없는 로비")
    func rulesSheet() throws {
        // 없으면: 규칙 버튼이 빈 덮개를 띄우거나, 예시 타일 없이 글자만 있어 그룹/런 차이가 안 읽힌다.
        let lobby = try rpLobby()
        let rules = try rpRender(lobby: lobby, overlay: .rules, name: "rules")
        let plain = try rpRender(lobby: lobby)
        #expect(rpYellowBoxes(rules) == 0)
        let whole = CGRect(origin: .zero, size: L.contentSize)
        for color in 0..<4 {
            let ink = rpRGB(RummyTilePalette.inks[color])
            #expect(rpCount(rules, near: ink, tolerance: 22, in: whole) > 60, "규칙 시트에 색 \(color) 예시 타일이 없다")
        }
        #expect(rpDiff(rules, plain) > 0.2, "규칙 시트가 화면을 덮지 않는다")
        // ★ 기준선: 시트 없는 로비엔 타일 잉크(보라)가 머리글 조커 외엔 거의 없다.
        #expect(rpCount(plain, near: rpRGB(RummyTilePalette.inks[0]), tolerance: 22, in: whole)
                < rpCount(rules, near: rpRGB(RummyTilePalette.inks[0]), tolerance: 22, in: whole) / 3)
    }
}
