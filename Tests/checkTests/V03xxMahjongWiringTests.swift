import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// 아잉 마작(내부 이름 mahjong) — **공용 접점 배선**(MJ/SPEC.md §4.6 체크리스트 #1~#19 · #21~#23 · §4.7, §6.3 T 줄).
// 스토어·창은 다른 갈래(C·U)가 채웠다. 여기서는 "그 문이 공용 파일에 꽂혀 있는가"를 소스 계약(주석 걷기 → 공백 접기 → 글자 그대로)으로
// 재고, 소스 계약이 모양만 잰다는 한계를 메우려고 **부르는 자리의 결과**를 같이 잰다 — 링이 실제로 가르는 효과 · 실제 `WorkTimerStore`
// 의 차단 거울 · 배너 미룸 판정 · 미션 아이콘 · 메뉴바 점 사유 · 말풍선 판정. 결과 단언마다 **값 하나만 바꾼 기준선**을 함께 둔다.
// 마작 줄은 모두 리버시 줄 **뒤**, 라우팅 줄만 리버시 줄 **앞**이다(§4.6 머리).
//
// 각 시험의 첫 줄 주석은 **"없으면 어떤 결함이 초록으로 통과하는가"** 다(관례).
// 버전이 정해지면 파일 이름과 `@Suite` 이름을 함께 `V03NN…` 으로 바꾼다(SPEC §1).

private let mwtT0 = Date(timeIntervalSince1970: 1_800_000_000)

private func mwtSubscribedLink() -> RealtimeLink {
    var link = RealtimeLink(transportAvailable: true)
    _ = link.apply(.signedIn(accessToken: "tok"), now: mwtT0, jitter: { $0 })
    _ = link.apply(.transport(.joined), now: mwtT0, jitter: { $0 })
    return link
}

private func mwtCollapsed(_ source: String) -> String {
    source.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
}

private func mwtCount(_ needle: String, in source: String) -> Int {
    source.components(separatedBy: needle).count - 1
}

/// Sources/check(+CheckCore) 파일을 주석 걷고 공백 접어 읽는다.
private func mwtMac(_ name: String) throws -> String {
    mwtCollapsed(V0317ShopTests.stripped(try V0317ShopTests.source(name)))
}

private func mwtRepoRoot() -> URL {
    URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
}

/// 폰 러너는 Sources/CheckMobileKit 에 산다(맥 시험이 모바일 세션 파일을 글자로만 읽는다 — 컴파일 의존 없음).
private func mwtPhoneRunner() throws -> String {
    let url = mwtRepoRoot().appendingPathComponent("Sources/CheckMobileKit/Realtime/MobileRealtimeRunner.swift")
    return mwtCollapsed(V0317ShopTests.stripped(try String(contentsOf: url, encoding: .utf8)))
}

private func mwtBetween(_ source: String, _ start: String, _ end: String) -> String? {
    guard let head = source.range(of: start),
          let tail = source.range(of: end, range: head.upperBound..<source.endIndex) else { return nil }
    return String(source[head.lowerBound..<tail.lowerBound])
}

@MainActor
private func mwtStore(_ name: String) -> WorkTimerStore {
    let path = CheckTestScratch.suitePath(named: name)
    let defaults = UserDefaults(suiteName: path)!
    defaults.removePersistentDomain(forName: path)
    return WorkTimerStore(environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"], defaults: defaults,
                          workspaceNotifications: nil)
}

/// S2 하네스 실응답 원문(`Fixtures/mahjong-rpc`)의 state.
private func mwtRealState(_ name: String) throws -> MahjongStatePayload {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("Fixtures/mahjong-rpc/\(name).json")
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try #require(try decoder.decode(MahjongActionResponse.self, from: Data(contentsOf: url)).state)
}

@MainActor
@Suite(.serialized)
struct V03xxMahjongWiringTests {
    // MARK: #1~#4 링 · 폰 러너

