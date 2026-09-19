#if os(iOS)
import CheckCore
import SwiftUI

/// 미니게임 화면(SPEC-ios §3.5): 머리 줄(최고 · 오늘 순위 · 안내) · 캔버스(논리 292×302 를 폭에 **등비 확대**) · 오늘 순위.
///
/// - 캔버스 어디든 **누르는 순간** = 행동(맥의 마우스 다운 래치와 같다 — 손을 뗄 때 발화하면 점프 게임엔 그 지연이 곧 낙차다).
/// - 프레임 상한은 화면 최대 주사율(`UIScreen.maximumFramesPerSecond`)을 코어 `MiniGameFrameRate` 에 넣은 값이다.
/// - 햅틱: 판에 먹힌 탭마다 가볍게, 게임오버·완주에 한 번.
/// - 앱이 background 로 가면 판은 끝(제출하지 않음) — 스토어가 한다. 화면을 떠나도 같다.
struct GamesMiniGameScreen: View {
    let store: GamesStore
    let kind: MiniGameKind

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pressLatched = false
    @State private var refreshHz = MiniGameFrameRate.baselineFPS
    /// 데모 스크린샷: 판 도중 장면을 멈춰 둔다(DEBUG · 데모에서만 참이 된다).
    @State private var framesFrozen = false

    private var hub: GamesMiniGameHub { store.miniGames }

