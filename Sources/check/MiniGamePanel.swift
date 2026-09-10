import AppKit
import SwiftUI

// MARK: - 미니게임 창 콘텐츠 (v0.2.46 → v0.2.48 개편)
//
// 처음엔 팀 카드 자리를 대체하는 팝오버 하위 패널이었다. 실사용에서 "바깥을 클릭하면 판이 날아간다 · 폭 292 가 좁다"가
// 걸려 **별도 창**으로 옮겼다(`CheckMiniGameWindow.swift` 머리 주석). 이 파일은 그 창이 담는 화면이다:
// 게임 열(헤더 · 캔버스 · 하단 스트립) + 순위 열. 게임 규칙과 60Hz 상태는 게임 잎 뷰(TimingBarGameView /
// FlappyGameView)의 @State 에 갇혀 있고, 이 화면은 입력(클릭·스페이스)을 MiniGameInput 카운터로 접어 넘기고
// 결과(onFinished)를 스토어로 올릴 뿐이다.
//
// v0.2.48 에서 두 가지가 더 붙었다(사용자 지적 2026-09-10).
//   · **일시정지**: "게임 도중에 그냥 포기하고 다른 게임 하고 싶을 때 멈추는 게 안 되네." 정지 상태는 **허브가**
//     소유하고(`CheckMiniGameWindowView.PauseState`) 게임에는 `MiniGameHost.isPaused` 한 줄로만 건넨다.
//     정지 화면(스크림·카드·카운트다운)도 허브가 캔버스 **위에** 그린다 — 게임마다 따로 그리면 두 벌이 되어 언젠가 갈린다.
//   · **크롬 개편**: "미니게임 창 자체도 좀 꾸며줘. 순위 쪽도 그렇고 전체적인 디자인이 너무 마음에 안 들어."
//     창을 620×420 → 700×470 으로 넓혔지만 **캔버스는 344×356 그대로**다(아래 상수 주석).

/// 미니게임 창의 **고정** 레이아웃(캔버스 · 순위 열 · 무스크롤 행수). 순수 상수 — 결정적 검증 지점.
///
/// **창 크기는 고정이다**(700×470, 리사이즈 불가 — 사용자 결정 2026-09-08: "확대해서 하면 더 쉬워지잖아").
/// 순위표가 걸린 게임이라 캔버스가 사람마다 다르면 겨루는 것이 실력이 아니라 창 크기가 된다.
///
/// ★ v0.2.48 에 창을 620×420 → 700×470 으로 넓혔지만 **캔버스는 344×356 그대로 상수**다. 넓힌 것은 크롬(여백 ·
/// 헤더 · 하단 스트립 · 순위 열)뿐이다. 캔버스가 커지면 플래피는 같은 시간에 화면이 더 넓게 보여 반응할 여유가 늘고,
/// 타이밍 바는 목표 구간이 픽셀로 넓어져 **모두가 같은 조건에서 겨룬다는 전제가 깨진다**. 그래서 계산 방향을 뒤집었다:
/// 예전에는 `canvasSize` 가 창 크기에서 계산되고 순위 열이 상수였는데, 지금은 **캔버스가 상수이고 순위 열이 나머지**다.
/// 창을 또 넓히면 늘어나는 것은 순위 열뿐이다.
///
/// 가로 2단이다(게임 | 오늘 순위). 처음엔 캔버스 아래에 순위를 세웠는데 "게임 창 밑에 뜨니까 보기 힘들다"는
/// 실사용 지적이 나왔다 — 눈이 세로로 멀어지고, 창을 낮추면 순위부터 잘렸다.
///
/// 산식(전부 아래 상수로 굳어 있다):
///   · 안쪽 = 700−28 × 470−28 = 672 × 442
///   · 게임 열 = 344(= 캔버스 폭, 상수) × [헤더 32 + 10 + 캔버스 356 + 10 + 하단 스트립 32 = 440] ≤ 442
///   · 순위 열 = 672 − 14(단 사이) − 344 = **314** × 442
///   · 무스크롤 행수 = 어제 챔피언 카드가 있으면 9, 없으면 10. 넘치면 ScrollView.
enum MiniGameWindowLayout {
    /// 창 콘텐츠 크기(고정). 컨트롤러의 min/max 도 이 값 하나를 쓴다 — 두 곳에 적으면 언젠가 갈린다.
    static let contentSize = CGSize(width: 700, height: 470)
    /// 창 안쪽 여백(사방).
    static let contentPadding: CGFloat = 14
    /// 게임 열 ↔ 순위 열 사이.
    static let columnSpacing: CGFloat = 14

    /// 두 단의 머리글 높이. **같은 값이어야** 두 단의 본문(캔버스 / 어제 챔피언·순위 목록)이 같은 y 에서 시작한다 —
    /// 예전에 오른쪽만 18 로 두었더니 "시작 위치가 안 맞는다"는 지적을 받았다(2026-09-08). 아래 `headerSpacing` 도
    /// 두 단이 공유한다. 둘 중 하나만 바꾸면 그 지적이 그대로 재발한다.
    static let headerHeight: CGFloat = 32
    static let headerSpacing: CGFloat = 10

    /// 캔버스 ↔ 하단 스트립 사이, 그리고 하단 스트립 높이(게임 열).
    static let canvasFooterSpacing: CGFloat = 10
    static let footerStripHeight: CGFloat = 32

    /// 어제 챔피언 카드(있을 때만)와 그 아래 간격.
    static let championHeight: CGFloat = 48
    static let championSpacing: CGFloat = 8

    /// 순위 행 높이·간격.
    static let rowHeight: CGFloat = 30
    static let rowSpacing: CGFloat = 5

    /// 순위 열 바닥 안내(2줄)와 그 위 간격.
    /// **28 이 상한이다**: 여기를 키우면 rankChrome 이 커져 무스크롤 행수가 9 → 8 로 떨어진다.
    static let prizeSpacing: CGFloat = 6
    static let prizeHeight: CGFloat = 28

    /// 두 단의 **바닥을 같은 줄에 세우기 위한** 꼬리 여백. 게임 열은 header+캔버스+스트립이 440 에서 끝나고
    /// 안쪽 높이는 442 다 — 순위 열도 이만큼 남겨야 두 바닥이 한 띠로 읽힌다.
    static var footerBaselineGap: CGFloat { max(0, innerSize.height - gameColumnHeight) }

