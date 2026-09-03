import Foundation
import Observation
import os

// MARK: - Codex 계정 사용량 (로컬 `codex app-server` 의 account/usage/read)

/// Codex **계정** 의 일별 토큰 사용량 스냅샷. 로컬 `codex app-server` 에 JSON-RPC `account/usage/read` 를 보내 받는다.
///
/// 왜 필요한가(issue #6): 로컬 rollout 스캔은 보관(`archived_sessions` 로 rename)·압축(7일 지난 rollout 을 `.zst` 로
/// 바꾸고 원본 삭제)에서 이번 달 기여를 잃어 계정 집계보다 46% 적게 나온 사례가 있다. 스캐너의 유실은 v0.2.41 에서
/// 수리했지만(CheckTokenUsage.scanCodex), **이미 `.zst` 만 남은 파일은 어떤 스캐너도 못 읽는다**(macOS SDK 에 zstd 디코더가
/// 없다). 그 구멍을 계정 집계가 메운다 — 서버 보드는 로컬 합과 계정 월합 중 큰 쪽을 쓴다(20260903160000 마이그레이션).
///
/// 값의 성질(실측, codex-cli 0.144.1):
/// - `buckets` 의 날짜는 **UTC 일자**다(로컬 이벤트 델타를 UTC/KST 로 각각 일별 합산해 대조 — UTC 가 3~10% 오차로 일치).
/// - 단위는 input(캐시 포함)+output = 로컬 스캐너의 `codexInput+codexOutput` 과 같은 단위.
/// - 계정 집계는 **다른 기기·Codex 클라우드/IDE 사용까지 포함**한다. 맥 2대가 같은 계정값을 올리므로 서버는 합이 아니라 max 를 쓴다.
/// - 반영 지연이 수십 분 이상이라 실시간은 로컬 집계가 맡고, 이 값은 30분마다 한 번 갱신한다.
///
/// 프라이버시: 여기 담기는 것은 숫자(일별 토큰·누적)와 시각뿐이다. `~/.codex/auth.json` 은 **존재 여부만** 본다(토큰이 들어
/// 있어 내용은 읽지 않는다).
struct CodexAccountUsage: Codable, Equatable, Sendable {
    /// 이 스냅샷을 받은 시각(앱 시계).
    var fetchedAt: Date
    /// 계정 누적 토큰(`summary.lifetimeTokens`). 프로토콜상 null 일 수 있다.
    var lifetimeTokens: Int?
    /// UTC 'YYYY-MM-DD' → 그 날 토큰. 최근 `retentionDays` 일만 보관한다(스냅샷이 UserDefaults 에 영속되므로 무한히 자라지 않게).
    var buckets: [String: Int]

    /// 버킷 보관 일수. 월 롤오버 직후에도 지난달 전체가 남아 있게 두 달을 넉넉히 덮는 70일.
    static let retentionDays = 70

    init(fetchedAt: Date, lifetimeTokens: Int?, buckets: [String: Int]) {
        self.fetchedAt = fetchedAt
        self.lifetimeTokens = lifetimeTokens
        self.buckets = buckets
    }

    /// 'YYYY-MM' 월의 버킷 합(접두어 매칭). 버킷이 UTC 일자라 이 합은 **UTC 월**이고 로컬 집계는 KST 월이다(경계 9시간 차) —
    /// 월간 순위 용도에선 허용한다(스펙 미결 항목으로 문서화).
    func monthTotal(_ month: String) -> Int {
        let prefix = month + "-"
        var sum = 0
        for (day, tokens) in buckets where day.hasPrefix(prefix) { sum += tokens }
        return sum
    }

    /// 가장 최근 버킷 날짜(고정폭 'YYYY-MM-DD' 라 사전식 최대 = 최신). 버킷이 없으면 nil.
    var latestBucketDate: String? { buckets.keys.max() }

    /// 그 월 안에서 가장 최근 버킷 날짜. 툴팁의 "D일까지 반영" 이 쓴다 — 지난달 버킷을 이번 달 반영일로 오인하지 않게 월을 가른다.
    func latestBucketDate(in month: String) -> String? {
        let prefix = month + "-"
        return buckets.keys.filter { $0.hasPrefix(prefix) }.max()
    }

    /// `fetchedAt` 기준 `retentionDays` 일 이전 버킷을 버린 사본. 날짜 문자열이 고정폭이라 컷오프 문자열과의 사전식 비교로 충분하다.
    func pruned() -> CodexAccountUsage {
        let cutoffDate = fetchedAt.addingTimeInterval(-TimeInterval(Self.retentionDays) * 86_400)
        let cutoff = Self.utcDayString(cutoffDate)
        var copy = self
        copy.buckets = buckets.filter { $0.key >= cutoff }
        return copy
    }

