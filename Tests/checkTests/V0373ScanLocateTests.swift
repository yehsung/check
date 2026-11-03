import Foundation
import Testing
@testable import check
@testable import CheckCore

// MARK: - v0.3.73: 기기마다 Claude·Codex 기록 위치를 스스로 찾는다
//
// 배경(2026-11-03 실사용자 신고): 셸에 `CLAUDE_CONFIG_DIR` 를 건 사람의 Claude Code 기록은 `<그 폴더>/projects` 에 쌓이는데
// 스캐너는 `~/.claude` 만 봐서 그 사람의 Claude 가 통째로 0 이었다. 사람마다 위치가 다를 수 있어 앱이 알려진 자리를 모두 찾는다:
// 로그인 셸의 CLAUDE_CONFIG_DIR · ~/.claude · Orca claude-profiles · Claude 데스크톱 앱 로컬 에이전트 모드.
// 가장 큰 위험은 두 배 집계다 — 이 파일의 절반은 "한 번만 센다"를 지킨다.
//
// 모든 테스트는 임시 홈의 픽스처만 읽는다.

private let s373Now = Date(timeIntervalSince1970: 1_784_000_000)   // KST 2026-07-14 12:33:20

private func s373ISO(_ date: Date) -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    f.timeZone = TimeZone(identifier: "UTC")
    return f.string(from: date)
}

private let s373July5 = Date(timeIntervalSince1970: 1_783_213_200)   // 2026-07-05T01:00:00Z

private func s373TempHome(_ tag: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("check-v0373-\(tag)-\(UUID().uuidString)", isDirectory: true)
}

private func s373Write(_ contents: String, to url: URL) {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? Data(contents.utf8).write(to: url)
    try? FileManager.default.setAttributes([.modificationDate: s373Now], ofItemAtPath: url.path)
}

private func s373Line(id: String, input: Int, output: Int) -> String {
    "{\"type\":\"assistant\",\"timestamp\":\"\(s373ISO(s373July5))\",\"requestId\":\"req-\(id)\","
    + "\"message\":{\"id\":\"\(id)\",\"usage\":{\"input_tokens\":\(input),\"output_tokens\":\(output),"
    + "\"cache_read_input_tokens\":0,\"cache_creation_input_tokens\":0}}}\n"
}

private func s373Scan(_ cache: TokenUsageCache = TokenUsageCache(), home: URL, claudeConfigDir: URL? = nil)
    -> TokenUsageIncrementalScanner.Result {
    TokenUsageIncrementalScanner.update(cache, homeDirectory: home, claudeConfigDir: claudeConfigDir, now: s373Now)
}

private func s373OrcaProfile(_ home: URL, _ id: String) -> URL {
    home.appendingPathComponent("Library/Application Support/orca/claude-profiles/\(id)/home", isDirectory: true)
}

private func s373DesktopSession(_ home: URL, _ session: String) -> URL {
    home.appendingPathComponent(
        "Library/Application Support/Claude/local-agent-mode-sessions/acct/org/\(session)/.claude", isDirectory: true
    )
}

// MARK: - 위치 찾기

/// 셸의 CLAUDE_CONFIG_DIR 아래 projects 가 집계된다(신고 사례 그대로 — ~/.claude 는 비어 있다).
/// 뮤테이션: claudeHomes 에서 claudeConfigDir 를 빼면 0 이 되어 빨강.
@Test
func claudeConfigDirProjectsAreCounted() {
    let home = s373TempHome("config-dir")
    let config = home.appendingPathComponent("workspace/tools/claude", isDirectory: true)
    s373Write(s373Line(id: "m1", input: 10, output: 20), to: config.appendingPathComponent("projects/p/s.jsonl"))
    let r = s373Scan(home: home, claudeConfigDir: config)
    #expect(r.usage.claudeInput == 10)
    #expect(r.usage.claudeOutput == 20)
    #expect(s373Scan(home: home).usage.claudeInput == 0, "설정 폴더를 모르면 0 이어야 한다(픽스처 확인)")
}

