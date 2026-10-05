import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// v0.3.44 — **체스를 창 밖에서 아는 길**. 0.3.44 초안에는 그 길이 **하나도 없었다**.
//
// 사실 관계(2026-10-05 실측):
//   · 체스 폴링은 `pollTick` 머리에서 `isWindowVisible` 을 요구한다(규약 ③ · V0343 ⑦ 이 못 박았다).
//     체스 창을 여는 길은 미니게임 창 머리글 **하나뿐**이고 그 입구는 판이 도는 중에는 숨는다.
//   · 그래서 창이 닫혀 있으면 체스 요청이 **한 건도** 안 나간다.
//   · 받은 신청의 TTL 은 60초이고, 서버는 `chess_invite` 푸시를 '맥에서 근무 중'(열린 세션 + 2분 내 입력)이면
//     **suppressed** 로 적는다(push_pipeline.sql) — 폰 푸시가 눌린다.
//   · 스토어는 `onInviteArrived`·`onAttention` 두 문을 **실제로 부르는데**(applyInvite · noteMatchProgress)
//     `CheckApp.wireChess()` 가 둘을 아무 데도 안 물렸고, `CheckMenuView`·`CheckOverlayWindow` 에 'chess' 가 0회였다.
//   → 근무 중 맥을 쓰는 사람에게 온 체스 신청은 **아무 데도 전달되지 않은 채** 만료되고, 신청자는
//     "상대가 응답하지 않았어요" 를 본다. 진행 중 판에서 창을 닫으면 "내 차례" 가 한 번도 안 와서
//     (체스는 오목의 자동 착수 장치를 전부 버렸다 — DECISIONS B4) 5분 시계가 그대로 흘러 판돈을 잃는다.
//
// 여기서 재는 것은 그 길 **넷**이다: ① 소켓 신호 라우팅 ② 창 없이 도는 따라잡기 ③ 캐릭터 말풍선 큐
// ④ 메뉴바 점 · 팝오버 배너.

private let crT0 = Date(timeIntervalSince1970: 1_800_000_000)
private let crMe = "00000000-0000-0000-0000-0000000000a1"

private func crSubscribedLink() -> RealtimeLink {
    var link = RealtimeLink(transportAvailable: true)
    _ = link.apply(.signedIn(accessToken: "tok"), now: crT0, jitter: { $0 })
    _ = link.apply(.transport(.joined), now: crT0, jitter: { $0 })
    return link
}

// MARK: - ① 소켓 신호: 'chess' 는 take_pokes 로 새지 않는다

/// 없으면: `chess` 가 '모르는 이름' 과 같은 갈래로 떨어져 **수마다 take_pokes 가 한 번씩 더** 나가고
/// (블리츠 한 판 40수 = 왕복 80회 · 두 사람 모두에게) 소켓은 체스 상태를 한 번도 당기지 않는다.
@Test
func theChessRingIsItsOwnBranchAndNotATakePokesDrain() {
    #expect(RealtimeLinkConstants.chessBroadcastEvent == "chess",
            "서버 `chess__ring` 의 realtime.send(…, 'chess', …) 와 글자가 달라졌다")
    #expect(RealtimeLinkConstants.chessBroadcastEvent != RealtimeLinkConstants.gomokuBroadcastEvent)

    var link = crSubscribedLink()
    #expect(link.apply(.transport(.broadcast(event: "chess")), now: crT0 + 1, jitter: { $0 }) == [.chessSignal])
    // 체스 신호도 소켓이 살아 있다는 증거다(좀비 판정 시계를 민다).
    #expect(link.state == .subscribed(since: crT0, lastHeardAt: crT0 + 1))

    // ★ 기준선이 갈린다: 모르는 이름은 **예전 그대로** drain 이고 오목은 오목 갈래다.
    //   셋이 같은 답이면 위 단언이 아무것도 재지 않는다(그게 바로 수리 전 상태였다).
    let unknown = link.apply(.transport(.broadcast(event: "모르는이름")), now: crT0 + 2, jitter: { $0 })
    let gomoku = link.apply(.transport(.broadcast(event: "gomoku")), now: crT0 + 3, jitter: { $0 })
    let read = link.apply(.transport(.broadcast(event: "message_read")), now: crT0 + 4, jitter: { $0 })
    #expect(unknown == [.drain])
    #expect(gomoku == [.gomokuSignal])
    #expect(read == [.messageReadSignal])
    #expect(Set([[RealtimeEffect.chessSignal], unknown, gomoku, read].map { "\($0)" }).count == 4,
            "네 이름이 네 갈래로 안 갈린다 — 체스가 또 drain 으로 샌다")
    // 문자 그대로만 가른다(대소문자가 다르면 체스가 아니다 — 모르는 이름은 예전처럼 drain).
    #expect(link.apply(.transport(.broadcast(event: "CHESS")), now: crT0 + 5, jitter: { $0 }) == [.drain])

    // 구독 전에는 어떤 이름이든 아무것도 시키지 않는다.
    var connecting = RealtimeLink(transportAvailable: true)
    _ = connecting.apply(.signedIn(accessToken: "tok"), now: crT0, jitter: { $0 })
    #expect(connecting.apply(.transport(.broadcast(event: "chess")), now: crT0 + 1, jitter: { $0 }) == [])

    // 프레임 해석이 이름을 그대로 넘긴다(서버 페이로드 {v,m,s} + realtime 이 붙이는 id).
    let text = String(decoding: try! JSONSerialization.data(withJSONObject: [
        "topic": "realtime:poke:me", "event": "broadcast",
        "payload": ["event": "chess", "type": "broadcast",
                    "payload": ["v": 1, "m": "c0de0000-0000-4000-8000-000000000a07", "s": 7]]
    ]), as: UTF8.self)
    #expect(RealtimeFrame.decode(text: text, channel: "poke:me", joinRef: "1") == .broadcast(event: "chess"))
}

