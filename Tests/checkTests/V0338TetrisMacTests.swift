import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// MARK: - v0.3.38 테트리스 **맥 화면** — 배치 · 키 · 대비 · 렌더
//
// 이 파일이 지키는 것 넷.
//  ① 캔버스 배치(논리 292×302 · 셀 13)가 스펙의 검산과 **숫자로** 맞는다 — 세 열의 합 292, 세 바닥이 273.
//  ② 조작 키가 **자리(keyCode)로** 들어오고, 방향키 게이트가 스페이스보다 **엄격**하다.
//  ③ 눌린 채 판이 끝나는 출구가 **여섯 곳 전부** 눌림을 푼다(한 곳만 재면 나머지를 지워도 초록이다).
//  ④ 조각이 배경보다 확실히 밝다 — 이 저장소가 플래피 기둥에서 한 번 당한 자리다(1.01:1 로 캐릭터가 사라졌다).
//
// 그림은 `ImageRenderer` **차분**으로 잰다: "잉크가 있다"가 아니라 "한 칸을 채우면 정확히 그 사각형만 달라진다".
// 절대 픽셀 색으로 재면 배경 무대가 바뀌는 순간 통째로 빨개지고, 반대로 "어딘가 잉크가 있다"는 배치를 안 잰다.

// MARK: - ① 배치 검산

@Test("캔버스 배치: 가로 합 292 · 세로 합 302 · 세 열의 바닥이 같은 줄(273)")
func tetrisCanvasLayoutAddsUp() {
    // 가로: 12 + 61 + 8 + 130 + 8 + 61 + 12
    let across = TetrisLayout.outerMargin + TetrisLayout.columnWidth + TetrisLayout.gutter
        + TetrisLayout.boardWidth + TetrisLayout.gutter + TetrisLayout.columnWidth + TetrisLayout.outerMargin
    #expect(across == TetrisLayout.logicalSize.width, "가로 합이 \(across) 다(기대 292)")
    #expect(TetrisLayout.boardX == 81)
    #expect(TetrisLayout.rightColumnX == 219)
    #expect(TetrisLayout.boardWidth == 130)

    // 세로: 버퍼 13 + 판 260 + 틈 4 + 밴드 21 + 바닥 4
    #expect(TetrisLayout.boardTopY == TetrisLayout.cell, "버퍼행이 정확히 한 셀이 아니다")
    #expect(TetrisLayout.boardBottomY == 273)
    let down = TetrisLayout.boardBottomY + 4 + TetrisLayout.bandHeight + 4
    #expect(down == TetrisLayout.logicalSize.height, "세로 합이 \(down) 다(기대 302)")
    #expect(TetrisLayout.bandY == TetrisLayout.boardBottomY + 4)

    // 세 바닥이 같은 줄이어야 창이 한 물건으로 읽힌다.
    #expect(TetrisLayout.linesValueY + TetrisLayout.valueHeight == TetrisLayout.boardBottomY,
            "왼쪽 열 바닥이 판 바닥과 어긋난다")
    #expect(TetrisLayout.slotY(TetrisGame.nextCount - 1) + TetrisLayout.boxHeight == TetrisLayout.boardBottomY,
            "넥스트 5번 슬롯 바닥이 판 바닥과 어긋난다")
    // 넥스트 1번 슬롯은 홀드 상자와 **정확히 같은 y** 다.
    #expect(TetrisLayout.slotY(0) == TetrisLayout.boxY)
}

@Test("셀 13 이 유일한 답이다 — 12 는 세로가 남고 14 는 버퍼행+밴드를 동시에 못 넣는다")
func cellThirteenIsTheOnlyFit() {
    let height = TetrisLayout.logicalSize.height
    func leftover(_ cell: CGFloat) -> CGFloat { height - cell * CGFloat(TetrisGame.visibleRows) }
    // 14: 남는 세로 22 < 버퍼 한 셀(14) + 밴드(21) = 35 → 못 넣는다.
    #expect(leftover(14) < 14 + TetrisLayout.bandHeight, "셀 14 가 들어간다면 이 검산의 전제가 틀렸다")
    // 13: 남는 42 ≥ 13 + 21 = 34 → 들어간다. 그리고 위 여백이 **정확히 한 셀**이다.
    #expect(leftover(13) >= 13 + TetrisLayout.bandHeight)
    #expect(TetrisLayout.cell == 13)

    // 넥스트 5칸 여유: 5s + 4×7 ≤ 248 → s ≤ 44. 미니셀 = (44 − 패딩 12)/2 = 16 이 상한이고 채택값은 9.
    let available = TetrisLayout.boardBottomY - TetrisLayout.boxY
    #expect(CGFloat(TetrisGame.nextCount) * TetrisLayout.boxHeight
            + CGFloat(TetrisGame.nextCount - 1) * TetrisLayout.slotGap == available)
    #expect(TetrisLayout.miniCell * 2 + 12 <= TetrisLayout.boxHeight, "미니셀이 슬롯을 넘친다")
}

@Test("cellRect: 보이는 첫 행이 판 윗변, 마지막 행이 판 아랫변, 버퍼행이 그 위 한 칸")
func cellRectMapsTheVisibleWindow() {
    let top = TetrisLayout.cellRect(row: TetrisGame.firstVisibleRow, column: 0)
    #expect(top.minY == TetrisLayout.boardTopY)
    #expect(top.minX == TetrisLayout.boardX)
    let bottom = TetrisLayout.cellRect(row: TetrisGame.totalRows - 1, column: TetrisGame.columns - 1)
    #expect(bottom.maxY == TetrisLayout.boardBottomY)
    #expect(bottom.maxX == TetrisLayout.boardX + TetrisLayout.boardWidth)
    let buffer = TetrisLayout.cellRect(row: TetrisGame.firstVisibleRow - 1, column: 0)
    #expect(buffer.minY == TetrisLayout.bufferY, "버퍼행이 캔버스 맨 위에서 시작하지 않는다")
    #expect(buffer.maxY == TetrisLayout.boardTopY)
}

// MARK: - ② 키: 자리로 받고, 방향은 엄격하게

@Test("keyCode 표: ← → ↓ ↑ X Z C 가 자리로 매핑되고 그 밖은 nil 이다")
func strokeKeyCodesAreAnsiPositions() {
    typealias Key = MiniGameSpaceKey.GameKey
    let expected: [UInt16: Key] = [123: .moveLeft, 124: .moveRight, 125: .softDrop,
                                   126: .rotateCW, 7: .rotateCW, 6: .rotateCCW, 8: .hold]
    for (code, key) in expected {
        #expect(MiniGameSpaceKey.Stroke.key(forKeyCode: code) == key, "keyCode \(code) 가 \(key) 가 아니다")
    }
    // 스페이스·ESC 는 조작 키가 아니다 — 저쪽 가지(관대한 게이트)로 가야 한다.
    #expect(MiniGameSpaceKey.Stroke.key(forKeyCode: MiniGameSpaceKey.spaceKeyCode) == nil)
    #expect(MiniGameSpaceKey.Stroke.key(forKeyCode: MiniGameSpaceKey.escapeKeyCode) == nil)
    // 아무 글자 키나 삼키면 다른 창의 타이핑을 훔친다.
    for code: UInt16 in [0, 1, 2, 3, 4, 5, 9, 12, 36, 48, 51] {
        #expect(MiniGameSpaceKey.Stroke.key(forKeyCode: code) == nil, "keyCode \(code) 를 조작 키로 받는다")
    }
    // 레벨/엣지 구분(DAS·ARR 은 레벨 키에만 있다).
    #expect(Key.moveLeft.isLevel && Key.moveRight.isLevel && Key.softDrop.isLevel)
    #expect(!Key.rotateCW.isLevel && !Key.rotateCCW.isLevel && !Key.hold.isLevel)
}

@Test("문자 키는 **자리로만** 받는다 — 한글 입력기에서 Z·X·C 가 'ㅋ'·'ㅌ'·'ㅊ' 로 온다")
func letterKeysNeverGoThroughCharacters() throws {
    let source = tmStripped(try tmPanelSource())
    let install = try tmInstallBody()
    // 이 저장소는 같은 사실 위에 `EnglishInputSource`(영문 전용 필드가 포커스를 얻으면 입력기를 ABC 로
    // 바꾼다)를 두고 있다. 게임 창에서는 입력기를 못 건드리므로 자리로 받는 쪽이 유일한 길이다.
    #expect(!install.contains("charactersIgnoringModifiers"),
            "글자로 키를 읽는다 — 한글 입력 상태에서 Z·X·C 가 통째로 빗나간다")
    #expect(!install.contains(".characters"), "글자로 키를 읽는다")
    #expect(source.contains("static func key(forKeyCode code: UInt16)"), "자리 → 키 표가 없다")
}

