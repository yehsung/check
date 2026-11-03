import CheckCore
import Foundation
#if os(iOS)
import SwiftUI
#endif

// 폰 아잉 뒤집기 **로비 조각**(로비 갈래 3/4 — 대표 답 #d_DdwzmxPClGqk "다 넣기 (루비 걸기 포함)"): 상대 한 줄 · 받은 신청 카드 ·
// 보낸 신청 줄 · 판돈 시트 · 판 화면 위 받은 신청 띠. 로비 스크롤 자체(절의 순서)는 `GamesReversiScreen.lobby` 가 쥔다.
// 본은 폰 체스(`GamesChessScreen`)·1:1 테트리스(`GamesTetrisDuelScreen`)의 같은 이름 조각이고, 아잉 뒤집기에서 달라지는 자리만 바꿨다:
//  · 받은 신청이 **여럿**이다(서버 `me.incoming` 배열 — 체스는 하나). 로비는 다 세우고, 판 화면 띠는 첫 건 + "외 N건".
//  · 막힌 [도전] 의 까닭이 셋이다(옛 버전 · 대결 중 · 집중) — 목록 아래 풀이 줄이 **왜·언제 풀리는지**를 글자로 말한다(툴팁이 없다).
//  · 로봇 연습 판이 로비를 덮는다 — 그 사이 온 신청은 판 화면 위 띠로 세우고, [수락]은 두던 로봇 판을 끝내므로 **먼저 묻는다**.
//
// ── 이 파일이 두 겹인 까닭 ──
// 위쪽 **판정**(`GamesReversiLobbyPlan` · `GamesReversiRespond` · `GamesReversiInviteBanner` · 판돈 보내기)은 `#if os(iOS)` 밖이다 —
// 폰 뷰는 맥 스위트가 한 줄도 못 본다. 요청이 나가는 문(수락 · 판돈 신청)은 **요청 건수**로 재야 하므로 함수 하나로 모았다
// (`GamesReversiLobbyTests`). 뷰는 그 결과를 배치만 한다.

/// 로비 절들의 판정(순수에 가깝다 — 스토어 값만 읽는다).
@MainActor
package enum GamesReversiLobbyPlan {
    /// 상대 고르기 절이 그릴 것.
    package enum Users: Equatable, Sendable {
        case rows
        /// 로비를 한 번 받았고 비어 있다 — "지금 대결할 수 있는 사람이 없어요".
        case empty
        /// 아직 한 번도 못 받았다 — 로딩 줄.
        case loading
    }

    /// ★ "받았다"의 표지는 `record` 다 — 코어는 로비 ok 응답의 `me` 를 옮길 때 전적을 반드시 세운다(0승 0패 0무여도). 아잉 뒤집기 코어에는
    ///   체스·테트리스의 `hasLoadedLobby` 깃발이 없고, 코어를 고치면 맥 전체 스위트를 다시 돌려야 해서 화면이 이 사실을 읽는다.
    ///   빈 목록을 "없다"로 말하는 것은 **한 번 받은 뒤에만**이다(공용 `MobileLoadKnowledge` 와 같은 규약).
    package static func users(_ store: GamesStore) -> Users {
        if !store.reversiLobbyUsers.isEmpty { return .rows }
        return store.reversi.record != nil ? .empty : .loading
    }

    /// 사람에게 신청하는 절들(받은·보낸 신청 · 상대 · 관전 · 순위)을 세우는가. 이 기기·서버 조합에서 할 수 없으면(업데이트 필요 · 서버 준비 중)
    /// 그 절들은 서지 않는다 — 신청은 전부 거절된다. **로봇 연습은 서버를 안 타므로 그때도 연다**(판 갈래 2/4 의 약속).
    package static func showsPeopleSections(_ reversi: ReversiStore) -> Bool { reversi.availability == .available }

    /// 목록 아래 풀이 줄(지금 목록에 있는 까닭만).
    package static func lockLegends(_ store: GamesStore) -> [String] {
        ReversiPhoneText.lockLegends(users: store.reversiLobbyUsers)
    }
}

