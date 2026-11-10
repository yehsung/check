import AppKit
import CheckRenderTestSupport
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// 2026-11-11 — 지난 확성기(최근 30일 모아 보기) 계약. 서버 함수는 최종 목록(server-spare-1111 CONTRACT-v2 §2)이다:
// `megaphone_feed(p_before_us, p_limit)` → 줄 배열 · 최신이 먼저 · 본문은 서버가 머리말을 뗐다 · 커서는 마지막 줄의 정수 µs.
// `megaphone_admin_hide(p_id, p_hidden)` → {status: ok | forbidden | not_found, hidden}.
//
// 재는 것(모양이 아니라 결과):
//   코어 — 요청 키 집합이 정확히 둘(첫 쪽은 명시적 null) · 운영 디코더 그대로 읽기(깨진 줄만 빠진다) · 머리말을 다시 떼지 않기 ·
//          내 글 가르기 · 커서 = 마지막 줄의 µs(Int64 정밀도) · 중복 없음 · 404 → 닫힘 · 다음 진입에서 요청 없이 다시 모름 ·
//          세대 가드 · 꼬리 지키기 · 운영자 내리기의 키 · 결과.
//   맥   — 작성기 열기·팝오버 열기·상점 열기는 0건 · 페이지 열기만 묻는다 · 실시간 신호는 페이지가 떠 있을 때만 ·
//          차단한 사람은 곧바로 빠진다 · 신고는 보낸 사람 신고(메시지 id 없음) · 내리기는 운영자 깃발 · 로그아웃 · 배너 스토어에 안 들어간다.
//   화면 — 페이지 · 작성기 문 · 신고 시트가 팝오버 700pt 안 · 작성기 높이 166 그대로. PNG 는 FEATURE_SHOTS_DIR 이 있으면 거기에.
//
// 서버는 스텁이다(`GomokuStubProtocol` · `MessageReadStubProtocol` — 시험마다 고유 호스트). 문자열은 전부 지어낸 것이다.

// MARK: - 하네스

private let mfMe = "00000000-0000-0000-0000-0000000000a1"
private let mfOther = "00000000-0000-0000-0000-0000000000c3"
private let mfThird = "00000000-0000-0000-0000-0000000000d4"
private let mfWall0 = Date(timeIntervalSince1970: 1_800_000_000)

private struct MFError: Error {}

@MainActor
private final class MFHost: GomokuStoreHost {
    var session: SupabaseSession?
    var sessionGeneration = 0
    let service: SupabaseWorkService
    var realtimeState: RealtimeState = .idle(.disabled)
    var rubyBalance: Int?

    init(service: SupabaseWorkService, userID: String) {
        self.service = service
        session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: userID)
    }

    func switchAccount(to userID: String) {
        session = SupabaseSession(accessToken: "access-token-\(userID)", refreshToken: nil, userID: userID)
        sessionGeneration += 1
    }

    func withSessionRetry<T>(_ operation: (SupabaseSession) async throws -> T) async throws -> T {
        guard let session else { throw MFError() }
        return try await operation(session)
    }

    func classifyAuthError(_ error: Error) -> AuthErrorDisposition { .transient }
}

@MainActor
private enum MFRetention {
    /// 스토어는 호스트를 약참조로 든다 — 시험이 버리면 요청이 한 건도 안 나간다.
    static var hosts: [MFHost] = []
}

@MainActor
private struct MFRig {
    let store: MegaphoneFeedStore
    let owner: MFHost
    let host: String

    var calls: [GomokuStubProtocol.Call] { GomokuStubProtocol.calls(host: host, rpc: "megaphone_feed") }
    var hideCalls: [GomokuStubProtocol.Call] { GomokuStubProtocol.calls(host: host, rpc: "megaphone_admin_hide") }
}

@MainActor
private func mfMake(_ label: String, pageSize: Int = MegaphoneFeedRules.pageSize,
                    handler: @escaping GomokuStubProtocol.Handler) -> MFRig {
    let host = "mf-\(label)-\(UUID().uuidString.prefix(8))".lowercased()
    GomokuStubProtocol.register(host: host, handler: handler)
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!, anonKey: "anon-test-key", session: GomokuStubProtocol.session())
    let owner = MFHost(service: service, userID: mfMe)
    MFRetention.hosts.append(owner)
    let store = MegaphoneFeedStore(host: owner)
    store.pageSize = pageSize
    return MFRig(store: store, owner: owner, host: host)
}

/// 줄의 µs — `ago` 초 전 + 밀리초 아래 자리(정밀도를 재려고 µs 끝자리를 남긴다).
private func mfMicros(_ ago: Double, from now: Date = mfWall0) -> Int64 {
    Int64(((now.timeIntervalSince1970 - ago) * 1_000).rounded()) * 1_000 + 123
}

/// 피드 한 줄(서버 모양 그대로 — 계약 §2 의 스네이크 키 아홉). `ago` 는 기준 시각의 몇 초 전.
private func mfRow(_ id: String, ago: Double = 60, sender: String = mfOther, name: String = "보낸이",
                   body: String = "모두 안녕", isMine: Bool = false, recipients: Int = 12,
                   avatar: String? = nil, now: Date = mfWall0) -> [String: Any] {
    let micros = mfMicros(ago, from: now)
    return [
        "megaphone_id": id, "sender_id": sender, "sender_display_name": name,
        "sender_avatar_url": avatar ?? NSNull(), "body": body, "recipients": recipients, "is_mine": isMine,
        "created_epoch_ms": micros / 1_000, "created_epoch_us": micros,
    ]
}

