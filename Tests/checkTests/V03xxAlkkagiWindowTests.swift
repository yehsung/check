import AppKit
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// 1:1 알까기 **맥 창**(SPEC v1.1 §5.1 · §7.2 U 줄) — 제목 · 1240×700 · 첫 클릭 · 고착 감시 · 자동저장 · 닫기 ≠ 기권 ·
// 로비→판→로비 전환 뒤 '보임'(DF#46).
//
// 없으면 초록으로 지나가는 결함(각 시험 첫 줄 주석에 하나씩). 단언마다 결과가 갈리는 기준선 짝을 둔다.
// 창은 알파 0(`CheckPanelVisibility`) · 직렬이고, 띄운 창은 곧바로 화면 밖으로 옮긴다. 스토어에는 host 가 없어 네트워크 0 —
// 서버는 호출을 기록하는 스텁(`AWStub`)이다.

// MARK: - 시험대

private let awWall0 = Date(timeIntervalSince1970: 1_800_000_000)
private let awNowMs = awWall0.timeIntervalSince1970 * 1000
private let awMe = AlkkagiPeer(id: "00000000-0000-4000-8000-000000000013", displayName: "영식", characterID: "shiba")
private let awMinsu = AlkkagiPeer(id: "00000000-0000-4000-8000-000000000011", displayName: "민수", characterID: "fox")

@MainActor
private final class AWStub: AlkkagiServing {
    var calls: [AlkkagiCall] = []
    func call(_ call: AlkkagiCall) async throws -> AlkkagiResponse {
        calls.append(call)
        if call.rpc == .leave { return AlkkagiResponse(status: .ok, serverNowMs: awNowMs) }
        throw AlkkagiServiceError.invalidResponse
    }
}

private func awMatch(finished: Bool = false) -> AlkkagiMatch {
    var stones = AlkkagiGame().stones
    for index in stones.indices { stones[index].isPlaced = true }
    return AlkkagiMatch(id: "00000000-0000-4000-8000-000000000900", revision: 9,
                        phase: finished ? .finished : .aiming, currentPlayer: .black, myColor: .black,
                        black: awMe, white: awMinsu, stones: stones,
                        deadlineMs: finished ? nil : awNowMs + 21_000, shotCount: 4,
                        result: finished ? .black : nil, finishReason: finished ? "ring_out" : nil,
                        placementRevision: 2, myReady: true, opponentReady: true, stake: 5)
}

@MainActor
private func awController(_ store: AlkkagiOnlineStore, stuck: Double = 60) -> CheckAlkkagiWindowController {
    let controller = CheckAlkkagiWindowController(stuckWindowCheckSeconds: stuck)
    controller.configure(store: store)
    return controller
}

@MainActor
private func awMoveOffscreen(_ controller: CheckAlkkagiWindowController) {
    controller.currentWindow?.setFrameOrigin(NSPoint(x: -6000, y: -6000))
}

@MainActor
private func awPump(_ seconds: TimeInterval = 0.3) {
    RunLoop.current.run(until: Date().addingTimeInterval(seconds))
}

/// 0.3.80 패널의 보임 통지 꼴(기준선) — `Group{…}.onAppear(windowDidShow).onDisappear(windowDidHide)` 를 그대로 옮겼다.
private struct AWOldShapePanel: View {
    let store: AlkkagiOnlineStore

    var body: some View {
        Group {
            if store.state != nil {
                Color.red.frame(width: 300, height: 200)
            } else {
                Color.blue.frame(width: 300, height: 200)
            }
        }
        .onAppear { store.windowDidShow() }
        .onDisappear { store.windowDidHide() }
    }
}

/// 소스(주석 걷음 · 공백 접음).
private func awSource(_ name: String) throws -> String {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let raw = try String(contentsOf: root.appendingPathComponent("Sources/check/\(name)"), encoding: .utf8)
    var out = ""
    for line in raw.components(separatedBy: "\n") {
        var kept = line
        if let range = kept.range(of: "//") { kept = String(kept[..<range.lowerBound]) }
        out += kept + " "
    }
    return out.split(whereSeparator: \.isWhitespace).joined(separator: " ")
}