@MainActor
@Test("방향 게이트는 스페이스보다 엄격하다 — 게임 창으로 간 키만 받는다")
func directionalKeysRequireTheGameWindow() {
    let game = tmWindow(identifier: CheckMiniGameWindowController.frameAutosaveName)
    let popover = tmWindow()                                  // identifier 없음 = `yieldsToOtherWindow` 가 모르는 창
    let hidden = tmWindow(identifier: CheckMiniGameWindowController.frameAutosaveName, onScreen: false)
    defer { [game, popover, hidden].forEach { $0.orderOut(nil) } }

    #expect(MiniGameSpaceKey.strokeBelongsToGame(game, gameWindow: game))
    // ★ 이것이 이 게이트의 존재 이유다: 스페이스는 이 창에 **양보하지 않는데**(관대한 게이트) 방향키는 받지 않는다.
    //   팝오버·할 일 보드는 identifier 가 없어 `yieldsToOtherWindow` 가 "모르는 창"으로 놓아 준다 —
    //   거기서 누른 ←/→ 를 삼키면 그 창의 커서를 훔친다(2026-09-17 오목 채팅 사고의 화살표판).
    #expect(!MiniGameSpaceKey.yieldsToOtherWindow(popover, gameWindow: game), "전제: 스페이스는 이 창에 양보하지 않는다")
    #expect(!MiniGameSpaceKey.strokeBelongsToGame(popover, gameWindow: game), "모르는 창의 방향키를 삼킨다")
    // 키가 아직 어느 창에도 안 간 순간(창을 막 연 그 짧은 틈)도 방향키는 안 받는다.
    #expect(!MiniGameSpaceKey.strokeBelongsToGame(nil, gameWindow: game))
    #expect(!MiniGameSpaceKey.strokeBelongsToGame(game, gameWindow: nil))
    // 화면에서 내려간 게임 창은 판이 도는 창이 아니다.
    #expect(!hidden.isVisible, "전제: 올리지 않은 창")
    #expect(!MiniGameSpaceKey.strokeBelongsToGame(hidden, gameWindow: hidden))
}

@Test("모니터 소스 계약: keyUp 을 받고, 방향 가지가 앞서되 그 안에 스페이스 게이트가 없다")
func theMonitorKeepsBothGatesApart() throws {
    let source = tmStripped(try tmPanelSource())
    let install = try tmInstallBody()

    // 뗌이 없으면 눌림이 굳는다.
    #expect(install.contains("matching: [.keyDown, .keyUp]"), "모니터가 뗌을 안 본다")

    // 방향 가지가 **먼저**다(스페이스 게이트가 방향키를 먼저 거르면 모르는 창에서 방향키가 죽는다).
    let directional = try #require(install.range(of: "if let key = stroke {"))
    let yieldCall = try #require(install.range(of: "yieldsToOtherWindow(target, gameWindow: gameWindow())"))
    let gate = try #require(install.range(of: "guard shouldConsume()"))
    #expect(directional.lowerBound < yieldCall.lowerBound, "방향 가지가 스페이스 가지보다 뒤에 있다")
    // V0330 의 계약(양보 판정이 게이트보다 먼저)은 그대로 살아 있어야 한다.
    #expect(yieldCall.lowerBound < gate.lowerBound)

    // 방향 가지 **안에는** 스페이스 쪽 게이트가 없다 — 섞으면 둘 중 하나가 무너진다.
    let branch = try tmRegion(after: "if let key = stroke {", in: install, includingAnchorBrace: true)
    #expect(!branch.contains("shouldConsume"), "방향 가지가 스페이스 게이트를 쓴다")
    #expect(!branch.contains("yieldsToOtherWindow"), "방향 가지가 스페이스 양보 판정을 쓴다")
    #expect(branch.contains("strokeBelongsToGame"), "방향 가지가 자기 게이트를 안 쓴다")

    // 뗌은 게이트보다 **먼저** 화면에 간다. 이 순서가 뒤집히면 "ESC 중에 뗀 키"가 굳는다.
    let release = try #require(branch.range(of: "onStroke(Stroke(key: key, isDown: false))"))
    let belongsGuard = try #require(branch.range(of: "guard belongs"))
    #expect(release.lowerBound < belongsGuard.lowerBound, "뗌이 게이트 뒤에 있다 — 키가 굳는다")

    // 모니터를 떼면 조작 처리기도 같이 떨어져야 한다(죽은 화면의 클로저가 남는 그 결함).
    let remove = try tmRegion(after: "static func remove()", in: source)
    #expect(remove.contains("armedStroke = nil"), "remove() 가 조작 처리기를 안 놓는다")
}

@MainActor
@Test("install 이 실제로 조작 처리기를 쥔다 — 합성 이벤트 없이 발화로 확인")
func installArmsTheStrokeHandler() {
    final class Box { var strokes: [MiniGameSpaceKey.Stroke] = [] }
    let box = Box()
    defer { MiniGameSpaceKey.remove() }
    MiniGameSpaceKey.install(shouldConsume: { false }, action: {}, wantsStrokes: { true },
                             onStroke: { box.strokes.append($0) })
    MiniGameSpaceKey.fireStrokeForTesting(.init(key: .moveLeft, isDown: true))
    MiniGameSpaceKey.fireStrokeForTesting(.init(key: .moveLeft, isDown: false))
    #expect(box.strokes == [.init(key: .moveLeft, isDown: true), .init(key: .moveLeft, isDown: false)])

    // 떼면 아무도 안 받는다 — 죽은 화면이 계속 입력을 먹으면 "어떤 사람은 되고 어떤 사람은 안 된다"가 된다.
    MiniGameSpaceKey.remove()
    MiniGameSpaceKey.fireStrokeForTesting(.init(key: .hold, isDown: true))
    #expect(box.strokes.count == 2, "모니터를 뗐는데도 처리기가 살아 있다")
}

// MARK: - 순수 규칙: 스트로크 → 입력

@Test("눌림은 상태, 회전·홀드는 횟수 — 그리고 뗌은 멱등이다")
func keyLatchSeparatesLevelsFromEdges() {
    var input = MiniGameInput()
    MiniGameKeyLatch.apply(.init(key: .moveLeft, isDown: true), to: &input, isFrozen: false)
    MiniGameKeyLatch.apply(.init(key: .rotateCW, isDown: true), to: &input, isFrozen: false)
    MiniGameKeyLatch.apply(.init(key: .rotateCW, isDown: true), to: &input, isFrozen: false)
    MiniGameKeyLatch.apply(.init(key: .hold, isDown: true), to: &input, isFrozen: false)
    #expect(input.moveLeftHeld)
    #expect(input.rotateClockwiseCount == 2, "회전을 두 번 눌렀는데 한 번으로 접혔다")
    #expect(input.holdCount == 1)

    // 엣지 키의 뗌은 아무 일도 하지 않는다(게이트 밖에서 온 뗌도 안전해야 한다).
    MiniGameKeyLatch.apply(.init(key: .rotateCW, isDown: false), to: &input, isFrozen: false)
    MiniGameKeyLatch.apply(.init(key: .hold, isDown: false), to: &input, isFrozen: false)
    #expect(input.rotateClockwiseCount == 2 && input.holdCount == 1, "뗌이 횟수를 되돌렸다")

    // 레벨 키의 뗌은 두 번 불러도 같다.
    MiniGameKeyLatch.apply(.init(key: .moveLeft, isDown: false), to: &input, isFrozen: false)
    let once = input
    MiniGameKeyLatch.apply(.init(key: .moveLeft, isDown: false), to: &input, isFrozen: false)
    #expect(input == once, "뗌이 멱등이 아니다")
}

@Test("얼어 있으면 누름은 안 세지만 **뗌은 언제나 반영된다**")
func frozenBoardStillAcceptsReleases() {
    var input = MiniGameInput(moveLeftHeld: true, softDropHeld: true)
    MiniGameKeyLatch.apply(.init(key: .moveRight, isDown: true), to: &input, isFrozen: true)
    MiniGameKeyLatch.apply(.init(key: .rotateCW, isDown: true), to: &input, isFrozen: true)
    #expect(!input.moveRightHeld, "정지 중인데 누름이 먹혔다 — 스크림 뒤에서 판이 움직인다")
    #expect(input.rotateClockwiseCount == 0)
    // ★ 여기가 핵심: "← 를 누른 채 ESC → 손을 뗌 → 재개" 에서 뗌이 무시되면 판이 왼쪽에 붙는다.
    MiniGameKeyLatch.apply(.init(key: .moveLeft, isDown: false), to: &input, isFrozen: true)
    #expect(!input.moveLeftHeld, "정지 중에 뗀 키가 굳었다")
    #expect(input.softDropHeld, "다른 키까지 같이 풀렸다")
}

