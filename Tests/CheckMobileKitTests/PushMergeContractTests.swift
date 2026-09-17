import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

/// 병합 계약(push-verify 발견 1 · 통합 w4/int): 푸시 코디네이터 → **실제** 탭 스토어의 문.
///
/// 가짜 스토어로 재지 않는다 — 예전 테스트(`witnessPrefersStoreMethod`)는 요구 서명과 정확히 같은 가짜를 써서, 실제 탭 모양과 요구의
/// 어긋남을 못 잡았고 병합하면 푸시 새로고침이 조용히 사라졌다. 병합 전 대역(`PushTabEntryPointStandIns.swift`)은 통합에서 지웠으므로
/// 이제 증인은 언제나 실제 스토어다 — 아래는 그 문이 **요청까지** 이어지는지 잰다.
///
/// 메시지 시나리오는 시스템 어댑터를 **붙이지 않는다**: 붙이면 코디네이터가 배지 확인으로 같은 요약을 읽어 메시지 탭의 요청과 섞인다.
/// 붙이지 않아도 표시 판단 · 읽음 액션 · 스토어 새로고침은 그대로 돈다.
@MainActor
@Suite(.serialized) struct PushMergeContractTests {
    @Test("푸시↔메시지: 포그라운드 표시 · 읽음 액션 → 실제 MessagesStore 새로고침(message_unread_summary) · 보고 있는 대화는 배너 숨김")
    func messagePushReachesRealMessagesStore() async {
        let h = PushHarness(label: "push-merge-messages")
        defer { h.tearDown() }
        h.setRPC("message_unread_summary", PushHarness.unreadSummary(total: 0))
        h.setRPC("message_history_with_reads", .json("[]"))
        h.setRPC("mark_messages_read", .json(#"{"status":"ok","advanced":true,"unread":0}"#))
        h.model.start()
        #expect(await baseWaitUntil { h.model.session.phase == .signedOut })
        await h.model.session.signIn(email: "push@aing-check.invalid", password: "pw")
        await h.model.session.pendingDeviceRegistration?.value
        h.clearRequests()

        h.model.sceneDidBecomeActive()
        // 활성화 새로고침(메시지 탭)이 나갔다 — 자리 스토어가 아니라 실제 메시지 탭 스토어가 앱 모델에 있다.
        #expect(await baseWaitUntil {
            h.requests().contains { ["message_unread_summary", "message_history_with_reads", "message_history"].contains($0.rpcName ?? "") }
        }, "활성화에서 메시지 탭이 아무것도 읽지 않았다 — 앱 모델의 메시지 스토어가 자리 스토어인가")
        // 활성화 새로고침(메시지·지금 탭)이 멎은 뒤에 기록을 비운다.
        _ = await baseWaitUntil {
            h.model.messages.pendingActivityTask == nil && !h.model.messages.isMarkingRead && !h.model.messages.directoryLoading
                && h.model.now.refreshTask == nil
        }
        await h.barrier()

        h.clearRequests()
        #expect(h.push.presentation(for: PushPayload(userInfo: PushHarness.messageUserInfo())) == .banner)
        #expect(await baseWaitUntil { !h.calls("message_unread_summary").isEmpty },
                "포그라운드 메시지 푸시가 메시지 탭 새로고침(message_unread_summary)으로 이어지지 않았다")

        h.clearRequests()
        await h.push.handleResponse(PushPayload(userInfo: PushHarness.messageUserInfo()), action: .markRead)
        #expect(h.calls("mark_messages_read").count == 1)
        #expect(await baseWaitUntil { !h.calls("message_unread_summary").isEmpty }, "읽음 액션 뒤 메시지 탭 새로고침이 없었다")