    /// Date → UTC 'YYYY-MM-DD'. 버킷 키와 같은 축(UTC)이다.
    static func utcDayString(_ date: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

/// 프로브 결과 상태. 원시값이 서버 컬럼 `token_usage_device_monthly.codex_account_status`(smallint) 에 그대로 올라간다 —
/// 값을 바꾸거나 재배열하지 마라(서버 진단 `token_scan_health()` 가 이 숫자를 읽는다).
enum CodexAccountProbeStatus: Int, Codable, Equatable, Sendable {
    /// 계정 사용량을 받았다.
    case ok = 1
    /// 로그인 셸·폴백 후보 어디에도 `codex` 실행 파일이 없다.
    case codexNotInstalled = 2
    /// `~/.codex/auth.json` 부재(프로세스를 띄우지 않고 판정) 또는 서버가 인증 오류를 돌려줌(API 키 로그인 포함).
    case notLoggedIn = 3
    /// 15초 데드라인 안에 응답이 없어 프로세스를 죽였다.
    case timeout = 4
    /// 그 밖의 실패(응답 없이 종료·파싱 불가·error 응답).
    case failed = 5
}

/// `codex app-server` 를 띄워 `account/usage/read` 를 한 번 묻는 순수+Process 프로브. 상태는 실행 파일 탐색 캐시뿐이다.
///
/// 절대 규칙: 테스트는 `parse(lines:)`·`requestLines(appVersion:)`·`fallbackCandidates(homeDirectory:)`·
/// `candidateToolchains(homeDirectory:shell:)`·`shellLookupScript`·`parseShellLookup`·`drainNonBlocking` 같은 순수 함수와,
/// **주입점을 전부 채운** `fetch(cache:lookup:run:)`/`resolveShellEnvironment(cache:lookup:)` 만 부른다(가짜 러너 = 프로세스 0).
/// 기본 인자의 `fetch`/`run`/`resolveShellEnvironment` 는 실제 프로세스를 띄우므로 프로덕션 러너(`CodexAccountUsageStore.live()`)에서만 쓴다.
enum CodexAccountUsageProbe {
    /// 프로브 실패. status 가 서버에 올라가고 reason 은 로컬 진단용(서버에 보내지 않는다 — 문자열은 어디에도 싣지 않는다).
    struct Failure: Error, Equatable, Sendable {
        var status: CodexAccountProbeStatus
        var reason: String
    }

    /// 찾아낸 실행 파일과, 그것을 띄울 때 넘길 환경. npm 전역 `codex` 는 `#!/usr/bin/env node` 셸 스크립트라 실행 시 PATH 에
    /// node 가 있어야 한다 — 그래서 로그인 셸의 PATH 를 자식 env 에 넘기고, 그 앞에 **실행 파일 자신의 디렉터리**를 둔다
    /// (nvm/volta/bun 은 codex 옆 bin 에 node 가 있다). GUI 앱의 PATH 는 `/usr/bin:/bin:/usr/sbin:/sbin` 뿐이다.
    struct Toolchain: Equatable, Sendable {
        var executable: URL
        var environment: [String: String]
    }

    /// 로그인 셸 조회 결과(PATH · CODEX_HOME · `command -v codex`). 성공하면 프로세스 수명 동안 캐시한다.
    struct ShellEnvironment: Equatable, Sendable {
        var path: String?
        var codexHome: String?
        var codex: String?
    }

    /// 로그인 셸 조회 제한(초). `/bin/zsh -lc` 는 실측 86ms, `-ic` 는 0.5s 지만 느린 dotfile(nvm 초기화 등)을 감안한다.
    nonisolated static let shellLookupTimeout: TimeInterval = 5
    /// 프로세스 총 데드라인(초). 실측 initialize 0.09s + usage 0.77s. 서버 내부 타임아웃 10초보다 길게 둔다.
    nonisolated static let fetchDeadline: TimeInterval = 15
    /// terminate() 뒤 SIGKILL 까지의 유예(초).
    nonisolated static let killGrace: TimeInterval = 2
    /// 실행 파일 탐색 실패·셸 조회 실패의 캐시 수명(초). 성공은 프로세스 수명 동안 캐시한다.
    nonisolated static let locateFailureTTL: TimeInterval = 1800
    /// 한 프로브에서 실행해 보는 후보 수 상한. 실패한 후보는 즉시 종료(exit 127 등)라 값싸지만, 목록이 길어도 무한히 띄우지 않는다.
    nonisolated static let maxCandidateAttempts = 4
    /// `account/usage/read` 요청 id. 응답 줄은 이 id 로만 고른다(초기화 응답·알림 줄이 앞뒤로 섞여 온다).
    nonisolated static let usageRequestID = 2
    /// 셸 조회 출력의 표지. dotfile 이 stdout 에 배너(neofetch·fortune)를 찍어도 마지막 표지 뒤만 읽는다.
    nonisolated static let shellLookupMarker = "@@CHECK-CODEX@@"

    // MARK: 탐색 상태 (프로세스 수명 캐시)

    /// 셸 조회 한 번(대화형 여부 → 결과). 프로덕션은 `/bin/zsh` 를 띄우는 `shellLookup`; 테스트는 고정값을 돌려주는 클로저를 주입한다.
    typealias ShellLookup = @Sendable (_ interactive: Bool) async -> ShellEnvironment?
    /// 툴체인 하나로 프로브 프로세스를 한 번 돌리는 일. 프로덕션은 `runSession`; 테스트는 경로별 canned 결과를 돌려준다(프로세스 0).
    typealias SessionRunner = @Sendable (Toolchain) async -> (result: Result<CodexAccountUsage, Failure>, kind: SessionKind)

    fileprivate struct LocateState {
        /// 로그인 셸 조회 결과(성공 시 프로세스 수명 캐시).
        var shell: ShellEnvironment?
        /// 셸 조회 실패 시각(타임아웃·기동 실패) → `locateFailureTTL` 뒤 재시도.
        var shellFailedAt: Date?
        /// **실행으로 확인된** 툴체인(응답 성공 또는 인증 오류 = 바이너리와 메서드가 살아 있다). 존재만으로는 캐시하지 않는다 —
        /// 리뷰 P1: nvm+zsh 사용자의 npm 셸 스크립트가 node 를 못 찾아 exit 127 로 끝나는데, 존재로 캐시하면 다른 후보(IDE 번들
        /// 네이티브 바이너리)는 영영 시도되지 않고 30분마다 같은 실패를 반복했다.
        var toolchain: Toolchain?
        /// 후보 전부 실패/부재 시각 → `locateFailureTTL` 동안 같은 상태를 돌려준다(프로세스 난사 방지).
        var failedAt: Date?
        var failedStatus: CodexAccountProbeStatus = .failed
    }

    /// 탐색 캐시(프로세스 수명). 프로덕션은 `shared` 하나뿐이고, 테스트는 새 인스턴스로 격리해 `fetch` 의 후보 확정 규칙을
    /// 가짜 러너로 돌린다(전역 하나면 테스트끼리 확정된 툴체인이 새어 순서에 따라 결과가 달라진다).
    final class LocateCache: Sendable {
        fileprivate let state = OSAllocatedUnfairLock(initialState: LocateState())
        static let shared = LocateCache()
        init() {}

        /// 실행으로 확정된 툴체인(없으면 nil). 테스트 관측용.
        var confirmedToolchain: Toolchain? { state.withLock { $0.toolchain } }
        /// 후보 전부 실패/부재가 캐시된 상태(status)와 시각. 테스트 관측용.
        var failure: (status: CodexAccountProbeStatus, at: Date)? {
            state.withLock { s in s.failedAt.map { (s.failedStatus, $0) } }
        }
    }

    /// 로그인 셸에서 `CODEX_HOME` 이 설정돼 있으면 그 경로. **탐색을 새로 하지 않는다** — 이미 캐시된 결과만 돌려주므로
    /// 토큰 스캐너가 이것을 읽어도 셸이 뜨지 않는다(테스트에서 프로세스가 새는 통로를 막는다). 첫 셸 조회 전엔 nil.
    static func cachedCodexHome(cache: LocateCache = .shared) -> URL? {
        cache.state.withLock { $0.shell?.codexHome }.flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }
    }

    /// 로그인 셸의 `CODEX_HOME`(있으면). 셸 조회를 **한 번** 돌려 캐시한다 — 계정 스토어가 auth.json 을 찾기 전에 부른다
    /// (리뷰 P2: CODEX_HOME 사용자는 auth.json 이 `$CODEX_HOME/auth.json` 에 있는데 `~/.codex` 만 보면 영영 '미로그인'이고,
    /// 그러면 프로브가 안 돌아 셸 조회도 안 돌아 스캐너의 CODEX_HOME 지원까지 같이 죽는 순환이었다).
    static func resolveCodexHome(
        now: Date = Date(), cache: LocateCache = .shared, lookup: ShellLookup? = nil
    ) async -> URL? {
        _ = await resolveShellEnvironment(now: now, cache: cache, lookup: lookup)
        return cachedCodexHome(cache: cache)
    }

    /// 프로덕션 셸 조회(`/bin/zsh` 실행). 주입이 없을 때의 기본값.
    private static let liveShellLookup: ShellLookup = { interactive in
        await shellLookup(interactive: interactive, timeout: shellLookupTimeout)
    }

    /// 로그인 셸 조회(캐시). `-lc`(.zprofile) 로 먼저 묻고 **codex 가 안 보이거나 CODEX_HOME 이 비어 있으면** `-ic`(.zshrc —
    /// nvm 초기화도, `export CODEX_HOME=…` 도 대개 여기 있다) 로 한 번 더 묻는다. 둘 다 `shellLookupTimeout` 으로 막고 stdin 은
    /// /dev/null 이라 대화형 dotfile 도 멈추지 않는다. 실패는 `locateFailureTTL` 동안 캐시한다.
    ///
    /// CODEX_HOME 도 재조회 조건인 이유(리뷰 2차 P2): `.zshrc` 에만 CODEX_HOME 을 둔 사용자는 `-lc` 가 codex 를 찾아 버리면 대화형
    /// 조회가 안 돌아 CODEX_HOME 이 영영 빈 채 캐시됐다 — 그러면 계정 스토어가 `~/.codex/auth.json` 만 봐서 '미로그인'이고
    /// 스캐너도 `~/.codex/sessions` 만 읽는다. 비용은 프로세스 수명당 대화형 셸 1회다(성공 결과는 수명 캐시).
    /// 병합 규칙: 세 필드 각각 **비어 있지 않은 쪽**을 쓰되 둘 다 있으면 대화형(실제 사용 환경)이 이긴다 — 로그인 셸이 찾은 codex 를
    /// 대화형이 못 찾았다고 지우지 않는다(옛 코드는 `codex: interactive.codex` 로 덮어써 codex 를 잃었을 것이다).
    static func resolveShellEnvironment(
        now: Date = Date(), cache: LocateCache = .shared, lookup: ShellLookup? = nil
    ) async -> ShellEnvironment? {
        let cached: ShellEnvironment?? = cache.state.withLock { state in
            if let s = state.shell { return .some(s) }
            if let failedAt = state.shellFailedAt, now.timeIntervalSince(failedAt) < locateFailureTTL { return .some(nil) }
            return nil
        }
        if let cached { return cached }
        let lookup = lookup ?? liveShellLookup
        var shell = await lookup(false)
        if needsInteractiveLookup(shell), let interactive = await lookup(true) {
            shell = merged(login: shell, interactive: interactive)
        }
        let resolved = shell
        cache.state.withLock { state in
            state.shell = resolved
            state.shellFailedAt = resolved == nil ? now : nil
        }
        return resolved
    }

    /// 대화형(`-ic`) 재조회가 필요한가(순수): 로그인 셸 결과가 없거나, codex 를 못 찾았거나, CODEX_HOME 이 비어 있을 때.
    static func needsInteractiveLookup(_ login: ShellEnvironment?) -> Bool {
        guard let login else { return true }
        return (login.codex?.isEmpty ?? true) || (login.codexHome?.isEmpty ?? true)
    }

    /// 로그인 셸 결과와 대화형 결과의 병합(순수): 필드별로 비어 있지 않은 쪽, 둘 다 있으면 대화형.
    static func merged(login: ShellEnvironment?, interactive: ShellEnvironment) -> ShellEnvironment {
        func pick(_ a: String?, _ b: String?) -> String? { (a?.isEmpty == false) ? a : b }
        return ShellEnvironment(
            path: pick(interactive.path, login?.path),
            codexHome: pick(interactive.codexHome, login?.codexHome),
            codex: pick(interactive.codex, login?.codex)
        )
    }

    // MARK: 후보 (순수)

    /// 폴백 후보(순서대로): homebrew·/usr/local(네이티브일 가능성이 큼) → **IDE 확장이 번들한 네이티브 바이너리**(이 맥에 실재;
    /// node 가 필요 없다) → npm/volta/bun/local/nvm 의 셸 스크립트(`#!/usr/bin/env node`). 네이티브를 node 심 앞에 두는 이유
    /// (리뷰 P1): node 가 어디에도 없는 맥에선 심이 전부 exit 127 이라 시도 상한(`maxCandidateAttempts`) 안에 네이티브까지 못 간다.
    /// 순수 함수: 존재 여부는 호출측이 본다(테스트는 목록 규칙만 고정한다).
    static func fallbackCandidates(homeDirectory: URL) -> [URL] {
        let home = homeDirectory
        var out: [URL] = [
            URL(fileURLWithPath: "/opt/homebrew/bin/codex"),
            URL(fileURLWithPath: "/usr/local/bin/codex")
        ]
        // IDE 확장 번들: ~/.cursor|.vscode/extensions/openai.chatgpt-*/bin/macos-*/codex (최신 확장 버전부터)
        for ide in [".cursor", ".vscode"] {
            let ext = home.appendingPathComponent("\(ide)/extensions", isDirectory: true)
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: ext.path) else { continue }
            for name in names.filter({ $0.hasPrefix("openai.chatgpt-") }).sorted(by: >) {
                let bin = ext.appendingPathComponent("\(name)/bin", isDirectory: true)
                guard let archs = try? FileManager.default.contentsOfDirectory(atPath: bin.path) else { continue }
                for arch in archs.filter({ $0.hasPrefix("macos-") }).sorted() {
                    out.append(bin.appendingPathComponent("\(arch)/codex"))
                }
            }
        }
        out += [
            home.appendingPathComponent(".npm-global/bin/codex"),
            home.appendingPathComponent(".volta/bin/codex"),
            home.appendingPathComponent(".bun/bin/codex"),
            home.appendingPathComponent(".local/bin/codex")
        ]
        for bin in nvmBinDirectories(homeDirectory: home) {
            out.append(URL(fileURLWithPath: bin).appendingPathComponent("codex"))
        }
        return out
    }

