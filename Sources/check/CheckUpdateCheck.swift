import AppKit
import Foundation
import CheckCore

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

// MARK: - 업데이트 감지 스토어 (@Observable · 서버 감시 + GitHub 하루 1회 폴백 · 실패 조용히)

/// 새 버전이 나왔는지 알린다. 소스는 둘이다.
///
/// ① **서버 `app_latest_release()`(v0.3.20)** — 릴리스 스크립트가 brew 탭 반영을 원격에서 확인한 **뒤에만** 적는 한 줄.
///    실행 5초 뒤 1회, 이후 300초마다, 깨어난 직후, 팝오버를 열 때(60초 스로틀) 조회한다. 예전엔 소스가 ②뿐이고 그마저
///    팝오버를 열 때만 하루 1회 쳤다 — 아이콘을 안 누르는 사용자는 릴리스를 하루 늦게 알거나 끝내 몰랐다.
///    조회는 jsonb 한 줄이라 5분 주기로도 부담이 없고, 루프는 tolerance 로 타이머 병합을 허용해 유휴 전력을 지킨다.
///    빌드 번호(CFBundleVersion)가 함께 오므로 **양쪽 빌드를 알면 빌드로 비교한다** — 버전 문자열 축은
///    "0.3.01"=="0.3.1" 같은 함정을 이미 겪었다.
/// ② **GitHub `/releases/latest`** — 폴백. 함수가 없는 옛 서버·서버 장애에서도 예전처럼 하루 1회는 안다
///    (24h 스로틀 · 무인증 GitHub API 60req/h/IP 보호). 빌드 ≤71 설치본은 ①을 모르므로 이 경로만 탄다.
///
/// 실패는 두 경로 모두 조용히 무시한다(사용자 방해 금지). 현재버전·빌드/페처/시계/영속/주기는 모두 주입 가능하고,
/// `serverFetcher` 가 nil(기본값)이면 서버 메서드는 전부 no-op 이라 테스트·프리뷰는 네트워크를 건드리지 않는다.
///
/// ## 맥 앱스토어 판(v0.3.51) — 새 버전 안내가 **없다**
/// 앱스토어 앱은 앱스토어로만 업데이트한다(심사 지침 2.4.5(vii)). 그래서 그 판에서 이 스토어는 **서버 공지만** 나른다:
///  · `isUpdateAvailable` 은 언제나 거짓 → 배너·캐릭터 말풍선·메뉴바 점이 전부 꺼진다(셋 다 이 값 하나를 본다).
///  · GitHub 폴링(`latestReleaseURL`·`performCheck`)은 **컴파일되지 않는다**, 서버 `app_latest_release` 응답은 버린다
///    (`applyServerRelease` — 배선도 CheckApp 에서 빠진다).
///  · 공지 조회(`noticeFetcher`)와 그 주기(실행 5초 뒤·5분마다·깨어날 때·팝오버)는 그대로다.
/// 판정은 `edition`(기본값 `MacEdition.current`)이 한다 — 기본 빌드의 테스트가 `.appStore` 를 주입해 이 갈래를 그대로 돌린다.
@Observable
@MainActor
final class UpdateCheckStore {
    #if !CHECK_MAS
    /// GitHub 최신 릴리스 엔드포인트(정식 릴리스만 반환 — 프리릴리스/드래프트 제외).
    static let latestReleaseURL = URL(string: "https://api.github.com/repos/yehsung/check/releases/latest")!
    #endif
    /// 감지 스로틀(초). 하루 1회.
    static let checkInterval: TimeInterval = 24 * 60 * 60
    /// 팝오버 열림 경로의 서버 조회 최소 간격(초). 열었다 닫았다를 반복해도 1분에 1회만 친다.
    /// 감시 루프·깨어남은 이 스로틀을 받지 않는다 — 스스로 드문 경로라, 받으면 실패 뒤 재시도만 한 주기 밀린다.
    static let serverOpenThrottle: TimeInterval = 60
    /// 깨어난 직후 서버 조회 전 대기 기본값(초). didWake 순간엔 Wi-Fi 가 아직 안 붙어 곧장 치면 거의 확실히 실패한다.
    static let defaultWakeSettleDelay: TimeInterval = 10

    /// 마지막 확인 시각(초, epoch) 영속 키.
    nonisolated static let lastCheckedKey = "check.update.lastCheckedAt"
    /// 캐릭터 말풍선을 이미 띄운 버전 영속 키(버전당 1회 — 도배 금지).
    nonisolated static let bubbleShownKey = "check.update.bubbleShownFor"
    /// 마지막으로 조회한 최신 태그 영속 키(노트와 한 쌍).
    nonisolated static let latestVersionKey = "check.update.latestVersion"
    /// 그 태그의 패치노트 줄들 영속 키(버전과 항상 함께 쓰고 함께 읽는다).
    nonisolated static let latestNotesKey = "check.update.latestNotes"
    /// 그 태그의 빌드 번호 영속 키(v0.3.20 — 버전·노트와 한 묶음). 없으면 nil: GitHub 경로만 탄 기록이거나 옛 기록이다.
    nonisolated static let latestBuildKey = "check.update.latestBuild"

    /// 배너에 한 번에 보여 줄 패치노트 최대 줄 수(팝오버 높이 보호).
    nonisolated static let maxNotes = 4

    /// 서버가 알려준 최신 태그("v0.2.1"). 아직 확인 전이면 nil. 관찰 대상 — 갱신되면 배너가 다시 그려진다.
    private(set) var latestVersion: String?
    /// 그 버전의 패치노트(표시용 평문 줄, 최대 maxNotes개). 노트 없는 옛 릴리스면 빈 배열 — 배너는 노트 없이 그려진다.
    private(set) var latestNotes: [String] = []
    /// 그 버전의 빌드 번호(CFBundleVersion). **서버 경로만 채운다** — GitHub 태그엔 빌드가 없다.
    /// GitHub 경로가 **다른** 태그를 적으면 nil 로 내린다: 버전과 빌드가 서로 다른 릴리스를 가리키면 판정이 거짓말을 한다.
    private(set) var latestBuild: Int?

    private let currentVersion: String
    /// 이 앱의 빌드 번호. 못 읽으면 nil 이고, nil 이면 서버 경로는 **침묵**한다(폴백 숫자 금지 — bundleBuild 주석).
    private let currentBuild: Int?
    /// 이 앱의 판(v0.3.51). 앱스토어 판이면 새 버전 안내를 하지 않는다(머리말 '맥 앱스토어 판').
    let edition: MacEdition
    private let fetcher: (URL) async throws -> Data
    private let clock: () -> Date
    private let defaults: UserDefaults
    private let serverWatchInterval: TimeInterval
    private let serverWatchInitialDelay: TimeInterval
    private let wakeSettleDelay: TimeInterval
    /// didWake 를 받을 노티 센터(주입 가능 — 테스트는 격리 센터를 넘겨 실제 워크스페이스 노티를 흔들지 않는다).
    private let workspaceNotifications: NotificationCenter?
    /// 진행 중 체크 핸들(재진입 가드). 관찰 대상 아님.
    @ObservationIgnored private var checkTask: Task<Void, Never>?

    /// 서버 최신 릴리스 조회기. **nil 이면 서버 메서드 전부 no-op**(테스트·프리뷰의 기본값).
    /// 앱은 AppDelegate 가 스토어의 서비스(`fetchLatestRelease`)를 물린다 — 여기서 서비스를 직접 만들면
    /// anon 키 읽기·URLSession 구성이 두 벌이 된다.
    @ObservationIgnored var serverFetcher: (@MainActor () async throws -> AppLatestRelease)?
    /// latestVersion 이 **새 값으로 바뀌었고 그 값이 업데이트일 때** 1회 부른다(두 경로 공통). 같은 값을 다시 확인하면 안 부른다.
    /// 앱은 여기서 캐릭터 말풍선을 즉시 시도한다 — 예전엔 40~80분 졸기 tick 에 편승해서만 떴다.
    @ObservationIgnored var onNewVersionAvailable: (@MainActor (String) -> Void)?
    /// 서버 공지 조회기(v0.3.40). **nil 이면 공지 경로는 no-op**(테스트·프리뷰의 기본값). 릴리스 조회와 **같은 Task 에서
    /// 뒤이어** 부른다 — 새 타이머를 만들지 않는다(무료 플랜 · 사용자 46명 · 이미 5분마다 한 번 여는 연결에 요청 하나를
    /// 더 얹는 것이 전부다). 실행 5초 뒤 · 300초마다 · 깨어남 · 팝오버 열기(60초 스로틀)를 그대로 물려받는다.
    /// 앱은 AppDelegate 가 스토어의 서비스(`appCurrentNotice`)를 물린다(serverFetcher 와 같은 이유로 서비스를 새로 만들지 않는다).
    @ObservationIgnored var noticeFetcher: (@MainActor () async throws -> AppNotice?)?
    /// 공지 조회가 **끝났을 때** 부른다 — "지금 보여 줄 공지가 없다"(nil)도 결과라 부른다. 조회기가 **던지면 부르지 않는다**:
    /// 장애 한 번에 떠 있던 카드를 내리지 않고, 다음 주기가 다시 판정한다. 닫음 표식 판정은 받는 쪽(WorkTimerStore.applyAppNotice)이
    /// 한다 — 이 스토어는 공지를 기억하지 않는다(재실행 5초 뒤 첫 조회가 다시 채우므로 영속할 이유가 없다).
    @ObservationIgnored var onNoticeFetched: (@MainActor (AppNotice?) -> Void)?
    /// 진행 중 서버 조회 핸들(재진입 가드).
    @ObservationIgnored private var serverCheckTask: Task<Void, Never>?
    /// 마지막 서버 조회 **시도** 시각. 영속하지 않는다 — 재실행 직후 조회를 막을 이유가 없고, 이 스로틀은 팝오버 도배 방지용일 뿐이다.
    @ObservationIgnored private var lastServerCheckAt: Date?
    @ObservationIgnored private var serverWatchTask: Task<Void, Never>?
    @ObservationIgnored private var wakeTask: Task<Void, Never>?
    @ObservationIgnored private var wakeObserver: NSObjectProtocol?

