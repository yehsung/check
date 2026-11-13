import CheckCore
import CoreGraphics
import Foundation
#if os(iOS)
import SwiftUI
#endif

// 폰 아잉 뒤집기 **관전 절**(로비 갈래 3/4) — "지금 대결 중" 목록과 남의 진행 중인 판을 **읽기 전용**으로 보는 판.
// 본은 폰 체스 관전(`GamesChessWatch.swift`)이고, 맥 `ReversiSpectateSide`·`ReversiWatchStatusText` 를 문구·순서 참고로 썼다.
//
// ── 자리 계약(부르는 쪽이 지킨다) ──
// 이 절은 **로비 스크롤 안의 한 절**이다. 새 라우트도, 새 화면도 아니다: 자식 화면을 push 하면 아잉 뒤집기 화면의 `onDisappear` →
// `reversiScreenDidDisappear()` 가 `stopWatching()` 을 불러 관전이 내려간다(배선 갈래 1/4). 로비는 한 줄만 둔다:
//
//     GamesReversiWatchSection(store: store.reversi)   // "지금 대결 중" ↔ 관전 판을 `spectating` 으로 갈아 끼운다
//
// 그래서 이 절은 제 스크롤도, 떠 있는 아래 막대도 만들지 않는다(둘 다 로비 스크롤과 싸운다). [관전]을 누른 자리가 그대로 판이 된다.
//
// ── 입력이 하나도 없다 ──
// 판은 `GamesReversiBoard(onTap: nil)` 이고 둘 수 있는 칸 점도 없다(값은 `GamesReversiWatchPlan` 에서 온다 — 뷰에 nil 을 적어 두면
// 누가 처리기를 끼워도 맥 스위트가 모른다). [기권]·[도전]도 없다 — 관전자에게는 걸린 판돈이 없다.
//
// ── 승자는 서버가 말한 것만 ──
// `reversi_watch` 는 읽기 전용이라 마감이 지난 판을 닫지 않는다 — "시간이 다 됐으니 누가 이겼겠지" 로 결과를 만들지 않는다(시계가 0 이면 주황으로
// 멈춰 보여 주고 상태는 여전히 "그 사람 차례"다 — 대국자의 다음 조회나 매분 정산이 닫는다).
// 끝난 판의 승자 색은 코어가 **서버 판 행**에서 옮긴 값(`ReversiSpectating.winner`) 하나다. 아잉 뒤집기 판 행은 `black`·`white` 를 uuid 로 싣고
// 서버가 `winner = case result when 'black_win' then black when 'white_win' then white end` · `check (winner in (black, white))` 로 둘을 묶는다
// (20261108200000_reversi.sql) — 테트리스처럼 a/b 자리·challenger 축이 섞이지 않는다. 이름은 **서버가 말한 흑·백 사람**에서만 고른다(로비 카드의
// a/b 는 uuid 순서라 색이 아니다). 승자를 모르면(무승부 · 사람을 아직 못 받은 틱) 이름을 지어내지 않는다.
// 말할 때도 **3인칭**이다("구름빵(흑) 승리") — 관전자에게는 둘 다 남이라 "이겼어요"는 누구 이야기인지 모른다.

