#if DEBUG
import CheckCore
import CheckMobileShared
import Foundation

/// 데모 모드(SPEC-ios-build §1-8) — **DEBUG 빌드에서만 컴파일된다.** Release 바이너리에는 이 파일도, 스텁 서버도 없다.
///
/// 실행: `simctl launch <기기> com.yehsung.aingcheck -AingCheckDemo YES -AingCheckDemoRoute <라우트>`
/// - 서버: `MobileStubURLProtocol`(호스트 `demo.aingcheck.invalid`)이 `Demo/Fixtures/**` 의 고정 JSON 을 돌려준다.
/// - 시계: 2026-09-17 14:05 KST 에 멈춰 있다(`MobileClock.demoInstant`).
/// - 세션: 로그인된 데모 계정(라우트 `login` 이면 로그아웃 상태, `update` 면 업데이트 필요 화면).
/// - 실시간 없음(소켓 nil) · 키체인·App Group 을 건드리지 않는다(메모리 금고 · 임시 저장소 — 실행마다 비운다).
///
/// 라우트: `now|messages|messages/<peer>|rankings/league|rankings/tokens|rankings/minigame|games|games/timing|games/flappy|
/// games/gomoku/lobby|games/gomoku/match|me|me/shop|me/feedback|me/settings|login|update` (`AingRoute(path:)` 로 연다).
///
/// ## 픽스처 규칙(탭 작업자가 자기 폴더에 더한다 — `Demo/Fixtures/<탭>/…json`)
/// 1. 파일 이름(확장자 뺀 것)이 **요청 키**다. 폴더 이름은 소유 구분일 뿐 키에 들어가지 않는다 — 키는 모든 폴더에서 유일해야 한다
///    (`BaseDemoFixtureTests` 가 중복을 잡는다).
///    - RPC `POST /rest/v1/rpc/<fn>` → `rpc.<fn>`
///    - 표 `<METHOD> /rest/v1/<table>` → `rest.<table>.<method 소문자>` (예: `rest.memberships.get`)
///    - 인증 `<METHOD> /auth/v1/<a>/<b>` → `auth.<a>.<b>.<method 소문자>` (예: `auth.token.post`, `auth.logout.post`)
///    - 저장소 `<METHOD> /storage/v1/...` → `storage.<method 소문자>`
/// 2. 변형: `<키>@<바늘>.json` 은 요청 본문이나 쿼리에 `<바늘>` 글자가 들어 있을 때 기본 파일보다 먼저 고른다(바늘이 긴 것 우선).
///    예: `rpc.gomoku_state@match-live-1.json`.
/// 3. 장면: `_<장면>` 폴더 안의 파일은 그 장면일 때만 쓰고, 같은 키의 바깥 파일보다 우선한다. 장면 이름 = 라우트의 `/` 를 `-` 로 바꾼 것
///    (예: 라우트 `games/gomoku/match` → `_games-gomoku-match`, `update` → `_update`).
/// 4. 파일이 JSON 객체이고 `"__status"` 키가 있으면 그 상태 코드와 `"__body"` 값을 응답으로 쓴다(오류 재현).
/// 5. 키에 맞는 파일이 없으면 404 PGRST202(함수·표 없음)로 답한다 — 스토어는 "옛 서버"처럼 조용히 접어야 한다.
/// 6. 금지 호출(`MobileForbiddenCalls`)은 403 으로 답하고 콘솔에 `[AingCheckDemo] 금지 호출` 을 찍는다.
/// 7. 사람 이름은 지어낸 값만(실사용자 이름 금지). 데모 사용자 id 는 `MobileDemo.userID`.
package enum MobileDemo {
    package static let host = "demo.aingcheck.invalid"
    package static let userID = "d0000000-0000-4000-8000-000000000001"
    package static let email = "demo@aing-check.invalid"
    package static let installationID = "d0000000-0000-4000-8000-0000000000aa"

    /// 실행 인자 → 데모 라우트. 데모가 아니면 nil.
    package static func launchRoute(arguments: [String]) -> String? {
        guard value(of: "-AingCheckDemo", in: arguments).map(isTruthy) == true else { return nil }
        let route = value(of: "-AingCheckDemoRoute", in: arguments)?.trimmingCharacters(in: .whitespaces)
        return (route?.isEmpty == false) ? route! : "now"
    }

    /// 데모 조립. 데모가 아니면 nil.
    @MainActor
    package static func environment(arguments: [String]) -> MobileEnvironment? {
        guard let route = launchRoute(arguments: arguments) else { return nil }
        let scenario = route.replacingOccurrences(of: "/", with: "-").lowercased()
        let index = MobileDemoFixtures.load()
        MobileStubURLProtocol.register(host: host) { request in
            index.response(for: request, scenario: scenario)
        }

        let storage = AingSharedStorage.temporary(name: "demo")
        try? FileManager.default.removeItem(at: storage.directory)
        if let suite = storage.defaultsSuiteName {
            UserDefaults.standard.removePersistentDomain(forName: suite)
        }
        storage.ensureDirectory()

        let vault = InMemoryTokenVault()
        if route != "login" {
            vault.write(accessToken, key: AingKeychain.accessTokenKey)
            vault.write("demo-refresh-token", key: AingKeychain.refreshTokenKey)
            storage.defaults.set(userID, forKey: AingSharedKeys.userID)
            storage.defaults.set(email, forKey: AingSharedKeys.email)
        }

        return MobileEnvironment(
            service: SupabaseWorkService(
                projectURL: URL(string: "https://\(host)")!,
                anonKey: "demo-anon-key",
                session: MobileStubURLProtocol.makeSession()
            ),
            vault: vault,
            storage: storage,
            appInfo: MobileAppInfo(build: 1, version: "0.1.0", osVersion: MobileAppInfo.fromBundle().osVersion, apnsEnvironment: nil),
            clock: .fixed(MobileClock.demoInstant),
            installationID: installationID,
            realtimeTransport: nil,
            runsTimers: false,
            reloadWidgetTimelines: {},
            demoRoute: route
        )
    }

    /// exp 가 2100-01-01 인 가짜 JWT(서명 없음 — 데모 스텁은 검증하지 않는다). 실행 직후 갱신이 돌지 않게 한다.
    package static let accessToken: String = {
        func b64(_ text: String) -> String {
            Data(text.utf8).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }
        return b64(#"{"alg":"none","typ":"JWT"}"#) + "." + b64(#"{"sub":"\#(userID)","exp":4102444800,"role":"authenticated"}"#) + ".demo"
    }()

    private static func value(of flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    private static func isTruthy(_ raw: String) -> Bool {
        ["yes", "1", "true"].contains(raw.lowercased())
    }
}

/// 픽스처 색인(읽기 전용 — 한 번 만들고 여러 스레드가 읽는다).
package final class MobileDemoFixtures: Sendable {
    package struct Entry: Sendable, Equatable {
        package let key: String
        package let needle: String?
        package let scenario: String?
        package let relativePath: String
        package let data: Data
    }

    package let entries: [Entry]

    package init(entries: [Entry]) {
        self.entries = entries
    }

    /// 패키지 리소스 `Fixtures` 폴더 전체를 읽는다.
    package static func load(bundle: Bundle = .module) -> MobileDemoFixtures {
        guard let root = bundle.url(forResource: "Fixtures", withExtension: nil) else {
            return MobileDemoFixtures(entries: [])
        }
        return load(root: root)
    }

    package static func load(root: URL) -> MobileDemoFixtures {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: nil) else {
            return MobileDemoFixtures(entries: [])
        }
        let rootPath = root.standardizedFileURL.resolvingSymlinksInPath().path
        var entries: [Entry] = []
        for case let url as URL in enumerator where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url) else { continue }
            let full = url.standardizedFileURL.resolvingSymlinksInPath().path
            let relative = full.hasPrefix(rootPath) ? String(full.dropFirst(rootPath.count + 1)) : url.lastPathComponent
            let folders = relative.split(separator: "/").dropLast()
            let scenario = folders.last(where: { $0.hasPrefix("_") }).map { String($0.dropFirst()).lowercased() }
            let name = url.deletingPathExtension().lastPathComponent
            let parts = name.split(separator: "@", maxSplits: 1).map(String.init)
            entries.append(Entry(
                key: parts[0],
                needle: parts.count > 1 ? parts[1] : nil,
                scenario: scenario,
                relativePath: relative,
                data: data
            ))
        }
        return MobileDemoFixtures(entries: entries.sorted { $0.relativePath < $1.relativePath })
    }

    /// 요청 → 픽스처 키(파일 이름 규칙 1).
    package static func key(for request: MobileStubRequest) -> String {
        let method = request.method.lowercased()
        if let rpc = request.rpcName { return "rpc.\(rpc)" }
        let segments = request.path.split(separator: "/").map(String.init)
        if segments.count >= 3, segments[0] == "rest", segments[1] == "v1" {
            return "rest.\(segments[2]).\(method)"
        }
        if segments.count >= 3, segments[0] == "auth", segments[1] == "v1" {
            return (["auth"] + segments.dropFirst(2) + [method]).joined(separator: ".")
        }
        if segments.first == "storage" { return "storage.\(method)" }
        return "unknown.\(method)"
    }

    /// 같은 장면·같은 키 안에서 바늘이 같은 파일이 두 개 이상이면 그 목록(테스트가 0 을 단언한다).
    package var duplicateKeys: [String] {
        var seen: [String: String] = [:]
        var dupes: [String] = []
        for entry in entries {
            let id = "\(entry.scenario ?? "")|\(entry.key)|\(entry.needle ?? "")"
            if let first = seen[id] {
                dupes.append("\(first) ↔ \(entry.relativePath)")
            } else {
                seen[id] = entry.relativePath
            }
        }
        return dupes
    }

    package func entry(for request: MobileStubRequest, scenario: String?) -> Entry? {
        let key = Self.key(for: request)
        let haystack = request.bodyText + "&" + request.query
        let candidates = entries.filter { $0.key == key && ($0.scenario == nil || $0.scenario == scenario) }
        func matches(_ entry: Entry) -> Bool { entry.needle.map { haystack.contains($0) } ?? true }
        // 장면 파일 > 바깥 파일, 그 안에서 바늘(긴 것) > 기본.
        let ranked = candidates.filter(matches).sorted { lhs, rhs in
            let ls = lhs.scenario != nil ? 1 : 0, rs = rhs.scenario != nil ? 1 : 0
            if ls != rs { return ls > rs }
            return (lhs.needle?.count ?? -1) > (rhs.needle?.count ?? -1)
        }
        return ranked.first
    }

    package func response(for request: MobileStubRequest, scenario: String?) -> MobileStubResponse {
        if let violation = MobileForbiddenCalls.violation(request) {
            print("[AingCheckDemo] 금지 호출: \(violation)")
            return .json(#"{"message":"forbidden on phone"}"#, status: 403)
        }
        guard let entry = entry(for: request, scenario: scenario) else {
            // 통합 점검용 한 줄: 데모 라우트마다 어떤 키가 픽스처 없이 404 로 접혔는지 콘솔(simctl launch --stdout)에서 센다.
            print("[AingCheckDemo] 픽스처 없음: \(Self.key(for: request)) 장면=\(scenario ?? "-")")
            return .missingFunction(Self.key(for: request))
        }
        if let object = try? JSONSerialization.jsonObject(with: entry.data) as? [String: Any],
           let status = object["__status"] as? Int {
            let body = object["__body"].flatMap { try? JSONSerialization.data(withJSONObject: $0, options: [.fragmentsAllowed]) } ?? Data("{}".utf8)
            return MobileStubResponse(status: status, body: body)
        }
        return MobileStubResponse(status: 200, body: entry.data)
    }
}
#endif
