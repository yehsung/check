@testable import CheckCore
import Foundation
import Testing

// 아잉 마작 패 움직임(SPEC §4.5 '움직임' · §6.3 C) — 순수 값. 어떤 프레임이든 `now` 하나로 정해지고, 응답이 온 **뒤** 시작하며,
// 다른 판·국이면 무시하고, 사건 꼬리가 여럿이면 1.5초 안에 따라잡는다.

@MainActor
@Suite("아잉 마작 움직임 — 순수 값 · 응답 뒤 시작 · 다른 판·국 무시 · 꼬리 여럿 1.5초")
struct V03xxMahjongMotionTests {
    private static let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private static func motion(duration: TimeInterval = MahjongMotion.defaultDuration) -> MahjongMotion {
        MahjongMotion(
            matchID: "m", handIndex: 2, seq: 9, kind: .discard,
            from: .init(compass: .right, area: .hand), to: .init(compass: .right, area: .river),
            startedAt: t0, duration: duration)
    }

    @Test("t=0 시작 자리 · 끝 자리 · 시작 전 0 · 끝난 뒤 1 · 이징은 위치만(진행도와 따로)")
    func progressIsAFunctionOfNow() {
        // 없으면: 프레임마다 쌓는 상태로 그려 창이 잠깐 가려졌다 돌아오면 움직임이 처음부터 다시 돈다.
        let m = Self.motion()
        #expect(m.progress(at: Self.t0) == 0 && m.progress(at: Self.t0.addingTimeInterval(-1)) == 0)
        #expect(m.progress(at: Self.t0.addingTimeInterval(m.duration)) == 1 && m.isFinished(at: Self.t0.addingTimeInterval(9)))
        let half = Self.t0.addingTimeInterval(m.duration / 2)
        #expect(abs(m.progress(at: half) - 0.5) < 1e-5)
        #expect(m.easedProgress(at: half) > m.progress(at: half), "이징은 앞당긴다 — 불투명도는 progress 로만")
        #expect(Self.motion(duration: 0).progress(at: Self.t0.addingTimeInterval(0.001)) == 1)
    }

    @Test("다른 판·국이면 무시 · 꼬리 여럿은 합쳐 1.5초 안")
    func appliesOnlyToItsHandAndCatchesUp() {
        // 없으면: 국이 바뀐 뒤 옛 국 버림이 새 강 위로 날아가거나, 사건 꼬리 20개를 0.24초씩 5초 동안 되감는다.
        let m = Self.motion()
        #expect(m.applies(matchID: "m", handIndex: 2))
        #expect(!m.applies(matchID: "other", handIndex: 2) && !m.applies(matchID: "m", handIndex: 3))
        for count in [1, 2, 6, 20, 80] {
            let each = MahjongMotion.duration(forTailCount: count)
            #expect(each <= MahjongMotion.defaultDuration)
            #expect(Double(count) * each <= MahjongMotion.catchUpWindow + 1e-9 || count == 1)
        }
    }

    @Test("스토어 — 새 버림 사건이 응답으로 온 뒤에 시작(자리 방위대로) · 첫 적용·다른 국은 움직임 없음")
    func storeStartsMotionAfterTheResponse() throws {
        // 없으면: 낙관적으로 미리 날리거나(①), 판을 처음 열 때 지난 사건 꼬리 전부를 다시 날린다.
        let clock = MJClock()
        let store = MahjongStore(clock: { clock.now })
        store.applyState(try MJFixture.state("mahjong_start__ok"))
        #expect(store.motion == nil, "첫 적용은 움직임 없음")
        clock.now = clock.now.addingTimeInterval(2)
        store.applyState(try MJFixture.state("mahjong_state__their_turn"))
        let m = try #require(store.motion)
        #expect(m.kind == .discard && m.seq == 3 && m.from == .init(compass: .bottom, area: .hand))
        #expect(m.to == .init(compass: .bottom, area: .river) && m.startedAt == clock.now && m.handIndex == 0)
        store.applyState(try MJFixture.state("mahjong_state__call_prompt"))
        #expect(store.motion?.seq == 5 && store.motion?.from.compass == .right, "하가(1)의 버림은 오른쪽에서")
        // 다른 국(버림 사건 셋이 든 첫 적용) — 옛 국 움직임 그대로, 새로 만들지 않는다.
        store.applyState(try MJFixture.state("mahjong_state__my_turn_hand2"))
        #expect(store.motion?.seq == 5, "다른 국 첫 적용은 새 움직임을 만들지 않는다")
        #expect(store.motion?.applies(matchID: store.match?.match?.id, handIndex: store.match?.match?.handIndex) == false)
    }
}
