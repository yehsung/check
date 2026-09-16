import Foundation
import Testing
@testable import check

// v0.3.31 M4 — **열린 대화에 메시지가 즉시 뜬다**(스토어 · 콜백 순서 모형).
//
// 사용자 신고(2026-09-17, 0.3.29): "상대와의 채팅창에 접속해 있는 상태에서 메시지 받으면 그 메시지가 채팅창에 바로 안 뜨고 시간이 좀 지난
// 다음에 뜨거나, 아예 창 뒤로 갔다가 다시 들어와야 뜬다."
//
// 원인 확정(헤드리스 재현 — 스크래치 사본 두 벌에서 같은 시나리오를 돌렸다. 실제 앱·메뉴바 재현 앱은 사용자 맥이라 띄우지 않았다):
//  · 0.3.29(main 4ff113a 사본, CtlM4Tests 8개 함수): 판정(`isMenuPresented`)이 맞으면 도착은 take_pokes → 이력 1왕복 뒤에 뜬다(c1 초록).
//    콜백 순서 모형 8개 중 **보이는데 false 로 남는 5개**(우리 다른 창이 키 — 실측상 팝오버 안 닫힘 · 루트 정체성 교체(새 onAppear 먼저) ·
//    빠른 재오픈의 늦은 키 상실 · 비활성 숨김 뒤 키 없이 재표시 · 잠자기)에서 새 말이 **끝내 안 떴다**(이력 조회 1회 = 열 때뿐)
//    → 신고의 "다시 들어와야 뜬다". 맥 시계 6분 빠름(신선도 필터가 도착을 비워 갱신을 안 부름) · 늦게 온 옛 이력이 방금 뜬 말을 지움
//    (→ "시간이 좀 지난 다음에") · 흡수 세션 맥(도착 신호 없음)도 빨강.
//  · 수정 전 mobile-int(278d665 사본, CtlPreM4Tests): 늦은 옛 이력·흡수 세션 맥은 1차 묶음이 이미 고쳤다(초록). 남은 셋 —
//    판정이 맞아도 새 말은 take_pokes 뒤 **요약·이력 두 왕복을 더** 기다린다 · 보이는데 false 인 순서 3개에서 새 말이 안 뜨고 읽음도 안 올라간다
//    (mark 0 → 닫으면 점, 두 번째 신고) · 시계 6분 빠르면 갱신 자체가 없다.
//  · 어느 AppKit 순서가 사용자 세션에서 실제로 일어났는지는 **실측하지 못했다**(실행 중 앱 프로브 금지). 그래서 판정을 한 순서에 맞춰 고치지 않고
//    순서와 무관한 사실(대화 뷰 자신의 생명주기 · 창 서버의 표시 상태)로 바꿨다.
// 이 파일은 그 셋이 고쳐졌음을 잰다. 변이 검증: 판정을 옛 한 칸으로 되돌리면 모형 표의 "보이는" 줄이 빨개진다.

private typealias Fx = MessageReadFixture

/// 서버 모형: m1 은 **take_pokes 가 불린 순간부터** 서버 이력에 있다(보낸 직후 초인종 → 소비의 순서). 그 전의 이력은 m0 만.
final class V0331ServerState: @unchecked Sendable {
    private let lock = NSLock()
    private var sent = false
    var hasSent: Bool { lock.lock(); defer { lock.unlock() }; return sent }
    func markSent() { lock.lock(); sent = true; lock.unlock() }
}

private func v0331Server(
    epoch: Int,
    takenEpoch: Int? = nil,
    state: V0331ServerState = V0331ServerState(),
    historyGate: MessageReadStubGate? = nil,
    takeGate: MessageReadStubGate? = nil,
    serverBody: String = "밥?"
) -> MessageReadStubProtocol.Handler {
    { call, index in
        switch call.rpc {
        case "message_history_with_reads":
            var rows = [Fx.readsRow(id: "m0", peer: Fx.peerA, isMine: false, body: "먼저 온 말", epoch: epoch - 120, unread: false)]
            if state.hasSent {
                rows.append(Fx.readsRow(id: "m1", peer: Fx.peerA, isMine: false, body: serverBody, epoch: epoch - 1, unread: true))
            }
            return Fx.historyReply(rows, gate: historyGate)
        case "message_unread_summary": return Fx.summaryReply([])
        case "mark_messages_read": return Fx.markReply()
        case "take_pokes":
            state.markSent()
            let rows = index == 0 ? [Fx.takenMessageRow(id: "m1", from: Fx.peerA, epoch: takenEpoch ?? epoch - 1)] : []
            return MessageReadStubProtocol.Reply(body: Fx.json(rows), gate: takeGate)
        default: return nil
        }
    }
}

/// 대화를 연다(패널 · 상대 · 첫 이력). 팝오버 표시 칸과 대화 뷰 표식은 **호출부가** 정한다.
@MainActor
private func v0331OpenConversation(_ store: WorkTimerStore, viewToken: UUID?, menu: Bool) async {
    store.isMenuPresented = menu
    if let viewToken { store.messageConversationViewDidAppear(viewToken) }
    store.openMessagePanel(peer: Fx.peerA)
    await messageReadWait { store.messageHistoryLoaded && messageReadIdle(store) }
}

@MainActor
private func v0331Count(_ host: String, _ rpc: String) -> Int {
    MessageReadStubProtocol.count(host: host, rpc: rpc)
}

// MARK: - 순수 판정 표

@Test(arguments: [
    // (패널, 뷰 표식, 팝오버 칸, 창 서버, 떠 있을 수 있음, 보고 있음)
    (true, true, false, nil as Bool?, true, true),      // 칸이 굳은 false 여도 뷰가 서 있다 — 0.3.29 의 결함 자리
    (true, false, true, nil, true, true),               // 뷰 표식 없이 칸만(스토어 단독 경로)
    (true, false, false, true, true, true),             // 창 서버가 떠 있다고 한다
    (true, true, false, false, true, false),            // 뷰는 섰는데 창 서버가 "없다" — 갱신은 하되 읽음은 안 올린다
    (true, true, true, false, true, false),             // 칸까지 true 여도 창 서버가 "없다"면 읽음은 안 올린다
    (true, false, false, nil, false, false),            // 아무 신호도 없다(닫힘)
    (true, false, false, false, false, false),
    (false, true, true, true, false, false)             // 대화 패널이 아니다
])
func 대화가_보이는가의_판정표(
    panel: Bool, view: Bool, menu: Bool, onScreen: Bool?, mayBe: Bool, seen: Bool
) {
    let s = MessageConversationVisibility.Signals(
        signedIn: true, panelVisible: panel,
        conversationViewShown: view, menuPresented: menu, popoverOnScreen: onScreen
    )
    #expect(MessageConversationVisibility.mayBeOnScreen(s) == mayBe)
    #expect(MessageConversationVisibility.isSeen(s) == seen)
    var signedOut = s
    signedOut.signedIn = false
    #expect(!MessageConversationVisibility.mayBeOnScreen(signedOut))
}

// MARK: - 원인 재현: 두 출처 콜백 순서 모형

