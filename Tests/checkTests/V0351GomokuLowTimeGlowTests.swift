import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// 0.3.51 — 오목 **내 차례 마지막 3초**의 판 테두리 빛(맥). 판정·그림은 코어 `GomokuTurnWarning`(폰과 한 벌), 시계는 잎 뷰
// `GomokuBoardTimeWarning` 이 읽는다. 하네스는 V0327 그대로다(ImageRenderer scale 2 · 좌표는 레이아웃 상수에서만 ·
// CHECK_SNAPSHOT_DIR/gomoku 에 PNG). 그 파일의 헬퍼는 private 이라 여기 한 벌 더 있다(V0330·V0341 과 같은 관례).
//
// 각 시험의 첫 줄은 "없으면 어떤 결함이 초록으로 통과하는가"다. 기준선은 언제나 **다른 입력**이다(+18초 · 상대 차례 +18초) —
// 같은 입력끼리 견주면 그 시험은 영원히 초록이다.

// MARK: - 판정(순수)

/// 없으면: 문턱을 링의 5초로 잘못 옮기거나, nil(AI 차례·멈춘 시계)을 0 으로 읽어 판이 빨갛게 켜지거나, 0초에 꺼지거나,
/// 세기가 0초 쪽으로 오르지 않고 거꾸로 가도 화면 시험 몇 장은 우연히 초록일 수 있다.
@MainActor
@Test
func turnWarningThresholdAndIntensityArePureAndNilIsOff() throws {
    #expect(GomokuTurnWarning.lowTimeSeconds == 3)
    // nil 은 언제나 꺼짐 — 링의 `?? 0` 을 베끼면 마감이 없는 순간에 0초로 켜진다.
    #expect(!GomokuTurnWarning.isActive(remaining: nil))
    #expect(GomokuTurnWarning.intensity(remaining: nil) == 0)
    // 경계: 3.01 은 꺼짐, 3.0 은 켜짐(링 글자 올림 "3초" 가 처음 보이는 순간과 같다), 0 도 켜짐(다음 상태가 올 때까지).
    #expect(!GomokuTurnWarning.isActive(remaining: 3.01))
    #expect(GomokuTurnWarning.isActive(remaining: 3.0))
    #expect(GomokuTurnWarning.isActive(remaining: 1.5))
    #expect(GomokuTurnWarning.isActive(remaining: 0))
    #expect(!GomokuTurnWarning.isActive(remaining: 18))
    #expect(!GomokuTurnWarning.isActive(remaining: .nan) && !GomokuTurnWarning.isActive(remaining: .infinity))
    #expect(!GomokuTurnWarning.isActive(remaining: -.infinity), "무한대는 마감이 아니다")
    // 세기: 꺼짐 0 · 3초 0.55 · 0초 1.0, 그 사이는 곧게(1.5초 = 0.775). 0초 아래로 가도 1.0 을 넘지 않는다.
    #expect(GomokuTurnWarning.intensity(remaining: 3.01) == 0)
    #expect(abs(GomokuTurnWarning.intensity(remaining: 3.0) - 0.55) < 1e-9)
    #expect(abs(GomokuTurnWarning.intensity(remaining: 1.5) - 0.775) < 1e-9)
    #expect(abs(GomokuTurnWarning.intensity(remaining: 0) - 1.0) < 1e-9)
    #expect(GomokuTurnWarning.intensity(remaining: -2) == 1.0)
    var previous = 0.0
    for tenth in stride(from: 30, through: 0, by: -1) {
        let value = GomokuTurnWarning.intensity(remaining: Double(tenth) / 10)
        #expect(value >= previous && value > 0 && value <= 1, "\(Double(tenth) / 10)초의 세기 \(value) 가 0초 쪽으로 오르지 않는다")
        previous = value
    }
    // 빛의 색은 판 위 빨간 표시 두 색(금수 X · 마지막 수 점)과 다르다 — 렌더 감지기(`gpIsForbiddenRed` 등)가 서로를 헷갈리지 않게.
    for (name, color) in [("금수 X", GomokuBoardView.forbiddenColor), ("마지막 수", GomokuBoardView.lastMoveColor)] {
        let mark = try #require(NSColor(color).usingColorSpace(.sRGB))
        let distance = abs(Double(mark.redComponent) - GomokuTurnWarning.tintRed)
            + abs(Double(mark.greenComponent) - GomokuTurnWarning.tintGreen)
            + abs(Double(mark.blueComponent) - GomokuTurnWarning.tintBlue)
        #expect(distance > 0.2, "빛 색이 \(name) 색과 너무 가깝다(채널 차 합 \(distance))")
    }
}

