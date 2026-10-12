import AppKit
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// v0.3.48 체스 끌기 — **실제 창 프로브**. 진짜 `NSWindow` + `NSHostingView` + `ChessPanel`(앱이 띄우는 그 화면)에
// 합성 `leftMouseDown → leftMouseDragged×N → leftMouseUp` 을 `window.sendEvent(_:)` 로 넣고, **스텁 서버가 받은
// 수**로 결과를 잰다.
//
// 해석기·스토어 시험이 못 보는 것이 여기 있다: 제스처가 실제로 눌림·움직임·뗌을 주는가, 판 좌표가 창 안에서
// 맞는가, 뷰의 취소(`onChange`)가 실제로 불리는가, 그리고 **그 순간 창에 그려진 그림**(끄는 중 · 뗀 그 틱 ·
// 거둔 직후 — `cacheDisplay` 로 창에 얹힌 그 뷰를 뜬다).
//
// ★ 전역 CGEvent 는 쏘지 않는다(사용자가 이 맥을 쓰고 있다 — 커서를 뺏는다). 이벤트는 **이 창에만** 직접 넣는다.
//
// ★ 창은 **키가 될 수 없는** 창이다(`DWProbeWindow.canBecomeKey == false`) — 그 한 줄 말고는 체스 창과 같은
//   스타일이다. 까닭(2026-10-12 실측, 같은 프로브를 창 열 가지에 돌렸다):
//     · 키가 될 수 **있는데 지금 키가 아닌** 창에서 SwiftUI 는 **제스처를 전부 무시한다** — `DragGesture` ·
//       `SpatialTapGesture` · `onTapGesture` 가 셋 다 0회(같은 창의 `Button` 은 눌린다). 누름을 "창을 앞으로
//       가져오는 첫 클릭" 으로 읽는 것이다. `isKeyWindow` 를 참으로 덮어써도 그대로였고, 갈린 것은
//       `canBecomeKey` 하나였다(테두리 없는 창 · 키 불가로 덮어쓴 제목 창 = 전부 답한다).
//     · 테스트 프로세스는 활성 앱이 아니라 창이 키가 **될 수 없다**. 활성화하면 되지만 그건 사용자의 포커스를
//       뺏는 일이다. 그래서 컨트롤러가 만든 창(키가 될 수 있다)에는 합성 끌기가 **닿지 않는다** — 이 프로브는
//       컨트롤러의 창이 아니라 같은 스타일의 프로브 창에 같은 화면을 얹는다.
//   이 무시는 옛 탭 제스처에도 똑같이 걸려 있던 것이라 이번 변경이 만든 차이가 아니다(실측 표에서 둘이 같다).
//
// ★ **창이 끌려가는지는 여기서 못 잰다.** 합성 이벤트로는 제목줄을 끌어도, `isMovableByWindowBackground` 를
//   켜도 창이 안 움직였다(같은 실측) — "안 움직였다" 는 단언이 대조군과 안 갈린다. 그래서 그 스위치가 꺼져
//   있다는 사실만 못 박는다(꺼져 있으면 내용 영역 끌기는 창을 옮기지 않는다 — AppKit 계약).
//
// 서버 응답은 **실서버 픽스처 원문**이다(`Fixtures/chess-rpc`): 초기 국면(내 차례) → 1.e4 의 답.
// 뒤집힌 판(흑 시점)은 1.e4 뒤 흑 차례 → 1…e5 의 답이다(`dwBlackToMoveState` — 같은 판, 같은 픽스처 묶음).
//
// 창 수명 스위트(`ChessWindowLifecycleTests`, 직렬)에 붙인다 — AppKit 창을 동시에 만들면 죽는다(그 파일 머리말).

// MARK: - 하네스

private let dwFixtureDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Fixtures/chess-rpc", isDirectory: true)

private func dwText(_ name: String) throws -> String {
    try String(contentsOf: dwFixtureDirectory.appendingPathComponent("\(name).json"), encoding: .utf8)
}

/// 픽스처 `chess_state__ok_initial_my_turn` 의 판과 그 판을 부른 사람(백).
private let dwMatchID = "9a7156f6-f055-4590-ba98-f537ead0a600"
private let dwWhiteID = "aa000000-0000-4000-8000-0000000000a1"
private let dwBlackID = "bb000000-0000-4000-8000-0000000000b2"

@MainActor
private enum DWRetention {
    static var stores: [WorkTimerStore] = []
}

/// 초기 국면(내 차례)을 든 1:1 스토어. `chess_move` 는 1.e4 의 실서버 답을 돌려준다.
/// `stateBody` 를 주면 픽스처 이름 대신 **그 원문**이 판 응답이 되고, `move` 는 착수 답의 픽스처 이름이다.
@MainActor
private func dwStore(_ label: String, me: String = dwWhiteID,
                     state: String = "chess_state__ok_initial_my_turn", stateBody: String? = nil,
                     move: String = "chess_move__ok_white_first") async throws -> (ChessStore, String) {
    let host = "v0348-cw-\(label)-\(UUID().uuidString.prefix(8))".lowercased()
    let bodies = [
        "chess_state": try stateBody ?? dwText(state),
        "chess_move": try dwText(move),
        "chess_lobby": try dwText("chess_lobby__ok_empty"),
    ]
    GomokuStubProtocol.register(host: host) { rpc, _, _ in
        guard let body = bodies[rpc] else {
            return GomokuStubProtocol.Reply(status: 404, body: #"{"code":"PGRST202","message":"missing"}"#)
        }
        return GomokuStubProtocol.Reply(body: body)
    }
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!, anonKey: "anon-test-key",
        session: GomokuStubProtocol.session())
    let owner = WorkTimerStore(
        service: service, environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: GomokuTestDefaults.make("v0348-chess-drag-window"), workspaceNotifications: nil)
    owner.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: me)
    DWRetention.stores.append(owner)
    let store = ChessStore(host: owner)
    store.pollStepSeconds = 3_600
    await store.refreshMatch(id: dwMatchID)
    return (store, host)
}

/// 1.e4 뒤 **흑 차례**를 흑이 본 판(같은 판 id). 실서버 픽스처 `chess_move__stale` 의 몸통(흑 · 내 차례 ·
/// 합법 수 20)을 판 응답으로 쓴다 — status 만 ok 로 바꾼다. 그 판의 답은 `chess_move__ok_black_reply`(1…e5).
private func dwBlackToMoveState() throws -> String {
    let data = try #require(try dwText("chess_move__stale").data(using: .utf8))
    var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    object["status"] = "ok"
    return try #require(String(data: try JSONSerialization.data(withJSONObject: object), encoding: .utf8))
}

/// 창이 그림·배치·제스처를 따라잡을 틈을 준다. **중첩 런루프를 돌리지 않는다**(오목 창 시험이 그렇게 데었다) —
/// 잠들어 양보하고, 대기는 재개 횟수 기반이다.
@MainActor
private func dwSettle(turns: Int = 6, until condition: @MainActor () -> Bool = { false }) async {
    for _ in 0..<turns {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(10))
    }
}

/// 키가 될 수 없는 창 — 그 한 줄 말고는 체스 창과 같다(파일 머리말 ★).
private final class DWProbeWindow: NSWindow {
    override var canBecomeKey: Bool { false }
}

/// 체스 창과 **같은 스타일**의 창에 앱이 띄우는 그 화면(`ChessPanel`)을 얹는다. 컨트롤러가 하는 배선
/// (`configure(store:)` 의 내용 뷰 · 다크 · 고정 크기 · 테스트 알파 0)을 그대로 따르고, 스토어에는 창이 보인다고 알린다.
@MainActor
private func dwOpen(_ store: ChessStore) async throws -> NSWindow {
    let production = CheckChessWindowController.makeWindow()
    defer { production.close() }
    let window = DWProbeWindow(
        contentRect: NSRect(origin: NSPoint(x: 120, y: 120), size: CheckChessWindowController.fixedContentSize),
        styleMask: production.styleMask, backing: .buffered, defer: false)
    #expect(window.styleMask == [.titled, .closable, .miniaturizable], "체스 창의 스타일이 바뀌었다 — 프로브 창도 따라간다")
    window.isReleasedWhenClosed = false
    window.appearance = production.appearance
    // 테스트 실행에서는 알파 0 이다. 일반 창은 알파 0 이면 사용자의 클릭을 통과시킨다(`CheckMousePanel` 머리말의 실측).
    window.alphaValue = CheckPanelVisibility.panelAlpha
    let hosting = NSHostingView(rootView:
        ChessPanel(store: store)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(CheckTheme.background))
    hosting.autoresizingMask = [.width, .height]
    window.contentView = hosting
    window.orderFrontRegardless()
    store.windowDidShow()
    await dwSettle(turns: 20)
    return window
}