@Test("releaseAll 은 눌림만 비운다 — 이미 지나간 횟수는 건드리지 않는다")
func releaseAllClearsOnlyHeldKeys() {
    var input = MiniGameInput(actionCount: 3, moveLeftHeld: true, moveRightHeld: true, softDropHeld: true,
                              rotateClockwiseCount: 5, rotateCounterClockwiseCount: 2, holdCount: 1)
    MiniGameKeyLatch.releaseAll(&input)
    #expect(!input.moveLeftHeld && !input.moveRightHeld && !input.softDropHeld)
    #expect(input.actionCount == 3 && input.rotateClockwiseCount == 5
            && input.rotateCounterClockwiseCount == 2 && input.holdCount == 1,
            "이미 지나간 사건까지 지웠다 — 그 프레임의 회전이 사라진다")
}

// MARK: - ③ 눌린 채 판이 끝나는 출구 — **한 곳에 한 테스트**
//
// 한 건으로 묶으면 나머지 다섯을 지워도 초록이다. 그래서 출구마다 따로 잰다.
// 재는 방법은 소스 계약이다: 이 출구들은 SwiftUI 뷰의 @State 를 건드리므로 헤드리스에서 못 두드린다.
// 대신 각 출구 **블록 안**에 해제가 있는지를 본다(블록은 중괄호 짝으로 자른다 — 파일 어딘가에 있으면
// 통과하는 느슨한 검사가 아니다).

private let tmRelease = "MiniGameKeyLatch.releaseAll(&input)"

@Test("출구 ① 탑아웃(자연 종료) — 토큰이 안 오르는 자리다")
func exitTopOutReleasesHeldKeys() throws {
    let block = try tmRegion(after: "if !playing {", in: tmStripped(try tmPanelSource()), includingAnchorBrace: true)
    #expect(block.contains(tmRelease), "탑아웃 뒤에도 눌림이 남는다 — 다음 판이 왼쪽으로 출발한다")
}

@Test("출구 ②~⑥ 공통 수신처(창 닫힘·포커스 상실·종류 전환·그만두기·패널 닫기)")
func exitInterruptTokenReleasesHeldKeys() throws {
    let block = try tmRegion(after: ".onChange(of: store.miniGameInterruptToken)",
                             in: tmStripped(try tmPanelSource()))
    #expect(block.contains(tmRelease), "토큰으로 끝난 판의 눌림이 남는다")
}

@Test("출구 ⑦ 일시정지 — togglePause 는 interruptToken 을 안 올린다(공통 수신처가 못 잡는다)")
func exitPauseReleasesHeldKeys() throws {
    let source = tmStripped(try tmPanelSource())
    let block = try tmRegion(after: "private func togglePause() -> Bool", in: source)
    #expect(block.contains(tmRelease), "정지에 들어갈 때 눌림을 안 비운다")
    // ★ 전제 확인: 이 함수가 정말로 토큰을 안 올린다(올린다면 이 출구는 공통 수신처가 잡고, 이 테스트는 헛돈다).
    #expect(!block.contains("miniGameInterruptToken"),
            "togglePause 가 토큰을 올리게 바뀌었다 — 이 출구의 전제가 달라졌으니 주석을 고쳐라")
}

@Test("출구 ⑧ 뷰 사라짐 — AppKit 창은 이 콜백이 안 올 수 있어 이것만 믿지 않는다")
func exitDisappearReleasesHeldKeys() throws {
    let block = try tmRegion(after: ".onDisappear", in: tmStripped(try tmPanelSource()))
    #expect(block.contains(tmRelease), "화면이 사라질 때 눌림을 안 비운다")
}

@Test("출구 ⑨ 모니터 재설치 — 갈아 끼우는 사이의 뗌은 아무도 못 받는다")
func exitReinstallReleasesHeldKeys() throws {
    let block = try tmRegion(after: "private func installSpaceKey()", in: tmStripped(try tmPanelSource()))
    #expect(block.contains(tmRelease), "모니터를 갈아 끼울 때 눌림을 안 비운다")
    // 해제가 **install 보다 먼저**여야 한다 — 뒤에 두면 새 모니터가 옛 눌림 위에서 시작한다.
    let releaseAt = try #require(block.range(of: tmRelease))
    let installAt = try #require(block.range(of: "MiniGameSpaceKey.install("))
    #expect(releaseAt.lowerBound < installAt.lowerBound)
}

@Test("출구 ⑥ [그만두기] — 스토어가 토큰을 올리지만 여기서도 푼다(스토어 구현에 기대지 않는다)")
func exitQuitReleasesHeldKeys() throws {
    let block = try tmRegion(after: "private func quitRound()", in: tmStripped(try tmPanelSource()))
    #expect(block.contains(tmRelease), "[그만두기]가 눌림을 안 비운다")
}

@Test("방향키는 테트리스가 도는 동안에만 받는다 — 다른 게임에서 삼키면 얻는 것이 0 이다")
func strokesAreWantedOnlyWhileTetrisIsRunning() throws {
    let panel = tmStripped(try tmPanelSource())
    let block = try tmRegion(after: "private func installSpaceKey()", in: panel)
    let wants = try #require(tmBetween(block, "wantsStrokes:", "onStroke:"))
    for needle in ["store.miniGameKind == .tetris", "isPlaying", "!pauseState.isFrozen"] {
        #expect(wants.contains(needle), "wantsStrokes 에 \(needle) 가 없다: \(wants)")
    }
    // 뗌은 게이트 밖에서도 오므로(다른 창에서 화살표를 뗄 때) `&input` 를 그대로 넘기면 그때마다 @State
    // setter 가 불려 이 창이 통째로 다시 그려진다 — 유휴 0% 규약이 남의 창 키 조작에 깨진다.
    let handle = try tmRegion(after: "private func handleStroke(", in: panel)
    #expect(handle.contains("guard next != input else { return }"),
            "바뀐 게 없어도 @State 를 건드린다 — 남의 창 화살표 뗌마다 이 창이 다시 그려진다")
}

// MARK: - 굳은 키 그물(⌘ 를 누르는 순간 사라지는 keyUp)

@Test("8초 그물: 판 시계로 재고, 뗀 뒤에는 바로 되살아난다")
func stuckKeyWatchdogReleasesAfterEightSeconds() {
    // 누르기 시작하면 그 시각을 찍는다.
    let start = TetrisKeyWatchdog.stamp(pressed: true, since: nil, now: 10)
    #expect(start == 10)
    // 계속 누르고 있으면 시각은 안 움직인다(움직이면 영원히 안 만료된다).
    #expect(TetrisKeyWatchdog.stamp(pressed: true, since: start, now: 17.9) == 10)
    #expect(TetrisKeyWatchdog.isLive(pressed: true, since: start, now: 17.9), "7.9초 만에 끊겼다")
    #expect(!TetrisKeyWatchdog.isLive(pressed: true, since: start, now: 18.1), "8초를 넘겨도 안 풀린다")
    #expect(TetrisKeyWatchdog.stuckSeconds == 8)
    // 떼면 시각이 사라지고, 다시 누르면 처음부터다.
    #expect(TetrisKeyWatchdog.stamp(pressed: false, since: start, now: 30) == nil)
    #expect(TetrisKeyWatchdog.stamp(pressed: true, since: nil, now: 30) == 30)
    #expect(TetrisKeyWatchdog.isLive(pressed: true, since: 30, now: 30))
    // 안 눌린 키는 언제나 거짓이다.
    #expect(!TetrisKeyWatchdog.isLive(pressed: false, since: 10, now: 11))
}