/// 없으면: 상대 차례에도(상대 카드 링이 이미 빨갛다 — 내가 할 일이 없다), AI 가 생각하는 동안에도, 창을 가려 멈춘 AI 시계에서도,
/// 끝난 판에서도 판이 빨갛게 켜지거나 — 반대로 AI 판의 **내** 차례에는 안 켜져도 컴파일과 스토어 시험은 초록이다.
@Test
func turnWarningWatchesOnlyMyRunningClock() {
    let now = Date(timeIntervalSince1970: 2_000_000_000)
    func state(my: GomokuColor = .black, turn: GomokuColor?, deadline: Date?, finished: Bool = false) -> GomokuMatchState {
        GomokuMatchState(
            id: "m", stake: 5, myColor: my, opponent: lgRival, board: GomokuBoard(), lastMove: nil, moveCount: 0, turn: turn,
            deadline: deadline, isFinished: finished, outcome: nil, endReason: nil, rubyDelta: nil, blackPassed: false
        )
    }
    let soon = now.addingTimeInterval(2)
    #expect(GomokuTurnWarning.watchesMyClock(state(turn: .black, deadline: soon)), "내 차례(흑)인데 안 본다")
    #expect(GomokuTurnWarning.watchesMyClock(state(my: .white, turn: .white, deadline: soon)), "내 차례(백)인데 안 본다")
    #expect(!GomokuTurnWarning.watchesMyClock(state(turn: .white, deadline: soon)), "상대 차례를 본다")
    #expect(!GomokuTurnWarning.watchesMyClock(state(turn: .black, deadline: nil)), "마감이 없는데 본다")
    #expect(!GomokuTurnWarning.watchesMyClock(state(turn: nil, deadline: soon)), "차례가 없는데 본다")
    #expect(!GomokuTurnWarning.watchesMyClock(state(turn: .black, deadline: soon, finished: true)), "끝난 판을 본다")
    #expect(!GomokuTurnWarning.watchesMyClock(nil), "판이 없는데 본다")

    // AI 판은 **진짜 AI 판 상태**로 본다(손으로 만든 nil 이 아니라 GomokuAIGame 이 내는 모양).
    let human = GomokuAIGame(humanColor: .black, board: lgBoard(), turn: .black, turnSeconds: 2, now: now)
    #expect(GomokuTurnWarning.watchesMyClock(human.matchState()), "AI 판의 내 차례인데 안 본다")
    var paused = human
    paused.pause(now: now)
    #expect(paused.pausedRemaining != nil && !GomokuTurnWarning.watchesMyClock(paused.matchState()),
            "창이 가려져 멈춘 AI 시계를 본다 — 남은 2초가 얼어 있는 동안 판이 빨갛다")
    let thinking = GomokuAIGame(humanColor: .black, board: lgBoard(), turn: .white, turnSeconds: 2, now: now)
    #expect(!GomokuTurnWarning.watchesMyClock(thinking.matchState()), "AI 가 생각하는 차례를 본다")
}

/// 없으면: 잎 뷰가 쓰는 남은 초(스토어 `remainingSeconds`)와 이 판정이 어긋나 링이 "4초"인데 판이 켜지거나 "3초"인데 안 켜져도,
/// 0초(마감이 지난 뒤 서버가 대신 두기 전)에 꺼져도 순수 시험은 초록이다.
@MainActor
@Test
func storeRemainingFeedsTheWarningAtTheSameMomentTheRingSaysThreeSeconds() {
    let t0 = Date(timeIntervalSince1970: 2_000_000_000)
    let store = GomokuStore()
    store.phase = .playing
    store.match = GomokuMatchState(
        id: "m", stake: 5, myColor: .black, opponent: lgRival, board: lgBoard(), lastMove: nil, moveCount: 6, turn: .black,
        deadline: t0.addingTimeInterval(10), isFinished: false, outcome: nil, endReason: nil, rubyDelta: nil, blackPassed: false
    )
    func at(_ offset: TimeInterval) -> (on: Bool, ring: String) {
        let remaining = store.remainingSeconds(now: t0.addingTimeInterval(offset))
        return (GomokuTurnWarning.isActive(remaining: remaining), GomokuText.remaining(remaining ?? 0))
    }
    #expect(at(6.99).on == false && at(6.99).ring == "4초", "링이 4초인데 판이 켜졌다")
    #expect(at(7.0).on == true && at(7.0).ring == "3초", "링이 3초가 된 순간 판이 안 켜졌다")
    #expect(at(9.5).on == true && at(9.5).ring == "1초")
    #expect(at(12).on == true && at(12).ring == "0초", "마감이 지나 0초인데 판이 꺼졌다 — 다음 상태가 올 때까지 켜져 있어야 한다")
    #expect(GomokuTurnWarning.intensity(remaining: store.remainingSeconds(now: t0.addingTimeInterval(12))) == 1.0)
}

// MARK: - 화면(렌더)

