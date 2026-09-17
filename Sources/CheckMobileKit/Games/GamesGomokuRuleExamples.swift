import CheckCore
import Foundation

/// 규칙 보기 시트의 예시 국면 — 맥 `GomokuRuleExample`(Sources/check/GomokuPanel.swift)을 그대로 옮겼다.
/// **좌표는 조사 코퍼스에서 온 값**이고(`id` 가 코퍼스 케이스 번호) 기대 판정은 테스트가 코어 판정기로 되묻는다.
package struct GomokuPhoneRuleExample: Identifiable, Equatable, Sendable {
    /// 규칙 예시 판에 얹는 표시.
    package enum Mark: Equatable, Sendable {
        case forbidden, win, legal, pivot
    }

    package let id: String
    package let title: String
    package let detail: String
    package let black: [String]
    package let white: [String]
    package let point: String
    package let expected: GomokuJudgement
    package var pivot: String? = nil

    package var board: GomokuBoard {
        var board = GomokuBoard()
        for notation in black { if let p = GomokuPoint(notation: notation) { board[p] = .black } }
        for notation in white { if let p = GomokuPoint(notation: notation) { board[p] = .white } }
        return board
    }

    package var marks: [GomokuPoint: Mark] {
        var marks: [GomokuPoint: Mark] = [:]
        if let p = GomokuPoint(notation: point) {
            switch expected {
            case .win: marks[p] = .win
            case .forbidden: marks[p] = .forbidden
            default: marks[p] = .legal
            }
        }
        if let pivot, let p = GomokuPoint(notation: pivot) { marks[p] = .pivot }
        return marks
    }

    /// 여섯 예시 모두 H8 을 가운데로 둔 9×9(D..L × 4..12) 안에 들어온다.
    package static let cropOriginX = 3
    package static let cropOriginY = 3
    package static let cropLines = 9

    package static let all: [GomokuPhoneRuleExample] = [
        GomokuPhoneRuleExample(
            id: "K01", title: "3-3 금수", detail: "열린 3이 한꺼번에 두 개 생겨요",
            black: ["F8", "G8", "H6", "H7"], white: [], point: "H8",
            expected: .forbidden(.doubleThree)),
        GomokuPhoneRuleExample(
            id: "K12", title: "4-4 금수", detail: "막혀 있어도 4가 두 개면 금수예요",
            black: ["E8", "F8", "G8", "H9", "H10", "H11"], white: ["D8", "H12"], point: "H8",
            expected: .forbidden(.doubleFour)),
        GomokuPhoneRuleExample(
            id: "K19", title: "장목 금수", detail: "흑은 6개 이상 이을 수 없어요",
            black: ["E8", "F8", "G8", "I8", "J8"], white: [], point: "H8",
            expected: .forbidden(.overline)),
        GomokuPhoneRuleExample(
            id: "K24", title: "5목이 먼저", detail: "금수 모양이 함께 생겨도 5목이면 이겨요",
            black: ["D8", "E8", "F8", "G8", "H9", "H10", "I9", "J10"], white: [], point: "H8",
            expected: .win),
        GomokuPhoneRuleExample(
            id: "K28", title: "4-3은 괜찮아요", detail: "4 하나 + 3 하나는 둘 수 있어요",
            black: ["E8", "F8", "G8", "H9", "H10"], white: ["D8"], point: "H8",
            expected: .legal),
        GomokuPhoneRuleExample(
            id: "K34", title: "거짓 3", detail: "4로 만들 자리(주황)가 장목이라 가로는 3이 아니에요",
            black: ["G8", "J8", "I6", "I7", "I9", "I10", "I11", "H9", "H10"], white: [], point: "H8",
            expected: .legal, pivot: "I8")
    ]

    /// 설명 줄(맥과 같은 문장).
    package static let ruleLines: [String] = [
        "흑이 먼저 둬요. 가로·세로·대각선으로 5개를 먼저 이으면 이겨요.",
        "흑만 금수가 있어요 — 3-3, 4-4, 장목(6개 이상). 흑 차례엔 금수 자리에 X가 떠요.",
        "흑은 정확히 5개여야 이기고, 백은 5개 이상이면 이겨요.",
        "5목이 되는 수는 금수 모양이 함께 생겨도 흑의 승리예요. 4-3은 금수가 아니에요.",
        "한 수에 30초. 30초를 넘기면 무작위로 놓입니다 · 3번 연속이면 집니다.",
        "흑이 둘 곳이 없으면 차례가 백으로 넘어가고, 판이 가득 차면 무승부예요.",
        "수락하는 순간 두 사람 모두 판돈을 걸어요. 이기면 판돈만큼 더 받고, 무승부면 건 판돈을 돌려받아요."
    ]
}