    /// 최신이 현재보다 높으면 true. latestVersion 미확인이면 false(오탐 방지).
    /// 빌드를 **양쪽 다** 알면 빌드로만 비교한다 — 버전 문자열 축은 "0.3.01" 과 "0.3.1" 을 같은 값으로 읽는다.
    /// 한쪽이라도 모르면(GitHub 경로 기록 · 옛 기록 · 개발 빌드) 예전 semver 규칙 그대로다.
    /// 앱스토어 판은 **언제나 거짓**이다(v0.3.51) — 배너·말풍선·메뉴바 점이 전부 이 값을 보므로 여기 한 줄이 셋을 함께 끈다.
    var isUpdateAvailable: Bool {
        guard edition.updatesItself else { return false }
        guard let latestVersion else { return false }
        if let latestBuild, let currentBuild { return latestBuild > currentBuild }
        return SemverCompare.isNewer(latestVersion, than: currentVersion)
    }

    init(
        currentVersion: String = UpdateCheckStore.bundleShortVersion(),
        fetcher: @escaping (URL) async throws -> Data = UpdateCheckStore.urlSessionFetch,
        clock: @escaping () -> Date = { Date() },
        defaults: UserDefaults = .standard,
        currentBuild: Int? = UpdateCheckStore.bundleBuild(),
        serverWatchInterval: TimeInterval = 300,
        serverWatchInitialDelay: TimeInterval = 5,
        wakeSettleDelay: TimeInterval = UpdateCheckStore.defaultWakeSettleDelay,
        workspaceNotifications: NotificationCenter? = NSWorkspace.shared.notificationCenter,
        edition: MacEdition = .current
    ) {
        self.currentVersion = currentVersion
        self.currentBuild = currentBuild
        self.edition = edition
        self.fetcher = fetcher
        self.clock = clock
        self.defaults = defaults
        self.serverWatchInterval = serverWatchInterval
        self.serverWatchInitialDelay = serverWatchInitialDelay
        self.wakeSettleDelay = wakeSettleDelay
        self.workspaceNotifications = workspaceNotifications
        // 지난 조회 결과(버전+노트)를 복원한다. 24h 스로틀이라 앱을 다시 켠 직후엔 대개 네트워크를 치지 않으므로,
        // 복원이 없으면 배너가 조회한 그날에만 뜨고 재실행 후엔 사라진다. 버전과 노트는 한 쌍으로만 쓰고 쓴다.
        if let stored = defaults.string(forKey: Self.latestVersionKey), !stored.isEmpty {
            latestVersion = stored
            latestNotes = defaults.stringArray(forKey: Self.latestNotesKey) ?? []
            // 빌드도 같은 묶음으로 복원한다. 키가 없는 옛 기록(빌드 ≤71 이 남긴 것)은 nil — 판정은 예전 semver 그대로 남는다.
            latestBuild = (defaults.object(forKey: Self.latestBuildKey) as? Int).flatMap { $0 > 0 ? $0 : nil }
        }
    }