/// 라우팅 배선이 실제로 체스 스토어까지 간다 — 그리고 **take_pokes 를 부르지 않는다**.
@MainActor
@Test(.gomokuDefaultsCleanup)
func theChessSignalRefetchesChessAndNeverConsumesPokes() async {
    let host = "v0345-rt-\(UUID().uuidString.prefix(8))".lowercased()
    GomokuStubProtocol.register(host: host) { rpc, _, _ in
        switch rpc {
        case "chess_lobby":
            return GomokuStubProtocol.Reply(body: #"{"status":"ok","users":[],"matches":[]}"#)
        case "gomoku_inbox":
            return GomokuStubProtocol.Reply(body: #"{"status":"ok","incoming":[],"outgoing":null}"#)
        default:
            return nil
        }
    }
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!, anonKey: "anon-test-key",
        session: GomokuStubProtocol.session())
    let transport = FakeRealtimeTransport()
    let store = WorkTimerStore(
        service: service, environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: GomokuTestDefaults.make("v0345-rt"), workspaceNotifications: nil,
        realtimeTransport: transport)
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: crMe)
    store.startedAt = Date()                      // 소비할 수 있는 맥(그래도 체스는 take_pokes 를 안 쓴다)
    store.startRealtimeIfPossible()
    transport.emit(.joined)

    func lobby() -> Int { GomokuStubProtocol.count(host: host, rpc: "chess_lobby") }
    func pokes() -> Int { GomokuStubProtocol.count(host: host, rpc: "take_pokes") }
    // 조인 직후 따라잡기가 체스 로비를 한 번 본다(소켓이 내려가 있던 사이에 온 신청·수를 따라잡는 유일한 계기다).
    await crWait { lobby() >= 1 }
    #expect(lobby() == 1, "조인 따라잡기가 체스를 보지 않았다 — 끊겼던 사이의 신청을 영영 모른다")
    let afterJoin = pokes()

    // 체스 초인종 → 체스 재조회 1회, take_pokes 0회.
    store.chess.lastLobbyRequestAt = .distantPast
    transport.emit(.broadcast(event: "chess"))
    await crWait { lobby() >= 2 }
    #expect(lobby() == 2, "체스 초인종이 체스 상태를 안 당긴다")
    #expect(pokes() == afterJoin, "체스 초인종마다 take_pokes 가 한 번씩 더 나간다 — 무료 플랜 예산이 그 자리에서 샌다")

    // ★ 기준선이 갈린다: **모르는 이름**은 예전처럼 take_pokes 로 간다(그래야 위 0 이 뜻을 가진다).
    transport.emit(.broadcast(event: "모르는이름"))
    await crWait { pokes() > afterJoin }
    #expect(pokes() == afterJoin + 1, "모르는 이름이 take_pokes 로 안 간다 — 이 시험의 대조가 죽었다")
    store.chess.reset()
}

