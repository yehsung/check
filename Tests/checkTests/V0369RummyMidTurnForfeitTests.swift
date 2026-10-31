import Foundation
import Testing
@testable import CheckCore

// V3 검증 갈래가 찾은 결함(V3-1 · V3-2)의 회귀 시험 — 내 차례 중에 **남이** 기권하면(rummy_leave · 계정 삭제) 서버는 seq 만 +1
// 하고 차례·마감·작업 판(draft)을 그대로 둔다(verify/v3/v3_engine.sql F8 이 실서버로 확인). 예전 편집기는 seq 가 바뀌면 무조건
// 다시 세워 끌어 놓던 작업을 지우고 "되돌린 판"을 다시 보냈다. 지금은 편집기·'내 차례' 알림을 **차례 정체성**
// (`RummyEditorKey` = 판 · 차례 자리 · turn_started_ms)으로 가른다.

private let v3Me = UUID(uuidString: "00000000-0000-0000-0000-0000000000A1")!
private let v3B = UUID(uuidString: "00000000-0000-0000-0000-0000000000B2")!
private let v3C = UUID(uuidString: "00000000-0000-0000-0000-0000000000C3")!
private let v3Match = UUID(uuidString: "7E7E0000-0000-4000-8000-0000000000F3")!
private let v3NowMs: Double = 1_800_000_000_000

private func v3Opt(_ value: Any?) -> Any { value ?? NSNull() }

private func v3Seat(_ no: Int, _ user: UUID, _ name: String, state: String, rackCount: Int, forfeitOrder: Int? = nil)
    -> [String: Any]
{
    ["seat_no": no, "user_id": user.uuidString.lowercased(), "display_name": name, "avatar_url": NSNull(),
     "character": "jelly", "state": state, "rack_count": rackCount, "initial_done": true, "timeout_streak": 0,
     "forfeit_order": v3Opt(forfeitOrder), "final_rank": NSNull(), "final_score": NSNull(), "payout": NSNull(),
     "is_winner": NSNull(), "final_rack": NSNull()]
}

private func v3State(seq: Int, seats: [[String: Any]], draft: [String: Any]?, lastKind: String, lastSeat: Int)
    throws -> RummyMatchState
{
    let state: [String: Any] = [
        "id": v3Match.uuidString.lowercased(), "status": "active", "host_id": v3Me.uuidString.lowercased(), "stake": 5,
        "is_public": false, "seat_count": 3, "max_seats": 4, "server_now_ms": v3NowMs, "seq": seq,
        "expires_at_ms": NSNull(), "seats": seats, "my_seat_no": 0,
        "my_rack": ["A10", "A11", "A12", "B5", "C9"], "my_initial_done": true,
        "table": [["D1", "D2", "D3"]], "pool_count": 40,
        "turn_seat_no": 0, "turn_started_ms": v3NowMs - 20_000, "turn_deadline_ms": v3NowMs + 40_000, "grace_ms": 2000,
        "draft": v3Opt(draft), "consecutive_passes": 0,
        "last_event": ["kind": lastKind, "seat_no": lastSeat, "count": 0, "at_ms": v3NowMs],
        "end_reason": NSNull(), "finished_at_ms": NSNull(),
    ]
    let data = try JSONSerialization.data(withJSONObject: ["status": "ok", "state": state])
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try #require(try decoder.decode(RummyActionResponse.self, from: data).state)
}

@MainActor
private final class V3AttentionBox { var items: [String] = [] }

