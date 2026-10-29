import Foundation

// 자리표시 — R 갈래가 채운다.
//
// 아잉 큐브(내부 이름 rummy) 규칙 코어. 선언 이름·시그니처는 설계서 §4.1 이 계약이다 — 바꾸지 마라
// (스토어·화면·시험이 이 이름으로 짜인다). 규칙 정본은 `rummy/research/rules.md` v1.1(R-01~R-24).
//
// ── 뼈대(K)에서 완성한 것 ──
//  · `RummyFace` 전부: R-01 면 표기 파싱·`text`·Codable(면 문자열 하나)·Comparable(R-09 비교 키 순)·`rackValue`·`joker`.
//  · `RummyTurnReason` 의 관대한 디코드(모르는 값 → `.unknown`). 와이어 `rejected{reason}` 가 이것을 쓴다 — 지우지 마라.
//  · `compareKey`(정렬)·`sameTable`(비교 키 다중집합)·`rackValue` 합 — 정의가 한 줄이라 그대로 두었다.
//
// ── 자리표시(R 갈래 몫) ──
//  · `analyze` → valid:false · `judgeTurn` → `.unknown` · `finalScores` → 0 · `payouts` → 0 배열·등수 1
//  · `displayOrder` → 받은 순서 그대로 · `newMeldPoints` → 0

// MARK: - 면

/// 타일 한 장의 면(R-01). 같은 면 두 장은 구별하지 않는다 — 끌기용 구별은 `RummyTile.id`(로컬) 몫이다.
package struct RummyFace: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    /// 0...3 = A...D. 조커는 nil.
    package let color: Int?
    /// 1...13. 조커는 nil.
    package let number: Int?

    package static let joker = RummyFace(rawColor: nil, rawNumber: nil)

    /// 색 글자(인덱스 = `color`).
    package static let colorLetters: [Character] = ["A", "B", "C", "D"]

    private init(rawColor: Int?, rawNumber: Int?) {
        color = rawColor
        number = rawNumber
    }

    /// R-01 정규식 `^([ABCD](1[0-3]|[1-9])|J)$` 에 맞을 때만 만든다.
    package init?(text: String) {
        if text == "J" {
            self = .joker
            return
        }
        let chars = Array(text)
        guard chars.count == 2 || chars.count == 3,
              let colorIndex = Self.colorLetters.firstIndex(of: chars[0]) else { return nil }
        let digits = chars.dropFirst()
        // 앞자리 0 없음 · 숫자만(부호·공백 금지).
        guard digits.allSatisfy({ $0.isASCII && $0.isNumber }), digits.first != "0",
              let value = Int(String(digits)), (1...13).contains(value) else { return nil }
        color = colorIndex
        number = value
    }

    /// 숫자 타일. 범위 밖 값은 부르는 쪽 실수다.
    package init(color: Int, number: Int) {
        precondition((0...3).contains(color) && (1...13).contains(number), "RummyFace 범위 밖: \(color) \(number)")
        self.color = color
        self.number = number
    }

    /// "A7" / "J".
    package var text: String {
        guard let color, let number else { return "J" }
        return "\(Self.colorLetters[color])\(number)"
    }

    package var isJoker: Bool { color == nil }

    /// 랙에 남았을 때 값(R-22): 숫자 또는 조커 30.
    package var rackValue: Int { number ?? 30 }

    package var description: String { text }

    // R-09 비교 키 순서: 색 A < B < C < D, 같은 색은 숫자 오름차순, 조커 맨 뒤.
    package static func < (lhs: RummyFace, rhs: RummyFace) -> Bool {
        switch (lhs.color, rhs.color) {
        case (nil, _): return false
        case (_, nil): return true
        case let (l?, r?):
            if l != r { return l < r }
            return (lhs.number ?? 0) < (rhs.number ?? 0)
        }
    }

    // Codable = 면 문자열 하나("A7"/"J"). 와이어·DB 모두 면 문자열이다(설계서 §1).
    package init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let face = RummyFace(text: raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "R-01 면 표기가 아니다: \(raw)")
        }
        self = face
    }

    package func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(text)
    }
}

// MARK: - 판정 값

