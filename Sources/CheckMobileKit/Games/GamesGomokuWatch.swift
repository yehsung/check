#if os(iOS)
import CheckCore
import SwiftUI

/// 관전 화면(0.3.41) — 남의 진행 중인 판을 **읽기 전용**으로 본다. `phase == .lobby && spectating != nil` 이면
/// 로비 **대신** 이 화면이 선다(새 라우트가 아니다 — 자식 라우트를 push 하면 `GamesGomokuScreen.onDisappear` →
/// `windowDidHide()` 로 스토어 폴링이 죽어 값이 갱신되지 않는다).
///
/// 위에서부터: 받은 신청 · 보낸 신청(각각 있을 때만) · 안내 한 줄 · 흑 카드 · 판 · 백 카드 · 상태 상자 · 판돈·수·경과,
/// 아래 막대에 [나가기]. 신청 두 절의 순서는 로비와 같다(`GamesGomokuLobby.body`).
/// 대국 화면(`GamesGomokuMatch`)과 같은 문법이지만 **입력이 하나도 없다**:
/// - 판은 순수 그림(`GamesGomokuBoardCanvas`)이다 — 탭 제스처·미리보기 돌·금수 표시가 없다.
///   `GamesGomokuPlayBoard` 는 `match.myColor`·탭에 묶여 있어 쓰지 않는다.
/// - 차례 링은 `watch.deadline` 을 **직접** 센다 — 스토어 `remainingSeconds` 는 내 판만 알고, 관전 중 `match` 는 nil 이라
///   그 값을 쓰면 링이 0초로 빨갛게 선다.
/// - 채팅·관전자 수는 그리지 않는다(서버 응답에 그 키 자체가 없다).
/// - 끝난 판을 다시 조회하지 않는다 — 폴링은 스토어가 멈추고(`isFinished`) 결과는 [나가기] 전까지 이 값에 남는다.
///   3분이 지나면 서버가 `not_found` 를 주므로 **화면이 들고 있는 것이 결과의 유일한 출처**다.
struct GamesGomokuWatch: View {
    let store: GamesStore
    let watch: GomokuSpectateState

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var typeSize

    private var gomoku: GomokuStore { store.context.gomoku }

    var body: some View {
        GeometryReader { screen in
            watchBody(visible: screen.size)
        }
    }

