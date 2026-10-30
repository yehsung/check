import Foundation
import Testing
@testable import check
@testable import CheckCore

// v0.3.69 — 아잉 큐브 **공용 접점 배선**(설계 §5 · map-mac §3 의 접점 1~19, #20 버전은 통합 몫).
// 스토어·창은 다른 갈래가 채우므로 여기서는 "그 문이 공용 파일에 꽂혀 있는가"만 잰다. 링은 순수 동작으로, 나머지는
// 소스 계약(주석 걷기 → 공백 접기 → 글자 그대로)으로 — V0360TetrisDuelRealtimeTests 작법 그대로다.
//
// 각 시험의 첫 줄 주석은 **"없으면 어떤 결함이 초록으로 통과하는가"** 다(관례).

private let rwT0 = Date(timeIntervalSince1970: 1_800_000_000)

private func rwSubscribedLink() -> RealtimeLink {
    var link = RealtimeLink(transportAvailable: true)
    _ = link.apply(.signedIn(accessToken: "tok"), now: rwT0, jitter: { $0 })
    _ = link.apply(.transport(.joined), now: rwT0, jitter: { $0 })
    return link
}

private func rwCollapsed(_ source: String) -> String {
    source.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
}

private func rwCount(_ needle: String, in source: String) -> Int {
    source.components(separatedBy: needle).count - 1
}

/// Sources/check(+CheckCore) 파일을 주석 걷고 공백 접어 읽는다.
private func rwMac(_ name: String) throws -> String {
    rwCollapsed(V0317ShopTests.stripped(try V0317ShopTests.source(name)))
}

/// 폰 러너는 Sources/CheckMobileKit 에 산다(맥 시험이 모바일 세션 파일을 글자로만 읽는다 — 컴파일 의존 없음).
private func rwPhoneRunner() throws -> String {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/CheckMobileKit/Realtime/MobileRealtimeRunner.swift")
    return rwCollapsed(V0317ShopTests.stripped(try String(contentsOf: url, encoding: .utf8)))
}

// MARK: - #1~#3 링: 'rummy' 는 자기 갈래이고 drain 으로 새지 않는다

/// 없으면: 'rummy' 가 '모르는 이름' 과 같은 갈래로 떨어져 **초인종마다 take_pokes 가 한 번씩 더** 나가고(작업 판은 끌기마다
/// 울린다) 소켓은 아잉 큐브 상태를 한 번도 당기지 않는다. 서버 `rummy__ring` 의 이벤트 이름과 글자가 갈려도 같은 결함이다.
@MainActor
@Test
func theRummyRingIsItsOwnBranchAndNotATakePokesDrain() {
    #expect(RealtimeLinkConstants.rummyBroadcastEvent == "rummy",
            "서버 `rummy__ring` 의 realtime.send(…, 'rummy', …) 와 글자가 달라졌다")
    var link = rwSubscribedLink()
    #expect(link.apply(.transport(.broadcast(event: "rummy")), now: rwT0 + 1, jitter: { $0 }) == [.rummySignal])
    // 아잉 큐브 신호도 소켓이 살아 있다는 증거다(좀비 판정 시계를 민다).
    #expect(link.state == .subscribed(since: rwT0, lastHeardAt: rwT0 + 1))

    // ★ 기준선이 갈린다: 여섯 이름이 여섯 갈래다(모르는 이름은 예전 그대로 drain — 그 기본값을 지운 것이 아니다).
    let unknown = link.apply(.transport(.broadcast(event: "모르는이름")), now: rwT0 + 2, jitter: { $0 })
    let tetris = link.apply(.transport(.broadcast(event: "tetris")), now: rwT0 + 3, jitter: { $0 })
    let chess = link.apply(.transport(.broadcast(event: "chess")), now: rwT0 + 4, jitter: { $0 })
    let gomoku = link.apply(.transport(.broadcast(event: "gomoku")), now: rwT0 + 5, jitter: { $0 })
    let read = link.apply(.transport(.broadcast(event: "message_read")), now: rwT0 + 6, jitter: { $0 })
    #expect(unknown == [.drain] && tetris == [.tetrisSignal] && chess == [.chessSignal]
            && gomoku == [.gomokuSignal] && read == [.messageReadSignal])
    #expect(Set([[RealtimeEffect.rummySignal], unknown, tetris, chess, gomoku, read].map { "\($0)" }).count == 6)
    // 문자 그대로만 가른다.
    #expect(link.apply(.transport(.broadcast(event: "RUMMY")), now: rwT0 + 7, jitter: { $0 }) == [.drain])

    // 구독 전에는 어떤 이름이든 아무것도 시키지 않는다.
    var connecting = RealtimeLink(transportAvailable: true)
    _ = connecting.apply(.signedIn(accessToken: "tok"), now: rwT0, jitter: { $0 })
    #expect(connecting.apply(.transport(.broadcast(event: "rummy")), now: rwT0 + 1, jitter: { $0 }) == [])

    // 프레임 해석이 이름을 그대로 넘긴다(서버 페이로드 {v,m,s} + realtime 이 붙이는 id).
    let text = String(decoding: try! JSONSerialization.data(withJSONObject: [
        "topic": "realtime:poke:me", "event": "broadcast",
        "payload": ["event": "rummy", "type": "broadcast",
                    "payload": ["v": 1, "m": "7e7e0000-0000-4000-8000-000000000069", "s": 3, "id": "x"]],
    ]), as: UTF8.self)
    #expect(RealtimeFrame.decode(text: text, channel: "poke:me", joinRef: "1") == .broadcast(event: "rummy"))
}

