import CheckCore
import Foundation
#if os(iOS)
import SwiftUI
#endif

// 폰 1:1 테트리스 **화면 하나**(설계서 P6) — 로비 · 대결 · 결과를 한 화면이 갈아 끼운다. 본은 폰 체스
// (`GamesChessScreen`)이고, 테트리스에서 달라지는 자리만 바꿨다.
//
// ── 이 파일이 두 겹인 까닭 ──
// 아래 **판정**(`GamesTetrisDuelCard` · `…ChallengeGate` · `…StakeSend` · `…StakeSelection`)은 `#if os(iOS)`
// **밖**에 있다. 폰 뷰는 맥 스위트가 한 줄도 못 보므로(저장소 메모 '폰 뷰는 맥 스위트가 못 본다') 뷰 안에
// 판정을 묻어 두면 "판돈을 안 골랐는데 신청이 나갔다"·"칩 서열이 뒤집혔다" 를 재는 그물을 걸 자리가 없다 —
// 체스 순위 절(`GamesChessRanking.swift`)이 같은 이유로 같은 모양이다. 그림(뷰)은 판정을 받아 그리기만 한다.
//
// ── 수명은 **직접 코어를 부르지 않는다** ──
// `onAppear` → `GamesStore.tetrisScreenDidAppear()`, `onDisappear` → `…DidDisappear()` 뿐이다. 그 둘이
// `openWindow`·`windowDidShow`·`windowDidHide`·`windowDidClose` 의 순서와 끝난 판 접기를 쥔다(배선 레인).
// 여기서 코어 창 문을 직접 부르면 그 순서가 두 벌이 된다.

/// 로비 안 탭 둘(설계서 P6 · 데모 라우트 `games/tetris/ranking`).
///
/// ★ **자식 화면이 아니라 탭**이다: 자식 라우트를 push 하면 이 화면의 `onDisappear` → `windowDidHide()` 로
///   폴링이 죽어 순위·로비가 갱신되지 않는다(오목·체스에서 실증된 자리 — 두 파일 머리말).
package enum GamesTetrisLobbyTab: String, Hashable, CaseIterable, Sendable {
    case opponents, ranking

    package var title: String {
        switch self {
        case .opponents: return TetrisPhoneText.usersTab
        case .ranking: return TetrisPhoneText.rankTab
        }
    }
}

#if DEBUG
extension GamesTetrisLobbyTab {
    /// 데모 라우트 꼬리가 고른 탭(`MobileDemoTetrisRoute.LobbyTab`) → 이 화면의 탭.
    ///
    /// **두 열거를 따로 두는 까닭**: 데모 값은 Release 바이너리에서 **이름이 사라져야** 하고(출시 게이트 —
    /// `Demo/MobileDemoTetrisRoute.swift` 머리말), 화면 탭은 사람이 쓰는 길에도 있어야 한다. 짝을 여기 한 줄로
    /// 두면 두 벌이 갈릴 자리가 없다(`GamesTetrisLobbyTests` 가 두 값 짝을 센다).
    package init(demo tab: MobileDemoTetrisRoute.LobbyTab) {
        switch tab {
        case .opponents: self = .opponents
        case .ranking: self = .ranking
        }
    }
}
#endif

