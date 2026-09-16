import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// v0.3.31 M4 — **화면** 쪽: 열린 대화에 새 줄이 재오픈 없이 그려지는가 · 바닥 따라가기 · "새 메시지 ↓".
//
// 스토어 규칙은 V0331MessageArrivalTests 가 잰다. 여기는 뷰가 그것을 실제로 쓰는가다 — 스토어가 새 말을 넣어도 뷰가
// 대화 뷰 생명주기를 안 알리거나(판정이 옛 한 칸으로 돌아감) 스크롤이 새 줄을 화면 밖에 붙이면 사용자에게는 똑같이 "안 뜬다".
//
// ★ 창은 **화면에 올리지 않는다**(orderFront 없음 — 테두리 없는 창에 붙이기만 한다). 사용자가 이 맥을 쓰는 중이라 테스트 창이 클릭을
//   가로채면 안 되고(부록 C), 레이아웃·스크롤·그리기는 창에 붙이는 것만으로 돈다(V0249 의 입력칸 측정과 같은 수법).

private typealias Fx = MessageReadFixture

@MainActor
private func v0331Spin(_ seconds: Double = 0.05) {
    RunLoop.current.run(until: Date().addingTimeInterval(seconds))
}

@MainActor
private func v0331FirstSubview<T: NSView>(of root: NSView, _ type: T.Type) -> T? {
    if let match = root as? T { return match }
    for child in root.subviews {
        if let match = v0331FirstSubview(of: child, type) { return match }
    }
    return nil
}

/// 화면에 올리지 않는 창에 붙인 호스팅 뷰.
@MainActor
private func v0331Mount<V: View>(_ view: V, width: CGFloat, height: CGFloat) -> (NSWindow, NSHostingView<AnyView>) {
    let host = NSHostingView(rootView: AnyView(
        view.frame(width: width, height: height, alignment: .top).background(CheckTheme.background)
    ))
    host.frame = NSRect(x: 0, y: 0, width: width, height: height)
    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    v0331Spin(0.1)
    host.layoutSubtreeIfNeeded()
    return (window, host)
}

