import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// v0.3.34 수리 — 맥 차단·신고 시트가 **연 자리를 떠나도 남던** 두 결함(적대적 검토 2026-09-20, medium 둘).
//
// ① 입력칸 자리 다툼: 신고 시트의 자세히 칸은 제보 패널과 **같은 부품**(`FeedbackBodyEditor`)이고, 그 부품 안의
//    `CheckTextEditor(...)` 호출 자리가 하나라 재사용 자리(`CheckEditorSlot`)도 하나였다. 오목 창은 닫아도 `orderOut` 뿐이라
//    그 창의 신고 칸이 제보 칸의 NSTextView 를 쥔 채 남고, 팝오버 [제보]가 다시 서면 칸이 **새로 만들어진다** —
//    새 NSTextView 는 한글 입력기 세션을 못 받아 자모가 하나씩 박힌다(v0.3.0~v0.3.12 결함, V0328 이 막았던 그 자리 다툼).
// ② 떠난 시트가 다음 화면을 덮는다: 팝오버 대화에서 연 시트는 [뒤로]·레일로 떠나도 남아 있다가 **다른 사람의 대화 자리에**
//    섰고("A 님을 차단할까요?"가 B 와의 대화를 가린다), 오목 창의 시트는 창을 닫거나 판이 바뀌어도 남아 **다음 판을 덮었다.**
//
// ★ 헤드리스 한계: 실제 입력기는 이 프로세스에서 안 돈다. ①은 "새로 만들어진 NSTextView 는 조합을 못 받는다"는 저장소의
//   실측(`CheckTextEditor.makeNSView` 주석)을 전제로, **같은 NSTextView 를 돌려받는가**를 잰다(V0328 과 같은 눈금).
// ★ 픽스처 본문은 전부 합성 문자열이다(퍼블릭 저장소).

private let blPeerA = MessageReadFixture.peerA
private let blPeerB = MessageReadFixture.peerB

@MainActor
private func blStore(
    _ label: String,
    handler: @escaping MessageReadStubProtocol.Handler = { _, _ in nil }
) -> (store: WorkTimerStore, host: String) {
    makeMessageReadStore("bl-\(label)") { call, index in
        if let reply = handler(call, index) { return reply }
        if call.rpc == "app_user_directory" {
            return MessageReadStubProtocol.Reply(body: MessageReadFixture.json([
                ["user_id": blPeerA, "display_name": "소라", "avatar_url": NSNull(), "is_working": true],
                ["user_id": blPeerB, "display_name": "도윤", "avatar_url": NSNull(), "is_working": false],
            ]))
        }
        return nil
    }
}

private func blUser(_ id: String, _ name: String) -> GomokuUser {
    GomokuUser(id: id, displayName: name, avatarURL: nil, characterID: nil, isWorking: true, isCapable: true, inMatch: true)
}

private func blMatch(id: String, opponent: GomokuUser) -> GomokuMatchState {
    GomokuMatchState(
        id: id, stake: 3, myColor: .black, opponent: opponent, board: GomokuBoard(),
        lastMove: nil, moveCount: 0, turn: .black, deadline: nil, isFinished: false, outcome: nil,
        endReason: nil, rubyDelta: nil, blackPassed: false
    )
}

private let blMatchOne = "11111111-2222-3333-4444-555555555501"
private let blMatchTwo = "11111111-2222-3333-4444-555555555502"

// MARK: - 마운트 헬퍼 (V0328 과 같은 수법 — 칸마다 자기 창)

@MainActor
@Observable
private final class BLShown {
    var shown = true
}

/// 팝오버 [제보] 패널의 본문 칸을 **제품 배선 그대로** 올린다(호출부는 `CheckFeedbackView.swift` 의 그 자리).
private struct BLFeedbackPanel: View {
    let store: WorkTimerStore
    @Bindable var flag: BLShown

    var body: some View {
        if flag.shown {
            FeedbackSendView(store: store)
        }
    }
}

@MainActor
private func blSpin(_ seconds: Double = 0.05) {
    RunLoop.current.run(until: Date().addingTimeInterval(seconds))
}

@MainActor
private func blSpin(until condition: () -> Bool) {
    var remaining = 100
    while !condition(), remaining > 0 {
        blSpin(0.01)
        remaining -= 1
    }
}

@MainActor
private func blTextViews(in root: NSView) -> [CheckEditorTextView] {
    var found: [CheckEditorTextView] = []
    if let match = root as? CheckEditorTextView { found.append(match) }
    for child in root.subviews { found += blTextViews(in: child) }
    return found
}

