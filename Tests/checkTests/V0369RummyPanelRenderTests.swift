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

/// 로비 오른쪽 열의 세 칸.
private var rpRoomCardRect: CGRect {
    rpInBody(CGRect(x: L.lobbyListWidth + L.columnSpacing, y: 0, width: L.lobbySideWidth, height: L.roomCardHeight))
}
private var rpInvitesRect: CGRect {
    rpInBody(CGRect(x: L.lobbyListWidth + L.columnSpacing, y: L.roomCardHeight + L.sideSpacing,
                    width: L.lobbySideWidth, height: L.invitesHeight))
}
private var rpPeopleRect: CGRect {
    rpInBody(CGRect(x: 0, y: L.lobbyTabHeight + 10, width: L.lobbyListWidth, height: L.bodyHeight - L.lobbyTabHeight - 10))
}

// MARK: - 로비 · 결과 · 규칙(판 화면·타일 그림은 2판 `V0369RummyV2MatchRenderTests`)

@MainActor
@Suite(.serialized)
struct V0369RummyPanelRenderTests {
    // MARK: 로비

    @Test("로비 — 방 없음: 방 만들기 카드(고른 판돈 파랑) · 공개 방 없음 줄 · 기준선 = 공개 방 하나")
    func lobbyWithoutRoom() throws {
        // 없으면: 방 만들기 카드가 비어 그려지거나, 공개 방 목록이 사람 목록에 묻혀 [참가] 가 안 보인다.
        let store = RummyStore()
        store.selectedStake = 5
        store.createPublic = true
        let none = try rpRender(store: store, lobby: try rpLobby(), name: "lobby-none")
        let withPublic = try rpRender(store: store, lobby: try rpLobby(publicRooms: [
            rpRoom(roomB, host: uJunho, stake: 10, isPublic: true, seats: [(uJunho, "joined", 0), (uSeoyeon, "joined", 1)]),
        ]), name: "lobby-public-room")
        #expect(rpYellowBoxes(none) == 0 && rpYellowBoxes(withPublic) == 0, "노란 상자 — 렌더 못 하는 컨트롤이 섞였다")
        // 고른 판돈 칩(파랑 채움)이 방 만들기 카드에 있다.
        #expect(rpCount(none, near: rpAccent, tolerance: 24, in: rpRoomCardRect) > 800, "고른 판돈 칩 · [방 만들기] 파랑이 없다")
        // 공개 방 줄([참가] 파랑)은 공개 방이 있을 때만.
        let publicBand = rpInBody(CGRect(x: 0, y: L.lobbyTabHeight + 10, width: L.lobbyListWidth, height: 90))
        let joinNone = rpCount(none, near: rpAccent, tolerance: 24, in: publicBand)
        let joinSome = rpCount(withPublic, near: rpAccent, tolerance: 24, in: publicBand)
        #expect(joinSome > joinNone + 150, "공개 방 [참가] 버튼 잉크가 안 생겼다(\(joinNone) → \(joinSome))")
        // ★ 기준선: 오른쪽 열은 공개 방 유무와 상관없이 같다.
        #expect(rpDiff(none, withPublic, in: rpRoomCardRect) < 0.002)
    }

    @Test("로비 — 방장 방: 자리 4칸 · [시작] 초록 · 사람 행 [초대] · 기준선 = 같은 방의 손님")
    func lobbyHostRoom() throws {
        // 없으면: 방장인데 [시작]·[초대] 가 없어 판을 못 열거나, 손님에게 [시작] 이 보여 눌러 봐야 거절만 받는다.
        let seats: [(String, String, Int?)] = [(uMe, "joined", 0), (uMinsu, "joined", 1), (uJunho, "invited", nil)]
        let host = try rpRender(lobby: try rpLobby(room: rpRoom(roomA, host: uMe, seats: seats)), name: "lobby-host-room")
        let guestSeats: [(String, String, Int?)] = [(uMinsu, "joined", 0), (uMe, "joined", 1), (uJunho, "invited", nil)]
        let guest = try rpRender(lobby: try rpLobby(room: rpRoom(roomA, host: uMinsu, seats: guestSeats)),
                                 name: "lobby-guest-room")
        #expect(rpYellowBoxes(host) == 0)
        let startBand = CGRect(x: rpRoomCardRect.midX, y: rpRoomCardRect.maxY - 60, width: rpRoomCardRect.width / 2,
                               height: 60)
        let startHost = rpCount(host, near: rpWorking, tolerance: 24, in: startBand)
        let startGuest = rpCount(guest, near: rpWorking, tolerance: 24, in: startBand)
        #expect(startHost > startGuest + 1500, "방장의 [시작] 초록이 없다(방장 \(startHost) · 손님 \(startGuest))")
        let inviteColumn = CGRect(x: rpPeopleRect.maxX - 110, y: rpPeopleRect.minY + 60, width: 100, height: 300)
        let inviteHost = rpCount(host, near: rpAccent, tolerance: 24, in: inviteColumn)
        let inviteGuest = rpCount(guest, near: rpAccent, tolerance: 24, in: inviteColumn)
        #expect(inviteHost > inviteGuest + 500, "방장의 사람 행에 [초대] 가 없다(방장 \(inviteHost) · 손님 \(inviteGuest))")
    }

