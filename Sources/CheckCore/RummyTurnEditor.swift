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
}

package struct RummyTurnEditor: Equatable, Sendable {
    /// 작업 판(놓인 순서).
    package private(set) var melds: [[RummyTile]]
    /// 내 랙(화면 순서).
    package private(set) var rack: [RummyTile]
    package let initialDone: Bool

    /// 차례 시작 판(면) — 판정 기준.
    private let startTable: [[RummyFace]]
    /// 차례 시작 랙(면) — 판정 기준(순서 무관).
    private let startRack: [RummyFace]
    /// 차례 시작 판(타일) — `reset` 이 되돌아갈 곳.
    private let startMelds: [[RummyTile]]
    /// 차례 시작 때 판에 있던 타일의 로컬 id(→ 랙으로 못 감, R-14).
    private let tableTileIDs: Set<Int>
    /// 랙에서 판으로 나간 타일과 나갈 때의 랙 자리(나간 순서). `reset` 이 거꾸로 되짚어 제자리에 꽂는다.
    /// 불변식: 지금 판 위에 있는 랙 출신 타일 = 이 목록의 타일.
    private var departures: [Departure]

    private struct Departure: Equatable, Sendable {
        let tile: RummyTile
        let index: Int
    }

    /// - Parameter rackOrder: 앞 차례의 내 랙 배치(면 순서). 그 순서대로 맞추고, 거기 없는 면(새로 받은 타일)은 받은 순서로 끝에 붙인다.
    package init(table: [[RummyFace]], rack: [RummyFace], initialDone: Bool, rackOrder: [RummyFace]? = nil) {
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
        var builtRack: [RummyTile] = []
        for face in Self.arrange(rack, by: rackOrder) {
            builtRack.append(RummyTile(id: nextID, face: face))
            nextID += 1
        }
        self.melds = builtMelds
        self.rack = builtRack
        self.initialDone = initialDone
        self.startTable = table
        self.startRack = rack
        self.startMelds = builtMelds
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

    /// 타일 하나를 옮긴다. 받아들였으면 true. 거절(false)이면 아무것도 바뀌지 않는다:
    /// 모르는 id · 판 타일을 `.rack` 으로(R-14) · 없는 세트 번호.
    /// 옮긴 뒤 빈 세트는 자동으로 지운다. 자리 번호 규약은 파일 머리말.
    @discardableResult
    package mutating func move(_ tileID: Int, to target: RummyDropTarget) -> Bool {
        guard let source = locate(tileID) else { return false }
        switch target {
        case .rack:
            if isFromTable(tileID) { return false }
        case .meld(let meldIndex, _):
            guard melds.indices.contains(meldIndex) else { return false }
        case .newMeld:
            break
        }

        let tile: RummyTile
        switch source {
        case .rack(let index): tile = rack.remove(at: index)
        case .meld(let meldIndex, let index): tile = melds[meldIndex].remove(at: index)
        }

        switch target {
        case .rack(let slot):
            var at = slot ?? rack.count
            if let slot, case .rack(let from) = source, slot > from { at -= 1 }
            rack.insert(tile, at: Self.clamp(at, upTo: rack.count))
            departures.removeAll { $0.tile.id == tileID }
        case .meld(let meldIndex, let slot):
            var at = slot ?? melds[meldIndex].count
            if let slot, case .meld(meldIndex, let from) = source, slot > from { at -= 1 }
            melds[meldIndex].insert(tile, at: Self.clamp(at, upTo: melds[meldIndex].count))
        case .newMeld:
            melds.append([tile])
        }

        if case .rack(let from) = source, !Self.isRack(target) {
            departures.append(Departure(tile: tile, index: from))
        }
        melds.removeAll(where: \.isEmpty)
        return true
    }

    private static func isRack(_ target: RummyDropTarget) -> Bool {
        if case .rack = target { return true }
        return false
    }

    private static func clamp(_ value: Int, upTo upper: Int) -> Int {
        min(max(value, 0), upper)
    }

    /// 차례 시작 상태로. 판은 시작 판 그대로, 랙은 **지금 순서를 유지**하고 판에 나갔던 타일만 나간 자리로 돌려 꽂는다.
    package mutating func reset() {
        melds = startMelds
        var restored = rack
        for departure in departures.reversed() {
            restored.insert(departure.tile, at: min(departure.index, restored.count))
        }
        rack = restored
        departures = []
    }

    /// 랙 정렬. `.number`(777) = 숫자 → 색, `.color`(789) = 색 → 숫자. 조커는 둘 다 맨 뒤. 같은 면은 id 순(안정).
    package mutating func sortRack(_ mode: RummyRackSort) {
        func key(_ tile: RummyTile) -> (Int, Int, Int, Int) {
            guard let color = tile.face.color, let number = tile.face.number else { return (1, 0, 0, tile.id) }
            switch mode {
            case .number: return (0, number, color, tile.id)
            case .color: return (0, color, number, tile.id)
            }
        }
        rack.sort { key($0) < key($1) }
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
}
