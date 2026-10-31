import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

/// 폰 전송 멱등 키 · 응답 유실 재시도(서버 안정화 2026-10-30 — 10-29 18:54 KST PGRST003·504·57014).
///
/// `MessagesStoreTests` 와 같은 하네스(앱 모델 전체 · 스텁 서버) 위에서 **전선으로** 잰다: 키는 요청 JSON 의 `p_client_message_id`,
/// 재시도는 send_message 요청 수, 잠은 주입한 `sleep` 이 받은 초. 벽시계를 기다리지 않는다(재시도 잠은 기록하고 곧바로 돌아오거나 문을 기다린다).
///
/// 지키는 것(`MessagesStore.performSend` 머리 ⓐ~ⓓ):
/// ① 키 = 자리 말풍선 id(소문자 uuid) — 한 벌. ② 서버가 키를 안다는 증거(ok 의 message_id)를 본 뒤의 모호한 실패는 **같은 키로 한 번** 다시.
/// ③ 증거가 없으면 지금처럼 실패(재시도 0 — 옛 서버면 두 통이 된다). ④ 답을 못 받은 전송을 10분 기억해 같은 상대·같은 본문 재전송에 같은 키.
/// ⑤ 이모티콘은 재시도 경로에서도 입력칸을 안 만진다. ⑥ 재시도 잠 동안 로그아웃하면 두 번째 요청이 안 나간다.
/// (반박 보강) ⑥' 재시도 왕복 중 로그아웃 · ⑦ duplicate 응답 뒤 한 통 · ⑧ 재시도 중 새 입력 보존 · ⑨ message_id 없는 ok 가 깃발을 내린다 · 분류 가장자리.
@MainActor
@Suite(.serialized) struct MessagesSendIdempotencyTests {
    static let peerA = "peer-a"
    static let peerB = "peer-b"
    /// 키를 아는 서버의 ok — 저장된 행의 id·시각을 싣는다(레인 l2s 응답 모양).
    static let okWithID = #"{"status":"ok","body":"x","ring":"sent","message_id":"9a0c2b1e-0000-4000-8000-000000000001","created_at":"2026-10-30T05:00:00.000Z"}"#
    /// 10-29 장애 때의 모양 — PostgREST 가 풀에서 연결을 못 얻었다(서비스가 `.invalidResponse(504)` 로 접는다).
    static let gatewayTimeout = MobileStubResponse.json(
        #"{"code":"PGRST003","message":"Timed out acquiring connection from connection pool."}"#, status: 504
    )

    // MARK: - 도구

    /// 이 하네스가 보낸 send_message 의 키들(차례대로 · 키가 빠진 요청은 nil).
    static func wireKeys(_ h: MessagesHarness) -> [String?] {
        h.bodies("send_message").map { text in
            let object = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
            return object?["p_client_message_id"] as? String
        }
    }

    /// send_message 응답 대본 — 요청마다 하나씩 꺼내고, 비면 서버 기본값(`setSend`)으로 돌아간다.
    static func script(_ h: MessagesHarness, _ steps: [MobileStubResponse]) {
        let queue = BaseLockedBox(steps)
        h.server.override("send_message") { _ in
            var next: MobileStubResponse?
            queue.mutate { pending in
                if !pending.isEmpty { next = pending.removeFirst() }
            }
            return next
        }
    }

    /// 재시도 잠은 받은 초를 적고 곧바로 돌아온다. 다른 잠(읽음 뒤 창 — 하네스가 3600초로 둔다)은 원래대로 둔다.
    static func instantRetrySleep(_ h: MessagesHarness) -> BaseLockedBox<[TimeInterval]> {
        let slept = BaseLockedBox<[TimeInterval]>([])
        let retry = h.store.sendRetryDelaySeconds
        h.store.sleep = { seconds in
            if seconds == retry {
                slept.mutate { $0.append(seconds) }
                return
            }
            try? await Task.sleep(for: .seconds(seconds))
        }
        return slept
    }

