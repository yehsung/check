import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// 아잉 마작 창(SPEC §5.1 · §5.2 · §6.3 U 줄 V03xxMahjongWindowTests — CC-05 · CC-14 · MCL:439).
// 창은 **화면에 올리지 않는다** — `prepareWindow()` 로 만들기만 하고, 닫기·최소화·키 통지는 위임 문을 직접 부른다(orderFront 없음).

@MainActor
@Suite("아잉 마작 창 — 크기 · 레이아웃 산식 · 첫 클릭 · 작은 화면 · 닫기", .serialized)
struct V03xxMahjongWindowTests {
    private func controller(store: MahjongStore = MahjongStore()) -> CheckMahjongWindowController {
        let controller = CheckMahjongWindowController(stuckWindowCheckSeconds: 3_600)
        controller.configure(store: store, content: { _ in AnyView(Color.clear) })
        return controller
    }

    @Test("1240×700 고정 · 제목 = 게임 이름 한 곳 · 크기 조절 없음")
    func fixedSizeAndTitle() throws {
        // 없으면: 창 크기·제목이 두 곳에 적혀 한쪽만 바뀌어도 초록이다.
        #expect(MahjongWindowLayout.contentSize == CGSize(width: 1240, height: 700))
        #expect(CheckMahjongWindowController.windowTitle == "아잉 마작")
        #expect(CheckMahjongWindowController.windowTitle == MahjongNoticeText.gameName)
        let made = CheckMahjongWindowController.makeWindow()
        defer { made.close() }
        #expect(made.contentRect(forFrameRect: made.frame).size == CGSize(width: 1240, height: 700))
        #expect(!made.styleMask.contains(.resizable) && made.styleMask.contains(.closable))
        #expect(made.identifier?.rawValue == "check.mahjong.window")
        #expect(!made.isVisible, "만들기만 했는데 화면에 올라왔다")
    }

    @Test("레이아웃 항등식 — 탁자 덩어리 502·536 · 펠트 안 가운데 · 손 658 ≤ 790 · 위 줄 안 겹침")
    func layoutIdentities() {
        // 없으면: UX §1.3 표의 숫자 하나가 바뀌어 강이 손 칸을 덮거나 펠트 밖으로 나가도 초록이다.
        typealias L = MahjongMatchLayout
        #expect(L.blockHeight == 502 && L.blockHeight == L.felt.height)
        #expect(L.blockWidth == 536 && L.blockOrigin.x == 174 && L.blockOrigin.x * 2 + L.blockWidth == L.felt.width)
        #expect(L.center == CGRect(x: 168, y: 168, width: 200, height: 200))
        #expect(L.river(.bottom).maxY + L.gap == L.blockHeight)
        #expect(L.river(.top).minY == L.handStrip + L.gap && L.river(.left).minX == L.handStrip + L.gap)
        #expect(L.river(.right).maxX + L.gap + L.handStrip == L.blockWidth)
        #expect(L.fullHandWidth == 658 && L.fullHandWidth <= L.hand.width)
        let body = CGRect(origin: .zero, size: L.bodySize)
        let all = [L.info, L.chromeLeft, L.topSeat, L.chromeRight, L.aids, L.leftSeat, L.rightSeat, L.felt, L.mySeat, L.hand, L.actions]
        for (i, a) in all.enumerated() {
            #expect(body.contains(a), "\(a) 가 본문 밖")
            for b in all[(i + 1)...] { #expect(!a.intersects(b), "\(a) 와 \(b) 가 겹친다") }
        }
        #expect(L.bodyOrigin.x + L.bodySize.width + MahjongWindowLayout.contentPadding == MahjongWindowLayout.contentSize.width)
        #expect(MahjongWindowLayout.lobbyListWidth + MahjongWindowLayout.columnSpacing + MahjongWindowLayout.lobbySideWidth
                == MahjongWindowLayout.innerWidth)
    }

    @Test("지연 생성 · 멱등 · autosave 이름이 겹치지 않는다")
    func lazyIdempotentAutosave() throws {
        // 없으면: 앱 시작 때 창이 미리 만들어지거나, 자동저장 이름이 다른 창과 겹쳐 자리 저장이 조용히 죽어도 초록이다.
        let c = controller()
        #expect(!c.hasWindow)
        let first = try #require(c.prepareWindow())
        let second = try #require(c.prepareWindow())
        defer { c.discardWindowForTesting() }
        #expect(first === second)
        #expect(c.frameAutosaveActive, "setFrameAutosaveName 이 false — 이름이 다른 창과 겹친다")
        let others = [CheckReversiWindowController.frameAutosaveName, "check.rummy.window", "check.chess.window",
                      "check.gomoku.window"]
        #expect(!others.contains(CheckMahjongWindowController.frameAutosaveName))
    }

    @Test("첫 클릭을 받는다 — contentView 가 MahjongHostingView(기준선: 보통 NSHostingView 는 거짓)")
    func acceptsFirstMouse() throws {
        // 없으면: 다른 앱을 쓰다 패를 한 번 누르면 그 클릭이 '창 앞으로'에 먹혀 버려지지 않아도 초록이다(CC-05).
        let c = controller()
        let window = try #require(c.prepareWindow())
        defer { c.discardWindowForTesting() }
        let hosting = try #require(window.contentView as? MahjongHostingView<AnyView>)
        #expect(hosting.acceptsFirstMouse(for: nil))
        #expect(!NSHostingView(rootView: EmptyView()).acceptsFirstMouse(for: nil), "기준선이 참이면 이 단언은 뜻이 없다")
    }

