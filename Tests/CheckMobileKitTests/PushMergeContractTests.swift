import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

/// 병합 계약(push-verify 발견 1): 푸시 코디네이터 → **실제** 메시지 탭 스토어(`h.model.messages`)의 새로고침 문.
///
/// 가짜 스토어로 재지 않는다 — 예전 테스트(`witnessPrefersStoreMethod`)는 요구 서명과 정확히 같은 가짜를 써서, 실제 D4 모양
/// (`didReceiveMessagePush(peerID: String?)`)과 요구(`String`)의 어긋남을 못 잡았고 병합하면 푸시 새로고침이 조용히 사라졌다.
/// 이 테스트는 브랜치 상태 둘 다에서 뜻이 있다.
/// - 대역이 붙어 있음(`PushTabEntryPointStandIns.swift`): 스토어가 **D-base 자리 스토어**여야 한다 — 활성화에서 아무 요청도 하지 않는다.
///   메시지 탭(D4)은 활성화 때 요약을 읽으므로, 탭 스토어가 들어왔는데 대역이 남아 있으면(탭 쪽 문이 대역의 두 모양과 겹치지 않아
///   컴파일이 지나간 경우 — 예: 이름표가 다름) 빨갛다.
/// - 대역을 지움(병합 후): 포그라운드 표시 · 읽음 액션이 `message_unread_summary` 재조회로 이어지는지.
///
/// 시스템 어댑터를 **붙이지 않는다**: 붙이면 코디네이터가 배지 확인으로 같은 요약을 읽어 메시지 탭의 요청과 섞인다. 붙이지 않아도
/// 표시 판단 · 읽음 액션 · 스토어 새로고침은 그대로 돈다.
@MainActor
@Suite(.serialized) struct PushMergeContractTests {
    @Test("메시지 푸시(포그라운드 표시 · 읽음 액션) → 실제 MessagesStore 새로고침 · 대역이 남아 있으면 자리 스토어여야 한다")
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
        // 활성화 새로고침(메시지 탭)이 나갈 시간을 준다.
        let storeReadOnActivation = await baseWaitUntil(timeout: 1.0) {
            h.requests().contains { ["message_unread_summary", "message_history_with_reads", "message_history"].contains($0.rpcName ?? "") }
        }
        try? await Task.sleep(for: .milliseconds(200))

        h.clearRequests()
        _ = h.push.presentation(for: PushPayload(userInfo: PushHarness.messageUserInfo()))
        let viaPresentation = await baseWaitUntil(timeout: 1.5) { !h.calls("message_unread_summary").isEmpty }

        h.clearRequests()
        await h.push.handleResponse(PushPayload(userInfo: PushHarness.messageUserInfo()), action: .markRead)
        #expect(h.calls("mark_messages_read").count == 1)
        let viaMarkRead = await baseWaitUntil(timeout: 1.5) { !h.calls("message_unread_summary").isEmpty }

        if Self.isStandIn(h.model.messages) {
            #expect(
                !storeReadOnActivation,
                "메시지 탭 스토어가 병합됐는데 푸시 대역이 남아 있다(푸시가 대역의 빈 문으로 간다) — PushTabEntryPointStandIns.swift 의 MessagesStore 확장을 지우고 탭 쪽 문을 요구 서명 didReceiveMessagePush(peerID: String?) 에 맞춰라"
            )
            #expect(!viaPresentation && !viaMarkRead, "자리 스토어는 새로고침할 것이 없다")
        } else {
            #expect(viaPresentation, "포그라운드 메시지 푸시가 메시지 탭 새로고침(message_unread_summary)으로 이어지지 않았다")
            #expect(viaMarkRead, "읽음 액션 뒤 메시지 탭 새로고침이 없었다")
        }
        #expect(h.forbiddenViolations.isEmpty)
    }

    /// `Any` 로 받아 검사한다(구체 타입으로 `is` 를 쓰면 브랜치 상태에 따라 '언제나 참/거짓' 경고가 난다).
    private static func isStandIn(_ store: Any) -> Bool {
        store is PushTabEntryPointStandIn
    }
}