/// AppKit 이 그린 픽셀(2x). ScrollView 안쪽도 그려진다(ImageRenderer 와 다르다).
@MainActor
private func v0331Bitmap(_ host: NSView) -> NSBitmapImageRep? {
    host.layoutSubtreeIfNeeded()
    let size = host.bounds.size
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { return nil }
    rep.size = size
    guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    host.displayIgnoringOpacity(host.bounds, in: context)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

/// 두 그림의 다른 픽셀 수(채널 합 차이 > 24). 크기가 다르면 -1.
private func v0331DiffCount(_ lhs: NSBitmapImageRep, _ rhs: NSBitmapImageRep) -> Int {
    guard lhs.pixelsWide == rhs.pixelsWide, lhs.pixelsHigh == rhs.pixelsHigh,
          let a = lhs.bitmapData, let b = rhs.bitmapData else { return -1 }
    let bpr = lhs.bytesPerRow, spp = lhs.samplesPerPixel
    var count = 0
    for y in 0..<lhs.pixelsHigh {
        for x in 0..<lhs.pixelsWide {
            let o = y * bpr + x * spp
            let d = abs(Int(a[o]) - Int(b[o])) + abs(Int(a[o + 1]) - Int(b[o + 1])) + abs(Int(a[o + 2]) - Int(b[o + 2]))
            if d > 24 { count += 1 }
        }
    }
    return count
}

/// 아래쪽 `bottomStripPoints` 띠 안의 accent(84,171,255) 계열 픽셀 수(2x 그림).
private func v0331AccentPixels(_ bitmap: NSBitmapImageRep, bottomStripPoints: CGFloat) -> Int {
    guard let data = bitmap.bitmapData else { return -1 }
    let bpr = bitmap.bytesPerRow, spp = bitmap.samplesPerPixel
    let rows = min(bitmap.pixelsHigh, Int(bottomStripPoints * 2))
    var count = 0
    for y in (bitmap.pixelsHigh - rows)..<bitmap.pixelsHigh {
        for x in 0..<bitmap.pixelsWide {
            let o = y * bpr + x * spp
            let r = Int(data[o]), g = Int(data[o + 1]), b = Int(data[o + 2])
            if b > 200, r < 130, g > 130, g < 210 { count += 1 }
        }
    }
    return count
}

private func v0331Entry(_ id: String, _ body: String, secondsAgo: TimeInterval, isMine: Bool = false) -> MessageHistoryEntry {
    MessageHistoryEntry(
        id: id, peerUserID: Fx.peerA, peerName: "민수", peerAvatarURL: nil, body: body,
        createdAt: Date().addingTimeInterval(-secondsAgo), isMine: isMine,
        readByPeer: isMine ? true : nil, isUnread: isMine ? nil : false
    )
}

// MARK: - 열린 대화에 새 줄이 재오픈 없이 그려진다

@MainActor
@Test(.gomokuDefaultsCleanup)
func 열린_대화_화면에_도착한_새_줄이_재오픈_없이_그려진다() async throws {
    let (store, _) = makeMessageReadStore("view-arrival") { call, _ in
        switch call.rpc {
        case "message_unread_summary": return Fx.summaryReply([])
        default: return nil
        }
    }
    let now = Date()
    store.messageHistory = [v0331Entry("m0", "점심 뭐 먹어요?", secondsAgo: 120, isMine: true)]
    store.messageHistoryReadSnapshot = MessageHistoryReadSnapshot(serial: 1, serverOrder: ["m0": 0])
    store.messageReadReceiptsAvailable = true
    store.messageHistoryLoaded = true
    store.isMessagePanelVisible = true
    store.selectedMessagePeerID = Fx.peerA
    // 신고의 상태: 팝오버는 떠 있는데 표시 칸은 false 로 굳었다. 뷰 자신의 생명주기가 판정을 지켜야 한다.
    store.isMenuPresented = false

    let make = {
        CheckMessageView(store: store, rendersPlainTextEditor: true, now: now, onBack: {})
            .frame(width: CheckMenuView.contentColumnWidth)
    }
    let (window, host) = v0331Mount(make(), width: CheckMenuView.contentColumnWidth, height: 520)
    defer { window.contentView = nil; window.close() }
    #expect(!store.messageConversationViewTokens.isEmpty, "대화 뷰가 나타남을 스토어에 알리지 않았다 — 판정이 옛 한 칸으로 돌아간다")
    #expect(store.isMessageConversationOnScreen, "뷰가 떠 있는데 스토어가 대화가 안 보인다고 판정한다")
    let before = try #require(v0331Bitmap(host))

    // drain 이 소비한 행이 들어오는 문 그대로(take_pokes 응답 직후 · 이력 왕복 없음).
    let epoch = Int(now.timeIntervalSince1970) - 1
    store.receiveConsumedMessages(rows: [
        TakenPokeRow(id: "m1", fromUser: Fx.peerA, fromDisplayName: "민수", fromAvatarUrl: nil,
                     createdEpoch: epoch, kind: "message", body: "김치찌개 어때요")
    ], now: now)
    #expect(store.selectedMessageThread?.messages.map(\.id) == ["m0", "m1"])
    v0331Spin(0.4)
    let after = try #require(v0331Bitmap(host))

    // 같은 상태를 **새로 열어** 그린 그림 — 재오픈하면 보이는 화면이 곧 기대값이다.
    let (freshWindow, freshHost) = v0331Mount(make(), width: CheckMenuView.contentColumnWidth, height: 520)
    defer { freshWindow.contentView = nil; freshWindow.close() }
    let reopened = try #require(v0331Bitmap(freshHost))

    let changed = v0331DiffCount(after, before)
    let fromReopened = v0331DiffCount(after, reopened)
    #expect(changed > 400, "도착 뒤 열린 화면이 거의 안 바뀌었다(새 줄이 안 그려졌다): \(changed)px")
    #expect(fromReopened >= 0 && fromReopened < 40, "열린 화면과 다시 연 화면이 다르다(재오픈해야 보인다): \(fromReopened)px")
    await messageReadWaitSync(store)
}

// MARK: - 대화 뷰 생명주기 배선(런타임)
//
// m4-fix: 소스 계약(V0331MessageArrivalTests)은 호출 **글자**만 본다 — `.onDisappear { if Int("0") == 1 { … } }` 로 죽여도 초록이었다
// (검증 변이 H01 생존). 깨지면 표식이 새서 닫힌 팝오버를 계속 "보인다"로 판정하고, 도착마다 삽입·이력 조회가 붙는다.

@MainActor
@Test(.gomokuDefaultsCleanup)
func 대화_뷰가_창에서_내려가면_스토어의_표식이_빠지고_다시_올리면_돌아온다() async throws {
    let (store, _) = makeMessageReadStore("view-lifecycle") { call, _ in
        call.rpc == "message_unread_summary" ? Fx.summaryReply([]) : nil
    }
    store.messageHistory = [v0331Entry("m0", "안녕", secondsAgo: 60)]
    store.messageHistoryLoaded = true
    store.isMessagePanelVisible = true
    store.selectedMessagePeerID = Fx.peerA
    store.isMenuPresented = false
    let make = { CheckMessageView(store: store, rendersPlainTextEditor: true, now: Date(), onBack: {}) }
    let width = CheckMenuView.contentColumnWidth

    let (window, host) = v0331Mount(make(), width: width, height: 400)
    defer { window.contentView = nil; window.close() }
    #expect(store.messageConversationViewTokens.count == 1, "대화 뷰가 나타남을 스토어에 알리지 않았다")
    #expect(store.isMessageConversationOnScreen)

    // 대화 뷰를 다른 화면으로 갈아 끼운다([뒤로]·팝오버 콘텐츠 내려감과 같은 SwiftUI 사라짐). 창은 화면에 올리지 않는다.
    host.rootView = AnyView(Color.clear.frame(width: 10, height: 10))
    host.layoutSubtreeIfNeeded()
    v0331Spin(0.3)
    #expect(store.messageConversationViewTokens.isEmpty, "대화 뷰가 내려갔는데 표식이 남았다 — 닫힌 대화를 계속 '보인다'로 판정한다")
    #expect(!store.isMessageConversationOnScreen, "대화 뷰가 내려갔는데 스토어가 대화가 떠 있을 수 있다고 판정한다")

    // 다시 올리면 새 표식 하나(옛 표식이 되살아나 둘이 되지 않는다).
    host.rootView = AnyView(make().frame(width: width, height: 400, alignment: .top))
    host.layoutSubtreeIfNeeded()
    v0331Spin(0.3)
    #expect(store.messageConversationViewTokens.count == 1, "다시 올린 대화 뷰의 표식이 \(store.messageConversationViewTokens.count) 개다")
    await messageReadWaitSync(store)
}

/// 스토어가 띄운 요약 조회 등이 끝나도록 런루프를 잠깐 돌린다(동기 테스트용).
@MainActor
private func messageReadWaitSync(_ store: WorkTimerStore) async {
    await messageReadWait { messageReadIdle(store) }
}

// MARK: - 바닥 따라가기 / 새 메시지 버튼 (호스팅)

@MainActor
final class V0331FollowBox {
    var last: MessageScrollFollow?
}

@MainActor
private func v0331Conversation(_ entries: [MessageHistoryEntry], box: V0331FollowBox) -> some View {
    MessageConversationView(
        items: MessageThreadBuilder.timeline(entries, now: Date()),
        peerUserID: Fx.peerA,
        lastMessageID: entries.last?.id,
        lastMessageIsMine: entries.last?.isMine ?? false,
        readReceiptsAvailable: true,
        onFollowChange: { box.last = $0 }
    )
}

/// 바닥까지 남은 거리(pt). 문서 뷰가 뒤집혔든 아니든 같은 뜻으로 잰다.
@MainActor
private func v0331DistanceFromBottom(_ scrollView: NSScrollView) -> CGFloat {
    let clip = scrollView.contentView
    guard let document = scrollView.documentView else { return 0 }
    if document.isFlipped {
        return document.frame.height - clip.bounds.maxY
    }
    return clip.bounds.minY
}

@MainActor
private func v0331ScrollToTop(_ scrollView: NSScrollView) {
    guard let document = scrollView.documentView else { return }
    let clip = scrollView.contentView
    let y = document.isFlipped ? 0 : max(0, document.frame.height - clip.bounds.height)
    clip.scroll(to: NSPoint(x: 0, y: y))
    scrollView.reflectScrolledClipView(clip)
}

@MainActor
private func v0331ScrollToBottom(_ scrollView: NSScrollView) {
    guard let document = scrollView.documentView else { return }
    let clip = scrollView.contentView
    let y = document.isFlipped ? max(0, document.frame.height - clip.bounds.height) : 0
    clip.scroll(to: NSPoint(x: 0, y: y))
    scrollView.reflectScrolledClipView(clip)
}

@MainActor
@Test
func 바닥에서_보던_대화는_새_말을_따라가고_위로_올려_둔_대화는_끌어내리지_않고_버튼을_띄운다() throws {
    let box = V0331FollowBox()
    var entries = (0..<30).map { v0331Entry("h\($0)", "이전 대화 \($0) 번째 줄입니다", secondsAgo: TimeInterval(3000 - $0 * 60)) }
    let width = MessagePanelLayout.contentWidth
    let height: CGFloat = 200
    let (window, host) = v0331Mount(v0331Conversation(entries, box: box), width: width, height: height)
    defer { window.contentView = nil; window.close() }
    let scrollView = try #require(v0331FirstSubview(of: host, NSScrollView.self), "대화 안에 스크롤 뷰가 없다")
    v0331Spin(0.2)
    #expect(v0331DistanceFromBottom(scrollView) <= MessageScrollFollow.nearBottomThreshold, "처음 열었는데 바닥이 아니다")

    func deliver(_ entry: MessageHistoryEntry) {
        entries.append(entry)
        host.rootView = AnyView(
            v0331Conversation(entries, box: box).frame(width: width, height: height, alignment: .top).background(CheckTheme.background)
        )
        host.layoutSubtreeIfNeeded()
        v0331Spin(0.45)
        host.layoutSubtreeIfNeeded()
    }

    // ① 바닥에서 보는 중 → 새 말을 따라간다.
    deliver(v0331Entry("n1", "새로 온 첫 번째 말", secondsAgo: 5))
    #expect(v0331DistanceFromBottom(scrollView) <= MessageScrollFollow.nearBottomThreshold, "바닥에서 보던 대화가 새 말을 따라가지 않았다")
    #expect(box.last?.showsNewMessageButton != true)

    // ② 위로 올려 둔다 → 새 말이 와도 끌어내리지 않고 버튼.
    v0331ScrollToTop(scrollView)
    v0331Spin(0.2)
    let topBefore = v0331DistanceFromBottom(scrollView)
    #expect(topBefore > MessageScrollFollow.nearBottomThreshold, "전제: 위로 올렸다")
    #expect(box.last?.isNearBottom == false, "위로 올린 스크롤을 따라가기 상태가 못 들었다")
    deliver(v0331Entry("n2", "올려 둔 사이 온 말", secondsAgo: 4))
    #expect(v0331DistanceFromBottom(scrollView) > MessageScrollFollow.nearBottomThreshold, "위로 올려 둔 사람을 바닥으로 끌어내렸다")
    #expect(box.last?.showsNewMessageButton == true, "위로 올려 둔 대화에 새 말이 왔는데 \"새 메시지 ↓\" 버튼이 안 섰다")
    // 상태만이 아니라 **그려졌다**: 받은 말풍선만 있는 대화에서 accent 알약이 바닥 띠에 나타난다.
    let withButton = try #require(v0331Bitmap(host))

    // ③ 스스로 바닥에 닿으면 버튼이 사라진다.
    v0331ScrollToBottom(scrollView)
    v0331Spin(0.3)
    #expect(box.last?.showsNewMessageButton == false, "바닥에 닿았는데 버튼이 남았다")
    let withoutButton = try #require(v0331Bitmap(host))
    // 아바타 이니셜 원 같은 accent 계열이 버튼 없이도 수백 픽셀 있다(실측 ~350) — 절대값이 아니라 **버튼이 있을 때와의 차이**로 잰다
    // (실측: 버튼 있음 ~5100 · 없음 ~350).
    let accentWith = v0331AccentPixels(withButton, bottomStripPoints: 40)
    let accentWithout = v0331AccentPixels(withoutButton, bottomStripPoints: 40)
    #expect(accentWith > accentWithout + 1500,
            "\"새 메시지 ↓\" 버튼이 섰다가 사라지는 것이 화면에 안 그려졌다(바닥 띠 accent: 있음 \(accentWith) · 없음 \(accentWithout))")

    // ④ 위로 올려 둔 채 **내가** 보낸 말 → 따라간다.
    v0331ScrollToTop(scrollView)
    v0331Spin(0.2)
    deliver(v0331Entry("n3", "내가 보낸 말", secondsAgo: 3, isMine: true))
    #expect(v0331DistanceFromBottom(scrollView) <= MessageScrollFollow.nearBottomThreshold, "내가 보낸 말이 화면 밖에 붙었다")
    #expect(box.last?.showsNewMessageButton != true)
}

