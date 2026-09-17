import CheckMobileShared
import Foundation

// MARK: - 푸시 페이로드 · 카테고리 · 액션 (순수 — macOS 에서도 컴파일되어 swift test 로 검증한다)
//
// 서버 계약(SPEC-wave1 §1.5): 트리거가 만든 APNs 본문에 `type` 과 대상 id 를 싣는다. 앱은 `type` 으로만 가른다.
//   message        {"aps":{…,"category":"MESSAGE","thread-id":"message-<보낸 사람>"},"type":"message","peer_id":uuid,"message_id":uuid}
//   gomoku_invite  {"aps":{…,"category":"GOMOKU_INVITE","thread-id":"gomoku"},"type":"gomoku_invite","match_id":uuid}
//   feedback_reply {"aps":{…,"category":"FEEDBACK_REPLY"},"type":"feedback_reply","report_id":uuid}
// 오목 차례·결과·읽음은 푸시하지 않는다(서버가 만들지 않는다). 모르는 type·id 가 빠진 페이로드는 nil — 조용히 "지금" 탭으로 접지 않는다.

/// 푸시 종류 세 개(서버 `push_outbox.kind` · `client_devices.push_prefs` 의 키와 같은 이름).
package enum PushKind: String, CaseIterable, Sendable, Hashable {
    case message
    case gomokuInvite = "gomoku_invite"
    case feedbackReply = "feedback_reply"

    /// APNs `aps.category`(카테고리 등록 식별자와 같다).
    package var categoryIdentifier: String {
        switch self {
        case .message: return PushIdentifiers.messageCategory
        case .gomokuInvite: return PushIdentifiers.gomokuInviteCategory
        case .feedbackReply: return PushIdentifiers.feedbackReplyCategory
        }
    }

    /// 알림 설정 토글 이름(나 탭).
    package var settingTitle: String {
        switch self {
        case .message: return "메시지"
        case .gomokuInvite: return "오목 신청"
        case .feedbackReply: return "제보 답장"
        }
    }

    /// 토글 아래 한 줄 · 권한 설명 시트의 줄.
    package var settingDetail: String {
        switch self {
        case .message: return "누가 나에게 메시지를 보내면"
        case .gomokuInvite: return "누가 오목 대결을 신청하면"
        case .feedbackReply: return "보낸 제보에 답장이 오면"
        }
    }

    /// 설명 시트·설정 화면의 SF Symbol.
    package var systemImage: String {
        switch self {
        case .message: return "bubble.left.fill"
        case .gomokuInvite: return "circle.grid.3x3.fill"
        case .feedbackReply: return "envelope.open.fill"
        }
    }

    package func isEnabled(in prefs: PushPrefs) -> Bool {
        switch self {
        case .message: return prefs.message
        case .gomokuInvite: return prefs.gomokuInvite
        case .feedbackReply: return prefs.feedbackReply
        }
    }

    package func setting(_ enabled: Bool, in prefs: PushPrefs) -> PushPrefs {
        var next = prefs
        switch self {
        case .message: next.message = enabled
        case .gomokuInvite: next.gomokuInvite = enabled
        case .feedbackReply: next.feedbackReply = enabled
        }
        return next
    }
}

/// 알림 한 건이 가리키는 것(서버 페이로드를 그대로 옮긴 값).
package struct PushPayload: Equatable, Sendable {
    package enum Content: Equatable, Sendable {
        /// `message_id` 가 없으면 답장·읽음 액션을 하지 않는다(경계 없이 읽음을 올리면 아직 못 본 말까지 읽음이 된다).
        case message(peerID: String, messageID: String?)
        case gomokuInvite(matchID: String)
        /// `report_id` 가 없으면 제보 목록으로 연다.
        case feedbackReply(reportID: String?)
    }

    package let content: Content

    package init(content: Content) {
        self.content = content
    }

    package var kind: PushKind {
        switch content {
        case .message: return .message
        case .gomokuInvite: return .gomokuInvite
        case .feedbackReply: return .feedbackReply
        }
    }

    /// 알림을 눌렀을 때 여는 화면(SPEC-ios §3 딥링크).
    package var route: AingRoute {
        switch content {
        case .message(let peer, _): return .message(peerID: peer)
        case .gomokuInvite(let match): return .gomokuInvite(matchID: match)
        case .feedbackReply(let report): return .feedback(reportID: report)
        }
    }

    /// 메시지 알림이면 보낸 사람(대화 상대).
    package var messagePeerID: String? {
        if case .message(let peer, _) = content { return peer }
        return nil
    }

    /// `UNNotificationContent.userInfo`(APNs 본문 전체) → 값. 모르는 type · 필수 id 없음 · id 모양이 틀리면 nil.
    package init?(userInfo: [AnyHashable: Any]) {
        func text(_ key: String) -> String? {
            switch userInfo[key] {
            case let value as String: return value
            // report_id 가 언젠가 bigint 로 바뀌어도 읽히게(JSON 숫자 → 문자열).
            case let value as NSNumber: return value.stringValue
            default: return nil
            }
        }
        guard let rawType = text("type")?.trimmingCharacters(in: .whitespaces).lowercased(),
              let kind = PushKind(rawValue: rawType)
        else { return nil }
        switch kind {
        case .message:
            guard let peer = text("peer_id").flatMap(Self.safeID) else { return nil }
            content = .message(peerID: peer, messageID: text("message_id").flatMap(Self.safeID))
        case .gomokuInvite:
            guard let match = text("match_id").flatMap(Self.safeID) else { return nil }
            content = .gomokuInvite(matchID: match)
        case .feedbackReply:
            content = .feedbackReply(reportID: text("report_id").flatMap(Self.safeID))
        }
    }

    /// APNs JSON 본문 → 값(테스트 · 데모 · `simctl push` 파일 검사).
    package init?(json: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any] else { return nil }
        self.init(userInfo: object)
    }

    /// id 모양 검사 — 라우트(`AingRoute`)와 같은 규칙(영문·숫자·`-`·`_`, 1~64자). 서버 uuid 는 소문자로 맞춘다.
    package static func safeID(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 64,
              trimmed.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") })
        else { return nil }
        return trimmed.lowercased()
    }
}

