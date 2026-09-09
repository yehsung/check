import AppKit
import SwiftUI

// MARK: - 미니게임 창 콘텐츠 (v0.2.46)
//
// 처음엔 팀 카드 자리를 대체하는 팝오버 하위 패널이었다. 실사용에서 "바깥을 클릭하면 판이 날아간다 · 폭 292 가 좁다"가
// 걸려 **별도 창**으로 옮겼다(`CheckMiniGameWindow.swift` 머리 주석). 이 파일은 그 창이 담는 화면이다:
// 종류 칩 + 게임 캔버스 + 오늘 순위. 게임 규칙과 60Hz 상태는 게임 잎 뷰(TimingBarGameView / FlappyGameView)의
// @State 에 갇혀 있고, 이 화면은 입력(클릭·스페이스)을 MiniGameInput 카운터로 접어 넘기고 결과(onFinished)를
// 스토어로 올릴 뿐이다.

/// 미니게임 창의 **고정** 레이아웃(캔버스 · 순위 열 · 무스크롤 행수). 순수 상수 — 결정적 검증 지점.
///
/// **창 크기는 고정이다**(620×420, 리사이즈 불가 — 사용자 결정 2026-09-08: "확대해서 하면 더 쉬워지잖아").
/// 순위표가 걸린 게임이라 캔버스가 사람마다 다르면 겨루는 것이 실력이 아니라 창 크기가 된다. 플래피는 캔버스가
/// 커질수록 같은 시간에 화면이 더 넓게 보여 반응할 여유가 늘고, 타이밍 바는 목표 구간이 픽셀로 넓어져 맞히기 쉬워진다.
/// 그래서 크기를 고정하고, 레이아웃도 계산이 아니라 상수다.
///
/// 가로 2단이다(게임 | 오늘 순위). 처음엔 캔버스 아래에 순위를 세웠는데 "게임 창 밑에 뜨니까 보기 힘들다"는
/// 실사용 지적이 나왔다 — 눈이 세로로 멀어지고, 창을 낮추면 순위부터 잘렸다.
///
/// 산식(전부 아래 상수로 굳어 있다):
///   · 안쪽 = 620−24 × 420−24 = 596 × 396
///   · 순위 열 = **240 고정**(이름 + "나" 칩 + 점수가 안 잘리는 최소치) × 396
///   · 캔버스 폭 = 596 − 12(단 사이) − 240 = 344, 높이 = 344 × 200/292 = 235.6 → **236**
///     (논리 캔버스 292×200 의 비율을 지킨다 — 안 지키면 `MiniGameCanvas.transform` 이 레터박스를 만들어
///      게임이 죽은 여백 안에서만 논다)
///   · 행수 = (396 − 고정분) / 30 을 [2, 10] 으로 조인다. 어제 1등 줄(22)이 있어도 없어도 10 이 나온다
///     (있으면 11.13, 없으면 11.87 → 둘 다 상한 10). 남는 세로는 목록 아래 여백이다.
enum MiniGameWindowLayout {
    /// 창 콘텐츠 크기(고정). 컨트롤러의 min/max 도 이 값 하나를 쓴다 — 두 곳에 적으면 언젠가 갈린다.
    static let contentSize = CGSize(width: 620, height: 420)
    /// 창 안쪽 여백(사방).
    static let contentPadding: CGFloat = 12
    /// 게임 열 ↔ 순위 열 사이.
    static let columnSpacing: CGFloat = 12
    /// 종류 칩 줄(게임 열 맨 위)과 그 아래 간격.
    static let chipRowHeight: CGFloat = 28
    static let chipRowSpacing: CGFloat = 12
    /// 순위 열 고정 폭.
    static let rankWidth: CGFloat = 240
    /// 순위 제목줄 · 어제 1등 줄(둘 다 18, 뒤에 4pt 간격).
    /// 순위 열 머리글 높이. **칩 줄과 같은 값**이어야 두 단의 본문(캔버스 / 어제 1등·순위 목록)이 같은
    /// y 에서 시작한다 — 18 로 두었더니 오른쪽이 18pt 높이 떠 "시작 위치가 안 맞는다"는 지적을 받았다(2026-09-08).
    static let rankHeaderHeight: CGFloat = chipRowHeight
    static let winnerRowHeight: CGFloat = 18
    static let rowGap: CGFloat = 4
    /// 목록 → 요약줄 간격 + 요약줄.
    static let summarySpacing: CGFloat = 8
    static let summaryHeight: CGFloat = 14
    /// 슬림 순위 행 높이·간격.
    static let rowHeight: CGFloat = 26
    static let rowSpacing: CGFloat = 4
    /// 상한 10(순위표는 열 명이면 충분하다). 넘치면 ScrollView 다.
    static let maxVisibleRows = 10
    /// 하한 2(그 아래는 순위표가 아니다). 창이 고정이라 실제로 걸릴 일은 없지만 계산의 바닥은 남겨 둔다.
    static let minVisibleRows = 2

