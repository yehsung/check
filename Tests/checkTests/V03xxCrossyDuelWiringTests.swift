import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// 1:1 길건너(내부 이름 crossy_duel) — **공용 접점 배선**(CD/SPEC.md §9.5 체크리스트 #1~#19 · #21~#23, §10.2 T `V03xxCrossyDuelWiringTests`).
// 스토어·창은 다른 갈래(C·U)가 채웠다. 여기서는 "그 문이 공용 파일에 꽂혀 있는가"를 소스 계약(주석 걷기 → 공백 접기 → 글자 그대로)으로
// 재고, 소스 계약이 모양만 잰다는 한계를 메우려고 **부르는 자리의 결과**를 같이 잰다 — 링이 실제로 가르는 효과 · 실제 `WorkTimerStore`
// 의 차단 거울 · 메뉴바 점 사유 · 팝오버 배너 높이 · 말풍선 큐와 판정 · 배너 미룸 · 미션 아이콘 · 팝오버 열기의 가벼운 로비.
// 결과 단언마다 **값 하나만 바꾼 기준선**을 함께 둔다. 길건너 줄은 모두 마작 줄 **뒤**, 라우팅 줄만 마작 줄 **앞**이다(§9.5 머리).
// 적대 검토 RV-C-1(①초인종 drain · ②미션 아이콘 별 · ③문 목록에 없음)의 재현 시험을 여기로 옮겼다(셋 다 이 가지 전에는 빨강).
//
// 각 시험의 첫 줄 주석은 **"없으면 어떤 결함이 초록으로 통과하는가"** 다(관례). 출시 뒤에도 V03xx 이름 그대로(SPEC §1).

private let cdwT0 = Date(timeIntervalSince1970: 1_800_000_000)
private let cdwMe = "0c0d0000-0000-4000-8000-0000000000aa"

private func cdwSubscribedLink() -> RealtimeLink {
    var link = RealtimeLink(transportAvailable: true)
    _ = link.apply(.signedIn(accessToken: "tok"), now: cdwT0, jitter: { $0 })
    _ = link.apply(.transport(.joined), now: cdwT0, jitter: { $0 })
    return link
}

private func cdwCollapsed(_ source: String) -> String {
    source.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
}

private func cdwCount(_ needle: String, in source: String) -> Int {
    source.components(separatedBy: needle).count - 1
}

/// Sources/check(+CheckCore) 파일을 주석 걷고 공백 접어 읽는다.
private func cdwMac(_ name: String) throws -> String {
    cdwCollapsed(V0317ShopTests.stripped(try V0317ShopTests.source(name)))
}

/// 폰 러너는 Sources/CheckMobileKit 에 산다(맥 시험이 모바일 세션 파일을 글자로만 읽는다).
private func cdwPhoneRunner() throws -> String {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/CheckMobileKit/Realtime/MobileRealtimeRunner.swift")
    return cdwCollapsed(V0317ShopTests.stripped(try String(contentsOf: url, encoding: .utf8)))
}

private func cdwBetween(_ source: String, _ start: String, _ end: String) -> String? {
    guard let head = source.range(of: start),
          let tail = source.range(of: end, range: head.upperBound..<source.endIndex) else { return nil }
    return String(source[head.lowerBound..<tail.lowerBound])
}

@MainActor
private func cdwDefaults(_ name: String) -> UserDefaults {
    let path = CheckTestScratch.suitePath(named: name)
    let defaults = UserDefaults(suiteName: path)!
    defaults.removePersistentDomain(forName: path)
    return defaults
}

@MainActor
private func cdwStore(_ name: String) -> WorkTimerStore {
    WorkTimerStore(environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"], defaults: cdwDefaults(name),
                   workspaceNotifications: nil)
}

private let cdwRival = CrossyDuelUser(id: "0c0d0000-0000-4000-8000-0000000000b1", displayName: "민수", characterID: "fox",
                                      isWorking: true)

private func cdwInvite(_ id: String, expiresIn seconds: TimeInterval = 50) -> CrossyDuelInvite {
    CrossyDuelInvite(id: id, peer: cdwRival, stake: 5, expiresAt: Date().addingTimeInterval(seconds))
}

/// 팝오버 높이를 재는 스토어. `teamless` 면 무소속 화면(헤더 카드 없이 배너가 맨 위에 선다).
@MainActor
private func cdwMenuStore(teamless: Bool) -> WorkTimerStore {
    let store = cdwStore(teamless ? "v03xx-crossy-duel-wiring-menu-teamless" : "v03xx-crossy-duel-wiring-menu")
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: cdwMe)
    if !teamless {
        store.currentTeamID = "11111111-1111-1111-1111-111111111111"
        store.teamName = "아잉팀"
        // 팀원 셋 — 본문이 레일보다 길게 시작해야 배너 높이가 창 높이 차로 그대로 드러난다(리버시 배선 시험과 같은 이유).
        store.teamMembers = (0..<3).map { index in
            TeamMemberStatus(id: "00000000-0000-0000-0000-0000000000c\(index)", name: "멤버\(index)", status: .offWork,
                             updatedAt: nil, currentSessionStartedAt: nil, weeklyDurationSeconds: 3_600)
        }
    }
    store.isMenuPresented = true
    return store
}