/// 없으면: 빛이 판 가장자리 대신 판 전체를 덮거나(돌·금수 X 가 붉게 물든다), 판 밖으로 번져 머리글 틈·열 사이·창 아래 여백을 칠하거나,
/// 판의 둥근 모서리 밖(창 바탕)을 칠하거나, 링이 빨개지는 5초부터 켜지거나, 세기가 0초 쪽으로 안 올라도 다른 화면 시험은 초록이다.
@MainActor
@Test
func myTurnLowTimeGlowsOnlyInsideTheBoardEdge() throws {
    try lgWarmUp()
    let calm = try lgBitmap(lgPanel(lgStore(turn: .black, deadlineIn: 18)))
    let ringRed = try lgBitmap(lgPanel(lgStore(turn: .black, deadlineIn: 4.5)))
    let low = try lgBitmap(lgPanel(lgStore(turn: .black, deadlineIn: 2)))
    let zero = try lgBitmap(lgPanel(lgStore(turn: .black, deadlineIn: -5)))
    lgSave(calm, "glow-off-18s")
    lgSave(low, "glow-on-2s")
    lgSave(zero, "glow-on-0s")

    // ① 기준선(18초)과 4.5초(링은 이미 빨갛다)에는 테두리에 빛이 한 픽셀도 없다 — 감지기가 나무·좌표 글자를 빛으로 안 센다.
    for (name, bitmap) in [("18초", calm), ("4.5초", ringRed)] {
        for (edge, band) in lgEdgeBands {
            #expect(lgGlow(bitmap, band).hits == 0, "\(name)인데 판 \(edge) 가장자리가 빛난다 — 3초 문턱이 아니다")
        }
    }
    // ② 2초 · 0초: 네 가장자리 띠가 거의 다(90% 이상) 빛난다.
    for (name, bitmap) in [("2초", low), ("0초", zero)] {
        for (edge, band) in lgEdgeBands {
            let glow = lgGlow(bitmap, band)
            #expect(glow.total > 0 && Double(glow.hits) >= Double(glow.total) * 0.9,
                    "\(name)인데 판 \(edge) 가장자리가 안 빛난다(\(glow.hits)/\(glow.total))")
        }
    }
    // ③ 빛은 **안쪽 가장자리**뿐이다: 판 안쪽(가장자리 20pt 를 뺀 자리 — 돌·금수 X·마지막 수)은 기준선과 같다.
    #expect(lgMaxDiff(low, calm, lgBoardInterior) <= 2, "빛이 판 안쪽까지 들어와 돌·표시를 물들인다")
    #expect(lgMaxDiff(zero, calm, lgBoardInterior) <= 2, "0초 빛이 판 안쪽까지 들어온다")
    // ④ 판 밖으로 안 번진다: 머리글 아래 틈 · 판과 오른쪽 열 사이 · 창 아래 여백 · 판 둥근 모서리 밖(창 바탕).
    for (name, rect) in [("머리글 아래 틈", lgHeaderGap), ("열 사이 틈", lgColumnGap), ("창 아래 여백", lgBottomBand),
                         ("왼쪽 위 모서리 밖", lgCornerOutside)] {
        #expect(lgMaxDiff(zero, calm, rect) <= 2, "빛이 판 밖(\(name))으로 번진다")
    }
    // ⑤ 세기는 0초 쪽으로 오른다(같은 띠의 평균 붉기). 2초 렌더는 렌더가 늦어도 3초 안쪽이다(남은 초는 줄기만 한다).
    let early = try lgBitmap(lgPanel(lgStore(turn: .black, deadlineIn: 2.9)))
    let topBand = lgEdgeBands[0].1
    #expect(lgRedness(zero, topBand) > lgRedness(early, topBand) + 20,
            "0초 빛(\(lgRedness(zero, topBand)))이 3초 무렵(\(lgRedness(early, topBand)))보다 세지 않다")
    #expect(lgRedness(early, topBand) > lgRedness(calm, topBand) + 40, "3초 무렵 빛이 너무 옅어 안 보인다")
}

/// 없으면: 상대 차례·AI 가 생각하는 차례·창이 가려져 멈춘 AI 시계·끝난 판·결과 화면·관전 판에서 2초 남은 마감을 보고 판이 빨갛게
/// 켜져도 — 그리고 반대로 AI 판의 **내** 차례에 안 켜져도 내 차례 렌더 시험은 초록이다.
@MainActor
@Test
func noGlowOnTheOpponentsTurnAIThinkingPausedClockFinishedOrSpectating() throws {
    try lgWarmUp()
    let opponentCalm = try lgBitmap(lgPanel(lgStore(turn: .white, deadlineIn: 18)))
    let opponentLow = try lgBitmap(lgPanel(lgStore(turn: .white, deadlineIn: 2)))
    lgSave(opponentLow, "glow-opponent-2s")
    // 상대 차례 2초: 상대 카드 링은 빨갛지만 판은 상대 차례 18초와 같은 그림이다(빛 없음 · 다른 변화도 없음).
    #expect(lgMaxDiff(opponentLow, opponentCalm, lgBoardRect) <= 2, "상대 차례 2초에 판이 바뀌었다")

    let finishedPlaying = try lgBitmap(lgPanel(lgStore(turn: .black, deadlineIn: 2, finished: true)))
    let result = try lgBitmap(lgPanel(lgStore(turn: .black, deadlineIn: 2, finished: true, phase: .result)))

    func aiStore(turn: GomokuColor, pause: Bool) -> GomokuStore {
        let store = GomokuStore()
        store.rubyBalance = 32
        var game = GomokuAIGame(humanColor: .black, board: lgBoard(), turn: turn, turnSeconds: 2, now: Date())
        if pause { game.pause(now: Date()) }
        store.aiGame = game
        store.match = game.matchState()
        store.phase = .playing
        return store
    }
    let aiMine = try lgBitmap(lgPanel(aiStore(turn: .black, pause: false)))
    let aiPaused = try lgBitmap(lgPanel(aiStore(turn: .black, pause: true)))
    let aiThinking = try lgBitmap(lgPanel(aiStore(turn: .white, pause: false)))
    lgSave(aiMine, "glow-ai-my-turn-2s")

    let spectating = try lgBitmap(lgPanel(lgSpectateStore(deadlineIn: 2)))
    lgSave(spectating, "glow-spectate-2s")

    for (name, bitmap) in [("상대 차례 2초", opponentLow), ("끝난 판(대국 화면)", finishedPlaying), ("결과 화면", result),
                           ("AI 판 멈춘 시계", aiPaused), ("AI 가 생각하는 차례", aiThinking), ("관전 2초", spectating)] {
        for (edge, band) in lgEdgeBands {
            #expect(lgGlow(bitmap, band).hits == 0, "\(name)인데 판 \(edge) 가장자리가 빛난다")
        }
    }
    // AI 판의 **내** 차례 2초는 빛난다(1:1 과 같은 잎 · 같은 판정) — 위 '없음' 들이 감지기가 눈먼 탓이 아니라는 기준선이기도 하다.
    for (edge, band) in lgEdgeBands {
        let glow = lgGlow(aiMine, band)
        #expect(glow.total > 0 && Double(glow.hits) >= Double(glow.total) * 0.9,
                "AI 판 내 차례 2초인데 판 \(edge) 가장자리가 안 빛난다(\(glow.hits)/\(glow.total))")
    }
}