/// 없으면: 아잉 큐브 줄이 테트리스·오목 줄 **사이**에 끼어 V0360(테트리스→오목 한 문장)·V0327(오목→체스→drain 한 문장)
/// 계약을 깨거나, drain 기본값 **뒤**에 서서 영영 닿지 않는다(컴파일·링 시험은 초록 — 이름 분기가 죽은 코드가 된다).
@MainActor
@Test
func theRummyRouteStandsInFrontOfTheTetrisAndGomokuSentence() throws {
    let link = try rwMac("RealtimeLink.swift")
    #expect(link.contains("package static let rummyBroadcastEvent = \"rummy\""))
    #expect(link.contains("if event == RealtimeLinkConstants.rummyBroadcastEvent { return [.rummySignal] } "
                          + "if event == RealtimeLinkConstants.tetrisBroadcastEvent { return [.tetrisSignal] } "
                          + "if event == RealtimeLinkConstants.gomokuBroadcastEvent { return [.gomokuSignal] } "
                          + "if event == RealtimeLinkConstants.chessBroadcastEvent { return [.chessSignal] } "
                          + "return [.drain]"))
}

// MARK: - #4 폰 러너: 빈 가지(폰 판에서 잇는다)

/// 없으면: 폰 러너의 exhaustive switch 가 컴파일되지 않거나(가지 없음), `default`/`.drain` 으로 떨어뜨리면 같은 계정의 맥이
/// 판을 하는 동안 작업 판 초인종마다 폰이 **메시지** 요약·이력을 한 번씩 더 조회한다.
@MainActor
@Test
func thePhoneRunnerKeepsAnEmptyRummyBranch() throws {
    let runner = try rwPhoneRunner()
    #expect(runner.contains("case .rummySignal: break"), "폰 러너의 아잉 큐브 가지가 비어 있지 않거나 없다")
    #expect(rwCount("case .rummySignal", in: runner) == 1, "폰 러너에 아잉 큐브 가지가 하나가 아니다")
}

// MARK: - #5~#12 맥 소유 배선(WorkTimerStore · WorkTimerStoreRealtime)