    /// 상한 10(순위표는 열 명이면 충분하다). 넘치면 ScrollView 다.
    static let maxVisibleRows = 10
    /// 하한 2(그 아래는 순위표가 아니다). 창이 고정이라 실제로 걸릴 일은 없지만 계산의 바닥은 남겨 둔다.
    static let minVisibleRows = 2

    /// 여백을 뺀 콘텐츠 영역(672×442).
    static var innerSize: CGSize {
        CGSize(width: contentSize.width - contentPadding * 2, height: contentSize.height - contentPadding * 2)
    }

    /// 캔버스 **344×356 — 상수다.** 창 크기에서 계산하지 마라.
    ///
    /// 논리 판 292×302 와 **같은 비율**이다: 344/356 = 0.9663 vs 292/302 = 0.9669 — 레터박스는 0.11pt 뿐이다.
    /// 배율은 짧은 축이 정하고(`MiniGameCanvas.transform(in:logicalSize:)`), 그래서 **캔버스를 흔들면 두 게임의
    /// 난이도가 함께 흔들린다** — 플래피는 반응할 여유가 늘고 타이밍 바는 목표 구간이 픽셀로 넓어진다.
    /// 이 값이 흔들리면 순위표에 남은 모든 기록의 의미가 갈린다(사용자 결정 2026-09-08).
    /// (예전 주석은 "논리 캔버스 292×200 과 비율이 다르다 · 위아래로 바닥이 더 그려질 뿐"이라고 적혀 있었다.
    ///  그 60pt 레터박스가 v0.2.48 개편이 없앤 결함이고, 200 을 쓰는 게임은 이제 없다.)
    static let canvasSize = CGSize(width: 344, height: 356)

    /// 순위 열 폭 = 안쪽 폭에서 캔버스와 단 사이를 뺀 **나머지**(314). 창을 넓히면 여기만 자란다.
    static var rankWidth: CGFloat { innerSize.width - columnSpacing - canvasSize.width }

    /// 순위 열(314×442).
    static var rankSize: CGSize { CGSize(width: rankWidth, height: innerSize.height) }

    /// 게임 열 세로 합(헤더 + 캔버스 + 하단 스트립). 안쪽 높이를 넘으면 창 밖으로 잘린다.
    static var gameColumnHeight: CGFloat {
        headerHeight + headerSpacing + canvasSize.height + canvasFooterSpacing + footerStripHeight
    }

    /// 순위 열에서 목록을 뺀 고정분.
    static func rankChrome(hasChampionRow: Bool) -> CGFloat {
        headerHeight + headerSpacing
            + (hasChampionRow ? championHeight + championSpacing : 0)
            + prizeSpacing + prizeHeight
    }

    static func listHeight(rows: Int) -> CGFloat {
        guard rows > 0 else { return 0 }
        return CGFloat(rows) * rowHeight + CGFloat(rows - 1) * rowSpacing
    }

    static func visibleRows(hasChampionRow: Bool) -> Int {
        let usable = rankSize.height - rankChrome(hasChampionRow: hasChampionRow)
        let raw = Int(((usable + rowSpacing) / (rowHeight + rowSpacing)).rounded(.down))
        return min(max(raw, minVisibleRows), maxVisibleRows)
    }

    /// 고정 레이아웃. 창 크기 인자가 없다 — 창이 안 바뀌기 때문이다.
    static func layout(hasChampionRow: Bool) -> (canvasSize: CGSize, rankSize: CGSize, visibleRows: Int) {
        (canvasSize, rankSize, visibleRows(hasChampionRow: hasChampionRow))
    }
}

/// 스페이스(점프·시작)와 ESC(일시정지)를 게임 입력으로 가로채는 로컬 keyDown 모니터.
///
/// 없으면 스페이스가 다른 것을 누른다(팝오버가 열려 있으면 근무 시작/종료 알약이 첫 포커스를 받는다).
/// 모니터가 먼저 받아 nil 을 돌려주면 그 이벤트는 SwiftUI 에 닿지 않는다. **전역 모니터가 아니다** —
/// 전역 모니터는 우리 앱이 활성일 때 눈이 먼다.
///
/// v0.2.48 에 ESC 를 **같은 모니터**에 얹었다. 두 벌을 걸면 설치·제거 규약이 두 곳이 되어 아래 두 실사용 버그가
/// 한쪽에서만 고쳐진 채 남는다. 다만 스페이스와 달리 ESC 는 **처리했을 때만 삼킨다**(onEscape 의 반환값) —
/// 시작 전·결과 화면처럼 정지할 판이 없을 때까지 ESC 를 먹으면 다른 화면의 취소 키를 훔친다.
enum MiniGameSpaceKey {
    nonisolated(unsafe) private static var token: Any?
    /// 스페이스 keyCode.
    static let spaceKeyCode: UInt16 = 49
    /// ESC keyCode(일시정지 토글).
    static let escapeKeyCode: UInt16 = 53

    /// 모니터가 걸려 있는가(헤드리스 검증 지점).
    static var isInstalled: Bool { token != nil }

    /// 건다(멱등). shouldConsume 이 거짓이면 이벤트를 그대로 흘린다.
    /// 모니터를 건다. **이미 걸려 있으면 갈아 끼운다** — 예전에는 `guard token == nil` 로 첫 설치만 살렸는데,
    /// 창을 닫을 때 `onDisappear` 가 오지 않는 경우(AppKit 창은 orderOut 뒤에도 뷰가 살아 있다 — 할 일 보드에서
    /// 실측한 사실이다)가 있어 **죽은 화면의 `action` 을 쥔 모니터가 남았다.** 그 상태로 창을 다시 열면 클릭은
    /// 새 화면으로, 스페이스는 옛 화면으로 가서 "어떤 사람은 스페이스가 되고 어떤 사람은 안 되는" 증상이 된다
    /// (2026-09-09 실사용 제보). 항상 최신 화면의 클로저를 쥐게 갈아 끼운다.
    ///
    /// - Parameter onEscape: ESC 처리기. **참을 돌려준 경우에만** 이벤트를 삼킨다(기본값은 "안 씀").
    static func install(shouldConsume: @escaping @MainActor () -> Bool,
                        action: @escaping @MainActor () -> Void,
                        onEscape: @escaping @MainActor () -> Bool = { false }) {
        remove()
        armed = action
        armedEscape = onEscape
        token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let isEscape = event.keyCode == escapeKeyCode
            guard event.keyCode == spaceKeyCode || isEscape,
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
                guard !isRepeat else { return true }
                // ESC 는 화면이 실제로 정지/재개를 했을 때만 삼킨다 — 아니면 그대로 흘려 보낸다.
                if isEscape { return onEscape() }
                action()
                return true
            }
            return consumed ? nil : event
        }
    }

    static func remove() {
        if let token { NSEvent.removeMonitor(token) }
        token = nil
        armed = nil
        armedEscape = nil
    }

    /// 지금 걸려 있는 모니터가 부를 동작. 창 게이트(창 가시성)를 통과했을 때 실행되는 바로 그 클로저다 —
    /// 헤드리스 검증이 합성 NSEvent 없이 "어느 화면에 묶여 있는가"를 확인하는 지점이다(합성 이벤트로는
    /// 팝오버·창이 열리지 않는다는 것을 이 저장소가 이미 겪었다).
    nonisolated(unsafe) private static var armed: (@MainActor () -> Void)?
    /// 같은 모니터가 쥔 ESC 처리기(반환값 = 삼켰는가).
    nonisolated(unsafe) private static var armedEscape: (@MainActor () -> Bool)?

    #if DEBUG
    @MainActor
    static func fireForTesting() { armed?() }

    /// ESC 발화(반환값 = 화면이 처리했는가 = 삼켰는가).
    @MainActor
    @discardableResult
    static func fireEscapeForTesting() -> Bool { armedEscape?() ?? false }
    #endif
}