    private func watchBody(visible: CGSize) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: MobileTheme.space2) {
                invites
                outgoing
                if let notice = gomoku.notice {
                    InlineNotice(text: notice, kind: .warning)
                }
                players(boardSide: boardSide(in: visible))
                GamesGomokuWatchStatusBox(store: store, watch: watch)
                info
                caption
            }
            .padding(.horizontal, MobileTheme.sideMargin)
            .padding(.top, MobileTheme.space2)
            .padding(.bottom, MobileTheme.space3)
        }
        .scrollBounceBehavior(.basedOnSize)
        .gamesDemoScrollAnchor(isDemo: store.context.isDemo)
        .safeAreaInset(edge: .bottom, spacing: 0) { leaveBar }
        // 로비와 같은 머리(제목은 화면 루트가 `navigationTitle` 로 세웠다 · 탭 막대는 그대로 보인다 — 관전은 로비 자리다).
        // 규칙 책은 남긴다(규칙을 모르는 채로 남의 판을 보는 자리다). [AI와 두기]는 로비 본문의 카드라 여기엔 없다 —
        // 맥도 관전 중에는 그 버튼을 숨긴다(AI 판이 서면 관전이 내려가 보던 판을 잃는다).
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                GamesGomokuRulesButton(store: gomoku)
            }
        }
    }

    // MARK: 받은 신청 · 보낸 신청 (관전 중에도 닿아야 한다)

    /// 관전 화면이 로비를 통째로 덮으므로, 여기 없으면 받은 신청의 60초를 거둘 길이 없다. 로비의 `.rows` 갈래와 **같은 부품**이다
    /// (`GamesGomokuInviteCard` — 수락·거절 문이 두 벌이 되지 않는다). 받은 신청이 없으면 아무것도 그리지 않는다:
    /// "없어요"는 할 일이 없는 줄이고, 관전 화면에서는 판이 밀려날 뿐이다.
    ///
    /// 개수 상한은 두지 않는다(맥 오른쪽 열은 세로 예산이 못 박혀 2장까지였다) — 폰은 스크롤이라 전부 그려도 거둘 길이 남는다.
    /// 보낸 신청은 바로 아래 `outgoing` 이 같은 규약으로 그린다.
    @ViewBuilder
    private var invites: some View {
        let pending = gomoku.pendingIncomingInvites
        if let first = pending.first {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                SectionHeader(GomokuPhoneText.incomingTitle,
                              trailing: .text(GomokuPhoneText.remainingPhrase(first.expiresAt.timeIntervalSince(store.context.clock.now()))),
                              padded: true)
            }
            InsetGroup {
                ForEach(Array(pending.enumerated()), id: \.element.id) { index, invite in
                    GamesGomokuInviteCard(store: store, invite: invite, showsCountdown: index > 0, isLast: index == pending.count - 1)
                }
            }
        }
    }

    /// 보낸 신청 한 줄 + [취소] — 로비의 같은 절(`GamesGomokuLobby.outgoing`)과 **같은 꼴**이다.
    ///
    /// 0.3.41 은 이 자리를 비워 두고 "그 행은 로비 파일 안에 private 이라 [나가기]로 돌아가는 길이 낫다"고 적었는데,
    /// 둘 다 더는 사실이 아니다: 그 행은 로비·관전이 같이 쓰도록 모듈에 공개됐고(`GamesGomokuOutgoingRow` 머리말),
    /// [나가기]는 **보던 판을 잃는** 길이라 "거둘 길"이 못 된다. 그래서 관전이 로비 자리에 서는 동안 루비를 걸어 둔
    /// 내 신청이 화면에서 통째로 사라져 TTL 60초를 거둘 길이 없었다(맥은 세로 예산 322pt 안에서까지 이 자리를 지켰다 —
    /// `GomokuPanel.swift` 의 2026-09-30 반증). 취소 문은 여기서 새로 만들지 않고 **그 부품을 그대로 부른다**.
    ///
    /// 보낸 신청이 없으면 **아무것도 그리지 않는다**(받은 신청과 같은 규약 — "없어요"는 할 일이 없는 줄이라 판만 밀어낸다).
    /// 그 행의 구분선은 `.none` 으로 못 박혀 있어 **한 줄만 든 `InsetGroup`** 안에 넣는다(로비와 같다).
    /// `GomokuStore.cancelChallenge()` 에는 단계 가드가 없어 관전 중에도 그대로 듣는다.
    @ViewBuilder
    private var outgoing: some View {
        if let invite = gomoku.outgoing {
            SectionHeader(GomokuPhoneText.outgoingTitle, padded: true)
            InsetGroup {
                GamesGomokuOutgoingRow(store: store, invite: invite)
            }
        }
    }

    // MARK: 두 사람 · 판

    /// 흑 카드 · 판 · 백 카드. **색을 모르는 동안에는 자리만 지킨다**(아래 `playerRow`).
    @ViewBuilder
    private func players(boardSide side: CGFloat) -> some View {
        if watch.hasServerState || !watch.faces.isEmpty {
            playerRow(.black, index: 0)
            board(side: side)
            playerRow(.white, index: 1)
        } else {
            // 씨앗도 응답도 없다(로비 30초 사이 목록에서 빠진 판을 눌렀다) — 두 사람을 하나도 모르니 빈 카드 두 장 대신
            // 한 줄이다(빈 카드는 "사람이 없는 판"으로 읽힌다).
            InsetGroup {
                GroupRow(divider: .none) {
                    // **끝난 판에는 로딩을 말하지 않는다.** 0.3.41 은 여기도 `LoadingRow` 여서, 아래 상태 상자가
                    // "대국이 끝났어요"를 말하는 동안 한 화면이 "아직 안 불러왔다"와 "이미 끝났다"를 동시에 주장했다.
                    // 끝난 판은 스토어가 폴링을 멈춰(`isFinished`) 더 올 것이 없으니 진행형·회전자는 거짓말이다.
                    if watch.isFinished {
                        Text(GomokuPhoneText.watchPlayersUnknown)
                            .font(.subheadline)
                            .foregroundStyle(MobileTheme.label2)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                            .accessibilityElement(children: .combine)
                    } else {
                        LoadingRow(GomokuPhoneText.watchLoading)
                    }
                }
            }
            board(side: side)
        }
    }

    /// 카드 한 자리. **흑·백을 추측하지 않는다**: `faces` 의 a/b 는 uuid 순서라 색이 아니므로, 서버가 `black`/`white` 를 말하기
    /// 전(`hasServerState == false`)에는 그 자리 얼굴만 그리고 **돌 배지도 차례 표시도 달지 않는다**. 안 그러면 절반의 판이 뒤집힌다.
    private func playerRow(_ color: GomokuColor, index: Int) -> some View {
        let known = watch.hasServerState
        let user: GomokuUser?
        let subtitle: String?
        if known {
            user = color == .black ? watch.black : watch.white
            // 부제는 **돌 색만**이다. 0.3.41 은 `playerSubtitle(color:isWorking:)` 으로 "흑 · 근무 중"을 세웠는데
            // 관전 응답에는 `is_working` 키가 없어 근무 안 하는 사람도 전원 "근무 중"이 됐다
            // (근거는 `GomokuPhoneText.watchPlayerSubtitle` 머리말).
            subtitle = user.map { _ in GomokuPhoneText.watchPlayerSubtitle(color: color) }
        } else {
            // 이 자리와 색의 관계를 아직 모른다 — `faces` 의 얼굴만 빌려 그리고 "불러오고 있어요"를 첫 자리에 한 번 둔다.
            user = watch.faces.indices.contains(index) ? watch.faces[index] : nil
            // 끝난 판이면 그 줄도 두지 않는다(위 `players` 의 else 갈래와 같은 이유 — 더 올 것이 없다).
            // 결과는 상태 상자가 말하고, 색을 모르는 카드는 배지 없이 얼굴만 남는다.
            subtitle = (index == 0 && !watch.isFinished) ? GomokuPhoneText.watchLoading : nil
        }
        return GamesGomokuWatchPlayerRow(
            store: store,
            user: user,
            color: known ? color : nil,
            isTurn: known && !watch.isFinished && watch.turn == color,
            deadline: watch.deadline,
            subtitle: subtitle
        )
    }

    /// 판 한 장(가운데 정렬 · 그림자는 대국·결과 화면과 같은 줄). 입력이 없으므로 `forbidden: [:]` · `preview: nil` 이고
    /// 탭 제스처를 달지 않는다. 끝난 판이 5목이면 승리선을 긋는다(결과 화면과 같은 판정 — `GomokuPhoneWinLine`).
    private func board(side: CGFloat) -> some View {
        GamesGomokuBoardCanvas(
            board: watch.board,
            geometry: GomokuPhoneBoardGeometry(side: side),
            lastMove: watch.lastMove,
            forbidden: [:],
            autoPoints: watch.autoPoints,
            preview: nil,
            winLine: watch.isFinished && watch.endReason == .five
                ? GomokuPhoneWinLine.ends(board: watch.board, lastMove: watch.lastMove)
                : nil
        )
        .frame(width: side, height: side)
        .shadow(color: colorScheme == .dark ? .black.opacity(0.35) : Color(red: 80 / 255, green: 50 / 255, blue: 10 / 255).opacity(0.18),
                radius: 9, y: 6)
        .frame(maxWidth: .infinity)
        // 보이스오버: 판 전체가 한 요소다(돌 수 · 마지막 수 · 누구 차례) — 칸마다 요소를 두는 것은 두는 사람의 판뿐이다.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(GomokuPhoneText.watchBoardAccessibility(watch))
    }

    /// 판 한 변 — **가용 높이 예산**으로 정한다. 관전에서 가장 중요한 상태(누구 차례 · 남은 초 · 끝났는가)가 판보다 먼저다.
    ///
    /// 0.3.41 은 대국 화면 `boardSide(in:)` 을 그대로 복사해 **글자 크기만** 봤다(`typeSize >= .xLarge` 일 때만 줄였다).
    /// 그런데 관전 화면은 대국보다 아래가 무겁다: 상태 상자 · 판돈/N수 줄 · 캡션이 더 있고, `safeAreaInset` 의 [나가기]
    /// 막대(64.5pt)와 탭 막대가 늘 깔린다. 그래서 iPhone SE(375×667)에서는 **기본 글자로도** 백 카드가 잘리고
    /// 상태 상자가 통째로 화면 밖이었다(위 주석이 "상태가 판보다 먼저"라고 적어 놓고 그 보호가 큰 글자에만 걸려 있었다).
    /// iPhone 15 도 받은 신청이 한 장 서면 같은 일이 났다 — 그 카드는 60초짜리라 판보다 먼저 자리를 받아야 한다.
    ///
    /// 두 상한 중 **작은 쪽**을 쓴다:
    /// ① 높이 예산 — `보이는 높이 − [나가기] 막대 − (상태 상자까지의 다른 블록 합)`. 상수 출처는 `GomokuPhoneWatchBudget`.
    /// ② 큰 글자 비율(옛 식) — 글자가 커지면 ① 의 상수가 실제보다 작아져 예산이 과하게 낙관적이 되므로 그대로 남긴다.
    private func boardSide(in visible: CGSize) -> CGFloat {
        let full = max(GomokuPhoneWatchBudget.boardFloor, visible.width - 24)
        guard visible.height > 0 else { return full }
        var side = min(full, visible.height - GomokuPhoneWatchBudget.leaveBar - blocksAboveStatusBox)
        if typeSize >= .xLarge {
            let fraction: CGFloat = typeSize.isAccessibilitySize ? 0.40 : 0.52
            side = min(side, visible.height * fraction)
        }
        // 바닥값 아래로는 줄이지 않는다 — 돌이 안 읽히는 판은 관전이 아니다. 예산이 그보다 좁은 자리
        // (SE + 신청 두 절이 다 선 경우)에서는 상태 상자가 한 번 스크롤 아래로 내려간다.
        return max(GomokuPhoneWatchBudget.boardFloor, side.rounded(.down))
    }

    /// 판 위·아래에서 **상태 상자까지** 자리를 먹는 블록들의 합(`VStack` 간격 · 위 패딩 포함).
    /// 판돈/N수 줄과 캡션은 세지 않는다 — 상태 상자 아래고, 스크롤로 닿으면 되는 것들이다.
    ///
    /// 두 사람을 하나도 모르는 판은 카드 두 장 대신 한 줄이라(`players` 의 else 갈래) 실제보다 조금 크게 잡힌다 —
    /// 판을 더 작게 잡는 쪽이므로 그대로 둔다(예산은 넉넉히 틀리는 편이 안전하다).
    private var blocksAboveStatusBox: CGFloat {
        var blocks: [CGFloat] = []
        let pending = gomoku.pendingIncomingInvites
        if !pending.isEmpty {
            blocks.append(GomokuPhoneWatchBudget.sectionHeader)
            blocks.append(GomokuPhoneWatchBudget.inviteCard * CGFloat(pending.count))
        }
        if gomoku.outgoing != nil {
            blocks.append(GomokuPhoneWatchBudget.sectionHeader)
            blocks.append(GomokuPhoneWatchBudget.outgoingRow)
        }
        if gomoku.notice != nil {
            blocks.append(GomokuPhoneWatchBudget.notice)
        }
        blocks.append(GomokuPhoneWatchBudget.playerCard)  // 흑(판 위)
        blocks.append(GomokuPhoneWatchBudget.playerCard)  // 백(판 아래)
        blocks.append(GomokuPhoneWatchBudget.statusBox)
        // 판도 `VStack` 자식 하나다 — 자식은 `blocks.count + 1` 개, 그 사이 간격은 `blocks.count` 개.
        return MobileTheme.space2 + blocks.reduce(0, +) + MobileTheme.space2 * CGFloat(blocks.count)
    }

    // MARK: 판돈 · 수 · 경과

    /// 판돈 | N수 · 경과 한 줄. 판돈은 씨앗이 없으면 첫 응답 전까지 모른다("판돈 —").
    private var info: some View {
        InsetGroup {
            GroupRow(divider: .none) {
                if typeSize.isAccessibilitySize {
                    // 큰 글자: 판돈 줄과 수·경과가 한 줄에 몰리면 "이기면 / +5"로 꺾인다(신청 카드에서 실측된 같은 결).
                    VStack(alignment: .leading, spacing: 4) { stakeLine; GamesGomokuWatchMoveLine(store: store, watch: watch) }
                } else {
                    stakeLine
                    Spacer(minLength: MobileTheme.space2)
                    GamesGomokuWatchMoveLine(store: store, watch: watch)
                }
            }
        }
    }

    /// 판돈 **액수만** — 접미사를 붙이지 않는다.
    ///
    /// 0.3.41 은 여기에 `stakeGainSuffix` 를 붙여 "판돈 10 · 이기면 +10" 이라고 썼는데, **관전자는 이 판에서
    /// 한 푼도 얻지 못한다**(보이스오버도 같은 말을 읽었다). 그 접미사를 붙이는 자리는 내비 부제·신청 카드·대국 화면 —
    /// 전부 **내 판**이고, 로비의 같은 '남의 판' 줄(`GamesLiveMatchRow`)도 접미사를 안 붙인다.
    @ViewBuilder
    private var stakeLine: some View {
        if let stake = watch.stake {
            GamesStakeLine(stake: stake)
                .font(MobileTheme.rowSubtitle)
                .foregroundStyle(MobileTheme.label2)
        } else {
            Text(GomokuPhoneText.watchStakeUnknown)
                .font(MobileTheme.rowSubtitle)
                .foregroundStyle(MobileTheme.label2)
        }
    }

    /// 카드 밑 작은 줄(로비 캡션과 같은 자리): 채팅이 없다는 사실 · 판 위 회색 점이 뜻하는 것을 **글자로도**
    /// (폰에는 호버 자리가 없어 점만으로는 아무도 모른다).
    private var caption: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(GomokuPhoneText.watchNoChat)
                .fixedSize(horizontal: false, vertical: true)
            if !watch.autoPoints.isEmpty {
                Text(GomokuPhoneText.autoPlacedCount(watch.autoPoints.count))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(MobileTheme.rowSubtitle)
        .foregroundStyle(MobileTheme.label2)
        .padding(.horizontal, MobileTheme.titleMargin - MobileTheme.sideMargin)
        .padding(.top, MobileTheme.space1)
        .accessibilityElement(children: .combine)
    }

    // MARK: [나가기]

    /// [나가기]는 **늘 보이는 아래 막대**에 둔다 — 판이 화면을 채우면 스크롤 끝의 버튼은 "거둘 길"이 못 된다.
    /// `leaveWatch()` 는 관전을 내리고 로비·받은함·순위를 다시 읽는다(`stopWatching()` 을 부르면 낡은 목록의 로비로 돌아오고,
    /// 관전 중 막아 둔 받은함의 끝난 내 판 결과도 서지 않는다). 채운 버튼은 화면당 하나라 여기는 틴트다 —
    /// 받은 신청 카드의 [수락]이 그 하나다.
    private var leaveBar: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(MobileTheme.separator)
                .frame(height: MobileTheme.hairline)
            AingButton(GomokuPhoneText.leaveWatch, systemImage: "arrow.uturn.backward", kind: .tinted, size: .md, fillsWidth: true) {
                gomoku.leaveWatch()
            }
            .accessibilityHint(GomokuPhoneText.leaveWatchHint)
            .padding(.horizontal, MobileTheme.sideMargin)
            .padding(.vertical, 10)
        }
        .background(MobileTheme.surface)
    }
}