// MARK: - ② 창이 없어도 따라잡기가 돈다

/// 없으면: 창을 안 연 사람에게 체스 요청이 **한 건도** 안 나가 받은 신청을 알 길이 전혀 없다(TTL 60초).
@MainActor
@Test(.gomokuDefaultsCleanup)
func chessCatchUpRunsWithTheWindowClosedUnlikePolling() async throws {
    let (store, host) = try crStoreWithIncomingInvite("closed")
    #expect(!store.isWindowVisible, "전제: 체스 창이 닫혀 있다")

    // ★ 기준선 ①: 폴링은 창이 없으면 **아무것도 안 한다**(V0343 ⑦ 이 못 박은 규약 — 여기서 그 반쪽을 쓴다).
    await store.pollTick(at: store.clock().addingTimeInterval(600))
    #expect(GomokuStubProtocol.count(host: host, rpc: "chess_lobby") == 0,
            "창이 닫혔는데 폴링이 요청을 냈다 — 아래 대조가 아무것도 안 잰다")

    // ★ 기준선 ②: 소켓 신호는 **창과 무관하게** 돈다.
    var arrived: [ChessInvite] = []
    store.onInviteArrived = { arrived.append($0) }
    store.handleSignal()
    await crWait { store.incoming != nil }
    #expect(GomokuStubProtocol.count(host: host, rpc: "chess_lobby") == 1,
            "창이 닫혀 있으면 소켓 신호도 아무것도 안 당긴다 — 신청을 아는 길이 0 이다")
    let invite = try #require(store.incoming)
    #expect(invite.stake == 5)
    #expect(store.visibleIncoming?.id == invite.id, "배너·메뉴바 점이 읽는 자리가 비어 있다")
    #expect(arrived.map(\.id) == [invite.id], "`onInviteArrived` 가 한 번도 안 불렸다 — 말풍선 큐가 영영 빈다")
    #expect(!store.isWindowVisible, "따라잡기가 창을 띄워 버렸다(신청은 창을 열지 않는다)")

    // 같은 신청을 다시 읽어도 문은 **한 번만** 열린다(말풍선이 두 번 뜨지 않게).
    store.lastLobbyRequestAt = .distantPast
    store.handleSignal()
    await crWait { GomokuStubProtocol.count(host: host, rpc: "chess_lobby") >= 2 }
    #expect(arrived.count == 1, "같은 신청에 말풍선 문이 두 번 열렸다")

    // 팝오버를 여는 계기도 같은 조회를 쓴다(스로틀 안에서는 안 쏜다 — 여닫는 것만으로 요청이 새면 안 된다).
    let before = GomokuStubProtocol.count(host: host, rpc: "chess_lobby")
    store.refreshLobbyIfStale()
    await crWait { GomokuStubProtocol.count(host: host, rpc: "chess_lobby") > before }
    #expect(GomokuStubProtocol.count(host: host, rpc: "chess_lobby") == before + 1,
            "팝오버 열기 계기가 체스 로비를 안 본다 — 배너·메뉴바 점이 낡은 채 남는다")
    store.refreshLobbyIfStale()
    for _ in 0..<40 { try? await Task.sleep(for: .milliseconds(5)) }
    #expect(GomokuStubProtocol.count(host: host, rpc: "chess_lobby") == before + 1,
            "팝오버를 여닫는 것만으로 요청이 샌다 — 스로틀이 없다")
    store.reset()
}

// MARK: - ③ 캐릭터 말풍선 큐 (신청 · 내 차례)

