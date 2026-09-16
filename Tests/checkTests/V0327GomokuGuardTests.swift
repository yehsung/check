import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check

// v0.3.27 오목 — 뮤테이션 검증(set #5)에서 **살아남은** 뮤턴트를 잡는 가드.
//
// 각 테스트 이름 옆 주석의 기호가 그 뮤턴트다(S2·S9·U6·X1·X2·X3·R8). 원본 코드에서는 초록이고, 해당 뮤턴트에서는 빨갛다
// (mut-client 탐침으로 실측 — S7 은 따로 두지 않고 수락 테스트 픽스처의 서버 루비를 로컬 계산과 다른 값으로 바꿨다).

private let ggMe = "00000000-0000-0000-0000-0000000000a1"
private let ggRival = "00000000-0000-0000-0000-0000000000b2"
private let ggMatch = "11111111-2222-3333-4444-555555555555"

private func ggJSON(_ object: Any) -> String {
    String(decoding: try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
}

private func ggState(
    status: String = "active", myColor: String = "black", moves: [(Int, String, Int, Int)] = [],
    turn: String? = "black", deadlineMs: Double? = nil, serverNowMs: Double? = nil,
    result: String? = nil, endReason: String? = nil, stake: Int = 5
) -> [String: Any] {
    let match: [String: Any] = [
        "id": ggMatch, "status": status, "stake": stake,
        "black": myColor == "black" ? ggMe : ggRival,
        "white": myColor == "black" ? ggRival : ggMe,
        "move_count": moves.count, "turn": turn ?? NSNull(),
        "deadline_ms": deadlineMs ?? NSNull(), "result": result ?? NSNull(), "end_reason": endReason ?? NSNull()
    ]
    let moveRows: [[String: Any]] = moves.map { move -> [String: Any] in
        ["seq": move.0, "color": move.1, "x": move.2, "y": move.3, "kind": "stone"]
    }
    return [
        "status": "ok", "match": match, "moves": moveRows, "my_color": myColor,
        "opponent": ["user_id": ggRival, "display_name": "라이벌", "avatar_url": NSNull(), "character": "aing"] as [String: Any],
        "server_now_ms": serverNowMs ?? NSNull()
    ]
}

private func ggDecode(_ object: [String: Any]) -> GomokuStatePayload {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try! decoder.decode(GomokuStatePayload.self, from: Data(ggJSON(object).utf8))
}

@MainActor
private enum GGRetain { static var stores: [WorkTimerStore] = [] }

@MainActor
private func ggStore(_ label: String, handler: @escaping GomokuStubProtocol.Handler) -> (WorkTimerStore, GomokuStore, String) {
    let host = "v0327-gg-\(label)-\(UUID().uuidString.prefix(8))".lowercased()
    GomokuStubProtocol.register(host: host, handler: handler)
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!, anonKey: "anon-test-key", session: GomokuStubProtocol.session())
    let store = WorkTimerStore(
        service: service, environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: GomokuTestDefaults.make("v0327-gg"), workspaceNotifications: nil)
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: ggMe)
    GGRetain.stores.append(store)
    return (store, store.gomoku, host)
}