/// 없으면: 세기 0(꺼짐)에서도 옅은 선이 남거나, 그림이 판의 둥근 사각형 밖(모서리 바깥)을 칠하거나, 빛이 가장자리 돌이 서는
/// 깊이(한 변의 3.1%)까지 들어와도 패널 시험의 몇 띠는 우연히 초록일 수 있다 — 그림 하나만 따로 잰다(폰도 이 그림을 쓴다).
@MainActor
@Test
func edgeGlowDrawingStaysInsideTheRoundedBoardAndZeroDrawsNothing() throws {
    let side: CGFloat = 300
    func render(_ intensity: Double?) throws -> NSBitmapImageRep {
        try lgBitmap(
            Canvas { context, size in
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
                if let intensity {
                    GomokuTurnWarning.drawEdgeGlow(into: &context, side: min(size.width, size.height), intensity: intensity)
                }
            }
            .frame(width: side, height: side)
        )
    }
    let blank = try render(nil)
    for (name, value) in [("0", 0.0), ("음수", -1.0), ("NaN", Double.nan)] {
        #expect(lgMaxDiff(try render(value), blank, CGRect(x: 0, y: 0, width: side, height: side)) == 0,
                "세기 \(name) 인데 무언가 그려졌다")
    }
    let full = try render(1)
    // 둥근 모서리 밖(꼭짓점 2pt 사각형)은 비어 있다 — 판 모양으로 먼저 자른다.
    for corner in [CGRect(x: 0, y: 0, width: 1.5, height: 1.5), CGRect(x: side - 1.5, y: side - 1.5, width: 1.5, height: 1.5)] {
        #expect(lgMaxDiff(full, blank, corner) <= 2, "빛이 판 둥근 모서리 밖을 칠한다(\(corner))")
    }
    // 가장자리 돌이 서는 깊이(3.1%)부터 안쪽은 비어 있다. 바깥 1pt 는 진하게 붉다.
    let stoneDepth = side * 0.031
    let inner = CGRect(x: stoneDepth, y: stoneDepth, width: side - stoneDepth * 2, height: side - stoneDepth * 2)
    #expect(lgMaxDiff(full, blank, inner) == 0, "빛이 가장자리 돌이 서는 깊이까지 들어온다")
    let edge = CGRect(x: side / 2 - 20, y: 0.25, width: 40, height: 1)
    #expect(lgRedness(full, edge) > 120, "세기 1 의 가장 바깥 겹이 충분히 붉지 않다(\(lgRedness(full, edge)))")
}

// MARK: - 실제 창 프로브(누름이 빛을 지나 판에 닿는다)

// ImageRenderer 는 입력을 모른다 — 빛 잎(판 전체 크기의 Canvas)이 누름을 삼켜도 렌더 시험은 초록이다. 그래서 진짜 `NSWindow` +
// `NSHostingView` 에 앱이 띄우는 그 화면(`GomokuPanel`)을 얹고 합성 클릭을 **이 창에만** `sendEvent` 로 넣는다(전역 CGEvent 없음 ·
// 커서·포커스를 안 뺏는다). 창은 **키가 될 수 없는** 창이다 — 키가 될 수 있는데 키가 아닌 창에서는 SwiftUI 가 제스처를 전부 무시한다
// (V0348ChessDragWindowTests 머리말의 실측 — 테스트 프로세스는 활성 앱이 아니다). 테스트 실행의 창 알파는 0 이라 사용자 클릭은 통과한다.
// 판은 AI 판이다 — 누름이 닿으면 서버 없이 로컬 판에 돌이 놓여 결과를 값으로 잴 수 있다. 호버 툴팁은 합성 이벤트로 못 깨운다
// (같은 실측) — 그 자리는 아래 소스 계약(빛 잎이 툴팁 자리보다 아래 겹)이 지킨다.

