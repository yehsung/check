import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

/// 이번 주 누적 근무 보상(v0.3.55 · 폰 1.0.8(19)) — 응답 디코드 · 화면이 읽는 규칙 · `MeStore` 의 **진짜 경로**(스텁 서버 →
/// `weekly_work_status` → 스토어 상태 → 카드가 읽는 값 · 루비 미러) · 폰 [근무 종료] 뒤 다시 읽기 · iOS 카드 소스 계약.
///
/// 기대값은 손으로 적은 글자다(규칙 함수로 기대값을 다시 만들면 규칙이 틀려도 초록이다).
@MainActor
@Suite("나 탭 이번 주 근무 보상(v0.3.55)")
struct MeWeeklyWorkTests {
    /// 서버 계약 모양(SPEC-weekly). `claimed` 는 받은 칸 시간 목록.
    nonisolated static func status(worked: Int, claimed: Set<Int>, granted: String = "[]", ruby: Int? = 120,
                                   week: String = "2026-09-14", next: String = "2026-09-21") -> String {
        let tiers = [(20, 20), (40, 50), (60, 200)]
            .map { #"{"hours":\#($0.0),"ruby":\#($0.1),"claimed":\#(claimed.contains($0.0))}"# }
            .joined(separator: ",")
        let rubyPart = ruby.map { #","ruby_balance":\#($0)"# } ?? ""
        return #"{"week_start":"\#(week)","next_week_start":"\#(next)","worked_seconds":\#(worked),"tiers":[\#(tiers)],"granted_now":\#(granted)\#(rubyPart),"server_now_ms":1789621500000}"#
    }

    nonisolated static func decode(_ json: String) throws -> WeeklyWorkStatusDTO {
        // 서비스와 같은 설정(SupabaseWorkService.init — 뱀 표기 → 낙타 표기).
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(WeeklyWorkStatusDTO.self, from: Data(json.utf8))
    }

    nonisolated static func tier(_ hours: Int, _ ruby: Int, _ claimed: Bool) -> WeeklyWorkStatusDTO.Tier {
        .init(hours: hours, ruby: ruby, claimed: claimed)
    }

    nonisolated static func dto(worked: Int, claimed: Set<Int>, granted: [WeeklyWorkStatusDTO.Grant] = [],
                                week: String = "2026-09-14") -> WeeklyWorkStatusDTO {
        WeeklyWorkStatusDTO(weekStart: week, nextWeekStart: "2026-09-21", workedSeconds: worked,
                            tiers: [tier(20, 20, claimed.contains(20)), tier(40, 50, claimed.contains(40)), tier(60, 200, claimed.contains(60))],
                            grantedNow: granted, rubyBalance: 120)
    }

    // MARK: - 디코드

    @Test("디코드: 계약 예시 그대로 · 지난주 따라잡기 지급의 week_start")
    func decodesContract() throws {
        let json = #"""
        { "week_start": "2026-10-12", "next_week_start": "2026-10-19",
          "worked_seconds": 83456,
          "tiers": [ {"hours": 20, "ruby": 20, "claimed": true},
                     {"hours": 40, "ruby": 50, "claimed": false},
                     {"hours": 60, "ruby": 200, "claimed": false} ],
          "granted_now": [ {"hours": 20, "ruby": 20}, {"hours": 60, "ruby": 200, "week_start": "2026-10-05"} ],
          "ruby_balance": 1057,
          "server_now_ms": 1781234567890 }
        """#
        let status = try Self.decode(json)
        #expect(status.weekStart == "2026-10-12" && status.nextWeekStart == "2026-10-19")
        #expect(status.workedSeconds == 83456)
        #expect(status.tiers == [Self.tier(20, 20, true), Self.tier(40, 50, false), Self.tier(60, 200, false)])
        #expect(status.grantedNow == [.init(hours: 20, ruby: 20), .init(hours: 60, ruby: 200, weekStart: "2026-10-05")])
        #expect(status.rubyBalance == 1057)
        #expect(status.serverNowMs == 1_781_234_567_890)
    }

    @Test("디코드: 칸이 다 빠져도 · null 이어도 응답 전체를 버리지 않는다(0초 · 칸 없음 · 잔량 모름)")
    func decodesMissingKeys() throws {
        let empty = try Self.decode("{}")
        #expect(empty.weekStart == nil && empty.nextWeekStart == nil)
        #expect(empty.workedSeconds == 0 && empty.tiers.isEmpty && empty.grantedNow.isEmpty)
        #expect(empty.rubyBalance == nil && empty.serverNowMs == nil)
        let nulls = try Self.decode(#"{"week_start":null,"worked_seconds":null,"tiers":null,"granted_now":null,"ruby_balance":null}"#)
        #expect(nulls.workedSeconds == 0 && nulls.tiers.isEmpty && nulls.grantedNow.isEmpty && nulls.rubyBalance == nil)
    }

    @Test("디코드: 모르는 칸은 무시 · 깨진 칸 원소 하나만 빠진다 · 소수 초는 내림 · claimed 가 없으면 받지 않은 것 · 모양 틀린 값은 nil")
    func decodesLossily() throws {
        let json = #"""
        {"week_start":"2026-10-12","worked_seconds":72000.9,"future_key":{"x":1},
         "tiers":[{"hours":20,"ruby":20,"claimed":true,"label":"새 칸"},{"hours":"사십","ruby":50},null,{"ruby":200},
                  {"hours":40,"ruby":50},{"hours":60.0,"ruby":200,"claimed":"yes"}],
         "granted_now":[{"hours":20},{"hours":20,"ruby":20,"week_start":5}],
         "ruby_balance":"많음","server_now_ms":1781234567890.0}
        """#
        let status = try Self.decode(json)
        #expect(status.workedSeconds == 72000, "소수 초를 버렸거나 올렸다")
        #expect(status.tiers == [Self.tier(20, 20, true), Self.tier(40, 50, false), Self.tier(60, 200, false)],
                "깨진 원소가 배열 전체를 죽였거나 · 지어낸 칸이 섰다: \(status.tiers)")
        #expect(status.grantedNow == [.init(hours: 20, ruby: 20, weekStart: nil)], "\(status.grantedNow)")
        #expect(status.rubyBalance == nil, "숫자가 아닌 잔량을 0 으로 지어냈다")
        #expect(status.serverNowMs == 1_781_234_567_890)
        #expect(status.nextWeekStart == nil)
    }

    // MARK: - 규칙(카드가 읽는 값)

    @Test("다음 칸 · 막대 · 곧 들어와요: 0 · 19:59:59 · 20:00(받음) · 20:00(아직 장부 없음) · 59:59 · 60+ 다 받음")
    func progressAndNextTier() {
        let zero = Self.dto(worked: 0, claimed: [])
        #expect(WeeklyWorkRules.nextTier(zero) == Self.tier(20, 20, false))
        #expect(WeeklyWorkRules.progress(zero) == 0)
        #expect(!WeeklyWorkRules.isNextTierPending(zero) && !WeeklyWorkRules.allClaimed(zero))
        #expect(MeText.weeklyHours(0) == "0시간 00분")

        let almost = Self.dto(worked: 71_999, claimed: [])
        #expect(WeeklyWorkRules.nextTier(almost)?.hours == 20)
        #expect(WeeklyWorkRules.progress(almost) < 1 && WeeklyWorkRules.progress(almost) > 0.999)
        #expect(!WeeklyWorkRules.isNextTierPending(almost), "19:59:59 를 20시간 넘은 것으로 봤다")
        #expect(MeText.weeklyHours(71_999) == "19시간 59분", "19:59:59 를 20시간으로 올려 적었다")

        let twenty = Self.dto(worked: 72_000, claimed: [20])
        #expect(WeeklyWorkRules.nextTier(twenty) == Self.tier(40, 50, false))
        #expect(WeeklyWorkRules.progress(twenty) == 0.5, "막대 원점이 0 이 아니다(20→40 칸 사이로 재면 0)")
        #expect(MeText.weeklyNextLead(hours: 40) == "40시간 되면" && MeText.weeklyRubyGain(50) == "+50")

        let pending = Self.dto(worked: 72_000, claimed: [])
        #expect(WeeklyWorkRules.nextTier(pending)?.hours == 20)
        #expect(WeeklyWorkRules.isNextTierPending(pending) && WeeklyWorkRules.progress(pending) == 1)
        #expect(MeText.weeklyPending(hours: 20) == "20시간 채웠어요 · 곧 들어와요")

        let fiftyNine = Self.dto(worked: 59 * 3600 + 59 * 60, claimed: [20, 40])
        #expect(WeeklyWorkRules.nextTier(fiftyNine) == Self.tier(60, 200, false))
        #expect(MeText.weeklyHours(fiftyNine.workedSeconds) == "59시간 59분")

        let done = Self.dto(worked: 61 * 3600, claimed: [20, 40, 60])
        #expect(WeeklyWorkRules.nextTier(done) == nil && WeeklyWorkRules.allClaimed(done))
        #expect(WeeklyWorkRules.progress(done) == 1 && WeeklyWorkRules.totalRuby(done) == 270)
        #expect(MeText.weeklyAllDone == "이번 주 보상 다 받았어요")
        #expect(MeText.weeklyAllDoneAccessibility(totalRuby: 270) == "이번 주 보상 다 받았어요, 루비 270개")

        // 서버가 칸 순서를 섞어 보내도(또는 같은 칸을 두 번) 화면은 시간 오름차순 · 한 번씩.
        var shuffled = Self.dto(worked: 30 * 3600, claimed: [20])
        shuffled.tiers = [Self.tier(60, 200, false), Self.tier(20, 20, true), Self.tier(40, 50, false), Self.tier(40, 99, false)]
        #expect(WeeklyWorkRules.sortedTiers(shuffled).map(\.hours) == [20, 40, 60])
        #expect(WeeklyWorkRules.nextTier(shuffled) == Self.tier(40, 50, false))
        // 칸을 하나도 모르면 다 받은 것도 아니고 막대도 0.
        var noTiers = Self.dto(worked: 30 * 3600, claimed: [])
        noTiers.tiers = []
        #expect(!WeeklyWorkRules.allClaimed(noTiers) && WeeklyWorkRules.progress(noTiers) == 0 && WeeklyWorkRules.nextTier(noTiers) == nil)
    }

    @Test("'받았어요' 알림: granted_now 는 늘 · 본 기록과 비교해 새로 받은 칸도(cron 이 먼저 지급한 경우) · 첫 조회는 기준만 · 같은 칸은 한 번")
    func newGrantsDiffAgainstSeen() {
        // 첫 조회(본 기록 없음): 며칠 전에 받은 20 을 방금 받은 것처럼 알리지 않는다.
        let first = Self.dto(worked: 30 * 3600, claimed: [20])
        #expect(WeeklyWorkRules.newGrants(previous: nil, status: first).isEmpty)
        let seen = WeeklyWorkRules.seen(after: first)
        #expect(seen == WeeklyWorkSeen(weekStart: "2026-09-14", claimedHours: [20]))

        // cron 이 40 을 먼저 지급했다(granted_now 는 빈 배열) — 그래도 알린다.
        let cronPaid = Self.dto(worked: 41 * 3600, claimed: [20, 40])
        #expect(WeeklyWorkRules.newGrants(previous: seen, status: cronPaid) == [.init(hours: 40, ruby: 50)])
        #expect(WeeklyWorkRules.notice(for: [.init(hours: 40, ruby: 50)]) == WeeklyWorkGrantNotice(ruby: 50, hours: [40]))

        // 같은 응답을 다시 봐도(기록 갱신 뒤) 알릴 것이 없다.
        #expect(WeeklyWorkRules.newGrants(previous: WeeklyWorkRules.seen(after: cronPaid), status: cronPaid).isEmpty)

        // 이 호출이 넣은 행(granted_now)과 차이가 같은 칸이면 한 번만 센다. 지난주 따라잡기 지급은 따로 센다.
        let both = Self.dto(worked: 61 * 3600, claimed: [20, 40, 60],
                            granted: [.init(hours: 60, ruby: 200), .init(hours: 40, ruby: 50, weekStart: "2026-09-07")])
        let grants = WeeklyWorkRules.newGrants(previous: WeeklyWorkSeen(weekStart: "2026-09-14", claimedHours: [20]), status: both)
        #expect(grants == [.init(hours: 60, ruby: 200), .init(hours: 40, ruby: 50, weekStart: "2026-09-07"), .init(hours: 40, ruby: 50)],
                "\(grants)")
        #expect(WeeklyWorkRules.notice(for: grants) == WeeklyWorkGrantNotice(ruby: 300, hours: [40, 40, 60]))

        // 본 기록이 지난주 것이면 이번 주 받은 칸은 다 처음 본 것이다.
        let lastWeekSeen = WeeklyWorkSeen(weekStart: "2026-09-07", claimedHours: [20, 40, 60])
        #expect(WeeklyWorkRules.newGrants(previous: lastWeekSeen, status: first) == [.init(hours: 20, ruby: 20)])

        // 첫 조회라도 granted_now 는 알린다(이 호출이 방금 넣은 행이다).
        let fresh = Self.dto(worked: 20 * 3600, claimed: [20], granted: [.init(hours: 20, ruby: 20)])
        #expect(WeeklyWorkRules.newGrants(previous: nil, status: fresh) == [.init(hours: 20, ruby: 20)])
        #expect(WeeklyWorkRules.notice(for: []) == nil)
    }

    @Test("본 기록 저장 글자 왕복 · 깨진 글자는 nil · 주를 모르면 저장하지 않는다")
    func seenEncoding() {
        let seen = WeeklyWorkSeen(weekStart: "2026-10-12", claimedHours: [40, 20])
        #expect(seen.encoded == "2026-10-12|20,40")
        #expect(WeeklyWorkSeen(encoded: seen.encoded) == seen)
        #expect(WeeklyWorkSeen(encoded: "2026-10-12|") == WeeklyWorkSeen(weekStart: "2026-10-12", claimedHours: []))
        #expect(WeeklyWorkSeen(encoded: nil) == nil && WeeklyWorkSeen(encoded: "") == nil && WeeklyWorkSeen(encoded: "|20") == nil)
        var unknownWeek = Self.dto(worked: 0, claimed: [])
        unknownWeek.weekStart = nil
        #expect(WeeklyWorkRules.seen(after: unknownWeek) == nil)
    }

    @Test("주 넘김: 다음 주 월요일 0시(KST) 직전은 이번 주 · 0시부터는 지난 값")
    func weekRollover() throws {
        let status = Self.dto(worked: 0, claimed: [])
        let midnight = try #require(WeeklyWorkRules.kstMidnight("2026-09-21"))
        #expect(RankMeFixture.iso(midnight) == "2026-09-20T15:00:00Z", "월요일 0시가 KST 가 아니다")
        #expect(!WeeklyWorkRules.weekHasRolled(status, now: midnight.addingTimeInterval(-1)))
        #expect(WeeklyWorkRules.weekHasRolled(status, now: midnight))
        #expect(!WeeklyWorkRules.weekHasRolled(nil, now: midnight))
        #expect(WeeklyWorkRules.kstMidnight("2026-9") == nil && WeeklyWorkRules.kstMidnight(nil) == nil)
    }

    @Test("루비 미러: 떠날 때와 같을 때만 서버 잔량을 쓴다(그 사이 바뀐 더 새 값을 되돌리지 않는다)")
    func rubyApplyRule() {
        #expect(WeeklyWorkRules.shouldApplyRuby(server: 140, atDeparture: 120, current: 120))
        #expect(WeeklyWorkRules.shouldApplyRuby(server: 140, atDeparture: nil, current: nil))
        #expect(!WeeklyWorkRules.shouldApplyRuby(server: 140, atDeparture: 120, current: 70), "뽑기로 깎인 잔량을 되살렸다")
        #expect(!WeeklyWorkRules.shouldApplyRuby(server: 140, atDeparture: nil, current: 70))
        #expect(!WeeklyWorkRules.shouldApplyRuby(server: nil, atDeparture: 120, current: 120))
    }

    // MARK: - 스토어(진짜 경로)

    @Test("나 탭이 보이면 읽는다: POST 본문 {} · 카드 값 · 루비 미러 · 60초 스로틀 · 61초 뒤 다시 · 금지 호출 0")
    func tabAppearLoadsAndThrottles() async throws {
        let harness = await RankMeHarness(label: "me-weekly-appear") { _ in nil }
        defer { harness.tearDown() }
        let store = harness.me
        #expect(!store.showsWeeklyWork || store.weeklyWork == nil)
        harness.enqueue("weekly_work_status", .json(Self.status(worked: 83_520, claimed: [20], ruby: 133)))
        store.tabDidAppear()
        await harness.quiesceMe()

        let calls = harness.requests(rpc: "weekly_work_status")
        #expect(calls.count == 1)
        #expect(calls.first?.method == "POST" && calls.first?.bodyText == "{}", "본문에 무언가 실렸다: \(calls.first?.bodyText ?? "")")
        let status = try #require(store.weeklyWork)
        #expect(status.workedSeconds == 83_520 && MeText.weeklyHours(status.workedSeconds) == "23시간 12분")
        #expect(store.showsWeeklyWork && store.weeklyWorkState.hasLoaded)
        #expect(WeeklyWorkRules.nextTier(status)?.hours == 40)
        #expect(store.rubyBalance == 133 && harness.model.gomokuHost.rubyBalance == 133, "정산 잔량이 미러에 안 실렸다")
        #expect(store.weeklyGrantNotice == nil && store.weeklyGrantSerial == 0, "첫 조회인데 지난 지급을 '받았어요'로 알렸다")

        // 30초 뒤 탭을 다시 열었다 — 스로틀.
        store.tabDidDisappear()
        harness.clock.advance(30)
        store.tabDidAppear()
        await harness.quiesceMe()
        #expect(harness.requests(rpc: "weekly_work_status").count == 1, "1분 안에 또 물었다")

        // 61초 더 — 다시 묻는다.
        store.tabDidDisappear()
        harness.clock.advance(31)
        harness.enqueue("weekly_work_status", .json(Self.status(worked: 84_000, claimed: [20], ruby: 133)))
        store.tabDidAppear()
        await harness.quiesceMe()
        #expect(harness.requests(rpc: "weekly_work_status").count == 2)
        #expect(store.weeklyWork?.workedSeconds == 84_000)
        harness.expectNoForbiddenCalls()
    }

    @Test("앱이 앞에 오면 나 탭이 안 보여도 읽는다(스로틀 같음) · 그 지급은 칩으로 남아 탭을 열고 떠날 때 걷힌다")
    func foregroundLoadsWhileTabHidden() async throws {
        let harness = await RankMeHarness(label: "me-weekly-foreground") { _ in nil }
        defer { harness.tearDown() }
        let store = harness.me
        #expect(!store.isTabVisible)
        harness.enqueue("weekly_work_status", .json(Self.status(worked: 30 * 3600, claimed: [20], ruby: 100)))
        store.appDidBecomeActive()
        await harness.quiesceMe()
        #expect(harness.requests(rpc: "weekly_work_status").count == 1, "앞에 왔는데 주간 보상을 안 읽었다")
        // 탭이 안 보이니 다른 루트 조회는 안 나갔다(기존 동작 그대로).
        #expect(harness.requests(rpc: "shop_state").isEmpty)

        // cron 이 40 을 지급한 뒤 다시 앞에 왔다 — 탭은 여전히 안 보인다.
        harness.clock.advance(61)
        harness.enqueue("weekly_work_status", .json(Self.status(worked: 41 * 3600, claimed: [20, 40], ruby: 150)))
        store.appDidBecomeActive()
        await harness.quiesceMe()
        #expect(store.weeklyGrantNotice == WeeklyWorkGrantNotice(ruby: 50, hours: [40]), "cron 이 먼저 준 칸을 알리지 않는다")
        #expect(store.weeklyGrantSerial == 1)
        #expect(store.rubyBalance == 150)

        // 탭을 안 본 채로는 걷히지 않는다 → 열고(본다) → 떠나면 걷힌다.
        store.tabDidDisappear()
        #expect(store.weeklyGrantNotice != nil, "보지도 않은 알림을 걷었다")
        harness.enqueue("weekly_work_status", .json(Self.status(worked: 41 * 3600, claimed: [20, 40], ruby: 150)))
        store.tabDidAppear()
        await harness.quiesceMe()
        #expect(store.weeklyGrantNotice != nil && store.weeklyGrantSerial == 1, "같은 칸을 또 알렸거나 탭을 열자마자 걷었다")
        store.tabDidDisappear()
        #expect(store.weeklyGrantNotice == nil, "본 알림이 떠난 뒤에도 남는다")
        harness.expectNoForbiddenCalls()
    }

    @Test("나 탭에서 바로 들어온 지급: granted_now → '+N 받음' · 햅틱 순번 +1 · 여러 칸은 합쳐서 한 번")
    func grantedNowWhileVisible() async throws {
        let harness = await RankMeHarness(label: "me-weekly-granted") { request in
            request.rpcName == "shop_state" ? .json(#"{"ruby_balance":330,"characters":[]}"#) : nil
        }
        defer { harness.tearDown() }
        let store = harness.me
        harness.enqueue("weekly_work_status", .json(Self.status(
            worked: 60 * 3600, claimed: [20, 40, 60],
            granted: #"[{"hours":20,"ruby":20},{"hours":40,"ruby":50},{"hours":60,"ruby":200}]"#, ruby: 330)))
        store.tabDidAppear()
        await harness.quiesceMe()
        #expect(store.weeklyGrantNotice == WeeklyWorkGrantNotice(ruby: 270, hours: [20, 40, 60]))
        #expect(store.weeklyGrantSerial == 1, "세 칸을 세 번 따로 울렸다")
        let status = try #require(store.weeklyWork)
        #expect(WeeklyWorkRules.allClaimed(status) && WeeklyWorkRules.totalRuby(status) == 270)
        #expect(store.rubyBalance == 330)
    }

    @Test("루비: 조회가 떠 있는 사이 뽑기가 잔량을 깎았으면 되돌리지 않는다 — 받은 게 있으면 상점을 다시 읽어 맞춘다")
    func rubyNotRegressedByLateResponse() async throws {
        let harness = await RankMeHarness(label: "me-weekly-ruby") { _ in nil }
        defer { harness.tearDown() }
        let store = harness.me
        // 기준(본 기록 20) 을 먼저 잡는다.
        harness.enqueue("weekly_work_status", .json(Self.status(worked: 30 * 3600, claimed: [20], ruby: 200)))
        await store.loadWeeklyWork()
        #expect(store.rubyBalance == 200)

        let hold = BaseHold.rpc("weekly_work_status", host: harness.host)
        harness.enqueue("weekly_work_status", .json(Self.status(worked: 41 * 3600, claimed: [20, 40], ruby: 250)))
        harness.enqueue("shop_state", .json(#"{"ruby_balance":200,"characters":[]}"#))
        let load = Task { await store.loadWeeklyWork() }
        #expect(await hold.waitHeld())
        // 그 사이 다른 응답(뽑기 −50)이 미러를 바꿨다.
        harness.model.gomokuHost.rubyBalance = 150
        #expect(await hold.releaseAndWaitDelivered())
        await load.value
        await harness.quiesceMe()
        #expect(store.weeklyWork?.workedSeconds == 41 * 3600, "응답 자체를 버렸다")
        #expect(harness.requests(rpc: "shop_state").count == 1, "잔량을 못 쓴 채 지급이 있었는데 상점을 다시 읽지 않았다")
        #expect(store.rubyBalance == 200, "상점 다시 읽기 값으로 맞추지 않았다(250 = 되돌림, 150 = 지급 누락)")
        #expect(store.weeklyGrantNotice == WeeklyWorkGrantNotice(ruby: 50, hours: [40]))

        // 받은 게 없고 미러만 바뀌었으면 아무것도 안 한다(상점도 안 읽는다).
        let hold2 = BaseHold.rpc("weekly_work_status", host: harness.host)
        harness.enqueue("weekly_work_status", .json(Self.status(worked: 42 * 3600, claimed: [20, 40], ruby: 250)))
        let load2 = Task { await store.loadWeeklyWork() }
        #expect(await hold2.waitHeld())
        harness.model.gomokuHost.rubyBalance = 90
        #expect(await hold2.releaseAndWaitDelivered())
        await load2.value
        await harness.quiesceMe()
        #expect(store.rubyBalance == 90 && harness.requests(rpc: "shop_state").count == 1)
    }

    @Test("함수가 없는 서버(404): 카드를 접고 60초 안엔 다시 안 묻는다 · 그 뒤 서버에 생기면 카드가 선다")
    func missingFunctionFoldsCard() async throws {
        let harness = await RankMeHarness(label: "me-weekly-missing") { _ in nil }
        defer { harness.tearDown() }
        let store = harness.me
        store.appDidBecomeActive()   // 기본 응답 = 404 PGRST202
        await harness.quiesceMe()
        #expect(harness.requests(rpc: "weekly_work_status").count == 1)
        #expect(!store.weeklyWorkAvailable && !store.showsWeeklyWork && store.weeklyWork == nil)

        harness.clock.advance(30)
        store.appDidBecomeActive()
        await harness.quiesceMe()
        #expect(harness.requests(rpc: "weekly_work_status").count == 1, "없는 함수를 1분 안에 또 두드렸다")

        harness.clock.advance(31)
        harness.enqueue("weekly_work_status", .json(Self.status(worked: 3600, claimed: [], ruby: 10)))
        store.appDidBecomeActive()
        await harness.quiesceMe()
        #expect(store.weeklyWorkAvailable && store.showsWeeklyWork && store.weeklyWork?.workedSeconds == 3600)
    }

    @Test("실패(5xx · 오프라인): 지난 값을 지킨다(0 으로 지어내지 않는다) · 다음 활성화에 바로 다시 묻는다")
    func failureKeepsLastValue() async throws {
        let harness = await RankMeHarness(label: "me-weekly-failure") { _ in nil }
        defer { harness.tearDown() }
        let store = harness.me
        harness.enqueue("weekly_work_status", .json(Self.status(worked: 50 * 3600, claimed: [20, 40], ruby: 70)))
        await store.loadWeeklyWork()
        harness.clock.advance(61)
        harness.enqueue("weekly_work_status", .json(#"{"message":"boom"}"#, status: 503))
        store.appDidBecomeActive()
        await harness.quiesceMe()
        #expect(store.weeklyWorkState.hasFailed && store.weeklyWork?.workedSeconds == 50 * 3600 && store.showsWeeklyWork)
        #expect(store.rubyBalance == 70)
        harness.enqueue("weekly_work_status", .networkFailure())
        store.appDidBecomeActive()
        await harness.quiesceMe()
        #expect(harness.requests(rpc: "weekly_work_status").count == 3, "실패 뒤 다음 활성화가 다시 묻지 않았다")
        #expect(store.weeklyWork?.workedSeconds == 50 * 3600)
    }

    @Test("주가 바뀌었으면(월요일 0시) 스로틀 안이어도 다시 읽는다")
    func rolloverBypassesThrottle() async throws {
        // 일요일 23:59:30 KST 에서 시작한다.
        let sunday = try #require(WeeklyWorkRules.kstMidnight("2026-09-21")).addingTimeInterval(-30)
        let harness = await RankMeHarness(label: "me-weekly-rollover", clockStart: sunday) { _ in nil }
        defer { harness.tearDown() }
        let store = harness.me
        harness.enqueue("weekly_work_status", .json(Self.status(worked: 65 * 3600, claimed: [20, 40, 60], ruby: 500)))
        store.appDidBecomeActive()
        await harness.quiesceMe()
        harness.clock.advance(31)   // 월요일 00:00:01 — 스로틀(60초) 안
        harness.enqueue("weekly_work_status", .json(Self.status(worked: 1, claimed: [], ruby: 500, week: "2026-09-21", next: "2026-09-28")))
        store.appDidBecomeActive()
        await harness.quiesceMe()
        #expect(harness.requests(rpc: "weekly_work_status").count == 2, "월요일이 됐는데 지난주 값(65시간 · 다 받음)을 1분 더 보여 준다")
        #expect(store.weeklyWork?.weekStart == "2026-09-21" && store.weeklyWork?.workedSeconds == 1)
        #expect(store.weeklyGrantNotice == nil, "새 주에 받은 칸이 없는데 알렸다")
    }

    @Test("세대 가드 · 로그아웃: 앞 계정의 늦은 응답은 버린다 · reset 이 카드 값을 다 비운다 · 본 기록 키는 계정별")
    func generationGuardAndReset() async throws {
        let harness = await RankMeHarness(label: "me-weekly-generation") { _ in nil }
        defer { harness.tearDown() }
        let store = harness.me
        harness.enqueue("weekly_work_status", .json(Self.status(worked: 41 * 3600, claimed: [20, 40],
                                                                 granted: #"[{"hours":40,"ruby":50}]"#, ruby: 99)))
        await store.loadWeeklyWork()
        #expect(store.weeklyGrantNotice != nil && store.weeklyWork != nil)
        #expect(harness.storage.defaults.string(forKey: "aing.me.weeklyWorkSeen.\(RankMeFixture.userID)") == "2026-09-14|20,40")

        let hold = BaseHold.rpc("weekly_work_status", host: harness.host)
        harness.enqueue("weekly_work_status", .json(Self.status(worked: 61 * 3600, claimed: [20, 40, 60],
                                                                 granted: #"[{"hours":60,"ruby":200}]"#, ruby: 299)))
        let late = Task { await store.loadWeeklyWork() }
        #expect(await hold.waitHeld())
        await harness.model.session.signOut()
        #expect(store.weeklyWork == nil && store.weeklyGrantNotice == nil && store.weeklyGrantSerial == 0)
        #expect(store.weeklyWorkAvailable && !store.weeklyWorkState.hasLoaded && !store.showsWeeklyWork)
        #expect(await hold.releaseAndWaitDelivered())
        await late.value
        #expect(store.weeklyWork == nil && store.weeklyGrantNotice == nil, "로그아웃 뒤 앞 계정의 응답이 섰다")
        #expect(harness.model.gomokuHost.rubyBalance == nil, "로그아웃 뒤 앞 계정의 잔량이 미러에 섰다")
    }

    // MARK: - 폰 [근무 종료] 뒤

    @Test("폰 [근무 종료]가 근무를 닫으면 주간 보상을 스로틀 없이 다시 읽는다 · mismatch 는 안 읽는다")
    func clockOutRefreshesWeekly() async throws {
        let h = NowHarness()
        defer { h.tearDown() }
        h.server.override("rpc.work_phone_touch", .json(NowPhoneWorkTests.touchMac))
        h.server.override("rpc.weekly_work_status", .json(Self.status(worked: 20 * 3600, claimed: [20], ruby: 42)))
        await h.launch()
        await h.activate()
        await h.store.phoneTouchTask?.value
        await h.settle()
        let me = h.model.me
        await me.loadWeeklyWork()   // 방금 읽었다 — 스로틀 안
        let before = h.requests("rpc.weekly_work_status").count

        h.server.override("rpc.work_phone_stop", .json(#"{"status":"mismatch","session":{"id":"s5"}}"#))
        await h.store.clockOut()
        await h.settle()
        #expect(h.requests("rpc.weekly_work_status").count == before, "닫히지 않은 근무에 주간 보상을 다시 읽었다")

        h.server.override("rpc.work_phone_stop", .json(#"""
        {"status":"ok","session":{"id":"s1","started_at":"2026-09-17T01:20:00+00:00","ended_at":"2026-09-17T05:05:00+00:00","origin":"mac"},
         "server_now":"2026-09-17T05:05:00+00:00","wallet":null}
        """#))
        await h.store.clockOut()
        for task in me.inflight { await task.value }
        await h.settle()
        #expect(h.requests("rpc.weekly_work_status").count == before + 1, "근무를 닫았는데 주간 보상을 다시 읽지 않았다(스로틀에 막혔다)")
        #expect(h.violations.isEmpty, "\(h.violations)")
    }

    // MARK: - 화면(iOS 전용 — 소스 계약 · 주석은 걷어내고 본다)

    @Test("카드 소스: 무대 바로 다음 · 서버 값만(칸 숫자를 박지 않는다) · 햅틱은 지급 순번 · '+N 받음'은 기존 RubyGain · 규칙 한 줄")
    func cardSourceContract() throws {
        let home = try IntegrationContractTests.code("Sources/CheckMobileKit/Me/MeTab.swift")
        let stage = try #require(home.range(of: "MeStageCard(store: store)"))
        let weekly = try #require(home.range(of: "MeWeeklyWorkCard(store: store)"), "나 탭에 주간 보상 카드가 없다")
        let lastWeek = try #require(home.range(of: "MeRecordsCard(store: store)"))
        #expect(stage.upperBound < weekly.lowerBound && weekly.upperBound < lastWeek.lowerBound,
                "카드 자리: 무대(루비 칩) → 이번 주 근무 → 「지난주」")

        let card = try IntegrationContractTests.code("Sources/CheckMobileKit/Me/MeWeeklyWorkViews.swift")
        #expect(card.contains("store.showsWeeklyWork"), "서버에 함수가 없어도 카드가 선다")
        #expect(card.contains(".sensoryFeedback(.success, trigger: store.weeklyGrantSerial)"), "지급 햅틱이 없다")
        #expect(card.contains("RubyGain(notice.ruby, suffix: MeText.weeklyGrantSuffix, style: .chip)"),
                "'받았어요'를 기존 루비 획득 칩이 아닌 새 모양으로 그린다")
        #expect(card.contains("MeText.weeklyRule") && card.contains("MeText.weeklyTitle"))
        #expect(card.contains("WeeklyWorkRules.progress(") && card.contains("WeeklyWorkRules.sortedTiers("))
        #expect(card.contains("RubyIcon("), "루비를 실제 보석이 아닌 기호로 그린다")
        #expect(!card.contains("💎") && !card.contains("diamond"), "진홍 마름모·이모지 루비(폰 규약 위반)")
        // 칸 값(20·40·60 · 20·50·200 · 270)은 서버가 말한다 — 카드가 숫자를 박으면 서버 표를 바꿔도 화면이 그대로다.
        for literal in ["20", "40", "50", "60", "200", "270", "3600"] {
            let pattern = "(?<![0-9.])\(literal)(?![0-9])"
            #expect(card.range(of: pattern, options: .regularExpression) == nil, "카드 소스에 칸 숫자 \(literal) 이 박혔다")
        }
        #expect(MeText.weeklyTitle == "이번 주 근무" && MeText.weeklyRule == "월요일 0시에 새로 세요")
        #expect(MeText.weeklyTierHours(60) == "60h", "칩이 길어져 세 칸 다 받은 줄이 세로로 쌓인다(402pt 실측)")
        #expect(MeText.weeklyTierAccessibility(hours: 20, ruby: 20, claimed: true) == "20시간 루비 20개, 받음")
        #expect(MeText.weeklyNextAccessibility(hours: 40, ruby: 50) == "40시간 되면 루비 50개")
    }

    @Test("주간 보상 RPC 는 폰 금지 목록에 없다 · 데모 장면(me · me/)에 픽스처가 있다")
    func notForbiddenAndDemoFixtures() throws {
        #expect(!MobileForbiddenCalls.forbiddenRPCs.contains("weekly_work_status"))
        let fixtures = MobileDemoFixtures.load()
        let request = MobileStubRequest(method: "POST", host: MobileDemo.host, path: SupabaseWorkService.weeklyWorkStatusPath,
                                        query: "", headers: [:], bodyText: "{}")
        let me = try #require(fixtures.entry(for: request, scenario: "me"), "나 탭 데모 장면에 주간 보상 픽스처가 없다")
        let status = try Self.decode(String(decoding: me.data, as: UTF8.self))
        #expect(status.weekStart == "2026-09-14" && MeText.weeklyHours(status.workedSeconds) == "23시간 12분")
        let empty = try #require(fixtures.entry(for: request, scenario: "me-"))
        #expect(try Self.decode(String(decoding: empty.data, as: UTF8.self)).workedSeconds == 0)
        // 다른 장면(게임 탭 등)에는 없다 — 거기서 잔량을 덮어 스크린샷 알약 값이 바뀌지 않게.
        #expect(fixtures.entry(for: request, scenario: "games") == nil)
    }
}
