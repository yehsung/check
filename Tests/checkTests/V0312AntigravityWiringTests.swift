import AppKit
import Foundation
import SQLite3
import SwiftUI
import Testing
@testable import check

// MARK: - v0.3.12: 안티그래비티를 스토어·업로드·표시에 꽂은 것의 회귀 그물
//
// 앞 단계가 만든 것은 **파서까지**였다(CheckAntigravityUsage.swift — 경로를 주면 숫자를 준다).
// 이 파일이 지키는 것은 그 숫자가 흘러가는 네 자리다.
//
//   ① 집계   — TokenUsageIncrementalScanner 가 세 번째 소스를 합류시키되 `total`·`todayTotal` 은 건드리지 않는다.
//   ② 영속   — TokenUsageMonthly 의 새 필드가 CodingKeys·init(decoder)·encode 세 곳에 다 있고, 옛 스냅샷은 0 으로 복원된다.
//   ③ 업로드 — 같은 upsert **한 번**에 네 키가 얹히고, 안 쓰는 사람 본문에는 네 키가 **하나도** 없다.
//   ④ 표시   — 굵은 총합이 서버 순위판 산식과 **같은 답**을 내고, 좁은 캡션은 폭 실측이 허락하는 것만 싣는다.
//
// 규약의 출처(바꾸기 전에 읽어라):
//   · 서버 컬럼/산식: supabase/migrations/20260911120000_antigravity_usage.sql
//     total = claude_total + codex_effective + antigravity_total (device_final) · 일별 antigravity_total 은 저장 전용.
//   · 실측 사실: gen_metadata 블롭·stdout 대조는 앞 단계의 facts.md 와 V0312AntigravityUsageTests 가 이미 못 박았다.
//     여기서는 그 값이 **스토어를 통과해** 같은 숫자로 나오는지만 본다(두 대 프로브 대신 실파일 한 벌 대조).

// MARK: - 공용 픽스처

/// 얼린 기준 시각(1,789,000,000) = KST 2026-09-10 09:26 → 월 "2026-09" · 날짜 "2026-09-10".
/// 자정에서 9시간 이상 떨어져 있어 KST/UTC 어느 쪽으로 읽어도 날짜가 흔들리지 않는다.
private let agNow = Date(timeIntervalSince1970: 1_789_000_000)
private var agMonth: String { TokenUsageIncrementalScanner.kstMonthString(agNow) }
private var agDay: String { TokenUsageIncrementalScanner.dayBounds(now: agNow).date }

private func agTempDir(_ tag: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("check-v0312-\(tag)-\(UUID().uuidString)", isDirectory: true)
}

