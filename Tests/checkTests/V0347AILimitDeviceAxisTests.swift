import Foundation
import Testing
@testable import check
@testable import CheckCore

// MARK: - v0.3.47 기기 축: 기기 이름 · 메인 맥 고르개
//
// 사용자 결정(2026-10-08): "컴퓨터 여러대에서 쓰는 사람들은 기기 여러대 인거 감지해서 각각의 기기마다
// 계정에 등록되게끔" · "설정의 컴퓨터 이름을 읽어서 그게 이름으로 들어가게끔" ·
// "그 한 맥은 애초에 앱 설정 자체에서 … 표시할 메인 피시를 선택할 수 있게끔".
//
// ## 왜 이 스위트가 필요한가
// 서버는 **이미** 기기별로 저장한다(`ai_limits` PK = `(user_id, device_id, provider)`). 폰이 "제공자당 최신
// 하나"로 접고 있었을 뿐이고, 그 접기가 "맥 A 에서 껐는데 맥 B 값이 이겨 되살아난다"를 만들었다.
// 숨기는 대신 드러내려면 두 가지가 더 필요하다: **그 맥을 부를 이름**과 **위젯이 그릴 한 대를 고르는 자리**.
//
// ## 이 파일이 지키는 것 — 전부 "초록인 채로 틀릴 수 있는" 자리다
//  ① 이름의 눈금이 **유니코드 스칼라**다. Swift `count`(자소)로 재면 서버 `char_length`(코드 포인트)와 갈려,
//     통과시킨 이름이 23514 로 **그 행 전체**를 조용히 날린다.
//  ② 업로드의 **키 집합이 모든 행에서 같다**(값 행·비우는 행 둘 다 `device_label` 을 적는다). 한 행만 빼면
//     PostgREST 가 400 PGRST102 로 본문 전체를 거절하고 그 거절은 조용하다.
//  ③ 접기가 **정렬을 한다**(최근에 일한 순). 기본 선택이 그 순서에 달려 있다.
//  ④ 이름을 모르는 옛 빌드의 **새 행이 그 맥의 이름을 지우지 않는다**.
//  ⑤ 고른 식별자가 목록에 **없으면** 가장 최근에 일한 맥으로 접는다(FK 를 안 건 대가이자 이유다).
//  ⑥ 고르기는 **낙관적**이고 서버가 거절하면 **되돌아간다**(화면만 바뀌는 거짓말을 만들지 않는다).
//
// ## 제공자 API 를 **실제로 부르지 않는다**
// 모든 리더는 주입된 가짜다(Claude 는 5분에 5회가 상한이다 — 스위트가 넘기면 사용자 계정이 5분 잠긴다).

// MARK: - 고정 시각·도우미

/// 고정 기준 시각. 다른 리밋 스위트와 **같은 값**이다(세 파일이 같은 세계를 말한다).
private let pdNow = Date(timeIntervalSince1970: 1_791_300_000)

/// 격리 UserDefaults. 이름은 **반드시** `CheckTestScratch` 에서 받는다(절대 경로 · UUID 없음) —
/// 평범한 도메인 이름은 `~/Library/Preferences` 에 plist 를 쌓고, 62만 개가 `cfprefsd` 를 죽인 전례가 있다.
private func pdDefaults(_ function: String = #function, line: Int = #line) -> UserDefaults {
    let name = CheckTestScratch.uniqueSuitePath(function: function, line: line)
    let defaults = UserDefaults(suiteName: name) ?? .standard
    defaults.removePersistentDomain(forName: name)
    return defaults
}

private func pdSnapshot(_ provider: AILimitProvider, observedAt: Date = pdNow) -> AILimitProviderSnapshot {
    AILimitProviderSnapshot(
        provider: provider,
        windows: [
            AILimitWindowSnapshot(window: .fiveHour, usedPercent: 27,
                                  resetsAt: observedAt.addingTimeInterval(3_600),
                                  observedAt: observedAt, source: .local),
            AILimitWindowSnapshot(window: .weekly, usedPercent: 60,
                                  resetsAt: observedAt.addingTimeInterval(86_400),
                                  observedAt: observedAt, source: .local)
        ],
        planLabel: "max"
    )
}

/// 요청받은 제공자만 답하는 가짜 러너(`VVRunnerSpy` 와 같은 규약 — 요청 밖의 제공자를 읽는 세계를 흉내내지 않는다).
private func pdRunner(available: Set<AILimitProvider>) -> AILimitStore.Runner {
    { now, providers in
        var results: [AILimitProvider: Result<AILimitProviderSnapshot, AILimitReadError>] = [:]
        for provider in providers {
            results[provider] = available.contains(provider)
                ? .success(pdSnapshot(provider, observedAt: now))
                : .failure(AILimitReadError(.notInstalled))
        }
        return AILimitReadOutcome(results: results)
    }
}

private func pdDevice(_ id: String, _ label: String?, _ secondsAgo: Double?) -> AILimitDevice {
    AILimitDevice(
        deviceID: id,
        label: label,
        lastObservedAt: secondsAgo.map { pdNow.addingTimeInterval(-$0) }
    )
}

