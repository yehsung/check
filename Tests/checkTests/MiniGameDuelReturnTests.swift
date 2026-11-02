import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// 2026-11-03 대표 요청 ⑧ — 미니게임 창에서 들어간 대결 창을 사람이 닫으면 미니게임 창이 다시 선다.
//
// 원문: "미니게임 화면에서도 사람들이랑 붙은 게임들 누르면 해당 게임 로비로 가지잖아. 거기서 엑스 누르면 다시 기본 미니게임 창이
// 다시 뜨면서 교대되는 느낌이면 좋을듯."
// 들어갈 때는 0.3.50 부터 '대결 창 먼저, 미니게임 창 나중'으로 바꿔 넘어갔다(`V0350MiniGameDuelEntryTests`). 나올 때는 창만 닫히고
// 아무것도 안 남았다(메뉴바 앱이라 독 아이콘도 없다). 여기서 재는 것: ① 스토어의 되돌림 판정(네 문 · 사람 닫기만 · 미니게임에서
// 들어온 창만) ② 창 컨트롤러가 '사람이 닫았다'와 '프로그램이 닫았다'를 가려 알린다 ③ 앱 배선이 둘을 잇는다.

@MainActor
private enum MDRRetention { static var stores: [WorkTimerStore] = [] }

/// 세션 없는 소유자 한 벌(요청이 나가지 않는다 — 대결 창 여는 문은 `presentWindow` 만 부르고, 시험은 그 문을 비워 둔다).
@MainActor
private func mdrStore(_ label: String) -> WorkTimerStore {
    let host = "mdr-\(label)-\(UUID().uuidString.prefix(8))".lowercased()
    GomokuStubProtocol.register(host: host) { _, _, _ in nil }
    let service = SupabaseWorkService(projectURL: URL(string: "http://\(host)")!, anonKey: "anon-test-key",
                                      session: GomokuStubProtocol.session())
    let store = WorkTimerStore(service: service, environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
                               defaults: GomokuTestDefaults.make("mdr"), workspaceNotifications: nil)
    MDRRetention.stores.append(store)
    return store
}

@MainActor
private func mdrEnter(_ store: WorkTimerStore, _ door: MiniGameDuelDoor) {
    switch door {
    case .gomoku: store.openGomokuFromMiniGame()
    case .chess: store.openChessFromMiniGame()
    case .tetris: store.openTetrisDuelFromMiniGame()
    case .rummy: store.openRummyFromMiniGame()
    }
}

private func mdrSource(_ name: String) throws -> String {
    let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/check", isDirectory: true)
    return try String(contentsOf: directory.appendingCheckSourcePath(name), encoding: .utf8)
}

/// 주석 줄을 걷고 공백을 한 칸으로 접는다(설명 글에 같은 글자가 있어도 초록이 되지 않게).
private func mdrCode(_ source: String) -> String {
    source.split(separator: "\n", omittingEmptySubsequences: false)
        .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
        .joined(separator: "\n")
        .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
}

@Suite("⑧ 대결 창을 닫으면 미니게임 창으로 돌아온다(2026-11-03)", .serialized)
@MainActor
struct MiniGameDuelReturnTests {

    // MARK: ① 스토어 판정

    @Test("네 대결 창 모두: 미니게임 창에서 들어가 사람이 닫으면 미니게임 창이 다시 선다", .gomokuDefaultsCleanup,
          arguments: [MiniGameDuelDoor.gomoku, .chess, .tetris, .rummy])
    func closingTheDuelWindowReturnsToTheMiniGameWindow(door: MiniGameDuelDoor) {
        // 없으면: 대결 창을 닫으면 화면에 아무것도 안 남는다 — 사용자는 팝오버를 다시 열고 미니게임을 다시 눌러야 한다.
        let store = mdrStore("return")
        store.isMiniGamePanelVisible = true
        mdrEnter(store, door)
        #expect(!store.isMiniGamePanelVisible, "전제: 들어가면 미니게임 창이 내려간다(0.3.50)")
        #expect(store.miniGameDuelReturn == door)

        store.duelWindowDidClose(door, byUser: true)
        #expect(store.isMiniGamePanelVisible, "\(door) 창을 닫았는데 미니게임 창이 안 섰다")
        #expect(store.miniGameDuelReturn == nil, "표지가 남았다 — 다음에 다른 길로 연 창을 닫아도 미니게임 창이 튀어나온다")
        store.closeMiniGamePanel()
    }