// MARK: - 시험

@MainActor
@Suite("1:1 알까기 — 맥 창(SPEC §5.1)", .serialized)
struct V03xxAlkkagiWindowTests {

    @Test("창 정체 — 제목 '1:1 알까기'(게임 이름 한 곳) · 1240×700 고정 · 최소화 가능 · 크기 고정 · 비활성에도 남음 · 다크")
    func windowIdentity() {
        // 없으면: 창 제목이 '알까기' 로 갈리거나(DF#2 — 이름 셋), 크기가 바뀌어 판 배율이 흔들리거나, 다른 앱을 누르면 창이 사라진다.
        #expect(CheckAlkkagiWindowController.windowTitle == "1:1 알까기")
        #expect(CheckAlkkagiWindowController.windowTitle == AlkkagiNoticeText.gameName, "창 제목이 게임 이름 한 곳에서 안 온다")
        #expect(CheckAlkkagiWindowController.windowTitle != "알까기", "기준선: 0.3.80 제목")
        #expect(CheckAlkkagiWindowController.frameAutosaveName == "check.alkkagi.window")
        #expect(CheckAlkkagiWindowController.fixedContentSize == CGSize(width: 1240, height: 700))
        let window = CheckAlkkagiWindowController.makeWindow()
        defer { window.close() }
        #expect(window.title == "1:1 알까기")
        #expect(window.contentMinSize == window.contentMaxSize)
        #expect(window.styleMask.contains(.miniaturizable))
        #expect(!window.styleMask.contains(.resizable))
        #expect(!window.isReleasedWhenClosed)
        #expect(!window.hidesOnDeactivate)
        #expect(window.appearance?.name == .darkAqua)
        #expect(window.alphaValue == CheckPanelVisibility.panelAlpha)
        #expect(CheckPanelVisibility.isRunningTests, "테스트 판정이 꺼져 있으면 이 스위트가 사용자 화면에 창을 띄운다")
    }

    @Test("자동저장 이름이 다른 창과 겹치지 않는다 — 실제로 열어 setFrameAutosaveName 이 참")
    func autosaveNameIsUnique() {
        // 없으면: 이름이 겹쳐 `setFrameAutosaveName` 이 false 를 돌려주고 자리 저장이 조용히 죽는다.
        let others = [CheckTetrisDuelWindowController.frameAutosaveName, CheckMahjongWindowController.frameAutosaveName,
                      CheckMiniGameWindowController.frameAutosaveName, CheckReversiWindowController.frameAutosaveName,
                      CheckCrossyDuelWindowController.frameAutosaveName]
        #expect(!others.contains(CheckAlkkagiWindowController.frameAutosaveName))
        let store = AlkkagiOnlineStore(clock: { awWall0 })
        let controller = awController(store)
        defer { controller.discardWindowForTesting() }
        controller.show()
        awMoveOffscreen(controller)
        #expect(controller.frameAutosaveActive, "자동저장 이름이 다른 창과 겹친다")
        // 기준선: 같은 이름을 쥔 창이 하나 더 있으면 거짓이 된다(이 단언이 무언가를 잰다).
        let rival = NSWindow(contentRect: .init(x: 0, y: 0, width: 10, height: 10), styleMask: [.titled], backing: .buffered, defer: true)
        rival.isReleasedWhenClosed = false
        #expect(!rival.setFrameAutosaveName(CheckAlkkagiWindowController.frameAutosaveName), "전제: 겹친 이름은 거짓")
    }