/// 받은 신청에 답하는 **한 문**. 로비 카드 · 판 화면 띠 · 로봇 판 확인 시트가 모두 이것을 부른다(세 자리가 각자 `respond` 를 부르면
/// 한 자리만 가드가 빠진다).
@MainActor
package enum GamesReversiRespond {
    /// [수락]을 눌렀을 때 갈 길.
    package enum AcceptRoute: Equatable, Sendable {
        /// 곧바로 수락 요청을 낸다.
        case send
        /// 두던 **로봇 연습 판**이 있다 — 먼저 묻는다. 코어 `respond` 에는 AI 가드가 없어 1:1 판이 서는 순간 연습 판이 말없이 사라진다
        /// (`match` 관찰자가 `discardAIGame`). 걸린 루비가 0 이라 손실은 없지만 두던 판을 잃는다 — 막지 않고 묻는다(막으면 60초 안에 진짜 대결을 놓친다).
        case confirmRobot
        /// 누를 수 없다 — 요청이 오가는 중이거나 **다른 게임의 판**이 흐른다(한 사람 한 판 · 서버도 `busy` 로 거절한다).
        case blocked
    }

    package static func canAccept(_ store: GamesStore) -> Bool {
        !store.reversi.isBusy && store.reversiEntryBlock == nil
    }

    /// 거절은 다른 게임 판이 흘러도 된다(판돈이 안 움직인다) — 요청이 오가는 중만 막는다.
    package static func canDecline(_ store: GamesStore) -> Bool { !store.reversi.isBusy }

    package static func acceptRoute(_ store: GamesStore) -> AcceptRoute {
        guard canAccept(store) else { return .blocked }
        return store.hasLiveReversiAIGame ? .confirmRobot : .send
    }

    /// 실제 수락. 확인 시트의 [끝내고 수락] 도 이 문을 지난다 — 그 사이 다른 게임 판이 섰으면(시트가 떠 있는 동안) 요청 0건.
    /// - Returns: 요청을 냈는가.
    @discardableResult
    package static func accept(_ store: GamesStore, inviteID: String) async -> Bool {
        guard canAccept(store) else { return false }
        await store.reversi.respond(inviteID: inviteID, accept: true)
        return true
    }

    @discardableResult
    package static func decline(_ store: GamesStore, inviteID: String) async -> Bool {
        guard canDecline(store) else { return false }
        await store.reversi.respond(inviteID: inviteID, accept: false)
        return true
    }
}

/// 판 화면(로봇 연습 · 끝난 판) 위에 세울 **받은 신청 띠**의 판정.
///
/// ★ 왜 띠가 있나: 판·결과 화면이 로비를 통째로 덮는다(코어 `phase`). 로봇 연습 중에 온 60초 신청은 탭 배지·게임 탭 카드 칩에만 서고,
///   사용자는 그 화면에서 [로비로]를 누를 길이 없다(로봇 판은 끝나야 [로비로]가 선다) — 그 사이 신청이 만료된다.
/// ★ **두는 중인 1:1 판 위에는 세우지 않는다** — 서버가 수락을 `busy` 로 거절하고(한 사람 한 판), 띠가 30초 시계·판을 밀어 내린다.
@MainActor
package enum GamesReversiInviteBanner {
    package static func invite(_ reversi: ReversiStore) -> ReversiInvite? {
        guard let match = reversi.match, match.isAI || match.isFinished else { return nil }
        return reversi.visibleIncoming
    }

    /// 띠에 못 실은 나머지 신청 수(0 이면 꼬리를 안 단다).
    package static func moreCount(_ reversi: ReversiStore) -> Int {
        guard invite(reversi) != nil else { return 0 }
        return max(0, reversi.visibleIncomingInvites.count - 1)
    }
}

extension GamesReversiStakeSend {
    /// 고른 판돈을 다시 누르면 해제(체스·테트리스 시트와 같은 규약 — 처음엔 아무것도 안 골라진 채 열린다).
    package static func toggled(current: ReversiStake?, tapped: ReversiStake) -> ReversiStake? {
        current == tapped ? nil : tapped
    }

