import CheckMobileShared
import Foundation

/// 앱 델리게이트(ios/App/AppDelegate.swift)가 부르는 푸시 공개 전달. App 폴더를 고치지 않으려고 푸시 폴더에 둔다.
public extension MobileAppModel {
    /// didFinishLaunching 에서 한 번: 알림 센터 delegate · 카테고리 등록 · 코디네이터에 시스템 어댑터 연결.
    /// DEBUG 데모 인자: `-AingCheckDemoPushPrimer YES`(로그인 뒤 설명 시트) · `-AingCheckDemoPushOpen message|gomoku_invite|feedback_reply`
    /// (로그인 뒤 그 종류의 데모 알림을 누른 것과 같은 경로로 연다).
    func installPushNotifications(arguments: [String] = ProcessInfo.processInfo.arguments) {
        #if os(iOS)
        guard push.system == nil else { return }
        let adapter = PushNotificationCenterAdapter(model: self)
        adapter.install()
        push.attach(system: adapter)
        #if DEBUG
        // 시뮬레이터 확인 전용: 권한 창(탭이 필요하다) 없이 조용한 알림 권한을 받아 `simctl push` 가 들어오게 한다.
        if context.isDemo, PushDemo.flag("-AingCheckDemoPushProvisional", in: arguments) {
            adapter.requestProvisionalAuthorizationForDemo()
        }
        #endif
        #endif
        #if DEBUG
        applyPushDemoArguments(arguments)
        #endif
    }
}

#if DEBUG
extension MobileAppModel {
    /// 데모 전용 실행 인자. 데모 조립(`-AingCheckDemo YES`)일 때만 듣는다.
    package func applyPushDemoArguments(_ arguments: [String]) {
        guard context.isDemo else { return }
        if PushDemo.flag("-AingCheckDemoPushPrimer", in: arguments) {
            push.demoForcesPrimer = true
        }
        if let raw = PushDemo.value(of: "-AingCheckDemoPushOpen", in: arguments),
           let kind = PushKind(rawValue: raw.lowercased()),
           let payload = PushPayload(json: PushDemo.payloadJSON(kind)) {
            Task { @MainActor [weak self] in
                await self?.push.handleResponse(payload, action: .open)
            }
        }
    }
}

/// 데모 · 시뮬레이터 확인용 알림 본문(서버 트리거가 만드는 모양 그대로 — SPEC-wave1 §1.5). 이름은 지어낸 값.
/// id 는 탭 데모 픽스처에 **실제로 있는 값**이다(통합 w4/int): 누르면 열리는 화면이 빈 자리("대화" 머리 · 없는 신청 · 없는 제보)가
/// 아니라 그 대화(한결 · 메시지 픽스처) · 그 신청(솜사탕 · 오목 받은함) · 답장 달린 제보(나 탭 제보 목록)로 선다.
package enum PushDemo {
    package static let peerID = "d0000000-0000-4000-8000-0000000000b1"
    package static let messageID = "d0000000-0000-4000-8000-00000000e00a"
    package static let matchID = "d0000000-0000-4000-8000-00000000a0a1"
    package static let reportID = "d0000000-0000-4000-8000-00000000fb02"

    package static func payloadJSON(_ kind: PushKind) -> Data {
        let text: String
        switch kind {
        case .message:
            text = #"{"aps":{"alert":{"title":"한결","body":"오후에 디자인 리뷰 10분만 가능할까요?"},"sound":"default","category":"MESSAGE","thread-id":"message-\#(peerID)"},"type":"message","peer_id":"\#(peerID)","message_id":"\#(messageID)"}"#
        case .gomokuInvite:
            text = #"{"aps":{"alert":{"title":"오목 신청","body":"솜사탕님이 오목 대결을 신청했어요 · 루비 5"},"sound":"default","category":"GOMOKU_INVITE","thread-id":"gomoku"},"type":"gomoku_invite","match_id":"\#(matchID)"}"#
        case .feedbackReply:
            text = #"{"aps":{"alert":{"title":"제보에 답장이 왔어요","body":"알려 주셔서 고마워요! 원인을 찾았고 다음 버전에서 고칠게요."},"sound":"default","category":"FEEDBACK_REPLY"},"type":"feedback_reply","report_id":"\#(reportID)"}"#
        }
        return Data(text.utf8)
    }

    static func flag(_ name: String, in arguments: [String]) -> Bool {
        value(of: name, in: arguments).map { ["yes", "1", "true"].contains($0.lowercased()) } ?? false
    }

    static func value(of name: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
}
#endif
