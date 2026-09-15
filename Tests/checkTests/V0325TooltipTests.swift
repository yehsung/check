import AppKit
import CryptoKit
import Foundation
import SwiftUI
import Testing
@testable import check

// MARK: - v0.3.25 자체 말풍선 툴팁
//
// 배경(실측 2026-09-16): 시스템 툴팁은 실앱(0.3.24) 팝오버에서 6번 호버에 2번만 떴고 뜰 때도 1.7초 걸렸다. 최소 MenuBarExtra
// 앱에서 앱을 활성으로 해도 2/6 이었다. 같은 창의 onHover + 앵커 preference 자체 말풍선은 7/7. 그래서 Sources/check 의 시스템
// 툴팁 30곳을 `.checkTooltip` 으로 바꾸고 창 루트 네 곳에 `.checkTooltipLayer()` 를 달았다(근거 전문은 CheckTooltip.swift 머리 주석).
//
// 여기서 묻는 것:
//   ① 상태 기계(시각을 인자로 받아 결정적) — 무작위 전이 열의 불변식 포함   ② 배치 순수 함수
//   ③ 말풍선 크기·배치가 **그림에도** 반영되는가(ImageRenderer)
//   ④ 센터: 주입한 짧은 지연으로 실제로 뜨는가, 클릭 모니터가 보이거나 대기 중일 때만 걸리는가,
//      클릭 모니터 핸들러가 실제 NSEvent 를 먹지 않고 그대로 돌려주는가
//   ⑤ 소스 계약: 시스템 툴팁은 폴백 한 곳뿐, 호출 30곳, 루트 네 곳, 모디파이어의 폴백·빈 문구·onHover 의 로컬 hovering
//      갱신·정리·visibleID 불읽기, 클릭 모니터 설치가 통과 핸들러·마스크를 쓰는가
//
// 호버 자체(커서 이동)는 여기서 재지 않는다 — ImageRenderer 는 호버를 못 내고, 사용자가 쓰는 맥에 CGEvent 를 보낼 수 없다.

@Suite("v0.3.25 자체 말풍선 툴팁")
struct V0325TooltipTests {
    static let a = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
    static let b = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!
    static let c = UUID(uuidString: "00000000-0000-0000-0000-00000000000C")!

    // MARK: - ① 상태 기계

    @Test func timingConstantsLiveInOnePlace() {
        #expect(CheckTooltipTiming.showDelay == 0.4)
        #expect(CheckTooltipTiming.warmWindow == 0.6)
        let intent = CheckTooltipIntent()
        #expect(intent.showDelay == CheckTooltipTiming.showDelay)
        #expect(intent.warmWindow == CheckTooltipTiming.warmWindow)
    }

    @Test func firstHoverWaitsAndShowsOnFireAfterTheDelay() {
        var intent = CheckTooltipIntent()
        intent.hoverBegan(Self.a, now: 10)
        #expect(intent.visibleID == nil, "첫 호버가 지연 없이 떴다")
        #expect(intent.pendingID == Self.a)
        #expect(abs((intent.pendingAt ?? 0) - 10.4) < 1e-9)
        #expect(intent.isActive)
        intent.fire(Self.a, now: 10.4)
        #expect(intent.visibleID == Self.a)
        #expect(intent.pendingID == nil && intent.pendingAt == nil)
    }

    @Test func duplicateHoverBeganKeepsTheOriginalSchedule() {
        var intent = CheckTooltipIntent()
        intent.hoverBegan(Self.a, now: 10)
        intent.hoverBegan(Self.a, now: 10.3)
        #expect(abs((intent.pendingAt ?? 0) - 10.4) < 1e-9, "같은 항목의 중복 통지가 예약을 뒤로 밀었다")
    }

    @Test func leavingBeforeTheDelayMakesFireANoOp() {
        var intent = CheckTooltipIntent()
        intent.hoverBegan(Self.a, now: 10)
        intent.hoverEnded(Self.a, now: 10.2)
        #expect(intent.pendingID == nil && intent.pendingAt == nil)
        #expect(!intent.isActive)
        intent.fire(Self.a, now: 10.4)
        #expect(intent.visibleID == nil, "이미 떠난 항목의 예약이 말풍선을 띄웠다")
        // 보인 적 없이 떠났으니 워밍도 없다 — 다음 항목은 다시 기다린다.
        #expect(intent.lastHiddenAt == nil)
        intent.hoverBegan(Self.b, now: 10.3)
        #expect(intent.visibleID == nil)
        #expect(intent.pendingID == Self.b)
    }

    @Test func fireForAStalePendingIDIsIgnored() {
        var intent = CheckTooltipIntent()
        intent.hoverBegan(Self.a, now: 10)
        intent.hoverBegan(Self.b, now: 10.1)   // a 에서 b 로 옮겼는데 a 의 끝 통지가 아직 안 왔다
        #expect(intent.pendingID == Self.b)
        intent.fire(Self.a, now: 10.4)
        #expect(intent.visibleID == nil, "옛 예약(a)이 새 대기(b)를 밀어내고 떴다")
        intent.fire(Self.b, now: 10.5)
        #expect(intent.visibleID == Self.b)
    }

    @Test func enteringAnotherItemWhileOneIsVisibleSwapsImmediately() {
        var intent = CheckTooltipIntent()
        intent.hoverBegan(Self.a, now: 10)
        intent.fire(Self.a, now: 10.4)
        intent.hoverBegan(Self.b, now: 11)
        #expect(intent.visibleID == Self.b, "보이는 중에 옆 항목으로 옮겼는데 다시 기다렸다")
        #expect(intent.pendingID == nil)
        // a 의 끝 통지가 뒤늦게 와도 b 는 그대로이고, 숨긴 것이 아니므로 워밍 시각도 안 찍힌다.
        intent.hoverEnded(Self.a, now: 11.01)
        #expect(intent.visibleID == Self.b)
        #expect(intent.lastHiddenAt == nil)
    }

    @Test func leavingTheVisibleItemHidesIt() {
        var intent = CheckTooltipIntent()
        intent.hoverBegan(Self.a, now: 10)
        intent.fire(Self.a, now: 10.4)
        intent.hoverEnded(Self.a, now: 12)
        #expect(intent.visibleID == nil)
        #expect(intent.lastHiddenAt == 12)
        #expect(!intent.isActive)
        #expect(intent.hovered.isEmpty)
    }

    @Test func hidingWarmsTheNextItemOnlyWithinTheWindow() {
        var intent = CheckTooltipIntent()
        intent.hoverBegan(Self.a, now: 10)
        intent.fire(Self.a, now: 10.4)
        intent.hoverEnded(Self.a, now: 20)
        intent.hoverBegan(Self.b, now: 20.5)
        #expect(intent.visibleID == Self.b, "숨은 지 0.5초 만에 들어간 옆 항목이 다시 기다렸다")
        intent.hoverEnded(Self.b, now: 21)
        intent.hoverBegan(Self.c, now: 21.7)
        #expect(intent.visibleID == nil, "숨은 지 0.7초 뒤인데 워밍으로 즉시 떴다")
        #expect(intent.pendingID == Self.c)
    }

