import Foundation
import Testing
@testable import check
@testable import CheckCore

// v0.3.50 — 미니게임 창 머리글의 **1:1 대결 입구**(오목 · 체스)는 대결 창을 띄우고 **미니게임 창을 내린다**.
//
// 예전: 입구가 대결 창만 열어, 로비 창이 뜬 뒤에도 미니게임 창이 남아 창 둘이 떠 있었다(2026-10-13 사용자 요청).
// 지금: 패널의 두 입구가 스토어의 한 문(`openGomokuFromMiniGame` · `openChessFromMiniGame`)을 지난다.
//
// 여기서 지키는 것:
//  ① 문을 지나면 그 대결 창이 **정확히 한 번** 뜨고, 다른 대결 창은 안 뜬다.
//  ② **여는 것이 먼저**다 — 대결 창이 뜨는 순간 미니게임 창은 아직 보인다(대결 창이 키를 가져간 뒤에 내린다).
//  ③ 끝나면 미니게임 창이 내려가 있고 판 중단 토큰이 한 번 오른다(`closeMiniGamePanel` 의 계약 그대로).
//  ④ 미니게임 창이 이미 닫혀 있어도 대결 창은 뜬다 — 토큰은 헛되이 오르지 않는다.
//  ⑤ 패널의 버튼이 그 문에 이어져 있다(소스 계약 — 문만 있고 아무도 안 부르면 ①~④ 가 전부 초록인 채로 창이 안 닫힌다).
//
// 각 시험의 첫 줄 주석은 **"없으면 어떤 결함이 초록으로 통과하는가"** 다(관례).

// MARK: - 하네스

@MainActor
private enum MDERetention {
    /// 오목·체스 스토어는 소유자를 **약참조**한다 — 테스트가 버리면 `openWindow` 의 세션 가드가 다른 이유로 닫힌다.
    static var stores: [WorkTimerStore] = []
}

/// **세션 없는** 소유자 한 벌 + 스텁 호스트. 세션이 없으므로 `openWindow` 는 요청 없이 `presentWindow` 만 부른다 —
/// 그 사실도 시험이 잰다(스텁에 도착한 요청 0건).
@MainActor
private func mdeStore(_ label: String) -> (WorkTimerStore, String) {
    let host = "v0350-mde-\(label)-\(UUID().uuidString.prefix(8))".lowercased()
    GomokuStubProtocol.register(host: host) { _, _, _ in nil }
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!,
        anonKey: "anon-test-key",
        session: GomokuStubProtocol.session()
    )
    let store = WorkTimerStore(
        service: service,
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: GomokuTestDefaults.make("v0350-minigame-entry"),
        workspaceNotifications: nil
    )
    MDERetention.stores.append(store)
    return (store, host)
}

/// 대결 창이 뜬 기록: 불린 횟수와 **그 순간** 미니게임 창이 보였는가.
@MainActor
private final class MDEPresentLog {
    private(set) var miniGameVisibleAtOpen: [Bool] = []
    var count: Int { miniGameVisibleAtOpen.count }
    func record(_ visible: Bool) { miniGameVisibleAtOpen.append(visible) }
}

/// 두 대결 스토어의 '창 띄우기' 문에 기록기를 건다(제품에서는 `CheckApp` 의 wireGomoku·wireChess 가 건다).
@MainActor
private func mdeWire(_ store: WorkTimerStore) -> (gomoku: MDEPresentLog, chess: MDEPresentLog) {
    let gomoku = MDEPresentLog()
    let chess = MDEPresentLog()
    store.gomoku.presentWindow = { [weak store] in gomoku.record(store?.isMiniGamePanelVisible ?? false) }
    store.chess.presentWindow = { [weak store] in chess.record(store?.isMiniGamePanelVisible ?? false) }
    return (gomoku, chess)
}

private func mdeSource(_ name: String) throws -> String {
    let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/check", isDirectory: true)
    return try String(contentsOf: directory.appendingCheckSourcePath(name), encoding: .utf8)
}

