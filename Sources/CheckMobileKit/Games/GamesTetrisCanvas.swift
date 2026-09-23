#if os(iOS)
import CheckCore
import SwiftUI

// 테트리스 한 프레임의 그림 — 맥 `Sources/check/MiniGameTetris.swift` 의 `TetrisGameView` 그리기를 옮겼다.
// 배치·색은 **옮기지 않았다**: `TetrisLayout`·`TetrisPalette` 가 코어(`Sources/CheckCore/TetrisLayout.swift`)에
// 한 벌로 있고 맥과 폰이 그 한 벌을 같이 읽는다. 그래서 같은 판의 스크린샷 둘은 픽셀이 같아야 한다.
//
// ── 맥과 다른 점은 딱 셋이다 ──────────────────────────────────────────────────────────────
// ① **글꼴에 배율을 곱한다.** 맥은 안 곱한다(`MiniGameTetris.swift` 의 hud 주석: "여기 숫자는 전부 실제 pt").
//    폰 캔버스의 관용구는 곱하는 쪽이다(`GamesTimingBarCanvas.overlay` 의 `11 * scale`,
//    `GamesFlappyCanvas` 의 `26 * t.scale`) — 판이 커진 만큼 글자도 커져야 같은 그림이 된다.
// ② **8pt 캡션 셋을 안 그린다.** 맥의 좌열 '레벨'(levelCaptionY 213) · '줄'(linesCaptionY 248) ·
//    하단 밴드의 '점수' 가 그것이다. 곱해도 8 × 1.1747(SE) = 9.40pt 라 iOS 캡션 하한 10pt 를 SE·15 에서 못 넘는다.
//    키울 수도 없다: `captionHeight` 9 이고 `levelCaptionY` 213 + 9 = 222 = `levelValueY` 라 캡션 상자 바닥이
//    값 상자 꼭대기와 붙어 있어 키우는 순간 겹친다. 그래서 **값 자리를 자기설명형**으로 바꿨다 —
//    levelValueY 에 "Lv 7" · linesValueY 에 "12줄" · 밴드 왼쪽은 숫자만.
//    남는 글꼴 기준값: 라벨 10 · 값 14 · 칩 10(전부 × scale).
// ③ **키보드가 없다.** 맥의 `TetrisKeyWatchdog`·`syncHeldKeys`·`input.actionCount` 관찰은 안 가져왔다.
//    폰 입력(끌기·탭·버튼)은 `GamesPlayController` 가 들고 있고 이 뷰는 **그림만** 그린다 —
//    두 게임 캔버스와 같은 계약이다(`game` · `bestScore` · `reduceMotion` 셋만 받는다).
//
// ── 그대로 지킨 금지 셋(맥 파일 머리 주석) ────────────────────────────────────────────────
// · `addFilter`·`drawLayer` 금지 — 60Hz 에서 캔버스를 흐리면 통합 GPU 에서 프레임이 깨진다.
//   우물 뒤의 부드러운 빛은 `MiniGameEffects.glow`(radialGradient) 하나다.
// · 배경은 **하늘만**(`terrain: false`) — 능선은 캔버스 아래쪽을 밝게 채우는데 거기가 하단 밴드 자리라
//   글자와 겹친다. 게다가 테트리스 판은 가로로 안 흐르므로 정지한 능선은 그냥 밝은 띠다.
// · 겹은 넷뿐이다(캔버스 · HUD 글자 · 판정 팝 · 카드). **여기에 겹을 더하지 마라.**
// · SwiftUI 반복 애니메이션(`repeatForever`) 금지 — 값만 내려서는 안 멈춘다.
//
// ── reduceMotion (설계 J) ─────────────────────────────────────────────────────────────────
// **끈다**: 판정 팝의 확대·상승(`GamesScorePop(reduceMotion:)`) · 무대 배경 연출
// (`MiniGameBackdrop.draw(…, reduceMotion:)`).
// **끄지 않는다**: 떨어지는 조각(게임 자체다) · 고스트(모양이지 움직임이 아니다) · 무대 전환(배경 교체다).
// 하드드롭 흔들림·잔상은 **애초에 만들지 않았다** — 맥에도 없고, 없으면 분기도 필요 없다.
// 줄소거 강조도 맥에 없어서 안 만들었다(만든다면 깜빡임이 아니라 정지한 밝기여야 한다 — 설계 J).
//
// ── 소스 계약(다음 사람이 `IntegrationContractTests.code(...)` 로 잴 문자열) ───────────────
// 이 파일은 `#if os(iOS)` 안이라 macOS `swift test` 가 **컴파일하지 않는다.** 그래서 모양은 소스 텍스트로만
// 잰다. 경로는 "Sources/CheckMobileKit/Games/GamesTetrisCanvas.swift" 이고, 계약인 문자열은 이렇다:
//
//   [있어야 한다]
//     "TetrisLayout."            — 폰 전용 배치 상수를 새로 만들지 않았다(코어 표 한 벌을 읽는다)
//     "TetrisPalette."           — 조각 색도 한 벌
//     "MiniGameStage.forTetrisAdvance(game.advance)"  — 무대 인자는 advance 다(줄 수가 아니다)
//     "terrain: false"           — 배경은 하늘만
//     "reduceMotion: reduceMotion" — 배경 연출과 판정 팝 둘 다에 내려간다(정확히 2회)
//     "* t.scale"(12회) · "* scale"(4회) — 글꼴에 배율을 곱한다(①). ⚠️ "* scale" 만 찾으면
//                                  "14 * t.scale" 은 안 걸린다(사이에 `t.` 가 있다) — 둘 다 세라.
//     "\"Lv \" + String(game.scoreLevel)" · "String(game.lines) + \"줄\"" — 자기설명형 값(②)
//     "GamesOverlayCard"         — 카드는 폰 공용 부품
//     "GamesStageChip"           — 무대 칩도 폰 공용 부품
//     "GamesScorePop"            — 판정 팝도 폰 공용 부품
//     "MiniGameProjection"       — 논리 → 실제 투영은 공용 껍데기 하나
//
//   [없어야 한다]
//     "addFilter" · "drawLayer" · ".blur("  — blur 금지
//     "terrain: true"            — 능선 금지
//     "1.0 / 60.0" · "Timer" · "CACurrentMediaTime" — 프레임 루프는 화면(TimelineView)이 돈다
//     "repeatForever"            — 안 멈추는 애니메이션 금지
//     "TetrisKeyWatchdog" · "syncHeldKeys" · "setLeftHeld" · "setSoftDropHeld" — 폰엔 키보드가 없다(③)
//     "size: 8" · "size: 9"      — iOS 캡션 하한 10pt 아래 글꼴 금지(②)
//     "MiniGameKind.controlHint" — 정적 멤버를 쓰면 테트리스에 "클릭 또는 스페이스"가 나간다
//     "struct TetrisLayout" · "enum TetrisLayout" — 폰 전용 배치 타입 금지