    var body: some View {
        // 캔버스는 **폭이 정한다**(좌우 16 여백 안 폭 × 302/292). 아래 순위 스크롤과 높이를 나눠 갖게 두면 비율 맞춤이
        // 캔버스를 좁혀 양옆에 빈 띠가 생긴다(데모 스크린샷 실측).
        GeometryReader { geo in
            let width = max(0, geo.size.width - MobileTheme.sideMargin * 2)
            let height = width * MiniGameCanvas.logicalHeight / MiniGameCanvas.logicalWidth
            VStack(spacing: MobileTheme.rowSpacing) {
                header
                canvas
                    .frame(width: width, height: height)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if !hub.isPublic {
                            InlineNotice(text: GamesMiniGameText.privateNotice, kind: .info)
                                .padding(.bottom, MobileTheme.space2)
                        }
                        rankings
                    }
                    .padding(.bottom, MobileTheme.space6)
                }
                .scrollIndicators(.hidden)
                .gamesDemoScrollAnchor(isDemo: store.context.isDemo)
            }
            // 열 폭을 못 박는다 — 큰 글자에서 자식 하나가 넓어지면 열 전체가 화면 밖으로 밀렸다(AX 스크린샷 실측).
            .frame(width: width)
            .padding(.horizontal, MobileTheme.sideMargin)
            .padding(.top, 4)
        }
        .background(MobileTheme.background.ignoresSafeArea())
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .hidesTabBar(for: .miniGamePlay)
        .onAppear {
            refreshHz = GamesDisplay.maximumFramesPerSecond
            hub.openScreen(kind)
            applyDemoSeed()
        }
        .onDisappear { hub.closeScreen(kind) }
    }

    // MARK: 머리 줄

    private var header: some View {
        let best = hub.best(for: kind)
        let rank = GamesMiniGameText.rankLine(hub.myRank(kind), knowsBoard: (hub.boards[kind] ?? GamesMiniGameBoard()).knowsPlayerCount)
        return VStack(alignment: .leading, spacing: 4) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    bestLabel(best)
                    Spacer(minLength: 6)
                    rankLabel(rank)
                }
                VStack(alignment: .leading, spacing: 4) {
                    bestLabel(best)
                    rankLabel(rank)
                }
            }
            // 제출 실패·판 끝남은 조용히 삼키지 않는다(맥과 같다 — 삼키면 "잘 놀았는데 순위표에 없다"가 된다).
            if let notice = hub.submitNotice {
                Text(notice)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(MobileTheme.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func bestLabel(_ best: Int) -> some View {
        Label {
            Text(GamesMiniGameText.bestLine(best)).monospacedDigit()
        } icon: {
            // 트로피는 금(순위 메달 색) — 앰버는 연결 끊김·대기 전용이다.
            Image(systemName: "trophy.fill").foregroundStyle(MobileTheme.gold)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(MobileTheme.label)
    }

    /// 오늘 순위 한 줄. 순위표를 모르면(불러오는 중·실패) 그리지 않는다 — 실패는 아래 순위 카드가 말한다.
    /// 순위가 있으면 공용 순위 원(금은동) — 예전 파랑 글자는 링크처럼 보였다(비평 14~19).
    @ViewBuilder
    private func rankLabel(_ line: String?) -> some View {
        if let rank = hub.myRank(kind) {
            HStack(spacing: 6) {
                Text("오늘")
                    .font(.subheadline)
                    .foregroundStyle(MobileTheme.label2)
                RankBadge(rank: rank)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(line ?? "오늘 \(rank)위")
        } else if let line {
            Text(line)
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(MobileTheme.label2)
        }
    }

    // MARK: 캔버스

    @ViewBuilder
    private var canvas: some View {
        if let controller = hub.controller, controller.kind == kind {
            TimelineView(.animation(minimumInterval: MiniGameFrameRate.minimumInterval(forRefreshRate: refreshHz),
                                    paused: !controller.isPlaying || framesFrozen)) { context in
                canvasContent(controller)
                    .onChange(of: context.date) { _, now in
                        guard !framesFrozen else { return }
                        controller.tick(at: now)
                    }
            }
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(CheckTheme.panel))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(MobileTheme.separator, lineWidth: 1))
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard !pressLatched else { return }
                        pressLatched = true
                        guard !framesFrozen else { return }
                        controller.tap()
                    }
                    .onEnded { _ in pressLatched = false }
            )
            .sensoryFeedback(.impact(weight: .light), trigger: controller.tapSerial)
            .sensoryFeedback(.error, trigger: controller.gameOverSerial)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(GamesMiniGameText.canvasAccessibility(kind))
            .accessibilityValue(accessibilityValue(controller))
            .accessibilityAddTraits(.allowsDirectInteraction)
            .accessibilityAction { controller.tap() }
            // 캔버스 안 글자는 판 배율을 따른다 — 시스템 글자 크기에 끌려가면 판을 넘친다.
            .dynamicTypeSize(...DynamicTypeSize.large)
        } else {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(CheckTheme.panel)
        }
    }

    @ViewBuilder
    private func canvasContent(_ controller: GamesPlayController) -> some View {
        switch kind {
        case .timingBar:
            GamesTimingBarCanvas(game: controller.timing, bestScore: hub.best(for: kind), reduceMotion: reduceMotion)
        case .flappy:
            GamesFlappyCanvas(game: controller.flappy, bestScore: hub.best(for: kind), reduceMotion: reduceMotion)
        }
    }

    private func accessibilityValue(_ controller: GamesPlayController) -> String {
        switch kind {
        case .timingBar:
            if case .finished(let total) = controller.timing.phase { return "총점 \(total)" }
            return controller.isPlaying ? "라운드 \(max(1, controller.timing.round)), 총점 \(controller.timing.total)" : GamesMiniGameText.startAction
        case .flappy:
            if controller.flappy.phase == .result { return "\(controller.flappy.score)점" }
            return controller.isPlaying ? "\(controller.flappy.score)점" : GamesMiniGameText.startAction
        }
    }

    // MARK: 오늘 순위

    @ViewBuilder
    private var rankings: some View {
        let state = hub.boards[kind] ?? GamesMiniGameBoard()
        let myID = store.context.session.session?.userID.lowercased()
        // 정족수 줄은 사람 수를 알 때만 — 불러오지 못했거나 불러오는 중이면 "아무도 안 했어요"라고 말하지 않는다.
        SectionHeader(GamesMiniGameText.rankTitle,
                      trailing: state.knowsPlayerCount ? .text(GamesMiniGameText.quorumCaption(players: state.entries.count)) : .none,
                      padded: true)
            .padding(.top, -18)
        // 어제 1등은 **자기 그룹**(순위 탭과 같은 공용 `ChampionRow`) — '오늘 순위' 첫 행처럼 읽히지 않게 떼어 둔다(시안 B 06).
        if let winner = state.yesterdayWinner {
            ChampionRow(
                caption: GamesMiniGameText.yesterdayChampion,
                name: winner.name,
                center: CenterLabel.serverValue(forDisplay: winner.center),
                score: GamesMiniGameText.score(winner.score),
                awarded: winner.awarded ? GamesMiniGameText.rubyPrizes[0] : nil
            )
            .padding(.bottom, 12)
        }
        InsetGroup {
            if state.entries.isEmpty {
                GroupRow(divider: .none) {
                    switch state.placeholder {
                    case .failed:
                        LoadFailureRow(GamesMiniGameText.failedCaption, isRetrying: state.loading) {
                            Task { await hub.loadBoard(kind, withWinner: true) }
                        }
                    case .loading:
                        LoadingRow(GamesMiniGameText.loadingCaption)
                    case .empty, .rows:
                        Text(GamesMiniGameText.emptyBoard)
                            .font(.subheadline)
                            .foregroundStyle(MobileTheme.label2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                ForEach(Array(state.entries.enumerated()), id: \.element.userID) { index, entry in
                    GamesRankRow(store: store, rank: index + 1, entry: entry, isMe: entry.userID == myID,
                                 isLast: index == state.entries.count - 1)
                }
            }
        }
        Text(GamesMiniGameText.prizeCaption)
            .font(MobileTheme.rowSubtitle)
            .foregroundStyle(MobileTheme.label2)
            .padding(.horizontal, MobileTheme.titleMargin - MobileTheme.sideMargin)
            .padding(.top, MobileTheme.space2)
    }

    // MARK: 데모

    private func applyDemoSeed() {
        #if DEBUG
        guard let seed = GamesDemoSeed.current(isDemo: store.context.isDemo), let controller = hub.controller else { return }
        switch seed {
        case .playing:
            controller.replaceForTesting(timing: GamesDemoSeed.timingBar(finished: false), flappy: GamesDemoSeed.flappy(finished: false))
            framesFrozen = true
        case .result, .bottom:
            controller.replaceForTesting(timing: GamesDemoSeed.timingBar(finished: true), flappy: GamesDemoSeed.flappy(finished: true))
        default:
            break
        }
        #endif
    }
}

/// 오늘 순위 한 줄 — **순위 탭과 같은 공용 부품**(통합 때 승격: `RankRow`·`RankRowBody`·`RankRowFace`·`PersonName`).
/// 인셋 그룹 안 48pt: 등수 원 · 얼굴(내 행은 착용 캐릭터 초상) · 이름(+ 센터 · '나') · 점수. 구분선 시작점·큰 글자 접힘·
/// 내 행 강조가 두 탭에서 같아진다(비평 4 "같은 데이터 다른 부품").
private struct GamesRankRow: View {
    let store: GamesStore
    let rank: Int
    let entry: MiniGameBoardEntry
    let isMe: Bool
    let isLast: Bool

    private let metrics = RankRowScaledMetrics()
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        RankRow(isMine: isMe, isLast: isLast, dividerInset: metrics.dividerInset(faceBase: 30),
                minHeight: 48, verticalPadding: (7, 7)) {
            RankRowBody(rank: rank, alignment: .center) {
                RankRowFace(name: entry.name, colorSeed: entry.userID, url: entry.avatarURL, userID: entry.userID, base: 30,
                            me: isMe ? GamesMeIdentity.current(store.context).rankFace : nil)
            } content: {
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 4) {
                        nameLine
                        score
                    }
                } else {
                    HStack(alignment: .center, spacing: 8) {
                        nameLine
                        Spacer(minLength: 4)
                        score
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var nameLine: some View {
        PersonName(entry.name, center: CenterLabel.serverValue(forDisplay: entry.center), isMe: isMe, onTint: true)
    }

    private var score: some View {
        Text(GamesMiniGameText.score(entry.bestScore))
            .font(MobileTheme.number(.callout, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(MobileTheme.label)
            .fixedSize()
    }
}
#endif
