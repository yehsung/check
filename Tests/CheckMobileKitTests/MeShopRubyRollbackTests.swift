import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

/// 상점 조회(`shop_state`)가 루비 미러를 되돌리지 않는다(폰 1.0.9) — `MeStore` 의 **진짜 경로**를 스텁 서버로 돈다.
///
/// 결함: `applyShopState` 가 쓰기 도장 없이 미러를 덮어, **받기 전에 떠난** `shop_state` 가 받기 뒤에 도착하면 잔량이
/// 1055 → 1000 으로 되돌아갔다. 나 탭이 뜰 때 상점 · 주간 · 도전 미션 조회가 함께 떠나므로 흔한 창이다
/// (주간 보상 0.3.55 도 같은 구멍이었고, 1.0.9 의 [받기] 버튼이 그 되돌림을 눈에 보이게 만든다).
///
/// 단언은 **모양이 아니라 결과**다: "가드를 불렀다"가 아니라 **잔량 숫자**를 못 박는다. 기대값은 손으로 적은 숫자다
/// (규칙 함수로 기대값을 다시 만들면 규칙이 틀려도 초록이다). 늦고 빠름은 벽시계가 아니라 `BaseHold` 로 정한다.
///
/// 이 스토어 파일들은 `#if os(iOS)` 밖이라 맥 `swift test` 가 진짜 경로를 돈다.
@MainActor
@Suite("나 탭 상점 잔량 되돌림(폰 1.0.9)")
struct MeShopRubyRollbackTests {
    // MARK: - 픽스처(서버 계약 모양)

    /// 유령은 안 가진 30짜리(구매 시험용), 여우는 보유, 다람쥐는 80.
    nonisolated static let rows = #"{"id":"fox","price":30,"owned":true},{"id":"ghost","price":30,"owned":false},{"id":"squirrel","price":80,"owned":false}"#
    /// 유령까지 보유(구매 뒤 다시 읽는 상점).
    nonisolated static let rowsWithGhost = #"{"id":"fox","price":30,"owned":true},{"id":"ghost","price":30,"owned":true},{"id":"squirrel","price":80,"owned":false}"#