@Test("잎 뷰가 그물을 실제로 쓴다 — 벽시계가 아니라 판 시계로")
func theLeafViewRoutesHeldKeysThroughTheWatchdog() throws {
    let view = tmStripped(try CheckCoreSourceLayout.joinedSplitSource("MiniGameTetris.swift"))
    let sync = try tmRegion(after: "private func syncHeldKeys()", in: view)
    #expect(sync.contains("let now = game.elapsed"), "벽시계로 재면 정지 중에도 그물이 돈다")
    for key in ["setLeftHeld", "setRightHeld", "setSoftDropHeld"] {
        #expect(sync.contains("game.\(key)(TetrisKeyWatchdog.isLive("), "\(key) 가 그물을 안 거친다")
    }
    // 이 함수는 **프레임마다** 불린다. SwiftUI 는 값을 비교하지 않고 setter 가 불리면 무효화하므로,
    // 같은 값을 다시 쓰면 프레임마다 세 번씩 헛 무효화가 난다(유휴 0% 규약의 반대편).
    for guarded in ["left != leftSince", "right != rightSince", "soft != softSince"] {
        #expect(sync.contains("if \(guarded)"), "프레임마다 @State 에 같은 값을 다시 쓴다(\(guarded))")
    }
    // 프레임 상한은 한 곳에서만 나온다(이 저장소의 계약).
    for forbidden in ["1.0 / 60.0", "1.0/60.0", "Timer", "CACurrentMediaTime"] {
        #expect(!view.contains(forbidden), "잎 뷰가 `\(forbidden)` 를 쓴다")
    }
    #expect(view.contains("MiniGameFrameRate.minimumInterval(forRefreshRate: host.refreshHz)"))
    #expect(view.contains("MiniGameFrameProbe.note()"), "프레임 프로브가 없다 — 유휴 0% 를 못 잰다")
}

@Test("잎 뷰는 GraphicsContext 필터를 쓰지 않는다 — 통합 GPU 에서 프레임이 깨진다")
func theLeafViewNeverBlursTheCanvas() throws {
    let view = tmStripped(try CheckCoreSourceLayout.joinedSplitSource("MiniGameTetris.swift"))
    for forbidden in ["addFilter", "drawLayer", ".blur("] {
        #expect(!view.contains(forbidden), "캔버스에 `\(forbidden)` 를 쓴다 — 부드러운 빛은 radialGradient 로")
    }
    // 공용 키트를 **재사용**한다(새로 만들지 않는다).
    for shared in ["MiniGameBackdrop.draw", "MiniGameStageChip(", "MiniGameOverlayCard(",
                   "MiniGameScorePop(", "MiniGameEffects.glow", "MiniGameStage.forTetrisAdvance"] {
        #expect(view.contains(shared), "공용 \(shared) 를 안 쓴다 — 두 벌이 되면 언젠가 갈린다")
    }
}

// MARK: - ④ 조각이 배경보다 확실히 밝다

@Test("조각 7종 × 무대 5종: 우물 위 최소 대비가 3:1 을 넘는다(플래피 기둥 1.01:1 사고의 반대편)")
func everyPieceStaysBrighterThanEveryStage() {
    var worst = (ratio: Double.infinity, label: "")
    var report: [String] = []
    for piece in TetrisGame.Piece.allCases {
        let ink = tmRGB(TetrisPalette.color(piece))
        var pieceWorst = Double.infinity
        for stage in MiniGameStage.all {
            for (name, sky) in [("상", stage.skyTop), ("하", stage.skyBottom)] {
                let well = tmOver(tmRGB(TetrisPalette.wellColor), TetrisPalette.wellOpacity, tmRGB(sky))
                let r = tmContrast(ink, well)
                if r < worst.ratio { worst = (r, "\(piece) / \(stage.name)\(name)") }
                pieceWorst = min(pieceWorst, r)
            }
        }
        report.append("\(piece) \(String(format: "%.2f", pieceWorst))")
    }
    print("[대비] 조각 vs 우물 최소: " + report.joined(separator: " · ") + " → 전체 \(String(format: "%.2f", worst.ratio)) (\(worst.label))")
    #expect(worst.ratio >= 3.0, "가장 어두운 조합 \(worst.label) 이 \(worst.ratio):1 이다 — 조각이 배경에 묻힌다")

    // ★ 기준선: 우물이 실제로 하늘을 어둡게 만든다(불투명도를 0 으로 돌리면 이 단언이 먼저 빨개진다).
    let brightest = MiniGameStage.all.map { tmLuminance(tmRGB($0.skyBottom)) }.max() ?? 0
    let wellOverBrightest = tmLuminance(tmOver(tmRGB(TetrisPalette.wellColor), TetrisPalette.wellOpacity,
                                               tmRGB(MiniGameStage.dusk.skyBottom)))
    #expect(wellOverBrightest < brightest / 3, "우물이 하늘을 충분히 어둡게 안 만든다(\(wellOverBrightest) vs \(brightest))")
}

@Test("조각끼리도 갈린다 — 휘도가 같은 쌍(I 하늘 ↔ S 초록)이 있어 채널 차로 잰다")
func everyPairOfPiecesIsDistinguishable() {
    let pieces = TetrisGame.Piece.allCases
    var worst = (distance: Double.infinity, label: "")
    for (i, a) in pieces.enumerated() {
        for b in pieces[(i + 1)...] {
            let x = tmRGB(TetrisPalette.color(a)), y = tmRGB(TetrisPalette.color(b))
            let d = max(abs(x.0 - y.0), max(abs(x.1 - y.1), abs(x.2 - y.2)))
            if d < worst.distance { worst = (d, "\(a) ↔ \(b)") }
        }
    }
    print("[대비] 조각끼리 최소 채널차 \(String(format: "%.3f", worst.distance)) (\(Int(worst.distance * 255))/255) — \(worst.label)")
    #expect(worst.distance >= 0.20, "\(worst.label) 이 \(worst.distance) 밖에 안 갈린다")
    // 휘도만으로는 못 가른다는 사실 자체를 못 박는다 — 이 단언이 깨지면 위 채널 검사를 휘도로 바꿔도 된다는 뜻이다.
    #expect(tmContrast(tmRGB(TetrisPalette.color(.i)), tmRGB(TetrisPalette.color(.s))) < 1.2,
            "I 와 S 의 휘도가 갈렸다 — '휘도로는 조각을 못 가른다'는 이 파일의 전제를 다시 재라")
}

@Test("고스트는 보이되 굳은 칸과 절대 혼동되지 않는다")
func theGhostIsFaintButVisible() {
    var minGhost = Double.infinity, maxGhost = 0.0
    for piece in TetrisGame.Piece.allCases {
        let ink = tmRGB(TetrisPalette.color(piece))
        for stage in MiniGameStage.all {
            let well = tmOver(tmRGB(TetrisPalette.wellColor), TetrisPalette.wellOpacity, tmRGB(stage.skyBottom))
            let ghost = tmOver(ink, TetrisPalette.ghostOpacity, well)
            let r = tmContrast(ghost, well)
            minGhost = min(minGhost, r)
            maxGhost = max(maxGhost, r)
        }
    }
    print("[대비] 고스트 vs 우물 \(String(format: "%.2f", minGhost))~\(String(format: "%.2f", maxGhost)):1")
    #expect(minGhost > 1.15, "고스트가 안 보인다(\(minGhost):1)")
    #expect(maxGhost < 3.0, "고스트가 굳은 칸만큼 진하다(\(maxGhost):1) — 어디가 실물인지 모른다")
}

// MARK: - 헤더 실측 폭

@MainActor
@Test("헤더 실측: 칩 셋 + [일시정지]가 344pt 안에 든다(고른 칩만 이름)")
func theHeaderFitsInThreeHundredFortyFour() throws {
    let budget = MiniGameWindowLayout.canvasSize.width
    for (label, playing, frozen) in [("판이 도는 중(일시정지 버튼)", true, false),
                                     ("정지·시작 전(오목 입구)", false, false),
                                     ("정지 카드(칩 잠금 해제 + 오목 입구)", true, true)] {
        let header = MiniGameGameHeader(selected: .flappy, isPlaying: playing, isFrozen: frozen,
                                        onSelect: { _ in }, onPause: {}, onGomoku: {})
        let width = try tmNaturalWidth(header)
        print("[헤더] \(label): \(String(format: "%.1f", width))pt / \(budget)pt")
        #expect(width <= budget, "\(label) 에서 헤더가 \(width)pt 라 344 를 넘는다")
    }
    // 아이콘 전용이 실제로 폭을 아낀다(이름 셋을 다 달면 넘치는지도 같이 본다).
    let iconOnly = try tmNaturalWidth(MiniGameGameHeader(selected: .flappy, isPlaying: true, isFrozen: false,
                                                         onSelect: { _ in }, onPause: {}, onGomoku: {}))
    let allTitles = try tmNaturalWidth(tmAllTitlesHeader())
    print("[헤더] 이름 셋 전부: \(String(format: "%.1f", allTitles))pt (아이콘 전용 \(String(format: "%.1f", iconOnly))pt)")
    #expect(allTitles > iconOnly + 40, "이름을 다 달아도 폭이 안 늘었다 — showsTitle 이 그림을 안 바꾼다")
}

