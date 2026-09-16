import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// v0.3.30 M2 — 메시지 **화면** 쪽: 보낸 말풍선 옆 안 읽음 1 · 근무 밖에서 [보내기]가 서버까지 가는가 · 콕찌르기 안내줄.
//
// 스토어 규칙(읽음 경계·요약·낙관 읽음)은 M1 스위트(V0330MessageRead*)가 잰다. 여기는 **뷰가 그 값을 실제로 쓰는가**다 —
// 서버·스토어를 다 풀어도 화면이 옛 조건으로 막거나 안 그리면 초록인 채로 아무것도 안 바뀐다(두 겹 게이트).
//
// 1 은 픽셀로 잰다(ImageRenderer, scale 2). 판정 표(순수 함수)만 재면 뷰가 그 함수를 안 부르는 결함이 초록으로 지나간다.

private let m2rNow = Date(timeIntervalSince1970: 1_790_000_000)
private let m2rPeer = MessageReadFixture.peerA

private func m2rEntry(
    id: String,
    isMine: Bool,
    readByPeer: Bool? = nil,
    isUnread: Bool? = nil,
    body: String = "점심 드셨어요?",
    secondsAgo: TimeInterval = 60
) -> MessageHistoryEntry {
    MessageHistoryEntry(
        id: id, peerUserID: m2rPeer, peerName: "민수", peerAvatarURL: nil, body: body,
        createdAt: m2rNow.addingTimeInterval(-secondsAgo), isMine: isMine,
        readByPeer: readByPeer, isUnread: isUnread
    )
}

private enum M2RRenderError: Error { case failed }

@MainActor
private func m2rBitmap(_ view: some View) throws -> NSBitmapImageRep {
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff)
    else { throw M2RRenderError.failed }
    return bitmap
}

/// 두 그림이 다른 픽셀들의 경계(pt)와 개수, 그리고 **앞 그림(lhs)에서** 그 픽셀들 중 파란(accent 계열) 것의 수.
private func m2rDiff(_ lhs: NSBitmapImageRep, _ rhs: NSBitmapImageRep) -> (count: Int, blue: Int, box: CGRect) {
    guard lhs.pixelsWide == rhs.pixelsWide, lhs.pixelsHigh == rhs.pixelsHigh,
          let a = lhs.bitmapData, let b = rhs.bitmapData else { return (-1, 0, .null) }
    let bpr = lhs.bytesPerRow, spp = lhs.samplesPerPixel
    var count = 0, blue = 0
    var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
    for y in 0..<lhs.pixelsHigh {
        for x in 0..<lhs.pixelsWide {
            let o = y * bpr + x * spp
            let d = abs(Int(a[o]) - Int(b[o])) + abs(Int(a[o + 1]) - Int(b[o + 1])) + abs(Int(a[o + 2]) - Int(b[o + 2]))
            guard d > 24 else { continue }
            count += 1
            // accent(84,171,255) 계열: 파랑이 가장 크고 빨강보다 확실히 크다.
            if Int(a[o + 2]) > 150 && Int(a[o + 2]) > Int(a[o]) + 60 { blue += 1 }
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        }
    }
    guard count > 0 else { return (0, 0, .null) }
    return (count, blue, CGRect(x: CGFloat(minX) / 2, y: CGFloat(minY) / 2,
                                width: CGFloat(maxX - minX + 1) / 2, height: CGFloat(maxY - minY + 1) / 2))
}

/// 대화 한 판(스냅샷 갈래 — ScrollView 대신 클립). 폭은 패널 안쪽 폭 그대로다.
@MainActor
private func m2rConversation(_ entries: [MessageHistoryEntry], receipts: Bool) throws -> NSBitmapImageRep {
    let items = MessageThreadBuilder.timeline(entries, now: m2rNow)
    let view = MessageConversationView(
        items: items,
        peerUserID: m2rPeer,
        lastMessageID: entries.last?.id,
        readReceiptsAvailable: receipts,
        clipsInsteadOfScrolling: true
    )
    .frame(width: MessagePanelLayout.contentWidth, height: 96)
    .background(CheckTheme.background)
    return try m2rBitmap(view)
}

