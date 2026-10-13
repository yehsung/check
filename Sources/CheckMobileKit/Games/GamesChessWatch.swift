import CheckCore
import CoreGraphics
import Foundation
#if os(iOS)
import SwiftUI
#endif

// 체스 **관전 절**(폰) — 남의 진행 중인 판을 **읽기 전용**으로 본다.
//
// ── 자리 계약(부르는 쪽이 지킨다) ──
// 이 절은 **로비 스크롤 안의 한 절**이다. 새 라우트도, 새 화면도 아니다: 자식 화면을 push 하면 체스 화면의
// `onDisappear` → `windowDidHide()` 로 스토어 폴링이 죽어(`shouldPollWatch` 가 창을 본다) 판이 갱신되지 않는다.
// 로비 화면은 **한 줄만** 두면 된다(`GamesChessScreen.lobby` 가 그렇게 부른다):
//
//     GamesChessWatchSection(store: store)     // "지금 대결 중" 절 ↔ 관전 판을 `store.spectating` 으로 갈아 끼운다
//
// 그래서 이 절은 **제 스크롤도, 떠 있는 아래 막대도 만들지 않는다**(둘 다 로비 스크롤과 싸운다).
// [관전]을 누른 자리에서 그 자리가 판으로 바뀌므로 화면이 튀지 않는다.
//
// ★ 스토어 자리는 **`ChessStore`** 다(로봇 입구 `GamesChessAISection` 과 같은 규약). 로비는 `store.chess`
//   (= `store.context.chess`)를 넘긴다 — 로비 레인의 자리표시가 `GamesStore` 로 가정했던 자리를 통합이 고쳤다.
//
// ── 이 파일이 두 겹인 까닭 ──
// 아래 **판정**(`GamesChessWatchPlan` · `GamesChessWatchStatus` · `GamesChessWatchBudget`)은 `#if os(iOS)`
// **밖**이다. 폰 뷰는 맥 스위트가 한 줄도 못 보므로(저장소 메모 '폰 뷰는 맥 스위트가 못 본다') 판정을 뷰에
// 묻어 두면 게이트를 되돌려도 전부 초록이 된다 — 오목에서 실제로 613건이 그랬다. 판정을 떼어 두면 맥
// `swift test` 가 **부르는 자리와 결과**를 값으로 잰다.
//
// ── 관전은 판만이다 ──
// 서버 `chess_watch` 는 판(FEN)·수순·남은 시간·두 사람·판돈만 준다. **채팅도 관전자 수도 없다**(그 키 자체가
// 응답에 없다). 끝난 판은 **3분 꼬리** 안에서만 보이고 그 뒤엔 `not_found` 다 — 그때 코어가 관전을 내리고
// 안내(`ChessNoticeText.watchGone`)를 남기므로, 로비 화면이 `store.notice` 를 그려야 그 말이 사용자에게 닿는다
// (맥은 `ChessLobbyInvitesBox` 가 그 자리다). 이 절은 안내줄을 따로 그리지 않는다 — 두 벌이 되면 같은 문장이
// 한 화면에 두 번 뜬다.
//
// ── 입력이 하나도 없다 ──
// 탭·호버·선택·도착 점이 전부 없다. 판은 순수 그림이고 `onTapSquare` 에 nil 이 간다(`GamesChessWatchPlan`).
// 판 방향은 **백이 아래**다 — 관전자에게는 내 색이 없다.

/// 관전 입구·관전 판의 **순수 판정**(맥에서 돈다). 색·글꼴은 고르지 않는다.
@MainActor
enum GamesChessWatchPlan {
    /// 로비 "지금 대결 중" 한 행의 오른쪽 끝에 서는 것.
    enum Entry: Equatable, Sendable {
        /// 아무것도 두지 않는다(주 스위치가 꺼진 배선).
        case absent
        /// 내 판 — 캡션만(관전에 못 들어간다).
        case myMatch
        /// 서버에 `chess_watch` 가 아직 없다 — 캡션만.
        case soon
        /// [관전] 칩.
        case chip
    }

