import CheckCore
import Foundation
#if os(iOS)
import SwiftUI
#endif

// 1:1 테트리스 **순위 탭**(폰 · D11) — 승점(승 − 패) 순위와 그 안의 내 자리. 0판 제외 · 최대 100행.
//
// ── 왜 로비 안 탭인가 ──
// 새 라우트가 아니라 로비 안의 탭이다. 코어 `loadRanking` 은 `rankingEnabled` 와 세션을 요구하고, 그것을 거는
// 자리들이 전부 **창이 보이고 단계가 로비일 때**다(`TetrisDuelStore.windowDidShow` 의 두 분기 ·
// `pollTick` 의 `phase == .lobby` 가드). 폰에서 자식 화면을 push 하면 테트리스 화면의 `onDisappear` →
// `tetrisScreenDidDisappear()` → `windowDidHide()` 로 폴링이 죽어 **값이 갱신되는 자리가 사라진다**
// (오목·체스 두 파일 머리말에 같은 실측이 있다).
//
// ── 이 파일이 두 겹인 까닭 ──
// 아래 **판정**(`GamesTetrisDuelRankingPlan`)은 `#if os(iOS)` **밖**에 있다. 폰 뷰는 맥 스위트가 한 줄도 못 보니
// 뷰 안에 판정을 묻으면 "0판인 사람이 끼었다"·"행이 있는데 곧 열려요가 떴다"·"판 중에 순위 조회가 나갔다" 를
// 재는 그물을 걸 자리가 없다. 체스 순위 절(`GamesChessRanking.swift`)이 같은 이유로 같은 모양이다.
//
// ── 실패는 이 탭 안에서만 말한다 ──
// 순위 조회 실패를 안내줄(notice)로 올리지 않는다 — 코어가 일부러 안 한다(`TetrisDuelStoreGame.loadRanking`
// 머리말: "실패는 안내줄로 새지 않는다 — 판 상태줄을 가린다").

