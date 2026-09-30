#if os(iOS)
import CheckCore
import SwiftUI

/// 오목 로비 맨 아래 **순위표 절**(0.3.41 폰) — 승점(승 − 패) 순위와 그 안의 내 자리.
///
/// 새 라우트가 아니라 로비 안의 절이다: 스토어의 `loadRanking` 은 `phase == .lobby` 와 창 표시를 요구하고, 폰에서 자식 화면을 push 하면
/// `GamesGomokuScreen.onDisappear` → `windowDidHide()` 로 폴링이 죽는다. 그래서 값이 갱신되는 자리는 로비뿐이다.
///
/// **이 뷰는 타이머를 만들지 않는다** — 순위 조회 주기는 스토어 폴링 루프가 돌고, 이 절에는 초 단위로 변하는 글자가 없다.
/// **순위 조회 실패를 안내줄(notice)로 올리지도 않는다** — 코어가 일부러 안 한다(`GomokuStoreRanking.swift` 머리말:
/// "순위 조회 실패는 **안내줄(notice)로 새지 않는다** — 대국 상태줄을 가리고, 기존 계약 테스트 다수가 notice == nil 을 단언한다").
/// 실패는 이 절 안에서만 말한다.
///
/// 네 상태 + 하나, **이 순서로** 본다: 목록(행을 들고 있으면 늘 이것) · 준비 중("순위는 곧 열려요") ·
/// 빈 목록("아직 전적이 없어요") · 실패 · 불러오는 중(아무것도 안 그린다). 순서의 근거는 `content` 머리말에 있다.
struct GamesGomokuRankingSection: View {
    let store: GamesStore
    /// [전체 보기]로 제자리 확장. 주인은 오목 화면(D)이다 — 절이 스스로 들고 있으면 로비를 다시 그릴 때 접힘이 되돌아간다.
    @Binding var isExpanded: Bool

    private var gomoku: GomokuStore { store.context.gomoku }

    var body: some View {
        // 절을 제 스택으로 감싼다(간격 0 · 조각마다 자기 여백 — 로비 스택과 같은 규약).
        VStack(alignment: .leading, spacing: 0) {
            content
        }
    }

    // MARK: 상태 분기

    /// 들고 있는 순위표 — 행이 **하나라도** 있으면 그것, 없으면 nil. `placeholder` 의 `hasRows` 와 같은 한 판정이다
    /// (두 곳에서 따로 세면 갈릴 수 있고, 아래 `content` 의 첫 갈래가 "행이 없으면 `placeholder != .rows`"에 기대고 있다).
    private var heldBoard: GomokuRankingBoard? {
        guard let ranking = gomoku.ranking, !ranking.entries.isEmpty else { return nil }
        return ranking
    }

    /// 빈·로딩·실패는 공용 규칙 한 곳에서(`MobileLoadKnowledge`). `hasRows` 는 `ranking?.entries`, `hasLoaded` 는
    /// `hasLoadedRanking`, `lastFailed` 는 `rankingLoadFailed`.
    ///
    /// 목록을 들고 있는데 마지막 조회가 실패했으면 `.rows` 다 — 들고 있던 목록을 그대로 그리고 **조용히 둔다**
    /// (`Components/MobileComponentRules.swift`: "절이 이미 줄을 들고 있으면 실패를 조용히 둔다 — 지난 값을 지우지 않는다").
    private var placeholder: MobileLoadKnowledge.Placeholder {
        MobileLoadKnowledge.placeholder(
            hasRows: heldBoard != nil,
            hasLoaded: gomoku.hasLoadedRanking,
            lastFailed: gomoku.rankingLoadFailed
        )
    }

