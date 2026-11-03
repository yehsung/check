import CheckCore
import Foundation
#if os(iOS)
import SwiftUI
#endif

// 폰 아잉 뒤집기 **화면 하나**(1.0.17) — 로비 · 판 · AI 연습 · 결과 · 관전 · 순위를 코어 `phase`·`spectating` 으로 갈아 끼운다(체스와 같은 구조).
//
// ── 이 파일이 두 겹인 까닭 ──
// 아래 **판정**(`GamesReversiCard` · `GamesReversiUnavailable` · `GamesReversiChallengeGate` · `GamesReversiStakeSend`)은 `#if os(iOS)` **밖**이다 —
// 폰 뷰는 맥 스위트가 한 줄도 못 본다(저장소 메모 '폰 뷰는 맥 스위트가 못 본다'). 그림(뷰)은 판정을 받아 그리기만 한다.
//
// ── 수명은 직접 코어를 부르지 않는다 ──
// `onAppear` → `GamesStore.reversiScreenDidAppear()`, `onDisappear` → `…DidDisappear()` 뿐이다. 그 둘이 `openWindow`·`windowDidShow`·
// `stopWatching`·`windowDidHide`·`windowDidClose` 의 순서와 끝난 판 접기를 쥔다(배선 갈래 1/4). 여기서 코어 창 문을 직접 부르면 그 순서가 두 벌이 된다.
// 순위·관전은 **자식 화면이 아니라 이 화면 안의 절·탭**이어야 한다 — push 하면 `onDisappear` → `windowDidHide()` 로 폴링이 죽는다(체스 머리말).

/// 게임 탭 **아잉 뒤집기 카드**가 그리는 한 줄의 판정(칩 + 보조 줄). 서열을 한 열거로 못 박는다(테트리스 카드와 같은 까닭 — 자리마다 삼항으로 고르면
/// 서열이 두 벌이 되어 한쪽만 고쳐진다): 차단 > 진행 중 판 > 받은 신청 > 보낸 신청 > 전적 > 기본 한 줄.
@MainActor
package enum GamesReversiCard {
    package enum Line: String, Equatable, Sendable, CaseIterable {
        /// 다른 게임 판이 흐른다 — 카드가 흐려지고 눌리지 않는다.
        case blocked
        /// 내 판이 흐른다(1:1 — 같은 계정 다른 기기의 판 포함 · AI 연습 판은 받은 신청이 없을 때만).
        case activeMatch
        case incoming
        case outgoing
        case record
        /// 칩도 보조 줄 재료도 없다 — **할 일**을 말한다.
        case idle
    }

    package static func line(_ store: GamesStore) -> Line {
        if store.reversiEntryBlock != nil { return .blocked }
        let reversi = store.reversi
        let incoming = reversi.visibleIncomingInvites.count
        // AI 연습 판은 사람의 신청을 가리지 않는다 — 오목·체스 카드와 같은 규칙(`GamesText.hubShowsActiveMatch`).
        if GamesText.hubShowsActiveMatch(active: store.hasActiveReversiMatch, isAIMatch: reversi.isAIMatch, incoming: incoming) {
            return .activeMatch
        }
        if incoming > 0 { return .incoming }
        if reversi.outgoing != nil { return .outgoing }
        return reversi.record != nil ? .record : .idle
    }

    /// 칩(없으면 nil). 막힌 칩은 **두는 판의 이름**을 말한다(`ChessPhoneText` 한 곳이 조립한다 — 뷰가 지어내지 않는다).
    package static func chip(_ store: GamesStore) -> String? {
        switch line(store) {
        case .blocked: return ChessPhoneText.entryBlock(playing: store.reversiEntryBlock?.text)
        case .activeMatch: return GamesText.activeMatchChip
        case .incoming: return ReversiPhoneText.incomingChip(store.reversi.visibleIncomingInvites.count)
        case .outgoing, .record, .idle: return nil
        }
    }

    /// 보조 줄(없으면 nil). 막혔을 때 칩은 왜 막혔는지, 이 줄은 **언제 풀리는지**를 말한다(폰엔 호버 툴팁이 없다).
    package static func detail(_ store: GamesStore) -> String? {
        let recordLine = store.reversi.record.map { ReversiPhoneText.recordTitle + " " + ReversiPhoneText.record($0) }
        switch line(store) {
        case .blocked:
            return ChessPhoneText.entryBlockHint(playing: store.reversiEntryBlock?.text, blocked: .reversi)
        case .activeMatch, .incoming, .record:
            return recordLine
        case .outgoing:
            return ReversiPhoneText.outgoingLine
        case .idle:
            return ReversiPhoneText.idleLine
        }
    }
}