/// 없으면: 소유자가 `reset()` 을 빠뜨리면 다음 사람이 앞 계정의 방·판을 보고, 차단 거울을 빠뜨리면 차단한 사람의 초대·공개 방이
/// 배너에 뜨고, 팝오버 계기를 빠뜨리면 창을 안 연 사람에게 초대가 안 닿고, 결과 계기를 빠뜨리면 일일 미션이 다음 박자까지
/// 안 오른다 — 넷 다 스토어 시험은 초록이다.
@MainActor
@Test
func theMacOwnerWiresTheRummyStoreLikeTetris() throws {
    let owner = try rwMac("WorkTimerStore.swift")
    #expect(owner.contains("let rummy: RummyStore"))
    #expect(owner.contains("self.rummy = RummyStore()"))
    #expect(owner.contains("tetris.attach(host: self) rummy.attach(host: self)"))
    #expect(rwCount("rummy.reset()", in: owner) == 2, "로그아웃·계정 전환 두 길에서 모두 내려야 한다")
    #expect(owner.contains("rummy.setHiddenPeers(Set(blockHiddenPeerIDs.compactMap { UUID(uuidString: $0) }))"),
            "차단 거울에 아잉 큐브가 없다")
    #expect(owner.contains("tetris.refreshLobbyIfStale() rummy.refreshLobbyIfStale()"), "팝오버 열기 계기에 아잉 큐브가 없다")
    #expect(owner.contains(
        "rummy.onMatchFinished = { [weak self] in self?.refreshAchievementsAfterGameResult(game: \"rummy\") }"))
    // 그 게임 이름이 일일 미션 키(설계 §1 `daily_rummy`)의 꼬리다 — 이미 채운 줄이면 묻지 않는 가드가 이 키로 찾는다.
    #expect(DailyMissionStatus.key(game: "rummy") == "daily_rummy")

    let realtime = try rwMac("WorkTimerStoreRealtime.swift")
    #expect(realtime.contains("case .rummySignal: rummy.handleSignal()"),
            "아잉 큐브 신호 가지가 없다 — 초인종마다 take_pokes 가 샌다")
    #expect(realtime.contains("tetris.realtimeDidJoin() rummy.realtimeDidJoin()"), "조인 직후 따라잡기에 아잉 큐브가 없다")
    #expect(realtime.contains("if case .didWake = event, !realtime.transportAvailable { rummy.systemDidWake() }"),
            "전송자 없는 맥의 깨어남이 아잉 큐브를 안 본다")
}

// MARK: - #13 CheckApp: 문 · 창 배선 · 계정 전환 감시

/// 없으면: 스토어 쪽 문이 옵셔널이라 `?.` 가 삼켜 **창이 안 뜨고**(presentWindow), 말풍선이 안 오고(onInviteArrived·onAttention),
/// 로그아웃해도 창이 남는다(dismissWindow·감시자). 컴파일·스토어 시험은 전부 초록이다.
@MainActor
@Test
func theAppWiresEveryRummyDoor() throws {
    let app = try rwMac("CheckApp.swift")
    #expect(app.contains("wireTetrisDuel() wireRummy()"), "실행 시 wireRummy() 를 부르지 않는다")
    #expect(app.contains("let rummy = store.rummy rummy.rankingEnabled = true"))
    #expect(app.contains("rummy.presentWindow = { CheckRummyWindowController.shared.show() }"))
    #expect(app.contains("rummy.dismissWindow = { Self.closeRummyWindow() }"))
    #expect(app.contains("rummy.requestAttention = { if !NSApp.isActive { NSApp.requestUserAttention(.criticalRequest) } }"))
    #expect(app.contains("rummy.onInviteArrived = { [weak self] room in self?.overlayController?.enqueueRummyInvite(room) }"))
    #expect(app.contains("rummy.onAttention = { [weak self] text in self?.overlayController?.enqueueRummyAttention(text) }"))
    #expect(app.contains("overlayController?.onOpenRummy = { [weak self] matchID in self?.store.rummy.openWindow(focusMatchID: matchID) }"))
    #expect(app.contains("Self.closeRummyWindow() self?.overlayController?.clearRummyInvites() }.start()"),
            "계정 전환 감시자가 아잉 큐브 창·말풍선 큐를 안 내린다")
    #expect(app.contains("CheckRummyWindowController.shared.configure(store: store.rummy, me: { [weak self] in"),
            "창 배선(configure)이 없다 — 창이 스토어 없이 뜬다")
    // 닫기는 창 식별자로 찾는다(창 컨트롤러 공개 표면이 configure·show 뿐이라) — 그 식별자가 창 컨트롤러의 것과 같아야 한다.
    #expect(app.contains("let id = CheckRummyWindowController.frameAutosaveName"))
    #expect(CheckRummyWindowController.frameAutosaveName == "check.rummy.window")
}