// MARK: - ① 기기 이름의 규칙

@Suite("v0.3.47 — 기기 이름")
struct V0347AILimitDeviceLabelTests {
    /// 빈 값은 **올리지 않고**(nil), 앞뒤 공백은 떼고, 상한을 넘으면 **자른다**(플랜 라벨과 반대다).
    @Test
    func theLabelIsTrimmedAndCutButNeverEmpty() {
        #expect(AILimitDeviceLabelContract.normalized(nil) == nil)
        #expect(AILimitDeviceLabelContract.normalized("") == nil, "빈 문자열을 올리면 서버 CHECK(1자 하한)가 그 행을 통째로 버린다")
        #expect(AILimitDeviceLabelContract.normalized("   \n ") == nil, "공백뿐인 이름이 1자 이상으로 올라간다")
        #expect(AILimitDeviceLabelContract.normalized("  Mac mini  ") == "Mac mini")
        #expect(AILimitDeviceLabelContract.normalized("Mac mini") == "Mac mini")

        let exactly = String(repeating: "a", count: 64)
        #expect(AILimitDeviceLabelContract.normalized(exactly) == exactly, "상한과 같은 길이를 잘랐다")
        let tooLong = String(repeating: "a", count: 65)
        #expect(AILimitDeviceLabelContract.normalized(tooLong) == exactly, "상한을 넘긴 이름을 버렸다 — 자르는 쪽이 덜 잃는다")
        #expect(AILimitDeviceLabelContract.maxScalars == 64,
                "서버 CHECK(ai_limits_device_label_sane: 1…64)와 숫자가 어긋나면 올리는 순간 23514 다")
    }

    /// ★★ 눈금이 **유니코드 스칼라**다 — Swift `count`(자소 묶음)로 재면 서버 `char_length`(코드 포인트)와 갈린다.
    ///
    /// 조합 문자가 든 이름은 Swift 로 40자인데 Postgres 로 80자다. 자소로 재서 64개를 통과시키면 그 행은
    /// 23514 로 **통째로** 거절되고, 그 거절은 조용하다 — 그 맥의 리밋이 서버에 영원히 안 올라간다.
    /// 그리고 자소는 **쪼개지 않는다**: 쪼갠 조각은 글자도 아니다.
    @Test
    func theCutIsMeasuredInScalarsAndNeverSplitsAGrapheme() {
        // "e" + U+0301(결합 악센트) = 자소 1개 · 스칼라 2개. 40개면 자소 40 · 스칼라 80 이다.
        let combining = String(repeating: "e\u{0301}", count: 40)
        #expect(combining.count == 40, "전제: Swift 는 이 이름을 40자로 센다")
        #expect(combining.unicodeScalars.count == 80, "전제: Postgres 는 이 이름을 80자로 센다")
        let cut = try! #require(AILimitDeviceLabelContract.normalized(combining))
        #expect(cut.unicodeScalars.count <= 64,
                "스칼라 상한을 넘겼다 — 서버가 23514 로 그 행을 버리고 그 맥의 리밋은 영원히 안 올라간다")
        #expect(cut.unicodeScalars.count == 64, "스칼라를 덜 채웠다 — 자를 수 있는 만큼 남기지 않았다")
        #expect(cut.count == 32, "자소가 쪼개졌다 — 반쪽 글자는 이름이 아니다")
        #expect(cut == String(repeating: "e\u{0301}", count: 32))
    }

    /// 이름의 출처는 **시스템 설정의 컴퓨터 이름**이다 — 네트워크 호스트명이 아니다.
    ///
    /// 실측으로 가른다(`scutil --get ComputerName` 과 글자 비교). 호스트명(`Host.current().name`)은
    /// 이 맥에서 `mac-mini.local` 이라 사람이 자기 맥으로 못 알아본다 — 그 퇴행을 이 단언만이 잡는다.
    /// `scutil` 을 못 부르는 기계에서는 **조용히 넘긴다**(이 저장소는 맥에서만 테스트한다는 전제에 기대지 않는다).
    @Test
    func theNameIsTheComputerNameFromSystemSettings() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/scutil")
        process.arguments = ["--get", "ComputerName"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        guard (try? process.run()) != nil else { return }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let expected = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0, !expected.isEmpty else { return }
        #expect(AILimitDeviceName.current() == expected,
                "기기 이름이 시스템 설정의 컴퓨터 이름이 아니다 — 호스트명은 사람이 자기 맥으로 못 알아본다")
    }
}

// MARK: - ② 접기·이름 가르기·기본 선택 (순수)

