import CheckCore
import Foundation

/// 푸시 코디네이터가 시스템(UserNotifications · UIApplication)에 시키는 일. iOS 는 `PushNotificationCenterAdapter`,
/// 테스트는 기록하는 가짜가 구현한다 — 코디네이터는 Foundation 만 써서 macOS `swift test` 로 검증된다.
@MainActor
package protocol PushNotificationSystem: AnyObject {
    /// 지금 알림 권한.
    func authorizationStatus() async -> PushAuthorizationStatus
    /// 시스템 권한 창을 띄운다(이미 답한 뒤면 창 없이 지금 값). 허락이면 true.
    func requestAuthorization() async -> Bool
    /// `UIApplication.registerForRemoteNotifications()` — 결과는 앱 델리게이트 콜백으로 온다.
    func registerForRemoteNotifications()
    /// `UIApplication.unregisterForRemoteNotifications()` — 로그아웃·치명 만료 때. 서버 기기 행 정리가 실패해도 이 토큰은 APNs 가
    /// 410 으로 거절하게 되고, 서버 발송기가 그 토큰을 비운다(앞 계정 메시지가 로그아웃한 폰에 계속 오는 창을 닫는다).
    func unregisterForRemoteNotifications()
    /// 알림 센터에 남은 이 앱 알림을 모두 지운다(로그아웃한 앞 계정의 보낸 사람·본문이 남지 않게).
    func removeAllDeliveredNotifications()
    /// 앱 아이콘 배지.
    func setBadgeCount(_ count: Int)
    /// 앱이 스스로 띄우는 안내 알림(알림 액션이 실패했을 때 — 앱 화면이 없으니 알림으로 말한다).
    func postLocalNotice(identifier: String, title: String, body: String, threadID: String?)
    /// 설정 앱의 이 앱 알림 화면.
    func openSystemSettings()
    /// 권한 설명 시트 띄우기 · 내리기.
    func presentPermissionPrimer(_ coordinator: PushCoordinator)
    func dismissPermissionPrimer()
}

/// 메시지 탭 스토어가 푸시 도착을 받는 진입점(SPEC-ios-build D4 `didReceiveMessagePush(peerID:)`).
///
/// **왜 프로토콜인가**: 메시지 탭(D4)과 푸시(D9)는 동시에 만들어지고 병합 순서가 정해져 있지 않다. 푸시가 `MessagesStore` 의
/// 메서드를 직접 부르면 D4 가 없는 브랜치에서 컴파일이 깨진다. 기본 구현(아무것도 안 함)을 둔 프로토콜에 `MessagesStore` 를
/// 적합시키면 D4 전에는 기본 구현이, D4 뒤에는 **스토어의 같은 이름 메서드가** 증인이 된다(어느 순서로 병합해도 컴파일된다).
/// 접근 수준을 internal 로 둔 이유: 스토어 쪽 메서드가 internal 이든 package 든 증인이 될 수 있게.
@MainActor
protocol PushMessageRefreshing: AnyObject {
    func didReceiveMessagePush(peerID: String)
}

extension PushMessageRefreshing {
    /// 메시지 탭이 진입점을 아직 갖지 않았을 때. 앱이 앞에 있으면 실시간 신호(`onMessageActivity`)가 같은 일을 한다.
    func didReceiveMessagePush(peerID: String) {}
}

/// 나 탭 스토어가 제보 답장 푸시를 받는 진입점(같은 이유로 기본 구현을 둔다).
@MainActor
protocol PushFeedbackRefreshing: AnyObject {
    func didReceiveFeedbackReplyPush(reportID: String?)
}

extension PushFeedbackRefreshing {
    func didReceiveFeedbackReplyPush(reportID: String?) {}
}

extension MessagesStore: PushMessageRefreshing {}
extension MeStore: PushFeedbackRefreshing {}