@Test("아이콘 전용 칩도 VoiceOver 는 이름을 읽는다 — 말풍선은 눈, 라벨은 귀 몫이다")
func iconOnlyChipsStillAnnounceTheirName() throws {
    let panel = tmStripped(try tmPanelSource())
    let chip = try tmRegion(after: "private struct MiniGameKindChip: View", in: panel)
    #expect(chip.contains(".accessibilityLabel(title)"),
            "이름을 뗀 칩이 VoiceOver 에게 아무 말도 안 한다(SF Symbol 의 기본 설명은 게임 이름이 아니다)")
    #expect(chip.contains(".checkTooltip(title)"), "말풍선이 사라졌다 — 이름을 뗀 칩의 유일한 눈 단서다")
    #expect(chip.contains("showsTitle ? 10 : 8"), "아이콘 전용 칩이 이름 칩과 같은 여백을 쓴다")

    // 캔버스 라벨도 **게임별**이어야 한다 — 하드코딩하면 테트리스에서 틀린 조작을 읽는다.
    #expect(panel.contains("\\(store.miniGameKind.controlHint)로 조작"),
            "캔버스 접근성 라벨이 조작 안내를 하드코딩한다")
    #expect(!panel.contains("클릭 또는 스페이스로 조작"), "옛 하드코딩 라벨이 남아 있다")
}

/// 비교용: 세 칩에 전부 이름을 단 헤더(예전 모양). 아이콘 전용이 실제로 폭을 아끼는지 재는 대조군이다.
@MainActor
private func tmAllTitlesHeader() -> some View {
    HStack(spacing: 6) {
        ForEach(MiniGameKind.macCases) { kind in
            Label(kind.title, systemImage: kind.icon)
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(Capsule().fill(Color.white.opacity(0.04)))
        }
        Spacer(minLength: 4)
        Label(CheckMiniGameWindowView.pauseTitle, systemImage: "pause.fill")
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Capsule().fill(Color.white.opacity(0.16)))
    }
}

// MARK: - 순위·푸터 자릿수

@MainActor
@Test("점수 칸 66 — 여덟 자리가 들어가고 이름 칸은 172pt 로 남는다")
func theRankRowFitsEightDigits() throws {
    #expect(MiniGameRankRow.scoreWidth == 66)
    // 행 고정분 = 앞 5 + 배지 22 + 간격 7 + 아바타 22 + 간격 7 + 간격 4(Spacer 최소) + 점수 66 + 뒤 9
    let fixed = MiniGameRankRow.leadingPadding + MiniGameRankRow.badgeSize + MiniGameRankRow.columnSpacing
        + MiniGameRankRow.avatarSize + MiniGameRankRow.columnSpacing + 4
        + MiniGameRankRow.scoreWidth + MiniGameRankRow.trailingPadding
    let nameRoom = MiniGameWindowLayout.rankWidth - fixed
    print("[순위] 고정분 \(fixed)pt · 이름 칸 \(nameRoom)pt / 열 \(MiniGameWindowLayout.rankWidth)pt")
    #expect(nameRoom >= 160, "이름 칸이 \(nameRoom)pt 로 줄었다 — 별명이 심하게 눌린다")

    // "12345678점" 이 66pt 안에 그대로 들어간다(줄여 그리지 않는다 = 행마다 글자 크기가 안 갈린다).
    let wide = try tmNaturalWidth(
        Text(String(12_345_678) + "점").font(.caption.weight(.bold)).monospacedDigit()
    )
    print("[순위] '12345678점' 실측 \(String(format: "%.1f", wide))pt / 칸 \(MiniGameRankRow.scoreWidth)pt")
    #expect(wide <= MiniGameRankRow.scoreWidth,
            "여덟 자리가 \(wide)pt 라 \(MiniGameRankRow.scoreWidth)pt 칸에서 줄어든다")
    // ★ 기준선: 옛 폭(46)에서는 실제로 넘쳤다 — 안 넘쳤다면 이 변경이 아무것도 안 고친 것이다.
    #expect(wide > 46, "옛 폭 46 으로도 들어간다 — 칸을 넓힌 근거가 사라졌다")

    // 이름 칸이 20pt 줄었다 — 별명이 잘리는지 확인한다. `minimumScaleFactor(0.75)` 는 그 아래로는
    // 줄이지 않고 "…" 로 **자른다**. 그러니 실제 별명 폭 ÷ 172 가 0.75 위에 있어야 한다.
    for name in ["킹재영", "Binary는호남선", "아주아주긴별명을쓰는사람"] {
        let natural = try tmNaturalWidth(Text(name).font(.caption.weight(.semibold)))
        let needed = natural / nameRoom
        print("[순위] 별명 '\(name)' \(String(format: "%.1f", natural))pt → 축소율 \(String(format: "%.2f", max(1, needed)))")
        #expect(natural <= nameRoom / 0.75,
                "'\(name)' 이 \(natural)pt 라 \(nameRoom)pt 칸에서 0.75 아래로 눌려 잘린다")
    }
}

@Test("결과 카드의 점수 제목은 한 줄로 가둔다 — 1억이면 두 줄로 접혀 카드가 길어진다")
func theResultCardKeepsTheScoreOnOneLine() throws {
    let card = tmStripped(try CheckCoreSourceLayout.joinedSplitSource("MiniGame.swift"))
    #expect(card.contains("lineLimit(titleIsScore ? 1 : nil)"), "점수 제목이 여러 줄로 접힌다")
    #expect(card.contains("minimumScaleFactor(titleIsScore ? 0.55 : 1)"))
}

@Test("정지 카드 부제: 테트리스는 중단해도 점수가 **기록된다**")
func thePauseSubtitleTellsTheTruthForTetris() throws {
    let panel = tmStripped(try tmPanelSource())
    let block = try tmRegion(after: "private var pauseSubtitle: String", in: panel)
    let tetris = try #require(tmBetween(block, "case .tetris:", "\n"))
    #expect(tetris.contains("기록돼요"), "테트리스 부제: \(tetris)")
    #expect(!tetris.contains("기록되지 않아요"), "interrupt() 가 점수를 확정하는데 '기록되지 않아요'는 거짓말이다")
    // 타이밍 바는 반대다(10라운드를 못 채우면 판이 무효) — 셋이 같은 문구면 둘이 거짓말이 된다.
    let timing = try #require(tmBetween(block, "case .timingBar:", "\n"))
    #expect(timing.contains("기록되지 않아요"))
}

// MARK: - 렌더: 잉크가 예상 사각형 안에 든다
//
// 절대 색이 아니라 **차분**으로 잰다. 한 칸을 채웠을 때 달라지는 픽셀이 그 칸의 사각형 안에만 있어야 한다 —
// 배치가 한 칸이라도 어긋나면 곧바로 빨개지고, 무대 색이 바뀌어도 흔들리지 않는다.

@MainActor
@Test("판 한 칸을 채우면 정확히 그 칸만 달라진다(왼쪽 아래 · 오른쪽 위 · 버퍼행)")
func fillingOneCellChangesOnlyThatCell() throws {
    let empty = try tmRender(tmGame(board: TetrisGame.emptyBoard()))
    let probes: [(String, Int, Int)] = [
        ("왼쪽 아래", TetrisGame.totalRows - 1, 0),
        ("오른쪽 위", TetrisGame.firstVisibleRow, TetrisGame.columns - 1),
        ("버퍼행 가운데", TetrisGame.firstVisibleRow - 1, 5)
    ]
    for (label, row, column) in probes {
        var board = TetrisGame.emptyBoard()
        board[row][column] = .o
        let filled = try tmRender(tmGame(board: board))
        let diff = try #require(tmDiffBounds(filled, empty, tolerance: 8), "\(label) 칸을 채웠는데 그림이 그대로다")
        let expected = tmActual(TetrisLayout.cellRect(row: row, column: column))
        // 래스터 반올림 여유 1.5pt.
        #expect(Double(diff.minX) / 2 >= expected.minX - 1.5, "\(label): 잉크가 왼쪽으로 샜다 \(Double(diff.minX) / 2) < \(expected.minX)")
        #expect(Double(diff.maxX) / 2 <= expected.maxX + 1.5, "\(label): 잉크가 오른쪽으로 샜다 \(Double(diff.maxX) / 2) > \(expected.maxX)")
        #expect(Double(diff.minY) / 2 >= expected.minY - 1.5, "\(label): 잉크가 위로 샜다 \(Double(diff.minY) / 2) < \(expected.minY)")
        #expect(Double(diff.maxY) / 2 <= expected.maxY + 1.5, "\(label): 잉크가 아래로 샜다 \(Double(diff.maxY) / 2) > \(expected.maxY)")
        print("[렌더] \(label) 기대 \(tmRectText(expected)) · 실측 \(tmDiffText(diff))")
    }
}

