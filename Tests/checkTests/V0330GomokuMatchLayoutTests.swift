import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// v0.3.30 오목 창 — 순수 규칙(판돈 고르기 · 기권 누름 방어 · 카드 말풍선), 판 시작 때 로비 안내 지우기,
// 그리고 **실제 창에서 재현한 결함** 하나: 로비 [수락] 자리를 두 번 누르면 두 번째 누름이 대국 화면 [기권]에 떨어져
// 판에 들어오자마자 "기권하기 · 계속 두기"가 떠 있었다(2026-09-17 사용자 제보 · 같은 좌표 두 번 누름으로 재현).
//
// 그림(픽셀)으로 재는 시험은 `V0327GomokuPanelRenderTests` 의 v0.3.30 절에 있다.

// MARK: - 순수 규칙

@Test
func stakeSelectionTogglesAndSwitches() {
    #expect(GomokuStakeSelection.toggled(current: nil, tapped: .five) == .five, "미선택에서 누르면 고른다")
    #expect(GomokuStakeSelection.toggled(current: .five, tapped: .five) == nil, "고른 것을 한 번 더 누르면 해제된다")
    #expect(GomokuStakeSelection.toggled(current: .five, tapped: .ten) == .ten, "다른 판돈을 누르면 그것으로 바뀐다")
}

@MainActor
@Test
func resignGuardIgnoresTapsRightAfterTheScreenAppears() {
    let shown = Date(timeIntervalSince1970: 1_790_000_000)
    #expect(!GomokuResignGuard.acceptsTap(shownAt: shown, now: shown), "화면이 뜬 그 순간의 누름을 받았다")
    #expect(!GomokuResignGuard.acceptsTap(shownAt: shown, now: shown.addingTimeInterval(0.5)),
            "더블클릭 간격(0.5초) 안의 누름을 받았다 — 로비 [수락]의 두 번째 누름이 기권 확인을 연다")
    #expect(GomokuResignGuard.acceptsTap(shownAt: shown, now: shown.addingTimeInterval(GomokuResignGuard.armDelay)))
    #expect(GomokuResignGuard.acceptsTap(shownAt: shown, now: shown.addingTimeInterval(30)))
    #expect(GomokuResignGuard.acceptsTap(shownAt: nil, now: shown), "기준 시각을 모르면 버튼이 영영 죽는다")
    #expect(GomokuResignGuard.armDelay >= 0.5 && GomokuResignGuard.armDelay <= 1.5,
            "방어 시간이 더블클릭 간격을 못 덮거나 사람이 느낄 만큼 길다")
    #expect(GomokuResignGuard.confirmTimeout >= 4, "확인이 너무 빨리 접혀 누르기 전에 사라진다")
}

@Test
func speechBubbleShowsTheLatestLineForFiveSeconds() {
    let t0 = Date(timeIntervalSince1970: 1_790_000_000)
    #expect(GomokuSpeechBubbleRule.remaining(sentAt: t0, now: t0) == 5)
    #expect(GomokuSpeechBubbleRule.remaining(sentAt: t0, now: t0.addingTimeInterval(4.5)) == 0.5)
    #expect(GomokuSpeechBubbleRule.remaining(sentAt: t0, now: t0.addingTimeInterval(5)) <= 0, "5초가 지났는데 남아 있다")
    #expect(GomokuSpeechBubbleRule.remaining(sentAt: t0, now: t0.addingTimeInterval(3_600)) <= 0,
            "창을 한참 뒤에 열었는데 옛 말이 말풍선으로 튀어나온다")
    // 기기 시계 보정 오차로 보낸 시각이 "지금"보다 뒤여도 5초를 넘겨 떠 있지 않는다.
    #expect(GomokuSpeechBubbleRule.remaining(sentAt: t0.addingTimeInterval(2), now: t0) == 5)

    let chat = [
        GomokuChatMessage(seq: 1, isMine: false, sentAt: t0, quick: nil, body: "상대 첫 말"),
        GomokuChatMessage(seq: 2, isMine: true, sentAt: t0, quick: nil, body: "내 말"),
        GomokuChatMessage(seq: 3, isMine: false, sentAt: t0, quick: .gg, body: GomokuQuickPhrase.gg.text)
    ]
    #expect(GomokuSpeechBubbleRule.latest(in: chat, mine: false, isMuted: false)?.seq == 3, "상대의 **가장 최근** 말이 아니다")
    #expect(GomokuSpeechBubbleRule.latest(in: chat, mine: true, isMuted: false)?.seq == 2)
    #expect(GomokuSpeechBubbleRule.latest(in: chat, mine: false, isMuted: true) == nil, "채팅을 껐는데 상대 말이 카드로 샌다")
    #expect(GomokuSpeechBubbleRule.latest(in: chat, mine: true, isMuted: true)?.seq == 2, "채팅을 껐다고 내 말풍선까지 사라졌다")
    #expect(GomokuSpeechBubbleRule.latest(in: [], mine: true, isMuted: false) == nil)
}