/// 관전 입구·관전 판의 **순수 판정**(맥에서 돈다). 색·글꼴은 고르지 않는다.
@MainActor
package enum GamesReversiWatchPlan {
    /// 로비 "지금 대결 중" 한 행의 오른쪽 끝에 서는 것(체스·테트리스와 같은 표).
    package enum Entry: Equatable, Sendable {
        /// 아무것도 두지 않는다(주 스위치가 꺼진 배선 — `startWatching` 이 조용히 돌아서므로 눌러도 아무 일 없는 버튼이 된다).
        case absent
        /// 내 판 — 캡션만(관전에 못 들어간다. 코어 `startWatching` 은 내 판이면 관전 대신 그 판을 읽는다).
        case myMatch
        /// 서버에 `reversi_watch` 가 아직 없다 — 캡션만.
        case soon
        /// [관전] 칩.
        case chip
    }

    /// ★ 잠금은 `watchUnavailable` **하나**로 판정한다 — `rankingUnavailable`(순위표가 없다)·`spectatorCountUnavailable`(관전자 수만 없다)과
    ///   겸업시키면 "수를 못 센다"는 이유로 멀쩡한 관전이 통째로 막힌다(체스가 데인 자리 · 맥 `ReversiLiveRow` 의 `canWatch` 와 같은 깃발).
    package static func entry(_ store: ReversiStore, isMine: Bool) -> Entry {
        guard store.spectatorFeaturesEnabled else { return .absent }
        if isMine { return .myMatch }
        if store.watchUnavailable { return .soon }
        return .chip
    }

    /// 줄 오른쪽 끝 슬롯이 무엇이든 그리는가 — 입구 또는 관전자 수. 폭 재보기와 슬롯 내용이 **이 하나**를 본다.
    /// 관전자 수는 주 스위치와 무관하다(로비 응답이 실어 온 사실이다).
    package static func hasTrailingContent(_ store: ReversiStore, live: ReversiLiveMatch) -> Bool {
        entry(store, isMine: store.isMine(live)) != .absent || GamesWatcherCount.shows(live.watchers)
    }

    // MARK: 관전 판에 넘기는 값 — 입력이 0건인 자리

    /// 판의 탭 처리기. ★ **늘 nil** — 관전자는 아무것도 두지 못한다.
    package static let boardTapHandler: ((Int) -> Void)? = nil
    /// 둘 수 있는 칸 점. ★ 늘 비었다(관전자의 차례는 없다).
    package static let boardLegalTargets: Set<Int> = []
    /// [기권]을 그리는가. ★ 늘 거짓 — 관전자에게는 걸린 판돈이 없다.
    package static let showsResign = false
}

/// 관전 상태 상자의 판정(순수 — 맥 `ReversiWatchStatusText` 와 같은 표 + 승자 이름).
///
/// ★ **시각이 들어오지 않는다** — 마감이 지나도 결과를 지어내지 않으므로 시각이 바꿀 문구가 없다(상태 상자에 타이머가 없다).
package enum GamesReversiWatchStatus {
    package enum Kind: Equatable, Sendable {
        /// 첫 응답 전(색·차례를 모른다).
        case loading
        case turn(ReversiColor)
        case ended
    }

    package static func kind(for watch: ReversiSpectating) -> Kind {
        if watch.isFinished { return .ended }
        // 색이 서기 전(첫 응답 전)에는 차례를 말하지 않는다 — 씨앗 얼굴(a/b)은 uuid 순서라 색이 아니다.
        guard watch.blackUser != nil, watch.whiteUser != nil, let turn = watch.turn else { return .loading }
        return .turn(turn)
    }

    /// 끝난 판의 이긴 색 — 서버 판 행에서 옮긴 값 하나(파일 머리말). 끝나지 않았으면 nil(진행 중에 승자를 말하지 않는다).
    package static func winnerColor(for watch: ReversiSpectating) -> ReversiColor? {
        watch.isFinished ? watch.winner : nil
    }

    /// 이긴 사람의 부를 수 있는 이름 — **서버가 말한 흑·백 사람**에서만. 모르거나 이름이 비었으면 nil("— 승리"는 아무도 가리키지 못한다).
    package static func winnerName(for watch: ReversiSpectating) -> String? {
        guard let color = winnerColor(for: watch) else { return nil }
        let user = color == .black ? watch.blackUser : watch.whiteUser
        let name = user?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? nil : name
    }

    package static func headline(for watch: ReversiSpectating) -> String {
        switch kind(for: watch) {
        case .ended:
            guard let winner = winnerColor(for: watch) else { return ReversiPhoneText.watchEndedDraw }
            return ReversiPhoneText.watchEndedWin(winner, name: winnerName(for: watch))
        case .loading:
            return ReversiPhoneText.watchLoading
        case .turn(let turn):
            return ReversiPhoneText.watchingTurn(turn)
        }
    }

    /// 둘째 줄 — **끝난 판에만** 있다(진행 중에는 지어낼 말이 없다). 사유는 3인칭이고 자리 비움 횟수는 서버 값이다.
    package static func detail(for watch: ReversiSpectating, lossStreak: Int) -> String? {
        guard watch.isFinished else { return nil }
        let reason = ReversiPhoneText.watchEndReason(watch.endReason, winner: winnerColor(for: watch),
                                                     lossStreak: max(1, lossStreak))
        return reason.isEmpty ? nil : reason
    }

    /// 카드 이름 — 사람을 모르거나 이름이 빈 문자열이면 "—".
    package static func displayName(_ user: ReversiUser?) -> String {
        let name = user?.displayName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? ReversiPhoneText.watchUnknownName : name
    }

    /// 관전 시계 색의 뜻. ★ **0 은 주황**(대기색)이다 — 빨강은 5초 아래 경고 자리라 0 을 빨갛게 하면 색만으로 "졌다"로 읽힌다
    /// (관전자에게 결과를 지어내는 색 · 맥 `ReversiDeadlineRing` 과 같은 규칙).
    package static func clockTint(remaining: Double) -> GamesChessMatchTint {
        if remaining <= 0 { return .warn }
        return GamesReversiMatchChrome.ringTint(remaining: remaining)
    }
}

