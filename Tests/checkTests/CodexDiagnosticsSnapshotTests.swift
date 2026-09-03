import Foundation
import Testing
@testable import check

// Codex 집계 진단의 **시각 정합**을 고정하는 스위트.
//
// 사고의 형태: `token_usage_device_monthly` 한 행 안에 시각이 다른 두 값이 섞여 있었다.
//   · codex_input  — 프로덕션 증분 스캐너 값. **업로드마다**(30초) 갱신된다.
//   · codex_diag_* — 진단. **도장당 1회**만 계산·업로드된다.
// 이월 정정량을 `codex_diag_legacy_total − codex_input` 으로 재려 하자 실제 행에서 **−4,297,774,877** 이
// 나왔다. 옛 산식이 현행보다 작다는 불가능한 값이었고, 정체는 정정량이 아니라 "진단 이후에 더 쓴 양"이었다.
// 두 값의 월 렌즈는 같았고 어긋난 것은 오직 **시각**이다.
//
// 그래서 고친 두 가지를 이 파일이 지킨다:
//   1) codex_diag_input_at_scan — 진단을 잰 그 순간의 Codex 총합을 **같은 행에** 함께 스냅샷한다.
//      값은 TokenUsageUpsertRequest 의 diagnostics 생성자가 **같은 본문의 codexInput+codexOutput 에서 파생**시킨다
//      (호출측이 따로 넘기면 어긋날 수 있고, 그 어긋남이 이 필드가 없애려던 결함이라 구조로 막았다).
//   2) 도장이 하루 단위 — "<빌드>:<KST YYYY-MM-DD>". 월 도장이면 스냅샷과 현재값이 최대 한 달까지 벌어진다.
//
// 이 스위트의 심장은 `codexDiagSnapshotIsNotOverwrittenByPlainUploads` 다 — 진단키가 실리는 업로드와
// 안 실리는 업로드가 [19,0,0,0,19,0] 으로 갈리지 않으면 스냅샷은 매 30초 codex_input 으로 덮여
// 이 기능 전체가 무의미해진다(그때는 굳이 컬럼을 더할 이유가 없다).

// MARK: - 픽스처 헬퍼

/// 스위트 전용 격리 UserDefaults(도장 키가 실제 사용자 설정을 건드리지 않게).
private func isolatedDefaults() -> UserDefaults {
    let name = "codex-diag-snapshot-\(UUID().uuidString)"
    UserDefaults().removePersistentDomain(forName: name)
    return UserDefaults(suiteName: name)!
}

/// 프로덕션과 **같은 설정**의 인코더(SupabaseWorkService.init 이 세우는 것과 동일: convertToSnakeCase).
/// 여기서 전략이 갈리면 키 이름 단언이 실서버와 무관해진다.
private func productionShapedEncoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase
    encoder.outputFormatting = [.sortedKeys]
    return encoder
}

