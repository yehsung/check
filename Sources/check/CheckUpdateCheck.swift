import Foundation

// MARK: - Semver 비교 (순수 함수)

/// 릴리스 태그("v0.2.1")와 현재 앱 버전("0.2.1")을 비교하는 순수 로직. "v" 접두 허용, 2/3자리 허용.
///
/// 프리릴리스 무시 규칙: "-"(프리릴리스)·"+"(빌드메타) 이후는 절단하고 수치 코어(x.y.z)만 비교한다.
/// 왜: GitHub `/releases/latest` 는 정식 릴리스만 돌려주므로 코어만 있으면 충분하고, 혹 태그에 프리릴리스
/// 꼬리표가 섞여도 "같은 코어면 같은 버전"으로 보수적으로 판정해 프리릴리스로 인한 오탐 넛지를 막는다.
enum SemverCompare {
    /// 비교용 정규화: "v/V" 접두 제거 → "-"/"+" 이후 절단 → "." 분할 → 정수 배열. 숫자가 아니면 nil(파싱 실패).
    static func components(_ raw: String) -> [Int]? {
        var s = raw.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("v") || s.hasPrefix("V") { s.removeFirst() }
        if let dash = s.firstIndex(of: "-") { s = String(s[..<dash]) }
        if let plus = s.firstIndex(of: "+") { s = String(s[..<plus]) }
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty else { return nil }
        var out: [Int] = []
        for p in parts {
            guard let n = Int(p) else { return nil }
            out.append(n)
        }
        return out
    }

    /// latest 가 current 보다 "더 높은" 버전이면 true. 파싱 실패 시 false(조용히 '업데이트 없음' 처리 — 오탐 방지).
    /// 자릿수가 달라도 짧은 쪽을 0 으로 패딩해 비교한다("1.2" == "1.2.0", "0.3" > "0.2.9").
    static func isNewer(_ latest: String, than current: String) -> Bool {
        guard let l = components(latest), let c = components(current) else { return false }
        let n = max(l.count, c.count)
        for i in 0..<n {
            let lv = i < l.count ? l[i] : 0
            let cv = i < c.count ? c[i] : 0
            if lv != cv { return lv > cv }
        }
        return false
    }
}

// MARK: - 업데이트 감지 스토어 (@Observable · 하루 1회 · 실패 조용히)

/// GitHub 최신 릴리스를 현재 앱 버전과 semver 비교해 "업데이트 가용" 여부를 알린다.
///
/// 유휴 0% 불변: 상시 타이머 없음 — 체크는 팝오버 열림 경로(CheckMenuView `.task`)에서만 킥되고, 24h 스로틀로
/// 하루 1회만 네트워크를 친다(무인증 GitHub API 60req/h/IP 보호). 실패는 조용히 무시한다(사용자 방해 금지).
/// 현재버전/페처/시계/영속은 모두 주입 가능해 헤드리스로 결정적 검증한다(테스트는 스텁 페처만 사용, 네트워크 미접촉).
@Observable
@MainActor
final class UpdateCheckStore {
    /// GitHub 최신 릴리스 엔드포인트(정식 릴리스만 반환 — 프리릴리스/드래프트 제외).
    static let latestReleaseURL = URL(string: "https://api.github.com/repos/yehsung/check/releases/latest")!
    /// 감지 스로틀(초). 하루 1회.
    static let checkInterval: TimeInterval = 24 * 60 * 60

    /// 마지막 확인 시각(초, epoch) 영속 키.
    nonisolated static let lastCheckedKey = "check.update.lastCheckedAt"
    /// 캐릭터 말풍선을 이미 띄운 버전 영속 키(버전당 1회 — 도배 금지).
    nonisolated static let bubbleShownKey = "check.update.bubbleShownFor"
    /// 마지막으로 조회한 최신 태그 영속 키(노트와 한 쌍).
    nonisolated static let latestVersionKey = "check.update.latestVersion"
    /// 그 태그의 패치노트 줄들 영속 키(버전과 항상 함께 쓰고 함께 읽는다).
    nonisolated static let latestNotesKey = "check.update.latestNotes"

    /// 배너에 한 번에 보여 줄 패치노트 최대 줄 수(팝오버 높이 보호).
    nonisolated static let maxNotes = 4

    /// 서버가 알려준 최신 태그("v0.2.1"). 아직 확인 전이면 nil. 관찰 대상 — 갱신되면 배너가 다시 그려진다.
    private(set) var latestVersion: String?
    /// 그 버전의 패치노트(표시용 평문 줄, 최대 maxNotes개). 노트 없는 옛 릴리스면 빈 배열 — 배너는 노트 없이 그려진다.
    private(set) var latestNotes: [String] = []

    private let currentVersion: String
    private let fetcher: (URL) async throws -> Data
    private let clock: () -> Date
    private let defaults: UserDefaults
    /// 진행 중 체크 핸들(재진입 가드). 관찰 대상 아님.
    @ObservationIgnored private var checkTask: Task<Void, Never>?

