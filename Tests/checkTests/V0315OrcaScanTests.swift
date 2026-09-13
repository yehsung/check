import Foundation
import Testing
@testable import check

// MARK: - v0.3.15: Orca 로 쓴 Codex/Claude 로컬 사용량 집계
//
// 배경(2026-09-13 실측): Orca(stablyai/orca)에 Codex 계정을 연동하면 Codex 가 `~/Library/Application Support/orca/
// codex-accounts/<id>/home` 을 CODEX_HOME 으로 받아 거기에만 rollout 을 쓴다. 스캐너가 `~/.codex` 만 봐서 계정 사용량은
// 올라오는데 로컬 Codex 가 0 이었다. Orca 는 같은 rollout 을 여러 home 에 하드링크(교차 볼륨이면 복사)로 걸기도 해서,
// 폴더만 늘리면 두 배가 된다 — 이 파일의 절반은 "한 번만 센다"를 지킨다.
//
// 모든 테스트는 임시 홈의 픽스처만 읽는다.

private let o315Now = Date(timeIntervalSince1970: 1_784_000_000)   // KST 2026-07-14 12:33:20

private func o315UTC(_ iso: String) -> Date {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    f.timeZone = TimeZone(identifier: "UTC")
    return f.date(from: iso)!
}

private func o315ISO(_ date: Date) -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    f.timeZone = TimeZone(identifier: "UTC")
    return f.string(from: date)
}

private let o315July5 = o315UTC("2026-07-05T01:00:00Z")

private func o315TempHome(_ tag: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("check-v0315-\(tag)-\(UUID().uuidString)", isDirectory: true)
}

private func o315Orca(_ home: URL) -> URL {
    home.appendingPathComponent("Library/Application Support/orca", isDirectory: true)
}

private func o315AccountHome(_ home: URL, _ id: String) -> URL {
    o315Orca(home).appendingPathComponent("codex-accounts/\(id)/home", isDirectory: true)
}

private func o315RuntimeHome(_ home: URL) -> URL {
    o315Orca(home).appendingPathComponent("codex-runtime-home/home", isDirectory: true)
}

private func o315Write(_ contents: String, to url: URL, modified: Date = o315Now) {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? Data(contents.utf8).write(to: url)
    try? FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
}

private func o315Append(_ contents: String, to url: URL, modified: Date) {
    if let h = try? FileHandle(forWritingTo: url) {
        _ = try? h.seekToEnd()
        try? h.write(contentsOf: Data(contents.utf8))
        try? h.close()
    }
    try? FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
}

private func o315Event(input: Int, output: Int, at date: Date = o315July5) -> String {
    "{\"timestamp\":\"\(o315ISO(date))\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\","
    + "\"info\":{\"total_token_usage\":{\"input_tokens\":\(input),\"cached_input_tokens\":0,"
    + "\"output_tokens\":\(output),\"total_tokens\":0}}}}"
}

/// 누적치 목록 → rollout 본문. 첫 이벤트는 기준선이라 합계 = 마지막 − 첫.
private func o315Body(_ cumulative: [(Int, Int)]) -> String {
    cumulative.map { o315Event(input: $0.0, output: $0.1) }.joined(separator: "\n") + "\n"
}

private func o315Scan(_ cache: TokenUsageCache = TokenUsageCache(), home: URL, codexHome: URL? = nil, now: Date = o315Now)
    -> TokenUsageIncrementalScanner.Result {
    TokenUsageIncrementalScanner.update(cache, homeDirectory: home, codexHome: codexHome, now: now)
}

private func o315ClaudeLine(id: String, requestId: String, input: Int, output: Int) -> String {
    "{\"type\":\"assistant\",\"timestamp\":\"\(o315ISO(o315July5))\",\"requestId\":\"\(requestId)\","
    + "\"message\":{\"id\":\"\(id)\",\"usage\":{\"input_tokens\":\(input),\"output_tokens\":\(output),"
    + "\"cache_read_input_tokens\":0,\"cache_creation_input_tokens\":0}}}"
}

// MARK: - 루트