/// KST 벽시계 시각의 절대 Date. 도장 산식(dayBounds)과 **독립적으로** 테스트 쪽에서 만든 기준점이라,
/// 프로덕션 산식이 바뀌면 이 값들이 그 변화를 그대로 드러낸다.
private func kst(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
    return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

/// 전 필드에 **서로 다른** 값을 심은 진단 스냅샷. 값이 겹치면 생성자가 필드를 잘못 짝지어도 드러나지 않는다.
private func filledDiagnostics(build: Int = 41) -> CodexUsageDiagnostics {
    var diagnostics = CodexUsageDiagnostics()
    diagnostics.filesTotal = 101
    diagnostics.filesMonth = 102
    diagnostics.eventsMonth = 103
    diagnostics.maxDelta = 104
    diagnostics.maxDeltaGapSeconds = 105
    diagnostics.bigDeltaCount = 106
    diagnostics.bigDeltaTotal = 107
    diagnostics.bigGapMedianSeconds = 108
    diagnostics.carryFiles = 109
    diagnostics.carryTotal = 110
    diagnostics.dupEvents = 111
    diagnostics.dupTokens = 112
    diagnostics.finalSum = 113
    diagnostics.dedupTotal = 114
    diagnostics.legacyTotal = 115
    diagnostics.drops = 116
    diagnostics.topFile = 117
    diagnostics.appBuild = build
    return diagnostics
}

private func upsertRequest(
    diagnostics: CodexUsageDiagnostics?,
    codexInput: Int = 7_000,
    codexOutput: Int = 0
) -> TokenUsageUpsertRequest {
    TokenUsageUpsertRequest(
        userId: "U", month: "2026-08", deviceId: "D",
        claudeInput: 11, claudeOutput: 22, claudeCacheRead: 33, claudeCacheCreation: 44,
        codexInput: codexInput, codexOutput: codexOutput,
        total: 11 + 22 + 33 + 44 + codexInput + codexOutput,
        todayTotal: 77, todayDate: "2026-08-18",
        diagnostics: diagnostics
    )
}

/// supabase/migrations/20260817140000_codex_diag_input_snapshot.sql 이 서버에 세운 진단 컬럼 19개.
/// 이 목록을 **마이그레이션에서 그대로 옮겨 적은 것**이 요점이다 — 앱이 보내는 키와 서버 컬럼이 1:1 이 아니면
/// PostgREST 는 모르는 키를 400 으로 되쏘거나(오타) 값이 조용히 어디에도 안 쌓인다.
private let migrationDiagColumns: Set<String> = [
    "codex_diag_files_total",
    "codex_diag_files_month",
    "codex_diag_events_month",
    "codex_diag_max_delta",
    "codex_diag_carry_files",
    "codex_diag_carry_total",
    "codex_diag_dup_events",
    "codex_diag_dup_tokens",
    "codex_diag_final_sum",
    "codex_diag_dedup_total",
    "codex_diag_drops",
    "codex_diag_top_file",
    "codex_diag_build",
    "codex_diag_legacy_total",
    "codex_diag_big_delta_count",
    "codex_diag_big_delta_total",
    "codex_diag_max_delta_gap_s",
    "codex_diag_big_gap_median_s",
    "codex_diag_input_at_scan",
]

/// 진단을 뺀 본문의 고정 키 13개(v0.2.41 에 codex_cache_read 가 항상 실린다 — 20260903120000 컬럼).
private let nonDiagColumns: Set<String> = [
    "user_id", "month", "device_id",
    "claude_input", "claude_output", "claude_cache_read", "claude_cache_creation",
    "codex_input", "codex_output", "total",
    "today_total", "today_date",
    "codex_cache_read",
]

@MainActor
private func makeStore(host: String, build: Int?) -> WorkTimerStore {
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed)
    )
    let store = WorkTimerStore(
        service: service,
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: isolatedDefaults()
    )
    store.session = SupabaseSession(
        accessToken: "access-token", refreshToken: nil,
        userID: "00000000-0000-0000-0000-000000000002"
    )
    store.currentTeamID = URLProtocolStub.stubTeamID
    store.appVersionProvider = { build.map { AppVersionReport(build: $0, version: "0.2.33") } }
    return store
}

/// 이 스토어가 그 호스트로 보낸 token_usage_device_monthly POST 본문들(보낸 순서 그대로).
///
/// **deviceID 로 거르는 이유**: 스텁의 기록 버퍼는 프로세스 전역이고 호스트별이라, 같은 호스트를 쓰는 다른
/// 스위트(예: device-table-missing 을 쓰는 tokenUploadSurfacesMissingDeviceTableSchema)가 병렬로 돌면
/// 남의 본문이 내 시퀀스에 섞여 [19,0,0,0,19,0] 같은 순서 단언이 무음으로 깨진다. deviceID 는
/// 격리 UserDefaults 마다 새로 만들어지는 UUID 라 이 스토어의 본문만 정확히 남는다.
private func deviceUploadBodies(host: String, deviceID: String) -> [String] {
    zip(URLProtocolStub.requests(forHost: host), URLProtocolStub.bodies(forHost: host))
        .filter {
            $0.0.url?.path == "/rest/v1/token_usage_device_monthly"
                && $0.0.httpMethod == "POST"
                && $0.1.contains("\"device_id\":\"\(deviceID)\"")
        }
        .map(\.1)
}