    /// `~/.nvm/versions/node/*/bin` — 최신 node 부터. codex 후보이자 node 탐색 디렉터리다.
    static func nvmBinDirectories(homeDirectory: URL) -> [String] {
        let nvm = homeDirectory.appendingPathComponent(".nvm/versions/node", isDirectory: true)
        guard let versions = try? FileManager.default.contentsOfDirectory(atPath: nvm.path) else { return [] }
        return versions
            .sorted(by: { $0.compare($1, options: .numeric) == .orderedDescending })
            .map { nvm.appendingPathComponent("\($0)/bin", isDirectory: true).path }
    }

    /// `#!/usr/bin/env node` 셸 스크립트가 node 를 찾을 수 있게 PATH 에 덧붙일 디렉터리들(흔한 node 설치 위치 전부).
    /// 리뷰 P1: 옛 목록은 homebrew·/usr/local·volta 뿐이라 nvm·bun 사용자는 exit 127 이었다.
    static func nodeSearchDirectories(homeDirectory: URL) -> [String] {
        let home = homeDirectory
        return ["/opt/homebrew/bin", "/usr/local/bin",
                home.appendingPathComponent(".volta/bin").path,
                home.appendingPathComponent(".bun/bin").path,
                home.appendingPathComponent(".local/bin").path]
            + nvmBinDirectories(homeDirectory: home)
    }