/// 없으면: 스토어가 부르는 문 둘이 아무 데도 안 물려 캐릭터가 '방금 누가 불렀다' 를 말하지 않는다.
@MainActor
@Test
func theChessInviteAndTurnBubblesReachTheCharacterQueue() throws {
    let (engine, controller, store) = crOverlay()
    defer {
        controller.clearChessInvites()
        controller.updateWorking(false)
    }
    let invite = crInvite(id: "invite-1", expiresIn: 50)
    store.chess.incoming = invite
    controller.enqueueChessInvite(invite)
    controller.enqueueChessInvite(invite)
    #expect(controller.chessInviteQueue.count == 1, "같은 신청이 두 번 들어갔다")

    #expect(controller.showNextChessInviteBubble())
    let text = CheckOverlayController.chessInviteBubbleText(name: "민수", stake: 5)
    #expect(engine.greetingText == text)
    #expect(text.contains("체스"), "말풍선이 어느 게임인지 말하지 않는다 — 오목 신청과 구별되지 않는다")
    #expect(text != CheckOverlayController.gomokuInviteBubbleText(name: "민수", stake: 5),
            "체스 신청 말풍선이 오목과 같은 문구다")
    #expect(controller.chessInviteQueue.isEmpty)
    #expect(controller.shownChessInvite?.matchID == "invite-1")

    // 열 곳이 배선되기 전에는 누를 자리를 만들지 않는다(화살표도 안 붙는다).
    #expect(controller.chessInviteBubbleScreenRect() == nil, "배선 전인데 클릭 자리가 생겼다")
    controller.onOpenChess = { _ in }
    #expect(controller.chessInviteBubbleScreenRect() != nil, "배선했는데 체스 말풍선을 누를 자리가 없다")
    #expect(controller.chessBubbleMatchID() == "invite-1")
    engine.greetingText = nil
    #expect(controller.chessInviteBubbleScreenRect() == nil, "말풍선이 사라졌는데 클릭 자리가 남았다")

    // 만료·처리된 신청은 뒤늦게 뜨지 않는다(큐에서 버린다).
    let stale = crInvite(id: "stale", expiresIn: -1)
    store.chess.incoming = stale
    controller.enqueueChessInvite(stale)
    #expect(controller.showNextChessInviteBubble() == false)
    #expect(controller.chessInviteQueue.isEmpty, "만료된 신청이 큐에 남아 다음 자리를 막는다")
    let handled = crInvite(id: "handled", expiresIn: 50)
    store.chess.incoming = nil                     // 그사이 배너로 수락·거절했다
    controller.enqueueChessInvite(handled)
    #expect(controller.showNextChessInviteBubble() == false)
    #expect(controller.chessInviteQueue.isEmpty, "이미 처리된 신청이 뒤늦게 말풍선으로 뜬다")

    // 떠 있는 말풍선 뒤에서는 **기다린다**(못 띄운 건을 소비하지 않는다 — 소비하면 그 신청은 조용히 만료된다).
    engine.showBubble("다른 안내", seconds: 60)
    let waiting = crInvite(id: "waiting", expiresIn: 50)
    store.chess.incoming = waiting
    controller.enqueueChessInvite(waiting)
    #expect(controller.showNextChessInviteBubble() == false)
    #expect(controller.chessInviteQueue.map(\.id) == ["waiting"], "못 띄운 신청을 큐에서 뺐다")
    #expect(engine.greetingText == "다른 안내", "체스 말풍선이 떠 있던 안내를 덮었다")
}

/// 내 차례 말풍선 — **창이 안 보일 때만** 뜨고, 판이 넘어갔으면 버린다.
@MainActor
@Test
func theChessTurnBubbleOnlyShowsWhileTheWindowIsHidden() throws {
    let (engine, controller, store) = crOverlay()
    defer {
        controller.clearChessInvites()
        controller.updateWorking(false)
    }
    let chess = store.chess
    chess.match = crMatch(ply: 4, turn: .white, myColor: .white)
    chess.isWindowVisible = false
    let attention = ChessAttention(kind: .myTurn, matchID: "match-1", opponentName: "민수", plyCount: 4)
    #expect(CheckOverlayController.chessAttentionIsCurrent(attention, in: chess))

    controller.enqueueChessAttention(attention)
    #expect(controller.showPendingChessAttentionBubble())
    let text = CheckOverlayController.chessAttentionBubbleText(attention)
    #expect(engine.greetingText == text)
    #expect(text.contains("체스"), "차례 말풍선이 어느 게임인지 말하지 않는다")
    #expect(controller.shownChessAttention?.matchID == "match-1")
    #expect(controller.pendingChessAttention == nil)
    controller.onOpenChess = { _ in }
    #expect(controller.chessBubbleMatchID() == "match-1", "차례 말풍선을 눌러도 그 판을 열 수 없다")

    // ★ 기준선 셋이 갈린다: 창이 보이면 · 판이 한 수 넘어갔으면 · 상대 차례면 **거짓**이다.
    chess.isWindowVisible = true
    #expect(!CheckOverlayController.chessAttentionIsCurrent(attention, in: chess), "창이 보이는데도 말풍선을 띄운다")
    chess.isWindowVisible = false
    chess.match = crMatch(ply: 5, turn: .black, myColor: .white)
    #expect(!CheckOverlayController.chessAttentionIsCurrent(attention, in: chess),
            "판이 넘어간 뒤에도 '내 차례예요' 를 띄운다 — 두 수 전의 거짓이다")
    chess.match = crMatch(ply: 4, turn: .black, myColor: .white)
    #expect(!CheckOverlayController.chessAttentionIsCurrent(attention, in: chess), "상대 차례인데 내 차례라고 한다")
    chess.match = nil
    #expect(!CheckOverlayController.chessAttentionIsCurrent(attention, in: chess))

    // 사실이 아니면 **버린다**(기다리지 않는다 — 차례 알림은 가장 최근 것만 뜻이 있다).
    engine.greetingText = nil
    controller.enqueueChessAttention(attention)
    #expect(controller.showPendingChessAttentionBubble() == false)
    #expect(controller.pendingChessAttention == nil, "사실이 아닌 차례 알림이 큐에 남았다")
    #expect(engine.greetingText == nil)

    // 판이 막 시작된 알림은 다른 문구다(두 갈래가 같으면 사용자는 무엇이 일어났는지 모른다).
    let started = ChessAttention(kind: .matchStarted, matchID: "match-1", opponentName: "민수", plyCount: 0)
    #expect(CheckOverlayController.chessAttentionBubbleText(started)
            != CheckOverlayController.chessAttentionBubbleText(attention))
}

