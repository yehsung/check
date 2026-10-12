import Foundation
import Testing
@testable import check
@testable import CheckCore

// v0.3.48 — 체스 **끌어서 두기**의 스토어 계약(`grab` · `beginDrag` · `placeDrop`/`finishDrop`/`drop` ·
// `pendingDrop` · `dragOrigin` · `beginFlight` 의 "끌어 놓은 말만 뺀다").
//
// ★ 모양이 아니라 **부르는 자리의 결과**를 잰다(메모리 `tests-measure-shape-not-result`): 스텁 서비스가 받은
//   `chess_move` 가 몇 건이고 본문의 UCI 가 무엇인가, 그 순간 `pendingDrop` 이 무엇으로 읽히는가, 그 수의
//   애니메이션에 **어느 말이 들어 있는가**. 함수가 있는지·소스에 글자가 있는지는 한 줄도 세지 않는다.
//
// 서버는 스텁이다(오목 `GomokuStubProtocol` 을 그대로 쓴다). 응답 본문은 손으로 만든 봉투이고, 키가 어긋나
// 아무것도 안 재는 사고를 막으려고 **서비스와 같은 디코더**로 읽으며 FEN·SAN 은 `ChessRules` 로 만든다
// (`V0346ChessFlightStoreTests` 와 같은 규칙 — 그 파일의 헬퍼는 private 이라 복사했다).
//
// ★ 기준선이 갈리는지 확인했다(같은 입력의 기준선은 영원히 초록이다):
//   · 놓은 자리 — 갈 수 있는 칸(1건) · 출발 칸 · 판 밖 · 갈 수 없는 칸 · 내 말(전부 0건) → ①②
//   · 입구 — **끌어 둔** 수(그 말이 애니메이션에 없다) · **클릭으로 둔 같은 수**(있다) → ⑥⑦⑧⑫
//   · 꼬리표 — 지워서 없다(`pendingDropRecord == nil`) · 남아 있는데 없는 것으로 읽힌다(자기 치유) → ⑤
//   · 걸쇠 — 계기 없음(1건) · 계기 열한 가지 각각(0건) → ⑩
//   · 놓은 직후의 틈 — 놓기 → (다른 말 집기 · 탭) → 왕복: 놓은 수가 1건 / 승격을 고르던 중이면 꼬리표가 지워진다 → ⑬④
//   · 서버 거절 — 재조회가 즉답(⑤) · 재조회가 늦다(⑭) · 승격의 거절과 전송 실패(⑮)
//   · 앞 수의 꼬리 — 끌어 둔 조용한 수(애니메이션 없음) · 클릭으로 둔 같은 수(새 애니메이션) → ⑯
//   · 낡은 놓기 — 판이 그대로(1건) · 출발 칸의 말이 달라짐 · 내 차례가 꺼짐(0건) → ⑰

// MARK: - 하네스

private let dsT0 = Date(timeIntervalSinceReferenceDate: 0)
private let dsServerNowMs = dsT0.timeIntervalSince1970 * 1000

private let dsMatch = "d0480000-0000-4000-8000-0000000000c1"
private let dsOtherMatch = "d0480000-0000-4000-8000-0000000000c2"
private let dsWhiteID = "aa480000-0000-4000-8000-0000000000a1"
private let dsBlackID = "bb480000-0000-4000-8000-0000000000b1"

/// 킹사이드 캐슬링만 남긴 판(왕 e1·룩 h1). 왕을 g1 으로 끌면 룩이 h1 → f1 로 간다.
private let dsCastleFEN = "4k3/8/8/8/8/8/8/4K2R w K - 0 1"
/// 앙파상 직전: 백 폰 d5 · 흑 폰 e5(방금 두 칸 왔다). 잡힌 폰은 도착 칸(e6)이 **아니라** e5 에 서 있다.
private let dsEnPassantFEN = "4k3/8/8/3Pp3/8/8/8/4K3 w - e6 0 1"
/// 승격 직전: 백 폰 a7. a8 로 가는 합법 수가 넷(Q R B N)이다.
private let dsPromotionFEN = "4k3/P7/8/8/8/8/8/4K3 w - - 0 1"

private struct DSError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

/// 상한은 벽시계가 아니라 **재개 횟수**다(전체 스위트에서는 렌더 테스트가 메인 액터를 오래 쥔다).
@MainActor
private func dsWait(_ resumes: Int = 4_000, _ condition: @MainActor () -> Bool) async {
    for _ in 0..<resumes {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(2))
    }
}

private let dsDecoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return decoder
}()

private func dsDecode(_ object: [String: Any]) throws -> ChessStatePayload {
    try dsDecoder.decode(ChessStatePayload.self, from: JSONSerialization.data(withJSONObject: object))
}

private func dsBody(_ object: [String: Any]) -> String {
    String(decoding: try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
}

private func dsSquare(_ notation: String) throws -> ChessSquare {
    guard let square = ChessSquare(notation) else { throw DSError("칸 이름이 아니다: \(notation)") }
    return square
}

/// 수순 하나. `positions[n]` 은 n 수를 둔 뒤의 국면이고 `rows[n]` 은 n+1 번째 수의 서버 행이다.
private struct DSLine {
    let positions: [ChessPosition]
    let rows: [[String: Any]]
}

/// 출발 국면(기본은 초기 배치)에서 UCI 수들을 **실제로 적용해** 국면 열과 서버 수 행을 만든다.
private func dsLine(_ ucis: [String], from startFEN: String? = nil) throws -> DSLine {
    var positions: [ChessPosition]
    if let startFEN {
        guard let start = ChessPosition(fen: startFEN) else { throw DSError("FEN 을 못 읽었다: \(startFEN)") }
        positions = [start]
    } else {
        positions = [.standard]
    }
    var rows: [[String: Any]] = []
    for (offset, uci) in ucis.enumerated() {
        let current = positions[offset]
        guard let move = ChessMove(uci: uci) else { throw DSError("UCI 가 아니다: \(uci)") }
        guard let san = ChessRules.san(for: move, in: current) else {
            throw DSError("합법 수가 아니다: \(uci) · \(current.fen)")
        }
        guard let after = ChessRules.apply(move, to: current) else {
            throw DSError("적용할 수 없는 수다: \(uci) · \(current.fen)")
        }
        var row: [String: Any] = [
            "seq": offset + 1, "color": current.sideToMove.rawValue,
            "from": move.from.index, "to": move.to.index,
            "san": san, "fen": after.fen, "ms_left": 300_000, "ms_spent": 0,
        ]
        if let promotion = move.promotion { row["promo"] = String(promotion.fenLetter).lowercased() }
        rows.append(row)
        positions.append(after)
    }
    return DSLine(positions: positions, rows: rows)
}

/// `chess_state` 봉투(= 쓰기 RPC 응답과 같은 모양). `legal_moves` 는 **내 차례일 때만** 싣는다(서버 계약 ⑦).
/// `status` 를 바꾸면 착수 거절 응답이 된다(서버는 거절에도 **건드리지 않은 판**을 되돌려 준다).
private func dsStateJSON(matchID: String = dsMatch, ply: Int, _ line: DSLine, myColor: ChessColor = .white,
                         finished: Bool = false, status: String = "ok") -> [String: Any] {
    let position = line.positions[ply]
    let isMine = !finished && position.sideToMove == myColor
    var row: [String: Any] = [
        "id": matchID, "status": finished ? "finished" : "active", "stake": 5,
        "white": dsWhiteID, "black": dsBlackID, "challenger": dsWhiteID, "opponent": dsBlackID,
        "ply_count": ply, "fen": position.fen,
        "white_ms_left": 300_000, "black_ms_left": 300_000, "increment_ms": 3_000,
        "white_grace_ms": 2_000, "black_grace_ms": 2_000, "started_ms": dsServerNowMs,
    ]
    if finished {
        // 상대가 기권했다 — 수 번호는 그대로이고 판만 닫힌다.
        row["result"] = myColor == .white ? "white_win" : "black_win"
        row["end_reason"] = "resign"
    } else {
        row["turn"] = position.sideToMove.rawValue
        row["turn_started_ms"] = dsServerNowMs
    }
    return [
        "status": status, "server_now_ms": dsServerNowMs, "match": row,
        "moves": Array(line.rows.prefix(ply)), "my_color": myColor.rawValue,
        "in_check": finished ? NSNull() : ChessRules.isInCheck(position),
        "legal_moves": isMine ? ChessRules.legalMoves(in: position).map(\.uci).sorted() : NSNull(),
    ]
}

@MainActor
private enum DSRetention {
    /// `WorkTimerStore` 는 체스 스토어를 약참조로 들린다 — 테스트가 버리면 host 가 nil 이 되어 요청이 안 나간다.
    static var stores: [WorkTimerStore] = []
}

/// 1:1 스토어 한 벌 + 스텁 호스트 이름. 창은 보이는 것으로 둔다(애니메이션이 서야 그 안을 잴 수 있다).
@MainActor
private func dsStore(_ label: String, me: String = dsWhiteID,
                     handler: @escaping GomokuStubProtocol.Handler) -> (ChessStore, String) {
    let host = "v0348-cd-\(label)-\(UUID().uuidString.prefix(8))".lowercased()
    GomokuStubProtocol.register(host: host, handler: handler)
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!, anonKey: "anon-test-key",
        session: GomokuStubProtocol.session())
    let owner = WorkTimerStore(
        service: service, environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: GomokuTestDefaults.make("v0348-chess-drag"), workspaceNotifications: nil)
    owner.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: me)
    DSRetention.stores.append(owner)
    let chess = ChessStore(host: owner)
    chess.pollStepSeconds = 3_600
    chess.clock = { dsT0 }
    chess.isWindowVisible = true
    return (chess, host)
}

