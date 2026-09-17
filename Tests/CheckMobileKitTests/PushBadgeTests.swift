import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

/// 앱 아이콘 배지(push-verify 발견 2): **모르면 적지 않는다**.
///
/// 예전에는 어댑터를 붙이는 순간 · 로그인 직후 탭 스토어 합(아직 아무것도 안 읽어 0)을 곧바로 적었다. 알림으로 앱이 뒤에서 켜진
/// 실행은 활성화가 없어 스토어가 끝내 읽지 않았고, 아이콘에 남은 안 읽은 수가 0 으로 지워졌다(서버는 배지를 싣지 않으므로 다음 실행까지
/// 그대로 틀린다). 뒤에서 도는 알림 액션(답장 · 읽음 · 거절)과 그 뒤 전용 배지 갈래는 w10 에서 걷어냈다 — 이제 배지는 앱이 앞에서만 적는다
/// (옛 카테고리 액션으로 뒤에서 켜진 실행은 `PushCoordinatorTests.legacyActionIdentifiersInBackgroundLaunch`).
@MainActor
@Suite(.serialized) struct PushBadgeTests {
    static let inboxEmpty = MobileStubResponse.json(#"{"status":"ok","incoming":[],"outgoing":null,"active_match_id":null}"#)

    /// 받은 오목 신청 하나가 남은 받은함(지어낸 이름).
    static func inboxWithInvite(now: Date) -> MobileStubResponse {
        let nowMs = Int(now.timeIntervalSince1970 * 1000)
        let row = #"{"match_id":"e9999999-5555-4666-8777-000000000009","challenger":{"user_id":"b9999999-3333-4444-8555-000000000009","display_name":"바다","avatar_url":null,"character":null},"stake":3,"invite_expires_ms":\#(nowMs + 60_000)}"#
        return .json(#"{"status":"ok","incoming":[\#(row)],"outgoing":null,"active_match_id":null,"server_now_ms":\#(nowMs)}"#)
    }

    @Test("활성화의 서버 확인을 기다리는 사이 뒤로 가면: 답이 와도 적지 않는다(탭 스토어 새로고침이 끝났는지 모른다) · 다시 앞에 오면 확인 뒤 적는다")
    func confirmationAnsweredAfterBackgroundWritesNothing() async {
        let h = PushHarness(label: "push-badge-bg-mid")
        h.system.status = .authorized
        defer { h.tearDown() }
        h.setRPC("message_unread_summary", PushHarness.unreadSummary(total: 2))
        h.setRPC("gomoku_inbox", Self.inboxEmpty)
        let model = h.makeRestoredModel()
        let badges = PushFakeBadges()
        model.push.badgeTotalSource = { badges.messages + badges.games }
        #expect(await baseWaitUntil { model.session.isSignedIn })
        await model.session.pendingDeviceRegistration?.value
        await baseBarrier(model.context.service)
        #expect(h.calls("message_unread_summary").isEmpty, "전제: 활성화 전에는 요약을 읽지 않았다")

        // 활성화는 요약을 두 번 읽는다(메시지 탭 새로고침 · 코디네이터 확인 — 순서는 정해지지 않았다). 둘 다 붙잡아 "답하기 전에 뒤로 감"을 사건으로 만든다.
        let summaryHold = BaseHold.rpc("message_unread_summary", host: h.host, limit: 2)
        model.sceneDidBecomeActive()
        let confirmation = model.push.pendingBadgeConfirmation
        #expect(confirmation != nil, "전제: 활성화가 서버 확인을 띄웠다")
        #expect(await summaryHold.waitHeld(2))
        model.sceneDidEnterBackground()
        #expect(await summaryHold.releaseAndWaitDelivered())
        await confirmation?.value
        await baseYield()
        await baseBarrier(model.context.service)
        #expect(model.push.badgeState == .unknown, "뒤에서 끝난 확인이 앎을 세웠다")
        #expect(h.system.badgeCounts.isEmpty, "뒤로 간 뒤에 적었다: \(h.system.badgeCounts)")

        // 다시 앞: 확인이 답한 뒤 탭 배지 합.
        badges.messages = 2
        model.sceneDidBecomeActive()
        await model.push.pendingBadgeConfirmation?.value
        #expect(model.push.badgeState == .stores)
        #expect(await baseWaitUntil { h.system.badgeCounts == [2] }, "\(h.system.badgeCounts)")
        #expect(h.forbiddenViolations.isEmpty)
    }

    @Test("업데이트 필요로 끝난 실행은 적지 않고, 키체인이 비어 로그아웃으로 끝나면(확정) 0")
    func launchOutcomes() async {
        let update = PushHarness(label: "push-badge-update")
        defer { update.tearDown() }
        update.setRPC("client_release", .json(#"{"status":"ok","platform":"ios","min_build":99,"latest_build":99}"#))
        let updating = update.makeRestoredModel()
        #expect(await baseWaitUntil { if case .needsUpdate = updating.session.phase { return true } else { return false } })
        await updating.push.pendingBadgeConfirmation?.value
        await baseYield()
        await baseBarrier(updating.context.service)
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
        await baseYield()
        await baseBarrier(model.context.service)
        #expect(h.system.badgeCounts.isEmpty, "오프라인 활성화에서 읽지 못한 0 을 적었다")

        // 망이 돌아오고 오목 신청 알림이 앞에서 왔다 → 확인을 다시 하고, 답한 뒤에 적는다(요약을 붙잡아 "답하기 전"을 사건으로).
        badges.messages = 2
        h.setRPC("message_unread_summary", PushHarness.unreadSummary(total: 2))
        let summaryHold = BaseHold.rpc("message_unread_summary", host: h.host)
        _ = model.push.presentation(for: PushPayload(userInfo: PushHarness.gomokuUserInfo()))
        #expect(await summaryHold.waitHeld())
        await baseYield()
        #expect(h.system.badgeCounts.isEmpty, "요약이 답하기 전에 적었다")
        #expect(await summaryHold.releaseAndWaitDelivered())
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
