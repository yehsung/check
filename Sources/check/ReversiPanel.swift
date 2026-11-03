import AppKit
import SwiftUI
import CheckCore

// MARK: - 아잉 뒤집기 창 화면 (내부 이름 reversi)
//
// `CheckReversiWindowController` 가 담는 화면이다: 로비(상대 고르기 · 순위 · 내 전적 · 지금 대결 중 · 신청) → 대국(8×8 판 ·
// 30초 링 · 돌 수 · 수 기록 · 판돈 · 기권) → 결과, 그리고 남의 판 관전과 AI 연습 판. 계약은 설계서 FLIP/SPEC.md §5.
// 상태·동작은 전부 `ReversiStore`(CheckCore)에 있고 여기는 **그리기와 탭 전달**만 한다.
//
// 이 화면이 지키는 약속(오목·체스 화면에서 얻은 것):
//   · **Picker/Menu/TextField 를 쓰지 않는다.** 고르기·수락·기권은 전부 Button + Shape/Canvas 다 — ImageRenderer 가
//     TextField·분절 Picker 는 노란 상자로, Menu·기본 Picker 는 아무것도 안 그린다(렌더 검증이 눈이 먼다).
//   · **둘 수 있는 칸은 내가 계산하지 않는다**(`store.legalTargets` — 1:1 은 서버 목록, AI 판은 로컬 규칙).
//   · **초 단위 값은 잎 뷰 TimelineView 안에서만 읽는다**(30초 링 · 3초 테두리 · 신청 남은 초). 창 루트가 시계를 읽으면
//     창 전체가 초마다 다시 그려진다. 잎은 창이 안 보이면 멈춘다(`isWindowVisible`).
//   · 문구는 `ReversiText`(맥 화면 글자)와 `ReversiNoticeText`(안내·거절, 코어) 두 표에만 있다. 정보는 **글자로** 말한다
//     (툴팁만 두지 않는다 — 렌더 검증이 툴팁을 못 본다).
//   · `.shadow` 를 쓰지 않는다 · 이징으로 불투명도를 깎지 않는다.

// MARK: - 나(플레이어 얼굴)

/// 카드에 그릴 사람 한 명의 얼굴. 스토어는 **상대만** 들고 있어서 나는 앱 배선이 `WorkTimerStore` 에서 읽어 넘긴다.
struct ReversiPlayerFace: Equatable {
    let name: String
    let avatarURL: URL?
    let characterID: String
    /// 소속 센터의 **화면 글자**. nil 이면 배지가 없다.
    var center: String? = nil
    /// 내 user id(소문자). 순위표에서 내 줄을 칠한다. 모르면 nil(칠하지 않는다 — 지어내지 않는다).
    var userID: String? = nil

    static let fallbackCharacterID = "aing"
    static let fallback = ReversiPlayerFace(name: "나", avatarURL: nil, characterID: fallbackCharacterID)

    /// 로그인한 나. 이름·아바타는 팀 목록의 내 행에서, 캐릭터는 이 맥에서 고른 캐릭터에서 읽는다.
    @MainActor
    static func me(from store: WorkTimerStore) -> ReversiPlayerFace {
        let myID = store.session?.userID
        let mine = store.teamMembers.first { $0.id == myID }
        let character = CheckCharacter3DScene.selectedCharacter(defaults: .standard).id
        return ReversiPlayerFace(name: mine?.name ?? "나", avatarURL: mine?.avatarURL, characterID: character,
                                 center: CenterLabel.display(store.myCenter), userID: myID?.lowercased())
    }

    static func of(_ user: ReversiUser) -> ReversiPlayerFace {
        ReversiPlayerFace(
            name: user.displayName,
            avatarURL: user.avatarURL.flatMap(URL.init(string:)),
            characterID: user.characterID ?? fallbackCharacterID,
            // 이미 화면 글자다(스토어 경계에서 한 번 변환했다).
            center: user.center,
            userID: user.id
        )
    }
}

// MARK: - 창 루트