/// 관전 판 한 변(pt). 판은 로비 스크롤 **안**이라 `GeometryReader` 로 높이를 못 읽는다 — 열 폭과 스크롤 뷰포트 높이를 받아 정한다.
/// ★ 폭만 보면 아래가 잘린다 — 관전에서 가장 중요한 상태(누구 차례 · 끝났는가)가 판보다 먼저다(체스 관전이 iPhone SE 에서 데인 자리).
package enum GamesReversiWatchBudget {
    /// `MobileTheme.space2`(8) — 토큰은 iOS 전용이라 숫자를 옮겨 적는다.
    package static let gap: CGFloat = 8
    /// 절 머리(`SectionHeader(padded: true)` + [나가기]): 위 22 + title3 24 + 아래 8.
    package static let sectionHeader: CGFloat = 22 + 24 + 8
    /// 사람 카드 한 장: 초상 44 + 위아래 8.
    package static let playerCard: CGFloat = 44 + 8 * 2
    /// 상태 상자: subheadline 두 줄(20×2) + 위아래 10.
    package static let statusBox: CGFloat = 20 * 2 + 10 * 2

    package static func blocksAroundBoard() -> CGFloat {
        let blocks: [CGFloat] = [sectionHeader, playerCard, playerCard, statusBox]
        return blocks.reduce(0, +) + gap * CGFloat(blocks.count)
    }

    /// 검산(기본 글자 · 블록 합 266): iPhone SE 375×667 → 열 343 · 뷰포트 ≈ 554 → 288(높이가 이긴다).
    /// iPhone 15 393×852 → 열 361 · 뷰포트 ≈ 739 → 360(폭이 이긴다 — 괜히 줄이지 않는다). 뷰포트를 모르면(0) 폭만 본다.
    /// 바닥은 `GamesReversiBoardLayout.minimumSide`(열이 더 좁으면 열 폭) · 칸이 정수 pt 가 되게 8의 배수로 내린다.
    package static func side(column: CGFloat, viewportHeight: CGFloat) -> CGFloat {
        guard column.isFinite, column > 0 else { return GamesReversiBoardLayout.minimumSide }
        var side = column
        if viewportHeight.isFinite, viewportHeight > 0 {
            side = min(side, viewportHeight - blocksAroundBoard())
        }
        side = max(min(GamesReversiBoardLayout.minimumSide, column), side)
        return max(8, (side / 8).rounded(.down) * 8)
    }
}

#if os(iOS)

/// 관전 절. `store.spectating` 이 모양을 고른다(파일 머리 '자리 계약').
struct GamesReversiWatchSection: View {
    let store: ReversiStore

    var body: some View {
        if let watch = store.spectating {
            GamesReversiWatchPanel(store: store, watch: watch)
        } else {
            GamesReversiLiveSection(store: store)
        }
    }
}

// MARK: - 지금 대결 중 (관전 입구)

/// "지금 대결 중" 절 — 남의 판 목록과 [관전] 입구. 목록은 **서버 순서 그대로**(최근 순 — 코어가 재정렬하지 않는다).
private struct GamesReversiLiveSection: View {
    let store: ReversiStore