    /// `shop_state()` 응답. `ruby` 가 nil 이면 **키를 싣지 않는다**(잔량을 모르는 서버 — 모르는 것을 0 으로 적지 않는다).
    nonisolated static func shop(ruby: Int?, rows: String = rows) -> String {
        let balance = ruby.map { #""ruby_balance":\#($0),"# } ?? ""
        return #"{\#(balance)"characters":[\#(rows)]}"#
    }

    /// `weekly_work_status()` 응답(지급이 들어간 모양 — 못 쓴 잔량의 복구 경로를 깨우는 `granted_now`).
    nonisolated static func weekly(ruby: Int, granted: String = #"[{"hours":40,"ruby":50}]"#) -> String {
        let tiers = [(20, 20, true), (40, 50, true), (60, 200, false)]
            .map { #"{"hours":\#($0.0),"ruby":\#($0.1),"claimed":\#($0.2)}"# }
            .joined(separator: ",")
        return #"{"week_start":"2026-09-14","next_week_start":"2026-09-21","worked_seconds":\#(41 * 3600),"tiers":[\#(tiers)],"granted_now":\#(granted),"ruby_balance":\#(ruby),"server_now_ms":1789621500000}"#
    }

    // MARK: - ① 받기 → 늦게 도착한 '받기 전' 상점 조회

    @Test("받기 뒤에 도착한 '받기 전' shop_state 는 잔량을 되돌리지 않는다(1055 가 1000 으로 가지 않는다) · 목록·보유는 그대로 들어온다")
    func staleShopStateDoesNotRollBackClaimedRuby() async throws {
        let harness = await RankMeHarness(label: "me-shop-ruby-claim") { _ in nil }
        defer { harness.tearDown() }
        let store = harness.me

        // 기준: 상점 1000 · 받을 미션 둘(콕 10회 5 + 팀 2명 50 = 55).
        harness.enqueue("shop_state", .json(Self.shop(ruby: 1_000)))
        await store.loadShop()
        harness.enqueue("achievements_status", .json(MeAchievementClaimTests.status(achieved: ["poke10", "team2"], ruby: 1_000)))
        await store.loadAchievements()
        #expect(store.rubyBalance == 1_000 && store.achievementClaimableCount == 2)

        // 나 탭이 뜨며 상점 조회가 떠났다 — 서버는 아직 받기 전(1000)을 말한다.
        let hold = BaseHold.rpc("shop_state", host: harness.host)
        harness.enqueue("shop_state", .json(Self.shop(ruby: 1_000, rows: Self.rowsWithGhost)))
        let staleFetch = Task { await store.loadShop() }
        #expect(await hold.waitHeld())

        // 그 사이 사람이 [받기] 를 눌렀고 서버가 1055 를 줬다.
        harness.enqueue("achievement_claim", .json(MeAchievementClaimTests.status(claimed: ["poke10", "team2"], ruby: 1_055,
                                                                                  claimedNow: ["poke10", "team2"])))
        store.claimAchievement(key: nil)
        await harness.quiesceMe()
        #expect(store.rubyBalance == 1_055 && harness.model.gomokuHost.rubyBalance == 1_055, "받기 응답의 잔량이 미러에 안 실렸다")

        // 이제 받기 **전**에 떠난 상점 응답이 도착한다.
        #expect(await hold.releaseAndWaitDelivered())
        await staleFetch.value
        await harness.quiesceMe()

        #expect(store.rubyBalance == 1_055,
                "받은 루비가 되돌아갔다(1000 = 받기 전 조회가 덮었다): \(String(describing: store.rubyBalance))")
        #expect(harness.model.gomokuHost.rubyBalance == 1_055, "게임 탭이 함께 보는 미러가 되돌아갔다")
        // 응답을 통째로 버리지는 않는다 — 잔량만 안 쓴다.
        #expect(store.shopState.hasLoaded && store.isOwned("ghost"), "늦은 조회의 목록·보유까지 버렸다")
        harness.expectNoForbiddenCalls()
    }

    @Test("ABA: 그 사이 쓴 값이 **떠날 때와 같은 1000** 이어도 늦은 조회의 1000 은 쓰지 않는다(횟수로 묻는다)")
    func sameValueWriteStillBlocksTheLateFetch() async throws {
        let harness = await RankMeHarness(label: "me-shop-ruby-aba") { _ in nil }
        defer { harness.tearDown() }
        let store = harness.me
        harness.enqueue("shop_state", .json(Self.shop(ruby: 1_000)))
        await store.loadShop()
        #expect(store.rubyBalance == 1_000)

        let hold = BaseHold.rpc("shop_state", host: harness.host)
        harness.enqueue("shop_state", .json(Self.shop(ruby: 1_000)))
        let staleFetch = Task { await store.loadShop() }
        #expect(await hold.waitHeld())
        // 뽑기 −50 뒤 받기 +50 처럼, 사이의 쓰기가 마침 떠날 때와 같은 값이었다.
        let serialBeforeWrite = harness.model.gomokuHost.rubyWriteSerial
        harness.model.gomokuHost.rubyBalance = 1_000
        #expect(harness.model.gomokuHost.rubyWriteSerial == serialBeforeWrite + 1, "같은 값을 쓴 것은 안 셌다")
        #expect(await hold.releaseAndWaitDelivered())
        await staleFetch.value
        await harness.quiesceMe()

        // 값은 어차피 1000 이다 — **쓴 횟수**로 가려냈는지가 이 시험의 전부다(쓰면 미러 순번이 하나 더 오른다).
        #expect(harness.model.gomokuHost.rubyWriteSerial == serialBeforeWrite + 1,
                "값이 같다고 늦은 조회가 미러에 또 썼다 — 값으로 비교하면 ABA 를 못 가른다")
    }

    // MARK: - ② 그 사이 아무도 안 썼으면 들어온다(대조군)

