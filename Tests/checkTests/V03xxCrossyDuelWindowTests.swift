import AppKit
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// 1:1 길건너 **맥 창**(SPEC v1.3 §9.1 · §10.2 U 줄) — 창 수명 · 첫 클릭 · 자기 주사율 · 전용 키 모니터 · 실제 레이아웃.
//
// 없으면 초록으로 지나가는 결함(각 시험 첫 줄 주석에 하나씩). **창 시험은 로비 단계만** 실제 창에 올린다 — SCNView 를 실제 창에
// 올리면 화면이 잠든 기계에서 전체 스위트가 멈춘다(메모리 full-suite-freezes-when-display-asleep, v1.1 CC-26). 판 화면의 레이아웃은
// 창 없이 `NSHostingView` 로 재고, 3D 자리는 `previewCanvas` 그림으로 대신한다(SCNView 마운트 0).
// 창은 알파 0(`CheckPanelVisibility`) · 직렬이고, 띄운 창은 곧바로 화면 밖으로 옮긴다.

// MARK: - 헬퍼

private let cwRival = CrossyDuelUser(id: "00000000-0000-0000-0000-0000000000b2", displayName: "민수",
                                     characterID: "fox", isWorking: true)

@MainActor
private func cwController(_ store: CrossyDuelStore) -> CheckCrossyDuelWindowController {
    let controller = CheckCrossyDuelWindowController()
    controller.configure(store: store, content: { _ in AnyView(Color.clear) })
    return controller
}

private func cwMatch(finished: Bool = false) -> CrossyDuelMatchState {
    CrossyDuelMatchState(id: "c0de0000-0000-4000-8000-000000000067", stake: 5, seed: 7, opponent: cwRival,
                         meReady: true, opponentReady: true, opponentScore: 12, isFinished: finished,
                         outcome: finished ? .win : nil, endReason: finished ? .goal : nil)
}

/// 판이 도는 스토어(네트워크 없음) — 1:1 엔진을 열어(`begin`) 구동기에 세운다. 입력은 이 판에 곧바로 들어간다.
@MainActor
private func cwLiveStore(phase: CrossyDuelPhase = .playing) -> CrossyDuelStore {
    let store = CrossyDuelStore(uptime: { 100 })
    var game = CrossyGame(seed: 7, rules: .duel)
    game.begin()
    store.duel = CrossyDuelSession(seed: 7, startedGame: game, startAt: 90)
    store.match = cwMatch()
    store.phase = phase
    return store
}

/// 화면에 올리되 보이지 않게(알파 0 · 화면 밖) — `strokeBelongsToGame` 이 `isVisible` 을 요구한다.
@MainActor
private func cwWindow(identifier: String? = nil) -> NSWindow {
    let window = NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: 200, height: 80),
                          styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.alphaValue = 0
    if let identifier { window.identifier = NSUserInterfaceItemIdentifier(identifier) }
    window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 80))
    window.orderFrontRegardless()
    return window
}

@MainActor
private func cwMoveOffscreen(_ controller: CheckCrossyDuelWindowController) {
    controller.currentWindow?.setFrameOrigin(NSPoint(x: -6000, y: -6000))
}

/// 엔진이 입력을 받았는가(뛰기가 시작됐거나 줄 세워졌다).
@MainActor
private func cwHops(_ store: CrossyDuelStore) -> Int {
    guard let game = store.duel?.game else { return -1 }
    return game.hopCount + (game.queued == nil ? 0 : 1)
}

@MainActor
private final class CWBox {
    var frames: [CGRect] = []
    var closes: [Bool] = []
    var begins = 0
    var ends = 0
}

// MARK: - 시험

@MainActor
@Suite("1:1 길건너 — 맥 창(SPEC §9.1)", .serialized)
struct V03xxCrossyDuelWindowTests {