    /// 후보 하나의 실행 환경. PATH = **실행 파일 디렉터리** → 로그인 셸 PATH(없으면 GUI PATH) → node 탐색 디렉터리.
    /// 실행 파일 디렉터리가 맨 앞인 이유: nvm/volta/bun 은 codex 옆 bin 에 짝이 맞는 node 가 있다. 셸 PATH 가 그 다음인 이유:
    /// 사용자가 실제로 쓰는 node 가 거기 있다. 탐색 디렉터리는 둘 다 실패했을 때의 그물이다. 중복은 앞의 것만 남긴다.
    static func environment(
        for executable: URL, homeDirectory: URL, shell: ShellEnvironment?, base: [String: String]
    ) -> [String: String] {
        var environment = base
        let shellPath = shell?.path.flatMap { $0.isEmpty ? nil : $0 } ?? base["PATH"] ?? "/usr/bin:/bin"
        let ordered = [executable.deletingLastPathComponent().path]
            + shellPath.split(separator: ":").map(String.init)
            + nodeSearchDirectories(homeDirectory: homeDirectory)
        var seen = Set<String>()
        environment["PATH"] = ordered.filter { !$0.isEmpty && seen.insert($0).inserted }.joined(separator: ":")
        if let home = shell?.codexHome, !home.isEmpty { environment["CODEX_HOME"] = home }
        return environment
    }

    /// 실행해 볼 툴체인 목록(순서대로): 로그인 셸이 찾은 codex → 폴백 후보 중 **실행 가능한** 것. 같은 경로는 한 번만.
    /// 순수(파일 존재 확인만): 어느 것이 실제로 도는지는 `fetch` 가 실행으로 확정한다.
    static func candidateToolchains(
        homeDirectory: URL, shell: ShellEnvironment?, base: [String: String] = ProcessInfo.processInfo.environment
    ) -> [Toolchain] {
        var urls: [URL] = []
        if let codex = shell?.codex, !codex.isEmpty { urls.append(URL(fileURLWithPath: codex)) }
        urls += fallbackCandidates(homeDirectory: homeDirectory)
        var seen = Set<String>()
        var out: [Toolchain] = []
        for url in urls {
            let path = url.standardizedFileURL.path
            guard seen.insert(path).inserted, FileManager.default.isExecutableFile(atPath: path) else { continue }
            out.append(Toolchain(
                executable: URL(fileURLWithPath: path),
                environment: environment(for: url, homeDirectory: homeDirectory, shell: shell, base: base)
            ))
        }
        return out
    }

    /// 로그인 셸 조회 스크립트. 표지 뒤에 PATH·CODEX_HOME·codex 경로를 NUL 구분으로 찍는다.
    static var shellLookupScript: String {
        "printf '\\n\(shellLookupMarker)\\0%s\\0%s\\0%s\\0' \"$PATH\" \"${CODEX_HOME-}\" \"$(command -v codex 2>/dev/null)\""
    }

    /// 셸 조회 출력 파싱(순수). 마지막 표지 뒤의 NUL 세 토막만 읽는다 — 그 앞은 dotfile 이 찍은 잡음일 수 있다.
    static func parseShellLookup(_ data: Data) -> ShellEnvironment? {
        let text = String(decoding: data, as: UTF8.self)
        guard let marker = text.range(of: shellLookupMarker, options: .backwards) else { return nil }
        let parts = text[marker.upperBound...].split(separator: "\0", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 4 else { return nil }   // parts[0] 은 표지 직후의 빈 조각(첫 NUL 앞)
        return ShellEnvironment(path: parts[1], codexHome: parts[2], codex: parts[3])
    }

    /// 로그인 셸에서 PATH·CODEX_HOME·codex 경로를 뽑는다. 제한 시간 안에 안 끝나면 죽이고 nil. 호출 스레드를 막지 않는다
    /// (리뷰 P2: 옛 구현은 세마포어 + waitUntilExit 로 협력 스레드 풀의 스레드를 5초까지 잠갔다) — ProcessSession 과 같은
    /// 콜백+데드라인 방식이라 타임아웃 시 리더도 함께 회수된다.
    private static func shellLookup(interactive: Bool, timeout: TimeInterval) async -> ShellEnvironment? {
        let session = ProcessSession(
            executable: URL(fileURLWithPath: "/bin/zsh"),
            arguments: [interactive ? "-ic" : "-lc", shellLookupScript],
            environment: nil, currentDirectory: nil, input: nil,
            deadline: timeout, killGrace: 1, lineMatcher: nil
        )
        let outcome = await withCheckedContinuation { (continuation: CheckedContinuation<ProcessSession.Outcome, Never>) in
            session.start { continuation.resume(returning: $0) }
        }
        switch outcome {
        case .responded(let data), .exited(let data):
            return parseShellLookup(data)
        case .timeout, .launchFailed:
            return nil
        }
    }

    // MARK: 요청/응답 (순수)

    /// stdio JSONL 요청 3줄(한 줄 = 한 메시지). initialize(id 1) → initialized 알림 → account/usage/read(id 2).
    static func requestLines(appVersion: String) -> [String] {
        let version = appVersion.replacingOccurrences(of: "\"", with: "")
        return [
            "{\"method\":\"initialize\",\"id\":1,\"params\":{\"clientInfo\":{\"name\":\"aing-check\",\"title\":\"aing-check\",\"version\":\"\(version)\"}}}",
            "{\"method\":\"initialized\",\"params\":{}}",
            "{\"method\":\"account/usage/read\",\"id\":\(usageRequestID)}"
        ]
    }

    /// 응답 줄들을 파싱한다. **`id == requestID` 인 줄만** 쓴다 — 초기화 응답(id 1)·알림(`remoteControl/status/changed` 등)·
    /// 잘린 JSON 이 섞여 와도 무시한다. 그 줄에 `error` 가 있으면 실패(인증 문구면 `.notLoggedIn`), `result` 가 있으면
    /// `summary.lifetimeTokens`(null 허용)와 `dailyUsageBuckets`(null 허용 → 빈 맵)을 읽는다. 해당 줄이 없으면 `.failed`.
    static func parse(lines: [String], requestID: Int = usageRequestID, fetchedAt: Date) -> Result<CodexAccountUsage, Failure> {
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty,
                  let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let id = object["id"] as? NSNumber, id.intValue == requestID
            else { continue }
            if let error = object["error"] {
                let message = (error as? [String: Any])?["message"] as? String ?? String(describing: error)
                let status: CodexAccountProbeStatus =
                    message.range(of: "auth", options: .caseInsensitive) != nil ? .notLoggedIn : .failed
                return .failure(Failure(status: status, reason: message))
            }
            guard let result = object["result"] as? [String: Any] else {
                return .failure(Failure(status: .failed, reason: "result 없음"))
            }
            let summary = result["summary"] as? [String: Any]
            let lifetime = (summary?["lifetimeTokens"] as? NSNumber).map { Int($0.int64Value) }
            var buckets: [String: Int] = [:]
            if let daily = result["dailyUsageBuckets"] as? [[String: Any]] {
                for bucket in daily {
                    guard let day = bucket["startDate"] as? String, day.count >= 10,
                          let tokens = bucket["tokens"] as? NSNumber else { continue }
                    // 고정폭 'YYYY-MM-DD' 접두어만 키로 쓴다(서버가 시각을 붙여 보내더라도 일 단위로 접는다).
                    buckets[String(day.prefix(10)), default: 0] += Int(tokens.int64Value)
                }
            }
            return .success(CodexAccountUsage(fetchedAt: fetchedAt, lifetimeTokens: lifetime, buckets: buckets).pruned())
        }
        return .failure(Failure(status: .failed, reason: "id \(requestID) 응답 줄 없음"))
    }

