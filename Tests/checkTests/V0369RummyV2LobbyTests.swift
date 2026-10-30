import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// 아잉 큐브 2판 — 레인 U2(맥 로비 · 이탈 · 반응).
//
//  · 이탈 판단 표: 창 닫기(판 = 기권 확인 · 방 손님 = 그냥 나감 · 방장 = 방 닫힘 확인 · 그 밖 = 닫기), 앱 종료·로그아웃(판·방이면 이탈).
//  · 초대 줄: 방 없이 [초대] · [한 판 더] → 방이 서면 한 사람씩. 만들기가 거절되면 줄을 버린다.
//  · 탁자 의자 배치 · 받을 것 한 목록 · 반응 말풍선(자리마다 최근 것 2.5초 · 선형으로 사라짐) · 방위.
//  · 소스 계약: 종료 훅이 근무 가드 **앞에서** 이탈을 띄우고 두 길 다 기다린다 · 로그아웃 버튼 · 창 닫기 문 · 받침대 저장 · 깨어남 하트비트.
//  · 렌더(ImageRenderer scale 2): 로비(사람 많음·초대·공개 방) · 받을 것 없음 · 업데이트 필요 펼침 · 방(방장·손님) · 결과 · 최종 판 ·
//    창 닫기 확인 · 반응 말풍선. `RUMMY_STILLS_DIR` 이 있으면 PNG 를 거기 남긴다(사람이 연다). 단언은 언제나 한 값만 바꾼 기준선과 견준다.

// MARK: - 픽스처

private let lxNow = Date(timeIntervalSince1970: 1_800_000_000)
private var lxNowMs: Double { lxNow.timeIntervalSince1970 * 1000 }
private let lxMe = ChessPlayerFace(name: "영식", avatarURL: nil, characterID: "shiba")

private func lxID(_ n: Int) -> String { String(format: "00000000-0000-4000-8000-%012d", n) }
private let uMe = lxID(1)
private let lxPeople: [(id: String, name: String, character: String)] = [
    (lxID(1), "영식", "shiba"), (lxID(2), "민수", "fox"), (lxID(3), "준호", "squirrel"), (lxID(4), "서연", "ghost"),
    (lxID(5), "하늘", "aing"), (lxID(6), "다은", "fox"), (lxID(7), "지호", "aing"), (lxID(8), "유나", "ghost"),
    (lxID(9), "태민", "squirrel"), (lxID(10), "옛버전", "fox"), (lxID(11), "구판", "aing"), (lxID(12), "느림", "shiba"),
]
private let roomA = "7e7e0000-0000-4000-8000-0000000000aa"
private let roomB = "7e7e0000-0000-4000-8000-0000000000bb"
private let roomC = "7e7e0000-0000-4000-8000-0000000000cc"
private let matchID = "7e7e0000-0000-4000-8000-000000000068"

private func lxName(_ id: String) -> (String, String) {
    let p = lxPeople.first { $0.id == id }!
    return (p.name, p.character)
}

private func lxDecode<T: Decodable>(_ type: T.Type, _ object: [String: Any]) throws -> T {
    let data = try JSONSerialization.data(withJSONObject: object)
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(T.self, from: data)
}

private func lxPerson(_ id: String) -> [String: Any] {
    ["id": id, "display_name": lxName(id).0, "avatar_url": NSNull(), "character": lxName(id).1]
}

private func lxUser(_ id: String, working: Bool = true, inMatch: Bool = false, capable: Bool = true,
                    focus: Bool = false) -> [String: Any] {
    lxPerson(id).merging(["is_working": working, "in_match": inMatch, "capable": capable, "focus_mode": focus],
                         uniquingKeysWith: { $1 })
}

private func lxRoom(_ id: String, host: String, stake: Int = 5, isPublic: Bool = false,
                    seats: [(String, String, Int?)]) -> [String: Any] {
    ["id": id, "host": lxPerson(host), "stake": stake, "is_public": isPublic,
     "expires_at_ms": lxNowMs + 522_000, "max_seats": 4,
     "seats": seats.map { seat in
         ["user_id": seat.0, "display_name": lxName(seat.0).0, "avatar_url": NSNull(),
          "character": lxName(seat.0).1, "state": seat.1, "seat_no": seat.2.map { $0 as Any } ?? NSNull()] as [String: Any]
     }]
}