/// 사용자가 알림에 한 일(액션 식별자 → 뜻).
package enum PushAction: Equatable, Sendable {
    /// 알림 본문을 눌렀다 → 화면 열기.
    case open
    /// MESSAGE "답장"(텍스트 입력).
    case reply(String)
    /// MESSAGE "읽음".
    case markRead
    /// GOMOKU_INVITE "수락"(앱을 연다).
    case acceptInvite
    /// GOMOKU_INVITE "거절".
    case declineInvite
    /// 지우기·모르는 액션 — 아무것도 하지 않는다.
    case ignore

    package init(actionIdentifier: String, textInput: String?) {
        switch actionIdentifier {
        case PushIdentifiers.defaultAction: self = .open
        case PushIdentifiers.replyAction: self = .reply(textInput ?? "")
        case PushIdentifiers.markReadAction: self = .markRead
        case PushIdentifiers.acceptAction: self = .acceptInvite
        case PushIdentifiers.declineAction: self = .declineInvite
        default: self = .ignore
        }
    }
}

/// 식별자 상수. 카테고리 이름은 서버 트리거의 `aps.category` 와 **글자까지 같아야** 액션 버튼이 붙는다.
package enum PushIdentifiers {
    package static let messageCategory = "MESSAGE"
    package static let gomokuInviteCategory = "GOMOKU_INVITE"
    package static let feedbackReplyCategory = "FEEDBACK_REPLY"

    package static let replyAction = "MESSAGE_REPLY"
    package static let markReadAction = "MESSAGE_READ"
    package static let acceptAction = "GOMOKU_ACCEPT"
    package static let declineAction = "GOMOKU_DECLINE"

    /// `UNNotificationDefaultActionIdentifier` · `UNNotificationDismissActionIdentifier` 의 값(UserNotifications 없이 비교하려고 적어 둔다 —
    /// iOS 어댑터 테스트가 실제 상수와 같은지 확인한다).
    package static let defaultAction = "com.apple.UNNotificationDefaultActionIdentifier"
    package static let dismissAction = "com.apple.UNNotificationDismissActionIdentifier"

    /// 앱이 스스로 띄우는 안내 알림(답장 실패 등)의 식별자 접두사.
    package static let localNoticePrefix = "aingcheck.local."
}

/// 카테고리 · 액션의 **플랫폼 무관 설명**. iOS 어댑터가 이것을 `UNNotificationCategory` 로 옮긴다(등록 모양을 테스트가 못 박는다).
package struct PushActionSpec: Equatable, Sendable {
    package var identifier: String
    package var title: String
    /// 텍스트 입력 액션이면 보내기 버튼 이름과 자리표시자.
    package var textInput: (button: String, placeholder: String)?
    /// 누르면 앱을 앞으로 연다.
    package var opensApp: Bool
    /// 잠금 화면에서는 기기 잠금을 풀어야 실행된다(내 계정으로 보내거나 거절하는 일).
    package var requiresUnlock: Bool
    package var isDestructive: Bool

    package static func == (lhs: PushActionSpec, rhs: PushActionSpec) -> Bool {
        lhs.identifier == rhs.identifier && lhs.title == rhs.title
            && lhs.textInput?.button == rhs.textInput?.button && lhs.textInput?.placeholder == rhs.textInput?.placeholder
            && lhs.opensApp == rhs.opensApp && lhs.requiresUnlock == rhs.requiresUnlock && lhs.isDestructive == rhs.isDestructive
    }
}

package struct PushCategorySpec: Equatable, Sendable {
    package var identifier: String
    package var actions: [PushActionSpec]
}

