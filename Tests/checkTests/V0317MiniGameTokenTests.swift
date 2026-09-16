import Foundation
import Testing
@testable import check
@testable import CheckCore

// v0.3.17 — 미니게임 점수 제출의 **위조 차단 계약**.
//
// 예전에는 클라가 `minigame_daily_scores` 표에 직접 upsert 했다. 그래서 앱 없이 `curl` 한 줄로 아무 점수나
// 올릴 수 있었고, 상금이 루비가 된 뒤로는 그 구멍이 곧 재화 발행기였다(두 게임 1등 = 하루 40루비,
// 캐릭터 전종 230 이 6일).
//
// 막는 방식은 **점수 값을 판단하지 않는다** — 그건 언젠가 정직한 사람을 막고, 그 사고는 위조보다 나쁘다
// ("잘 놀았는데 점수가 안 올라간다"는 재현도 신고도 안 된다). 대신 "이 판이 실제로 앱에서 시작됐는가"만 본다:
// 판 시작에 서버가 토큰과 시작 시각을 발급하고, 제출은 그 토큰으로만 받는다.

private let tkUserID = "00000000-0000-0000-0000-000000000002"

@MainActor
private func tkDefaults() -> UserDefaults {
    let suite = "v0317-mg-token-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

@MainActor
private func tkStore(host: String) -> WorkTimerStore {
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed)
    )
    let store = WorkTimerStore(
        service: service,
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: tkDefaults()
    )
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: tkUserID)
    store.currentTeamID = URLProtocolStub.stubTeamID
    return store
}

@MainActor
private func tkSettle() async {
    for _ in 0..<60 { try? await Task.sleep(for: .milliseconds(5)) }
}

// MARK: - ① 토큰이 없으면 제출이 안 나간다 (그리고 사용자에게 말한다)

/// 이게 이번 변경의 핵심이다. 토큰 없이도 제출이 나가면 서버가 `no_token` 으로 거절하므로 위조는 여전히
/// 막히지만, **사용자는 이유를 모른 채 순위표에서 사라진다.** 그래서 클라에서 먼저 멈추고 말해 준다.
@MainActor
@Test("토큰 없이 끝난 판은 제출하지 않고, 조용히 버리지도 않는다")
func noTokenMeansNoSubmitButTheUserIsTold() async {
    let host = "v0317-mg-no-token"
    let store = tkStore(host: host)
    #expect(store.miniGameRoundToken == nil)

    store.recordMiniGameScore(kind: .timingBar, score: 880)
    await tkSettle()

    // ⚠️ **제출이** 안 나갔는지를 본다. 토큰 없는 판 뒤에는 다음 판을 위한 선발급(start_round)이
    //    한 번 나가는 것이 정상이라, "요청이 0건"으로 재면 그 정상 동작에 걸린다.
    let submits = URLProtocolStub.requests(forHost: host).filter { ($0.url?.path ?? "").contains("submit_score") }
    #expect(submits.isEmpty,
            Comment(rawValue: "토큰이 없는데 제출이 나갔다 — \(submits.count)건"))
    #expect(store.miniGameSubmitNotice != nil,
            "점수를 못 올렸는데 아무 말도 안 한다 — 삼키면 \"잘 놀았는데 순위표에 없다\"가 된다")
    // 로컬 최고는 그래도 오른다(순위표와 별개로 내 기록이다).
    #expect(store.miniGameBest(.timingBar) == 880)
}

// MARK: - ② 토큰이 있으면 그 토큰으로 나간다

@MainActor
@Test("제출은 판 시작에 받아 둔 토큰을 그대로 싣는다")
func submitCarriesTheRoundToken() async {
    let host = "v0317-mg-with-token"
    let store = tkStore(host: host)
    store.miniGameRoundToken = "tok-abc"
    store.miniGameRoundTokenKind = .flappy

    store.recordMiniGameScore(kind: .flappy, score: 29)
    await tkSettle()

    let paths = URLProtocolStub.requests(forHost: host).map { $0.url?.path ?? "" }
    #expect(paths.first == "/rest/v1/rpc/minigame_submit_score", Comment(rawValue: "\(paths)"))
    let body = URLProtocolStub.bodies(forHost: host).first ?? ""
    #expect(body.contains("tok-abc"), Comment(rawValue: "본문에 토큰이 없다 — \(body)"))

    // ★ 한 토큰에 한 점수다. 보낸 뒤에는 비어 있어야 같은 토큰이 두 번 안 나간다.
    #expect(store.miniGameRoundToken == nil, "토큰을 안 비웠다 — 다음 판이 같은 토큰을 재사용한다")
}