private func agDefaults() -> UserDefaults {
    let name = "check-v0312-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

/// 세 종류가 다 찬 월 집계. 값은 자릿수가 서로 달라(클로드 10자리·Codex 9자리·안티 5자리) 합이 우연히 맞는 일이 없다.
private func agUsage(
    claudeInput: Int = 1_000_000_000, claudeOutput: Int = 200_000_000,
    claudeCacheRead: Int = 30_000_000, claudeCacheCreation: Int = 4_000_000,
    codexInput: Int = 500_000_000, codexOutput: Int = 60_000_000, codexCacheRead: Int = 7_000_000,
    antigravityInput: Int = 26_275, antigravityOutput: Int = 81,
    antigravityThinking: Int = 66, antigravityCacheRead: Int = 16_254,
    antigravityDaily: [String: Int] = [:],
    todayTotal: Int = 0, todayDate: String = "",
    claudeDaily: [String: Int] = [:], codexDaily: [String: Int] = [:], codexDailyUTC: [String: Int] = [:],
    windowStart: String = "", claudeCompleteFrom: String = ""
) -> TokenUsageMonthly {
    var usage = TokenUsageMonthly(month: agMonth)
    usage.claudeInput = claudeInput
    usage.claudeOutput = claudeOutput
    usage.claudeCacheRead = claudeCacheRead
    usage.claudeCacheCreation = claudeCacheCreation
    usage.codexInput = codexInput
    usage.codexOutput = codexOutput
    usage.codexCacheRead = codexCacheRead
    usage.antigravityInput = antigravityInput
    usage.antigravityOutput = antigravityOutput
    usage.antigravityThinking = antigravityThinking
    usage.antigravityCacheRead = antigravityCacheRead
    usage.antigravityDaily = antigravityDaily
    usage.todayTotal = todayTotal
    usage.todayDate = todayDate
    usage.claudeDaily = claudeDaily
    usage.codexDaily = codexDaily
    usage.codexDailyUTC = codexDailyUTC
    usage.windowStart = windowStart
    usage.claudeCompleteFrom = claudeCompleteFrom
    return usage
}

/// 합성 gen_metadata 블롭(최소형). 파서 단위 테스트가 모양을 이미 못 박았으므로 여기서는 "값이 흐르는가"만 본다 —
/// 최상위 1 → 사용량 4 → varint 2/3/5/9. (풍부한 합성은 V0312AntigravityUsageTests 의 v0312Row 가 한다.)
private func agSyntheticGenRow(input: Int, output: Int, thinking: Int, cacheRead: Int) -> [UInt8] {
    func varint(_ v: Int) -> [UInt8] {
        var out = [UInt8](), x = UInt64(v)
        repeat {
            var b = UInt8(x & 0x7F); x >>= 7
            if x != 0 { b |= 0x80 }
            out.append(b)
        } while x != 0
        return out
    }
    func num(_ field: Int, _ value: Int) -> [UInt8] { varint(field << 3) + varint(value) }
    func msg(_ field: Int, _ payload: [UInt8]) -> [UInt8] {
        varint(field << 3 | 2) + varint(payload.count) + payload
    }
    let usage = num(AntigravityGenMetadataParser.inputTokensField, input)
        + num(AntigravityGenMetadataParser.outputTokensField, output)
        + num(AntigravityGenMetadataParser.cacheReadTokensField, cacheRead)
        + num(AntigravityGenMetadataParser.thinkingTokensField, thinking)
    return msg(
        AntigravityGenMetadataParser.genField,
        msg(AntigravityGenMetadataParser.usageField, usage)
    )
}

private let agSQLiteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

// MARK: - ① 집계 합류 · 총합 규약

/// 안티그래비티 소계는 **네 값 전부**(캐시읽기 포함)다 — 서버가 네 컬럼을 그냥 더하기 때문이고,
/// 그 정의가 갈리면 화면의 굵은 총합이 순위판의 내 행과 어긋난다.
///
/// 같은 자리에서 **업로드값 total 과 todayTotal 에는 안 들어간다**는 것도 함께 못 박는다.
/// 그 둘은 서버가 '옛 표와 같은 단위'로 읽는 값이고(legacy_live·prefer_device·token_scan_health),
/// today 는 서버에서 fork_safe/tail_factor 축소를 타므로 섞으면 계정 스냅샷과 무관한 값이 근거 없이 깎인다.
@Test
func v0312AntigravitySubtotalIncludesCacheReadButUploadTotalsDoNot() {
    let usage = agUsage(todayTotal: 123_456, todayDate: agDay)

    #expect(usage.antigravityTotal == 26_275 + 81 + 66 + 16_254)
    #expect(usage.antigravityTotal == 42_676)

    // 업로드값 total = 클로드 4 + Codex 2. 안티그래비티는 한 톨도 없다.
    #expect(usage.total == 1_000_000_000 + 200_000_000 + 30_000_000 + 4_000_000 + 500_000_000 + 60_000_000)
    #expect(usage.total == usage.claudeTotal + usage.codexTotal)
    // 대조군: 안티그래비티를 0 으로 바꿔도 total 이 같다(= total 이 그 값을 읽지 않는다).
    var noAG = usage
    noAG.antigravityInput = 0; noAG.antigravityOutput = 0
    noAG.antigravityThinking = 0; noAG.antigravityCacheRead = 0
    #expect(noAG.total == usage.total)
    #expect(noAG.antigravityTotal == 0)
    // today 도 그대로다(스캐너가 넣지 않는다는 사실은 아래 실파일 대조가 한 번 더 확인한다).
    #expect(usage.todayTotal == 123_456)
}

/// 굵은 총합 = 서버 순위판 산식의 **쌍둥이**.
/// SQL: `total = claude_total + codex_effective + antigravity_total` (20260911120000 device_final)
/// Swift: `displayTotal(account:)` = TokenUsageDisplay.effectiveTotal(= claudeTotal + codexEffective) + antigravityTotal
/// 두 식이 갈리면 내 박스의 숫자와 순위판의 내 행이 어긋나고, 사용자는 어느 쪽이 맞는지 가릴 방법이 없다.
@Test
func v0312DisplayTotalIsTheTwinOfTheServerBoardFormula() {
    let usage = agUsage()

    // ⓐ 계정 스냅샷이 없을 때: codex_effective = 로컬 합.
    let noAccount = usage.displayTotal(account: nil)
    #expect(noAccount == usage.claudeTotal + usage.codexTotal + usage.antigravityTotal)

    // ⓑ 계정 스냅샷이 있을 때도 안티그래비티는 **그대로 더해진다**(축소율·fork_safe 게이트를 타지 않는다 —
    //    안티그래비티에는 '계정값'이라는 두 번째 출처가 아예 없어 그 산식이 풀 문제가 존재하지 않는다).
    let account = CodexAccountUsage(
        fetchedAt: agNow, lifetimeTokens: 900_000_000,
        buckets: [agDay: 100_000_000, "2026-09-08": 200_000_000]
    )
    let codexEffective = TokenUsageDisplay.codexEffective(local: usage, account: account)
    #expect(usage.displayTotal(account: account) == usage.claudeTotal + codexEffective + usage.antigravityTotal)
    // 계정이 붙으면 Codex 몫이 실제로 달라진다 — 그래야 위 단언이 "같은 입력 두 번"이 아니다.
    #expect(codexEffective != usage.codexTotal)

    // ⓒ 안티그래비티가 0 인 사람의 총합은 이 변경 전과 **글자 하나 다르지 않다**.
    var noAG = usage
    noAG.antigravityInput = 0; noAG.antigravityOutput = 0
    noAG.antigravityThinking = 0; noAG.antigravityCacheRead = 0
    #expect(noAG.displayTotal(account: account) == TokenUsageDisplay.effectiveTotal(local: noAG, account: account))
}

// MARK: - ② 영속(하위호환)

/// 새 필드가 **CodingKeys·init(decoder)·encode 세 곳에 다 있다**. 한 곳만 빠지면 증상이 제각각이라 셋을 한 번에 잰다:
///  · CodingKeys 누락 → 컴파일 에러(여기서 못 잡는다)
///  · encode 누락     → 저장은 되는데 재시작하면 0 (조용한 손실)
///  · decode 누락     → 컴파일 에러
/// 그리고 **옛 스냅샷**(키가 아예 없는 JSON)은 던지지 않고 0 으로 복원돼야 한다 — 던지면 그 사람의 월 집계가
/// 통째로 폐기되고 재스캔까지 화면이 빈다.
@Test
func v0312MonthlySnapshotRoundTripsAndOldSnapshotsDecodeToZero() throws {
    let usage = agUsage(antigravityDaily: [agDay: 26_422], todayTotal: 7, todayDate: agDay)
    let data = try JSONEncoder().encode(usage)

    // 인코딩 결과에 네 키 + 일별 맵이 실제로 있다(encode 누락 방어).
    let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(object["antigravityInput"] as? Int == 26_275)
    #expect(object["antigravityOutput"] as? Int == 81)
    #expect(object["antigravityThinking"] as? Int == 66)
    #expect(object["antigravityCacheRead"] as? Int == 16_254)
    #expect((object["antigravityDaily"] as? [String: Int])?[agDay] == 26_422)

    let restored = try JSONDecoder().decode(TokenUsageMonthly.self, from: data)
    #expect(restored == usage)

    // 옛 스냅샷(v0.3.11 이하): 키가 하나도 없다 → 0/빈 맵. 나머지 필드는 그대로 살아야 한다.
    var legacy = object
    for key in ["antigravityInput", "antigravityOutput", "antigravityThinking", "antigravityCacheRead", "antigravityDaily"] {
        legacy.removeValue(forKey: key)
    }
    let legacyData = try JSONSerialization.data(withJSONObject: legacy)
    let legacyRestored = try JSONDecoder().decode(TokenUsageMonthly.self, from: legacyData)
    #expect(legacyRestored.antigravityTotal == 0)
    #expect(legacyRestored.antigravityDaily.isEmpty)
    #expect(legacyRestored.total == usage.total, "옛 스냅샷의 나머지 값이 함께 사라졌다")
    #expect(legacyRestored.claudeDaily == usage.claudeDaily)
}

/// 증분 캐시도 같은 규약이다: 옛 캐시 파일엔 안티그래비티 상태 키가 없고, 그때 **빈 맵**으로 떨어져야 한다
/// (= 안티그래비티만 1회 전량 파싱). 여기서 레이아웃 버전을 올려 해결하려 들면 Claude 엔트리·Codex 상태까지
/// 통째로 버려져 **전체 재파싱 1회**(내 맥 실측 1,892파일/1.2GB)가 딸려 온다 — 그래서 올리지 않았다.
@Test
func v0312CacheKeepsClaudeAndCodexStatesWhenAntigravityStateIsAbsent() throws {
    var cache = TokenUsageCache()
    cache.claudeFileStates["/a.jsonl"] = FileProgress(size: 10, mtimeMicros: 20, consumedOffset: 5)
    cache.antigravityFileStates["/x.db"] = AntigravityFileProgress(
        size: 1_024, mtimeMicros: 30, lastIdx: 3, monthKey: agMonth,
        monthInput: 1, monthOutput: 2, monthThinking: 3, monthCacheRead: 4,
        dayContrib: [agDay: 6], modelContrib: ["gemini-3.8-flash": 6]
    )
    let data = try JSONEncoder().encode(cache)
    let restored = try JSONDecoder().decode(TokenUsageCache.self, from: data)
    #expect(restored.antigravityFileStates["/x.db"] == cache.antigravityFileStates["/x.db"])
    #expect(restored.claudeFileStates["/a.jsonl"] == cache.claudeFileStates["/a.jsonl"])

    // 옛 캐시: antigravityFileStates 키가 통째로 없다 → 빈 맵 + Claude 상태 보존(= Claude 재파싱 없음).
    var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    object.removeValue(forKey: "antigravityFileStates")
    let legacy = try JSONDecoder().decode(
        TokenUsageCache.self, from: try JSONSerialization.data(withJSONObject: object)
    )
    #expect(legacy.antigravityFileStates.isEmpty)
    #expect(legacy.claudeFileStates["/a.jsonl"] == cache.claudeFileStates["/a.jsonl"],
            "안티그래비티 키가 없다고 Claude 상태까지 버렸다 — 전체 재파싱이 딸려 온다")
    // 캐시 레이아웃 세대는 v0.2.43 의 2 그대로다(올리는 순간이 곧 전체 재파싱이다).
    #expect(TokenUsageCacheStore.currentSchemaVersion == 2)
}

// MARK: - ① 실데이터 대조 (이 맥의 대화 db 두 건)

/// 실측 픽스처(facts.md 2026-09-11) 두 건의 stdout 값.
///   4bc6f72b… : 제미나이 1턴  (5282 / 1 / 0 / 8128)
///   295b1ce6… : 클로드 1턴 + 제미나이 1턴, 행의 합 = (20993 / 80 / 66 / 8126)
private let agFixtureNames = [
    "4bc6f72b-74f0-44e1-a56e-771d9a2a5e93.db",
    "295b1ce6-2806-4de1-a282-ba903278ac63.db"
]
/// 디렉터리의 파일 이름 목록(정렬). "실제 폴더가 그대로인가"를 이름 몇 개가 아니라 목록 전체로 잰다.
private func agRealListing(_ url: URL) -> [String] {
    ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []).sorted()
}

private let agFixtureInput = 5_282 + 20_993
private let agFixtureOutput = 1 + 80
private let agFixtureThinking = 0 + 66
private let agFixtureCacheRead = 8_128 + 8_126