// MARK: - 판이 시작되면 로비 안내가 대국 상태줄에 남지 않는다

@MainActor
private func lmStatePayload(id: String, finished: Bool = false) throws -> GomokuStatePayload {
    let me = "00000000-0000-0000-0000-0000000000a1"
    let rival = "00000000-0000-0000-0000-0000000000b2"
    let object: [String: Any] = [
        "status": "ok",
        "match": [
            "id": id, "status": finished ? "finished" : "active", "stake": 5, "black": me, "white": rival,
            "challenger": me, "opponent": rival, "move_count": 0, "turn": finished ? NSNull() : "black",
            "deadline_ms": NSNull(), "result": finished ? "white_win" : NSNull(),
            "end_reason": finished ? "resign" : NSNull(), "winner": NSNull(), "invite_expires_ms": NSNull()
        ] as [String: Any],
        "moves": [] as [Any],
        "my_color": "black",
        "opponent": ["user_id": rival, "display_name": "라이벌", "avatar_url": NSNull(), "character": "aing"] as [String: Any],
        "ruby_balance": NSNull(),
        "server_now_ms": NSNull()
    ]
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(GomokuStatePayload.self, from: JSONSerialization.data(withJSONObject: object))
}

/// 2026-09-17 스크린샷: 대국 상태줄에 로비 안내 "신청을 보냈어요"가 남아 "내 차례예요"를 가렸다.
@MainActor
@Test
func aNewMatchClearsTheLobbyNoticeButKeepsInMatchNotices() throws {
    let store = GomokuStore()
    store.notice = "신청을 보냈어요"
    store.applyState(try lmStatePayload(id: "11111111-2222-3333-4444-555555555555"))
    #expect(store.phase == .playing)
    #expect(store.notice == nil, "판이 열렸는데 로비 안내('\(store.notice ?? "")')가 대국 상태줄에 남았다")

    // 같은 판의 다음 상태(새 수 · 되맞춤)는 판 안에서 뜬 안내를 지우지 않는다.
    store.notice = "상대 차례예요"
    store.applyState(try lmStatePayload(id: "11111111-2222-3333-4444-555555555555"))
    #expect(store.notice == "상대 차례예요", "같은 판의 상태를 받을 때마다 판 안 안내가 지워진다")

    // 다른 판이 열리면 다시 지운다.
    store.notice = "신청을 보냈어요"
    store.applyState(try lmStatePayload(id: "99999999-2222-3333-4444-555555555555"))
    #expect(store.notice == nil)
}

// MARK: - 실제 창: 로비 [수락] 두 번 누름이 [기권]에 떨어지지 않는다

/// 창이 그림·배치를 따라잡을 틈을 준다. **중첩 런루프를 돌리지 않는다** — 처음엔 메인 스레드에서 `RunLoop.run` 을
/// 돌렸는데, 그 판으로 오목 묶음 전체를 돌린 네 번 모두 병렬로 도는 스토어 시험 `늦게_온_기권_응답도…`(늦게 온 응답
/// 순서를 잰다)가 빨개졌고, 잠들어 양보하게 바꾼 뒤로는 초록이었다(2026-09-17 실측). 대기는 재개 횟수 기반이다.
@MainActor
private func lmSettle(until condition: () -> Bool = { false }, turns: Int = 40) async {
    for _ in 0..<turns {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(10))
    }
}