/// 주석을 걷어내고 공백을 한 칸으로 접는다. **안 걷어내면 설명을 지워야만 초록이 되는 테스트가 된다.**
private func mdeStripped(_ source: String) -> String {
    var out = ""
    var inLine = false, inBlock = false, inString = false, escaped = false
    var index = source.startIndex
    while index < source.endIndex {
        let c = source[index]
        let nextIndex = source.index(after: index)
        let next: Character? = nextIndex < source.endIndex ? source[nextIndex] : nil
        if inLine {
            if c == "\n" { inLine = false; out.append(c) }
        } else if inBlock {
            if c == "*", next == "/" { inBlock = false; index = nextIndex }
        } else if inString {
            out.append(c)
            if escaped { escaped = false }
            else if c == "\\" { escaped = true }
            else if c == "\"" { inString = false }
        } else if c == "/", next == "/" {
            inLine = true; index = nextIndex
        } else if c == "/", next == "*" {
            inBlock = true; index = nextIndex
        } else if c == "\"" {
            inString = true; out.append(c)
        } else {
            out.append(c)
        }
        index = source.index(after: index)
    }
    return out.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
}

/// 걷어낸 소스에서 `func name(` 의 본문(바깥 중괄호 안쪽).
private func mdeFunctionBody(_ source: String, name: String) -> String? {
    guard let declaration = source.range(of: "func \(name)(") else { return nil }
    guard let open = source.range(of: "{", range: declaration.upperBound..<source.endIndex) else { return nil }
    var depth = 0
    var index = open.lowerBound
    while index < source.endIndex {
        let character = source[index]
        if character == "{" { depth += 1 }
        if character == "}" {
            depth -= 1
            if depth == 0 { return String(source[open.upperBound..<index]) }
        }
        index = source.index(after: index)
    }
    return nil
}

// MARK: - 시험

@Suite("0.3.50 — 미니게임 창의 1:1 대결 입구")
struct V0350MiniGameDuelEntryTests {

