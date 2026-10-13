import CheckCore
import Foundation
#if os(iOS)
import SwiftUI
#endif

// 체스 **순위표 절**(폰) — 승점(승 − 패) 순위와 그 안의 내 자리.
//
// ── 왜 제자리 절인가 ──
// 새 라우트가 아니라 로비 안의 절이다: 코어 `loadRanking` 은 `phase == .lobby` 와 창 표시를 요구하고
// (`ChessStoreRanking.swift:83` · `canPollSpectatorFeatures`), 폰에서 자식 화면을 push 하면 체스 화면의
// `onDisappear` → `windowDidHide()` 로 폴링이 죽는다. 값이 갱신되는 자리는 로비뿐이다(오목에서 실증됐다).
//
// ── 이 파일이 두 겹인 까닭 ──
// 아래 **판정**(`GamesChessRankingPlan`)은 `#if os(iOS)` **밖**에 있다. 폰 뷰는 맥 스위트가 한 줄도 못 보므로
// (저장소 메모 '폰 뷰는 맥 스위트가 못 본다') 뷰 안에 판정을 묻어 두면 "0판인 사람이 끼었다"·"행이 있는데
// 곧 열려요가 떴다" 를 재는 그물을 걸 자리가 없다 — 오목이 그래서 소스 글자만 재고 있었고, 그 그물로는
// 게이트를 되돌려도 613건이 전부 초록이었다. 판정을 떼어 두면 맥 `swift test` 가 **결과를 값으로** 잰다.
// 그림(뷰)은 판정을 그대로 받아 그리기만 한다.
//
// ── 실패는 이 절 안에서만 말한다 ──
// 순위 조회 실패를 안내줄(notice)로 올리지 않는다 — 코어가 일부러 안 한다(`ChessStoreRanking.swift` 머리말:
// "순위 조회 실패는 **안내줄(notice)로 새지 않는다**"). 대국 상태줄을 가린다.

/// 순위 절의 **순수 판정**(맥에서 돈다). 색·글꼴은 고르지 않는다 — 뷰가 고른다.
@MainActor
enum GamesChessRankingPlan {
    /// 절이 그릴 것. **이 순서로** 본다(아래 `content` 머리말).
    enum Content: Equatable, Sendable {
        /// 행을 들고 있다 — 행을 그린다.
        case rows
        /// 서버에 `chess_ranking` 이 아직 없다(PGRST202) — "순위는 곧 열려요".
        case soon
        /// 받았고 비어 있다.
        case empty
        /// 한 번도 못 받았고 마지막 조회가 실패했다.
        case failed
        /// 아직 모른다 — 절을 통째로 접는다.
        case loading
    }

    /// 접힌 줄 수 · 펼쳤을 때의 상한. **숫자를 다시 적지 않는다** — 문구 레인의 표가 한 출처다
    /// (`GamesChessText.rankCollapsedRows` · `rankRowLimit`).
    static var collapsedRows: Int { GamesChessText.rankCollapsedRows }
    static var rowLimit: Int { GamesChessText.rankRowLimit }

    /// ★ **0판인 사람은 안 낀다.** 서버 `chess_ranking` 이 이미 걸러 주지만(전적 표에 행이 없다) 그 약속을
    /// 화면이 다시 지킨다 — 0승 0패 0무 줄은 순위표에 아무 정보도 주지 않고, 전적 컷 직후에는 그런 줄이
    /// 사용자 수만큼 생길 수 있다. 서버가 한 번 느슨해지면 순위표가 통째로 0판 줄로 덮인다.
    static func playable(_ entries: [ChessRankEntry]) -> [ChessRankEntry] {
        entries.filter { $0.wins + $0.losses + $0.draws > 0 }
    }

    /// 들고 있는 순위 행. **재정렬하지 않는다** — 서버 순서가 권위다(`ChessRankingOrder` 는 판정용이지
    /// 정렬기가 아니다 · `ChessStoreRanking.swift` 머리말 "정렬은 서버가 한다"). 거르고 자르기만 한다.
    static func held(_ store: ChessStore) -> [ChessRankEntry] {
        playable(store.ranking?.entries ?? [])
    }

    /// 지금 그릴 행(접힘 반영).
    static func visible(_ store: ChessStore, isExpanded: Bool) -> [ChessRankEntry] {
        Array(held(store).prefix(isExpanded ? rowLimit : collapsedRows))
    }