// MARK: - 순수 따라가기 규칙

@Test
func 따라가기_규칙_표() {
    var f = MessageScrollFollow()
    #expect(f.isNearBottom && !f.showsNewMessageButton)

    // 내용이 자란 측정은 "위로 올렸다"가 아니다(새 말의 높이만큼 멀어진 측정이 따라가기 판정보다 먼저 올 수 있다).
    f.measured(contentHeight: 1000, viewportHeight: 200, contentMaxY: 200)
    f.measured(contentHeight: 1080, viewportHeight: 200, contentMaxY: 280)
    #expect(f.isNearBottom, "새 말의 높이만큼 멀어진 측정을 사용자가 올린 것으로 읽었다")
    let followsAtBottom = f.lastMessageChanged(isMine: false)
    #expect(followsAtBottom, "바닥에서 보던 사람의 새 말을 안 따라간다")

    // 내용은 그대로인데 멀어졌다 = 사람이 올렸다.
    f.measured(contentHeight: 1080, viewportHeight: 200, contentMaxY: 200)
    f.measured(contentHeight: 1080, viewportHeight: 200, contentMaxY: 700)
    #expect(!f.isNearBottom)
    let followsWhenScrolledUp = f.lastMessageChanged(isMine: false)
    #expect(!followsWhenScrolledUp)
    #expect(f.showsNewMessageButton)
    // 경계: 60pt 안이면 바닥 근처(버튼 내림).
    f.measured(contentHeight: 1080, viewportHeight: 200, contentMaxY: 200 + MessageScrollFollow.nearBottomThreshold)
    #expect(f.isNearBottom && !f.showsNewMessageButton)
    f.measured(contentHeight: 1080, viewportHeight: 200, contentMaxY: 200 + MessageScrollFollow.nearBottomThreshold + 1)
    #expect(!f.isNearBottom)
    // 내가 보낸 말은 어디서든 따라간다.
    let followsMine = f.lastMessageChanged(isMine: true)
    #expect(followsMine)
    #expect(f.isNearBottom && !f.showsNewMessageButton)
    // 버튼 → 바닥.
    f.measured(contentHeight: 1080, viewportHeight: 200, contentMaxY: 900)
    _ = f.lastMessageChanged(isMine: false)
    #expect(f.showsNewMessageButton)
    f.jumpedToBottom()
    #expect(f.isNearBottom && !f.showsNewMessageButton)
    // 아직 못 잰 틀은 판정을 바꾸지 않는다.
    var g = MessageScrollFollow()
    g.measured(contentHeight: 0, viewportHeight: 0, contentMaxY: 900)
    #expect(g.isNearBottom)
}