extension GomokuWindowLifecycleTests {
    /// 없으면: 빛 잎이 누름을 삼켜 마지막 3초에 판을 눌러도 돌이 안 놓여도 — 가장 급한 순간에 판이 죽어도 — 렌더 시험은 초록이다.
    /// 판 전체 크기 Canvas 는 제 틀 전체가 누름 자리다. 지금 자리(탭 제스처를 단 판 뷰 **안쪽** 겹)에서는 누름이 잎에 떨어져도 바깥
    /// 제스처가 받지만, 잎을 제스처 **바깥 위**로 옮기고 `.allowsHitTesting(false)` 를 빼면 D4 누름이 통째로 사라진다(2026-10-14 실측 —
    /// 이 시험이 빨개진다). `.allowsHitTesting(false)` 만 빼는 변형은 지금 자리에서는 효과가 없어 이 시험이 아니라 소스 계약이 잡는다.
    @Test
    func aClickOnTheBoardStillPlacesTheStoneWhileTheEdgeGlows() async throws {
        let store = GomokuStore()
        store.rubyBalance = 32
        // 사람 시계 3초 — 열자마자 빛 구간이다. 시계 작업은 세우지 않는다(직접 앉힌 판 · 창이 보여도 멈춘 시계가 없어 이어 갈 것이 없다).
        let game = GomokuAIGame(humanColor: .black, board: lgBoard(), turn: .black, turnSeconds: 3, now: Date())
        store.aiGame = game
        store.match = game.matchState()
        store.phase = .playing
        let window = try await lgOpenProbe(store)
        defer { lgCloseProbe(window, store) }

        // 누르는 그 순간 창에 빛이 그려져 있다(이게 아니면 아래 단언은 빛과 상관없는 누름을 잰다).
        let lit = try lgCapture(window)
        for (edge, band) in lgEdgeBands {
            let glow = lgGlow(lit.rep, band, scale: lit.scale)
            #expect(glow.total > 0 && Double(glow.hits) >= Double(glow.total) * 0.9,
                    "프로브 창의 판 \(edge) 가장자리가 안 빛난다(\(glow.hits)/\(glow.total)) — 빛이 꺼진 채 누름을 잰다")
        }

        let target = try #require(GomokuPoint(notation: "D4"))
        #expect(store.match?.board[target] == nil, "전제: D4 가 비어 있다")
        let spot = GomokuBoardGeometry(side: GomokuWindowLayout.boardSide).location(of: target)
        try await lgClick(window, at: CGPoint(x: lgBoardRect.minX + spot.x, y: lgBoardRect.minY + spot.y))
        await lgSettle(turns: 40) { store.match?.board[target] == .black }
        #expect(store.match?.board[target] == .black, "빛이 켜진 판의 D4 를 눌렀는데 돌이 안 놓였다 — 빛 잎이 누름을 삼킨다")
    }
}

// MARK: - 소스 계약(주석을 걷어낸 뒤)

/// 없으면: 빛 잎이 툴팁 자리들 **위**에 얹혀 금수 X·자동 착수 툴팁 호버를 가리거나, 입력을 받아 탭·호버를 삼키거나, 보이스오버에 빈 요소로
/// 잡히거나, 시계를 TimelineView 밖(또는 `Date()`)에서 읽거나, 멈춘 TimelineView 의 마지막 그림(빛)을 차례가 넘어간 뒤에도 들고 있거나,
/// blur·shadow·반복 애니메이션으로 합성기를 태우거나, 관전·결과 판에도 붙어도 픽셀 시험은 초록일 수 있다(ImageRenderer 는 호버를 모른다).
@Test
func glowLeafReadsTheClockInItsTimelineAndStaysOutOfInputAndVoiceOver() throws {
    let panel = lgStripped(try lgSource("Sources/check/GomokuPanel.swift"))
    let board = try #require(lgRegion(panel, from: "private struct GomokuPlayBoard: View {", to: "private struct GomokuBoardTimeWarning: View {"),
                             "대국 판 뷰 다음에 빛 잎이 없다")
    let overlay = try #require(board.range(of: ".overlay { GomokuBoardTimeWarning(store: store) }"), "대국 판에 빛 잎이 안 얹혔다")
    for later in [".checkTooltip(", ".onContinuousHover", "SpatialTapGesture", ".accessibilityElement(children: .ignore)"] {
        let hit = try #require(board.range(of: later), "대국 판에 '\(later)' 가 없다")
        #expect(overlay.lowerBound < hit.lowerBound, "빛 잎이 '\(later)' 보다 뒤(위 겹)에 얹혔다 — 툴팁·입력·보이스오버를 가린다")
    }

    let leaf = try #require(lgRegion(panel, from: "private struct GomokuBoardTimeWarning: View {", to: "enum GomokuResignGuard {"))
    for required in [".allowsHitTesting(false)", ".accessibilityHidden(true)", "GomokuTurnWarning.isActive(remaining: remaining)",
                     "GomokuTurnWarning.intensity(remaining: remaining)", "GomokuTurnWarning.drawEdgeGlow(",
                     "TimelineView(.animation(minimumInterval: 0.2, paused: !store.isWindowVisible || !watches))"] {
        #expect(leaf.contains(required), "빛 잎에 '\(required)' 가 없다")
    }
    // 켜짐 판정은 두 번 — TimelineView 를 멈추는 데 한 번, **그 안 본문에서** 한 번 더(멈춘 TimelineView 는 마지막 그림을 들고 있다).
    #expect(leaf.components(separatedBy: "GomokuTurnWarning.watchesMyClock(store.match)").count - 1 == 2, "본문에서 차례를 다시 안 본다")
    let timeline = try #require(leaf.range(of: "TimelineView("))
    let recheck = try #require(leaf.range(of: "GomokuTurnWarning.watchesMyClock(store.match)", options: .backwards))
    #expect(timeline.lowerBound < recheck.lowerBound, "차례 재판정이 TimelineView 본문 안에 없다")
    for forbidden in ["?? 0", "Date()", ".shadow(", ".blur(", "repeatForever", "withAnimation", ".animation(.", "drawLayer", "addFilter"] {
        #expect(!leaf.contains(forbidden), "빛 잎에 '\(forbidden)' 가 있다")
    }
    // 빛 잎은 대국 판 **한 곳**에만 선다(결과·관전 판은 GomokuBoardView 그대로). 코어 판정을 읽는 자리도 이 잎뿐이다.
    #expect(panel.components(separatedBy: "GomokuBoardTimeWarning(").count - 1 == 1, "빛 잎이 대국 판 말고 다른 판에도 섰다")
    #expect(panel.components(separatedBy: "GomokuTurnWarning.").count == leaf.components(separatedBy: "GomokuTurnWarning.").count,
            "빛 판정을 잎 밖에서도 읽는다")

    // 코어: 판정·그림 파일은 시계를 읽지 않고(잎이 넘긴다) 한 벌이다(AppKit·UIKit·플랫폼 분기 없음). 스토어는 빛 상태를 들지 않는다(규칙 ⑥).
    let core = lgStripped(try lgSource("Sources/CheckCore/GomokuTurnWarning.swift"))
    for forbidden in ["Date()", "TimelineView", "import AppKit", "import UIKit", "#if os(", "repeatForever", ".blur(", ".shadow(", "remainingSeconds("] {
        #expect(!core.contains(forbidden), "공용 판정·그림 파일에 '\(forbidden)' 가 있다")
    }
    #expect(core.contains("clip(to:"), "그림이 판 모양으로 먼저 자르지 않는다")
    let storeDirectory = CheckCoreSourceLayout.coreDirectory
    for name in try FileManager.default.contentsOfDirectory(atPath: storeDirectory.path) where name.hasPrefix("GomokuStore") {
        let code = lgStripped(try String(contentsOf: storeDirectory.appendingPathComponent(name), encoding: .utf8))
        #expect(!code.contains("GomokuTurnWarning"), "\(name) 가 빛 상태를 쥔다 — 스토어는 매초 아무것도 대입하지 않는다(규칙 ⑥)")
    }
}

