import AppKit
import SwiftUI
import CheckCore

// MARK: - 1:1 테트리스 창 화면 (v0.3.60)
//
// `CheckTetrisDuelWindowController` 가 담는 화면이다: 로비(상대 고르기 · 순위 탭 · 내 전적 · 지금 대결 중 · 받은/보낸 신청)
// → 대결(준비 → 카운트다운 3·2·1 → 판 → 결과). 상태·동작은 전부 `TetrisDuelStore`(CheckCore)에 있고 여기는
// **그리기와 탭 전달**만 한다.
//
// 이 파일이 지키는 약속(체스 화면에서 물려받은 것 + 테트리스에서 새로 생긴 것):
//   · **Picker/Menu/TextField 를 쓰지 않는다**(ImageRenderer 가 노란 상자로 그리거나 아무것도 안 그린다 — 체스 머리 주석).
//     탭·판돈 고르기·수락·기권은 전부 Button + Shape 다.
//   · ★ **판(`store.duel`)은 관찰 대상이 아니다.** 프레임마다 바뀌는 값이라 관찰하면 그 값을 읽는 모든 뷰가 매 걸음
//     무효화된다. 그래서 판 칸·떨어지는 조각·경과 초·카운트다운은 **잎 뷰의 TimelineView 안에서만** 읽는다
//     (`TetrisDuelBoardView` · `TetrisDuelElapsedLeaf`). 조각이 굳을 때만 바뀌는 숫자(지운 줄·공격·들어올 줄·속도)는
//     관찰 가능한 `store.myStats` 로 읽는다.
//   · **상대 판은 스냅숏이 올 때만 다시 그린다**(`store.match?.opponentBoard` — 관찰 값이고 보고 응답에서만 바뀐다).
//   · 판의 프레임 루프는 **창이 보일 때만** 돈다. 창이 숨어도 판은 스토어의 판 루프가 민다(설계 D10) — 이 뷰의 틱은
//     "더 자주 그리기" 일 뿐이다(같은 시각이면 멱등).
//   · 문구는 `TetrisDuelText`(화면 글자)와 `TetrisDuelNoticeText`(안내·결과 사유, 코어) 두 표에만 있다.

// MARK: - 아이콘 한 출처

/// 1:1 테트리스를 가리키는 아이콘 한 출처(창 머리글 · 팝오버 배너). 두 판이 나란히 선 그림이다 —
/// 솔로 테트리스 칩(`square.grid.2x2.fill`)과 갈려야 "대결 창" 으로 읽힌다.
enum TetrisDuelEntryIcon {
    static let symbol = "rectangle.split.2x1.fill"
    /// 그 이름이 없는 맥에서 쓸 대체 기호.
    static let fallbackSymbol = "square.grid.2x2.fill"

    @MainActor
    static var resolved: String {
        NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil ? symbol : fallbackSymbol
    }
}

// MARK: - 문구

/// 1:1 테트리스 화면의 사용자 문구(순수 — 값으로 검증한다). 진단 어휘를 쓰지 않는다.
enum TetrisDuelText {
    static let title = "1:1 테트리스"
    static let subtitle = "공격형 · 먼저 꼭대기까지 쌓이면 져요"
    static let rulesButton = "규칙"
    static let rulesHelp = "1:1 테트리스 규칙을 봐요"
    static let rulesTitle = "1:1 테트리스 규칙"
    static let close = "닫기"

    static let usersTab = "상대 고르기"
    static let rankTab = "순위"
    static let lobbyCaption = "근무 중이 아니어도 신청하고 받을 수 있어요"
    static let emptyUsers = "지금 대결할 수 있는 사람이 없어요"
    static let loadingUsers = "상대 목록을 불러오고 있어요"
    static let usersLoadFailed = TetrisDuelNoticeText.checkConnection
    static let reloadUsers = "다시 불러오기"
    static let challenge = "신청"
    static let needsUpdate = "앱 업데이트 필요"
    static let inMatch = "대결 중"
    static let working = "근무 중"
    static let focused = "집중 모드"

    static let stakeTitle = "판돈"
    /// 판돈 줄. 이기면 **순이익**(판돈 − 수수료, `DuelFee.winnerNet`) — 결과 카드의 루비 변화와 같은 숫자다.
    static func stakeLine(_ stake: Int) -> String { "\(stake) · 이기면 +\(DuelFee.winnerNet(stake: stake))" }
    static func stakePromptTitle(name: String) -> String { "\(name)님에게 신청" }
    static let stakePromptCaption = "판돈을 고르세요"
    static func stakePromptChosen(_ stake: Int) -> String { "판돈 \(stakeLine(stake))" }
    static func challengeWithStake(_ stake: Int) -> String { "\(stake) 걸고 신청하기" }
    static let stakeShortfall = CheckCoreShared.shortfallNotice(need: nil, have: nil)

    static let incomingTitle = "받은 신청"
    static func incomingMore(_ count: Int) -> String { "외 \(count)건" }
    static func inviteBannerTitle(name: String) -> String { "\(name)님이 테트리스 대결을 신청했어요" }
    static let inviteBannerSubtitle = "1분 안에 응답하세요"
    static let acceptHelp = "수락하고 테트리스 창을 열어요"
    static let viewInvite = "보기"
    static let viewInviteHelp = "테트리스 창에서 이 신청을 봐요"
    static let outgoingTitle = "보낸 신청"
    static let noIncoming = "받은 신청이 없어요"
    static let accept = "수락"
    static let decline = "거절"
    static let cancel = "취소"

    static let recordTitle = "내 전적"
    static let liveTitle = "지금 대결 중"
    static let noLive = "지금 진행 중인 대결이 없어요"
    static let myMatch = "내 판"

    static let rankLoading = "순위를 불러오고 있어요"
    static let rankEmpty = "아직 순위가 없어요"
    static let rankFailed = TetrisDuelNoticeText.checkConnection
    static let rankSoon = "순위는 곧 열려요"
    static let rankHelp = "승점 = 승 − 패"
    static func rankSince(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일부터"
        return formatter.string(from: date)
    }

    static func record(_ record: TetrisDuelRecord?) -> String {
        guard let record else { return "0승 0패 0무" }
        return self.record(wins: record.wins, losses: record.losses, draws: record.draws)
    }

    static func record(wins: Int, losses: Int, draws: Int) -> String { "\(wins)승 \(losses)패 \(draws)무" }
    static func points(_ value: Int) -> String { "승점 \(value >= 0 ? "+" : "")\(value)" }

    // ── 대결 화면 ──
    static let me = "나"
    static let elapsedTitle = "경과"
    /// 2분이 지나 가속이 걸렸다(설계 D7 — 레벨 바닥이 1 을 넘었다).
    static let speedUp = "속도 올라가는 중"
    static func speedLevel(_ level: Int) -> String { "레벨 \(level)" }
    static let connectionTrouble = "연결 확인 중"
    static let opponentSilent = "상대 연결 확인 중"
    static let linesTitle = "지운 줄"
    static let attackTitle = "보낸 공격"
    static let incomingLinesTitle = "들어올 줄"
    static let ready = "준비 완료"
    static let notReady = "들어오는 중"
    static let finishedPresence = "대결 끝"
    static let waitingTitle = "상대를 기다리는 중"
    static func waitingSubtitle(seconds: Int) -> String { "\(seconds)초 안에 둘 다 들어오면 시작해요" }
    static let waitingAction = "창을 열어 두세요"
    static let startingSoon = "곧 시작해요"
    static let playingNow = "대결 중"
    static let toppedOutTitle = "꼭대기에 닿았어요"
    static let toppedOutSubtitle = "결과를 기다리는 중"
    static let resign = "기권"
    static let confirmResign = "기권하기"
    static let keepPlaying = "계속하기"
    static let resignWarning = "기권하면 판돈을 잃어요"
    static let backToLobby = "로비로"
    static let keysTitle = "조작"
    /// 조작 안내(솔로와 같은 키). **ESC 정지는 없다** — 대결은 멈출 수 없다.
    static let keys: [(key: String, action: String)] = [
        ("← →", "이동"), ("↑ · X", "회전"), ("Z", "반대로 회전"),
        ("↓", "빨리 내리기"), ("스페이스", "바로 내리기"), ("C", "홀드")
    ]
    static let gameHint = "창을 가리거나 내려도 판은 계속 흘러가요"

