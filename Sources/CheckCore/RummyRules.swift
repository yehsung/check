import Foundation

// 아잉 큐브(내부 이름 rummy) 규칙 코어. 선언 이름·시그니처는 설계서 §4.1 이 계약이다 — 바꾸지 마라
// (스토어·화면·시험이 이 이름으로 짜인다). 규칙 정본은 `rummy/research/rules.md` v1.1(R-01~R-24),
// 판정은 파이썬 참조 구현 `rummy/research/reference.py` 를 줄 단위로 옮겼다(서버 `rummy_*` 판정 함수도 같은 것을 옮긴다).
// 기대값의 집은 `Tests/checkTests/Fixtures/rummy/cases.json`(154건) 과 설계서 §2.1 P01~P10 표 하나다 — 여기 숫자를 고치면
// 서버와 갈린다. 고칠 일이 생기면 코퍼스부터 고치고 양쪽을 같이 맞춰라.
//
// 다중집합(M·K)은 `[원소: 개수]` 사전이다. 빼기는 0 아래로 내려가지 않는다(R-16) — `minus` 가 0 이하 항목을 지운다.
// 판 형식 검사(R-16 0단계)의 "면 정규식" 절반은 `RummyFace(text:)` 가 맡는다: `[RummyFace]` 로 들어온 값은 이미 R-01 을 통과했다.
// 그래서 `judgeTurn` 의 malformed 는 "빈 세트"만 본다. 와이어에서 모르는 면은 디코드가 거절한다.

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
    /// R-11 첫 등록 최소 점수. 30 정확히는 통과, 29 는 실패.
    package static let initialMinimum = 30

    /// R-04~R-08 세트 판정(reference.py `meld_valid`). 무효면 kind·points 가 nil.
    package static func analyze(_ meld: [RummyFace]) -> RummyMeldAnalysis {
        let n = meld.count
        let numbered: [(color: Int, number: Int)] = meld.compactMap { face in
            guard let color = face.color, let number = face.number else { return nil }
            return (color, number)
        }
        let jokers = n - numbered.count
        // R-06: 3~13장 · 숫자 타일 1장 이상 · 조커 2장까지.
        guard (3...13).contains(n), !numbered.isEmpty, jokers <= 2 else { return .invalid }
        let colors = Set(numbered.map(\.color))
        let values = numbered.map(\.number)
        let distinctValues = Set(values)

        var group: Int?
        // 그룹(R-04·R-06): n ∈ {3,4}, 숫자 하나, 색 모두 다름.
        if n <= 4, distinctValues.count == 1, colors.count == numbered.count {
            group = values[0] * n
        }
        var run: Int?
        // 런(R-05·R-06): 색 하나, 숫자 모두 다름, hi − lo + 1 ≤ n. 순환(12-13-1) 없음.
        if colors.count == 1, distinctValues.count == values.count,
           let lo = values.min(), let hi = values.max(), hi - lo + 1 <= n {
            let start = runStart(lowest: lo, count: n)
            run = n * start + n * (n - 1) / 2  // R-08
        }
        // R-07: 점수 큰 쪽, 같으면 그룹.
        switch (group, run) {
        case let (g?, r?): return r > g ? .init(valid: true, kind: .run, points: r) : .init(valid: true, kind: .group, points: g)
        case let (g?, nil): return .init(valid: true, kind: .group, points: g)
        case let (nil, r?): return .init(valid: true, kind: .run, points: r)
        case (nil, nil): return .invalid
        }
    }

    /// R-07 런 시작 숫자 s = min(lo, 14 − n): 조커는 안쪽 빈칸 → 위쪽(13 까지) → 아래쪽 순으로 붙는다.
    private static func runStart(lowest: Int, count: Int) -> Int {
        min(lowest, 14 - count)
    }

    /// R-09 비교 키: (색 A<B<C<D, 숫자 오름, J 맨 뒤) 정렬.
    package static func compareKey(_ meld: [RummyFace]) -> [RummyFace] {
        meld.sorted()
    }

    /// R-09 표시 순서. 런 = R-07 구간 s … s+n−1 을 왼쪽부터(빈 자리에 조커), 그룹 = 색 A → D 뒤 조커.
    /// 무효 세트는 받은 순서 그대로 돌려준다 — 작업 중인 조각은 플레이어가 놓은 순서가 곧 뜻이다(R-09 "작업 중에는 놓은 순서").
    package static func displayOrder(_ meld: [RummyFace]) -> [RummyFace] {
        let analysis = analyze(meld)
        guard analysis.valid, let kind = analysis.kind else { return meld }
        switch kind {
        case .group:
            return compareKey(meld)
        case .run:
            let numbers = meld.compactMap(\.number)
            guard let lo = numbers.min() else { return meld }
            let start = runStart(lowest: lo, count: meld.count)
            var byNumber: [Int: RummyFace] = [:]
            for face in meld where !face.isJoker { byNumber[face.number!] = face }
            return (start..<(start + meld.count)).map { byNumber[$0] ?? .joker }
        }
    }

    /// K 다중집합 같음 — 판 위 세트 순서·세트 안 순서는 의미 없다(R-09).
    package static func sameTable(_ a: [[RummyFace]], _ b: [[RummyFace]]) -> Bool {
        a.count == b.count && keyBag(a) == keyBag(b)
    }

    /// R-16 차례 판정(reference.py `turn_valid`). 위에서부터 처음 걸리는 reason 하나.
    package static func judgeTurn(
        initialDone: Bool, tableBefore: [[RummyFace]], rackBefore: [RummyFace], tableAfter: [[RummyFace]]
    ) -> RummyTurnReason {
        // 0. 형식 — 면 정규식은 RummyFace 가 이미 보증했다. 남은 것은 빈 세트.
        if tableAfter.contains(where: \.isEmpty) { return .malformed }

        // 1. 판 보존 — 판에 있던 면이 사라지면 안 된다. 조커가 빠졌으면 따로 알린다(R-15).
        let before = bag(tableBefore.joined())
        let after = bag(tableAfter.joined())
        let missing = minus(before, after)
        if (missing[.joker] ?? 0) > 0 { return .jokerNotReused }
        if !missing.isEmpty { return .tableTileRemoved }

        // 2. 출처 — 새로 생긴 면은 모두 내 랙에서.
        let played = minus(after, before)
        if !isSubset(played, of: bag(rackBefore)) { return .tileNotOwned }

        // 3. 최소 — 1장 이상.
        if played.isEmpty { return .noTilePlayed }

        // 4. 세트 — 낱장·2장 조각 포함 하나라도 무효면 거절.
        if tableAfter.contains(where: { !analyze($0).valid }) { return .invalidMeld }

        // 5. 첫 등록(R-11·R-12) — 판 기존 세트는 그대로(K 부분집합), 새 세트 점수 합 ≥ 30.
        if !initialDone {
            if !isSubset(keyBag(tableBefore), of: keyBag(tableAfter)) { return .initialTableTouched }
            if newMeldPoints(tableBefore: tableBefore, tableAfter: tableAfter) < initialMinimum { return .initialUnder30 }
        }
        return .ok
    }

    /// 랙 값 합(R-22, 조커 30).
    package static func rackValue(_ rack: [RummyFace]) -> Int {
        rack.reduce(0) { $0 + $1.rackValue }
    }

    /// R-22~R-24 끝 점수와 승자(0-기반 자리, 오름차순). reference.py `score` 를 옮겼다.
    /// - 빈 랙이 있으면 R-22: 처음 빈 랙이 승자, 나머지 랙 값의 합을 가져간다.
    /// - 없으면 R-23·R-24: 최소 집단 T 가 감점 합 P 를 똑같이 나눈다(⌊P/m⌋, 나머지는 장수 적은 → 자리 앞 순으로 1점씩),
    ///   승자는 T 중 장수 최소(공동 가능).
    package static func finalScores(racks: [[RummyFace]]) -> (scores: [Int], winners: [Int]) {
        guard !racks.isEmpty else { return ([], []) }
        let values = racks.map(rackValue)

        if let emptied = racks.firstIndex(where: \.isEmpty) {
            var scores = values.map { -$0 }
            scores[emptied] = values.enumerated().reduce(0) { $1.offset == emptied ? $0 : $0 + $1.element }
            return (scores, [emptied])
        }

        let lowest = values.min()!
        let tied = racks.indices.filter { values[$0] == lowest }
        let fewest = tied.map { racks[$0].count }.min()!
        let winners = tied.filter { racks[$0].count == fewest }
        var scores = values.map { -($0 - lowest) }
        let pot = -scores.enumerated().reduce(0) { tied.contains($1.offset) ? $0 : $0 + $1.element }
        let order = tied.sorted { (racks[$0].count, $0) < (racks[$1].count, $1) }
        let base = pot / tied.count, remainder = pot % tied.count
        for (rank, seat) in order.enumerated() {
            scores[seat] = base + (rank < remainder ? 1 : 0)
        }
        return (scores, winners)
    }

    /// §2.1 0번: 정산이 `payouts` 에 넘기는 점수(서버 `rummy__settle` 과 같다). `racks` 는 끝까지 남은 자리 순.
    /// `finalScores` 그대로이되, 막힘 끝(빈 랙 없음)의 최소 집단 T(m ≥ 2)는 모두 ⌊P/m⌋ 로 같게 넘긴다 —
    /// 화면 점수의 나머지 1점이 §2.1 묶음을 갈라 값이 같은 공동 최소 집단이 다른 상금·등수를 받지 않게(설계서 P11).
    package static func payoutScores(racks: [[RummyFace]]) -> [Int] {
        var scores = finalScores(racks: racks).scores
        guard !racks.isEmpty, !racks.contains(where: \.isEmpty) else { return scores }
        let values = racks.map(rackValue)
        let lowest = values.min()!
        let tied = racks.indices.filter { values[$0] == lowest }
        guard tied.count >= 2 else { return scores }
        let pot = values.reduce(0) { $0 + ($1 - lowest) }
        for seat in tied { scores[seat] = pot / tied.count }
        return scores
    }

    /// 등수 상금표(× 판돈, 설계서 §2.1 ①). 2인 [2,0] · 3인 [2,1,0] · 4인 [3,1,0,0].
    package static func prizeTable(seatCount: Int) -> [Int] {
        switch seatCount {
        case 2: return [2, 0]
        case 3: return [2, 1, 0]
        case 4: return [3, 1, 0, 0]
        default: return []
        }
    }

    /// §2.1 등수별 분배(제로섬)와 표시 등수. `seats` 는 자리 순(p1..pn).
    /// 시작 인원이 2~4 밖이거나 active 가 하나도 없으면 분배할 수 없다 — 0 배열(등수는 그대로 센다).
    package static func payouts(seatCount: Int, stake: Int, seats: [RummyPayoutSeat]) -> (payouts: [Int], ranks: [Int]) {
        let prizes = prizeTable(seatCount: seatCount).map { $0 * stake }
        var payouts = Array(repeating: 0, count: seats.count)

        // ② active 를 score 내림차순으로 줄 세우고 같은 score 끼리 묶는다.
        let active = seats.indices.filter { seats[$0].active }.sorted { seats[$0].score > seats[$1].score }
        var groups: [[Int]] = []
        for index in active {
            if let last = groups.last?.first, seats[last].score == seats[index].score {
                groups[groups.count - 1].append(index)
            } else {
                groups.append([index])
            }
        }

        // 묶음 m명이 합을 나눈다: ⌊합/m⌋, 나머지는 (tiles 오름 → seat 오름) 앞사람부터 1씩.
        func split(_ total: Int, among group: [Int]) {
            let order = group.sorted { (seats[$0].tiles, seats[$0].seat) < (seats[$1].tiles, seats[$1].seat) }
            let base = total / group.count, remainder = total % group.count
            for (rank, index) in order.enumerated() {
                payouts[index] += base + (rank < remainder ? 1 : 0)
            }
        }

        if !prizes.isEmpty, !groups.isEmpty {
            var position = 0
            for group in groups {
                let total = (position..<(position + group.count)).reduce(0) { $0 + ($1 < prizes.count ? prizes[$1] : 0) }
                split(total, among: group)
                position += group.count
            }
            // ③ 기권자가 차지한 자리의 몫은 1위 묶음에 더 나눈다.
            let leftover = seatCount * stake - payouts.reduce(0, +)
            if leftover > 0 { split(leftover, among: groups[0]) }
            // ④ 제로섬 단언.
            assert(payouts.reduce(0, +) == seatCount * stake, "rummy payouts 합이 n·stake 가 아니다: \(payouts)")
        }

        // ⑤ 표시 등수: active = 1 + (score 가 더 큰 active 수), 기권 = k + (기권자 수 − forfeitOrder + 1).
        let activeCount = active.count
        let forfeitCount = seats.count - activeCount
        let ranks = seats.map { seat -> Int in
            if seat.active {
                return 1 + active.filter { seats[$0].score > seat.score }.count
            }
            return activeCount + (forfeitCount - (seat.forfeitOrder ?? 1) + 1)
        }
        return (payouts, ranks)
    }

    /// 첫 등록 진행 표시("18/30")용: 새로 생긴 세트(K(after) − K(before))의 R-08 점수 합. 무효 세트는 0점.
    package static func newMeldPoints(tableBefore: [[RummyFace]], tableAfter: [[RummyFace]]) -> Int {
        minus(keyBag(tableAfter), keyBag(tableBefore)).reduce(0) { total, entry in
            total + (analyze(entry.key).points ?? 0) * entry.value
        }
    }

    // MARK: 다중집합

    private static func bag<Element: Hashable>(_ items: some Sequence<Element>) -> [Element: Int] {
        items.reduce(into: [:]) { $0[$1, default: 0] += 1 }
    }

    /// 판의 비교 키 다중집합 K(R-09).
    private static func keyBag(_ table: [[RummyFace]]) -> [[RummyFace]: Int] {
        bag(table.map(compareKey))
    }

    /// a − b, 0 이하는 지운다(Counter 의 `-` 와 같다).
    private static func minus<Element: Hashable>(_ a: [Element: Int], _ b: [Element: Int]) -> [Element: Int] {
        a.reduce(into: [:]) { out, entry in
            let left = entry.value - (b[entry.key] ?? 0)
            if left > 0 { out[entry.key] = left }
        }
    }

    private static func isSubset<Element: Hashable>(_ a: [Element: Int], of b: [Element: Int]) -> Bool {
        a.allSatisfy { (b[$0.key] ?? 0) >= $0.value }
    }
}
