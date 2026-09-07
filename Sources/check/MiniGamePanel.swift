import AppKit
import SwiftUI

// MARK: - 미니게임 패널 (v0.2.46)
//
// 팀 카드 자리를 대체하는 "미니게임" 화면. 리그/토큰/찌르기/개인 기록/울트라와 **같은 뼈대**다(뒤로 + 제목 + PanelDivider + 본문,
// padding 12 + panelStyle). 본문 = 게임 캔버스(292 × h) + 오늘 순위(슬림 행). 게임 규칙·60Hz 상태는 게임 잎 뷰
// (TimingBarGameView / FlappyGameView)의 @State 에 갇혀 있고, 이 패널은 입력(클릭·스페이스)을 MiniGameInput 카운터로
// 접어 넘기고 결과(onFinished)를 스토어로 올릴 뿐이다.

/// 미니게임 패널 본문의 높이 예산(순수 계산 — 결정적 검증 지점).
///
/// 하위 패널 본문(제목 행 구분선 아래 ~ 패널 하단 패딩 위)이 크롬 없이 쓸 수 있는 높이는 425pt 다
/// (창 상한 700 − 본문 밖 크롬 270 − 안전 여유 5, InsightsPanelChromeBudget 과 같은 값). 배너·목표 편집 행이 얹히면
/// (extraChromeHeight) 그만큼 줄여야 하는데, 이 패널은 캔버스(고정 블록)와 순위 목록(행 기반)이 섞여 있어 두 레버를
/// 순서대로 당긴다: ① 목록 행수 4→2 ② 캔버스 높이 200→140(게임은 논리 좌표를 비율 유지로 그리므로 규칙 불변)
/// ③ 그래도 안 되면 순위 섹션을 통째로 숨기고 캔버스만 남긴다(rows 0). 팝오버 창은 위가 고정돼 아래로만 자라므로
/// 상한을 넘기면 푸터(로그아웃/앱 종료)가 화면 밖으로 잘린다 — 그래서 어느 조합에서도 예산 안에 들어가야 한다.
enum MiniGamePanelBudget {
    /// 크롬 없는 본문 예산(pt).
    static let bodyBudget: CGFloat = 425
    /// 캔버스 → 순위 섹션 사이 VStack 간격.
    static let sectionSpacing: CGFloat = 12
    /// 순위 제목줄(18) + 4 + 어제 1등 줄(18) + 4. 어제 줄이 없을 때도 최악 기준으로 센다.
    static let headerHeight: CGFloat = 44
    /// 목록 → 요약줄 간격(8) + 요약줄(14).
    static let summaryHeight: CGFloat = 8 + 14
    /// 슬림 순위 행 높이·간격.
    static let rowHeight: CGFloat = 26
    static let rowSpacing: CGFloat = 4
    /// 크롬 없을 때 무스크롤 행수. 5행이면 424pt 로 여유가 1pt 라 4 로 둔다(200+12+44+116+8+14 = 394).
    static let maxVisibleRows = 4
    /// 캔버스를 줄이기 전에 남기는 최소 행수.
    static let minVisibleRows = 2

    /// 캔버스를 뺀 순위 섹션 고정분(간격 + 제목/어제 줄 + 요약줄).
    static var sectionChrome: CGFloat { sectionSpacing + headerHeight + summaryHeight }

    static func listHeight(rows: Int) -> CGFloat {
        guard rows > 0 else { return 0 }
        return CGFloat(rows) * rowHeight + CGFloat(rows - 1) * rowSpacing
    }

    /// 본문 총 높이(캔버스 h + 순위 섹션). rows 0 이면 섹션이 통째로 빠져 캔버스만 남는다.
    static func bodyHeight(canvasHeight: CGFloat, rows: Int) -> CGFloat {
        guard rows > 0 else { return canvasHeight }
        return canvasHeight + sectionChrome + listHeight(rows: rows)
    }

    /// 얹힌 크롬 높이에 맞춘 (캔버스 높이, 무스크롤 행수).
    static func layout(extraChromeHeight: CGFloat) -> (canvasHeight: CGFloat, visibleRows: Int) {
        let available = bodyBudget - max(0, extraChromeHeight)
        // ① 캔버스는 그대로 두고 행수만 줄여 본다(4 → 2).
        for rows in stride(from: maxVisibleRows, through: minVisibleRows, by: -1)
        where bodyHeight(canvasHeight: MiniGameCanvas.preferredHeight, rows: rows) <= available {
            return (MiniGameCanvas.preferredHeight, rows)
        }
        // ② 최소 행수에서 캔버스가 양보한다(하한 140).
        let shrunk = available - sectionChrome - listHeight(rows: minVisibleRows)
        if shrunk >= MiniGameCanvas.minimumHeight {
            return (min(MiniGameCanvas.preferredHeight, shrunk), minVisibleRows)
        }
        // ③ 순위 섹션을 숨기고 캔버스만 남긴다(캔버스는 예산 안에서 최대, 하한 140 은 지킨다).
        let canvasOnly = min(MiniGameCanvas.preferredHeight, max(MiniGameCanvas.minimumHeight, available))
        return (canvasOnly, 0)
    }
}