/// 사람 많음: 초대 가능 6 · 바쁨 2(게임 중·집중) · 업데이트 필요 3.
private var lxUsers: [[String: Any]] { [
    lxUser(lxID(2)), lxUser(lxID(3), inMatch: true), lxUser(lxID(4), working: false), lxUser(lxID(5)),
    lxUser(lxID(10), capable: false), lxUser(lxID(6)), lxUser(lxID(7), focus: true), lxUser(lxID(8), working: false),
    lxUser(lxID(11), capable: false), lxUser(lxID(9)), lxUser(lxID(12), capable: false),
] }

private func lxLobby(room: [String: Any]? = nil, invites: [[String: Any]] = [], publicRooms: [[String: Any]] = [],
                     users: [[String: Any]] = lxUsers) throws -> RummyLobby {
    try lxDecode(RummyLobby.self, [
        "status": "ok", "server_now_ms": lxNowMs, "stakes": [3, 5, 10], "turn_seconds": 60, "room_ttl_seconds": 600,
        "me": ["ruby_balance": 42, "games": 12, "wins": 4, "room": room.map { $0 as Any } ?? NSNull(),
               "active_match_id": NSNull()],
        "invites": invites, "public_rooms": publicRooms, "users": users,
    ])
}

private var lxInvite: [String: Any] { lxRoom(roomB, host: lxID(6), stake: 10, seats: [(lxID(6), "joined", 0), (uMe, "invited", nil)]) }
private var lxPublic: [String: Any] { lxRoom(roomC, host: lxID(7), stake: 3, isPublic: true,
                              seats: [(lxID(7), "joined", 0), (lxID(8), "joined", 1), (lxID(9), "joined", 2)]) }

private let lxTable: [[String]] = [["A3", "A4", "A5"], ["B7", "C7", "D7"], ["C9", "C10", "C11", "C12"]]

/// 끝난 판(4명 · 서연 기권) — 확정 판 세 묶음을 흩어 놓은 배치와 함께.
private func lxFinished(isPublic: Bool = true) throws -> RummyMatchState {
    let finals: [(String, String, Int, Int, Int, Bool, [String])] = [
        (uMe, "done", 1, 42, 15, true, []), (lxID(2), "done", 3, -14, 0, false, ["B9", "C5"]),
        (lxID(3), "done", 2, -9, 5, false, ["A9"]), (lxID(4), "forfeit", 4, -19, 0, false, ["J", "A6", "B3"]),
    ]
    let seats: [[String: Any]] = finals.enumerated().map { index, f in
        ["seat_no": index, "user_id": f.0, "display_name": lxName(f.0).0, "avatar_url": NSNull(),
         "character": lxName(f.0).1, "state": f.1, "rack_count": f.6.count, "initial_done": true, "timeout_streak": 0,
         "final_rank": f.2, "final_score": f.3, "payout": f.4, "is_winner": f.5, "final_rack": f.6]
    }
    return try lxDecode(RummyMatchState.self, [
        "id": matchID, "status": "finished", "host_id": uMe, "stake": 5, "is_public": isPublic, "seat_count": 4,
        "max_seats": 4, "server_now_ms": lxNowMs, "seq": 40, "seats": seats, "my_seat_no": 0,
        "my_rack": NSNull(), "my_initial_done": true, "table": lxTable, "table_layout": [[80, 96], [520, 240], [200, 420]],
        "pool_count": 20, "turn_seat_no": NSNull(), "consecutive_passes": 0,
        "end_reason": "rack_empty", "finished_at_ms": lxNowMs,
    ])
}

// MARK: - 렌더 도구

private enum LXError: Error { case render }

@MainActor
private func lxBitmap(_ view: some View) throws -> NSBitmapImageRep {
    let renderer = ImageRenderer(content: view.fixedSize())
    renderer.scale = 2
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff) else { throw LXError.render }
    return bitmap
}