    /// 여백을 뺀 콘텐츠 영역(596×396).
    static var innerSize: CGSize {
        CGSize(width: contentSize.width - contentPadding * 2, height: contentSize.height - contentPadding * 2)
    }

    /// 캔버스(344×368 — 폭은 창에서 순위 열을 뺀 나머지, 높이는 칩 줄 아래 남는 세로 전부).
    ///
    /// 비율을 292:200 으로 고정하면 높이가 236 이 되어 게임 열 아래에 120pt 남는 여백이 생겼다.
    /// 캔버스는 `MiniGameCanvas.transform(in:)` 이 **비율을 유지해 가운데 정렬**하므로(짧은 축 기준 배율),
    /// 그릇이 세로로 길어져도 게임 규칙·난이도는 그대로다 — 위아래로 같은 색 바닥이 더 그려질 뿐이다.
    /// 창이 고정 크기라 이 값도 상수이고, 모두가 같은 캔버스에서 겨룬다.
    static let canvasSize: CGSize = {
        let width: CGFloat = contentSize.width - contentPadding * 2 - columnSpacing - rankWidth
        let height: CGFloat = innerSize.height - chipRowHeight - columnSpacing
        return CGSize(width: width, height: height)
    }()

    /// 순위 열(240×396).
    static var rankSize: CGSize { CGSize(width: rankWidth, height: innerSize.height) }

    /// 순위 열에서 목록을 뺀 고정분.
    static func rankChrome(hasYesterdayRow: Bool) -> CGFloat {
        rankHeaderHeight + chipRowSpacing
            + (hasYesterdayRow ? winnerRowHeight + rowGap : 0)
            + summarySpacing + summaryHeight
    }

    static func listHeight(rows: Int) -> CGFloat {
        guard rows > 0 else { return 0 }
        return CGFloat(rows) * rowHeight + CGFloat(rows - 1) * rowSpacing
    }

    static func visibleRows(hasYesterdayRow: Bool) -> Int {
        let usable = rankSize.height - rankChrome(hasYesterdayRow: hasYesterdayRow)
        let raw = Int(((usable + rowSpacing) / (rowHeight + rowSpacing)).rounded(.down))
        return min(max(raw, minVisibleRows), maxVisibleRows)
    }

    /// 고정 레이아웃. 창 크기 인자가 없다 — 창이 안 바뀌기 때문이다.
    static func layout(hasYesterdayRow: Bool) -> (canvasSize: CGSize, rankSize: CGSize, visibleRows: Int) {
        (canvasSize, rankSize, visibleRows(hasYesterdayRow: hasYesterdayRow))
    }
}