/// **스토어를 통과한 숫자가 stdout 실측과 같은가.** 파서 단위 테스트가 이미 행 파싱을 못 박았으므로 여기서 재는 것은
/// 합류 배선이다: 세 소스를 도는 `TokenUsageIncrementalScanner.update` 가 네 값을 제자리에 넣고, `total`·`todayTotal`
/// 은 건드리지 않고, 일별 맵이 KST 오늘 키에 붙는가.
///
/// 픽스처는 실파일을 **복사**해 쓴다. 원본은 `stat`·`copyItem` 말고는 손대지 않는다 — ⚠️ **실제 폴더를 sqlite 로
/// 열면 안 된다**: 1단(READONLY)은 `-wal` 이 있는 db 를 읽을 때 그 디렉터리에 `-shm` 을 만든다
/// (자세한 사실관계는 `AntigravityConversationReader` 의 §사이드카의 사실관계, 규약은
///  `V0312AntigravityUsageTests.swift` 머리말 §규칙). 아래 `agRealListing` 전후 비교가 그 규약을 지킨다.
/// 이 맥이 아니면(파일 없음) 조용히 건너뛴다.
@Test
func v0312ScannerJoinsAntigravityWithTheRealConversationFixtures() throws {
    let source = AntigravityUsageScanner.conversationsDirectory(
        homeDirectory: FileManager.default.homeDirectoryForCurrentUser
    )
    // 복사 직전 실제 폴더의 파일 목록. 테스트가 끝날 때 그대로여야 한다.
    let realBefore = agRealListing(source)
    defer {
        #expect(agRealListing(source) == realBefore,
                "사용자의 실제 conversations/ 에 파일이 생겼거나 사라졌다 — 실파일은 복사만 해야 한다")
    }
    let available = agFixtureNames.filter {
        FileManager.default.fileExists(atPath: source.appendingPathComponent($0).path)
    }
    guard available.count == agFixtureNames.count else { return }

    let home = agTempDir("real-fixture-home")
    defer { try? FileManager.default.removeItem(at: home) }
    let dest = AntigravityUsageScanner.conversationsDirectory(homeDirectory: home)
    try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
    for name in available {
        // ★ **`.db` 만** 복사한다 — `-wal`·`-shm` 은 일부러 두고 온다.
        //   `agy` 가 정상 종료하면 사이드카가 없고(2026-09-11 실측: 새로 만든 대화에 -wal/-shm 이 없었다),
        //   그것이 **깨끗한 사용자 맥의 정상 상태**다. v0.3.12 초판은 그 상태를 읽지 못해(prepare 가 CANTOPEN)
        //   그런 사람의 집계가 통째로 0 이었고, 여기서 사이드카까지 복사한 탓에 그 사실이 초록 뒤에 숨었다.
        //   이제는 사이드카 없이도 같은 값이 나와야 한다(2단 immutable — AntigravityConversationReader 주석).
        try FileManager.default.copyItem(at: source.appendingPathComponent(name), to: dest.appendingPathComponent(name))
        // mtime = 기준 시각. 귀속 시각이 min(mtime, now) 이라 이 값이 곧 KST 귀속 날짜다(월 프리필터도 이걸 본다).
        try FileManager.default.setAttributes([.modificationDate: agNow], ofItemAtPath: dest.appendingPathComponent(name).path)
    }

    let result = TokenUsageIncrementalScanner.update(TokenUsageCache(), homeDirectory: home, now: agNow)
    let usage = result.usage

    #expect(usage.antigravityInput == agFixtureInput)
    #expect(usage.antigravityOutput == agFixtureOutput)
    #expect(usage.antigravityThinking == agFixtureThinking)
    #expect(usage.antigravityCacheRead == agFixtureCacheRead)
    #expect(usage.antigravityTotal == agFixtureInput + agFixtureOutput + agFixtureThinking + agFixtureCacheRead)
    #expect(usage.antigravityTotal == 42_676)

    // 이 홈에는 Claude/Codex 로그가 없다 — 그래서 업로드값 total 과 today 는 **0 이어야 한다**.
    // (안티그래비티가 섞였다면 42,676 이 여기 나타난다. 이 두 줄이 규약 ③④의 실물 증거다.)
    #expect(usage.total == 0)
    #expect(usage.todayTotal == 0)

    // 일별 맵은 KST 오늘 키에 붙고, 값은 월 합계와 **같은 정의**다(네 값 전부 — 캐시읽기 포함).
    // ★ 이 두 줄이 일/월 정의 통일의 실데이터 증거다. 한쪽만 되돌리면 26,422 vs 42,676 으로 갈라진다(38%).
    #expect(usage.antigravityDaily == [agDay: 42_676])
    #expect(usage.antigravityDaily.values.reduce(0, +) == usage.antigravityTotal)

    // 계측: 두 파일을 stat 하고 읽었으며 세 행을 먹었다(1턴 + 2턴).
    #expect(result.stats.antigravityFilesStatted == 2)
    #expect(result.stats.antigravityFilesRead == 2)
    #expect(result.stats.antigravityRowsIngested == 3)
    #expect(result.stats.antigravityRowsRejected == 0)
    #expect(result.stats.antigravityOpenFailures == 0, "대화 db 를 열지 못했다 — 그 파일의 토큰이 통째로 빠진다")
    #expect(result.stats.antigravityQueryFailures == 0)
    // 사이드카 없는 사본이므로 둘 다 2단으로 구해졌다. 1단으로 읽혔다면 이 테스트가 재현하려던 상태가 아니다.
    #expect(result.stats.antigravityImmutableReads == 2)
    #expect(!result.stats.antigravityBlind)
    #expect(result.stats.statesChanged)

    // 두 번째 스캔은 아무것도 더하지 않는다(증분 규약이 스토어 경로에서도 성립한다).
    let again = TokenUsageIncrementalScanner.update(result.cache, homeDirectory: home, now: agNow)
    #expect(again.usage.antigravityTotal == usage.antigravityTotal)
    #expect(again.stats.antigravityRowsIngested == 0)
}

/// ★ **눈먼 스캔이 진단에 남는가.** 못 읽은 대화 db 가 있는데 집계가 0 이면, 그 사실이 스캐너 계측과 스토어에
/// 남아야 한다. v0.3.12 초판은 사이드카 없는 WAL 의 CANTOPEN 을 '표 없음'으로 접어 넣어 `openFailures` 가 0 이었고,
/// 그래서 "집계 0 · 실패 0" 이라는 **완전한 침묵**이 됐다 — 원인을 가를 신호가 어디에도 없었다.
@MainActor
@Test
func v0312BlindAntigravityScanLeavesATrace() async throws {
    let home = agTempDir("blind-home")
    defer { try? FileManager.default.removeItem(at: home) }
    let dir = AntigravityUsageScanner.conversationsDirectory(homeDirectory: home)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

    // gen_metadata 가 없는 db 하나. 열리긴 열리지만 우리가 읽을 표가 없다 → 질의 실패 1 · 집계 0.
    let foreign = dir.appendingPathComponent("not-a-conversation.db")
    var db: OpaquePointer?
    _ = foreign.path.withCString { sqlite3_open_v2($0, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) }
    sqlite3_exec(db, "create table other (a integer)", nil, nil, nil)
    sqlite3_close(db)
    try FileManager.default.setAttributes([.modificationDate: agNow], ofItemAtPath: foreign.path)

    let blind = TokenUsageIncrementalScanner.update(TokenUsageCache(), homeDirectory: home, now: agNow)
    #expect(blind.stats.antigravityQueryFailures == 1)
    #expect(blind.stats.antigravityOpenFailures == 0, "질의 실패가 열기 칸에 섞였다 — 둘을 가른 의미가 없어진다")
    #expect(blind.usage.antigravityTotal == 0)
    #expect(blind.stats.antigravityBlind, "못 읽은 파일이 있는데 집계가 0 인 사실이 어디에도 안 남았다")

    // 스토어까지 그 사실이 흐른다(로그로 나가는 값이 여기 남는다). 게이트는 짝으로 있어야 한다 —
    // 스캐너만 고치고 스토어가 안 읽으면 진단은 여전히 침묵이다.
    let store = TokenUsageStore(
        defaults: agDefaults(),
        homeDirectory: home,
        cacheURL: agTempDir("blind-cache").appendingPathComponent("c.json"),
        clock: { agNow },
        notificationCenter: NotificationCenter()
    )
    await store.refreshNow()
    await store.awaitScanCompletion()
    #expect(store.lastScanAntigravityBlind)
    #expect(store.lastScanAntigravityImmutableReads == 0)

    // 대조군: 읽히는 대화 db 가 하나라도 있으면 눈먼 스캔이 아니다(실패 수만 세면 이 구분이 안 된다).
    let good = dir.appendingPathComponent("conv-ok.db")
    var db2: OpaquePointer?
    _ = good.path.withCString { sqlite3_open_v2($0, &db2, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) }
    sqlite3_exec(db2, "create table gen_metadata (`idx` integer primary key, `data` blob, `size` integer not null default 0)", nil, nil, nil)
    sqlite3_close(db2)
    // 본문은 파서가 거부해도 상관없다 — 여기서 재는 것은 '집계 0 여부'가 아니라 이 테스트의 대조 축이다.
    // 그래서 실제 값이 들어간 행을 하나 넣는다.
    var db3: OpaquePointer?
    _ = good.path.withCString { sqlite3_open_v2($0, &db3, SQLITE_OPEN_READWRITE, nil) }
    var stmt: OpaquePointer?
    sqlite3_prepare_v2(db3, "insert into gen_metadata (idx, data, size) values (0, ?, 0)", -1, &stmt, nil)
    let blob = agSyntheticGenRow(input: 11, output: 3, thinking: 1, cacheRead: 5)
    blob.withUnsafeBytes { _ = sqlite3_bind_blob(stmt, 1, $0.baseAddress, Int32($0.count), agSQLiteTransient) }
    #expect(sqlite3_step(stmt) == SQLITE_DONE)
    sqlite3_finalize(stmt)
    sqlite3_close(db3)
    try FileManager.default.setAttributes([.modificationDate: agNow], ofItemAtPath: good.path)

    let mixed = TokenUsageIncrementalScanner.update(TokenUsageCache(), homeDirectory: home, now: agNow)
    #expect(mixed.usage.antigravityTotal == 20)
    #expect(mixed.stats.antigravityQueryFailures == 1)
    #expect(!mixed.stats.antigravityBlind, "실패는 있었지만 값이 나왔다 — 눈먼 스캔이 아니다")
}

