import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

// 폰 [나] 탭 잔디 — 공유 Codex 계정 분배 (v0.3.36)
//
// 결함: `MeStoreRecords` 가 `TokenDailyMerge.serverTotals` 를 **비율 인자 없이** 불러, 서버 계정 버킷
// (= 공유 그룹 **전체**의 하루 사용량)이 그대로 '내 잔디'가 됐다. 맥은 같은 함수를 `WorkTimerStoreInsights` 에서
// `accountShareRatio:` 와 함께 부른다 — 폰에만 빠져 있었다(2026-09-22 조사 기준 공유 11명 오차 1.05~19.15배).
//
// 폰은 맥과 **분모가 다르다**: 폰에는 로컬 스캐너가 없어 `CodexAccountUsage` 가 아예 없다. 그래서 분모를
// 서버 일별 계정 버킷의 이번 달 합(`TokenDailyMerge.accountBucketSum`)으로 만든다.
//
// 이 파일이 지키는 것: ⓐ 게이트(분모 0·수집 꺼짐·일별 실패면 **왕복 0건**) · ⓑ 적용(비율이 계정 칸에만 걸린다) ·
// ⓒ 실패 갈래 전부가 `.keep`(캐시를 지킨다 — 1.0 으로 되돌리면 정확하던 잔디가 최대 19배로 되부푼다) ·
// ⓓ 스로틀·영속·계정 격리.

@MainActor
@Suite("나 탭 잔디 공유 비율(v0.3.36)")
struct MeTokenShareTests {
    nonisolated static let me = RankMeFixture.userID