/// 팝오버 루트(onAppear/onDisappear)·창 키 통지(becomeKey/resignKey)·대화 뷰 생명주기·창 서버의 사실을 한 사건열로 흘린다.
/// `measured` = 이 저장소에 실측 기록이 있는 순서(CheckWindowAnchor.swift 의 표·메모리). 나머지는 SwiftUI/AppKit 이 **약속하지 않는** 순서다.
struct V0331CallbackSequence: CustomStringConvertible, Sendable {
    enum Step: Sendable {
        case rootAppear          // 팝오버 콘텐츠 onAppear → setMenuPresented(true) · 대화 뷰 onAppear
        case rootDisappear       // onDisappear → setMenuPresented(false) · 대화 뷰 onDisappear
        case becomeKey, resignKey
        case viewSwapNewFirst    // 대화 뷰 정체성 교체: 새 뷰 나타남 → 옛 뷰 사라짐(루트도 같은 순서로)
        case screen(Bool)        // 창 서버가 보는 사실(이후 질의의 답)
    }
    let name: String
    let measured: Bool
    let steps: [Step]
    let visible: Bool
    var description: String { name }
}

let v0331Sequences: [V0331CallbackSequence] = [
    .init(name: "열기", measured: true, steps: [.screen(true), .rootAppear, .becomeKey], visible: true),
    .init(name: "열기→우리_다른_창이_키(팝오버_안_닫힘)", measured: true,
          steps: [.screen(true), .rootAppear, .becomeKey, .resignKey], visible: true),
    .init(name: "열기→다른_창→팝오버_다시_클릭", measured: false,
          steps: [.screen(true), .rootAppear, .becomeKey, .resignKey, .becomeKey], visible: true),
    .init(name: "아이콘으로_닫기(onDisappear만)", measured: true,
          steps: [.screen(true), .rootAppear, .becomeKey, .screen(false), .rootDisappear], visible: false),
    .init(name: "정체성_교체_새것_먼저", measured: false,
          steps: [.screen(true), .rootAppear, .becomeKey, .viewSwapNewFirst], visible: true),
    .init(name: "빠른_재오픈_늦은_키_상실", measured: false,
          steps: [.screen(true), .rootAppear, .becomeKey, .screen(false), .rootDisappear, .screen(true), .rootAppear, .becomeKey, .resignKey],
          visible: true),
    .init(name: "앱_비활성_숨김(vis=false)", measured: true,
          steps: [.screen(true), .rootAppear, .becomeKey, .screen(false), .resignKey], visible: false),
    .init(name: "비활성_숨김→키_없이_재표시", measured: false,
          steps: [.screen(true), .rootAppear, .becomeKey, .screen(false), .resignKey, .screen(true)], visible: true),
    .init(name: "잠자기(잠금화면이_키)→깨어남", measured: false,
          steps: [.screen(true), .rootAppear, .becomeKey, .resignKey], visible: true)
]

final class V0331ScreenFact: @unchecked Sendable {
    var onScreen: Bool? = nil
}

@MainActor
@Test(.gomokuDefaultsCleanup, arguments: v0331Sequences, [true, false])
func 콜백이_어떤_순서로_와도_보이는_대화에는_도착이_즉시_뜨고_읽음이_올라간다(
    sequence: V0331CallbackSequence, windowServerAnswers: Bool
) async {
    let epoch = Int(Date().timeIntervalSince1970)
    let (store, host) = makeMessageReadStore("model", handler: v0331Server(epoch: epoch))
    store.startedAt = Date().addingTimeInterval(-600)
    let screen = V0331ScreenFact()
    // 창 서버가 답하는 실행과 "모른다"(창을 못 잡음)인 실행을 둘 다 돈다.
    store.menuPopoverOnScreenProbe = { windowServerAnswers ? screen.onScreen : nil }
    await v0331OpenConversation(store, viewToken: nil, menu: false)
    store.isMenuPresented = false

    var liveTokens: [UUID] = []
    for step in sequence.steps {
        switch step {
        case .screen(let on): screen.onScreen = on
        case .rootAppear:
            store.setMenuPresented(true)
            let token = UUID()
            liveTokens.append(token)
            store.messageConversationViewDidAppear(token)
        case .rootDisappear:
            store.setMenuPresented(false)
            if let token = liveTokens.popLast() { store.messageConversationViewDidDisappear(token) }
        case .becomeKey: store.setMenuPresented(true)
        case .resignKey: store.setMenuPresented(false)
        case .viewSwapNewFirst:
            let fresh = UUID()
            store.setMenuPresented(true)
            store.messageConversationViewDidAppear(fresh)
            store.setMenuPresented(false)
            if let old = liveTokens.popLast() { store.messageConversationViewDidDisappear(old) }
            liveTokens.append(fresh)
        }
    }
    await messageReadWait { messageReadIdle(store) }
    let historyBefore = v0331Count(host, "message_history_with_reads")
    let markBefore = v0331Count(host, "mark_messages_read")

    _ = await store.drainReceivedPokes()
    // ★ 재는 순간: take_pokes 응답이 반영된 **직후**(추가 왕복 전).
    let idsRightAfterTake = store.selectedMessageThread?.messages.map(\.id) ?? []
    await messageReadWait { messageReadIdle(store) }
    try? await Task.sleep(for: .milliseconds(40))
    await messageReadWait { messageReadIdle(store) }

    let label = "\(sequence.name) measured=\(sequence.measured) windowServer=\(windowServerAnswers) presented=\(store.isMenuPresented)"
    if sequence.visible {
        #expect(idsRightAfterTake == ["m0", "m1"], "보이는 대화인데 take_pokes 직후 새 말이 대화에 없다 — \(label)")
        #expect(store.selectedMessageThread?.messages.map(\.id) == ["m0", "m1"], "서버와 맞춘 뒤 새 말이 사라졌다 — \(label)")
        #expect(v0331Count(host, "message_history_with_reads") > historyBefore, "보이는 대화의 도착이 이력을 다시 받지 않았다(서버 값과 못 맞춘다) — \(label)")
        #expect(v0331Count(host, "mark_messages_read") > markBefore, "보고 있던 대화의 새 말을 읽음으로 안 올렸다(닫으면 점) — \(label)")
        #expect(MessageReadStubProtocol.calls(host: host, rpc: "mark_messages_read").last?.json["p_through"] as? String == "m1")
    } else {
        let swiftUIHeardDisappear = sequence.steps.contains { if case .rootDisappear = $0 { return true } else { return false } }
        if swiftUIHeardDisappear {
            #expect(idsRightAfterTake == ["m0"], "닫힌 대화에 넣었다 — \(label)")
            #expect(v0331Count(host, "message_history_with_reads") == historyBefore, "닫힌 대화에 이력 조회가 붙었다 — \(label)")
            #expect(v0331Count(host, "mark_messages_read") == markBefore, "닫힌 대화의 말을 읽음으로 올렸다 — \(label)")
        } else if windowServerAnswers {
            // SwiftUI 가 사라짐을 못 들은 숨김(앱 비활성): 대화 뷰 표식이 남아 갱신은 "보인다"로 기운다 — 값은 도착당 이력 1건.
            // **읽음은 창 서버의 "안 떠 있다"가 막는다**(못 본 말을 읽었다고 상대에게 알리지 않는다).
            #expect(v0331Count(host, "message_history_with_reads") <= historyBefore + 1, "도착 1건에 이력이 두 번 넘게 나갔다 — \(label)")
            #expect(v0331Count(host, "mark_messages_read") == markBefore, "창 서버가 안 떠 있다고 하는데 읽음으로 올렸다 — \(label)")
        } else {
            // 창 서버도 모르고 SwiftUI 도 못 들었다 — 이 프로세스 안의 어떤 신호로도 "보이는 대화"와 가를 수 없다(설계상 보인다로 기운다).
            // 이 칸은 앱에서 창 서버 질의가 실패할 때만 생긴다. 값의 상한만 본다: 도착 이력 1 + 읽음 성공 뒤 서버 판정 이력 1.
            #expect(v0331Count(host, "message_history_with_reads") <= historyBefore + 2, "도착 1건에 이력이 세 번 넘게 나갔다 — \(label)")
        }
    }
    store.tickerTask?.cancel()
}

