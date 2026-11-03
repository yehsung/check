import CheckCore
import Foundation
#if os(iOS)
import SwiftUI
#endif

// 폰 아잉 뒤집기 **규칙 시트**(로비 갈래 3/4) — 줄 목록(`ReversiPhoneText.rules`) + 예시 판 네 장. 본은 맥 `ReversiRulesOverlay`(줄 여덟 + 예시 넷)이고,
// 폰은 툴팁이 없어 두 줄(신청 유효 초 · 앱을 나가면)을 글자로 더했다. 숫자 셋은 **로비 응답 값**이다(상수를 베끼지 않는다).
// 시트의 주인은 화면 루트이고 코어 깃발 `isRulesVisible` 로 연다(로비·대국 화면의 책 버튼이 같은 깃발을 켠다 — 체스와 같은 관례).
// 보통명칭 '리버시'는 **설명으로만** 쓴다(마지막 줄) — 등록 상표 이름은 화면·코드 어디에도 쓰지 않는다.

/// 규칙 시트의 예시 판 한 장(순수 값). 판·점·고리를 **규칙 코어로 계산**해 만든다 — 손으로 적은 그림이 규칙과 어긋나지 않게(맥 `ReversiRuleExample` 과 같은 네 장).
package struct GamesReversiRuleExample: Identifiable, Equatable, Sendable {
    package let id: String
    package let title: String
    package let detail: String
    package let board: ReversiBoard
    /// 점(그 장면에서 둘 수 있는 칸).
    package var dots: Set<Int> = []
    /// 방금 둔 돌(빨간 점).
    package var lastStone: Int?
    /// 방금 뒤집힌 돌(주황 고리).
    package var flipped: Set<Int> = []

    package static var all: [GamesReversiRuleExample] {
        var examples: [GamesReversiRuleExample] = []

        // ① 시작 — 흑 차례 둘 수 있는 네 칸(d3 · c4 · f5 · e6).
        let start = ReversiBoard.start
        examples.append(GamesReversiRuleExample(
            id: "start", title: "흑이 먼저", detail: "점이 흑이 둘 수 있는 칸이에요",
            board: start, dots: Set(ReversiRules.legalMoves(start, color: .black))))

        // ② 여러 줄이 한 번에 — c3 에 흑을 두면 가로·세로·대각 세 방향이 함께 뒤집힌다.
        if let before = ReversiBoard(string: "...................wwb...www......b.w........w........b........."),
           case .success(let outcome) = ReversiRules.play(before, color: .black, idx: 18) {
            examples.append(GamesReversiRuleExample(
                id: "lines", title: "여러 줄이 한 번에", detail: "c3에 두면 주황 고리 돌이 모두 흑이 돼요",
                board: outcome.board, lastStone: 18, flipped: Set(outcome.flipped)))
        }

        // ③ 넘김 — 흑은 둘 곳이 없어(백 a1 은 모서리) 백 차례가 이어진다.
        if let pass = ReversiBoard(string: "wb" + String(repeating: ".", count: 62)) {
            examples.append(GamesReversiRuleExample(
                id: "pass", title: "둘 곳이 없으면 넘김", detail: "흑은 둘 곳이 없어 백 차례가 이어져요",
                board: pass, dots: Set(ReversiRules.legalMoves(pass, color: .white))))
        }

        // ④ 끝과 점수 — 둘 다 둘 곳이 없다. 빈칸은 이긴 쪽 몫.
        if let end = ReversiBoard(string: "bbb" + String(repeating: ".", count: 53) + "w......."),
           let score = ReversiRules.score(end) {
            examples.append(GamesReversiRuleExample(
                id: "end", title: "끝과 점수",
                detail: "둘 다 못 두면 끝 · 빈칸은 이긴 쪽 몫 (\(score.black) : \(score.white))",
                board: end))
        }
        return examples
    }
}

#if os(iOS)

/// 규칙 시트 — 문구 표의 줄을 번호와 함께 그리고, 그 아래 예시 판 네 장(두 칸씩). 닫기는 왼쪽 위 ✕ 하나(공용 `SheetHeader`).
struct GamesReversiRulesSheet: View {
    let turnSeconds: Int
    let lossStreak: Int
    let inviteTtlSeconds: Int

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let lines = ReversiPhoneText.rules(turnSeconds: turnSeconds, lossStreak: lossStreak, inviteTtlSeconds: inviteTtlSeconds)
        VStack(spacing: 0) {
            SheetHeader(ReversiPhoneText.rulesTitle, onClose: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: MobileTheme.space3) {
                    InsetGroup {
                        ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                            GroupRow(divider: index == lines.count - 1 ? .none : .inset(MobileTheme.cardPadding)) {
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Text("\(index + 1)")
                                        .font(.caption.weight(.bold))
                                        .monospacedDigit()
                                        .foregroundStyle(MobileTheme.accent)
                                        .frame(minWidth: 18)
                                        .accessibilityHidden(true)
                                    Text(line)
                                        .font(MobileTheme.rowSubtitle)
                                        .foregroundStyle(MobileTheme.label)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                    SectionHeader(ReversiPhoneText.rulesExamplesTitle, padded: true)
                    examples
                }
                .padding(.horizontal, MobileTheme.sideMargin)
                .padding(.vertical, MobileTheme.space3)
            }
        }
        .background(MobileTheme.background.ignoresSafeArea())
        .presentationDetents([.large])
    }

    /// 예시 판 — 보통 글자는 두 칸씩, 큰 글자는 한 칸씩(설명 두 줄이 낱글자로 꺾이지 않게).
    private var examples: some View {
        let columns = typeSize.isAccessibilitySize ? 1 : 2
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .top), count: columns),
                         alignment: .leading, spacing: 18) {
            ForEach(GamesReversiRuleExample.all) { example in
                GamesReversiRuleExampleTile(example: example)
            }
        }
    }
}

/// 예시 판 한 장 + 제목 + 설명. 판은 대국 판과 같은 그림(`GamesReversiBoardCanvas`)이고 뒤집힌 돌에만 주황 고리를 얹는다.
private struct GamesReversiRuleExampleTile: View {
    let example: GamesReversiRuleExample

    @State private var width: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            board
            Text(example.title)
                .font(MobileTheme.rowTitle)
                .foregroundStyle(MobileTheme.accent)
            Text(example.detail)
                .font(MobileTheme.rowSubtitle)
                .foregroundStyle(MobileTheme.label2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { proxy in proxy.size.width } action: { value in
            if value != width { width = value }
        }
        .accessibilityElement(children: .combine)
    }

    private var board: some View {
        // 첫 배치에서 폭을 아직 모르는 한 틱은 보통 크기(144)로 선다 — 8 로 그리면 판이 점처럼 번쩍였다 커진다.
        let side = width > 0 ? max(8, (min(width, 220) / 8).rounded(.down) * 8) : 144
        let geometry = GamesReversiBoardGeometry(side: side)
        return GamesReversiBoardCanvas(board: example.board, geometry: geometry, legalTargets: example.dots,
                                       lastStoneIdx: example.lastStone)
            .overlay {
                Canvas { context, _ in
                    let radius = geometry.cell * 0.46
                    for idx in example.flipped {
                        let center = geometry.center(idx: idx)
                        let ring = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius,
                                                          width: radius * 2, height: radius * 2))
                        context.stroke(ring, with: .color(MobileTheme.pending), lineWidth: max(1.5, geometry.cell * 0.09))
                    }
                }
                .frame(width: side, height: side)
                .allowsHitTesting(false)
            }
            .frame(width: side, height: side)
            .accessibilityHidden(true)
    }
}

#endif
