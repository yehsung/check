import SwiftUI
import CheckCore

// MARK: - 테트리스 (v0.3.38)
//
// 미니게임 3종 중 셋째. 규칙은 `TetrisGame`(순수 값 타입 — 뷰·스토어·시계 의존 0)에, 그림과 프레임 루프는
// `TetrisGameView`(잎 뷰 하나)에 있다. 허브(미니게임 창)는 `MiniGameHost` 와 `MiniGameInput` 만 건네고
// 이 뷰는 그 둘 말고는 아무것도 읽지 않는다 — 플래피·타이밍 바와 **같은 계약**이다(MiniGame.swift 머리 주석).
//
// ── 왜 캔버스 한 장인가 ────────────────────────────────────────────────────────────────────
// 판 10×20 = 200칸에 고스트 4칸·조각 4칸·홀드·넥스트 5개까지 얹으면 SwiftUI 뷰로는 프레임마다 250개가 넘는
// 서브트리가 생긴다. 플래피가 잔상 8겹으로 겪은 그 비용이다(MiniGameFlappy.swift 머리 주석 — 겹을 줄여
// 프레임당 그리기 21% 감소). 그래서 판·조각·상자는 전부 `Canvas` 한 장에 사각형으로 그리고, **글자만**
// 위 겹(SwiftUI Text)에 둔다. 글자를 Canvas 로 그리면 `context.resolve` 가 프레임마다 타이포그래피를
// 다시 잡아 오히려 비싸고, `.monospacedDigit()` 같은 규약도 잃는다.
//
// ── blur 금지 ─────────────────────────────────────────────────────────────────────────────
// `GraphicsContext` 의 `addFilter`·`drawLayer` 를 쓰지 않는다 — 60Hz 에서 캔버스를 흐리면 통합 GPU 에서
// 프레임이 깨진다(MiniGameEngine.swift `MiniGameBackdrop` 머리 주석). 우물 뒤의 부드러운 빛은
// `MiniGameEffects.glow`(radialGradient) 하나로 만든다.
//
// ── 배경에 지형(능선)을 쓰지 않는 이유 ────────────────────────────────────────────────────
// `MiniGameBackdrop.draw(terrain:)` 의 능선은 캔버스 **아래쪽**을 밝게 채운다. 테트리스는 바로 거기에
// 하단 밴드(점수 · B2B/콤보)가 있어 능선 위에 글자가 겹친다. 게다가 능선은 `scroll` 로 흘러야 뜻이 있는데
// 테트리스 판은 가로로 흐르지 않는다 — 정지한 능선은 그냥 밝은 띠다. 그래서 하늘만 쓴다.

// MARK: - 배치 · 조각 색 → 코어
//
// `TetrisLayout`(논리 292×302 · 셀 13)과 `TetrisPalette`(조각 7종 색 · 우물 불투명도)는
// `Sources/CheckCore/TetrisLayout.swift` 에 있다 — **폰 화면이 같은 표를 쓴다**(폰 전용 배치를 만들지 않는다).
// 왜 이 값인가(가로 합 292 · 세로 합 302 · 세 바닥 273 · 조각 대비 실측)는 전부 거기 머리 주석에 옮겨 갔다.
// 소스 계약 테스트는 두 조각을 `CheckCoreSourceLayout.joinedSplitSource("MiniGameTetris.swift")` 로 이어 읽는다.

// MARK: - 굳은 키 그물

/// 눌린 채 판이 끝나는 출구 중 **클라가 못 막는 하나**(⌘ 를 누르는 순간 그 keyUp 이 통째로 사라진다)를
/// 위한 마지막 그물. 판 시계로 재고, 8초를 넘긴 레벨 키는 화면이 스스로 뗀다.
///
/// 왜 8초인가: 판이 10열이라 ARR 0.033초면 0.33초에 벽에 닿는다. 8초 연속 한 방향은 어떤 플레이에서도
/// 뜻이 없고, 소프트드롭도 20행을 다 내려가는 데 1초가 안 걸린다. 그래도 정직한 플레이를 끊지 않을 만큼은
/// 길다 — 레벨 1(중력 1초/칸)에서 20행을 소프트드롭으로 훑는 데 걸리는 시간의 여덟 배다.
///
/// **벽시계가 아니라 `game.elapsed`** 로 잰다. 일시정지·창 숨김 동안 시계가 멈춰야 "정지했다가 돌아오니
/// 키가 풀려 있다"가 안 생긴다.
enum TetrisKeyWatchdog {
    static let stuckSeconds: TimeInterval = 8.0

