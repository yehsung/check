import Foundation
import Testing
@testable import check
@testable import CheckCore

// v0.3.31 M4 — 두 번째 신고: "이미 읽은 메시지인데도 메시지 아이콘 옆에 점이 자꾸 생긴다."
//
// 0.3.29 원인(대조군 CtlM4Tests d1·d2·d3 — main 사본에서 셋 다 빨강): 읽음 기록 `messageReadStamps` 가 **메모리 전용 · 로컬 시계**였다.
//  d1 재실행하면 도장이 사라져 받은 대화마다 점 · d2 대화를 연 채 받은 말은 createdAt > 도장이라 닫으면 점 · d3 맥 시계가 2분 느리면 방금 읽은 것도 점.
// 1차 묶음(M1)이 점을 서버 읽음 경계로 옮겼고(수정 전 mobile-int 대조군 pre_d3 초록), **남은 틈은 d2 의 변형**이었다 —
// 떠 있는 팝오버에서 `isMenuPresented` 가 false 로 남는 순서에서는 보고 있던 대화의 새 말이 읽음으로 안 올라가 닫으면 점이 됐다
// (CtlPreM4Tests pre2: mark 0). 이 파일은 신고 기준 여섯 항목을 **서버 경계를 흉내 내는 스텁**(읽음 처리가 실제로 경계를 옮겨야 요약이 0 이 된다)으로 잰다.

private typealias Fx = MessageReadFixture

/// 서버 읽음 경계 모형. 받은 메시지 id 들(순서대로)과 "여기까지 읽음" 자리. 요약·이력의 unread 는 이 경계에서만 나온다 —
/// 클라가 읽음 처리를 **실제로** 그 id 까지 보내야 점이 꺼진다(낙관 표시만으로 초록이 되지 않게).
final class V0331ReadServer: @unchecked Sendable {
    private let lock = NSLock()
    private var received: [(id: String, peer: String, epoch: Int)] = []
    private var readThrough: [String: Int] = [:]   // peer → received 안의 자리
    private(set) var markCalls: [String] = []

    func receive(_ id: String, from peer: String, epoch: Int) {
        lock.lock(); received.append((id, peer, epoch)); lock.unlock()
    }

    func readOnAnotherDevice(peer: String) {
        lock.lock()
        if let last = received.lastIndex(where: { $0.peer == peer }) { readThrough[peer] = last }
        lock.unlock()
    }

    private func isUnread(_ index: Int) -> Bool {
        guard let through = readThrough[received[index].peer] else { return true }
        return index > through
    }

    func handler() -> MessageReadStubProtocol.Handler {
        { [self] call, _ in
            lock.lock(); defer { lock.unlock() }
            switch call.rpc {
            case "message_history_with_reads":
                let rows = received.indices.map { i in
                    Fx.readsRow(id: received[i].id, peer: received[i].peer, isMine: false, epoch: received[i].epoch, unread: isUnread(i))
                }
                return Fx.historyReply(rows)
            case "message_unread_summary":
                var counts: [String: Int] = [:]
                for i in received.indices where isUnread(i) { counts[received[i].peer, default: 0] += 1 }
                return Fx.summaryReply(counts.sorted { $0.key < $1.key }.map { ($0.key, $0.value) })
            case "mark_messages_read":
                let json = call.json
                guard let peer = json["p_peer"] as? String else { return Fx.markReply(advanced: false) }
                let through = json["p_through"] as? String
                markCalls.append(through ?? "nil")
                if let through, let index = received.firstIndex(where: { $0.id == through && $0.peer == peer }) {
                    readThrough[peer] = max(readThrough[peer] ?? -1, index)
                }
                return Fx.markReply()
            case "take_pokes":
                // 아직 소비 안 된(= 이 테스트가 방금 받은) 마지막 한 건.
                guard let last = received.last else { return MessageReadStubProtocol.Reply(body: "[]") }
                return MessageReadStubProtocol.Reply(body: Fx.json([Fx.takenMessageRow(id: last.id, from: last.peer, epoch: last.epoch)]))
            default: return nil
            }
        }
    }
}

@MainActor
private func v0331DotCount(_ host: String, _ rpc: String) -> Int {
    MessageReadStubProtocol.count(host: host, rpc: rpc)
}

// MARK: 1. 읽은 뒤 앱 재실행 → 점 없음

