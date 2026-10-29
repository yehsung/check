import AppKit
import SwiftUI
import CheckCore

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

/// 스페이스(점프·시작)·ESC(일시정지)·**테트리스 조작키**를 게임 입력으로 가로채는 로컬 키 모니터.
///
/// 없으면 스페이스가 다른 것을 누른다(팝오버가 열려 있으면 근무 시작/종료 알약이 첫 포커스를 받는다).
/// 모니터가 먼저 받아 nil 을 돌려주면 그 이벤트는 SwiftUI 에 닿지 않는다. **전역 모니터가 아니다** —
/// 전역 모니터는 우리 앱이 활성일 때 눈이 먼다.
///
/// v0.2.48 에 ESC 를 **같은 모니터**에 얹었다. 두 벌을 걸면 설치·제거 규약이 두 곳이 되어 아래 두 실사용 버그가
/// 한쪽에서만 고쳐진 채 남는다. 다만 스페이스와 달리 ESC 는 **처리했을 때만 삼킨다**(onEscape 의 반환값) —
/// 시작 전·결과 화면처럼 정지할 판이 없을 때까지 ESC 를 먹으면 다른 화면의 취소 키를 훔친다.
///
/// v0.3.38 에 방향·회전·홀드가 **같은 모니터**에 얹혔고, `.keyUp` 도 받기 시작했다(뗌이 있어야 눌림이 안 굳는다).
/// 스페이스와 **게이트가 반대 방향**인 것이 이 확장의 핵심이다 — 아래 `strokeBelongsToGame` 주석.
///
/// v0.3.62 에 ESC 가 **스페이스 쪽에서 방향키 쪽으로 넘어갔다.** 키 상실이 판을 끝내는 대신 멈추게 되면서
/// 남의 창에서 누른 ESC 가 정지해 둔 판을 자동 재개했기 때문이다 — 그래서 모니터는 ESC 처리기에 **키가 향한
/// 창을 넘기고**, 화면이 `strokeBelongsToGame` 으로 가린다. 스페이스의 관대한 게이트는 **그대로 둔다**
/// (창을 막 연 순간 스페이스가 죽는 2026-09-09 사고가 그 관대함의 이유다).
enum MiniGameSpaceKey {
    nonisolated(unsafe) private static var token: Any?
    /// 스페이스 keyCode.
    static let spaceKeyCode: UInt16 = 49
    /// ESC keyCode(일시정지 토글).
    static let escapeKeyCode: UInt16 = 53

    /// 판이 도는 동안만 쓰는 조작 키. **물리 키 자리(ANSI keyCode)로만 들어온다** — 글자로 받으면
    /// 한글 입력 상태에서 Z·X·C 가 'ㅋ'·'ㅌ'·'ㅊ' 로 와서 통째로 빗나간다. 이 저장소는 그 사실 위에
    /// `EnglishInputSource`(영문 전용 필드가 포커스를 얻으면 입력기를 ABC 로 바꾼다)를 이미 두고 있다 —
    /// 게임 창에서는 입력기를 건드릴 수 없으니(사용자가 치던 글을 뺏는다) 자리로 받는 쪽이 유일한 길이다.
    enum GameKey: Equatable, Sendable, CaseIterable {
        /// 누름/뗌 짝으로 오는 키(DAS·ARR 은 게임 시계가 만든다).
        case moveLeft, moveRight, softDrop
        /// 누름만 뜻이 있는 키(뗌은 멱등하게 무시된다).
        case rotateCW, rotateCCW, hold

        var isLevel: Bool {
            switch self {
            case .moveLeft, .moveRight, .softDrop: return true
            case .rotateCW, .rotateCCW, .hold: return false
            }
        }
    }

    /// 한 번의 키 사건. `isDown == false` 는 **뗌**이고, 게이트와 무관하게 언제나 화면에 전달된다.
    struct Stroke: Equatable, Sendable {
        let key: GameKey
        let isDown: Bool

        /// ANSI keyCode(Carbon `Events.h`) → 조작 키. `charactersIgnoringModifiers` 를 쓰지 마라(위 주석).
        /// ← 123 · → 124 · ↓ 125 · ↑ 126 · Z 6 · X 7 · C 8.
        static func key(forKeyCode code: UInt16) -> GameKey? {
            switch code {
            case 123: return .moveLeft
            case 124: return .moveRight
            case 125: return .softDrop
            case 126, 7: return .rotateCW      // ↑ · X
            case 6: return .rotateCCW          // Z
            case 8: return .hold               // C
            default: return nil
            }
        }
    }

    /// 길건너 아잉이(v0.3.67)의 **뛰기 키** — ↑↓←→ 와 W·A·S·D. 테트리스 표(`Stroke.key`)와 **따로** 둔다:
    /// 같은 ↑ 가 저쪽에서는 회전이고 이쪽에서는 앞으로 한 칸이며, W·A·S·D(13·0·1·2)는 저 표에서 **반드시 nil**
    /// 이어야 한다(아무 글자나 삼키면 다른 창의 타이핑을 훔친다 — V0338 이 그 자리를 잰다). 이 표의 글자 키는
    /// 길건너 판이 **게임 창으로 간 키**만 받는 엄격한 게이트(`strokeBelongsToGame`) 뒤에서만 쓰인다.
    /// 물리 키 자리(ANSI keyCode)로만 받는다 — 한글 입력 상태에서 W·A·S·D 는 'ㅈ'·'ㅁ'·'ㄴ'·'ㅇ' 으로 온다.
    /// ↑ 126 · ↓ 125 · ← 123 · → 124 · W 13 · S 1 · A 0 · D 2.
    static func hopDirection(forKeyCode code: UInt16) -> CrossyGame.Direction? {
        switch code {
        case 126, 13: return .forward
        case 125, 1: return .back
        case 123, 0: return .left
        case 124, 2: return .right
        default: return nil
        }
    }

