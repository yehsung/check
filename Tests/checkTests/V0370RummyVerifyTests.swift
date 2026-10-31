import Foundation
import Testing
@testable import CheckCore

// 아잉 큐브 0.3.70 플레이 다듬기 적대 검증에서 찾은 결함의 재현 시험.

private func xf(_ text: String) -> [RummyFace] { text.split(separator: " ").map { RummyFace(text: String($0))! } }

private func xEditor(_ sets: [String], at points: [RummyPoint], rack: String, initialDone: Bool = true) -> RummyTurnEditor {
    RummyTurnEditor(table: sets.map(xf), rack: xf(rack), initialDone: initialDone,
                    tableLayout: RummyLayout(points.map { Optional($0) }))
}

private func xTexts(_ e: RummyTurnEditor) -> [String] { e.submissionTable.map { $0.map(\.text).joined(separator: " ") } }

/// 확정 판 그림: 서버는 묶음을 K 로 저장하고 모든 기기가 `displayOrder` 를 같은 배치 점에 그린다(`RummyPanelMatch`·편집기 init).
/// 면 → 화면 왼쪽 위 목록(같은 면은 왼쪽부터).
private func xConfirmedSpots(_ e: RummyTurnEditor) -> [[String]] {
    let confirmed = RummyTurnEditor(table: e.submissionTable, rack: [], initialDone: true,
                                    tableLayout: RummyLayout(e.points.map { Optional($0) }))
    func spots(_ x: RummyTurnEditor) -> [[String]] {
        x.melds.indices.map { set in
            x.melds[set].enumerated().map { "\($0.element.face.text)@\(x.points[set].x + $0.offset * RummyTableLayout.tileWidth),\(x.points[set].y)" }
        }
    }
    return spots(confirmed)
}

private func xScreenSpots(_ e: RummyTurnEditor) -> [[String]] {
    e.melds.indices.map { set in
        e.melds[set].enumerated().map { "\($0.element.face.text)@\(e.points[set].x + $0.offset * RummyTableLayout.tileWidth),\(e.points[set].y)" }
    }
}

@Suite("0.3.70 아잉 큐브 적대 검증 — 확정 전후 같은 그림(R-09)")
struct V0370RummyVerifyTests {
    @Test("조커 런 끝에서 한 장을 빼 남은 토막이 맞는 세트면 그 자리에서 표시 순서 — 확정 뒤 조커가 튀지 않는다")
    func leftoverRunKeepsConfirmedOrder() {
        // 없으면: A3 J A5 A6 에서 A3 을 빼면 남은 [J A5 A6] 이 그 순서로 남아, 확정 뒤 판(표시 순서 A5 A6 J)에서 조커가
        // 왼끝에서 오른끝으로 튀는 결함이 초록이 된다(0.3.70 은 '받은' 묶음만 표시 순서로 늘어놓았다).
        var e = xEditor(["A3 J A5 A6", "B3 C3 D3"], at: [RummyPoint(x: 100, y: 100), RummyPoint(x: 100, y: 300)], rack: "A9")
        let a3 = e.melds[0][0].id
        let ok = e.moveBlock([a3], to: .meld(1, index: nil))
        #expect(ok)
        #expect(xTexts(e) == ["A5 A6 J", "A3 B3 C3 D3"], "\(xTexts(e))")
        #expect(xScreenSpots(e) == xConfirmedSpots(e), "확정 전 화면 ≠ 확정 뒤 판")
        // 남은 토막의 숫자 타일(A5 180 · A6 220)은 제자리, 조커만 오른끝(260)으로 건너간다.
        #expect(e.points[0] == RummyPoint(x: 180, y: 100))
        // 빼낸 A3 을 남은 토막 앞에 다시 꽂으면 처음 판 그대로(A3 J A5 A6 @ 100).
        var back = xEditor(["A3 J A5 A6", "B3 C3 D3"], at: [RummyPoint(x: 100, y: 100), RummyPoint(x: 100, y: 300)], rack: "A9")
        let a3b = back.melds[0][0].id
        let out = back.moveBlock([a3b], to: .newMeldAt(RummyPoint(x: 600, y: 500)))
        let into = back.moveBlock([a3b], to: .meld(0, index: 0))
        #expect(out && into)
        #expect(xTexts(back) == ["A3 J A5 A6", "B3 C3 D3"] && back.points[0] == RummyPoint(x: 100, y: 100), "\(xTexts(back)) \(back.points)")
        // 오른쪽이 막혔으면(여백 16 안에 이웃) 조커가 건너갈 자리가 없다 → 사각형 제자리에서 순서만(이웃은 그대로).
        var tight = xEditor(["A3 J A5 A6", "B3 C3 D3", "C9 C10 C11"],
                            at: [RummyPoint(x: 100, y: 100), RummyPoint(x: 100, y: 300), RummyPoint(x: 276, y: 100)], rack: "A9")
        let ok3 = tight.moveBlock([tight.melds[0][0].id], to: .meld(1, index: nil))
        #expect(ok3)
        #expect(xTexts(tight) == ["A5 A6 J", "A3 B3 C3 D3", "C9 C10 C11"])
        #expect(tight.points[0] == RummyPoint(x: 140, y: 100) && tight.points[2] == RummyPoint(x: 276, y: 100), "\(tight.points)")
        #expect(xScreenSpots(tight) == xConfirmedSpots(tight))
    }