    @Test("창 정체 — 제목 · 자동저장 이름 · 660×504 고정 · 최소화 가능 · 크기 고정 · 비활성에도 남음 · 다크")
    func windowIdentity() {
        // 없으면: 자동저장 이름이 다른 창과 겹쳐 자리 저장이 죽거나, 크기가 바뀌어 판 배율이 흔들리거나, 다른 앱을 누르면 창이 사라진다.
        #expect(CheckCrossyDuelWindowController.windowTitle == "1:1 길건너")
        #expect(CheckCrossyDuelWindowController.frameAutosaveName == "check.crossy-duel.window")
        #expect(CheckCrossyDuelWindowController.fixedContentSize == NSSize(width: 660, height: 504))
        let window = CheckCrossyDuelWindowController.makeWindow()
        defer { window.close() }
        #expect(window.styleMask.contains(.miniaturizable))
        #expect(!window.styleMask.contains(.resizable), "크기가 바뀌면 판 배율이 창에 딸려 흔들린다")
        #expect(!window.isReleasedWhenClosed)
        #expect(!window.hidesOnDeactivate, "다른 앱을 누르면 창이 사라진다 — 판은 계속 흐르는데 안 보인다")
        #expect(window.appearance?.name == .darkAqua)
        #expect(window.alphaValue == CheckPanelVisibility.panelAlpha)
        #expect(window.identifier?.rawValue == CheckCrossyDuelWindowController.frameAutosaveName)
        #expect(CheckPanelVisibility.isRunningTests, "테스트 판정이 꺼져 있으면 이 스위트가 사용자 화면에 창을 띄운다")
    }

    @Test("자동저장 이름이 다른 창과 겹치지 않는다 — 실제로 열어 setFrameAutosaveName 이 참")
    func autosaveNameIsUnique() {
        // 없으면: 이름이 겹쳐 `setFrameAutosaveName` 이 false 를 돌려주고 자리 저장이 조용히 죽는다.
        let others = [CheckTetrisDuelWindowController.frameAutosaveName, CheckMahjongWindowController.frameAutosaveName,
                      CheckMiniGameWindowController.frameAutosaveName, CheckReversiWindowController.frameAutosaveName]
        #expect(!others.contains(CheckCrossyDuelWindowController.frameAutosaveName))
        let store = CrossyDuelStore()
        let controller = cwController(store)
        defer { controller.discardWindowForTesting() }
        controller.show()
        cwMoveOffscreen(controller)
        #expect(controller.frameAutosaveActive, "자동저장 이름이 다른 창과 겹친다")
    }

    @Test("지연 생성 · 멱등 show — 열기 전엔 창이 없고 두 번 열어도 한 창 · 열면 스토어가 '보임'")
    func lazyAndIdempotent() throws {
        // 없으면: 앱 시작에 창이 미리 만들어지거나(메모리·첫 프레임 낭비), 두 번 열 때 창이 둘이 되어 키 모니터가 엉뚱한 창을 본다.
        let store = CrossyDuelStore()
        let controller = cwController(store)
        defer { controller.discardWindowForTesting() }
        #expect(!controller.hasWindow, "열기 전에 창이 만들어졌다")
        controller.show()
        cwMoveOffscreen(controller)
        let first = try #require(controller.currentWindow)
        controller.show()
        cwMoveOffscreen(controller)
        #expect(controller.currentWindow === first, "두 번 열었더니 창이 갈렸다")
        #expect(controller.isOpen)
        #expect(store.isWindowVisible, "창을 열었는데 스토어가 '보임'을 안 받았다 — 준비 보고의 문이 안 열린다")
        #expect(CrossyDuelKeys.isInstalled(for: controller), "창을 열었는데 이 창의 키 모니터가 안 걸렸다")
    }

