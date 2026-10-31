import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// v0.3.67 — 미니게임 **역대 최고** 순위(맥). 사용자 결정(2026-10-27): "미니게임 멀티 아닌 3종 에서 역대 최고 점수 랭킹 볼 수 있는
// 창도 만들어줘." → 순위 열 머리의 [오늘 | 역대] 전환 · 역대 = 지금 고른 게임의 사람마다 전체 기간 최고 한 줄.
//
// 이 파일이 지키는 것(층마다 한 묶음):
//   ① 전선(CheckCore) — 요청 본문 키 · 경로 · 원소 단위로 너그러운 디코드 · 정렬 · 날짜 글자
//   ② 스토어 — 처음 넘어갈 때만 받기 · 게임 전환 · 늦은 응답 버리기 · 판 기록 뒤 새로 받기/낡음 표시 · 실패와 재시도 ·
//              서버 함수 부재(PGRST202 · 본문 없는 404)는 '준비 중' · 배열이 아닌 본문은 실패 · 로그아웃
//   ③ 화면 — 두 판의 오프스크린 렌더(ImageRenderer) · 어제 1등·상금은 오늘 판에만 · 날짜 칸 · 빈 상태 넷 · 전환 단추
//   ④ 마이그레이션 계약(CHECK_MIGRATIONS_DIR) — 실행권 · definer · 정렬 축 · 가시성 술어 · 키 목록 = 디코더 키
//
// 네트워크는 이 파일 전용 URLProtocol(호스트마다 대본)로만 나간다 — 창은 띄우지 않는다(`openMiniGameWindow` 를 부르지 않는다:
// 그 함수는 실제 NSWindow 를 화면에 세운다). 스냅숏은 `CHECK_SNAPSHOT_DIR`/v0367-alltime 에 남는다.

private let v67Me = "00000000-0000-0000-0000-000000000002"
private let v67Path = "/rest/v1/rpc/minigame_alltime_board"

// MARK: - 대본 URLProtocol

/// 호스트 · 경로 · (있으면) p_game 별로 응답을 줄 세운다. 줄에 하나 남으면 그 응답을 계속 준다. 대본이 없는 경로는
/// 무해한 기본값(배열 `[]`, 제출 = ok, 판 시작 = 토큰)이다. 요청은 전부 적는다(경로 · 본문 · p_game).
final class V0367AllTimeURLProtocol: URLProtocol {
    struct Reply: Sendable {
        let status: Int
        let body: String
        var delay: Double = 0
    }

    struct Call: Sendable {
        let path: String
        let body: String
        let game: String?
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var queues: [String: [Reply]] = [:]
    nonisolated(unsafe) private static var logs: [String: [Call]] = [:]

    private static func key(_ host: String, _ path: String, _ game: String?) -> String {
        host + "|" + path + "|" + (game ?? "*")
    }

    static func script(_ host: String, path: String = v67Path, game: String? = nil, _ replies: [Reply]) {
        lock.lock(); defer { lock.unlock() }
        queues[key(host, path, game)] = replies
    }

    static func calls(_ host: String, path: String = v67Path) -> [Call] {
        lock.lock(); defer { lock.unlock() }
        return (logs[host] ?? []).filter { $0.path == path }
    }

    static func allCalls(_ host: String) -> [Call] {
        lock.lock(); defer { lock.unlock() }
        return logs[host] ?? []
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [V0367AllTimeURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    private static func bodyText(from request: URLRequest) -> String {
        if let body = request.httpBody { return String(data: body, encoding: .utf8) ?? "" }
        guard let stream = request.httpBodyStream else { return "" }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1024)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: 1024)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private static func defaultReply(for path: String) -> Reply {
        if path.hasSuffix("/minigame_submit_score") {
            return Reply(status: 200, body: #"{"status":"ok","best_score":500,"plays":1,"improved":true}"#)
        }
        if path.hasSuffix("/minigame_start_round") {
            return Reply(status: 200, body: #"{"status":"ok","token":"tok-next"}"#)
        }
        return Reply(status: 200, body: "[]")
    }

    override func startLoading() {
        let host = request.url?.host ?? ""
        let path = request.url?.path ?? ""
        let body = Self.bodyText(from: request)
        let game = (try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any])?["p_game"] as? String
        Self.lock.lock()
        Self.logs[host, default: []].append(Call(path: path, body: body, game: game))
        var reply = Self.defaultReply(for: path)
        for candidate in [Self.key(host, path, game), Self.key(host, path, nil)] {
            guard var queue = Self.queues[candidate], let first = queue.first else { continue }
            reply = first
            if queue.count > 1 {
                queue.removeFirst()
                Self.queues[candidate] = queue
            }
            break
        }
        Self.lock.unlock()
        let response = HTTPURLResponse(
            url: request.url!, statusCode: reply.status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"])!
        let delivery = V0367Delivery(proto: self, response: response, data: Data(reply.body.utf8))
        if reply.delay > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + reply.delay) { delivery.run() }
        } else {
            delivery.run()
        }
    }

    override func stopLoading() {}
}

private final class V0367Delivery: @unchecked Sendable {
    let proto: URLProtocol
    let response: HTTPURLResponse
    let data: Data

    init(proto: URLProtocol, response: HTTPURLResponse, data: Data) {
        self.proto = proto
        self.response = response
        self.data = data
    }

    func run() {
        proto.client?.urlProtocol(proto, didReceive: response, cacheStoragePolicy: .notAllowed)
        proto.client?.urlProtocol(proto, didLoad: data)
        proto.client?.urlProtocolDidFinishLoading(proto)
    }
}

// MARK: - 픽스처

/// 타이밍 바 역대 응답(일부러 서버 정렬을 섞어 둔다 — 클라가 다시 세우는지 본다).
private let v67TimingJSON = """
[
  {"user_id":"aaaaaaaa-0000-0000-0000-00000000000b","display_name":"비","avatar_url":null,"best_score":900,
   "best_at":"2026-09-20T03:00:00+00:00","day":"2026-09-20","center":"busan"},
  {"user_id":"\(v67Me)","display_name":"나야","avatar_url":null,"best_score":950,
   "best_at":"2026-10-01T01:00:00.123456+00:00","day":"2026-10-01","center":null},
  {"user_id":"aaaaaaaa-0000-0000-0000-00000000000a","display_name":"에이","avatar_url":"https://example.com/a.jpg","best_score":900,
   "best_at":"2026-09-13T02:00:00+00:00","day":"2026-09-13","center":"seoul"}
]
"""

private let v67FlappyJSON = """
[{"user_id":"ffffffff-0000-0000-0000-000000000001","display_name":"플래피왕","avatar_url":null,"best_score":77,
  "best_at":"2026-09-30T05:00:00Z","day":"2026-09-30","center":null}]
"""

private let v67TetrisJSON = """
[{"user_id":"eeeeeeee-0000-0000-0000-000000000001","display_name":"테트왕","avatar_url":null,"best_score":1234567,
  "best_at":"2026-10-10T05:00:00Z","day":"2026-10-10","center":null}]
"""

/// PostgREST 가 함수를 못 찾을 때의 실제 모양(404 + PGRST202 + "… in the schema cache").
private let v67PGRST202 = """
{"code":"PGRST202","details":"Searched for the function public.minigame_alltime_board with parameter p_game or with a single unnamed json/jsonb parameter, but no matches were found in the schema cache.","hint":null,"message":"Could not find the function public.minigame_alltime_board(p_game) in the schema cache"}
"""

private func v67OK(_ body: String, delay: Double = 0) -> V0367AllTimeURLProtocol.Reply {
    .init(status: 200, body: body, delay: delay)
}

@MainActor
private func v67InertTokenStore(_ label: String, function: String) -> TokenUsageStore {
    let home = CheckTestScratch.directory("token-" + label, function: function)
    return TokenUsageStore(
        defaults: CheckTestScratch.defaults("token-" + label, function: function),
        homeDirectory: home.appendingPathComponent("home", isDirectory: true),
        cacheURL: home.appendingPathComponent("cache.json", isDirectory: false)
    )
}

/// 대본 네트워크에 물린 로그인 스토어. 창은 열지 않는다(`isMiniGamePanelVisible` 깃발만 필요한 테스트가 직접 세운다).
@MainActor
private func v67Store(host: String, function: String = #function) -> WorkTimerStore {
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!,
        anonKey: "anon-test-key",
        session: V0367AllTimeURLProtocol.session()
    )
    let store = WorkTimerStore(
        service: service,
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: CheckTestScratch.defaults(host, function: function),
        tokenUsage: v67InertTokenStore(host, function: function)
    )
    store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: v67Me)
    store.currentTeamID = URLProtocolStub.stubTeamID
    return store
}

/// 조건이 설 때까지 5ms 씩(상한 3초). 섰으면 true.
@MainActor
@discardableResult
private func v67Wait(_ timeout: Double = 3, _ condition: @MainActor () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return condition()
}

