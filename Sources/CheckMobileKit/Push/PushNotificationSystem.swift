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
    /// `userInfo` 는 알림 본문(`content.userInfo`)에 그대로 싣는다 — 누르면 `PushPayload` 로 읽혀 그 화면이 열린다(카테고리 없음).
    func postLocalNotice(identifier: String, title: String, body: String, threadID: String?, userInfo: [String: String])
    /// 설정 앱의 이 앱 알림 화면.
    func openSystemSettings()
    /// 권한 설명 시트 띄우기 · 내리기.
    func presentPermissionPrimer(_ coordinator: PushCoordinator)
    func dismissPermissionPrimer()
}

/// 메시지 탭 스토어가 푸시 도착을 받는 진입점(SPEC-ios-build D4 `didReceiveMessagePush(peerID:)` — w4/messages 의 서명 `String?`).
///
/// **기본 구현을 두지 않는다**(push-verify 발견 1). 예전에는 no-op 기본 구현이 있어서 D4 의 서명(`String?`)이 요구(`String`)와 달라도
/// 조용히 컴파일됐고, 푸시 경로는 기본 구현을 불러 메시지 새로고침이 통째로 사라졌다(D4 자기 테스트의 `String` 인자 호출까지 그리로 갔다).
/// 이제 서명이 어긋나면 **컴파일 오류**로 드러난다. D4 가 병합되기 전 이 브랜치에서는 `PushTabEntryPointStandIns.swift` 의 대역이 자리
/// 스토어에 문을 붙이고, 병합하면 그 대역이 '재선언' 오류를 내어 지우게 만든다(절차는 그 파일 머리 주석).
/// 접근 수준을 internal 로 둔 이유: 스토어 쪽 메서드가 internal 이든 package 든 증인이 될 수 있게.
@MainActor
protocol PushMessageRefreshing: AnyObject {
    func didReceiveMessagePush(peerID: String?)
}

/// 나 탭 스토어가 제보 답장 푸시를 받는 진입점. 같은 이유로 기본 구현이 없다 — 서명은 `reportID: String?`.
@MainActor
protocol PushFeedbackRefreshing: AnyObject {
    func didReceiveFeedbackReplyPush(reportID: String?)
}

/// 병합 대역 표지. `PushTabEntryPointStandIns.swift` 의 대역이 붙은 스토어만 적합한다 — 병합 계약 테스트가 "대역이 남은 채 탭 스토어가
/// 들어왔는가"를 가르는 데 쓴다. 대역 파일을 지워도 이 표지는 남는다(테스트가 계속 컴파일되게).
@MainActor
protocol PushTabEntryPointStandIn: AnyObject {}

extension MessagesStore: PushMessageRefreshing {}
extension MeStore: PushFeedbackRefreshing {}