    @Test("닫기와 최소화는 다른 통지 — 최소화 = 안 보임만 · 빨간 점 = onClosed(true) · close() = onClosed(false) · 키 상실 처리기 없음")
    func closeAndMiniaturizeAreSeparate() throws {
        // 없으면: 최소화가 '닫기'로 번져 결과 화면이 접히거나, 사람이 닫은 것과 로그아웃 닫기를 못 갈라 미니게임 창이 엉뚱하게 선다.
        #expect(!CheckCrossyDuelWindowController().responds(to: #selector(NSWindowDelegate.windowDidResignKey(_:))),
                "창이 키 상실에 반응한다 — 다른 앱을 잠깐 본 것이 판 중단이 된다")
        let store = cwLiveStore()
        let controller = cwController(store)
        let box = CWBox()
        controller.onClosed = { box.closes.append($0) }
        defer { controller.discardWindowForTesting() }
        controller.show()
        cwMoveOffscreen(controller)
        let window = try #require(controller.currentWindow)

        controller.windowDidMiniaturize(Notification(name: NSWindow.didMiniaturizeNotification, object: window))
        #expect(!store.isWindowVisible, "최소화가 '안 보임'을 안 알렸다")
        #expect(box.closes.isEmpty, "최소화가 '닫혔다'를 알렸다")
        #expect(store.duel != nil && store.phase == .playing, "최소화했더니 판이 바뀌었다")
        controller.windowDidDeminiaturize(Notification(name: NSWindow.didDeminiaturizeNotification, object: window))
        #expect(store.isWindowVisible)

