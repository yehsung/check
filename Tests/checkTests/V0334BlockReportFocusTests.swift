import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// v0.3.34 수리 둘 — 맥 신고·차단 시트가 **입력칸을 잃거나 엉뚱한 칸에 키를 주던** 결함(적대적 검토 2026-09-20, medium 둘).
//
// ① 오목 덮개 밑 채팅칸: 신고·차단 덮개는 판 위에 ZStack 으로 얹힐 뿐이라, 채팅하던 사람이 ··· → [신고하기]를 열어도
//    첫 응답자는 **가려진 채팅칸**(↩ 전송 칸)에 남았다. 칸을 누르지 않고 설명을 치면 그 글이 보이지 않는 채팅 초안에 쌓이고,
//    ↩ 를 누르면 신고하려던 **바로 그 사람에게** 채팅으로 나갔다. 자세히 칸을 눌러 쓰고 있어도 ⌘↩ 는 덮개 밑 [보내기]를 눌렀다.
// ② 팝오버 신고 시트의 자세히 칸: 본문 상자(`FeedbackListBox`)가 추정 높이와 상한을 비교해 if/else 두 갈래 중 하나를 그려서,
//    180자째에 카운터가 서거나(21pt) 보내기 실패 안내가 서서 상한이 45pt 줄면 갈래가 바뀌었다 — SwiftUI 는 그 아래를 통째로
//    다시 만들고, 자세히 칸은 **새 NSTextView** 가 되며 치던 포커스를 잃는다(새 칸은 한글 조합을 못 받는다 — `makeNSView` 주석).
//
// ★ 헤드리스 한계: 실제 입력기는 이 프로세스에서 안 돈다. ②는 V0328·V0334 와 같은 눈금(같은 NSTextView 를 쥐고 있는가 ·
//   첫 응답자가 남았는가)으로 잰다. ①의 키는 `window.sendEvent` 로 첫 응답자에게 흘린다(검증자 프로브와 같은 길).
// ★ 픽스처 본문은 전부 합성 문자열이다(퍼블릭 저장소).

private let bfPeerA = MessageReadFixture.peerA

@MainActor
private func bfStore(_ label: String) -> (store: WorkTimerStore, host: String) {
    makeMessageReadStore("bf-\(label)") { call, _ in
        if call.rpc == "app_user_directory" {
            return MessageReadStubProtocol.Reply(body: MessageReadFixture.json([
                ["user_id": bfPeerA, "display_name": "소라", "avatar_url": NSNull(), "is_working": true],
            ]))
        }
        return nil
    }
}

private func bfMatch() -> GomokuMatchState {
    GomokuMatchState(
        id: "11111111-2222-3333-4444-5555555555bf", stake: 3, myColor: .black,
        opponent: GomokuUser(id: bfPeerA, displayName: "소라", avatarURL: nil, characterID: nil,
                             isWorking: true, isCapable: true, inMatch: true),
        board: GomokuBoard(), lastMove: nil, moveCount: 0, turn: .black, deadline: nil, isFinished: false,
        outcome: nil, endReason: nil, rubyDelta: nil, blackPassed: false
    )
}

@MainActor
private func bfSpin(_ seconds: Double = 0.05) {
    RunLoop.current.run(until: Date().addingTimeInterval(seconds))
}

@MainActor
private func bfSpin(until condition: () -> Bool) {
    var remaining = 100
    while !condition(), remaining > 0 {
        bfSpin(0.01)
        remaining -= 1
    }
}

@MainActor
private func bfTextViews(in root: NSView) -> [CheckEditorTextView] {
    var found: [CheckEditorTextView] = []
    if let match = root as? CheckEditorTextView { found.append(match) }
    for child in root.subviews { found += bfTextViews(in: child) }
    return found
}

/// 칸을 **자기 창에** 세운다(화면에 올리지는 않는다 — 올리지 않아도 SwiftUI 는 마운트·반납을 하고 첫 응답자도 선다).
@MainActor
private func bfMount<V: View>(_ view: V, width: CGFloat, height: CGFloat) -> (NSWindow, NSHostingView<some View>) {
    let host = NSHostingView(rootView: view.frame(width: width, height: height))
    host.frame = NSRect(x: 0, y: 0, width: width, height: height)
    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    bfSpin()
    return (window, host)
}

