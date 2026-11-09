import Foundation
import Testing
@testable import CheckCore

// 1:1 알까기 관전(SPEC v1.1 §3.5 `alkkagi_watch_live` · §3.7 WATCH · §4.5 · §7.2 C 줄 Watch). **결과를 잰다.**
// 관전 2초 · 배치 중 돌 0 · 끝난 판 꼬리(결과까지) · stopWatching · 스위치 꺼짐이면 부르지 않음 · 내 판이 서면 내림 ·
// 서버에 관전 함수가 없으면 내림 · 늦은 응답(다른 판 · 옛 revision)은 버림. 시험대(AKScript · AK · akFixture)는 Store 시험 파일.

@MainActor
@Suite(.serialized)
struct V03xxAlkkagiWatchTests {
    private static let liveID = "00000000-0000-4000-8000-0000000000bb"

    /// 없으면: [관전] 을 눌러도 첫 조회가 2초 뒤에야 나가거나, 숨긴 배치 중에 돌이 새어 나와도(관전자가 두 사람 돌을 다 봄) 초록이다.
    @Test("관전 시작 — 첫 조회는 바로(watch_live) · 배치 중 돌 [] · 관전자 수 · 판돈")
    func watchStartsWithAnImmediateLiveCall() async throws {
        let script = AKScript([.response(try akFixture("alkkagi_watch_live__placing"))],
                              fallback: { _ in try? akFixture("alkkagi_watch_live__placing") })
        let store = AK.store(script)
        defer { store.reset(); script.finish() }
        store.spectatorFeaturesEnabled = true
        store.watch(matchID: Self.liveID)
        try await akEventually { store.watched != nil }
        #expect(script.calls.first == .watchLive(matchID: UUID(uuidString: Self.liveID)))
        let watched = try #require(store.watched)
        #expect(watched.phase == .placing && watched.stones.isEmpty, "숨긴 배치 중 돌이 보인다")
        #expect(watched.watchers == 1 && watched.stake == 5 && watched.whiteMissedTurns == 1 && !watched.isFinished)
        // 기준선: 숨긴 배치가 아닌 판은 돌이 실린다(같은 디코더 — 그래서 위 단언이 갈린다).
        #expect(try #require(try akFixture("alkkagi_watch_live__finished").watch).stones.count == 10)
    }

    /// 없으면: 관전 걸음이 2초가 아니거나(다수 값) 가려진 · 숨은 창에서도 2초마다 서버를 두드려도 초록이다.
    @Test("관전 걸음 2초 — 창이 안 보이면 쉰다(조회 0) · 보이면 2초마다")
    func watchStepsEveryTwoSecondsOnlyWhileVisible() async throws {
        let script = AKScript(fallback: { _ in try? akFixture("alkkagi_watch_live__placing") })
        let store = AK.store(script)
        defer { store.reset(); script.finish() }
        store.spectatorFeaturesEnabled = true
        store.watch(matchID: Self.liveID)                      // 창이 안 보인다 — 첫 조회만
        try await akEventually { script.calls.count == 1 }
        try await Task.sleep(for: .milliseconds(2_400))
        #expect(script.calls.count == 1, "숨은 창에서 관전 조회가 돌았다")
        store.isWindowVisible = true                           // 보인다 — 다음 걸음부터 조회
        try await akEventually(timeout: .milliseconds(2_600)) { script.calls.count == 2 }
        try await Task.sleep(for: .milliseconds(900))
        #expect(script.calls.count == 2, "2초보다 빨리 다시 불렀다")
        #expect(AlkkagiOnlineStore.watchPollSeconds == 2)
    }

    /// 없으면: 끝난 판이 꼬리(180초) 동안 결과를 못 보이거나, 꼬리가 지나 not_found 가 와도 관전 화면에 갇혀도 초록이다.
    @Test("끝난 판 꼬리 — 결과 · 사유까지 보인다 · not_found 면 관전을 내린다 · 옛 revision 은 버린다")
    func finishedTailThenNotFoundStopsWatching() async throws {
        let script = AKScript([.response(try akFixture("alkkagi_watch_live__finished"))])
        let store = AK.store(script)
        defer { store.reset(); script.finish() }
        store.spectatorFeaturesEnabled = true
        store.watch(matchID: Self.liveID)
        try await akEventually { store.watched != nil }
        let finished = try #require(store.watched)
        #expect(finished.isFinished && finished.result == .black && finished.endReason == .ringOut && finished.finishedAtMs != nil)
        let id = try #require(UUID(uuidString: Self.liveID))
        // 옛 revision(진행 중) 응답은 끝난 판을 되감지 않는다.
        var older = try #require(try akFixture("alkkagi_watch_live__placing").watch)
        older.revision = finished.revision - 1
        store.applyWatch(AlkkagiResponse(status: .ok, serverNowMs: AK.nowMs, watch: older), matchID: id,
                         generation: store.watchGeneration)
        #expect(store.watched == finished)
        store.applyWatch(try akFixture("alkkagi_watch__not_found"), matchID: id, generation: store.watchGeneration)
        #expect(store.watched == nil && store.watchTask == nil, "꼬리가 지난 판의 관전을 내리지 않았다")
    }