// MARK: - #14·#15 메뉴바 점 · 팝오버 배너

/// 없으면: 초대를 받아도 메뉴바 점이 안 켜지고(캐릭터가 없는 사람에게 알릴 곳이 사라진다), 보이스오버가 사유를 말하지 않는다.
@MainActor
@Test
func theMenuBarDotLightsForARummyInvite() throws {
    let reasons = MenuBarDotReasons(rummyInvite: true)
    #expect(!reasons.isEmpty)
    #expect(reasons.accessibilityDescription == "아잉 큐브 초대")
    // 기준선: 아무 사유도 없으면 점이 없다(한 값만 바꿨다).
    #expect(MenuBarDotReasons().isEmpty)
    #expect(MenuBarDotReasons(tetrisInvite: true, rummyInvite: true).accessibilityDescription == "테트리스 신청 · 아잉 큐브 초대")

    let app = try rwMac("CheckApp.swift")
    #expect(app.contains("hasRummyInvite: appDelegate.store.rummy.hasIncomingInvite"), "메뉴바 라벨이 초대를 안 읽는다")
    let menu = try rwMac("CheckMenuView.swift")
    #expect(menu.contains("tetrisInvite: hasTetrisInvite, rummyInvite: hasRummyInvite"))
}

/// 없으면: 팝오버에 초대 배너가 안 서거나(우선순위 줄 누락) 높이 예산에서 빠져 팝오버가 잘리고, [참가]가 서버 참가 없이 창만 연다.
@MainActor
@Test
func thePopoverShowsTheRummyInviteBanner() throws {
    let menu = try rwMac("CheckMenuView.swift")
    #expect(menu.contains("if store.isSignedIn, tetrisBannerInvite != nil { return .tetrisInvite } "
                          + "if store.isSignedIn, rummyBannerInvite != nil { return .rummyInvite }"))
    #expect(menu.contains("case .rummyInvite: return Self.rummyInviteBannerHeight"))
    #expect(CheckMenuView.rummyInviteBannerHeight == CheckMenuView.tetrisInviteBannerHeight)
    #expect(menu.contains("previewRummyInvite ?? store.rummy.incomingInvites.first"))
    // 두 자리(무소속 화면 맨 위 · 헤더 카드 아래) 모두 테트리스 배너 바로 뒤에 선다.
    #expect(rwCount("tetrisInviteBanner rummyInviteBanner", in: menu) == 2)
    #expect(menu.contains("let rummy = store.rummy rummy.join(room.id) rummy.openWindow(focusMatchID: room.id) WindowTopAnchor.dismissMenuPopover()"))
    #expect(menu.contains("store.rummy.decline(room.id)"))
    #expect(RummyInviteText.bannerTitle(name: "보라") == "보라님이 아잉 큐브에 초대했어요")
    #expect(RummyInviteText.bannerTitle(name: "  ") == "누군가님이 아잉 큐브에 초대했어요")
    #expect([RummyInviteText.join, RummyInviteText.decline, RummyInviteText.open] == ["참가", "거절", "열기"])
}

// MARK: - #16 캐릭터 말풍선