/// 안티그래비티가 **없는** 홈에서는 이 변경 전과 완전히 같다 — 새 소스가 남의 숫자를 건드리지 않는다는 대조군.
@Test
func v0312ScannerLeavesEverythingUntouchedWhenAntigravityIsNotInstalled() {
    let home = agTempDir("no-antigravity-home")
    defer { try? FileManager.default.removeItem(at: home) }
    let result = TokenUsageIncrementalScanner.update(TokenUsageCache(), homeDirectory: home, now: agNow)
    #expect(result.usage.antigravityTotal == 0)
    #expect(result.usage.antigravityDaily.isEmpty)
    #expect(result.stats.antigravityFilesStatted == 0)
    #expect(result.cache.antigravityFileStates.isEmpty)
    // 상태가 안 바뀌었으니 저장을 유도하지도 않는다(디렉터리 없음이 매 스캔 디스크 쓰기를 만들면 안 된다).
    #expect(!result.stats.statesChanged)
}

// MARK: - ③ 업로드 본문 (월간 · 요청 수 그대로)

/// 월 upsert 본문의 **키 집합**을 문자 그대로 못 박는다.
///  · 쓰는 사람: antigravity_* 네 키가 **함께** 실리고 값이 집계와 같다. `total` 은 안티그래비티를 뺀 값 그대로다.
///  · 안 쓰는 사람: 네 키가 **하나도** 없다 → 서버에 컬럼이 아직 없어도(배포 순서가 어긋나도) 그 사람의 업로드는
///    종전과 바이트 단위로 같아 400 이 날 일이 없다. 이 기능이 남의 사용량을 멈추지 못한다는 보장이다.
@Test
func v0312MonthlyUpsertBodyCarriesTheFourKeysTogetherOrNotAtAll() throws {
    let encoder = JSONEncoder()
    encoder.keyEncodingStrategy = .convertToSnakeCase

    func body(_ usage: TokenUsageMonthly) throws -> [String: Any] {
        let request = TokenUsageUpsertRequest(
            userId: "u1", month: usage.month, deviceId: "dev-1",
            claudeInput: usage.claudeInput, claudeOutput: usage.claudeOutput,
            claudeCacheRead: usage.claudeCacheRead, claudeCacheCreation: usage.claudeCacheCreation,
            codexInput: usage.codexInput, codexOutput: usage.codexOutput,
            total: usage.total, todayTotal: usage.todayTotal, todayDate: usage.todayDate,
            codexCacheRead: usage.codexCacheRead,
            antigravity: TokenUsageAntigravityFields(usage: usage),
            diagnostics: nil
        )
        return try #require(try JSONSerialization.jsonObject(with: try encoder.encode(request)) as? [String: Any])
    }

    let used = try body(agUsage(todayTotal: 5, todayDate: agDay))
    #expect(used["antigravity_input"] as? Int == 26_275)
    #expect(used["antigravity_output"] as? Int == 81)
    #expect(used["antigravity_thinking"] as? Int == 66)
    #expect(used["antigravity_cache_read"] as? Int == 16_254)
    // ★ total 은 여전히 클로드 4 + Codex 2 다. 여기에 안티그래비티가 섞이면 옛 표와의 '같은 단위' 비교가 무너진다.
    #expect(used["total"] as? Int == 1_794_000_000)
    #expect(used["today_total"] as? Int == 5)

    let unused = try body(agUsage(antigravityInput: 0, antigravityOutput: 0, antigravityThinking: 0, antigravityCacheRead: 0))
    for key in ["antigravity_input", "antigravity_output", "antigravity_thinking", "antigravity_cache_read"] {
        #expect(unused[key] == nil, "안 쓰는 사람 본문에 \(key) 가 실렸다 — 컬럼 없는 서버에서 400 이 난다")
    }
    // 그 본문은 안티그래비티가 생기기 전과 같은 키 집합이다(요청이 늘지도, 모양이 바뀌지도 않았다).
    #expect(Set(unused.keys) == [
        "user_id", "month", "device_id",
        "claude_input", "claude_output", "claude_cache_read", "claude_cache_creation",
        "codex_input", "codex_output", "codex_cache_read",
        "total", "today_total", "today_date"
    ], "본문 키: \(unused.keys.sorted())")

    // 넷 중 셋만 0 이어도 넷이 함께 실린다(합이 0 일 때만 통째로 빠진다) — "셋만 실린 본문"이 생기면
    // 서버의 네 컬럼 합이 이 기기의 실제 합과 달라진다.
    let onlyCache = try body(agUsage(antigravityInput: 0, antigravityOutput: 0, antigravityThinking: 0, antigravityCacheRead: 9))
    #expect(onlyCache["antigravity_input"] as? Int == 0)
    #expect(onlyCache["antigravity_cache_read"] as? Int == 9)
}

// MARK: - ③ 업로드 본문 (일별)

/// 일별 표에는 합 하나(antigravity_total)가 간다. 규약은 나머지 넷과 같다 — **덮는 날에만** 값이 있고,
/// 모르는 날은 키를 빼 서버 값을 보존한다(창 안의 지난달 날짜에 0 을 실으면 그 달 행이 지워진다).
@Test
func v0312DailyUploadCarriesAntigravityOnlyForDaysItCovers() {
    let lastMonthDay = "2026-08-31"   // 창(2026-07-01) 안이지만 **지난달** — 로컬 안티그래비티 맵이 모르는 날이다.
    let usage = agUsage(
        antigravityDaily: [agDay: 42_676, lastMonthDay: 111],
        claudeDaily: [agDay: 1_000, lastMonthDay: 2_000],
        windowStart: "2026-07-01"
    )
    let values = TokenUsageDailyUpload.values(usage: usage, account: nil)

    // 이번 달 날: 안티그래비티 값이 실린다.
    #expect(values[agDay]?.antigravity == 42_676)
    // 창 안의 **지난달** 날: 로컬 맵이 현재 월만 담으므로 모른다 → nil(키 생략). 그 날의 Claude 값은 여전히 실린다.
    #expect(values[lastMonthDay]?.antigravity == nil)
    #expect(values[lastMonthDay]?.claude == 2_000)

    // 안티그래비티'만' 있는 날도 행이 만들어진다(그 날 다른 도구를 안 썼다고 기록이 사라지면 안 된다).
    let onlyAG = TokenUsageDailyUpload.values(
        usage: agUsage(antigravityDaily: [agDay: 7], windowStart: agMonth + "-01"), account: nil
    )
    #expect(onlyAG[agDay]?.antigravity == 7)
    #expect(onlyAG[agDay]?.claude == 0)

    // 요청 행까지 값이 살아 간다.
    let rows = TokenUsageDailyUpload.rows(userID: "u1", deviceID: "dev-1", days: [agDay], values: values)
    #expect(rows.first?.antigravityTotal == 42_676)
}

