import AppKit
import SwiftUI
import CheckCore

// 아잉 마작 — **창 밖에서 아는 표면**(메뉴바 점 · 팝오버 배너 · 캐릭터 말풍선 · 미니게임 사이드바 줄)의 문구와 부품(SPEC §5.6 · §5.8).
//
// 이 파일은 부품만 둔다. 꽂는 일(팝오버 배너 자리 · 메뉴바 점 · 말풍선 · 사이드바 줄)은 통합 갈래(T)가 공용 접점 파일에서 한다.
// 스토어의 공개 표면(`hasIncomingInvite` · `visibleInvites` · `hasAwaySeatHere` · `join` · `decline` · `comeBack` · `openWindow`)만 읽는다.
// 큐브 `RummyInviteBanner` 를 베끼고 문구만 바꿨다(큐브 파일은 안 고친다).

/// 창 밖 문구 — 배너 · 말풍선 · 메뉴바 점 · 사이드바가 **한 곳**에서 읽는다(같은 사실은 한 문구).
enum MahjongInviteText {
    /// 게임 이름 — 코어 `MahjongNoticeText.gameName` 한 곳에서 받는다(창 제목 · 사이드바 · 점 · 말풍선 모두 이 값).
    static let gameName = MahjongNoticeText.gameName
    /// 사이드바 도움말(오목 '렌주룰 1:1 오목…'·체스 'FIDE 규칙 1:1 체스…' 꼴).
    static let sidebarHelp = "리치 마작 4인 대국 창을 열어요"
    /// 메뉴바 점 보이스오버 사유.
    static var dotReason: String { "\(gameName) 초대" }
    static var awayDotReason: String { "\(gameName) 자리 비움" }
    static let stakeTitle = "루비"
    static let bannerSubtitle = "4인 · 1위 +2N · 2위 본전 · 3·4위 −N"
    static let join = "참가"
    static let decline = "거절"
    static let open = "열기"
    static let comeBack = "돌아가기"
    static var joinHelp: String { "이 방에 앉고 \(gameName) 창을 열어요" }
    static var openHelp: String { "참가하지 않고 \(gameName) 창에서 방을 먼저 봐요" }
    static let someone = "누군가"

    /// 배너 첫 줄: "OO님이 아잉 마작 방에 초대했어요".
    static func bannerTitle(name: String?) -> String {
        "\(displayName(name))님이 \(gameName) 방에 초대했어요"
    }

    /// 초대 말풍선(3단 줄임 — 체스·큐브 말풍선과 같은 접기 규칙): 이름 있는 꼴 → 짧은 꼴 → 이름 없는 꼴.
    static func bubbleText(name: String?, stake: Int) -> String {
        let shortName = OverlayMessageBubble.clippedName(displayName(name))
        let full = "\(shortName)님이 \(gameName) 방에 초대했어요 · 루비 \(stake)"
        if OverlayMessageBubble.fitsCapsule(full) { return full }
        let short = "\(shortName)님의 \(gameName) 초대 · 루비 \(stake)"
        if OverlayMessageBubble.fitsCapsule(short) { return short }
        return "\(gameName) 초대 · 루비 \(stake)"
    }

    /// 자리 비움 말풍선(3단 줄임 — 초대 말풍선 규칙 그대로).
    static func awayBubbleText() -> String {
        let full = "\(gameName) — 자리 비움이 됐어요 · 차례가 오면 저절로 버려요"
        if OverlayMessageBubble.fitsCapsule(full) { return full }
        let short = "\(gameName) — 자리 비움이 됐어요"
        if OverlayMessageBubble.fitsCapsule(short) { return short }
        return "\(gameName) 자리 비움"
    }

    /// 팝오버 자리 비움 배너 첫 줄.
    static var awayBannerTitle: String { "\(gameName) — 자리 비움이 됐어요" }
    static let awayBannerSubtitle = "차례가 오면 저절로 버려요 · 손패를 한 번 누르면 돌아와요"