/// 테트리스 캔버스(우물·조각·홀드/넥스트 + 글자층 · 판정 팝 · 카드). 두 게임 캔버스와 같은 서명이다.
struct GamesTetrisCanvas: View {
    let game: TetrisGame
    let bestScore: Int
    let reduceMotion: Bool

    /// 판정 팝이 화면에 머무는 시간(판 시계). 줄소거 정지(0.500초)보다 길어야 소거가 끝나기 전에 사라지지 않는다.
    /// 맥 `TetrisGameView.popHold` 와 같은 값이다.
    static let popHold: TimeInterval = 0.80

    private var stage: MiniGameStage { MiniGameStage.forTetrisAdvance(game.advance) }

    var body: some View {
        // 바깥 모서리 자르기는 **화면이 한다**(`GamesMiniGameScreen.canvas` 의 clipShape 14) — 두 게임 캔버스와 같다.
        ZStack {
            Canvas(rendersAsynchronously: false) { context, size in
                draw(&context, size: size)
            }
            hud
            clearPop
            overlayCard
        }
    }

    // MARK: 캔버스

    private func draw(_ context: inout GraphicsContext, size: CGSize) {
        let t = MiniGameProjection(container: size, logicalSize: TetrisLayout.logicalSize)
        let full = CGRect(origin: .zero, size: size)
        let stage = self.stage

        // 1) 하늘 — 논리 사각형이 아니라 **캔버스 전체**를 덮는다(레터박스 0.11pt 까지).
        MiniGameBackdrop.draw(into: &context, rect: full, stage: stage, scroll: 0,
                              terrain: false, reduceMotion: reduceMotion)

        // 2) 우물 뒤 후광 — blur 가 아니라 radialGradient 하나다.
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

    /// 글자 겹. 맥과 **같은 자리**(TetrisLayout 의 논리 좌표)에 앉히되 글꼴에는 배율을 곱한다.
    private var hud: some View {
        GeometryReader { geo in
            let t = MiniGameProjection(container: geo.size, logicalSize: TetrisLayout.logicalSize)
            ZStack(alignment: .topLeading) {
                place(t, CGRect(x: TetrisLayout.textMinX, y: TetrisLayout.labelY,
                                width: TetrisLayout.columnWidth, height: TetrisLayout.labelHeight)) {
                    label("홀드", scale: t.scale)
                }
                place(t, CGRect(x: TetrisLayout.rightColumnX, y: TetrisLayout.labelY,
                                width: TetrisLayout.columnWidth, height: TetrisLayout.labelHeight)) {
                    label("다음", scale: t.scale)
                }
                place(t, CGRect(x: TetrisLayout.outerMargin, y: TetrisLayout.stageChipY,
                                width: TetrisLayout.columnWidth, height: TetrisLayout.stageChipHeight)) {
                    GamesStageChip(stage: stage, scale: t.scale)
                }
                // 맥은 여기에 캡션('레벨'·'줄') + 값 두 줄을 그린다. 폰은 **값 한 줄**이고 값이 스스로 말한다.
                statValue(t, valueY: TetrisLayout.levelValueY, text: "Lv " + String(game.scoreLevel))
                statValue(t, valueY: TetrisLayout.linesValueY, text: String(game.lines) + "줄")
                band(t)
            }
            .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
        }
        .allowsHitTesting(false)
    }

    /// '홀드'·'다음' 라벨. 맥은 9pt 지만 폰은 10pt 하한을 지킨다(곱하기 전 기준값이 10 이다).
    private func label(_ text: String, scale: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 10 * scale, weight: .bold))
            .foregroundStyle(CheckTheme.secondaryText)
    }

    /// 레벨·줄 값 한 줄. 맥의 `statBlock`(캡션 8 + 값 14)에서 **캡션을 걷어내고** 값을 자기설명형으로 바꾼 것이다.
    ///
    /// 폭 검산: 값 상자가 논리 61 이고 글꼴이 논리 14 다(맥은 실제 71.86 안의 실제 14 라 여유가 더 컸다).
    /// 14pt heavy monospacedDigit 한 자리가 9.56pt 이므로 "Lv 29" ≈ 39pt · "1234줄" ≈ 52pt 로 61 안에 든다.
    /// 그보다 긴 값(다섯 자리 줄 수)은 **판이 15분 상한이라 나올 수 없지만**, 나와도 잘리지 않게 줄여 앉힌다.
    private func statValue(_ t: MiniGameProjection, valueY: CGFloat, text: String) -> some View {
        place(t, CGRect(x: TetrisLayout.textMinX, y: valueY,
                        width: TetrisLayout.columnWidth, height: TetrisLayout.valueHeight)) {
            // String(...) — 보간(`Text("\(value)")`)은 로캘 자리수 구분을 붙인다. 이 창의 표기 규약은
            // "구분 없는 평문 숫자"다(맥 `MiniGamePanel.gameFooter` 주석).
            Text(text)
                .font(.system(size: 14 * t.scale, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(CheckTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    /// 하단 밴드: 왼쪽 점수(**숫자만**) · 오른쪽 B2B/콤보 캡슐.
    ///
    /// 맥은 여기 왼쪽에 8pt '점수' 캡션이 붙는다 — 폰에서는 그 8pt 가 하한 아래라 빼고 숫자만 둔다.
    /// 하단 밴드는 21pt 한 줄이라 순간 판정(판정 팝)과 상시 표시가 자리를 다투지 않게 여기엔 상시 값만 있다.
    private func band(_ t: MiniGameProjection) -> some View {
        place(t, CGRect(x: TetrisLayout.textMinX, y: TetrisLayout.bandY,
                        width: TetrisLayout.textMaxX - TetrisLayout.textMinX, height: TetrisLayout.bandHeight)) {
            HStack(alignment: .firstTextBaseline, spacing: 5 * t.scale) {
                Text(String(game.score))
                    .font(.system(size: 14 * t.scale, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(CheckTheme.primaryText)
                    .lineLimit(1)
                Spacer(minLength: 4 * t.scale)
                if game.backToBack >= 1 {
                    chip("B2B ×" + String(game.backToBack), tint: CheckTheme.pending, scale: t.scale)
                }
                if game.combo >= 1 {
                    chip("콤보 " + String(game.combo), tint: stage.glow, scale: t.scale)
                }
            }
        }
    }

    private func chip(_ text: String, tint: Color, scale: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 10 * scale, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(tint)
            .padding(.horizontal, 5 * scale)
            .padding(.vertical, 1 * scale)
            .background(Capsule().fill(tint.opacity(0.18)))
            .overlay(Capsule().stroke(tint.opacity(0.45), lineWidth: 1))
            .fixedSize()
    }

    /// 논리 사각형 자리에 글자를 앉힌다. 폭·높이는 배율을 먹고, 글꼴은 부르는 쪽이 이미 곱해 넘긴다.
    private func place<V: View>(_ t: MiniGameProjection, _ rect: CGRect,
                                @ViewBuilder _ content: () -> V) -> some View {
        content()
            .frame(width: rect.width * t.scale, height: rect.height * t.scale, alignment: .leading)
            .position(x: t.x(rect.midX), y: t.y(rect.midY))
    }

    // MARK: 판정 팝

    /// 소거·스핀 판정을 판 위에 띄운다. 하단 밴드가 아니라 판 위인 이유: 밴드는 21pt 한 줄이라 순간 판정과
    /// 상시 표시(점수·콤보)가 자리를 다툰다. 순간 판정은 눈이 가 있는 곳(판)에 떠야 읽힌다 — 세 게임이 같다.
    @ViewBuilder
    private var clearPop: some View {
        if let clear = game.lastClear, clear.points > 0,
           game.elapsed - clear.at < Self.popHold {
            GeometryReader { geo in
                let t = MiniGameProjection(container: geo.size, logicalSize: TetrisLayout.logicalSize)
                GamesScorePop(text: "+" + String(clear.points),
                              caption: Self.verdict(clear),
                              tint: stage.glow,
                              reduceMotion: reduceMotion,
                              scale: t.scale)
                    .id(clear.at)
                    .position(x: t.x(TetrisLayout.boardX + TetrisLayout.boardWidth / 2),
                              y: t.y(TetrisLayout.boardTopY + 58))
            }
            .allowsHitTesting(false)
        }
    }

    /// 판정 이름. nil 이면 캡션 없이 점수만 뜬다(평범한 1~3줄 소거).
    ///
    /// ⚠️ 맥 `TetrisGameView.verdict(_:)` 와 **같은 문장을 두 벌로** 들고 있다. 코어로 합치지 않은 이유는
    /// 이번 단계 범위가 이 파일 하나이기 때문이고, 합치려면 맥 잎 뷰와 그 호출을 읽는
    /// `Tests/checkTests/V0338TetrisMacTests.swift`(`TetrisGameView.verdict`)를 같이 옮겨야 한다.
    /// 그때까지는 **두 벌이 같은지 계약 테스트로 묶어라** — 한쪽만 고치면 맥과 폰의 판정 이름이 조용히 갈린다.
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

    /// 세 게임이 같은 부품(`GamesOverlayCard`)을 쓴다.
    ///
    /// 카드는 **가운데**다(맥과 같다) — 두 게임처럼 아래에 붙이면 하단 밴드(점수·B2B·콤보)를 덮는다.
    /// 배율은 판 배율의 0.82 배다: 맥 카드는 배율을 안 타는 실제 pt 라 344pt 판에서 논리 1/1.178 = 0.849 로
    /// 보인다. 0.82 는 그 크기의 3% 안이고, 두 게임 캔버스가 쓰는 값과도 같다.
    ///
    /// 조작 안내는 `GamesMiniGameText.howToPlay(.tetris)` 다. 여기에 **"탭해서 회전"이 반드시 들어가야 한다** —
    /// 시계 회전은 캔버스 탭이고(버튼은 반시계다) 화면 어디에도 그 사실을 말하는 자리가 이 카드뿐이다.
    /// 정적 `MiniGameKind.controlHint`("클릭 또는 스페이스")는 **여기서 절대 쓰지 마라** — 폰에 틀린 안내가 나간다.
    @ViewBuilder
    private var overlayCard: some View {
        GeometryReader { geo in
            let scale = MiniGameProjection(container: geo.size, logicalSize: TetrisLayout.logicalSize).scale
            Group {
                switch game.phase {
                case .ready:
                    GamesOverlayCard(
                        title: MiniGameKind.tetris.title,
                        subtitle: GamesMiniGameText.howToPlay(.tetris),
                        action: GamesMiniGameText.startAction,
                        icon: MiniGameKind.tetris.icon,
                        tint: stage.glow, scale: scale * 0.82)
                case .result:
                    GamesOverlayCard(
                        title: String(game.score) + "점",
                        titleIsScore: true,
                        subtitle: game.score > bestScore ? "신기록!" : "최고 " + String(bestScore),
                        subtitleIsHighlighted: game.score > bestScore,
                        action: GamesMiniGameText.againAction,
                        icon: MiniGameKind.tetris.icon,
                        tint: stage.glow, scale: scale * 0.82)
                case .running, .lineClear, .are, .over:
                    EmptyView()
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .allowsHitTesting(false)
    }
}
#endif