/// 스페이스 키를 게임 입력으로 가로채는 로컬 keyDown 모니터. 팝오버가 열리면 근무 시작/종료 알약(WorkTogglePill)이
/// 첫 포커스를 받으므로, 이 모니터가 없으면 "스페이스로 점프"가 근무를 켜고 끈다. 모니터가 먼저 받아 nil 을 돌려주면
/// 그 이벤트는 SwiftUI 에 닿지 않는다. **전역 모니터가 아니다** — 전역 모니터는 우리 앱이 활성일 때 눈이 먼다.
/// 소비 조건은 호출부 클로저가 정한다(팝오버가 열려 있고 이 패널이 보일 때만) — 설정 창·할 일 보드의 스페이스는 건드리지 않는다.
enum MiniGameSpaceKey {
    nonisolated(unsafe) private static var token: Any?
    /// 스페이스 keyCode.
    static let spaceKeyCode: UInt16 = 49

    /// 모니터가 걸려 있는가(헤드리스 검증 지점).
    static var isInstalled: Bool { token != nil }

    /// 건다(멱등). shouldConsume 이 거짓이면 이벤트를 그대로 흘린다.
    static func install(shouldConsume: @escaping @MainActor () -> Bool, action: @escaping @MainActor () -> Void) {
        guard token == nil else { return }
        token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == spaceKeyCode,
                  event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
                  let window = event.window, window.isKeyWindow
            else { return event }
            // 키 반복(누르고 있기)은 삼키기만 한다 — 점프 연타가 되면 게임이 아니다.
            let isRepeat = event.isARepeat
            let consumed = MainActor.assumeIsolated { () -> Bool in
                guard shouldConsume() else { return false }
                if !isRepeat { action() }
                return true
            }
            return consumed ? nil : event
        }
    }

    static func remove() {
        if let token { NSEvent.removeMonitor(token) }
        token = nil
    }
}

/// 미니게임 패널. store 를 통째로 받지만 초 단위 시계(displayNow)는 읽지 않는다 — 60Hz 는 게임 잎 뷰의 TimelineView 안이다.
struct MiniGamePanel: View {
    let store: WorkTimerStore
    /// 목록 위쪽에서 배너/목표 편집 행이 먹은 높이(pt). 그만큼 행수·캔버스가 양보한다(MiniGamePanelBudget).
    var extraChromeHeight: CGFloat = 0
    /// 스냅샷 전용: 초과 리스트를 ScrollView 대신 클립으로 그린다(ImageRenderer 육안 확인용). 앱은 false.
    var clipsOverflowInsteadOfScroll: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 클릭·스페이스를 접은 입력 카운터. 게임 잎 뷰는 "늘었다"만 본다.
    @State private var input = MiniGameInput()
    /// 마우스 다운 래치 — DragGesture(minimumDistance: 0) 의 onChanged 는 누르고 있는 동안 계속 오므로 첫 호출만 입력으로 센다.
    @State private var pressLatched = false
    /// 게임 진행 중(잎 뷰가 알려 준다). 진행 중엔 종류 칩을 잠가 실수로 판을 날리지 않게 한다.
    @State private var isPlaying = false

    static let title = "미니게임"
    static let rankTitle = "오늘 순위"
    static let prizeCaption = "자정에 1등은 울트라 찌르기 +10"
    static let emptyBoard = "아직 기록이 없어요 — 첫 기록의 주인공이 되세요"
    static let loadingCaption = "불러오는 중…"
    static let failedCaption = "순위를 불러오지 못했어요"
    static let awardedChip = "+10 받음"

    private var layout: (canvasHeight: CGFloat, visibleRows: Int) {
        MiniGamePanelBudget.layout(extraChromeHeight: extraChromeHeight)
    }

