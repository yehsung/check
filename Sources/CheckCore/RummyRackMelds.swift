import Foundation

// 아잉 큐브 0.3.70 — 받침대 정리 읽기(감사 #3 · #2). 맥·폰 공용 순수 값. 판정과 무관(확정은 서버 R-16).
//
// ① 랙 묶음: 받침대에서 **내가 딱 붙여 둔 덩어리**(`RummyRackLayout.chunks` — 같은 줄 · 빈칸 없음)가 그대로 맞는 묶음(3장 이상 ·
//    `RummyRules.analyze` 유효)이면 그 덩어리와 R-08 점수. 덩어리를 쪼개 보거나 다시 짜 보지 않는다 — 정답 찾기 힌트가 아니라
//    내가 만든 것만 센다(공정성). 순서는 `analyze` 와 같이 보지 않는다(서버도 묶음을 다중집합으로 판정한다).
// ② 첫 등록 합: 판에 이번 차례 새로 놓은 맞는 묶음 점수(`initialPoints` — 진행 막대와 같은 값) + 랙 묶음 합.
//    합치는 까닭: 첫 등록 30 은 "이번 차례에 새로 내놓는 묶음들의 합"이다. 랙에서 판으로 한 묶음씩 옮겨도 합이 그대로여야
//    "다 내면 30 이 되나"를 끝까지 같은 숫자로 읽는다(랙만 세면 내려놓을수록 숫자가 줄어 거꾸로 읽힌다).
// ③ 끼워 넣기 미리보기: `rackLayoutAfterDrop` = 같은 놓기를 사본에 해 본 받침대(미리보기 = 실제).

/// 받침대의 맞는 덩어리 하나.
package struct RummyRackMeld: Equatable, Hashable, Sendable {
    /// 덩어리 타일(화면 순 — 왼쪽부터).
    package let tileIDs: [Int]
    package let kind: RummyMeldKind
    /// R-08 점수(조커는 대신하는 숫자).
    package let points: Int

    package init(tileIDs: [Int], kind: RummyMeldKind, points: Int) {
        self.tileIDs = tileIDs
        self.kind = kind
        self.points = points
    }
}

extension RummyTurnEditor {
    /// ① 받침대에서 그대로 맞는 덩어리들(화면 순).
    package var rackMelds: [RummyRackMeld] {
        let faces = Dictionary(uniqueKeysWithValues: rack.map { ($0.id, $0.face) })
        return rackLayout.chunks.compactMap { ids in
            guard ids.count >= 3 else { return nil }
            let analysis = RummyRules.analyze(ids.compactMap { faces[$0] })
            guard analysis.valid, let kind = analysis.kind, let points = analysis.points else { return nil }
            return RummyRackMeld(tileIDs: ids, kind: kind, points: points)
        }
    }

    /// ① 랙 묶음 점수 합.
    package var rackMeldPoints: Int {
        rackMelds.reduce(0) { $0 + $1.points }
    }

    /// ② 첫 등록 합(판에 새로 놓은 맞는 묶음 + 랙 묶음). 첫 등록을 마쳤으면 nil(보이지 않는다).
    package var initialPlanPoints: (table: Int, rack: Int)? {
        guard !initialDone else { return nil }
        return (initialPoints, rackMeldPoints)
    }

    /// ③ `tileIDs` 를 받침대 `slot` 에 놓으면 될 받침대(바꾸지 않는다). 거절이면(R-14 판 출신 등) nil.
    package func rackLayoutAfterDrop(_ tileIDs: [Int], at slot: RummyRackSlot) -> RummyRackLayout? {
        var copy = self
        guard copy.moveBlock(tileIDs, to: .rackSlot(slot)) else { return nil }
        return copy.rackLayout
    }
}