@MainActor
private func ggWait(_ timeout: TimeInterval = 20, _ condition: @MainActor () -> Bool) async {
    // 상한은 벽시계가 아니라 **재개 횟수**다(5ms 한 번 = 한 차례). 전체 스위트에서는 렌더 테스트가 메인 액터를 수십 초씩 쥐어
    // 벽시계 상한이 스토어의 Task 가 차례를 받기도 전에 끝났다(0.3.27 전체 실행: 690초 지점에서 20초 대기 실패, 격리 3/3 초록).
    // V0325TooltipTests.waitUntil 과 같은 해법 — 재개마다 메인 액터 차례를 거치므로 스토어의 Task 도 같은 줄에서 순서를 받는다.
    for _ in 0..<Int(timeout * 200) {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
}

private let ggPeer = GomokuUser(id: ggRival, displayName: "라이벌", avatarURL: nil, characterID: nil,
                                isWorking: true, isCapable: true, inMatch: false)

// S2 — 계정 전환(adoptWorkStateOwner)은 sessionGeneration 을 올리지 않고 reset 만 한다. 그 사이 도착한 앞 계정의 수락 응답.
@MainActor
@Test(.gomokuDefaultsCleanup)
func 리셋_뒤에_도착한_수락_응답은_판도_루비도_세우지_않는다() async {
    let (_, gomoku, host) = ggStore("reset-respond") { rpc, _, _ in
        guard rpc == "gomoku_respond" else { return nil }
        return GomokuStubProtocol.Reply(
            body: ggJSON(["status": "ok", "ruby_balance": 17, "state": ggState(myColor: "white", turn: "black")]),
            delay: 0.4)
    }
    gomoku.incoming = [GomokuInvite(id: ggMatch, peer: ggPeer, stake: 3, expiresAt: Date().addingTimeInterval(50))]
    let pending = Task { await gomoku.respond(inviteID: ggMatch, accept: true) }
    await ggWait { GomokuStubProtocol.count(host: host, rpc: "gomoku_respond") == 1 }
    gomoku.reset()
    await pending.value
    #expect(gomoku.match == nil, "리셋 뒤 도착한 앞 계정의 수락 응답이 판을 세웠다")
    #expect(gomoku.phase == .lobby)
    #expect(gomoku.rubyBalance == nil, "리셋 뒤 도착한 앞 계정의 루비가 들어왔다")
}

// S9 — 신호 직렬화(requestSync): 끝나는 판을 읽는 동안 온 신호는 판이 끝난 **뒤** 의 기준(인박스)으로 간다.
@MainActor
@Test(.gomokuDefaultsCleanup)
func 끝나는_판을_읽는_중에_온_신호는_판이_끝난_뒤_받은함을_본다() async {
    let (_, gomoku, host) = ggStore("signal-finishing") { rpc, _, _ in
        switch rpc {
        case "gomoku_state":
            return GomokuStubProtocol.Reply(body: ggJSON(ggState(
                status: "finished", moves: [(1, "black", 7, 7)], turn: nil, result: "white_win", endReason: "resign")),
                delay: 0.3)
        case "gomoku_inbox":
            return GomokuStubProtocol.Reply(body: #"{"status":"ok","incoming":[],"outgoing":null}"#)
        case "gomoku_lobby":
            return GomokuStubProtocol.Reply(body: #"{"status":"ok","users":[]}"#)
        default:
            return nil
        }
    }
    gomoku.applyState(ggDecode(ggState(moves: [(1, "black", 7, 7)], turn: "white")))
    gomoku.handleSignal()
    await ggWait { GomokuStubProtocol.count(host: host, rpc: "gomoku_state") == 1 }
    gomoku.handleSignal()
    await ggWait { gomoku.match?.isFinished == true && gomoku.syncTask == nil }
    await ggWait(5) { GomokuStubProtocol.count(host: host, rpc: "gomoku_inbox") >= 1 }
    try? await Task.sleep(for: .milliseconds(500))
    #expect(GomokuStubProtocol.count(host: host, rpc: "gomoku_inbox") == 1, "판이 끝난 뒤 온 신호가 인박스를 안 봤다(새 신청을 놓친다)")
    #expect(GomokuStubProtocol.count(host: host, rpc: "gomoku_state") == 1, "끝난 판을 한 번 더 읽었다")
}

// X1 — 내 차례라도 표시 마감 + 유예(2초)가 지나면 보이는 창은 한 번 묻는다(결과 화면이 신호에만 기대지 않게).
@MainActor
@Test(.gomokuDefaultsCleanup)
func 내_차례라도_마감과_유예가_지나면_보이는_창은_결과를_묻는다() async {
    let moves = [(1, "black", 7, 7), (2, "white", 8, 7)]
    let (_, gomoku, host) = ggStore("overdue") { rpc, _, _ in
        rpc == "gomoku_state" ? GomokuStubProtocol.Reply(body: ggJSON(ggState(moves: moves, turn: "black"))) : nil
    }
    let local = Date(timeIntervalSince1970: 1_800_000_000)
    gomoku.clock = { local }
    let serverNow = local.timeIntervalSince1970 * 1000
    gomoku.applyState(ggDecode(ggState(moves: moves, turn: "black", deadlineMs: serverNow + 30_000, serverNowMs: serverNow)))
    gomoku.isWindowVisible = true
    await gomoku.pollTick(at: local.addingTimeInterval(31))
    #expect(GomokuStubProtocol.count(host: host, rpc: "gomoku_state") == 0, "유예(2초) 안인데 물었다")
    await gomoku.pollTick(at: local.addingTimeInterval(33))
    #expect(GomokuStubProtocol.count(host: host, rpc: "gomoku_state") == 1, "마감+유예가 지났는데 묻지 않았다 — 결과 화면이 안 온다")
}

// X2 — 금수 X 메모는 판이 바뀌면 다시 계산한다(상대가 둔 뒤 옛 판의 X 로 클릭을 막으면 안 된다).
@MainActor
@Test
func 금수_X_메모는_판이_바뀌면_다시_계산한다() throws {
    let memo = GomokuForbiddenMemo()
    var board = GomokuBoard()
    #expect(memo.points(for: board).isEmpty)
    for notation in ["F8", "G8", "H6", "H7"] {
        board[try #require(GomokuPoint(notation: notation))] = .black
    }
    #expect(memo.points(for: board)[try #require(GomokuPoint(notation: "H8"))] == .doubleThree,
            "상대가 둔 뒤에도 X 가 옛 판 기준이다")
}

// X3 — [로비로] 로 접은 끝난 판의 늦은 상태 응답이 사용자를 결과 화면으로 끌고 가지 않는다.
@MainActor
@Test
func 로비로_접은_끝난_판의_늦은_응답은_결과_화면으로_끌고_가지_않는다() {
    let gomoku = GomokuStore()
    let finished = ggDecode(ggState(status: "finished", moves: [(1, "black", 7, 7)], turn: nil,
                                    result: "black_win", endReason: "resign"))
    gomoku.applyState(finished)
    #expect(gomoku.phase == .result)
    gomoku.backToLobby()
    #expect(gomoku.phase == .lobby && gomoku.match == nil)
    gomoku.applyState(finished)
    #expect(gomoku.phase == .lobby, "접은 판의 늦은 응답이 결과 화면으로 끌고 갔다")
    #expect(gomoku.match == nil)
}

// U6 — 결과 카드는 rubyDelta 가 있으면 그 부호 그대로 그린다(진 판이 초록 +10 으로 보이면 안 된다).
@MainActor
@Test
func 결과_카드는_루비_변화의_부호를_그대로_그린다() throws {
    func resultStore(delta: Int?) -> GomokuStore {
        let store = GomokuStore()
        store.phase = .result
        store.match = GomokuMatchState(
            id: "m", stake: 10, myColor: .black,
            opponent: GomokuUser(id: ggRival, displayName: "민수", avatarURL: nil, characterID: "fox",
                                 isWorking: true, isCapable: true, inMatch: false),
            board: GomokuBoard(), lastMove: nil, moveCount: 21, turn: nil, deadline: nil, isFinished: true,
            outcome: .lost, endReason: .five, rubyDelta: delta, blackPassed: false)
        return store
    }
    let me = GomokuPlayerFace(name: "영식", avatarURL: nil, characterID: "shiba")
    let explicit = try ggBitmap(GomokuPanel(store: resultStore(delta: -10), me: { me }, clipsOverflowInsteadOfScroll: true))
    let computed = try ggBitmap(GomokuPanel(store: resultStore(delta: nil), me: { me }, clipsOverflowInsteadOfScroll: true))
    let diff = ggDiffCount(explicit, computed)
    #expect(diff <= 20, "진 판의 rubyDelta(-10)가 결과 기반 계산(-10)과 다르게 그려졌다(다른 픽셀 \(diff))")
}

// R8 — 예산을 넘긴 칸은 X 목록에 '판정할 수 없는 자리'로 남는다(버리면 X 가 사라지고 클릭이 서버 거절로 간다).
@Test
func 예산을_넘긴_칸은_X_목록에_예산_사유로_남는다() throws {
    var board = GomokuBoard()
    for notation in ["F8", "G8", "H6", "H7"] {
        board[try #require(GomokuPoint(notation: notation))] = .black
    }
    let h8 = try #require(GomokuPoint(notation: "H8"))
    let full = GomokuRules.judgeCounting(board: board, point: h8, color: .black, budget: nil)
    #expect(full.judgement == .forbidden(.doubleThree))
    #expect(full.nodes > 1, "예산을 조일 여지가 없는 국면이다(nodes \(full.nodes)) — 이 테스트가 아무것도 안 잰다")

    let tight = full.nodes - 1
    #expect(GomokuRules.judgeCounting(board: board, point: h8, color: .black, budget: tight).judgement == .forbidden(.budget))
    #expect(GomokuRules.forbiddenPoints(board: board, budget: tight)[h8] == .budget,
            "예산을 넘긴 칸이 X 목록에서 빠졌다")
    #expect(GomokuRules.forbiddenPoints(board: board)[h8] == .doubleThree, "기본 예산은 설계값(10,000)이다")
}

private enum GGRenderError: Error { case failed }

@MainActor
private func ggBitmap(_ view: some View) throws -> NSBitmapImageRep {
    let renderer = ImageRenderer(content: view.fixedSize())
    renderer.scale = 2
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff)
    else { throw GGRenderError.failed }
    return bitmap
}

private func ggDiffCount(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep) -> Int {
    guard a.pixelsWide == b.pixelsWide, a.pixelsHigh == b.pixelsHigh,
          let pa = a.bitmapData, let pb = b.bitmapData else { return Int.max }
    let bpr = a.bytesPerRow, spp = a.samplesPerPixel
    var count = 0
    for y in 0..<a.pixelsHigh {
        for x in 0..<a.pixelsWide {
            let o = y * bpr + x * spp
            if abs(Int(pa[o]) - Int(pb[o])) > 8 || abs(Int(pa[o + 1]) - Int(pb[o + 1])) > 8
                || abs(Int(pa[o + 2]) - Int(pb[o + 2])) > 8 { count += 1 }
        }
    }
    return count
}