    var body: some View {
        let lives = store.liveMatches
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(ReversiPhoneText.liveTitle,
                          trailing: lives.isEmpty ? .none : .text(ReversiPhoneText.liveCount(lives.count)),
                          padded: true)
            InsetGroup {
                if lives.isEmpty {
                    GroupRow(divider: .none) {
                        Text(ReversiPhoneText.noLive)
                            .font(.subheadline)
                            .foregroundStyle(MobileTheme.label2)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                } else {
                    ForEach(Array(lives.enumerated()), id: \.element.id) { index, live in
                        GamesReversiLiveRow(store: store, live: live, isLast: index == lives.count - 1)
                    }
                }
            }
        }
    }
}

/// "지금 대결 중" 한 줄: 두 얼굴 · 이름 둘 · 판돈 액수 · 경과 · 오른쪽 끝 관전자 수 + 관전 입구.
/// 큰 글자·좁은 폭에서는 입구가 글 아래로 내려간다(오목 320pt 실측 — 칩이 붙으면 판돈이 줄임표로 잘렸다).
private struct GamesReversiLiveRow: View {
    let store: ReversiStore
    let live: ReversiLiveMatch
    let isLast: Bool

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        GroupRow(divider: isLast ? .none : .inset(MobileTheme.cardPadding)) {
            if typeSize.isAccessibilitySize {
                stacked
            } else if hasEntry {
                ViewThatFits(in: .horizontal) {
                    inline
                    stacked
                }
            } else {
                inline
            }
        }
    }

    private var hasEntry: Bool { GamesReversiWatchPlan.hasTrailingContent(store, live: live) }

    private var inline: some View {
        HStack(spacing: MobileTheme.space3) {
            faces
            texts
            Spacer(minLength: 0)
            entry
        }
    }

    private var stacked: some View {
        VStack(alignment: .leading, spacing: 6) {
            faces
            texts
            entry
        }
    }

    private var faces: some View {
        HStack(spacing: 8) {
            PersonAvatar(name: live.a.displayName, colorSeed: live.a.id,
                         url: live.a.avatarURL.flatMap(URL.init(string:)), userID: live.a.id, size: 30,
                         characterHint: live.a.characterID)
            Text("vs")
                .font(.footnote)
                .foregroundStyle(MobileTheme.label2)
            PersonAvatar(name: live.b.displayName, colorSeed: live.b.id,
                         url: live.b.avatarURL.flatMap(URL.init(string:)), userID: live.b.id, size: 30,
                         characterHint: live.b.characterID)
        }
        .accessibilityHidden(true)
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(ReversiPhoneText.livePair(live))
                .font(MobileTheme.rowTitle)
                .foregroundStyle(MobileTheme.label)
                .fixedSize(horizontal: false, vertical: true)
            // 경과는 **잎 뷰 자리**에서만 센다(절 루트가 시계를 읽으면 1초마다 목록이 다시 그려진다).
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                HStack(spacing: 0) {
                    // ★ 남의 판이라 꼬리('이기면 +N')를 붙이지 않는다(판돈 액수만).
                    GamesStakeLine(stake: live.stake)
                    Text(" · " + ReversiPhoneText.elapsedPhrase(store.clock().timeIntervalSince(live.startedAt)))
                        .monospacedDigit()
                }
                .font(MobileTheme.rowSubtitle)
                .foregroundStyle(MobileTheme.label2)
            }
        }
        // 합치기는 **이 글 묶음에만** — 행 전체를 합치면 [관전]이 한 덩이에 삼켜져 보이스오버가 누를 수 없다.
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var entry: some View {
        if hasEntry {
            HStack(spacing: 6) {
                GamesWatcherBadge(count: live.watchers)
                entryControl
            }
        }
    }

    @ViewBuilder
    private var entryControl: some View {
        switch GamesReversiWatchPlan.entry(store, isMine: store.isMine(live)) {
        case .absent:
            EmptyView()
        case .myMatch:
            caption(ReversiPhoneText.myMatch, voiceOver: nil)
        case .soon:
            caption(ReversiPhoneText.watchSoonCaption, voiceOver: ReversiNoticeText.unavailable)
        case .chip:
            AingButton(ReversiPhoneText.watch, kind: .tinted, size: .sm) {
                store.startWatching(matchID: live.id)
            }
            .fixedSize()
            .accessibilityHint(ReversiPhoneText.watchChipHint)
        }
    }

    private func caption(_ text: String, voiceOver: String?) -> some View {
        Text(text)
            .font(MobileTheme.rowSubtitle)
            .foregroundStyle(MobileTheme.label2)
            .fixedSize()
            .accessibilityLabel(Text(voiceOver ?? text))
    }
}