/// Orca 계정 home 의 sessions 와 archived_sessions 가 집계된다.
/// 뮤테이션: codexHomes 에서 Orca home 추가를 빼면 빨강.
@Test
func orcaAccountHomeSessionsAndArchivedAreCounted() {
    let home = o315TempHome("account")
    defer { try? FileManager.default.removeItem(at: home) }
    let account = o315AccountHome(home, "e9f7e9bc")
    o315Write(o315Body([(100, 0), (1_100, 100)]),
              to: account.appendingPathComponent("sessions/2026/07/05/rollout-2026-07-05T00-00-00-a.jsonl"))
    o315Write(o315Body([(10, 0), (510, 0)]),
              to: account.appendingPathComponent("archived_sessions/rollout-2026-07-04T00-00-00-b.jsonl"))

    let r = o315Scan(home: home)
    #expect(r.usage.codexTotal == 1_600, "Orca 계정 home 의 rollout 이 안 잡혔다: \(r.usage.codexTotal)")
    #expect(r.stats.codexFilesStatted == 2)
}

/// Orca 공유 런타임 미러도 집계되고, home 순위는 기본 → 런타임 미러 → 계정(이름순)이다.
/// 뮤테이션: codexHomes 에서 Orca home 추가를 빼면 빨강.
@Test
func orcaSharedRuntimeHomeIsCountedAndHomesAreOrdered() {
    let home = o315TempHome("runtime")
    defer { try? FileManager.default.removeItem(at: home) }
    o315Write(o315Body([(0, 0), (600, 100)]),
              to: o315RuntimeHome(home).appendingPathComponent("sessions/2026/07/05/rollout-2026-07-05T00-00-00-rt.jsonl"))
    try? FileManager.default.createDirectory(at: o315AccountHome(home, "bbb"), withIntermediateDirectories: true)
    try? FileManager.default.createDirectory(at: o315AccountHome(home, "aaa"), withIntermediateDirectories: true)

    #expect(o315Scan(home: home).usage.codexTotal == 700)
    let homes = TokenUsageIncrementalScanner.codexHomes(homeDirectory: home, codexHome: nil)
    #expect(homes.map(\.path) == [
        home.appendingPathComponent(".codex").path,
        o315RuntimeHome(home).path,
        o315AccountHome(home, "aaa").path,
        o315AccountHome(home, "bbb").path
    ])
    #expect(TokenUsageIncrementalScanner.codexRoots(homeDirectory: home, codexHome: nil).count == 8)
}

/// Orca 폴더가 없으면 루트는 종전과 정확히 같은 두 원소다.
@Test
func codexRootsWithoutOrcaAreExactlyTheLegacyPair() {
    let home = o315TempHome("no-orca")
    defer { try? FileManager.default.removeItem(at: home) }
    let roots = TokenUsageIncrementalScanner.codexRoots(homeDirectory: home, codexHome: nil)
    #expect(roots.map(\.path) == [
        home.appendingPathComponent(".codex/sessions").path,
        home.appendingPathComponent(".codex/archived_sessions").path
    ])
}

// MARK: - 별칭(하드링크·복사본)

/// `~/.codex` 와 Orca 계정 home 에 하드링크된 같은 rollout 은 한 번만 센다. 정본은 home 순위가 앞선 `~/.codex`.
/// 하드링크라 한쪽에 이어 쓰면 양쪽이 같이 자라고, 그래도 한 번만 더해진다.
/// 뮤테이션: scanCodex 의 dedupeCodexAliases 호출을 빼면 빨강(두 배).
@Test
func hardlinkedRolloutAcrossHomesCountsOnce() throws {
    let home = o315TempHome("hardlink")
    defer { try? FileManager.default.removeItem(at: home) }
    let name = "rollout-2026-07-05T00-00-00-hl.jsonl"
    let original = home.appendingPathComponent(".codex/sessions/2026/07/05/\(name)")
    o315Write(o315Body([(100, 0), (2_100, 300)]), to: original)
    let alias = o315AccountHome(home, "acct").appendingPathComponent("sessions/2026/07/05/\(name)")
    try FileManager.default.createDirectory(at: alias.deletingLastPathComponent(), withIntermediateDirectories: true)
    #expect(link(original.path, alias.path) == 0, "하드링크 픽스처 실패")

    let r1 = o315Scan(home: home)
    #expect(r1.usage.codexTotal == 2_300, "하드링크 별칭이 두 번 계상됐다: \(r1.usage.codexTotal)")
    #expect(r1.cache.codexFileStates.count == 1)
    #expect(r1.cache.codexFileStates.keys.first?.contains("/.codex/sessions/") == true)
    #expect(r1.stats.codexAliasFilesSkipped == 1)

    o315Append(o315Event(input: 3_100, output: 400) + "\n", to: alias, modified: o315Now.addingTimeInterval(60))
    let r2 = o315Scan(r1.cache, home: home)
    #expect(r2.usage.codexTotal == 3_400)
    #expect(r2.cache.codexFileStates.count == 1)
    #expect(o315Scan(home: home).usage.codexTotal == r2.usage.codexTotal)
}