/// 게임을 바꾸면 지난 게임 토큰으로는 못 낸다. 서버도 게임을 대조하지만, 클라가 먼저 멈춰야
/// 사용자가 이유를 듣는다(서버까지 갔다 오면 그냥 "못 올렸어요"만 남는다).
@MainActor
@Test("다른 게임의 토큰으로는 제출하지 않는다")
func aTokenFromAnotherGameIsNotUsed() async {
    let host = "v0317-mg-wrong-kind"
    let store = tkStore(host: host)
    store.miniGameRoundToken = "tok-timing"
    store.miniGameRoundTokenKind = .timingBar

    store.recordMiniGameScore(kind: .flappy, score: 29)
    await tkSettle()

    let wrongSubmits = URLProtocolStub.requests(forHost: host).filter { ($0.url?.path ?? "").contains("submit_score") }
    #expect(wrongSubmits.isEmpty, "타이밍바 토큰으로 플래피 점수를 냈다")
    #expect(store.miniGameSubmitNotice != nil)
}

// MARK: - ③ 표에 직접 쓰는 경로가 소스에 없다

/// 행동 테스트만으로는 **다른 뷰가 서비스를 직접 부르는** 조합을 못 잡는다. 경로 문자열 자체를 금지한다.
@Test("클라 어디에도 minigame_daily_scores 직접 쓰기 경로가 없다")
func noSourceWritesTheScoreTableDirectly() throws {
    let sources = try tkAllSources()
    for (name, code) in sources {
        let writesTable = tkStripped(code).contains("/rest/v1/minigame_daily_scores")
        #expect(!writesTable, Comment(rawValue: "\(name) 이 점수 표에 직접 쓴다 — 토큰 RPC 를 거쳐야 한다"))
    }
}

// MARK: - ④ 두 게임이 모두 배선됐다