        // 배너 숨김은 메시지 탭이 대화 화면 표시에 맞춰 적는 router.visibleConversationPeerID 를 읽는다(두 탭 사이 배선).
        let token = UUID()
        h.model.messages.conversationDidAppear(peerID: PushHarness.peerID, token: token)
        #expect(h.model.router.visibleConversationPeerID == PushHarness.peerID)
        #expect(h.push.presentation(for: PushPayload(userInfo: PushHarness.messageUserInfo())) == .hidden)
        #expect(h.push.presentation(for: PushPayload(userInfo: PushHarness.messageUserInfo(peer: "b9999999-3333-4444-8555-000000000009"))) == .banner)
        h.model.messages.conversationDidDisappear(token: token)
        #expect(h.model.router.visibleConversationPeerID == nil)
        #expect(h.push.presentation(for: PushPayload(userInfo: PushHarness.messageUserInfo())) == .banner)
        #expect(h.forbiddenViolations.isEmpty)
    }

    @Test("푸시↔나: 제보 답장 푸시(포그라운드) → 실제 MeStore 가 답장 시각을 다시 읽어 '새 답장'(badgeCount 1) · 누르면 나 탭 제보 라우트")
    func feedbackReplyPushReachesRealMeStore() async {
        let h = PushHarness(label: "push-merge-me")
        h.system.status = .authorized
        defer { h.tearDown() }
        h.setRPC("feedback_reply_latest", .json(#""2026-09-17T04:00:00+00:00""#))
        await h.launchSignedIn()
        h.clearRequests()
        #expect(h.model.me.badgeCount == 0)

        _ = h.push.presentation(for: PushPayload(userInfo: PushHarness.feedbackUserInfo()))
        #expect(await baseWaitUntil { !h.calls("feedback_reply_latest").isEmpty },
                "제보 답장 푸시가 나 탭 새로고침(feedback_reply_latest)으로 이어지지 않았다")
        #expect(await baseWaitUntil { h.model.me.badgeCount == 1 }, "새 답장 표시가 서지 않았다")
        #expect(h.calls("feedback_list").isEmpty, "목록을 한 번도 안 연 채면 목록까지 읽지 않는다")

        await h.push.handleResponse(PushPayload(userInfo: PushHarness.feedbackUserInfo()), action: .open)
        #expect(h.model.router.consumePendingRoute(for: .me) == .feedback(reportID: PushHarness.reportID))
        #expect(h.forbiddenViolations.isEmpty)
    }

    @Test("푸시↔게임: 오목 신청 푸시 → 받은함 재조회 → 게임 탭 배지 1 · 앱 배지 합 · 탭하면 게임 탭이 오목 화면으로 소비 · presentWindow 는 게임 탭 것 그대로")
    func gomokuPushReachesRealGamesStore() async {
        let h = PushHarness(label: "push-merge-games")
        h.system.status = .authorized
        defer { h.tearDown() }
        h.setRPC("gomoku_inbox", PushBadgeTests.inboxEmpty)
        await h.launchSignedIn()
        #expect(h.model.gomoku.presentWindow != nil, "게임 탭이 오목 창 열기 문을 달지 않았다")
        #expect(h.model.games.badgeCount == 0)

        h.setRPC("gomoku_inbox", PushBadgeTests.inboxWithInvite(now: h.clock.now))
        h.clearRequests()
        _ = h.push.presentation(for: PushPayload(userInfo: PushHarness.gomokuUserInfo()))
        #expect(await baseWaitUntil { h.model.games.badgeCount == 1 }, "받은 신청이 게임 탭 배지에 오지 않았다")
        #expect(!h.calls("gomoku_inbox").isEmpty)
        #expect(h.model.badges.badge(for: .games) == 1)
        #expect(h.model.badges.appBadgeTotal == h.model.messages.badgeCount + 1)
        #expect(h.push.badgeTotalSource() == h.model.badges.appBadgeTotal, "앱 배지 출처가 탭 배지 합이 아니다")

        // 탭 → 라우트 → 게임 탭이 꺼내 오목 화면으로 쌓는다(푸시는 게임 스토어를 직접 부르지 않는다).
        await h.push.handleResponse(PushPayload(userInfo: PushHarness.gomokuUserInfo()), action: .open)
        let route = h.model.router.consumePendingRoute(for: .games)
        #expect(route == .gomokuInvite(matchID: PushHarness.matchID))
        #expect(route.flatMap { h.model.games.routeStep(for: $0) } == .push(.gomoku))

        // 푸시 설치 · 응답 뒤에도 판 시작 문은 게임 탭 것이다 — 부르면 게임 탭 오목 대국 라우트가 열린다.
        h.model.router.reset()
        h.model.gomoku.presentWindow?()
        #expect(h.model.router.lastOpenedRoute == .gomokuMatch(matchID: nil), "presentWindow 가 게임 탭 문이 아니다(덮어쓰였다)")
        #expect(h.forbiddenViolations.isEmpty)
    }
}