    static func outcomeTitle(_ outcome: TetrisDuelOutcome?) -> String {
        switch outcome {
        case .won?: return "이겼어요"
        case .lost?: return "졌어요"
        case .draw?: return "무승부예요"
        case nil: return "대결이 끝났어요"
        }
    }

    /// 판 시계 글자(`m:ss`). 음수는 0 으로.
    static func clock(_ seconds: Double) -> String {
        let whole = Int(max(0, seconds).rounded(.down))
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }

    /// 루비 증감 글자(+N / −N / 0).
    static func rubyDelta(_ value: Int) -> String { value > 0 ? "+\(value)" : "\(value)" }

    /// 규칙 보기의 줄들. 공격 표 · 가속 · 침묵 · 판돈은 **설계서 결정 그대로**다(D2 · D5 · D7 · D4).
    static let rules: [(title: String, detail: String)] = [
        ("공격", "2줄을 한 번에 지우면 상대에게 방해 줄 1줄, 3줄은 2줄, 4줄은 4줄을 보내요. "
            + "들어올 방해 줄이 있으면 내가 보낼 줄이 먼저 그것을 지워요."),
        ("방해 줄", "줄을 지우지 못한 채 조각이 굳으면 아래에서 회색 줄이 올라와요. 우물 왼쪽 빨간 막대가 들어올 줄이에요."),
        ("승부", "먼저 꼭대기까지 쌓이는 쪽이 져요. 2분이 지나면 떨어지는 속도가 점점 빨라져요."),
        ("연결", "창을 가리거나 내려도 판은 계속 흘러가요. 15초 넘게 연결이 끊기면 그쪽이 져요."),
        ("판돈", "수락하는 순간 두 사람 모두 판돈을 걸어요. 이기면 판돈만큼 더 받고(수수료 \(DuelFee.percent)% 빼고), "
            + "무승부면 돌려받아요. 30초 안에 둘 다 들어오지 않아도 돌려받아요.")
    ]
}

// MARK: - 창 루트

struct TetrisDuelPanel: View {
    let store: TetrisDuelStore
    /// 내 얼굴을 읽는 문(앱 배선이 WorkTimerStore 에서 읽는다 — 체스와 같은 얼굴 값).
    var me: @MainActor () -> ChessPlayerFace = { ChessPlayerFace.fallback }
    /// 스냅샷 전용: 목록을 ScrollView 대신 클립으로 그린다(ImageRenderer 는 ScrollView 안을 못 그린다). 앱은 false.
    var clipsOverflowInsteadOfScroll: Bool = false
    /// 스냅샷 전용: 판돈 창을 이 상대에게 띄운 채로 그린다. 앱은 nil.
    var previewStakeTarget: TetrisDuelUser? = nil
    /// 스냅샷 전용: 판돈 창에서 이 판돈을 고른 상태로. 앱은 nil.
    var previewStakeSelection: TetrisDuelStake? = nil
    /// 스냅샷 전용: [기권] 자리를 확인 상태로. 앱은 false.
    var previewConfirmResign: Bool = false
    /// 스냅샷 전용: 로비 탭. 앱은 nil(화면 @State 가 정한다).
    var previewLobbyTab: TetrisDuelLobbyTab? = nil
    /// 스냅샷 전용: 규칙 창을 띄운 채로. 앱은 false.
    var previewRules: Bool = false
    /// 사람 아바타의 캐릭터 한 표를 읽는 곳. nil 이면 이니셜로 떨어진다.
    var safety: WorkTimerStore? = nil

    @State private var confirmResign = false
    @State private var stakeTarget: TetrisDuelUser?
    @State private var rulesVisible = false
    @State private var lobbyTab: TetrisDuelLobbyTab = .users

    private var activeStakeTarget: TetrisDuelUser? { stakeTarget ?? previewStakeTarget }
    private var activeTab: TetrisDuelLobbyTab { previewLobbyTab ?? lobbyTab }
    private var myUserID: String? { safety?.session?.userID.lowercased() }

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: TetrisDuelWindowLayout.headerSpacing) {
                TetrisDuelHeader(store: store, onRules: { rulesVisible = true })
                    .frame(height: TetrisDuelWindowLayout.headerHeight)
                content
                    .frame(width: TetrisDuelWindowLayout.innerWidth, height: TetrisDuelWindowLayout.bodyHeight,
                           alignment: .topLeading)
            }
            .padding(TetrisDuelWindowLayout.contentPadding)
            // 덮개는 한 번에 하나.
            if rulesVisible || previewRules {
                TetrisDuelRulesOverlay(onClose: { rulesVisible = false })
            } else if let target = activeStakeTarget, store.phase == .lobby {
                TetrisDuelStakePrompt(store: store, target: target, initialSelection: previewStakeSelection,
                                      onClose: { stakeTarget = nil })
            }
        }
        .frame(width: TetrisDuelWindowLayout.contentSize.width, height: TetrisDuelWindowLayout.contentSize.height,
               alignment: .topLeading)
        .background(CheckTheme.background)
        .foregroundStyle(CheckTheme.primaryText)
        // 툴팁 말풍선 레이어 — 창 루트 하나(새 창 루트에는 이 한 줄이 반드시 있어야 말풍선이 뜬다).
        .checkTooltipLayer()
        // 사람 아바타의 캐릭터 한 표. nil 이면 빈 표 = 모르는 사람은 착용값·그마저 없으면 이니셜.
        .appUserAvatarCharacters(from: safety)
        .onChange(of: store.match?.id) { _, _ in
            confirmResign = false
            // 판이 시작되면 로비가 사라진다 — 열려 있던 판돈 창을 들고 있으면 로비로 돌아올 때 되살아난다.
            stakeTarget = nil
        }
        // 기권 확인은 **그 판 그 화면에서 연 것**만 산다.
        .onChange(of: store.phase) { _, _ in confirmResign = false }
        .onChange(of: store.isWindowVisible) { _, _ in confirmResign = false }
        .onChange(of: lobbyTab) { _, tab in
            if tab == .ranking { store.refreshRankingIfStale() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let match = store.match, store.phase != .lobby {
            matchView(match)
        } else {
            lobby
        }
    }

    // MARK: 로비 (두 열)

    private var lobby: some View {
        HStack(alignment: .top, spacing: TetrisDuelWindowLayout.columnSpacing) {
            VStack(alignment: .leading, spacing: 10) {
                TetrisDuelLobbyTabs(selected: activeTab, onSelect: { lobbyTab = $0 })
                    .frame(height: TetrisDuelWindowLayout.lobbyTabHeight)
                switch activeTab {
                case .users:
                    TetrisDuelOpponentList(store: store, clipsOverflowInsteadOfScroll: clipsOverflowInsteadOfScroll,
                                           onChallenge: { stakeTarget = $0 })
                case .ranking:
                    TetrisDuelRankList(store: store, myUserID: myUserID,
                                       clipsOverflowInsteadOfScroll: clipsOverflowInsteadOfScroll)
                }
            }
            .frame(width: TetrisDuelWindowLayout.lobbyListWidth, height: TetrisDuelWindowLayout.bodyHeight,
                   alignment: .top)
            .clipped()
            TetrisDuelLobbySide(store: store, me: me(), myUserID: myUserID,
                                clipsOverflowInsteadOfScroll: clipsOverflowInsteadOfScroll)
                .frame(width: TetrisDuelWindowLayout.lobbySideWidth, height: TetrisDuelWindowLayout.bodyHeight,
                       alignment: .top)
                .clipped()
        }
    }

    // MARK: 대결 (위 띠 + 세 열)

    private func matchView(_ match: TetrisDuelMatchState) -> some View {
        VStack(alignment: .leading, spacing: TetrisDuelWindowLayout.matchTopBarSpacing) {
            TetrisDuelTopBar(store: store, match: match)
                .frame(height: TetrisDuelWindowLayout.matchTopBarHeight)
            HStack(alignment: .top, spacing: TetrisDuelWindowLayout.columnSpacing) {
                VStack(spacing: TetrisDuelWindowLayout.playerCardSpacing) {
                    TetrisDuelMyCard(store: store, face: me())
                        .frame(height: TetrisDuelWindowLayout.playerCardHeight)
                    TetrisDuelBoardView(store: store)
                        .frame(width: TetrisDuelWindowLayout.canvasSize.width,
                               height: TetrisDuelWindowLayout.canvasSize.height)
                }
                .frame(width: TetrisDuelWindowLayout.canvasSize.width)
                TetrisDuelOpponentColumn(store: store, match: match)
                    .frame(width: TetrisDuelWindowLayout.opponentColumnWidth,
                           height: TetrisDuelWindowLayout.matchColumnHeight, alignment: .top)
                TetrisDuelMatchSide(store: store, match: match, confirmResign: $confirmResign,
                                    showsConfirmPreview: previewConfirmResign)
                    .frame(width: TetrisDuelWindowLayout.sideColumnWidth,
                           height: TetrisDuelWindowLayout.matchColumnHeight, alignment: .top)
                    .clipped()
            }
        }
    }
}

