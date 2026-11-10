import AppKit
import CheckRenderTestSupport
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// 2026-11-11 — **이전 대화 더 보기**(메시지 30일 보관 · `message_page`).
//
// 대표 결정(#d_IKem7qxZXc5b): "메시지 30일로 늘리기" — 앱에 '이전 대화 더 보기' 추가. 서버 최종 목록(서버 안정화 11-11 §1)의
// `message_page(p_peer, p_before_us, p_before_id, p_limit)` 모양으로 잰다 — 전선은 코어 `MessageHistoryPaging.swift` 한 곳이다.
//
// 이 파일이 재는 것:
//  ① 24시간 머리 · 안 읽음 점 · 읽음 경계(`mark_messages_read` p_through) · 모두 읽음이 **지난 쪽을 불러와도 그대로**다.
//  ② 요청 본문(네 키 · 명시적 null · µs 커서 정수 그대로) · 서비스 디코더로 읽기 · 확성기 줄 버림 · 사진 줄은 글로.
//  ③ 첫 누름은 커서 없이 · 머리와 겹친 쪽은 같은 누름 안에서 이어 묻기(상한) · 머리가 이기는 중복 제거.
//  ④ 쓸 수 있는가(404 → 숨김, 다음 패널 열기에서 다시 세움) · 서버 호출은 버튼에서만 · 입력칸 안내.
//  ⑤ 세대 · 순번 · 상대 가드(로그아웃 · 상대 바꾸기 · 닫기 중 도착한 응답은 버린다) · 선택을 쓰지 않는다.
//  ⑥ 머리 미끄러짐의 틈 메우기 · 다시 정렬하지 않는 잇기.
//  ⑦ 화면: 맨 위 줄은 스크롤 안의 첫 줄 · 붙인 뒤 제자리(호스팅 측정) · 스냅숏(FEATURE_SHOTS_DIR).
//
// 실행: 함수 이름 정규식으로 — `swift test --skip-build --filter 'checkTests\.이전대화_'` (파일 이름 필터는 자유 함수를 건너뛴다).
// 픽스처의 이름·본문은 전부 지어낸 것이다(공개 저장소).

private typealias Fx = MessageReadFixture
private typealias Reply = MessageReadStubProtocol.Reply

// MARK: - 픽스처

private enum MoPhoto: Sendable { case none, withCaption, only }

/// `message_page` 한 줄의 재료(Sendable — 스텁 처리기가 다른 스레드에서 JSON 을 만든다).
private struct MoRow: Sendable {
    let id: String
    var peer: String = Fx.peerA
    let isMine: Bool
    let us: Int64
    var body: String = "지난 이야기"
    var photo: MoPhoto = .none
    var megaphone = false
    var unread: Bool? = nil
    var readByPeer: Bool? = nil

    /// 서버 최종 목록 §1의 열네 칸 그대로(SQL 초안 `message_page` 의 returns table).
    var json: [String: Any] {
        let stored = photo == .only ? MessageNoticeText.photoFallbackBody : body
        let hasPhoto = photo != .none
        return [
            "id": id,
            "from_user": isMine ? Fx.me : peer,
            "to_user": isMine ? peer : Fx.me,
            "body": stored,
            "caption": photo == .only ? NSNull() : stored as Any,
            "photo_path": hasPhoto ? "\(isMine ? Fx.me : peer)/\(id).jpg" as Any : NSNull(),
            "photo_width": hasPhoto ? 1600 as Any : NSNull(),
            "photo_height": hasPhoto ? 1200 as Any : NSNull(),
            "is_megaphone": megaphone,
            "is_mine": isMine,
            "created_epoch_ms": us / 1_000,
            "created_epoch_us": us,
            "read_by_peer": isMine ? (readByPeer ?? false) as Any : NSNull(),
            "unread_for_me": isMine ? NSNull() : (unread ?? false) as Any
        ]
    }
}

private enum MoFx {
    static var nowEpoch: Int { Int(Fx.now.timeIntervalSince1970) }

    /// `secondsAgo` 초 전의 µs 시각. 끝자리 µs 까지 싣는다(초 단위로 접으면 잃는 값).
    static func micros(_ secondsAgo: Int, offset: Int64 = 123_457) -> Int64 {
        Int64(nowEpoch - secondsAgo) * 1_000_000 + offset
    }

    /// 24시간 머리(`message_history_with_reads`) 한 줄 — 초 단위 epoch.
    static func head(
        _ id: String, peer: String = Fx.peerA, isMine: Bool, secondsAgo: Int, body: String = "오늘 이야기",
        unread: Bool? = nil, readByPeer: Bool? = nil
    ) -> [String: Any] {
        Fx.readsRow(
            id: id, peer: peer, isMine: isMine, body: body, epoch: nowEpoch - secondsAgo,
            readByPeer: readByPeer, unread: unread, name: "민수"
        )
    }

    static func entry(_ id: String, _ body: String = "말", at date: Date, isMine: Bool = false) -> MessageHistoryEntry {
        MessageHistoryEntry(
            id: id, peerUserID: Fx.peerA, peerName: "민수", peerAvatarURL: nil, body: body,
            createdAt: date, isMine: isMine, readByPeer: isMine ? true : nil, isUnread: isMine ? nil : false
        )
    }
}

/// `message_page` 를 흉내 내는 서버 — SQL 초안의 where(µs 커서 · 같은 µs 는 id) · order(µs desc, id desc) · limit 그대로.
private struct MoPageServer: Sendable {
    let rows: [MoRow]
    var gate: MessageReadStubGate? = nil

    func reply(_ call: MessageReadStubProtocol.Call) -> Reply {
        let json = call.json
        let beforeUs = (json["p_before_us"] as? NSNumber)?.int64Value
        let beforeID = json["p_before_id"] as? String
        let limit = max(1, min(100, (json["p_limit"] as? NSNumber)?.intValue ?? 50))
        let ordered = rows.sorted { $0.us != $1.us ? $0.us > $1.us : $0.id > $1.id }
        let filtered = ordered.filter { row in
            guard let beforeUs else { return true }
            if row.us < beforeUs { return true }
            guard row.us == beforeUs, let beforeID else { return false }
            return row.id < beforeID
        }
        return Reply(body: Fx.json(filtered.prefix(limit).map(\.json)), gate: gate)
    }
}

/// [이전 대화 더 보기]가 낸 `message_page` 호출. 2026-11-11(사진 — `MessagePhotoTests`): 대화를 **열 때** 사진 칸을 배우는 조회
/// (`p_limit` = `MessagePhotoText.metaPageLimit`)도 같은 함수를 부른다 — 그 호출은 이 기능의 것이 아니라 뺀다(지난 쪽은 `olderPageLimit`).
@MainActor
private func moPage(_ host: String) -> [MessageReadStubProtocol.Call] {
    MessageReadStubProtocol.calls(host: host, rpc: "message_page").filter {
        ($0.json["p_limit"] as? NSNumber)?.intValue != MessagePhotoText.metaPageLimit
    }
}

/// 대화가 열린 상태(패널 · 상대). 팝오버 표시는 읽음 시험만 따로 켠다.
@MainActor
private func moOpen(_ store: WorkTimerStore, peer: String = Fx.peerA, menu: Bool = false) {
    store.isMenuPresented = menu
    store.isMessagePanelVisible = true
    store.selectedMessagePeerID = peer
}

/// 두 자리 번호(사전 순 = 숫자 순).
private func moID(_ prefix: String, _ index: Int) -> String {
    prefix + String(format: "%03d", index)
}

// MARK: - ② 요청 본문 · 커서

@MainActor
@Test(.gomokuDefaultsCleanup)
func 이전대화_요청은_네_키를_null까지_싣고_다음_커서는_가장_오래된_쪽_줄의_µs와_id다() async throws {
    // 머리: 다른 사람(b0) 한 줄 + peerA 두 줄. 서버: peerA 두 줄 + 옛 줄 60 개(꽉 찬 쪽 하나 + 남는 쪽 하나).
    let older = (0..<60).map { MoRow(id: moID("o", $0), isMine: $0 % 3 == 0, us: MoFx.micros(200_000 - $0 * 60)) }
    let server = MoPageServer(rows: [
        MoRow(id: "a1", isMine: false, us: MoFx.micros(3_600)),
        MoRow(id: "a2", isMine: true, us: MoFx.micros(60))
    ] + older)
    let (store, host) = makeMessageReadStore("older-cursor") { call, _ in
        switch call.rpc {
        case "message_history_with_reads":
            return Fx.historyReply([
                MoFx.head("b0", peer: Fx.peerB, isMine: false, secondsAgo: 80_000),
                MoFx.head("a1", isMine: false, secondsAgo: 3_600),
                MoFx.head("a2", isMine: true, secondsAgo: 60)
            ])
        case "message_page": return server.reply(call)
        default: return nil
        }
    }
    moOpen(store)
    await store.performLoadMessageHistory()
    #expect(store.messageHistory.map(\.id) == ["b0", "a1", "a2"])

    // 첫 누름: 커서 없이(머리 줄은 µs 가 없다) — 네 키가 **다** 실리고 커서 둘은 명시적 null 이다.
    await store.performLoadOlderMessages()
    let first = try #require(moPage(host).first)
    #expect(Set(first.json.keys) == ["p_peer", "p_before_us", "p_before_id", "p_limit"], "본문 키 집합: \(first.body)")
    #expect(first.body.contains("\"p_before_us\":null") && first.body.contains("\"p_before_id\":null"),
            "커서가 없을 때 키를 빼면 PostgREST 가 함수를 못 고른다: \(first.body)")
    #expect(first.json["p_peer"] as? String == Fx.peerA)
    #expect((first.json["p_limit"] as? NSNumber)?.intValue == MessageNoticeText.olderPageLimit)
    #expect(first.method == "POST")
    #expect(moPage(host).count == 1, "옛 줄이 붙었는데 같은 누름에서 또 물었다")
    // 첫 쪽: a2 · a1(머리에 있어 버림) + o059 … o012(48 줄). 커서는 서버가 준 가장 오래된 줄(o012)의 µs · id.
    #expect(store.messageOlderPages[Fx.peerA]?.map(\.id) == (12..<60).map { moID("o", $0) })
    let cursor = try #require(store.messageOlderCursors[Fx.peerA])
    #expect(cursor == MessagePageCursor(epochMicros: MoFx.micros(200_000 - 12 * 60), id: "o012"))
    #expect(store.messageOlderRowState == .button)

    // 둘째 누름: 그 커서가 **정수 그대로** 실린다(µs 끝자리까지 — 실수를 지나면 잃는다).
    await store.performLoadOlderMessages()
    let second = try #require(moPage(host).last)
    #expect(moPage(host).count == 2)
    #expect(Set(second.json.keys) == ["p_peer", "p_before_us", "p_before_id", "p_limit"])
    #expect(second.body.contains("\"p_before_us\":\(cursor.epochMicros)"), "커서 µs 가 정수 그대로가 아니다: \(second.body)")
    #expect(second.json["p_before_id"] as? String == "o012")
    #expect(store.messageOlderPages[Fx.peerA]?.map(\.id) == (0..<60).map { moID("o", $0) })
    // 상한보다 적게 왔다 = 끝. 다시 눌러도 안 묻는다.
    #expect(store.messageOlderRowState == .end)
    store.loadOlderMessages()
    await store.performLoadOlderMessages()
    #expect(moPage(host).count == 2)
    // 지난 쪽 + 머리(peerA 만) — 다른 사람(b0)은 없다.
    #expect(store.selectedConversationMessages.map(\.id) == (0..<60).map { moID("o", $0) } + ["a1", "a2"])
}