// MARK: - 픽스처

private let lgRival = GomokuUser(
    id: "00000000-0000-0000-0000-000000000011", displayName: "민수", avatarURL: nil, characterID: "fox",
    isWorking: true, isCapable: true, inMatch: true
)
private let lgMe = GomokuPlayerFace(name: "영식", avatarURL: nil, characterID: "shiba")

/// 돌은 판 가운데에만 둔다 — 가장자리 띠에 돌·마지막 수(빨간 점)가 있으면 감지기가 그것을 센다.
private func lgBoard() -> GomokuBoard {
    var board = GomokuBoard()
    for notation in ["H8", "I9", "G7"] { if let p = GomokuPoint(notation: notation) { board[p] = .black } }
    for notation in ["H9", "H10", "I8"] { if let p = GomokuPoint(notation: notation) { board[p] = .white } }
    return board
}

@MainActor
private func lgStore(turn: GomokuColor?, deadlineIn seconds: TimeInterval?, finished: Bool = false,
                     phase: GomokuPhase = .playing) -> GomokuStore {
    let store = GomokuStore()
    store.phase = phase
    store.rubyBalance = 32
    store.record = GomokuRecord(wins: 7, losses: 3, draws: 1)
    store.match = GomokuMatchState(
        id: "match-glow", stake: 5, myColor: .black, opponent: lgRival, board: lgBoard(),
        lastMove: GomokuPoint(notation: "I8"), moveCount: 6, turn: turn,
        deadline: seconds.map { Date().addingTimeInterval($0) }, isFinished: finished,
        outcome: finished ? .won : nil, endReason: finished ? .five : nil, rubyDelta: finished ? 5 : nil, blackPassed: false
    )
    return store
}

/// 남의 판 관전(서버가 흑·백을 말한 뒤) — 마감 2초.
@MainActor
private func lgSpectateStore(deadlineIn seconds: TimeInterval) -> GomokuStore {
    let store = GomokuStore()
    store.record = GomokuRecord(wins: 7, losses: 3, draws: 1)
    store.rubyBalance = 32
    store.hasLoadedLobby = true
    let a = GomokuUser(id: "00000000-0000-0000-0000-000000000030", displayName: "대결자", avatarURL: nil, characterID: "fox",
                       isWorking: true, isCapable: true, inMatch: true)
    let b = GomokuUser(id: "00000000-0000-0000-0000-000000000060", displayName: "상대", avatarURL: nil, characterID: "ghost",
                       isWorking: true, isCapable: true, inMatch: true)
    var watch = GomokuSpectateState(id: "watch-glow", faces: [a, b], stake: 5)
    watch.board = lgBoard()
    watch.lastMove = GomokuPoint(notation: "I8")
    watch.moveCount = 6
    watch.appliedSeq = 6
    watch.black = a
    watch.white = b
    watch.turn = .black
    watch.deadline = Date().addingTimeInterval(seconds)
    watch.startedAt = Date(timeIntervalSince1970: 2_000_000_000)
    store.spectating = watch
    return store
}

@MainActor
private func lgPanel(_ store: GomokuStore) -> some View {
    GomokuPanel(store: store, me: { lgMe }, clipsOverflowInsteadOfScroll: true)
}

// MARK: - 사각형(레이아웃 상수에서만, pt)

@MainActor
private var lgBoardRect: CGRect {
    CGRect(x: GomokuWindowLayout.contentPadding,
           y: GomokuWindowLayout.contentPadding + GomokuWindowLayout.headerHeight + GomokuWindowLayout.headerSpacing,
           width: GomokuWindowLayout.boardSide, height: GomokuWindowLayout.boardSide)
}