/// 게임 탭 **1:1 테트리스 카드**가 그리는 한 줄의 판정(칩 + 보조 줄).
///
/// ★ **서열을 한 열거로 못 박는다**(`Line`). 칩과 보조 줄을 자리마다 삼항으로 고르면 서열이 두 벌이 되어
///   한쪽만 고쳐지고, 그 상태가 **초록인 채로** 남는다(체스 카드가 삼항 셋이라 맥 스위트가 서열을 못 쟀다).
///   서열은 설계서 P2 의 그것이다: 차단 > 진행 중 판 > 받은 신청 > 보낸 신청 > 전적 > 기본 한 줄.
@MainActor
package enum GamesTetrisDuelCard {
    /// 카드가 지금 말하는 **한 가지**. 서열이 뒤집히면 이 값이 바뀐다.
    package enum Line: String, Equatable, Sendable, CaseIterable {
        /// 다른 게임 판이 흐른다 — 카드가 흐려지고 눌리지 않는다.
        case blocked
        /// 내 테트리스 판이 흐른다(결과 카드는 판이 아니다 — `hasActiveTetrisMatch`).
        case activeMatch
        case incoming
        case outgoing
        case record
        /// 칩도 보조 줄 재료도 없다 — **할 일**을 말한다.
        case idle
    }

    package static func line(_ store: GamesStore) -> Line {
        // ① 차단이 맨 앞이다. 다른 게임 판이 흐르는 동안 이 카드를 열어 두면 로비 [수락]으로 테트리스가 서고
        //    흐르던 판이 조용히 시간패한다(P3 — 서버 오목 게이트는 테트리스를 모른다).
        if store.tetrisEntryBlock != nil { return .blocked }
        // ② 내 판이 흐르면 그것이 가장 급한 사실이다(받은 신청보다 먼저 — 판돈이 걸려 있다).
        if store.hasActiveTetrisMatch { return .activeMatch }
        if store.tetris.visibleIncoming != nil { return .incoming }
        if store.tetris.outgoing != nil { return .outgoing }
        return store.tetris.record != nil ? .record : .idle
    }

    /// 칩(없으면 nil). 막힌 칩은 **두는 판의 이름**을 말한다(`ChessPhoneText` 한 곳이 조립한다 — 뷰가 지어내지 않는다).
    package static func chip(_ store: GamesStore) -> String? {
        switch line(store) {
        case .blocked: return ChessPhoneText.entryBlock(playing: store.tetrisEntryBlock?.text)
        case .activeMatch: return GamesText.activeMatchChip
        case .incoming: return TetrisPhoneText.incomingChip
        case .outgoing, .record, .idle: return nil
        }
    }

    /// 보조 줄(없으면 nil).
    ///
    /// ★ 막혔을 때 **두 자리를 다 그린다**: 칩은 왜 막혔는지, 이 줄은 **언제 풀리는지**를 말한다. 한 자리만
    ///   그리면 사용자가 기다릴 끝을 모른다(폰엔 호버 툴팁이 없다 — `GamesChessTextTests` 가 못을 박은 그 규약).
    package static func detail(_ store: GamesStore) -> String? {
        let recordLine = store.tetris.record.map { TetrisPhoneText.recordTitle + " " + TetrisPhoneText.record($0) }
        switch line(store) {
        case .blocked:
            return ChessPhoneText.entryBlockHint(playing: store.tetrisEntryBlock?.text, blocked: .tetris)
        case .activeMatch, .incoming:
            // 칩이 급한 사실을 말했으니 이 줄은 전적이다(모르면 비운다 — 꾸미지 않는다).
            return recordLine
        case .outgoing:
            return TetrisPhoneText.outgoingLine
        case .record:
            return recordLine
        case .idle:
            return TetrisPhoneText.idleLine
        }
    }
}

/// 상대 줄 [신청] 버튼이 **눌리는가**. 체스 게이트(`GamesChessChallengeGate`)와 같은 자리·같은 뜻이고,
/// 테트리스에는 로봇 판이 없어 가를 것이 하나 적은 대신 **집중 모드**가 있다(서버 `target_focused`).
///
/// ★ `user.canBeChallenged` 를 그대로 쓴다(코어 한 곳 — `isCapable && !inMatch && !isFocused`). 여기서 세 조건을
///   다시 적으면 서버가 축을 하나 더하는 날 두 벌이 갈린다.
package enum GamesTetrisDuelChallengeGate {
    @MainActor
    package static func isEnabled(user: TetrisDuelUser, store: TetrisDuelStore, blockedBy other: GamesBusyGame?) -> Bool {
        other == nil
            && user.canBeChallenged
            && store.outgoing == nil
            // 내 판이 있으면(끝난 판이어도 결과 카드가 떠 있는 상태다) 로비가 화면에 없다 — 열려 있으면
            // 그 사이 들어온 로비 응답으로 버튼이 되살아날 수 있다.
            && store.match == nil
            && !store.isBusy
    }
}

/// 판돈 시트의 [신청] 이 **실제로 요청을 낼 수 있는가**(낼 수 있으면 그 판돈, 못 내면 nil).
///
/// ★ 왜 뷰가 아니라 여기 있나: 신청이 나가는 **마지막 문**이라 "버튼이 비활성"이 아니라 **요청 0건**을 재야 하고,
///   뷰는 `#if os(iOS)` 안이라 맥 스위트가 못 본다. 특히 **아무것도 안 고른 채**(nil)가 nil 로 떨어지는 것이
///   설계 결정이다(처음엔 아무것도 안 골라진 채 열리고, 골라야 신청이 생긴다).
package enum GamesTetrisDuelStakeSend {
    @MainActor
    package static func sendable(
        _ selected: TetrisDuelStake?, store: TetrisDuelStore, balance: Int?, blockedBy other: GamesBusyGame?
    ) -> TetrisDuelStake? {
        guard let selected,
              GamesTetrisStakeSelection.affordable(selected, balance: balance),
              !store.isBusy,
              other == nil,
              // 게이트가 열린 뒤 상태가 바뀐 틈을 막는다(시트가 떠 있는 동안 판이 서거나 신청이 나갔다).
              store.match == nil,
              store.outgoing == nil
        else { return nil }
        return selected
    }
}