    @Test func mouseDownHidesAndSuppressesUntilTheHoverEnds() {
        var intent = CheckTooltipIntent()
        intent.hoverBegan(Self.a, now: 10)
        intent.fire(Self.a, now: 10.4)
        intent.mouseDown(now: 11)
        #expect(intent.visibleID == nil)
        #expect(intent.suppressed == [Self.a])
        #expect(intent.hovered.contains(Self.a))
        // 누른 채 그 자리에 머무는 동안(중복 통지 포함) 다시 뜨지 않는다.
        intent.hoverBegan(Self.a, now: 11.1)
        #expect(!intent.isActive, "누른 항목이 호버가 끝나기 전에 다시 대기에 올랐다")
        intent.fire(Self.a, now: 11.5)
        #expect(intent.visibleID == nil)
        // 나갔다 들어오면 다시 뜬다(첫 호버처럼 기다린 뒤).
        intent.hoverEnded(Self.a, now: 12)
        #expect(intent.suppressed.isEmpty)
        intent.hoverBegan(Self.a, now: 12.1)
        #expect(intent.pendingID == Self.a)
        intent.fire(Self.a, now: 12.5)
        #expect(intent.visibleID == Self.a)
    }

    @Test func mouseDownCancelsAPendingItemToo() {
        var intent = CheckTooltipIntent()
        intent.hoverBegan(Self.b, now: 30)
        intent.mouseDown(now: 30.1)
        #expect(intent.pendingID == nil && intent.pendingAt == nil)
        #expect(intent.suppressed == [Self.b])
        intent.fire(Self.b, now: 30.4)
        #expect(intent.visibleID == nil, "누른 뒤에 대기 중이던 말풍선이 떴다")
    }

    @Test func mouseDownDoesNotWarmTheNeighbor() {
        // (가) 누르고 옆으로: 클릭으로 숨긴 것은 '방금 숨었다'가 아니다.
        var intent = CheckTooltipIntent()
        intent.hoverBegan(Self.a, now: 10)
        intent.fire(Self.a, now: 10.4)
        intent.mouseDown(now: 11)
        #expect(intent.lastHiddenAt == nil)
        intent.hoverEnded(Self.a, now: 11.2)
        intent.hoverBegan(Self.b, now: 11.3)
        #expect(intent.visibleID == nil, "클릭 뒤 옆 버튼이 워밍으로 즉시 떴다")
        #expect(intent.pendingID == Self.b)

        // (나) 워밍으로 뜬 직후 누르고 옆으로: 클릭 **전**에 남아 있던 워밍도 끊긴다.
        var chain = CheckTooltipIntent()
        chain.hoverBegan(Self.a, now: 10)
        chain.fire(Self.a, now: 10.4)
        chain.hoverEnded(Self.a, now: 20)
        chain.hoverBegan(Self.b, now: 20.1)
        #expect(chain.visibleID == Self.b)   // 워밍
        chain.mouseDown(now: 20.2)
        chain.hoverEnded(Self.b, now: 20.3)
        chain.hoverBegan(Self.c, now: 20.4)  // 옛 lastHiddenAt(20.0) 기준 0.4초 — 워밍 창 안이다
        #expect(chain.visibleID == nil, "클릭 전의 워밍이 남아 옆 버튼이 즉시 떴다")
        #expect(chain.pendingID == Self.c)
    }

    /// 툴팁 안에 툴팁(토큰 사용량 행 ⊃ 순위 버튼). 검토가 상태 기계를 복사해 재생한 경로다: 행에 들어와 대기 → 0.4초 안에 버튼에
    /// 들어가 대기가 버튼으로 덮임 → 버튼을 떠나 행 위에 멈춤. 고치기 전에는 여기서 아무것도 기다리지 않아 행 말풍선이 영영 안 떴다.
    @Test func leavingTheInnerItemBringsTheOuterBubbleBack() {
        let row = Self.a, button = Self.b
        // (가) 대기 중에 안쪽을 지나갔다 — 바깥은 처음처럼 기다린 뒤 뜬다.
        var passing = CheckTooltipIntent()
        passing.hoverBegan(row, now: 10)
        passing.hoverBegan(button, now: 10.1)
        #expect(passing.pendingID == button)
        passing.hoverEnded(button, now: 10.3)
        #expect(passing.pendingID == row, "버튼을 떠나 행 위에 멈췄는데 행 말풍선이 대기에 안 올랐다")
        #expect(abs((passing.pendingAt ?? 0) - 10.7) < 1e-9, "행은 떠난 시각부터 다시 기다려야 한다")
        passing.fire(row, now: 10.7)
        #expect(passing.visibleID == row)

        // (나) 안쪽 말풍선이 보이다 떠났다 — 방금 숨었으니 바깥은 워밍으로 바로 뜬다.
        var shown = CheckTooltipIntent()
        shown.hoverBegan(row, now: 20)
        shown.fire(row, now: 20.4)
        shown.hoverBegan(button, now: 21)
        #expect(shown.visibleID == button)
        shown.hoverEnded(button, now: 22)
        #expect(shown.visibleID == row, "안쪽 말풍선을 떠나 행으로 돌아왔는데 행 말풍선이 바로 안 돌아왔다")

        // (다) 둘 다 떠나면 아무것도 안 남는다(되올림이 떠난 항목을 붙잡지 않는다).
        shown.hoverEnded(row, now: 22.1)
        #expect(shown.visibleID == nil && shown.pendingID == nil && !shown.isActive)

        // (라) 클릭으로 거둔 바깥은 되올리지 않는다.
        var clicked = CheckTooltipIntent()
        clicked.hoverBegan(row, now: 30)
        clicked.fire(row, now: 30.4)
        clicked.mouseDown(now: 30.5)
        clicked.hoverBegan(button, now: 30.6)
        clicked.hoverEnded(button, now: 30.8)
        #expect(clicked.visibleID == nil && clicked.pendingID == nil, "클릭으로 거둔 행 말풍선이 버튼을 지나자 되살아났다")
    }

    /// 되올림은 남은 호버 중 **가장 최근에 들어온** 항목이다 — 세 겹(카드 ⊃ 행 ⊃ 버튼)에서 버튼을 떠나면 행이지 카드가 아니다.
    /// 호버 목록을 들어온 순서로 두는 이유이고, 순서를 뒤집는 뮤턴트(N5)가 두 겹 테스트로는 살아남았다.
    @Test func leavingTheInnermostOfThreeBringsBackTheMiddleNotTheOutermost() {
        let card = Self.a, row = Self.b, button = Self.c
        var intent = CheckTooltipIntent()
        intent.hoverBegan(card, now: 10)
        intent.hoverBegan(row, now: 10.1)
        intent.hoverBegan(button, now: 10.2)
        intent.fire(button, now: 10.6)
        #expect(intent.visibleID == button)
        intent.hoverEnded(button, now: 11)
        #expect(intent.visibleID == row, "버튼을 떠나 행 위에 멈췄는데 바깥 카드 말풍선이 떴다")
        intent.hoverEnded(row, now: 11.2)
        #expect(intent.visibleID == card, "행을 떠나 카드 위에 멈췄는데 카드 말풍선이 안 돌아왔다")
    }