    static func displayName(_ name: String?) -> String {
        let trimmed = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? someone : trimmed
    }
}

/// 입구·배너 아이콘. 이 맥에서 실제로 풀리는 이름만 쓴다(없으면 대체 — 렌더로 확인).
enum MahjongEntryIcon {
    static let symbol = "square.grid.3x3.square"
    static let fallbackSymbol = "square.grid.3x3.fill"

    @MainActor
    static var resolved: String {
        NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil ? symbol : fallbackSymbol
    }
}

/// 팝오버의 **받은 아잉 마작 초대 배너** — 큐브 배너와 모양·높이가 같다. 남은 초는 세지 않는다(방 TTL 10분 — 만료는 스토어가 걷는다).
struct MahjongInviteBanner: View {
    let room: MahjongRoom
    let onJoin: () -> Void
    let onDecline: () -> Void
    var onOpen: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: MahjongEntryIcon.resolved)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(CheckTheme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(MahjongInviteText.bannerTitle(name: room.host?.displayName))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(CheckTheme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    HStack(spacing: 3) {
                        Text(MahjongInviteText.stakeTitle)
                        RubyIcon(size: 11)
                        Text("\(room.stake ?? 0) · \(MahjongInviteText.bannerSubtitle)")
                    }
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .lineLimit(1)
                }
                Spacer(minLength: 6)
            }
            HStack(spacing: 8) {
                MahjongBannerButton(title: MahjongInviteText.join, primary: true, action: onJoin)
                    .checkTooltip(MahjongInviteText.joinHelp)
                MahjongBannerButton(title: MahjongInviteText.decline, primary: false, action: onDecline)
                if let onOpen {
                    MahjongBannerButton(title: MahjongInviteText.open, primary: false, action: onOpen)
                        .checkTooltip(MahjongInviteText.openHelp)
                }
            }
        }
        .modifier(MahjongBannerChrome(tint: CheckTheme.accent))
    }
}

/// 팝오버의 **자리 비움 배너**(CC-10 — 창 밖 짝 셋 가운데 하나). [돌아가기] = 창을 열고 돌아오기.
struct MahjongAwayBanner: View {
    let onComeBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: MahjongEntryIcon.resolved)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(CheckTheme.pending)
                VStack(alignment: .leading, spacing: 2) {
                    Text(MahjongInviteText.awayBannerTitle)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(CheckTheme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(MahjongInviteText.awayBannerSubtitle)
                        .font(.caption2)
                        .foregroundStyle(CheckTheme.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 6)
            }
            MahjongBannerButton(title: MahjongInviteText.comeBack, primary: true, tint: CheckTheme.pending, action: onComeBack)
        }
        .modifier(MahjongBannerChrome(tint: CheckTheme.pending))
    }
}

private struct MahjongBannerButton: View {
    let title: String
    let primary: Bool
    var tint: Color = CheckTheme.accent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundStyle(primary ? Color.white : tint)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(primary ? tint : tint.opacity(0.14))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(tint.opacity(primary ? 0 : 0.45), lineWidth: 1))
                )
        }
        .buttonStyle(.plain)
    }
}

private struct MahjongBannerChrome: ViewModifier {
    let tint: Color

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(tint.opacity(0.16))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(tint.opacity(0.45), lineWidth: 1))
            )
    }
}

/// 미니게임 사이드바 '같이 하기' 여섯째 줄(SPEC §5.8 확정 C — 리버시 줄 뒤에 T 가 한 줄 넣는다).
struct MiniGameMahjongEntryButton: View {
    static let title = MahjongInviteText.gameName
    static let help = MahjongInviteText.sidebarHelp

    var hasInvite: Bool = false
    let action: () -> Void

    var body: some View {
        MiniGameSidebarRow(title: Self.title, icon: MahjongEntryIcon.resolved, tint: CheckTheme.pending, opensWindow: true,
                           hasInvite: hasInvite, help: Self.help, action: action)
    }
}