package enum RummyMeldKind: String, Sendable { case run, group }

package struct RummyMeldAnalysis: Equatable, Sendable {
    package let valid: Bool
    package let kind: RummyMeldKind?
    package let points: Int?

    package init(valid: Bool, kind: RummyMeldKind?, points: Int?) {
        self.valid = valid
        self.kind = kind
        self.points = points
    }

    package static let invalid = RummyMeldAnalysis(valid: false, kind: nil, points: nil)
}

/// R-16 판정 이유 9개 + 모름. 원시값이 서버 `rummy_judge_turn` 반환 글자 그대로다.
package enum RummyTurnReason: String, Sendable, Codable, CaseIterable {
    case ok, malformed, jokerNotReused = "joker_not_reused", tableTileRemoved = "table_tile_removed", tileNotOwned = "tile_not_owned",
         noTilePlayed = "no_tile_played", invalidMeld = "invalid_meld", initialTableTouched = "initial_table_touched",
         initialUnder30 = "initial_under_30", unknown

    /// 모르는 값은 `.unknown` 으로 접는다(서버가 어휘를 넓혀도 응답 디코드가 죽지 않게). **지우지 마라.**
    package init(from decoder: any Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = RummyTurnReason(rawValue: raw) ?? .unknown
    }
}

/// payouts 입력 한 자리(§2.1).
package struct RummyPayoutSeat: Equatable, Sendable {
    package var active: Bool
    package var score: Int
    package var tiles: Int
    package var seat: Int
    package var forfeitOrder: Int?

    package init(active: Bool, score: Int, tiles: Int, seat: Int, forfeitOrder: Int? = nil) {
        self.active = active
        self.score = score
        self.tiles = tiles
        self.seat = seat
        self.forfeitOrder = forfeitOrder
    }
}

// MARK: - 규칙

package enum RummyRules {
    /// R-06~R-09 세트 판정. 자리표시.
    package static func analyze(_ meld: [RummyFace]) -> RummyMeldAnalysis {
        .invalid
    }

    /// R-09 비교 키: (색 A<B<C<D, 숫자 오름, J 맨 뒤) 정렬.
    package static func compareKey(_ meld: [RummyFace]) -> [RummyFace] {
        meld.sorted()
    }

    /// R-09 표시 순서(런은 조커 자리 포함). 자리표시 — 받은 순서 그대로.
    package static func displayOrder(_ meld: [RummyFace]) -> [RummyFace] {
        meld
    }

    /// K 다중집합 같음 — 판 위 세트 순서·세트 안 순서는 의미 없다(R-09).
    package static func sameTable(_ a: [[RummyFace]], _ b: [[RummyFace]]) -> Bool {
        guard a.count == b.count else { return false }
        func keys(_ table: [[RummyFace]]) -> [String] {
            table.map { compareKey($0).map(\.text).joined(separator: ",") }.sorted()
        }
        return keys(a) == keys(b)
    }

    /// R-16 차례 판정. 자리표시.
    package static func judgeTurn(
        initialDone: Bool, tableBefore: [[RummyFace]], rackBefore: [RummyFace], tableAfter: [[RummyFace]]
    ) -> RummyTurnReason {
        .unknown
    }

    /// 랙 값 합(조커 30).
    package static func rackValue(_ rack: [RummyFace]) -> Int {
        rack.reduce(0) { $0 + $1.rackValue }
    }

    /// R-22~R-24 끝 점수와 승자(0-기반 자리). 자리표시.
    package static func finalScores(racks: [[RummyFace]]) -> (scores: [Int], winners: [Int]) {
        (Array(repeating: 0, count: racks.count), [])
    }

    /// §2.1 등수별 분배. 자리표시.
    package static func payouts(seatCount: Int, stake: Int, seats: [RummyPayoutSeat]) -> (payouts: [Int], ranks: [Int]) {
        (Array(repeating: 0, count: seats.count), Array(repeating: 1, count: seats.count))
    }

    /// 첫 등록 진행 표시("18/30")용 새 세트 점수 합. 자리표시.
    package static func newMeldPoints(tableBefore: [[RummyFace]], tableAfter: [[RummyFace]]) -> Int {
        0
    }
}