/// 로비 왼쪽 열의 탭 — 상대 고르기 · 순위(전적과 순위표 탭).
enum TetrisDuelLobbyTab: Equatable { case users, ranking }

// MARK: - 머리글

private struct TetrisDuelHeader: View {
    let store: TetrisDuelStore
    let onRules: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(CheckTheme.accent.opacity(0.18))
                Image(systemName: TetrisDuelEntryIcon.resolved)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(CheckTheme.accent)
            }
            .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text(TetrisDuelText.title).font(.title3.weight(.bold))
                Text(TetrisDuelText.subtitle)
                    .font(.caption)
                    .foregroundStyle(CheckTheme.secondaryText)
            }
            Spacer(minLength: 12)
            HStack(spacing: 5) {
                Image(systemName: "flag.checkered")
                Text(recordLine).monospacedDigit()
            }
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(Capsule().fill(Color.white.opacity(0.06)))
            .overlay(Capsule().stroke(CheckTheme.border, lineWidth: 1))
            .checkTooltip(TetrisDuelText.rankHelp)
            RubyBalanceChip(balance: store.rubyBalance, large: true)
                .checkTooltip("내 루비")
            TetrisDuelActionButton(title: TetrisDuelText.rulesButton, icon: "book.fill", style: .outline,
                                   height: 30, action: onRules)
                .checkTooltip(TetrisDuelText.rulesHelp)
        }
    }

    /// 전적 캡슐 — 로비 전적이 권위다. 순위 응답의 내 줄이 **같은 전적**일 때만 등수를 덧붙인다(두 출처를 섞지 않는다).
    private var recordLine: String {
        let record = TetrisDuelText.record(store.record)
        guard let mine = store.ranking?.me, let rank = mine.rank, let held = store.record,
              mine.wins == held.wins, mine.losses == held.losses, mine.draws == held.draws
        else { return record }
        return "\(record) · \(rank)위"
    }
}

// MARK: - 로비: 탭 · 상대 목록 · 순위

private struct TetrisDuelLobbyTabs: View {
    let selected: TetrisDuelLobbyTab
    let onSelect: (TetrisDuelLobbyTab) -> Void

    var body: some View {
        HStack(spacing: 6) {
            tab(.users, title: TetrisDuelText.usersTab, icon: "person.2.fill")
            tab(.ranking, title: TetrisDuelText.rankTab, icon: "trophy.fill")
            Spacer(minLength: 4)
        }
    }