/// 칸을 **자기 창에** 세운다(화면에 올리지는 않는다 — 올리지 않아도 SwiftUI 는 마운트·반납을 한다, V0328 실측).
@MainActor
private func blMount<V: View>(_ view: V, width: CGFloat, height: CGFloat) -> (NSWindow, NSHostingView<some View>) {
    let host = NSHostingView(rootView: view.frame(width: width, height: height))
    host.frame = NSRect(x: 0, y: 0, width: width, height: height)
    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    blSpin()
    return (window, host)
}

// MARK: - ① 신고 칸과 제보 칸은 입력칸 자리를 나눠 쓰지 않는다

@MainActor
@Suite(.serialized) struct V0334BlockReportEditorSlotTests {
    @Test(.gomokuDefaultsCleanup)
    func 오목_창의_신고_칸은_제보_칸의_NSTextView_를_빼앗지_않는다() throws {
        CheckTextEditor.resetPoolForTesting()
        defer { CheckTextEditor.resetPoolForTesting() }
        let (store, _) = blStore("slot")

        // 팝오버 [제보]를 한 번 열었다 닫는다 — 그 칸이 제 자리로 반납된다.
        let flag = BLShown()
        let (feedbackWindow, feedbackHost) = blMount(
            BLFeedbackPanel(store: store, flag: flag), width: FeedbackPanelLayout.contentWidth, height: 420
        )
        let feedback1 = try #require(blTextViews(in: feedbackHost).first, "제보 칸이 안 올라왔다")
        flag.shown = false
        blSpin(until: { blTextViews(in: feedbackHost).isEmpty })
        try #require(blTextViews(in: feedbackHost).isEmpty, "제보 칸이 안 내려갔다 — 반납 경로를 안 지났다")

        // 오목 창 채팅 ··· → [신고하기]. 오목 창은 닫아도 `orderOut` 뿐이라 이 칸은 살아 남는다.
        store.gomoku.phase = .playing
        store.gomoku.match = blMatch(id: blMatchOne, opponent: blUser(blPeerA, "소라"))
        store.openReport(try #require(GomokuChatSafetyRule.target(for: store.gomoku)), surface: .gomoku)
        let face = GomokuPlayerFace(name: "영식", avatarURL: nil, characterID: "shiba")
        let (gomokuWindow, gomokuHost) = blMount(
            GomokuPanel(store: store.gomoku, me: { face }, safety: store),
            width: GomokuWindowLayout.contentSize.width, height: GomokuWindowLayout.contentSize.height
        )
        let gomokuEditors = blTextViews(in: gomokuHost)
        // 전제: 채팅 칸 + 신고 칸 둘이 섰다(신고 칸이 안 섰으면 아래 단언은 늘 참이다).
        try #require(gomokuEditors.count >= 2, "오목 창에 채팅 칸과 신고 칸이 함께 안 섰다: \(gomokuEditors.count)")
        #expect(!gomokuEditors.contains { $0 === feedback1 },
                "오목 창의 신고 칸이 제보 칸의 NSTextView 를 가져갔다 — 제보 칸이 새로 만들어진다")
        #expect(!gomokuEditors.contains { $0.poolSlot == feedback1.poolSlot },
                "신고 칸과 제보 칸이 같은 재사용 자리를 쓴다: \(feedback1.poolSlot?.description ?? "nil")")
        // 자리는 **부른 화면**에서 펼쳐진다 — 선언 자리(부품 파일)로 굳으면 팝오버 시트와 오목 덮개가 다시 한 자리를 나눠 쓴다.
        let gomokuSlots = gomokuEditors.compactMap { $0.poolSlot?.id }
        #expect(gomokuSlots.count == gomokuEditors.count && Set(gomokuSlots).count == gomokuSlots.count,
                "오목 창의 두 칸(채팅 · 신고)이 자리를 나눠 쓴다: \(gomokuSlots)")
        #expect(gomokuSlots.allSatisfy { $0.hasPrefix("check/GomokuPanel.swift:") },
                "오목 덮개의 신고 칸 자리가 부른 화면(GomokuPanel)이 아니라 부품 파일로 굳었다: \(gomokuSlots)")
        #expect(feedback1.poolSlot?.id.hasPrefix("check/CheckFeedbackView.swift:") == true,
                "제보 칸 자리가 제보 화면에서 안 펼쳐졌다: \(feedback1.poolSlot?.description ?? "nil")")

        // 팝오버 [제보]를 다시 연다 — **자기 칸을 돌려받아야 한다.**
        flag.shown = true
        blSpin(until: { !blTextViews(in: feedbackHost).isEmpty })
        let feedback2 = try #require(blTextViews(in: feedbackHost).first, "제보 칸이 다시 안 올라왔다")
        #expect(feedback2 === feedback1,
                "제보 칸이 새로 만들어졌다 — 새 NSTextView 는 한글 입력기 세션을 못 받아 자모가 하나씩 박힌다")
        withExtendedLifetime((feedbackWindow, gomokuWindow)) {}
    }

    /// 팝오버 대화 자리의 시트와 오목 창의 덮개는 **같은 뷰**(`BlockReportSheetView`)지만 호출 자리가 다르다 — 칸도 각자 제 자리다.
    /// (한 부품 안에서 `CheckTextEditor` 를 부르면 그 부품의 모든 사용처가 한 자리를 나눠 쓴다 — ①의 뿌리.)
    @Test func 자세히_칸의_자리는_부품이_아니라_부르는_화면이_정한다() throws {
        let feedback = try blSource("Sources/check/CheckFeedbackView.swift")
        let sheet = try blSource("Sources/check/CheckBlockReportViews.swift")
        // 부품은 받은 자리를 그대로 넘긴다(자기 줄로 굳히지 않는다). 값을 먼저 뽑는다 — 실패 메시지에 소스 전체가 쏟아지지 않게.
        let feedbackForwards = feedback.contains("file: editorFile, line: editorLine")
        let sheetForwards = sheet.contains("file: editorFile, line: editorLine")
        #expect(feedbackForwards, "FeedbackBodyEditor 가 부른 자리를 입력칸에 안 넘긴다 — 쓰는 화면 전부가 자리 하나를 나눠 쓴다")
        #expect(sheetForwards, "BlockReportSheetView 가 부른 자리를 자세히 칸에 안 넘긴다 — 팝오버와 오목 창이 자리를 나눠 쓴다")
        // 기본값은 **맨 매직 리터럴**이어야 부른 자리에서 펼쳐진다(보간·중첩 호출이면 선언 자리로 굳는다 — CheckEditorSlot 주석).
        let feedbackLiteral = feedback.contains("file: String = #fileID")
        let sheetLiteral = sheet.contains("file: String = #fileID")
        #expect(feedbackLiteral && sheetLiteral, "자리 기본값이 맨 매직 리터럴이 아니다")
    }
}

