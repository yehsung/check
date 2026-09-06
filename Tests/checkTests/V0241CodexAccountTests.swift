import Foundation
import Testing
@testable import check

// MARK: - v0.2.41: Codex 집계 정확화(issue #6 + #2) 회귀 그물
//
// 이 파일이 지키는 것:
//   (A) 스캐너 — archived_sessions 루트 집계, 보관(rename) 무손실·무중복, `.zst` 동결 보존, `.zst` 없는 삭제는 정리,
//       압축된 채 루트를 옮긴 파일 동결(리뷰 P2), 열거 뒤 옮겨진 경로의 옛 상태 정리(리뷰 P2 — 이중 계상 방지),
//       캐시 델타 분리(필드별 클램프), 일별 맵·todayTotal 파생 일치, 월 롤오버 시 일별 맵 비움, CODEX_HOME 재정의,
//       진단 스캐너의 두 루트 항등식.
//   (B) 계정 프로브 파서 — 정상/잡음/에러/null 버킷/잘림/월합·UTC prefix/보관 정리/요청 모양/폴백 후보/후보 PATH(리뷰 P1)/
//       셸 조회 파서/툴체인 확정 규칙.
//   (C) 계정 스토어 — 1800초 간격·force·auth.json 부재(프로세스 0)·CODEX_HOME 아래 auth.json(리뷰 P2)·영속 왕복·
//       실패 시 직전 스냅샷 유지·재진입.
//   (D) 업로드 계약(URLProtocolStub) — 본문 키 존재/생략, 로컬 0 + 계정 > 0 업로드, 계정값만 바뀌어도 업로드,
//       하트비트 5키 불변, 기본 스토어는 프로세스를 띄우지 않는다, 수집 설정 도착 전엔 프로브 없음(리뷰 P2).
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

/// 열거자와 같은 정규 경로(realpath — `/var` → `/private/var`). `resolvingSymlinksInPath()` 는 `/private` 접두어를 일부러 벗기므로
/// 쓸 수 없다. 손으로 만든 파일 목록을 스캐너에 넘길 때 키가 갈리지 않게 한다(파일이 존재해야 한다).
private func c41Canonical(_ url: URL) -> URL {
    guard let raw = realpath(url.path, nil) else { return url }
    defer { free(raw) }
    return URL(fileURLWithPath: String(cString: raw), isDirectory: false)
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

/// 이미 압축된(`.zst`) 파일이 보관/보관 해제로 루트를 옮겨도 이번 달 기여가 보존된다(리뷰 P2 — codex 소스로 확인:
/// 보관은 물리 경로 `.jsonl.zst` 를 그대로 archived_sessions 로 rename 하고, 보관 해제는 파일명 날짜로 sessions/YYYY/MM/DD 에 되돌린다).
/// 옛 규칙(같은 경로의 `.zst` 만 확인)은 옛 경로에 아무것도 없어 상태를 지웠고 새 경로의 `.zst` 는 읽을 수 없어 몫이 사라졌다.
/// 뮤테이션: compressedTwinCandidates 를 `[path + ".zst"]` 로 되돌리면 빨강.
@Test
func scannerFreezesCompressedRolloutMovedBetweenRoots() {
    let home = c41TempHome("zst-move")
    defer { try? FileManager.default.removeItem(at: home) }
    let name = "rollout-2026-07-05T00-00-00-mvz.jsonl"
    let live = c41Sessions(home, "2026/07/05/\(name)")
    c41Write([c41Event(input: 300, output: 0, at: c41July5), c41Event(input: 4_300, output: 200, at: c41July5)]
        .joined(separator: "\n") + "\n", to: live)
    let r1 = c41Scan(home: home)
    #expect(r1.usage.codexTotal == 4_200)

    // 압축 워커: 원본 삭제 + `.zst`. 그 다음 사용자가 보관 → `.zst` 가 archived_sessions 로 rename.
    try? FileManager.default.removeItem(at: live)
    let archivedZst = c41Archived(home, name + ".zst")
    c41Write("zstd-frame-bytes", to: archivedZst)
    let r2 = c41Scan(r1.cache, home: home)
    #expect(r2.usage.codexTotal == 4_200, "압축된 채 보관된 파일의 기여가 사라졌다: \(r2.usage.codexTotal)")
    #expect(c41State(r2.cache, live) != nil, "동결돼야 할 옛 경로 상태가 정리됐다")
    #expect(r2.stats.codexFilesStatted == 0)

    // 보관 해제: archived 의 `.zst` 가 sessions/2026/07/05/ 로 돌아간다(옛 경로 = 원래 경로 + .zst → 기존 규칙으로도 동결).
    try? FileManager.default.removeItem(at: archivedZst)
    c41Write("zstd-frame-bytes", to: URL(fileURLWithPath: live.path + ".zst"))
    let r3 = c41Scan(r2.cache, home: home)
    #expect(r3.usage.codexTotal == 4_200)

    // 반대 방향: archived 에서 스캔한 파일이 압축된 뒤 보관 해제로 sessions/YYYY/MM/DD/<이름>.zst 가 된 경우.
    let archivedName = "rollout-2026-07-06T09-30-00-una.jsonl"
    let archivedLive = c41Archived(home, archivedName)
    c41Write([c41Event(input: 10, output: 0, at: c41July5), c41Event(input: 1_010, output: 0, at: c41July5)]
        .joined(separator: "\n") + "\n", to: archivedLive)
    let r4 = c41Scan(r3.cache, home: home)
    #expect(r4.usage.codexTotal == 5_200)
    try? FileManager.default.removeItem(at: archivedLive)
    c41Write("zstd-frame-bytes", to: c41Sessions(home, "2026/07/06/\(archivedName).zst"))
    let r5 = c41Scan(r4.cache, home: home)
    #expect(r5.usage.codexTotal == 5_200, "압축된 채 보관 해제된 파일의 기여가 사라졌다: \(r5.usage.codexTotal)")

    // 동명 `.jsonl` 이 다른 루트에 있는 경우는 동결이 **아니다** — 새 키로 파싱되므로 옛 상태를 지워야 이중 계상이 없다
    // (scannerKeepsMonthTotalWhenRolloutIsArchivedByRename 이 값으로 증명). 여기서는 후보 산식만 고정한다.
    let roots = TokenUsageIncrementalScanner.codexRoots(homeDirectory: home, codexHome: nil)
    let twins = TokenUsageIncrementalScanner.compressedTwinCandidates(for: live.path, roots: roots)
    #expect(twins == [live.path + ".zst", c41Archived(home, name + ".zst").path])
    let fromArchived = TokenUsageIncrementalScanner.compressedTwinCandidates(for: archivedLive.path, roots: roots)
    #expect(fromArchived == [archivedLive.path + ".zst", c41Sessions(home, "2026/07/06/\(archivedName).zst").path])
    // 날짜가 없는 이름은 같은 경로 후보뿐(archived 후보는 자기 자신과 같아 접힌다).
    #expect(TokenUsageIncrementalScanner.compressedTwinCandidates(for: c41Archived(home, "rollout-x.jsonl").path, roots: roots)
            == [c41Archived(home, "rollout-x.jsonl").path + ".zst"])
    #expect(TokenUsageIncrementalScanner.compressedTwinCandidates(for: "/tmp/other.jsonl", roots: roots) == ["/tmp/other.jsonl.zst"])
}

