import Foundation

// 아잉 큐브 2판 — 내 받침대(랙) 자유 배치 모델(설계서 v2 §2.3). 맥·폰 공용 순수 값.
//
// 받침대는 줄 2개(넘치면 3번째 줄부터 더 연다)이고, 한 줄은 **반 칸 단위** `halfColumnsPerRow`(32 = 타일 16장)다.
// 타일 한 장은 반 칸 2개를 차지한다(`halfCol ..< halfCol + 2`). 같은 줄에서 두 타일이 반 칸이라도 겹치면 안 되고, 빈칸은 된다.
// 화면 순서(`readingOrder`)는 줄 → 반 칸 순이다. 편집기의 `rack` 배열은 늘 이 순서다.
//
// 정렬(777 · 789)은 **조합 단위로 끊고 단위 사이 반 칸**을 띄운다(낱장끼리도). 단위가 줄 끝에 안 들어가면 통째로 다음 줄로.
// 판마다 로컬에 저장한다(`RummyRackEntry` — 면과 자리. 타일 로컬 id 는 차례마다 새로 붙으므로 면으로 짝짓는다).

/// 받침대 위 한 자리(줄 · 반 칸). 타일의 왼쪽 끝이다.
package struct RummyRackSlot: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    package var row: Int
    package var halfCol: Int

    package init(row: Int, halfCol: Int) {
        self.row = row
        self.halfCol = halfCol
    }

    package static func < (lhs: RummyRackSlot, rhs: RummyRackSlot) -> Bool {
        (lhs.row, lhs.halfCol) < (rhs.row, rhs.halfCol)
    }

    package var description: String { "(\(row),\(halfCol))" }
}

/// 저장용 한 줄 — 면과 자리. 같은 면이 둘이면 저장 순서대로 하나씩 짝짓는다.
package struct RummyRackEntry: Hashable, Sendable, Codable {
    package var face: RummyFace
    package var slot: RummyRackSlot

    package init(face: RummyFace, slot: RummyRackSlot) {
        self.face = face
        self.slot = slot
    }
}