/// 이 기기·서버 조합에서 아잉 뒤집기를 할 수 없다(코어 `availability`) — 로비 대신 세울 안내. 문구는 코어 것이다(맥과 같은 말).
package enum GamesReversiUnavailable {
    package static func title(_ availability: ReversiAvailability) -> String? {
        switch availability {
        case .available: return nil
        case .updateRequired: return ReversiNoticeText.updateRequired
        case .serverMissing: return ReversiNoticeText.unavailable
        }
    }

    package static func icon(_ availability: ReversiAvailability) -> String {
        availability == .updateRequired ? "arrow.up.circle" : "clock"
    }
}

/// 상대 줄 [도전] 버튼이 **눌리는가** — 맥 `ReversiPanel` 의 상대 줄 게이트(`isCapable && !inMatch && !focusMode && !isBusy`)에 폰에서 셋을 더한 것이다:
/// 보낸 신청 · 내 판(**AI 연습 포함**) · **다른 게임의 판**(한 사람 한 판, 다섯 방향).
///
/// ★ `store.match == nil` 이 **AI 연습 판까지** 막는 자리다(`GamesStore.hasLiveReversiAIGame` 머리말) — 코어 `challenge` 에는 AI 가드가 없어 여기를 열면
///   요청이 그대로 나가고, 1:1 판이 서는 순간 두던 AI 판이 말없이 사라진다.
/// ★ `user.isCapable` 은 서버 `capable` 이 **nil 이면 false** 다(코어 `user(from:)`) — 모르는 상대에게 신청해 `target_outdated` 를 받는 것보다 낫다.
///   리버시 화면이 없는 폰(1.0.16 이하)은 서버 상수(`reversi_ios_min_build`)가 capable=false 로 내린다.
package enum GamesReversiChallengeGate {
    @MainActor
    package static func isEnabled(user: ReversiUser, store: ReversiStore, blockedBy other: GamesBusyGame?) -> Bool {
        other == nil
            && user.isCapable
            && !user.inMatch
            && !user.focusMode
            && store.outgoing == nil
            && store.match == nil
            // 서버가 진행 중이라 말한 내 판(같은 계정 다른 기기 · 판을 아직 못 읽음) — 신청은 `busy` 로 돌아온다.
            && store.activeMatchID == nil
            && !store.isBusy
    }
}

/// 판돈 시트의 [도전하기] 가 **실제로 요청을 낼 수 있는가**(낼 수 있으면 그 판돈, 못 내면 nil). 신청이 나가는 **마지막 문**이라 "버튼이 비활성"이 아니라
/// **요청 0건**을 재야 한다(뷰는 맥 스위트가 못 본다). 게이트가 열린 뒤 상태가 바뀐 틈(시트가 떠 있는 동안 AI 연습을 시작했다 · 다른 기기에서 판이 섰다)을 막는다.
/// 판돈 표(3·5·10)는 서버 CHECK 가 쥔다(`ReversiStake`). 잔액을 **모르면 막지 않는다**(맥 0.3.29 규칙 — 서버가 거절하면 그때 안내한다).
package enum GamesReversiStakeSend {
    @MainActor
    package static func sendable(
        _ selected: ReversiStake?, store: ReversiStore, balance: Int?, blockedBy other: GamesBusyGame?
    ) -> ReversiStake? {
        guard let selected,
              affordable(selected, balance: balance),
              !store.isBusy,
              other == nil,
              store.match == nil,
              store.outgoing == nil,
              store.activeMatchID == nil
        else { return nil }
        return selected
    }

    package static func affordable(_ stake: ReversiStake, balance: Int?) -> Bool {
        guard let balance else { return true }
        return balance >= stake.rawValue
    }
}