/// 판돈 고르기(체스 `GamesChessStakeSelection` 과 같은 규약 — 고른 판돈을 다시 누르면 해제 ·
/// **잔액을 모르면 막지 않는다**). 판돈 표(3·5·10)의 주인은 서버 CHECK 다.
package enum GamesTetrisStakeSelection {
    package static func toggled(current: TetrisDuelStake?, tapped: TetrisDuelStake) -> TetrisDuelStake? {
        current == tapped ? nil : tapped
    }

    /// 이 판돈을 걸 수 있는가. **잔액을 모르면(nil) 막지 않는다** — 서버가 거절하면 그때 안내한다.
    package static func affordable(_ stake: TetrisDuelStake, balance: Int?) -> Bool {
        guard let balance else { return true }
        return balance >= stake.rawValue
    }
}

/// 이 기기가 지금 대결을 할 수 없다(코어 `availability`) — 로비 대신 세울 안내. **문구는 코어 것**이다
/// (`TetrisDuelNoticeText` — 맥과 같은 말이어야 한다).
package enum GamesTetrisDuelUnavailable {
    package static func title(_ availability: TetrisDuelAvailability) -> String? {
        switch availability {
        case .available: return nil
        case .updateRequired: return TetrisDuelNoticeText.updateMine
        case .serverMissing: return TetrisDuelNoticeText.unavailable
        }
    }

    package static func icon(_ availability: TetrisDuelAvailability) -> String {
        availability == .updateRequired ? "arrow.up.circle" : "clock"
    }
}

#if os(iOS)

/// 1:1 테트리스 화면 — 코어 `TetrisDuelStore` 의 단계를 한 화면에서 갈아 끼운다(설계서 P6).
struct GamesTetrisDuelScreen: View {
    let store: GamesStore

    /// [신청] → 판돈 시트의 대상.
    @State private var stakeTarget: TetrisDuelUser?
    @State private var rulesVisible = false
    @State private var tab: GamesTetrisLobbyTab = .opponents

    private var tetris: TetrisDuelStore { store.tetris }
    /// 순위 탭의 내 행을 고르는 값(미니게임 순위와 **같은 자리**에서 읽는다).
    private var myUserID: String? { store.context.session.session?.userID.lowercased() }

