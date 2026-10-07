import AppKit
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

    /// ★ **창마다 자기 칸이다** — v0.3.46 승인 문법에는 '대표 창 고르기'가 **아예 없다**.
    ///
    /// v0.3.45 는 줄마다 대표 창 하나를 크게 세웠다. 그래서 "어느 창을 머리로 세우나"라는 선택이 필요했고,
    /// 그 선택이 틀리면 5시간 창이 없는 계정에서 폰은 숫자를 통째로 건너뛰고(초안) 맥은 `—` 를 그리고
    /// 위젯은 주간을 올렸다 — 같은 데이터로 세 화면이 다른 말을 했다. 한 줄 안에 두 열을 **나란히** 세우는
    /// 새 문법에서는 창마다 칸이 있고, 없는 창은 `없음` 으로 빈다. 고를 것이 없으면 틀릴 수도 없다.
    ///
    /// 여기서 재는 것: **폰과 위젯이 같은 데이터로 같은 두 칸을 만드는가**(맥 쪽 그물은 모듈이 달라
    /// `AILimitsMacTests` 에 있다).
    @Test("칸 구성: 폰과 위젯이 창마다 같은 칸을 만든다 · 없는 창은 둘 다 비고 `없음` 글자를 쓴다")
    func everyWindowGetsItsOwnCellOnPhoneAndWidget() throws {
        let base = MobileClock.demoInstant
        func surfaces(fiveHour: Double?) throws -> (phone: AILimitDisplayRow, widget: AingWidgetLimitRow) {
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
            return (AILimitDisplayRow(provider: .antigravity, planLabel: nil,
                                      fiveHour: display(.fiveHour), weekly: display(.weekly)),
                    AingWidgetLimitRow(provider: .antigravity,
                                       fiveHour: display(.fiveHour), weekly: display(.weekly)))
        }
        // ① 주간만 오는 계정(안티그래비티 실측): 5시간 칸은 **둘 다 비고**, 주간 칸은 둘 다 42% 다.
        let weeklyOnly = try surfaces(fiveHour: nil)
        #expect(weeklyOnly.phone.display(.fiveHour) == nil && weeklyOnly.widget.display(.fiveHour) == nil,
                "없는 창을 지어냈다 — 그 칸은 `없음` 으로 비어야 한다")
        let phoneWeekly = try #require(weeklyOnly.phone.display(.weekly))
        #expect(phoneWeekly.valueText == "42%")
        #expect(weeklyOnly.widget.display(.weekly) == phoneWeekly, "폰과 위젯이 같은 칸에 다른 값을 넣는다")
        #expect(weeklyOnly.phone.hasAnyWindow && weeklyOnly.widget.hasAnyWindow)
        // 비는 칸의 글자는 `—`(판정 불가)가 **아니다** — 두 사실을 같은 글자로 말하지 않는다.
        #expect(AILimitColumnText.absentValueText != AILimitFreshnessRule.unknownValueText)
        // ② 기준선: 두 창이 다 있으면 두 칸이 **다 찬다**(기준선이 같은 입력이면 이 테스트는 영원히 초록이다).
        let both = try surfaces(fiveHour: 27)
        #expect(both.phone.display(.fiveHour)?.valueText == "27%" && both.phone.display(.weekly)?.valueText == "42%")
        #expect(both.widget.display(.fiveHour) == both.phone.display(.fiveHour))
        #expect(both.widget.display(.weekly) == both.phone.display(.weekly))
        // ③ 창이 하나도 안 보이면 두 칸을 `없음 · 없음` 으로 세우지 않는다(그 줄은 아예 서지 않는다).
        let none = AILimitDisplayRow(provider: .claude, planLabel: nil, fiveHour: nil, weekly: nil)
        #expect(!none.hasAnyWindow && none.display(.fiveHour) == nil && none.display(.weekly) == nil)
        #expect(!AingWidgetLimitRow(provider: .claude, fiveHour: nil, weekly: nil).hasAnyWindow)
        // ④ 창이 **둘뿐**이라는 전제: 셋이 되는 날 공유 팔레트의 열거값이 함께 늘어야 한다(안 늘면 새 창이
        //    조용히 5시간 열 색으로 떨어진다).
        #expect(AILimitWindow.allCases.count == AILimitColumnWindow.allCases.count,
                "창이 늘었는데 열 팔레트는 둘뿐이다 — 새 창이 5시간 열 색을 입는다")
        for window in AILimitWindow.allCases {
            #expect(AILimitColumnPalette.column(windowRawValue: window.rawValue).rawValue == window.rawValue,
                    "\(window.rawValue) 가 열로 옮겨지지 않는다(파랑·보라가 뒤집힐 자리다)")
        }
    }

    /// ★ **가로 예산이 가장 좁은 기기에서도 말줄임을 만들지 않는가** (v0.3.46).
    ///
    /// 숫자 칸은 `lineLimit(1)` 이라 넘쳐도 **높이가 변하지 않는다** = 렌더 높이로는 안 잡히고, 넘친 순간의
    /// 증상은 말줄임이다. 그리고 이 자리에서 말줄임은 **숫자 자릿수 오독**이다("100% 이상" → "100% 이…").
    /// 뷰는 `#if os(iOS)` 라 맥 스위트가 한 줄도 컴파일하지 않으므로 예산을 뷰 밖(`MeAILimitCardBudget`)에
    /// 두고 **여기서 글자를 다시 재서** 되묻는다(글자수로 재면 안 된다 — 한글 13pt · 라틴 7pt · 숫자 7.3pt).
    @Test("폰 가로 예산: 숫자·이름·열 머리가 칸에 들어간다 · 가장 좁은 기기(375pt)에서도 바가 남는다")
    func columnGridFitsEvenTheNarrowestPhone() throws {
        let budget = MeAILimitCardBudget.self
        // ① 실측 상수가 **지금 이 맥에서도** 같은 값인가(글꼴이 바뀌면 여기서 빨개진다).
        #expect(abs(measuredWidth("100% 이상", size: budget.valueFontSize, weight: .bold, monospacedDigits: true)
                    - budget.worstValueWidth) < 1.5)
        #expect(abs(measuredWidth("안티그래비티", size: budget.nameFontSize, weight: .semibold) - budget.worstNameWidth) < 1.5)
        #expect(abs(measuredWidth("5시간", size: budget.headerFontSize, weight: .semibold) - budget.worstHeaderWidth) < 1.5)
        // ② 가장 넓은 문구가 칸에 들어간다(`없음` · `—` · `0%` 는 그보다 좁다).
        #expect(budget.valueFits(budget.worstValueWidth), "가장 넓은 숫자가 칸을 넘는다 — 자릿수가 잘린다")
        for text in [AILimitColumnText.absentValueText, AILimitFreshnessRule.unknownValueText, "0%", "99% 이상"] {
            let width = measuredWidth(text, size: budget.valueFontSize, weight: .bold, monospacedDigits: true)
            #expect(budget.valueFits(width), "\(text) 가 숫자 칸(\(budget.valueWidth))을 넘는다: \(width)")
        }
        #expect(budget.worstNameWidth <= budget.nameTextWidth,
                "가장 긴 제공자 이름이 108pt 칸의 글자 자리(\(budget.nameTextWidth))를 넘는다")
        for window in AILimitWindow.allCases {
            let width = measuredWidth(window.displayName, size: budget.headerFontSize, weight: .semibold)
            #expect(width <= budget.valueWidth, "열 머리 '\(window.displayName)' 가 숫자 칸보다 넓다")
        }
        // ③ 기기 폭 → 바 폭. 기준 기기(393)와 **가장 좁은 기기(375)** 둘 다 바가 보일 만큼 남는다.
        for screen in [budget.narrowestScreenWidth, budget.referenceScreenWidth, 440] as [CGFloat] {
            let inner = budget.innerWidth(screenWidth: screen)
            let bar = budget.barWidth(innerWidth: inner)
            #expect(bar >= budget.minimumBarWidth, "\(screen)pt 기기에서 바가 \(bar)pt 다 — 8% 와 0% 가 안 갈린다")
            // ★ 열 머리의 오른쪽 끝이 자기 열 숫자 칸의 오른쪽 끝과 맞는다 — **항등식**으로 잰다
            //   (두 칸이 남는 폭을 똑같이 나눠 가지므로 측정 상수가 필요 없다).
            #expect(abs(budget.cellWidth(innerWidth: inner) - (bar + budget.barValueGap + budget.valueWidth)) < 0.001)
            #expect(abs(budget.nameColumnWidth + budget.nameGap + budget.columnGap
                        + budget.cellWidth(innerWidth: inner) * 2 - inner) < 0.001,
                    "한 줄의 가로 합이 카드 안쪽 폭과 다르다 — 어딘가 넘치거나 남는다")
        }
        // ④ 기준 기기의 숫자를 못 박는다(승인본의 108pt 칸이 줄어들면 여기서 빨개진다).
        #expect(budget.innerWidth(screenWidth: budget.referenceScreenWidth) == 329)
        #expect(budget.nameColumnWidth == 108 && budget.markSide == 26)
    }

    /// ★ **채움 폭 산식은 세 화면이 한 벌**이다. 0% 는 0pt(채움 없음), 0 보다 크면 **보이는 길이**를 갖는다.
    ///
    /// 왜 비례 최소값인가: 맥 팝오버의 바는 69pt 고 폰 카드의 바는 32pt 다(이름 칸을 두느라 좁다).
    /// 최소 채움을 고정 pt 로 두면 좁은 바에서 1% 와 18% 가 같은 길이가 된다 — 바가 거짓말을 한다.
    @Test("채움 폭: 0% 는 0pt · 1% 도 보인다 · 100% 는 꽉 · 판정 불가는 채움 없음(좁은 바와 넓은 바 둘 다)")
    func barFillWidthIsOneFormula() {
        for bar in [26.0, 32, 44, 69] {
            #expect(AILimitBarFill.width(barWidth: bar, percent: 0) == 0, "0% 가 길이를 가졌다 — '안 썼다'가 아니라 '조금 썼다'로 보인다")
            #expect(AILimitBarFill.width(barWidth: bar, percent: nil) == 0, "판정 불가를 0% 로 그렸다")
            #expect(AILimitBarFill.width(barWidth: bar, percent: 1) >= 2, "1% 가 안 보인다")
            #expect(AILimitBarFill.width(barWidth: bar, percent: 1) < AILimitBarFill.width(barWidth: bar, percent: 50))
            #expect(AILimitBarFill.width(barWidth: bar, percent: 100) == bar)
            #expect(AILimitBarFill.width(barWidth: bar, percent: 140) == bar, "100 을 넘는 값이 바를 넘겼다")
            #expect(AILimitBarFill.width(barWidth: bar, percent: -5) == 0)
            // 최소 채움은 **바 폭에 비례**한다(좁은 바에서 1% 와 18% 가 같은 길이가 되지 않게).
            #expect(AILimitBarFill.minimumFill(barWidth: bar) < bar * 0.2)
        }
        #expect(AILimitBarFill.minimumFill(barWidth: 69) > AILimitBarFill.minimumFill(barWidth: 26))
        #expect(AILimitBarFill.width(barWidth: 0, percent: 50) == 0, "폭 0 에서 음수·NaN 이 나오면 레이아웃이 깨진다")
    }

    /// ★ **사용량 단계는 글자가 쓰는 수로 가른다**(맥이 2026-10-07 에 밟은 결함).
    ///
    /// 초안은 클램프도 안 된 날것 double 로 90 을 갈랐다. 89.5% 는 규칙이 `90%` 라고 **적는데**
    /// (`wholePercent` 가 반올림한다) 색은 평온했다 — 같은 자리에서 글자와 색이 다른 단계를 말한 것이다.
    @Test("사용량 단계: 89.5% 는 글자가 `90%` 라 색도 위험이다 · 경계 양쪽 · 모르는 값엔 경고를 붙이지 않는다")
    func usageStageAgreesWithTheGlyph() {
        func stage(_ percent: Double?) -> AILimitUsageStage {
            AILimitUsageStage.stage(wholePercent: percent.map(AILimitFreshnessRule.wholePercent))
        }
        #expect(stage(nil) == .calm, "모르는 값에 경고를 붙였다")
        #expect(stage(0) == .calm && stage(69) == .calm)
        #expect(stage(69.5) == .warn, "글자는 `70%` 인데 색은 평온하다")
        #expect(stage(70) == .warn && stage(89) == .warn)
        #expect(stage(89.5) == .danger, "글자는 `90%` 인데 색은 주의다 — 같은 자리가 두 말을 한다")
        #expect(stage(90) == .danger && stage(100) == .danger)
        #expect(stage(.nan) == .calm && stage(.infinity) == .calm, "NaN·무한은 0 으로 접힌다(코어 규칙) — 경고를 붙이지 않는다")
        // 경계는 맥과 **같은 수**여야 한다(맥은 이 모듈을 링크하지 않는다 — 소스로 대조한다).
        let mac = try? IntegrationContractTests.code("Sources/check/CheckAILimitsRow.swift")
        if let mac {
            #expect(mac.contains("warnPercent = \(AILimitUsageStage.warnPercent)")
                    && mac.contains("dangerPercent = \(AILimitUsageStage.dangerPercent)"),
                    "맥의 사용량 경계가 폰·위젯과 갈렸다")
        }
    }

    /// ★ **두 열의 색 숫자는 한 표**다 — 폰·위젯은 같은 상수를 보고, 맥은 같은 16진수를 따로 적는다.
    ///
    /// 맥 앱 타깃은 `CheckMobileShared` 를 링크하지 않는다(Package.swift — 셋이 다 보는 모듈은 `CheckCore`
    /// 뿐이다). 그래서 승인본 16진수가 갈리지 않는지는 **소스로** 되묻는다. 한쪽만 고치는 날 여기서 빨개진다.
    @Test("열 팔레트: 승인본 16진수가 맥 코드에도 그대로 있다 · 대비와 위계가 지켜진다")
    func columnPaletteIsOneTableAcrossSurfaces() throws {
        // ① 승인본(어두운 쪽) 16진수가 맥 팔레트에도 **그대로** 있다(밑줄은 걷어내고 본다).
        let mac = try IntegrationContractTests.code("Sources/check/CheckAILimitsRow.swift")
            .replacingOccurrences(of: "_", with: "")
        let approved: [(String, UInt32)] = [
            ("5시간 바", AILimitColumnPalette.fiveHourBar.dark),
            ("5시간 열 머리", AILimitColumnPalette.fiveHourHeader.dark),
            ("주간 바", AILimitColumnPalette.weeklyBar.dark),
            ("주간 열 머리", AILimitColumnPalette.weeklyHeader.dark),
            ("빈 트랙", AILimitColumnPalette.emptyTrack.dark),
            ("없는 칸 트랙", AILimitColumnPalette.absentTrack.dark),
            ("구분선", AILimitColumnPalette.separator.dark),
            ("없는 칸 글자", AILimitColumnPalette.absentText.dark),
        ]
        for (name, hex) in approved {
            let needle = "0x" + String(format: "%06X", hex)
            #expect(mac.contains(needle), "\(name) \(needle) 이 맥 팔레트에 없다 — 세 화면이 다른 색으로 그린다")
        }
        // ② `없음` 글자도 맥과 같은 글자다(두 벌로 적으면 한쪽만 고쳐지는 날 화면이 갈린다).
        #expect(mac.contains("\"\(AILimitColumnText.absentValueText)\""), "맥의 `없음` 글자가 갈렸다")

        // ③ 대비: 열 머리 글자는 라이트·다크 둘 다 **4.5:1 이상**, 바는 그래픽이라 3:1 이상.
        func rgb(_ hex: UInt32) -> MobileThemePalette.RGB { MobileThemePalette.RGB(hex: hex) }
        let backdrops = (light: rgb(0xFFFFFF), dark: rgb(0x2B2E3D))     // 폰 카드 바탕(`surface`)
        for window in AILimitWindow.allCases {
            let column = AILimitColumnPalette.column(windowRawValue: window.rawValue)
            let header = AILimitColumnPalette.header(column), bar = AILimitColumnPalette.bar(column)
            #expect(rgb(header.light).contrast(against: backdrops.light) >= 4.5,
                    "\(window.rawValue) 라이트 열 머리 대비 \(rgb(header.light).contrast(against: backdrops.light))")
            #expect(rgb(header.dark).contrast(against: backdrops.dark) >= 4.5,
                    "\(window.rawValue) 다크 열 머리 대비 \(rgb(header.dark).contrast(against: backdrops.dark))")
            #expect(rgb(bar.light).contrast(against: backdrops.light) >= 3)
            #expect(rgb(bar.dark).contrast(against: backdrops.dark) >= 3)
            // 머리 글자와 바는 **같은 계열에서 명도만 다르다**(머리와 바의 색을 따로 고르면 짝이 안 보인다).
            #expect(header.light != bar.light && header.dark != bar.dark)
        }
        // ④ 두 열은 **서로 다른 색**이다(같으면 색 단서가 사라진다).
        #expect(AILimitColumnPalette.fiveHourBar != AILimitColumnPalette.weeklyBar)
        #expect(AILimitColumnPalette.fiveHourHeader != AILimitColumnPalette.weeklyHeader)
        // ⑤ 위계 ⓐ: 두 트랙은 **서로 다르다** — 창이 없다는 사실의 단서가 `없음` 글자 하나로 줄지 않게.
        #expect(AILimitColumnPalette.absentTrack != AILimitColumnPalette.emptyTrack,
                "없는 칸과 빈 칸의 트랙이 같다 — 글자 하나만 남는다")
        // ⓑ 트랙은 어느 바보다도 **조용하다**(트랙이 채움으로 읽히면 0% 가 '꽤 썼다'로 보인다).
        for window in AILimitWindow.allCases {
            let bar = AILimitColumnPalette.bar(AILimitColumnPalette.column(windowRawValue: window.rawValue))
            for (track, name) in [(AILimitColumnPalette.emptyTrack, "빈 트랙"),
                                  (AILimitColumnPalette.absentTrack, "없는 칸 트랙")] {
                #expect(rgb(track.light).contrast(against: backdrops.light)
                        < rgb(bar.light).contrast(against: backdrops.light), "\(name)(라이트)이 바만큼 눈에 띈다")
                #expect(rgb(track.dark).contrast(against: backdrops.dark)
                        < rgb(bar.dark).contrast(against: backdrops.dark), "\(name)(다크)이 바만큼 눈에 띈다")
            }
        }
        // ⓒ 승인본이 전제한 바탕(위젯 바탕 = 어두운 한 벌)에서는 없는 칸 트랙이 빈 트랙보다 **바탕에 가깝다**
        //    = 더 조용하다. 폰 카드 바탕(`surface`)은 그보다 한 단 밝아 같은 값이 '조금 어두운 홈'으로 보이는데,
        //    그래도 **채움으로는 읽히지 않는다**(ⓑ) — 세 화면이 한 표를 쓰는 값이 더 중요하다.
        let widgetBackdrops = (light: rgb(AingWidgetPalette.background.light), dark: rgb(AingWidgetPalette.background.dark))
        #expect(rgb(AILimitColumnPalette.absentTrack.dark).contrast(against: widgetBackdrops.dark)
                < rgb(AILimitColumnPalette.emptyTrack.dark).contrast(against: widgetBackdrops.dark))
        #expect(rgb(AILimitColumnPalette.absentTrack.light).contrast(against: widgetBackdrops.light)
                < rgb(AILimitColumnPalette.emptyTrack.light).contrast(against: widgetBackdrops.light))
        for (ink, backdrop) in [(AILimitColumnPalette.absentText.light, backdrops.light),
                                (AILimitColumnPalette.absentText.dark, backdrops.dark)] {
            let ratio = rgb(ink).contrast(against: backdrop)
            #expect(ratio >= 2, "`없음` 글자가 \(ratio):1 로 사라졌다")
            #expect(ratio < 4.5, "`없음` 글자가 숫자만큼 커졌다 — 값이 아니라 '값이 없다는 사실'이다")
        }
    }

    /// 글자 폭 실측(맥 글꼴로 — SF Pro 글리프 폭은 iOS 와 같은 글꼴에서 같다. 다른 것은 텍스트 스타일이
    /// 어느 pt 로 풀리는지뿐이고, 그 pt 를 `MeAILimitCardBudget` 이 상수로 들고 있다).
    nonisolated static func width(_ text: String, size: CGFloat, weight: NSFont.Weight, monospacedDigits: Bool) -> CGFloat {
        var font = NSFont.systemFont(ofSize: size, weight: weight)
        if monospacedDigits {
            let descriptor = font.fontDescriptor.addingAttributes([
                .featureSettings: [[NSFontDescriptor.FeatureKey.typeIdentifier: kNumberSpacingType,
                                    NSFontDescriptor.FeatureKey.selectorIdentifier: kMonospacedNumbersSelector]],
            ])
            font = NSFont(descriptor: descriptor, size: size) ?? font
        }
        return (text as NSString).size(withAttributes: [.font: font]).width
    }

    private func measuredWidth(_ text: String, size: CGFloat, weight: NSFont.Weight,
                               monospacedDigits: Bool = false) -> CGFloat {
        Self.width(text, size: size, weight: weight, monospacedDigits: monospacedDigits)
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

    @Test("카드: 값은 코어 규칙에서만 온다 · 한 줄에 두 칸 · 열 머리는 맨 위 한 번 · 이름+요금제 · 출처 문구 없음")
    func cardContract() throws {
        let card = try IntegrationContractTests.code("Sources/CheckMobileKit/Me/MeAILimitsCard.swift")
        #expect(card.contains("limits.displayRows"), "카드가 규칙이 만든 줄을 안 쓴다")
        #expect(card.contains("AIProviderTile(provider:"), "로고 타일이 없다")
        #expect(card.contains("row.provider.displayName"), "타일 옆 이름 글자가 없다 — 색으로만 제공자를 가른다")
        #expect(card.contains("row.planLabel"), "요금제를 안 쓴다 — 폰 카드는 이름과 요금제를 **둘 다** 쓴다(승인된 문법)")
        #expect(card.contains("MeAILimitBar(") && !card.contains("trim(from:"), "링 게이지로 돌아갔다")
        // ★ 창을 직접 집지 않는다 — 칸은 `row.display(window)` 하나로만 꺼낸다(대표 창 고르기가 없다).
        #expect(card.contains("row.display("), "카드가 창별 칸 규칙을 쓰지 않는다")
        #expect(!card.contains("row.fiveHour") && !card.contains("row.weekly"),
                "카드가 창을 직접 집는다 — 그 자리에서 '어느 창을 세우나' 선택이 되살아난다")
        #expect(!card.contains("primaryWindow") && !card.contains("secondaryWeekly"),
                "대표 창 고르기가 돌아왔다(새 문법에는 그 선택이 없다)")
        // ★ 창이 **없는** 칸의 글자는 공유 규칙에서 온다(`—` 와 다른 말이어야 한다).
        #expect(card.contains("AILimitColumnText.absentValueText"), "없는 칸의 글자를 공유 규칙에서 안 가져온다")
        #expect(!card.contains("\"없음\""), "뷰가 `없음` 글자를 또 적었다 — 맥·위젯과 갈릴 자리다")
        #expect(!card.contains("unknownValueText"), "뷰가 '판정 불가' 글자를 없는 칸에 쓴다(고장으로 읽힌다)")
        // 열 색·구분선 숫자는 공유 팔레트 하나에서 온다(위젯과 같은 값).
        #expect(card.contains("AILimitColumnPalette"), "열 색을 뷰가 따로 적었다")
        #expect(card.contains("AILimitUsageStage"), "사용량 단계(70·90%)를 뷰가 따로 갈랐다")
        // 가로 숫자는 전부 예산 타입에서 — 뷰에 박으면 맥 스위트가 한 줄도 재지 못한다.
        #expect(card.contains("MeAILimitCardBudget.nameColumnWidth") && card.contains("MeAILimitCardBudget.valueWidth"))
        // 퍼센트·나이를 뷰가 다시 만들면 규칙이 둘이 된다.
        #expect(!card.contains("rounded()") && !card.contains("timeIntervalSince"), "뷰가 숫자·나이를 다시 계산한다")
        #expect(!card.contains("이상"), "뷰가 하한 접미사를 직접 붙인다(규칙의 valueText 를 써야 한다)")
        // ★ **구간을 잘라서 잰다.** "파일 어디든 한 번 나오면 된다"로 재면 커버리지 구멍이다 — 격자에서 칸을
        //   통째로 지워도 쌓은 모양 쪽이 남아 초록이었을 자리다(관례: 뮤테이션 M7).
        let grid = try #require(card.range(of: "private var grid:"))
        let nameColumn = try #require(card.range(of: "private var nameColumn:"))
        let gridBody = card[grid.lowerBound..<nameColumn.lowerBound]
        #expect(gridBody.contains("cell(.fiveHour)") && gridBody.contains("cell(.weekly)"),
                "격자에 두 칸이 나란히 서지 않는다 — 세로로 쌓은 옛 문법이다")
        let stacked = try #require(card.range(of: "private var stacked:"))
        #expect(card[stacked.lowerBound...].contains("AILimitWindow.allCases"),
                "AX 크기에서 창 하나가 빠진다(쌓은 모양에서도 정보는 다 있어야 한다)")
        // 열 머리는 **카드에 한 번만** 선다(줄마다 반복하지 않는다 — 승인된 문법 ②).
        #expect(card.components(separatedBy: "columnHeaderRow").count - 1 == 2, "열 머리 줄이 한 자리가 아니다")
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