    @Test("프로그램 닫기(로그아웃·계정 전환)는 미니게임 창을 띄우지 않고 표지만 지운다", .gomokuDefaultsCleanup)
    func programmaticCloseOnlyClearsTheMark() {
        let store = mdrStore("program")
        store.isMiniGamePanelVisible = true
        store.openGomokuFromMiniGame()
        store.duelWindowDidClose(.gomoku, byUser: false)
        #expect(!store.isMiniGamePanelVisible, "로그아웃으로 닫힌 오목 창이 미니게임 창을 띄웠다")
        #expect(store.miniGameDuelReturn == nil)
        // 다음에 사람이 같은 창을 닫아도(이번엔 팝오버에서 연 창) 미니게임 창은 안 선다.
        store.duelWindowDidClose(.gomoku, byUser: true)
        #expect(!store.isMiniGamePanelVisible)
    }

    @Test("미니게임 창에서 들어오지 않은 대결 창(팝오버 배너·말풍선·메뉴)은 닫으면 그냥 닫힌다 · 다른 창의 닫힘은 표지를 안 건드린다",
          .gomokuDefaultsCleanup)
    func onlyTheWindowEnteredFromTheMiniGameReturns() {
        let store = mdrStore("other")
        // 미니게임 창이 닫힌 채로 대결 창을 연 길(팝오버 배너 등) — 표지가 없다.
        store.openChessFromMiniGame()
        #expect(store.miniGameDuelReturn == nil, "미니게임 창이 안 떠 있었는데 표지를 적었다")
        store.duelWindowDidClose(.chess, byUser: true)
        #expect(!store.isMiniGamePanelVisible, "미니게임에서 오지 않은 체스 창을 닫았는데 미니게임 창이 섰다")

        // 미니게임에서 오목으로 들어갔는데 (따로 떠 있던) 체스 창을 닫았다 — 아무 일 없고, 오목을 닫을 때 돌아온다.
        store.isMiniGamePanelVisible = true
        store.openGomokuFromMiniGame()
        store.duelWindowDidClose(.chess, byUser: true)
        #expect(!store.isMiniGamePanelVisible && store.miniGameDuelReturn == .gomoku)
        store.duelWindowDidClose(.gomoku, byUser: true)
        #expect(store.isMiniGamePanelVisible)
        store.closeMiniGamePanel()
    }

    @Test("미니게임 창이 이미 다시 떠 있으면 대결 창을 닫아도 또 열지 않는다(표지는 지운다)", .gomokuDefaultsCleanup)
    func doesNotReopenAnAlreadyVisibleMiniGameWindow() {
        let store = mdrStore("visible")
        store.isMiniGamePanelVisible = true
        store.openTetrisDuelFromMiniGame()
        store.isMiniGamePanelVisible = true          // 사람이 팝오버에서 미니게임 창을 다시 열었다
        let token = store.miniGameInterruptToken
        store.duelWindowDidClose(.tetris, byUser: true)
        #expect(store.isMiniGamePanelVisible && store.miniGameDuelReturn == nil)
        #expect(store.miniGameInterruptToken == token, "떠 있던 미니게임 창의 판을 건드렸다")
        store.closeMiniGamePanel()
    }

    // MARK: ② 창 컨트롤러 — 사람이 닫았는가