/// 프로브 창을 내린다.
@MainActor
private func dwClose(_ window: NSWindow, _ store: ChessStore) {
    store.windowDidClose()
    store.stopPolling()
    window.orderOut(nil)
    window.contentView = nil
    window.close()
}

/// 판 좌표(판 왼쪽 위가 원점) → **창 콘텐츠 좌표**(왼쪽 위가 원점). 판은 레이아웃 상수가 정한 자리에 있다.
@MainActor
private func dwContent(_ board: CGPoint) -> CGPoint {
    CGPoint(
        x: ChessWindowLayout.contentPadding + board.x,
        y: ChessWindowLayout.contentPadding + ChessWindowLayout.headerHeight
            + ChessWindowLayout.headerSpacing + board.y)
}

/// 판 위 칸의 가운데 — 창 콘텐츠 좌표. `orientation` 은 아래쪽에 오는 색이다(흑이면 판이 뒤집혀 있다).
@MainActor
private func dwPoint(_ notation: String, orientation: ChessColor = .white,
                     dx: CGFloat = 0, dy: CGFloat = 0) throws -> CGPoint {
    let square = try #require(ChessSquare(notation))
    let center = ChessBoardGeometry(side: ChessWindowLayout.boardSide, orientation: orientation).center(of: square)
    return dwContent(CGPoint(x: center.x + dx, y: center.y + dy))
}

/// 합성 마우스 이벤트 한 건을 **이 창에만** 넣는다.
@MainActor
private func dwSend(_ window: NSWindow, _ type: NSEvent.EventType, at point: CGPoint, number: Int) throws {
    let height = window.contentView?.bounds.height ?? ChessWindowLayout.contentSize.height
    let event = try #require(NSEvent.mouseEvent(
        with: type, location: NSPoint(x: point.x, y: height - point.y), modifierFlags: [],
        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
        eventNumber: number, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1),
                             "합성 마우스 이벤트를 만들지 못했다(\(type.rawValue))")
    window.sendEvent(event)
}

/// 누르고 → `steps` 번에 나눠 움직인다(아직 떼지 않는다).
@MainActor
private func dwPressAndDrag(_ window: NSWindow, from: CGPoint, to: CGPoint, steps: Int = 8, number: Int) async throws {
    try dwSend(window, .leftMouseDown, at: from, number: number)
    await dwSettle(turns: 2)
    for step in 1...steps {
        let t = CGFloat(step) / CGFloat(steps)
        try dwSend(window, .leftMouseDragged,
                   at: CGPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t), number: number)
        await dwSettle(turns: 1)
    }
}

/// 제자리에서 누르고 뗀다(클릭).
@MainActor
private func dwClick(_ window: NSWindow, at point: CGPoint, number: Int) async throws {
    try dwSend(window, .leftMouseDown, at: point, number: number)
    await dwSettle(turns: 2)
    try dwSend(window, .leftMouseUp, at: point, number: number)
    await dwSettle(turns: 4)
}

/// 창에 얹힌 **그 뷰 자체**를 그린 비트맵(`cacheDisplay` — 창 알파 0 은 합성 단계에서만 지우므로 그림은 그대로 나온다).
/// 부르는 순간 SwiftUI 가 밀린 상태 변화를 그림에 반영한다 — 그래서 "이 줄에서 사용자가 볼 한 장" 을 뜬다.
@MainActor
private func dwCapture(_ window: NSWindow) throws -> NSBitmapImageRep {
    let view = try #require(window.contentView)
    let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: rep)
    return rep
}

/// 그 칸 가운데 50% 상자의 **흰 말 잉크**(최대 채널 ≥ 235). 칸·덮개는 전부 그보다 어둡다(`ChessBoardView` 머리말).
@MainActor
private func dwWhiteInk(_ rep: NSBitmapImageRep, _ notation: String) throws -> Int {
    let center = try dwPoint(notation)
    let scale = CGFloat(rep.pixelsWide) / ChessWindowLayout.contentSize.width
    let half = ChessWindowLayout.cellSide * 0.25
    guard let data = rep.bitmapData, rep.samplesPerPixel >= 3 else { return 0 }
    let x0 = max(0, Int((center.x - half) * scale)), x1 = min(rep.pixelsWide - 1, Int((center.x + half) * scale))
    let y0 = max(0, Int((center.y - half) * scale)), y1 = min(rep.pixelsHigh - 1, Int((center.y + half) * scale))
    guard x0 <= x1, y0 <= y1 else { return 0 }
    var hits = 0
    for y in y0...y1 {
        for x in x0...x1 {
            let o = y * rep.bytesPerRow + x * rep.samplesPerPixel
            if max(data[o], max(data[o + 1], data[o + 2])) >= 235 { hits += 1 }
        }
    }
    return hits
}

/// 창 콘텐츠 좌표 사각형 안의 **흑 말 채움**(세 채널 전부 ≤ 55) 픽셀 수와 그것을 감싸는 상자(pt).
/// 흑 말의 테두리는 밝아서(0.90) 여기 안 세어진다 — 상자는 채움의 상자다.
@MainActor
private func dwDarkInk(_ rep: NSBitmapImageRep, in rect: CGRect) -> (count: Int, bounds: CGRect?) {
    let scale = CGFloat(rep.pixelsWide) / ChessWindowLayout.contentSize.width
    guard let data = rep.bitmapData, rep.samplesPerPixel >= 3 else { return (0, nil) }
    let x0 = max(0, Int(rect.minX * scale)), x1 = min(rep.pixelsWide - 1, Int(rect.maxX * scale))
    let y0 = max(0, Int(rect.minY * scale)), y1 = min(rep.pixelsHigh - 1, Int(rect.maxY * scale))
    guard x0 <= x1, y0 <= y1 else { return (0, nil) }
    var hits = 0, minX = Int.max, maxX = Int.min, minY = Int.max, maxY = Int.min
    for y in y0...y1 {
        for x in x0...x1 {
            let o = y * rep.bytesPerRow + x * rep.samplesPerPixel
            guard max(data[o], max(data[o + 1], data[o + 2])) <= 55 else { continue }
            hits += 1
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        }
    }
    guard hits > 0 else { return (0, nil) }
    return (hits, CGRect(x: CGFloat(minX) / scale, y: CGFloat(minY) / scale,
                         width: CGFloat(maxX - minX + 1) / scale, height: CGFloat(maxY - minY + 1) / scale))
}

/// 창 콘텐츠 좌표 한 점의 색(RGB).
@MainActor
private func dwPixel(_ rep: NSBitmapImageRep, at point: CGPoint) -> (Int, Int, Int) {
    let scale = CGFloat(rep.pixelsWide) / ChessWindowLayout.contentSize.width
    guard let data = rep.bitmapData, rep.samplesPerPixel >= 3 else { return (0, 0, 0) }
    let x = min(rep.pixelsWide - 1, max(0, Int(point.x * scale)))
    let y = min(rep.pixelsHigh - 1, max(0, Int(point.y * scale)))
    let o = y * rep.bytesPerRow + x * rep.samplesPerPixel
    return (Int(data[o]), Int(data[o + 1]), Int(data[o + 2]))
}

/// 두 색의 가장 큰 채널 차.
private func dwDelta(_ a: (Int, Int, Int), _ b: (Int, Int, Int)) -> Int {
    max(abs(a.0 - b.0), max(abs(a.1 - b.1), abs(a.2 - b.2)))
}

@MainActor
private func dwMoves(_ host: String) -> [String] {
    GomokuStubProtocol.calls(host: host, rpc: "chess_move").compactMap { $0.json["p_uci"] as? String }
}