    /// 방향·회전·홀드를 **게임이 받는가**. 스페이스(`yieldsToOtherWindow`)와 정확히 반대 방향의 게이트다.
    ///
    /// v0.3.62 에 **ESC 도 이 판정을 쓴다**(`installSpaceKey` 의 onEscape). 키 상실이 판을 끝내는 대신
    /// 멈추게 되면서 "키 없는 창에 살아 있는 정지된 판" 이 생겼고, 남의 창에서 누른 ESC 가 그 판을 자동
    /// 재개했기 때문이다. 즉 이 함수는 이제 **엄격한 게이트가 필요한 키 전부**의 판정이다.
    ///
    /// 스페이스는 "양보할 근거가 분명할 때만" 양보한다 — 창을 막 연 순간을 살리기 위해서다(v0.3.30).
    /// 방향키는 그 관대함을 쓸 수 없다: `yieldsToOtherWindow` 가 아는 독립 창은 오목·설정 둘뿐이고
    /// 팝오버·할 일 보드는 identifier 가 없어 "모르는 창"으로 떨어진다. 그 창들에서 누른 ←/→/↑/↓ 를
    /// 삼키면 리스트 선택과 커서가 통째로 죽는다 — 2026-09-17 오목 채팅 사고(스페이스를 삼켜 띄어쓰기가
    /// 안 됐다)의 화살표판이다.
    ///
    /// 엄격하게 해도 플레이 손실이 0 인 이유: 판이 **실제로 도는 동안** 게임 창은 언제나 키 창이다(포커스를
    /// 잃는 순간 `windowDidResignKey` 가 판을 **멈춘다** — CheckMiniGameWindow.swift · 0.3.62 전에는 끝냈다).
    /// 그래서 "키가 향한 창이 게임 창인가"를 요구해도 정상 플레이에서는 한 번도 안 걸린다.
    ///
    /// 끝내기에서 멈추기로 바뀌어도 **조작키가 새지 않는다** — 게이트가 둘이기 때문이다. 이 판정과 별개로
    /// `wantsStrokes` 가 `!pauseState.isFrozen` 을 요구하므로(`installSpaceKey`), 키를 잃어 얼어붙은 동안은
    /// 방향·회전·홀드를 **아예 안 받는다**. 창이 키를 되찾아도 사용자가 [이어하기] 를 눌러 카운트다운이
    /// 끝나기 전까지 그대로다(`.resuming` 도 `isFrozen` 이다). 그 사이의 키는 남의 창 몫으로 흘러간다.
    /// `isKeyWindow` 로 묻지 않는다(창을 막 연 순간이 죽는 그 금지는 여기서도 유효하다) — 키가 실제로
    /// 향한 창이 게임 창과 **같은 객체인지**로만 잰다.
    @MainActor
    static func strokeBelongsToGame(_ eventWindow: NSWindow?, gameWindow: NSWindow?) -> Bool {
        guard let eventWindow, let gameWindow, eventWindow === gameWindow else { return false }
        return gameWindow.isVisible
    }

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
    ///   **키가 향한 창을 함께 넘긴다**(v0.3.62) — ESC 는 그 창이 게임 창일 때만 받아야 하기 때문이다
    ///   (`strokeBelongsToGame` 짝 게이트 · 아래 `installSpaceKey` 의 onEscape 주석).
    /// - Parameter gameWindow: 게임 창. 다른 창으로 향한 키를 양보할지 가를 때 "게임 창이 아닌가"를 이것으로 잰다.
    /// - Parameter wantsStrokes: 지금 방향·회전·홀드를 받는가(테트리스이고 판이 도는 중이며 얼어 있지 않을 때).
    /// - Parameter onStroke: 조작 키 한 번. **뗌은 게이트와 무관하게 언제나 온다** — 아래 ★★ 참고.
    /// - Parameter wantsHops: 지금 뛰기 키(↑↓←→ · WASD)를 받는가(길건너 아잉이이고 얼어 있지 않을 때 — v0.3.67).
    /// - Parameter onHop: 뛰기 한 번(누름만 — 뛰기는 누름 한 번이 한 칸이라 뗌이 뜻이 없다).
    static func install(shouldConsume: @escaping @MainActor () -> Bool,
                        action: @escaping @MainActor () -> Void,
                        onEscape: @escaping @MainActor (NSWindow?) -> Bool = { _ in false },
                        gameWindow: @escaping @MainActor () -> NSWindow? = { nil },
                        wantsStrokes: @escaping @MainActor () -> Bool = { false },
                        onStroke: @escaping @MainActor (Stroke) -> Void = { _ in },
                        wantsHops: @escaping @MainActor () -> Bool = { false },
                        onHop: @escaping @MainActor (CrossyGame.Direction) -> Void = { _ in }) {
        remove()
        armed = action
        armedEscape = onEscape
        armedStroke = onStroke
        armedHop = onHop
        // `.keyUp` 이 있어야 눌림이 안 굳는다. 스페이스·ESC 는 여전히 keyDown 만 본다(아래 `!isUp` 가드).
        token = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { event in
            let isUp = event.type == .keyUp
            let keyCode = event.keyCode
            let isEscape = keyCode == escapeKeyCode
            let hasModifier = !event.modifierFlags.intersection([.command, .control, .option]).isEmpty
            let stroke = Stroke.key(forKeyCode: keyCode)
            // 키 반복(누르고 있기)은 삼키기만 한다 — 점프 연타가 되면 게임이 아니고, 테트리스에서는
            // OS 키 반복에 ARR 을 맡기는 순간 시스템 키보드 설정이 순위를 가른다(반복은 게임 시계가 만든다).
            // `isARepeat` 은 keyDown 에서만 뜻이 있다.
            let isRepeat = isUp ? false : event.isARepeat
            // 창은 번호로 넘긴다 — NSEvent 를 메인 액터 클로저로 보내면 Swift 6 가 데이터 경쟁으로 막는다.
            let windowNumber = event.windowNumber
            let hop = hopDirection(forKeyCode: keyCode)
            let consumed = MainActor.assumeIsolated { () -> Bool in
                // ── 뛰기(길건너 아잉이 · v0.3.67) ───────────────────────────────────────────────
                // 테트리스 가지보다 **앞**이다 — ↑↓←→ 가 두 표에 다 있어서, 길건너 판이 받는 동안에는 이쪽이 먹어야 한다
                // (`wantsHops` 는 길건너일 때만 참이라 테트리스 판에서는 이 가지가 통째로 지나간다).
                // 게이트는 방향 가지와 **같은 엄격한 쪽**(키가 게임 창으로 갔는가)이고, 스페이스 쪽 게이트는 안 쓴다.
                if let hop, wantsHops() {
                    let belongs = strokeBelongsToGame(NSApp.window(withWindowNumber: windowNumber),
                                                      gameWindow: gameWindow())
                    guard belongs else { return false }
                    // 뗌은 뜻이 없다 — 게임 창으로 간 뗌만 삼킨다(누름을 삼키고 뗌을 흘리면 짝 잃은 뗌이 남의 손에 간다).
                    if isUp { return true }
                    guard !hasModifier else { return false }
                    // 누르고 있기는 뛰기가 아니다(한 번 누름 = 한 칸) — OS 키 반복은 삼키기만 한다.
                    guard !isRepeat else { return true }
                    onHop(hop)
                    return true
                }
                // ── 방향·회전·홀드(테트리스) ────────────────────────────────────────────────────
                // 스페이스 가지보다 **앞**이지만, 이 가지 안에는 `shouldConsume` 도 양보 판정도 넣지 않는다 —
                // 게이트가 서로 반대 방향이라 섞으면 둘 중 하나가 무너진다(소스 계약이 순서를 못 박는다).
                if let key = stroke {
                    let belongs = strokeBelongsToGame(NSApp.window(withWindowNumber: windowNumber),
                                                      gameWindow: gameWindow())
                    // ★★ 뗌은 **게이트보다 먼저, 무조건** 화면에 알린다. 게이트 뒤에 두면
                    //    "←를 누른 채 ESC → ←를 뗌(무시됨) → 재개" 에서 키가 눌린 채로 굳는다.
                    //    수식키 가드도 뗌에는 안 건다 — ←를 잡은 채 ⌘ 를 누르면 그 keyUp 이 수식키를 달고 온다.
                    //    화면의 해제는 멱등이라 남의 창에서 온 뗌을 받아도 안전하다.
                    if isUp {
                        onStroke(Stroke(key: key, isDown: false))
                        return belongs && wantsStrokes()
                    }
                    guard belongs, wantsStrokes() else { return false }
                    guard !hasModifier else { return false }
                    guard !isRepeat else { return true }
                    onStroke(Stroke(key: key, isDown: true))
                    return true
                }
                // ── 스페이스 · ESC (v0.3.30 의 관대한 게이트 그대로) ────────────────────────────
                guard !isUp, keyCode == spaceKeyCode || isEscape, !hasModifier else { return false }
                // ★ 키 창 여부로 거르지 않는다. 로컬 모니터는 **우리 앱이 활성일 때만** 이벤트를 받으므로,
                //   여기 도달했다는 것 자체가 "우리 앱이 앞에 있다"는 뜻이다. 그 위에 `isKeyWindow` 를 더 요구했더니
                //   게임 창을 처음 연 직후 — 메뉴바 팝오버가 닫히며 키가 넘어가는 그 짧은 순간 — 스페이스가 통째로
                //   빠졌다("업데이트하고 처음 열어 플레이할 때 스페이스가 안 됐다", 2026-09-09 제보).
                //   창이 실제로 떠 있는지는 아래 shouldConsume(컨트롤러의 창 가시성 + 이 화면의 생존)이 판정한다.
                // 다른 창에서 글을 쓰는 중이거나 다른 독립 창으로 간 키는 그 창 몫이다(v0.3.30 — `yieldsToOtherWindow`).
                let target = NSApp.window(withWindowNumber: windowNumber)
                guard !yieldsToOtherWindow(target, gameWindow: gameWindow()) else { return false }
                guard shouldConsume() else { return false }
                guard !isRepeat else { return true }
                // ESC 는 화면이 실제로 정지/재개를 했을 때만 삼킨다 — 아니면 그대로 흘려 보낸다.
                // **키가 향한 창을 함께 넘긴다**(v0.3.62) — 여기까지 온 ESC 는 스페이스의 관대한 게이트만
                // 지난 것이라 "남의 창으로 간 ESC" 가 섞여 있다. 그것을 가리는 것은 화면 몫이다(소유권 게이트).
                if isEscape { return onEscape(target) }
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
        armedStroke = nil
        armedHop = nil
    }

    /// 이 키를 **다른 창에 양보하는가**(v0.3.30). 순수 판정이라 실제 창으로 잰다.
    ///
    /// 게이트가 "게임 창이 화면에 떠 있는가" 하나뿐이어서, 게임 창을 띄워 둔 채 **다른 창에서** 누른 스페이스까지
    /// 점프로 삼켰다 — 미니게임 창에서 [1:1 오목]으로 넘어가 대국 채팅을 치면 띄어쓰기가 통째로 안 됐다
    /// (2026-09-17 실사용 제보). 그렇다고 키 창을 요구하면 창을 막 연 순간이 죽는다(install 의 ★). 그래서
    /// **양보할 근거가 분명할 때만** 양보한다 — 키가 향한 창이 게임 창이 아니고 화면에 떠 있으면서:
    ///  · 그 창에서 글을 쓰는 중이다(첫 응답자가 텍스트 — 팝오버의 메시지 입력칸도 여기에 든다), 또는
    ///  · 스페이스를 게임에 넘길 이유가 없는 우리 독립 창(오목·설정)이다.
    /// 키가 향한 창이 없거나(키가 아직 안 넘어온 그 순간) 게임 창이면 예전 그대로 `shouldConsume` 이 판정한다.
    @MainActor
    static func yieldsToOtherWindow(_ eventWindow: NSWindow?, gameWindow: NSWindow?) -> Bool {
        guard let eventWindow, eventWindow !== gameWindow, eventWindow.isVisible else { return false }
        if eventWindow.firstResponder is NSText { return true }
        guard let id = eventWindow.identifier?.rawValue else { return false }
        return standaloneWindowIDs.contains(id)
    }

    /// 스페이스를 게임에 넘기지 않는 우리 독립 창들(창 식별자 = 각 컨트롤러의 자리 저장 키).
    ///
    /// ★ **독립 창을 새로 만들면 여기에 더해야 한다.** 이 목록이 아는 창이 "오목·설정 둘뿐"이던 동안,
    ///   미니게임 창을 띄워 둔 채 오목 대국 채팅을 치면 스페이스가 통째로 삼켜져 띄어쓰기가 안 됐다
    ///   (2026-09-17 실사용 제보). 체스 창(v0.3.44)의 입력도 같은 로컬 모니터를 지나므로 빠지면 같은 사고가
    ///   그대로 재현된다 — 빼면 빨개지는 테스트가 `V0344ChessWindowTests` 에 있다.
    @MainActor
    /// v0.3.46: **AI 리밋 창이 빠져 셋이다.** 그 창은 사라졌다(카드가 팝오버 안으로 들어왔다 —
    /// `CheckAILimitsRow.swift` 머리말). 없는 창의 식별자를 목록에 남겨 두면, 다음 사람이 그 이름으로
    /// 컨트롤러를 찾다 못 찾고 "등록이 빠졌다"로 읽는다.
    /// v0.3.54: 캐릭터 뽑기 창이 더해져 **넷**이다. 그 창은 글을 받지 않지만 [한 번 더]·[닫기]·"확률 보기" 가 키보드로도 눌린다
    /// (전체 키보드 접근 — 스페이스가 초점 단추를 누른다). 등록이 빠지면 미니게임 창을 띄워 둔 채 그 단추를 스페이스로 누를 때 게임이 삼킨다.
    /// v0.3.60: 1:1 테트리스 창이 더해져 **다섯**이다. 그 창의 스페이스는 **하드드롭**이라, 등록이 빠지면 미니게임 창을 띄워 둔 채
    /// 대결 창에서 누른 스페이스를 미니게임 모니터가 먼저 삼킨다 — 루비가 걸린 판에서 조각이 안 떨어진다.
    /// v0.3.68: 아잉 큐브 창이 더해져 **일곱**이다. 판은 끌기라 키가 적지만 [완료]·[뽑기]·[되돌리기]·확인 대화상자가
    /// 키보드로도 눌린다(전체 키보드 접근 — 스페이스가 초점 단추를 누른다). 등록이 빠지면 미니게임 창을 띄워 둔 채 [완료]를
    /// 스페이스로 누를 때 게임이 삼킨다 — 60초 차례에서 그 한 번이 시간 초과 벌칙이 된다.
    /// v0.3.66: 생일 축하 창이 더해져 **여섯**이다. 글을 받지 않지만 두 초상 · [이걸로 받을게요] · [지금 입기] 가 키보드로도 눌린다(뽑기 창과 같은 이유).
    static var standaloneWindowIDs: Set<String> {
        [CheckGomokuWindowController.frameAutosaveName,
         CheckChessWindowController.frameAutosaveName,
         CheckSettingsWindowController.frameAutosaveName,
         CheckGachaWindowController.frameAutosaveName,
         CheckTetrisDuelWindowController.frameAutosaveName,
         CheckCakeGiftWindowController.frameAutosaveName,
         CheckRummyWindowController.frameAutosaveName]
    }

    /// 지금 걸려 있는 모니터가 부를 동작. 창 게이트(창 가시성)를 통과했을 때 실행되는 바로 그 클로저다 —
    /// 헤드리스 검증이 합성 NSEvent 없이 "어느 화면에 묶여 있는가"를 확인하는 지점이다(합성 이벤트로는
    /// 팝오버·창이 열리지 않는다는 것을 이 저장소가 이미 겪었다).
    nonisolated(unsafe) private static var armed: (@MainActor () -> Void)?
    /// 같은 모니터가 쥔 ESC 처리기(인자 = 키가 향한 창 · 반환값 = 삼켰는가).
    nonisolated(unsafe) private static var armedEscape: (@MainActor (NSWindow?) -> Bool)?
    /// 같은 모니터가 쥔 조작 키 처리기(v0.3.38).
    nonisolated(unsafe) private static var armedStroke: (@MainActor (Stroke) -> Void)?
    /// 같은 모니터가 쥔 뛰기 처리기(v0.3.67).
    nonisolated(unsafe) private static var armedHop: (@MainActor (CrossyGame.Direction) -> Void)?

    #if DEBUG
    @MainActor
    static func fireForTesting() { armed?() }

    /// ESC 발화(인자 = 키가 향한 창 · 반환값 = 화면이 처리했는가 = 삼켰는가).
    /// 창을 안 주면 "키가 아직 어느 창에도 안 간 순간"과 같다 — 소유권 게이트가 있으면 거짓이 돌아온다.
    @MainActor
    @discardableResult
    static func fireEscapeForTesting(_ eventWindow: NSWindow? = nil) -> Bool { armedEscape?(eventWindow) ?? false }

    /// 조작 키 발화. 합성 NSEvent 로는 창·팝오버가 열리지 않으므로, 모니터가 **어느 화면의 클로저를 쥐고
    /// 있는가**를 이 지점으로 확인한다(`fireForTesting` 과 같은 규약).
    @MainActor
    static func fireStrokeForTesting(_ stroke: Stroke) { armedStroke?(stroke) }

    /// 뛰기 발화(v0.3.67) — `fireStrokeForTesting` 과 같은 규약.
    @MainActor
    static func fireHopForTesting(_ direction: CrossyGame.Direction) { armedHop?(direction) }
    #endif
}

// MARK: - 조작 키 → 입력 (순수)

/// 조작 키 한 번을 `MiniGameInput` 에 반영하는 **순수 규칙**. 화면(@State)에서 떼어 둔 이유는 하나다 —
/// "눌린 채 판이 끝나는" 출구가 여섯이라 각 출구를 테스트가 따로 재야 하는데, SwiftUI 뷰 안의 @State 는
/// 헤드리스에서 못 두드린다.
///
/// 규칙 넷(스펙 §4):
///  ① 뗌은 게이트와 무관하게 언제나 반영한다(모니터가 이미 그렇게 부른다).
///  ② 누름은 얼어 있으면 안 센다(정지 중 스크림 뒤에서 판이 움직이면 정지가 아니다).
///  ③ 정지에 들어가면 눌림을 비운다 — 재개 뒤 계속 누르고 있어도 안 움직인다(3초 카운트다운의 취지와 맞다).
///  ④ ⌘ 를 누르는 순간 사라지는 keyUp 은 여기서 못 막는다 — 잎 뷰의 8초 그물(`TetrisKeyWatchdog`)이 맡는다.
enum MiniGameKeyLatch {
    /// 한 번의 사건을 반영한다.
    static func apply(_ stroke: MiniGameSpaceKey.Stroke, to input: inout MiniGameInput, isFrozen: Bool) {
        guard stroke.isDown else { return release(stroke.key, from: &input) }
        guard !isFrozen else { return }
        switch stroke.key {
        case .moveLeft: input.moveLeftHeld = true
        case .moveRight: input.moveRightHeld = true
        case .softDrop: input.softDropHeld = true
        case .rotateCW: input.rotateClockwiseCount &+= 1
        case .rotateCCW: input.rotateCounterClockwiseCount &+= 1
        case .hold: input.holdCount &+= 1
        }
    }

    /// 뗌. **엣지 키(회전·홀드)의 뗌은 아무 일도 하지 않는다**(멱등) — 게이트 밖에서 온 뗌도 안전해야 한다.
    static func release(_ key: MiniGameSpaceKey.GameKey, from input: inout MiniGameInput) {
        switch key {
        case .moveLeft: input.moveLeftHeld = false
        case .moveRight: input.moveRightHeld = false
        case .softDrop: input.softDropHeld = false
        case .rotateCW, .rotateCCW, .hold: break
        }
    }

    /// 눌린 채 판이 끝나는 **모든 출구**가 부르는 한 줄. 카운터는 건드리지 않는다(이미 지나간 사건이다).
    static func releaseAll(_ input: inout MiniGameInput) {
        input.moveLeftHeld = false
        input.moveRightHeld = false
        input.softDropHeld = false
    }
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

        /// **정지 상한(초).** 넘으면 판을 그 점수로 확정하고 끝낸다(무효가 아니다).
        ///
        /// 왜 필요한가: 서버는 정지를 **모른다** — 라운드 토큰의 만료를 `clock_timestamp() - started_at` 실시간으로만
        /// 재고(20260914010000:296-297), 유효기간은 30분이다. 클라가 판 시작 때 토큰을 최대 12분 묵은 것까지
        /// 재사용하고(WorkTimerStoreMiniGame) 테트리스 한 판이 최장 9분쯤이므로, 남는 여유가 **9분 안팎**이다.
        /// 그 이상 멈춰 두면 돌아와 끝내도 제출이 `token_expired` 로 거절된다 — **멈춰 뒀다는 이유로 기록을 잃는다.**
        /// 5분에서 잘라 그 시점 점수를 확정하면, 잃는 것은 "이어서 더 할 기회"뿐이고 번 점수는 남는다.
        /// 이것은 설정 스위치가 아니라 게임 상수다(2026-09-15 '자동 종료는 사용자 스위치로 주지 않는다').
        /// 거는 범위는 **접었을 때 기록이 남는 게임**이다(v0.3.62 · `quittingKeepsTheScore`) — 0.3.61 까지는
        /// "두 기존 게임은 한 판이 짧아 이 여유를 쓸 일이 없다"로 테트리스에만 걸었는데, 자동 정지(키 상실)가
        /// 그 전제를 무너뜨려 플래피가 들어왔다. 타이밍 바는 접어도 남는 것이 없어 빠진다.
        ///
        /// **이 상한은 앱이 켜져 있는 동안만 산다** — 집행하는 쪽이 1초씩 자는 Task 라 프로세스가 죽으면 같이
        /// 죽는다(`armPauseWatchdog`). 5분이 차기 전에 앱을 끄면 그 판 점수는 어디에도 안 남는다.
        static let pauseLimitSeconds = 5 * 60

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

        /// **ESC 한 번**의 전이(0.3.62). 게이트에 걸리면 `nil` 이다 — 수신처는 그때 이벤트를 **안 삼키고**
        /// 남의 창으로 흘려보낸다(그래야 그 창의 ESC, 예컨대 팝오버 닫기가 산다).
        ///
        /// 왜 뷰 클로저에서 떼어내 여기 두는가: 판정이 클로저 안에 있던 동안은 헤드리스에서 부를 수가 없어
        /// 이 게이트를 지키는 단언이 전부 **소스의 모양**(substring·순서)뿐이었다. 그래서 게이트 극성을
        /// 뒤집어도(`guard !strokeBelongsToGame`) `gameWindow` 에 nil 을 넘겨도 시험이 통째로 초록이었다 —
        /// 그 구멍으로 되살아나는 것이 바로 이 게이트가 막는 사고다(팝오버를 닫으려고 누른 ESC 가 게임 창으로
        /// 가 정지해 둔 판을 3-2-1 뒤 재개한다. 조작키는 `strokeBelongsToGame` 가 전부 막으므로 한 수도 못 두고
        /// 탑아웃 → 그 점수로 확정되고, 그 ESC 는 삼켜져 팝오버도 안 닫힌다).
        ///
        /// `nil` 인 자리 둘:
        ///   · **키가 게임 창으로 간 것이 아니다** — 남의 창·팝오버·'아직 어느 창에도 안 간 순간'. 판정은
        ///     방향키와 같은 `strokeBelongsToGame`(이벤트 창이 게임 창과 같은 객체인가 + 보이는가)이다.
        ///   · **판이 도는 중이 아니다** — 시작 전·결과 화면의 ESC 까지 먹으면 다른 화면의 취소 키를 훔친다.
        ///
        /// 셋째 가드(`next != self`)는 **오늘은 도달할 수 없다** — `isPlaying` 이 참이면 `toggled` 가 세 상태
        /// 모두에서 제자리를 안 돌려준다. 지우지 않고 두는 이유는 `toggled` 에 제자리 전이가 생기는 날
        /// "바뀌지도 않았는데 ESC 를 삼키는" 상태를 여기서 막기 위해서다. 재현 가능한 분기로 읽지 마라
        /// (그래서 위 목록에서 뺐다 — 뮤테이션을 넣어도 빨개지는 시험이 없는 것이 정상이다).
        ///
        /// 규칙은 `toggled(isPlaying:)` **한 벌**이다. 여기서 베껴 적으면 두 벌이 되어 언젠가 갈린다.
        @MainActor
        func escaped(eventWindow: NSWindow?, gameWindow: NSWindow?, isPlaying: Bool) -> PauseState? {
            guard MiniGameSpaceKey.strokeBelongsToGame(eventWindow, gameWindow: gameWindow) else { return nil }
            guard isPlaying else { return nil }
            let next = toggled(isPlaying: isPlaying)
            guard next != self else { return nil }
            return next
        }

        /// **정지 상한을 이 게임에 거는가.** 기준은 게임 이름이 아니라 **"접었을 때 기록이 남는가"** 다 —
        /// 상한이 하는 일은 `quitRound()` 로 판을 접는 것 하나이고, 접는 결과가 게임마다 다르기 때문이다.
        /// 기록이 남는 게임에서 상한은 **점수를 건진다**(멈춰 뒀다는 이유로 토큰이 늙어 판을 통째로 잃는 것을
        /// 막는다). 기록이 안 남는 게임에서는 같은 동작이 **판을 없앤다** — 거기 걸면 돕는 게 아니라 뺏는다.
        ///
        /// 코드에서 확인한 사실(2026-10-21):
        ///   · 테트리스·플래피 — `interrupt()` 가 `phase = .result` 로 **결과를 확정**하고(TetrisGame·FlappyGame),
        ///     잎 뷰의 `onChange(of: game.phase)` 가 그 전이에서 `host.onFinished(점수)` 를 부른다 → 기록이 남는다.
        ///   · 타이밍 바 — `interrupt()` 가 `game.invalidate()` 만 한다(MiniGameTimingBar). phase 가 `.ready` 로
        ///     되돌아가고 `onFinished` 는 **안 불린다** → 남는 것이 없다(10라운드를 못 채워 애초에 점수가 없다).
        ///
        /// 그래서 타이밍 바의 정지는 상한 없이 얼어 있어도 **해롭지 않다**: 프레임 루프가 멈춰 있어 유휴 0% 는
        /// 그대로고(`TimelineView(.animation(paused:))`), 접어 봐야 건질 점수가 없으며, 라운드 토큰이 30분에
        /// 만료되면 어차피 기록되지 않는다 — 상한이 있든 없든 그 판의 결과는 '없음'으로 같고, 상한을 걸면
        /// 돌아와 이어서 끝낼 기회만 사라진다.
        ///
        /// **게임이 늘면 여기서 멈춰 서서 그 게임의 `interrupt()` 를 읽어라.** 기본 가지를 두지 않는 이유다.
        static func quittingKeepsTheScore(_ kind: MiniGameKind) -> Bool {
            switch kind {
            // 길건너 아잉이(v0.3.67)도 `interrupt()` 가 그 점수로 결과를 확정한다(CrossyGame) — 접어도 기록이 남는다.
            case .tetris, .flappy, .crossy: return true
            case .timingBar: return false
            }
        }

        /// **창이 키를 잃었을 때**의 전이(0.3.62 — 실사용 제보 "테트리스 일시정지하고 다른 창을 클릭하면
        /// 아예 끝나버려요"의 수리). `toggled(isPlaying:)` 를 재사용하지 않는 이유는 **방향이 하나**라는 것이다 —
        /// 키 상실은 언제나 '얼린다'이고 절대 풀지 않는다. `toggled` 를 그대로 쓰면 이미 정지해 둔 판이 키를
        /// 잃는 순간 `.resuming` 으로 **풀려** 안 보이는 창에서 3-2-1 이 흐른다(제보의 반대 방향 사고다).
        ///
        /// `nil` 은 "아무 일도 하지 않는다"다(지금 상태를 그대로 둔다). 두 자리에서 돌려준다:
        ///   · **판이 도는 중이 아니다** — 시작 전·결과 화면에서 얼리면 클릭이 안 먹는 창이 된다(위 `toggled` 와 같은 근거).
        ///   · **이미 `.paused` 다** — 여기서 또 얼리면 수신처가 정지 감시(`armPauseWatchdog`)를 새로 걸고,
        ///     그 시계는 1초 수면부터 다시 시작한다. 1초 안에 키를 잃었다 되찾기를 반복하면 누적(`pausedSecondsUsed`)이
        ///     영영 안 올라 5분 상한이 통째로 무력해진다 — 그 상한은 순위 공정성의 보루다.
        func resigningKey(isPlaying: Bool) -> PauseState? {
            guard isPlaying else { return nil }
            switch self {
            case .paused: return nil
            // 카운트다운 중이면 **취소하고 다시 언다.** 안 그러면 안 보이는 창에서 3-2-1 이 흘러 판이 저절로 풀린다.
            case .none, .resuming: return .paused
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
    /// 이 판에서 **누적으로** 멈춰 있던 초. 정지를 풀어도 0 으로 안 돌아간다 — 상한이 회당이면
    /// "4분 59초 멈춤 → 재개 → 다시 멈춤"을 반복해 벽시계를 무한히 늘릴 수 있고, 그러면 상한이
    /// 막으려던 바로 그 일(토큰이 늙어 판을 통째로 잃는 것)이 그대로 일어난다. 새 판에서만 0 이 된다.
    @State private var pausedSecondsUsed = 0
    /// 정지 감시(v0.3.38). 너무 오래 멈춰 있으면 그 점수로 확정하고 판을 끝낸다 — 아래 `pauseLimitSeconds` 참조.
    @State private var pauseWatchdog: Task<Void, Never>?
    /// 판 도중 토큰 감시(v0.3.67 — 끝이 정해지지 않은 판만). `tokenKeeperInterval` 마다 스토어에 "토큰이 늙었으면 갈아 끼워라" 를 묻는다.
    @State private var tokenKeeper: Task<Void, Never>?

    /// 토큰 감시 간격(초). 갈아 끼우는 나이(20분)와 TTL(30분) 사이 10분 안에 스무 번 묻는다.
    static let tokenKeeperInterval: Double = 30

    /// - Parameter initialPause: **스냅샷·프리뷰 전용** 초기 정지 상태. 앱은 언제나 `.none` 으로 연다.
    ///   `.none` 이 아니면 `isPlaying` 도 참으로 시작한다 — 정지는 진행 중일 때만 가능한 상태이기 때문이다.
    init(store: WorkTimerStore, clipsOverflowInsteadOfScroll: Bool = false, initialPause: PauseState = .none) {
        self.store = store
        self.clipsOverflowInsteadOfScroll = clipsOverflowInsteadOfScroll
        _pauseState = State(initialValue: initialPause)
        _isPlaying = State(initialValue: initialPause.isFrozen)
    }

    static let title = "미니게임"
    static let rankTitle = MiniGameBoardScope.today.boardTitle
    /// [역대] 판의 머리 제목(v0.3.67). 글자의 정본은 코어 `MiniGameBoardScope` 다(폰이 같은 글자를 쓴다).
    static let allTimeRankTitle = MiniGameBoardScope.allTime.boardTitle
    /// [역대] 판의 바닥 안내 두 줄 — 상금·정족수 안내 자리를 **같은 크기로** 대신한다(상금은 오늘 판의 것이다).
    static let allTimeRuleCaption = "사람마다 가장 높은 점수 하나만 올라가요"
    static let allTimeDayCaption = "날짜는 그 점수를 처음 낸 날이에요"
    static let allTimeFailedCaption = "역대 순위를 불러오지 못했어요"
    /// 서버에 함수가 아직 없을 때(앱이 db push 보다 먼저 나간 창). 실패가 아니라서 [다시 시도] 를 달지 않는다.
    static let allTimeUnavailableCaption = "역대 순위는 준비 중이에요 — 곧 열려요"
    static let prizeCaption =
        "자정에 1·2·3등에게 루비 \(rubyPrizes[0])·\(rubyPrizes[1])·\(rubyPrizes[2])"
    static let emptyBoard = "아직 기록이 없어요 — 첫 기록의 주인공이 되세요"
    static let loadingCaption = "불러오는 중…"
    static let failedCaption = "순위를 불러오지 못했어요"
    /// 어제 챔피언 카드에 붙는 칩. 이 카드는 **1등만** 띄우므로(서버 `minigame_yesterday_winner`
    /// 가 rank=1 로 거른다) 1등 몫을 그대로 쓴다.
    static let awardedChip = "루비 +\(rubyPrizes[0]) 받음"
    static let pauseTitle = "일시정지"
    static let resumeAction = "이어하기"
    static let quitAction = "그만두기"
    static let noRankToday = "오늘 기록 없음"

    /// 자정 상품(루비). 서버 `public.ruby_prize_amounts()` 와 **짝인 상수**다(둘 다 {20,10,5}).
    /// 2026-09-13 에 상품이 **울트라 +10(1등만) → 루비 20·10·5(1·2·3등)** 로 바뀌었고,
    /// 2026-10-14(0.3.51 · 서버 20261014120000)에 **10·5·3** 으로 줄었다가,
    /// 2026-10-22(0.3.64 · 서버 20261023131000) 사용자 결정("일반 미니게임 3종 상금루비 올려야할듯 20 10 5 로 다시 해줘")으로
    /// **20·10·5** 로 돌아왔다.
    /// 서버 배열을 고치면 여기도 같이 고쳐야 하단 안내가 거짓말이 되지 않는다 — 서버는 금액을 내려 주지 않는다
    /// (`minigame_yesterday_winner` 는 awarded 참/거짓뿐). 폰 `GamesMiniGameText`·`RankingsText` 에도 같은 상수가 있다.
    static let rubyPrizes = [20, 10, 5]

    /// 자정 상품 정족수. 서버 `public.minigame_prize_quorum()` 과 **짝인 상수**다(둘 다 5).
    /// 서버는 지급을 막고 화면은 그 조건을 미리 알린다 — 서버 함수를 바꾸면 여기도 같이 바꿔야
    /// "5명부터 지급"이 거짓말이 되지 않는다.
    static let prizeQuorum = 5

    var body: some View {
        // 어제 1등 카드는 [오늘] 판에만 선다 — [역대] 에서는 그 48pt 를 순위 행이 쓴다(무스크롤 9 → 10행).
        let layout = MiniGameWindowLayout.layout(hasChampionRow: showsChampionCard)
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
        // 툴팁 말풍선 레이어(v0.3.25) — 미니게임 창 루트. 캔버스·순위 열의 클리핑 바깥이다.
        .checkTooltipLayer()
        // 사람 아바타의 캐릭터 한 표(2026-09-20) — 미니게임 창 루트(오늘 순위 · 어제 1등의 아바타가 이 아래다).
        .appUserAvatarCharacters(from: store)
        .onAppear { installSpaceKey() }
        .onDisappear {
            MiniGameSpaceKey.remove()
            cancelResume()
            cancelTokenKeeper()
            // 출구 ⑧ 뷰 사라짐. ⚠️ AppKit 창은 orderOut 뒤에도 뷰가 살아 있어 이 콜백이 **안 올 수 있다**
            // (install 의 ★ 주석 — 2026-09-09 실측). 그래서 이것만 믿지 않고 아래 출구들에도 같이 건다.
            MiniGameKeyLatch.releaseAll(&input)
        }
        .onChange(of: store.miniGameInterruptToken) { _, _ in
            // 판이 끝났다(창 닫힘·로그아웃·종류 전환·[그만두기]·패널 닫기). 눌린 채 끝났어도 래치를 풀어
            // 다음 판의 첫 클릭이 먹히게 한다. 출구 ②~⑥의 **공통 수신처**다 — 토큰을 올리는 다섯 자리가
            // 전부 여기로 모인다(WorkTimerStoreMiniGame · CheckMiniGameWindow · WorkTimerStore.signOut).
            // ★ **포커스 상실은 여기로 안 온다**(0.3.62) — 그 신호는 판을 끝내지 않고 멈추므로 아래
            //   `miniGamePauseRequestToken` 수신처(출구 ⑩)가 따로 받는다. 거기를 이 자리로 합치면
            //   고치려던 제보("다른 창을 클릭하면 아예 끝나버려요")가 그대로 돌아온다.
            pressLatched = false
            isPlaying = false
            cancelResume()
            pauseState = .none
            MiniGameKeyLatch.releaseAll(&input)
            cancelTokenKeeper()
        }
        .onChange(of: store.miniGamePauseRequestToken) { _, _ in
            // 출구 ⑩ 키 상실(0.3.62). 판을 **끝내지 않고 멈춘다** — 실사용 제보 "테트리스 일시정지하고
            // 다른 창을 클릭하면 아예 끝나버려요"(0.3.61 · build 114). 자동 재개는 하지 않는다: 창이 키를
            // 되찾은 순간에 사람이 화면을 보고 있다는 보장이 없다. [이어하기] 로 3-2-1 뒤 이어서 한다.
            //
            // 할지 말지와 어디로 갈지는 순수 값이 정한다(`PauseState.resigningKey`) — 판이 안 도는 중이거나
            // 이미 `.paused` 면 nil 이고, 여기서 **아무것도 하지 않는다**(특히 정지 감시를 다시 걸지 않는다).
            guard let next = pauseState.resigningKey(isPlaying: isPlaying) else { return }
            // 순서는 `togglePause` 와 **정확히 같다**: 카운트다운 Task 를 거두고 → 눌린 키를 놓고 → 상태를
            // 옮기고 → 정지 감시를 건다. 해제가 빠지면 "← 를 누른 채 다른 창을 클릭 → 손을 뗌 → 이어하기" 에서
            // 엔진이 아직 ← 를 눌린 것으로 알고 판이 왼쪽으로 붙는다(출구 ⑦ 과 같은 함정이다).
            // 이 자리는 interruptToken 을 **안 올린다** — 올리면 고치려던 바로 그 '판이 끝남'이 돌아온다.
            cancelResume()
            MiniGameKeyLatch.releaseAll(&input)
            pauseState = next
            // `next` 는 언제나 `.paused` 다(위 순수 값의 유일한 비-nil 결과). 감시는 카드가 떠 있는 동안만 돈다.
            // 여기서는 게임 종류를 **묻지 않는다** — 범위 판정은 `armPauseWatchdog` 한 자리에 있다(수동 정지와
            // 같은 문으로 들어가야 두 길이 갈리지 않는다).
            armPauseWatchdog()
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

    /// 헤더(32pt): 종류 칩 셋 | Spacer | [일시정지](진행 중일 때만).
    private var gameHeader: some View {
        MiniGameGameHeader(
            selected: store.miniGameKind,
            isPlaying: isPlaying,
            isFrozen: pauseState.isFrozen,
            onSelect: { store.selectMiniGame($0) },
            onPause: { togglePause() },
            onGomoku: { store.openGomokuFromMiniGame() },
            onChess: { store.openChessFromMiniGame() },
            onTetrisDuel: { store.openTetrisDuelFromMiniGame() },
            onRummy: { store.openRummyFromMiniGame() }
        )
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
            // 344pt 한 줄에 "최고 99999999점"(≈96) + "오늘 N위"(≈45) + 조작 안내(테트리스 ≈200)가 같이 선다.
            // 셋 다 `minimumScaleFactor` 가 있어야 어느 하나가 통째로 잘리지 않는다 — 안내만 줄어들면
            // 조작법이 먼저 사라진다(그건 첫 판에 가장 필요한 글자다).
            .minimumScaleFactor(0.85)
            Spacer(minLength: 4)
            Text(myRank.map { "오늘 \($0)위" } ?? Self.noRankToday)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(myRank == nil ? CheckTheme.secondaryText : CheckTheme.accent)
                .monospacedDigit()
                .lineLimit(1)
            Spacer(minLength: 4)
            // ★ 점수를 못 올렸다는 안내는 **새 줄을 만들지 않고** 조작 안내 자리를 빌린다(v0.3.17).
            //   이 스트립은 32pt 고정이고 창 레이아웃이 순수 상수로 못 박혀 있다 — 줄을 더하면
            //   `MiniGameLayout` 전부를 다시 재야 한다. 셋 중 조작 안내가 제일 덜 급하고,
            //   안내가 뜨는 순간은 이미 판이 끝난 뒤라 조작법을 볼 이유도 없다.
            //   조용히 삼키지 않는 이유: 삼키면 "잘 놀았는데 순위표에 없다"가 되고 재현도 신고도 안 된다.
            Text(store.miniGameSubmitNotice ?? store.miniGameKind.controlHint)
                .font(.caption2)
                .foregroundStyle(store.miniGameSubmitNotice == nil ? CheckTheme.secondaryText : CheckTheme.danger)
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
            // 끝난 판은 **장부를 거쳐** 올린다(v0.3.67) — 판을 접는 문(칩 전환 · 창 닫기)이 먼저 올렸으면 두 번 안 올린다.
            onFinished: { score in store.finishMiniGameLiveRound(kind: kind, score: score) },
            onPlayingChanged: { playing in
                isPlaying = playing
                // ★ 판이 **시작되는** 이 순간이 서버 토큰을 받는 자리다(v0.3.17 위조 차단).
                //   두 게임이 전부 이 한 호스트를 지나므로 배선 지점이 하나다 — 게임마다 따로 붙이면
                //   한쪽을 빠뜨렸을 때 그 게임 점수만 통째로 안 올라간다(겉으론 안 보인다).
                //   `beginMiniGameRound` 는 Task 로 띄우고 기다리지 않는다(60Hz 판을 막지 않는다).
                if playing {
                    store.beginMiniGameRound(kind: kind)
                    // 진행 중인 판의 장부를 연다(v0.3.67 — 판을 접는 문이 잎 뷰 없이도 이 점수를 올린다).
                    store.beginMiniGameLiveRound(kind: kind)
                    // 끝이 정해지지 않은 판(길건너)은 판 도중 토큰을 갈아 끼운다 — 감시는 그 게임에서만 돈다.
                    armTokenKeeper(kind: kind)
                    // 정지 예산은 **판마다** 새로 준다(위 `pausedSecondsUsed` 주석).
                    pausedSecondsUsed = 0
                }
                // 판이 스스로 끝났으면(게임오버·10라운드 완주) 정지 상태도 같이 푼다 — 안 그러면 결과 화면 위에
                // 스크림이 남아 아무것도 못 누르는 창이 된다.
                if !playing {
                    cancelResume()
                    cancelPauseWatchdog()
                    cancelTokenKeeper()
                    pauseState = .none
                    // 출구 ① 탑아웃(자연 종료). 토큰이 **안 오르는** 자리라 공통 수신처가 못 잡는다 —
                    // 결과 카드를 보는 동안 ← 를 놓았는데 그 뗌이 반영되지 않으면 다음 판이 왼쪽으로 출발한다.
                    MiniGameKeyLatch.releaseAll(&input)
                }
            },
            onScoreChanged: { score in store.noteMiniGameLiveScore(kind: kind, score: score) }
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
            case .tetris:
                TetrisGameView(host: host, input: input)
            case .crossy:
                // 창이 닫혀 있으면 3D 판을 **통째로 내린다**(v0.3.67) — 창은 재사용되므로(CheckMiniGameWindow) 그대로 두면 SCNView ·
                // 2048² 그림자 맵 · 4× MSAA 버퍼 · 노드 풀이 닫힌 창 안에서 계속 산다. 다시 열면 새로 만든다(판은 닫을 때 이미 접혔다 —
                // 점수는 장부가 올렸다: `settleMiniGameLiveRound`).
                if store.isMiniGamePanelVisible {
                    CrossyGameView(host: host, input: input)
                } else {
                    CheckTheme.fieldFill
                }
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
        // 조작 안내는 **게임별**이다 — 하드코딩하면 테트리스에서 VoiceOver 가 틀린 조작을 읽는다
        // (`MiniGameKind.controlHint` 정적 멤버는 두 잎 뷰 전용이고, 그 밖에서 쓰면 소스 계약이 빨개진다).
        .accessibilityLabel("\(store.miniGameKind.title) 캔버스 — \(store.miniGameKind.controlHint)로 조작")
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
        // 테트리스는 플래피와 같은 의미론이다 — `interrupt()` 가 **그 점수로 결과를 확정**한다(무효가 아니다).
        // 그래서 "기록되지 않아요"라고 쓰면 거짓말이 된다. 숫자를 못 적는 이유는 위 주석과 같다(진행 중 점수가
        // 잎 뷰의 @State 안이고 `MiniGameHost` 에 내보내는 문이 없다).
        case .tetris: return "지금 그만두면 지금까지 쌓은 점수가 기록돼요"
        // 길건너도 같은 의미론이다(`CrossyGame.interrupt` 가 그 점수로 확정) — 점수 = 간 가장 앞 줄.
        case .crossy: return "지금 그만두면 지금까지 간 줄 수가 점수로 기록돼요"
        }
    }

    private func installSpaceKey() {
        // 출구 ⑨ 모니터 재설치. 갈아 끼우는 사이에 도착한 뗌은 **아무도 못 받는다** —
        // 옛 모니터는 이미 떨어져 나갔고 새 모니터는 아직 안 걸렸다. 그 창을 여기서 닫는다.
        MiniGameKeyLatch.releaseAll(&input)
        MiniGameSpaceKey.install(
            // 이 화면이 살아 있고 **게임 창이 실제로 화면에 떠 있을 때만** 스페이스를 삼킨다.
            // (키 창 판정은 모니터에서 뺐다 — 창을 막 연 순간 키가 아직 안 넘어와 스페이스가 죽었다.)
            shouldConsume: { CheckMiniGameWindowController.shared.isWindowOnScreen },
            action: {
                // 정지 중 스페이스는 점프가 아니다(스크림 뒤에서 판이 움직이면 정지가 아니다).
                guard !pauseState.isFrozen else { return }
                input.actionCount += 1
            },
            // ESC 는 **그 키가 실제로 게임 창으로 간 것일 때만** 받는다 — 스페이스와 달리 짝 게이트를 단다.
            // 게이트도 전이도 순수 값 하나(`PauseState.escaped`)가 정하고 여기는 배선뿐이다 — 판정이 이
            // 클로저 안에 있던 동안은 헤드리스에서 못 불러 그물이 소스의 모양밖에 못 쟀다(그 함수 머리말).
            //
            // 왜 필요한가(v0.3.62): 키를 잃으면 판을 **끝내지 않고 멈추므로** "키 없는 창에 살아 있는 정지된 판"
            // 이라는 상태가 생겼다. 위의 관대한 게이트(창 가시성 + `yieldsToOtherWindow`)는 그 상태를 못 가린다 —
            // 팝오버·할 일 보드는 identifier 가 없어 "모르는 창"으로 놓아 주므로, 거기서 **팝오버를 닫으려고**
            // 누른 ESC 가 게임 창으로 가서 정지해 둔 판을 자동 재개했다(3-2-1 뒤 60Hz 재개 → 조작키는
            // `strokeBelongsToGame` 가 전부 막아 한 수도 못 두고 탑아웃 → 그 점수로 확정). 이 수리가 못 박은
            // "자동 재개는 없다"가 ESC 한 번에 깨지고, 고치려던 제보가 다른 길로 돌아오는 자리다.
            // 게다가 그 ESC 는 삼켜져 **팝오버가 안 닫혔다**(두 번째 ESC 는 `.resuming → .paused` 로 또 삼켜진다).
            //
            // 왜 ESC 는 엄격해도 손실이 0 인가: 정지·재개는 **판이 도는 중에만** 뜻이 있고(시작 전·결과 화면의
            // ESC 는 `togglePause` 가 이미 거짓을 돌려준다), 그때 게임 창은 사용자가 보고 **클릭해 둔** 창이다.
            // 스페이스를 살린 그 관대함의 이유(창을 막 연 순간 키가 아직 안 넘어와 스페이스가 죽었다 —
            // 2026-09-09 제보)는 ESC 에 없다: 창을 막 연 그 순간에는 정지할 판이 아직 없다.
            onEscape: { eventWindow in
                guard let next = pauseState.escaped(eventWindow: eventWindow,
                                                    gameWindow: CheckMiniGameWindowController.shared.currentWindow,
                                                    isPlaying: isPlaying)
                else { return false }
                applyPause(next)
                return true
            },
            gameWindow: { CheckMiniGameWindowController.shared.currentWindow },
            // 방향·회전·홀드는 **테트리스가 도는 동안에만** 받는다. 다른 게임에서 받으면 쓰지도 않을 키를
            // 삼켜 다른 창의 커서를 훔친다(얻는 것이 0 인 위험이다).
            wantsStrokes: { store.miniGameKind == .tetris && isPlaying && !pauseState.isFrozen },
            onStroke: { handleStroke($0) },
            // 뛰기 키는 **길건너 아잉이가 고른 동안만** 받는다(다른 게임에서 받으면 쓰지도 않을 키를 삼킨다).
            // 판이 도는 중이 아니어도 받는다 — 시작 카드에서 방향키로 바로 시작한다(결과 화면의 방향키는 엔진이 무시한다).
            // 얼어 있으면 안 받는다 — 스크림 뒤에서 판이 뛰면 정지가 아니다(그 키는 남의 창 몫으로 흘러간다).
            wantsHops: { store.miniGameKind == .crossy && !pauseState.isFrozen },
            onHop: { handleHop($0) }
        )
    }

    /// 모니터가 준 뛰기 한 번. **누른 순서 그대로** 적는다(`MiniGameInput.recordHop`) — 잎 뷰는 `hops(since:)` 로
    /// 그 사이 누른 것을 순서대로 받는다(한 프레임에 둘이 와도 접히지 않는다).
    private func handleHop(_ direction: CrossyGame.Direction) {
        guard !pauseState.isFrozen else { return }
        input.recordHop(direction)
    }

    /// 모니터가 준 조작 키 한 번. 규칙은 `MiniGameKeyLatch`(순수)에 있고 여기는 배선뿐이다.
    ///
    /// **바뀐 게 없으면 `input` 에 손대지 않는다.** `&input` 로 넘기는 것만으로 `@State` 의 setter 가 불려
    /// 이 창이 통째로 다시 그려진다(같은 값 대입도 관찰자를 깨우는 그 성질 — `MiniGameFrameRateMonitor.update`
    /// 에 같은 근거가 있다). 뗌은 **게이트 밖에서도** 오므로(다른 창에서 화살표를 뗄 때) 그대로 두면
    /// 남의 창 키 조작이 이 창의 렌더를 부른다. 그래서 사본에 적용해 보고 달라졌을 때만 대입한다.
    private func handleStroke(_ stroke: MiniGameSpaceKey.Stroke) {
        var next = input
        MiniGameKeyLatch.apply(stroke, to: &next, isFrozen: pauseState.isFrozen)
        guard next != input else { return }
        input = next
    }

    // MARK: 일시정지 전이

    /// [일시정지] 버튼 · [이어하기] 가 여기로 온다. 반환값은 "화면이 실제로 처리했는가"다.
    /// ESC 는 **여기로 오지 않는다** — 소유권 게이트가 더 붙어야 해서 `PauseState.escaped` 를 거쳐
    /// 곧장 `applyPause` 로 간다(규칙은 같은 `toggled` 한 벌을 쓴다).
    @discardableResult
    private func togglePause() -> Bool {
        let next = pauseState.toggled(isPlaying: isPlaying)
        guard next != pauseState else { return false }
        applyPause(next)
        return true
    }

    /// 정해진 다음 상태를 화면에 **옮긴다.** 어디로 갈지는 순수 값이 정하고(`toggled` · `escaped`),
    /// 여기는 @State 와 Task 를 그 결과에 맞추는 일만 한다 — [일시정지] 버튼과 ESC 가 **같은 순서**를
    /// 밟게 하는 한 자리다(순서를 두 벌로 적으면 한쪽만 고쳐진 채 남는다).
    private func applyPause(_ next: PauseState) {
        cancelResume()
        // 출구 ⑦ 일시정지 — **토큰을 안 올리는 자리라 공통 수신처가 못 잡는다**(직접 확인: 이 함수 전문에
        // `store.miniGameInterruptToken` 이 한 번도 없다). 여기를 빠뜨리면 "← 를 누른 채 ESC → 손을 뗌 →
        // 재개" 에서 엔진이 아직 ← 를 눌린 것으로 알고 판이 왼쪽으로 붙는다. 재개 뒤 계속 누르고 있어도
        // 안 움직이는 것은 의도다(3초 카운트다운으로 리듬 이득을 없애는 그 결정과 같은 결).
        MiniGameKeyLatch.releaseAll(&input)
        if case .resuming = next {
            beginResume()
        } else {
            pauseState = next
        }
        // 정지 감시는 **카드가 떠 있는 동안만** 돈다. 카운트다운(`resuming`)은 3초짜리라 상한과 무관하고,
        // 재개 취소로 다시 `.paused` 가 되면 여기서 새로 걸린다(멱등 — 시계가 처음부터 다시 간다).
        if case .paused = pauseState { armPauseWatchdog() } else { cancelPauseWatchdog() }
    }

    /// 재개: 스크림은 그대로 두고 숫자만 3 → 2 → 1 로 내린다.
    private func beginResume() {
        cancelResume()
        cancelPauseWatchdog()
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

    /// 정지 감시를 건다(멱등 — 이미 걸려 있으면 갈아 끼운다). 거는 범위는 **접었을 때 기록이 남는 게임**
    /// 이다(`PauseState.quittingKeepsTheScore` — 왜 그 기준인지는 거기 적어 뒀다).
    ///
    /// 0.3.61 까지는 `guard store.miniGameKind == .tetris` 였다. 그 전제("두 기존 게임은 한 판이 짧아 이 여유를
    /// 쓸 일이 없다")는 **v0.3.62 의 자동 정지가 무너뜨렸다** — 이제 플래피도 다른 창을 클릭하는 것만으로
    /// 정지에 들어가므로, 테트리스에만 남기면 플래피의 판이 **무기한 정지**로 남고 30분 뒤 돌아와 이어해도
    /// 라운드 토큰이 서버 TTL 을 넘겨 `token_expired` 로 거절된다(= 0.3.61 이 포커스 상실 때 해 주던
    /// '그 점수로 확정'이 플래피에서 사라진다). 그렇다고 가드를 **통째로 걷으면** 범위가 한 칸 넓어져
    /// 타이밍 바의 **수동 정지**까지 5분에 잘리는데, 거기서는 접어도 남는 것이 없어 상한이 '점수를 건진다'가
    /// 아니라 '판을 없앤다'로 뒤집힌다 — 0.3.61 에는 없던 손해다. 그래서 이름이 아니라 **기록이 남는가**로 가른다.
    ///
    /// 상한에서 `quitRound()` 로 접는 길은 [그만두기]와 같고, 그 결과(그 점수로 확정)는 0.3.61 이 포커스
    /// 상실 때 하던 것과 정확히 같다 — 되돌리는 것이지 새로 만드는 것이 아니다.
    ///
    /// **상한이 사는 경우는 "앱이 켜진 채 5분이 지난" 경우뿐이다.** 1초씩 자는 Task 라 프로세스가 죽으면
    /// 같이 죽는다 — 자동 정지 뒤 5분 안에 ⌘Q 하면 그 판 점수는 어디에도 안 남는다(0.3.61 은 포커스를 잃는
    /// 그 클릭 자체로 즉시 확정했으니 거기서는 남았다). 종료 시 저장은 이 수리의 범위 밖이다.
    private func armPauseWatchdog() {
        cancelPauseWatchdog()
        // 접어도 기록이 안 남는 게임에는 안 건다 — 거는 순간 상한이 점수를 건지는 장치가 아니라 판을
        // 없애는 장치가 된다(위 머리말 · `PauseState.quittingKeepsTheScore`).
        guard PauseState.quittingKeepsTheScore(store.miniGameKind) else { return }
        // 1초씩 센다. **남은 시간이 아니라 쓴 시간을 누적**하므로, 정지를 풀었다 다시 걸어도
        // 시계가 처음부터 가지 않는다(`pausedSecondsUsed` 가 판 단위로 산다).
        pauseWatchdog = Task { @MainActor in
            while pausedSecondsUsed < PauseState.pauseLimitSeconds {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                // 그 사이 이어하기·그만두기·판 종료가 있었으면 아무것도 하지 않는다(누적은 남긴다).
                guard case .paused = pauseState, isPlaying else { return }
                pausedSecondsUsed += 1
            }
            quitRound()
        }
    }

    private func cancelPauseWatchdog() {
        pauseWatchdog?.cancel()
        pauseWatchdog = nil
    }

    /// 판 도중 토큰 감시를 건다(멱등). 갈아 끼우지 않는 게임(`roundTokenMidRunRefreshSeconds == nil`)에는 안 건다.
    /// 판이 끝나면(`!playing`) · 판이 접히면(interruptToken) · 화면이 사라지면 거둔다. 정지 중에도 돈다 — 멈춰 둔 동안에도 TTL 은 흐른다.
    private func armTokenKeeper(kind: MiniGameKind) {
        cancelTokenKeeper()
        guard kind.roundTokenMidRunRefreshSeconds != nil else { return }
        tokenKeeper = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.tokenKeeperInterval))
                guard !Task.isCancelled, isPlaying else { return }
                store.keepMiniGameRoundTokenFresh(kind: kind)
            }
        }
    }

    private func cancelTokenKeeper() {
        tokenKeeper?.cancel()
        tokenKeeper = nil
    }

    /// [그만두기]. 스토어의 `abortMiniGameRound()` 가 토큰을 올려 잎 뷰의 판을 끝낸다(플래피는 그 점수로 확정,
    /// 타이밍 바는 무효). 종류 칩 잠금도 함께 풀린다.
    private func quitRound() {
        cancelResume()
        cancelPauseWatchdog()
        pauseState = .none
        isPlaying = false
        // 출구 ⑥ [그만두기]. 아래 `abortMiniGameRound()` 가 토큰을 올려 공통 수신처도 지나가지만,
        // **여기서도 푼다** — 토큰을 올리는 쪽이 스토어라 그 구현이 바뀌면(예: 이미 끝난 판이면 안 올림)
        // 이 출구만 조용히 뚫린다. 해제는 멱등이라 두 번 불러도 값이 같다.
        MiniGameKeyLatch.releaseAll(&input)
        store.abortMiniGameRound()
    }

    // MARK: 순위 열 — [오늘 | 역대] (v0.3.67 에 역대가 붙었다)

    private var myUserID: String? { store.session?.userID }

    /// 순위 열이 [역대] 를 보고 있는가. 어제 1등 카드·상금 안내는 [오늘] 판에만 있다.
    private var showsAllTime: Bool { store.miniGameBoardScope == .allTime }

    /// 어제 1등 카드를 세우는가 — [오늘] 판이고 어제 1등이 있을 때만. 레이아웃(무스크롤 행수)도 이 값 하나를 읽는다.
    private var showsChampionCard: Bool { !showsAllTime && store.miniGameYesterdayWinner != nil }

    /// 내 오늘 순위(1부터). 순위 밖/없음이면 nil.
    private var myRank: Int? {
        guard let me = myUserID, let index = store.miniGameBoard.firstIndex(where: { $0.userID == me }) else { return nil }
        return index + 1
    }

    /// 내 최고 점수. 로컬 캐시 · 오늘 내 행 · 역대 내 행 중 가장 큰 쪽이다 — 순위 응답이 로컬을 올리기 전 첫 프레임에도
    /// "최고 0점 · 오늘 953점" 같은 모순을 그리지 않는다.
    private var bestScore: Int {
        let today = myUserID.flatMap { me in store.miniGameBoard.first { $0.userID == me } }
        let allTime = myUserID.flatMap { me in store.miniGameAllTimeBoard.first { $0.userID == me } }
        return max(store.miniGameBest(store.miniGameKind), today?.bestScore ?? 0, allTime?.bestScore ?? 0)
    }

    /// 오늘 참여 인원(= 순위 행 수). 정족수 안내의 분자다.
    private var players: Int { store.miniGameBoard.count }

    /// 머리 칩의 인원 — 지금 보는 판의 행 수다([역대] 면 역대에 이름이 오른 사람 수).
    private var headerCount: Int { showsAllTime ? store.miniGameAllTimeBoard.count : players }

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
            if showsChampionCard, let winner = store.miniGameYesterdayWinner {
                MiniGameChampionCard(winner: winner, awardedChip: Self.awardedChip)
                    .frame(height: MiniGameWindowLayout.championHeight)
                Color.clear.frame(height: MiniGameWindowLayout.championSpacing)
            }
            rankList(visibleRows: visibleRows)
            Spacer(minLength: MiniGameWindowLayout.prizeSpacing)
            // 바닥 띠는 두 판 모두 **같은 크기의 카드**다 — 하나만 비우면 게임 열 하단 스트립과 한 띠로 안 읽힌다.
            Group {
                if showsAllTime { allTimeFooter } else { prizeFooter }
            }
            .frame(height: MiniGameWindowLayout.prizeHeight)
            // 게임 열의 하단 스트립과 **같은 줄**에서 끝난다.
            Color.clear.frame(height: MiniGameWindowLayout.footerBaselineGap)
        }
    }