    /// 이번 달 계정 버킷 합 1,000(09-10 = 800 · 09-11 = 200), 09-11 의 로컬 꼬리 40.
    /// 비율 0.25 면 잔디 = 200(09-10) + max(50, 40)(09-11) = 250 = 보드가 준 내 몫.
    nonisolated static let sharedDaily = #"""
    [{"day":"2026-09-10","device_id":"mac-1","claude_total":0,"codex_total":0,"codex_utc_total":0,"codex_account":800},
     {"day":"2026-09-11","device_id":"mac-1","claude_total":0,"codex_total":40,"codex_utc_total":40,"codex_account":200}]
    """#

    /// 계정 버킷이 하나도 없는 일별(맥이 Codex 에 로그인한 적 없음).
    nonisolated static let noAccountDaily = #"""
    [{"day":"2026-09-10","device_id":"mac-1","claude_total":30000,"codex_total":500,"codex_utc_total":500,"codex_account":null}]
    """#

    /// 이번 달 버킷은 0 이고 **지난 달**만 버킷이 있다(분모 0 → 비율이 어차피 1.0).
    nonisolated static let lastMonthOnlyDaily = #"""
    [{"day":"2026-08-30","device_id":"mac-1","claude_total":0,"codex_total":0,"codex_utc_total":0,"codex_account":900},
     {"day":"2026-09-10","device_id":"mac-1","claude_total":0,"codex_total":70,"codex_utc_total":70,"codex_account":null}]
    """#

    /// 보드 응답 한 줄. `share` 는 `codex_account_month`(= 이미 나눈 내 몫), `effective` 는 `codex_effective`.
    /// `effective` 가 nil 이면 그 키를 **빼서** 옛 RPC 응답을 만든다(`TokenRowServerValue` 가드가 탈락해야 한다).
    nonisolated static func board(share: String, effective: String? = "300", user: String = me) -> String {
        let effectiveJSON = effective.map { "\"codex_effective\":\($0)," } ?? ""
        return #"""
        [{"user_id":"\#(user)","display_name":"나","avatar_url":null,
          "claude_input":0,"claude_output":0,"claude_cache_read":0,"claude_cache_creation":0,
          "codex_input":0,"codex_output":0,"total":1000,
          "today_total":0,"today_date":"2026-09-17","codex_cache_read":0,
          "codex_account_month":\#(share),\#(effectiveJSON)"center":null}]
        """#
    }

    /// 기록 조회에 필요한 최소 응답기. `daily` 와 `board` 만 갈아 끼운다.
    nonisolated static func responder(
        daily: String, board: String?, collects: Bool = true, boardStatus: Int = 200
    ) -> @Sendable (MobileStubRequest) -> MobileStubResponse? {
        { request in
            if request.path == "/rest/v1/profiles", request.method == "GET" {
                if request.query.contains("token_usage_collect") {
                    return .json(#"[{"token_usage_public":true,"token_usage_collect":\#(collects),"focus_mode":false}]"#)
                }
            }
            if request.path == "/rest/v1/work_sessions", request.method == "GET" { return .json("[]") }
            if request.path == "/rest/v1/token_usage_device_daily", request.method == "GET" { return .json(daily) }
            if request.rpcName == "token_usage_board" {
                guard let board else { return .json(#"{"message":"boom"}"#, status: boardStatus) }
                return .json(board, status: boardStatus)
            }
            return nil
        }
    }

    func boardCount(_ harness: RankMeHarness) -> Int { harness.requests(rpc: "token_usage_board").count }

    // MARK: - ⓐ 게이트: 분모가 없으면 무거운 보드 RPC 를 한 번도 안 쏜다

    @Test("게이트: 계정 버킷이 전부 null 이면 보드 요청 0건 — Codex 계정이 없는 사람은 이 RPC 를 모른다")
    func noAccountBucketsMeansNoBoardCall() async throws {
        let harness = await RankMeHarness(label: "share-gate-null",
                                          responder: Self.responder(daily: Self.noAccountDaily, board: Self.board(share: "250")))
        defer { harness.tearDown() }
        await harness.me.loadRecords()
        #expect(boardCount(harness) == 0, "분모가 없는데 보드를 쐈다")
        #expect(harness.me.tokenShareRatio == nil)
        #expect(harness.me.lastTokenBoardFetchAt == nil)
        // 잔디는 그대로 그려진다(비율은 쓰일 자리가 없다).
        #expect(harness.me.tokenGrid.totalTokens == 30_500)
    }

    @Test("게이트: 이번 달 버킷이 0 이고 지난 달만 있으면 요청 0건 + 캐시 비율 유지")
    func lastMonthBucketsDoNotOpenTheBoard() async throws {
        let harness = await RankMeHarness(label: "share-gate-lastmonth",
                                          responder: Self.responder(daily: Self.lastMonthOnlyDaily, board: Self.board(share: "250")))
        defer { harness.tearDown() }
        harness.me.tokenShareRatio = 0.4
        await harness.me.loadRecords()
        #expect(boardCount(harness) == 0)
        #expect(harness.me.tokenShareRatio == 0.4, "게이트에 걸린 갈래가 캐시를 건드렸다")
    }

    @Test("게이트: 수집을 끄면 요청 0건이고 잔디는 비어 있다")
    func collectionOffMeansNoBoardCall() async throws {
        let harness = await RankMeHarness(label: "share-gate-off",
                                          responder: Self.responder(daily: Self.sharedDaily, board: Self.board(share: "250"), collects: false))
        defer { harness.tearDown() }
        await harness.me.loadRecords()
        #expect(boardCount(harness) == 0)
        #expect(harness.me.tokenGrid.totalTokens == 0)
        #expect(!harness.me.showsTokenGrid)
    }

    // MARK: - ⓑ 적용: 비율은 계정 칸에만 걸린다

    @Test("적용: 버킷 합 1,000 · 내 몫 250 이면 비율 0.25 이고 잔디의 계정 칸이 1/4 로 줄어든다")
    func boardShareShrinksTheAccountCells() async throws {
        let harness = await RankMeHarness(label: "share-apply",
                                          responder: Self.responder(daily: Self.sharedDaily, board: Self.board(share: "250")))
        defer { harness.tearDown() }
        await harness.me.loadRecords()
        #expect(boardCount(harness) == 1)
        #expect(harness.me.tokenShareRatio == 0.25)
        // 200(09-10, 반영된 날) + max(50, 로컬 40)(09-11, 마지막 버킷 날) = 250 = 보드가 준 내 몫.
        #expect(harness.me.tokenGrid.totalTokens == 250, "잔디 합 \(harness.me.tokenGrid.totalTokens) — 수리 전이면 1,000(계정 전체)")
        #expect(!harness.me.recordsState.hasFailed)
        // 보드 요청이 이번 달로 나갔다(‹ › 로 움직이는 순위 탭의 달을 물려받지 않는다).
        let sent = try #require(harness.requests(rpc: "token_usage_board").first)
        #expect(sent.jsonBody["p_month"] as? String == "2026-09")
        harness.expectNoForbiddenCalls()
    }

    @Test("적용: 내 몫 0 은 nil 과 다르다 — 비율 0, 계정 칸 0, 로컬 꼬리만 남는다")
    func zeroShareIsNotNil() async throws {
        let harness = await RankMeHarness(label: "share-zero",
                                          responder: Self.responder(daily: Self.sharedDaily, board: Self.board(share: "0")))
        defer { harness.tearDown() }
        await harness.me.loadRecords()
        #expect(harness.me.tokenShareRatio == 0.0, "0 을 nil 로 접어 1.0 으로 올렸다")
        #expect(harness.me.tokenGrid.totalTokens == 40, "계정 칸이 0 이 아니거나 로컬 꼬리가 사라졌다")
    }

    // MARK: - ⓒ 실패 갈래: 전부 캐시를 지킨다(아무것도 비우지 않는다)

    @Test("보드 5xx: 캐시 비율 유지 · 잔디 안 비움 · hasFailed 는 서지 않는다")
    func boardFailureKeepsTheCachedRatio() async throws {
        let harness = await RankMeHarness(label: "share-5xx",
                                          responder: Self.responder(daily: Self.sharedDaily, board: nil, boardStatus: 503))
        defer { harness.tearDown() }
        harness.me.tokenShareRatio = 0.25
        await harness.me.loadRecords()
        #expect(boardCount(harness) >= 1)
        #expect(harness.me.tokenShareRatio == 0.25, "실패가 정확하던 비율을 1.0 으로 되돌렸다")
        #expect(harness.me.tokenGrid.totalTokens == 250)
        #expect(!harness.me.recordsState.hasFailed, "비율 조회 실패로 기록 전체가 빨개졌다")
        // 도장은 남는다 — 300초 뒤에 다시 시도한다.
        #expect(harness.me.lastTokenBoardFetchAt != nil)
    }

    @Test("옛 RPC(codex_effective 칸 없음): 가드 탈락 → 캐시 유지, 폐기된 max 값으로 비율을 만들지 않는다")
    func legacyRPCNeverBuildsARatio() async throws {
        let harness = await RankMeHarness(label: "share-legacy",
                                          responder: Self.responder(daily: Self.sharedDaily,
                                                                    board: Self.board(share: "250", effective: nil)))
        defer { harness.tearDown() }
        harness.me.tokenShareRatio = 0.5
        await harness.me.loadRecords()
        #expect(boardCount(harness) == 1)
        #expect(harness.me.tokenShareRatio == 0.5, "옛 RPC 행으로 비율을 만들었다")
    }

    @Test("내 행 없음 · 몫 null: 캐시가 있으면 유지, 없으면 1.0(잔디 무변화)")
    func missingRowOrNullShareKeepsTheCache() async throws {
        for (label, board) in [("남의 행만", Self.board(share: "250", user: "u-someone-else")),
                               ("몫 null", Self.board(share: "null"))] {
            let cached = await RankMeHarness(label: "share-keep-\(label.count)",
                                             responder: Self.responder(daily: Self.sharedDaily, board: board))
            defer { cached.tearDown() }
            cached.me.tokenShareRatio = 0.25
            await cached.me.loadRecords()
            #expect(cached.me.tokenShareRatio == 0.25, "\(label): 캐시를 1.0 으로 덮었다")
            #expect(cached.me.tokenGrid.totalTokens == 250)

            let fresh = await RankMeHarness(label: "share-fresh-\(label.count)",
                                            responder: Self.responder(daily: Self.sharedDaily, board: board))
            defer { fresh.tearDown() }
            await fresh.me.loadRecords()
            #expect(fresh.me.tokenShareRatio == nil, "\(label): 증거가 없는데 값을 지어냈다")
            #expect(fresh.me.tokenGrid.totalTokens == 1_000, "\(label): 첫 로드의 잔디가 오늘 동작과 다르다")
        }
    }

    @Test("취소: 비율이 1.0 으로 되돌아가지 않고, 도장이 비워져 다음 진입에 바로 재시도한다")
    func cancellationKeepsTheRatioAndClearsTheStamp() async throws {
        var hold: BaseHold?
        let harness = await RankMeHarness(label: "share-cancel", beforeStart: { host in
            hold = BaseHold.install(host: host) { $0.rpcName == "token_usage_board" }
        }, responder: Self.responder(daily: Self.sharedDaily, board: Self.board(share: "250")))
        defer { harness.tearDown() }
        let held = try #require(hold)
        harness.me.tokenShareRatio = 0.25

        let task = Task { @MainActor in await harness.me.loadRecords() }
        #expect(await held.waitHeld(), "보드 요청이 뜨지 않았다")
        task.cancel()
        _ = await held.releaseAndWaitDelivered()
        await task.value

        #expect(harness.me.tokenShareRatio == 0.25, "취소가 비율을 되돌렸다")
        #expect(harness.me.lastTokenBoardFetchAt == nil, "취소가 300초 동안 재시도를 잠갔다")
    }

    @Test("달 재확인: 응답이 오는 사이 달이 바뀌면 그 응답을 버리고 캐시를 지킨다")
    func monthRolloverDiscardsTheResponse() async throws {
        var hold: BaseHold?
        let harness = await RankMeHarness(label: "share-month", beforeStart: { host in
            hold = BaseHold.install(host: host) { $0.rpcName == "token_usage_board" }
        }, responder: Self.responder(daily: Self.sharedDaily, board: Self.board(share: "250")))
        defer { harness.tearDown() }
        let held = try #require(hold)
        harness.me.tokenShareRatio = 0.5

        let task = Task { @MainActor in await harness.me.loadRecords() }
        #expect(await held.waitHeld())
        harness.clock.advance(86_400 * 20)   // 2026-09-17 → 10-07: 달이 넘어갔다
        _ = await held.releaseAndWaitDelivered()
        await task.value

        #expect(harness.me.tokenShareRatio == 0.5, "다른 달의 비율을 받아 썼다")
        #expect(harness.me.lastTokenBoardFetchAt == nil, "버린 왕복이 도장을 남겨 300초를 잠갔다")
    }

    // MARK: - ⓓ 스로틀 · 영속 · 계정 격리

    @Test("스로틀: 연속 두 번은 보드 1건, 301초 뒤에는 2건")
    func boardIsThrottledForFiveMinutes() async throws {
        let harness = await RankMeHarness(label: "share-throttle",
                                          responder: Self.responder(daily: Self.sharedDaily, board: Self.board(share: "250")))
        defer { harness.tearDown() }
        await harness.me.loadRecords()
        await harness.me.loadRecords()
        #expect(boardCount(harness) == 1, "300초 안에 같은 무거운 RPC 를 두 번 쐈다")
        harness.clock.advance(301)
        await harness.me.loadRecords()
        #expect(boardCount(harness) == 2)
    }

    @Test("영속: 같은 계정으로 스토어를 새로 만들면 첫 계산부터 저장된 비율이 걸린다")
    func ratioSurvivesARelaunch() async throws {
        let harness = await RankMeHarness(label: "share-persist",
                                          responder: Self.responder(daily: Self.sharedDaily, board: Self.board(share: "250")))
        defer { harness.tearDown() }
        await harness.me.loadRecords()
        #expect(harness.me.tokenShareRatio == 0.25)
        let key = "aing.me.codexShareRatio.\(Self.me)"
        #expect(harness.storage.defaults.object(forKey: key) as? Double == 0.25)
        // 계정별 키다 — 다른 사람의 비율로 내 잔디가 깎이지 않는다.
        #expect(harness.storage.defaults.object(forKey: "aing.me.codexShareRatio.u-someone-else") == nil)

        // 새 스토어 = 앱 재실행. 보드가 실패해도 저장본이 첫 계산에 걸린다(부푼 잔디가 떴다가 내려앉지 않게).
        let relaunched = MeStore(context: harness.model.context)
        await relaunched.loadRecords()
        #expect(relaunched.tokenShareRatio == 0.25)
        #expect(relaunched.tokenGrid.totalTokens == 250, "저장본이 첫 계산에 안 걸려 잔디가 1,000 으로 떴다")
    }

    @Test("reset(): 비율·도장이 비워진다 — 계정을 바꾼 뒤 앞 사람 비율로 내 잔디가 깎이지 않게")
    func resetClearsTheRatio() async throws {
        let harness = await RankMeHarness(label: "share-reset",
                                          responder: Self.responder(daily: Self.sharedDaily, board: Self.board(share: "250")))
        defer { harness.tearDown() }
        await harness.me.loadRecords()
        #expect(harness.me.tokenShareRatio == 0.25)
        #expect(harness.me.lastTokenBoardFetchAt != nil)
        harness.me.reset()
        #expect(harness.me.tokenShareRatio == nil)
        #expect(harness.me.lastTokenBoardFetchAt == nil)
    }
}