@Suite("v0.3.47 — 기기 접기와 기본 선택")
struct V0347AILimitDeviceRosterTests {
    /// 제공자별로 흩어진 행이 **기기 단위**로 접히고, 최근에 일한 순으로 선다.
    @Test
    func rowsFoldIntoMacsOrderedByMostRecentlyWorked() {
        let folded = AILimitDeviceRoster.fold([
            AILimitDeviceObservation(deviceID: "MAC-A", label: "Mac mini", observedAt: pdNow.addingTimeInterval(-7_200)),
            AILimitDeviceObservation(deviceID: "MAC-A", label: "Mac mini", observedAt: pdNow.addingTimeInterval(-600)),
            AILimitDeviceObservation(deviceID: "MAC-B", label: "사무실 iMac", observedAt: pdNow.addingTimeInterval(-60))
        ])
        #expect(folded.count == 2, "제공자 행 수만큼 맥이 늘었다")
        #expect(folded.map(\.deviceID) == ["MAC-B", "MAC-A"], "최근에 일한 맥이 앞이 아니다 — 기본 선택이 그 순서에 달려 있다")
        #expect(folded[1].lastObservedAt == pdNow.addingTimeInterval(-600), "한 맥의 여러 행에서 가장 최근 시각을 못 골랐다")
    }

    /// ★ 이름을 **모르는** 옛 빌드가 쓴 더 새 행이 그 맥의 이름을 **지우지 않는다**.
    ///
    /// "가장 최근 행의 라벨"로 접으면 그 맥은 고르개에서 "이름 모를 맥"이 된다 — 맥 두 대 중 하나만 최신
    /// 빌드인 바로 그 사람이 당하는 자리다.
    @Test
    func aNewerRowWithoutALabelDoesNotEraseTheName() {
        let folded = AILimitDeviceRoster.fold([
            AILimitDeviceObservation(deviceID: "MAC-A", label: "Mac mini", observedAt: pdNow.addingTimeInterval(-3_600)),
            AILimitDeviceObservation(deviceID: "MAC-A", label: nil, observedAt: pdNow)
        ])
        #expect(folded.count == 1)
        #expect(folded[0].label == "Mac mini", "이름을 모르는 새 행이 이름을 지웠다")
        #expect(folded[0].lastObservedAt == pdNow, "그 새 행의 시각은 반영돼야 한다(일한 것은 사실이다)")
    }