/// 설정 폴더와 ~/.claude 에 서로 다른 기록이 있으면 둘 다 더한다(설정을 중간에 바꾼 사람).
@Test
func claudeConfigDirAndDefaultHomeAreBothCounted() {
    let home = s373TempHome("both")
    let config = home.appendingPathComponent("cfg", isDirectory: true)
    s373Write(s373Line(id: "a", input: 1, output: 2), to: config.appendingPathComponent("projects/p/a.jsonl"))
    s373Write(s373Line(id: "b", input: 3, output: 4), to: home.appendingPathComponent(".claude/projects/p/b.jsonl"))
    let r = s373Scan(home: home, claudeConfigDir: config)
    #expect(r.usage.claudeInput == 4)
    #expect(r.usage.claudeOutput == 6)
    #expect(r.stats.claudeHomesFound == 2)
}

/// CLAUDE_CONFIG_DIR 가 ~/.claude 자체(또는 그리로 가는 심볼릭 링크)면 한 번만 센다.
/// 뮤테이션: claudeHomes 의 실제 경로 중복 제거와 scanClaude 의 파일 중복 제거를 함께 빼면 파일 상태가 둘이 된다.
@Test
func claudeConfigDirPointingAtDefaultHomeCountsOnce() throws {
    let home = s373TempHome("same")
    let dotClaude = home.appendingPathComponent(".claude", isDirectory: true)
    s373Write(s373Line(id: "x", input: 5, output: 6), to: dotClaude.appendingPathComponent("projects/p/x.jsonl"))
    let link = home.appendingPathComponent("link-to-claude", isDirectory: true)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: dotClaude)
    for config in [dotClaude, link] {
        let r = s373Scan(home: home, claudeConfigDir: config)
        #expect(r.usage.claudeInput == 5, "두 배 집계: \(r.usage.claudeInput)")
        #expect(r.cache.claudeFileStates.count == 1, "같은 파일을 두 경로로 읽었다: \(r.cache.claudeFileStates.count)")
        #expect(r.stats.claudeHomesFound == 1)
    }
}

/// Orca 계정 폴더: projects 가 진짜 폴더면 집계되고, ~/.claude/projects 로 가는 링크면 한 번만 센다.
@Test
func orcaClaudeProfileRealAndLinkedProjects() throws {
    let home = s373TempHome("orca")
    let dotProjects = home.appendingPathComponent(".claude/projects", isDirectory: true)
    s373Write(s373Line(id: "shared", input: 7, output: 8), to: dotProjects.appendingPathComponent("p/s.jsonl"))
    // 계정 a: 링크(정상 공유) — 같은 파일이 두 경로로 보인다.
    let a = s373OrcaProfile(home, "a")
    try FileManager.default.createDirectory(at: a, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: a.appendingPathComponent("projects"), withDestinationURL: dotProjects)
    // 계정 b: 진짜 폴더(링크 전 판·링크 실패) — 여기에만 있는 기록.
    let b = s373OrcaProfile(home, "b")
    s373Write(s373Line(id: "only-b", input: 100, output: 200), to: b.appendingPathComponent("projects/q/t.jsonl"))
    let r = s373Scan(home: home)
    #expect(r.usage.claudeInput == 107, "Orca 계정 폴더가 빠졌거나 링크로 두 번 셌다: \(r.usage.claudeInput)")
    #expect(r.usage.claudeOutput == 208)
    #expect(r.cache.claudeFileStates.count == 2)
}

/// 같은 기록이 두 위치에 복사본으로 있어도(링크가 아닌 진짜 사본) 엔트리 키로 한 번만 센다.
@Test
func copiedClaudeTranscriptAcrossHomesCountsOnce() {
    let home = s373TempHome("copy")
    let config = home.appendingPathComponent("cfg", isDirectory: true)
    let body = s373Line(id: "dup", input: 11, output: 12)
    s373Write(body, to: config.appendingPathComponent("projects/p/s.jsonl"))
    s373Write(body, to: home.appendingPathComponent(".claude/projects/p/s.jsonl"))
    s373Write(body, to: s373OrcaProfile(home, "z").appendingPathComponent("projects/p/s.jsonl"))
    let r = s373Scan(home: home, claudeConfigDir: config)
    #expect(r.usage.claudeInput == 11, "복사본을 여러 번 셌다: \(r.usage.claudeInput)")
    #expect(r.usage.claudeOutput == 12)
}

