import Foundation
import Testing
@testable import CheckCore

// 2026-10-30 — 확성기 배너 코어(`MegaphoneBanner` · `MegaphoneInboxItem` · `MegaphoneBannerStore` · `MegaphoneText` 대기 문구) 계약.
// 계약 docs/plan/megaphone-banner-contract.md "그물 — 시험 · 코어" 줄의 항목을 하나씩 잰다. **모양이 아니라 결과를 잰다.**
//
// 서버는 스텁이다(`GomokuStubProtocol` — 시험마다 고유 호스트). 시계와 타이머는 `MBTimeline` 하나가 쥔다 — `advance` 가 시각을
// 옮기고 그때까지 만기된 타이머를 순서대로 부른다(8초를 실제로 기다리지 않는다). 본 것 기록은 격리 스위트(`CheckTestScratch`)다.
//
// 각 시험은 비교 기준선을 하나씩 둔다 — 같은 입력에서 그 값 하나만 바꿔 결과가 갈리는 것을 보인다("상수가 있다"가 아니라).

// MARK: - 하네스

private let mbMe = "00000000-0000-0000-0000-0000000000a1"
private let mbOther = "00000000-0000-0000-0000-0000000000c3"
private let mbWall0 = Date(timeIntervalSince1970: 1_800_000_000)

private struct MBError: Error {}

@MainActor
private final class MBHost: GomokuStoreHost {
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
        guard let session else { throw MBError() }
        return try await operation(session)
    }

    func classifyAuthError(_ error: Error) -> AuthErrorDisposition { .transient }
}

@MainActor
private enum MBRetention {
    /// 스토어는 호스트를 약참조로 든다 — 시험이 버리면 요청이 한 건도 안 나간다.
    static var hosts: [MBHost] = []
}

/// 시계 + 가짜 타이머 대기열. 스토어의 시계 클로저가 그대로 잡도록 격리 없는 참조 타입이다(만지는 것은 메인 액터의 시험뿐).
private final class MBTimeline: @unchecked Sendable {
    var now: Date = mbWall0
    private(set) var scheduledDelays: [TimeInterval] = []
    private var timers: [(due: Date, seq: Int, fire: @MainActor @Sendable () -> Void)] = []
    private var seq = 0

    func schedule(_ after: TimeInterval, _ fire: @escaping @MainActor @Sendable () -> Void) {
        seq += 1
        scheduledDelays.append(after)
        timers.append((now.addingTimeInterval(after), seq, fire))
    }

    /// 시각을 `seconds` 만큼 옮기며 그 안에 만기된 타이머를 만기 순으로 부른다(부르는 중에 걸린 타이머도).
    @MainActor
    func advance(_ seconds: TimeInterval) {
        let target = now.addingTimeInterval(seconds)
        while let next = timers.filter({ $0.due <= target }).min(by: { ($0.due, $0.seq) < ($1.due, $1.seq) }) {
            timers.removeAll { $0.seq == next.seq }
            if next.due > now { now = next.due }
            next.fire()
        }
        now = target
    }
}

private final class MBFlag: @unchecked Sendable { var value: Bool; init(_ value: Bool) { self.value = value } }

@MainActor
private struct MBRig {
    let store: MegaphoneBannerStore
    let timeline: MBTimeline
    let owner: MBHost
    let host: String

    func calls(_ rpc: String) -> Int { GomokuStubProtocol.count(host: host, rpc: rpc) }
}

@MainActor
private func mbMake(_ label: String, userID: String = mbMe, defaults: UserDefaults? = nil,
                    function: String = #function, handler: @escaping GomokuStubProtocol.Handler) -> MBRig {
    let host = "mb-\(label)-\(UUID().uuidString.prefix(8))".lowercased()
    GomokuStubProtocol.register(host: host, handler: handler)
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!, anonKey: "anon-test-key", session: GomokuStubProtocol.session())
    let owner = MBHost(service: service, userID: userID)
    MBRetention.hosts.append(owner)
    let timeline = MBTimeline()
    let store = MegaphoneBannerStore(
        host: owner,
        defaults: defaults ?? CheckTestScratch.defaults("mb-\(label)", function: function),
        clock: { timeline.now },
        schedule: { after, fire in timeline.schedule(after, fire) }
    )
    return MBRig(store: store, timeline: timeline, owner: owner, host: host)
}

