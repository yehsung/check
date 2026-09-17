import CheckCore
import CheckMobileShared
import Foundation
import Testing
import UserNotifications
@testable import CheckMobileKit

/// 푸시 페이로드 파싱(서버 §1.5 모양 그대로) · 액션 식별자 · 카테고리 설명 · 토큰 hex · 보내기 실패 문구.
@MainActor
@Suite struct PushPayloadTests {
    @Test("세 종류: 서버 트리거 본문(_apns 칸 포함) → 종류 · 대상 id · 라우트, 라우트 URL 은 되돌아온다")
    func parsesServerShapes() throws {
        let message = try #require(PushPayload(userInfo: PushHarness.messageUserInfo()))
        #expect(message.kind == .message)
        #expect(message.content == .message(peerID: PushHarness.peerID, messageID: PushHarness.messageID))
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

    @Test("관대한 파싱과 거절: 대문자 uuid 는 소문자로 · report_id 숫자 · 빠진 message_id/report_id · 모르는 type · 필수 id 없음 · 이상한 id")
    func parsingEdges() {
        let upper = PushPayload(userInfo: PushHarness.messageUserInfo(peer: PushHarness.peerID.uppercased(), message: PushHarness.messageID.uppercased()))
        #expect(upper?.content == .message(peerID: PushHarness.peerID, messageID: PushHarness.messageID))

        #expect(PushPayload(userInfo: PushHarness.messageUserInfo(message: nil))?.content == .message(peerID: PushHarness.peerID, messageID: nil))
        #expect(PushPayload(userInfo: PushHarness.feedbackUserInfo(report: nil))?.route == .feedback(reportID: nil))
        #expect(PushPayload(userInfo: PushHarness.feedbackUserInfo(report: NSNumber(value: 42)))?.route == .feedback(reportID: "42"))
        #expect(PushPayload(userInfo: ["type": " MESSAGE ", "peer_id": "p-1"])?.content == .message(peerID: "p-1", messageID: nil))

        #expect(PushPayload(userInfo: ["type": "gomoku_turn", "match_id": "m"]) == nil, "서버가 보내지 않는 종류는 모른다")
        #expect(PushPayload(userInfo: ["aps": ["alert": "x"]]) == nil)
        #expect(PushPayload(userInfo: ["type": "message"]) == nil)
        #expect(PushPayload(userInfo: ["type": "gomoku_invite"]) == nil)
        #expect(PushPayload(userInfo: ["type": "message", "peer_id": "../etc"]) == nil)
        #expect(PushPayload(userInfo: ["type": "message", "peer_id": "a b"]) == nil)
        #expect(PushPayload(userInfo: ["type": "gomoku_invite", "match_id": String(repeating: "a", count: 65)]) == nil)
        // message_id 모양이 틀리면 버린다(답장·읽음을 하지 않는다) — 알림 자체(탭 → 대화)는 산다.
        #expect(PushPayload(userInfo: ["type": "message", "peer_id": "p-1", "message_id": "1;drop"])?.content == .message(peerID: "p-1", messageID: nil))

        let json = Data(#"{"aps":{"alert":{"title":"t","body":"b"}},"type":"gomoku_invite","match_id":"M-1"}"#.utf8)
        #expect(PushPayload(json: json)?.content == .gomokuInvite(matchID: "m-1"))
        #expect(PushPayload(json: Data("[]".utf8)) == nil)
    }

    @Test("액션 식별자 → 뜻, 시스템 상수와 같은 글자")
    func actionIdentifiers() {
        #expect(PushIdentifiers.defaultAction == UNNotificationDefaultActionIdentifier)
        #expect(PushIdentifiers.dismissAction == UNNotificationDismissActionIdentifier)
        #expect(PushAction(actionIdentifier: UNNotificationDefaultActionIdentifier, textInput: nil) == .open)
        #expect(PushAction(actionIdentifier: "MESSAGE_REPLY", textInput: "좋아요") == .reply("좋아요"))
        #expect(PushAction(actionIdentifier: "MESSAGE_REPLY", textInput: nil) == .reply(""))
        #expect(PushAction(actionIdentifier: "MESSAGE_READ", textInput: nil) == .markRead)
        #expect(PushAction(actionIdentifier: "GOMOKU_ACCEPT", textInput: nil) == .acceptInvite)
        #expect(PushAction(actionIdentifier: "GOMOKU_DECLINE", textInput: nil) == .declineInvite)
        #expect(PushAction(actionIdentifier: UNNotificationDismissActionIdentifier, textInput: nil) == .ignore)
        #expect(PushAction(actionIdentifier: "WHATEVER", textInput: nil) == .ignore)
    }

    @Test("카테고리 3종(서버 aps.category 글자 그대로): MESSAGE 답장(텍스트·잠금 해제)+읽음 · GOMOKU_INVITE 수락(앱 열기)+거절(파괴적) · FEEDBACK_REPLY 액션 없음")
    func categories() throws {
        let byID = Dictionary(uniqueKeysWithValues: PushCategories.all.map { ($0.identifier, $0) })
        #expect(Set(byID.keys) == ["MESSAGE", "GOMOKU_INVITE", "FEEDBACK_REPLY"])
        #expect(Set(PushKind.allCases.map(\.categoryIdentifier)) == Set(byID.keys))

        let message = try #require(byID["MESSAGE"])
        #expect(message.actions.map(\.identifier) == ["MESSAGE_REPLY", "MESSAGE_READ"])
        let reply = message.actions[0]
        #expect(reply.title == "답장")
        #expect(reply.textInput?.button == "보내기")
        #expect(reply.requiresUnlock, "잠금 화면에서 남이 내 이름으로 답장하지 못하게")
        #expect(!reply.opensApp)
        #expect(message.actions[1].title == "읽음")
        #expect(message.actions[1].textInput == nil)

        let gomoku = try #require(byID["GOMOKU_INVITE"])
        #expect(gomoku.actions.map(\.identifier) == ["GOMOKU_ACCEPT", "GOMOKU_DECLINE"])
        #expect(gomoku.actions[0].title == "수락" && gomoku.actions[0].opensApp)
        #expect(gomoku.actions[1].title == "거절" && gomoku.actions[1].isDestructive && !gomoku.actions[1].opensApp)

        #expect(try #require(byID["FEEDBACK_REPLY"]).actions.isEmpty)
    }

    @Test("APNs 토큰 → hex 소문자(서버 ^[0-9a-f]{32,200}$ 를 지난다)")
    func tokenHex() {
        #expect(PushTokenFormatter.hex(Data([0x00, 0xAB, 0xFF, 0x10])) == "00abff10")
        let hex = PushTokenFormatter.hex(PushHarness.deviceToken)
        #expect(hex.count == 64)
        #expect(hex.range(of: "^[0-9a-f]{32,200}$", options: .regularExpression) != nil)
    }

    @Test("보내기 실패 문구는 맥과 같은 코어 문장")
    func sendFailureNotices() {
        func response(_ status: String, max: Int? = nil) -> PokeSendResponse {
            PokeSendResponse(status: status, maxLength: max)
        }
        #expect(PushCoordinator.sendFailureNotice(response("ok")) == nil)
        #expect(PushCoordinator.sendFailureNotice(response("target_focused")) == MessageNoticeText.targetFocused)
        #expect(PushCoordinator.sendFailureNotice(response("target_not_working")) == MessageNoticeText.targetNotWorking)
        #expect(PushCoordinator.sendFailureNotice(response("not_working")) == MessageNoticeText.notWorking)
        #expect(PushCoordinator.sendFailureNotice(response("blackout")) == MessageNoticeText.blackout)
        #expect(PushCoordinator.sendFailureNotice(response("not_text")) == MessageNoticeText.notText)
        #expect(PushCoordinator.sendFailureNotice(response("too_long", max: 150)) == MessageNoticeText.tooLong(maxLength: 150))
        #expect(PushCoordinator.sendFailureNotice(response("flood")) == MessageNoticeText.invalid)
        #expect(PushCoordinator.sendFailureNotice(response("weird")) == MessageNoticeText.invalid)
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

    @Test("병합 계약: 메시지·나 탭 스토어가 같은 이름 메서드를 가지면 기본 구현이 아니라 그 메서드가 불린다")
    func witnessPrefersStoreMethod() {
        final class StoreWithEntry: PushMessageRefreshing, PushFeedbackRefreshing {
            var peers: [String] = []
            var reports: [String?] = []
            func didReceiveMessagePush(peerID: String) { peers.append(peerID) }
            func didReceiveFeedbackReplyPush(reportID: String?) { reports.append(reportID) }
        }
        final class StoreWithoutEntry: PushMessageRefreshing {}
        func deliver<S: PushMessageRefreshing>(_ store: S) { store.didReceiveMessagePush(peerID: "p") }
        func deliverFeedback<S: PushFeedbackRefreshing>(_ store: S) { store.didReceiveFeedbackReplyPush(reportID: "r") }
        let with = StoreWithEntry()
        deliver(with)
        deliverFeedback(with)
        #expect(with.peers == ["p"] && with.reports == ["r"])
        deliver(StoreWithoutEntry()) // 기본 구현 — 아무 일도 없고 죽지 않는다
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