/// 열거와 처리 사이에 보관(rename)된 파일(리뷰 P2): 두 루트를 차례로 열거하므로 그 사이 옮겨진 파일은 **양쪽 목록에 다 든다** —
/// 옛 경로 항목은 낡았다. 옛 경로를 '본 것'으로 치면 옛 상태가 남아 새 경로 상태와 함께 **정확히 두 배**가 되고 배경 경로에선
/// 그 값이 곧바로 업로드된다. 낡은 항목의 모양은 둘이다:
///   ① 열거 stat 이 옛 상태와 같다(보관은 mtime 을 보존하는 rename 이라 이것이 실제 모양) → 무변경 스킵 분기 — 파일을 열지 않으므로
///      '읽기 실패'가 없다. 같은 이름이 두 루트에 있을 때만 존재를 확인해 없으면 seen 으로 치지 않는다.
///   ② 열거 stat 이 옛 상태와 다르다(옮기기 직전에 자랐다) → 읽기 실패(`continue`) — 읽기 성공 뒤에만 seen 에 넣는다.
/// 어느 쪽이든 정리 규칙(존재 → .zst 쌍둥이)이 그 순회에서 옛 상태를 지운다. 손으로 만든 목록으로 그 창을 재현한다.
/// 뮤테이션: ① 무변경 분기의 이름 충돌 존재 확인을 빼거나 ② seenPaths.insert 를 읽기 전으로 되돌리면 각각 빨강.
@Test
func scannerDropsStaleStateWhenListedPathBecameUnreadable() throws {
    let home = c41TempHome("stale-listing")
    defer { try? FileManager.default.removeItem(at: home) }
    let roots = TokenUsageIncrementalScanner.codexRoots(homeDirectory: home, codexHome: nil)
    // 보관 디렉터리는 codex 가 만들어 두는 것 — 없으면 rename 이 실패해 픽스처가 성립하지 않으므로 먼저 만든다.
    try FileManager.default.createDirectory(at: roots[1], withIntermediateDirectories: true)

    // ① 무변경 stat 의 낡은 항목(실제 보관 모양).
    let name = "rollout-2026-07-05T00-00-00-race.jsonl"
    let live = c41Sessions(home, "2026/07/05/\(name)")
    let body = [c41Event(input: 100, output: 0, at: c41July5), c41Event(input: 2_100, output: 400, at: c41July5)]
        .joined(separator: "\n") + "\n"
    c41Write(body, to: live)
    let r1 = c41Scan(home: home)
    #expect(r1.usage.codexTotal == 2_400)
    let stale = try #require(r1.cache.codexFileStates.first?.key)   // 열거자가 준 정규 경로(/private/var/…)
    let prior = try #require(r1.cache.codexFileStates[stale])
    let archived = c41Archived(home, name)
    try FileManager.default.moveItem(at: live, to: archived)
    #expect(!FileManager.default.fileExists(atPath: stale))
    // 열거자는 정규 경로(/private/var/…)를 주므로 손으로 만든 목록도 같은 모양으로(안 그러면 키가 갈려 픽스처 자체가 이중 계상).
    let unchangedListing: [(url: URL, size: Int, mtimeMicros: Int)] = [
        (URL(fileURLWithPath: stale), prior.size, prior.mtimeMicros),   // rename 직전의 stat = 옛 상태와 동일
        (c41Canonical(archived), prior.size, prior.mtimeMicros)
    ]
    var cache = r1.cache
    var stats = TokenUsageIncrementalScanner.Stats()
    TokenUsageIncrementalScanner.scanCodexFiles(&cache, files: unchangedListing, roots: roots, monthString: "2026-07", stats: &stats)
    #expect(cache.codexFileStates[stale] == nil, "무변경으로 보인 옛 경로 상태가 남았다(이중 계상)")
    #expect(cache.codexFileStates.count == 1)
    #expect(cache.codexFileStates.values.reduce(0) { $0 + $1.monthContribTotal } == 2_400, "월 합이 두 배가 됐다")
    #expect(stats.codexFilesRead == 1)
    #expect(stats.statesChanged == true)

    // ② 자란 stat 의 낡은 항목(읽기 실패 경로): 다른 파일로 같은 창을 만든다. 옮기기 직전에 한 줄이 붙어 열거 stat 이 옛 상태보다 크다.
    let name2 = "rollout-2026-07-06T00-00-00-grow.jsonl"
    let live2 = c41Sessions(home, "2026/07/06/\(name2)")
    c41Write([c41Event(input: 10, output: 0, at: c41July5), c41Event(input: 510, output: 0, at: c41July5)]
        .joined(separator: "\n") + "\n", to: live2)
    let r2 = c41Scan(cache, home: home)
    #expect(r2.usage.codexTotal == 2_900)
    let stale2 = try #require(r2.cache.codexFileStates.keys.first { $0.hasSuffix(name2) })
    let prior2 = try #require(r2.cache.codexFileStates[stale2])
    c41Append(c41Event(input: 810, output: 0, at: c41July5) + "\n", to: live2, modified: c41Now.addingTimeInterval(5))
    let grownAttrs = try FileManager.default.attributesOfItem(atPath: live2.path)
    let grownSize = try #require(grownAttrs[.size] as? Int)
    let grownMtime = Int((try #require(grownAttrs[.modificationDate] as? Date)).timeIntervalSince1970 * 1_000_000)
    #expect(grownSize > prior2.size)
    let archived2 = c41Archived(home, name2)
    try FileManager.default.moveItem(at: live2, to: archived2)
    let grownListing: [(url: URL, size: Int, mtimeMicros: Int)] = [
        (URL(fileURLWithPath: stale2), grownSize, grownMtime),   // 이어읽기 대상으로 보이지만 열 수 없다
        (c41Canonical(archived2), grownSize, grownMtime)
    ]
    var cache2 = r2.cache
    var stats2 = TokenUsageIncrementalScanner.Stats()
    TokenUsageIncrementalScanner.scanCodexFiles(&cache2, files: grownListing, roots: roots, monthString: "2026-07", stats: &stats2)
    #expect(cache2.codexFileStates[stale2] == nil, "읽기 실패한 옛 경로 상태가 남았다(이중 계상)")
    #expect(cache2.codexFileStates.count == 2)
    #expect(cache2.codexFileStates.values.reduce(0) { $0 + $1.monthContribTotal } == 2_400 + 800, "월 합이 두 배가 됐다")
    #expect(stats2.codexFilesRead == 1)

    // 읽기 실패가 **존재하는** 파일에서 났다면(권한 등) 상태는 지우지 않는다 — 정리 규칙의 존재 확인이 지킨다.
    let name3 = "rollout-2026-07-07T00-00-00-perm.jsonl"
    let live3 = c41Sessions(home, "2026/07/07/\(name3)")
    c41Write([c41Event(input: 1, output: 0, at: c41July5), c41Event(input: 101, output: 0, at: c41July5)]
        .joined(separator: "\n") + "\n", to: live3)
    let r3 = c41Scan(cache2, home: home)
    #expect(r3.usage.codexTotal == 3_300)
    let key3 = try #require(r3.cache.codexFileStates.keys.first { $0.hasSuffix(name3) })
    try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: live3.path)
    defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: live3.path) }
    var cache3 = r3.cache
    var stats3 = TokenUsageIncrementalScanner.Stats()
    TokenUsageIncrementalScanner.scanCodexFiles(
        &cache3, files: [(URL(fileURLWithPath: key3), r3.cache.codexFileStates[key3]!.size + 1, prior.mtimeMicros + 1)],
        roots: roots, monthString: "2026-07", stats: &stats3)
    #expect(cache3.codexFileStates[key3] != nil, "존재하는 파일의 읽기 실패로 상태가 지워졌다")
    #expect(stats3.codexFilesRead == 0)
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
func probeFallbackCandidatesStartWithHomebrewThenUserPrefixes() throws {
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
    // IDE 번들 네이티브 바이너리는 node 심(npm-global 이하) **앞**이다(리뷰 P1: node 없는 맥에서 시도 상한 안에 닿게).
    let ide = try #require(paths.firstIndex { $0.hasSuffix(".cursor/extensions/openai.chatgpt-1.2.3/bin/macos-arm64/codex") })
    let npm = try #require(paths.firstIndex(of: home.appendingPathComponent(".npm-global/bin/codex").path))
    #expect(ide == 2 && ide < npm, "IDE 번들이 node 심 뒤에 있다: \(paths)")
    #expect(paths.count == 2 + 1 + 4 + 2)
    #expect(CodexAccountUsageProbe.shellLookupTimeout == 5)
    #expect(CodexAccountUsageProbe.fetchDeadline == 15)
    #expect(CodexAccountUsageProbe.killGrace == 2)
}