    /// 눌림 시작 시각 갱신(순수). 떼면 nil, 누르기 시작하면 지금, 계속 누르고 있으면 그대로.
    static func stamp(pressed: Bool, since: TimeInterval?, now: TimeInterval) -> TimeInterval? {
        guard pressed else { return nil }
        return since ?? now
    }

    /// 엔진에 넘길 눌림. 굳은 키(8초 초과)는 거짓이다.
    static func isLive(pressed: Bool, since: TimeInterval?, now: TimeInterval) -> Bool {
        guard pressed, let since else { return false }
        return now - since < stuckSeconds
    }
}

// MARK: - 잎 뷰

/// 테트리스 캔버스. 부모가 준 프레임을 채우고, 규칙은 `TetrisGame` 에 맡긴다.
///
/// 프레임 루프는 `TimelineView(.animation(paused:))` 하나뿐이다 — 진행 중(running·텀·유예)일 때만 돌고,
/// ready/result 와 허브의 interrupt·일시정지 뒤엔 멈춘다(유휴 0%). 틱은 TimelineView 의 날짜가 바뀔 때
/// (`onChange`)만 일어나므로 body 평가 도중 상태를 바꾸지 않는다.
///
/// ⚠️ 여기에 SwiftUI 반복 애니메이션(`repeatForever`)을 넣지 마라 — 값만 내려서는 안 멈춰 창을 닫아도
/// 컴포지터가 코어를 계속 태운다(플래피가 v0.2.48 에 그랬고 v0.2.51 에 걷어냈다).
struct TetrisGameView: View {
    let host: MiniGameHost
    let input: MiniGameInput

    @State private var game: TetrisGame
    @State private var lastTick: Date?
    /// 레벨 키가 눌리기 시작한 판 시각(굳은 키 그물). 벽시계가 아니다.
    @State private var leftSince: TimeInterval?
    @State private var rightSince: TimeInterval?
    @State private var softSince: TimeInterval?

    init(host: MiniGameHost, input: MiniGameInput, initialGame: TetrisGame? = nil) {
        self.host = host
        self.input = input
        // 시드는 시각에서 — 판마다 다른 조각 순서. 테스트는 initialGame 으로 고정한다(플래피와 같은 규약).
        let seed = UInt64(truncatingIfNeeded: Int64(Date().timeIntervalSince1970 * 1000))
        _game = State(initialValue: initialGame ?? TetrisGame(seed: seed))
    }

    var body: some View {
        // 프레임 상한은 **화면 주사율에서 온다**. 여기 숫자를 적지 마라 — 1/60 을 박아 두면 75Hz·144Hz 에서
        // 네 프레임에 한 장이 두 배로 늘어진다(근거·표는 `MiniGameFrameRate`). 소스 계약 테스트가 막는다.
        TimelineView(.animation(minimumInterval: MiniGameFrameRate.minimumInterval(forRefreshRate: host.refreshHz),
                                paused: !game.isPlaying || host.isPaused)) { context in
            canvas
                .onChange(of: context.date) { _, now in tick(now) }
        }
        .onChange(of: input.actionCount) { _, _ in act() }
        // 회전·홀드는 **차분**으로 센다. 한 프레임에 두 번 눌린 경우를 한 번으로 접으면 빠른 손이 손해를 본다.
        .onChange(of: input.rotateClockwiseCount) { old, new in
            for _ in 0..<max(0, new - old) { game.rotate(clockwise: true) }
        }
        .onChange(of: input.rotateCounterClockwiseCount) { old, new in
            for _ in 0..<max(0, new - old) { game.rotate(clockwise: false) }
        }
        .onChange(of: input.holdCount) { old, new in
            for _ in 0..<max(0, new - old) { game.holdCurrentPiece() }
        }
        // 눌림은 카운터가 아니라 **상태**다. 값이 바뀐 그 프레임에 곧바로 반영해야 "눌렀는데 한 박자 뒤에 간다"가 없다.
        .onChange(of: input.moveLeftHeld) { _, _ in syncHeldKeys() }
        .onChange(of: input.moveRightHeld) { _, _ in syncHeldKeys() }
        .onChange(of: input.softDropHeld) { _, _ in syncHeldKeys() }
        .onChange(of: host.interruptToken) { _, _ in
            game.interrupt()
            clearHeldStamps()
        }
        .onChange(of: game.isPlaying) { _, playing in
            host.onPlayingChanged(playing)
        }
        .onChange(of: game.phase) { old, new in
            // 결과 확정은 판마다 한 번 — running/텀/유예 → result 전이가 그 순간이다(interrupt 포함).
            if new == .result, old != .result { host.onFinished(game.score) }
        }
    }