/// Claude 데스크톱 앱 로컬 에이전트 모드 기록이 집계된다. 세션 폴더가 심볼릭 링크면 따라가지 않는다.
@Test
func claudeDesktopAgentModeSessionsAreCounted() throws {
    let home = s373TempHome("desktop")
    let session = s373DesktopSession(home, "local_1")
    s373Write(s373Line(id: "d1", input: 9, output: 1), to: session.appendingPathComponent("projects/-sessions-x/s.jsonl"))
    // 링크된 세션 폴더(무관한 트리) — 넣지 않는다.
    let outside = home.appendingPathComponent("elsewhere", isDirectory: true)
    s373Write(s373Line(id: "d2", input: 1000, output: 1000), to: outside.appendingPathComponent(".claude/projects/p/s.jsonl"))
    let org = session.deletingLastPathComponent().deletingLastPathComponent()
    try FileManager.default.createSymbolicLink(at: org.appendingPathComponent("local_linked"), withDestinationURL: outside)
    let r = s373Scan(home: home)
    #expect(r.usage.claudeInput == 9, "데스크톱 세션이 빠졌거나 링크를 따라갔다: \(r.usage.claudeInput)")
}

/// 이어 읽기(두 번째 스캔)에서도 여러 위치가 두 배로 바뀌지 않는다.
@Test
func secondIncrementalScanOverManyHomesDoesNotDouble() throws {
    let home = s373TempHome("incremental")
    let config = home.appendingPathComponent("cfg", isDirectory: true)
    let dotProjects = home.appendingPathComponent(".claude/projects", isDirectory: true)
    s373Write(s373Line(id: "i1", input: 2, output: 3), to: dotProjects.appendingPathComponent("p/s.jsonl"))
    try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: config.appendingPathComponent("projects"), withDestinationURL: dotProjects)
    let first = s373Scan(home: home, claudeConfigDir: config)
    let second = s373Scan(first.cache, home: home, claudeConfigDir: config)
    #expect(first.usage.claudeInput == 2)
    #expect(second.usage.claudeInput == 2, "두 번째 스캔에서 늘었다: \(second.usage.claudeInput)")
    #expect(second.stats.claudeFilesRead == 0, "바뀐 것이 없는데 다시 읽었다")
}

/// 위치 목록 순서·중복 규칙(순수): 설정 폴더 → ~/.claude → Orca(이름순) → 데스크톱. 없는 Orca·데스크톱 폴더는 목록에 없다.
@Test
func claudeHomesOrderAndAbsentFolders() {
    let home = s373TempHome("order")
    let plain = TokenUsageIncrementalScanner.claudeHomes(homeDirectory: home, claudeConfigDir: nil)
    #expect(plain.map(\.lastPathComponent) == [".claude"], "아무것도 없을 때는 종전과 같은 한 곳: \(plain)")
    let config = home.appendingPathComponent("cfg", isDirectory: true)
    try? FileManager.default.createDirectory(at: s373OrcaProfile(home, "b"), withIntermediateDirectories: true)
    try? FileManager.default.createDirectory(at: s373OrcaProfile(home, "a"), withIntermediateDirectories: true)
    try? FileManager.default.createDirectory(at: s373DesktopSession(home, "s"), withIntermediateDirectories: true)
    let all = TokenUsageIncrementalScanner.claudeHomes(homeDirectory: home, claudeConfigDir: config)
    #expect(all.count == 5)
    #expect(all.first?.lastPathComponent == "cfg")
    #expect(all[1].lastPathComponent == ".claude")
    #expect(all[2].deletingLastPathComponent().lastPathComponent == "a")
    #expect(all[3].deletingLastPathComponent().lastPathComponent == "b")
    #expect(all[4].path.contains("local-agent-mode-sessions"))
}

// MARK: - 셸 값

/// 셸 조회 출력의 다섯째 토막이 CLAUDE_CONFIG_DIR 이고, 옛 모양(토막 넷)이면 nil 이다.
@Test
func shellLookupParsesClaudeConfigDir() {
    let marker = CodexAccountUsageProbe.shellLookupMarker
    let fresh = CodexAccountUsageProbe.parseShellLookup(Data("noise\n\(marker)\0/bin\0\0/opt/codex\0/Users/u/cfg\0".utf8))
    #expect(fresh?.claudeConfigDir == "/Users/u/cfg")
    #expect(fresh?.codex == "/opt/codex")
    let legacy = CodexAccountUsageProbe.parseShellLookup(Data("\n\(marker)\0/bin\0/h\0/opt/codex\0".utf8))
    #expect(legacy?.codexHome == "/h")
    #expect(legacy?.claudeConfigDir == nil)
    #expect(CodexAccountUsageProbe.shellLookupScript.contains("CLAUDE_CONFIG_DIR"))
}