/// ★ 키 집합이 다른 행은 **한 요청에 섞이면 안 된다**(PostgREST 는 스키마를 보기도 전에 400 PGRST102 로 본문 전체를
/// 거절한다). 옵셔널이 다섯이 된 지금도 묶음이 키 모양별로 갈리는지, 스텁 네트워크로 실제 본문을 받아 확인한다.
///
/// ★★ **다섯째 비트를 실제로 고정한다.** 초판은 키 모양이 서로 완전히 다른 세 행을 넣어서, 묶음 함수에서
/// `antigravityTotal` 비트를 지워도 여전히 셋으로 갈려 초록이었다(검토자 지적 — 그 비트를 못 박지 못했다).
/// 그래서 **안티그래비티 유무만 다른 두 행**(9/9 · 9/12)을 넣는다. 비트가 빠지면 그 둘이 한 묶음이 되어
/// 요청 수가 4 → 3 으로 줄고, 이 테스트가 정확히 그 자리에서 빨개진다.
@Test
func v0312DailyUpsertSplitsRequestsByKeyShapeWithTheFifthOptional() async throws {
    let host = "v0312-daily-shape"
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed)
    )
    // 네 가지 키 모양. 9/9 와 9/12 는 **안티그래비티 유무만** 다르다(나머지 키는 글자 그대로 같다).
    let rows = [
        TokenUsageDailyUpsertRow(userId: "u1", day: "2026-09-09", deviceId: "d", claudeTotal: 1, codexTotal: 2, codexAccount: nil, antigravityTotal: 3),
        TokenUsageDailyUpsertRow(userId: "u1", day: "2026-09-12", deviceId: "d", claudeTotal: 1, codexTotal: 2, codexAccount: nil, antigravityTotal: nil),
        TokenUsageDailyUpsertRow(userId: "u1", day: "2026-09-10", deviceId: "d", claudeTotal: 4, codexTotal: nil, codexAccount: nil, antigravityTotal: nil),
        TokenUsageDailyUpsertRow(userId: "u1", day: "2026-09-11", deviceId: "d", claudeTotal: nil, codexTotal: nil, codexAccount: nil, antigravityTotal: 6)
    ]
    try await service.upsertTokenUsageDaily(accessToken: "t", rows: rows)

    let bodies = zip(URLProtocolStub.requests(forHost: host), URLProtocolStub.bodies(forHost: host))
        .filter { $0.0.url?.path == "/rest/v1/token_usage_device_daily" }
        .map { $0.1 }
    #expect(bodies.count == 4, "키 모양 넷이 섞였다 — 400 PGRST102 로 본문 전체가 버려진다")

    // 그 둘이 **서로 다른 요청**에 실렸는가 = 다섯째 비트가 살아 있는가.
    let with9 = try #require(bodies.first { $0.contains("2026-09-09") })
    let with12 = try #require(bodies.first { $0.contains("2026-09-12") })
    #expect(with9 != with12, "안티그래비티 유무만 다른 두 행이 한 요청에 묶였다 — 묶음 함수에 다섯째 비트가 없다")
    #expect(with9.contains("antigravity_total"))
    #expect(!with12.contains("antigravity_total"))

    // 각 묶음 안에서는 모든 행의 키 집합이 정확히 같다.
    for body in bodies {
        let array = try #require(try JSONSerialization.jsonObject(with: Data(body.utf8)) as? [[String: Any]])
        let shapes = Set(array.map { Set($0.keys) })
        #expect(shapes.count == 1, "한 요청 안에 키 집합이 둘 이상이다: \(shapes)")
    }
    // 안티그래비티만 있는 행의 본문에는 claude_total 이 없다(= 그 기기가 그 날 Claude 값을 지우지 않는다).
    let agOnly = try #require(bodies.first { $0.contains("2026-09-11") })
    let agArray = try #require(try JSONSerialization.jsonObject(with: Data(agOnly.utf8)) as? [[String: Any]])
    #expect(agArray.first?["antigravity_total"] as? Int == 6)
    #expect(agArray.first?["claude_total"] == nil)
}

// MARK: - ④ 표시: 툴팁 · 순위판 잔차

/// 내 박스 툴팁은 **굵은 총합을 이루는 값들**을 그대로 읽어 준다. 0 인 종류는 줄을 만들지 않는다.
@Test
func v0312MyBoxTooltipListsExactlyTheKindsThatAreNotZero() {
    let all = agUsage()
    #expect(all.detailTooltip == "Claude 1,234,000,000 · Codex 560,000,000 · 안티그래비티 42,676")

    // 안티그래비티만 쓰는 사람: 다른 두 줄이 없다.
    let onlyAG = agUsage(
        claudeInput: 0, claudeOutput: 0, claudeCacheRead: 0, claudeCacheCreation: 0,
        codexInput: 0, codexOutput: 0, codexCacheRead: 0
    )
    #expect(onlyAG.detailTooltip == "안티그래비티 42,676")

    // 안 쓰는 사람: 이 변경 전과 글자 하나 다르지 않다.
    let noAG = agUsage(antigravityInput: 0, antigravityOutput: 0, antigravityThinking: 0, antigravityCacheRead: 0)
    #expect(noAG.detailTooltip == "Claude 1,234,000,000 · Codex 560,000,000")
}

/// 순위판 카드 툴팁의 세 값 합은 **언제나 굵은 총합과 같다**. 안티그래비티 몫은 서버가 내역 컬럼을 안 주므로
/// `total − claude − codex_effective` 잔차로 되살린다(같은 식의 이항이라 추정이 아니다).
@Test
func v0312BoardTooltipRecoversAntigravityAsTheResidualOfTheServerFormula() {
    // 새 서버: total 에 안티그래비티가 들어 있다.
    let entry = TokenBoardEntry(
        userID: "u1", name: "영식", avatarURL: nil,
        total: 1_562_135_145 + 6_930_295_293 + 42_676,
        claudeInput: 1_000_000_000, claudeOutput: 500_000_000,
        claudeCacheRead: 62_135_145, claudeCacheCreation: 0,
        codexInput: 3_000_000_000, codexOutput: 100_000_000,
        codexAccountMonth: 6_000_000_000,
        codexEffectiveFromServer: 6_930_295_293
    )
    #expect(entry.claudeTotal == 1_562_135_145)
    #expect(entry.codexEffective == 6_930_295_293)
    #expect(entry.antigravityEffective == 42_676)
    #expect(entry.claudeTotal + entry.codexEffective + entry.antigravityEffective == entry.total)
    #expect(entry.detailTooltip == "Claude 1,562,135,145 · Codex 6,930,295,293 · 안티그래비티 42,676")

    // 옛 표가 이긴 행 / 안티그래비티가 없는 사람: 잔차 0 → 툴팁도 캡션도 이 변경 전과 같다.
    let legacyRow = TokenBoardEntry(
        userID: "u2", name: "민수", avatarURL: nil,
        total: 300_000_000 + 40_000_000,
        claudeInput: 300_000_000, claudeOutput: 0, claudeCacheRead: 0, claudeCacheCreation: 0,
        codexInput: 40_000_000, codexOutput: 0,
        codexEffectiveFromServer: 40_000_000
    )
    #expect(legacyRow.antigravityEffective == 0)
    #expect(legacyRow.detailTooltip == "Claude 300,000,000 · Codex 40,000,000")

    // 서버가 산식을 바꿔 셋이 안 맞게 되는 날에도 화면에 음수가 뜨지 않는다.
    let shrunk = TokenBoardEntry(
        userID: "u3", name: "지원", avatarURL: nil,
        total: 10, claudeInput: 100, claudeOutput: 0, claudeCacheRead: 0, claudeCacheCreation: 0,
        codexInput: 0, codexOutput: 0
    )
    #expect(shrunk.antigravityEffective == 0)
}

// MARK: - ④ 표시: 폭 예산 (NSFont 실측을 테스트가 되묻는다)

private func agWidth(_ s: String) -> CGFloat {
    (s as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 10)]).width
}