/// 후보 툴체인의 PATH(리뷰 P1): 실행 파일 디렉터리가 맨 앞 → 로그인 셸 PATH → node 탐색 디렉터리(bun·nvm 포함). 셸이 찾은
/// codex 가 첫 후보, 실행 가능한 폴백만 뒤따르고 같은 경로는 한 번, CODEX_HOME 은 셸 값이 실린다.
/// 옛 구현은 폴백 PATH 에 homebrew·/usr/local·volta 만 덧붙여 nvm 의 npm 셸 스크립트가 node 를 못 찾았다(exit 127).
/// 뮤테이션: environment(for:) 에서 실행 파일 디렉터리를 빼거나 nodeSearchDirectories 에서 nvm/bun 을 빼면 빨강.
@Test
func probeCandidateToolchainsPutExecutableDirectoryFirstInPATH() throws {
    let home = c41TempHome("toolchains")
    defer { try? FileManager.default.removeItem(at: home) }
    let nvmBin = home.appendingPathComponent(".nvm/versions/node/v22.3.0/bin", isDirectory: true)
    c41Write("#!/usr/bin/env node\n", to: nvmBin.appendingPathComponent("codex"))
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: nvmBin.appendingPathComponent("codex").path)
    c41Write("#!/usr/bin/env node\n", to: home.appendingPathComponent(".npm-global/bin/codex"))   // 실행 비트 없음 → 제외
    let base = ["PATH": "/usr/bin:/bin", "HOME": home.path]

    // 셸이 못 찾은 경우(nvm 초기화가 .zshrc 에 있고 -lc 만 돈 모양): 폴백 nvm 후보 하나.
    let shellNoCodex = CodexAccountUsageProbe.ShellEnvironment(path: "/opt/homebrew/bin:/usr/bin:/bin", codexHome: "", codex: "")
    let fallbackOnly = CodexAccountUsageProbe.candidateToolchains(homeDirectory: home, shell: shellNoCodex, base: base)
        .filter { $0.executable.path.hasPrefix(home.standardizedFileURL.path) || $0.executable.path.hasPrefix(home.path) }
    let nvm = try #require(fallbackOnly.first)
    #expect(nvm.executable.path.hasSuffix(".nvm/versions/node/v22.3.0/bin/codex"))
    let path = try #require(nvm.environment["PATH"]).split(separator: ":").map(String.init)
    #expect(path.first?.hasSuffix(".nvm/versions/node/v22.3.0/bin") == true, "실행 파일 디렉터리가 PATH 맨 앞이 아니다: \(path)")
    #expect(path.contains("/opt/homebrew/bin") && path.contains("/usr/bin"))            // 셸 PATH 승계
    #expect(path.contains(home.appendingPathComponent(".bun/bin").path))                 // node 탐색 디렉터리(bun)
    #expect(path.filter { $0.hasSuffix(".nvm/versions/node/v22.3.0/bin") }.count == 1)   // 중복 없음
    #expect(nvm.environment["CODEX_HOME"] == nil)                                        // 빈 CODEX_HOME 은 싣지 않는다
    #expect(nvm.environment["HOME"] == home.path)                                        // 나머지 env 승계

    // 셸이 찾은 codex 는 첫 후보이고, 폴백과 같은 경로면 한 번만 든다. CODEX_HOME 은 셸 값.
    let shellFound = CodexAccountUsageProbe.ShellEnvironment(
        path: nvmBin.path + ":/usr/bin:/bin", codexHome: home.appendingPathComponent("cx").path,
        codex: nvmBin.appendingPathComponent("codex").path)
    let all = CodexAccountUsageProbe.candidateToolchains(homeDirectory: home, shell: shellFound, base: base)
    #expect(all.first?.executable.path.hasSuffix("v22.3.0/bin/codex") == true)
    #expect(all.filter { $0.executable.path.hasSuffix("v22.3.0/bin/codex") }.count == 1)
    #expect(all.first?.environment["CODEX_HOME"] == home.appendingPathComponent("cx").path)
    #expect(all.first?.environment["PATH"]?.hasPrefix(nvmBin.standardizedFileURL.path) == true)
    // 셸 PATH 가 없으면(조회 실패) GUI PATH 를 잇는다.
    let noShell = CodexAccountUsageProbe.environment(for: nvmBin.appendingPathComponent("codex"), homeDirectory: home, shell: nil, base: base)
    #expect(noShell["PATH"]?.contains("/usr/bin:/bin") == true)
    #expect(CodexAccountUsageProbe.nodeSearchDirectories(homeDirectory: home).contains(nvmBin.path))
    #expect(CodexAccountUsageProbe.maxCandidateAttempts == 4)
}

/// 셸 조회 파서: 마지막 표지 뒤의 NUL 세 토막만 읽는다(dotfile 이 stdout 에 찍은 배너는 무시). 스크립트는 `-lc`/`-ic` 공용이고
/// 표지·PATH·CODEX_HOME·`command -v codex` 를 그 순서로 찍는다.
@Test
func probeShellLookupParserReadsOnlyAfterTheLastMarker() throws {
    let marker = CodexAccountUsageProbe.shellLookupMarker
    let noisy = "Welcome banner\n" + marker + "\0/first:/bin\0\0\0" + "\n" + marker + "\0/opt/homebrew/bin:/usr/bin\0/Users/x/cx\0/opt/homebrew/bin/codex\0"
    let env = try #require(CodexAccountUsageProbe.parseShellLookup(Data(noisy.utf8)))
    #expect(env.path == "/opt/homebrew/bin:/usr/bin")
    #expect(env.codexHome == "/Users/x/cx")
    #expect(env.codex == "/opt/homebrew/bin/codex")
    #expect(CodexAccountUsageProbe.parseShellLookup(Data("no marker here\0a\0b\0c\0".utf8)) == nil)
    #expect(CodexAccountUsageProbe.parseShellLookup(Data((marker + "\0/only-path").utf8)) == nil)   // 토막 부족
    let script = CodexAccountUsageProbe.shellLookupScript
    #expect(script.contains(marker) && script.contains("\"$PATH\"") && script.contains("${CODEX_HOME-}")
            && script.contains("command -v codex"))
}

/// 툴체인 확정 규칙: 성공 또는 인증 오류만 확정(바이너리·메서드가 산 증거). 그 밖은 다음 후보의 이유다.
@Test
func probeConfirmsToolchainOnlyOnSuccessOrAuthError() {
    #expect(CodexAccountUsageProbe.confirmsToolchain(.success(c41Usage())))
    #expect(CodexAccountUsageProbe.confirmsToolchain(.failure(.init(status: .notLoggedIn, reason: "auth"))))
    for status in [CodexAccountProbeStatus.failed, .timeout, .codexNotInstalled] {
        #expect(!CodexAccountUsageProbe.confirmsToolchain(.failure(.init(status: status, reason: "x"))), "\(status)")
    }
}

/// 실행 파일(내용은 아무거나, 실행 비트만)을 심는다 — 가짜 러너가 경로만 보고 답하므로 실제로 실행되지 않는다.
private func c41PlantExecutable(_ url: URL) {
    c41Write("#!/bin/sh\nexit 127\n", to: url)
    try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
}

/// 경로별 canned 결과를 돌려주고 시도 순서를 기록하는 가짜 세션 러너(프로세스 0). 등록되지 않은 경로(이 맥의 실제 후보가 섞여
/// 들어와도)는 '응답 없이 종료'다.
private final class C41SessionRunner: @unchecked Sendable {
    typealias Outcome = (result: Result<CodexAccountUsage, CodexAccountUsageProbe.Failure>, kind: CodexAccountUsageProbe.SessionKind)
    private let lock = NSLock()
    private var _attempts: [String] = []
    private var _outcomes: [String: Outcome] = [:]
    var attempts: [String] { lock.withLock { _attempts } }
    func set(_ suffix: String, _ outcome: Outcome) { lock.withLock { _outcomes[suffix] = outcome } }
    func reset() { lock.withLock { _attempts = [] } }
    func run(_ toolchain: CodexAccountUsageProbe.Toolchain) async -> Outcome {
        let path = toolchain.executable.path
        return lock.withLock {
            _attempts.append(path)
            if let hit = _outcomes.first(where: { path.hasSuffix($0.key) }) { return hit.value }
            return (.failure(.init(status: .failed, reason: "응답 없이 종료")), .exited)
        }
    }
}

/// 셸 조회 호출을 세고 고정값을 돌려주는 가짜(프로세스 0).
private final class C41ShellLookup: @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [Bool] = []
    var calls: [Bool] { lock.withLock { _calls } }
    var login: CodexAccountUsageProbe.ShellEnvironment?
    var interactive: CodexAccountUsageProbe.ShellEnvironment?
    init(login: CodexAccountUsageProbe.ShellEnvironment?, interactive: CodexAccountUsageProbe.ShellEnvironment? = nil) {
        self.login = login
        self.interactive = interactive
    }
    func lookup(_ isInteractive: Bool) async -> CodexAccountUsageProbe.ShellEnvironment? {
        lock.withLock { _calls.append(isInteractive); return isInteractive ? interactive : login }
    }
}