@MainActor
@Test("홀드 상자·넥스트 열·하단 밴드가 각자의 자리에만 그려진다")
func theSideColumnsAndBandStayInTheirBoxes() throws {
    let base = tmGame(board: TetrisGame.emptyBoard(), next: [.i, .i, .i, .i, .i])
    let baseImage = try tmRender(base)

    // 홀드 — 비어 있던 상자에 조각이 들어온다.
    let held = try tmRender(tmGame(board: TetrisGame.emptyBoard(), next: [.i, .i, .i, .i, .i], heldPiece: .t))
    let holdDiff = try #require(tmDiffBounds(held, baseImage, tolerance: 8), "홀드 조각이 아무것도 안 그린다")
    let holdBox = tmActual(CGRect(x: TetrisLayout.outerMargin, y: TetrisLayout.boxY,
                                  width: TetrisLayout.columnWidth, height: TetrisLayout.boxHeight))
    #expect(Double(holdDiff.maxX) / 2 <= holdBox.maxX + 1.5, "홀드 미리보기가 상자 밖으로 나갔다")
    #expect(Double(holdDiff.minX) / 2 >= holdBox.minX - 1.5)
    #expect(Double(holdDiff.minY) / 2 >= holdBox.minY - 1.5)
    #expect(Double(holdDiff.maxY) / 2 <= holdBox.maxY + 1.5)
    print("[렌더] 홀드 기대 \(tmRectText(holdBox)) · 실측 \(tmDiffText(holdDiff))")

    // 넥스트 — 큐 전체를 다른 조각으로 바꾸면 오른쪽 열에서만 달라진다.
    let nextChanged = try tmRender(tmGame(board: TetrisGame.emptyBoard(), next: [.o, .o, .o, .o, .o]))
    let nextDiff = try #require(tmDiffBounds(nextChanged, baseImage, tolerance: 8), "넥스트가 아무것도 안 그린다")
    let column = tmActual(CGRect(x: TetrisLayout.rightColumnX, y: TetrisLayout.slotY(0),
                                 width: TetrisLayout.columnWidth,
                                 height: TetrisLayout.boardBottomY - TetrisLayout.slotY(0)))
    #expect(Double(nextDiff.minX) / 2 >= column.minX - 1.5, "넥스트가 판 쪽으로 샜다")
    #expect(Double(nextDiff.maxX) / 2 <= column.maxX + 1.5)
    #expect(Double(nextDiff.minY) / 2 >= column.minY - 1.5)
    #expect(Double(nextDiff.maxY) / 2 <= column.maxY + 1.5)
    print("[렌더] 넥스트 기대 \(tmRectText(column)) · 실측 \(tmDiffText(nextDiff))")

    // 하단 밴드 — 여덟 자리 점수가 밴드 안에 머문다(판이나 옆 열로 새지 않는다).
    let scored = try tmRender(tmGame(board: TetrisGame.emptyBoard(), next: [.i, .i, .i, .i, .i], score: 12_345_678))
    let bandDiff = try #require(tmDiffBounds(scored, baseImage, tolerance: 8), "점수가 아무것도 안 그린다")
    let band = tmActual(CGRect(x: TetrisLayout.textMinX - 2, y: TetrisLayout.bandY - 2,
                               width: TetrisLayout.textMaxX - TetrisLayout.textMinX + 4,
                               height: TetrisLayout.bandHeight + 4))
    #expect(Double(bandDiff.minY) / 2 >= band.minY - 1.5, "점수가 판 쪽으로 올라갔다(\(Double(bandDiff.minY) / 2))")
    #expect(Double(bandDiff.maxY) / 2 <= band.maxY + 1.5, "점수가 캔버스 아래로 나갔다")
    #expect(Double(bandDiff.maxX) / 2 <= band.maxX + 1.5, "점수 글자가 오른쪽 모서리 원까지 갔다")
    print("[렌더] 밴드 기대 \(tmRectText(band)) · 실측 \(tmDiffText(bandDiff))")
}

@MainActor
@Test("고스트는 조각과 같은 색이되 훨씬 옅다 — 그리고 판 안에 있다")
func theGhostDrawsUnderTheActivePiece() throws {
    // 조각을 맨 위에 두면 고스트는 바닥에 앉는다.
    let piece = TetrisGame.ActivePiece(piece: .o, rotation: .spawn, column: 4, row: TetrisGame.firstVisibleRow)
    let withPiece = try tmRender(tmGame(board: TetrisGame.emptyBoard(), active: piece))
    let without = try tmRender(tmGame(board: TetrisGame.emptyBoard()))
    let diff = try #require(tmDiffBounds(withPiece, without, tolerance: 8), "조각이 아무것도 안 그린다")
    let well = tmActual(TetrisLayout.wellRect)
    #expect(Double(diff.minX) / 2 >= well.minX - 1.5, "조각·고스트가 판 왼쪽으로 샜다")
    #expect(Double(diff.maxX) / 2 <= well.maxX + 1.5, "조각·고스트가 판 오른쪽으로 샜다")
    // 고스트가 실제로 바닥까지 내려갔다 — 조각만 그렸다면 차이가 위 두 줄에서 끝난다.
    #expect(Double(diff.maxY) / 2 >= well.maxY - 30, "고스트가 바닥에 안 보인다(차이 아랫변 \(Double(diff.maxY) / 2))")
    print("[렌더] 조각+고스트 판 \(tmRectText(well)) · 실측 \(tmDiffText(diff))")
}

@MainActor
@Test("스냅샷 — 사람이 직접 본다(판·홀드·넥스트·밴드·결과 카드)")
func tetrisSnapshots() throws {
    let rows = ["..ssoo....", ".jjssoozz.", "llljjjttt.", "iiiill.ttz"]
    let playing = tmGame(board: TetrisGame.boardFixture(bottomRows: rows),
                         active: .init(piece: .t, rotation: .spawn, column: 3, row: 24),
                         next: [.i, .o, .s, .z, .l], heldPiece: .j,
                         score: 12_345_678, lines: 42, advance: 96, combo: 3, backToBack: 2)
    MiniGameSnapshots.save(try tmRender(playing), name: "tetris-playing.png", sub: "tetris")
    let ready = tmGame(board: TetrisGame.emptyBoard(), phase: .ready)
    MiniGameSnapshots.save(try tmRender(ready), name: "tetris-ready.png", sub: "tetris")
    let result = tmGame(board: TetrisGame.boardFixture(bottomRows: rows), phase: .result, score: 100_000_000)
    MiniGameSnapshots.save(try tmRender(result, best: 9_000), name: "tetris-result.png", sub: "tetris")
    // 렌더 자체가 실패하면(ImageRenderer 가 nil) 위 세 줄이 던진다 — 크기만 확인하고 끝낸다.
    let bitmap = try tmRender(playing)
    #expect(bitmap.pixelsWide == Int(MiniGameWindowLayout.canvasSize.width) * 2)
    #expect(bitmap.pixelsHigh == Int(MiniGameWindowLayout.canvasSize.height) * 2)
}

// MARK: - 스페이스·클릭 한 키가 시작과 하드드롭을 겸한다

@Test("시작시킨 그 누름은 하드드롭까지 하지 않는다 — 그리고 탑아웃 직후엔 아무 일도 없다")
func oneActionKeyDoesExactlyOneThing() throws {
    // 화면이 액션을 **한 번만** 흘린다(두 번 부르면 시작하자마자 조각이 바닥에 박힌다).
    let view = tmStripped(try CheckCoreSourceLayout.joinedSplitSource("MiniGameTetris.swift"))
    let act = try tmRegion(after: "private func act()", in: view)
    #expect(act.components(separatedBy: "game.action()").count - 1 == 1, "act() 가 액션을 한 번만 흘리지 않는다")
    #expect(act.contains("if !wasPlaying, game.isPlaying"), "새 판 첫 프레임이 정지 구간을 물려받는다")

    // 행동: ready 에서 한 번 누르면 판이 시작되고 조각은 **스폰 자리 그대로**다.
    var game = TetrisGame(seed: 7)
    #expect(!game.isPlaying)
    game.action()
    #expect(game.isPlaying, "액션이 판을 안 연다")
    #expect(game.active?.row == TetrisGame.spawnRow, "시작시킨 누름이 하드드롭까지 했다")

    // 그 다음 누름은 하드드롭이다.
    game.action()
    #expect(game.active?.row != TetrisGame.spawnRow || game.phase != .running, "두 번째 누름이 하드드롭이 아니다")

    // 탑아웃 직후 유예: `.over` 동안 반사적으로 누른 스페이스는 새 판을 열지 않는다.
    var over = TetrisGame(seed: 7, board: TetrisGame.emptyBoard(), active: nil,
                          phase: .over(hold: TetrisGame.overHold), score: 1234)
    over.action()
    #expect(over.score == 1234 && over.isGameOver, "죽자마자 누른 키가 새 판을 열었다")
    // 유예를 프레임 단위로 흘린다 — `step(dt:)` 첫 줄이 `maxStep`(1/20) 으로 자르므로 0.4 를 한 번에 못 민다.
    for _ in 0..<20 { over.step(dt: TetrisGame.maxStep) }
    #expect(over.phase == .result, "유예가 안 끝난다")
    over.action()
    #expect(over.phase == .running && over.score == 0, "결과 화면에서 누른 키가 새 판을 안 연다")
}

