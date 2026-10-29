import AppKit
import SwiftUI
import CheckCore

// 아잉 큐브(v0.3.69) — **창 밖에서 초대를 아는 세 표면**(메뉴바 점 · 팝오버 배너 · 캐릭터 말풍선)의 문구와 배너.
//
// 창(`CheckRummyWindowController`)과 판 화면(`RummyPanel`)은 다른 갈래 몫이라 이 파일은 그 둘을 모른다 —
// 스토어의 공개 표면(`RummyStore.incomingInvites` · `join` · `decline` · `openWindow`)만 읽는다.
// 아잉 큐브 폴링도 창이 보일 때만 돌고 창을 여는 길은 미니게임 머리글 하나뿐이라, 창을 안 연 사람에게는 이 세 표면과
// 팝오버 계기(`refreshLobbyIfStale`)·소켓 신호가 초대를 아는 전부다. 이번 버전은 푸시가 없다(설계 §0).

/// 초대 문구 — 배너 · 말풍선 · 메뉴바 점이 **한 곳**에서 읽는다(같은 사실은 한 문구).
enum RummyInviteText {
    /// 게임 이름(설계 §1 창 제목과 같다).
    static let gameName = "아잉 큐브"
    /// 미니게임 머리글 입구의 짧은 이름(설계 §1).
    static let entrySegmentTitle = "큐브"
    /// 메뉴바 점 보이스오버 사유.
    static let dotReason = "아잉 큐브 초대"
    static let stakeTitle = "판돈"
    static let bannerSubtitle = "2~4인 · 등수별 분배"
    static let join = "참가"
    static let decline = "거절"
    static let open = "열기"
    static let joinHelp = "이 방에 앉고 아잉 큐브 창을 열어요"
    static let openHelp = "참가하지 않고 아잉 큐브 창에서 방을 먼저 봐요"
    /// 이름이 비었을 때(서버가 이름을 못 실었다).
    static let someone = "누군가"

    /// 배너 첫 줄: "OO님이 아잉 큐브에 초대했어요".
    static func bannerTitle(name: String?) -> String {
        "\(displayName(name))님이 \(gameName)에 초대했어요"
    }

    /// 말풍선 문구(순수). 체스·테트리스 말풍선과 **같은 접기 규칙**(캡슐에 들어갈 때까지 세 단계)이고 게임 이름만 다르다.
    static func bubbleText(name: String?, stake: Int) -> String {
        let shortName = OverlayMessageBubble.clippedName(displayName(name))
        let full = "\(shortName)님이 \(gameName)에 초대했어요 · 판돈 \(stake)"
        if OverlayMessageBubble.fitsCapsule(full) { return full }
        let short = "\(shortName)님의 \(gameName) 초대 · 판돈 \(stake)"
        if OverlayMessageBubble.fitsCapsule(short) { return short }
        return "\(gameName) 초대 · 판돈 \(stake)"
    }

    static func displayName(_ name: String?) -> String {
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? someone : trimmed
    }
}

/// 입구·배너 아이콘. 이 맥에서 실제로 풀리는 이름만 쓴다(없으면 아무것도 안 그려 자리만 빈다 — 테트리스 아이콘과 같은 규약).
enum RummyEntryIcon {
    static let symbol = "cube.fill"
    static let fallbackSymbol = "square.stack.3d.up.fill"

    @MainActor
    static var resolved: String {
        NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil ? symbol : fallbackSymbol
    }
}

/// 팝오버의 **받은 아잉 큐브 초대 배너**(v0.3.69). 테트리스 배너(`TetrisDuelInviteBanner`)와 모양·높이(92)가 같다 —
/// 다른 것은 문구와 남은 초가 없다는 것뿐이다(방 TTL 이 10분이라 초를 세지 않는다 — 만료는 스토어가 목록에서 걷는다).
///
/// ★ 이 배너가 없으면 초대를 받은 사람이 팝오버에서 볼 곳이 없다 — 창을 여는 길은 미니게임 머리글 하나뿐이고
///   아잉 큐브 폴링은 창이 보일 때만 돈다.
struct RummyInviteBanner: View {
    let room: RummyRoom
    let onJoin: () -> Void
    let onDecline: () -> Void
    var onOpen: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: RummyEntryIcon.resolved)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(CheckTheme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(RummyInviteText.bannerTitle(name: room.host?.displayName))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(CheckTheme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    HStack(spacing: 3) {
                        Text(RummyInviteText.stakeTitle)
                        RubyIcon(size: 11)
                        Text("\(room.stake ?? 0) · \(RummyInviteText.bannerSubtitle)")
                    }
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .lineLimit(1)
                }
                Spacer(minLength: 6)
            }
            HStack(spacing: 8) {
                Button(action: onJoin) {
                    Text(RummyInviteText.join)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background(RoundedRectangle(cornerRadius: 8).fill(CheckTheme.accent))
                }
                .buttonStyle(.plain)
                .checkTooltip(RummyInviteText.joinHelp)
                Button(action: onDecline) {
                    Text(RummyInviteText.decline)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(CheckTheme.accent)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background(Self.secondaryFill)
                }
                .buttonStyle(.plain)
                if let onOpen {
                    Button(action: onOpen) {
                        Text(RummyInviteText.open)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(CheckTheme.accent)
                            .frame(maxWidth: .infinity)
                            .frame(height: 28)
                            .background(Self.secondaryFill)
                    }
                    .buttonStyle(.plain)
                    .checkTooltip(RummyInviteText.openHelp)
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
                    .stroke(CheckTheme.accent.opacity(0.45), lineWidth: 1))
        )
    }

    private static var secondaryFill: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(CheckTheme.accent.opacity(0.14))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(CheckTheme.accent.opacity(0.45), lineWidth: 1))
    }
}