/// rpc 이름 → 응답 본문 목록(같은 rpc 의 n 번째 호출이 n 번째 본문, 모자라면 마지막 것 반복).
/// 표에 없는 rpc 는 PGRST202 로 답한다 — 요청이 새면 그 자리가 곧 결함이다.
private func dsHandler(_ map: [String: [String]] = [:]) -> GomokuStubProtocol.Handler {
    { rpc, _, index in
        guard let bodies = map[rpc], !bodies.isEmpty else {
            return GomokuStubProtocol.Reply(status: 404, body: #"{"code":"PGRST202","message":"missing"}"#)
        }
        return GomokuStubProtocol.Reply(body: bodies[min(index, bodies.count - 1)])
    }
}

/// `ply` 까지 둔 1:1 판을 들고, 그다음 수(`ply + 1`)를 서버가 받아 주는 스토어.
@MainActor
private func dsPlayable(_ label: String, _ line: DSLine, ply: Int = 0) throws -> (ChessStore, String) {
    let next = min(ply + 1, line.positions.count - 1)
    let (store, host) = dsStore(label, handler: dsHandler([
        "chess_move": [dsBody(dsStateJSON(ply: next, line))],
        "chess_state": [dsBody(dsStateJSON(ply: next, line))],
    ]))
    store.applyState(try dsDecode(dsStateJSON(ply: ply, line)))
    return (store, host)
}

/// 로봇의 수를 테스트가 풀어 준다(안 풀면 로봇이 곧바로 두어 사람 수의 애니메이션을 덮는다).
///
/// ★ 기다림은 **취소를 본다.** `try? await Task.sleep` 은 취소되면 곧바로 돌아오므로, 취소를 안 보는 루프는
///   스토어가 로봇 작업을 끊는 순간 쉬지 않고 도는 CPU 버너가 된다(테스트 프로세스가 끝날 때까지).
private actor DSRobotGate {
    private var isOpen = false
    func open() { isOpen = true }
    func waitUntilOpen() async {
        while !isOpen, !Task.isCancelled { try? await Task.sleep(for: .milliseconds(2)) }
    }
}

/// 손으로 짠 국면에서 시작한 로봇 판(사람이 백). `startAIMatch` 는 초기 배치만 열어 주므로 캐슬링·잡기·승격을
/// 재려면 로컬 판을 직접 세운다 — 수는 그대로 `send` → `moveInAIMatch` → `commitAIGame` 길을 지난다.
@MainActor
private func dsRobotStore(_ label: String, fen: String? = nil,
                          gate: DSRobotGate) throws -> (ChessStore, String) {
    let (store, host) = dsStore(label, handler: dsHandler())
    store.aiRuntime.minimumThinkSeconds = 0
    store.aiMoveChooser = { position, _ in
        await gate.waitUntilOpen()
        return ChessRules.legalMoves(in: position).first
    }
    if let fen {
        let position = try #require(ChessPosition(fen: fen), "FEN 을 못 읽었다: \(fen)")
        let game = ChessAIGame(humanColor: .white, position: position, now: dsT0)
        store.aiGame = game
        store.match = game.matchState()
        store.phase = .playing
    } else {
        store.startAIMatch(humanColor: .white)
    }
    #expect(store.isAIMatch)
    return (store, host)
}

@MainActor
private func dsMoveCalls(_ host: String) -> [String] {
    GomokuStubProtocol.calls(host: host, rpc: "chess_move").compactMap { $0.json["p_uci"] as? String }
}

@Suite("체스 끌기 — 스토어")
struct V0348ChessDragStoreTests {

    // MARK: - ① 합법 칸에 놓으면 정확히 한 건, 그 UCI 로

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func droppingOnALegalSquareSendsExactlyOneMoveWithThatUCI() async throws {
        // 없으면: 끌기가 고르기만 세우고 수를 안 보내도, 두 번 보내도, 다른 수를 보내도 초록이다.
        let line = try dsLine(["e2e4", "e7e5"])
        let (store, host) = try dsPlayable("legal", line)
        let e2 = try dsSquare("e2"), e4 = try dsSquare("e4")

        // 잡는 순간 그 말이 고른 말이 된다 — 클릭으로 고른 것과 **같은 값**이다(갈 수 있는 칸 점이 뜬다).
        #expect(store.grab(at: e2) == .movable)
        #expect(store.beginDrag(from: e2))
        #expect(store.selection == ChessSelection(from: e2, targets: [try dsSquare("e3"), e4]))
        #expect(store.dragOrigin == e2)
        #expect(dsMoveCalls(host).isEmpty, "잡기만 했는데 수가 나갔다")

        await store.drop(from: e2, on: e4)

        let calls = GomokuStubProtocol.calls(host: host, rpc: "chess_move")
        #expect(calls.count == 1, "놓은 수가 \(calls.count)건 나갔다")
        #expect(calls.first?.json["p_uci"] as? String == "e2e4")
        #expect(calls.first?.json["p_expected_ply"] as? Int == 0)
        #expect(calls.first?.json["p_match_id"] as? String == dsMatch)
        // 답이 판을 한 수 앞으로 옮겼고, 끌기의 흔적은 하나도 안 남았다.
        #expect(store.match?.plyCount == 1)
        #expect(store.match?.lastMove?.uci == "e2e4")
        #expect(store.match?.position?[e4] == ChessPiece(.white, .pawn))
        #expect(store.selection == nil)
        #expect(store.dragOrigin == nil)
        #expect(store.pendingDrop == nil)
        #expect(store.pendingDropRecord == nil, "받아들여진 수의 꼬리표가 남았다")
        #expect(store.notice == nil)
        #expect(!store.isBusy)
    }

    // MARK: - ② 출발 칸 · 판 밖 · 갈 수 없는 칸은 0건이고, 고르기는 남는다

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func droppingAnywhereElseSendsNothingAndKeepsTheSelection() async throws {
        // 없으면: 판 밖·출발 칸에 놓은 말이 가장 가까운 합법 칸으로 나가거나, 놓칠 때마다 고르기가 풀려
        //        "다시 집어야 한다" 가 되어도 초록이다.
        let line = try dsLine(["e2e4"])
        let (store, host) = try dsPlayable("elsewhere", line)
        let e2 = try dsSquare("e2")
        let kept = ChessSelection(from: e2, targets: [try dsSquare("e3"), try dsSquare("e4")])

        // 출발 칸에 도로 놓았다 — 수 없음, 고르기는 **남는다**(해제는 탭의 일이다), 말이 없다.
        #expect(store.beginDrag(from: e2))
        await store.drop(from: e2, on: e2)
        #expect(store.selection == kept, "출발 칸에 놓았더니 고르기가 풀렸다")
        #expect(store.notice == nil, "출발 칸에 놓았는데 안내가 떴다")
        #expect(store.dragOrigin == nil, "놓았는데 끌기가 살아 있다")

        // 판 밖 — 조용히 돌아간다.
        #expect(store.beginDrag(from: e2))
        await store.drop(from: e2, on: nil)
        #expect(store.selection == kept, "판 밖에 놓았더니 고르기가 풀렸다")
        #expect(store.notice == nil, "판 밖에 놓았는데 안내가 떴다")

        // 갈 수 없는 빈 칸 — 기존 `.illegalTarget` 거절(문구)이 그대로 나고, 고르기는 남는다.
        #expect(store.beginDrag(from: e2))
        await store.drop(from: e2, on: try dsSquare("e5"))
        #expect(store.selection == kept)
        #expect(store.notice == ChessNoticeText.cannotMove)

        // 내 다른 말 위 — 갈 수 없는 칸이다. 탭과 달리 고르기를 **옮기지 않는다**(끌던 말이 돌아갈 뿐이다).
        store.notice = nil
        #expect(store.beginDrag(from: e2))
        await store.drop(from: e2, on: try dsSquare("d2"))
        #expect(store.selection == kept, "내 말 위에 놓았더니 고르기가 그 말로 옮겨갔다")
        #expect(store.notice == ChessNoticeText.cannotMove)

        #expect(dsMoveCalls(host).isEmpty, "둘 수 없는 자리에 놓았는데 수가 나갔다: \(dsMoveCalls(host))")
        #expect(store.pendingDrop == nil)
        #expect(store.pendingDropRecord == nil)
        #expect(store.match?.plyCount == 0)

        // ★ 기준선: 같은 스토어에서 갈 수 있는 칸에 놓으면 곧바로 나간다(위 0건이 "스토어가 죽어서" 가 아니다).
        #expect(store.beginDrag(from: e2))
        await store.drop(from: e2, on: try dsSquare("e4"))
        #expect(dsMoveCalls(host) == ["e2e4"])
    }

    // MARK: - ③ 끌기의 거절은 탭과 같은 문구다

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func dragRefusalsSayTheSameThingAsTheTap() async throws {
        // 없으면: 같은 상황을 탭은 "상대 차례예요" 라 하고 끌기는 다른 말(또는 무음)을 해도 초록이다.
        let line = try dsLine(["e2e4"])
        // d2 의 폰으로 잰다 — 세 상황 **전부에서 그 칸에 내 말이 서 있다**(e2 의 폰은 '상대 차례' 판에서 이미 e4 로 갔다).
        let d2 = try dsSquare("d2"), d4 = try dsSquare("d4")

        enum Situation: CaseIterable { case notMyTurn, busy, finished }
        func arrange(_ situation: Situation, _ store: ChessStore) throws {
            switch situation {
            case .notMyTurn: store.applyState(try dsDecode(dsStateJSON(ply: 1, line)))
            case .busy: store.isBusy = true
            case .finished: store.applyState(try dsDecode(dsStateJSON(ply: 0, line, finished: true)))
            }
        }
        let expected: [Situation: String] = [
            .notMyTurn: ChessNoticeText.notYourTurn, .busy: ChessNoticeText.sending,
            .finished: ChessNoticeText.finishedMatch,
        ]

        for situation in Situation.allCases {
            // 탭(기준).
            let (tapped, tapHost) = try dsPlayable("say-tap", line)
            try arrange(situation, tapped)
            await tapped.tap(d2)
            let said = try #require(tapped.notice, "\(situation): 탭이 아무 말도 안 했다 — 기준선이 비었다")
            #expect(said == expected[situation])

            // 끌기 시작.
            let (dragged, dragHost) = try dsPlayable("say-drag", line)
            try arrange(situation, dragged)
            #expect(dragged.grab(at: d2) == .stuck, "\(situation): 해석기에 '끌 수 있다' 고 말한다")
            #expect(!dragged.beginDrag(from: d2), "\(situation): 끌기가 시작됐다")
            #expect(dragged.notice == said, "\(situation): 끌기 시작이 '\(dragged.notice ?? "무음")' — 탭은 '\(said)'")
            #expect(dragged.selection == nil)
            #expect(dragged.dragOrigin == nil)

            // 놓기(끄는 중에 그 상황이 됐다 — 뷰가 취소를 놓쳤다고 치고 스토어에 직접 놓는다).
            let (dropped, dropHost) = try dsPlayable("say-drop", line)
            #expect(dropped.beginDrag(from: d2))
            try arrange(situation, dropped)
            await dropped.drop(from: d2, on: d4)
            #expect(dropped.notice == said, "\(situation): 놓기가 '\(dropped.notice ?? "무음")' — 탭은 '\(said)'")
            #expect(dropped.pendingDrop == nil)

            for host in [tapHost, dragHost, dropHost] {
                #expect(dsMoveCalls(host).isEmpty, "\(situation): 거절인데 수가 나갔다")
            }
        }

        // 말에 달린 거절 셋도 탭과 같다: 빈 칸·상대 말은 조용하고, 갈 곳 없는 내 말은 "둘 수 없는 자리".
        for (square, grab) in [("e4", ChessBoardPointer.Grab.none), ("e7", .none), ("a1", .stuck)] {
            let (tapped, _) = try dsPlayable("piece-tap", line)
            await tapped.tap(try dsSquare(square))
            let (dragged, _) = try dsPlayable("piece-drag", line)
            #expect(dragged.grab(at: try dsSquare(square)) == grab, "\(square)")
            #expect(!dragged.beginDrag(from: try dsSquare(square)), "\(square) 에서 끌기가 시작됐다")
            #expect(dragged.notice == tapped.notice, "\(square): 끌기 '\(dragged.notice ?? "무음")' · 탭 '\(tapped.notice ?? "무음")'")
            #expect(dragged.selection == tapped.selection)
            #expect(dragged.dragOrigin == nil)
        }
        let (rook, _) = try dsPlayable("piece-rook", line)
        await rook.tap(try dsSquare("a1"))
        #expect(rook.notice == ChessNoticeText.cannotMove, "전제: 갈 곳 없는 말의 탭이 말을 한다")
    }

    // MARK: - ③b 고른 말과 끌기

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func draggingKeepsOrMovesTheSelectionWhereATapWouldToggleIt() async throws {
        // 없으면: 이미 고른 말을 집어 들었더니 고르기가 **해제**되어(탭의 길) 갈 수 있는 칸 점이 사라져도 초록이다.
        let line = try dsLine(["e2e4"])
        let (store, host) = try dsPlayable("selected", line)
        let e2 = try dsSquare("e2"), d2 = try dsSquare("d2")

        await store.tap(e2)
        #expect(store.selection?.from == e2)
        #expect(store.beginDrag(from: e2), "이미 고른 말을 끌 수 없다")
        #expect(store.selection?.from == e2, "고른 말을 끌었더니 해제됐다")
        await store.drop(from: e2, on: e2)
        #expect(store.selection?.from == e2, "출발 칸에 놓았더니 해제됐다")
        // ★ 기준선: 같은 자리의 **탭**은 해제한다(클릭 동작은 그대로다).
        await store.tap(e2)
        #expect(store.selection == nil, "고른 말을 다시 눌렀는데 해제가 안 된다 — 클릭 동작이 바뀌었다")

        // 다른 말을 고른 채로 끌면 고르기가 끄는 말로 옮겨간다.
        await store.tap(d2)
        #expect(store.selection?.from == d2)
        #expect(store.beginDrag(from: e2))
        #expect(store.selection == ChessSelection(from: e2, targets: [try dsSquare("e3"), try dsSquare("e4")]))
        // 끌기를 거둬도 고르기는 남는다(끌던 말은 여전히 고른 말이다).
        store.cancelDrag()
        #expect(store.dragOrigin == nil)
        #expect(store.selection?.from == e2)
        #expect(dsMoveCalls(host).isEmpty)
    }

    // MARK: - ④ 승격 — 놓기 → 고르기 → 한 건 / 취소 → 0건

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func promotionByDragAsksFirstThenSendsOneMoveOrNoneOnCancel() async throws {
        // 없으면: 끝줄에 놓은 폰이 묻지도 않고 퀸으로 나가거나, 취소했는데 폰이 도착 칸에 **유령으로 남아도** 초록이다.
        let line = try dsLine(["a7a8q"], from: dsPromotionFEN)
        let a7 = try dsSquare("a7"), a8 = try dsSquare("a8")
        let pawn = ChessPendingDrop(matchID: dsMatch, ply: 0, from: a7, to: a8, piece: ChessPiece(.white, .pawn))

        // 고른다.
        let (store, host) = try dsPlayable("promo-choose", line)
        #expect(store.beginDrag(from: a7))
        await store.drop(from: a7, on: a8)
        #expect(store.promotion == ChessPromotionPrompt(from: a7, to: a8), "끝줄에 놓았는데 고르기 창이 안 떴다")
        #expect(dsMoveCalls(host).isEmpty, "고르기 전에 수가 나갔다")
        #expect(store.pendingDrop == pawn, "고르는 동안 폰이 도착 칸에 안 머문다")
        #expect(store.match?.plyCount == 0)

        await store.choosePromotion(.queen)
        #expect(dsMoveCalls(host) == ["a7a8q"])
        #expect(store.promotion == nil)
        #expect(store.pendingDrop == nil)
        #expect(store.pendingDropRecord == nil)
        #expect(store.match?.position?[a8] == ChessPiece(.white, .queen))
        // 폰은 미끄러지지 않는다(이미 도착 칸에 있었다). 잡기도 캐슬링도 아니라 애니메이션 자체가 없다.
        #expect(store.flight == nil, "끌어 놓은 승격 폰이 다시 미끄러졌다")

        // 취소한다 — 0건이고 폰은 출발 칸으로.
        let (cancelled, cancelHost) = try dsPlayable("promo-cancel", line)
        #expect(cancelled.beginDrag(from: a7))
        await cancelled.drop(from: a7, on: a8)
        #expect(cancelled.pendingDrop == pawn)
        cancelled.cancelPromotion()
        #expect(cancelled.promotion == nil)
        #expect(cancelled.pendingDrop == nil, "취소했는데 폰이 도착 칸에 남았다")
        #expect(cancelled.pendingDropRecord == nil, "취소가 꼬리표를 안 지웠다")
        #expect(dsMoveCalls(cancelHost).isEmpty, "취소했는데 수가 나갔다")
        #expect(cancelled.match?.position?[a7] == ChessPiece(.white, .pawn))

        // 고르는 중의 판 탭·새 끌기도 접는다(기존 탭 규칙) — 그때도 폰은 돌아간다.
        let (tapped, tapHost) = try dsPlayable("promo-tap", line)
        #expect(tapped.beginDrag(from: a7))
        await tapped.drop(from: a7, on: a8)
        await tapped.tap(try dsSquare("e1"))
        #expect(tapped.promotion == nil)
        #expect(tapped.pendingDropRecord == nil, "판 탭이 고르기를 접었는데 꼬리표가 남았다")

        let (regrabbed, grabHost) = try dsPlayable("promo-regrab", line)
        #expect(regrabbed.beginDrag(from: a7))
        await regrabbed.drop(from: a7, on: a8)
        #expect(regrabbed.beginDrag(from: try dsSquare("e1")))
        #expect(regrabbed.promotion == nil)
        #expect(regrabbed.pendingDropRecord == nil, "새 끌기가 고르기를 접었는데 꼬리표가 남았다")
        #expect(dsMoveCalls(tapHost).isEmpty && dsMoveCalls(grabHost).isEmpty)

        // ★ 기준선: **클릭으로** 온 승격에는 꼬리표가 없다(폰이 출발 칸에 그려진 채로 묻는다 — 지금 그대로).
        let (clicked, _) = try dsPlayable("promo-click", line)
        await clicked.tap(a7)
        await clicked.tap(a8)
        #expect(clicked.promotion == ChessPromotionPrompt(from: a7, to: a8))
        #expect(clicked.pendingDropRecord == nil, "클릭 길이 꼬리표를 세웠다")
    }

    // MARK: - ⑤ pendingDrop 의 수명 — 성공 · 서버 거절 · 네트워크 실패 · 판 교체, 그리고 자기 치유

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func theDroppedPieceWaitsOnItsSquareWhileTheServerAnswers() async throws {
        // 없으면: 1:1 판에서 답을 기다리는 100~300ms 동안 말이 출발 칸에 도로 그려져(꼬리표가 안 서서)
        //        "놓았는데 되돌아갔다가 다시 간다" 가 되어도 초록이다.
        let line = try dsLine(["e2e4"])
        let reply = dsBody(dsStateJSON(ply: 1, line))
        let (store, host) = dsStore("wait", handler: { rpc, _, _ in
            rpc == "chess_move" ? GomokuStubProtocol.Reply(body: reply, delay: 0.5)     // 늦게 도착한다
                                : GomokuStubProtocol.Reply(status: 404, body: #"{"code":"PGRST202"}"#)
        })
        store.applyState(try dsDecode(dsStateJSON(ply: 0, line)))
        let e2 = try dsSquare("e2"), e4 = try dsSquare("e4")
        let waiting = ChessPendingDrop(matchID: dsMatch, ply: 0, from: e2, to: e4, piece: ChessPiece(.white, .pawn))

        #expect(store.beginDrag(from: e2))
        // 동기 구간: **await 없이** 꼬리표가 선다(뷰가 마우스를 뗀 그 틱이다).
        let move = try #require(store.placeDrop(from: e2, on: e4))
        #expect(move.uci == "e2e4")
        #expect(store.pendingDrop == waiting, "놓은 그 자리에서 꼬리표가 안 섰다 — 한 장이 출발 칸으로 번쩍인다")
        #expect(store.dragOrigin == nil)
        #expect(store.selection == nil)
        #expect(dsMoveCalls(host).isEmpty)

        let sending = Task { @MainActor in await store.finishDrop(move) }
        await dsWait { GomokuStubProtocol.count(host: host, rpc: "chess_move") == 1 }
        // 답을 기다리는 중: 판은 **그대로**(서버가 권위다)이고 꼬리표만 말을 도착 칸에 세운다.
        #expect(store.isBusy)
        #expect(store.match?.plyCount == 0, "답이 오기 전에 판이 바뀌었다 — 낙관적 착수다")
        #expect(store.match?.position?[e2] == ChessPiece(.white, .pawn))
        #expect(store.pendingDrop == waiting, "답을 기다리는 동안 말이 도착 칸에 안 머문다")

        await sending.value
        #expect(store.match?.plyCount == 1)
        #expect(store.pendingDrop == nil)
        #expect(store.pendingDropRecord == nil)
        #expect(!store.isBusy)
        #expect(dsMoveCalls(host) == ["e2e4"])
    }

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func aRefusedOrFailedDropGoesBackToItsSquare() async throws {
        // 없으면: 서버가 거절했는데(또는 연결이 끊겼는데) 놓은 말이 도착 칸에 **유령으로 남아도** 초록이다.
        let line = try dsLine(["e2e4"])
        let e2 = try dsSquare("e2"), e4 = try dsSquare("e4")

        // 서버 거절(illegal) — 서버는 건드리지 않은 판을 되돌려 준다.
        let refusedState = dsBody(dsStateJSON(ply: 0, line, status: "illegal"))
        let (refused, refusedHost) = dsStore("refused", handler: dsHandler([
            "chess_move": [refusedState], "chess_state": [dsBody(dsStateJSON(ply: 0, line))],
        ]))
        refused.applyState(try dsDecode(dsStateJSON(ply: 0, line)))
        #expect(refused.beginDrag(from: e2))
        await refused.drop(from: e2, on: e4)
        #expect(dsMoveCalls(refusedHost) == ["e2e4"], "전제: 수는 한 건 나갔다")
        #expect(refused.match?.plyCount == 0)
        #expect(refused.pendingDrop == nil, "거절된 말이 도착 칸에 남았다")
        #expect(refused.pendingDropRecord == nil, "거절이 꼬리표를 안 지웠다")
        #expect(refused.notice == ChessNoticeText.illegalMove, "기존 안내 문구가 달라졌다: \(refused.notice ?? "무음")")
        #expect(refused.match?.position?[e2] == ChessPiece(.white, .pawn))
        #expect(!refused.isBusy)

        // 네트워크 실패(5xx).
        let (failed, failedHost) = dsStore("failed", handler: { rpc, _, _ in
            rpc == "chess_move" ? GomokuStubProtocol.Reply(status: 500, body: #"{"message":"boom"}"#)
                                : GomokuStubProtocol.Reply(status: 404, body: #"{"code":"PGRST202"}"#)
        })
        failed.applyState(try dsDecode(dsStateJSON(ply: 0, line)))
        #expect(failed.beginDrag(from: e2))
        await failed.drop(from: e2, on: e4)
        #expect(dsMoveCalls(failedHost) == ["e2e4"])
        #expect(failed.pendingDrop == nil, "보내지 못한 말이 도착 칸에 남았다")
        #expect(failed.pendingDropRecord == nil)
        #expect(failed.notice == ChessNoticeText.checkConnection)
        #expect(failed.match?.plyCount == 0)

        // 거절된 뒤에 **클릭으로** 같은 수를 두면 평소대로 미끄러진다 — 낡은 꼬리표가 다음 수를 삼키지 않는다.
        let (retry, _) = dsStore("retry", handler: dsHandler([
            "chess_move": [refusedState, dsBody(dsStateJSON(ply: 1, line))],
            "chess_state": [dsBody(dsStateJSON(ply: 0, line))],
        ]))
        retry.applyState(try dsDecode(dsStateJSON(ply: 0, line)))
        #expect(retry.beginDrag(from: e2))
        await retry.drop(from: e2, on: e4)
        #expect(retry.match?.plyCount == 0)
        await retry.tap(e2)
        await retry.tap(e4)
        #expect(retry.match?.plyCount == 1)
        #expect(retry.flight?.sliders.map(\.from) == [e2], "거절된 끌기의 꼬리표가 다음 클릭 수의 미끄러짐을 지웠다")
    }

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func aStalePendingDropReadsAsAbsentEvenWhenNobodyClearedIt() async throws {
        // 없으면: 지우는 자리를 하나 놓친 날 **판에 없는 말**이 그려진 채 남는다(이 기능의 최악의 버그).
        //        그래서 "지웠다" 가 아니라 "남아 있는데도 없는 것으로 읽힌다" 를 잰다 — 원본은 일부러 그대로 둔다.
        let line = try dsLine(["e2e4"])
        let e2 = try dsSquare("e2"), e4 = try dsSquare("e4")
        let record = ChessPendingDrop(matchID: dsMatch, ply: 0, from: e2, to: e4, piece: ChessPiece(.white, .pawn))

        /// 놓고 **아직 안 보낸** 스토어(꼬리표만 서 있다 — 왕복이 지우기 전의 순간이다).
        func placed(_ label: String) throws -> ChessStore {
            let (store, _) = try dsPlayable(label, line)
            #expect(store.beginDrag(from: e2))
            #expect(store.placeDrop(from: e2, on: e4)?.uci == "e2e4")
            #expect(store.pendingDrop == record, "전제: 꼬리표가 섰다")
            return store
        }
        func mutated(_ store: ChessStore, _ change: (inout ChessMatchState) -> Void) throws {
            var next = try #require(store.match)
            change(&next)
            store.match = next                  // 깔때기를 안 거친다 — `beginFlight` 도 명시적 지움도 안 불린다
        }

        // ★ 기준선: 아무것도 안 바뀌면 그대로 읽힌다.
        let untouched = try placed("heal-none")
        try mutated(untouched) { $0.drawOfferBy = dsBlackID }        // 판의 **다른 칸**만 바뀐 갱신
        #expect(untouched.pendingDrop == record, "무관한 갱신에 놓은 말이 출발 칸으로 튄다")

        // (가) 수 번호가 올랐다 — 그 말은 이미 판에 그려져 있다.
        let advanced = try placed("heal-ply")
        try mutated(advanced) { $0.plyCount = 1 }
        #expect(advanced.pendingDropRecord == record, "전제: 원본은 아무도 안 지웠다")
        #expect(advanced.pendingDrop == nil, "수 번호가 달라졌는데 놓은 말이 그려진다")

        // (나) 같은 수 번호인데 판이 끝났다(상대 기권·시간패) — 기다릴 답이 없다.
        let ended = try placed("heal-finished")
        try mutated(ended) { $0.isFinished = true; $0.turn = nil }
        #expect(ended.pendingDropRecord == record)
        #expect(ended.pendingDrop == nil, "끝난 판에 놓은 말이 그려진다")

        // (다) 같은 수 번호인데 내 차례가 아니다.
        let flipped = try placed("heal-turn")
        try mutated(flipped) { $0.turn = .black }
        #expect(flipped.pendingDropRecord == record)
        #expect(flipped.pendingDrop == nil)

        // (라) 출발 칸의 말이 달라졌다(판이 다시 읽혔다).
        let reread = try placed("heal-piece")
        let elsewhere = try #require(ChessPosition(fen: "rnbqkbnr/pppppppp/8/8/8/4P3/PPPP1PPP/RNBQKBNR w KQkq - 0 1"))
        try mutated(reread) { $0.position = elsewhere }
        #expect(reread.pendingDropRecord == record)
        #expect(reread.pendingDrop == nil, "출발 칸에 그 말이 없는데 놓은 말이 그려진다")

        // (마) 판이 갈렸다 — 읽는 자리도 없다고 읽고, `match` 관찰자가 원본도 지운다.
        let swapped = try placed("heal-match")
        swapped.applyState(try dsDecode(dsStateJSON(matchID: dsOtherMatch, ply: 0, line)))
        #expect(swapped.match?.id == dsOtherMatch)
        #expect(swapped.pendingDrop == nil, "다른 판에 앞 판의 말이 그려진다")
        #expect(swapped.pendingDropRecord == nil)
        // 그리고 놓은 수는 **새 판으로 나가지 않는다**(새 판에서도 e2e4 는 합법이다 — 그래서 위험하다).
        let (lateStore, lateHost) = try dsPlayable("heal-late", line)
        #expect(lateStore.beginDrag(from: e2))
        let late = try #require(lateStore.placeDrop(from: e2, on: e4))
        lateStore.applyState(try dsDecode(dsStateJSON(matchID: dsOtherMatch, ply: 0, line)))
        await lateStore.finishDrop(late)
        #expect(dsMoveCalls(lateHost).isEmpty, "앞 판에서 놓은 수가 새 판으로 나갔다")

        // (바) 명시적으로 지우는 자리들: 판 내림 · 로그아웃 · 창 숨김 · 창 닫힘.
        let cleared = try placed("heal-clear")
        cleared.clearMatch()
        #expect(cleared.pendingDropRecord == nil)
        let hidden = try placed("heal-hide")
        hidden.windowDidHide()
        #expect(hidden.pendingDropRecord == nil, "창을 숨겼는데 꼬리표가 남았다")
        #expect(hidden.match != nil, "전제: 창 숨김은 판을 안 내린다 — 자기 치유가 아니라 지워서 없다")
        let closed = try placed("heal-close")
        closed.windowDidClose()
        #expect(closed.pendingDropRecord == nil)
        let reset = try placed("heal-reset")
        reset.reset()
        #expect(reset.pendingDropRecord == nil)
        // 가림은 지우지 않는다(가림 통지는 틀릴 수 있다 — 보이는 창에서 기다리던 말이 튀면 안 된다).
        let occluded = try placed("heal-occluded")
        occluded.windowOcclusionDidChange(visible: false)
        #expect(occluded.pendingDrop == record, "가림 통지에 놓은 말이 출발 칸으로 튄다")
    }

    // MARK: - ⑥ 끌어 둔 수는 그 말이 애니메이션에 없고, 클릭으로 둔 같은 수는 있다

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func aDroppedMoveDoesNotSlideAgainWhileTheSameClickedMoveDoes() async throws {
        // 없으면: 끌어 놓은 말이 출발 칸으로 되돌아갔다가 다시 미끄러진다(가장 눈에 띄는 결함). 또는 반대로
        //        "미끄러짐을 통째로 꺼서" 클릭으로 둔 수까지 순간이동해도 초록이다.
        let line = try dsLine(["e2e4", "e7e5"])
        let e2 = try dsSquare("e2"), e4 = try dsSquare("e4")

        let (dragged, dragHost) = try dsPlayable("slide-drag", line)
        #expect(dragged.beginDrag(from: e2))
        await dragged.drop(from: e2, on: e4)
        #expect(dragged.match?.plyCount == 1)
        #expect(dragged.flight == nil, "끌어 놓은 말이 다시 미끄러졌다: \(String(describing: dragged.flight?.sliders))")

        // ★ 대조군: **같은 수**를 클릭으로 두면 그 말이 미끄러진다.
        let (clicked, clickHost) = try dsPlayable("slide-click", line)
        await clicked.tap(e2)
        await clicked.tap(e4)
        #expect(clicked.match?.plyCount == 1)
        let flight = try #require(clicked.flight, "클릭으로 둔 수가 안 미끄러진다 — 클릭 동작이 바뀌었다")
        #expect(flight.sliders == [ChessMoveFlight.Slider(piece: ChessPiece(.white, .pawn), from: e2, to: e4)])
        #expect(flight.landed == nil)
        #expect(flight.frame(now: dsT0)?.moving.map(\.piece) == [ChessPiece(.white, .pawn)])
        // 두 길이 서버에 보낸 것은 같다.
        #expect(dsMoveCalls(dragHost) == ["e2e4"])
        #expect(dsMoveCalls(clickHost) == ["e2e4"])
        #expect(dragged.match == clicked.match, "끌어 둔 판과 클릭으로 둔 판이 다르다")

        // 내가 끌어 둔 뒤 온 **상대 수**는 온전히 미끄러진다(꼬리표가 다음 수까지 먹으면 안 된다).
        dragged.applyState(try dsDecode(dsStateJSON(ply: 2, line)))
        let theirs = try #require(dragged.flight, "끌어 둔 뒤 상대 수가 순간이동한다")
        #expect(theirs.move.uci == "e7e5")
        #expect(theirs.sliders == [ChessMoveFlight.Slider(piece: ChessPiece(.black, .pawn),
                                                          from: try dsSquare("e7"), to: try dsSquare("e5"))])
        #expect(theirs.landed == nil)
        #expect(theirs.frame(now: dsT0)?.moving.count == 1)
    }

    // MARK: - ⑦ 캐슬링을 왕 끌기로 두면 룩은 미끄러진다

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func castlingByDraggingTheKingStillSlidesTheRook() async throws {
        // 없으면: 끌어 놓은 수의 애니메이션을 통째로 지워 룩이 h1 에서 f1 으로 **순간이동**해도 초록이다.
        let line = try dsLine(["e1g1"], from: dsCastleFEN)
        let e1 = try dsSquare("e1"), g1 = try dsSquare("g1")
        let rook = ChessMoveFlight.Slider(piece: ChessPiece(.white, .rook),
                                          from: try dsSquare("h1"), to: try dsSquare("f1"))
        let king = ChessMoveFlight.Slider(piece: ChessPiece(.white, .king), from: e1, to: g1)

        let (dragged, host) = try dsPlayable("castle-drag", line)
        #expect(dragged.beginDrag(from: e1))
        await dragged.drop(from: e1, on: g1)
        #expect(dsMoveCalls(host) == ["e1g1"])
        let flight = try #require(dragged.flight, "왕을 끌어 캐슬링했더니 룩이 순간이동한다")
        #expect(flight.sliders == [rook], "움직이는 말이 룩 하나가 아니다: \(flight.sliders)")
        #expect(flight.landed == g1)
        #expect(flight.knockout == nil)
        let frame = try #require(flight.frame(now: dsT0))
        #expect(frame.moving.map(\.piece) == [ChessPiece(.white, .rook)], "끌어 놓은 왕이 moving 에 있다")
        #expect(frame.hidden == [try dsSquare("f1")], "숨기는 칸이 룩의 도착 칸 하나가 아니다")
        #expect(frame.landed == g1)

        // ★ 대조군: 클릭으로 둔 캐슬링은 둘 다 미끄러지고, 룩은 **같은 길이**로 간다.
        let (clicked, _) = try dsPlayable("castle-click", line)
        await clicked.tap(e1)
        await clicked.tap(g1)
        let both = try #require(clicked.flight)
        #expect(both.sliders == [rook, king])
        #expect(both.landed == nil)
        #expect(flight.slideDuration == both.slideDuration, "끌어 둔 캐슬링의 룩이 다른 속도로 간다")
        #expect(flight.duration == both.duration)
    }

    // MARK: - ⑧ 잡는 수는 잡힌 말이 밀려난다(앙파상 포함)

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func capturingByDragStillKnocksTheCapturedPieceOut() async throws {
        // 없으면: 끌어서 잡으면 잡힌 말이 그 프레임에 **사라진다**(0.3.44 가 고친 증상으로 되돌아간다).
        let line = try dsLine(["e2e4", "d7d5", "e4d5"])
        let e4 = try dsSquare("e4"), d5 = try dsSquare("d5")

        let (dragged, host) = try dsPlayable("capture-drag", line, ply: 2)
        #expect(dragged.beginDrag(from: e4))
        await dragged.drop(from: e4, on: d5)
        #expect(dsMoveCalls(host) == ["e4d5"])
        let flight = try #require(dragged.flight, "끌어서 잡았더니 잡힌 말이 그냥 사라진다")
        #expect(flight.sliders.isEmpty, "끌어 놓은 말이 미끄러진다: \(flight.sliders)")
        #expect(flight.landed == d5)
        let knockout = try #require(flight.knockout)
        #expect(knockout.piece == ChessPiece(.black, .pawn))
        #expect(knockout.square == d5)
        #expect(knockout.pushFile == -1 && knockout.pushRank == 1, "밀려나는 방향이 잡은 말이 온 방향이 아니다")
        // 잡은 말은 이미 도착해 있다 — 밀림은 기다리지 않고 곧바로 시작한다.
        #expect(flight.knockoutDelay == 0)
        #expect(flight.duration == ChessMoveFlight.knockoutSeconds)
        let first = try #require(flight.frame(now: dsT0))
        #expect(first.moving.isEmpty)
        #expect(first.leaving?.piece == ChessPiece(.black, .pawn), "첫 프레임에 잡힌 말이 없다")
        #expect(first.leaving?.opacity == 1)
        #expect(first.hidden.isEmpty, "도착 칸을 숨겼다 — 끌어 놓은 말이 사라진다")
        #expect(first.landed == d5)

        // ★ 대조군: 클릭으로 잡으면 잡는 말이 미끄러지고, 밀림은 그 말이 절반쯤 온 뒤에 시작한다.
        let (clicked, _) = try dsPlayable("capture-click", line, ply: 2)
        await clicked.tap(e4)
        await clicked.tap(d5)
        let slid = try #require(clicked.flight)
        #expect(slid.sliders.map(\.from) == [e4])
        #expect(slid.knockout == knockout, "잡힌 말의 모양(말·칸·방향)이 두 길에서 다르다")
        #expect(slid.knockoutDelay > 0)

        // 앙파상 — 잡힌 폰은 도착 칸이 아니라 **지나친 칸**에서 밀려난다.
        let passant = try dsLine(["d5e6"], from: dsEnPassantFEN)
        let (store, _) = try dsPlayable("capture-ep", passant)
        #expect(store.beginDrag(from: try dsSquare("d5")))
        await store.drop(from: try dsSquare("d5"), on: try dsSquare("e6"))
        let ep = try #require(store.flight, "끌어서 앙파상으로 잡았더니 잡힌 폰이 그냥 사라진다")
        #expect(ep.sliders.isEmpty)
        #expect(ep.knockout?.square == (try dsSquare("e5")), "잡힌 폰의 칸이 e5 가 아니다")
        #expect(ep.knockout?.piece == ChessPiece(.black, .pawn))
        #expect(ep.landed == (try dsSquare("e6")))
    }

    // MARK: - ⑧b 끌어 놓은 수의 사본 — 빠지는 것은 그 말 하나와 '기다림' 뿐이다

    @Test
    func theLandedCopyOnlyRemovesTheMoverAndTheWait() throws {
        // 없으면: 끌어 놓은 수의 애니메이션이 클릭으로 둔 수와 **다른 모양**으로 굴러도(밀리는 거리·방향·흐려짐,
        //        룩의 속도) 초록이다. 달라져도 되는 것은 둘뿐이다 — 그 말이 없고, 밀림이 기다리지 않는다.
        func flight(_ uci: String, before: ChessPosition) throws -> ChessMoveFlight {
            let move = try #require(ChessMove(uci: uci))
            let after = try #require(ChessRules.apply(move, to: before))
            return try #require(ChessMoveFlight.make(move: move, before: before, after: after, matchID: dsMatch,
                                                     ply: 1, generation: 1, startedAt: dsT0))
        }

        // 잡기도 캐슬링도 아닌 수 — 남는 것이 없다.
        #expect(try flight("e2e4", before: .standard).withMoverLanded() == nil)

        // 잡는 수: 밀림의 **모든 프레임**이 클릭으로 둔 수의 같은 진행도 프레임과 같다(시작만 앞당겨졌다).
        let capturePosition = try #require(ChessPosition(
            fen: "rnbqkbnr/ppp1pppp/8/3p4/4P3/8/PPPP1PPP/RNBQKBNR w KQkq d6 0 2"))
        let clicked = try flight("e4d5", before: capturePosition)
        let landed = try #require(clicked.withMoverLanded())
        #expect(landed.sliders.isEmpty)
        #expect(landed.knockout == clicked.knockout)
        #expect(landed.knockoutDuration == clicked.knockoutDuration)
        #expect(clicked.knockoutDelay > 0, "전제: 클릭으로 둔 수는 밀림이 기다린다")
        #expect(landed.knockoutDelay == 0)
        #expect(landed.landed == (try dsSquare("d5")))
        #expect(landed.matchID == clicked.matchID && landed.ply == clicked.ply
                && landed.generation == clicked.generation && landed.move == clicked.move
                && landed.startedAt == clicked.startedAt)
        for step in 0...10 {
            let into = clicked.knockoutDuration * Double(step) / 10 * 0.999      // 끝의 열린 경계 바로 안쪽
            let mine = try #require(landed.frame(now: dsT0.addingTimeInterval(into))?.leaving,
                                    "밀림 \(step)/10 에서 잡힌 말이 없다")
            let theirs = try #require(
                clicked.frame(now: dsT0.addingTimeInterval(clicked.knockoutDelay + into))?.leaving)
            #expect(mine.piece == theirs.piece && mine.square == theirs.square)
            #expect(abs(mine.fileOffset - theirs.fileOffset) < 1e-9 && abs(mine.rankOffset - theirs.rankOffset) < 1e-9,
                    "밀림 \(step)/10 의 자리가 다르다")
            #expect(abs(mine.scale - theirs.scale) < 1e-9 && abs(mine.opacity - theirs.opacity) < 1e-9)
        }
        // 다 밀려나면 끝난다(헛되이 깨어 있지 않는다).
        #expect(landed.isFinished(now: dsT0.addingTimeInterval(landed.knockoutDuration + 0.001)))
        #expect(!landed.isFinished(now: dsT0.addingTimeInterval(landed.knockoutDuration - 0.001)))

        // 캐슬링: 룩의 **모든 프레임**이 클릭으로 둔 캐슬링의 룩과 같다.
        let castlePosition = try #require(ChessPosition(fen: dsCastleFEN))
        let castled = try flight("e1g1", before: castlePosition)
        let kingLanded = try #require(castled.withMoverLanded())
        #expect(kingLanded.slideDuration == castled.slideDuration)
        for step in 0...10 {
            let now = dsT0.addingTimeInterval(castled.slideDuration * Double(step) / 10 * 0.999)
            let mine = try #require(kingLanded.frame(now: now))
            let theirs = try #require(castled.frame(now: now))
            #expect(mine.moving == theirs.moving.filter { $0.piece.kind == .rook }, "룩의 \(step)/10 프레임이 다르다")
            #expect(mine.moving.count == 1 && theirs.moving.count == 2)
            #expect(mine.landed == (try dsSquare("g1")) && theirs.landed == nil)
        }

        // 두 번 빼도 같은 값이다(이미 뺀 사본에는 뺄 말이 없다).
        #expect(landed.withMoverLanded() == landed)
        #expect(kingLanded.withMoverLanded() == kingLanded)
    }

    // MARK: - ⑨ 꼬리표는 **그 수**에만 쓰인다

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func thePendingDropOnlySparesItsOwnMove() async throws {
        // 없으면: 놓은 뒤 판이 **다른 수**로 나아갔는데(같은 계정의 다른 기기) 그 수가 내 손이 옮긴 것처럼
        //        안 미끄러지거나, 창이 가려진 동안 나아간 수의 꼬리표가 남아 다음 수를 삼켜도 초록이다.
        let mine = try dsLine(["e2e4"])
        let other = try dsLine(["d2d4"])
        let e2 = try dsSquare("e2"), e4 = try dsSquare("e4")

        // 다른 수로 나아갔다 — 평소대로 미끄러지고 꼬리표는 걷힌다.
        let (store, _) = try dsPlayable("own-other", mine)
        #expect(store.beginDrag(from: e2))
        #expect(store.placeDrop(from: e2, on: e4) != nil)
        store.applyState(try dsDecode(dsStateJSON(ply: 1, other)))
        #expect(store.pendingDropRecord == nil)
        #expect(store.flight?.sliders.map(\.from) == [try dsSquare("d2")], "다른 수가 안 미끄러진다")
        #expect(store.flight?.landed == nil)

        // 수 번호가 그대로인 응답(폴링)은 꼬리표를 안 건드린다 — 아직 답이 아니다.
        let (polled, _) = try dsPlayable("own-poll", mine)
        #expect(polled.beginDrag(from: e2))
        #expect(polled.placeDrop(from: e2, on: e4) != nil)
        polled.applyState(try dsDecode(dsStateJSON(ply: 0, mine)))
        #expect(polled.pendingDrop != nil, "폴링 응답에 놓은 말이 출발 칸으로 튄다")

        // 창이 가려진 동안 답이 왔다 — 애니메이션은 안 서지만 꼬리표는 걷힌다.
        let (occluded, _) = try dsPlayable("own-occluded", mine)
        #expect(occluded.beginDrag(from: e2))
        #expect(occluded.placeDrop(from: e2, on: e4) != nil)
        occluded.windowOcclusionDidChange(visible: false)
        occluded.applyState(try dsDecode(dsStateJSON(ply: 1, mine)))
        #expect(occluded.flight == nil)
        #expect(occluded.pendingDropRecord == nil, "가려진 채 나아간 수의 꼬리표가 남았다")
    }

    // MARK: - ⑩ 끄는 중에 판이 바뀌면 끌기를 거두고, 그 뒤 놓아도 수가 안 나간다

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func everyRevocationPathDropsTheDragAndBlocksTheLateDrop() async throws {
        // 없으면: 끄는 중에 상대가 기권했는데(또는 판이 바뀌었는데 · 창이 가려졌다 돌아왔는데) 그 뒤 뗀 마우스가
        //        **수를 낸다**. 가장 나쁜 꼴은 판 교체다 — 새 판에서도 e2e4 가 합법이라 엉뚱한 판에 수가 떨어진다.
        let line = try dsLine(["g1f3", "g8f6"])
        let e2 = try dsSquare("e2"), e4 = try dsSquare("e4")

        struct Revocation {
            let label: String
            let revoke: @MainActor (ChessStore) throws -> Void
            /// 계기가 지나간 뒤 되돌아오는 조건을 **원래대로** 돌려놓는다 — 그래도 한 번 내려간 걸쇠는 안 걸린다.
            var restore: @MainActor (ChessStore) -> Void = { _ in }
        }
        let paths: [Revocation] = [
            Revocation(label: "상대 기권·시간패(끝난 판)", revoke: { store in
                store.applyState(try dsDecode(dsStateJSON(ply: 0, line, finished: true)))
            }),
            Revocation(label: "판 교체", revoke: { store in
                store.applyState(try dsDecode(dsStateJSON(matchID: dsOtherMatch, ply: 0, line)))
            }),
            Revocation(label: "수가 나아감(다시 내 차례)", revoke: { store in
                store.applyState(try dsDecode(dsStateJSON(ply: 2, line)))
            }),
            Revocation(label: "내 차례가 꺼짐", revoke: { store in
                store.applyState(try dsDecode(dsStateJSON(ply: 1, line)))
            }),
            Revocation(label: "왕복 중", revoke: { $0.isBusy = true }),
            Revocation(label: "창 숨김(최소화) 뒤 다시 보임", revoke: { $0.windowDidHide() },
                 restore: { $0.isWindowVisible = true }),
            Revocation(label: "창 닫힘", revoke: { $0.windowDidClose() }),
            Revocation(label: "창 가림 뒤 다시 보임", revoke: { $0.windowOcclusionDidChange(visible: false) },
                 restore: { $0.windowOcclusionDidChange(visible: true) }),
            Revocation(label: "판 내림", revoke: { $0.clearMatch() }),
            Revocation(label: "로그아웃", revoke: { $0.reset() }),
            Revocation(label: "뷰가 거둠", revoke: { $0.cancelDrag() }),
        ]

        for path in paths {
            let (store, host) = try dsPlayable("revoke", line)
            #expect(store.beginDrag(from: e2))
            #expect(store.dragOrigin == e2)
            try path.revoke(store)
            if path.label != "왕복 중" {
                // 왕복은 놓는 순간의 사다리가 막는다(걸쇠가 아니라). 나머지는 **계기가 온 그 자리에서** 걸쇠가 내려간다.
                #expect(store.dragOrigin == nil, "\(path.label): 끌기가 살아 있다 — 말이 손에 붙은 채다")
            }
            path.restore(store)
            await store.drop(from: e2, on: e4)
            #expect(dsMoveCalls(host).isEmpty, "\(path.label): 끌기를 거둔 뒤 놓았는데 수가 나갔다 \(dsMoveCalls(host))")
            #expect(store.pendingDrop == nil, "\(path.label): 놓은 말이 그려진다")
            #expect(store.pendingDropRecord == nil, "\(path.label): 꼬리표가 섰다")
            #expect(store.dragOrigin == nil)
            // 왕복이 풀린 뒤에 다시 놓아도 안 나간다 — 거절된 놓기가 걸쇠를 내렸다.
            if path.label == "왕복 중" {
                store.isBusy = false
                await store.drop(from: e2, on: e4)
                #expect(dsMoveCalls(host).isEmpty, "왕복이 풀리자 앞서 거절된 놓기가 되살아났다")
            }
        }

        // 폴링 응답(시계·무승부 제안만 바뀐 같은 수 번호)은 끌기를 **안** 끊는다.
        let (steady, steadyHost) = try dsPlayable("revoke-none", line)
        #expect(steady.beginDrag(from: e2))
        var offer = dsStateJSON(ply: 0, line)
        var row = try #require(offer["match"] as? [String: Any])
        row["draw_offer_by"] = dsBlackID
        row["white_ms_left"] = 250_000
        offer["match"] = row
        steady.applyState(try dsDecode(offer))
        #expect(steady.match?.drawOfferedByOpponent == true, "전제: 판의 다른 칸이 실제로 바뀌었다")
        #expect(steady.dragOrigin == e2, "무관한 갱신이 끌던 말을 손에서 떨군다")
        // ★ 기준선: 계기가 없으면 같은 놓기가 한 건 나간다.
        await steady.drop(from: e2, on: e4)
        #expect(dsMoveCalls(steadyHost) == ["e2e4"])
    }

    // MARK: - ⑪ 누른 칸에서 끌기가 되는가(해석기에 먹이는 값)

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func grabTellsThePointerWhatAPressCanBecome() async throws {
        // 없으면: 상대 말·빈 칸을 '끌 수 있다' 고 말해 끌기가 시작되거나, 내 차례인데 '못 끈다' 고 말해
        //        끌기가 통째로 죽어도 초록이다. 그리고 이 조회는 **아무것도 바꾸지 않아야** 한다.
        let line = try dsLine(["e2e4"])
        let (store, host) = try dsPlayable("grab", line)
        let before = store.match

        #expect(store.grab(at: try dsSquare("e2")) == .movable)
        #expect(store.grab(at: try dsSquare("g1")) == .movable)
        #expect(store.grab(at: try dsSquare("a1")) == .stuck, "갈 곳 없는 룩을 끌 수 있다고 말한다")
        #expect(store.grab(at: try dsSquare("e4")) == .none)
        #expect(store.grab(at: try dsSquare("e7")) == .none, "상대 말을 끌 수 있다고 말한다")
        // 순수 조회다.
        #expect(store.match == before)
        #expect(store.selection == nil && store.notice == nil && store.dragOrigin == nil)
        #expect(GomokuStubProtocol.calls(host: host).isEmpty)

        // 상대 차례: 내 말은 '못 끈다'(뗄 때 거절 한 번), 상대 말은 여전히 '아무것도 아니다'.
        store.applyState(try dsDecode(dsStateJSON(ply: 1, line)))
        #expect(store.grab(at: try dsSquare("d2")) == .stuck)
        #expect(store.grab(at: try dsSquare("e7")) == .none)
        let (empty, _) = dsStore("grab-empty", handler: dsHandler())
        #expect(empty.grab(at: try dsSquare("e2")) == .none, "판이 없는데 끌 수 있다고 말한다")
    }

    // MARK: - ⑫ 로봇 판 — 같은 묶음

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func theRobotBoardFollowsTheSameDragRules() async throws {
        // 없으면: 끌기가 1:1 깔때기(`applyState`)에만 붙어 로봇 판에서는 끌어 놓은 말이 다시 미끄러지거나,
        //        로봇 판의 수가 서버로 새어도 초록이다.
        let e2 = try dsSquare("e2"), e4 = try dsSquare("e4")

        // 평범한 수: 한 수 나아가고, 서버로는 0건이고, 끌어 놓은 말은 안 미끄러진다.
        let gate = DSRobotGate()
        // 나머지 판들의 로봇은 이 시험이 끝날 때까지 **안 둔다**(사람 수의 결과만 잰다). 끝에서 한 번에 푼다.
        let parked = DSRobotGate()
        let (store, host) = try dsRobotStore("robot-drag", gate: gate)
        #expect(store.grab(at: e2) == .movable)
        #expect(store.beginDrag(from: e2))
        await store.drop(from: e2, on: e4)
        #expect(store.match?.plyCount == 1)
        #expect(store.match?.lastMove?.uci == "e2e4")
        #expect(store.flight == nil, "로봇 판에서 끌어 놓은 말이 다시 미끄러졌다")
        #expect(store.pendingDrop == nil && store.pendingDropRecord == nil)
        #expect(store.selection == nil && store.dragOrigin == nil)
        // 로봇 차례에는 내 말을 못 끈다.
        #expect(store.grab(at: try dsSquare("d2")) == .stuck)
        #expect(!store.beginDrag(from: try dsSquare("d2")))
        #expect(store.notice == ChessNoticeText.notYourTurn)
        // 로봇의 답은 온전히 미끄러진다.
        await gate.open()
        await dsWait { store.flight?.ply == 2 }
        let robots = try #require(store.flight, "끌어 둔 뒤 로봇의 수가 순간이동한다")
        #expect(robots.sliders.count == 1)
        #expect(robots.landed == nil)
        #expect(GomokuStubProtocol.calls(host: host).isEmpty, "로봇 판이 서버에 요청을 냈다")

        // ★ 대조군: 같은 수를 클릭으로 두면 미끄러진다.
        let (clicked, _) = try dsRobotStore("robot-click", gate: parked)
        await clicked.tap(e2)
        await clicked.tap(e4)
        #expect(clicked.flight?.sliders.map(\.from) == [e2], "로봇 판에서 클릭으로 둔 수가 안 미끄러진다")

        // 둘 수 없는 자리들 — 0수.
        let (idle, _) = try dsRobotStore("robot-idle", gate: parked)
        #expect(idle.beginDrag(from: e2))
        await idle.drop(from: e2, on: e2)
        await idle.drop(from: e2, on: nil)
        #expect(idle.beginDrag(from: e2))
        await idle.drop(from: e2, on: try dsSquare("e5"))
        #expect(idle.match?.plyCount == 0, "둘 수 없는 자리에 놓았는데 로봇 판이 나아갔다")
        #expect(idle.notice == ChessNoticeText.cannotMove)
        #expect(idle.selection?.from == e2)

        // 잡는 수: 잡힌 말은 밀려나고 끌어 놓은 말은 안 미끄러진다.
        let captureFEN = "rnbqkbnr/ppp1pppp/8/3p4/4P3/8/PPPP1PPP/RNBQKBNR w KQkq d6 0 2"
        let (capture, _) = try dsRobotStore("robot-capture", fen: captureFEN, gate: parked)
        #expect(capture.beginDrag(from: e4))
        await capture.drop(from: e4, on: try dsSquare("d5"))
        let knocked = try #require(capture.flight, "로봇 판에서 끌어서 잡았더니 잡힌 말이 그냥 사라진다")
        #expect(knocked.sliders.isEmpty)
        #expect(knocked.knockout?.piece == ChessPiece(.black, .pawn))
        #expect(knocked.landed == (try dsSquare("d5")))

        // 캐슬링: 룩은 미끄러진다.
        let (castle, _) = try dsRobotStore("robot-castle", fen: dsCastleFEN, gate: parked)
        #expect(castle.beginDrag(from: try dsSquare("e1")))
        await castle.drop(from: try dsSquare("e1"), on: try dsSquare("g1"))
        #expect(castle.flight?.sliders.map(\.piece) == [ChessPiece(.white, .rook)])
        #expect(castle.flight?.landed == (try dsSquare("g1")))

        // 승격: 놓기 → 고르기 → 한 수 / 취소 → 0수.
        let a7 = try dsSquare("a7"), a8 = try dsSquare("a8")
        let (promo, _) = try dsRobotStore("robot-promo", fen: dsPromotionFEN, gate: parked)
        #expect(promo.beginDrag(from: a7))
        await promo.drop(from: a7, on: a8)
        #expect(promo.promotion == ChessPromotionPrompt(from: a7, to: a8))
        #expect(promo.match?.plyCount == 0, "고르기 전에 로봇 판이 나아갔다")
        #expect(promo.pendingDrop?.to == a8, "고르는 동안 폰이 도착 칸에 안 머문다")
        await promo.choosePromotion(.rook)
        #expect(promo.match?.plyCount == 1)
        #expect(promo.match?.position?[a8] == ChessPiece(.white, .rook))
        #expect(promo.pendingDropRecord == nil)
        #expect(promo.flight == nil, "끌어 놓은 승격 폰이 다시 미끄러졌다")

        let (cancelled, _) = try dsRobotStore("robot-promo-cancel", fen: dsPromotionFEN, gate: parked)
        #expect(cancelled.beginDrag(from: a7))
        await cancelled.drop(from: a7, on: a8)
        cancelled.cancelPromotion()
        #expect(cancelled.match?.plyCount == 0)
        #expect(cancelled.pendingDropRecord == nil)

        // 세워 둔 로봇들을 푼다 — 기다리는 작업을 남기고 끝내지 않는다.
        await parked.open()
    }

    // MARK: - ⑬ 놓은 직후의 틈 — 왕복이 시작되기 전의 다음 끌기·탭이 놓은 수를 지우지 않는다
    //
    // 뷰는 `placeDrop` 을 마우스를 뗀 그 자리에서 부르고 왕복(`finishDrop`)은 Task 로 넘긴다. 그 Task 가 돌기 전에
    // 처리된 다음 입력(이벤트가 밀려 한 턴에 몰릴 때)은 `isBusy == false` 인 스토어를 본다 — 여기서는 그 순서를
    // 그대로 부른다: 놓기(동기) → 다음 입력 → 왕복.

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func aGrabBetweenTheDropAndItsRoundTripDoesNotLoseTheMove() async throws {
        // 없으면: 틈에 시작한 끌기가 앞 수의 꼬리표를 지워 `finishDrop` 이 보낼 것이 없다 — 놓은 수가 **문구도
        //        로그도 없이 사라지고** 말은 출발 칸으로 돌아간다(사용자는 두었다고 믿은 채 시계가 흐른다).
        let line = try dsLine(["e2e4"])
        let e2 = try dsSquare("e2"), e4 = try dsSquare("e4"), d2 = try dsSquare("d2"), d4 = try dsSquare("d4")
        let waiting = ChessPendingDrop(matchID: dsMatch, ply: 0, from: e2, to: e4, piece: ChessPiece(.white, .pawn))

        // (가) 다른 말을 쥔 채로 답이 온다.
        let (store, host) = try dsPlayable("gap-grab", line)
        #expect(store.beginDrag(from: e2))
        let move = try #require(store.placeDrop(from: e2, on: e4))
        #expect(store.pendingDrop == waiting, "전제: 놓은 말이 도착 칸에 서 있다")
        // ↓ 틈 — `finishDrop` 은 아직 안 돌았다.
        #expect(!store.isBusy && store.grab(at: d2) == .movable, "전제: 틈에서는 다른 말이 집힌다")
        #expect(store.beginDrag(from: d2), "전제: 틈에서 다른 말을 집었다")
        #expect(store.pendingDrop == waiting, "틈에 시작한 끌기가 놓은 말을 출발 칸으로 돌려보냈다")
        #expect(store.dragOrigin == d2 && store.selection?.from == d2)

        await store.finishDrop(move)
        let calls = GomokuStubProtocol.calls(host: host, rpc: "chess_move")
        #expect(calls.count == 1, "놓은 수가 \(calls.count)건 나갔다 — 틈에 다른 말을 집었더니 사라졌다")
        #expect(calls.first?.json["p_uci"] as? String == "e2e4")
        #expect(calls.first?.json["p_expected_ply"] as? Int == 0)
        #expect(store.match?.plyCount == 1)
        #expect(store.match?.position?[e4] == ChessPiece(.white, .pawn))
        #expect(store.pendingDropRecord == nil)
        #expect(store.flight == nil, "틈에 다른 말을 집었더니 놓은 말이 다시 미끄러졌다")
        // 답이 판을 한 수 옮기면서 쥐고 있던 끌기는 걸쇠째 내려갔다 — 그 뒤 놓아도 **두 번째 수는 없다**.
        #expect(store.dragOrigin == nil && store.selection == nil, "판이 나아갔는데 쥐고 있던 끌기가 살아 있다")
        #expect(store.placeDrop(from: d2, on: d4) == nil)
        #expect(dsMoveCalls(host) == ["e2e4"], "답이 온 뒤 놓은 끌기가 수를 냈다: \(dsMoveCalls(host))")
        #expect(store.pendingDropRecord == nil)

        // (나) 다른 말을 쥔 채 **왕복 중에** 놓는다 — '보내는 중' 거절 한 번이고, 가고 있는 수는 그대로 간다.
        let reply = dsBody(dsStateJSON(ply: 1, line))
        let (slow, slowHost) = dsStore("gap-grab-busy", handler: { rpc, _, _ in
            rpc == "chess_move" ? GomokuStubProtocol.Reply(body: reply, delay: 0.5)
                                : GomokuStubProtocol.Reply(status: 404, body: #"{"code":"PGRST202"}"#)
        })
        slow.applyState(try dsDecode(dsStateJSON(ply: 0, line)))
        #expect(slow.beginDrag(from: e2))
        let slowMove = try #require(slow.placeDrop(from: e2, on: e4))
        #expect(slow.beginDrag(from: d2))
        let sending = Task { @MainActor in await slow.finishDrop(slowMove) }
        await dsWait { GomokuStubProtocol.count(host: slowHost, rpc: "chess_move") == 1 }
        #expect(slow.isBusy, "전제: 놓은 수가 가고 있다")
        #expect(slow.pendingDrop == waiting, "가고 있는 수의 말이 도착 칸에 안 머문다")
        #expect(slow.placeDrop(from: d2, on: d4) == nil)
        #expect(slow.notice == ChessNoticeText.sending, "왕복 중의 놓기가 '\(slow.notice ?? "무음")' 이라 말했다")
        #expect(slow.dragOrigin == nil)
        #expect(slow.pendingDrop == waiting, "거절된 놓기가 가고 있는 수의 말을 출발 칸으로 돌려보냈다")
        await sending.value
        #expect(dsMoveCalls(slowHost) == ["e2e4"], "왕복 중에 놓은 끌기가 수를 냈다: \(dsMoveCalls(slowHost))")
        #expect(slow.match?.plyCount == 1)
        #expect(slow.pendingDropRecord == nil && !slow.isBusy)
    }

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func aSecondDropInTheGapIsRefusedAndTheFirstMoveStillGoesOut() async throws {
        // 없으면: 틈 안에서 두 번째 끌기를 **놓기까지** 끝내면 그 놓기가 앞 수의 꼬리표를 덮는다 — 뒤이어 도는
        //        `finishDrop` 둘이 다 "내 수가 아니다" 로 물러나 chess_move 0건, 두 말이 문구 없이 출발 칸으로 돌아간다.
        let line = try dsLine(["e2e4"])
        let e2 = try dsSquare("e2"), e3 = try dsSquare("e3"), e4 = try dsSquare("e4")
        let d2 = try dsSquare("d2"), d4 = try dsSquare("d4")
        let waiting = ChessPendingDrop(matchID: dsMatch, ply: 0, from: e2, to: e4, piece: ChessPiece(.white, .pawn))

        // (가) 다른 말을 갈 수 있는 칸에 놓는다.
        let (store, host) = try dsPlayable("gap-second-drop", line)
        #expect(store.beginDrag(from: e2))
        let move = try #require(store.placeDrop(from: e2, on: e4))
        #expect(store.beginDrag(from: d2), "전제: 틈에서 다른 말을 집었다")
        #expect(store.placeDrop(from: d2, on: d4) == nil, "틈의 두 번째 놓기가 수를 돌려줬다")
        #expect(store.notice == ChessNoticeText.sending, "틈의 두 번째 놓기가 '\(store.notice ?? "무음")' 이라 말했다")
        #expect(store.dragOrigin == nil)
        #expect(store.pendingDrop == waiting, "두 번째 놓기가 보내기를 기다리는 수의 꼬리표를 덮었다")
        await store.finishDrop(move)
        #expect(dsMoveCalls(host) == ["e2e4"], "틈에서 두 번 놓았더니 나간 수가 \(dsMoveCalls(host)) 다")
        #expect(store.match?.plyCount == 1)
        #expect(store.pendingDropRecord == nil && !store.isBusy)

        // (나) 같은 말을 다시 집어 다른 칸에 놓는다 — 먼저 놓은 칸으로 나간다.
        let (same, sameHost) = try dsPlayable("gap-second-drop-same", line)
        #expect(same.beginDrag(from: e2))
        let first = try #require(same.placeDrop(from: e2, on: e4))
        #expect(same.beginDrag(from: e2), "전제: 틈에서 같은 말을 다시 집었다")
        #expect(same.placeDrop(from: e2, on: e3) == nil)
        #expect(same.notice == ChessNoticeText.sending)
        #expect(same.pendingDrop == waiting)
        await same.finishDrop(first)
        #expect(dsMoveCalls(sameHost) == ["e2e4"], "같은 말을 두 번 놓았더니 나간 수가 \(dsMoveCalls(sameHost)) 다")
        #expect(same.match?.plyCount == 1)
        #expect(same.pendingDropRecord == nil)
    }

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func aTapBetweenTheDropAndItsRoundTripDoesNotLoseTheMove() async throws {
        // 없으면: 틈에 온 **탭** 하나가 꼬리표를 지워 놓은 수가 조용히 사라진다(같은 결함의 다른 문).
        let line = try dsLine(["e2e4"])
        let e2 = try dsSquare("e2"), e4 = try dsSquare("e4"), d2 = try dsSquare("d2")
        let (store, host) = try dsPlayable("gap-tap", line)
        #expect(store.beginDrag(from: e2))
        let move = try #require(store.placeDrop(from: e2, on: e4))
        await store.tap(d2)
        #expect(store.selection?.from == d2, "전제: 틈에 온 탭은 평소대로 그 말을 골랐다")
        #expect(store.pendingDrop?.to == e4, "틈에 온 탭이 놓은 말을 출발 칸으로 돌려보냈다")

        await store.finishDrop(move)
        let calls = GomokuStubProtocol.calls(host: host, rpc: "chess_move")
        #expect(calls.count == 1, "놓은 수가 \(calls.count)건 나갔다 — 탭 하나에 사라졌다")
        #expect(calls.first?.json["p_uci"] as? String == "e2e4")
        #expect(store.match?.plyCount == 1)
        #expect(store.pendingDropRecord == nil)
        #expect(store.selection == nil, "판이 나아갔는데 앞 판에서 고른 말이 남았다")
        // ★ 대조: **승격을 고르던 중**의 탭·끌기는 여전히 꼬리표를 지운다(④ 의 promo-tap · promo-regrab).
    }

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func aGrabInTheGapOnTheRobotBoardDoesNotLoseTheMove() async throws {
        // 없으면: 로봇 판에서도 같은 틈이다 — 놓은 수가 판에 안 올라간다(서버가 없어 되물을 곳도 없다).
        let e2 = try dsSquare("e2"), e4 = try dsSquare("e4"), d2 = try dsSquare("d2"), d4 = try dsSquare("d4")
        let gate = DSRobotGate()
        let (store, host) = try dsRobotStore("robot-gap", gate: gate)
        #expect(store.beginDrag(from: e2))
        let move = try #require(store.placeDrop(from: e2, on: e4))
        #expect(store.beginDrag(from: d2), "전제: 틈에서 다른 말을 집었다")

        await store.finishDrop(move)
        #expect(store.match?.plyCount == 1, "로봇 판에서 놓은 수가 판에 안 올라갔다")
        #expect(store.match?.lastMove?.uci == "e2e4")
        #expect(store.flight == nil, "틈에 다른 말을 집었더니 놓은 말이 다시 미끄러졌다")
        #expect(store.pendingDropRecord == nil && store.dragOrigin == nil)
        // 쥐고 있던 끌기를 놓아도 로봇 차례라 두 번째 수는 없다.
        #expect(store.placeDrop(from: d2, on: d4) == nil)
        #expect(store.match?.plyCount == 1, "로봇 차례에 놓은 끌기가 판을 옮겼다")
        #expect(GomokuStubProtocol.calls(host: host).isEmpty, "로봇 판이 서버에 요청을 냈다")
        await gate.open()
        store.clearMatch()
    }

    // MARK: - ⑭ 서버가 거절한 끌기 — 놓은 말은 재조회를 기다리지 않고 돌아간다

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func aRefusedDropGoesBackBeforeTheSlowRereadReturns() async throws {
        // 없으면: 거절 문구("지금은 둘 수 없는 수예요")는 이미 떴는데 뒤따르는 재조회가 끝날 때까지 말이 도착 칸에
        //        그려진다 — 같은 판·같은 수 번호·내 차례·출발 칸에 그 말이라 자기 치유 넷이 전부 통과한다.
        //        재조회가 느리면 그만큼 남는다(요청 타임아웃 15초). ⑤ 의 거절 시험은 재조회가 즉답이라 이 구간을 못 본다.
        let e2 = try dsSquare("e2"), e4 = try dsSquare("e4")
        let a7 = try dsSquare("a7"), a8 = try dsSquare("a8")
        let line = try dsLine(["e2e4"])
        let promoting = try dsLine(["a7a8q"], from: dsPromotionFEN)

        /// 착수는 곧바로 거절하고(illegal) 재조회는 **늦게** 답하는 스토어.
        func refusing(_ label: String, _ line: DSLine) throws -> (ChessStore, String) {
            let refused = dsBody(dsStateJSON(ply: 0, line, status: "illegal"))
            let reread = dsBody(dsStateJSON(ply: 0, line))
            let (store, host) = dsStore(label, handler: { rpc, _, _ in
                switch rpc {
                case "chess_move": return GomokuStubProtocol.Reply(body: refused)
                case "chess_state": return GomokuStubProtocol.Reply(body: reread, delay: 0.6)
                default: return GomokuStubProtocol.Reply(status: 404, body: #"{"code":"PGRST202"}"#)
                }
            })
            store.applyState(try dsDecode(dsStateJSON(ply: 0, line)))
            return (store, host)
        }
        /// 거절 응답은 이미 반영됐고(문구가 떴다) 재조회가 **나가 있는** 순간의 단언.
        func expectGoneWhileRereading(_ store: ChessStore, _ host: String, _ label: String) async {
            await dsWait { GomokuStubProtocol.count(host: host, rpc: "chess_state") == 1 }
            #expect(GomokuStubProtocol.count(host: host, rpc: "chess_state") == 1, "전제(\(label)): 거절 뒤 재조회가 나갔다")
            #expect(store.notice == ChessNoticeText.illegalMove, "전제(\(label)): 거절 문구가 이미 떴다")
            #expect(store.isBusy, "전제(\(label)): 재조회가 아직 안 끝났다")
            #expect(store.match?.plyCount == 0)
            #expect(store.pendingDrop == nil, "\(label): 서버가 거절한 뒤에도 재조회가 끝날 때까지 놓은 말이 도착 칸에 그려진다")
            #expect(store.pendingDropRecord == nil, "\(label): 거절이 꼬리표를 재조회 뒤로 미뤘다")
        }

        // 끌어 놓은 수.
        let (store, host) = try refusing("refused-slow", line)
        #expect(store.beginDrag(from: e2))
        let move = try #require(store.placeDrop(from: e2, on: e4))
        #expect(store.pendingDrop != nil, "전제: 놓은 말이 도착 칸에 서 있다")
        let sending = Task { @MainActor in await store.finishDrop(move) }
        await expectGoneWhileRereading(store, host, "끌기")
        await sending.value
        #expect(dsMoveCalls(host) == ["e2e4"])
        #expect(!store.isBusy && store.pendingDropRecord == nil)
        #expect(store.match?.position?[e2] == ChessPiece(.white, .pawn))

        // 끌어 놓은 **승격**도 같은 `send` 를 지난다 — 폰이 재조회 내내 끝줄에 서 있으면 안 된다.
        let (promo, promoHost) = try refusing("refused-slow-promo", promoting)
        #expect(promo.beginDrag(from: a7))
        #expect(promo.placeDrop(from: a7, on: a8) == nil)
        #expect(promo.pendingDrop?.to == a8, "전제: 고르는 동안 폰이 도착 칸에 서 있다")
        let choosing = Task { @MainActor in await promo.choosePromotion(.queen) }
        await expectGoneWhileRereading(promo, promoHost, "승격")
        await choosing.value
        #expect(dsMoveCalls(promoHost) == ["a7a8q"])
        #expect(!promo.isBusy && promo.pendingDropRecord == nil)
    }

    // MARK: - ⑮ 거절·실패한 끌기-승격 — 폰이 끝줄에 유령으로 남지 않는다

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func aRefusedOrFailedPromotionByDragLeavesNoGhostPawn() async throws {
        // 없으면: 끌어 놓고 고른 승격을 서버가 거절했거나 보내지 못했는데 폰이 마지막 랭크에 **유령으로 남는다**
        //        (다음 탭까지) — 판에 없는 말이 그려지는, 이 기능의 최악의 부류다. ④ 는 성공·취소만 잰다.
        let line = try dsLine(["a7a8q"], from: dsPromotionFEN)
        let a7 = try dsSquare("a7"), a8 = try dsSquare("a8")
        let pawn = ChessPendingDrop(matchID: dsMatch, ply: 0, from: a7, to: a8, piece: ChessPiece(.white, .pawn))

        // 서버 거절(illegal) — 건드리지 않은 판이 되돌아온다.
        let (denied, deniedHost) = dsStore("promo-refused", handler: dsHandler([
            "chess_move": [dsBody(dsStateJSON(ply: 0, line, status: "illegal"))],
            "chess_state": [dsBody(dsStateJSON(ply: 0, line))],
        ]))
        denied.applyState(try dsDecode(dsStateJSON(ply: 0, line)))
        #expect(denied.beginDrag(from: a7))
        #expect(denied.placeDrop(from: a7, on: a8) == nil)
        #expect(denied.pendingDrop == pawn, "전제: 고르는 동안 폰이 도착 칸에 서 있다")
        await denied.choosePromotion(.queen)
        #expect(dsMoveCalls(deniedHost) == ["a7a8q"], "전제: 수는 한 건 나갔다")
        #expect(denied.notice == ChessNoticeText.illegalMove)
        #expect(denied.match?.plyCount == 0)
        #expect(denied.pendingDrop == nil, "거절된 승격의 폰이 끝줄에 남았다")
        #expect(denied.pendingDropRecord == nil, "거절된 승격이 꼬리표를 안 지웠다")
        #expect(denied.match?.position?[a7] == ChessPiece(.white, .pawn))

        // 네트워크 실패(5xx) — 판을 다시 읽지도 않는다. 꼬리표를 걷는 것은 `choosePromotion` 자신뿐이다.
        let (failed, failedHost) = dsStore("promo-failed", handler: { rpc, _, _ in
            rpc == "chess_move" ? GomokuStubProtocol.Reply(status: 500, body: #"{"message":"boom"}"#)
                                : GomokuStubProtocol.Reply(status: 404, body: #"{"code":"PGRST202"}"#)
        })
        failed.applyState(try dsDecode(dsStateJSON(ply: 0, line)))
        #expect(failed.beginDrag(from: a7))
        #expect(failed.placeDrop(from: a7, on: a8) == nil)
        #expect(failed.pendingDrop == pawn)
        await failed.choosePromotion(.rook)
        #expect(dsMoveCalls(failedHost) == ["a7a8r"])
        #expect(failed.notice == ChessNoticeText.checkConnection)
        #expect(failed.match?.plyCount == 0)
        #expect(failed.pendingDrop == nil, "보내지 못한 승격의 폰이 끝줄에 남았다")
        #expect(failed.pendingDropRecord == nil, "보내지 못한 승격이 꼬리표를 안 지웠다")
    }

    // MARK: - ⑯ 앞 수의 꼬리 — 조용한 수를 끌어 놓으면 돌고 있던 애니메이션이 거둬진다

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func aQuietDropEndsTheOpponentsSlideThatWasStillRunning() async throws {
        // 없으면: 끌어 놓은 조용한 수는 애니메이션을 세우지 않는다(움직일 것이 안 남는다). 그런데 그때 **상대 수의
        //        꼬리**가 아직 돌고 있었으면 그 값이 남아, 판은 이미 다음 수의 판인데 옛 수의 프레임이 그 위에 그려진다
        //        (그 꼬리가 숨기는 칸에 내 말이 놓였을 수도 있다). 클릭으로 둔 수는 새 애니메이션이 옛것을 갈아 치워
        //        이 자리가 안 드러난다 — 끌어 놓은 조용한 수에만 있는 길이다.
        // 수순: 1.e4 d5 2.exd5 Qxd5(상대가 잡는다 — 꼬리가 가장 길다, 0.32초) 3.a3(조용한 수를 끌어 둔다).
        let line = try dsLine(["e2e4", "d7d5", "e4d5", "d8d5", "a2a3"])
        let a2 = try dsSquare("a2"), a3 = try dsSquare("a3")
        func arriving(_ label: String) throws -> (ChessStore, String) {
            let (store, host) = dsStore(label, handler: dsHandler([
                "chess_move": [dsBody(dsStateJSON(ply: 5, line))], "chess_state": [dsBody(dsStateJSON(ply: 5, line))],
            ]))
            store.applyState(try dsDecode(dsStateJSON(ply: 3, line)))
            store.applyState(try dsDecode(dsStateJSON(ply: 4, line)))        // 상대의 Qxd5 가 미끄러지기 시작한다
            #expect(store.flight?.ply == 4 && store.flight?.knockout != nil, "전제(\(label)): 상대의 잡는 수가 미끄러지는 중이다")
            return (store, host)
        }

        let (dragged, dragHost) = try arriving("tail-drag")
        #expect(dragged.beginDrag(from: a2))
        await dragged.drop(from: a2, on: a3)
        #expect(dsMoveCalls(dragHost) == ["a2a3"])
        #expect(dragged.match?.plyCount == 5)
        #expect(dragged.flight == nil,
                "끌어 놓은 조용한 수 뒤에 앞 수의 꼬리가 남았다(ply \(dragged.flight?.ply ?? -1)) — 옛 수의 프레임이 새 판 위에 그려진다")

        // ★ 대조군: 같은 수를 **클릭으로** 두면 그 수의 애니메이션이 옛것을 갈아 치운다(nil 이 아니라 새 값이다).
        let (clicked, clickHost) = try arriving("tail-click")
        await clicked.tap(a2)
        await clicked.tap(a3)
        #expect(dsMoveCalls(clickHost) == ["a2a3"])
        #expect(clicked.flight?.ply == 5 && clicked.flight?.sliders.map(\.from) == [a2],
                "클릭으로 둔 수가 앞 수의 꼬리를 갈아 치우지 않았다")
    }

    // MARK: - ⑰ 낡은 놓기 — 놓은 뒤 판이 다시 읽혔으면 보내지 않는다

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func aDropWhoseBoardWasRereadUnderItIsNeverSent() async throws {
        // 없으면: `finishDrop` 이 자기 치유값(`pendingDrop`)이 아니라 원본을 읽어도 초록이다. 그러면 놓고 보내기 전에
        //        **같은 판·같은 수 번호에서** 판이 다시 읽힌 경우(출발 칸의 말이 달라졌다 · 내 차례가 꺼졌다) 낡은 수가
        //        나간다 — `send` 는 '지금의' 판 id·수 번호를 실어 보내므로 서버는 그것을 지금 판의 수로 받는다.
        //        (판 id 나 수 번호가 달라진 경우는 ⑤(마)·⑨ 가 잰다. 여기는 그 둘이 **그대로인** 경우다.)
        let line = try dsLine(["e2e4"])
        let e2 = try dsSquare("e2"), e4 = try dsSquare("e4")
        /// 놓고 아직 안 보낸 스토어와 그 수.
        func placed(_ label: String) throws -> (ChessStore, String, ChessMove) {
            let (store, host) = try dsPlayable(label, line)
            #expect(store.beginDrag(from: e2))
            let move = try #require(store.placeDrop(from: e2, on: e4))
            return (store, host, move)
        }

        // (가) 출발 칸의 말이 달라졌다(e2 폰이 이미 e3 에 가 있는 판으로 다시 읽혔다).
        let (reread, rereadHost, rereadMove) = try placed("stale-piece")
        let elsewhere = try #require(ChessPosition(fen: "rnbqkbnr/pppppppp/8/8/8/4P3/PPPP1PPP/RNBQKBNR w KQkq - 0 1"))
        var changed = try #require(reread.match)
        changed.position = elsewhere
        reread.match = changed                      // 깔때기를 안 거친다 — 원본을 지우는 자리가 하나도 안 불린다
        #expect(reread.pendingDropRecord != nil, "전제: 원본은 아무도 안 지웠다 — 막는 것은 읽는 자리다")
        await reread.finishDrop(rereadMove)
        #expect(dsMoveCalls(rereadHost).isEmpty, "출발 칸에 그 말이 없는데 놓은 수가 나갔다: \(dsMoveCalls(rereadHost))")
        #expect(reread.pendingDropRecord == nil, "안 보낸 놓기의 꼬리표가 남았다")
        #expect(!reread.isBusy)

        // (나) 같은 수 번호인데 내 차례가 아니게 됐다.
        let (turned, turnedHost, turnedMove) = try placed("stale-turn")
        var flipped = try #require(turned.match)
        flipped.turn = .black
        turned.match = flipped
        #expect(turned.pendingDropRecord != nil, "전제: 원본은 아무도 안 지웠다")
        await turned.finishDrop(turnedMove)
        #expect(dsMoveCalls(turnedHost).isEmpty, "내 차례가 아닌 판에 놓은 수가 나갔다: \(dsMoveCalls(turnedHost))")
        #expect(turned.pendingDropRecord == nil)

        // ★ 기준선: 판이 그대로면 같은 놓기가 한 건 나간다(판의 다른 칸만 바뀐 갱신은 막지 않는다).
        let (steady, steadyHost, steadyMove) = try placed("stale-none")
        var offered = try #require(steady.match)
        offered.drawOfferBy = dsBlackID
        steady.match = offered
        await steady.finishDrop(steadyMove)
        #expect(dsMoveCalls(steadyHost) == ["e2e4"])
    }
}