// MARK: - ② 응답 디코드 (서비스 디코더 그대로)

@Test
func 이전대화_응답은_서비스_디코더로_읽고_확성기는_버리고_사진_줄은_글로_그린다() async throws {
    // 진짜 서비스(액터) · 진짜 디코더 · 진짜 요청 경로 — 응답은 호스트별 스텁이 준다.
    let host = "msg-older-decode-\(UUID().uuidString.prefix(8))".lowercased()
    let huge: Int64 = 9_007_199_254_740_993
    MessageReadStubProtocol.register(host: host) { call, _ in
        call.rpc == "message_page" ? Reply(body: Fx.json([MoRow(id: "edge", isMine: false, us: huge).json])) : nil
    }
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!,
        anonKey: "anon-test-key",
        session: MessageReadStubProtocol.session()
    )
    let rows: [Any] = [
        MoRow(id: "n3", isMine: true, us: MoFx.micros(100_000), body: "사진 설명", photo: .withCaption, readByPeer: false).json,
        MoRow(id: "n2", isMine: false, us: MoFx.micros(110_000), photo: .only, unread: true).json,
        "깨진 원소",
        // 다른 대화의 줄(서버가 실수로 섞었다) — 버린다.
        MoRow(id: "x1", peer: Fx.peerB, isMine: false, us: MoFx.micros(115_000)).json,
        // 보이는 글자 없음 — 버린다.
        MoRow(id: "x2", isMine: false, us: MoFx.micros(118_000), body: "   ").json,
        MoRow(id: "n1", isMine: false, us: MoFx.micros(120_000), body: "첫째", unread: true).json,
        // 확성기 줄(가장 오래됐다) — 버리지만 **커서는 된다**(확성기만 담긴 쪽에서 멈추지 않게).
        MoRow(id: "mega", isMine: false, us: MoFx.micros(150_000), body: "공지", megaphone: true).json
    ]
    let data = Data(Fx.json(rows).utf8)
    let page = try await service.messagePage(from: data, peer: Fx.peerA, me: Fx.me, limit: 50, peerName: "민수")
    #expect(page.entries.map(\.id) == ["n1", "n2", "n3"], "오래된 것 → 최신이 아니거나 버릴 줄이 남았다")
    #expect(!page.entries.contains { $0.id == "mega" }, "확성기 줄을 메시지함에 들였다")
    #expect(page.entries.first { $0.id == "n2" }?.body == MessageNoticeText.photoFallbackBody, "사진만 보낸 줄의 글이 '📷 사진'이 아니다")
    #expect(page.entries.first { $0.id == "n3" }?.body == "사진 설명", "사진과 같이 보낸 글(caption)을 안 그렸다")
    // 받은 쪽 안 읽음 칸은 **싣지 않는다** — 24시간 너머의 받은 말이 점을 켜면 요약이 그 말을 안 세서 영영 안 꺼진다.
    #expect(page.entries.allSatisfy { $0.isUnread == nil }, "지난 쪽 줄이 안 읽음 칸을 들고 왔다")
    #expect(page.entries.first { $0.id == "n3" }?.readByPeer == false, "내 말의 안 읽음 1 을 잃었다")
    #expect(page.entries.first { $0.id == "n1" }?.readByPeer == nil)
    #expect(page.entries.map(\.isMine) == [false, false, true])
    #expect(page.entries.allSatisfy { $0.peerUserID == Fx.peerA && $0.peerName == "민수" })
    // 화면 시각은 밀리초 칸(created_epoch_ms)에서 온다.
    let n1 = try #require(page.entries.first { $0.id == "n1" })
    #expect(abs(n1.createdAt.timeIntervalSince1970 - Double(MoFx.micros(120_000) / 1_000) / 1_000) < 0.000_5)
    #expect(page.rowCount == 7, "버린 줄 · 깨진 원소도 쪽 끝 판정의 줄 수에 든다")
    #expect(page.oldestCursor == MessagePageCursor(epochMicros: MoFx.micros(150_000), id: "mega"))
    #expect(!page.hasMore, "50건 요청에 7줄이 왔는데 더 있다고 읽었다")
    #expect(try await service.messagePage(from: data, peer: Fx.peerA, me: Fx.me, limit: 7).hasMore, "꽉 찬 쪽을 끝으로 읽었다")

    // 배열이 아닌 답은 던진다(스토어가 실패로 그린다).
    await #expect(throws: (any Error).self) {
        try await service.messagePage(from: Data(#"{"status":"ok"}"#.utf8), peer: Fx.peerA, me: Fx.me, limit: 50)
    }

    // µs 는 Int64 그대로다 — 2^53 을 넘는 값도 끝자리까지(실수 갈래가 있으면 …992 나 …994 가 된다). 요청 경로 왕복으로 잰다:
    // 커서 없는 첫 요청은 두 커서 키가 null, 그 응답의 커서를 실은 둘째 요청은 같은 정수가 그대로 나간다(서비스 인코더).
    let first = try await service.fetchMessagePage(accessToken: "access-token", peer: Fx.peerA, me: Fx.me, before: nil)
    #expect(first.oldestCursor?.epochMicros == huge, "응답 µs 를 정수 그대로 못 읽었다: \(String(describing: first.oldestCursor))")
    _ = try await service.fetchMessagePage(accessToken: "access-token", peer: Fx.peerA, me: Fx.me, before: first.oldestCursor)
    let sent = MessageReadStubProtocol.calls(host: host, rpc: "message_page")
    #expect(sent.count == 2)
    #expect(sent.first?.body.contains("\"p_before_us\":null") == true && sent.first?.body.contains("\"p_before_id\":null") == true)
    #expect(sent.last?.body.contains("\"p_before_us\":9007199254740993") == true, "요청 커서가 정수 그대로가 아니다: \(sent.last?.body ?? "")")
    #expect(sent.last?.json["p_before_id"] as? String == "edge")
    #expect(sent.allSatisfy { Set($0.json.keys) == ["p_peer", "p_before_us", "p_before_id", "p_limit"] })

    // 커서 순서: µs 가 먼저, 같은 µs 는 id(서버 `m.id < p_before_id`).
    let a = MessagePageCursor(epochMicros: 10, id: "b")
    #expect(MessagePageCursor(epochMicros: 9, id: "z").isOlder(than: a))
    #expect(MessagePageCursor(epochMicros: 10, id: "a").isOlder(than: a))
    #expect(!MessagePageCursor(epochMicros: 10, id: "c").isOlder(than: a))
}

// MARK: - ③ 첫 누름 · 이어 묻기 · 중복