    /// 번들 CFBundleShortVersionString(없으면 "0.0.0" — 개발 빌드 등에선 항상 업데이트 가용으로 보이지 않게 최저값).
    static func bundleShortVersion() -> String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0.0.0"
    }

    /// 번들 CFBundleVersion(정수, > 0). 못 읽으면 nil — **bundleShortVersion 처럼 폴백 값을 두지 않는다.**
    /// 빌드 비교는 버전 비교를 **대신**하므로, 개발 빌드에서 0 같은 숫자를 쓰면 서버가 아는 모든 릴리스가 "업데이트"가 된다.
    /// 파싱 규칙은 서버 보고와 한 곳을 쓴다(AppVersionReport.fromInfoDictionary — 문자열/숫자 모양 수용, 0·음수 거절).
    nonisolated static func bundleBuild() -> Int? {
        AppVersionReport.fromInfoDictionary(Bundle.main.infoDictionary)?.build
    }

    /// 기본 페처: URLSession. 테스트는 스텁을 주입해 네트워크를 건드리지 않는다.
    /// 맥 앱스토어 판(v0.3.51)에는 GitHub 폴링이 없다 — 이 페처를 부르는 길(`performCheck`)이 컴파일되지 않으므로 늘 던진다.
    static func urlSessionFetch(_ url: URL) async throws -> Data {
        #if CHECK_MAS
        throw URLError(.unsupportedURL)
        #else
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, _) = try await URLSession.shared.data(for: req)
        return data
        #endif
    }

    /// 마지막 확인 시각(영속). 0(미기록)이면 nil.
    private var lastCheckedAt: Date? {
        let t = defaults.double(forKey: Self.lastCheckedKey)
        return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }

    /// 팝오버 열림 경로. **서버를 먼저** 본다(60초 스로틀) — 서버가 이미 알려 준 새 버전이면 GitHub 을 기다릴 이유가 없다.
    ///
    /// 그다음은 예전 그대로다: 24h 스로틀 + 재진입 가드. 신선하면(24h 이내 확인됨) 즉시 반환한다. 아니면 fetch 해 tag_name 을
    /// latestVersion 에 반영. 실패(네트워크/형식)는 조용히 무시한다(latestVersion 미변경). 스로틀 스탬프는 시도 시점에 찍어
    /// (성공/실패 무관) 팝오버를 하루에 수십 번 열어도 네트워크는 1회만 치게 한다(rate-limit 보호).
    ///
    /// 맥 앱스토어 판(v0.3.51)은 **서버 쪽(공지)만** 본다 — GitHub 폴링은 그 판에 컴파일되지 않고, 판정표가 거짓이면
    /// 기본 빌드에서도(테스트가 `.appStore` 를 주입한 경우) GitHub 을 치지 않는다.
    func checkIfStale() async {
        await checkServerNow(minimumInterval: Self.serverOpenThrottle)
        guard edition.updatesItself else { return }
        #if !CHECK_MAS
        if let checkTask { await checkTask.value; return }
        if let last = lastCheckedAt, clock().timeIntervalSince(last) < Self.checkInterval { return }
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.performCheck()
        }
        checkTask = task
        await task.value
        checkTask = nil
        #endif
    }

    #if !CHECK_MAS
    private func performCheck() async {
        // 시도 시점에 스로틀 스탬프(성공/실패 무관) — 도배 오픈에도 하루 1회로 제한.
        defaults.set(clock().timeIntervalSince1970, forKey: Self.lastCheckedKey)
        guard let data = try? await fetcher(Self.latestReleaseURL) else { return }
        guard let tag = Self.parseTag(data) else { return }
        // 빌드는 서버만 안다. GitHub 이 **같은 태그**를 말하면 서버가 준 빌드를 그대로 두고(같은 릴리스다),
        // 다른 태그면 버린다 — 남기면 v0.3.21 태그에 v0.3.20 의 빌드가 붙어 빌드 비교가 엉뚱한 릴리스로 판정한다.
        let build = Self.isSameTag(tag, latestVersion) ? latestBuild : nil
        record(version: tag, notes: Self.parseNotes(Self.parseBody(data)), build: build)
    }
    #endif

    /// 최신 릴리스 기록의 **유일한 쓰기 지점**(두 경로 공통). 버전·노트·빌드를 한 번에 바꾸고 한 번에 영속한 뒤
    /// (재실행 후에도 같은 배너를 그대로 그린다), 버전이 새 값으로 바뀌었고 그게 업데이트면 onNewVersionAvailable 을 1회 부른다.
    /// 쓰기 지점이 경로마다 있으면 언젠가 한쪽이 빌드 키나 콜백을 빠뜨린다 — 그래서 한 곳으로 모았다.
    private func record(version: String, notes: [String], build: Int?) {
        let previous = latestVersion
        latestVersion = version
        latestNotes = notes
        latestBuild = build
        defaults.set(version, forKey: Self.latestVersionKey)
        defaults.set(notes, forKey: Self.latestNotesKey)
        if let build {
            defaults.set(build, forKey: Self.latestBuildKey)
        } else {
            defaults.removeObject(forKey: Self.latestBuildKey)
        }
        // 같은 버전을 5분마다 다시 확인해도 한 번뿐이다(말풍선 자체는 bubbleShownKey 가 따로 버전당 1회를 지킨다).
        guard version != previous, isUpdateAvailable else { return }
        onNewVersionAvailable?(version)
    }

    /// 두 태그가 같은 릴리스인가. 앞의 "v/V" 하나만 무시한다("v0.3.20" == "0.3.20").
    /// 숫자 정규화는 **하지 않는다**("0.3.01" ≠ "0.3.1") — 그 동치가 바로 빌드 축이 피하려는 함정이다.
    nonisolated static func isSameTag(_ tag: String, _ other: String?) -> Bool {
        guard let other else { return false }
        return strippingTagPrefix(tag) == strippingTagPrefix(other)
    }

    nonisolated private static func strippingTagPrefix(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("v") || s.hasPrefix("V") { s.removeFirst() }
        return s
    }

    // MARK: 서버 소스 (app_latest_release · 5분 감시 · 깨어남)

    /// 서버 응답 한 줄을 반영한다. 아래 중 하나라도 어긋나면 **아무것도 바꾸지 않는다**:
    ///  · 계약 버전 v 가 1(또는 누락)이 아니다 — 모르는 모양을 추측해 읽으면 엉뚱한 안내가 나간다,
    ///  · build 가 없거나 0 이하 · version 이 숫자 코어로 안 읽힌다(빈 표 응답 `{"version":null,...}` 포함),
    ///  · 내 빌드를 모른다(개발 빌드) — 모르면 침묵한다.
    /// 통과했고 서버 빌드가 내 빌드보다 **클 때만** 기록한다. 같거나 낮으면 그대로 둔다 — 서버 경로는 절대 지우지 않는다
    /// (지우면 GitHub 경로가 적은 기록까지 날아가고, 업데이트한 뒤엔 어차피 빌드 비교가 false 로 수렴한다).
    ///
    /// 맥 앱스토어 판(v0.3.51)은 **아무것도 기록하지 않는다** — 서버 릴리스 행은 brew·DMG 판이 나간 시각에 게시되므로
    /// 그 판에 알리면 갈 곳 없는 "새 버전"이 된다(앱스토어 심사는 하루 이틀 늦는다).
    func applyServerRelease(_ r: AppLatestRelease) {
        guard edition.updatesItself else { return }
        guard r.v == nil || r.v == 1 else { return }
        guard let build = r.build, build > 0 else { return }
        guard let version = r.version?.trimmingCharacters(in: .whitespaces),
              SemverCompare.components(version) != nil
        else { return }
        guard let currentBuild, build > currentBuild else { return }
        // GitHub tag_name 과 같은 모양("v0.3.20")으로 적는다. 말풍선 1회 기록(bubbleShownKey)이 버전 문자열이라,
        // 모양이 다르면 GitHub 경로가 같은 릴리스를 적는 순간 말풍선이 한 번 더 뜬다.
        record(version: "v" + Self.strippingTagPrefix(version), notes: Self.serverNotes(r.notes ?? []), build: build)
    }

    /// 서버 최신 릴리스(와 공지)를 1회 조회해 반영한다. serverFetcher·noticeFetcher 가 **둘 다** nil 이면 no-op.
    ///
    /// - Parameter minimumInterval: 0 보다 크면 마지막 **시도** 뒤 이 시간이 안 지났을 때 조용히 돌아간다(팝오버 경로 60초).
    ///   감시 루프·깨어남은 0 으로 부른다.
    /// 재진입 가드: 조회가 떠 있으면 새로 치지 않고 그 결과를 기다린다(루프와 팝오버가 같은 순간 겹쳐도 요청 1회).
    /// 스탬프는 시도 시점에 찍고(성공/실패 무관), 실패는 조용히 삼킨다(기록 미변경 — 다음 무스로틀 시도가 곧 다시 친다).
    /// 공지(v0.3.40)는 **같은 Task 안에서 릴리스 뒤에** 부른다 — 스로틀·재진입 가드·주기를 한 벌로 나눠 쓰고, 한쪽의 실패가
    /// 다른 쪽을 막지 않는다(각자 삼킨다).
    func checkServerNow(minimumInterval: TimeInterval = 0) async {
        guard serverFetcher != nil || noticeFetcher != nil else { return }
        if let serverCheckTask { await serverCheckTask.value; return }
        if minimumInterval > 0, let last = lastServerCheckAt,
           clock().timeIntervalSince(last) < minimumInterval {
            return
        }
        lastServerCheckAt = clock()
        let serverFetcher = serverFetcher
        let noticeFetcher = noticeFetcher
        let task = Task { @MainActor [weak self] in
            if let serverFetcher, let release = try? await serverFetcher() {
                self?.applyServerRelease(release)
            }
            guard let noticeFetcher else { return }
            // `try?` 를 쓰지 않는다 — 옵셔널을 돌려주는 식에 `try?` 를 걸면 "던졌다"와 "공지 없음(nil)"이 한 값으로 접혀,
            // 장애 한 번이 떠 있던 카드를 내리게 된다. 던진 것만 삼키고, nil 은 결과로 넘긴다.
            do {
                let notice = try await noticeFetcher()
                self?.onNoticeFetched?(notice)
            } catch {
                // 조용히(사용자 방해 금지) — 다음 주기가 다시 판정한다.
            }
        }
        serverCheckTask = task
        await task.value
        serverCheckTask = nil
    }

    /// 서버 감시를 켠다(멱등 — 앱은 실행당 1회 AppDelegate 가 부른다). serverWatchInitialDelay 뒤 1회,
    /// 이후 serverWatchInterval 마다 조회하고, 깨어남 노티를 구독해 handleWake 로 잇는다.
    ///
    /// **왜 실행 5초 뒤인가**: 로그인 자동 실행 직후엔 네트워크 연결·저장 세션 복구가 겹친다 — 급할 것 없는 조회를
    /// 그 틈에 끼우지 않는다. **왜 300초인가**: 릴리스는 하루 한두 번이라 분 단위 지연은 체감이 없고 요청은 jsonb 한 줄이다.
    /// tolerance(주기의 10%)로 타이머 병합을 허용한다 — 정확한 시각이 의미 없는 조회다.
    func startServerWatch() {
        if serverWatchTask == nil {
            let initialDelay = serverWatchInitialDelay
            let interval = serverWatchInterval
            serverWatchTask = Task { @MainActor [weak self] in
                var delay = initialDelay
                while !Task.isCancelled {
                    // ★ 멈추는 시계(.suspending)로 잔다. 기본 시계는 맥이 잠든 동안에도 흘러서, 덮개를 5분 넘게 닫았다
                    //   열면 이 잠이 **깨는 즉시** 끝나 네트워크가 붙기 전에 조회가 나간다 — 그 순간은 handleWake 가
                    //   settle 뒤에 따로 맡는다. 겹치면 헛조회 한 번에, 매달린 요청이 깨어남 조회를 삼키기까지 한다.
                    try? await Task.sleep(for: .seconds(delay), tolerance: .seconds(delay / 10), clock: .suspending)
                    // 수면 동안 self 를 붙들지 않는다 — 깨어난 뒤에만 잡고, 이번 조회가 끝나면 놓는다.
                    guard let self, !Task.isCancelled else { return }
                    await self.checkServerNow()
                    delay = interval
                }
            }
        }
        if wakeObserver == nil, let workspaceNotifications {
            wakeObserver = workspaceNotifications.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: nil
            ) { [weak self] _ in
                Task { @MainActor in self?.handleWake() }
            }
        }
    }

    /// 서버 감시를 끈다(루프 · 깨어남 대기 · 노티 구독). 이미 떠 있던 조회 1건은 끝까지 간다 — 끊을 이유가 없다.
    func stopServerWatch() {
        serverWatchTask?.cancel()
        serverWatchTask = nil
        wakeTask?.cancel()
        wakeTask = nil
        if let wakeObserver, let workspaceNotifications {
            workspaceNotifications.removeObserver(wakeObserver)
        }
        wakeObserver = nil
    }

    /// 깨어났다 — 덮개를 닫아 둔 동안 나온 릴리스를 다음 5분 tick 까지 기다리지 않고 본다. 다만 didWake 순간엔
    /// 네트워크가 아직 없으므로 wakeSettleDelay(기본 10초) 뒤에 친다. 연달아 깨어나면(덮개 여닫기) 마지막 한 번만 친다.
    func handleWake() {
        wakeTask?.cancel()
        let settle = wakeSettleDelay
        wakeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(settle), tolerance: .seconds(settle / 10))
            guard let self, !Task.isCancelled else { return }
            await self.checkServerNow()
        }
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
            guard let item = plainNoteItem(line) else { continue }
            items.append(item)
        }
        return capNotes(items)
    }

    /// 서버 노트 배열(`app_latest_release.notes`)을 배너 표시용 줄 배열로 정규화한다(순수 함수).
    /// 불릿 판정만 없을 뿐 항목 평문화(plainNoteItem)와 상한(capNotes)은 parseNotes 와 **같은 함수**다 —
    /// 두 경로가 같은 릴리스를 다르게 그리면 배너 노트가 조회 경로에 따라 바뀐다.
    nonisolated static func serverNotes(_ items: [String]) -> [String] {
        capNotes(items.compactMap(plainNoteItem))
    }

    /// 노트 한 항목의 표시용 평문화(두 경로 공통). 마크다운 강조 기호(`**`, 백틱)를 떼고 앞뒤 공백을 걷는다. 비면 nil(버린다).
    nonisolated static func plainNoteItem(_ raw: String) -> String? {
        let line = raw
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "`", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return line.isEmpty ? nil : line
    }

    /// 배너 노트 줄 수 상한 — 두 경로가 쓰는 **유일한** 자르기다. maxNotes(4)를 넘으면 앞 3줄만 남기고 마지막 줄을
    /// "외 N건" 으로 대체한다. GitHub 본문 경로와 서버 배열 경로가 각자 자르면 언젠가 한쪽만 바뀐다.
    nonisolated static func capNotes(_ items: [String]) -> [String] {
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

// MARK: - 교체를 위한 정상 종료 신호 (SIGTERM)

/// DMG 자가 업데이트 스크립트가 보내는 SIGTERM 을 받아 **평소의 종료 절차**로 잇는다.
///
/// **왜 필요한가**: 교체 스크립트는 번들을 갈아치우기 전에 이 앱을 끝내야 한다. 그런데 기본 처분으로 SIGTERM 이
/// 오면 프로세스가 **즉시** 죽어 `applicationShouldTerminate` 가 돌지 않는다 — 근무 중이었다면 열린 세션이
/// 서버에 그대로 남고 하트비트만 끊긴다. 그 상태는 이 저장소가 이미 크게 겪은 사고다(두 맥을 오가다 세션이
/// 갇혀 근무가 통째로 큐에 묶인 일). brew 경로는 cask 의 `uninstall quit:` 스탠자가 **정상** 종료를 보내므로
/// 그 쪽엔 이 문제가 없었다 — DMG 경로만 거친 종료를 쓰면 두 설치 방식의 동작이 어긋난다.
///
/// AppleScript(`tell application id "kingcheck" to quit`)로 보내는 길도 있지만 두 가지가 걸린다: 보내는 쪽이
/// 자동화 권한(TCC) 프롬프트에 걸려 원클릭이 사용자 응답을 기다리며 멈출 수 있고, Apple Event 는 **응답으로**
/// 돌아오므로 프로세스가 실제로 사라졌는지 알려 주지 않는다 — `applicationShouldTerminate` 가 근무중일 때
/// `.terminateLater` 를 돌려주고 최대 3초 서버 왕복을 하는 이 앱에서는, 그 틈에 번들을 바꾸면 종료 절차와 경합한다.
/// 신호 + PID 소멸 확인은 두 문제를 한 번에 없앤다.
///
/// 구현은 기본 처분을 끄고(`SIG_IGN`) 메인 큐의 `DispatchSource` 로 받는 표준 방식이다 —
/// 신호 처리기 안에서 할 수 없는 일(Objective-C 런타임 호출)을 큐로 옮기는 것이 요점이다.
/// 실측: 신호를 보낸 뒤 비동기 마무리까지 끝내고 종료하는 데 600ms, 스크립트의 20초 대기 안에 넉넉히 든다.
///
/// 부수 효과로 **로그아웃·시스템 종료**에서 오는 SIGTERM 에서도 근무 마무리가 돌아간다(그 전엔 즉사했다).
enum GracefulTerminationSignal {
    /// 설치된 신호 소스. 프로세스에 하나뿐이고 메인에서만 건드린다.
    @MainActor private static var source: DispatchSourceSignal?

    /// 멱등 — 실행당 1회 `AppDelegate` 가 부른다. 두 번 불러도 소스는 하나다(두 벌을 달면 종료가 두 번 불린다).
    ///
    /// - Parameter onTerminate: 신호를 받았을 때 할 일. 기본값은 평소 종료(`NSApp.terminate`)이고,
    ///   테스트는 표식을 세우는 클로저를 넘겨 **실제로 신호를 받는지** 확인한다.
    @MainActor
    static func install(
        onTerminate: @escaping @Sendable () -> Void = {
            // 소스를 `.main` 큐에 달았으므로 이 블록은 메인에서 돈다 — 그 사실을 적어 준다
            // (기본 인자 자리는 nonisolated 문맥이라 NSApp 을 그냥 부르면 경고가 난다).
            MainActor.assumeIsolated { NSApp.terminate(nil) }
        }
    ) {
        guard source == nil else { return }
        // 기본 처분을 끄지 않으면 소스를 달기 전에 프로세스가 죽는다.
        signal(SIGTERM, SIG_IGN)
        let s = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        s.setEventHandler(handler: onTerminate)
        s.resume()
        source = s
    }

    /// 테스트 전용 되돌리기 — 소스를 떼고 기본 처분을 복구한다. 스위트가 프로세스 전역 상태를 남기지 않게 한다.
    @MainActor
    static func uninstallForTesting() {
        source?.cancel()
        source = nil
        signal(SIGTERM, SIG_DFL)
    }
}

// MARK: - 자가 업데이트 (brew upgrade · DMG 교체) — 맥 앱스토어 판에는 없다
//
// ★ 여기서부터 파일 끝까지(설치 출처 · 진행 단계 · 원클릭 실행기 · DMG 교체 스크립트)는 맥 앱스토어 판(v0.3.51)에서
//   **통째로 컴파일되지 않는다.** 앱스토어 앱은 앱스토어로만 업데이트하고(심사 지침 2.4.5(vii)), 앱이 끝나도 살아남는
//   분리 프로세스(2.4.5(iii))와 코드 내려받기·설치(2.4.5(iv))는 금지다 — 샌드박스는 어차피 `/Applications` 교체와 brew 실행을
//   막는다. 판정표(`MacEdition.updatesItself`)가 거짓이어도 코드가 남아 있으면 심사관이 바이너리에서 `brew upgrade` 를 본다.
//   `GracefulTerminationSignal`(위)은 남긴다 — 로그아웃·시스템 종료의 SIGTERM 에서도 근무를 마무리한다.
#if !CHECK_MAS

// MARK: - 설치 출처 (brew cask / 직접 설치)

/// 이 앱이 **어떻게 깔렸는가**. 업데이트 방법이 여기서 갈린다.
///
/// `.brew` 는 `brew upgrade --cask` 가 맡고, `.standalone`(DMG 나 zip 으로 직접 설치)은 우리가 새 DMG 를
/// 받아 번들을 갈아치운다. 예전엔 이 구분이 아예 없어서 **brew 가 깔려 있기만 하면** brew 경로를 탔다 —
/// DMG 로 설치하는 사람은 대개 개발자이고 그 맥에는 brew 가 거의 다 있으므로, [지금 업데이트]가
/// `brew upgrade --cask aing-check` 를 불러 "설치되지 않았다"로 끝나고 배너는 600초 뒤 실패로 떨어졌다.
/// brew 가 **없는** DMG 사용자는 그보다 더 나빴다 — "brew 명령을 복사해 실행하세요"라는 쓸 수 없는 안내를 받았다.
enum InstallSource: Equatable { case brew, standalone }

// MARK: - 업데이트 진행 단계 (스크립트 → 앱)

/// DMG 자가 업데이트 스크립트가 상태 파일에 남기는 단계. **배너가 "업데이트 중…" 한 줄로 굳지 않게 하는 유일한 통로다.**
///
/// 왜 필요한가: brew 경로는 실패 사유가 사실상 하나("업그레이드가 안 일어났다")라 뭉뚱그린 한 문장으로 버텼다.
/// DMG 경로는 사유가 많고(오프라인 · 자산 없음 · 검증 실패 · 권한 · 용량 · 교체 실패) 각각 **다른 조치**를 요구한다.
/// 게다가 30MB 를 받는 동안은 몇 분이 걸릴 수 있어, 표식이 없으면 사용자는 멈춘 것과 구별할 수 없다 —
/// 이 앱은 이미 "배너가 업데이트 중으로 굳었다"는 실사용 신고를 받은 적이 있다.
/// 오프라인은 1초에 판정되는데 표식이 없으면 600초를 기다려야 한다.
enum UpdateStage: String, Equatable, Sendable {
    /// 시작했다(아직 네트워크를 치기 전).
    case start
    /// 내려받는 중.
    case download
    /// 받은 것을 검증하는 중(공증 · 신원 · 버전).
    case verify
    /// 설치할 자리 옆에 사본을 만드는 중.
    case staging
    /// 앱 종료를 기다리는 중.
    case quit
    /// 번들을 바꾸는 중.
    case swap
    /// 끝났다(곧 새 앱이 뜬다).
    case done

    /// 배너 제목에 그대로 쓰는 사용자용 문구. 진행률(%)은 쓰지 않는다 —
    /// 총량을 알려면 요청을 한 번 더 쳐야 하고, "무엇을 하는 중인지"만으로도 멈춤과 진행이 갈린다.
    var userText: String {
        switch self {
        case .start, .download: return "새 버전을 받는 중…"
        case .verify: return "받은 파일을 확인하는 중…"
        case .staging: return "설치를 준비하는 중…"
        case .quit, .swap, .done: return "앱을 바꾸는 중…"
        }
    }
}

/// 상태 파일에서 읽어 낸 현재 상황. 단계와 실패 단계는 **함께** 올 수 없다(실패하면 스크립트가 끝난다).
struct UpdateProgress: Equatable, Sendable {
    let stage: UpdateStage?
    /// 실패한 단계 이름(`error=<단계>` 로 적힌다). 있으면 즉시 실패로 본다 — 600초를 기다리지 않는다.
    let failedStep: String?

    static let unknown = UpdateProgress(stage: nil, failedStep: nil)

    /// 상태 파일 내용에서 **마지막** 뜻있는 줄을 읽는다(순수 함수 — 테스트가 동기로 검증한다).
    ///
    /// 스크립트는 줄을 **덧붙이기만** 한다(`>>`). 그래야 중간에 죽어도 어디까지 갔는지 남고, 쓰기가 한 줄이라
    /// 반쯤 쓰인 줄을 읽을 틈이 거의 없다. 모르는 줄은 조용히 버린다 — 스크립트가 나중에 줄을 더 적어도
    /// 옛 앱이 깨지지 않게(열거값 확장 함정과 같은 이유).
    static func parse(_ raw: String?) -> UpdateProgress {
        guard let raw else { return .unknown }
        var stage: UpdateStage?
        var failed: String?
        for line in raw.split(whereSeparator: \.isNewline) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if let v = t.droppingPrefix("stage=") {
                // 모르는 단계 이름은 무시하고 직전 단계를 지키다 — 앞으로 단계가 늘어도 옛 앱이 "모름"으로 되돌지 않게.
                if let s = UpdateStage(rawValue: v) { stage = s }
            } else if let v = t.droppingPrefix("error=") {
                // `error=<단계> code=<n>` 모양이라 첫 토막만 쓴다.
                failed = v.split(separator: " ").first.map(String.init)
            }
        }
        // 실패가 적혀 있으면 그게 결론이다(단계는 실패 직전 것이라 안내에 쓰지 않는다).
        return UpdateProgress(stage: failed == nil ? stage : nil, failedStep: failed)
    }

    /// 실패 단계 → 사용자에게 보여 줄 한 문장. 모르는 단계면 nil(배너가 뭉뚱그린 기본 문구를 쓴다).
    ///
    /// 왜 단계마다 다른 문장인가: 사유마다 **할 일이 다르다**. 오프라인은 연결을 고치면 되고, 권한은 관리자
    /// 계정이 필요하고, "이미 최신"은 아무것도 할 필요가 없다. 예전 한 문장("업데이트가 진행되지 않았어요 —
    /// 아래 명령을 복사해 실행하세요")은 brew 경로에선 통했지만 DMG 경로의 아홉 가지 사유를 전부 뭉갰고,
    /// 게다가 쓸 수 없는 brew 명령을 권했다.
    ///
    /// nil 을 돌려주는 길을 남기는 이유는 **옛 앱 보호**다 — 스크립트가 나중에 단계를 더 적어도, 그 이름을
    /// 모르는 설치본이 빈 안내를 내지 않고 기본 문구로 떨어진다. 대신 `dmgUpdateScript` 가 쓰는 단계는
    /// 하나도 빠짐없이 여기 있어야 하고, 그 사실을 소스 계약 테스트가 스크립트에서 이름을 긁어 되묻는다.
    static func userMessage(forFailedStep step: String) -> String? {
        switch step {
        case "download":
            return "새 버전을 받지 못했어요 — 인터넷 연결을 확인해 주세요"
        // 검증 계열은 사용자가 할 수 있는 일이 없다. 중요한 것은 **설치하지 않았다**는 사실을 알리는 것이다.
        case "image", "dmg-notary", "notary", "identity", "content", "build-unreadable", "staged-verify":
            return "받은 파일을 믿을 수 없어서 설치하지 않았어요 — 잠시 뒤 다시 시도해 주세요"
        case "swapped-verify":
            return "설치 직후 확인이 어긋나 원래 버전으로 되돌렸어요 — 잠시 뒤 다시 시도해 주세요"
        case "not-newer":
            return "이미 최신 버전이에요"
        case "permission":
            return "응용 프로그램 폴더에 쓸 권한이 없어요 — 아래에서 받아 직접 덮어써 주세요"
        case "copy":
            return "저장 공간이 부족할 수 있어요 — 공간을 확보한 뒤 다시 시도해 주세요"
        case "busy", "lock":
            return "이미 업데이트가 진행 중이에요 — 잠시 기다려 주세요"
        case "mount":
            return "받은 파일을 열지 못했어요 — 잠시 뒤 다시 시도해 주세요"
        case "swap", "swap-aside":
            return "앱을 바꾸지 못했어요 — 아래에서 받아 직접 덮어써 주세요"
        default:
            return nil
        }
    }
}