    /// 이 결과가 툴체인을 **확인**하는가: 성공, 또는 서버가 낸 인증 오류(바이너리가 돌고 메서드도 안다 — 로그인만 안 된 것).
    /// 그 밖의 결과(응답 없이 종료·기동 실패·메서드 모름·잘못된 응답)는 다음 후보를 볼 이유다.
    static func confirmsToolchain(_ result: Result<CodexAccountUsage, Failure>) -> Bool {
        switch result {
        case .success: return true
        case .failure(let f): return f.status == .notLoggedIn
        }
    }

    // MARK: 실행 (Process)

    /// 실행 파일을 찾아 프로브를 한 번 돈다. 프로덕션 러너 전용.
    ///
    /// 후보 확정 규칙(리뷰 P1): 툴체인은 **실행으로** 확정한다. 확인된 툴체인은 프로세스 수명 동안 캐시하되, 그것이 돌지 못하게
    /// 되면(응답 없이 종료·기동 실패 — node 삭제 등) 캐시를 버리고 재탐색한다. 후보는 셸이 찾은 codex → 폴백 순으로
    /// `maxCandidateAttempts` 개까지 실행해 보고, 타임아웃은 환경 문제(네트워크)라 거기서 멈춘다(캐시 없음 — 다음 프로브가 재탐색).
    /// 후보가 하나도 없으면 `.codexNotInstalled`, 전부 실패면 `.failed` 를 `locateFailureTTL` 동안 캐시한다(확정 툴체인을
    /// 폐기한 직후 남은 후보가 0 인 것도 `.failed` — 설치는 돼 있으니까).
    ///
    /// `cache`·`lookup`·`run` 은 테스트 주입점이다(기본값 = 프로덕션: 공유 캐시·`/bin/zsh` 조회·실제 프로세스). 테스트는 새
    /// 캐시 + 고정 셸 환경 + 경로별 canned 결과로 이 확정 규칙만 돌린다 — 프로세스는 뜨지 않는다.
    static func fetch(
        homeDirectory: URL, appVersion: String, now: Date = Date(),
        cache: LocateCache = .shared, lookup: ShellLookup? = nil, run: SessionRunner? = nil
    ) async -> Result<CodexAccountUsage, Failure> {
        let run: SessionRunner = run ?? { toolchain in
            await runSession(toolchain: toolchain, homeDirectory: homeDirectory, appVersion: appVersion, now: now)
        }
        var excluded: URL?
        if let cached = cache.state.withLock({ $0.toolchain }) {
            let (result, kind) = await run(cached)
            switch kind {
            case .responded, .timeout:
                // 응답이 왔으면(오류 응답 포함) 바이너리는 산 것 — 다른 후보를 띄울 이유가 없다.
                return result
            case .exited, .launchFailed:
                cache.state.withLock { $0.toolchain = nil }
                excluded = cached.executable
            }
        }
        if let failure: Failure = cache.state.withLock({ state in
            guard let failedAt = state.failedAt, now.timeIntervalSince(failedAt) < locateFailureTTL else { return nil }
            return Failure(status: state.failedStatus, reason: "탐색 실패 캐시")
        }) {
            return .failure(failure)
        }

        let shell = await resolveShellEnvironment(now: now, cache: cache, lookup: lookup)
        let candidates = candidateToolchains(homeDirectory: homeDirectory, shell: shell)
            .filter { $0.executable != excluded }
        guard !candidates.isEmpty else {
            // 후보 0 의 상태는 **왜 0 인지**로 가른다(리뷰 2차 P2): 방금 확정 툴체인을 폐기해서 비었으면 codex 는 설치돼 있고
            // 돌지 못하는 것(node 삭제 등)이라 `.failed` 다 — `.codexNotInstalled` 로 올리면 서버 진단(token_scan_health)이
            // '미설치'로 오진해 운영자가 엉뚱한 곳을 본다. 애초에 후보가 하나도 없었을 때만 `.codexNotInstalled`.
            let status: CodexAccountProbeStatus = excluded == nil ? .codexNotInstalled : .failed
            cache.state.withLock { $0.failedAt = now; $0.failedStatus = status }
            return .failure(Failure(status: status, reason: excluded == nil ? "codex 실행 파일 없음" : "확정 툴체인 폐기 뒤 남은 후보 없음"))
        }
        var last: Result<CodexAccountUsage, Failure> = .failure(Failure(status: .failed, reason: "후보 없음"))
        for candidate in candidates.prefix(maxCandidateAttempts) {
            let (result, kind) = await run(candidate)
            last = result
            if confirmsToolchain(result) {
                cache.state.withLock { $0.toolchain = candidate; $0.failedAt = nil }
                return result
            }
            if case .timeout = kind { return result }
        }
        cache.state.withLock { $0.failedAt = now; $0.failedStatus = .failed }
        if case .failure = last { return last }
        return .failure(Failure(status: .failed, reason: "후보 전부 실패"))
    }