@MainActor
private func v67Settled(_ store: WorkTimerStore) async {
    await v67Wait { !store.miniGameAllTimeLoading && (store.miniGameAllTimeLoaded || store.miniGameAllTimeFailed) }
}

// MARK: - ① 전선

@Suite("v0.3.67 역대 순위 — 전선(CheckCore)")
struct V0367AllTimeWireTests {
    @Test("요청은 POST /rpc/minigame_alltime_board 에 p_game 키 하나만 싣는다 — 세 게임 모두")
    func requestEncodesOnlyTheGameKey() async throws {
        let host = "v67-wire-request"
        let service = SupabaseWorkService(
            projectURL: URL(string: "http://\(host)")!, anonKey: "anon", session: V0367AllTimeURLProtocol.session())
        for kind in [MiniGameKind.timingBar, .flappy, .tetris] {
            _ = try await service.fetchMiniGameAllTimeBoard(accessToken: "t", kind: kind)
        }
        let calls = V0367AllTimeURLProtocol.allCalls(host)
        #expect(calls.map(\.path) == [v67Path, v67Path, v67Path])
        #expect(SupabaseWorkService.miniGameAllTimeBoardPath == v67Path)
        #expect(calls.map(\.game) == ["timing_bar", "flappy", "tetris"])
        for call in calls {
            let json = try #require(try JSONSerialization.jsonObject(with: Data(call.body.utf8)) as? [String: Any])
            #expect(Set(json.keys) == ["p_game"], "본문 키가 p_game 하나가 아니다 — 서버에 DEFAULT 없는 인자라 어긋나면 PGRST202 다: \(json.keys.sorted())")
        }
        let encoded = try JSONEncoderForTests.snake.encode(MiniGameAllTimeBoardRequest(pGame: "tetris"))
        #expect(String(decoding: encoded, as: UTF8.self) == #"{"p_game":"tetris"}"#)
    }

    @Test("원소 하나가 이상해도 배열은 살고, 쓸 수 없는 원소만 버린다(소수 점수·소수초·이름 없음은 받는다)")
    func lossyDecodeKeepsGoodRowsAndDropsUnusableOnes() async throws {
        let host = "v67-wire-lossy"
        V0367AllTimeURLProtocol.script(host, [v67OK("""
            [
              {"user_id":"u1","display_name":"하나","avatar_url":"https://example.com/1.jpg","best_score":99000900,
               "best_at":"2026-09-13T02:00:00.512345+00:00","day":"2026-09-13","center":"seoul"},
              {"user_id":"u2","display_name":null,"best_score":800.0,"best_at":"2026-09-14T02:00:00Z","day":"2026-09-14"},
              {"user_id":"u3","display_name":"점수글자","best_score":"many","day":"2026-09-15"},
              {"display_name":"아이디없음","best_score":700,"day":"2026-09-16"},
              {"user_id":"   ","best_score":600},
              null,
              5,
              {"user_id":"u4","display_name":"날짜이상","best_score":10,"best_at":"어제","day":"2026-9-1","center":"daejeon","extra":true}
            ]
            """)])
        let service = SupabaseWorkService(
            projectURL: URL(string: "http://\(host)")!, anonKey: "anon", session: V0367AllTimeURLProtocol.session())
        let entries = try await service.fetchMiniGameAllTimeBoard(accessToken: "t", kind: .tetris)
        #expect(entries.map(\.userID) == ["u1", "u2", "u4"], "버릴 원소·살릴 원소가 갈렸다: \(entries.map(\.userID))")
        let first = try #require(entries.first)
        #expect(first.bestScore == 99_000_900 && first.bestAt != nil && first.day == "2026-09-13")
        #expect(first.avatarURL?.absoluteString == "https://example.com/1.jpg" && first.center == "서울")
        #expect(first.dayCaption == "9/13")
        #expect(entries[1].name == "사용자" && entries[1].bestScore == 800 && entries[1].bestAt != nil,
                "이름 없음은 '사용자' 로, 정수인 소수 점수는 받는다")
        #expect(entries[2].bestAt == nil && entries[2].dayCaption == nil && entries[2].center == nil,
                "못 읽는 시각·날짜·모르는 센터는 nil 로 접는다(행은 산다)")

        // 배열이 아닌 본문은 **던진다** — 빈 표로 접으면 '아직 기록이 없어요' 와 구별이 안 된다.
        V0367AllTimeURLProtocol.script("v67-wire-object", [v67OK(#"{"status":"ok"}"#)])
        let objectService = SupabaseWorkService(
            projectURL: URL(string: "http://v67-wire-object")!, anonKey: "anon", session: V0367AllTimeURLProtocol.session())
        await #expect(throws: (any Error).self) {
            _ = try await objectService.fetchMiniGameAllTimeBoard(accessToken: "t", kind: .flappy)
        }

        // 디코더 단독: 키 일곱 개가 snake_case 로 매칭된다(서버 jsonb_build_object 키와 같은 목록 — ④ 가 대조한다).
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let row = try decoder.decode(MiniGameAllTimeBoardRow.self, from: Data("""
            {"user_id":"x","display_name":"이름","avatar_url":"https://e.com/x.png","best_score":3,"best_at":"2026-10-01T00:00:00Z","day":"2026-10-01","center":"busan"}
            """.utf8))
        #expect(row == MiniGameAllTimeBoardRow(
            userId: "x", displayName: "이름", avatarUrl: "https://e.com/x.png", bestScore: 3,
            bestAt: "2026-10-01T00:00:00Z", day: "2026-10-01", center: "busan"))
    }

    @Test("정렬: 점수 내림차순 → 먼저 닿은 사람 → user_id(서버와 같은 마지막 축 · 이름이 아니다)")
    func sortingMatchesTheServerAxes() {
        let t0 = Date(timeIntervalSince1970: 1_790_000_000)
        func entry(_ id: String, _ name: String, _ score: Int, _ at: Date?) -> MiniGameAllTimeEntry {
            MiniGameAllTimeEntry(userID: id, name: name, avatarURL: nil, bestScore: score, bestAt: at, day: nil)
        }
        let entries = [
            entry("c", "가나다", 500, t0),
            entry("d", "모름", 500, nil),
            entry("a", "하하", 500, t0),
            entry("b", "가가", 500, t0.addingTimeInterval(-60)),
            entry("e", "꼴찌", 900, t0.addingTimeInterval(9_999))
        ]
        #expect(entries.sortedForMiniGameAllTimeBoard().map(\.userID) == ["e", "b", "a", "c", "d"],
                "같은 점수·같은 시각은 user_id 오름차순이다(이름순이면 c 가 a 보다 앞선다)")
    }

    @Test("날짜 글자: 'YYYY-MM-DD' → 'M/d'(앞자리 0 없음) · 모양이 아니면 nil")
    func dayCaptionFormatsMonthSlashDay() {
        #expect(MiniGameAllTimeEntry.dayCaption("2026-09-13") == "9/13")
        #expect(MiniGameAllTimeEntry.dayCaption("2026-10-01") == "10/1")
        #expect(MiniGameAllTimeEntry.dayCaption("2026-12-31") == "12/31")
        for bad in ["", "2026-9-13", "2026-13-01", "2026-00-10", "2026-09-32", "abcd-ef-gh", "2026/09/13", "２０２６-09-13", "2026-09-13-01"] {
            #expect(MiniGameAllTimeEntry.dayCaption(bad) == nil, "\(bad) 를 날짜로 읽었다")
        }
        #expect(MiniGameAllTimeEntry.dayCaption(nil) == nil)
    }

    @Test("판 이름: [오늘 | 역대] 글자와 머리 제목 — 맥 창의 오늘 제목은 코어 글자 그대로")
    @MainActor
    func scopeLabelsAndTitles() {
        #expect(MiniGameBoardScope.allCases == [.today, .allTime], "전환 단추의 순서는 오늘이 왼쪽이다")
        #expect(MiniGameBoardScope.today.label == "오늘" && MiniGameBoardScope.allTime.label == "역대")
        #expect(MiniGameBoardScope.today.boardTitle == "오늘 순위" && MiniGameBoardScope.allTime.boardTitle == "역대 순위")
        #expect(CheckMiniGameWindowView.rankTitle == "오늘 순위")
        #expect(CheckMiniGameWindowView.allTimeRankTitle == "역대 순위")
    }
}

/// 요청 본문 인코더(서비스와 같은 snake_case 규약).
private enum JSONEncoderForTests {
    static var snake: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }
}

// MARK: - ② 스토어