    /// 서버가 키를 안다는 증거 한 번(ok + message_id) — 다른 상대에게 보내 대상 대화를 더럽히지 않는다.
    static func primeKeyEvidence(_ h: MessagesHarness, sourceLocation: SourceLocation = #_sourceLocation) async {
        h.server.setSend(.json(okWithID))
        h.store.setDraft("증거", for: peerB)
        #expect(h.store.sendDraft(to: peerB, isComposing: false), sourceLocation: sourceLocation)
        #expect(await baseWaitUntil { !h.store.isSending }, sourceLocation: sourceLocation)
        await h.settle()
        #expect(h.store.serverKnowsSendKey, "message_id 를 실은 ok 가 증거로 안 셌다", sourceLocation: sourceLocation)
        #expect(h.store.pendingOutgoing.isEmpty, sourceLocation: sourceLocation)
    }

    /// 초안 하나를 보내고 끝까지 기다린 뒤 전선 키를 돌려준다. 전선 키가 그 순간의 자리 말풍선 id 와 같은지도 잰다(①).
    @discardableResult
    static func sendDraft(_ h: MessagesHarness, _ text: String, to peer: String, sourceLocation: SourceLocation = #_sourceLocation) async -> String? {
        h.store.setDraft(text, for: peer)
        #expect(h.store.sendDraft(to: peer, isComposing: false), sourceLocation: sourceLocation)
        let bubble = h.store.pendingOutgoing.last?.id
        #expect(await baseWaitUntil { !h.store.isSending }, sourceLocation: sourceLocation)
        await h.settle()
        let wire = wireKeys(h).last ?? nil
        #expect(wire != nil && wire == bubble, "전선 키 \(String(describing: wire)) ≠ 말풍선 id \(String(describing: bubble))", sourceLocation: sourceLocation)
        return wire
    }

    // MARK: - ① 키 = 자리 말풍선 id

    @Test("① 전송 본문의 p_client_message_id 는 자리 말풍선 id(소문자 uuid) 그대로 — 초안·이모티콘 두 입구 모두 · message_id 없는 ok 는 증거가 아니다")
    func keyIsThePendingBubbleID() async throws {
        let h = await MessagesHarness.make()
        defer { h.tearDown() }
        h.store.setDraft("키를 싣는다", for: Self.peerA)
        #expect(h.store.sendDraft(to: Self.peerA, isComposing: false))
        let draftBubble = try #require(h.store.pendingOutgoing.last?.id)
        #expect(UUID(uuidString: draftBubble) != nil && draftBubble == draftBubble.lowercased(), "키가 소문자 uuid 가 아니다: \(draftBubble)")
        #expect(await baseWaitUntil { !h.store.isSending })
        await h.settle()

        #expect(h.store.sendSticker(.joy, to: Self.peerA))
        let stickerBubble = try #require(h.store.pendingOutgoing.last?.id)
        #expect(await baseWaitUntil { !h.store.isSending })
        await h.settle()

        #expect(Self.wireKeys(h) == [draftBubble, stickerBubble], "전선 키가 말풍선 id 와 다르다: \(Self.wireKeys(h))")
        #expect(draftBubble != stickerBubble, "두 전송이 한 키를 나눠 썼다")
        let raw = h.bodies("send_message").first ?? ""
        #expect(raw.contains(#""p_client_message_id":"\#(draftBubble)""#), "키 이름이 서버 인자와 다르다: \(raw)")
        // 기본 스텁의 ok 는 옛 서버 모양(message_id 없음)이다 — 그걸로 깃발이 서면 옛 서버에서 재시도가 두 통을 만든다.
        #expect(!h.store.serverKnowsSendKey)
        #expect(h.store.unconfirmedSends.isEmpty, "확정 답(ok)을 받은 전송을 기억했다")
        h.expectNoForbiddenCalls()
    }

    // MARK: - ② 증거 뒤 모호한 실패 → 같은 키로 한 번