@MainActor
@Test(.gomokuDefaultsCleanup)
func 읽은_뒤_재실행해도_서버_경계로_점이_없다() async {
    let epoch = Int(Date().timeIntervalSince1970)
    let server = V0331ReadServer()
    server.receive("m1", from: Fx.peerA, epoch: epoch - 300)
    server.receive("m2", from: Fx.peerA, epoch: epoch - 200)

    // 첫 실행: 대화를 열어 읽는다.
    let (first, _) = makeMessageReadStore("dot-restart-1", handler: server.handler())
    first.isMenuPresented = true
    first.messageConversationViewDidAppear(UUID())
    first.openMessagePanel(peer: Fx.peerA)
    await messageReadWait { server.markCalls.contains("m2") && messageReadIdle(first) }
    #expect(server.markCalls.last == "m2", "대화를 열었는데 서버 경계를 마지막 받은 말까지 안 올렸다")

    // 재실행 = 새 스토어(메모리에 아무것도 없다). 실행 직후 요약 한 번(startStatusRefreshLoop 의 그 호출).
    let (second, host) = makeMessageReadStore("dot-restart-2", handler: server.handler())
    #expect(!second.hasUnreadMessages, "응답이 오기 전부터 점이 켜졌다")
    await second.requestMessageActivityRefresh()?.value
    #expect(v0331DotCount(host, "message_unread_summary") == 1)
    #expect(!second.hasUnreadMessages, "재실행하니 이미 읽은 대화에 점이 다시 생겼다")
    // 팝오버를 열어 이력까지 받아도 그대로(도장이 없어도 서버가 판정한다).
    second.setMenuPresented(true)
    await messageReadWait { v0331DotCount(host, "message_history_with_reads") >= 1 && messageReadIdle(second) }
    #expect(second.messageReadStamps.isEmpty, "전제: 로컬 도장은 없다")
    #expect(second.unreadMessagePeerIDs.isEmpty)
    second.tickerTask?.cancel()

    // 대조: 서버가 안 읽었다고 하면 같은 경로에서 점이 켜진다(위 단언이 공허하지 않다).
    server.receive("m3", from: Fx.peerA, epoch: epoch - 10)
    await second.performLoadMessageUnreadSummary()
    #expect(second.unreadMessagePeerIDs == [Fx.peerA])
}

// MARK: 2. 대화를 연 채로 여러 개 도착 → 닫아도 점 없음

@MainActor
@Test(.gomokuDefaultsCleanup, arguments: [true, false])
func 대화를_연_채로_받은_여러_말은_닫아도_점이_없다(menuFlagStuckFalse: Bool) async {
    let epoch = Int(Date().timeIntervalSince1970)
    let server = V0331ReadServer()
    server.receive("m0", from: Fx.peerA, epoch: epoch - 300)
    let (store, host) = makeMessageReadStore("dot-open-arrivals", handler: server.handler())
    store.startedAt = Date().addingTimeInterval(-600)
    let token = UUID()
    store.isMenuPresented = true
    store.messageConversationViewDidAppear(token)
    store.openMessagePanel(peer: Fx.peerA)
    await messageReadWait { store.messageHistoryLoaded && messageReadIdle(store) }
    // 신고의 조건: 우리 다른 창이 키를 가져가 팝오버는 떠 있는데 표시 칸이 false 로 굳었다(모형의 실측 순서).
    if menuFlagStuckFalse { store.setMenuPresented(false) }

    for (index, id) in ["m1", "m2", "m3"].enumerated() {
        server.receive(id, from: Fx.peerA, epoch: epoch - 30 + index)
        _ = await store.drainReceivedPokes()
        #expect(store.selectedMessageThread?.messages.last?.id == id, "\(id) 가 열린 대화에 곧바로 안 들어왔다")
        await messageReadWait { messageReadIdle(store) }
    }
    #expect(server.markCalls.last == "m3", "보고 있던 대화의 마지막 말까지 읽음으로 안 올렸다: \(server.markCalls)")

    // 닫는다([뒤로] + 대화 뷰 사라짐). 곧바로도, 서버에 다시 물어도 점이 없어야 한다.
    store.closeMessagePanel()
    store.messageConversationViewDidDisappear(token)
    #expect(!store.hasUnreadMessages, "대화를 닫자마자 점이 생겼다")
    await store.performLoadMessageUnreadSummary()
    await store.performLoadMessageHistory()
    #expect(!store.hasUnreadMessages, "서버에 다시 물으니 보고 있던 말들이 안 읽음이다(경계가 안 올라갔다)")
    #expect(v0331DotCount(host, "take_pokes") == 3)
}