/// 순위 탭의 **순수 판정**(맥에서 돈다). 색·글꼴은 고르지 않는다 — 뷰가 고른다.
@MainActor
package enum GamesTetrisDuelRankingPlan {
    /// 탭이 그릴 것. **이 순서로** 본다(아래 `content` 머리말).
    package enum Content: Equatable, Sendable {
        case rows
        /// 서버에 `tetris_ranking` 이 아직 없다(PGRST202) — "순위는 곧 열려요".
        case soon
        case empty
        case failed
        /// 아직 모른다 — 불러오는 중 한 줄.
        case loading
    }

    /// 접힌 줄 수 · 펼쳤을 때의 상한. **숫자를 다시 적지 않는다** — 문구 표가 한 출처다.
    package static var collapsedRows: Int { TetrisPhoneText.rankCollapsedRows }
    package static var rowLimit: Int { TetrisPhoneText.rankRowLimit }

    /// ★ **0판인 사람은 안 낀다**(D11). 서버 `tetris_ranking` 이 이미 걸러 주지만 그 약속을 화면이 다시 지킨다 —
    /// 0승 0패 0무 줄은 순위표에 아무 정보도 주지 않고, 서버가 한 번 느슨해지면 순위표가 통째로 그 줄로 덮인다.
    /// (`no_show` 무승부는 서버가 전적에서 뺀다 — D11. 그래서 수락만 하고 안 들어온 판은 여기 닿지 않는다.)
    package static func playable(_ entries: [TetrisDuelRankEntry]) -> [TetrisDuelRankEntry] {
        entries.filter { $0.wins + $0.losses + $0.draws > 0 }
    }

    /// 들고 있는 순위 행. **재정렬하지 않는다** — 서버 순서가 권위다(코어 `rankingBoard(from:)` 가 "행 순서는
    /// 입력 그대로" 라고 못 박았다). 거르고 자르기만 한다.
    package static func held(_ store: TetrisDuelStore) -> [TetrisDuelRankEntry] {
        playable(store.ranking?.entries ?? [])
    }

    package static func visible(_ store: TetrisDuelStore, isExpanded: Bool) -> [TetrisDuelRankEntry] {
        Array(held(store).prefix(isExpanded ? rowLimit : collapsedRows))
    }

    package static func total(_ store: TetrisDuelStore) -> Int { min(held(store).count, rowLimit) }

    package static func showsToggle(_ store: TetrisDuelStore) -> Bool { total(store) > collapsedRows }

    /// ★ **분기 순서**: 행 → 준비 중 → 빈·실패·로딩.
    ///
    /// ① **행 갈래가 맨 앞이다.** `rankingUnavailable` 을 먼저 보면, 순위를 받아 둔 채 그 깃발이 남아 있는 창에서
    ///   들고 있는 행을 통째로 버리고 "곧 열려요"를 말한다 — 폰 공용 규칙 위반이다(`MobileComponentRules`:
    ///   "절이 이미 줄을 들고 있으면 실패를 조용히 둔다").
    /// ② **준비 중(`soon`)은 `placeholder` 보다 먼저** 본다. 코어가 PGRST202 창을 "받은 것"으로 세기 때문에
    ///   (`loadRanking` 의 `isSchemaMissing` 갈래가 `hasLoadedRanking = true` · `rankingLoadFailed = false` 로
    ///   적는다) `placeholder` 는 `.failed` 가 아니라 **`.empty`** 로 떨어진다. 이 확인을 뒤로 미루면
    ///   "순위는 곧 열려요" 대신 "아직 순위가 없어요"가 뜬다(체스·맥도 이 순서다).
    package static func content(_ store: TetrisDuelStore) -> Content {
        if !held(store).isEmpty { return .rows }
        if store.rankingUnavailable { return .soon }
        switch MobileLoadKnowledge.placeholder(hasRows: false, hasLoaded: store.hasLoadedRanking,
                                               lastFailed: store.rankingLoadFailed) {
        case .rows:
            // 닿지 않는다 — `hasRows: false` 로 계산했다. 사실이 아닌 값을 꾸미지 않고 로딩으로 접는다.
            return .loading
        case .empty: return .empty
        case .failed: return .failed
        case .loading: return .loading
        }
    }

    /// 목록 **밖**의 내 순위.
    ///
    /// ★ 순위 응답의 `me` 와 **로비 전적이 어긋나면 그리지 않는다**(한쪽이 늦었다는 뜻이다). 섞으면
    ///   "8승 3패 · 승점 +4" 같은 자기모순 문장이 뜬다 — 체스가 `myRankConsistentWithRecord` 로 코어에 둔 판정을
    ///   테트리스 코어는 안 들고 있어(확인했다 — `TetrisDuelStore` 에 그 이름이 없다) 이 자리에서 본다.
    ///   전적을 **아직 모르면**(로비 응답 전) 막지 않는다: 그때는 어긋남을 말할 근거가 없고, 순위 응답만으로도
    ///   내 자리는 사실이다.
    package static func myRank(_ store: TetrisDuelStore) -> TetrisDuelMyRank? {
        guard let mine = store.ranking?.me else { return nil }
        guard let record = store.record else { return mine }
        guard record.wins == mine.wins, record.losses == mine.losses, record.draws == mine.draws else { return nil }
        return mine
    }

    /// 머리 오른쪽 캡션. **한 번도 못 받았으면 아무것도 말하지 않는다** — 컷을 모르는데 "전체 기간"은 거짓이다.
    package static func sinceCaption(_ store: TetrisDuelStore) -> String? {
        guard let ranking = store.ranking else { return nil }
        return ranking.recordSince.map(TetrisPhoneText.rankSince) ?? TetrisPhoneText.rankWholePeriod
    }

    /// 순위 탭을 고른 그 순간의 조회(60초 스로틀은 코어가 쥔다 — `refreshRankingIfStale`).
    ///
    /// ★★ **단계 가드가 이 함수의 알맹이다.** 판이 흐르는 동안 순위를 당기면 ① 판 보고와 같은 연결을 두고 다투고
    ///   ② 코어 폴링도 `phase == .lobby` 에서만 당기므로 두 자리가 갈린다. 그리고 순위 **탭이 아닐 때는** 쏘지
    ///   않는다 — 상대 고르기 탭에서 1분마다 안 보는 표를 긁는 꼴이 된다.
    ///   값으로 재는 자리: `GamesTetrisLobbyTests` 가 `tetris_ranking` 요청 **건수**를 센다.
    package static func shouldRefresh(_ store: TetrisDuelStore, tab: GamesTetrisLobbyTab) -> Bool {
        store.rankingEnabled && tab == .ranking && store.phase == .lobby
    }

    package static func refreshIfNeeded(_ store: TetrisDuelStore, tab: GamesTetrisLobbyTab) {
        guard shouldRefresh(store, tab: tab) else { return }
        store.refreshRankingIfStale()
    }
}