/// **세 번째 도구는 순위판 캡션(121pt)에 물리적으로 들어가지 않는다.** 이것이 v0.3.12 의 폭 결론이고,
/// 그래서 세 번째 값은 폭 제한이 없는 툴팁에만 있다(TokenBoardEntry.toolUsageLabel 주석).
///
/// 왜 테스트가 필요한가: 이 줄은 `lineLimit(1) + minimumScaleFactor` 라 넘쳐도 **높이가 안 변한다** —
/// 렌더 높이 테스트로는 영원히 안 잡히고, 증상은 말줄임이다("Codex 254만" → "Codex 25…" = 자릿수 오독).
/// 그래서 값으로 재고, 그 값을 여기서 **다시 측정해** 상수와 맞는지 되묻는다(폰트 메트릭이 바뀌면 빨강).
@MainActor
@Test
func v0312CaptionWidthBudgetRejectsTheThirdToolAndStillFitsTwo() {
    // ⓐ 폭의 유래가 코드와 같다: 본문 292 − 카드 8/12 − spacing 30 − 바 3 − 아바타 30 = 209, 숫자 열 88 → 캡션 121.
    #expect(TokenToolMixWidthBudget.sharedColumnWidth == 209)
    #expect(TokenToolMixWidthBudget.captionWidth == 121)
    #expect(TokenToolMixWidthBudget.fittingNaturalWidth == 121 / 0.7)

    // ⓑ 상수가 실측과 같다(오차 0.5pt 안 — 폰트 메트릭이 바뀌면 이 단언이 먼저 말해 준다).
    #expect(abs(agWidth("Claude 1,234억 · Codex 1,234억") - TokenToolMixWidthBudget.twoKindWorstWidth) < 0.5)
    #expect(abs(agWidth("Claude 1,234억 · Codex 1,234억 · AG 1,234억") - TokenToolMixWidthBudget.threeKindShortWidth) < 0.5)
    #expect(abs(agWidth("Claude 1,234억 · Codex 1,234억 · Antigravity 1,234억") - TokenToolMixWidthBudget.threeKindFullWidth) < 0.5)
    #expect(abs(agWidth("1,234,567,890,123 토큰") - TokenToolMixWidthBudget.widestTotalWidth) < 0.5)

    // ⓒ 두 종류의 현실 최대 조합은 지금도 말줄임 없이 들어간다(이번 변경이 기존 캡션을 깨지 않았다).
    #expect(TokenToolMixWidthBudget.fits(naturalWidth: TokenToolMixWidthBudget.twoKindWorstWidth))

    // ⓓ 세 종류는 약어로 줄여도 안 들어간다 — 숫자 열을 물리적 바닥(76pt)까지 낮춰 캡션을 133pt 로 넓혀도 그렇다.
    #expect(!TokenToolMixWidthBudget.fits(naturalWidth: TokenToolMixWidthBudget.threeKindShortWidth))
    #expect(!TokenToolMixWidthBudget.fits(naturalWidth: TokenToolMixWidthBudget.threeKindFullWidth))
    #expect(TokenToolMixWidthBudget.widestPossibleCaptionWidth == 133)
    #expect(TokenToolMixWidthBudget.threeKindShortWidth * TokenToolMixWidthBudget.captionMinScale
            > TokenToolMixWidthBudget.widestPossibleCaptionWidth)
    // 바닥이 76 인 근거: 16자리 총합이 0.7 축소로 겨우 사는 폭이다(그 아래로 낮추면 총합이 말줄임된다).
    #expect(TokenToolMixWidthBudget.widestTotalWidth * TokenToolMixWidthBudget.captionMinScale
            <= TokenToolMixWidthBudget.numberColumnFloor)

    // ⓔ 이름 세 개가 들어갈 자리조차 없다: 숫자 3개(105.4)+구분자 2개(17.9)를 뺀 나머지에 "Claude "+"Codex " 만으로 넘친다.
    let digits = 3 * agWidth("1,234억") + 2 * agWidth(" · ")
    let namesBudget = TokenToolMixWidthBudget.widestPossibleCaptionWidth / TokenToolMixWidthBudget.captionMinScale - digits
    #expect(agWidth("Claude ") + agWidth("Codex ") > namesBudget)

    // ⓕ 그래서 캡션은 두 종류 그대로다 — 안티그래비티가 있어도 이 줄은 안 바뀐다.
    let entry = TokenBoardEntry(
        userID: "u1", name: "영식", avatarURL: nil,
        total: 19_658_964_272 + 2_543_110 + 1_000_000,
        claudeInput: 19_658_964_272, claudeOutput: 0, claudeCacheRead: 0, claudeCacheCreation: 0,
        codexInput: 2_543_110, codexOutput: 0, codexEffectiveFromServer: 2_543_110
    )
    #expect(entry.antigravityEffective == 1_000_000)
    #expect(entry.toolUsageLabel == "Claude 196.6억 · Codex 254만")
    #expect(agWidth(entry.toolUsageLabel ?? "") <= TokenToolMixWidthBudget.fittingNaturalWidth)
    // 그 값은 툴팁에 살아 있다(캡션에서 뺀 것을 어디서도 못 보는 상태로 두지 않는다).
    #expect(entry.detailTooltip.contains("안티그래비티 1,000,000"))
}

// MARK: - ④ 표시: 게이트는 짝으로 (안티그래비티만 쓰는 사람)

/// `usage.total` 에는 안티그래비티가 **안 들어간다**(업로드값의 뜻을 지키려고 뺐다). 그래서 `total > 0` 을 묻는
/// 게이트를 그대로 두면 안티그래비티만 쓰는 사람은 **행도 안 보이고 업로드도 안 된다** — 스토어만 고치고 뷰를
/// 안 고치면 초록인 채로 아무것도 안 바뀌는, 이 저장소가 여러 번 밟은 함정이다. 두 문을 한 번에 잰다.
@MainActor
@Test
func v0312AntigravityOnlyUserPassesBothTheRowGateAndTheUploadGate() async throws {
    let usage = agUsage(
        claudeInput: 0, claudeOutput: 0, claudeCacheRead: 0, claudeCacheCreation: 0,
        codexInput: 0, codexOutput: 0, codexCacheRead: 0,
        antigravityDaily: [agDay: 42_676], windowStart: agMonth + "-01"
    )
    #expect(usage.total == 0, "이 픽스처가 '총합 0 인데 안티그래비티는 있다'가 아니면 아래 단언이 의미가 없다")
    #expect(usage.antigravityTotal == 42_676)

    // ⓐ 행 게이트: 그림이 그려진다(EmptyView 면 픽셀 높이가 0 이다).
    let defaults = agDefaults()
    defaults.set(try JSONEncoder().encode(usage), forKey: TokenUsageStore.snapshotKey)
    let store = TokenUsageStore(
        defaults: defaults,
        homeDirectory: agTempDir("row-gate-home"),
        cacheURL: agTempDir("row-gate-cache").appendingPathComponent("c.json"),
        clock: { agNow },
        notificationCenter: NotificationCenter()
    )
    #expect(store.currentMonthUsage?.antigravityTotal == 42_676, "스냅샷 복원이 안 됐다(월 불일치?)")
    let renderer = ImageRenderer(content: CheckTokenUsageRow(store: store).frame(width: 292).fixedSize())
    renderer.scale = 2
    let image = try #require(renderer.nsImage)
    #expect(image.size.height > 0, "안티그래비티만 쓰는 사람의 토큰 행이 통째로 사라졌다")

    // ⓑ 업로드 게이트: 월 upsert 가 실제로 나간다.
    let host = "v0312-upload-gate"
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed)
    )
    let work = WorkTimerStore(
        service: service,
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: agDefaults(),
        workspaceNotifications: nil,
        tokenUsage: store
    )
    defer {
        work.tickerTask?.cancel(); work.refreshTask?.cancel()
        work.syncTask?.cancel(); work.pokePollTask?.cancel()
    }
    work.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "00000000-0000-0000-0000-000000000003")
    work.currentTeamID = URLProtocolStub.stubTeamID
    work.membershipConfirmed = true
    work.tokenUsageCollect = true

    await work.uploadTokenUsageIfNeeded(usage: usage, now: agNow)
    let posts = zip(URLProtocolStub.requests(forHost: host), URLProtocolStub.bodies(forHost: host))
        .filter { $0.0.url?.path == "/rest/v1/token_usage_device_monthly" && $0.0.httpMethod == "POST" }
    #expect(posts.count == 1, "안티그래비티만 쓰는 사람의 사용량이 서버에 한 번도 닿지 않는다")
    let sentBody = try #require(posts.first?.1)
    let object = try #require(try JSONSerialization.jsonObject(with: Data(sentBody.utf8)) as? [String: Any])
    #expect(object["antigravity_input"] as? Int == 26_275)
    #expect(object["total"] as? Int == 0, "total 에 안티그래비티가 섞였다")
}

// MARK: - ④ 표시: 육안 확인용 스냅샷
//
// 값 단언이 못 보는 것이 하나 있다: **말줄임**. `lineLimit(1) + minimumScaleFactor` 는 넘쳐도 높이가 안 변하고,
// `.help` 툴팁은 픽셀을 만들지 않는다. 그래서 이 세 장을 남겨 사람이 직접 본다.
//   antigravity-mybox-three.png : 세 종류가 다 있는 내 박스(굵은 총합에 안티그래비티가 들어갔다)
//   antigravity-mybox-only.png  : 안티그래비티만 쓰는 사람(행이 사라지지 않는다 — 게이트 짝)
//   antigravity-board-row.png   : 순위판 행(캡션은 두 종류 그대로, 총합은 세 종류 — 잘린 글자가 없어야 한다)
//
// 저장 위치는 `CHECK_SNAPSHOT_DIR`(없으면 이 실행의 임시 디렉터리) 아래 `panels/` — 개인 머신 경로를
// 소스에 박지 않는다(V0246·V0248 렌더 스위트와 같은 규약).
private enum V0312Snapshots {
    static func save(_ png: Data, _ name: String) -> URL? {
        let base = ProcessInfo.processInfo.environment["CHECK_SNAPSHOT_DIR"].map {
            URL(fileURLWithPath: $0, isDirectory: true)
        } ?? FileManager.default.temporaryDirectory.appendingPathComponent("check-snapshots", isDirectory: true)
        let dir = base.appendingPathComponent("panels", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        return (try? png.write(to: url)) == nil ? nil : url
    }
}

@MainActor
private func v0312RenderPNG(_ view: some View, width: CGFloat = 292) throws -> Data {
    let renderer = ImageRenderer(content: view.frame(width: width).fixedSize())
    renderer.scale = 3
    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff),
          let png = bitmap.representation(using: .png, properties: [:])
    else { throw V0312RenderError.failed }
    return png
}