    /// [전체 보기] 줄이 말하는 전체 수(상한까지).
    static func total(_ store: ChessStore) -> Int { min(held(store).count, rowLimit) }

    /// [전체 보기]/[접기] 줄을 두는가.
    static func showsToggle(_ store: ChessStore) -> Bool { total(store) > collapsedRows }

    /// ★ **분기 순서**: 행 → 준비 중 → 빈·실패·로딩.
    ///
    /// ① **행 갈래가 맨 앞이다.** `rankingUnavailable` 을 먼저 보면, 순위 조회는 **성공**해 행을 들고 있는데
    ///   `chess_watch` 만 PGRST202 인 창에서 코어가 그 깃발을 세우므로(`ChessStoreWatch.swift:320` — 순위를
    ///   한 번도 못 받았을 때만이지만, 그 창을 지나며 세워진 깃발은 다음 성공까지 남는다) 받아 둔 행을 통째로
    ///   버리고 "곧 열려요"를 말한다. 폰 공용 규칙 위반이다(`Components/MobileComponentRules.swift`:
    ///   "절이 이미 줄을 들고 있으면 실패를 조용히 둔다 — 지난 값을 지우지 않는다"). 오목에서 이 순서가
    ///   뒤집혀 있어 수리했다.
    /// ② **준비 중은 `placeholder` 보다 먼저** 본다. 코어가 PGRST202 창을 "받은 것"으로 세기 때문에
    ///   (`ChessStoreRanking.swift:95-101` — `rankingUnavailable = true` · `rankingLoadFailed = false` ·
    ///   `hasLoadedRanking = true`) `placeholder` 는 `.failed` 가 아니라 **`.empty`** 로 떨어진다. 이 확인을
    ///   뒤로 미루면 "곧 열려요" 대신 "아직 전적이 없어요"가 뜬다(맥 `ChessRankColumn.emptyText` 도 이 순서다).
    static func content(_ store: ChessStore) -> Content {
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

    /// 목록 **밖**의 내 순위. ★ 접힌 상태에서 내가 5위 밖이면 이 줄이 그 정보를 맡으므로 **행 갈래와 무관하게**
    /// 늘 본다(목록에 내 행이 있어도 중복은 해롭지 않다 — 없는 쪽이 사고다).
    ///
    /// 값은 `myRankConsistentWithRecord` 하나에서만 온다. nil 이면 이 줄을 그리지 않는다: 순위 응답의 전적이
    /// 로비 전적과 어긋난다는 뜻이고(한쪽이 늦었다), 섞으면 "8승 3패 · 승점 +4" 같은 자기모순 문장이 뜬다.
    static func myRank(_ store: ChessStore) -> ChessMyRank? { store.myRankConsistentWithRecord }

    /// 머리 오른쪽 캡션. **한 번도 못 받았으면 아무것도 말하지 않는다** — 컷을 모르는데 "전체 기간"은 거짓이다.
    static func sinceCaption(_ store: ChessStore) -> String? {
        guard let ranking = store.ranking else { return nil }
        return ranking.recordSince.map(GamesChessText.rankSince) ?? GamesChessText.rankWholePeriod
    }
}

#if os(iOS)

/// 체스 로비 **순위표 절**. 상태는 전부 코어 `ChessStore` 가 들고, 판정은 `GamesChessRankingPlan` 이 한다.
///
/// **이 뷰는 타이머를 만들지 않는다** — 순위 조회 주기는 스토어 폴링 루프가 돌고, 이 절에는 초 단위로 변하는
/// 글자가 없다. [전체 보기] 접힘만 제 `@State` 다(공개 자리 API 가 `store:` 하나라 바인딩을 받지 않는다 —
/// 화면 루트가 들어 주던 오목과 다른 점이고, 로비 뷰가 해제되면 접힘이 돌아온다).
struct GamesChessRankingSection: View {
    let store: ChessStore

    @State private var isExpanded = false

