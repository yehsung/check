@testable import CheckCore
import Foundation
import Testing

// 아잉 마작 스토어 표면 시험(갈래 C1 — SPEC §4.5). 스텁 서버 장면(로비 → 방 → 시작 → 차례 → … → 판 끝) · 리버시 적대 검증
// 여섯 장면 · 깨우기 · 요청 마감은 C2 가 이 파일에 더한다. 여기서는 네트워크 없이 `applyState` 의 칸 나눔과 가드만 잰다.

@MainActor
@Suite("아잉 마작 스토어 표면 — 칸 나눔 · 결정 키 접기 · 늦은 응답 가드")
struct V03xxMahjongStoreTests {
    private static func decode(_ text: String) throws -> MahjongStatePayload {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(MahjongStatePayload.self, from: Data(text.utf8))
    }

    private static func turnState(seq: Int, decisionSeq: Int?, handIndex: Int = 3, status: String = "active") -> String {
        let decision = decisionSeq.map {
            #"{"kind":"turn","seq":\#(seq),"decision_seq":\#($0),"started_ms":1000,"deadline_ms":6000,"bank_ms":20000,"#
                + #""discard":[0,4],"riichi":[0,4],"tsumo":false,"ankan":[],"kakan":[],"kyuushu":false}"#
        } ?? "null"
        return #"{"match":{"id":"m-1","status":"\#(status)","seq":\#(seq),"hand_index":\#(handIndex),"phase":"turn"},"#
            + #""my_seat":0,"my_hand":[0,4],"my_decision":\#(decision),"server_now_ms":1000}"#
    }

    @Test("서버 state 는 match 에만 · 연습 칸과 따로 · table 한 길 · 단계 playing")
    func serverStateLandsInMatchOnly() throws {
        // 없으면: 연습판과 서버 방이 한 칸을 나눠 써서 연습 중 온 방 응답이 연습 탁자를 덮는다(CC-02).
        let store = MahjongStore()
        #expect(store.applyState(try Self.decode(Self.turnState(seq: 5, decisionSeq: 2))) == .applied)
        #expect(store.match?.match?.id == "m-1")
        #expect(store.practice == nil && !store.isPractice)
        #expect(store.table == store.match)
        #expect(store.phase == .playing)
        // 연습판 id 는 서버 경로로 못 들어온다(가드 (g)).
        let practice = try Self.decode(Self.turnState(seq: 9, decisionSeq: 1).replacingOccurrences(of: "m-1", with: "ai-1"))
        #expect(store.applyState(practice) == .ignored)
        #expect(store.match?.match?.id == "m-1")
    }

    @Test("결정 키가 바뀌면 리치 무장을 접는다 — 같은 키 state 가 다시 오면 무장 유지(기준선)")
    func riichiArmFoldsOnDecisionKeyChange() throws {
        // 없으면: 무장한 채 시간 초과되면 다음 차례 클릭이 원치 않은 리치(−1000·손 잠김)가 된다(CC-03).
        let store = MahjongStore()
        store.applyState(try Self.decode(Self.turnState(seq: 5, decisionSeq: 2)))
        store.armRiichi()
        #expect(store.riichiArmed)
        // 기준선: 같은 결정 키(decision_seq 2) — 무장 유지.
        store.applyState(try Self.decode(Self.turnState(seq: 5, decisionSeq: 2)))
        #expect(store.riichiArmed)
        // 새 결정(decision_seq 3) — 접힌다.
        store.applyState(try Self.decode(Self.turnState(seq: 7, decisionSeq: 3)))
        #expect(!store.riichiArmed)
        // 결정이 없어져도 접힌다.
        store.armRiichi()
        #expect(store.riichiArmed)
        store.applyState(try Self.decode(Self.turnState(seq: 8, decisionSeq: nil)))
        #expect(!store.riichiArmed)
    }

    @Test("늦은 응답 — 낮은 seq · 이전 국 · 판이 된 id 의 forming 응답은 버린다(ⓔ)")
    func lateResponsesAreIgnored() throws {
        // 없으면: 망 재정렬로 늦게 온 옛 state 가 화면을 되돌리거나, 판이 된 방에 늦은 방 응답이 와 방 화면으로 돌아간다(V2-04).
        let store = MahjongStore()
        store.applyState(try Self.decode(Self.turnState(seq: 10, decisionSeq: 4, handIndex: 3)))
        #expect(store.applyState(try Self.decode(Self.turnState(seq: 9, decisionSeq: 4, handIndex: 3))) == .ignored)
        #expect(store.applyState(try Self.decode(Self.turnState(seq: 12, decisionSeq: 4, handIndex: 2))) == .ignored)
        #expect(store.applyState(try Self.decode(Self.turnState(seq: 11, decisionSeq: 5, status: "forming"))) == .ignored)
        #expect(store.match?.match?.seq == 10)
        #expect(store.phase == .playing)
        // 기준선: 더 새 seq 는 들어간다.
        #expect(store.applyState(try Self.decode(Self.turnState(seq: 11, decisionSeq: 5))) == .applied)
        #expect(store.match?.match?.seq == 11)
    }

    @Test("창이 탁자를 보인다 = 보임 && 안 가려짐(ⓐ)")
    func windowShowingTableNeedsVisibleAndUnoccluded() {
        // 없으면: 가려진 창(전체 화면 앱)을 보이는 것으로 쳐 내 차례 말풍선이 죽는다(CC-01 · V2-01).
        let store = MahjongStore()
        #expect(!store.isWindowShowingTable)
        store.windowDidShow()
        #expect(store.isWindowShowingTable)
        store.windowOcclusionDidChange(visible: false)
        #expect(store.isWindowVisible && !store.isWindowShowingTable)
        store.windowOcclusionDidChange(visible: true)
        #expect(store.isWindowShowingTable)
        store.windowDidHide()
        #expect(!store.isWindowShowingTable)
    }
}