/// 배선 지점은 **하나**다(`MiniGameHost.onPlayingChanged`). 두 게임이 전부 그 호스트를 지나므로 한 곳만
/// 이으면 둘 다 덮인다 — 게임마다 따로 붙이면 한쪽을 빠뜨렸을 때 그 게임 점수만 통째로 안 올라가고,
/// 겉으론 아무 표시가 없다. 그래서 ㉠ 허브가 시작 신호에서 토큰을 받고 ㉡ 두 게임이 그 신호를 보낸다를
/// 함께 못 박는다.
@Test("판 시작 신호에서 토큰을 받고, 두 게임이 모두 그 신호를 보낸다")
func bothGamesReachTheSingleTokenWiring() throws {
    let sources = try tkAllSources()

    // ⚠️ `#expect(code.contains(...))` 를 그대로 쓰면 실패할 때 **소스 전문**이 진단에 찍혀 읽을 수가 없다.
    //    Bool 로 먼저 접어 두면 실패 메시지가 내가 쓴 한 줄만 남는다.
    let panelWiresStart = tkStripped(try #require(sources["MiniGamePanel.swift"]))
        .contains("if playing { store.beginMiniGameRound(kind: kind) }")
    #expect(panelWiresStart,
            "허브가 판 시작에서 토큰을 안 받는다 — 끝날 때 받으면 경과가 0 이라 서버가 전부 거절한다")

    for game in ["MiniGameTimingBar.swift", "MiniGameFlappy.swift"] {
        let signals = tkStripped(try #require(sources[game])).contains("host.onPlayingChanged(")
        #expect(signals, Comment(rawValue: "\(game) 이 시작 신호를 안 보낸다 — 그 게임만 점수가 안 올라간다"))
    }

    // ★ 기준선이 실제로 다르다: 위 검사가 "원래부터 그랬다"로 초록이 되지 않게, 제출이 정말
    //   토큰 경로를 쓰는지 서비스 쪽에서 확인한다.
    let service = tkStripped(try #require(sources["SupabaseWorkService.swift"]))
    #expect(service.contains("/rest/v1/rpc/minigame_start_round"), "시작 RPC 가 서비스에 없다")
    #expect(service.contains("/rest/v1/rpc/minigame_submit_score"), "제출 RPC 가 서비스에 없다")
}

// MARK: - 소스 읽기

private func tkAllSources() throws -> [String: String] {
    let dir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/check", isDirectory: true)
    var out: [String: String] = [:]
    let names = try FileManager.default.checkSourcesContentsOfDirectory(atPath: dir.path)
    for name in names where name.hasSuffix(".swift") {
        out[name] = try String(contentsOf: dir.appendingCheckSourcePath(name), encoding: .utf8)
    }
    return out
}

/// 주석을 걷어낸다. 안 걷어내면 **설명을 지워야만 초록이 되는** 테스트가 된다(이 저장소의 하우스 규칙) —
/// 위 금지 문자열은 경로라서 주석에도 쓰일 수 있다. 문자열 리터럴 안의 `//` 는 보존한다.
private func tkStripped(_ source: String) -> String {
    var out = ""
    var inLine = false, inBlock = false, inString = false, escaped = false
    var index = source.startIndex
    while index < source.endIndex {
        let c = source[index]
        let nextIndex = source.index(after: index)
        let next: Character? = nextIndex < source.endIndex ? source[nextIndex] : nil
        if inLine {
            if c == "\n" { inLine = false; out.append(c) }
        } else if inBlock {
            if c == "*", next == "/" { inBlock = false; index = nextIndex }
        } else if inString {
            out.append(c)
            if escaped { escaped = false }
            else if c == "\\" { escaped = true }
            else if c == "\"" { inString = false }
        } else if c == "/", next == "/" {
            inLine = true; index = nextIndex
        } else if c == "/", next == "*" {
            inBlock = true; index = nextIndex
        } else if c == "\"" {
            inString = true; out.append(c)
        } else {
            out.append(c)
        }
        index = source.index(after: index)
    }
    return out.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
}

// MARK: - ⑤ 늦게 온 토큰이 지금 판의 토큰을 덮지 않는다 (실사용 신고 2026-09-14)

/// **신고**: "플레이 도중에 '점수를 못 올렸어요' 한 번 떴어. 그다음 판은 또 정상적으로 되었고."
///
/// 서버는 `(user_id, game)` 당 **미사용 토큰을 한 행만** 두고 `minigame_start_round` 가 그 행의 id 를
/// **갈아 끼운다**(`do update set id = gen_random_uuid()`). 그래서 요청이 겹치면 **마지막에 발급된
/// 토큰 하나만 살아 있다.** 클라가 늦게 도착한 옛 응답으로 덮어쓰면 죽은 토큰을 들고 제출해
/// `no_token` 이 되고, 다음 판은 경합이 없어 정상이다 — 신고의 모양과 정확히 같다.
///
/// 이 프로토콜은 **요청별로 지연을 달리** 준다(스텁의 호스트 단위 지연으로는 순서를 못 뒤집는다):
/// 1번째 응답을 느리게, 2번째를 빠르게 보내 응답 A 가 B 보다 늦게 도착하는 순서를 만든다.
final class RoundRaceURLProtocol: URLProtocol {
    private static let lock = NSLock()
    // ⚠️ **호스트별로** 센다. 전역 카운터로 두면 병렬로 도는 다른 테스트가 같은 프로토콜 클래스를
    //    공유해 시퀀스를 서로 밀어 버린다(실제로 그렇게 빨개졌다).
    private nonisolated(unsafe) static var seqByHost: [String: Int] = [:]
    private nonisolated(unsafe) static var pathsByHost: [String: [String]] = [:]
    private nonisolated(unsafe) static var bodiesByHost: [String: [String]] = [:]

    static func reset(host: String) {
        lock.lock(); seqByHost[host] = 0; pathsByHost[host] = []; bodiesByHost[host] = []; lock.unlock()
    }

    static func paths(host: String) -> [String] { lock.lock(); defer { lock.unlock() }; return pathsByHost[host] ?? [] }
    static func bodies(host: String) -> [String] { lock.lock(); defer { lock.unlock() }; return bodiesByHost[host] ?? [] }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RoundRaceURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url?.path ?? ""
        var body = ""
        if let data = request.httpBody { body = String(data: data, encoding: .utf8) ?? "" }
        else if let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var data = Data()
            let size = 1024
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
            defer { buffer.deallocate() }
            while stream.hasBytesAvailable {
                let n = stream.read(buffer, maxLength: size)
                if n <= 0 { break }
                data.append(buffer, count: n)
            }
            body = String(data: data, encoding: .utf8) ?? ""
        }
        let host = request.url?.host ?? ""
        Self.lock.lock()
        Self.pathsByHost[host, default: []].append(path)
        Self.bodiesByHost[host, default: []].append(body)
        Self.lock.unlock()
        if path.contains("minigame_submit_score") {
            // 제출은 정상 수락으로 답한다 — 이 테스트가 보는 것은 "무엇을 들고 나갔나"이지 서버 판정이 아니다.
            finish(json: #"{"status":"ok","best_score":3,"plays":1,"improved":true}"#, after: 0)
            return
        }
        guard path.contains("minigame_start_round") else {
            finish(json: "[]", after: 0)
            return
        }
        Self.lock.lock(); let n = (Self.seqByHost[host] ?? 0) + 1; Self.seqByHost[host] = n; Self.lock.unlock()
        // 1번째(판 A) = 느림 · 2번째(판 B) = 빠름 → 응답이 뒤집혀 도착한다.
        let token = n == 1 ? "tok-A" : "tok-B"
        let delay: TimeInterval = n == 1 ? 0.30 : 0.02
        finish(json: #"{"status":"ok","token":"\#(token)"}"#, after: delay)
    }

    private func finish(json: String, after delay: TimeInterval) {
        let url = request.url!
        DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                                           headerFields: ["Content-Type": "application/json"])!
            self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            self.client?.urlProtocol(self, didLoad: Data(json.utf8))
            self.client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}

@MainActor
@Test("늦게 도착한 옛 판의 토큰이 지금 판의 토큰을 덮지 않는다")
func aLateTokenFromAFinishedRoundNeverOverwritesTheCurrentOne() async {
    RoundRaceURLProtocol.reset(host: "v0317-round-race")
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://v0317-round-race")!,
        anonKey: "anon-test-key",
        session: RoundRaceURLProtocol.session()
    )
    let store = WorkTimerStore(
        service: service,
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: tkDefaults()
    )
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: tkUserID)

    // 판 A 시작 → 느린 요청이 날아간다.
    store.beginMiniGameRound(kind: .flappy)
    // ⚠️ 고정 시간을 기다리면 부하에서 **도착 순서가 뒤집힌다**(스텁은 도착 순서로 지연을 정한다).
    //    프로토콜이 요청 A 를 실제로 받은 것을 확인하고 나서 B 를 낸다 — 그래야 "A 가 느리다"가 성립한다.
    for _ in 0..<300 where RoundRaceURLProtocol.paths(host: "v0317-round-race")
        .filter({ $0.contains("minigame_start_round") }).isEmpty {
        try? await Task.sleep(for: .milliseconds(10))
    }
    // 판 A 가 끝나고(플래피 즉사) 판 B 시작 → 빠른 요청. 서버에서는 이 순간 토큰 A 가 죽는다.
    store.beginMiniGameRound(kind: .flappy)

    // 두 응답이 모두 도착할 때까지(느린 쪽 0.30s). 부하를 감안해 넉넉히 기다린다.
    for _ in 0..<300 where RoundRaceURLProtocol.paths(host: "v0317-round-race")
        .filter({ $0.contains("minigame_start_round") }).count < 2 {
        try? await Task.sleep(for: .milliseconds(10))
    }
    try? await Task.sleep(for: .milliseconds(600))

    #expect(store.miniGameRoundToken == "tok-B",
            Comment(rawValue: "늦게 온 죽은 토큰이 지금 판의 것을 덮었다 — 들고 있는 값 \(store.miniGameRoundToken ?? "nil")"))
}