#if os(iOS)

/// 아잉 뒤집기 화면 — 게임 탭 목적지(`GamesDestination.reversi`). 코어 `phase` 로 로비 · 판(1:1 · 로봇 연습) · 결과를 갈아 끼우고,
/// 관전은 로비 안 절(`spectating`)이다.
///
/// 판·결과·로봇 연습은 판 갈래(2/4 — `GamesReversiMatchView` · `GamesReversiAI*`), 로비·신청·받기·관전·순위·규칙은 로비 갈래(3/4 —
/// `GamesReversiLobby` · `GamesReversiWatch` · `GamesReversiRanking` · `GamesReversiRules`)가 채웠다. 수명 훅 두 줄(`onAppear`·`onDisappear`)은
/// 그대로 둔다 — 순서를 쥔 곳이 `GamesStore` 다.
///
/// ★ **시트의 주인은 이 루트 하나다**(돌 색 · 판돈 · 규칙 · 로봇 판 확인) — 행·카드가 시트를 직접 띄우면 판이 서는 순간(로비가 판 화면으로
///   바뀌며) 그 행이 사라져 시트가 고아가 된다. 판 id 가 바뀌면 판돈·돌 색·로봇 확인 시트를 접는다(규칙 시트는 판 중에도 읽을 수 있어 둔다).
/// ★ 사람 절(받은·보낸 신청 · 상대 · 관전 · 순위)은 **이 기기·서버가 아잉 뒤집기를 할 수 있을 때만** 선다(`GamesReversiLobbyPlan.showsPeopleSections`) —
///   업데이트가 필요하거나 서버가 준비 중이면 안내 한 줄 + 로봇 연습만 선다(로봇 연습은 서버를 안 탄다).
struct GamesReversiScreen: View {
    let store: GamesStore

    /// [로봇과 연습하기] → 돌 색 시트.
    @State private var showsAIColorSheet = false
    /// [도전] → 판돈 시트의 대상.
    @State private var stakeTarget: ReversiUser?
    /// 로봇 판을 두는 중에 누른 [수락] — 확인을 거쳐야 보낸다(`GamesReversiRespond.AcceptRoute.confirmRobot`).
    @State private var acceptNeedsRobotConfirm: ReversiInvite?

    private var reversi: ReversiStore { store.reversi }

