import SwiftUI
import CheckCore

// 아잉 뒤집기 — **규칙 창**(줄 목록 = 순수 값 `ReversiRulesOverlayLines` + 예시 판 네 장). 계약은 설계서 FLIP/SPEC.md §5.7.
// 줄 목록은 체스식(시험이 값으로 되묻도록 뷰 밖에 둔다), 예시 판은 오목식(작은 판을 그대로 그린다).
// 보통명칭 '리버시'는 **설명으로만** 쓴다(8번 줄) — 등록 상표 이름은 화면·코드 어디에도 쓰지 않는다(DEC:23).
// 툴팁만으로 설명하지 않는다 — 전부 글자와 그림이다.

/// 규칙 줄(순서·뜻 고정 — SPEC §5.7 의 1~8). 시험이 번호로 집는다.
enum ReversiRulesOverlayLines {
    static let all: [String] = [
        "흑이 먼저 둬요. 가운데 네 칸에 흑 둘·백 둘을 엇갈려 놓고 시작해요.",
        "상대 돌을 내 돌 사이에 끼우도록 두면 끼인 돌이 모두 내 색으로 뒤집혀요. 가로·세로·대각선 여러 줄이 한 번에 뒤집힐 수 있어요.",
        "하나도 못 뒤집는 칸에는 둘 수 없어요. 둘 수 있는 칸은 점으로 보여요.",
        "둘 곳이 없으면 차례가 저절로 넘어가요. 둘 곳이 있으면 넘길 수 없어요.",
        "둘 다 둘 곳이 없으면 끝나요. 돌이 많은 쪽이 이기고, 남은 빈칸은 이긴 쪽 점수에 더해요. 같으면 32 : 32 무승부예요.",
        "한 수에 \(Int(ReversiText.turnSeconds))초. 넘기면 둘 수 있는 칸 가운데 하나에 저절로 놓여요. 연달아 3번 저절로 놓이면 져요.",
        // 판돈 줄 — 체스·오목과 같은 문구(수수료 0 · 무승부 환불).
        "수락하는 순간 두 사람 모두 판돈을 걸어요. 이기면 판돈만큼 더 받고, 무승부면 건 판돈을 돌려받아요.",
        "리버시와 같은 규칙이에요. 리버시를 알면 따로 배울 것이 없어요."
    ]
}

/// 규칙 창의 예시 판 한 장(순수 값). 판·점·고리를 **규칙 코어로 계산**해 만든다 — 손으로 적은 그림이 규칙과 어긋나지 않게.
struct ReversiRuleExample: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let board: ReversiBoard
    /// 점(그 장면에서 둘 수 있는 칸).
    var dots: Set<Int> = []
    /// 방금 둔 돌(빨간 점).
    var lastStone: Int? = nil
    /// 방금 뒤집힌 돌(주황 고리).
    var flipped: Set<Int> = []

    static var all: [ReversiRuleExample] {
        var examples: [ReversiRuleExample] = []

        // ① 시작 — 흑 차례 합법 수 네 칸(d3 · c4 · f5 · e6).
        let start = ReversiBoard.start
        examples.append(ReversiRuleExample(
            id: "start", title: "흑이 먼저", detail: "점이 흑이 둘 수 있는 칸이에요",
            board: start, dots: Set(ReversiRules.legalMoves(start, color: .black))))

        // ② 여러 줄이 한 번에 — c3 에 흑을 두면 가로·세로·대각 세 방향이 함께 뒤집힌다(코퍼스 B02).
        if let before = ReversiBoard(string: "...................wwb...www......b.w........w........b........."),
           case .success(let outcome) = ReversiRules.play(before, color: .black, idx: 18) {
            examples.append(ReversiRuleExample(
                id: "lines", title: "여러 줄이 한 번에", detail: "c3에 두면 주황 고리 돌이 모두 흑이 돼요",
                board: outcome.board, lastStone: 18, flipped: Set(outcome.flipped)))
        }

        // ③ 넘김 — 흑은 둘 곳이 없어(백 a1 은 모서리) 백 차례가 이어진다(코퍼스 E02).
        if let pass = ReversiBoard(string: "wb" + String(repeating: ".", count: 62)) {
            examples.append(ReversiRuleExample(
                id: "pass", title: "둘 곳이 없으면 넘김", detail: "흑은 둘 곳이 없어 백 차례가 이어져요",
                board: pass, dots: Set(ReversiRules.legalMoves(pass, color: .white))))
        }

        // ④ 끝과 점수 — 둘 다 둘 곳이 없다. 빈칸은 이긴 쪽 몫(코퍼스 E05).
        if let end = ReversiBoard(string: "bbb" + String(repeating: ".", count: 53) + "w......."),
           let score = ReversiRules.score(end) {
            examples.append(ReversiRuleExample(
                id: "end", title: "끝과 점수",
                detail: "둘 다 못 두면 끝 · 빈칸은 이긴 쪽 몫 (\(score.black) : \(score.white))",
                board: end))
        }
        return examples
    }
}

