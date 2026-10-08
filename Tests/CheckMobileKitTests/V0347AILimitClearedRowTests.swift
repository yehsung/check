import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit
@testable import CheckWidgetsKit

/// v0.3.47 — **설정에서 끈 제공자가 폰·위젯에서 사라진다**.
///
/// ## 무엇이 서버에서 오는가
/// 맥 설정에 보기 스위치가 생겼다(제공자별 + 마스터). 끄면 맥은 그 제공자의 행을 **지우지 못한다** —
/// `authenticated` 에 DELETE 를 일부러 주지 않았다. 대신 창 값·리셋·플랜을 **전부 null 로 덮은 행**을 한 번
/// 올린다(`SupabaseWorkServiceAILimits.aiLimitClearingRow`). 폰·위젯이 할 일은 그 행을 **즉시 숨기는 것**이다.
///
/// ## 이 스위트가 재는 것 (셋)
/// ① 숨김 판정이 **'보이는 창이 0개인가'** 하나인가 — 두 표면이 같은 술어(`AILimitProviderSnapshot.isLinked`)를 쓰고,
///    **주간만 오는 안티그래비티**(실측)가 그 판정에 걸리지 않는가. '5시간 창이 있나'로 재면 그 제공자가 함께 사라진다.
/// ② 비워진 행이 **값 행을 되살리지 않는가** — 제공자당 최신 하나를 고르는 자리에서 비우기가 이겨야 한다.
/// ③ 빈 상태 문구가 **두 경우에 다 참인가** — "로그인하면 보여요" 는 설정에서 끈 사람에게 거짓이다(이미 로그인해 있다).
///
/// 3일 유령 게이트(`AILimitGhostRow`)는 **건드리지 않는다** — 이건 그것과 별개의 빠른 길이다(설정을 끈 사람에게
/// 사흘을 기다리게 할 수 없다). 그 게이트가 그대로 살아 있는지도 여기서 되묻는다.
@MainActor
@Suite("비워진 리밋 행(v0.3.47 — 폰·위젯)")
struct V0347AILimitClearedRowTests {
    nonisolated static let now = MobileClock.demoInstant   // 2026-09-17 14:05 KST(목)

