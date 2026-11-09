import Foundation
import Testing
@testable import check
@testable import CheckCore

// 없으면: 끝난 판이 남은 채 온 신청의 [수락]·[거절]이 조용히 사라지고(RV2-C-1) · 굴림을 본 뒤의 차례 말풍선에서 쏜 사람 이름이 빠지고
// (RV2-C-2) · 숨은 창이 굴림 끝에 서버를 안 불러 다음 차례가 매분 훑기까지 안 열리고(RV2-C-3) · 끝난 판 관전이 꼬리 180초 내내
// 2초마다 서버를 두드려도(RV2-C-4) 초록으로 통과한다. 1:1 알까기 v2 적대 검토(갈래 C · U · T)가 실패하는 시험으로 증명한 결함의 회귀 시험.
// 시험대(`AKScript` · `AK` · `akEventually`)는 V03xxAlkkagiStoreTests.swift 의 것을 그대로 빌린다.
// 각 시험은 결함 자리와 결과가 갈리는 기준선 짝을 함께 잰다(고치기 전: 기준선 초록 · 결함 자리 빨강 — 검토 갈래가 확인).

@MainActor
@Suite(.serialized)
struct V03xxAlkkagiReviewTests {
    // MARK: RV2-C-1 — 떠나지 않은 끝난 판이 받은 신청 응답을 조용히 삼킨다

    /// 창을 닫은 채 판이 끝나면(시간패 · 상대 판 밖 승) 스토어는 그 끝난 판을 `state` 로 계속 든다(서버 로비도 left_at null 인 끝난 판을
    /// 다시 싣는다 — 20261110160000 §8 lobby 의 `a.is_active or g.status = 'finished'`). 그 사이 온 신청은 배너 · 말풍선 · 메뉴바 점으로
    /// 보이는데, [수락]·[거절] 이 `respond` 의 `state == nil` 가드에 걸려 **서버를 부르지 않고 안내도 없이** 돌아간다(배너 [수락]은
    /// 창만 연다 — 결과 카드). 길건너 · 뒤집기 `respond` 는 판 유무를 보지 않는다(CC/CrossyDuelStore.swift:969-970 ·
    /// CC/ReversiStore.swift:1144-1145). 기준선: 끝난 판이 없으면 같은 누름이 서버를 1번 부른다.
    @Test("RV2-C-1 끝난 판이 남아 있어도 배너 [수락]·[거절]이 서버에 닿는다")
    func lingeringFinishedMatchDoesNotSwallowRespond() async throws {
        var leaves = -1
        func respondCalls(withFinished: Bool, accept: Bool) async throws -> (calls: Int, bannerVisible: Bool) {
            let invite = AK.invite(id: AK.inviteID)
            let finished = AK.match(phase: .finished, revision: 9, stake: 5, result: .white, reason: "timeout")
            let script = AKScript(fallback: { call in
                switch call {
                case .lobby: return AK.lobby(incoming: [invite], state: withFinished ? finished : nil)
                case .respond: return AK.response(status: .ok)
                default: return AK.response()
                }
            })
            let store = AK.store(script)
            defer { store.reset(); script.finish() }
            await store.refreshLightLobby()
            let banner = store.visibleIncoming?.id == invite.id
            await store.respond(inviteID: invite.id, accept: accept)
            leaves = script.count("alkkagi_leave")
            return (script.count("alkkagi_respond"), banner)
        }
        // 기준선 — 끝난 판 없음: 누름 하나 = 서버 한 번.
        let base = try await respondCalls(withFinished: false, accept: true)
        #expect(base.bannerVisible && base.calls == 1)
        #expect(leaves == 0, "끝난 판이 없으면 떠나기를 부르지 않는다")
        // 결함 자리 — 끝난 판이 남음: 배너는 보이는데 누름이 서버에 안 닿는다.
        let accepted = try await respondCalls(withFinished: true, accept: true)
        #expect(accepted.bannerVisible, "배너가 안 보이면 이 시험은 뜻이 없다")
        #expect(accepted.calls == 1, "끝난 판이 남아 배너 [수락]이 서버를 부르지 않았다(안내도 없음)")
        #expect(leaves == 1, "수락 전에 끝난 판을 떠나야 새 판이 끝난 뒤 서버 로비가 옛 결과를 다시 싣지 않는다")
        let declined = try await respondCalls(withFinished: true, accept: false)
        #expect(declined.calls == 1, "끝난 판이 남아 배너 [거절]이 서버를 부르지 않았다(배너가 그대로 남는다)")
        #expect(leaves == 0, "거절은 결과 카드를 그대로 둔다(떠나지 않는다)")
    }

    // MARK: RV2-C-2 — 상대가 쏴서 넘어온 차례 말풍선에서 이름이 빠진다