// MARK: - ④ 메뉴바 점 · 팝오버 배너

/// 없으면: 체스 신청이 메뉴바 점에도 팝오버에도 안 뜬다 — 캐릭터를 꺼 둔 사람에게는 알 길이 **0** 이다.
@MainActor
@Test
func theMenuBarDotAndThePopoverBannerKnowAboutChessInvites() throws {
    // 점 사유: 켜지고, 말하고, 끄면 **예전과 바이트가 같다**.
    #expect(MenuBarDotReasons().isEmpty)
    #expect(!MenuBarDotReasons(chessInvite: true).isEmpty, "체스 신청이 점을 안 켠다")
    #expect(MenuBarDotReasons(chessInvite: true).accessibilityDescription == "체스 신청")
    // ★ 기준선 갈림: 오목과 **다른 말**을 하고, 둘이 함께 켜지면 순서대로 이어 말한다.
    #expect(MenuBarDotReasons.chessInviteText != MenuBarDotReasons.gomokuInviteText)
    #expect(MenuBarDotReasons(unreadMessages: true, gomokuInvite: true, chessInvite: true)
            .accessibilityDescription == "새 메시지 · 오목 신청 · 체스 신청")
    #expect(MenuBarDotReasons(gomokuInvite: true).accessibilityDescription == "오목 신청")
    // 라벨이 그 사유를 점으로 옮긴다(깃발만 있고 점이 안 켜지는 경우를 가른다).
    let off = WorkStatusSnapshot(status: .offWork, elapsedSeconds: 0)
    #expect(MenuBarStatusLabel(snapshot: off, title: "오프", hasChessInvite: true).dotReasons.chessInvite)
    #expect(!MenuBarStatusLabel(snapshot: off, title: "오프").dotReasons.chessInvite)
    #expect(MenuBarStatusLabel(snapshot: off, title: "오프", hasChessInvite: true).dotReasons.isEmpty == false)
    #expect(MenuBarStatusLabel(snapshot: off, title: "오프").dotReasons.isEmpty,
            "아무 사유도 없는데 점이 켜진다 — 예전 그림과 바이트가 달라진다")

    // 팝오버 배너: 그려지고(잉크), 오목 배너와 **다른 그림**이고, 둘이 함께 오면 오목이 이긴다(배너는 한 번에 하나).
    let store = crMenuStore()
    let invite = crInvite(id: "invite-1", expiresIn: 48)
    let withChess = try crBitmap(CheckMenuView(store: store, previewChessInvite: invite))
    let without = try crBitmap(CheckMenuView(store: store))
    print("[배너] 체스 배너 높이 \(Double(withChess.pixelsHigh) / 2)pt · 없을 때 \(Double(without.pixelsHigh) / 2)pt")
    #expect(withChess.pixelsHigh > without.pixelsHigh,
            "체스 신청 배너를 띄웠는데 팝오버가 한 픽셀도 안 자랐다 — 배너가 안 그려진다")
    let grew = Double(withChess.pixelsHigh - without.pixelsHigh) / 2
    #expect(abs(grew - Double(CheckMenuView.chessInviteBannerHeight)) < 24,
            "배너 높이 예산(\(CheckMenuView.chessInviteBannerHeight)pt)과 실제(\(grew)pt)가 크게 다르다 — 목록 행수 예산이 어긋난다")
    #expect(CheckMenuView.chessInviteBannerHeight == CheckMenuView.gomokuInviteBannerHeight,
            "두 배너가 같은 모양인데 높이 예산이 다르다")

    // 배너 자체도 오목과 다른 그림이다(같으면 어느 게임의 신청인지 모른다).
    let chessBanner = try crBitmap(ChessInviteBanner(invite: invite, onAccept: {}, onDecline: {}, onOpen: {})
        .frame(width: 316).background(CheckTheme.background))
    let gomokuBanner = try crBitmap(GomokuInviteBanner(
        invite: GomokuInvite(id: "invite-1", peer: crGomokuPeer, stake: 5,
                             expiresAt: invite.expiresAt),
        onAccept: {}, onDecline: {}, onOpen: {})
        .frame(width: 316).background(CheckTheme.background))
    let box = CGRect(x: 0, y: 0, width: 316,
                     height: Double(min(chessBanner.pixelsHigh, gomokuBanner.pixelsHigh)) / 2)
    #expect(crMaxChannelDifference(chessBanner, gomokuBanner, rect: box) > 60,
            "체스 배너와 오목 배너가 같은 그림이다")
    #expect(ChessText.inviteBannerTitle(name: "민수").contains("체스"), "배너 제목이 어느 게임인지 말하지 않는다")
}

