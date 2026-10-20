#if os(iOS)
import CheckCore
import SwiftUI

// 폰 1:1 테트리스 **판 그림** — 내 판 한 장(`GamesTetrisDuelCanvas`)과 상대 미니 판(`GamesTetrisDuelMiniBoard`).
//
// 이 파일은 **그림만** 그린다. 솔로 캔버스(`GamesTetrisCanvas`)와 **같은 계약**이고, 받는 것은 값뿐이다
// (`game` · `reduceMotion` · `cells`). 입력·시계·배치 복제본은 여기 없다 — 프레임 루프는 화면의 `TimelineView` 가
// 돌고(`GamesTetrisDuelMatch.swift`), 판은 코어 스토어가 단조 시계로 민다(설계 D10).
//
// ── 맥 대결 창(`TetrisDuelPanel.TetrisDuelBoardView`)과 다른 점은 둘이다 ───────────────────────
// ① **글꼴에 배율을 곱한다.** 맥은 안 곱한다(실제 pt). 폰 캔버스의 관용구는 곱하는 쪽이고, 솔로 폰 캔버스가
//    먼저 그렇게 했다 — 판이 커진 만큼 글자도 커져야 같은 그림이 된다.
// ② **8pt 캡션 셋을 안 그린다.** 맥은 '레벨'·'줄' 캡션 + 값 두 줄인데, 8 × 1.1747(SE) = 9.40pt 라 iOS 캡션
//    하한 10pt 를 못 넘고 `captionHeight` 9 + `levelCaptionY` 213 = `levelValueY` 222 라 키우는 순간 값 상자와
//    겹친다(솔로 캔버스 머리 주석 ②와 같은 계산). 그래서 **값 자리를 자기설명형**으로 둔다 — "Lv 7" · "12줄".
//    하단 밴드의 '보낸 공격'·'들어올 줄'은 **10pt 라벨**이라 하한을 지킨다(그 둘은 숫자만으로는 못 읽는다 —
//    같은 자리에 두 숫자가 서고 하나는 내가 보낸 것, 하나는 나에게 올 것이다).
//
// ── 대결이 더하는 것 셋은 **전부 코어 painter 안에 있다** ─────────────────────────────────────
// 방해 줄 회색(`isGarbage`/`garbageMask`) · 우물 왼쪽 거터의 들어올 줄 미터(`drawMeter`) · 상대 미니 판
// (`drawMiniBoard`). **직접 칠하지 마라** — 회색이어야 하는 칸을 화면이 고르면 맥과 폰의 같은 판이 다르게 보인다.
//
// ── 그대로 지킨 금지 셋(솔로·맥 캔버스와 같다) ──────────────────────────────────────────────
// · `addFilter`·`drawLayer`·`.blur(` 금지 — 60Hz 에서 캔버스를 흐리면 통합 GPU 에서 프레임이 깨진다.
// · `repeatForever` 금지 — 값만 내려서는 안 멈춘다.
// · 배경은 **하늘만**(painter 가 `terrain: false` 로 그린다).
// · 배치·색은 코어 표 한 벌(`TetrisLayout` · `TetrisPalette` · `TetrisDuelPalette` · `TetrisMiniBoardLayout`)을
//   읽는다. 폰 전용 배치 타입을 새로 만들지 마라(`struct/enum TetrisLayout` 금지).
//
// ── reduceMotion ────────────────────────────────────────────────────────────────────────────
// painter 에 그대로 내려간다(무대 배경 연출만 끈다). 떨어지는 조각·고스트는 **게임 자체**라 끄지 않는다.
// 판정 팝(솔로의 `GamesScorePop`)은 **대결에 없다** — 맥 대결 창에도 없고, 점수가 아니라 공격이 승부라
// 같은 자리에 띄울 숫자가 다르다(밴드의 '보낸 공격' 이 그 일을 상시로 한다).
//
// ── 소스 계약(`GamesTetrisDuelMatchTests.theDuelCanvasOnlyDraws` 가 주석을 걷고 읽는다) ──────
//   [있어야 한다] "TetrisBoardPainter.drawGame" · "TetrisBoardPainter.drawMiniBoard" · "TetrisLayout."
//                "TetrisDuelPalette." · "reduceMotion: reduceMotion" · "* t.scale" · "TetrisPhoneText."
//   [없어야 한다] "addFilter" · "drawLayer" · ".blur(" · "repeatForever" · "TimelineView" · "Timer"
//                "CACurrentMediaTime" · "1.0 / 60.0" · "store." · "setLeftHeld" · "softDropOneCell"
//                "struct TetrisLayout" · "enum TetrisLayout" · "drawMeter" · "garbageMask" · "size: 8"