    @Test("로비 — 초대 받음: 받은 초대 칸에 [참가] 초록 · [거절] · 기준선 = 초대 없음")
    func lobbyInvited() throws {
        // 없으면: 초대가 와도 창 안에서 받을 곳이 없어 메뉴바 점만 깜박인다.
        let invite = rpRoom(roomA, host: uMinsu, stake: 10, seats: [(uMinsu, "joined", 0), (uMe, "invited", nil)])
        let invited = try rpRender(lobby: try rpLobby(invites: [invite]), name: "lobby-invited")
        let plain = try rpRender(lobby: try rpLobby())
        #expect(rpYellowBoxes(invited) == 0)
        let joinInk = rpCount(invited, near: rpWorking, tolerance: 24, in: rpInvitesRect)
        let joinPlain = rpCount(plain, near: rpWorking, tolerance: 24, in: rpInvitesRect)
        #expect(joinInk > joinPlain + 500, "받은 초대 [참가] 초록이 없다(\(joinPlain) → \(joinInk))")
        #expect(rpDiff(invited, plain, in: rpInvitesRect) > 0.03)
    }

    // MARK: 결과 · 규칙

    @Test("결과 — 등수 순 줄 · 루비 순수익(+10 초록 / −5 빨강) · 남은 랙 타일 · 기준선 = 모두 본전")
    func resultScreen() throws {
        // 없으면: 결과가 자리 순으로 서거나, 순수익이 아니라 받은 몫(15)을 보여 잃은 사람이 땄다고 읽는다.
        let finals: [(rank: Int, score: Int, payout: Int, winner: Bool, rack: [String])] = [
            (1, 42, 15, true, []), (3, -14, 0, false, ["B9", "C5"]), (2, -9, 5, false, ["A9"]),
            (4, -19, 0, false, ["J", "A6", "B3"]),
        ]
        let seats: [RPSeat] = [(uMe, 0, true, "done", 0), (uMinsu, 2, true, "done", 0),
                               (uJunho, 1, true, "done", 0), (uSeoyeon, 3, true, "forfeit", 0)]
        let result = try rpRender(match: try rpMatch(status: "finished", seats: seats, rack: nil, finals: finals,
                                                     endReason: "rack_empty"), name: "result")
        let even = finals.map { (rank: $0.rank, score: $0.score, payout: 5, winner: $0.winner, rack: $0.rack) }
        let flat = try rpRender(match: try rpMatch(status: "finished", seats: seats, rack: nil, finals: even,
                                                   endReason: "rack_empty"))
        #expect(rpYellowBoxes(result) == 0)
        // 순수익 열(등수 64 + 얼굴 44 + 이름 190 + 간격 16×3 + 여백 18+16 ≈ 380pt 부터 96pt).
        let top = 18 + 48 + L.resultRowSpacing
        func netCell(_ row: Int) -> CGRect {
            rpInBody(CGRect(x: 370, y: top + CGFloat(row) * (L.resultRowHeight + L.resultRowSpacing),
                            width: 120, height: L.resultRowHeight))
        }
        let winGreen = rpCount(result, near: rpWorking, tolerance: 24, in: netCell(0))
        let flatGreen = rpCount(flat, near: rpWorking, tolerance: 24, in: netCell(0))
        #expect(winGreen > flatGreen + 100, "1등 줄 +10 초록이 없다(\(flatGreen) → \(winGreen))")
        let loseRed = rpCount(result, near: rpDanger, tolerance: 24, in: netCell(3))
        let flatRed = rpCount(flat, near: rpDanger, tolerance: 24, in: netCell(3))
        #expect(loseRed > flatRed + 60, "꼴찌 줄 −5 빨강이 없다(\(flatRed) → \(loseRed))")
        // 남은 랙 타일: 꼴찌 줄(조커·A6·B3) 오른쪽에 타일 몸체.
        let rackCell = rpInBody(CGRect(x: 520, y: top + 3 * (L.resultRowHeight + L.resultRowSpacing),
                                       width: 400, height: L.resultRowHeight))
        #expect(rpCount(result, near: rpRGB(RummyTilePalette.bodyTop), tolerance: 10, in: rackCell) > 150, "남은 타일이 안 보인다")
    }

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