/// 복사본(같은 이름·같은 바이트·다른 inode)도 한 번만 센다. Orca 쪽 복사본에 이어 쓰면 정본이 그쪽으로 넘어가고,
/// 합계는 큰 파일을 전량 재파싱한 값과 같으며 옛 정본(`~/.codex`) 상태는 지워진다.
/// 뮤테이션: (a) dedupe 호출 제거 → r1 두 배로 빨강 (b) 정리 규칙의 aliasPaths 삭제 분기 제거 → r2 에서 옛 정본 상태가 남아 빨강.
@Test
func copiedRolloutAcrossHomesCountsOnceAndFollowsTheGrowingCopy() {
    let home = o315TempHome("copy")
    defer { try? FileManager.default.removeItem(at: home) }
    let name = "rollout-2026-07-05T00-00-00-cp.jsonl"
    let body = o315Body([(100, 0), (2_100, 300)])
    let original = home.appendingPathComponent(".codex/sessions/2026/07/05/\(name)")
    let copy = o315AccountHome(home, "acct").appendingPathComponent("sessions/2026/07/05/\(name)")
    o315Write(body, to: original)
    o315Write(body, to: copy)

    let r1 = o315Scan(home: home)
    #expect(r1.usage.codexTotal == 2_300, "복사본이 두 번 계상됐다: \(r1.usage.codexTotal)")
    #expect(r1.cache.codexFileStates.count == 1)
    #expect(r1.cache.codexFileStates.keys.first?.contains("/.codex/sessions/") == true)

    o315Append(o315Event(input: 3_100, output: 400) + "\n", to: copy, modified: o315Now.addingTimeInterval(60))
    let r2 = o315Scan(r1.cache, home: home)
    #expect(r2.usage.codexTotal == 3_400, "정본 전환 뒤 합계가 틀렸다(옛 정본 상태 잔존 = 두 배): \(r2.usage.codexTotal)")
    #expect(r2.cache.codexFileStates.count == 1)
    #expect(r2.cache.codexFileStates.keys.first?.contains("/orca/codex-accounts/") == true)
    #expect(o315Scan(home: home).usage.codexTotal == r2.usage.codexTotal)   // 전량 재파싱과 같다

    let r3 = o315Scan(r2.cache, home: home)
    #expect(r3.usage.codexTotal == 3_400)
    #expect(r3.stats.cacheChanged == false)
}

/// 이름이 다른 두 세션은 home 이 달라도 둘 다 센다(과잉 제거 방지).
@Test
func distinctRolloutsInDifferentHomesAreBothCounted() {
    let home = o315TempHome("distinct")
    defer { try? FileManager.default.removeItem(at: home) }
    o315Write(o315Body([(0, 0), (1_000, 0)]),
              to: home.appendingPathComponent(".codex/sessions/2026/07/05/rollout-2026-07-05T00-00-00-x.jsonl"))
    o315Write(o315Body([(0, 0), (200, 0)]),
              to: o315AccountHome(home, "acct").appendingPathComponent("sessions/2026/07/05/rollout-2026-07-05T00-00-00-y.jsonl"))
    let r = o315Scan(home: home)
    #expect(r.usage.codexTotal == 1_200)
    #expect(r.stats.codexAliasFilesSkipped == 0)
}