// MARK: - 세로 예산

/// 관전 첫 화면의 세로 예산(pt · **기본 글자 크기**). `boardSide(in:)` 이 판을 줄일 때 쓴다.
///
/// 상수마다 **어디서 나온 숫자인지**를 적는다 — 다음 사람이 손으로 검산할 수 있어야 한다(관전 화면은 폰 전용이라
/// 맥 `swift test` 가 그릴 수 없다). 글자가 커지면 이 값들은 전부 작아지므로 예산만으로 판을 정하지 않는다
/// (`boardSide(in:)` 의 비율 상한 ②).
///
/// 검산(기본 글자 · 상태 상자 바닥까지):
/// - iPhone SE 375×667 → 보이는 높이 ≈ 667 − 64(상태막대+내비) − 49(탭 막대) = 554, 가용 = 554 − 64.5 = 489.5.
///   신청이 없을 때 다른 블록 합 = 8 + (60+60+60) + 8×3 = 212 → 판 277(옛 식은 351 이라 상태 상자가 통째로 밖).
/// - iPhone 15 393×852 → 보이는 높이 ≈ 739, 가용 ≈ 674.5. 신청 없으면 판은 폭 상한 369 그대로,
///   받은 신청이 한 장 서면 블록 합이 212 + (54+128) + 8×2 = 410 → 판 264 로 줄어 상태 상자가 남는다.
private enum GomokuPhoneWatchBudget {
    /// [나가기] 막대(`GamesGomokuWatch.leaveBar`): 실선 0.5 + `.md` 버튼 누름 영역 44 + 위아래 10 = 64.5.
    static let leaveBar = MobileTheme.hairline + AingButtonMetrics.targetHeight(for: .md) + 20