@Suite("v0.3.67 역대 순위 — 스토어")
@MainActor
struct V0367AllTimeStoreTests {
    @Test("[역대] 로 처음 넘어갈 때 한 번 받고, 오가며 다시 눌러도 그 게임 표가 최신이면 다시 받지 않는다")
    func firstSwitchFetchesOnceAndTogglingDoesNotRefetch() async throws {
        let host = "v67-store-first"
        V0367AllTimeURLProtocol.script(host, game: "timing_bar", [v67OK(v67TimingJSON)])
        let store = v67Store(host: host)
        #expect(store.miniGameBoardScope == .today, "기본은 오늘 판이다")
        try? await Task.sleep(for: .milliseconds(60))
        #expect(V0367AllTimeURLProtocol.calls(host).isEmpty, "[오늘] 만 보는 사람에게 역대 요청이 나갔다")

        store.selectMiniGameBoardScope(.allTime)
        #expect(store.miniGameBoardScope == .allTime)
        #expect(store.miniGameAllTimeLoading, "첫 프레임부터 '불러오는 중…' 이어야 한다")
        await v67Settled(store)
        #expect(store.miniGameAllTimeLoaded && !store.miniGameAllTimeFailed && !store.miniGameAllTimeUnavailable)
        #expect(store.miniGameAllTimeBoard.map(\.userID) == [
            v67Me, "aaaaaaaa-0000-0000-0000-00000000000a", "aaaaaaaa-0000-0000-0000-00000000000b"
        ], "점수 → 먼저 닿은 날 순으로 다시 서야 한다: \(store.miniGameAllTimeBoard.map(\.name))")
        #expect(store.miniGameAllTimeBoard.map(\.dayCaption) == ["10/1", "9/13", "9/20"])
        #expect(store.miniGameAllTimeBoard[1].center == "서울")
        #expect(V0367AllTimeURLProtocol.calls(host).map(\.game) == ["timing_bar"])
        // 내 역대 행(950)은 이 계정의 진짜 전체 기간 최고다 — 로컬 "최고 N" 이 따라 올라간다.
        #expect(store.miniGameBest(.timingBar) == 950)

        store.selectMiniGameBoardScope(.today)
        store.selectMiniGameBoardScope(.allTime)
        store.selectMiniGameBoardScope(.allTime)   // 같은 쪽 재선택은 no-op
        try? await Task.sleep(for: .milliseconds(80))
        #expect(V0367AllTimeURLProtocol.calls(host).count == 1, "오가며 누를 때마다 역대 요청이 나간다")
        #expect(!store.miniGameAllTimeLoading)
    }

    @Test("[역대] 를 보는 중에 게임을 바꾸면 앞 게임의 행을 즉시 비우고 바뀐 게임을 받는다")
    func kindChangeWhileAllTimeShownClearsAndRefetches() async throws {
        let host = "v67-store-kind"
        V0367AllTimeURLProtocol.script(host, game: "timing_bar", [v67OK(v67TimingJSON)])
        V0367AllTimeURLProtocol.script(host, game: "flappy", [v67OK(v67FlappyJSON, delay: 0.25)])
        let store = v67Store(host: host)
        store.selectMiniGameBoardScope(.allTime)
        await v67Settled(store)
        #expect(store.miniGameAllTimeBoard.count == 3)

        store.selectMiniGame(.flappy)
        #expect(store.miniGameAllTimeBoard.isEmpty, "앞 게임의 역대 1등이 '이 게임 1등인 척' 남았다")
        #expect(!store.miniGameAllTimeLoaded && store.miniGameAllTimeLoading)
        await v67Settled(store)
        #expect(store.miniGameAllTimeBoard.map(\.name) == ["플래피왕"])
        #expect(V0367AllTimeURLProtocol.calls(host).map(\.game) == ["timing_bar", "flappy"])
    }

    @Test("[오늘] 을 보는 중에 게임을 바꾸면 역대는 안 받고, 다음에 [역대] 로 넘어갈 때 그 게임을 받는다")
    func kindChangeWhileTodayShownDefersTheFetch() async throws {
        let host = "v67-store-kind-today"
        V0367AllTimeURLProtocol.script(host, game: "timing_bar", [v67OK(v67TimingJSON)])
        V0367AllTimeURLProtocol.script(host, game: "tetris", [v67OK(v67TetrisJSON)])
        let store = v67Store(host: host)
        store.selectMiniGameBoardScope(.allTime)
        await v67Settled(store)
        store.selectMiniGameBoardScope(.today)

        store.selectMiniGame(.tetris)
        #expect(store.miniGameAllTimeBoard.isEmpty && !store.miniGameAllTimeLoading,
                "[오늘] 을 보는데 역대가 '불러오는 중' 으로 섰다")
        try? await Task.sleep(for: .milliseconds(80))
        #expect(V0367AllTimeURLProtocol.calls(host).map(\.game) == ["timing_bar"], "보지도 않는 역대를 받았다")

        store.selectMiniGameBoardScope(.allTime)
        await v67Settled(store)
        #expect(V0367AllTimeURLProtocol.calls(host).map(\.game) == ["timing_bar", "tetris"])
        #expect(store.miniGameAllTimeBoard.map(\.bestScore) == [1_234_567])
    }

    @Test("응답이 오는 사이 게임을 바꿨으면 늦게 온 앞 게임 응답은 버린다")
    func lateResponseForThePreviousKindIsDropped() async throws {
        let host = "v67-store-stale"
        V0367AllTimeURLProtocol.script(host, game: "timing_bar", [v67OK(v67TimingJSON, delay: 0.3)])
        V0367AllTimeURLProtocol.script(host, game: "flappy", [v67OK(v67FlappyJSON)])
        let store = v67Store(host: host)
        store.selectMiniGameBoardScope(.allTime)
        // 타이밍 바 요청이 **나간 뒤에** 게임을 바꾼다 — 그 전에 바꾸면 첫 Task 가 바뀐 게임을 읽어 늦은 응답 자체가 안 생긴다.
        #expect(await v67Wait { V0367AllTimeURLProtocol.calls(host).count == 1 })
        #expect(V0367AllTimeURLProtocol.calls(host).first?.game == "timing_bar")
        store.selectMiniGame(.flappy)
        await v67Settled(store)
        // 늦은 타이밍 바 응답까지 다 도착한 뒤에 본다.
        await v67Wait { V0367AllTimeURLProtocol.calls(host).count == 2 }
        try? await Task.sleep(for: .milliseconds(450))
        #expect(store.miniGameKind == .flappy)
        #expect(store.miniGameAllTimeBoard.map(\.name) == ["플래피왕"],
                "늦게 온 타이밍 바 역대가 플래피 자리에 덮였다: \(store.miniGameAllTimeBoard.map(\.name))")
        #expect(store.miniGameBest(.flappy) == 0 && store.miniGameBest(.timingBar) == 0,
                "버려야 할 응답의 내 행으로 로컬 최고를 올렸다")
        #expect(!store.miniGameAllTimeLoading)
    }

    @Test("[역대] 를 보는 중에 판이 기록되면 오늘 순위 뒤에 역대를 다시 받는다")
    func recordedRoundRefreshesTheAllTimeBoardWhenShown() async throws {
        let host = "v67-store-round"
        V0367AllTimeURLProtocol.script(host, game: "timing_bar", [v67OK("[]"), v67OK(v67TimingJSON)])
        let store = v67Store(host: host)
        store.isMiniGamePanelVisible = true   // 창 깃발만 — 실제 창은 띄우지 않는다
        store.selectMiniGameBoardScope(.allTime)
        await v67Settled(store)
        #expect(store.miniGameAllTimeBoard.isEmpty && store.miniGameAllTimeLoaded)

        store.miniGameRoundToken = "tok-round"
        store.miniGameRoundTokenKind = .timingBar
        store.miniGameRoundTokenAt = Date()
        store.recordMiniGameScore(kind: .timingBar, score: 950)
        let refreshed = await v67Wait { V0367AllTimeURLProtocol.calls(host).count == 2 && !store.miniGameAllTimeLoading }
        #expect(refreshed, "판이 기록됐는데 [역대] 를 다시 받지 않았다")
        #expect(store.miniGameAllTimeBoard.first?.userID == v67Me, "새 개인 최고가 역대 표에 안 들어왔다")
        // 순서: 제출 → (선발급) → 오늘 순위 → 역대. 역대가 오늘 순위보다 먼저 나가면 다음 판 토큰·오늘 순위가 늦어진다.
        let paths = V0367AllTimeURLProtocol.allCalls(host).map(\.path)
        let submit = try #require(paths.firstIndex(of: "/rest/v1/rpc/minigame_submit_score"))
        let todayBoard = try #require(paths.lastIndex(of: "/rest/v1/rpc/minigame_board"))
        let allTime = try #require(paths.lastIndex(of: v67Path))
        #expect(submit < todayBoard && todayBoard < allTime, "요청 순서가 제출 → 오늘 → 역대가 아니다: \(paths)")
    }

    @Test("[오늘] 을 보는 중에 판이 기록되면 역대는 안 받고 낡음만 표시한다 — 다음에 [역대] 로 넘어가면 받는다")
    func recordedRoundWhileTodayShownMarksStaleWithoutFetching() async throws {
        let host = "v67-store-round-today"
        V0367AllTimeURLProtocol.script(host, game: "timing_bar", [v67OK("[]"), v67OK(v67TimingJSON)])
        let store = v67Store(host: host)
        store.isMiniGamePanelVisible = true
        store.selectMiniGameBoardScope(.allTime)
        await v67Settled(store)
        store.selectMiniGameBoardScope(.today)

        store.miniGameRoundToken = "tok-round-today"
        store.miniGameRoundTokenKind = .timingBar
        store.miniGameRoundTokenAt = Date()
        store.recordMiniGameScore(kind: .timingBar, score: 950)
        await v67Wait { V0367AllTimeURLProtocol.allCalls(host).contains { $0.path == "/rest/v1/rpc/minigame_board" } }
        try? await Task.sleep(for: .milliseconds(120))
        #expect(V0367AllTimeURLProtocol.calls(host).count == 1, "[오늘] 을 보는데 판마다 역대를 받았다")

        store.selectMiniGameBoardScope(.allTime)
        await v67Wait { V0367AllTimeURLProtocol.calls(host).count == 2 && !store.miniGameAllTimeLoading }
        #expect(V0367AllTimeURLProtocol.calls(host).count == 2, "낡은 역대 표를 그대로 보여 줬다(판 기록 뒤 다시 안 받았다)")
        #expect(store.miniGameAllTimeBoard.first?.userID == v67Me)
    }

    @Test("실패: 표가 없으면 실패 + [다시 시도] 이고, 다시 시도가 살린다 · 이미 그린 표는 실패해도 남는다")
    func failureMarksFailedAndRetryRecovers() async throws {
        let host = "v67-store-fail"
        V0367AllTimeURLProtocol.script(host, game: "timing_bar", [
            .init(status: 500, body: #"{"message":"boom"}"#), v67OK(v67TimingJSON), .init(status: 503, body: "")
        ])
        let store = v67Store(host: host)
        store.selectMiniGameBoardScope(.allTime)
        await v67Settled(store)
        #expect(store.miniGameAllTimeFailed && !store.miniGameAllTimeLoaded && !store.miniGameAllTimeLoading)
        #expect(!store.miniGameAllTimeUnavailable, "5xx 를 '준비 중' 으로 접었다 — 사용자가 다시 시도할 길이 사라진다")
        #expect(store.miniGameAllTimeBoard.isEmpty)

        store.loadMiniGameAllTimeBoard()   // [다시 시도]
        await v67Wait { store.miniGameAllTimeLoaded && !store.miniGameAllTimeLoading }
        #expect(!store.miniGameAllTimeFailed && store.miniGameAllTimeBoard.count == 3)

        // 새로 받기가 실패해도 이미 그린 표는 지우지 않는다(일시 장애 한 번에 순위가 깜빡이지 않게).
        await store.performLoadMiniGameAllTimeBoard()
        #expect(store.miniGameAllTimeFailed && store.miniGameAllTimeLoaded && store.miniGameAllTimeBoard.count == 3)
    }

    @Test("실패한 채 [오늘] 갔다가 [역대] 로 돌아오면 한 번 더 받는다(보러 온 것이 곧 재시도 의사)")
    func returningToAFailedAllTimeBoardRetries() async throws {
        let host = "v67-store-fail-return"
        V0367AllTimeURLProtocol.script(host, game: "timing_bar", [.init(status: 500, body: "{}"), v67OK(v67TimingJSON)])
        let store = v67Store(host: host)
        store.selectMiniGameBoardScope(.allTime)
        await v67Settled(store)
        #expect(store.miniGameAllTimeFailed)
        store.selectMiniGameBoardScope(.today)
        store.selectMiniGameBoardScope(.allTime)
        await v67Wait { store.miniGameAllTimeLoaded && !store.miniGameAllTimeLoading }
        #expect(V0367AllTimeURLProtocol.calls(host).count == 2 && store.miniGameAllTimeBoard.count == 3)
    }

    @Test("서버에 함수가 없으면(404 PGRST202 · 본문 없는 404) 실패가 아니라 조용한 '준비 중' 이고, 오가며 눌러도 다시 두드리지 않는다")
    func missingFunctionIsAQuietUnavailableState() async throws {
        for (host, reply) in [
            ("v67-store-pgrst202", V0367AllTimeURLProtocol.Reply(status: 404, body: v67PGRST202)),
            ("v67-store-bare404", V0367AllTimeURLProtocol.Reply(status: 404, body: ""))
        ] {
            V0367AllTimeURLProtocol.script(host, [reply])
            let store = v67Store(host: host)
            store.selectMiniGameBoardScope(.allTime)
            await v67Settled(store)
            #expect(store.miniGameAllTimeUnavailable, "\(host): 함수 부재가 '준비 중' 으로 안 접혔다")
            #expect(store.miniGameAllTimeLoaded && !store.miniGameAllTimeFailed && !store.miniGameAllTimeLoading,
                    "\(host): 함수 부재에 실패 문구·[다시 시도] 가 섰다 — 사용자가 고칠 수 없는 일이다")
            #expect(store.miniGameAllTimeBoard.isEmpty)
            store.selectMiniGameBoardScope(.today)
            store.selectMiniGameBoardScope(.allTime)
            try? await Task.sleep(for: .milliseconds(80))
            #expect(V0367AllTimeURLProtocol.calls(host).count == 1, "\(host): 404 를 오갈 때마다 다시 두드린다(오류 고리)")
        }
    }

    @Test("배열이 아닌 본문은 실패다(빈 표로 접지 않는다)")
    func nonArrayBodyIsAFailure() async throws {
        let host = "v67-store-object"
        V0367AllTimeURLProtocol.script(host, [v67OK(#"{"status":"ok","rows":[]}"#)])
        let store = v67Store(host: host)
        store.selectMiniGameBoardScope(.allTime)
        await v67Settled(store)
        #expect(store.miniGameAllTimeFailed && !store.miniGameAllTimeLoaded && !store.miniGameAllTimeUnavailable)
    }

    @Test("로그아웃은 역대 행·깃발을 비우고 보기 선택은 남긴다(앱 실행의 것)")
    func signOutClearsTheBoardButKeepsTheScope() async throws {
        let host = "v67-store-signout"
        V0367AllTimeURLProtocol.script(host, game: "timing_bar", [v67OK(v67TimingJSON)])
        let store = v67Store(host: host)
        store.selectMiniGameBoardScope(.allTime)
        await v67Settled(store)
        #expect(!store.miniGameAllTimeBoard.isEmpty)
        store.signOut()
        #expect(store.miniGameAllTimeBoard.isEmpty && !store.miniGameAllTimeLoaded && !store.miniGameAllTimeLoading)
        #expect(!store.miniGameAllTimeFailed && !store.miniGameAllTimeUnavailable && store.miniGameAllTimeFreshKind == nil)
        #expect(store.miniGameBoardScope == .allTime)
    }

    @Test("창 열기(소스 계약): [역대] 를 보던 채면 다시 받고, [오늘] 이면 역대를 건드리지 않는다")
    func windowOpenRefreshesOnlyWhenAllTimeIsShown() throws {
        // openMiniGameWindow 는 실제 NSWindow 를 세운다 — 에이전트 규칙상 부르지 않고 본문으로 잰다(주석을 걷고).
        let source = v67StripComments(try v67Source("WorkTimerStoreMiniGame.swift"))
        let open = try #require(v67FunctionBody(source, name: "openMiniGameWindow"))
        let normalized = v67Collapse(open)
        #expect(normalized.contains("if miniGameBoardScope == .allTime { if !miniGameAllTimeLoaded { miniGameAllTimeLoading = true } loadMiniGameAllTimeBoard() }"),
                "창 열기의 역대 새로 받기가 [역대] 조건 아래에 있지 않다")
        #expect(normalized.components(separatedBy: "loadMiniGameAllTimeBoard()").count - 1 == 1)
        // 30초 루프에는 얹지 않는다(오늘 순위와 같은 규약).
        let store = v67StripComments(try v67Source("WorkTimerStore.swift"))
        let loop = try #require(v67FunctionBody(store, name: "startRefreshLoopTask"))
        #expect(!loop.contains("AllTime"), "30초 refresh 루프에 역대 조회가 얹혔다")
    }
}

// MARK: - ③ 화면(오프스크린 렌더)

private enum V67RenderError: Error { case failed }

@MainActor
private enum V67Geometry {
    // v0.3.69 — 게임 구역이 왼쪽 사이드바만큼 밀렸다(`gameColumnOrigin.x` = 사이드바 188 + 여백 14).
    static let rankLeft = MiniGameWindowLayout.gameColumnOrigin.x + MiniGameWindowLayout.canvasSize.width + MiniGameWindowLayout.columnSpacing
    static let rankRight = rankLeft + MiniGameWindowLayout.rankWidth
    static let bodyTop = MiniGameWindowLayout.contentPadding + MiniGameWindowLayout.headerHeight + MiniGameWindowLayout.headerSpacing
    static let footerBottom = MiniGameWindowLayout.contentPadding + MiniGameWindowLayout.innerSize.height - MiniGameWindowLayout.footerBaselineGap
    static let footerTop = footerBottom - MiniGameWindowLayout.prizeHeight
    /// 행 오른쪽 끝(패딩 안쪽) · 점수 칸 · 날짜 칸(pt).
    static let rowRight = rankRight - MiniGameRankRow.trailingPadding
    static let scoreLeft = rowRight - MiniGameRankRow.scoreWidth
    static let dateRight = scoreLeft - MiniGameRankRow.columnSpacing
    static let dateLeft = dateRight - MiniGameRankRow.dateWidth
}

@MainActor
private func v67RenderStore(function: String = #function, line: Int = #line) -> WorkTimerStore {
    let host = "v67-render-\(line)"
    let store = v67Store(host: host, function: function)
    store.isMiniGamePanelVisible = true
    return store
}

@MainActor
private func v67TodayRows(_ count: Int) -> [MiniGameBoardEntry] {
    (0..<count).map { i in
        MiniGameBoardEntry(userID: i == 1 ? v67Me : "t\(i)", name: i == 1 ? "나야" : "오늘\(i)", avatarURL: nil,
                           bestScore: 990 - i * 37, bestAt: Date(timeIntervalSince1970: 1_790_000_000 + Double(i) * 60), plays: i + 1)
    }
}

@MainActor
private func v67AllTimeRows(_ count: Int, includeMe: Bool = true, days: Bool = true) -> [MiniGameAllTimeEntry] {
    let dayKeys = ["2026-09-13", "2026-09-08", "2026-10-21", "2026-09-30", "2026-10-02", "2026-09-23",
                   "2026-10-11", "2026-09-19", "2026-10-26", "2026-09-27", "2026-10-05", "2026-09-15"]
    return (0..<count).map { i in
        let isMe = includeMe && i == 2
        return MiniGameAllTimeEntry(
            userID: isMe ? v67Me : "h\(i)", name: isMe ? "나야" : "명예\(i)",
            avatarURL: i == 0 ? CheckMascotAssets.url(for: .neutral) : nil,
            bestScore: 1000 - i * 41, bestAt: Date(timeIntervalSince1970: 1_789_000_000 + Double(i) * 3_600),
            day: days ? dayKeys[i % dayKeys.count] : nil, center: i == 3 ? "서울" : nil)
    }
}

@MainActor
private func v67Bitmap(_ store: WorkTimerStore) throws -> NSBitmapImageRep {
    let view = CheckMiniGameWindowView(store: store, clipsOverflowInsteadOfScroll: true)
        .background(CheckTheme.background)
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff)
    else { throw V67RenderError.failed }
    return bitmap
}

