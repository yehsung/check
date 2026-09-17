import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

/// 앱 아이콘 배지(push-verify 발견 2): **모르면 적지 않는다**.
///
/// 예전에는 어댑터를 붙이는 순간 · 로그인 직후 탭 스토어 합(아직 아무것도 안 읽어 0)을 곧바로 적었다. 알림 액션으로 앱이 뒤에서 켜진
/// 실행은 활성화가 없어 스토어가 끝내 읽지 않았고, 아이콘에 남은 안 읽은 수가 0 으로 지워졌다(서버는 배지를 싣지 않으므로 다음 실행까지
/// 그대로 틀린다).
@MainActor
@Suite(.serialized) struct PushBadgeTests {
    static let inboxEmpty = MobileStubResponse.json(#"{"status":"ok","incoming":[],"outgoing":null,"active_match_id":null}"#)

    /// 받은 오목 신청 하나가 남은 받은함(지어낸 이름).
    static func inboxWithInvite(now: Date) -> MobileStubResponse {
        let nowMs = Int(now.timeIntervalSince1970 * 1000)
        let row = #"{"match_id":"e9999999-5555-4666-8777-000000000009","challenger":{"user_id":"b9999999-3333-4444-8555-000000000009","display_name":"바다","avatar_url":null,"character":null},"stake":3,"invite_expires_ms":\#(nowMs + 60_000)}"#
        return .json(#"{"status":"ok","incoming":[\#(row)],"outgoing":null,"active_match_id":null,"server_now_ms":\#(nowMs)}"#)
    }

    @Test("뒤에서 켜진 실행(키체인 세션) · 읽음 액션: 요약·받은함을 읽은 뒤 남은 수만 적는다 — 복원 중에도, 액션 전에도 0 을 적지 않는다")
    func backgroundMarkReadWritesServerCount() async {
        let h = PushHarness(label: "push-badge-markread")
        h.system.status = .authorized
        defer { h.tearDown() }
        h.setRPC("client_release", .json(#"{"status":"ok","platform":"ios","min_build":1,"latest_build":1}"#, delay: 0.2))
        h.setRPC("mark_messages_read", .json(#"{"status":"ok","advanced":true,"unread":2}"#))
        h.setRPC("message_unread_summary", PushHarness.unreadSummary(total: 2))
        h.setRPC("gomoku_inbox", Self.inboxEmpty)

        let model = h.makeRestoredModel()
        #expect(model.session.phase == .launching)
        try? await Task.sleep(for: .milliseconds(100))
        #expect(h.system.badgeCounts.isEmpty, "실행 복원 중에 모르는 값을 적었다")

        await model.push.handleResponse(PushPayload(userInfo: PushHarness.messageUserInfo()), action: .markRead)
        #expect(model.session.isSignedIn)
        #expect(h.system.badgeCounts == [2], "남은 안 읽은 2건 — 0 을 먼저 적거나 지웠다: \(h.system.badgeCounts)")
        #expect(model.push.badgeState == .server)
        let names = h.requests().compactMap(\.rpcName)
        let mark = names.firstIndex(of: "mark_messages_read") ?? -1
        let summary = names.firstIndex(of: "message_unread_summary") ?? -1
        #expect(mark >= 0 && summary > mark, "읽음을 올린 뒤에 요약을 읽어야 한다: \(names)")
        #expect(names.contains("gomoku_inbox"))

        // 그 뒤 앱을 열면: 앞의 확인으로 넘어가 탭 배지 합을 적는다(같은 값이면 다시 적지 않는다).
        let badges = PushFakeBadges()
        badges.messages = 2
        model.push.badgeTotalSource = { badges.messages + badges.games }
        model.sceneDidBecomeActive()
        await model.push.pendingBadgeConfirmation?.value
        #expect(model.push.badgeState == .stores)
        #expect(h.system.badgeCounts == [2])
        badges.messages = 0
        #expect(await baseWaitUntil { h.system.badgeCounts.last == 0 })
        #expect(h.forbiddenViolations.isEmpty)
    }

    @Test("뒤에서 켜진 실행 · 오목 거절: 메시지와 무관한 액션이어도 서버에서 읽어 적는다 — 안 읽은 메시지 2 + 남은 오목 신청(게임 탭 배지)")
    func backgroundDeclineWritesServerCount() async {
        let h = PushHarness(label: "push-badge-decline")
        h.system.status = .authorized
        defer { h.tearDown() }
        h.setRPC("gomoku_respond", .json(#"{"status":"ok","accepted":false,"ruby_balance":100}"#))
        h.setRPC("message_unread_summary", PushHarness.unreadSummary(total: 2))
        h.setRPC("gomoku_inbox", Self.inboxWithInvite(now: h.clock.now))

        let model = h.makeRestoredModel()
        await model.push.handleResponse(PushPayload(userInfo: PushHarness.gomokuUserInfo()), action: .declineInvite)
        #expect(model.session.isSignedIn)
        #expect(h.calls("gomoku_respond").count == 1)
        #expect(model.gomoku.pendingIncomingInvites.count == 1, "받은함을 읽지 않았다")
        let expected = 2 + (model.links.games?.badgeCount ?? 0)
        #expect(h.system.badgeCounts == [expected], "\(h.system.badgeCounts)")
        #expect(h.system.badgeCounts.last != 0)
        #expect(h.forbiddenViolations.isEmpty)
    }

    @Test("뒤에서 켜진 실행 · 오프라인: 요약을 못 읽으면 아이콘을 건드리지 않는다 · 읽음이 안 올라갔으면 읽지도 않는다")
    func backgroundOfflineLeavesIconAlone() async {
        let h = PushHarness(label: "push-badge-offline")
        h.system.status = .authorized
        defer { h.tearDown() }
        h.setRPC("mark_messages_read", .json(#"{"status":"ok","advanced":true,"unread":0}"#))
        h.setRPC("message_unread_summary", .networkFailure())
        h.setRPC("gomoku_inbox", Self.inboxEmpty)

        let model = h.makeRestoredModel()
        await model.push.handleResponse(PushPayload(userInfo: PushHarness.messageUserInfo()), action: .markRead)
        #expect(model.session.isSignedIn)
        #expect(h.calls("message_unread_summary").count == 1)
        #expect(h.system.badgeCounts.isEmpty, "모르는 채 적었다: \(h.system.badgeCounts)")
        #expect(model.push.badgeState == .unknown)
        #expect(h.calls("gomoku_inbox").isEmpty)

        // 읽음 자체가 실패했으면 안 읽은 수는 그대로다 — 배지 확인도 하지 않는다.
        h.setRPC("mark_messages_read", .networkFailure())
        h.clearRequests()
        await model.push.handleResponse(PushPayload(userInfo: PushHarness.messageUserInfo()), action: .markRead)
        #expect(h.requests().compactMap(\.rpcName) == ["mark_messages_read"])
        #expect(h.system.badgeCounts.isEmpty)
        #expect(h.forbiddenViolations.isEmpty)
    }

    @Test("업데이트 필요로 끝난 실행은 적지 않고, 키체인이 비어 로그아웃으로 끝나면(확정) 0")
    func launchOutcomes() async {
        let update = PushHarness(label: "push-badge-update")
        defer { update.tearDown() }
        update.setRPC("client_release", .json(#"{"status":"ok","platform":"ios","min_build":99,"latest_build":99}"#))
        let updating = update.makeRestoredModel()
        #expect(await baseWaitUntil { if case .needsUpdate = updating.session.phase { return true } else { return false } })
        try? await Task.sleep(for: .milliseconds(100))
        #expect(update.system.badgeCounts.isEmpty, "업데이트 화면에서 앞 실행의 배지를 지웠다")

        let empty = PushHarness(label: "push-badge-empty")
        defer { empty.tearDown() }
        empty.push.attach(system: empty.system)
        #expect(empty.system.badgeCounts.isEmpty, "실행 복원 전에 적었다")
        empty.model.start()
        #expect(await baseWaitUntil { empty.model.session.phase == .signedOut })
        #expect(await baseWaitUntil { empty.system.badgeCounts == [0] })
        #expect(update.forbiddenViolations.isEmpty && empty.forbiddenViolations.isEmpty)
    }

    @Test("앞: 활성화하면 서버 확인(요약)이 답한 뒤에야 탭 배지 합을 적는다 · 오프라인이면 안 적고, 다음 포그라운드 알림이 다시 확인한다")
    func foregroundWaitsForServerAnswer() async {
        let h = PushHarness(label: "push-badge-foreground")
        h.system.status = .authorized
        defer { h.tearDown() }
        h.setRPC("message_unread_summary", .networkFailure())
        h.setRPC("gomoku_inbox", Self.inboxEmpty)
        let model = h.makeRestoredModel()
        let badges = PushFakeBadges()
        model.push.badgeTotalSource = { badges.messages + badges.games }
        #expect(await baseWaitUntil { model.session.isSignedIn })

        model.sceneDidBecomeActive()
        await model.push.pendingBadgeConfirmation?.value
        #expect(model.push.badgeState == .unknown)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(h.system.badgeCounts.isEmpty, "오프라인 활성화에서 읽지 못한 0 을 적었다")

        // 망이 돌아오고 오목 신청 알림이 앞에서 왔다 → 확인을 다시 하고, 답한 뒤에 적는다.
        badges.messages = 2
        h.setRPC("message_unread_summary", PushHarness.unreadSummary(total: 2, delay: 0.3))
        _ = model.push.presentation(for: PushPayload(userInfo: PushHarness.gomokuUserInfo()))
        try? await Task.sleep(for: .milliseconds(100))
        #expect(h.system.badgeCounts.isEmpty, "요약이 답하기 전에 적었다")
        await model.push.pendingBadgeConfirmation?.value
        #expect(model.push.badgeState == .stores)
        #expect(h.system.badgeCounts == [2])
        badges.games = 1
        #expect(await baseWaitUntil { h.system.badgeCounts.last == 3 })

        // 로그아웃은 확정 0, 앎은 처음으로.
        await model.session.signOut()
        #expect(h.system.badgeCounts.last == 0)
        #expect(model.push.badgeState == .unknown)
        #expect(h.forbiddenViolations.isEmpty)
    }
}