struct ReversiPanel: View {
    let store: ReversiStore
    /// 내 얼굴을 읽는 문(앱 배선이 WorkTimerStore 에서 읽는다).
    var me: @MainActor () -> ReversiPlayerFace = { ReversiPlayerFace.fallback }
    /// 사람 아바타의 캐릭터 한 표를 읽는 곳(앱 배선이 `WorkTimerStore` 를 넘긴다).
    var safety: WorkTimerStore? = nil
    /// 스냅샷 전용: 목록을 ScrollView 대신 클립으로 그린다(ImageRenderer 는 ScrollView 안을 못 그린다). 앱은 false.
    var clipsOverflowInsteadOfScroll: Bool = false
    /// 스냅샷 전용: 판돈 창을 이 상대에게 띄운 채로 그린다. 앱은 nil.
    var previewStakeTarget: ReversiUser? = nil
    /// 스냅샷 전용: 판돈 창에서 이 판돈을 고른 상태로 그린다. 앱은 nil.
    var previewStakeSelection: ReversiStake? = nil
    /// 스냅샷 전용: [기권] 자리를 확인 상태로 그린다. 앱은 false.
    var previewConfirmResign: Bool = false
    /// 스냅샷 전용: AI 색 고르기 창을 띄운 채로 그린다. 앱은 false.
    var previewAIPrompt: Bool = false
    /// 스냅샷 전용 "지금"(30초 링 · 뒤집기 프레임 · 3초 테두리). 앱은 nil.
    var previewNow: Date? = nil

    @State private var confirmResign = false
    /// [도전]을 누른 상대 — 판돈 창이 이 값으로 열린다. nil 이면 닫혀 있다.
    @State private var stakeTarget: ReversiUser?
    /// 머리글 [AI와 두기] 를 눌렀다 — 색 고르기 창이 뜬다.
    @State private var aiPromptVisible = false