    /// `codex app-server` 를 띄워 요청 3줄을 쓰고, stdout 을 **비동기로 계속 읽으며**(파이프 버퍼 교착 방지) id 2 응답 줄이
    /// 오면 끝낸다. 총 `fetchDeadline` 뒤 terminate() → `killGrace` 뒤 SIGKILL. stderr 는 /dev/null.
    static func run(
        toolchain: Toolchain, homeDirectory: URL, appVersion: String,
        deadline: TimeInterval = fetchDeadline, killGrace: TimeInterval = killGrace, now: Date = Date()
    ) async -> Result<CodexAccountUsage, Failure> {
        await runSession(toolchain: toolchain, homeDirectory: homeDirectory, appVersion: appVersion,
                         deadline: deadline, killGrace: killGrace, now: now).result
    }

    /// 프로세스가 어떻게 끝났는지. fetch 의 후보 확정이 이것을 본다(파싱 결과만으로는 '기동 실패'와 '메서드 모름'이 안 갈린다).
    enum SessionKind: Sendable { case responded, exited, timeout, launchFailed }

    private static func runSession(
        toolchain: Toolchain, homeDirectory: URL, appVersion: String,
        deadline: TimeInterval = fetchDeadline, killGrace: TimeInterval = killGrace, now: Date
    ) async -> (result: Result<CodexAccountUsage, Failure>, kind: SessionKind) {
        let session = ProcessSession(
            executable: toolchain.executable, arguments: ["app-server"], environment: toolchain.environment,
            currentDirectory: homeDirectory,
            input: Data((requestLines(appVersion: appVersion).joined(separator: "\n") + "\n").utf8),
            deadline: deadline, killGrace: killGrace,
            lineMatcher: { CodexAccountUsageProbe.lineHasUsageResponseID(String(decoding: $0, as: UTF8.self)) }
        )
        let outcome = await withCheckedContinuation { (continuation: CheckedContinuation<ProcessSession.Outcome, Never>) in
            session.start { continuation.resume(returning: $0) }
        }
        switch outcome {
        case .responded(let data):
            return (parse(lines: lines(from: data), fetchedAt: now), .responded)
        case .timeout:
            return (.failure(Failure(status: .timeout, reason: "\(Int(deadline))초 안에 응답 없음")), .timeout)
        case .exited(let data):
            // 응답 없이 끝났어도 그때까지 받은 줄에 답이 있을 수 있다(종료 직전에 흘려보낸 경우).
            let parsed = parse(lines: lines(from: data), fetchedAt: now)
            if confirmsToolchain(parsed) { return (parsed, .responded) }
            return (.failure(Failure(status: .failed, reason: "응답 없이 종료")), .exited)
        case .launchFailed(let reason):
            return (.failure(Failure(status: .failed, reason: reason)), .launchFailed)
        }
    }

    private static func lines(from data: Data) -> [String] {
        data.split(separator: 0x0A, omittingEmptySubsequences: true).map { String(decoding: $0, as: UTF8.self) }
    }

    /// Process/Pipe 를 한 곳에 가두고 잠금으로 상태를 지킨다(Swift 6: Process 는 Sendable 이 아니다).
    /// 완료 콜백은 정확히 한 번 불린다(readability·termination·deadline 어느 쪽이 먼저 오든).
    /// 셸 조회(입력 없음·줄 판정 없음 → 종료까지 기다림)와 codex 프로브(요청 쓰기·id 2 줄에서 조기 종료) 둘 다 이것으로 돈다.
    private final class ProcessSession: @unchecked Sendable {
        enum Outcome: Sendable {
            case responded(Data)
            case exited(Data)
            case timeout
            case launchFailed(String)
        }

        private struct State {
            var received = Data()
            /// 줄 판정을 마친 바이트 수(개행까지). 새 조각이 올 때 그 뒤부터만 본다.
            var scanned = 0
            var finished = false
        }

        private let executable: URL
        private let arguments: [String]
        private let environment: [String: String]?
        private let currentDirectory: URL?
        private let input: Data?
        private let deadline: TimeInterval
        private let killGrace: TimeInterval
        private let lineMatcher: (@Sendable (Data) -> Bool)?
        private let process = Process()
        private let stdin = Pipe()
        private let stdout = Pipe()
        private let state = OSAllocatedUnfairLock(initialState: State())
        private var completion: (@Sendable (Outcome) -> Void)?

        init(
            executable: URL, arguments: [String], environment: [String: String]?, currentDirectory: URL?, input: Data?,
            deadline: TimeInterval, killGrace: TimeInterval, lineMatcher: (@Sendable (Data) -> Bool)?
        ) {
            self.executable = executable
            self.arguments = arguments
            self.environment = environment
            self.currentDirectory = currentDirectory
            self.input = input
            self.deadline = deadline
            self.killGrace = killGrace
            self.lineMatcher = lineMatcher
        }

        func start(_ completion: @escaping @Sendable (Outcome) -> Void) {
            self.completion = completion
            process.executableURL = executable
            process.arguments = arguments
            if let environment { process.environment = environment }
            if let currentDirectory { process.currentDirectoryURL = currentDirectory }
            process.standardInput = input == nil ? FileHandle.nullDevice : stdin
            process.standardOutput = stdout
            process.standardError = FileHandle.nullDevice
            let reader = stdout.fileHandleForReading
            reader.readabilityHandler = { [weak self] handle in
                self?.consume(from: handle)
            }
            process.terminationHandler = { [weak self] _ in
                self?.finishAfterExit()
            }
            do {
                try process.run()
            } catch {
                reader.readabilityHandler = nil
                finish(with: .launchFailed(error.localizedDescription))
                return
            }
            if let input {
                // 요청 줄. 파이프의 읽는 쪽이 먼저 닫히면 write 가 SIGPIPE 로 **우리 프로세스를** 죽인다 — fd 단위로 끈다.
                let writer = stdin.fileHandleForWriting
                _ = fcntl(writer.fileDescriptor, F_SETNOSIGPIPE, 1)
                try? writer.write(contentsOf: input)
            }
            // 총 데드라인. 응답이 먼저 오면 finish 가 이미 끝내 둔 상태라 no-op.
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + deadline) { [weak self] in
                self?.finish(with: .timeout)
            }
        }

        /// stdout 조각을 모은다. 줄 판정자가 있으면 새로 완결된 줄마다 물어 참이면 즉시 끝낸다.
        /// 읽기(availableData)도 잠금 안에서 한다 — 종료 경로의 비차단 드레인과 **순서가 섞이지 않게**(밖에서 읽고 안에서
        /// 붙이면 뒤 조각이 먼저 붙을 수 있고, 셸 조회는 마지막 표지를 찾으므로 순서가 곧 내용이다).
        private func consume(from handle: FileHandle) {
            let done: Data? = state.withLock { s -> Data? in
                guard !s.finished else { return nil }
                let data = handle.availableData
                // 빈 조각 = EOF(프로세스가 stdout 을 닫았다, 종료 직전). terminationHandler 가 마무리한다.
                guard !data.isEmpty else { return nil }
                s.received.append(data)
                guard let lineMatcher else { return nil }
                var matched = false
                while let nl = s.received[s.scanned...].firstIndex(of: 0x0A) {
                    let line = s.received[s.scanned..<nl]
                    s.scanned = nl + 1
                    if !matched, lineMatcher(Data(line)) { matched = true }
                }
                return matched ? s.received : nil
            }
            if let done { finish(with: .responded(done)) }
        }