@MainActor
@Test(.gomokuDefaultsCleanup)
func 이전대화_첫_쪽이_머리와_겹치면_같은_누름_안에서_이어_묻고_머리가_이긴다() async throws {
    // 머리 60 줄(peerA) — 첫 쪽(50)은 전부 머리와 겹친다. 서버는 그 60 줄 + 옛 줄 30 개.
    let headIDs = (0..<60).map { moID("h", $0) }
    let headRows = (0..<60).map { MoRow(id: moID("h", $0), isMine: $0 % 2 == 0, us: MoFx.micros(3_600 - $0 * 50), body: "서버가 다시 준 줄") }
    let older = (0..<30).map { MoRow(id: moID("o", $0), isMine: false, us: MoFx.micros(200_000 - $0 * 60), unread: true) }
    let server = MoPageServer(rows: headRows + older)
    let (store, host) = makeMessageReadStore("older-catchup") { call, _ in
        switch call.rpc {
        case "message_history_with_reads":
            return Fx.historyReply((0..<60).map {
                MoFx.head(moID("h", $0), isMine: $0 % 2 == 0, secondsAgo: 3_600 - $0 * 50, body: "머리 \($0)")
            })
        case "message_page": return server.reply(call)
        default: return nil
        }
    }
    moOpen(store)
    await store.performLoadMessageHistory()
    #expect(store.messageHistory.map(\.id) == headIDs)

    store.loadOlderMessages()
    await messageReadWait { moPage(host).count >= 2 && !store.messageOlderLoading }
    let calls = moPage(host)
    #expect(calls.count == 2, "겹친 쪽 하나 뒤에 이어 묻지 않았거나 더 물었다: \(calls.count)")
    #expect(calls.first?.body.contains("\"p_before_id\":null") == true)
    #expect(calls.last?.json["p_before_id"] as? String == "h010", "이어 묻기 커서가 첫 쪽의 가장 오래된 줄이 아니다")
    #expect(calls.last?.body.contains("\"p_before_us\":\(MoFx.micros(3_600 - 10 * 50))") == true)
    #expect(store.messageOlderPages[Fx.peerA]?.map(\.id) == (0..<30).map { moID("o", $0) })
    let merged = store.selectedConversationMessages
    #expect(merged.map(\.id) == (0..<30).map { moID("o", $0) } + headIDs, "지난 쪽이 머리 앞에 안 이어졌다")
    #expect(merged.first { $0.id == "h000" }?.body == "머리 0", "중복 id 에서 지난 쪽이 이겼다(머리가 이겨야 한다)")
    #expect(store.messageOlderRowState == .end)
    #expect(store.messageHistory.map(\.id) == headIDs, "지난 쪽이 24시간 머리에 섞였다")
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 이전대화_이어_묻기는_한_누름에_상한까지만이고_다음_누름이_그_커서에서_잇는다() async throws {
    // 머리 300 줄 — 첫 누름의 이어 묻기가 상한(olderCatchUpRequests)에 닿아도 옛 줄에 못 간다.
    let limit = MessageNoticeText.olderCatchUpRequests
    #expect(limit == MessageNoticeText.historyLimit / MessageNoticeText.olderPageLimit + 1)
    let headRows = (0..<300).map { MoRow(id: moID("h", $0), isMine: false, us: MoFx.micros(30_000 - $0 * 60)) }
    let older = (0..<20).map { MoRow(id: moID("o", $0), isMine: false, us: MoFx.micros(200_000 - $0 * 60)) }
    let server = MoPageServer(rows: headRows + older)
    let (store, host) = makeMessageReadStore("older-bound") { call, _ in
        switch call.rpc {
        case "message_history_with_reads":
            return Fx.historyReply((0..<300).map { MoFx.head(moID("h", $0), isMine: false, secondsAgo: 30_000 - $0 * 60) })
        case "message_page": return server.reply(call)
        default: return nil
        }
    }
    moOpen(store)
    await store.performLoadMessageHistory()
    await store.performLoadOlderMessages()
    #expect(moPage(host).count == limit, "한 누름의 이어 묻기가 상한을 지키지 않았다: \(moPage(host).count)")
    #expect(store.messageOlderPages[Fx.peerA] == nil, "머리와 겹친 줄을 지난 쪽에 들였다")
    #expect(store.messageOlderRowState == .button, "옛 줄을 아직 못 찾았는데 버튼이 내려갔다")
    #expect(store.messageOlderCursors[Fx.peerA]?.id == moID("h", 300 - limit * 50))

    // 다음 누름: 그 커서에서 잇는다(처음부터 다시 묻지 않는다).
    await store.performLoadOlderMessages()
    let resumed = moPage(host)[limit]
    #expect(resumed.json["p_before_id"] as? String == moID("h", 300 - limit * 50), "다음 누름이 커서를 잃었다")
    #expect(store.messageOlderPages[Fx.peerA]?.map(\.id) == (0..<20).map { moID("o", $0) })
    #expect(store.messageOlderRowState == .end)
    #expect(moPage(host).count == limit + 2)
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 이전대화_확성기만_담긴_꽉_찬_쪽도_커서를_넘겨_옛_말에_닿는다() async {
    let megaphones = (0..<60).map {
        MoRow(id: moID("m", $0), isMine: false, us: MoFx.micros(150_000 - $0 * 60), body: "공지 \($0)", megaphone: true)
    }
    let older = (0..<3).map { MoRow(id: moID("o", $0), isMine: false, us: MoFx.micros(300_000 - $0 * 60)) }
    let server = MoPageServer(rows: [MoRow(id: "a1", isMine: false, us: MoFx.micros(600))] + megaphones + older)
    let (store, host) = makeMessageReadStore("older-megaphone") { call, _ in
        switch call.rpc {
        case "message_history_with_reads": return Fx.historyReply([MoFx.head("a1", isMine: false, secondsAgo: 600)])
        case "message_page": return server.reply(call)
        default: return nil
        }
    }
    moOpen(store)
    await store.performLoadMessageHistory()
    await store.performLoadOlderMessages()
    #expect(moPage(host).count == 2, "확성기만 담긴 꽉 찬 쪽에서 멈췄거나 더 물었다")
    #expect(store.messageOlderPages[Fx.peerA]?.map(\.id) == ["o000", "o001", "o002"], "확성기 줄이 지난 쪽에 들었다")
    #expect(!store.selectedConversationMessages.contains { $0.id.hasPrefix("m") })
    #expect(store.messageOlderRowState == .end)
}

// MARK: - ① 안 읽음 · 읽음 경계 · 모두 읽음은 그대로다

@MainActor
@Test(.gomokuDefaultsCleanup)
func 이전대화_지난_쪽의_안_읽은_말은_점을_켜지_않는다() async {
    // 24시간 너머의 받은 말 — 서버는 그 말에 unread_for_me=true 를 싣는다(아무도 안 읽었다).
    let server = MoPageServer(rows: [
        MoRow(id: "a1", isMine: false, us: MoFx.micros(3_600)),
        MoRow(id: "a2", isMine: true, us: MoFx.micros(60)),
        MoRow(id: "o2", isMine: false, us: MoFx.micros(100_000), unread: true),
        MoRow(id: "o1", isMine: false, us: MoFx.micros(200_000), unread: true)
    ])
    let (store, host) = makeMessageReadStore("older-dots") { call, _ in
        switch call.rpc {
        case "message_history_with_reads":
            return Fx.historyReply([
                MoFx.head("a1", isMine: false, secondsAgo: 3_600, unread: false),
                MoFx.head("a2", isMine: true, secondsAgo: 60, readByPeer: true)
            ])
        case "message_unread_summary": return Fx.summaryReply([])
        case "message_page": return server.reply(call)
        default: return nil
        }
    }
    moOpen(store)
    await store.performLoadMessageHistory()
    await store.performLoadMessageUnreadSummary()
    let headBefore = store.messageHistory
    let threadBefore = store.selectedMessageThread?.messages.map(\.id)
    #expect(store.unreadMessagePeerIDs.isEmpty && store.unreadConversationPeerIDs.isEmpty && !store.hasUnreadMessages)

    await store.performLoadOlderMessages()
    #expect(store.selectedConversationMessages.map(\.id) == ["o1", "o2", "a1", "a2"], "지난 쪽이 머리 앞에 안 이어졌다")
    #expect(store.messageHistory == headBefore, "지난 쪽이 24시간 머리(messageHistory)에 섞였다")
    #expect(store.selectedMessageThread?.messages.map(\.id) == threadBefore, "selectedMessageThread 가 머리만이 아니다")
    #expect(store.messageOlderPages[Fx.peerA]?.allSatisfy { $0.isUnread == nil } == true, "지난 쪽 줄에 isUnread 가 실렸다")
    #expect(store.unreadMessagePeerIDs.isEmpty, "24시간 너머의 받은 말이 목록·레일 점을 켰다")
    #expect(store.unreadConversationPeerIDs.isEmpty)
    #expect(!store.hasUnreadMessages, "24시간 너머의 받은 말이 메뉴바 점을 켰다")
    // 모두 읽음도 지난 쪽을 안 본다.
    #expect(store.markAllConversationsReadFromLoaded() == 0, "모두 읽음이 지난 쪽 줄을 읽음으로 올리려 한다")
    await messageReadWait { messageReadIdle(store) }
    #expect(MessageReadStubProtocol.count(host: host, rpc: "mark_messages_read") == 0)
}

/// 서버 쪽 상태(읽음 처리 횟수 · 새 말 도착)를 시험이 정하는 상자. 스텁 처리기는 다른 스레드에서 부른다.
private final class MoServerState: @unchecked Sendable {
    private let lock = NSLock()
    private var marks = 0
    private var newMessage = false

    func noteMark() { lock.lock(); marks += 1; lock.unlock() }
    var markCount: Int { lock.lock(); defer { lock.unlock() }; return marks }
    func deliverNewMessage() { lock.lock(); newMessage = true; lock.unlock() }
    var hasNewMessage: Bool { lock.lock(); defer { lock.unlock() }; return newMessage }
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 이전대화_지난_쪽을_불러와도_읽음_경계는_머리의_마지막_받은_말이다() async {
    let state = MoServerState()
    // 24시간 너머의 받은 말 둘 — 아무도 안 읽어 unread_for_me=true 로 온다. 꽉 찬 쪽이 아니라 끝까지 받는다.
    let server = MoPageServer(rows: [
        MoRow(id: "a1", isMine: false, us: MoFx.micros(600)),
        MoRow(id: "o2", isMine: false, us: MoFx.micros(100_000), unread: true),
        MoRow(id: "o1", isMine: false, us: MoFx.micros(200_000), unread: true)
    ])
    let (store, host) = makeMessageReadStore("older-mark") { call, _ in
        switch call.rpc {
        case "message_history_with_reads":
            // 서버가 읽음을 기억한다: 첫 읽음 처리 뒤 a1 은 읽음, 새 말 a2 는 두 번째 읽음 처리 전까지 안 읽음.
            var rows = [MoFx.head("a1", isMine: false, secondsAgo: 600, unread: state.markCount < 1)]
            if state.hasNewMessage {
                rows.append(MoFx.head("a2", isMine: false, secondsAgo: 30, unread: state.markCount < 2))
            }
            return Fx.historyReply(rows)
        case "mark_messages_read":
            state.noteMark()
            return Fx.markReply()
        case "message_unread_summary": return Fx.summaryReply([])
        case "message_page": return server.reply(call)
        default: return nil
        }
    }
    moOpen(store, menu: true)
    await store.performLoadMessageHistory()
    await messageReadWait { MessageReadStubProtocol.count(host: host, rpc: "mark_messages_read") >= 1 && messageReadIdle(store) }
    // 읽음 처리 성공 뒤의 합치기 새로고침까지 가라앉힌다.
    try? await Task.sleep(for: .milliseconds(80))
    await messageReadWait { messageReadIdle(store) }
    #expect(MessageReadStubProtocol.count(host: host, rpc: "mark_messages_read") == 1)
    #expect(store.unreadMessagePeerIDs.isEmpty)

    // 지난 쪽(안 읽음 표시가 붙은 옛 말 둘)을 붙이고 판정을 다시 돌려도 새 읽음 호출은 없다 — 지난 쪽은 판정 재료가 아니다.
    await store.performLoadOlderMessages()
    #expect(store.messageOlderPages[Fx.peerA]?.map(\.id) == ["o1", "o2"])
    store.evaluateMessageReadMarking()
    #expect(store.markAllConversationsReadFromLoaded() == 0, "모두 읽음이 지난 쪽 줄을 올리려 한다")
    try? await Task.sleep(for: .milliseconds(80))
    await messageReadWait { messageReadIdle(store) }
    #expect(MessageReadStubProtocol.count(host: host, rpc: "mark_messages_read") == 1, "지난 쪽 때문에 읽음 처리가 다시 나갔다")
    #expect(store.unreadMessagePeerIDs.isEmpty, "지난 쪽의 안 읽은 옛 말이 점을 켰다")

    // 새 말이 오면 경계는 머리의 새 마지막 받은 말이다 — 지난 쪽 id 가 경계가 되는 일은 없다(p_through 는 지난 쪽이 없을 때와 같다).
    state.deliverNewMessage()
    await store.performLoadMessageHistory()
    await messageReadWait { MessageReadStubProtocol.count(host: host, rpc: "mark_messages_read") >= 2 && messageReadIdle(store) }
    try? await Task.sleep(for: .milliseconds(80))
    await messageReadWait { messageReadIdle(store) }
    let throughs = MessageReadStubProtocol.calls(host: host, rpc: "mark_messages_read").compactMap { $0.json["p_through"] as? String }
    #expect(throughs == ["a1", "a2"], "읽음 경계: \(throughs)")
    #expect(store.messageOlderPages[Fx.peerA]?.map(\.id) == ["o1", "o2"])
    #expect(store.selectedConversationMessages.map(\.id) == ["o1", "o2", "a1", "a2"])
    #expect(store.unreadMessagePeerIDs.isEmpty)
    #expect(!store.hasUnreadMessages)
}

// MARK: - ④ 버튼에서만 · 쓸 수 있는가 · 입력칸 안내

@MainActor
@Test(.gomokuDefaultsCleanup)
func 이전대화_서버를_부르는_자리는_버튼_하나다() async {
    let (store, host) = makeMessageReadStore("older-tap-only") { call, _ in
        switch call.rpc {
        case "message_history_with_reads": return Fx.historyReply([MoFx.head("a1", isMine: false, secondsAgo: 600, unread: false)])
        case "message_unread_summary": return Fx.summaryReply([])
        case "message_page": return Reply(body: "[]")
        default: return nil
        }
    }
    store.isMenuPresented = true
    store.openMessagePanel(peer: Fx.peerA)
    await messageReadWait { store.messageHistoryLoaded && messageReadIdle(store) }
    store.requestMessageActivityRefresh(includeHistory: true)
    await messageReadWait { messageReadIdle(store) }
    store.refreshMessageActivityOnMenuOpen()
    await messageReadWait { messageReadIdle(store) }
    store.closeMessagePanel()
    store.openMessagePanel(peer: Fx.peerA)
    await messageReadWait { messageReadIdle(store) }
    #expect(moPage(host).isEmpty, "패널 열기 · 새로고침이 이전 대화를 물었다(기존 요청 수가 바뀐다)")
    #expect(store.messageOlderRowState == .button, "모르는 서버인데 버튼이 안 섰다")
    #expect(store.messageExpiryNoticeNow == WorkTimerStore.messageExpiryNotice, "성공 전인데 30일이라고 말한다")

    store.loadOlderMessages()
    await messageReadWait { moPage(host).count == 1 && !store.messageOlderLoading }
    #expect(moPage(host).count == 1)
    // 빈 쪽 = 더 없다 → 끝 줄. 다시 눌러도 안 묻는다. 성공했으니 입력칸 안내는 30일 문장이다.
    #expect(store.messageOlderRowState == .end)
    #expect(store.messageOlderAvailable == true)
    #expect(store.messageExpiryNoticeNow == MessageNoticeText.storeExpiry)
    #expect(store.messageExpiryNoticeNow == "\(MessageNoticeText.storeDays)일이 지난 메시지는 사라져요")
    store.loadOlderMessages()
    try? await Task.sleep(for: .milliseconds(50))
    #expect(moPage(host).count == 1)
    await messageReadWait { messageReadIdle(store) }
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 이전대화_함수가_없는_서버면_버튼을_내리고_다음_패널_열기에서_다시_세운다() async {
    // 스텁 기본값이 404 PGRST202 다(V0330MessageReadStub — 이번에 이름을 더했다).
    let (store, host) = makeMessageReadStore("older-missing-404")
    store.openMessagePanel(peer: Fx.peerA)
    await messageReadWait { store.messageHistoryLoaded && messageReadIdle(store) }
    #expect(store.messageOlderRowState == .button)

    store.loadOlderMessages()
    await messageReadWait { store.messageOlderAvailable == false }
    #expect(store.messageOlderAvailable == false)
    #expect(store.messageOlderRowState == nil, "함수가 없는 서버에 버튼이 남았다")
    #expect(store.messageExpiryNoticeNow == WorkTimerStore.messageExpiryNotice)
    #expect(!store.messageOlderFailed, "함수 없음을 실패([다시 시도])로 그렸다")
    store.loadOlderMessages()
    try? await Task.sleep(for: .milliseconds(50))
    #expect(moPage(host).count == 1, "숨긴 버튼 뒤로 다시 물었다")

    // 숨김은 영구히 들지 않는다 — 다음 패널 열기에서 모름으로 되돌린다(서버 호출은 없다).
    store.closeMessagePanel()
    store.openMessagePanel(peer: Fx.peerA)
    #expect(store.messageOlderAvailable == nil)
    #expect(store.messageOlderRowState == .button)
    #expect(moPage(host).count == 1)
    store.loadOlderMessages()
    await messageReadWait { moPage(host).count == 2 && !store.messageOlderLoading }
    #expect(moPage(host).count == 2)
    await messageReadWait { messageReadIdle(store) }
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 이전대화_일시_장애는_다시_시도로_그리고_숨기지_않는다() async {
    let server = MoPageServer(rows: [MoRow(id: "o1", isMine: false, us: MoFx.micros(200_000))])
    let (store, host) = makeMessageReadStore("older-failures") { call, index in
        guard call.rpc == "message_page" else { return nil }
        switch index {
        case 0: return Reply(status: 500, body: #"{"message":"boom"}"#)
        case 1: return Reply(body: #"{"status":"ok"}"#)
        default: return server.reply(call)
        }
    }
    moOpen(store)
    store.messageHistoryLoaded = true
    await store.performLoadOlderMessages()
    #expect(store.messageOlderRowState == .failed, "5xx 를 실패로 안 그렸다")
    #expect(store.messageOlderAvailable == nil, "일시 장애 한 번에 버튼을 숨겼다")

    await store.performLoadOlderMessages()
    #expect(store.messageOlderRowState == .failed, "배열이 아닌 답을 실패로 안 그렸다")
    #expect(store.messageOlderAvailable == nil)

    await store.performLoadOlderMessages()
    #expect(store.messageOlderAvailable == true)
    #expect(store.messageOlderRowState == .end)
    #expect(store.messageExpiryNoticeNow == MessageNoticeText.storeExpiry)
    #expect(store.selectedConversationMessages.map(\.id) == ["o1"])
    #expect(moPage(host).count == 3)
}

// MARK: - ⑤ 가드 · 비우기

@MainActor
@Test(.gomokuDefaultsCleanup)
func 이전대화_로그아웃_뒤에_도착한_응답은_다음_계정에_안_붙는다() async {
    let gate = MessageReadStubGate()
    let server = MoPageServer(rows: [MoRow(id: "o1", isMine: false, us: MoFx.micros(200_000), body: "앞 계정의 옛 대화")], gate: gate)
    let (store, host) = makeMessageReadStore("older-signout") { call, _ in
        call.rpc == "message_page" ? server.reply(call) : nil
    }
    moOpen(store)
    let flight = Task { await store.performLoadOlderMessages() }
    await messageReadWait { moPage(host).count == 1 }
    #expect(store.messageOlderLoading)

    store.clearPersistedSession()
    #expect(!store.messageOlderLoading)
    // 다른 계정이 같은 상대와의 대화를 연다.
    store.session = SupabaseSession(accessToken: "access-token-2", refreshToken: nil, userID: Fx.peerB)
    moOpen(store)
    gate.open()
    await flight.value
    #expect(store.messageOlderPages.isEmpty, "앞 계정의 30일 대화가 다음 계정 화면에 붙었다")
    #expect(store.messageOlderCursors.isEmpty, "앞 계정의 커서가 남았다")
    #expect(store.selectedConversationMessages.isEmpty)
    #expect(store.messageOlderAvailable == nil, "앞 계정의 응답이 다음 계정의 상태를 정했다")
    #expect(!store.messageOlderLoading)
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 이전대화_상대를_바꾸는_중에_온_응답은_버리고_상대를_안_바꾼다() async {
    let gate = MessageReadStubGate()
    let server = MoPageServer(rows: [MoRow(id: "o1", isMine: false, us: MoFx.micros(200_000))], gate: gate)
    let (store, host) = makeMessageReadStore("older-peer-switch") { call, _ in
        call.rpc == "message_page" ? server.reply(call) : nil
    }
    store.openMessagePanel(peer: Fx.peerA)
    await messageReadWait { messageReadIdle(store) }
    let flight = Task { await store.performLoadOlderMessages() }
    await messageReadWait { moPage(host).count == 1 }

    store.openMessagePanel(peer: Fx.peerB)
    gate.open()
    await flight.value
    #expect(store.selectedMessagePeerID == Fx.peerB, "응답이 상대를 바꿨다")
    #expect(store.messageOlderPages.isEmpty, "앞 상대의 옛 대화가 남았거나 뒤 상대에 붙었다")
    #expect(store.messageOlderCursors.isEmpty)
    #expect(!store.messageOlderLoading)
    await messageReadWait { messageReadIdle(store) }
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 이전대화_닫기_상대_바꾸기_로그아웃이_지난_쪽과_커서를_비운다() async {
    let (store, _) = makeMessageReadStore("older-clears")
    let page = [MoFx.entry("o1", at: Fx.now.addingTimeInterval(-200_000))]
    func seed() {
        store.messageOlderPages[Fx.peerA] = page
        store.messageOlderCursors[Fx.peerA] = MessagePageCursor(epochMicros: MoFx.micros(200_000), id: "o1")
        store.messageOlderHasMore[Fx.peerA] = true
        store.messageOlderFailed = true
        store.messageOlderScrollAnchor = MessageOlderScrollAnchor(serial: 3, messageID: "a1")
    }
    func cleared() -> Bool {
        store.messageOlderPages.isEmpty && store.messageOlderCursors.isEmpty && store.messageOlderHasMore.isEmpty
            && !store.messageOlderFailed && store.messageOlderScrollAnchor == nil
    }

    store.openMessagePanel(peer: Fx.peerA)
    seed()
    store.closeMessagePanel()
    #expect(cleared(), "패널을 닫았는데 옛 대화가 남았다")

    store.openMessagePanel(peer: Fx.peerA)
    seed()
    store.openMessagePanel(peer: Fx.peerB)
    #expect(cleared(), "상대를 바꿨는데 앞 상대의 옛 대화가 남았다")

    seed()
    store.messageOlderAvailable = true
    store.clearPersistedSession()
    #expect(cleared(), "로그아웃이 옛 대화를 안 비웠다")
    #expect(store.messageOlderAvailable == nil, "로그아웃이 쓸 수 있는가를 안 되돌렸다")
    await messageReadWait { messageReadIdle(store) }
}

@Test
func 이전대화_차단과_응답_경로는_선택을_안_쓴다_소스계약() throws {
    let older = moSource("WorkTimerStoreMessageOlder.swift")
    #expect(!older.contains("selectedMessagePeerID = "), "이전 대화 파일이 선택에 대입한다")
    #expect(!older.contains("selectMessagePeer("), "이전 대화 파일이 상대를 고른다")
    #expect(older.contains("selectedMessagePeerID == peer"), "응답 경로에 상대 가드가 없다")
    #expect(older.contains("token == messageOlderRequestToken"), "응답 경로에 순번 가드가 없다")
    #expect(older.contains("generation == sessionGeneration"), "응답 경로에 세대 가드가 없다")
    // 지난 쪽은 머리(messageHistory)에 대입하지 않는다.
    #expect(!older.contains("messageHistory = "), "지난 쪽 파일이 24시간 머리를 바꾼다")
    // 차단(hideBlockedPeer)은 닫기 문을 지나고, 닫기 문이 지난 쪽을 비운다.
    let blocks = moSource("WorkTimerStoreBlocks.swift")
    let hide = try #require(moRegion(blocks, from: "private func hideBlockedPeer(", to: "\n    }\n"))
    #expect(hide.contains("closeMessagePanel()"))
    let messages = v0331StripComments(try CheckCoreSourceLayout.joinedSplitSource("WorkTimerStoreMessages.swift"))
    let close = try #require(moRegion(messages, from: "func closeMessagePanel() {", to: "\n    }\n"))
    #expect(close.contains("clearOlderMessages()"), "닫기 문이 옛 대화를 안 비운다")
    let select = try #require(moRegion(messages, from: "func selectMessagePeer(", to: "\n    }\n\n"))
    #expect(select.contains("clearOlderMessages()"), "상대 바꾸기가 옛 대화를 안 비운다")
    let open = try #require(moRegion(messages, from: "func openMessagePanel(peer:", to: "\n    }\n"))
    #expect(open.contains("rearmOlderMessagesAvailability()"), "패널 열기가 숨긴 버튼을 다시 세우지 않는다")
    #expect(!open.contains("loadOlderMessages"), "패널 열기가 이전 대화를 묻는다")
    let headLoad = try #require(moRegion(messages, from: "func performLoadMessageHistory() async {", to: "\n    }\n\n"))
    // 앞 판은 화면이 보던 판(확성기 줄을 뺀 판)이다 — 날것(`messageHistory`)을 넘기면 받은 확성기 줄이 24시간 뒤 말풍선으로 선다.
    #expect(headLoad.contains("carryOlderMessagesAcrossHeadSlide(previousHead: visibleMessageHistory, nextHead: sorted)"),
            "머리 미끄러짐의 틈 메우기가 머리를 세우기 전에 없다(또는 확성기 줄을 뺀 판이 아니다)")
}

/// 주석을 걷은 소스(V0331 의 공용 도우미 — 코어로 간 파일도 찾는다). 못 읽으면 빈 글자(단언이 빨개진다).
private func moSource(_ name: String) -> String {
    (try? v0331Source(name)) ?? ""
}

/// `from` 부터 그 뒤 처음 나오는 `to` 까지(포함하지 않음). 없으면 nil.
private func moRegion(_ text: String, from: String, to: String) -> String? {
    guard let start = text.range(of: from),
          let end = text.range(of: to, range: start.upperBound..<text.endIndex) else { return nil }
    return String(text[start.lowerBound..<end.lowerBound])
}

// MARK: - ⑥ 잇기 · 머리 미끄러짐

@Test
func 이전대화_잇기는_다시_정렬하지_않고_머리가_이기며_머리보다_새_줄은_앞에_안_붙는다() {
    let base = Fx.now
    let head = [MoFx.entry("h1", "머리 첫 줄", at: base), MoFx.entry("h2", at: base.addingTimeInterval(5))]
    // 같은 초의 지난 쪽 줄(o2)은 머리 줄(h1)보다 **앞**이다 — 함께 정렬하면 순서표에 없는 o2 가 h1 뒤로 밀린다.
    let older = [MoFx.entry("o1", at: base.addingTimeInterval(-60)), MoFx.entry("o2", at: base),
                 MoFx.entry("h1", "옛 본문", at: base)]
    let merged = MessageOlderHistoryRules.merged(older: older, head: head)
    #expect(merged.map(\.id) == ["o1", "o2", "h1", "h2"])
    #expect(merged.first { $0.id == "h1" }?.body == "머리 첫 줄", "중복 id 에서 지난 쪽이 이겼다")
    #expect(MessageOlderHistoryRules.merged(older: [], head: head) == head)

    // 받은 쪽 붙이기: 머리에 있는 id · 이미 있는 id 는 빠지고, 붙은 줄은 안 읽음 칸이 비어 있다.
    var unreadOld = MoFx.entry("o0", at: base.addingTimeInterval(-120))
    unreadOld.isUnread = true
    // 머리를 받은 뒤 도착한 말(머리의 가장 새 줄보다 새 것)은 앞에 붙이지 않는다 — 다음 머리 조회가 받는다.
    let arrived = MoFx.entry("late", at: base.addingTimeInterval(5 + MessageOlderHistoryRules.headClockSlack + 1))
    let prepended = MessageOlderHistoryRules.prepending(
        [unreadOld, MoFx.entry("o1", at: base.addingTimeInterval(-60)), MoFx.entry("h2", at: base), arrived],
        to: [MoFx.entry("o1", at: base.addingTimeInterval(-60))], head: head
    )
    #expect(prepended.map(\.id) == ["o0", "o1"])
    #expect(prepended.allSatisfy { $0.isUnread == nil })
    // 머리가 비었으면(24시간 안에 말이 없는 상대) 받은 줄을 전부 붙인다.
    #expect(MessageOlderHistoryRules.prepending([unreadOld, arrived], to: [], head: []).map(\.id) == ["o0", "late"])
}

@Test
func 이전대화_미끄러짐_규칙은_그_상대의_빠진_옛_줄만_옮긴다() {
    let base = Fx.now
    // 머리를 다시 받은 때 — a1(85,000초 전 줄)이 24시간을 넘겼다.
    let later = base.addingTimeInterval(2_000)
    let previous = [MoFx.entry("a1", at: base.addingTimeInterval(-85_000)), MoFx.entry("a2", at: base.addingTimeInterval(-60))]
    let next = [MoFx.entry("a2", at: base.addingTimeInterval(-60))]
    let older = [MoFx.entry("o1", at: base.addingTimeInterval(-200_000))]
    #expect(MessageOlderHistoryRules.carriedAcrossHeadSlide(
        peer: Fx.peerA, previousHead: previous, nextHead: next, older: older, now: later
    ).map(\.id) == ["o1", "a1"])
    // 지난 쪽이 비어 있어도 옮긴다(커서만 있는 상대 — 언제 부를지는 스토어가 정한다).
    #expect(MessageOlderHistoryRules.carriedAcrossHeadSlide(
        peer: Fx.peerA, previousHead: previous, nextHead: next, older: [], now: later
    ).map(\.id) == ["a1"])
    // 새 머리보다 **새로운** 줄이 빠졌으면(서버가 지웠다) 옮기지 않는다.
    let vanished = [MoFx.entry("a2", at: base.addingTimeInterval(-60)), MoFx.entry("gone", at: base.addingTimeInterval(-30))]
    #expect(MessageOlderHistoryRules.carriedAcrossHeadSlide(
        peer: Fx.peerA, previousHead: vanished, nextHead: next, older: older, now: later
    ).map(\.id) == ["o1"])
}

@Test
func 이전대화_미끄러짐은_창_안에서_빠진_줄을_옮기지_않는다() {
    let base = Fx.now
    let older = [MoFx.entry("o1", at: base.addingTimeInterval(-200_000))]
    // 상대가 나를 차단했다(서버가 그 둘의 줄을 통째로 뺀다) — 새 머리에 그 상대 줄이 **하나도 없다**(상대 맨 앞이 없다).
    // 몇 분 전 말까지 "지난 말"로 남으면 서버가 감춘 대화가 화면에 그대로다. 창 안의 줄은 옮기지 않는다.
    let recent = [MoFx.entry("r1", at: base.addingTimeInterval(-600)), MoFx.entry("r2", at: base.addingTimeInterval(-60), isMine: true)]
    let others = [MoFx.entry("b1", at: base.addingTimeInterval(-30))].map {
        MessageHistoryEntry(id: $0.id, peerUserID: Fx.peerB, peerName: "다른 사람", peerAvatarURL: nil, body: $0.body,
                            createdAt: $0.createdAt, isMine: false)
    }
    #expect(MessageOlderHistoryRules.carriedAcrossHeadSlide(
        peer: Fx.peerA, previousHead: recent + others, nextHead: others, older: older, now: base
    ) == older, "창 안에서 빠진 줄(서버가 뺐다)이 지난 쪽으로 옮겨졌다")
    // 대조: 같은 모양인데 그 줄들이 정말 24시간을 넘겼다(상대가 하루 동안 말이 없었다) — 그때는 옮긴다.
    let aged = base.addingTimeInterval(86_400 + 600)
    #expect(MessageOlderHistoryRules.carriedAcrossHeadSlide(
        peer: Fx.peerA, previousHead: recent + others, nextHead: others, older: older, now: aged
    ).map(\.id) == ["o1", "r1", "r2"])
    // 시계가 조금 늦은 맥(서버 now() 보다 몇 분 뒤처짐)에서도 경계에 막 걸린 줄은 옮긴다(`headWindowSlack`).
    let edgeRow = [MoFx.entry("e1", at: base.addingTimeInterval(-86_400 + 120))]
    #expect(MessageOlderHistoryRules.carriedAcrossHeadSlide(
        peer: Fx.peerA, previousHead: edgeRow, nextHead: [], older: [], now: base
    ).map(\.id) == ["e1"])

    // 새 머리가 상한까지 찼다 — 그 맨 앞보다 옛 줄은 상한에 밀려난 것이다(24시간 안이어도 옮긴다). 맨 앞보다 새 줄이 빠졌으면 안 옮긴다.
    let full = (0..<3).map { MoFx.entry(moID("n", $0), at: base.addingTimeInterval(TimeInterval(-300 + $0 * 60))) }
    let pushedOut = [MoFx.entry("p1", at: base.addingTimeInterval(-900)), MoFx.entry("p2", at: base.addingTimeInterval(-120))]
    #expect(MessageOlderHistoryRules.carriedAcrossHeadSlide(
        peer: Fx.peerB, previousHead: pushedOut.map {
            MessageHistoryEntry(id: $0.id, peerUserID: Fx.peerB, peerName: "다른 사람", peerAvatarURL: nil, body: $0.body,
                                createdAt: $0.createdAt, isMine: false)
        }, nextHead: full, older: [], now: base, headLimit: 3
    ).map(\.id) == ["p1"])
    // 대조: 상한에 못 미친 머리라면 같은 줄(15분 전)은 창 안이라 안 옮긴다.
    #expect(MessageOlderHistoryRules.carriedAcrossHeadSlide(
        peer: Fx.peerB, previousHead: pushedOut.map {
            MessageHistoryEntry(id: $0.id, peerUserID: Fx.peerB, peerName: "다른 사람", peerAvatarURL: nil, body: $0.body,
                                createdAt: $0.createdAt, isMine: false)
        }, nextHead: full, older: [], now: base, headLimit: 4
    ).isEmpty)
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 이전대화_오래_열어_둔_대화에서_24시간_경계가_움직여도_가운데가_비지_않는다() async {
    let server = MoPageServer(rows: [
        MoRow(id: "a2", isMine: true, us: MoFx.micros(3_600)),
        // 머리의 a1 과 같은 id 를 실은 줄(다른 본문)도 온다 — 머리가 이긴다.
        MoRow(id: "a1", isMine: false, us: MoFx.micros(85_000), body: "서버가 다시 준 a1"),
        MoRow(id: "o2", isMine: false, us: MoFx.micros(100_000)),
        MoRow(id: "o1", isMine: true, us: MoFx.micros(200_000))
    ])
    let (store, host) = makeMessageReadStore("older-slide") { call, index in
        switch call.rpc {
        case "message_history_with_reads":
            if index == 0 {
                return Fx.historyReply([
                    MoFx.head("a1", isMine: false, secondsAgo: 85_000, body: "곧 24시간이 지날 말"),
                    MoFx.head("a2", isMine: true, secondsAgo: 3_600)
                ])
            }
            // 경계가 움직였다 — a1 이 머리에서 빠졌고 새 말 a3 이 왔다.
            return Fx.historyReply([
                MoFx.head("a2", isMine: true, secondsAgo: 3_600),
                MoFx.head("a3", isMine: false, secondsAgo: 10)
            ])
        case "message_page": return server.reply(call)
        default: return nil
        }
    }
    moOpen(store)
    await store.performLoadMessageHistory()
    await store.performLoadOlderMessages()
    #expect(moPage(host).count == 1)
    #expect(store.selectedConversationMessages.map(\.id) == ["o1", "o2", "a1", "a2"])
    #expect(store.selectedConversationMessages.first { $0.id == "a1" }?.body == "곧 24시간이 지날 말", "머리가 안 이겼다")

    // 시간이 흘러 a1(85,000초 전)이 24시간을 넘겼다 — 경계가 움직인 까닭은 시계다(창 안에서 빠진 줄은 옮기지 않는다).
    store.clock = { Fx.now.addingTimeInterval(2_000) }
    await store.performLoadMessageHistory()
    #expect(store.messageHistory.map(\.id) == ["a2", "a3"], "머리(24시간)는 서버가 준 그대로여야 한다")
    #expect(store.messageOlderPages[Fx.peerA]?.map(\.id) == ["o1", "o2", "a1"], "머리에서 빠진 a1 이 지난 쪽으로 안 옮겨졌다")
    #expect(store.selectedConversationMessages.map(\.id) == ["o1", "o2", "a1", "a2", "a3"], "대화 가운데가 비었다")
    #expect(store.selectedConversationMessages.first { $0.id == "a1" }?.body == "곧 24시간이 지날 말")
    #expect(store.messageOlderPages[Fx.peerA]?.allSatisfy { $0.isUnread == nil } == true)
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 이전대화_끝까지_받은_뒤_경계가_움직여도_머리에서_빠진_말이_남는다() async {
    // 30일 안의 말이 전부 머리 안에 있었다 — 쪽은 전부 머리와 겹쳐 지난 쪽은 비고 커서만 남는다(끝 줄).
    let rows = (0..<6).map { MoRow(id: moID("h", $0), isMine: false, us: MoFx.micros(80_000 - $0 * 10_000)) }
    let server = MoPageServer(rows: rows)
    let (store, host) = makeMessageReadStore("older-slide-cursor") { call, index in
        switch call.rpc {
        case "message_history_with_reads":
            if index == 0 {
                return Fx.historyReply((0..<6).map { MoFx.head(moID("h", $0), isMine: false, secondsAgo: 80_000 - $0 * 10_000) })
            }
            // 경계가 움직였다 — 앞 셋(h000~h002)이 머리에서 빠졌다.
            return Fx.historyReply((3..<6).map { MoFx.head(moID("h", $0), isMine: false, secondsAgo: 80_000 - $0 * 10_000) })
        case "message_page": return server.reply(call)
        default: return nil
        }
    }
    moOpen(store)
    await store.performLoadMessageHistory()
    await store.performLoadOlderMessages()
    #expect(moPage(host).count == 1)
    #expect(store.messageOlderPages[Fx.peerA] == nil)
    #expect(store.messageOlderCursors[Fx.peerA]?.id == "h000")
    #expect(store.messageOlderRowState == .end)

    // 끝 줄이라 다시 받을 길이 없다 — 빠진 셋은 지난 쪽으로 옮겨져야 대화가 안 줄어든다.
    // 경계가 움직인 까닭은 시계다: 30,000초 뒤 앞 셋(80,000 · 70,000 · 60,000초 전)이 24시간을 넘겼다.
    store.clock = { Fx.now.addingTimeInterval(30_000) }
    await store.performLoadMessageHistory()
    #expect(store.messageHistory.map(\.id) == (3..<6).map { moID("h", $0) })
    #expect(store.selectedConversationMessages.map(\.id) == (0..<6).map { moID("h", $0) }, "끝까지 받은 대화가 경계를 따라 줄었다")
    #expect(moPage(host).count == 1, "머리 다시 받기가 이전 대화를 물었다")
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 이전대화_머리에서_빠진_확성기_줄은_지난_쪽으로_안_옮긴다() async {
    // 받은 확성기 fan-out 줄(mg)은 머리(`messageHistory`)에 있고 화면은 배너 목록으로 거른다. 24시간이 지나 머리에서 빠질 때
    // 날것의 머리를 옮기면 그 줄이 지난 쪽에서 메시지 말풍선으로 선다. 기준선: 배너 목록이 없는 서버(필터 꺼짐)는 확성기 줄도
    // 메시지로 보여 주므로 옮긴다 — 같은 단언 자리에서 갈린다("숨긴다"가 늘 참이라 초록인 시험이 아니게).
    for inbox in [true, false] {
        let megaphoneBody = "📢 라운지에 간식 있어요"
        let server = MoPageServer(rows: [
            MoRow(id: "a2", isMine: true, us: MoFx.micros(3_600)),
            MoRow(id: "a1", isMine: false, us: MoFx.micros(70_000)),
            MoRow(id: "mg", isMine: false, us: MoFx.micros(80_000), body: megaphoneBody, megaphone: true),
            MoRow(id: "o1", isMine: false, us: MoFx.micros(100_000))
        ])
        let (store, _) = makeMessageReadStore("older-slide-mega-\(inbox)") { call, index in
            switch call.rpc {
            case "megaphone_inbox":
                guard inbox else { return Fx.missingFunction(call.rpc) }
                return Reply(body: Fx.json([[
                    "message_id": "mg", "megaphone_id": "mp-mg", "sender_id": Fx.peerA, "sender_display_name": "민수",
                    "sender_avatar_url": NSNull(), "body": "라운지에 간식 있어요", "created_epoch": MoFx.nowEpoch - 80_000
                ]]))
            case "message_unread_summary_v2":
                return inbox ? Fx.summaryReply([]) : Fx.missingFunction(call.rpc)
            case "message_unread_summary":
                return Fx.summaryReply([])
            case "mark_messages_read":
                return Fx.markReply()
            case "message_history_with_reads":
                if index == 0 {
                    return Fx.historyReply([
                        MoFx.head("mg", isMine: false, secondsAgo: 80_000, body: megaphoneBody),
                        MoFx.head("a1", isMine: false, secondsAgo: 70_000, body: "어제 이야기"),
                        MoFx.head("a2", isMine: true, secondsAgo: 3_600)
                    ])
                }
                return Fx.historyReply([MoFx.head("a2", isMine: true, secondsAgo: 3_600)])
            case "message_page": return server.reply(call)
            default: return nil
            }
        }
        store.megaphoneBanner.schedule = { _, _ in }
        store.megaphoneBanner.clock = { Fx.now }
        await store.requestMegaphoneBannerRefresh()?.value
        await messageReadWait { messageReadIdle(store) }
        #expect(store.megaphoneBanner.capability == (inbox ? .available : .unavailable), "inbox=\(inbox)")
        moOpen(store)
        await store.performLoadMessageHistory()
        await store.performLoadOlderMessages()
        #expect(store.messageOlderPages[Fx.peerA]?.map(\.id) == ["o1"], "inbox=\(inbox)")
        #expect(store.selectedConversationMessages.contains { $0.id == "mg" } == !inbox, "전제(inbox=\(inbox)): 머리의 확성기 줄 표시")

        // 시간이 흘러 mg · a1 이 24시간을 넘겼다 — 머리에서 빠진다.
        store.clock = { Fx.now.addingTimeInterval(20_000) }
        await store.performLoadMessageHistory()
        await messageReadWait { messageReadIdle(store) }
        if inbox {
            #expect(store.messageOlderPages[Fx.peerA]?.map(\.id) == ["o1", "a1"], "확성기 줄이 지난 쪽으로 옮겨졌다")
            #expect(store.selectedConversationMessages.map(\.id) == ["o1", "a1", "a2"], "확성기 줄이 메시지 말풍선으로 섰다")
        } else {
            #expect(store.messageOlderPages[Fx.peerA]?.map(\.id) == ["o1", "mg", "a1"])
            #expect(store.selectedConversationMessages.map(\.id) == ["o1", "mg", "a1", "a2"])
        }
    }
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 이전대화_지난_쪽의_내_말_읽음은_머리를_따른다() async {
    // 규칙: 머리에 상대가 읽은 내 말이 있으면 지난 쪽의 내 말은 전부 읽은 것이다(지난 쪽은 머리보다 앞 · 읽음 경계는 앞으로만).
    let base = Fx.now
    func mine(_ id: String, _ offset: TimeInterval, read: Bool?) -> MessageHistoryEntry {
        var entry = MoFx.entry(id, at: base.addingTimeInterval(offset), isMine: true)
        entry.readByPeer = read
        return entry
    }
    let older = [mine("o1", -200_000, read: false), MoFx.entry("o2", at: base.addingTimeInterval(-150_000)),
                 mine("o3", -100_000, read: false), mine("o4", -90_000, read: nil)]
    // 기준선: 머리의 내 말도 아직 안 읽혔다 — 지난 쪽 1 은 그대로다.
    #expect(MessageOlderHistoryRules.merged(older: older, head: [mine("h1", -60, read: false)]).map(\.readByPeer)
        == [false, nil, false, nil, false])
    // 상대가 읽었다 — 지난 쪽의 내 말도 읽음. 받은 말(o2)과 모름(o4 — 옛 서버)은 그대로다.
    #expect(MessageOlderHistoryRules.merged(older: older, head: [mine("h1", -60, read: true)]).map(\.readByPeer)
        == [true, nil, true, nil, true])
    // 머리에 내 말이 없으면(받은 말뿐) 바꿀 근거가 없다.
    #expect(MessageOlderHistoryRules.merged(older: older, head: [MoFx.entry("h2", at: base)]).map(\.readByPeer)
        == [false, nil, false, nil, nil])

    // 스토어: 지난 쪽을 받은 뒤 상대가 읽었다 → 머리를 다시 받는다(message_read 신호와 같은 길) → 지난 쪽의 1 도 지워진다.
    let server = MoPageServer(rows: [
        MoRow(id: "a1", isMine: true, us: MoFx.micros(60)),
        MoRow(id: "o2", isMine: false, us: MoFx.micros(150_000)),
        MoRow(id: "o1", isMine: true, us: MoFx.micros(200_000), readByPeer: false)
    ])
    let (store, _) = makeMessageReadStore("older-read-follow") { call, index in
        switch call.rpc {
        case "message_history_with_reads":
            return Fx.historyReply([MoFx.head("a1", isMine: true, secondsAgo: 60, readByPeer: index > 0)])
        case "message_page": return server.reply(call)
        default: return nil
        }
    }
    moOpen(store)
    await store.performLoadMessageHistory()
    await store.performLoadOlderMessages()
    #expect(store.selectedConversationMessages.map(\.id) == ["o1", "o2", "a1"])
    #expect(store.selectedConversationMessages.first { $0.id == "o1" }?.readByPeer == false, "전제: 받은 그때는 안 읽음")
    await store.performLoadMessageHistory()
    #expect(store.messageHistory.first?.readByPeer == true, "전제: 머리의 1 이 지워졌다")
    #expect(store.selectedConversationMessages.first { $0.id == "o1" }?.readByPeer == true,
            "새 말은 읽었는데 지난 쪽의 내 말에 낡은 1 이 남았다")
    #expect(store.selectedConversationMessages.first { $0.id == "o2" }?.readByPeer == nil)
}