    @ViewBuilder
    private var content: some View {
        // ★ **행 갈래가 맨 앞이다.** 전에는 `rankingUnavailable` 을 먼저 봤는데, 그 깃발을 세우는 자리가 둘이라 틀렸었다:
        // 순위 조회는 **성공**해 행을 들고 있는데 `gomoku_watch` 만 PGRST202 인 창에서도 코어가 이 깃발을 세운다
        // (`GomokuStoreWatch.swift:232` — 같은 마이그레이션이니 순위도 없을 것이라 보고 함께 접는다). 그러면 화면이
        // **받아서 들고 있던 순위 행을 통째로 버리고** "순위는 곧 열려요"를 말했다 — 머리엔 "10월 1일부터"(받은 적 있다는 증거)를
        // 남긴 채로. 폰 공용 규칙 위반이다(`Components/MobileComponentRules.swift`: "절이 이미 줄을 들고 있으면 실패를
        // 조용히 둔다 — 지난 값을 지우지 않는다"). 그 경로의 `noteWatchFailure` 는 `rankingLoadFailed` 도 `ranking` 도
        // 건드리지 않으므로 들고 있던 행이 온전하다 — 그대로 그리는 것이 맞다.
        if let board = heldBoard {
            rows(board)
        } else if gomoku.rankingUnavailable {
            // ⚠️ 준비 중(서버에 함수가 아직 없다)은 **`placeholder` 분기보다 먼저** 본다. 코어가 그 창을 "받은 것"으로 세기 때문에
            // (`GomokuStoreRanking.swift:39-44` — `rankingUnavailable = true` · `rankingLoadFailed = false` · `hasLoadedRanking = true`)
            // `placeholder` 는 `.failed` 가 아니라 **`.empty`** 로 떨어진다. 이 확인을 `.empty` 뒤로 미루면 "곧 열려요" 대신
            // "아직 전적이 없어요"가 뜬다(맥 `GomokuRankColumn.content` 도 이 확인이 `.empty` 보다 먼저다).
            // 차가운 창(한 번도 못 받았다)은 `ranking == nil` 이라 위 갈래를 안 타고 반드시 여기로 떨어진다.
            header
            InsetGroup {
                messageRow(GomokuPhoneText.rankingUnavailable, hint: nil)
            }
        } else {
            switch placeholder {
            case .rows:
                // 닿지 않는다 — `heldBoard == nil` 이면 `placeholder` 는 `hasRows: false` 로 계산돼 `.rows` 가 될 수 없다.
                EmptyView()
            case .empty:
                header
                InsetGroup {
                    messageRow(GomokuPhoneText.noRanking, hint: GomokuPhoneText.noRankingHint)
                }
            case .failed:
                header
                InsetGroup {
                    GroupRow(divider: .none) {
                        // 세로 한 칸: 실패 한 줄 + [다시 시도] 위에, **왜 다시 시도가 안 먹을 수도 있는지** 한 줄.
                        // 구버전 앱이면 서버가 `unsupported_client` 로 거절하고 `applyRanking` 이 같은 이 깃발로 접는다
                        // (`GomokuStoreRanking.swift:57`) — 스토어가 status 를 넘겨 주지 않아 **뷰는 두 원인을 가릴 수 없다.**
                        // 전에는 버튼만 두어 눌러도 같은 거절이 오는 경로에서 원인을 숨겼다. 단정하지 않고 나머지 원인을 같이 말한다.
                        VStack(alignment: .leading, spacing: MobileTheme.space2) {
                            LoadFailureRow(GomokuPhoneText.rankingLoadFailed) {
                                Task { await gomoku.loadRanking() }
                            }
                            Text(GomokuPhoneText.rankingLoadFailedHint)
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
    }

    // MARK: 머리 · 캡션

    private var header: some View {
        SectionHeader(GomokuPhoneText.rankTitle, trailing: headerTrailing, padded: true)
    }

    /// 머리 오른쪽 = 전적 기준 기간. **한 번도 못 받았으면 아무것도 말하지 않는다** — 컷을 모르는데 "전체 기간"은 거짓이다.
    private var headerTrailing: SectionHeader.Trailing {
        guard let ranking = gomoku.ranking else { return .none }
        return .text(ranking.recordSince.map(GomokuPhoneText.rankSince) ?? GomokuPhoneText.rankWholePeriod)
    }

    private var caption: some View {
        Text(GomokuPhoneText.rankCaption)
            .font(MobileTheme.rowSubtitle)
            .foregroundStyle(MobileTheme.label2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, MobileTheme.titleMargin - MobileTheme.sideMargin)
            .padding(.top, MobileTheme.space2)
    }

    // MARK: 목록

    @ViewBuilder
    private func rows(_ ranking: GomokuRankingBoard) -> some View {
        let total = min(ranking.entries.count, GomokuPhoneText.rankRowLimit)
        let visible = visibleEntries(ranking.entries)
        let showsToggle = total > GomokuPhoneText.rankCollapsedRows
        header
        myRankRow
        InsetGroup {
            // 내 행은 `myUserID` 로 고른다(순위 응답의 `me` 와 무관하게 **행 자체가 나인가** — 맥과 같은 판정).
            let mine = gomoku.myUserID
            ForEach(Array(visible.enumerated()), id: \.element.id) { index, entry in
                GamesGomokuRankRow(
                    entry: entry,
                    isMe: entry.id == mine,
                    // [전체 보기] 줄이 뒤에 서면 마지막 행도 구분선을 긋는다.
                    isLast: !showsToggle && index == visible.count - 1
                )
            }
            if showsToggle { toggleRow(total: total) }
        }
        caption
    }

    /// 보여 줄 행. **재정렬하지 않는다** — 서버 순서가 권위다(`GomokuRankingOrder` 는 판정용이지 정렬기가 아니다 ·
    /// `GomokuStoreRanking.swift` 머리말 "정렬은 서버가 한다"). 앞에서부터 자르기만 한다.
    private func visibleEntries(_ entries: [GomokuRankEntry]) -> [GomokuRankEntry] {
        Array(entries.prefix(isExpanded ? GomokuPhoneText.rankRowLimit : GomokuPhoneText.rankCollapsedRows))
    }

    /// 목록 **밖**의 내 순위 한 줄 — 접힌 상태에서 내가 5위 밖이면 이 줄이 그 정보를 맡는다.
    ///
    /// 값은 `myRankConsistentWithRecord` 하나에서만 온다. nil 이면 **이 줄을 그리지 않는다**: 순위 응답의 전적이 로비 전적과
    /// 어긋난다는 뜻이고(한쪽이 늦었다), 섞으면 "8승 3패 · 승점 +4" 같은 자기모순 문장이 뜬다
    /// (`GomokuStoreRanking.swift:68-74` — "순위 응답의 전적이 로비 전적과 같을 때만 순위를 내주고, 다르면 nil").
    /// 로비 전적은 이미 절 맨 위 두 칸 카드가 말하고 있으니, 빈 줄로 두어도 사용자가 전적을 잃지 않는다.
    @ViewBuilder
    private var myRankRow: some View {
        if let mine = gomoku.myRankConsistentWithRecord {
            InsetGroup {
                GroupRow(divider: .none, isHighlighted: true) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(GomokuPhoneText.myRankTitle)
                            .font(MobileTheme.rowSubtitle)
                            .foregroundStyle(MobileTheme.label2)
                        Text(GomokuPhoneText.myRankLine(mine))
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

    /// 그룹 맨 아래 [전체 보기] · [접기] — 제자리에서 펴고 접는다(새 화면을 밀지 않는다 · 폴링이 죽는다).
    private func toggleRow(total: Int) -> some View {
        GroupRow(
            divider: .none,
            // 글자 버튼은 제 좌우 여백(13)을 들고 있어, 카드 여백에서 그만큼 빼야 글자가 위 행의 순위 원과 같은 x 에 선다.
            padding: EdgeInsets(top: 2, leading: MobileTheme.cardPadding - 13, bottom: 2, trailing: MobileTheme.cardPadding)
        ) {
            AingButton(
                isExpanded ? GomokuPhoneText.rankCollapse : GomokuPhoneText.rankSeeAll(total: total),
                systemImage: isExpanded ? "chevron.up" : "chevron.down",
                kind: .plain,
                size: .sm
            ) {
                isExpanded.toggle()
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: 한 줄 문구

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
/// ★ **승점만 띄우지 않는다**(사용자 지시) — 승점 아래 "6승 2패 1무"를 늘 같이 그린다.
/// 동률은 서버가 같은 rank 를 주고 다음 숫자를 건너뛴다(4,4,6) — 받은 숫자를 그대로 그린다(1~3위 메달도 동률이면 둘 다 받는다).
private struct GamesGomokuRankRow: View {
    let entry: GomokuRankEntry
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
                    // 큰 글자: 숫자를 이름 아래로(가로로 몰면 이름이 한 글자씩 꺾이고 숫자가 잘린다 — 공용 행의 실측 근거와 같다).
                    VStack(alignment: .leading, spacing: 4) {
                        nameLine
                        // ★ 승점·전적은 큰 글자에서 **세로로 쌓고 접히게** 둔다. 전에는 이 자리가
                        // `HStack(spacing: 8) { pointsText; recordText }` 였고 두 조각이 각자 `.fixedSize()` 였다 —
                        // 가로 고정 둘이 한 HStack 에 있으면 스택이 제안 폭을 무시하고 이상 폭을 그대로 보고하고,
                        // `InsetGroup` 의 `clipShape`(`Components/InsetGroup.swift`)가 넘친 오른쪽을 **자른다**.
                        // 잘리는 쪽은 뒤에 선 **전적**이라, 사용자가 금지한 '승점만' 화면이 큰 글자에서만 되살아났다.
                        // 320pt 기기 · 카드 안쪽 폭 256(= 320 − sideMargin 16×2 − cardPadding 16×2) 기준 CoreText 실측:
                        // `승점 + 8 + "18승 5패 0무"` 가 Large 107.8 · AX2 204.8 · AX3 246.8 · **AX4 283.3** · **AX5 325.0** 이고
                        // 짧은 `"6승 2패 1무"` 쪽도 AX4 259.8 · AX5 297.9 다 — **AX4 부터 두 꼴 다 넘친다.**
                        // 세로로 쌓으면 각 줄이 256 을 온전히 쓰고, 그래도 남지 않는 AX5 의 전적은 아래 `fixedSize` 로
                        // **두 줄로 접힌다**(잘리지 않는다). 공용 관용구와 같은 손짓이다 — `PersonName.stacked` 도,
                        // 이 파일의 캡션·한 줄 문구도 큰 글자에서 이 꼴을 쓴다.
                        VStack(alignment: .leading, spacing: 2) {
                            pointsText
                            recordText
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    HStack(alignment: .center, spacing: 8) {
                        nameLine
                        Spacer(minLength: 4)
                        // 보통 글자에서는 오른쪽 숫자 칸을 **통째로** 가로 고정한다(조각마다 걸던 `.fixedSize()` 를 이 자리로
                        // 올렸다 — 조각 안에 두면 큰 글자 가지에서 바깥이 풀 수 없다). 폭이 모자랄 때 숫자가 아니라
                        // 이름이 먼저 줄어드는 것은 전과 같다(`PersonName` 이 `ViewThatFits` 로 스스로 접는다).
                        VStack(alignment: .trailing, spacing: 1) {
                            pointsText
                            recordText
                        }
                        .fixedSize()
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(GomokuPhoneText.rankRowAccessibility(entry, isMe: isMe)))
    }

    /// 얼굴은 **그 행의 `entry.user`** 로 그린다 — `PersonAvatar` 가 `userID` 로 환경값 `\.appUserCharacters` 에서 착용 캐릭터를 찾는다
    /// (사진 → 착용 캐릭터 → 이니셜 · `Components/PersonComponents.swift`: "`userID`: … 모든 호출부가 넘긴다 —
    /// 빠뜨리면 그 자리만 이니셜로 남는다").
    ///
    /// ★ **`characterHint:` 로 행이 받은 착용값도 함께 넘긴다.** 표(`app_user_characters()`)는 한 벌이지만 **늘 차 있지는 않다** —
    ///   로그인 직후 한 번 + 스로틀 조회라(`App/AppUserCharacterStore.swift`) 그 조회가 실패했거나 아직 안 온 세션에서는 표가 비어
    ///   **순위표 전원이 이니셜**이 된다. 순위 행은 저마다 자기 `characterID` 를 들고 오므로 버릴 이유가 없다. 힌트는 표가
    ///   이 사람을 모를 때만, 그리고 이 빌드가 초상을 아는 id 일 때만 쓰인다(판정은 코어 한 곳 —
    ///   `AppUserCharacterDirectory.avatar(for:photoURL:characterHint:)` · 맥 순위판과 같은 규칙).
    ///
    /// 내 행도 같은 길로 그린다(공용 `RankRowFace` 의 `me:` 초상 갈래를 쓰지 않는다): 순위 행의 출처는 **서버가 준 그 행**이고,
    /// 맥 순위판도 내 행을 남과 같은 부품으로 그린다. 상태 점도 달지 않는다 — 순위 행의 `user` 는 코어 경계(`user(from:)`)에서
    /// 근무·가능·대국 중이 전부 false 라, 그 값으로 점을 달면 **전원이 "근무 안 함"** 이 된다(순위판은 근무 상태판이 아니다).
    private var face: some View {
        PersonAvatar(name: entry.user.displayName, colorSeed: entry.user.id,
                     url: entry.user.avatarLink, userID: entry.user.id, size: 30,
                     characterHint: entry.user.characterID)
    }

    private var nameLine: some View {
        PersonName(entry.user.displayName, center: CenterLabel.serverValue(forDisplay: entry.user.center),
                   isMe: isMe, onTint: true)
    }

    /// 승점은 **부호를 보이게**("+4" · "−2" · "0"). 색으로 말하지 않는다 — 폰 토큰 규약에서 초록·앰버는 근무 중·연결 끊김의 뜻이라
    /// 승점에 쓰면 그 자리에서 뜻이 갈린다(맥은 초록·앰버를 쓴다 — 폰에서는 부호가 그 일을 한다).
    ///
    /// ★ **가로 고정(`.fixedSize()`)은 이 조각이 들지 않는다 — 쓰는 자리에서 건다.** 조각 안에 두면 바깥에서 풀 수 없어
    /// 큰 글자 가지가 이 줄을 접을 길이 없어지고, 카드가 오른쪽을 잘라 전적이 사라졌다(위 `body` 의 실측 주석).
    private var pointsText: some View {
        Text(GomokuPhoneText.signedPoints(entry.points))
            .font(MobileTheme.number(.callout, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(MobileTheme.label)
    }

    /// 가로 고정을 들지 않는 이유는 `pointsText` 와 같다 — 큰 글자에서 **접혀야** 하는 쪽이 바로 이 줄이다.
    private var recordText: some View {
        Text(GomokuPhoneText.record(wins: entry.wins, losses: entry.losses, draws: entry.draws))
            .font(MobileTheme.rowSubtitle)
            .monospacedDigit()
            .foregroundStyle(MobileTheme.label2)
    }
}
#endif