private func lxSave(_ bitmap: NSBitmapImageRep, _ name: String) {
    guard let dir = ProcessInfo.processInfo.environment["RUMMY_STILLS_DIR"], !dir.isEmpty,
          let png = bitmap.representation(using: .png, properties: [:]) else { return }
    let url = URL(fileURLWithPath: dir, isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    try? png.write(to: url.appendingPathComponent("rummy-v2-\(name).png"))
}

/// 창 한 장(1240×700 · scale 2). 첫 두 장은 다르게 나온다(실측) — 한 번 굳힌 뒤 둘째 장을 쓴다.
@MainActor
private func lxRender(store: RummyStore = RummyStore(), lobby: RummyLobby? = nil, match: RummyMatchState? = nil,
                      phase: RummyStore.Phase? = nil, overlay: RummyPreviewOverlay? = nil, notice: String? = nil,
                      reactions: [RummyReactionBubble]? = nil, name: String? = nil) throws -> NSBitmapImageRep {
    let panel = RummyPanel(store: store, me: { lxMe }, clipsOverflowInsteadOfScroll: true, previewPhase: phase,
                           previewLobby: lobby, previewMatch: match, previewNow: lxNow, previewNotice: notice,
                           previewMyUserID: UUID(uuidString: uMe), previewOverlay: overlay, previewReactions: reactions)
        .environment(\.colorScheme, .dark)
    _ = try lxBitmap(panel)
    let bitmap = try lxBitmap(panel)
    if let name { lxSave(bitmap, name) }
    return bitmap
}

private func lxCount(_ bitmap: NSBitmapImageRep, near target: (Int, Int, Int), tolerance: Int = 18, in rect: CGRect) -> Int {
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

/// 펠트(남보라) 픽셀 — 파랑이 빨강보다 28 이상 높고 어두운 것. 무채색 카드 배경(파랑−빨강 ≈ 16)은 안 걸린다.
private func lxFeltCount(_ bitmap: NSBitmapImageRep, in rect: CGRect) -> Int {
    guard let data = bitmap.bitmapData, bitmap.samplesPerPixel >= 3 else { return -1 }
    let bpr = bitmap.bytesPerRow, spp = bitmap.samplesPerPixel
    let x0 = max(0, Int(rect.minX * 2)), x1 = min(bitmap.pixelsWide - 1, Int(rect.maxX * 2))
    let y0 = max(0, Int(rect.minY * 2)), y1 = min(bitmap.pixelsHigh - 1, Int(rect.maxY * 2))
    guard x0 <= x1, y0 <= y1 else { return 0 }
    var hits = 0
    for y in y0...y1 {
        for x in x0...x1 {
            let o = y * bpr + x * spp
            let r = Int(data[o]), g = Int(data[o + 1]), b = Int(data[o + 2])
            if b - r >= 28, b < 130, g <= r + 4 { hits += 1 }
        }
    }
    return hits
}

private func lxDiff(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep, in r: CGRect, threshold: Int = 24) -> Double {
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

private func lxYellowBoxes(_ bitmap: NSBitmapImageRep) -> Int {
    lxCount(bitmap, near: (255, 204, 0), tolerance: 12, in: CGRect(origin: .zero, size: L.contentSize))
}

private typealias L = RummyWindowLayout
private let lxAccent = (84, 171, 255)
private let lxWorking = (89, 224, 161)
private let lxDanger = (255, 115, 117)
private let lxWhite = (255, 255, 255)

private var lxBodyOrigin: CGPoint { CGPoint(x: L.contentPadding, y: L.contentPadding + L.headerHeight + L.headerSpacing) }
private func lxInBody(_ rect: CGRect) -> CGRect { rect.offsetBy(dx: lxBodyOrigin.x, dy: lxBodyOrigin.y) }
private func lxTableRect(hasJoinables: Bool) -> CGRect {
    lxInBody(CGRect(x: L.lobbyListWidth + L.columnSpacing, y: 0, width: L.lobbySideWidth,
                    height: L.tableCardHeight(hasJoinables: hasJoinables)))
}
private var lxJoinBand: CGRect {
    lxInBody(CGRect(x: L.lobbyListWidth + L.columnSpacing, y: L.tableCardHeight(hasJoinables: true) + L.sideSpacing,
                    width: L.lobbySideWidth, height: L.joinCardHeight))
}
private var lxPeopleRect: CGRect {
    lxInBody(CGRect(x: 0, y: L.lobbyTabHeight + 10, width: L.lobbyListWidth, height: L.bodyHeight - L.lobbyTabHeight - 10))
}

// MARK: - 판단 표

@MainActor
@Suite("v0.3.69 아잉 큐브 2판 — 로비·이탈·반응")
struct V0369RummyV2LobbyTests {
    @Test("창 닫기 판단 — 판 기권 확인 · 방 손님 그냥 나감 · 방장 확인 · 관전·로비·결과는 닫기")
    func closeDecisionTable() {
        typealias P = RummyExitPolicy
        #expect(P.closeDecision(phase: .playing, mySeatState: .playing, amHost: false) == .confirmForfeit)
        #expect(P.closeDecision(phase: .playing, mySeatState: .playing, amHost: true) == .confirmForfeit)
        #expect(P.closeDecision(phase: .playing, mySeatState: .forfeit, amHost: false) == .close, "기권한 관전자에게 또 묻는다")
        #expect(P.closeDecision(phase: .playing, mySeatState: nil, amHost: false) == .close)
        #expect(P.closeDecision(phase: .room, mySeatState: .joined, amHost: false) == .leaveRoom)
        #expect(P.closeDecision(phase: .room, mySeatState: .joined, amHost: true) == .confirmCloseRoom)
        #expect(P.closeDecision(phase: .lobby, mySeatState: nil, amHost: false) == .close)
        #expect(P.closeDecision(phase: .finished, mySeatState: .done, amHost: true) == .close)
        // 앱 종료·로그아웃: 보낼 것이 있는 것은 방 · 판(내 자리가 아직 playing)뿐.
        #expect(P.needsExitLeave(phase: .room, mySeatState: .joined))
        #expect(P.needsExitLeave(phase: .playing, mySeatState: .playing))
        #expect(!P.needsExitLeave(phase: .playing, mySeatState: .forfeit))
        #expect(!P.needsExitLeave(phase: .lobby, mySeatState: nil))
        #expect(!P.needsExitLeave(phase: .finished, mySeatState: .done))
    }

    @Test("판·방이 없는 스토어 — 창 닫기는 그냥 닫히고 종료·로그아웃은 기다릴 것이 없다")
    func idleStoreExitsAtOnce() async {
        let store = RummyStore()
        let controller = CheckRummyWindowController(stuckWindowCheckSeconds: 60)
        #expect(controller.requestClose(store: store))
        #expect(controller.lastCloseDecision == .close)
        #expect(controller.exitPrompt.pending == nil)
        #expect(RummyExitPolicy.startQuitLeave(store) == nil, "할 일이 없는데 종료를 늦춘다")
        #expect(await store.leaveForExit(reason: .appQuit), "판이 없으면 즉시 true")
    }

    @Test("창 닫기 확인 — 확인은 준 일을 한 번만 · 취소·다시 묻기는 일을 버린다")
    func exitPromptRunsOnce() {
        let prompt = RummyExitPrompt()
        var runs = 0
        prompt.ask(.confirmForfeit) { runs += 1 }
        #expect(prompt.pending == .confirmForfeit)
        prompt.confirm()
        prompt.confirm()
        #expect(runs == 1 && prompt.pending == nil)
        prompt.ask(.confirmCloseRoom) { runs += 1 }
        prompt.cancel()
        prompt.confirm()
        #expect(runs == 1 && prompt.pending == nil, "취소한 확인이 나중에 실행됐다")
    }

    @Test("초대 줄 — 일하는 중 기다림 · 방 없음/방장 아님 버림 · 이미 앉은 사람 건너뜀 · 아니면 첫 사람 초대")
    func inviteQueueSteps() {
        let a = UUID(), b = UUID()
        typealias Q = RummyInviteQueue
        #expect(Q.step(pending: [], isWorking: false, roomStatus: .forming, amHost: true, seated: []) == .wait)
        #expect(Q.step(pending: [a], isWorking: true, roomStatus: nil, amHost: false, seated: []) == .wait,
                "방 만들기가 떠 있는데 줄을 버렸다")
        #expect(Q.step(pending: [a], isWorking: false, roomStatus: nil, amHost: false, seated: []) == .drop,
                "만들기가 거절됐는데 줄이 남아 다음 방에서 엉뚱하게 초대한다")
        #expect(Q.step(pending: [a], isWorking: false, roomStatus: .active, amHost: true, seated: []) == .drop)
        #expect(Q.step(pending: [a], isWorking: false, roomStatus: .forming, amHost: false, seated: []) == .drop)
        #expect(Q.step(pending: [a, b], isWorking: false, roomStatus: .forming, amHost: true, seated: [a]) == .skip(a))
        #expect(Q.step(pending: [a, b], isWorking: false, roomStatus: .forming, amHost: true, seated: []) == .invite(a))
        // 스토어에 세션이 없으면 만들기가 안 떠난다 → 그 자리에서 줄을 버린다(눌러 둔 사람이 다음 방에 끌려가지 않게).
        let queue = RummyInviteQueue()
        queue.invite(a, store: RummyStore())
        #expect(queue.pending.isEmpty)
    }

    @Test("한 판 더 — 나와 기권한 사람은 빼고 자리 순으로 부른다")
    func rematchInvitees() throws {
        let match = try lxFinished()
        #expect(RummyResultView.rematchInvitees(match) == [lxID(2), lxID(3)].compactMap(UUID.init(uuidString:)))
    }

    @Test("받을 것 한 목록 — 초대 먼저 · 같은 방 한 번 · 지금 앉은 방은 뺀다")
    func joinablesMergeInvitesAndPublicRooms() throws {
        let lobby = try lxLobby(invites: [lxInvite], publicRooms: [lxPublic, lxInvite])
        let scene = RummyScene(phase: .lobby, availability: .available, lobby: lobby, match: nil, editor: nil,
                               isMyTurn: false, otherDraft: nil, notice: nil, isWorking: false, ranking: nil,
                               myUserID: UUID(uuidString: uMe), fixedNow: lxNow, isPreview: true)
        let list = RummyLobbyView.joinables(scene)
        #expect(list.map(\.id.uuidString).map { $0.lowercased() } == [roomB, roomC])
        #expect(list.map(\.isInvite) == [true, false])
    }

    @Test("탁자 의자 — 나는 아래 · 앉은 사람은 내 다음 자리부터 시계 방향 · 초대 중은 그 뒤(흐리게) · 나머지 빈 의자")
    func tableSeating() throws {
        let room = try lxDecode(RummyRoom.self, lxRoom(roomA, host: lxID(2), seats: [
            (lxID(2), "joined", 0), (uMe, "joined", 2), (lxID(3), "joined", 3), (lxID(4), "invited", nil),
        ]))
        let chairs = RummyTableSeating.chairs(room: room, me: lxMe, myUserID: UUID(uuidString: uMe))
        #expect(chairs.map(\.name) == ["영식", "준호", "민수", "서연"], "\(chairs.map(\.name))")
        #expect(chairs[0].isMe && chairs[0].seatNo == 2)
        #expect(chairs[2].isHost && chairs[2].tag == RummyText.hostTag)
        #expect(chairs[3].dimmed && chairs[3].seatNo == nil, "초대 중 자리에 반응 앵커가 붙는다")
        let empty = RummyTableSeating.chairs(room: nil, me: lxMe, myUserID: UUID(uuidString: uMe))
        #expect(empty.map(\.kind) == [.person, .empty, .empty, .empty])
    }

    @Test("방위 — 둘이면 마주 봄 · 셋이면 왼·오른 · 넷이면 왼·위·오른(내 다음 자리부터)")
    func seatCompass() {
        typealias C = RummySeatCompass
        #expect(C.of(seatNo: 1, mySeatNo: 1, seatNos: [0, 1]) == .bottom)
        #expect(C.of(seatNo: 0, mySeatNo: 1, seatNos: [0, 1]) == .top)
        #expect(C.of(seatNo: 2, mySeatNo: 1, seatNos: [0, 1, 2]) == .left)
        #expect(C.of(seatNo: 0, mySeatNo: 1, seatNos: [0, 1, 2]) == .right)
        #expect([2, 3, 0].map { C.of(seatNo: $0, mySeatNo: 1, seatNos: [0, 1, 2, 3]) } == [.left, .top, .right])
        #expect(C.of(seatNo: 3, mySeatNo: nil, seatNos: [0, 3]) == .bottom)
    }

    @Test("반응 말풍선 — 자리마다 최근 것 하나 · 2.5초 · 튀어나와 1로 · 마지막 0.3초 선형으로 사라짐")
    func reactionBubbleTiming() {
        let t0 = lxNow
        let bubbles = [
            RummyReactionBubble(id: 1, seatNo: 1, sticker: .joy, isMine: false, receivedAt: t0),
            RummyReactionBubble(id: 2, seatNo: 1, sticker: .heart, isMine: false, receivedAt: t0.addingTimeInterval(1)),
            RummyReactionBubble(id: 3, seatNo: 0, sticker: .sad, isMine: true, receivedAt: t0),
        ]
        let at = RummyReactionOverlay.visible(bubbles, at: t0.addingTimeInterval(1.2))
        #expect(at.map(\.id) == [3, 2], "자리 1 의 앞 반응이 남았다")
        #expect(RummyReactionOverlay.visible(bubbles, at: t0.addingTimeInterval(2.6)).map(\.id) == [2])
        #expect(RummyReactionOverlay.visible(bubbles, at: t0.addingTimeInterval(3.6)).isEmpty)
        #expect(abs(RummyReactionOverlay.scale(age: 0) - 0.5) < 0.001 && RummyReactionOverlay.scale(age: 0.3) == 1)
        // 말풍선 자리: 위 앵커는 위에(창 위 끝이면 아래로), 옆 앵커는 옆에 — 탁자 아래 의자(나)는 판 가운데를 덮지 않는다.
        let seat = CGRect(x: 600, y: 400, width: 46, height: 46)
        #expect(RummyReactionOverlay.side(for: RummySeatAnchor(rect: seat)) == .top)
        #expect(RummyReactionOverlay.side(for: RummySeatAnchor(rect: CGRect(x: 600, y: 20, width: 46, height: 46))) == .bottom)
        let right = RummyReactionOverlay.center(for: seat, side: .trailing)
        #expect(right.x - RummyReactionBubbleView.height / 2 >= seat.maxX && abs(right.y - seat.midY) < 0.5)
        #expect(RummyReactionOverlay.scale(age: 0.15) > 1, "튀어나오며 살짝 넘치지 않는다")
        #expect(RummyReactionOverlay.opacity(age: 1) == 1)
        let mid = RummyReactionOverlay.opacity(age: 2.35)
        #expect(abs(mid - 0.5) < 0.01, "사라짐이 선형이 아니다(\(mid))")
        #expect(RummyReactionOverlay.opacity(age: 2.5) == 0)
    }

    // MARK: 소스 계약

    @Test("소스 계약 — 종료 훅은 근무 가드 앞에서 이탈을 띄우고 두 길 모두 기다린다 · 로그아웃 버튼 · 창 닫기 문 · 받침대 저장 · 깨어남 하트비트")
    func exitPathsAreWired() throws {
        let app = V0317ShopTests.stripped(try V0317ShopTests.source("CheckApp.swift"))
        let start = try #require(app.range(of: "func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {"))
        let body = String(app[start.upperBound...].prefix(1400))
        let launch = try #require(body.range(of: "let rummyExit = RummyExitPolicy.startQuitLeave(store.rummy)"))
        let guardLine = try #require(body.range(of: "guard store.isSignedIn, store.startedAt != nil, !store.adoptedRemoteSession else {"))
        #expect(launch.upperBound <= guardLine.lowerBound, "근무가 없으면 이탈을 띄우기도 전에 종료한다")
        #expect(body.contains("guard let rummyExit else { return .terminateNow } Task { @MainActor in _ = await rummyExit.value NSApp.reply(toApplicationShouldTerminate: true) } return .terminateLater }"),
                "근무 없는 종료가 아잉 큐브 이탈을 기다리지 않는다")
        #expect(body.contains("await store.finishWorkBeforeQuit() _ = await rummyExit?.value NSApp.reply(toApplicationShouldTerminate: true)"),
                "근무 중 종료가 아잉 큐브 이탈을 기다리지 않는다")
        #expect(app.contains("rummy.rackDefaults = .standard"), "받침대 자리가 앱을 다시 켜면 사라진다")
        #expect(app.contains("forName: NSWorkspace.didWakeNotification"))
        #expect(app.contains("guard let matchID = rummy.heartbeatMatchID else { return } Task { @MainActor in await rummy.heartbeatTick(matchID: matchID) }"))

        let menu = V0317ShopTests.stripped(try V0317ShopTests.source("CheckMenuView.swift"))
        #expect(menu.contains("IconButton(icon: \"rectangle.portrait.and.arrow.right\", help: \"로그아웃\") { store.signOutLeavingRummy() }"),
                "로그아웃 버튼이 아잉 큐브 판을 두고 세션부터 지운다")
        let flow = V0317ShopTests.stripped(try V0317ShopTests.source("RummyExitFlow.swift"))
        #expect(flow.contains("_ = await self?.rummy.leaveForExit(reason: .signOut)"))
        #expect(flow.contains("guard let self, self.sessionGeneration == generation else { return } self.signOut()"))

        let window = V0317ShopTests.stripped(try V0317ShopTests.source("CheckRummyWindow.swift"))
        #expect(window.contains("func windowShouldClose(_ sender: NSWindow) -> Bool { guard sender === windowStorage, let store = wiring?.store else { return true } return requestClose(store: store) }"))
        #expect(window.contains("case .leaveRoom: Task { @MainActor in _ = await store.leaveForExit(reason: .windowClosed) } return true"))
        #expect(window.contains("private func closeAndLeave(store: RummyStore) { close() Task { @MainActor in _ = await store.leaveForExit(reason: .windowClosed) } }"))
        #expect(window.contains("RummyPanel(store: rummy, me: me, safety: safety) .environment(prompt)"))
        // 프로그램이 내리는 닫기(로그아웃 정리)는 `windowShouldClose` 를 거치지 않는 `window.close()` 다 — performClose 면 확인이 뜬다.
        let closeWindow = try #require(app.range(of: "static func closeRummyWindow() {"))
        #expect(!app[closeWindow.upperBound...].prefix(300).contains("performClose"))
    }

    // MARK: 렌더

    @Test("로비 — 사람 많음: 초대 가능 위 · 바쁨 흐리게 · 업데이트 필요 접힘 · 방 없이도 [초대] · 받은 초대+공개 방 한 줄 · 기준선 = 받을 것 없음")
    func lobbyRenders() throws {
        let store = RummyStore()
        store.selectedStake = 5
        let busy = try lxRender(store: store, lobby: try lxLobby(invites: [lxInvite], publicRooms: [lxPublic]), name: "lobby")
        let quiet = try lxRender(store: store, lobby: try lxLobby(), name: "lobby-empty")
        // 업데이트 필요 접힘/펼침은 사람이 적은 목록에서 잰다(많으면 펼친 줄이 칸 아래로 잘린다 — 앱은 스크롤).
        let few = Array(lxUsers.prefix(5))
        let folded = try lxRender(store: store, lobby: try lxLobby(users: few))
        let opened = try lxRender(store: store, lobby: try lxLobby(users: few), overlay: .outdatedExpanded,
                                  name: "lobby-outdated-open")
        #expect(lxYellowBoxes(busy) == 0 && lxYellowBoxes(quiet) == 0 && lxYellowBoxes(opened) == 0)
        // 받은 초대 [참가] 초록 · 공개 방 카드가 한 줄에 선다(없으면 한 줄 안내만).
        let joinBusy = lxCount(busy, near: lxWorking, tolerance: 24, in: lxJoinBand)
        let joinQuiet = lxCount(quiet, near: lxWorking, tolerance: 24, in: lxJoinBand)
        #expect(joinBusy > joinQuiet + 500, "받은 초대 [참가] 초록이 없다(\(joinQuiet) → \(joinBusy))")
        // 탁자 펠트는 둘 다 · 받을 것이 없으면 탁자 카드가 커진다(빈 카드 대신).
        #expect(lxFeltCount(busy, in: lxTableRect(hasJoinables: true)) > 40_000, "탁자 펠트가 없다")
        #expect(lxFeltCount(busy, in: lxPeopleRect) < 2_000, "사람 칸에 펠트 색이 번졌다(측정이 무채색 배경을 센다)")
        #expect(lxDiff(busy, quiet, in: lxJoinBand) > 0.05)
        // 방이 없어도 사람 행 [초대](파랑)가 산다 — 초대 가능한 사람 줄에.
        let inviteColumn = CGRect(x: lxPeopleRect.maxX - 110, y: lxPeopleRect.minY + 20, width: 100, height: 240)
        #expect(lxCount(quiet, near: lxAccent, tolerance: 24, in: inviteColumn) > 600, "방 없는 로비에 [초대] 가 없다")
        // 업데이트 필요 접힘 → 펼치면 사람 칸이 바뀐다.
        #expect(lxDiff(folded, opened, in: lxPeopleRect) > 0.01, "업데이트 필요 사람을 펼쳐도 그대로다")
        // 긴 목록이 '업데이트 필요' 접힌 줄을 칸 밖으로 밀지 않는다(그 줄의 노랑 글자가 사람 칸 바닥에 있다).
        let foldBand = CGRect(x: lxPeopleRect.minX, y: lxPeopleRect.maxY - 60, width: lxPeopleRect.width, height: 60)
        #expect(lxCount(busy, near: (255, 184, 84), tolerance: 30, in: foldBand) > 150, "'업데이트 필요' 줄이 칸 밖으로 밀렸다")
    }

    @Test("방 — 방장: 탁자 둘레 의자 · 상금 · [N명으로 시작] 초록 · 기준선 = 같은 방의 손님(시작 없음)")
    func roomRenders() throws {
        let hostSeats: [(String, String, Int?)] = [(uMe, "joined", 0), (lxID(2), "joined", 1), (lxID(3), "invited", nil)]
        let host = try lxRender(lobby: try lxLobby(room: lxRoom(roomA, host: uMe, seats: hostSeats)), name: "room-host")
        let guestSeats: [(String, String, Int?)] = [(lxID(2), "joined", 0), (uMe, "joined", 1), (lxID(3), "invited", nil)]
        let guest = try lxRender(lobby: try lxLobby(room: lxRoom(roomA, host: lxID(2), seats: guestSeats)), name: "room-guest")
        #expect(lxYellowBoxes(host) == 0 && lxYellowBoxes(guest) == 0)
        let table = lxTableRect(hasJoinables: false)
        let startBand = CGRect(x: table.maxX - 250, y: table.maxY - 60, width: 250, height: 60)
        let startHost = lxCount(host, near: lxWorking, tolerance: 24, in: startBand)
        let startGuest = lxCount(guest, near: lxWorking, tolerance: 24, in: startBand)
        #expect(startHost > startGuest + 1500, "방장의 [시작] 초록이 없다(방장 \(startHost) · 손님 \(startGuest))")
        // 반응 말풍선: 방 의자 앵커 위에 흰 말풍선(기준선 = 같은 방 말풍선 없음).
        let bubbles = [RummyReactionBubble(id: 1, seatNo: 1, sticker: .heart, isMine: false, receivedAt: lxNow.addingTimeInterval(-0.6)),
                       RummyReactionBubble(id: 2, seatNo: 0, sticker: .joy, isMine: true, receivedAt: lxNow.addingTimeInterval(-1))]
        let reacted = try lxRender(lobby: try lxLobby(room: lxRoom(roomA, host: uMe, seats: hostSeats)), reactions: bubbles,
                                   name: "room-reactions")
        let white = lxCount(reacted, near: lxWhite, tolerance: 6, in: table)
        let plainWhite = lxCount(host, near: lxWhite, tolerance: 6, in: table)
        #expect(white > plainWhite + 3000, "반응 말풍선이 의자 위에 안 섰다(\(plainWhite) → \(white))")
    }

    @Test("결과 — [한 판 더] 파랑 · [최종 판] 은 배치 그대로 펠트 위 묶음 · 창 닫기 확인 덮개 · 기준선 = 등수 줄")
    func resultRenders() throws {
        let match = try lxFinished()
        let ranks = try lxRender(match: match, name: "result")
        let board = try lxRender(match: match, overlay: .finalBoard, name: "result-board")
        let closing = try lxRender(match: match, overlay: .closeForfeit, name: "close-forfeit")
        #expect(lxYellowBoxes(ranks) == 0 && lxYellowBoxes(board) == 0 && lxYellowBoxes(closing) == 0)
        let headerRight = lxInBody(CGRect(x: L.innerWidth - 200, y: 18, width: 182, height: 48))
        #expect(lxCount(ranks, near: lxAccent, tolerance: 24, in: headerRight) > 1500, "[한 판 더] 파랑이 없다")
        let below = lxInBody(CGRect(x: 18, y: 18 + 48 + L.resultRowSpacing, width: L.innerWidth - 36, height: 440))
        let feltBoard = lxFeltCount(board, in: below)
        let feltRanks = lxFeltCount(ranks, in: below)
        #expect(feltBoard > 20_000 && feltBoard > feltRanks * 5, "최종 판 펠트가 안 깔렸다(\(feltRanks) → \(feltBoard))")
        #expect(lxCount(board, near: (RummyTilePalette.bodyTop.r, RummyTilePalette.bodyTop.g, RummyTilePalette.bodyTop.b),
                        tolerance: 10, in: below) > 400, "최종 판 묶음 타일이 안 보인다")
        let whole = CGRect(origin: .zero, size: L.contentSize)
        let againUnder = lxCount(closing, near: lxAccent, tolerance: 24, in: headerRight)
        #expect(againUnder * 5 < lxCount(ranks, near: lxAccent, tolerance: 24, in: headerRight), "창 닫기 확인이 화면을 덮지 않는다")
        #expect(lxCount(closing, near: lxDanger, tolerance: 24, in: whole) > 800, "[기권하고 닫기] 빨강이 없다")
    }

    @Test("반응 고르기 — 이모티콘 여섯 칸")
    func reactionPickerRenders() throws {
        let picker = try lxBitmap(RummyReactionPicker(onPick: { _ in }).background(CheckTheme.panel)
            .environment(\.colorScheme, .dark))
        lxSave(picker, "reaction-picker")
        #expect(picker.pixelsWide >= Int(RummyReactionPicker.cell * 3 * 2))
        #expect(lxYellowBoxes(picker) == 0)
    }
}