    /// 서버는 쏘는 순간 `shot_count` 를 올리고 `rolling` 을 낸다(20261110160000:1006 · 픽스처 alkkagi_state__rolling = shot_count 1).
    /// 받는 쪽은 신호로 그 `rolling` 을 먼저 보고, 굴림이 끝난 뒤 `aiming`(같은 shot_count · 같은 shot)을 본다. 스토어는 '상대가 쐈다'를
    /// `next.shotCount > old.shotCount` 로 재므로 직전 상태(rolling)와 수가 같아 이름 없는 꼴("알까기 내 차례예요")로 운다 — SPEC §5.8 의
    /// "{이름}님이 쐈어요 · 알까기 내 차례예요" 는 rolling 을 건너뛴 때만 나온다(기존 시험 myTurnAttentionOnEveryEntry 가 그 길만 잰다).
    /// 기준선: rolling 을 건너뛰면 이름이 실린다.
    @Test("RV2-C-2 상대 쏘기 → 굴림 → 내 차례: 차례 말풍선에 상대 이름")
    func opponentShotSeenThroughRollingKeepsTheName() async throws {
        func lastAttention(seeRolling: Bool) async throws -> AlkkagiAttention? {
            let theirs = AK.match(current: .white, revision: 4, shotCount: 1)
            var rolling = AK.match(phase: .rolling, current: .white, revision: 5, shotCount: 2)
            rolling.shot = AK.shot(by: 5, on: theirs)                                 // 백(상대)의 돌
            var mine = AK.match(current: .black, revision: 6, shotCount: 2)
            mine.shot = rolling.shot                                                  // 서버는 굴림 뒤에도 shot 을 남긴다
            let sequence = seeRolling ? [theirs, rolling, mine] : [theirs, mine]
            let script = AKScript(sequence.map { AKScript.Reply.response(AK.response($0)) },
                                  fallback: { _ in AK.response() })
            let store = AK.store(script)
            defer { store.reset(); script.finish() }
            var seen: [AlkkagiAttention] = []
            store.onAttention = { seen.append($0) }
            await store.refreshLobby()
            for _ in 1..<sequence.count { await store.refreshMatch() }
            return seen.last
        }
        let skipped = try #require(try await lastAttention(seeRolling: false))
        #expect(skipped.kind == .myTurn && skipped.opponentName == "White")          // 기준선
        let viaRolling = try #require(try await lastAttention(seeRolling: true))
        #expect(viaRolling.kind == .myTurn)
        #expect(viaRolling.opponentName == "White", "굴림을 본 뒤의 차례 말풍선에서 쏜 사람 이름이 빠졌다")
    }

    // MARK: RV2-C-3 — 숨거나 가려진 창은 굴림 끝에 서버를 찌르지 않는다(내 차례가 늦게 열리거나 놓친 차례로 셈)