/// 스페이스 키를 게임 입력으로 가로채는 로컬 keyDown 모니터.
///
/// 없으면 스페이스가 다른 것을 누른다(팝오버가 열려 있으면 근무 시작/종료 알약이 첫 포커스를 받는다).
/// 모니터가 먼저 받아 nil 을 돌려주면 그 이벤트는 SwiftUI 에 닿지 않는다. **전역 모니터가 아니다** —
/// 전역 모니터는 우리 앱이 활성일 때 눈이 먼다. 삼키는 범위는 **키 창이 미니게임 창일 때**뿐이라
/// 설정 창·할 일 보드·팝오버의 스페이스는 그대로 흘러간다.
enum MiniGameSpaceKey {
    nonisolated(unsafe) private static var token: Any?
    /// 스페이스 keyCode.
    static let spaceKeyCode: UInt16 = 49

    /// 모니터가 걸려 있는가(헤드리스 검증 지점).
    static var isInstalled: Bool { token != nil }

    /// 건다(멱등). shouldConsume 이 거짓이면 이벤트를 그대로 흘린다.
    /// 모니터를 건다. **이미 걸려 있으면 갈아 끼운다** — 예전에는 `guard token == nil` 로 첫 설치만 살렸는데,
    /// 창을 닫을 때 `onDisappear` 가 오지 않는 경우(AppKit 창은 orderOut 뒤에도 뷰가 살아 있다 — 할 일 보드에서
    /// 실측한 사실이다)가 있어 **죽은 화면의 `action` 을 쥔 모니터가 남았다.** 그 상태로 창을 다시 열면 클릭은
    /// 새 화면으로, 스페이스는 옛 화면으로 가서 "어떤 사람은 스페이스가 되고 어떤 사람은 안 되는" 증상이 된다
    /// (2026-09-09 실사용 제보). 항상 최신 화면의 클로저를 쥐게 갈아 끼운다.
    static func install(shouldConsume: @escaping @MainActor () -> Bool, action: @escaping @MainActor () -> Void) {
        remove()
        armed = action
        token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == spaceKeyCode,
                  event.modifierFlags.intersection([.command, .control, .option]).isEmpty
            else { return event }
            // ★ 키 창 여부로 거르지 않는다. 로컬 모니터는 **우리 앱이 활성일 때만** 이벤트를 받으므로,
            //   여기 도달했다는 것 자체가 "우리 앱이 앞에 있다"는 뜻이다. 그 위에 `isKeyWindow` 를 더 요구했더니
            //   게임 창을 처음 연 직후 — 메뉴바 팝오버가 닫히며 키가 넘어가는 그 짧은 순간 — 스페이스가 통째로
            //   빠졌다("업데이트하고 처음 열어 플레이할 때 스페이스가 안 됐다", 2026-09-09 제보).
            //   창이 실제로 떠 있는지는 아래 shouldConsume(컨트롤러의 창 가시성 + 이 화면의 생존)이 판정한다.
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
        armed = nil
    }

    /// 지금 걸려 있는 모니터가 부를 동작. 창 게이트(키 창·제목)를 통과했을 때 실행되는 바로 그 클로저다 —
    /// 헤드리스 검증이 합성 NSEvent 없이 "어느 화면에 묶여 있는가"를 확인하는 지점이다(합성 이벤트로는
    /// 팝오버·창이 열리지 않는다는 것을 이 저장소가 이미 겪었다).
    nonisolated(unsafe) private static var armed: (@MainActor () -> Void)?

    #if DEBUG
    @MainActor
    static func fireForTesting() { armed?() }
    #endif
}

/// 미니게임 창의 콘텐츠. store 를 통째로 받지만 초 단위 시계(displayNow)는 읽지 않는다 — 60Hz 는 게임 잎 뷰의 TimelineView 안이다.
struct CheckMiniGameWindowView: View {
    let store: WorkTimerStore
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