/// 같은 home 안의 동명(sessions↔archived — 보관 rename 경합)은 별칭 제거가 건드리지 않는다(기존 규칙 몫).
@Test
func aliasDedupeLeavesSameHomeNameCollisionsAlone() {
    let home = o315TempHome("same-home")
    defer { try? FileManager.default.removeItem(at: home) }
    let roots = TokenUsageIncrementalScanner.codexRoots(homeDirectory: home, codexHome: nil)
    let name = "rollout-2026-07-05T00-00-00-race.jsonl"
    let files: [(url: URL, size: Int, mtimeMicros: Int)] = [
        (roots[0].appendingPathComponent("2026/07/05/\(name)"), 10, 1),
        (roots[1].appendingPathComponent(name), 20, 1)
    ]
    let d = TokenUsageIncrementalScanner.dedupeCodexAliases(files, roots: roots)
    #expect(d.kept.count == 2)
    #expect(d.aliasPaths.isEmpty)
}

/// CODEX_HOME 이 Orca 계정 home 을 가리키면 그 home 을 한 번만 연다.
/// 뮤테이션: codexHomes 의 정규 경로 중복 제거를 빼면 빨강.
@Test
func codexHomePointingAtOrcaAccountHomeIsScannedOnce() {
    let home = o315TempHome("codex-home-orca")
    defer { try? FileManager.default.removeItem(at: home) }
    let account = o315AccountHome(home, "acct")
    o315Write(o315Body([(0, 0), (900, 0)]), to: account.appendingPathComponent("sessions/2026/07/05/rollout-2026-07-05T00-00-00-ch.jsonl"))

    let homes = TokenUsageIncrementalScanner.codexHomes(homeDirectory: home, codexHome: account)
    #expect(homes.count == 1, "같은 home 이 두 번 들어갔다: \(homes.map(\.path))")
    let r = o315Scan(home: home, codexHome: account)
    #expect(r.usage.codexTotal == 900)
    #expect(r.stats.codexFilesStatted == 1)
}

/// 심볼릭 링크인 계정 디렉터리·home 은 제외한다(리다이렉트된 루트를 훑지 않는다).
/// 뮤테이션: codexHomes 의 isRealDirectory 검사를 빼면 빨강.
@Test
func symlinkedOrcaAccountHomesAreSkipped() throws {
    let home = o315TempHome("symlink")
    defer { try? FileManager.default.removeItem(at: home) }
    let elsewhereA = home.appendingPathComponent("elsewhere-a", isDirectory: true)
    let elsewhereB = home.appendingPathComponent("elsewhere-b/home", isDirectory: true)
    o315Write(o315Body([(0, 0), (500, 0)]), to: elsewhereA.appendingPathComponent("home/sessions/2026/07/05/rollout-2026-07-05T00-00-00-la.jsonl"))
    o315Write(o315Body([(0, 0), (700, 0)]), to: elsewhereB.appendingPathComponent("sessions/2026/07/05/rollout-2026-07-05T00-00-00-lb.jsonl"))
    let accounts = o315Orca(home).appendingPathComponent("codex-accounts", isDirectory: true)
    try FileManager.default.createDirectory(at: accounts.appendingPathComponent("real-id"), withIntermediateDirectories: true)
    // (1) <id> 디렉터리가 링크
    try FileManager.default.createSymbolicLink(at: accounts.appendingPathComponent("linked-id"), withDestinationURL: elsewhereA)
    // (2) <id>/home 이 링크
    try FileManager.default.createSymbolicLink(at: accounts.appendingPathComponent("real-id/home"), withDestinationURL: elsewhereB)

    let homes = TokenUsageIncrementalScanner.codexHomes(homeDirectory: home, codexHome: nil)
    #expect(homes.map(\.path) == [home.appendingPathComponent(".codex").path], "링크된 home 이 들어갔다: \(homes.map(\.path))")
    #expect(o315Scan(home: home).usage.codexTotal == 0)
}

// MARK: - 진단 · 압축 쌍둥이