    /// 머리글(32pt): 제목("오늘 순위" / "역대 순위") + 인원 칩 + [오늘 | 역대] 전환.
    private var rankHeader: some View {
        HStack(spacing: 6) {
            Text(store.miniGameBoardScope.boardTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(CheckTheme.primaryText)
            Spacer(minLength: 4)
            if headerCount > 0 {
                Label("\(headerCount)명", systemImage: "person.2.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(CheckTheme.secondaryText)
                    .monospacedDigit()
                    .padding(.horizontal, 8)
                    .frame(height: 20)
                    .background(Capsule().fill(Color.white.opacity(0.06)))
                    .overlay(Capsule().stroke(CheckTheme.border, lineWidth: 1))
                    .fixedSize()
            }
            MiniGameBoardScopePicker(selected: store.miniGameBoardScope) { scope in
                store.selectMiniGameBoardScope(scope)
            }
        }
    }

    /// 바닥 안내(2줄): 상품 규칙 + 정족수. 색만으로 정보를 주지 않게 아이콘과 글자를 함께 쓴다.
    /// 게임 열의 하단 스트립과 **같은 카드 처리**다(테두리 있는 fieldFill) — 한쪽만 맨 텍스트면
    /// 두 단의 바닥이 하나의 띠로 읽히지 않는다(2026-09-10 지적).
    private var prizeFooter: some View {
        footerCard {
            Label {
                Text(Self.prizeCaption)
            } icon: {
                Image(systemName: "trophy.fill").foregroundStyle(CheckTheme.pending)
            }
            Label {
                Text(quorumCaption).monospacedDigit()
            } icon: {
                Image(systemName: players >= Self.prizeQuorum ? "checkmark.seal.fill" : "person.2.fill")
                    .foregroundStyle(players >= Self.prizeQuorum ? CheckTheme.working : CheckTheme.secondaryText)
            }
        }
    }

    /// [역대] 판의 바닥 안내(2줄): 무엇이 올라가는가 + 날짜가 무엇인가. **상금 이야기는 없다** — 상금은 오늘 판의 것이다.
    private var allTimeFooter: some View {
        footerCard {
            Label {
                Text(Self.allTimeRuleCaption)
            } icon: {
                Image(systemName: "rosette").foregroundStyle(CheckTheme.accent)
            }
            Label {
                Text(Self.allTimeDayCaption)
            } icon: {
                Image(systemName: "calendar").foregroundStyle(CheckTheme.secondaryText)
            }
        }
    }

    /// 바닥 카드 껍데기 — 두 판의 안내가 **같은 글꼴·여백·테두리**를 쓰게 한 벌로 둔다.
    private func footerCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            content()
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

    /// 지금 보는 판의 행 수.
    private var boardCount: Int { showsAllTime ? store.miniGameAllTimeBoard.count : store.miniGameBoard.count }

    private var rowCount: Int { max(1, boardCount) }

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
            if boardCount == 0 {
                HStack(spacing: 8) {
                    Text(showsAllTime ? allTimeEmptyText : emptyText)
                        .font(.caption2)
                        .foregroundStyle(CheckTheme.secondaryText)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    if showsAllTime {
                        if store.miniGameAllTimeFailed, !store.miniGameAllTimeLoaded {
                            MiniGameRetryButton { store.loadMiniGameAllTimeBoard() }
                        }
                    } else if store.miniGameBoardFailed, !store.miniGameBoardLoaded {
                        MiniGameRetryButton { store.loadMiniGameBoard() }
                    }
                }
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, minHeight: MiniGameWindowLayout.rowHeight * 1.5, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(CheckTheme.fieldFill))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(CheckTheme.border, lineWidth: 1))
            } else if showsAllTime {
                ForEach(Array(store.miniGameAllTimeBoard.enumerated()), id: \.element.id) { index, entry in
                    // 오늘 행과 **같은 행 뷰**다(배지·아바타·이름·"나" 칩·우측 점수). 다른 것은 점수 앞의 작은 날짜("9/13") 하나.
                    MiniGameRankRow(
                        rank: index + 1,
                        entry: entry.rankRowEntry,
                        center: entry.center,
                        isMe: myUserID != nil && entry.userID == myUserID,
                        dateCaption: entry.dayCaption
                    )
                        .frame(height: MiniGameWindowLayout.rowHeight)
                }
            } else {
                ForEach(Array(store.miniGameBoard.enumerated()), id: \.element.id) { index, entry in
                    // 내 행에도 단다(토큰 순위판·리그와 같은 규약).
                    MiniGameRankRow(
                        rank: index + 1,
                        entry: entry,
                        center: entry.center,
                        isMe: myUserID != nil && entry.userID == myUserID
                    )
                        .frame(height: MiniGameWindowLayout.rowHeight)
                }
            }
            // 빈 안내 카드는 1.5행을 먹는다 — 자리 계산에서는 그만큼 빼되(안 그러면 단 밖으로 넘친다),
            // **등수는 1부터** 센다. 안내 문구는 순위가 아니라 메시지이므로 "1·2위는 어디 갔나"가 되면 안 된다.
            let usedRows = boardCount == 0 ? 2 : boardCount
            let firstPlaceholderRank = boardCount + 1
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