@MainActor
@Test("캔버스 클릭이 하드드롭으로 간다 — 허브가 액션 카운터 하나로 접는다")
func clickingTheCanvasHardDrops() throws {
    let panel = tmStripped(try tmPanelSource())
    let gesture = try tmRegion(after: "DragGesture(minimumDistance: 0)", in: panel, includingAnchorBrace: false)
    #expect(gesture.contains("input.actionCount += 1"), "캔버스 클릭이 액션으로 안 간다")
    #expect(gesture.contains("guard !pauseState.isFrozen else { return }"), "정지 중 클릭이 판을 움직인다")
    // 잎 뷰가 그 카운터를 본다.
    let view = tmStripped(try CheckCoreSourceLayout.joinedSplitSource("MiniGameTetris.swift"))
    #expect(view.contains(".onChange(of: input.actionCount)"), "잎 뷰가 액션 카운터를 안 본다")
    // 회전·홀드는 **차분**으로 센다(한 프레임에 두 번 누른 것을 한 번으로 접으면 빠른 손이 손해를 본다).
    for (counter, call) in [("rotateClockwiseCount", "game.rotate(clockwise: true)"),
                            ("rotateCounterClockwiseCount", "game.rotate(clockwise: false)"),
                            ("holdCount", "game.holdCurrentPiece()")] {
        let block = try tmRegion(after: ".onChange(of: input.\(counter))", in: view)
        #expect(block.contains("for _ in 0..<max(0, new - old)"), "\(counter) 를 차분으로 안 센다")
        #expect(block.contains(call), "\(counter) 가 \(call) 로 안 간다")
    }
}

// MARK: - 판정 문구

@Test("판정 이름: 퍼펙트 > T-스핀 > 테트리스 순서로 가른다")
func verdictNamesTheBiggestThingThatHappened() {
    func event(lines: Int, spin: TetrisGame.Spin = .none, perfect: Bool = false) -> TetrisGame.ClearEvent {
        .init(lines: lines, spin: spin, backToBack: false, perfectClear: perfect, points: 100, at: 0)
    }
    #expect(TetrisGameView.verdict(event(lines: 4, perfect: true)) == "퍼펙트 클리어")
    #expect(TetrisGameView.verdict(event(lines: 4)) == "테트리스!")
    #expect(TetrisGameView.verdict(event(lines: 2, spin: .full)) == "T-스핀 더블")
    #expect(TetrisGameView.verdict(event(lines: 1, spin: .mini)) == "T-스핀 미니")
    // 평범한 1~3줄은 캡션 없이 점수만 뜬다 — 매번 글자가 뜨면 아무것도 특별하지 않다.
    #expect(TetrisGameView.verdict(event(lines: 1)) == nil)
    #expect(TetrisGameView.verdict(event(lines: 3)) == nil)
    // 퍼펙트가 T-스핀보다 앞이다(둘 다일 때 더 드문 쪽을 말한다).
    #expect(TetrisGameView.verdict(event(lines: 2, spin: .full, perfect: true)) == "퍼펙트 클리어")
    // 팝은 줄소거 정지(0.5초)보다 오래 머문다.
    #expect(TetrisGameView.popHold > TetrisGame.lineClearSeconds)
}

// MARK: - 정지 상한(토큰이 정지 중에도 늙는다)

@Test("정지 상한 5분은 라운드 토큰 예산 안에 있다 — 숫자를 근거에서 되짚는다")
func pauseLimitFitsInsideTheRoundTokenBudget() {
    // 서버 TTL 30분(20260914010000:225-226) − 클라가 재사용하는 토큰의 최대 나이 12분 − 한 판 최장 ~9분.
    let ttl = 30 * 60, reuse = 12 * 60, longestRound = 9 * 60
    let headroom = ttl - reuse - longestRound
    #expect(CheckMiniGameWindowView.PauseState.pauseLimitSeconds < headroom,
            "정지 상한이 토큰 여유(\(headroom)초)보다 크다 — 멈춰 뒀다는 이유로 기록을 잃는다")
    #expect(CheckMiniGameWindowView.PauseState.pauseLimitSeconds == 5 * 60)
}

@Test("정지 감시는 카드가 떠 있는 동안만 돌고, 상한에서 **그 점수로 확정**한다(무효가 아니다)")
func pauseWatchdogArmsOnlyWhileTheCardIsUpAndConfirmsTheScore() throws {
    let panel = tmStripped(try tmPanelSource())
    // 걸리는 자리: .paused 일 때만. 카운트다운은 3초라 상한과 무관하다.
    #expect(panel.contains("if case .paused = pauseState { armPauseWatchdog() } else { cancelPauseWatchdog() }"),
            "정지 감시가 .paused 분기에 안 걸려 있다")
    // 상한에서 부르는 것은 quitRound — 이 저장소에서 '중단해도 점수 유효'를 실행하는 바로 그 경로다.
    let watchdog = try tmRegion(after: "private func armPauseWatchdog()", in: panel)
    #expect(watchdog.contains("quitRound()"), "상한에서 판을 무효로 끝낸다 — 점수가 사라진다")
    // ★ 상한은 **회당이 아니라 판 누적**이다. 회당이면 "4분 59초 → 재개 → 다시 정지" 를 반복해
    //   벽시계를 무한히 늘릴 수 있고, 그러면 상한이 막으려던 바로 그 손실이 그대로 일어난다.
    #expect(watchdog.contains("while pausedSecondsUsed < PauseState.pauseLimitSeconds"),
            "감시가 한 번 자고 끝난다 — 정지를 풀었다 걸면 시계가 처음부터 간다")
    #expect(watchdog.contains("pausedSecondsUsed += 1"), "누적을 안 센다")
    #expect(!watchdog.contains("sleep(for: .seconds(PauseState.pauseLimitSeconds))"),
            "상한만큼 한 번에 자면 누적이 성립하지 않는다")
    // 0 으로 되돌리는 자리는 **판 시작 한 곳뿐**이어야 한다(재개에서 되돌리면 회당으로 돌아간다).
    // 선언(`@State … = 0`) + 판 시작 리셋, 딱 둘이어야 한다. 셋째가 생기면 회당으로 돌아간다.
    #expect(panel.contains("@State private var pausedSecondsUsed = 0"), "선언 모양이 바뀌었다 — 아래 개수 단언의 전제")
    #expect(panel.components(separatedBy: "pausedSecondsUsed = 0").count - 1 == 2,
            "정지 예산을 판 시작 말고 다른 곳에서도 되돌린다(재개에서 되돌리면 회당 상한이 된다)")
    let begin = try tmRegion(after: "if playing {", in: panel, includingAnchorBrace: true)
    #expect(begin.contains("pausedSecondsUsed = 0"), "새 판에 정지 예산을 안 준다")
    #expect(watchdog.contains("store.miniGameKind == .tetris"), "두 기존 게임에도 상한이 걸린다")
    #expect(watchdog.contains("guard case .paused = pauseState, isPlaying else { return }"),
            "이어하기·그만두기·판 종료 뒤에도 발화한다")
    // 거두는 자리 넷(이어하기·그만두기·판 종료·재무장). 하나라도 빠지면 끝난 판에서 발화한다.
    for site in ["private func beginResume()", "private func quitRound()", "private func armPauseWatchdog()"] {
        let region = try tmRegion(after: site, in: panel)
        #expect(region.contains("cancelPauseWatchdog()"), "\(site) 가 정지 감시를 안 거둔다")
    }
    #expect(panel.contains("cancelResume()\n                    cancelPauseWatchdog()"),
            "판이 스스로 끝날 때(onPlayingChanged) 정지 감시를 안 거둔다")
}

@Test("토큰 만료만 이유를 밝힌다 — too_fast 는 밝히지 않는다(위조 보조)")
func onlyTokenExpiryExplainsItself() throws {
    let store = tmStripped(try tmSource("WorkTimerStoreMiniGame.swift"))
    #expect(store.contains("response.status == \"token_expired\""),
            "거절 이유를 갈라 주지 않는다 — 오래 끌어 잃은 사람이 원인을 모른다")
    #expect(store.contains("판이 너무 오래 걸려 기록하지 못했어요"))
    // need_seconds/elapsed_seconds 는 어디에도 나가지 않는다(위조 타이밍 계산 보조).
    #expect(!store.contains("need_seconds"))
    #expect(!store.contains("elapsed_seconds"))
}