    var body: some View {
        let layout = layout
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                IconButton(icon: "chevron.left", help: "뒤로") { store.closeMiniGamePanel() }
                Text(Self.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(CheckTheme.primaryText)
                    .lineLimit(1)
                Spacer(minLength: 6)
                kindChips
            }
            PanelDivider()
            canvas(height: layout.canvasHeight)
            if layout.visibleRows > 0 {
                rankSection(visibleRows: layout.visibleRows)
            }
        }
        .padding(12)
        .panelStyle()
        .onAppear { installSpaceKey() }
        .onDisappear { MiniGameSpaceKey.remove() }
        .onChange(of: store.miniGameInterruptToken) { _, _ in
            // 판이 끝났다(팝오버 닫힘·종류 전환). 눌린 채 닫혔어도 래치를 풀어 다음 판의 첫 클릭이 먹히게 한다.
            pressLatched = false
            isPlaying = false
        }
    }

    // MARK: 종류 칩

    private var kindChips: some View {
        HStack(spacing: 4) {
            ForEach(MiniGameKind.allCases) { kind in
                MiniGameKindChip(
                    title: kind.title,
                    isSelected: kind == store.miniGameKind,
                    isEnabled: !isPlaying || kind == store.miniGameKind
                ) {
                    store.selectMiniGame(kind)
                }
            }
        }
    }

    // MARK: 캔버스

    private var host: MiniGameHost {
        let kind = store.miniGameKind
        return MiniGameHost(
            bestScore: store.miniGameBest(kind),
            reduceMotion: reduceMotion,
            interruptToken: store.miniGameInterruptToken,
            onFinished: { score in store.recordMiniGameScore(kind: kind, score: score) },
            onPlayingChanged: { playing in isPlaying = playing }
        )
    }

    @ViewBuilder
    private func canvas(height: CGFloat) -> some View {
        ZStack {
            switch store.miniGameKind {
            case .timingBar:
                TimingBarGameView(host: host, input: input)
            case .flappy:
                FlappyGameView(host: host, input: input)
            }
        }
        .frame(width: MiniGameCanvas.logicalWidth, height: height)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(CheckTheme.fieldFill))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(CheckTheme.border, lineWidth: 1))
        .contentShape(Rectangle())
        // 마우스 **다운**에 반응한다(Button/onTapGesture 는 마우스 업 발화 — 점프 게임엔 그 지연이 곧 낙차다).
        // 커서가 밖으로 나가도 onChanged 가 계속 오므로 래치로 1회만 센다.
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !pressLatched else { return }
                    pressLatched = true
                    input.actionCount += 1
                }
                .onEnded { _ in pressLatched = false }
        )
        .accessibilityLabel("\(store.miniGameKind.title) 캔버스 — 클릭 또는 스페이스로 조작")
    }

    private func installSpaceKey() {
        let store = store
        MiniGameSpaceKey.install(
            // 팝오버가 열려 있고(키 창) 이 패널이 보일 때만 삼킨다 — 설정 창·할 일 보드에서의 스페이스는 그대로 흘린다.
            shouldConsume: { store.isMenuPresented && store.isMiniGamePanelVisible },
            action: { input.actionCount += 1 }
        )
    }

    // MARK: 오늘 순위

    private var myUserID: String? { store.session?.userID }

    /// 내 오늘 순위(1부터). 순위 밖/없음이면 nil.
    private var myRank: Int? {
        guard let me = myUserID, let index = store.miniGameBoard.firstIndex(where: { $0.userID == me }) else { return nil }
        return index + 1
    }

    @ViewBuilder
    private func rankSection(visibleRows: Int) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Text(Self.rankTitle)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(CheckTheme.secondaryText)
                Spacer(minLength: 4)
                Image(systemName: "trophy.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(CheckTheme.working)
                Text(Self.prizeCaption)
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(height: 18)
            if let winner = store.miniGameYesterdayWinner {
                HStack(spacing: 6) {
                    CheckAvatarView(name: winner.name, avatarURL: winner.avatarURL, size: 16)
                    Text("어제 1등 \(winner.name) · \(winner.score)점")
                        .font(.caption2)
                        .foregroundStyle(CheckTheme.primaryText)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if winner.awarded {
                        Text(Self.awardedChip)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(CheckTheme.working)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(CheckTheme.working.opacity(0.18)))
                            .fixedSize()
                    }
                    Spacer(minLength: 0)
                }
                .frame(height: 18)
            }
            rankList(visibleRows: visibleRows)
            Text(summaryText)
                .font(.caption2)
                .foregroundStyle(CheckTheme.secondaryText)
                .monospacedDigit()
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 14)
                .padding(.top, 4)
        }
    }

    /// "내 최고 N점 · 오늘 M위". 오늘 순위에 없으면 앞 절만. 최고는 로컬 캐시와 오늘 내 행 중 큰 쪽이다 — 순위 응답이
    /// 로컬을 올리기 전 첫 프레임에도 "최고 0점 · 오늘 953점" 같은 모순을 그리지 않는다.
    private var summaryText: String {
        let kind = store.miniGameKind
        let mine = myUserID.flatMap { me in store.miniGameBoard.first { $0.userID == me } }
        let best = max(store.miniGameBest(kind), mine?.bestScore ?? 0)
        if let rank = myRank { return "내 최고 \(best)점 · 오늘 \(rank)위" }
        return "내 최고 \(best)점"
    }

    private var rowCount: Int { max(1, store.miniGameBoard.count) }

    @ViewBuilder
    private func rankList(visibleRows: Int) -> some View {
        let capHeight = MiniGamePanelBudget.listHeight(rows: visibleRows)
        if rowCount <= visibleRows {
            rows.frame(maxWidth: .infinity, alignment: .top)
        } else if clipsOverflowInsteadOfScroll {
            // 스냅샷 전용: ImageRenderer 는 ScrollView 안쪽을 못 그린다(다른 패널과 같은 우회).
            rows.frame(maxWidth: .infinity, alignment: .top)
                .frame(height: capHeight, alignment: .top)
                .clipped()
        } else {
            ScrollView(.vertical, showsIndicators: true) {
                rows.frame(maxWidth: .infinity)
            }
            .frame(height: capHeight)
        }
    }

    @ViewBuilder
    private var rows: some View {
        VStack(spacing: MiniGamePanelBudget.rowSpacing) {
            if store.miniGameBoard.isEmpty {
                HStack(spacing: 8) {
                    Text(emptyText)
                        .font(.caption2)
                        .foregroundStyle(CheckTheme.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 4)
                    if store.miniGameBoardFailed, !store.miniGameBoardLoaded {
                        MiniGameRetryButton { store.loadMiniGameBoard() }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: MiniGamePanelBudget.rowHeight, alignment: .leading)
            } else {
                ForEach(Array(store.miniGameBoard.enumerated()), id: \.element.id) { index, entry in
                    MiniGameRankRow(rank: index + 1, entry: entry, isMe: myUserID != nil && entry.userID == myUserID)
                        .frame(height: MiniGamePanelBudget.rowHeight)
                }
            }
        }
    }

    /// 빈 목록 문구: 실패 → 실패 문구, 로드 전 진행중 → 불러오는 중, 로드 성공 → 아직 없음.
    private var emptyText: String {
        if store.miniGameBoardFailed, !store.miniGameBoardLoaded { return Self.failedCaption }
        if !store.miniGameBoardLoaded { return Self.loadingCaption }
        return Self.emptyBoard
    }
}

