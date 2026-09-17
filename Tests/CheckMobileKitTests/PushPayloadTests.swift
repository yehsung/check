import CheckCore
import CheckMobileShared
import Foundation
import Testing
import UserNotifications
@testable import CheckMobileKit

/// 푸시 페이로드 파싱(서버 §1.5 모양 그대로) · 액션 식별자(옛 카테고리 액션 포함) · 카테고리 설명 · 토큰 hex.
@MainActor
@Suite struct PushPayloadTests {
    @Test("세 종류: 서버 트리거 본문(_apns 칸 포함) → 종류 · 대상 id · 라우트, 라우트 URL 은 되돌아온다")
    func parsesServerShapes() throws {
        let message = try #require(PushPayload(userInfo: PushHarness.messageUserInfo()))
        #expect(message.kind == .message)
        #expect(message.content == .message(peerID: PushHarness.peerID))
        #expect(message.route == .message(peerID: PushHarness.peerID))
        #expect(message.messagePeerID == PushHarness.peerID)

        let gomoku = try #require(PushPayload(userInfo: PushHarness.gomokuUserInfo()))
        #expect(gomoku.content == .gomokuInvite(matchID: PushHarness.matchID))
        #expect(gomoku.route == .gomokuInvite(matchID: PushHarness.matchID))
        #expect(gomoku.messagePeerID == nil)

        let feedback = try #require(PushPayload(userInfo: PushHarness.feedbackUserInfo()))
        #expect(feedback.content == .feedbackReply(reportID: PushHarness.reportID))
        #expect(feedback.route == .feedback(reportID: PushHarness.reportID))

        for payload in [message, gomoku, feedback] {
            #expect(AingRoute(url: payload.route.url) == payload.route, "\(payload.route.url)")
            #expect(payload.kind.categoryIdentifier == (PushHarness.categoryOf(payload.kind)))
        }
    }