/// 판 네 가장자리의 바깥 3pt 띠(모서리 24pt 는 뺀다 — 둥근 모서리 밖은 창 바탕이다).
@MainActor
private var lgEdgeBands: [(String, CGRect)] {
    let b = lgBoardRect
    let skip: CGFloat = 24
    return [
        ("위", CGRect(x: b.minX + skip, y: b.minY + 0.5, width: b.width - skip * 2, height: 3)),
        ("아래", CGRect(x: b.minX + skip, y: b.maxY - 3.5, width: b.width - skip * 2, height: 3)),
        ("왼쪽", CGRect(x: b.minX + 0.5, y: b.minY + skip, width: 3, height: b.height - skip * 2)),
        ("오른쪽", CGRect(x: b.maxX - 3.5, y: b.minY + skip, width: 3, height: b.height - skip * 2))
    ]
}

/// 판 안쪽(가장자리 20pt 를 뺀 자리) — 빛 깊이(한 변의 2.4% ≈ 14.6pt)보다 깊다.
@MainActor
private var lgBoardInterior: CGRect { lgBoardRect.insetBy(dx: 20, dy: 20) }

@MainActor
private var lgHeaderGap: CGRect {
    CGRect(x: lgBoardRect.minX, y: lgBoardRect.minY - GomokuWindowLayout.headerSpacing + 0.5,
           width: lgBoardRect.width, height: GomokuWindowLayout.headerSpacing - 1)
}

@MainActor
private var lgColumnGap: CGRect {
    CGRect(x: lgBoardRect.maxX + 0.5, y: lgBoardRect.minY, width: GomokuWindowLayout.columnSpacing - 1, height: lgBoardRect.height)
}

@MainActor
private var lgBottomBand: CGRect {
    let size = GomokuWindowLayout.contentSize
    return CGRect(x: 0, y: size.height - GomokuWindowLayout.contentPadding + 2,
                  width: size.width, height: GomokuWindowLayout.contentPadding - 4)
}

@MainActor
private var lgCornerOutside: CGRect { CGRect(x: lgBoardRect.minX, y: lgBoardRect.minY, width: 1.5, height: 1.5) }

// MARK: - 헬퍼

private enum LGRenderError: Error { case failed }

@MainActor
private func lgBitmap(_ view: some View) throws -> NSBitmapImageRep {
    let renderer = ImageRenderer(content: view.fixedSize())
    renderer.scale = 2
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff)
    else { throw LGRenderError.failed }
    return bitmap
}

/// ImageRenderer 는 첫 두 장을 다르게 굽는다(그림자 Δ≤2) — 견줄 장을 그리기 전에 두 장을 버린다.
@MainActor
private func lgWarmUp() throws {
    for _ in 0..<2 { _ = try lgBitmap(lgPanel(lgStore(turn: .black, deadlineIn: 18))) }
}

private func lgSave(_ bitmap: NSBitmapImageRep, _ name: String) {
    MiniGameSnapshots.save(bitmap, name: "\(name).png", sub: "gomoku")
}

/// 사각형(pt) → 픽셀 범위. 렌더 장은 언제나 2배이고, 창 프로브는 그 화면의 배율(외부 1배 모니터면 1)을 넘긴다.
private func lgPixelRange(_ bitmap: NSBitmapImageRep, _ rect: CGRect, scale: CGFloat = 2) -> (x: ClosedRange<Int>, y: ClosedRange<Int>)? {
    let x0 = max(0, Int(rect.minX * scale)), x1 = min(bitmap.pixelsWide - 1, Int(rect.maxX * scale) - 1)
    let y0 = max(0, Int(rect.minY * scale)), y1 = min(bitmap.pixelsHigh - 1, Int(rect.maxY * scale) - 1)
    guard x0 <= x1, y0 <= y1 else { return nil }
    return (x0...x1, y0...y1)
}

/// 빛 픽셀: 나무(R−G ≈ 40)·좌표 글자(갈색)·돌(무채색)과 갈리는 붉음(R ≥ 150 · R−G ≥ 70).
private func lgGlow(_ bitmap: NSBitmapImageRep, _ rect: CGRect, scale: CGFloat = 2) -> (hits: Int, total: Int) {
    guard let data = bitmap.bitmapData, bitmap.samplesPerPixel >= 3,
          let range = lgPixelRange(bitmap, rect, scale: scale) else { return (0, 0) }
    let bpr = bitmap.bytesPerRow, spp = bitmap.samplesPerPixel
    var hits = 0, total = 0
    for y in range.y {
        for x in range.x {
            let o = y * bpr + x * spp
            let r = Int(data[o]), g = Int(data[o + 1])
            total += 1
            if r >= 150 && r - g >= 70 { hits += 1 }
        }
    }
    return (hits, total)
}

/// 사각형 안 평균 붉기(R − G).
private func lgRedness(_ bitmap: NSBitmapImageRep, _ rect: CGRect) -> Int {
    guard let data = bitmap.bitmapData, bitmap.samplesPerPixel >= 3, let range = lgPixelRange(bitmap, rect) else { return 0 }
    let bpr = bitmap.bytesPerRow, spp = bitmap.samplesPerPixel
    var sum = 0, count = 0
    for y in range.y {
        for x in range.x {
            let o = y * bpr + x * spp
            sum += Int(data[o]) - Int(data[o + 1])
            count += 1
        }
    }
    return count == 0 ? 0 : sum / count
}