// MARK: - 관전 판 (로비 자리)

/// 관전 판 — "지금 대결 중" 절이 **그 자리에서** 이 모양으로 바뀐다.
/// 위에서부터: 절 머리(+[나가기]) · 흑 카드 · 판 · 백 카드 · 상태 상자 · 판돈·관전자 | N수·경과 · 수 기록 · 캡션. **입력이 하나도 없다.**
private struct GamesReversiWatchPanel: View {
    let store: ReversiStore
    let watch: ReversiSpectating

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize

    /// 절의 폭(= 열 폭)과 로비 스크롤의 보이는 높이. 판 한 변이 여기서 나온다(`GamesReversiWatchBudget`).
    @State private var columnWidth: CGFloat = 0
    @State private var viewportHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: MobileTheme.space2) {
            header
            players
            statusBox
            info
            GamesReversiMoveList(plies: watch.plies, counts: watch.counts)
            caption
        }
        .onGeometryChange(for: CGFloat.self) { proxy in proxy.size.width } action: { width in
            if width != columnWidth { columnWidth = width }
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.bounds(of: .scrollView)?.height ?? 0
        } action: { height in
            if height != viewportHeight { viewportHeight = height }
        }
    }

    /// 절 머리 + [나가기]. 문은 하나다 — `leaveWatch()` 는 관전을 내리고 로비·순위를 다시 읽는다(`stopWatching()` 은 낡은 목록을 남긴다).
    private var header: some View {
        SectionHeader(ReversiPhoneText.watchTitle,
                      trailing: .action(ReversiPhoneText.leaveWatch) { store.leaveWatch() },
                      padded: true)
            .accessibilityHint(ReversiPhoneText.leaveWatchHint)
    }

    // MARK: 두 사람 · 판

    @ViewBuilder
    private var players: some View {
        if watch.blackUser != nil || watch.whiteUser != nil || !watch.faces.isEmpty {
            playerRow(.black, index: 0)
            board
            playerRow(.white, index: 1)
        } else {
            // 씨앗도 응답도 없다(로비 주기 사이 목록에서 빠진 판을 눌렀다) — 빈 카드 두 장 대신 한 줄이다.
            InsetGroup {
                GroupRow(divider: .none) {
                    if watch.isFinished {
                        Text(ReversiPhoneText.playersUnknown)
                            .font(.subheadline)
                            .foregroundStyle(MobileTheme.label2)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                    } else {
                        LoadingRow(ReversiPhoneText.watchLoading)
                    }
                }
            }
            board
        }
    }

    /// 카드 한 자리. **흑·백을 추측하지 않는다**: 서버가 색을 말하기 전에는 씨앗 얼굴만 그리고 돌 배지·시계를 달지 않는다.
    private func playerRow(_ color: ReversiColor, index: Int) -> some View {
        let known = watch.blackUser != nil && watch.whiteUser != nil
        let user: ReversiUser?
        let subtitle: String?
        if known {
            user = color == .black ? watch.blackUser : watch.whiteUser
            subtitle = GamesReversiMatchChrome.cardSubtitle(
                color: color, counts: watch.counts,
                autoStreak: color == .black ? watch.blackAutoStreak : watch.whiteAutoStreak,
                limit: store.autoAbandonStreak)
        } else {
            user = watch.faces.indices.contains(index) ? watch.faces[index] : nil
            subtitle = (index == 0 && !watch.isFinished) ? ReversiPhoneText.watchLoading : nil
        }
        return GamesReversiWatchPlayerRow(
            store: store, user: user, color: known ? color : nil,
            isTurn: known && !watch.isFinished && watch.turn == color,
            deadline: watch.deadline, subtitle: subtitle)
    }

    /// 판 한 장(가운데). ★ **입력이 0건이다** — 값은 전부 `GamesReversiWatchPlan` 에서 온다. 뒤집기 그림은 코어가 관전에도 붙인다(`applyWatch`).
    private var board: some View {
        GamesReversiBoard(
            store: store, matchID: watch.id, board: watch.board,
            side: GamesReversiWatchBudget.side(column: columnWidth, viewportHeight: boardViewport),
            legalTargets: GamesReversiWatchPlan.boardLegalTargets,
            lastStoneIdx: watch.lastStoneIdx, autoStones: watch.autoStones,
            turn: watch.isFinished ? nil : watch.turn,
            onTap: GamesReversiWatchPlan.boardTapHandler)
            .shadow(color: colorScheme == .dark ? .black.opacity(0.35) : Color.black.opacity(0.16), radius: 9, y: 6)
            .frame(maxWidth: .infinity)
    }

    /// 큰 글자에서는 예산 상수가 실제보다 작아져 상한이 낙관적이 된다 — 보이는 높이의 비율로 한 번 더 줄인다(대국 화면과 같은 비율).
    private var boardViewport: CGFloat {
        guard viewportHeight > 0 else { return 0 }
        if typeSize.isAccessibilitySize { return GamesReversiWatchBudget.blocksAroundBoard() + viewportHeight * 0.40 }
        if typeSize >= .xLarge { return GamesReversiWatchBudget.blocksAroundBoard() + viewportHeight * 0.52 }
        return viewportHeight
    }

    // MARK: 상태 · 판돈 · 수

    private var statusBox: some View {
        let kind = GamesReversiWatchStatus.kind(for: watch)
        let tint = Self.tint(kind)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: Self.symbol(kind))
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                Text(GamesReversiWatchStatus.headline(for: watch))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MobileTheme.label)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            if let detail = GamesReversiWatchStatus.detail(for: watch, lossStreak: store.autoAbandonStreak) {
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(MobileTheme.label2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: MobileTheme.innerRadius, style: .continuous).fill(tint.opacity(0.12)))
        .accessibilityElement(children: .combine)
    }

    /// 진행 중은 초록 · 끝은 청회색 · 모름은 회색. **빨강은 쓰지 않는다** — 관전자에게 결과를 지어내는 색이다.
    private static func tint(_ kind: GamesReversiWatchStatus.Kind) -> Color {
        switch kind {
        case .loading: return MobileTheme.label2
        case .turn: return MobileTheme.working
        case .ended: return MobileTheme.offWork
        }
    }

    private static func symbol(_ kind: GamesReversiWatchStatus.Kind) -> String {
        switch kind {
        case .loading: return "hourglass"
        case .turn: return "eye"
        case .ended: return "flag.checkered"
        }
    }

    private var info: some View {
        InsetGroup {
            GroupRow(divider: .none) {
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 4) { stakeRow; moveLine }
                } else {
                    stakeRow
                    Spacer(minLength: MobileTheme.space2)
                    moveLine
                }
            }
        }
    }

    /// 판돈 액수 + **관전자 수**(나 말고 몇 명이 보는가 — 0 이면 눈 칸이 서지 않는다). ★ 꼬리를 붙이지 않는다(관전자는 한 푼도 못 얻는다).
    private var stakeRow: some View {
        HStack(spacing: 6) {
            if let stake = watch.stake {
                GamesStakeLine(stake: stake)
                    .font(MobileTheme.rowSubtitle)
                    .foregroundStyle(MobileTheme.label2)
            } else {
                Text(ReversiPhoneText.stakeUnknown)
                    .font(MobileTheme.rowSubtitle)
                    .foregroundStyle(MobileTheme.label2)
            }
            GamesWatcherBadge(count: store.spectatorCount)
        }
    }

    /// "12수 · 1분 35초째" — **잎 뷰**. 끝난 판은 경과를 세지 않는다.
    @ViewBuilder
    private var moveLine: some View {
        if let startedAt = watch.startedAt, !watch.isFinished {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                infoText(ReversiPhoneText.watchMoves(watch.moveCount) + " · "
                         + ReversiPhoneText.elapsedPhrase(store.clock().timeIntervalSince(startedAt)))
            }
        } else {
            infoText(ReversiPhoneText.watchMoves(watch.moveCount))
        }
    }

    private func infoText(_ text: String) -> some View {
        Text(text)
            .font(MobileTheme.rowSubtitle)
            .monospacedDigit()
            .foregroundStyle(MobileTheme.label2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var caption: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(ReversiPhoneText.watchCaption)
                .fixedSize(horizontal: false, vertical: true)
            if watch.isFinished {
                Text(ReversiPhoneText.watchTailCaption)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(MobileTheme.rowSubtitle)
        .foregroundStyle(MobileTheme.label2)
        .padding(.horizontal, MobileTheme.titleMargin - MobileTheme.sideMargin)
        .padding(.top, MobileTheme.space1)
        .accessibilityElement(children: .combine)
    }
}

/// 관전 사람 한 장 — 초상(+ 돌 배지) · 이름(+ 센터) · 돌 수 · 차례면 마감 링.
/// - `color`: 서버가 말한 돌 색. **nil 이면 색을 모른다**(첫 응답 전): 돌 배지도 초록 테두리도 링도 없다.
private struct GamesReversiWatchPlayerRow: View {
    let store: ReversiStore
    let user: ReversiUser?
    let color: ReversiColor?
    let isTurn: Bool
    let deadline: Date?
    let subtitle: String?

    private var badge: CharacterPortrait.Badge {
        guard let color else { return .none }
        return .stone(isBlack: color == .black)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: MobileTheme.groupRadius, style: .continuous)
        HStack(spacing: MobileTheme.space3) {
            // 표정은 늘 `.plain` — 관전 응답에 근무 칸이 없어 근무 표정을 쓰면 전원이 근무 중으로 보인다.
            CharacterPortrait(id: user?.characterID, mood: .plain, size: 44, badge: badge)
            VStack(alignment: .leading, spacing: 1) {
                PersonName(GamesReversiWatchStatus.displayName(user),
                           center: CenterLabel.serverValue(forDisplay: user?.center))
                if let subtitle {
                    Text(subtitle)
                        .font(MobileTheme.rowSubtitle)
                        .monospacedDigit()
                        .foregroundStyle(MobileTheme.label2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            .layoutPriority(1)
            Spacer(minLength: 4)
            if isTurn, let deadline {
                GamesReversiWatchRing(store: store, deadline: deadline)
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(shape.fill(MobileTheme.surface))
        // 차례인 카드만 초록 테두리. 남은 시간이 0 이어도 초록이다 — 차례는 여전히 그 사람 것이다(결과가 아니다).
        .overlay(shape.strokeBorder(isTurn ? MobileTheme.workingDot : Color.clear, lineWidth: 2))
    }
}

/// 관전 마감 링 — **잎 뷰**. 내 판 링(`GamesReversiTurnRing`)은 `store.remainingSeconds`(**내 판 전용**)를 읽으므로 쓰지 않고,
/// 관전 판의 마감 시각을 스토어 시계로 직접 센다. 한 수 시간은 로비가 말한 값(`turnSeconds`). 0 은 주황(`clockTint`).
private struct GamesReversiWatchRing: View {
    let store: ReversiStore
    let deadline: Date

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.2, paused: !store.isWindowVisible)) { _ in
            let remaining = max(0, deadline.timeIntervalSince(store.clock()))
            let fraction = GamesReversiMatchChrome.ringFraction(remaining: remaining, turnSeconds: store.turnSeconds)
            let tint = GamesReversiWatchStatus.clockTint(remaining: remaining)
            ZStack {
                Circle().stroke(MobileTheme.fill, lineWidth: 4)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(GamesChessInk.dot(tint), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(ReversiPhoneText.remaining(remaining))
                    .font(.system(size: 13, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(GamesChessInk.color(tint))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }
            .padding(2)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(ReversiPhoneText.clockAccessibility(remaining))
        }
    }
}

#endif