// MARK: - ⑥ 짧은 판도 점수가 올라간다 (선발급)

/// 토큰을 **판 시작에** 받으면 플래피 즉사(1초 미만)는 왕복이 못 끝나 점수를 통째로 버린다.
/// 그래서 창을 열 때·게임을 바꿀 때·제출이 끝난 뒤에 **미리** 받아 둔다.
///
/// ★ 일찍 받는 것은 안전한 방향이다: 서버의 시간 하한은 `started_at` 기준이라 토큰이 오래될수록
///   경과가 길어져 **더 관대해진다**. 늦게 받을 때만 정직한 플레이가 막힌다.
@MainActor
@Test("선발급 토큰이 있으면 판 시작이 다시 요청하지 않고, 즉사 판도 올라간다")
func aPrefetchedTokenSurvivesAnInstantRound() async {
    RoundRaceURLProtocol.reset(host: "v0317-prefetch")
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://v0317-prefetch")!,
        anonKey: "anon-test-key",
        session: RoundRaceURLProtocol.session()
    )
    let store = WorkTimerStore(
        service: service,
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: tkDefaults()
    )
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: tkUserID)

    // 창을 열 때처럼 미리 받는다(이 프로토콜의 첫 응답은 0.30s 로 느리다 — 판 시작에 받았다면 즉사 판을 놓친다).
    store.prefetchMiniGameRoundToken(kind: .flappy)
    for _ in 0..<100 where store.miniGameRoundToken == nil { try? await Task.sleep(for: .milliseconds(10)) }
    #expect(store.miniGameRoundToken == "tok-A", "선발급이 안 됐다")

    let beforeStarts = RoundRaceURLProtocol.paths(host: "v0317-prefetch").filter { $0.contains("minigame_start_round") }.count

    // 판 시작 — 이미 쓸 수 있는 토큰이 있으므로 **다시 요청하지 않는다**.
    store.beginMiniGameRound(kind: .flappy)
    try? await Task.sleep(for: .milliseconds(30))
    let afterStarts = RoundRaceURLProtocol.paths(host: "v0317-prefetch").filter { $0.contains("minigame_start_round") }.count
    #expect(afterStarts == beforeStarts,
            "판 시작이 토큰을 다시 받았다 — started_at 이 now() 로 되돌아가 벌어 둔 여유가 사라진다")

    // 즉사: 시작하자마자 끝난다.
    store.recordMiniGameScore(kind: .flappy, score: 3)
    for _ in 0..<100 where !RoundRaceURLProtocol.paths(host: "v0317-prefetch").contains(where: { $0.contains("minigame_submit_score") }) {
        try? await Task.sleep(for: .milliseconds(10))
    }
    let submits = RoundRaceURLProtocol.bodies(host: "v0317-prefetch").filter { $0.contains("p_token") }
    #expect(submits.count == 1, Comment(rawValue: "즉사 판이 안 올라갔다 — 제출 \(submits.count)건"))
    #expect(submits.first?.contains("tok-A") == true, "선발급 토큰이 안 실렸다")
    #expect(store.miniGameSubmitNotice == nil, "올라갔는데 실패 문구가 떴다")
}