extension ChessWindowLifecycleTests {

    // MARK: - ① 끌어서 둔다 — 스텁이 정확히 한 건을 받는다

    @Test(.gomokuDefaultsCleanup)
    func draggingAPieceInTheRealWindowSendsExactlyOneMove() async throws {
        // 없으면: 해석기·스토어가 다 멀쩡한데 **제스처가 판에 안 달렸거나**(눌림이 안 온다) 좌표가 어긋나
        //        (다른 칸의 말이 집힌다) 실제 창에서는 끌기가 안 되어도 초록이다.
        let (store, host) = try await dwStore("drag")
        let window = try await dwOpen(store)
        defer { dwClose(window, store) }
        #expect(store.phase == .playing && store.match?.isMyTurn == true, "전제: 내 차례의 판이 떠 있다")
        let frameBefore = window.frame
        let e2 = try #require(ChessSquare("e2")), e4 = try #require(ChessSquare("e4"))
        let resting = try dwCapture(window)
        let restingInk = (e2: try dwWhiteInk(resting, "e2"), e4: try dwWhiteInk(resting, "e4"))

        try await dwPressAndDrag(window, from: try dwPoint("e2"), to: try dwPoint("e4"), number: 1)
        await dwSettle(turns: 30) { store.dragOrigin != nil }
        // 끄는 중: 그 말이 고른 말이 됐고(갈 수 있는 칸 점이 뜬다) 수는 아직 안 나갔다.
        #expect(store.dragOrigin == e2, "합성 끌기가 스토어의 끌기를 시작하지 못했다(dragOrigin=\(String(describing: store.dragOrigin)))")
        #expect(store.selection == ChessSelection(from: e2, targets: [try #require(ChessSquare("e3")), e4]))
        #expect(dwMoves(host).isEmpty, "아직 안 놓았는데 수가 나갔다")
        #expect(store.match?.plyCount == 0)
        // 그 순간의 **그림**: 출발 칸은 비었고 커서 자리(e4 한가운데)에 말이 있다.
        let dragging = try dwCapture(window)
        let draggingInk = (e2: try dwWhiteInk(dragging, "e2"), e4: try dwWhiteInk(dragging, "e4"))

        try dwSend(window, .leftMouseUp, at: try dwPoint("e4"), number: 1)
        // ★ 뗀 **그 틱**의 그림 — 여기까지 await 가 없다. 서버 답은 아직 안 왔고(판은 그대로다) 놓은 말은
        //   도착 칸에 서 있어야 한다. 출발 칸에 돌아가 있으면 사용자는 말이 번쩍 되돌아갔다 다시 가는 것을 본다.
        #expect(store.match?.plyCount == 0, "전제: 뗀 틱에는 답이 아직 없다")
        #expect(dwMoves(host).isEmpty, "전제: 뗀 틱에는 수가 아직 안 나갔다")
        let dropped = try dwCapture(window)
        let droppedInk = (e2: try dwWhiteInk(dropped, "e2"), e4: try dwWhiteInk(dropped, "e4"))
        print("[실창] 흰 잉크 e2/e4 — 멈춤 \(restingInk.e2)/\(restingInk.e4) · 끄는 중 \(draggingInk.e2)/\(draggingInk.e4) · 뗀 틱 \(droppedInk.e2)/\(droppedInk.e4)")
        #expect(restingInk.e2 > 200 && restingInk.e4 == 0, "전제: 멈춘 판은 e2 에 폰이 있고 e4 가 비었다")
        #expect(draggingInk.e2 == 0, "끄는 중인데 출발 칸에 말이 그려진다(\(draggingInk.e2)px)")
        #expect(draggingInk.e4 > 200, "끄는 중인데 커서 자리에 말이 없다(\(draggingInk.e4)px)")
        #expect(droppedInk.e2 == 0, "뗀 틱에 말이 출발 칸으로 되돌아갔다(\(droppedInk.e2)px) — 번쩍인다")
        #expect(droppedInk.e4 > 200, "뗀 틱에 도착 칸에 말이 없다(\(droppedInk.e4)px)")

        await dwSettle(turns: 300) { store.match?.plyCount == 1 }
        let settled = try dwCapture(window)
        #expect(try dwWhiteInk(settled, "e2") == 0)
        #expect(try dwWhiteInk(settled, "e4") > 200, "답이 온 뒤 도착 칸에 말이 없다")

        #expect(dwMoves(host) == ["e2e4"], "실제 창에서 끌어 놓은 수가 \(dwMoves(host)) 로 나갔다")
        #expect(store.match?.plyCount == 1)
        #expect(store.match?.position?[e4] == ChessPiece(.white, .pawn))
        #expect(store.dragOrigin == nil)
        #expect(store.pendingDrop == nil && store.pendingDropRecord == nil)
        #expect(store.flight == nil, "끌어 놓은 말이 다시 미끄러졌다")
        // 판 위 끌기가 창을 옮기지 않는다 — 합성 이벤트로는 창이 움직이는지 못 재므로(파일 머리말 ★) 스위치를 못 박는다.
        let production = CheckChessWindowController.makeWindow()
        defer { production.close() }
        #expect(!production.isMovableByWindowBackground, "체스 창이 바탕 끌기로 움직인다 — 판 위에서 말을 끌면 창이 끌려간다")
        #expect(window.frame == frameBefore)
    }

    // MARK: - ② 클릭-클릭은 그대로다

    @Test(.gomokuDefaultsCleanup)
    func clickClickInTheRealWindowStillSendsTheMoveAndStillSlides() async throws {
        // 없으면: 탭 제스처를 끌기 제스처로 바꾸면서 **클릭이 죽어도**(가장 흔한 사고) 초록이다.
        let (store, host) = try await dwStore("click")
        let window = try await dwOpen(store)
        defer { dwClose(window, store) }
        let e2 = try #require(ChessSquare("e2"))

        // 고르고 → 같은 칸을 다시 누르면 해제된다(지금의 탭 그대로).
        try await dwClick(window, at: try dwPoint("e2"), number: 1)
        await dwSettle(turns: 30) { store.selection != nil }
        #expect(store.selection?.from == e2, "판을 눌렀는데 말이 안 골라졌다 — 클릭이 죽었다")
        #expect(store.dragOrigin == nil, "제자리 클릭이 끌기로 읽혔다")
        try await dwClick(window, at: try dwPoint("e2"), number: 2)
        await dwSettle(turns: 30) { store.selection == nil }
        #expect(store.selection == nil, "고른 말을 다시 눌렀는데 해제가 안 된다")

        // 손이 3pt 떨린 클릭도 탭이다(문턱 4pt 밑).
        try dwSend(window, .leftMouseDown, at: try dwPoint("e2"), number: 3)
        try dwSend(window, .leftMouseDragged, at: try dwPoint("e2", dx: 3), number: 3)
        try dwSend(window, .leftMouseUp, at: try dwPoint("e2", dx: 3), number: 3)
        await dwSettle(turns: 30) { store.selection != nil }
        #expect(store.selection?.from == e2, "3pt 떨린 클릭이 탭으로 안 읽혔다")
        #expect(dwMoves(host).isEmpty)

        // 도착 칸을 누른다 — 한 건 나가고, **미끄러진다**(끌어 둔 수와 갈리는 자리다).
        try await dwClick(window, at: try dwPoint("e4"), number: 4)
        await dwSettle(turns: 300) { store.match?.plyCount == 1 }
        #expect(dwMoves(host) == ["e2e4"], "실제 창의 클릭-클릭이 \(dwMoves(host)) 로 나갔다")
        #expect(store.match?.plyCount == 1)
        #expect(store.pendingDropRecord == nil, "클릭 길이 놓은 말의 꼬리표를 세웠다")
    }

    // MARK: - ③ 판 밖·갈 수 없는 칸에 놓으면 아무 수도 안 나가고 고르기는 남는다