    @Test("첫 클릭을 받는다 — contentView 가 acceptsFirstMouse 참(기준선: 보통 호스팅 뷰는 거짓) · 연습 창도 같다")
    func acceptsFirstMouse() throws {
        // 없으면: 다른 앱에서 온 첫 클릭이 '창 앞으로'에 먹혀 판을 누른 손이 빈다(DF#83).
        let store = AlkkagiOnlineStore(clock: { awWall0 })
        let controller = awController(store)
        defer { controller.discardWindowForTesting() }
        controller.show()
        awMoveOffscreen(controller)
        let content = try #require(controller.currentWindow?.contentView)
        #expect(content.acceptsFirstMouse(for: nil), "알까기 창 첫 클릭이 창 앞으로에 먹힌다")
        #expect(content is NSHostingView<AlkkagiOnlinePanel>, "온라인 창 루트가 패널이 아니다")
        let plain = NSHostingView(rootView: Color.clear)
        #expect(!plain.acceptsFirstMouse(for: nil), "전제: 보통 호스팅 뷰는 첫 클릭을 안 받는다")

        // 스토어 없는 연습 창(시험 · 독립 연습)도 첫 클릭을 받고, 옛 시험(MiniGameDuelReturnTests)의 호스팅 타입 단언과 맞는다.
        let practice = CheckAlkkagiWindowController(stuckWindowCheckSeconds: 60)
        defer { practice.discardWindowForTesting() }
        practice.show(me: AlkkagiPlayerProfile(name: "흑돌 닉네임"))
        awMoveOffscreen(practice)
        let local = try #require(practice.currentWindow?.contentView as? NSHostingView<AlkkagiGameView>)
        #expect(local.acceptsFirstMouse(for: nil))
        #expect(local.rootView.me.name == "흑돌 닉네임")
    }

    @Test("고착 감시 재생성 — 못 뜬 창을 버리고 새로 열되 3회까지 · 자동저장을 놓았다 다시 잡는다 · 판은 그대로")
    func stuckWindowRebuildsUpToThree() throws {
        // 없으면: 화면에 못 올라간 창이 영영 안 뜨거나(재생성 없음), 재생성이 끝없이 돌거나, 자동저장 이름을 쥔 채 버려져 새 창이 자리를 못 저장한다.
        #expect(CheckAlkkagiWindowController.stuckWindowCheckSeconds == 0.5)
        #expect(CheckAlkkagiWindowController.maxStuckWindowRebuilds == 3)
        let store = AlkkagiOnlineStore(clock: { awWall0 })
        store.state = awMatch()
        let controller = awController(store)
        defer { controller.discardWindowForTesting() }
        controller.show()
        awMoveOffscreen(controller)
        let first = try #require(controller.currentWindow)
        controller.rebuildStuckWindow()
        awMoveOffscreen(controller)
        let second = try #require(controller.currentWindow)
        #expect(second !== first, "재생성이 같은 창을 돌려줬다")
        #expect(controller.isOpen && controller.frameAutosaveActive, "재생성한 창이 자동저장을 못 잡았다(옛 창이 이름을 쥐었다)")
        #expect(store.state?.id == awMatch().id, "재생성이 판을 바꿨다")
        #expect(store.isWindowVisible)
        controller.rebuildStuckWindow()
        controller.rebuildStuckWindow()
        awMoveOffscreen(controller)
        let third = try #require(controller.currentWindow)
        controller.rebuildStuckWindow()   // 넷째는 상한에 막힌다(기준선: 셋째까지는 창이 바뀌었다).
        #expect(controller.stuckWindowRebuilds == 3)
        #expect(controller.currentWindow === third, "상한(3회)을 넘어 재생성했다")
    }

