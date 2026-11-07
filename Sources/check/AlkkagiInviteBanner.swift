import SwiftUI
import CheckCore

enum AlkkagiInviteText {
    static let dotReason = "알까기 신청"
    static let subtitle = "수락하면 돌 배치를 시작해요"
    static let accept = "수락"
    static let responding = "응답 중…"
    static let decline = "거절"
    static let open = "보기"
    static let acceptHelp = "수락하고 알까기 창을 열어요"
    static let openHelp = "알까기 창에서 이 신청을 봐요"

    static func title(name: String) -> String {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(name.isEmpty ? "누군가" : name)님이 알까기 대결을 신청했어요"
    }
}

/// 받은 신청과 액션만 주입한다. 응답 상태와 만료 목록은 스토어가 관리한다.
struct AlkkagiInviteBanner: View {
    let invite: AlkkagiInvite
    let isBusy: Bool
    let serverNowMs: () -> Double
    let onAccept: () -> Void
    let onDecline: () -> Void
    var onOpen: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                if let characterID = invite.opponent.characterID {
                    CharacterPortrait(characterID: characterID)
                        .frame(width: 24, height: 24)
                } else {
                    Image(systemName: "circle.lefthalf.filled")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(CheckTheme.accent)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(AlkkagiInviteText.title(name: invite.opponent.displayName))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(CheckTheme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(AlkkagiInviteText.subtitle)
                        .font(.caption2)
                        .foregroundStyle(CheckTheme.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
                AlkkagiInviteBannerCountdown(expiresAtMs: invite.expiresAtMs, serverNowMs: serverNowMs)
            }
            HStack(spacing: 8) {
                AlkkagiInviteBannerButton(
                    title: isBusy ? AlkkagiInviteText.responding : AlkkagiInviteText.accept,
                    primary: true,
                    action: onAccept
                )
                .checkTooltip(AlkkagiInviteText.acceptHelp)
                .disabled(isBusy)
                AlkkagiInviteBannerButton(title: AlkkagiInviteText.decline, primary: false, action: onDecline)
                    .disabled(isBusy)
                if let onOpen {
                    AlkkagiInviteBannerButton(title: AlkkagiInviteText.open, primary: false, action: onOpen)
                        .checkTooltip(AlkkagiInviteText.openHelp)
                }
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(CheckTheme.accent.opacity(0.16))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(CheckTheme.accent.opacity(0.55), lineWidth: 1))
        )
    }
}

/// 서버 보정 시계는 이 잎에서만 읽고, 팝오버가 비활성이면 기존 공용 카운트다운을 멈춘다.
private struct AlkkagiInviteBannerCountdown: View {
    let expiresAtMs: Double
    let serverNowMs: () -> Double
    @Environment(\.controlActiveState) private var controlActiveState

    var body: some View {
        TetrisDuelCountdownText(
            expiresAt: Date(timeIntervalSince1970: expiresAtMs / 1_000),
            isLive: controlActiveState != .inactive,
            now: { Date(timeIntervalSince1970: serverNowMs() / 1_000) }
        )
    }
}

private struct AlkkagiInviteBannerButton: View {
    let title: String
    let primary: Bool
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(primary ? Color.white : CheckTheme.accent)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(primary ? CheckTheme.accent : CheckTheme.accent.opacity(0.14))
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .stroke(CheckTheme.accent.opacity(primary ? 0 : 0.45), lineWidth: 1))
                )
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.5)
    }
}
