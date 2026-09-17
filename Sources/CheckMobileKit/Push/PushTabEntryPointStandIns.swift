import Foundation

// MARK: - 병합 대역(merge stand-in) — 메시지 탭(D4) · 나 탭(D5+D7)의 푸시 새로고침 문
//
// 푸시 코디네이터는 두 탭 스토어의 새로고침 문을 **요구 서명 그대로** 부른다(`PushMessageRefreshing.didReceiveMessagePush(peerID: String?)`
// · `PushFeedbackRefreshing.didReceiveFeedbackReplyPush(reportID: String?)` — 기본 구현이 없다). 탭 브랜치가 아직 들어오지 않은 이
// 브랜치에서는 D-base 자리 스토어에 그 문이 없으므로, 아무것도 하지 않는 대역을 붙여 컴파일되게 한다.
//
// ── 병합 절차(아키텍트) ──
// 1. 탭 브랜치가 문을 가져오면 **컴파일 오류**('invalid redeclaration of didReceiveMessagePush(peerID:)')가 난다 → 이 파일에서 그
//    스토어의 확장을 통째로 지운다(표지 `PushTabEntryPointStandIn` 적합성도 함께). 대역은 `String?` 와 `String` 두 모양을 모두
//    선언한다 — 탭 쪽이 어느 모양이든 겹쳐서 오류가 난다(옵셔널 한 글자 차이로 조용히 갈라진 것이 push-verify 발견 1 이었다).
// 2. 지운 뒤 탭 쪽 서명이 요구와 다르면 이번에는 `extension MessagesStore: PushMessageRefreshing {}`(PushNotificationSystem.swift)가
//    적합성 오류를 낸다 → 탭 쪽을 요구 서명에 맞춘다(요구를 바꾸려면 코디네이터 호출부도 함께).
// 3. `PushMergeContractTests` 가 **실제 스토어**로 확인한다: 대역이 남은 채 메시지 탭 스토어가 들어와 있으면 빨갛고, 대역을 지운 뒤에는
//    메시지 푸시가 `message_unread_summary` 재조회로 이어지는지 단언한다.
// 4. 나 탭(w4/rankme d02e10c)에는 아직 이 문이 없다 — 병합해도 오류가 나지 않고 대역이 남는다(포그라운드 제보 답장 푸시가 나 탭을
//    새로고침하지 않는다. 누르면 라우트로 열리는 것은 그대로). 나 탭이 문을 더하면 1 과 같은 오류로 드러난다.

extension MessagesStore: PushTabEntryPointStandIn {
    /// 대역(D4 병합 때 지운다). 자리 스토어에는 새로고침할 것이 없다.
    package func didReceiveMessagePush(peerID: String?) {}

    /// 겹침 탐지용 대역 — 탭 쪽이 옵셔널이 아닌 모양을 가져와도 '재선언' 오류로 드러나게 한다. 코디네이터는 부르지 않는다.
    package func didReceiveMessagePush(peerID: String) {}
}

extension MeStore: PushTabEntryPointStandIn {
    /// 대역(나 탭이 문을 가져오면 지운다).
    package func didReceiveFeedbackReplyPush(reportID: String?) {}

    /// 겹침 탐지용 대역(위와 같은 이유).
    package func didReceiveFeedbackReplyPush(reportID: String) {}
}