/// 미니게임 창의 콘텐츠. store 를 통째로 받지만 초 단위 시계(displayNow)는 읽지 않는다 — 60Hz 는 게임 잎 뷰의 TimelineView 안이다.
struct CheckMiniGameWindowView: View {
    /// 허브가 소유하는 **일시정지** 상태(v0.2.48).
    ///
    /// 왜 허브인가: 정지 중에는 판을 못 들여다보게 캔버스를 통째로 가려야 하는데(순위표가 걸린 게임에서 멈춰 놓고
    /// 다음 기둥을 외우는 것이 이득이면 안 된다), 그 스크림을 게임마다 그리면 두 벌이 된다. 게임은 `isPaused`
    /// 한 값만 읽는다.
    enum PauseState: Equatable {
        case none
        case paused
        /// 재개 카운트다운(3 → 2 → 1). 이 동안에도 판은 **얼어 있다** — 안 그러면 정지로 얻은 리듬 이점이 남는다.
        case resuming(Int)

        /// 카운트다운 시작값. 3-2-1 이 있어야 정지 직전 화면을 보고 손을 맞춰 두는 이득이 사라진다.
        static let countdownStart = 3

        /// 판이 얼어 있는가(= `MiniGameHost.isPaused`). 카운트다운 중에도 참이다.
        var isFrozen: Bool { self != .none }
        /// 정지 카드(이어하기·그만두기)가 떠 있는가. **화면이 실제로 이 프로퍼티로 분기한다** —
        /// 테스트만 부르고 화면은 `countdown == nil` 로 따로 판정하면, 상태가 하나 더 생기는 날
        /// 테스트는 초록인 채 화면만 갈린다.
        var showsCard: Bool { self == .paused }
        /// 카운트다운 숫자(아니면 nil).
        var countdown: Int? {
            if case let .resuming(remaining) = self { return remaining }
            return nil
        }

        /// [일시정지] 버튼과 ESC 가 공유하는 전이. **진행 중일 때만** 정지할 수 있다 —
        /// 시작 전·결과 화면에서 얼리면 클릭이 안 먹는 화면이 된다.
        func toggled(isPlaying: Bool) -> PauseState {
            switch self {
            case .none: return isPlaying ? .paused : .none
            case .paused: return .resuming(Self.countdownStart)
            case .resuming: return .paused          // 카운트다운 중 ESC 는 다시 정지(취소)
            }
        }

        /// 카운트다운 한 걸음(1초). 3 → 2 → 1 → none.
        func steppedDown() -> PauseState {
            guard case let .resuming(remaining) = self else { return self }
            return remaining <= 1 ? .none : .resuming(remaining - 1)
        }
    }

    let store: WorkTimerStore
    /// 스냅샷 전용: 초과 리스트를 ScrollView 대신 클립으로 그린다(ImageRenderer 육안 확인용). 앱은 false.
    var clipsOverflowInsteadOfScroll: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 클릭·스페이스를 접은 입력 카운터. 게임 잎 뷰는 "늘었다"만 본다.
    @State private var input = MiniGameInput()
    /// 마우스 다운 래치 — DragGesture(minimumDistance: 0) 의 onChanged 는 누르고 있는 동안 계속 오므로 첫 호출만 입력으로 센다.
    @State private var pressLatched = false
    /// 게임 진행 중(잎 뷰가 알려 준다). 진행 중엔 [일시정지]가 보이고, **정지 중이 아닐 때만** 종류 칩이 잠긴다.
    @State private var isPlaying: Bool
    @State private var pauseState: PauseState
    /// 재개 카운트다운 Task. 창이 닫히거나 interruptToken 이 오르면 반드시 cancel 한다 — 안 그러면 죽은 화면의
    /// @State 를 1초마다 두드리는 Task 가 남는다.
    @State private var resumeTask: Task<Void, Never>?

    /// - Parameter initialPause: **스냅샷·프리뷰 전용** 초기 정지 상태. 앱은 언제나 `.none` 으로 연다.
    ///   `.none` 이 아니면 `isPlaying` 도 참으로 시작한다 — 정지는 진행 중일 때만 가능한 상태이기 때문이다.
    init(store: WorkTimerStore, clipsOverflowInsteadOfScroll: Bool = false, initialPause: PauseState = .none) {
        self.store = store
        self.clipsOverflowInsteadOfScroll = clipsOverflowInsteadOfScroll
        _pauseState = State(initialValue: initialPause)
        _isPlaying = State(initialValue: initialPause.isFrozen)
    }

    static let title = "미니게임"
    static let rankTitle = "오늘 순위"
    static let prizeCaption = "자정에 1등은 울트라 찌르기 +10"
    static let emptyBoard = "아직 기록이 없어요 — 첫 기록의 주인공이 되세요"
    static let loadingCaption = "불러오는 중…"
    static let failedCaption = "순위를 불러오지 못했어요"
    static let awardedChip = "+10 받음"
    static let pauseTitle = "일시정지"
    static let resumeAction = "이어하기"
    static let quitAction = "그만두기"
    static let noRankToday = "오늘 기록 없음"