// MARK: - ⑦ 화면 — 빈 자리 높이

/// 빈 자리 한 차림의 **자연 높이**(폭은 고정 · 높이는 제안 없음) — `ViewThatFits(in: .vertical)` 이 재는 값과 같은 물음이다.
@MainActor
private func moIdealHeight(_ view: MessagePanelEmptyStack) -> CGFloat {
    // 대화 자리 폭(`contentWidth`)에서 빈 자리 좌우 padding 16×2 를 뺀 폭.
    let host = NSHostingView(rootView: view
        .frame(width: MessagePanelLayout.contentWidth - 32)
        .fixedSize(horizontal: false, vertical: true))
    host.layoutSubtreeIfNeeded()
    return host.fittingSize.height
}

@MainActor
@Test
func 이전대화_빈_대화의_맨_위_줄은_가장_좁은_틀에도_들어간다() throws {
    // 가장 좁은 틀: 새 버전 배너 + 패치노트 4줄 + 주간 목표 편집이 다 떴다(`minConversationHeight`). 넉넉한 틀: 크롬 없음(`emptyStateHeight`).
    let narrow = MessagePanelLayout.minConversationHeight
    let roomy = min(MessagePanelLayout.conversationHeight(extraChromeHeight: 0), MessagePanelLayout.emptyStateHeight)
    #expect(MessagePanelLayout.conversationHeight(extraChromeHeight: 1_000) == narrow)
    let state = MessagePanelEmptyMessage.state(hasPeer: true, loaded: true, failed: false)
    let full = moIdealHeight(MessagePanelEmptyStack(state: state, olderRow: .button))
    let noHint = moIdealHeight(MessagePanelEmptyStack(state: state, olderRow: .button, showsHint: false))
    let compact = moIdealHeight(MessagePanelEmptyStack(state: state, olderRow: .button, showsSymbol: false, showsHint: false))
    // 기준선: 그 줄을 얹은 다 차림은 가장 좁은 틀을 넘친다(그래서 차림을 고른다 — 이 시험이 공허하지 않다는 증거).
    #expect(full > narrow, "다 차림 \(full)pt 가 좁은 틀 \(narrow)pt 에 들어간다 — 기준선이 무너졌다")
    // 가장 좁은 틀에도 들어가는 차림이 있다 — ViewThatFits 가 그것을 고른다(넘쳐 머리 구분선 · 입력칸을 덮지 않는다).
    #expect(compact <= narrow, "가장 작은 차림 \(compact)pt 도 좁은 틀 \(narrow)pt 를 넘친다")
    #expect(compact < noHint && noHint < full)
    // 넉넉한 틀에서는 다 차림이 들어간다 — 크롬이 없는 날의 그림(스냅숏 ④)이 예전 그대로다.
    #expect(full <= roomy, "다 차림 \(full)pt 가 넉넉한 틀 \(roomy)pt 도 넘친다")
    // 소스: 줄이 있을 때만 차림을 고르고, 마지막 차림은 아이콘과 보조 한 줄을 뺀 것이다.
    let view = moSource("CheckMessageView.swift")
    let empty = try #require(moRegion(view, from: "private var emptyState: some View {", to: "private var composer: some View {"))
    #expect(empty.contains("ViewThatFits(in: .vertical)"), "빈 자리가 틀에 맞춰 차림을 고르지 않는다")
    #expect(empty.contains("emptyStack(state, olderRow: olderRow, showsSymbol: false, showsHint: false)"))
}