    @Test("작은 화면 — 1440×900 배율 1 · 1280×800 배율 < 1 이고 ≥ 0.82 · 1024×640 하한 아래 안내 · 원점은 화면 안")
    func smallScreenScale() {
        // 없으면: 13" 큰 글자·1024×640 에서 손패·ACTIONS(맨 아래·오른쪽)가 화면 밖으로 잘려도 초록이다(CC-14).
        // visibleFrame = 화면 − 메뉴바 25 − 독 70.
        let big = CGSize(width: 1440, height: 900 - 95), mid = CGSize(width: 1280, height: 800 - 95)
        let small = CGSize(width: 1024, height: 640 - 95)
        #expect(MahjongWindowScale.fit(visible: big) == 1 && !MahjongWindowScale.isCramped(visible: big))
        let midScale = MahjongWindowScale.fit(visible: mid)
        #expect(midScale < 1 && midScale >= 0.82 && !MahjongWindowScale.isCramped(visible: mid))
        #expect(MahjongWindowScale.isCramped(visible: small) && MahjongWindowScale.fit(visible: small) == 0.82)
        for screen in [big, mid, small] {
            let visible = NSRect(x: 0, y: 70, width: screen.width, height: screen.height)
            let placed = MahjongWindowScale.placement(frame: NSRect(x: 300, y: 200, width: 1240, height: 728),
                                                      visibleFrames: [visible])
            #expect(placed.frame.minX >= visible.minX && placed.frame.maxY <= visible.maxY, "\(screen): 원점 \(placed.frame)")
            if !placed.cramped {
                #expect(visible.contains(placed.frame), "\(screen): 창 \(placed.frame) 이 화면 \(visible) 밖")
            }
        }
        // 컨트롤러가 창에 입힌다(화면에 올리지 않고).
        let c = controller()
        c.visibleFrames = { [NSRect(x: 0, y: 70, width: mid.width, height: mid.height)] }
        _ = c.prepareWindow()
        defer { c.discardWindowForTesting() }
        c.fitToScreen()
        #expect(c.scaleBox.scale == midScale && !c.scaleBox.cramped)
        let content = c.currentWindow.map { $0.contentRect(forFrameRect: $0.frame).size }
        #expect(content == CGSize(width: (1240 * midScale).rounded(.down), height: (700 * midScale).rounded(.down)))
    }

    @Test("닫기와 최소화 · onClosed 사람/프로그램 가름")
    func closeAndMinimize() throws {
        // 없으면: 최소화가 '닫혔다'로 새거나(미니게임 창 복귀가 최소화에 튄다) 사람 닫기와 프로그램 닫기가 같은 값이어도 초록이다.
        let store = MahjongStore()
        let c = controller(store: store)
        var closes: [Bool] = []
        c.onClosed = { closes.append($0) }
        let window = try #require(c.prepareWindow())
        defer { c.discardWindowForTesting() }
        c.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification, object: window))
        c.windowDidDeminiaturize(Notification(name: NSWindow.didDeminiaturizeNotification, object: window))
        #expect(store.isWindowVisible)
        c.windowDidMiniaturize(Notification(name: NSWindow.didMiniaturizeNotification, object: window))
        #expect(c.closedNoticeCount == 0 && closes.isEmpty, "최소화가 닫기로 셌다")
        #expect(!store.isWindowVisible, "최소화했는데 스토어가 보인다고 안다(폴링이 계속 돈다)")
        c.windowDidDeminiaturize(Notification(name: NSWindow.didDeminiaturizeNotification, object: window))
        #expect(store.isWindowVisible)
        c.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: window))
        #expect(closes == [true] && c.closedNoticeCount == 1)
        #expect(!store.isWindowVisible)
        c.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification, object: window))
        c.close()
        #expect(closes == [true, false], "프로그램 닫기가 사람 닫기로 왔다: \(closes)")
        // 열려 있지 않은 창을 다시 닫아도 통지는 늘지 않는다.
        c.close()
        #expect(closes.count == 2)
    }

    @Test(.gomokuDefaultsCleanup)
    func closingTheWindowSendsNoWriteRPC() async throws {
        // 없으면: 창 닫기가 기권·나가기 RPC 를 보내도 초록이다(큐브와 반대 — 닫아도 판은 계속, MCL:439).
        let host = "v03xx-mj-window-\(UUID().uuidString.prefix(8))".lowercased()
        GomokuStubProtocol.register(host: host) { _, _, _ in nil }
        let service = SupabaseWorkService(projectURL: URL(string: "http://\(host)")!, anonKey: "anon-test-key",
                                          session: GomokuStubProtocol.session())
        let owner = WorkTimerStore(service: service, environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
                                   defaults: GomokuTestDefaults.make("v03xx-mahjong-window"), workspaceNotifications: nil)
        owner.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: mjWindowMe)
        MJWindowRetention.owners.append(owner)
        let store = MahjongStore()
        store.attach(host: owner)
        let c = controller(store: store)
        let window = try #require(c.prepareWindow())
        defer { c.discardWindowForTesting() }
        c.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification, object: window))
        c.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: window))
        c.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification, object: window))
        c.close()
        for _ in 0..<20 { await Task.yield() }
        let writes = GomokuStubProtocol.calls(host: host).map(\.rpc).filter {
            $0.hasPrefix("mahjong_") && !["mahjong_state", "mahjong_lobby", "mahjong_ranking"].contains($0)
        }
        #expect(writes.isEmpty, "창 닫기가 쓰기 RPC 를 보냈다: \(writes)")
    }
}

private let mjWindowMe = "aaaaaaaa-0000-4000-8000-000000000001"

@MainActor
private enum MJWindowRetention {
    /// 스토어는 host 를 약참조로 든다 — 시험이 버리면 곧바로 해제되어 요청이 한 건도 안 나간다.
    static var owners: [WorkTimerStore] = []
}