    /// [역대] 빈 목록 문구: 실패 → 실패 문구, 서버 준비 전 → 준비 중, 로드 전 → 불러오는 중, 로드 성공 → 아직 없음.
    private var allTimeEmptyText: String {
        if store.miniGameAllTimeFailed, !store.miniGameAllTimeLoaded { return Self.allTimeFailedCaption }
        if store.miniGameAllTimeUnavailable { return Self.allTimeUnavailableCaption }
        if !store.miniGameAllTimeLoaded { return Self.loadingCaption }
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

/// 게임 열 머리글(32pt). **렌더 테스트가 단독으로 자연 폭을 잰다**(internal) — 헤더가 344pt 를 넘는지는
/// 창 안에서 그려서는 알 수 없다(넘치면 SwiftUI 가 조용히 눌러 담는다). 그래서 뷰를 떼어 `.fixedSize()` 로 잰다.
struct MiniGameGameHeader: View {
    let selected: MiniGameKind
    let isPlaying: Bool
    let isFrozen: Bool
    let onSelect: (MiniGameKind) -> Void
    let onPause: () -> Void
    let onGomoku: () -> Void
    let onChess: () -> Void
    /// [1:1 테트리스] 입구(v0.3.60). **기본값이 있는 채로 맨 끝** — 머리글을 부르는 기존 호출부(테스트 여섯 곳)가 그대로 산다.
    var onTetrisDuel: () -> Void = {}
    /// [아잉 큐브] 입구(v0.3.68). 테트리스 입구와 같은 이유로 **기본값이 있는 채로 맨 끝**이다(기존 호출부 보호).
    var onRummy: () -> Void = {}

    /// 종류 칩끼리의 간격(v0.3.67 — 넷째 칩 "길건너 아잉이"가 들어오며 344pt 예산을 다시 쟀다).
    ///
    /// 칩이 셋일 때는 머리글 전체가 한 간격(6)이었다. 넷째 칩(아이콘 전용 ≈33pt + 간격)이 들어오고 고른 칩의 이름이
    /// 가장 긴 "길건너 아잉이"면, 1:1 입구 묶음이 선 머리글이 **349.5pt** 로 344 를 넘었다(실측 — V0367CrossyTests 의
    /// `headerFitsWithFourChips`). 그래서 칩끼리만 4pt 로 좁히고(테두리 있는 캡슐이라 4pt 로도 갈린다) 칩 묶음과 입구 사이
    /// Spacer 의 최소 폭을 4 → 0 으로 내렸다(바깥 간격 6 + 6 = 12pt 가 그대로 남는다). 이름을 줄이거나 칩 여백을 깎는
    /// 길은 고르지 않았다 — 이름은 사용자가 지었고, 아이콘 전용 칩 여백(8)은 V0338 이 못 박은 값이다.
    static let chipSpacing: CGFloat = 4

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: Self.chipSpacing) {
                ForEach(MiniGameKind.macCases) { kind in
                    MiniGameKindChip(
                        title: kind.title,
                        icon: kind.icon,
                        isSelected: kind == selected,
                        // 게임이 셋이 되면서 "칩 셋 + [일시정지]" 가 344pt 예산을 다툰다(사용자 확정 2026-09-23:
                        // "고른 칩만 이름, 나머지는 아이콘 전용"). 고른 칩만 이름을 다는 이유는 폭만이 아니다 —
                        // 지금 무엇을 하고 있는지는 **한 번만** 말하면 되고, 나머지는 "다른 게임으로 가는 문"이다.
                        showsTitle: kind == selected,
                        // 정지 중에는 다른 게임 칩을 **푼다** — 사용자가 원한 것이 정확히 "포기하고 다른 게임 하기"다
                        // (2026-09-10). 다른 칩을 누르면 selectMiniGame 이 토큰을 올려 판을 무효화하고 넘어간다.
                        isEnabled: !isPlaying || isFrozen || kind == selected
                    ) {
                        onSelect(kind)
                    }
                }
            }
            Spacer(minLength: 0)
            if isPlaying, !isFrozen {
                MiniGameChromeButton(title: CheckMiniGameWindowView.pauseTitle, icon: "pause.fill", tint: CheckTheme.pending) {
                    onPause()
                }
            } else {
                // 1:1 대결 창 입구 **둘**(오목 v0.3.27 · 체스 v0.3.44). 둘 다 이 창과 **별도의 넓은 창**이다
                // (사용자 결정) — 여기는 문만 둔다. [일시정지] 와 **같은 자리를 번갈아 쓴다**: 판이 도는 중에는
                // [일시정지]가 이 자리를 쓰고, **정지 중에는 이 문이 열린다**(0.3.62 — 키를 잃으면 판이 끝나는
                // 대신 멈추므로 정지한 판 위에서 누를 수 있는 문이 됐다). 누르면 `openGomokuFromMiniGame` 쪽의
                // `closeMiniGamePanel()` 이 판을 끝낸다 — 대결 창으로 가는 것은 분명한 의사표시다.
                // **누르면 이 창은 내려간다**(0.3.50 — `WorkTimerStore.openGomokuFromMiniGame`): 대결 창과 둘이 떠 있지 않게.
                // 팝오버를 닫지 않는다 — 이 창에서 오는 길이면 팝오버는 이미 닫혀 있다(토글이라 부르면 오히려 열린다).
                //
                // ★ **입구 둘 다 이름을 단다 — 실측으로 들어간다.** 입구가 둘이 되며 344pt 예산을 다시 쟀고,
                //   이름을 둘 다 단 머리글이 **330.5pt** 였다(2026-10-05 `theHeaderFitsInThreeHundredFortyFour`
                //   의 출력). 남는 여유는 13.5pt 뿐이라 **문을 하나 더 달거나 이름을 늘리면 넘친다** —
                //   그 경계를 그 시험이 숫자로 지킨다(아이콘 전용으로 접는 길은 `showsTitle: false` 로 열어 뒀다).
                //   이름을 떼지 않은 이유: 이 버튼은 '다른 창을 여는 문' 이라 아이콘만으로는 어디로 가는지
                //   읽히지 않고, 종류 칩과 달리 **고른 상태가 없어** "지금 있는 자리" 라는 단서도 없다.
                //
                // ★ v0.3.60 — 문이 **셋**(오목 · 체스 · 테트리스)이 되며 예산을 다시 쟀다. 위 경계 그대로 이름 단 캡슐 셋은
                //   344pt 를 넘는다(`theHeaderFitsInThreeHundredFortyFour` 가 그 대조군을 잰다). 그래서 **"1:1" 을 한 번만**
                //   말하는 묶음 캡슐 하나(`MiniGameDuelEntryGroup`)로 접었다: [1:1 | 오목 | 체스 | 테트리스]. 이름은 셋 다 남는다
                //   (아이콘 전용으로 접지 않은 이유는 위와 같다) — 반복되던 "1:1 " 접두와 아이콘 셋만 빠진다.
                //   각 문은 여전히 **자기 버튼**이고(말풍선 · 보이스오버 이름 · 탭이 따로) 묶음은 그리기만 바꾼다(환경값).
                // ★ v0.3.68 — 넷째 문 [큐브](아잉 큐브 · 2~4인)가 들어오며 머리 "1:1" 을 뗐다(예산 · 뜻 — `MiniGameDuelEntryGroup` 주석).
                MiniGameDuelEntryGroup {
                    MiniGameGomokuEntryButton { onGomoku() }
                    MiniGameChessEntryButton { onChess() }
                    MiniGameTetrisDuelEntryButton { onTetrisDuel() }
                    // v0.3.68 — 아잉 큐브(2~4인)도 같은 묶음의 문이다(다른 넓은 창으로 가는 대결 문이라는 뜻이 같다).
                    MiniGameRummyEntryButton { onRummy() }
                }
            }
        }
    }
}