    /// 실제 서버 모양 — **맥 한 대**(이 맥에서 Claude 를 껐다). Claude 는 **비워진 행**이고(끈 직후 · 같은 PK 를
    /// 덮었다), 안티그래비티는 **주간만** 온다(5시간 창이 없는 요금제 — 실측).
    ///
    /// ★ 한 기기에 같은 제공자 행이 **둘일 수 없다**(서버 PK = user·device·provider · upsert 가 덮는다).
    ///   그래서 "비우기 vs 옛 값"은 기기가 **둘일 때만** 생기는 일이고, 그 갈래는
    ///   `clearingOnOneMacDoesNotEraseTheOtherMac` 가 따로 잰다.
    nonisolated static let macA = "mac-off-a1"
    nonisolated static let macB = "mac-on-b2"
    nonisolated static let rows = #"""
    [
      {"device_id":"mac-off-a1","device_label":"예성의 MacBook Pro",
       "provider":"claude","five_hour_percent":null,"five_hour_resets_at":null,
       "weekly_percent":null,"weekly_resets_at":null,"plan_label":null,"observed_at":"2026-09-17T05:04:30+00:00"},
      {"device_id":"mac-off-a1","device_label":"예성의 MacBook Pro",
       "provider":"antigravity","five_hour_percent":null,"five_hour_resets_at":null,
       "weekly_percent":8,"weekly_resets_at":"2026-09-23T11:05:00+00:00","plan_label":null,"observed_at":"2026-09-17T05:03:00+00:00"}
    ]
    """#

    nonisolated static func responder(_ request: MobileStubRequest) -> MobileStubResponse? {
        if request.path == "/rest/v1/ai_limits", request.method == "GET" { return .json(rows) }
        if request.path == "/rest/v1/ai_limits_prefs", request.method == "GET" { return .json("[]") }
        return MeStoreTests.rootResponder(request)
    }

    // MARK: - 서버 응답부터 위젯 파일까지

    /// ★ 끝에서 끝까지 한 번. 순수 함수만 재면 **null 퍼센트가 0 으로 디코드되는 결함**을 통째로 놓친다 —
    /// 그 결함의 증상은 "끈 제공자가 `0% · 초기화됨` 으로 영구 표시"(가장 비싼 방향의 거짓)이고, 멤버와이즈로
    /// 만든 행을 쓰는 테스트에서는 영원히 초록이다.
    @Test("시나리오: 맥에서 Claude 를 끄면 비워진 행이 와서 폰 카드·위젯 패널에서 **바로** 사라진다 · 주간만 오는 제공자는 남는다")
    func clearedRowDisappearsFromPhoneCardAndWidgetPanel() async throws {
        let harness = await RankMeHarness(label: "v0347-cleared") { Self.responder($0) }
        defer { harness.tearDown() }
        let store = harness.me

        store.appDidBecomeActive()
        #expect(await baseWaitUntil { store.aiLimits.state.hasLoaded })

        // 폰 카드: Claude 줄이 없다. ★ **옛 값 행(27%)이 되살아나지도 않는다** — 비우기가 최신이다.
        let providers = store.aiLimits.displayRows.map(\.provider)
        #expect(providers == [.antigravity],
                "설정에서 끈 제공자가 카드에 남았다(줄: \(providers)) — 비워진 행을 숨기지 않거나 옛 값 행을 되살렸다")
        let antigravity = try #require(store.aiLimits.displayRows.first)
        #expect(antigravity.fiveHour == nil && antigravity.weekly?.valueText == "8%",
                "주간만 오는 제공자가 비워진 행과 함께 사라졌거나 없는 5시간 창을 지어냈다")
        #expect(store.aiLimits.hasVisibleProviders, "그릴 줄이 있는데 카드를 가리는 깃발이 거짓이다")
        #expect(store.aiLimits.fiveHourSummary == nil, "5시간 창이 없는데 요약 숫자를 지어냈다")

        // 단서 자체는 남아 있다(쓰지 않기로 한 단서다 — 근거는 `AILimitSurfaceText` 머리말).
        let group = try #require(store.aiLimits.groups?.first)
        #expect(group.device.deviceID == Self.macA)
        #expect(group.bundle.provider(.claude)?.isLinked == false, "전제: 비워진 행은 창 0개로 남는다")
        // 맥이 **한 대**뿐이다 → 이름 줄이 서지 않고 위젯 패널에도 이름이 없다(지금과 똑같이 보인다).
        #expect(!store.aiLimits.showsDeviceNames, "맥 한 대인데 기기 이름을 그린다 — 군더더기다")

        // 위젯 패널: 그 줄이 **실리지 않는다**(위젯은 받지 못한 줄을 그릴 수 없다).
        let panel = try #require(store.aiLimits.widgetPanel())
        #expect(panel.providers.map(\.provider) == ["antigravity"],
                "비워진 줄이 위젯 패널까지 갔다 — 다음 타임라인에서 `0% · 초기화됨` 으로 굳는다")
        #expect(panel.providers.first?.fiveHourPercent == nil, "없는 5시간 창을 0 으로 지어내 실었다")
        #expect(panel.deviceName == nil, "맥 한 대인데 위젯 머리에 이름을 적는다")

        // 그 패널로 위젯이 그릴 것: 안티그래비티 한 줄(주간만).
        guard case .limits(let limits) = AingWidgetLimitsState(snapshot: Self.snapshot(panel), at: Self.now) else {
            throw ClearedRowFailure.notLimits
        }
        #expect(limits.rows.map(\.provider) == [.antigravity])
        #expect(limits.rows.first?.display(.fiveHour) == nil && limits.rows.first?.display(.weekly)?.valueText == "8%")

        // 폰은 이 축에서 읽기만 한다(끄기도 맥의 일이다 — 폰이 비우는 행을 올리지 않는다).
        let writes = harness.requests.filter { $0.path == "/rest/v1/ai_limits" && $0.method.uppercased() != "GET" }
        #expect(writes.isEmpty, "폰이 리밋 표에 썼다 — 올리는 쪽은 맥 하나다")
        harness.expectNoForbiddenCalls()
    }

    /// ★ 전부 끈 사람의 화면. 폰은 **빈 상태 한 줄**, 위젯은 `.noProviders` — 숫자를 지어내지 않는다.
    @Test("전부 끄기: 제공자 셋이 다 비워지면 폰은 빈 상태로, 위젯은 안내로 떨어진다(0% 줄이 서지 않는다)")
    func everyProviderClearedFallsBackToTheEmptyState() async throws {
        let cleared = #"""
        [
          {"device_id":"mac-off-a1","device_label":"예성의 MacBook Pro",
           "provider":"claude","five_hour_percent":null,"five_hour_resets_at":null,
           "weekly_percent":null,"weekly_resets_at":null,"plan_label":null,"observed_at":"2026-09-17T05:04:30+00:00"},
          {"device_id":"mac-off-a1","device_label":"예성의 MacBook Pro",
           "provider":"codex","five_hour_percent":null,"five_hour_resets_at":null,
           "weekly_percent":null,"weekly_resets_at":null,"plan_label":null,"observed_at":"2026-09-17T05:04:30+00:00"},
          {"device_id":"mac-off-a1","device_label":"예성의 MacBook Pro",
           "provider":"antigravity","five_hour_percent":null,"five_hour_resets_at":null,
           "weekly_percent":null,"weekly_resets_at":null,"plan_label":null,"observed_at":"2026-09-17T05:04:30+00:00"}
        ]
        """#
        let harness = await RankMeHarness(label: "v0347-cleared-all") { request in
            if request.path == "/rest/v1/ai_limits", request.method == "GET" { return .json(cleared) }
            if request.path == "/rest/v1/ai_limits_prefs", request.method == "GET" { return .json("[]") }
            return MeStoreTests.rootResponder(request)
        }
        defer { harness.tearDown() }
        let store = harness.me

        store.appDidBecomeActive()
        #expect(await baseWaitUntil { store.aiLimits.state.hasLoaded })
        #expect(store.aiLimits.displayRows.isEmpty, "비워진 행으로 줄을 만들었다")
        #expect(store.aiLimits.displayGroups.isEmpty, "줄이 0개인 맥의 **머리글만** 남겼다 — 그 줄은 '그 맥은 0% 다'로 읽힌다")
        #expect(!store.aiLimits.hasVisibleProviders)
        #expect(store.aiLimits.fiveHourSummary == nil)
        #expect(store.aiLimits.mainDisplayGroup == nil, "그릴 맥이 없는데 메인 맥을 지어냈다")

        // 위젯에는 **빈 목록**이 간다(nil 이 아니다 — "아직 모른다"와 "그릴 줄이 없다"는 다른 안내다).
        let panel = try #require(store.aiLimits.widgetPanel(), "받았는데 패널을 안 넘겼다 — 위젯이 '앱을 열면'으로 굳는다")
        #expect(panel.providers.isEmpty)
        #expect(panel.deviceName == nil, "그릴 줄이 없는데 맥 이름을 실었다 — 위젯 머리에 이름만 남는다")
        #expect(AingWidgetLimitsState(snapshot: Self.snapshot(panel), at: Self.now) == .noProviders)
        #expect(AingWidgetLimitsState(snapshot: Self.snapshot(nil), at: Self.now) == .noData, "두 빈 상태가 한 뜻이 됐다")
    }

    // MARK: - 판정은 '보이는 창이 0개인가' 하나다

    /// ★ **이 표가 이 변경의 핵심 그물이다.** 네 모양을 두 표면에 같이 먹여, 숨는 것이 **(창 0개) 하나뿐**임을 센다.
    /// '5시간 창이 있나'로 재는 구현은 `주간만` 줄에서 빨개진다(= 안티그래비티가 통째로 사라지는 결함).
    /// '퍼센트가 null 인 칸이 있나'로 재는 구현도 같은 자리에서 빨개진다.
    @Test("판정 표: 5시간만·주간만·둘 다 있는 제공자는 남고 **창 0개만** 숨는다(폰·위젯이 같은 판정)")
    func onlyAProviderWithZeroVisibleWindowsIsHidden() throws {
        let base = Self.now
        func fetched(_ provider: String, fiveHour: Double?, weekly: Double?) -> AILimitFetchedRow {
            AILimitFetchedRow(
                deviceID: Self.macA, deviceLabel: "예성의 MacBook Pro",
                provider: provider,
                fiveHourPercent: fiveHour, fiveHourResetsAt: fiveHour == nil ? nil : base.addingTimeInterval(9_000),
                weeklyPercent: weekly, weeklyResetsAt: weekly == nil ? nil : base.addingTimeInterval(450_000),
                planLabel: nil, observedAt: base.addingTimeInterval(-60)
            )
        }
        func widgetRow(_ provider: String, fiveHour: Double?, weekly: Double?) -> WidgetSnapshot.AILimitRow {
            WidgetSnapshot.AILimitRow(
                provider: provider,
                fiveHourPercent: fiveHour, fiveHourResetsAt: fiveHour == nil ? nil : base.addingTimeInterval(9_000),
                weeklyPercent: weekly, weeklyResetsAt: weekly == nil ? nil : base.addingTimeInterval(450_000),
                observedAt: base.addingTimeInterval(-60)
            )
        }
        // (이름, 5시간, 주간, 보여야 하나)
        let table: [(String, Double?, Double?, Bool)] = [
            ("둘 다 있다", 27, 60, true),
            ("5시간만(주간 없는 요금제)", 27, nil, true),
            ("주간만(안티그래비티 실측)", nil, 8, true),
            ("창 0개(설정에서 끈 뒤 올라온 비우기 행)", nil, nil, false),
        ]
        for (label, fiveHour, weekly, shows) in table {
            // 폰
            let bundle = meOneDeviceBundle(from: [fetched("claude", fiveHour: fiveHour, weekly: weekly)], now: base)
            #expect(bundle.visibleProviders.isEmpty == !shows, "폰: \(label) — 보임 판정이 뒤집혔다")
            // 위젯(같은 데이터 · 같은 판정이어야 한다)
            let panel = WidgetSnapshot.AILimitPanel(providers: [widgetRow("claude", fiveHour: fiveHour, weekly: weekly)])
            let state = AingWidgetLimitsState(snapshot: Self.snapshot(panel), at: base)
            if shows {
                guard case .limits(let limits) = state else { throw ClearedRowFailure.notLimits }
                #expect(limits.rows.map(\.provider) == [.claude], "위젯: \(label) — 줄이 사라졌다")
                #expect(limits.rows.first?.hasAnyWindow == true)
            } else {
                #expect(state == .noProviders, "위젯: \(label) — 그릴 숫자가 없는 줄을 세웠다")
            }
        }

        // 섞여 있을 때 **비워진 쪽만** 사라진다(목록이 통째로 비지 않는다 — 이것이 '없음' 처리와 섞이면 생기는 사고다).
        let mixed = meOneDeviceBundle(
            from: [fetched("claude", fiveHour: nil, weekly: nil), fetched("antigravity", fiveHour: nil, weekly: 8)],
            now: base
        )
        #expect(mixed.visibleProviders.map(\.provider) == [.antigravity])
        let mixedPanel = WidgetSnapshot.AILimitPanel(providers: [
            widgetRow("claude", fiveHour: nil, weekly: nil), widgetRow("antigravity", fiveHour: nil, weekly: 8),
        ])
        guard case .limits(let mixedLimits) = AingWidgetLimitsState(snapshot: Self.snapshot(mixedPanel), at: base) else {
            throw ClearedRowFailure.notLimits
        }
        #expect(mixedLimits.rows.map(\.provider) == [.antigravity])
        // 그 줄의 5시간 칸은 `없음` 글자를 쓴다(`—`(판정 불가)가 아니다 — 두 사실을 같은 글자로 말하지 않는다).
        #expect(mixedLimits.rows.first?.display(.fiveHour) == nil)
        #expect(AILimitColumnText.absentValueText == "없음")
    }

    /// ★ **맥 두 대 — 이 작업의 출발점.** 비우기는 **그 맥의 설정**이고 다른 맥은 아직 올린다.
    ///
    /// ## 0.3.46 이 틀렸던 자리(이 테스트가 뒤집은 단언)
    /// 그때는 "제공자당 `observed_at` 최신 하나"였다. 그래서 **맥 A 에서 끄면 맥 B 의 살아 있는 값까지
    /// 사라졌고**(비우기 행이 더 최신이면), 반대로 맥 B 가 다음 주기에 값을 올리면 **맥 A 에서 끈 것이
    /// 아무 효과도 없었다**. 어느 쪽이든 "한 대에서 끄기"가 불가능했고, 화면은 누구 값인지 말하지 않았다.
    /// 기기가 바깥 축이 되면 두 거짓이 함께 사라진다 — **끈 맥의 줄만 사라지고 다른 맥의 줄은 자기 묶음에 남는다.**
    ///
    /// 양쪽 순서를 **다 잰다**(한쪽만 재면 "항상 숨긴다"·"항상 보인다" 둘 다 초록이다).
    @Test("맥 두 대: 끈 맥의 줄만 사라지고 **다른 맥의 줄은 남는다**(어느 쪽이 더 최신이어도 같다)")
    func clearingOnOneMacDoesNotEraseTheOtherMac() throws {
        let base = Self.now
        func row(_ device: String, _ label: String, _ fiveHour: Double?, ago: TimeInterval) -> AILimitFetchedRow {
            AILimitFetchedRow(
                deviceID: device, deviceLabel: label,
                provider: "claude",
                fiveHourPercent: fiveHour, fiveHourResetsAt: fiveHour == nil ? nil : base.addingTimeInterval(9_000),
                weeklyPercent: fiveHour == nil ? nil : 60, weeklyResetsAt: nil,
                planLabel: fiveHour == nil ? nil : "max", observedAt: base.addingTimeInterval(-ago)
            )
        }
        let offMac = row(Self.macA, "예성의 MacBook Pro", nil, ago: 30)        // 방금 껐다
        let liveOld = row(Self.macB, "사무실 iMac", 27, ago: 7_200)            // 두 시간 전 값(아직 켜 둔 맥)
        let liveNew = row(Self.macB, "사무실 iMac", 27, ago: 10)               // 방금 올린 값

        // ① 비우기가 **더 최신**이어도 다른 맥의 값은 남는다. 0.3.46 은 여기서 목록을 통째로 비웠다
        //    (= 아직 켜 둔 맥의 살아 있는 숫자가 남의 설정 때문에 사라졌다).
        let clearedIsNewer = AILimitsStore.groups(from: [liveOld, offMac], now: base)
        #expect(clearedIsNewer.map(\.device.deviceID) == [Self.macB],
                "끈 맥의 묶음이 남았거나 켜 둔 맥의 묶음이 사라졌다(\(clearedIsNewer.map(\.device.deviceID)))")
        #expect(clearedIsNewer.first?.bundle.visibleProviders.map(\.provider) == [.claude])
        #expect(clearedIsNewer.first?.bundle.provider(.claude)?.window(.fiveHour)?.usedPercent == 27)

        // ② 값이 **더 최신**이어도 끈 맥의 줄은 돌아오지 않는다. 0.3.46 은 여기서 Claude 를 그려
        //    "맥 A 에서 껐는데 되살아났다"가 됐다.
        let valueIsNewer = AILimitsStore.groups(from: [offMac, liveNew], now: base)
        #expect(valueIsNewer.map(\.device.deviceID) == [Self.macB],
                "끈 맥의 줄이 다른 맥 값으로 되살아났다 — 이 작업이 고치려던 바로 그 결함이다")

        // ③ 두 맥이 **다 켜져 있으면** 둘 다 보인다(기준선 — 이것이 같은 입력이면 ①②는 영원히 초록이다).
        let bothOn = AILimitsStore.groups(from: [row(Self.macA, "예성의 MacBook Pro", 44, ago: 30), liveOld], now: base)
        #expect(bothOn.map(\.device.deviceID) == [Self.macA, Self.macB], "두 맥이 다 켜져 있는데 묶음이 하나다")
        #expect(bothOn.map { $0.bundle.provider(.claude)?.window(.fiveHour)?.usedPercent } == [44, 27],
                "두 맥의 값이 섞였다 — 각 묶음은 **자기 맥의 숫자**만 말해야 한다")

        // ④ **한 기기 안**에서는 비우기가 값을 덮는다(서버 PK 가 같아 행이 하나지만, 응답이 둘을 줘도 최신이 이긴다).
        let sameMac = AILimitsStore.groups(
            from: [row(Self.macA, "예성의 MacBook Pro", 27, ago: 7_200), row(Self.macA, "예성의 MacBook Pro", nil, ago: 30)],
            now: base
        )
        #expect(sameMac.isEmpty, "한 맥 안에서 비우기가 옛 값 행에 밀렸다 — 끈 사람의 카드에 옛 숫자가 최대 3일 남는다")
    }

    /// 3일 유령 게이트는 **그대로다**(이 변경은 그것과 별개의 빠른 길이다). 비워진 행이 늙어도 결과는 같다 — 숨김.
    @Test("유령 게이트는 그대로: 문턱 3일이 살아 있고, 늙은 비우기 행도 (게이트든 창 0개든) 숨는다")
    func theThreeDayGhostGateIsUntouched() {
        let base = Self.now
        #expect(AILimitGhostRow.maxObservationAge == 3 * 86_400, "유령 문턱이 바뀌었다 — 이 변경은 그 게이트를 건드리지 않는다")
        #expect(AILimitsStore.ghostRowAge == AILimitGhostRow.maxObservationAge, "폰과 위젯이 다른 문턱을 쓴다")
        let old = AILimitFetchedRow(deviceID: Self.macA, provider: "claude", fiveHourPercent: nil, fiveHourResetsAt: nil,
                                    weeklyPercent: nil, weeklyResetsAt: nil, planLabel: nil,
                                    observedAt: base.addingTimeInterval(-4 * 86_400))
        #expect(meOneDeviceBundle(from: [old], now: base).visibleProviders.isEmpty)
        // ★ 유령뿐인 맥은 **묶음 자체가 서지 않는다**(이름만 남은 머리글은 "그 맥은 0% 다"로 읽힌다).
        #expect(AILimitsStore.groups(from: [old], now: base).isEmpty, "3일 넘게 꺼진 맥의 이름만 남았다")
        // 살아 있는 값 행은 여전히 보인다(게이트를 조이지 않았다).
        let alive = AILimitFetchedRow(deviceID: Self.macA, provider: "claude", fiveHourPercent: 27, fiveHourResetsAt: nil,
                                      weeklyPercent: 60, weeklyResetsAt: nil, planLabel: "max",
                                      observedAt: base.addingTimeInterval(-600))
        #expect(meOneDeviceBundle(from: [alive], now: base).visibleProviders.map(\.provider) == [.claude])
    }

    // MARK: - 빈 상태 문구

    /// ★ 설정 스위치가 생긴 뒤 "맥 앱에서 AI 도구에 **로그인하면** 보여요" 는 **거짓이 될 수 있다** —
    /// 끈 사람은 이미 로그인해 있고, 몇 번을 더 로그인해도 카드는 비어 있다. 그렇다고 두 경우를 가려 다르게
    /// 말할 수도 없다(위젯은 가릴 단서가 없고, 폰의 단서는 3일이면 사라져 문구가 혼자 바뀐다 —
    /// 근거 넷은 `AILimitSurfaceText` 머리말).
    ///
    /// 그래서 재는 것: **한 상수** · **옛 문장이 아님** · **두 문을 다 가리킴**.
    @Test("빈 상태 문구: 폰·위젯이 한 상수를 쓰고, 연동과 보기 설정 **두 문**을 가리킨다(옛 '로그인하면' 한 문장이 아니다)")
    func emptyStateSentenceIsTrueForBothDoors() throws {
        let text = AILimitSurfaceText.noVisibleProviders
        // ① 한 상수 — 두 모듈이 각자 적으면 한쪽만 고쳐지는 날 같은 상태를 두 화면이 다르게 말한다.
        #expect(MeText.aiLimitsNoProviders == text && AingWidgetText.limitsNoProviders == text,
                "폰·위젯이 다른 빈 상태 문구를 쓴다")
        // ② 옛 문장이 아니다(설정에서 끈 사람에게 거짓이던 그 문장).
        #expect(text != "맥 앱에서 AI 도구에 로그인하면 보여요", "끈 사람에게 거짓인 옛 문구로 돌아갔다")
        // ③ 두 문을 다 가리킨다: 연동(로그인)과 보기 설정.
        #expect(text.contains("로그인"), "연동이 없는 사람이 할 일이 문장에 없다")
        #expect(text.contains("보기"), "설정에서 끈 사람이 할 일이 문장에 없다 — 그 사람에게 이 화면은 고장으로 읽힌다")
        // ④ 다른 빈 상태(아직 못 받음)와 섞이지 않는다.
        #expect(text != AingWidgetText.limitsNoData && !AingWidgetText.limitsNoData.isEmpty)
        // ⑤ 문장 길이 — 위젯 미디움의 안내 자리(초상 72pt 옆)에 들어갈 한 문장이다.
        #expect(text.count <= 40, "안내가 너무 길다(\(text.count)자) — 위젯 미디움에서 네 줄을 넘긴다")

        // 두 모듈 어디에도 **그 문장을 다시 적지 않았다**(상수를 참조한다).
        let phone = try IntegrationContractTests.code("Sources/CheckMobileKit/Me/MeAILimitsText.swift")
        let widget = try IntegrationContractTests.code("Sources/CheckWidgetsKit/AingWidgetModel.swift")
        for (name, source) in [("폰", phone), ("위젯", widget)] {
            #expect(source.contains("AILimitSurfaceText.noVisibleProviders"), "\(name): 빈 상태 문구를 공유 상수에서 안 가져온다")
            #expect(!source.contains("로그인하면 보여요"), "\(name): 옛 문장을 다시 적었다")
        }
        // 그 문구가 **화면에 실제로 쓰이는지**(상수만 바꾸고 뷰가 다른 글자를 그리면 초록인 채 거짓이다).
        let card = try IntegrationContractTests.code("Sources/CheckMobileKit/Me/MeAILimitsCard.swift")
        #expect(card.contains("MeText.aiLimitsNoProviders"), "폰 카드가 빈 상태 문구를 그리지 않는다")
        let limitsWidget = try IntegrationContractTests.code("Sources/CheckWidgetsKit/Widgets/AingLimitsWidget.swift")
        #expect(limitsWidget.contains("AingWidgetText.limitsNoProviders"), "위젯이 빈 상태 문구를 그리지 않는다")
    }

    // MARK: - 소스 계약(주석을 걷어내고 본다)

    /// 숨김 판정이 **한 술어**인지 소스로 되묻는다. 값으로 재는 위의 표와 짝이다 — 표는 "지금 같은 답을 내는가"를,
    /// 여기는 "같은 자리를 보고 있는가"를 잰다(두 표면이 각자 자기 조건을 적으면 언젠가 갈린다).
    @Test("소스 계약: 두 표면이 `isLinked`/`hasAnyWindow` 로 거르고, 창 개수가 아닌 조건으로 숨기지 않는다")
    func hidingJudgementIsOnePredicateOnBothSurfaces() throws {
        let widget = try IntegrationContractTests.code("Sources/CheckWidgetsKit/AingWidgetModel.swift")
        #expect(widget.contains("guard snapshot.isLinked else { return nil }"),
                "위젯이 공유 술어로 걸러내지 않는다 — 조건을 따로 적으면 폰과 갈린다")
        #expect(widget.contains("AILimitGhostRow.isGhost"), "위젯의 3일 유령 게이트가 사라졌다")
        for banned in ["fiveHourPercent == nil", "fiveHourPercent != nil"] {
            #expect(!widget.contains("guard row.\(banned)"), "위젯이 5시간 창 유무로 줄을 지운다(주간만 오는 제공자가 사라진다)")
        }
        let store = try IntegrationContractTests.code("Sources/CheckMobileKit/Me/MeAILimitsStore.swift")
        #expect(store.contains("row.hasAnyWindow ? row : nil"), "폰이 그릴 칸이 0개인 줄을 끝에서 거르지 않는다")
        #expect(store.contains("bundle.visibleProviders"), "폰이 공유 거르기를 안 쓴다")
        // ★ 묶음도 같은 자리에서 거른다 — 줄이 0개가 된 맥의 머리글만 남기지 않는다.
        #expect(store.contains("guard !bundle.visibleProviders.isEmpty else { return nil }"),
                "폰이 제공자 0명인 기기 묶음을 걸러내지 않는다 — 이름만 남은 머리글이 선다")
        // 위젯 본문도 같은 깃발을 본다(그릴 숫자가 없는 줄을 세우지 않는다).
        let limitsWidget = try IntegrationContractTests.code("Sources/CheckWidgetsKit/Widgets/AingLimitsWidget.swift")
        #expect(limitsWidget.contains(#"filter(\.hasAnyWindow)"#), "위젯 본문이 빈 줄 그물을 버렸다")
        // 설정을 아는 코드는 폰·위젯에 **한 줄도 없다**(스위치는 맥에만 있고, 폰은 '줄이 없다'만 본다).
        for (name, source) in [("폰 카드", try IntegrationContractTests.code("Sources/CheckMobileKit/Me/MeAILimitsCard.swift")),
                               ("폰 스토어", store), ("위젯", widget)] {
            for banned in ["disabledProviders", "aiLimits.show", "AILimitVisibility"] {
                #expect(!source.contains(banned), "\(name) 가 맥의 로컬 설정을 읽으려 한다(\(banned)) — 그 값은 서버에 없다")
            }
        }
    }

    // MARK: - 도우미

    nonisolated static func snapshot(_ panel: WidgetSnapshot.AILimitPanel?) -> WidgetSnapshot {
        WidgetSnapshot(
            generatedAt: now.addingTimeInterval(-30),
            me: .init(working: true, sessionStartedAt: now.addingTimeInterval(-3_600), todaySeconds: 3_600,
                      weekSeconds: 7_200, goalHours: 40, status: .working),
            aiLimits: panel
        )
    }

    enum ClearedRowFailure: Error { case notLimits }
}