/// 이상한 셸 값은 버린다: 빈 값·공백·상대 경로·`~`·루트. 절대 경로는 정규화한다.
@Test
func unusableClaudeConfigDirValuesAreIgnored() {
    for bad in ["", "   ", "relative/dir", "~/x", "/", "/a\nb"] {
        #expect(CodexAccountUsageProbe.usableDirectoryPath(bad) == nil, "받으면 안 되는 값: \(bad)")
    }
    #expect(CodexAccountUsageProbe.usableDirectoryPath(" /Users/u/cfg/ ")?.path == "/Users/u/cfg")
    #expect(CodexAccountUsageProbe.usableDirectoryPath("/Users/u/a/../cfg")?.path == "/Users/u/cfg")
}

/// 대화형 셸 값이 이기고, 대화형에 없으면 로그인 셸 값을 쓴다. 비어 있으면 대화형 재조회를 부른다.
@Test
func claudeConfigDirMergeAndInteractiveRetry() {
    let login = CodexAccountUsageProbe.ShellEnvironment(path: "/bin", codexHome: "/h", codex: "/c", claudeConfigDir: "")
    #expect(CodexAccountUsageProbe.needsInteractiveLookup(login), ".zshrc 에만 둔 값을 놓친다")
    let interactive = CodexAccountUsageProbe.ShellEnvironment(path: nil, codexHome: nil, codex: nil, claudeConfigDir: "/z")
    #expect(CodexAccountUsageProbe.merged(login: login, interactive: interactive).claudeConfigDir == "/z")
    let keep = CodexAccountUsageProbe.ShellEnvironment(path: "/bin", codexHome: "/h", codex: "/c", claudeConfigDir: "/l")
    #expect(CodexAccountUsageProbe.merged(login: keep, interactive: interactive.with(claudeConfigDir: nil)).claudeConfigDir == "/l")
}

/// 성공한 셸 조회는 하루 동안 쓰고, 하루가 지나면 다시 묻는다. 다시 묻다 실패하면 직전 값을 지킨다.
@Test
func shellEnvironmentRefreshesDailyAndKeepsLastGoodOnFailure() async {
    let cache = CodexAccountUsageProbe.LocateCache()
    let calls = CallBox()
    let first = CodexAccountUsageProbe.ShellEnvironment(path: "/bin", codexHome: "/h", codex: "/c", claudeConfigDir: "/one")
    let t0 = Date(timeIntervalSince1970: 2_000_000_000)
    _ = await CodexAccountUsageProbe.resolveShellEnvironment(now: t0, cache: cache, lookup: { _ in calls.bump(); return first })
    #expect(CodexAccountUsageProbe.cachedClaudeConfigDir(cache: cache)?.path == "/one")
    let afterOne = calls.count
    _ = await CodexAccountUsageProbe.resolveShellEnvironment(
        now: t0.addingTimeInterval(3600), cache: cache, lookup: { _ in calls.bump(); return nil }
    )
    #expect(calls.count == afterOne, "하루 안에 다시 셸을 띄웠다")
    let changed = first.with(claudeConfigDir: "/two")
    _ = await CodexAccountUsageProbe.resolveShellEnvironment(
        now: t0.addingTimeInterval(86_401), cache: cache, lookup: { _ in calls.bump(); return changed }
    )
    #expect(CodexAccountUsageProbe.cachedClaudeConfigDir(cache: cache)?.path == "/two", "하루 뒤 바뀐 설정을 못 읽었다")
    _ = await CodexAccountUsageProbe.resolveShellEnvironment(
        now: t0.addingTimeInterval(2 * 86_402), cache: cache, lookup: { _ in calls.bump(); return nil }
    )
    #expect(CodexAccountUsageProbe.cachedClaudeConfigDir(cache: cache)?.path == "/two", "재조회 실패로 기록 위치를 잃었다")
}

private final class CallBox: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    var count: Int { lock.lock(); defer { lock.unlock() }; return n }
    func bump() { lock.lock(); n += 1; lock.unlock() }
}

private extension CodexAccountUsageProbe.ShellEnvironment {
    func with(claudeConfigDir: String?) -> Self {
        var copy = self
        copy.claudeConfigDir = claudeConfigDir
        return copy
    }
}