package struct RummyRackLayout: Equatable, Sendable {
    /// 한 줄의 반 칸 수(타일 16장).
    package static let halfColumnsPerRow = 32
    /// 늘 보이는 줄 수. 넘치면 줄이 더 열린다.
    package static let baseRows = 2
    /// 타일 한 장의 폭(반 칸).
    package static let tileSpan = 2

    /// 타일 로컬 id → 자리.
    package private(set) var slots: [Int: RummyRackSlot]

    package init() {
        slots = [:]
    }

    /// 화면에 그릴 줄 수(최소 2).
    package var rowCount: Int {
        max(Self.baseRows, (slots.values.map(\.row).max() ?? -1) + 1)
    }

    package func slot(of tileID: Int) -> RummyRackSlot? { slots[tileID] }

    /// 그 반 칸을 덮는 타일(화면의 누르기 판정용).
    package func tile(covering slot: RummyRackSlot) -> Int? {
        slots.first { $0.value.row == slot.row && (0..<Self.tileSpan).contains(slot.halfCol - $0.value.halfCol) }?.key
    }

    /// 화면 순서(줄 → 반 칸). 자리가 같을 일은 없지만(겹침 금지) 만약을 위해 id 로 끊는다.
    package var readingOrder: [Int] {
        slots.sorted { ($0.value, $0.key) < ($1.value, $1.key) }.map(\.key)
    }

    /// `tiles` 장을 `slot` 부터 나란히 놓을 수 있는가(줄 안 · 겹침 없음). `excluding` 은 장애물에서 뺀다(옮기는 타일들).
    package func isFree(_ slot: RummyRackSlot, tiles: Int = 1, excluding: Set<Int> = []) -> Bool {
        let span = tiles * Self.tileSpan
        guard slot.row >= 0, slot.halfCol >= 0, slot.halfCol + span <= Self.halfColumnsPerRow else { return false }
        for (id, other) in slots where other.row == slot.row && !excluding.contains(id) {
            if other.halfCol < slot.halfCol + span && other.halfCol + Self.tileSpan > slot.halfCol { return false }
        }
        return true
    }

    /// `slot` 에서 가장 가까운 빈자리(`tiles` 장이 나란히 들어가는). 같은 줄을 먼저(줄 차이 → 반 칸 차이 → 왼쪽),
    /// 기존 줄이 다 막혔으면 새 줄(맨 아래)의 첫 자리. 늘 답이 있다.
    package func nearestFree(to slot: RummyRackSlot, tiles: Int = 1, excluding: Set<Int> = []) -> RummyRackSlot {
        let span = tiles * Self.tileSpan
        let maxStart = max(0, Self.halfColumnsPerRow - span)
        let wantRow = max(0, slot.row)
        let wantCol = min(max(0, slot.halfCol), maxStart)
        var best: (key: (Int, Int, Int), slot: RummyRackSlot)?
        for row in 0..<rowCount {
            for col in 0...maxStart {
                let candidate = RummyRackSlot(row: row, halfCol: col)
                guard isFree(candidate, tiles: tiles, excluding: excluding) else { continue }
                let key = (abs(row - wantRow), abs(col - wantCol), col)
                if best == nil || key < best!.key { best = (key, candidate) }
            }
        }
        if let best { return best.slot }
        let occupiedRows = slots.filter { !excluding.contains($0.key) }.map(\.value.row)
        return RummyRackSlot(row: max(rowCount, (occupiedRows.max() ?? -1) + 1), halfCol: 0)
    }

    /// "마지막 빈자리"(뽑은 타일·랙 끝으로 보내기): 화면 순서로 마지막 타일 **바로 뒤**에 들어가면 거기,
    /// 아니면 그 뒤 줄들의 첫 빈자리, 그것도 없으면 앞에서부터 첫 빈자리, 다 막혔으면 새 줄.
    package func endSlot(tiles: Int = 1, excluding: Set<Int> = []) -> RummyRackSlot {
        let span = tiles * Self.tileSpan
        let others = slots.filter { !excluding.contains($0.key) }
        let rows = rowCount
        if let last = others.values.max() {
            let after = RummyRackSlot(row: last.row, halfCol: last.halfCol + Self.tileSpan)
            if isFree(after, tiles: tiles, excluding: excluding) { return after }
            for row in (last.row + 1)..<max(rows, last.row + 1) {
                if let slot = firstFree(row: row, span: span, excluding: excluding) { return slot }
            }
        }
        for row in 0..<rows {
            if let slot = firstFree(row: row, span: span, excluding: excluding) { return slot }
        }
        return RummyRackSlot(row: max(rows, (others.values.map(\.row).max() ?? -1) + 1), halfCol: 0)
    }

    private func firstFree(row: Int, span: Int, excluding: Set<Int>) -> RummyRackSlot? {
        guard span <= Self.halfColumnsPerRow else { return nil }
        for col in 0...(Self.halfColumnsPerRow - span) {
            let slot = RummyRackSlot(row: row, halfCol: col)
            if isFree(slot, tiles: span / Self.tileSpan, excluding: excluding) { return slot }
        }
        return nil
    }

    /// 타일들을 `slot` 부터 나란히 놓는다(덮어쓴다 — 호출자가 `isFree`/`nearestFree` 로 고른 자리여야 한다).
    package mutating func set(_ tileIDs: [Int], at slot: RummyRackSlot) {
        for (offset, id) in tileIDs.enumerated() {
            slots[id] = RummyRackSlot(row: slot.row, halfCol: slot.halfCol + offset * Self.tileSpan)
        }
    }

    package mutating func remove(_ tileID: Int) {
        slots[tileID] = nil
    }

    // MARK: - 0.3.70 끼워 넣기 · 덩어리

    /// 끼워 넣기(0.3.70 — 감사 #2). `tileIDs` 를 `wanted` 부터 나란히 놓는다(이미 있던 자리는 먼저 뺀다).
    ///  · `wanted` 가 비었으면 **그대로**(옛 규칙 — 빈칸에 놓기).
    ///  · 아니면 그 줄의 타일 사이에 **끼운다**: 왼쪽 끝이 `wanted` 보다 앞인 타일은 제자리, 나머지는 오른쪽으로 민다.
    ///    놓은 블록이 왼쪽 이웃에 닿거나 겹치면 그 바로 뒤에 붙인다(그 이웃 덩어리에 붙는다).
    ///    미는 타일은 **필요한 만큼만** 밀고 덩어리 모양을 지킨다: 딱 붙은 타일은 붙은 채, 빈칸은 반 칸까지 줄어들되 0 은 안 된다
    ///    (다른 덩어리끼리 붙어 버리지 않게). 블록이 왼쪽 덩어리에 붙었는데 오른쪽 이웃이 원래 다른 덩어리였으면 그 사이에도 반 칸을 둔다.
    ///  · 줄 끝을 넘치면 넘친 **덩어리**를 다음 줄 맨 앞에 끼워 흘린다(`settle`) — 덩어리가 한 줄보다 길거나 줄의 첫 덩어리면
    ///    넘친 타일부터. 다음 줄도 같은 규칙으로 밀리고, 마지막 줄을 넘치면 새 줄이 열린다.
    /// 타일을 잃거나 겹치지 않는다(시험 `V0370RummyRackTests`).
    package mutating func insert(_ tileIDs: [Int], at wanted: RummyRackSlot) {
        guard !tileIDs.isEmpty else { return }
        for id in tileIDs { slots[id] = nil }
        let span = tileIDs.count * Self.tileSpan
        let row = max(0, wanted.row)
        let start0 = min(max(0, wanted.halfCol), max(0, Self.halfColumnsPerRow - span))
        let first = RummyRackSlot(row: row, halfCol: start0)
        if isFree(first, tiles: tileIDs.count) {
            set(tileIDs, at: first)
            return
        }
        let line = items(inRow: row)
        let split = line.firstIndex { $0.col >= start0 } ?? line.count
        let left = Array(line[..<split]), right = Array(line[split...])
        var start = start0
        var joinedLeft = false
        if let a = left.last, start0 <= a.col + Self.tileSpan {
            start = a.col + Self.tileSpan
            joinedLeft = true
        }
        var placed = left
        for (offset, id) in tileIDs.enumerated() { placed.append((id, start + offset * Self.tileSpan)) }
        var end = start + span
        for (index, tile) in right.enumerated() {
            let gap: Int
            if index == 0 {
                let separate = left.last.map { $0.col + Self.tileSpan < tile.col } ?? false
                gap = joinedLeft && separate ? 1 : 0
            } else {
                gap = min(1, tile.col - (right[index - 1].col + Self.tileSpan))
            }
            let col = max(tile.col, end + gap)
            placed.append((tile.id, col))
            end = col + Self.tileSpan
        }
        settle(placed, row: row)
    }

    /// 같은 줄에서 딱 붙은(빈칸 없는) 덩어리들 — 화면 순, 덩어리 안은 왼쪽부터. 랙 묶음 표시(감사 #3)가 쓴다.
    package var chunks: [[Int]] {
        var result: [[Int]] = []
        var previous: RummyRackSlot?
        for id in readingOrder {
            guard let slot = slots[id] else { continue }
            if let previous, previous.row == slot.row, previous.halfCol + Self.tileSpan == slot.halfCol {
                result[result.count - 1].append(id)
            } else {
                result.append([id])
            }
            previous = slot
        }
        return result
    }

    /// 한 줄의 타일(왼쪽부터).
    private func items(inRow row: Int) -> [(id: Int, col: Int)] {
        slots.filter { $0.value.row == row }
            .sorted { ($0.value.halfCol, $0.key) < ($1.value.halfCol, $1.key) }
            .map { ($0.key, $0.value.halfCol) }
    }

    /// 한 줄 몫(왼쪽부터 · 겹침 없음)을 `row` 에 앉힌다. 줄 끝을 넘으면 넘친 덩어리(한 줄보다 짧고 줄의 첫 덩어리가 아니면 통째로,
    /// 아니면 넘친 타일부터)를 다음 줄 맨 앞에 끼우고 그 줄 타일을 민다(첫 타일과는 반 칸 — 다른 덩어리). 줄마다 한 장 이상 남으니 끝난다.
    private mutating func settle(_ placed: [(id: Int, col: Int)], row: Int) {
        guard let over = placed.firstIndex(where: { $0.col + Self.tileSpan > Self.halfColumnsPerRow }) else {
            for item in placed { slots[item.id] = RummyRackSlot(row: row, halfCol: item.col) }
            return
        }
        func touches(_ i: Int) -> Bool { placed[i - 1].col + Self.tileSpan == placed[i].col }
        var head = over
        while head > 0, touches(head) { head -= 1 }
        var tail = over
        while tail + 1 < placed.count, touches(tail + 1) { tail += 1 }
        let chunkSpan = placed[tail].col + Self.tileSpan - placed[head].col
        let cut = head > 0 && chunkSpan <= Self.halfColumnsPerRow ? head : max(over, 1)
        for item in placed[..<min(cut, placed.count)] { slots[item.id] = RummyRackSlot(row: row, halfCol: item.col) }
        guard cut < placed.count else { return }
        var flowing: [(id: Int, col: Int)] = []
        for i in cut..<placed.count {
            let col = i == cut ? 0
                : flowing[flowing.count - 1].col + Self.tileSpan + min(1, placed[i].col - (placed[i - 1].col + Self.tileSpan))
            flowing.append((placed[i].id, col))
        }
        let moving = Set(flowing.map(\.id))
        let next = row + 1
        let existing = items(inRow: next).filter { !moving.contains($0.id) }
        var line = flowing
        var end = (flowing.last?.col ?? 0) + Self.tileSpan
        for (index, tile) in existing.enumerated() {
            let gap = index == 0 ? 1 : min(1, tile.col - (existing[index - 1].col + Self.tileSpan))
            let col = max(tile.col, end + gap)
            line.append((tile.id, col))
            end = col + Self.tileSpan
        }
        settle(line, row: next)
    }

    /// 빈칸 없이 순서대로(줄이 차면 다음 줄). 옛 선형 자리 API(`.rack(index:)`)와 처음 받은 랙이 쓴다.
    package static func packed(_ tileIDs: [Int]) -> RummyRackLayout {
        grouped(tileIDs.map { [$0] }, gap: 0)
    }

    /// 단위(조합)마다 이어 놓고 단위 사이 `gap` 반 칸. 단위가 줄 끝에 안 들어가면 통째로 다음 줄(단위가 한 줄보다 길면 쪼갠다).
    package static func grouped(_ units: [[Int]], gap: Int = 1) -> RummyRackLayout {
        var layout = RummyRackLayout()
        var row = 0, col = 0
        for unit in units where !unit.isEmpty {
            let span = unit.count * tileSpan
            if col > 0, col + span > halfColumnsPerRow, span <= halfColumnsPerRow {
                row += 1
                col = 0
            }
            for id in unit {
                if col + tileSpan > halfColumnsPerRow {
                    row += 1
                    col = 0
                }
                layout.slots[id] = RummyRackSlot(row: row, halfCol: col)
                col += tileSpan
            }
            col += gap
        }
        return layout
    }

    /// 정렬 단위로 나눈다. `.number`(777) = 숫자 → 색 순으로 늘어놓고 **같은 숫자**끼리 한 단위,
    /// `.color`(789) = 색 → 숫자 순으로 늘어놓고 **같은 색 연속 숫자**끼리 한 단위. 조커는 둘 다 맨 뒤 한 단위.
    /// 늘어놓는 순서는 v1 `sortRack` 과 같다(같은 면은 id 순 — 안정).
    package static func sortUnits(_ tiles: [RummyTile], by mode: RummyRackSort) -> [[RummyTile]] {
        func key(_ tile: RummyTile) -> (Int, Int, Int, Int) {
            guard let color = tile.face.color, let number = tile.face.number else { return (1, 0, 0, tile.id) }
            switch mode {
            case .number: return (0, number, color, tile.id)
            case .color: return (0, color, number, tile.id)
            }
        }
        let sorted = tiles.sorted { key($0) < key($1) }
        var units: [[RummyTile]] = []
        for tile in sorted {
            if let last = units.last?.last, joins(last.face, tile.face, mode: mode) {
                units[units.count - 1].append(tile)
            } else {
                units.append([tile])
            }
        }
        return units
    }

    private static func joins(_ previous: RummyFace, _ next: RummyFace, mode: RummyRackSort) -> Bool {
        if previous.isJoker || next.isJoker { return previous.isJoker && next.isJoker }
        switch mode {
        case .number: return previous.number == next.number
        case .color: return previous.color == next.color && (previous.number ?? 0) + 1 == next.number
        }
    }
}

