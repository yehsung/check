import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

#if canImport(AppKit)
import AppKit
#endif

/// 도전 미션 · 받기(서버 20261019120000 · 20261019121000 — 맥 0.3.58, 폰 배선) — `MeStore` 의 **진짜 경로**를 스텁 서버로 돈다:
/// `achievements_status` → 줄 · 받을 수 있는 수 → `achievement_claim` → 받음 · 루비 미러 · 연출, 그리고 `weekly_work_claim`.
///
/// 단언은 **결과를 값으로** 못 박는다(모양이 아니라): 겹친 받기의 뒤바뀐 답 · 늦은 응답의 잔액 · 함수 없는 서버 · 같은 턴 두 번 ·
/// 줄 안의 실패. 기대값은 손으로 적은 글자·숫자다(규칙 함수로 기대값을 다시 만들면 규칙이 틀려도 초록이다).
///
/// 이 스토어 파일들은 `#if os(iOS)` 밖이라 맥 `swift test` 가 진짜 경로를 돈다(`MeWeeklyWorkTests` 와 같은 자리).
@MainActor
@Suite("나 탭 도전 미션 · 받기(v0.3.58)")
struct MeAchievementClaimTests {
    // MARK: - 서버 계약 픽스처

    struct MissionDef: Sendable {
        let key: String
        let series: String
        let tier: Int
        let title: String
        let reward: Int
        let target: Int
        let sort: Int
    }

    /// 서버 정의표 그대로(`achievement_defs()`): 미션 13개 · 계열 9개.
    nonisolated static let defs: [MissionDef] = [
        .init(key: "phone_login", series: "phone_login", tier: 1, title: "폰 앱에서 로그인하기", reward: 50, target: 1, sort: 10),
        .init(key: "todo3", series: "todo3", tier: 1, title: "할 일 3개 이상 등록하기", reward: 20, target: 3, sort: 20),
        .init(key: "gomoku1", series: "gomoku1", tier: 1, title: "오목 한 판 두기", reward: 10, target: 1, sort: 30),
        .init(key: "chess1", series: "chess1", tier: 1, title: "체스 한 판 두기", reward: 10, target: 1, sort: 40),
        .init(key: "minigame3", series: "minigame3", tier: 1, title: "미니게임 3종 한 판씩 해보기", reward: 10, target: 3, sort: 50),
        .init(key: "poke10", series: "poke", tier: 1, title: "콕 찌르기 10회", reward: 5, target: 10, sort: 60),
        .init(key: "poke50", series: "poke", tier: 2, title: "콕 찌르기 50회", reward: 20, target: 50, sort: 70),
        .init(key: "poke100", series: "poke", tier: 3, title: "콕 찌르기 100회", reward: 50, target: 100, sort: 80),
        .init(key: "ultra5", series: "ultra5", tier: 1, title: "울트라 찌르기 5회", reward: 50, target: 5, sort: 90),
        .init(key: "team2", series: "team", tier: 1, title: "팀 2명 채우기", reward: 50, target: 2, sort: 100),
        .init(key: "team3", series: "team", tier: 2, title: "팀 3명 채우기", reward: 200, target: 3, sort: 110),
        .init(key: "streak14", series: "streak", tier: 1, title: "14일 연속 근무", reward: 30, target: 14, sort: 120),
        .init(key: "streak30", series: "streak", tier: 2, title: "30일 연속 근무", reward: 200, target: 30, sort: 130),
    ]