    /// 플레이어 카드 한 장(`GamesGomokuWatchPlayerRow`): 초상 44 + 위아래 8 = 60.
    /// 이름·부제 두 줄(callout 21 + 1 + footnote 18 = 40)은 초상보다 낮아 높이를 정하지 않는다.
    static let playerCard: CGFloat = 44 + 8 * 2

    /// 상태 상자(`GamesGomokuWatchStatusBox.box`): subheadline **두 줄**(20×2) + 위아래 10 = 60.
    /// 한 줄로 끝나는 문구("관전 중 · 흑 차례")가 많지만, 375pt 에서 "관전 중 · 시간이 지나 곧 자동으로 놓여요"는 두 줄이다.
    static let statusBox: CGFloat = 20 * 2 + 10 * 2

    /// 안내 한 줄(`InlineNotice`): footnote 18 + 위아래 10 = 38.
    static let notice: CGFloat = 18 + 10 * 2

    /// `SectionHeader(padded: true)`: 위 22 + title3 24 + 아래 8 = 54.
    static let sectionHeader: CGFloat = 22 + 24 + 8

    /// 받은 신청 카드 한 장(`GamesGomokuInviteCard`): 위 14 + 초상 44 + 아래 10 + 버튼 누름 영역 44 + 아래 16 = 128.
    static let inviteCard: CGFloat = 14 + 44 + 10 + AingButtonMetrics.targetHeight(for: .md) + MobileTheme.cardPadding