    var body: some View {
        content
            .background(MobileTheme.background.ignoresSafeArea())
            .navigationTitle(TetrisPhoneText.title)
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $stakeTarget) { target in
                GamesTetrisStakeSheet(store: store, target: target)
            }
            .sheet(isPresented: $rulesVisible) {
                GamesTetrisRulesSheet()
            }
            .onAppear {
                store.tetrisScreenDidAppear()
                applyDemoTab()
            }
            .onDisappear { store.tetrisScreenDidDisappear() }
            .onChange(of: tetris.match?.id) { _, _ in
                // 판이 시작되면 로비가 사라진다 — 열려 있던 판돈 시트를 들고 있으면 로비로 돌아올 때 되살아난다.
                stakeTarget = nil
            }
    }

    /// 데모 스크린샷 전용: 라우트 꼬리가 `games/tetris/ranking` 이면 순위 탭에서 시작한다.
    ///
    /// Release 에서는 **한 줄도 돌지 않는다**(`demoTetrisRoute` 가 DEBUG 전용 — 출시 게이트). 그 구성에서 값이
    /// 늘 nil 이라 동작은 같다(기본 탭은 상대 고르기다).
    private func applyDemoTab() {
        #if DEBUG
        guard let demo = store.demoTetrisRoute else { return }
        tab = GamesTetrisLobbyTab(demo: demo.lobbyTab)
        #endif
    }

    @ViewBuilder
    private var content: some View {
        if let unavailable = GamesTetrisDuelUnavailable.title(tetris.availability) {
            // 대결을 할 수 없는 기기·서버 상태다 — 로비를 그리면 신청 버튼이 서고 그 요청은 전부 거절된다.
            EmptyStateView(systemImage: GamesTetrisDuelUnavailable.icon(tetris.availability), title: unavailable)
                .padding(.horizontal, MobileTheme.sideMargin)
        } else if tetris.phase == .lobby {
            lobby
        } else {
            // 준비·카운트다운·판·결과는 한 화면이 맡는다(레인 C). `phase != .lobby` 는 **판을 들고 있다는 뜻**이다 —
            // 코어 `refreshPhase()` 가 `match` 에서만 단계를 낸다(`match == nil` → `.lobby`).
            GamesTetrisDuelMatchView(store: store)
        }
    }

    // MARK: - 로비

    private var lobby: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // ★ 받은 신청이 **맨 위**다(설계서 P5 의 '배너' 자리 — 폰엔 전역 배너 부품도 탭 배지도 없다).
                //   신청은 60초 뒤 사라지므로 스크롤을 내려야 보이는 자리에 두면 그 사이 만료된다.
                incoming
                summary
                caption
                notice
                blockedByOtherGame
                outgoing
                tabPicker
                switch tab {
                case .opponents:
                    opponents
                    liveMatches
                case .ranking:
                    GamesTetrisDuelRankingSection(store: tetris, myUserID: myUserID)
                }
            }
            .padding(.horizontal, MobileTheme.sideMargin)
            .padding(.top, MobileTheme.space2)
            .padding(.bottom, MobileTheme.space6)
        }
        .refreshable {
            await tetris.refreshLobby()
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { rulesVisible = true } label: { Image(systemName: "book") }
                    .accessibilityLabel(TetrisPhoneText.rulesTitle)
            }
        }
    }

    // MARK: 머리 두 칸 — 내 전적 · 내 루비

    private var summary: some View {
        InsetGroup {
            HStack(spacing: 0) {
                summaryCell(TetrisPhoneText.recordTitle) {
                    Text(TetrisPhoneText.record(tetris.record))
                        .font(.headline)
                        .monospacedDigit()
                        .foregroundStyle(MobileTheme.label)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityLabel(TetrisPhoneText.myRecordAccessibility(tetris.record))
                Rectangle()
                    .fill(MobileTheme.separator)
                    .frame(width: MobileTheme.hairline)
                summaryCell(TetrisPhoneText.myRubyTitle) {
                    // 공유 미러 먼저(나 탭 상점 구매도 적는다) — `GamesStore.rubyBalance` 와 같은 순서.
                    if let balance = store.rubyBalance {
                        RubyPrice(balance, isShort: false, style: .headline)
                    } else {
                        Text(TetrisPhoneText.unknownNumber).font(.headline).foregroundStyle(MobileTheme.label)
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

    private var caption: some View {
        Text(TetrisPhoneText.subtitle)
            .font(.footnote)
            .foregroundStyle(MobileTheme.label2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, MobileTheme.titleMargin - MobileTheme.sideMargin)
            .padding(.top, MobileTheme.space2)
    }

    @ViewBuilder
    private var notice: some View {
        if let text = tetris.notice {
            InlineNotice(text: text, kind: .warning)
                .padding(.top, MobileTheme.rowSpacing)
        }
    }

    /// 한 사람 한 판(P3) — 오목·체스 판이 흐르는 동안은 테트리스를 신청·수락할 수 없다. 버튼만 흐려 두면
    /// **왜**인지 알 길이 없어(폰엔 호버 툴팁이 없다) 절 위에 까닭을 세운다.
    ///
    /// ★ **두 줄**이다: 제목은 왜, 둘째 줄은 **언제 풀리는지**. 조립은 문구 표가 쥔다(뷰에서 이으면 맥 스위트가 못 본다).
    @ViewBuilder
    private var blockedByOtherGame: some View {
        if let playing = store.tetrisEntryBlock {
            InlineNotice(text: ChessPhoneText.entryBlockNotice(playing: playing.text, blocked: .tetris) ?? "",
                         kind: .warning)
                .padding(.top, MobileTheme.rowSpacing)
        }
    }

    // MARK: 받은 신청 · 보낸 신청

    @ViewBuilder
    private var incoming: some View {
        if let invite = tetris.visibleIncoming {
            let more = tetris.visibleIncomingInvites.count - 1
            SectionHeader(TetrisPhoneText.incomingTitle,
                          trailing: .text(more > 0
                                          ? TetrisPhoneText.incomingMore(more)
                                          : TetrisPhoneText.inviteTtlHint(ttlSeconds: Int(tetris.inviteTTLSeconds))),
                          padded: true)
            InsetGroup {
                GamesTetrisInviteCard(store: store, invite: invite)
            }
        }
    }

    @ViewBuilder
    private var outgoing: some View {
        if let invite = tetris.outgoing {
            SectionHeader(TetrisPhoneText.outgoingTitle, padded: true)
            InsetGroup {
                GamesTetrisOutgoingRow(store: store, invite: invite)
            }
            Text(TetrisPhoneText.stakeNotHeldYet(ttlSeconds: Int(tetris.inviteTTLSeconds)))
                .font(MobileTheme.rowSubtitle)
                .foregroundStyle(MobileTheme.label2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, MobileTheme.titleMargin - MobileTheme.sideMargin)
                .padding(.top, MobileTheme.space2)
        }
    }

    // MARK: 탭 둘

    private var tabPicker: some View {
        Picker(TetrisPhoneText.title, selection: $tab) {
            ForEach(GamesTetrisLobbyTab.allCases, id: \.self) { value in
                Text(value.title).tag(value)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.top, MobileTheme.rowSpacing)
        // 순위는 **로비에서만** 갱신된다(화면을 떠나면 폴링이 죽는다) — 탭을 고른 그 순간이 조회를 낼 자리다.
        // 판정은 `GamesTetrisDuelRankingPlan` 한 곳이다(스로틀·단계 가드를 뷰가 다시 적지 않게).
        .onChange(of: tab) { _, value in
            // ★ 먼저 관전을 거둔다. 관전 판은 [상대] 탭의 "지금 대결 중" 자리에만 있어서, 탭을 바꾸면
            //   **화면에서는 사라지는데 `spectating` 은 살아** 2초 폴링이 계속 나간다 — 아무것도 안 보는
            //   사람이 남의 카드에 관전자로 잡히고 [나가기]는 그 사라진 절 안에 있다. 코어
            //   (`shouldPollWatch`)는 탭을 모르므로 **화면이 풀어야 하는 매듭**이다
            //   (까닭과 고르지 않은 다른 길은 `GamesTetrisWatchPlan.tabDidChange` 머리말에).
            GamesTetrisWatchPlan.tabDidChange(tetris, to: value)
            GamesTetrisDuelRankingPlan.refreshIfNeeded(tetris, tab: value)
        }
    }

    // MARK: 상대 고르기

    @ViewBuilder
    private var opponents: some View {
        let users = store.tetrisLobbyUsers
        SectionHeader(TetrisPhoneText.usersTab,
                      trailing: users.isEmpty ? .none : .text(TetrisPhoneText.peopleCount(users.count)),
                      padded: true)
        InsetGroup {
            if tetris.lobbyLoadFailed {
                // 실패 문구·[다시 시도]는 **공용 부품**이 쥔다(`LoadFailureRow` · `MobileLoadText`) —
                // 그 리터럴이 CheckMobileKit 안에서 한 파일에만 있어야 한다(`IntegrationFixTests`).
                GroupRow(divider: users.isEmpty ? .none : .inset(MobileTheme.cardPadding)) {
                    LoadFailureRow(TetrisPhoneText.usersLoadFailed) { Task { await tetris.refreshLobby() } }
                }
            }
            // 빈 목록을 "없다"로 말하는 것은 **한 번 받았고 마지막 조회가 실패하지 않았을 때만**(`MobileLoadKnowledge`).
            if users.isEmpty {
                if !tetris.lobbyLoadFailed {
                    GroupRow(divider: .none) {
                        if tetris.hasLoadedLobby {
                            Text(TetrisPhoneText.emptyUsers)
                                .font(.subheadline)
                                .foregroundStyle(MobileTheme.label2)
                        } else {
                            LoadingRow(TetrisPhoneText.loadingUsers)
                        }
                    }
                }
            } else {
                // ★ **정렬하지 않는다** — 코어가 서버와 같은 규칙으로 이미 맞췄다(`GamesStore.tetrisLobbyUsers`).
                ForEach(Array(users.enumerated()), id: \.element.id) { index, user in
                    GamesTetrisOpponentRow(store: store, user: user, isLast: index == users.count - 1,
                                           onChallenge: { stakeTarget = $0 })
                }
            }
        }
        Text(TetrisPhoneText.lobbyCaption)
            .font(MobileTheme.rowSubtitle)
            .foregroundStyle(MobileTheme.label2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, MobileTheme.titleMargin - MobileTheme.sideMargin)
            .padding(.top, MobileTheme.space2)
    }

    // MARK: 지금 대결 중 (0.3.65 부터 관전 입구가 있다 — D8 을 되돌린 것)

    /// 관전 중이면 **이 자리가 관전 판으로 바뀐다**(새 화면을 밀지 않는다 — `GamesTetrisWatch.swift` 자리 계약).
    /// 자식 라우트를 push 하면 이 화면의 `onDisappear` 로 폴링이 죽어 판이 갱신되지 않는다.
    @ViewBuilder
    private var liveMatches: some View {
        if let watch = tetris.spectating {
            GamesTetrisWatchPanel(store: tetris, watch: watch)
        } else {
            liveMatchList
        }
    }

    @ViewBuilder
    private var liveMatchList: some View {
        let lives = tetris.liveMatches
        // 한 번도 안 받았으면 절을 통째로 접는다(머리만 번쩍이지 않게 — 체스 순위 절과 같은 규약).
        if !lives.isEmpty {
            SectionHeader(TetrisPhoneText.liveTitle, trailing: .text(TetrisPhoneText.liveCount(lives.count)), padded: true)
            InsetGroup {
                ForEach(Array(lives.enumerated()), id: \.element.id) { index, live in
                    GamesTetrisLiveRow(store: tetris, live: live, isLast: index == lives.count - 1)
                }
            }
        } else if tetris.hasLoadedLobby, !tetris.lobbyLoadFailed {
            SectionHeader(TetrisPhoneText.liveTitle, padded: true)
            InsetGroup {
                GroupRow(divider: .none) {
                    Text(TetrisPhoneText.noLive)
                        .font(.subheadline)
                        .foregroundStyle(MobileTheme.label2)
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

// MARK: - 상대 한 줄

/// 상대 한 줄(폰 체스 줄과 같은 모양): 아바타(근무 중 점) · 이름 · 상태 부제 · 오른쪽 [신청] 틴트(또는 회색 비활성).
///
/// ★ 부제와 버튼 글자를 **문구 표가 한 번에** 고른다(`TetrisPhoneText.opponentRow(for:)`) — 자리마다 따로
///   고르면 한 줄에 같은 문장이 두 번 나오고 근무 축이 덮인다(체스 헤드리스 실측 D4).
private struct GamesTetrisOpponentRow: View {
    let store: GamesStore
    let user: TetrisDuelUser
    let isLast: Bool
    let onChallenge: (TetrisDuelUser) -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    private var canChallenge: Bool {
        GamesTetrisDuelChallengeGate.isEnabled(user: user, store: store.tetris, blockedBy: store.tetrisEntryBlock)
    }

    private var lines: TetrisPhoneText.OpponentRow { TetrisPhoneText.opponentRow(for: user) }

    var body: some View {
        GroupRow(divider: isLast ? .none : .inset(MobileTheme.cardPadding + 36 + MobileTheme.space3), minHeight: 56) {
            // 큰 글자: [신청]을 아래 줄로 — 한 줄에 두면 이름이 글자 하나씩 꺾인다(오목·체스에서 실측).
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
            PersonName(user.displayName)
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
            AingButton(TetrisPhoneText.challenge, kind: .tinted, size: .sm) { onChallenge(user) }
                .fixedSize()
                .accessibilityHint(TetrisPhoneText.challengeHint(name: user.displayName))
        } else {
            // 막힌 까닭은 **버튼**이 말하고(짧게), 근무 축은 부제가 말한다 — 둘을 한 자리에서 골랐다.
            AingButton(lines.buttonTitle, kind: .gray, size: .sm) {}
                .disabled(true)
                .fixedSize()
        }
    }
}

// MARK: - 받은 신청 · 보낸 신청

/// 받은 신청 한 건: 아바타 44 · "테트라이벌님의 신청" · 판돈 줄 + 남은 초 · [거절 회색] [수락 채움].
///
/// ★ 수락이 **루비가 실제로 빠지는 순간**이다(신청만 받은 상태에서는 0원도 안 움직인다 — 아래 판돈 시트 머리말).
private struct GamesTetrisInviteCard: View {
    let store: GamesStore
    let invite: TetrisDuelInvite

    @Environment(\.dynamicTypeSize) private var typeSize

    private var tetris: TetrisDuelStore { store.tetris }

    /// 오목·체스 판이 흐르는 동안은 테트리스 수락도 막는다(한 사람 한 판 — 삼각).
    private var canRespond: Bool { !tetris.isBusy && store.tetrisEntryBlock == nil }

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
                    PersonName(TetrisPhoneText.incomingTitle(name: invite.peer.displayName))
                    HStack(spacing: 0) {
                        GamesStakeLine(stake: invite.stake, prefix: TetrisPhoneText.stakeTitle,
                                       suffix: TetrisPhoneText.stakeGainSuffix(invite.stake))
                        GamesTetrisRemainingText(store: store, expiresAt: invite.expiresAt, prefix: " · ")
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
        AingButton(TetrisPhoneText.accept, kind: .filled, size: .md, fillsWidth: true) {
            Task { await tetris.respond(inviteID: invite.id, accept: true) }
        }
        .disabled(!canRespond)
    }

    private var declineButton: some View {
        AingButton(TetrisPhoneText.decline, kind: .gray, size: .md, fillsWidth: true) {
            Task { await tetris.respond(inviteID: invite.id, accept: false) }
        }
        .disabled(tetris.isBusy)
    }
}

/// 보낸 신청 한 줄: 아바타 · "구름빵님에게 신청했어요" · 판돈 · 남은 초 · [취소] 회색 알약.
private struct GamesTetrisOutgoingRow: View {
    let store: GamesStore
    let invite: TetrisDuelInvite

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
            Text(TetrisPhoneText.outgoingTitle(name: invite.peer.displayName))
                .font(MobileTheme.rowTitle)
                .foregroundStyle(MobileTheme.label)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 0) {
                GamesStakeLine(stake: invite.stake, prefix: TetrisPhoneText.stakeTitle)
                GamesTetrisRemainingText(store: store, expiresAt: invite.expiresAt, prefix: " · ")
            }
            .font(MobileTheme.rowSubtitle)
            .foregroundStyle(MobileTheme.label2)
        }
        .accessibilityElement(children: .combine)
    }

    private var cancelButton: some View {
        AingButton(TetrisPhoneText.cancel, kind: .gray, size: .sm) {
            Task { await store.tetris.cancelChallenge() }
        }
        .disabled(store.tetris.isBusy)
        .fixedSize()
    }
}

// MARK: - 지금 대결 중 한 줄

/// 로비 "지금 대결 중" 한 줄 — 이름 둘 · 판돈 · 오른쪽 끝에 **관전자 수 + [관전] 입구**(0.3.65).
///
/// 내 판은 칩 대신 그 자리에 "내 판" 캡션이 선다(`GamesTetrisWatchEntry` — 오목·체스와 같은 관용구).
/// 큰 글자·좁은 폭에서는 입구가 글 아래로 내려간다(오목에서 320pt 실측으로 고친 자리 — 칩이 붙으면서
/// 판돈 줄에 남는 폭이 줄어 판돈이 줄임표로 잘렸다).
private struct GamesTetrisLiveRow: View {
    let store: TetrisDuelStore
    let live: TetrisDuelLiveMatch
    let isLast: Bool

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        GroupRow(divider: isLast ? .none : .inset(MobileTheme.cardPadding), minHeight: 48) {
            if typeSize.isAccessibilitySize {
                stacked
            } else if hasEntry {
                // 오른쪽 끝에 무엇이든 붙는 행만 폭을 재본다(없으면 전과 같은 한 줄 — 빈 모양을 바꾸지 않는다).
                ViewThatFits(in: .horizontal) {
                    inline
                    stacked
                }
            } else {
                inline
            }
        }
    }

    /// 입구 슬롯이 실제로 뷰를 그리는가. 위 폭 재보기와 `entry` 가 **이 하나**를 본다 — 조건을 두 곳에 적으면
    /// 한쪽만 고쳐져 "빈 슬롯 때문에 줄을 접는" 꼴이 된다.
    private var hasEntry: Bool { GamesTetrisWatchPlan.hasTrailingContent(store, live: live) }

    private var inline: some View {
        HStack(spacing: MobileTheme.space3) {
            texts
            Spacer(minLength: 0)
            entry
        }
    }

    private var stacked: some View {
        VStack(alignment: .leading, spacing: 6) {
            texts
            entry
        }
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(TetrisPhoneText.liveRow(live.a.displayName, live.b.displayName))
                .font(MobileTheme.rowTitle)
                .foregroundStyle(MobileTheme.label)
                .fixedSize(horizontal: false, vertical: true)
            GamesStakeLine(stake: live.stake.rawValue, prefix: TetrisPhoneText.stakeTitle)
                .font(MobileTheme.rowSubtitle)
                .foregroundStyle(MobileTheme.label2)
        }
        // 합치기는 **이 글 묶음에만** 둔다 — 행 전체를 합치면 [관전]이 한 덩이에 삼켜져 보이스오버가 누를 수 없다.
        .accessibilityElement(children: .combine)
    }

    private var entry: some View {
        GamesTetrisWatchEntry(store: store, live: live)
    }
}

// MARK: - 초 단위 잎

/// 신청 만료까지 남은 초("42초 남음") — **잎 뷰**다(초 단위 값은 잎만 읽는다. 스토어는 매초 아무것도 대입하지 않는다).
private struct GamesTetrisRemainingText: View {
    let store: GamesStore
    let expiresAt: Date
    var prefix = ""

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let remaining = expiresAt.timeIntervalSince(store.context.clock.now())
            Text(prefix + TetrisPhoneText.remainingPhrase(remaining))
                .monospacedDigit()
                .accessibilityLabel(TetrisPhoneText.remainingAccessibility(remaining))
        }
    }
}

// MARK: - 판돈 시트

/// 판돈 시트(폰 체스 `GamesChessStakeSheet` 와 같은 모양): **아무것도 안 골라진 채** 열리고, 판돈은 고르기만
/// (다시 누르면 해제), 신청은 맨 아래 채운 버튼 하나.
///
/// ★ 캡션이 **거짓말을 하지 않는 것**이 이 시트의 계약이다: 신청만 한 상태에서는 **0원도 안 움직이고**, 양쪽에서
///   빠지는 것은 **수락하는 순간**이다(서버 §2.4). "신청하면 빠져요" 로 적으면 사용자가 취소를 못 해 손해를
///   본다고 믿는다(실제로는 잃는 것이 없다).
private struct GamesTetrisStakeSheet: View {
    let store: GamesStore
    let target: TetrisDuelUser

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selected: TetrisDuelStake?

    private var tetris: TetrisDuelStore { store.tetris }
    private var balance: Int? { store.rubyBalance }

    /// 지금 신청을 **낼 수 있는 판돈**(못 내면 nil). 판정은 `GamesTetrisDuelStakeSend` 한 곳이다 —
    /// 요청이 나가는 마지막 문이라 맥 스위트가 값으로 재야 한다.
    private var sendable: TetrisDuelStake? {
        GamesTetrisDuelStakeSend.sendable(selected, store: tetris, balance: balance,
                                          blockedBy: store.tetrisEntryBlock)
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(TetrisPhoneText.stakeTitle,
                        subtitle: TetrisPhoneText.stakePromptTitle(name: target.displayName),
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
                                PersonName(target.displayName)
                                Text(selected.map { TetrisPhoneText.stakePromptChosen($0.rawValue) }
                                        ?? TetrisPhoneText.stakePromptCaption)
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
                                ForEach(TetrisDuelStake.allCases, id: \.rawValue) { stake in stakeOption(stake) }
                            }
                        } else {
                            HStack(spacing: 10) {
                                ForEach(TetrisDuelStake.allCases, id: \.rawValue) { stake in stakeOption(stake) }
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Text(TetrisPhoneText.myRubyTitle)
                                .font(.footnote)
                                .foregroundStyle(MobileTheme.label2)
                            if let balance {
                                RubyPrice(balance, isShort: false, gemSize: 14, style: .footnote)
                            } else {
                                Text(TetrisPhoneText.unknownNumber).font(.footnote).foregroundStyle(MobileTheme.label2)
                            }
                            if TetrisDuelStake.allCases.contains(where: {
                                !GamesTetrisStakeSelection.affordable($0, balance: balance)
                            }) {
                                Text(TetrisPhoneText.bulletPrefix + TetrisPhoneText.stakeShortfall)
                                    .font(.footnote)
                                    .foregroundStyle(MobileTheme.label2)
                            }
                        }
                        Text(TetrisPhoneText.stakeCaption)
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
            // ★ 아무것도 안 고르면 글자가 "판돈을 고르세요" 이고 **비활성**이다 — 골라야 [신청]이 생긴다.
            AingButton(selected.map { TetrisPhoneText.challengeWithStake($0.rawValue) }
                        ?? TetrisPhoneText.stakePromptCaption,
                       kind: .filled, size: .lg, fillsWidth: true) {
                guard let stake = sendable else { return }
                dismiss()
                Task { await tetris.challenge(userID: target.id, stake: stake) }
            }
            .disabled(sendable == nil)
            .padding(.horizontal, MobileTheme.sideMargin)
            .padding(.bottom, MobileTheme.space3)
        }
        .background(MobileTheme.background.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
    }

    /// 판돈 칸 하나 — **고르기만** 한다(선택 = 파랑 틴트 + 파랑 테두리 + 체크). 모자라면 흐린 가격 + 비활성,
    /// **잔액을 모르면 막지 않는다**.
    private func stakeOption(_ stake: TetrisDuelStake) -> some View {
        let isSelected = selected == stake
        let affordable = GamesTetrisStakeSelection.affordable(stake, balance: balance)
        let enabled = affordable && !tetris.isBusy
        let shape = RoundedRectangle(cornerRadius: MobileTheme.tileRadius, style: .continuous)
        return Button {
            withAnimation(.easeOut(duration: 0.15)) {
                selected = GamesTetrisStakeSelection.toggled(current: selected, tapped: stake)
            }
        } label: {
            VStack(spacing: 2) {
                RubyPrice(stake.rawValue, isShort: !affordable, gemSize: 20, style: .title3)
                Text(TetrisPhoneText.stakeGain(stake.rawValue))
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
        .accessibilityLabel(TetrisPhoneText.stakeOptionAccessibility(stake.rawValue))
        .accessibilityValue(isSelected ? TetrisPhoneText.selected : (affordable ? "" : TetrisPhoneText.stakeShortfall))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - 규칙 시트

/// 규칙 시트 — 문구 표의 `rules` 를 그대로 그린다. ★ "앱을 나가면" 항목이 **맥과 다른 사실**이다(P7):
/// 맥은 "창을 가려도 판은 흘러간다"가 안심이고, 폰은 앱을 나가면 15초 침묵으로 **진다**.
private struct GamesTetrisRulesSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(TetrisPhoneText.rulesTitle, onClose: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: MobileTheme.space3) {
                    InsetGroup {
                        ForEach(Array(TetrisPhoneText.rules.enumerated()), id: \.offset) { index, rule in
                            GroupRow(divider: index == TetrisPhoneText.rules.count - 1
                                     ? .none : .inset(MobileTheme.cardPadding)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(rule.title)
                                        .font(MobileTheme.rowTitle)
                                        .foregroundStyle(MobileTheme.label)
                                    Text(rule.detail)
                                        .font(MobileTheme.rowSubtitle)
                                        .foregroundStyle(MobileTheme.label2)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    SectionHeader(TetrisPhoneText.controlsTitle, padded: true)
                    InsetGroup {
                        ForEach(Array(TetrisPhoneText.controls.enumerated()), id: \.offset) { index, row in
                            GroupRow(divider: index == TetrisPhoneText.controls.count - 1
                                     ? .none : .inset(MobileTheme.cardPadding)) {
                                Text(row.gesture)
                                    .font(MobileTheme.rowSubtitle)
                                    .foregroundStyle(MobileTheme.label)
                                Spacer(minLength: 8)
                                Text(row.action)
                                    .font(MobileTheme.rowSubtitle)
                                    .foregroundStyle(MobileTheme.label2)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
                .padding(.horizontal, MobileTheme.sideMargin)
                .padding(.vertical, MobileTheme.space3)
            }
        }
        .background(MobileTheme.background.ignoresSafeArea())
        .presentationDetents([.large])
    }
}
#endif
