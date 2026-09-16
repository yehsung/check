import AppKit
import Foundation
import Testing
@testable import check

// MARK: - 스페이스 모니터가 다른 창에 키를 양보한다 (v0.3.30 — 2026-09-17 실사용 제보)
//
// "미니게임에서 오목 로비로 들어간 상태에서 채팅을 치니 띄어쓰기가 아예 안 됐다."
// 미니게임 창의 스페이스 모니터는 게이트가 "게임 창이 화면에 떠 있는가" 하나뿐이라, 게임 창을 띄워 둔 채
// 오목 창에서 누른 스페이스까지 점프로 삼켰다. 판정은 `MiniGameSpaceKey.yieldsToOtherWindow` 한 곳이고,
// 여기서는 **진짜 NSWindow** 로 잰다(합성 이벤트로는 이 앱의 창이 열리지 않는다 — 판정만 순수하게 뺀 이유).

/// 화면에 올리되 보이지 않게(알파 0) — `isVisible` 은 올려야 참이다.
@MainActor
private func syWindow(identifier: String? = nil, textFocused: Bool = false, onScreen: Bool = true) -> NSWindow {
    let window = NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: 200, height: 80),
                          styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.alphaValue = 0
    if let identifier { window.identifier = NSUserInterfaceItemIdentifier(identifier) }
    let content = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 80))
    window.contentView = content
    if onScreen { window.orderFrontRegardless() }
    if textFocused {
        let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 200, height: 40))
        content.addSubview(textView)
        window.makeFirstResponder(textView)
    }
    return window
}

@MainActor
@Test
func theGameKeepsSpaceWhenTheKeyHasNoWindowYetOrIsTheGameWindow() {
    let game = syWindow(identifier: CheckMiniGameWindowController.frameAutosaveName)
    defer { game.orderOut(nil) }
    // 창을 막 연 그 순간(키가 아직 안 넘어옴) — 2026-09-09 에 고친 경로가 되살아나면 안 된다.
    #expect(!MiniGameSpaceKey.yieldsToOtherWindow(nil, gameWindow: game))
    #expect(!MiniGameSpaceKey.yieldsToOtherWindow(game, gameWindow: game))
    // 게임 창이 아직 없을 때도 창 없는 키는 게임 몫이다.
    #expect(!MiniGameSpaceKey.yieldsToOtherWindow(nil, gameWindow: nil))
}

@MainActor
@Test
func spaceTypedIntoTheGomokuWindowIsNeverTakenByTheGame() {
    let game = syWindow(identifier: CheckMiniGameWindowController.frameAutosaveName)
    let gomoku = syWindow(identifier: CheckGomokuWindowController.frameAutosaveName)
    let gomokuTyping = syWindow(identifier: CheckGomokuWindowController.frameAutosaveName, textFocused: true)
    let settings = syWindow(identifier: CheckSettingsWindowController.frameAutosaveName)
    defer { [game, gomoku, gomokuTyping, settings].forEach { $0.orderOut(nil) } }

    #expect(gomokuTyping.firstResponder is NSText, "전제: 채팅 입력칸이 첫 응답자다")
    #expect(MiniGameSpaceKey.yieldsToOtherWindow(gomokuTyping, gameWindow: game), "오목 채팅의 띄어쓰기를 삼킨다 — 제보된 증상")
    #expect(MiniGameSpaceKey.yieldsToOtherWindow(gomoku, gameWindow: game), "오목 판을 보는 중의 스페이스로 뒤의 게임이 점프한다")
    #expect(MiniGameSpaceKey.yieldsToOtherWindow(settings, gameWindow: game))
}

@MainActor
@Test
func typingInAnyOtherVisibleWindowWinsButAnUnknownIdleWindowDoesNot() {
    let game = syWindow(identifier: CheckMiniGameWindowController.frameAutosaveName)
    // 팝오버처럼 식별자가 없는 창: 글을 쓰는 중이면 양보, 아니면(팝오버가 닫히며 키가 넘어가는 순간) 게임 몫.
    let typing = syWindow(textFocused: true)
    let idle = syWindow()
    // 화면에서 내려간 창은 키의 주인이 아니다.
    let hidden = syWindow(identifier: CheckGomokuWindowController.frameAutosaveName, textFocused: true, onScreen: false)
    defer { [game, typing, idle, hidden].forEach { $0.orderOut(nil) } }

    #expect(MiniGameSpaceKey.yieldsToOtherWindow(typing, gameWindow: game))
    #expect(!MiniGameSpaceKey.yieldsToOtherWindow(idle, gameWindow: game))
    #expect(!hidden.isVisible, "전제: 올리지 않은 창")
    #expect(!MiniGameSpaceKey.yieldsToOtherWindow(hidden, gameWindow: game))
}

/// 소스 계약: 판정 함수가 있어도 모니터가 안 부르거나, 화면이 게임 창을 안 넘기면 아무것도 안 바뀐 채 초록이다.
@Test
func theMonitorAsksTheYieldRuleBeforeItsGateAndTheScreenPassesTheGameWindow() throws {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/check/MiniGamePanel.swift")
    let source = syStrippingLineComments(try String(contentsOf: url, encoding: .utf8))
    let start = try #require(source.range(of: "static func install(shouldConsume:")).lowerBound
    let end = try #require(source.range(of: "static func remove()", range: start..<source.endIndex)).lowerBound
    let install = String(source[start..<end])
    #expect(install.contains("NSApp.window(withWindowNumber: windowNumber)"), "키가 향한 창을 이벤트에서 찾아야 한다")
    let yield = try #require(install.range(of: "yieldsToOtherWindow(target, gameWindow: gameWindow())"),
                             "모니터가 양보 판정을 부르지 않는다")
    let gate = try #require(install.range(of: "guard shouldConsume()"))
    #expect(yield.lowerBound < gate.lowerBound, "양보 판정은 게이트보다 먼저다(게이트를 통과하면 곧바로 삼킨다)")
    #expect(!install.contains("isKeyWindow"), "키 창 요구는 여전히 금지 — 창을 막 연 순간이 죽는다")
    #expect(source.contains("gameWindow: { CheckMiniGameWindowController.shared.currentWindow }"),
            "화면이 게임 창을 넘기지 않으면 모든 창이 '게임 창이 아님'으로 판정된다")
}

/// 줄 주석만 걷어낸다(이 파일이 보는 구간에는 블록 주석이 없다).
private func syStrippingLineComments(_ source: String) -> String {
    source.split(separator: "\n", omittingEmptySubsequences: false).map { line -> Substring in
        guard let comment = line.range(of: "//") else { return line }
        return line[..<comment.lowerBound]
    }.joined(separator: "\n")
}