    @Test(.gomokuDefaultsCleanup)
    func droppingOutsideOrOnAnIllegalSquareInTheRealWindowSendsNothing() async throws {
        // 없으면: 판 밖에서 뗀 끌기가 누른 칸의 탭(= 해제)이나 가장 가까운 칸의 놓기로 읽혀도 초록이다.
        let (store, host) = try await dwStore("outside")
        let window = try await dwOpen(store)
        defer { dwClose(window, store) }
        let e2 = try #require(ChessSquare("e2"))

        // 판 오른쪽 밖(오른쪽 열 위)에서 뗀다.
        let outside = CGPoint(x: ChessWindowLayout.contentPadding + ChessWindowLayout.boardSide + 60,
                              y: try dwPoint("e4").y)
        try await dwPressAndDrag(window, from: try dwPoint("e2"), to: outside, number: 1)
        await dwSettle(turns: 30) { store.dragOrigin != nil }
        #expect(store.dragOrigin == e2, "전제: 끌기가 시작됐다")
        try dwSend(window, .leftMouseUp, at: outside, number: 1)
        await dwSettle(turns: 30) { store.dragOrigin == nil }
        #expect(store.dragOrigin == nil, "판 밖에서 뗐는데 끌기가 안 끝났다")
        #expect(store.selection?.from == e2, "판 밖에 놓았더니 고르기가 풀렸다")
        #expect(store.notice == nil, "판 밖에 놓았는데 안내가 떴다: \(store.notice ?? "")")

        // 갈 수 없는 칸(e5)에 놓는다 — 거절 문구가 뜨고 고르기는 남는다.
        try await dwPressAndDrag(window, from: try dwPoint("e2"), to: try dwPoint("e5"), number: 2)
        try dwSend(window, .leftMouseUp, at: try dwPoint("e5"), number: 2)
        await dwSettle(turns: 30) { store.notice != nil }
        #expect(store.notice == ChessNoticeText.cannotMove)
        #expect(store.selection?.from == e2)

        await dwSettle(turns: 10)
        #expect(dwMoves(host).isEmpty, "둘 수 없는 자리에 놓았는데 수가 나갔다: \(dwMoves(host))")
        #expect(store.match?.plyCount == 0)
        #expect(store.pendingDropRecord == nil)
    }

    // MARK: - ④ 끄는 중에 판이 바뀌면 뷰가 끌기를 거둔다 — 그 뒤 떼도 수가 안 나간다

    @Test(.gomokuDefaultsCleanup)
    func theViewRevokesTheDragWhenThePremiseChangesMidDrag() async throws {
        // 없으면: 뷰의 취소 배선(`onChange`)이 빠져도 초록이다 — 스토어 걸쇠만으로는 **되돌아오는 조건**
        //        (왕복이 시작됐다 풀렸다)을 못 막는다. 여기서는 스토어 걸쇠가 **일부러 안 내려가는** 계기
        //        (`isBusy`)로 재서, 수가 안 나간 것이 뷰의 취소 덕임을 가른다.
        let (store, host) = try await dwStore("revoke")
        let window = try await dwOpen(store)
        defer { dwClose(window, store) }
        let e2 = try #require(ChessSquare("e2"))

        try await dwPressAndDrag(window, from: try dwPoint("e2"), to: try dwPoint("e3"), steps: 4, number: 1)
        await dwSettle(turns: 30) { store.dragOrigin != nil }
        #expect(store.dragOrigin == e2, "전제: 끌기가 시작됐다")
        #expect(try dwWhiteInk(try dwCapture(window), "e2") == 0, "전제: 끄는 중에는 출발 칸이 비어 그려진다")

        // 끄는 중에 왕복이 시작됐다가 풀렸다. 놓는 순간에는 스토어가 볼 수 있는 흔적이 없다.
        store.isBusy = true
        await dwSettle(turns: 10) { store.dragOrigin == nil }
        #expect(store.dragOrigin == nil, "판이 바뀌었는데 뷰가 끌기를 안 거뒀다 — 말이 손에 붙은 채다")
        // 말은 **즉시** 제자리에 그려진다(마우스는 아직 눌려 있다).
        let revoked = try dwCapture(window)
        #expect(try dwWhiteInk(revoked, "e2") > 200, "끌기를 거뒀는데 말이 출발 칸에 안 돌아왔다")
        #expect(try dwWhiteInk(revoked, "e3") == 0, "끌기를 거뒀는데 말이 커서 자리에 남아 있다")
        store.isBusy = false
        await dwSettle(turns: 5)

        try dwSend(window, .leftMouseDragged, at: try dwPoint("e4"), number: 1)
        try dwSend(window, .leftMouseUp, at: try dwPoint("e4"), number: 1)
        await dwSettle(turns: 30)
        #expect(dwMoves(host).isEmpty, "끌기를 거둔 뒤 뗐는데 수가 나갔다: \(dwMoves(host))")
        #expect(store.match?.plyCount == 0)
        #expect(store.pendingDropRecord == nil)

        // 거둔 뒤의 **다음** 끌기는 멀쩡하다(해석기가 소진된 채 굳지 않았다).
        try await dwPressAndDrag(window, from: try dwPoint("e2"), to: try dwPoint("e4"), number: 2)
        try dwSend(window, .leftMouseUp, at: try dwPoint("e4"), number: 2)
        await dwSettle(turns: 300) { store.match?.plyCount == 1 }
        #expect(dwMoves(host) == ["e2e4"], "취소 뒤의 새 끌기가 안 먹는다: \(dwMoves(host))")
    }

    // MARK: - ④' 창이 가려졌다 다시 보인다 — 뷰가 볼 수 없는 계기도 말을 제자리에 돌린다

    @Test(.gomokuDefaultsCleanup)
    func occlusionMidDragPutsThePieceBackEvenThoughTheViewCannotSeeIt() async throws {
        // 없으면: 가림은 뷰가 관찰할 값이 없다(`isWindowOccluded` 는 관찰 대상이 아니다). 스토어 걸쇠가 유일한
        //        신호인데, 뷰가 그 걸쇠를 안 보면 가림이 풀린 뒤에도 말이 손에 붙은 채 그려진다.
        //        (수가 안 나가는 것은 스토어가 따로 막는다 — 여기서는 **그림과 그 뒤의 뗌**을 잰다.)
        let (store, host) = try await dwStore("occluded")
        let window = try await dwOpen(store)
        defer { dwClose(window, store) }
        let e2 = try #require(ChessSquare("e2"))

        try await dwPressAndDrag(window, from: try dwPoint("e2"), to: try dwPoint("e3"), steps: 4, number: 1)
        await dwSettle(turns: 30) { store.dragOrigin != nil }
        #expect(store.dragOrigin == e2, "전제: 끌기가 시작됐다")
        #expect(try dwWhiteInk(try dwCapture(window), "e2") == 0, "전제: 끄는 중에는 출발 칸이 비어 그려진다")

        // 가려졌다가 곧 다시 보인다(다른 창이 잠깐 덮었다). 마우스는 계속 눌려 있다.
        store.windowOcclusionDidChange(visible: false)
        store.windowOcclusionDidChange(visible: true)
        await dwSettle(turns: 5)
        #expect(store.dragOrigin == nil)
        let after = try dwCapture(window)
        #expect(try dwWhiteInk(after, "e2") > 200, "가림이 지나갔는데 말이 출발 칸에 안 돌아왔다")
        #expect(try dwWhiteInk(after, "e3") == 0, "가림이 지나갔는데 말이 커서 자리에 남아 있다")

        // 그 뒤에 움직이고 떼도 말은 다시 안 들리고 수도 안 나간다.
        try dwSend(window, .leftMouseDragged, at: try dwPoint("e4"), number: 1)
        await dwSettle(turns: 3)
        #expect(try dwWhiteInk(try dwCapture(window), "e4") == 0, "거둔 끌기가 다음 움직임에 되살아났다")
        try dwSend(window, .leftMouseUp, at: try dwPoint("e4"), number: 1)
        await dwSettle(turns: 30)
        #expect(dwMoves(host).isEmpty, "가림이 지나간 뒤 뗐는데 수가 나갔다: \(dwMoves(host))")
        #expect(store.match?.plyCount == 0)
        #expect(store.selection?.from == e2, "끌기를 거뒀다고 고르기까지 풀렸다")
    }

    // MARK: - ④a 놓자마자 다시 집는다 — 앞 끌기의 늦은 통지가 새 누름을 떨구지 않는다