    /// 최신이 현재보다 높으면 true. latestVersion 미확인이면 false(오탐 방지).
    var isUpdateAvailable: Bool {
        guard let latestVersion else { return false }
        return SemverCompare.isNewer(latestVersion, than: currentVersion)
    }

    init(
        currentVersion: String = UpdateCheckStore.bundleShortVersion(),
        fetcher: @escaping (URL) async throws -> Data = UpdateCheckStore.urlSessionFetch,
        clock: @escaping () -> Date = { Date() },
        defaults: UserDefaults = .standard
    ) {
        self.currentVersion = currentVersion
        self.fetcher = fetcher
        self.clock = clock
        self.defaults = defaults
        // 지난 조회 결과(버전+노트)를 복원한다. 24h 스로틀이라 앱을 다시 켠 직후엔 대개 네트워크를 치지 않으므로,
        // 복원이 없으면 배너가 조회한 그날에만 뜨고 재실행 후엔 사라진다. 버전과 노트는 한 쌍으로만 쓰고 쓴다.
        if let stored = defaults.string(forKey: Self.latestVersionKey), !stored.isEmpty {
            latestVersion = stored
            latestNotes = defaults.stringArray(forKey: Self.latestNotesKey) ?? []
        }
    }

    /// 번들 CFBundleShortVersionString(없으면 "0.0.0" — 개발 빌드 등에선 항상 업데이트 가용으로 보이지 않게 최저값).
    static func bundleShortVersion() -> String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.0.0"
    }

    /// 기본 페처: URLSession. 테스트는 스텁을 주입해 네트워크를 건드리지 않는다.
    static func urlSessionFetch(_ url: URL) async throws -> Data {
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, _) = try await URLSession.shared.data(for: req)
        return data
    }

    /// 마지막 확인 시각(영속). 0(미기록)이면 nil.
    private var lastCheckedAt: Date? {
        let t = defaults.double(forKey: Self.lastCheckedKey)
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    /// 24h 스로틀 + 재진입 가드. 신선하면(24h 이내 확인됨) 즉시 반환한다. 아니면 fetch 해 tag_name 을 latestVersion 에 반영.
    /// 실패(네트워크/형식)는 조용히 무시한다(latestVersion 미변경). 스로틀 스탬프는 시도 시점에 찍어(성공/실패 무관)
    /// 팝오버를 하루에 수십 번 열어도 네트워크는 1회만 치게 한다(rate-limit 보호).
    func checkIfStale() async {
        if let checkTask { await checkTask.value; return }
        if let last = lastCheckedAt, clock().timeIntervalSince(last) < Self.checkInterval { return }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performCheck()
        }
        checkTask = task
        await task.value
        checkTask = nil
    }

    private func performCheck() async {
        // 시도 시점에 스로틀 스탬프(성공/실패 무관) — 도배 오픈에도 하루 1회로 제한.
        defaults.set(clock().timeIntervalSince1970, forKey: Self.lastCheckedKey)
        guard let data = try? await fetcher(Self.latestReleaseURL) else { return }
        guard let tag = Self.parseTag(data) else { return }
        latestVersion = tag
        latestNotes = Self.parseNotes(Self.parseBody(data))
        // 버전과 노트를 한 번에 영속(재실행 후에도 같은 배너를 그대로 그린다).
        defaults.set(tag, forKey: Self.latestVersionKey)
        defaults.set(latestNotes, forKey: Self.latestNotesKey)
    }

    /// 릴리스 JSON 디코드 대상. body 는 옵셔널 — 노트 없이 만든 옛 릴리스/필드 누락에도 안전하다.
    private struct Release: Decodable {
        let tag_name: String
        let body: String?
    }

    /// 릴리스 JSON 에서 tag_name 만 뽑는다(실패/빈 값이면 nil — 조용히). 실 API 응답과 필드명이 일치한다(v0.2.1 확인).
    /// 순수 파싱이라 nonisolated — 헤드리스 테스트가 동기로 검증한다.
    nonisolated static func parseTag(_ data: Data) -> String? {
        guard let r = try? JSONDecoder().decode(Release.self, from: data), !r.tag_name.isEmpty else { return nil }
        return r.tag_name
    }

    /// 릴리스 JSON 에서 본문(body)만 뽑는다(없으면 nil). 표시용 정규화는 parseNotes 가 맡는다.
    nonisolated static func parseBody(_ data: Data) -> String? {
        try? JSONDecoder().decode(Release.self, from: data).body
    }

    /// 릴리스 본문을 배너 표시용 줄 배열로 정규화한다(순수 함수).
    ///
    /// 규칙: "- "/"* " 로 시작하는 줄만 항목으로 취하고(헤딩·빈 줄·설치 안내 같은 산문은 버린다), 불릿과
    /// 마크다운 강조 기호(`**`, 백틱)를 떼어 평문으로 만든다. 항목이 maxNotes(4)를 넘으면 앞 3줄만 남기고
    /// 마지막 줄을 "외 N건" 으로 대체한다 — 팝오버 높이를 지키면서 "더 있다"는 사실은 알려 준다.
    nonisolated static func parseNotes(_ body: String?) -> [String] {
        guard let body, !body.isEmpty else { return [] }
        var items: [String] = []
        // isNewline 으로 쪼갠다 — GitHub 본문은 CRLF 인데 Swift 에서 "\r\n" 은 "\n" 과 같지 않은 한 글자라,
        // separator: "\n" 으로 나누면 줄이 하나도 안 갈라진다(항목 0개가 되는 함정).
        for rawLine in body.split(whereSeparator: \.isNewline) {
            var line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix("- ") || line.hasPrefix("* ") else { continue }
            line.removeFirst(2)
            line = line
                .replacingOccurrences(of: "**", with: "")
                .replacingOccurrences(of: "`", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            items.append(line)
        }
        guard items.count > maxNotes else { return items }
        return Array(items.prefix(maxNotes - 1)) + ["외 \(items.count - (maxNotes - 1))건"]
    }

    // MARK: - 캐릭터 말풍선 버전당 1회 (영속 기록)

    /// 실제로 업데이트가 있고, 이 최신 버전에 대해 아직 말풍선을 안 띄웠으면 true.
    func shouldShowBubble() -> Bool {
        guard isUpdateAvailable, let latestVersion else { return false }
        return defaults.string(forKey: Self.bubbleShownKey) != latestVersion
    }

    /// 현재 최신 버전에 대해 말풍선을 띄웠음을 영속 기록(도배 금지 — 다음 새 버전에서만 다시 true).
    func markBubbleShown() {
        guard let latestVersion else { return }
        defaults.set(latestVersion, forKey: Self.bubbleShownKey)
    }
}