        /// 종료 이벤트: 아직 안 끝났으면 남은 stdout 을 **비차단으로** 마저 읽고 끝낸다.
        /// 차단 읽기(readToEnd)를 쓰지 않는 이유(리뷰 P2): npm 런처(node codex.js)는 SIGTERM 은 자식(네이티브 codex)에
        /// 전달하지만 SIGKILL 은 전달 못 한다 — 유예 뒤 SIGKILL 이 node 만 죽이면 네이티브 자식이 stdout 파이프를 쥔 채 남고,
        /// 그 EOF 를 기다리는 스레드가 영원히 샌다. 이미 finished 면(타임아웃 경로) 읽지도 않는다. 남은 자식은 stdin EOF 와
        /// (세션 해제로) 닫히는 stdout 파이프에서 스스로 끝난다.
        private func finishAfterExit() {
            let alreadyFinished = state.withLock { $0.finished }
            guard !alreadyFinished else { return }
            let reader = stdout.fileHandleForReading
            reader.readabilityHandler = nil
            let (data, answered): (Data, Bool) = state.withLock { s in
                guard !s.finished else { return (s.received, false) }
                s.received.append(CodexAccountUsageProbe.drainNonBlocking(reader.fileDescriptor))
                var matched = false
                if let lineMatcher {
                    // 마지막 조각(개행이 없을 수도 있다)까지 판정한다.
                    var cursor = s.scanned
                    while cursor < s.received.count {
                        let end = s.received[cursor...].firstIndex(of: 0x0A) ?? s.received.count
                        if lineMatcher(Data(s.received[cursor..<end])) { matched = true }
                        cursor = end + 1
                    }
                    s.scanned = s.received.count
                }
                return (s.received, matched)
            }
            finish(with: answered ? .responded(data) : .exited(data))
        }

        /// 정확히 한 번만 완료한다. 아직 살아 있으면 terminate → killGrace 뒤 SIGKILL. stdin 은 여기서 닫는다.
        private func finish(with outcome: Outcome) {
            let first: Bool = state.withLock { s in
                guard !s.finished else { return false }
                s.finished = true
                return true
            }
            guard first else { return }
            stdout.fileHandleForReading.readabilityHandler = nil
            try? stdin.fileHandleForWriting.close()
            if process.isRunning {
                process.terminate()
                let pid = process.processIdentifier
                // 유예 뒤 SIGKILL. **강한 캡처**다 — 완료 직후 세션이 해제되면 약참조는 nil 이 되어 SIGTERM 을 무시한 프로세스가
                // 영영 남는다. 세션을 2초 더 붙들어 두는 비용뿐이다.
                // pid 하나에만 보낸다(프로세스 그룹 `kill(-pgid)` 는 쓸 수 없다 — Foundation.Process 는 자식을 새 그룹으로 띄우지 않아
                // 그룹 = 우리 앱이다). npm 런처(node)가 SIGTERM 은 네이티브 자식에 넘기지만 SIGKILL 은 못 넘기므로 자식이 고아로
                // 남을 수 있는데, 그 자식은 stdin EOF(위에서 닫음)와 세션 해제로 닫히는 stdout 파이프에서 스스로 끝난다. 그동안
                // 우리 쪽이 그 파이프의 EOF 를 기다리지 않는 것이 finishAfterExit 의 비차단 드레인이다(리뷰 P2).
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + killGrace) {
                    if self.process.isRunning { kill(pid, SIGKILL) }
                }
            }
            let completion = self.completion
            self.completion = nil
            completion?(outcome)
        }
    }

    /// 파이프에서 **지금 있는 만큼만** 읽는다(O_NONBLOCK). 0 = EOF, -1 = EAGAIN/오류 — 어느 쪽이든 더 기다리지 않는다.
    /// 종료 경로의 잔여 드레인이 쓴다(리뷰 P2: 쓰는 쪽 fd 를 물려받은 고아 자식이 남아 있으면 차단 읽기는 영원히 안 돌아온다).
    /// 순수(파일 서술자 하나만 만진다)라 테스트가 파이프로 검증한다.
    static func drainNonBlocking(_ fd: Int32) -> Data {
        let flags = fcntl(fd, F_GETFL)
        if flags >= 0 { _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK) }
        var out = Data()
        var buffer = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let n = buffer.withUnsafeMutableBytes { Darwin.read(fd, $0.baseAddress, $0.count) }
            guard n > 0 else { break }
            out.append(contentsOf: buffer[0..<n])
        }
        return out
    }

    /// 줄이 `"id":2` 응답인지의 값싼 판별(전체 JSON 파싱 전 프리체크). 최종 판정은 parse 가 한다.
    static func lineHasUsageResponseID(_ line: String) -> Bool {
        guard line.contains("\"id\"") else { return false }
        guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              let id = object["id"] as? NSNumber else { return false }
        return id.intValue == usageRequestID
    }
}

// MARK: - 스토어 (@MainActor · 30분 간격 · 영속)

/// 계정 사용량 스냅샷의 갱신 간격·영속·상태를 담당한다. 프로브 실행은 주입된 `runner` 에 위임하므로 테스트는 실제 `codex` 를
/// 절대 띄우지 않는다(`inert()`/러너 주입).
///
/// 게이트 순서(refreshIfDue): 재진입 금지 → 간격(1800초, force 면 무시) → Codex 홈 확정(`codexHome` 주입 — 프로덕션은 로그인
/// 셸의 `CODEX_HOME`, 없으면 `~/.codex`) → 그 아래 `auth.json` 부재면 프로세스 없이 `.notLoggedIn` → 러너.
/// 스탬프(lastProbeAt)는 러너를 부르기 **전에** 찍어 실패도 30분 동안 재시도하지 않는다(난사 방지 —
/// uploadTokenUsageIfNeeded 의 lastTokenUploadAt 과 같은 관용구).
///
/// 영속(UserDefaults `check.codexAccount.snapshot`): 버킷이 날짜별이라 월 롤오버에 안전하다 — 복원 시 월을 따지지 않는다
/// (TokenUsageStore 의 월 일치 게이트와 다른 이유: 저쪽은 '한 달 합' 하나라 달이 바뀌면 의미가 없지만, 이쪽은 `monthTotal(month)` 가
/// 조회 시점에 달을 가른다).
@Observable
@MainActor
final class CodexAccountUsageStore {
    typealias Runner = @Sendable (_ homeDirectory: URL, _ now: Date) async -> Result<CodexAccountUsage, CodexAccountUsageProbe.Failure>
    /// Codex 홈 재정의(nil = `~/.codex`). 프로덕션은 로그인 셸의 `CODEX_HOME` 을 한 번 조회해 캐시한다(셸 프로세스 1회).
    typealias CodexHomeResolver = @Sendable () async -> URL?