@MainActor
private func bfKey(_ window: NSWindow, _ characters: String, keyCode: UInt16 = 0,
                   flags: NSEvent.ModifierFlags = []) -> NSEvent {
    NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: flags,
        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
        context: nil, characters: characters, charactersIgnoringModifiers: characters,
        isARepeat: false, keyCode: keyCode
    )!
}

@MainActor
private func bfReturn(_ window: NSWindow, command: Bool = false) -> NSEvent {
    bfKey(window, "\r", keyCode: 36, flags: command ? .command : [])
}

/// 메인 액터를 잠깐 내준다 — 채팅 전송은 메인 액터 Task 안에서 요청을 띄우므로, 동기로 런루프만 돌리면 그 Task 가 영영 안 돌아
/// 요청 수가 늘 0 이다(그러면 "안 보냈다"는 단언이 공짜로 초록이 된다). 런루프도 함께 돌린다(포커스 놓기 · 되찾기는 다음 턴이다).
@MainActor
private func bfSettle() async {
    for _ in 0..<5 {
        bfSpin(0.02)
        try? await Task.sleep(for: .milliseconds(20))
    }
}

/// 첫 응답자에게 글자를 한 자씩 흘린다(사용자가 칸을 누르지 않고 곧장 친 것).
@MainActor
private func bfType(_ text: String, in window: NSWindow) {
    for character in text {
        window.sendEvent(bfKey(window, String(character)))
    }
    bfSpin()
}

// MARK: - ① 오목 신고·차단 덮개가 서 있는 동안 채팅칸은 키를 받지 않는다