    var body: some View {
        // 절을 제 스택으로 감싼다(간격 0 · 조각마다 자기 여백 — 로비 스택과 같은 규약).
        VStack(alignment: .leading, spacing: 0) {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        // 분기 순서의 근거는 `GamesChessRankingPlan.content` 머리말에 있다. 뷰는 **다시 판정하지 않는다.**
        switch GamesChessRankingPlan.content(store) {
        case .rows:
            rows
        case .soon:
            header
            InsetGroup { messageRow(GamesChessText.rankingUnavailable, hint: nil) }
        case .empty:
            header
            InsetGroup { messageRow(GamesChessText.noRanking, hint: GamesChessText.noRankingHint) }
        case .failed:
            header
            InsetGroup {
                GroupRow(divider: .none) {
                    // 세로 한 칸: 실패 한 줄 + [다시 시도] 아래, **왜 다시 시도가 안 먹을 수도 있는지** 한 줄.
                    VStack(alignment: .leading, spacing: MobileTheme.space2) {
                        LoadFailureRow(GamesChessText.rankingLoadFailed) {
                            Task { await store.loadRanking() }
                        }
                        Text(GamesChessText.rankingLoadFailedHint)
                            .font(MobileTheme.rowSubtitle)
                            .foregroundStyle(MobileTheme.label2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case .loading:
            // 절을 통째로 접는다 — 첫 조회 전에 머리만 번쩍이지 않게(로비 "지금 대결 중"과 같은 규약).
            EmptyView()
        }
    }

    // MARK: 머리 · 캡션

    private var header: some View {
        SectionHeader(GamesChessText.rankTitle, trailing: headerTrailing, padded: true)
    }

    private var headerTrailing: SectionHeader.Trailing {
        guard let caption = GamesChessRankingPlan.sinceCaption(store) else { return .none }
        return .text(caption)
    }

    /// 절 아래 작은 두 줄: 승점의 뜻 + **0판인 사람은 안 낀다**는 사실(`playable` 이 실제로 거르는 그것 —
    /// 빈 순위·짧은 목록을 사고로 읽지 않게 하는 줄이다).
    private var caption: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(GamesChessText.rankCaption)
                .fixedSize(horizontal: false, vertical: true)
            Text(GamesChessText.rankZeroGamesNote)
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
        let visible = GamesChessRankingPlan.visible(store, isExpanded: isExpanded)
        let showsToggle = GamesChessRankingPlan.showsToggle(store)
        header
        myRankRow
        InsetGroup {
            // 내 행은 `myUserID` 로 고른다(순위 응답의 `me` 와 무관하게 **행 자체가 나인가** — 맥과 같은 판정).
            let mine = store.myUserID
            ForEach(Array(visible.enumerated()), id: \.element.id) { index, entry in
                GamesChessRankRow(
                    entry: entry,
                    isMe: entry.id == mine,
                    // [전체 보기] 줄이 뒤에 서면 마지막 행도 구분선을 긋는다.
                    isLast: !showsToggle && index == visible.count - 1
                )
            }
            if showsToggle { toggleRow(total: GamesChessRankingPlan.total(store)) }
        }
        caption
    }

    /// 목록 밖의 내 순위 한 줄. 판정은 `GamesChessRankingPlan.myRank` 하나다.
    @ViewBuilder
    private var myRankRow: some View {
        if let mine = GamesChessRankingPlan.myRank(store) {
            InsetGroup {
                GroupRow(divider: .none, isHighlighted: true) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(GamesChessText.myRankTitle)
                            .font(MobileTheme.rowSubtitle)
                            .foregroundStyle(MobileTheme.label2)
                        Text(GamesChessText.myRankLine(mine))
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
            // 글자 버튼은 제 좌우 여백(13)을 들고 있어, 카드 여백에서 그만큼 빼야 글자가 위 행의 순위 원과 같은 x 에 선다.
            padding: EdgeInsets(top: 2, leading: MobileTheme.cardPadding - 13, bottom: 2, trailing: MobileTheme.cardPadding)
        ) {
            AingButton(
                isExpanded ? GamesChessText.rankCollapse : GamesChessText.rankSeeAll(total: total),
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

/// 순위 한 줄 — **순위 탭·미니게임과 같은 공용 부품**(`RankRow`·`RankRowBody`·`RankBadge`·`PersonName`):
/// 순위 원 24 · 얼굴 30 · 이름(+ 센터) · 오른쪽 승점과 승·패·무. 내 행은 파랑 6% 칠 + '나' 칩.
///
/// ★ **일곱 칸을 다 그린다**(순위 · 아바타 · 이름 · 승점 · 승 · 패 · 무). 승점만 띄우는 것은 사용자가 금지했다.
/// 동률은 서버가 같은 rank 를 주고 다음 숫자를 건너뛴다(4,4,6) — 받은 숫자를 그대로 그린다.
private struct GamesChessRankRow: View {
    let entry: ChessRankEntry
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
                    // 큰 글자: 숫자를 이름 아래로 쌓는다. 가로로 몰면 이름이 한 글자씩 꺾이고, `.fixedSize()` 두
                    // 조각이 한 HStack 에 있으면 스택이 제안 폭을 무시한 이상 폭을 보고해 `InsetGroup` 의
                    // `clipShape` 가 **뒤에 선 전적을 자른다** — 사용자가 금지한 '승점만' 화면이 큰 글자에서만
                    // 되살아난다(오목 절의 CoreText 실측: AX4 부터 두 꼴 다 카드 안쪽 폭 256 을 넘는다).
                    stacked
                } else {
                    // 보통 글자에서도 **320pt 좁은 기기**가 있다(Display Zoom). 들어가면 한 줄, 안 들어가면
                    // 같은 쌓은 꼴로 접는다 — 접는 방법을 한 벌로 둬서 두 갈래가 싸우지 않는다.
                    ViewThatFits(in: .horizontal) {
                        inline
                        stacked
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(GamesChessText.rankRowAccessibility(entry, isMe: isMe)))
    }

    /// 한 줄 꼴: 이름 · 오른쪽에 승점과 전적.
    private var inline: some View {
        HStack(alignment: .center, spacing: 8) {
            nameLine
            Spacer(minLength: 4)
            // 오른쪽 숫자 칸을 **통째로** 가로 고정한다(조각마다 걸면 바깥이 풀 수 없다). 폭이 모자랄 때
            // 숫자가 아니라 이름이 먼저 줄어든다(`PersonName` 이 `ViewThatFits` 로 스스로 접는다).
            VStack(alignment: .trailing, spacing: 1) {
                pointsText
                recordText
            }
            .fixedSize()
        }
    }

    /// 쌓은 꼴: 이름 아래 승점·전적. 전적은 그래도 모자라면 **두 줄로 접힌다**(잘리지 않는다).
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

    /// 얼굴은 **그 행의 `entry.user`** 로 그린다 — `PersonAvatar` 가 `userID` 로 환경값에서 착용 캐릭터를 찾는다.
    ///
    /// ★ **`characterHint:` 로 행이 받은 착용값도 함께 넘긴다.** 표(`app_user_characters()`)는 한 벌이지만
    ///   늘 차 있지는 않다(로그인 직후 한 번 + 스로틀 조회) — 그 조회가 아직 안 온 세션에서는 표가 비어
    ///   **순위표 전원이 이니셜**이 된다(오목에서 빠뜨려 캐릭터가 기본 그림으로 떴다). 순위 행은 저마다
    ///   자기 `characterID` 를 들고 오므로 버릴 이유가 없고, 판정은 코어 한 곳이다
    ///   (`AppUserCharacterDirectory.avatar(for:photoURL:characterHint:)`).
    ///
    /// 상태 점은 달지 않는다 — 순위 행의 `user` 는 코어 경계(`user(from:)`)에서 근무·가능·대국 중이 전부
    /// false 라, 그 값으로 점을 달면 **전원이 "근무 안 함"** 이 된다(순위판은 근무 상태판이 아니다).
    private var face: some View {
        PersonAvatar(name: entry.user.displayName, colorSeed: entry.user.id,
                     url: entry.user.avatarURL.flatMap(URL.init(string:)), userID: entry.user.id, size: 30,
                     characterHint: entry.user.characterID)
    }

    private var nameLine: some View {
        PersonName(entry.user.displayName, center: CenterLabel.serverValue(forDisplay: entry.user.center),
                   isMe: isMe, onTint: true)
    }

    /// 승점은 **부호를 보이게**("+4" · "−2" · "0"). 색으로 말하지 않는다 — 폰 토큰 규약에서 초록·앰버는
    /// 근무 중·연결 끊김의 뜻이라 승점에 쓰면 그 자리에서 뜻이 갈린다(맥은 초록·앰버를 쓴다).
    ///
    /// ★ 가로 고정은 이 조각이 들지 않는다 — **쓰는 자리에서** 건다(큰 글자 가지가 접을 수 있어야 한다).
    private var pointsText: some View {
        Text(GamesChessText.points(entry.points))
            .font(MobileTheme.number(.callout, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(MobileTheme.label)
    }

    private var recordText: some View {
        Text(GamesChessText.record(wins: entry.wins, losses: entry.losses, draws: entry.draws))
            .font(MobileTheme.rowSubtitle)
            .monospacedDigit()
            .foregroundStyle(MobileTheme.label2)
    }
}
#endif