    /// 없으면: [로비로] 뒤에도 관전 걸음이 남아 서버를 두드리거나, 앞 판의 늦은 응답이 새로 고른 판 화면을 덮어도 초록이다.
    @Test("stopWatching · 판 바꾸기 — 걸음이 멈추고 앞 판의 늦은 응답은 버린다")
    func stopAndSwitchDropLateReplies() async throws {
        let other = "00000000-0000-4000-8000-0000000000dd"
        let script = AKScript([.suspended], fallback: { _ in try? akFixture("alkkagi_watch_live__finished") })
        let store = AK.store(script)
        defer { store.reset(); script.finish() }
        store.spectatorFeaturesEnabled = true
        store.watch(matchID: other)
        try await akEventually { script.isSuspended(0) }
        store.watch(matchID: Self.liveID)                      // 다른 판으로
        try await akEventually { store.watched?.id == Self.liveID }
        var stale = try #require(try akFixture("alkkagi_watch_live__placing").watch)
        stale.id = other
        script.resume(0, returning: AlkkagiResponse(status: .ok, serverNowMs: AK.nowMs, watch: stale))
        try await Task.sleep(for: .milliseconds(50))
        #expect(store.watched?.id == Self.liveID, "앞 판의 늦은 응답이 화면을 덮었다")
        store.stopWatching()
        #expect(store.watched == nil && store.watchTask == nil)
        let count = script.calls.count
        store.isWindowVisible = true
        try await Task.sleep(for: .milliseconds(2_300))
        #expect(script.calls.count == count, "멈춘 관전이 다시 불렀다")
    }

    /// 없으면: 관전 스위치가 꺼진 조립(시험 · 미리보기 · 배선 전)이 서버를 부르거나, 진행 중인 내 판이 있는데 남의 판을 보러 가거나,
    /// 관전 중 내 판이 서도 관전 화면이 판 화면을 가려도 초록이다.
    @Test("스위치 꺼짐이면 부르지 않음 · 내 판 진행 중이면 시작 안 함 · 내 판이 서면 관전을 내린다")
    func gatesSwitchAndOwnMatch() async throws {
        let script = AKScript(fallback: { call in
            if case .watchLive = call { return try? akFixture("alkkagi_watch_live__placing") }
            return AK.response(AK.match(phase: .placing))
        })
        let store = AK.store(script)
        defer { store.reset(); script.finish() }
        store.watch(matchID: Self.liveID)
        try await Task.sleep(for: .milliseconds(50))
        #expect(script.calls.isEmpty && store.watched == nil, "스위치가 꺼졌는데 관전을 불렀다")

        store.spectatorFeaturesEnabled = true
        store.watch(matchID: Self.liveID)
        try await akEventually { store.watched != nil }
        await store.refreshLobby()                             // 내 판(배치)이 섰다
        #expect(store.state != nil && store.watched == nil, "내 판이 섰는데 관전이 남았다")
        let count = script.calls.count
        store.watch(matchID: Self.liveID)
        try await Task.sleep(for: .milliseconds(50))
        #expect(script.calls.count == count && store.watched == nil, "진행 중인 내 판이 있는데 관전을 시작했다")
    }

    /// 없으면: 서버에 관전 함수가 아직 없을 때(PGRST202) 관전 걸음이 2초마다 404 를 두드려도 초록이다.
    @Test("서버에 관전 함수가 없으면(PGRST202) 관전을 내린다")
    func serverMissingStopsWatching() async throws {
        let script = AKScript([.failure(.serverMissing)])
        let store = AK.store(script)
        defer { store.reset(); script.finish() }
        store.spectatorFeaturesEnabled = true
        store.isWindowVisible = true
        store.watch(matchID: Self.liveID)
        try await akEventually { store.watchTask == nil }
        #expect(script.calls.count == 1 && store.watched == nil)
    }
}
