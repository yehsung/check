import Foundation
import Testing
@testable import check

// v0.3.13 — **클라가 실제로 보내는 본문 그대로** 서버를 치는 계약 감시망.
//
// ## 왜 이 파일이 생겼나 (2026-09-12 프로덕션 장애)
// `20260912143000_profile_center.sql` 이 `minigame_board` 에 center 컬럼을 더하려고 drop+create 를 하면서
// 원래 시그니처의 `p_day date default null` 에서 **default 를 떨어뜨렸다.**
// 앱은 '오늘' 순위를 볼 때 `p_day` 키를 아예 보내지 않는다(`encodeIfPresent` —
// `SupabaseWorkModels.swift` 의 `MiniGameBoardRequest.pDay: String? = nil`).
// 기본값이 사라지자 PostgREST 는 `minigame_board(p_game)` 에 맞는 함수를 못 찾아 **PGRST202(404)** 를 냈고,
// 미니게임 창이 통째로 빈 화면이 됐다(운영자 신고).
//
// ## 26개 프로브가 전부 초록이었던 이유
// 프로브가 `p_day` 를 **넣어서** 불렀기 때문이다. 넣으면 `minigame_board(text, date)` 가 그대로 잡히므로
// default 가 있든 없든 똑같이 성공한다. 즉 프로브는 **앱이 안 보내는 모양**을 검사하고 있었다.
// → 그래서 이 파일의 규칙은 하나다: **손으로 적은 JSON 을 서버에 쏘지 않는다.**
//   진짜 `SupabaseWorkService` 가 진짜 `JSONEncoder` 로 만들어 URLSession 에 넘긴 바이트를
//   URLProtocol 로 가로채, **그 바이트를** 실서버에 그대로 쏜다.
//
// ## 왜 클라 쪽 에러 분류로는 못 잡나
// PGRST202 본문의 message 는 "… in the schema cache" 로 끝난다. `SupabaseWorkHTTP.swift` 의 공용 매핑이
// 그 문구를 `.databaseSchemaMissing`("마이그레이션이 아직 안 나갔다")으로 접고,
// `WorkTimerStoreMiniGame.swift` 는 그걸 실패가 아니라 '아직 표가 없다'로 보아 **빈 목록을 조용히** 그린다.
// 이건 의도된 관용구다(브루 배포가 db push 보다 앞서는 창을 위해). 그 대가로 **함수 시그니처가 깨진 사고는
// 앱 안에서 영원히 무음**이다 — 서버를 실제로 쳐 보는 아래 프로브 말고는 잡을 자리가 없다.
//
// ## 이 파일의 두 층
//  1) **오프라인**(항상 돈다): 앱이 각 RPC 에 보내는 본문의 **키 집합**을 고정한다. `p_day` 가 빠지는 것이
//     사고가 아니라 **계약**임을 못박는다.
//  2) **라이브**(`CHECK_RPC_SHAPE_LIVE=1`): 그 바이트를 실서버 REST 에 쏴 PGRST202 가 아님을 단언한다.
//     게이트가 꺼져 있으면 swift-testing 이 SKIPPED 로 보고하고(통과가 아니다), 아래 항상 도는
//     `라이브_프로브_목록은_앱의_RPC_다섯을_전부_덮는다` 가 그 사실을 콘솔에 소리 내어 남긴다.

// MARK: - 나간 본문 캡처

private struct ShapeError: Error, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}

/// 앱이 그 RPC 를 부를 때 **실제로 나간** 요청 한 건.
private struct ClientRPCCall {
    /// RPC 이름(= `/rest/v1/rpc/<name>`).
    let name: String
    /// 나간 본문 JSON **원문**.
    let body: String
    /// 그 본문의 최상위 키 집합. PostgREST 의 함수 해석은 정확히 이 집합으로 이뤄진다.
    let keys: Set<String>
    let method: String
    let contentType: String?
}