    private var activeStakeTarget: ReversiUser? { stakeTarget ?? previewStakeTarget }

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: ReversiWindowLayout.headerSpacing) {
                ReversiHeader(store: store, onAIMatch: { aiPromptVisible = true })
                    .frame(height: ReversiWindowLayout.headerHeight)
                content
                    .frame(width: ReversiWindowLayout.innerSize.width, height: ReversiWindowLayout.bodyHeight,
                           alignment: .topLeading)
            }
            .padding(ReversiWindowLayout.contentPadding)
            // 덮개는 **한 번에 하나**다 — 규칙 → 판돈 → AI 순.
            if store.isRulesVisible {
                ReversiRulesOverlay(onClose: { store.isRulesVisible = false })
            } else if let target = activeStakeTarget {
                ReversiStakePrompt(store: store, target: target, initialSelection: previewStakeSelection,
                                   onClose: { stakeTarget = nil })
            } else if aiPromptVisible || previewAIPrompt {
                ReversiAIPrompt(store: store, onClose: { aiPromptVisible = false })
            }
        }
        .frame(width: ReversiWindowLayout.contentSize.width, height: ReversiWindowLayout.contentSize.height,
               alignment: .topLeading)
        .background(CheckTheme.background)
        .foregroundStyle(CheckTheme.primaryText)
        // 툴팁 말풍선 레이어 — 창 루트 하나(새 창 루트에는 이 한 줄이 반드시 있어야 말풍선이 뜬다).
        .checkTooltipLayer()
        // 사람 아바타의 캐릭터 한 표. nil 이면 빈 표 = 모르는 사람은 착용값·그마저 없으면 이니셜.
        .appUserAvatarCharacters(from: safety)
        .environment(\.reversiPreviewNow, previewNow)
        .onChange(of: store.match?.id) { _, _ in
            confirmResign = false
            // 판이 시작되면 로비가 사라진다 — 열려 있던 판돈 창을 들고 있으면 로비로 돌아올 때 되살아난다.
            stakeTarget = nil
            aiPromptVisible = false
        }
        // 기권 확인은 **그 판 그 화면에서 연 것**만 산다.
        .onChange(of: store.phase) { _, _ in confirmResign = false }
        .onChange(of: store.isWindowVisible) { _, _ in confirmResign = false }
    }

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .playing:
            if let match = store.match { playing(match) } else { lobby }
        case .result:
            if let match = store.match { result(match) } else { lobby }
        case .lobby:
            // 관전은 로비 자리에 선다 — `phase` 는 `.lobby` 그대로이고 `spectating` 하나가 화면을 가른다.
            if let watch = store.spectating { spectate(watch) } else { lobby }
        }
    }

    // MARK: 로비

    /// 로비는 **세 열**이다: 상대 목록 420 · 순위 340 · 오른쪽 400.
    private var lobby: some View {
        HStack(alignment: .top, spacing: ReversiWindowLayout.columnSpacing) {
            ReversiOpponentList(store: store, clipsOverflowInsteadOfScroll: clipsOverflowInsteadOfScroll,
                                onChallenge: { stakeTarget = $0 })
                .frame(width: ReversiWindowLayout.lobbyUsersWidth, height: ReversiWindowLayout.bodyHeight,
                       alignment: .top)
                .clipped()
            ReversiRankColumn(store: store, myUserID: me().userID,
                              clipsOverflowInsteadOfScroll: clipsOverflowInsteadOfScroll)
                .frame(width: ReversiWindowLayout.lobbyRankWidth, height: ReversiWindowLayout.bodyHeight,
                       alignment: .top)
                .clipped()
            ReversiLobbySide(store: store, me: me(), clipsOverflowInsteadOfScroll: clipsOverflowInsteadOfScroll)
                .frame(width: ReversiWindowLayout.lobbySideWidth, height: ReversiWindowLayout.bodyHeight,
                       alignment: .top)
                .clipped()
        }
    }

    // MARK: 관전

    /// 관전은 대국과 같은 **두 열**이다. 판은 입력이 없다(관전자는 아무것도 쓰지 못한다).
    private func spectate(_ watch: ReversiSpectating) -> some View {
        HStack(alignment: .top, spacing: ReversiWindowLayout.columnSpacing) {
            ReversiStaticBoard(store: store, matchID: watch.id, board: watch.board,
                               lastStoneIdx: watch.lastStoneIdx, autoStones: watch.autoStones, turn: watch.turn)
            ReversiSpectateSide(store: store, watch: watch,
                                clipsOverflowInsteadOfScroll: clipsOverflowInsteadOfScroll)
                .frame(width: ReversiWindowLayout.sideColumnWidth, height: ReversiWindowLayout.bodyHeight,
                       alignment: .top)
                .clipped()
        }
    }

    // MARK: 대국

    private func playing(_ match: ReversiMatchState) -> some View {
        HStack(alignment: .top, spacing: ReversiWindowLayout.columnSpacing) {
            ReversiPlayBoard(store: store, match: match)
                .frame(width: ReversiWindowLayout.boardSide, height: ReversiWindowLayout.boardSide)
            ReversiMatchSide(
                store: store, match: match, me: me(),
                confirmResign: $confirmResign,
                showsConfirmPreview: previewConfirmResign,
                clipsOverflowInsteadOfScroll: clipsOverflowInsteadOfScroll
            )
            .frame(width: ReversiWindowLayout.sideColumnWidth, height: ReversiWindowLayout.bodyHeight, alignment: .top)
            .clipped()
        }
    }

    // MARK: 결과

    private func result(_ match: ReversiMatchState) -> some View {
        HStack(alignment: .top, spacing: ReversiWindowLayout.columnSpacing) {
            ReversiStaticBoard(store: store, matchID: match.id, board: match.board,
                               lastStoneIdx: match.lastStoneIdx, autoStones: match.autoStones, turn: nil)
            VStack(alignment: .leading, spacing: ReversiWindowLayout.matchSideSpacing) {
                ReversiResultCard(store: store, match: match)
                    .fixedSize(horizontal: false, vertical: true)
                ReversiMoveListCard(plies: match.plies, counts: match.counts,
                                    clipsOverflowInsteadOfScroll: clipsOverflowInsteadOfScroll)
                    .frame(maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            }
            .frame(width: ReversiWindowLayout.sideColumnWidth, height: ReversiWindowLayout.bodyHeight, alignment: .top)
            .clipped()
        }
    }
}

// MARK: - 머리글