package enum PushCategories {
    /// SPEC-ios §5: MESSAGE(답장 텍스트 입력 · 읽음) · GOMOKU_INVITE(수락 — 앱 열기 · 거절) · FEEDBACK_REPLY(액션 없음).
    package static let all: [PushCategorySpec] = [
        PushCategorySpec(identifier: PushIdentifiers.messageCategory, actions: [
            PushActionSpec(
                identifier: PushIdentifiers.replyAction,
                title: PushText.replyAction,
                textInput: (PushText.replySend, PushText.replyPlaceholder),
                opensApp: false,
                requiresUnlock: true,
                isDestructive: false
            ),
            PushActionSpec(
                identifier: PushIdentifiers.markReadAction,
                title: PushText.markReadAction,
                textInput: nil,
                opensApp: false,
                requiresUnlock: false,
                isDestructive: false
            ),
        ]),
        PushCategorySpec(identifier: PushIdentifiers.gomokuInviteCategory, actions: [
            PushActionSpec(
                identifier: PushIdentifiers.acceptAction,
                title: PushText.acceptAction,
                textInput: nil,
                opensApp: true,
                requiresUnlock: true,
                isDestructive: false
            ),
            PushActionSpec(
                identifier: PushIdentifiers.declineAction,
                title: PushText.declineAction,
                textInput: nil,
                opensApp: false,
                requiresUnlock: true,
                isDestructive: true
            ),
        ]),
        PushCategorySpec(identifier: PushIdentifiers.feedbackReplyCategory, actions: []),
    ]
}

/// 포그라운드에서 알림이 왔을 때 보일지.
package enum PushPresentation: Equatable, Sendable {
    /// 배너 · 알림 센터 목록 · 소리.
    case banner
    /// 보이지 않는다(지금 보고 있는 대화의 메시지).
    case hidden
}

/// 시스템 알림 권한(UNAuthorizationStatus 를 플랫폼 무관하게 옮긴 값).
package enum PushAuthorizationStatus: String, Equatable, Sendable {
    /// 아직 읽지 않았다.
    case unknown
    case notDetermined
    case denied
    case authorized
    case provisional
    case ephemeral

    /// 알림을 받을 수 있는가(원격 등록을 할 이유가 있는가).
    package var allowsDelivery: Bool {
        switch self {
        case .authorized, .provisional, .ephemeral: return true
        case .unknown, .notDetermined, .denied: return false
        }
    }
}

/// APNs 기기 토큰 → hex 소문자(서버 `apns_token ~ '^[0-9a-f]{32,200}$'`).
package enum PushTokenFormatter {
    package static func hex(_ token: Data) -> String {
        token.map { String(format: "%02x", $0) }.joined()
    }
}

/// 푸시 화면 문구. 맥과 뜻이 같은 것은 코어 상수를 쓴다(보내기 실패 사유는 `MessageNoticeText`).
package enum PushText {
    // 액션 버튼
    package static let replyAction = "답장"
    package static let replySend = "보내기"
    package static let replyPlaceholder = "메시지 입력"
    package static let markReadAction = "읽음"
    package static let acceptAction = "수락"
    package static let declineAction = "거절"

    // 권한 설명 시트
    package static let primerTitle = "알림을 켜 둘까요?"
    package static let primerBody = "앱을 닫아 두어도 이런 소식을 바로 알려 드려요."
    package static let primerMacNote = "맥에서 근무 중이고 방금 입력이 있었다면 메시지·오목 신청 알림은 폰에 보내지 않아요."
    package static let primerSettingsNote = "종류별로 끄는 것은 나 탭 설정에서 할 수 있어요."
    package static let primerAllow = "알림 켜기"
    package static let primerLater = "나중에"

    // 알림 설정(나 탭)
    package static let settingsAuthorized = "켜짐"
    package static let settingsProvisional = "조용히 받기"
    package static let settingsDenied = "꺼짐 — 설정 앱에서 켤 수 있어요"
    package static let settingsNotDetermined = "아직 켜지 않았어요"
    package static let settingsUnknown = "확인 중"
    package static let settingsOpenSystem = "설정 앱 열기"
    package static let settingsEnable = "알림 켜기"
    package static let settingsSaveFailed = "알림 설정을 저장하지 못했어요. 잠시 후 다시 시도해 주세요"

    // 알림 액션 결과(앱이 스스로 띄우는 안내 알림)
    package static let replyFailedTitle = "답장을 보내지 못했어요"
    package static let replyNeedsSignIn = "앱에서 다시 로그인한 뒤 보내 주세요"
    package static let replyMessageGone = "메시지를 찾지 못했어요. 앱에서 대화를 열어 보내 주세요"
    /// 맥 `WorkTimerStore.sendMessage` 의 연결 실패 문장과 같다.
    package static let connectionUnstable = "연결이 불안정해요. 잠시 후 다시 시도해 주세요"
}