    /// ★ 맥 이름을 **바꾼** 사람: 두 이름이 다 서버에 있으면 **더 최근에 올라간 이름**이 이긴다.
    ///
    /// 위 테스트(널이 이름을 지우지 않는다)와 **다른 결함을 문다.** 거기서는 라벨이 nil 인 행이 애초에
    /// 후보가 아니라서, 고르는 규칙을 "마지막 행 승"으로 바꿔도 통과한다(2026-10-08 뮤테이션으로 실증:
    /// `isNewer = true` 가 살아남았다). 실제로 그 규칙이 쥐고 있는 것은 **이름 둘이 경쟁하는 경우**다 —
    /// 배열 순서에 기대면 이름을 바꾼 사람의 고르개에 그가 지운 이름이 선다. 서버는 행 순서를 보장하지 않는다.
    @Test
    func aRenamedMacShowsTheNewestNameWhicheverRowComesFirst() {
        let newer = AILimitDeviceObservation(deviceID: "MAC-A", label: "거실 Mac mini", observedAt: pdNow)
        let older = AILimitDeviceObservation(
            deviceID: "MAC-A", label: "Mac mini", observedAt: pdNow.addingTimeInterval(-3_600))
        #expect(AILimitDeviceRoster.fold([newer, older]).first?.label == "거실 Mac mini",
                "옛 이름이 이겼다 — 이름을 바꾼 사람의 고르개에 그가 지운 이름이 선다")
        #expect(AILimitDeviceRoster.fold([older, newer]).first?.label == "거실 Mac mini",
                "접기가 배열 순서에 달려 있다 — 서버는 행 순서를 보장하지 않는다")
    }

    /// 관측 시각이 없는 기기는 **뒤로** 가고, 동률은 식별자로 가른다(순서가 결정적이어야 기본 선택이 뽑기가 아니다).
    @Test
    func devicesWithoutATimeGoLastAndTiesAreDeterministic() {
        let folded = AILimitDeviceRoster.fold([
            AILimitDeviceObservation(deviceID: "MAC-Z", label: nil, observedAt: nil),
            AILimitDeviceObservation(deviceID: "MAC-B", label: nil, observedAt: pdNow),
            AILimitDeviceObservation(deviceID: "MAC-A", label: nil, observedAt: pdNow)
        ])
        #expect(folded.map(\.deviceID) == ["MAC-A", "MAC-B", "MAC-Z"])
        #expect(AILimitDeviceRoster.fold([
            AILimitDeviceObservation(deviceID: "   ", label: "빈 식별자", observedAt: pdNow)
        ]).isEmpty, "식별자가 공백뿐인 행이 맥 한 대로 섰다")
    }

    /// 이름이 겹치면 **식별자 꼬리**로 가른다(맥 미니 두 대). 겹치지 않으면 아무것도 붙지 않는다.
    @Test
    func duplicateNamesAreToldApartByAnIdentifierTail() {
        let twins = [
            pdDevice("DEVICE-AAAA", "Mac mini", 60),
            pdDevice("DEVICE-BBBB", "Mac mini", 120),
            pdDevice("DEVICE-CCCC", "사무실 iMac", 180)
        ]
        let names = AILimitDeviceRoster.displayNames(twins)
        #expect(names["DEVICE-AAAA"] == "Mac mini (AAAA)", "같은 이름 둘을 가르지 못했다 — 고를 수가 없다")
        #expect(names["DEVICE-BBBB"] == "Mac mini (BBBB)")
        #expect(names["DEVICE-CCCC"] == "사무실 iMac", "겹치지 않는 이름에 식별자 조각을 붙였다 — 설정 창이 진단 화면이 된다")
    }

    /// 이름이 없는 맥끼리도 갈린다(대체 이름에 이미 꼬리가 들어 있다).
    @Test
    func unnamedMacsAreStillToldApart() {
        let unnamed = [pdDevice("DEVICE-1111", nil, 60), pdDevice("DEVICE-2222", nil, 120)]
        let names = AILimitDeviceRoster.displayNames(unnamed)
        #expect(names["DEVICE-1111"] == "이름 모를 맥 1111")
        #expect(names["DEVICE-2222"] == "이름 모를 맥 2222")
        #expect(Set(names.values).count == 2, "이름 없는 맥 둘이 같은 이름으로 섰다")
    }

    /// 기본값(아직 안 골랐다) = **가장 최근에 일한 맥**. 기존 사용자가 업데이트만 하면 지금과 같게 보인다.
    @Test
    func theDefaultChoiceIsTheMostRecentlyWorkedMac() {
        let devices = [pdDevice("MAC-A", "Mac mini", 600), pdDevice("MAC-B", "사무실 iMac", 60)]
        #expect(AILimitMainDeviceRule.resolve(devices: devices, chosen: nil)?.deviceID == "MAC-B")
        // 순서가 거꾸로 들어와도 같은 답이다(호출부가 자기 순서로 정렬해 넘기는 날에도).
        #expect(AILimitMainDeviceRule.resolve(devices: devices.reversed(), chosen: nil)?.deviceID == "MAC-B",
                "기본 선택이 배열 순서에 달려 있다 — 폰이 다른 순서로 넘기면 다른 맥이 보인다")
        #expect(AILimitMainDeviceRule.resolve(devices: [], chosen: "MAC-A") == nil)
    }

    /// 고른 맥이 **목록에 있으면** 그것이다(최근 순을 이긴다 — 그게 고르개가 있는 이유다).
    @Test
    func anExplicitChoiceWinsOverRecency() {
        let devices = [pdDevice("MAC-A", "Mac mini", 600), pdDevice("MAC-B", "사무실 iMac", 60)]
        #expect(AILimitMainDeviceRule.resolve(devices: devices, chosen: "MAC-A")?.deviceID == "MAC-A",
                "골라도 가장 최근에 일한 맥이 이긴다 — 그러면 고르개는 아무 일도 안 하는 장식이다")
    }

    /// ★ 모르는 식별자는 **접는다**. FK 를 안 건 대가이자 이유다(고른 맥의 행이 사라지는 일은 정상이다 —
    /// 그 맥에서 설정을 끄면 행이 비워지고, 3일 유령 게이트가 낡은 행을 숨긴다).
    @Test
    func anUnknownChoiceFoldsBackToTheMostRecentMac() {
        let devices = [pdDevice("MAC-A", "Mac mini", 600), pdDevice("MAC-B", "사무실 iMac", 60)]
        #expect(AILimitMainDeviceRule.resolve(devices: devices, chosen: "MAC-SOLD")?.deviceID == "MAC-B",
                "목록에 없는 식별자를 고른 채로 두면 폰·위젯이 아무 맥도 안 그린다")
    }

    /// 고를 수 있는 식별자의 상한이 **`ai_limits.device_id` 와 같다**. 어긋나면 고르는 순간 23514 다.
    @Test
    func theChoiceLengthCapMatchesTheDeviceIDCap() {
        #expect(AILimitMainDeviceIDContract.maxLength == 128,
                "서버 CHECK(ai_limits_prefs_main_device_sane: 1…128)와 숫자가 어긋났다")
        #expect(AILimitMainDeviceIDContract.normalized(String(repeating: "a", count: 128))?.count == 128)
        #expect(AILimitMainDeviceIDContract.normalized(String(repeating: "a", count: 129)) == nil,
                "상한을 넘긴 식별자를 보냈다 — 23514 로 그 행이 통째로 거절되고 거절은 조용하다")
        #expect(AILimitMainDeviceIDContract.normalized("  ") == nil)
    }
}

// MARK: - ③ 업로드가 기기 이름을 싣는다

@Suite("v0.3.47 — 업로드의 기기 이름")
@MainActor
struct V0347AILimitDeviceLabelUploadTests {
    private func service(host: String) -> SupabaseWorkService {
        SupabaseWorkService(
            projectURL: URL(string: "http://\(host)")!,
            anonKey: "anon-test-key",
            session: URLSession(configuration: .stubbed)
        )
    }