    // MARK: ①②③ 오목 입구

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func theGomokuEntryOpensTheDuelWindowThenClosesTheMiniGameWindow() async throws {
        // 없으면: 입구가 오목 창만 열고 미니게임 창을 그대로 둔다(창 둘이 떠 있다 — 신고 그대로). 또는 먼저 내리고
        //        나중에 열어, 대결 창이 키를 가져가기 전에 미니게임 창이 사라진다.
        let (store, host) = mdeStore("gomoku")
        let logs = mdeWire(store)
        store.isMiniGamePanelVisible = true
        let token = store.miniGameInterruptToken

        store.openGomokuFromMiniGame()

        #expect(logs.gomoku.count == 1, "오목 창이 \(logs.gomoku.count)번 떴다(기대 1)")
        #expect(logs.gomoku.miniGameVisibleAtOpen == [true],
                "오목 창이 뜨는 순간 미니게임 창이 이미 내려가 있었다 — 여는 것이 먼저다")
        #expect(logs.chess.count == 0, "오목 입구가 체스 창을 띄웠다")
        #expect(store.isMiniGamePanelVisible == false, "오목 창이 떴는데 미니게임 창이 남았다 — 창 둘이 떠 있다")
        #expect(store.miniGameInterruptToken == token + 1,
                "미니게임 창을 내리며 판 중단 토큰이 정확히 한 번 올라야 한다(정지해 둔 판이 남으면 안 된다)")

        // 세션이 없으면 입구는 요청을 한 건도 안 낸다(창을 띄울 뿐이다).
        try? await Task.sleep(for: .milliseconds(100))
        #expect(GomokuStubProtocol.calls(host: host).isEmpty,
                "세션 없는 입구가 요청을 냈다: \(GomokuStubProtocol.calls(host: host).map(\.rpc))")
    }

    // MARK: ①②③ 체스 입구(대칭)

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func theChessEntryOpensTheDuelWindowThenClosesTheMiniGameWindow() async throws {
        // 없으면: 오목 쪽만 고쳐지고 체스 입구는 여전히 미니게임 창을 남긴다(두 문이 따로라 한쪽만 빠져도 조용하다).
        let (store, host) = mdeStore("chess")
        let logs = mdeWire(store)
        store.isMiniGamePanelVisible = true
        let token = store.miniGameInterruptToken

        store.openChessFromMiniGame()

        #expect(logs.chess.count == 1, "체스 창이 \(logs.chess.count)번 떴다(기대 1)")
        #expect(logs.chess.miniGameVisibleAtOpen == [true],
                "체스 창이 뜨는 순간 미니게임 창이 이미 내려가 있었다 — 여는 것이 먼저다")
        #expect(logs.gomoku.count == 0, "체스 입구가 오목 창을 띄웠다")
        #expect(store.isMiniGamePanelVisible == false, "체스 창이 떴는데 미니게임 창이 남았다 — 창 둘이 떠 있다")
        #expect(store.miniGameInterruptToken == token + 1)

        try? await Task.sleep(for: .milliseconds(100))
        #expect(GomokuStubProtocol.calls(host: host).isEmpty,
                "세션 없는 입구가 요청을 냈다: \(GomokuStubProtocol.calls(host: host).map(\.rpc))")
    }

    // MARK: ④ 미니게임 창이 이미 닫혀 있을 때

    @Test(.gomokuDefaultsCleanup)
    @MainActor
    func theEntriesStillOpenTheDuelWindowWhenTheMiniGameWindowIsAlreadyClosed() {
        // 없으면: 문이 "미니게임 창이 보일 때만" 으로 좁아져 닫힌 상태에서는 대결 창이 안 뜨거나, 닫을 창이 없는데도
        //        토큰이 올라 잎 뷰를 헛되이 깨운다(`closeMiniGamePanel` 의 가드).
        let (store, _) = mdeStore("already-closed")
        let logs = mdeWire(store)
        #expect(store.isMiniGamePanelVisible == false)
        let token = store.miniGameInterruptToken

        store.openGomokuFromMiniGame()
        store.openChessFromMiniGame()

        #expect(logs.gomoku.count == 1 && logs.chess.count == 1, "닫힌 상태에서 입구가 대결 창을 안 띄운다")
        #expect(logs.gomoku.miniGameVisibleAtOpen == [false] && logs.chess.miniGameVisibleAtOpen == [false])
        #expect(store.isMiniGamePanelVisible == false)
        #expect(store.miniGameInterruptToken == token, "닫을 미니게임 창이 없는데 판 중단 토큰이 올랐다")

        // ★ 기준선 갈림: 같은 문이 창이 보일 때는 토큰을 올린다(위 두 시험) — 두 입력이 다른 답을 낸다.
        store.isMiniGamePanelVisible = true
        store.openChessFromMiniGame()
        #expect(store.miniGameInterruptToken == token + 1)
        #expect(logs.chess.miniGameVisibleAtOpen == [false, true])
    }

    // MARK: ⑤ 패널의 버튼이 그 문에 이어져 있다

    @Test
    func thePanelEntriesGoThroughTheStoreDoors() throws {
        // 없으면: 스토어의 문은 멀쩡한데 패널이 옛 배선(대결 창만 여는 클로저)을 그대로 불러, 위 시험이 전부
        //        초록인 채로 미니게임 창이 안 닫힌다.
        let panel = mdeStripped(try mdeSource("MiniGamePanel.swift"))
        #expect(panel.contains("MiniGameGomokuEntryButton { onGomoku() }"), "머리글에 오목 입구 버튼이 없다")
        #expect(panel.contains("MiniGameChessEntryButton { onChess() }"), "머리글에 체스 입구 버튼이 없다")
        #expect(panel.contains("onGomoku: { store.openGomokuFromMiniGame() }"),
                "오목 입구가 스토어의 문을 안 지난다 — 미니게임 창이 안 닫힌다")
        #expect(panel.contains("onChess: { store.openChessFromMiniGame() }"),
                "체스 입구가 스토어의 문을 안 지난다 — 미니게임 창이 안 닫힌다")
        #expect(!panel.contains("onGomoku: { store.gomoku.openWindow(focusMatchID: nil) }"),
                "오목 입구에 옛 배선(대결 창만 연다)이 남았다")
        #expect(!panel.contains("onChess: { store.chess.openWindow(focusMatchID: nil) }"),
                "체스 입구에 옛 배선(대결 창만 연다)이 남았다")

        // 문 안쪽: 대결 창을 **먼저** 띄우고 그 뒤에 미니게임 창을 내린다(동작 시험 ②의 소스 쪽 짝).
        let store = mdeStripped(try mdeSource("WorkTimerStoreMiniGame.swift"))
        for (name, open) in [("openGomokuFromMiniGame", "gomoku.openWindow(focusMatchID: nil)"),
                             ("openChessFromMiniGame", "chess.openWindow(focusMatchID: nil)")] {
            let body = try #require(mdeFunctionBody(store, name: name), "\(name) 본문을 못 찾았다")
            let opened = try #require(body.range(of: open), "\(name) 이 대결 창을 안 연다")
            let closed = try #require(body.range(of: "closeMiniGamePanel()"), "\(name) 이 미니게임 창을 안 내린다")
            #expect(opened.lowerBound < closed.lowerBound, "\(name) 이 미니게임 창을 먼저 내린다 — 여는 것이 먼저다")
        }
    }
}