    @Test(.gomokuDefaultsCleanup)
    func aPressRightAfterADropIsNotRevokedByTheLateNoticeOfThatDrop() async throws {
        // 없으면: 뷰의 취소 통지(`onChange`)는 값이 바뀐 **다음 그리기**에 온다. 놓은 직후(또는 상대 수가 닿은
        //        바로 그 프레임)에 시작한 누름이 그 늦은 통지에 '끌 수 없음' 으로 떨어져 **끌기가 씹힌다**.
        //        이 프로브를 처음 돌렸을 때 실제로 났던 결함이다(놓기 → 양보 없이 다음 누름).
        // 경합이라 한 번으로는 안 잡힐 수 있어 여러 번 돈다 — 매번 "놓기 → **양보 없이** 누름 → 끌어 놓기" 다.
        let (store, host) = try await dwStore("regrab")
        let window = try await dwOpen(store)
        defer { dwClose(window, store) }
        let e2 = try #require(ChessSquare("e2"))

        var refused = 0
        let rounds = 12
        for round in 0..<rounds {
            // 앞 끌기: 집어서 출발 칸에 도로 놓는다(수 없음 · 고르기는 남는다 · 걸쇠가 내려간다).
            try await dwPressAndDrag(window, from: try dwPoint("e2"), to: try dwPoint("e2", dy: -30),
                                     steps: 3, number: round * 2 + 1)
            #expect(store.dragOrigin == e2, "전제(\(round)): 앞 끌기가 시작됐다")
            try dwSend(window, .leftMouseUp, at: try dwPoint("e2"), number: round * 2 + 1)
            #expect(store.dragOrigin == nil, "전제(\(round)): 놓는 순간 걸쇠가 내려갔다")

            // ★ 여기까지 await 가 없다 — 곧바로 다시 **누른다**. 그리고 누른 채로 한 박자 쉰다: 앞 끌기가 끝났다는
            //   늦은 통지가 바로 이 틈에(눌렀고 아직 문턱 전) 온다. 그 뒤에 끌어 갈 수 없는 칸(e5)에 놓는다 —
            //   거절 문구가 떠야 한다(끌기가 씹히면 '다른 칸에서 뗀 누름' 이 되어 아무 말도 안 한다).
            store.notice = nil
            try dwSend(window, .leftMouseDown, at: try dwPoint("e2"), number: round * 2 + 2)
            await dwSettle(turns: 3)
            try dwSend(window, .leftMouseDragged, at: try dwPoint("e3"), number: round * 2 + 2)
            try dwSend(window, .leftMouseDragged, at: try dwPoint("e5"), number: round * 2 + 2)
            try dwSend(window, .leftMouseUp, at: try dwPoint("e5"), number: round * 2 + 2)
            await dwSettle(turns: 10) { store.notice != nil }
            if store.notice == ChessNoticeText.cannotMove { refused += 1 }
            await dwSettle(turns: 3)
        }
        #expect(refused == rounds, "놓자마자 다시 집은 끌기가 \(rounds)번 중 \(rounds - refused)번 씹혔다")

        // 같은 경합의 다른 문: **판의 전제**가 바뀐 통지. 왕복이 막 끝난(= 상대 수가 막 닿은) 그 프레임에 집는다.
        var afterChange = 0
        for round in 0..<rounds {
            store.isBusy = true
            await dwSettle(turns: 3)                    // 뷰가 '왕복 중' 을 그렸다
            store.isBusy = false                        // 전제가 바뀌었다 — 통지는 다음 그리기에 온다
            store.notice = nil
            try dwSend(window, .leftMouseDown, at: try dwPoint("e2"), number: 100 + round)     // await 없이 곧바로
            await dwSettle(turns: 3)                    // 늦은 통지가 이 틈에 온다
            try dwSend(window, .leftMouseDragged, at: try dwPoint("e3"), number: 100 + round)
            try dwSend(window, .leftMouseDragged, at: try dwPoint("e5"), number: 100 + round)
            try dwSend(window, .leftMouseUp, at: try dwPoint("e5"), number: 100 + round)
            await dwSettle(turns: 10) { store.notice != nil }
            if store.notice == ChessNoticeText.cannotMove { afterChange += 1 }
            await dwSettle(turns: 3)
        }
        #expect(afterChange == rounds, "판이 바뀐 직후에 집은 끌기가 \(rounds)번 중 \(rounds - afterChange)번 씹혔다")
        #expect(dwMoves(host).isEmpty)
        #expect(store.selection?.from == e2)
    }

    // MARK: - ④b 뗌이 안 온 끌기 — 다음 누름이 치운다

    @Test(.gomokuDefaultsCleanup)
    func aDragWhoseMouseUpNeverCameIsClearedByTheNextPress() async throws {
        // 없으면: 마우스 업을 잃은 끌기(실측: 뗌 없이 온 두 번째 다운에 SwiftUI 는 앞 제스처의 `onEnded` 를 안 부른다)
        //        뒤에 해석기가 '끄는 중' 에 굳어, 다음 클릭이 **옛 말의 놓기**로 나가거나 말이 손에 붙은 채 남는다.
        let (store, host) = try await dwStore("lost-up")
        let window = try await dwOpen(store)
        defer { dwClose(window, store) }
        let e2 = try #require(ChessSquare("e2")), g1 = try #require(ChessSquare("g1"))

        try await dwPressAndDrag(window, from: try dwPoint("e2"), to: try dwPoint("e3"), steps: 4, number: 1)
        await dwSettle(turns: 30) { store.dragOrigin != nil }
        #expect(store.dragOrigin == e2, "전제: 끌기가 시작됐다")

        // 뗌 없이 다른 칸(g1 — 내 나이트)을 누르고 뗀다.
        try await dwClick(window, at: try dwPoint("g1"), number: 2)
        await dwSettle(turns: 30) { store.selection?.from == g1 }
        #expect(store.dragOrigin == nil, "뗌을 잃은 끌기가 살아 있다")
        #expect(store.selection?.from == g1, "새 클릭이 탭으로 안 읽혔다(고른 칸 \(store.selection?.from.notation ?? "없음"))")
        #expect(try dwWhiteInk(try dwCapture(window), "e2") > 200, "끌던 말이 출발 칸에 안 돌아왔다")
        #expect(dwMoves(host).isEmpty, "뗌을 잃은 끌기가 수를 냈다: \(dwMoves(host))")
        #expect(store.match?.plyCount == 0)
    }

    // MARK: - ⑤ 내 차례가 아닐 때 끌려 하면 — 끌기는 없고 거절 한 번

    @Test(.gomokuDefaultsCleanup)
    func draggingOnTheOpponentsTurnInTheRealWindowOnlyRefuses() async throws {
        // 없으면: 상대 차례에 내 말을 끌면 말이 집히거나(선수가 나간다), 반대로 아무 말도 안 해도 초록이다.
        // 픽스처: 같은 판을 **흑**이 본 초기 국면(백 차례 = 내 차례가 아니다). 흑은 판이 뒤집혀 있다.
        let (store, host) = try await dwStore("their-turn", me: dwBlackID,
                                              state: "chess_state__ok_initial_their_turn")
        let window = try await dwOpen(store)
        defer { dwClose(window, store) }
        #expect(store.match?.myColor == .black && store.match?.isMyTurn == false, "전제: 상대 차례의 판이다")
        #expect(store.notice == nil)

        try await dwPressAndDrag(window, from: try dwPoint("e7", orientation: .black),
                                 to: try dwPoint("e5", orientation: .black), number: 1)
        await dwSettle(turns: 10)
        #expect(store.dragOrigin == nil, "상대 차례인데 말이 집혔다")
        #expect(store.selection == nil)
        #expect(store.notice == nil, "떼기도 전에 거절이 났다 — 뗄 때 한 번이어야 한다")

        try dwSend(window, .leftMouseUp, at: try dwPoint("e5", orientation: .black), number: 1)
        await dwSettle(turns: 30) { store.notice != nil }
        #expect(store.notice == ChessNoticeText.notYourTurn, "상대 차례에 끌려 했는데 '\(store.notice ?? "무음")'")
        #expect(store.selection == nil)
        #expect(dwMoves(host).isEmpty)
    }