/// 진단 스캐너도 같은 home 목록·같은 별칭 제거를 거쳐 항등식이 선다. filesTotal 은 고유 파일 수다.
@Test
func diagnosticsIdentityHoldsWithOrcaAliases() throws {
    let home = o315TempHome("diag")
    defer { try? FileManager.default.removeItem(at: home) }
    let name = "rollout-2026-07-05T00-00-00-dhl.jsonl"
    let original = home.appendingPathComponent(".codex/sessions/2026/07/05/\(name)")
    o315Write(o315Body([(100, 0), (1_100, 0)]), to: original)
    let alias = o315AccountHome(home, "acct").appendingPathComponent("sessions/2026/07/05/\(name)")
    try FileManager.default.createDirectory(at: alias.deletingLastPathComponent(), withIntermediateDirectories: true)
    #expect(link(original.path, alias.path) == 0)
    o315Write(o315Body([(0, 0), (400, 0)]),
              to: o315AccountHome(home, "acct").appendingPathComponent("sessions/2026/07/06/rollout-2026-07-06T00-00-00-u.jsonl"))

    let production = TokenUsageScanner.scan(homeDirectory: home, now: o315Now)
    let d = CodexUsageDiagnosticsScanner.compute(homeDirectory: home, month: "2026-07", appBuild: 1)
    #expect(production.codexTotal == 1_400)
    #expect(d.dedupTotal + d.dupTokens == production.codexTotal)
    #expect(d.filesTotal == 2, "진단이 별칭까지 셌다: \(d.filesTotal)")
}

/// Orca home 아래 경로의 압축 쌍둥이 후보는 그 home 안에서만 만든다. 그 home 에서 압축된 채 보관된 파일도 기여가 동결된다.
/// 뮤테이션: compressedTwinCandidates 의 쌍 선택을 첫 쌍 고정으로 되돌리면 빨강.
@Test
func compressedTwinCandidatesStayInsideTheOwningOrcaHome() {
    let home = o315TempHome("twins")
    defer { try? FileManager.default.removeItem(at: home) }
    let account = o315AccountHome(home, "acct")
    let name = "rollout-2026-07-05T00-00-00-z.jsonl"
    let live = account.appendingPathComponent("sessions/2026/07/05/\(name)")
    o315Write(o315Body([(300, 0), (4_300, 200)]), to: live)

    let roots = TokenUsageIncrementalScanner.codexRoots(homeDirectory: home, codexHome: nil)
    #expect(TokenUsageIncrementalScanner.compressedTwinCandidates(for: live.path, roots: roots)
            == [live.path + ".zst", account.appendingPathComponent("archived_sessions/\(name).zst").path])
    let archivedName = "rollout-2026-07-06T09-30-00-una.jsonl"
    let archivedLive = account.appendingPathComponent("archived_sessions/\(archivedName)")
    #expect(TokenUsageIncrementalScanner.compressedTwinCandidates(for: archivedLive.path, roots: roots)
            == [archivedLive.path + ".zst", account.appendingPathComponent("sessions/2026/07/06/\(archivedName).zst").path])

    let r1 = o315Scan(home: home)
    #expect(r1.usage.codexTotal == 4_200)
    // 압축 워커가 원본을 지우고, 사용자가 보관 → `.zst` 가 그 home 의 archived_sessions 로.
    try? FileManager.default.removeItem(at: live)
    o315Write("zstd-frame-bytes", to: account.appendingPathComponent("archived_sessions/\(name).zst"))
    let r2 = o315Scan(r1.cache, home: home)
    #expect(r2.usage.codexTotal == 4_200, "Orca home 에서 압축·보관된 파일의 기여가 사라졌다: \(r2.usage.codexTotal)")
}