    /// 알까기는 차례제 다섯 중 유일하게 **굴림이 끝나야** 다음 차례가 열린다 — 그 전이는 누군가 state · 로비를 불러야(`alk_advance`)
    /// 일어난다. 쏜 사람이 쏘자마자 창을 가리거나(굴림 약 1.4초 안) 닫으면 그쪽 마감 새로고침이 취소되고(`stopPolling`), 받는 쪽은 창이
    /// 숨어 있어 `scheduleDeadlineRefresh` 가 아예 서지 않는다 → 매분 훑기(`alk_sweep` 자리 36, 0~60초 늦음)가 굴림을 끝낸다. 그때 다음 마감은
    /// `roll_until + 30초`(20261110160000:621)라 훑기가 32초 넘게 늦으면 같은 고리(:626-640)가 받는 사람의 놓친 차례를 바로 센다 —
    /// 말풍선 한 번 없이(VC-20 의 목적 '가려진 창에서 놓친 차례 셋 = 판돈 잃음'을 정면으로 친다).
    /// 기준선: 보이는 창은 굴림 끝에 한 번 부른다.
    @Test("RV2-C-3 숨은 창도 굴림 끝에 한 번 판 상태를 부른다(다음 차례를 서버가 연다)")
    func hiddenWindowStillPokesAtRollEnd() async throws {
        func stateCallsAfterRoll(visible: Bool) async throws -> Int {
            var rolling = AK.match(phase: .rolling, current: .black, revision: 5, shotCount: 1)
            rolling.shot = AlkkagiShot(id: "shot-short", stoneID: 0, pull: AK.vector(0, 80), startedAtMs: AK.nowMs,
                                       steps: 24, initialStones: rolling.stones)            // 0.1초 굴림
            let script = AKScript(fallback: { _ in AK.response(rolling) })
            let store = AK.store(script)
            defer { store.reset(); script.finish() }
            if visible { store.isWindowVisible = true }
            await store.refreshLightLobby()
            try await akEventually { !store.isLoading }
            let base = script.count("alkkagi_state")
            try await Task.sleep(for: .milliseconds(600))
            return script.count("alkkagi_state") - base
        }
        #expect(try await stateCallsAfterRoll(visible: true) >= 1)                           // 기준선
        #expect(try await stateCallsAfterRoll(visible: false) >= 1,
                "숨은 창이 굴림 끝에 서버를 찌르지 않는다 — 다음 차례가 매분 훑기까지 안 열린다")
    }

    /// 쏜 사람이 굴림 중에 창을 닫거나(가리거나) 내리면 `stopPolling` 이 마감 새로고침을 취소한다 — 굴림 끝 한 번은 다시 세워야 한다.
    /// 기준선: 숨은 창의 **조준 마감**은 그대로 부르지 않는다(완화는 굴림 끝 한 번뿐 — 다섯 규칙의 '숨은 창 조회 0' 은 그대로).
    @Test("RV2-C-3 굴림 중에 창을 내리거나 가려도 굴림 끝 한 번 · 숨은 창의 조준 마감은 부르지 않음")
    func hidingDuringRollStillPokesButAimDeadlineDoesNot() async throws {
        enum Hide { case close, occlude }
        func stateCallsAfterHidingMidRoll(_ hide: Hide) async throws -> Int {
            var rolling = AK.match(phase: .rolling, current: .black, revision: 5, shotCount: 1)
            rolling.shot = AlkkagiShot(id: "shot-mid", stoneID: 0, pull: AK.vector(0, 80), startedAtMs: AK.nowMs,
                                       steps: 96, initialStones: rolling.stones)            // 0.4초 굴림
            let script = AKScript(fallback: { _ in AK.response(rolling) })
            let store = AK.store(script)
            defer { store.reset(); script.finish() }
            store.isWindowVisible = true
            await store.refreshLightLobby()
            try await akEventually { !store.isLoading }
            switch hide {
            case .close: store.windowDidHide()
            case .occlude: store.windowOcclusionDidChange(visible: false)
            }
            let base = script.count("alkkagi_state")
            try await Task.sleep(for: .milliseconds(900))
            return script.count("alkkagi_state") - base
        }
        func stateCallsAtHiddenAimDeadline() async throws -> Int {
            let aiming = AK.match(phase: .aiming, current: .white, revision: 5, deadlineMs: AK.nowMs + 100)
            let script = AKScript(fallback: { _ in AK.response(aiming) })
            let store = AK.store(script)
            defer { store.reset(); script.finish() }
            await store.refreshLightLobby()
            try await akEventually { !store.isLoading }
            let base = script.count("alkkagi_state")
            try await Task.sleep(for: .milliseconds(600))
            return script.count("alkkagi_state") - base
        }
        #expect(try await stateCallsAfterHidingMidRoll(.close) >= 1, "굴림 중 창을 내리면 굴림 끝 새로고침이 사라진다")
        #expect(try await stateCallsAfterHidingMidRoll(.occlude) >= 1, "굴림 중 창이 가려지면 굴림 끝 새로고침이 사라진다")
        #expect(try await stateCallsAtHiddenAimDeadline() == 0, "숨은 창이 조준 마감에 서버를 불렀다 — 완화가 굴림 밖으로 샜다")
    }

    // MARK: RV2-C-4 — 끝난 판 관전이 꼬리 180초 내내 2초마다 서버를 두드린다

    /// 뒤집기 관전은 끝난 판이면 걸음을 멈추고 결과를 [나가기]까지 둔다(`ReversiStoreWatch.shouldPollWatch` —
    /// CC/ReversiStoreWatch.swift:141-144 `!watch.isFinished`). 알까기는 끝난 판에도 `alkkagi_watch_live` 를 2초마다 불러
    /// (관전자 하나당 최대 90번 · 매번 `match_watch_ping` 쓰기) 꼬리가 끝나 `not_found` 가 오면 결과 화면을 말없이 로비로 걷는다.
    /// 기준선: 진행 중인 판은 2초 뒤 한 번 더 부른다.
    @Test("RV2-C-4 끝난 판 관전은 결과를 받은 뒤 더 부르지 않는다")
    func finishedWatchStopsPolling() async throws {
        func watchCalls(finished: Bool) async throws -> Int {
            let watchID = "00000000-0000-4000-8000-0000000000bb"
            let snapshot = AlkkagiWatchState(id: watchID, revision: 9, phase: finished ? .finished : .aiming,
                                             black: AK.black, white: AK.white, blackReady: true, whiteReady: true,
                                             deadlineMs: finished ? nil : AK.nowMs + 30_000,
                                             result: finished ? .black : nil, finishReason: finished ? "ring_out" : nil,
                                             stake: 5, finishedAtMs: finished ? AK.nowMs : nil, watchers: 1)
            let script = AKScript(fallback: { _ in AlkkagiResponse(status: .ok, serverNowMs: AK.nowMs, watch: snapshot) })
            let store = AK.store(script)
            defer { store.reset(); script.finish() }
            store.spectatorFeaturesEnabled = true
            store.isWindowVisible = true
            store.watch(matchID: watchID)
            try await akEventually { store.watched != nil }
            try await Task.sleep(for: .milliseconds(2_400))
            return script.count("alkkagi_watch_live")
        }
        #expect(try await watchCalls(finished: false) >= 2)                                   // 기준선
        #expect(try await watchCalls(finished: true) == 1, "끝난 판인데도 관전 걸음이 계속 서버를 부른다")
    }
}