    private func store(host: String, defaults: UserDefaults, aiLimits: AILimitStore) -> WorkTimerStore {
        let store = WorkTimerStore(
            service: service(host: host),
            environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
            defaults: defaults,
            workspaceNotifications: nil,
            aiLimits: aiLimits
        )
        store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "me")
        // 기기 신원은 **지어내지 않고** 있는 것을 쓴다(관례: '기기 신원을 지어내지 마라').
        store.deviceID = "MAC-PD"
        return store
    }

    private func bodies(host: String) -> [[[String: Any]]] {
        URLProtocolStub.bodies(forHost: host).compactMap {
            (try? JSONSerialization.jsonObject(with: Data($0.utf8))) as? [[String: Any]]
        }
    }

    /// ★★ 값 행과 **비우는 행이 둘 다** 기기 이름을 싣고, 키 집합이 글자 하나까지 같다.
    ///
    /// 한 행만 그 칸을 빼면 PostgREST 가 400 PGRST102("All object keys must match")로 **본문 전체**를
    /// 거절하고, 400 은 호출측이 조용히 삼키므로 그 사람의 행은 영원히 한 줄도 안 올라간다(영구 고착).
    @Test
    func valueAndClearingRowsBothCarryTheLabelWithOneKeySet() async {
        let host = "pd-label-both"
        let defaults = pdDefaults()
        let limits = AILimitStore(
            defaults: defaults, clock: { pdNow },
            deviceLabelProvider: { "예성의 Mac mini" },
            runner: pdRunner(available: [.claude, .codex])
        )
        let store = self.store(host: host, defaults: defaults, aiLimits: limits)
        defer { store.session = nil }

        await limits.refreshIfDue(now: pdNow)
        await store.uploadAILimitsIfNeeded(now: pdNow)
        let first = try! #require(bodies(host: host).first)
        #expect(first.count == 2, "전제: 값 행 둘이 나갔다")
        for row in first {
            #expect(row["device_label"] as? String == "예성의 Mac mini", "값 행이 기기 이름을 싣지 않았다")
        }

        limits.setProviderEnabled(.codex, false)
        store.lastUploadedAILimits = nil
        await store.uploadAILimitsIfNeeded(now: pdNow.addingTimeInterval(60))
        let second = try! #require(bodies(host: host).last)
        let codexRow = try! #require(second.first { $0["provider"] as? String == "codex" })
        #expect(codexRow["five_hour_percent"] is NSNull, "전제: 이 행은 비우는 행이다")
        #expect(codexRow["device_label"] as? String == "예성의 Mac mini",
                "비우는 행에 기기 이름이 없다 — 키 집합이 달라져 본문 전체가 400 PGRST102 로 거절된다")

        let expected = Set(AILimitUpsertRow.CodingKeys.allCases.map(\.rawValue))
        #expect(expected.contains("device_label"), "키 목록에 device_label 이 없다")
        for body in bodies(host: host) {
            for row in body { #expect(Set(row.keys) == expected) }
        }
        #expect(URLProtocolStub.hasMismatchedObjectKeys(URLProtocolStub.bodies(forHost: host).last!) == false)
    }

    /// 이름이 없으면(빈 값·공백뿐) **null 로** 간다 — 빈 문자열을 올리면 서버 CHECK(1자 하한)가 그 행을 버린다.
    @Test
    func anEmptyComputerNameGoesUpAsNull() async {
        let host = "pd-label-empty"
        let defaults = pdDefaults()
        let limits = AILimitStore(
            defaults: defaults, clock: { pdNow },
            deviceLabelProvider: { "   " },
            runner: pdRunner(available: [.claude])
        )
        let store = self.store(host: host, defaults: defaults, aiLimits: limits)
        defer { store.session = nil }

        await limits.refreshIfDue(now: pdNow)
        await store.uploadAILimitsIfNeeded(now: pdNow)
        let row = try! #require(bodies(host: host).first?.first)
        #expect(row["device_label"] is NSNull, "공백뿐인 이름이 그대로 올라갔다 — 23514 로 그 행이 통째로 거절된다")
        #expect(row["five_hour_percent"] as? Double == 27, "이름이 없다고 값까지 못 올라가면 안 된다")
    }

    /// 긴 이름은 **잘려서** 올라간다(버리지 않는다 — 앞부분도 그 맥을 가리킨다).
    @Test
    func aTooLongNameIsCutNotDropped() async {
        let host = "pd-label-long"
        let defaults = pdDefaults()
        let long = String(repeating: "가", count: 70)
        let limits = AILimitStore(
            defaults: defaults, clock: { pdNow },
            deviceLabelProvider: { long },
            runner: pdRunner(available: [.claude])
        )
        let store = self.store(host: host, defaults: defaults, aiLimits: limits)
        defer { store.session = nil }

        await limits.refreshIfDue(now: pdNow)
        await store.uploadAILimitsIfNeeded(now: pdNow)
        let row = try! #require(bodies(host: host).first?.first)
        let sent = try! #require(row["device_label"] as? String)
        #expect(sent.unicodeScalars.count == 64, "상한을 넘긴 이름이 그대로 올라갔다 — 그 행은 23514 로 거절된다")
        #expect(sent == String(repeating: "가", count: 64))
    }

    /// 이름은 **그때그때 읽는다** — 사용자가 시스템 설정에서 맥 이름을 바꾸면 앱을 다시 켜지 않아도 반영된다.
    ///
    /// 초안처럼 init 에서 한 번 굳히면 이름을 바꾼 사람은 다음 재시작까지 옛 이름으로 올라가고, 그동안
    /// 폰의 고르개에는 그가 지운 이름이 서 있다.
    @Test
    func theNameIsReReadOnEveryUpload() async {
        let host = "pd-label-renamed"
        let defaults = pdDefaults()
        let box = PDNameBox("Mac mini")
        let limits = AILimitStore(
            defaults: defaults, clock: { pdNow },
            deviceLabelProvider: { box.name },
            runner: pdRunner(available: [.claude])
        )
        let store = self.store(host: host, defaults: defaults, aiLimits: limits)
        defer { store.session = nil }

        await limits.refreshIfDue(now: pdNow)
        await store.uploadAILimitsIfNeeded(now: pdNow)
        #expect(bodies(host: host).first?.first?["device_label"] as? String == "Mac mini")

        box.name = "거실 Mac mini"
        store.lastUploadedAILimits = nil
        await store.uploadAILimitsIfNeeded(now: pdNow.addingTimeInterval(60))
        #expect(bodies(host: host).last?.first?["device_label"] as? String == "거실 Mac mini",
                "맥 이름을 바꿨는데 옛 이름이 올라갔다 — 앱을 다시 켜야만 반영된다는 뜻이다")
    }
}