/// 내 판 한 장(코어 painter) + 글자 겹. 솔로 캔버스와 같은 서명 꼴이다 — **값만** 받는다.
struct GamesTetrisDuelCanvas: View {
    let game: TetrisGame
    let reduceMotion: Bool

    var body: some View {
        // 바깥 모서리 자르기는 **화면이 한다**(솔로와 같다 — 화면이 판 상자의 테두리·그림자를 쥔다).
        ZStack {
            Canvas(rendersAsynchronously: false) { context, size in
                // 미터·방해 줄 회색이 이 한 번의 호출 안에 있다. 여기에 덧칠을 더하지 마라.
                var canvas = context
                TetrisBoardPainter.drawGame(game, into: &canvas, size: size, reduceMotion: reduceMotion)
            }
            hud
        }
    }

    // MARK: 글자 겹

    /// 맥 대결 창과 **같은 자리**(TetrisLayout 논리 좌표)에 앉히되 글꼴에는 배율을 곱한다(머리말 ①).
    private var hud: some View {
        GeometryReader { geo in
            let t = MiniGameProjection(container: geo.size, logicalSize: TetrisLayout.logicalSize)
            ZStack(alignment: .topLeading) {
                place(t, CGRect(x: TetrisLayout.textMinX, y: TetrisLayout.labelY,
                                width: TetrisLayout.columnWidth, height: TetrisLayout.labelHeight)) {
                    label(TetrisPhoneText.holdLabel, scale: t.scale)
                }
                place(t, CGRect(x: TetrisLayout.rightColumnX, y: TetrisLayout.labelY,
                                width: TetrisLayout.columnWidth, height: TetrisLayout.labelHeight)) {
                    label(TetrisPhoneText.nextLabel, scale: t.scale)
                }
                // 레벨은 **난이도 레벨**이다(가속 바닥이 섞인 값 — 맥 대결 창과 같다). 점수 레벨은 대결에 뜻이 없다.
                statValue(t, valueY: TetrisLayout.levelValueY,
                          text: TetrisPhoneText.levelValue(game.difficultyLevel))
                statValue(t, valueY: TetrisLayout.linesValueY, text: TetrisPhoneText.linesValue(game.lines))
                band(t)
            }
            .shadow(color: .black.opacity(0.5), radius: 3, y: 1)
        }
        .allowsHitTesting(false)
    }