    /// 없으면: 'mahjong' 이 '모르는 이름' 과 같은 갈래로 떨어져 **버림마다 take_pokes 가 한 번씩 더** 나가고 소켓은 아잉 마작 상태를
    /// 한 번도 당기지 않는다(스토어 시험은 초인종을 직접 부르므로 초록이다). 서버 이벤트 글자와 갈려도 같은 결함이다.
    @Test
    func theMahjongRingIsItsOwnBranchAndNotATakePokesDrain() throws {
        #expect(RealtimeLinkConstants.mahjongBroadcastEvent == "mahjong")
        var link = mwtSubscribedLink()
        #expect(link.apply(.transport(.broadcast(event: "mahjong")), now: mwtT0 + 1, jitter: { $0 }) == [.mahjongSignal])
        // ★ 기준선이 갈린다: 문자 그대로만 가른다 — 대문자는 모르는 이름이라 drain 이다.
        #expect(link.apply(.transport(.broadcast(event: "MAHJONG")), now: mwtT0 + 2, jitter: { $0 }) == [.drain])
        // 이웃 갈래는 그대로다(새 줄이 앞을 가로채지 않는다).
        #expect(link.apply(.transport(.broadcast(event: "reversi")), now: mwtT0 + 3, jitter: { $0 }) == [.reversiSignal])
        #expect(link.apply(.transport(.broadcast(event: "rummy")), now: mwtT0 + 4, jitter: { $0 }) == [.rummySignal])
    }

    /// 없으면: 새 줄이 리버시·큐브·테트리스·오목·체스 한 문장 **사이**에 끼어 V0369·V0360·V0327·리버시 계약을 깨거나, drain 기본값
    /// **뒤**에 서서 영영 닿지 않는다(이름 분기가 죽은 코드 — 컴파일은 초록).
    @Test
    func theMahjongRouteStandsInFrontOfTheReversiLine() throws {
        let link = try mwtMac("RealtimeLink.swift")
        #expect(link.contains("package static let mahjongBroadcastEvent = \"mahjong\""))
        #expect(link.contains("case reversiSignal case mahjongSignal"), "효과 case 가 리버시 뒤에 없다")
        let sentence: String = [
            "if event == RealtimeLinkConstants.mahjongBroadcastEvent { return [.mahjongSignal] } ",
            "if event == RealtimeLinkConstants.reversiBroadcastEvent { return [.reversiSignal] } ",
            "if event == RealtimeLinkConstants.rummyBroadcastEvent { return [.rummySignal] }",
        ].joined()
        #expect(link.contains(sentence), "라우팅 줄이 리버시 줄 바로 앞에 없다")
    }

    /// 없으면: 폰 러너에 마작 가지가 없어 switch 가 컴파일되지 않거나(맥 시험은 모바일 타깃을 안 짓는다), 가지가 `.drain` 으로 새
    /// 같은 계정의 맥이 판을 하는 동안 폰이 버림마다 메시지 조회를 한 번씩 더 한다.
    @Test
    func thePhoneRunnerKeepsAnEmptyMahjongBranch() throws {
        let runner = try mwtPhoneRunner()
        #expect(mwtCount("case .mahjongSignal", in: runner) == 1, "폰 러너에 아잉 마작 가지가 하나가 아니다")
        let branch = try #require(mwtBetween(runner, "case .mahjongSignal:", "case .megaphoneSignal:"))
        #expect(branch == "case .mahjongSignal: break ", "폰 러너의 아잉 마작 가지가 비어 있지 않다: \(branch)")
        #expect(!branch.contains("?.handleSignal()"))
        // ★ 기준선: 리버시 가지가 바로 앞이다(같은 읽기가 이웃 가지를 알아본다). 폰 1.0.17(대표 답 #d_DdwzmxPClGqk)부터 리버시 가지는
        //   스토어로 잇는다 — 빈 가지가 아니다. 그 가지의 모양은 `V03xxReversiWiringTests.thePhoneRunnerWiresTheReversiBranchToTheStore` 가 잰다.
        #expect(runner.contains("case .reversiSignal: reversi?.handleSignal() case .mahjongSignal: break"))
    }

    // MARK: #5~#12 · #8b 맥 소유 배선