// MARK: - 즉시 삽입

@MainActor
@Test(.gomokuDefaultsCleanup)
func 보이는_대화에는_take_pokes_응답만으로_새_말이_들어간다_추가_왕복_0() async {
    let epoch = Int(Date().timeIntervalSince1970)
    let state = V0331ServerState()
    // 첫 이력(대화 열기) 뒤의 이력·요약 응답은 **전부 문에 붙잡는다** — 새 말이 그 응답 없이 들어왔음을 증명한다.
    let hold = MessageReadStubGate()
    let base = v0331Server(epoch: epoch, state: state)
    let (store, host) = makeMessageReadStore("instant") { call, index in
        guard var reply = base(call, index) else { return nil }
        if (call.rpc == "message_history_with_reads" && index >= 1) || call.rpc == "message_unread_summary" { reply.gate = hold }
        return reply
    }
    store.startedAt = Date().addingTimeInterval(-600)
    await v0331OpenConversation(store, viewToken: UUID(), menu: true)

    _ = await store.drainReceivedPokes()
    #expect(store.selectedMessageThread?.messages.map(\.id) == ["m0", "m1"],
            "이력·요약 응답이 하나도 안 왔는데(문에 붙잡힘) 새 말이 대화에 없다 — take_pokes 뒤 왕복을 기다린다")
    #expect(v0331Count(host, "take_pokes") == 1)
    let m1 = store.selectedMessageThread?.messages.last
    #expect(m1?.body == "밥?" && m1?.isMine == false && m1?.peerName == "상대" && m1?.isUnread == true)
    // 같은 순간 읽음 처리도 이미 떠났다(보고 있는 대화의 말 — 기존 규칙 그대로).
    #expect(store.messageOptimisticReads[Fx.peerA]?.throughID == "m1")
    #expect(!store.hasUnreadMessages, "보고 있는 대화에 들어온 말이 점을 켰다")
    // 대화창에 방금 뜬 말은 캐릭터 말풍선으로 한 번 더 띄우지 않는다(읽은 것 필터).
    #expect(store.receivedMessages.isEmpty, "열린 대화에 들어간 말이 말풍선 큐에도 올랐다")
    hold.open()
    await messageReadWait { messageReadIdle(store) }
    #expect(store.selectedMessageThread?.messages.map(\.id) == ["m0", "m1"])
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 창_서버가_안_떠_있다고_하면_읽음은_안_올리고_말풍선은_그대로_뜬다() async {
    // 앱 비활성으로 팝오버가 화면에서만 사라지고 SwiftUI 는 모르는 숨김: 대화 뷰 표식이 남아 갱신은 "보인다"로 기운다.
    // 그래도 못 본 말이다 — 읽음으로 올리지 않고, 캐릭터 말풍선으로 알린다.
    let epoch = Int(Date().timeIntervalSince1970)
    let (store, host) = makeMessageReadStore("hidden-bubble", handler: v0331Server(epoch: epoch))
    store.startedAt = Date().addingTimeInterval(-600)
    await v0331OpenConversation(store, viewToken: UUID(), menu: false)
    store.menuPopoverOnScreenProbe = { false }
    let markBefore = v0331Count(host, "mark_messages_read")

    _ = await store.drainReceivedPokes()
    await messageReadWait { messageReadIdle(store) }
    #expect(v0331Count(host, "mark_messages_read") == markBefore, "창 서버가 안 떠 있다는데 읽음으로 올렸다")
    #expect(store.receivedMessages.map(\.id) == ["m1"], "못 본 말인데 말풍선 큐에서 빠졌다")
    #expect(store.unreadMessagePeerIDs == [Fx.peerA], "못 본 말의 점이 안 켜졌다")
}