    @Test("오목·체스·테트리스 창: 빨간 점(windowWillClose)은 '사람이 닫았다', close()(로그아웃의 orderOut)는 '프로그램'")
    func duelControllersTellUserCloseFromProgramClose() throws {
        var heard: [String] = []

        let gomoku = CheckGomokuWindowController()
        gomoku.configure(store: GomokuStore(), content: { _ in AnyView(Color.clear) })
        gomoku.onClosed = { heard.append("gomoku:\($0)") }
        defer { gomoku.discardWindowForTesting() }
        gomoku.show()
        let gw = try #require(gomoku.currentWindow)
        gomoku.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: gw))
        gomoku.show()
        gomoku.close()

        let chess = CheckChessWindowController()
        chess.configure(store: ChessStore(), content: { _ in AnyView(Color.clear) })
        chess.onClosed = { heard.append("chess:\($0)") }
        defer { chess.discardWindowForTesting() }
        chess.show()
        let cw = try #require(chess.currentWindow)
        chess.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: cw))
        chess.show()
        chess.close()

        let tetrisStore = TetrisDuelStore()
        tetrisStore.pollStepSeconds = 3_600
        tetrisStore.gameLoopStepSeconds = 3_600
        let tetris = CheckTetrisDuelWindowController()
        tetris.configure(store: tetrisStore, content: { _ in AnyView(Color.clear) })
        tetris.onClosed = { heard.append("tetris:\($0)") }
        defer { tetris.discardWindowForTesting() }
        tetris.show()
        let tw = try #require(tetris.currentWindow)
        tetris.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: tw))
        tetris.show()
        tetris.close()

        #expect(heard == ["gomoku:true", "gomoku:false", "chess:true", "chess:false", "tetris:true", "tetris:false"])
    }

    @Test("큐브 창: windowShouldClose 를 지난 닫기만 '사람' — 프로그램의 window.close()(로그아웃)는 '프로그램'")
    func rummyControllerTellsUserCloseFromProgramClose() throws {
        // 큐브는 로그아웃 정리가 `window.close()` 라 windowWillClose 가 **둘 다**에서 온다 — 그래서 windowShouldClose 로 가른다.
        var heard: [Bool] = []
        let store = RummyStore()
        let controller = CheckRummyWindowController(stuckWindowCheckSeconds: 60)
        controller.configure(store: store, content: { _ in AnyView(Color.clear) })
        controller.onClosed = { heard.append($0) }
        defer { controller.discardWindowForTesting() }
        controller.show()
        let window = try #require(controller.currentWindow)

        // 사람: 빨간 점 → windowShouldClose(로비라 묻지 않고 닫는다) → windowWillClose.
        #expect(controller.windowShouldClose(window))
        controller.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: window))
        // 프로그램: windowShouldClose 없이 windowWillClose.
        controller.show()
        controller.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: window))
        #expect(heard == [true, false])
    }

    // MARK: ③ 앱 배선

    @Test("CheckApp 이 네 창의 닫힘을 스토어의 duelWindowDidClose 로 잇는다(문마다 자기 이름으로)")
    func theAppWiresAllFourWindows() throws {
        // 없으면: 스토어 판정·컨트롤러 알림이 다 초록인데 둘을 잇는 줄이 없어 실제 앱에서는 아무 일도 안 일어난다.
        let app = mdrCode(try mdrSource("CheckApp.swift"))
        for (controller, door) in [("CheckGomokuWindowController", "gomoku"), ("CheckChessWindowController", "chess"),
                                   ("CheckTetrisDuelWindowController", "tetris"), ("CheckRummyWindowController", "rummy")] {
            let hook = try #require(app.range(of: "\(controller).shared.onClosed = {"), "\(controller) 의 닫힘을 안 잇는다")
            let body = String(app[hook.upperBound...].prefix(160))
            #expect(body.contains("duelWindowDidClose(.\(door), byUser: byUser)"), "\(controller) 가 다른 문 이름으로 이어졌다: \(body)")
        }
    }
}