@MainActor
private func v67NaturalBitmap(_ view: some View) throws -> NSBitmapImageRep {
    let renderer = ImageRenderer(content: view.fixedSize().background(CheckTheme.background))
    renderer.scale = 2
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff)
    else { throw V67RenderError.failed }
    return bitmap
}

private func v67Save(_ bitmap: NSBitmapImageRep, _ name: String) {
    MiniGameSnapshots.save(bitmap, name: "\(name).png", sub: "v0367-alltime")
}

/// 두 비트맵이 다른 픽셀의 경계 상자(px). 같으면 nil.
private func v67DiffBounds(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep, tolerance: Int = 8) -> (minX: Int, minY: Int, maxX: Int, maxY: Int)? {
    guard a.pixelsWide == b.pixelsWide, a.pixelsHigh == b.pixelsHigh, let pa = a.bitmapData, let pb = b.bitmapData else { return nil }
    let bpr = a.bytesPerRow, spp = a.samplesPerPixel
    var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
    for y in 0..<a.pixelsHigh {
        for x in 0..<a.pixelsWide {
            let offset = y * bpr + x * spp
            for sample in 0..<min(spp, 3) where abs(Int(pa[offset + sample]) - Int(pb[offset + sample])) > tolerance {
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                break
            }
        }
    }
    guard maxX >= 0 else { return nil }
    return (minX, minY, maxX, maxY)
}

