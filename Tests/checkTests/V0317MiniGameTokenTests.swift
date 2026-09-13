import Foundation
import Testing
@testable import check

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

    let requests = URLProtocolStub.requests(forHost: host)
    #expect(requests.isEmpty,
            Comment(rawValue: "토큰이 없는데 요청이 나갔다 — \(requests.map { $0.url?.path ?? "" })"))
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
    #expect(paths == ["/rest/v1/rpc/minigame_submit_score"], Comment(rawValue: "\(paths)"))
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

    #expect(URLProtocolStub.requests(forHost: host).isEmpty, "타이밍바 토큰으로 플래피 점수를 냈다")
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
    let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
    for name in names where name.hasSuffix(".swift") {
        out[name] = try String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)
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