    var body: some View {
        let layout = MiniGameWindowLayout.layout(hasYesterdayRow: store.miniGameYesterdayWinner != nil)
        // 가로 2단: 왼쪽이 게임(종류 칩 + 캔버스), 오른쪽이 오늘 순위. 순위를 캔버스 **아래**에 두면 눈이 세로로
        // 멀어지고 창을 낮출 때 순위부터 잘린다("게임 창 밑에 뜨니까 보기 힘들다" — 실사용 지적).
        HStack(alignment: .top, spacing: MiniGameWindowLayout.columnSpacing) {
            VStack(spacing: MiniGameWindowLayout.chipRowSpacing) {
                kindChips
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: MiniGameWindowLayout.chipRowHeight)
                canvas(size: layout.canvasSize)
                Spacer(minLength: 0)
            }
            .frame(width: layout.canvasSize.width, alignment: .top)
            rankColumn(visibleRows: layout.visibleRows)
                .frame(width: layout.rankSize.width, alignment: .top)
        }
        .padding(MiniGameWindowLayout.contentPadding)
        .frame(width: MiniGameWindowLayout.contentSize.width, height: MiniGameWindowLayout.contentSize.height, alignment: .topLeading)
        .onAppear { installSpaceKey() }
        .onDisappear { MiniGameSpaceKey.remove() }
        .onChange(of: store.miniGameInterruptToken) { _, _ in
            // 판이 끝났다(창 닫힘·포커스 이동·종류 전환). 눌린 채 끝났어도 래치를 풀어 다음 판의 첫 클릭이 먹히게 한다.
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
    private func canvas(size: CGSize) -> some View {
        ZStack {
            switch store.miniGameKind {
            case .timingBar:
                TimingBarGameView(host: host, input: input)
            case .flappy:
                FlappyGameView(host: host, input: input)
            }
        }
        .frame(width: size.width, height: size.height)
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
        MiniGameSpaceKey.install(
            // 이 화면이 살아 있고 **게임 창이 실제로 화면에 떠 있을 때만** 스페이스를 삼킨다.
            // (키 창 판정은 모니터에서 뺐다 — 창을 막 연 순간 키가 아직 안 넘어와 스페이스가 죽었다.)
            shouldConsume: { CheckMiniGameWindowController.shared.isWindowOnScreen },
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
    private func rankColumn(visibleRows: Int) -> some View {
        // 바깥 간격은 왼쪽 단(칩 줄 → 캔버스)과 같은 값이다. 머리글 높이도 칩 줄과 같아서 두 단의
        // 본문 윗변이 정확히 같은 줄에서 시작한다.
        VStack(spacing: MiniGameWindowLayout.chipRowSpacing) {
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
                    .minimumScaleFactor(0.7)
            }
            .frame(height: MiniGameWindowLayout.rankHeaderHeight)
            VStack(spacing: MiniGameWindowLayout.rowGap) {
            if let winner = store.miniGameYesterdayWinner {
                HStack(spacing: 6) {
                    CheckAvatarView(name: winner.name, avatarURL: winner.avatarURL, size: 16)
                    Text("어제 1등 \(winner.name) · \(winner.score)점")
                        .font(.caption2)
                        .foregroundStyle(CheckTheme.primaryText)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
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
                .frame(height: MiniGameWindowLayout.winnerRowHeight)
            }
            rankList(visibleRows: visibleRows)
            Text(summaryText)
                .font(.caption2)
                .foregroundStyle(CheckTheme.secondaryText)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: MiniGameWindowLayout.summaryHeight)
                .padding(.top, MiniGameWindowLayout.summarySpacing - MiniGameWindowLayout.rowGap)
            Spacer(minLength: 0)
            }
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
        let capHeight = MiniGameWindowLayout.listHeight(rows: visibleRows)
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
        VStack(spacing: MiniGameWindowLayout.rowSpacing) {
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
                .frame(maxWidth: .infinity, minHeight: MiniGameWindowLayout.rowHeight, alignment: .leading)
            } else {
                ForEach(Array(store.miniGameBoard.enumerated()), id: \.element.id) { index, entry in
                    MiniGameRankRow(rank: index + 1, entry: entry, isMe: myUserID != nil && entry.userID == myUserID)
                        .frame(height: MiniGameWindowLayout.rowHeight)
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
