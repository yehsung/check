import Foundation

// 차례 중 작업 상태(순수 값 타입). 선언 이름·시그니처는 설계서 §4.2 가 계약이다 — 바꾸지 마라.
//
// 로컬 id: 판 타일 먼저(세트 순·표시 순), 그다음 랙(화면 순)으로 0.. 을 붙인다. 와이어엔 면 문자열만 간다(설계서 §1).
// 시작 판의 세트는 R-09 표시 순서로 다시 그린다(런의 조커가 제자리에) — 비교는 K 다중집합이라 판정엔 영향이 없다.
//
// 끌기 자리(index) 규약: **옮기기 전 화면에서 "이 자리 앞에 놓는다"** 는 슬롯 번호다(SwiftUI `move(fromOffsets:toOffset:)` 와 같다).
// 같은 줄 안에서 뒤로 옮기면 빠진 자리만큼 하나 당겨 꽂는다. nil 이거나 넘치면 끝, 음수는 맨 앞.
//
// R-14: 차례 시작 때 판에 있던 타일은 랙으로 못 간다(`move` 가 false, 아무것도 안 바꾼다). 이번 차례에 랙에서 낸 타일은 돌아올 수 있다.
// 첫 등록 차례의 판 조작(R-12)은 막지 않는다 — 판정(`reason`)이 initial_table_touched 로 알려 준다(편집기는 규칙을 둘로 들지 않는다).
//
// ── v2(설계서 v2 §2.2·§2.3) — 더하기만, v1 서명 그대로 ──
//  · 판 배치: 묶음마다 왼쪽 위 점(`points`)을 함께 든다. 시작 점은 `RummyTableLayout.place`(결정적 자동 배치)이고, 묶음 길이가
//    바뀌면 오른쪽으로 늘어나다 막히면 가장 가까운 빈자리로(`RummyTableLayout.refit`). `moveSet` = 묶음 통째 위치 이동.
//    `.newMeldAt(점)` = 빈 곳에 놓아 새 묶음(그 점에서 가장 가까운 빈자리). 배치는 판정과 무관하다(`reason` 은 면만 본다).
//  · 받침대: `rackLayout`(줄 · 반 칸 자유 배치)이 랙 자리의 정본이고 `rack` 배열은 늘 그 화면 순서다. `.rackSlot(자리)` = 그 자리
//    가까운 빈자리로. 옛 `.rack(index: i)` 는 선형 자리 규약 그대로 꽂은 뒤 **빈칸 없이 다시 채운다**(v2 화면은 `.rackSlot`),
//    `.rack(index: nil)` 은 마지막 빈자리(`RummyRackLayout.endSlot`). 판으로 나간 랙 타일은 나간 **자리**를 기억했다가
//    `reset` 이 그 자리로(막혔으면 가장 가까운 빈자리로) 돌린다.
//  · 묶음째 옮기기: `moveBlock` 은 전부 아니면 전무이고 `move(x)` 는 `moveBlock([x])` 다(같은 규약 한 벌).

/// 끌기용 타일 한 장. `id` 는 이 편집기 안에서만 뜻이 있는 로컬 번호다(와이어엔 면 문자열만 간다 — 설계서 §1).
package struct RummyTile: Identifiable, Hashable, Sendable {
    package let id: Int
    package let face: RummyFace

    package init(id: Int, face: RummyFace) {
        self.id = id
        self.face = face
    }
}

package enum RummyRackSort: Sendable {
    /// 같은 숫자끼리(777).
    case number
    /// 색별 연속(789).
    case color
}

package enum RummyDropTarget: Hashable, Sendable {
    case rack(index: Int?)
    case meld(Int, index: Int?)
    case newMeld
    /// v2: 판의 빈 곳에 놓아 새 묶음. 점 = 놓은 묶음의 왼쪽 위(판 논리 좌표) — 그 점에서 가장 가까운 빈자리로 스냅한다.
    case newMeldAt(RummyPoint)
    /// v2: 받침대의 한 자리(줄 · 반 칸). 그 자리에서 가장 가까운 빈자리로, 여러 장이면 그 자리부터 나란히.
    case rackSlot(RummyRackSlot)
}

