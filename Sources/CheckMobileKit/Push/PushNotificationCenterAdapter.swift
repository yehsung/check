#if os(iOS)
import os
import SwiftUI
import UIKit
import UserNotifications

/// iOS 알림 어댑터 — `UNUserNotificationCenter` 의 delegate 이자 코디네이터의 `PushNotificationSystem`.
///
/// 앱 델리게이트 didFinishLaunching 에서 설치한다(`MobileAppModel.installPushNotifications()`) — 알림을 눌러 앱이 **켜지는** 경우
/// 응답 콜백이 didFinishLaunching 직후에 오므로 delegate 는 그 전에 붙어 있어야 한다.
/// 판단은 전부 `PushCoordinator` 가 한다. 여기는 시스템 값 ↔ 플랫폼 무관 값 옮기기와 화면(설명 시트) 띄우기만.
@MainActor
final class PushNotificationCenterAdapter: NSObject, UNUserNotificationCenterDelegate, UIAdaptivePresentationControllerDelegate, PushNotificationSystem {
    /// 종류 · 액션 · 표시 결정만 남긴다(본문 · 이름 · id 는 남기지 않는다 — 메시지 파일 공통 규약).
    nonisolated static let logger = Logger(subsystem: "com.yehsung.aingcheck", category: "push")
    private weak var model: MobileAppModel?
    private weak var primerController: UIViewController?

    init(model: MobileAppModel) {
        self.model = model
        super.init()
    }