// MARK: - ② 떠난 시트는 다음 화면을 덮지 않는다

@MainActor
@Suite(.serialized) struct V0334BlockReportLeaveTests {
    @Test(.gomokuDefaultsCleanup)
    func 대화를_떠나면_시트가_걷히고_다른_사람의_대화를_덮지_않는다() {
        let (store, _) = blStore("leave-rail")
        store.openMessagePanel(peer: blPeerA)
        store.openReport(BlockReportTarget(peerID: blPeerA, peerName: "소라"), surface: .message)
        #expect(store.blockReportSheet(on: .message) != nil, "전제: 대화 자리에 신고 시트가 섰다")

        // 레일 [콕 / 메시지]로 떠난다(시트가 떠 있어도 레일은 눌린다).
        store.togglePokePanel()
        #expect(store.blockReportSheet(on: .message) == nil, "대화를 떠났는데 시트가 남았다")

        // 목록에서 B 를 고른다 — B 와의 대화가 서야 한다.
        store.openMessagePanel(peer: blPeerB)
        #expect(store.selectedMessagePeerID == blPeerB)
        #expect(store.blockReportSheet(on: .message) == nil, "B 와의 대화 자리에 A 에 대한 시트가 섰다")
    }

    @Test(.gomokuDefaultsCleanup)
    func 대화가_떠_있는_채로_다른_사람에게_가면_앞사람의_차단_확인이_걷힌다() {
        let (store, _) = blStore("leave-bubble")
        store.openMessagePanel(peer: blPeerA)
        store.openBlockConfirm(BlockReportTarget(peerID: blPeerA, peerName: "소라"), surface: .message)
        // 같은 사람의 말풍선을 다시 눌러도 쓰던 시트는 그대로다(같은 대화다 — 과잉 정리 대조).
        store.openMessagePanel(peer: blPeerA)
        #expect(store.blockReportSheet(on: .message)?.target.peerID == blPeerA, "같은 대화로 돌아왔는데 시트가 걷혔다")

        // 캐릭터 말풍선으로 B 와의 대화로 곧장 간다(패널을 닫지 않는 길).
        store.openMessagePanel(peer: blPeerB)
        #expect(store.blockReportSheet(on: .message) == nil, "B 와의 대화 자리에 'A 님을 차단할까요?' 가 섰다")
        // 확인을 지나지 않았으니 아무도 차단되지 않았다.
        #expect(store.blockHiddenPeerIDs.isEmpty)
    }