/// 게임 종류 칩. 선택 = accent 채움 + **이름**, 비선택 = 흐린 캡슐 + **아이콘만**.
///
/// 아이콘 전용 칩에도 `.accessibilityLabel(title)` 이 붙는다 — 아이콘은 VoiceOver 에게 아무 말도 하지 않고,
/// SF Symbol 의 기본 설명("square grid 2x2")은 게임 이름이 아니다. 말풍선(`.checkTooltip`)은 눈으로 보는
/// 사람 몫이고 이 라벨은 듣는 사람 몫이라 **둘 다** 있어야 한다.
private struct MiniGameKindChip: View {
    let title: String
    let icon: String
    let isSelected: Bool
    /// 이름을 함께 그릴지. 거짓이면 아이콘만(폭이 97 → 33 으로 준다).
    var showsTitle: Bool = true
    var isEnabled: Bool = true
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Group {
                if showsTitle {
                    Label(title, systemImage: icon)
                } else {
                    Image(systemName: icon)
                }
            }
                .font(.caption2.weight(.bold))
                .foregroundStyle(isSelected ? CheckTheme.accent : CheckTheme.secondaryText)
                // 아이콘 전용 칩은 좌우 여백을 줄인다 — 10 그대로면 아이콘 하나가 가운데 뜬 넓은 알약이 된다.
                .padding(.horizontal, showsTitle ? 10 : 8)
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
        .accessibilityLabel(title)
        .checkTooltip(title)
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
        .checkTooltip(title)
    }
}