    // MARK: 입력

    private func act() {
        let wasPlaying = game.isPlaying
        // 시작과 하드드롭이 같은 키다. 엔진의 `action()` 이 phase 로 가르므로 **시작시킨 그 누름이
        // 하드드롭까지 하는 일은 없다**(ready/result → 새 판, running → 하드드롭, 텀·유예 → 무시).
        // 탑아웃 직후 반사적 스페이스도 `.over(hold:)` 유예가 삼킨다.
        game.action()
        // 새 판 첫 프레임은 정지해 있던 동안의 시간을 물려받지 않는다.
        if !wasPlaying, game.isPlaying {
            lastTick = nil
            clearHeldStamps()
            // 새 판은 엔진이 눌림을 비우고 시작한다(`startRound` 의 releaseAllKeys). 사람이 아직 누르고
            // 있다면 여기서 곧바로 되돌려 줘야 "시작하자마자 방향키가 한 번 죽는다"가 안 생긴다.
            syncHeldKeys()
        }
    }

    /// 화면이 쥔 눌림을 엔진에 반영한다. **굳은 키 그물**(8초)이 여기 한 곳에만 있다.
    ///
    /// 이 함수는 프레임마다 불린다(tick). 그래서 `@State` 에 **같은 값을 대입하지 않는다** — SwiftUI 는
    /// 값을 비교하지 않고 setter 가 불리면 뷰를 무효화하므로, 그냥 쓰면 프레임마다 세 번씩 헛 무효화가 난다
    /// (같은 근거가 `MiniGameFrameRateMonitor.update` 에 있다). 엔진 쪽은 `setLeftHeld` 안에 이미 가드가 있다.
    private func syncHeldKeys() {
        let now = game.elapsed
        let left = TetrisKeyWatchdog.stamp(pressed: input.moveLeftHeld, since: leftSince, now: now)
        let right = TetrisKeyWatchdog.stamp(pressed: input.moveRightHeld, since: rightSince, now: now)
        let soft = TetrisKeyWatchdog.stamp(pressed: input.softDropHeld, since: softSince, now: now)
        if left != leftSince { leftSince = left }
        if right != rightSince { rightSince = right }
        if soft != softSince { softSince = soft }
        game.setLeftHeld(TetrisKeyWatchdog.isLive(pressed: input.moveLeftHeld, since: left, now: now))
        game.setRightHeld(TetrisKeyWatchdog.isLive(pressed: input.moveRightHeld, since: right, now: now))
        game.setSoftDropHeld(TetrisKeyWatchdog.isLive(pressed: input.softDropHeld, since: soft, now: now))
    }

    private func clearHeldStamps() {
        leftSince = nil
        rightSince = nil
        softSince = nil
    }

    private func tick(_ now: Date) {
        // 프로브는 가드 **앞**이다 — 재는 것이 "틱이 일을 했는가"가 아니라 "프레임 루프가 돌았는가"이기 때문이다.
        MiniGameFrameProbe.note()
        guard game.isPlaying, !host.isPaused else { lastTick = nil; return }
        defer { lastTick = now }
        guard let last = lastTick else { return }
        // 눌림을 먼저 맞추고 시간을 흘린다 — 반대로 하면 굳은 키가 한 프레임 더 산다.
        syncHeldKeys()
        game.step(dt: now.timeIntervalSince(last))
    }

    // MARK: 그림

    private var stage: MiniGameStage { MiniGameStage.forTetrisAdvance(game.advance) }