package struct RummyTurnEditor: Equatable, Sendable {
    /// 작업 판(놓인 순서).
    package private(set) var melds: [[RummyTile]]
    /// v2: 묶음마다 왼쪽 위 점(판 순서, `melds` 와 같은 길이).
    package private(set) var points: [RummyPoint]
    /// 내 랙(화면 순서 = `rackLayout.readingOrder`).
    package private(set) var rack: [RummyTile]
    /// v2: 받침대 자리(타일 id → 줄 · 반 칸). 랙 자리의 정본.
    package private(set) var rackLayout: RummyRackLayout
    package let initialDone: Bool

    /// 차례 시작 판(면) — 판정 기준.
    private let startTable: [[RummyFace]]
    /// 차례 시작 랙(면) — 판정 기준(순서 무관).
    private let startRack: [RummyFace]
    /// 차례 시작 판(타일) — `reset` 이 되돌아갈 곳.
    private let startMelds: [[RummyTile]]
    /// 차례 시작 판 배치.
    private let startPoints: [RummyPoint]
    /// 차례 시작 때 판에 있던 타일의 로컬 id(→ 랙으로 못 감, R-14).
    private let tableTileIDs: Set<Int>
    /// 랙에서 판으로 나간 타일과 나갈 때의 받침대 자리(나간 순서). `reset` 이 거꾸로 되짚어 제자리에 놓는다.
    /// 불변식: 지금 판 위에 있는 랙 출신 타일 = 이 목록의 타일.
    private var departures: [Departure]

    private struct Departure: Equatable, Sendable {
        let tile: RummyTile
        let slot: RummyRackSlot
    }

    /// - Parameters:
    ///   - rackOrder: 앞 차례의 내 랙 배치(면 순서). 그 순서대로 맞추고, 거기 없는 면(새로 받은 타일)은 받은 순서로 끝에 붙인다.
    ///   - tableLayout: v2 확정 판 배치(`state.table_layout`). 빈 자리는 결정적 자동 배치로 채운다.
    ///   - rackEntries: v2 앞 차례(또는 저장된) 받침대 자리(면 + 자리). 주면 `rackOrder` 보다 앞선다 — 면으로 짝지어 그 자리에 놓고,
    ///     짝 없는 면(새로 받은 타일)은 받은 순서로 마지막 빈자리에.
    package init(
        table: [[RummyFace]], rack: [RummyFace], initialDone: Bool, rackOrder: [RummyFace]? = nil,
        tableLayout: RummyLayout? = nil, rackEntries: [RummyRackEntry]? = nil
    ) {
        var nextID = 0
        var builtMelds: [[RummyTile]] = []
        var tableIDs: Set<Int> = []
        for meld in table {
            var tiles: [RummyTile] = []
            for face in RummyRules.displayOrder(meld) {
                tiles.append(RummyTile(id: nextID, face: face))
                tableIDs.insert(nextID)
                nextID += 1
            }
            builtMelds.append(tiles)
        }
        // 받침대: 면 → 자리를 먼저 정하고, 화면 순서로 id 를 붙인다(로컬 id 규약: 랙은 화면 순).
        let placed = Self.arrangeSlots(rack, order: rackOrder, entries: rackEntries)
        var builtRack: [RummyTile] = []
        var layout = RummyRackLayout()
        for (face, slot) in placed {
            let tile = RummyTile(id: nextID, face: face)
            builtRack.append(tile)
            layout.set([tile.id], at: slot)
            nextID += 1
        }
        let points = RummyTableLayout.place(sets: table, layout: tableLayout)
        self.melds = builtMelds
        self.points = points
        self.rack = builtRack
        self.rackLayout = layout
        self.initialDone = initialDone
        self.startTable = table
        self.startRack = rack
        self.startMelds = builtMelds
        self.startPoints = points
        self.tableTileIDs = tableIDs
        self.departures = []
    }

    /// 면 순서 `order` 를 따라 `rack` 을 늘어놓는다(같은 면 여럿이면 앞에서부터 하나씩 짝짓는다). 짝 없는 면은 무시, 남는 랙 면은 끝에.
    private static func arrange(_ rack: [RummyFace], by order: [RummyFace]?) -> [RummyFace] {
        guard let order else { return rack }
        var remaining = rack
        var arranged: [RummyFace] = []
        arranged.reserveCapacity(rack.count)
        for face in order {
            if let index = remaining.firstIndex(of: face) {
                arranged.append(remaining.remove(at: index))
            }
        }
        return arranged + remaining
    }

    /// 받침대 첫 배치(면 · 자리, 화면 순서). 저장된 자리가 있으면 면으로 짝지어 그 자리(겹치면 가장 가까운 빈자리),
    /// 남는 면은 받은 순서로 마지막 빈자리. 없으면 `rackOrder` 순으로 빈칸 없이.
    private static func arrangeSlots(
        _ rack: [RummyFace], order: [RummyFace]?, entries: [RummyRackEntry]?
    ) -> [(RummyFace, RummyRackSlot)] {
        guard let entries, !entries.isEmpty else {
            let faces = arrange(rack, by: order)
            let layout = RummyRackLayout.packed(Array(faces.indices))
            return faces.indices.map { (faces[$0], layout.slot(of: $0)!) }
        }
        var layout = RummyRackLayout()
        var used = Array(repeating: false, count: rack.count)
        for entry in entries {
            guard let index = rack.indices.first(where: { !used[$0] && rack[$0] == entry.face }) else { continue }
            used[index] = true
            let slot = layout.isFree(entry.slot) ? entry.slot : layout.nearestFree(to: entry.slot)
            layout.set([index], at: slot)
        }
        for index in rack.indices where !used[index] {
            layout.set([index], at: layout.endSlot())
        }
        return layout.readingOrder.map { (rack[$0], layout.slot(of: $0)!) }
    }

    /// 차례 시작 때 판에 있던 타일인가.
    package func isFromTable(_ tileID: Int) -> Bool {
        tableTileIDs.contains(tileID)
    }

    private enum Spot: Equatable {
        case rack(Int)
        case meld(Int, Int)
    }

    private func locate(_ tileID: Int) -> Spot? {
        if let index = rack.firstIndex(where: { $0.id == tileID }) { return .rack(index) }
        for (meldIndex, meld) in melds.enumerated() {
            if let index = meld.firstIndex(where: { $0.id == tileID }) { return .meld(meldIndex, index) }
        }
        return nil
    }

    private func tile(_ tileID: Int) -> RummyTile? {
        switch locate(tileID) {
        case .rack(let index)?: return rack[index]
        case .meld(let meldIndex, let index)?: return melds[meldIndex][index]
        case nil: return nil
        }
    }

    /// 타일 하나를 옮긴다. 받아들였으면 true. 거절(false)이면 아무것도 바뀌지 않는다:
    /// 모르는 id · 판 타일을 `.rack`/`.rackSlot` 으로(R-14) · 없는 세트 번호.
    /// 옮긴 뒤 빈 세트는 자동으로 지운다. 자리 번호 규약은 파일 머리말. `moveBlock([tileID], to:)` 와 같다.
    @discardableResult
    package mutating func move(_ tileID: Int, to target: RummyDropTarget) -> Bool {
        moveBlock([tileID], to: target)
    }

    // MARK: - v2 묶음째 집기·옮기기

    /// 랙에서 길게 눌러 집히는 '이어진 덩어리'(화면 순). 누른 타일에서 같은 줄의 **딱 붙은** 이웃(반 칸 빈칸이면 끊긴다)을
    /// 오른쪽 → 왼쪽 번갈아 넓히되, 이 순서로 런이나 그룹의 일부가 될 수 있는 동안만(`RummyRules.isChainable`). 랙에 없는 id 면 빈 배열.
    package func rackChain(around tileID: Int) -> [Int] {
        guard let start = rackLayout.slot(of: tileID) else { return [] }
        var bySlot: [RummyRackSlot: Int] = [:]
        for (id, slot) in rackLayout.slots { bySlot[slot] = id }
        let faces = Dictionary(uniqueKeysWithValues: rack.map { ($0.id, $0.face) })
        var chain = [tileID]
        var left = start.halfCol, right = start.halfCol
        func face(_ id: Int) -> RummyFace { faces[id] ?? .joker }
        var grew = true
        while grew {
            grew = false
            if let next = bySlot[RummyRackSlot(row: start.row, halfCol: right + RummyRackLayout.tileSpan)],
               RummyRules.isChainable((chain + [next]).map(face)) {
                chain.append(next)
                right += RummyRackLayout.tileSpan
                grew = true
            }
            if let previous = bySlot[RummyRackSlot(row: start.row, halfCol: left - RummyRackLayout.tileSpan)],
               RummyRules.isChainable(([previous] + chain).map(face)) {
                chain.insert(previous, at: 0)
                left -= RummyRackLayout.tileSpan
                grew = true
            }
        }
        return chain
    }

    /// 판에서 길게 눌러 집히는 타일들: 그 타일의 묶음 전체, `fromTileToEnd` 면 그 타일부터 오른쪽 끝까지(⌥ — 런 쪼개기).
    /// 판에 없는 id 면 빈 배열.
    package func meldPick(for tileID: Int, fromTileToEnd: Bool = false) -> [Int] {
        guard case .meld(let meldIndex, let index)? = locate(tileID) else { return [] }
        let meld = melds[meldIndex]
        return (fromTileToEnd ? Array(meld[index...]) : meld).map(\.id)
    }

    /// 고른 타일들의 화면 순서(판 묶음 순 → 묶음 안 순 → 랙 화면 순). 모르는 id 는 버린다.
    package func screenOrder(_ tileIDs: Set<Int>) -> [Int] {
        (melds.flatMap { $0 } + rack).map(\.id).filter { tileIDs.contains($0) }
    }

    /// `moveBlock` 이 받아들일까(바꾸지 않고 묻기).
    package func canMoveBlock(_ tileIDs: [Int], to target: RummyDropTarget) -> Bool {
        var copy = self
        return copy.moveBlock(tileIDs, to: target)
    }

    /// 여러 장을 한 번에 옮긴다 — **전부 아니면 전무.** 거절(false): 빈 목록 · 중복 · 모르는 id · 판 출신이 섞인 채 랙으로(R-14) ·
    /// 없는 세트 번호. 놓인 순서 = 넘긴 순서(화면이 `screenOrder` 로 맞춰 넘긴다).
    /// 자리 = 옮기기 전 화면 슬롯(`move` 규약) — 같은 줄이면 그 슬롯 앞에 있던 집힌 장수만큼 당겨 꽂는다.
    /// 랙에서 판으로 나간 타일은 나갈 때의 받침대 자리를 하나씩 기억한다(→ `reset` 이 고칠 것 없이 맞는다).
    @discardableResult
    package mutating func moveBlock(_ tileIDs: [Int], to target: RummyDropTarget) -> Bool {
        guard !tileIDs.isEmpty, Set(tileIDs).count == tileIDs.count else { return false }
        var block: [RummyTile] = []
        var sources: [Int: Spot] = [:]
        for id in tileIDs {
            guard let spot = locate(id), let found = tile(id) else { return false }
            sources[id] = spot
            block.append(found)
        }
        let toRack: Bool
        switch target {
        case .rack, .rackSlot:
            if tileIDs.contains(where: isFromTable) { return false }
            toRack = true
        case .meld(let meldIndex, _):
            guard melds.indices.contains(meldIndex) else { return false }
            toRack = false
        case .newMeld, .newMeldAt:
            toRack = false
        }
        let moving = Set(tileIDs)
        let countsBefore = melds.map(\.count)
        var lookup = Dictionary(uniqueKeysWithValues: rack.map { ($0.id, $0) })
        for tile in block { lookup[tile.id] = tile }

        // 1) 랙에서 빼기(판으로 나가는 것은 자리를 기억).
        let readingBefore = rack.map(\.id)
        for tile in block {
            guard case .rack? = sources[tile.id], let slot = rackLayout.slot(of: tile.id) else { continue }
            if !toRack { departures.append(Departure(tile: tile, slot: slot)) }
            rackLayout.remove(tile.id)
        }
        if toRack { departures.removeAll { moving.contains($0.tile.id) } }

        // 2) 판에서 빼기(빈 세트는 아직 남겨 둔다 — 세트 번호가 옮기기 전 화면 기준이다).
        var working = melds.map { meld in meld.filter { !moving.contains($0.id) } }
        var newPointWanted: RummyPoint??

        // 3) 놓기.
        switch target {
        case .meld(let meldIndex, let slot):
            var at = working[meldIndex].count
            if let slot {
                let before = melds[meldIndex].prefix(max(slot, 0)).filter { moving.contains($0.id) }.count
                at = Self.clamp(slot - before, upTo: working[meldIndex].count)
            }
            working[meldIndex].insert(contentsOf: block, at: at)
        case .newMeld:
            working.append(block)
            newPointWanted = .some(nil)
        case .newMeldAt(let point):
            working.append(block)
            newPointWanted = .some(point)
        case .rack(let slot?):
            // 옛 선형 자리: 화면 순서에 꽂고 빈칸 없이 다시 채운다.
            var order = readingBefore.filter { !moving.contains($0) }
            let before = readingBefore.prefix(max(slot, 0)).filter { moving.contains($0) }.count
            order.insert(contentsOf: tileIDs, at: Self.clamp(slot - before, upTo: order.count))
            rackLayout = .packed(order)
        case .rack(nil):
            rackLayout.set(tileIDs, at: rackLayout.endSlot(tiles: tileIDs.count))
        case .rackSlot(let wanted):
            let slot = rackLayout.isFree(wanted, tiles: tileIDs.count)
                ? wanted : rackLayout.nearestFree(to: wanted, tiles: tileIDs.count)
            rackLayout.set(tileIDs, at: slot)
        }

        // 4) 빈 세트 지우기 + 길이가 바뀐 세트 다시 맞추기(오른쪽으로 늘다 막히면 가장 가까운 빈자리).
        var keptMelds: [[RummyTile]] = []
        var keptPoints: [RummyPoint] = []
        var changed: [Int] = []
        for index in countsBefore.indices where !working[index].isEmpty {
            if working[index].count != countsBefore[index] { changed.append(keptMelds.count) }
            keptMelds.append(working[index])
            keptPoints.append(points[index])
        }
        for index in changed {
            let others = keptMelds.indices.filter { $0 != index }
                .map { RummyTableLayout.frame(at: keptPoints[$0], tiles: keptMelds[$0].count) }
            keptPoints[index] = RummyTableLayout.refit(keptPoints[index], tiles: keptMelds[index].count, among: others)
        }
        if let wanted = newPointWanted {
            let others = keptMelds.indices.map { RummyTableLayout.frame(at: keptPoints[$0], tiles: keptMelds[$0].count) }
            let point = wanted.map { RummyTableLayout.snap($0, tiles: block.count, among: others) }
                ?? RummyTableLayout.firstFree(tiles: block.count, among: others)
            keptMelds.append(block)
            keptPoints.append(point)
        }
        melds = keptMelds
        points = keptPoints
        rack = rackLayout.readingOrder.compactMap { lookup[$0] }
        return true
    }

    /// v2: 묶음 통째 위치 이동(판 좌표 왼쪽 위). 가장 가까운 빈자리로 스냅한다(자기 자리는 장애물에서 뺀다). 없는 번호면 false.
    /// 내용은 안 바뀐다 — 판정(`reason`)·`isChanged` 와 무관하고 `isLayoutChanged` 만 바뀐다.
    @discardableResult
    package mutating func moveSet(_ setIndex: Int, to point: RummyPoint) -> Bool {
        guard melds.indices.contains(setIndex) else { return false }
        points[setIndex] = tableLayout.snap(point, tiles: melds[setIndex].count, excluding: setIndex)
        return true
    }

    private static func clamp(_ value: Int, upTo upper: Int) -> Int {
        min(max(value, 0), upper)
    }

    /// 차례 시작 상태로. 판은 시작 판·시작 배치 그대로, 랙은 **지금 자리를 유지**하고 판에 나갔던 타일만 나간 자리로 돌린다
    /// (그 자리가 그새 막혔으면 가장 가까운 빈자리).
    package mutating func reset() {
        var lookup = Dictionary(uniqueKeysWithValues: rack.map { ($0.id, $0) })
        for departure in departures.reversed() {
            let slot = rackLayout.isFree(departure.slot) ? departure.slot : rackLayout.nearestFree(to: departure.slot)
            rackLayout.set([departure.tile.id], at: slot)
            lookup[departure.tile.id] = departure.tile
        }
        melds = startMelds
        points = startPoints
        rack = rackLayout.readingOrder.compactMap { lookup[$0] }
        departures = []
    }

    /// 랙 정렬. `.number`(777) = 숫자 → 색, `.color`(789) = 색 → 숫자. 조커는 둘 다 맨 뒤. 같은 면은 id 순(안정).
    /// v2: 조합 단위(777 = 같은 숫자, 789 = 같은 색 연속)로 끊어 **단위 사이 반 칸**을 띄워 받침대에 다시 놓는다.
    package mutating func sortRack(_ mode: RummyRackSort) {
        let units = RummyRackLayout.sortUnits(rack, by: mode)
        rackLayout = .grouped(units.map { $0.map(\.id) })
        let lookup = Dictionary(uniqueKeysWithValues: rack.map { ($0.id, $0) })
        rack = rackLayout.readingOrder.compactMap { lookup[$0] }
    }

    /// !sameTable(작업 판, 시작 판) — 세트 안 순서만 바꿨거나 쪼갰다 되돌린 것은 "안 바뀜"(R-19·R-09).
    /// 이 편집기가 그 확정 판·랙에서 시작했는가(판은 K 비교, 랙은 순서 무관). 같은 차례에 seq 만 오른 state 가 와도
    /// 이것이 참이면 편집기를 덮지 않는다.
    package func standsOn(table: [[RummyFace]], rack: [RummyFace]) -> Bool {
        guard RummyRules.sameTable(table, startTable), rack.count == startRack.count else { return false }
        var counts: [RummyFace: Int] = [:]
        for face in startRack { counts[face, default: 0] += 1 }
        for face in rack { counts[face, default: 0] -= 1 }
        return counts.values.allSatisfy { $0 == 0 }
    }

    package var isChanged: Bool {
        !RummyRules.sameTable(submissionTable, startTable)
    }

    package var submissionTable: [[RummyFace]] {
        melds.map { $0.map(\.face) }
    }

    package var reason: RummyTurnReason {
        RummyRules.judgeTurn(
            initialDone: initialDone, tableBefore: startTable, rackBefore: startRack, tableAfter: submissionTable)
    }

    package var canSubmit: Bool { reason == .ok }

    package func analysis(ofMeld index: Int) -> RummyMeldAnalysis {
        guard melds.indices.contains(index) else { return .invalid }
        return RummyRules.analyze(melds[index].map(\.face))
    }

    /// 첫 등록 전: 새 세트 점수 합("18/30" 의 18).
    package var initialPoints: Int {
        RummyRules.newMeldPoints(tableBefore: startTable, tableAfter: submissionTable)
    }

    /// 이번 차례에 랙에서 판으로 낸 장수. 판 타일은 랙에 못 오므로 시작 랙 장수 − 지금 랙 장수다.
    package var playedCount: Int { startRack.count - rack.count }

    package var rackFaces: [RummyFace] {
        rack.map(\.face)
    }

    // MARK: - v2 배치 읽기

    /// 지금 작업 판의 배치(묶음 장수 + 점). 화면이 그대로 그린다.
    package var tableLayout: RummyTableLayout {
        RummyTableLayout(counts: melds.map(\.count), points: points)
    }

    /// `rummy_draft`/`rummy_play` 의 `p_layout`(묶음마다 점, null 없음).
    package var submissionLayout: RummyLayout {
        RummyLayout(points.map { Optional($0) })
    }

    /// 배치만이라도 바뀌었는가(되돌리기 버튼·작업 전송용 — 판정과 무관).
    package var isLayoutChanged: Bool {
        points != startPoints || isChanged
    }

    /// 차례 시작 랙(면, 서버가 준 순서). 스토어가 다음 차례 랙과 대어 새로 받은 타일(뽑기)을 가린다.
    package var startRackFaces: [RummyFace] { startRack }

    /// 받침대 저장용(면 + 자리, 화면 순).
    package var rackEntries: [RummyRackEntry] {
        rack.compactMap { tile in rackLayout.slot(of: tile.id).map { RummyRackEntry(face: tile.face, slot: $0) } }
    }

    /// 되돌린 것처럼(판에 나간 랙 타일이 나간 자리로 돌아온) 받침대 자리 — 다음 차례 편집기에 넘긴다(서버가 작업 판을 버리고
    /// 그 타일들을 랙에 돌려주므로).
    package var restoredRackEntries: [RummyRackEntry] {
        var copy = self
        copy.reset()
        return copy.rackEntries
    }
}