    /// 보낸 신청 행(`GamesGomokuOutgoingRow`): [취소] 누름 영역 44(초상 36·글 40 보다 높다) + `GroupRow` 위아래 10 = 64.
    /// 그 행의 `minHeight: 56` 보다 크므로 이 값이 이긴다.
    static let outgoingRow = AingButtonMetrics.targetHeight(for: .sm) + 10 * 2

    /// 판을 이보다 작게는 줄이지 않는다. 한 칸은 `side × 0.88 ÷ 14`(`GomokuPhoneBoardGeometry.cell`)라
    /// 210pt 에서 13.2pt — 돌이 겨우 읽히는 선이다. 대국 화면의 바닥값 240 보다 낮게 둘 수 있는 이유는
    /// **관전 판에 탭이 없어서**다(240 은 누르는 칸 16pt 를 지키려는 값이다).
    static let boardFloor: CGFloat = 210
}

// MARK: - 플레이어 카드

/// 관전 플레이어 한 장 — 대국 카드(`GamesGomokuPlayerCard`)와 같은 모양이지만 **마감을 직접 받는다**.
/// 그 카드를 재사용하면 차례 링이 스토어 `remainingSeconds`(내 판 전용)를 읽어 0초에 빨갛게 선다.
///
/// - `color`: 서버가 말한 돌 색. **nil 이면 색을 모른다**(첫 응답 전 — `faces` 는 uuid 순서다): 돌 배지도 초록 테두리도 없다.
/// - `user`: nil 이면 그 자리 사람조차 모른다(씨앗 없는 판) — 이름 자리에 "—".
private struct GamesGomokuWatchPlayerRow: View {
    let store: GamesStore
    let user: GomokuUser?
    let color: GomokuColor?
    let isTurn: Bool
    /// 진행 중인 판의 차례 마감. 지난 값이 올 수 있다 — 그 판정은 링(`GamesGomokuWatchClock`)이 한다.
    let deadline: Date?
    let subtitle: String?