    /// 관전 입구 판정.
    ///
    /// ★ **주 스위치가 꺼진 배선에서는 칩 자체를 두지 않는다.** `startWatching` 이 `spectatorFeaturesEnabled` 를
    ///   먼저 보고 조용히 돌아서므로(`ChessStoreWatch.swift:134`) 눌러도 아무 일이 없는 버튼이 된다.
    ///   오목도 같은 게이트다(`GamesComponents.swift:241` — `showsWatch && gomoku.spectatorFeaturesEnabled`).
    ///
    /// ★ **잠금은 `watchUnavailable` 하나로 판정한다.** `rankingUnavailable` 은 "순위표가 없다" 이고 이 둘은
    ///   같이 없어지지 않는다 — 코어가 "순위를 한 번이라도 받았으면 순위 깃발은 세우지 않는다" 로 좁혀 둔
    ///   탓에(`ChessStoreWatch.swift:320`), 순위 행을 들고 있는 사용자에게는 순위 깃발로 만든 게이트가 **영영
    ///   열려** 칩이 활성인 채 404 를 무한히 낸다(오목에서 5번 눌러 5요청 실측). 게이트와 신호는 짝으로 움직인다.
    ///   [[client-gates-come-in-pairs]]
    static func entry(_ store: ChessStore, isMine: Bool) -> Entry {
        guard store.spectatorFeaturesEnabled else { return .absent }
        if isMine { return .myMatch }
        if store.watchUnavailable { return .soon }
        return .chip
    }

    // MARK: 관전 판에 넘기는 값 — 입력이 0건인 자리

    /// 판의 탭 처리기. ★ **늘 nil 이다** — 관전자는 아무것도 쓰지 못한다. 값으로 떼어 둔 까닭은 재기 위해서다:
    /// 뷰 안에 nil 을 적어 두면 누가 거기에 처리기를 끼워도 맥 스위트가 모른다.
    static let boardTapHandler: ((ChessSquare) -> Void)? = nil
    /// 고른 말 표시 없음(관전에는 선택이 없다).
    static let boardSelection: ChessSquare? = nil
    /// 도착 점 없음.
    static let boardLegalTargets: Set<ChessSquare> = []
    /// ★ **백이 아래**다. 관전자에게는 내 색이 없고, 체스 관례가 백 아래다(맥 `ChessPanel.swift:1041`).
    static let boardWhiteAtBottom = true

    /// 체크 덮개가 설 칸. ★ **관전에도 그린다** — 선택·도착 점은 "내 차례·내 색" 에 매여 있어 버리지만
    /// 체크는 판의 사실이고, 체스에서 그건 글자로만 말해서는 안 되는 정보다(맥 관전도 같은 덮개를 그린다).
    ///
    /// ★ 깃발은 **응답이 준 값**이다(`chess_watch` 의 `in_check` → `ChessSpectateState.isInCheck`) — 관전
    ///   화면은 합법 수를 만들지 않는다(§6 ④). 끝난 판은 nil 이다(`GamesChessCheckMark` 의 가드).
    static func boardCheckSquare(for watch: ChessSpectateState) -> ChessSquare? {
        GamesChessCheckMark.square(isInCheck: watch.isInCheck, isFinished: watch.isFinished,
                                   turn: watch.turn, position: watch.position)
    }
}

/// 관전 상태 한 줄의 판정(순수 — 맥 `ChessWatchStatusText` 와 같은 표).
///
/// ★ **마감이 지나도 결과를 지어내지 않는다.** `chess_watch` 는 읽기 전용이라 시간이 다 된 판을 닫지 않으므로
/// "남은 시간이 0 인데 아직 진행 중" 인 판을 볼 수 있다(`ChessStoreWatch.swift` 머리말). 시계는 0 에서 멈춰
/// 보여 주고 상태는 여전히 "그 사람 차례" 다 — 그 판은 대국자의 다음 조회나 매분 cron 이 닫는다.
/// 그래서 이 판정에는 **시각이 들어오지 않는다**(시각이 바꿀 문구가 없다 = 상태 상자에 타이머가 없다).
enum GamesChessWatchStatus {
    enum Kind: Equatable, Sendable {
        /// 첫 응답 전(색·차례를 모른다 — 로비 카드의 a/b 는 uuid 순서라 색이 아니다).
        case loading
        case turn(ChessColor)
        case ended
    }

    static func kind(for watch: ChessSpectateState) -> Kind {
        if watch.isFinished { return .ended }
        guard watch.hasServerState, let turn = watch.turn else { return .loading }
        return .turn(turn)
    }

    static func headline(for watch: ChessSpectateState) -> String {
        switch kind(for: watch) {
        case .ended:
            guard let winner = watch.winner else { return GamesChessText.endedDraw }
            return GamesChessText.endedWin(winner)
        case .loading:
            return GamesChessText.watchLoading
        case .turn(let turn):
            return GamesChessText.watchingTurn(turn)
        }
    }