/// 리뷰 P1 재현 — 툴체인은 **실행으로** 확정한다. 셸이 찾은 npm 셸 스크립트(`#!/usr/bin/env node`)가 node 를 못 찾아 exit 127
/// (응답 없이 종료)로 끝나면 다음 후보(IDE 번들 네이티브 바이너리)를 띄워 그것으로 확정하고, 확정된 것이 나중에 돌지 못하게 되면
/// (node 삭제 = 기동 실패) 캐시를 버리고 재탐색한다. 옛 구현은 존재만으로 첫 후보를 프로세스 수명 동안 캐시해 30분마다 같은
/// 실패를 반복했고 다른 후보는 영영 시도되지 않았다.
/// 뮤테이션: 확정 조건을 '존재'로 되돌리거나(첫 후보 캐시), exited 에서 캐시를 안 비우거나, 타임아웃에서 다음 후보로 넘어가면 빨강.
@Test
func probeFetchConfirmsToolchainByExecutionAndEvictsOneThatStoppedRunning() async throws {
    let home = c41TempHome("fetch-confirm")
    defer { try? FileManager.default.removeItem(at: home) }
    let npm = home.appendingPathComponent(".npm-global/bin/codex")
    let ide = home.appendingPathComponent(".cursor/extensions/openai.chatgpt-1.2.3/bin/macos-arm64/codex")
    c41PlantExecutable(npm)
    c41PlantExecutable(ide)
    let shell = C41ShellLookup(login: .init(path: "/opt/homebrew/bin:/usr/bin:/bin", codexHome: "", codex: npm.path))
    let runner = C41SessionRunner()
    runner.set(".npm-global/bin/codex", (.failure(.init(status: .failed, reason: "exit 127")), .exited))
    runner.set("macos-arm64/codex", (.success(c41Usage()), .responded))
    let cache = CodexAccountUsageProbe.LocateCache()
    let t0 = c41FetchedAt
    func fetch(at now: Date) async -> Result<CodexAccountUsage, CodexAccountUsageProbe.Failure> {
        await CodexAccountUsageProbe.fetch(homeDirectory: home, appVersion: "t", now: now, cache: cache, lookup: shell.lookup, run: runner.run)
    }

    // 1) 첫 프로브: 셸이 찾은 npm 후보 실패 → IDE 후보 성공 → IDE 로 확정.
    let first = await fetch(at: t0)
    #expect((try? first.get())?.monthTotal("2026-09") == 60_000)
    let mine = { runner.attempts.filter { $0.hasPrefix(home.path) || $0.hasPrefix(home.standardizedFileURL.path) } }
    #expect(mine().map { ($0 as NSString).lastPathComponent == "codex" } == [true, true])
    #expect(mine().first?.hasSuffix(".npm-global/bin/codex") == true, "셸이 찾은 codex 가 첫 후보여야 한다: \(runner.attempts)")
    #expect(mine().last?.hasSuffix("macos-arm64/codex") == true, "실패한 첫 후보 뒤에 다음 후보를 띄우지 않았다(리뷰 P1): \(runner.attempts)")
    #expect(cache.confirmedToolchain?.executable.path.hasSuffix("macos-arm64/codex") == true, "실행으로 확인된 후보가 캐시돼야 한다")
    #expect(cache.failure == nil)
    // 로그인 셸이 codex 는 찾았지만 CODEX_HOME 이 비어 있어 대화형 조회가 한 번 더 돈다(리뷰 2차 P2; nil 이라 로그인 결과 유지).
    #expect(shell.calls == [false, true])

    // 2) 두 번째 프로브: 확정된 IDE 후보만 돈다(npm 은 다시 띄우지 않는다). 셸 조회도 캐시(프로세스 수명당 대화형 1회).
    runner.reset()
    _ = await fetch(at: t0.addingTimeInterval(1_800))
    #expect(mine().count == 1 && mine().first?.hasSuffix("macos-arm64/codex") == true, "확정된 툴체인 하나만 띄워야 한다: \(runner.attempts)")
    #expect(shell.calls == [false, true])

    // 3) 확정된 것이 돌지 못하게 됨(기동 실패): 캐시를 버리고 그것을 뺀 나머지를 재탐색 → npm 도 실패 → 전부 실패를 TTL 동안 캐시.
    runner.set("macos-arm64/codex", (.failure(.init(status: .failed, reason: "launch")), .launchFailed))
    runner.reset()
    let t3 = t0.addingTimeInterval(3_600)
    let third = await fetch(at: t3)
    #expect((try? third.get()) == nil)
    #expect(mine().first?.hasSuffix("macos-arm64/codex") == true && mine().dropFirst().first?.hasSuffix(".npm-global/bin/codex") == true,
            "확정 툴체인 실패 뒤 재탐색이 없다: \(runner.attempts)")
    #expect(!mine().dropFirst().contains { $0.hasSuffix("macos-arm64/codex") }, "기동 실패한 후보를 재탐색에서 다시 띄웠다")
    #expect(cache.confirmedToolchain == nil)
    #expect(cache.failure?.status == .failed && cache.failure?.at == t3)

    // 4) TTL 안의 프로브는 프로세스를 하나도 띄우지 않고 캐시된 실패를 돌려준다. TTL 이 지나면 재탐색.
    runner.reset()
    let cachedFailure = await fetch(at: t3.addingTimeInterval(CodexAccountUsageProbe.locateFailureTTL - 1))
    if case .failure(let f) = cachedFailure { #expect(f.status == .failed) } else { Issue.record("캐시된 실패여야 한다") }
    #expect(runner.attempts.isEmpty, "탐색 실패 캐시 안에서 프로세스가 떴다: \(runner.attempts)")
    _ = await fetch(at: t3.addingTimeInterval(CodexAccountUsageProbe.locateFailureTTL))
    #expect(!mine().isEmpty)

    // 5) 인증 오류 응답도 확정이다(바이너리·메서드가 산 증거) — 다음 후보를 띄우지 않는다.
    let authCache = CodexAccountUsageProbe.LocateCache()
    runner.set(".npm-global/bin/codex", (.failure(.init(status: .notLoggedIn, reason: "chatgpt authentication required")), .responded))
    runner.reset()
    let auth = await CodexAccountUsageProbe.fetch(homeDirectory: home, appVersion: "t", now: t0, cache: authCache, lookup: shell.lookup, run: runner.run)
    if case .failure(let f) = auth { #expect(f.status == .notLoggedIn) } else { Issue.record("인증 오류가 그대로 돌아와야 한다") }
    #expect(mine().count == 1)
    #expect(authCache.confirmedToolchain?.executable.path.hasSuffix(".npm-global/bin/codex") == true)

    // 6) 타임아웃은 환경 문제 — 거기서 멈추고(다음 후보 없음) 아무것도 캐시하지 않는다(다음 프로브가 재탐색).
    let timeoutCache = CodexAccountUsageProbe.LocateCache()
    runner.set(".npm-global/bin/codex", (.failure(.init(status: .timeout, reason: "15초")), .timeout))
    runner.reset()
    let timedOut = await CodexAccountUsageProbe.fetch(homeDirectory: home, appVersion: "t", now: t0, cache: timeoutCache, lookup: shell.lookup, run: runner.run)
    if case .failure(let f) = timedOut { #expect(f.status == .timeout) } else { Issue.record("타임아웃이 그대로 돌아와야 한다") }
    #expect(mine().count == 1, "타임아웃 뒤 다음 후보를 띄웠다: \(runner.attempts)")
    #expect(timeoutCache.confirmedToolchain == nil && timeoutCache.failure == nil)

    // 7) 후보가 하나도 없으면 프로세스 없이 `.codexNotInstalled` 를 TTL 동안 캐시한다.
    let empty = c41TempHome("fetch-empty")
    defer { try? FileManager.default.removeItem(at: empty) }
    let emptyCache = CodexAccountUsageProbe.LocateCache()
    let none = C41ShellLookup(login: .init(path: "/usr/bin:/bin", codexHome: "", codex: ""), interactive: nil)
    runner.reset()
    let real = CodexAccountUsageProbe.candidateToolchains(homeDirectory: empty, shell: nil).count   // 이 맥의 /opt/homebrew 등
    let notInstalled = await CodexAccountUsageProbe.fetch(homeDirectory: empty, appVersion: "t", now: t0, cache: emptyCache, lookup: none.lookup, run: runner.run)
    if real == 0 {
        if case .failure(let f) = notInstalled { #expect(f.status == .codexNotInstalled) } else { Issue.record("미설치여야 한다") }
        #expect(runner.attempts.isEmpty)
        #expect(emptyCache.failure?.status == .codexNotInstalled)
        #expect(none.calls == [false, true])   // codex 를 못 찾으면 대화형 셸로 한 번 더
    }

    // 8) 시도 상한: 실행 가능한 후보가 5개여도 한 프로브에 maxCandidateAttempts(4)개까지만 띄운다.
    let many = c41TempHome("fetch-many")
    defer { try? FileManager.default.removeItem(at: many) }
    for rel in [".npm-global/bin/codex", ".volta/bin/codex", ".bun/bin/codex", ".local/bin/codex", ".nvm/versions/node/v20.1.0/bin/codex"] {
        c41PlantExecutable(many.appendingPathComponent(rel))
    }
    let manyCache = CodexAccountUsageProbe.LocateCache()
    let manyRunner = C41SessionRunner()   // 전부 '응답 없이 종료'
    let candidates = CodexAccountUsageProbe.candidateToolchains(homeDirectory: many, shell: nil).count
    #expect(candidates >= 5)
    _ = await CodexAccountUsageProbe.fetch(homeDirectory: many, appVersion: "t", now: t0, cache: manyCache, lookup: none.lookup, run: manyRunner.run)
    #expect(manyRunner.attempts.count == CodexAccountUsageProbe.maxCandidateAttempts, "시도 상한을 넘겼다: \(manyRunner.attempts.count)")
    #expect(manyCache.failure?.status == .failed)
}

/// 셸 조회 규칙: `-lc` 가 codex 를 못 찾으면 `-ic`(.zshrc 의 nvm 초기화) 로 한 번 더 묻고, 찾은 쪽의 PATH·CODEX_HOME 을 쓴다.
/// 성공은 프로세스 수명 캐시(두 번째 호출에 셸 0), 실패(둘 다 nil)는 TTL 동안 캐시. `resolveCodexHome` 은 빈 CODEX_HOME 을 nil 로.
/// 뮤테이션: 대화형 재조회를 빼거나, 실패 캐시 TTL 비교를 뒤집으면 빨강.
@Test
func probeShellEnvironmentRetriesInteractivelyAndCachesOutcome() async {
    let t0 = c41FetchedAt
    // -lc 는 codex 없음(PATH 만), -ic 가 nvm PATH 와 codex 를 찾는다.
    let shell = C41ShellLookup(
        login: .init(path: "/usr/bin:/bin", codexHome: "", codex: ""),
        interactive: .init(path: "/Users/x/.nvm/versions/node/v22/bin:/usr/bin:/bin", codexHome: "/Users/x/cx", codex: "/Users/x/.nvm/versions/node/v22/bin/codex"))
    let cache = CodexAccountUsageProbe.LocateCache()
    let env = await CodexAccountUsageProbe.resolveShellEnvironment(now: t0, cache: cache, lookup: shell.lookup)
    #expect(shell.calls == [false, true])
    #expect(env?.codex == "/Users/x/.nvm/versions/node/v22/bin/codex")
    #expect(env?.path == "/Users/x/.nvm/versions/node/v22/bin:/usr/bin:/bin")
    #expect(env?.codexHome == "/Users/x/cx")
    #expect(CodexAccountUsageProbe.cachedCodexHome(cache: cache)?.path == "/Users/x/cx")
    // 캐시: 두 번째 호출은 셸을 띄우지 않는다.
    _ = await CodexAccountUsageProbe.resolveShellEnvironment(now: t0.addingTimeInterval(86_400), cache: cache, lookup: shell.lookup)
    #expect(shell.calls == [false, true])

    // -ic 도 못 찾으면 codex 는 비고 PATH 는 더 넓은 쪽(대화형)을 쓴다.
    let widest = C41ShellLookup(login: .init(path: "/usr/bin:/bin", codexHome: "", codex: ""),
                                interactive: .init(path: "/opt/homebrew/bin:/usr/bin:/bin", codexHome: "", codex: ""))
    let c2 = CodexAccountUsageProbe.LocateCache()
    let e2 = await CodexAccountUsageProbe.resolveShellEnvironment(now: t0, cache: c2, lookup: widest.lookup)
    #expect(e2?.codex == "" && e2?.path == "/opt/homebrew/bin:/usr/bin:/bin")
    #expect(await CodexAccountUsageProbe.resolveCodexHome(now: t0, cache: c2, lookup: widest.lookup) == nil)   // 빈 CODEX_HOME → nil

    // 둘 다 실패(타임아웃·기동 실패 = nil): TTL 동안 캐시, 지나면 재조회.
    let failing = C41ShellLookup(login: nil, interactive: nil)
    let c3 = CodexAccountUsageProbe.LocateCache()
    #expect(await CodexAccountUsageProbe.resolveShellEnvironment(now: t0, cache: c3, lookup: failing.lookup) == nil)
    #expect(failing.calls == [false, true])
    _ = await CodexAccountUsageProbe.resolveShellEnvironment(now: t0.addingTimeInterval(CodexAccountUsageProbe.locateFailureTTL - 1), cache: c3, lookup: failing.lookup)
    #expect(failing.calls.count == 2, "실패 캐시 안에서 셸을 다시 띄웠다")
    _ = await CodexAccountUsageProbe.resolveShellEnvironment(now: t0.addingTimeInterval(CodexAccountUsageProbe.locateFailureTTL), cache: c3, lookup: failing.lookup)
    #expect(failing.calls.count == 4)
    #expect(CodexAccountUsageProbe.cachedCodexHome(cache: c3) == nil)
}

/// 리뷰 2차 P2 — 대화형 재조회 조건은 "codex 를 못 찾았거나 **CODEX_HOME 이 비어 있을 때**" 다. `.zshrc` 에만
/// `export CODEX_HOME=…` 을 둔 사용자는 `-lc` 가 codex(npm)를 찾아 버리면 옛 규칙에선 대화형 조회가 안 돌아 CODEX_HOME 이 영영
/// 빈 채 캐시됐고, 계정 스토어는 `~/.codex/auth.json` 만 봐서 '미로그인'이었다. 병합은 필드별 '비어 있지 않은 쪽' —
/// 대화형이 codex 를 못 돌려줘도 로그인 셸이 찾은 codex 는 남는다. 비용은 프로세스 수명당 대화형 1회(캐시).
/// 뮤테이션: 재조회 조건을 codex 부재로 되돌리면 calls == [false] 이고 cachedCodexHome == nil 이라 빨강; 병합을
/// `codex: interactive.codex` 로 되돌리면 codex 가 지워져 빨강.
@MainActor
@Test
func probeShellLookupRetriesInteractivelyWhenCodexHomeIsEmptyAndMergesNonEmptyFields() async {
    let home = c41TempHome("codex-home-interactive")
    defer { try? FileManager.default.removeItem(at: home) }
    let custom = home.appendingPathComponent("x", isDirectory: true)
    // auth.json 은 `$CODEX_HOME/auth.json` 에만 있다(`~/.codex/auth.json` 없음).
    c41Write("{\"tokens\":\"secret\"}", to: custom.appendingPathComponent("auth.json"))
    let npm = home.appendingPathComponent(".npm-global/bin/codex").path
    let shell = C41ShellLookup(
        login: .init(path: "/usr/bin:/bin", codexHome: "", codex: npm),
        interactive: .init(path: "", codexHome: custom.path, codex: ""))
    let cache = CodexAccountUsageProbe.LocateCache()
    let t0 = c41FetchedAt
    let env = await CodexAccountUsageProbe.resolveShellEnvironment(now: t0, cache: cache, lookup: shell.lookup)
    #expect(shell.calls == [false, true], "codex 는 찾았지만 CODEX_HOME 이 비었으면 대화형으로 한 번 더 물어야 한다")
    #expect(env?.codexHome == custom.path)
    #expect(env?.codex == npm, "대화형이 codex 를 못 찾았다고 로그인 셸이 찾은 codex 를 지웠다")
    #expect(env?.path == "/usr/bin:/bin", "대화형 PATH 가 비었으면 로그인 셸 PATH 를 유지해야 한다")
    #expect(CodexAccountUsageProbe.cachedCodexHome(cache: cache)?.path == custom.path)
    #expect(CodexAccountUsageProbe.needsInteractiveLookup(.init(path: "/usr/bin", codexHome: "/x", codex: "/x/codex")) == false)
    #expect(CodexAccountUsageProbe.needsInteractiveLookup(nil))

    // 그 캐시로 만든 계정 스토어: `$CODEX_HOME/auth.json` 을 찾아 러너가 정확히 1회 돈다(옛 규칙이면 미로그인 → 0).
    let runner = C41Runner(.success(c41Usage()))
    let store = CodexAccountUsageStore(
        defaults: c41Defaults(), homeDirectory: home,
        codexHome: { await CodexAccountUsageProbe.resolveCodexHome(now: t0, cache: cache, lookup: shell.lookup) },
        runner: runner.run)
    await store.refreshIfDue(now: t0)
    #expect(store.runnerCallCount == 1, "CODEX_HOME 아래 auth.json 을 두고도 미로그인으로 끝났다")
    #expect(store.lastStatus == .ok)
    #expect(shell.calls == [false, true], "캐시된 셸 환경을 두고 셸을 다시 띄웠다(프로세스 수명당 1회여야 한다)")

    // 둘 다 채워져 있으면 대화형 조회는 없다(비용 0).
    let full = C41ShellLookup(login: .init(path: "/usr/bin:/bin", codexHome: "/Users/x/cx", codex: "/usr/local/bin/codex"), interactive: nil)
    let c2 = CodexAccountUsageProbe.LocateCache()
    _ = await CodexAccountUsageProbe.resolveShellEnvironment(now: t0, cache: c2, lookup: full.lookup)
    #expect(full.calls == [false])
    // 병합 규칙(순수): 둘 다 비어 있지 않으면 대화형(실제 사용 환경)이 이긴다.
    let both = CodexAccountUsageProbe.merged(
        login: .init(path: "/a", codexHome: "/h1", codex: "/a/codex"),
        interactive: .init(path: "/b", codexHome: "/h2", codex: "/b/codex"))
    #expect(both == .init(path: "/b", codexHome: "/h2", codex: "/b/codex"))
}

/// 리뷰 2차 P2 — 확정 툴체인이 exited/launchFailed 로 폐기된 뒤 남은 후보가 0 이면 `.codexNotInstalled` 가 아니라 `.failed` 다:
/// 바이너리는 설치돼 있고 돌지 못하는 것(node 삭제 등)이라, '미설치'로 올리면 서버 진단이 오진한다. 캐시 상태도 `.failed`.
/// 뮤테이션: 후보 0 분기의 status 를 `.codexNotInstalled` 고정으로 되돌리면 빨강.
@Test
func probeFetchReportsFailedNotNotInstalledWhenEvictedToolchainWasTheOnlyCandidate() async {
    let home = c41TempHome("fetch-evict-only")
    defer { try? FileManager.default.removeItem(at: home) }
    let ide = home.appendingPathComponent(".cursor/extensions/openai.chatgpt-2.0.0/bin/macos-arm64/codex")
    c41PlantExecutable(ide)
    // 로그인 셸은 codex 를 모른다(CODEX_HOME 도 비어 대화형이 한 번 더 돌지만 nil) → 후보는 IDE 번들 하나뿐.
    let none = C41ShellLookup(login: .init(path: "/usr/bin:/bin", codexHome: "", codex: ""), interactive: nil)
    let runner = C41SessionRunner()
    runner.set("macos-arm64/codex", (.success(c41Usage()), .responded))
    let cache = CodexAccountUsageProbe.LocateCache()
    let t0 = c41FetchedAt
    // 이 맥의 실제 폴백(/opt/homebrew 등)이 섞이면 '후보 0' 이 아니라 '전부 실패' 경로다 — 상태는 같지만 시도 수 단언은 그때만.
    let onlyIDE = CodexAccountUsageProbe.candidateToolchains(homeDirectory: home, shell: nil).count == 1
    let first = await CodexAccountUsageProbe.fetch(homeDirectory: home, appVersion: "t", now: t0, cache: cache, lookup: none.lookup, run: runner.run)
    #expect((try? first.get())?.monthTotal("2026-09") == 60_000)
    #expect(cache.confirmedToolchain?.executable.path.hasSuffix("macos-arm64/codex") == true)

    // 같은 후보가 기동 실패 → 폐기 → 남은 후보 0 → `.failed`(미설치 아님).
    runner.set("macos-arm64/codex", (.failure(.init(status: .failed, reason: "launch")), .launchFailed))
    runner.reset()
    let t1 = t0.addingTimeInterval(1_800)
    let second = await CodexAccountUsageProbe.fetch(homeDirectory: home, appVersion: "t", now: t1, cache: cache, lookup: none.lookup, run: runner.run)
    if case .failure(let f) = second { #expect(f.status == .failed, "설치된 codex 가 못 도는 것을 미설치로 올렸다: \(f)") } else { Issue.record("실패여야 한다") }
    #expect(cache.confirmedToolchain == nil)
    #expect(cache.failure?.status == .failed)
    #expect(cache.failure?.at == t1)
    if onlyIDE {
        #expect(runner.attempts.count == 1, "폐기한 후보 말고는 띄울 것이 없어야 한다: \(runner.attempts)")
    }
    // TTL 안에서는 캐시된 `.failed` 를 그대로 돌려준다(프로세스 0).
    runner.reset()
    let cached = await CodexAccountUsageProbe.fetch(homeDirectory: home, appVersion: "t", now: t1.addingTimeInterval(60), cache: cache, lookup: none.lookup, run: runner.run)
    if case .failure(let f) = cached { #expect(f.status == .failed) } else { Issue.record("캐시된 실패여야 한다") }
    #expect(runner.attempts.isEmpty)
}

/// 종료 경로의 잔여 드레인은 **비차단**이다(리뷰 P2): 쓰는 쪽이 아직 열려 있어도(고아 자식이 파이프를 쥔 모양) 지금 있는 만큼만
/// 읽고 돌아온다. 차단 읽기(readToEnd)였다면 EOF 까지 영원히 기다려 스레드가 샌다 — 세마포어 2초로 그 차이를 가른다.
/// 뮤테이션: O_NONBLOCK 설정을 빼면 두 번째 드레인(빈 파이프)이 막혀 빨강.
@Test
func probeDrainNonBlockingReturnsWhatIsThereWithoutWaitingForEOF() throws {
    let pipe = Pipe()
    let fd = pipe.fileHandleForReading.fileDescriptor
    defer { try? pipe.fileHandleForWriting.close() }   // 뮤턴트가 막혔더라도 스레드를 풀어 준다
    final class Box: @unchecked Sendable { let lock = NSLock(); var data: Data? }
    func drain(timeout: TimeInterval) -> Data? {
        let box = Box()
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            let d = CodexAccountUsageProbe.drainNonBlocking(fd)
            box.lock.withLock { box.data = d }
            done.signal()
        }
        guard done.wait(timeout: .now() + timeout) == .success else { return nil }
        return box.lock.withLock { box.data }
    }
    try pipe.fileHandleForWriting.write(contentsOf: Data("partial-line-without-newline".utf8))
    let first = try #require(drain(timeout: 2), "쓰는 쪽이 열린 채로 드레인이 돌아오지 않았다(차단 읽기)")
    #expect(String(decoding: first, as: UTF8.self) == "partial-line-without-newline")
    // 비어 있는 파이프(쓰는 쪽은 여전히 열림): 즉시 빈 데이터.
    let empty = try #require(drain(timeout: 2), "빈 파이프에서 드레인이 막혔다")
    #expect(empty.isEmpty)
    // 여러 조각이 쌓여 있어도 지금 있는 만큼 전부 읽는다(파이프 버퍼 16KiB 아래로 두어 쓰기가 막히지 않게).
    let chunk = Data(repeating: 0x41, count: 10_000)
    try pipe.fileHandleForWriting.write(contentsOf: chunk)
    try pipe.fileHandleForWriting.write(contentsOf: Data("\n".utf8))
    let all = try #require(drain(timeout: 2))
    #expect(all.count == chunk.count + 1)
    // 쓰는 쪽이 닫히면(EOF) 빈 데이터로 즉시 돌아온다.
    try pipe.fileHandleForWriting.close()
    #expect(drain(timeout: 2)?.isEmpty == true)
}

@Test
func probeStatusRawValuesMatchServerColumnContract() {
    // 서버 smallint 계약(20260903160000 마이그레이션 주석): 1 ok · 2 미설치 · 3 미로그인 · 4 타임아웃 · 5 실패.
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

/// CODEX_HOME 사용자(리뷰 P2): auth.json 은 `$CODEX_HOME/auth.json` 에 있다. 주입된 홈 확정이 그 경로를 주면 `~/.codex` 에
/// auth.json 이 없어도 러너가 돈다. 반대로 CODEX_HOME 아래에 없으면 `~/.codex` 에 있어도 미로그인이다(codex 도 그렇게 본다).
/// 뮤테이션: refreshIfDue 가 codexHomeResolver 를 무시하고 `~/.codex` 만 보면 빨강.
@MainActor
@Test
func accountStoreChecksAuthUnderResolvedCodexHome() async {
    let home = c41TempHome("codex-home-auth")
    defer { try? FileManager.default.removeItem(at: home) }
    let custom = home.appendingPathComponent("custom-codex", isDirectory: true)
    c41Write("{\"tokens\":\"secret\"}", to: custom.appendingPathComponent("auth.json"))
    let runner = C41Runner(.success(c41Usage()))
    let resolverCalls = C41Runner(.success(c41Usage()))
    let store = CodexAccountUsageStore(
        defaults: c41Defaults(), homeDirectory: home,
        codexHome: { _ = await resolverCalls.run(home, c41FetchedAt); return custom },
        runner: runner.run)
    await store.refreshIfDue(now: c41FetchedAt)
    #expect(runner.calls == 1, "CODEX_HOME 아래 auth.json 을 두고도 미로그인으로 끝났다")
    #expect(resolverCalls.calls == 1)
    #expect(store.lastStatus == .ok)

    // CODEX_HOME 은 있는데 그 아래 auth.json 이 없다 — `~/.codex/auth.json` 이 있어도 미로그인(러너 0).
    let other = c41TempHome("codex-home-auth-2")
    defer { try? FileManager.default.removeItem(at: other) }
    c41LogIn(other)
    let strict = CodexAccountUsageStore(
        defaults: c41Defaults(), homeDirectory: other,
        codexHome: { other.appendingPathComponent("empty-codex", isDirectory: true) },
        runner: runner.run)
    await strict.refreshIfDue(now: c41FetchedAt)
    #expect(runner.calls == 1)
    #expect(strict.lastStatus == .notLoggedIn)
    // 홈 확정을 기다리는 동안에도 재진입은 막힌다(inFlight 가 await 앞에 선다).
    let slow = CodexAccountUsageStore(
        defaults: c41Defaults(), homeDirectory: home,
        codexHome: { try? await Task.sleep(for: .milliseconds(120)); return custom },
        runner: runner.run)
    async let first: Void = slow.refreshIfDue(now: c41FetchedAt)
    try? await Task.sleep(for: .milliseconds(20))
    #expect(slow.isDue(now: c41FetchedAt.addingTimeInterval(3_600), force: true) == false)
    await first
    #expect(runner.calls == 2)
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
    // 수집 설정이 서버에서 도착한 상태(프로브 게이트). 도착 전의 동작은 uploadWrapperWaitsForCollectSettingBeforeProbing 이 본다.
    store.tokenUsagePublicLoaded = true
    store.tokenUsageCollectLoaded = true
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

/// 수집 설정이 서버에서 도착하기 전(tokenUsageCollectLoaded == false)에는 프로브가 돌지 않는다(리뷰 P2) — 기본값이 '수집'이라
/// 거부자의 맥에서 로그인 직후 한 틱에 `codex app-server` 가 뜰 수 있었다. 업로드는 서버 트리거가 버리므로 그대로 나간다.
/// 뮤테이션: 래퍼 게이트에서 tokenUsageCollectLoaded 를 빼면 빨강.
@MainActor
@Test
func uploadWrapperWaitsForCollectSettingBeforeProbing() async {
    let host = "v0241-wrapper-loaded"
    let home = c41TempHome("wrapper-loaded-home")
    defer { try? FileManager.default.removeItem(at: home) }
    c41LogIn(home)
    let runner = C41Runner(.success(c41Usage(month: 7, fetchedAt: c41SepNow)))
    let account = CodexAccountUsageStore(defaults: c41Defaults(), homeDirectory: home, runner: runner.run)
    let store = c41Store(host: host, tokenUsage: c41TokenStore(home: home, now: c41SepNow, snapshot: c41LocalUsage(total: 3_000)), codexAccount: account)
    defer { c41CancelTasks(store) }
    store.tokenUsageCollectLoaded = false
    await store.uploadTokenUsageIfNeeded(now: c41SepNow)
    #expect(runner.calls == 0, "수집 설정 도착 전에 codex 프로세스가 떴다")
    #expect(c41UploadBodies(host: host).count == 1)   // 업로드 자체는 나간다(서버가 막는다)
    #expect(c41UploadBodies(host: host).first?["codex_account_month"] == nil)
    // 설정이 도착하면(로드 완료) 다음 틱에 돈다.
    store.tokenUsageCollectLoaded = true
    await store.uploadTokenUsageIfNeeded(now: c41SepNow.addingTimeInterval(61))
    #expect(runner.calls == 1)
    #expect(c41UploadBodies(host: host).last?["codex_account_month"] as? Int == 7)
}

/// 프로필 프라이버시 GET(`token_usage_public` select)만 가로채 **정해진 시간 동안 응답을 붙들어 두는** 프로토콜. 나머지 요청은
/// protocolClasses 의 다음 순서인 URLProtocolStub 이 그대로 받는다. URLProtocolStub 의 `delayed-` 접두어(0.15초)로는 병렬 스위트
/// 부하에서 '토글 → 게이트 판정' 사이에 응답이 먼저 도착해 흔들린다 — 지연을 넉넉히(0.6초) 두고, 요청이 **나간 순간**을
/// 세어 그 뒤에 토글하므로 순서가 확정된다.
private final class C41HeldPrivacyGET: URLProtocol {
    nonisolated(unsafe) static var holdSeconds: TimeInterval = 0.6
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _started: [String: Int] = [:]
    /// 호스트별 '나간(아직 응답 전일 수 있는)' 프라이버시 GET 수.
    static func started(host: String) -> Int { lock.withLock { _started[host, default: 0] } }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.path == "/rest/v1/profiles" && request.httpMethod == "GET"
            && request.url?.query?.contains("token_usage_public") == true
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let host = request.url?.host ?? ""
        Self.lock.withLock { Self._started[host, default: 0] += 1 }
        let box = C41HeldDelivery(
            proto: self,
            response: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
        DispatchQueue.global().asyncAfter(deadline: .now() + Self.holdSeconds) { box.run() }
    }
    override func stopLoading() {}
}

/// 붙들어 둔 응답의 전달(URLProtocolStub.StubDelivery 와 같은 꼴 — Process/URLProtocol 은 Sendable 이 아니라 상자에 넣는다).
private final class C41HeldDelivery: @unchecked Sendable {
    let proto: URLProtocol
    let response: HTTPURLResponse
    init(proto: URLProtocol, response: HTTPURLResponse) { self.proto = proto; self.response = response }
    func run() {
        proto.client?.urlProtocol(proto, didReceive: response, cacheStoragePolicy: .notAllowed)
        proto.client?.urlProtocol(proto, didLoad: Data(#"[{"token_usage_public":true}]"#.utf8))
        proto.client?.urlProtocolDidFinishLoading(proto)
    }
}

/// c41Store 와 같되 프라이버시 GET 을 C41HeldPrivacyGET 이 붙든다. 플래그는 **로그인 직후 모양**(아무 설정도 안 옴)으로 둔다.
@MainActor
private func c41HeldPrivacyStore(host: String, tokenUsage: TokenUsageStore, codexAccount: CodexAccountUsageStore) -> WorkTimerStore {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [C41HeldPrivacyGET.self, URLProtocolStub.self]
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!, anonKey: "anon-test-key", session: URLSession(configuration: configuration))
    let store = WorkTimerStore(
        service: service, environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"], defaults: c41Defaults(),
        workspaceNotifications: nil, tokenUsage: tokenUsage, codexAccount: codexAccount)
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: c41UserID)
    store.currentTeamID = URLProtocolStub.stubTeamID
    store.membershipConfirmed = true
    store.isMenuPresented = false
    store.tokenUsagePublicLoaded = false
    store.tokenUsageCollectLoaded = false
    return store
}

/// 리뷰 2차 P2 — 프로브 게이트는 낙관 플래그(tokenUsagePublicLoaded)가 아니라 **수집 설정 수신**(tokenUsageCollectLoaded)이다.
/// 프로필 GET 이 아직 응답하지 않은 채 사용자가 공개 토글을 누르면 setTokenUsagePublic 이 tokenUsagePublicLoaded 를 먼저 세운다 —
/// 옛 게이트는 그것을 '설정 도착'으로 읽어 거부자의 맥에서 `codex app-server` 를 띄웠다. 응답이 실제로 오면 그때 게이트가
/// 열리고, 늦게 온 서버값이 사용자의 선택을 덮지도 않는다.
/// 뮤테이션: 게이트를 tokenUsagePublicLoaded 로 되돌리면 첫 단언(러너 0)이 빨강; 로더가 응답 전에 플래그를 세우면 빨강.
@MainActor
@Test
func uploadWrapperIgnoresOptimisticPublicFlagUntilCollectSettingActuallyArrives() async {
    let host = "v0241-collect-flag"
    let home = c41TempHome("collect-flag-home")
    defer { try? FileManager.default.removeItem(at: home) }
    c41LogIn(home)
    let runner = C41Runner(.success(c41Usage(month: 9, fetchedAt: c41SepNow)))
    let account = CodexAccountUsageStore(defaults: c41Defaults(), homeDirectory: home, runner: runner.run)
    let store = c41HeldPrivacyStore(host: host, tokenUsage: c41TokenStore(home: home, now: c41SepNow, snapshot: c41LocalUsage(total: 3_000)), codexAccount: account)
    defer { c41CancelTasks(store) }
    store.tokenUsagePublic = false   // 직전 실행에서 비공개였던 사람이

    // 프로필 GET 을 띄워 두고(응답은 붙들려 있다) 그 사이에 공개 토글을 누른다. 요청이 **나간 것**을 확인한 뒤 진행한다.
    async let load: Void = store.loadTokenUsagePrivacyIfNeeded()
    for _ in 0..<200 where C41HeldPrivacyGET.started(host: host) == 0 { try? await Task.sleep(for: .milliseconds(5)) }
    #expect(C41HeldPrivacyGET.started(host: host) == 1, "프로필 GET 이 나가 있어야 한다(응답 대기 중)")
    #expect(store.tokenUsageCollectLoaded == false, "응답 전에 수신 플래그가 섰다")
    store.setTokenUsagePublic(true)
    #expect(store.tokenUsagePublicLoaded == true)      // 낙관 플래그는 GET 전에 선다(사용자 선택 보호 — 옛 규약)
    #expect(store.tokenUsageCollectLoaded == false)    // 수신 플래그는 여전히 아니다

    await store.uploadTokenUsageIfNeeded(now: c41SepNow)
    #expect(runner.calls == 0, "수집 설정이 서버에서 오기 전에 공개 토글만으로 codex 프로세스가 떴다(리뷰 2차 P2)")
    #expect(c41UploadBodies(host: host).count == 1)   // 업로드 자체는 나간다(서버 트리거가 막는다)

    // 응답이 실제로 오면 그때 플래그가 서고, 다음 틱에 프로브가 돈다.
    await load
    #expect(store.tokenUsageCollectLoaded == true, "서버 응답을 받았는데 수신 플래그가 안 섰다")
    #expect(C41HeldPrivacyGET.started(host: host) == 1)
    await store.uploadTokenUsageIfNeeded(now: c41SepNow.addingTimeInterval(61))
    #expect(runner.calls == 1)
    #expect(c41UploadBodies(host: host).last?["codex_account_month"] as? Int == 9)

    // 사용자가 GET 전에 **비공개**를 골랐으면 늦게 온 서버값(공개 true)이 그 선택을 덮지 않는다 — 대신 수집 설정은 받아
    // 게이트가 열린다(옛 규약처럼 로더를 통째로 건너뛰면 그 세션 내내 프로브가 잠긴다).
    let host2 = host + "-private"
    let account2 = CodexAccountUsageStore(defaults: c41Defaults(), homeDirectory: home, runner: runner.run)
    let store2 = c41HeldPrivacyStore(host: host2, tokenUsage: c41TokenStore(home: home, now: c41SepNow, snapshot: c41LocalUsage(total: 3_000)), codexAccount: account2)
    defer { c41CancelTasks(store2) }
    store2.setTokenUsagePublic(false)
    await store2.loadTokenUsagePrivacyIfNeeded()   // 게이트는 수신 플래그라 토글 뒤에도 GET 은 나간다
    #expect(store2.tokenUsageCollectLoaded == true)
    #expect(store2.tokenUsagePublic == false, "늦게 온 서버값이 사용자의 비공개 선택을 덮었다")
    await store2.loadTokenUsagePrivacyIfNeeded()   // 받은 뒤엔 다시 묻지 않는다
    #expect(C41HeldPrivacyGET.started(host: host2) == 1)
    await store2.uploadTokenUsageIfNeeded(now: c41SepNow)
    #expect(runner.calls == 2)
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
func effectiveTotalFollowsTheAccountFirstRule() {
    // v0.2.43: 내 박스 총합은 `claude 합 + CodexEffectiveRule.month(...)` — 계정이 반영된 날은 계정, 미반영 꼬리만 로컬.
    // (v0.2.41 의 max(로컬, 계정) 은 포크 복사본으로 부푼 로컬을 골랐다 — V0243AccountFirstTests 가 규칙 자체를 고정한다.)
    var local = TokenUsageMonthly(month: "2026-09")
    local.claudeInput = 1_000; local.claudeCacheRead = 9_000
    local.codexInput = 400; local.codexOutput = 100; local.codexCacheRead = 350
    local.codexDaily = ["2026-09-01": 300, "2026-09-02": 150, "2026-09-03": 50]
    #expect(TokenUsageDisplay.effectiveTotal(local: local, account: nil) == 10_500)                 // 계정 없음 → 로컬
    let empty = CodexAccountUsage(fetchedAt: c41FetchedAt, lifetimeTokens: nil, buckets: ["2026-08-31": 999])
    #expect(TokenUsageDisplay.effectiveTotal(local: local, account: empty) == 10_500)               // 이 달 버킷 없음 → 로컬
    // 계정 9/1 100 · 9/2 120(마지막 버킷) → 220 + 꼬리 9/3 50 + max(0, 150 − 120) = 300. 로컬 500 이 커도 갈아타지 않는다.
    let account = CodexAccountUsage(fetchedAt: c41FetchedAt, lifetimeTokens: nil, buckets: ["2026-09-01": 100, "2026-09-02": 120])
    #expect(TokenUsageDisplay.codexEffective(local: local, account: account) == 300)
    #expect(TokenUsageDisplay.effectiveTotal(local: local, account: account) == 10_300)
    #expect(local.total == 10_500)                                                                   // 업로드값 불변(캐시 미포함)
}

@Test
func tooltipListsAccountAndLocalWhenTheAccountMonthIsPositive() {
    var usage = TokenUsageMonthly(month: "2026-09")
    usage.codexInput = 1_000; usage.codexOutput = 200; usage.codexCacheRead = 700
    // v0.2.43 UTC 축: Codex 가 있는 툴팁은 끝에 하루의 뜻(9시 경계)을 밝힌다(V0243UTCAxisTests 가 리터럴·배선을 고정).
    let axis = " · " + TokenUsageMonthly.tokenDayAxisNote
    let base = "Codex 1,200 (입력 1,000 · 출력 200 · 캐시 700)"
    let labeled = "Codex 로컬 집계 1,200 (입력 1,000 · 출력 200 · 캐시 700)"
    #expect(usage.detailTooltip == base + axis)
    // v0.2.43: 이 달 계정 월합이 있으면 로컬 줄에 "로컬 집계" 라벨, 계정 줄, "총합은 계정 집계 기준" — 계정이 로컬보다 크든 작든 같다.
    let big = CodexAccountUsage(fetchedAt: c41FetchedAt, lifetimeTokens: nil, buckets: ["2026-09-01": 3_000, "2026-09-07": 2_000, "2026-08-31": 999])
    #expect(usage.detailTooltip(account: big) == labeled + " · Codex 계정 집계 5,000 (7일까지 반영) · 총합은 계정 집계 기준" + axis)
    let equal = CodexAccountUsage(fetchedAt: c41FetchedAt, lifetimeTokens: nil, buckets: ["2026-09-02": 1_200])
    #expect(usage.detailTooltip(account: equal) == labeled + " · Codex 계정 집계 1,200 (2일까지 반영) · 총합은 계정 집계 기준" + axis)
    // 이 달 버킷이 없으면(월합 0) 계정 줄 없음 — 지난달 버킷을 이번 달 반영일로 오인하지 않는다.
    let lastMonthOnly = CodexAccountUsage(fetchedAt: c41FetchedAt, lifetimeTokens: nil, buckets: ["2026-08-31": 999])
    #expect(usage.detailTooltip(account: lastMonthOnly) == base + axis)
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
    // v0.2.43: 계정 우선 규칙은 월합만으로는 못 세고(꼬리·마지막 버킷) 스냅샷이 필요하다 — 뷰가 스냅샷 자체를 넘긴다.
    #expect(row.contains("TokenUsageDisplay.effectiveTotal(local: usage, account: account?.snapshot)"))
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
    // 종료 경로의 잔여 읽기는 비차단 드레인이다(리뷰 P2). 차단 읽기(readToEnd/readDataToEndOfFile)가 프로브 소스에 돌아오면
    // npm 런처의 고아 자식이 파이프를 쥔 채 남을 때 스레드가 영원히 샌다 — 그 호출 지점은 프로세스 없이는 못 재현하므로
    // 드레인 함수 테스트(probeDrainNonBlocking…)와 이 계약으로 짝을 맞춘다.
    #expect(probe.contains("s.received.append(CodexAccountUsageProbe.drainNonBlocking(reader.fileDescriptor))"))
    #expect(!probe.contains("readToEnd(") && !probe.contains("readDataToEndOfFile("), "프로브에 차단 읽기가 돌아왔다")
    // 셸 조회도 세마포어·waitUntilExit 없이 ProcessSession(콜백+데드라인)으로 돈다(리뷰 P2: 협력 스레드 풀 잠식).
    #expect(!probe.contains("DispatchSemaphore") && !probe.contains("waitUntilExit("), "셸 조회가 호출 스레드를 막는다")
    #expect(probe.contains("executable: URL(fileURLWithPath: \"/bin/zsh\")"))
}

/// 서버 마이그레이션 계약(20260903160000): 컬럼 6개 · 보드 14컬럼 · 계정은 max · greatest · 진단 판정 · 진단 상태는 min ·
/// anon 차단 · 프로브 롤백. 파일이 없으면(supabase/ 없는 체크아웃) 다른 SQL 계약 테스트(20260726010000 등)와 같이 **빨강**이다 —
/// 조용히 통과하면 계약이 검사되지 않은 채 초록으로 보인다(리뷰 P2).
@Test
func migrationContractCodexAccountUsage() throws {
    let url = c41RepoURL("supabase/migrations/20260903160000_codex_account_usage.sql")
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
    // 진단 상태는 기기 중 최선(min). max 면 한 기기의 실패가 계정값을 받은 기기를 가린다.
    #expect(sql.contains("min(d.codex_account_status)::smallint"))
    #expect(!sql.contains("max(d.codex_account_status)"))
    #expect(sql.contains("h.codex_account_status = 1 and h.codex_account_month = 1000"))   // 프로브 ⓕ (A=1, B=5 → 1)
    #expect(sql.contains("grant  execute on function public.token_scan_health(text) to service_role;"))
    #expect(sql.contains("raise exception 'CODEX_ACCOUNT_USAGE_PROBE_ROLLBACK';"))
    #expect(sql.contains("if sqlerrm <> 'CODEX_ACCOUNT_USAGE_PROBE_ROLLBACK' then raise; end if;"))
    #expect(sql.contains("if n <> 18 then"))   // 새 컬럼 6 × 3 권한
    #expect(!sql.contains("create table"))     // 표를 만들지 않는다(PGRST201 회피)
}