// MARK: - 소스 계약 (문 둘이 **물려 있는가**)

/// 없으면: 스토어 쪽 문이 옵셔널이라 `?.` 가 삼켜 컴파일·스토어 테스트가 조용히 초록이다.
@Test
func theAppWiresTheChessInviteAndAttentionDoors() throws {
    let app = crCollapsed(try V0317ShopTests.stripped(V0317ShopTests.source("CheckApp.swift")))
    #expect(app.contains("chess.onInviteArrived = { [weak self] invite in self?.overlayController?.enqueueChessInvite(invite) }"),
            "받은 신청 문이 말풍선 큐에 안 물렸다 — 신청이 아무 데도 전달되지 않은 채 60초에 만료된다")
    #expect(app.contains("chess.onAttention = { [weak self] attention in self?.overlayController?.enqueueChessAttention(attention) }"),
            "내 차례 문이 말풍선 큐에 안 물렸다 — 창을 닫으면 판돈이 걸린 판을 조용히 시간패한다")
    #expect(app.contains("overlayController?.onOpenChess = { [weak self] matchID in self?.store.chess.openWindow(focusMatchID: matchID) }"),
            "말풍선을 눌러도 그 대국의 창이 안 열린다(화살표도 안 붙는다)")
    #expect(app.contains("self?.overlayController?.clearChessInvites()"),
            "계정 전환에서 앞 계정의 체스 신청 말풍선을 안 비운다")
    #expect(app.contains("hasChessInvite: appDelegate.store.chess.visibleIncoming != nil"),
            "메뉴바 점이 체스 신청을 안 본다")
    // ★ `wireChess()` 는 오버레이 컨트롤러를 만든 **뒤에** 와야 한다(먼저 이으면 첫 신청이 받을 곳 없이 사라진다).
    let overlayLine = try #require(app.range(of: "overlayController = CheckOverlayController("))
    let wireLine = try #require(app.range(of: "wireChess()"))
    #expect(overlayLine.lowerBound < wireLine.lowerBound,
            "wireChess() 가 오버레이 컨트롤러보다 먼저다 — 첫 신청이 받을 곳 없이 사라진다")

    // 라우팅·계기 세 줄.
    let realtime = crCollapsed(try V0317ShopTests.stripped(V0317ShopTests.source("WorkTimerStoreRealtime.swift")))
    #expect(realtime.contains("case .chessSignal:"), "체스 신호 가지가 없다 — 초인종마다 take_pokes 가 샌다")
    #expect(realtime.contains("chess.handleSignal()"))
    #expect(realtime.contains("gomoku.realtimeDidJoin() chess.realtimeDidJoin()"),
            "조인 직후 따라잡기에 체스가 없다")
    let owner = crCollapsed(try V0317ShopTests.stripped(V0317ShopTests.source("WorkTimerStore.swift")))
    #expect(owner.contains("chess.refreshLobbyIfStale()"), "팝오버 열기 계기에 체스가 없다")

    // 팝오버는 배너를 **두 자리**(무소속 · 메인)에 모두 그린다 — 한 곳만 두면 무소속 사용자가 못 본다.
    let menu = crCollapsed(try V0317ShopTests.stripped(V0317ShopTests.source("CheckMenuView.swift")))
    #expect(crCount("chessInviteBanner", in: menu) >= 3,
            "체스 배너를 그리는 자리가 모자란다(\(crCount("chessInviteBanner", in: menu))곳) — 무소속 화면이나 메인 화면 하나가 빠졌다")
    #expect(menu.contains("if store.isSignedIn, chessBannerInvite != nil { return .chessInvite }"))
    #expect(menu.contains("case .chessInvite: return Self.chessInviteBannerHeight"))
}