/// 이름을 바꿔 보는 상자. 클로저가 **그때그때** 읽는지 가르는 유일한 도구다.
private final class PDNameBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: String
    init(_ value: String) { self.value = value }
    var name: String {
        get { lock.lock(); defer { lock.unlock() }; return value }
        set { lock.lock(); value = newValue; lock.unlock() }
    }
}

// MARK: - ④ 메인 맥: 서버 왕복과 스토어 반영

@Suite("v0.3.47 — 메인 맥 서버 왕복")
@MainActor
struct V0347AILimitMainDeviceTests {
    private func service(host: String) -> SupabaseWorkService {
        SupabaseWorkService(
            projectURL: URL(string: "http://\(host)")!,
            anonKey: "anon-test-key",
            session: URLSession(configuration: .stubbed)
        )
    }

    private func store(host: String, defaults: UserDefaults, aiLimits: AILimitStore) -> WorkTimerStore {
        let store = WorkTimerStore(
            service: service(host: host),
            environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
            defaults: defaults,
            workspaceNotifications: nil,
            aiLimits: aiLimits
        )
        store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "me")
        store.deviceID = "MAC-A"
        return store
    }

    private func limits(_ defaults: UserDefaults) -> AILimitStore {
        AILimitStore(
            defaults: defaults, clock: { pdNow },
            deviceLabelProvider: { "Mac mini" },
            runner: pdRunner(available: [.claude])
        )
    }

    /// 서버 행이 **기기 단위로 접혀** 들어온다(제공자 행 셋 → 맥 둘), 최근 순으로.
    ///
    /// 조회가 읽는 칸은 셋뿐이다 — 고르개가 필요한 것은 "어떤 맥이 있고 언제 일했나"이고, 사용률까지 받아 오면
    /// 설정 창을 여는 것만으로 쓰지도 않는 숫자가 네트워크로 흐른다.
    @Test
    func theRosterFoldsServerRowsIntoMacs() async throws {
        let host = "pd-ai-devices-two"
        let service = self.service(host: host)
        let devices = try await service.fetchAILimitDevices(accessToken: "t", userID: "me")
        #expect(devices.map(\.deviceID) == ["MAC-B", "MAC-A"], "최근에 일한 맥이 앞이 아니다")
        #expect(devices[0].label == "예성의 MacBook Pro")
        #expect(devices[1].label == "Mac mini",
                "이름을 모르는 더 새 행이 그 맥의 이름을 지웠다 — 고르개에 '이름 모를 맥'이 선다")
        #expect(devices[1].lastObservedAt != nil, "관측 시각을 못 읽었다 — 기본 선택이 이 값으로 선다")

        let request = try #require(URLProtocolStub.requests(forHost: host).last)
        let query = request.url?.query ?? ""
        #expect(query.contains("user_id=eq.me"), "남의 행까지 긁는 조회다")
        #expect(request.url?.path == "/rest/v1/ai_limits")
        let select = try #require(request.url.flatMap {
            URLComponents(url: $0, resolvingAgainstBaseURL: false)?
                .queryItems?.first { $0.name == "select" }?.value
        })
        #expect(select == "device_id,device_label,observed_at", "조회가 값 칸까지 읽는다")
    }

    /// 행이 없거나 칸이 null 이면 **"아직 안 골랐다"** 다(throw 가 아니다 — 가입 트리거가 이 행을 안 만든다).
    @Test
    func noRowMeansNotChosenYet() async throws {
        let empty = try await service(host: "pd-prefs-empty")
            .fetchAILimitMainDeviceID(accessToken: "t", userID: "me")
        #expect(empty == nil, "행이 없다고 던지면 아무도 못 고른 상태에서 고르개가 영영 안 뜬다")
        let chosen = try await service(host: "pd-ai-prefs-chosen")
            .fetchAILimitMainDeviceID(accessToken: "t", userID: "me")
        #expect(chosen == "MAC-B", "고른 값을 못 읽었다 — 고르개가 늘 기본값을 그린다")
    }

    /// 고르기는 **upsert 하나**다(`on_conflict=user_id` — 계정당 한 행). 되돌릴 때는 **명시적 null** 이다.
    @Test
    func choosingUpsertsOnUserIDAndCanBeUndoneWithAnExplicitNull() async throws {
        let host = "pd-prefs-write"
        let service = self.service(host: host)
        try await service.upsertAILimitMainDeviceID(accessToken: "t", userID: "me", mainDeviceID: "MAC-B")
        let request = try #require(URLProtocolStub.requests(forHost: host).last)
        #expect(request.url?.path == "/rest/v1/ai_limits_prefs")
        #expect(request.httpMethod == "POST")
        #expect(request.url?.query?.contains("on_conflict=user_id") == true,
                "on_conflict 이 user_id 가 아니면 두 번째 고르기가 23505 로 거절된다")
        #expect(request.value(forHTTPHeaderField: "Prefer")?.contains("resolution=merge-duplicates") == true)
        let sent = try #require(URLProtocolStub.bodies(forHost: host).last)
        let rows = try #require(
            (try? JSONSerialization.jsonObject(with: Data(sent.utf8))) as? [[String: Any]])
        #expect(rows.count == 1, "계정당 한 행인데 본문에 행이 여럿이다")
        #expect(rows[0]["user_id"] as? String == "me")
        #expect(rows[0]["main_device_id"] as? String == "MAC-B")
        #expect(rows[0]["updated_at"] == nil, "updated_at 을 보냈다 — 서버 터치 트리거가 덮으므로 버려진다")

        // 되돌리기: 키를 **생략하면** merge-duplicates 가 옛 값을 그대로 둔다(= 안 고른 상태로 못 돌아간다).
        try await service.upsertAILimitMainDeviceID(accessToken: "t", userID: "me", mainDeviceID: nil)
        let undone = try #require(URLProtocolStub.bodies(forHost: host).last)
        let undoneRows = try #require(
            (try? JSONSerialization.jsonObject(with: Data(undone.utf8))) as? [[String: Any]])
        #expect(undoneRows[0]["main_device_id"] is NSNull,
                "안 고른 상태로 되돌리기가 서버에 닿지 못한다 — 빠진 키는 갱신되지 않는다")
    }

    /// 설정 창이 열리면 목록과 선택이 스토어에 **한 번에** 들어오고, 5분 안에는 다시 묻지 않는다.
    @Test
    func loadingFillsTheStoreOnceWithinTheInterval() async {
        let host = "pd-ai-devices-two-ai-prefs-chosen"
        let defaults = pdDefaults()
        let limits = self.limits(defaults)
        let store = self.store(host: host, defaults: defaults, aiLimits: limits)
        defer { store.session = nil }

        #expect(limits.devicesAreDue(now: pdNow), "전제: 한 번도 못 받았으면 받아 올 때다")
        await store.loadAILimitDevicesIfNeeded(now: pdNow)
        #expect(limits.devices.map(\.deviceID) == ["MAC-B", "MAC-A"])
        #expect(limits.mainDeviceID == "MAC-B", "고른 맥을 못 읽었다")
        #expect(limits.effectiveMainDevice?.deviceID == "MAC-B")
        #expect(limits.showsMainDevicePicker, "맥이 두 대인데 고르개가 안 보인다")

        let roundTrips = URLProtocolStub.requests(forHost: host).count
        #expect(roundTrips == 2, "목록·선택 두 조회 말고 다른 요청이 더 났다")
        await store.loadAILimitDevicesIfNeeded(now: pdNow.addingTimeInterval(299))
        #expect(URLProtocolStub.requests(forHost: host).count == roundTrips,
                "5분 안에 다시 물었다 — 설정 창을 여닫을 때마다 계정당 두 번씩 GET 이 더 난다")
        await store.loadAILimitDevicesIfNeeded(now: pdNow.addingTimeInterval(300))
        #expect(URLProtocolStub.requests(forHost: host).count == roundTrips + 2,
                "간격이 지났는데 다시 묻지 않았다 — 둘째 맥이 생겨도 고르개에 안 나타난다")
    }

    /// 맥이 **한 대**면 고르개를 숨긴다(근거는 뷰 주석 넷) — 그리고 숨겨도 기본 선택은 그 한 대다.
    @Test
    func oneMacHidesThePickerButStillResolves() async {
        let host = "pd-ai-devices-one"
        let defaults = pdDefaults()
        let limits = self.limits(defaults)
        let store = self.store(host: host, defaults: defaults, aiLimits: limits)
        defer { store.session = nil }

        await store.loadAILimitDevicesIfNeeded(now: pdNow)
        #expect(limits.devices.count == 1)
        #expect(limits.showsMainDevicePicker == false, "고를 것이 없는 고르개를 보여 준다 — 권한에 대한 거짓말이다")
        #expect(limits.effectiveMainDevice?.deviceID == "MAC-A", "숨겼더니 기본 선택도 사라졌다")

        // 서버에 행이 하나도 없는 사람(한 번도 안 올렸다)도 같은 분기로 덮인다.
        let emptyDefaults = pdDefaults()
        let emptyLimits = self.limits(emptyDefaults)
        let emptyStore = self.store(host: "pd-ai-devices-none", defaults: emptyDefaults, aiLimits: emptyLimits)
        defer { emptyStore.session = nil }
        await emptyStore.loadAILimitDevicesIfNeeded(now: pdNow)
        #expect(emptyLimits.devices.isEmpty)
        #expect(emptyLimits.showsMainDevicePicker == false)
        #expect(emptyLimits.effectiveMainDevice == nil)
    }

    /// 저장된 선택이 **목록에 없으면** 가장 최근에 일한 맥을 보여 준다(그 맥을 팔았거나 3일 유령 게이트가 숨겼다).
    @Test
    func anUnknownStoredChoiceShowsTheMostRecentMac() async {
        let host = "pd-ai-devices-two-ai-prefs-gone"
        let defaults = pdDefaults()
        let limits = self.limits(defaults)
        let store = self.store(host: host, defaults: defaults, aiLimits: limits)
        defer { store.session = nil }

        await store.loadAILimitDevicesIfNeeded(now: pdNow)
        #expect(limits.mainDeviceID == "MAC-SOLD-LAST-WEEK", "서버 값은 그대로 들고 있어야 한다(지우지 않는다)")
        #expect(limits.effectiveMainDevice?.deviceID == "MAC-B",
                "모르는 식별자를 접지 않았다 — 폰·위젯이 아무 맥도 안 그린다")
    }

    /// ★★ 고르기는 **낙관적**이고, 서버가 거절하면 **되돌아간다**.
    ///
    /// 안 되돌리면 설정 창에는 내가 고른 맥이 떠 있는데 폰·위젯은 옛 맥을 계속 보여 준다 — 사용자가 고친 줄
    /// 아는 바로 그 결함이 남는다(화면만 바뀌는 거짓말). 칩이 제자리로 튀는 쪽이 정직하다.
    @Test
    func pickingIsOptimisticAndRevertsWhenTheServerRefuses() async {
        // 성공 경로.
        let okHost = "pd-ai-devices-two-ai-prefs-chosen-ok"
        let okDefaults = pdDefaults()
        let okLimits = limits(okDefaults)
        let okStore = store(host: okHost, defaults: okDefaults, aiLimits: okLimits)
        defer { okStore.session = nil }
        await okStore.loadAILimitDevicesIfNeeded(now: pdNow)
        #expect(okLimits.mainDeviceID == "MAC-B", "전제: 지금 고른 것은 MAC-B 다")
        await okStore.setAILimitMainDevice("MAC-A")
        #expect(okLimits.mainDeviceID == "MAC-A", "고르기가 화면에 반영되지 않았다")

        // 실패 경로: `schema-missing` 접두어는 모든 /rest/v1 요청을 404 로 떨어뜨린다
        // (앱이 db push 보다 먼저 나간 서버의 모양).
        let badDefaults = pdDefaults()
        let badLimits = limits(badDefaults)
        let badStore = store(host: "schema-missing-pd-prefs", defaults: badDefaults, aiLimits: badLimits)
        defer { badStore.session = nil }
        badLimits.applyDevices(
            [pdDevice("MAC-A", "Mac mini", 600), pdDevice("MAC-B", "사무실 iMac", 60)],
            mainDeviceID: "MAC-B", now: pdNow)
        await badStore.setAILimitMainDevice("MAC-A")
        #expect(badLimits.mainDeviceID == "MAC-B",
                "서버가 거절했는데 화면은 바뀐 채다 — 설정 창과 폰이 서로 다른 맥을 가리킨다")
    }

    /// 로그인·기기 신원이 없으면 **요청을 아예 보내지 않는다**(관례: 기기 신원을 지어내지 마라).
    @Test
    func noSessionOrDeviceIdentityMeansNoRequest() async {
        let host = "pd-ai-devices-two-nosession"
        let defaults = pdDefaults()
        let limits = self.limits(defaults)
        let store = self.store(host: host, defaults: defaults, aiLimits: limits)
        store.session = nil
        await store.loadAILimitDevicesIfNeeded(now: pdNow)
        await store.setAILimitMainDevice("MAC-B")
        #expect(URLProtocolStub.requests(forHost: host).isEmpty, "로그인 없이 요청을 보냈다")

        store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "me")
        store.deviceID = ""
        defer { store.session = nil }
        await store.loadAILimitDevicesIfNeeded(now: pdNow)
        await store.setAILimitMainDevice("MAC-B")
        #expect(URLProtocolStub.requests(forHost: host).isEmpty, "기기 신원 없이 요청을 보냈다")
    }
}