@MainActor
private func lmClick(_ window: NSWindow, x: CGFloat, yFromTop: CGFloat, clickCount: Int) {
    let height = window.contentView?.bounds.height ?? GomokuWindowLayout.contentSize.height
    let location = NSPoint(x: x, y: height - yFromTop)
    for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
        if let event = NSEvent.mouseEvent(
            with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: clickCount,
            pressure: type == .leftMouseDown ? 1 : 0
        ) {
            window.sendEvent(event)
        }
    }
}

/// **창 수명 스위트(`GomokuWindowLifecycleTests`, 직렬)에 붙인다.** 따로 된 스위트로 두면 그 스위트와 동시에 창을 만들어
/// 같은 자동저장 이름(`check.gomoku.window`)을 먼저 쥐고, 저쪽 `frameAutosaveActive` 단언이 빨개졌다(2026-09-17 실측).
extension GomokuWindowLifecycleTests {
    /// 재현(수정 전 코드에서 확인): 받은 신청 카드 [수락]은 창 위 기준 y 628~652, 대국 화면 [기권]은 y 646~680 이다.
    /// 두 버튼이 겹치는 (900, 650) 을 로비에서 한 번, 판이 열린 뒤 곧바로 한 번(더블클릭의 두 번째) 누르면
    /// 옛 코드는 기권 확인을 열었다. 이제 그 누름은 무시되고, 화면을 본 뒤(1초 뒤) 누른 [기권]만 확인을 연다.
    @Test
    func theSecondClickOfAnAcceptDoubleClickDoesNotOpenTheResignConfirm() async throws {
        let opponent = GomokuUser(
            id: "00000000-0000-0000-0000-00000000000a", displayName: "민수", avatarURL: nil,
            characterID: "fox", isWorking: true, isCapable: true, inMatch: false
        )
        let store = GomokuStore()
        store.users = [opponent]
        store.rubyBalance = 50
        store.incoming = [GomokuInvite(id: "invite-1", peer: opponent, stake: 5, expiresAt: Date().addingTimeInterval(50))]
        let controller = CheckGomokuWindowController()
        controller.configure(store: store)
        final class Clock { var now = Date(timeIntervalSince1970: 1_790_000_000) }
        let clock = Clock()
        GomokuResignGuard.clock = { clock.now }
        GomokuResignGuard.confirmOpensForTesting = 0
        defer {
            GomokuResignGuard.clock = { Date() }
            controller.discardWindowForTesting()
        }
        controller.show()
        let window = try #require(controller.currentWindow)
        await lmSettle(turns: 15)

        // 로비: [수락] 아래쪽 가장자리를 누른다(첫 번째 누름 — 서버 없는 가게라 수락은 조용히 끝난다).
        let spot = (x: CGFloat(900), y: CGFloat(650))
        lmClick(window, x: spot.x, yFromTop: spot.y, clickCount: 1)
        await lmSettle(turns: 3)

        // 그 사이 판이 열린다.
        store.incoming = []
        store.match = GomokuMatchState(
            id: "match-stray", stake: 5, myColor: .black, opponent: opponent, board: GomokuBoard(),
            lastMove: nil, moveCount: 0, turn: .black, deadline: Date().addingTimeInterval(25),
            isFinished: false, outcome: nil, endReason: nil, rubyDelta: nil, blackPassed: false
        )
        store.phase = .playing
        await lmSettle(turns: 15)

        // 더블클릭의 두 번째 누름 — 같은 자리, 이제는 [기권] 위다.
        lmClick(window, x: spot.x, yFromTop: spot.y, clickCount: 2)
        await lmSettle(turns: 10)
        #expect(GomokuResignGuard.confirmOpensForTesting == 0,
                "판이 열린 직후의 누름(로비 [수락]의 두 번째 누름)이 기권 확인을 열었다")

        // 대조군: 화면을 보고 1초 뒤에 누른 [기권]은 확인을 연다 — 이게 안 되면 위 단언은 아무것도 안 잰다.
        clock.now = clock.now.addingTimeInterval(GomokuResignGuard.armDelay + 0.1)
        lmClick(window, x: spot.x, yFromTop: spot.y, clickCount: 1)
        await lmSettle(until: { GomokuResignGuard.confirmOpensForTesting > 0 }, turns: 20)
        #expect(GomokuResignGuard.confirmOpensForTesting == 1,
                "화면을 보고 누른 [기권]이 확인을 안 연다 — 창 하네스가 버튼에 닿지 않는다(위 단언이 무의미하다)")
    }
}