/// pt 사각형 안에서 조건을 만족하는 픽셀 수.
private func v67Count(_ bitmap: NSBitmapImageRep, _ rect: CGRect, where predicate: (Int, Int, Int) -> Bool) -> Int {
    guard let data = bitmap.bitmapData, bitmap.samplesPerPixel >= 3 else { return 0 }
    let bpr = bitmap.bytesPerRow, spp = bitmap.samplesPerPixel
    let x0 = max(0, Int(rect.minX * 2)), x1 = min(bitmap.pixelsWide - 1, Int(rect.maxX * 2))
    let y0 = max(0, Int(rect.minY * 2)), y1 = min(bitmap.pixelsHigh - 1, Int(rect.maxY * 2))
    guard x0 <= x1, y0 <= y1 else { return 0 }
    var count = 0
    for y in y0...y1 {
        for x in x0...x1 {
            let offset = y * bpr + x * spp
            if predicate(Int(data[offset]), Int(data[offset + 1]), Int(data[offset + 2])) { count += 1 }
        }
    }
    return count
}

/// pt 사각형 안에서 두 비트맵이 다른 픽셀 수.
private func v67DiffCount(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep, _ rect: CGRect, tolerance: Int = 8) -> Int {
    guard a.pixelsWide == b.pixelsWide, a.pixelsHigh == b.pixelsHigh, let pa = a.bitmapData, let pb = b.bitmapData else { return -1 }
    let bpr = a.bytesPerRow, spp = a.samplesPerPixel
    let x0 = max(0, Int(rect.minX * 2)), x1 = min(a.pixelsWide - 1, Int(rect.maxX * 2))
    let y0 = max(0, Int(rect.minY * 2)), y1 = min(a.pixelsHigh - 1, Int(rect.maxY * 2))
    var count = 0
    for y in y0...y1 {
        for x in x0...x1 {
            let offset = y * bpr + x * spp
            if (0..<min(spp, 3)).contains(where: { abs(Int(pa[offset + $0]) - Int(pb[offset + $0])) > tolerance }) { count += 1 }
        }
    }
    return count
}

/// accent(파랑) 잉크. `V0246MiniGameHubRenderTests.mgIsAccentish` 와 같은 판정.
private func v67IsAccentish(_ r: Int, _ g: Int, _ b: Int) -> Bool { b > r + 40 && b > 90 }
/// 상금 트로피(pending · 주황) 잉크.
private func v67IsPrizeOrange(_ r: Int, _ g: Int, _ b: Int) -> Bool { r > 190 && g > 120 && g < 210 && b < 120 }