@MainActor
@Test(.gomokuDefaultsCleanup, arguments: ["other-peer", "panel-closed", "popover-closed"])
func 다른_대화나_닫힌_대화에는_넣지_않는다(situation: String) async {
    let epoch = Int(Date().timeIntervalSince1970)
    let (store, host) = makeMessageReadStore("not-visible", handler: v0331Server(epoch: epoch))
    store.startedAt = Date().addingTimeInterval(-600)
    let token = UUID()
    await v0331OpenConversation(store, viewToken: token, menu: true)
    switch situation {
    case "other-peer": store.selectMessagePeer(Fx.peerB)
    case "panel-closed":
        store.closeMessagePanel()
        store.messageConversationViewDidDisappear(token)
    default:
        store.setMenuPresented(false)
        store.messageConversationViewDidDisappear(token)
        store.menuPopoverOnScreenProbe = { false }
    }
    await messageReadWait { messageReadIdle(store) }
    let historyBefore = v0331Count(host, "message_history_with_reads")
    let summaryBefore = v0331Count(host, "message_unread_summary")

    _ = await store.drainReceivedPokes()
    #expect(!store.messageHistory.contains { $0.id == "m1" }, "\(situation): 안 보이는 대화에 즉시 넣었다")
    await messageReadWait { messageReadIdle(store) }
    try? await Task.sleep(for: .milliseconds(40))
    await messageReadWait { messageReadIdle(store) }
    #expect(v0331Count(host, "message_unread_summary") == summaryBefore + 1, "\(situation): 도착이 요약(점)을 안 받았다")
    if situation == "other-peer" {
        // 다른 사람과의 대화는 보이고 있다 — 이력은 받고(목록·점 계산), 새 말은 그 사람 대화에만 산다.
        #expect(v0331Count(host, "message_history_with_reads") == historyBefore + 1)
        #expect(store.selectedMessageThread?.peerUserID != Fx.peerA)
        #expect(store.unreadMessagePeerIDs == [Fx.peerA])
    } else {
        #expect(v0331Count(host, "message_history_with_reads") == historyBefore, "\(situation): 닫힌 대화에 이력 조회가 붙었다")
    }
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 중복_id_는_넣지_않고_같은_초의_새_말은_서버가_아는_말_뒤에_선다() async {
    let epoch = Int(Date().timeIntervalSince1970)
    let (store, _) = makeMessageReadStore("dup-order") { call, _ in
        switch call.rpc {
        case "message_history_with_reads":
            return Fx.historyReply([
                Fx.readsRow(id: "z-known", peer: Fx.peerA, isMine: false, body: "서버가 아는 말", epoch: epoch, unread: false)
            ])
        case "message_unread_summary": return Fx.summaryReply([])
        default: return nil
        }
    }
    await v0331OpenConversation(store, viewToken: UUID(), menu: true)
    let row = { (id: String, body: String) in
        TakenPokeRow(id: id, fromUser: Fx.peerA, fromDisplayName: "상대", fromAvatarUrl: nil, createdEpoch: epoch, kind: "message", body: body)
    }
    // 같은 초 · id 사전순이 서버가 아는 말보다 앞인 두 말. 서버 순서를 모르는 새 말은 **뒤**에 선다(도착이 더 나중이다).
    let entries = WorkTimerStore.consumedMessageEntries(rows: [row("a-new", "첫째"), row("b-new", "둘째"), row("z-known", "중복")], receiptsKnown: true)
    #expect(store.insertConsumedMessagesIntoVisibleConversation(entries) == 2, "중복 id 를 한 번 더 넣었다")
    #expect(store.messageHistory.map(\.id) == ["z-known", "a-new", "b-new"])
    #expect(store.messageHistory.first?.body == "서버가 아는 말", "중복 행이 서버 행을 덮었다")
    // 같은 것을 또 넣어도 그대로(멱등).
    #expect(store.insertConsumedMessagesIntoVisibleConversation(entries) == 0)
    #expect(store.messageHistory.map(\.id) == ["z-known", "a-new", "b-new"])
    // 읽음 경계는 즉시 삽입한 **마지막** 말이다(서버 순서 뒤).
    #expect(MessageUnreadRules.markTarget(
        peer: Fx.peerA, history: store.messageHistory,
        snapshot: store.messageHistoryReadSnapshot!, optimistic: nil
    ) == "b-new")
    await messageReadWait { messageReadIdle(store) }
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 서버_재조회가_이기고_삽입보다_먼저_띄운_늦은_이력은_새_말을_지우지_않는다() async {
    let epoch = Int(Date().timeIntervalSince1970)
    let state = V0331ServerState()
    let gate = MessageReadStubGate()
    final class Counter: @unchecked Sendable { var n = 0 }
    let historyCalls = Counter()
    let (store, host) = makeMessageReadStore("server-wins") { call, index in
        switch call.rpc {
        case "message_history_with_reads":
            historyCalls.n = index + 1
            var rows = [Fx.readsRow(id: "m0", peer: Fx.peerA, isMine: false, epoch: epoch - 120, unread: false)]
            // index 1: 삽입 **전에** 띄웠고 늦게 온다(m1 모름). index 2+: 서버가 정규화한 본문 · 읽음 반영.
            if index == 1 { return Fx.historyReply(rows, gate: gate) }
            if state.hasSent {
                rows.append(Fx.readsRow(id: "m1", peer: Fx.peerA, isMine: false, body: "밥? (서버)", epoch: epoch - 1, unread: false))
            }
            return Fx.historyReply(rows)
        case "message_unread_summary": return Fx.summaryReply([])
        case "mark_messages_read": return Fx.markReply()
        case "take_pokes":
            state.markSent()
            return MessageReadStubProtocol.Reply(body: Fx.json(index == 0 ? [Fx.takenMessageRow(id: "m1", from: Fx.peerA, epoch: epoch - 1)] : []))
        default: return nil
        }
    }
    store.startedAt = Date().addingTimeInterval(-600)
    await v0331OpenConversation(store, viewToken: UUID(), menu: true)
    // 삽입 전에 띄운 이력(예: 내가 보낸 직후 조회) — 문에 붙잡힌다.
    let early = Task { @MainActor in await store.performLoadMessageHistory() }
    await messageReadWait { v0331Count(host, "message_history_with_reads") == 2 }

    _ = await store.drainReceivedPokes()
    #expect(store.selectedMessageThread?.messages.last?.body == "밥?", "전제: 즉시 삽입한 본문")
    await messageReadWait { v0331Count(host, "message_history_with_reads") >= 3 && store.messageHistory.last?.body == "밥? (서버)" }
    #expect(store.messageHistory.last?.body == "밥? (서버)", "나중에 띄운 서버 이력이 즉시 삽입한 행을 이기지 못했다")
    #expect(store.messageHistory.last?.isUnread == false)
    #expect(store.messageHistory.filter { $0.id == "m1" }.count == 1)

    // 이제 삽입 전에 띄운 옛 응답이 도착한다 — 더 나중에 반영된 조회가 있으니 버려진다.
    gate.open()
    await early.value
    #expect(store.selectedMessageThread?.messages.map(\.id) == ["m0", "m1"], "늦게 온 옛 이력이 새 말을 지웠다")
    #expect(store.messageReadRuntime.localArrivalSerials.isEmpty, "서버가 답한 뒤에도 즉시 삽입 장부가 남았다")
    await messageReadWait { messageReadIdle(store) }
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 삽입보다_먼저_띄운_이력이_먼저_반영돼도_새_말은_남고_나중_조회에_없으면_서버가_이긴다() async {
    // 순서: 이력 A 띄움(m1 모름, 붙잡힘) → 삽입 → A 도착(반영 — 더 나중 조회가 아직 없다) → 새 말은 남아야 한다.
    // 그 뒤 삽입보다 나중에 띄운 조회 B 가 m1 을 모르면(보관 창 밖) 서버가 이긴다.
    let epoch = Int(Date().timeIntervalSince1970)
    let gate = MessageReadStubGate()
    let (store, host) = makeMessageReadStore("early-applied") { call, index in
        switch call.rpc {
        case "message_history_with_reads":
            let rows = [Fx.readsRow(id: "m0", peer: Fx.peerA, isMine: false, epoch: epoch - 120, unread: false)]
            return Fx.historyReply(rows, gate: index == 1 ? gate : nil)
        case "message_unread_summary": return Fx.summaryReply([])
        default: return nil
        }
    }
    await v0331OpenConversation(store, viewToken: UUID(), menu: true)
    let early = Task { @MainActor in await store.performLoadMessageHistory() }
    await messageReadWait { v0331Count(host, "message_history_with_reads") == 2 }
    let row = TakenPokeRow(id: "m1", fromUser: Fx.peerA, fromDisplayName: "상대", fromAvatarUrl: nil, createdEpoch: epoch, kind: "message", body: "지금")
    store.insertConsumedMessagesIntoVisibleConversation(WorkTimerStore.consumedMessageEntries(rows: [row], receiptsKnown: true))
    gate.open()
    await early.value
    #expect(store.messageHistory.map(\.id) == ["m0", "m1"], "삽입 전에 띄운 이력이 반영되며 새 말을 지웠다")

    await store.performLoadMessageHistory()
    #expect(store.messageHistory.map(\.id) == ["m0"], "삽입 뒤에 띄운 서버 이력에 없는데 로컬 행이 남았다(서버가 이겨야 한다)")
    #expect(store.messageReadRuntime.localArrivalSerials.isEmpty)
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 신선도_밖_행도_보이는_대화에_넣고_갱신을_부른다() async {
    // 맥 시계가 서버보다 6분 빠르다 = 방금 온 말이 로컬 시계로 361초 전이다. 말풍선(5분)으로는 안 띄우지만 대화에는 넣는다.
    // 서버 시계로는 방금(m1 = serverEpoch − 1), 맥 시계로는 361초 전이다.
    let serverEpoch = Int(Date().timeIntervalSince1970) - 360
    // 읽음 처리는 **없는 서버**로 둔다 — 성공 뒤 새로고침이 요약을 한 번 더 받으면 "도착 갱신을 불렀는가"를 가를 수 없다.
    let base = v0331Server(epoch: serverEpoch)
    let (store, host) = makeMessageReadStore("stale-clock") { call, index in
        call.rpc == "mark_messages_read" ? Fx.missingFunction(call.rpc) : base(call, index)
    }
    store.startedAt = Date().addingTimeInterval(-600)
    await v0331OpenConversation(store, viewToken: UUID(), menu: true)
    let summaryBefore = v0331Count(host, "message_unread_summary")

    _ = await store.drainReceivedPokes()
    #expect(store.selectedMessageThread?.messages.map(\.id) == ["m0", "m1"], "신선도 밖이라고 보이는 대화에 안 넣었다")
    #expect(store.receivedMessages.isEmpty, "5분 넘은 말이 말풍선 큐에 올랐다")
    await messageReadWait { v0331Count(host, "message_unread_summary") > summaryBefore && messageReadIdle(store) }
    #expect(v0331Count(host, "message_unread_summary") == summaryBefore + 1, "말풍선 큐가 비었다고 도착 갱신을 건너뛰었다")
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 소비_못_하는_맥의_초인종은_대화가_보이면_스로틀_없이_이력을_곧바로_다시_받는다() async {
    let epoch = Int(Date().timeIntervalSince1970)
    let state = V0331ServerState()
    let transport = FakeRealtimeTransport()
    let (store, host) = makeMessageReadStore("idle-ring-visible", transport: transport, handler: v0331Server(epoch: epoch, state: state))
    // 비근무 맥. 팝오버를 방금 열어 60초 스로틀 도장이 찍혔다.
    store.setMenuPresented(true)
    await v0331OpenConversation(store, viewToken: UUID(), menu: true)
    store.isMenuPresented = false          // 떠 있는데 칸이 굳었다(원인 ①) — 뷰 표식이 판정을 지킨다.
    store.startRealtimeIfPossible()
    transport.emit(.joined)
    await messageReadWait { messageReadIdle(store) }
    let historyBefore = v0331Count(host, "message_history_with_reads")

    state.markSent()
    transport.emit(.broadcast(event: "ring"))
    await messageReadWait { store.selectedMessageThread?.messages.count == 2 && messageReadIdle(store) }
    #expect(v0331Count(host, "take_pokes") == 0, "비근무 맥이 take_pokes 를 쐈다")
    #expect(v0331Count(host, "message_history_with_reads") > historyBefore, "보이는 대화인데 초인종이 이력을 곧바로 받지 않았다")
    #expect(store.selectedMessageThread?.messages.map(\.id) == ["m0", "m1"])
    #expect(v0331Count(host, "mark_messages_read") >= 1)
    store.tickerTask?.cancel()
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 닫힌_팝오버에서는_도착_1건당_요청이_늘지_않는다() async {
    let epoch = Int(Date().timeIntervalSince1970)
    let transport = FakeRealtimeTransport()
    let (store, host) = makeMessageReadStore("closed-budget", transport: transport, handler: v0331Server(epoch: epoch))
    let token = UUID()
    await v0331OpenConversation(store, viewToken: token, menu: true)
    // 아이콘으로 닫았다: 루트·대화 뷰 사라짐, 창 서버도 없다고 한다. 대화 패널 깃발은 남는다(다음에 열면 그 대화).
    store.setMenuPresented(false)
    store.messageConversationViewDidDisappear(token)
    store.menuPopoverOnScreenProbe = { false }
    store.startRealtimeIfPossible()
    transport.emit(.joined)
    await messageReadWait { messageReadIdle(store) }
    let historyBefore = v0331Count(host, "message_history_with_reads")
    let summaryBefore = v0331Count(host, "message_unread_summary")

    for _ in 0..<3 {
        transport.emit(.broadcast(event: "ring"))
        await messageReadWait { messageReadIdle(store) }
    }
    try? await Task.sleep(for: .milliseconds(60))
    await messageReadWait { messageReadIdle(store) }
    #expect(v0331Count(host, "message_history_with_reads") == historyBefore, "닫힌 팝오버에 이력 조회가 붙었다")
    #expect(v0331Count(host, "message_unread_summary") - summaryBefore <= 3, "도착 3건에 요약이 3건 넘게 나갔다")
    #expect(v0331Count(host, "mark_messages_read") == 0)
    #expect(store.messageReadRuntime.activityTask == nil && store.messageReadRuntime.activityWindowTask == nil, "도착이 끝났는데 도는 작업이 남았다(주기 요청)")

    // 앱 비활성으로 화면에서만 사라져 SwiftUI 가 모르는 경우(뷰 표식이 남음): 창 서버가 "없다" → 이력은 도착당 최대 1, 읽음은 0.
    store.messageConversationViewDidAppear(token)
    let hiddenHistoryBefore = v0331Count(host, "message_history_with_reads")
    for _ in 0..<2 {
        transport.emit(.broadcast(event: "ring"))
        await messageReadWait { messageReadIdle(store) }
    }
    try? await Task.sleep(for: .milliseconds(60))
    await messageReadWait { messageReadIdle(store) }
    #expect(v0331Count(host, "message_history_with_reads") - hiddenHistoryBefore <= 2)
    #expect(v0331Count(host, "mark_messages_read") == 0, "창 서버가 안 떠 있다고 하는데 읽음으로 올렸다")
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 로그아웃_뒤_늦게_온_take_pokes_는_다음_계정의_대화에_안_들어간다() async {
    let epoch = Int(Date().timeIntervalSince1970)
    let takeGate = MessageReadStubGate()
    let (store, host) = makeMessageReadStore("late-take", handler: v0331Server(epoch: epoch, takeGate: takeGate))
    store.startedAt = Date().addingTimeInterval(-600)
    let token = UUID()
    await v0331OpenConversation(store, viewToken: token, menu: true)
    let drain = Task { @MainActor in await store.drainReceivedPokes() }
    await messageReadWait { v0331Count(host, "take_pokes") == 1 }

    // 계정 전환 — 다음 계정도 같은 상대와의 대화를 연다(가장 나쁜 겹침).
    store.clearPersistedSession()
    store.session = SupabaseSession(accessToken: "next-token", refreshToken: nil, userID: Fx.peerB)
    store.isMessagePanelVisible = true
    store.selectedMessagePeerID = Fx.peerA
    store.isMenuPresented = true

    takeGate.open()
    _ = await drain.value
    #expect(!store.messageHistory.contains { $0.id == "m1" }, "앞 계정이 소비한 말이 다음 계정의 대화에 들어갔다")
    #expect(store.messageReadRuntime.localArrivalSerials.isEmpty)
    #expect(store.receivedMessages.isEmpty)
    await messageReadWait { messageReadIdle(store) }
}

// MARK: - M4 수리(m4-fix) — 적대적 검증이 실측으로 찾은 틈
//
// 검증자 프로브(스크래치 사본, 6138a45)의 실제 출력:
//  · P2  근무 밖 초인종에서 요약 응답만 1.2초 붙잡으면 보이는 대화의 이력이 **한 건도 안 떠났다**(historyLaunched=0 · ids=["m0"]).
//        요약 왕복 → 이력 왕복의 줄 서기라 근무 밖은 2~3왕복(P2c: 근무 중 0.31초 대 근무 밖 0.83초).
//  · P2b 요약이 이력보다 먼저 반영돼, 보고 있는 대화인데 새 말이 그려지기 전에 메뉴바·레일 점이 한 왕복 동안 켜졌다.
//  · P1  같은 초의 두 말(서버 순서 z-first → a-second)을 즉시 삽입하면 id 사전순으로 뒤집혀 그려지고 읽음 경계를 앞 말로 올렸다.
//  · H05/H06 즉시 삽입분을 서버 순서 뒤에 두는 가드(effectiveOrder)를 점·말풍선 판정에서 걷어도 스위트가 초록이었다.

/// 수리 테스트의 서버 모형(보냄 · 읽음 경계). 읽음 경계는 서버처럼 **더 나중 말로만** 커진다.
final class V0331FixServerBox: @unchecked Sendable {
    private let lock = NSLock()
    private var sentFlag = false
    private var through: String?
    private let laterIDs: [String]

    /// `laterIDs` = 서버 순서(앞 → 뒤). 경계 비교에 쓴다.
    init(order laterIDs: [String] = []) { self.laterIDs = laterIDs }

    var sent: Bool { lock.lock(); defer { lock.unlock() }; return sentFlag }
    var readThrough: String? { lock.lock(); defer { lock.unlock() }; return through }
    func markSent() { lock.lock(); sentFlag = true; lock.unlock() }
    func markRead(_ id: String?) {
        lock.lock()
        defer { lock.unlock() }
        guard let id else { return }
        let old = through.flatMap { laterIDs.firstIndex(of: $0) } ?? -1
        let new = laterIDs.firstIndex(of: id) ?? -1
        if through == nil || new > old { through = id }
    }
    /// 경계가 `id` 를 덮었는가(서버 순서 기준).
    func isRead(_ id: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard let through, let t = laterIDs.firstIndex(of: through), let i = laterIDs.firstIndex(of: id) else { return false }
        return i <= t
    }
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 근무_밖_초인종은_요약_응답을_기다리지_않고_보이는_대화의_이력을_곧바로_띄운다() async {
    let epoch = Int(Date().timeIntervalSince1970)
    let state = V0331ServerState()
    let summaryGate = MessageReadStubGate()
    let transport = FakeRealtimeTransport()
    let base = v0331Server(epoch: epoch, state: state)
    let (store, host) = makeMessageReadStore("idle-ring-parallel", transport: transport) { call, index in
        guard var reply = base(call, index) else { return nil }
        // 보낸 뒤의 요약 응답은 **전부 문에 붙잡는다** — 새 말이 요약 왕복 없이 그려지는지 본다(검증 P2 모양).
        if call.rpc == "message_unread_summary", state.hasSent { reply.gate = summaryGate }
        return reply
    }
    // 비근무 맥 · 팝오버와 대화가 떠 있다.
    await v0331OpenConversation(store, viewToken: UUID(), menu: true)
    store.startRealtimeIfPossible()
    transport.emit(.joined)
    await messageReadWait { messageReadIdle(store) }
    let historyBefore = v0331Count(host, "message_history_with_reads")
    let summaryBefore = v0331Count(host, "message_unread_summary")

    state.markSent()
    transport.emit(.broadcast(event: "ring"))
    await messageReadWait(3) { store.selectedMessageThread?.messages.map(\.id) == ["m0", "m1"] }
    await messageReadWait(3) { v0331Count(host, "message_unread_summary") > summaryBefore }
    #expect(v0331Count(host, "take_pokes") == 0, "비근무 맥이 take_pokes 를 쐈다")
    #expect(v0331Count(host, "message_unread_summary") == summaryBefore + 1, "전제: 초인종이 요약을 띄웠다(응답은 붙잡힘)")
    #expect(v0331Count(host, "message_history_with_reads") > historyBefore,
            "보이는 대화의 초인종인데 요약 응답을 기다리느라 이력 조회가 안 떠났다")
    #expect(store.selectedMessageThread?.messages.map(\.id) == ["m0", "m1"],
            "요약 응답이 붙잡혀 있다고 보이는 대화에 새 말이 안 그려졌다(요약 → 이력 줄 서기)")

    // 붙잡혔던 요약도 끝내 반영된다(나란히 띄웠을 뿐 버리지 않는다).
    summaryGate.open()
    await messageReadWait { messageReadIdle(store) && store.messageUnreadSummary != nil }
    #expect(store.messageUnreadSummary != nil, "붙잡혔던 요약이 반영되지 않았다")
    store.tickerTask?.cancel()
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 근무_밖_초인종에서_이력이_도는_동안_요약이_보고_있는_대화의_점을_먼저_켜지_않는다() async {
    let epoch = Int(Date().timeIntervalSince1970)
    let box = V0331FixServerBox(order: ["m0", "m1"])
    let historyGate = MessageReadStubGate()
    let transport = FakeRealtimeTransport()
    let (store, host) = makeMessageReadStore("idle-ring-dot", transport: transport) { call, _ in
        switch call.rpc {
        case "message_history_with_reads":
            var rows = [Fx.readsRow(id: "m0", peer: Fx.peerA, isMine: false, body: "먼저", epoch: epoch - 120, unread: false)]
            guard box.sent else { return Fx.historyReply(rows) }
            rows.append(Fx.readsRow(id: "m1", peer: Fx.peerA, isMine: false, body: "새 말", epoch: epoch - 1, unread: !box.isRead("m1")))
            return Fx.historyReply(rows, gate: historyGate)
        case "message_unread_summary":
            // 서버는 사실대로 답한다: 보냈고 아직 안 읽었으면 그 상대 1건.
            return (box.sent && !box.isRead("m1")) ? Fx.summaryReply([(Fx.peerA, 1)]) : Fx.summaryReply([])
        case "mark_messages_read":
            box.markRead(call.json["p_through"] as? String)
            return Fx.markReply()
        default: return nil
        }
    }
    await v0331OpenConversation(store, viewToken: UUID(), menu: true)
    store.startRealtimeIfPossible()
    transport.emit(.joined)
    await messageReadWait { messageReadIdle(store) }
    #expect(!store.hasUnreadMessages, "전제: 점 없음")
    let historyBefore = v0331Count(host, "message_history_with_reads")
    let summaryBefore = v0331Count(host, "message_unread_summary")

    box.markSent()
    transport.emit(.broadcast(event: "ring"))
    await messageReadWait(3) {
        v0331Count(host, "message_history_with_reads") > historyBefore && v0331Count(host, "message_unread_summary") > summaryBefore
    }
    // 요약 응답(붙잡지 않음)이 돌아와 처리될 틈 — 그 사이 점이 한 번이라도 켜지면 곧바로 빨강.
    await messageReadWait(0.6) { store.hasUnreadMessages }
    #expect(store.selectedMessageThread?.messages.map(\.id) == ["m0"], "전제: 이력 응답은 아직 붙잡혀 있다")
    #expect(!store.hasUnreadMessages, "보고 있는 대화에 온 말인데, 새 말이 그려지기 전에 요약이 메뉴바·레일 점을 먼저 켰다")

    historyGate.open()
    await messageReadWait { messageReadIdle(store) && store.selectedMessageThread?.messages.count == 2 }
    try? await Task.sleep(for: .milliseconds(40))
    await messageReadWait { messageReadIdle(store) }
    #expect(store.selectedMessageThread?.messages.map(\.id) == ["m0", "m1"])
    #expect(!store.hasUnreadMessages, "보고 있는 대화의 새 말이 반영된 뒤에도 점이 남았다")
    #expect(box.isRead("m1"), "보고 있는 대화의 새 말을 읽음으로 안 올렸다")
    store.tickerTask?.cancel()
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 이력_조회가_실패해도_나란히_띄운_요약은_반영된다() async {
    // 요약을 이력 뒤에 반영하는 대가가 "이력이 실패하면 요약도 잃는다"가 되면 안 된다 — 다른 사람의 점이 그 실패에 묶인다.
    let (store, host) = makeMessageReadStore("history-fails-summary-lands") { call, _ in
        switch call.rpc {
        case "message_history_with_reads": return MessageReadStubProtocol.Reply(status: 503, body: "{}")
        case "message_unread_summary": return Fx.summaryReply([(Fx.peerB, 2)])
        default: return nil
        }
    }
    await store.requestMessageActivityRefresh(includeHistory: true)?.value
    await messageReadWait { messageReadIdle(store) }
    #expect(v0331Count(host, "message_history_with_reads") >= 1)
    #expect(store.messageUnreadSummary?.summary.unreadPeerIDs == [Fx.peerB], "이력 실패에 요약까지 버려졌다")
    #expect(store.unreadMessagePeerIDs == [Fx.peerB])
}

@MainActor
@Test(.gomokuDefaultsCleanup, arguments: [true, false])
func 같은_초에_온_두_말은_도착_순서대로_그려지고_읽음_경계는_나중_말이다(oneDrain: Bool) async {
    // 서버 순서(created_at 마이크로초) = z-first → a-second. **id 사전순과 반대**로 둔다 — 같으면 id 로 깨도 초록이다(검증 P1).
    let epoch = Int(Date().timeIntervalSince1970)
    let box = V0331FixServerBox(order: ["m0", "z-first", "a-second"])
    let hold = MessageReadStubGate()
    let (store, host) = makeMessageReadStore("same-second-\(oneDrain)") { call, index in
        switch call.rpc {
        case "message_history_with_reads":
            var rows = [Fx.readsRow(id: "m0", peer: Fx.peerA, isMine: false, body: "먼저", epoch: epoch - 120, unread: false)]
            if box.sent {
                rows.append(Fx.readsRow(id: "z-first", peer: Fx.peerA, isMine: false, body: "첫째", epoch: epoch, unread: !box.isRead("z-first")))
                rows.append(Fx.readsRow(id: "a-second", peer: Fx.peerA, isMine: false, body: "둘째", epoch: epoch, unread: !box.isRead("a-second")))
            }
            // 대화 열기(0) 뒤의 이력은 전부 붙잡는다 — 재는 순간은 take_pokes 응답 직후(서버 순서를 아직 모른다)다.
            return Fx.historyReply(rows, gate: index >= 1 ? hold : nil)
        case "message_unread_summary": return Fx.summaryReply([])
        case "mark_messages_read":
            box.markRead(call.json["p_through"] as? String)
            return Fx.markReply()
        case "take_pokes":
            box.markSent()
            let first = Fx.takenMessageRow(id: "z-first", from: Fx.peerA, epoch: epoch, body: "첫째")
            let second = Fx.takenMessageRow(id: "a-second", from: Fx.peerA, epoch: epoch, body: "둘째")
            let rows: [[String: Any]]
            if oneDrain {
                rows = index == 0 ? [first, second] : []
            } else {
                rows = index == 0 ? [first] : (index == 1 ? [second] : [])
            }
            return MessageReadStubProtocol.Reply(body: Fx.json(rows))
        default: return nil
        }
    }
    store.startedAt = Date().addingTimeInterval(-600)
    await v0331OpenConversation(store, viewToken: UUID(), menu: true)

    _ = await store.drainReceivedPokes()
    if !oneDrain { _ = await store.drainReceivedPokes() }
    let label = "oneDrain=\(oneDrain)"
    #expect(store.messageHistory.map(\.id) == ["m0", "z-first", "a-second"], "같은 초 두 말이 id 사전순으로 뒤집혀 들어갔다 — \(label)")
    #expect(store.selectedMessageThread?.messages.map(\.body) == ["먼저", "첫째", "둘째"], "열린 대화에 같은 초 두 말이 뒤집혀 그려졌다 — \(label)")
    // 읽음 경계: 한 번에 왔으면 나중 말 하나로. 두 번에 왔으면 온 차례대로(앞 말 → 나중 말) — 어느 쪽이든 이력 응답을 기다리지 않는다.
    let expectedMarks = oneDrain ? ["a-second"] : ["z-first", "a-second"]
    let marks = { MessageReadStubProtocol.calls(host: host, rpc: "mark_messages_read").map { $0.json["p_through"] as? String ?? "nil" } }
    await messageReadWait(3) { marks() == expectedMarks }
    #expect(marks() == expectedMarks, "이력 응답 전 읽음 경계가 \(marks()) 다 — \(label)")

    hold.open()
    await messageReadWait { messageReadIdle(store) }
    try? await Task.sleep(for: .milliseconds(40))
    await messageReadWait { messageReadIdle(store) }
    #expect(store.selectedMessageThread?.messages.map(\.body) == ["먼저", "첫째", "둘째"], "서버 이력 뒤 순서가 바뀌었다 — \(label)")
    #expect(marks() == expectedMarks, "서버 이력 뒤 읽음 처리가 한 번 더 나갔다(경계를 앞 말로 올렸었다): \(marks()) — \(label)")
    #expect(!store.hasUnreadMessages)
    #expect(store.messageReadRuntime.localArrivalSerials.isEmpty)
}

@Test
func 같은_초_동률은_서버_자리_다음_도착_번호_다음_id_로_깬다() {
    let at = Date(timeIntervalSince1970: 1_790_000_000)
    let entry = { (id: String) in
        MessageHistoryEntry(id: id, peerUserID: Fx.peerA, peerName: "상대", peerAvatarURL: nil, body: id, createdAt: at, isMine: false)
    }
    let earlier = MessageHistoryEntry(id: "zz-earlier", peerUserID: Fx.peerA, peerName: "상대", peerAvatarURL: nil, body: "앞",
                                      createdAt: at.addingTimeInterval(-1), isMine: false)
    let entries = [entry("a-arrived-late"), entry("m-known"), entry("b-arrived-first"), entry("c-unknown"), earlier]
    let arrival = ["b-arrived-first": 7, "a-arrived-late": 9]
    // 서버 순서가 있으면: 서버가 아는 말 → 모르는 말(도착분 아님, id) → 도착분(도착 번호). 초가 다르면 초가 먼저다.
    let withServer = entries.sortedForMessageHistory(serverOrder: ["m-known": 0], arrivalOrder: arrival).map(\.id)
    #expect(withServer == ["zz-earlier", "m-known", "c-unknown", "b-arrived-first", "a-arrived-late"])
    // 옛 서버(서버 순서 없음)도 도착분은 같은 초의 다른 말 뒤, 그들끼리는 도착 순서.
    let legacy = Array(entries.reversed()).sortedForMessageHistory(serverOrder: nil, arrivalOrder: arrival).map(\.id)
    #expect(legacy == ["zz-earlier", "c-unknown", "m-known", "b-arrived-first", "a-arrived-late"])
    // 표가 비면 예전 규칙 그대로(id).
    #expect(entries.sortedForMessageHistory().map(\.id) == ["zz-earlier", "a-arrived-late", "b-arrived-first", "c-unknown", "m-known"])
    // 대화 묶음도 같은 표를 쓴다.
    #expect(MessageThreadBuilder.threads(from: entries, serverOrder: ["m-known": 0], arrivalOrder: arrival).first?.messages.map(\.id) == withServer)
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 삽입보다_먼저_띄운_이력이_반영돼도_같은_초_도착분은_도착_순서를_지킨다() async {
    let epoch = Int(Date().timeIntervalSince1970)
    let gate = MessageReadStubGate()
    let (store, host) = makeMessageReadStore("same-second-kept") { call, index in
        switch call.rpc {
        case "message_history_with_reads":
            let rows = [Fx.readsRow(id: "m0", peer: Fx.peerA, isMine: false, body: "먼저", epoch: epoch - 120, unread: false)]
            return Fx.historyReply(rows, gate: index == 1 ? gate : nil)
        case "message_unread_summary": return Fx.summaryReply([])
        case "mark_messages_read": return Fx.markReply()
        default: return nil
        }
    }
    await v0331OpenConversation(store, viewToken: UUID(), menu: true)
    // 삽입 전에 띄운 이력(두 말을 모른다) — 붙잡힌다.
    let early = Task { @MainActor in await store.performLoadMessageHistory() }
    await messageReadWait { v0331Count(host, "message_history_with_reads") == 2 }
    let row = { (id: String, body: String) in
        TakenPokeRow(id: id, fromUser: Fx.peerA, fromDisplayName: "상대", fromAvatarUrl: nil, createdEpoch: epoch, kind: "message", body: body)
    }
    // take_pokes 행 순서 = 서버 순서(z-first → a-second), id 사전순의 반대.
    let inserted = store.insertConsumedMessagesIntoVisibleConversation(
        WorkTimerStore.consumedMessageEntries(rows: [row("z-first", "첫째"), row("a-second", "둘째")], receiptsKnown: true)
    )
    #expect(inserted == 2)
    #expect(store.messageHistory.map(\.id) == ["m0", "z-first", "a-second"])

    gate.open()
    await early.value
    #expect(store.messageHistory.map(\.id) == ["m0", "z-first", "a-second"],
            "삽입 전에 띄운 이력을 반영하며 남긴 도착분이 id 사전순으로 뒤집혔다")
    #expect(store.selectedMessageThread?.messages.map(\.id) == ["m0", "z-first", "a-second"])
    await messageReadWait { messageReadIdle(store) }
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 한_번의_drain_으로_같은_상대의_두_말이_보이는_대화에_들어와도_점도_말풍선도_없다() async {
    // 요약·이력·읽음 응답을 전부 붙잡는다 — 즉시 삽입한 두 말의 판정이 **서버 순서가 모르는 id** 로만 서는 순간을 잰다(검증 P6).
    // 앞 말(m1)은 낙관 읽음 경계(m2)의 id 와 같지 않으므로, 즉시 삽입분을 서버 순서 뒤에 두는 순서표 없이는 "덮이지 않음"으로 읽힌다.
    let epoch = Int(Date().timeIntervalSince1970)
    let box = V0331FixServerBox()
    let hold = MessageReadStubGate()
    let (store, _) = makeMessageReadStore("two-in-one-drain") { call, index in
        switch call.rpc {
        case "message_history_with_reads":
            let rows = [Fx.readsRow(id: "m0", peer: Fx.peerA, isMine: false, body: "먼저", epoch: epoch - 120, unread: false)]
            return Fx.historyReply(rows, gate: box.sent ? hold : nil)
        case "message_unread_summary": return Fx.summaryReply([], gate: box.sent ? hold : nil)
        case "mark_messages_read":
            return MessageReadStubProtocol.Reply(body: Fx.json(["status": "ok", "advanced": true, "unread": 0]), gate: hold)
        case "take_pokes":
            box.markSent()
            let rows = index == 0 ? [Fx.takenMessageRow(id: "m1", from: Fx.peerA, epoch: epoch - 2, body: "하나"),
                                     Fx.takenMessageRow(id: "m2", from: Fx.peerA, epoch: epoch - 1, body: "둘")] : []
            return MessageReadStubProtocol.Reply(body: Fx.json(rows))
        default: return nil
        }
    }
    store.startedAt = Date().addingTimeInterval(-600)
    await v0331OpenConversation(store, viewToken: UUID(), menu: true)

    _ = await store.drainReceivedPokes()
    #expect(store.selectedMessageThread?.messages.map(\.id) == ["m0", "m1", "m2"])
    #expect(store.messageOptimisticReads[Fx.peerA]?.throughID == "m2", "전제: 경계는 나중 말")
    #expect(!store.hasUnreadMessages, "보고 있는 대화에 한 번에 들어온 두 말 중 앞 말이 메뉴바·레일·목록 점을 켰다")
    #expect(store.unreadMessagePeerIDs.isEmpty)
    #expect(store.receivedMessages.isEmpty, "보고 있는 대화에 방금 뜬 앞 말이 캐릭터 말풍선 큐에도 올랐다: \(store.receivedMessages.map(\.id))")
    hold.open()
    await messageReadWait { messageReadIdle(store) }
}

// MARK: - 뷰 ↔ 스토어 배선 (소스 계약)

@Test
func 대화_뷰가_생명주기를_스토어에_알리고_앱이_창_서버_질의를_꽂는다() throws {
    let view = try v0331Source("CheckMessageView.swift")
    #expect(view.contains("store.messageConversationViewDidAppear(viewToken)"), "대화 뷰가 나타남을 스토어에 안 알린다")
    #expect(view.contains("store.messageConversationViewDidDisappear(viewToken)"), "대화 뷰가 사라짐을 스토어에 안 알린다")
    let app = try v0331Source("CheckApp.swift")
    #expect(app.contains("store.menuPopoverOnScreenProbe = { WindowTopAnchor.menuPopoverOnScreen() }"), "앱이 창 서버 질의를 스토어에 꽂지 않는다")
    let poke = try v0331Source("WorkTimerStorePoke.swift")
    #expect(poke.contains("receiveConsumedMessages(rows: rows, now: now)"), "drain 이 즉시 삽입 문을 지나지 않는다")
    let messages = try v0331Source("WorkTimerStoreMessages.swift")
    // 옛 한 칸 게이트가 되살아나지 않았다.
    #expect(!messages.contains("isMenuPresented && isMessagePanelVisible"), "도착 갱신 게이트가 옛 isMenuPresented 한 칸으로 돌아갔다")
    #expect(!messages.contains("guard session != nil, isMenuPresented, isMessagePanelVisible"), "읽음 판정이 옛 한 칸으로 돌아갔다")
}

func v0331Source(_ name: String) throws -> String {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/check/\(name)")
    return v0331StripComments(try String(contentsOf: url, encoding: .utf8))
}

/// `//`·`/* */` 주석을 걷어낸다(문자열 안의 `//` 는 남긴다) — 설명문의 낱말이 단언에 걸려 "주석을 지워야 초록"이 되지 않게.
func v0331StripComments(_ source: String) -> String {
    var out = ""
    var inLine = false, inBlock = false, inString = false, escaped = false
    var index = source.startIndex
    while index < source.endIndex {
        let c = source[index]
        let nextIndex = source.index(after: index)
        let next: Character? = nextIndex < source.endIndex ? source[nextIndex] : nil
        if inLine {
            if c == "\n" { inLine = false; out.append(c) }
        } else if inBlock {
            if c == "*", next == "/" { inBlock = false; index = nextIndex }
        } else if inString {
            out.append(c)
            if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { inString = false }
        } else if c == "/", next == "/" {
            inLine = true; index = nextIndex
        } else if c == "/", next == "*" {
            inBlock = true; index = nextIndex
        } else if c == "\"" {
            inString = true; out.append(c)
        } else {
            out.append(c)
        }
        index = source.index(after: index)
    }
    return out
}