    @Test("닫기 ≠ 기권 — 빨간 점은 판을 안 끝낸다(resign 호출 0) · 끝난 판이면 떠남 1회(기준선) · 키 상실 처리기 없음")
    func closingIsNotResigning() async throws {
        // 없으면: 창을 닫는 것이 판돈이 걸린 판의 기권이 되거나(사용자 실수 한 번에 루비를 잃는다), 닫기 통지가 스토어에 안 닿는다.
        #expect(!CheckAlkkagiWindowController().responds(to: #selector(NSWindowDelegate.windowDidResignKey(_:))),
                "창이 키 상실에 반응한다 — 다른 앱을 잠깐 본 것이 판 중단이 된다")
        func closeOnce(finished: Bool) async throws -> (calls: [AlkkagiOnlineWire.RPC], state: AlkkagiMatch?, heard: [Bool]) {
            let stub = AWStub()
            let store = AlkkagiOnlineStore(service: stub, clock: { awWall0 }, pollSeconds: 3_600)
            store.state = awMatch(finished: finished)
            let controller = awController(store)
            var heard: [Bool] = []
            controller.onClosed = { heard.append($0) }
            defer { controller.discardWindowForTesting() }
            controller.show()
            awMoveOffscreen(controller)
            let window = try #require(controller.currentWindow)
            controller.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: window))
            for _ in 0..<40 where !stub.calls.contains(where: { $0.rpc == .leave }) {
                try await Task.sleep(for: .milliseconds(25))
            }
            #expect(!store.isWindowVisible && !controller.isOpen)
            return (stub.calls.map(\.rpc), store.state, heard)
        }
        let active = try await closeOnce(finished: false)
        #expect(!active.calls.contains(.resign), "창을 닫았더니 기권이 나갔다: \(active.calls)")
        #expect(!active.calls.contains(.leave), "진행 판을 닫았더니 떠남이 나갔다: \(active.calls)")
        #expect(active.state?.phase == .aiming, "창을 닫았더니 진행 판이 바뀌었다")
        #expect(active.heard == [true], "빨간 점이 '사람이 닫음'으로 안 갔다: \(active.heard)")
        // 기준선: 끝난 판은 닫기 통지가 스토어에 닿아 떠남 1회(닫기 통지가 아예 안 닿는 변이는 0회).
        let finished = try await closeOnce(finished: true)
        #expect(finished.calls.filter { $0 == .leave }.count == 1, "닫기 통지가 스토어에 안 닿았다: \(finished.calls)")
        #expect(!finished.calls.contains(.resign))
    }

    @Test("최소화 = 안 보임만 · 되살림 = 보임 · 가림은 '안 보임'이 아니다")
    func miniaturizeAndOcclusion() throws {
        // 없으면: 최소화가 '닫기'로 번져 끝난 판을 떠나 버리거나, 가려진 창이 '안 보임'으로 번져 차례 말풍선 문이 엉뚱하게 닫힌다.
        let store = AlkkagiOnlineStore(clock: { awWall0 })
        let controller = awController(store)
        var heard: [Bool] = []
        controller.onClosed = { heard.append($0) }
        defer { controller.discardWindowForTesting() }
        controller.show()
        awMoveOffscreen(controller)
        let window = try #require(controller.currentWindow)
        #expect(store.isWindowVisible)
        controller.windowDidMiniaturize(Notification(name: NSWindow.didMiniaturizeNotification, object: window))
        #expect(!store.isWindowVisible && heard.isEmpty)
        controller.windowDidDeminiaturize(Notification(name: NSWindow.didDeminiaturizeNotification, object: window))
        #expect(store.isWindowVisible)
        controller.applyOcclusion(visible: false)
        #expect(store.isWindowVisible && store.isWindowOccluded)
        controller.applyOcclusion(visible: true)
        #expect(!store.isWindowOccluded)
        controller.close()
        #expect(heard == [false] && !store.isWindowVisible)
    }

    @Test("로비→판→로비 전환 뒤 보임 참 · 최소화한 채 판이 서면 보임 거짓 · 패널은 보임을 알리지 않는다(기준선: 0.3.80 패널 onAppear 꼴은 알린다) — DF#46")
    func visibilitySurvivesLobbyMatchLobby() throws {
        // 없으면: 패널이 Group onAppear/onDisappear 로 보임을 알려 로비↔판 전환에서 `isWindowVisible` 이 거짓으로 남고, 폴링·말풍선 문이
        // 창이 열린 채로 엉뚱하게 갈린다.
        let store = AlkkagiOnlineStore(clock: { awWall0 })
        let controller = awController(store)
        defer { controller.discardWindowForTesting() }
        controller.show()
        awMoveOffscreen(controller)
        awPump()
        #expect(store.isWindowVisible)
        var trail: [Bool] = []
        store.state = awMatch()
        awPump()
        trail.append(store.isWindowVisible)
        store.state = nil
        awPump()
        trail.append(store.isWindowVisible)
        store.state = awMatch()
        awPump()
        trail.append(store.isWindowVisible)
        #expect(trail == [true, true, true], "실제 호스팅에서 전환 뒤 보임이 거짓이 됐다: \(trail)")
        #expect(controller.lastVisibilityNotice == true)

        // 패널 소스에 보임 통지가 없다(창 컨트롤러 한 곳).
        let panel = try awSource("AlkkagiOnlinePanel.swift")
        #expect(!panel.contains("windowDidShow") && !panel.contains("windowDidHide"), "패널이 보임 통지를 다시 한다")
        let window = try awSource("CheckAlkkagiWindow.swift")
        #expect(window.contains("onlineStore?.windowDidShow()") && window.contains("onlineStore?.windowDidHide()"))

        // 최소화한 채 판이 서면(신청 수락 · 상대 수락) 보임은 거짓이어야 한다 — 그래야 시작 말풍선 문이 열리고 폴링이 쉰다.
        let window2 = try #require(controller.currentWindow)
        store.state = nil
        awPump()
        controller.windowDidMiniaturize(Notification(name: NSWindow.didMiniaturizeNotification, object: window2))
        store.state = awMatch()
        awPump()
        #expect(!store.isWindowVisible, "최소화한 창에서 판이 섰더니 '보임'이 됐다 — 시작 말풍선 문이 닫힌다")

        // 기준선(같은 실제 호스팅 · 창 컨트롤러 없이 화면 밖 창에 올려 잰다): 새 패널은 스스로 '보임'을 알리지 않고(거짓 그대로),
        // 0.3.80 꼴(Group onAppear)은 알린다(참). 보임의 출처가 창 통지 하나라는 것을 결과로 가른다.
        func probe<V: View>(_ view: V) -> NSWindow {
            let window = NSWindow(contentRect: NSRect(x: -6000, y: -6000, width: 300, height: 200),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.alphaValue = 0
            window.contentView = NSHostingView(rootView: view)
            window.orderFrontRegardless()
            return window
        }
        let newStore = AlkkagiOnlineStore(clock: { awWall0 })
        let newProbe = probe(AlkkagiOnlinePanel(store: newStore))
        let oldStore = AlkkagiOnlineStore(clock: { awWall0 })
        let oldProbe = probe(AWOldShapePanel(store: oldStore))
        defer {
            for window in [newProbe, oldProbe] { window.contentView = nil; window.orderOut(nil) }
        }
        awPump()
        #expect(!newStore.isWindowVisible, "패널이 스스로 '보임'을 알린다 — 출처가 둘이다")
        #expect(oldStore.isWindowVisible, "기준선: 0.3.80 꼴은 패널이 '보임'을 알린다 — 이게 거짓이면 위 단언이 아무것도 안 잰다")

        // 잼(11-10, 단언 없이 기록): 0.3.80 꼴에서 보인 채 로비↔판 전환 · 최소화 뒤 판 시작이 보임을 어떻게 남기는가.
        // 결과는 [참 참 참] · 거짓 — Group 의 조건 내용 전환은 onAppear/onDisappear 를 다시 부르지 않아 추정(전환 뒤 거짓)은 재현되지 않았다.
        var oldTrail: [Bool] = [oldStore.isWindowVisible]
        oldStore.state = awMatch()
        awPump()
        oldTrail.append(oldStore.isWindowVisible)
        oldStore.state = nil
        awPump()
        oldTrail.append(oldStore.isWindowVisible)
        oldStore.windowDidHide()            // 창 컨트롤러의 최소화 통지와 같다
        oldStore.state = awMatch()
        awPump()
        print("[DF#46 잼] 0.3.80 꼴: 보인 채 전환 \(oldTrail) · 최소화 뒤 판 시작 → 보임 \(oldStore.isWindowVisible) | 새 꼴: 전환 \(trail) · 최소화 뒤 판 시작 → 보임 \(store.isWindowVisible)")
    }
}