    @Test("관대한 파싱과 거절: 대문자 uuid 는 소문자로 · report_id 숫자 · 빠진 report_id · message_id 는 있든 없든 무관 · 모르는 type · 필수 id 없음 · 이상한 id")
    func parsingEdges() {
        let upper = PushPayload(userInfo: PushHarness.messageUserInfo(peer: PushHarness.peerID.uppercased(), message: PushHarness.messageID.uppercased()))
        #expect(upper?.content == .message(peerID: PushHarness.peerID))

        // 서버는 message_id 를 계속 싣는다 — 앱은 읽지 않으니 빠지거나 모양이 틀려도 같은 알림(탭 → 대화)이다.
        #expect(PushPayload(userInfo: PushHarness.messageUserInfo(message: nil)) == PushPayload(userInfo: PushHarness.messageUserInfo()))
        #expect(PushPayload(userInfo: PushHarness.feedbackUserInfo(report: nil))?.route == .feedback(reportID: nil))
        #expect(PushPayload(userInfo: PushHarness.feedbackUserInfo(report: NSNumber(value: 42)))?.route == .feedback(reportID: "42"))
        #expect(PushPayload(userInfo: ["type": " MESSAGE ", "peer_id": "p-1"])?.content == .message(peerID: "p-1"))

        #expect(PushPayload(userInfo: ["type": "gomoku_turn", "match_id": "m"]) == nil, "서버가 보내지 않는 종류는 모른다")
        #expect(PushPayload(userInfo: ["aps": ["alert": "x"]]) == nil)
        #expect(PushPayload(userInfo: ["type": "message"]) == nil)
        #expect(PushPayload(userInfo: ["type": "gomoku_invite"]) == nil)
        #expect(PushPayload(userInfo: ["type": "message", "peer_id": "../etc"]) == nil)
        #expect(PushPayload(userInfo: ["type": "message", "peer_id": "a b"]) == nil)
        #expect(PushPayload(userInfo: ["type": "gomoku_invite", "match_id": String(repeating: "a", count: 65)]) == nil)
        #expect(PushPayload(userInfo: ["type": "message", "peer_id": "p-1", "message_id": "1;drop"])?.content == .message(peerID: "p-1"))

        let json = Data(#"{"aps":{"alert":{"title":"t","body":"b"}},"type":"gomoku_invite","match_id":"M-1"}"#.utf8)
        #expect(PushPayload(json: json)?.content == .gomokuInvite(matchID: "m-1"))
        #expect(PushPayload(json: Data("[]".utf8)) == nil)
    }

    @Test("액션 식별자 → 뜻: 탭 · 수락 · 지우기는 시스템 상수 글자 그대로, 옛 카테고리 액션(답장 · 읽음 · 거절)과 모르는 식별자는 탭으로 접는다")
    func actionIdentifiers() {
        #expect(PushIdentifiers.dismissAction == UNNotificationDismissActionIdentifier)
        #expect(PushAction(actionIdentifier: UNNotificationDefaultActionIdentifier) == .open)
        #expect(PushAction(actionIdentifier: "GOMOKU_ACCEPT") == .acceptInvite)
        #expect(PushAction(actionIdentifier: UNNotificationDismissActionIdentifier) == .dismiss)
        // 이미 설치된 앱이 등록했던 옛 카테고리의 버튼 — 새 빌드가 다시 등록하기 전에 눌리면 이 글자로 온다(버리지 않는다).
        for legacy in ["MESSAGE_REPLY", "MESSAGE_READ", "GOMOKU_DECLINE"] {
            #expect(PushAction(actionIdentifier: legacy) == .open, "\(legacy)")
        }
        #expect(PushAction(actionIdentifier: "WHATEVER") == .open)
        #expect(PushAction(actionIdentifier: "") == .open)
    }

    @Test("카테고리 3종(서버 aps.category 글자 그대로): MESSAGE 액션 없음 · GOMOKU_INVITE 수락(앱 열기 · 잠금 해제)만 · FEEDBACK_REPLY 액션 없음 — 앱을 열지 않는 액션 0")
    func categories() throws {
        let byID = Dictionary(uniqueKeysWithValues: PushCategories.all.map { ($0.identifier, $0) })
        #expect(Set(byID.keys) == ["MESSAGE", "GOMOKU_INVITE", "FEEDBACK_REPLY"])
        #expect(Set(PushKind.allCases.map(\.categoryIdentifier)) == Set(byID.keys))

        #expect(try #require(byID["MESSAGE"]).actions.isEmpty)
        #expect(try #require(byID["FEEDBACK_REPLY"]).actions.isEmpty)

        let gomoku = try #require(byID["GOMOKU_INVITE"])
        #expect(gomoku.actions == [PushActionSpec(identifier: "GOMOKU_ACCEPT", title: "수락", opensApp: true, requiresUnlock: true)])

        let allActions = PushCategories.all.flatMap(\.actions)
        let background = allActions.filter { !$0.opensApp }.map(\.identifier)
        #expect(background.isEmpty, "앱을 열지 않고 도는 액션이 남았다: \(background)")
        let removed: Set<String> = ["MESSAGE_REPLY", "MESSAGE_READ", "GOMOKU_DECLINE"]
        #expect(removed.isDisjoint(with: allActions.map(\.identifier)))
        // 등록된 모든 액션 식별자는 탭으로 접히지 않고 제 뜻으로 읽힌다(등록과 해석이 어긋나지 않는다).
        #expect(allActions.allSatisfy { PushAction(actionIdentifier: $0.identifier) != .open })
    }

    @Test("어댑터가 opensApp · requiresUnlock 을 시스템 옵션(.foreground · .authenticationRequired)으로 옮긴다 — iOS 전용이라 소스 계약으로 본다")
    func adapterMapsActionOptions() throws {
        // makeCategories 는 #if os(iOS) 안이라 macOS swift test 로는 컴파일되지 않는다. 여기서 .foreground 가 빠지면
        // [수락]이 앱을 열지 않고 뒤에서만 켜져 사용자 눈에는 아무 일도 안 일어난다(w10 검증 발견).
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let raw = try String(contentsOf: root.appendingPathComponent("Sources/CheckMobileKit/Push/PushNotificationCenterAdapter.swift"), encoding: .utf8)
        let code = stripComments(raw).filter { !$0.isWhitespace }
        #expect(code.contains("ifaction.opensApp{options.insert(.foreground)}"), "opensApp 이 .foreground 로 옮겨지지 않는다")
        #expect(code.contains("ifaction.requiresUnlock{options.insert(.authenticationRequired)}"), "requiresUnlock 이 .authenticationRequired 로 옮겨지지 않는다")
    }

    @Test("APNs 토큰 → hex 소문자(서버 ^[0-9a-f]{32,200}$ 를 지난다)")
    func tokenHex() {
        #expect(PushTokenFormatter.hex(Data([0x00, 0xAB, 0xFF, 0x10])) == "00abff10")
        let hex = PushTokenFormatter.hex(PushHarness.deviceToken)
        #expect(hex.count == 64)
        #expect(hex.range(of: "^[0-9a-f]{32,200}$", options: .regularExpression) != nil)
    }

    @Test("종류별 설정 켜고 끄기 · 권한 상태가 받기를 허락하는가")
    func kindsAndAuthorization() {
        let prefs = PushPrefs()
        #expect(PushKind.allCases.allSatisfy { $0.isEnabled(in: prefs) })
        let off = PushKind.gomokuInvite.setting(false, in: prefs)
        #expect(off == PushPrefs(message: true, gomokuInvite: false, feedbackReply: true))
        #expect(!PushKind.gomokuInvite.isEnabled(in: off))
        #expect(PushKind(rawValue: "gomoku_invite") == .gomokuInvite && PushKind(rawValue: "feedback_reply") == .feedbackReply)
        let allowing: [PushAuthorizationStatus] = [.authorized, .provisional, .ephemeral]
        let blocking: [PushAuthorizationStatus] = [.unknown, .notDetermined, .denied]
        #expect(allowing.filter { $0.allowsDelivery }.count == 3)
        #expect(blocking.filter { $0.allowsDelivery }.isEmpty)
    }
}

extension PushHarness {
    static func categoryOf(_ kind: PushKind) -> String {
        switch kind {
        case .message: return "MESSAGE"
        case .gomokuInvite: return "GOMOKU_INVITE"
        case .feedbackReply: return "FEEDBACK_REPLY"
        }
    }
}