private func m2rSource(_ name: String) throws -> String {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("\(CheckCoreSourceLayout.directory(for: name))/\(name)")
    return m2rStripComments(try String(contentsOf: url, encoding: .utf8))
}

/// `//`·`/* */` 주석을 걷어낸다(문자열 안의 `//` 는 남긴다) — 설명문의 낱말이 단언에 걸려 "주석을 지워야 초록"이 되지 않게.
private func m2rStripComments(_ source: String) -> String {
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

/// `from` 뒤부터 그 뒤 첫 `to` 직전까지.
private func m2rRegion(_ source: String, from start: String, to end: String) -> String? {
    guard let head = source.range(of: start) else { return nil }
    let tail = source.range(of: end, range: head.upperBound..<source.endIndex)?.lowerBound ?? source.endIndex
    return String(source[head.upperBound..<tail])
}

@MainActor
@Suite("V0330ReadReceiptView")
struct V0330ReadReceiptViewTests {
    // MARK: 1 표시 조건 — 판정 표

    @Test func 안_읽음_1은_읽음을_아는_서버에서_내가_보낸_안_읽힌_말에만_찍힌다() {
        struct Row { let isMine: Bool; let readByPeer: Bool?; let receipts: Bool; let shows: Bool }
        let table: [Row] = [
            Row(isMine: true, readByPeer: false, receipts: true, shows: true),
            Row(isMine: true, readByPeer: true, receipts: true, shows: false),
            Row(isMine: true, readByPeer: nil, receipts: true, shows: false),
            Row(isMine: true, readByPeer: false, receipts: false, shows: false),
            Row(isMine: true, readByPeer: true, receipts: false, shows: false),
            Row(isMine: true, readByPeer: nil, receipts: false, shows: false),
            // 받은 말은 값이 무엇이든 1이 없다(서버는 받은 행에 read_by_peer 를 null 로 준다 — 그래도 뷰가 isMine 을 본다).
            Row(isMine: false, readByPeer: false, receipts: true, shows: false),
            Row(isMine: false, readByPeer: nil, receipts: true, shows: false)
        ]
        for row in table {
            let entry = m2rEntry(id: "t", isMine: row.isMine, readByPeer: row.readByPeer)
            #expect(
                MessageReadReceiptMark.showsUnreadOne(for: entry, receiptsAvailable: row.receipts) == row.shows,
                "isMine=\(row.isMine) readByPeer=\(String(describing: row.readByPeer)) receipts=\(row.receipts)"
            )
        }
        #expect(MessageReadReceiptMark.text == "1")
        #expect(MessageReadReceiptMark.accessibilityLabel == "안 읽음")
    }

    // MARK: 1 표시 조건 — 실제 픽셀

    /// 같은 대화를 네 조건으로 그린다. **1 이 찍히는 조합만** 그림이 다르고, 나머지 셋은 눈에 보이는 차이가 없다.
    /// 다른 자리는 작고(글자 하나) 파랗다(accent) — 말풍선이 밀리거나 줄이 늘어난 것이 아니다.
    @Test func 말풍선_옆_1은_그_조합에서만_작은_파란_글자로_그려진다() throws {
        let received = m2rEntry(id: "r1", isMine: false, body: "네 먹었어요", secondsAgo: 120)
        func sent(_ read: Bool?) -> MessageHistoryEntry { m2rEntry(id: "s1", isMine: true, readByPeer: read, secondsAgo: 30) }

        let unread = try m2rConversation([received, sent(false)], receipts: true)
        let read = try m2rConversation([received, sent(true)], receipts: true)
        let unknown = try m2rConversation([received, sent(nil)], receipts: true)
        let oldServer = try m2rConversation([received, sent(false)], receipts: false)
        MiniGameSnapshots.save(unread, name: "v0330-read-receipt-unread.png", sub: "messages")
        MiniGameSnapshots.save(read, name: "v0330-read-receipt-read.png", sub: "messages")

        // "같다"는 **눈에 보이는 차이가 없다**(채널 합 24 초과 픽셀 0)로 잰다. 바이트 지문은 다른 렌더 스위트와 함께 돌 때
        // 아바타 재표본이 한 단계 흔들려 갈린다(실측: 코드가 같은 두 그림에서 몇 픽셀 · 채널 차 1~2). 1 은 수십 픽셀이 확 바뀐다.
        #expect(m2rDiff(unread, read).count > 10, "상대가 안 읽었는데 1 이 안 그려졌다")
        #expect(m2rDiff(read, unknown).count == 0, "읽음을 모르는(nil) 말에 무언가 그려졌다")
        #expect(m2rDiff(read, oldServer).count == 0, "읽음을 모르는 서버인데 1 이 그려졌다")

        let diff = m2rDiff(unread, read)
        #expect(diff.count > 10, "1 의 픽셀이 너무 적다(\(diff.count))")
        #expect(diff.box.width <= 10 && diff.box.height <= 14,
                "1 을 찍었더니 \(diff.box) 만큼 바뀌었다 — 말풍선이 밀렸거나 줄이 늘었다")
        #expect(diff.blue * 2 >= diff.count, "바뀐 픽셀이 accent 색이 아니다(파랑 \(diff.blue)/\(diff.count))")
        // 말풍선 **바깥**(왼쪽)이다: 보낸 말풍선은 오른쪽 끝에 붙고, 1 은 그 왼쪽 시각 위에 선다.
        #expect(diff.box.maxX < MessagePanelLayout.contentWidth - 60, "1 이 말풍선 안쪽(\(diff.box))에 그려졌다")
        // 아래쪽이다(시각과 같은 줄 높이 — 말풍선 바닥 근처).
        #expect(diff.box.minY > 40, "1 이 보낸 말풍선 줄보다 위(\(diff.box))에 있다")
    }

    /// 받은 말에는 어떤 값이 와도 1 이 없다(뷰가 isMine 을 본다).
    @Test func 받은_말에는_1이_없다() throws {
        let odd = try m2rConversation([m2rEntry(id: "r1", isMine: false, readByPeer: false)], receipts: true)
        let plain = try m2rConversation([m2rEntry(id: "r1", isMine: false, readByPeer: nil)], receipts: true)
        #expect(m2rDiff(odd, plain).count == 0)
    }

    /// 패널이 **스토어의** 읽음 기능 여부를 대화에 내린다 — 대화 뷰만 재면 패널이 기본값(false)을 넘기는 결함이 초록이다.
    @Test(.gomokuDefaultsCleanup)
    func 대화_패널은_스토어의_읽음_기능_여부를_내린다() throws {
        let store = makeMessageReadStore("m2-receipt-panel").store
        func render(receipts: Bool, read: Bool) throws -> NSBitmapImageRep {
            store.messageHistory = [
                m2rEntry(id: "r1", isMine: false, body: "네 먹었어요", secondsAgo: 120),
                m2rEntry(id: "s1", isMine: true, readByPeer: read, secondsAgo: 30)
            ]
            store.messageHistoryLoaded = true
            store.selectedMessagePeerID = m2rPeer
            store.messageReadReceiptsAvailable = receipts
            let view = CheckMessageView(
                store: store, rendersPlainTextEditor: true, clipsOverflowInsteadOfScroll: true, now: m2rNow, onBack: {}
            )
            .frame(width: CheckMenuView.contentColumnWidth)
            .background(CheckTheme.background)
            return try m2rBitmap(view)
        }
        let shown = m2rDiff(try render(receipts: true, read: false), try render(receipts: false, read: false))
        #expect(shown.count > 10 && shown.blue > 0,
                "스토어가 읽음을 안다고 했는데 패널이 1 을 안 그린다(기본값 false 를 넘기고 있다) — 차이 \(shown.count)px")
        // 대조군: 읽힌 말이면 기능 여부가 바뀌어도 눈에 보이는 차이가 없다 — 위 차이는 1 에서만 온다.
        #expect(m2rDiff(try render(receipts: true, read: true), try render(receipts: false, read: true)).count == 0)
    }

    @Test func 안_읽음_1에는_보이스오버_문구가_붙는다() throws {
        let view = try m2rSource("CheckMessageView.swift")
        let row = try #require(m2rRegion(view, from: "private struct MessageBubbleRow: View {", to: "// MARK: - 입력줄"))
        #expect(row.contains("Text(MessageReadReceiptMark.text)"))
        #expect(row.contains(".accessibilityLabel(MessageReadReceiptMark.accessibilityLabel)"), "1 이 보이스오버에 \"1\" 로만 읽힌다")
        #expect(row.contains(".foregroundStyle(CheckTheme.accent)"))
        #expect(row.contains(".monospacedDigit()"))
        // 판정은 순수 함수 하나다 — 행이나 대화가 조건을 다시 세지 않는다.
        let conversation = try #require(m2rRegion(view, from: "struct MessageConversationView: View {", to: "/// 날짜 구분선"))
        #expect(conversation.contains("MessageReadReceiptMark.showsUnreadOne("))
        #expect(!conversation.contains("readByPeer"), "대화 뷰가 readByPeer 를 직접 판정한다")
        #expect(!row.contains("readByPeer"), "말풍선 행이 readByPeer 를 직접 판정한다")
    }

    // MARK: 근무 밖 메시지 — 뷰의 문을 그대로 누른다

    /// 대조군 실험: **비근무** 사용자가 [보내기](버튼 · ⌘↩ · ↩ 이 모두 지나는 `MessageComposerView.send()`)를 누르면
    /// `send_message` 가 **1회** 나간다. 옛 코드(스토어 `sendMessage` 의 `startedAt` 선게이트)에서는 0회였다 —
    /// 그 줄을 되살리는 변이에서 이 테스트가 빨개지는 것을 보고서에 적었다.
    /// 같은 스토어에서 상대가 없으면 0회 — 카운터가 0 도 읽을 수 있다는 대조다(1 이 우연히 나온 것이 아니다).
    @Test(.gomokuDefaultsCleanup)
    func 비근무_사용자의_보내기_문은_서버까지_간다() async {
        let (store, host) = makeMessageReadStore("m2-send") { call, _ in
            call.rpc == "send_message" ? MessageReadStubProtocol.Reply(body: #"{"status":"ok"}"#) : nil
        }
        #expect(store.startedAt == nil && !store.snapshot.isWorking, "픽스처가 비근무가 아니다")

        // 대조: 상대를 안 골랐으면 문이 아무것도 안 보낸다.
        store.messageDraft = "근무 밖에서도 가요?"
        MessageComposerView(store: store).send()
        #expect(MessageReadStubProtocol.count(host: host, rpc: "send_message") == 0)

        store.selectedMessagePeerID = m2rPeer
        #expect(store.canSendMessageNow, "비근무라고 [보내기]가 잠겼다")
        MessageComposerView(store: store).send()
        await messageReadWait { MessageReadStubProtocol.count(host: host, rpc: "send_message") >= 1 && !store.isSendingMessage }
        #expect(MessageReadStubProtocol.count(host: host, rpc: "send_message") == 1)
        let body = MessageReadStubProtocol.calls(host: host, rpc: "send_message").first?.json
        #expect(body?["p_to"] as? String == m2rPeer)
        #expect(store.messageNotice != WorkTimerStore.messageNotWorkingNotice, "비근무 안내가 떴다 — 선게이트가 남아 있다")
    }

    /// 콕찌르기 목록 → 말풍선 버튼 → 대화 화면이 근무와 무관하게 열린다(스토어 문 — 뷰는 이 문을 그대로 넘긴다:
    /// `onOpenMessages: { store.openMessagePanel(peer: $0) }` 는 V0238MenuTests 가 소스로 못 박는다).
    @Test(.gomokuDefaultsCleanup)
    func 비근무_사용자도_대화_화면에_들어간다() {
        let store = makeMessageReadStore("m2-open").store
        store.togglePokePanel()
        #expect(store.isPokePanelVisible)
        store.openMessagePanel(peer: m2rPeer)
        #expect(store.isMessagePanelVisible)
        #expect(store.selectedMessagePeerID == m2rPeer)
    }

    /// 뷰 쪽 짝 게이트: 목록 행의 말풍선 버튼과 [보내기]는 근무 조건을 보지 않는다(찌르기 버튼만 본다).
    @Test func 말풍선_버튼과_보내기_버튼에는_근무_조건이_없다() throws {
        let menu = try m2rSource("CheckMenuView.swift")
        let messageButton = try #require(m2rRegion(menu, from: "private var messageButton: some View {", to: "private var messageHelp: String {"))
        for gate in ["canPoke", "isWorking", "isMyselfWorking", "startedAt"] {
            #expect(!messageButton.contains(gate), "말풍선 버튼이 '\(gate)' 를 본다 — 비근무 사용자가 대화에 못 들어간다")
        }
        #expect(messageButton.contains("Button(action: onOpenMessages)"))

        let composer = try m2rSource("CheckMessageView.swift")
        let composerBody = try #require(m2rRegion(composer, from: "struct MessageComposerView: View {", to: "var sendHelp: String {"))
        for gate in ["isWorking", "startedAt", "isMyselfWorking"] {
            #expect(!composerBody.contains(gate), "작성기가 '\(gate)' 를 본다")
        }
        #expect(composerBody.contains(".disabled(!store.canSendMessageNow)"))
        #expect(composerBody.contains("CheckEditorSend.commitThenSend { store.sendDraftMessage() }"))
    }

    // MARK: 콕찌르기 안내줄

    /// 비근무 안내가 **찌르기 전용**임을 말하고(메시지는 된다), 한 줄에 들어간다.
    @Test func 비근무_안내줄은_찌르기만_막혔다고_말하고_한_줄에_들어간다() throws {
        let text = MessageAnytimeNotice.pokeOffWork
        #expect(text.contains("찌르기") && text.contains("메시지"))
        #expect(!text.hasPrefix("근무 중일 때만"), "메시지까지 막는 문장처럼 읽힌다")

        func height(_ string: String) throws -> Int {
            let view = Text(string)
                .font(.caption2)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: MessagePanelLayout.contentWidth, alignment: .leading)
                .background(Color.black)
            return try m2rBitmap(view).pixelsHigh
        }
        #expect(try height(text) == height("가"), "안내줄이 두 줄로 접힌다 — 비근무 사용자의 팝오버만 자란다")
        // 대조군: 정말 긴 문장이면 두 줄이 된다(높이 비교가 헛돌지 않는다).
        #expect(try height(text + " · " + text) > height("가"))

        let menu = try m2rSource("CheckMenuView.swift")
        #expect(menu.contains("return (MessageAnytimeNotice.pokeOffWork, false)"))
        #expect(!menu.contains("return (\"근무 중일 때만 콕 찌를 수 있어요\", false)"), "옛 안내줄이 남아 있다")
    }

    // MARK: 보관 안내

    /// 창 상단 보관 안내는 상수에서 파생된다 — 24시간이 자동으로 나온다(리터럴을 뷰에 적지 않았다).
    @Test func 보관_안내는_24시간을_말한다() throws {
        #expect(WorkTimerStore.messageHistoryHours == 24)
        #expect(WorkTimerStore.messageExpiryNotice == "24시간이 지난 메시지는 사라져요")
        let view = try m2rSource("CheckMessageView.swift")
        #expect(view.contains("Text(WorkTimerStore.messageExpiryNotice)"))
        #expect(!view.contains("12시간") && !view.contains("24시간"), "보관 시간을 뷰에 리터럴로 적었다")
    }
}