/// 선발급이 **실제로 그 세 지점에서** 일어나는지. 행동 테스트는 한 경로만 보므로 소스로 못 박는다.
@Test("창 열기·게임 전환·제출 뒤에 토큰을 미리 받는다")
func prefetchHappensAtTheThreeQuietMoments() throws {
    let code = tkStripped(try #require(tkAllSources()["WorkTimerStoreMiniGame.swift"]))
    let count = code.components(separatedBy: "prefetchMiniGameRoundToken(kind:").count - 1
    // 정의 1 + 호출 5(창 열기 · 게임 전환 · 제출 성공/거절 뒤 · 토큰 없음 · 네트워크 실패)
    #expect(count >= 5, Comment(rawValue: "선발급 지점이 \(count)곳뿐이다 — 짧은 판이 다시 점수를 버린다"))
    let opensWindow = code.contains("prefetchMiniGameRoundToken(kind: miniGameKind) CheckMiniGameWindowController.shared.show()")
    #expect(opensWindow, "창을 열 때 미리 받지 않는다")
}


/// 위 경합의 **가드 자체**를 결정적으로 잰다(네트워크 순서에 안 기댄다).
/// 늦게 온 응답은 자기 세대가 밀렸으면 채택되지 않아야 한다.
@MainActor
@Test("세대가 밀린 응답은 토큰을 대입하지 않는다")
func aStaleGenerationResponseIsDropped() async {
    // ⚠️ **유효한 토큰을 돌려주는 스텁**이어야 한다. 기본 스텁은 이 RPC 에 `[]` 를 주어 디코드가
    //    throw 되고, 그러면 가드를 지워도 덮어쓰지 않아 이 테스트가 통째로 공허해진다(실제로 그랬다).
    let host = "v0317-stale-gen"
    RoundRaceURLProtocol.reset(host: host)
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!,
        anonKey: "anon-test-key",
        session: RoundRaceURLProtocol.session()
    )
    let store = WorkTimerStore(
        service: service,
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: tkDefaults()
    )
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: tkUserID)
    store.miniGameRoundToken = "tok-current"
    store.miniGameRoundTokenKind = .flappy
    store.miniGameRoundTokenAt = Date()
    let current = store.miniGameRoundGeneration

    // 이미 지나간 세대(현재보다 작은 값)로 도착한 응답을 흉내 낸다.
    await store.performBeginMiniGameRound(kind: .flappy, roundGeneration: current - 1)

    #expect(store.miniGameRoundToken == "tok-current",
            "세대가 밀린 응답이 지금 토큰을 덮었다 — 서버에서 이미 죽은 값을 들고 제출하게 된다")
}