@MainActor
private func cdwOverlay() -> (ReactionEngine, CheckOverlayController, WorkTimerStore) {
    let store = cdwStore("v03xx-crossy-duel-wiring-overlay")
    let engine = ReactionEngine(clock: { Date(timeIntervalSince1970: 900_000) })
    let controller = CheckOverlayController(
        store: store, notificationCenter: NotificationCenter(), engine: engine,
        defaults: cdwDefaults("v03xx-crossy-duel-wiring-overlay"), workspaceNotifications: nil)
    return (engine, controller, store)
}

private enum CDWError: Error { case render }

@MainActor
private func cdwBitmap(_ view: some View) throws -> NSBitmapImageRep {
    guard let bitmap = CheckRenderSettle.bitmap(view.fixedSize(), scale: 2) else { throw CDWError.render }
    return bitmap
}

@MainActor
@Suite(.serialized)
struct V03xxCrossyDuelWiringTests {
    // MARK: #1~#4 링 · 폰 러너

    /// 없으면(RV-C-1①): 'crossy_duel' 이 '모르는 이름' 과 같은 갈래(drain = take_pokes)로 떨어져 신청 · 수락 · 시작 · 정산을 맥이 한 번도
    /// 당기지 않는다(스토어 시험은 초인종을 직접 부르므로 초록이다). 서버 이벤트 글자와 갈려도 같은 결함이다(그 짝은 MigrationContract).
    @Test
    func theCrossyDuelRingIsItsOwnBranchAndNotATakePokesDrain() {
        #expect(RealtimeLinkConstants.crossyDuelBroadcastEvent == "crossy_duel")
        var link = cdwSubscribedLink()
        #expect(link.apply(.transport(.broadcast(event: "crossy_duel")), now: cdwT0 + 1, jitter: { $0 }) == [.crossyDuelSignal])
        // ★ 기준선이 갈린다: 문자 그대로만 가른다 — 대문자 · 혼자 하기 이름은 모르는 이름이라 drain 이다.
        #expect(link.apply(.transport(.broadcast(event: "CROSSY_DUEL")), now: cdwT0 + 2, jitter: { $0 }) == [.drain])
        #expect(link.apply(.transport(.broadcast(event: "crossy")), now: cdwT0 + 3, jitter: { $0 }) == [.drain])
        // 이웃 갈래는 그대로다(새 줄이 앞을 가로채지 않는다).
        #expect(link.apply(.transport(.broadcast(event: "mahjong")), now: cdwT0 + 4, jitter: { $0 }) == [.mahjongSignal])
        #expect(link.apply(.transport(.broadcast(event: "reversi")), now: cdwT0 + 5, jitter: { $0 }) == [.reversiSignal])
    }

    /// 없으면: 새 줄이 마작·리버시·큐브 한 문장 **사이**에 끼어 마작 계약을 깨거나, drain 기본값 **뒤**에 서서 영영 닿지 않는다
    /// (이름 분기가 죽은 코드 — 컴파일은 초록).
    @Test
    func theCrossyDuelRouteStandsInFrontOfTheMahjongLine() throws {
        let link = try cdwMac("RealtimeLink.swift")
        #expect(link.contains("package static let crossyDuelBroadcastEvent = \"crossy_duel\""))
        #expect(link.contains("case mahjongSignal case crossyDuelSignal"), "효과 case 가 마작 뒤에 없다")
        let sentence: String = [
            "if event == RealtimeLinkConstants.crossyDuelBroadcastEvent { return [.crossyDuelSignal] } ",
            "if event == RealtimeLinkConstants.mahjongBroadcastEvent { return [.mahjongSignal] } ",
            "if event == RealtimeLinkConstants.reversiBroadcastEvent { return [.reversiSignal] }",
        ].joined()
        #expect(link.contains(sentence), "라우팅 줄이 마작 줄 바로 앞에 없다")
    }

    /// 없으면: 폰 러너에 길건너 가지가 없어 switch 가 컴파일되지 않거나(맥 시험은 모바일 타깃 뷰를 안 짓는다), 가지가 `.drain` 으로 새
    /// 같은 계정의 맥이 판을 하는 동안 폰이 초인종마다 메시지 조회를 한 번씩 더 한다.
    @Test
    func thePhoneRunnerKeepsAnEmptyCrossyDuelBranch() throws {
        let runner = try cdwPhoneRunner()
        #expect(cdwCount("case .crossyDuelSignal", in: runner) == 1, "폰 러너에 1:1 길건너 가지가 하나가 아니다")
        let branch = try #require(cdwBetween(runner, "case .crossyDuelSignal:", "case .pushAccessToken"))
        #expect(branch == "case .crossyDuelSignal: break ", "폰 러너의 1:1 길건너 가지가 비어 있지 않다: \(branch)")
        // ★ 기준선: 확성기 가지가 바로 앞이다(마작·리버시 앵커 묶음 밖 — 같은 읽기가 이웃 가지를 알아본다).
        #expect(runner.contains("requestMegaphoneRefresh() case .crossyDuelSignal: break case .pushAccessToken"))
        // 마작 계약의 앵커(마작 가지 ~ 확성기 가지 사이)는 그대로다.
        #expect(cdwBetween(runner, "case .mahjongSignal:", "case .megaphoneSignal:") == "case .mahjongSignal: break ")
    }

    // MARK: #5~#12 · #8b 맥 소유 배선

