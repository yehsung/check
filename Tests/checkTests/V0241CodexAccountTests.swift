import Foundation
import Testing
@testable import check

// MARK: - v0.2.41: Codex 집계 정확화(issue #6 + #2) 회귀 그물
//
// 이 파일이 지키는 것:
//   (A) 스캐너 — archived_sessions 루트 집계, 보관(rename) 무손실·무중복, `.zst` 동결 보존, `.zst` 없는 삭제는 정리,
//       캐시 델타 분리(필드별 클램프), 일별 맵·todayTotal 파생 일치, 월 롤오버 시 일별 맵 비움, CODEX_HOME 재정의,
//       진단 스캐너의 두 루트 항등식.
//   (B) 계정 프로브 파서 — 정상/잡음/에러/null 버킷/잘림/월합·UTC prefix/보관 정리/요청 모양/폴백 후보.
//   (C) 계정 스토어 — 1800초 간격·force·auth.json 부재(프로세스 0)·영속 왕복·실패 시 직전 스냅샷 유지·재진입.
//   (D) 업로드 계약(URLProtocolStub) — 본문 키 존재/생략, 로컬 0 + 계정 > 0 업로드, 계정값만 바뀌어도 업로드,
//       하트비트 5키 불변, 기본 스토어는 프로세스를 띄우지 않는다.
//   (E) 보드 디코드(새 컬럼 있음/없음) · 표시 산식 경계 · 소스/SQL 계약.
//
// 모든 테스트는 임시 홈의 픽스처만 읽고, **실제 `codex` 를 절대 실행하지 않는다**(러너 주입·inert).

// MARK: - 시각/픽스처 헬퍼

/// KST 2026-07-14 12:33:20 → 월 "2026-07". 다른 토큰 테스트와 같은 기준 시각이라 월 해석이 일치한다.
private let c41Now = Date(timeIntervalSince1970: 1_784_000_000)

private func c41UTC(_ iso: String) -> Date {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    f.timeZone = TimeZone(identifier: "UTC")
    return f.date(from: iso)!
}

private func c41ISO(_ date: Date) -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    f.timeZone = TimeZone(identifier: "UTC")
    return f.string(from: date)
}

private func c41TempHome(_ tag: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("check-v0241-\(tag)-\(UUID().uuidString)", isDirectory: true)
}

private func c41Sessions(_ home: URL, _ path: String) -> URL {
    home.appendingPathComponent(".codex/sessions/\(path)", isDirectory: false)
}

private func c41Archived(_ home: URL, _ name: String) -> URL {
    home.appendingPathComponent(".codex/archived_sessions/\(name)", isDirectory: false)
}

/// 파일을 쓰고 mtime 을 지정한다(기본 c41Now — 프리필터 통과).
private func c41Write(_ contents: String, to url: URL, modified: Date = c41Now) {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? Data(contents.utf8).write(to: url)
    try? FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
}

private func c41Append(_ contents: String, to url: URL, modified: Date) {
    if let h = try? FileHandle(forWritingTo: url) {
        _ = try? h.seekToEnd()
        try? h.write(contentsOf: Data(contents.utf8))
        try? h.close()
    }
    try? FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
}

/// token_count 이벤트 한 줄(개행 미포함). 필드별 누적치를 따로 준다(캐시 분리 검증용).
private func c41Event(input: Int, output: Int, cached: Int = 0, at date: Date) -> String {
    "{\"timestamp\":\"\(c41ISO(date))\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\","
    + "\"info\":{\"total_token_usage\":{\"input_tokens\":\(input),\"cached_input_tokens\":\(cached),"
    + "\"output_tokens\":\(output),\"total_tokens\":0}}}}"
}

/// 7월(현재 월)의 임의 시각(오늘 아님).
private let c41July5 = c41UTC("2026-07-05T01:00:00Z")   // KST 07-05 10:00
/// 오늘(KST 07-14).
private let c41Today = c41UTC("2026-07-14T02:00:00Z")   // KST 07-14 11:00

private func c41Scan(_ cache: TokenUsageCache = TokenUsageCache(), home: URL, codexHome: URL? = nil, now: Date = c41Now)
    -> TokenUsageIncrementalScanner.Result {
    TokenUsageIncrementalScanner.update(cache, homeDirectory: home, codexHome: codexHome, now: now)
}

/// 캐시 키는 열거자가 준 경로(`/private/var/...`)라 임시 디렉터리 URL(`/var/...`)과 접두어가 다를 수 있다 — 꼬리로 찾는다.
private func c41State(_ cache: TokenUsageCache, _ url: URL) -> CodexFileProgress? {
    let tail = url.pathComponents.suffix(3).joined(separator: "/")
    return cache.codexFileStates.first { $0.key.hasSuffix(tail) }?.value
}

// MARK: - (A) 스캐너

/// archived_sessions 루트의 rollout 도 집계된다(평면 디렉터리·같은 파일명 규약).
/// 뮤테이션: codexRoots 에서 archived_sessions 를 빼면 빨강.
@Test
func scannerCountsRolloutsUnderArchivedSessionsRoot() {
    let home = c41TempHome("archived-root")
    defer { try? FileManager.default.removeItem(at: home) }
    c41Write([c41Event(input: 1_000, output: 100, at: c41July5), c41Event(input: 4_000, output: 600, at: c41July5)]
        .joined(separator: "\n") + "\n", to: c41Archived(home, "rollout-2026-07-05T00-00-00-arch.jsonl"))
    // 보관 루트에 rollout- 접두어가 아닌 파일(예: 인덱스)이 있어도 무시된다.
    c41Write("{\"noise\":true}\n", to: c41Archived(home, "index.jsonl"))

    let r = c41Scan(home: home)
    #expect(r.usage.codexInput == 3_000)
    #expect(r.usage.codexOutput == 500)
    #expect(r.usage.codexTotal == 3_500)
    #expect(r.stats.codexFilesStatted == 1)
}