@Suite("v0.3.67 역대 순위 — 미니게임 창(오프스크린 렌더)")
@MainActor
struct V0367AllTimePanelTests {
    @Test("두 판 모두 창(888×470)을 채우고, 오늘 ↔ 역대 전환이 바꾸는 것은 순위 열뿐이다")
    func bothScopesRenderAndOnlyTheRankColumnChanges() throws {
        defer { MiniGameSpaceKey.remove() }
        let store = v67RenderStore()
        store.miniGameBoard = v67TodayRows(6)
        store.miniGameBoardLoaded = true
        store.miniGameYesterdayWinner = MiniGameWinner(day: "2026-10-26", userID: "t9", name: "어제왕", avatarURL: nil, score: 977, awarded: true)
        store.miniGameAllTimeBoard = v67AllTimeRows(7)
        store.miniGameAllTimeLoaded = true

        store.miniGameBoardScope = .today
        let today = try v67Bitmap(store)
        store.miniGameBoardScope = .allTime
        let allTime = try v67Bitmap(store)
        let size = MiniGameWindowLayout.contentSize
        for (name, bitmap) in [("v0367-today", today), ("v0367-alltime", allTime)] {
            #expect(bitmap.pixelsWide == Int(size.width) * 2 && bitmap.pixelsHigh == Int(size.height) * 2,
                    "\(name) 크기가 \(bitmap.pixelsWide)×\(bitmap.pixelsHigh)px 다")
            v67Save(bitmap, name)
        }
        let diff = try #require(v67DiffBounds(today, allTime), "오늘·역대 판이 같은 그림이다")
        #expect(Double(diff.minX) / 2 >= Double(V67Geometry.rankLeft) - 1,
                "판 전환이 게임 열까지 다시 칠했다(minX \(Double(diff.minX) / 2)pt)")
        // 머리 제목·전환 단추가 바뀐다(머리 띠 안에 차이가 있다).
        let header = CGRect(x: V67Geometry.rankLeft, y: MiniGameWindowLayout.contentPadding,
                            width: MiniGameWindowLayout.rankWidth, height: MiniGameWindowLayout.headerHeight)
        #expect(v67DiffCount(today, allTime, header) > 40, "머리 제목·전환 단추가 판을 따라 안 바뀐다")

        // 넘치는 역대(12명 — 무스크롤 10행 초과)와 50명 머리(인원 칩 두 자리)도 남긴다.
        store.miniGameAllTimeBoard = v67AllTimeRows(12)
        v67Save(try v67Bitmap(store), "v0367-alltime-overflow")
    }

    @Test("어제 1등 카드는 [역대] 에 없다(대조군: [오늘] 에서는 그 카드가 그림을 바꾼다)")
    func championCardBelongsToTheTodayBoardOnly() throws {
        defer { MiniGameSpaceKey.remove() }
        let winner = MiniGameWinner(day: "2026-10-26", userID: "t9", name: "어제왕", avatarURL: nil, score: 977, awarded: true)
        func render(_ scope: MiniGameBoardScope, winner: MiniGameWinner?) throws -> NSBitmapImageRep {
            let store = v67RenderStore()
            store.miniGameBoard = v67TodayRows(3)
            store.miniGameBoardLoaded = true
            store.miniGameAllTimeBoard = v67AllTimeRows(3, includeMe: false)
            store.miniGameAllTimeLoaded = true
            store.miniGameYesterdayWinner = winner
            store.miniGameBoardScope = scope
            return try v67Bitmap(store)
        }
        // 대조군 — 같은 비교가 [오늘] 에서는 갈려야 이 테스트가 무엇이든 잰다.
        #expect(v67DiffBounds(try render(.today, winner: winner), try render(.today, winner: nil)) != nil,
                "대조군이 죽었다: [오늘] 에서도 어제 1등 카드가 아무것도 안 그린다")
        #expect(v67DiffBounds(try render(.allTime, winner: winner), try render(.allTime, winner: nil)) == nil,
                "[역대] 판에 어제 1등 카드가 섰다 — 상금·어제 1등은 오늘 판의 것이다")
        // 그리고 [역대] 는 카드가 비운 48pt 를 순위 행이 쓴다(무스크롤 10행).
        #expect(MiniGameWindowLayout.visibleRows(hasChampionRow: false) == 10)
    }

    @Test("바닥 안내: [오늘] 은 상금(트로피) · [역대] 는 같은 크기 카드에 상금 이야기가 없다")
    func prizeFooterIsReplacedOnTheAllTimeBoard() throws {
        defer { MiniGameSpaceKey.remove() }
        let store = v67RenderStore()
        store.miniGameBoard = v67TodayRows(5)
        store.miniGameBoardLoaded = true
        store.miniGameAllTimeBoard = v67AllTimeRows(5)
        store.miniGameAllTimeLoaded = true
        store.miniGameBoardScope = .today
        let today = try v67Bitmap(store)
        store.miniGameBoardScope = .allTime
        let allTime = try v67Bitmap(store)
        let footer = CGRect(x: V67Geometry.rankLeft, y: V67Geometry.footerTop,
                            width: MiniGameWindowLayout.rankWidth, height: MiniGameWindowLayout.prizeHeight)
        #expect(v67Count(today, footer, where: v67IsPrizeOrange) > 20, "대조군이 죽었다: [오늘] 바닥에 트로피가 없다")
        #expect(v67Count(allTime, footer, where: v67IsPrizeOrange) == 0, "[역대] 바닥에 상금 트로피가 남았다")
        #expect(v67DiffCount(today, allTime, footer) > 200, "[역대] 바닥 안내가 오늘 것과 같다")
        // 카드 껍데기는 남는다 — 바닥 띠 왼쪽 위 모서리 안쪽(테두리 · fieldFill)이 두 판에서 같다.
        let corner = CGRect(x: V67Geometry.rankLeft + 2, y: V67Geometry.footerTop + 2, width: 6, height: 6)
        #expect(v67DiffCount(today, allTime, corner, tolerance: 4) == 0, "[역대] 바닥 카드의 크기·껍데기가 달라졌다")
    }

    @Test("[역대] 행은 점수 앞 고정 칸에 날짜('9/13')를 그리고, 점수 칸은 움직이지 않는다")
    func allTimeRowsDrawTheDateInItsOwnColumn() throws {
        defer { MiniGameSpaceKey.remove() }
        func render(days: Bool) throws -> NSBitmapImageRep {
            let store = v67RenderStore()
            store.miniGameAllTimeBoard = v67AllTimeRows(4, includeMe: false, days: days)
            store.miniGameAllTimeLoaded = true
            store.miniGameBoardScope = .allTime
            return try v67Bitmap(store)
        }
        let with = try render(days: true)
        let without = try render(days: false)
        let diff = try #require(v67DiffBounds(with, without), "날짜가 있으나 없으나 행이 같다 — 날짜를 안 그린다")
        let minX = Double(diff.minX) / 2, maxX = Double(diff.maxX) / 2
        #expect(minX >= Double(V67Geometry.dateLeft) - 2 && maxX <= Double(V67Geometry.dateRight) + 2,
                "날짜 차이가 날짜 칸(\(V67Geometry.dateLeft)…\(V67Geometry.dateRight)pt) 밖이다: \(minX)…\(maxX)pt — 점수나 이름이 밀렸다")
        let top = Double(diff.minY) / 2
        #expect(top >= Double(V67Geometry.bodyTop) - 1, "날짜가 머리글에 그려졌다")
        v67Save(with, "v0367-alltime-dates")
    }

    @Test("[역대] 에서도 내 행은 accent 로 강조된다(같은 행 · 보는 사람만 바꿔 잰다)")
    func myRowIsHighlightedOnTheAllTimeBoard() throws {
        defer { MiniGameSpaceKey.remove() }
        // 행은 **똑같이** 두고 로그인한 사람만 바꾼다 — 행을 바꾸면 이름·아바타 색이 같이 바뀌어 강조가 아니라 아바타를 잰다
        // (2026-10-27 뮤테이션 실측: isMe 를 지워도 초록이었다 — 보라색 '나' 아바타가 accent 판정에 걸렸다).
        func render(viewer: String) throws -> NSBitmapImageRep {
            let store = v67RenderStore()
            store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: viewer)
            store.miniGameAllTimeBoard = v67AllTimeRows(4, includeMe: true)
            store.miniGameAllTimeLoaded = true
            store.miniGameBoardScope = .allTime
            return try v67Bitmap(store)
        }
        let mine = try render(viewer: v67Me)
        let other = try render(viewer: "99999999-0000-0000-0000-000000000099")
        // 내 행(3위) 한 줄만 잰다.
        let myRow = CGRect(x: V67Geometry.rankLeft, y: V67Geometry.bodyTop + 2 * (MiniGameWindowLayout.rowHeight + MiniGameWindowLayout.rowSpacing),
                           width: MiniGameWindowLayout.rankWidth, height: MiniGameWindowLayout.rowHeight)
        let accentMine = v67Count(mine, myRow, where: v67IsAccentish)
        let accentOther = v67Count(other, myRow, where: v67IsAccentish)
        #expect(accentMine > accentOther + 100, "내 역대 행에 accent 강조가 없다(\(accentMine) vs \(accentOther))")
        #expect(v67DiffCount(mine, other, myRow) > 100, "보는 사람이 바뀌어도 내 행이 같은 그림이다")
    }

    @Test("빈 [역대] 넷: 불러오는 중 · 실패([다시 시도]) · 준비 중([다시 시도] 없음) · 아직 없음 — 서로 다른 그림")
    func emptyAllTimeStatesAreDistinctAndOnlyFailureOffersRetry() throws {
        defer { MiniGameSpaceKey.remove() }
        func render(loaded: Bool, failed: Bool, unavailable: Bool) throws -> NSBitmapImageRep {
            let store = v67RenderStore()
            store.miniGameBoard = v67TodayRows(3)
            store.miniGameBoardLoaded = true
            store.miniGameBoardScope = .allTime
            store.miniGameAllTimeLoaded = loaded
            store.miniGameAllTimeFailed = failed
            store.miniGameAllTimeUnavailable = unavailable
            store.miniGameAllTimeLoading = !loaded && !failed
            return try v67Bitmap(store)
        }
        let loading = try render(loaded: false, failed: false, unavailable: false)
        let failed = try render(loaded: false, failed: true, unavailable: false)
        let unavailable = try render(loaded: true, failed: false, unavailable: true)
        let empty = try render(loaded: true, failed: false, unavailable: false)
        let shots = [("v0367-alltime-loading", loading), ("v0367-alltime-failed", failed),
                     ("v0367-alltime-unavailable", unavailable), ("v0367-alltime-empty", empty)]
        for (name, bitmap) in shots { v67Save(bitmap, name) }
        for i in 0..<shots.count {
            for j in (i + 1)..<shots.count {
                #expect(v67DiffBounds(shots[i].1, shots[j].1) != nil, "\(shots[i].0) 와 \(shots[j].0) 가 같은 그림이다")
            }
        }
        // 빈 안내 카드 자리(본문 윗변부터 1.5행)의 accent = [다시 시도] 단추. 실패만 단다.
        let card = CGRect(x: V67Geometry.rankLeft, y: V67Geometry.bodyTop, width: MiniGameWindowLayout.rankWidth,
                          height: MiniGameWindowLayout.rowHeight * 1.5)
        let retryFailed = v67Count(failed, card, where: v67IsAccentish)
        #expect(retryFailed > 60, "실패한 [역대] 에 [다시 시도] 가 없다(accent \(retryFailed)px)")
        for (name, bitmap) in [("준비 중", unavailable), ("불러오는 중", loading), ("아직 없음", empty)] {
            let accent = v67Count(bitmap, card, where: v67IsAccentish)
            #expect(accent < 10, "\(name) 에 [다시 시도] 가 섰다(accent \(accent)px) — 고칠 수 없는 일에 재시도를 주지 않는다")
        }
    }

    @Test("전환 단추: 한 캡슐 두 칸 · 고른 칸만 accent · 머리글 314pt 안에 선다")
    func scopePickerDrawsTheSelectionAndFits() throws {
        defer { MiniGameSpaceKey.remove() }
        let today = try v67NaturalBitmap(MiniGameBoardScopePicker(selected: .today) { _ in })
        let allTime = try v67NaturalBitmap(MiniGameBoardScopePicker(selected: .allTime) { _ in })
        v67Save(today, "v0367-picker-today")
        v67Save(allTime, "v0367-picker-alltime")
        let width = Double(today.pixelsWide) / 2
        #expect(width <= 100, "전환 단추가 \(width)pt 다 — 제목·인원 칩과 314pt 머리글에 같이 못 선다")
        #expect(today.pixelsWide == allTime.pixelsWide, "고른 칸에 따라 단추 폭이 흔들린다")
        let w = CGFloat(today.pixelsWide) / 2, h = CGFloat(today.pixelsHigh) / 2
        let left = CGRect(x: 0, y: 0, width: w / 2, height: h), right = CGRect(x: w / 2, y: 0, width: w / 2, height: h)
        #expect(v67Count(today, left, where: v67IsAccentish) > v67Count(today, right, where: v67IsAccentish) + 20,
                "[오늘] 을 골랐는데 왼쪽 칸이 강조되지 않았다")
        #expect(v67Count(allTime, right, where: v67IsAccentish) > v67Count(allTime, left, where: v67IsAccentish) + 20,
                "[역대] 를 골랐는데 오른쪽 칸이 강조되지 않았다")

        // 창 안에서: 50명(두 자리 인원 칩)이어도 단추가 순위 열 오른쪽 끝 안에 선다.
        let store = v67RenderStore()
        store.miniGameAllTimeBoard = v67AllTimeRows(50)
        store.miniGameAllTimeLoaded = true
        store.miniGameBoardScope = .allTime
        let window = try v67Bitmap(store)
        let header = CGRect(x: V67Geometry.rankLeft - 20, y: MiniGameWindowLayout.contentPadding,
                            width: MiniGameWindowLayout.rankWidth + 34, height: MiniGameWindowLayout.headerHeight)
        let accent = v67Count(window, header, where: v67IsAccentish)
        #expect(accent > 20, "창 머리글에 전환 단추가 안 보인다")
        let insideOnly = CGRect(x: V67Geometry.rankRight + 1, y: header.minY, width: 13, height: header.height)
        #expect(v67Count(window, insideOnly, where: v67IsAccentish) == 0, "전환 단추가 순위 열 밖으로 넘쳤다")
        v67Save(window, "v0367-alltime-50")
    }

    @Test("화면 배선(소스 계약): 단추가 스토어 전환을 부르고, 어제 1등·레이아웃·바닥이 판을 따른다")
    func panelWiringFollowsTheScope() throws {
        let panel = v67Collapse(v67StripComments(try v67Source("MiniGamePanel.swift")))
        #expect(panel.contains("MiniGameBoardScopePicker(selected: store.miniGameBoardScope) { scope in store.selectMiniGameBoardScope(scope) }"),
                "전환 단추가 스토어의 selectMiniGameBoardScope 를 안 부른다")
        #expect(panel.contains("MiniGameWindowLayout.layout(hasChampionRow: showsChampionCard)"))
        #expect(panel.contains("private var showsChampionCard: Bool { !showsAllTime && store.miniGameYesterdayWinner != nil }"))
        #expect(panel.contains("if showsAllTime { allTimeFooter } else { prizeFooter }"))
        #expect(panel.contains("dateCaption: entry.dayCaption"), "역대 행에 날짜를 안 넘긴다")
        #expect(!panel.contains("Date()"), "창 콘텐츠가 시계를 읽는다")
    }
}