/// 규칙 보기. 리버시 표준(WOF)을 **사용자 어휘**로 줄여 적는다 — 진단·규격 번호는 싣지 않는다.
struct ReversiRulesOverlay: View {
    let onClose: () -> Void

    var body: some View {
        ZStack {
            // 불투명에 가까운 바닥 — 판 위에서 규칙을 읽는 동안 뒤 화면이 비치면 글자가 안 읽힌다.
            CheckTheme.panelElevated.opacity(0.93)
                .contentShape(Rectangle())
                .onTapGesture { onClose() }
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Label(ReversiText.rulesTitle, systemImage: "book.fill")
                        .font(.title3.weight(.bold))
                    Spacer()
                    ChessActionButton(title: ReversiText.close, icon: "xmark", style: .outline, height: 30,
                                      action: onClose)
                        .keyboardShortcut(.cancelAction)
                }
                HStack(alignment: .top, spacing: 26) {
                    VStack(alignment: .leading, spacing: 11) {
                        ForEach(Array(ReversiRulesOverlayLines.all.enumerated()), id: \.offset) { index, line in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("\(index + 1)")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(CheckTheme.accent)
                                    .frame(width: 18, height: 18)
                                    .background(Circle().fill(CheckTheme.accent.opacity(0.18)))
                                Text(line)
                                    .font(.callout)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .frame(width: 430, alignment: .leading)
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.fixed(ReversiWindowLayout.rulesExampleSide), spacing: 22),
                                       count: 2),
                        alignment: .leading, spacing: 16
                    ) {
                        ForEach(ReversiRuleExample.all) { example in
                            exampleTile(example)
                        }
                    }
                }
            }
            .padding(26)
            .frame(width: ReversiWindowLayout.rulesWidth)
            .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(CheckTheme.panel))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(CheckTheme.border, lineWidth: 1))
        }
        .frame(width: ReversiWindowLayout.contentSize.width, height: ReversiWindowLayout.contentSize.height)
    }

    private func exampleTile(_ example: ReversiRuleExample) -> some View {
        let side = ReversiWindowLayout.rulesExampleSide
        return VStack(alignment: .leading, spacing: 6) {
            ReversiBoardView(
                board: example.board,
                geometry: ReversiBoardGeometry(side: side),
                legalTargets: example.dots,
                lastStoneIdx: example.lastStone,
                flippedMarks: example.flipped,
                showsCoordinates: false
            )
            Text(example.title)
                .font(.callout.weight(.bold))
                .foregroundStyle(CheckTheme.accent)
            Text(example.detail)
                .font(.caption2)
                .foregroundStyle(CheckTheme.secondaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(height: 28, alignment: .top)
        }
        .frame(width: side, alignment: .leading)
    }
}