    /// 없으면: 소유자가 `reset()` 을 빠뜨리면 다음 사람이 앞 계정의 방·판·초대를 보고, 장부 defaults 를 빠뜨리면 앱을 다시 켠 기기가
    /// 자기 판의 창·깨우기를 잃고, 결과 계기를 빠뜨리면 일일 미션이 안 오른다 — 스토어 시험은 전부 초록이다.
    @Test
    func theMacOwnerWiresTheMahjongStoreAfterReversi() throws {
        let owner = try mwtMac("WorkTimerStore.swift")
        #expect(owner.contains("let reversi: ReversiStore let mahjong: MahjongStore"))
        #expect(owner.contains("self.reversi = ReversiStore() self.mahjong = MahjongStore()"))
        #expect(owner.contains("reversi.attach(host: self) mahjong.attach(host: self)"))
        #expect(owner.contains("reversi.deviceLedger.defaults = defaults mahjong.deviceLedger.defaults = defaults"), "#8b 장부 defaults")
        #expect(mwtCount("mahjong.reset()", in: owner) == 2, "로그아웃·계정 전환 두 길에서 모두 내려야 한다")
        #expect(mwtCount("reversi.reset() mahjong.reset()", in: owner) == 2, "두 길 모두 리버시 바로 뒤가 아니다")
        #expect(owner.contains(
            "if reversi.hiddenPeerIDs != blockHiddenPeerIDs { reversi.hiddenPeerIDs = blockHiddenPeerIDs } "
                + "mahjong.setHiddenPeers(Set(blockHiddenPeerIDs.compactMap { UUID(uuidString: $0) }))"), "차단 거울")
        #expect(owner.contains("reversi.refreshLobbyIfStale() mahjong.refreshLobbyIfStale()"))
        #expect(owner.contains(
            "mahjong.onMatchFinished = { [weak self] in self?.refreshAchievementsAfterGameResult(game: \"mahjong\") }"))
        #expect(DailyMissionStatus.key(game: "mahjong") == "daily_mahjong")

        let realtime = try mwtMac("WorkTimerStoreRealtime.swift")
        #expect(realtime.contains("case .mahjongSignal: mahjong.handleSignal()"), "신호 가지가 없다 — 초인종마다 take_pokes 가 샌다")
        #expect(realtime.contains("reversi.realtimeDidJoin() mahjong.realtimeDidJoin()"))
        let wake: String = [
            "if case .didWake = event, !realtime.transportAvailable { reversi.systemDidWake() } ",
            "if case .didWake = event, !realtime.transportAvailable { mahjong.systemDidWake() }",
        ].joined()
        #expect(realtime.contains(wake), "전송자 없는 맥의 깨어남이 별도 블록으로 아잉 마작을 안 본다")
    }

    /// 없으면(결과): 소스에 줄이 있어도 엉뚱한 칸을 비추면 차단한 사람의 초대가 배너·말풍선·점에 남는다. 실제 `WorkTimerStore` 에서
    /// 차단을 바꿔 마작 스토어가 따라가는지 · 호스트·장부 defaults·미션 꼬리가 실제로 물렸는지 잰다.
    @Test
    func theRealOwnerMirrorsBlocksAndAttachesItself() throws {
        let store = mwtStore("v03xx-mahjong-wiring-owner")
        #expect(store.mahjong.host as AnyObject? === store, "소유자가 자신을 호스트로 넘기지 않았다")
        #expect(store.mahjong.deviceLedger.defaults != nil, "#8b — 장부가 프로세스 안에만 산다")
        #expect(store.mahjong.onMatchFinished != nil)
        let peer = UUID(uuidString: "0e57a3c9-f9a2-4f0c-b585-d78604e285e5")!
        // ★ 기준선: 차단 전에는 비어 있다.
        #expect(store.mahjong.hiddenPeerIDs.isEmpty)
        store.blockHiddenPeerIDs = [peer.uuidString.lowercased()]
        #expect(store.mahjong.hiddenPeerIDs == [peer], "차단 거울이 아잉 마작 스토어에 닿지 않는다")
        store.blockHiddenPeerIDs = []
        #expect(store.mahjong.hiddenPeerIDs.isEmpty)
    }

    // MARK: #13 CheckApp

    /// 없으면: 스토어 쪽 문이 옵셔널이라 `?.` 가 삼켜 **창이 안 뜨고**(presentWindow), 말풍선이 안 오고(onInviteArrived·onAttention),
    /// 로그아웃해도 창이 남고(감시자), App Nap 이 5초 깨우기를 밀어 판이 멎는다. 컴파일·스토어 시험은 초록이다.
    @Test
    func theAppWiresEveryMahjongDoor() throws {
        let app = try mwtMac("CheckApp.swift")
        // 1:1 길건너(CD/SPEC.md §9.5 #13)가 마작 뒤·확성기 앞에 선다 — 마작 자리는 그대로 리버시 바로 뒤다.
        #expect(app.contains("wireRummy() wireReversi() wireMahjong() wireCrossyDuel() wireMegaphoneBanner()"),
                "wireMahjong() 이 리버시 뒤·확성기 앞(길건너 1:1 앞)이 아니다")
        let body = try #require(mwtBetween(app, "private func wireMahjong() {", "static func closeRummyWindow() {"))
        for line in [
            "mahjong.rankingEnabled = true",
            "mahjong.presentWindow = { CheckMahjongWindowController.shared.show() }",
            "mahjong.dismissWindow = { CheckMahjongWindowController.shared.close() }",
            "mahjong.requestAttention = {",
            "mahjong.onInviteArrived = { [weak self] room in self?.overlayController?.enqueueMahjongInvite(room) }",
            "mahjong.onAttention = { [weak self] attention in self?.overlayController?.enqueueMahjongAttention(attention) }",
            "overlayController?.onOpenMahjong = { [weak self] matchID in self?.store.mahjong.openWindow(focusMatchID: matchID) }",
            "CheckMahjongWindowController.shared.close() self?.overlayController?.clearMahjongInvites() }.start()",
            "let mahjongActivity = MahjongActivityHold() mahjong.onHoldingActivityChange = { holding in mahjongActivity.set(holding) }",
        ] {
            #expect(body.contains(line), "wireMahjong 에 없다: \(line)")
        }
        #expect(app.contains("CheckMahjongWindowController.shared.configure(store: store.mahjong, me:"), "창 configure 가 없다")
        // 닫기 안내는 창 컨트롤러가 스토어에 직접 알린다 — 배선이 또 부르면 한 번 닫기에 두 번 알린다.
        #expect(!body.contains("windowDidClose(byUser:"))
    }

    /// 없으면(결과): App Nap 신호가 연습판·남의 기기 판에도 서거나(배터리) 이 기기가 연 방에서 안 서 5초 깨우기가 밀린다.
    @Test(.gomokuDefaultsCleanup)
    func theActivityHoldFollowsTheLedgeredRoomOrMatch() throws {
        // 방장(0e57…, 자리 3)의 기기 — 장부는 세션 사용자 id 로 적으므로 호스트가 있어야 한다.
        let device = mjDevice("hold", me: "0e57a3c9-f9a2-4f0c-b585-d78604e285e5", server: MJServer())
        let store = device.store
        var heard: [Bool] = []
        store.onHoldingActivityChange = { heard.append($0) }
        let started = try mwtRealState("mahjong_start__ok")
        store.applyState(started)
        // ★ 기준선: 장부에 없는 판은 붙들지 않는다(같은 계정의 놀던 기기).
        #expect(!store.holdsActivity && heard.isEmpty)
        store.noteOwnsMatch(try #require(started.match?.id))
        #expect(store.holdsActivity && heard == [true])
        store.reset()
        #expect(!store.holdsActivity && heard == [true, false])
    }

    // MARK: #14 메뉴바 점(짝 게이트 — 초대 · 자리 비움)

    /// 없으면: 세 자리(앱 인자 · 라벨 칸 · dotReasons) 중 하나만 빠져도 컴파일·시험이 초록인데 점만 안 켜진다(기본값 false).
    @Test
    func theMenuBarDotLightsForAnInviteAndForAnAwaySeat() throws {
        let app = try mwtMac("CheckApp.swift")
        #expect(app.contains("hasMahjongInvite: appDelegate.store.mahjong.hasIncomingInvite"))
        #expect(app.contains("hasMahjongAway: appDelegate.store.mahjong.hasAwaySeatHere"))
        let menu = try mwtMac("CheckMenuView.swift")
        #expect(menu.contains("var hasMahjongInvite = false"))
        #expect(menu.contains("var hasMahjongAway = false"))
        #expect(menu.contains("reversiInvite: hasReversiInvite, mahjongInvite: hasMahjongInvite, mahjongAway: hasMahjongAway"))
        // 결과: 사유가 켜지면 점이 서고 보이스오버가 그 문구를 말한다.
        let invite = MenuBarDotReasons(mahjongInvite: true)
        #expect(!invite.isEmpty && invite.accessibilityDescription == MahjongInviteText.dotReason)
        let away = MenuBarDotReasons(mahjongAway: true)
        #expect(!away.isEmpty && away.accessibilityDescription == MahjongInviteText.awayDotReason)
        // ★ 기준선: 둘 다 꺼지면 점이 없다.
        #expect(MenuBarDotReasons().isEmpty)
        #expect(MenuBarDotReasons(reversiInvite: true, mahjongInvite: true).accessibilityDescription
                    == "\(ReversiText.dotReason) · \(MahjongInviteText.dotReason)", "말하는 순서가 리버시 뒤가 아니다")
    }

    // MARK: #15 팝오버 배너(두 자리)

    /// 없으면: 배너가 한 자리(무소속 · 머리 카드 아래)에만 꽂히거나 높이 switch 에 빠져 팝오버가 잘린다 — 렌더 시험은 기본 화면만 본다.
    @Test
    func thePopoverShowsTheMahjongBannersInBothSpots() throws {
        let menu = try mwtMac("CheckMenuView.swift")
        #expect(mwtCount("reversiInviteBanner mahjongInviteBanner", in: menu) == 2, "초대 배너가 두 자리 모두 리버시 뒤가 아니다")
        #expect(mwtCount("mahjongInviteBanner mahjongAwayBanner", in: menu) == 2, "자리 비움 배너가 두 자리 모두 초대 뒤가 아니다")
        #expect(menu.contains("case reversiInvite case mahjongInvite case mahjongAway"))
        #expect(menu.contains("case .mahjongInvite: return Self.mahjongInviteBannerHeight case .mahjongAway: return Self.mahjongAwayBannerHeight"))
        #expect(menu.contains(
            "if store.isSignedIn, reversiBannerInvite != nil { return .reversiInvite } "
                + "if store.isSignedIn, mahjongBannerInvite != nil { return .mahjongInvite } "
                + "if store.isSignedIn, showsMahjongAwayBanner { return .mahjongAway }"))
        #expect(menu.contains("previewMahjongAway || store.mahjong.hasAwaySeatHere"), "자리 비움 후보가 장부 판정을 안 읽는다")
        #expect(CheckMenuView.mahjongInviteBannerHeight == 92 && CheckMenuView.mahjongAwayBannerHeight == 92)
    }

    // MARK: #16 말풍선

    /// 없으면: 말풍선 칸이 없거나 살아 있는 초대를 첫 건 하나로만 걸러 둘째 초대가 조용히 지워지고, 창이 탁자를 보이는데도 "내 차례"
    /// 말풍선이 겹쳐 뜨거나(가려진 창을 보이는 것으로 친다) 지난 국의 차례 말풍선이 뜬다.
    @Test
    func theOverlayCarriesMahjongBubblesAndJudgesThemOnTheCurrentHand() throws {
        let raw = try CheckCoreSourceLayout.joinedSplitSource("CheckOverlayWindow.swift")
        #expect(raw.contains("// MARK: - 마작 말풍선"))
        let overlay = mwtCollapsed(V0317ShopTests.stripped(raw))
        #expect(overlay.contains("let alive = Set(store.mahjong.visibleInvites.map(\\.id))"), "큐브형 살아 있음 거르기가 아니다")
        #expect(overlay.contains("guard !mahjong.isWindowShowingTable"))
        #expect(overlay.contains("if let rect = mahjongInviteBubbleScreenRect(), rect.contains(screenPoint) { return true }"))
        #expect(overlay.contains("if let rect = mahjongInviteBubbleScreenRect(), rect.contains(location), let matchID = mahjongBubbleMatchID() { onOpenMahjong?(matchID) return }"))
        // 결과: 실응답 내 차례 state 위에서 열쇠의 판·국이 같으면 참.
        let store = MahjongStore()
        let mine = try mwtRealState("mahjong_state__turn_mine")
        store.applyState(mine)
        let id = try #require(mine.match?.id)
        let turn = MahjongAttention(kind: .myTurn, matchID: id, handIndex: 0, key: "\(id)#0")
        #expect(CheckOverlayController.mahjongAttentionIsCurrent(turn, in: store))
        // ★ 기준선: 다른 국 · 다른 판 · 비움 아닌 자리의 '자리 비움'은 거짓.
        #expect(!CheckOverlayController.mahjongAttentionIsCurrent(
            MahjongAttention(kind: .myTurn, matchID: id, handIndex: 1, key: "\(id)#1"), in: store))
        #expect(!CheckOverlayController.mahjongAttentionIsCurrent(
            MahjongAttention(kind: .myTurn, matchID: "other", handIndex: 0, key: "other#0"), in: store))
        #expect(!CheckOverlayController.mahjongAttentionIsCurrent(
            MahjongAttention(kind: .away, matchID: id, handIndex: 0, key: "\(id)#away"), in: store))
        let away = MahjongStore()
        let left = try mwtRealState("mahjong_leave__active")
        away.applyState(left)
        let leftID = try #require(left.match?.id)
        #expect(CheckOverlayController.mahjongAttentionIsCurrent(
            MahjongAttention(kind: .away, matchID: leftID, handIndex: 0, key: "\(leftID)#away"), in: away))
    }

    // MARK: #17~#19 미니게임 창 · §4.7 문 복귀

    /// 없으면: 사이드바 여섯째 문이 없거나 엉뚱한 자리(리버시 앞)에 서고, 미니게임 창이 마작 창을 띄우기 전에 내려가며, 마작 창이 미니게임
    /// 창 소속으로 잡혀 미니게임 창을 닫을 때 같이 사라진다.
    @Test
    func theMiniGameWindowOpensTheMahjongWindow() throws {
        #expect(MiniGameSpaceKey.standaloneWindowIDs.contains("check.mahjong.window"))
        #expect(MiniGameSpaceKey.standaloneWindowIDs.contains(CheckMahjongWindowController.frameAutosaveName))
        // 1:1 길건너 창이 더해져 열이다(CD/SPEC.md §9.5 #17).
        #expect(MiniGameSpaceKey.standaloneWindowIDs.count == 10)
        #expect(MiniGameMahjongEntryButton.title == "아잉 마작")
        #expect(MiniGameMahjongEntryButton.help == "리치 마작 4인 대국 창을 열어요")
        let panel = try mwtMac("MiniGamePanel.swift")
        #expect(panel.contains(
            "MiniGameReversiEntryButton(hasInvite: invites.reversi) { onReversi() } "
                + "MiniGameMahjongEntryButton(hasInvite: invites.mahjong) { onMahjong() }"), "여섯째 문이 리버시 뒤에 없다")
        #expect(panel.contains("onReversi: { store.openReversiFromMiniGame() }, onMahjong: { store.openMahjongFromMiniGame() }"))
        #expect(panel.contains("let onReversi: () -> Void let onMahjong: () -> Void"), "문을 기본값 없이 받지 않는다")
        #expect(panel.contains("reversi: Bool = false, mahjong: Bool = false, crossyDuel: Bool = false) {"),
                "명시 init 맨 뒤 기본값(마작 뒤에 1:1 길건너 — CD/SPEC.md §9.5 #18)")
        #expect(panel.contains("mahjong: store.mahjong.hasIncomingInvite"))
        #expect(panel.contains("case .reversi: reversi case .mahjong: mahjong"))
        // 결과: 첨자가 제 칸을 읽는다.
        #expect(MiniGameDuelInvites(mahjong: true)[.mahjong] && !MiniGameDuelInvites(reversi: true)[.mahjong])
        let miniGame = try mwtMac("WorkTimerStoreMiniGame.swift")
        #expect(miniGame.contains(
            "func openMahjongFromMiniGame() { noteMiniGameDuelReturn(.mahjong) mahjong.openWindow(focusMatchID: nil) closeMiniGamePanel() }"),
                "마작 창을 먼저 띄우고 미니게임 창을 내려야 한다")
    }

    /// 없으면(§4.7 조건부 — **마작 글자만**): 버그 개선 가지의 문 목록에 마작이 빠지거나(사이드바 여섯째 줄이 안 선다) 창을 닫아도
    /// 미니게임 창으로 안 돌아온다. 문 목록이 없는 체크아웃에서는 재지 않는다(그 가지가 들어오기 전).
    @Test
    func theDuelDoorListEndsWithMahjongAndTheWindowReturns() throws {
        let miniGame = try mwtMac("WorkTimerStoreMiniGame.swift")
        guard miniGame.contains("enum MiniGameDuelDoor") else { return }
        let caseLine = try #require(mwtBetween(miniGame, "enum MiniGameDuelDoor", "}"))
        // 1:1 길건너(CD/SPEC.md §9.5 #19)가 맨 뒤에 붙어 마작은 끝에서 둘째다 — 마작 바로 뒤가 길건너 하나뿐인지 잰다.
        #expect(caseLine.hasSuffix("mahjong, crossyDuel "), "문 목록이 mahjong, crossyDuel 로 끝나지 않는다: \(caseLine)")
        let rummy = try #require(caseLine.range(of: "rummy"))
        let mahjong = try #require(caseLine.range(of: "mahjong"))
        #expect(rummy.upperBound <= mahjong.lowerBound, "mahjong 이 rummy 뒤가 아니다")
        #expect(miniGame.contains("noteMiniGameDuelReturn(.mahjong)"))
        let app = try mwtMac("CheckApp.swift")
        let hook = try #require(app.range(of: "CheckMahjongWindowController.shared.onClosed = {"))
        #expect(String(app[hook.upperBound...].prefix(120)).contains("duelWindowDidClose(.mahjong, byUser: byUser)"))
        #expect(Array(MiniGameDuelDoor.allCases.suffix(2)) == [.mahjong, .crossyDuel])
    }

    // MARK: #21 확성기 · #22 미션 아이콘

    /// 없으면: 판 중에 확성기 배너가 탁자 위로 떠 5초 차례를 가린다 — 배너 시험은 기본값 false 로 초록이다.
    @Test
    func theMegaphoneBannerWaitsForAMahjongMatch() throws {
        #expect(MegaphoneBannerDeferral.isDeferred(gomoku: .lobby, chess: .lobby, tetris: .lobby, miniGameRoundLive: false,
                                                   mahjongLive: true))
        // ★ 기준선: 같은 인자에서 그 한 칸만 거짓이면 미루지 않는다.
        #expect(!MegaphoneBannerDeferral.isDeferred(gomoku: .lobby, chess: .lobby, tetris: .lobby, miniGameRoundLive: false,
                                                    mahjongLive: false))
        let src = try mwtMac("WorkTimerStoreMegaphoneBanner.swift")
        // 1:1 길건너(CD/SPEC.md §9.5 #21)가 마작 뒤 맨 끝 인자다.
        #expect(src.contains("reversiLive: reversi.defersMegaphoneBanner, mahjongLive: mahjong.defersMegaphoneBanner, "
                                + "crossyDuelLive: crossyDuel.defersMegaphoneBanner)"))
        #expect(src.contains("reversiLive: Bool = false, mahjongLive: Bool = false, crossyDuelLive: Bool = false) -> Bool {"))
        #expect(src.contains("if reversiLive { return true } if mahjongLive { return true }"))
    }

    /// 없으면: 일일 미션 `daily_mahjong` 줄이 모르는 게임의 별(fallback)로 그려진다.
    @Test
    func theDailyMissionRowUsesTheMahjongDoorIcon() throws {
        #expect(DailyMissionCopy.icon(game: "mahjong") == MahjongEntryIcon.resolved)
        #expect(DailyMissionCopy.icon(game: "mahjong") != AchievementCopy.fallbackIcon)
        #expect(DailyMissionCopy.icon(game: "mahjong_typo") == AchievementCopy.fallbackIcon)
    }
}