// MARK: - ④ 마이그레이션 계약

private struct V67Error: Error, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}

private let v67Migration = "20261027120000_minigame_alltime_board.sql"

/// `supabase/` 는 .gitignore 라 worktree 에는 없다 — `CHECK_MIGRATIONS_DIR` 이 먼저, 없으면 조상을 훑는다(V0364 와 같은 방식).
private func v67MigrationsDirectory() throws -> URL {
    if let override = ProcessInfo.processInfo.environment["CHECK_MIGRATIONS_DIR"], !override.isEmpty {
        let url = URL(fileURLWithPath: override, isDirectory: true)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw V67Error("CHECK_MIGRATIONS_DIR 가 가리키는 디렉토리가 없다: \(override)")
        }
        return url
    }
    var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    while directory.path != "/" {
        let candidate = directory.appendingPathComponent("supabase/migrations", isDirectory: true)
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return candidate
        }
        directory = directory.deletingLastPathComponent()
    }
    throw V67Error("supabase/migrations 를 못 찾았다 — CHECK_MIGRATIONS_DIR 로 알려 줘라")
}

private func v67MigrationRaw(_ name: String = v67Migration) throws -> String {
    let file = try v67MigrationsDirectory().appendingPathComponent(name)
    guard FileManager.default.fileExists(atPath: file.path) else { throw V67Error("\(name) 이 없다") }
    return try String(contentsOf: file, encoding: .utf8)
}

/// SQL `--` 줄 주석을 걷는다(설명을 지워야만 초록이 되는 테스트가 되지 않게). 이 파일의 문자열 리터럴 중 `--` 를 담은 것
/// (`'--[^' || chr(10) || ']*'`)은 그 줄이 잘린다 — 그 줄에 걸리는 단언은 두지 않는다.
private func v67StripSQL(_ sql: String) -> String {
    sql.split(separator: "\n", omittingEmptySubsequences: false).map { line -> Substring in
        if let range = line.range(of: "--") { return line[line.startIndex..<range.lowerBound] }
        return line
    }.joined(separator: "\n")
}

/// `create or replace function public.minigame_alltime_board(` 부터 그 함수 달러 인용 본문 끝까지(본문만).
private func v67FunctionBodySQL(_ sql: String, header: String) throws -> String {
    guard sql.components(separatedBy: header).count - 1 == 1, let start = sql.range(of: header)?.lowerBound else {
        throw V67Error("함수 헤더 \"\(header)\" 가 정확히 한 번 나오지 않는다")
    }
    let rest = sql[start...]
    guard let asRange = rest.range(of: "as $", options: .caseInsensitive) else { throw V67Error("달러 인용 시작이 없다") }
    let tagStart = rest.index(asRange.upperBound, offsetBy: -1)
    guard let tagEnd = rest[rest.index(after: tagStart)...].firstIndex(of: "$") else { throw V67Error("태그가 안 닫힌다") }
    let tag = String(rest[tagStart...tagEnd])
    let bodyStart = rest.index(after: tagEnd)
    guard let close = rest.range(of: tag, range: bodyStart..<rest.endIndex) else { throw V67Error("종료 태그 \(tag) 가 없다") }
    return String(rest[bodyStart..<close.lowerBound])
}

private func v67SnakeCase(_ camel: String) -> String {
    var out = ""
    for character in camel {
        if character.isUppercase { out += "_" + character.lowercased() } else { out.append(character) }
    }
    return out
}

@Suite("v0.3.67 역대 순위 — 마이그레이션 계약(20261027120000)")
struct V0367AllTimeMigrationTests {
    @Test("체인 자리: 운영 마지막 적용분(20261026120000) 뒤다")
    func migrationSitsAfterTheLastAppliedOne() throws {
        let names = try FileManager.default.contentsOfDirectory(at: try v67MigrationsDirectory(), includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "sql" }.map(\.lastPathComponent).sorted()
        #expect(names.count > 100, "마이그레이션을 \(names.count)개밖에 못 읽었다 — 이 검사가 헛돈다")
        let index = try #require(names.firstIndex(of: v67Migration), "\(v67Migration) 이 체인에 없다")
        let last = try #require(names.firstIndex(of: "20261026120000_cake_aing_gift.sql"))
        #expect(index > last)
        #expect(names.filter { $0.hasPrefix("20261027120000_") }.count == 1, "같은 버전 번호가 둘이다")
    }