/// 없으면: 창을 닫아 둔 사람은 초대도 "내 차례"도 모른다 — 차례 60초가 그대로 흘러 3회 연속 시간 초과면 **기권(판돈 잃음)**.
/// 말풍선을 눌러도 창이 안 열리거나(클릭 자리), 몸체 히트테스트가 말풍선을 놓쳐 클릭이 뒤 앱으로 샌다.
@MainActor
@Test
func theCharacterBubblesCarryRummyInvitesAndTurns() throws {
    // 문구: 설계 §5 "OO님이 아잉 큐브에 초대했어요 · 판돈 N", 캡슐을 넘치면 세 단계로 접힌다(체스·테트리스와 같은 규칙).
    let full = CheckOverlayController.rummyInviteBubbleText(name: "보라", stake: 5)
    #expect(full == "보라님이 아잉 큐브에 초대했어요 · 판돈 5")
    let long = CheckOverlayController.rummyInviteBubbleText(name: String(repeating: "가", count: 40), stake: 10)
    #expect(OverlayMessageBubble.fitsCapsule(long), "긴 이름에서 말풍선 문구가 캡슐을 넘친다: \(long)")
    #expect(long.hasSuffix("판돈 10"))

    // 쪼갠 파일(맥 오버레이 + CheckCore 패널 가시성) — 반쪽 읽기 금지 계약대로 이어 읽는다.
    let overlay = rwCollapsed(V0317ShopTests.stripped(try CheckCoreSourceLayout.joinedSplitSource("CheckOverlayWindow.swift")))
    #expect(overlay.contains("if let rect = rummyInviteBubbleScreenRect(), rect.contains(screenPoint) { return true }"),
            "몸체 히트테스트가 아잉 큐브 말풍선을 모른다")
    #expect(overlay.contains("if let rect = rummyInviteBubbleScreenRect(), rect.contains(location), let target = rummyBubbleTarget() { onOpenRummy?(target.matchID) return }"),
            "말풍선을 눌러도 큐브 창이 안 열린다")
    #expect(overlay.contains("let alive = Set(store.rummy.incomingInvites.map(\\.id))"), "걷힌 초대(차단·만료·거절)를 말풍선이 다시 띄운다")
    #expect(overlay.contains("guard Self.rummyAttentionIsCurrent(in: store.rummy) else { pendingRummyAttention = nil return false }"))
}

// MARK: - #17~#19 미니게임 창: 스페이스 키 등록 · 머리글 입구 · 여는 길

/// 없으면: 미니게임 창을 띄워 둔 채 큐브 창에서 [완료]를 스페이스로 누르면 미니게임 모니터가 먼저 삼키고(등록 누락),
/// 머리글에 입구가 없어 창을 여는 길이 아예 없고, 입구를 눌러도 미니게임 창이 남아 두 창이 겹친다.
@MainActor
@Test
func theMiniGameWindowOpensTheRummyWindow() throws {
    #expect(MiniGameSpaceKey.standaloneWindowIDs.contains("check.rummy.window"))
    #expect(MiniGameSpaceKey.standaloneWindowIDs.contains(CheckRummyWindowController.frameAutosaveName))
    #expect(MiniGameSpaceKey.standaloneWindowIDs.count == 7)

    #expect(MiniGameRummyEntryButton.segmentTitle == "큐브", "설계 §1 입구 버튼 글자")
    #expect(MiniGameRummyEntryButton.title == "아잉 큐브")
    let panel = try rwMac("MiniGamePanel.swift")
    #expect(panel.contains("MiniGameTetrisDuelEntryButton { onTetrisDuel() } MiniGameRummyEntryButton { onRummy() }"),
            "대결 묶음에 큐브 입구가 없다")
    #expect(panel.contains("onRummy: { store.openRummyFromMiniGame() }"))
    #expect(panel.contains("var onRummy: () -> Void = {}"), "기존 머리글 호출부를 지키려면 기본값이 있어야 한다")

    let miniGame = try rwMac("WorkTimerStoreMiniGame.swift")
    #expect(miniGame.contains("func openRummyFromMiniGame() { rummy.openWindow(focusMatchID: nil) closeMiniGamePanel() }"),
            "큐브 창을 먼저 띄우고 미니게임 창을 내려야 한다")
}
