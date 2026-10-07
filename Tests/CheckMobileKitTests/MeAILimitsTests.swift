import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit
@testable import CheckWidgetsKit

/// v0.3.45 AI 리밋 — **폰 쪽**: 서버 읽기(GET 하나 · 본인 행만) · 제공자별 최신 고르기 · 늦은 응답 가드 ·
/// 실패에도 들고 있던 값 지키기 · 위젯으로 넘기기(쓰는 주체는 지금 탭) · 카드 소스 계약.
@MainActor
@Suite("나 탭 AI 리밋(v0.3.45)")
struct MeAILimitsTests {
    /// 세 제공자 + 모르는 제공자 + 기기 둘(같은 Claude 계정을 맥 두 대가 읽은 모양).
    nonisolated static let rows = #"""
    [
      {"provider":"claude","five_hour_percent":27,"five_hour_resets_at":"2026-09-17T07:40:00.434051+00:00",
       "weekly_percent":60,"weekly_resets_at":"2026-09-22T10:05:00+00:00","plan_label":"max","observed_at":"2026-09-17T05:03:00.128+00:00"},
      {"provider":"claude","five_hour_percent":9,"five_hour_resets_at":"2026-09-17T07:40:00+00:00",
       "weekly_percent":11,"weekly_resets_at":"2026-09-22T10:05:00+00:00","plan_label":"max","observed_at":"2026-09-17T02:00:00+00:00"},
      {"provider":"codex","five_hour_percent":0,"five_hour_resets_at":null,
       "weekly_percent":56,"weekly_resets_at":"2026-09-21T06:51:40+00:00","plan_label":"plus","observed_at":"2026-09-17T05:00:00+00:00"},
      {"provider":"antigravity","five_hour_percent":null,"five_hour_resets_at":null,
       "weekly_percent":8,"weekly_resets_at":"2026-09-23T11:05:00+00:00","plan_label":null,"observed_at":"2026-09-17T04:55:00+00:00"},
      {"provider":"future-provider","five_hour_percent":99,"five_hour_resets_at":"2026-09-17T07:40:00+00:00",
       "weekly_percent":99,"weekly_resets_at":"2026-09-22T10:05:00+00:00","plan_label":null,"observed_at":"2026-09-17T05:04:00+00:00"}
    ]
    """#

    nonisolated static func responder(_ request: MobileStubRequest) -> MobileStubResponse? {
        if request.path == "/rest/v1/ai_limits", request.method == "GET" { return .json(rows) }
        return MeStoreTests.rootResponder(request)
    }

    // MARK: - 읽기

    @Test("시나리오: 탭을 열지 않아도(active 진입) 리밋을 한 번 읽는다 · 본인 행만 · 쓰기 0 · 금지 호출 0")
    func loadsWithoutOpeningTab() async throws {
        let harness = await RankMeHarness(label: "me-ailimits") { Self.responder($0) }
        defer { harness.tearDown() }
        let store = harness.me

        // 나 탭은 보이지 않는다 — 그래도 리밋은 받는다(위젯이 이 값의 소비자다).
        store.appDidBecomeActive()
        #expect(await baseWaitUntil { store.aiLimits.state.hasLoaded })
        #expect(!store.isTabVisible, "전제: 탭은 아직 보이지 않는다")
        #expect(harness.requests(rpc: "shop_state").isEmpty, "보이지 않는 나 탭이 다른 조회까지 띄웠다")

        let gets = harness.requests(path: "/rest/v1/ai_limits", method: "GET")
        #expect(gets.count == 1, "리밋 조회가 \(gets.count)번 나갔다")
        let get = try #require(gets.first)
        #expect(get.queryValue("user_id") == "eq.\(RankMeFixture.userID)", "본인 행만 거르지 않았다 — RLS 가 막아 주지만 쿼리도 좁혀야 한다")
        #expect(get.query.contains("five_hour_percent") && get.query.contains("weekly_resets_at"))
        #expect(!get.query.contains("device_id"), "쓰지 않는 칸(기기 식별자)을 받아 온다")
        #expect(!get.query.contains("account_fingerprint"), "폰이 계정 지문을 받아 온다(쓰임이 없는 값이다)")

        let writes = harness.requests.filter { $0.path == "/rest/v1/ai_limits" && $0.method.uppercased() != "GET" }
        #expect(writes.isEmpty, "폰이 리밋 표에 썼다 — 올리는 쪽은 맥 하나다")
        harness.expectNoForbiddenCalls()

        // 제공자별 최신 하나(맥 두 대의 Claude 행에서 05:03 쪽) · 모르는 제공자는 버린다 · 순서 고정.
        let rows = store.aiLimits.displayRows
        #expect(rows.map(\.provider) == [.claude, .codex, .antigravity])
        let claude = try #require(rows.first)
        #expect(claude.planLabel == "max")
        #expect(claude.fiveHour?.valueText == "27%", "오래된 기기 행(9%)이 이겼다")
        // 소수초가 붙은 `observed_at`("…05:03:00.128+00:00")도 읽힌다 — 포매터 한 벌이면 nil 이 되고 그 행은 버려진다
        // (119.9초 전이라 나이는 "1분 전"이다. 파싱이 깨졌다면 행 자체가 사라져 위의 단언들이 먼저 빨갛다).
        #expect(claude.fiveHour?.captionText == "1분 전")
        #expect(claude.weekly?.valueText == "60%")
        // 안티그래비티는 5시간 창이 없다 — 줄을 지어내지 않는다.
        let antigravity = try #require(rows.last)
        #expect(antigravity.fiveHour == nil && antigravity.weekly?.valueText == "8%")
        #expect(antigravity.visibleWindows.count == 1)
        // Codex 0% 는 리셋을 주장하지 않는다(가짜 reset_at 함정) — 맥이 nil 로 올렸고 캡션은 나이다.
        let codex = try #require(rows.dropFirst().first)
        #expect(codex.fiveHour?.valueText == "0%" && codex.fiveHour?.freshness.isResetClaim == false)
        #expect(codex.fiveHour?.resetsAt == nil)
        // 요약은 **5시간 창만** 모은다(주간 60% 가 이기면 지금 여유가 안 보인다).
        #expect(store.aiLimits.fiveHourSummary?.valueText == "27%")
        #expect(store.aiLimits.hasVisibleProviders)
    }

    @Test("위젯: 받은 값을 지금 탭이 스냅샷 **최상위 칸**에 쓴다(리밋 스토어는 쓰지 않는다) · 토큰 줄은 기록이 와야 선다")
    func pushesPanelThroughNowStore() async throws {
        let harness = await RankMeHarness(label: "me-ailimits-widget") { Self.responder($0) }
        defer { harness.tearDown() }
        let store = harness.me

        store.appDidBecomeActive()
        #expect(await baseWaitUntil { harness.model.context.widgetSnapshots.current?.aiLimits != nil })
        let panel = try #require(harness.model.context.widgetSnapshots.current?.aiLimits)
        #expect(panel.providers.map(\.provider) == ["claude", "codex", "antigravity"], "모르는 제공자가 위젯까지 갔다")
        #expect(panel.providers[0].fiveHourPercent == 27)
        #expect(panel.providers[1].fiveHourResetsAt == nil, "0% 행의 가짜 리셋 시각을 위젯에 실었다")
        #expect(panel.todayTokens == nil, "기록을 받기 전인데 토큰 수를 지어냈다")

        // 파일에도 같은 값(위젯 확장이 읽는 그 파일).
        let file = try #require(WidgetSnapshotCodec.read(from: harness.storage.widgetSnapshotURL))
        #expect(file.aiLimits == panel)

        // 기록(토큰 잔디)이 오면 토큰 줄이 선다 — 리밋을 다시 읽지 않고.
        let before = harness.requests(path: "/rest/v1/ai_limits", method: "GET").count
        store.tabDidAppear()
        #expect(await baseWaitUntil { store.recordsState.hasLoaded })
        await harness.quiesceMe()
        #expect(await baseWaitUntil { harness.model.context.widgetSnapshots.current?.aiLimits?.todayTokens != nil })
        let withTokens = try #require(harness.model.context.widgetSnapshots.current?.aiLimits)
        #expect(withTokens.recentTokens == store.tokenGrid.totalTokens)
        #expect(withTokens.todayTokens == AILimitsStore.todayTokens(store.tokenGrid))
        #expect(harness.requests(path: "/rest/v1/ai_limits", method: "GET").count == before, "토큰이 왔다고 리밋을 다시 물었다")
        harness.expectNoForbiddenCalls()
    }

    @Test("실패·낡음: 404 는 들고 있던 값을 비우지 않고 다시 묻는다 · 성공한 뒤 60초 안에는 묻지 않는다")
    func failureKeepsValuesAndFreshnessGate() async throws {
        let answer = BaseLockedBox(true)
        let harness = await RankMeHarness(label: "me-ailimits-fail") { request in
            if request.path == "/rest/v1/ai_limits", request.method == "GET" {
                return answer.get() ? .json(Self.rows) : .missingFunction(request.path)
            }
            return MeStoreTests.rootResponder(request)
        }
        defer { harness.tearDown() }
        let store = harness.me

        store.appDidBecomeActive()
        #expect(await baseWaitUntil { store.aiLimits.state.hasLoaded })
        let loaded = store.aiLimits.displayRows.count
        #expect(loaded == 3)

        // 신선하면 다시 묻지 않는다(시계를 안 돌렸다).
        let before = harness.requests(path: "/rest/v1/ai_limits", method: "GET").count
        store.appDidBecomeActive()
        await harness.barrier()
        #expect(harness.requests(path: "/rest/v1/ai_limits", method: "GET").count == before, "신선한 값을 다시 물었다")

        // 60초를 넘기고 실패시키면 — 실패 깃발만 서고 값은 그대로.
        answer.mutate { $0 = false }
        harness.clock.advance(AILimitsStore.staleSeconds + 1)
        store.appDidBecomeActive()
        #expect(await baseWaitUntil { store.aiLimits.state.hasFailed })
        #expect(store.aiLimits.displayRows.count == loaded, "실패가 들고 있던 리밋을 비웠다")
        #expect(harness.model.context.widgetSnapshots.current?.aiLimits?.providers.count == 3, "실패가 위젯 값을 지웠다")
    }

    @Test("계정 교체: reset 이 묶음·상태·위젯 값 흔적을 지운다")
    func resetClearsEverything() async throws {
        let harness = await RankMeHarness(label: "me-ailimits-reset") { Self.responder($0) }
        defer { harness.tearDown() }
        let store = harness.me
        store.appDidBecomeActive()
        #expect(await baseWaitUntil { store.aiLimits.state.hasLoaded })
        #expect(store.aiLimits.bundle != nil)

        store.reset()
        #expect(store.aiLimits.bundle == nil && !store.aiLimits.state.hasLoaded)
        #expect(store.aiLimits.displayRows.isEmpty && store.aiLimits.fiveHourSummary == nil)
        #expect(store.aiLimits.widgetPanel() == nil, "비운 뒤에도 위젯에 넘길 값이 있다")
    }

    // MARK: - 순수 규칙

    @Test("고르기: 제공자별 최신 하나 · 모르는 제공자 버림 · 창 없는 행 버림 · 소스는 server")
    func bundlePicksNewestPerProvider() throws {
        let base = MobileClock.demoInstant
        let rows = [
            AILimitFetchedRow(provider: "claude", fiveHourPercent: 9, fiveHourResetsAt: nil, weeklyPercent: 11,
                              weeklyResetsAt: nil, planLabel: "max", observedAt: base.addingTimeInterval(-3_600)),
            AILimitFetchedRow(provider: "claude", fiveHourPercent: 27, fiveHourResetsAt: base.addingTimeInterval(9_000),
                              weeklyPercent: 60, weeklyResetsAt: nil, planLabel: "max", observedAt: base),
            AILimitFetchedRow(provider: "future-provider", fiveHourPercent: 99, fiveHourResetsAt: nil, weeklyPercent: nil,
                              weeklyResetsAt: nil, planLabel: nil, observedAt: base),
            // 퍼센트가 둘 다 없다 — 창이 0개라 숨는다(미연동과 같다).
            AILimitFetchedRow(provider: "codex", fiveHourPercent: nil, fiveHourResetsAt: nil, weeklyPercent: nil,
                              weeklyResetsAt: nil, planLabel: "plus", observedAt: base),
        ]
        let bundle = AILimitsStore.bundle(from: rows, now: base)
        #expect(bundle.schemaVersion == AILimitSnapshotBundle.currentSchemaVersion)
        #expect(bundle.visibleProviders.map(\.provider) == [.claude])
        let claude = try #require(bundle.provider(.claude))
        #expect(claude.window(.fiveHour)?.usedPercent == 27, "오래된 행이 이겼다")
        #expect(claude.window(.fiveHour)?.resetsAt == base.addingTimeInterval(9_000))
        #expect(claude.orderedWindows.map(\.window) == [.fiveHour, .weekly])
        #expect(claude.source == .server, "폰이 받은 값인데 경로가 server 가 아니다")
        #expect(bundle.provider(.codex)?.isLinked == false)
    }

    /// ★ 유령 행을 숨긴다(v0.3.45 P2). 맥에서 로그아웃한 제공자는 업로드에서 **빠질 뿐**이고 서버에는 DELETE
    /// 권한도 정리 cron 도 없다 → 그 행이 영원히 남아, 시간이 지나면 리셋을 지나 `0% · 초기화됨` 으로 굳는다.
    /// 쓰지도 않는 제공자가 "한도를 하나도 안 썼다"로 **영구 표시**되는 것이다.
    /// 그래서 읽는 쪽에서 끊는다 — 문턱의 **양쪽**을 잰다(한쪽만 재면 `>=` 를 `>` 로 바꿔도, 문턱을 10배로
    /// 늘려도 초록이다).
    @Test("유령 행: observed_at 이 문턱보다 오래된 줄은 숨는다(양쪽 경계) · 살아 있는 줄은 남는다")
    func ghostRowsAreHidden() throws {
        let base = MobileClock.demoInstant
        let cutoff = AILimitsStore.ghostRowAge
        func row(_ provider: String, age: TimeInterval) -> AILimitFetchedRow {
            AILimitFetchedRow(provider: provider, fiveHourPercent: 27,
                              fiveHourResetsAt: base.addingTimeInterval(-age + 600),
                              weeklyPercent: 60, weeklyResetsAt: nil, planLabel: nil,
                              observedAt: base.addingTimeInterval(-age))
        }
        // 문턱 **직전**(1초 모자란다)은 남고, 문턱 **정확히**는 숨는다.
        let justInside = AILimitsStore.bundle(from: [row("claude", age: cutoff - 1)], now: base)
        #expect(justInside.visibleProviders.map(\.provider) == [.claude],
                "아직 문턱에 닿지 않은 줄을 숨겼다 — 맥을 며칠 끈 사람의 하한까지 사라진다")
        let exactly = AILimitsStore.bundle(from: [row("claude", age: cutoff)], now: base)
        #expect(exactly.visibleProviders.isEmpty, "문턱에 닿은 유령 행이 남았다 — '0% · 초기화됨' 으로 굳는다")
        let wayOld = AILimitsStore.bundle(from: [row("codex", age: cutoff * 10)], now: base)
        #expect(wayOld.visibleProviders.isEmpty)

        // 산 제공자와 유령이 섞여 있으면 **산 쪽만** 남는다(목록이 통째로 비지 않는다).
        let mixed = AILimitsStore.bundle(
            from: [row("claude", age: 300), row("antigravity", age: cutoff + 60)], now: base
        )
        #expect(mixed.visibleProviders.map(\.provider) == [.claude])

        // ★ 문턱은 **맥의 갱신 주기보다 훨씬 커야** 한다 — 켜져 있는 맥의 제공자가 숨는 조합이 없어야 한다.
        #expect(cutoff > 3_600 * 24, "문턱이 하루보다 짧다 — 주말에 맥을 끈 사람의 줄이 사라진다")
        // 미래 관측(기기 시계가 어긋난 맥)은 여기서 **버리지 않는다** — 그 판정은 코어 규칙이 한다.
        let future = AILimitsStore.bundle(from: [row("claude", age: -7_200)], now: base)
        #expect(future.visibleProviders.map(\.provider) == [.claude])
    }

    /// ★ **대표 창 고르기는 한 규칙이다**(v0.3.45 P2): 보이는 창을 5시간 → 주간 순서로 세우고 **첫 줄이 대표**다.
    ///
    /// 맥 카드는 초안에서 `.fiveHour` 를 무조건 머리 숫자로 그려, 주간만 오는 계정에서 큰 글자가 `—` · 캡션이
    /// `알 수 없음` 이었다(같은 데이터로 폰·위젯은 주간을 세웠다 — 세 화면이 다른 말을 했다). 맥 쪽 그물은
    /// `AILimitsMacWindowContentTests` 에 있고(모듈이 달라 한 테스트로 묶을 수 없다), 여기서는 **폰과 위젯이
    /// 서로 같은 창을 세우는지**를 같은 데이터로 되묻는다.
    @Test("대표 창: 폰과 위젯이 같은 창을 세운다(주간만 오는 계정에서도) · 대표로 선 창을 두 번 그리지 않는다")
    func representativeWindowIsOneRuleAcrossSurfaces() throws {
        let base = MobileClock.demoInstant
        func rows(fiveHour: Double?) -> [AILimitFetchedRow] {
            [AILimitFetchedRow(provider: "antigravity", fiveHourPercent: fiveHour,
                               fiveHourResetsAt: fiveHour == nil ? nil : base.addingTimeInterval(9_000),
                               weeklyPercent: 42, weeklyResetsAt: base.addingTimeInterval(86_400),
                               planLabel: nil, observedAt: base)]
        }
        func surfaces(fiveHour: Double?) throws -> (phone: AILimitDisplay, widget: (display: AILimitDisplay, label: String)) {
            let snapshot = try #require(AILimitsStore.bundle(from: rows(fiveHour: fiveHour), now: base)
                .provider(.antigravity))
            func display(_ window: AILimitWindow) -> AILimitDisplay? {
                guard snapshot.window(window) != nil else { return nil }
                let value = AILimitFreshnessRule.display(provider: snapshot, window: window, now: base)
                return value.isVisible ? value : nil
            }
            let phone = AILimitDisplayRow(provider: .antigravity, planLabel: nil,
                                          fiveHour: display(.fiveHour), weekly: display(.weekly))
            let widget = AingWidgetLimitRow(provider: .antigravity,
                                            fiveHour: display(.fiveHour), weekly: display(.weekly))
            return (try #require(phone.visibleWindows.first), try #require(widget.primaryWindow))
        }
        // ① 주간만 오는 계정: 둘 다 **주간**을 세우고 라벨도 주간이다(값만 집으면 옆 줄의 5시간과 같은 창으로 읽힌다).
        let weeklyOnly = try surfaces(fiveHour: nil)
        #expect(weeklyOnly.phone.window == .weekly)
        #expect(weeklyOnly.widget.display == weeklyOnly.phone, "폰과 위젯이 다른 창을 대표로 세운다")
        #expect(weeklyOnly.widget.label == AILimitWindow.weekly.displayName)
        #expect(weeklyOnly.phone.valueText == "42%" && weeklyOnly.phone.valueText != AILimitFreshnessRule.unknownValueText)
        // ② 기준선: 두 창이 다 있으면 둘 다 **5시간**을 세운다(선택 규칙이 '주간 고정'으로 굳지 않았다).
        let both = try surfaces(fiveHour: 27)
        #expect(both.phone.window == .fiveHour && both.widget.display == both.phone)
        #expect(both.widget.label == AILimitWindow.fiveHour.displayName)
    }

    /// ★ **폰 머리 줄도 대표 창을 세운다**(v0.3.45 P2 — 세 화면이 다른 말을 하던 자리).
    ///
    /// 폰 카드는 `row.fiveHour == nil` 이면 `headLine(nil)` 을 불러 **값과 캡션을 둘 다 건너뛰었다**.
    /// 같은 데이터로 맥(`AILimitCardModel.head`)은 `42% · 주간`, 위젯(`primaryWindow`)도 `42% · 주간` 을
    /// 세우는데 **폰만 머리 숫자가 없었다**(재검증자 실측: `mac 42%/주간 · widget 42%/주간 · phone 숫자 없음`).
    ///
    /// ★ 그 분기는 뷰 안(`#if os(iOS)`)에 있어서 맥 스위트가 한 줄도 재지 못했다. 그래서 고르기를 **뷰 밖**
    /// (`AILimitDisplayRow.primaryWindow`)으로 끌어내고, 여기서 ① 규칙 자체와 ② 뷰가 그 규칙에 물렸는지를 함께 잰다.
    @Test("폰 머리 줄: 대표 창을 세운다(주간만 오는 계정도) · 라벨이 값과 한 묶음 · 대표를 두 번 안 그린다")
    func phoneHeadLineStandsUpTheRepresentativeWindow() throws {
        let base = MobileClock.demoInstant
        func row(fiveHour: Double?) throws -> AILimitDisplayRow {
            let rows = [AILimitFetchedRow(provider: "antigravity", fiveHourPercent: fiveHour,
                                          fiveHourResetsAt: fiveHour == nil ? nil : base.addingTimeInterval(9_000),
                                          weeklyPercent: 42, weeklyResetsAt: base.addingTimeInterval(86_400),
                                          planLabel: nil, observedAt: base)]
            let snapshot = try #require(AILimitsStore.bundle(from: rows, now: base).provider(.antigravity))
            func display(_ window: AILimitWindow) -> AILimitDisplay? {
                guard snapshot.window(window) != nil else { return nil }
                let value = AILimitFreshnessRule.display(provider: snapshot, window: window, now: base)
                return value.isVisible ? value : nil
            }
            return AILimitDisplayRow(provider: .antigravity, planLabel: nil,
                                     fiveHour: display(.fiveHour), weekly: display(.weekly))
        }

        // ① 주간만 오는 계정: 머리에 **주간 42%** 가 선다(값도 라벨도 있다).
        let weeklyOnly = try row(fiveHour: nil)
        let primary = try #require(weeklyOnly.primaryWindow, "5시간 창이 없으면 머리 줄이 통째로 사라진다")
        #expect(primary.display.window == .weekly)
        #expect(primary.display.valueText == "42%")
        #expect(primary.label == AILimitWindow.weekly.displayName,
                "주간 값에 '\(primary.label)' 라벨이 붙었다 — 위 줄의 5시간과 같은 창으로 읽힌다")
        #expect(weeklyOnly.secondaryWeekly == nil, "대표로 이미 선 주간을 아래에 한 번 더 그린다")
        // 위젯이 같은 데이터로 **같은 창·같은 라벨**을 세운다(두 화면이 한 규칙이다).
        let widget = try #require(AingWidgetLimitRow(provider: .antigravity, fiveHour: weeklyOnly.fiveHour,
                                                     weekly: weeklyOnly.weekly).primaryWindow)
        #expect(widget.display == primary.display && widget.label == primary.label)

        // ② 기준선: 두 창이 다 있으면 머리는 **5시간**이고 주간은 아래 얇은 줄로 내려간다(고정이 아니다).
        let both = try row(fiveHour: 27)
        let bothPrimary = try #require(both.primaryWindow)
        #expect(bothPrimary.display.window == .fiveHour && bothPrimary.display.valueText == "27%")
        #expect(bothPrimary.label == AILimitWindow.fiveHour.displayName)
        #expect(both.secondaryWeekly?.valueText == "42%", "두 창이 다 있으면 주간이 따로 한 줄 더 선다")

        // ③ 창이 하나도 안 보이면 머리 줄을 만들지 않는다(0% 로 지어내지 않는다).
        let none = AILimitDisplayRow(provider: .claude, planLabel: nil, fiveHour: nil, weekly: nil)
        #expect(none.primaryWindow == nil && none.secondaryWeekly == nil)

        // ★ 뷰가 그 규칙에 **물렸는가**(소스 계약 — 이 뷰는 `#if os(iOS)` 라 값으로는 잴 수 없다).
        let card = try IntegrationContractTests.code("Sources/CheckMobileKit/Me/MeAILimitsCard.swift")
        #expect(card.contains("row.primaryWindow"), "카드가 대표 창 규칙을 쓰지 않는다")
        #expect(card.contains("row.secondaryWeekly"), "주간 줄이 대표 여부를 보지 않는다 — 같은 값을 두 번 그린다")
        #expect(!card.contains("row.fiveHour"), "카드가 5시간 창을 무조건 머리로 쓴다(주간만 오는 계정에서 숫자가 사라진다)")
        #expect(!card.contains("headLine(nil)"), "값·캡션을 둘 다 건너뛰는 갈래가 남았다")
        #expect(card.contains("primary.label"), "머리 줄에 창 라벨이 없다")
    }

    @Test("토큰 축: 오늘 칸은 잔디의 마지막 날 · 수집을 끄면 둘 다 nil(0 으로 지어내지 않는다)")
    func tokenTotals() async throws {
        let harness = await RankMeHarness(label: "me-ailimits-tokens") { Self.responder($0) }
        defer { harness.tearDown() }
        let store = harness.me
        store.tabDidAppear()
        #expect(await baseWaitUntil { store.recordsState.hasLoaded && store.aiLimits.state.hasLoaded })

        #expect(store.showsTokenGrid, "전제: 수집을 켠 계정이다")
        let totals = store.aiLimits.phoneTokenTotals()
        #expect(totals.recent == store.tokenGrid.totalTokens)
        // 픽스처의 토큰은 9/16(어제) 것뿐이다 — 오늘(9/17) 칸은 0 이어야 한다("모른다"가 아니라 진짜 0).
        #expect(totals.today == 0)
        #expect(AILimitsStore.todayTokens(.empty) == nil, "빈 격자에서 오늘 값을 지어냈다")

        store.showsTokenGrid = false
        let off = store.aiLimits.phoneTokenTotals()
        #expect(off.today == nil && off.recent == nil, "수집을 끈 사람에게 토큰 줄을 그린다")
        #expect(store.aiLimits.widgetPanel()?.todayTokens == nil)
    }

    @Test("플랜 라벨: 32자가 넘으면 버린다(서버 CHECK 와 **같은 함수**로 — 리더가 통과시킨 라벨이 업로드에서 조용히 거절되지 않게)")
    func planLabelContract() {
        #expect(AILimitPlanLabelContract.normalized("  max  ") == "max")
        #expect(AILimitPlanLabelContract.normalized("") == nil)
        #expect(AILimitPlanLabelContract.normalized(String(repeating: "가", count: 33)) == nil)
        #expect(AILimitPlanLabelContract.normalized(String(repeating: "가", count: 32)) != nil)
    }

    // MARK: - 소스 계약(주석을 걷어내고 본다)

    @Test("카드: 값은 코어 규칙에서만 온다 · 막대는 ProgressBar · 로고 타일 **옆에 이름 글자** · 출처 문구 없음 · 토큰은 다른 블록")
    func cardContract() throws {
        let card = try IntegrationContractTests.code("Sources/CheckMobileKit/Me/MeAILimitsCard.swift")
        #expect(card.contains("limits.displayRows"), "카드가 규칙이 만든 줄을 안 쓴다")
        #expect(card.contains("AIProviderTile(provider:"), "로고 타일이 없다")
        #expect(card.contains("row.provider.displayName"), "타일 옆 이름 글자가 없다 — 색으로만 제공자를 가른다")
        #expect(card.contains("ProgressBar(") && !card.contains("trim(from:"), "링 게이지로 돌아갔다")
        #expect(card.contains("thin: true"), "주간 얇은 줄이 없다(5시간만 그린다)")
        #expect(card.components(separatedBy: "ViewThatFits(in: .horizontal)").count >= 2, "큰 글자에서 조각을 빼는 갈래가 없다")
        // 퍼센트·나이를 뷰가 다시 만들면 규칙이 둘이 된다.
        #expect(!card.contains("rounded()") && !card.contains("timeIntervalSince"), "뷰가 숫자·나이를 다시 계산한다")
        #expect(!card.contains("이상"), "뷰가 하한 접미사를 직접 붙인다(규칙의 valueText 를 써야 한다)")
        // 출처(폰 직접/서버 경유)는 사용자 문구가 아니다.
        for banned in ["서버에서", "맥에서 읽", "AILimitSource", ".server", ".local"] {
            #expect(!card.contains(banned), "카드가 값의 출처를 말한다(\(banned))")
        }
        // 위젯 스냅샷 쓰기는 지금 탭 하나 — 나 탭 폴더에 한 줄도 없다.
        let writers = try IntegrationContractTests.files(
            containing: ["widgetSnapshots.update", "WidgetSnapshotCodec.write("],
            under: "Sources/CheckMobileKit/Me"
        )
        #expect(writers.isEmpty, "나 탭이 위젯 스냅샷을 직접 쓴다: \(writers)")
        // 폰은 제공자 API 를 직접 부르지 않는다(자격증명을 읽지 않는다 — 사용자 계정이 위험해진다).
        let direct = try IntegrationContractTests.files(
            containing: ["api.anthropic.com", "chatgpt.com", "cloudcode-pa.googleapis.com", "find-generic-password", "Claude Code-credentials"],
            under: "Sources/CheckMobileKit"
        )
        #expect(direct.isEmpty, "폰이 제공자·키체인을 직접 읽는다: \(direct)")
        let widgetDirect = try IntegrationContractTests.files(
            containing: ["api.anthropic.com", "chatgpt.com", "cloudcode-pa.googleapis.com"],
            under: "Sources/CheckWidgetsKit"
        )
        #expect(widgetDirect.isEmpty, "위젯이 제공자를 직접 부른다: \(widgetDirect)")
    }

    /// ★ 공개 문서의 라이선스 문장이 **코드와 같은 말**을 한다(v0.3.45 P2).
    ///
    /// `docs/ai-limits.md` 는 `docs/_config.yml` 로 GitHub Pages 에 그대로 나간다. 초안에는 "재배포 조건이
    /// MIT 이므로 출처 표기를 **지운다**"로 적혀 있었다 — MIT 는 반대로 저작권·라이선스 표기를 **유지**할 것을
    /// 요구하므로 그 지시를 따르면 위반이다. 코드는 올바로 출처를 달아 뒀고(로고 파일 머리말) 공개 문서만
    /// 반대를 말했다. 문서는 테스트가 없으면 아무도 되묻지 않으므로 여기서 묶는다.
    @Test("공개 문서: MIT 는 출처 표기를 **유지**한다(문서와 코드가 같은 말을 한다)")
    func publicDocKeepsTheAttributionRule() throws {
        let doc = try String(
            contentsOf: IntegrationContractTests.root.appendingPathComponent("docs/ai-limits.md"), encoding: .utf8
        )
        #expect(doc.contains("CodexBar") && doc.contains("MIT"), "전제: 문서가 로고 출처와 라이선스를 말한다")
        #expect(!doc.contains("출처 표기를 지운다"),
                "공개 문서가 MIT 표기를 지우라고 말한다 — 그대로 하면 라이선스 위반이다")
        #expect(doc.contains("유지") && doc.contains("남긴다"), "표기를 남긴다는 말이 없다")
        // 코드에는 출처 한 줄이 **실제로** 남아 있다(문서가 가리키는 그 자리 — 주석이라 `code(_:)` 로는 못 본다).
        let logo = try String(
            contentsOf: IntegrationContractTests.root
                .appendingPathComponent("Sources/CheckCore/AIProviderLogo.swift"), encoding: .utf8
        )
        #expect(logo.contains("CodexBar") && logo.contains("MIT License"),
                "로고 파일에서 출처 표기가 사라졌다 — 문서가 가리키는 근거가 없어졌다")
    }
}