private func mfJSON(_ object: Any) -> String {
    String(decoding: try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
}

private func mfArray(_ rows: [[String: Any]]) -> GomokuStubProtocol.Reply {
    GomokuStubProtocol.Reply(body: mfJSON(rows))
}

/// 함수 없는 서버(앱이 서버보다 먼저 나간 창).
private let mfMissing = GomokuStubProtocol.Reply(
    status: 404, body: #"{"code":"PGRST202","message":"Could not find the function public.megaphone_feed in the schema cache"}"#)

@MainActor
private func mfIDs(_ store: MegaphoneFeedStore) -> [String] { store.items.map(\.megaphoneID) }

/// 운영 서비스(디코더가 운영 그대로)로 한 쪽을 받는다 — 응답 본문만 스텁이 정한다.
private func mfFetch(_ label: String, body: String, limit: Int) async throws -> MegaphoneFeedPage {
    let host = "mf-fetch-\(label)-\(UUID().uuidString.prefix(8))".lowercased()
    GomokuStubProtocol.register(host: host) { rpc, _, _ in rpc == "megaphone_feed" ? GomokuStubProtocol.Reply(body: body) : nil }
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!, anonKey: "anon-test-key", session: GomokuStubProtocol.session())
    return try await service.fetchMegaphoneFeed(accessToken: "access-token", beforeUs: nil, limit: limit, me: mfMe)
}

@MainActor
private func mfWait(_ condition: @MainActor () -> Bool) async -> Bool {
    for _ in 0..<600 {
        if condition() { return true }
        try? await Task.sleep(nanoseconds: 5_000_000)
    }
    return condition()
}

/// 화면용 도메인 한 줄(네트워크 없이 스토어에 넣을 때).
private func mfItem(_ id: String, sender: String? = mfOther, name: String = "보낸이", body: String = "모두 안녕",
                    own: Bool = false, ago: TimeInterval = 60, now: Date = mfWall0, recipients: Int? = 12) -> MegaphoneFeedItem {
    MegaphoneFeedItem(megaphoneID: id, senderID: sender, senderName: name, body: body, recipients: recipients,
                      createdAt: now.addingTimeInterval(-ago), isOwn: own)
}

// MARK: - 코어

@Suite("지난 확성기 코어 — 전선 · 커서 · 중복 · 문 · 세대 · 내리기")
@MainActor
struct MegaphoneFeedCoreTests {

    // 없으면: 합성 Encodable 이 nil 키를 빼 첫 쪽이 `{"p_limit":30}` 으로 나가고 PostgREST 가 함수를 못 찾는(PGRST202) 결함,
    //        커서를 첫 줄 · 확성기 id · 밀리초로 싣는 결함이 초록.
    @Test("요청 키는 정확히 둘 — 첫 쪽 p_before_us 는 명시적 null · 다음 쪽은 마지막 줄의 created_epoch_us 그대로")
    func requestKeysAreExactAndTheCursorIsTheOldestMicros() async throws {
        let rig = mfMake("null-cursor", pageSize: 2) { rpc, _, index in
            guard rpc == "megaphone_feed" else { return nil }
            return index == 0 ? mfArray([mfRow("m2", ago: 10), mfRow("m1", ago: 20)]) : mfArray([])
        }
        await rig.store.refresh()?.value
        let first = try #require(rig.calls.first)
        #expect(Set(first.json.keys) == ["p_before_us", "p_limit"], "키 집합이 \(first.json.keys.sorted())")
        #expect(first.json["p_before_us"] is NSNull, "첫 쪽 커서가 null 이 아니다: \(first.body)")
        #expect(first.body.contains(#""p_before_us":null"#), "본문에 null 키가 없다: \(first.body)")
        #expect(first.json["p_limit"] as? Int == 2)
        #expect(rig.store.hasMore, "꽉 찬 쪽(2/2)인데 더 없다고 본다")
        await rig.store.loadMore()?.value
        let second = try #require(rig.calls.dropFirst().first)
        #expect(Set(second.json.keys) == ["p_before_us", "p_limit"])
        let oldest = mfMicros(20)
        #expect((second.json["p_before_us"] as? NSNumber)?.int64Value == oldest, "커서가 마지막 줄의 µs 가 아니다: \(second.body)")
        #expect(second.body.contains(#""p_before_us":\#(oldest)"#), "커서가 정수로 안 실렸다: \(second.body)")
        // 기준선: 첫 줄(m2)의 µs 는 다르다 — 커서를 첫 줄로 잡으면 위 단언이 빨강이다.
        #expect(mfMicros(10) != oldest)
        #expect(MegaphoneFeedRequest(pBeforeUs: nil).pLimit == 30, "계약의 쪽 크기는 30")
    }

    // 없으면: µs 를 Double 로 옮겨 2^53 위에서 끝자리가 뭉개지고 경계의 확성기를 건너뛰거나 두 번 받는 결함이 초록.
    @Test("커서는 Int64 그대로 왕복한다 — 2^53+1 도 끝자리까지")
    func cursorKeepsInt64Precision() async throws {
        let big: Int64 = 9_007_199_254_740_993
        let row = #"[{"megaphone_id":"m-big","sender_id":"\#(mfOther)","sender_display_name":"보낸이","sender_avatar_url":null,"body":"큰 수","recipients":3,"is_mine":false,"created_epoch_ms":1800000000000,"created_epoch_us":\#(big)}]"#
        let rig = mfMake("int64", pageSize: 1) { rpc, _, index in
            guard rpc == "megaphone_feed" else { return nil }
            return index == 0 ? GomokuStubProtocol.Reply(body: row) : mfArray([])
        }
        await rig.store.refresh()?.value
        #expect(rig.store.items.first?.createdEpochUs == big, "µs 가 뭉개졌다: \(String(describing: rig.store.items.first?.createdEpochUs))")
        await rig.store.loadMore()?.value
        let second = try #require(rig.calls.dropFirst().first)
        #expect(second.body.contains("\(big)"), "커서 끝자리가 바뀌었다: \(second.body)")
        // 기준선: Double 로 옮기면 끝자리가 바뀐다(이 시험이 재는 것이 실재한다).
        #expect(Int64(Double(big)) != big)
    }

    // 없으면: 스네이크 원시값 함정(운영 디코더에선 늘 nil) · 깨진 줄 하나에 쪽이 통째로 죽는 결함 · 머리말을 한 번 더 떼어
    //        사람이 '📢' 로 시작한 글이 잘리는 결함이 초록.
    @Test("운영 디코더로 읽는다 — 깨진 줄만 빠지고, 본문은 다시 떼지 않고, 내 글 · 얼굴 · 받은 수 · 시각을 옮긴다")
    func decodesWithTheProductionDecoder() async throws {
        let rows: [[String: Any]] = [
            mfRow("m4", ago: 5, body: "오늘 3시 라운지", recipients: 46, avatar: "https://example.invalid/a.jpg"),
            mfRow("m3", ago: 10, sender: mfMe, name: "나", body: "내가 보낸 말", isMine: true),
            mfRow("m2", ago: 15, name: "  ", body: "📢 둘째 확성기도 내 글이에요"),      // 이름 공백 · 사람이 쓴 📢
            mfRow("m1", ago: 20, sender: mfMe, body: "서버가 남의 글이라 말함", isMine: false),
        ]
        let broken: [Any] = [
            ["megaphone_id": 7, "body": "id 가 숫자", "created_epoch_us": 1],                              // 모양 틀림
            ["megaphone_id": "x1", "sender_id": mfOther, "body": "커서 없음", "created_epoch_ms": 1],        // µs 없음
            ["megaphone_id": "x2", "sender_id": mfOther, "body": "   ", "created_epoch_us": 5_000],          // 보이는 글 없음
        ]
        let page = try await mfFetch("production", body: mfJSON(rows + broken), limit: 7)
        #expect(page.items.map(\.megaphoneID) == ["m4", "m3", "m2", "m1"], "\(page.items.map(\.megaphoneID))")
        #expect(page.hasMore, "전선 7줄 = 요청 7줄인데 깨진 줄 때문에 끝으로 봤다")
        let items = page.items
        #expect(items[0].body == "오늘 3시 라운지")
        #expect(items[0].senderID == mfOther && items[0].senderName == "보낸이" && !items[0].isOwn)
        #expect(items[0].senderAvatarURL?.absoluteString == "https://example.invalid/a.jpg")
        #expect(items[0].recipients == 46)
        #expect(items[0].createdEpochUs == mfMicros(5))
        #expect(abs(items[0].createdAt.timeIntervalSince(mfWall0.addingTimeInterval(-5))) < 0.002, "밀리초 시각을 못 옮겼다")
        #expect(items[1].isOwn, "is_mine:true 인데 내 글이 아니다")
        #expect(items[2].body == "📢 둘째 확성기도 내 글이에요", "서버가 뗀 본문을 한 번 더 뗐다: \(items[2].body)")
        #expect(items[2].senderName == MegaphoneBanner.fallbackSenderName)
        #expect(items[3].isOwn == false, "서버의 is_mine:false 를 내 id 비교가 덮었다")

        // 기준선: 평범한 JSONDecoder(스네이크 변환 없음)는 줄을 하나도 못 세운다 — 이 시험이 운영 디코더를 잰다는 증거.
        let plain = try JSONDecoder().decode(MegaphoneFeedResponse.self, from: Data(mfJSON(rows).utf8))
        #expect(plain.page(limit: 30, me: mfMe).items.isEmpty, "평범한 디코더로도 읽힌다 — 이 시험이 운영 디코더를 재는지 알 수 없다")
        // 머리말 없는 글에 떼기를 해도 무해하다(배너 규칙) — 그래도 피드는 떼지 않는다.
        #expect(MegaphoneBanner.displayBody("오늘 3시 라운지") == "오늘 3시 라운지")
        // 전선이 모자라면 끝이다.
        #expect(try await mfFetch("short", body: mfJSON(rows), limit: 5).hasMore == false)
    }

    // 없으면: 겹친 줄을 두 번 · 빈 쪽 뒤에도 [더 보기]가 남아 같은 쪽을 끝없이 다시 묻는 결함이 초록.
    @Test("더 보기: 겹친 줄은 한 번만 · 겹쳐 눌러도 한 건 · 빈 쪽이면 끝")
    func pagingDedupesAndEnds() async throws {
        let rig = mfMake("paging", pageSize: 3) { rpc, _, index in
            guard rpc == "megaphone_feed" else { return nil }
            switch index {
            case 0: return mfArray([mfRow("m5", ago: 5), mfRow("m4", ago: 10), mfRow("m3", ago: 15)])
            case 1: return mfArray([mfRow("m3", ago: 15), mfRow("m2", ago: 20), mfRow("m1", ago: 25)])
            default: return mfArray([])
            }
        }
        await rig.store.refresh()?.value
        #expect(mfIDs(rig.store) == ["m5", "m4", "m3"] && rig.store.hasMore)
        let first = rig.store.loadMore()
        #expect(rig.store.loadMore() == nil, "더 보기가 겹쳐 나갔다")
        await first?.value
        #expect(rig.calls.count == 2)
        #expect((rig.calls[1].json["p_before_us"] as? NSNumber)?.int64Value == mfMicros(15))
        #expect(mfIDs(rig.store) == ["m5", "m4", "m3", "m2", "m1"], "겹친 줄이 두 번 섰다: \(mfIDs(rig.store))")
        #expect(rig.store.hasMore, "새 줄 둘 + 꽉 찬 전선이면 더 있을 수 있다")
        await rig.store.loadMore()?.value
        #expect((rig.calls[2].json["p_before_us"] as? NSNumber)?.int64Value == mfMicros(25))
        #expect(rig.store.hasMore == false, "빈 쪽 뒤에도 더 있다고 본다")
        #expect(rig.store.loadMore() == nil)
        #expect(rig.calls.count == 3)
    }

    // 없으면: 404 를 영구히 기억해 서버가 올라온 뒤에도 문이 안 서거나, 다시 세우려고 작성기를 열 때마다 묻는 결함이 초록.
    @Test("함수 없음(404) → 닫힘 · rearm 은 요청 없이 모름으로 · 다음 열기에서 열린다")
    func missingFunctionClosesTheDoorAndRearmReopens() async {
        let rig = mfMake("door") { rpc, _, index in
            guard rpc == "megaphone_feed" else { return nil }
            return index == 0 ? mfMissing : mfArray([mfRow("m1")])
        }
        #expect(rig.store.isAvailable == nil)
        await rig.store.open()?.value
        #expect(rig.store.isAvailable == false, "404 를 닫힘으로 안 접었다")
        #expect(rig.store.items.isEmpty && rig.store.loadFailed == false, "닫힘을 연결 실패로 봤다")
        rig.store.rearm()
        #expect(rig.store.isAvailable == nil, "닫힘을 영구히 기억했다")
        #expect(rig.calls.count == 1, "rearm 이 요청을 냈다")
        await rig.store.open()?.value
        #expect(rig.store.isAvailable == true && mfIDs(rig.store) == ["m1"])
        rig.store.rearm()
        #expect(rig.store.isAvailable == true, "열림을 rearm 이 지웠다")
        #expect(rig.calls.count == 2)
    }

    @Test("연결 실패는 문을 안 건드린다 · 더 보기의 404 는 문을 닫는다")
    func transportFailureKeepsTheDoorButMissingFunctionShutsIt() async {
        let flaky = mfMake("flaky") { rpc, _, _ in
            rpc == "megaphone_feed" ? GomokuStubProtocol.Reply(status: 503, body: #"{"message":"busy"}"#) : nil
        }
        await flaky.store.refresh()?.value
        #expect(flaky.store.isAvailable == nil, "연결 실패를 문 닫힘으로 봤다")
        #expect(flaky.store.loadFailed && !flaky.store.isLoading)

        let later = mfMake("missing-later", pageSize: 1) { rpc, _, index in
            guard rpc == "megaphone_feed" else { return nil }
            return index == 0 ? mfArray([mfRow("m1")]) : mfMissing
        }
        await later.store.refresh()?.value
        #expect(later.store.isAvailable == true && later.store.hasMore)
        await later.store.loadMore()?.value
        #expect(later.store.isAvailable == false && later.store.items.isEmpty && !later.store.loadMoreFailed)
    }

    // 없으면: 로그아웃 · 계정 전환 뒤 앞 계정의 응답이 다음 계정의 목록('내가 보낸' 포함)을 채우는 결함이 초록.
    @Test("세대 가드: 요청이 날아가는 사이 reset · 계정 전환이 오면 그 응답은 버린다")
    func resetAndAccountSwitchDiscardInFlightResponses() async {
        // 첫 응답(기준선)은 곧바로, 그 뒤는 0.3초 늦게 — 요청이 전선에 오른 **뒤에** 세대를 바꾼다(기록된 호출 수로 기다린다).
        let rig = mfMake("generation") { rpc, _, index in
            guard rpc == "megaphone_feed" else { return nil }
            return GomokuStubProtocol.Reply(body: mfJSON([mfRow("m1", sender: mfMe, isMine: true)]), delay: index == 0 ? 0 : 0.3)
        }
        await rig.store.refresh()?.value
        #expect(mfIDs(rig.store) == ["m1"] && rig.store.items[0].isOwn)
        rig.store.reset()
        #expect(rig.store.items.isEmpty && rig.store.isAvailable == nil && !rig.store.hasLoaded)

        let inFlight = rig.store.refresh()
        _ = await mfWait { rig.calls.count == 2 }
        rig.store.reset()
        await inFlight?.value
        #expect(rig.store.items.isEmpty, "reset 뒤 도착한 응답이 목록을 채웠다")
        #expect(rig.store.isAvailable == nil && !rig.store.isLoading)

        let other = rig.store.refresh()
        _ = await mfWait { rig.calls.count == 3 }
        rig.owner.switchAccount(to: mfThird)
        await other?.value
        #expect(rig.store.items.isEmpty, "계정 전환 뒤 앞 계정의 응답이 목록을 채웠다")
        // 요청이 나가기 **전에** 계정이 바뀌어도 앞 계정의 새로고침은 돌지 않는다(부르는 순간의 세대).
        let before = rig.calls.count
        let early = rig.store.refresh()
        rig.owner.switchAccount(to: mfOther)
        await early?.value
        #expect(rig.calls.count == before && rig.store.items.isEmpty, "바뀐 계정 이름으로 앞 계정의 새로고침이 나갔다")
    }

    // 없으면: 실시간 새로고침이 더 보기로 받아 둔 꼬리를 날려 읽던 자리가 사라지는 결함이 초록.
    // 페이지가 **떠 있는 동안의** 새로고침(`refresh` — 실시간 신호의 길)만 잰다. 페이지를 새로 여는 길(`open`)은 아래 시험이 잰다.
    @Test("떠 있는 동안의 새로고침은 새 머리를 얹고 더 보기로 받은 꼬리를 지킨다 · 겹치지 않으면 갈아 끼운다")
    func refreshKeepsTheLoadedTail() async {
        let rig = mfMake("tail", pageSize: 2) { rpc, _, index in
            guard rpc == "megaphone_feed" else { return nil }
            switch index {
            case 0: return mfArray([mfRow("m4", ago: 40), mfRow("m3", ago: 50)])
            case 1: return mfArray([mfRow("m2", ago: 60), mfRow("m1", ago: 70)])
            case 2: return mfArray([mfRow("m5", ago: 30), mfRow("m4", ago: 40)])
            default: return mfArray([mfRow("m9", ago: 1), mfRow("m8", ago: 2)])
            }
        }
        await rig.store.refresh()?.value
        await rig.store.loadMore()?.value
        #expect(mfIDs(rig.store) == ["m4", "m3", "m2", "m1"])
        await rig.store.refresh()?.value
        #expect(mfIDs(rig.store) == ["m5", "m4", "m3", "m2", "m1"], "새로고침이 꼬리를 날렸다: \(mfIDs(rig.store))")
        #expect(rig.store.hasMore, "꼬리를 지켰으면 꼬리의 '더 있음'도 지켜야 한다")
        await rig.store.refresh()?.value
        #expect(mfIDs(rig.store) == ["m9", "m8"])
    }

    // 없으면: 더 보기로 받은 꼬리가 앱이 도는 내내 다시 안 물어져, 운영자가 내린 글 · 내가 폰에서(또는 상대가) 차단한 사람의 글이
    // 페이지를 다시 열어도 계속 보이는 결함이 초록(검토 #1).
    @Test("페이지를 다시 열면 첫 쪽으로 갈아 끼운다 — 서버가 뺀 꼬리 줄(운영자가 내림 · 차단)이 남지 않는다")
    func reopenReplacesTheLoadedTail() async {
        let rig = mfMake("reopen", pageSize: 2) { rpc, _, index in
            guard rpc == "megaphone_feed" else { return nil }
            switch index {
            case 0: return mfArray([mfRow("m4", ago: 40), mfRow("m3", ago: 50)])
            case 1: return mfArray([mfRow("m2", ago: 60), mfRow("m1", ago: 70)])
            // 다시 연 첫 쪽은 같다 — 그 사이 꼬리의 m2 를 운영자가 내렸다(서버가 뺀다).
            case 2: return mfArray([mfRow("m4", ago: 40), mfRow("m3", ago: 50)])
            case 3: return mfArray([mfRow("m1", ago: 70)])
            // 실패한 열기 뒤의 새로고침도 갈아 끼운다(표시는 반영하는 순간 쓴다).
            case 4: return GomokuStubProtocol.Reply(status: 503, body: #"{"message":"busy"}"#)
            default: return mfArray([mfRow("m4", ago: 40), mfRow("m3", ago: 50)])
            }
        }
        await rig.store.open()?.value
        await rig.store.loadMore()?.value
        #expect(mfIDs(rig.store) == ["m4", "m3", "m2", "m1"])
        rig.store.close()
        await rig.store.open()?.value
        #expect(mfIDs(rig.store) == ["m4", "m3"], "다시 연 페이지가 옛 꼬리를 살렸다: \(mfIDs(rig.store))")
        #expect(rig.store.hasMore, "꽉 찬 첫 쪽이면 더 있다")
        await rig.store.loadMore()?.value
        #expect(mfIDs(rig.store) == ["m4", "m3", "m1"], "서버가 뺀 줄이 남았다: \(mfIDs(rig.store))")
        #expect((rig.calls[3].json["p_before_us"] as? NSNumber)?.int64Value == mfMicros(50), "다시 받은 꼬리의 커서가 첫 쪽 끝이 아니다")

        rig.store.close()
        await rig.store.open()?.value
        #expect(rig.store.loadFailed && mfIDs(rig.store) == ["m4", "m3", "m1"], "실패한 열기가 목록을 지웠다")
        await rig.store.refresh()?.value
        #expect(mfIDs(rig.store) == ["m4", "m3"], "실패한 열기 뒤의 첫 쪽이 옛 꼬리를 살렸다: \(mfIDs(rig.store))")
        #expect(rig.calls.count == 6)
    }

    // 없으면: 팝오버가 닫혀 숨은 페이지가 남의 확성기마다 묻거나, 다시 열어도 놓친 확성기가 안 보이는 결함이 초록(검토 #2).
    @Test("놓친 신호: 열린 페이지에서만 표시가 서고 · 다시 보일 때 한 번만 읽고 · 닫기 · reset 은 표시를 지운다")
    func missedSignalRefreshesOnceOnReturn() async {
        let rig = mfMake("missed") { rpc, _, _ in rpc == "megaphone_feed" ? mfArray([mfRow("m1")]) : nil }
        rig.store.noteMissedSignal()
        #expect(!rig.store.missedSignal, "닫힌 페이지에 표시가 섰다")
        #expect(rig.store.refreshIfMissedSignal() == nil)
        await rig.store.open()?.value
        #expect(rig.calls.count == 1)
        rig.store.noteMissedSignal()
        #expect(rig.store.missedSignal)
        #expect(rig.calls.count == 1, "표시만 남겨야 하는데 물었다")
        await rig.store.refreshIfMissedSignal()?.value
        #expect(rig.calls.count == 2 && !rig.store.missedSignal)
        #expect(rig.store.refreshIfMissedSignal() == nil, "놓친 신호 하나에 두 번 읽었다")
        rig.store.noteMissedSignal()
        rig.store.close()
        #expect(!rig.store.missedSignal, "닫은 페이지의 표시가 남았다")
        await rig.store.open()?.value
        rig.store.noteMissedSignal()
        rig.store.reset()
        #expect(!rig.store.missedSignal)
        #expect(rig.calls.count == 3)
    }

    @Test("더 보기 응답은 그 사이 꼬리가 바뀌었으면 버린다(엉뚱한 자리에 안 붙인다)")
    func loadMoreDropsWhenTheTailChanged() async {
        let rig = mfMake("stale-more", pageSize: 2) { rpc, _, index in
            guard rpc == "megaphone_feed" else { return nil }
            return index == 0 ? mfArray([mfRow("m4", ago: 40), mfRow("m3", ago: 50)])
                : mfArray([mfRow("m2", ago: 60), mfRow("m1", ago: 70)])
        }
        await rig.store.refresh()?.value
        let more = rig.store.loadMore()
        // 더 보기가 날아가는 사이 새로고침이 목록을 갈았다(안 겹치는 새 머리).
        rig.store.applyFirstPage(MegaphoneFeedPage(items: [mfItem("m9", ago: 1), mfItem("m8", ago: 2)], hasMore: true))
        await more?.value
        #expect(mfIDs(rig.store) == ["m9", "m8"], "바뀐 꼬리 뒤에 옛 커서의 쪽을 붙였다: \(mfIDs(rig.store))")
        #expect(rig.store.isLoadingMore == false)
    }

    // 없으면: 내리기 키가 틀려(PGRST202) 운영자가 눌러도 아무 일이 없거나, 거절된 글이 목록에서 사라지는 결함이 초록.
    @Test("운영자 내리기: 키는 정확히 p_id · p_hidden(true) · ok/not_found 만 줄을 뺀다 · 겹쳐 누르면 한 건")
    func adminHideSendsExactKeysAndRemovesOnlyOnSuccess() async throws {
        let rig = mfMake("hide", pageSize: 30) { rpc, _, index in
            switch rpc {
            case "megaphone_feed":
                return mfArray([mfRow("m4", ago: 5), mfRow("m3", ago: 10), mfRow("m2", ago: 15), mfRow("m1", ago: 20)])
            case "megaphone_admin_hide":
                switch index {
                case 0: return GomokuStubProtocol.Reply(body: #"{"status":"ok","hidden":true}"#)
                case 1: return GomokuStubProtocol.Reply(body: #"{"status":"forbidden"}"#)
                case 2: return GomokuStubProtocol.Reply(body: #"{"status":"not_found"}"#)
                default: return GomokuStubProtocol.Reply(status: 500, body: "{}")
                }
            default: return nil
            }
        }
        await rig.store.refresh()?.value
        let first = rig.store.adminHide(megaphoneID: "m1")
        #expect(rig.store.adminHide(megaphoneID: "m2") == nil, "내리기가 겹쳐 나갔다")
        await first?.value
        let call = try #require(rig.hideCalls.first)
        #expect(Set(call.json.keys) == ["p_id", "p_hidden"], "키 집합이 \(call.json.keys.sorted())")
        #expect(call.json["p_id"] as? String == "m1" && call.body.contains(#""p_hidden":true"#), "\(call.body)")
        #expect(mfIDs(rig.store) == ["m4", "m3", "m2"])
        #expect(rig.store.notice == MegaphoneFeedNotice(text: MegaphoneFeedText.adminHidden, isError: false))

        await rig.store.adminHide(megaphoneID: "m2")?.value
        #expect(mfIDs(rig.store) == ["m4", "m3", "m2"], "운영자가 아닌데 목록에서 뺐다")
        #expect(rig.store.notice == MegaphoneFeedNotice(text: MegaphoneFeedText.adminForbidden, isError: true))

        await rig.store.adminHide(megaphoneID: "m2")?.value
        #expect(mfIDs(rig.store) == ["m4", "m3"], "이미 없는 글(not_found)을 남겼다")

        await rig.store.adminHide(megaphoneID: "m3")?.value
        #expect(mfIDs(rig.store) == ["m4", "m3"], "실패했는데 뺐다")
        #expect(rig.store.notice?.isError == true && rig.store.hidingID == nil)
        // 목록에 없는 글은 묻지 않는다.
        #expect(rig.store.adminHide(megaphoneID: "nope") == nil)
        #expect(rig.hideCalls.count == 4)
    }

    @Test("문구: 숫자는 상수에서 · 시각은 메시지 구분선과 같은 말 · 앱 안 말에 내부 낱말 없음")
    func copyDerivesFromConstants() {
        let days = MegaphoneFeedRules.windowDays
        #expect(days == 30 && MegaphoneFeedRules.pageSize == 30 && MegaphoneFeedRules.collapsedLineLimit == 3)
        #expect(MegaphoneFeedText.windowNote == "최근 \(days)일")
        #expect(MegaphoneFeedText.empty.contains("\(days)일"))
        #expect(MegaphoneFeedText.title == "지난 확성기")
        #expect(MegaphoneFeedText.entryLink == "지난 확성기 ›")
        #expect(MegaphoneFeedText.loadMore == "이전 확성기 더 보기")
        #expect(MegaphoneFeedText.ownBadge == "내가 보낸")
        #expect(MegaphoneFeedText.adminHideAction == "내리기")
        #expect(MegaphoneFeedText.recipients(46) == "46명에게")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let now = Date(timeIntervalSince1970: 1_793_000_000)   // 2026-10-26 16:33 KST
        #expect(MegaphoneFeedText.timeLabel(now.addingTimeInterval(-60), now: now, calendar: calendar) == "오늘 16:32")
        #expect(MegaphoneFeedText.timeLabel(now.addingTimeInterval(-86_400), now: now, calendar: calendar) == "어제 16:33")
        #expect(MegaphoneFeedText.timeLabel(now.addingTimeInterval(-20 * 86_400), now: now, calendar: calendar) == "10월 6일 16:33")
        let forbidden = ["서버", "RPC", "토큰", "테스트", "피드", "API", "404", "관리자"]
        for text in [MegaphoneFeedText.title, MegaphoneFeedText.windowNote, MegaphoneFeedText.empty, MegaphoneFeedText.loading,
                     MegaphoneFeedText.failed, MegaphoneFeedText.unavailable, MegaphoneFeedText.loadMore,
                     MegaphoneFeedText.loadMoreFailed, MegaphoneFeedText.ownBadge, MegaphoneFeedText.adminHideAction,
                     MegaphoneFeedText.adminHidden, MegaphoneFeedText.adminForbidden, MegaphoneFeedText.adminHideFailed] {
            for word in forbidden { #expect(!text.contains(word), "\(text) 에 \(word)") }
        }
    }
}

// MARK: - 맥 배선

@MainActor
private func mfMacStore(_ label: String, function: String = #function,
                        handler: @escaping GomokuStubProtocol.Handler) -> (WorkTimerStore, String) {
    let host = "mf-mac-\(label)-\(UUID().uuidString.prefix(8))".lowercased()
    GomokuStubProtocol.register(host: host, handler: handler)
    let service = SupabaseWorkService(projectURL: URL(string: "http://\(host)")!, anonKey: "anon-test-key",
                                      session: GomokuStubProtocol.session())
    let store = WorkTimerStore(service: service,
                               environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
                               defaults: CheckTestScratch.defaults("mf-" + label, function: function))
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: mfMe)
    store.characterDefaults = CheckTestScratch.defaults("mf-character-" + label, function: function)
    return (store, host)
}

private let mfInfoJSON = #"{"status":"ok","enabled":true,"price":30,"cooldown_seconds":600,"cooldown_remaining_seconds":0,"recipients":46,"max_length":198,"ruby_balance":120}"#

private func mfCount(_ host: String) -> Int { GomokuStubProtocol.count(host: host, rpc: "megaphone_feed") }

/// 작성기를 열고(확성기 값 읽기까지) 기다린다.
@MainActor
private func mfOpenComposer(_ store: WorkTimerStore) async {
    store.isShopPanelVisible = true
    if !store.megaphone.isComposerOpen { store.toggleMegaphoneComposer() }
    _ = await mfWait { !store.megaphone.infoLoading }
}

/// 페이지를 열고 첫 쪽이 다 돌 때까지 기다린다.
@MainActor
private func mfOpenPage(_ store: WorkTimerStore) async {
    store.openMegaphoneFeed()
    _ = await mfWait { !store.megaphoneFeed.isLoading }
}

@Suite("지난 확성기 맥 배선 — 문 · 부르는 자리 · 차단 · 신고 · 내리기 · 로그아웃")
@MainActor
struct MegaphoneFeedMacTests {

    // 없으면: 작성기를 열 때마다 30일 목록을 묻거나, 404 뒤에도 문이 서 있거나, 한 번 닫힌 문이 다시 안 서는 결함이 초록.
    @Test("작성기 열기는 0건 · 모를 때 문이 선다 · 페이지의 404 → 문이 숨고 다음 작성기 열기에서 요청 없이 다시 선다")
    func composerSendsNothingAndTheLinkFollowsTheDoor() async {
        let (store, host) = mfMacStore("door") { rpc, _, index in
            switch rpc {
            case "megaphone_info": return GomokuStubProtocol.Reply(body: mfInfoJSON)
            case "megaphone_feed": return index == 0 ? mfMissing : mfArray([mfRow("m1")])
            default: return nil
            }
        }
        #expect(store.showsMegaphoneFeedEntry, "모를 때 문이 숨었다 — 누를 길이 없다")
        await mfOpenComposer(store)
        try? await Task.sleep(for: .milliseconds(30))
        #expect(mfCount(host) == 0, "작성기를 열었는데 지난 확성기를 물었다")
        await mfOpenPage(store)
        #expect(mfCount(host) == 1 && store.isMegaphoneFeedShowing)
        #expect(store.megaphoneFeed.isAvailable == false && store.showsMegaphoneFeedEntry == false, "404 인데 문이 섰다")
        store.closeMegaphoneFeed()
        store.openMegaphoneFeed()
        #expect(!store.isMegaphoneFeedShowing && mfCount(host) == 1, "숨은 문으로 페이지가 열렸다")
        // 다음 자연스러운 진입: 작성기를 접었다 다시 연다 — 요청 없이 문이 다시 선다.
        store.toggleMegaphoneComposer()
        await mfOpenComposer(store)
        #expect(store.showsMegaphoneFeedEntry, "닫힘을 영구히 기억했다")
        #expect(mfCount(host) == 1, "문을 다시 세우려고 물었다")
        await mfOpenPage(store)
        #expect(mfCount(host) == 2 && store.megaphoneFeed.items.map(\.megaphoneID) == ["m1"])
        // [뒤로]는 작성기가 열린 상점으로 — 쓰던 글이 그대로다.
        store.closeMegaphoneFeed()
        #expect(!store.isMegaphoneFeedShowing && store.megaphone.isComposerOpen && store.isShopPanelVisible)
    }

    // 없으면: 팝오버를 열 때마다 · 상점을 열 때마다 30일 목록을 받아 요청이 늘고 기존 시험의 셈이 흔들리는 결함이 초록.
    @Test("팝오버 열기 · 상점 열기는 0건 · 작성기 없이 openMegaphoneFeed 는 안 연다")
    func noAutomaticCallsOutsideThePage() async {
        let (store, host) = mfMacStore("no-auto") { rpc, _, _ in
            rpc == "megaphone_info" ? GomokuStubProtocol.Reply(body: mfInfoJSON) : nil
        }
        store.setMenuPresented(true)
        try? await Task.sleep(for: .milliseconds(80))
        store.setMenuPresented(false)
        store.toggleShopPanel()
        _ = await mfWait { !store.megaphone.infoLoading && !store.shopLoading }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(mfCount(host) == 0, "페이지를 안 열었는데 지난 확성기를 물었다")
        store.openMegaphoneFeed()
        #expect(!store.isMegaphoneFeedShowing && !store.megaphoneFeed.isOpen, "작성기가 없는데 페이지가 열렸다")
        #expect(mfCount(host) == 0)
    }

    @Test("실시간 'megaphone' 신호는 페이지가 떠 있을 때만 지난 확성기를 다시 읽는다", .gomokuDefaultsCleanup)
    func realtimeSignalRefreshesOnlyWhileShowing() async {
        let transport = FakeRealtimeTransport()
        let (store, host) = makeMessageReadStore("megafeed-rt", transport: transport) { call, _ in
            switch call.rpc {
            case "megaphone_info": return MessageReadStubProtocol.Reply(body: mfInfoJSON)
            case "megaphone_feed": return MessageReadStubProtocol.Reply(body: mfJSON([mfRow("m1")]))
            default: return nil
            }
        }
        func feed() -> Int { MessageReadStubProtocol.count(host: host, rpc: "megaphone_feed") }
        func inbox() -> Int { MessageReadStubProtocol.count(host: host, rpc: "megaphone_inbox") }
        store.startRealtimeIfPossible()
        transport.emit(.joined)
        await messageReadWait { messageReadIdle(store) }
        // ① 페이지가 안 떠 있다 — 배너 목록만 받는다.
        let inbox0 = inbox()
        transport.emit(.broadcast(event: "megaphone"))
        await messageReadWait { inbox() > inbox0 }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(inbox() == inbox0 + 1, "기준선: 신호가 배너 목록을 안 받았다")
        #expect(feed() == 0, "페이지가 안 떠 있는데 지난 확성기를 읽었다")
        // ② 팝오버를 연 채 페이지를 연다(작성기 열기 0 + 페이지 열기 1). 팝오버 열기의 부수 호출을 피하려고 깃발만 세운다.
        store.isMenuPresented = true
        store.isShopPanelVisible = true
        store.toggleMegaphoneComposer()
        store.openMegaphoneFeed()
        await messageReadWait { feed() >= 1 && !store.megaphoneFeed.isLoading }
        #expect(store.isMegaphoneFeedShowing && feed() == 1)
        transport.emit(.broadcast(event: "megaphone"))
        await messageReadWait { feed() > 1 && !store.megaphoneFeed.isLoading }
        #expect(feed() == 2, "페이지가 떠 있는데 신호가 목록을 다시 안 읽었다")
        // ③ 팝오버만 닫는다(패널은 제자리) — 신호는 0건, 다시 열 때 한 번, 놓친 신호가 없으면 다시 열어도 0건(검토 #2).
        store.setMenuPresented(false)
        #expect(store.isMegaphoneFeedShowing, "기준선: 팝오버를 닫아도 페이지는 제자리다")
        let inboxHidden = inbox()
        transport.emit(.broadcast(event: "megaphone"))
        transport.emit(.broadcast(event: "megaphone"))
        await messageReadWait { inbox() > inboxHidden }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(feed() == 2, "팝오버가 닫혀 숨은 페이지가 신호마다 물었다")
        store.setMenuPresented(true)
        await messageReadWait { feed() > 2 && !store.megaphoneFeed.isLoading }
        #expect(feed() == 3, "놓친 신호 둘을 다시 열 때 한 번으로 안 읽었다")
        store.setMenuPresented(false)
        store.setMenuPresented(true)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(feed() == 3, "놓친 신호가 없는데 팝오버 열기가 물었다")
        // ④ 페이지를 닫으면 다시 0건.
        store.closeMegaphoneFeed()
        let inbox1 = inbox()
        transport.emit(.broadcast(event: "megaphone"))
        await messageReadWait { inbox() > inbox1 }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(feed() == 3, "페이지를 닫았는데 신호가 목록을 읽었다")
    }

    // 없으면: 받아 둔 줄이 전부 방금 차단한 사람 글일 때 페이지가 "울린 확성기가 없어요"라고 말하고 더 볼 길도 없는 결함이 초록(검토 #3).
    @Test("이 페이지에서 건 차단이 서버에 닿으면 첫 쪽을 다시 읽어 다른 사람의 글로 찬다 · 다른 자리의 차단은 안 읽는다")
    func blockFromTheFeedRefillsThePage() async throws {
        let (store, host) = mfMacStore("block-refill") { rpc, _, index in
            switch rpc {
            case "megaphone_info": return GomokuStubProtocol.Reply(body: mfInfoJSON)
            case "megaphone_feed":
                // 첫 쪽은 한 사람이 다 채웠다 · 차단 뒤의 첫 쪽은 서버가 그 사이를 뺐다.
                return index == 0
                    ? mfArray([mfRow("m4", ago: 10, sender: mfOther), mfRow("m3", ago: 20, sender: mfOther)])
                    : mfArray([mfRow("m2", ago: 30, sender: mfThird), mfRow("m1", ago: 40, sender: mfThird)])
            default: return nil
            }
        }
        store.megaphoneFeed.pageSize = 2
        store.isMenuPresented = true
        await mfOpenComposer(store)
        await mfOpenPage(store)
        #expect(store.visibleMegaphoneFeed.map(\.megaphoneID) == ["m4", "m3"] && store.megaphoneFeed.hasMore)
        let target = try #require(MegaphoneFeedSafetyRule.blockTarget(for: store.megaphoneFeed.items[0], me: mfMe))
        store.openBlockConfirm(target, surface: .megaphoneFeed)
        store.confirmBlockFromSheet()
        #expect(store.visibleMegaphoneFeed.isEmpty, "기준선: 차단한 사람의 글이 곧바로 빠진다")
        _ = await mfWait { store.blockingPeerID == nil && mfCount(host) == 2 && !store.megaphoneFeed.isLoading }
        #expect(GomokuStubProtocol.count(host: host, rpc: "block_user") == 1)
        #expect(mfCount(host) == 2, "차단이 닿았는데 지난 확성기를 다시 안 읽었다")
        #expect(store.visibleMegaphoneFeed.map(\.megaphoneID) == ["m2", "m1"], "빈 목록이 남았다: \(store.visibleMegaphoneFeed.map(\.megaphoneID))")

        // 다른 자리(대화)에서 건 차단은 이 목록을 안 읽는다.
        store.openBlockConfirm(BlockReportTarget(peerID: mfThird, peerName: "도윤"), surface: .message)
        store.confirmBlockFromSheet()
        _ = await mfWait { store.blockingPeerID == nil }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(GomokuStubProtocol.count(host: host, rpc: "block_user") == 2)
        #expect(mfCount(host) == 2, "다른 자리의 차단이 지난 확성기를 읽었다")
    }

    // 없으면: 차단한 사람의 글이 서버 응답을 기다리는 동안 남거나, 메시지 id 를 지어내 신고가 엉뚱한 줄을 가리키는 결함이 초록.
    @Test("차단하면 그 사람의 글이 곧바로 빠진다 · 신고는 보낸 사람 신고(메시지 id 없음) · 내 글엔 ··· 가 없다 · 시트는 이 자리에만")
    func blockHidesImmediatelyAndReportIsAPersonReport() async throws {
        let (store, _) = mfMacStore("safety") { _, _, _ in nil }
        store.megaphoneFeed.applyFirstPage(MegaphoneFeedPage(items: [
            mfItem("m3", sender: mfOther, name: "소라", body: "라운지에 간식"),
            mfItem("m2", sender: mfMe, name: "나", body: "내가 보낸 말", own: true),
            mfItem("m1", sender: mfThird, name: "도윤", body: "집중 중에 온 말"),
        ], hasMore: false))
        #expect(store.visibleMegaphoneFeed.map(\.megaphoneID) == ["m3", "m2", "m1"])
        let items = store.megaphoneFeed.items
        #expect(MegaphoneFeedSafetyRule.actions(for: items[0], me: mfMe, isAdmin: false) == [.report, .block])
        #expect(MegaphoneFeedSafetyRule.actions(for: items[1], me: mfMe, isAdmin: false).isEmpty, "내 글에 ··· 가 섰다")
        // 서버가 is_mine 을 잘못 말해도 내 id 면 신고·차단이 없다.
        #expect(MegaphoneFeedSafetyRule.actions(for: mfItem("x", sender: mfMe), me: mfMe, isAdmin: false).isEmpty)
        // 운영자: 남의 글엔 셋, 내 글엔 내리기만.
        #expect(MegaphoneFeedSafetyRule.actions(for: items[0], me: mfMe, isAdmin: true) == [.report, .block, .adminHide])
        #expect(MegaphoneFeedSafetyRule.actions(for: items[1], me: mfMe, isAdmin: true) == [.adminHide])
        let report = try #require(MegaphoneFeedSafetyRule.reportTarget(for: items[0], me: mfMe))
        #expect(report.peerID == mfOther && report.peerName == "소라")
        #expect(report.messageID == nil, "줄에 없는 메시지 id 를 지어냈다")
        #expect(report.messageBody == nil, "서버로 안 가는 본문을 신고하는 것처럼 보인다")
        #expect(MegaphoneFeedSafetyRule.reportTarget(for: items[1], me: mfMe) == nil)

        store.openReport(report, surface: .megaphoneFeed)
        #expect(store.blockReportSheet(on: .megaphoneFeed)?.kind == .report)
        #expect(store.blockReportSheet(on: .message) == nil, "피드에서 연 시트가 대화 자리에 선다")
        store.closeMegaphoneFeed()
        #expect(store.blockReportSheet(on: .megaphoneFeed) == nil, "페이지를 떠났는데 시트가 남았다")

        let block = try #require(MegaphoneFeedSafetyRule.blockTarget(for: items[2], me: mfMe))
        store.openBlockConfirm(block, surface: .megaphoneFeed)
        store.confirmBlockFromSheet()
        // 서버 응답을 기다리지 않는다 — 같은 순간에 빠진다.
        #expect(store.visibleMegaphoneFeed.map(\.megaphoneID) == ["m3", "m2"], "차단한 사람의 글이 남았다")
        #expect(store.megaphoneFeed.items.count == 3, "원본 목록을 고쳤다 — 차단이 실패하면 되돌릴 수 없다")
    }

    // 없으면: 운영자가 아닌 사람의 ··· 에 [내리기]가 서서 누를 때마다 forbidden 왕복이 나가는 결함이 초록.
    @Test("내리기는 운영자 깃발이 있을 때만 나간다 · 성공하면 그 줄이 빠지고 결과 한 줄이 선다")
    func adminHideIsGatedByTheAdminFlag() async throws {
        let (store, host) = mfMacStore("admin") { rpc, _, _ in
            switch rpc {
            case "megaphone_info": return GomokuStubProtocol.Reply(body: mfInfoJSON)
            case "megaphone_feed": return mfArray([mfRow("m2", ago: 10), mfRow("m1", ago: 20)])
            case "megaphone_admin_hide": return GomokuStubProtocol.Reply(body: #"{"status":"ok","hidden":true}"#)
            default: return nil
            }
        }
        await mfOpenComposer(store)
        await mfOpenPage(store)
        let target = try #require(store.megaphoneFeed.items.last)
        #expect(store.canHideMegaphonePosts == false)
        #expect(store.hideMegaphonePost(target) == nil, "운영자가 아닌데 내리기가 나갔다")
        #expect(GomokuStubProtocol.count(host: host, rpc: "megaphone_admin_hide") == 0)
        store.ultraUnlimited = true
        await store.hideMegaphonePost(target)?.value
        #expect(GomokuStubProtocol.count(host: host, rpc: "megaphone_admin_hide") == 1)
        #expect(store.visibleMegaphoneFeed.map(\.megaphoneID) == ["m2"])
        #expect(store.megaphoneFeedNotice?.text == MegaphoneFeedText.adminHidden)
        // 페이지를 떠나면 결과 한 줄도 걷힌다.
        store.closeMegaphoneFeed()
        #expect(store.megaphoneFeedNotice == nil)
    }

    @Test("로그아웃은 목록 · 문 · 열림을 비운다(다음 사람이 앞 사람의 '내가 보낸' 글을 안 본다)")
    func signOutResetsTheFeed() async {
        let (store, host) = mfMacStore("signout") { rpc, _, _ in
            switch rpc {
            case "megaphone_info": return GomokuStubProtocol.Reply(body: mfInfoJSON)
            case "megaphone_feed": return mfArray([mfRow("m1", sender: mfMe, isMine: true)])
            default: return nil
            }
        }
        await mfOpenComposer(store)
        await mfOpenPage(store)
        #expect(mfCount(host) == 1)
        #expect(store.megaphoneFeed.items.first?.isOwn == true && store.isMegaphoneFeedShowing)
        store.signOut()
        #expect(store.megaphoneFeed.items.isEmpty)
        #expect(store.megaphoneFeed.isAvailable == nil && !store.megaphoneFeed.isOpen && !store.megaphoneFeed.hasLoaded)
        #expect(!store.isMegaphoneFeedShowing)
    }

    // 없으면: 지난 글이 배너로 다시 뜨거나 본 것 기록(100개)을 밀어내는 결함이 초록.
    @Test("지난 확성기 줄은 배너 스토어에 안 들어간다 — 막 보낸 글이어도 배너가 안 뜨고 필터 id 도 안 는다")
    func feedRowsNeverReachTheBannerStore() async {
        let (store, host) = mfMacStore("no-banner") { rpc, _, _ in
            switch rpc {
            case "megaphone_info": return GomokuStubProtocol.Reply(body: mfInfoJSON)
            case "megaphone_feed": return mfArray([mfRow("mp-fresh", ago: 5, name: "소라", body: "방금 보낸 말", now: Date())])
            default: return nil
            }
        }
        store.megaphoneBanner.schedule = { _, _ in }
        await mfOpenComposer(store)
        await mfOpenPage(store)
        #expect(store.megaphoneFeed.items.map(\.megaphoneID) == ["mp-fresh"])
        #expect(store.megaphoneBanner.current == nil && store.megaphoneBanner.queue.isEmpty, "지난 글이 배너로 떴다")
        #expect(store.megaphoneBanner.knownMessageIDs.isEmpty, "지난 글이 메시지함 필터에 들어갔다")
        #expect(GomokuStubProtocol.count(host: host, rpc: "megaphone_inbox") == 0, "지난 확성기가 배너 목록을 불렀다")
        #expect(mfCount(host) == 1)
    }
}

// MARK: - 소스 계약(주석을 걷고 본다)

@Suite("지난 확성기 소스 계약 — 전선 이름 한 곳 · 문 짝 · 실시간 자리")
struct MegaphoneFeedSourceTests {
    static func code(_ name: String) throws -> String {
        V0317ShopTests.stripped(try CheckCoreSourceLayout.joinedSplitSource(name))
    }

    @Test("전선 이름(megaphone_feed · megaphone_admin_hide)은 코어 파일 한 곳에만 있다")
    func wireNamesLiveInOneFile() throws {
        let base = CheckCoreSourceLayout.repoRoot.appendingPathComponent("Sources")
        let walker = try #require(FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil))
        var holders: [String] = []
        for case let url as URL in walker where url.pathExtension == "swift" {
            let code = V0317ShopTests.stripped(try String(contentsOf: url, encoding: .utf8))
            if code.contains("megaphone_feed") || code.contains("megaphone_admin_hide") { holders.append(url.lastPathComponent) }
        }
        #expect(holders == ["MegaphoneFeed.swift"], "전선 이름이 여러 곳에: \(holders)")
    }

    @Test("문 짝: 화면은 닫힘(false)에서만 문을 숨기고, 작성기 열기는 요청 없이 다시 세운다 · 디스패치와 실시간은 같은 술어")
    func gatePairsAndSingleShowingPredicate() throws {
        let composer = try Self.code("CheckMegaphoneComposer.swift")
        // 문은 문 술어를 읽고, 입력칸이 내려가기 전에 조합 중인 한글을 먼저 확정한다(두 버튼과 같은 문 — 검토 #4).
        #expect(composer.contains(
            "if store.showsMegaphoneFeedEntry { MegaphoneFeedEntryLink { FeedbackReplySend.commitThenSend(slot: .megaphone) { store.openMegaphoneFeed() } } }"),
                "작성기의 문이 문 술어를 안 읽거나 조합 확정 문을 안 지난다")
        let wiring = try Self.code("WorkTimerStoreMegaphoneFeed.swift")
        #expect(wiring.contains("megaphoneFeed.isAvailable != false"), "문 술어가 닫힘만 숨기지 않는다")
        let toggle = try Self.code("WorkTimerStoreMegaphone.swift")
        let start = try #require(toggle.range(of: "func toggleMegaphoneComposer()"))
        let end = try #require(toggle.range(of: "func prefetchMegaphoneInfo()", range: start.upperBound..<toggle.endIndex))
        let body = String(toggle[start.upperBound..<end.lowerBound])
        #expect(body.contains("rearmMegaphoneFeedEntry()"), "작성기 열기가 닫힌 문을 다시 안 세운다")
        #expect(!body.contains("megaphoneFeed.refresh(") && !body.contains("megaphoneFeed.open(") && !body.contains("openMegaphoneFeed("),
                "작성기 열기가 지난 확성기를 묻는다")
        let menu = try Self.code("CheckMenuView.swift")
        #expect(menu.contains("} else if store.isShopPanelVisible { if store.isMegaphoneFeedShowing { CheckMegaphoneFeedPanel("),
                "상점 자리가 지난 확성기 페이지를 안 그린다")
        let realtime = try Self.code("WorkTimerStoreRealtime.swift")
        let signal = try #require(realtime.range(of: "case .megaphoneSignal:"))
        let next = try #require(realtime.range(of: "case .pushAccessToken", range: signal.upperBound..<realtime.endIndex))
        let branch = String(realtime[signal.upperBound..<next.lowerBound])
        #expect(branch.contains("requestMegaphoneBannerRefresh()") && branch.contains("refreshMegaphoneFeedIfShowing()"))
        #expect(wiring.contains("guard isMegaphoneFeedShowing else { return }"), "실시간 새로고침이 화면 술어를 안 본다")
        #expect(wiring.contains("guard isMenuPresented else { megaphoneFeed.noteMissedSignal() return }"),
                "팝오버가 닫혀 숨은 페이지가 신호마다 묻는다")
        #expect(wiring.contains("guard canHideMegaphonePosts, isMegaphoneFeedShowing else { return nil }"), "내리기가 운영자 깃발을 안 본다")
        // 놓친 신호의 한 번은 팝오버 열기 자리에 · 차단 뒤 다시 읽기는 차단이 닿는 두 자리(확인 시트 · 신고하면서 차단)에.
        let store = try Self.code("WorkTimerStore.swift")
        let menuOpen = try #require(store.range(of: "func setMenuPresented("))
        let menuEnd = try #require(store.range(of: "var needsInsightsReload", range: menuOpen.upperBound..<store.endIndex))
        #expect(store[menuOpen.upperBound..<menuEnd.lowerBound].contains("refreshMegaphoneFeedIfSignalMissed()"),
                "팝오버를 다시 열어도 놓친 확성기를 안 읽는다")
        let blocks = try Self.code("WorkTimerStoreBlocks.swift")
        #expect(blocks.components(separatedBy: "refreshMegaphoneFeedAfterBlock(from:").count - 1 == 2,
                "차단이 닿는 두 자리 중 하나가 지난 확성기를 다시 안 읽는다")
        // 넘침 판정은 글이 실제로 받은 폭으로 잰다(스크롤 막대 — 검토 #5).
        let panel = try Self.code("CheckMegaphoneFeedPanel.swift")
        #expect(panel.contains("Layout.needsMore(item.body, width: measuredBodyWidth ?? Layout.bodyWidth)"))
        #expect(panel.contains(".onGeometryChange(for: CGFloat.self) { proxy in proxy.size.width }"), "본문 폭을 안 잰다")
    }

    @Test("배너 스토어로 가는 길이 없다 · 로그아웃 두 자리 모두 비운다 · 레일 · 배너 카드는 그대로")
    func noBannerPathAndBothSignOutSites() throws {
        for name in ["MegaphoneFeed.swift", "WorkTimerStoreMegaphoneFeed.swift", "CheckMegaphoneFeedPanel.swift"] {
            let code = try Self.code(name)
            #expect(!code.contains("megaphoneBanner") && !code.contains("MegaphoneBannerStore"), "\(name) 이 배너 스토어를 만진다")
            #expect(!code.contains("print(") && !code.contains("Logger("), "\(name) 에 로그가 붙었다(본문은 사람이 쓴 문장)")
        }
        let store = try Self.code("WorkTimerStore.swift")
        #expect(store.components(separatedBy: "megaphoneFeed.reset()").count - 1 == 2, "로그아웃 두 자리 중 하나가 목록을 안 비운다")
        #expect(store.contains("megaphoneFeed.attach(host: self)"))
        // 문은 작성기 하나 — 레일 · 배너 카드에는 없다.
        for name in ["CheckMenuView.swift", "CheckMegaphoneBannerWindow.swift"] {
            let code = try Self.code(name)
            #expect(!code.contains("openMegaphoneFeed") && !code.contains("MegaphoneFeedEntryLink"), "\(name) 에 지난 확성기 문이 생겼다")
        }
        // 피드 줄은 배너 타입이 아니다(타입으로 막힌 길).
        let core = try Self.code("MegaphoneFeed.swift")
        #expect(!core.contains("MegaphoneBanner(") && !core.contains("displayBody("), "피드가 배너 값을 만들거나 머리말을 다시 뗀다")
    }
}