    /// 판돈 시트의 [N 걸고 도전하기] — 신청이 나가는 **유일한 문**. 마지막 문 판정(`sendable`)을 지난 판돈만 스토어에 적고 신청한다
    /// (코어 `challenge` 는 `selectedStake` 로 보낸다 — 적고 보내는 두 줄이 갈리면 고른 것과 다른 판돈이 나간다).
    /// - Returns: 요청을 냈는가.
    @MainActor @discardableResult
    package static func send(_ selected: ReversiStake?, to userID: String, games: GamesStore) async -> Bool {
        guard let stake = sendable(selected, store: games.reversi, balance: games.rubyBalance,
                                   blockedBy: games.reversiEntryBlock) else { return false }
        games.reversi.selectedStake = stake
        await games.reversi.challenge(userID: userID)
        return true
    }
}

#if os(iOS)

// MARK: - 상대 한 줄

/// 상대 한 줄(폰 체스·테트리스 줄과 같은 모양): 아바타(근무 중 점) · 이름 + 센터 · 부제(근무 축 + 버튼이 못 말한 까닭) · 오른쪽 [도전] 틴트
/// (막혔으면 까닭 글자의 회색 비활성). 판정은 `GamesReversiChallengeGate` 하나, 글자는 `ReversiPhoneText.opponentRow(for:)` 하나다.
struct GamesReversiOpponentRow: View {
    let store: GamesStore
    let user: ReversiUser
    let isLast: Bool
    let onChallenge: (ReversiUser) -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    private var canChallenge: Bool {
        GamesReversiChallengeGate.isEnabled(user: user, store: store.reversi, blockedBy: store.reversiEntryBlock)
    }

    private var lines: ReversiPhoneText.OpponentRow { ReversiPhoneText.opponentRow(for: user) }

    var body: some View {
        GroupRow(divider: isLast ? .none : .inset(MobileTheme.cardPadding + 36 + MobileTheme.space3), minHeight: 56) {
            // 큰 글자: [도전]을 아래 줄로 — 한 줄에 두면 이름이 글자 하나씩 꺾인다(오목·체스 실측).
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: MobileTheme.space3) { avatar; info }
                    challengeButton
                }
            } else {
                avatar
                info
                Spacer(minLength: 8)
                challengeButton
            }
        }
    }

    private var avatar: some View {
        PersonAvatar(name: user.displayName, colorSeed: user.id,
                     status: user.isWorking ? .working : nil,
                     url: user.avatarURL.flatMap(URL.init(string:)), userID: user.id, size: 36,
                     characterHint: user.characterID)
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 1) {
            PersonName(user.displayName, center: CenterLabel.serverValue(forDisplay: user.center))
            Text(lines.subtitle)
                .font(MobileTheme.rowSubtitle)
                .foregroundStyle(MobileTheme.label2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var challengeButton: some View {
        if canChallenge {
            AingButton(ReversiPhoneText.challenge, kind: .tinted, size: .sm) { onChallenge(user) }
                .fixedSize()
                .accessibilityHint(ReversiPhoneText.challengeHint(name: user.displayName))
        } else {
            // 상대 쪽 까닭이 없으면(내 쪽 막힘 — 다른 게임 판 · 보낸 신청 · 요청 중) 버튼은 '도전' 그대로 흐려진다.
            // 내 쪽 까닭은 로비 위 안내 줄(다른 게임 판)·보낸 신청 절이 말한다.
            AingButton(lines.buttonTitle, kind: .gray, size: .sm) {}
                .disabled(true)
                .fixedSize()
        }
    }
}

// MARK: - 받은 신청 · 보낸 신청

/// 받은 신청 한 건: 아바타 44 · "솜사탕님의 신청" + 센터 · 판돈 줄 + 남은 초 · [거절 회색] [수락 채움].
/// ★ 수락이 **루비가 실제로 빠지는 순간**이다(신청만 받은 상태에서는 0원도 안 움직인다).
/// [수락]은 화면 루트로 올린다(`onAccept`) — 로봇 판 확인 시트의 주인이 루트다(`GamesReversiRespond.acceptRoute`).
struct GamesReversiInviteCard: View {
    let store: GamesStore
    let invite: ReversiInvite
    /// 띠(판 화면 위)에서 쓰는 머리 글자. nil 이면 로비 카드 모양("솜사탕님의 신청").
    var bannerTitle: String?
    /// 띠에 못 실은 나머지 신청 수(0 이면 꼬리 없음).
    var more = 0
    let onAccept: (ReversiInvite) -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            let header = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(spacing: MobileTheme.space3))
            header {
                PersonAvatar(name: invite.peer.displayName, colorSeed: invite.peer.id,
                             status: invite.peer.isWorking ? .working : nil,
                             url: invite.peer.avatarURL.flatMap(URL.init(string:)), userID: invite.peer.id, size: 44,
                             characterHint: invite.peer.characterID)
                VStack(alignment: .leading, spacing: 1) {
                    if let bannerTitle {
                        Text(bannerTitle)
                            .font(MobileTheme.rowTitle)
                            .foregroundStyle(MobileTheme.label)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        PersonName(ReversiPhoneText.incomingTitle(name: invite.peer.displayName),
                                   center: CenterLabel.serverValue(forDisplay: invite.peer.center))
                    }
                    HStack(spacing: 0) {
                        GamesStakeLine(stake: invite.stake, prefix: ReversiPhoneText.stakeTitle,
                                       suffix: ReversiPhoneText.stakeGainSuffix(invite.stake))
                        GamesReversiRemainingText(store: store.reversi, expiresAt: invite.expiresAt, prefix: " · ")
                        if more > 0 {
                            Text(" · " + ReversiPhoneText.incomingMore(more))
                        }
                    }
                    .font(MobileTheme.rowSubtitle)
                    .foregroundStyle(MobileTheme.label2)
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, MobileTheme.cardPadding)
            .padding(.top, 14)
            .padding(.bottom, 10)
            Group {
                if typeSize.isAccessibilitySize {
                    VStack(spacing: 8) { acceptButton; declineButton }
                } else {
                    HStack(spacing: 10) { declineButton; acceptButton }
                }
            }
            .padding(.horizontal, MobileTheme.cardPadding)
            .padding(.bottom, MobileTheme.cardPadding)
        }
    }

    private var acceptButton: some View {
        AingButton(ReversiPhoneText.accept, kind: .filled, size: .md, fillsWidth: true) {
            onAccept(invite)
        }
        .disabled(!GamesReversiRespond.canAccept(store))
    }

    private var declineButton: some View {
        AingButton(ReversiPhoneText.decline, kind: .gray, size: .md, fillsWidth: true) {
            Task { await GamesReversiRespond.decline(store, inviteID: invite.id) }
        }
        .disabled(!GamesReversiRespond.canDecline(store))
    }
}