// MARK: - 원클릭 업그레이드 실행 (분리 프로세스 · 폴백)

/// `brew upgrade aing-check` 를 원클릭으로 실행한다. brew 경로를 탐지하고, 앱 종료에도 살아남는 분리 프로세스로
/// 업그레이드+재실행을 던진다. brew 미탐지/스폰 실패 시 상태로 알려 배너가 "명령 복사" 폴백을 안내하게 한다.
///
/// 파일 존재 판정/스폰은 주입 가능해(테스트가 파일시스템·프로세스를 건드리지 않게) 상태 전이를 결정적으로 검증한다.
@Observable
@MainActor
final class UpdateRunner {
    /// 실행 상태. running 동안 배너가 "업데이트 중…"을 보여 주고, unavailable/failed 면 명령 복사 폴백을 안내한다.
    enum Status: Equatable { case idle, running, failed, unavailable }
    private(set) var status: Status = .idle

    /// brew 후보 경로(Apple Silicon → Intel 순). nonisolated — nonisolated 스폰 헬퍼에서도 참조한다.
    nonisolated static let brewCandidates = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
    nonisolated static let caskName = "aing-check"
    nonisolated static let appPath = "/Applications/aing-check.app"
    /// 폴백 복사 문자열(사양상 정확히 이 문자열이어야 한다).
    nonisolated static let copyCommand = "brew upgrade aing-check"

    /// brew 실행파일 존재 판정(주입 가능).
    private let fileExists: (String) -> Bool
    /// 분리 프로세스 스폰(주입 가능). 인자는 탐지된 brew 절대경로. 성공하면 true.
    private let spawn: (String) -> Bool

    init(
        fileExists: @escaping (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) },
        spawn: @escaping (String) -> Bool = UpdateRunner.detachedSpawn
    ) {
        self.fileExists = fileExists
        self.spawn = spawn
    }

    /// 탐지된 brew 경로(없으면 nil).
    var brewPath: String? { Self.brewCandidates.first(where: fileExists) }

    /// 원클릭 업그레이드. brew 미탐지 → unavailable, 스폰 실패 → failed, 성공 → running.
    /// running 중 재호출은 무시한다(중복 스폰 금지).
    func runUpgrade() {
        guard status != .running else { return }
        guard let brew = brewPath else {
            status = .unavailable
            return
        }
        status = spawn(brew) ? .running : .failed
    }

    /// 기본 스폰: 앱 종료에도 살아남는 분리 프로세스로 `brew upgrade … && open -a …` 를 띄운다(성공 시 true).
    ///
    /// 왜 nohup/이중 분리: brew cask 의 `quit` 스탠자가 업그레이드 도중 이 앱을 종료시킨다. 그래서 부모(앱)가 죽어도
    /// 명령이 이어지고 끝나면 앱을 다시 열도록, 세션에서 떼어(nohup) 백그라운드(&)로 던진다. 여기선 실행만 하고
    /// 완료를 기다리지 않으므로 UI 를 막지 않는다(Process.run 은 spawn 직후 반환).
    nonisolated static func detachedSpawn(brew: String) -> Bool {
        let inner = "\"\(brew)\" upgrade \(caskName) && open -a \"\(appPath)\""
        let script = "nohup zsh -c '\(inner)' >/dev/null 2>&1 &"
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        proc.arguments = ["-c", script]
        do {
            try proc.run()
            return true
        } catch {
            return false
        }
    }
}