    /// 둘째 줄. **끝난 판에만 있다**(진행 중에는 머리 한 줄로 끝 — 지어낼 말이 없다).
    ///
    /// 사유는 **3인칭**(`watchEndReason`)이다. 내 기준 표(`endReason(_:outcome:)` 꼴)를 쓰면 `outcome` 이 없어
    /// 언제나 패자 쪽 문장이 나오고, 같은 상자의 머리글은 "흑 승리" 라 관전자가 "흑 승리 / 기권했어요" 라는
    /// 자기모순을 읽는다(오목 0ba552d 가 고친 자리 · 맥 `ChessWatchStatusText.detail` 의 당부).
    static func detail(for watch: ChessSpectateState) -> String? {
        guard watch.isFinished else { return nil }
        let reason = GamesChessText.watchEndReason(watch.endReason, winner: watch.winner)
        return reason.isEmpty ? nil : reason
    }
}

/// 관전 절의 세로 예산(pt · **기본 글자 크기**). 판 한 변의 **세로 상한**을 정할 때 쓴다.
///
/// ★ **너비만 보면 아래가 잘린다.** 관전에서 가장 중요한 상태(누구 차례 · 남은 시간 · 끝났는가)가 판보다
/// 먼저다. 오목 관전이 대국 화면의 식을 복사해 **글자 크기만** 보다가 iPhone SE(375×667)에서 기본 글자로도
/// 백 카드가 잘리고 상태 상자가 통째로 화면 밖이었다 — 그래서 높이 예산으로 고쳤다.
///
/// 폭 상한은 여기서 보지 않는다 — 판 부품이 제 `GeometryReader` + `aspectRatio(1, .fit)` 로 폭을 이미 보고,
/// 마지막 자르기(8의 배수)도 `GamesChessBoardMetrics.side(fitting:)` 한 곳에서 한다.
///
/// 상수마다 **어디서 나온 숫자인지** 적는다(폰 전용 화면이라 맥 `swift test` 가 그림을 그릴 수 없다 —
/// 다음 사람이 손으로 검산할 수 있어야 한다). `#if os(iOS)` 밖에 둬서 **산수만은** 맥에서 잰다.
enum GamesChessWatchBudget {
    /// `MobileTheme.space2`(8) — 그 토큰은 iOS 전용이라 숫자를 옮겨 적는다(이 파일의 판정 겹은 맥에서 돈다).
    static let gap: CGFloat = 8
    /// 절 머리(`SectionHeader(padded: true)` + 오른쪽 [나가기]): 위 22 + title3 24 + 아래 8 = 54.
    /// ★ 관전은 **로비 스크롤 안의 절**이라 [나가기]가 떠 있는 아래 막대가 아니라 이 머리에 붙는다
    /// (스크롤 끝의 버튼은 "거둘 길"이 못 된다는 오목의 교훈을, 막대 대신 **절 머리**로 지킨다).
    static let sectionHeader: CGFloat = 22 + 24 + 8
    /// 플레이어 카드 한 장: 초상 44 + 위아래 8 = 60. 이름·부제 두 줄(callout 21 + 1 + footnote 18 = 40)과
    /// 시계(44)는 초상보다 높지 않아 높이를 정하지 않는다.
    static let playerCard: CGFloat = 44 + 8 * 2
    /// 상태 상자: subheadline **두 줄**(20×2) + 위아래 10 = 60. 끝난 판이 두 줄이고(머리 + 3인칭 사유),
    /// 375pt 에서 "시간이 다 됐지만 무승부예요 · 메이트할 기물이 없어요" 는 그 둘째 줄이 두 줄로 접힌다.
    static let statusBox: CGFloat = 20 * 2 + 10 * 2

    /// 판 위·아래에서 **상태 상자까지** 자리를 먹는 블록의 합(`VStack` 간격 포함).
    /// 판돈·N수 줄과 캡션은 세지 않는다 — 상태 상자 아래고, 스크롤로 닿으면 되는 것들이다.
    static func blocksAroundBoard() -> CGFloat {
        let blocks: [CGFloat] = [sectionHeader, playerCard, playerCard, statusBox]
        return blocks.reduce(0, +) + gap * CGFloat(blocks.count)
    }