/// 보낸 신청 한 줄: 아바타 · "구름빵님에게 신청했어요" · 판돈 · 남은 초 · [취소] 회색 알약.
struct GamesReversiOutgoingRow: View {
    let store: GamesStore
    let invite: ReversiOutgoing

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        GroupRow(divider: .none, minHeight: 56) {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: MobileTheme.space3) { avatar; texts }
                    cancelButton
                }
            } else {
                avatar
                texts
                Spacer(minLength: 8)
                cancelButton
            }
        }
    }

    private var avatar: some View {
        PersonAvatar(name: invite.peer.displayName, colorSeed: invite.peer.id,
                     status: invite.peer.isWorking ? .working : nil,
                     url: invite.peer.avatarURL.flatMap(URL.init(string:)), userID: invite.peer.id, size: 36,
                     characterHint: invite.peer.characterID)
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(ReversiPhoneText.outgoingTitle(name: invite.peer.displayName.isEmpty
                                                ? ReversiPhoneText.opponentFallbackName : invite.peer.displayName))
                .font(MobileTheme.rowTitle)
                .foregroundStyle(MobileTheme.label)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 0) {
                GamesStakeLine(stake: invite.stake, prefix: ReversiPhoneText.stakeTitle)
                GamesReversiRemainingText(store: store.reversi, expiresAt: invite.expiresAt, prefix: " · ")
            }
            .font(MobileTheme.rowSubtitle)
            .foregroundStyle(MobileTheme.label2)
        }
        .accessibilityElement(children: .combine)
    }

    private var cancelButton: some View {
        AingButton(ReversiPhoneText.cancel, kind: .gray, size: .sm) {
            Task { await store.reversi.cancelChallenge() }
        }
        .disabled(store.reversi.isBusy)
        .fixedSize()
    }
}