/// 보관(rename)으로 경로가 바뀐 파일: 옛 경로 상태는 정리되고 새 경로가 0 부터 파싱되며 첫 이벤트가 기준선이라
/// 월 합이 **같게** 재구성된다 — 이중 계상도 유실도 없다(issue #6 의 보관 유실 재현 → 수리 증명).
@Test
func scannerKeepsMonthTotalWhenRolloutIsArchivedByRename() {
    let home = c41TempHome("archive-move")
    defer { try? FileManager.default.removeItem(at: home) }
    let live = c41Sessions(home, "2026/07/05/rollout-2026-07-05T00-00-00-mv.jsonl")
    c41Write([c41Event(input: 500, output: 50, at: c41July5), c41Event(input: 2_500, output: 250, at: c41July5)]
        .joined(separator: "\n") + "\n", to: live)
    let r1 = c41Scan(home: home)
    #expect(r1.usage.codexTotal == 2_200)
    #expect(r1.cache.codexFileStates.count == 1)

    // Codex CLI 의 archive_thread: std::fs::rename → archived_sessions/<같은 파일명>, mtime 보존.
    let archived = c41Archived(home, "rollout-2026-07-05T00-00-00-mv.jsonl")
    try? FileManager.default.createDirectory(at: archived.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? FileManager.default.moveItem(at: live, to: archived)
    try? FileManager.default.setAttributes([.modificationDate: c41Now], ofItemAtPath: archived.path)

    let r2 = c41Scan(r1.cache, home: home)
    #expect(r2.usage.codexTotal == 2_200, "보관 뒤 월 합이 달라졌다: \(r2.usage.codexTotal)")
    #expect(r2.cache.codexFileStates.count == 1, "옛 경로 상태가 남아 있다(이중 계상 위험)")
    #expect(c41State(r2.cache, archived) != nil)
    #expect(r2.cache.codexFileStates.keys.contains { $0.contains("/sessions/") } == false)
    // 전량 재파싱과 같다(차분 계약).
    let full = c41Scan(home: home)
    #expect(full.usage.codexTotal == r2.usage.codexTotal)
}

/// 압축(`.jsonl` → `.jsonl.zst`, 원본 삭제): 상태는 **동결**(기여 보존, 더 자라지 않음). `.zst` 는 읽지 않는다.
/// 압축이 풀려(materialize) `.jsonl` 이 되돌아오면 이어읽기 규칙이 그대로 동작해 이중 계상이 없다.
/// 뮤테이션: 정리 규칙의 `.zst` 존재 확인을 지우면(옛 규칙) 빨강.
@Test
func scannerFreezesContributionWhileRolloutIsCompressedAndResumesAfterMaterialize() {
    let home = c41TempHome("zst-freeze")
    defer { try? FileManager.default.removeItem(at: home) }
    let url = c41Sessions(home, "2026/07/05/rollout-2026-07-05T00-00-00-zst.jsonl")
    let body = [c41Event(input: 100, output: 0, at: c41July5), c41Event(input: 7_100, output: 900, at: c41July5)]
        .joined(separator: "\n") + "\n"
    c41Write(body, to: url)
    let r1 = c41Scan(home: home)
    #expect(r1.usage.codexTotal == 7_900)

    // 압축 워커: 원본 삭제 + 같은 이름 + ".zst"(내용은 zstd 프레임 — 우리는 읽지 않으므로 아무 바이트나).
    try? FileManager.default.removeItem(at: url)
    let zst = URL(fileURLWithPath: url.path + ".zst")
    c41Write("zstd-frame-bytes", to: zst)

    let r2 = c41Scan(r1.cache, home: home)
    #expect(r2.usage.codexTotal == 7_900, "압축된 파일의 이번 달 기여가 사라졌다(issue #6 의 46% 과소집계)")
    #expect(c41State(r2.cache, url) != nil, "동결돼야 할 상태가 정리됐다")
    #expect(r2.stats.codexFilesStatted == 0)    // .zst 는 순회 대상이 아니다(읽지 않는다)
    #expect(r2.stats.cacheChanged == false)     // 동결 = 상태 불변

    // materialize: `.zst` 삭제 + 바이트 동일한 `.jsonl` 복원. (a) mtime 이 새것이면 이어읽기(새 바이트 0), (b) 같으면 무변경.
    try? FileManager.default.removeItem(at: zst)
    c41Write(body, to: url, modified: c41Now.addingTimeInterval(60))
    let r3 = c41Scan(r2.cache, home: home)
    #expect(r3.usage.codexTotal == 7_900, "복원 뒤 이중 계상: \(r3.usage.codexTotal)")
    #expect(r3.stats.codexBytesRead == 0)       // 오프셋 이어읽기 — 새 바이트가 없다
    #expect(c41State(r3.cache, url)?.prevCumulative == 8_000)

    // 복원 뒤 세션이 이어지면(append) 델타가 정상 가산된다 — 동결이 '이 파일을 버린 것'이 아님을 못 박는다.
    c41Append(c41Event(input: 7_600, output: 1_000, at: c41July5) + "\n", to: url, modified: c41Now.addingTimeInterval(120))
    let r4 = c41Scan(r3.cache, home: home)
    #expect(r4.usage.codexTotal == 8_500)
}

/// `.jsonl` 도 `.zst` 도 없는 삭제는 예전처럼 정리된다(유령 기여 근절 규칙은 그대로).
@Test
func scannerStillDropsVanishedRolloutWhenNoCompressedTwinExists() {
    let home = c41TempHome("vanish")
    defer { try? FileManager.default.removeItem(at: home) }
    let a = c41Sessions(home, "2026/07/05/rollout-2026-07-05T00-00-00-a.jsonl")
    let b = c41Sessions(home, "2026/07/06/rollout-2026-07-06T00-00-00-b.jsonl")
    c41Write([c41Event(input: 100, output: 0, at: c41July5), c41Event(input: 1_100, output: 0, at: c41July5)].joined(separator: "\n") + "\n", to: a)
    c41Write([c41Event(input: 200, output: 0, at: c41July5), c41Event(input: 2_200, output: 0, at: c41July5)].joined(separator: "\n") + "\n", to: b)
    let r1 = c41Scan(home: home)
    #expect(r1.usage.codexTotal == 3_000)

    try? FileManager.default.removeItem(at: a)
    let r2 = c41Scan(r1.cache, home: home)
    #expect(r2.usage.codexTotal == 2_000)
    #expect(c41State(r2.cache, a) == nil)
    #expect(r2.stats.statesChanged == true)
}

/// 캐시 델타 분리(issue #2): 입력(캐시 포함)·출력·캐시가 각각 누적되고 필드별로 클램프된다. 캐시는 total 에 안 들어간다.
/// 뮤테이션: 캐시 델타를 total 에 더하거나, 클램프를 합산 후 한 번만 하면 빨강.
@Test
func scannerSplitsCodexDeltaIntoInputOutputAndCacheWithPerFieldClamp() {
    let home = c41TempHome("cache-split")
    defer { try? FileManager.default.removeItem(at: home) }
    let url = c41Sessions(home, "2026/07/05/rollout-2026-07-05T00-00-00-cs.jsonl")
    c41Write([
        c41Event(input: 1_000, output: 100, cached: 600, at: c41July5),   // 기준선
        c41Event(input: 3_000, output: 400, cached: 2_100, at: c41July5), // +2000 / +300 / +1500
        // 한 필드만 줄어드는 비정상 리셋: 입력 2,900(−100 → 0), 출력 900(+500), 캐시 2,000(−100 → 0).
        c41Event(input: 2_900, output: 900, cached: 2_000, at: c41July5)
    ].joined(separator: "\n") + "\n", to: url)

    let r = c41Scan(home: home)
    #expect(r.usage.codexInput == 2_000)
    #expect(r.usage.codexOutput == 800)
    #expect(r.usage.codexCacheRead == 1_500)
    #expect(r.usage.codexTotal == 2_800)
    #expect(r.usage.total == 2_800)          // 캐시 미포함
    let s = c41State(r.cache, url)!
    #expect(s.prevInput == 2_900 && s.prevOutput == 900 && s.prevCached == 2_000)
    #expect(s.monthInput == 2_000 && s.monthOutput == 800 && s.monthCached == 1_500)
    // 진단 스캐너도 같은 필드별 클램프를 미러한다(항등식이 리셋에서도 선다).
    let d = CodexUsageDiagnosticsScanner.compute(homeDirectory: home, month: "2026-07", appBuild: 1)
    #expect(d.dedupTotal + d.dupTokens == r.usage.codexTotal)
    #expect(d.drops == 0)   // 합산 누적(3,400 → 3,800)은 줄지 않았다 — drops 는 옛 합산 기준 그대로
}

/// 일별 맵: Claude 는 ts14 를 KST 일자로, Codex 는 이벤트 일키로 버킷팅한다. 두 맵의 합 == 월 합, todayTotal == 두 맵의 오늘 키 합.
/// 뮤테이션: 일 버킷 경계를 UTC 자정으로 바꾸거나 todayTotal 파생을 끊으면 빨강.
@Test
func scannerBuildsDailyMapsAndDerivesTodayTotalFromThem() {
    let home = c41TempHome("daily")
    defer { try? FileManager.default.removeItem(at: home) }
    // Claude: KST 07-03(UTC 07-02 16:00 = KST 07-03 01:00), KST 07-14 오늘 두 줄(그중 하나는 UTC 07-13 15:30 = KST 07-14 00:30 경계 직후).
    func claude(_ id: String, _ ts: Date, _ input: Int) -> String {
        "{\"type\":\"assistant\",\"timestamp\":\"\(c41ISO(ts))\",\"requestId\":\"r-\(id)\","
        + "\"message\":{\"id\":\"m-\(id)\",\"usage\":{\"input_tokens\":\(input),\"output_tokens\":1,"
        + "\"cache_read_input_tokens\":2,\"cache_creation_input_tokens\":3}}}"
    }
    c41Write([
        claude("a", c41UTC("2026-07-02T16:00:00Z"), 100),
        claude("b", c41UTC("2026-07-13T15:30:00Z"), 200),
        claude("c", c41Today, 300)
    ].joined(separator: "\n") + "\n", to: home.appendingPathComponent(".claude/projects/p/s.jsonl"))
    // Codex: 07-05 에 +1,000, 오늘 +50, 그리고 6월 이벤트(현재 월 밖 — 기준선만 전진).
    c41Write([
        c41Event(input: 10, output: 0, at: c41UTC("2026-06-20T00:00:00Z")),
        c41Event(input: 1_010, output: 0, at: c41July5),
        c41Event(input: 1_060, output: 0, at: c41Today)
    ].joined(separator: "\n") + "\n", to: c41Sessions(home, "2026/06/20/rollout-2026-06-20T00-00-00-dd.jsonl"))

    let r = c41Scan(home: home)
    #expect(r.usage.claudeDaily == ["2026-07-03": 106, "2026-07-14": 206 + 306])
    #expect(r.usage.codexDaily == ["2026-07-05": 1_000, "2026-07-14": 50])
    #expect(r.usage.claudeDaily.values.reduce(0, +) == r.usage.claudeTotal)
    #expect(r.usage.codexDaily.values.reduce(0, +) == r.usage.codexTotal)
    #expect(r.usage.todayDate == "2026-07-14")
    #expect(r.usage.todayTotal == 512 + 50)
    #expect(r.usage.codexDaily["2026-06-20"] == nil)   // 현재 월 키만
}

/// 월 롤오버: 무변경 파일(크기·mtime 동일)이라도 달이 바뀌면 월 기여와 일별 맵을 비운다(지난달 값이 새 달로 새지 않는다).
/// 뮤테이션: 무변경 롤오버 분기에서 dayContrib 를 물려주면(`dayContrib: p.dayContrib`) 빨강.
@Test
func scannerClearsDayContribOnMonthRolloverForUnchangedFile() {
    let home = c41TempHome("rollover")
    defer { try? FileManager.default.removeItem(at: home) }
    let url = c41Sessions(home, "2026/07/05/rollout-2026-07-05T00-00-00-ro.jsonl")
    // mtime 을 8월 1일 KST 새벽으로 둔다 — 7월 스캔(컷오프 7/1)도 8월 스캔(컷오프 8/1 0시)도 **같은 크기·같은 mtime** 으로 이 파일을
    // 본다. 그래야 8월 스캔이 "무변경 + 월 롤오버" 분기(재읽기 없이 키만 갱신)를 실제로 탄다.
    let augMtime = c41UTC("2026-08-01T02:00:00Z")   // KST 08-01 11:00
    c41Write([c41Event(input: 100, output: 0, at: c41July5), c41Event(input: 900, output: 100, at: c41July5)]
        .joined(separator: "\n") + "\n", to: url, modified: augMtime)
    let july = c41Scan(home: home)
    #expect(july.usage.codexTotal == 900)
    #expect(c41State(july.cache, url)?.dayContrib == ["2026-07-05": 900])

    // 8월 1일(KST) 스캔: 파일은 순회에 잡히지만 크기·mtime 이 그대로 → 무변경 롤오버 경로.
    let aug = c41Scan(july.cache, home: home, now: c41UTC("2026-08-01T03:00:00Z"))
    #expect(aug.usage.month == "2026-08")
    #expect(aug.stats.codexBytesRead == 0)           // 재읽기 없이
    #expect(aug.stats.statesChanged == true)         // 키만 갱신(저장 유도)
    #expect(aug.usage.codexTotal == 0)
    #expect(aug.usage.codexDaily.isEmpty)
    let s = c41State(aug.cache, url)
    #expect(s?.monthKey == "2026-08")
    #expect(s?.dayContrib == [:], "지난달 일별 맵이 새 달 상태에 남았다: \(String(describing: s?.dayContrib))")
    #expect(s?.monthContribTotal == 0)
    #expect(s?.prevCumulative == 1_000)   // 기준선은 파일 안에서 이어진다

    // 롤오버 뒤 8월 이벤트가 붙으면(append) 8월 몫만 센다 — 7월 일별 맵이 되살아나지 않는다.
    c41Append(c41Event(input: 1_500, output: 100, at: c41UTC("2026-08-01T02:30:00Z")) + "\n", to: url,
              modified: augMtime.addingTimeInterval(60))
    let aug2 = c41Scan(aug.cache, home: home, now: c41UTC("2026-08-01T03:00:00Z"))
    #expect(aug2.usage.codexTotal == 600)
    #expect(aug2.usage.codexDaily == ["2026-08-01": 600])
}

/// CODEX_HOME 재정의: codexHome 을 주면 `~/.codex` 대신 그 아래 두 루트를 읽는다.
@Test
func scannerHonorsCodexHomeOverride() {
    let home = c41TempHome("codex-home")
    defer { try? FileManager.default.removeItem(at: home) }
    let custom = home.appendingPathComponent("custom-codex", isDirectory: true)
    c41Write([c41Event(input: 1, output: 0, at: c41July5), c41Event(input: 11, output: 0, at: c41July5)].joined(separator: "\n") + "\n",
             to: custom.appendingPathComponent("archived_sessions/rollout-2026-07-05T00-00-00-ch.jsonl"))
    c41Write([c41Event(input: 1, output: 0, at: c41July5), c41Event(input: 1_001, output: 0, at: c41July5)].joined(separator: "\n") + "\n",
             to: c41Sessions(home, "2026/07/05/rollout-2026-07-05T00-00-00-default.jsonl"))

    #expect(c41Scan(home: home).usage.codexTotal == 1_000)                       // 기본 ~/.codex
    #expect(c41Scan(home: home, codexHome: custom).usage.codexTotal == 10)      // 재정의
    let roots = TokenUsageIncrementalScanner.codexRoots(homeDirectory: home, codexHome: nil)
    #expect(roots.map(\.lastPathComponent) == ["sessions", "archived_sessions"])
    #expect(roots[0].path.hasSuffix(".codex/sessions"))
    // 진단 스캐너도 같은 재정의를 받는다.
    #expect(CodexUsageDiagnosticsScanner.compute(homeDirectory: home, codexHome: custom, month: "2026-07", appBuild: 1).dedupTotal == 10)
}

/// 진단 스캐너도 archived_sessions 를 봐 항등식 `dedupTotal + dupTokens == codexTotal` 이 보관 파일이 있어도 선다.
@Test
func diagnosticsScannerIncludesArchivedSessionsSoIdentityHolds() {
    let home = c41TempHome("diag-archived")
    defer { try? FileManager.default.removeItem(at: home) }
    c41Write([c41Event(input: 100, output: 0, at: c41July5), c41Event(input: 600, output: 0, at: c41July5)].joined(separator: "\n") + "\n",
             to: c41Sessions(home, "2026/07/05/rollout-2026-07-05T00-00-00-live.jsonl"))
    c41Write([c41Event(input: 100, output: 0, at: c41July5), c41Event(input: 2_100, output: 0, at: c41July5)].joined(separator: "\n") + "\n",
             to: c41Archived(home, "rollout-2026-07-04T00-00-00-arch.jsonl"))
    let production = TokenUsageScanner.scan(homeDirectory: home, now: c41Now)
    let d = CodexUsageDiagnosticsScanner.compute(homeDirectory: home, month: "2026-07", appBuild: 1)
    #expect(production.codexTotal == 2_500)
    #expect(d.filesTotal == 2)
    #expect(d.dedupTotal + d.dupTokens == production.codexTotal)
}

// MARK: - (B) 계정 프로브 파서 (순수)

private let c41FetchedAt = c41UTC("2026-09-03T05:00:00Z")

private let c41GoodResponse = [
    #"{"id":1,"result":{"userAgent":"codex/0.144.1","capabilities":{}}}"#,
    #"{"method":"remoteControl/status/changed","params":{"status":"idle"}}"#,
    #"{"id":2,"result":{"summary":{"lifetimeTokens":1367529985,"peakDailyTokens":74396254,"longestRunningTurnSec":3302},"dailyUsageBuckets":[{"startDate":"2026-08-31","tokens":3879446},{"startDate":"2026-09-01","tokens":32229528},{"startDate":"2026-09-02","tokens":28000000}]}}"#,
    #"{"method":"thread/started","params":{}}"#
]

@Test
func probeParserPicksOnlyTheUsageResponseLineAmongNoise() throws {
    let usage = try CodexAccountUsageProbe.parse(lines: c41GoodResponse, fetchedAt: c41FetchedAt).get()
    #expect(usage.lifetimeTokens == 1_367_529_985)
    #expect(usage.buckets == ["2026-08-31": 3_879_446, "2026-09-01": 32_229_528, "2026-09-02": 28_000_000])
    #expect(usage.fetchedAt == c41FetchedAt)
    // 월합은 UTC 일자 접두어 매칭 — 8월 버킷은 9월 합에 들지 않는다.
    #expect(usage.monthTotal("2026-09") == 60_229_528)
    #expect(usage.monthTotal("2026-08") == 3_879_446)
    #expect(usage.monthTotal("2026-07") == 0)
    #expect(usage.latestBucketDate == "2026-09-02")
    #expect(usage.latestBucketDate(in: "2026-08") == "2026-08-31")
    #expect(usage.latestBucketDate(in: "2026-07") == nil)
}

@Test
func probeParserMapsAuthenticationErrorToNotLoggedInAndOthersToFailed() {
    let auth = CodexAccountUsageProbe.parse(
        lines: [#"{"id":1,"result":{}}"#, #"{"id":2,"error":{"code":-32000,"message":"chatgpt authentication required to read token usage"}}"#],
        fetchedAt: c41FetchedAt)
    guard case .failure(let f1) = auth else { Issue.record("에러 응답이 성공으로 파싱됐다"); return }
    #expect(f1.status == .notLoggedIn)

    let other = CodexAccountUsageProbe.parse(lines: [#"{"id":2,"error":{"message":"internal"}}"#], fetchedAt: c41FetchedAt)
    guard case .failure(let f2) = other else { Issue.record("에러 응답이 성공으로 파싱됐다"); return }
    #expect(f2.status == .failed)
}

@Test
func probeParserToleratesNullBucketsAndNullLifetime() throws {
    let usage = try CodexAccountUsageProbe.parse(
        lines: [#"{"id":2,"result":{"summary":{"lifetimeTokens":null},"dailyUsageBuckets":null}}"#], fetchedAt: c41FetchedAt).get()
    #expect(usage.lifetimeTokens == nil)
    #expect(usage.buckets.isEmpty)
    #expect(usage.monthTotal("2026-09") == 0)
    #expect(usage.latestBucketDate == nil)
    // summary 자체가 없어도 성공(프로토콜상 옵셔널).
    let bare = try CodexAccountUsageProbe.parse(lines: [#"{"id":2,"result":{}}"#], fetchedAt: c41FetchedAt).get()
    #expect(bare.lifetimeTokens == nil && bare.buckets.isEmpty)
}

@Test
func probeParserSkipsTruncatedLinesAndFailsWithoutTheUsageResponse() {
    // 잘린 JSON(id 2 응답이 중간에 끊김) → 그 줄은 버려지고 응답 없음 → failed.
    let truncated = CodexAccountUsageProbe.parse(
        lines: [#"{"id":1,"result":{}}"#, #"{"id":2,"result":{"summary":{"lifetimeTokens":12"#], fetchedAt: c41FetchedAt)
    guard case .failure(let f) = truncated else { Issue.record("잘린 응답이 성공으로 파싱됐다"); return }
    #expect(f.status == .failed)
    // 잘린 줄 뒤에 온전한 id 2 줄이 오면 그것을 쓴다.
    let recovered = CodexAccountUsageProbe.parse(
        lines: ["{\"id\":2,\"resu", "", #"{"id":2,"result":{"dailyUsageBuckets":[{"startDate":"2026-09-01","tokens":5}]}}"#],
        fetchedAt: c41FetchedAt)
    #expect((try? recovered.get())?.buckets == ["2026-09-01": 5])
    // id 가 다른 응답만 있으면 실패(id 1 을 답으로 오인하지 않는다).
    guard case .failure = CodexAccountUsageProbe.parse(lines: [#"{"id":1,"result":{"dailyUsageBuckets":[]}}"#], fetchedAt: c41FetchedAt)
    else { Issue.record("id 1 응답을 usage 응답으로 썼다"); return }
}

@Test
func probeParserPrunesBucketsOlderThanRetentionWindow() throws {
    let old = CodexAccountUsage.utcDayString(c41FetchedAt.addingTimeInterval(-71 * 86_400))
    let edge = CodexAccountUsage.utcDayString(c41FetchedAt.addingTimeInterval(-70 * 86_400))
    let line = "{\"id\":2,\"result\":{\"dailyUsageBuckets\":[{\"startDate\":\"\(old)\",\"tokens\":1},{\"startDate\":\"\(edge)\",\"tokens\":2},{\"startDate\":\"2026-09-02\",\"tokens\":3}]}}"
    let usage = try CodexAccountUsageProbe.parse(lines: [line], fetchedAt: c41FetchedAt).get()
    #expect(usage.buckets[old] == nil)
    #expect(usage.buckets[edge] == 2)
    #expect(usage.buckets["2026-09-02"] == 3)
    #expect(CodexAccountUsage.retentionDays == 70)
}

@Test
func probeRequestIsThreeJSONLMessagesWithUsageReadAsID2() {
    let lines = CodexAccountUsageProbe.requestLines(appVersion: "0.2.41")
    #expect(lines.count == 3)
    let objects = lines.map { (try? JSONSerialization.jsonObject(with: Data($0.utf8))) as? [String: Any] ?? [:] }
    #expect(objects[0]["method"] as? String == "initialize")
    #expect(objects[0]["id"] as? Int == 1)
    let client = (objects[0]["params"] as? [String: Any])?["clientInfo"] as? [String: Any]
    #expect(client?["name"] as? String == "aing-check")
    #expect(client?["version"] as? String == "0.2.41")
    #expect(objects[1]["method"] as? String == "initialized")
    #expect(objects[1]["id"] == nil)   // 알림은 id 없음
    #expect(objects[2]["method"] as? String == "account/usage/read")
    #expect(objects[2]["id"] as? Int == CodexAccountUsageProbe.usageRequestID)
    #expect(CodexAccountUsageProbe.usageRequestID == 2)
    #expect(CodexAccountUsageProbe.lineHasUsageResponseID(#"{"id":2,"result":{}}"#))
    #expect(!CodexAccountUsageProbe.lineHasUsageResponseID(#"{"id":1,"result":{}}"#))
}

@Test
func probeFallbackCandidatesStartWithHomebrewThenUserPrefixes() {
    let home = c41TempHome("candidates")
    defer { try? FileManager.default.removeItem(at: home) }
    // nvm 두 버전 + Cursor 확장 번들을 심어 글롭 규칙을 본다.
    for v in ["v20.11.0", "v22.3.0"] {
        c41Write("#!/usr/bin/env node\n", to: home.appendingPathComponent(".nvm/versions/node/\(v)/bin/codex"))
    }
    c41Write("bin", to: home.appendingPathComponent(".cursor/extensions/openai.chatgpt-1.2.3/bin/macos-arm64/codex"))
    let paths = CodexAccountUsageProbe.fallbackCandidates(homeDirectory: home).map(\.path)
    #expect(paths.first == "/opt/homebrew/bin/codex")
    #expect(paths[1] == "/usr/local/bin/codex")
    #expect(paths.contains(home.appendingPathComponent(".npm-global/bin/codex").path))
    #expect(paths.contains(home.appendingPathComponent(".volta/bin/codex").path))
    #expect(paths.contains(home.appendingPathComponent(".bun/bin/codex").path))
    #expect(paths.contains(home.appendingPathComponent(".local/bin/codex").path))
    let nvm = paths.filter { $0.contains("/.nvm/") }
    #expect(nvm.count == 2 && nvm[0].contains("v22.3.0"))   // 최신 node 먼저
    #expect(paths.contains { $0.hasSuffix(".cursor/extensions/openai.chatgpt-1.2.3/bin/macos-arm64/codex") })
    #expect(CodexAccountUsageProbe.shellLookupTimeout == 5)
    #expect(CodexAccountUsageProbe.fetchDeadline == 15)
    #expect(CodexAccountUsageProbe.killGrace == 2)
}

@Test
func probeStatusRawValuesMatchServerColumnContract() {
    // 서버 smallint 계약(20260903120000 마이그레이션 주석): 1 ok · 2 미설치 · 3 미로그인 · 4 타임아웃 · 5 실패.
    #expect(CodexAccountProbeStatus.ok.rawValue == 1)
    #expect(CodexAccountProbeStatus.codexNotInstalled.rawValue == 2)
    #expect(CodexAccountProbeStatus.notLoggedIn.rawValue == 3)
    #expect(CodexAccountProbeStatus.timeout.rawValue == 4)
    #expect(CodexAccountProbeStatus.failed.rawValue == 5)
}

// MARK: - (C) 계정 스토어

private func c41Defaults() -> UserDefaults {
    let name = "check-v0241-\(UUID().uuidString)"
    let d = UserDefaults(suiteName: name)!
    d.removePersistentDomain(forName: name)
    return d
}

/// 러너 호출을 세고 정해진 결과를 돌려주는 가짜 프로브(프로세스 0).
private final class C41Runner: @unchecked Sendable {
    private let lock = NSLock()
    private var _calls = 0
    var calls: Int { lock.withLock { _calls } }
    var result: Result<CodexAccountUsage, CodexAccountUsageProbe.Failure>
    init(_ result: Result<CodexAccountUsage, CodexAccountUsageProbe.Failure>) { self.result = result }
    func run(_ home: URL, _ now: Date) async -> Result<CodexAccountUsage, CodexAccountUsageProbe.Failure> {
        lock.withLock { _calls += 1 }
        return result
    }
}

private func c41Usage(month: Int = 60_000, fetchedAt: Date = c41FetchedAt) -> CodexAccountUsage {
    CodexAccountUsage(fetchedAt: fetchedAt, lifetimeTokens: 1_000_000, buckets: ["2026-09-01": month / 2, "2026-09-02": month - month / 2])
}

/// auth.json 을 심는다(내용은 아무거나 — 스토어는 존재 여부만 본다).
private func c41LogIn(_ home: URL) {
    c41Write("{\"tokens\":\"secret\"}", to: home.appendingPathComponent(".codex/auth.json"))
}

@MainActor
@Test
func accountStoreProbesAtMostOncePer1800SecondsUnlessForced() async {
    let home = c41TempHome("interval")
    defer { try? FileManager.default.removeItem(at: home) }
    c41LogIn(home)
    let runner = C41Runner(.success(c41Usage()))
    let store = CodexAccountUsageStore(defaults: c41Defaults(), homeDirectory: home, runner: runner.run)
    let t0 = c41FetchedAt

    await store.refreshIfDue(now: t0)
    #expect(runner.calls == 1)
    #expect(store.snapshot?.monthTotal("2026-09") == 60_000)
    #expect(store.lastStatus == .ok)
    #expect(store.lastProbeAt == t0)

    await store.refreshIfDue(now: t0.addingTimeInterval(1_799))
    #expect(runner.calls == 1, "1800초 전에 프로브가 또 돌았다")
    await store.refreshIfDue(now: t0.addingTimeInterval(1_800))
    #expect(runner.calls == 2)
    // force 는 1800초 간격을 무시하되 60초 하한은 지킨다(월 경계 창에서 30초 틱마다 프로세스가 뜨지 않게).
    await store.refreshIfDue(now: t0.addingTimeInterval(1_800 + 59), force: true)
    #expect(runner.calls == 2, "force 가 60초 하한을 뚫었다")
    await store.refreshIfDue(now: t0.addingTimeInterval(1_800 + 60), force: true)
    #expect(runner.calls == 3)
    #expect(CodexAccountUsageStore.refreshInterval == 1_800)
    #expect(CodexAccountUsageStore.forcedRefreshFloor == 60)
}

@MainActor
@Test
func accountStoreSkipsProcessWhenAuthFileIsMissing() async {
    let home = c41TempHome("no-auth")
    defer { try? FileManager.default.removeItem(at: home) }
    let runner = C41Runner(.success(c41Usage()))
    let store = CodexAccountUsageStore(defaults: c41Defaults(), homeDirectory: home, runner: runner.run)

    await store.refreshIfDue(now: c41FetchedAt, force: true)
    #expect(runner.calls == 0, "auth.json 없이 프로세스를 띄웠다")
    #expect(store.lastStatus == .notLoggedIn)
    #expect(store.snapshot == nil)
    #expect(store.lastProbeAt == c41FetchedAt)   // 스탬프는 찍힌다(30분 안에 auth.json stat 을 반복하지 않는다)

    // 로그인하면(파일 생김) 다음 기회에 돈다.
    c41LogIn(home)
    await store.refreshIfDue(now: c41FetchedAt.addingTimeInterval(1_800))
    #expect(runner.calls == 1)
    #expect(store.lastStatus == .ok)
}

@MainActor
@Test
func accountStorePersistsSnapshotAndRestoresRegardlessOfMonth() async {
    let home = c41TempHome("persist")
    defer { try? FileManager.default.removeItem(at: home) }
    c41LogIn(home)
    let defaults = c41Defaults()
    let runner = C41Runner(.success(c41Usage(month: 777)))
    let store = CodexAccountUsageStore(defaults: defaults, homeDirectory: home, runner: runner.run)
    await store.refreshIfDue(now: c41FetchedAt)
    #expect(defaults.data(forKey: CodexAccountUsageStore.snapshotKey) != nil)

    // 다른 달의 시계로 새 스토어를 만들어도 스냅샷은 복원된다(버킷이 날짜별이라 monthTotal 이 조회 시점에 달을 가른다).
    let restored = CodexAccountUsageStore(
        defaults: defaults, homeDirectory: home, clock: { c41UTC("2026-11-01T00:00:00Z") }, runner: runner.run)
    #expect(restored.snapshot == store.snapshot)
    #expect(restored.snapshot?.monthTotal("2026-09") == 777)
    #expect(restored.snapshot?.monthTotal("2026-11") == 0)
    #expect(restored.lastProbeAt == nil)   // 프로브 시각은 영속하지 않는다(재시작 후 첫 기회에 다시 묻는다)
    #expect(CodexAccountUsageStore.snapshotKey == "check.codexAccount.snapshot")
}

@MainActor
@Test
func accountStoreKeepsPreviousSnapshotWhenProbeFails() async {
    let home = c41TempHome("fail-keeps")
    defer { try? FileManager.default.removeItem(at: home) }
    c41LogIn(home)
    let runner = C41Runner(.success(c41Usage(month: 10)))
    let store = CodexAccountUsageStore(defaults: c41Defaults(), homeDirectory: home, runner: runner.run)
    await store.refreshIfDue(now: c41FetchedAt)
    runner.result = .failure(.init(status: .timeout, reason: "15초"))
    await store.refreshIfDue(now: c41FetchedAt.addingTimeInterval(1_800))
    #expect(store.lastStatus == .timeout)
    #expect(store.snapshot?.monthTotal("2026-09") == 10)   // 직전 값 유지(버킷은 낡아도 틀리지 않는다)
}

@MainActor
@Test
func accountStoreDoesNotReenterWhileAProbeIsInFlight() async {
    let home = c41TempHome("reentry")
    defer { try? FileManager.default.removeItem(at: home) }
    c41LogIn(home)
    let calls = C41Runner(.success(c41Usage()))
    let store = CodexAccountUsageStore(defaults: c41Defaults(), homeDirectory: home) { home, now in
        // 느린 프로브(실제 0.8초를 흉내) — 그 사이 들어온 두 번째 호출은 되돌아가야 한다.
        try? await Task.sleep(for: .milliseconds(150))
        return await calls.run(home, now)
    }
    async let first: Void = store.refreshIfDue(now: c41FetchedAt, force: true)
    try? await Task.sleep(for: .milliseconds(20))
    #expect(store.isDue(now: c41FetchedAt.addingTimeInterval(3_600), force: true) == false)   // 진행 중이면 force 여도 거짓
    await store.refreshIfDue(now: c41FetchedAt.addingTimeInterval(3_600), force: true)
    await first
    #expect(calls.calls == 1, "진행 중인 프로브 옆에 두 번째 프로세스가 떴다")
}

@MainActor
@Test
func inertAccountStoreNeverRunsAProcess() async {
    let store = CodexAccountUsageStore.inert()
    await store.refreshIfDue(now: c41FetchedAt, force: true)
    #expect(store.runnerCallCount == 0)
    #expect(store.lastStatus == .notLoggedIn)
    #expect(store.snapshot == nil)
}

// MARK: - (D) 업로드 계약 (URLProtocolStub)

private let c41UserID = "00000000-0000-0000-0000-000000000003"
private let c41DevicePath = "/rest/v1/token_usage_device_monthly"

@MainActor
private func c41TokenStore(home: URL, now: Date, snapshot: TokenUsageMonthly?) -> TokenUsageStore {
    let defaults = c41Defaults()
    if let snapshot, let data = try? JSONEncoder().encode(snapshot) {
        defaults.set(data, forKey: TokenUsageStore.snapshotKey)
    }
    return TokenUsageStore(
        defaults: defaults, homeDirectory: home,
        cacheURL: c41TempHome("cache").appendingPathComponent("cache.json", isDirectory: false),
        clock: { now }, notificationCenter: NotificationCenter(), codexHomeResolver: { nil }
    )
}

@MainActor
private func c41Store(host: String, tokenUsage: TokenUsageStore, codexAccount: CodexAccountUsageStore? = nil) -> WorkTimerStore {
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!, anonKey: "anon-test-key", session: URLSession(configuration: .stubbed))
    let store = WorkTimerStore(
        service: service, environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"], defaults: c41Defaults(),
        workspaceNotifications: nil, tokenUsage: tokenUsage, codexAccount: codexAccount)
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: c41UserID)
    store.currentTeamID = URLProtocolStub.stubTeamID
    store.membershipConfirmed = true
    store.isMenuPresented = false
    return store
}

@MainActor
private func c41CancelTasks(_ store: WorkTimerStore) {
    store.tickerTask?.cancel(); store.refreshTask?.cancel(); store.syncTask?.cancel(); store.pokePollTask?.cancel()
}

/// 사용량 upsert 본문(하트비트 제외 — codex_input 키가 있는 것만)들.
private func c41UploadBodies(host: String) -> [[String: Any]] {
    zip(URLProtocolStub.requests(forHost: host), URLProtocolStub.bodies(forHost: host))
        .filter { $0.0.url?.path == c41DevicePath && $0.0.httpMethod == "POST" }
        .compactMap { (try? JSONSerialization.jsonObject(with: Data($0.1.utf8))) as? [String: Any] }
        .filter { $0["codex_input"] != nil }
}

/// KST 2026-09-03 12:00 — 계정 버킷(9월)과 같은 달.
private let c41SepNow = c41UTC("2026-09-03T03:00:00Z")

private func c41LocalUsage(total: Int) -> TokenUsageMonthly {
    var u = TokenUsageMonthly(month: "2026-09")
    u.claudeInput = total
    u.codexInput = 0
    u.codexCacheRead = 42
    u.todayDate = "2026-09-03"
    return u
}

/// 계정 nil → codex_account_* 키 0개, codex_cache_read 는 항상 실린다. 계정이 있으면 다섯 키가 값으로 실린다.
@MainActor
@Test
func uploadBodyOmitsAccountKeysWhenAbsentAndCarriesCacheReadAlways() async throws {
    let host = "v0241-body-keys"
    let home = c41TempHome("body-keys-home")
    defer { try? FileManager.default.removeItem(at: home) }
    let store = c41Store(host: host, tokenUsage: c41TokenStore(home: home, now: c41SepNow, snapshot: nil))
    defer { c41CancelTasks(store) }

    await store.uploadTokenUsageIfNeeded(usage: c41LocalUsage(total: 1_000), now: c41SepNow)
    let first = try #require(c41UploadBodies(host: host).first)
    #expect(first["codex_cache_read"] as? Int == 42)
    #expect(first.keys.filter { $0.hasPrefix("codex_account") }.isEmpty, "계정 없이 codex_account_* 가 실렸다: \(first.keys.sorted())")
    #expect(first["total"] as? Int == 1_000)   // 로컬 total 불변(캐시 미포함)

    // 계정 스냅샷 + 상태와 함께 60초 뒤 다시 올리면 다섯 키가 실린다.
    let account = c41Usage(month: 500_000, fetchedAt: c41SepNow.addingTimeInterval(-60))
    await store.uploadTokenUsageIfNeeded(usage: c41LocalUsage(total: 1_000), account: account, accountStatus: .ok, now: c41SepNow.addingTimeInterval(61))
    let second = try #require(c41UploadBodies(host: host).last)
    #expect(c41UploadBodies(host: host).count == 2)
    #expect(second["codex_account_month"] as? Int == 500_000)
    #expect(second["codex_account_lifetime"] as? Int == 1_000_000)
    #expect(second["codex_account_status"] as? Int == 1)
    #expect(second["codex_account_last_day"] as? String == "2026-09-02")
    let at = try #require(second["codex_account_at"] as? String)
    #expect(ISO8601DateFormatter().date(from: at) == account.fetchedAt)
    // 상태만 있고 스냅샷이 없으면 status 만 실린다(미로그인 3).
    await store.uploadTokenUsageIfNeeded(usage: c41LocalUsage(total: 1_000), account: nil, accountStatus: .notLoggedIn, now: c41SepNow.addingTimeInterval(122))
    let third = try #require(c41UploadBodies(host: host).last)
    #expect(third["codex_account_status"] as? Int == 3)
    #expect(third["codex_account_month"] == nil && third["codex_account_lifetime"] == nil)
}

/// 로컬 0 + 계정 > 0 이면 업로드된다(옛 게이트 `usage.total > 0` 만이면 침묵). 계정 0·로컬 0 은 여전히 침묵.
@MainActor
@Test
func uploadHappensWhenLocalIsZeroButAccountMonthIsPositive() async {
    let host = "v0241-local-zero"
    let home = c41TempHome("local-zero-home")
    defer { try? FileManager.default.removeItem(at: home) }
    let store = c41Store(host: host, tokenUsage: c41TokenStore(home: home, now: c41SepNow, snapshot: nil))
    defer { c41CancelTasks(store) }

    await store.uploadTokenUsageIfNeeded(usage: c41LocalUsage(total: 0), account: nil, now: c41SepNow)
    #expect(c41UploadBodies(host: host).isEmpty)
    await store.uploadTokenUsageIfNeeded(usage: c41LocalUsage(total: 0), account: c41Usage(month: 0), accountStatus: .ok, now: c41SepNow)
    #expect(c41UploadBodies(host: host).isEmpty, "계정 월합 0 인데 빈 행을 올렸다")

    await store.uploadTokenUsageIfNeeded(usage: c41LocalUsage(total: 0), account: c41Usage(month: 900), accountStatus: .ok, now: c41SepNow)
    let bodies = c41UploadBodies(host: host)
    #expect(bodies.count == 1)
    #expect(bodies.first?["total"] as? Int == 0)
    #expect(bodies.first?["codex_account_month"] as? Int == 900)
}

/// usage 가 그대로여도 계정값(월합·누적·상태)이 바뀌면 올린다. 둘 다 그대로면 60초가 지나도 침묵(변경 게이트).
@MainActor
@Test
func uploadFiresWhenOnlyTheAccountValuesChange() async {
    let host = "v0241-account-change"
    let home = c41TempHome("account-change-home")
    defer { try? FileManager.default.removeItem(at: home) }
    let store = c41Store(host: host, tokenUsage: c41TokenStore(home: home, now: c41SepNow, snapshot: nil))
    defer { c41CancelTasks(store) }
    let usage = c41LocalUsage(total: 5_000)
    let a1 = c41Usage(month: 100, fetchedAt: c41SepNow)

    await store.uploadTokenUsageIfNeeded(usage: usage, account: a1, accountStatus: .ok, now: c41SepNow)
    #expect(c41UploadBodies(host: host).count == 1)
    // 같은 값 → 침묵.
    await store.uploadTokenUsageIfNeeded(usage: usage, account: a1, accountStatus: .ok, now: c41SepNow.addingTimeInterval(61))
    #expect(c41UploadBodies(host: host).count == 1)
    // 계정 월합만 바뀜(다른 기기에서 더 씀) → 업로드.
    let a2 = c41Usage(month: 200, fetchedAt: c41SepNow)
    await store.uploadTokenUsageIfNeeded(usage: usage, account: a2, accountStatus: .ok, now: c41SepNow.addingTimeInterval(122))
    #expect(c41UploadBodies(host: host).count == 2)
    // 상태만 바뀜(ok → timeout, 스냅샷 그대로) → 업로드.
    await store.uploadTokenUsageIfNeeded(usage: usage, account: a2, accountStatus: .timeout, now: c41SepNow.addingTimeInterval(183))
    #expect(c41UploadBodies(host: host).count == 3)
    #expect(c41UploadBodies(host: host).last?["codex_account_status"] as? Int == 4)
    // 60초 스로틀은 계정 변경에도 적용된다.
    await store.uploadTokenUsageIfNeeded(usage: usage, account: c41Usage(month: 300), accountStatus: .ok, now: c41SepNow.addingTimeInterval(200))
    #expect(c41UploadBodies(host: host).count == 3)
    // 변경 게이트 키 산식 자체.
    #expect(WorkTimerStore.accountUploadKey(account: nil, month: "2026-09", status: nil) == nil)
    #expect(WorkTimerStore.accountUploadKey(account: a1, month: "2026-09", status: .ok)
            != WorkTimerStore.accountUploadKey(account: a2, month: "2026-09", status: .ok))
    #expect(WorkTimerStore.accountUploadKey(account: a1, month: "2026-09", status: .ok)
            == WorkTimerStore.accountUploadKey(account: a1, month: "2026-09", status: .ok))
    // 받은 시각만 다른 스냅샷(30분마다 같은 값을 다시 받은 경우)은 같은 키 — 헛업로드가 없다.
    let a1Later = c41Usage(month: 100, fetchedAt: c41SepNow.addingTimeInterval(1_800))
    #expect(WorkTimerStore.accountUploadKey(account: a1, month: "2026-09", status: .ok)
            == WorkTimerStore.accountUploadKey(account: a1Later, month: "2026-09", status: .ok))
    #expect(WorkTimerStore.accountUploadKey(account: a1, month: "2026-09", status: .ok) == "100|1000000|1")
}

/// 래퍼(`uploadTokenUsageIfNeeded(now:)`)가 프로브를 먼저 돌리고 그 스냅샷을 본문에 싣는다. 수집 거부·로그아웃이면 프로브도 안 돈다.
@MainActor
@Test
func uploadWrapperRefreshesAccountProbeBeforeUploadingAndRespectsGates() async throws {
    let host = "v0241-wrapper"
    let home = c41TempHome("wrapper-home")
    defer { try? FileManager.default.removeItem(at: home) }
    c41LogIn(home)
    let runner = C41Runner(.success(c41Usage(month: 12_345, fetchedAt: c41SepNow)))
    let account = CodexAccountUsageStore(defaults: c41Defaults(), homeDirectory: home, runner: runner.run)
    let tokenUsage = c41TokenStore(home: home, now: c41SepNow, snapshot: c41LocalUsage(total: 3_000))
    let store = c41Store(host: host, tokenUsage: tokenUsage, codexAccount: account)
    defer { c41CancelTasks(store) }
    #expect(store.codexAccount === account)

    // 수집 거부 → 프로브 0.
    store.tokenUsageCollect = false
    await store.uploadTokenUsageIfNeeded(now: c41SepNow)
    #expect(runner.calls == 0, "수집 거부자 맥에서 codex 프로세스가 떴다")
    store.tokenUsageCollect = true
    // 로그아웃 → 프로브 0.
    let signedIn = store.session
    store.session = nil
    await store.uploadTokenUsageIfNeeded(now: c41SepNow)
    #expect(runner.calls == 0)
    store.session = signedIn

    await store.uploadTokenUsageIfNeeded(now: c41SepNow)
    #expect(runner.calls == 1)
    let body = try #require(c41UploadBodies(host: host).first)
    #expect(body["codex_account_month"] as? Int == 12_345)
    #expect(body["codex_account_status"] as? Int == 1)
    #expect(store.lastUploadedAccountKey != nil)
}

/// 래퍼의 force 는 롤오버(들고 있는 값의 달 ≠ 이번 달, nil 포함)에 걸리되 60초 하한을 지킨다 — 첫 스캔 전 30초 틱이
/// 프로세스를 난사하지 않는다. 값이 이번 달이면 force 가 아니라 1800초 간격을 탄다.
@MainActor
@Test
func uploadWrapperForcesAccountProbeOnRolloverWithSixtySecondFloor() async {
    let host = "v0241-wrapper-force"
    let home = c41TempHome("wrapper-force-home")
    defer { try? FileManager.default.removeItem(at: home) }
    c41LogIn(home)
    let runner = C41Runner(.success(c41Usage(month: 1, fetchedAt: c41SepNow)))
    let account = CodexAccountUsageStore(defaults: c41Defaults(), homeDirectory: home, runner: runner.run)
    // usage nil(= 달이 바뀌어 스냅샷이 복원되지 않은 모양이자 첫 스캔 전): 30초 뒤 틱은 하한에 막히고 60초 뒤 틱만 당겨 돈다.
    let store = c41Store(host: host, tokenUsage: c41TokenStore(home: home, now: c41SepNow, snapshot: nil), codexAccount: account)
    defer { c41CancelTasks(store) }
    await store.uploadTokenUsageIfNeeded(now: c41SepNow)
    #expect(runner.calls == 1)
    await store.uploadTokenUsageIfNeeded(now: c41SepNow.addingTimeInterval(30))
    #expect(runner.calls == 1, "롤오버 force 가 60초 하한을 뚫고 30초 틱마다 프로세스를 띄운다")
    await store.uploadTokenUsageIfNeeded(now: c41SepNow.addingTimeInterval(60))
    #expect(runner.calls == 2)

    // 이번 달 값을 들고 있으면(스캔 완료) force 가 아니다 — 1800초 전엔 다시 묻지 않는다.
    let current = c41Store(host: host + "-current", tokenUsage: c41TokenStore(home: home, now: c41SepNow, snapshot: c41LocalUsage(total: 5)), codexAccount: account)
    defer { c41CancelTasks(current) }
    await current.uploadTokenUsageIfNeeded(now: c41SepNow.addingTimeInterval(200))
    #expect(runner.calls == 2)
    await current.uploadTokenUsageIfNeeded(now: c41SepNow.addingTimeInterval(60 + 1_800))
    #expect(runner.calls == 3)
}

/// 스토어 기본값(주입 없음)은 무해 인스턴스라 업로드 경로에서 프로세스를 띄우지 않는다(fail-closed).
@MainActor
@Test
func defaultAccountStoreIsInertSoUploadPathSpawnsNothing() async {
    let host = "v0241-default-inert"
    let home = c41TempHome("default-inert-home")
    defer { try? FileManager.default.removeItem(at: home) }
    let store = c41Store(host: host, tokenUsage: c41TokenStore(home: home, now: c41SepNow, snapshot: c41LocalUsage(total: 10)))
    defer { c41CancelTasks(store) }
    await store.uploadTokenUsageIfNeeded(now: c41SepNow)
    #expect(store.codexAccount.runnerCallCount == 0)
    #expect(store.codexAccount.lastStatus == .notLoggedIn)
    #expect(c41UploadBodies(host: host).first?["codex_account_status"] as? Int == 3)   // 상태만 실린다
}

/// 하트비트 본문은 여전히 다섯 키뿐 — 계정 키도 캐시 키도 섞이지 않는다.
@MainActor
@Test
func heartbeatBodyStillCarriesExactlyFiveKeysAfterAccountFields() async throws {
    let host = "v0241-heartbeat"
    let home = c41TempHome("heartbeat-home")
    defer { try? FileManager.default.removeItem(at: home) }
    c41Write(c41Event(input: 1, output: 0, at: c41SepNow.addingTimeInterval(-3_600)) + "\n",
             to: c41Sessions(home, "2026/09/03/rollout-2026-09-03T00-00-00-hb.jsonl"), modified: c41SepNow)
    let tokenUsage = c41TokenStore(home: home, now: c41SepNow, snapshot: nil)
    let store = c41Store(host: host, tokenUsage: tokenUsage)
    defer { c41CancelTasks(store) }
    await tokenUsage.refreshIfStale()
    await store.sendTokenScanHeartbeatIfNeeded(now: c41SepNow)
    let body = try #require(URLProtocolStub.bodies(forHost: host).first)
    let object = try #require((try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? [String: Any])
    #expect(Set(object.keys) == ["user_id", "month", "device_id", "last_scan_at", "scan_files"])
}

// MARK: - (E) 보드 디코드 · 표시 산식 · 계약

@Test
func tokenBoardRowDecodesWithAndWithoutTheNewColumns() throws {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let newRPC = #"[{"user_id":"a","display_name":"영","avatar_url":null,"claude_input":1,"claude_output":2,"claude_cache_read":3,"claude_cache_creation":4,"codex_input":100,"codex_output":20,"total":1010,"today_total":5,"today_date":"2026-09-03","codex_cache_read":60,"codex_account_month":1000}]"#
    let rows = try decoder.decode([TokenBoardRow].self, from: Data(newRPC.utf8))
    let entry = try #require(rows.toTokenBoardEntries().first)
    #expect(entry.codexCacheRead == 60)
    #expect(entry.codexAccountMonth == 1_000)
    #expect(entry.claudeTotal == 10)
    #expect(entry.codexLocalTotal == 120)
    #expect(entry.codexEffective == 1_000)
    #expect(entry.total == 1_010)

    let oldRPC = #"[{"user_id":"b","display_name":"민","avatar_url":null,"claude_input":1,"claude_output":0,"claude_cache_read":0,"claude_cache_creation":0,"codex_input":300,"codex_output":0,"total":301}]"#
    let old = try #require(try decoder.decode([TokenBoardRow].self, from: Data(oldRPC.utf8)).toTokenBoardEntries().first)
    #expect(old.codexCacheRead == 0)
    #expect(old.codexAccountMonth == nil)      // "모름"은 0 과 다르다
    #expect(old.codexEffective == 300)          // 계정 없으면 로컬
    // 계정 null 은 nil 로(0 이 아니라).
    let nullAccount = #"[{"user_id":"c","display_name":"c","avatar_url":null,"claude_input":0,"claude_output":0,"claude_cache_read":0,"claude_cache_creation":0,"codex_input":0,"codex_output":0,"total":0,"codex_cache_read":0,"codex_account_month":null}]"#
    #expect(try decoder.decode([TokenBoardRow].self, from: Data(nullAccount.utf8)).first?.codexAccountMonth == nil)
}

@Test
func effectiveTotalUsesLargerOfLocalCodexAndAccountMonth() {
    var local = TokenUsageMonthly(month: "2026-09")
    local.claudeInput = 1_000; local.claudeCacheRead = 9_000
    local.codexInput = 400; local.codexOutput = 100; local.codexCacheRead = 350
    #expect(TokenUsageDisplay.effectiveTotal(local: local, accountMonth: nil) == 10_500)
    #expect(TokenUsageDisplay.effectiveTotal(local: local, accountMonth: 0) == 10_500)
    #expect(TokenUsageDisplay.effectiveTotal(local: local, accountMonth: 499) == 10_500)   // 로컬(500)이 크다
    #expect(TokenUsageDisplay.effectiveTotal(local: local, accountMonth: 500) == 10_500)   // 동률
    #expect(TokenUsageDisplay.effectiveTotal(local: local, accountMonth: 501) == 10_501)   // 계정이 크면 계정
    #expect(TokenUsageDisplay.effectiveTotal(local: local, accountMonth: -5) == 10_500)    // 음수 방어
    #expect(local.total == 10_500)                                                          // 업로드값 불변(캐시 미포함)
}

@Test
func tooltipAppendsAccountLinesOnlyWhenAccountMonthIsPositive() {
    var usage = TokenUsageMonthly(month: "2026-09")
    usage.codexInput = 1_000; usage.codexOutput = 200; usage.codexCacheRead = 700
    let base = "Codex 1,200 (입력 1,000 · 출력 200 · 캐시 700)"
    #expect(usage.detailTooltip == base)
    // 계정이 로컬보다 크면 총합에 계정값이 쓰였음을 명시.
    let big = CodexAccountUsage(fetchedAt: c41FetchedAt, lifetimeTokens: nil, buckets: ["2026-09-01": 3_000, "2026-09-07": 2_000, "2026-08-31": 999])
    #expect(usage.detailTooltip(account: big) == base + " · Codex 계정 집계 5,000 (7일까지 반영) · 총합은 계정 집계 기준")
    // 계정이 로컬 이하면 반영일만.
    let small = CodexAccountUsage(fetchedAt: c41FetchedAt, lifetimeTokens: nil, buckets: ["2026-09-02": 1_200])
    #expect(usage.detailTooltip(account: small) == base + " · Codex 계정 집계 1,200 (2일까지 반영)")
    // 이 달 버킷이 없으면(월합 0) 계정 줄 없음 — 지난달 버킷을 이번 달 반영일로 오인하지 않는다.
    let lastMonthOnly = CodexAccountUsage(fetchedAt: c41FetchedAt, lifetimeTokens: nil, buckets: ["2026-08-31": 999])
    #expect(usage.detailTooltip(account: lastMonthOnly) == base)
}

@Test
func monthlySnapshotRoundTripsCacheAndDailyMapsAndDecodesLegacyWithoutThem() throws {
    var original = TokenUsageMonthly(month: "2026-09")
    original.codexInput = 10; original.codexCacheRead = 4; original.todayTotal = 3; original.todayDate = "2026-09-03"
    original.claudeDaily = ["2026-09-01": 1, "2026-09-03": 2]
    original.codexDaily = ["2026-09-03": 1]
    let data = try JSONEncoder().encode(original)
    #expect(try JSONDecoder().decode(TokenUsageMonthly.self, from: data) == original)
    // v0.2.40 스냅샷(새 키 없음) → 기본값.
    let legacy = #"{"month":"2026-09","claudeInput":10,"codexInput":50,"codexOutput":0,"todayTotal":7,"todayDate":"2026-09-03"}"#
    let decoded = try JSONDecoder().decode(TokenUsageMonthly.self, from: Data(legacy.utf8))
    #expect(decoded.codexCacheRead == 0 && decoded.claudeDaily.isEmpty && decoded.codexDaily.isEmpty)
    #expect(decoded.todayTotal == 7)
}

// MARK: 소스/SQL 계약

private func c41RepoURL(_ relative: String) -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent(relative)
}

/// `//` 줄 주석과 `/* */` 블록 주석을 걷어낸다(하우스 규칙 — 안 걷어내면 설명을 지워야만 초록이 되는 테스트가 된다).
private func c41StrippingComments(_ source: String) -> String {
    var result = ""
    var inString = false, inLineComment = false, inBlockComment = false
    var previous: Character = " "
    let chars = Array(source)
    var i = 0
    while i < chars.count {
        let c = chars[i]
        let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil
        if inLineComment {
            if c == "\n" { inLineComment = false; result.append(c) }
        } else if inBlockComment {
            if c == "*", next == "/" { inBlockComment = false; i += 1 }
        } else if inString {
            if c == "\"", previous != "\\" { inString = false }
            result.append(c)
        } else if c == "/", next == "/" {
            inLineComment = true; i += 1
        } else if c == "/", next == "*" {
            inBlockComment = true; i += 1
        } else if c == "\"" {
            inString = true; result.append(c)
        } else {
            result.append(c)
        }
        previous = c
        i += 1
    }
    return result
}

/// 프로덕션 조립 계약: 라이브 프로브는 CheckApp 한 곳에서만, 스토어 기본값은 무해 인스턴스, 행은 표시 산식을 쓴다.
@Test
func sourceContractLiveAccountStoreIsBuiltOnlyInCheckApp() throws {
    let sources = try FileManager.default.contentsOfDirectory(atPath: c41RepoURL("Sources/check").path)
        .filter { $0.hasSuffix(".swift") }
    var liveSites: [String] = []
    for name in sources {
        let code = c41StrippingComments(try String(contentsOf: c41RepoURL("Sources/check/\(name)"), encoding: .utf8))
        let n = code.components(separatedBy: "CodexAccountUsageStore.live(").count - 1
        if n > 0 { liveSites.append("\(name):\(n)") }
    }
    #expect(liveSites == ["CheckApp.swift:1"], "라이브 프로브 조립 지점: \(liveSites)")

    let app = c41StrippingComments(try String(contentsOf: c41RepoURL("Sources/check/CheckApp.swift"), encoding: .utf8))
    #expect(app.contains("codexAccount: CodexAccountUsageStore.live()"))
    let store = c41StrippingComments(try String(contentsOf: c41RepoURL("Sources/check/WorkTimerStore.swift"), encoding: .utf8))
    #expect(store.contains("codexAccount: CodexAccountUsageStore? = nil"))
    #expect(store.contains("self.codexAccount = codexAccount ?? CodexAccountUsageStore.inert()"))
    let row = c41StrippingComments(try String(contentsOf: c41RepoURL("Sources/check/CheckTokenUsage.swift"), encoding: .utf8))
    #expect(row.contains("TokenUsageDisplay.effectiveTotal(local: usage, accountMonth: accountMonth(for: usage))"))
    #expect(row.contains(".help(usage.detailTooltip(account: account?.snapshot))"))
    let menu = c41StrippingComments(try String(contentsOf: c41RepoURL("Sources/check/CheckMenuView.swift"), encoding: .utf8))
    #expect(menu.contains("CheckTokenUsageRow(store: store.tokenUsage, account: store.codexAccount"))
    // 하트비트 본문은 여전히 다섯 필드다(구조체에 let 이 5개).
    let models = c41StrippingComments(try String(contentsOf: c41RepoURL("Sources/check/SupabaseWorkModels.swift"), encoding: .utf8))
    let heartbeat = try #require(models.components(separatedBy: "struct TokenScanHeartbeatRequest: Encodable {").last?
        .components(separatedBy: "}").first)
    #expect(heartbeat.components(separatedBy: "let ").count - 1 == 5)
    // 프로브 스토어는 auth.json 을 읽지 않고 존재만 본다(내용엔 토큰이 있다).
    let probe = c41StrippingComments(try String(contentsOf: c41RepoURL("Sources/check/CheckCodexAccountUsage.swift"), encoding: .utf8))
    #expect(probe.contains("FileManager.default.fileExists(atPath: authPath)"))
    #expect(!probe.contains("contentsOf: authPath") && !probe.contains("Data(contentsOf: home"))
    #expect(probe.contains("standardError = FileHandle.nullDevice"))
}

/// 서버 마이그레이션 계약(20260903120000): 컬럼 6개 · 보드 14컬럼 · 계정은 max · greatest · 진단 판정 · anon 차단 · 프로브 롤백.
@Test
func migrationContractCodexAccountUsage() throws {
    let url = c41RepoURL("supabase/migrations/20260903120000_codex_account_usage.sql")
    guard FileManager.default.fileExists(atPath: url.path) else {
        // supabase/ 는 gitignore 라 체크아웃에 없을 수 있다(워크트리) — 그때는 계약을 검사할 대상이 없다.
        return
    }
    let sql = try String(contentsOf: url, encoding: .utf8)
    for column in ["codex_cache_read bigint not null default 0", "codex_account_month bigint", "codex_account_lifetime bigint",
                   "codex_account_at timestamptz", "codex_account_last_day text", "codex_account_status smallint"] {
        #expect(sql.contains("add column if not exists \(column)"), "컬럼 정의 누락: \(column)")
    }
    #expect(sql.contains("drop function if exists public.token_usage_board(text);"))
    #expect(sql.contains("  today_date text,\n  codex_cache_read bigint,\n  codex_account_month bigint\n)"))
    #expect(sql.contains("max(d.codex_account_month)::bigint as codex_account"))
    #expect(!sql.contains("sum(d.codex_account_month)"))
    #expect(sql.contains("+ greatest(sum(d.codex_input + d.codex_output), coalesce(max(d.codex_account_month), 0))"))
    #expect(sql.contains("revoke execute on function public.token_usage_board(text) from anon;"))
    #expect(sql.contains("grant execute on function public.token_usage_board(text) to authenticated;"))
    #expect(sql.contains("drop function if exists public.token_scan_health(text);"))
    #expect(sql.contains("'로컬 로그 없음(계정 집계로 대체)'"))
    #expect(sql.contains("grant  execute on function public.token_scan_health(text) to service_role;"))
    #expect(sql.contains("raise exception 'CODEX_ACCOUNT_USAGE_PROBE_ROLLBACK';"))
    #expect(sql.contains("if sqlerrm <> 'CODEX_ACCOUNT_USAGE_PROBE_ROLLBACK' then raise; end if;"))
    #expect(sql.contains("if n <> 18 then"))   // 새 컬럼 6 × 3 권한
    #expect(!sql.contains("create table"))     // 표를 만들지 않는다(PGRST201 회피)
}