private extension String {
    /// 접두가 맞으면 그 뒤를, 아니면 nil. `hasPrefix` + `dropFirst` 두 줄을 한 자리로 모은다.
    func droppingPrefix(_ p: String) -> String? {
        hasPrefix(p) ? String(dropFirst(p.count)) : nil
    }
}

// MARK: - 원클릭 업그레이드 실행 (분리 프로세스 · 폴백)

/// 원클릭 업데이트를 실행한다. 설치 출처를 먼저 가려(`installSource`) brew 가 **이 번들을** 관리하면
/// `brew upgrade --cask` 를, 직접 깔린 번들이면 **새 DMG 를 받아 번들을 교체**하는 분리 프로세스를 던진다.
/// 어느 쪽도 쓸 수 없으면 상태로 알려 배너가 출처에 맞는 폴백을 안내하게 한다.
///
/// 파일/폴더 판정 · 심링크 해소 · 쓰기 권한 · 번들 경로 · PID · 내 build · 상태 파일 읽기 · 스폰 · 대기가
/// 모두 주입 가능해(테스트가 파일시스템·프로세스·네트워크를 건드리지 않게) 상태 전이와 **실제로 던지는
/// 스크립트 문자열**을 결정적으로 검증한다.
@Observable
@MainActor
final class UpdateRunner {
    /// 실행 상태. running 동안 배너가 진행 문구를 보여 주고, unavailable/failed 면 폴백을 안내한다.
    enum Status: Equatable { case idle, running, failed, unavailable }
    private(set) var status: Status = .idle