// MARK: 3. 맥 시계가 ±2분 어긋나도 점 없음

@MainActor
@Test(.gomokuDefaultsCleanup, arguments: [-120.0, 120.0])
func 맥_시계가_2분_어긋나도_읽은_대화에_점이_없다(skew: TimeInterval) async {
    let epoch = Int(Date().timeIntervalSince1970)
    let server = V0331ReadServer()
    server.receive("m1", from: Fx.peerA, epoch: epoch - 5)   // 방금 온 말(시계가 느린 맥에서는 "미래"다)
    let (store, host) = makeMessageReadStore("dot-skew", handler: server.handler())
    store.clock = { Date().addingTimeInterval(skew) }
    store.isMenuPresented = true
    store.messageConversationViewDidAppear(UUID())
    store.openMessagePanel(peer: Fx.peerA)
    await messageReadWait { server.markCalls.contains("m1") && messageReadIdle(store) }
    store.closeMessagePanel()
    await store.performLoadMessageUnreadSummary()
    #expect(!store.hasUnreadMessages, "시계 \(skew)초 어긋난 맥에서 읽은 대화에 점")
    // 점 계산에 로컬 시각 비교가 남아 있지 않다: 도장을 아주 옛날로 돌려도(서버가 읽음을 알면) 영향이 없다.
    store.messageReadStamps[Fx.peerA] = Date(timeIntervalSince1970: 0)
    #expect(!store.hasUnreadMessages, "서버가 읽음을 아는데 로컬 도장(시계)이 점을 켰다")
    #expect(v0331DotCount(host, "mark_messages_read") >= 1)
}

// MARK: 4. 폰(다른 기기)에서 읽음 → 자기 신호로 몇 초 안에 점 꺼짐

@MainActor
@Test(.gomokuDefaultsCleanup)
func 폰에서_읽으면_자기_읽음_신호로_닫힌_팝오버의_점이_꺼진다() async {
    let epoch = Int(Date().timeIntervalSince1970)
    let server = V0331ReadServer()
    server.receive("m1", from: Fx.peerA, epoch: epoch - 60)
    let transport = FakeRealtimeTransport()
    let (store, host) = makeMessageReadStore("dot-phone", transport: transport, handler: server.handler())
    store.startRealtimeIfPossible()
    transport.emit(.joined)
    await messageReadWait { v0331DotCount(host, "message_unread_summary") >= 1 && messageReadIdle(store) }
    #expect(store.hasUnreadMessages, "전제: 안 읽은 말이 있다")

    server.readOnAnotherDevice(peer: Fx.peerA)
    let started = Date()
    transport.emit(.broadcast(event: "message_read"))
    await messageReadWait { !store.hasUnreadMessages && messageReadIdle(store) }
    #expect(!store.hasUnreadMessages, "폰에서 읽은 신호를 받았는데 맥의 점이 남았다")
    #expect(Date().timeIntervalSince(started) < 3, "점이 꺼지기까지 3초 넘게 걸렸다")
    #expect(v0331DotCount(host, "take_pokes") == 0)
    #expect(v0331DotCount(host, "message_history_with_reads") == 0, "닫힌 팝오버에서 이력까지 받았다")
}

// MARK: 5. 로그아웃 → 다른 계정 → 앞 계정 점 없음