    func install() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories(Self.makeCategories())
    }

    /// 플랫폼 무관 설명(`PushCategories.all`) → 시스템 카테고리.
    nonisolated static func makeCategories() -> Set<UNNotificationCategory> {
        Set(PushCategories.all.map { spec in
            let actions: [UNNotificationAction] = spec.actions.map { action in
                var options: UNNotificationActionOptions = []
                if action.opensApp { options.insert(.foreground) }
                if action.requiresUnlock { options.insert(.authenticationRequired) }
                if action.isDestructive { options.insert(.destructive) }
                if let input = action.textInput {
                    return UNTextInputNotificationAction(
                        identifier: action.identifier,
                        title: action.title,
                        options: options,
                        textInputButtonTitle: input.button,
                        textInputPlaceholder: input.placeholder
                    )
                }
                return UNNotificationAction(identifier: action.identifier, title: action.title, options: options)
            }
            return UNNotificationCategory(identifier: spec.identifier, actions: actions, intentIdentifiers: [], options: [])
        })
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let payload = PushPayload(userInfo: notification.request.content.userInfo)
        let presentation = await presentation(for: payload)
        Self.logger.notice("willPresent kind=\(payload?.kind.rawValue ?? "unknown", privacy: .public) presentation=\(String(describing: presentation), privacy: .public)")
        switch presentation {
        case .banner: return [.banner, .list, .sound]
        case .hidden: return []
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let payload = PushPayload(userInfo: response.notification.request.content.userInfo)
        let action = PushAction(
            actionIdentifier: response.actionIdentifier,
            textInput: (response as? UNTextInputNotificationResponse)?.userText
        )
        Self.logger.notice("didReceive kind=\(payload?.kind.rawValue ?? "unknown", privacy: .public) action=\(Self.actionName(action), privacy: .public)")
        await handle(payload, action: action)
    }

    nonisolated static func actionName(_ action: PushAction) -> String {
        switch action {
        case .open: return "open"
        case .reply: return "reply"
        case .markRead: return "markRead"
        case .acceptInvite: return "accept"
        case .declineInvite: return "decline"
        case .ignore: return "ignore"
        }
    }

    private func presentation(for payload: PushPayload?) -> PushPresentation {
        model?.push.presentation(for: payload) ?? .banner
    }

    private func handle(_ payload: PushPayload?, action: PushAction) async {
        guard let model else { return }
        // 알림 액션으로 앱이 백그라운드에서 켜졌으면 화면(onAppear)이 없어 실행 복원이 시작되지 않았다 — 여기서 시작한다(한 번만 돈다).
        model.start()
        await model.push.handleResponse(payload, action: action)
    }

    // MARK: - PushNotificationSystem

    func authorizationStatus() async -> PushAuthorizationStatus {
        Self.map(await Self.readAuthorizationStatus())
    }

    func requestAuthorization() async -> Bool {
        await Self.requestSystemAuthorization()
    }

    func registerForRemoteNotifications() {
        UIApplication.shared.registerForRemoteNotifications()
    }

    func unregisterForRemoteNotifications() {
        UIApplication.shared.unregisterForRemoteNotifications()
    }

    func removeAllDeliveredNotifications() {
        UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    }

    func setBadgeCount(_ count: Int) {
        UNUserNotificationCenter.current().setBadgeCount(max(0, count), withCompletionHandler: nil)
    }

    func postLocalNotice(identifier: String, title: String, body: String, threadID: String?, userInfo: [String: String]) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let threadID { content.threadIdentifier = threadID }
        // 누르면 didReceive → PushPayload 가 이 칸을 읽어 그 대화를 연다(카테고리를 붙이지 않는다 — 안내에 답장·읽음 버튼은 없다).
        content.userInfo = userInfo
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    func presentPermissionPrimer(_ coordinator: PushCoordinator) {
        presentPrimer(coordinator, attempt: 0)
    }

    func dismissPermissionPrimer() {
        primerController?.dismiss(animated: true)
        primerController = nil
    }

    /// 창이 아직 없으면(실행 직후) 잠깐 뒤 다시 — 끝내 없으면 코디네이터에 "못 띄움"을 알린다(쉬는 기간을 적지 않는다).
    private func presentPrimer(_ coordinator: PushCoordinator, attempt: Int) {
        guard coordinator.isPrimerPresented, primerController == nil else { return }
        guard let presenter = Self.topViewController() else {
            guard attempt < 10 else {
                coordinator.primerCouldNotPresent()
                return
            }
            Task { @MainActor [weak self, weak coordinator] in
                try? await Task.sleep(for: .milliseconds(300))
                guard let self, let coordinator else { return }
                self.presentPrimer(coordinator, attempt: attempt + 1)
            }
            return
        }
        let host = UIHostingController(rootView: PushPermissionPrimerView(coordinator: coordinator))
        host.modalPresentationStyle = .pageSheet
        if let sheet = host.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
        }
        host.presentationController?.delegate = self
        primerController = host
        presenter.present(host, animated: true)
    }

    nonisolated func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.primerController = nil
            self.model?.push.primerDidDisappear()
        }
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap(\.windows)
        guard let window = windows.first(where: \.isKeyWindow) ?? windows.first else { return nil }
        var top = window.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }

    #if DEBUG
    /// 데모(시뮬레이터) 전용 — 사용자 입력 없이 받을 수 있는 조용한(provisional) 권한.
    /// 콜백은 메인 액터 밖에서 온다 — 메인 액터 문맥에서 만든 클로저를 넘기지 않게 nonisolated 로 둔다.
    nonisolated func requestProvisionalAuthorizationForDemo() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.provisional, .alert, .sound, .badge]) { _, _ in }
    }
    #endif

    // MARK: - 시스템 값 옮기기(메인 액터 밖 콜백)

    private nonisolated static func readAuthorizationStatus() async -> UNAuthorizationStatus {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    private nonisolated static func requestSystemAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    nonisolated static func map(_ status: UNAuthorizationStatus) -> PushAuthorizationStatus {
        switch status {
        case .notDetermined: return .notDetermined
        case .denied: return .denied
        case .authorized: return .authorized
        case .provisional: return .provisional
        case .ephemeral: return .ephemeral
        @unknown default: return .unknown
        }
    }
}
#endif