// MARK: - 헬퍼

private enum CRError: Error { case failed }

private let crPeer = ChessUser(
    id: "00000000-0000-0000-0000-00000000000b", displayName: "민수", avatarURL: nil,
    characterID: "fox", isWorking: true, isCapable: true, inMatch: false)

private let crGomokuPeer = GomokuUser(
    id: "00000000-0000-0000-0000-00000000000b", displayName: "민수", avatarURL: nil,
    characterID: "fox", isWorking: true, isCapable: true, inMatch: false)

private func crInvite(id: String, expiresIn seconds: TimeInterval) -> ChessInvite {
    ChessInvite(id: id, peer: crPeer, stake: 5, expiresAt: Date().addingTimeInterval(seconds))
}

@MainActor
private func crMatch(ply: Int, turn: ChessColor?, myColor: ChessColor) -> ChessMatchState {
    let fen = "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"
    return ChessMatchState(
        id: "match-1", stake: 5, myColor: myColor, opponent: crPeer, fen: fen,
        position: ChessPosition(fen: fen), plyCount: ply, turn: turn, lastMove: nil, moves: [],
        clock: .initial, isInCheck: false, legalMoves: [], isFinished: false, outcome: nil,
        endReason: nil, rubyDelta: nil, drawOfferBy: nil, drawOfferedByMe: false)
}

/// 말풍선 큐 검증용 오버레이(공유 인스턴스가 아니다). 스토어를 함께 돌려준다 —
/// 신청 말풍선은 **스토어의 받은 신청에 아직 있는 것만** 띄운다.
@MainActor
private func crOverlay() -> (ReactionEngine, CheckOverlayController, WorkTimerStore) {
    let store = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
        defaults: crDefaults("v0345-chess-overlay"), workspaceNotifications: nil)
    let engine = ReactionEngine(clock: { Date(timeIntervalSince1970: 900_000) })
    let controller = CheckOverlayController(
        store: store, notificationCenter: NotificationCenter(), engine: engine,
        defaults: crDefaults("v0345-chess-overlay"), workspaceNotifications: nil)
    return (engine, controller, store)
}