    @Test(.gomokuDefaultsCleanup)
    func 보내는_중에_떠나도_실패한_신고는_결과_한_줄로_남는다() async throws {
        let gate = MessageReadStubGate()
        let (store, host) = blStore("leave-inflight") { call, _ in
            call.rpc == "report_content"
                ? MessageReadStubProtocol.Reply(status: 500, body: #"{"message":"boom"}"#, gate: gate) : nil
        }
        store.openMessagePanel(peer: blPeerA)
        store.openReport(BlockReportTarget(peerID: blPeerA, peerName: "소라"), surface: .message)
        store.selectReportReason(.spam)
        store.reportDetailDraft = "합성 설명"
        let task = try #require(store.sendReportFromSheet())
        #expect(store.isSendingReport)

        // 보내는 중에 레일로 떠난다 — 시트는 걷히지만(다음 대화를 덮으면 안 된다) 결과는 어딘가에 서야 한다.
        store.togglePokePanel()
        #expect(store.blockReportSheet(on: .message) == nil, "떠났는데 시트가 남았다")

        gate.open()
        #expect(await task.value == false)
        #expect(MessageReadStubProtocol.count(host: host, rpc: "report_content") == 1)
        let notice = store.blockReportNotice(on: .message)
        #expect(notice?.isError == true,
                "떠난 사이 실패한 신고가 아무 데도 안 떴다 — 사용자는 접수된 줄 안다: \(notice?.text ?? "nil")")
        #expect(store.blockHiddenPeerIDs.isEmpty, "실패한 신고로 걷어냈다")
    }

    @Test(.gomokuDefaultsCleanup)
    func 오목_판이_바뀌면_앞_판의_시트가_다음_판을_덮지_않는다() throws {
        let (store, _) = blStore("gomoku-next")
        let opponent = blUser(blPeerA, "소라")
        store.gomoku.phase = .playing
        store.gomoku.match = blMatch(id: blMatchOne, opponent: opponent)
        store.openBlockConfirm(try #require(GomokuChatSafetyRule.target(for: store.gomoku)), surface: .gomoku)
        #expect(store.blockReportSheet(on: .gomoku) != nil, "전제: 오목 창에 시트가 섰다")

        // 같은 상대와 다음 판(다시 두기) — 새 판의 판을 앞 판의 시트가 덮으면 안 된다.
        store.gomoku.match = blMatch(id: blMatchTwo, opponent: opponent)
        #expect(store.blockReportSheet(on: .gomoku) == nil, "다음 판의 판을 앞 판의 시트가 덮었다")

        // 로비로 나가도(판 없음) 서지 않는다.
        store.openReport(try #require(GomokuChatSafetyRule.target(for: store.gomoku)), surface: .gomoku)
        #expect(store.blockReportSheet(on: .gomoku) != nil)
        store.gomoku.match = nil
        store.gomoku.phase = .lobby
        #expect(store.blockReportSheet(on: .gomoku) == nil, "로비를 앞 판의 신고 시트가 덮었다")
    }

    @Test(.gomokuDefaultsCleanup)
    func 오목_창을_닫으면_그_창에서_연_시트가_걷힌다() throws {
        let (store, _) = blStore("gomoku-close")
        store.gomoku.phase = .playing
        store.gomoku.match = blMatch(id: blMatchOne, opponent: blUser(blPeerA, "소라"))
        let controller = CheckGomokuWindowController()
        controller.configure(store: store.gomoku, me: { GomokuPlayerFace.fallback }, safety: store)
        defer { controller.discardWindowForTesting() }

        // 코드가 닫는 길(로그아웃 감시자 · reset 의 dismissWindow).
        store.openReport(try #require(GomokuChatSafetyRule.target(for: store.gomoku)), surface: .gomoku)
        controller.close()
        #expect(store.blockReportSheet(on: .gomoku) == nil, "창을 닫았는데 시트가 남았다 — 다음에 열면 판을 덮는다")

        // 사용자가 빨간 점을 누르는 길(AppKit 이 던지는 그 알림).
        controller.show()
        let window = try #require(controller.currentWindow)
        store.openBlockConfirm(try #require(GomokuChatSafetyRule.target(for: store.gomoku)), surface: .gomoku)
        controller.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: window))
        #expect(store.blockReportSheet(on: .gomoku) == nil, "빨간 점으로 닫았는데 시트가 남았다")
        #expect(store.blockHiddenPeerIDs.isEmpty, "확인을 지나지 않았는데 걷어냈다")

        // 팝오버에서 연 시트는 오목 창을 닫아도 그대로다(연 자리만 정리한다 — 과잉 정리 대조).
        store.openMessagePanel(peer: blPeerB)
        store.openReport(BlockReportTarget(peerID: blPeerB, peerName: "도윤"), surface: .message)
        controller.close()
        #expect(store.blockReportSheet(on: .message) != nil, "오목 창을 닫았더니 팝오버 대화의 시트가 걷혔다")
    }
}

// MARK: - 소스 읽기

private func blSource(_ relative: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    // 주석을 걷어 낸 코드만 읽는다 — 설명 속 같은 글자가 계약을 대신 채우지 못하게(v0331StripComments).
    return v0331StripComments(try String(contentsOf: root.appendingPathComponent(relative), encoding: .utf8))
}
