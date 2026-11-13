import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// 1:1 알까기 v2 — **공용 접점 배선**(alkkagi/v2 SPEC v1.1 §6 체크리스트 #1~#10 · §7.2 T `V03xxAlkkagiWiringTests`).
// 스토어·창은 다른 갈래(C·U)가 채웠다. 여기서는 "그 문이 공용 파일에 꽂혀 있는가"를 소스 계약(주석 걷기 → 공백 접기 → 글자 그대로)으로
// 재고, 소스 계약이 모양만 잰다는 한계를 메우려고 **부르는 자리의 결과**를 같이 잰다 — 실제 `WorkTimerStore` 의 메뉴바 점 사유 · 팝오버
// 배너 · 사이드바 점 · 확성기 미룸 · 링 · 팝오버 열기의 가벼운 로비 · 판 끝 업적 조회 · 말풍선 큐와 사실 판정 · 배너 [수락] 뒤 창.
// 결과 단언마다 **값 하나만 바꾼 기준선**을 함께 둔다. 알까기 줄은 모두 길건너 줄 **뒤**다(SPEC §6 — 자리 · 순서는 그대로).
//
// 각 시험의 첫 줄 주석은 **"없으면 어떤 결함이 초록으로 통과하는가"** 다(관례). 출시 뒤에도 V03xx 이름 그대로(SPEC §1).

private let akwT0 = Date(timeIntervalSince1970: 1_800_000_000)
private let akwMe = "0a1b0000-0000-4000-8000-0000000000aa"
private let akwRival = AlkkagiPeer(id: "0a1b0000-0000-4000-8000-0000000000b1", displayName: "민수", characterID: "fox")

private func akwSubscribedLink() -> RealtimeLink {
    var link = RealtimeLink(transportAvailable: true)
    _ = link.apply(.signedIn(accessToken: "tok"), now: akwT0, jitter: { $0 })
    _ = link.apply(.transport(.joined), now: akwT0, jitter: { $0 })
    return link
}

private func akwCollapsed(_ source: String) -> String {
    source.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
}

private func akwCount(_ needle: String, in source: String) -> Int {
    source.components(separatedBy: needle).count - 1
}

/// Sources/check(+CheckCore) 파일을 주석 걷고 공백 접어 읽는다.
private func akwMac(_ name: String) throws -> String {
    akwCollapsed(V0317ShopTests.stripped(try V0317ShopTests.source(name)))
}

private func akwPhoneRunner() throws -> String {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/CheckMobileKit/Realtime/MobileRealtimeRunner.swift")
    return akwCollapsed(V0317ShopTests.stripped(try String(contentsOf: url, encoding: .utf8)))
}

private func akwBetween(_ source: String, _ start: String, _ end: String) -> String? {
    guard let head = source.range(of: start),
          let tail = source.range(of: end, range: head.upperBound..<source.endIndex) else { return nil }
    return String(source[head.lowerBound..<tail.lowerBound])
}

@MainActor
private func akwDefaults(_ name: String) -> UserDefaults {
    let path = CheckTestScratch.suitePath(named: name)
    let defaults = UserDefaults(suiteName: path)!
    defaults.removePersistentDomain(forName: path)
    return defaults
}

@MainActor
private func akwStore(_ name: String) -> WorkTimerStore {
    WorkTimerStore(environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"], defaults: akwDefaults(name),
                   workspaceNotifications: nil)
}

private func akwInvite(_ id: String, stake: Int? = 5, expiresIn seconds: TimeInterval = 50) -> AlkkagiInvite {
    AlkkagiInvite(id: id, opponent: akwRival, expiresAtMs: (Date().timeIntervalSince1970 + seconds) * 1_000, stake: stake)
}

/// 내가 흑인 판 하나(돌 없음 — 사실 판정은 단계 · 차례만 읽는다).
private func akwMatch(_ id: String, phase: AlkkagiMatchPhase, current: AlkkagiGame.Player = .black) -> AlkkagiMatch {
    AlkkagiMatch(id: id, revision: 3, phase: phase, currentPlayer: current, myColor: .black,
                 black: AlkkagiPeer(id: akwMe, displayName: "나"), white: akwRival, stones: [], stake: 5)
}

/// 팝오버 높이를 재는 스토어. `teamless` 면 무소속 화면(헤더 카드 없이 배너가 맨 위에 선다).
@MainActor
private func akwMenuStore(teamless: Bool) -> WorkTimerStore {
    let store = akwStore(teamless ? "v03xx-alkkagi-wiring-menu-teamless" : "v03xx-alkkagi-wiring-menu")
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: akwMe)
    if !teamless {
        store.currentTeamID = "11111111-1111-1111-1111-111111111111"
        store.teamName = "아잉팀"
        store.teamMembers = (0..<3).map { index in
            TeamMemberStatus(id: "00000000-0000-0000-0000-0000000000d\(index)", name: "멤버\(index)", status: .offWork,
                             updatedAt: nil, currentSessionStartedAt: nil, weeklyDurationSeconds: 3_600)
        }
    }
    store.isMenuPresented = true
    return store
}

@MainActor
private func akwOverlay() -> (ReactionEngine, CheckOverlayController, WorkTimerStore) {
    let store = akwStore("v03xx-alkkagi-wiring-overlay")
    let engine = ReactionEngine(clock: { Date(timeIntervalSince1970: 900_000) })
    let controller = CheckOverlayController(
        store: store, notificationCenter: NotificationCenter(), engine: engine,
        defaults: akwDefaults("v03xx-alkkagi-wiring-overlay"), workspaceNotifications: nil)
    return (engine, controller, store)
}

private enum AKWError: Error { case render }

@MainActor
private func akwBitmap(_ view: some View) throws -> NSBitmapImageRep {
    guard let bitmap = CheckRenderSettle.bitmap(view.fixedSize(), scale: 2) else { throw AKWError.render }
    return bitmap
}