    /// `achievements_status()` · `achievement_claim()` 응답 한 벌.
    /// - achieved: 채웠고 아직 안 받은 키 · claimed: 받은 키(둘 다 progress = target).
    /// - claimedNow: 이 호출이 장부에 넣었다고 서버가 말한 키.
    /// - claimableCount/Ruby: 서버가 센 값(진단) — 일부러 틀리게 넣어 "줄에서 센다"를 재는 테스트가 있다.
    nonisolated static func status(achieved: Set<String> = [], claimed: Set<String> = [], progress: [String: Int] = [:],
                                   ruby: Int? = 1_000, claimedNow: [String] = [],
                                   claimableCount: Int? = nil, claimableRuby: Int? = nil,
                                   extra: [String] = []) -> String {
        let rows = defs.map { def -> String in
            let done = achieved.contains(def.key) || claimed.contains(def.key)
            let value = done ? def.target : min(progress[def.key] ?? 0, def.target)
            return #"{"key":"\#(def.key)","series":"\#(def.series)","tier":\#(def.tier),"title":"\#(def.title)","detail":"","reward":\#(def.reward),"target":\#(def.target),"progress":\#(value),"achieved":\#(done),"claimed":\#(claimed.contains(def.key)),"achieved_at_ms":\#(done ? "1789000000000" : "null"),"claimed_at_ms":\#(claimed.contains(def.key) ? "1789000000000" : "null"),"sort":\#(def.sort)}"#
        } + extra
        let now = claimedNow.compactMap { key in
            defs.first { $0.key == key }.map { #"{"key":"\#($0.key)","title":"\#($0.title)","reward":\#($0.reward)}"# }
        }
        let pending = defs.filter { achieved.contains($0.key) && !claimed.contains($0.key) }
        let count = claimableCount ?? pending.count
        let sum = claimableRuby ?? pending.reduce(0) { $0 + $1.reward }
        let balance = ruby.map { #","ruby_balance":\#($0)"# } ?? ""
        return #"{"launch_at_ms":1781000000000,"missions":[\#(rows.joined(separator: ","))],"claimable_count":\#(count),"claimable_ruby":\#(sum),"claimed_now":[\#(now.joined(separator: ","))]\#(balance),"server_now_ms":1789621500000}"#
    }

    /// `weekly_work_status()` · `weekly_work_claim()` 응답(v0.3.58 받기 서버 모양 — `supportsClaim: false` 면 옛 서버).
    nonisolated static func weekly(worked: Int, achieved: Set<Int> = [], claimed: Set<Int> = [], ruby: Int? = 1_000,
                                   claimedNow: [Int] = [], week: String = "2026-09-14", supportsClaim: Bool = true) -> String {
        let table = [(20, 20), (40, 50), (60, 200)]
        let tiers = table.map { hours, value -> String in
            let got = claimed.contains(hours)
            let done = got || achieved.contains(hours)
            guard supportsClaim else { return #"{"hours":\#(hours),"ruby":\#(value),"claimed":\#(got)}"# }
            return #"{"hours":\#(hours),"ruby":\#(value),"claimed":\#(got),"achieved":\#(done),"claimable":\#(done && !got)}"#
        }
        let pendingRows = table.filter { achieved.contains($0.0) && !claimed.contains($0.0) }
        let pending = pendingRows.map { #"{"week_start":"\#(week)","hours":\#($0.0),"ruby":\#($0.1)}"# }
        let nowRows = claimedNow.compactMap { hours in table.first { $0.0 == hours } }
        let now = nowRows.map { #"{"week_start":"\#(week)","hours":\#($0.0),"ruby":\#($0.1)}"# }
        let claimKeys = supportsClaim
            ? #","pending":[\#(pending.joined(separator: ","))],"claimable_ruby":\#(pendingRows.reduce(0) { $0 + $1.1 }),"claimed_now":[\#(now.joined(separator: ","))]"#
            : ""
        let balance = ruby.map { #","ruby_balance":\#($0)"# } ?? ""
        return #"{"week_start":"\#(week)","next_week_start":"2026-09-21","worked_seconds":\#(worked),"tiers":[\#(tiers.joined(separator: ","))],"granted_now":[]\#(balance),"server_now_ms":1789621500000\#(claimKeys)}"#
    }

    /// 나 탭이 보일 때 함께 나가는 조회(주간 · 상점)를 조용히 성공시키는 응답기 — 미션 조회만 세기 위한 것.
    nonisolated static func quietResponder(_ request: MobileStubRequest) -> MobileStubResponse? {
        switch request.rpcName {
        case "weekly_work_status": return .json(weekly(worked: 3_600, supportsClaim: false))
        case "shop_state": return .json(#"{"ruby_balance":1000,"characters":[]}"#)
        default: return nil
        }
    }

    // MARK: - 조회

    @Test("나 탭이 보이면 읽는다: POST 본문 {} · 계열 9줄(서버 제목·순서) · 받을 수는 줄에서 센다 · 루비 미러 · 60초 스로틀 · 금지 호출 0")
    func tabAppearLoadsRowsAndThrottles() async throws {
        let harness = await RankMeHarness(label: "me-ach-appear") { Self.quietResponder($0) }
        defer { harness.tearDown() }
        let store = harness.me
        #expect(store.achievementSection == .loading, "로그인만 한 상태에서 절이 벌써 \(store.achievementSection)")
        // 서버가 센 수(claimable_count)를 **일부러 틀리게** 싣는다 — 화면은 줄에서 세야 한다.
        harness.enqueue("achievements_status", .json(Self.status(achieved: ["poke10", "team2"], claimed: ["gomoku1"],
                                                                progress: ["poke50": 23, "streak14": 3], ruby: 1_234,
                                                                claimableCount: 99, claimableRuby: 9_999)))
        store.tabDidAppear()
        await harness.quiesceMe()

        let calls = harness.requests(rpc: "achievements_status")
        #expect(calls.count == 1)
        #expect(calls.first?.method == "POST" && calls.first?.bodyText == "{}", "본문에 무언가 실렸다: \(calls.first?.bodyText ?? "")")

        let rows = store.achievementRows
        #expect(rows.map(\.key) == ["phone_login", "todo3", "gomoku1", "chess1", "minigame3", "poke10", "ultra5", "team2", "streak14"],
                "계열마다 한 줄(받을 수 있는 단계가 먼저)이 아니다: \(rows.map(\.key))")
        #expect(rows.map(\.title).first == "폰 앱에서 로그인하기" && rows[5].title == "콕 찌르기 10회", "제목이 서버 글자가 아니다")
        #expect(store.achievementClaimableCount == 2 && store.achievementClaimableRuby == 55,
                "서버가 센 99 · 9999 를 그대로 믿었다: \(store.achievementClaimableCount) · \(store.achievementClaimableRuby)")
        #expect(MeText.claimPendingHint(store.achievementClaimableCount) == "받을 보상 2개")
        #expect(rows[5].state == .claimable && rows[2].state == .claimed && rows[8].state == .inProgress)
        #expect(MeText.missionProgress(rows[8]) == "3/14")
        // 잔량 미러는 이 테스트에서 재지 않는다 — 나 탭이 열리면 상점 조회도 같이 나가 두 응답이 같은 칸에 쓴다(순서가 갈린다).
        // 미러에 **쓴다**는 사실은 조회 하나만 도는 `failureKeepsRows` · `lateFetchDoesNotRegressRuby` 가 값으로 못 박는다.
        #expect(store.achievementsState.hasLoaded && !store.achievementsState.hasFailed)
        #expect(store.missionClaimBursts.isEmpty && store.missionClaimBurstSerial == 0, "조회만 했는데 받기 연출이 섰다")

        // 30초 뒤 다시 열었다 — 스로틀.
        store.tabDidDisappear()
        harness.clock.advance(30)
        store.tabDidAppear()
        await harness.quiesceMe()
        #expect(harness.requests(rpc: "achievements_status").count == 1, "1분 안에 또 물었다")

        // 61초 더 — 다시 묻는다.
        store.tabDidDisappear()
        harness.clock.advance(31)
        harness.enqueue("achievements_status", .json(Self.status(achieved: ["poke10", "team2", "todo3"], claimed: ["gomoku1"], ruby: 1_234)))
        store.tabDidAppear()
        await harness.quiesceMe()
        #expect(harness.requests(rpc: "achievements_status").count == 2)
        #expect(store.achievementClaimableCount == 3)
        harness.expectNoForbiddenCalls()
    }

    @Test("같은 턴에 두 번(탭 표시 + 앱 활성화) 불러도 조회는 한 번 — 순서가 어느 쪽이어도 · 탭이 안 보여도 한 번은 묻는다")
    func sameTurnFiresOnce() async throws {
        // 계약이 바뀐 자리다(1.0.9 배지). 옛 계약은 "탭이 안 보이면 묻지 않는다"였고 근거는 "받기 전에는 루비가 안 움직인다"였다 —
        // **그 근거가 배지와 함께 사라졌다**: 이제 탭이 안 보여도 알아야 할 값(탭 막대에 그릴 받을 보상 수)이 있다. 주간 보상이
        // 이미 같은 이유로 탭과 무관하게 읽는다. 변하지 않은 것은 **'한 번'** 이다 — 콜드 스타트는 탭 표시와 활성화가 같은 턴에
        // 오고, 그때 서버 호출이 둘로 늘면 정산과 같은 표를 두 번 읽는다.
        let harness = await RankMeHarness(label: "me-ach-once") { Self.quietResponder($0) }
        defer { harness.tearDown() }
        let store = harness.me
        for _ in 0..<4 { harness.enqueue("achievements_status", .json(Self.status(achieved: ["team2"]))) }

        // ① 탭이 안 보이는 채로 앞에 왔다 — 주간 보상과 **똑같이** 한 번 묻는다(배지가 설 수 있게).
        store.appDidBecomeActive()
        await harness.quiesceMe()
        #expect(harness.requests(rpc: "achievements_status").count == 1,
                "탭이 안 보이면 안 물었다 — 나 탭에 안 가 본 사람에게 배지가 영영 안 선다: \(harness.requests(rpc: "achievements_status").count)건")
        #expect(!harness.requests(rpc: "weekly_work_status").isEmpty, "대조: 주간 보상은 탭이 안 보여도 읽는다")
        #expect(store.achievementClaimableCount == 1, "탭 없이 읽은 값이 안 들어왔다")

        // ② 이어서 같은 턴에 탭이 떴다 — 또 나가지 않는다(떠 있음 · 60초 스로틀).
        store.tabDidAppear()
        await harness.quiesceMe()
        #expect(harness.requests(rpc: "achievements_status").count == 1,
                "활성화 직후 같은 턴의 탭 표시가 또 물었다: \(harness.requests(rpc: "achievements_status").count)번")

        // ③ 반대 순서의 콜드 스타트(탭 표시 + 활성화가 같은 턴) — 새 스토어에서 한 번.
        let cold = await RankMeHarness(label: "me-ach-once-cold") { Self.quietResponder($0) }
        defer { cold.tearDown() }
        for _ in 0..<4 { cold.enqueue("achievements_status", .json(Self.status(achieved: ["team2"]))) }
        cold.me.tabDidAppear()
        cold.me.appDidBecomeActive()
        await cold.quiesceMe()
        let fired = cold.requests(rpc: "achievements_status").count
        #expect(fired == 1, "같은 턴에 achievements_status 가 \(fired)번 나갔다")
        #expect(!cold.me.achievementsState.isLoading)
        harness.expectNoForbiddenCalls()
        cold.expectNoForbiddenCalls()
    }

    @Test("나 탭을 한 번도 열지 않고 앱이 앞에 오면 **탭 배지 수**가 선다(도전 미션 셋 + 이번 주 근무 하나 = 4)")
    func coldStartBadgeStandsWithoutOpeningTab() async throws {
        // 1.0.9 결함의 결과를 재는 자리다 — "함수를 불렀는가"가 아니라 **화면이 읽는 숫자**(`MobileRootView` 가 그리는
        // `model.badges.badge(for: .me)`)를 못 박는다. 앱을 새로 켜면 `achievements` 는 nil 이라, 조회 조건이 되살아나면
        // 이 수는 0(배지 없음)이 된다.
        let harness = await RankMeHarness(label: "me-ach-coldbadge") { request in
            switch request.rpcName {
            case "achievements_status":
                return .json(Self.status(achieved: ["todo3", "poke10", "team2"], claimed: ["gomoku1"], ruby: 120))
            case "weekly_work_status":
                return .json(Self.weekly(worked: 83_520, achieved: [20]))
            case "shop_state":
                return .json(#"{"ruby_balance":120,"characters":[]}"#)
            default:
                return nil
            }
        }
        defer { harness.tearDown() }
        let store = harness.me
        #expect(!store.isTabVisible, "전제: 나 탭을 한 번도 안 열었다")
        #expect(harness.model.badges.badge(for: .me) == nil, "아직 아무것도 못 읽었는데 배지가 선다")

        // 앱이 앞에 왔다 — 탭은 그대로 안 보인다(지금 탭에 있는 사람이다).
        store.appDidBecomeActive()
        await harness.quiesceMe()

        #expect(!store.isTabVisible, "전제가 깨졌다 — 활성화가 나 탭을 띄웠다")
        #expect(store.achievementClaimableCount == 3 && store.weeklyWork?.pendingCount == 1,
                "재료: 미션 \(store.achievementClaimableCount) · 주간 \(String(describing: store.weeklyWork?.pendingCount))")
        #expect(store.missionClaimableCount == 4, "스토어가 센 받을 보상 수: \(store.missionClaimableCount)")
        let badge = harness.model.badges.badge(for: .me)
        #expect(badge != nil, "나 탭을 한 번도 열지 않은 사람에게 배지가 안 섰다 — 배지가 필요한 바로 그 사람이다")
        #expect(badge == 4, "탭 배지가 스토어와 다른 수를 말한다: \(String(describing: badge))")
        // 홈 화면 아이콘에는 안 더한다(v0.3.58 규칙) — 배지를 켠 것이 아이콘으로 새지 않았다.
        #expect(harness.model.badges.appBadgeTotal == 0, "미션이 앱 아이콘 배지로 샜다")
        // 그 수가 실제로 탭 막대에 붙는가 — 안 붙으면 위 값이 아무 데도 안 간다.
        let root = try IntegrationContractTests.code("Sources/CheckMobileKit/App/MobileRootView.swift")
        #expect(root.contains(".badge(badges.badge(for: .me) ?? 0)"), "나 탭 막대에 배지를 안 붙였다")
        harness.expectNoForbiddenCalls()
    }

    @Test("함수 없는 서버(404): 절이 감춰지고 60초 안엔 다시 안 묻는다 · 그 뒤 서버에 생기면 줄이 선다")
    func missingFunctionHidesSection() async throws {
        let harness = await RankMeHarness(label: "me-ach-missing") { Self.quietResponder($0) }
        defer { harness.tearDown() }
        let store = harness.me
        store.tabDidAppear()   // 기본 응답 = 404 PGRST202
        await harness.quiesceMe()
        #expect(harness.requests(rpc: "achievements_status").count == 1)
        #expect(!store.achievementsAvailable && store.achievementSection == .hidden && store.achievements == nil)
        #expect(store.achievementRows.isEmpty && store.achievementClaimableCount == 0 && store.missionClaimableCount == 0)

        store.tabDidDisappear()
        harness.clock.advance(30)
        store.tabDidAppear()
        await harness.quiesceMe()
        #expect(harness.requests(rpc: "achievements_status").count == 1, "없는 함수를 1분 안에 또 두드렸다")

        store.tabDidDisappear()
        harness.clock.advance(31)
        harness.enqueue("achievements_status", .json(Self.status(achieved: ["team2"], ruby: 50)))
        store.tabDidAppear()
        await harness.quiesceMe()
        #expect(harness.requests(rpc: "achievements_status").count == 2, "스로틀 뒤에 다시 묻지 않았다")
        #expect(store.achievementsAvailable && store.achievementRows.count == 9 && store.achievementClaimableCount == 1)

        // 서버가 기능을 거뒀다 — 그려 둔 줄과 [받기]는 이제 거짓이라 함께 사라진다.
        harness.clock.advance(61)
        harness.enqueue("achievements_status", .missingFunction("/rest/v1/rpc/achievements_status"))
        await store.loadAchievements()
        #expect(store.achievementSection == .hidden && store.achievements == nil)
    }

    @Test("실패(5xx · 오프라인): 한 번도 못 읽었으면 .failed · 알던 줄은 지킨다 · [다시 시도]는 스로틀 없이 한 번")
    func failureKeepsRows() async throws {
        let harness = await RankMeHarness(label: "me-ach-failure") { Self.quietResponder($0) }
        defer { harness.tearDown() }
        let store = harness.me
        harness.enqueue("achievements_status", .json(#"{"message":"boom"}"#, status: 503))
        await store.loadAchievements()
        #expect(store.achievementSection == .failed && store.achievementsState.hasFailed)

        harness.enqueue("achievements_status", .json(Self.status(achieved: ["poke10"], ruby: 70)))
        store.retryAchievements()
        await harness.quiesceMe()
        #expect(harness.requests(rpc: "achievements_status").count == 2, "[다시 시도]가 스로틀에 막혔다")
        #expect(store.achievementRows.count == 9 && store.rubyBalance == 70)

        // 이제 실패해도 알던 줄을 그린다(빈 목록으로 지어내지 않는다).
        harness.enqueue("achievements_status", .networkFailure())
        await store.loadAchievements()
        #expect(store.achievementsState.hasFailed && store.achievementRows.count == 9 && store.achievementClaimableCount == 1)
        if case .loaded = store.achievementSection {} else { Issue.record("실패가 알던 줄을 지웠다: \(store.achievementSection)") }

        // 떠 있는 조회가 있으면 [다시 시도]는 요청 0건.
        let hold = BaseHold.rpc("achievements_status", host: harness.host)
        store.retryAchievements()
        #expect(await hold.waitHeld())
        store.retryAchievements()
        #expect(await hold.releaseAndWaitDelivered())
        await harness.quiesceMe()
        #expect(harness.requests(rpc: "achievements_status").count == 4, "떠 있는 조회에 [다시 시도]가 겹쳐 나갔다")
    }

    @Test("모르는 키도 그린다(아이콘만 기본값) · 제목·보상·순서는 서버 글자 그대로")
    func unknownKeysStillDrawn() async throws {
        let harness = await RankMeHarness(label: "me-ach-unknown") { Self.quietResponder($0) }
        defer { harness.tearDown() }
        let store = harness.me
        let future = #"{"key":"future9","series":"future9","tier":1,"title":"새 미션 한 번","detail":"서버가 더한 줄","reward":777,"target":1,"progress":1,"achieved":true,"claimed":false,"sort":5}"#
        harness.enqueue("achievements_status", .json(Self.status(extra: [future])))
        await store.loadAchievements()
        let row = try #require(store.achievementRows.first)
        #expect(row.key == "future9" && row.title == "새 미션 한 번" && row.detail == "서버가 더한 줄" && row.reward == 777,
                "서버가 더한 줄을 버렸거나 글자를 바꿨다")
        #expect(MeText.missionIcon(row.key) == MeText.missionFallbackIcon && MeText.missionIcon(row.key) == "star.fill")
        #expect(store.achievementClaimableCount == 1 && store.achievementClaimableRuby == 777)
        #expect(store.achievementRows.count == 10)
    }

    // MARK: - 받기

    @Test("받기: 본문 {p_key} · claimed_now 만큼 연출 · 잔량 · 줄이 다음 단계로 · 받을 수가 줄어든다")
    func claimOneRow() async throws {
        let harness = await RankMeHarness(label: "me-ach-claim") { Self.quietResponder($0) }
        defer { harness.tearDown() }
        let store = harness.me
        harness.enqueue("achievements_status", .json(Self.status(achieved: ["poke10", "team2"], progress: ["poke50": 23], ruby: 1_000)))
        await store.loadAchievements()
        #expect(store.achievementClaimableCount == 2)

        harness.enqueue("achievement_claim", .json(Self.status(achieved: ["team2"], claimed: ["poke10"],
                                                               progress: ["poke50": 23], ruby: 1_005, claimedNow: ["poke10"])))
        store.claimAchievement(key: "poke10")
        await harness.quiesceMe()

        let calls = harness.requests(rpc: "achievement_claim")
        #expect(calls.count == 1 && calls.first?.bodyText == #"{"p_key":"poke10"}"#, "본문: \(calls.first?.bodyText ?? "")")
        #expect(store.rubyBalance == 1_005 && harness.model.gomokuHost.rubyBalance == 1_005)
        let poke = try #require(store.achievementRows.first { $0.series == "poke" })
        #expect(poke.key == "poke50" && poke.state == .inProgress, "받은 뒤 그 계열 줄이 다음 단계로 안 바뀌었다: \(poke.key) \(poke.state)")
        #expect(store.achievementClaimableCount == 1 && store.missionClaimableCount == 1)
        let burst = try #require(store.claimBurst(series: "poke"), "받기 연출이 안 섰다")
        #expect(burst.amount == 5 && burst.target == "achievement:poke" && store.missionClaimBurstSerial == 1)
        #expect(!store.isClaimingAchievement("poke10") && !store.achievementClaimDidFail("poke10"))

        // 이미 받은 것을 또 받으면(서버가 claimed_now: []) 아무 말도 안 한다 — 연출 순번이 오르지 않는다.
        harness.enqueue("achievement_claim", .json(Self.status(achieved: ["team2"], claimed: ["poke10"], ruby: 1_005)))
        store.claimAchievement(key: "poke10")
        await harness.quiesceMe()
        #expect(store.missionClaimBurstSerial == 1, "서버가 아무것도 안 줬는데 '받았어요'를 연출했다")
        harness.expectNoForbiddenCalls()
    }

    @Test("두 번 눌러도 요청 하나 · 전부 받기가 떠 있으면 낱개는 나가지 않는다")
    func doubleTapSendsOneRequest() async throws {
        let harness = await RankMeHarness(label: "me-ach-double") { Self.quietResponder($0) }
        defer { harness.tearDown() }
        let store = harness.me
        harness.enqueue("achievements_status", .json(Self.status(achieved: ["poke10", "team2"], ruby: 1_000)))
        await store.loadAchievements()

        let hold = BaseHold.rpc("achievement_claim", host: harness.host)
        harness.enqueue("achievement_claim", .json(Self.status(achieved: ["team2"], claimed: ["poke10"], ruby: 1_005, claimedNow: ["poke10"])))
        store.claimAchievement(key: "poke10")
        #expect(await hold.waitHeld())
        #expect(store.isClaimingAchievement("poke10"))
        store.claimAchievement(key: "poke10")   // 연타
        #expect(await hold.releaseAndWaitDelivered())
        await harness.quiesceMe()
        #expect(harness.requests(rpc: "achievement_claim").count == 1, "연타로 요청이 두 번 나갔다(두 번 지급 시도)")
        #expect(store.missionClaimBurstSerial == 1)

        // 전부 받기가 떠 있는 동안 낱개 줄은 기다린다.
        let all = BaseHold.rpc("achievement_claim", host: harness.host)
        harness.enqueue("achievement_claim", .json(Self.status(claimed: ["poke10", "team2"], ruby: 1_055, claimedNow: ["team2"])))
        store.claimAllAchievements()
        #expect(await all.waitHeld())
        #expect(store.isClaimingAchievement("team2"), "전부 받기가 떠 있는데 낱개 버튼이 살아 있다")
        store.claimAchievement(key: "team2")
        #expect(await all.releaseAndWaitDelivered())
        await harness.quiesceMe()
        let bodies = harness.requests(rpc: "achievement_claim").map(\.bodyText)
        #expect(bodies == [#"{"p_key":"poke10"}"#, #"{"p_key":null}"#], "\(bodies)")
        #expect(store.achievementClaimableCount == 0)
    }

    @Test("겹친 받기의 답이 뒤바뀌어 와도 받은 줄에 [받기]가 다시 서지 않는다 · 늦은 답이 잔액을 내리지 않는다")
    func reversedClaimResponsesDoNotUnclaim() async throws {
        let harness = await RankMeHarness(label: "me-ach-reversed") { request in
            request.rpcName == "weekly_work_status" ? .json(Self.weekly(worked: 3_600, supportsClaim: false)) : nil
        }
        defer { harness.tearDown() }
        let store = harness.me
        harness.enqueue("achievements_status", .json(Self.status(achieved: ["poke10", "team2"], ruby: 1_000)))
        await store.loadAchievements()
        #expect(store.rubyBalance == 1_000)

        // poke10 의 받기만 붙잡는다(team2 는 통과) — 서버가 먼저 끝낸 poke10 의 답이 **나중에** 온다.
        let hold = BaseHold.install(host: harness.host, limit: 1) {
            $0.rpcName == "achievement_claim" && $0.bodyText.contains("poke10")
        }
        // ① team2 가 먼저 답한다: team2 받음 · poke10 은 아직 받을 수 있음.
        harness.enqueue("achievement_claim", .json(Self.status(achieved: ["poke10"], claimed: ["team2"], ruby: 1_050, claimedNow: ["team2"])))
        // ② 붙잡힌 poke10 의 답(받기 **전** 서버를 말한다): poke10 받음 · team2 는 아직 받을 수 있음 · 잔액도 낮다.
        harness.enqueue("achievement_claim", .json(Self.status(achieved: ["team2"], claimed: ["poke10"], ruby: 1_005, claimedNow: ["poke10"])))
        // 잔액을 못 쓴 채 지급이 있었으니 스토어가 상점을 다시 읽어 사실로 맞춘다.
        harness.enqueue("shop_state", .json(#"{"ruby_balance":1055,"characters":[]}"#))

        store.claimAchievement(key: "poke10")
        #expect(await hold.waitHeld())
        store.claimAchievement(key: "team2")
        // 붙잡힌 poke10 이 아직 떠 있으므로 `quiesceMe`(떠 있는 일 전부 기다리기)로는 여기서 멈춘다 — team2 의 효과만 기다린다.
        #expect(await baseWaitUntil { store.achievements?.missions.first { $0.key == "team2" }?.claimed == true },
                "team2 받기가 반영되지 않았다")
        #expect(store.achievementRows.first { $0.series == "team" }?.key == "team3", "team2 를 받았는데 줄이 안 넘어갔다")
        #expect(await hold.releaseAndWaitDelivered())
        await harness.quiesceMe()

        let keys = Set(try #require(store.achievements).missions.filter(\.claimed).map(\.key))
        #expect(keys == ["poke10", "team2"], "받음이 되돌아갔다(지금 받은 것: \(keys.sorted()))")
        #expect(store.achievementClaimableCount == 0, "방금 받은 줄에 [받기]가 다시 섰다 — 누르면 서버는 아무것도 안 준다")
        #expect(store.achievementRows.first { $0.series == "poke" }?.key == "poke50")
        #expect(harness.requests(rpc: "shop_state").count == 1, "잔량을 못 쓴 채 지급이 있었는데 상점을 다시 읽지 않았다")
        #expect(store.rubyBalance == 1_055, "늦은 받기 답(1005)이 잔액을 내렸거나 지급이 누락됐다: \(String(describing: store.rubyBalance))")
    }

    @Test("받기 뒤에 도착한 '받기 전' 조회는 버린다([받기]가 다시 서지 않는다) · 그 뒤 스로틀 안에 다시 묻지 않는다")
    func staleFetchAfterClaimIsDropped() async throws {
        let harness = await RankMeHarness(label: "me-ach-stale-fetch") { Self.quietResponder($0) }
        defer { harness.tearDown() }
        let store = harness.me
        harness.enqueue("achievements_status", .json(Self.status(achieved: ["poke10"], ruby: 1_000)))
        await store.loadAchievements()

        // 붙잡힌 조회는 **받기 전**의 서버를 말한다: poke10 은 아직 안 받았고 team2 는 **아직 달성 전**(1/2)이다.
        // 받기는 서버에서 먼저 정산을 돌리므로 그 응답에는 team2 의 달성이 들어 있다 — 그래서 늦게 온 조회를 그대로 덮으면
        // 받은 줄이 [받기]로 되돌아가고(merged 가 막는다) **방금 열린 team2 의 [받기]가 사라진다**(이 가드가 막는다).
        let hold = BaseHold.rpc("achievements_status", host: harness.host)
        harness.enqueue("achievements_status", .json(Self.status(achieved: ["poke10"], progress: ["team2": 1], ruby: 1_000)))
        harness.enqueue("achievement_claim", .json(Self.status(achieved: ["team2"], claimed: ["poke10"], ruby: 1_005, claimedNow: ["poke10"])))
        harness.clock.advance(61)
        let fetch = Task { await store.loadAchievements() }
        #expect(await hold.waitHeld())
        store.claimAchievement(key: "poke10")
        await harness.quiesceMe()
        #expect(store.achievementClaimableCount == 1 && store.rubyBalance == 1_005)
        #expect(store.achievementRows.first { $0.series == "team" }?.state == .claimable)

        #expect(await hold.releaseAndWaitDelivered())
        await fetch.value
        await harness.quiesceMe()
        let keys = Set(try #require(store.achievements).missions.filter(\.claimed).map(\.key))
        #expect(keys == ["poke10"], "받기 전 조회가 받은 줄을 [받기]로 되돌렸다: \(keys.sorted())")
        let team = try #require(store.achievementRows.first { $0.series == "team" })
        #expect(team.state == .claimable && store.achievementClaimableCount == 1,
                "받기 전 조회가 방금 열린 [받기]를 거뒀다(team2: \(team.state) · 받을 수 \(store.achievementClaimableCount))")
        #expect(store.rubyBalance == 1_005, "받기 전 조회가 잔액을 되돌렸다: \(String(describing: store.rubyBalance))")

        // 버린 조회 때문에 '낡음'이 남으면 안 된다 — 받기 응답이 신선도 도장을 찍었다.
        store.refreshAchievementsIfStale()
        await harness.quiesceMe()
        #expect(harness.requests(rpc: "achievements_status").count == 2, "버린 조회 뒤 스로틀 안인데 또 물었다")
    }

    @Test("조회가 떠 있는 사이 미러가 바뀌면 서버 잔량을 쓰지 않는다(받은 게 없으면 상점도 안 읽는다)")
    func lateFetchDoesNotRegressRuby() async throws {
        let harness = await RankMeHarness(label: "me-ach-ruby-mirror") { Self.quietResponder($0) }
        defer { harness.tearDown() }
        let store = harness.me
        harness.enqueue("achievements_status", .json(Self.status(achieved: ["poke10"], ruby: 1_000)))
        await store.loadAchievements()
        #expect(store.rubyBalance == 1_000)

        let hold = BaseHold.rpc("achievements_status", host: harness.host)
        harness.enqueue("achievements_status", .json(Self.status(achieved: ["poke10"], ruby: 1_000)))
        let shopReadsBefore = harness.requests(rpc: "shop_state").count
        let fetch = Task { await store.loadAchievements() }
        #expect(await hold.waitHeld())
        harness.model.gomokuHost.rubyBalance = 950   // 그 사이 뽑기 −50
        #expect(await hold.releaseAndWaitDelivered())
        await fetch.value
        await harness.quiesceMe()
        #expect(store.rubyBalance == 950, "늦은 조회가 깎인 루비를 되살렸다: \(String(describing: store.rubyBalance))")
        #expect(store.achievementRows.count == 9, "응답 자체를 버렸다")
        #expect(harness.requests(rpc: "shop_state").count == shopReadsBefore, "받은 게 없는데 상점을 다시 읽었다")
    }

    @Test("받기 실패는 그 줄에만 남는다 · 다음 성공에 걷힌다 · 나 탭을 떠나면 걷힌다 · 줄과 버튼은 그대로")
    func claimFailureStaysInItsRow() async throws {
        let harness = await RankMeHarness(label: "me-ach-fail-row") { Self.quietResponder($0) }
        defer { harness.tearDown() }
        let store = harness.me
        harness.enqueue("achievements_status", .json(Self.status(achieved: ["poke10", "team2"], ruby: 1_000)))
        await store.loadAchievements()

        harness.enqueue("achievement_claim", .json(#"{"message":"boom"}"#, status: 503))
        store.claimAchievement(key: "poke10")
        await harness.quiesceMe()
        #expect(store.achievementClaimDidFail("poke10"), "받기 실패를 그 줄이 말하지 않는다")
        #expect(!store.achievementClaimDidFail("team2"), "다른 줄에도 실패가 번졌다")
        #expect(store.achievementClaimableCount == 2 && !store.isClaimingAchievement("poke10"),
                "실패했는데 [받기]가 사라졌다(다시 누르는 것이 재시도다)")
        #expect(store.missionClaimBurstSerial == 0 && store.rubyBalance == 1_000)
        #expect(MeText.claimFailed == "받지 못했어요 · 다시 눌러 주세요")

        // 다시 누르면 재시도 — 성공하면 그 줄의 실패가 걷힌다.
        harness.enqueue("achievement_claim", .json(Self.status(achieved: ["team2"], claimed: ["poke10"], ruby: 1_005, claimedNow: ["poke10"])))
        store.claimAchievement(key: "poke10")
        await harness.quiesceMe()
        #expect(!store.achievementClaimDidFail("poke10") && store.missionClaimBurstSerial == 1)

        // 오프라인 실패 뒤 나 탭을 떠나면 연출 · 실패 문장이 걷힌다(다시 열면 화면이 새로 묻는다).
        harness.enqueue("achievement_claim", .networkFailure())
        store.claimAchievement(key: "team2")
        await harness.quiesceMe()
        #expect(store.achievementClaimDidFail("team2"))
        store.tabDidDisappear()
        #expect(!store.achievementClaimDidFail("team2") && store.missionClaimBursts.isEmpty && !store.weeklyClaimFailed)
    }

    @Test("전부 받기 실패는 받을 수 있는 줄 전부에 · 전부 받기 성공은 전부 걷는다")
    func claimAllFailureMarksEveryClaimableRow() async throws {
        let harness = await RankMeHarness(label: "me-ach-fail-all") { Self.quietResponder($0) }
        defer { harness.tearDown() }
        let store = harness.me
        harness.enqueue("achievements_status", .json(Self.status(achieved: ["poke10", "team2"], ruby: 1_000)))
        await store.loadAchievements()
        harness.enqueue("achievement_claim", .json(#"{"message":"boom"}"#, status: 503))
        store.claimAllAchievements()
        await harness.quiesceMe()
        #expect(store.achievementClaimDidFail("poke10") && store.achievementClaimDidFail("team2"))
        #expect(!store.achievementClaimDidFail("streak14"), "못 받는 줄에도 실패를 적었다")

        harness.enqueue("achievement_claim", .json(Self.status(claimed: ["poke10", "team2"], ruby: 1_055, claimedNow: ["poke10", "team2"])))
        store.claimAllAchievements()
        await harness.quiesceMe()
        #expect(store.achievementClaimFailedKeys.isEmpty, "전부 받기가 성공했는데 실패 문장이 남았다")
        // 계열마다 하나씩(콕 · 팀) — 합쳐서 두 연출이고 순번은 둘 다 올랐다.
        #expect(store.claimBurst(series: "poke")?.amount == 5 && store.claimBurst(series: "team")?.amount == 50)
        #expect(store.missionClaimBurstSerial == 2)
        #expect(store.rubyBalance == 1_055 && store.achievementClaimableCount == 0)
    }

    @Test("받기 함수가 없는 서버: 절을 감춘다(없는 버튼을 남기지 않는다)")
    func claimOnMissingFunctionHidesSection() async throws {
        let harness = await RankMeHarness(label: "me-ach-claim-missing") { Self.quietResponder($0) }
        defer { harness.tearDown() }
        let store = harness.me
        harness.enqueue("achievements_status", .json(Self.status(achieved: ["poke10"], ruby: 1_000)))
        await store.loadAchievements()
        harness.enqueue("achievement_claim", .missingFunction("/rest/v1/rpc/achievement_claim"))
        store.claimAchievement(key: "poke10")
        await harness.quiesceMe()
        #expect(store.achievementSection == .hidden && !store.achievementsAvailable && store.achievements == nil)
        #expect(!store.achievementClaimDidFail("poke10"), "기능이 없는 것을 '받지 못했어요'로 말했다")

        // 절이 감춰졌으면 받기는 더 나가지 않는다.
        store.claimAchievement(key: "poke10")
        await harness.quiesceMe()
        #expect(harness.requests(rpc: "achievement_claim").count == 1)
    }

    @Test("로그아웃: reset 이 미션 값을 다 비우고 앞 계정의 늦은 응답은 서지 않는다")
    func signOutDropsEverything() async throws {
        let harness = await RankMeHarness(label: "me-ach-signout") { Self.quietResponder($0) }
        defer { harness.tearDown() }
        let store = harness.me
        harness.enqueue("achievements_status", .json(Self.status(achieved: ["poke10"], claimed: ["team2"], ruby: 1_000)))
        await store.loadAchievements()
        harness.enqueue("achievement_claim", .json(#"{"message":"boom"}"#, status: 503))
        store.claimAchievement(key: "poke10")
        await harness.quiesceMe()
        #expect(store.achievements != nil && store.achievementClaimDidFail("poke10"))

        let hold = BaseHold.rpc("achievement_claim", host: harness.host)
        harness.enqueue("achievement_claim", .json(Self.status(claimed: ["poke10", "team2"], ruby: 9_999, claimedNow: ["poke10"])))
        store.claimAchievement(key: "poke10")
        #expect(await hold.waitHeld())
        await harness.model.session.signOut()
        #expect(store.achievements == nil && store.achievementsAvailable && store.achievementClaimFailedKeys.isEmpty)
        #expect(store.achievementClaimsInFlight.isEmpty && store.missionClaimBursts.isEmpty && store.missionClaimBurstSerial == 0)
        #expect(store.achievementSection == .hidden, "로그아웃 상태에서 절이 \(store.achievementSection)")
        #expect(await hold.releaseAndWaitDelivered())
        await harness.quiesceMe()
        #expect(store.achievements == nil && store.missionClaimBurstSerial == 0, "로그아웃 뒤 앞 계정의 받기가 섰다")
        #expect(harness.model.gomokuHost.rubyBalance == nil, "로그아웃 뒤 앞 계정의 잔량이 미러에 섰다")
    }

    // MARK: - 이번 주 근무 받기

    @Test("주간 받기: 본문 두 키 모두 null · 연출 · 잔량 · 버튼이 사라진다 · 받을 것 없으면 요청 0건")
    func weeklyClaim() async throws {
        let harness = await RankMeHarness(label: "me-weekly-claim") { request in
            request.rpcName == "shop_state" ? .json(#"{"ruby_balance":1000,"characters":[]}"#) : nil
        }
        defer { harness.tearDown() }
        let store = harness.me
        // 받을 것이 없으면 버튼도 요청도 없다.
        harness.enqueue("weekly_work_status", .json(Self.weekly(worked: 30 * 3_600, claimed: [20], ruby: 1_000)))
        await store.loadWeeklyWork()
        #expect(!store.showsWeeklyClaim && !store.canClaimWeeklyWork && store.weeklyClaimableRuby == 0)
        store.claimWeeklyWork()
        await harness.quiesceMe()
        #expect(harness.requests(rpc: "weekly_work_claim").isEmpty, "받을 것이 없는데 받기를 보냈다")

        // 40시간 칸을 채웠다(달성 · 미지급).
        harness.enqueue("weekly_work_status", .json(Self.weekly(worked: 41 * 3_600, achieved: [40], claimed: [20], ruby: 1_000)))
        await store.loadWeeklyWork()
        #expect(store.showsWeeklyClaim && store.canClaimWeeklyWork && store.weeklyClaimableRuby == 50)
        #expect(store.weeklyWork?.pendingCount == 1 && store.missionClaimableCount == 1)
        #expect(store.weeklyGrantNotice == nil, "받기 서버인데 '받았어요' 칩을 띄웠다(같은 일을 두 번 알린다)")

        harness.enqueue("weekly_work_claim", .json(Self.weekly(worked: 41 * 3_600, claimed: [20, 40], ruby: 1_050, claimedNow: [40])))
        store.claimWeeklyWork()
        await harness.quiesceMe()
        let calls = harness.requests(rpc: "weekly_work_claim")
        #expect(calls.count == 1 && calls.first?.method == "POST")
        let body = try #require(calls.first?.jsonBody)
        #expect(Set(body.keys) == ["p_week_start", "p_hours"], "키 집합이 흔들리면 PostgREST 가 다른 함수를 찾는다: \(body.keys)")
        #expect(body["p_week_start"] is NSNull && body["p_hours"] is NSNull, "전부 받기인데 주 · 시간을 실었다")
        #expect(store.rubyBalance == 1_050 && harness.model.gomokuHost.rubyBalance == 1_050)
        #expect(!store.showsWeeklyClaim && !store.weeklyClaimInFlight && !store.weeklyClaimFailed)
        #expect(store.weeklyWork?.tiers.first { $0.hours == 40 }?.claimed == true)
        let burst = try #require(store.weeklyClaimBurst, "주간 받기 연출이 안 섰다")
        #expect(burst.amount == 50 && burst.target == "weekly" && store.missionClaimBurstSerial == 1)
        #expect(store.weeklyGrantNotice == nil, "받기를 '받았어요' 칩으로 또 말했다")
        harness.expectNoForbiddenCalls()
    }

    @Test("주간 받기: 두 번 눌러도 요청 하나 · 실패는 주간 줄에만 · 뒤에 도착한 '받기 전' 조회는 버린다")
    func weeklyClaimGuards() async throws {
        let harness = await RankMeHarness(label: "me-weekly-claim-guards") { _ in nil }
        defer { harness.tearDown() }
        let store = harness.me
        harness.enqueue("weekly_work_status", .json(Self.weekly(worked: 41 * 3_600, achieved: [40], claimed: [20], ruby: 1_000)))
        await store.loadWeeklyWork()

        // 함수 없음(404)도 그냥 실패다 — 조용히 삼키면 누른 사람에게 아무 일도 안 일어난다(상태 · 받기는 한 마이그레이션이라
        // "받을 것이 있는데 받기 함수가 없는" 서버는 없다).
        harness.enqueue("weekly_work_claim", .missingFunction("/rest/v1/rpc/weekly_work_claim"))
        store.claimWeeklyWork()
        await harness.quiesceMe()
        #expect(store.weeklyClaimFailed && store.showsWeeklyClaim, "404 받기를 조용히 삼켰다")
        store.tabDidDisappear()
        #expect(!store.weeklyClaimFailed, "나 탭을 떠났는데 주간 받기 실패가 남았다")

        // 실패 — 주간 줄 안에서 말하고 버튼은 그대로.
        harness.enqueue("weekly_work_claim", .json(#"{"message":"boom"}"#, status: 503))
        store.claimWeeklyWork()
        await harness.quiesceMe()
        #expect(store.weeklyClaimFailed && store.showsWeeklyClaim && !store.weeklyClaimInFlight)
        #expect(store.achievementClaimFailedKeys.isEmpty && store.missionClaimBurstSerial == 0)

        // 연타 = 요청 하나. 그 사이 떠난 '받기 전' 조회는 받기 뒤에 도착해도 버린다.
        let fetchHold = BaseHold.rpc("weekly_work_status", host: harness.host)
        harness.enqueue("weekly_work_status", .json(Self.weekly(worked: 41 * 3_600, achieved: [40], claimed: [20], ruby: 1_000)))
        harness.clock.advance(61)
        let fetch = Task { await store.loadWeeklyWork() }
        #expect(await fetchHold.waitHeld())

        let claimHold = BaseHold.rpc("weekly_work_claim", host: harness.host)
        harness.enqueue("weekly_work_claim", .json(Self.weekly(worked: 41 * 3_600, claimed: [20, 40], ruby: 1_050, claimedNow: [40])))
        store.claimWeeklyWork()
        #expect(await claimHold.waitHeld())
        store.claimWeeklyWork()   // 연타
        #expect(await claimHold.releaseAndWaitDelivered())
        await harness.quiesceMe()
        #expect(harness.requests(rpc: "weekly_work_claim").count == 3, "연타로 받기가 또 나갔다(404 · 503 · 성공 셋이어야 한다)")
        #expect(!store.showsWeeklyClaim && store.rubyBalance == 1_050 && !store.weeklyClaimFailed)

        #expect(await fetchHold.releaseAndWaitDelivered())
        await fetch.value
        await harness.quiesceMe()
        #expect(!store.showsWeeklyClaim, "받기 전 조회가 [받기]를 다시 세웠다 — 누르면 서버는 아무것도 안 준다")
        #expect(store.weeklyWork?.tiers.first { $0.hours == 40 }?.claimed == true)
        #expect(store.rubyBalance == 1_050, "받기 전 조회가 잔액을 되돌렸다")
    }

    @Test("옛 서버(받기 칸 없음)는 예전 그대로: 버튼 없음 · cron 이 준 칸은 '받았어요' 칩으로 알린다")
    func oldServerKeepsAutoGrantNotice() async throws {
        let harness = await RankMeHarness(label: "me-weekly-old-server") { _ in nil }
        defer { harness.tearDown() }
        let store = harness.me
        harness.enqueue("weekly_work_status", .json(Self.weekly(worked: 30 * 3_600, claimed: [20], ruby: 100, supportsClaim: false)))
        await store.loadWeeklyWork()
        #expect(store.weeklyWork?.supportsClaim == false && !store.showsWeeklyClaim && store.weeklyClaimableRuby == 0)
        store.claimWeeklyWork()
        await harness.quiesceMe()
        #expect(harness.requests(rpc: "weekly_work_claim").isEmpty, "옛 서버에 받기를 보냈다")

        // cron 이 40 을 먼저 지급했다 — 옛 서버에서는 이 갈래가 그대로 알린다.
        harness.enqueue("weekly_work_status", .json(Self.weekly(worked: 41 * 3_600, claimed: [20, 40], ruby: 150, supportsClaim: false)))
        await store.loadWeeklyWork()
        #expect(store.weeklyGrantNotice == WeeklyWorkGrantNotice(ruby: 50, hours: [40]), "옛 서버의 자동 지급 알림이 사라졌다")
        #expect(store.weeklyGrantSerial == 1 && store.rubyBalance == 150)

        // 같은 사실을 받기 서버가 말하면(단계가 claimed 로 바뀐 응답) 알리지 않는다 — 사람이 [받기]를 눌러 이미 봤다.
        let fresh = await RankMeHarness(label: "me-weekly-claim-server-no-chip") { _ in nil }
        defer { fresh.tearDown() }
        fresh.enqueue("weekly_work_status", .json(Self.weekly(worked: 30 * 3_600, claimed: [20], ruby: 100)))
        await fresh.me.loadWeeklyWork()
        fresh.enqueue("weekly_work_status", .json(Self.weekly(worked: 41 * 3_600, claimed: [20, 40], ruby: 150)))
        await fresh.me.loadWeeklyWork()
        #expect(fresh.me.weeklyGrantNotice == nil && fresh.me.weeklyGrantSerial == 0,
                "받기 서버에서 받은 칸을 '채웠어요'로 또 알렸다")
    }

    // MARK: - 문구(값으로)

    @Test("문구: 낱말 · 진행 숫자 · 보상 · 받을 보상 수 · 보이스오버 · 실패 한 줄")
    func copyValues() {
        #expect(MeText.missionsTitle == "도전 미션")
        #expect(MeText.claimButton == "받기" && MeText.claimedMark == "받음" && MeText.claimedMark == MeText.weeklyGrantSuffix)
        #expect(MeText.missionsLoadFailed == "미션을 불러오지 못했어요")
        #expect(MeText.claimFailed == "받지 못했어요 · 다시 눌러 주세요" && MeText.claimFailed == AchievementNoticeText.claimFailedRow)
        #expect(MeText.claimAmount(50) == "+50" && MeText.claimAmount(-3) == "+0")
        #expect(MeText.missionReward(50) == "+50" && MeText.missionReward(0) == nil, "보상 0 인 줄에 '+0' 칩을 그린다")
        #expect(MeText.claimPendingHint(0) == nil && MeText.claimPendingHint(1) == "받을 보상 1개" && MeText.claimPendingHint(12) == "받을 보상 12개")
        #expect(MeText.claimAccessibility(50) == "받기, 루비 50개" && MeText.claimAccessibility(-1) == "받기, 루비 0개")

        let progressing = AchievementStatus.Mission(key: "poke50", series: "poke", tier: 2, title: "콕 찌르기 50회",
                                                    reward: 20, target: 50, progress: 23)
        #expect(MeText.missionProgress(progressing) == "23/50")
        #expect(MeText.missionAccessibility(progressing) == "콕 찌르기 50회, 23/50, 달성하면 루비 20개")
        let claimable = AchievementStatus.Mission(key: "team2", series: "team", title: "팀 2명 채우기",
                                                  reward: 50, target: 2, progress: 2, achieved: true)
        #expect(MeText.missionAccessibility(claimable) == "팀 2명 채우기, 달성했어요", "줄이 금액을 또 읽는다(버튼이 읽는다)")
        let claimed = AchievementStatus.Mission(key: "gomoku1", title: "오목 한 판 두기", reward: 10, target: 1,
                                                progress: 1, achieved: true, claimed: true)
        #expect(MeText.missionAccessibility(claimed) == "오목 한 판 두기, 루비 10개 받았어요")
        let noReward = AchievementStatus.Mission(key: "future9", title: "새 미션", reward: 0, target: 1, progress: 0)
        #expect(MeText.missionAccessibility(noReward) == "새 미션, 0/1", "보상 없는 줄이 '루비 0개'를 읽는다")
    }

    @Test("아이콘: 13개 키 전부 · 모르는 키는 별 · 맥과 같은 기호 · 이름이 실제로 풀린다")
    func iconTable() throws {
        let expected: [String: String] = [
            "phone_login": "iphone", "todo3": "checklist", "gomoku1": "circle.grid.3x3.fill",
            "chess1": "checkerboard.rectangle", "minigame3": "gamecontroller.fill",
            "poke10": "hand.point.right.fill", "poke50": "hand.point.right.fill", "poke100": "hand.point.right.fill",
            "ultra5": "bolt.fill", "team2": "person.3.fill", "team3": "person.3.fill",
            "streak14": "flame.fill", "streak30": "flame.fill",
        ]
        for def in Self.defs {
            #expect(MeText.missionIcon(def.key) == expected[def.key], "\(def.key) 아이콘: \(MeText.missionIcon(def.key))")
        }
        #expect(MeText.missionIcon("future9") == "star.fill" && MeText.missionIcon("") == "star.fill")
        #if canImport(AppKit)
        // 이름이 없으면 `Image(systemName:)` 는 **아무것도 안 그린다**(두부도 안 뜬다 — 자리만 비어 조용히 고장난다).
        for symbol in Set(expected.values).union([MeText.missionFallbackIcon]) {
            #expect(NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil, "없는 기호 이름: \(symbol)")
        }
        #endif
    }

    @Test("맥과 같은 낱말 · 같은 기호가 맥 소스에 아직 있다(한쪽만 바뀌면 빨개진다)")
    func macParity() throws {
        let code = try MeTextParityTests.macCode()
        for sentence in [MeText.missionsTitle, MeText.missionsLoadFailed, MeText.claimButton, MeText.claimedMark, "받을 보상 "] {
            #expect(code.contains(sentence), "맥 코드에 없는 문장: \(sentence)")
        }
        // 맥은 `"\(claimButton), 루비 \(max(0, amount))개"` 로 적는다 — 소스에 남는 글자는 꼬리뿐이다.
        #expect(code.contains(", 루비 ") && code.contains("개\""), "맥 받기 버튼 보이스오버 문구가 바뀌었다")
        for symbol in ["iphone", "checklist", "circle.grid.3x3.fill", "checkerboard.rectangle", "gamecontroller.fill",
                       "person.3.fill", "hand.point.right.fill", "bolt.fill", "flame.fill", "star.fill"] {
            #expect(code.contains("\"\(symbol)\""), "맥이 쓰지 않는 기호를 폰이 쓴다: \(symbol)")
        }
    }

    @Test("미션 · 받기 RPC 는 폰 금지 목록에 없다")
    func notForbidden() {
        #expect(!MobileForbiddenCalls.forbiddenRPCs.contains("achievements_status"))
        #expect(!MobileForbiddenCalls.forbiddenRPCs.contains("achievement_claim"))
        #expect(!MobileForbiddenCalls.forbiddenRPCs.contains("weekly_work_claim"))
        #expect(MobileForbiddenCalls.forbiddenRPCs.contains("ultra_wallet_sync"),
                "대조: 3시간 랩(자동 지급)은 여전히 폰이 부르지 않는다")
        #expect(SupabaseWorkService.achievementsStatusPath == "/rest/v1/rpc/achievements_status")
        #expect(SupabaseWorkService.achievementClaimPath == "/rest/v1/rpc/achievement_claim")
        #expect(SupabaseWorkService.weeklyWorkClaimPath == "/rest/v1/rpc/weekly_work_claim")
    }
}