/// 받은 신청 하나가 떠 있는 체스 스토어 + 그 스텁 호스트. `chess_lobby` 가 신청 id 를 말하고
/// `chess_state` 가 그 신청의 내용(상대·판돈·만료)을 채운다 — 실서버 두 왕복과 같은 모양이다.
@MainActor
private func crStoreWithIncomingInvite(_ label: String) throws -> (ChessStore, String) {
    let host = "v0345-reach-\(label)-\(UUID().uuidString.prefix(8))".lowercased()
    let inviteID = "c0de0000-0000-4000-8000-0000000000ff"
    let nowMs = Date().timeIntervalSince1970 * 1000
    let lobby = """
        {"status":"ok","server_now_ms":\(Int(nowMs)),"initial_ms":300000,"increment_ms":3000,\
        "grace_ms":2000,"invite_ttl_seconds":60,"users":[],"matches":[],\
        "me":{"ruby_balance":100,"wins":0,"losses":0,"draws":0,"active_match_id":null,\
        "incoming_match_id":"\(inviteID)","outgoing_match_id":null}}
        """
    let state = """
        {"status":"ok","server_now_ms":\(Int(nowMs)),\
        "match":{"id":"\(inviteID)","status":"pending","stake":5,\
        "white":"\(crMe)","black":"\(crPeer.id)","challenger":"\(crPeer.id)","opponent":"\(crMe)",\
        "ply_count":0,"fen":"rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1","turn":"white",\
        "invite_expires_ms":\(Int(nowMs + 48_000))},\
        "my_color":"white","opponent":{"user_id":"\(crPeer.id)","display_name":"민수","character":"fox"},\
        "moves":[],"in_check":null,"legal_moves":null,"ruby_balance":100}
        """
    GomokuStubProtocol.register(host: host) { rpc, _, _ in
        switch rpc {
        case "chess_lobby": return GomokuStubProtocol.Reply(body: lobby)
        case "chess_state": return GomokuStubProtocol.Reply(body: state)
        default: return nil
        }
    }
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!, anonKey: "anon-test-key",
        session: GomokuStubProtocol.session())
    let owner = WorkTimerStore(
        service: service, environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: crDefaults("v0345-chess-reach"), workspaceNotifications: nil)
    owner.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: crMe)
    CRRetention.stores.append(owner)
    let chess = ChessStore(host: owner)
    chess.pollStepSeconds = 3_600
    return (chess, host)
}

@MainActor
private enum CRRetention {
    /// `WorkTimerStore` 는 체스 스토어를 **약참조**로 들린다 — 버리면 요청이 한 건도 안 나간다.
    static var stores: [WorkTimerStore] = []
}

@MainActor
private func crMenuStore() -> WorkTimerStore {
    let store = WorkTimerStore(
        environment: ["CHECK_SUPABASE_ANON_KEY": "local-test-key"],
        defaults: crDefaults("v0345-chess-menu"), workspaceNotifications: nil)
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: crMe)
    store.currentTeamID = "11111111-1111-1111-1111-111111111111"
    store.teamName = "아잉팀"
    store.isMenuPresented = true
    return store
}

private func crDefaults(_ name: String) -> UserDefaults {
    let path = CheckTestScratch.suitePath(named: name)
    let defaults = UserDefaults(suiteName: path)!
    defaults.removePersistentDomain(forName: path)
    return defaults
}

@MainActor
private func crWait(_ resumes: Int = 2_000, _ condition: @MainActor () -> Bool) async {
    for _ in 0..<resumes {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
}

@MainActor
private func crBitmap(_ view: some View) throws -> NSBitmapImageRep {
    let renderer = ImageRenderer(content: view.fixedSize())
    renderer.scale = 2
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff) else { throw CRError.failed }
    return bitmap
}

private func crMaxChannelDifference(_ lhs: NSBitmapImageRep, _ rhs: NSBitmapImageRep, rect: CGRect) -> Int {
    guard let a = lhs.bitmapData, let b = rhs.bitmapData,
          lhs.pixelsWide == rhs.pixelsWide else { return 255 }
    let spp = lhs.samplesPerPixel, bpr = lhs.bytesPerRow
    let x0 = max(0, Int(rect.minX * 2)), x1 = min(lhs.pixelsWide - 1, Int(rect.maxX * 2))
    let y0 = max(0, Int(rect.minY * 2))
    let y1 = min(min(lhs.pixelsHigh, rhs.pixelsHigh) - 1, Int(rect.maxY * 2))
    guard x0 <= x1, y0 <= y1 else { return 255 }
    var worst = 0
    for y in y0...y1 {
        for x in x0...x1 {
            let offset = y * bpr + x * spp
            for channel in 0..<min(3, spp) {
                worst = max(worst, abs(Int(a[offset + channel]) - Int(b[offset + channel])))
            }
        }
    }
    return worst
}

/// 걷어낸 소스에서 줄바꿈을 한 칸으로 접는다(소스 계약 비교용 — 다른 파일의 것은 private 이라 복사).
private func crCollapsed(_ source: String) -> String {
    source.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
}

private func crCount(_ needle: String, in source: String) -> Int {
    guard !needle.isEmpty else { return 0 }
    var count = 0
    var rest = Substring(source)
    while let found = rest.range(of: needle) {
        count += 1
        rest = rest[found.upperBound...]
    }
    return count
}