// MARK: - ⑦ 화면 — 소스 계약

@Test
func 이전대화_맨_위_줄은_스크롤_안의_첫_줄이고_틀_높이에_따로_더한다() throws {
    let view = moSource("CheckMessageView.swift")
    let content = try #require(moRegion(view, from: "private var content: some View {", to: "ForEach(lines)"))
    #expect(content.contains("MessageOlderHistoryRow(state: olderRow)"), "맨 위 줄이 스크롤 내용의 첫 줄이 아니다")
    #expect(view.contains("let messages = store.selectedConversationMessages"), "대화가 지난 쪽을 안 그린다")
    #expect(view.contains("let olderRow = store.messageOlderRowState"))
    #expect(view.contains("onLoadOlder: { store.loadOlderMessages() }"))
    #expect(view.contains("olderAnchor: store.messageOlderScrollAnchor"))
    #expect(view.contains("MessagePanelLayout.olderRowHeight + 6"), "맨 위 줄의 높이를 틀 추정에 안 더했다")
    let estimate = try #require(moRegion(view, from: "static func conversationContentHeight(lines:", to: "\n    }\n"))
    #expect(!estimate.contains("olderRow"), "맨 위 줄의 높이를 말풍선 산식에 섞었다")
    // 붙인 뒤 제자리: 빈 id 가 아닐 때 애니메이션 없이 위에 맞춘다.
    let conversation = try #require(moRegion(view, from: "struct MessageConversationView: View {", to: "private var content: some View {"))
    #expect(conversation.contains("guard let id = next?.messageID, !id.isEmpty else { return }"), "맞추기 가드가 뒤집혔다")
    #expect(conversation.contains("proxy.scrollTo(id, anchor: .top)"))
    // 툴팁은 우리 말풍선이다(시스템 툴팁 금지).
    let row = try #require(moRegion(view, from: "struct MessageOlderHistoryRow: View {", to: "\n}\n"))
    #expect(row.contains(".checkTooltip(MessageNoticeText.olderTooltip)"))
    #expect(!row.contains(".help("))
    // 빈 대화에서도 준다(24시간 안에 말이 없는 상대).
    let empty = try #require(moRegion(view, from: "private var emptyState: some View {", to: "private var composer: some View {"))
    #expect(empty.contains("store.messageOlderRowState"))
    #expect(view.contains("Text(store.messageExpiryNoticeNow)"))
}