private enum V0312RenderError: Error { case failed }

@MainActor
private func v0312Store(_ usage: TokenUsageMonthly) throws -> TokenUsageStore {
    let defaults = agDefaults()
    defaults.set(try JSONEncoder().encode(usage), forKey: TokenUsageStore.snapshotKey)
    return TokenUsageStore(
        defaults: defaults,
        homeDirectory: agTempDir("snap-home"),
        cacheURL: agTempDir("snap-cache").appendingPathComponent("c.json"),
        clock: { agNow },
        notificationCenter: NotificationCenter()
    )
}

@MainActor
@Test
func v0312RendersTokenBoxAndBoardRowSnapshots() throws {
    // ① 세 종류가 다 있는 내 박스. 굵은 총합 = 클로드 + Codex + 안티그래비티.
    let three = agUsage()
    let threeStore = try v0312Store(three)
    let threePNG = try v0312RenderPNG(CheckTokenUsageRow(store: threeStore))
    #expect(threePNG.count > 0)
    _ = V0312Snapshots.save(threePNG, "antigravity-mybox-three.png")

    // ② 안티그래비티만 쓰는 사람 — 행이 살아 있다(그림이 ①과 다르다 = 숫자가 실제로 갈렸다).
    let onlyAG = agUsage(
        claudeInput: 0, claudeOutput: 0, claudeCacheRead: 0, claudeCacheCreation: 0,
        codexInput: 0, codexOutput: 0, codexCacheRead: 0
    )
    let onlyStore = try v0312Store(onlyAG)
    let onlyPNG = try v0312RenderPNG(CheckTokenUsageRow(store: onlyStore))
    #expect(onlyPNG != threePNG)
    _ = V0312Snapshots.save(onlyPNG, "antigravity-mybox-only.png")

    // ③ 순위판 행(내 행 + 비공개 칩 = 폭이 가장 빡빡한 조합). 캡션은 두 종류 그대로, 총합은 세 종류.
    let entry = TokenBoardEntry(
        userID: "u1", name: "김영식", avatarURL: nil,
        total: 19_658_964_272 + 2_543_110 + 42_676,
        claudeInput: 19_658_964_272, claudeOutput: 0, claudeCacheRead: 0, claudeCacheCreation: 0,
        codexInput: 2_543_110, codexOutput: 0,
        todayTotal: 12_345_678, todayDate: agDay,
        codexEffectiveFromServer: 2_543_110
    )
    #expect(entry.antigravityEffective == 42_676)
    let rowPNG = try v0312RenderPNG(
        TokenBoardRowView(entry: entry, isMe: true, showsPrivateChip: true, todayKey: agDay)
            .frame(height: 62)
    )
    #expect(rowPNG.count > 0)
    _ = V0312Snapshots.save(rowPNG, "antigravity-board-row.png")
}

// MARK: - ⑤ 실홈 차단: **테스트 프로세스는 사용자 폴더를 열지 않는다** (v0.3.12 중대)
//
// 무엇이 있었나 — 토큰 스토어를 **주입하지 않은** `WorkTimerStore` 를 만드는 테스트가 이 저장소에 약 170곳 있다.
// 그 기본값은 `TokenUsageStore.shared`(= 실제 홈)이고, `session` 과 `startedAt` 만 채우면
// `refreshTokenUsageInBackgroundIfDue` 의 게이트가 전부 열려 스캔이 정말로 돈다. v0.3.12 가 그 스캔에
// `~/.gemini/antigravity-cli/conversations/*.db` 를 더한 순간부터 **테스트가 사용자 실폴더를 sqlite 로 열었다**
// (실측 2026-09-11: V0251MessagePeer 필터만 돌려도 그 폴더 `*-shm` 두 개의 mtime 이 갱신됐다).
//
// 배선 하나를 고치는 것으로는 다음 사람이 같은 모양을 또 만든다. 그래서 **스캔 경로 자체**를 막았고
// (`TokenUsageStore.realHomeScanIsBlocked`), 이 세 테스트가 그 그물을 지킨다:
//   ⑴ 기본 홈 그대로 만든 스토어가 스캔을 해도 사용자 폴더의 지문이 한 글자도 안 바뀐다 · 결과는 조용한 빈 집계다.
//   ⑵ 게이트는 **테스트 번들 판정 하나**로만 열린다 = 프로덕션에서는 언제나 거짓이다(소스 계약).
//   ⑶ 주입을 잊은 `WorkTimerStore` 의 배경 스캔(= 결함이 난 그 경로)도 사용자 폴더를 못 건드린다.

/// 사용자의 **실제** 대화 디렉터리. 여기는 `stat` 말고 아무것도 하지 않는다.
private var agRealConversations: URL {
    AntigravityUsageScanner.conversationsDirectory(homeDirectory: FileManager.default.homeDirectoryForCurrentUser)
}

/// 디렉터리의 지문: 이름 + 크기 + mtime. 이름만 보면 못 잡는다 — 이미 있는 `-shm` 을 다시 읽으면
/// **이름은 그대로인데 mtime 이 갱신된다**(그게 이번에 잡힌 실측 증거다).
private func agFingerprint(_ url: URL) -> [String] {
    let fm = FileManager.default
    return ((try? fm.contentsOfDirectory(atPath: url.path)) ?? []).sorted().map { name in
        let a = try? fm.attributesOfItem(atPath: url.appendingPathComponent(name).path)
        let size = (a?[.size] as? Int) ?? -1
        let mtime = (a?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? -1
        return "\(name)|\(size)|\(mtime)"
    }
}

/// 파일 하나의 지문(없으면 "없음"). 실홈 스캔은 디스크 캐시(Application Support)도 건드리면 안 된다.
private func agFileFingerprint(_ url: URL) -> String {
    guard let a = try? FileManager.default.attributesOfItem(atPath: url.path) else { return "없음" }
    let size = (a[.size] as? Int) ?? -1
    let mtime = (a[.modificationDate] as? Date)?.timeIntervalSince1970 ?? -1
    return "\(size)|\(mtime)"
}

private func agSourceURL(_ name: String) -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // Tests/checkTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // repo root
        .appendingPathComponent("Sources/check/\(name)")
}

private func agOccurrences(of needle: String, in haystack: String) -> Int {
    haystack.components(separatedBy: needle).count - 1
}

/// `//` 줄 주석과 `/* */` 블록 주석을 걷어낸다(문자열 리터럴 안의 `//` 는 남긴다).
/// 소스 계약 테스트는 **주석을 걷어내고** 세야 한다 — 안 그러면 설명문을 지워야만 초록이 되는 테스트가 된다
/// (V0237KeychainTests·RealtimeLinkTests 의 같은 헬퍼와 동일 규약, private 라 파일마다 사본을 둔다).
private func agStrippingComments(_ source: String) -> String {
    var result = ""
    var inString = false
    var inLineComment = false
    var inBlockComment = false
    var previous: Character = " "
    let characters = Array(source)
    var index = 0
    while index < characters.count {
        let c = characters[index]
        let next: Character? = index + 1 < characters.count ? characters[index + 1] : nil
        if inLineComment {
            if c == "\n" { inLineComment = false; result.append(c) }
        } else if inBlockComment {
            if c == "*", next == "/" { inBlockComment = false; index += 1 }
        } else if inString {
            if c == "\"", previous != "\\" { inString = false }
            result.append(c)
        } else if c == "/", next == "/" {
            inLineComment = true; index += 1
        } else if c == "/", next == "*" {
            inBlockComment = true; index += 1
        } else if c == "\"" {
            inString = true; result.append(c)
        } else {
            result.append(c)
        }
        previous = c
        index += 1
    }
    return result
}