/// 게임 종류 칩(caption2 semibold). 선택 = accent 캡슐, 비선택 = secondaryText.
private struct MiniGameKindChip: View {
    let title: String
    let isSelected: Bool
    var isEnabled: Bool = true
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(isSelected ? CheckTheme.accent : CheckTheme.secondaryText)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(isSelected ? CheckTheme.accent.opacity(0.18) : Color.white.opacity(hovering ? 0.10 : 0.04))
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
        .onHover { hovering = $0 }
        .help(title)
    }
}

/// 오늘 순위 슬림 행(26pt): 순위 · 아바타 20 · 이름(+"나" 칩) · 우측 "N점". 내 행은 accent 테두리.
struct MiniGameRankRow: View {
    let rank: Int
    let entry: MiniGameBoardEntry
    var isMe: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Text("\(rank)")
                .font(.caption2)
                .foregroundStyle(CheckTheme.secondaryText)
                .monospacedDigit()
                .frame(width: 18, alignment: .trailing)
            CheckAvatarView(name: entry.name, avatarURL: entry.avatarURL, size: 20)
            Text(entry.name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(CheckTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            if isMe {
                Text("나")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(CheckTheme.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(CheckTheme.accent.opacity(0.18)))
                    .fixedSize()
            }
            Spacer(minLength: 4)
            Text("\(entry.bestScore)점")
                .font(.caption.weight(.bold))
                .foregroundStyle(CheckTheme.primaryText)
                .monospacedDigit()
                .lineLimit(1)
        }
        .padding(.leading, 4)
        .padding(.trailing, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(CheckTheme.fieldFill))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isMe ? CheckTheme.accent.opacity(0.45) : CheckTheme.border, lineWidth: 1)
        )
    }
}

/// [다시 시도] — CheckMenuView 의 PanelRetryButton 과 같은 수치(그쪽은 private).
private struct MiniGameRetryButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("다시 시도", systemImage: "arrow.clockwise")
                .font(.caption2.weight(.bold))
                .foregroundStyle(CheckTheme.accent)
                .padding(.horizontal, 9)
                .frame(height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(CheckTheme.accent.opacity(0.14))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(CheckTheme.accent.opacity(0.35), lineWidth: 1))
                )
                .fixedSize()
        }
        .buttonStyle(.plain)
    }
}