@MainActor
@Suite(.serialized) struct V0334GomokuOverlayChatLockTests {
    /// 덮개가 서면 채팅칸이 포커스를 놓고(조합 중 음절은 초안에 확정해 둔 채), 덮개 위에서 친 글·↩·⌘↩ 가 **어느 것도**
    /// 채팅으로 나가지 않는다. 덮개가 닫히면 채팅칸이 포커스를 되찾고 쓰던 초안 그대로 ↩ 로 보낸다(원래대로).
    @Test(.gomokuDefaultsCleanup)
    func 신고_덮개가_서면_채팅칸이_키를_놓고_덮개_위의_글과_리턴이_채팅으로_가지_않는다() async throws {
        CheckTextEditor.resetPoolForTesting()
        defer { CheckTextEditor.resetPoolForTesting() }
        let (store, host) = bfStore("overlay-report")
        store.gomoku.phase = .playing
        store.gomoku.match = bfMatch()
        let face = GomokuPlayerFace(name: "영식", avatarURL: nil, characterID: "shiba")
        let (window, hostView) = bfMount(
            GomokuPanel(store: store.gomoku, me: { face }, safety: store),
            width: GomokuWindowLayout.contentSize.width, height: GomokuWindowLayout.contentSize.height
        )
        let chat = try #require(bfTextViews(in: hostView).first, "채팅 칸이 안 섰다")
        try #require(bfTextViews(in: hostView).count == 1, "전제: 덮개 전에는 채팅 칸 하나다")

        // 채팅하던 중이다 — 초안이 있고, 마지막 음절은 조합 중이다.
        try #require(window.makeFirstResponder(chat))
        store.gomoku.chatDraft = "합성 초안"
        bfSpin()
        try #require(chat.string == "합성 초안")
        chat.setSelectedRange(NSRange(location: (chat.string as NSString).length, length: 0))
        chat.setMarkedText("요", selectedRange: NSRange(location: 1, length: 0),
                           replacementRange: NSRange(location: NSNotFound, length: 0))
        try #require(chat.hasMarkedText(), "전제: 조합 중인 음절이 섰다")

        // ··· → [신고하기]
        store.openReport(try #require(GomokuChatSafetyRule.target(for: store.gomoku)), surface: .gomoku)
        bfSpin(until: { window.firstResponder !== chat })
        let editors = bfTextViews(in: hostView)
        try #require(editors.count == 2, "덮개의 자세히 칸이 안 섰다: \(editors.count)")
        let detail = try #require(editors.first { $0 !== chat })

        #expect(window.firstResponder !== chat, "덮개가 섰는데 가려진 채팅칸이 아직 첫 응답자다 — 친 글이 그리로 간다")
        #expect(!chat.hasMarkedText(), "포커스를 놓으며 조합 중 음절을 확정하지 않았다")
        #expect(store.gomoku.chatDraft == "합성 초안요", "덮개가 쓰던 채팅 초안을 건드렸다: \(store.gomoku.chatDraft.debugDescription)")

        // 탭·클릭으로도 가려진 채팅칸에 들어갈 수 없다.
        _ = window.makeFirstResponder(chat)
        #expect(window.firstResponder !== chat, "덮개가 떠 있는데 채팅칸이 첫 응답자가 됐다")

        // 칸을 누르지 않고 곧장 설명을 친다 → 보이지 않는 채팅 초안에 쌓이면 안 된다.
        bfType("abc", in: window)
        #expect(store.gomoku.chatDraft == "합성 초안요", "덮개 위에서 친 글이 가려진 채팅 초안에 들어갔다: \(store.gomoku.chatDraft.debugDescription)")
        // ↩ — 채팅이 나가면 안 된다(신고하려던 바로 그 사람에게 간다).
        window.sendEvent(bfReturn(window))
        #expect(!store.gomoku.isSendingChat, "덮개 위의 ↩ 가 채팅 전송을 시작했다")
        await bfSettle()
        #expect(MessageReadStubProtocol.count(host: host, rpc: "gomoku_chat_send") == 0, "덮개 위의 ↩ 가 채팅을 보냈다")

        // 자세히 칸을 눌러 쓰다가 ↩(줄바꿈) · ⌘↩ — 둘 다 채팅을 보내면 안 된다.
        try #require(window.makeFirstResponder(detail), "덮개의 자세히 칸이 포커스를 못 받는다")
        bfType("xyz", in: window)
        #expect(store.reportDetailDraft == "xyz", "자세히 칸에 친 글이 초안에 안 올라갔다: \(store.reportDetailDraft.debugDescription)")
        window.sendEvent(bfReturn(window))
        bfSpin()
        #expect(detail.string == "xyz\n", "자세히 칸의 ↩ 가 줄바꿈이 아니다: \(detail.string.debugDescription)")
        _ = window.performKeyEquivalent(with: bfReturn(window, command: true))
        #expect(!store.gomoku.isSendingChat, "덮개 위의 ⌘↩ 가 덮개 밑 [보내기]를 눌렀다")
        await bfSettle()
        #expect(MessageReadStubProtocol.count(host: host, rpc: "gomoku_chat_send") == 0, "덮개 위의 ⌘↩ 가 채팅을 보냈다")
        #expect(store.blockReportSheet(on: .gomoku) != nil, "↩·⌘↩ 가 덮개를 닫았다")

        // 덮개를 닫는다(✕ · Esc 와 같은 문) — 채팅은 원래대로다: 포커스가 돌아오고, 초안 그대로 ↩ 로 나간다.
        store.closeBlockReportSheet()
        bfSpin(until: { window.firstResponder === chat })
        #expect(window.firstResponder === chat, "덮개가 닫혔는데 채팅칸이 포커스를 못 되찾았다")
        #expect(store.gomoku.chatDraft == "합성 초안요", "덮개를 닫자 쓰던 초안이 바뀌었다: \(store.gomoku.chatDraft.debugDescription)")
        window.sendEvent(bfReturn(window))
        #expect(store.gomoku.isSendingChat, "덮개를 닫은 뒤 ↩ 가 채팅 전송을 시작하지 않았다")
        await bfSettle()
        #expect(MessageReadStubProtocol.count(host: host, rpc: "gomoku_chat_send") == 1, "덮개를 닫은 뒤 ↩ 가 채팅을 안 보낸다")
        withExtendedLifetime(window) {}
    }

    /// 차단 확인 덮개도 같다. 기본 버튼인 줄 알고 ↩ 를 눌러도 차단은 안 되고(확인은 버튼으로만), 써 두던 초안도 안 나간다.
    @Test(.gomokuDefaultsCleanup)
    func 차단_확인_덮개_위의_리턴과_커맨드리턴도_채팅을_보내지_않는다() async throws {
        CheckTextEditor.resetPoolForTesting()
        defer { CheckTextEditor.resetPoolForTesting() }
        let (store, host) = bfStore("overlay-confirm")
        store.gomoku.phase = .playing
        store.gomoku.match = bfMatch()
        let face = GomokuPlayerFace(name: "영식", avatarURL: nil, characterID: "shiba")
        let (window, hostView) = bfMount(
            GomokuPanel(store: store.gomoku, me: { face }, safety: store),
            width: GomokuWindowLayout.contentSize.width, height: GomokuWindowLayout.contentSize.height
        )
        let chat = try #require(bfTextViews(in: hostView).first, "채팅 칸이 안 섰다")
        try #require(window.makeFirstResponder(chat))
        store.gomoku.chatDraft = "합성 초안"
        bfSpin()

        store.openBlockConfirm(try #require(GomokuChatSafetyRule.target(for: store.gomoku)), surface: .gomoku)
        bfSpin(until: { window.firstResponder !== chat })
        #expect(window.firstResponder !== chat, "차단 확인이 섰는데 가려진 채팅칸이 아직 첫 응답자다")

        window.sendEvent(bfReturn(window))
        _ = window.performKeyEquivalent(with: bfReturn(window, command: true))
        #expect(!store.gomoku.isSendingChat, "차단 확인 위의 ↩/⌘↩ 가 채팅 전송을 시작했다")
        await bfSettle()
        #expect(MessageReadStubProtocol.count(host: host, rpc: "gomoku_chat_send") == 0, "차단 확인 위의 ↩/⌘↩ 가 채팅을 보냈다")
        #expect(MessageReadStubProtocol.count(host: host, rpc: "block_user") == 0, "↩ 가 확인 버튼 없이 차단했다")
        #expect(store.blockHiddenPeerIDs.isEmpty)
        #expect(store.gomoku.chatDraft == "합성 초안")

        store.closeBlockReportSheet()
        bfSpin(until: { window.firstResponder === chat })
        #expect(window.firstResponder === chat, "차단 확인을 닫았는데 채팅칸이 포커스를 못 되찾았다")
        #expect(store.gomoku.chatDraft == "합성 초안")
        _ = window.performKeyEquivalent(with: bfReturn(window, command: true))
        #expect(store.gomoku.isSendingChat, "차단 확인을 닫은 뒤 ⌘↩ 가 채팅을 안 보낸다 — [보내기]가 막힌 채 남았다")
        await bfSettle()
        #expect(MessageReadStubProtocol.count(host: host, rpc: "gomoku_chat_send") == 1)
        withExtendedLifetime(window) {}
    }
}

// MARK: - ② 팝오버 신고 시트의 자세히 칸은 글자 수·안내 줄에 따라 새로 만들어지지 않는다

@MainActor
@Suite(.serialized) struct V0334ReportSheetEditorStabilityTests {
    /// 검증자가 잰 조합(대화 패널 위 크롬 110pt — 새 버전 배너 + 노트 한두 줄): 본문 추정이 상한 바로 아래라
    /// 카운터 줄(13 + 간격 8)이 서는 순간 옛 상자는 스크롤 갈래로 넘어갔다.
    static let extraChrome: CGFloat = 110

    @MainActor
    private func mountSheet(_ label: String) throws -> (WorkTimerStore, NSWindow, NSHostingView<some View>) {
        let (store, _) = bfStore(label)
        store.openMessagePanel(peer: bfPeerA)
        store.openReport(BlockReportTarget(peerID: bfPeerA, peerName: "소라"), surface: .message)
        store.selectReportReason(.spam)
        store.reportDetailDraft = String(repeating: "가", count: 179)
        let (window, host) = bfMount(
            CheckMessageView(store: store, extraChromeHeight: Self.extraChrome, onBack: {}),
            width: MessagePanelLayout.contentWidth + 24, height: 700
        )
        return (store, window, host)
    }

    @Test(.gomokuDefaultsCleanup)
    func 자세히_칸은_180자를_넘나들어도_같은_칸이고_포커스를_지킨다() throws {
        CheckTextEditor.resetPoolForTesting()
        defer { CheckTextEditor.resetPoolForTesting() }
        // 전제: 이 크롬에서는 본문(179자)이 상한 안이고, 카운터 줄 하나가 더해지면 상한을 넘는다 — 경계가 아니면 이 테스트는 늘 초록이다.
        let target = BlockReportTarget(peerID: bfPeerA, peerName: "소라")
        let cap = BlockReportSheetLayout.popoverBodyCap(extraChromeHeight: Self.extraChrome, hasFooterNotice: false)
        let body = BlockReportSheetLayout.reportBodyHeight(target: target, detail: String(repeating: "가", count: 179))
        try #require(body <= cap && body + 13 + BlockReportSheetLayout.spacing > cap,
                     "전제가 깨졌다(본문 \(body) · 상한 \(cap)) — 카운터가 설 때 상한을 넘는 경계를 다시 골라라")

        let (store, window, host) = try mountSheet("counter")
        let first = try #require(bfTextViews(in: host).first, "자세히 칸이 안 섰다")
        try #require(window.makeFirstResponder(first))

        // 180번째 글자를 친다 — 카운터가 선다.
        first.insertText("나", replacementRange: NSRange(location: NSNotFound, length: 0))
        bfSpin()
        try #require(BlockReportRules.detailCounterText(store.reportDetailDraft) != nil, "전제: 180자에서 카운터가 선다")
        let second = try #require(bfTextViews(in: host).first, "자세히 칸이 사라졌다")
        #expect(second === first, "카운터가 서는 순간 자세히 칸이 새 NSTextView 로 바뀌었다 — 새 칸은 한글 조합을 못 받는다")
        #expect(window.firstResponder === first, "카운터가 서는 순간 치던 칸이 포커스를 잃었다(다음 키가 칸에 안 들어간다)")

        // 179자로 지운다 — 카운터가 진다.
        first.deleteBackward(nil)
        bfSpin()
        try #require(BlockReportRules.detailCounterText(store.reportDetailDraft) == nil, "전제: 179자에서 카운터가 진다")
        #expect(bfTextViews(in: host).first === first, "카운터가 지는 순간 자세히 칸이 새로 만들어졌다")
        #expect(window.firstResponder === first, "카운터가 지는 순간 포커스를 잃었다")
        withExtendedLifetime(window) {}
    }

    @Test(.gomokuDefaultsCleanup)
    func 보내기_실패_안내가_서고_져도_자세히_칸은_같은_칸이다() throws {
        CheckTextEditor.resetPoolForTesting()
        defer { CheckTextEditor.resetPoolForTesting() }
        let (store, window, host) = try mountSheet("notice")
        let first = try #require(bfTextViews(in: host).first, "자세히 칸이 안 섰다")
        try #require(window.makeFirstResponder(first))

        // 보내기 실패 — 아래 안내 줄이 서서 본문 상한이 45pt 준다.
        store.reportNotice = BlockReportText.serverNotReady
        bfSpin()
        #expect(bfTextViews(in: host).first === first, "안내 줄이 서자 자세히 칸이 새 NSTextView 로 바뀌었다")
        #expect(window.firstResponder === first, "안내 줄이 서자 치던 칸이 포커스를 잃었다 — 고쳐 쓰려던 글에 키가 안 들어간다")

        store.reportNotice = nil
        bfSpin()
        #expect(bfTextViews(in: host).first === first, "안내 줄이 지자 자세히 칸이 새로 만들어졌다")
        #expect(window.firstResponder === first)
        withExtendedLifetime(window) {}
    }

    /// 실제 배선(팝오버 `CheckMenuView`) — 검증자가 잰 조합 그대로: 새 버전 배너 + 노트 두 줄(크롬 119pt, 본문 상한 209pt)에서
    /// 사람 신고 본문이 208 → 229pt 로 넘어가던 자리다.
    @Test(.gomokuDefaultsCleanup)
    func 팝오버_배선에서도_180자째에_자세히_칸이_바뀌지_않는다() throws {
        CheckTextEditor.resetPoolForTesting()
        defer { CheckTextEditor.resetPoolForTesting() }
        let (store, _) = bfStore("menu-counter")
        store.isMenuPresented = true
        store.displayNow = MessageReadFixture.now
        store.currentTeamID = URLProtocolStub.stubTeamID
        store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 3_600)
        store.pokeDirectory = [PokeDirectoryEntry(userID: bfPeerA, name: "소라", avatarURL: nil, isWorking: true)]
        store.pokeDirectoryLoaded = true
        store.messageHistoryLoaded = true
        store.openMessagePanel(peer: bfPeerA)
        store.openReport(BlockReportTarget(peerID: bfPeerA, peerName: "소라"), surface: .message)
        store.selectReportReason(.spam)
        store.reportDetailDraft = String(repeating: "가", count: 179)
        let (window, host) = bfMount(
            CheckMenuView(store: store, previewUpdateBanner: true,
                          previewUpdateNotes: ["합성 노트 한 줄", "합성 노트 두 줄"]),
            width: 414, height: 700
        )
        let editors = bfTextViews(in: host).filter { $0.poolSlot?.id.hasPrefix("check/CheckMessageView.swift:") == true }
        let first = try #require(editors.first, "팝오버 신고 시트의 자세히 칸이 안 섰다")
        try #require(editors.count == 1)
        try #require(window.makeFirstResponder(first))

        first.insertText("나", replacementRange: NSRange(location: NSNotFound, length: 0))
        bfSpin()
        try #require(BlockReportRules.detailCounterText(store.reportDetailDraft) != nil, "전제: 180자에서 카운터가 선다")
        let after = bfTextViews(in: host).filter { $0.poolSlot?.id.hasPrefix("check/CheckMessageView.swift:") == true }
        #expect(after.count == 1 && after.first === first, "팝오버에서 카운터가 서는 순간 자세히 칸이 새 NSTextView 로 바뀌었다")
        #expect(window.firstResponder === first, "팝오버에서 카운터가 서는 순간 치던 칸이 포커스를 잃었다")
        withExtendedLifetime(window) {}
    }