// MARK: - 헬퍼

private enum TMError: Error { case render, region(String) }

private func tmSource(_ name: String) throws -> String {
    try String(contentsOf: CheckCoreSourceLayout.repoRoot
        .appendingPathComponent("Sources/check", isDirectory: true)
        .appendingPathComponent(name), encoding: .utf8)
}

private func tmPanelSource() throws -> String { try tmSource("MiniGamePanel.swift") }

/// 모니터 본문. **중괄호 짝으로 자르지 않는다** — `install` 의 인자에 기본 클로저(`= { false }`)가 있어
/// "닻 뒤 첫 중괄호"가 그 클로저를 집는다(처음에 그렇게 썼다가 검사가 통째로 공허해졌다).
/// V0330 과 같은 방식으로 `remove()` 선언 앞까지를 잘라 쓰고, 잘린 것이 진짜 본문인지 기준선으로 확인한다.
private func tmInstallBody() throws -> String {
    let source = tmStripped(try tmPanelSource())
    guard let start = source.range(of: "static func install(shouldConsume:")?.lowerBound,
          let end = source.range(of: "static func remove()", range: start..<source.endIndex)?.lowerBound
    else { throw TMError.region("install 본문을 못 찾는다") }
    let body = String(source[start..<end])
    guard body.contains("NSEvent.addLocalMonitorForEvents") else {
        throw TMError.region("install 본문이 반쪽이다 — 이 아래 검사가 전부 공허해진다")
    }
    return body
}

/// 주석을 걷어낸다. **안 걷어내면 설명을 지워야만 초록이 되는 테스트가 된다** — 이 저장소가 겪은 함정이다.
private func tmStripped(_ source: String) -> String {
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
            if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { inString = false }
        } else if c == "/", next == "/" {
            inLine = true
            index = nextIndex
        } else if c == "/", next == "*" {
            inBlock = true
            index = nextIndex
        } else {
            out.append(c)
            if c == "\"" { inString = true }
        }
        index = source.index(after: index)
    }
    return out
}

/// 닻 뒤 첫 중괄호 블록을 **짝을 세어** 잘라 낸다. 파일 어딘가에 문자열이 있으면 통과하는 느슨한 검사가
/// 되지 않게 — 출구 검사는 "그 블록 **안**에 있는가"여야 한다.
private func tmRegion(after anchor: String, in source: String, includingAnchorBrace: Bool = false) throws -> String {
    guard let anchorRange = source.range(of: anchor) else { throw TMError.region("닻 없음: \(anchor)") }
    var index = includingAnchorBrace ? source.index(before: anchorRange.upperBound) : anchorRange.upperBound
    while index < source.endIndex, source[index] != "{" { index = source.index(after: index) }
    guard index < source.endIndex else { throw TMError.region("블록 없음: \(anchor)") }
    var depth = 0
    let start = index
    while index < source.endIndex {
        if source[index] == "{" { depth += 1 }
        if source[index] == "}" {
            depth -= 1
            if depth == 0 { return String(source[start...index]) }
        }
        index = source.index(after: index)
    }
    throw TMError.region("짝이 안 맞음: \(anchor)")
}

private func tmBetween(_ source: String, _ open: String, _ close: String) -> String? {
    guard let a = source.range(of: open),
          let b = source.range(of: close, range: a.upperBound..<source.endIndex) else { return nil }
    return String(source[a.upperBound..<b.lowerBound])
}

// ── 색 계산(WCAG) ──────────────────────────────────────────────────────────────────────────

private func tmRGB(_ color: Color) -> (Double, Double, Double) {
    let ns = NSColor(color).usingColorSpace(.sRGB) ?? NSColor.black
    return (Double(ns.redComponent), Double(ns.greenComponent), Double(ns.blueComponent))
}

private func tmOver(_ fg: (Double, Double, Double), _ alpha: Double, _ bg: (Double, Double, Double)) -> (Double, Double, Double) {
    (fg.0 * alpha + bg.0 * (1 - alpha), fg.1 * alpha + bg.1 * (1 - alpha), fg.2 * alpha + bg.2 * (1 - alpha))
}

private func tmLuminance(_ c: (Double, Double, Double)) -> Double {
    func lin(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
    return 0.2126 * lin(c.0) + 0.7152 * lin(c.1) + 0.0722 * lin(c.2)
}

private func tmContrast(_ a: (Double, Double, Double), _ b: (Double, Double, Double)) -> Double {
    let la = tmLuminance(a), lb = tmLuminance(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
}

// ── 창(진짜 NSWindow — 합성 이벤트로는 이 앱의 창이 열리지 않는다) ─────────────────────────

@MainActor
private func tmWindow(identifier: String? = nil, onScreen: Bool = true) -> NSWindow {
    let window = NSWindow(contentRect: NSRect(x: -4000, y: -4000, width: 200, height: 80),
                          styleMask: [.titled], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    window.alphaValue = 0
    if let identifier { window.identifier = NSUserInterfaceItemIdentifier(identifier) }
    window.contentView = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 80))
    if onScreen { window.orderFrontRegardless() }
    return window
}

// ── 렌더 ──────────────────────────────────────────────────────────────────────────────────

@MainActor
private func tmGame(board: [[TetrisGame.Piece?]],
                    active: TetrisGame.ActivePiece? = nil,
                    phase: TetrisGame.Phase = .running,
                    next: [TetrisGame.Piece] = [.i, .o, .s, .z, .l],
                    heldPiece: TetrisGame.Piece? = nil,
                    score: Int = 0,
                    lines: Int = 0,
                    advance: Int = 0,
                    combo: Int = -1,
                    backToBack: Int = -1) -> TetrisGame {
    TetrisGame(seed: 20_260_923, board: board, active: active, phase: phase, next: next,
               heldPiece: heldPiece, score: score, advance: advance, lines: lines,
               combo: combo, backToBack: backToBack)
}

@MainActor
private func tmRender(_ game: TetrisGame, best: Int = 0) throws -> NSBitmapImageRep {
    let size = MiniGameWindowLayout.canvasSize
    let view = TetrisGameView(host: .inert(bestScore: best), input: MiniGameInput(), initialGame: game)
        .frame(width: size.width, height: size.height)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff) else { throw TMError.render }
    return bitmap
}

@MainActor
private func tmNaturalWidth(_ view: some View) throws -> Double {
    let renderer = ImageRenderer(content: view.fixedSize())
    renderer.scale = 2
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff) else { throw TMError.render }
    return Double(bitmap.pixelsWide) / 2
}

/// 논리 사각형 → 캔버스 실제 pt(344×356 안). 배율·원점은 두 게임과 같은 투영에서 온다.
@MainActor
private func tmActual(_ logical: CGRect) -> CGRect {
    let t = MiniGameCanvas.transform(in: MiniGameWindowLayout.canvasSize, logicalSize: TetrisLayout.logicalSize)
    return CGRect(x: t.origin.x + logical.minX * t.scale, y: t.origin.y + logical.minY * t.scale,
                  width: logical.width * t.scale, height: logical.height * t.scale)
}

private func tmRectText(_ r: CGRect) -> String {
    String(format: "x %.1f…%.1f · y %.1f…%.1f", r.minX, r.maxX, r.minY, r.maxY)
}

private func tmDiffText(_ d: (minX: Int, minY: Int, maxX: Int, maxY: Int)) -> String {
    String(format: "x %.1f…%.1f · y %.1f…%.1f",
           Double(d.minX) / 2, Double(d.maxX) / 2, Double(d.minY) / 2, Double(d.maxY) / 2)
}

private func tmDiffBounds(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep, tolerance: Int = 0) -> (minX: Int, minY: Int, maxX: Int, maxY: Int)? {
    guard a.pixelsWide == b.pixelsWide, a.pixelsHigh == b.pixelsHigh,
          let pa = a.bitmapData, let pb = b.bitmapData else { return nil }
    let bpr = a.bytesPerRow, spp = a.samplesPerPixel
    var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
    for y in 0..<a.pixelsHigh {
        for x in 0..<a.pixelsWide {
            let offset = y * bpr + x * spp
            var differs = false
            for sample in 0..<min(spp, 3) where abs(Int(pa[offset + sample]) - Int(pb[offset + sample])) > tolerance {
                differs = true
                break
            }
            if differs { minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y) }
        }
    }
    guard maxX >= 0 else { return nil }
    return (minX, minY, maxX, maxY)
}
