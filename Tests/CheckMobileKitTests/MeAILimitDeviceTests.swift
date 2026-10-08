import AppKit
import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit
@testable import CheckWidgetsKit

// MARK: - v0.3.47 기기 축 — 폰 카드 · 위젯 (폰 쪽 그물)
//
// ## 무엇을 고쳤고 무엇이 그 증거인가
// 서버는 **이미** 기기별로 저장한다(`ai_limits` PK = user·device·provider). 폰이 "제공자당 `observed_at` 최신
// 하나"로 접고 있었을 뿐이고, 그 접기가 두 거짓을 만들었다:
//  ① 맥 A 에서 끈 제공자가 맥 B 의 더 새로운 행에 밀려 **되살아난다**(한 대에서 끌 방법이 없다).
//  ② 두 맥이 다른 값을 보고해도 화면이 **누구 값인지 말하지 않는다**.
// 이 스위트는 그 접기가 **사라졌는지**를 값으로 되묻는다 — 그리고 접기를 되돌리는 변형이 어디서 빨개지는지를
// 각 단언의 메시지에 적어 둔다.
//
// ## 기준선을 다르게 둔다
// "맥 한 대" 갈래와 "맥 두 대" 갈래를 **같은 스위트에서** 잰다. 한쪽만 재면 "항상 묶는다"(한 대인 사람에게
// 군더더기가 보인다)와 "절대 안 묶는다"(고친 것이 없다)가 **둘 다 초록**이다.

/// 기기 축이 요점이 **아닌** 테스트(제공자 고르기 · 유령 문턱 · 칸 구성)가 쓰는 한 대뿐인 픽스처의 기기.
let mePureMac = "mac-pure-7a3f"

/// 기기 **한 대**뿐인 픽스처의 묶음 하나. 0.3.46 의 `AILimitsStore.bundle(from:now:)` 가 서던 자리다 —
/// 그 함수는 **기기를 접는 함수**였으므로 이름째로 지웠다(남겨 두면 다음 사람이 그 접기를 다시 쓴다).
/// 기기가 둘 이상인 갈래는 `AILimitsStore.groups(from:now:)` 를 직접 불러 잰다.
@MainActor
func meOneDeviceBundle(from rows: [AILimitFetchedRow], now: Date) -> AILimitSnapshotBundle {
    let groups = AILimitsStore.groups(from: rows, now: now)
    #expect(groups.count <= 1, "한 대뿐인 픽스처인데 묶음이 \(groups.count)개다 — 테스트 전제가 깨졌다")
    return groups.first?.bundle ?? AILimitSnapshotBundle(providers: [])
}

@MainActor
@Suite("나 탭 AI 리밋 — 기기 축(v0.3.47)")
struct MeAILimitDeviceTests {
    nonisolated static let now = MobileClock.demoInstant   // 2026-09-17 14:05 KST(목)

    /// 서버 행 한 줄(기기까지). 시각은 `now` 에서 뺀 초.
    nonisolated static func row(
        _ device: String, label: String?, provider: String = "claude",
        fiveHour: Double? = 27, weekly: Double? = 60, ago: TimeInterval
    ) -> AILimitFetchedRow {
        AILimitFetchedRow(
            deviceID: device, deviceLabel: label, provider: provider,
            fiveHourPercent: fiveHour, fiveHourResetsAt: fiveHour == nil ? nil : now.addingTimeInterval(9_000),
            weeklyPercent: weekly, weeklyResetsAt: weekly == nil ? nil : now.addingTimeInterval(450_000),
            planLabel: "max", observedAt: now.addingTimeInterval(-ago)
        )
    }

    // MARK: - 묶기