/// inbox 한 줄. `agoSeconds` 는 mbWall0 기준 몇 초 전에 보냈나.
private func mbItem(_ messageID: String, _ megaphoneID: String, agoSeconds: Double, sender: String = mbOther,
                    name: String = "보낸이", body: String = "모두 안녕") -> [String: Any] {
    ["message_id": messageID, "megaphone_id": megaphoneID, "sender_id": sender, "sender_display_name": name,
     "sender_avatar_url": NSNull(), "body": body, "created_epoch": mbWall0.timeIntervalSince1970 - agoSeconds]
}

private func mbJSON(_ object: Any) -> String {
    String(decoding: try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
}

private func mbReply(_ items: [[String: Any]], delay: TimeInterval = 0) -> GomokuStubProtocol.Reply {
    GomokuStubProtocol.Reply(body: mbJSON(items), delay: delay)
}

/// 함수 없는 서버(앱이 db push 보다 먼저 나간 창).
private let mbMissing = GomokuStubProtocol.Reply(
    status: 404, body: #"{"code":"PGRST202","message":"Could not find the function in the schema cache"}"#)

@MainActor
private func mbWait(_ condition: @MainActor () -> Bool) async -> Bool {
    for _ in 0..<600 {
        if condition() { return true }
        try? await Task.sleep(nanoseconds: 5_000_000)
    }
    return condition()
}

private let mbForbidden = ["서버", "RPC", "토큰", "테스트", "전역", "scope", "쿨타임"]

// MARK: - 시험

@Suite("확성기 배너 코어 — 필터 · 신선도 · 한 번에 하나 · 미룸 · 경합 · 폴백 · 문구")
@MainActor
struct MegaphoneBannerStoreTests {

    // 없으면: 모름/없음 상태에서도 줄을 숨겨 옛 서버 사용자가 확성기를 통째로 잃거나, 404 뒤에도 숨김이 남는 결함이 초록.
    @Test("필터 술어 세 갈래: 모름 → 안 숨김 · 가능 → inbox 가 말한 id 만 · 불가(404) → 다시 안 숨김")
    func filterPredicateThreeWays() async {
        let fresh = mbReply([mbItem("msg-1", "mega-1", agoSeconds: 30)])
        let rig = mbMake("filter") { rpc, _, index in
            guard rpc == "megaphone_inbox" else { return nil }
            return index == 0 ? fresh : mbMissing
        }
        let store = rig.store
        #expect(store.capability == .unknown)
        #expect(!store.hides(messageID: "msg-1"), "모름: 아직 inbox 를 안 물었다 — 숨기면 안 된다")
        #expect(store.unreadSummaryFunction == MegaphoneBannerStore.unreadSummaryV1)

        await store.refresh()
        #expect(store.capability == .available)
        #expect(store.hides(messageID: "msg-1"))
        #expect(!store.hides(messageID: "dm-7"), "기준선: inbox 가 말하지 않은 id 는 그대로 메시지")
        #expect(store.unreadSummaryFunction == MegaphoneBannerStore.unreadSummaryV2)

        await store.refresh()   // 이번엔 404 — 서버가 함수를 잃었다
        #expect(store.capability == .unavailable)
        #expect(!store.hides(messageID: "msg-1"), "불가: 같은 id 라도 필터를 끈다")
        #expect(!store.needsVerification(messageID: "msg-9", body: "📢 공지"), "불가: 판정 보류도 없다(지금처럼 메시지)")
        #expect(store.unreadSummaryFunction == MegaphoneBannerStore.unreadSummaryV1)
    }

    // 없으면: inbox 가 처음부터 없는 서버에서 접두 줄이 영영 판정 보류로 남거나, 필터가 켜지는 결함이 초록.
    @Test("inbox 404 → 필터 끔: 처음부터 없는 서버는 지금처럼 메시지 · 요약은 옛 함수")
    func inboxMissingTurnsFilterOff() async {
        let rig = mbMake("inbox404") { rpc, _, _ in rpc == "megaphone_inbox" ? mbMissing : nil }
        #expect(rig.store.needsVerification(messageID: "msg-1", body: "📢 공지"), "기준선: 모를 때는 보류한다")
        await rig.store.refresh()
        #expect(rig.store.capability == .unavailable)
        #expect(!rig.store.needsVerification(messageID: "msg-1", body: "📢 공지"))
        #expect(!rig.store.hides(messageID: "msg-1"))
        #expect(rig.store.current == nil && !rig.store.lastRefreshFailed)
        #expect(rig.store.unreadSummaryFunction == MegaphoneBannerStore.unreadSummaryV1)
    }

    // 없으면: 앱을 켜 둔 사이 한참 전에 온 확성기가 뒤늦게 화면을 덮는 결함(또는 경계 반대로 신선한 것을 버리는 결함)이 초록.
    @Test("신선도 10분: 599초 전은 뜨고 601초 전은 안 뜬다 — 그래도 둘 다 메시지함에서는 빠진다")
    func freshnessTenMinutes() async {
        let items = mbReply([mbItem("msg-old", "mega-old", agoSeconds: 601), mbItem("msg-new", "mega-new", agoSeconds: 599)])
        let rig = mbMake("fresh") { rpc, _, _ in rpc == "megaphone_inbox" ? items : nil }
        await rig.store.refresh()
        #expect(rig.store.current?.megaphoneID == "mega-new", "기준선: 경계 안쪽(599초)은 뜬다")
        #expect(rig.store.queue.isEmpty, "601초 전은 줄에도 없다")
        #expect(rig.store.hides(messageID: "msg-old") && rig.store.hides(messageID: "msg-new"))
        #expect(MegaphoneBannerRules.freshness == 600)
    }

    // 없으면: 푸시를 눌러 들어왔는데(수 시간 전 확성기) 신선도에 걸려 아무것도 안 뜨는 결함이 초록.
    @Test("푸시 진입은 24시간 안이면 신선도 무시 · 25시간은 안 뜬다 · 뒤이은 inbox 가 id·상대를 맞춘다")
    func pushEntryIgnoresFreshness() async {
        let threeHours: TimeInterval = 3 * 3_600
        let item = mbReply([mbItem("msg-p", "mega-p", agoSeconds: threeHours, name: "푸시맨")])
        let rig = mbMake("push") { rpc, _, _ in rpc == "megaphone_inbox" ? item : nil }
        rig.store.presentFromPush(megaphoneID: "mega-p", senderName: "푸시맨", body: "📢 세 시간 전 말",
                                  createdAt: mbWall0.addingTimeInterval(-threeHours))
        #expect(rig.store.current?.megaphoneID == "mega-p")
        #expect(rig.store.current?.body == "세 시간 전 말", "알림 본문의 📢 표식은 떼고 그린다")
        #expect(rig.store.current?.canReply == false, "아직 상대를 모르면 답장 버튼이 없다")
        // presentFromPush 가 스스로 refresh 한다 — 같은 확성기의 id·보낸 사람이 얹힌다(타이머는 다시 안 센다).
        #expect(await mbWait { rig.store.current?.messageID == "msg-p" })
        #expect(rig.store.current?.senderID == mbOther && rig.store.current?.canReply == true)
        #expect(rig.store.hides(messageID: "msg-p"))
        #expect(rig.timeline.scheduledDelays.filter { $0 == MegaphoneBannerRules.displaySeconds }.count == 1)

        // 기준선: 같은 3시간 전 항목이 푸시가 아니라 inbox 로만 오면 안 뜬다.
        let plain = mbMake("push-base") { rpc, _, _ in rpc == "megaphone_inbox" ? item : nil }
        await plain.store.refresh()
        #expect(plain.store.current == nil && plain.store.hides(messageID: "msg-p"))

        // 24시간 밖은 푸시라도 안 뜬다.
        let stale = mbMake("push-stale") { _, _, _ in nil }
        stale.store.presentFromPush(megaphoneID: "mega-q", senderName: "옛날", body: "📢 어제 말",
                                    createdAt: mbWall0.addingTimeInterval(-25 * 3_600))
        #expect(stale.store.current == nil)
    }

    // 없으면: 재실행할 때마다 같은 확성기가 또 뜨거나, 한 계정의 기록이 다른 계정을 막는 결함이 초록.
    @Test("본 것 기록: 재실행해도 다시 안 뜬다 · 계정별 키 · 최근 100개")
    func seenRecordSurvivesRelaunchPerAccount() async {
        let shared = CheckTestScratch.defaults("mb-seen-shared")
        defer { shared.removePersistentDomain(forName: CheckTestScratch.suitePath("mb-seen-shared")) }
        let item = mbReply([mbItem("msg-s", "mega-s", agoSeconds: 20)])
        let handler: GomokuStubProtocol.Handler = { rpc, _, _ in rpc == "megaphone_inbox" ? item : nil }

        let first = mbMake("seen-a", defaults: shared, handler: handler)
        await first.store.refresh()
        #expect(first.store.current?.megaphoneID == "mega-s")
        first.store.dismissCurrent()
        #expect(shared.stringArray(forKey: MegaphoneBannerRules.seenKey(userID: mbMe)) == ["mega-s"])

        let relaunched = mbMake("seen-b", defaults: shared, handler: handler)
        await relaunched.store.refresh()
        #expect(relaunched.store.current == nil && relaunched.store.queue.isEmpty, "재실행: 이미 본 확성기")
        #expect(relaunched.store.hides(messageID: "msg-s"), "안 띄워도 메시지함에서는 뺀다")

        let otherAccount = mbMake("seen-c", userID: mbOther, defaults: shared, handler: handler)
        await otherAccount.store.refresh()
        #expect(otherAccount.store.current?.megaphoneID == "mega-s", "기준선: 다른 계정은 자기 기록을 읽는다")

        let many = mbMake("seen-many") { _, _, _ in nil }
        for index in 0..<105 {
            many.store.presentOwn(body: "\(index)번째", senderName: "나", megaphoneID: "own-\(index)")
            many.store.dismissCurrent()
            many.timeline.advance(MegaphoneBannerRules.gap)
        }
        many.store.presentOwn(body: "id 없는 내 배너", senderName: "나")
        let seen = many.store.seenMegaphoneIDs
        #expect(seen.count == MegaphoneBannerRules.seenLimit)
        #expect(seen.first == "own-5" && seen.last == "own-104", "오래된 다섯을 밀어낸다 · 자리값 id 는 기록하지 않는다")
    }

    // 없으면: 두 장이 한꺼번에 뜨거나, 8초가 아닌 시간에 닫히거나, 닫히자마자 다음 장이 붙는 결함이 초록.
    @Test("한 번에 하나 · 8초 · 다음 장은 0.4초 뒤 · 오래된 것부터")
    func oneAtATimeEightSeconds() async {
        let items = mbReply([mbItem("msg-b", "mega-b", agoSeconds: 60), mbItem("msg-a", "mega-a", agoSeconds: 120)])
        let rig = mbMake("one") { rpc, _, _ in rpc == "megaphone_inbox" ? items : nil }
        await rig.store.refresh()
        #expect(rig.store.current?.megaphoneID == "mega-a", "먼저 보낸 것부터")
        #expect(rig.store.queue.map(\.megaphoneID) == ["mega-b"])
        rig.timeline.advance(7.9)
        #expect(rig.store.current?.megaphoneID == "mega-a", "기준선: 8초 전에는 그대로")
        rig.timeline.advance(0.1)
        #expect(rig.store.current == nil)
        rig.timeline.advance(0.39)
        #expect(rig.store.current == nil, "쉬는 0.4초 동안은 비어 있다")
        rig.timeline.advance(0.01)
        #expect(rig.store.current?.megaphoneID == "mega-b")
        rig.timeline.advance(8)
        #expect(rig.store.current == nil)
    }

    // 없으면: 마우스를 올려도 사라지거나, 떠난 뒤 남은 0.5초 만에 휙 사라지는 결함이 초록.
    @Test("멈춤: 올려 둔 동안은 안 사라진다 · 풀리면 남은 시간과 3초 중 긴 쪽")
    func pauseAndResume() async {
        let rig = mbMake("pause") { _, _, _ in nil }
        rig.store.presentOwn(body: "멈춰 봐", senderName: "나")
        rig.timeline.advance(1)
        rig.store.pauseTimer()
        rig.timeline.advance(100)
        #expect(rig.store.current != nil && rig.store.isTimerPaused)
        rig.store.resumeTimer()
        rig.timeline.advance(6.9)
        #expect(rig.store.current != nil, "남은 7초가 3초보다 길다")
        rig.timeline.advance(0.1)
        #expect(rig.store.current == nil)

        rig.timeline.advance(MegaphoneBannerRules.gap)
        rig.store.presentOwn(body: "거의 끝", senderName: "나")
        rig.timeline.advance(7.5)
        rig.store.pauseTimer()
        rig.store.resumeTimer()
        rig.timeline.advance(2.9)
        #expect(rig.store.current != nil, "기준선: 남은 0.5초가 아니라 3초를 센다")
        rig.timeline.advance(0.1)
        #expect(rig.store.current == nil)
    }

    // 없으면: 대결 판 위에 배너가 뜨거나, 판이 끝난 뒤 묵은 확성기가 줄줄이 뜨는 결함이 초록.
    @Test("미룸: 붙드는 동안 안 뜬다 · 풀리면 신선한 것만 · 떠 있던 것은 줄 맨 앞으로")
    func deferralHoldsAndReleasesFreshOnly() async {
        let items = mbReply([mbItem("msg-a", "mega-a", agoSeconds: 60), mbItem("msg-b", "mega-b", agoSeconds: 500)])
        let rig = mbMake("defer") { rpc, _, _ in rpc == "megaphone_inbox" ? items : nil }
        let deferred = MBFlag(true)
        rig.store.isBannerDeferred = { deferred.value }
        await rig.store.refresh()
        #expect(rig.store.current == nil && rig.store.queue.count == 2, "붙드는 동안은 줄에만 있다")

        rig.timeline.advance(200)   // a: 260초 · b: 700초
        deferred.value = false
        rig.store.deferralChanged()
        #expect(rig.store.current?.megaphoneID == "mega-a")
        #expect(rig.store.queue.isEmpty, "10분 넘은 b 는 버린다")
        rig.store.dismissCurrent()
        rig.timeline.advance(MegaphoneBannerRules.gap)
        #expect(rig.store.current == nil)

        rig.store.presentOwn(body: "판 시작 직전", senderName: "나")
        #expect(rig.store.current != nil)
        deferred.value = true
        rig.store.deferralChanged()
        #expect(rig.store.current == nil && rig.store.queue.first?.isOwn == true, "판이 시작되면 떠 있던 것을 되돌린다")
        rig.timeline.advance(8)
        deferred.value = false
        rig.store.deferralChanged()
        #expect(rig.store.current?.isOwn == true, "기준선: 풀리면 다시 뜬다")
    }

    // 없으면: 울림이 inbox 보다 먼저 와서 확성기 줄이 메시지로 새거나, 접두만 보고 위조 DM 을 숨기거나 배너로 띄우는 결함이 초록.
    @Test("경합: 접두만 있고 id 를 모르는 줄은 refresh 한 번 뒤 판정 · 위조·실패는 메시지로")
    func prefixOnlyLinesWaitForOneRefresh() async {
        let real = mbReply([mbItem("msg-r", "mega-r", agoSeconds: 5)])
        let rig = mbMake("race") { rpc, _, _ in rpc == "megaphone_inbox" ? real : nil }
        #expect(!rig.store.needsVerification(messageID: "dm-2", body: "안녕"), "접두 없는 줄은 바로 메시지")
        #expect(rig.store.needsVerification(messageID: "msg-r", body: "📢 공지"))
        #expect(rig.store.needsVerification(messageID: "dm-f", body: "📢 공짜 배너"))
        await rig.store.refresh(verifying: ["msg-r", "dm-f"])
        #expect(rig.store.hides(messageID: "msg-r") && !rig.store.needsVerification(messageID: "msg-r", body: "📢 공지"))
        #expect(!rig.store.hides(messageID: "dm-f"), "위조 접두: inbox 에 없으니 메시지로 보인다")
        #expect(!rig.store.needsVerification(messageID: "dm-f", body: "📢 공짜 배너"), "다시 보류하지 않는다")
        #expect(rig.store.current?.megaphoneID == "mega-r", "배너는 inbox 가 말한 것만")
        #expect(rig.store.queue.isEmpty)

        // 연결 실패: 판정을 미루지 않고 메시지로 둔다(잃는 쪽보다 낫다).
        let offline = mbMake("race-offline") { rpc, _, _ in
            rpc == "megaphone_inbox" ? GomokuStubProtocol.Reply(status: 503, body: "{}") : nil
        }
        await offline.store.refresh(verifying: ["msg-n"])
        #expect(offline.store.lastRefreshFailed && offline.store.capability == .unknown)
        #expect(!offline.store.needsVerification(messageID: "msg-n", body: "📢 공지"))
        #expect(!offline.store.hides(messageID: "msg-n"))

        // 진행 중인 refresh 에 늦게 붙은 확인은 한 번 더 돈 결과로 판정한다(먼저 떠난 요청은 그 줄을 몰랐을 수 있다).
        let late = mbReply([mbItem("msg-late", "mega-late", agoSeconds: 1)])
        let slow = mbReply([], delay: 0.2)
        let chained = mbMake("race-late") { rpc, _, index in
            guard rpc == "megaphone_inbox" else { return nil }
            return index == 0 ? slow : late
        }
        let running = Task { await chained.store.refresh() }
        #expect(await mbWait { chained.calls("megaphone_inbox") == 1 })
        await chained.store.refresh(verifying: ["msg-late"])
        #expect(chained.calls("megaphone_inbox") == 2)
        #expect(chained.store.hides(messageID: "msg-late"))
        await running.value
    }

    // 없으면: v2 가 없는 서버에서 줄은 숨기고 옛 요약은 그 줄을 세어 배지가 영영 안 꺼지는 결함이 초록.
    @Test("요약 v2 404 → 옛 함수로 내리고 필터도 끈다 · v2 가 있으면 v2 만")
    func unreadSummaryFallsBackAndDisablesFilter() async throws {
        let inbox = mbReply([mbItem("msg-1", "mega-1", agoSeconds: 10)])
        let v1 = GomokuStubProtocol.Reply(body: #"{"status":"ok","total":3,"peers":[{"peer_user_id":"p1","count":3,"last_epoch_ms":1}]}"#)
        let rig = mbMake("v2-missing") { rpc, _, _ in
            switch rpc {
            case "megaphone_inbox": return inbox
            case "message_unread_summary_v2": return mbMissing
            case "message_unread_summary": return v1
            default: return nil
            }
        }
        let early = try await rig.store.fetchUnreadSummary()
        #expect(early.total == 3 && rig.calls("message_unread_summary_v2") == 0, "모를 때는 처음부터 옛 함수")
        await rig.store.refresh()
        #expect(rig.store.hides(messageID: "msg-1"))
        let summary = try await rig.store.fetchUnreadSummary()
        #expect(summary.total == 3)
        #expect(rig.calls("message_unread_summary_v2") == 1 && rig.calls("message_unread_summary") == 2)
        #expect(rig.store.capability == .unavailable && rig.store.unreadSummaryV2Missing)
        #expect(!rig.store.hides(messageID: "msg-1"), "옛 요약이 확성기 줄을 세니 줄도 다시 보인다")
        #expect(rig.store.unreadSummaryFunction == MegaphoneBannerStore.unreadSummaryV1)
        await rig.store.refresh()
        #expect(rig.store.capability == .unavailable, "inbox 가 다시 성공해도 이 세션은 필터를 끈 채 둔다")

        // 기준선: v2 가 있으면 v2 만 부르고 필터는 켜져 있다.
        let v2 = GomokuStubProtocol.Reply(body: #"{"status":"ok","total":1,"peers":[]}"#)
        let good = mbMake("v2-ok") { rpc, _, _ in
            switch rpc {
            case "megaphone_inbox": return inbox
            case "message_unread_summary_v2": return v2
            case "message_unread_summary": return v1
            default: return nil
            }
        }
        await good.store.refresh()
        let fine = try await good.store.fetchUnreadSummary()
        #expect(fine.total == 1 && good.calls("message_unread_summary") == 0)
        #expect(good.store.hides(messageID: "msg-1") && good.store.capability == .available)
    }

    // 없으면: 보낸 사람 화면에 아무것도 안 뜨거나(효과를 못 봄), 내 배너에 답장 버튼이 붙는 결함이 초록.
    @Test("본인 배너: 보낸 직후 줄 맨 앞 · 내 id · 답장 없음 · 응답 id 를 주면 본 것으로 기록")
    func ownBannerAfterSending() async {
        let items = mbReply([mbItem("msg-a", "mega-a", agoSeconds: 10), mbItem("msg-b", "mega-b", agoSeconds: 5)])
        let rig = mbMake("own") { rpc, _, _ in rpc == "megaphone_inbox" ? items : nil }
        await rig.store.refresh()
        #expect(rig.store.current?.megaphoneID == "mega-a" && rig.store.current?.canReply == true)
        rig.store.presentOwn(body: "모두 힘내요", senderName: "나", megaphoneID: "mega-mine")
        #expect(rig.store.current?.megaphoneID == "mega-a", "떠 있는 것을 끊지 않는다")
        #expect(rig.store.queue.map(\.megaphoneID) == ["mega-mine", "mega-b"], "기준선: inbox 순서보다 앞에 선다")
        rig.timeline.advance(8 + MegaphoneBannerRules.gap)
        let own = rig.store.current
        #expect(own?.isOwn == true && own?.senderID == mbMe && own?.body == "모두 힘내요")
        #expect(own?.canReply == false)
        #expect(rig.store.hasSeen(megaphoneID: "mega-mine"))
    }

    // 없으면: 로그아웃 뒤 앞 계정의 필터·줄이 남거나, 늦게 온 응답·지난 타이머가 다음 계정 상태를 바꾸는 결함이 초록.
    @Test("reset: 줄·id·필터·캐시를 비운다 · 늦은 응답과 지난 타이머는 버린다 · 기록은 계정 키에 남는다")
    func resetClearsEverything() async {
        let item = mbReply([mbItem("msg-1", "mega-1", agoSeconds: 10)])
        let slow = mbReply([mbItem("msg-1", "mega-1", agoSeconds: 10)], delay: 0.2)
        let rig = mbMake("reset") { rpc, _, index in
            guard rpc == "megaphone_inbox" else { return nil }
            return index == 2 ? slow : item
        }
        await rig.store.refresh()
        #expect(rig.store.current?.megaphoneID == "mega-1" && rig.store.capability == .available)
        rig.timeline.advance(5)
        rig.store.reset()
        #expect(rig.store.capability == .unknown && rig.store.knownMessageIDs.isEmpty)
        #expect(rig.store.current == nil && rig.store.queue.isEmpty)
        #expect(rig.store.unreadSummaryFunction == MegaphoneBannerStore.unreadSummaryV1)

        rig.store.presentOwn(body: "새 배너", senderName: "나")
        rig.timeline.advance(3)   // reset 전 타이머(8초)가 만기 — 새 배너를 닫으면 안 된다
        #expect(rig.store.current?.isOwn == true, "기준선: 지난 타이머는 세대로 버린다")
        rig.timeline.advance(5)
        #expect(rig.store.current == nil)

        await rig.store.refresh()   // 같은 계정: 기록은 키에 남아 있다
        #expect(rig.store.current == nil && rig.store.hides(messageID: "msg-1"))

        let inFlight = Task { await rig.store.refresh() }
        #expect(await mbWait { rig.calls("megaphone_inbox") == 3 })
        rig.store.reset()
        await inFlight.value
        #expect(rig.store.knownMessageIDs.isEmpty && rig.store.capability == .unknown, "reset 전에 떠난 응답은 버린다")

        rig.owner.switchAccount(to: mbOther)
        await rig.store.refresh()
        #expect(rig.store.current?.megaphoneID == "mega-1", "다음 계정은 앞 계정의 기록을 읽지 않는다")
    }

    // 없으면: 서버가 sender 키를 from_user 로 내리거나 한 줄이 깨졌을 때 inbox 가 통째로 실패해 배너도 필터도 죽는 결함이 초록.
    @Test("전선: inbox 한 줄이 깨져도 나머지 · from_user · 밀리초 · 표식 떼기 · info/전송의 새 키")
    func wireDecoding() async throws {
        let rows: [[String: Any]] = [
            ["megaphone_id": "mega-x", "body": "id 없음", "created_epoch": 1],
            ["message_id": "msg-2", "megaphone_id": "mega-2", "from_user": mbOther, "sender_display_name": "",
             "body": "📢 표식이 남은 본문", "created_epoch": (mbWall0.timeIntervalSince1970 - 10) * 1000],
            ["message_id": "msg-3", "megaphone_id": "mega-3", "body": "📢 ", "created_epoch": 1],
        ]
        let body = mbJSON(rows)
        let rig = mbMake("wire") { rpc, _, _ in rpc == "megaphone_inbox" ? GomokuStubProtocol.Reply(body: body) : nil }
        let banners = try await rig.owner.service.fetchMegaphoneInbox(accessToken: "t")
        #expect(banners.count == 1)
        let banner = try #require(banners.first)
        #expect(banner.messageID == "msg-2" && banner.senderID == mbOther && banner.senderName == "사용자")
        #expect(banner.body == "표식이 남은 본문")
        #expect(abs(banner.createdAt.timeIntervalSince(mbWall0) + 10) < 0.001, "밀리초 epoch 도 같은 시각")
        let sent = try #require(GomokuStubProtocol.calls(host: rig.host, rpc: "megaphone_inbox").first)
        #expect(sent.json["p_hours"] as? Int == 24)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let iso = ISO8601DateFormatter()
        let item = try decoder.decode(MegaphoneInboxItem.self, from: Data(
            #"{"message_id":"m","megaphone_id":"g","sender_id":"s","body":"안녕","created_at":"2027-01-15T08:00:00Z"}"#.utf8))
        #expect(item.banner(parsingDate: { iso.date(from: $0) })?.createdAt == iso.date(from: "2027-01-15T08:00:00Z"))
        #expect(item.banner(parsingDate: { _ in nil }) == nil, "시각을 모르면 지어내지 않는다")

        let info = try decoder.decode(MegaphoneInfoResponse.self, from: Data(
            #"{"status":"ok","price":30,"recipients":9,"cooldown_remaining_seconds":250,"global_cooldown_seconds":300,"global_cooldown_remaining_seconds":250,"cooldown_scope":"global"}"#.utf8))
        #expect(info.globalCooldownSeconds == 300 && info.globalCooldownRemainingSeconds == 250 && info.cooldownScope == "global")
        let global = try decoder.decode(MegaphoneSendResponse.self, from: Data(
            #"{"status":"cooldown","retry_after_seconds":200,"cooldown_seconds":300,"scope":"global"}"#.utf8))
        #expect(MegaphoneSendOutcome(response: global) == .cooldown(retryAfterSeconds: 200, scope: .global))
        let old = try decoder.decode(MegaphoneSendResponse.self, from: Data(
            #"{"status":"cooldown","retry_after_seconds":200}"#.utf8))
        #expect(MegaphoneSendOutcome(response: old) == .cooldown(retryAfterSeconds: 200), "기준선: scope 없는 옛 서버는 사람당")
        #expect(MegaphoneSendOutcome(response: old) != .cooldown(retryAfterSeconds: 200, scope: .global))
    }

    // 없으면: 앱 전체 대기를 "N분 뒤에 다시 보낼 수 있어요"(내 탓처럼)로 말하거나, 둘 중 짧은 쪽 시간을 말하는 결함이 초록.
    @Test("작성 문구: 앱 전체 대기 '다음 확성기까지 N분' · 긴 쪽 · 같으면 앱 전체 · '화면에 떠요' — 작성 화면이 그 줄을 쓴다")
    func composerTexts() async {
        #expect(MegaphoneText.globalCooldown(seconds: 1) == "다음 확성기까지 1분")
        #expect(MegaphoneText.globalCooldown(seconds: 61) == "다음 확성기까지 2분")
        #expect(MegaphoneText.globalCooldown(seconds: 300) == "다음 확성기까지 5분")
        #expect(MegaphoneText.cooldownLine(remaining: 400, globalRemaining: 200) == "7분 뒤에 다시 보낼 수 있어요")
        #expect(MegaphoneText.cooldownLine(remaining: 250, globalRemaining: 250) == "다음 확성기까지 5분")
        #expect(MegaphoneText.cooldownLine(remaining: 0, globalRemaining: 0) == nil)
        #expect(MegaphoneText.reach(recipients: 9) == "지금 보내면 9명의 화면에 떠요")
        for text in [MegaphoneText.globalCooldown(seconds: 120), MegaphoneText.reach(recipients: 3), MegaphoneText.explainer] {
            for word in mbForbidden { #expect(!text.contains(word), "사용자 문구에 금지어 \(word): \(text)") }
        }

        // 부르는 자리: 작성 화면 한 줄(infoLine) · 첫 단계 거절(requestSend) · 전송 응답(apply)이 같은 판정을 쓴다.
        let rig = mbMake("texts") { _, _, _ in nil }
        let mega = MegaphoneStore(host: rig.owner)
        mega.clock = { rig.timeline.now }
        mega.applyInfo(MegaphoneInfoResponse(price: 30, cooldownSeconds: 600, cooldownRemainingSeconds: 250, recipients: 9,
                                             globalCooldownSeconds: 300, globalCooldownRemainingSeconds: 250,
                                             cooldownScope: "global"))
        #expect(mega.infoLine(now: rig.timeline.now) == "다음 확성기까지 5분")
        mega.setDraft("안녕")
        mega.requestSend()
        #expect(mega.notice == "다음 확성기까지 5분" && !mega.isConfirming)
        mega.applyInfo(MegaphoneInfoResponse(price: 30, cooldownSeconds: 600, cooldownRemainingSeconds: 400, recipients: 9,
                                             globalCooldownSeconds: 300, globalCooldownRemainingSeconds: 200,
                                             cooldownScope: "self"))
        #expect(mega.infoLine(now: rig.timeline.now) == "7분 뒤에 다시 보낼 수 있어요", "사람당이 더 길면 사람당 문구")
        mega.applyInfo(MegaphoneInfoResponse(price: 30, cooldownSeconds: 600, cooldownRemainingSeconds: 125, recipients: 9))
        #expect(mega.infoLine(now: rig.timeline.now) == "3분 뒤에 다시 보낼 수 있어요", "기준선: 옛 서버(새 키 없음)는 지금 문구")
        mega.applyInfo(MegaphoneInfoResponse(price: 30, cooldownSeconds: 600, cooldownRemainingSeconds: 0, recipients: 9,
                                             globalCooldownSeconds: 300, globalCooldownRemainingSeconds: 0))
        #expect(mega.infoLine(now: rig.timeline.now) == "지금 보내면 9명의 화면에 떠요")

        mega.apply(MegaphoneSendResponse(status: "cooldown", retryAfterSeconds: 200, scope: "global"), requestID: "r1")
        #expect(mega.notice == "다음 확성기까지 4분")
        #expect(mega.infoLine(now: rig.timeline.now) == "다음 확성기까지 4분")
        mega.apply(MegaphoneSendResponse(status: "cooldown", retryAfterSeconds: 200), requestID: "r2")
        #expect(mega.notice == "4분 뒤에 다시 보낼 수 있어요", "기준선: scope 없는 응답은 사람당 문구")
    }
}