    /// 겹친 항목은 커서 바로 아래(가장 안쪽) 문구를 보인다 — onHover 통지 순서가 거꾸로 와서 상태 기계가 바깥을 올린 경우에도.
    @Test func overlayPrefersTheInnermostContainedEntry() {
        let row = CGRect(x: 12, y: 100, width: 292, height: 40)
        let button = CGRect(x: 270, y: 106, width: 27, height: 27)
        let elsewhere = CGRect(x: 12, y: 300, width: 40, height: 20)
        #expect(CheckTooltipOverlay.innermostIndex(of: row, among: [row, button, elsewhere]) == 1)
        #expect(CheckTooltipOverlay.innermostIndex(of: row, among: [button, row]) == 0, "순서와 무관해야 한다")
        #expect(CheckTooltipOverlay.innermostIndex(of: button, among: [row, button]) == 1, "안쪽이 보이면 바깥으로 넓히지 않는다")
        #expect(CheckTooltipOverlay.innermostIndex(of: row, among: [elsewhere]) == nil)
        #expect(CheckTooltipOverlay.innermostIndex(of: row, among: []) == nil)

        // 오버레이가 실제로 이 판정으로 문구·자리를 고른다(소스 계약) — 순수 함수만 맞고 그리는 쪽이 안 쓰면 뜻이 없다.
        let sources = try? Self.strippedSources()
        let overlay = sources?["CheckTooltip.swift"].flatMap { Self.between($0, "struct CheckTooltipOverlay: View {", "nonisolated static func innermostIndex") }
        #expect(overlay?.contains("let shown = Self.innermostIndex(of: target, among: rects).map { entries[$0] } ?? entry") == true)
        #expect(overlay?.contains("CheckTooltipPlacedBubble(text: shown.text, target: proxy[shown.anchor], container: proxy.size)") == true)
    }

    /// 창이 숨으면(orderOut) 센터를 비운다. 설정·미니게임·할 일 보드는 닫을 때 orderOut 만 해서 레이어의 onDisappear 가 안 온다.
    @MainActor
    @Test func hiddenWindowResetsTheCenter() async throws {
        let center = CheckTooltipCenter(showDelay: 10, warmWindow: 0.6)
        center.hoverBegan(Self.a)
        #expect(center.pendingID == Self.a && center.isMouseDownMonitorInstalled)

        let watcher = CheckTooltipWindowWatcher { center.reset() }
        let view = CheckTooltipWindowWatcherView(frame: .zero)
        view.onHidden = watcher.onHidden
        view.windowDidHide()
        #expect(center.pendingID == nil, "창이 숨었는데 대기가 남았다")
        #expect(!center.isMouseDownMonitorInstalled, "창이 숨었는데 클릭 모니터가 앱 전역에 남았다")

        // 실제 창: orderOut 이 isVisible 관찰을 거쳐 알림까지 닿는가.
        center.hoverBegan(Self.b)
        #expect(center.pendingID == Self.b)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 40, height: 40), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.alphaValue = 0
        window.contentView = view
        window.orderFrontRegardless()
        #expect(center.pendingID == Self.b, "창이 **뜨는** 순간에 센터를 비웠다 — 숨을 때만 비워야 한다")
        window.orderOut(nil)
        #expect(center.pendingID == nil, "실제 창의 orderOut 이 센터를 비우지 못했다")
        window.contentView = nil
    }

    /// 레이어가 창 숨김 감시자를 **크기 0 으로** 단다(소스 계약) — 감시자가 빠지면 orderOut 창에 호버 상태가 남는다.
    @Test func layerWatchesItsWindowHiding() throws {
        let sources = try Self.strippedSources()
        let tooltip = try #require(sources["CheckTooltip.swift"])
        #expect(tooltip.contains(".background(CheckTooltipWindowWatcher { center.reset() }.frame(width: 0, height: 0))"))
        #expect(tooltip.contains("window.observe(\\.isVisible"))
    }

    @Test func resetClearsEverything() {
        var intent = CheckTooltipIntent()
        intent.hoverBegan(Self.a, now: 10)
        intent.fire(Self.a, now: 10.4)
        intent.hoverBegan(Self.b, now: 11)
        intent.mouseDown(now: 11.5)
        intent.hoverEnded(Self.a, now: 11.6)
        intent.hoverBegan(Self.c, now: 11.7)
        #expect(intent != CheckTooltipIntent())
        #expect(!intent.suppressed.isEmpty && !intent.hovered.isEmpty && intent.pendingID != nil)
        intent.reset()
        #expect(intent == CheckTooltipIntent())
    }