/// 헤더의 [1:1 오목] 입구(v0.3.27). 종류 칩과 같은 26pt 캡슐이지만 **초록**이다 — 칩(파랑 = 이 창의 게임 고르기)과
/// 같은 색이면 "세 번째 게임"으로 읽히는데, 이 버튼은 다른 창을 여는 문이다. 렌더 테스트가 단독으로 폭을 잰다(internal).
struct MiniGameGomokuEntryButton: View {
    static let title = "1:1 오목"
    static let icon = "circle.grid.3x3.fill"
    static let help = "렌주룰 1:1 오목 대결 창을 열어요"

    /// 이름을 함께 그릴지. **헤더는 참**(위 ★ — 실측 330.5pt / 344pt). 예산이 더 빠듯해지는 날 접는 문이다.
    var showsTitle: Bool = true
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        MiniGameEntryCapsule(title: Self.title, icon: Self.icon, help: Self.help, segmentTitle: Self.segmentTitle,
                             showsTitle: showsTitle, hovering: hovering, action: action)
            .onHover { hovering = $0 }
    }

    /// 묶음 캡슐 안에서 쓰는 짧은 이름("1:1" 은 묶음이 한 번만 말한다).
    static let segmentTitle = "오목"
}

/// 헤더의 [1:1 체스] 입구(v0.3.44). 오목 입구와 **같은 초록 캡슐**이다 — 색의 뜻이 "이 창의 게임"(파랑 칩)이
/// 아니라 "다른 창으로 가는 1:1 대결 문"이고, 두 입구는 그 뜻이 같다. 가르는 것은 **아이콘**이다.
/// 렌더 테스트가 단독으로 폭을 잰다(internal 인 이유).
struct MiniGameChessEntryButton: View {
    static let title = "1:1 체스"
    static let icon = ChessEntryIcon.symbol
    static let help = "FIDE 규칙 1:1 체스 대결 창을 열어요"