/// 진짜 서비스 + 스텁 URLProtocol 로 한 번 호출하고, **나간 요청**을 돌려준다.
///
/// 응답 디코드 실패는 일부러 삼킨다 — 여기서 보는 것은 나간 요청이고, 스텁은 응답을 만들기 **전에**
/// `startLoading()` 에서 본문을 이미 기록한다. 그래서 서버 픽스처를 늘리지 않아도 본문은 항상 잡힌다.
private func captureRPC(
    _ name: String,
    _ perform: (SupabaseWorkService) async throws -> Void
) async throws -> ClientRPCCall {
    // 호스트를 매번 새로 만든다 — 스텁의 기록 버퍼는 프로세스 전역 호스트별 사전이고, 스위트는 병렬로 돈다.
    let host = "v0313-shape-\(name.replacingOccurrences(of: "_", with: "-"))-\(UUID().uuidString)"
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed)
    )
    try? await perform(service)

    let path = "/rest/v1/rpc/\(name)"
    let requests = URLProtocolStub.requests(forHost: host)
    let bodies = URLProtocolStub.bodies(forHost: host)
    guard let index = requests.firstIndex(where: { $0.url?.path == path }), index < bodies.count else {
        throw ShapeError("\(name): 요청이 아예 안 나갔다(경로 \(path)). 나간 경로들=\(requests.compactMap(\.url?.path))")
    }
    let request = requests[index]
    let body = bodies[index]
    guard let object = (try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? [String: Any] else {
        throw ShapeError("\(name): 본문이 JSON 객체가 아니다: \(body)")
    }
    return ClientRPCCall(
        name: name,
        body: body,
        keys: Set(object.keys),
        method: request.httpMethod ?? "",
        contentType: request.value(forHTTPHeaderField: "Content-Type")
    )
}

/// 라이브 프로브가 실서버에 쏘는 **전량**. 손으로 적은 JSON 은 여기 한 줄도 없다 —
/// 전부 위 `captureRPC` 가 앱에서 뽑아낸 바이트다. (오늘의 사고는 프로브가 앱과 다른 모양을
/// 보내고 있었기 때문에 무음이었다. 그 구멍을 원리적으로 막는 것이 이 함수다.)
private func captureClientRPCCalls() async throws -> [ClientRPCCall] {
    [
        // ★ 오늘의 사고 지점. day: nil = 미니게임 창을 열 때의 그 호출(WorkTimerStoreMiniGame.swift 의
        //   performLoadMiniGameBoard 가 `day: nil` 로 부른다).
        try await captureRPC("minigame_board") {
            _ = try await $0.fetchMiniGameBoard(accessToken: "shape-token", kind: .flappy, day: nil)
        },
        try await captureRPC("minigame_yesterday_winner") {
            _ = try await $0.fetchMiniGameYesterdayWinner(accessToken: "shape-token", kind: .flappy)
        },
        try await captureRPC("token_usage_board") {
            _ = try await $0.fetchTokenBoard(accessToken: "shape-token", month: TokenUsageMonthKey.current())
        },
        try await captureRPC("app_user_directory") {
            _ = try await $0.fetchPokeDirectory(accessToken: "shape-token")
        },
        try await captureRPC("team_weekly_leaderboard") {
            _ = try await $0.fetchTeamLeaderboard(accessToken: "shape-token")
        }
    ]
}

// MARK: - ① 오프라인: 앱이 보내는 본문의 키 집합 (항상 돈다)

/// ★ 이 파일의 심장. `p_day` 가 빠지는 것은 버그가 아니라 **계약**이다 — 서버가 KST 오늘을 정한다
/// (클라 시계를 믿지 않는 것이 미니게임 전체의 규약이다). 그래서 서버 쪽 `p_day` 의 default 는
/// 장식이 아니라 이 본문이 성립하기 위한 **전제**다.
@Test
func 미니게임_오늘_순위는_p_day_키를_아예_안_보낸다() async throws {
    let call = try await captureRPC("minigame_board") {
        _ = try await $0.fetchMiniGameBoard(accessToken: "shape-token", kind: .flappy, day: nil)
    }
    #expect(call.keys == ["p_game"], "오늘 순위 본문의 키 집합이 바뀌었다: \(call.body)")
    #expect(!call.body.contains("p_day"), "p_day 가 본문에 실렸다(null 로라도 실으면 안 된다): \(call.body)")
    #expect(call.body.contains("\"p_game\":\"flappy\""))
    #expect(call.method == "POST")
    #expect(call.contentType == "application/json")
}