    /// 없으면: 소유자가 `reset()` 을 빠뜨리면 다음 사람이 앞 계정의 판·신청을 보고, 장부 defaults 를 빠뜨리면 앱을 다시 켠 기기가
    /// 자기 판을 못 알아보고, 결과 계기를 빠뜨리면 일일 미션이 안 오른다 — 스토어 시험은 전부 초록이다.
    @Test
    func theMacOwnerWiresTheCrossyDuelStoreAfterMahjong() throws {
        let owner = try cdwMac("WorkTimerStore.swift")
        #expect(owner.contains("let mahjong: MahjongStore let crossyDuel: CrossyDuelStore"))
        #expect(owner.contains("self.mahjong = MahjongStore() self.crossyDuel = CrossyDuelStore()"))
        #expect(owner.contains("mahjong.attach(host: self) crossyDuel.attach(host: self)"))
        #expect(owner.contains("mahjong.deviceLedger.defaults = defaults crossyDuel.deviceLedger.defaults = defaults"), "#8b 장부 defaults")
        #expect(cdwCount("crossyDuel.reset()", in: owner) == 2, "로그아웃·계정 전환 두 길에서 모두 내려야 한다")
        #expect(cdwCount("mahjong.reset() crossyDuel.reset()", in: owner) == 2, "두 길 모두 마작 바로 뒤가 아니다")
        #expect(owner.contains(
            "mahjong.setHiddenPeers(Set(blockHiddenPeerIDs.compactMap { UUID(uuidString: $0) })) "
                + "if crossyDuel.hiddenPeerIDs != blockHiddenPeerIDs { crossyDuel.hiddenPeerIDs = blockHiddenPeerIDs }"), "차단 거울")
        #expect(owner.contains("mahjong.refreshLobbyIfStale() crossyDuel.refreshLobbyIfStale()"))
        #expect(owner.contains(
            "crossyDuel.onMatchFinished = { [weak self] in self?.refreshAchievementsAfterGameResult(game: \"crossy_duel\") }"))
        // 게임 이름이 일일 미션 키의 꼬리다 — 혼자 하기 `crossy` 갈래로 접히지 않는다(SPEC §1 일일 미션 줄).
        #expect(DailyMissionStatus.key(game: "crossy_duel") == "daily_crossy_duel")
        #expect(DailyMissionStatus.key(game: "crossy") != "daily_crossy_duel")

        let realtime = try cdwMac("WorkTimerStoreRealtime.swift")
        #expect(realtime.contains("case .crossyDuelSignal: crossyDuel.handleSignal()"), "신호 가지가 없다 — 초인종마다 take_pokes 가 샌다")
        #expect(realtime.contains("mahjong.realtimeDidJoin() crossyDuel.realtimeDidJoin()"))
        let wake: String = [
            "if case .didWake = event, !realtime.transportAvailable { mahjong.systemDidWake() } ",
            "if case .didWake = event, !realtime.transportAvailable { crossyDuel.systemDidWake() }",
        ].joined()
        #expect(realtime.contains(wake), "전송자 없는 맥의 깨어남이 별도 블록으로 1:1 길건너를 안 본다")
    }

    /// 없으면(결과): 소스에 줄이 있어도 엉뚱한 칸을 비추면 차단한 사람의 신청이 배너·말풍선·점에 남는다. 실제 `WorkTimerStore` 에서
    /// 차단을 바꿔 길건너 스토어가 따라가는지 · 호스트·장부 defaults·미션 꼬리가 실제로 물렸는지 잰다.
    @Test
    func theRealOwnerMirrorsBlocksAndAttachesItself() {
        let store = cdwStore("v03xx-crossy-duel-wiring-owner")
        #expect(store.crossyDuel.host as AnyObject? === store, "소유자가 자신을 호스트로 넘기지 않았다")
        #expect(store.crossyDuel.deviceLedger.defaults != nil, "#8b — 장부가 프로세스 안에만 산다")
        #expect(store.crossyDuel.onMatchFinished != nil)
        // ★ 기준선: 차단 전에는 비어 있고 받은 신청이 보인다.
        store.crossyDuel.incoming = [cdwInvite("c-1")]
        #expect(store.crossyDuel.hiddenPeerIDs.isEmpty && store.crossyDuel.visibleIncoming?.id == "c-1")
        store.blockHiddenPeerIDs = [cdwRival.id]
        #expect(store.crossyDuel.hiddenPeerIDs == [cdwRival.id], "차단 거울이 1:1 길건너 스토어에 닿지 않는다")
        #expect(store.crossyDuel.visibleIncoming == nil, "차단한 사람의 신청이 보인다")
        store.blockHiddenPeerIDs = []
        #expect(store.crossyDuel.hiddenPeerIDs.isEmpty && store.crossyDuel.visibleIncoming?.id == "c-1")
        store.crossyDuel.incoming = []
    }

    // MARK: #13 CheckApp

    /// 없으면: 스토어 쪽 문이 옵셔널이라 `?.` 가 삼켜 **창이 안 뜨고**(presentWindow), 말풍선이 안 오고(onInviteArrived·onAttention),
    /// 로그아웃해도 창이 남고(감시자), App Nap 이 보고를 밀어 15초 침묵 패를 맞는다. 컴파일·스토어 시험은 초록이다.
    @Test
    func theAppWiresEveryCrossyDuelDoor() throws {
        let app = try cdwMac("CheckApp.swift")
        #expect(app.contains("wireReversi() wireMahjong() wireCrossyDuel() wireAlkkagi() wireMegaphoneBanner()"), "wireCrossyDuel() 이 마작 뒤·(알까기)·확성기 앞이 아니다")
        let body = try #require(cdwBetween(app, "private func wireCrossyDuel() {", "static func closeRummyWindow() {"))
        for line in [
            "let crossyDuel = store.crossyDuel crossyDuel.rankingEnabled = true",
            "crossyDuel.presentWindow = { CheckCrossyDuelWindowController.shared.show() }",
            "crossyDuel.dismissWindow = { CheckCrossyDuelWindowController.shared.close() }",
            "CheckCrossyDuelWindowController.shared.onClosed = { [weak self] byUser in self?.store.duelWindowDidClose(.crossyDuel, byUser: byUser) }",
            "crossyDuel.requestAttention = { if !NSApp.isActive { NSApp.requestUserAttention(.criticalRequest) } }",
            "crossyDuel.onInviteArrived = { [weak self] invite in self?.overlayController?.enqueueCrossyDuelInvite(invite) }",
            "crossyDuel.onAttention = { [weak self] attention in self?.overlayController?.enqueueCrossyDuelAttention(attention) }",
            "overlayController?.onOpenCrossyDuel = { [weak self] matchID in self?.store.crossyDuel.openWindow(focusMatchID: matchID) }",
            "CheckCrossyDuelWindowController.shared.close() self?.overlayController?.clearCrossyDuelInvites() }.start()",
            "let crossyDuelActivity = CrossyDuelActivityHold() crossyDuel.onHoldingActivityChange = { holding in crossyDuelActivity.set(holding) }",
        ] {
            #expect(body.contains(line), "wireCrossyDuel 에 없다: \(line)")
        }
        #expect(app.contains("CheckCrossyDuelWindowController.shared.configure(store: store.crossyDuel, me:"), "창 configure 가 없다")
        // 닫힘 알림은 창 컨트롤러가 스토어에 직접 알린다(`notifyClosed`) — 배선이 또 부르면 한 번 닫기에 두 번 접는다.
        #expect(!body.contains("windowDidClose()"))
    }

    /// 없으면(결과): App Nap 붙들기가 판 밖(로비)에서도 서거나(배터리) 판 중에 안 서 보고가 밀린다. 같은 값이 두 번 와도 하나만 쥔다.
    @Test
    func theActivityHoldFollowsTheStoreSignal() {
        var begun: [String] = []
        var ended = 0
        let hold = CrossyDuelActivityHold(begin: { reason in begun.append(reason); return NSObject() }, end: { _ in ended += 1 })
        // ★ 기준선: 놓기만 오면 아무것도 안 한다.
        hold.set(false)
        #expect(begun.isEmpty && ended == 0 && !hold.isHolding)
        hold.set(true)
        hold.set(true)
        #expect(begun == [CrossyDuelActivityHold.reason] && hold.isHolding, "같은 신호 두 번에 활동을 두 번 쥐었다")
        hold.set(false)
        #expect(ended == 1 && !hold.isHolding)
        // 스토어의 붙들기 사실: 판 밖(로비)은 거짓이다.
        let store = CrossyDuelStore()
        #expect(!store.holdsActivity && !store.defersMegaphoneBanner)
    }

    // MARK: #14 메뉴바 점(짝 게이트)

    /// 없으면: 세 자리(앱 인자 · 라벨 칸 · dotReasons) 중 하나만 빠져도 컴파일·시험이 초록인데 점만 안 켜진다(기본값 false).
    /// 결과로 잰다 — 실제 `WorkTimerStore` 에 신청을 넣고 앱과 **같은 식**으로 라벨을 세워 사유가 나오는지.
    @Test
    func theMenuBarDotLightsForARealCrossyDuelInvite() throws {
        let app = try cdwMac("CheckApp.swift")
        #expect(app.contains("hasMahjongAway: appDelegate.store.mahjong.hasAwaySeatHere, "
                                + "hasCrossyDuelInvite: appDelegate.store.crossyDuel.visibleIncoming != nil"),
                "메뉴바 라벨이 1:1 길건너 신청을 안 읽는다")
        let menu = try cdwMac("CheckMenuView.swift")
        #expect(menu.contains("var hasMahjongAway = false var hasCrossyDuelInvite = false"))
        #expect(menu.contains("mahjongAway: hasMahjongAway, crossyDuelInvite: hasCrossyDuelInvite"))

        let store = cdwStore("v03xx-crossy-duel-wiring-dot")
        let off = WorkStatusSnapshot(status: .offWork, elapsedSeconds: 0)
        func label() -> MenuBarStatusLabel {
            MenuBarStatusLabel(snapshot: off, title: "오프", hasCrossyDuelInvite: store.crossyDuel.visibleIncoming != nil)
        }
        // ★ 기준선: 신청이 없으면 점이 없다.
        #expect(label().dotReasons.isEmpty)
        store.crossyDuel.incoming = [cdwInvite("c-dot")]
        #expect(label().dotReasons == MenuBarDotReasons(crossyDuelInvite: true))
        #expect(label().dotReasons.accessibilityDescription == CrossyDuelText.dotReason)
        #expect(CrossyDuelText.dotReason == "1:1 길건너 신청")
        // 차단한 사람의 신청은 점을 내린다(앱 소유자의 차단 거울을 지나 스토어까지).
        store.blockHiddenPeerIDs = [cdwRival.id]
        #expect(label().dotReasons.isEmpty, "차단한 사람의 1:1 길건너 신청에 점이 남았다")
        store.blockHiddenPeerIDs = []
        store.crossyDuel.incoming = []
        // 말하는 순서: 마작 뒤.
        #expect(MenuBarDotReasons(mahjongInvite: true, crossyDuelInvite: true).accessibilityDescription
                    == "\(MahjongInviteText.dotReason) · \(CrossyDuelText.dotReason)")
    }

    // MARK: #15 팝오버 배너(두 자리)

    /// 없으면: 팝오버에 신청 배너가 안 서거나(우선순위 줄 누락) 높이 예산에서 빠져 팝오버가 잘리고, 무소속 자리를 빠뜨리면 팀 없는
    /// 사람은 배너를 못 본다. [수락]이 창을 먼저 띄우지 않으면 수락 순간 준비 시계가 도는데 판을 못 본다.
    @Test
    func thePopoverShowsTheCrossyDuelInviteBannerInBothSpots() throws {
        let menu = try cdwMac("CheckMenuView.swift")
        #expect(menu.contains("if store.isSignedIn, showsMahjongAwayBanner { return .mahjongAway } "
                                + "if store.isSignedIn, crossyDuelBannerInvite != nil { return .crossyDuelInvite }"))
        #expect(menu.contains("case mahjongAway case crossyDuelInvite"))
        #expect(menu.contains("case .crossyDuelInvite: return Self.crossyDuelInviteBannerHeight"))
        #expect(CheckMenuView.crossyDuelInviteBannerHeight == 92)
        #expect(menu.contains("previewCrossyDuelInvite ?? store.crossyDuel.visibleIncoming"))
        #expect(cdwCount("mahjongAwayBanner crossyDuelInviteBanner", in: menu) == 2, "두 자리(무소속 · 머리 카드 아래) 모두 마작 배너 뒤가 아니다")
        #expect(menu.contains("await crossyDuel.respond(inviteID: invite.id, accept: true) crossyDuel.openWindow(focusMatchID: invite.id) "
                                + "WindowTopAnchor.dismissMenuPopover()"))
        #expect(menu.contains("await crossyDuel.respond(inviteID: invite.id, accept: false)"))

        // 결과: 두 자리 모두에서 **실제 스토어의 신청**으로 배너가 그려진다(미리보기 칸이 아니다). 기준선은 신청 없는 같은 팝오버.
        for teamless in [false, true] {
            let store = cdwMenuStore(teamless: teamless)
            store.crossyDuel.incoming = []
            let without = try cdwBitmap(CheckMenuView(store: store))
            store.crossyDuel.incoming = [cdwInvite("c-banner", expiresIn: 48)]
            let with = try cdwBitmap(CheckMenuView(store: store))
            let grew = Double(with.pixelsHigh - without.pixelsHigh) / 2
            print("[배너] 1:1 길건너 배너(\(teamless ? "무소속" : "팀")) 높이 \(grew)pt (예산 \(CheckMenuView.crossyDuelInviteBannerHeight)pt)")
            #expect(with.pixelsHigh > without.pixelsHigh, "\(teamless ? "무소속" : "팀") 화면에 1:1 길건너 배너가 안 그려진다")
            #expect(abs(grew - Double(CheckMenuView.crossyDuelInviteBannerHeight)) < 24,
                    "배너 높이 예산(\(CheckMenuView.crossyDuelInviteBannerHeight)pt)과 실제(\(grew)pt)가 크게 다르다")
            if !teamless {
                // 마작 초대와 함께 오면 마작이 이긴다(배너는 한 번에 하나 — 창 높이 예산).
                let both = try cdwBitmap(CheckMenuView(store: store, previewMahjongAway: true))
                #expect(both.pixelsHigh == with.pixelsHigh, "마작·1:1 길건너 배너가 함께 그려졌다 — 창이 700pt 상한을 넘는다")
            }
            store.crossyDuel.incoming = []
        }
    }

    // MARK: #16 캐릭터 말풍선

    /// 없으면: 창을 닫아 둔 사람은 신청도 "대결이 시작됐어요"도 모른다 — 준비를 못 해 판이 무산된다. 몸체 히트테스트가 말풍선을
    /// 놓치면 클릭이 뒤 앱으로 새고, 클릭 자리가 없으면 눌러도 창이 안 열린다.
    @Test
    func theOverlayCarriesCrossyDuelBubblesInTheTetrisShape() throws {
        let raw = try CheckCoreSourceLayout.joinedSplitSource("CheckOverlayWindow.swift")
        #expect(raw.contains("// MARK: - 1:1 길건너 말풍선"))
        let overlay = cdwCollapsed(V0317ShopTests.stripped(raw))
        #expect(overlay.contains("if let rect = crossyDuelInviteBubbleScreenRect(), rect.contains(screenPoint) { return true }"),
                "몸체 히트테스트가 1:1 길건너 말풍선을 모른다")
        #expect(overlay.contains("if let rect = crossyDuelInviteBubbleScreenRect(), rect.contains(location), "
                                    + "let matchID = crossyDuelBubbleMatchID() { onOpenCrossyDuel?(matchID) return }"), "말풍선을 눌러도 창이 안 열린다")
        // 살아 있는 신청 거르기는 **테트리스형**(목록 전체) — 체스형(첫 건 한 칸)을 베끼면 둘째 신청부터 큐에서 조용히 지워진다.
        #expect(overlay.contains("let alive = Set(store.crossyDuel.visibleIncomingInvites.map(\\.id))"))
        #expect(!overlay.contains("store.crossyDuel.visibleIncoming?.id"), "체스형(첫 건 한 칸) 거르기가 섞였다")
        // 문구 글자는 맥 문구 집 한 곳(`CrossyDuelText`)에서 받는다.
        #expect(overlay.contains("CrossyDuelText.inviteBubbleText(name: name, stake: stake)"))
        let long = CheckOverlayController.crossyDuelInviteBubbleText(name: String(repeating: "가", count: 40), stake: 10)
        #expect(OverlayMessageBubble.fitsCapsule(long), "긴 이름에서 말풍선 문구가 캡슐을 넘친다: \(long)")
        #expect(long.hasSuffix("루비 10") && long.contains("1:1 길건너"))
    }

    /// 없으면(결과): 체스형 거르기를 베끼면 **둘째 신청부터** 큐에서 조용히 지워지고, 처리된 신청이 뒤늦게 뜬다.
    @Test
    func twoLiveInvitesBothReachTheCharacter() throws {
        let (engine, controller, store) = cdwOverlay()
        defer {
            controller.clearCrossyDuelInvites()
            controller.updateWorking(false)
        }
        let first = cdwInvite("invite-1"), second = cdwInvite("invite-2")
        store.crossyDuel.incoming = [first, second]
        controller.enqueueCrossyDuelInvite(first)
        controller.enqueueCrossyDuelInvite(first)
        controller.enqueueCrossyDuelInvite(second)
        #expect(controller.crossyDuelInviteQueue.map(\.id) == ["invite-1", "invite-2"], "같은 신청이 두 번 들어갔다")
        #expect(controller.showNextCrossyDuelInviteBubble())
        #expect(engine.greetingText == CrossyDuelText.inviteBubbleText(name: "민수", stake: 5))
        // ★ 둘째 신청이 큐에 **남아 있다**(체스형이면 여기서 지워진다 — 결과가 갈리는 자리).
        #expect(controller.crossyDuelInviteQueue.map(\.id) == ["invite-2"], "살아 있는 둘째 신청이 큐에서 지워졌다")
        #expect(controller.crossyDuelInviteBubbleScreenRect() == nil, "배선 전인데 클릭 자리가 생겼다")
        controller.onOpenCrossyDuel = { _ in }
        #expect(controller.crossyDuelBubbleMatchID() == "invite-1", "말풍선을 눌러도 그 신청의 창을 열 수 없다")
        engine.greetingText = nil
        // 처리된(스토어에서 사라진) 신청은 뒤늦게 뜨지 않는다 — 기준선: 위와 같은 큐인데 스토어 목록만 비었다.
        store.crossyDuel.incoming = []
        controller.enqueueCrossyDuelInvite(cdwInvite("handled"))
        #expect(controller.showNextCrossyDuelInviteBubble() == false)
        #expect(controller.crossyDuelInviteQueue.isEmpty, "이미 처리된 신청이 뒤늦게 말풍선으로 뜬다")
    }

    /// 없으면(결과): 창이 보이는데도 "대결이 시작됐어요" 가 겹쳐 뜨거나(규칙 ①), 열린 채 가려진 창에서는 말을 못 하거나, 끝난 판 ·
    /// 다른 판의 알림이 뜬다.
    @Test
    func theStartBubbleOnlyShowsTheCurrentHiddenMatch() throws {
        let (engine, controller, store) = cdwOverlay()
        defer {
            controller.clearCrossyDuelInvites()
            controller.updateWorking(false)
        }
        let crossyDuel = store.crossyDuel
        let matchID = "7e7e0000-0000-4000-8000-0000000000c1"
        crossyDuel.match = CrossyDuelMatchState(id: matchID, stake: 5, opponent: cdwRival)
        crossyDuel.isWindowVisible = false
        let attention = CrossyDuelAttention(kind: .matchStarted, matchID: matchID, opponentName: "민수")
        #expect(CheckOverlayController.crossyDuelAttentionIsCurrent(attention, in: crossyDuel))
        // ★ 기준선 — 값 하나씩만 바꿨다.
        let other = CrossyDuelAttention(kind: .matchStarted, matchID: "other", opponentName: "민수")
        #expect(!CheckOverlayController.crossyDuelAttentionIsCurrent(other, in: crossyDuel), "다른 판의 알림을 띄운다")
        crossyDuel.isWindowVisible = true
        #expect(!CheckOverlayController.crossyDuelAttentionIsCurrent(attention, in: crossyDuel), "창이 보이는데 말풍선을 띄운다")
        crossyDuel.isWindowOccluded = true
        #expect(CheckOverlayController.crossyDuelAttentionIsCurrent(attention, in: crossyDuel), "가려진 창인데 시작 말풍선을 버린다")
        crossyDuel.isWindowOccluded = false
        crossyDuel.isWindowVisible = false
        crossyDuel.match?.isFinished = true
        #expect(!CheckOverlayController.crossyDuelAttentionIsCurrent(attention, in: crossyDuel), "끝난 판인데 시작 말풍선을 띄운다")
        crossyDuel.match?.isFinished = false

        controller.enqueueCrossyDuelAttention(attention)
        #expect(controller.showPendingCrossyDuelAttentionBubble())
        #expect(engine.greetingText == "민수님과 1:1 길건너 대결이 시작됐어요")
        controller.onOpenCrossyDuel = { _ in }
        #expect(controller.crossyDuelBubbleMatchID() == matchID, "시작 말풍선을 눌러도 그 판을 열 수 없다")
        // 사실이 아니면 **버린다**(기다리지 않는다).
        engine.greetingText = nil
        controller.enqueueCrossyDuelAttention(other)
        #expect(controller.showPendingCrossyDuelAttentionBubble() == false)
        #expect(controller.pendingCrossyDuelAttention == nil, "사실이 아닌 시작 알림이 큐에 남았다")
        crossyDuel.match = nil
    }

    // MARK: #17~#19 미니게임 창 — 스페이스 키 등록 · 사이드바 문 · 여는 길

    /// 없으면(RV-C-1③): 대결 문에 1:1 길건너가 없어 창을 여는 길이 아예 없고, 미니게임 창을 띄워 둔 채 길건너 창에서 뛰면 미니게임
    /// 모니터가 방향키·스페이스를 먼저 삼키고(등록 누락), 문을 눌러도 미니게임 창이 남아 두 창이 겹친다.
    @Test
    func theMiniGameWindowOpensTheCrossyDuelWindow() throws {
        // ★ 기준선: 이웃 문(마작)은 있다 — 목록을 읽는 길이 살아 있다.
        #expect(MiniGameDuelDoor.allCases.contains(.mahjong))
        #expect(MiniGameDuelDoor.allCases.count == 8 && MiniGameDuelDoor.allCases[6] == .crossyDuel)
        #expect(MiniGameDuelDoor.allCases.last == .alkkagi)
        #expect(MiniGameSpaceKey.standaloneWindowIDs.contains("check.crossy-duel.window"))
        #expect(MiniGameSpaceKey.standaloneWindowIDs.contains(CheckCrossyDuelWindowController.frameAutosaveName))
        #expect(MiniGameSpaceKey.standaloneWindowIDs.count == 11)
        #expect(MiniGameCrossyDuelEntryButton.title == "1:1 길건너")
        #expect(MiniGameCrossyDuelEntryButton.help == "100점에 먼저 닿으면 이기는 1:1 길건너 대결 창을 열어요")
        let panel = try cdwMac("MiniGamePanel.swift")
        #expect(panel.contains("MiniGameMahjongEntryButton(hasInvite: invites.mahjong) { onMahjong() } "
                                + "MiniGameCrossyDuelEntryButton(hasInvite: invites.crossyDuel) { onCrossyDuel() }"), "일곱째 문이 마작 뒤에 없다")
        #expect(panel.contains("onMahjong: { store.openMahjongFromMiniGame() }, onCrossyDuel: { store.openCrossyDuelFromMiniGame() }"))
        #expect(panel.contains("let onMahjong: () -> Void let onCrossyDuel: () -> Void"), "문을 기본값 없이 받지 않는다")
        #expect(panel.contains("mahjong: Bool = false, crossyDuel: Bool = false, alkkagi: Bool = false) {"), "명시 init 맨 뒤 기본값(길건너 뒤 알까기)")
        #expect(panel.contains("crossyDuel: store.crossyDuel.visibleIncoming != nil"))
        #expect(panel.contains("case .mahjong: mahjong case .crossyDuel: crossyDuel"))
        // 결과: 첨자가 제 칸을 읽는다.
        #expect(MiniGameDuelInvites(crossyDuel: true)[.crossyDuel] && !MiniGameDuelInvites(mahjong: true)[.crossyDuel])
        let miniGame = try cdwMac("WorkTimerStoreMiniGame.swift")
        #expect(miniGame.contains("func openCrossyDuelFromMiniGame() { noteMiniGameDuelReturn(.crossyDuel) "
                                    + "crossyDuel.openWindow(focusMatchID: nil) closeMiniGamePanel() }"),
                "1:1 길건너 창을 먼저 띄우고 미니게임 창을 내려야 한다")
        #expect(miniGame.contains("case gomoku, chess, tetris, rummy, reversi, mahjong, crossyDuel, alkkagi }"))
    }

    /// 없으면(결과): 문을 눌러도 1:1 길건너 창이 안 뜨거나(presentWindow 를 안 부름) 미니게임 창이 남는다 — 실제 `WorkTimerStore` 에서.
    @Test(.gomokuDefaultsCleanup)
    func theSidebarDoorOpensTheWindowThenClosesTheMiniGameWindow() {
        let store = cdwStore("v03xx-crossy-duel-wiring-door")
        var order: [String] = []
        store.crossyDuel.presentWindow = { order.append("present") }
        defer { store.crossyDuel.presentWindow = nil }
        store.isMiniGamePanelVisible = true
        store.openCrossyDuelFromMiniGame()
        #expect(order == ["present"], "문을 눌러도 1:1 길건너 창을 띄우지 않는다")
        #expect(!store.isMiniGamePanelVisible && store.miniGameDuelReturn == .crossyDuel)
        // ★ 기준선: 다른 문의 닫힘은 표지를 건드리지 않는다.
        store.duelWindowDidClose(.mahjong, byUser: true)
        #expect(store.miniGameDuelReturn == .crossyDuel && !store.isMiniGamePanelVisible)
        store.duelWindowDidClose(.crossyDuel, byUser: true)
        #expect(store.isMiniGamePanelVisible && store.miniGameDuelReturn == nil, "닫으면 미니게임 창으로 돌아와야 한다")
        store.closeMiniGamePanel()
    }

    // MARK: #21 확성기 · #22 미션 아이콘

    /// 없으면: 판 중에 확성기 배너가 떠 길을 가린다 — 배너 시험은 기본값 false 로 초록이다.
    @Test
    func theMegaphoneBannerWaitsForACrossyDuelMatch() throws {
        #expect(MegaphoneBannerDeferral.isDeferred(gomoku: .lobby, chess: .lobby, tetris: .lobby, miniGameRoundLive: false,
                                                   crossyDuelLive: true))
        // ★ 기준선: 같은 인자에서 그 한 칸만 거짓이면 미루지 않는다.
        #expect(!MegaphoneBannerDeferral.isDeferred(gomoku: .lobby, chess: .lobby, tetris: .lobby, miniGameRoundLive: false,
                                                    crossyDuelLive: false))
        let src = try cdwMac("WorkTimerStoreMegaphoneBanner.swift")
        // 1:1 알까기(alkkagi/v2 SPEC §6 #5)가 길건너 뒤 맨 끝 인자다.
        #expect(src.contains("mahjongLive: mahjong.defersMegaphoneBanner, crossyDuelLive: crossyDuel.defersMegaphoneBanner, "
                                + "alkkagiLive: alkkagi.defersMegaphoneBanner)"))
        #expect(src.contains("mahjongLive: Bool = false, crossyDuelLive: Bool = false, alkkagiLive: Bool = false) -> Bool {"))
        #expect(src.contains("if mahjongLive { return true } if crossyDuelLive { return true }"))
    }

    /// 없으면(RV-C-1②): 맥 미션 화면의 열한째 줄(daily_crossy_duel)이 기본 별로 그려진다 — 폰(MeText)은 flag.checkered 라 같은 줄이
    /// 두 기기에서 다른 그림이고, 맥 안에서도 사이드바 문 기호와 갈린다.
    @Test
    func theDailyMissionRowUsesTheCrossyDuelDoorIcon() {
        // ★ 기준선: 이웃 게임은 별이 아니다 · 혼자 하기 crossy 는 혼자 하기 기호(걷는 사람)다.
        #expect(DailyMissionCopy.icon(game: "mahjong") != AchievementCopy.fallbackIcon)
        #expect(DailyMissionCopy.icon(game: "crossy") == MiniGameKind.crossy.icon)
        let icon = DailyMissionCopy.icon(game: "crossy_duel")
        #expect(icon != AchievementCopy.fallbackIcon, "맥 미션 줄 1:1 길건너가 기본 별로 떨어졌다")
        #expect(icon == "flag.checkered" && icon == CrossyDuelEntryIcon.resolved, "폰 MeText · 사이드바 문과 다른 기호: \(icon)")
        #expect(DailyMissionCopy.icon(game: "crossy_duel_typo") == AchievementCopy.fallbackIcon)
    }

    // MARK: #11 팝오버 열기 → 가벼운 로비(CS-4)

    /// 없으면(결과): 팝오버를 열 때마다 사람 목록·전적까지 읽는 무거운 로비가 나가거나(팝오버 50명 × 30초 부하 — SPEC §3.3), 아예 안
    /// 나가 창을 안 연 사람의 배너·점이 신청을 영영 모른다. 실제 `WorkTimerStore` 의 팝오버 열기에서 나가는 요청 본문을 잰다.
    @Test(.gomokuDefaultsCleanup)
    func openingThePopoverReadsTheLightLobbyOnce() async throws {
        let host = "cdw-light-\(UUID().uuidString.prefix(8))".lowercased()
        GomokuStubProtocol.register(host: host) { _, _, _ in nil }
        let service = SupabaseWorkService(projectURL: URL(string: "http://\(host)")!, anonKey: "anon-test-key",
                                          session: GomokuStubProtocol.session())
        let store = WorkTimerStore(service: service, environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
                                   defaults: cdwDefaults("v03xx-crossy-duel-wiring-light"), workspaceNotifications: nil)
        store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: cdwMe)
        store.isMenuPresented = false
        store.setMenuPresented(true)
        let lobby = CrossyDuelWire.RPC.lobby
        for _ in 0..<100 where GomokuStubProtocol.count(host: host, rpc: lobby) == 0 {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let calls = GomokuStubProtocol.calls(host: host, rpc: lobby)
        #expect(calls.count == 1, "팝오버 열기에 1:1 길건너 로비가 \(calls.count)번 나갔다")
        #expect(calls.first?.json["p_users"] as? Bool == false, "팝오버 열기가 무거운 로비(p_users true)를 읽는다: \(calls.first?.body ?? "")")
        // 30초 스로틀: 닫았다 곧바로 다시 열어도 한 번 더 나가지 않는다.
        store.setMenuPresented(false)
        store.setMenuPresented(true)
        try await Task.sleep(nanoseconds: 200_000_000)
        #expect(GomokuStubProtocol.count(host: host, rpc: lobby) == 1, "30초 안에 다시 연 팝오버가 로비를 또 읽었다")
        // ★ 기준선: 창 경로(전체 로비)는 사람 목록까지 읽는다 — 같은 감지기가 p_users 를 가른다.
        await store.crossyDuel.refreshLobby()
        let full = GomokuStubProtocol.calls(host: host, rpc: lobby)
        #expect(full.count == 2 && full.last?.json["p_users"] as? Bool == true)
        store.setMenuPresented(false)
    }
}