    // MARK: - ⑥ 놓자마자 다른 말을 집는다 — 놓은 수는 그대로 나간다

    @Test(.gomokuDefaultsCleanup)
    func aLegalDropFollowedAtOnceByAnotherGrabStillSendsTheMove() async throws {
        // 없으면: 뷰는 놓기의 동기 구간을 그 자리에서 끝내고 왕복만 Task 로 넘긴다. 그 Task 가 돌기 **전에** 다음
        //        누름+끌기가 처리되면(이벤트가 밀려 한 턴에 몰릴 때) 스토어는 아직 '보내는 중' 이 아니다 — 그 끌기가
        //        앞 수의 꼬리표를 지워 **놓은 수가 문구도 로그도 없이 사라졌다**(chess_move 0건 · 폰은 출발 칸으로).
        // 세 갈래: 틈에서 집어 틈에서 도로 놓는다 · 틈에서 집어 답이 온 뒤에 갈 수 있는 칸에 놓는다 ·
        //         (대조군) 한 박자 양보한 뒤에 집는다 — 그때는 왕복이 이미 시작돼 집히지도 않는다.
        struct Variant {
            let label: String
            /// 놓은 뒤 다음 누름 전에 메인 액터를 양보하는가(양보하면 틈이 닫힌다).
            let yields: Bool
            /// 집은 말을 답이 올 때까지 쥐고 있다가 갈 수 있는 칸(d4)에 놓는가.
            let holds: Bool
        }
        let variants = [
            Variant(label: "틈에서 집고 틈에서 놓음", yields: false, holds: false),
            Variant(label: "틈에서 집고 답 뒤에 놓음", yields: false, holds: true),
            Variant(label: "양보 뒤에 집음", yields: true, holds: false),
        ]
        let e2 = try #require(ChessSquare("e2")), e4 = try #require(ChessSquare("e4"))
        let d2 = try #require(ChessSquare("d2"))
        for (index, variant) in variants.enumerated() {
            let (store, host) = try await dwStore("drop-then-grab-\(index)")
            let window = try await dwOpen(store)
            try await dwPressAndDrag(window, from: try dwPoint("e2"), to: try dwPoint("e4"), number: 1)
            #expect(store.dragOrigin == e2, "전제(\(variant.label)): 끌기가 시작됐다")
            try dwSend(window, .leftMouseUp, at: try dwPoint("e4"), number: 1)
            #expect(store.pendingDrop?.to == e4, "전제(\(variant.label)): 놓은 말이 도착 칸에 서 있다")
            #expect(dwMoves(host).isEmpty, "전제(\(variant.label)): 뗀 틱에는 수가 아직 안 나갔다")
            if variant.yields { await dwSettle(turns: 1) }

            // ★ 여기까지 await 가 없다(양보 갈래만 빼고) — 곧바로 d2 를 집어 d3 한가운데까지 끈다.
            try dwSend(window, .leftMouseDown, at: try dwPoint("d2"), number: 2)
            try dwSend(window, .leftMouseDragged, at: try dwPoint("d2", dy: -10), number: 2)
            try dwSend(window, .leftMouseDragged, at: try dwPoint("d3"), number: 2)
            if !variant.yields {
                // 틈은 실제로 열려 있었다: 그 끌기가 시작됐고, 앞 수는 아직 안 나갔다.
                #expect(store.dragOrigin == d2 && !store.isBusy && dwMoves(host).isEmpty,
                        "전제(\(variant.label)): 왕복이 시작되기 전에 다른 말을 집었다")
                #expect(store.pendingDrop?.to == e4, "\(variant.label): 다른 말을 집었더니 놓은 말의 꼬리표가 지워졌다")
                // 그 순간의 그림: 놓은 폰은 도착 칸에 **그대로** 서 있다(출발 칸으로 번쩍 돌아가지 않는다).
                let gap = try dwCapture(window)
                let ink = (e2: try dwWhiteInk(gap, "e2"), e4: try dwWhiteInk(gap, "e4"),
                           d2: try dwWhiteInk(gap, "d2"), d3: try dwWhiteInk(gap, "d3"))
                print("[실창 틈] \(variant.label) — 흰 잉크 e2/e4 \(ink.e2)/\(ink.e4) · d2/d3 \(ink.d2)/\(ink.d3)")
                #expect(ink.e2 == 0 && ink.e4 > 200,
                        "\(variant.label): 다른 말을 집자 놓은 폰이 출발 칸으로 돌아갔다(e2 \(ink.e2)px · e4 \(ink.e4)px)")
            }
            if variant.holds {
                // 쥔 채로 답을 기다린 뒤 갈 수 있는 칸에 놓는다 — **두 번째 수는 없다**(판이 나아가며 그 끌기는 거둬졌다).
                await dwSettle(turns: 300) { store.match?.plyCount == 1 }
                await dwSettle(turns: 5)
                print("[실창 틈] \(variant.label) — 답 뒤: 걸쇠 \(store.dragOrigin?.notation ?? "없음") · 보내는 중 \(store.isBusy)")
                try dwSend(window, .leftMouseDragged, at: try dwPoint("d4"), number: 2)
                try dwSend(window, .leftMouseUp, at: try dwPoint("d4"), number: 2)
            } else {
                try dwSend(window, .leftMouseUp, at: try dwPoint("d2"), number: 2)    // 제자리에 도로 놓는다(수 없음)
            }
            await dwSettle(turns: 300) { store.match?.plyCount == 1 }
            await dwSettle(turns: 20)
            print("[실창 틈] \(variant.label) — chess_move=\(dwMoves(host)) ply=\(store.match?.plyCount ?? -1) notice=\(store.notice ?? "무음")")
            #expect(dwMoves(host) == ["e2e4"],
                    "\(variant.label): 갈 수 있는 칸에 놓은 수가 \(dwMoves(host)) 로 나갔다 — 곧바로 다른 말을 집었더니 달라졌다")
            #expect(store.match?.plyCount == 1)
            #expect(store.pendingDropRecord == nil && store.dragOrigin == nil)
            dwClose(window, store)
        }
    }

    // MARK: - ⑦ 도착 칸 클릭이 칸 경계를 살짝 넘는다 — 손떨림은 누른 칸의 클릭이다

    @Test(.gomokuDefaultsCleanup)
    func aDestinationClickThatWigglesAcrossACellBorderStillMoves() async throws {
        // 없으면: e2 를 고른 뒤 도착 칸 e4 의 오른쪽 경계 0.4pt 안쪽을 누르고 0.4pt 바깥(f4)에서 떼면 **수도 문구도
        //        로그도 없다**(옛 탭 제스처는 같은 입력에 '둘 수 없는 자리예요' 라도 말했다). 지금은 누른 칸 e4 로 수가 나간다.
        //        문턱(4pt)을 넘겨 옆 칸에서 뗀 것은 클릭이 아니다 — 그건 여전히 아무 일도 없어야 한다(대조군).
        let e2 = try #require(ChessSquare("e2"))
        let border = ChessWindowLayout.cellSide / 2                 // 칸 가운데에서 오른쪽 경계까지
        // (경계 안쪽에서 누른 거리, 경계 바깥에서 뗀 거리, 수가 나가는가)
        let cases: [(inside: CGFloat, outside: CGFloat, moves: Bool)] = [
            (0.4, 0.4, true),       // 손떨림 0.8pt
            (1.5, 1.5, true),       // 손떨림 3.0pt
            (0.5, 4.5, false),      // 5.0pt — 문턱을 넘겨 옆 칸에서 뗐다
        ]
        for (index, item) in cases.enumerated() {
            let label = "손떨림 \(item.inside + item.outside)pt"
            let (store, host) = try await dwStore("wiggle-\(index)")
            let window = try await dwOpen(store)
            // ① 말을 고른다(가운데 클릭).
            try await dwClick(window, at: try dwPoint("e2"), number: 1)
            await dwSettle(turns: 30) { store.selection != nil }
            #expect(store.selection?.from == e2, "전제(\(label)): e2 를 골랐다")
            // ② 도착 칸의 오른쪽 경계 바로 안쪽을 누르고, 경계 바깥(f4)에서 뗀다.
            let down = try dwPoint("e4", dx: border - item.inside), up = try dwPoint("e4", dx: border + item.outside)
            store.notice = nil
            try dwSend(window, .leftMouseDown, at: down, number: 2)
            await dwSettle(turns: 2)
            try dwSend(window, .leftMouseDragged, at: up, number: 2)
            try dwSend(window, .leftMouseUp, at: up, number: 2)
            await dwSettle(turns: 60) { !dwMoves(host).isEmpty || store.notice != nil }
            await dwSettle(turns: 10)
            print("[실창 경계 클릭] \(label) — chess_move=\(dwMoves(host)) notice=\(store.notice ?? "무음") 고른 칸=\(store.selection?.from.notation ?? "없음")")
            if item.moves {
                #expect(dwMoves(host) == ["e2e4"], "\(label): 도착 칸 클릭이 \(dwMoves(host)) — 경계를 살짝 넘었다고 삼켜졌다")
                await dwSettle(turns: 300) { store.match?.plyCount == 1 }
                #expect(store.match?.plyCount == 1)
                #expect(store.pendingDropRecord == nil && store.dragOrigin == nil, "\(label): 클릭이 끌기로 읽혔다")
            } else {
                #expect(dwMoves(host).isEmpty, "\(label): 문턱을 넘겨 옆 칸에서 뗐는데 수가 나갔다: \(dwMoves(host))")
                #expect(store.notice == nil, "\(label): 문턱을 넘겨 옆 칸에서 뗐는데 '\(store.notice ?? "")' 라 말했다")
                #expect(store.selection?.from == e2, "\(label): 고르기가 풀렸다")
                #expect(store.match?.plyCount == 0)
            }
            dwClose(window, store)
        }
    }

    // MARK: - ⑧ 뒤집힌 판(흑 시점) — 누른 점 · 끄는 말 · 도착 칸 덮개 · 놓는 칸이 전부 뒤집힌 좌표로 맞는다

    @Test(.gomokuDefaultsCleanup)
    func draggingAsBlackOnTheFlippedBoardSendsTheMirroredMove() async throws {
        // 없으면: 위 끌기 시험은 전부 백 시점이다 — 흑으로 두는 사람의 판에서만 좌표 뒤집기가 깨져도(다른 말이 집힌다 ·
        //        끄는 말이 커서 반대쪽에 그려진다 · 도착 칸 덮개가 거울 칸에 뜬다 · 수가 거울 칸으로 나간다) 초록이다.
        let (store, host) = try await dwStore("black-drag", me: dwBlackID, stateBody: try dwBlackToMoveState(),
                                              move: "chess_move__ok_black_reply")
        let window = try await dwOpen(store)
        defer { dwClose(window, store) }
        #expect(store.phase == .playing)
        #expect(store.match?.myColor == .black && store.match?.isMyTurn == true && store.match?.plyCount == 1,
                "전제: 흑으로 두는 내 차례(1.e4 뒤)")
        let g = ChessBoardGeometry(side: ChessWindowLayout.boardSide, orientation: .black)
        let white = ChessBoardGeometry(side: ChessWindowLayout.boardSide, orientation: .white)
        let e7 = try #require(ChessSquare("e7")), e5 = try #require(ChessSquare("e5"))
        let e6 = try #require(ChessSquare("e6")), c5 = try #require(ChessSquare("c5"))
        // 뒤집히지 않은 판이라면 같은 화면 점은 d2(백 폰)다 — 뒤집기가 빠지면 집히는 말이 달라진다.
        #expect(white.square(at: g.center(of: e7))?.notation == "d2", "전제: 흑 시점의 e7 자리는 백 시점의 d2 다")

        let press = g.center(of: e7)
        // 놓는 점은 e5 칸 안에서 **가운데를 벗어난** 자리 — 말 중심이 커서를 따라오는지를 잰다.
        let drop = CGPoint(x: g.center(of: e5).x + 11, y: g.center(of: e5).y - 7)
        #expect(g.square(at: drop) == e5)
        let cell = ChessWindowLayout.cellSide
        /// 그 칸 가운데 50% 상자(창 콘텐츠 좌표, 흑 시점).
        func cellBox(_ square: ChessSquare) -> CGRect {
            let c = dwContent(g.center(of: square))
            return CGRect(x: c.x - cell * 0.25, y: c.y - cell * 0.25, width: cell * 0.5, height: cell * 0.5)
        }
        let resting = try dwCapture(window)
        let restingE7 = dwDarkInk(resting, in: cellBox(e7)).count
        #expect(restingE7 > 200, "전제: 멈춘 판의 e7(흑 시점 자리)에 흑 폰이 있다(\(restingE7)px)")
        #expect(dwDarkInk(resting, in: cellBox(e5)).count == 0, "전제: e5 는 비었다")

        try await dwPressAndDrag(window, from: dwContent(press), to: dwContent(drop), number: 1)
        await dwSettle(turns: 30) { store.dragOrigin != nil }
        #expect(store.dragOrigin == e7, "흑 시점에서 e7 을 눌러 끌었는데 집힌 칸이 \(store.dragOrigin?.notation ?? "없음")")
        #expect(store.selection == ChessSelection(from: e7, targets: [e6, e5]))
        #expect(dwMoves(host).isEmpty)

        // 끄는 중의 그림: 출발 칸은 비었고, 말은 **커서 자리**에 1.12배로 있다.
        let dragging = try dwCapture(window)
        let sourceInk = dwDarkInk(dragging, in: cellBox(e7)).count
        #expect(sourceInk == 0, "끄는 중인데 출발 칸(e7)에 말이 그려진다(\(sourceInk)px)")
        let cursor = dwContent(drop)
        // 커서 둘레(위쪽은 e4 백 폰의 테두리를 피한다).
        let around = dwDarkInk(dragging, in: CGRect(x: cursor.x - 46, y: cursor.y - 30, width: 92, height: 76))
        let bounds = try #require(around.bounds, "끄는 중인데 커서 둘레에 말이 없다")
        // 폰 실루엣: 좌우 대칭(가운데 x = 커서 x), 세로는 머리 꼭대기 0.215 ~ 받침 0.91 → 가운데가 커서보다 조금 아래다.
        let pieceSide = cell * ChessPieceArt.fillFraction * CGFloat(ChessBoardLift.cursorScale)
        let expectedMidY = cursor.y - pieceSide / 2 + pieceSide * (0.215 + 0.91) / 2
        #expect(abs(bounds.midX - cursor.x) <= 1.5, "끄는 말의 가운데 x 가 커서에서 \(bounds.midX - cursor.x)pt 어긋났다")
        #expect(abs(bounds.midY - expectedMidY) <= 2.5, "끄는 말의 가운데 y 가 기대에서 \(bounds.midY - expectedMidY)pt 어긋났다")
        // 1.12배: 멈춘 폰(d7)의 폭과 견준다.
        let d7 = dwContent(g.center(of: try #require(ChessSquare("d7"))))
        let restingPawn = try #require(dwDarkInk(dragging, in: CGRect(x: d7.x - 38, y: d7.y - 38, width: 76, height: 76)).bounds)
        let ratio = bounds.width / restingPawn.width
        #expect(ratio > 1.06 && ratio < 1.18, "끄는 말의 크기가 ×\(ratio) 다 — 1.12배여야 한다")
        // 도착 칸 덮개: e5 모서리(말·점이 안 닿는 6pt 안쪽)가 같은 색 칸 c5 모서리와 달라야 한다.
        func corner(_ square: ChessSquare) -> CGPoint {
            let box = g.rect(of: square)
            return dwContent(CGPoint(x: box.minX + 6, y: box.maxY - 6))
        }
        let tinted = dwPixel(dragging, at: corner(e5)), plain = dwPixel(dragging, at: corner(c5))
        print("[실창 흑] 끄는 말 상자 \(bounds) · 커서 \(cursor) · 폭 ×\(ratio) · 덮개 e5 \(tinted) / c5 \(plain)")
        #expect(dwDelta(dwPixel(resting, at: corner(e5)), plain) <= 2, "전제: 멈춘 판에서는 e5 와 c5 모서리가 같은 색이다")
        #expect(dwDelta(tinted, plain) > 8, "커서 밑 도착 칸(e5)에 덮개가 없다")
        // 뒤집히지 않은 좌표로 덮개를 그렸다면 색이 변했을 칸(같은 화면 자리의 거울 = d4)은 그대로다.
        let d4 = try #require(ChessSquare("d4"))
        #expect(dwDelta(dwPixel(dragging, at: corner(d4)), dwPixel(resting, at: corner(d4))) <= 2,
                "도착 칸 덮개가 거울 칸에 그려졌다")

        try dwSend(window, .leftMouseUp, at: dwContent(drop), number: 1)
        #expect(store.match?.plyCount == 1, "전제: 뗀 틱에는 답이 아직 없다")
        let dropped = try dwCapture(window)
        let droppedInk = (e7: dwDarkInk(dropped, in: cellBox(e7)).count, e5: dwDarkInk(dropped, in: cellBox(e5)).count)
        print("[실창 흑] 어두운 잉크 e7/e5 — 멈춤 \(restingE7)/0 · 끄는 중 \(sourceInk)/— · 뗀 틱 \(droppedInk.e7)/\(droppedInk.e5)")
        #expect(droppedInk.e7 == 0, "뗀 틱에 말이 출발 칸으로 되돌아갔다")
        #expect(droppedInk.e5 > 200, "뗀 틱에 도착 칸(e5)에 말이 없다")

        await dwSettle(turns: 300) { store.match?.plyCount == 2 }
        #expect(dwMoves(host) == ["e7e5"], "흑 시점에서 끌어 놓은 수가 \(dwMoves(host)) 로 나갔다")
        #expect(store.match?.plyCount == 2)
        #expect(store.match?.position?[e5] == ChessPiece(.black, .pawn))
        #expect(store.pendingDrop == nil && store.pendingDropRecord == nil && store.dragOrigin == nil)
        #expect(store.flight == nil, "끌어 놓은 말이 다시 미끄러졌다")
        let settled = try dwCapture(window)
        #expect(dwDarkInk(settled, in: cellBox(e5)).count > 200)
        #expect(dwDarkInk(settled, in: cellBox(e7)).count == 0)
    }

    @Test(.gomokuDefaultsCleanup)
    func clickClickAsBlackStillSendsTheMirroredMove() async throws {
        // 없으면: 흑 시점의 클릭-클릭이 거울 칸을 골라도 초록이다(위 클릭 시험도 백 시점뿐이다).
        let (store, host) = try await dwStore("black-click", me: dwBlackID, stateBody: try dwBlackToMoveState(),
                                              move: "chess_move__ok_black_reply")
        let window = try await dwOpen(store)
        defer { dwClose(window, store) }
        let e7 = try #require(ChessSquare("e7"))
        try await dwClick(window, at: try dwPoint("e7", orientation: .black), number: 1)
        await dwSettle(turns: 30) { store.selection != nil }
        #expect(store.selection?.from == e7, "흑 시점에서 e7 을 눌렀는데 고른 칸이 \(store.selection?.from.notation ?? "없음")")
        #expect(store.dragOrigin == nil)
        try await dwClick(window, at: try dwPoint("e5", orientation: .black), number: 2)
        await dwSettle(turns: 300) { store.match?.plyCount == 2 }
        #expect(dwMoves(host) == ["e7e5"], "흑 시점의 클릭-클릭이 \(dwMoves(host)) 로 나갔다")
        #expect(store.pendingDropRecord == nil, "클릭 길이 놓은 말의 꼬리표를 세웠다")
    }

    @Test(.gomokuDefaultsCleanup)
    func onTheFlippedBoardDroppingOutsideKeepsTheSelectionAndTheNextDragMoves() async throws {
        // 없으면: 뒤집힌 판의 **가장자리 줄**(흑 시점에서 a 줄은 오른쪽 끝, h 줄은 왼쪽 끝)에서 좌표가 한 칸 밀려도,
        //        판 밖으로 끈 말이 변에 걸려 반쪽만 보여도 초록이다.
        let (store, host) = try await dwStore("black-edge", me: dwBlackID, stateBody: try dwBlackToMoveState(),
                                              move: "chess_move__ok_black_reply")
        let window = try await dwOpen(store)
        defer { dwClose(window, store) }
        let side = ChessWindowLayout.boardSide
        let g = ChessBoardGeometry(side: side, orientation: .black)
        let a7 = try #require(ChessSquare("a7")), h7 = try #require(ChessSquare("h7"))
        #expect(g.rect(of: a7).maxX == side && g.rect(of: h7).minX == 0, "전제: 흑 시점에서 a 줄이 오른쪽 끝이다")

        // a7 을 집어 판 오른쪽 밖(오른쪽 열 위)으로 끈다. 그 줄 위쪽(6·5랭크)은 비어 있다.
        let outside = CGPoint(x: side + 40, y: g.center(of: a7).y - 90)
        try await dwPressAndDrag(window, from: dwContent(g.center(of: a7)), to: dwContent(outside), number: 1)
        #expect(store.dragOrigin == a7, "흑 시점 오른쪽 끝 칸에서 집힌 말이 \(store.dragOrigin?.notation ?? "없음")")
        // 판 밖으로 나간 말은 판 변 안쪽에 **통째로** 그려진다 — 사라지지도, 변에 걸려 잘리지도 않는다.
        let clamped = try dwCapture(window)
        // 판 오른쪽 변 안쪽 100pt 띠에서 잰다. 변의 마지막 1pt 는 뺀다 — 그 바깥은 창 바탕(어둡다)이라 잉크로 세어진다.
        let edgeX = dwContent(CGPoint(x: side, y: 0)).x
        let nearEdge = dwContent(CGPoint(x: side - 100, y: outside.y - 50))
        let pawn = try #require(dwDarkInk(clamped, in: CGRect(x: nearEdge.x, y: nearEdge.y, width: 99, height: 100)).bounds,
                                "판 밖으로 끌었더니 말이 사라졌다")
        // 온전한 말의 기준: 같은 그림에 멈춰 있는 폰(b7)의 폭 × 1.12.
        let b7 = dwContent(g.center(of: try #require(ChessSquare("b7"))))
        let restingPawn = try #require(dwDarkInk(clamped, in: CGRect(x: b7.x - 38, y: b7.y - 38, width: 76, height: 76)).bounds)
        let ratio = pawn.width / restingPawn.width
        print("[실창 흑 가장자리] 판 밖으로 끈 폰 상자 \(pawn) · 멈춘 폰 폭 \(restingPawn.width)pt · ×\(ratio) · 판 오른쪽 변 x=\(edgeX)")
        // 창 캡처는 1pt 눈금이라 폭이 ±1pt 흔들린다(34pt 폰의 1.12배 = 38pt 안팎). 변에 걸려 잘리면 0.6배 밑이다.
        #expect(ratio > 1.0 && ratio < 1.2, "판 변에서 끄는 말이 잘렸다 — 폭이 멈춘 폰의 ×\(ratio)(1.12배여야 한다)")
        #expect(pawn.maxX < edgeX - 1, "끄는 말이 판 오른쪽 변에 닿았다(오른쪽 끝 x=\(pawn.maxX)) — 변에서 잘렸다")

        try dwSend(window, .leftMouseUp, at: dwContent(outside), number: 1)
        await dwSettle(turns: 20)
        #expect(dwMoves(host).isEmpty && store.notice == nil, "판 밖에 놓았는데 수·안내가 났다")
        #expect(store.selection?.from == a7, "판 밖에 놓았더니 고르기가 풀렸다")

        // 왼쪽 끝 줄(h)을 두 칸 민다.
        try await dwPressAndDrag(window, from: try dwPoint("h7", orientation: .black),
                                 to: try dwPoint("h5", orientation: .black), number: 2)
        #expect(store.dragOrigin == h7)
        try dwSend(window, .leftMouseUp, at: try dwPoint("h5", orientation: .black), number: 2)
        await dwSettle(turns: 60) { !dwMoves(host).isEmpty }
        #expect(dwMoves(host) == ["h7h5"], "흑 시점 왼쪽 끝 줄을 끌어 둔 수가 \(dwMoves(host))")
    }
}