    @Test("② 키를 아는 서버(message_id 를 본 뒤) — 504 다음 ok: 요청 정확히 2건 · 같은 키 · 1.5초 잠 한 번 · 말풍선 하나 · 실패 문구 없음")
    func ambiguousFailureRetriesOnceWithSameKey() async throws {
        let h = await MessagesHarness.make()
        defer { h.tearDown() }
        let gate = BaseGate()
        let slept = BaseLockedBox<[TimeInterval]>([])
        let retry = h.store.sendRetryDelaySeconds
        #expect(retry == 1.5)
        h.store.sleep = { seconds in
            guard seconds == retry else {
                try? await Task.sleep(for: .seconds(seconds))
                return
            }
            slept.mutate { $0.append(seconds) }
            await gate.wait()
        }
        await Self.primeKeyEvidence(h)
        let before = h.count("send_message")
        Self.script(h, [Self.gatewayTimeout, .json(Self.okWithID)])
        h.store.setDraft("응답을 잃은 말", for: Self.peerA)
        #expect(h.store.sendDraft(to: Self.peerA, isComposing: false))
        let bubble = try #require(h.store.pendingOutgoing.last?.id)

        // 재시도 잠 한가운데: 말풍선은 그 하나가 "보내는 중"으로 서 있고, 실패 문구도 글 되돌림도 없다.
        #expect(await baseWaitUntil { gate.arrivals == 1 }, "504 뒤 재시도 잠에 들지 않았다")
        #expect(h.count("send_message") - before == 1)
        #expect(h.store.pendingOutgoing.map(\.id) == [bubble], "재시도가 말풍선을 바꾸거나 하나 더 세웠다: \(h.store.pendingOutgoing)")
        #expect(h.store.pendingOutgoing.first?.state == .sending)
        #expect(h.store.isSending, "재시도 전에 왕복이 끝난 것으로 내려앉았다")
        #expect(h.store.sendNotices[Self.peerA] == nil, "재시도 전에 실패 문구가 섰다")
        #expect(h.store.draft(for: Self.peerA).isEmpty, "재시도 전에 글이 입력칸으로 돌아왔다")

        h.server.appendRow(.sent("m1", to: Self.peerA, body: "응답을 잃은 말", at: 60))
        gate.open()
        #expect(await baseWaitUntil { !h.store.isSending })
        await h.settle()
        let keys = Array(Self.wireKeys(h).dropFirst(before))
        #expect(keys == [bubble, bubble], "재시도 전선 키: \(keys)")
        #expect(slept.get() == [1.5], "재시도 잠: \(slept.get())")
        #expect(h.store.sendNotices[Self.peerA] == nil)
        #expect(h.store.draft(for: Self.peerA).isEmpty, "성공했는데 글이 입력칸으로 돌아왔다")
        #expect(h.store.pendingOutgoing.isEmpty, "진짜 행이 왔는데 자리 말풍선이 남았다")
        #expect(h.store.thread(for: Self.peerA)?.messages.map(\.id) == ["m1"])
        #expect(h.store.unconfirmedSends.isEmpty, "성공한 전송을 기억했다")
        h.expectNoForbiddenCalls()
    }