extension RummyRules {
    /// 이 순서 그대로 런이나 그룹의 **일부**가 될 수 있는가(길이 무관 · 조커 와일드 · 1장 = 참). 길게 눌러 집기(랙)의 넓히기 기준.
    /// 런 = 숫자 타일이 모두 같은 색이고 왼쪽부터 1씩 오르며(조커가 빈칸을 메운다) 1…13 안. 그룹 = 4장 이하, 숫자 하나, 색 모두 다름.
    package static func isChainable(_ faces: [RummyFace]) -> Bool {
        guard faces.count > 1 else { return !faces.isEmpty }
        let numbered = faces.enumerated().compactMap { item -> (index: Int, color: Int, number: Int)? in
            guard let color = item.element.color, let number = item.element.number else { return nil }
            return (item.offset, color, number)
        }
        guard !numbered.isEmpty else { return faces.count <= 13 }
        // 런의 일부: 시작 숫자 s = number − index 가 모두 같고 s ≥ 1, s + count − 1 ≤ 13, 색 하나.
        let starts = Set(numbered.map { $0.number - $0.index })
        if Set(numbered.map(\.color)).count == 1, starts.count == 1, let start = starts.first,
           start >= 1, start + faces.count - 1 <= 13 {
            return true
        }
        // 그룹의 일부.
        return faces.count <= 4 && Set(numbered.map(\.number)).count == 1
            && Set(numbered.map(\.color)).count == numbered.count
    }
}