    /// 전이를 무작위로 섞어도 상태 기계의 불변식이 선다: 대기·표시 중인 항목은 **늘 호버 중**이고, 대기와 표시는 겹치지 않고,
    /// 대기 시각은 대기 항목과 함께만 있고, 클릭으로 거둔 항목은 대기·표시에 없다.
    ///
    /// 왜 있는가: `fire` 의 "여전히 호버 중" 검사를 빼는 뮤턴트(M4)가 살아남았다. 공개 전이로는 차이를 낼 수 없는 등가 뮤턴트로
    /// 보인다 — hoverBegan 은 호버 집합에 넣은 **뒤에만** 대기를 세우고, 호버를 끝내는 전이·클릭·reset 은 대기를 지운다.
    /// 그 논증을 읽기로만 두지 않고 여기서 실행한다. 이 불변식이 깨지면 fire 의 가드는 표시만 막을 뿐, 떠난 항목의 대기가 남아
    /// 클릭 모니터(isActive 는 pendingID 를 본다)가 걸린 채로 남는다.
    @Test func invariantsHoldAcrossRandomTransitions() {
        var rng = TooltipWalkRNG(seed: 0x0325_7001)
        let ids = [Self.a, Self.b, Self.c]
        var firstViolation: String?
        var steps = 0, pendingSteps = 0, visibleSteps = 0, suppressedSteps = 0, warmShows = 0, warmMisses = 0
        walks: for walk in 0..<300 {
            var intent = CheckTooltipIntent()
            var now: TimeInterval = 0
            for step in 0..<80 {
                now += Double(rng.next() % 700) / 1000   // 0…0.7초 — 워밍 창(0.6) 안팎을 양쪽으로 넘나든다
                let id = ids[Int(rng.next() % UInt64(ids.count))]
                let before = intent
                let op: String
                // 클릭은 16번에 1번. 거둔 항목은 **그 항목의** 호버가 끝날 때까지 남아서, 클릭이 흔하면 워밍 경로가 굶는다
                // (6번에 1번이던 첫 판은 24,000걸음 중 워밍 즉시 표시가 43번뿐이었다).
                switch rng.next() % 16 {
                case 0...5: intent.hoverBegan(id, now: now); op = "hoverBegan"
                case 6...10: intent.hoverEnded(id, now: now); op = "hoverEnded"
                case 11...14: intent.fire(id, now: now); op = "fire"
                default: intent.mouseDown(now: now); op = "mouseDown"
                }
                steps += 1
                if intent.pendingID != nil { pendingSteps += 1 }
                if intent.visibleID != nil { visibleSteps += 1 }
                if !intent.suppressed.isEmpty { suppressedSteps += 1 }
                if op == "hoverBegan", before.visibleID == nil, intent.visibleID == id { warmShows += 1 }
                // 숨긴 적은 있는데 창을 넘겨 들어가 다시 기다린 경우 — 워밍 판정의 반대편.
                if op == "hoverBegan", before.visibleID == nil, before.pendingID != id, before.lastHiddenAt != nil,
                   intent.pendingID == id { warmMisses += 1 }

                var broken: [String] = []
                if let pending = intent.pendingID, !intent.hovered.contains(pending) { broken.append("대기 항목이 호버 밖") }
                if let visible = intent.visibleID, !intent.hovered.contains(visible) { broken.append("표시 항목이 호버 밖") }
                if intent.pendingID != nil, intent.visibleID != nil { broken.append("대기와 표시가 겹침") }
                if (intent.pendingID == nil) != (intent.pendingAt == nil) { broken.append("대기 시각과 대기 항목이 어긋남") }
                if let pending = intent.pendingID, intent.suppressed.contains(pending) { broken.append("거둔 항목이 대기 중") }
                if let visible = intent.visibleID, intent.suppressed.contains(visible) { broken.append("거둔 항목이 표시 중") }
                if !broken.isEmpty {
                    firstViolation = "walk \(walk) step \(step) \(op)(\(id.uuidString.suffix(1))): \(broken.joined(separator: ", "))"
                    break walks
                }
            }
        }
        #expect(firstViolation == nil, "\(firstViolation ?? "")")
        #expect(steps == 300 * 80)
        // 공허하게 초록이 아니다: 대기·표시·클릭으로 거둔 상태, 워밍 즉시 표시와 창을 넘긴 재대기를 실제로 여러 번 지난다.
        // 바닥값은 일부러 낮다 — 분포·걸음 수를 바꿔 한 경로가 굶으면 빨개지라는 뜻이지 이 시드의 수를 외우라는 뜻이 아니다.
        #expect(pendingSteps > 2_000 && visibleSteps > 2_000 && suppressedSteps > 2_000 && warmShows > 50 && warmMisses > 150,
                "대기 \(pendingSteps) · 표시 \(visibleSteps) · 거둠 \(suppressedSteps) · 워밍 즉시 \(warmShows) · 창 넘겨 재대기 \(warmMisses)")
    }

    // MARK: - ② 배치

    /// 메인 팝오버 창(414 폭). 높이는 실측 사례의 한 값이다 — 배치 규칙은 높이에 무관하다.
    static let popover = CGSize(width: 414, height: 517)

    @Test func placementDefaultsAreSixPoints() {
        #expect(CheckTooltipPlacement.gap == 6)
        #expect(CheckTooltipPlacement.margin == 6)
    }

    @Test func footerButtonWithoutRoomBelowGoesAbove() {
        let target = CGRect(x: 180, y: 483, width: 28, height: 28)   // maxY 511 — 아래 공간 없음
        let origin = CheckTooltipPlacement.origin(target: target, bubble: CGSize(width: 120, height: 26), container: Self.popover)
        #expect(origin == CGPoint(x: 134, y: 451))   // y = 483 − 6 − 26, x = 194 − 60
    }

    @Test func topButtonGoesBelow() {
        let target = CGRect(x: 150, y: 12, width: 28, height: 28)
        let origin = CheckTooltipPlacement.origin(target: target, bubble: CGSize(width: 120, height: 26), container: Self.popover)
        #expect(origin == CGPoint(x: 104, y: 46))    // y = 40 + 6
    }

    @Test func rightEdgeRailButtonIsClampedInsideTheRightMargin() {
        let target = CGRect(x: 340, y: 200, width: 64, height: 52)   // 오른쪽 세로 레일(338…402)
        let bubble = CGSize(width: 180, height: 26)
        let origin = CheckTooltipPlacement.origin(target: target, bubble: bubble, container: Self.popover)
        #expect(origin == CGPoint(x: 228, y: 258))
        #expect(origin.x + bubble.width == Self.popover.width - 6)
    }

    @Test func leftEdgeTargetIsClampedToTheLeftMargin() {
        let target = CGRect(x: 0, y: 100, width: 20, height: 20)
        let origin = CheckTooltipPlacement.origin(target: target, bubble: CGSize(width: 100, height: 26), container: Self.popover)
        #expect(origin == CGPoint(x: 6, y: 126))
    }

    @Test func compactWindowOf340ClampsAWideBubble() {
        let container = CGSize(width: 340, height: 400)
        let target = CGRect(x: 300, y: 10, width: 28, height: 28)
        let origin = CheckTooltipPlacement.origin(target: target, bubble: CGSize(width: 258, height: 40), container: container)
        #expect(origin == CGPoint(x: 76, y: 44))     // x 상한 = 340 − 6 − 258
    }

    @Test func bubbleLargerThanTheContainerSitsAtTheMargin() {
        let container = CGSize(width: 200, height: 100)
        let target = CGRect(x: 50, y: 40, width: 20, height: 20)
        let origin = CheckTooltipPlacement.origin(target: target, bubble: CGSize(width: 300, height: 150), container: container)
        #expect(origin == CGPoint(x: 6, y: 6))
    }

    @Test func neitherSideFitsSoTheRoomierSideIsClamped() {
        let container = CGSize(width: 414, height: 120)
        let bubble = CGSize(width: 100, height: 60)
        // 아래 공간(50) > 위(40): 아래에 붙인 뒤 상한 120 − 6 − 60 = 54 로 클램프.
        let roomierBelow = CheckTooltipPlacement.origin(
            target: CGRect(x: 100, y: 40, width: 30, height: 30), bubble: bubble, container: container)
        #expect(roomierBelow == CGPoint(x: 65, y: 54))
        // 위 공간(60) > 아래(30): 위에 붙인 뒤(−6) 하한 6 으로 클램프.
        let roomierAbove = CheckTooltipPlacement.origin(
            target: CGRect(x: 100, y: 60, width: 30, height: 30), bubble: bubble, container: container)
        #expect(roomierAbove == CGPoint(x: 65, y: 6))
    }

    @Test func exactFitsAreInclusive() {
        let bubble = CGSize(width: 100, height: 26)
        // 아래가 딱 맞는다: 479 + 6 + 26 = 511 = 517 − 6 → 아래.
        let belowExact = CheckTooltipPlacement.origin(
            target: CGRect(x: 100, y: 459, width: 20, height: 20), bubble: bubble, container: Self.popover)
        #expect(belowExact.y == 485)
        // 1pt 넘치면 위로.
        let belowOver = CheckTooltipPlacement.origin(
            target: CGRect(x: 100, y: 460, width: 20, height: 20), bubble: bubble, container: Self.popover)
        #expect(belowOver.y == 428)
        // 위가 딱 맞는다(아래는 안 된다): 52 − 6 − 40 = 6.
        let aboveExact = CheckTooltipPlacement.origin(
            target: CGRect(x: 100, y: 52, width: 20, height: 1), bubble: CGSize(width: 100, height: 40),
            container: CGSize(width: 414, height: 100))
        #expect(aboveExact.y == 6)
        // 가로가 딱 맞는다: 오른쪽 끝 308 + 100 = 408 = 414 − 6, 왼쪽 끝 6.
        let rightExact = CheckTooltipPlacement.origin(
            target: CGRect(x: 348, y: 100, width: 20, height: 20), bubble: bubble, container: Self.popover)
        #expect(rightExact.x == 308)
        let leftExact = CheckTooltipPlacement.origin(
            target: CGRect(x: 46, y: 100, width: 20, height: 20), bubble: bubble, container: Self.popover)
        #expect(leftExact.x == 6)
    }

    // MARK: - ③ 말풍선 그림

    @MainActor
    @Test func bubbleHugsShortTextAndWrapsLongTextAt240() throws {
        let shortText = "새로고침"
        let longText = "앱 사용자 전체의 AI 토큰 순위를 봅니다 — 이 문장은 일부러 길게 적어 한 줄 폭 240pt 를 넘기고 여러 줄로 접히는지 확인한다"
        let short = try Self.renderedSize(CheckTooltipBubble(text: shortText))
        let long = try Self.renderedSize(CheckTooltipBubble(text: longText))
        let shortLine = try Self.renderedSize(Self.bubbleFont(Text(shortText)))
        let longLine = try Self.renderedSize(Self.bubbleFont(Text(longText)))
        // 전제: 짧은 글은 한 줄로 240 안, 긴 글은 한 줄이면 240 을 넘는다.
        #expect(shortLine.width < CheckTooltipBubble.maxTextWidth)
        #expect(longLine.width > CheckTooltipBubble.maxTextWidth)
        // 짧은 글: 글 폭 + 가로 여백(9×2)에 맞춘다 — 240 으로 늘지 않는다.
        #expect(short.width < CheckTooltipBubble.maxTextWidth)
        #expect(abs(short.width - (shortLine.width + 18)) <= 1.5, "짧은 말풍선 폭 \(short.width) vs 글 \(shortLine.width) + 18")
        // 긴 글: 글 폭은 240 이하로 줄바꿈하고(말풍선 = 글 + 18), 높이는 한 줄짜리보다 크다.
        #expect(long.width <= CheckTooltipBubble.maxTextWidth + 18 + 0.5, "긴 말풍선 폭 \(long.width)")
        #expect(long.width > CheckTooltipBubble.maxTextWidth / 2)
        #expect(long.height > short.height + 8, "긴 말풍선 높이 \(long.height) vs 한 줄 \(short.height) — 줄바꿈이 안 됐다")
    }

    /// 배치가 **그림에도** 반영되는가. 잔디 말풍선에서 조건부 자식에 건 alignmentGuide 가 무시되고 (0,0) 에 그려진
    /// 실측이 있다 — 순수 함수가 초록이어도 가이드가 안 먹으면 말풍선은 전부 좌상단에 뜬다. 컨테이너 크기의 판 위에
    /// 그린 말풍선의 카드 색 영역이 배치 원점에 있는지, 컨테이너 폭 제안에 늘어나지 않았는지 잰다.
    @MainActor
    @Test func placedBubbleIsDrawnAtThePlacementOrigin() throws {
        let cases: [(name: String, text: String, target: CGRect)] = [
            ("하단 푸터 버튼 → 위", "새로고침", CGRect(x: 180, y: 483, width: 28, height: 28)),
            ("오른쪽 레일 버튼 → 오른쪽 여백 안", "앱 사용자 전체의 AI 토큰 순위를 봅니다", CGRect(x: 340, y: 200, width: 64, height: 52)),
            ("상단 왼쪽 버튼 → 아래·왼쪽 여백", "닫기", CGRect(x: 0, y: 12, width: 28, height: 28)),
        ]
        for item in cases {
            let bubble = try Self.renderedSize(CheckTooltipBubble(text: item.text))
            let expected = CheckTooltipPlacement.origin(target: item.target, bubble: bubble, container: Self.popover)
            let placed = CheckTooltipPlacedBubble(text: item.text, target: item.target, container: Self.popover)
            let box = try #require(try Self.cardFillBox(placed), "\(item.name): 말풍선 카드가 안 그려졌다")
            #expect(abs(box.minX - expected.x) <= 3, "\(item.name): x \(box.minX) vs 배치 \(expected.x)")
            #expect(abs(box.minY - expected.y) <= 3, "\(item.name): y \(box.minY) vs 배치 \(expected.y)")
            #expect(abs(box.width - bubble.width) <= 4, "\(item.name): 폭 \(box.width) vs 말풍선 \(bubble.width) — 컨테이너 제안에 늘어났다")
        }
    }

    /// 보이는 말풍선이 없으면 레이어·모디파이어는 **한 픽셀도** 바꾸지 않는다 — 이 앱의 렌더 테스트 전부가 기대는 사실이다.
    ///
    /// 레이어 밖 폴백만은 정확히 같지 않다. 폴백은 시스템 툴팁 모디파이어 그 자체인데, 그 모디파이어는 ImageRenderer 그림의
    /// 색을 최대 1단계 흔든다(실측 2026-09-16 스크래치 프로브, 같은 200pt 뷰: 400×176px 중 1,132px 이 채널 차 1 ·
    /// 같은 뷰끼리 0px · 접근성 힌트만 단 뷰 0px). 그 흔들림은 v0.3.24 까지 호출부가 늘 갖고 있던 것이라, 폴백은 크기가 같고
    /// 채널 차가 1 이하인지만 본다 — 말풍선이나 빈 카드를 그리면 차가 1 을 크게 넘는다.
    @MainActor
    @Test func layerAndModifiersDrawNothingWhileNoBubbleIsVisible() throws {
        let plain = VStack(spacing: 8) {
            Text("새로고침").padding(6)
            Text("로그아웃").padding(6)
        }
        .padding(12)
        .frame(width: 200)
        .background(CheckTheme.background)

        let layered = VStack(spacing: 8) {
            Text("새로고침").padding(6).checkTooltip("새로고침")
            Text("로그아웃").padding(6).checkTooltip("   ")
        }
        .padding(12)
        .frame(width: 200)
        .background(CheckTheme.background)
        .checkTooltipLayer()

        let fallback = VStack(spacing: 8) {
            Text("새로고침").padding(6).checkTooltip("새로고침")
            Text("로그아웃").padding(6).checkTooltip("   ")
        }
        .padding(12)
        .frame(width: 200)
        .background(CheckTheme.background)

        // ★ 레이어도 채널 차 1 이하로 본다(정확히 같음이 아니다). 정확히 같음을 요구하던 판은 격리 20회 중 2~6회 빨개졌다 —
        //   ImageRenderer 가 프로세스 초기 몇 장 사이에 **같은 뷰의** 그림을 채널 1단계 옮긴다(재검증 실측: 1,722~1,726px, 최대 차는
        //   늘 1). 말풍선·빈 카드·AppKit 자리(노란 상자)를 그리면 차가 1 을 크게 넘으므로 이 단언의 뜻은 그대로다.
        func pixels(_ view: some View) throws -> (bytes: [UInt8], width: Int, height: Int) {
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let image = renderer.cgImage else { throw TooltipRenderError.failed }
            return try Self.rgba(image)
        }
        func maxChannelDelta(_ lhs: (bytes: [UInt8], width: Int, height: Int),
                             _ rhs: (bytes: [UInt8], width: Int, height: Int)) -> Int {
            guard lhs.bytes.count == rhs.bytes.count else { return Int.max }
            var delta = 0
            for index in lhs.bytes.indices { delta = max(delta, abs(Int(lhs.bytes[index]) - Int(rhs.bytes[index]))) }
            return delta
        }
        let base = try pixels(plain)
        let layer = try pixels(layered)
        #expect(layer.width == base.width && layer.height == base.height, "레이어가 크기를 바꿨다")
        let layerDelta = maxChannelDelta(layer, base)
        #expect(layerDelta <= 1, "레이어·모디파이어가 말풍선 없이도 그림을 바꿨다(최대 채널 차 \(layerDelta))")

        let fell = try pixels(fallback)
        #expect(fell.width == base.width && fell.height == base.height, "폴백이 크기를 바꿨다")
        let fallbackDelta = maxChannelDelta(fell, base)
        #expect(fallbackDelta <= 1, "폴백이 시스템 툴팁의 1단계 색 흔들림을 넘어 그림을 바꿨다(최대 채널 차 \(fallbackDelta))")
    }

    // MARK: - ④ 센터

    @MainActor
    @Test func centerShowsAfterTheInjectedDelayAndTheMonitorFollowsActivity() async throws {
        let center = CheckTooltipCenter(showDelay: 0.05, warmWindow: 0.6)
        #expect(center.visibleID == nil)
        #expect(!center.isMouseDownMonitorInstalled, "아무것도 없는데 클릭 모니터가 걸려 있다")

        center.hoverBegan(Self.a)
        #expect(center.visibleID == nil)
        #expect(center.pendingID == Self.a)
        #expect(center.isMouseDownMonitorInstalled, "대기 중에 클릭 모니터가 없으면 누르는 순간 예약을 못 거둔다")

        #expect(await Self.waitUntil { center.visibleID == Self.a }, "주입한 지연(0.05초) 뒤에 말풍선이 안 떴다")
        #expect(center.isMouseDownMonitorInstalled)

        center.hoverEnded(Self.a)
        #expect(center.visibleID == nil)
        #expect(!center.isMouseDownMonitorInstalled, "숨겼는데 클릭 모니터가 남았다")

        // 방금 숨었다 — 워밍으로 즉시.
        center.hoverBegan(Self.b)
        #expect(center.visibleID == Self.b)
        #expect(center.isMouseDownMonitorInstalled)

        center.mouseDown()
        #expect(center.visibleID == nil)
        #expect(!center.isMouseDownMonitorInstalled)

        // 클릭이 워밍을 끊었다 — 옆 항목은 대기. 떠나면 예약이 취소돼 나중에도 안 뜬다.
        center.hoverEnded(Self.b)
        center.hoverBegan(Self.c)
        #expect(center.visibleID == nil)
        #expect(center.pendingID == Self.c)
        #expect(center.isMouseDownMonitorInstalled)
        center.hoverEnded(Self.c)
        #expect(center.pendingID == nil)
        #expect(!center.isMouseDownMonitorInstalled)
        try await Task.sleep(for: .milliseconds(250))
        #expect(center.visibleID == nil, "떠난 항목의 예약이 취소되지 않고 말풍선을 띄웠다")

        // reset 은 예약과 모니터까지 걷는다.
        center.hoverBegan(Self.a)
        #expect(center.isMouseDownMonitorInstalled)
        center.reset()
        #expect(center.visibleID == nil && center.pendingID == nil)
        #expect(!center.isMouseDownMonitorInstalled, "reset 뒤에 클릭 모니터가 남았다")
        try await Task.sleep(for: .milliseconds(250))
        #expect(center.visibleID == nil, "reset 뒤에 옛 예약이 살아 말풍선을 띄웠다")
        #expect(!center.isMouseDownMonitorInstalled)
    }

    @MainActor
    @Test func centerReadsTheInjectedClockForTheWarmWindow() async {
        let clock = ManualTooltipClock()
        let center = CheckTooltipCenter(showDelay: 0.05, warmWindow: 0.6, now: { clock.now })
        center.hoverBegan(Self.a)
        #expect(await Self.waitUntil { center.visibleID == Self.a })
        clock.now += 1
        center.hoverEnded(Self.a)
        clock.now += 0.5
        center.hoverBegan(Self.b)
        #expect(center.visibleID == Self.b, "주입한 시계로 0.5초 — 워밍 창 안인데 기다렸다")
        clock.now += 1
        center.hoverEnded(Self.b)
        clock.now += 0.7
        center.hoverBegan(Self.c)
        #expect(center.visibleID == nil, "주입한 시계로 0.7초가 지났는데 워밍으로 즉시 떴다")
        #expect(center.pendingID == Self.c)
        center.reset()
        #expect(!center.isMouseDownMonitorInstalled)
    }

    /// 클릭 모니터 핸들러는 센터에 알리고 **받은 이벤트를 그대로** 돌려준다. nil 을 돌려주면(뮤턴트 X2) 말풍선이 보이거나
    /// 대기 중인 동안 앱의 좌·우·기타 클릭이 통째로 사라진다. 위 센터 테스트는 mouseDown() 을 직접 불러 이 반환값을 못 봤다.
    /// 설치 자리가 이 핸들러와 이 마스크를 쓰는지는 소스 계약(`clickMonitorIsInstalledThroughThePassThroughHandler`)이 본다.
    @MainActor
    @Test func mouseDownMonitorHandlerNotifiesAndPassesTheSameEventThrough() throws {
        #expect(CheckTooltipCenter.mouseDownMonitorMask == [.leftMouseDown, .rightMouseDown, .otherMouseDown])
        var notified = 0
        let handler = CheckTooltipCenter.mouseDownMonitorHandler { notified += 1 }
        let types: [NSEvent.EventType] = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        for type in types {
            let event = try #require(
                NSEvent.mouseEvent(
                    with: type, location: NSPoint(x: 10, y: 10), modifierFlags: [], timestamp: 0,
                    windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
                ),
                "마우스다운(\(type.rawValue)) 이벤트를 만들지 못했다"
            )
            let returned = handler(event)
            #expect(returned === event, "클릭 모니터가 마우스다운(\(type.rawValue))을 먹었다 — 말풍선이 떠 있는 동안 클릭이 사라진다")
        }
        #expect(notified == types.count, "클릭 모니터가 센터에 알리지 않았다(\(notified)/\(types.count))")
    }

    // MARK: - ⑤ 소스 계약

    @Test func systemTooltipSurvivesOnlyAsTheFallback() throws {
        let sources = try Self.strippedSources()
        let helpSites = sources.compactMap { name, code -> String? in
            let n = Self.count(".help(", in: code)
            return n > 0 ? "\(name):\(n)" : nil
        }.sorted()
        #expect(helpSites == ["CheckTooltip.swift:1"], "시스템 툴팁이 남은 자리: \(helpSites)")
        #expect(sources["CheckTooltip.swift"]?.contains("content.help(text)") == true)
    }

    @Test func everyFormerSystemTooltipSiteUsesCheckTooltipWithTheSameText() throws {
        let sources = try Self.strippedSources()
        // 옛 시스템 툴팁은 30곳이었다(grep 31줄 중 한 줄은 문서 주석이었다).
        let total = sources.values.reduce(0) { $0 + Self.count(".checkTooltip(", in: $1) }
        #expect(total >= 30, ".checkTooltip( 호출 \(total)곳")
        let perFile: [String: Int] = [
            "CheckMenuView.swift": 11, "CheckTodoBoardView.swift": 4, "MiniGamePanel.swift": 3, "CheckComponents.swift": 3,
            "CheckTokenUsage.swift": 2, "CheckSettingsView.swift": 2, "CheckShopPanel.swift": 1, "CheckMessageView.swift": 1,
            "CheckCharacterPanel.swift": 1, "CheckFocusModeButton.swift": 1, "CheckAvatarView.swift": 1,
        ]
        for (name, minimum) in perFile {
            let n = Self.count(".checkTooltip(", in: sources[name] ?? "")
            #expect(n >= minimum, "\(name): .checkTooltip( \(n)곳 < \(minimum)")
        }
        // 문구·조건은 그대로다(표본 — 삼항·보간·상수·계산 프로퍼티를 한 가지씩 이상).
        let samples: [(file: String, call: String)] = [
            ("CheckCharacterPanel.swift", #".checkTooltip("캐릭터 고르기")"#),
            ("CheckShopPanel.swift", #".checkTooltip(owned ? "\(name) — 보유 중" : "\(name) 사기")"#),
            ("CheckSettingsView.swift", #".checkTooltip(store.isDisplayNameLocked ? "일주일에 한 번만 바꿀 수 있어요" : "별명 저장")"#),
            ("CheckSettingsView.swift", #".checkTooltip("\(WorkShortcut.default.displayString) 로 되돌려요")"#),
            ("CheckTodoBoardView.swift", ".checkTooltip(item.isDone ? TodoBoardStrings.markUndone : TodoBoardStrings.markDone)"),
            ("CheckTodoBoardView.swift", ".checkTooltip(TodoBoardStrings.deleteItem)"),
            ("CheckComponents.swift", ".checkTooltip(help)"),
            ("CheckComponents.swift", #".checkTooltip("닫기")"#),
            ("CheckAvatarView.swift", #".checkTooltip("아바타 변경")"#),
            ("CheckFocusModeButton.swift", ".checkTooltip(FocusModeButtonText.tooltip(face))"),
            ("CheckTokenUsage.swift", #".checkTooltip("앱 사용자 전체의 AI 토큰 순위를 봅니다")"#),
            ("CheckMenuView.swift", #".checkTooltip("잠시 후 다시 찌를 수 있어요")"#),
            ("CheckMenuView.swift", ".checkTooltip(UltraBalanceText.rowTooltip(balance: ultraBalance, unlimited: ultraUnlimited))"),
            ("CheckMenuView.swift", ".checkTooltip(UltraBalanceText.badgeHelp(balance: balance, unlimited: isUnlimited))"),
            ("CheckMenuView.swift", ".checkTooltip(messageHelp)"),
        ]
        for sample in samples {
            #expect(sources[sample.file]?.contains(sample.call) == true, "\(sample.file) 에 \(sample.call) 이 없다")
        }
        #expect(Self.count(".checkTooltip(title)", in: sources["MiniGamePanel.swift"] ?? "") == 3)
    }

    @Test func fourWindowRootsCarryTheLayerOutsideEveryClip() throws {
        let sources = try Self.strippedSources()
        let layerSites = sources.compactMap { name, code -> String? in
            let n = Self.count(".checkTooltipLayer()", in: code)
            return n > 0 ? "\(name):\(n)" : nil
        }.sorted()
        // v0.3.27: 1:1 오목 창(GomokuPanel) 루트가 다섯 번째 자리로 붙었다(테스트 이름은 식별자라 그대로 둔다).
        #expect(layerSites == [
            "CheckMenuView.swift:1", "CheckSettingsView.swift:1", "CheckTodoBoardWindow.swift:1", "GomokuPanel.swift:1",
            "MiniGamePanel.swift:1",
        ], "레이어 자리: \(layerSites)")
        // 오목 창: 창 고정 프레임·배경·전경색 뒤(판·목록 클리핑 바깥).
        let gomoku = try #require(Self.between(sources["GomokuPanel.swift"] ?? "",
                                               "struct GomokuPanel: View {", "private var content: some View {"))
        #expect(gomoku.contains("height: GomokuWindowLayout.contentSize.height, alignment: .topLeading) .background(CheckTheme.background) .foregroundStyle(CheckTheme.primaryText) .checkTooltipLayer()"))

        // 팝오버: 창 전체를 덮는 가장 바깥 시각 체인(배경·전경색) 바로 뒤.
        let menu = try #require(Self.between(sources["CheckMenuView.swift"] ?? "",
                                             "struct CheckMenuView: View {", "private var bodyColumn: some View {"))
        #expect(menu.contains(".background(CheckTheme.background) .foregroundStyle(CheckTheme.primaryText) .checkTooltipLayer()"))
        // 설정 창: 창을 채우는 프레임·배경 뒤.
        let settings = try #require(Self.between(sources["CheckSettingsView.swift"] ?? "",
                                                 "struct CheckSettingsView: View {", "private func section("))
        #expect(settings.contains(".background(CheckTheme.background) .checkTooltipLayer()"))
        // 할 일 보드: 보드 본체(모서리 clipShape 를 가진 CheckTodoBoardView) 바깥.
        let board = try #require(Self.between(sources["CheckTodoBoardWindow.swift"] ?? "",
                                              "private struct TodoBoardRootView: View {", "final class CheckTodoBoardController {"))
        #expect(board.contains("onOpacityChange: onOpacityChange ) .checkTooltipLayer()"))
        // 미니게임 창: 창 고정 프레임 뒤.
        let game = try #require(Self.between(sources["MiniGamePanel.swift"] ?? "",
                                             "struct CheckMiniGameWindowView: View {", "private func gameColumn("))
        #expect(game.contains("height: MiniGameWindowLayout.contentSize.height, alignment: .topLeading) .checkTooltipLayer()"))
    }

    @Test func modifierFallsBackSkipsBlankCleansUpAndNeverReadsVisibleID() throws {
        let code = try #require(try Self.strippedSources()["CheckTooltip.swift"])
        let modifier = try #require(Self.between(code,
                                                 "struct CheckTooltipModifier: ViewModifier {", "struct CheckTooltipLayerModifier: ViewModifier {"))
        // 공백뿐인 문구 → 아무것도 안 붙인다(말풍선·힌트·호버 추적 모두 없음).
        #expect(modifier.contains("if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { content } else if let center {"))
        // 레이어 밖 → 시스템 툴팁 폴백.
        #expect(modifier.contains("@Environment(\\.checkTooltipCenter) private var center"))
        #expect(modifier.contains("} else { content.help(text) }"))
        // 호버 추적 + 호버 중에 사라지면 끝났다고 알린다. onHover 는 센터에 알리기 전에 **로컬 hovering 을 갱신한다** — 이 줄이
        // 빠지면(뮤턴트 X1) preference 가 한 번도 안 실려, 센터가 visibleID 를 세워도 오버레이가 찾을 항목이 없다. 레이어가
        // 있으니 시스템 툴팁 폴백도 없어 실앱의 말풍선이 전부 사라진다. 렌더·센터 테스트는 호버를 못 내므로 소스로 못 박는다.
        #expect(modifier.contains(
            ".onHover { inside in if hovering != inside { hovering = inside } if inside { center.hoverBegan(entryID) } else { center.hoverEnded(entryID) } }"
        ), "onHover 가 로컬 hovering 을 갱신하지 않으면 preference 가 안 실려 말풍선이 한 번도 안 뜬다")
        #expect(modifier.contains(".onDisappear { guard hovering else { return } hovering = false center.hoverEnded(entryID) }"))
        // preference 는 로컬 호버 중일 때만 싣고(body 에서 읽은 값), 안쪽 툴팁 값을 보존하는 transform 이다.
        #expect(modifier.contains("let showing = hovering"))
        #expect(modifier.contains(".transformAnchorPreference(key: CheckTooltipPreferenceKey.self, value: .bounds) { entries, anchor in if showing { entries.append("))
        #expect(!modifier.contains(".anchorPreference("), "바깥 anchorPreference 는 안쪽 툴팁이 실은 값을 덮는다")
        #expect(modifier.contains(".accessibilityHint(Text(text))"))
        // 호버 한 번에 이 모디파이어를 단 뷰 전부가 다시 평가되지 않게 — 센터의 보이는 항목을 읽지 않는다.
        #expect(!modifier.contains("visibleID"))

        let layer = try #require(Self.between(code,
                                              "struct CheckTooltipLayerModifier: ViewModifier {", "struct CheckTooltipOverlay: View {"))
        #expect(layer.contains("@State private var center = CheckTooltipCenter()"))
        #expect(layer.contains(".environment(\\.checkTooltipCenter, center)"))
        #expect(layer.contains(".overlayPreferenceValue(CheckTooltipPreferenceKey.self)"))
        #expect(layer.contains(".onDisappear { center.reset() }"))
        #expect(!layer.contains("visibleID"), "레이어 body 가 visibleID 를 읽으면 루트 전체가 호버마다 다시 평가된다")

        let overlay = try #require(Self.between(code,
                                                "struct CheckTooltipOverlay: View {", "struct CheckTooltipPlacedBubble: View {"))
        #expect(overlay.contains("entries.last(where: { $0.id == visible })"))
        #expect(overlay.contains(".allowsHitTesting(false)"))
    }

    /// 클릭 모니터는 **이벤트를 돌려주는 핸들러**로, 세 가지 마우스다운 마스크로 한 벌만 건다. 핸들러의 반환값 자체는
    /// `mouseDownMonitorHandlerNotifiesAndPassesTheSameEventThrough` 가 실제 NSEvent 로 잰다 — 여기서는 설치 자리가 그
    /// 핸들러·마스크를 우회하지 않는지(예: 이벤트를 먹는 클로저를 직접 넘기거나 마스크를 좁히는지)만 본다.
    @Test func clickMonitorIsInstalledThroughThePassThroughHandler() throws {
        let code = try #require(try Self.strippedSources()["CheckTooltip.swift"])
        let install = try #require(Self.between(code,
                                                "private func installMouseDownMonitor() {", "private func removeMouseDownMonitor() {"))
        #expect(install.contains(
            "removeMouseDownMonitor() let raw = NSEvent.addLocalMonitorForEvents(matching: Self.mouseDownMonitorMask, handler: Self.mouseDownMonitorHandler { [weak self] in self?.mouseDown() }) mouseDownMonitor = raw.map(CheckTooltipMonitorToken.init)"
        ), "클릭 모니터가 기존 것을 떼고, 통과 핸들러·세 마우스다운 마스크로 걸리지 않는다")
        #expect(Self.count("NSEvent.addLocalMonitorForEvents", in: code) == 1, "클릭 모니터 설치 자리가 둘 이상이다")
    }

    // MARK: - 도우미

    /// 이상 크기로 그린 뷰의 포인트 크기(scale 2 픽셀 ÷ 2).
    @MainActor
    static func renderedSize(_ view: some View) throws -> CGSize {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.cgImage else { throw TooltipRenderError.failed }
        return CGSize(width: CGFloat(image.width) / 2, height: CGFloat(image.height) / 2)
    }

    @MainActor
    static func bubbleFont(_ text: Text) -> some View {
        text.font(.system(size: 11, weight: .medium)).fixedSize()
    }

    /// 말풍선 카드 채움색(CheckTheme.panelElevated = sRGB 0.21·0.22·0.29 ≈ 54·56·74)인 불투명 픽셀의 경계 상자(포인트).
    /// 글자(밝음)·테두리(흰 14% 가 얹혀 밝음)·그림자(검정)는 걸리지 않는다.
    @MainActor
    static func cardFillBox(_ view: some View) throws -> CGRect? {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.cgImage else { throw TooltipRenderError.failed }
        let (bytes, width, height) = try rgba(image)
        var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                guard bytes[i + 3] >= 245,
                      abs(Int(bytes[i]) - 54) <= 12, abs(Int(bytes[i + 1]) - 56) <= 12, abs(Int(bytes[i + 2]) - 74) <= 12
                else { continue }
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        return CGRect(x: CGFloat(minX) / 2, y: CGFloat(minY) / 2,
                      width: CGFloat(maxX - minX + 1) / 2, height: CGFloat(maxY - minY + 1) / 2)
    }

    /// 그림의 크기 + RGBA 바이트 해시. 실패해도 64글자만 찍히게 해시로 비교한다(CheckMenuRenderTests 의 경고와 같은 이유).
    @MainActor
    static func pixelDigest(_ view: some View) throws -> String {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.cgImage else { throw TooltipRenderError.failed }
        let (bytes, width, height) = try rgba(image)
        let hash = SHA256.hash(data: Data(bytes)).map { String(format: "%02x", $0) }.joined()
        return "\(width)x\(height):\(hash)"
    }

    /// sRGB RGBA8(premultiplied) 버퍼로 옮겨 그린다 — 렌더러의 색 공간과 무관하게 같은 기준으로 읽는다. 0행이 맨 위다.
    static func rgba(_ image: CGImage) throws -> (bytes: [UInt8], width: Int, height: Int) {
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { throw TooltipRenderError.failed }
        let drawn = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { throw TooltipRenderError.failed }
        return (bytes, width, height)
    }

    /// 조건이 설 때까지 메인 액터를 **돌려주며** 기다린다. 상한은 벽시계가 아니라 재개 횟수다 — 관련 스위트를 한 프로세스로
    /// 같이 돌리면 렌더 테스트가 메인 액터를 오래 쥐어(실측: 이 스위트의 센터 테스트가 27초 걸렸다) 3초 벽시계 상한으로는
    /// 센터의 fire Task 가 차례를 받기 전에 포기했다. 재개마다 메인 액터 차례를 거치므로 fire Task 도 같은 줄에서 순서를 받는다.
    @MainActor
    static func waitUntil(maxResumes: Int = 4_000, _ condition: @MainActor () -> Bool) async -> Bool {
        for _ in 0..<maxResumes {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    static func sourcesDirectory() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/check", isDirectory: true)
    }

    /// Sources/check 아래 모든 .swift(하위 폴더 포함)를 **주석을 걷어낸 채** 읽는다. 키는 Sources/check 기준 상대 경로.
    /// 주석 제거는 상점 테스트의 도우미(`V0317ShopTests.stripped`)를 그대로 쓴다 — 공백은 한 칸으로 접힌다.
    static func strippedSources() throws -> [String: String] {
        let root = sourcesDirectory().standardizedFileURL.resolvingSymlinksInPath()
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return [:] }
        var out: [String: String] = [:]
        for case let file as URL in walker where file.pathExtension == "swift" {
            let path = file.standardizedFileURL.resolvingSymlinksInPath().path
            let relative = path.hasPrefix(root.path + "/") ? String(path.dropFirst(root.path.count + 1)) : file.lastPathComponent
            out[relative] = V0317ShopTests.stripped(try String(contentsOf: file, encoding: .utf8))
        }
        return out
    }

    static func count(_ needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }

    /// `start` 첫 등장 뒤부터 그 뒤 `end` 첫 등장 전까지. 둘 중 하나라도 없으면 nil.
    static func between(_ source: String, _ start: String, _ end: String) -> String? {
        guard let from = source.range(of: start),
              let to = source.range(of: end, range: from.upperBound..<source.endIndex)
        else { return nil }
        return String(source[from.upperBound..<to.lowerBound])
    }
}

private enum TooltipRenderError: Error {
    case failed
}

/// 센터 시각 주입용 수동 시계.
@MainActor
private final class ManualTooltipClock {
    var now: TimeInterval = 100
}

/// 결정적 의사난수(SplitMix64) — 무작위 전이 열을 매 실행 같게 재현한다(실패 메시지의 walk·step 으로 되짚을 수 있게).
private struct TooltipWalkRNG {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