    private func tab(_ value: TetrisDuelLobbyTab, title: String, icon: String) -> some View {
        let isOn = selected == value
        return Button { onSelect(value) } label: {
            Label(title, systemImage: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(isOn ? CheckTheme.accent : CheckTheme.secondaryText)
                .padding(.horizontal, 12)
                .frame(height: TetrisDuelWindowLayout.lobbyTabHeight)
                .background(Capsule().fill(isOn ? CheckTheme.accent.opacity(0.20) : Color.white.opacity(0.04)))
                .overlay(Capsule().stroke(isOn ? CheckTheme.accent.opacity(0.55) : CheckTheme.border, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

private struct TetrisDuelOpponentList: View {
    let store: TetrisDuelStore
    let clipsOverflowInsteadOfScroll: Bool
    let onChallenge: (TetrisDuelUser) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 제목은 탭이 이미 말한다("상대 고르기") — 카드는 안내 한 줄만.
            Text(TetrisDuelText.lobbyCaption)
                .font(.caption)
                .foregroundStyle(CheckTheme.secondaryText)
                .lineLimit(1)
            if store.visibleUsers.isEmpty {
                Text(emptyText)
                    .font(.callout)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if store.lobbyLoadFailed {
                    TetrisDuelActionButton(title: TetrisDuelText.reloadUsers, icon: "arrow.clockwise",
                                           style: .outline, height: 30, fullWidth: true) {
                        Task { await store.refreshLobby() }
                    }
                }
            } else {
                TetrisDuelScrollBox(clips: clipsOverflowInsteadOfScroll) {
                    VStack(spacing: TetrisDuelWindowLayout.lobbyRowSpacing) {
                        // 서버 정렬 그대로(스토어 `sortedForLobby` 가 같은 규칙으로 되맞춘다 — 여기서 다시 줄 세우지 않는다).
                        ForEach(store.visibleUsers) { user in
                            TetrisDuelOpponentRow(user: user, isEnabled: canChallenge(user),
                                                  onChallenge: { onChallenge(user) })
                                .frame(height: TetrisDuelWindowLayout.lobbyRowHeight)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .tetrisDuelCard()
    }

    /// [신청] — 서버가 어차피 거절할 상대(구버전 · 대결 중 · 집중)만 끈다. **근무 여부는 보지 않는다**(D1).
    private func canChallenge(_ user: TetrisDuelUser) -> Bool {
        user.canBeChallenged && !store.isBusy && store.availability == .available
    }

    private var emptyText: String {
        switch store.availability {
        case .updateRequired: return TetrisDuelNoticeText.updateMine
        case .serverMissing: return TetrisDuelNoticeText.unavailable
        case .available: break
        }
        if store.lobbyLoadFailed { return TetrisDuelText.usersLoadFailed }
        return store.hasLoadedLobby ? TetrisDuelText.emptyUsers : TetrisDuelText.loadingUsers
    }
}

private struct TetrisDuelOpponentRow: View {
    let user: TetrisDuelUser
    let isEnabled: Bool
    let onChallenge: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            CheckAvatarView(name: user.displayName, userID: user.id,
                            avatarURL: user.avatarURL.flatMap(URL.init(string:)), size: 32,
                            characterHint: user.characterID)
            VStack(alignment: .leading, spacing: 2) {
                Text(user.displayName)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Text(statusLine)
                    .font(.caption2)
                    .foregroundStyle(user.isCapable ? CheckTheme.secondaryText : CheckTheme.pending)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            TetrisDuelActionButton(title: TetrisDuelText.challenge, height: 28, isEnabled: isEnabled,
                                   action: onChallenge)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(CheckTheme.border, lineWidth: 1))
    }

    /// 상태 글자: 구버전 > 대결 중 > 집중 > 근무 중 > "—".
    private var statusLine: String {
        if !user.isCapable { return TetrisDuelText.needsUpdate }
        if user.inMatch { return TetrisDuelText.inMatch }
        if user.isFocused { return TetrisDuelText.focused }
        return user.isWorking ? TetrisDuelText.working : "—"
    }
}

private struct TetrisDuelRankList: View {
    let store: TetrisDuelStore
    let myUserID: String?
    let clipsOverflowInsteadOfScroll: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 제목은 탭이 이미 말한다("순위") — 카드는 승점 산식과 기록 시작일만.
            HStack(alignment: .firstTextBaseline) {
                Text(TetrisDuelText.rankHelp)
                    .font(.caption)
                    .foregroundStyle(CheckTheme.secondaryText)
                Spacer(minLength: 4)
                if let since = store.ranking?.recordSince {
                    Text(TetrisDuelText.rankSince(since))
                        .font(.caption2)
                        .foregroundStyle(CheckTheme.secondaryText)
                        .lineLimit(1)
                }
            }
            if let board = store.ranking, !board.entries.isEmpty {
                TetrisDuelScrollBox(clips: clipsOverflowInsteadOfScroll) {
                    VStack(spacing: 5) {
                        ForEach(board.entries) { entry in
                            TetrisDuelRankRow(entry: entry, isMe: entry.user.id == myUserID)
                                .frame(height: 34)
                        }
                    }
                }
            } else {
                Text(emptyText)
                    .font(.callout)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .tetrisDuelCard()
    }

    private var emptyText: String {
        if store.rankingUnavailable { return TetrisDuelText.rankSoon }
        if store.rankingLoadFailed, !store.hasLoadedRanking { return TetrisDuelText.rankFailed }
        if !store.hasLoadedRanking { return TetrisDuelText.rankLoading }
        return TetrisDuelText.rankEmpty
    }
}

private struct TetrisDuelRankRow: View {
    let entry: TetrisDuelRankEntry
    let isMe: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text("\(entry.rank)")
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .frame(width: 24, alignment: .trailing)
                .foregroundStyle(entry.rank <= 3 ? CheckTheme.pending : CheckTheme.secondaryText)
            CheckAvatarView(name: entry.user.displayName, userID: entry.user.id,
                            avatarURL: entry.user.avatarURL.flatMap(URL.init(string:)), size: 22,
                            characterHint: entry.user.characterID)
            Text(entry.user.displayName)
                .font(.caption.weight(isMe ? .bold : .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 0) {
                Text(TetrisDuelText.points(entry.points))
                    .font(.caption.weight(.bold))
                    .monospacedDigit()
                Text(TetrisDuelText.record(wins: entry.wins, losses: entry.losses, draws: entry.draws))
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .monospacedDigit()
            }
            .frame(width: 96, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isMe ? CheckTheme.accent.opacity(0.14) : Color.white.opacity(0.03))
        )
    }
}

// MARK: - 로비: 오른쪽 열

private struct TetrisDuelLobbySide: View {
    let store: TetrisDuelStore
    let me: ChessPlayerFace
    let myUserID: String?
    let clipsOverflowInsteadOfScroll: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: TetrisDuelWindowLayout.lobbySideSpacing) {
            recordCard
                .frame(height: TetrisDuelWindowLayout.lobbyRecordHeight)
            // "지금 대결 중" 이 남는 높이를 먹는다(최소 `lobbyLiveHeight`) — 신청 칸은 **자연 높이**로 바닥에 붙는다.
            // 신청 칸에 `.frame(maxHeight:)` 를 걸면 그 칸도 늘어나는 칸이 되어 남는 높이를 나눠 갖고, 내용이 그 안에서 정렬돼
            // 간격 위에 빈 띠가 생긴다(첫 두 스틸에서 실측). 예산(`invitesMaxHeight`)은 자연 높이의 상한이고 아래 시험이 잰다.
            liveBox
                .frame(minHeight: TetrisDuelWindowLayout.lobbyLiveHeight, maxHeight: .infinity)
            // ★ 예산을 넘기면 잘린다(부모 열이 `.clipped()` 다) — 예산은 조각을 더해서 낸다(`invitesMaxHeight`).
            TetrisDuelInvitesBox(store: store)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var recordCard: some View {
        HStack(spacing: 10) {
            CharacterPortrait(characterID: me.characterID)
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(TetrisDuelText.recordTitle)
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                Text(TetrisDuelText.record(store.record))
                    .font(.callout.weight(.bold))
                    .monospacedDigit()
            }
            Spacer(minLength: 4)
            if let mine = store.ranking?.me, let record = store.record,
               mine.wins == record.wins, mine.losses == record.losses, mine.draws == record.draws {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(TetrisDuelText.points(mine.points))
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                    if let rank = mine.rank {
                        Text("\(rank)위")
                            .font(.caption2)
                            .foregroundStyle(CheckTheme.secondaryText)
                            .monospacedDigit()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .tetrisDuelCard(padding: 12)
    }

    private var liveBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(TetrisDuelText.liveTitle).font(.headline)
            if store.liveMatches.isEmpty {
                Text(TetrisDuelText.noLive)
                    .font(.caption)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TetrisDuelScrollBox(clips: clipsOverflowInsteadOfScroll) {
                    VStack(spacing: 6) {
                        ForEach(store.liveMatches) { live in
                            TetrisDuelLiveRow(live: live, isMine: isMine(live))
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .tetrisDuelCard()
    }

    private func isMine(_ live: TetrisDuelLiveMatch) -> Bool {
        if live.id == store.match?.id { return true }
        guard let myUserID else { return false }
        return live.a.id == myUserID || live.b.id == myUserID
    }
}

private struct TetrisDuelLiveRow: View {
    let live: TetrisDuelLiveMatch
    let isMine: Bool

    var body: some View {
        HStack(spacing: 8) {
            CheckAvatarView(name: live.a.displayName, userID: live.a.id,
                            avatarURL: live.a.avatarURL.flatMap(URL.init(string:)), size: 18,
                            characterHint: live.a.characterID)
            Text(live.a.displayName).font(.caption2).lineLimit(1)
            Text("vs").font(.caption2).foregroundStyle(CheckTheme.secondaryText)
            CheckAvatarView(name: live.b.displayName, userID: live.b.id,
                            avatarURL: live.b.avatarURL.flatMap(URL.init(string:)), size: 18,
                            characterHint: live.b.characterID)
            Text(live.b.displayName).font(.caption2).lineLimit(1)
            Spacer(minLength: 4)
            if isMine {
                Text(TetrisDuelText.myMatch)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(CheckTheme.secondaryText)
            } else {
                HStack(spacing: 3) {
                    RubyIcon(size: 11)
                    Text("\(live.stake.rawValue)").monospacedDigit()
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(CheckTheme.secondaryText)
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.04)))
    }
}

/// 로비 오른쪽 열 맨 아래 — 받은 신청 1장(가장 최근) + 보낸 신청 줄 + 안내 줄.
/// **내부 타입이다**(private 아님) — 테스트가 예산 안과 자연 높이로 두 번 그려 잉크를 견준다(체스와 같은 규약).
struct TetrisDuelInvitesBox: View {
    let store: TetrisDuelStore

    var body: some View {
        VStack(alignment: .leading, spacing: TetrisDuelWindowLayout.invitesSpacing) {
            HStack(spacing: 6) {
                Text(TetrisDuelText.incomingTitle).font(.headline)
                let more = store.visibleIncomingInvites.count - 1
                if more > 0 {
                    Text(TetrisDuelText.incomingMore(more))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(CheckTheme.secondaryText)
                }
            }
            .frame(height: TetrisDuelWindowLayout.invitesTitleHeight)
            if let invite = store.visibleIncoming {
                TetrisDuelInviteCard(store: store, invite: invite)
            } else {
                Text(TetrisDuelText.noIncoming)
                    .font(.caption)
                    .foregroundStyle(CheckTheme.secondaryText)
            }
            if let outgoing = store.outgoing {
                TetrisDuelOutgoingLine(store: store, invite: outgoing)
            }
            if let notice = store.notice {
                TetrisDuelNoticeLine(text: notice)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .tetrisDuelCard()
    }
}

private struct TetrisDuelInviteCard: View {
    let store: TetrisDuelStore
    let invite: TetrisDuelInvite

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                CheckAvatarView(name: invite.peer.displayName, userID: invite.peer.id,
                                avatarURL: invite.peer.avatarURL.flatMap(URL.init(string:)), size: 28,
                                characterHint: invite.peer.characterID)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(invite.peer.displayName)님의 신청")
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Text(TetrisDuelText.stakeLine(invite.stake))
                        .font(.caption2)
                        .foregroundStyle(CheckTheme.secondaryText)
                        .monospacedDigit()
                }
                Spacer(minLength: 4)
                TetrisDuelCountdownText(expiresAt: invite.expiresAt, isLive: store.isWindowVisible, now: store.clock)
            }
            HStack(spacing: 8) {
                TetrisDuelActionButton(title: TetrisDuelText.accept, height: 28, fullWidth: true,
                                       isEnabled: !store.isBusy) {
                    Task { await store.respond(inviteID: invite.id, accept: true) }
                }
                TetrisDuelActionButton(title: TetrisDuelText.decline, tint: CheckTheme.offWork, style: .outline,
                                       height: 28, fullWidth: true, isEnabled: !store.isBusy) {
                    Task { await store.respond(inviteID: invite.id, accept: false) }
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(CheckTheme.accent.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .stroke(CheckTheme.accent.opacity(0.4), lineWidth: 1))
    }
}

private struct TetrisDuelOutgoingLine: View {
    let store: TetrisDuelStore
    let invite: TetrisDuelInvite

    var body: some View {
        HStack(spacing: 8) {
            Text("\(TetrisDuelText.outgoingTitle) · \(invite.peer.displayName) · \(invite.stake)")
                .font(.caption2)
                .foregroundStyle(CheckTheme.secondaryText)
                .lineLimit(1)
            TetrisDuelCountdownText(expiresAt: invite.expiresAt, isLive: store.isWindowVisible, now: store.clock)
            Spacer(minLength: 4)
            TetrisDuelActionButton(title: TetrisDuelText.cancel, tint: CheckTheme.offWork, style: .outline,
                                   height: 26, isEnabled: !store.isBusy) {
                Task { await store.cancelChallenge() }
            }
        }
        .frame(maxWidth: .infinity, minHeight: TetrisDuelWindowLayout.outgoingLineHeight, alignment: .leading)
    }
}

// MARK: - 대결: 위 띠

private struct TetrisDuelTopBar: View {
    let store: TetrisDuelStore
    let match: TetrisDuelMatchState

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Text(TetrisDuelText.stakeTitle).foregroundStyle(CheckTheme.secondaryText)
                RubyIcon(size: 15)
                Text(TetrisDuelText.stakeLine(match.stake)).monospacedDigit().lineLimit(1)
            }
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 12)
            .frame(height: TetrisDuelWindowLayout.matchTopBarHeight)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(CheckTheme.border, lineWidth: 1))
            TetrisDuelElapsedLeaf(store: store)
            if let floor = store.myStats?.levelFloor, floor > 1, !match.isFinished {
                // 2분이 지나 가속이 걸렸다(D7). 바닥은 10초마다 오르므로 이 칩은 그때만 다시 그려진다(관찰 값).
                HStack(spacing: 5) {
                    Image(systemName: "hare.fill")
                    Text(TetrisDuelText.speedUp)
                    Text(TetrisDuelText.speedLevel(floor)).monospacedDigit().foregroundStyle(CheckTheme.secondaryText)
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(CheckTheme.pending)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(Capsule().fill(CheckTheme.pending.opacity(0.16)))
                .overlay(Capsule().stroke(CheckTheme.pending.opacity(0.45), lineWidth: 1))
                .checkTooltip("2분이 지나면 떨어지는 속도가 점점 빨라져요")
            }
            Spacer(minLength: 4)
            if store.connectionTrouble {
                Label(TetrisDuelText.connectionTrouble, systemImage: "wifi.exclamationmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(CheckTheme.danger)
            }
        }
    }
}

/// 경과 시간 — **잎 뷰**(초를 읽는 것은 여기 TimelineView 뿐이다). 창이 안 보이거나 판이 아니면 멈춘다.
struct TetrisDuelElapsedLeaf: View {
    let store: TetrisDuelStore

    var body: some View {
        let live = store.isWindowVisible && store.phase == .playing
        TimelineView(.animation(minimumInterval: 0.5, paused: !live)) { _ in
            // 끝난 판은 **엔진에 흘린 판 시간**에서 멈춘다 — 단조 시계로 재면 결과 화면에서도 경과가 계속 자란다.
            let elapsed = store.phase == .finished
                ? (store.duel?.simulated ?? 0)
                : max(0, store.matchElapsedSeconds() ?? 0)
            HStack(spacing: 5) {
                Image(systemName: "timer")
                Text(TetrisDuelText.clock(elapsed)).monospacedDigit()
            }
            .font(.callout.weight(.bold))
            .foregroundStyle(CheckTheme.primaryText)
            .padding(.horizontal, 12)
            .frame(height: TetrisDuelWindowLayout.matchTopBarHeight)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.05)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(CheckTheme.border, lineWidth: 1))
            .accessibilityLabel("\(TetrisDuelText.elapsedTitle) \(TetrisDuelText.clock(elapsed))")
        }
    }
}

// MARK: - 대결: 내 카드 · 내 판

private struct TetrisDuelMyCard: View {
    let store: TetrisDuelStore
    let face: ChessPlayerFace

    var body: some View {
        let stats = store.myStats
        HStack(spacing: 10) {
            CharacterPortrait(characterID: face.characterID)
                .frame(width: 34, height: 34)
            HStack(spacing: 6) {
                Text(face.name)
                    .font(.callout.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(TetrisDuelText.me)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(CheckTheme.accent)
                    .padding(.horizontal, 6)
                    .frame(height: 16)
                    .background(Capsule().fill(CheckTheme.accent.opacity(0.18)))
            }
            Spacer(minLength: 4)
            TetrisDuelStat(title: TetrisDuelText.linesTitle, value: stats?.lines ?? 0)
            TetrisDuelStat(title: TetrisDuelText.attackTitle, value: stats?.attackSent ?? 0,
                           tint: CheckTheme.working)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(CheckTheme.panel.opacity(0.9)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(CheckTheme.border, lineWidth: 1))
    }
}

/// 숫자 한 칸(작은 제목 + 큰 숫자).
private struct TetrisDuelStat: View {
    let title: String
    let value: Int
    var tint: Color = CheckTheme.primaryText

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(CheckTheme.secondaryText)
            Text(String(value))
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(tint)
        }
        .frame(minWidth: 44, alignment: .trailing)
    }
}

/// 내 판 — 캔버스 한 장(`TetrisBoardPainter`) + 글자 겹 + 덮개(준비·카운트다운·탑아웃·결과).
///
/// ★ 판은 **이 잎의 TimelineView 안에서만** 읽는다(`store.duel` 은 관찰 대상이 아니다). 프레임마다 `store.tick()` 을
/// 불러 판을 지금까지 미는데, 판 루프가 0.05초마다 같은 일을 하므로 이 틱이 없어도 판은 흐른다(창이 숨으면 이쪽이 멈춘다).
struct TetrisDuelBoardView: View {
    let store: TetrisDuelStore

    /// 판 구동기가 아직 없을 때(시드를 받기 전) 그릴 빈 판.
    private static let placeholder = TetrisGame(seed: 0)

    var body: some View {
        let phase = store.phase
        let live = store.isWindowVisible && (phase == .countdown || phase == .playing)
        TimelineView(.animation(minimumInterval: MiniGameFrameRate.minimumInterval(
            forRefreshRate: MiniGameFrameRateMonitor.shared.refreshHz), paused: !live)) { context in
            let game = store.duel?.game ?? Self.placeholder
            ZStack {
                Canvas(rendersAsynchronously: false) { canvas, size in
                    TetrisBoardPainter.drawGame(game, into: &canvas, size: size)
                }
                hud(game)
                overlay(phase: phase)
            }
            .onChange(of: context.date) { _, _ in
                TetrisDuelKeys.releaseStuckKeys(store: store)
                store.tick()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibility)
    }

    private var accessibility: String {
        let stats = store.myStats
        return "내 판, \(TetrisDuelText.linesTitle) \(stats?.lines ?? 0), \(TetrisDuelText.incomingLinesTitle) "
            + "\(stats?.pendingGarbage ?? 0)"
    }

    // MARK: 글자 겹(솔로와 같은 자리 · 같은 크기 — 점수 대신 공격)

    private func hud(_ game: TetrisGame) -> some View {
        GeometryReader { geo in
            let t = MiniGameProjection(container: geo.size, logicalSize: TetrisLayout.logicalSize)
            ZStack(alignment: .topLeading) {
                place(t, CGRect(x: TetrisLayout.textMinX, y: TetrisLayout.labelY,
                                width: TetrisLayout.columnWidth, height: TetrisLayout.labelHeight)) {
                    caption("홀드")
                }
                place(t, CGRect(x: TetrisLayout.rightColumnX, y: TetrisLayout.labelY,
                                width: TetrisLayout.columnWidth, height: TetrisLayout.labelHeight)) {
                    caption("다음")
                }
                statBlock(t, captionY: TetrisLayout.levelCaptionY, valueY: TetrisLayout.levelValueY,
                          caption: "레벨", value: String(game.difficultyLevel))
                statBlock(t, captionY: TetrisLayout.linesCaptionY, valueY: TetrisLayout.linesValueY,
                          caption: "줄", value: String(game.lines))
                band(t, game: game)
            }
            .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
        }
        .allowsHitTesting(false)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(CheckTheme.secondaryText)
    }

    private func statBlock(_ t: MiniGameProjection, captionY: CGFloat, valueY: CGFloat,
                           caption: String, value: String) -> some View {
        ZStack(alignment: .topLeading) {
            place(t, CGRect(x: TetrisLayout.textMinX, y: captionY,
                            width: TetrisLayout.columnWidth, height: TetrisLayout.captionHeight)) {
                Text(caption)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(CheckTheme.secondaryText)
            }
            place(t, CGRect(x: TetrisLayout.textMinX, y: valueY,
                            width: TetrisLayout.columnWidth, height: TetrisLayout.valueHeight)) {
                Text(value)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(CheckTheme.primaryText)
            }
        }
    }

    /// 하단 밴드: 왼쪽 보낸 공격 · 오른쪽 들어올 줄(미터와 같은 빨강 — 막대가 무엇인지 글자로 한 번 말한다).
    private func band(_ t: MiniGameProjection, game: TetrisGame) -> some View {
        place(t, CGRect(x: TetrisLayout.textMinX, y: TetrisLayout.bandY,
                        width: TetrisLayout.textMaxX - TetrisLayout.textMinX, height: TetrisLayout.bandHeight)) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(TetrisDuelText.attackTitle)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(CheckTheme.secondaryText)
                Text(String(game.attackSentTotal))
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(CheckTheme.working)
                Spacer(minLength: 4)
                if game.pendingGarbageLines > 0 {
                    Text("\(TetrisDuelText.incomingLinesTitle) \(game.pendingGarbageLines)")
                        .font(.system(size: 9, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(TetrisDuelPalette.meterColor)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(TetrisDuelPalette.meterColor.opacity(0.18)))
                        .overlay(Capsule().stroke(TetrisDuelPalette.meterColor.opacity(0.5), lineWidth: 1))
                        .fixedSize()
                }
            }
        }
    }

    private func place<V: View>(_ t: MiniGameProjection, _ rect: CGRect, @ViewBuilder _ content: () -> V) -> some View {
        content()
            .frame(width: rect.width * t.scale, height: rect.height * t.scale, alignment: .leading)
            .position(x: t.x(rect.midX), y: t.y(rect.midY))
    }

    // MARK: 덮개

    @ViewBuilder
    private func overlay(phase: TetrisDuelPhase) -> some View {
        switch phase {
        case .ready:
            let seconds = readySecondsLeft()
            MiniGameOverlayCard(title: TetrisDuelText.waitingTitle,
                                subtitle: TetrisDuelText.waitingSubtitle(seconds: seconds),
                                action: TetrisDuelText.waitingAction,
                                icon: "hourglass", tint: CheckTheme.accent)
        case .countdown:
            let remaining = store.countdownSeconds() ?? 0
            VStack(spacing: 4) {
                Text(String(max(1, Int(remaining.rounded(.up)))))
                    .font(.system(size: 72, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(CheckTheme.primaryText)
                    .shadow(color: .black.opacity(0.6), radius: 6, y: 2)
                Text(TetrisDuelText.startingSoon)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(CheckTheme.secondaryText)
            }
            .accessibilityLabel("\(TetrisDuelText.startingSoon) \(max(1, Int(remaining.rounded(.up))))")
        case .playing:
            if store.myStats?.toppedOut == true {
                MiniGameOverlayCard(title: TetrisDuelText.toppedOutTitle,
                                    subtitle: TetrisDuelText.toppedOutSubtitle,
                                    action: TetrisDuelText.playingNow,
                                    icon: "exclamationmark.triangle.fill", tint: CheckTheme.danger)
            }
        case .finished:
            let outcome = store.match?.outcome
            MiniGameOverlayCard(title: TetrisDuelText.outcomeTitle(outcome),
                                subtitle: TetrisDuelNoticeText.endReason(store.match?.endReason, outcome: outcome),
                                action: TetrisDuelText.rubyDelta(store.match?.rubyDelta ?? 0) + " 루비",
                                icon: TetrisDuelResultCard.icon(outcome),
                                tint: TetrisDuelResultCard.tint(outcome))
        case .lobby:
            EmptyView()
        }
    }

    /// 준비 마감까지 남은 초(스토어 벽시계 — 테스트가 갈아 끼운다). 모르면 30.
    private func readySecondsLeft() -> Int {
        guard let deadline = store.match?.readyDeadline else { return 30 }
        return max(0, Int(deadline.timeIntervalSince(store.clock()).rounded(.up)))
    }
}

// MARK: - 대결: 상대 열

private struct TetrisDuelOpponentColumn: View {
    let store: TetrisDuelStore
    let match: TetrisDuelMatchState

    var body: some View {
        let board = match.opponentBoard
        VStack(spacing: TetrisDuelWindowLayout.playerCardSpacing) {
            HStack(spacing: 8) {
                CheckAvatarView(name: match.opponent.displayName, userID: match.opponent.id,
                                avatarURL: match.opponent.avatarURL.flatMap(URL.init(string:)), size: 30,
                                characterHint: match.opponent.characterID)
                VStack(alignment: .leading, spacing: 1) {
                    Text(match.opponent.displayName)
                        .font(.callout.weight(.bold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                    TetrisDuelOpponentPresence(store: store, board: board, isFinished: match.isFinished)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: TetrisDuelWindowLayout.playerCardHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(CheckTheme.panel.opacity(0.9)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(CheckTheme.border, lineWidth: 1))

            VStack(spacing: 12) {
                // 상대 판 — 스냅숏이 올 때만 바뀌는 관찰 값이라 프레임 루프가 없다.
                Canvas(rendersAsynchronously: false) { canvas, size in
                    TetrisBoardPainter.drawMiniBoard(board.cells, into: &canvas, size: size)
                }
                .frame(width: TetrisMiniBoardLayout.boardSize.width, height: TetrisMiniBoardLayout.boardSize.height)
                .overlay {
                    if board.toppedOut {
                        Text(TetrisDuelText.toppedOutTitle)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(CheckTheme.danger)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.black.opacity(0.65)))
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("상대 판")
                VStack(spacing: 6) {
                    statRow(TetrisDuelText.linesTitle, board.lines, tint: CheckTheme.primaryText)
                    statRow(TetrisDuelText.attackTitle, board.attackSent, tint: CheckTheme.working)
                    statRow(TetrisDuelText.incomingLinesTitle, board.pending,
                            tint: board.pending > 0 ? TetrisDuelPalette.meterColor : CheckTheme.secondaryText)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .tetrisDuelCard(padding: 0)
        }
    }

    private func statRow(_ title: String, _ value: Int, tint: Color) -> some View {
        HStack {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(CheckTheme.secondaryText)
            Spacer(minLength: 4)
            Text(String(value))
                .font(.callout.weight(.heavy))
                .monospacedDigit()
                .foregroundStyle(tint)
        }
    }
}

/// 상대 상태 한 줄 — 준비 · 연결 확인 중(잎 — 침묵 초를 읽는 것은 여기 TimelineView 뿐이다).
struct TetrisDuelOpponentPresence: View {
    let store: TetrisDuelStore
    let board: TetrisDuelOpponentBoard
    let isFinished: Bool

    /// 상대 보고가 이만큼 끊기면 "상대 연결 확인 중" 을 띄운다(서버 판정 15초의 1/3 — 1초 하트비트 서넛을 놓친 자리).
    static let silenceHintSeconds: TimeInterval = 5

    var body: some View {
        TimelineView(.animation(minimumInterval: 1, paused: !store.isWindowVisible || isFinished)) { _ in
            let silent = !isFinished && board.ready && (store.opponentSilenceSeconds() ?? 0) >= Self.silenceHintSeconds
            Text(silent ? TetrisDuelText.opponentSilent : Self.label(board: board, phase: store.phase, isFinished: isFinished))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(silent ? CheckTheme.pending : CheckTheme.secondaryText)
                .lineLimit(1)
        }
    }

    /// "준비 완료" 는 판이 서기 전까지만 — 판 중·끝난 뒤에도 남으면 상대가 아직 안 들어온 것처럼 읽힌다.
    static func label(board: TetrisDuelOpponentBoard, phase: TetrisDuelPhase, isFinished: Bool) -> String {
        if board.toppedOut { return TetrisDuelText.toppedOutTitle }
        if !board.ready { return TetrisDuelText.notReady }
        if isFinished { return TetrisDuelText.finishedPresence }
        return phase == .playing ? TetrisDuelText.playingNow : TetrisDuelText.ready
    }
}

// MARK: - 대결: 오른쪽 열

private struct TetrisDuelMatchSide: View {
    let store: TetrisDuelStore
    let match: TetrisDuelMatchState
    @Binding var confirmResign: Bool
    let showsConfirmPreview: Bool

    private var showsConfirm: Bool { confirmResign || showsConfirmPreview }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if match.isFinished {
                TetrisDuelResultCard(store: store, match: match)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                statusBox
            }
            keysCard
            Spacer(minLength: 0)
            actionRow
                .frame(height: TetrisDuelWindowLayout.actionRowHeight)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var statusBox: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(headline)
                .font(.callout.weight(.bold))
                .foregroundStyle(store.phase == .playing ? CheckTheme.working : CheckTheme.pending)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tetrisDuelCard(padding: 12)
    }

    private var headline: String {
        switch store.phase {
        case .ready: return TetrisDuelText.waitingTitle
        case .countdown: return TetrisDuelText.startingSoon
        case .playing:
            return store.myStats?.toppedOut == true ? TetrisDuelText.toppedOutTitle : TetrisDuelText.playingNow
        case .finished, .lobby: return TetrisDuelText.outcomeTitle(match.outcome)
        }
    }

    private var detail: String? {
        if let notice = store.notice { return notice }
        switch store.phase {
        case .ready: return TetrisDuelText.waitingAction
        case .playing, .countdown: return TetrisDuelText.gameHint
        case .finished, .lobby: return nil
        }
    }

    private var keysCard: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(TetrisDuelText.keysTitle)
                .font(.caption.weight(.bold))
                .foregroundStyle(CheckTheme.secondaryText)
            ForEach(TetrisDuelText.keys, id: \.key) { line in
                HStack(spacing: 8) {
                    Text(line.key)
                        .font(.caption2.weight(.bold))
                        .monospacedDigit()
                        .padding(.horizontal, 6)
                        .frame(minWidth: 58, minHeight: 18)
                        .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.08)))
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(CheckTheme.border, lineWidth: 1))
                    Text(line.action)
                        .font(.caption2)
                        .foregroundStyle(CheckTheme.secondaryText)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tetrisDuelCard(padding: 12)
    }

    @ViewBuilder
    private var actionRow: some View {
        if match.isFinished {
            TetrisDuelActionButton(title: TetrisDuelText.backToLobby, icon: "chevron.left", style: .outline,
                                   height: TetrisDuelWindowLayout.actionRowHeight, fullWidth: true) {
                store.backToLobby()
            }
        } else if showsConfirm {
            HStack(spacing: 8) {
                TetrisDuelActionButton(title: TetrisDuelText.confirmResign, tint: CheckTheme.danger,
                                       height: TetrisDuelWindowLayout.actionRowHeight, fullWidth: true,
                                       isEnabled: !store.isBusy) {
                    confirmResign = false
                    Task { await store.resign() }
                }
                .checkTooltip(TetrisDuelText.resignWarning)
                TetrisDuelActionButton(title: TetrisDuelText.keepPlaying, tint: CheckTheme.offWork, style: .outline,
                                       height: TetrisDuelWindowLayout.actionRowHeight, fullWidth: true) {
                    confirmResign = false
                }
            }
        } else {
            TetrisDuelActionButton(title: TetrisDuelText.resign, icon: "flag.fill", tint: CheckTheme.danger,
                                   style: .outline, height: TetrisDuelWindowLayout.actionRowHeight, fullWidth: true) {
                confirmResign = true
            }
        }
    }
}

/// 결과 카드 — 승/패/무 · 사유(꼭대기 · 기권 · 연결 끊김 · 시간 초과 · 상대가 안 들어옴) · 루비 증감 · [로비로] 는 아래 줄.
struct TetrisDuelResultCard: View {
    let store: TetrisDuelStore
    let match: TetrisDuelMatchState

    static func tint(_ outcome: TetrisDuelOutcome?) -> Color {
        switch outcome {
        case .won?: return CheckTheme.working
        case .lost?: return CheckTheme.danger
        default: return CheckTheme.offWork
        }
    }

    static func icon(_ outcome: TetrisDuelOutcome?) -> String {
        switch outcome {
        case .won?: return "trophy.fill"
        case .lost?: return "xmark.circle.fill"
        default: return "equal.circle.fill"
        }
    }

    /// 루비 증감 — 스토어가 낸 값(승 `DuelFee.winnerNet` · 패 −판돈 · 무 0). 없으면 같은 식으로 다시 낸다.
    private var delta: Int {
        if let rubyDelta = match.rubyDelta { return rubyDelta }
        switch match.outcome {
        case .won?: return DuelFee.winnerNet(stake: match.stake)
        case .lost?: return -match.stake
        default: return 0
        }
    }

    var body: some View {
        let tint = Self.tint(match.outcome)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: Self.icon(match.outcome))
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(tint)
                Text(TetrisDuelText.outcomeTitle(match.outcome))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(tint)
                Spacer(minLength: 4)
                HStack(spacing: 4) {
                    RubyIcon(size: 18)
                    Text(TetrisDuelText.rubyDelta(delta))
                        .font(.title3.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(delta > 0 ? CheckTheme.working
                                         : (delta < 0 ? CheckTheme.danger : CheckTheme.secondaryText))
                }
            }
            Text(TetrisDuelNoticeText.endReason(match.endReason, outcome: match.outcome))
                .font(.caption)
                .foregroundStyle(CheckTheme.secondaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .tetrisDuelCard(padding: 12)
    }
}

// MARK: - 가운데 작은 창들

/// 판돈 고르기. **고르기와 신청이 갈려 있다** — 처음엔 아무것도 안 골라져 있고, 골라야 [신청하기] 가 선다(체스와 같다).
private struct TetrisDuelStakePrompt: View {
    let store: TetrisDuelStore
    let target: TetrisDuelUser
    let initialSelection: TetrisDuelStake?
    let onClose: () -> Void

    @State private var selection: TetrisDuelStake?

    private var chosen: TetrisDuelStake? { selection ?? initialSelection }

    var body: some View {
        TetrisDuelOverlayScrim {
            VStack(spacing: 12) {
                Text(TetrisDuelText.stakePromptTitle(name: target.displayName)).font(.headline)
                Text(chosen.map { TetrisDuelText.stakePromptChosen($0.rawValue) } ?? TetrisDuelText.stakePromptCaption)
                    .font(.caption)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .frame(height: 20)
                HStack(spacing: 10) {
                    ForEach(TetrisDuelStake.allCases, id: \.rawValue) { stake in
                        TetrisDuelStakeButton(stake: stake, isSelected: chosen == stake,
                                              isEnabled: affordable(stake)) {
                            selection = (chosen == stake) ? nil : stake
                        }
                    }
                }
                if let chosen, !affordable(chosen) {
                    Text(TetrisDuelText.stakeShortfall)
                        .font(.caption2)
                        .foregroundStyle(CheckTheme.danger)
                }
                if let chosen, affordable(chosen) {
                    TetrisDuelActionButton(title: TetrisDuelText.challengeWithStake(chosen.rawValue),
                                           icon: "paperplane.fill", height: 34, fullWidth: true,
                                           isEnabled: !store.isBusy) {
                        onClose()
                        Task { await store.challenge(userID: target.id, stake: chosen) }
                    }
                    .keyboardShortcut(.defaultAction)
                } else {
                    TetrisDuelActionButton(title: TetrisDuelText.cancel, tint: CheckTheme.offWork, style: .outline,
                                           height: 34, fullWidth: true, action: onClose)
                        .keyboardShortcut(.cancelAction)
                }
            }
            .padding(20)
            .frame(width: TetrisDuelWindowLayout.stakePromptWidth)
            .tetrisDuelCard(padding: 0)
            // Esc 는 고른 뒤에도 언제나 닫는다(위 [취소] 가 사라지는 갈래가 있으므로 한 번 더 건다).
            .overlay(
                Button(action: onClose) { Color.clear.frame(width: 0, height: 0) }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)
            )
        }
    }

    /// 잔액을 모르면(nil) 막지 않는다 — 서버가 `insufficient` 로 말한다.
    private func affordable(_ stake: TetrisDuelStake) -> Bool {
        guard let balance = store.rubyBalance else { return true }
        return balance >= stake.rawValue
    }
}

private struct TetrisDuelStakeButton: View {
    let stake: TetrisDuelStake
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                RubyIcon(size: 18)
                Text("\(stake.rawValue)")
                    .font(.callout.weight(.bold))
                    .monospacedDigit()
            }
            .foregroundStyle(isSelected ? Color.white : CheckTheme.primaryText)
            .frame(maxWidth: .infinity)
            .frame(height: 62)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? CheckTheme.accent : Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? Color.clear : CheckTheme.border, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
    }
}

/// 규칙 보기 — 사용자 어휘로 다섯 줄.
private struct TetrisDuelRulesOverlay: View {
    let onClose: () -> Void

    var body: some View {
        TetrisDuelOverlayScrim {
            VStack(alignment: .leading, spacing: 10) {
                Text(TetrisDuelText.rulesTitle).font(.headline)
                ForEach(TetrisDuelText.rules, id: \.title) { line in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(line.title).font(.caption.weight(.bold)).foregroundStyle(CheckTheme.accent)
                        Text(line.detail)
                            .font(.caption)
                            .foregroundStyle(CheckTheme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                TetrisDuelActionButton(title: TetrisDuelText.close, style: .outline, height: 32, fullWidth: true,
                                       action: onClose)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(20)
            .frame(width: 520, alignment: .leading)
            .tetrisDuelCard(padding: 0)
        }
    }
}

private struct TetrisDuelOverlayScrim<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            CheckTheme.panelElevated.opacity(0.93)
            content
        }
        .frame(width: TetrisDuelWindowLayout.contentSize.width, height: TetrisDuelWindowLayout.contentSize.height)
    }
}

// MARK: - 공용 조각

/// 신청 만료까지 남은 초 — **잎 뷰**. 창이 안 보이면 멈춘다. '지금' 은 스토어 벽시계(테스트가 갈아 끼운다).
struct TetrisDuelCountdownText: View {
    let expiresAt: Date
    let isLive: Bool
    var now: () -> Date = { Date() }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1, paused: !isLive)) { _ in
            Text(TetrisDuelText.clock(expiresAt.timeIntervalSince(now())))
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(CheckTheme.pending)
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(Capsule().fill(CheckTheme.pending.opacity(0.14)))
        }
    }
}

/// 팝오버 배너의 남은 초 — **잎**(팝오버가 닫혀 창이 비활성이면 멈춘다 — 체스 배너와 같은 규약).
struct TetrisDuelInviteBannerCountdown: View {
    let invite: TetrisDuelInvite
    @Environment(\.controlActiveState) private var controlActiveState

    var body: some View {
        TetrisDuelCountdownText(expiresAt: invite.expiresAt, isLive: controlActiveState != .inactive)
    }
}

/// 팝오버의 **받은 테트리스 신청 배너**(v0.3.60). 체스 배너(`ChessInviteBanner`)와 모양·높이가 같다.
///
/// ★ 이 배너가 없으면 신청을 받은 사람이 팝오버에서 볼 곳이 없다 — 창을 여는 길은 미니게임 머리글 하나뿐이고
///   테트리스 폴링은 창이 보일 때만 돈다.
struct TetrisDuelInviteBanner: View {
    let invite: TetrisDuelInvite
    let onAccept: () -> Void
    let onDecline: () -> Void
    var onOpen: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: TetrisDuelEntryIcon.resolved)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(CheckTheme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(TetrisDuelText.inviteBannerTitle(name: invite.peer.displayName))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(CheckTheme.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    HStack(spacing: 3) {
                        Text(TetrisDuelText.stakeTitle)
                        RubyIcon(size: 11)
                        Text("\(invite.stake) · \(TetrisDuelText.inviteBannerSubtitle)")
                    }
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .lineLimit(1)
                }
                Spacer(minLength: 6)
                TetrisDuelInviteBannerCountdown(invite: invite)
            }
            HStack(spacing: 8) {
                Button(action: onAccept) {
                    Text(TetrisDuelText.accept)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background(RoundedRectangle(cornerRadius: 8).fill(CheckTheme.accent))
                }
                .buttonStyle(.plain)
                .checkTooltip(TetrisDuelText.acceptHelp)
                Button(action: onDecline) {
                    Text(TetrisDuelText.decline)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(CheckTheme.accent)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(CheckTheme.accent.opacity(0.14))
                                .overlay(RoundedRectangle(cornerRadius: 8)
                                    .stroke(CheckTheme.accent.opacity(0.45), lineWidth: 1))
                        )
                }
                .buttonStyle(.plain)
                if let onOpen {
                    Button(action: onOpen) {
                        Text(TetrisDuelText.viewInvite)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(CheckTheme.accent)
                            .frame(maxWidth: .infinity)
                            .frame(height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(CheckTheme.accent.opacity(0.14))
                                    .overlay(RoundedRectangle(cornerRadius: 8)
                                        .stroke(CheckTheme.accent.opacity(0.45), lineWidth: 1))
                            )
                    }
                    .buttonStyle(.plain)
                    .checkTooltip(TetrisDuelText.viewInviteHelp)
                }
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(CheckTheme.accent.opacity(0.16))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(CheckTheme.accent.opacity(0.55), lineWidth: 1)
                )
        )
    }
}

private struct TetrisDuelNoticeLine: View {
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

/// 둥근 사각 버튼(채움/외곽선) — 체스 창과 같은 모양. Menu·Picker 대신 쓴다.
struct TetrisDuelActionButton: View {
    enum Style { case filled, outline }

    let title: String
    var icon: String? = nil
    var tint: Color = CheckTheme.accent
    var style: Style = .filled
    var height: CGFloat = 30
    var fullWidth: Bool = false
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: max(10, height * 0.34), weight: .bold))
                }
                Text(title)
                    .font(height >= 38 ? .callout.weight(.bold) : .caption.weight(.bold))
                    .lineLimit(1)
            }
            .foregroundStyle(style == .filled ? Color.white : tint)
            .padding(.horizontal, 14)
            .frame(maxWidth: fullWidth ? .infinity : nil)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: height * 0.3, style: .continuous)
                    .fill(style == .filled ? tint : tint.opacity(0.14))
            )
            .overlay(
                RoundedRectangle(cornerRadius: height * 0.3, style: .continuous)
                    .stroke(tint.opacity(style == .filled ? 0 : 0.45), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
    }
}

/// 스크롤 칸. 스냅샷에서는 **클립 갈래**로 그린다 — ImageRenderer 는 ScrollView 안을 못 그린다.
private struct TetrisDuelScrollBox<Content: View>: View {
    let clips: Bool
    @ViewBuilder let content: Content

    var body: some View {
        if clips {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipped()
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                content.frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

extension View {
    /// 테트리스 창 카드 크롬(체스 창 카드와 같은 모양).
    func tetrisDuelCard(padding: CGFloat = TetrisDuelWindowLayout.cardPadding) -> some View {
        self
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(CheckTheme.panel.opacity(0.85)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(CheckTheme.border, lineWidth: 1))
    }
}
