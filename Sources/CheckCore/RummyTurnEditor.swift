import Foundation

// 자리표시 — R 갈래가 채운다.
//
// 차례 중 작업 상태(순수 값 타입). 선언 이름·시그니처는 설계서 §4.2 가 계약이다 — 바꾸지 마라.
// 뼈대는 init 이 판·랙을 `RummyTile`(로컬 id 0..: 판 타일 먼저, 그다음 랙)로 담아 `melds`·`rack` 이 보이게만 한다.
// `move` 는 false, `reset`·`sortRack` 은 빈 몸, 판정 값은 `RummyRules` 자리표시를 그대로 따른다.

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

    /// 차례 시작 판(면).
    private let startTable: [[RummyFace]]
    /// 차례 시작 랙(면).
    private let startRack: [RummyFace]
    /// 차례 시작 때 판에 있던 타일의 로컬 id(→ 랙으로 못 감, R-14).
    private let tableTileIDs: Set<Int>

    /// - Parameter rackOrder: 앞 차례의 내 랙 배치(면 순서) 보존. 자리표시 — 아직 쓰지 않는다.
    package init(table: [[RummyFace]], rack: [RummyFace], initialDone: Bool, rackOrder: [RummyFace]? = nil) {
        var nextID = 0
        var builtMelds: [[RummyTile]] = []
        var tableIDs: Set<Int> = []
        for meld in table {
            var tiles: [RummyTile] = []
            for face in meld {
                tiles.append(RummyTile(id: nextID, face: face))
                tableIDs.insert(nextID)
                nextID += 1
            }
            builtMelds.append(tiles)
        }
        var builtRack: [RummyTile] = []
        for face in rack {
            builtRack.append(RummyTile(id: nextID, face: face))
            nextID += 1
        }
        self.melds = builtMelds
        self.rack = builtRack
        self.initialDone = initialDone
        self.startTable = table
        self.startRack = rack
        self.tableTileIDs = tableIDs
    }

    /// 차례 시작 때 판에 있던 타일인가.
    package func isFromTable(_ tileID: Int) -> Bool {
        tableTileIDs.contains(tileID)
    }

    /// 판 타일을 `.rack` 으로 → false. 빈 세트는 자동 제거. 자리표시 — 늘 false.
    @discardableResult
    package mutating func move(_ tileID: Int, to target: RummyDropTarget) -> Bool {
        false
    }

    /// 차례 시작 상태로(랙 순서는 유지). 자리표시.
    package mutating func reset() {}

    /// 자리표시.
    package mutating func sortRack(_ mode: RummyRackSort) {}

    /// !sameTable(작업 판, 시작 판).
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

    /// 첫 등록 전: 새 세트 점수 합.
    package var initialPoints: Int {
        RummyRules.newMeldPoints(tableBefore: startTable, tableAfter: submissionTable)
    }

    /// 이번 차례에 랙에서 판으로 낸 장수. 자리표시.
    package var playedCount: Int { 0 }

    package var rackFaces: [RummyFace] {
        rack.map(\.face)
    }
}