/// 두 home 에 하드링크된 세션을 **정본 쪽 home 의 Codex 만 압축**하면(원본 삭제 + `.zst`) 옛 정본 상태는 동결 규칙에 걸리고,
/// 다른 home 의 `.jsonl` 은 짝을 잃어 새로 파싱된다. 동결을 남기면 두 배 — 같은 이름을 다른 경로로 읽었으면 동결하지 않는다.
/// 뮤테이션: 정리 규칙의 seenNames 예외를 빼면 빨강(4,600).
@Test
func compressedCanonicalIsNotFrozenWhileItsAliasIsStillLive() throws {
    let home = o315TempHome("zst-alias")
    defer { try? FileManager.default.removeItem(at: home) }
    let name = "rollout-2026-07-05T00-00-00-za.jsonl"
    let original = home.appendingPathComponent(".codex/sessions/2026/07/05/\(name)")
    o315Write(o315Body([(100, 0), (2_100, 300)]), to: original)
    let alias = o315AccountHome(home, "acct").appendingPathComponent("sessions/2026/07/05/\(name)")
    try FileManager.default.createDirectory(at: alias.deletingLastPathComponent(), withIntermediateDirectories: true)
    #expect(link(original.path, alias.path) == 0, "하드링크 픽스처 실패")

    let r1 = o315Scan(home: home)
    #expect(r1.usage.codexTotal == 2_300)
    #expect(r1.cache.codexFileStates.keys.first?.contains("/.codex/sessions/") == true)

    // `~/.codex` 쪽 압축 워커: 원본 링크 삭제 + `.zst`. Orca 쪽 링크는 같은 바이트로 남는다.
    try FileManager.default.removeItem(at: original)
    o315Write("zstd-frame-bytes", to: URL(fileURLWithPath: original.path + ".zst"))

    let r2 = o315Scan(r1.cache, home: home)
    #expect(r2.usage.codexTotal == 2_300, "압축된 정본이 동결된 채 별칭이 새로 파싱돼 두 배가 됐다: \(r2.usage.codexTotal)")
    #expect(r2.cache.codexFileStates.count == 1)
    #expect(r2.cache.codexFileStates.keys.first?.contains("/orca/codex-accounts/") == true)
    #expect(o315Scan(home: home).usage.codexTotal == r2.usage.codexTotal)
}

// MARK: - Claude transcripts

/// `~/.claude/transcripts` 의 assistant usage 도 집계되고, projects 와 같은 (message.id, requestId) 는 한 번만 센다.
/// 오래 남은 transcripts 파일은 완전성 하한(claudeCompleteFrom)을 바꾸지 않는다.
/// 뮤테이션: scanClaude 에서 transcripts 루트를 빼면 빨강 / oldestMtime 을 전체 파일로 되돌리면 빨강.
@Test
func claudeTranscriptsRootIsCountedWithGlobalDedupe() {
    let home = o315TempHome("claude-transcripts")
    defer { try? FileManager.default.removeItem(at: home) }
    let projects = home.appendingPathComponent(".claude/projects/p/s.jsonl")
    let transcripts = home.appendingPathComponent(".claude/transcripts/t.jsonl")
    let oldTranscripts = home.appendingPathComponent(".claude/transcripts/old.jsonl")
    o315Write([
        o315ClaudeLine(id: "m-shared", requestId: "r-shared", input: 5, output: 50)
    ].joined(separator: "\n") + "\n", to: projects)
    o315Write([
        o315ClaudeLine(id: "m-only-transcripts", requestId: "r1", input: 10, output: 20),
        o315ClaudeLine(id: "m-shared", requestId: "r-shared", input: 5, output: 50)
    ].joined(separator: "\n") + "\n", to: transcripts)
    // 40일 전 mtime(12주 창 안, 정리 하한 29일 밖) — 이 파일이 하한 재료가 되면 claudeCompleteFrom 이 비어 있지 않게 된다.
    o315Write(o315ClaudeLine(id: "m-old", requestId: "r-old", input: 1, output: 1) + "\n",
              to: oldTranscripts, modified: o315Now.addingTimeInterval(-40 * 86_400))

    let r = o315Scan(home: home)
    #expect(r.usage.claudeInput == 16, "transcripts 가 안 잡혔거나 중복 계상: input \(r.usage.claudeInput)")
    #expect(r.usage.claudeOutput == 71)
    #expect(r.usage.claudeCompleteFrom == "", "transcripts 파일이 완전성 하한을 바꿨다: \(r.usage.claudeCompleteFrom)")
}