/// 본문 하나의 codex_diag_* 키 개수(0 = 진단 미동봉, 19 = 진단 동봉).
private func diagKeyCount(in body: String) -> Int {
    let object = (try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? [String: Any] ?? [:]
    return object.keys.filter { $0.hasPrefix("codex_diag") }.count
}

// MARK: - 1. 진단 nil → codex_diag_* 키가 하나도 없다

// **옵셔널이 이 설계의 전부다.** nil 이면 합성 Encodable 이 encodeIfPresent 로 키 자체를 빼고,
// PostgREST 의 upsert 는 본문에 없는 컬럼을 건드리지 않는다 — 그래서 30초마다 도는 평상시 업로드가
// 서버에 쌓인 진단값을 지우지 않는다. 키가 하나라도 새어 나가면(예: 옵셔널을 값으로 바꾸면) 그 컬럼은
// 매 업로드마다 덮어써진다. 개수를 세는 것이 아니라 **집합이 정확히 비었는지**를 본다.
@Test
func codexDiagKeysVanishEntirelyWhenDiagnosticsIsNil() throws {
    let data = try productionShapedEncoder().encode(upsertRequest(diagnostics: nil))
    let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    let keys = Set(object.keys)

    #expect(keys.filter { $0.hasPrefix("codex_diag") }.isEmpty)
    // 남은 것은 고정 13키뿐 — 진단이 빠졌다고 다른 값이 함께 사라지지도, 늘어나지도 않는다(계정 키도 nil 이라 0개).
    #expect(keys == nonDiagColumns)
    #expect(keys.count == 13)
    #expect(keys.filter { $0.hasPrefix("codex_account") }.isEmpty)
    // 스냅샷 컬럼도 예외가 아니다(이것만 값 타입으로 새면 평상시 업로드가 매번 덮는다).
    #expect(object["codex_diag_input_at_scan"] == nil)
}

// MARK: - 2. 진단을 채우면 19키 · 스냅샷은 Codex '총합'에서 파생된다

// 두 가지를 한 번에 못 박는다.
//  (a) 나가는 진단 키 집합이 마이그레이션 컬럼 19개와 **정확히 같다**(빠짐도 여분도 없음).
//  (b) codex_diag_input_at_scan 이 codexInput 이 아니라 **codexInput+codexOutput** 에서 온다.
//      오늘은 앱이 Codex 델타를 전액 codexInput 에 담고 codexOutput 은 항상 0 이라 두 산식의 값이 같다 —
//      그래서 (5, 3) 처럼 출력이 0 이 아닌 본문을 일부러 만들어야만 차이가 보인다. 훗날 출력을 쪼개 담는 날
//      "그 업로드의 Codex 총합"이라는 뜻이 조용히 깨지는 것을 지금 막아 두는 단언이다.
@Test
func codexDiagEncodesNineteenMigrationColumnsWithSnapshotFromCodexTotal() throws {
    let encoder = productionShapedEncoder()
    let diagnostics = filledDiagnostics()

    let data = try encoder.encode(upsertRequest(diagnostics: diagnostics, codexInput: 7_000, codexOutput: 0))
    let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    let diagKeys = Set(object.keys.filter { $0.hasPrefix("codex_diag") })

    #expect(diagKeys == migrationDiagColumns)
    #expect(diagKeys.count == 19)
    #expect(Set(object.keys) == nonDiagColumns.union(migrationDiagColumns))

    // 값이 필드끼리 뒤바뀌지 않았는지 — 전부 서로 다른 값을 심어 뒀다.
    #expect(object["codex_diag_files_total"] as? Int == 101)
    #expect(object["codex_diag_max_delta_gap_s"] as? Int == 105)
    #expect(object["codex_diag_big_gap_median_s"] as? Int == 108)
    #expect(object["codex_diag_legacy_total"] as? Int == 115)
    #expect(object["codex_diag_build"] as? Int == 41)

    // (b-1) 출력이 0 인 오늘의 모양: 스냅샷 = 이 본문의 codex_input 그 자체.
    #expect(object["codex_diag_input_at_scan"] as? Int == 7_000)
    #expect(object["codex_diag_input_at_scan"] as? Int == object["codex_input"] as? Int)

    // (b-2) 출력이 0 이 아닌 모양: 합(8)이 실린다. codexInput 만 쓰면 여기서 5 가 나온다.
    let splitData = try encoder.encode(upsertRequest(diagnostics: diagnostics, codexInput: 5, codexOutput: 3))
    let splitObject = try #require(try JSONSerialization.jsonObject(with: splitData) as? [String: Any])
    #expect(splitObject["codex_input"] as? Int == 5)
    #expect(splitObject["codex_output"] as? Int == 3)
    #expect(splitObject["codex_diag_input_at_scan"] as? Int == 8)
}

// MARK: - 3. 도장은 KST 자정에서 갈린다

// 도장이 월 단위였을 때 스냅샷과 현재값은 최대 한 달까지 벌어졌다(음수 정정량 사고의 원인).
// 날짜 단위가 실제로 **하루**를 뜻하는지 — 같은 KST 날 안이면 몇 시든 같고, 자정을 넘기면 달라진다 —
// 를 벽시계 시각으로 확인한다. 빌드 축도 함께 살아 있어야 산식 재배포가 관측된다.
@MainActor
@Test
func codexDiagStampSplitsAtKSTMidnightAndTracksBuild() {
    let noon = WorkTimerStore.codexDiagnosticsStamp(build: 41, now: kst(2026, 8, 18, 12, 0))
    let lastMinute = WorkTimerStore.codexDiagnosticsStamp(build: 41, now: kst(2026, 8, 18, 23, 59))
    let nextMidnight = WorkTimerStore.codexDiagnosticsStamp(build: 41, now: kst(2026, 8, 19, 0, 0))
    let newerBuild = WorkTimerStore.codexDiagnosticsStamp(build: 42, now: kst(2026, 8, 18, 12, 0))

    #expect(noon == "41:2026-08-18")
    // 같은 KST 날 안이면 11시간 59분이 지나도 같은 도장 → 하루에 한 번만 스캔한다.
    #expect(noon == lastMinute)
    // 1분 뒤 자정을 넘으면 갈린다 → 다음 날 표본이 쌓인다(시계열이 서야 재발을 본다).
    #expect(nextMidnight == "41:2026-08-19")
    #expect(nextMidnight != lastMinute)
    // 빌드가 오르면 같은 날이라도 다시 보고한다(어느 산식이 만든 숫자인지가 진단의 절반이다).
    #expect(newerBuild == "42:2026-08-18")
    #expect(newerBuild != noon)

    // 날짜의 출처는 단 하나 — 스캐너의 KST 하루 경계. 도장이 여기서 따로 날짜를 계산하기 시작하면
    // 업로드한 행의 today_date 와 도장의 날짜가 어긋난다.
    #expect(noon.hasSuffix(TokenUsageIncrementalScanner.dayBounds(now: kst(2026, 8, 18, 12, 0)).date))
    #expect(nextMidnight.hasSuffix(TokenUsageIncrementalScanner.dayBounds(now: kst(2026, 8, 19, 0, 0)).date))
}

// MARK: - 4. 도장이 스캔을 실제로 막는다(빌드 × KST 날짜)

// 도장은 장식이 아니라 **전량 순회를 건너뛰는 게이트**다(실측 444파일 0.39초 — 30초마다 치를 비용이 아니다).
// 다섯 상황을 한 줄에 세워 스캔이 일어난 횟수만 센다: 첫 호출 1 / 같은 빌드·같은 날 0 / 다음날 1 /
// 빌드 상승 1 / 빌드 미상 0. 총 3회.
//
// 도장은 프로덕션 순서대로 **스캔이 실제로 일어난 뒤에만** 찍는다(업로드 성공 → 도장). 여기서 미리 찍어 버리면
// "게이트가 막았다"와 "아직 안 찍혔다"를 구분할 수 없다.
@MainActor
@Test
func codexDiagScansOncePerBuildAndKSTDay() async {
    let store = makeStore(host: "codex-diag-scan-count", build: 41)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
    }

    var scans = 0
    func attempt(month: String, now: Date) async {
        if await store.codexDiagnosticsIfUnreported(month: month, now: now) != nil { scans += 1 }
    }
    func stamp(build: Int, now: Date) {
        store.defaults.set(
            WorkTimerStore.codexDiagnosticsStamp(build: build, now: now),
            forKey: WorkTimerStore.codexDiagnosticsReportedStampKey
        )
    }

    let day1Noon = kst(2026, 8, 18, 12, 0)
    let day1Late = kst(2026, 8, 18, 23, 59)
    let day2 = kst(2026, 8, 19, 0, 1)

    // 1) 도장이 없다 → 스캔한다.
    await attempt(month: "2026-08", now: day1Noon)
    #expect(scans == 1)
    stamp(build: 41, now: day1Noon)

    // 2~3) 같은 빌드·같은 KST 날이면 몇 번을 불러도 스캔하지 않는다(23:59 도 아직 같은 날).
    await attempt(month: "2026-08", now: day1Noon)
    await attempt(month: "2026-08", now: day1Late)
    #expect(scans == 1)

    // 4) 날이 바뀌면 다시 스캔한다.
    await attempt(month: "2026-08", now: day2)
    #expect(scans == 2)
    stamp(build: 41, now: day2)
    await attempt(month: "2026-08", now: day2)
    #expect(scans == 2)

    // 5) 같은 날이라도 빌드가 오르면 다시 스캔한다.
    store.appVersionProvider = { AppVersionReport(build: 42, version: "0.2.34") }
    await attempt(month: "2026-08", now: day2)
    #expect(scans == 3)
    stamp(build: 42, now: day2)
    await attempt(month: "2026-08", now: day2)
    #expect(scans == 3)

    // 6) 빌드를 모르면(개발 빌드 등) 계산하지 않는다 — 출처 없는 숫자는 코호트를 오염시킨다.
    store.appVersionProvider = { nil }
    await attempt(month: "2026-08", now: day2)
    #expect(scans == 3)

    #expect(store.defaults.string(forKey: WorkTimerStore.codexDiagnosticsReportedStampKey) == "42:2026-08-19")
}

