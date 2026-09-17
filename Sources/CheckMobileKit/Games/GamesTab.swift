#if os(iOS)
import CheckCore
import CheckMobileShared
import SwiftUI

/// 게임 탭(SPEC-ios §3.5): 카드 세 장 — 타이밍 바 · 플래피 아잉(오늘 내 최고·순위) · 1:1 오목(받은 신청 수·진행 중 판).
/// 경로는 `router.pathBinding(for: .games)`, 딥링크(`games/<game>` · `gomoku/lobby|invite|match`)는 `consumePendingRoute`.
struct GamesTab: View {
    let store: GamesStore

    var body: some View {
        let router = store.context.router
        NavigationStack(path: router.pathBinding(for: .games)) {
            ScrollView {
                VStack(alignment: .leading, spacing: MobileTheme.rowSpacing) {
                    ForEach(MiniGameKind.allCases) { kind in
                        miniGameCard(kind)
                    }
                    gomokuCard
                }
                .padding(.horizontal, MobileTheme.sideMargin)
                .padding(.vertical, MobileTheme.rowSpacing)
            }
            .background(MobileTheme.background.ignoresSafeArea())
            .navigationTitle(GamesText.tabTitle)
            .refreshable {
                for kind in MiniGameKind.allCases { await store.miniGames.loadBoard(kind, withWinner: false) }
                await store.context.gomoku.loadInbox()
            }
            .navigationDestination(for: GamesDestination.self) { destination in
                switch destination {
                case .miniGame(let kind):
                    GamesMiniGameScreen(store: store, kind: kind)
                case .gomoku:
                    GamesGomokuScreen(store: store)
                }
            }
        }
        // 대국 중 화면 꺼짐 방지는 뷰가 쓰지 않는다 — 주인은 스토어 하나(`GamesStore.installIdleTimerSink`, init 에서 단다).
        .onAppear {
            store.hubDidAppear()
            consumeRoute()
        }
        .onChange(of: router.routeSerial) { consumeRoute() }
    }

    // MARK: 카드

    private func miniGameCard(_ kind: MiniGameKind) -> some View {
        let hub = store.miniGames
        let line = GamesText.todayLine(best: hub.myTodayBest(kind), rank: hub.myRank(kind), board: hub.boards[kind] ?? GamesMiniGameBoard())
        return Button {
            store.context.router.push(GamesDestination.miniGame(kind), on: .games)
        } label: {
            GamesCardLabel(
                icon: kind.icon, tint: kind == .timingBar ? MobileTheme.accent : MobileTheme.working,
                title: kind.title, subtitle: GamesMiniGameText.howToPlay(kind), detail: line,
                detailTint: hub.myRank(kind) == nil ? MobileTheme.secondaryText : MobileTheme.primaryText,
                badge: nil
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint("\(kind.title) 게임을 열어요")
    }

    private var gomokuCard: some View {
        let incoming = store.badgeCount
        let active = store.hasActiveGomokuMatch
        let gomoku = store.context.gomoku
        let line = GamesText.gomokuLine(
            incoming: incoming, hasActiveMatch: active, hasOutgoing: gomoku.outgoing != nil,
            inboxFailed: gomoku.inboxLoadFailed && gomoku.incoming.isEmpty
        )
        return Button {
            store.context.router.push(GamesDestination.gomoku, on: .games)
        } label: {
            GamesCardLabel(
                icon: "circle.grid.3x3.fill", tint: MobileTheme.aiToken,
                title: GomokuPhoneText.title, subtitle: GamesText.gomokuCardSubtitle, detail: line,
                detailTint: (incoming > 0 || active) ? MobileTheme.pending : MobileTheme.secondaryText,
                badge: incoming > 0 ? incoming : nil
            )
        }
        .buttonStyle(.plain)
        .accessibilityHint("오목 대결 화면을 열어요")
    }

    // MARK: 딥링크

    /// 라우터가 남긴 링크를 꺼내 경로를 바꾼다. 무엇을 할지는 스토어가 정한다(오목 화면이 이미 보이면 대상 판을 코어에 바로 넘긴다).
    private func consumeRoute() {
        let router = store.context.router
        guard let route = router.consumePendingRoute(for: .games), let step = store.routeStep(for: route) else { return }
        switch step {
        case .popToRoot:
            router.popToRoot(.games)
        case .push(let destination):
            router.push(destination, on: .games)
        }
    }
}

/// 게임 카드 한 장의 모양(아이콘 원판 · 제목 · 규칙 한 줄 · 오늘 줄 · 배지 · 화살표).
private struct GamesCardLabel: View {
    let icon: String
    let tint: Color
    let title: String
    let subtitle: String
    let detail: String
    let detailTint: Color
    let badge: Int?

    var body: some View {
        AingCard {
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: icon)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(tint.opacity(0.16)))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(MobileTheme.title(.title3))
                            .foregroundStyle(MobileTheme.primaryText)
                        if let badge {
                            Text("\(badge)")
                                .font(.caption.weight(.bold))
                                .monospacedDigit()
                                .foregroundStyle(MobileTheme.onAccent)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(MobileTheme.danger))
                                .accessibilityLabel("받은 신청 \(badge)건")
                        }
                    }
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(MobileTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(detail)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(detailTint)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MobileTheme.secondaryText)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
#endif