    /// 자정 상품 정족수. 서버 `public.minigame_prize_quorum()` 과 **짝인 상수**다(둘 다 5).
    /// 서버는 지급을 막고 화면은 그 조건을 미리 알린다 — 서버 함수를 바꾸면 여기도 같이 바꿔야
    /// "5명부터 지급"이 거짓말이 되지 않는다.
    static let prizeQuorum = 5

    var body: some View {
        let layout = MiniGameWindowLayout.layout(hasChampionRow: store.miniGameYesterdayWinner != nil)
        // 가로 2단: 왼쪽이 게임(헤더 + 캔버스 + 하단 스트립), 오른쪽이 오늘 순위. 순위를 캔버스 **아래**에 두면 눈이
        // 세로로 멀어지고 창을 낮출 때 순위부터 잘린다("게임 창 밑에 뜨니까 보기 힘들다" — 실사용 지적).
        HStack(alignment: .top, spacing: MiniGameWindowLayout.columnSpacing) {
            gameColumn(canvas: layout.canvasSize)
                .frame(width: layout.canvasSize.width, alignment: .top)
            rankColumn(visibleRows: layout.visibleRows)
                .frame(width: layout.rankSize.width, alignment: .top)
        }
        .padding(MiniGameWindowLayout.contentPadding)
        .frame(width: MiniGameWindowLayout.contentSize.width, height: MiniGameWindowLayout.contentSize.height, alignment: .topLeading)
        .onAppear { installSpaceKey() }
        .onDisappear {
            MiniGameSpaceKey.remove()
            cancelResume()
        }
        .onChange(of: store.miniGameInterruptToken) { _, _ in
            // 판이 끝났다(창 닫힘·포커스 이동·종류 전환·[그만두기]). 눌린 채 끝났어도 래치를 풀어 다음 판의 첫 클릭이 먹히게 한다.
            pressLatched = false
            isPlaying = false
            cancelResume()
            pauseState = .none
        }
    }

    // MARK: 게임 열

    @ViewBuilder
    private func gameColumn(canvas size: CGSize) -> some View {
        VStack(spacing: 0) {
            gameHeader
                .frame(height: MiniGameWindowLayout.headerHeight)
            Color.clear.frame(height: MiniGameWindowLayout.headerSpacing)
            canvasStack(size: size)
            Color.clear.frame(height: MiniGameWindowLayout.canvasFooterSpacing)
            gameFooter
                .frame(height: MiniGameWindowLayout.footerStripHeight)
            Spacer(minLength: 0)
        }
    }

    /// 헤더(32pt): 종류 칩 둘 | Spacer | [일시정지](진행 중일 때만).
    private var gameHeader: some View {
        HStack(spacing: 6) {
            ForEach(MiniGameKind.allCases) { kind in
                MiniGameKindChip(
                    title: kind.title,
                    icon: kind.icon,
                    isSelected: kind == store.miniGameKind,
                    // 정지 중에는 다른 게임 칩을 **푼다** — 사용자가 원한 것이 정확히 "포기하고 다른 게임 하기"다
                    // (2026-09-10). 다른 칩을 누르면 selectMiniGame 이 토큰을 올려 판을 무효화하고 넘어간다.
                    isEnabled: !isPlaying || pauseState.isFrozen || kind == store.miniGameKind
                ) {
                    store.selectMiniGame(kind)
                }
            }
            Spacer(minLength: 4)
            if isPlaying, !pauseState.isFrozen {
                MiniGameChromeButton(title: Self.pauseTitle, icon: "pause.fill", tint: CheckTheme.pending) {
                    togglePause()
                }
            }
        }
    }

    /// 하단 스트립(32pt): 최고 기록 | 오늘 내 순위 | 조작 안내.
    private var gameFooter: some View {
        HStack(spacing: 8) {
            Label {
                // String(...) — `Text("\(bestScore)점")` 은 LocalizedStringKey 보간이라 로캘 자리수 구분을
                // 붙여 만점에서 "최고 1,000점"이 된다. 게임 쪽 표기는 구분 없는 "1000"(총점 헤더·결과 카드)이라
                // 같은 창에서 표기가 갈린다. 통합에서 셋(여기·챔피언 카드·순위 행)을 한 표기로 맞췄다.
                Text("최고 " + String(bestScore) + "점").monospacedDigit()
            } icon: {
                Image(systemName: "trophy.fill").foregroundStyle(CheckTheme.pending)
            }
            .font(.caption2.weight(.semibold))
            .foregroundStyle(CheckTheme.primaryText)
            .lineLimit(1)
            Spacer(minLength: 4)
            Text(myRank.map { "오늘 \($0)위" } ?? Self.noRankToday)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(myRank == nil ? CheckTheme.secondaryText : CheckTheme.accent)
                .monospacedDigit()
                .lineLimit(1)
            Spacer(minLength: 4)
            Text(MiniGameKind.controlHint)
                .font(.caption2)
                .foregroundStyle(CheckTheme.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(CheckTheme.fieldFill))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(CheckTheme.border, lineWidth: 1))
    }

    // MARK: 캔버스

    private var host: MiniGameHost {
        let kind = store.miniGameKind
        return MiniGameHost(
            bestScore: store.miniGameBest(kind),
            reduceMotion: reduceMotion,
            interruptToken: store.miniGameInterruptToken,
            isPaused: pauseState.isFrozen,
            // 프레임 상한의 재료(v0.2.50). 창 컨트롤러가 창이 선 화면에서 읽어 두고, 화면을 옮기면 갱신한다.
            // `@Observable` 이라 **여기서 읽는 것만으로** 값이 바뀔 때 이 뷰가 다시 그려진다.
            refreshHz: MiniGameFrameRateMonitor.shared.refreshHz,
            onFinished: { score in store.recordMiniGameScore(kind: kind, score: score) },
            onPlayingChanged: { playing in
                isPlaying = playing
                // 판이 스스로 끝났으면(게임오버·10라운드 완주) 정지 상태도 같이 푼다 — 안 그러면 결과 화면 위에
                // 스크림이 남아 아무것도 못 누르는 창이 된다.
                if !playing {
                    cancelResume()
                    pauseState = .none
                }
            }
        )
    }