@Suite("v0.3.69 아잉 큐브 — 내 차례 중 남의 기권(seq+1)과 작업 판(V3-1·V3-2)", .serialized)
@MainActor
struct V0369RummyMidTurnForfeitTests {
    @Test("남이 기권해 seq 만 오르고 차례·마감·서버 작업 판이 그대로면 내 편집기 작업이 남는다")
    func myWorkSurvivesOtherSeatForfeit() throws {
        let store = RummyStore()
        store.draftDebounceSeconds = 3_600   // 네트워크로 안 나가게(디바운스만 걸린다)
        store.deadlineWakeEnabled = false
        let three = [v3Seat(0, v3Me, "나", state: "playing", rackCount: 5),
                     v3Seat(1, v3B, "비", state: "playing", rackCount: 9),
                     v3Seat(2, v3C, "씨", state: "playing", rackCount: 7)]
        #expect(store.applyState(try v3State(seq: 5, seats: three, draft: nil, lastKind: "draw", lastSeat: 2)) == .applied)
        #expect(store.isMyTurn)
        let editor = try #require(store.editor)
        let ids = ["A10", "A11", "A12"].compactMap { text in editor.rack.first { $0.face.text == text }?.id }
        try #require(ids.count == 3)
        store.moveTile(ids[0], to: .newMeld)
        let meld = (store.editor?.melds.count ?? 1) - 1
        store.moveTile(ids[1], to: .meld(meld, index: nil))
        store.moveTile(ids[2], to: .meld(meld, index: nil))
        let worked = try #require(store.editor?.submissionTable)
        #expect(worked.count == 2, "끌어 놓기가 됐다(판 2세트)")
        #expect(store.editor?.rackFaces.count == 2)

        // 씨가 나갔다(rummy_leave → 기권). 서버: seq 6 · 차례 0 그대로 · 마감 그대로 · draft = 내가 보낸 작업 판.
        let after = [v3Seat(0, v3Me, "나", state: "playing", rackCount: 5),
                     v3Seat(1, v3B, "비", state: "playing", rackCount: 9),
                     v3Seat(2, v3C, "씨", state: "forfeit", rackCount: 0, forfeitOrder: 1)]
        let echo: [String: Any] = ["table": [["D1", "D2", "D3"], ["A10", "A11", "A12"]], "draft_seq": 3, "at_ms": v3NowMs]
        store.cancelDraft()   // 위 끌기의 디바운스는 이미 서버에 닿았다고 친다(서버 draft = echo)
        #expect(store.applyState(try v3State(seq: 6, seats: after, draft: echo, lastKind: "forfeit", lastSeat: 2)) == .applied)
        #expect(store.draftDebounceTask == nil,
                "서버가 이미 든 내 작업 판 위에 되돌린 시작 판을 다시 보내려 한다 — 마감이면 (b) 자동 확정 대신 (a) 1장")
        #expect(store.isMyTurn, "차례는 여전히 나")
        #expect(store.editor?.submissionTable == worked, "남의 기권(seq+1)으로 내 차례 작업 판이 지워졌다")
        #expect(store.editor?.rackFaces.count == 2, "끌어 놓은 세 장이 랙으로 돌아갔다")
    }
    @Test("남의 기권(seq+1)은 '내 차례' 알림을 다시 울리지 않는다(같은 차례)")
    func otherSeatForfeitDoesNotReannounceMyTurn() throws {
        let store = RummyStore()
        store.draftDebounceSeconds = 3_600
        store.deadlineWakeEnabled = false
        let box = V3AttentionBox()
        store.onAttention = { box.items.append($0) }
        let three = [v3Seat(0, v3Me, "나", state: "playing", rackCount: 5),
                     v3Seat(1, v3B, "비", state: "playing", rackCount: 9),
                     v3Seat(2, v3C, "씨", state: "playing", rackCount: 7)]
        store.applyState(try v3State(seq: 5, seats: three, draft: nil, lastKind: "draw", lastSeat: 2))
        let first = box.items.count
        let after = [v3Seat(0, v3Me, "나", state: "playing", rackCount: 5),
                     v3Seat(1, v3B, "비", state: "playing", rackCount: 9),
                     v3Seat(2, v3C, "씨", state: "forfeit", rackCount: 0, forfeitOrder: 1)]
        store.applyState(try v3State(seq: 6, seats: after, draft: nil, lastKind: "forfeit", lastSeat: 2))
        #expect(box.items.count == first, "같은 차례인데 '내 차례' 알림이 또 울렸다: \(box.items)")
    }
}