    /// 판의 **세로 상한**. `nil` 이면 아직 뷰포트를 모른다 — 그때는 상한 없이 폭이 정한다(판 부품의 몫).
    ///
    /// 뷰포트는 로비 스크롤의 보이는 높이다(`GeometryProxy.bounds(of: .scrollView)`). 절이 스크롤 **안**에
    /// 있어 `GeometryReader` 로는 못 읽는다 — 그 안에서는 제안 높이를 그대로 받아 예산이 뜻을 잃는다.
    ///
    /// 검산(기본 글자 · 블록 합 = (54+60+60+60) + 8×4 = 266):
    /// - iPhone SE 375×667 → 뷰포트 ≈ 667 − 64(상태막대+내비) − 49(탭 막대) = 554 → 예산 288 →
    ///   상한 288. 폭 상한은 361(393 기기) 또는 343(375 기기)이라 **SE 에서는 높이가 이긴다**.
    /// - iPhone 15 393×852 → 뷰포트 ≈ 739 → 예산 473 → 상한 472. 폭 361 이 더 작아 **폭이 이긴다**
    ///   (판을 괜히 줄이지 않는다).
    static func boardCap(viewportHeight: CGFloat) -> CGFloat? {
        guard viewportHeight.isFinite, viewportHeight > 0 else { return nil }
        let budget = viewportHeight - blocksAroundBoard()
        // 8의 배수로 내리는 것도 판 부품 한 곳에서 한다(칸이 `side / 8` 이라 나누어떨어져야 격자에 이음선이 없다).
        return GamesChessBoardMetrics.side(fitting: CGSize(width: .greatestFiniteMagnitude, height: budget))
    }
}

#if os(iOS)

/// 체스 관전 절. `store.spectating` 이 모양을 고른다(파일 머리 '자리 계약').
struct GamesChessWatchSection: View {
    let store: ChessStore

    var body: some View {
        if let watch = store.spectating {
            GamesChessWatchPanel(store: store, watch: watch)
        } else {
            GamesChessLiveSection(store: store)
        }
    }
}

// MARK: - 로비 절: 지금 대결 중 (관전 입구)

/// "지금 대결 중" 절 — 남의 판 목록과 [관전] 입구. 로비 스크롤 스택 안에 그대로 들어간다.
///
/// 목록은 **서버 순서 그대로**다(`accepted_at desc` — 코어가 재정렬하지 않는다).
private struct GamesChessLiveSection: View {
    let store: ChessStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(GamesChessText.liveTitle,
                          trailing: store.liveMatches.isEmpty ? .none : .text(GamesChessText.liveCount(store.liveMatches.count)),
                          padded: true)
            InsetGroup {
                if store.liveMatches.isEmpty {
                    GroupRow(divider: .none) {
                        Text(GamesChessText.noLiveMatches)
                            .font(.subheadline)
                            .foregroundStyle(MobileTheme.label2)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .accessibilityElement(children: .combine)
                } else {
                    ForEach(Array(store.liveMatches.enumerated()), id: \.element.id) { index, live in
                        GamesChessLiveRow(store: store, live: live, isLast: index == store.liveMatches.count - 1)
                    }
                }
            }
        }
    }
}