@MainActor
@Test(.gomokuDefaultsCleanup)
func 로그아웃하고_다른_계정으로_들어가면_앞_계정의_점이_남지_않는다() async {
    let gate = MessageReadStubGate()
    final class Phase: @unchecked Sendable { var nextAccount = false }
    let phase = Phase()
    let (store, host) = makeMessageReadStore("dot-account") { call, index in
        guard call.rpc == "message_unread_summary" else { return nil }
        if phase.nextAccount { return Fx.summaryReply([]) }
        // 앞 계정: 첫 요약은 곧바로(점 켜짐), 둘째는 로그아웃 뒤에야 도착한다.
        return index == 0 ? Fx.summaryReply([(Fx.peerA, 2)]) : Fx.summaryReply([(Fx.peerA, 3)], gate: gate)
    }
    await store.performLoadMessageUnreadSummary()
    #expect(store.hasUnreadMessages, "전제: 앞 계정에 안 읽음")
    let late = Task { @MainActor in await store.performLoadMessageUnreadSummary() }
    await messageReadWait { v0331DotCount(host, "message_unread_summary") == 2 }

    store.signOut()
    store.session = SupabaseSession(accessToken: "next", refreshToken: nil, userID: Fx.peerB)
    phase.nextAccount = true
    #expect(!store.hasUnreadMessages, "로그아웃했는데 앞 계정의 점이 남았다")
    gate.open()
    await late.value
    #expect(!store.hasUnreadMessages, "앞 계정의 늦은 요약이 다음 계정에 점을 켰다")
    await store.performLoadMessageUnreadSummary()
    #expect(!store.hasUnreadMessages)
}

// MARK: 6. 점이 뜨는 자리 전부가 같은 판정 하나

@Test
func 점이_뜨는_세_자리가_모두_같은_판정_하나를_읽는다() throws {
    // 판정: `unreadMessagePeerIDs`(MessageUnreadRules 한 곳) → `hasUnreadMessages` 는 그 비어 있음.
    let messages = v0331StripComments(try CheckCoreSourceLayout.joinedSplitSource("WorkTimerStoreMessages.swift"))
    #expect(messages.contains("var hasUnreadMessages: Bool { !unreadMessagePeerIDs.isEmpty }"))
    #expect(messages.contains("MessageUnreadRules.unreadPeerIDs("))
    // ① 메뉴바 아이콘
    let app = try v0331Source("CheckApp.swift")
    #expect(app.contains("hasUnreadMessages: appDelegate.store.hasUnreadMessages"), "메뉴바 점이 공용 판정을 안 읽는다")
    // ② 콕찌르기 목록 행 · ③ 레일 진입 버튼
    let menu = try v0331Source("CheckMenuView.swift")
    #expect(menu.contains("unreadMessagePeerIDs: store.unreadMessagePeerIDs"), "목록 행 점이 공용 판정을 안 읽는다")
    #expect(menu.contains("let unread = store.hasUnreadMessages"), "레일 점이 공용 판정을 안 읽는다")

    // 그 밖의 **어느 소스도** 안 읽음을 따로 계산하지 않는다: 읽음 재료(서버 플래그·요약·도장·낙관 읽음)를 만지는 파일은 정해져 있다.
    let allowed: Set<String> = [
        "WorkTimerStoreMessages.swift",            // 판정(MessageUnreadRules)의 배선과 그 재료의 주인
        "MessageRules.swift",                      // 판정 규칙 본문(D-base 에서 코어로 뗀 조각 — 같은 파일의 나머지 반쪽)
        "WorkTimerStore.swift",                    // 저장 프로퍼티 선언 · 로그아웃 비우기
        "SupabaseWorkServiceMessageReads.swift",   // 서버 응답 → 재료
        "SupabaseWorkModels.swift"                 // 모델 필드 선언
    ]
    let sourcesURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/check")
    let files = try FileManager.default.checkSourcesContentsOfDirectory(atPath: sourcesURL.path).filter { $0.hasSuffix(".swift") }
    let ingredients = ["isUnread", "messageReadStamps", "messageUnreadSummary", "messageOptimisticReads", "legacyUnreadPeerIDs"]
    var offenders: [String] = []
    for file in files where !allowed.contains(file) {
        let text = try v0331Source(file)
        for word in ingredients where text.contains(word) { offenders.append("\(file):\(word)") }
    }
    #expect(offenders.isEmpty, "공용 판정 밖에서 안 읽음 재료를 읽는 자리: \(offenders)")
    // 공용 판정을 읽는 자리는 위 셋뿐이다(새 자리가 생기면 여기서 드러난다).
    var readers: [String] = []
    for file in files where file != "WorkTimerStoreMessages.swift" {
        let text = try v0331Source(file)
        if text.contains("store.unreadMessagePeerIDs") || text.contains("store.hasUnreadMessages") { readers.append(file) }
    }
    #expect(Set(readers) == ["CheckApp.swift", "CheckMenuView.swift"], "점 판정을 읽는 파일: \(readers.sorted())")
}