/// ⑴ **기본 홈으로 만든 스토어가 스캔을 돌려도 사용자 폴더는 한 글자도 안 바뀐다.**
/// 홈과 캐시 경로를 **일부러 주입하지 않는다** — 결함이 난 모양(주입 없는 스토어) 그대로여야 그물을 재는 것이 된다.
/// 스캔이 죽지도 않는다: 조용한 빈 집계가 나오고(이번 달 키 · 총합 0), 더러워진 것이 없어 저장도 나가지 않는다.
@MainActor
@Test
func v0312BlockedRealHomeScanTouchesNothingAndReturnsEmpty() async {
    #expect(CheckPanelVisibility.isRunningTests, "테스트 판정이 죽었다 — 이 그물 전체가 열린다")
    #expect(TokenUsageStore.realHomeScanIsBlocked(homeDirectory: FileManager.default.homeDirectoryForCurrentUser),
            "실홈이 차단 대상이 아니다 — 테스트가 사용자 폴더를 스캔한다")
    #expect(!TokenUsageStore.realHomeScanIsBlocked(homeDirectory: agTempDir("injected-home")),
            "주입된 임시 홈까지 막으면 스캐너 정확성 테스트 수십 개가 통째로 빈 집계가 된다")

    let before = agFingerprint(agRealConversations)

    // ★ homeDirectory·cacheURL 을 주입하지 않는다(기본값 = 실제 홈 · 실제 캐시).
    let store = TokenUsageStore(defaults: agDefaults(), notificationCenter: NotificationCenter())
    #expect(store.blockedRealHomeScanCount == 0)

    await store.refreshNow()
    await store.awaitScanCompletion()
    await store.awaitPendingSaves()

    // 막힌 사실이 관측값으로 남는다(스캔은 '돌았다'고 세지만 읽은 것은 아무것도 없다).
    #expect(store.blockedRealHomeScanCount == 1)
    #expect(store.scanCount == 1)
    // 조용한 빈 결과: 형태는 온전하고(이번 달 키) 값은 전부 0이며, 파일은 한 개도 stat 하지 않았다.
    #expect(store.lastScanFileCount == 0, "막혔는데 파일을 셌다 — 실홈 순회가 돌았다는 뜻이다")
    #expect(store.currentMonthUsage?.month == TokenUsageIncrementalScanner.kstMonthString(Date()))
    #expect(store.currentMonthUsage?.total == 0)
    #expect(store.currentMonthUsage?.antigravityTotal == 0)
    #expect(store.isScanning == false)
    #expect(store.lastScanAntigravityBlind == false, "차단은 '눈먼 스캔'으로 신고되지 않는다(원인이 다르다)")
    // 디스크에 나간 것이 없다 — 막힌 스캔은 캐시를 더럽히지 않는다.
    #expect(store.saveCount == 0, "막힌 스캔이 캐시를 저장했다")

    // ★ 이번 결함의 실증 지점: 사용자 폴더의 지문(이름+크기+mtime)이 그대로다.
    #expect(agFingerprint(agRealConversations) == before, """
        테스트가 사용자의 ~/.gemini/antigravity-cli/conversations 를 건드렸다.
        before=\(before)
        after =\(agFingerprint(agRealConversations))
        """)
    // ⚠️ 사용자의 **실제 토큰 캐시 파일**을 전후 비교하지 마라(2026-09-11 검토 지적).
    //   그 파일은 실행 중인 aing-check 앱이 자기 주기로 쓴다 — 테스트가 도는 창에 앱이 한 번만 써도
    //   코드와 무관하게 빨개진다(실측: 아무 테스트도 안 도는 구간에 21:55·21:57·22:10 세 번 갱신됐다).
    //   "내가 안 썼다"는 위 `store.saveCount == 0` 이 재고, 그 값은 다른 프로세스의 쓰기에 흔들리지 않는다.
}

/// ⑵ **프로덕션에서는 이 게이트가 언제나 거짓이다.** 그것을 소스로 못 박는다 — 런타임으로는 증명할 수 없다
/// (이 프로세스는 영원히 테스트다). 판정은 `CheckPanelVisibility.isRunningTests` **하나**이고, 그 파일 주석이
/// 왜 다른 후보(`XCTestConfigurationFilePath` · `NSClassFromString("XCTestCase")`)가 이 저장소에서 안 통했는지를
/// 실측으로 적어 두었다. 여기서 재는 것: (1) 게이트 첫 줄이 그 판정이다 · (2) 새 판정을 만들지 않았다 ·
/// (3) 이 파일에 `#if DEBUG` 같은 빌드 갈래가 없다(어느 갈래가 배포되는지 추적 불가능해진다).
@Test
func v0312RealHomeScanBlockIsGatedOnTheTestBundleAlone() throws {
    let raw = try String(contentsOf: agSourceURL("CheckTokenUsage.swift"), encoding: .utf8)
    let source = agStrippingComments(raw)

    guard let start = source.range(of: "static func realHomeScanIsBlocked"),
          let end = source.range(of: "\n    }", range: start.upperBound..<source.endIndex)
    else {
        Issue.record("realHomeScanIsBlocked 를 소스에서 찾지 못했다")
        return
    }
    let body = String(source[start.upperBound..<end.lowerBound])
    #expect(body.contains("guard CheckPanelVisibility.isRunningTests else { return false }"),
            "게이트가 테스트 번들 판정으로 시작하지 않는다 — 프로덕션에서 참이 될 수 있다: \(body)")
    #expect(agOccurrences(of: "CheckPanelVisibility.isRunningTests", in: body) == 1)

    // 판정을 새로 만들지 않았다(실측으로 탈락한 후보들이 되살아나지 않았다).
    #expect(!source.contains("XCTestConfigurationFilePath"))
    #expect(!source.contains("XCTestBundlePath"))
    #expect(!source.contains("NSClassFromString"))
    // 빌드 갈래로 가르지 않았다 — 프로덕션 동작이 컴파일 조건에 따라 달라지면 이 계약이 무의미해진다.
    #expect(!source.contains("#if DEBUG"))

    // 이 판정을 쓰는 곳은 스캔 시작 지점 **한 곳**이다(정의 1 + 호출 1).
    #expect(agOccurrences(of: "realHomeScanIsBlocked(", in: source) == 2,
            "게이트를 두 곳에서 쓰면 어느 경로가 막혔는지 추적이 안 된다")
    guard let scanStart = source.range(of: "private func startScan()") else {
        Issue.record("startScan 을 소스에서 찾지 못했다")
        return
    }
    let scanBody = String(source[scanStart.upperBound..<source.endIndex]).prefix(1_200)
    #expect(scanBody.contains("realHomeScanIsBlocked(homeDirectory: homeDirectory)"),
            "스캔 시작 지점이 게이트를 지나지 않는다")
}

/// ⑶ **결함이 난 그 경로로 재현한다.** 토큰 스토어를 주입하지 않은 `WorkTimerStore`(= 이 저장소의 약 170곳 모양)에
/// `session` 과 `startedAt` 만 채우고 배경 스캔을 직접 부른다. 수정 전에는 이 한 줄이 사용자의
/// `~/.gemini/antigravity-cli/conversations` 를 sqlite 로 열어 `-shm` 의 mtime 을 갱신했다.
@MainActor
@Test
func v0312UninjectedWorkTimerStoreCannotTouchTheUserFolder() async {
    let before = agFingerprint(agRealConversations)
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://v0312-blocked-bg-scan")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed)
    )
    // ★ tokenUsage 를 **일부러 주입하지 않는다** — 기본값 TokenUsageStore.shared(= 실제 홈)가 쓰이는 그 모양이다.
    let store = WorkTimerStore(
        service: service,
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: agDefaults()
    )
    defer {
        store.tickerTask?.cancel()
        store.refreshTask?.cancel()
        store.syncTask?.cancel()
        store.pokePollTask?.cancel()
    }
    store.session = SupabaseSession(
        accessToken: "access-token", refreshToken: nil,
        userID: "00000000-0000-0000-0000-0000000003a1"
    )
    store.currentTeamID = URLProtocolStub.stubTeamID
    store.startedAt = Date().addingTimeInterval(-3_600)
    #expect(store.tokenUsage === TokenUsageStore.shared, "이 테스트의 전제는 '주입을 잊었다'다")

    await store.refreshTokenUsageInBackgroundIfDue(now: Date())
    await store.tokenUsage.awaitScanCompletion()
    await store.tokenUsage.awaitPendingSaves()

    // 스캔 요청은 실제로 게이트를 통과해 들어왔고(= 재현이 됐다), 그 전부가 막혔다.
    // 정확한 증가분은 단언하지 않는다 — shared 는 프로세스 전역이라 병렬로 도는 다른 테스트도 같은 계수기를 올린다.
    #expect(store.tokenUsage.blockedRealHomeScanCount >= 1, "배경 스캔이 아예 안 들어왔다 — 이 테스트가 아무것도 안 재고 있다")
    #expect(store.tokenUsage.lastScanFileCount == 0, "막혔는데 파일을 셌다")
    #expect(agFingerprint(agRealConversations) == before, """
        주입을 잊은 스토어의 배경 스캔이 사용자 폴더를 건드렸다(이번 결함의 재현 지점).
        before=\(before)
        after =\(agFingerprint(agRealConversations))
        """)
}