/// "지금 대결 중" 한 줄: 두 얼굴 vs · 이름 둘 · 판돈 [보석]10 · 1분 35초째 · 오른쪽 끝 관전 입구.
///
/// 큰 글자·좁은 폭에서는 칩이 글 아래로 내려간다 — 오목에서 320pt 실측으로 고친 자리다([관전] 칩 52pt 가
/// 붙으면서 판돈·경과 줄에 남는 폭이 142.5 → 78.5pt 로 줄어 **판돈이 줄임표로 잘렸다**).
private struct GamesChessLiveRow: View {
    let store: ChessStore
    let live: ChessLiveMatch
    let isLast: Bool

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        GroupRow(divider: isLast ? .none : .inset(MobileTheme.cardPadding)) {
            if typeSize.isAccessibilitySize {
                stacked
            } else if hasEntry {
                // 입구가 붙는 행만 폭을 재본다(없으면 전과 같은 한 줄 — 칩이 없는 모양을 바꾸지 않는다).
                ViewThatFits(in: .horizontal) {
                    inline
                    stacked
                }
            } else {
                inline
            }
        }
    }

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

    /// 입구 슬롯이 실제로 뷰를 그리는가. 위 폭 재보기와 아래 `entry` 가 **이 하나**를 본다 — 조건을 두 곳에
    /// 적으면 한쪽만 고쳐져 "빈 슬롯 때문에 줄을 접는" 꼴이 된다.
    private var hasEntry: Bool { GamesChessWatchPlan.entry(store, isMine: store.isMine(live)) != .absent }

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
            Text(GamesChessText.livePair(live))
                .font(MobileTheme.rowTitle)
                .foregroundStyle(MobileTheme.label)
                .fixedSize(horizontal: false, vertical: true)
            // 경과는 **잎 뷰 자리**에서만 센다(절 루트가 시계를 읽으면 1초마다 목록이 다시 그려진다).
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                HStack(spacing: 0) {
                    // ★ 남의 판이라 접미사를 붙이지 않는다(판돈 액수만).
                    GamesStakeLine(stake: live.stake.rawValue)
                    Text(" · " + GamesChessText.elapsedPhrase(store.clock().timeIntervalSince(live.startedAt)))
                        .monospacedDigit()
                }
                .font(MobileTheme.rowSubtitle)
                .foregroundStyle(MobileTheme.label2)
            }
        }
        // 합치기는 **이 글 묶음에만** 둔다 — 행 전체를 합치면 [관전]이 한 덩이에 삼켜져 보이스오버가 누를 수 없다.
        .accessibilityElement(children: .combine)
    }

    /// 관전 입구. 판정은 `GamesChessWatchPlan.entry` **하나**다(뷰가 깃발을 다시 읽지 않는다 — 그래야 맥
    /// 스위트가 게이트를 잴 수 있고, `watchUnavailable` 을 `rankingUnavailable` 로 바꾸면 빨개진다).
    @ViewBuilder
    private var entry: some View {
        switch GamesChessWatchPlan.entry(store, isMine: store.isMine(live)) {
        case .absent:
            EmptyView()
        case .myMatch:
            // 수락 직후·로비 주기 사이에 내 판이 잠깐 목록에 보이는 틈이 있어, 비워 두면 "왜 내 판만 칩이
            // 없나"로 읽힌다.
            caption(GamesChessText.myMatch, voiceOver: nil)
        case .soon:
            // 서버에 **관전이** 아직 없다(PGRST202 — 앱이 db push 보다 먼저 나간 창). 또렷한 칩을 흐려만 두면
            // 눈으로 보는 사용자는 이유를 알 길이 없다(폰엔 호버 툴팁이 없다) — 그래서 칩을 빼고 이유를 글자로.
            caption(GamesChessText.watchSoonCaption, voiceOver: ChessNoticeText.unavailable)
        case .chip:
            AingButton(GamesChessText.watch, kind: .tinted, size: .sm) {
                store.startWatching(matchID: live.id)
            }
            .fixedSize()
            .accessibilityHint(GamesChessText.watchChipHint)
        }
    }

    private func caption(_ text: String, voiceOver: String?) -> some View {
        Text(text)
            .font(MobileTheme.rowSubtitle)
            .foregroundStyle(MobileTheme.label2)
            .fixedSize()
            // 짧게 자른 것은 눈으로 보는 폭 때문이지 뜻을 줄인 게 아니다.
            .accessibilityLabel(Text(voiceOver ?? text))
    }
}

// MARK: - 관전 판 (로비 자리)

/// 관전 판 — "지금 대결 중" 절이 **그 자리에서** 이 모양으로 바뀐다(새 라우트도, 새 화면도 아니다 ·
/// 파일 머리 '자리 계약'). 그래서 **제 스크롤도 떠 있는 아래 막대도 두지 않는다** — 로비 스크롤 안의 절이다.
///
/// 위에서부터: 절 머리(+오른쪽 [나가기]) · 흑 카드 · 판 · 백 카드 · 상태 상자 · 판돈·N수·경과 · 캡션.
/// **입력이 하나도 없다** — 판은 순수 그림이고 `onTapSquare` 에 nil 이 간다.
private struct GamesChessWatchPanel: View {
    let store: ChessStore
    let watch: ChessSpectateState

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize

    /// 로비 스크롤의 **보이는 높이**. 판의 세로 상한이 여기서 나온다(0 이면 아직 모른다 → 상한 없음).
    /// 절이 스크롤 **안**에 있어 `GeometryReader` 로는 못 읽는다(그 안에서는 제안 높이를 그대로 받아
    /// 예산이 뜻을 잃는다) — `bounds(of: .scrollView)` 가 뷰포트를 말해 주는 유일한 길이다.
    @State private var viewportHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: MobileTheme.space2) {
            header
            players
            statusBox
            info
            caption
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.bounds(of: .scrollView)?.height ?? 0
        } action: { height in
            if height != viewportHeight { viewportHeight = height }
        }
    }

    /// 절 머리 + 오른쪽 [나가기]. 막대가 아니라 **머리**에 두는 까닭은 위 머리말(스크롤 안의 절)이고,
    /// 문은 **하나**다 — `leaveWatch()` 는 관전을 내리고 로비·순위를 다시 읽는다(`stopWatching()` 을
    /// 부르면 낡은 목록으로 돌아온다).
    private var header: some View {
        SectionHeader(GamesChessText.watchTitle,
                      trailing: .action(GamesChessText.leaveWatch) { store.leaveWatch() },
                      padded: true)
            .accessibilityHint(GamesChessText.leaveWatchHint)
    }

    // MARK: 두 사람 · 판

    /// 흑 카드 · 판 · 백 카드. **색을 모르는 동안에는 자리만 지킨다.**
    @ViewBuilder
    private var players: some View {
        if watch.hasServerState || !watch.faces.isEmpty {
            playerRow(.black, index: 0)
            board
            playerRow(.white, index: 1)
        } else {
            // 씨앗도 응답도 없다(로비 주기 사이 목록에서 빠진 판을 눌렀다) — 두 사람을 하나도 모르니 빈 카드
            // 두 장 대신 한 줄이다(빈 카드는 "사람이 없는 판"으로 읽힌다).
            InsetGroup {
                GroupRow(divider: .none) {
                    // **끝난 판에는 로딩을 말하지 않는다** — 폴링이 이미 멈춰(isFinished) 더 올 것이 없다.
                    if watch.isFinished {
                        Text(GamesChessText.playersUnknown)
                            .font(.subheadline)
                            .foregroundStyle(MobileTheme.label2)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                            .accessibilityElement(children: .combine)
                    } else {
                        LoadingRow(GamesChessText.watchLoading)
                    }
                }
            }
            board
        }
    }

    /// 카드 한 자리. **흑·백을 추측하지 않는다**: `faces` 의 a/b 는 uuid 순서라 색이 아니므로, 서버가
    /// `black`/`white` 를 말하기 전(`hasServerState == false`)에는 그 자리 얼굴만 그리고 **돌 배지도 시계도**
    /// 달지 않는다. 안 그러면 절반의 판이 뒤집힌다.
    private func playerRow(_ color: ChessColor, index: Int) -> some View {
        let known = watch.hasServerState
        let user: ChessUser?
        let subtitle: String?
        if known {
            user = color == .black ? watch.black : watch.white
            subtitle = user.map { _ in GamesChessText.stoneName(color) }
        } else {
            user = watch.faces.indices.contains(index) ? watch.faces[index] : nil
            subtitle = (index == 0 && !watch.isFinished) ? GamesChessText.watchLoading : nil
        }
        return GamesChessWatchPlayerRow(
            store: store,
            user: user,
            color: known ? color : nil,
            isTurn: known && !watch.isFinished && watch.turn == color,
            subtitle: subtitle
        )
    }

    /// 판 한 장(가운데 정렬). ★ **입력이 0건이다** — 값은 전부 `GamesChessWatchPlan` 에서 온다.
    ///
    /// 판 부품은 `onTapSquare == nil` 을 보고 **선택·도착 점을 스스로 버린다**(`GamesChessBoardCanvas` 머리말) —
    /// 그래도 빈 값을 넘기는 것은 두 겹을 다 맞춰 두려는 것이다(부르는 쪽이 매번 빈 값을 넘기기를 그쪽도 안 믿는다).
    ///
    /// `position` 은 **옵셔널이 아니다**(판 부품의 자리). 못 읽은 FEN·첫 응답 전에는 `.empty` 를 넘겨
    /// **빈 판**을 그린다 — 오목 관전이 첫 응답 전에 빈 판을 그리는 것과 같은 모양이고, 그 창에서 상태 상자는
    /// "판을 불러오고 있어요" 를 말한다(두 조각이 서로를 설명한다).
    private var board: some View {
        capped(
            GamesChessBoard(
                position: watch.position ?? .empty,
                // 애니메이션 모델은 코어가 세 깔때기 전부에 붙여 뒀다(관전 포함 — `applyWatch`). 그림만 읽는다.
                // ★ `ChessStore.isWindowVisible` 이 꺼진 배선에서는 `beginFlight` 가 애니메이션을 안 만든다 —
                //   그 깃발은 **배선 레인**이 켠다(이 절은 깃발을 건드리지 않는다).
                flight: store.flight,
                whiteAtBottom: GamesChessWatchPlan.boardWhiteAtBottom,
                selection: GamesChessWatchPlan.boardSelection,
                legalTargets: GamesChessWatchPlan.boardLegalTargets,
                lastMove: watch.lastMove.map { (from: $0.from, to: $0.to) },
                checkSquare: GamesChessWatchPlan.boardCheckSquare(for: watch),
                onTapSquare: GamesChessWatchPlan.boardTapHandler
            ),
            to: GamesChessWatchBudget.boardCap(viewportHeight: viewportHeight)
        )
        .shadow(color: colorScheme == .dark ? .black.opacity(0.35)
                    : Color(red: 80 / 255, green: 50 / 255, blue: 10 / 255).opacity(0.18),
                radius: 9, y: 6)
        .frame(maxWidth: .infinity)
        // 보이스오버: 판 전체가 한 요소다. 칸마다 요소를 두는 것은 두는 사람의 판뿐이다.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(GamesChessText.boardAccessibility(watch))
    }

    /// 판에 **세로 상한만** 건다(폭은 판 부품이 제 `aspectRatio(1, .fit)` 로 본다). 상한을 모르는 첫 한 틱은
    /// 그대로 둔다 — `.frame(maxHeight: .infinity)` 로 메우면 그 한 틱에 판이 세로로 늘어진다.
    ///
    /// 큰 글자에서는 예산 상수들이 실제보다 작아져 상한이 과하게 낙관적이 되므로 비율 상한을 같이 둔다.
    @ViewBuilder
    private func capped(_ board: some View, to cap: CGFloat?) -> some View {
        if let cap {
            let fraction: CGFloat = typeSize.isAccessibilitySize ? 0.40 : (typeSize >= .xLarge ? 0.52 : 1)
            board.frame(maxHeight: min(cap, max(GamesChessBoardMetrics.minimumSide, viewportHeight * fraction)))
        } else {
            board
        }
    }

    // MARK: 상태 · 판돈 · 수 · 경과

    private var statusBox: some View {
        let kind = GamesChessWatchStatus.kind(for: watch)
        let tint = Self.tint(kind)
        // 글자는 `label` 이고 뜻은 기호·바탕이 낸다(공용 `InlineNotice` 와 같은 문법 — 틴트 위 틴트 글자는 대비가 떨어진다).
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: Self.symbol(kind))
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                Text(GamesChessWatchStatus.headline(for: watch))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MobileTheme.label)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            if let detail = GamesChessWatchStatus.detail(for: watch) {
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
    private static func tint(_ kind: GamesChessWatchStatus.Kind) -> Color {
        switch kind {
        case .loading: return MobileTheme.label2
        case .turn: return MobileTheme.working
        case .ended: return MobileTheme.offWork
        }
    }

    private static func symbol(_ kind: GamesChessWatchStatus.Kind) -> String {
        switch kind {
        case .loading: return "hourglass"
        case .turn: return "eye"
        case .ended: return "flag.checkered"
        }
    }

    /// 판돈 | N수 · 경과 한 줄. 판돈은 씨앗이 없으면 첫 응답 전까지 모른다("판돈 —").
    private var info: some View {
        InsetGroup {
            GroupRow(divider: .none) {
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 4) { stakeLine; moveLine }
                } else {
                    stakeLine
                    Spacer(minLength: MobileTheme.space2)
                    moveLine
                }
            }
        }
    }

    /// 판돈 **액수만** — ★ 접미사를 붙이지 않는다(관전자는 이 판에서 한 푼도 얻지 못한다).
    @ViewBuilder
    private var stakeLine: some View {
        if let stake = watch.stake {
            GamesStakeLine(stake: stake)
                .font(MobileTheme.rowSubtitle)
                .foregroundStyle(MobileTheme.label2)
        } else {
            Text(GamesChessText.stakeUnknown)
                .font(MobileTheme.rowSubtitle)
                .foregroundStyle(MobileTheme.label2)
        }
    }

    /// "12수 · 1분 35초째" — **잎 뷰**. 끝난 판은 경과를 세지 않는다(끝난 뒤 흐르는 시간은 아무 뜻도 없다).
    @ViewBuilder
    private var moveLine: some View {
        if let startedAt = watch.startedAt, !watch.isFinished {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                infoText(GamesChessText.watchPly(watch.plyCount) + " · "
                    + GamesChessText.elapsedPhrase(store.clock().timeIntervalSince(startedAt)))
            }
        } else {
            infoText(GamesChessText.watchPly(watch.plyCount))
        }
    }

    private func infoText(_ text: String) -> some View {
        Text(text)
            .font(MobileTheme.rowSubtitle)
            .monospacedDigit()
            .foregroundStyle(MobileTheme.label2)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// 카드 밑 작은 줄: 입력이 없다는 사실 + 끝난 판의 3분 꼬리.
    private var caption: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(GamesChessText.watchCaption)
                .fixedSize(horizontal: false, vertical: true)
            if watch.isFinished {
                Text(GamesChessText.watchTailCaption)
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

/// 관전 플레이어 한 장 — 초상 · 이름(+센터) · 돌 색 · 그쪽 시계.
///
/// - `color`: 서버가 말한 돌 색. **nil 이면 색을 모른다**(첫 응답 전): 돌 배지도 초록 테두리도 시계도 없다.
/// - `user`: nil 이면 그 자리 사람조차 모른다(씨앗 없는 판) — 이름 자리에 "—".
private struct GamesChessWatchPlayerRow: View {
    let store: ChessStore
    let user: ChessUser?
    let color: ChessColor?
    let isTurn: Bool
    let subtitle: String?

    /// 돌 배지는 **색을 알 때만** — 모르는 동안 아무 색이나 달면 절반의 판이 뒤집힌다.
    private var badge: CharacterPortrait.Badge {
        guard let color else { return .none }
        return .stone(isBlack: color == .black)
    }

    /// 사람을 모르거나 **이름이 빈 문자열**이면 "—". 코어 경계가 이름을 모를 때 nil 이 아니라 빈 문자열을
    /// 넣으므로 `??` 로는 못 접는다(오목에서 이름 줄이 통째로 비던 함정).
    private var displayName: String {
        let name = user?.displayName ?? ""
        return name.isEmpty ? GamesChessText.unknownName : name
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: MobileTheme.groupRadius, style: .continuous)
        HStack(spacing: MobileTheme.space3) {
            // 표정은 **늘 `.plain`**(상태 없음). 관전 응답에 `is_working` 키가 없어 근무 표정을 쓰면 전원이
            // 근무 중으로 보인다 — 근무 상태를 모르는 자리에서 링은 상태 점과 같은 단정이다.
            CharacterPortrait(id: user?.characterID, mood: .plain, size: 44, badge: badge)
            VStack(alignment: .leading, spacing: 1) {
                PersonName(displayName, center: CenterLabel.serverValue(forDisplay: user?.center))
                if let subtitle {
                    Text(subtitle)
                        .font(MobileTheme.rowSubtitle)
                        .foregroundStyle(MobileTheme.label2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            .layoutPriority(1)
            Spacer(minLength: 4)
            if let color {
                GamesChessWatchClock(store: store, color: color, isTurn: isTurn)
                    .frame(width: 64, height: 44)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(shape.fill(MobileTheme.surface))
        // 차례인 카드만 초록 테두리. 남은 시간이 0 이어도 초록이다 — 차례는 여전히 그 사람 것이고,
        // 관전자가 볼 수 있는 "0 인데 진행 중"은 결과가 아니다.
        .overlay(shape.strokeBorder(isTurn ? MobileTheme.workingDot : Color.clear, lineWidth: 2))
    }
}

/// 관전 한쪽 시계 — **잎 뷰**. 시계가 **둘** 있다는 것이 오목과 가장 다른 점이다(둘이 같은 값이면 한쪽이
/// 안 그려진 것이다).
///
/// ★ **스토어에서 다시 읽는다.** 값으로 받아 두면 폴링이 깨우지 않는 동안 그 값이 굳는다 — `chess_watch` 는
/// 저장된 ms 와 `turn_started_ms` 를 그대로 싣고 상대가 생각하는 동안 응답이 **매번 같아서**(관찰 대상이
/// 안 바뀐다) 보간은 여기서만 살아난다.
///
/// 눈금은 0.2초다(10초 아래는 소수 한 자리로 그린다 — 맥과 같은 표). **흐르지 않는 쪽은 멈춘다**:
/// 창 표시 깃발(`isWindowVisible`)로는 멈추지 않는다 — 그 값은 맥 창 개념이라 폰 배선이 늦으면 보이는
/// 시계가 굳는다. 폰은 화면을 떠나거나 background 로 가면 시스템이 TimelineView 를 세운다.
private struct GamesChessWatchClock: View {
    let store: ChessStore
    let color: ChessColor
    let isTurn: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.2, paused: !isRunning)) { context in
            let remaining = store.spectating?.clock.remainingSeconds(color, now: context.date) ?? 0
            face(remaining: remaining)
        }
    }

    private var isRunning: Bool { store.spectating?.clock.running == color }

    private func face(remaining: Double) -> some View {
        let total = max(1, Double(store.initialMs) / 1000)
        let fraction = min(1, max(0, remaining / total))
        // 0 은 **대기색**이다(빨강은 10초 아래 경고 자리다 — 0 을 빨갛게 하면 색만으로 "졌다"로 읽힌다).
        let tint: Color = remaining <= 0 ? MobileTheme.pending
            : (remaining <= 10 ? MobileTheme.danger
               : (remaining <= 30 ? MobileTheme.pending : (isTurn ? MobileTheme.working : MobileTheme.label2)))
        return VStack(spacing: 3) {
            Text(GamesChessText.clock(remaining))
                .font(MobileTheme.number(.subheadline, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(MobileTheme.fill)
                    Capsule().fill(tint).frame(width: max(1, proxy.size.width * fraction))
                }
            }
            .frame(height: 4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(GamesChessText.clockAccessibility(remaining))
    }
}

#endif