// MARK: - 5. 스냅샷은 평상시 업로드에 덮이지 않는다 ★ 이 설계의 핵심

// 연속 업로드 6회의 진단키수가 [19, 0, 0, 0, 19, 0] 이어야 한다.
//   · #1 — 오늘 첫 업로드: 진단 19키 + 그 순간의 Codex 총합 스냅샷.
//   · #2~#4 — 같은 날 평상시 업로드: codex_input 은 자라지만 **codex_diag_* 는 키 자체가 없다**.
//     본문에 없으면 PostgREST 가 그 컬럼을 건드리지 않으므로 서버의 스냅샷은 #1 시점 값으로 얼어 있다.
//     이것이 `codex_diag_legacy_total − codex_diag_input_at_scan` 을 같은 시각의 뺄셈으로 만든다.
//   · #5 — 날이 바뀌어 다시 진단. 스냅샷도 그날 값으로 함께 갱신된다(두 값은 항상 같은 순간에서 온다).
// 만약 스냅샷이 옵셔널이 아니면 이 수열은 [19,1,1,1,19,1] 이 되고 스냅샷은 매번 codex_input 과 같아진다 —
// 그러면 이 컬럼을 더한 이유가 통째로 사라진다.
@MainActor
@Test
func codexDiagSnapshotIsNotOverwrittenByPlainUploads() async {
    let host = "codex-diag-snapshot-sequence"
    let store = makeStore(host: host, build: 41)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
    }

    var codex = 1_000
    func upload(_ now: Date) async {
        // 매번 값을 키운다 — 변경 게이트를 통과시키면서, 스냅샷이 '얼어 있음'을 눈에 보이게 한다.
        codex += 777
        await store.uploadTokenUsageIfNeeded(
            usage: TokenUsageMonthly(
                month: "2026-08", claudeInput: 100, codexInput: codex,
                todayTotal: 3, todayDate: "2026-08-18"
            ),
            now: now
        )
    }

    let day1 = kst(2026, 8, 18, 12, 0)
    await upload(day1)                              // #1 진단 동봉
    await upload(day1.addingTimeInterval(70))       // #2 평상시(60초 스로틀 통과)
    await upload(day1.addingTimeInterval(140))      // #3 평상시
    await upload(day1.addingTimeInterval(210))      // #4 평상시
    let day2 = kst(2026, 8, 19, 9, 0)
    await upload(day2)                              // #5 날이 바뀌어 다시 진단
    await upload(day2.addingTimeInterval(70))       // #6 평상시

    let bodies = deviceUploadBodies(host: host, deviceID: store.deviceID)
    #expect(bodies.count == 6)
    #expect(bodies.map(diagKeyCount) == [19, 0, 0, 0, 19, 0])

    // 진단이 실린 두 본문에서만 스냅샷이 **그 본문의 codex_input 과 같다**(= 같은 순간의 값).
    let snapshots: [Int?] = bodies.map { body in
        let object = (try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? [String: Any] ?? [:]
        return object["codex_diag_input_at_scan"] as? Int
    }
    let inputs: [Int?] = bodies.map { body in
        let object = (try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? [String: Any] ?? [:]
        return object["codex_input"] as? Int
    }
    #expect(snapshots.compactMap { $0 }.count == 2)
    #expect(snapshots[0] == inputs[0])
    #expect(snapshots[4] == inputs[4])
    // 평상시 업로드는 스냅샷 키를 아예 싣지 않는다(0 을 싣는 것과 다르다 — 0 이면 서버 값을 0 으로 덮는다).
    #expect(snapshots[1] == nil && snapshots[2] == nil && snapshots[3] == nil && snapshots[5] == nil)
    // codex_input 은 그 사이에도 계속 자랐다 — '얼어 있는 스냅샷 vs 자라는 현재값'이 바로 사고의 구도다.
    #expect(inputs[0]! < inputs[3]!)
    #expect(inputs[4]! < inputs[5]!)

    #expect(store.defaults.string(forKey: WorkTimerStore.codexDiagnosticsReportedStampKey) == "41:2026-08-19")
}

// MARK: - 6. 업로드가 실패하면 도장을 찍지 않는다(다음 기회에 다시 계산·전송)

// 도장은 서버 쓰기가 실제로 성공했을 때만 찍힌다. 만약 스캔 직후에 찍는다면, 마이그레이션 미적용(404)이나
// 네트워크 단절로 실패한 날의 진단은 영영 사라진다 — 정작 진단이 가장 필요한 상황에서 표본이 비는 셈이다.
// 실패 두 번이면 진단키수는 [19, 19] 이고 도장은 계속 nil 이어야 한다.
@MainActor
@Test
func codexDiagLeavesNoStampWhenUploadFailsAndRecomputesNextTime() async {
    // 스텁이 이 호스트의 token_usage_device_monthly POST 만 404(PGRST205)로 거부한다.
    // 다른 스위트도 같은 호스트를 쓰므로 본문은 이 스토어의 deviceID 로 걸러 읽는다.
    let host = "device-table-missing"
    let store = makeStore(host: host, build: 41)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
    }

    let day1 = kst(2026, 8, 18, 12, 0)
    await store.uploadTokenUsageIfNeeded(
        usage: TokenUsageMonthly(month: "2026-08", claudeInput: 100, codexInput: 2_000), now: day1
    )
    let stampAfterFirst = store.defaults.string(forKey: WorkTimerStore.codexDiagnosticsReportedStampKey)

    await store.uploadTokenUsageIfNeeded(
        usage: TokenUsageMonthly(month: "2026-08", claudeInput: 100, codexInput: 3_000),
        now: day1.addingTimeInterval(70)
    )
    let stampAfterSecond = store.defaults.string(forKey: WorkTimerStore.codexDiagnosticsReportedStampKey)

    #expect(stampAfterFirst == nil)
    #expect(stampAfterSecond == nil)

    // 도장이 없으니 두 번 다 진단을 새로 계산해 실어 보냈다.
    let bodies = deviceUploadBodies(host: host, deviceID: store.deviceID)
    #expect(bodies.count == 2)
    #expect(bodies.map(diagKeyCount) == [19, 19])
    // 실패 경로가 조용히 삼켜지지 않았다는 대조 신호(스키마 부재는 화면 문구로 드러난다).
    #expect(store.syncMessage == "DB 스키마 필요")
}