/// 대조군 — 날짜를 **주면** 키가 는다. 이 줄이 없으면 위 단언이 "앱이 minigame_board 를 아예 안 부른다"
/// 여도 초록이다(기준선이 같은 입력이면 그 비교는 영원히 초록이다).
/// 동시에 이것이 **26개 프로브가 보내던 모양**이다 — 그래서 그것들은 사고를 못 봤다.
@Test
func 날짜를_주면_p_day_가_실린다_그것이_옛_프로브가_보던_모양이다() async throws {
    let call = try await captureRPC("minigame_board") {
        _ = try await $0.fetchMiniGameBoard(accessToken: "shape-token", kind: .flappy, day: "2026-09-11")
    }
    #expect(call.keys == ["p_game", "p_day"], "어제 순위 본문의 키 집합이 바뀌었다: \(call.body)")
    #expect(call.body.contains("\"p_day\":\"2026-09-11\""))
}

@Test
func 어제_1등은_p_game_하나만_보낸다() async throws {
    let call = try await captureRPC("minigame_yesterday_winner") {
        _ = try await $0.fetchMiniGameYesterdayWinner(accessToken: "shape-token", kind: .timingBar)
    }
    #expect(call.keys == ["p_game"], "본문 키 집합이 바뀌었다: \(call.body)")
    #expect(call.body.contains("\"p_game\":\"timing_bar\""))
}

@Test
func 토큰_순위판은_p_month_하나만_보낸다() async throws {
    let call = try await captureRPC("token_usage_board") {
        _ = try await $0.fetchTokenBoard(accessToken: "shape-token", month: "2026-09")
    }
    #expect(call.keys == ["p_month"], "본문 키 집합이 바뀌었다: \(call.body)")
    #expect(call.body.contains("\"p_month\":\"2026-09\""))
}

/// 인자 없는 RPC 두 개는 **빈 객체**를 보낸다(`EmptyBody`). 빈 본문(0바이트)이 아니다 —
/// 이 둘을 헷갈려 본문을 통째로 빼면 PostgREST 는 다른 해석 경로를 타고,
/// 본문 없는 POST 는 `Content-Type` 도 안 붙어 400 이 난다.
@Test
func 인자없는_RPC_둘은_빈_객체를_보낸다() async throws {
    for name in ["app_user_directory", "team_weekly_leaderboard"] {
        let call = try await captureRPC(name) { service in
            if name == "app_user_directory" {
                _ = try await service.fetchPokeDirectory(accessToken: "shape-token")
            } else {
                _ = try await service.fetchTeamLeaderboard(accessToken: "shape-token")
            }
        }
        #expect(call.keys.isEmpty, "\(name) 본문에 키가 생겼다: \(call.body)")
        #expect(call.body == "{}", "\(name) 본문이 빈 객체가 아니다: \(call.body)")
        #expect(call.contentType == "application/json", "\(name) 에 Content-Type 이 없다")
    }
}

/// 본문 캡처가 실제로 '앱의 인코더'를 지났는지 — snake_case 변환은 서비스 생성자에서 한 번만 정해지고
/// (`encoder.keyEncodingStrategy = .convertToSnakeCase`), 그 설정이 바뀌면 **모든** RPC 가 동시에
/// 해석 불가가 된다. 키 하나를 카멜로 되돌리는 실수는 이 한 줄에서 먼저 걸린다.
@Test
func 본문_키는_전부_snake_case_다() async throws {
    for call in try await captureClientRPCCalls() {
        for key in call.keys {
            #expect(key == key.lowercased(), "\(call.name): 대문자가 섞인 키 \(key) — snake_case 변환이 깨졌다")
            #expect(key.hasPrefix("p_"), "\(call.name): PostgREST 인자 이름 규약(p_)에서 벗어난 키 \(key)")
        }
    }
}