    var body: some View {
        @Bindable var reversi = reversi
        content
            .background(MobileTheme.background.ignoresSafeArea())
            .navigationTitle(ReversiPhoneText.title)
            .navigationBarTitleDisplayMode(.inline)
            // 규칙 책 버튼 — 로비와 판 화면 **둘 다**의 오른쪽 위(판 중에도 규칙을 읽는다). 코어 깃발 하나로 연다(맥과 같은 깃발).
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { reversi.isRulesVisible = true } label: { Image(systemName: "book") }
                        .accessibilityLabel(ReversiPhoneText.rulesTitle)
                }
            }
            .sheet(isPresented: $showsAIColorSheet) {
                GamesReversiAIColorSheet(store: reversi)
            }
            .sheet(item: $stakeTarget) { target in
                GamesReversiStakeSheet(store: store, target: target)
            }
            // ★ 숫자 셋은 **로비 응답이 말한 값**이다(응답 전에는 코어 기본값 30 · 3 · 60) — 상수를 베끼면 서버가 바꾼 날 규칙 시트만 옛 숫자다.
            .sheet(isPresented: $reversi.isRulesVisible) {
                GamesReversiRulesSheet(turnSeconds: reversi.turnSeconds, lossStreak: reversi.autoAbandonStreak,
                                       inviteTtlSeconds: Int(reversi.inviteTTLSeconds))
            }
            .sheet(item: $acceptNeedsRobotConfirm) { invite in
                robotConfirm(for: invite)
            }
            .onAppear { store.reversiScreenDidAppear() }
            .onDisappear { store.reversiScreenDidDisappear() }
            // 판이 섰다(신청 수락 · 다른 기기에서 연 판을 읽음) — 들고 있던 시트가 로비로 돌아올 때 되살아나지 않게 접는다.
            .onChange(of: reversi.match?.id) { _, _ in
                showsAIColorSheet = false
                stakeTarget = nil
                acceptNeedsRobotConfirm = nil
            }
    }

    @ViewBuilder
    private var content: some View {
        switch reversi.phase {
        case .playing, .result:
            // 판이 없으면 로비가 선다 — 늦게 온 응답이 단계만 올려 놓고 판을 못 세운 틈이다(체스·오목과 같은 대체 갈래).
            if reversi.match != nil {
                GamesReversiMatchView(store: store)
                    // 로봇 연습·끝난 판이 로비를 덮는 동안 온 60초 신청 — 판 위 띠(판정 `GamesReversiInviteBanner`).
                    // 띠가 서면 판 예산(보이는 높이)이 저절로 줄어든다(대국 화면의 `GeometryReader` 가 안쪽이다).
                    .safeAreaInset(edge: .top, spacing: 0) {
                        GamesReversiInviteBannerView(store: store, onAccept: accept)
                            .animation(.easeOut(duration: 0.2), value: GamesReversiInviteBanner.invite(reversi)?.id)
                    }
            } else {
                lobby
            }
        case .lobby:
            lobby
        }
    }

    // MARK: - 수락 (한 문)

    /// [수락] — 갈 길은 `GamesReversiRespond.acceptRoute` 하나가 고른다(로비 카드 · 판 위 띠가 같은 길을 지난다).
    private func accept(_ invite: ReversiInvite) {
        switch GamesReversiRespond.acceptRoute(store) {
        case .send:
            Task { await GamesReversiRespond.accept(store, inviteID: invite.id) }
        case .confirmRobot:
            acceptNeedsRobotConfirm = invite
        case .blocked:
            break
        }
    }

    /// 로봇 판을 두는 중에 1:1 신청을 수락하려 한다 — **먼저 묻는다**(까닭은 `GamesReversiRespond.AcceptRoute.confirmRobot`).
    /// 확인 뒤에는 코어가 알아서 로봇 판을 버린다(1:1 판이 서는 순간 `match` 관찰자) — 이 화면이 따로 정리하지 않는다.
    private func robotConfirm(for invite: ReversiInvite) -> some View {
        AingConfirmSheet(
            title: ReversiPhoneText.acceptEndsRobotTitle,
            message: ReversiPhoneText.acceptEndsRobotMessage,
            confirmTitle: ReversiPhoneText.acceptEndsRobotConfirm,
            cancelTitle: ReversiPhoneText.acceptEndsRobotCancel,
            onConfirm: {
                acceptNeedsRobotConfirm = nil
                Task { await GamesReversiRespond.accept(store, inviteID: invite.id) }
            },
            onCancel: { acceptNeedsRobotConfirm = nil }
        )
    }

    // MARK: - 로비

    /// 로비 스크롤. 순서: 받은 신청(60초 — 스크롤해야 보이는 자리에 두면 그 사이 만료된다 · 테트리스와 같은 자리) → 내 전적·루비 → 규칙 한 줄 →
    /// 안내 → 다른 게임 판 막힘 → 보낸 신청 → 로봇 연습 → 상대 고르기 → 지금 대결 중(↔ 관전 판) → 순위.
    /// 이 기기·서버가 아잉 뒤집기를 못 하면(업데이트 필요 · 서버 준비 중) 안내 + 로봇 연습만 선다.
    private var lobby: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if GamesReversiLobbyPlan.showsPeopleSections(reversi) {
                    incoming
                    summary
                    caption
                    notice
                    blockedByOtherGame
                    outgoing
                    GamesReversiAIEntryCard(store: reversi, onPlay: { showsAIColorSheet = true })
                        .padding(.top, MobileTheme.rowSpacing)
                    opponents
                    GamesReversiWatchSection(store: reversi)
                    GamesReversiRankingSection(store: reversi)
                } else {
                    // 할 수 없는 기기·서버 상태다 — 사람에게 신청하는 길은 서지 않는다. **로봇 연습은 서버를 안 타므로 그대로 연다**.
                    InlineNotice(text: GamesReversiUnavailable.title(reversi.availability) ?? "", kind: .warning)
                    notice
                    GamesReversiAIEntryCard(store: reversi, onPlay: { showsAIColorSheet = true })
                        .padding(.top, MobileTheme.rowSpacing)
                }
            }
            .padding(.horizontal, MobileTheme.sideMargin)
            .padding(.top, MobileTheme.space2)
            .padding(.bottom, MobileTheme.space6)
        }
        .refreshable {
            await reversi.refreshLobby()
            await reversi.refreshRanking()
        }
        // 데모 스크린샷(`-AingCheckGamesDemo bottom`)에서 맨 아래(순위·관전 절)부터 보여 준다 — 다른 1:1 로비와 같은 모양.
        .gamesDemoScrollAnchor(isDemo: store.context.isDemo)
    }

    // MARK: 머리 두 칸 — 내 전적 · 내 루비

    private var summary: some View {
        InsetGroup {
            HStack(spacing: 0) {
                summaryCell(ReversiPhoneText.recordTitle) {
                    Text(ReversiPhoneText.record(reversi.record))
                        .font(.headline)
                        .monospacedDigit()
                        .foregroundStyle(MobileTheme.label)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityLabel(ReversiPhoneText.myRecordAccessibility(reversi.record))
                Rectangle()
                    .fill(MobileTheme.separator)
                    .frame(width: MobileTheme.hairline)
                summaryCell(ReversiPhoneText.myRubyTitle) {
                    // 공유 미러 먼저(나 탭 상점 구매도 적는다) — `GamesStore.rubyBalance` 와 같은 순서.
                    if let balance = store.rubyBalance {
                        RubyPrice(balance, isShort: false, style: .headline)
                    } else {
                        Text(ReversiPhoneText.unknownNumber).font(.headline).foregroundStyle(MobileTheme.label)
                    }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, MobileTheme.rowSpacing)
    }

    private func summaryCell(_ title: String, @ViewBuilder value: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(MobileTheme.rowSubtitle)
                .foregroundStyle(MobileTheme.label2)
            value()
        }
        .padding(.horizontal, MobileTheme.cardPadding)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    /// 규칙 한 줄 — 한 수 시간은 **서버가 말한 값**.
    private var caption: some View {
        Text(ReversiPhoneText.lobbySubtitle(turnSeconds: reversi.turnSeconds))
            .font(.footnote)
            .foregroundStyle(MobileTheme.label2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, MobileTheme.titleMargin - MobileTheme.sideMargin)
            .padding(.top, MobileTheme.space2)
    }

    /// 코어 안내(신청·수락·취소 응답 · 관전 못 봄 · 연결) — 거절 까닭(바쁨 · 상대 대국 중 · 상대 앱 모름 · 집중 · 루비 모자람)이 여기 선다.
    @ViewBuilder
    private var notice: some View {
        if let text = reversi.notice {
            InlineNotice(text: text, kind: .warning)
                .padding(.top, MobileTheme.rowSpacing)
        }
    }

    /// 한 사람 한 판 — 다른 1:1 판(오목·체스·테트리스·큐브)이 흐르는 동안은 신청·수락을 못 한다. 버튼만 흐려 두면 **왜**인지 모른다(툴팁이 없다).
    /// ★ **두 줄**이다: 왜(두는 판의 이름) + 언제 풀리는지. 조립은 문구 표가 쥔다(`entryBlockNotice`).
    @ViewBuilder
    private var blockedByOtherGame: some View {
        if let playing = store.reversiEntryBlock {
            InlineNotice(text: ChessPhoneText.entryBlockNotice(playing: playing.text, blocked: .reversi) ?? "", kind: .warning)
                .padding(.top, MobileTheme.rowSpacing)
        }
    }

    // MARK: 받은 신청 · 보낸 신청

    /// 받은 신청 — 서버가 **여럿**을 준다(최신이 앞). 다 세운다: 하나에 답하면 다음 것이 그 자리에 오르지만, 60초가 각자 흐르므로 안 보이는 사이 만료된다.
    @ViewBuilder
    private var incoming: some View {
        let invites = reversi.visibleIncomingInvites
        if !invites.isEmpty {
            SectionHeader(ReversiPhoneText.incomingTitle,
                          trailing: .text(ReversiPhoneText.inviteTtlHint(ttlSeconds: Int(reversi.inviteTTLSeconds))),
                          padded: true)
            VStack(spacing: MobileTheme.rowSpacing) {
                ForEach(invites) { invite in
                    InsetGroup {
                        GamesReversiInviteCard(store: store, invite: invite, onAccept: accept)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var outgoing: some View {
        if let invite = reversi.outgoing {
            SectionHeader(ReversiPhoneText.outgoingTitle, padded: true)
            InsetGroup {
                GamesReversiOutgoingRow(store: store, invite: invite)
            }
            Text(ReversiPhoneText.stakeNotHeldYet(ttlSeconds: Int(reversi.inviteTTLSeconds)))
                .font(MobileTheme.rowSubtitle)
                .foregroundStyle(MobileTheme.label2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, MobileTheme.titleMargin - MobileTheme.sideMargin)
                .padding(.top, MobileTheme.space2)
        }
    }

    // MARK: 상대 고르기 — 근무 중 먼저(코어 정렬) · 막힌 까닭 버튼 · 풀이 줄

    @ViewBuilder
    private var opponents: some View {
        let users = store.reversiLobbyUsers
        SectionHeader(ReversiPhoneText.lobbyTitle,
                      trailing: users.isEmpty ? .none : .text(ReversiPhoneText.peopleCount(users.count)),
                      padded: true)
        InsetGroup {
            switch GamesReversiLobbyPlan.users(store) {
            case .rows:
                // ★ **정렬하지 않는다** — 코어가 서버와 같은 규칙으로 이미 맞췄다(`sortedForLobby`).
                ForEach(Array(users.enumerated()), id: \.element.id) { index, user in
                    GamesReversiOpponentRow(store: store, user: user, isLast: index == users.count - 1,
                                            onChallenge: { stakeTarget = $0 })
                }
            case .empty:
                GroupRow(divider: .none) {
                    Text(ReversiPhoneText.emptyUsers)
                        .font(.subheadline)
                        .foregroundStyle(MobileTheme.label2)
                    Spacer(minLength: 0)
                }
            case .loading:
                GroupRow(divider: .none) { LoadingRow(ReversiPhoneText.loadingUsers) }
            }
        }
        VStack(alignment: .leading, spacing: 2) {
            Text(ReversiPhoneText.lobbyCaption)
                .fixedSize(horizontal: false, vertical: true)
            // 막힌 [도전]의 뜻 — 목록에 그 까닭이 **있을 때만**(왜 · 언제 풀리는지).
            ForEach(GamesReversiLobbyPlan.lockLegends(store), id: \.self) { line in
                Text(line)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(MobileTheme.rowSubtitle)
        .foregroundStyle(MobileTheme.label2)
        .padding(.horizontal, MobileTheme.titleMargin - MobileTheme.sideMargin)
        .padding(.top, MobileTheme.space2)
    }
}

#endif