    /// '홀드'·'다음' 라벨. 곱하기 전 기준값이 10 이다(iOS 캡션 하한).
    private func label(_ text: String, scale: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 10 * scale, weight: .bold))
            .foregroundStyle(CheckTheme.secondaryText)
    }

    /// 레벨·줄 값 한 줄(자기설명형 — 머리말 ②).
    ///
    /// 폭 검산: 값 상자가 논리 61 이고 글꼴이 논리 14 다. 14pt heavy monospacedDigit 한 자리가 9.56pt 이므로
    /// "Lv 28" ≈ 39pt · "1234줄" ≈ 52pt 로 61 안에 든다(판 상한 480초라 더 긴 값은 나올 수 없다).
    private func statValue(_ t: MiniGameProjection, valueY: CGFloat, text: String) -> some View {
        place(t, CGRect(x: TetrisLayout.textMinX, y: valueY,
                        width: TetrisLayout.columnWidth, height: TetrisLayout.valueHeight)) {
            // String(...) — 보간은 로캘 자리수 구분을 붙인다. 이 판의 표기 규약은 "구분 없는 평문 숫자"다.
            Text(text)
                .font(.system(size: 14 * t.scale, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(CheckTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    /// 하단 밴드: 왼쪽 **보낸 공격**(내가 상대에게 보낸 누계) · 오른쪽 **들어올 줄**(미터와 같은 빨강 —
    /// 우물 왼쪽 막대가 무엇인지 글자로 한 번 말한다). 솔로의 점수·콤보 자리를 그대로 쓴다.
    private func band(_ t: MiniGameProjection) -> some View {
        place(t, CGRect(x: TetrisLayout.textMinX, y: TetrisLayout.bandY,
                        width: TetrisLayout.textMaxX - TetrisLayout.textMinX, height: TetrisLayout.bandHeight)) {
            HStack(alignment: .firstTextBaseline, spacing: 4 * t.scale) {
                Text(TetrisPhoneText.attackTitle)
                    .font(.system(size: 10 * t.scale, weight: .bold))
                    .foregroundStyle(CheckTheme.secondaryText)
                Text(String(game.attackSentTotal))
                    .font(.system(size: 14 * t.scale, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(CheckTheme.working)
                Spacer(minLength: 4 * t.scale)
                if game.pendingGarbageLines > 0 {
                    chip(TetrisPhoneText.incomingLines(game.pendingGarbageLines),
                         tint: TetrisDuelPalette.meterColor, scale: t.scale)
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
            .overlay(Capsule().stroke(tint.opacity(0.5), lineWidth: 1))
            .fixedSize()
    }

    /// 논리 사각형 자리에 글자를 앉힌다. 글꼴은 부르는 쪽이 이미 곱해 넘긴다.
    private func place<V: View>(_ t: MiniGameProjection, _ rect: CGRect,
                                @ViewBuilder _ content: () -> V) -> some View {
        content()
            .frame(width: rect.width * t.scale, height: rect.height * t.scale, alignment: .leading)
            .position(x: t.x(rect.midX), y: t.y(rect.midY))
    }
}

// MARK: - 상대 미니 판

/// 상대 판을 작게. **스냅숏이 올 때만 다시 그린다** — 이 뷰는 프레임 루프(`TimelineView`) **밖**에 서고
/// 받는 값(`cells`)은 보고 응답에서만 바뀌는 관찰 값(`match.opponentBoard`)이다.
///
/// 셀 변(pt)은 **순수 표가 쥔다**(`GamesTetrisDuelChrome.miniBoardCell` — 5pt. 고른 까닭과 검산은 그 주석에
/// 있다). 그 수가 판 폭을 깎고 판 폭이 곧 제스처 한 칸 문턱이라(P11) 맥 스위트가 값으로 재야 하기 때문이다 —
/// 여기 숫자를 다시 적지 마라.
struct GamesTetrisDuelMiniBoard: View {
    /// 한 칸 변(pt) — 표의 결론을 그대로 쓴다.
    static var cell: CGFloat { GamesTetrisDuelChrome.miniBoardCell }
    /// 이 판의 크기(코어 표가 셈한다 — 폰이 따로 세지 않는다).
    static var size: CGSize { TetrisMiniBoardLayout.boardSize(cell: cell) }

    let cells: [[TetrisDuelCell]]

    var body: some View {
        Canvas(rendersAsynchronously: false) { context, size in
            var canvas = context
            TetrisBoardPainter.drawMiniBoard(cells, into: &canvas, size: size, cell: Self.cell)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(TetrisPhoneText.opponentBoardLabel)
    }
}
#endif