/// 신청 만료까지 남은 초("42초 남음") — **잎 뷰**(초 단위 값은 잎만 읽는다 · 스토어는 매초 아무것도 대입하지 않는다).
/// 시계는 스토어 시계(앱 시계 — 데모 고정 시계와 같은 눈금). 만료된 신청은 코어 타이머가 걷는다(`scheduleInviteExpiry`).
struct GamesReversiRemainingText: View {
    let store: ReversiStore
    let expiresAt: Date
    var prefix = ""

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let remaining = expiresAt.timeIntervalSince(store.clock())
            Text(prefix + ReversiPhoneText.remainingPhrase(remaining))
                .monospacedDigit()
                .accessibilityLabel(ReversiPhoneText.clockAccessibility(remaining))
        }
    }
}

// MARK: - 판 화면 위 받은 신청 띠

/// 로봇 연습·끝난 판 화면 위 받은 신청 띠(판정 `GamesReversiInviteBanner`). 카드는 로비와 같은 부품이고 머리 글자만 띠 문장이다.
struct GamesReversiInviteBannerView: View {
    let store: GamesStore
    let onAccept: (ReversiInvite) -> Void

    var body: some View {
        if let invite = GamesReversiInviteBanner.invite(store.reversi) {
            InsetGroup {
                GamesReversiInviteCard(store: store, invite: invite,
                                       bannerTitle: ReversiPhoneText.bannerTitle(name: invite.peer.displayName),
                                       more: GamesReversiInviteBanner.moreCount(store.reversi),
                                       onAccept: onAccept)
            }
            .padding(.horizontal, MobileTheme.sideMargin)
            .padding(.top, MobileTheme.space1)
            .padding(.bottom, MobileTheme.space2)
            .background(MobileTheme.background)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

// MARK: - 판돈 시트

/// 판돈 시트(폰 체스·테트리스 시트와 같은 모양): **아무것도 안 골라진 채** 열리고, 판돈은 고르기만(다시 누르면 해제), 신청은 맨 아래 채운 버튼 하나.
/// ★ 캡션이 **거짓말을 하지 않는 것**이 이 시트의 계약이다: 신청만 한 상태에서는 0원도 안 움직이고, 양쪽에서 빠지는 것은 **수락하는 순간**이다.
struct GamesReversiStakeSheet: View {
    let store: GamesStore
    let target: ReversiUser

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selected: ReversiStake?

    private var reversi: ReversiStore { store.reversi }
    /// 공유 미러 먼저 — `GamesStore.rubyBalance` 와 같은 순서.
    private var balance: Int? { store.rubyBalance }

    /// 지금 신청을 **낼 수 있는 판돈**(못 내면 nil). 판정은 `GamesReversiStakeSend` 한 곳이다.
    private var sendable: ReversiStake? {
        GamesReversiStakeSend.sendable(selected, store: reversi, balance: balance, blockedBy: store.reversiEntryBlock)
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(ReversiPhoneText.stakeTitle,
                        subtitle: ReversiPhoneText.stakePromptTitle(name: target.displayName),
                        onClose: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: MobileTheme.space4) {
                    InsetGroup {
                        GroupRow(divider: .none, minHeight: 64) {
                            PersonAvatar(name: target.displayName, colorSeed: target.id,
                                         status: target.isWorking ? .working : nil,
                                         url: target.avatarURL.flatMap(URL.init(string:)), userID: target.id, size: 44,
                                         characterHint: target.characterID)
                            VStack(alignment: .leading, spacing: 1) {
                                PersonName(target.displayName, center: CenterLabel.serverValue(forDisplay: target.center))
                                Text(selected.map { ReversiPhoneText.stakePromptChosen($0.rawValue) }
                                        ?? ReversiPhoneText.stakePromptCaption)
                                    .font(MobileTheme.rowSubtitle)
                                    .monospacedDigit()
                                    .foregroundStyle(selected == nil ? MobileTheme.label2 : MobileTheme.accent)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    // 큰 글자에서는 세로로 — 가로 셋에 "10" 이 줄바꿈되어 "1/0" 으로 읽혔다(오목 AX 실측).
                    Group {
                        if typeSize.isAccessibilitySize {
                            VStack(spacing: 10) {
                                ForEach(ReversiStake.allCases, id: \.rawValue) { stake in stakeOption(stake) }
                            }
                        } else {
                            HStack(spacing: 10) {
                                ForEach(ReversiStake.allCases, id: \.rawValue) { stake in stakeOption(stake) }
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Text(ReversiPhoneText.myRubyTitle)
                                .font(.footnote)
                                .foregroundStyle(MobileTheme.label2)
                            if let balance {
                                RubyPrice(balance, isShort: false, gemSize: 14, style: .footnote)
                            } else {
                                Text(ReversiPhoneText.unknownNumber).font(.footnote).foregroundStyle(MobileTheme.label2)
                            }
                            if ReversiStake.allCases.contains(where: { !GamesReversiStakeSend.affordable($0, balance: balance) }) {
                                Text(ReversiPhoneText.bulletPrefix + ReversiPhoneText.stakeShortfall)
                                    .font(.footnote)
                                    .foregroundStyle(MobileTheme.label2)
                            }
                        }
                        Text(ReversiPhoneText.stakeCaption)
                            .font(.footnote)
                            .foregroundStyle(MobileTheme.label2)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(ReversiPhoneText.stakeNotHeldYet(ttlSeconds: Int(reversi.inviteTTLSeconds)))
                            .font(.footnote)
                            .foregroundStyle(MobileTheme.label2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, MobileTheme.titleMargin - MobileTheme.sideMargin)
                }
                .padding(.horizontal, MobileTheme.sideMargin)
                .padding(.top, MobileTheme.space2)
                .padding(.bottom, MobileTheme.space4)
            }
            // ★ 아무것도 안 고르면 글자가 "판돈을 고르세요" 이고 **비활성**이다 — 골라야 [도전하기]가 생긴다.
            AingButton(selected.map { ReversiPhoneText.challengeWithStake($0.rawValue) }
                        ?? ReversiPhoneText.stakePromptCaption,
                       kind: .filled, size: .lg, fillsWidth: true) {
                guard sendable != nil else { return }
                let choice = selected
                let targetID = target.id
                dismiss()
                Task { await GamesReversiStakeSend.send(choice, to: targetID, games: store) }
            }
            .disabled(sendable == nil)
            .padding(.horizontal, MobileTheme.sideMargin)
            .padding(.bottom, MobileTheme.space3)
        }
        .background(MobileTheme.background.ignoresSafeArea())
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.medium, .large])
        .presentationDragIndicator(.hidden)
    }

    /// 판돈 칸 하나 — **고르기만** 한다(선택 = 파랑 틴트 + 파랑 테두리 + 체크). 모자라면 흐린 가격 + 비활성, **잔액을 모르면 막지 않는다**.
    private func stakeOption(_ stake: ReversiStake) -> some View {
        let isSelected = selected == stake
        let affordable = GamesReversiStakeSend.affordable(stake, balance: balance)
        let enabled = affordable && !reversi.isBusy
        let shape = RoundedRectangle(cornerRadius: MobileTheme.tileRadius, style: .continuous)
        return Button {
            withAnimation(.easeOut(duration: 0.15)) {
                selected = GamesReversiStakeSend.toggled(current: selected, tapped: stake)
            }
        } label: {
            VStack(spacing: 2) {
                RubyPrice(stake.rawValue, isShort: !affordable, gemSize: 20, style: .title3)
                Text(ReversiPhoneText.stakeGain(stake.rawValue))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(affordable ? MobileTheme.label2 : MobileTheme.label3Text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 72)
            .background(shape.fill(isSelected ? MobileTheme.accentTint : MobileTheme.surface))
            .overlay(shape.strokeBorder(isSelected ? MobileTheme.accent : Color.clear, lineWidth: 2))
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(MobileTheme.accent)
                        .padding(7)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(ReversiPhoneText.stakeOptionAccessibility(stake.rawValue))
        .accessibilityValue(isSelected ? ReversiPhoneText.selected : (affordable ? "" : ReversiPhoneText.stakeShortfall))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#endif