#if os(iOS)

/// 1:1 테트리스 로비 **순위 탭**. 상태는 전부 코어 `TetrisDuelStore` 가 들고, 판정은 `GamesTetrisDuelRankingPlan`
/// 이 한다. **이 뷰는 타이머를 만들지 않는다** — 순위 주기는 스토어 폴링 루프가 돌고, 여기엔 초 단위로 변하는
/// 글자가 없다.
struct GamesTetrisDuelRankingSection: View {
    let store: TetrisDuelStore
    /// 내 행을 고르는 값. **화면이 넘긴다**(폰 세션 스토어 — `GamesMiniGameScreen` 과 같은 자리)
    /// — 코어 host 를 뒤지지 않는 까닭은 그 쪽이 약한 참조라 로그아웃 틈에 nil 이 되고, 그때 내 행 강조만
    /// 조용히 사라지는 갈래가 생기기 때문이다.
    let myUserID: String?

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        // 탭을 고른 그 순간 말고 **탭이 선 채로 화면이 다시 뜬 길**도 있다(앱을 나갔다 돌아옴 · 판이 끝나 로비로).
        // 판정은 같은 한 곳이다(뷰가 단계·스로틀을 다시 적지 않는다).
        .onAppear { GamesTetrisDuelRankingPlan.refreshIfNeeded(store, tab: .ranking) }
    }

    @ViewBuilder
    private var content: some View {
        // 분기 순서의 근거는 `GamesTetrisDuelRankingPlan.content` 머리말에 있다. 뷰는 **다시 판정하지 않는다.**
        switch GamesTetrisDuelRankingPlan.content(store) {
        case .rows:
            rows
        case .soon:
            header
            InsetGroup { messageRow(TetrisPhoneText.rankSoon, hint: nil) }
        case .empty:
            header
            InsetGroup { messageRow(TetrisPhoneText.rankEmpty, hint: TetrisPhoneText.rankEmptyHint) }
        case .failed:
            header
            InsetGroup {
                GroupRow(divider: .none) {
                    // 세로 한 칸: 실패 한 줄 + [다시 시도] 아래, **왜 다시 시도가 안 먹을 수도 있는지** 한 줄.
                    VStack(alignment: .leading, spacing: MobileTheme.space2) {
                        LoadFailureRow(TetrisPhoneText.rankLoadFailed) {
                            Task { await store.loadRanking() }
                        }
                        Text(TetrisPhoneText.rankLoadFailedHint)
                            .font(MobileTheme.rowSubtitle)
                            .foregroundStyle(MobileTheme.label2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case .loading:
            // ★ 체스 순위 절과 **다르게** 접지 않는다: 저쪽은 로비 맨 아래 절이라 접어도 위에 볼 것이 남지만,
            //   이쪽은 **탭 하나가 통째로 이 뷰**다 — 접으면 순위 탭을 눌렀는데 빈 화면이 선다.
            header
            InsetGroup {
                GroupRow(divider: .none) {
                    LoadingRow(TetrisPhoneText.rankLoading)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: 머리 · 캡션

    private var header: some View {
        SectionHeader(TetrisPhoneText.rankTitle, trailing: headerTrailing, padded: true)
    }

    private var headerTrailing: SectionHeader.Trailing {
        guard let caption = GamesTetrisDuelRankingPlan.sinceCaption(store) else { return .none }
        return .text(caption)
    }

    /// 탭 아래 작은 두 줄: 승점의 뜻 + **0판인 사람은 안 낀다**는 사실(`playable` 이 실제로 거르는 그것 —
    /// 빈 순위·짧은 목록을 사고로 읽지 않게 하는 줄이다).
    private var caption: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(TetrisPhoneText.rankCaption)
                .fixedSize(horizontal: false, vertical: true)
            Text(TetrisPhoneText.rankZeroGamesNote)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(MobileTheme.rowSubtitle)
        .foregroundStyle(MobileTheme.label2)
        .padding(.horizontal, MobileTheme.titleMargin - MobileTheme.sideMargin)
        .padding(.top, MobileTheme.space2)
        .accessibilityElement(children: .combine)
    }

    // MARK: 목록

    @ViewBuilder
    private var rows: some View {
        let visible = GamesTetrisDuelRankingPlan.visible(store, isExpanded: isExpanded)
        let showsToggle = GamesTetrisDuelRankingPlan.showsToggle(store)
        header
        myRankRow
        InsetGroup {
            // 내 행은 순위 응답의 `me` 와 무관하게 **행 자체가 나인가**로 고른다(맥·체스와 같은 판정).
            let mine = myUserID
            ForEach(Array(visible.enumerated()), id: \.element.id) { index, entry in
                GamesTetrisRankRow(
                    entry: entry,
                    isMe: entry.id == mine,
                    // [전체 보기] 줄이 뒤에 서면 마지막 행도 구분선을 긋는다.
                    isLast: !showsToggle && index == visible.count - 1
                )
            }
            if showsToggle { toggleRow(total: GamesTetrisDuelRankingPlan.total(store)) }
        }
        caption
    }

    /// 목록 밖의 내 순위 한 줄. 판정은 `GamesTetrisDuelRankingPlan.myRank` 하나다.
    ///
    /// ★ 접힌 상태에서 내가 5위 밖이면 이 줄이 그 정보를 맡으므로 **행 갈래와 무관하게** 늘 본다.
    @ViewBuilder
    private var myRankRow: some View {
        if let mine = GamesTetrisDuelRankingPlan.myRank(store) {
            InsetGroup {
                GroupRow(divider: .none, isHighlighted: true) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(TetrisPhoneText.myRankTitle)
                            .font(MobileTheme.rowSubtitle)
                            .foregroundStyle(MobileTheme.label2)
                        Text(TetrisPhoneText.myRankLine(mine))
                            .font(MobileTheme.rowTitle)
                            .monospacedDigit()
                            .foregroundStyle(MobileTheme.label)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
            .padding(.bottom, MobileTheme.rowSpacing)
        }
    }

    /// 그룹 맨 아래 [전체 보기] · [접기] — **제자리에서** 펴고 접는다(새 화면을 밀지 않는다 · 폴링이 죽는다).
    private func toggleRow(total: Int) -> some View {
        GroupRow(
            divider: .none,
            padding: EdgeInsets(top: 2, leading: MobileTheme.cardPadding - 13, bottom: 2, trailing: MobileTheme.cardPadding)
        ) {
            AingButton(
                isExpanded ? TetrisPhoneText.rankCollapse : TetrisPhoneText.rankSeeAll(total: total),
                systemImage: isExpanded ? "chevron.up" : "chevron.down",
                kind: .plain,
                size: .sm
            ) {
                isExpanded.toggle()
            }
            Spacer(minLength: 0)
        }
    }

    private func messageRow(_ text: String, hint: String?) -> some View {
        GroupRow(divider: .none) {
            VStack(alignment: .leading, spacing: 2) {
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(MobileTheme.label2)
                    .fixedSize(horizontal: false, vertical: true)
                if let hint {
                    Text(hint)
                        .font(MobileTheme.rowSubtitle)
                        .foregroundStyle(MobileTheme.label2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

/// 순위 한 줄 — **순위 탭·미니게임과 같은 공용 부품**(`RankRow`·`RankRowBody`): 순위 원 24 · 얼굴 30 · 이름 ·
/// 오른쪽 승점과 승·패·무. 내 행은 파랑 6% 칠 + '나' 칩.
///
/// ★ **여섯 칸을 다 그린다**(순위 · 아바타 · 이름 · 승점 · 승 · 패 · 무). 승점만 띄우는 것은 사용자가 금지했다.
/// 동률은 서버가 같은 rank 를 주고 다음 숫자를 건너뛴다(4,4,6) — 받은 숫자를 그대로 그린다.
private struct GamesTetrisRankRow: View {
    let entry: TetrisDuelRankEntry
    let isMe: Bool
    let isLast: Bool

    private let metrics = RankRowScaledMetrics()
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        RankRow(isMine: isMe, isLast: isLast, dividerInset: metrics.dividerInset(faceBase: 30),
                minHeight: 48, verticalPadding: (7, 7)) {
            RankRowBody(rank: entry.rank, alignment: .center) {
                face
            } content: {
                if typeSize.isAccessibilitySize {
                    // 큰 글자: 숫자를 이름 아래로 쌓는다(가로로 몰면 `InsetGroup` 의 clipShape 가 전적을 자른다 —
                    // 사용자가 금지한 '승점만' 화면이 큰 글자에서만 되살아난다. 체스 절의 CoreText 실측).
                    stacked
                } else {
                    // 보통 글자에서도 **320pt 좁은 기기**가 있다(Display Zoom). 들어가면 한 줄, 안 들어가면 쌓는다.
                    ViewThatFits(in: .horizontal) {
                        inline
                        stacked
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(TetrisPhoneText.rankRowAccessibility(entry, isMe: isMe)))
    }

    private var inline: some View {
        HStack(alignment: .center, spacing: 8) {
            nameLine
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 1) {
                pointsText
                recordText
            }
            .fixedSize()
        }
    }

    private var stacked: some View {
        VStack(alignment: .leading, spacing: 4) {
            nameLine
            VStack(alignment: .leading, spacing: 2) {
                pointsText
                recordText
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 얼굴은 **그 행의 `entry.user`** 로 그린다. ★ `characterHint:` 로 행이 받은 착용값도 함께 넘긴다 —
    /// 캐릭터 표가 아직 안 찬 세션에서는 그 힌트가 없으면 **순위표 전원이 이니셜**이 된다(오목에서 데인 자리).
    ///
    /// 상태 점은 달지 않는다 — 순위 행의 `user` 는 코어 경계(`user(from:)`)에서 근무·가능·대결 중이 전부 false 라
    /// 그 값으로 점을 달면 **전원이 "근무 안 함"** 이 된다(순위판은 근무 상태판이 아니다).
    private var face: some View {
        PersonAvatar(name: entry.user.displayName, colorSeed: entry.user.id,
                     url: entry.user.avatarURL.flatMap(URL.init(string:)), userID: entry.user.id, size: 30,
                     characterHint: entry.user.characterID)
    }

    private var nameLine: some View {
        PersonName(entry.user.displayName, isMe: isMe, onTint: true)
    }

    /// 승점은 **부호를 보이게**("+4" · "−2" · "0"). 색으로 말하지 않는다 — 폰 토큰 규약에서 초록·앰버는
    /// 근무 중·연결 끊김의 뜻이라 승점에 쓰면 그 자리에서 뜻이 갈린다.
    private var pointsText: some View {
        Text(TetrisPhoneText.points(entry.points))
            .font(MobileTheme.number(.callout, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(MobileTheme.label)
    }

    private var recordText: some View {
        Text(TetrisPhoneText.record(wins: entry.wins, losses: entry.losses, draws: entry.draws))
            .font(MobileTheme.rowSubtitle)
            .monospacedDigit()
            .foregroundStyle(MobileTheme.label2)
    }
}
#endif