    @Test("②' 증거가 있어도 재시도는 한 번뿐이고(504·504 → 요청 2건 뒤 연결 문구), 확정 실패(429 · 거절 status)는 되치지 않는다")
    func retryIsBoundedAndOnlyForAmbiguousFailures() async {
        let h = await MessagesHarness.make()
        defer { h.tearDown() }
        let slept = Self.instantRetrySleep(h)
        await Self.primeKeyEvidence(h)

        var before = h.count("send_message")
        Self.script(h, [Self.gatewayTimeout, Self.gatewayTimeout, .json(Self.okWithID)])
        await Self.sendDraft(h, "두 번 다 잃는다", to: Self.peerA)
        #expect(h.count("send_message") - before == 2, "재시도가 한 번이 아니다: \(h.count("send_message") - before)건")
        #expect(h.store.sendNotices[Self.peerA] == MessagesSendRules.connectionNotice)
        #expect(h.store.draft(for: Self.peerA) == "두 번 다 잃는다")
        #expect(h.store.pendingOutgoing.isEmpty)
        #expect(slept.get() == [1.5])

        // 연결 끊김(URLError)도 같은 모호한 실패다.
        before = h.count("send_message")
        Self.script(h, [.networkFailure(.networkConnectionLost), .json(Self.okWithID)])
        await Self.sendDraft(h, "끊긴 연결", to: Self.peerB)
        #expect(h.count("send_message") - before == 2)
        #expect(h.store.sendNotices[Self.peerB] == nil)

        // 429 는 서버가 답을 준 것이다 — 되치면 장애 때 요청만 는다.
        before = h.count("send_message")
        Self.script(h, [.json(#"{"message":"Too Many Requests"}"#, status: 429)])
        await Self.sendDraft(h, "레이트리밋", to: Self.peerB)
        #expect(h.count("send_message") - before == 1, "429 를 되쳤다")
        // 거절 status 도 확정 답이다.
        before = h.count("send_message")
        Self.script(h, [.json(#"{"status":"target_focused"}"#)])
        await Self.sendDraft(h, "집중 중", to: Self.peerB)
        #expect(h.count("send_message") - before == 1, "거절 status 를 되쳤다")
        #expect(slept.get() == [1.5, 1.5], "확정 실패에 재시도 잠이 들었다: \(slept.get())")
        h.expectNoForbiddenCalls()
    }

    // MARK: - ③ 증거 없음 → 지금 동작 그대로

    @Test("③ 증거 없는 서버(첫 전송 · message_id 없는 ok 뒤) — 504·시간 초과는 재시도 없이 지금처럼: 요청 1건 · 연결 문구 · 글 되돌림 · 말풍선 거둠")
    func noEvidenceMeansNoRetry() async {
        let h = await MessagesHarness.make()
        defer { h.tearDown() }
        let slept = Self.instantRetrySleep(h)

        // 첫 전송(아무 증거 없음)의 504.
        h.server.setSend(Self.gatewayTimeout)
        await Self.sendDraft(h, "첫 말을 잃는다", to: Self.peerA)
        #expect(h.count("send_message") == 1, "증거 없이 재시도했다")
        #expect(h.store.sendNotices[Self.peerA] == MessagesSendRules.connectionNotice)
        #expect(h.store.draft(for: Self.peerA) == "첫 말을 잃는다")
        #expect(h.store.pendingOutgoing.isEmpty)

        // 옛 서버의 ok(키를 모른다 — message_id 없음) 한 번으로는 깃발이 서지 않는다.
        h.server.setSend(.json(#"{"status":"ok","body":"x","ring":"sent"}"#))
        await Self.sendDraft(h, "옛 서버", to: Self.peerB)
        #expect(!h.store.serverKnowsSendKey)
        let before = h.count("send_message")
        h.server.setSend(.networkFailure(.timedOut))
        await Self.sendDraft(h, "시간 초과", to: Self.peerB)
        #expect(h.count("send_message") - before == 1, "옛 서버에서 재시도했다 — 키를 모르는 서버면 두 통이 된다")
        #expect(h.store.sendNotices[Self.peerB] == MessagesSendRules.connectionNotice)
        #expect(h.store.draft(for: Self.peerB) == "시간 초과")
        #expect(slept.get().isEmpty, "증거 없이 재시도 잠에 들었다: \(slept.get())")
        h.expectNoForbiddenCalls()
    }

    // MARK: - ④ 답을 못 받은 전송의 수동 재전송 = 같은 키

    @Test("④ 모호한 실패 뒤 같은 상대·같은 본문 재전송은 같은 키 — 다른 본문·다른 상대·확정 거절(too_long·target_focused)·성공·10분 뒤에는 새 키")
    func manualResendAfterAmbiguousFailureReusesKey() async {
        let h = await MessagesHarness.make()
        defer { h.tearDown() }
        let slept = Self.instantRetrySleep(h)
        h.server.setSend(.networkFailure(.timedOut))

        let k1 = await Self.sendDraft(h, "같은 말", to: Self.peerA)
        #expect(h.store.draft(for: Self.peerA) == "같은 말", "실패한 글이 입력칸으로 안 돌아왔다")
        // 되돌아온 글을 그대로 다시 보낸다(사용자의 [보내기] 재탭).
        #expect(h.store.sendDraft(to: Self.peerA, isComposing: false))
        #expect(await baseWaitUntil { !h.store.isSending })
        await h.settle()
        #expect(Self.wireKeys(h).last == k1, "같은 상대·같은 본문 재전송이 새 키를 만들었다")

        let k2 = await Self.sendDraft(h, "다른 말", to: Self.peerA)
        #expect(k2 != k1, "다른 본문이 앞 키를 썼다")
        let k3 = await Self.sendDraft(h, "같은 말", to: Self.peerB)
        #expect(k3 != k1 && k3 != k2, "다른 상대가 앞 키를 썼다")
        #expect(h.store.unconfirmedSends.count == 3, "기억: \(h.store.unconfirmedSends)")

        // 기억한 키로 다시 보냈는데 서버가 확정 거절 → 저장된 것이 없다 → 기억을 지운다 → 다음은 새 키.
        h.server.setSend(.json(#"{"status":"too_long","max_length":3}"#))
        #expect(await Self.sendDraft(h, "같은 말", to: Self.peerA) == k1, "다른 전송 뒤에도 기억이 남아야 한다")
        #expect(!h.store.unconfirmedSends.contains { $0.peerUserID == Self.peerA && $0.body == "같은 말" }, "확정 거절 뒤에도 기억했다")
        h.server.setSend(.json(#"{"status":"ok","body":"x","ring":"sent"}"#))
        let k4 = await Self.sendDraft(h, "같은 말", to: Self.peerA)
        #expect(![k1, k2, k3].contains(k4), "확정 거절 뒤 재전송이 옛 키를 썼다")

        // 처음부터 확정 거절이면 기억하지 않는다.
        h.server.setSend(.json(#"{"status":"target_focused"}"#))
        let k5 = await Self.sendDraft(h, "집중 중인 사람", to: Self.peerA)
        let k6 = await Self.sendDraft(h, "집중 중인 사람", to: Self.peerA)
        #expect(k5 != k6, "확정 거절(target_focused) 뒤 재전송이 같은 키를 썼다")

        // 기억한 키로 다시 보내 성공 → 기억을 지운다 → 같은 말을 또 보내면(일부러 두 번) 새 키.
        h.server.setSend(.json(#"{"status":"ok","body":"x","ring":"sent"}"#))
        #expect(await Self.sendDraft(h, "다른 말", to: Self.peerA) == k2)
        let k7 = await Self.sendDraft(h, "다른 말", to: Self.peerA)
        #expect(k7 != k2, "성공한 뒤의 같은 말이 옛 키를 썼다 — 서버가 duplicate 로 삼킨다")

        // 10분이 지나면 잊는다(상대 B 의 "같은 말" 은 아직 기억에 있다).
        #expect(h.store.unconfirmedSends.map(\.key) == [k3].compactMap { $0 })
        h.clock.advance(h.store.unconfirmedSendReuseSeconds + 1)
        let k8 = await Self.sendDraft(h, "같은 말", to: Self.peerB)
        #expect(k8 != k3, "10분 지난 기억의 키를 썼다")
        #expect(h.store.unconfirmedSends.isEmpty)
        #expect(slept.get().isEmpty, "증거 없는 판에서 재시도 잠에 들었다")
        h.expectNoForbiddenCalls()
    }

    // MARK: - ⑤ 이모티콘은 재시도 경로에서도 입력칸을 안 만진다

    @Test("⑤ 이모티콘: 504→ok 재시도 성공 · 504→504 실패 모두 쓰던 글 그대로 · 빈 입력칸에 토큰을 안 꽂는다")
    func stickerRetryNeverTouchesDraft() async {
        let h = await MessagesHarness.make()
        defer { h.tearDown() }
        let slept = Self.instantRetrySleep(h)
        await Self.primeKeyEvidence(h)
        h.store.setDraft("쓰던 글", for: Self.peerA)
        let before = h.count("send_message")

        Self.script(h, [Self.gatewayTimeout, .json(Self.okWithID)])
        #expect(h.store.sendSticker(.joy, to: Self.peerA))
        #expect(await baseWaitUntil { !h.store.isSending })
        await h.settle()
        #expect(h.count("send_message") - before == 2)
        #expect(h.store.draft(for: Self.peerA) == "쓰던 글", "재시도 성공이 쓰던 글을 지웠다")
        #expect(h.store.sendNotices[Self.peerA] == nil)

        Self.script(h, [Self.gatewayTimeout, Self.gatewayTimeout])
        #expect(h.store.sendSticker(.sad, to: Self.peerA))
        #expect(await baseWaitUntil { !h.store.isSending })
        await h.settle()
        #expect(h.count("send_message") - before == 4)
        #expect(h.store.draft(for: Self.peerA) == "쓰던 글", "재시도 실패가 쓰던 글을 \(h.store.draft(for: Self.peerA)) 로 덮었다")
        #expect(h.store.sendNotices[Self.peerA] == MessagesSendRules.connectionNotice)
        #expect(h.store.pendingOutgoing.isEmpty)

        h.store.setDraft("", for: Self.peerA)
        Self.script(h, [Self.gatewayTimeout, Self.gatewayTimeout])
        #expect(h.store.sendSticker(.heart, to: Self.peerA))
        #expect(await baseWaitUntil { !h.store.isSending })
        await h.settle()
        #expect(h.store.draft(for: Self.peerA).isEmpty, "실패한 이모티콘이 입력칸에 \(h.store.draft(for: Self.peerA)) 를 꽂았다")
        #expect(slept.get() == [1.5, 1.5, 1.5])
        h.expectNoForbiddenCalls()
    }

    // MARK: - ⑥ 재시도 잠 동안 로그아웃

    @Test("⑥ 재시도 잠 동안 로그아웃(세대 변화) — 두 번째 요청이 나가지 않고, 깃발·기억·글·문구·말풍선이 다음 계정에 안 선다")
    func logoutDuringRetryWaitStopsTheSecondRequest() async {
        let h = await MessagesHarness.make()
        defer { h.tearDown() }
        let gate = BaseGate()
        let retry = h.store.sendRetryDelaySeconds
        h.store.sleep = { seconds in
            guard seconds == retry else {
                try? await Task.sleep(for: .seconds(seconds))
                return
            }
            await gate.wait()
        }
        await Self.primeKeyEvidence(h)
        let before = h.count("send_message")
        h.server.setSend(Self.gatewayTimeout)
        h.store.setDraft("앞 계정의 글", for: Self.peerA)
        #expect(h.store.sendDraft(to: Self.peerA, isComposing: false))
        #expect(await baseWaitUntil { gate.arrivals == 1 }, "504 뒤 재시도 잠에 들지 않았다")
        #expect(h.count("send_message") - before == 1)
        #expect(h.store.isSending, "재시도 잠 전에 왕복이 끝나 아래 단언이 공허하다")

        await h.switchAccount()
        #expect(!h.store.serverKnowsSendKey, "로그아웃이 증거 깃발을 안 지웠다 — 다음 계정이 증거 없이 재시도한다")
        // 잠을 풀고, 혹시 나갈 두 번째 요청이 스텁에 닿을 시간을 준다(같은 서비스·세션 한 바퀴 장벽).
        gate.open()
        await baseYield()
        await h.barrier()
        await baseYield()
        #expect(h.count("send_message") - before == 1, "로그아웃 뒤 재시도가 나갔다: \(h.count("send_message") - before)건")
        let leaked = !h.store.drafts.isEmpty || !h.store.sendNotices.isEmpty || !h.store.pendingOutgoing.isEmpty
            || !h.store.unconfirmedSends.isEmpty || h.store.serverKnowsSendKey
        #expect(!leaked, "앞 계정 상태가 다음 계정에 섰다: \(h.store.drafts) \(h.store.sendNotices) \(h.store.unconfirmedSends)")
        h.expectNoForbiddenCalls()
    }
}

// MARK: - 반박 검증 보강(2026-10-30) — 분류 가장자리 · 재시도 왕복 중 로그아웃 · duplicate 응답 · 재시도 중 새 입력 · 되돌린 서버
//
// ⑥ 은 잠 동안의 로그아웃만 잰다 — 재시도 왕복 **뒤** 세대 가드는 ⑥' 가, 분류 가장자리(취소·401 갱신 실패·4xx·디코드)는 순수 시험이 문다.

extension MessagesSendIdempotencyTests {
    /// 모호/확정 분류의 가장자리(순수). 재시도 문은 이 판정 하나라, 여기서 새면 확정 실패를 되치거나(장애 때 요청이 는다)
    /// 취소한 왕복을 되살린다.
    @Test("분류: 답을 못 받은 실패만 모호하다 — 취소·401(토큰 갱신 실패 뒤 원래 오류)·429·4xx·23505·디코드 실패는 확정")
    func ambiguousFailureClassificationEdges() {
        for code: URLError.Code in [.timedOut, .networkConnectionLost, .cannotConnectToHost, .notConnectedToInternet] {
            #expect(MessagesSendRules.isAmbiguousFailure(URLError(code)), "\(code) 를 확정으로 봤다")
        }
        for status in [500, 502, 503, 504] {
            #expect(MessagesSendRules.isAmbiguousFailure(SupabaseWorkServiceError.invalidResponse(status)), "\(status) 를 확정으로 봤다")
        }
        let definite: [any Error] = [
            URLError(.cancelled), CancellationError(),
            // 401 → 갱신 실패면 `withMobileSessionRetry` 가 **원래 오류**(.sessionExpired)를 던진다 — 서버가 답을 준 것이다.
            SupabaseWorkServiceError.sessionExpired,
            SupabaseWorkServiceError.rateLimited(retryAfterSeconds: nil),
            SupabaseWorkServiceError.invalidResponse(400), SupabaseWorkServiceError.invalidResponse(404),
            SupabaseWorkServiceError.invalidResponse(409), SupabaseWorkServiceError.invalidResponse(-1),
            SupabaseWorkServiceError.sessionAlreadyOpen,
            DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "200 인데 본문을 못 읽음")),
        ]
        for error in definite {
            #expect(!MessagesSendRules.isAmbiguousFailure(error), "\(error) 를 모호하다고 봐 되친다")
        }
    }

    @Test("⑥' 재시도 요청(두 번째)이 떠 있는 동안 로그아웃 — 그 늦은 504 가 다음 계정의 입력칸·문구·말풍선·기억·깃발에 안 선다")
    func logoutDuringRetryRoundTripDoesNotLeak() async {
        let h = await MessagesHarness.make()
        defer { h.tearDown() }
        let gate = BaseGate()
        let retry = h.store.sendRetryDelaySeconds
        h.store.sleep = { seconds in
            guard seconds == retry else {
                try? await Task.sleep(for: .seconds(seconds))
                return
            }
            await gate.wait()
        }
        await Self.primeKeyEvidence(h)
        let before = h.count("send_message")
        h.server.setSend(Self.gatewayTimeout)
        h.store.setDraft("앞 계정의 글", for: Self.peerA)
        #expect(h.store.sendDraft(to: Self.peerA, isComposing: false))
        #expect(await baseWaitUntil { gate.arrivals == 1 }, "504 뒤 재시도 잠에 들지 않았다")
        // 첫 요청은 이미 돌아왔다 — 이제부터 오는 send_message(재시도)를 붙잡는다.
        let hold = BaseHold.rpc("send_message", host: h.host)
        gate.open()
        #expect(await hold.waitHeld(), "재시도 요청이 떠나지 않았다")
        #expect(h.store.isSending, "재시도 왕복이 로그아웃 전에 끝나 아래 단언이 공허하다")
        await h.switchAccount()
        #expect(await hold.releaseAndWaitDelivered())
        await h.barrier()
        await baseYield()
        #expect(h.count("send_message") - before == 2)
        let leaked = !h.store.drafts.isEmpty || !h.store.sendNotices.isEmpty || !h.store.pendingOutgoing.isEmpty
            || !h.store.unconfirmedSends.isEmpty || h.store.serverKnowsSendKey || h.store.isSending
        #expect(!leaked, "앞 계정 상태가 다음 계정에 섰다: \(h.store.drafts) \(h.store.sendNotices) \(h.store.unconfirmedSends)")
        h.expectNoForbiddenCalls()
    }

    @Test("⑦ 답을 못 받은 말이 실은 저장됐고 이력에도 이미 섰을 때 — 같은 키 재전송의 duplicate 응답 뒤 그 말은 한 번만 보이고 자리 말풍선이 안 남는다")
    func duplicateResponseLeavesExactlyOneMessage() async {
        let h = await MessagesHarness.make()
        defer { h.tearDown() }
        _ = Self.instantRetrySleep(h)
        // 서버는 저장했는데 답이 끊겼다(증거 없음 → 재시도 없이 실패 · 글 되돌림 · 키 기억).
        h.server.setSend(.networkFailure(.networkConnectionLost))
        let k1 = await Self.sendDraft(h, "저장된 말", to: Self.peerA)
        #expect(h.store.draft(for: Self.peerA) == "저장된 말")
        h.server.appendRow(.sent("m1", to: Self.peerA, body: "저장된 말", at: 60))
        // 그 사이 이력이 한 번 돌아 행이 이미 화면에 있다 — 다음 이력엔 "처음 나타난" 행이 없는 가장 까다로운 쪽.
        _ = h.store.requestActivityRefresh(includeHistory: true)
        await h.settle()
        #expect(h.store.thread(for: Self.peerA)?.messages.map(\.id) == ["m1"])

        h.server.setSend(.json(#"{"status":"ok","body":"저장된 말","ring":"duplicate","message_id":"m1","created_at":"2026-09-17T04:57:40.000Z","duplicate":true}"#))
        #expect(h.store.sendDraft(to: Self.peerA, isComposing: false))
        #expect(await baseWaitUntil { !h.store.isSending })
        await h.settle()
        #expect(Self.wireKeys(h).last == k1, "되돌아온 글의 재전송이 새 키를 만들었다 — 서버가 두 통으로 둔다")
        #expect(h.store.pendingOutgoing.isEmpty, "duplicate 응답 뒤 자리 말풍선이 남았다: \(h.store.pendingOutgoing)")
        #expect(h.store.thread(for: Self.peerA)?.messages.map(\.id) == ["m1"])
        #expect(h.store.sendNotices[Self.peerA] == nil)
        #expect(h.store.draft(for: Self.peerA).isEmpty)
        #expect(h.store.unconfirmedSends.isEmpty)
        #expect(h.store.serverKnowsSendKey, "duplicate 응답도 키를 안다는 증거다")
        h.expectNoForbiddenCalls()
    }

    @Test("⑧ 재시도 잠 동안 같은 대화에 새 말을 보내려 하면 — 글·이모티콘 모두 막히고 새로 친 글은 입력칸에 남으며, 재시도까지 실패해도 옛 글이 덮지 않는다")
    func newInputDuringRetryIsKept() async {
        let h = await MessagesHarness.make()
        defer { h.tearDown() }
        let gate = BaseGate()
        let retry = h.store.sendRetryDelaySeconds
        h.store.sleep = { seconds in
            guard seconds == retry else {
                try? await Task.sleep(for: .seconds(seconds))
                return
            }
            await gate.wait()
        }
        await Self.primeKeyEvidence(h)
        let before = h.count("send_message")
        Self.script(h, [Self.gatewayTimeout, Self.gatewayTimeout])
        h.store.setDraft("옛 글", for: Self.peerA)
        #expect(h.store.sendDraft(to: Self.peerA, isComposing: false))
        let bubble = h.store.pendingOutgoing.last?.id
        #expect(await baseWaitUntil { gate.arrivals == 1 })
        h.store.setDraft("새로 친 글", for: Self.peerA)
        #expect(!h.store.canSend(to: Self.peerA))
        #expect(!h.store.sendDraft(to: Self.peerA, isComposing: false), "재시도 중에 두 번째 전송이 떴다")
        #expect(!h.store.sendSticker(.joy, to: Self.peerA), "재시도 중에 이모티콘이 떴다")
        #expect(h.store.draft(for: Self.peerA) == "새로 친 글", "막힌 전송이 새로 친 글을 지웠다")
        gate.open()
        #expect(await baseWaitUntil { !h.store.isSending })
        await h.settle()
        #expect(h.count("send_message") - before == 2)
        #expect(h.store.draft(for: Self.peerA) == "새로 친 글", "실패한 옛 글이 새로 친 글을 덮었다")
        #expect(h.store.sendNotices[Self.peerA] == MessagesSendRules.connectionNotice)
        #expect(h.store.pendingOutgoing.isEmpty)
        #expect(h.store.unconfirmedSends.map(\.key) == [bubble].compactMap { $0 })
        #expect(h.store.unconfirmedSends.first?.body == "옛 글")
        h.expectNoForbiddenCalls()
    }

    @Test("⑨ 되돌린 서버(키를 모름) — 증거 뒤라도 message_id 없는 ok 를 보면 깃발을 내리고, 다음 모호한 실패는 재시도하지 않는다")
    func okWithoutMessageIDLowersTheFlag() async {
        let h = await MessagesHarness.make()
        defer { h.tearDown() }
        let slept = Self.instantRetrySleep(h)
        await Self.primeKeyEvidence(h)
        h.server.setSend(.json(#"{"status":"ok","body":"x","ring":"sent"}"#))
        await Self.sendDraft(h, "되돌린 뒤 첫 말", to: Self.peerA)
        #expect(!h.store.serverKnowsSendKey, "키를 모르는 판의 ok 뒤에도 깃발이 섰다 — 재시도가 두 통을 만든다")
        let before = h.count("send_message")
        h.server.setSend(Self.gatewayTimeout)
        await Self.sendDraft(h, "되돌린 뒤 둘째 말", to: Self.peerA)
        #expect(h.count("send_message") - before == 1, "키를 모르는 판에서 재시도했다")
        #expect(slept.get().isEmpty)
        // 확정 거절(status)은 증거를 바꾸지 않는다 — 서버 판은 ok 로만 잰다.
        await Self.primeKeyEvidence(h)
        h.server.setSend(.json(#"{"status":"target_focused"}"#))
        await Self.sendDraft(h, "거절", to: Self.peerA)
        #expect(h.store.serverKnowsSendKey, "거절 status 가 깃발을 내렸다")
        h.expectNoForbiddenCalls()
    }
}
