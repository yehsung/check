import CheckCore
import CheckMobileShared
import Foundation
#if os(iOS)
import UIKit
#endif

// 확성기 배너 · 폰 화면 규칙(계약 docs/plan/megaphone-banner-contract.md — 폰 배너).
//
// 뷰(`MegaphoneBannerOverlay`, iOS 전용)는 맥 스위트가 컴파일하지 않는다 — 판정은 전부 여기 두어 맥 스위트가 잰다:
// 위로 쓸기 판정 · 끌림 오프셋 · 미룸 집계 · 미룸 다시 맞추기 · [답장] 라우트.

/// 배너 화면 판정(순수 함수).
package enum MegaphoneBannerPhoneRules {
    /// 본문 최대 줄 수.
    package static let bodyLineLimit = 4
    /// 카드 모서리.
    package static let cornerRadius: CGFloat = 22
    /// 세이프에어리어 아래 첫 틈.
    package static let topGap: CGFloat = 8
    /// 이만큼 위로 끌고 놓으면 닫힌다.
    package static let dismissDistance: CGFloat = 36
    /// 짧게 끌어도 이만큼 위로 튕기면(예측 끝점) 닫힌다.
    package static let dismissPredicted: CGFloat = 90
    /// 아래로 끄는 것은 이만큼까지만 따라온다(고무줄).
    package static let downwardLimit: CGFloat = 16
    /// 들어오기 전·나간 뒤 카드가 있는 자리: 카드 높이 + 상태바·다이내믹 아일랜드·틈을 넉넉히 넘는 값(화면 위 밖).
    package static let topClearance: CGFloat = 120
    /// 카드 높이를 재기 전(첫 장) 가정하는 높이.
    package static let assumedCardHeight: CGFloat = 180
    /// 시트·대결 화면·미니게임 판이 바뀌었는지 다시 보는 간격(배너가 떠 있거나 기다릴 때만 돈다).
    package static let deferralPollSeconds: Double = 1

    /// 손을 뗐을 때 닫는가 — 위로 충분히 끌었거나, 위로 튕겼다. 아래로 끈 것은 닫지 않는다.
    package static func swipeDismisses(translation: CGFloat, predictedEnd: CGFloat) -> Bool {
        translation <= -dismissDistance || predictedEnd <= -dismissPredicted
    }

    /// 끄는 동안 카드가 따라오는 양 — 위로는 그대로, 아래로는 1/4 만큼 `downwardLimit` 까지.
    package static func dragOffset(translation: CGFloat) -> CGFloat {
        translation <= 0 ? translation : min(translation * 0.25, downwardLimit)
    }

    /// 미끄러져 들어오고 나가는 거리(위로, 음수). 이동만 이징하고 불투명도는 건드리지 않는다.
    package static func slideOutOffset(cardHeight: CGFloat) -> CGFloat {
        -(max(cardHeight, 0) + topClearance)
    }

    /// 배너를 미뤄야 하는가: 시트·풀스크린 커버(오버레이가 그 밑에 깔려 안 보인다) · 오목·체스·테트리스 화면 · 미니게임 판 진행 중.
    package static func isDeferred(modalPresented: Bool, matchScreenVisible: Bool, miniGameRoundPlaying: Bool) -> Bool {
        modalPresented || matchScreenVisible || miniGameRoundPlaying
    }

    /// 스토어에 `deferralChanged()` 를 알려야 하는가 — 미루는데 떠 있거나(줄로 되돌린다), 풀렸는데 기다리는 것이 있다(띄운다).
    package static func needsDeferralSync(isDeferred: Bool, hasCurrent: Bool, hasQueue: Bool) -> Bool {
        isDeferred ? hasCurrent : (!hasCurrent && hasQueue)
    }

    /// 다시 보기 고리의 열쇠. 떠 있는 것도 기다리는 것도 없으면 nil(고리를 돌리지 않는다).
    package static func deferralPollKey(currentID: String?, queueCount: Int) -> String? {
        guard currentID != nil || queueCount > 0 else { return nil }
        return "\(currentID ?? "-")#\(queueCount)"
    }

    /// [답장]이 여는 곳 — 상대를 알고 내가 보낸 것이 아닐 때만 1:1 대화.
    package static func replyRoute(for banner: MegaphoneBanner) -> AingRoute? {
        guard banner.canReply, let raw = banner.senderID, let peerID = PushPayload.safeID(raw) else { return nil }
        return .message(peerID: peerID)
    }
}

/// [답장]이 대화 화면에 넘기는 이름·아바타 — 확성기 줄이 메시지함에서 빠져 대화가 비어 있어도 머리가 빈 칸이 아니게.
package struct MegaphoneReplyPeerHint: Equatable, Sendable {
    package var name: String?
    package var avatarURL: URL?

    package init(name: String?, avatarURL: URL?) {
        self.name = name
        self.avatarURL = avatarURL
    }
}

/// 배너에 보이는 글자.
package enum MegaphoneBannerPhoneText {
    package static let reply = "답장"
    package static let close = "닫기"

    package static func accessibilityLabel(name: String, body: String) -> String {
        "\(name)님의 확성기, \(body)"
    }

    package static let accessibilityHint = "위로 쓸면 닫혀요. 누르고 있으면 멈춰요."
}

/// 지금 시트·풀스크린 커버가 앱 주 창에 떠 있는가(UIKit — SwiftUI 는 이 상태를 알려 주지 않는다). 맥 빌드는 언제나 false.
package enum MegaphoneBannerModalProbe {
    @MainActor
    package static func isModalPresented() -> Bool {
        #if os(iOS)
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .filter { !$0.isHidden }
        guard let baseLevel = windows.map(\.windowLevel.rawValue).min() else { return false }
        return windows.contains { window in
            guard window.windowLevel.rawValue == baseLevel else { return false }
            var next = window.rootViewController?.presentedViewController
            while let controller = next {
                if !controller.isBeingDismissed { return true }
                next = controller.presentedViewController
            }
            return false
        }
        #else
        return false
        #endif
    }
}