    @Test("무효 묶음 끝을 빼 맞게 된 토막(J A5 A6 A9 → J A5 A6)도 그 자리에서 표시 순서")
    func leftoverBecomesValidKeepsConfirmedOrder() {
        // 없으면: 작업 중 무효 묶음에서 끝 타일을 빼 남은 토막이 맞는 세트가 됐는데 놓은 순서 그대로 남아 확정 뒤 튀는 결함이 초록이 된다.
        var e = xEditor(["B1 B2 B3"], at: [RummyPoint(x: 0, y: 0)], rack: "J A5 A6 A9")
        let rack = e.rack.map(\.id)
        let ok1 = e.moveBlock(rack, to: .newMeldAt(RummyPoint(x: 400, y: 300)))
        #expect(ok1)
        #expect(xTexts(e).last == "J A5 A6 A9")
        let a9 = e.melds[1][3].id
        let ok2 = e.moveBlock([a9], to: .rack(index: nil))
        #expect(ok2)
        #expect(xTexts(e) == ["B1 B2 B3", "A5 A6 J"], "\(xTexts(e))")
        #expect(xScreenSpots(e) == xConfirmedSpots(e))
    }

    @Test("작업 중 [J A5] 오른쪽에 A6 을 놓아 맞는 런이 되면 A5 는 제자리 — 조커만 오른끝으로(A5 · A6 이 80 왼쪽으로 튀지 않는다)")
    func jokerFirstWorkingMeldKeepsNumberedTile() {
        // 없으면: 첫 남은 타일(조커)을 기준으로 표시 순서 A5 A6 J 를 늘어놓아, 방금 놓은 A6 과 A5 가 80 왼쪽으로 튀는 결함이 초록이 된다.
        var e = xEditor(["B1 B2 B3"], at: [RummyPoint(x: 0, y: 0)], rack: "J A5 A6")
        let j = e.rack.first { $0.face.isJoker }!.id
        let a5 = e.rack.first { $0.face.text == "A5" }!.id
        let a6 = e.rack.first { $0.face.text == "A6" }!.id
        let ok1 = e.moveBlock([j, a5], to: .newMeldAt(RummyPoint(x: 400, y: 300)))
        #expect(ok1)
        let at = e.points[1]
        #expect(xTexts(e) == ["B1 B2 B3", "J A5"])
        let ok2 = e.moveBlock([a6], to: .meld(1, index: nil))
        #expect(ok2)
        #expect(xTexts(e) == ["B1 B2 B3", "A5 A6 J"])
        #expect(e.points[1] == RummyPoint(x: at.x + RummyTableLayout.tileWidth, y: at.y), "A5 가 제자리가 아니다: \(at) → \(e.points[1])")
    }
}