    var showsTitle: Bool = true
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        // 아이콘 이름은 이 맥에서 실제로 풀리는 것만 쓴다(없으면 아무것도 안 그려 자리만 빈다 — ChessEntryIcon).
        MiniGameEntryCapsule(title: Self.title, icon: ChessEntryIcon.resolved, help: Self.help,
                             segmentTitle: Self.segmentTitle,
                             showsTitle: showsTitle, hovering: hovering, action: action)
            .onHover { hovering = $0 }
    }

    static let segmentTitle = "체스"
}

/// 헤더의 [1:1 테트리스] 입구(v0.3.60). 오목·체스 입구와 **같은 부품**이다. 아이콘은 두 판이 나란히 선 그림
/// (`TetrisDuelEntryIcon`) — 이 창의 솔로 테트리스 칩(`square.grid.2x2.fill`)과 갈린다. 렌더 테스트가 단독으로 잰다(internal).
struct MiniGameTetrisDuelEntryButton: View {
    static let title = "1:1 테트리스"
    static let segmentTitle = "테트리스"
    static let help = "공격형 1:1 테트리스 대결 창을 열어요"

    var showsTitle: Bool = true
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        MiniGameEntryCapsule(title: Self.title, icon: TetrisDuelEntryIcon.resolved, help: Self.help,
                             segmentTitle: Self.segmentTitle,
                             showsTitle: showsTitle, hovering: hovering, action: action)
            .onHover { hovering = $0 }
    }
}