    @Test("그 사이 미러에 쓴 사람이 없으면 shop_state 잔량이 그대로 들어온다(1000 → 1234)")
    func shopStateRubyAppliesWhenNobodyWroteMeanwhile() async throws {
        let harness = await RankMeHarness(label: "me-shop-ruby-control") { _ in nil }
        defer { harness.tearDown() }
        let store = harness.me
        harness.enqueue("shop_state", .json(Self.shop(ruby: 1_000)))
        await store.loadShop()
        #expect(store.rubyBalance == 1_000)

        let hold = BaseHold.rpc("shop_state", host: harness.host)
        harness.enqueue("shop_state", .json(Self.shop(ruby: 1_234)))
        let fetch = Task { await store.loadShop() }
        #expect(await hold.waitHeld())
        // 아무도 미러에 쓰지 않는다.
        #expect(await hold.releaseAndWaitDelivered())
        await fetch.value
        await harness.quiesceMe()

        #expect(store.rubyBalance == 1_234 && harness.model.gomokuHost.rubyBalance == 1_234,
                "도장이 멀쩡한 조회의 잔량까지 막았다: \(String(describing: store.rubyBalance))")
        harness.expectNoForbiddenCalls()
    }

    // MARK: - ③ 구매 응답의 잔량은 언제나

    @Test("구매 응답의 잔량은 그 사이 미러가 바뀌었어도 언제나 들어온다(누른 사람 자신의 결과)")
    func purchaseResponseRubyAlwaysApplies() async throws {
        let harness = await RankMeHarness(label: "me-shop-ruby-buy") { _ in nil }
        defer { harness.tearDown() }
        let store = harness.me
        harness.enqueue("shop_state", .json(Self.shop(ruby: 1_000)))
        await store.loadShop()
        store.selectShopItem("ghost")
        #expect(store.canConfirmPurchase)

        let hold = BaseHold.rpc("buy_character", host: harness.host)
        harness.enqueue("buy_character", .json(#"{"status":"ok","character":"ghost","price":30,"ruby_balance":970}"#))
        // 구매 뒤 다시 읽는 상점은 **잔량을 안 싣는다** — 이 시험이 재는 건 구매 응답이 준 970 이다.
        harness.enqueue("shop_state", .json(Self.shop(ruby: nil, rows: Self.rowsWithGhost)))
        store.confirmPurchase()
        #expect(await hold.waitHeld())
        // 그 사이 다른 응답(오목 판돈 정산)이 미러를 바꿨다.
        harness.model.gomokuHost.rubyBalance = 1_500
        #expect(await hold.releaseAndWaitDelivered())
        await harness.quiesceMe()

        #expect(store.rubyBalance == 970,
                "산 사람의 잔량이 안 섰다(1500 = 구매 경로에 도장이 끼어 막혔다): \(String(describing: store.rubyBalance))")
        #expect(harness.model.gomokuHost.rubyBalance == 970)
        #expect(store.isOwned("ghost") && store.shopNotice == MeText.bought)
        harness.expectNoForbiddenCalls()
    }

    // MARK: - ④ 주간 보상의 복구 경로(못 쓴 잔량을 상점 재조회로 맞춘다)

    @Test("주간 복구 경로: 미러가 바뀌어 주간 잔량을 못 썼을 때 띄우는 상점 재조회는 **여전히** 잔량을 고친다(1150 → 1250)")
    func weeklyRecoveryReloadStillFixesTheBalance() async throws {
        let harness = await RankMeHarness(label: "me-shop-ruby-weekly") { _ in nil }
        defer { harness.tearDown() }
        let store = harness.me
        harness.enqueue("shop_state", .json(Self.shop(ruby: 1_000)))
        await store.loadShop()
        #expect(store.rubyBalance == 1_000)

        let hold = BaseHold.rpc("weekly_work_status", host: harness.host)
        harness.enqueue("weekly_work_status", .json(Self.weekly(ruby: 1_250)))
        // 복구가 띄우는 재조회에 서버가 줄 답(지급이 들어간 잔량).
        harness.enqueue("shop_state", .json(Self.shop(ruby: 1_250)))
        let load = Task { await store.loadWeeklyWork() }
        #expect(await hold.waitHeld())
        // 그 사이 뽑기 −100 이 미러에 썼다 — 주간 응답의 1250 은 못 쓴다.
        harness.model.gomokuHost.rubyBalance = 1_150
        #expect(await hold.releaseAndWaitDelivered())
        await load.value
        await harness.quiesceMe()

        #expect(harness.requests(rpc: "shop_state").count == 2, "지급이 있었는데 상점을 다시 읽지 않았다")
        #expect(store.rubyBalance == 1_250,
                "복구 재조회가 잔량을 못 고쳤다(1150 = 지급이 화면에서 빠졌다): \(String(describing: store.rubyBalance))")
        #expect(harness.model.gomokuHost.rubyBalance == 1_250)
        #expect(store.weeklyGrantNotice == WeeklyWorkGrantNotice(ruby: 50, hours: [40]), "지급 알림까지 잃었다")
        harness.expectNoForbiddenCalls()
    }
}