    /// 갈래를 하나로 묶어도 **높이 규칙은 그대로**여야 한다: 본문이 상한 안이면 자연 높이(빈 자리 없음),
    /// 넘치면 대화 패널 예산(고정 크롬 178 + 대화 높이) 그대로에서 스크롤. 예산을 넘으면 팝오버 700pt 상한이 깨진다.
    @Test(.gomokuDefaultsCleanup)
    func 한_갈래로_묶여도_시트_높이는_자연_높이이거나_예산_그대로다() throws {
        for (extra, draft) in [(CGFloat(0), ""), (Self.extraChrome, String(repeating: "가", count: 179)),
                               (Self.extraChrome, String(repeating: "가", count: 185)), (CGFloat(170), "")] {
            let (store, _) = bfStore("height-\(Int(extra))-\(draft.count)")
            store.openMessagePanel(peer: bfPeerA)
            store.openReport(BlockReportTarget(peerID: bfPeerA, peerName: "소라"), surface: .message)
            store.selectReportReason(.spam)
            store.reportDetailDraft = draft
            let sheet = try #require(store.blockReportSheet(on: .message))
            let capped = NSHostingView(rootView: CheckMessageView(store: store, extraChromeHeight: extra, onBack: {})
                .frame(width: MessagePanelLayout.contentWidth + 24))
            // 같은 시트를 상한 없이(자연 높이) — 오목 덮개와 같은 차림이다.
            let natural = NSHostingView(rootView: BlockReportSheetView(store: store, sheet: sheet)
                .padding(12)
                .frame(width: MessagePanelLayout.contentWidth + 24))
            capped.layoutSubtreeIfNeeded()
            natural.layoutSubtreeIfNeeded()
            let budget = BlockReportSheetLayout.messagePanelFixedChrome
                + MessagePanelLayout.conversationHeight(extraChromeHeight: extra)
            let expected = min(natural.fittingSize.height, budget)
            #expect(abs(capped.fittingSize.height - expected) <= 1,
                    "크롬 \(extra) · \(draft.count)자: 시트 \(capped.fittingSize.height)pt — 자연 \(natural.fittingSize.height) · 예산 \(budget)")
        }
    }
}