/// 헤더의 [아잉 큐브] 입구(v0.3.68). 오목·체스·테트리스 입구와 **같은 부품**이다. 2~4인 게임이라 이름에 "1:1" 이 없다.
/// 렌더 테스트가 단독으로 잰다(internal).
struct MiniGameRummyEntryButton: View {
    static let title = RummyInviteText.gameName
    static let segmentTitle = RummyInviteText.entrySegmentTitle
    static let help = "2~4인 아잉 큐브 창을 열어요"

    var showsTitle: Bool = true
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        MiniGameEntryCapsule(title: Self.title, icon: RummyEntryIcon.resolved, help: Self.help,
                             segmentTitle: Self.segmentTitle,
                             showsTitle: showsTitle, hovering: hovering, action: action)
            .onHover { hovering = $0 }
    }
}

/// 묶음 안에서는 입구가 **조각(세그먼트)** 으로 그려진다는 표시(환경값). 입구 버튼의 호출 모양은 그대로 둔 채
/// 그리기만 바꾸려고 둔 문이다 — 버튼마다 인자를 하나씩 더하면 세 입구의 호출부가 갈린다.
private struct MiniGameDuelEntryCompactKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    fileprivate var miniGameDuelEntryCompact: Bool {
        get { self[MiniGameDuelEntryCompactKey.self] }
        set { self[MiniGameDuelEntryCompactKey.self] = newValue }
    }
}

/// 1:1 대결 입구 **묶음**(v0.3.60): 초록 캡슐 하나에 "1:1" 머리 + 문 조각들. 렌더 테스트가 단독으로 폭을 잰다(internal).
///
/// 왜 묶음인가: 문이 셋이 되자 이름 단 캡슐 셋이 344pt 를 넘었다(머리글 실측은 V0338 의 헤더 시험이 출력한다).
/// "1:1 오목 · 1:1 체스 · 1:1 테트리스" 에서 겹치는 것은 "1:1 " 과 캡슐 테두리뿐이라, 그것을 한 번만 그리면 이름 셋이
/// 그대로 들어간다. 색은 입구와 같은 초록이다(뜻: "다른 창으로 가는 1:1 대결 문").
///
/// ★ v0.3.68 — 넷째 문(아잉 큐브 · 2~4인)이 들어오며 **머리 "1:1" 을 뗐다.** 두 가지 까닭이다.
///   ① 344pt 예산: 문 넷 묶음 머리글이 길건너 아잉이를 고른 채 **369pt** 였다(V0367CrossyTests.headerFitsWithFourChips 실측).
///      머리 글자(≈28pt)를 떼고 조각 좌우 여백을 6 → 4 로 줄여 예산 안에 넣었다 — 숫자는 그 시험과 V0338 헤더 시험이 지킨다.
///   ② 뜻: 아잉 큐브는 1:1 이 아니다. 묶음의 뜻("다른 넓은 창으로 가는 대결 문")은 초록 캡슐 자체가 말하고, 각 문의 전체 이름
///      ("1:1 오목" · "아잉 큐브" …)은 말풍선과 보이스오버 이름에 그대로 남는다(조각은 짧은 이름만 그린다).
struct MiniGameDuelEntryGroup<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 0) {
            content
        }
        .padding(.horizontal, 3)
        .frame(height: 26)
        .background(Capsule().fill(CheckTheme.working.opacity(0.14)))
        .overlay(Capsule().stroke(CheckTheme.working.opacity(0.45), lineWidth: 1))
        .environment(\.miniGameDuelEntryCompact, true)
        .fixedSize()
    }
}

/// 두 입구가 **한 부품**을 쓴다(같은 사실은 한 부품 — 각자 만들면 수치가 갈린다: 오목에서 모서리 16 vs 14 ·
/// 아이콘 32 vs 34 로 갈려 있던 사고가 그 자리다).
private struct MiniGameEntryCapsule: View {
    let title: String
    let icon: String
    let help: String
    /// 묶음(`MiniGameDuelEntryGroup`) 안에서 쓰는 짧은 이름.
    let segmentTitle: String
    let showsTitle: Bool
    let hovering: Bool
    let action: () -> Void

    @Environment(\.miniGameDuelEntryCompact) private var compact

    var body: some View {
        if compact {
            segment
        } else {
            capsule
        }
    }

    /// 묶음 안의 조각 — 캡슐 테두리는 묶음이 한 번 그리고, 조각은 글자와 호버 바탕만 그린다.
    private var segment: some View {
        Button(action: action) {
            Text(segmentTitle)
                .font(.caption2.weight(.bold))
                .foregroundStyle(CheckTheme.working)
                .padding(.horizontal, 4)
                .frame(height: 20)
                .background(Capsule().fill(CheckTheme.working.opacity(hovering ? 0.24 : 0)))
                .contentShape(Capsule())
                .fixedSize()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .checkTooltip(help)
    }

    private var capsule: some View {
        Button(action: action) {
            Group {
                if showsTitle {
                    Label(title, systemImage: icon)
                } else {
                    Image(systemName: icon)
                }
            }
                .font(.caption2.weight(.bold))
                .foregroundStyle(CheckTheme.working)
                // 아이콘 전용은 좌우 여백을 줄인다(종류 칩과 같은 수치 — 10 그대로면 넓은 알약이 된다).
                .padding(.horizontal, showsTitle ? 10 : 8)
                .frame(height: 26)
                .background(Capsule().fill(CheckTheme.working.opacity(hovering ? 0.24 : 0.14)))
                .overlay(Capsule().stroke(CheckTheme.working.opacity(0.45), lineWidth: 1))
                .contentShape(Capsule())
                .fixedSize()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .checkTooltip(help)
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
        .checkTooltip(title)
    }
}

/// 어제 챔피언 카드(48pt). 왕관 · 아바타 · 이름 · 점수 · "루비 +20 받음"(1등 몫 `rubyPrizes[0]`). 금색 채움 + 금색 테두리로 순위 행과 층을 가른다.
private struct MiniGameChampionCard: View {
    let winner: MiniGameWinner
    let awardedChip: String

    var body: some View {
        // ★ 열 규격은 `MiniGameRankRow` 와 **같은 숫자**다(배지/왕관 22 · 간격 7 · 앞 5 · 뒤 9 ·
        //   점수 칸은 `MiniGameRankRow.scoreWidth` — v0.3.38 에 46 → 66, 근거는 그 상수 주석).
        //   갈리면 어제 1등의 이름과 점수가 아래 순위 행들과 어긋나 목록이 두 개로 읽힌다
        //   (2026-09-10 실측: 이름 7pt · 점수 56.5pt 어긋남).
        HStack(spacing: MiniGameRankRow.columnSpacing) {
            Image(systemName: "crown.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(MiniGameMedal.gold)
                .frame(width: MiniGameRankRow.badgeSize, height: MiniGameRankRow.badgeSize)
            // 어제 1등도 이 화면의 아바타다 — 바로 아래 순위 행들이 전부 배지를 다는데 여기만 비면
            // 같은 목록의 첫 줄만 센터를 숨긴 꼴이 된다. overlay 라 열 규격(위 주석)은 1pt 도 안 움직인다.
            CheckAvatarView(
                name: winner.name,
                userID: winner.userID,
                avatarURL: winner.avatarURL,
                size: MiniGameRankRow.avatarSize,
                center: winner.center
            )
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
            // 받음 칩은 점수 **앞**이다 — 뒤에 두면 칩 폭만큼 점수가 밀려 오른쪽 끝이 목록과 갈린다.
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

/// 순위 행(30pt): 순위 배지 22 · 아바타 22 · 이름(+"나" 칩) · 우측 "N점". [역대] 판은 같은 행에 점수 앞 작은 날짜("9/13")가 붙는다(v0.3.67).
/// 1·2·3위는 금·은·동 배지, 4위부터는 투명 배지에 흐린 숫자. 내 행은 accent 채움 + 테두리다.
struct MiniGameRankRow: View {
    /// 열 규격. **어제 챔피언 카드가 같은 값을 읽는다** — 두 벌로 적으면 두 카드의 이름·점수가 어긋난다.
    static let badgeSize: CGFloat = 22
    static let avatarSize: CGFloat = 22
    static let columnSpacing: CGFloat = 7
    static let leadingPadding: CGFloat = 5
    static let trailingPadding: CGFloat = 9
    /// 점수 칸은 **고정폭**이다 — 자릿수가 달라도 오른쪽 끝이 한 줄로 서야 순위표로 읽힌다.
    ///
    /// v0.3.38 에 46 → **66** 으로 넓혔다. 46 은 "타이밍 바 상한 1000 이라 '1000점'이 들어갈 폭"이었는데,
    /// 테트리스 상한이 1억이라 "12345678점"(9자리+점)이 들어와야 한다. `.minimumScaleFactor(0.8)` 덕에
    /// 잘리지는 않았지만 **행마다 글자 크기가 달라져** 순위표가 한 줄로 안 선다(6자리부터 눈에 띈다).
    /// 66 의 대가는 이름 칸이다: 행 고정분 = 5+22+7+22+7+4+66+9 = 142 → 이름 172pt(314 − 142).
    /// 이름은 이미 `lineLimit(1) + minimumScaleFactor(0.75)` 라 긴 별명도 줄어들 뿐 잘리지 않는다.
    /// **어제 챔피언 카드가 같은 상수를 읽는다** — 두 벌로 적으면 두 카드의 점수가 어긋난다.
    static let scoreWidth: CGFloat = 66
    /// [역대] 행의 날짜 칸(v0.3.67) — "12/31" 이 9pt 로 들어가는 **고정폭**이라 행마다 점수 칸 왼쪽 끝이 한 줄로 선다.
    /// 대가는 이름 칸이다: 30 + 간격 7 = 37pt → 이름 135pt(172 − 37). 오늘 행은 이 칸이 없어 172pt 그대로다.
    static let dateWidth: CGFloat = 30

    let rank: Int
    let entry: MiniGameBoardEntry
    /// 소속 센터. 아바타 모서리에 겹쳐 그린다.
    var center: String? = nil
    var isMe: Bool = false
    /// [역대] 행의 작은 날짜("9/13" — 그 점수를 처음 낸 KST 날). nil 이면 칸 자체가 없다(오늘 행).
    var dateCaption: String? = nil

    private var medal: Color? { MiniGameMedal.color(rank: rank) }

    var body: some View {
        HStack(spacing: Self.columnSpacing) {
            badge
            CheckAvatarView(name: entry.name, userID: entry.userID, avatarURL: entry.avatarURL, size: Self.avatarSize, center: center)
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
            if let dateCaption {
                Text(dateCaption)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(CheckTheme.secondaryText)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: Self.dateWidth, alignment: .trailing)
                    .accessibilityLabel(dateCaption + " 달성")
            }
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

/// 순위 열 머리의 [오늘 | 역대] 전환(v0.3.67). **한 캡슐 안의 두 칸**이다 — 떨어진 칩 둘이면 게임 열 머리의
/// 종류 칩 줄(이 창의 게임 고르기)과 같은 물건으로 읽힌다. 고른 칸의 말씨(accent 채움 + 테두리)는 종류 칩과 같다.
/// 렌더 테스트가 단독으로 폭을 잰다(internal) — 머리글 314pt 에 제목·인원 칩과 함께 서야 한다.
struct MiniGameBoardScopePicker: View {
    let selected: MiniGameBoardScope
    let onSelect: (MiniGameBoardScope) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(MiniGameBoardScope.allCases) { scope in
                let isSelected = scope == selected
                Button { onSelect(scope) } label: {
                    Text(scope.label)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(isSelected ? CheckTheme.accent : CheckTheme.secondaryText)
                        .padding(.horizontal, 9)
                        .frame(height: 20)
                        .background(Capsule().fill(isSelected ? CheckTheme.accent.opacity(0.20) : Color.clear))
                        .overlay(Capsule().stroke(isSelected ? CheckTheme.accent.opacity(0.55) : Color.clear, lineWidth: 1))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                // 단추 글자 두 자("오늘")만으로는 무엇을 고르는지 안 들린다 — 보이스오버에는 판 이름을 준다.
                .accessibilityLabel(scope.boardTitle)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Capsule().fill(Color.white.opacity(0.04)))
        .overlay(Capsule().stroke(CheckTheme.border, lineWidth: 1))
        .fixedSize()
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