@Test
func 이전대화_전선_이름은_코어_한_파일에만_있고_부르는_자리는_버튼_뒤뿐이다() throws {
    let root = CheckCoreSourceLayout.macDirectory
    let files = try FileManager.default.checkSourcesContentsOfDirectory(atPath: root.path).filter { $0.hasSuffix(".swift") }
    var wire: [String] = []
    var fetchers: [String] = []
    var performers: [String] = []
    var tappers: [String] = []
    for file in files {
        let code = moSource(file)
        if code.contains("message_page") || code.contains("p_before_us") { wire.append(file) }
        if code.contains("fetchMessagePage(") { fetchers.append(file) }
        if code.contains("performLoadOlderMessages(") { performers.append(file) }
        if code.contains("loadOlderMessages()") { tappers.append(file) }
    }
    #expect(wire == ["MessageHistoryPaging.swift"], "전선 이름이 여러 곳에 있다: \(wire)")
    // 2026-11-11(사진): 사진 칸 조회(`WorkTimerStoreMessagePhotos` — 대화를 열 때 · 열린 대화에 받은 말이 올 때)가 같은 함수의 둘째 자리다.
    #expect(Set(fetchers) == ["MessageHistoryPaging.swift", "WorkTimerStoreMessageOlder.swift", "WorkTimerStoreMessagePhotos.swift"],
            "서비스를 부르는 자리: \(fetchers)")
    #expect(Set(performers) == ["WorkTimerStoreMessageOlder.swift"], "이전 대화 조회를 부르는 자리: \(performers)")
    #expect(Set(tappers) == ["CheckMessageView.swift", "WorkTimerStoreMessageOlder.swift"], "버튼 문을 부르는 자리: \(tappers)")
    // 새 요약(v3) · 대화 목록(message_threads)은 이번 판에 안 쓴다(오케스트레이터: "안 읽음 점과 읽음 처리는 지금처럼").
    let all = files.map(moSource).joined()
    #expect(!all.contains("message_unread_summary_v3") && !all.contains("message_threads"))
}