    /// DMG 경로가 상태 파일에서 읽어 낸 현재 진행(brew 경로는 늘 `.unknown`). 관찰 대상 — 배너가 다시 그려진다.
    private(set) var progress: UpdateProgress = .unknown

    /// brew 접두사 후보(Apple Silicon → Intel 순). **`bin/brew` 와 `Caskroom` 은 같은 접두사에서 짝으로 봐야 한다** —
    /// Caskroom 위치는 `HOMEBREW_PREFIX` 에 묶여 있어 사용자가 옮길 수 없다(실측: `brew --caskroom` → `/opt/homebrew/Caskroom`,
    /// `HOMEBREW_CASK_OPTS` 의 `--appdir` 은 앱 자리만 바꾸고 Caskroom 은 못 바꾼다). 두 값을 따로 고르면
    /// ARM 맥에 Rosetta Intel brew 가 함께 깔린 경우처럼 "brew 는 /opt/homebrew, 설치 기록은 /usr/local" 짝이 나와
    /// 엉뚱한 brew 에게 엉뚱한 설치를 올리라고 시킨다.
    ///
    /// **알려진 한계**: brew 를 비표준 접두사(예: `~/homebrew`)에 깐 사람은 두 후보에 걸리지 않아 `.standalone` 이 된다.
    /// 그러면 brew 가 관리하는 번들을 DMG 로 덮어쓰게 되는데, 앱 자체는 **올바르게** 갱신되고 brew 기록만 낡는다
    /// (다음 `brew upgrade --cask` 가 스스로 맞춘다). 로그인 셸을 띄워 `brew --prefix` 를 묻는 길도 있지만,
    /// GUI 앱의 PATH 에는 사용자 셸 설정이 없어 `zsh -lc` 로 프로파일을 읽어야 하고 그건 느리고 깨지기 쉽다.
    /// brew 자신이 비표준 접두사를 cask 에 대해 지원하지 않으므로 이 한계를 받아들인다.
    nonisolated static let brewPrefixCandidates = ["/opt/homebrew", "/usr/local"]
    /// brew 실행파일 후보. **접두사 후보에서 파생한다** — 두 목록을 따로 적으면 언젠가 어긋나고 짝 판정이 무너진다.
    /// nonisolated — nonisolated 스폰 헬퍼에서도 참조한다.
    nonisolated static let brewCandidates = brewPrefixCandidates.map { "\($0)/bin/brew" }
    nonisolated static let caskName = "aing-check"
    nonisolated static let appPath = "/Applications/aing-check.app"
    /// 폴백 복사 문자열. **원클릭이 실제로 실행하는 명령과 같아야 한다** — 예전엔 `brew upgrade aing-check` 였는데,
    /// 그 명령은 탭이 낡았을 때 조용히 "이미 최신"으로 끝나 사용자가 손으로 실행해도 똑같이 실패했다.
    nonisolated static let copyCommand = "brew update && brew upgrade --cask aing-check"

    /// 늘 **최신** DMG 를 가리키는 주소. 릴리스 스크립트가 태그마다 같은 이름으로 자산을 올린다
    /// (`scripts/release-brew.sh`). 문서·랜딩 페이지도 같은 주소를 쓴다.
    ///
    /// 태그를 박은 주소(`releases/download/<태그>/…`)로 바꾸는 길도 검토했으나 채택하지 않았다:
    /// `SKIP_DMG=1` 로 낸 릴리스에는 자산이 아예 없어 **태그를 박아도 404 다**(모양만 바뀐다). 그 창에서
    /// 잘못된 것을 설치하는 위험은 아래 build 결박이 막고, 404 는 상태 파일이 "자산이 아직 없다"로 즉시 알린다.
    nonisolated static let dmgURL = "https://github.com/yehsung/check/releases/latest/download/aing-check.dmg"

    /// 내려받은 앱이 **우리 앱인지** 못박는 코드 서명 지정 요구사항.
    ///
    /// **왜 `spctl` 만으로는 안 되는가(실측)**: `spctl --assess --type execute` 는 "애플이 공증했고 신뢰할 수 있다"만
    /// 본다 — Xcode·Google Chrome·Mail 이 전부 `accepted`(종료코드 0)로 통과한다. 즉 공격자가 **자기 Developer ID 로
    /// 공증한** 앱을 내려주면 그것도 통과한다. 팀 ID(MQ2KQK37WD)와 번들 id(kingcheck)를 못박는 이 요구사항만이
    /// 신원 관문이고, 같은 실측에서 위 세 앱은 모두 거절됐다(그리고 번들 안 파일 하나를 고친 우리 앱도 거절됐다).
    ///
    /// **거꾸로 이 요구사항만으로도 안 된다(실측)**: Developer ID 로 서명했지만 **공증하지 않은** 번들은
    /// `codesign --verify -R` 을 통과한다. 공증을 강제하는 것은 `spctl` 쪽이므로 **둘 다** 봐야 한다.
    nonisolated static let codeRequirement =
        "anchor apple generic and identifier \"kingcheck\" and certificate leaf[subject.OU] = MQ2KQK37WD"

    /// running 감시 시한(초). 이 시간이 지나도 여전히 running 이면 실패로 본다.
    ///
    /// 왜 필요한가: 업데이트가 **실제로 일어나면** 앱이 종료되므로(brew 경로는 cask 의 `uninstall quit:`,
    /// DMG 경로는 우리 스크립트의 SIGTERM) 이 감시는 발화할 기회가 없다. 즉 감시가 발화했다는 것은
    /// "명령은 떴는데 업데이트가 일어나지 않았다"는 뜻이다. 예전엔 running 을 벗어나는 경로가 **하나도 없어서**
    /// 그 경우 배너가 "업데이트 중…"으로 영원히 굳고 버튼도 비활성이라 재시도조차 못 했다(실사용 신고).
    ///
    /// **왜 150초가 아니라 600초인가**: 이 수리가 앞세운 `brew update` 는 탭이 몇 주 낡았거나 회선이 느리면
    /// 단독으로도 150초를 넘긴다(git fetch + 수천 formula 재인덱싱). 150초이던 시절엔 **정상 진행 중인** 업그레이드를
    /// 실패로 판정해 배너가 재시도를 열었고, 사용자가 다시 누르면 두 번째 brew 가 같은 락을 다퉈 둘 다 깨졌다.
    ///
    /// DMG 경로는 이 시한에 **의존하지 않는다** — 상태 파일이 단계와 실패를 알려 주므로 오프라인은 1초에,
    /// 자산 없음은 즉시 판정된다. 여기서 이 시한은 "스크립트가 말없이 사라진" 경우의 마지막 그물일 뿐이다.
    nonisolated static let watchdogSeconds: Double = 600

    /// DMG 내려받기 제한 시간(초). **`--retry` 를 쓰지 않는다** — `man curl` 에 따르면 `--max-time` 은 전송마다
    /// 리셋되므로 `--retry 3 --max-time 420` 의 최악은 4배가 되어 감시 시한을 넘긴다. 실패하면 사용자가 다시 누른다.
    /// 28.5MB 를 420초에 받으려면 약 70KB/s 면 되고, 그보다 느리면 어차피 끝까지 못 간다.
    nonisolated static let dmgDownloadTimeoutSeconds = 420

    /// 상태 파일을 다시 읽는 간격(초). DMG 경로에서만 돈다(brew 경로는 예전처럼 한 번 자고 판정한다).
    nonisolated static let progressPollSeconds: Double = 1

    /// 스크립트가 단계를 적는 상태 파일. 로그와 **따로** 둔다 — 로그는 사람이 읽는 덧붙임 파일이고
    /// 이 파일은 앱이 파싱하는 짧은 표식이라, 섞으면 로그 한 줄이 늘 때마다 파싱이 흔들린다.
    ///
    /// 자리는 `~/Library/Caches/kingcheck/` 안이다 — cask 의 `zap trash:` 목록에 그 폴더가 있어
    /// `brew uninstall --zap` 이 함께 지운다(바깥에 두면 지워지지 않는 잔재가 된다).
    nonisolated static let statePath =
        NSString(string: "~/Library/Caches/kingcheck/update.state").expandingTildeInPath

    /// brew 실행파일 존재 판정(주입 가능).
    private let fileExists: (String) -> Bool
    /// 폴더 안 항목 이름들(주입 가능). Caskroom 의 버전 폴더를 훑는 데만 쓴다. 읽을 수 없으면 빈 배열.
    private let directoryContents: (String) -> [String]
    /// 경로의 심링크를 걷어 실제 자리로 정규화(주입 가능). "brew 가 관리하는 번들이 곧 내 번들인가"를
    /// 비교하는 **유일한 수단**이라 주입 지점을 남긴다 — 안 그러면 테스트가 실제 심링크를 만들어야 한다.
    private let resolvePath: (String) -> String
    /// 이 자리에 쓸 수 있는가(주입 가능). **번들의 부모 폴더**를 묻는다 — 교체는 그 폴더 안에서
    /// 이름을 바꾸는 일이므로 번들 자체의 권한이 아니라 부모의 권한이 관문이다.
    private let isWritable: (String) -> Bool
    /// 지금 돌고 있는 이 앱의 번들 경로(주입 가능). **하드코딩된 `appPath` 를 쓰지 않는다** —
    /// DMG 사용자는 앱을 `~/Applications` 나 다른 자리에 끌어다 놓을 수 있고, 그러면 교체가 엉뚱한 곳을 노린다.
    private let bundlePath: String
    /// 이 앱의 PID(주입 가능). 스크립트가 교체 직전에 이 PID 에 SIGTERM 을 보내고 사라질 때까지 기다린다.
    private let processID: Int32
    /// 이 앱의 build 번호(주입 가능). 받은 DMG 의 build 가 이보다 **커야만** 설치한다(다운그레이드 차단).
    /// 모르면(개발 빌드) 0 으로 넘겨 어떤 build 든 통과시킨다 — 폴백 숫자를 지어내지 않는다는 규칙과 같다.
    private let currentBuild: Int?
    /// 상태 파일 읽기(주입 가능). 없으면 nil.
    private let readState: (String) -> String?
    /// 상태 파일 지우기(주입 가능). 스폰 **직전에** 부른다 — 지난 시도의 실패 표식을 읽고
    /// 누르자마자 거짓 실패를 띄우는 창을 없앤다.
    private let clearState: (String) -> Void
    /// brew 분리 프로세스 스폰(주입 가능). 인자는 탐지된 brew 절대경로. 성공하면 true.
    private let spawn: (String) -> Bool
    /// DMG 분리 프로세스 스폰(주입 가능). 성공하면 true.
    private let spawnDMG: (DMGUpdatePlan) -> Bool
    /// 감시 대기(주입 가능). 테스트가 600초를 실제로 자지 않게 한다.
    private let watchdogSleep: @Sendable (Double) async -> Void
    @ObservationIgnored private var watchdogTask: Task<Void, Never>?