/// 스텁 서버에 붙은 실제 `WorkTimerStore`(알까기 스토어는 소유자의 공용 `duelRPC` 로 부른다 — 운영 어댑터 그대로).
@MainActor
private func akwStubbedStore(_ name: String, host: String) -> WorkTimerStore {
    let service = SupabaseWorkService(projectURL: URL(string: "http://\(host)")!, anonKey: "anon-test-key",
                                      session: GomokuStubProtocol.session())
    let store = WorkTimerStore(service: service, environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
                               defaults: akwDefaults(name), workspaceNotifications: nil)
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: akwMe)
    return store
}

@MainActor
@Suite(.serialized)
struct V03xxAlkkagiWiringTests {
    // MARK: #10 링 · 폰 러너(그대로)

    /// 없으면: 'alkkagi' 초인종이 '모르는 이름'(drain = take_pokes)으로 떨어져 신청 · 수락 · 판 진행을 맥이 한 번도 당기지 않는다
    /// (스토어 시험은 초인종을 직접 부르므로 초록이다). 서버 이벤트 글자와 갈리면 같은 결함이다(그 짝은 MigrationContract).
    @Test
    func theAlkkagiRingIsItsOwnBranchAndNotATakePokesDrain() throws {
        #expect(RealtimeLinkConstants.alkkagiBroadcastEvent == "alkkagi")
        var link = akwSubscribedLink()
        #expect(link.apply(.transport(.broadcast(event: "alkkagi")), now: akwT0 + 1, jitter: { $0 }) == [.alkkagiSignal])
        // ★ 기준선이 갈린다: 문자 그대로만 가른다 — 대문자 · 다른 이름은 모르는 이름이라 drain 이다.
        #expect(link.apply(.transport(.broadcast(event: "ALKKAGI")), now: akwT0 + 2, jitter: { $0 }) == [.drain])
        #expect(link.apply(.transport(.broadcast(event: "alkkagi_v2")), now: akwT0 + 3, jitter: { $0 }) == [.drain])
        #expect(link.apply(.transport(.broadcast(event: "crossy_duel")), now: akwT0 + 4, jitter: { $0 }) == [.crossyDuelSignal])
        let realtime = try akwMac("WorkTimerStoreRealtime.swift")
        #expect(realtime.contains("case .alkkagiSignal: alkkagi.handleSignal()"), "신호 가지가 없다 — 초인종마다 take_pokes 가 샌다")
        #expect(realtime.contains("alkkagi.realtimeDidJoin()") && realtime.contains("alkkagi.systemDidWake()"))
        // 폰 1.0.18 부터 알까기가 있다 — 러너 가지는 폰 스토어를 잇는다(맥과 같은 재조회 한 번 · 조인 따라잡기).
        let runner = try akwPhoneRunner()
        #expect(akwCount("case .alkkagiSignal", in: runner) == 1, "폰 러너에 알까기 가지가 하나가 아니다")
        #expect(runner.contains("alkkagi?.handleSignal()") && runner.contains("alkkagi?.realtimeDidJoin()"),
                "폰 러너의 알까기 가지가 스토어를 잇지 않는다 — 신청 · 차례가 다음 계기까지 안 선다")
    }

    // MARK: #7 맥 소유 배선

    /// 없으면: 소유자가 `reset()` 을 빠뜨리면 다음 사람이 앞 계정의 판·신청을 보고, 차단 거울을 빠뜨리면 차단한 사람의 신청이 남고,
    /// 결과 계기를 빠뜨리면 일일 미션 줄(daily_alkkagi)이 안 오른다 — 스토어 시험은 전부 초록이다.
    @Test
    func theMacOwnerWiresTheAlkkagiStoreAfterCrossyDuel() throws {
        let owner = try akwMac("WorkTimerStore.swift")
        #expect(akwCount("alkkagi.reset()", in: owner) == 2, "로그아웃·계정 전환 두 길에서 모두 내려야 한다")
        #expect(owner.contains("if crossyDuel.hiddenPeerIDs != blockHiddenPeerIDs { crossyDuel.hiddenPeerIDs = blockHiddenPeerIDs } "
                                + "if alkkagi.hiddenPeerIDs != blockHiddenPeerIDs { alkkagi.hiddenPeerIDs = blockHiddenPeerIDs }"), "차단 거울")
        #expect(owner.contains("crossyDuel.refreshLobbyIfStale() alkkagi.refreshLobbyIfStale()"))
        #expect(owner.contains(
            "alkkagi.onMatchFinished = { [weak self] in self?.refreshAchievementsAfterGameResult(game: \"alkkagi\") }"))
        #expect(owner.contains("alkkagi.attach(host: self)"))
        // 게임 이름이 일일 미션 키의 꼬리다(서버 `daily_alkkagi` — SPEC §1).
        #expect(DailyMissionStatus.key(game: "alkkagi") == "daily_alkkagi")
    }

    /// 없으면(결과): 소스에 줄이 있어도 엉뚱한 칸을 비추면 차단한 사람의 신청이 배너·말풍선·점에 남는다. 실제 `WorkTimerStore` 에서
    /// 차단을 바꿔 알까기 스토어가 따라가는지 · 호스트 · 결과 계기가 물렸는지 잰다.
    @Test
    func theRealOwnerMirrorsBlocksAndAttachesItself() {
        let store = akwStore("v03xx-alkkagi-wiring-owner")
        #expect(store.alkkagi.host as AnyObject? === store, "소유자가 자신을 호스트로 넘기지 않았다")
        #expect(store.alkkagi.onMatchFinished != nil)
        // ★ 기준선: 차단 전에는 비어 있고 받은 신청이 보인다.
        store.alkkagi.incoming = [akwInvite("a-1")]
        #expect(store.alkkagi.hiddenPeerIDs.isEmpty && store.alkkagi.visibleIncoming?.id == "a-1")
        store.blockHiddenPeerIDs = [akwRival.id]
        #expect(store.alkkagi.hiddenPeerIDs == [akwRival.id], "차단 거울이 1:1 알까기 스토어에 닿지 않는다")
        #expect(store.alkkagi.visibleIncoming == nil, "차단한 사람의 신청이 보인다")
        // 알까기 스토어는 차단한 사람의 신청을 목록에서 **걷는다**(필터가 아니라 지움 — 코어 갈래 규약). 차단을 풀면 다음 로비가 다시 싣는다.
        #expect(store.alkkagi.incoming.isEmpty, "차단한 사람의 신청이 스토어 목록에 남았다")
        store.blockHiddenPeerIDs = []
        #expect(store.alkkagi.hiddenPeerIDs.isEmpty)
        store.alkkagi.incoming = [akwInvite("a-1")]
        #expect(store.alkkagi.visibleIncoming?.id == "a-1")
        store.alkkagi.incoming = []
    }

    // MARK: #1 CheckApp

    /// 없으면: 스토어 쪽 문이 옵셔널이라 `?.` 가 삼켜 **말풍선이 안 오고**(onInviteArrived · onAttention), 순위 · 관전이 영영 안 서고
    /// (스위치 기본 꺼짐), 말풍선을 눌러도 창이 안 열리고, 로그아웃해도 말풍선 큐가 남는다. 컴파일·스토어 시험은 초록이다.
    @Test
    func theAppWiresEveryAlkkagiDoor() throws {
        let app = try akwMac("CheckApp.swift")
        #expect(app.contains("wireReversi() wireMahjong() wireCrossyDuel() wireAlkkagi() wireMegaphoneBanner()"),
                "wireAlkkagi() 가 길건너 뒤·확성기 앞이 아니다")
        let body = try #require(akwBetween(app, "private func wireAlkkagi() {", "static func closeRummyWindow() {"))
        for line in [
            "let alkkagi = store.alkkagi alkkagi.rankingEnabled = true alkkagi.spectatorFeaturesEnabled = true",
            "CheckAlkkagiWindowController.shared.configure(store: alkkagi, safety: store)",
            "alkkagi.presentWindow = { CheckAlkkagiWindowController.shared.show() }",
            "alkkagi.dismissWindow = { CheckAlkkagiWindowController.shared.close() }",
            "CheckAlkkagiWindowController.shared.onClosed = { [weak self] byUser in self?.store.duelWindowDidClose(.alkkagi, byUser: byUser) }",
            "alkkagi.requestAttention = { if !NSApp.isActive { NSApp.requestUserAttention(.criticalRequest) } }",
            "alkkagi.onInviteArrived = { [weak self] invite in self?.overlayController?.enqueueAlkkagiInvite(invite) }",
            "alkkagi.onAttention = { [weak self] attention in self?.overlayController?.enqueueAlkkagiAttention(attention) }",
            "overlayController?.onOpenAlkkagi = { [weak self] matchID in self?.store.alkkagi.openWindow(focusMatchID: matchID) }",
            "CheckAlkkagiWindowController.shared.close() self?.overlayController?.clearAlkkagiInvites() }.start()",
        ] {
            #expect(body.contains(line), "wireAlkkagi 에 없다: \(line)")
        }
        // 닫힘 알림은 창 컨트롤러가 스토어에 직접 알린다 — 배선이 또 부르면 한 번 닫기에 두 번 접는다. App Nap 붙들기는 없다(차례제 다수).
        #expect(!body.contains("windowDidClose()") && !body.contains("ActivityHold"))
        // ★ 기준선: 같은 읽기가 이웃(길건너) 배선의 같은 줄을 알아본다.
        #expect(app.contains("crossyDuel.onInviteArrived = { [weak self] invite in self?.overlayController?.enqueueCrossyDuelInvite(invite) }"))
    }

    // MARK: #3 메뉴바 점(짝 게이트)

    /// 없으면: 세 자리(앱 인자 · 라벨 칸 · dotReasons) 중 하나만 빠지거나 `incoming` 을 그대로 읽어 차단 · 내 판 신청에도 점이 켜져도
    /// 초록이다. 결과로 잰다 — 실제 `WorkTimerStore` 에 신청을 넣고 앱과 **같은 식**으로 라벨을 세워 사유가 나오는지.
    @Test
    func theMenuBarDotLightsForARealAlkkagiInvite() throws {
        let app = try akwMac("CheckApp.swift")
        #expect(app.contains("hasCrossyDuelInvite: appDelegate.store.crossyDuel.visibleIncoming != nil, "
                                + "hasAlkkagiInvite: appDelegate.store.alkkagi.visibleIncoming != nil"),
                "메뉴바 라벨이 1:1 알까기 신청을 스토어가 걷은 목록(visibleIncoming)으로 안 읽는다")
        let menu = try akwMac("CheckMenuView.swift")
        #expect(menu.contains("crossyDuelInvite: hasCrossyDuelInvite, alkkagiInvite: hasAlkkagiInvite"))

        let store = akwStore("v03xx-alkkagi-wiring-dot")
        let off = WorkStatusSnapshot(status: .offWork, elapsedSeconds: 0)
        func label() -> MenuBarStatusLabel {
            MenuBarStatusLabel(snapshot: off, title: "오프", hasAlkkagiInvite: store.alkkagi.visibleIncoming != nil)
        }
        // ★ 기준선: 신청이 없으면 점이 없다.
        #expect(label().dotReasons.isEmpty)
        store.alkkagi.incoming = [akwInvite("a-dot")]
        #expect(label().dotReasons == MenuBarDotReasons(alkkagiInvite: true))
        #expect(label().dotReasons.accessibilityDescription == "1:1 알까기 신청")
        #expect(AlkkagiText.dotReason == "1:1 알까기 신청" && MenuBarDotReasons.alkkagiInviteText == AlkkagiText.dotReason)
        // 차단한 사람의 신청은 점을 내린다(앱 소유자의 차단 거울을 지나 스토어까지).
        store.blockHiddenPeerIDs = [akwRival.id]
        #expect(label().dotReasons.isEmpty, "차단한 사람의 1:1 알까기 신청에 점이 남았다")
        store.blockHiddenPeerIDs = []
        store.alkkagi.incoming = [akwInvite("a-dot")]                     // 차단은 목록에서 걷는다 — 다시 싣는다
        #expect(label().dotReasons == MenuBarDotReasons(alkkagiInvite: true), "기준선: 차단을 풀고 다시 온 신청에 점이 선다")
        // 내 판이 된 신청(같은 id)은 점을 내린다 — `incoming` 을 그대로 읽으면 여기서 빨갛다.
        store.alkkagi.state = akwMatch("a-dot", phase: .placing)
        #expect(label().dotReasons.isEmpty, "판이 된 신청에 점이 남았다")
        store.alkkagi.state = nil
        store.alkkagi.incoming = []
        // 말하는 순서: 길건너 뒤.
        #expect(MenuBarDotReasons(crossyDuelInvite: true, alkkagiInvite: true).accessibilityDescription
                    == "\(CrossyDuelText.dotReason) · \(AlkkagiText.dotReason)")
    }

    // MARK: #3 팝오버 배너(두 자리) · [수락]

    /// 없으면: 팝오버에 신청 배너가 안 서거나(우선순위 줄 누락) 높이 예산에서 빠져 팝오버가 잘리고, 무소속 자리를 빠뜨리면 팀 없는
    /// 사람은 배너를 못 본다. `incoming.first` 를 읽으면 차단 · 내 판 신청이 배너에 남는다.
    @Test
    func thePopoverShowsTheAlkkagiInviteBannerInBothSpots() throws {
        let menu = try akwMac("CheckMenuView.swift")
        #expect(menu.contains("if store.isSignedIn, crossyDuelBannerInvite != nil { return .crossyDuelInvite } "
                                + "if store.isSignedIn, alkkagiBannerInvite != nil { return .alkkagiInvite }"))
        #expect(menu.contains("case crossyDuelInvite case alkkagiInvite"))
        #expect(menu.contains("case .alkkagiInvite: return Self.alkkagiInviteBannerHeight"))
        #expect(CheckMenuView.alkkagiInviteBannerHeight == 92)
        #expect(menu.contains("previewAlkkagiInvite ?? store.alkkagi.visibleIncoming"))
        #expect(!menu.contains("store.alkkagi.incoming.first"), "배너가 스토어가 걷기 전 목록을 읽는다")
        #expect(akwCount("crossyDuelInviteBanner alkkagiInviteBanner", in: menu) == 2, "두 자리(무소속 · 머리 카드 아래) 모두 길건너 배너 뒤가 아니다")

        for teamless in [false, true] {
            let store = akwMenuStore(teamless: teamless)
            store.alkkagi.incoming = []
            let without = try akwBitmap(CheckMenuView(store: store))
            store.alkkagi.incoming = [akwInvite("a-banner", expiresIn: 48)]
            let with = try akwBitmap(CheckMenuView(store: store))
            let grew = Double(with.pixelsHigh - without.pixelsHigh) / 2
            print("[배너] 1:1 알까기 배너(\(teamless ? "무소속" : "팀")) 높이 \(grew)pt (예산 \(CheckMenuView.alkkagiInviteBannerHeight)pt)")
            #expect(with.pixelsHigh > without.pixelsHigh, "\(teamless ? "무소속" : "팀") 화면에 1:1 알까기 배너가 안 그려진다")
            #expect(abs(grew - Double(CheckMenuView.alkkagiInviteBannerHeight)) < 24,
                    "배너 높이 예산(\(CheckMenuView.alkkagiInviteBannerHeight)pt)과 실제(\(grew)pt)가 크게 다르다")
            // ★ 기준선: 차단한 사람의 신청이면 배너가 없다(같은 높이).
            store.blockHiddenPeerIDs = [akwRival.id]
            let hidden = try akwBitmap(CheckMenuView(store: store))
            #expect(hidden.pixelsHigh == without.pixelsHigh, "차단한 사람의 신청 배너가 그려졌다")
            store.blockHiddenPeerIDs = []
            store.alkkagi.incoming = []
        }
    }

    /// 없으면: [수락]이 respond 결과가 **성공일 때만** 창을 열어(다섯 게임과 다르게) 모자람 · 만료로 실패한 사람이 까닭을 못 보거나,
    /// 알까기만 있던 앞 가드(`!isBusy`)가 남아 눌러도 아무 일이 없다. 소스는 다섯 게임과 같은 세 줄 · 결과는 실패 응답 뒤 창 열기 1회.
    @Test(.gomokuDefaultsCleanup)
    func acceptingFromTheBannerOpensTheWindowEvenWhenRespondFails() async throws {
        let menu = try akwMac("CheckMenuView.swift")
        let accept = try #require(akwBetween(menu, "private func acceptAlkkagiInvite(_ invite: AlkkagiInvite) {",
                                             "private func declineAlkkagiInvite("))
        #expect(accept.contains("let alkkagi = store.alkkagi Task { @MainActor in await alkkagi.respond(inviteID: invite.id, accept: true) "
                                    + "alkkagi.openWindow(focusMatchID: invite.id) WindowTopAnchor.dismissMenuPopover() } }"),
                "[수락] 이 다섯 게임과 같은 세 줄이 아니다: \(accept)")
        #expect(!accept.contains("guard") && !accept.contains("if "), "[수락] 에 결과 · 바쁨 가드가 섰다(VC-4 — 다섯 게임 5/5 는 없다)")
        // ★ 기준선: 길건너 [수락] 도 같은 세 줄이다(다섯 게임 꼴).
        #expect(menu.contains("await crossyDuel.respond(inviteID: invite.id, accept: true) crossyDuel.openWindow(focusMatchID: invite.id) "
                                + "WindowTopAnchor.dismissMenuPopover()"))

        // 결과: 실제 소유자 · 운영 어댑터에서 respond 가 모자람(insufficient) · 만료(expired)로 끝나도 같은 순서로 창이 뜬다.
        for status in ["insufficient", "expired"] {
            let host = "akw-accept-\(status)-\(UUID().uuidString.prefix(6))".lowercased()
            let lobby = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .appendingPathComponent("Fixtures/alkkagi-rpc/alkkagi_lobby__ok.json"), encoding: .utf8)
            let reply = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .appendingPathComponent("Fixtures/alkkagi-rpc/alkkagi_respond__\(status == "insufficient" ? "insufficient_me" : "expired").json"),
                                   encoding: .utf8)
            GomokuStubProtocol.register(host: host) { rpc, _, _ in
                switch rpc {
                case "alkkagi_lobby": return .init(body: lobby)
                case "alkkagi_respond": return .init(body: reply)
                default: return nil
                }
            }
            let store = akwStubbedStore("v03xx-alkkagi-wiring-accept-\(status)", host: host)
            let alkkagi = store.alkkagi
            await alkkagi.refreshLobby()
            let invite = try #require(alkkagi.visibleIncoming, "원문 로비의 받은 신청이 안 섰다")
            var opened = 0
            alkkagi.presentWindow = { opened += 1 }
            defer { alkkagi.presentWindow = nil; alkkagi.reset() }
            // 앱의 [수락] 과 같은 순서(소스 계약이 위에서 잰 세 줄).
            await alkkagi.respond(inviteID: invite.id, accept: true)
            #expect(GomokuStubProtocol.count(host: host, rpc: "alkkagi_respond") == 1, "\(status): 수락이 서버에 안 나갔다")
            #expect(alkkagi.state == nil, "\(status): 실패한 수락에 판이 섰다")
            alkkagi.openWindow(focusMatchID: invite.id)
            #expect(opened == 1, "\(status): 실패한 수락 뒤 창을 안 열었다 — 까닭(안내 줄)을 볼 곳이 없다")
            #expect(alkkagi.notice != nil, "\(status): 창 안내 줄이 비었다")
        }
    }

    // MARK: #2 캐릭터 말풍선

    /// 없으면: 창을 닫아 둔 사람은 신청도 "대결이 시작됐어요"도 "내 차례"도 모른다 — 한 수 30초를 세 번 넘겨 판돈을 잃는다.
    /// 몸체 히트테스트가 말풍선을 놓치면 클릭이 뒤 앱으로 새고, 클릭 자리가 없으면 눌러도 창이 안 열린다.
    @Test
    func theOverlayCarriesAlkkagiBubblesInTheCrossyDuelShape() throws {
        let raw = try CheckCoreSourceLayout.joinedSplitSource("CheckOverlayWindow.swift")
        #expect(raw.contains("// MARK: - 1:1 알까기 말풍선"))
        let overlay = akwCollapsed(V0317ShopTests.stripped(raw))
        #expect(overlay.contains("if let rect = crossyDuelInviteBubbleScreenRect(), rect.contains(screenPoint) { return true } "
                                    + "if let rect = alkkagiInviteBubbleScreenRect(), rect.contains(screenPoint) { return true }"),
                "몸체 히트테스트가 1:1 알까기 말풍선을 모른다")
        #expect(overlay.contains("if let rect = alkkagiInviteBubbleScreenRect(), rect.contains(location), "
                                    + "let matchID = alkkagiBubbleMatchID() { onOpenAlkkagi?(matchID) return }"), "말풍선을 눌러도 창이 안 열린다")
        // 살아 있는 신청 거르기는 **테트리스형**(목록 전체) — 체스형(첫 건 한 칸)을 베끼면 둘째 신청부터 큐에서 조용히 지워진다.
        #expect(overlay.contains("let alive = Set(store.alkkagi.visibleIncomingInvites.map(\\.id))"))
        #expect(!overlay.contains("store.alkkagi.visibleIncoming?.id"), "체스형(첫 건 한 칸) 거르기가 섞였다")
        // 문구 글자는 맥 문구 집 한 곳(`AlkkagiText`)에서 받는다 — 판돈은 "루비 N", 💎 0(VC-7).
        #expect(overlay.contains("AlkkagiText.inviteBubbleText(name: invite.opponent.displayName, stake: invite.stake)"))
        let long = AlkkagiText.inviteBubbleText(name: String(repeating: "가", count: 40), stake: 10)
        #expect(OverlayMessageBubble.fitsCapsule(long), "긴 이름에서 말풍선 문구가 캡슐을 넘친다: \(long)")
        #expect(long.hasSuffix("루비 10") && long.contains("1:1 알까기") && !long.contains("💎"))
        let short = AlkkagiText.inviteBubbleText(name: "민수", stake: 3)
        #expect(short.hasPrefix("민수님") && short.hasSuffix(" · 루비 3") && short.contains("1:1 알까기") && !short.contains("💎"),
                "짧은 이름 말풍선: \(short)")
        #expect(OverlayMessageBubble.fitsCapsule(short))
        for kind in [AlkkagiAttention.Kind.matchStarted, .myTurn] {
            let text = CheckOverlayController.alkkagiAttentionBubbleText(AlkkagiAttention(kind: kind, matchID: "m", opponentName: "민수"))
            #expect(!text.contains("💎") && OverlayMessageBubble.fitsCapsule(text))
        }
    }

    /// 없으면(결과): 체스형 거르기를 베끼면 **둘째 신청부터** 큐에서 조용히 지워지고, 처리된 신청이 뒤늦게 뜬다.
    @Test
    func twoLiveInvitesBothReachTheCharacter() throws {
        let (engine, controller, store) = akwOverlay()
        defer {
            controller.clearAlkkagiInvites()
            controller.updateWorking(false)
        }
        let first = akwInvite("invite-1"), second = akwInvite("invite-2", stake: 10)
        store.alkkagi.incoming = [first, second]
        controller.enqueueAlkkagiInvite(first)
        controller.enqueueAlkkagiInvite(first)
        controller.enqueueAlkkagiInvite(second)
        #expect(controller.alkkagiInviteQueue.map(\.id) == ["invite-1", "invite-2"], "같은 신청이 두 번 들어갔다")
        #expect(controller.showNextAlkkagiInviteBubble())
        #expect(engine.greetingText == AlkkagiText.inviteBubbleText(name: "민수", stake: 5))
        #expect(engine.greetingText?.contains("루비 5") == true)
        // ★ 둘째 신청이 큐에 **남아 있다**(체스형이면 여기서 지워진다 — 결과가 갈리는 자리).
        #expect(controller.alkkagiInviteQueue.map(\.id) == ["invite-2"], "살아 있는 둘째 신청이 큐에서 지워졌다")
        #expect(controller.alkkagiInviteBubbleScreenRect() == nil, "배선 전인데 클릭 자리가 생겼다")
        controller.onOpenAlkkagi = { _ in }
        #expect(controller.alkkagiBubbleMatchID() == "invite-1", "말풍선을 눌러도 그 신청의 창을 열 수 없다")
        engine.greetingText = nil
        // 처리된(스토어에서 사라진) 신청은 뒤늦게 뜨지 않는다 — 기준선: 위와 같은 큐인데 스토어 목록만 비었다.
        store.alkkagi.incoming = []
        controller.enqueueAlkkagiInvite(akwInvite("handled"))
        #expect(controller.showNextAlkkagiInviteBubble() == false)
        #expect(controller.alkkagiInviteQueue.isEmpty, "이미 처리된 신청이 뒤늦게 말풍선으로 뜬다")
        // 시간이 지난 신청도 뜨지 않는다(스토어 타이머가 걷기 전의 틈).
        store.alkkagi.incoming = [akwInvite("late", expiresIn: -1)]
        controller.enqueueAlkkagiInvite(akwInvite("late", expiresIn: -1))
        #expect(controller.showNextAlkkagiInviteBubble() == false && controller.alkkagiInviteQueue.isEmpty)
        store.alkkagi.incoming = []
    }

    /// 없으면(결과): 창이 보이는데도 시작 · 차례 말풍선이 겹쳐 뜨거나(규칙 ①), 열린 채 가려진 창에서는 말을 못 하거나, 끝난 판 · 다른 판 ·
    /// 이미 쏜 뒤(상대 차례)의 "내 차례" 가 뜬다. 차례가 넘어온 **원인**(상대 시간 넘김 · 배치 끝)은 묻지 않는다(VC-20).
    @Test
    func theAttentionBubblesOnlyShowTheCurrentHiddenMatch() throws {
        let (engine, controller, store) = akwOverlay()
        defer {
            controller.clearAlkkagiInvites()
            controller.updateWorking(false)
        }
        let alkkagi = store.alkkagi
        let matchID = "7a7a0000-0000-4000-8000-0000000000c1"
        alkkagi.state = akwMatch(matchID, phase: .placing)
        alkkagi.isWindowVisible = false
        let started = AlkkagiAttention(kind: .matchStarted, matchID: matchID, opponentName: "민수")
        #expect(CheckOverlayController.alkkagiAttentionIsCurrent(started, in: alkkagi))
        // ★ 기준선 — 값 하나씩만 바꿨다.
        let other = AlkkagiAttention(kind: .matchStarted, matchID: "other", opponentName: "민수")
        #expect(!CheckOverlayController.alkkagiAttentionIsCurrent(other, in: alkkagi), "다른 판의 알림을 띄운다")
        alkkagi.isWindowVisible = true
        #expect(!CheckOverlayController.alkkagiAttentionIsCurrent(started, in: alkkagi), "창이 보이는데 말풍선을 띄운다")
        alkkagi.isWindowOccluded = true
        #expect(CheckOverlayController.alkkagiAttentionIsCurrent(started, in: alkkagi), "가려진 창인데 시작 말풍선을 버린다")
        alkkagi.isWindowOccluded = false
        alkkagi.isWindowVisible = false

        // 내 차례: 조준 · 내 차례일 때만 사실이다(배치 중 · 상대 차례 · 끝난 판은 거짓).
        let myTurn = AlkkagiAttention(kind: .myTurn, matchID: matchID, opponentName: "")
        #expect(!CheckOverlayController.alkkagiAttentionIsCurrent(myTurn, in: alkkagi), "배치 중인데 내 차례 말풍선을 띄운다")
        alkkagi.state = akwMatch(matchID, phase: .aiming, current: .black)
        #expect(CheckOverlayController.alkkagiAttentionIsCurrent(myTurn, in: alkkagi), "조준 · 내 차례인데 말풍선을 버린다")
        alkkagi.state = akwMatch(matchID, phase: .aiming, current: .white)
        #expect(!CheckOverlayController.alkkagiAttentionIsCurrent(myTurn, in: alkkagi), "상대 차례인데 내 차례 말풍선을 띄운다")
        alkkagi.state = akwMatch(matchID, phase: .finished)
        #expect(!CheckOverlayController.alkkagiAttentionIsCurrent(started, in: alkkagi), "끝난 판인데 시작 말풍선을 띄운다")
        alkkagi.state = akwMatch(matchID, phase: .aiming, current: .black)

        // 문구: 상대가 쏴서 넘어왔을 때만 이름이 실린다(스토어가 그 밖은 빈 이름으로 보낸다).
        #expect(CheckOverlayController.alkkagiAttentionBubbleText(myTurn) == "알까기 내 차례예요")
        let shot = AlkkagiAttention(kind: .myTurn, matchID: matchID, opponentName: "민수")
        #expect(CheckOverlayController.alkkagiAttentionBubbleText(shot) == "민수님이 쐈어요 · 알까기 내 차례예요")
        #expect(CheckOverlayController.alkkagiAttentionBubbleText(started) == "민수님과 1:1 알까기 대결이 시작됐어요")

        controller.enqueueAlkkagiAttention(myTurn)
        #expect(controller.showPendingAlkkagiAttentionBubble())
        #expect(engine.greetingText == "알까기 내 차례예요")
        controller.onOpenAlkkagi = { _ in }
        #expect(controller.alkkagiBubbleMatchID() == matchID, "차례 말풍선을 눌러도 그 판을 열 수 없다")
        // 사실이 아니면 **버린다**(기다리지 않는다).
        engine.greetingText = nil
        controller.enqueueAlkkagiAttention(other)
        #expect(controller.showPendingAlkkagiAttentionBubble() == false)
        #expect(controller.pendingAlkkagiAttention == nil, "사실이 아닌 알림이 큐에 남았다")
        alkkagi.state = nil
    }

    // MARK: #4 미니게임 창 사이드바 문

    /// 없으면: 사이드바 문이 옛 이름('알까기') · 옛 도움말('대전' · '초대')을 그대로 쓰거나, 아이콘을 글자로 따로 적어 입구 · 배너 ·
    /// 미션 줄 기호가 갈리고, 신청 점이 차단 · 내 판 신청에도 선다.
    @Test
    func theSidebarDoorUsesTheOneNameIconAndVisibleIncoming() throws {
        #expect(MiniGameAlkkagiEntryButton.title == "1:1 알까기")
        #expect(MiniGameAlkkagiEntryButton.help == "돌을 튕겨 밀어내는 1:1 알까기 대결 창을 열어요")
        for banned in ["대전", "초대", "참가비"] {
            #expect(!MiniGameAlkkagiEntryButton.help.contains(banned) && !MiniGameAlkkagiEntryButton.title.contains(banned))
        }
        let panel = try akwMac("MiniGamePanel.swift")
        #expect(panel.contains("MiniGameCrossyDuelEntryButton(hasInvite: invites.crossyDuel) { onCrossyDuel() } "
                                + "MiniGameAlkkagiEntryButton(hasInvite: invites.alkkagi) { onAlkkagi() }"), "여덟째 문이 길건너 뒤에 없다")
        #expect(panel.contains("MiniGameSidebarRow(title: Self.title, icon: AlkkagiEntryIcon.resolved,"), "문 아이콘이 한 출처가 아니다")
        #expect(panel.contains("crossyDuel: store.crossyDuel.visibleIncoming != nil, alkkagi: store.alkkagi.visibleIncoming != nil"))
        #expect(!panel.contains("store.alkkagi.incoming.isEmpty"))
        let doc = try V0317ShopTests.source("MiniGamePanel.swift")
        #expect(!doc.contains("로컬 2인 알까기"), "문서 주석이 옛 '로컬 2인 알까기 문' 그대로다")

        // 결과: 실제 소유자의 신청이 사이드바 점으로 — 차단 · 내 판이면 내린다.
        let store = akwStore("v03xx-alkkagi-wiring-sidebar")
        #expect(!MiniGameDuelInvites(store: store).alkkagi, "기준선: 신청이 없으면 점이 없다")
        store.alkkagi.incoming = [akwInvite("a-side")]
        #expect(MiniGameDuelInvites(store: store).alkkagi && MiniGameDuelInvites(store: store)[.alkkagi])
        store.blockHiddenPeerIDs = [akwRival.id]
        #expect(!MiniGameDuelInvites(store: store).alkkagi, "차단한 사람의 신청에 사이드바 점이 남았다")
        store.blockHiddenPeerIDs = []
        store.alkkagi.incoming = [akwInvite("a-side")]                    // 차단은 목록에서 걷는다 — 다시 싣는다
        #expect(MiniGameDuelInvites(store: store).alkkagi, "기준선: 차단을 풀고 다시 온 신청에 점이 선다")
        store.alkkagi.state = akwMatch("a-side", phase: .placing)
        #expect(!MiniGameDuelInvites(store: store).alkkagi, "판이 된 신청에 사이드바 점이 남았다")
        store.alkkagi.state = nil
        store.alkkagi.incoming = []
    }

    // MARK: #5 확성기 · #6 미션 아이콘

    /// 없으면: 판 중(배치 · 조준 · 굴림)에 확성기 배너가 떠 판을 가린다 — 배너 시험은 기본값 false 로 초록이다.
    @Test
    func theMegaphoneBannerWaitsForAnAlkkagiMatch() throws {
        #expect(MegaphoneBannerDeferral.isDeferred(gomoku: .lobby, chess: .lobby, tetris: .lobby, miniGameRoundLive: false,
                                                   alkkagiLive: true))
        // ★ 기준선: 같은 인자에서 그 한 칸만 거짓이면 미루지 않는다.
        #expect(!MegaphoneBannerDeferral.isDeferred(gomoku: .lobby, chess: .lobby, tetris: .lobby, miniGameRoundLive: false,
                                                    alkkagiLive: false))
        let src = try akwMac("WorkTimerStoreMegaphoneBanner.swift")
        #expect(src.contains("crossyDuelLive: crossyDuel.defersMegaphoneBanner, alkkagiLive: alkkagi.defersMegaphoneBanner)"))
        #expect(src.contains("crossyDuelLive: Bool = false, alkkagiLive: Bool = false) -> Bool {"))
        #expect(src.contains("if crossyDuelLive { return true } if alkkagiLive { return true }"))

        // 결과: 실제 소유자의 미룸 판정이 알까기 진행 판을 따른다(끝난 판 · 판 없음은 미루지 않는다).
        let store = akwStore("v03xx-alkkagi-wiring-megaphone")
        #expect(!store.isMegaphoneBannerDeferred, "기준선: 판이 없으면 미루지 않는다")
        for phase in [AlkkagiMatchPhase.placing, .aiming, .rolling] {
            store.alkkagi.state = akwMatch("a-mega", phase: phase)
            #expect(store.isMegaphoneBannerDeferred, "\(phase) 판 중에 확성기 배너를 미루지 않는다")
        }
        store.alkkagi.state = akwMatch("a-mega", phase: .finished)
        #expect(!store.isMegaphoneBannerDeferred, "끝난 판에도 배너를 미룬다")
        store.alkkagi.state = nil
    }

    /// 없으면: 맥 미션 화면의 열두째 줄(daily_alkkagi)과 업적 줄이 사이드바 문과 다른 기호(글자로 따로 적은 이름)를 쓰고, 폰 MeText 와
    /// 갈려 같은 줄이 두 기기에서 다른 그림이 된다.
    @Test
    func theDailyMissionRowUsesTheAlkkagiDoorIcon() throws {
        #expect(DailyMissionCopy.icon(game: "mahjong") != AchievementCopy.fallbackIcon, "기준선: 이웃 게임은 별이 아니다")
        let icon = DailyMissionCopy.icon(game: "alkkagi")
        #expect(icon != AchievementCopy.fallbackIcon, "맥 미션 줄 1:1 알까기가 기본 별로 떨어졌다")
        #expect(icon == AlkkagiEntryIcon.resolved && icon == AlkkagiEntryIcon.symbol, "사이드바 문과 다른 기호: \(icon)")
        // 폰 MeText(모바일 타깃 — 맥 시험은 글자로만 읽는다)의 같은 줄이 같은 기호다(SPEC §6 #8).
        let phone = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/CheckMobileKit/Me/MeText.swift")
        let meText = akwCollapsed(V0317ShopTests.stripped(try String(contentsOf: phone, encoding: .utf8)))
        #expect(meText.contains("(\"alkkagi\", \"\(icon)\"),"), "폰 MeText 와 맥 미션 줄 기호가 갈렸다")
        // 폰 1.0.18 부터 알까기가 있다 — 일일 줄에서 '맥에서' 꼬리를 뗀다(1:1 길건너 다음).
        #expect(meText.contains("phonePlayableMacFirstGames: Set<String> = [\"rummy\", \"reversi\", \"crossy_duel\", \"alkkagi\", \"mahjong\"]"),
                "폰에서 할 수 있는 알까기를 맥에서 하라고 적었다")
        #expect(AchievementCopy.icon("alkkagi_first_win") == AlkkagiEntryIcon.symbol)
        #expect(DailyMissionCopy.icon(game: "alkkagi_typo") == AchievementCopy.fallbackIcon)
        let rows = try akwMac("CheckAchievementRows.swift")
        #expect(rows.contains("(\"alkkagi\", AlkkagiEntryIcon.symbol)") && rows.contains("case \"alkkagi\": return AlkkagiEntryIcon.resolved"))
        // 뒤집기 기호(`circle.lefthalf.filled`)와 겹치지 않는다(DF#3).
        #expect(icon != ReversiEntryIcon.symbol)
    }

    // MARK: 팝오버 열기 → 가벼운 로비 · 판 끝 → 업적 조회

    /// 없으면(결과): 팝오버를 열 때마다 사람 목록·전적까지 읽는 무거운 로비가 나가거나(부하), 아예 안 나가 창을 안 연 사람의 배너·점이
    /// 신청을 영영 모른다. 실제 `WorkTimerStore` 의 팝오버 열기에서 나가는 요청 본문을 잰다.
    @Test(.gomokuDefaultsCleanup)
    func openingThePopoverReadsTheLightLobbyOnce() async throws {
        let host = "akw-light-\(UUID().uuidString.prefix(8))".lowercased()
        GomokuStubProtocol.register(host: host) { _, _, _ in nil }
        let store = akwStubbedStore("v03xx-alkkagi-wiring-light", host: host)
        store.isMenuPresented = false
        store.setMenuPresented(true)
        let lobby = AlkkagiOnlineWire.RPC.lobby.rawValue
        for _ in 0..<100 where GomokuStubProtocol.count(host: host, rpc: lobby) == 0 {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let calls = GomokuStubProtocol.calls(host: host, rpc: lobby)
        #expect(calls.count == 1, "팝오버 열기에 1:1 알까기 로비가 \(calls.count)번 나갔다")
        #expect(calls.first?.json["p_users"] as? Bool == false, "팝오버 열기가 무거운 로비(p_users true)를 읽는다: \(calls.first?.body ?? "")")
        #expect(calls.first?.json["p_protocol"] as? Int == 2)
        // 30초 스로틀: 닫았다 곧바로 다시 열어도 한 번 더 나가지 않는다.
        store.setMenuPresented(false)
        store.setMenuPresented(true)
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(GomokuStubProtocol.count(host: host, rpc: lobby) == 1, "30초 안에 다시 연 팝오버가 로비를 또 읽었다")
        // ★ 기준선: 창 경로(전체 로비)는 사람 목록까지 읽는다 — 같은 감지기가 p_users 를 가른다.
        await store.alkkagi.refreshLobby()
        let full = GomokuStubProtocol.calls(host: host, rpc: lobby)
        #expect(full.count == 2 && full.last?.json["p_users"] as? Bool == true)
        store.setMenuPresented(false)
    }

    /// 없으면(결과): 판이 끝나도 업적 · 일일 미션(daily_alkkagi) 조회가 안 나가 미션 줄이 다음 지갑 박자까지 안 오르거나, 한 판에 두 번
    /// 나간다. 실제 소유자에서 판 끝 계기를 한 번 울려 `achievements_status` 요청 수를 잰다.
    @Test(.gomokuDefaultsCleanup)
    func aFinishedMatchRefreshesAchievementsOnce() async throws {
        let host = "akw-achv-\(UUID().uuidString.prefix(8))".lowercased()
        GomokuStubProtocol.register(host: host) { _, _, _ in nil }
        let store = akwStubbedStore("v03xx-alkkagi-wiring-achievements", host: host)
        try await Task.sleep(nanoseconds: 100_000_000)
        let before = GomokuStubProtocol.count(host: host, rpc: "achievements_status")
        // ★ 기준선: 계기가 울리기 전에는 늘지 않는다.
        try await Task.sleep(nanoseconds: 100_000_000)
        #expect(GomokuStubProtocol.count(host: host, rpc: "achievements_status") == before)
        let task = try #require(store.alkkagi.onMatchFinished, "판 끝 계기가 소유자에 물리지 않았다")
        task()
        for _ in 0..<100 where GomokuStubProtocol.count(host: host, rpc: "achievements_status") == before {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        await store.achievementsFetchTask?.value
        #expect(GomokuStubProtocol.count(host: host, rpc: "achievements_status") == before + 1, "판 끝에 업적 조회가 한 번 나가지 않았다")
    }
}