// MARK: - 7. 수집 거부자에게선 스캔도 업로드도 도장도 없다

// 진단 계산은 **홈 디렉터리 전량 순회**다. 수집을 거부한 사람에게 그 순회가 도는 것은 업로드가 나가는 것과
// 같은 무게의 위반이고, 서버 트리거가 행을 버려 주는 것과는 별개 문제다(순회는 이 맥에서 이미 일어난다).
// 그래서 `guard tokenUsageCollect` 가 진단 호출보다 **앞**에 있어야 한다.
// 요청 0건·도장 nil 로 결과를 보고, 소요 시간으로 순회가 돌지 않았음을 함께 본다(전량 패스는 실측 0.39초라
// 이 예산 안에 절대 못 끝난다). 대조군으로 '켜면 그대로 올라간다'를 붙여 게이트가 전원을 죽이지 않음을 고정한다.
@MainActor
@Test
func codexDiagSkipsScanAndUploadWhenCollectionIsOff() async {
    let host = "codex-diag-collect-off"
    let store = makeStore(host: host, build: 41)
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
    }
    store.tokenUsageCollect = false

    let day1 = kst(2026, 8, 18, 12, 0)
    let started = Date()
    await store.uploadTokenUsageIfNeeded(
        usage: TokenUsageMonthly(month: "2026-08", claudeInput: 100, codexInput: 5_000), now: day1
    )
    let elapsed = Date().timeIntervalSince(started)

    #expect(URLProtocolStub.requests(forHost: host).isEmpty)
    #expect(store.defaults.string(forKey: WorkTimerStore.codexDiagnosticsReportedStampKey) == nil)
    // 전량 순회가 돌았다면 이 시간에 못 끝난다 — '계산도 안 했다'의 증거.
    // 예산 0.2초는 전량 패스 실측(444파일 0.39초)의 절반이라 스캔을 확실히 배제하면서,
    // 가드 하나만 통과하는 이 경로가 부하로 느려져도 헛되이 붉어지지 않을 만큼 넉넉하다.
    #expect(elapsed < 0.2)

    // 대조군: 다시 켜면 진단이 실려 정상적으로 나간다(게이트가 한 방향으로만 막는다).
    store.tokenUsageCollect = true
    await store.uploadTokenUsageIfNeeded(
        usage: TokenUsageMonthly(month: "2026-08", claudeInput: 100, codexInput: 6_000),
        now: day1.addingTimeInterval(70)
    )
    let bodies = deviceUploadBodies(host: host, deviceID: store.deviceID)
    #expect(bodies.count == 1)
    #expect(bodies.map(diagKeyCount) == [19])
    #expect(store.defaults.string(forKey: WorkTimerStore.codexDiagnosticsReportedStampKey) == "41:2026-08-18")
}