/// ★ **왜 앱 안에서는 이 사고가 8시간 동안 무음이었나** — 여기서 끝난다.
///
/// PGRST202 본문의 message 는 "… in the schema cache" 로 끝난다. `SupabaseWorkHTTP.swift` 의 공용 매핑은
/// 그 문구를 보고 `.databaseSchemaMissing`("마이그레이션이 아직 안 나갔다")으로 접는다.
/// `WorkTimerStoreMiniGame.swift` 의 `performLoadMiniGameBoard` 는 그 에러를 실패가 아니라 '아직 표가 없다'로
/// 보아 **`miniGameBoardFailed` 를 세우지 않고** `miniGameBoardLoaded = true` 로 접는다 —
/// 즉 실패 문구도, [다시 시도] 버튼도 없이 **빈 순위판**이 나온다. 그게 운영자가 본 화면이다.
///
/// 이 접기는 의도된 관용구다(브루 배포가 `db push` 보다 앞서는 창을 위해서다). 그래서 여기서는
/// 그 사실을 **없애려 들지 않고 못박는다**: 이 매핑이 살아 있는 한 시그니처 파손은 앱 안에서 영원히
/// 무음이고, 따라서 **실서버를 직접 치는 위 프로브 말고는 잡을 자리가 없다.**
///
/// 언젠가 PGRST202(함수 없음)와 PGRST205(표 없음)를 가르기로 한다면, 고칠 곳은 두 군데다:
/// `SupabaseWorkHTTP.serviceError` 의 "schema cache" 분기와, 그 새 에러를 받는 스토어의 catch.
@Test
func PGRST202_는_마이그레이션_미적용과_구별되지_않는다_그래서_앱은_조용히_빈_화면을_그린다() async throws {
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://v0313-pgrst202")!,
        anonKey: "anon-test-key",
        session: URLSession(configuration: .stubbed)
    )
    // 2026-09-12 실서버가 실제로 돌려준 본문 모양 그대로(함수 이름만 사고 당시 것으로).
    let body = Data(#"""
    {"code":"PGRST202","details":"Searched for the function public.minigame_board with parameter p_game or with a single unnamed json/jsonb parameter, but no matches were found in the schema cache.","hint":null,"message":"Could not find the function public.minigame_board(p_game) in the schema cache"}
    """#.utf8)
    let error = await service.serviceError(statusCode: 404, data: body)
    let why = "PGRST202 의 분류가 바뀌었다. 스토어의 catch(WorkTimerStoreMiniGame·Poke·Sync·Messages·Feedback)가 "
        + "이 값을 '아직 표가 없다'로 접고 있으니, 분류를 가를 거면 그쪽도 같이 고쳐라."
    #expect(error == .databaseSchemaMissing, Comment(rawValue: why))
}

// MARK: - ② 라이브 프로브 게이트

private enum LiveRPCShapeEnv {
    static let gateName = "CHECK_RPC_SHAPE_LIVE"
    static let enabled = ProcessInfo.processInfo.environment[gateName] == "1"

    /// anon 키 — LiveE2ETests 와 같은 규약(파일에서 읽고, 원문은 절대 출력하지 않는다).
    static func anonKey() throws -> String {
        let path = ProcessInfo.processInfo.environment["CHECK_RPC_SHAPE_ANON_KEY_FILE"]
            ?? "/Users/yesung/check/.env.local"
        let text = try String(contentsOfFile: path, encoding: .utf8)
        let prefix = "\(SupabaseConfig.anonKeyEnvironmentName)="
        for rawLine in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix(prefix) else { continue }
            let value = String(line.dropFirst(prefix.count))
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if !value.isEmpty { return value }
        }
        throw ShapeError("anon 키(\(SupabaseConfig.anonKeyEnvironmentName))를 \(path) 에서 못 찾았다")
    }
}

private struct RPCProbeResult {
    let status: Int
    /// PostgREST 오류 본문의 `code`(PGRST202 / 42501 …). 성공(2xx)이면 nil.
    let code: String?
    let message: String
}

/// **로그인 없이**(anon 키만) 실서버 REST 를 친다.
///
/// 왜 계정이 필요 없나 — PostgREST 는 함수를 먼저 **해석**하고 그 다음에 실행권을 본다.
/// 본문 모양에 맞는 함수가 없으면 역할과 무관하게 404 PGRST202 가 오고, 있으면 실행 단계에서
/// 401 42501(anon 은 실행권이 회수돼 있다 — LiveE2ETests s08b 가 그걸 지킨다)이 온다.
/// 실측(2026-09-12): `{"p_game":"flappy"}` → 42501, `{"p_game_TYPO":"flappy"}` → PGRST202.
/// 그래서 이 프로브는 **계정을 만들지도, 프로덕션 데이터를 한 줄도 건드리지도 않는다.**
private func probeProductionRPC(anonKey: String, name: String, body: String) async throws -> RPCProbeResult {
    var request = URLRequest(url: SupabaseConfig.projectURL.appending(path: "/rest/v1/rpc/\(name)"))
    request.httpMethod = "POST"
    request.setValue(anonKey, forHTTPHeaderField: "apikey")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = Data(body.utf8)
    let session = URLSession(configuration: .ephemeral)
    let (data, response) = try await session.data(for: request)
    let status = (response as? HTTPURLResponse)?.statusCode ?? -1
    let text = String(decoding: data, as: UTF8.self)
    let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    return RPCProbeResult(status: status, code: json?["code"] as? String, message: text)
}

// MARK: - ③ 라이브: 앱이 보내는 바이트로 실서버를 친다

/// ★ 오늘의 사고를 **다음엔** 잡는 자리.
@Test(.enabled(if: LiveRPCShapeEnv.enabled))
func 실서버가_앱이_보내는_본문_모양을_전부_해석한다() async throws {
    let anonKey = try LiveRPCShapeEnv.anonKey()
    let calls = try await captureClientRPCCalls()
    #expect(calls.count == 5)

    for call in calls {
        let result = try await probeProductionRPC(anonKey: anonKey, name: call.name, body: call.body)
        print("RPC-SHAPE| \(call.name) \(call.body) → HTTP \(result.status) code=\(result.code ?? "nil")")
        #expect(
            result.code != "PGRST202",
            "\(call.name): 실서버에 이 본문 모양에 맞는 함수가 없다(= 오늘의 장애 그대로). 본문=\(call.body) 응답=\(result.message)"
        )
        #expect(
            result.status != 404,
            "\(call.name): 404 — 함수/경로 해석 실패. 본문=\(call.body) 응답=\(result.message)"
        )
        // 지금의 정상 상태는 42501(함수는 찾았고 anon 에게 실행권이 없다)이다. 다른 코드가 오면
        // 사고는 아닐 수 있어도 **서버 표면이 바뀐 것**이므로 눈에 띄게 남긴다.
        #expect(
            result.code == "42501",
            "\(call.name): 예상 밖 응답(42501 이 아니다). anon 에 실행권이 열렸는지 확인하라. 응답=\(result.message)"
        )
    }
}

/// 프로브가 **실제로 PGRST202 를 잡는지**(= 위 단언이 장식이 아닌지) 서버에 직접 물어 확인한다.
/// 서버를 되돌려 사고를 재현할 수는 없으니, 같은 실패를 본문 쪽에서 만든다 —
/// 서버가 모르는 인자 이름은 default 를 잃은 함수와 **똑같은 해석 실패**를 낸다.
@Test(.enabled(if: LiveRPCShapeEnv.enabled))
func 프로브는_해석실패를_실제로_빨갛게_본다() async throws {
    let anonKey = try LiveRPCShapeEnv.anonKey()
    let result = try await probeProductionRPC(
        anonKey: anonKey,
        name: "minigame_board",
        body: #"{"p_game_that_server_does_not_know":"flappy"}"#
    )
    print("RPC-SHAPE| 음성 대조군 → HTTP \(result.status) code=\(result.code ?? "nil")")
    #expect(result.status == 404, "해석 실패가 404 가 아니다 — 위 프로브의 404 단언이 무의미해진다")
    #expect(result.code == "PGRST202", "해석 실패 코드가 PGRST202 가 아니다: \(result.message)")
}

// MARK: - ④ 게이트를 소리 내어 남긴다 (항상 돈다)

/// 라이브 프로브가 덮는 RPC 가 작업 지시의 다섯과 정확히 같은지 — 여기서 하나 빠지면
/// 그 RPC 의 시그니처는 아무도 안 본다. 겸해서 **게이트 상태를 콘솔에 남긴다**:
/// 게이트가 꺼진 실행이 "전부 통과"처럼 보이지 않게 하는 것이 이 print 의 전부다.
@Test
func 라이브_프로브_목록은_앱의_RPC_다섯을_전부_덮는다() async throws {
    let calls = try await captureClientRPCCalls()
    #expect(
        Set(calls.map(\.name)) == [
            "minigame_board",
            "minigame_yesterday_winner",
            "token_usage_board",
            "app_user_directory",
            "team_weekly_leaderboard"
        ]
    )
    for call in calls {
        print("RPC-SHAPE| 앱이 보내는 본문 — \(call.name): \(call.body)")
    }
    if LiveRPCShapeEnv.enabled {
        print("RPC-SHAPE| 라이브 프로브 ON — 위 본문 그대로 실서버를 친다.")
    } else {
        print("RPC-SHAPE| ⚠️ 라이브 프로브 OFF(SKIPPED). 실서버는 한 번도 안 쳤다.")
        print("RPC-SHAPE| ⚠️ 켜는 법: \(LiveRPCShapeEnv.gateName)=1 swift test --filter V0313RPCBodyShape")
        print("RPC-SHAPE| ⚠️ 2026-09-12 PGRST202 장애는 위 오프라인 계약이 아니라 그 프로브만 잡는다.")
    }
}