    /// 돌 배지는 **색을 알 때만**(함정 1) — 모르는 동안 아무 색이나 달면 절반의 판이 뒤집힌다.
    private var badge: CharacterPortrait.Badge {
        guard let color else { return .none }
        return .stone(isBlack: color == .black)
    }

    /// 이름 자리. 사람을 모르거나(씨앗 없는 판) **이름이 빈 문자열**이면 "—" 다(위 `PersonName` 자리의 주석).
    private var displayName: String {
        let name = user?.displayName ?? ""
        return name.isEmpty ? "—" : name
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: MobileTheme.groupRadius, style: .continuous)
        HStack(spacing: MobileTheme.space3) {
            // 표정은 **늘 `.plain`**(상태 없음 — 링도 발광도 없다). 0.3.41 은 `user?.mood` 를 읽었는데 그 값은
            // `isWorking ? .working : .off`(`GamesComponents.swift`)라, 관전 응답에 `is_working` 키가 없는 탓에
            // 전원 근무 표정(웃음 + 초록 링 + 발광)이 됐다. 근무 상태를 모르는 자리에서 링은 상태 점과 같은 단정이다.
            CharacterPortrait(id: user?.characterID, mood: .plain, size: 44, badge: badge)
            VStack(alignment: .leading, spacing: 1) {
                // `??` 로는 이름을 못 접는다: 코어 경계 `peerUser` 가 이름을 모를 때 nil 이 아니라 **빈 문자열**을
                // 넣으므로(`displayName ?? ""`), 서버가 이름을 안 실은 판은 "—" 대신 이름 줄이 통째로 비었다.
                // 끝난 판 한 줄에서 고친 것과 **같은 함정**이다(`GomokuPhoneWatchStatus.displayName`).
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
            if isTurn, let deadline {
                GamesGomokuWatchClock(store: store, deadline: deadline)
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(shape.fill(MobileTheme.surface))
        // 차례인 카드만 초록 테두리(대국 화면과 같다). 마감이 지나도 초록이다 — 차례는 여전히 그 사람 것이고,
        // "곧 자동으로 놓여요"는 링과 상태 상자가 대기색으로 말한다.
        .overlay(shape.strokeBorder(isTurn ? MobileTheme.workingDot : Color.clear, lineWidth: 2))
    }
}

// MARK: - 잎 뷰(시계를 읽는 자리)

/// 관전 차례 링 — **잎 뷰**. 마감 시각을 직접 받아 스토어 시계로 센다(데모 고정 시계와 같은 눈금).
/// 그림은 대국 링(`GamesGomokuTurnRing`)과 같고 **0초 색만 다르다**: 마감이 지난 남의 판은 자동 착수 **대기**지 패배가 아닌데,
/// 빨간 0초는 색만으로 "졌다"로 읽혔다(맥 2026-09-30 반증). 그래서 0초는 대기색(pending)이다.
private struct GamesGomokuWatchClock: View {
    let store: GamesStore
    let deadline: Date

    var body: some View {
        // 1초 눈금 — 관전은 남의 시계라 0.2초로 돌릴 이유가 없다(로비 "지금 대결 중" 줄과 같은 관용구).
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let remaining = max(0, deadline.timeIntervalSince(store.context.clock.now()))
            let total = Double(max(1, store.context.gomoku.turnSeconds))
            let fraction = min(1, max(0, remaining / total))
            let ring = remaining <= 0 ? MobileTheme.pendingDot
                : (remaining <= 5 ? MobileTheme.danger : (remaining <= 10 ? MobileTheme.pendingDot : MobileTheme.workingDot))
            let ink = remaining <= 0 ? MobileTheme.pending
                : (remaining <= 5 ? MobileTheme.danger : (remaining <= 10 ? MobileTheme.pending : MobileTheme.working))
            ZStack {
                Circle().stroke(MobileTheme.fill, lineWidth: 4)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(ring, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(GomokuPhoneText.remaining(remaining))
                    .font(.system(size: 13, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(ink)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }
            .padding(2)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(GomokuPhoneText.clockAccessibility(remaining))
        }
    }
}

/// 상태 상자 — **잎 뷰**. 문구·색을 `GomokuPhoneWatchStatus` 가 시각으로 고른다.
/// 시각이 문구를 바꾸는 것은 **마감이 있는 진행 중 판**뿐이라, 끝난 판·첫 응답 전에는 시계를 아예 달지 않는다
/// (끝난 판은 폴링도 이미 멈춰 있다 — 1초마다 다시 그릴 이유가 없다).
private struct GamesGomokuWatchStatusBox: View {
    let store: GamesStore
    let watch: GomokuSpectateState

    var body: some View {
        if !watch.isFinished, watch.deadline != nil {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                box(now: store.context.clock.now())
            }
        } else {
            box(now: store.context.clock.now())
        }
    }

    private func box(now: Date) -> some View {
        let kind = GomokuPhoneWatchStatus.kind(for: watch, now: now)
        let tint = Self.tint(kind)
        // 글자는 `label` 이고 뜻은 기호·바탕이 낸다(공용 `InlineNotice` 와 같은 문법) — 틴트 위 틴트 글자는 대비가 떨어진다.
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: Self.symbol(kind))
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                Text(GomokuPhoneWatchStatus.text(for: watch, now: now))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(MobileTheme.label)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            if let warning = GomokuPhoneWatchStatus.streakWarning(for: watch, lossStreak: store.context.gomoku.autoAbandonStreak) {
                Text(warning)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(MobileTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: MobileTheme.innerRadius, style: .continuous).fill(tint.opacity(0.12)))
        .accessibilityElement(children: .combine)
    }

    /// 진행 중은 초록(대국의 "내 차례"와 같은 결) · 마감 지남은 앰버(대기 — **빨강 금지**) · 끝은 청회색 · 모름은 회색.
    private static func tint(_ kind: GomokuPhoneWatchStatus.Kind) -> Color {
        switch kind {
        case .loading: return MobileTheme.label2
        case .turn: return MobileTheme.working
        case .overdue: return MobileTheme.pending
        case .ended: return MobileTheme.offWork
        }
    }

    private static func symbol(_ kind: GomokuPhoneWatchStatus.Kind) -> String {
        switch kind {
        case .loading: return "hourglass"
        case .turn: return "eye"
        case .overdue: return "clock.badge.exclamationmark"
        case .ended: return "flag.checkered"
        }
    }
}

/// "12수 · 1분 35초째" — **잎 뷰**. 끝난 판은 경과를 세지 않는다(끝난 뒤 흐르는 시간은 아무 뜻도 없다).
private struct GamesGomokuWatchMoveLine: View {
    let store: GamesStore
    let watch: GomokuSpectateState

    var body: some View {
        if let startedAt = watch.startedAt, !watch.isFinished {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                line(GomokuPhoneText.watchMoves(watch.moveCount) + " · "
                    + GomokuPhoneText.elapsedPhrase(store.context.clock.now().timeIntervalSince(startedAt)))
            }
        } else {
            line(GomokuPhoneText.watchMoves(watch.moveCount))
        }
    }

    private func line(_ text: String) -> some View {
        Text(text)
            .font(MobileTheme.rowSubtitle)
            .monospacedDigit()
            .foregroundStyle(MobileTheme.label2)
            .fixedSize(horizontal: false, vertical: true)
    }
}
#endif