    /// 캔버스 + 정지 스크림/카드. 스크림은 캔버스와 **정확히 같은 사각형**을 덮는다.
    @ViewBuilder
    private func canvasStack(size: CGSize) -> some View {
        ZStack {
            switch store.miniGameKind {
            case .timingBar:
                TimingBarGameView(host: host, input: input)
            case .flappy:
                FlappyGameView(host: host, input: input)
            }
            if pauseState.isFrozen {
                pauseOverlay
            }
        }
        .frame(width: size.width, height: size.height)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(CheckTheme.fieldFill))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(CheckTheme.border, lineWidth: 1))
        // 캔버스가 판 위에 떠 있는 것처럼 — 창 크롬(헤더·스트립)과 층이 갈려야 "게임 화면"으로 읽힌다.
        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
        .contentShape(Rectangle())
        // 마우스 **다운**에 반응한다(Button/onTapGesture 는 마우스 업 발화 — 점프 게임엔 그 지연이 곧 낙차다).
        // 커서가 밖으로 나가도 onChanged 가 계속 오므로 래치로 1회만 센다. 정지 중에는 세지 않는다 —
        // 스크림을 클릭해 점프가 되면 정지가 아니다.
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !pressLatched else { return }
                    pressLatched = true
                    guard !pauseState.isFrozen else { return }
                    input.actionCount += 1
                }
                .onEnded { _ in pressLatched = false }
        )
        .accessibilityLabel("\(store.miniGameKind.title) 캔버스 — 클릭 또는 스페이스로 조작")
    }

    /// 정지 화면: 캔버스를 **완전히 가리는** 스크림 + 카드(또는 카운트다운 숫자).
    ///
    /// 스크림이 있는 이유는 미관이 아니다 — 순위표가 걸린 게임이라 멈춰 놓고 다음 기둥을 외우는 것이 이득이 되면
    /// 안 된다. 불투명도를 낮추면(판이 비쳐 보이면) 그 이득이 되살아난다.
    private var pauseOverlay: some View {
        ZStack {
            // 바닥은 **불투명**이다. 스크림 하나(0.93)만 얹었더니 밑그림이 7% 만큼 비쳐 시작 카드의 흰 글자가
            // 그대로 읽혔다(재개 카운트다운 스냅샷에서 실측, 2026-09-10). 색조는 아래 0.93 층이 그대로 만들고,
            // 이 층은 "판을 실제로 지우는" 일만 한다 — 둘 중 하나만 있으면 가림이 반쪽이 된다.
            CheckTheme.panel
            CheckTheme.panelElevated.opacity(0.93)
            if pauseState.showsCard {
                MiniGamePauseCard(
                    subtitle: pauseSubtitle,
                    onResume: { beginResume() },
                    onQuit: { quitRound() }
                )
            } else if let remaining = pauseState.countdown {
                VStack(spacing: 4) {
                    Text("\(remaining)")
                        .font(.system(size: 68, weight: .heavy, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(CheckTheme.accent)
                    Text("곧 다시 시작해요")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CheckTheme.secondaryText)
                }
            }
        }
        .transaction { if reduceMotion { $0.animation = nil } }
    }

    /// 정지 카드 부제 — **게임마다 interrupt 의미론이 다르다.** 플래피는 그 순간 점수로 결과가 확정되고,
    /// 타이밍 바는 10라운드를 못 채웠으므로 판이 무효다. 같은 문구를 쓰면 한쪽이 거짓말이 된다.
    ///
    /// 플래피 쪽에 **숫자를 못 적는 이유**: 진행 중 점수는 잎 뷰의 @State 안이고 `MiniGameHost` 에 그것을
    /// 내보내는 문이 없다(허브는 `onFinished` 로 끝난 판만 받는다). 없는 숫자를 지어내느니 "지금까지 지나온
    /// 기둥 수"라고 적는다 — 숫자를 넣으려면 MiniGame.swift 의 호스트 계약부터 넓혀야 한다.
    private var pauseSubtitle: String {
        switch store.miniGameKind {
        case .timingBar: return "지금 그만두면 이번 판 점수는 기록되지 않아요"
        case .flappy: return "지금 그만두면 지금까지 지나온 기둥 수가 점수로 기록돼요"
        }
    }

    private func installSpaceKey() {
        MiniGameSpaceKey.install(
            // 이 화면이 살아 있고 **게임 창이 실제로 화면에 떠 있을 때만** 스페이스를 삼킨다.
            // (키 창 판정은 모니터에서 뺐다 — 창을 막 연 순간 키가 아직 안 넘어와 스페이스가 죽었다.)
            shouldConsume: { CheckMiniGameWindowController.shared.isWindowOnScreen },
            action: {
                // 정지 중 스페이스는 점프가 아니다(스크림 뒤에서 판이 움직이면 정지가 아니다).
                guard !pauseState.isFrozen else { return }
                input.actionCount += 1
            },
            onEscape: { togglePause() }
        )
    }

    // MARK: 일시정지 전이

    /// ESC · [일시정지] 버튼 · [이어하기] 가 모두 여기로 온다. 반환값은 "화면이 실제로 처리했는가" —
    /// ESC 모니터가 이 값으로 이벤트를 삼킬지 정한다.
    @discardableResult
    private func togglePause() -> Bool {
        let next = pauseState.toggled(isPlaying: isPlaying)
        guard next != pauseState else { return false }
        cancelResume()
        if case .resuming = next {
            beginResume()
        } else {
            pauseState = next
        }
        return true
    }

    /// 재개: 스크림은 그대로 두고 숫자만 3 → 2 → 1 로 내린다.
    private func beginResume() {
        cancelResume()
        pauseState = .resuming(PauseState.countdownStart)
        resumeTask = Task { @MainActor in
            while true {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                guard case .resuming = pauseState else { return }
                pauseState = pauseState.steppedDown()
                if pauseState == .none { return }
            }
        }
    }

    private func cancelResume() {
        resumeTask?.cancel()
        resumeTask = nil
    }

    /// [그만두기]. 스토어의 `abortMiniGameRound()` 가 토큰을 올려 잎 뷰의 판을 끝낸다(플래피는 그 점수로 확정,
    /// 타이밍 바는 무효). 종류 칩 잠금도 함께 풀린다.
    private func quitRound() {
        cancelResume()
        pauseState = .none
        isPlaying = false
        store.abortMiniGameRound()
    }

    // MARK: 오늘 순위

    private var myUserID: String? { store.session?.userID }

    /// 내 오늘 순위(1부터). 순위 밖/없음이면 nil.
    private var myRank: Int? {
        guard let me = myUserID, let index = store.miniGameBoard.firstIndex(where: { $0.userID == me }) else { return nil }
        return index + 1
    }

    /// 내 최고 점수. 로컬 캐시와 오늘 내 행 중 큰 쪽이다 — 순위 응답이 로컬을 올리기 전 첫 프레임에도
    /// "최고 0점 · 오늘 953점" 같은 모순을 그리지 않는다.
    private var bestScore: Int {
        let mine = myUserID.flatMap { me in store.miniGameBoard.first { $0.userID == me } }
        return max(store.miniGameBest(store.miniGameKind), mine?.bestScore ?? 0)
    }

    /// 오늘 참여 인원(= 순위 행 수). 정족수 안내의 분자다.
    private var players: Int { store.miniGameBoard.count }

    /// 정족수 안내. 5는 서버 `minigame_prize_quorum()` 과 짝인 상수다(위 `prizeQuorum`).
    /// 0명일 때만 문장을 바꾼다 — "오늘 0명 참여"는 사람이 쓰는 말이 아니다.
    private var quorumCaption: String {
        if players >= Self.prizeQuorum { return "오늘 \(players)명 참여 · 지급 조건 충족" }
        if players == 0 { return "오늘은 아직 아무도 안 했어요 · \(Self.prizeQuorum)명부터 지급" }
        return "오늘 \(players)명 참여 · \(Self.prizeQuorum)명부터 지급"
    }

    @ViewBuilder
    private func rankColumn(visibleRows: Int) -> some View {
        // 머리글 높이·그 아래 간격은 게임 열과 **같은 상수**를 쓴다 — 두 단의 본문 윗변이 정확히 같은 줄에서 시작한다.
        VStack(spacing: 0) {
            rankHeader
                .frame(height: MiniGameWindowLayout.headerHeight)
            Color.clear.frame(height: MiniGameWindowLayout.headerSpacing)
            if let winner = store.miniGameYesterdayWinner {
                MiniGameChampionCard(winner: winner, awardedChip: Self.awardedChip)
                    .frame(height: MiniGameWindowLayout.championHeight)
                Color.clear.frame(height: MiniGameWindowLayout.championSpacing)
            }
            rankList(visibleRows: visibleRows)
            Spacer(minLength: MiniGameWindowLayout.prizeSpacing)
            prizeFooter
                .frame(height: MiniGameWindowLayout.prizeHeight)
            // 게임 열의 하단 스트립과 **같은 줄**에서 끝난다.
            Color.clear.frame(height: MiniGameWindowLayout.footerBaselineGap)
        }
    }

    /// 머리글(32pt): "오늘 순위" + 참여 인원 칩.
    private var rankHeader: some View {
        HStack(spacing: 6) {
            Text(Self.rankTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(CheckTheme.primaryText)
            Spacer(minLength: 4)
            if players > 0 {
                Label("\(players)명", systemImage: "person.2.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(CheckTheme.secondaryText)
                    .monospacedDigit()
                    .padding(.horizontal, 8)
                    .frame(height: 20)
                    .background(Capsule().fill(Color.white.opacity(0.06)))
                    .overlay(Capsule().stroke(CheckTheme.border, lineWidth: 1))
                    .fixedSize()
            }
        }
    }

    /// 바닥 안내(2줄): 상품 규칙 + 정족수. 색만으로 정보를 주지 않게 아이콘과 글자를 함께 쓴다.
    /// 게임 열의 하단 스트립과 **같은 카드 처리**다(테두리 있는 fieldFill) — 한쪽만 맨 텍스트면
    /// 두 단의 바닥이 하나의 띠로 읽히지 않는다(2026-09-10 지적).
    private var prizeFooter: some View {
        VStack(alignment: .leading, spacing: 1) {
            Label {
                Text(Self.prizeCaption)
            } icon: {
                Image(systemName: "trophy.fill").foregroundStyle(CheckTheme.pending)
            }
            .font(.caption2)
            .foregroundStyle(CheckTheme.secondaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            Label {
                Text(quorumCaption).monospacedDigit()
            } icon: {
                Image(systemName: players >= Self.prizeQuorum ? "checkmark.seal.fill" : "person.2.fill")
                    .foregroundStyle(players >= Self.prizeQuorum ? CheckTheme.working : CheckTheme.secondaryText)
            }
            .font(.caption2)
            .foregroundStyle(CheckTheme.secondaryText)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(CheckTheme.fieldFill))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(CheckTheme.border, lineWidth: 1))
    }

    private var rowCount: Int { max(1, store.miniGameBoard.count) }

    @ViewBuilder
    private func rankList(visibleRows: Int) -> some View {
        let capHeight = MiniGameWindowLayout.listHeight(rows: visibleRows)
        if rowCount <= visibleRows {
            // 남는 자리는 **흐린 자리표시 행**으로 채운다. 비워 두면 오른쪽 단 아래가 최대 272pt 통째로
            // 비어 "목록이 여기서 끝났다"로 읽히고, 두 단의 바닥이 서로 다른 물건이 된다(2026-09-10 실측).
            rows(placeholders: visibleRows).frame(maxWidth: .infinity, alignment: .top)
        } else if clipsOverflowInsteadOfScroll {
            // 스냅샷 전용: ImageRenderer 는 ScrollView 안쪽을 못 그린다(다른 패널과 같은 우회).
            rows(placeholders: 0).frame(maxWidth: .infinity, alignment: .top)
                .frame(height: capHeight, alignment: .top)
                .clipped()
                .mask(overflowFade)
        } else {
            ScrollView(.vertical, showsIndicators: true) {
                rows(placeholders: 0).frame(maxWidth: .infinity)
            }
            .frame(height: capHeight)
            // 아래가 더 있다는 유일한 단서가 macOS 오버레이 스크롤바면 정지 화면에서는 아무 단서도 없다.
            // 마지막 행을 페이드로 지워 "이어진다"를 그림으로 말한다.
            .mask(overflowFade)
        }
    }

    /// 목록이 넘칠 때 아래쪽을 흐리는 마스크. 잘린 행이 페이드로 사라지면 스크롤바 없이도 계속됨이 보인다.
    private var overflowFade: LinearGradient {
        LinearGradient(
            stops: [.init(color: .black, location: 0),
                    .init(color: .black, location: 0.88),
                    .init(color: .black.opacity(0.05), location: 1)],
            startPoint: .top, endPoint: .bottom
        )
    }

    @ViewBuilder
    private func rows(placeholders visibleRows: Int) -> some View {
        VStack(spacing: MiniGameWindowLayout.rowSpacing) {
            if store.miniGameBoard.isEmpty {
                HStack(spacing: 8) {
                    Text(emptyText)
                        .font(.caption2)
                        .foregroundStyle(CheckTheme.secondaryText)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    if store.miniGameBoardFailed, !store.miniGameBoardLoaded {
                        MiniGameRetryButton { store.loadMiniGameBoard() }
                    }
                }
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: MiniGameWindowLayout.rowHeight * 1.5, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(CheckTheme.fieldFill))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(CheckTheme.border, lineWidth: 1))
            } else {
                ForEach(Array(store.miniGameBoard.enumerated()), id: \.element.id) { index, entry in
                    MiniGameRankRow(rank: index + 1, entry: entry, isMe: myUserID != nil && entry.userID == myUserID)
                        .frame(height: MiniGameWindowLayout.rowHeight)
                }
            }
            // 빈 안내 카드는 1.5행을 먹는다 — 자리 계산에서는 그만큼 빼되(안 그러면 단 밖으로 넘친다),
            // **등수는 1부터** 센다. 안내 문구는 순위가 아니라 메시지이므로 "1·2위는 어디 갔나"가 되면 안 된다.
            let usedRows = store.miniGameBoard.isEmpty ? 2 : store.miniGameBoard.count
            let firstPlaceholderRank = store.miniGameBoard.count + 1
            ForEach(0..<max(0, visibleRows - usedRows), id: \.self) { index in
                MiniGameRankPlaceholderRow(rank: firstPlaceholderRank + index)
                    .frame(height: MiniGameWindowLayout.rowHeight)
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

// MARK: - 메달 색

/// 1·2·3위 배지 색. 색만으로 정보를 주지 않게 배지 안에는 **언제나 숫자**가 있다(색은 보조 신호다).
private enum MiniGameMedal {
    static let gold = Color(red: 1.00, green: 0.824, blue: 0.290)     // #FFD24A
    static let silver = Color(red: 0.839, green: 0.863, blue: 0.902)  // #D6DCE6
    static let bronze = Color(red: 0.878, green: 0.584, blue: 0.353)  // #E0955A

    static func color(rank: Int) -> Color? {
        switch rank {
        case 1: return gold
        case 2: return silver
        case 3: return bronze
        default: return nil
        }
    }
}

// MARK: - 크롬 조각

/// 게임 종류 칩(아이콘 + 이름). 선택 = accent 채움, 비선택 = 흐린 캡슐.
private struct MiniGameKindChip: View {
    let title: String
    let icon: String
    let isSelected: Bool
    var isEnabled: Bool = true
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.caption2.weight(.bold))
                .foregroundStyle(isSelected ? CheckTheme.accent : CheckTheme.secondaryText)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(
                    Capsule().fill(isSelected ? CheckTheme.accent.opacity(0.20) : Color.white.opacity(hovering ? 0.10 : 0.04))
                )
                .overlay(
                    Capsule().stroke(isSelected ? CheckTheme.accent.opacity(0.55) : CheckTheme.border, lineWidth: 1)
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .onHover { hovering = $0 }
        .help(title)
    }
}

/// 헤더 오른쪽 소형 버튼([일시정지]). 정지 카드 안 버튼과 수치가 다르다 — 여기는 32pt 헤더에 들어가야 한다.
private struct MiniGameChromeButton: View {
    let title: String
    let icon: String
    var tint: Color = CheckTheme.accent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.caption2.weight(.bold))
                .foregroundStyle(tint)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(Capsule().fill(tint.opacity(0.16)))
                .overlay(Capsule().stroke(tint.opacity(0.40), lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(title)
    }
}

/// 정지 카드. 크롬(배경·테두리·그림자)은 시작·결과 카드와 **같은 한 벌**(`MiniGameCardChrome`)이다 —
/// 같은 캔버스 위에 번갈아 뜨는 두 카드가 각자 만들면 수치가 갈린다(실제로 모서리 16 vs 14 · 아이콘 32 vs 34 ·
/// 폭 250 vs 240 · 그림자 14/5 vs 12/4 로 갈려 있었다, 2026-09-10 지적).
/// 바닥만 **불투명**이다 — 스크림(panelElevated 0.93)과 같은 색 반투명으로 두면 카드가 스크림에 녹는다.
private struct MiniGamePauseCard: View {
    let subtitle: String
    let onResume: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "pause.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(CheckTheme.pending)
                .frame(width: MiniGameCardChrome.iconDiameter, height: MiniGameCardChrome.iconDiameter)
                .background(Circle().fill(CheckTheme.pending.opacity(0.16)))
                .overlay(Circle().stroke(CheckTheme.pending.opacity(0.40), lineWidth: 1))
            Text(CheckMiniGameWindowView.pauseTitle)
                .font(.headline)
                .foregroundStyle(CheckTheme.primaryText)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(CheckTheme.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                MiniGamePauseAction(title: CheckMiniGameWindowView.resumeAction, icon: "play.fill",
                                    tint: CheckTheme.accent, action: onResume)
                MiniGamePauseAction(title: CheckMiniGameWindowView.quitAction, icon: "xmark",
                                    tint: CheckTheme.danger, action: onQuit)
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, MiniGameCardChrome.verticalPadding)
        .frame(width: MiniGameCardChrome.width)
        .modifier(MiniGameCardChrome(tint: CheckTheme.accent, fillOpacity: 1, sheen: true))
    }
}

/// 정지 카드 안의 알약 버튼(이어하기 = accent, 그만두기 = danger).
private struct MiniGamePauseAction: View {
    let title: String
    let icon: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
                .padding(.horizontal, 12)
                .frame(height: 28)
                .background(Capsule().fill(tint.opacity(0.18)))
                .overlay(Capsule().stroke(tint.opacity(0.45), lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(title)
    }
}

/// 어제 챔피언 카드(48pt). 왕관 · 아바타 · 이름 · 점수 · "+10 받음". 금색 채움 + 금색 테두리로 순위 행과 층을 가른다.
private struct MiniGameChampionCard: View {
    let winner: MiniGameWinner
    let awardedChip: String

    var body: some View {
        // ★ 열 규격은 `MiniGameRankRow` 와 **같은 숫자**다(배지/왕관 22 · 간격 7 · 앞 5 · 뒤 9 · 점수 칸 46).
        //   갈리면 어제 1등의 이름과 점수가 아래 순위 행들과 어긋나 목록이 두 개로 읽힌다
        //   (2026-09-10 실측: 이름 7pt · 점수 56.5pt 어긋남).
        HStack(spacing: MiniGameRankRow.columnSpacing) {
            Image(systemName: "crown.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(MiniGameMedal.gold)
                .frame(width: MiniGameRankRow.badgeSize, height: MiniGameRankRow.badgeSize)
            CheckAvatarView(name: winner.name, avatarURL: winner.avatarURL, size: MiniGameRankRow.avatarSize)
            VStack(alignment: .leading, spacing: 0) {
                Text("어제 1등")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(MiniGameMedal.gold)
                Text(winner.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CheckTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Spacer(minLength: 4)
            // "+10 받음" 칩은 점수 **앞**이다 — 뒤에 두면 칩 폭만큼 점수가 밀려 오른쪽 끝이 목록과 갈린다.
            if winner.awarded {
                Text(awardedChip)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(CheckTheme.working)
                    .padding(.horizontal, 6)
                    .frame(height: 18)
                    .background(Capsule().fill(CheckTheme.working.opacity(0.18)))
                    .fixedSize()
            }
            // 자리수 구분을 붙이지 않는다(gameFooter 주석 참고) — 어제 1등이 만점이면 "1,000점"이 된다.
            Text(String(winner.score) + "점")
                .font(.caption.weight(.bold))
                .foregroundStyle(CheckTheme.primaryText)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: MiniGameRankRow.scoreWidth, alignment: .trailing)
        }
        .padding(.leading, MiniGameRankRow.leadingPadding)
        .padding(.trailing, MiniGameRankRow.trailingPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(MiniGameMedal.gold.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(MiniGameMedal.gold.opacity(0.35), lineWidth: 1))
    }
}

/// 오늘 순위 행(30pt): 순위 배지 22 · 아바타 22 · 이름(+"나" 칩) · 우측 "N점".
/// 1·2·3위는 금·은·동 배지, 4위부터는 투명 배지에 흐린 숫자. 내 행은 accent 채움 + 테두리다.
struct MiniGameRankRow: View {
    /// 열 규격. **어제 챔피언 카드가 같은 값을 읽는다** — 두 벌로 적으면 두 카드의 이름·점수가 어긋난다.
    static let badgeSize: CGFloat = 22
    static let avatarSize: CGFloat = 22
    static let columnSpacing: CGFloat = 7
    static let leadingPadding: CGFloat = 5
    static let trailingPadding: CGFloat = 9
    /// 점수 칸은 **고정폭**이다 — 자릿수가 달라도 오른쪽 끝이 한 줄로 서야 순위표로 읽힌다.
    /// 타이밍 바 상한이 1000 이라 "1000점"이 들어갈 폭이고, 그래도 모자라면 줄여서 그린다.
    static let scoreWidth: CGFloat = 46

    let rank: Int
    let entry: MiniGameBoardEntry
    var isMe: Bool = false

    private var medal: Color? { MiniGameMedal.color(rank: rank) }

    var body: some View {
        HStack(spacing: Self.columnSpacing) {
            badge
            CheckAvatarView(name: entry.name, avatarURL: entry.avatarURL, size: Self.avatarSize)
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
                    .frame(height: 16)
                    .background(Capsule().fill(CheckTheme.accent.opacity(0.22)))
                    .fixedSize()
            }
            Spacer(minLength: 4)
            // String(...) 인 이유: 보간(`"\(entry.bestScore)점"`)은 로캘 자리수 구분을 붙여 만점에서
            // "1,000점"이 된다 — 이 46pt 예산이 재던 글자보다 넓고, 게임 쪽 "1000" 표기와도 갈린다.
            Text(String(entry.bestScore) + "점")
                .font(.caption.weight(.bold))
                .foregroundStyle(CheckTheme.primaryText)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: Self.scoreWidth, alignment: .trailing)
        }
        .padding(.leading, Self.leadingPadding)
        .padding(.trailing, Self.trailingPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(fill))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(stroke, lineWidth: 1))
    }

    /// 순위 배지(원형 22). 메달 색 안의 글자는 **검정**이다 — 금·은색 위 흰 글자는 대비가 무너진다.
    private var badge: some View {
        Text("\(rank)")
            .font(.system(size: 11, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(medal == nil ? CheckTheme.secondaryText : Color.black.opacity(0.78))
            .frame(width: Self.badgeSize, height: Self.badgeSize)
            .background(Circle().fill(medal ?? Color.white.opacity(0.05)))
            .overlay(Circle().stroke(medal == nil ? CheckTheme.border : Color.clear, lineWidth: 1))
    }

    private var fill: Color {
        if isMe { return CheckTheme.accent.opacity(0.10) }
        return CheckTheme.fieldFill
    }

    private var stroke: Color {
        if isMe { return CheckTheme.accent.opacity(0.45) }
        // 1위만 살짝 더 강조 — 목록 맨 위가 "오늘의 1등"으로 읽혀야 한다.
        if rank == 1 { return MiniGameMedal.gold.opacity(0.35) }
        return CheckTheme.border
    }
}

/// 아직 아무도 없는 자리. 순위 행과 **같은 높이·같은 열 규격**의 흐린 껍데기라 목록의 길이가 예고된다.
/// 숫자를 빼면 그냥 빈 상자가 되어 "여기가 몇 위 자리인지"가 사라진다 — 그래서 등수는 남긴다.
private struct MiniGameRankPlaceholderRow: View {
    let rank: Int

    var body: some View {
        HStack(spacing: MiniGameRankRow.columnSpacing) {
            Text("\(rank)")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(CheckTheme.secondaryText.opacity(0.35))
                .frame(width: MiniGameRankRow.badgeSize, height: MiniGameRankRow.badgeSize)
                .background(Circle().fill(Color.white.opacity(0.03)))
            Circle()
                .fill(Color.white.opacity(0.03))
                .frame(width: MiniGameRankRow.avatarSize, height: MiniGameRankRow.avatarSize)
            Capsule()
                .fill(Color.white.opacity(0.04))
                .frame(width: 62, height: 8)
            Spacer(minLength: 4)
        }
        .padding(.leading, MiniGameRankRow.leadingPadding)
        .padding(.trailing, MiniGameRankRow.trailingPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.02)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(CheckTheme.border.opacity(0.45), lineWidth: 1))
        .accessibilityHidden(true)
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