@Test
func 이전대화_새_문구는_상수에서_나온다() {
    #expect(MessageNoticeText.historyHours == 24, "24시간 머리는 그대로다(폰과 한 벌)")
    #expect(MessageNoticeText.expiry == "24시간이 지난 메시지는 사라져요")
    #expect(MessageNoticeText.storeDays == 30)
    #expect(MessageNoticeText.olderPageLimit == 50)
    #expect(MessageNoticeText.storeExpiry == "30일이 지난 메시지는 사라져요")
    #expect(MessageNoticeText.olderTooltip.contains("\(MessageNoticeText.storeDays)일"))
    #expect(MessageNoticeText.olderButtonTitle == "이전 대화 더 보기")
    #expect(MessageNoticeText.photoFallbackBody == "📷 사진")
    #expect(MessageOlderRowState.button.isTappable && MessageOlderRowState.failed.isTappable)
    #expect(!MessageOlderRowState.loading.isTappable && !MessageOlderRowState.end.isTappable)
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 이전대화_입력칸_안내는_한_번이라도_성공한_뒤에만_30일이다() {
    let (store, _) = makeMessageReadStore("older-notice")
    #expect(store.messageOlderAvailable == nil)
    #expect(store.messageExpiryNoticeNow == WorkTimerStore.messageExpiryNotice, "모르는 서버인데 30일이라고 말한다")
    store.messageOlderAvailable = false
    #expect(store.messageExpiryNoticeNow == WorkTimerStore.messageExpiryNotice, "함수가 없는 서버에서 30일이라고 말한다")
    store.messageOlderAvailable = true
    #expect(store.messageExpiryNoticeNow == "\(MessageNoticeText.storeDays)일이 지난 메시지는 사라져요")
}

// MARK: - ⑦ 화면 — 호스팅(붙인 뒤 제자리)

@MainActor
private func moSpin(_ seconds: Double = 0.05) {
    RunLoop.current.run(until: Date().addingTimeInterval(seconds))
}

@MainActor
private func moFirstScrollView(in root: NSView) -> NSScrollView? {
    if let match = root as? NSScrollView { return match }
    for child in root.subviews {
        if let match = moFirstScrollView(in: child) { return match }
    }
    return nil
}

/// 내용 맨 위에서 화면 맨 위까지의 거리(pt) — 스크롤 위치.
@MainActor
private func moOffsetFromTop(_ scrollView: NSScrollView) -> CGFloat {
    let clip = scrollView.contentView
    guard let document = scrollView.documentView else { return 0 }
    return document.isFlipped ? clip.bounds.minY : document.frame.height - clip.bounds.maxY
}

@MainActor
private func moDistanceFromBottom(_ scrollView: NSScrollView) -> CGFloat {
    let clip = scrollView.contentView
    guard let document = scrollView.documentView else { return 0 }
    return document.isFlipped ? document.frame.height - clip.bounds.maxY : clip.bounds.minY
}

@MainActor
private func moScrollToTop(_ scrollView: NSScrollView) {
    guard let document = scrollView.documentView else { return }
    let clip = scrollView.contentView
    let y = document.isFlipped ? 0 : max(0, document.frame.height - clip.bounds.height)
    clip.scroll(to: NSPoint(x: 0, y: y))
    scrollView.reflectScrolledClipView(clip)
}

@MainActor
@Test
func 이전대화_붙인_뒤에도_읽던_자리가_제자리다() throws {
    let now = Date()
    let head = (0..<14).map {
        MoFx.entry("h\($0)", "오늘 이야기 \($0) 번째 줄이에요", at: now.addingTimeInterval(TimeInterval(-3_000 + $0 * 60)))
    }
    let older = (0..<14).map {
        MoFx.entry("o\($0)", "지난 이야기 \($0) 번째 줄이에요", at: now.addingTimeInterval(TimeInterval(-3 * 86_400 + $0 * 60)))
    }
    let width = MessagePanelLayout.contentWidth
    let height: CGFloat = 200
    func make(_ entries: [MessageHistoryEntry], anchor: MessageOlderScrollAnchor?) -> AnyView {
        AnyView(
            MessageConversationView(
                items: MessageThreadBuilder.timeline(entries, now: now),
                peerUserID: Fx.peerA,
                lastMessageID: entries.last?.id,
                readReceiptsAvailable: true,
                olderRow: .button,
                onLoadOlder: {},
                olderAnchor: anchor
            )
            .frame(width: width, height: height, alignment: .top)
            .background(CheckTheme.background)
        )
    }

    /// 머리만 그린 대화를 맨 위까지 올린 뒤(= [이전 대화 더 보기]를 누르는 자리) 지난 쪽을 붙인다. (붙인 뒤 위치, 자란 높이, 바닥까지 거리).
    func prependFromTop(anchor: MessageOlderScrollAnchor?) throws -> (offset: CGFloat, grown: CGFloat, fromBottom: CGFloat) {
        // 창은 화면에 올리지 않는다(orderFront 없음) — 붙이기만으로 배치·스크롤이 돈다(V0331MessageArrivalViewTests 와 같은 수법).
        let host = NSHostingView(rootView: make(head, anchor: nil))
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        host.layoutSubtreeIfNeeded()
        moSpin(0.2)
        let scrollView = try #require(moFirstScrollView(in: host), "대화 안에 스크롤 뷰가 없다")
        moScrollToTop(scrollView)
        moSpin(0.2)
        // 맨 위의 실측 위치(내용 여백 · 삽입 여백만큼 0 이 아닐 수 있다). 이후 위치는 이 값에서 잰다.
        let top = moOffsetFromTop(scrollView)
        #expect(top < 30, "전제: 맨 위까지 올렸다(\(top)pt)")
        #expect(moDistanceFromBottom(scrollView) > MessageScrollFollow.nearBottomThreshold, "전제: 머리만으로도 화면보다 길다")
        let before = scrollView.documentView?.frame.height ?? 0

        host.rootView = make(older + head, anchor: anchor)
        host.layoutSubtreeIfNeeded()
        moSpin(0.45)
        host.layoutSubtreeIfNeeded()
        moSpin(0.1)
        let after = scrollView.documentView?.frame.height ?? 0
        return (moOffsetFromTop(scrollView) - top, after - before, moDistanceFromBottom(scrollView))
    }

    let anchored = try prependFromTop(anchor: MessageOlderScrollAnchor(serial: 1, messageID: "h0"))
    #expect(anchored.grown > 200, "전제: 지난 쪽 열네 줄이 붙어 내용이 자랐다(\(anchored.grown)pt)")
    // 붙기 전 맨 위 메시지(h0)가 화면 맨 위다 = 위치가 자란 높이(+ h0 위의 맨 위 줄 · 날짜 구분선)만큼 내려가 있다.
    #expect(anchored.offset >= anchored.grown - 4 && anchored.offset <= anchored.grown + 110,
            "붙인 뒤 읽던 자리를 잃었다(위치 \(anchored.offset)pt · 자란 높이 \(anchored.grown)pt)")
    #expect(anchored.fromBottom > MessageScrollFollow.nearBottomThreshold, "붙인 뒤 바닥으로 끌려갔다")

    // 대조군: 맞추기 표 없이 붙이면 위치가 다르다(위 단언이 저절로 참인 것이 아니다).
    let unanchored = try prependFromTop(anchor: nil)
    #expect(abs(unanchored.offset - anchored.offset) > 60,
            "맞추기 없이도 같은 자리다(맞춤 \(anchored.offset)pt · 없음 \(unanchored.offset)pt) — 비교가 헛돈다")
}