private struct ReversiHeader: View {
    let store: ReversiStore
    var onAIMatch: () -> Void = {}

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(CheckTheme.accent.opacity(0.18))
                Image(systemName: ReversiEntryIcon.resolved)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(CheckTheme.accent)
            }
            .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(ReversiText.title).font(.title3.weight(.bold))
                Text(ReversiText.subtitle)
                    .font(.caption)
                    .foregroundStyle(CheckTheme.secondaryText)
            }
            Spacer(minLength: 12)
            HStack(spacing: 5) {
                Image(systemName: "flag.checkered")
                Text(ReversiRecordSource.headerLine(store)).monospacedDigit()
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(Capsule().fill(Color.white.opacity(0.06)))
            .overlay(Capsule().stroke(CheckTheme.border, lineWidth: 1))
            .checkTooltip(ReversiText.rankHelp)
            RubyBalanceChip(balance: store.rubyBalance, large: true)
                .checkTooltip(ReversiText.myRubyHelp)
            // 로비에서만 선다 — 판 중에 새 판을 열 길을 두지 않는다. 관전 중에도 숨긴다.
            if store.phase == .lobby, store.spectating == nil {
                ChessActionButton(title: ReversiText.aiButton, icon: "cpu", style: .outline, height: 30,
                                  isEnabled: store.canStartAIMatch, action: onAIMatch)
                    .checkTooltip(ReversiText.aiButtonHelp)
            }
            ChessActionButton(title: ReversiText.rulesButton, icon: "book.fill", style: .outline, height: 30) {
                store.isRulesVisible = true
            }
            .checkTooltip(ReversiText.rulesHelp)
        }
    }
}

/// 전적 글자 — **한 출처**. 순위 응답의 `me` 가 로비 전적과 같을 때만 순위·승점을 함께 쓴다
/// (두 출처를 섞으면 "8승 3패 · 승점 +4" 같은 자기모순 문장이 뜬다).
enum ReversiRecordSource {
    /// 순위 응답의 내 줄이 로비 전적과 같을 때만 그 줄. 로비 전적이 아직 없으면 순위 줄을 믿는다.
    @MainActor
    static func consistentRank(_ store: ReversiStore) -> ReversiMyRank? {
        guard let mine = store.ranking?.me else { return nil }
        guard let record = store.record else { return mine }
        guard record.wins == mine.wins, record.losses == mine.losses, record.draws == mine.draws else { return nil }
        return mine
    }

    @MainActor
    static func headerLine(_ store: ReversiStore) -> String {
        guard let mine = consistentRank(store) else { return ReversiText.record(store.record) }
        let record = ReversiText.record(wins: mine.wins, losses: mine.losses, draws: mine.draws)
        guard let rank = mine.rank else { return record }
        return "\(record) · \(ReversiText.myRank(rank: rank, points: mine.points))"
    }
}

// MARK: - 공용 조각

/// 가운데 작은 창의 공통 바닥 — 뒤를 어둡게 덮고 가운데에 내용을 세운다.
struct ReversiOverlayScrim<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            CheckTheme.panelElevated.opacity(0.93)
            content
        }
        .frame(width: ReversiWindowLayout.contentSize.width, height: ReversiWindowLayout.contentSize.height)
    }
}

/// 스크롤 칸. 스냅샷에서는 **클립 갈래**로 그린다 — ImageRenderer 는 ScrollView 안을 못 그린다.
struct ReversiScrollBox<Content: View>: View {
    let clips: Bool
    @ViewBuilder let content: Content

    var body: some View {
        if clips {
            // 클립 갈래도 **위 정렬**이다(아래 ScrollView 는 언제나 위에서 시작한다).
            // ★ 내용을 바닥(`Color.clear`)의 overlay 로 얹는다 — 내용 높이가 부모로 새지 않는다. `frame(maxHeight:)` 만 두면
            //   12줄 넘는 수 목록이 카드 높이를 밀어 올려 열의 간격이 눌린다(스냅샷이 앱과 다른 그림이 된다).
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .topLeading) { content }
                .clipped()
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                content.frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

/// 안내 한 줄(두 줄까지).
struct ReversiNoticeLine: View {
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
            Text(text).lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption)
        .foregroundStyle(CheckTheme.secondaryText)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 돌 색 점(흑·백). 판의 돌과 **같은 두 극단색**을 쓴다.
struct ReversiStoneDot: View {
    let color: ReversiColor
    var size: CGFloat = 14

    var body: some View {
        Circle()
            .fill(color == .black ? ReversiBoardView.blackStone : ReversiBoardView.whiteStone)
            .overlay(Circle().stroke(color == .black ? Color.white.opacity(0.35) : Color.black.opacity(0.25),
                                     lineWidth: 1))
            .frame(width: size, height: size)
    }
}