    @Test("모양 · 실행권: jsonb · sql stable definer · search_path=public · anon/PUBLIC 회수 · authenticated 만(drop 없음)")
    func signatureAndGrants() throws {
        let sql = v67StripSQL(try v67MigrationRaw())
        let collapsed = v67Collapse(sql)
        #expect(collapsed.contains("create or replace function public.minigame_alltime_board(p_game text) returns jsonb language sql stable security definer set search_path = public as $fn$"),
                "함수 머리가 계약과 다르다")
        #expect(sql.components(separatedBy: "create or replace function public.").count - 1 == 1, "공개 스키마 함수를 하나보다 많이 만든다")
        #expect(!sql.lowercased().contains("drop function public."), "drop function 은 DEFAULT·ACL 을 버린다(2026-09-12 PGRST202)")
        for line in [
            "revoke all on function public.minigame_alltime_board(text) from public;",
            "revoke all on function public.minigame_alltime_board(text) from anon;",
            "grant execute on function public.minigame_alltime_board(text) to authenticated;",
            "grant execute on function public.minigame_alltime_board(text) to service_role;"
        ] {
            #expect(sql.contains(line), Comment(rawValue: "실행권 줄이 없다: \(line)"))
        }
        let grants = sql.split(separator: "\n").filter { $0.lowercased().contains("grant ") && $0.contains("minigame_alltime_board") }
        #expect(!grants.contains { $0.lowercased().contains(" to anon") || $0.lowercased().contains(" to public") },
                "anon/PUBLIC 에게 실행권을 준다 — 2026-08-09 노출 사고의 자리")
        #expect(!sql.lowercased().contains("cron.schedule"), "역대 순위에 cron 은 없다")
    }

    @Test("본문: 사람마다 최고 → 처음 닿은 날 · 정렬 best_score desc → best_at asc → user_id · 50행 · 오늘 순위와 같은 가시성 술어")
    func bodyTieBreakAndVisibilityMirrorTheTodayBoard() throws {
        let body = v67Collapse(try v67FunctionBodySQL(v67StripSQL(try v67MigrationRaw()),
                                                      header: "create or replace function public.minigame_alltime_board("))
        #expect(body.contains("select distinct on (s.user_id) s.user_id, s.best_score, s.best_at, s.day"))
        #expect(body.contains("order by s.user_id, s.best_score desc, s.best_at asc, s.day asc"),
                "같은 최고를 여러 날 냈을 때 '처음 닿은 날' 을 고르는 축이 아니다")
        #expect(body.contains("order by b.best_score desc, b.best_at asc, b.user_id limit 50 )"), "정렬 축·50행 상한이 계약과 다르다")
        #expect(body.contains("order by v.best_score desc, v.best_at asc, v.user_id), '[]'::jsonb)"), "배열 순서 축이 계약과 다르다")
        #expect(body.contains("where s.game = p_game and s.best_score > 0"))

        // 오늘 순위(minigame_board 최신판 = 20260917160000 숨김 격리)의 술어를 별칭만 바꿔 그대로 옮겼는가.
        let board = v67Collapse(try v67FunctionBodySQL(v67StripSQL(try v67MigrationRaw("20260917160000_hidden_accounts.sql")),
                                                       header: "CREATE OR REPLACE FUNCTION public.minigame_board("))
        for predicate in ["(coalesce(p.minigame_public, true) or s.user_id = auth.uid())",
                          "public.same_visibility(auth.uid(), s.user_id)", "s.best_score > 0", "limit 50"] {
            #expect(board.contains(predicate), Comment(rawValue: "정본(minigame_board)에서 \(predicate) 를 못 찾았다 — 기준이 바뀌었다"))
        }
        #expect(body.contains("where (coalesce(p.minigame_public, true) or b.user_id = auth.uid()) and public.same_visibility(auth.uid(), b.user_id)"),
                "가시성 술어(공개 끔 = 본인만 · 숨김 격리)가 오늘 순위와 다르다")
        #expect(!body.contains("blocked_between"), "순위판은 차단을 거르지 않는다")
        for verb in ["insert ", "update ", "delete "] {
            #expect(!body.lowercased().contains(verb), "순위 함수가 쓴다: \(verb)")
        }
    }

    @Test("응답 키 = 디코더 키(snake_case) — 한쪽만 고치면 그 칸이 조용히 nil 이 된다")
    func responseKeysMatchTheDecoder() throws {
        let body = try v67FunctionBodySQL(v67StripSQL(try v67MigrationRaw()),
                                          header: "create or replace function public.minigame_alltime_board(")
        let object = try #require(body.range(of: "jsonb_build_object(")).upperBound
        let rest = body[object...]
        let end = try #require(rest.range(of: "order by v.best_score")).lowerBound
        let segment = String(rest[..<end])
        let keys = Set(segment.matches(of: /'([a-z_]+)',/).map { String($0.output.1) })
        let decoder = Set(MiniGameAllTimeBoardRow.CodingKeys.allCases.map { v67SnakeCase($0.rawValue) })
        #expect(keys == decoder, "서버 키 \(keys.sorted()) ≠ 디코더 키 \(decoder.sorted())")
        #expect(keys.count == 7)
        #expect(segment.contains("to_char(v.day, 'YYYY-MM-DD')"), "day 가 'YYYY-MM-DD' 글자가 아니다 — 화면 'M/d' 가 깨진다")
    }

    @Test("프로브 관용: set local role %I 복귀 · RESET ROLE 없음 · 센티널 롤백 · 주석에 달러 태그 없음 · 최상위 트랜잭션 제어 없음")
    func probeIdiomsFollowTheHouseRules() throws {
        let raw = try v67MigrationRaw()
        let sql = v67StripSQL(raw)
        #expect(sql.contains("execute format('set local role %I', v_exec_role);"))
        #expect(sql.contains("v_exec_role text := current_user;"))
        #expect(!sql.lowercased().contains("reset role"), "RESET ROLE 은 링크드 연결에서 세션 사용자로 떨어져 42501 이다")
        #expect(sql.contains("raise exception 'MGAT_PROBE_ROLLBACK';") && sql.contains("if sqlerrm <> 'MGAT_PROBE_ROLLBACK' then raise; end if;"))
        #expect(sql.contains("alter table public.minigame_daily_scores enable trigger guard_minigame_score;"),
                "트리거를 끈 프로브가 다시 켜지 않는다")
        // 주석 안의 달러 태그 글자는 그 자리에서 본문을 끝낸다(달러 인용 안 주석 함정).
        for (index, line) in raw.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            guard let range = line.range(of: "--") else { continue }
            let comment = line[range.upperBound...]
            #expect(comment.firstMatch(of: /\$[A-Za-z_]*\$/) == nil, "줄 \(index + 1) 주석에 달러 태그가 있다: \(comment)")
        }
        for statement in sql.split(separator: "\n").map({ $0.trimmingCharacters(in: .whitespaces).lowercased() }) {
            #expect(!["begin;", "commit;", "rollback;"].contains(statement), "최상위 트랜잭션 제어가 있다: \(statement)")
        }
    }
}

// MARK: - 소스 헬퍼

private func v67Source(_ name: String) throws -> String {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("\(CheckCoreSourceLayout.directory(for: name))/\(name)")
    return try String(contentsOf: url, encoding: .utf8)
}

/// Swift `//` · `/* */` 주석을 걷는다(문자열 안의 `//` 는 이 파일들의 대상 구간에 없다).
private func v67StripComments(_ source: String) -> String {
    var output = ""
    var inBlock = false
    for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
        var rest = Substring(line)
        var kept = ""
        while !rest.isEmpty {
            if inBlock {
                if let close = rest.range(of: "*/") { rest = rest[close.upperBound...]; inBlock = false } else { rest = "" }
                continue
            }
            let lineComment = rest.range(of: "//")
            let blockComment = rest.range(of: "/*")
            if let block = blockComment, lineComment.map({ block.lowerBound < $0.lowerBound }) ?? true {
                kept += rest[..<block.lowerBound]; rest = rest[block.upperBound...]; inBlock = true; continue
            }
            if let comment = lineComment { kept += rest[..<comment.lowerBound]; rest = ""; continue }
            kept += rest; rest = ""
        }
        output += kept + "\n"
    }
    return output
}

/// 공백(줄바꿈 포함)을 한 칸으로 접는다 — 여러 줄 인자 목록을 한 줄 리터럴로 대조하려고.
private func v67Collapse(_ text: String) -> String {
    text.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).joined(separator: " ")
}

private func v67FunctionBody(_ source: String, name: String) -> String? {
    guard let declaration = source.range(of: "func \(name)(") else { return nil }
    guard let open = source.range(of: "{", range: declaration.upperBound..<source.endIndex) else { return nil }
    var depth = 0
    var index = open.lowerBound
    while index < source.endIndex {
        let character = source[index]
        if character == "{" { depth += 1 }
        if character == "}" {
            depth -= 1
            if depth == 0 { return String(source[open.upperBound..<index]) }
        }
        index = source.index(after: index)
    }
    return nil
}