    init(
        fileExists: @escaping (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) },
        directoryContents: @escaping (String) -> [String] = { UpdateRunner.contentsOfDirectory($0) },
        resolvePath: @escaping (String) -> String = { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path },
        isWritable: @escaping (String) -> Bool = { FileManager.default.isWritableFile(atPath: $0) },
        bundlePath: String = Bundle.main.bundlePath,
        processID: Int32 = ProcessInfo.processInfo.processIdentifier,
        currentBuild: Int? = UpdateCheckStore.bundleBuild(),
        readState: @escaping (String) -> String? = { try? String(contentsOfFile: $0, encoding: .utf8) },
        clearState: @escaping (String) -> Void = { try? FileManager.default.removeItem(atPath: $0) },
        spawn: @escaping (String) -> Bool = UpdateRunner.detachedSpawn,
        spawnDMG: @escaping (DMGUpdatePlan) -> Bool = UpdateRunner.detachedSpawnDMG,
        watchdogSleep: @escaping @Sendable (Double) async -> Void = { try? await Task.sleep(for: .seconds($0)) }
    ) {
        self.fileExists = fileExists
        self.directoryContents = directoryContents
        self.resolvePath = resolvePath
        self.isWritable = isWritable
        self.bundlePath = bundlePath
        self.processID = processID
        self.currentBuild = currentBuild
        self.readState = readState
        self.clearState = clearState
        self.spawn = spawn
        self.spawnDMG = spawnDMG
        self.watchdogSleep = watchdogSleep
    }

    /// 폴더 안 항목 이름들(기본 `directoryContents`). 읽을 수 없으면 빈 배열 — 없는 Caskroom 과 같게 취급한다.
    nonisolated static func contentsOfDirectory(_ path: String) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []
    }

    /// **이 번들을** 관리하는 brew 설치의 접두사(없으면 nil).
    ///
    /// Caskroom 폴더가 있는지만 보면 **안 된다**. 실측: brew 는 앱을 `appdir` 로 옮기고 Caskroom 에는 심링크만 남긴다 —
    /// `/opt/homebrew/Caskroom/aing-check/0.3.48/aing-check/aing-check.app → /Applications/aing-check.app`.
    /// 즉 Caskroom 의 존재는 "brew 가 이 기기의 **어떤** 사본을 관리한다"까지만 말한다.
    ///
    /// 그 차이가 조용한 영구 실패를 만든다: brew 로 `/Applications` 에 깔아 쓰던 사람이 DMG 를 받아 `~/Applications`
    /// 에 두고 그쪽을 실행하면, 폴더 존재만 보는 판정은 `.brew` 라 답하고 `brew upgrade --cask` 는 **돌고 있지 않은
    /// 사본**을 올린다. 돌고 있는 앱은 영원히 안 바뀌는데 배너는 같은 새 버전을 계속 권한다.
    ///
    /// 그래서 심링크를 걷어 **지금 돌고 있는 번들과 같은 자리를 가리킬 때만** `.brew` 로 본다. 확신이 없으면
    /// `.standalone` 으로 떨어뜨린다 — 두 오판의 피해가 대칭이 아니다. 거짓 `.standalone` 은 DMG 로 **올바르게**
    /// 갱신되고 brew 기록만 낡는다(다음 `brew upgrade` 가 스스로 맞춘다). 거짓 `.brew` 는 아무것도 안 바뀐다.
    var managingBrewPrefix: String? {
        let destination = destinationPath
        return Self.brewPrefixCandidates.first { prefix in
            guard fileExists("\(prefix)/bin/brew") else { return false }
            return stagedBundlePaths(caskroom: "\(prefix)/Caskroom/\(Self.caskName)")
                .contains { resolvePath($0) == destination }
        }
    }

    /// Caskroom 안에서 "설치된 앱"을 가리키는 자리들(버전 폴더마다). 숨김 항목(`.metadata`)은 건너뛴다.
    ///
    /// 두 모양을 다 본다 — 지금 cask 는 `app "aing-check/aing-check.app"`(배포 zip 안에 폴더가 한 겹 있다)라
    /// 중간에 폴더가 끼지만, 스탠자가 `app "aing-check.app"` 로 단순해지면 버전 폴더 바로 아래가 된다.
    /// 한 모양만 보면 그때 판정이 **조용히** `.standalone` 으로 기울어 brew 사용자가 DMG 경로를 타게 된다.
    private func stagedBundlePaths(caskroom: String) -> [String] {
        directoryContents(caskroom)
            .filter { !$0.hasPrefix(".") }
            .flatMap { version in
                [
                    "\(caskroom)/\(version)/\(Self.caskName)/\(Self.caskName).app",
                    "\(caskroom)/\(version)/\(Self.caskName).app",
                ]
            }
    }

    /// 이 번들을 관리하는 brew 실행파일 경로(없으면 nil). 접두사와 **짝으로** 나온다.
    var brewPath: String? { managingBrewPrefix.map { "\($0)/bin/brew" } }

    /// 설치 출처. brew 가 **이 번들을** 관리할 때만 `.brew` 다(`managingBrewPrefix` 주석).
    var installSource: InstallSource { managingBrewPrefix == nil ? .standalone : .brew }

    /// 교체할 번들의 경로. 심링크를 걷어 실제 자리로 정규화한다 — 심링크를 그대로 교체하면 링크를 번들로
    /// 덮어써 원본이 남고, `open` 은 새 앱을 띄우지만 다음 업데이트는 다시 옛 자리를 본다.
    var destinationPath: String { resolvePath(bundlePath) }

    /// 내 build 번호를 아는가. 모르면(개발 빌드 — `CFBundleVersion` 이 없다) 자가 업데이트를 하지 않는다.
    /// 배너가 "권한이 없어요" 같은 엉뚱한 사유를 말하지 않도록 바깥에서도 볼 수 있게 열어 둔다.
    var hasKnownBuild: Bool { currentBuild != nil }

    /// 이 번들을 교체할 수 있는가. 부모 폴더에 쓸 수 있어야 한다.
    ///
    /// 왜 스크립트가 아니라 여기서 보는가: 권한이 없으면 스크립트는 28.5MB 를 **다 받은 뒤** 복사 단계에서야
    /// 실패한다(실측). 미리 보면 버튼을 누른 즉시 "권한이 없다"고 말할 수 있다. 스크립트에도 같은 판정이
    /// 남아 있다 — 받는 동안 권한이 바뀌는 경우까지 막는 2차 방어다.
    var canReplaceBundle: Bool {
        isWritable(URL(fileURLWithPath: destinationPath).deletingLastPathComponent().path)
    }

    /// 앱 번들이 **DMG 안이나 App Translocation 자리에서** 돌고 있는가. 그러면 교체할 '설치본'이 없다.
    ///
    /// DMG 를 열고 응용 프로그램 폴더로 끌어다 놓지 않은 채 바로 실행하면 macOS 가 번들을 읽기 전용 임시 자리로
    /// 옮겨 띄운다(App Translocation). 그 경로를 교체 대상으로 쓰면 임시 사본을 갈아치우고 끝나므로,
    /// 다음 실행이면 사라진다 — 사용자는 업데이트가 됐다고 믿지만 아무것도 바뀌지 않는다.
    /// DMG 배포에서 가장 흔한 사용 오류가 '끌어놓지 않고 바로 두 번 클릭' 이므로 이 판정이 실제로 자주 걸린다.
    var isRunningFromReadOnlyLocation: Bool {
        let p = destinationPath
        return p.hasPrefix("/Volumes/")
            || p.contains("/AppTranslocation/")
            || p.hasPrefix("/private/var/folders/")
    }

    /// 원클릭 업데이트. 출처에 따라 갈린다.
    ///
    /// `.brew`  — 스폰 실패 → failed, 성공 → running(+600초 감시). 예전과 **동작이 같다**.
    /// `.standalone` — 읽기 전용 자리에서 돌거나 번들을 교체할 권한이 없으면 **스폰하지 않고** unavailable
    ///                (배너가 옮기라고/직접 받으라고 안내한다). 그 밖엔 DMG 스크립트를 던지고 상태 파일을 지켜본다.
    /// running 중 재호출은 무시한다(중복 스폰 금지).
    @discardableResult
    func runUpgrade() -> Task<Void, Never>? {
        guard status != .running else { return nil }
        let source = installSource
        switch source {
        case .brew:
            guard let brew = brewPath else {
                status = .unavailable
                return nil
            }
            guard spawn(brew) else {
                status = .failed
                return nil
            }
        case .standalone:
            // 교체할 설치본이 없거나 쓸 수 없으면 받아 봐야 버린다 — 28.5MB 를 받기 전에 멈춘다.
            // 내 build 를 모르면(개발 빌드) 계획이 nil 이라 여기서 멈춘다 — `dmgUpdatePlan()` 주석.
            guard !isRunningFromReadOnlyLocation, canReplaceBundle, let plan = dmgUpdatePlan() else {
                status = .unavailable
                return nil
            }
            // ── 수리: 스폰 **직전에** 지난 시도의 상태 파일을 지운다.
            // 스크립트도 첫 줄에서 비우지만 그건 zsh 가 뜬 **뒤**다. 러너는 1초 뒤 첫 폴링을 하므로
            // 그 틈에 지난주의 `error=download` 를 읽으면 누르자마자 거짓 실패 문구가 뜬다.
            clearState(Self.statePath)
            guard spawnDMG(plan) else {
                status = .failed
                return nil
            }
        }
        progress = .unknown
        status = .running
        watchdogTask?.cancel()
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.watch(source)
        }
        watchdogTask = task
        return task
    }

    /// running 을 지켜본다. brew 는 예전 그대로 한 번 자고 판정하고, DMG 는 상태 파일을 짧은 간격으로 읽는다.
    ///
    /// 왜 갈라 두는가: brew 경로는 표식을 남기지 않으므로 폴링이 아무것도 못 읽고 600번 헛깨어난다.
    /// 그리고 그 경로의 동작은 실전에서 잘 돌고 있어 바꿀 이유가 없다.
    private func watch(_ source: InstallSource) async {
        switch source {
        case .brew:
            await watchdogSleep(Self.watchdogSeconds)
            guard !Task.isCancelled, status == .running else { return }
            // 여기 도달 = 앱이 살아 있는데 시한이 지났다 = 업데이트가 일어나지 않았다.
            // failed 로 내려 배너가 폴백 안내와 함께 재시도를 허용하게 한다.
            status = .failed
        case .standalone:
            var elapsed = 0.0
            while elapsed < Self.watchdogSeconds {
                await watchdogSleep(Self.progressPollSeconds)
                elapsed += Self.progressPollSeconds
                guard !Task.isCancelled, status == .running else { return }
                let p = UpdateProgress.parse(readState(Self.statePath))
                progress = p
                // 실패가 적혀 있으면 **즉시** 내려간다 — 오프라인은 1초에 판정되는데 600초를 기다릴 이유가 없다.
                if p.failedStep != nil {
                    status = .failed
                    return
                }
                // 교체가 끝났으면 곧 이 앱이 죽고 새 앱이 뜬다. 더 볼 것이 없다.
                if p.stage == .done { return }
            }
            guard !Task.isCancelled, status == .running else { return }
            status = .failed
        }
    }

    /// 이번 실행이 던질 DMG 업데이트 한 벌. 테스트가 이 값을 그대로 본다.
    ///
    /// 인자 순서는 스크립트의 `$1`…`$6` 과 **한 자리씩 대응**한다. 순서를 바꾸면 경로에 URL 이 들어가는 식으로
    /// 조용히 어긋나므로, 테스트가 각 자리의 뜻을 글자로 못박는다.
    /// **내 build 를 모르면 nil 이다.** 그때는 자가 업데이트를 하지 않는다.
    ///
    /// 왜 `?? 0` 으로 때우지 않는가: 0 을 넘기면 스크립트의 `GOT_BUILD > MIN_BUILD` 비교가 **아무 build 든**
    /// 통과시켜 다운그레이드 차단이 통째로 꺼진다. 그리고 이건 이론이 아니다 — 실측으로 테스트 호스트 번들
    /// (`checkPackageTests.xctest`)에는 `CFBundleVersion` 이 **없어서** `currentBuild` 가 늘 nil 이다.
    /// `?? 0` 을 두면 `spawnDMG` 를 안 박은 테스트가 실제 스크립트를 띄워 아무 build 나 받아 테스트 번들을
    /// 갈아치울 수 있었다. 폴백 숫자를 두지 않는 규칙은 `bundleBuild()` 주석과 같다.
    func dmgUpdatePlan() -> DMGUpdatePlan? {
        guard let currentBuild else { return nil }
        return DMGUpdatePlan(
            script: Self.dmgUpdateScript,
            arguments: [
                "aing-check-update",
                Self.dmgUpdateScript,
                destinationPath,
                Self.dmgURL,
                String(processID),
                Self.codeRequirement,
                String(currentBuild),
                Self.statePath,
                Self.logPath,
            ]
        )
    }

    /// 기본 스폰: 앱 종료에도 살아남는 분리 프로세스로 `brew update && brew upgrade --cask … && open -a …` 를 띄운다.
    ///
    /// 왜 nohup/이중 분리: brew cask 의 `quit` 스탠자가 업그레이드 도중 이 앱을 종료시킨다. 그래서 부모(앱)가 죽어도
    /// 명령이 이어지고 끝나면 앱을 다시 열도록, 세션에서 떼어(nohup) 백그라운드(&)로 던진다. 여기선 실행만 하고
    /// 완료를 기다리지 않으므로 UI 를 막지 않는다(Process.run 은 spawn 직후 반환).
    ///
    /// **왜 `brew update` 를 먼저 하는가(이 수리의 핵심)**: brew 의 자동 갱신은 `HOMEBREW_AUTO_UPDATE_SECS`
    /// 로 스로틀된다(기본 하루). 최근에 다른 brew 명령을 쓴 사람은 그 창 안에서 자동 갱신이 **건너뛰어져** 탭이
    /// 낡은 채로 남고, `brew upgrade` 는 새 버전을 못 본 채 "이미 최신"으로 조용히 끝난다. 그러면 앱은 죽지 않고
    /// 배너만 "업데이트 중…"으로 굳는다 — 실사용에서 보고된 증상이 정확히 이것이다.
    ///
    /// **왜 `--cask` 를 명시하는가**: 이름만 주면 brew 가 포뮬러를 먼저 찾는다. 지금은 동명 포뮬러가 없어 우연히
    /// 동작하지만, 언젠가 생기면 엉뚱한 것을 올린다. 문서·복사 명령과도 같은 형태로 맞춘다.
    ///
    /// **로그**: 예전엔 출력을 통째로 /dev/null 에 버려 실패 원인을 아무도 볼 수 없었다. 이제 파일에 남겨
    /// 사용자가 붙여넣을 수 있게 한다(전송 없음 — 이 맥에만 남는다).
    nonisolated static let logPath = NSString(string: "~/Library/Logs/aing-check-update.log").expandingTildeInPath

    /// 스폰할 셸 스크립트 문자열. **테스트가 이 함수를 직접 검사한다** — 테스트가 문자열을 재조립하면
    /// 소스를 되돌려도 초록이라 회귀를 못 잡는다.
    nonisolated static func upgradeScript(brew: String) -> String {
        let inner = "\"\(brew)\" update && \"\(brew)\" upgrade --cask \(caskName) && open -a \"\(appPath)\""
        // 실패해도 로그가 남도록 파이프 전체를 파일로 리다이렉트한다(append — 직전 시도와 비교할 수 있게).
        return "nohup zsh -c '\(inner)' >>\"\(logPath)\" 2>&1 &"
    }

    nonisolated static func detachedSpawn(brew: String) -> Bool {
        let script = upgradeScript(brew: brew)
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

    // MARK: DMG 자가 업데이트 (직접 설치한 사람의 원클릭)

    /// DMG 자가 업데이트 한 벌 — 스크립트 본문과 그 스크립트에 넘길 인자들.
    struct DMGUpdatePlan: Equatable {
        /// 분리 프로세스가 실행할 zsh 스크립트(상수 — 어떤 값도 끼워 넣지 않는다).
        let script: String
        /// `zsh -c <래퍼>` 에 이어 붙일 인자들.
        /// `[argv0, 스크립트, 번들경로, DMG주소, PID, 요구사항, 내build, 상태파일, 로그파일]`.
        let arguments: [String]
    }

    /// 분리 스폰 래퍼. **순수 상수다 — 어떤 값도 문자열에 끼워 넣지 않는다.**
    ///
    /// 왜 이렇게까지 하는가: 교체 대상은 `Bundle.main.bundlePath` 이고 그건 **사용자가 정하는 값**이다
    /// (앱을 어느 폴더에 끌어다 놓았는지). 기존 brew 경로처럼 `zsh -c '…경로…'` 로 끼워 넣으면 폴더 이름에
    /// 작은 인용(`'`)이 하나 있는 것만으로 스크립트가 끊기고 그 뒤가 명령으로 해석된다 — 실측으로 임의 명령이
    /// 실행됐고, 평범한 `Yesung's Apps` 같은 폴더만으로도 `unmatched "` 로 통째로 죽었다. 이 스크립트에는
    /// `rm -rf` 가 들어 있으므로 인용이 깨지는 것 자체가 위험하다.
    ///
    /// 그래서 **스크립트 본문까지** 위치 인자로 넘긴다. 그러면 바깥 셸이 전개하는 것은 `$1`…`$8` 뿐이고
    /// 전개 결과는 다시 파싱되지 않으므로, 어떤 글자가 와도 데이터로만 남는다(공백·한글·`'`·`;`·`$` 실측 확인).
    nonisolated static let dmgSpawnWrapper =
        #"nohup zsh -c "$1" aing-check-update "$2" "$3" "$4" "$5" "$6" "$7" >>"$8" 2>&1 &"#

    /// DMG 자가 업데이트 스크립트. **상수**이고 값은 전부 위치 인자로 받는다:
    /// `$1` 번들 경로 · `$2` DMG 주소 · `$3` 앱 PID · `$4` 코드 서명 지정 요구사항 · `$5` 내 build · `$6` 상태 파일.
    ///
    /// **순서가 안전의 핵심이다** — 검증을 다 통과하고 사본까지 만든 뒤에야 기존 번들을 건드린다.
    /// 그래서 네트워크·공증·신원·버전·권한 중 무엇이 실패해도 설치본은 그 자리에 그대로 남는다(실측: 404 는
    /// 내려받기에서, 권한 없음은 스테이징에서 멈추고 번들은 손대지 않았다).
    ///
    /// **`set -e` 를 쓰지 않는다**: zsh 의 errexit 은 `&&`/`||` 목록의 마지막이 아닌 명령에 적용되지 않아
    /// (실측: `set -e; false && echo nope; echo AFTER` → AFTER 가 찍히고 종료코드 0) 실패를 조용히 흘린다.
    /// 그래서 파괴적인 단계마다 `|| { fail …; }` 로 **명시 분기**한다.
    ///
    /// **`xcrun stapler` 를 쓰지 않는다**: Xcode 명령행 도구가 없는 맥에서는 그 자체로 실패하고,
    /// DMG 로 설치하는 사람이야말로 개발자 도구가 없을 확률이 높다. `spctl` 이 이미 공증을 본다
    /// (실측: 마운트한 앱에 `source=Notarized Developer ID`).
    nonisolated static let dmgUpdateScript = """
        set -u
        DEST="$1"; URL="$2"; APP_PID="$3"; REQ="$4"; MIN_BUILD="$5"; STATE="$6"
        M="[aing-check-update]"
        # 상태 파일은 이번 시도에서 새로 시작한다(지난 시도의 실패가 남아 배너를 속이지 않게).
        # 부모 폴더를 먼저 만든다 — 없으면 `: >` 가 조용히 실패해 표식이 하나도 안 남고,
        # 배너는 다시 600초 "업데이트 중…"으로 굳는다(고치려던 바로 그 증상).
        mkdir -p "$(dirname "$STATE")" 2>/dev/null
        : > "$STATE" 2>/dev/null
        note() { echo "stage=$1" >>"$STATE" 2>/dev/null; echo "$M $1"; }
        fail() { echo "error=$1 code=${2:-1}" >>"$STATE" 2>/dev/null; echo "$M 실패: $1 ($3)"; exit 1; }
        echo "$M ---- 시작 $(date +%Y-%m-%dT%H:%M:%S) → $DEST"
        note start

        # 자물쇠. 두 벌이 같은 번들을 동시에 갈아치우면 한쪽이 치워 둔 옛 번들을 다른 쪽이 지운다.
        # SIGKILL 로 죽은 시도가 남긴 자물쇠는 한 시간 뒤 가져온다(영구히 막히지 않게).
        LOCK="${TMPDIR:-/tmp}/aing-check-update.lock"
        if ! mkdir "$LOCK" 2>/dev/null; then
          if [ -n "$(find "$LOCK" -maxdepth 0 -mmin +60 2>/dev/null)" ]; then
            rm -rf "$LOCK"
            mkdir "$LOCK" 2>/dev/null || fail lock 1 "자물쇠를 잡지 못했습니다"
          else
            fail busy 1 "이미 업데이트가 진행 중입니다"
          fi
        fi

        TMP="$(mktemp -d "${TMPDIR:-/tmp}/aing-check-update.XXXXXX")" || { rm -rf "$LOCK"; exit 1; }
        MNT="$TMP/mnt"
        MOUNTED=""
        PARENT="$(dirname "$DEST")"
        STAGE_DIR="$PARENT/.aing-check-update.$$"
        OLD="$DEST.aing-check-old"
        cleanup() {
          # errexit 을 안 쓰므로 트랩이 중간에 끊기지 않는다. 붙지 않은 마운트에 detach 를 부르면 실패하므로
          # 실제로 붙었을 때만 부른다.
          [ -n "$MOUNTED" ] && hdiutil detach "$MNT" -force >/dev/null 2>&1
          rm -rf "$TMP" "$STAGE_DIR" "$LOCK"
        }
        trap cleanup EXIT

        # 지난 시도가 SIGKILL 로 죽어 남긴 잔재를 치운다. 남겨 두면 다음 ditto 가 **병합**해
        # 새 버전에서 지워진 파일이 섞인 번들이 되고 코드 서명이 무효가 된다(실측: ditto 는 대상이 이미 있으면 합친다).
        rm -rf "$OLD"
        find "$PARENT" -maxdepth 1 -name '.aing-check-update.*' -exec rm -rf {} + 2>/dev/null

        # 1) 받는다. `'=https'` 의 작은 인용은 **지워선 안 된다**: zsh 는 단어 앞의 `=https` 를 `=명령어` 확장으로
        #    읽어 "https not found" 로 죽는다(실측). 스크립트를 위치 인자로 넘기므로 작은 인용을 마음껏 쓸 수 있다.
        note download
        curl -fL --proto '=https' --tlsv1.2 --connect-timeout 20 --max-time 420 -o "$TMP/a.dmg" "$URL" \\
          || fail download $? "내려받지 못했습니다(연결 또는 주소)"
        echo "$M 받음: $(stat -f %z "$TMP/a.dmg") bytes"

        # 2) 붙이기 **전에** DMG 자체를 본다 — 공격자 바이트를 커널 파일시스템 파서에 먼저 들이지 않는다.
        #    종료코드만 보지 않고 출처 문자열까지 확인한다: Gatekeeper 가 꺼진 맥에서는 spctl 이 무엇이든 통과시킨다.
        note verify
        hdiutil verify "$TMP/a.dmg" >/dev/null 2>&1 || fail image $? "받은 파일이 손상됐습니다"
        LC_ALL=C spctl -a -t open --context context:primary-signature -v "$TMP/a.dmg" 2>&1 \\
          | grep -q "source=Notarized Developer ID" || fail dmg-notary 1 "DMG 가 공증되지 않았습니다"

        # 3) 읽기 전용으로 붙인다.
        mkdir -p "$MNT"
        hdiutil attach -readonly -nobrowse -noautoopen -mountpoint "$MNT" "$TMP/a.dmg" >/dev/null \\
          || fail mount $? "DMG 를 열지 못했습니다"
        MOUNTED=1
        SRC="$MNT/aing-check.app"
        # 심링크면 거절한다 — 링크를 따라가면 검증·복사 대상이 **디스크의 다른 앱**으로 돌아간다.
        [ -d "$SRC" ] && [ ! -L "$SRC" ] || fail content 1 "DMG 안에 앱이 없습니다"

        # 4) ★ 두 관문을 **둘 다** 지난다.
        #    공증: spctl 이 본다. 우리 신원: 지정 요구사항이 본다. 하나만으로는 각각 뚫린다(실측) —
        #    spctl 만 보면 Xcode·Chrome 같은 '남이 공증한 앱'이 통과하고, 요구사항만 보면
        #    우리 인증서로 서명했지만 **공증하지 않은** 번들이 통과한다.
        LC_ALL=C spctl --assess --type execute -v "$SRC" 2>&1 \\
          | grep -q "source=Notarized Developer ID" || fail notary 1 "앱이 공증되지 않았습니다"
        codesign --verify --deep --strict -R "=$REQ" "$SRC" \\
          || fail identity $? "우리 앱이 아닙니다(서명 신원 불일치)"

        # 5) 버전 결박 — 받은 것이 **더 새 것**이어야 한다.
        #    실측: 옛 정식 릴리스(0.3.47)는 위 검증을 전부 통과한다. 결박이 없으면 `latest` 가 한 번 흔들리거나
        #    자산이 잘못 올라간 순간 다운그레이드가 설치되고, 그 뒤엔 배너가 또 업데이트를 권해 고리가 된다.
        GOT_BUILD="$(plutil -extract CFBundleVersion raw "$SRC/Contents/Info.plist" 2>/dev/null)"
        case "$GOT_BUILD" in
          ''|*[!0-9]*) fail build-unreadable 1 "받은 앱의 build 를 읽지 못했습니다" ;;
        esac
        if [ "$GOT_BUILD" -le "$MIN_BUILD" ]; then
          fail not-newer 1 "받은 앱이 더 새 버전이 아닙니다(build $GOT_BUILD ≤ $MIN_BUILD)"
        fi
        echo "$M 검증 통과: $(plutil -extract CFBundleShortVersionString raw "$SRC/Contents/Info.plist" 2>/dev/null) build $GOT_BUILD"

        # 6) 사본을 DEST 와 **같은 볼륨**에 만든다 — 그래야 마지막 교체가 복사가 아니라 이름 바꾸기다.
        note staging
        mkdir -p "$STAGE_DIR" || fail permission $? "이 자리에 쓸 권한이 없습니다 — $PARENT"
        STAGE="$STAGE_DIR/$(basename "$DEST")"
        ditto "$SRC" "$STAGE" || fail copy $? "복사하지 못했습니다(용량 부족일 수 있습니다)"
        xattr -dr com.apple.quarantine "$STAGE" 2>/dev/null
        # 복사본을 **다시** 검증한다 — 용량 부족으로 반쪽 복사가 되면 서명이 깨진 번들이 자리에 들어간다.
        codesign --verify --deep --strict -R "=$REQ" "$STAGE" \\
          || fail staged-verify $? "복사본 검증에 실패했습니다"

        # 7) 앱을 **정상** 종료시킨다. SIGTERM 을 앱이 받아 근무 세션을 닫고(finishWorkBeforeQuit) 스스로 끝낸다.
        #    Apple Event 로 quit 을 보내면 자동화 권한 프롬프트가 끼어들 수 있고, 무엇보다 **응답으로** 돌아와
        #    프로세스 소멸을 보장하지 않는다 — 종료 절차가 도는 중에 번들을 바꾸면 경합한다. 그래서 PID 소멸을 본다.
        note quit
        if [ -n "$APP_PID" ] && kill -0 "$APP_PID" 2>/dev/null; then
          echo "$M 앱 종료 요청: pid $APP_PID"
          kill -TERM "$APP_PID" 2>/dev/null
          i=0
          while [ "$i" -lt 100 ] && kill -0 "$APP_PID" 2>/dev/null; do sleep 0.2; i=$((i+1)); done
          if kill -0 "$APP_PID" 2>/dev/null; then
            echo "$M 20초 안에 끝나지 않아 강제 종료"
            kill -KILL "$APP_PID" 2>/dev/null
            sleep 1
          fi
        fi

        # 8) 교체 — 같은 볼륨이라 이름 바꾸기 두 번. 어느 쪽이 실패해도 옛 번들을 되돌리고,
        #    **교체된 자리를 다시 검증**한 뒤에만 옛 번들을 지운다(검증한 것과 실행될 것이 같다는 보장).
        note swap
        if [ -d "$DEST" ] && ! mv "$DEST" "$OLD"; then
          fail swap-aside $? "옛 번들을 치우지 못했습니다"
        fi
        # 되돌리기까지 실패하면(부모 폴더가 그 사이 못 쓰게 됐다든지) 앱은 `$OLD` 에 남는다. 그때는 앱이
        # 제자리에 없어서 **다시 눌러 볼 수조차 없으므로**, 사람이 손으로 고칠 수 있게 어디 있는지 로그에 적는다.
        rescue_note() {
          [ -d "$DEST" ] || echo "$M ★ 복구 안내: 앱이 \"$OLD\" 에 있습니다 — 그 폴더 이름을 \"$(basename "$DEST")\" 로 바꿔 주세요"
        }
        if ! mv "$STAGE" "$DEST"; then
          [ -d "$OLD" ] && mv "$OLD" "$DEST"
          rescue_note
          fail swap $? "번들을 바꾸지 못했습니다(되돌렸습니다)"
        fi
        if ! codesign --verify --deep --strict -R "=$REQ" "$DEST"; then
          rm -rf "$DEST"
          [ -d "$OLD" ] && mv "$OLD" "$DEST"
          rescue_note
          fail swapped-verify 1 "바꾼 뒤 검증에 실패해 되돌렸습니다"
        fi
        rm -rf "$OLD"

        # 9) 다시 연다. 성공·실패 어느 쪽이든 앱은 떠 있어야 한다 — 사용자가 앱을 잃으면 알릴 표면조차 없다.
        note done
        open -a "$DEST" || open "$DEST" || echo "$M 경고: 다시 열지 못했습니다 — 직접 실행해 주세요"
        echo "$M ---- 완료"
        """

    /// 기본 DMG 스폰. 래퍼만 셸 텍스트로 주고 나머지는 전부 인자로 넘긴다(`dmgSpawnWrapper` 주석).
    nonisolated static func detachedSpawnDMG(_ plan: DMGUpdatePlan) -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        proc.arguments = ["-c", dmgSpawnWrapper] + plan.arguments
        do {
            try proc.run()
            return true
        } catch {
            return false
        }
    }
}
#endif