    nonisolated static let snapshotKey = "check.codexAccount.snapshot"
    /// 프로브 간격(초). 계정 버킷의 반영 지연이 수십 분이라 더 자주 물어도 새 값이 없다.
    nonisolated static let refreshInterval: TimeInterval = 1800
    /// force 여도 지키는 하한(초). 월 롤오버 판정은 KST 월 경계 창에서 여러 틱 연속 참일 수 있는데(WorkTimerStoreSync 의
    /// refreshTokenUsageInBackgroundIfDue ★ 주석과 같은 경로), 하한이 없으면 30초 틱마다 `codex app-server` 를 띄운다.
    nonisolated static let forcedRefreshFloor: TimeInterval = 60

    /// 마지막으로 받은 계정 스냅샷(실패해도 직전 값을 유지 — 버킷은 날짜별이라 낡아도 틀리지 않는다).
    private(set) var snapshot: CodexAccountUsage?
    /// 마지막 프로브의 상태. 서버 `codex_account_status` 로 올라간다.
    private(set) var lastStatus: CodexAccountProbeStatus?
    /// 마지막 프로브 **시도** 시각(주입 시계). 간격 판정의 기준.
    private(set) var lastProbeAt: Date?
    /// 러너가 불린 횟수(테스트 계측 — auth.json 부재·간격·재진입 가드가 프로세스를 실제로 막는지).
    @ObservationIgnored private(set) var runnerCallCount = 0
    @ObservationIgnored private var inFlight = false

    private let defaults: UserDefaults
    private let homeDirectory: URL
    private let clock: () -> Date
    private let codexHomeResolver: CodexHomeResolver
    private let runner: Runner

    init(
        defaults: UserDefaults,
        homeDirectory: URL,
        clock: @escaping () -> Date = { Date() },
        codexHome: @escaping CodexHomeResolver = { nil },
        runner: @escaping Runner
    ) {
        self.defaults = defaults
        self.homeDirectory = homeDirectory
        self.clock = clock
        self.codexHomeResolver = codexHome
        self.runner = runner
        if let data = defaults.data(forKey: Self.snapshotKey),
           let restored = try? JSONDecoder().decode(CodexAccountUsage.self, from: data) {
            snapshot = restored
        }
    }

    /// 프로덕션 조립: 실홈 + 로그인 셸의 CODEX_HOME + 실제 프로브. **CheckApp 한 곳에서만** 만든다(소스 계약 테스트가 되묻는다).
    static func live(defaults: UserDefaults = .standard) -> CodexAccountUsageStore {
        let version = UpdateCheckStore.bundleShortVersion()
        return CodexAccountUsageStore(
            defaults: defaults,
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser,
            codexHome: { await CodexAccountUsageProbe.resolveCodexHome() },
            runner: { home, now in
                await CodexAccountUsageProbe.fetch(homeDirectory: home, appVersion: version, now: now)
            }
        )
    }

    /// 무해 인스턴스: 존재하지 않는 홈(auth.json 부재 → 러너 미호출)·격리 defaults·호출되면 실패를 돌려주는 러너.
    /// WorkTimerStore 의 기본값이라, 주입을 잊은 테스트가 실제 `codex` 를 띄우는 일이 구조적으로 없다(fail-closed).
    static func inert() -> CodexAccountUsageStore {
        let name = "check.codexAccount.inert.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return CodexAccountUsageStore(
            defaults: defaults,
            homeDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent("check-codex-account-inert-\(UUID().uuidString)", isDirectory: true),
            runner: { _, _ in .failure(.init(status: .codexNotInstalled, reason: "inert")) }
        )
    }

    /// 간격이 찼는지. 진행 중이면 거짓. force 는 1800초 간격을 무시하되 60초 하한은 지킨다.
    func isDue(now: Date, force: Bool = false) -> Bool {
        if inFlight { return false }
        guard let last = lastProbeAt else { return true }
        let elapsed = now.timeIntervalSince(last)
        return force ? elapsed >= Self.forcedRefreshFloor : elapsed >= Self.refreshInterval
    }

    /// 간격(1800초)이 찼을 때만 프로브를 돈다. `force` 는 월 롤오버처럼 '지금 값이 없다'가 이유일 때 쓴다(60초 하한은 유지).
    func refreshIfDue(now: Date, force: Bool = false) async {
        guard isDue(now: now, force: force) else { return }
        lastProbeAt = now
        // 재진입 가드는 홈 확정(await)부터 건다 — 셸 조회를 기다리는 사이 들어온 틱이 두 번째 프로세스를 띄우지 않게.
        inFlight = true
        defer { inFlight = false }
        // Codex 홈: 로그인 셸의 CODEX_HOME 이 있으면 codex 는 auth.json 도 그 아래에 둔다 — `~/.codex` 만 보면 그 사용자는
        // 영영 '미로그인'이다(리뷰 P2). 이 조회가 곧 스캐너의 CODEX_HOME 캐시도 채운다(CodexAccountUsageProbe.cachedCodexHome).
        let codexHome = await codexHomeResolver() ?? homeDirectory.appendingPathComponent(".codex", isDirectory: true)
        // auth.json 이 없으면 로그인 안 된 것 — 프로세스를 띄우지 않는다(파일 내용은 읽지 않는다, 존재 여부만).
        let authPath = codexHome.appendingPathComponent("auth.json").path
        guard FileManager.default.fileExists(atPath: authPath) else {
            lastStatus = .notLoggedIn
            return
        }
        runnerCallCount += 1
        let result = await runner(homeDirectory, now)
        switch result {
        case .success(let usage):
            snapshot = usage
            lastStatus = .ok
            if let data = try? JSONEncoder().encode(usage) {
                defaults.set(data, forKey: Self.snapshotKey)
            }
        case .failure(let failure):
            lastStatus = failure.status
        }
    }
}

// MARK: - 표시 산식 (순수)

/// 내 팝오버 행의 표시 총합. 로컬 6필드 합(`TokenUsageMonthly.total`, 업로드값)은 건드리지 않고, **표시**만
/// `claudeTotal + max(codexTotal, 계정 월합)` 으로 한다 — 서버 보드가 `greatest(codex_local, codex_account)` 로 하는 것과 같은 규칙이라
/// 내 행과 순위판의 내 숫자가 어긋나지 않는다.
enum TokenUsageDisplay {
    static func effectiveTotal(local: TokenUsageMonthly, accountMonth: Int?) -> Int {
        local.claudeTotal + max(local.codexTotal, max(0, accountMonth ?? 0))
    }
}