    /// 겹은 넷뿐이다: 캔버스(하늘 → 우물 → 굳은 칸 → 고스트 → 조각 → 홀드·넥스트 상자) · HUD 글자 ·
    /// 판정 팝 · 시작/결과 카드. **여기에 겹을 더하지 마라** — 플래피가 겹을 늘렸다가 전부 되돌렸다.
    private var canvas: some View {
        ZStack {
            Canvas(rendersAsynchronously: false) { context, size in
                draw(&context, size: size)
            }
            hud
            clearPop
            overlayCard
        }
        // 바탕은 캔버스가 하늘로 꽉 채운다. 모서리만 창 모양대로 잘라 낸다(두 게임과 같은 규약).
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func draw(_ context: inout GraphicsContext, size: CGSize) {
        let t = MiniGameProjection(container: size, logicalSize: TetrisLayout.logicalSize)
        let full = CGRect(origin: .zero, size: size)
        let stage = self.stage

        // 1) 하늘 — 논리 사각형이 아니라 **캔버스 전체**를 덮는다(레터박스 0.11pt 까지).
        //    `terrain: false` · `scroll: 0` 인 이유는 파일 머리 주석에.
        MiniGameBackdrop.draw(into: &context, rect: full, stage: stage, scroll: 0,
                              terrain: false, reduceMotion: host.reduceMotion)

        // 2) 우물 뒤 후광 — blur 가 아니라 radialGradient 하나다(통합 GPU 에서 프레임이 깨지는 그 금지).
        let well = t.rect(TetrisLayout.wellRect)
        MiniGameEffects.glow(into: &context,
                             in: well.insetBy(dx: -well.width * 0.45, dy: -well.height * 0.12),
                             color: stage.glow, opacity: 0.16)

        // 3) 우물 바닥. **조각-배경 대비의 기준값**이라 불투명도를 흔들면 TetrisPalette 의 실측이 무효가 된다.
        context.fill(Path(roundedRect: well, cornerRadius: 4 * t.scale),
                     with: .color(TetrisPalette.wellColor.opacity(TetrisPalette.wellOpacity)))
        drawGrid(&context, t: t)
        // 버퍼행은 **판의 일부지만 규칙상 다른 자리**다(여기까지 쌓이면 다음 스폰이 막혀 끝난다).
        // 경계선 하나로 그 사실을 말한다 — 색을 달리하면 조각 색과 싸운다.
        let boundary = t.rect(TetrisLayout.boardX, TetrisLayout.boardTopY, TetrisLayout.boardWidth, 1)
        context.fill(Path(boundary), with: .color(stage.structureEdge.opacity(0.45)))
        context.stroke(Path(roundedRect: well, cornerRadius: 4 * t.scale),
                       with: .color(stage.structureEdge.opacity(0.55)), lineWidth: 1)

        // 4) 굳은 칸. 버퍼행(보이는 판 바로 위 한 줄)은 0.55 로 흐리게 — 거기 쌓인 것은 "곧 끝"이라는 경고다.
        let bufferRow = TetrisGame.firstVisibleRow - 1
        for row in bufferRow..<TetrisGame.totalRows {
            for column in 0..<TetrisGame.columns {
                guard let piece = game.board[row][column] else { continue }
                drawCell(&context, t: t, row: row, column: column,
                         color: TetrisPalette.color(piece),
                         opacity: row == bufferRow ? 0.55 : 1)
            }
        }

        // 5) 고스트 → 6) 조각 순서다. 겹치는 자리에서는 실물이 위로 와야 한다.
        if let ghost = game.ghost, let active = game.active, ghost.row != active.row {
            for cell in ghost.cells where cell.row >= bufferRow {
                drawCell(&context, t: t, row: cell.row, column: cell.column,
                         color: TetrisPalette.color(ghost.piece),
                         opacity: TetrisPalette.ghostOpacity, highlight: false)
            }
        }
        if let active = game.active {
            for cell in active.cells where cell.row >= bufferRow {
                drawCell(&context, t: t, row: cell.row, column: cell.column,
                         color: TetrisPalette.color(active.piece),
                         opacity: cell.row == bufferRow ? 0.55 : 1)
            }
        }

        // 7) 홀드 상자와 넥스트 5칸. 크기가 아니라 **세기**로 1번 슬롯을 구분한다 —
        //    크기를 달리하면 슬롯 산식이 두 벌이 되어 언젠가 갈린다.
        drawSlot(&context, t: t, rect: CGRect(x: TetrisLayout.outerMargin, y: TetrisLayout.boxY,
                                              width: TetrisLayout.columnWidth, height: TetrisLayout.boxHeight),
                 piece: game.heldPiece, stage: stage,
                 emphasized: false, spent: game.holdUsed)
        for (index, piece) in game.next.prefix(TetrisGame.nextCount).enumerated() {
            drawSlot(&context, t: t, rect: CGRect(x: TetrisLayout.rightColumnX, y: TetrisLayout.slotY(index),
                                                  width: TetrisLayout.columnWidth, height: TetrisLayout.boxHeight),
                     piece: piece, stage: stage,
                     emphasized: index == 0, spent: false)
        }
    }

    /// 우물 격자. 아주 옅은 선이라 빈 판에서도 "여기가 10열이다"가 읽히고, 조각 위로는 안 올라온다(먼저 그린다).
    private func drawGrid(_ context: inout GraphicsContext, t: MiniGameProjection) {
        let line = GraphicsContext.Shading.color(.white.opacity(0.055))
        for column in 1..<TetrisGame.columns {
            let x = TetrisLayout.boardX + CGFloat(column) * TetrisLayout.cell
            context.fill(Path(t.rect(x, TetrisLayout.bufferY, 1 / t.scale,
                                     TetrisLayout.boardBottomY - TetrisLayout.bufferY)), with: line)
        }
        for row in 1..<TetrisGame.visibleRows {
            let y = TetrisLayout.boardTopY + CGFloat(row) * TetrisLayout.cell
            context.fill(Path(t.rect(TetrisLayout.boardX, y, TetrisLayout.boardWidth, 1 / t.scale)), with: line)
        }
    }

    /// 칸 하나. 인접한 칸과는 **1pt 틈**으로 갈린다(테두리를 그리면 칸마다 도형이 하나 더 는다).
    private func drawCell(_ context: inout GraphicsContext, t: MiniGameProjection,
                          row: Int, column: Int, color: Color, opacity: Double, highlight: Bool = true) {
        let logical = TetrisLayout.cellRect(row: row, column: column).insetBy(dx: 0.5, dy: 0.5)
        let rect = t.rect(logical)
        context.fill(Path(roundedRect: rect, cornerRadius: 1.5 * t.scale), with: .color(color.opacity(opacity)))
        guard highlight else { return }
        // 윗변 띠 — 덩어리에 두께를 준다. 사각형 **안쪽**으로만 그린다(밖으로 나가면 틈이 사라진다).
        context.fill(Path(t.rect(logical.minX, logical.minY, logical.width, 2.5)),
                     with: .color(TetrisPalette.cellHighlight.opacity(opacity)))
    }

    /// 홀드·넥스트 상자 하나(61×44). 미리보기 조각은 상자 안 **가운데**에 놓는다.
    private func drawSlot(_ context: inout GraphicsContext, t: MiniGameProjection, rect: CGRect,
                          piece: TetrisGame.Piece?, stage: MiniGameStage, emphasized: Bool, spent: Bool) {
        let box = t.rect(rect)
        context.fill(Path(roundedRect: box, cornerRadius: 6 * t.scale),
                     with: .color(.white.opacity(0.05)))
        let border: Color = spent ? CheckTheme.danger.opacity(0.35)
            : (emphasized ? stage.glow.opacity(0.45) : CheckTheme.border)
        context.stroke(Path(roundedRect: box, cornerRadius: 6 * t.scale), with: .color(border), lineWidth: 1)
        guard let piece else { return }

        // 스폰 모양의 바운딩 상자만 잘라 쓴다: I = 4×1 · O = 2×2 · 나머지 3×2. 미니셀 9 를 곱하면
        // 각각 36×9 · 18×18 · 27×18 이라 61×44 상자 안에 넉넉히 든다.
        let cells = TetrisGame.shape(piece, .spawn)
        let minX = cells.map(\.dx).min() ?? 0
        let maxX = cells.map(\.dx).max() ?? 0
        let minY = cells.map(\.dy).min() ?? 0
        let maxY = cells.map(\.dy).max() ?? 0
        let width = CGFloat(maxX - minX + 1) * TetrisLayout.miniCell
        let height = CGFloat(maxY - minY + 1) * TetrisLayout.miniCell
        let originX = rect.midX - width / 2
        let originY = rect.midY - height / 2
        // 소진 표시는 **불투명도**다(조각 0.35 + 위험색 테두리) — 회색으로 칠하면 어떤 조각이었는지 사라진다.
        let alpha = spent ? TetrisPalette.spentOpacity : 1
        for cell in cells {
            let logical = CGRect(x: originX + CGFloat(cell.dx - minX) * TetrisLayout.miniCell,
                                 y: originY + CGFloat(cell.dy - minY) * TetrisLayout.miniCell,
                                 width: TetrisLayout.miniCell, height: TetrisLayout.miniCell)
                .insetBy(dx: 0.5, dy: 0.5)
            context.fill(Path(roundedRect: t.rect(logical), cornerRadius: 1.5 * t.scale),
                         with: .color(TetrisPalette.color(piece).opacity(alpha)))
        }
    }

    // MARK: HUD 글자

    /// 글자 겹. **글꼴 크기에는 배율을 곱하지 않는다** — 저장소의 두 게임이 그렇게 돼 있다
    /// (`MiniGameTimingBar` 의 헤더: 폰트 11 고정 + 프레임만 `* projection.scale`). 여기 숫자는 전부 실제 pt 다.
    private var hud: some View {
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
                place(t, CGRect(x: TetrisLayout.outerMargin, y: TetrisLayout.stageChipY,
                                width: TetrisLayout.columnWidth, height: TetrisLayout.stageChipHeight)) {
                    MiniGameStageChip(stage: stage)
                }
                statBlock(t, captionY: TetrisLayout.levelCaptionY, valueY: TetrisLayout.levelValueY,
                          caption: "레벨", value: String(game.scoreLevel))
                statBlock(t, captionY: TetrisLayout.linesCaptionY, valueY: TetrisLayout.linesValueY,
                          caption: "줄", value: String(game.lines))
                band(t)
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

    /// 레벨·줄 한 벌(캡션 8pt + 값 14pt heavy). **값은 15pt 이상으로 키우지 마라** —
    /// 옆 열 폭이 논리 61(실제 71.86)이고 14pt heavy monospacedDigit 7자리가 이미 66.91pt 다.
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
                // String(...) — 보간(`Text("\(value)")`)은 로캘 자리수 구분을 붙인다. 이 창의 표기 규약은
                // "구분 없는 평문 숫자"다(MiniGamePanel.gameFooter 주석).
                Text(value)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(CheckTheme.primaryText)
            }
        }
    }

    /// 하단 밴드: 왼쪽 점수 · 오른쪽 B2B/콤보 캡슐.
    ///
    /// **라운드 토큰 만료 경고는 아직 없다.** 스펙은 이 밴드의 오른쪽 끝을 그 자리로 잡아 두었지만, 띄우려면
    /// 스토어가 `MiniGameRoundStartResponse.expiresAt`(지금 디코드만 하고 아무도 안 들고 있다)을 기기 시계
    /// 보정까지 해서 쥐어야 한다 — 이번 화면 작업의 범위 밖이라 **붙이지 않았고, 자리도 비워 두지 않았다**
    /// (안 쓰는 자리를 비워 두면 B2B·콤보가 가운데로 몰려 보인다). 나중에 붙일 때는 이 `HStack` 맨 뒤에
    /// 더하고, 그때 두 캡슐이 그만큼 왼쪽으로 밀리는 것을 실측으로 확인해라.
    private func band(_ t: MiniGameProjection) -> some View {
        place(t, CGRect(x: TetrisLayout.textMinX, y: TetrisLayout.bandY,
                        width: TetrisLayout.textMaxX - TetrisLayout.textMinX, height: TetrisLayout.bandHeight)) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("점수")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(CheckTheme.secondaryText)
                Text(String(game.score))
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(CheckTheme.primaryText)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if game.backToBack >= 1 {
                    chip("B2B ×\(game.backToBack)", tint: CheckTheme.pending)
                }
                if game.combo >= 1 {
                    chip("콤보 \(game.combo)", tint: stage.glow)
                }
            }
        }
    }

    private func chip(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(tint)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(tint.opacity(0.18)))
            .overlay(Capsule().stroke(tint.opacity(0.45), lineWidth: 1))
            .fixedSize()
    }

    /// 논리 사각형 자리에 글자를 앉힌다. **폭·높이만** 배율을 먹고 글꼴은 실제 pt 그대로다.
    private func place<V: View>(_ t: MiniGameProjection, _ rect: CGRect,
                                @ViewBuilder _ content: () -> V) -> some View {
        content()
            .frame(width: rect.width * t.scale, height: rect.height * t.scale, alignment: .leading)
            .position(x: t.x(rect.midX), y: t.y(rect.midY))
    }

    // MARK: 판정 팝

    /// 소거·스핀 판정을 판 위에 띄운다. 하단 밴드가 아니라 **`MiniGameScorePop`** 인 이유:
    /// 밴드는 21pt 한 줄이라 순간 판정과 상시 표시(점수·콤보)가 자리를 다툰다. 순간 판정은 눈이 가 있는
    /// 곳(판)에 떠야 읽힌다 — 두 게임이 같은 결론으로 이 뷰를 쓴다.
    @ViewBuilder
    private var clearPop: some View {
        if let clear = game.lastClear, clear.points > 0,
           game.elapsed - clear.at < Self.popHold {
            GeometryReader { geo in
                let t = MiniGameProjection(container: geo.size, logicalSize: TetrisLayout.logicalSize)
                MiniGameScorePop(text: "+" + String(clear.points),
                                 caption: Self.verdict(clear),
                                 tint: stage.glow,
                                 reduceMotion: host.reduceMotion)
                    .id(clear.at)
                    .position(x: t.x(TetrisLayout.boardX + TetrisLayout.boardWidth / 2),
                              y: t.y(TetrisLayout.boardTopY + 58))
            }
            .allowsHitTesting(false)
        }
    }

    /// 판정 팝이 화면에 머무는 시간(판 시계). 줄소거 정지(0.500초)보다 길어야 소거가 끝나기 전에 사라지지 않는다.
    static let popHold: TimeInterval = 0.80

    /// 판정 이름. nil 이면 캡션 없이 점수만 뜬다(평범한 1~3줄 소거).
    static func verdict(_ clear: TetrisGame.ClearEvent) -> String? {
        if clear.perfectClear { return "퍼펙트 클리어" }
        let names = [1: "싱글", 2: "더블", 3: "트리플", 4: "테트리스"]
        switch clear.spin {
        case .full: return "T-스핀 " + (names[clear.lines] ?? "")
        case .mini: return "T-스핀 미니"
        case .none: return clear.lines == 4 ? "테트리스!" : nil
        }
    }

    // MARK: 시작 · 결과 카드

    /// 세 게임이 **같은** `MiniGameOverlayCard` 를 쓴다(색·글씨 통일 — 2026-09-08 지적).
    ///
    /// 행동 알약에 전체 조작(`MiniGameKind.tetris.controlHint` = "← → 이동 · ↑ 회전 · …")을 넣지 않는다.
    /// 그 알약은 한 줄짜리 자리이고, 여기서 필요한 것은 "지금 무엇을 누르면 되는가" 하나다 — 전체 조작은
    /// 창 하단 스트립이 상시로 보여 준다(`gameFooter` 가 `store.miniGameKind.controlHint` 를 그린다).
    /// 정적 `MiniGameKind.controlHint`("클릭 또는 스페이스")는 **여기서 절대 쓰지 마라** — 테트리스에
    /// 틀린 안내가 나가고, 소스 계약 테스트가 그 호출을 빨갛게 만든다.
    @ViewBuilder
    private var overlayCard: some View {
        switch game.phase {
        case .ready:
            MiniGameOverlayCard(
                title: MiniGameKind.tetris.title,
                subtitle: MiniGameKind.tetris.howToPlay,
                action: "스페이스로 시작",
                icon: MiniGameKind.tetris.icon,
                tint: stage.glow
            )
        case .result:
            MiniGameOverlayCard(
                title: String(game.score) + "점",
                titleIsScore: true,
                subtitle: game.score > host.bestScore ? "신기록!" : "최고 " + String(host.bestScore),
                subtitleIsHighlighted: game.score > host.bestScore,
                action: "스페이스로 다시",
                icon: MiniGameKind.tetris.icon,
                tint: stage.glow
            )
        case .running, .lineClear, .are, .over:
            EmptyView()
        }
    }
}