        controller.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: window))
        #expect(box.closes == [true], "빨간 점이 '사람이 닫음'으로 안 갔다: \(box.closes)")
        #expect(!controller.isOpen && !store.isWindowVisible)
        #expect(store.duel != nil && store.phase == .playing, "창을 닫았더니 진행 중인 판이 바뀌었다 — 닫기는 기권이 아니다")

        controller.show()
        cwMoveOffscreen(controller)
        controller.close()
        #expect(box.closes == [true, false], "프로그램 닫기가 '사람이 닫음'과 갈리지 않는다: \(box.closes)")
    }

    @Test("가림은 '안 보임'이 아니다 — isWindowVisible 그대로 · 가림 기록만")
    func occlusionKeepsVisibility() {
        // 없으면: 가려진 창이 '안 보임'으로 번져 준비 보고·하트비트 문이 닫힌다(판은 흐르는데 보고가 멎는다).
        let store = CrossyDuelStore()
        let controller = cwController(store)
        defer { controller.discardWindowForTesting() }
        controller.show()
        cwMoveOffscreen(controller)
        controller.applyOcclusion(visible: false)
        #expect(store.isWindowVisible, "가려졌다고 '안 보임'까지 됐다")
        #expect(store.isWindowOccluded)
        #expect(controller.lastOcclusionNotice == false)
        controller.applyOcclusion(visible: true)
        #expect(!store.isWindowOccluded)
    }

    @Test("첫 클릭을 받는다 — contentView 가 acceptsFirstMouse 참(기준선: 보통 호스팅 뷰는 거짓)")
    func acceptsFirstMouse() throws {
        // 없으면: 다른 앱에서 온 첫 클릭이 '창 앞으로'에 먹혀 "클릭 = 앞으로" 가 빈다(CC-16).
        let store = CrossyDuelStore()
        let controller = CheckCrossyDuelWindowController()
        controller.configure(store: store)   // 실제 패널(로비 단계 — SCNView 없음)
        defer { controller.discardWindowForTesting() }
        controller.show()
        cwMoveOffscreen(controller)
        let content = try #require(controller.currentWindow?.contentView)
        #expect(content.acceptsFirstMouse(for: nil), "대결 창 첫 클릭이 창 앞으로에 먹힌다")
        let plain = NSHostingView(rootView: Color.clear)
        #expect(!plain.acceptsFirstMouse(for: nil), "전제: 보통 호스팅 뷰는 첫 클릭을 안 받는다 — 이게 참이면 위 단언이 아무것도 안 잰다")
    }

    @Test("자기 주사율 — setForTesting(75) 면 간격 1/75 · fps 75(기준선 60) · show() 가 갱신 · 공용 모니터와 다른 인스턴스")
    func ownFrameRateMonitor() throws {
        // 없으면: 미니게임 창을 안 연 세션에서 폴백 60 으로 돌아 75·144Hz 화면에서 규칙적 저더가 난다(CC-5).
        let controller = CheckCrossyDuelWindowController()
        #expect(controller.frameRateMonitor !== MiniGameFrameRateMonitor.shared, "공용 모니터를 쓰면 다른 화면의 미니게임 창과 서로 덮는다")
        controller.frameRateMonitor.setForTesting(75)
        let at75 = CrossyDuelCanvasLeaf.timing(controller.frameRateMonitor)
        #expect(at75.fps == 75)
        #expect(at75.interval == MiniGameFrameRate.minimumInterval(forRefreshRate: 75))
        let baseline = CrossyDuelCanvasLeaf.timing(MiniGameFrameRateMonitor())
        #expect(baseline.fps == 60 && baseline.interval != at75.interval, "기준선 60 과 갈리지 않는다")
        // 창 루트가 이 모니터를 받는다(창 파일의 `.frameRate(monitor)`).
        let panel = CrossyDuelPanel(store: CrossyDuelStore()).frameRate(controller.frameRateMonitor)
        #expect(panel.frameRateMonitor === controller.frameRateMonitor)
        // show() 가 그 창의 화면에서 다시 읽는다 — 틀린 값(1)을 세워 두고 갱신이 일어났는지 본다.
        controller.configure(store: CrossyDuelStore(), content: { _ in AnyView(Color.clear) })
        defer { controller.discardWindowForTesting() }
        controller.frameRateMonitor.setForTesting(1)
        controller.show()
        cwMoveOffscreen(controller)
        #expect(controller.frameRateMonitor.refreshHz != 1, "show() 가 주사율을 다시 읽지 않았다")
    }

    @Test("실제 호스팅 레이아웃에서 캔버스 프레임 344×356 — 레이아웃 상수 자리와 같다(판 화면 · SCNView 없음)")
    func canvasFrameInHostingLayout() async throws {
        // 없으면: 상수끼리 더한 항등식은 초록인데 실제 배치에서 캔버스가 눌리거나 밀려 솔로와 다른 배율의 판을 친다(CC-25).
        let store = cwLiveStore()
        let box = CWBox()
        let image = try #require(CGContext(data: nil, width: 688, height: 712, bitsPerComponent: 8, bytesPerRow: 0,
                                           space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?.makeImage())
        let panel = CrossyDuelPanel(store: store, previewCanvas: image, onCanvasFrame: { box.frames.append($0) })
        let hosting = NSHostingView(rootView: panel)
        hosting.frame = NSRect(origin: .zero, size: CheckCrossyDuelWindowController.fixedContentSize)
        for _ in 0..<40 where box.frames.isEmpty {
            hosting.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(25))
        }
        let frame = try #require(box.frames.last, "캔버스 자리가 한 번도 안 왔다")
        #expect(frame.size == CGSize(width: 344, height: 356), "캔버스가 \(frame.size) 로 놓였다")
        #expect(frame.size == MiniGameWindowLayout.canvasSize, "솔로 캔버스와 크기가 다르다")
        #expect(abs(frame.minX - CrossyDuelWindowLayout.canvasRect.minX) < 0.5
                && abs(frame.minY - CrossyDuelWindowLayout.canvasRect.minY) < 0.5,
                "캔버스가 \(frame.origin) 에 놓였다 — 상수 자리 \(CrossyDuelWindowLayout.canvasRect.origin)")
    }

    @Test("SCNView 는 카운트다운·판·결과에서만 마운트 — 로비·준비는 안 올린다")
    func sceneMountsOnlyInMatchPhases() {
        // 없으면: 로비 창(창 시험이 실제로 띄우는 단계)에 SCNView 가 올라가 화면이 잠든 기계에서 스위트가 멈춘다(CC-26).
        #expect(!CrossyDuelCanvasLeaf.mountsScene(.lobby))
        #expect(!CrossyDuelCanvasLeaf.mountsScene(.ready))
        #expect(CrossyDuelCanvasLeaf.mountsScene(.countdown))
        #expect(CrossyDuelCanvasLeaf.mountsScene(.playing))
        #expect(CrossyDuelCanvasLeaf.mountsScene(.finished))
    }

    // MARK: 키

    @Test("키: 이 창의 스페이스 → 앞으로 한 칸 · 키 반복 → 0(삼킴) · 남의 창 → 안 삼킴 · 로비 → 안 삼킴")
    func spaceIsForwardRepeatIsSwallowed() {
        // 없으면: 스페이스가 초점 단추 [기권] 을 누르거나(삼키지 않음), 꾹 누르기가 자동 질주가 되거나(반복을 입력으로),
        //        다른 창(미니게임·팝오버)에서 누른 키가 루비가 걸린 판을 움직인다(CC-8).
        CrossyDuelKeys.remove()
        defer { CrossyDuelKeys.remove() }
        let duel = cwWindow(identifier: CheckCrossyDuelWindowController.frameAutosaveName)
        let other = cwWindow(identifier: CheckMiniGameWindowController.frameAutosaveName)
        defer { [duel, other].forEach { $0.orderOut(nil) } }

        let pressed = cwLiveStore()
        let before = cwHops(pressed)
        #expect(CrossyDuelKeys.handleForTesting(keyCode: 49, isUp: false, eventWindow: duel, duelWindow: duel, store: pressed))
        #expect(cwHops(pressed) == before + 1, "스페이스가 앞으로 한 칸을 안 했다(\(before) → \(cwHops(pressed)))")
        #expect(pressed.duel?.game.player.facing == .forward)

        let repeated = cwLiveStore()
        let repeatBefore = cwHops(repeated)
        #expect(CrossyDuelKeys.handleForTesting(keyCode: 49, isUp: false, isRepeat: true, eventWindow: duel, duelWindow: duel,
                                                store: repeated), "키 반복을 안 삼켰다 — 초점 단추로 샌다")
        #expect(cwHops(repeated) == repeatBefore, "키 반복이 입력이 됐다 — 꾹 누르기 = 자동 질주")

        let foreign = cwLiveStore()
        let foreignBefore = cwHops(foreign)
        #expect(!CrossyDuelKeys.handleForTesting(keyCode: 49, isUp: false, eventWindow: other, duelWindow: duel, store: foreign),
                "남의 창 스페이스를 삼켰다")
        #expect(cwHops(foreign) == foreignBefore, "남의 창 스페이스가 판을 움직였다")

        let lobby = CrossyDuelStore()
        #expect(!CrossyDuelKeys.handleForTesting(keyCode: 49, isUp: false, eventWindow: duel, duelWindow: duel, store: lobby),
                "로비에서 스페이스를 삼켰다 — 초점 단추를 못 누른다")
    }

    @Test("키: 방향키·WASD 는 뛰기 표 그대로 · 카운트다운엔 삼키되 판은 안 움직임 · ⌘ 조합은 흘림 · 뗌은 이 창 것만 삼킴")
    func arrowsAndCountdown() {
        // 없으면: ← 가 오른쪽으로 뛰거나(표 어긋남), 카운트다운 스페이스가 초점 단추를 누르거나, ⌘W 같은 단축키를 판이 먹는다.
        let duel = cwWindow(identifier: CheckCrossyDuelWindowController.frameAutosaveName)
        defer { duel.orderOut(nil) }
        for (code, direction) in [(UInt16(123), CrossyGame.Direction.left), (124, .right), (125, .back), (126, .forward),
                                  (0, .left), (2, .right), (1, .back), (13, .forward)] {
            #expect(CrossyDuelKeyRule.handle(keyCode: code, isUp: false, isRepeat: false, hasModifier: false,
                                             belongs: true, live: true).command == .hop(direction), "keyCode \(code)")
        }
        let left = cwLiveStore()
        #expect(CrossyDuelKeys.handleForTesting(keyCode: 123, isUp: false, eventWindow: duel, duelWindow: duel, store: left))
        #expect(left.duel?.game.player.facing == .left, "← 가 판에 안 닿았다")

        let counting = cwLiveStore(phase: .countdown)
        let before = cwHops(counting)
        #expect(CrossyDuelKeys.handleForTesting(keyCode: 49, isUp: false, eventWindow: duel, duelWindow: duel, store: counting),
                "카운트다운 스페이스를 안 삼켰다 — 초점 단추로 샌다")
        #expect(cwHops(counting) == before, "카운트다운에 판이 움직였다")

        #expect(!CrossyDuelKeyRule.handle(keyCode: 13, isUp: false, isRepeat: false, hasModifier: true,
                                          belongs: true, live: true).consumed, "⌘W 를 판이 먹었다")
        let up = CrossyDuelKeyRule.handle(keyCode: 49, isUp: true, isRepeat: false, hasModifier: false, belongs: true, live: true)
        #expect(up.consumed && up.command == nil, "이 창의 뗌은 삼키기만")
        let foreignUp = CrossyDuelKeyRule.handle(keyCode: 49, isUp: true, isRepeat: false, hasModifier: false,
                                                 belongs: false, live: true)
        #expect(!foreignUp.consumed, "남의 창 뗌을 삼켰다")
        #expect(CrossyDuelKeyRule.handle(keyCode: 36, isUp: false, isRepeat: false, hasModifier: false,
                                         belongs: true, live: true).consumed == false, "↩ 같은 다른 키를 삼켰다")
    }

    // MARK: 붙들기 · 문구

    @Test("App Nap 붙들기 — 같은 값 두 번이면 활동 하나 · 놓으면 끝")
    func activityHoldIsIdempotent() {
        // 없으면: 신호가 두 번 오면 활동이 둘 쥐어져 판이 끝나도 하나가 남아 App Nap 이 영영 안 걸린다.
        let box = CWBox()
        let hold = CrossyDuelActivityHold(begin: { _ in box.begins += 1; return NSObject() }, end: { _ in box.ends += 1 })
        hold.set(true)
        hold.set(true)
        #expect(box.begins == 1 && hold.isHolding)
        hold.set(false)
        hold.set(false)
        #expect(box.ends == 1 && !hold.isHolding)
    }

    @Test("창 밖 문구 — 말풍선 3단 접기 · 사이드바 도움말 · 메뉴바 점 · 게임 이름 한 곳")
    func outsideCopy() {
        // 없으면: 긴 이름에서 말풍선이 잘려 판돈이 안 보이거나, 게임 이름이 두 벌로 적혀 갈린다.
        #expect(CrossyDuelText.gameName == CrossyDuelNoticeText.gameName)
        #expect(MiniGameCrossyDuelEntryButton.title == "1:1 길건너")
        #expect(MiniGameCrossyDuelEntryButton.help == "100점에 먼저 닿으면 이기는 1:1 길건너 대결 창을 열어요")
        #expect(CrossyDuelText.dotReason == "1:1 길건너 신청")
        let short = CrossyDuelText.inviteBubbleText(name: "민수", stake: 5)
        #expect(OverlayMessageBubble.fitsCapsule(short) && short.hasPrefix("민수님") && short.hasSuffix("루비 5"), "\(short)")
        let long = CrossyDuelText.inviteBubbleText(name: "가장긴별명열두글자입니다가장긴별명", stake: 10)
        #expect(OverlayMessageBubble.fitsCapsule(long), "긴 이름 말풍선이 캡슐을 넘친다: \(long)")
        #expect(long.hasSuffix("루비 10"), "접어도 판돈은 남아야 한다: \(long)")
        let nameless = CrossyDuelText.inviteBubbleText(name: "  ", stake: 3)
        #expect(nameless.hasPrefix("누군가님") && OverlayMessageBubble.fitsCapsule(nameless), "\(nameless)")
        #expect(!CrossyDuelEntryIcon.resolved.isEmpty)
    }
}