    /// ★ 1대/2대 **분기 조건**을 값으로 못 박는다. 조건은 `groups.count` 가 아니라 **`displayGroups.count`** 다:
    /// 맥은 둘인데 한 대가 전부 껐거나 3일째 꺼져 있으면 화면에는 묶음이 하나뿐이고, 그때 이름을 그리면
    /// **있지도 않은 둘째 맥을 암시한다**.
    @Test("분기 조건: 그릴 묶음이 하나면 이름을 안 그리고, 둘 이상이면 그린다(숨겨진 맥은 세지 않는다)")
    func deviceNamesAppearOnlyWhenTwoMacsAreActuallyDrawn() throws {
        let base = Self.now
        // ① 한 대 — 이름 없음.
        let one = AILimitsStore.groups(from: [Self.row("mac-a", label: "Mac mini", ago: 60)], now: base)
        #expect(one.count == 1)
        // ② 두 대 — 둘 다 그린다.
        let two = AILimitsStore.groups(
            from: [Self.row("mac-a", label: "Mac mini", ago: 60),
                   Self.row("mac-b", label: "사무실 iMac", ago: 600)],
            now: base
        )
        #expect(two.map(\.device.deviceID) == ["mac-a", "mac-b"], "최근에 일한 맥이 먼저가 아니다")
        // ③ 맥은 둘인데 한 대는 **전부 비워졌다**(그 맥에서 껐다) → 그릴 묶음은 하나다.
        let oneCleared = AILimitsStore.groups(
            from: [Self.row("mac-a", label: "Mac mini", ago: 60),
                   Self.row("mac-b", label: "사무실 iMac", fiveHour: nil, weekly: nil, ago: 30)],
            now: base
        )
        #expect(oneCleared.map(\.device.deviceID) == ["mac-a"],
                "줄이 0개인 맥의 머리글만 남았다 — 이름뿐인 묶음은 '그 맥은 0% 다'로 읽힌다")
        // ④ 한 대가 **3일째 꺼져 있다** → 그 묶음도 서지 않는다(유령 게이트를 묶기 **앞에** 지난다).
        let oneGhost = AILimitsStore.groups(
            from: [Self.row("mac-a", label: "Mac mini", ago: 60),
                   Self.row("mac-b", label: "사무실 iMac", ago: AILimitGhostRow.maxObservationAge + 60)],
            now: base
        )
        #expect(oneGhost.map(\.device.deviceID) == ["mac-a"], "3일 넘게 꺼진 맥의 이름만 남았다")
    }

    /// ★ **이름이 겹치는 맥 두 대**(맥 미니 두 대 — 시스템 설정 이름이 글자 그대로 같다). 맥들은 서로를 모르므로
    /// 가르는 일은 **읽는 쪽**이 한다. 겹치지 않는 이름에는 아무것도 붙이지 않는다 — 한 대뿐인 사람에게
    /// 식별자 조각을 보여 줄 이유가 없다.
    @Test("이름 겹침: 같은 이름 둘은 꼬리로 갈리고, 겹치지 않는 이름엔 아무것도 안 붙는다")
    func duplicateLabelsGetDistinguishingTails() throws {
        let base = Self.now
        let devices = AILimitsStore.groups(
            from: [Self.row("twin-aaaa-a1b2", label: "Mac mini", ago: 30),
                   Self.row("twin-bbbb-c3d4", label: "Mac mini", ago: 600),
                   Self.row("solo-eeee-f5a6", label: "사무실 iMac", ago: 900)],
            now: base
        ).map(\.device)
        let names = AILimitDeviceRoster.displayNames(devices)
        #expect(names["twin-aaaa-a1b2"] == "Mac mini (A1B2)")
        #expect(names["twin-bbbb-c3d4"] == "Mac mini (C3D4)")
        #expect(names["twin-aaaa-a1b2"] != names["twin-bbbb-c3d4"], "맥 미니 두 대가 같은 이름으로 섰다 — 고를 수도 가를 수도 없다")
        #expect(names["solo-eeee-f5a6"] == "사무실 iMac", "겹치지 않는 이름에 식별자 조각이 붙었다")
    }

    /// ★ **이름을 한 번도 올린 적 없는 맥**(v0.3.46 이하 빌드가 남긴 행). `device_label` 이 null 이다.
    /// "이름 모를 맥" 하나로 두면 둘이 나란히 설 때 어느 쪽인지 알 수가 없으므로 꼬리를 붙여 가른다.
    @Test("label 없는 옛 행: `이름 모를 맥 ABCD` 로 서고, 둘이면 서로 다른 이름이 된다")
    func labellessRowsGetANameThatStillDistinguishes() throws {
        let base = Self.now
        let devices = AILimitsStore.groups(
            from: [Self.row("old-mac-9f8e", label: nil, ago: 30),
                   Self.row("old-mac-2b1c", label: nil, ago: 600),
                   Self.row("new-mac-0001", label: "예성의 MacBook Pro", ago: 900)],
            now: base
        ).map(\.device)
        let names = AILimitDeviceRoster.displayNames(devices)
        let first = try #require(names["old-mac-9f8e"])
        let second = try #require(names["old-mac-2b1c"])
        #expect(first.hasPrefix(AILimitDevice.unnamedPrefix) && second.hasPrefix(AILimitDevice.unnamedPrefix))
        #expect(first == "\(AILimitDevice.unnamedPrefix) 9F8E" && second == "\(AILimitDevice.unnamedPrefix) 2B1C")
        #expect(first != second, "이름 없는 맥 둘이 같은 글자로 섰다 — 가를 수 없다")
        // 이름을 올린 맥은 그 이름 그대로(섞이지 않는다).
        #expect(names["new-mac-0001"] == "예성의 MacBook Pro")
        // 공백뿐인 라벨도 **없는 것**으로 본다(서버 CHECK 가 1자 하한이라 그 값은 애초에 올라가지 않는다).
        let blank = AILimitsStore.groups(from: [Self.row("blank-mac-77aa", label: "   ", ago: 30)], now: base)
        #expect(blank.first?.device.label == nil, "공백뿐인 이름을 이름으로 받았다")
        #expect(AILimitDeviceRoster.displayNames(blank.map(\.device))["blank-mac-77aa"]
                == "\(AILimitDevice.unnamedPrefix) 77AA")
    }

    /// ★ **옛 빌드가 이름을 지우지 못한다.** 한 맥이 이름 있는 행과 이름 없는 행을 둘 다 갖고 있을 때
    /// (업데이트 전후가 섞인 창), "가장 최근 행의 라벨"을 쓰면 **이름 없는 행이 이름을 지운다**.
    /// 규칙은 "라벨이 **있는** 행 중 가장 최근 것"이다(코어 `AILimitDeviceRoster.fold`).
    @Test("이름 고르기: 라벨 있는 행 중 최근 것이 이긴다(라벨 없는 최신 행이 이름을 지우지 않는다)")
    func theNewestLabelledRowNamesTheMac() throws {
        let base = Self.now
        let groups = AILimitsStore.groups(
            from: [
                // 이름 있는 행(10분 전) · 이름 없는 행(30초 전 — **더 최신**) · 둘 다 같은 맥.
                Self.row("mac-mix", label: "예성의 MacBook Pro", provider: "claude", ago: 600),
                Self.row("mac-mix", label: nil, provider: "codex", ago: 30),
            ],
            now: base
        )
        #expect(groups.count == 1)
        #expect(groups.first?.device.label == "예성의 MacBook Pro",
                "라벨 없는 최신 행이 맥 이름을 지웠다 — 고르개·카드에서 그 맥이 '이름 모를 맥'이 된다")
        // 그리고 **더 새 이름**은 이긴다(이름을 바꾼 사람의 새 이름이 옛 이름에 밀리지 않는다).
        let renamed = AILimitsStore.groups(
            from: [Self.row("mac-mix", label: "옛 이름", provider: "claude", ago: 600),
                   Self.row("mac-mix", label: "새 이름", provider: "codex", ago: 30)],
            now: base
        )
        #expect(renamed.first?.device.label == "새 이름", "맥 이름을 바꿨는데 옛 이름이 남는다")
    }

    /// 묶음 id 가 **기기**다. 맥 두 대가 같은 Claude 를 올리면 줄 id(제공자)는 카드 안에서 두 번 나오고,
    /// 한 `ForEach` 에 펼치면 SwiftUI 가 같은 id 둘을 보고 줄을 뒤섞는다.
    @Test("id: 묶음 id 는 유일하고(기기), 줄 id 는 묶음 안에서만 유일하다")
    func groupIDsAreUniqueEvenWhenProvidersRepeat() async throws {
        let harness = await RankMeHarness(label: "me-dev-ids") { MeAILimitsTests.responder($0) }
        defer { harness.tearDown() }
        let store = harness.me
        store.appDidBecomeActive()
        #expect(await baseWaitUntil { store.aiLimits.state.hasLoaded })

        let groups = store.aiLimits.displayGroups
        #expect(Set(groups.map(\.id)).count == groups.count, "기기 묶음 id 가 겹친다")
        for group in groups {
            #expect(Set(group.rows.map(\.id)).count == group.rows.count, "한 묶음 안에서 제공자 줄 id 가 겹친다")
        }
        // ★ 펼친 목록에서는 **겹친다** — 그래서 그리는 쪽이 펼친 목록을 쓰면 안 된다(스토어 주석의 경고).
        let flat = store.aiLimits.displayRows.map(\.id)
        #expect(Set(flat).count < flat.count, "전제: 두 맥이 같은 제공자를 올렸다(겹치지 않으면 이 그물이 의미 없다)")
    }

    // MARK: - 메인 맥

    /// ★ 맥이 **한 대**면 고른 맥을 **묻지 않는다**(GET 0건). 고르기가 바꿀 수 있는 것이 없고, 혼자 쓰는 사람 —
    /// 거의 모든 사용자 — 의 새로고침마다 요청이 하나 더 나가는 것을 피한다.
    @Test("맥 한 대: 위젯은 지금과 같고(이름 없음) 고른 맥을 묻지도 않는다")
    func oneMacLooksExactlyLikeBeforeAndCostsNoExtraRequest() async throws {
        let single = #"""
        [
          {"device_id":"only-mac-1","device_label":"Mac mini",
           "provider":"claude","five_hour_percent":27,"five_hour_resets_at":"2026-09-17T07:40:00+00:00",
           "weekly_percent":60,"weekly_resets_at":"2026-09-22T10:05:00+00:00","plan_label":"max","observed_at":"2026-09-17T05:03:00+00:00"},
          {"device_id":"only-mac-1","device_label":"Mac mini",
           "provider":"codex","five_hour_percent":0,"five_hour_resets_at":null,
           "weekly_percent":56,"weekly_resets_at":"2026-09-21T06:51:40+00:00","plan_label":"plus","observed_at":"2026-09-17T05:00:00+00:00"}
        ]
        """#
        let harness = await RankMeHarness(label: "me-dev-one") { request in
            if request.path == "/rest/v1/ai_limits", request.method == "GET" { return .json(single) }
            return MeStoreTests.rootResponder(request)
        }
        defer { harness.tearDown() }
        let store = harness.me
        store.appDidBecomeActive()
        #expect(await baseWaitUntil { store.aiLimits.state.hasLoaded })

        #expect(store.aiLimits.displayGroups.count == 1)
        #expect(!store.aiLimits.showsDeviceNames, "맥 한 대인데 기기 이름을 그린다 — 군더더기를 보이지 않는 것이 사용자 결정이다")
        #expect(store.aiLimits.displayRows.map(\.provider) == [.claude, .codex])
        let panel = try #require(store.aiLimits.widgetPanel())
        #expect(panel.deviceName == nil, "맥 한 대인데 위젯 머리에 이름을 적는다")
        #expect(panel.deviceNameTail == nil, "맥 한 대인데 위젯에 겹침 꼬리를 실었다")
        #expect(panel.providers.map(\.provider) == ["claude", "codex"])
        #expect(harness.requests(path: "/rest/v1/ai_limits_prefs", method: "GET").isEmpty,
                "맥 한 대인데 고른 맥을 물었다 — 답이 바꿀 수 있는 것이 없는 요청이다")
        MeAILimitsTests.expectNoPrefsWrites(harness)
        harness.expectNoForbiddenCalls()
    }

    /// ★ 고른 맥이 **두 번째** 맥이면 위젯이 그 맥을 싣는다(기본값은 "가장 최근에 일한 맥"이라 안 고르면 첫째다).
    /// 기준선을 다르게 둔다: 고르지 않은 경우(`MeAILimitsTests` 의 픽스처)는 첫째 맥이 선다.
    @Test("고른 맥: ai_limits_prefs 가 가리키는 맥이 위젯에 실린다(안 골랐을 때와 **다른** 맥이다)")
    func theChosenMacIsWhatTheWidgetGets() async throws {
        let harness = await RankMeHarness(label: "me-dev-chosen") { request in
            if request.path == "/rest/v1/ai_limits_prefs", request.method == "GET" {
                return .json(#"[{"main_device_id":"\#(MeAILimitsTests.macB)"}]"#)
            }
            return MeAILimitsTests.responder(request)
        }
        defer { harness.tearDown() }
        let store = harness.me
        store.appDidBecomeActive()
        #expect(await baseWaitUntil { store.aiLimits.state.hasLoaded })

        #expect(store.aiLimits.mainDeviceID == MeAILimitsTests.macB)
        #expect(store.aiLimits.mainDisplayGroup?.device.deviceID == MeAILimitsTests.macB)
        let panel = try #require(store.aiLimits.widgetPanel())
        #expect(panel.deviceName == "사무실 iMac", "고른 맥의 이름이 위젯에 안 갔다")
        #expect(panel.deviceNameTail == nil, "이름이 겹치지 않는데 꼬리를 실었다")
        #expect(panel.providers.map(\.provider) == ["claude"], "고른 맥이 아닌 맥의 줄이 실렸다")
        #expect(panel.providers.first?.fiveHourPercent == 9, "고른 맥의 숫자가 아니다(첫째 맥은 27% 다)")
        // 카드는 **여전히 둘 다** 보여 준다 — 고르기는 위젯만의 일이다(사용자 결정).
        #expect(store.aiLimits.displayGroups.count == 2, "고르기가 폰 카드까지 줄였다 — 카드는 전부 보여 준다")
        MeAILimitsTests.expectNoPrefsWrites(harness)
        harness.expectNoForbiddenCalls()
    }

    /// ★ 이름이 **겹치는** 맥 두 대(상한 길이 64 스칼라)면 위젯 패널이 합친 이름과 **꼬리를 따로** 싣는다(v0.3.47 P2).
    ///
    /// 위젯은 맥 한 대만 그리므로 "이 숫자가 어느 쌍둥이 것인지"를 말할 글자가 꼬리뿐이다. 합친 글자만 실으면 위젯은
    /// 어디까지가 꼬리인지 몰라 한 `Text` 로 그리고, 말줄임이 그 꼬리부터 먹는다. 기준선을 다르게 둔다: 고른 맥이
    /// **다른** 쌍둥이면 꼬리도 **다른** 글자다(같은 꼬리가 실리면 위젯 두 장이 다시 같아진다).
    @Test("쌍둥이 맥: 위젯 패널이 합친 이름 + **꼬리를 따로** 싣는다 · 고른 쌍둥이에 따라 꼬리가 바뀐다")
    func twinMacsSendTheTailSeparatelyToTheWidget() async throws {
        let maxName = String(repeating: "가", count: AILimitDeviceLabelContract.maxScalars)
        let twins = #"""
        [
          {"device_id":"twin-aaaa-a1b2","device_label":"\#(maxName)",
           "provider":"claude","five_hour_percent":27,"five_hour_resets_at":"2026-09-17T07:40:00+00:00",
           "weekly_percent":60,"weekly_resets_at":"2026-09-22T10:05:00+00:00","plan_label":"max","observed_at":"2026-09-17T05:03:00+00:00"},
          {"device_id":"twin-bbbb-c3d4","device_label":"\#(maxName)",
           "provider":"claude","five_hour_percent":9,"five_hour_resets_at":"2026-09-17T07:40:00+00:00",
           "weekly_percent":11,"weekly_resets_at":"2026-09-22T10:05:00+00:00","plan_label":"max","observed_at":"2026-09-17T04:50:00+00:00"}
        ]
        """#
        func panel(chosen: String?) async throws -> WidgetSnapshot.AILimitPanel {
            let harness = await RankMeHarness(label: "me-dev-twin-\(chosen ?? "none")") { request in
                if request.path == "/rest/v1/ai_limits", request.method == "GET" { return .json(twins) }
                if request.path == "/rest/v1/ai_limits_prefs", request.method == "GET" {
                    return chosen.map { .json(#"[{"main_device_id":"\#($0)"}]"#) } ?? MeAILimitsTests.noPrefs
                }
                return MeStoreTests.rootResponder(request)
            }
            defer { harness.tearDown() }
            let store = harness.me
            store.appDidBecomeActive()
            #expect(await baseWaitUntil { store.aiLimits.state.hasLoaded })
            #expect(store.aiLimits.displayGroups.count == 2, "전제: 같은 이름 두 대가 둘 다 그려진다")
            MeAILimitsTests.expectNoPrefsWrites(harness)
            harness.expectNoForbiddenCalls()
            return try #require(store.aiLimits.widgetPanel())
        }

        // 안 골랐다 → 가장 최근에 일한 맥(A1B2).
        let recent = try await panel(chosen: nil)
        #expect(recent.deviceName == "\(maxName) (A1B2)", "합친 이름(소리·옛 위젯이 읽는 값)이 바뀌었다")
        #expect(recent.deviceNameTail == "A1B2", "쌍둥이인데 꼬리를 따로 싣지 않았다 — 위젯이 그 꼬리를 말줄임에 내준다")
        #expect(recent.providers.first?.fiveHourPercent == 27)
        // 다른 쌍둥이를 골랐다 → 꼬리도 다르다.
        let other = try await panel(chosen: "twin-bbbb-c3d4")
        #expect(other.deviceNameTail == "C3D4", "고른 쌍둥이의 꼬리가 아니다")
        #expect(other.providers.first?.fiveHourPercent == 9)
        #expect(recent.deviceNameTail != other.deviceNameTail, "두 쌍둥이가 같은 꼬리로 실렸다 — 위젯 두 장을 가를 글자가 없다")
        // 실린 두 칸이 위젯 쪽에서 **같은 조각**으로 되돌아온다(꼬리 경계를 위젯이 다시 짐작하지 않는다).
        let parts = AingWidgetLimits.deviceNameParts(combined: try #require(recent.deviceName), tail: recent.deviceNameTail)
        #expect(parts == AILimitDeviceNameParts(base: maxName, tail: "A1B2"))
    }

    /// ★ 고른 맥이 **목록에 없으면 접는다**. `main_device_id` 에는 FK 가 없고(마이그레이션 머리말), 고른 맥의 행이
    /// 사라지는 일은 정상이다(설정 off · 3일 유령). 접지 않으면 위젯이 통째로 빈다.
    @Test("모르는 식별자: 고른 맥이 사라졌으면 가장 최근에 일한 맥으로 접는다(위젯이 비지 않는다)")
    func anUnknownChosenIDFoldsToTheMostRecentMac() async throws {
        let harness = await RankMeHarness(label: "me-dev-gone") { request in
            if request.path == "/rest/v1/ai_limits_prefs", request.method == "GET" {
                return .json(#"[{"main_device_id":"mac-that-was-sold"}]"#)
            }
            return MeAILimitsTests.responder(request)
        }
        defer { harness.tearDown() }
        let store = harness.me
        store.appDidBecomeActive()
        #expect(await baseWaitUntil { store.aiLimits.state.hasLoaded })

        #expect(store.aiLimits.mainDeviceID == "mac-that-was-sold", "읽은 값을 그대로 들고 있어야 한다(접기는 쓰는 자리에서)")
        #expect(store.aiLimits.mainDisplayGroup?.device.deviceID == MeAILimitsTests.macA,
                "모르는 식별자에서 메인 맥이 nil 이 됐다 — 위젯이 통째로 빈다")
        let panel = try #require(store.aiLimits.widgetPanel())
        #expect(!panel.providers.isEmpty && panel.deviceName == "예성의 MacBook Pro")
    }

    /// ★ 고른 맥 **조회가 실패해도** 카드를 비우지 않는다. 카드는 그 값을 쓰지 않으므로 비울 이유가 없고,
    /// 위젯은 코어 규칙대로 가장 최근에 일한 맥으로 접는다 — 위젯 머리에 **그 맥 이름이 적히므로** 거짓말이 아니다.
    /// 그리고 한 번 읽은 뒤 실패하면 **들고 있던 값을 지킨다**(두 번째 조회가 흔들릴 때마다 위젯이 튀지 않게).
    @Test("고른 맥 조회 실패: 카드는 그대로, 위젯은 최근 맥으로 접는다 · 한 번 읽은 값은 실패로 안 지워진다")
    func aFailedPrefsReadNeverEmptiesTheCard() async throws {
        let answerPrefs = BaseLockedBox(false)
        let harness = await RankMeHarness(label: "me-dev-prefs-fail") { request in
            if request.path == "/rest/v1/ai_limits_prefs", request.method == "GET" {
                return answerPrefs.get() ? .json(#"[{"main_device_id":"\#(MeAILimitsTests.macB)"}]"#)
                                         : .missingFunction(request.path)
            }
            return MeAILimitsTests.responder(request)
        }
        defer { harness.tearDown() }
        let store = harness.me

        // ① 실패 — 카드는 멀쩡하고, 리밋 조회 자체는 성공했으므로 실패 깃발도 서지 않는다.
        store.appDidBecomeActive()
        #expect(await baseWaitUntil { store.aiLimits.state.hasLoaded })
        #expect(store.aiLimits.displayGroups.count == 2, "고른 맥을 못 읽었다고 카드를 비웠다")
        #expect(!store.aiLimits.state.hasFailed, "쓰지도 않는 조회의 실패를 카드의 실패로 올렸다")
        #expect(store.aiLimits.mainDeviceID == nil)
        #expect(store.aiLimits.widgetPanel()?.deviceName == "예성의 MacBook Pro", "최근 맥으로 접지 않았다")

        // ② 성공 — 고른 맥이 반영된다.
        answerPrefs.mutate { $0 = true }
        harness.clock.advance(AILimitsStore.staleSeconds + 1)
        store.appDidBecomeActive()
        #expect(await baseWaitUntil { store.aiLimits.mainDeviceID == MeAILimitsTests.macB })

        // ③ 다시 실패 — **들고 있던 값을 지킨다**(nil 로 되돌리면 위젯이 다른 맥으로 튄다).
        //
        // ★ `quiesceMe()` 로는 못 기다린다 — 그 함수는 `MeStore.inflight` 만 await 하고 리밋 스토어는 **자기
        //   task** 를 쥔다(실측: 그 기다림으로는 변형 "실패하면 지운다"가 **안 물렸다**. 단언이 로드가 끝나기
        //   전에 옛 값을 읽었다). 그래서 로드가 끝난 증거(`state.loadedAt` 이 새 시각으로 바뀜)를 기다린다 —
        //   그 칸은 두 번째 조회가 **돌아온 뒤에** 써진다.
        let loadedBefore = store.aiLimits.state.loadedAt
        answerPrefs.mutate { $0 = false }
        harness.clock.advance(AILimitsStore.staleSeconds + 1)
        store.appDidBecomeActive()
        #expect(await baseWaitUntil { store.aiLimits.state.loadedAt != loadedBefore },
                "세 번째 적재가 끝나지 않았다 — 이 단언은 아무것도 재지 못한다")
        #expect(store.aiLimits.mainDeviceID == MeAILimitsTests.macB,
                "두 번째 조회가 흔들릴 때마다 위젯이 다른 맥으로 튄다")
    }

    /// 토큰은 **합산 유지**다(2026-10-08 사용자 결정 — 리밋만 메인 맥을 따른다). 메인 맥을 바꿔도 토큰 수는
    /// 계정 전체의 값 그대로다.
    @Test("토큰 축: 메인 맥을 골라도 토큰 수는 계정 전체 합이다(순위표와 같은 장부)")
    func tokensStayAccountWideWhateverTheMainMacIs() async throws {
        let harness = await RankMeHarness(label: "me-dev-tokens") { request in
            if request.path == "/rest/v1/ai_limits_prefs", request.method == "GET" {
                return .json(#"[{"main_device_id":"\#(MeAILimitsTests.macB)"}]"#)
            }
            return MeAILimitsTests.responder(request)
        }
        defer { harness.tearDown() }
        let store = harness.me
        store.appDidBecomeActive()
        store.tabDidAppear()
        #expect(await baseWaitUntil { store.recordsState.hasLoaded && store.aiLimits.state.hasLoaded })
        await harness.quiesceMe()

        let panel = try #require(store.aiLimits.widgetPanel())
        #expect(panel.deviceName == "사무실 iMac", "전제: 메인 맥은 둘째 맥이다")
        #expect(panel.recentTokens == store.tokenGrid.totalTokens,
                "토큰이 메인 맥 것으로 깎였다 — 합산 유지가 사용자 결정이다")
        #expect(panel.todayTokens == AILimitsStore.todayTokens(store.tokenGrid))
    }

    // MARK: - ★ 고른 맥이 조용할 때 (v0.3.47 P1)

    /// 고른 맥이 **값을 비운 맥**(그 맥 설정에서 전부 껐다)일 때 폰이 하는 말.
    ///
    /// ## 이 테스트가 무는 결함 (실측으로 재현한 P1)
    /// 0.3.47 초안은 이름을 적는 조건을 `displayGroups.count > 1` 하나로 뒀다. 고른 맥이 조용하면 폰은 **다른
    /// 맥**을 그리는데 그릴 묶음이 하나뿐이라 그 조건이 **거짓**이었고, 그래서
    ///  · 폰 카드 머리글에 맥 이름이 **안 적혔고**,
    ///  · 위젯 머리에도 이름이 **안 실렸다**(`deviceName` nil).
    /// 설정 창 칩에는 고른 맥에 불이 들어와 있으므로, 사용자는 **다른 맥의 숫자를 자기가 고른 맥 것으로 읽는다**.
    ///
    /// ## 기준선을 다르게 둔다
    /// 같은 행 묶음에서 **고른 맥만 바꿔** 두 번 잰다. 한쪽만 재면 "늘 이름을 적는다"(혼자 쓰는 사람에게
    /// 군더더기가 보인다)와 "절대 안 적는다"(고친 것이 없다)가 둘 다 초록이다.
    @Test("고른 맥이 조용하면: 이름을 적고 · 대체 사실을 말하고 · 위젯에도 그 맥 이름을 싣는다(고른 맥이 멀쩡하면 전부 아니다)")
    func aSilentChosenMacIsNeverSubstitutedQuietly() async throws {
        // 맥 둘 — macB 는 **창 값이 전부 null**(그 맥에서 껐다)이고 **더 최근**이다.
        let rows = #"""
        [
          {"device_id":"mac-a-7f21","device_label":"예성의 MacBook Pro",
           "provider":"claude","five_hour_percent":27,"five_hour_resets_at":"2026-09-17T07:40:00+00:00",
           "weekly_percent":60,"weekly_resets_at":"2026-09-22T10:05:00+00:00","plan_label":"max","observed_at":"2026-09-17T05:03:00+00:00"},
          {"device_id":"mac-b-3c90","device_label":"사무실 iMac",
           "provider":"claude","five_hour_percent":null,"five_hour_resets_at":null,
           "weekly_percent":null,"weekly_resets_at":null,"plan_label":null,"observed_at":"2026-09-17T05:04:00+00:00"}
        ]
        """#
        func harness(chosen: String) async -> RankMeHarness {
            await RankMeHarness(label: "me-dev-silent-\(chosen)") { request in
                if request.path == "/rest/v1/ai_limits", request.method == "GET" { return .json(rows) }
                if request.path == "/rest/v1/ai_limits_prefs", request.method == "GET" {
                    return .json(#"[{"main_device_id":"\#(chosen)"}]"#)
                }
                return MeStoreTests.rootResponder(request)
            }
        }

        // ① 고른 맥(macB)이 조용하다 → 그려지는 것은 macA 하나뿐이다.
        let silent = await harness(chosen: MeAILimitsTests.macB)
        defer { silent.tearDown() }
        let quiet = silent.me
        quiet.appDidBecomeActive()
        #expect(await baseWaitUntil { quiet.aiLimits.state.hasLoaded })

        #expect(quiet.aiLimits.displayGroups.map(\.device.deviceID) == [MeAILimitsTests.macA],
                "전제: 값을 비운 맥은 묶음이 서지 않는다")
        #expect(quiet.aiLimits.roster.map(\.deviceID) == [MeAILimitsTests.macB, MeAILimitsTests.macA],
                "명부가 숨긴 맥을 잊었다 — 그러면 '고른 맥이 조용하다'를 계산할 재료가 없다")
        #expect(quiet.aiLimits.settingsMainDevice?.deviceID == MeAILimitsTests.macB,
                "설정 칩이 가리키는 맥을 폰이 다르게 계산한다 — 두 표면이 같은 입력을 보지 않는다")
        #expect(quiet.aiLimits.isShowingSubstituteDevice,
                "고른 맥 대신 다른 맥을 그리면서 그 사실을 말하지 않는다 — 사용자는 고르기가 안 먹혔다고 읽는다")
        #expect(quiet.aiLimits.showsDeviceNames,
                "다른 맥을 그리는데 머리글에 그 맥 이름이 안 적힌다 — 남의 숫자를 자기가 고른 맥 것으로 읽는다")
        let quietPanel = try #require(quiet.aiLimits.widgetPanel())
        #expect(quietPanel.deviceName == "예성의 MacBook Pro",
                "위젯 머리에 이름이 안 실렸다 — 위젯이 말할 수 있는 유일한 한마디가 빠졌다")
        #expect(quietPanel.providers.first?.fiveHourPercent == 27, "전제: 실린 숫자는 macA 것이다")
        MeAILimitsTests.expectNoPrefsWrites(silent)

        // ② 같은 행 묶음, **고른 맥만 macA** → 그리는 맥이 곧 고른 맥이라 아무 말도 하지 않는다.
        let matched = await harness(chosen: MeAILimitsTests.macA)
        defer { matched.tearDown() }
        let same = matched.me
        same.appDidBecomeActive()
        #expect(await baseWaitUntil { same.aiLimits.state.hasLoaded })

        #expect(same.aiLimits.displayGroups.map(\.device.deviceID) == [MeAILimitsTests.macA],
                "기준선이 다른 그림을 그린다 — 두 갈래의 차이가 '고른 맥' 하나여야 한다")
        #expect(!same.aiLimits.isShowingSubstituteDevice, "고른 맥을 그리면서 '다른 맥을 보여 준다'고 말한다")
        #expect(!same.aiLimits.showsDeviceNames,
                "맥 한 대를 그리는데 이름을 적는다 — 혼자 쓰는 사람에게 군더더기를 보이지 않는 것이 사용자 결정이다")
        #expect(same.aiLimits.widgetPanel()?.deviceName == nil, "위젯 머리에 쓸데없는 이름이 붙었다")
    }

    /// 고른 맥이 **3일 넘게 조용한**(유령) 경우도 같은 길이다. 비운 행과 유령은 뜻이 다르지만(설정 off vs 꺼 둔 맥)
    /// 화면에서 할 말은 같다 — 둘을 가르지 않는 근거는 `AILimitSurfaceText` 머리말이다.
    @Test("고른 맥이 3일째 조용해도 같다: 이름 + 대체 안내 · 숨긴 맥까지 명부에 남는다")
    func aGhostChosenMacTakesTheSamePath() async throws {
        let rows = #"""
        [
          {"device_id":"mac-a-7f21","device_label":"예성의 MacBook Pro",
           "provider":"claude","five_hour_percent":27,"five_hour_resets_at":"2026-09-17T07:40:00+00:00",
           "weekly_percent":60,"weekly_resets_at":"2026-09-22T10:05:00+00:00","plan_label":"max","observed_at":"2026-09-17T05:03:00+00:00"},
          {"device_id":"mac-b-3c90","device_label":"사무실 iMac",
           "provider":"claude","five_hour_percent":91,"five_hour_resets_at":"2026-09-13T07:40:00+00:00",
           "weekly_percent":44,"weekly_resets_at":"2026-09-18T10:05:00+00:00","plan_label":"max","observed_at":"2026-09-13T05:00:00+00:00"}
        ]
        """#
        let harness = await RankMeHarness(label: "me-dev-ghost-chosen") { request in
            if request.path == "/rest/v1/ai_limits", request.method == "GET" { return .json(rows) }
            if request.path == "/rest/v1/ai_limits_prefs", request.method == "GET" {
                return .json(#"[{"main_device_id":"\#(MeAILimitsTests.macB)"}]"#)
            }
            return MeStoreTests.rootResponder(request)
        }
        defer { harness.tearDown() }
        let store = harness.me
        store.appDidBecomeActive()
        #expect(await baseWaitUntil { store.aiLimits.state.hasLoaded })

        #expect(store.aiLimits.displayGroups.map(\.device.deviceID) == [MeAILimitsTests.macA],
                "전제: 3일 넘게 조용한 맥은 묶음이 서지 않는다")
        #expect(store.aiLimits.roster.count == 2, "명부가 유령 행을 걸러 냈다 — 걸러 내면 그 맥은 없었던 것이 된다")
        #expect(store.aiLimits.isShowingSubstituteDevice && store.aiLimits.showsDeviceNames)
        #expect(store.aiLimits.widgetPanel()?.deviceName == "예성의 MacBook Pro")
    }

    /// ★ **안 골랐는데** 가장 최근에 일한 맥이 조용한 경우. 설정 칩은 그 맥에 불이 들어와 있고(같은 규칙이
    /// 접어 준다) 폰은 다른 맥을 그린다 — 고른 적이 없어도 **두 표면이 갈리는 것은 똑같다**.
    @Test("안 골랐어도: 설정 칩이 가리키는 맥을 못 그리면 이름을 적고 대체 사실을 말한다")
    func anUnchosenButSilentDefaultIsAlsoAnnounced() async throws {
        let rows = #"""
        [
          {"device_id":"mac-a-7f21","device_label":"예성의 MacBook Pro",
           "provider":"claude","five_hour_percent":27,"five_hour_resets_at":"2026-09-17T07:40:00+00:00",
           "weekly_percent":60,"weekly_resets_at":"2026-09-22T10:05:00+00:00","plan_label":"max","observed_at":"2026-09-17T05:00:00+00:00"},
          {"device_id":"mac-b-3c90","device_label":"사무실 iMac",
           "provider":"claude","five_hour_percent":null,"five_hour_resets_at":null,
           "weekly_percent":null,"weekly_resets_at":null,"plan_label":null,"observed_at":"2026-09-17T05:04:00+00:00"}
        ]
        """#
        let harness = await RankMeHarness(label: "me-dev-unchosen-silent") { request in
            if request.path == "/rest/v1/ai_limits", request.method == "GET" { return .json(rows) }
            return MeAILimitsTests.responder(request)   // prefs 는 빈 배열(= 한 번도 안 골랐다)
        }
        defer { harness.tearDown() }
        let store = harness.me
        store.appDidBecomeActive()
        #expect(await baseWaitUntil { store.aiLimits.state.hasLoaded })

        #expect(store.aiLimits.mainDeviceID == nil, "전제: 한 번도 고르지 않았다")
        #expect(store.aiLimits.settingsMainDevice?.deviceID == MeAILimitsTests.macB,
                "전제: 맥 설정의 칩은 가장 최근에 일한 맥(조용한 쪽)에 불이 들어와 있다")
        #expect(store.aiLimits.displayGroups.map(\.device.deviceID) == [MeAILimitsTests.macA])
        #expect(store.aiLimits.isShowingSubstituteDevice,
                "안 골랐다는 이유로 조용히 다른 맥을 그린다 — 설정 창과 폰이 다른 맥을 가리킨다")
        #expect(store.aiLimits.showsDeviceNames)
    }

    /// 맥이 **한 대뿐인 사람**은 이 장치에 걸리지 않는다(그 한 대가 곧 그가 아는 맥이다).
    /// 그리고 로그아웃하면 명부도 비운다 — 남으면 다음 사람의 카드가 앞 사람의 맥 이야기를 한다.
    @Test("한 대뿐이면 아무 말도 안 한다 · reset 이 명부를 비운다")
    func oneMacSaysNothingAndResetForgetsTheRoster() async throws {
        let single = #"""
        [
          {"device_id":"only-mac-1","device_label":"Mac mini",
           "provider":"claude","five_hour_percent":27,"five_hour_resets_at":null,
           "weekly_percent":60,"weekly_resets_at":null,"plan_label":"max","observed_at":"2026-09-17T05:03:00+00:00"}
        ]
        """#
        let harness = await RankMeHarness(label: "me-dev-one-silent") { request in
            if request.path == "/rest/v1/ai_limits", request.method == "GET" { return .json(single) }
            return MeStoreTests.rootResponder(request)
        }
        defer { harness.tearDown() }
        let store = harness.me
        store.appDidBecomeActive()
        #expect(await baseWaitUntil { store.aiLimits.state.hasLoaded })

        #expect(store.aiLimits.roster.map(\.deviceID) == ["only-mac-1"])
        #expect(!store.aiLimits.isShowingSubstituteDevice, "한 대뿐인데 '다른 맥을 보여 준다'고 말한다")
        #expect(!store.aiLimits.showsDeviceNames)

        store.aiLimits.reset()
        #expect(store.aiLimits.roster.isEmpty, "로그아웃 뒤에도 앞 사람의 맥 명부가 남는다")
        #expect(!store.aiLimits.isShowingSubstituteDevice, "묶음이 없는데 대체했다고 말한다")
    }

    /// 그릴 묶음이 **하나도 없으면** 대체한 것이 없다(빈 상태 안내가 그 자리를 쥔다 — 두 말이 겹치지 않게).
    @Test("전부 조용하면 대체 안내를 띄우지 않는다(빈 상태 안내와 두 말이 겹치지 않게)")
    func nothingToDrawMeansNothingWasSubstituted() async throws {
        let rows = #"""
        [
          {"device_id":"mac-a-7f21","device_label":"예성의 MacBook Pro",
           "provider":"claude","five_hour_percent":null,"five_hour_resets_at":null,
           "weekly_percent":null,"weekly_resets_at":null,"plan_label":null,"observed_at":"2026-09-17T05:03:00+00:00"},
          {"device_id":"mac-b-3c90","device_label":"사무실 iMac",
           "provider":"claude","five_hour_percent":null,"five_hour_resets_at":null,
           "weekly_percent":null,"weekly_resets_at":null,"plan_label":null,"observed_at":"2026-09-17T05:04:00+00:00"}
        ]
        """#
        let harness = await RankMeHarness(label: "me-dev-all-silent") { request in
            if request.path == "/rest/v1/ai_limits", request.method == "GET" { return .json(rows) }
            return MeAILimitsTests.responder(request)
        }
        defer { harness.tearDown() }
        let store = harness.me
        store.appDidBecomeActive()
        #expect(await baseWaitUntil { store.aiLimits.state.hasLoaded })

        #expect(store.aiLimits.displayGroups.isEmpty, "전제: 그릴 묶음이 없다")
        #expect(store.aiLimits.roster.count == 2, "전제: 명부에는 두 대가 있다(걸러진 쪽이 아니다)")
        #expect(!store.aiLimits.isShowingSubstituteDevice, "그릴 것이 없는데 '다른 맥을 보여 주고 있다'고 말한다")
        #expect(!store.aiLimits.showsDeviceNames)
    }

    // MARK: - 서버 읽기

    /// 귀속 없는 행은 버린다. 화면의 묶음 단위가 기기이므로 둘 곳이 없고, 억지로 한 묶음에 몰면 그게 바로
    /// 0.3.46 의 결함(맥들을 섞기)이다. 서버에서는 PK 칸이라 NOT NULL 이므로 응답이 망가진 경우뿐이다.
    @Test("device_id 가 빈 행은 버린다(한 묶음으로 몰지 않는다) · 나머지 행은 산다")
    func rowsWithoutADeviceAreDropped() async throws {
        let broken = #"""
        [
          {"device_id":null,"device_label":null,
           "provider":"claude","five_hour_percent":99,"five_hour_resets_at":null,
           "weekly_percent":99,"weekly_resets_at":null,"plan_label":null,"observed_at":"2026-09-17T05:04:00+00:00"},
          {"device_id":"   ","device_label":"공백 맥",
           "provider":"codex","five_hour_percent":88,"five_hour_resets_at":null,
           "weekly_percent":88,"weekly_resets_at":null,"plan_label":null,"observed_at":"2026-09-17T05:04:00+00:00"},
          {"device_id":"good-mac-1","device_label":"Mac mini",
           "provider":"claude","five_hour_percent":27,"five_hour_resets_at":null,
           "weekly_percent":60,"weekly_resets_at":null,"plan_label":"max","observed_at":"2026-09-17T05:03:00+00:00"}
        ]
        """#
        let harness = await RankMeHarness(label: "me-dev-nodevice") { request in
            if request.path == "/rest/v1/ai_limits", request.method == "GET" { return .json(broken) }
            return MeStoreTests.rootResponder(request)
        }
        defer { harness.tearDown() }
        let store = harness.me
        store.appDidBecomeActive()
        #expect(await baseWaitUntil { store.aiLimits.state.hasLoaded })

        #expect(store.aiLimits.displayGroups.map(\.device.deviceID) == ["good-mac-1"],
                "귀속 없는 행이 묶음을 얻었다(\(store.aiLimits.displayGroups.map(\.device.deviceID)))")
        #expect(store.aiLimits.displayRows.map(\.provider) == [.claude], "귀속 없는 행의 숫자가 카드에 섞였다")
        #expect(!store.aiLimits.showsDeviceNames, "그릴 맥이 하나인데 이름을 그린다")
    }

    /// ★ **보이스오버가 어느 맥인지 말하는가.** 보이스오버는 한 줄씩 읽으므로, 묶음 머리글을 지나쳐 세 번째 줄에
    /// 바로 닿은 사람에게 "Claude 5시간 91%" 는 **어느 맥인지 말하지 않는다** — 이 기능이 고치려던 거짓이
    /// 소리에만 남는다. 뷰는 `#if os(iOS)` 라 맥 스위트가 재지 못하므로 문장 만들기를 뷰 밖에 뒀다.
    @Test("줄 보이스오버: 기기 이름이 **맨 앞** · 맥 한 대면 안 들어간다 · 없는 창도 말한다")
    func theSpokenRowSaysWhichMacItBelongsTo() throws {
        let base = Self.now
        let groups = AILimitsStore.displayGroups(
            from: AILimitsStore.groups(
                from: [Self.row("mac-a", label: "예성의 MacBook Pro", fiveHour: 27, weekly: 60, ago: 60),
                       Self.row("mac-b", label: "사무실 iMac", fiveHour: nil, weekly: 44, ago: 600)],
                now: base
            ),
            now: base
        )
        let second = try #require(groups.last)
        let row = try #require(second.rows.first)

        // 맥이 둘 → 이름이 **맨 앞**이다(뒤에 붙으면 숫자를 다 들은 뒤에야 주인이 나온다).
        let spoken = MeText.aiLimitRowAccessibility(deviceName: second.name, row: row)
        #expect(spoken.hasPrefix("사무실 iMac, "), "줄을 하나만 들은 사람이 어느 맥인지 모른다(\(spoken))")
        #expect(spoken.contains(row.provider.displayName) && spoken.contains("44%"))
        // 없는 창도 말한다(화면의 `없음` 글자를 그대로 읽는다 — 보는 사람과 듣는 사람이 다른 사실을 받지 않게).
        #expect(spoken.contains(AILimitColumnText.absentValueText), "없는 창을 소리에서 지웠다")
        // 맥 한 대 → 이름이 **안 들어간다**(군더더기를 소리로도 보이지 않는다).
        let alone = MeText.aiLimitRowAccessibility(deviceName: nil, row: row)
        #expect(!alone.contains("사무실 iMac") && alone.hasPrefix(row.provider.displayName))
        #expect(alone != spoken, "기준선이 같다 — 이 단언은 아무것도 재지 못한다")
    }

    // MARK: - 폰 카드 소스 계약 · 가로 예산 (뷰는 `#if os(iOS)` 라 맥 스위트가 한 줄도 컴파일하지 않는다)

    /// ★ 뷰가 **스토어의 묶음**을 그리고, 열 머리는 **카드당 한 번**인지 소스로 되묻는다.
    /// 값으로 재는 위의 단언들과 짝이다 — 그쪽은 "스토어가 맞는 값을 내는가", 여기는 "뷰가 그 값을 쓰는가".
    @Test("카드 소스 계약: 묶음으로 돌고 · 묶음마다 머리글 · 열 머리는 **한 번만** · 1대면 이름 줄이 안 선다")
    func cardDrawsGroupsAndKeepsOneColumnHeader() throws {
        let card = try IntegrationContractTests.code("Sources/CheckMobileKit/Me/MeAILimitsCard.swift")
        #expect(card.contains("limits.displayGroups"), "카드가 기기 묶음을 안 쓴다 — 접힌 목록을 그린다")
        #expect(card.contains("limits.showsDeviceNames"), "카드가 1대/2대 분기를 스토어에 묻지 않는다")
        #expect(card.contains("deviceNameRow("), "묶음 머리글을 그리지 않는다")
        // ★ 묶음 **경계에 선이 있다**. 없으면 두 맥의 줄이 맞붙어 한 표처럼 읽히고(승인된 문법 ④가 화면에서
        //   사라진다), 1px 이라 렌더 높이로는 잡히지 않는다 — 그래서 소스로 잰다.
        #expect(card.contains("if groupIndex > 0 { rowSeparator }"),
                "묶음 경계에 구분선이 없다 — 두 맥의 줄이 맞붙어 한 묶음처럼 읽힌다")
        // ★ 열 머리는 **한 번만 세운다**: 호출이 하나뿐이고, 그 호출이 묶음 `ForEach` **밖**에 있다.
        #expect(card.components(separatedBy: "columnHeaderRow").count - 1 == 2,
                "열 머리 줄의 정의+호출이 한 쌍이 아니다 — 묶음마다 되풀이하기 시작했다(세로 길이가 그만큼 늘어난다)")
        let tableBody = try #require(card.range(of: "VStack(spacing: 0) {\n            columnHeaderRow"),
                                     "열 머리가 묶음 ForEach 안으로 들어갔다")
        #expect(!tableBody.isEmpty)
        // 뷰가 숫자·이름을 **다시 계산하지 않는다**(규칙이 둘이 되는 자리).
        for banned in ["displayNames(", "AILimitMainDeviceRule", "shortTail("] {
            #expect(!card.contains(banned), "카드가 기기 이름·메인 맥 규칙을 자기 손으로 다시 만든다(\(banned))")
        }
        // 1대일 때 이름 줄이 서지 않는 길이 **값으로** 막혀 있다(기본값 false).
        #expect(card.contains("var showsDeviceNames: Bool = false"),
                "묶음 머리글이 기본으로 켜져 있다 — 혼자 쓰는 사람의 카드가 바뀐다")
        // 줄 라벨도 **뷰 밖**에서 만든다(순서·누락을 맥 스위트가 값으로 잴 수 있는 자리에).
        #expect(card.contains("MeText.aiLimitRowAccessibility(deviceName: deviceName, row: row)"),
                "줄 보이스오버 문장을 뷰가 직접 이어 붙인다 — 맥 스위트가 그 순서를 못 잰다")
        #expect(!card.contains("private var label: String"), "뷰에 라벨 계산이 남았다 — 규칙이 둘이 된다")
    }

    /// ★ 묶음 머리글이 **가장 좁은 기기에서도 한 줄에 드는가**(글자수로 재면 안 된다 — 한글 12pt ≈ 13pt,
    /// 라틴 소문자 ≈ 7pt). 넘치면 두 줄로 접히는 것이 설계이지만, **현실적인 가장 넓은 이름**은 한 줄에 들어야
    /// 카드의 세로가 기기 수에 비례해서만 자란다.
    @Test("기기 머리글 폭: 겹침 꼬리까지 붙은 가장 넓은 이름이 375pt 기기에서도 한 줄에 든다")
    func deviceNameRowFitsOneLineEvenOnTheNarrowestPhone() throws {
        func width(_ text: String) -> CGFloat {
            MeAILimitsTests.width(text, size: MeAILimitCardBudget.deviceNameFontSize, weight: .semibold,
                                  monospacedDigits: false)
        }
        // 상수의 실측값을 **다시 재서** 되묻는다(글꼴이 바뀌면 여기서 빨개진다).
        let worst = width("예성의 MacBook Pro (A1B2)")
        #expect(abs(worst - MeAILimitCardBudget.worstDeviceNameWidth) < 1.5,
                "가장 넓은 머리글 실측이 \(worst)pt 인데 상수는 \(MeAILimitCardBudget.worstDeviceNameWidth)pt 다")
        for screen in [MeAILimitCardBudget.narrowestScreenWidth, MeAILimitCardBudget.referenceScreenWidth] {
            #expect(MeAILimitCardBudget.deviceNameFitsOneLine(worst, screenWidth: screen),
                    "\(screen)pt 기기에서 머리글이 두 줄로 접힌다(자리 \(MeAILimitCardBudget.innerWidth(screenWidth: screen))pt)")
            for name in ["Mac mini", "사무실 iMac", "예성의 MacBook Pro", "이름 모를 맥 A1B2"] {
                #expect(MeAILimitCardBudget.deviceNameFitsOneLine(width(name), screenWidth: screen),
                        "\(screen)pt 기기에서 `\(name)` 이 한 줄에 안 든다")
            }
        }
        // ★ 머리글은 제공자 이름보다 **조용하다**(같은 굵기·같은 크기면 네 번째 제공자 줄처럼 읽힌다).
        #expect(MeAILimitCardBudget.deviceNameFontSize < MeAILimitCardBudget.nameFontSize,
                "묶음 머리글이 제공자 이름만큼 크다 — 구획이 데이터처럼 보인다")
    }

    /// ★★ **상한 길이 이름 두 대**에서 꼬리가 살아남는가 (v0.3.47 P2).
    ///
    /// ## 그물이 없던 까닭
    /// 기존 폭 테스트는 '가장 넓은 현실적인 이름'을 `예성의 MacBook Pro (A1B2)`(24자)로 잡았고, 그 이름은 한 줄에
    /// 든다. 그래서 "두 줄로 접힌다"는 설계가 **참인 구간만** 재고 있었다. `device_label` 상한은 **64 스칼라**이고
    /// 한글 64자는 두 줄에도 들지 않는다 — 그 구간에서 말줄임이 **뒤**를 먹고, 거기가 바로 겹침을 가르는 꼬리
    /// 자리였다(두 머리글이 글자 그대로 똑같아진다).
    ///
    /// ## 여기서 재는 것
    /// ① 상한 길이 이름은 **정말로** 두 줄을 넘긴다(= 말줄임이 난다 — 전제가 참이어야 이 그물이 뜻을 갖는다).
    /// ② 그런데 꼬리는 **그 어떤 이름 앞에서도** 자리를 갖는다(`fixedSize` + `layoutPriority` 가 그 뜻이다).
    /// ③ 그래서 두 묶음의 **꼬리가 서로 다르다** = 사람이 두 머리글을 가를 수 있다.
    /// (뷰 자체는 `#if os(iOS)` 라 맥 스위트가 한 줄도 컴파일하지 않는다 — 그림으로 보는 그물은 `ImageRenderer`
    ///  카탈로그의 `card-twin-long-names` 다. 여기서는 그 배치가 성립할 **조건**을 값으로 못 박는다.)
    @Test("상한 길이 쌍둥이: 이름은 잘려도 꼬리는 남는다 — 두 머리글이 다르게 보인다")
    func theTailSurvivesEvenWhenTwoMaximumLengthNamesAreIdentical() throws {
        func width(_ text: String) -> CGFloat {
            MeAILimitsTests.width(text, size: MeAILimitCardBudget.deviceNameFontSize, weight: .semibold,
                                  monospacedDigits: false)
        }
        // 꼬리 글자의 실측값을 **다시 재서** 되묻는다(글꼴이 바뀌면 여기서 빨개진다). 상수는 **가장 넓은** 꼬리다 —
        // 꼬리 글자 수는 고정(4자)이고 폭만 글리프에 따라 다르므로, 좁은 쪽을 들면 자리 계산이 과대평가된다.
        let widestTail = width(AILimitDeviceNameParts.tailText("WWWW"))
        #expect(abs(widestTail - MeAILimitCardBudget.worstDeviceTailWidth) < 1.5,
                "가장 넓은 꼬리 실측이 \(widestTail)pt 인데 상수는 \(MeAILimitCardBudget.worstDeviceTailWidth)pt 다")
        #expect(width(AILimitDeviceNameParts.tailText("A1B2")) <= widestTail + 0.01,
                "현실적인 꼬리가 '가장 넓은 꼬리'보다 넓다 — 상한을 잘못 잡았다")

        let maxName = String(repeating: "가", count: AILimitDeviceLabelContract.maxScalars)
        // ★ 초안이 그렸던 **합친 글자**로 전제를 잰다(그게 잘리던 글자다). 꼬리까지 붙으면 두 줄을 확실히 넘는다.
        let combinedWidth = width(AILimitDeviceNameParts(base: maxName, tail: "A1B2").combined)
        for screen in [MeAILimitCardBudget.narrowestScreenWidth, MeAILimitCardBudget.referenceScreenWidth] {
            // ① 전제: 합쳐 적으면 두 줄에도 안 든다 = 말줄임이 **뒤**(꼬리 자리)를 먹는다.
            #expect(MeAILimitCardBudget.deviceNameOverflowsTwoLines(combinedWidth, screenWidth: screen),
                    "\(screen)pt 기기에서 상한 길이 쌍둥이 머리글 \(combinedWidth)pt 가 두 줄에 든다 — 이 그물이 재는 구간이 사라졌다")
            #expect(!MeAILimitCardBudget.deviceNameFitsOneLine(combinedWidth, screenWidth: screen))
            // ② 그런데 꼬리는 **따로 서므로** 제 자리를 갖는다(이름이 아무리 길어도).
            #expect(MeAILimitCardBudget.deviceTailAlwaysFits(widestTail, screenWidth: screen),
                    "\(screen)pt 기기에서 꼬리가 들어갈 자리가 없다 — 긴 이름 앞에서 꼬리가 눌린다")
        }

        // ③ 두 묶음의 꼬리가 다르다 = 머리글이 가려진다. 스토어가 내놓는 **조각**으로 잰다.
        let base = Self.now
        let groups = AILimitsStore.displayGroups(
            from: AILimitsStore.groups(
                from: [Self.row("twin-aaaa-a1b2", label: maxName, ago: 60),
                       Self.row("twin-bbbb-c3d4", label: maxName, ago: 600)],
                now: base
            ),
            now: base
        )
        #expect(groups.count == 2, "전제: 같은 이름 두 대가 둘 다 그려진다")
        let first = try #require(groups.first), second = try #require(groups.last)
        #expect(first.nameParts.base == second.nameParts.base, "전제: 두 맥의 이름 글자가 같다")
        #expect(first.nameParts.tail == "A1B2" && second.nameParts.tail == "C3D4",
                "상한 길이 쌍둥이에서 꼬리가 사라졌다 — 두 머리글을 가를 글자가 없다")
        #expect(first.nameParts.tail != second.nameParts.tail)
        // 보이스오버는 합친 글자를 듣는다(소리에는 잘릴 자리가 없다).
        #expect(first.name != second.name && first.name.hasSuffix("(A1B2)"))
    }

    /// 카드 소스 계약 — **꼬리가 말줄임에 먹히지 않는 자리에 있고**, 대체 안내가 표 앞에 선다(v0.3.47 P1·P2).
    ///
    /// 값으로 재는 위의 단언들과 짝이다: 그쪽은 "스토어가 조각을 내놓는가", 여기는 "뷰가 그 조각을 **따로**
    /// 그리는가". 뷰는 `#if os(iOS)` 라 맥 스위트가 한 줄도 컴파일하지 않아서, 이 두 자리는 글자로만 잴 수 있다.
    @Test("카드 소스 계약: 이름만 잘리고 꼬리는 fixedSize · 대체 안내는 표 **앞** · 안내 글자는 공유 상수")
    func cardKeepsTheTailAndTellsAboutSubstitution() throws {
        let card = try IntegrationContractTests.code("Sources/CheckMobileKit/Me/MeAILimitsCard.swift")
        // 머리글이 **조각**을 받는다(합친 글자를 받으면 자르는 글자와 가르는 글자가 한 덩어리다).
        #expect(card.contains("deviceNameRow(group.nameParts, isFirst: groupIndex == 0)"),
                "머리글이 조각을 안 받는다 — 꼬리가 말줄임이 먹는 자리로 돌아갔다")
        let header = try #require(card.range(of: "private func deviceNameRow(_ parts: AILimitDeviceNameParts"))
        let headerBody = String(card[header.upperBound...].prefix(900))
        #expect(headerBody.contains("Text(parts.base)"), "이름을 조각으로 그리지 않는다")
        #expect(headerBody.contains("Text(AILimitDeviceNameParts.tailText(tail))"), "꼬리를 따로 그리지 않는다")
        // ★ 꼬리는 **줄지 않고 먼저** 자리를 받는다. 둘 중 하나만 있으면 긴 이름 앞에서 꼬리가 눌리거나 `…` 가 된다.
        let tailText = try #require(headerBody.range(of: "Text(AILimitDeviceNameParts.tailText(tail))"))
        let tailBlock = String(headerBody[tailText.upperBound...].prefix(260))
        #expect(tailBlock.contains(".fixedSize()"), "꼬리가 줄어들 수 있다")
        #expect(tailBlock.contains(".layoutPriority(1)"), "꼬리가 이름보다 나중에 자리를 받는다")
        // 말줄임이 나는 쪽은 **이름뿐**이다(꼬리에 truncationMode 가 붙으면 그 자리가 잘리는 자리가 된다).
        let nameText = try #require(headerBody.range(of: "Text(parts.base)"))
        let nameBlock = String(headerBody[nameText.upperBound...].prefix(160))
        #expect(nameBlock.contains(".lineLimit(2)") && nameBlock.contains(".truncationMode(.tail)"),
                "이름의 두 줄 접기·말줄임이 사라졌다")

        // 대체 안내: 표 **앞**이고(숫자를 다 본 뒤면 늦다), 글자는 공유 상수에서 온다.
        #expect(card.contains("if limits.isShowingSubstituteDevice { substituteDeviceLine }"),
                "대체 사실을 말하는 줄이 없다 — 고르기가 안 먹혔다고 읽는 바로 그 자리다")
        let line = try #require(card.range(of: "if limits.isShowingSubstituteDevice { substituteDeviceLine }"))
        let table = try #require(card.range(of: "table(groups, showsDeviceNames: limits.showsDeviceNames)"))
        #expect(line.lowerBound < table.lowerBound, "대체 안내가 표 뒤에 있다 — 숫자를 다 읽은 뒤에 설명이 온다")
        #expect(card.contains("Text(MeText.aiLimitsSubstitutedDevice)"), "안내 문장을 뷰가 직접 적는다")
        #expect(MeText.aiLimitsSubstitutedDevice == AILimitSurfaceText.substitutedMainDevice,
                "폰 글자와 공유 상수가 갈렸다")
        #expect(!MeText.aiLimitsSubstitutedDevice.isEmpty)
        // 뷰는 **기기 이름 규칙을 다시 만들지 않는다**(기존 계약 그대로 — 조각을 쓰는 것도 스토어가 준 값이다).
        for banned in ["displayNameParts(", "displayNames(", "AILimitMainDeviceRule", "shortTail("] {
            #expect(!card.contains(banned), "카드가 기기 이름·메인 맥 규칙을 자기 손으로 다시 만든다(\(banned))")
        }
    }
}

// MARK: - 위젯 쪽

@MainActor
@Suite("위젯 AI 리밋 — 기기 축(v0.3.47)")
struct WidgetAILimitDeviceTests {
    nonisolated static let now = MobileClock.demoInstant

    nonisolated static func snapshot(_ panel: WidgetSnapshot.AILimitPanel?) -> WidgetSnapshot {
        WidgetSnapshot(
            generatedAt: now.addingTimeInterval(-30),
            me: .init(working: true, sessionStartedAt: now.addingTimeInterval(-3_600), todaySeconds: 3_600,
                      weekSeconds: 7_200, goalHours: 40, status: .working),
            aiLimits: panel
        )
    }

    nonisolated static func panel(deviceName: String?) -> WidgetSnapshot.AILimitPanel {
        WidgetSnapshot.AILimitPanel(
            providers: [
                .init(provider: "claude", fiveHourPercent: 27, fiveHourResetsAt: now.addingTimeInterval(9_000),
                      weeklyPercent: 60, weeklyResetsAt: now.addingTimeInterval(450_000),
                      observedAt: now.addingTimeInterval(-30)),
            ],
            deviceName: deviceName,
            todayTokens: 12_345_678,
            recentTokens: 19_658_964_272
        )
    }

    /// ★ **생 JSON** 으로 잰다. 멤버와이즈 왕복만 두면 `AILimitPanel.init(from:)` 의 디코드 줄이 빠져도 초록이고
    /// (인코드는 합성이라 파일에는 값이 들어간다), 그 결함의 증상은 "위젯 머리에 맥 이름이 안 뜬다" 하나뿐이다.
    @Test("스냅샷 칸: 맥 이름이 파일에 실리고 생 JSON 에서 그대로 돌아온다 · 옛 파일은 nil · 판은 1 그대로")
    func deviceNameSurvivesTheFile() throws {
        let snapshot = Self.snapshot(Self.panel(deviceName: "예성의 MacBook Pro"))
        let data = try WidgetSnapshotCodec.encode(snapshot)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains(#""deviceName":"예성의 MacBook Pro""#), "맥 이름이 파일에 안 실렸다")
        #expect(text.contains(#""version":1"#), "판을 올렸다 — 더하기만 한 옵셔널 칸이다")
        #expect(try #require(WidgetSnapshotCodec.decode(data)) == snapshot)

        // 생 JSON(손으로 쓴 파일) — 디코드 줄이 빠지면 **여기서만** 빨갛다.
        let json = #"""
        {"version":1,"generatedAt":1789621500000,
         "aiLimits":{"providers":[{"provider":"claude","weeklyPercent":60,"observedAt":1789621470000}],
          "deviceName":"사무실 iMac","todayTokens":1}}
        """#
        let decoded = try #require(WidgetSnapshotCodec.decode(Data(json.utf8)))
        #expect(decoded.aiLimits?.deviceName == "사무실 iMac", "디코드 줄이 빠졌다 — 파일에 이름이 있어도 영원히 nil 이다")

        // 옛 스냅샷(칸이 없다) · 빈 문자열 · 공백뿐 → 전부 nil(머리에 빈 `· ` 만 남는 꼴을 막는다).
        for body in [#"{"providers":[]}"#, #"{"providers":[],"deviceName":""}"#, #"{"providers":[],"deviceName":"  "}"#] {
            let old = #"{"version":1,"generatedAt":1789621500000,"aiLimits":\#(body)}"#
            let panel = try #require(WidgetSnapshotCodec.decode(Data(old.utf8))?.aiLimits)
            #expect(panel.deviceName == nil, "빈 이름을 이름으로 받았다(\(body))")
        }
    }

    /// ★ 겹침 꼬리 칸(`deviceNameTail`)도 **생 JSON** 으로 잰다 — 디코드 줄이 빠지면 컴파일은 통과하고 꼬리는 영원히
    /// nil 이라, 위젯 머리가 소리 없이 합친 글자 한 줄로 돌아가 상한 길이 쌍둥이를 다시 못 가른다.
    @Test("스냅샷 칸: 겹침 꼬리가 파일에 실리고 생 JSON 에서 돌아온다 · 옛 파일·빈 값은 nil · 판은 1 그대로")
    func deviceNameTailSurvivesTheFile() throws {
        var panel = Self.panel(deviceName: "Mac mini (A1B2)")
        panel.deviceNameTail = "A1B2"
        let snapshot = Self.snapshot(panel)
        let data = try WidgetSnapshotCodec.encode(snapshot)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains(#""deviceNameTail":"A1B2""#), "꼬리가 파일에 안 실렸다")
        #expect(text.contains(#""version":1"#), "판을 올렸다 — 더하기만 한 옵셔널 칸이다")
        #expect(try #require(WidgetSnapshotCodec.decode(data)) == snapshot)
        // 꼬리가 없으면 칸 자체가 파일에 안 생긴다(옛 위젯·옛 파일과 같은 모양).
        let plain = String(decoding: try WidgetSnapshotCodec.encode(Self.snapshot(Self.panel(deviceName: "사무실 iMac"))),
                           as: UTF8.self)
        #expect(!plain.contains("deviceNameTail"), "겹치지 않는 이름인데 꼬리 칸을 썼다")

        let json = #"""
        {"version":1,"generatedAt":1789621500000,
         "aiLimits":{"providers":[{"provider":"claude","weeklyPercent":60,"observedAt":1789621470000}],
          "deviceName":"Mac mini (C3D4)","deviceNameTail":"C3D4"}}
        """#
        let decoded = try #require(WidgetSnapshotCodec.decode(Data(json.utf8)))
        #expect(decoded.aiLimits?.deviceNameTail == "C3D4", "디코드 줄이 빠졌다 — 파일에 꼬리가 있어도 영원히 nil 이다")
        #expect(decoded.aiLimits?.deviceName == "Mac mini (C3D4)")

        for body in [#"{"providers":[],"deviceName":"Mac mini (A1B2)"}"#,
                     #"{"providers":[],"deviceName":"Mac mini (A1B2)","deviceNameTail":""}"#,
                     #"{"providers":[],"deviceName":"Mac mini (A1B2)","deviceNameTail":"  "}"#] {
            let old = #"{"version":1,"generatedAt":1789621500000,"aiLimits":\#(body)}"#
            let panel = try #require(WidgetSnapshotCodec.decode(Data(old.utf8))?.aiLimits)
            #expect(panel.deviceNameTail == nil, "빈 꼬리를 꼬리로 받았다(\(body))")
            #expect(panel.deviceName == "Mac mini (A1B2)", "꼬리 칸이 이름 칸을 흔들었다(\(body))")
        }
    }

    /// ★ **머리에 이름을 적을지 말지**가 값으로 답해진다. 뷰는 `#if os(iOS)` 라 맥 스위트가 한 줄도 컴파일하지
    /// 않으므로, 그 분기가 뷰 안에 있으면 재는 그물이 소스 grep 하나뿐이고 — grep 은 조건에 `false` 를 더하는
    /// 변형을 **못 잡는다**(실측: 그 변형이 안 물렸다). 그래서 분기의 결과를 `headerDevice` 가 내놓는다.
    @Test("머리 줄 분기: 맥 한 대면 nil · 둘 이상이면 가운뎃점 글자 + **읽어 줄 글자는 이름만**")
    func theHeaderDecidesWithAValueNotInsideTheView() throws {
        func limits(_ name: String?) throws -> AingWidgetLimits {
            guard case .limits(let value) = AingWidgetLimitsState(snapshot: Self.snapshot(Self.panel(deviceName: name)),
                                                                 at: Self.now) else {
                throw WidgetDeviceFailure.notLimits
            }
            return value
        }
        #expect(try limits(nil).headerDevice == nil, "맥 한 대인데 머리에 이름을 적는다 — 군더더기를 보이지 않는 것이 사용자 결정이다")
        let header = try #require(try limits("예성의 MacBook Pro").headerDevice)
        #expect(header.text == "· 예성의 MacBook Pro", "보이는 글자가 제목의 꼬리로 이어지지 않는다")
        #expect(header.spoken == "예성의 MacBook Pro", "보이스오버가 가운뎃점을 이름의 일부로 읽는다")
        #expect(header.text != header.spoken, "보이는 글자와 읽어 줄 글자를 한 글자로 합쳤다")
        #expect(header.tail == nil, "겹치지 않는 이름에 꼬리 조각이 생겼다")
        // 겹침 꼬리가 붙은 이름도 **그대로** 지난다(위젯이 이름을 다시 만들지 않는다).
        #expect(try limits("Mac mini (A1B2)").headerDevice?.spoken == "Mac mini (A1B2)")
    }

    /// ★ 머리 이름이 **두 조각**으로 갈린다(v0.3.47 P2) — 이름(잘려도 되는 쪽)과 겹침 꼬리(절대 안 잘리는 쪽).
    ///
    /// 경계는 폰이 실어 준 꼬리로만 가른다. 기준선을 다르게 둔다: 꼬리 칸이 없는 옛 파일 · 짝이 안 맞는 꼬리 ·
    /// 이름 자체에 괄호가 든 맥은 **가르지 않는다**(위젯이 괄호를 찾아 자르면 그 맥에서 이름을 지어낸다).
    @Test("머리 줄 조각: 꼬리가 실리면 `· 이름` + `(꼬리)` 로 갈리고 · 옛 파일·짝 안 맞는 꼬리·괄호 이름은 안 갈린다")
    func theHeaderSplitsTheTailOnlyWhenThePhoneSaysWhereItIs() throws {
        func header(_ name: String?, tail: String?) throws -> AingWidgetLimitsHeaderDevice? {
            var panel = Self.panel(deviceName: name)
            panel.deviceNameTail = tail
            guard case .limits(let value) = AingWidgetLimitsState(snapshot: Self.snapshot(panel), at: Self.now) else {
                throw WidgetDeviceFailure.notLimits
            }
            return value.headerDevice
        }
        let twin = try #require(try header("Mac mini (A1B2)", tail: "A1B2"))
        #expect(twin.name == "· Mac mini", "꼬리가 이름 조각에 남았다 — 말줄임이 그 꼬리를 먹는다")
        #expect(twin.tail == "(A1B2)", "꼬리 조각이 없다 — 쌍둥이를 가를 글자가 잘리는 자리에 있다")
        #expect(twin.spoken == "Mac mini (A1B2)", "보이스오버가 꼬리를 못 듣는다")
        #expect(twin.text == "· Mac mini (A1B2)", "두 조각을 합치면 예전 머리 글자와 같아야 한다")

        // 옛 파일(꼬리 칸 없음): 지금까지처럼 합친 글자 하나.
        let old = try #require(try header("Mac mini (A1B2)", tail: nil))
        #expect(old.name == "· Mac mini (A1B2)" && old.tail == nil)
        // 짝이 안 맞는 꼬리: 가르지 않는다(꼬리를 두 번 적거나 이름을 잘라 먹지 않는다).
        let mismatch = try #require(try header("Mac mini (A1B2)", tail: "ZZZZ"))
        #expect(mismatch.name == "· Mac mini (A1B2)" && mismatch.tail == nil, "짝이 안 맞는 꼬리로 이름을 갈랐다")
        // 이름 자체에 괄호가 든 맥: 꼬리가 없으면 그대로다(위젯이 괄호를 찾아 자르지 않는다).
        let paren = try #require(try header("Studio (Office)", tail: nil))
        #expect(paren.name == "· Studio (Office)" && paren.tail == nil, "꼬리가 없는데 괄호를 꼬리로 잘랐다")
        // 맥 한 대: 꼬리 칸이 있어도 이름이 없으면 아무것도 안 적는다.
        #expect(try header(nil, tail: "A1B2") == nil, "맥 한 대인데 꼬리만 적었다")
    }

    /// 위젯 모델이 그 이름을 **그대로** 들고 온다(위젯은 이름을 만들지 않는다 — 겹침을 가른 글자가 이미 들어 있다).
    @Test("모델: 패널의 맥 이름이 그대로 오고, 없으면 nil 이다(위젯이 이름을 지어내지 않는다)")
    func theModelCarriesTheNameAsIs() throws {
        guard case .limits(let named) = AingWidgetLimitsState(snapshot: Self.snapshot(Self.panel(deviceName: "Mac mini (A1B2)")),
                                                             at: Self.now) else {
            throw WidgetDeviceFailure.notLimits
        }
        #expect(named.deviceName == "Mac mini (A1B2)")
        guard case .limits(let plain) = AingWidgetLimitsState(snapshot: Self.snapshot(Self.panel(deviceName: nil)),
                                                             at: Self.now) else {
            throw WidgetDeviceFailure.notLimits
        }
        #expect(plain.deviceName == nil, "맥 한 대인데 이름을 지어냈다")
        #expect(named.rows.map(\.provider) == plain.rows.map(\.provider), "이름 유무가 줄을 흔들었다")
    }

    /// ★ **머리 줄에 기기 이름이 들어갈 자리가 있는가** — 가장 좁은 기기 칸(329×155 → 안쪽 297pt)에서 잰다.
    /// 머리 줄에는 이미 `N분 전` 이 있고 그 글자는 **줄지 않는다**(`fixedSize()`).
    ///
    /// 그리고 **세로 예산이 하나도 안 변했는지** 같이 잰다: 이름을 둘째 줄로 내리면 좁은 기기의 줄 높이가
    /// 마크 하한과 0.2pt 차가 되어 글자를 조금 키운 사람에게서 깨진다. 그래서 머리 줄 안을 골랐고,
    /// 그 선택이 지켜지는지는 "세로가 안 변했다"로 되묻는다.
    @Test("위젯 머리 폭: 맥 이름이 329pt 칸에서도 나이 글자를 밀어내지 않는다 · 세로 예산은 그대로다")
    func headerHasRoomForTheMacName() throws {
        func width(_ text: String, size: Double, weight: NSFont.Weight, mono: Bool = false) -> Double {
            Double(MeAILimitsTests.width(text, size: CGFloat(size), weight: weight, monospacedDigits: mono))
        }
        // 상수의 실측값을 다시 재서 되묻는다.
        let title = width(AingWidgetText.limitsTitle, size: AingWidgetLimitsMediumBudget.titleFontSize, weight: .bold)
        #expect(abs(title - AingWidgetLimitsMediumBudget.measuredTitleWidth) < 1.5,
                "제목 실측이 \(title)pt 인데 상수는 \(AingWidgetLimitsMediumBudget.measuredTitleWidth)pt 다")
        let age = width("12시간 전", size: AingWidgetLimitsMediumBudget.deviceNameFontSize, weight: .regular, mono: true)
        #expect(abs(age - AingWidgetLimitsMediumBudget.worstAgeWidth) < 1.5,
                "나이 글자 실측이 \(age)pt 인데 상수는 \(AingWidgetLimitsMediumBudget.worstAgeWidth)pt 다")
        // 머리에 설 수 있는 모든 나이 글자가 그 상한 안이다(상한을 잘못 잡으면 이름 자리가 과대평가된다).
        for shorter in ["방금", "3분 전", "3시간 전", "4일 전"] {
            #expect(width(shorter, size: AingWidgetLimitsMediumBudget.deviceNameFontSize, weight: .regular, mono: true)
                    <= AingWidgetLimitsMediumBudget.worstAgeWidth + 0.01,
                    "`\(shorter)` 가 가장 넓은 나이 글자보다 넓다 — 이름 자리가 과대평가됐다")
        }

        for (label, size) in [("기준 364×170", AingWidgetLimitsMediumBudget.referenceSize),
                              ("좁은 329×155", AingWidgetLimitsMediumBudget.narrowSize)] {
            let budget = AingWidgetLimitsMediumBudget.family(width: size.width, height: size.height,
                                                            providerCount: 3, hasTokens: true)
            for name in ["Mac mini", "사무실 iMac", "예성의 MacBook Pro", "예성의 MacBook Pro (A1B2)", "이름 모를 맥 A1B2"] {
                let measured = width(name, size: AingWidgetLimitsMediumBudget.deviceNameFontSize, weight: .regular)
                #expect(budget.deviceNameFits(measured),
                        "\(label): `\(name)` \(measured)pt 가 이름 자리 \(budget.deviceNameWidth)pt 를 넘는다")
            }
            // ★ 세로가 **하나도 안 변했다** — 이름은 머리 줄 안에 있고 새 줄을 만들지 않았다.
            #expect(budget.usedHeight <= budget.innerHeight + 0.001,
                    "\(label): 쓰는 높이 \(budget.usedHeight)pt 가 칸 \(budget.innerHeight)pt 를 넘는다")
            #expect(budget.rowFitsMark, "\(label): 줄 높이 \(budget.rowHeight) < 마크 \(budget.markSide)")
            // 그리고 이름 자리가 **양수**다(그 값이 음수면 `deviceNameFits` 가 모든 이름을 거절해야 한다).
            #expect(budget.deviceNameWidth > 0, "\(label): 이름 자리가 음수다")
        }
        // ★ 좁은 칸의 이름 자리는 설계서가 적은 **194.4pt** 다(그 수가 이 선택의 근거였다 — 바뀌면 근거를 다시 쓴다).
        let narrow = AingWidgetLimitsMediumBudget.family(width: AingWidgetLimitsMediumBudget.narrowSize.width,
                                                        height: AingWidgetLimitsMediumBudget.narrowSize.height,
                                                        providerCount: 3, hasTokens: true)
        #expect(abs(narrow.deviceNameWidth - 194.4) < 1.0, "좁은 칸의 이름 자리가 \(narrow.deviceNameWidth)pt 다")
    }

    /// 소스 계약: 위젯이 **머리에 이름을 그리고**, 메인 맥을 **스스로 고르지 않는다**.
    ///
    /// 고르는 규칙과 `ai_limits_prefs` 를 아는 쪽은 앱이다. 위젯이 같은 판단을 따로 하면 두 벌이 갈린 채
    /// 한동안 산다(확장은 앱과 **따로** 갱신된다 — 이 기능이 몇 번이고 밟은 함정).
    @Test("위젯 소스 계약: 머리에 맥 이름을 그린다 · 고르기 규칙·prefs 표를 위젯이 모른다 · 토큰 줄엔 맥 이름이 없다")
    func theWidgetDrawsTheNameButNeverChoosesTheMac() throws {
        let view = try IntegrationContractTests.code("Sources/CheckWidgetsKit/Widgets/AingLimitsWidget.swift")
        let line = try IntegrationContractTests.code("Sources/CheckWidgetsKit/AingWidgetLimitsHeader.swift")
        // ★ **조건 글자까지** 조인다. "`limits.deviceName` 이 파일에 나온다"로만 재면 조건에 `false` 를 더하는
        //   변형을 못 잡는다(실측으로 안 물렸다). 뷰는 값이 준 답을 **그대로** 넘기고 자기 조건을 더하지 않는다.
        //   (머리 줄 자체는 플랫폼 무관 뷰라 `WidgetAILimitHeaderRenderTests` 가 **그림으로** 잰다 — `if let device`
        //    에 `false` 를 더하면 그쪽에서 빨개진다.)
        #expect(view.contains("device: limits.headerDevice,"), "위젯 머리가 값이 준 답을 그대로 넘기지 않는다")
        #expect(view.contains("AingWidgetLimitsHeaderLine("), "위젯이 맥 스위트가 굽는 그 머리 줄을 쓰지 않는다")
        #expect(line.contains("if let device {"), "머리 줄이 값의 답에 자기 조건을 더했다")
        // 이름과 꼬리를 **따로** 그린다 — 꼬리는 `fixedSize` + `layoutPriority`(폰 카드와 같은 수리).
        #expect(line.contains("Text(device.name)") && line.contains("Text(tail)"), "이름과 꼬리를 한 글자로 그린다")
        #expect(!line.contains("Text(device.text)"), "합친 글자를 한 `Text` 로 그린다 — 말줄임이 꼬리부터 먹는다")
        let tailRange = try #require(line.range(of: "Text(tail)"))
        let tailCode = String(line[tailRange.lowerBound...].prefix(200))
        #expect(tailCode.contains(".fixedSize()") && tailCode.contains(".layoutPriority(1)"),
                "꼬리가 제 폭을 먼저 갖지 않는다 — 긴 이름 앞에서 눌리거나 `…` 가 된다")
        #expect(line.contains("accessibilityLabel(Text(device.spoken))"), "보이는 글자와 읽어 줄 글자를 가르지 않는다")
        for code in [view, line] {
            #expect(!code.contains("AingWidgetText.limitsDeviceName("),
                    "뷰가 이름 글자를 다시 꾸민다 — 그 분기는 맥 스위트가 잴 수 있는 자리에 있어야 한다")
            for banned in ["AILimitMainDeviceRule", "ai_limits_prefs", "mainDeviceID", "AILimitDeviceRoster"] {
                #expect(!code.contains(banned), "위젯이 메인 맥을 스스로 고르려 한다(\(banned)) — 앱과 두 벌이 갈린다")
            }
        }
        let model = try IntegrationContractTests.code("Sources/CheckWidgetsKit/AingWidgetModel.swift")
        for banned in ["AILimitMainDeviceRule", "ai_limits_prefs", "AILimitDeviceRoster"] {
            #expect(!model.contains(banned), "위젯 모델이 기기 고르기를 다시 구현한다(\(banned))")
        }
        // 토큰 줄은 **계정 전체의 합**이라 맥 이름을 쓰지 않는다(그 줄에 이름이 붙으면 그 맥의 수로 읽힌다).
        let tokenBlock = try #require(view.range(of: "private func tokenBlock("))
        let tail = String(view[tokenBlock.lowerBound...].prefix(1_200))
        #expect(!tail.contains("deviceName"), "토큰 줄에 맥 이름을 붙였다 — 토큰은 계정 전체의 합이다(합산 유지)")
    }

    /// 미리보기 카탈로그에 **맥 두 대인 사람의 위젯**이 들어 있다(사람이 그 모양을 눈으로 본다).
    @Test("미리보기: 맥 이름이 붙은 칸을 기준 폭과 가장 좁은 폭 둘 다 굽는다")
    func previewCatalogBakesTheNamedHeader() throws {
        let catalog = try IntegrationContractTests.code("Sources/CheckWidgetsKit/Widgets/AingWidgetPreviewCatalog.swift")
        for alive in ["limits-medium-device", "limits-medium-device-narrow"] {
            #expect(catalog.contains(alive), "미리보기에 \(alive) 가 없다 — 사람이 그 모양을 못 본다")
        }
        let card = try IntegrationContractTests.code("Sources/CheckMobileKit/Me/MeAILimitsCard.swift")
        for alive in ["card-two-devices", "card-twin-names", "card-two-devices-narrow"] {
            #expect(card.contains(alive), "카드 미리보기에 \(alive) 가 없다")
        }
    }

    enum WidgetDeviceFailure: Error { case notLimits }
}