private func lgMaxDiff(_ lhs: NSBitmapImageRep, _ rhs: NSBitmapImageRep, _ rect: CGRect) -> Int {
    guard let a = lhs.bitmapData, let b = rhs.bitmapData, lhs.pixelsWide == rhs.pixelsWide, lhs.pixelsHigh == rhs.pixelsHigh,
          let range = lgPixelRange(lhs, rect) else { return 255 }
    let spp = lhs.samplesPerPixel, bpr = lhs.bytesPerRow
    var worst = 0
    for y in range.y {
        for x in range.x {
            let o = y * bpr + x * spp
            for channel in 0..<min(3, spp) {
                worst = max(worst, abs(Int(a[o + channel]) - Int(b[o + channel])))
            }
        }
    }
    return worst
}

// 창 프로브 도우미(V0348ChessDragWindowTests 의 dw* 와 같은 길 — 그쪽은 private 이라 한 벌 더 있다).

@MainActor
private func lgSettle(turns: Int = 6, until condition: @MainActor () -> Bool = { false }) async {
    for _ in 0..<turns {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(10))
    }
}

/// 키가 될 수 없는 창 — 그 한 줄 말고는 오목 창과 같다.
private final class LGProbeWindow: NSWindow {
    override var canBecomeKey: Bool { false }
}

/// 오목 창과 **같은 스타일**의 프로브 창에 앱이 띄우는 그 화면을 얹는다(컨트롤러 `configure(store:)` 의 내용 뷰 그대로 · 다크 · 테스트 알파 0).
@MainActor
private func lgOpenProbe(_ store: GomokuStore) async throws -> NSWindow {
    let production = CheckGomokuWindowController.makeWindow()
    defer { production.close() }
    let window = LGProbeWindow(
        contentRect: NSRect(origin: NSPoint(x: 140, y: 140), size: CheckGomokuWindowController.fixedContentSize),
        styleMask: production.styleMask, backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.appearance = production.appearance
    window.alphaValue = CheckPanelVisibility.panelAlpha
    let hosting = NSHostingView(rootView:
        GomokuPanel(store: store, me: { lgMe })
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(CheckTheme.background))
    hosting.autoresizingMask = [.width, .height]
    window.contentView = hosting
    window.orderFrontRegardless()
    store.windowDidShow()
    await lgSettle(turns: 20)
    return window
}

/// 프로브 창을 내리고 스토어를 비운다(AI 수 작업·폴링을 끊는다).
@MainActor
private func lgCloseProbe(_ window: NSWindow, _ store: GomokuStore) {
    store.windowDidHide()
    store.windowDidClose()
    store.reset()
    window.orderOut(nil)
    window.contentView = nil
    window.close()
}

/// 합성 클릭 한 번을 **이 창에만** 넣는다(창 콘텐츠 좌표 · 왼쪽 위 원점).
@MainActor
private func lgClick(_ window: NSWindow, at point: CGPoint) async throws {
    let height = window.contentView?.bounds.height ?? GomokuWindowLayout.contentSize.height
    for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
        let event = try #require(NSEvent.mouseEvent(
            with: type, location: NSPoint(x: point.x, y: height - point.y), modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
            eventNumber: 1, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1),
                                 "합성 마우스 이벤트를 만들지 못했다")
        window.sendEvent(event)
        await lgSettle(turns: 2)
    }
}

/// 창에 얹힌 그 뷰 자체를 그린 비트맵과 그 배율(px/pt). 창 알파 0 은 합성 단계에서만 지우므로 그림은 그대로 나온다.
@MainActor
private func lgCapture(_ window: NSWindow) throws -> (rep: NSBitmapImageRep, scale: CGFloat) {
    let view = try #require(window.contentView)
    let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: rep)
    return (rep, CGFloat(rep.pixelsWide) / max(1, view.bounds.width))
}

private func lgSource(_ relative: String) throws -> String {
    try String(contentsOf: CheckCoreSourceLayout.repoRoot.appendingPathComponent(relative), encoding: .utf8)
}

/// `from` 부터 그 뒤 첫 `to` 직전까지(없으면 nil).
private func lgRegion(_ source: String, from start: String, to end: String) -> String? {
    guard let head = source.range(of: start) else { return nil }
    let tail = source.range(of: end, range: head.upperBound..<source.endIndex)?.lowerBound ?? source.endIndex
    return String(source[head.upperBound..<tail])
}

/// 주석을 걷어내고 공백을 한 칸으로 접는다(V0327 `gpStripped` 와 같은 규칙).
private func lgStripped(_ source: String) -> String {
    var out = ""
    var inLine = false, inBlock = false, inString = false, escaped = false
    var index = source.startIndex
    while index < source.endIndex {
        let c = source[index]
        let nextIndex = source.index(after: index)
        let next: Character? = nextIndex < source.endIndex ? source[nextIndex] : nil
        if inLine {
            if c == "\n" { inLine = false; out.append(c) }
        } else if inBlock {
            if c == "*", next == "/" { inBlock = false; index = nextIndex }
        } else if inString {
            out.append(c)
            if escaped { escaped = false }
            else if c == "\\" { escaped = true }
            else if c == "\"" { inString = false }
        } else if c == "/", next == "/" {
            inLine = true; index = nextIndex
        } else if c == "/", next == "*" {
            inBlock = true; index = nextIndex
        } else if c == "\"" {
            inString = true; out.append(c)
        } else {
            out.append(c)
        }
        index = source.index(after: index)
    }
    return out.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
}