// MARK: - 화면(렌더 — 높이 예산 · PNG)

/// 두 그림이 눈으로 다른가(바이트 동치는 디더 Δ1 에 흔들린다 — `CheckRenderDiff` 만 쓴다).
private func mfLooksDifferent(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep) throws -> Bool {
    let ca = try #require(a.cgImage), cb = try #require(b.cgImage)
    return try #require(CheckRenderDiff(ca, cb), "두 그림을 견줄 판을 못 만들었다").looksDifferent
}

@MainActor
private enum MFShots {
    /// PNG 를 FEATURE_SHOTS_DIR(있으면)에 굽는다. 없으면 이 실행의 임시 폴더.
    static func save(_ bitmap: NSBitmapImageRep, name: String) {
        let dir = ProcessInfo.processInfo.environment["FEATURE_SHOTS_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("check-megafeed", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { return }
        try? png.write(to: dir.appendingPathComponent(name))
    }

    static let longBody = String(repeating: "오늘 저녁 7시 라운지에서 보드게임 모임이 있어요. 누구나 와도 돼요! ", count: 4)

    /// 화면용 줄(지금 시각 기준 — 서버 모양 그대로).
    static func rows(now: Date, count: Int = 4) -> [[String: Any]] {
        let base: [[String: Any]] = [
            mfRow("mp-1", ago: 300, sender: mfOther, name: "소라", body: "3층 라운지에 귤 한 상자 있어요 🍊", recipients: 46, now: now),
            mfRow("mp-2", ago: 5_400, sender: mfMe, name: "나", body: "오늘 회고 6시에 해요", isMine: true, recipients: 45, now: now),
            mfRow("mp-3", ago: 90_000, sender: mfThird, name: "도윤", body: longBody, recipients: 44, now: now),
            mfRow("mp-4", ago: 9 * 86_400, sender: "00000000-0000-0000-0000-0000000000e5", name: "하윤",
                  body: "**우산** 두고 가신 분 찾아가세요", recipients: 41, now: now),
        ]
        guard count > base.count else { return Array(base.prefix(count)) }
        return base + (base.count..<count).map { index in
            mfRow("mp-\(index + 1)", ago: Double(index) * 7_200 + 9 * 86_400, sender: mfOther, name: "소라",
                  body: "반복 줄 \(index + 1) — 높이 예산을 재려고 늘린 글이에요", now: now)
        }
    }

    /// 팝오버를 그릴 수 있는 스토어(팀 화면 + 상점 + 작성기). 서버는 스텁이다. `feedReply` 가 nil 이면 rows 배열.
    static func popoverStore(rows: [[String: Any]], feedReply: GomokuStubProtocol.Reply? = nil,
                             function: String = #function, line: Int = #line) async -> WorkTimerStore {
        let host = "mf-shot-\(UUID().uuidString.prefix(8))".lowercased()
        let feedBody = mfJSON(rows)
        GomokuStubProtocol.register(host: host) { rpc, _, _ in
            switch rpc {
            case "megaphone_info": return GomokuStubProtocol.Reply(body: mfInfoJSON)
            case "megaphone_feed": return feedReply ?? GomokuStubProtocol.Reply(body: feedBody)
            case "megaphone_admin_hide": return GomokuStubProtocol.Reply(body: #"{"status":"ok","hidden":true}"#)
            default: return nil
            }
        }
        let service = SupabaseWorkService(projectURL: URL(string: "http://\(host)")!, anonKey: "anon-test-key",
                                          session: GomokuStubProtocol.session())
        let store = V0317ShopTests.teamStore(members: 8, service: service, function: function, line: line)
        store.toggleShopPanel()
        // 상점 진입의 읽기(스텁은 상점 상태를 모른다)가 다 돈 **뒤에** 상점 값을 넣는다 — 늦은 응답이 덮지 않게.
        _ = await mfWait { !store.shopLoading && !store.megaphone.infoLoading }
        store.applyShopState(ShopStateResponse(rubyBalance: 120, ultraBalance: 3, ultraPrice: 3, ultraBuyMax: 20,
                                               characters: V0317ShopTests.rows(ownedIDs: [])))
        store.shopLoaded = true
        store.toggleMegaphoneComposer()
        _ = await mfWait { !store.megaphone.infoLoading }
        return store
    }

    /// 팝오버 열기 → 상점 → 작성기 → 페이지까지(첫 쪽이 다 돈 뒤).
    static func pageStore(rows: [[String: Any]], function: String = #function, line: Int = #line) async -> WorkTimerStore {
        let store = await popoverStore(rows: rows, function: function, line: line)
        store.openMegaphoneFeed()
        _ = await mfWait { !store.megaphoneFeed.isLoading }
        return store
    }
}

@Suite("지난 확성기 화면 — 팝오버 700pt · 작성기 166pt · PNG")
@MainActor
struct MegaphoneFeedRenderTests {

    @Test("넘침 판정: 긴 글만 [더 보기] — 짧은 글 · 한 줄 글은 아니다")
    func needsMoreOnlyForLongBodies() {
        #expect(MegaphoneFeedLayout.needsMore(MFShots.longBody))
        #expect(!MegaphoneFeedLayout.needsMore("3층 라운지에 귤 한 상자 있어요"))
        #expect(!MegaphoneFeedLayout.needsMore(String(repeating: "가", count: 20)))
        #expect(MegaphoneFeedLayout.bodyWidth == 258)
    }

    // 없으면: 마우스를 꽂은 맥(늘 보이는 스크롤 막대 ≈15pt)에서 계산 폭엔 3줄이라 [더 보기]가 안 서는데 실제 폭에선 4줄이라
    // '…'로 잘려 끝까지 못 읽는 결함이 초록(검토 #5). 판정은 뷰가 잰 폭(`measuredBodyWidth`)을 받는다 — 소스 계약이 그 자리를 본다.
    @Test("넘침 판정은 받은 폭으로 잰다 — 스크롤 막대만큼 좁아지면 계산 폭에선 안 넘치던 글에도 [더 보기]가 선다")
    func needsMoreFollowsTheMeasuredWidth() throws {
        let narrow = MegaphoneFeedLayout.bodyWidth - NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy)
        #expect(narrow < MegaphoneFeedLayout.bodyWidth - 10, "기준선: 늘 보이는 막대가 폭을 먹는다")
        // 좁은 폭에서 처음 넘치는 길이를 찾는다(글자를 하나씩 늘린다). 그 글은 계산 폭에선 아직 3줄 안이어야 한다.
        let words = Array(String(repeating: "오늘 라운지에서 귤 나눠요 모두 와서 가져가세요 3층 창가 자리예요 ", count: 6))
        var flip: String?
        for count in 20...words.count {
            let body = String(words.prefix(count))
            if MegaphoneFeedLayout.needsMore(body, width: narrow) {
                flip = body
                break
            }
        }
        let body = try #require(flip, "좁은 폭에서도 끝까지 안 넘쳤다")
        #expect(!MegaphoneFeedLayout.needsMore(body), "계산 폭에서도 넘친다 — 좁은 폭의 차이를 못 잰다")
        #expect(MegaphoneFeedLayout.needsMore(body, width: narrow), "좁아진 폭에서 넘치는데 [더 보기]가 안 선다")
    }

    @Test("머리 줄 작은 글씨: 시각 · 받은 사람 수(모르면 시각만)")
    func metaTextShowsRecipients() {
        let item = mfItem("m1", ago: 60, now: mfWall0, recipients: 46)
        let time = MegaphoneFeedText.timeLabel(item.createdAt, now: mfWall0)
        #expect(CheckMegaphoneFeedPanel.metaText(item, now: mfWall0) == "\(time) · 46명에게")
        #expect(CheckMegaphoneFeedPanel.metaText(mfItem("m2", recipients: nil), now: mfWall0) == time)
    }

    @Test("페이지: 내 글 · 긴 글을 그리고 팝오버 예산 안이다 · [더 보기]가 실제로 펼친다(PNG)")
    func pageRendersWithinTheBudget() async throws {
        let now = Date()
        let store = await MFShots.pageStore(rows: MFShots.rows(now: now))
        #expect(store.isMegaphoneFeedShowing && store.megaphoneFeed.items.count == 4)
        #expect(store.megaphoneFeed.items[1].isOwn && store.megaphoneFeed.items[2].body.count > 100)
        let panel = CheckMegaphoneFeedPanel(store: store, clipsOverflowInsteadOfScroll: true, now: { now }, onBack: {})
        let rep = try #require(V0317ShopTests.bitmap(panel, width: CheckMenuView.contentColumnWidth))
        let height = CGFloat(rep.pixelsHigh) / 2
        let budget = 700 - ShopPanelGridBudget.popoverChromeOutsidePanel
        #expect(height <= budget, "페이지가 \(height)pt — 패널 예산 \(budget)pt 를 넘는다")
        MFShots.save(rep, name: "megafeed-page.png")
        let expanded = CheckMegaphoneFeedPanel(store: store, clipsOverflowInsteadOfScroll: true, previewExpandedIDs: ["mp-3"],
                                               now: { now }, onBack: {})
        let open = try #require(V0317ShopTests.bitmap(expanded, width: CheckMenuView.contentColumnWidth))
        #expect(CGFloat(open.pixelsHigh) / 2 > height, "펼쳤는데 높이가 그대로다 — [더 보기]가 아무것도 안 펼친다")
        #expect(CGFloat(open.pixelsHigh) / 2 <= budget)
        MFShots.save(open, name: "megafeed-page-expanded.png")
    }

    @Test("운영자 화면: 줄마다 ··· · 내리기 결과 한 줄이 선 페이지도 예산 안이다(PNG)")
    func adminPageWithNoticeStaysInTheBudget() async throws {
        let now = Date()
        let store = await MFShots.pageStore(rows: MFShots.rows(now: now, count: 3) + [
            mfRow("mp-hide", ago: 3_600, sender: mfThird, name: "도윤", body: "내릴 글", now: now),
        ])
        let before = try #require(V0317ShopTests.bitmap(
            CheckMegaphoneFeedPanel(store: store, clipsOverflowInsteadOfScroll: true, now: { now }, onBack: {}),
            width: CheckMenuView.contentColumnWidth))
        store.ultraUnlimited = true
        let hidden = try #require(store.megaphoneFeed.items.last)
        #expect(hidden.megaphoneID == "mp-hide")
        await store.hideMegaphonePost(hidden)?.value
        #expect(store.megaphoneFeedNotice == MegaphoneFeedNotice(text: MegaphoneFeedText.adminHidden, isError: false))
        #expect(!store.visibleMegaphoneFeed.contains { $0.megaphoneID == "mp-hide" }, "내린 글이 남았다")
        let panel = CheckMegaphoneFeedPanel(store: store, clipsOverflowInsteadOfScroll: true, extraChromeHeight: 241,
                                            now: { now }, onBack: {})
        let rep = try #require(V0317ShopTests.bitmap(panel, width: CheckMenuView.contentColumnWidth))
        let height = CGFloat(rep.pixelsHigh) / 2
        // 가장 큰 크롬(새 버전 배너 + 노트 4줄 149 + 목표 편집 92 = 241)이 얹혀도 패널은 남은 자리 안이다.
        let budget = 700 - ShopPanelGridBudget.popoverChromeOutsidePanel - 241
        #expect(height <= budget, "결과 줄이 선 페이지가 \(height)pt — 남은 자리 \(budget)pt 를 넘는다")
        #expect(try mfLooksDifferent(before, rep), "운영자 ··· · 결과 줄이 그림에 안 나온다")
        MFShots.save(rep, name: "megafeed-page-admin-notice.png")
    }

    @Test("꼬리 [이전 확성기 더 보기] · 신고 접수 한 줄이 선 페이지도 예산 안이다(PNG)")
    func pageWithFooterAndNoticeStaysInTheBudget() async throws {
        let now = Date()
        let store = await MFShots.pageStore(rows: MFShots.rows(now: now, count: 30))
        #expect(store.megaphoneFeed.hasMore, "준비 실패 — 꽉 찬 쪽인데 꼬리 단추가 없다")
        store.blockReportNotice = BlockReportNotice(text: BlockReportText.reportSentNotice, isError: false, surface: .megaphoneFeed)
        #expect(store.megaphoneFeedNotice?.text == BlockReportText.reportSentNotice)
        let panel = CheckMegaphoneFeedPanel(store: store, clipsOverflowInsteadOfScroll: true, extraChromeHeight: 241,
                                            now: { now }, onBack: {})
        let rep = try #require(V0317ShopTests.bitmap(panel, width: CheckMenuView.contentColumnWidth))
        let height = CGFloat(rep.pixelsHigh) / 2
        let budget = 700 - ShopPanelGridBudget.popoverChromeOutsidePanel - 241
        #expect(height <= budget, "결과 줄이 선 페이지가 \(height)pt — 남은 자리 \(budget)pt 를 넘는다")
        MFShots.save(rep, name: "megafeed-page-more-notice.png")
        // 꼬리 단추는 목록 끝에 있다 — 상한을 풀어 끝까지 그린 그림에서 확인한다.
        let full = CheckMegaphoneFeedPanel(store: store, clipsOverflowInsteadOfScroll: true, extraChromeHeight: -4_000,
                                           now: { now }, onBack: {})
        if let tail = V0317ShopTests.bitmap(full, width: CheckMenuView.contentColumnWidth) {
            MFShots.save(tail, name: "megafeed-page-full-list.png")
        }
        store.closeMegaphoneFeed()
        #expect(store.blockReportNotice(on: .megaphoneFeed) == nil, "페이지를 떠났는데 결과 줄이 남았다")
    }

    // 없으면: 줄이 많고 배너·목표 편집 행이 얹힌 화면에서 팝오버가 700pt 를 넘어 푸터(로그아웃)가 잘리는 결함이 초록.
    @Test("최악 조합(30줄 + 더 보기 + 목표 편집 행)에서도 팝오버가 700pt 안이다(PNG)")
    func popoverStaysUnderTheCapInTheWorstCase() async throws {
        let store = await MFShots.pageStore(rows: MFShots.rows(now: Date(), count: 30))
        #expect(store.megaphoneFeed.items.count == 30 && store.megaphoneFeed.hasMore, "준비 실패 — 꽉 찬 쪽이 아니다")
        let plain = CheckMenuView(store: store, previewClipsOverflowList: true, characterDefaults: V0317ShopTests.isolatedDefaults("mf-plain"))
        let typical = try #require(V0317ShopTests.popoverHeight(plain))
        #expect(typical <= 700, "팝오버가 \(typical)pt")
        if let rep = V0317ShopTests.bitmap(plain, width: CheckMenuView.mainWindowWidth) { MFShots.save(rep, name: "megafeed-popover.png") }

        store.isEditingWeeklyGoal = true
        let worst = CheckMenuView(store: store, previewClipsOverflowList: true, previewGoalEditing: true,
                                  characterDefaults: V0317ShopTests.isolatedDefaults("mf-worst"))
        let height = try #require(V0317ShopTests.popoverHeight(worst))
        #expect(height <= 700, "최악 조합 팝오버가 \(height)pt — 700pt 상한을 넘어 푸터가 잘린다")
        if let rep = V0317ShopTests.bitmap(worst, width: CheckMenuView.mainWindowWidth) { MFShots.save(rep, name: "megafeed-popover-worst.png") }
    }

    @Test("신고 시트도 같은 자리 · 같은 상한이다(최악 조합 700pt · PNG)")
    func reportSheetStaysUnderTheCap() async throws {
        let store = await MFShots.pageStore(rows: MFShots.rows(now: Date()))
        let item = try #require(store.megaphoneFeed.items.first { $0.megaphoneID == "mp-3" })
        store.openReport(try #require(MegaphoneFeedSafetyRule.reportTarget(for: item, me: store.session?.userID)), surface: .megaphoneFeed)
        store.isEditingWeeklyGoal = true
        let view = CheckMenuView(store: store, previewClipsOverflowList: true, previewGoalEditing: true,
                                 previewPlainTextEditors: true, characterDefaults: V0317ShopTests.isolatedDefaults("mf-report"))
        let height = try #require(V0317ShopTests.popoverHeight(view))
        #expect(height <= 700, "신고 시트를 연 팝오버가 \(height)pt")
        if let rep = V0317ShopTests.bitmap(view, width: CheckMenuView.mainWindowWidth) { MFShots.save(rep, name: "megafeed-report-sheet.png") }
    }

    // 없으면: 문이 작성기를 키워 상점 높이 예산(166 · 크롬 230)이 거짓이 되거나, 닫힘인데 문이 그려지는 결함이 초록.
    @Test("작성기 문: 섰을 때도 작성기는 166pt 그대로 · 닫힘이면 문이 사라진다 · 상점 팝오버 700pt 안(PNG)")
    func composerLinkKeepsTheComposerHeight() async throws {
        let store = await MFShots.popoverStore(rows: MFShots.rows(now: Date()))
        #expect(store.showsMegaphoneFeedEntry, "준비 실패 — 문이 안 섰다")
        let with = try #require(V0317ShopTests.bitmap(MegaphoneComposer(store: store), width: MegaphoneFeedLayout.contentWidth))
        #expect(CGFloat(with.pixelsHigh) / 2 == MegaphoneComposer.height, "문이 선 작성기가 \(CGFloat(with.pixelsHigh) / 2)pt")
        // 눈으로 볼 PNG 는 패널 바탕 위에(작성기 글자는 어두운 바탕 기준 색이다).
        let framed = MegaphoneComposer(store: store).padding(12).background(CheckTheme.panel).environment(\.colorScheme, .dark)
        if let shot = V0317ShopTests.bitmap(framed, width: MegaphoneFeedLayout.contentWidth + 24) {
            MFShots.save(shot, name: "megafeed-composer-link.png")
        }
        // 기준선: 문이 닫힌 작성기(페이지를 열어 404 를 받은 뒤 — 같은 높이 · 다른 픽셀).
        let bare = await MFShots.popoverStore(rows: [], feedReply: mfMissing)
        bare.openMegaphoneFeed()
        _ = await mfWait { !bare.megaphoneFeed.isLoading }
        bare.closeMegaphoneFeed()
        #expect(bare.showsMegaphoneFeedEntry == false, "준비 실패 — 404 뒤에도 문이 서 있다")
        let without = try #require(V0317ShopTests.bitmap(MegaphoneComposer(store: bare), width: MegaphoneFeedLayout.contentWidth))
        #expect(CGFloat(without.pixelsHigh) / 2 == MegaphoneComposer.height)
        #expect(try mfLooksDifferent(with, without), "문이 섰는데 그림이 같다 — 문이 안 그려진다")

        store.isEditingWeeklyGoal = true
        let view = CheckMenuView(store: store, previewClipsOverflowList: true, previewGoalEditing: true,
                                 characterDefaults: V0317ShopTests.isolatedDefaults("mf-composer"))
        let height = try #require(V0317ShopTests.popoverHeight(view))
        #expect(height <= 700, "작성기를 연 상점 팝오버가 \(height)pt")
        store.isEditingWeeklyGoal = false
        let normal = CheckMenuView(store: store, previewClipsOverflowList: true,
                                   characterDefaults: V0317ShopTests.isolatedDefaults("mf-composer-normal"))
        if let rep = V0317ShopTests.bitmap(normal, width: CheckMenuView.mainWindowWidth) { MFShots.save(rep, name: "megafeed-shop-composer.png") }
    }

    @Test("빈 · 실패 · 닫힘 상태를 그린다(PNG)")
    func emptyFailedAndClosedStates() async throws {
        let empty = await MFShots.pageStore(rows: [])
        #expect(empty.megaphoneFeed.hasLoaded && empty.megaphoneFeed.items.isEmpty)
        let emptyRep = try #require(V0317ShopTests.bitmap(CheckMegaphoneFeedPanel(store: empty, onBack: {}), width: CheckMenuView.contentColumnWidth))
        MFShots.save(emptyRep, name: "megafeed-empty.png")

        let failed = await MFShots.popoverStore(rows: [], feedReply: GomokuStubProtocol.Reply(status: 503, body: "{}"))
        failed.openMegaphoneFeed()
        _ = await mfWait { !failed.megaphoneFeed.isLoading }
        #expect(failed.megaphoneFeed.loadFailed)
        let failedRep = try #require(V0317ShopTests.bitmap(CheckMegaphoneFeedPanel(store: failed, onBack: {}), width: CheckMenuView.contentColumnWidth))
        MFShots.save(failedRep, name: "megafeed-failed.png")
        #expect(try mfLooksDifferent(emptyRep, failedRep), "빈 목록과 실패가 같은 그림이다")

        let closed = await MFShots.popoverStore(rows: [], feedReply: mfMissing)
        closed.openMegaphoneFeed()
        _ = await mfWait { !closed.megaphoneFeed.isLoading }
        #expect(closed.megaphoneFeed.isAvailable == false)
        let closedRep = try #require(V0317ShopTests.bitmap(CheckMegaphoneFeedPanel(store: closed, onBack: {}), width: CheckMenuView.contentColumnWidth))
        MFShots.save(closedRep, name: "megafeed-closed.png")
    }
}