// MARK: - ⑦ 화면 — 스냅숏 (FEATURE_SHOTS_DIR)

/// 스냅숏을 `FEATURE_SHOTS_DIR` 에 저장한다(설정돼 있을 때만). 다른 메시지 스냅숏과 같은 자리(`CHECK_SNAPSHOT_DIR/panels`)에도 남긴다.
private func moSaveShot(_ bitmap: NSBitmapImageRep, name: String) {
    if let dir = ProcessInfo.processInfo.environment["FEATURE_SHOTS_DIR"], !dir.isEmpty {
        let url = URL(fileURLWithPath: dir, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        if let png = bitmap.representation(using: .png, properties: [:]) {
            try? png.write(to: url.appendingPathComponent(name))
        }
    }
    MessagePanelSnapshots.save(bitmap, name: name)
}

@MainActor
private func moMenuBitmap(_ store: WorkTimerStore) throws -> NSBitmapImageRep {
    // ★ ImageRenderer 는 ScrollView 안쪽 · TextEditor 를 못 그린다 — 렌더 시험 전용 두 스위치(앱은 언제나 false).
    let view = CheckMenuView(store: store, previewClipsOverflowList: true, previewPlainTextEditors: true)
    return try #require(CheckRenderSettle.bitmap(view, scale: 2), "렌더 실패")
}

private func moLooksDifferent(_ lhs: NSBitmapImageRep, _ rhs: NSBitmapImageRep) -> Bool {
    guard let a = lhs.cgImage, let b = rhs.cgImage, let diff = CheckRenderDiff(a, b) else { return false }
    return diff.looksDifferent
}

@MainActor
@Test(.gomokuDefaultsCleanup)
func 이전대화_화면_스냅숏() throws {
    let (store, _) = makeMessageReadStore("older-shots")
    store.isMenuPresented = true
    store.displayNow = Date()
    store.currentTeamID = URLProtocolStub.stubTeamID
    store.teamName = "아잉팀"
    store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 3_600)
    let now = Date()
    let head = [
        MoFx.entry("h1", "오늘 점심 같이 먹어요", at: now.addingTimeInterval(-1_800)),
        MoFx.entry("h2", "좋아요 12시에 봬요", at: now.addingTimeInterval(-1_500), isMine: true)
    ]
    store.messageHistory = head
    store.messageHistoryReadSnapshot = MessageHistoryReadSnapshot(serial: 1, serverOrder: ["h1": 0, "h2": 1])
    store.messageReadReceiptsAvailable = true
    store.messageHistoryLoaded = true
    store.isMessagePanelVisible = true
    store.selectedMessagePeerID = Fx.peerA

    // ① 모르는 서버 — 대화 맨 위에 [이전 대화 더 보기], 안내는 24시간 그대로.
    let withButton = try moMenuBitmap(store)
    moSaveShot(withButton, name: "msg30-1-button.png")
    #expect(Double(withButton.pixelsHigh) / 2 <= 700, "팝오버 높이 상한을 넘었다")

    // 대조: 함수가 없는 서버 — 줄이 없다.
    store.messageOlderAvailable = false
    let hidden = try moMenuBitmap(store)
    #expect(moLooksDifferent(withButton, hidden), "맨 위 줄이 그려지지 않았다(숨긴 그림과 같다)")
    store.messageOlderAvailable = nil

    // ② 지난 쪽을 불러왔다 — 사흘 전 날짜 구분선 + 옛 말(사진 줄은 글로) + 오늘. 안내는 30일.
    store.messageOlderAvailable = true
    store.messageOlderPages[Fx.peerA] = [
        MoFx.entry("o1", "지난 금요일 회의록 보냈어요", at: now.addingTimeInterval(-3 * 86_400)),
        MoFx.entry("o2", MessageNoticeText.photoFallbackBody, at: now.addingTimeInterval(-3 * 86_400 + 60)),
        MoFx.entry("o3", "확인했어요 고마워요", at: now.addingTimeInterval(-3 * 86_400 + 120), isMine: true)
    ]
    store.messageOlderHasMore[Fx.peerA] = true
    let loaded = try moMenuBitmap(store)
    moSaveShot(loaded, name: "msg30-2-older-loaded.png")
    #expect(moLooksDifferent(loaded, withButton), "지난 쪽이 그려지지 않았다")
    #expect(Double(loaded.pixelsHigh) / 2 <= 700)

    // ③ 더 없다 — 끝 줄.
    store.messageOlderHasMore[Fx.peerA] = false
    let end = try moMenuBitmap(store)
    moSaveShot(end, name: "msg30-3-end.png")
    #expect(moLooksDifferent(end, loaded), "끝 줄이 버튼과 같은 그림이다")

    // ④ 24시간 안에 말이 없는 상대 — 빈 자리에도 버튼.
    store.messageOlderPages = [:]
    store.messageOlderHasMore = [:]
    store.messageOlderAvailable = nil
    store.messageHistory = []
    store.messageHistoryReadSnapshot = MessageHistoryReadSnapshot(serial: 2, serverOrder: [:])
    let empty = try moMenuBitmap(store)
    moSaveShot(empty, name: "msg30-4-empty-with-button.png")
    store.messageOlderAvailable = false
    let emptyHidden = try moMenuBitmap(store)
    #expect(moLooksDifferent(empty, emptyHidden), "빈 대화에 [이전 대화 더 보기]가 안 그려졌다")
    #expect(Double(empty.pixelsHigh) / 2 <= 700)
}
