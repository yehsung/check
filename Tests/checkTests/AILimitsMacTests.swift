import AppKit
import Foundation
import os
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// MARK: - AI 리밋 맥 배선 — 리더 3종 · 스토어 · 업로드 본문 · 팝오버 폭 (v0.3.45)
//
// ## 이 스위트가 재는 것
// 리더 셋의 **파싱**(실측 응답 모양 그대로), 스토어의 **간격·백오프·영속**, 업로드 본문의 **키 집합**,
// 팝오버 한 줄의 **폭**이다. 네 가지가 각각 "틀려도 화면이 멀쩡해 보이는" 종류의 결함이라 값으로 못 박는다.
//
// ## 프로세스도 네트워크도 띄우지 않는다
// `security`·`agy`·제공자 HTTP 는 전부 주입된 가짜다. 특히 **Claude 는 실호출 테스트를 만들면 안 된다** —
// 5분에 5회가 상한이라 스위트가 5회를 넘기면 사용자 계정이 5분간 429 로 잠긴다(실측 2026-10-07).
//
// ## 픽스처는 실측 응답에서 **신원만 지운 것**이다
// 숫자·키 이름·중첩 구조는 2026-10-07 이 맥에서 실제로 받은 응답 그대로다(`scratchpad/usage-*.json`).
// 반면 `email`·`user_id`·`account_id` 같은 신원 값과 토큰 문자열은 **한 글자도 담지 않는다** —
// 이 저장소는 퍼블릭이고, 픽스처는 커밋되면 영구적이다(관례: '에이전트가 저장소에 파일을 흘린다').
// 자리만 남겨 두는 이유는 그 키가 응답에 **있다**는 사실 자체가 파서의 계약이기 때문이다.

// MARK: - 고정 시각·픽스처

/// 고정 기준 시각. 벽시계에 기대지 않는다.
private let amNow = Date(timeIntervalSince1970: 1_791_300_000)

/// 격리 UserDefaults(테스트마다 새 도메인 — `cfprefsd` 를 죽인 plist 폭증의 수리와 같은 규약).
///
/// ★ 이름은 **반드시** `CheckTestScratch` 에서 받는다. 평범한 이름(`"check.aiLimits.test.…"`)을 주면
///   `UserDefaults(suiteName:)` 이 그것을 도메인으로 읽어 `~/Library/Preferences` 에 plist 를 만든다.
///   UUID 를 붙이면 **실행마다 새 파일**이라 무한히 쌓인다 — 62만 개가 `cfprefsd` 를 죽여 로그아웃·유령
///   기기·토큰 2배를 한꺼번에 만든 그 사고다. `uniqueSuitePath` 는 절대 경로를 주고, 가짓수가
///   `호출 자리 × 이번 실행의 호출 횟수` 로 유계다. `PreferencesLeakGateTests` 가 이 규약을 지킨다.
///   `function`·`line` 은 **호출 지점**에서 평가되는 기본 인자라 호출부를 한 줄도 안 고친다.
private func amDefaults(_ function: String = #function, line: Int = #line) -> UserDefaults {
    let name = CheckTestScratch.uniqueSuitePath(function: function, line: line)
    let defaults = UserDefaults(suiteName: name) ?? .standard
    defaults.removePersistentDomain(forName: name)
    return defaults
}

/// `~/Library/Preferences` 의 **전체 항목** 이름. 접두사로 좁히지 않는다 — 좁히면 다음에 생기는 접두사를 또
/// 놓친다(`PreferencesLeakGateTests` 머리말: 그래서 98,609개를 두 번 못 봤다).
private func amPreferencesEntries() throws -> Set<String> {
    let dir = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        .appendingPathComponent("Library/Preferences", isDirectory: true)
    return Set(try FileManager.default.contentsOfDirectory(atPath: dir.path))
}

/// Claude `GET /api/oauth/usage` 의 실측 응답(신원 없음 — 원래도 없었다).
///
/// ★ `limits[].is_active` 가 **27% 찬 5시간 창에서 false** 인 그 모양을 그대로 담았다. 이 깃발을 표시
///   게이트로 쓰면 아래 테스트가 "5시간 창이 사라졌다"로 빨개진다.
/// ★ `resets_at` 이 **두 형식으로 섞여** 있다(소수 6자리 / 없음) — 포매터 한 벌이면 한쪽이 nil 이 된다.
private let amClaudeUsageJSON = """
{"five_hour":{"utilization":27.0,"resets_at":"2026-10-06T19:00:00.434051+00:00","limit_dollars":null,
"used_dollars":null,"remaining_dollars":null,"locked_reason":null},
"seven_day":{"utilization":60.0,"resets_at":"2026-10-12T03:00:00.434076+00:00","limit_dollars":null,
"used_dollars":null,"remaining_dollars":null,"locked_reason":null},
"seven_day_opus":null,"seven_day_sonnet":null,"tangelo":null,"nimbus_quill":null,
"iguana_necktie":{"utilization":0.0,"resets_at":"2026-11-05T07:59:00+00:00","limit_dollars":250,
"used_dollars":0.0,"remaining_dollars":250.0,"locked_reason":null},
"extra_usage":{"is_enabled":false,"monthly_limit":2000,"used_credits":0.0,"utilization":0.0},
"limits":[{"kind":"session","group":"session","percent":27,"severity":"normal",
"resets_at":"2026-10-06T19:00:00.434051+00:00","scope":null,"is_active":false},
{"kind":"weekly_all","group":"weekly","percent":60,"severity":"normal",
"resets_at":"2026-10-12T03:00:00.434076+00:00","scope":null,"is_active":true},
{"kind":"weekly_scoped","group":"weekly","percent":42,"severity":"normal",
"resets_at":"2026-10-12T03:00:00.434283+00:00","scope":{"model":{"id":null,"display_name":"Fable"}},"is_active":false}]}
"""

/// 키체인 `security -w` 출력의 실측 모양. **토큰 자리는 자리표시자**이고 `expiresAt` 은 epoch **밀리초**다.
private func amClaudeCredentialsJSON(expiresAtMilliseconds: Double, plan: String = "max") -> String {
    """
    {"claudeAiOauth":{"accessToken":"PLACEHOLDER-NOT-A-TOKEN","refreshToken":"PLACEHOLDER-NOT-A-TOKEN",
    "expiresAt":\(Int(expiresAtMilliseconds)),"scopes":["user:inference"],"subscriptionType":"\(plan)",
    "rateLimitTier":"default"}}
    """
}

/// Codex `GET /backend-api/wham/usage` 의 실측 응답. **신원 세 칸은 자리표시자**다(키는 남긴다 — 그 키가
/// 응답에 있다는 사실이 "덤프에 남기지 마라"의 근거다).
///
/// 숫자는 실측 그대로: 5시간 0%(= `reset_after_seconds` 가 창 길이와 같은 **투영**), 주간 56%.
private let amCodexUsageJSON = """
{"user_id":"PLACEHOLDER","account_id":"PLACEHOLDER","email":"PLACEHOLDER","plan_type":"plus",
"rate_limit":{"allowed":true,"limit_reached":false,
"primary_window":{"used_percent":0,"limit_window_seconds":18000,"reset_after_seconds":18000,"reset_at":1791331156},
"secondary_window":{"used_percent":56,"limit_window_seconds":604800,"reset_after_seconds":352855,"reset_at":1791666011}},
"code_review_rate_limit":null,"additional_rate_limits":null,
"credits":{"has_credits":false,"unlimited":false,"balance":"0"}}
"""

/// 플랜이 없는(크레딧) 사용자: **두 창이 전부 null** 이다.
private let amCodexNoPlanJSON = """
{"plan_type":null,"rate_limit":{"allowed":true,"limit_reached":false,
"primary_window":null,"secondary_window":null},
"credits":{"has_credits":false,"unlimited":false,"balance":"0"}}
"""

/// `agy -p /usage --output-format json` 의 실측 봉투. `remaining_fraction` 은 **남은** 비율이다.
private func amAntigravityCLIJSON(
    status: String = "SUCCESS",
    geminiWeekly: Double,
    gemini5h: Double,
    thirdPartyWeekly: Double,
    thirdParty5h: Double
) -> String {
    """
    {"conversation_id":"","status":"\(status)","response":"","duration_seconds":0,"num_turns":0,
    "usage":{"input_tokens":0,"output_tokens":0,"thinking_tokens":0,"cache_read_tokens":0,"total_tokens":0},
    "command":{"name":"usage","data":{"description":"Models share limits","groups":[
      {"name":"Gemini Models","description":"Gemini models","buckets":[
        {"id":"gemini-weekly","name":"Weekly Limit Remaining","window":"weekly",
         "remaining_fraction":\(geminiWeekly),"reset_time":"2026-10-13T19:11:25Z"},
        {"id":"gemini-5h","name":"Five Hour Limit Remaining","window":"5h",
         "remaining_fraction":\(gemini5h),"reset_time":"2026-10-07T00:11:25Z"}]},
      {"name":"Claude and GPT models","description":"3p models","buckets":[
        {"id":"3p-weekly","name":"Weekly Limit Remaining","window":"weekly",
         "remaining_fraction":\(thirdPartyWeekly),"reset_time":"2026-10-13T19:11:25Z"},
        {"id":"3p-5h","name":"Five Hour Limit Remaining","window":"5h",
         "remaining_fraction":\(thirdParty5h),"reset_time":"2026-10-07T00:11:25Z"}]}]}}}
    """
}

// MARK: - 가짜 주입물

/// 명령별 canned 결과 + **호출 기록**을 남기는 가짜 프로세스 실행기.
private final class AMFakeProcess: @unchecked Sendable {
    /// 실행 파일 경로 접미사 → 결과.
    var outcomes: [String: AILimitCommandOutput] = [:]
    private let recorded = OSAllocatedUnfairLock(initialState: [AILimitCommand]())

    /// ★ `NSLock` 이 아니라 `OSAllocatedUnfairLock` 이다 — `lock()` 은 async 컨텍스트에서 쓸 수 없고
    ///   러너는 `async` 클로저다(프로덕션 프로브들이 같은 락을 쓰는 이유와 같다).
    var commands: [AILimitCommand] { recorded.withLock { $0 } }

    var runner: AILimitCommandRunner {
        { [self] command in
            recorded.withLock { $0.append(command) }
            return outcomes.first { command.executable.path.hasSuffix($0.key) }?.value ?? .notRun
        }
    }

    func count(suffix: String) -> Int {
        commands.filter { $0.executable.path.hasSuffix(suffix) }.count
    }
}

/// 호스트별 canned 응답 + **요청 기록**을 남기는 가짜 HTTP. 실제 `URLSession` 을 쓰지 않는다
/// (`URLProtocol` 등록은 프로세스 전역 상태라 병렬 테스트에서 서로를 덮는다 — 그 플레이키를 만들지 않는다).
private final class AMFakeHTTP: @unchecked Sendable {
    /// 호스트 → 응답.
    var responses: [String: AILimitHTTPResponse] = [:]
    private let recorded = OSAllocatedUnfairLock(initialState: [URLRequest]())

    var requests: [URLRequest] { recorded.withLock { $0 } }

    var fetcher: AILimitHTTPFetcher {
        { [self] request in
            recorded.withLock { $0.append(request) }
            return responses[request.url?.host ?? ""] ?? .offline
        }
    }

    func request(host: String) -> URLRequest? {
        requests.first { $0.url?.host == host }
    }
}

// MARK: - 리더: Claude

@Suite("AILimitsMac — 리더 3종")
struct AILimitsMacReaderTests {
    /// 실측 응답에서 **두 창만** 뽑는다. 코드네임 창 20여 개와 달러 창(`iguana_necktie`)은 섞이지 않는다.
    ///
    /// ★ `limits[].is_active` 가 5시간 창에서 **false** 인 픽스처다 — 그 깃발을 게이트로 쓰면 이 테스트가 빨개진다.
    @Test
    func claudeUsageKeepsOnlyTheTwoKnownWindows() throws {
        let result = AILimitClaudeReader.parseUsage(
            Data(amClaudeUsageJSON.utf8), observedAt: amNow, planLabel: "max"
        )
        let snapshot = try result.get()
        #expect(snapshot.provider == .claude)
        #expect(snapshot.windows.count == 2, "창이 \(snapshot.windows.map(\.window)) 다 — 코드네임·달러 창이 섞였거나 창을 잃었다")
        #expect(snapshot.window(.fiveHour)?.usedPercent == 27)
        #expect(snapshot.window(.weekly)?.usedPercent == 60)
        #expect(snapshot.planLabel == "max")
        // 지문은 없다 — 이 응답에 안정된 계정 식별자가 없고, 12시간마다 도는 토큰을 해시하면 지문이 매일 바뀐다.
        #expect(snapshot.accountFingerprint == nil)
    }

    /// ★ **포매터 한 벌로는 두 형식을 다 못 받는다.** 소수 6자리와 소수 없음이 같은 응답에 섞여 온다.
    ///
    /// 없으면: `[.withInternetDateTime]` 한 벌로 바꿔도 초록이고(5시간·주간이 둘 다 소수 형식이라 **둘 다 nil**),
    /// 그러면 리셋 시각이 통째로 사라진 채 바와 캡션만 남는다.
    @Test
    func resetTimesParseBothISOShapes() throws {
        let fractional = AILimitDateParser.date("2026-10-06T19:00:00.434051+00:00")
        let plain = AILimitDateParser.date("2026-11-05T07:59:00+00:00")
        let zulu = AILimitDateParser.date("2026-10-13T19:11:25Z")
        #expect(fractional != nil, "소수 6자리 형식을 못 읽었다")
        #expect(plain != nil, "소수 없는 형식을 못 읽었다 — 포매터가 한 벌뿐이다")
        #expect(zulu != nil, "Z 형식(안티그래비티)을 못 읽었다")
        #expect(AILimitDateParser.date(nil) == nil)
        #expect(AILimitDateParser.date("") == nil)
        // 두 형식이 같은 응답에 있다는 것이 이 테스트의 전제다.
        let snapshot = try AILimitClaudeReader.parseUsage(
            Data(amClaudeUsageJSON.utf8), observedAt: amNow, planLabel: nil
        ).get()
        #expect(snapshot.window(.fiveHour)?.resetsAt != nil)
    }

    /// 키체인이 **항목 없음**(44)이면 '미설치'다 → 그 제공자만 숨는다.
    @Test
    func claudeKeychainItemMissingIsNotInstalled() async {
        let process = AMFakeProcess()
        process.outcomes["security"] = AILimitCommandOutput(
            status: AILimitClaudeReader.keychainItemNotFoundStatus, stdout: Data()
        )
        let http = AMFakeHTTP()
        let reader = AILimitClaudeReader(runner: process.runner, fetch: http.fetcher, appVersion: "0.3.45")
        let result = await reader.read(now: amNow)
        #expect((try? result.get()) == nil)
        if case .failure(let error) = result { #expect(error.failure == .notInstalled) }
        // ★ 자격증명을 못 읽었으면 **네트워크를 치지 않는다**(토큰 없이 401 을 받아 '만료'로 오보하지 않게).
        #expect(http.requests.isEmpty, "자격증명 없이 사용량을 조회했다")
    }

    /// 승인 대화상자에서 거부·타임아웃이면 `.blocked` 이고, **Claude 행만** 숨는다.
    ///
    /// 없으면: 거부 하나가 기능 전체를 죽이는 변경(러너 실패를 통째로 던지기)이 통과한다.
    @Test
    func claudeKeychainDenialHidesOnlyClaude() async {
        let process = AMFakeProcess()
        // 승인 창이 떠 응답이 없었다 = 타임아웃.
        process.outcomes["security"] = AILimitCommandOutput(status: -1, stdout: Data(), timedOut: true)
        process.outcomes["agy"] = AILimitCommandOutput(
            status: 0,
            stdout: Data(amAntigravityCLIJSON(
                geminiWeekly: 0.4, gemini5h: 0.9, thirdPartyWeekly: 0.8, thirdParty5h: 1.0
            ).utf8)
        )
        let http = AMFakeHTTP()
        http.responses["chatgpt.com"] = AILimitHTTPResponse(status: 200, body: Data(amCodexUsageJSON.utf8))

        let claude = AILimitClaudeReader(runner: process.runner, fetch: http.fetcher, appVersion: "0.3.45")
        let codex = AILimitCodexReader(
            fetch: http.fetcher,
            codexHome: URL(fileURLWithPath: "/nonexistent"),
            appVersion: "0.3.45",
            readFile: { _ in Data(amCodexAuthJSON(expirySeconds: amNow.timeIntervalSince1970 + 86_400).utf8) }
        )
        let antigravity = AILimitAntigravityReader(
            runner: process.runner,
            locate: { URL(fileURLWithPath: "/opt/homebrew/bin/agy") },
            scratchDirectory: { nil }
        )
        let outcome = AILimitReadOutcome(results: [
            .claude: await claude.read(now: amNow),
            .codex: await codex.read(now: amNow),
            .antigravity: await antigravity.read(now: amNow)
        ])

        #expect(outcome.failures[.claude] == .blocked)
        #expect(outcome.failures[.claude]?.hidesProvider == true, "키체인 거부가 Claude 행을 숨기지 않는다")
        // ★ 기준선이 갈린다: 나머지 둘은 **살아 있다**. 셋이 다 죽으면 이 테스트는 "셋 다 실패한다"를 재는 것이고
        //   '한 행만 숨긴다'는 요건을 전혀 안 잰다.
        #expect(outcome.failures[.codex] == nil, "Claude 거부가 Codex 까지 죽였다")
        #expect(outcome.failures[.antigravity] == nil, "Claude 거부가 안티그래비티까지 죽였다")
        #expect(outcome.snapshots.count == 2)
        // 문구는 없다 — 사용자가 할 수 있는 일이 없으므로 조용히 숨긴다.
        #expect(AILimitReadFailure.blocked.noticeText(for: .claude) == nil)
    }

    /// `expiresAt` 이 과거면 **호출조차 하지 않는다**(만료는 네트워크 없이 공짜로 안다).
    @Test
    func claudeExpiredTokenNeverCallsTheNetwork() async {
        let process = AMFakeProcess()
        let expiredMilliseconds = (amNow.timeIntervalSince1970 - 60) * 1000
        process.outcomes["security"] = AILimitCommandOutput(
            status: 0, stdout: Data(amClaudeCredentialsJSON(expiresAtMilliseconds: expiredMilliseconds).utf8)
        )
        let http = AMFakeHTTP()
        http.responses["api.anthropic.com"] = AILimitHTTPResponse(status: 200, body: Data(amClaudeUsageJSON.utf8))
        let reader = AILimitClaudeReader(runner: process.runner, fetch: http.fetcher, appVersion: "0.3.45")
        let result = await reader.read(now: amNow)
        if case .failure(let error) = result { #expect(error.failure == .expired) } else { Issue.record("만료를 못 잡았다") }
        #expect(http.requests.isEmpty, "만료된 토큰으로 사용량을 조회했다 — 429 예산을 헛되게 쓴다")
        #expect(AILimitReadFailure.expired.noticeText(for: .claude) == "클로드 코드를 한 번 실행해 주세요")
        #expect(AILimitReadFailure.expired.hidesProvider == false, "만료는 숨기지 않는다 — 사용자가 할 일이 있다")
    }

    /// `expiresAt` 이 **밀리초**다. 초로 읽으면 1970년이 되어 모든 사람이 영원히 만료다.
    @Test
    func claudeExpiryIsMilliseconds() throws {
        let future = (amNow.timeIntervalSince1970 + 12 * 3_600) * 1000
        let credentials = try AILimitClaudeReader.parseCredentials(
            Data(amClaudeCredentialsJSON(expiresAtMilliseconds: future).utf8)
        ).get()
        let expires = try #require(credentials.expiresAt)
        #expect(abs(expires.timeIntervalSince(amNow) - 12 * 3_600) < 1,
                "expiresAt 을 초로 읽었다 — \(expires) 는 1970년 근처다")
        #expect(credentials.planLabel == "max")
        // ★ 액세스 토큰은 값으로 들고 있지만 **에러·분류에는 담길 자리가 없다**(AILimitReadError 에 메시지 필드가 없다).
        #expect(credentials.accessToken.isEmpty == false)
    }

    /// 토큰이 비면 '미로그인'이다(항목은 있다) → 숨긴다.
    @Test
    func claudeEmptyTokenIsNotLoggedIn() {
        let json = #"{"claudeAiOauth":{"accessToken":"","expiresAt":9999999999999}}"#
        let result = AILimitClaudeReader.parseCredentials(Data(json.utf8))
        if case .failure(let error) = result { #expect(error.failure == .notLoggedIn) } else { Issue.record("빈 토큰을 통과시켰다") }
    }

    // MARK: 리더: Codex

    /// 실측 응답: 5시간 0% · 주간 56%. ★ **0% 창의 `reset_at` 은 투영이므로 nil 로 접는다.**
    ///
    /// 없으면: 화면이 "0% · 오후 6:59 리셋" 을 띄우고 그 시각이 호출마다 바뀐다(실측: 두 호출에 684초 =
    /// 경과 시간만큼 움직였다). 사용자는 "방금 리셋됐구나"로 읽고 쓰기 계획을 세운다.
    @Test
    func codexZeroPercentWindowDropsTheProjectedResetTime() throws {
        let snapshot = try AILimitCodexReader.parseUsage(
            Data(amCodexUsageJSON.utf8), observedAt: amNow, fallbackPlanLabel: nil, accountID: "acct-placeholder"
        ).get()
        #expect(snapshot.window(.fiveHour)?.usedPercent == 0)
        #expect(snapshot.window(.fiveHour)?.resetsAt == nil,
                "0% 창의 reset_at 을 믿었다 — 그 값은 now + 창길이 투영이다")
        // 주간은 **진짜 경계**다(두 호출에서 값이 같았다) → 그대로 쓴다. 기준선이 갈려야 위 단언이 뜻을 갖는다.
        #expect(snapshot.window(.weekly)?.usedPercent == 56)
        let weeklyReset = try #require(snapshot.window(.weekly)?.resetsAt)
        #expect(Int(weeklyReset.timeIntervalSince1970) == 1_791_666_011, "reset_at 을 밀리초로 읽었다")
        #expect(snapshot.planLabel == "plus")
        // 원문이 아니라 해시다(16자 hex).
        let fingerprint = try #require(snapshot.accountFingerprint)
        #expect(fingerprint.count == AILimitFingerprint.hexLength)
        #expect(fingerprint != "acct-placeholder")
    }

    /// 두 창이 **전부 null** 인 크레딧 사용자 → `.noPlan`. 창을 0% 로 지어내지 않는다.
    ///
    /// 없으면: 플랜 없는 사람의 카드에 "0% · 0%" 가 떠서 **리밋이 무한한 것처럼** 보인다.
    @Test
    func codexWithBothWindowsNullIsNoPlan() {
        let result = AILimitCodexReader.parseUsage(
            Data(amCodexNoPlanJSON.utf8), observedAt: amNow, fallbackPlanLabel: nil, accountID: nil
        )
        if case .failure(let error) = result {
            #expect(error.failure == .noPlan)
        } else {
            Issue.record("두 창이 null 인데 스냅샷을 만들었다 — 0% 를 지어냈다")
        }
        #expect(AILimitReadFailure.noPlan.noticeText(for: .codex) == "구독 리밋 없음")
        #expect(AILimitReadFailure.noPlan.hidesProvider == false)
        // 기준선: `rate_limit` 이 통째로 없으면 '모양을 모른다'(.malformed)이고 '플랜 없음'이 아니다.
        let unknownShape = AILimitCodexReader.parseUsage(
            Data("{}".utf8), observedAt: amNow, fallbackPlanLabel: nil, accountID: nil
        )
        if case .failure(let error) = unknownShape { #expect(error.failure == .malformed) }
    }

    /// 창이 **하나만** 오는 플랜(Starter)도 그 창만 쓴다 — 없는 창을 만들지 않는다.
    @Test
    func codexWithOnlyTheWeeklyWindowKeepsOneRow() throws {
        let json = """
        {"plan_type":"plus","rate_limit":{"primary_window":null,
        "secondary_window":{"used_percent":12,"limit_window_seconds":604800,"reset_after_seconds":100,"reset_at":1791666011}}}
        """
        let snapshot = try AILimitCodexReader.parseUsage(
            Data(json.utf8), observedAt: amNow, fallbackPlanLabel: nil, accountID: nil
        ).get()
        #expect(snapshot.windows.count == 1)
        #expect(snapshot.window(.fiveHour) == nil)
        #expect(snapshot.window(.weekly)?.usedPercent == 12)
    }

    /// ★★ **401 이 와도 `auth.json` 에 쓰지 않는다.**
    ///
    /// 우리가 `refresh_token` 으로 갱신해 파일을 덮으면 실제 codex CLI 와 회전 경합이 되어 **사용자가
    /// 로그아웃된다**(이 저장소가 자기 토큰으로 이미 겪은 사고). 그래서 리더에는 쓰기 경로가 아예 없다.
    ///
    /// 재는 방법: 실제 파일을 쓰고, 401 을 먹인 뒤 **바이트가 그대로인지** `cmp` 수준으로 확인한다
    /// (쓰기 함수가 없다는 사실만으로는 다음 사람이 더하는 날을 못 막는다).
    @Test
    func codexDoesNotWriteAuthFileOnUnauthorized() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("check-ai-limits-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let authPath = directory.appendingPathComponent("auth.json")
        let original = Data(amCodexAuthJSON(expirySeconds: amNow.timeIntervalSince1970 + 86_400).utf8)
        try original.write(to: authPath)
        let attributesBefore = try FileManager.default.attributesOfItem(atPath: authPath.path)

        let http = AMFakeHTTP()
        http.responses["chatgpt.com"] = AILimitHTTPResponse(
            status: 401, body: Data(#"{"detail":"Unauthorized"}"#.utf8)
        )
        // 실제 파일을 읽는다(기본 readFile) — 쓰기가 생기면 이 파일이 바뀐다.
        let reader = AILimitCodexReader(fetch: http.fetcher, codexHome: directory, appVersion: "0.3.45")
        let result = await reader.read(now: amNow)
        if case .failure(let error) = result {
            #expect(error.failure == .unauthorized)
        } else {
            Issue.record("401 을 성공으로 읽었다")
        }
        let after = try Data(contentsOf: authPath)
        #expect(after == original, "401 뒤 auth.json 이 바뀌었다 — 사용자를 Codex 에서 로그아웃시킨다")
        let attributesAfter = try FileManager.default.attributesOfItem(atPath: authPath.path)
        #expect(
            (attributesBefore[.modificationDate] as? Date) == (attributesAfter[.modificationDate] as? Date),
            "auth.json 의 수정 시각이 바뀌었다 — 같은 바이트로 덮어썼더라도 codex CLI 와 경합이다"
        )
        // 401 은 만료와 **같은 문구**로 접는다(우리가 갱신하지 않으므로 사용자가 할 일이 같다).
        #expect(AILimitReadFailure.unauthorized.noticeText(for: .codex) == "코덱스를 한 번 실행해 주세요")
    }

    /// `auth.json` 이 없으면 '미설치'이고 **네트워크를 치지 않는다**.
    @Test
    func codexWithoutAuthFileNeverCallsTheNetwork() async {
        let http = AMFakeHTTP()
        http.responses["chatgpt.com"] = AILimitHTTPResponse(status: 200, body: Data(amCodexUsageJSON.utf8))
        let reader = AILimitCodexReader(
            fetch: http.fetcher,
            codexHome: URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)"),
            appVersion: "0.3.45"
        )
        let result = await reader.read(now: amNow)
        if case .failure(let error) = result { #expect(error.failure == .notInstalled) }
        #expect(http.requests.isEmpty)
    }

    /// `account_id` 를 못 읽어도 **호출을 포기하지 않는다**(개인 계정에선 헤더 없이도 200 이다).
    @Test
    func codexCallsEvenWithoutAccountID() async throws {
        let json = """
        {"tokens":{"access_token":"\(amFakeJWT(expirySeconds: amNow.timeIntervalSince1970 + 86_400, plan: "plus", account: nil))"}}
        """
        let http = AMFakeHTTP()
        http.responses["chatgpt.com"] = AILimitHTTPResponse(status: 200, body: Data(amCodexUsageJSON.utf8))
        let reader = AILimitCodexReader(
            fetch: http.fetcher,
            codexHome: URL(fileURLWithPath: "/ignored"),
            appVersion: "0.3.45",
            readFile: { _ in Data(json.utf8) }
        )
        let snapshot = try await reader.read(now: amNow).get()
        #expect(snapshot.windows.isEmpty == false)
        let request = try #require(http.request(host: "chatgpt.com"))
        #expect(request.value(forHTTPHeaderField: "ChatGPT-Account-Id") == nil)
        // ★ User-Agent 를 사칭하지 않는다 — 우리 앱 이름이다.
        let agent = try #require(request.value(forHTTPHeaderField: "User-Agent"))
        #expect(agent.hasPrefix("check/"), "User-Agent 가 \(agent) 다")
        #expect(!agent.lowercased().contains("claude-cli"), "User-Agent 를 사칭했다")
    }

    /// JWT 에서 플랜과 account_id 를 **네트워크 없이** 꺼낸다.
    @Test
    func codexReadsPlanAndAccountFromTheJWT() throws {
        let token = amFakeJWT(
            expirySeconds: amNow.timeIntervalSince1970 + 86_400, plan: "plus", account: "acct-placeholder"
        )
        let json = #"{"tokens":{"access_token":"\#(token)"}}"#
        let credentials = try AILimitCodexReader.parseCredentials(Data(json.utf8)).get()
        #expect(credentials.planLabel == "plus")
        #expect(credentials.accountID == "acct-placeholder")
        #expect(credentials.expiresAt != nil)
    }

    // MARK: 리더: 안티그래비티

    /// ★★ **`remaining_fraction` 을 뒤집는다.** 여기서 틀리면 0% 와 100% 가 통째로 바뀐다.
    ///
    /// 픽스처는 그룹 둘 × 창 둘 = 네 칸이고 값이 **전부 다르다**:
    ///   Gemini  weekly 0.40(= 60% 썼다) · 5h 0.90(= 10%)
    ///   3P      weekly 0.80(= 20%)      · 5h 0.25(= 75%)
    /// 그래서 창마다 대표가 **다른 그룹**에서 나온다(weekly → Gemini 60%, 5h → 3P 75%).
    /// 부호를 안 뒤집으면 weekly 가 80%(= 3P 의 남은 비율)로 나와 **그룹까지 바뀐다** — 둘이 한 번에 잡힌다.
    @Test
    func antigravityInvertsRemainingFractionAndPicksTheWorstGroup() throws {
        let json = amAntigravityCLIJSON(
            geminiWeekly: 0.40, gemini5h: 0.90, thirdPartyWeekly: 0.80, thirdParty5h: 0.25
        )
        let snapshot = try AILimitAntigravityReader.parseCLI(Data(json.utf8), observedAt: amNow).get()
        #expect(snapshot.provider == .antigravity)
        #expect(snapshot.windows.count == 2, "그룹 둘을 그대로 네 줄로 올렸다 — 창마다 대표 하나여야 한다")
        let weekly = try #require(snapshot.window(.weekly))
        let fiveHour = try #require(snapshot.window(.fiveHour))
        #expect(abs(weekly.usedPercent - 60) < 0.001,
                "주간이 \(weekly.usedPercent)% 다 — 40 이면 뒤집지 않았고 20 이면 적게 쓴 그룹을 세웠다")
        #expect(abs(fiveHour.usedPercent - 75) < 0.001,
                "5시간이 \(fiveHour.usedPercent)% 다 — 25 면 뒤집지 않았고 10 이면 적게 쓴 그룹을 세웠다")
        // 쓴 비율이 0 보다 크므로 reset_time 은 믿는다(기준선이 아래 테스트와 갈린다).
        #expect(weekly.resetsAt != nil)
        #expect(fiveHour.resetsAt != nil)
    }

    /// 뒤집기의 두 끝: `remaining_fraction` 1.0 → 0% 썼다 · 0.0 → 100% 썼다.
    ///
    /// 그리고 **1.0(= 0% 씀)일 때 `reset_time` 은 투영이므로 접는다**(Codex 와 같은 함정).
    @Test
    func antigravityFractionEndpointsAndProjectedReset() throws {
        let untouched = try AILimitAntigravityReader.parseCLI(
            Data(amAntigravityCLIJSON(geminiWeekly: 1, gemini5h: 1, thirdPartyWeekly: 1, thirdParty5h: 1).utf8),
            observedAt: amNow
        ).get()
        #expect(untouched.window(.weekly)?.usedPercent == 0, "남은 1.0 을 100% 썼다로 읽었다")
        #expect(untouched.window(.weekly)?.resetsAt == nil, "0% 창의 reset_time 을 믿었다 — 그 값은 투영이다")

        let exhausted = try AILimitAntigravityReader.parseCLI(
            Data(amAntigravityCLIJSON(geminiWeekly: 0, gemini5h: 0, thirdPartyWeekly: 0, thirdParty5h: 0).utf8),
            observedAt: amNow
        ).get()
        #expect(exhausted.window(.weekly)?.usedPercent == 100, "남은 0 을 0% 썼다로 읽었다")
        #expect(exhausted.window(.weekly)?.resetsAt != nil, "다 쓴 창의 reset_time 은 진짜 경계다")
    }

    /// `status != "SUCCESS"` 는 실패다 — **100% 를 지어내지 않는다.**
    @Test
    func antigravityNonSuccessStatusIsAFailure() {
        let json = amAntigravityCLIJSON(
            status: "ERROR", geminiWeekly: 1, gemini5h: 1, thirdPartyWeekly: 1, thirdParty5h: 1
        )
        let result = AILimitAntigravityReader.parseCLI(Data(json.utf8), observedAt: amNow)
        if case .failure(let error) = result { #expect(error.failure == .network) } else { Issue.record("ERROR 를 성공으로 읽었다") }
        // 소문자 "success" 도 실패다(실측 봉투는 대문자다).
        let lower = amAntigravityCLIJSON(
            status: "success", geminiWeekly: 1, gemini5h: 1, thirdPartyWeekly: 1, thirdParty5h: 1
        )
        #expect((try? AILimitAntigravityReader.parseCLI(Data(lower.utf8), observedAt: amNow).get()) == nil)
    }

    /// `remaining_fraction` 이 없는 버킷(proto `oneof` 의 다른 갈래 · `disabled`)은 **버린다**.
    @Test
    func antigravitySkipsBucketsWithoutAFraction() throws {
        let json = """
        {"status":"SUCCESS","command":{"name":"usage","data":{"groups":[
          {"name":"G","buckets":[
            {"id":"a","window":"weekly","remaining_amount":12,"reset_time":"2026-10-13T19:11:25Z"},
            {"id":"b","window":"5h","remaining_fraction":0.5,"reset_time":"2026-10-07T00:11:25Z"},
            {"id":"c","window":"weekly","remaining_fraction":0.5,"disabled":true,
             "reset_time":"2026-10-13T19:11:25Z"}]}]}}}
        """
        let snapshot = try AILimitAntigravityReader.parseCLI(Data(json.utf8), observedAt: amNow).get()
        #expect(snapshot.windows.count == 1, "fraction 없는 버킷·disabled 버킷을 세웠다")
        #expect(snapshot.window(.fiveHour)?.usedPercent == 50)
        #expect(snapshot.window(.weekly) == nil)
    }

    /// `agy` 가 PATH 에 없으면 그 제공자는 '없음'이고 **프로세스를 띄우지 않는다**.
    @Test
    func antigravityWithoutTheBinaryRunsNoProcess() async {
        let process = AMFakeProcess()
        let reader = AILimitAntigravityReader(runner: process.runner, locate: { nil }, scratchDirectory: { nil })
        let result = await reader.read(now: amNow)
        if case .failure(let error) = result { #expect(error.failure == .notInstalled) }
        #expect(process.count(suffix: "agy") == 0)
        #expect(AILimitReadFailure.notInstalled.hidesProvider == true)
    }

    /// `agy` 를 띄울 때의 인자·데드라인·작업 디렉터리 계약.
    ///
    /// ★ `--log-file` 이 없으면 실행마다 ~19KB 가 사용자 홈(`~/.gemini/antigravity-cli/log/`)에 쌓인다.
    /// ★ 데드라인 90초 · 출력 상한 1 MiB · 빈 임시 디렉터리에서 실행.
    @Test
    func antigravityCommandContract() async throws {
        let process = AMFakeProcess()
        process.outcomes["agy"] = AILimitCommandOutput(
            status: 0,
            stdout: Data(amAntigravityCLIJSON(
                geminiWeekly: 0.5, gemini5h: 0.5, thirdPartyWeekly: 0.5, thirdParty5h: 0.5
            ).utf8)
        )
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("check-ai-limits-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        let reader = AILimitAntigravityReader(
            runner: process.runner,
            locate: { URL(fileURLWithPath: "/opt/homebrew/bin/agy") },
            scratchDirectory: { scratch }
        )
        _ = await reader.read(now: amNow)
        let command = try #require(process.commands.first)
        #expect(command.arguments.prefix(4) == ["-p", "/usage", "--output-format", "json"])
        #expect(command.arguments.contains("--log-file"), "로그를 돌리지 않으면 사용자 홈에 쌓인다")
        #expect(command.arguments.last?.hasPrefix(scratch.path) == true, "로그가 임시 폴더 밖으로 나간다")
        #expect(command.timeout == AILimitAntigravityReader.timeout)
        #expect(command.timeout == 90)
        #expect(command.outputLimit == AILimitProcess.defaultOutputLimit)
        #expect(command.outputLimit == 1 << 20)
        #expect(command.currentDirectory == scratch)
        // 리더가 끝나면 임시 폴더를 치운다(로그가 남지 않는다).
        #expect(!FileManager.default.fileExists(atPath: scratch.path), "임시 폴더가 남았다")
    }
}

// MARK: - 보조 픽스처(서명 없는 가짜 JWT)

/// 서명을 **검증하지 않는** JWT 리더용 픽스처. 세 번째 조각은 의미 없는 글자다 — 실제 토큰이 아니다.
private func amFakeJWT(expirySeconds: Double, plan: String?, account: String?) -> String {
    var claims: [String: Any] = ["exp": Int(expirySeconds)]
    if let plan { claims["chatgpt_plan_type"] = plan }
    if let account { claims["chatgpt_account_id"] = account }
    let payload = (try? JSONSerialization.data(withJSONObject: claims)) ?? Data("{}".utf8)
    func urlSafe(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    let header = urlSafe(Data(#"{"alg":"none","typ":"JWT"}"#.utf8))
    return "\(header).\(urlSafe(payload)).NOT-A-SIGNATURE"
}

/// `~/.codex/auth.json` 픽스처. 토큰 자리는 서명 없는 가짜 JWT다.
private func amCodexAuthJSON(expirySeconds: Double) -> String {
    """
    {"tokens":{"access_token":"\(amFakeJWT(expirySeconds: expirySeconds, plan: "plus", account: "acct-placeholder"))",
    "account_id":"acct-placeholder"},"last_refresh":"2026-09-30T00:00:00Z"}
    """
}

// MARK: - 프로덕션 프로세스 실행기 (실제 프로세스 — 작고 결정적인 것만)

/// 실행기를 돌리고 **최대 `within` 초만** 기다린다. 돌아오지 않으면 nil.
///
/// ★ 모든 프로세스 테스트가 이것을 지나는 이유: `withCheckedContinuation` 은 취소에 반응하지 않아
///   `.timeLimit` 트레이트로 끊을 수 없다(실측 — 변형본에서 7분을 넘겨도 빨개지지 않고 **매달렸다**).
///   매달리는 테스트는 결함을 알려 주는 게 아니라 스위트를 세운다. 그래서 기다림을 테스트가 직접 잰다.
private func amRun(
    _ runner: @escaping AILimitCommandRunner,
    _ command: AILimitCommand,
    within seconds: Double = 5
) async -> AILimitCommandOutput? {
    let box = OSAllocatedUnfairLock(initialState: AILimitCommandOutput?.none)
    let work = Task.detached {
        let output = await runner(command)
        box.withLock { $0 = output }
    }
    defer { work.cancel() }
    let deadline = Date().addingTimeInterval(seconds)
    while box.withLock({ $0 }) == nil, Date() < deadline {
        try? await Task.sleep(for: .milliseconds(50))
    }
    return box.withLock { $0 }
}


@Suite("AILimitsMac — 프로세스 실행기: 반드시 돌아온다")
struct AILimitsMacProcessTests {
    /// ★★ **실행기는 반드시 돌아온다.** 이 테스트가 없으면 돌아오지 않는 구현이 초록으로 배포된다.
    ///
    /// 2026-10-07 실증에서 실제로 그랬다: 세션의 세 핸들러가 `[weak self]` 였고, `start` 가 반환한 순간
    /// 세션을 가리키는 강한 참조가 하나도 남지 않아 해제됐다. 그러면 대기 중인 `CheckedContinuation` 을
    /// 부를 주체가 없어 **호출자가 영원히 멈춘다** — 90초 데드라인조차 약참조라 울리지 않았다(12분 넘게 매달렸다).
    ///
    /// 왜 치명적인가: `AILimitStore.refreshIfDue` 는 `inFlight = true` 를 세우고 `defer` 로 내린다.
    /// 러너가 돌아오지 않으면 그 `defer` 가 영원히 안 돌아 **앱 수명 동안 리밋이 한 번도 갱신되지 않는다**
    /// (이 저장소의 '세션 영구고착' 과 같은 결의 결함이고, 화면은 낡은 숫자를 조용히 그린다).
    ///
    /// ★ **기다림을 이 테스트가 직접 재는 이유**: `withCheckedContinuation` 은 취소에 반응하지 않으므로
    ///   `.timeLimit` 트레이트로는 못 끊는다(위 변형을 넣고 돌려 봤다 — 7분을 넘겨도 빨개지지 않고 **매달렸다**).
    ///   매달리는 테스트는 결함을 알려 주는 게 아니라 스위트를 세운다. 그래서 결과를 상자에 받고 **5초만**
    ///   기다린 뒤 판정한다 — 변형이 들어오면 5초 뒤 깨끗하게 빨개진다(실증: 변형본에서 이 단언이 실패한다).
    ///
    /// `/bin/echo` 를 쓰는 이유: 즉시 끝나고 출력이 결정적이며 어느 맥에나 있다.
    @Test
    func liveProcessRunnerAlwaysResumesTheContinuation() async {
        let output = await amRun(AILimitProcess.live(), AILimitCommand(
            executable: URL(fileURLWithPath: "/bin/echo"),
            arguments: ["check-ai-limits"],
            timeout: 10
        ))
        guard let output else {
            Issue.record("실행기가 5초 안에 돌아오지 않았다 — 세션이 해제돼 continuation 이 영원히 매달린다")
            return
        }
        #expect(output.launchFailed == false)
        #expect(output.timedOut == false)
        #expect(output.status == 0)
        #expect(String(data: output.stdout, encoding: .utf8) == "check-ai-limits\n")
    }

    /// 데드라인이 실제로 프로세스를 끊고 돌아온다(`agy` 가 멈추는 날 앱이 함께 멈추지 않게).
    ///
    /// ★ stdin 이 `/dev/null` 이라는 것도 여기서 함께 재는 셈이다 — 아니면 `agy` 가 입력을 기다려
    ///   데드라인까지 매달린다(실측).
    @Test
    func liveProcessRunnerEnforcesTheDeadline() async {
        let started = Date()
        let output = await amRun(
            AILimitProcess.live(),
            AILimitCommand(executable: URL(fileURLWithPath: "/bin/sleep"), arguments: ["30"], timeout: 1),
            within: 10
        )
        let elapsed = Date().timeIntervalSince(started)
        guard let output else {
            Issue.record("데드라인 1초인데 10초 안에 돌아오지 않았다 — 타이머가 세션을 살려 두지 못한다")
            return
        }
        #expect(output.timedOut, "데드라인이 안 울렸다")
        #expect(elapsed < 10, "데드라인 1초인데 \(elapsed)초 걸렸다")
        // 기준선이 갈린다: `/bin/sleep 30` 은 스스로 끝나지 않으므로 위 단언이 "그냥 끝났다"를 재는 게 아니다.
        #expect(output.status != 0)
    }

    /// 실행 파일이 없으면 `launchFailed` 로 **즉시** 돌아온다(예외가 새지 않는다).
    @Test
    func liveProcessRunnerReportsLaunchFailure() async {
        let output = await amRun(AILimitProcess.live(), AILimitCommand(
            executable: URL(fileURLWithPath: "/nonexistent/check-ai-limits-\(UUID().uuidString)"),
            arguments: [],
            timeout: 5
        ))
        guard let output else {
            Issue.record("기동 실패에서 돌아오지 않았다 — 예외 경로가 continuation 을 버렸다")
            return
        }
        #expect(output.launchFailed)
        #expect(output.stdout.isEmpty)
    }

    /// `inert()` 실행기는 아무것도 띄우지 않는다(주입 기본값의 fail-closed).
    @Test
    func inertProcessRunnerLaunchesNothing() async {
        let output = await AILimitProcess.inert()(AILimitCommand(
            executable: URL(fileURLWithPath: "/bin/echo"), arguments: ["x"], timeout: 1
        ))
        #expect(output.launchFailed)
    }
}

// MARK: - 스토어

@Suite("AILimitsMac — 스토어: 간격·백오프·영속·자동 감지")
@MainActor
struct AILimitsMacStoreTests {
    /// 성공 스냅샷 하나를 돌려주는 러너.
    private func store(
        defaults: UserDefaults,
        outcome: @escaping @Sendable (Date) -> AILimitReadOutcome,
        now: @escaping () -> Date = { amNow }
    ) -> AILimitStore {
        AILimitStore(defaults: defaults, clock: now, runner: { outcome($0) })
    }

    nonisolated private static func claudeOutcome(used: Double = 27, weekly: Double = 60, observedAt: Date = amNow) -> AILimitReadOutcome {
        AILimitReadOutcome(results: [.claude: .success(AILimitProviderSnapshot(
            provider: .claude,
            windows: [
                AILimitWindowSnapshot(window: .fiveHour, usedPercent: used, resetsAt: observedAt.addingTimeInterval(3_600),
                                      observedAt: observedAt, source: .local),
                AILimitWindowSnapshot(window: .weekly, usedPercent: weekly, resetsAt: observedAt.addingTimeInterval(86_400),
                                      observedAt: observedAt, source: .local)
            ],
            planLabel: "max"
        ))])
    }

    /// 자격증명이 하나도 없으면 `isAvailable == false` → 화면이 섹션을 통째로 숨긴다(설정 토글 없음).
    @Test
    func noCredentialsMeansTheSectionIsHidden() async {
        let defaults = amDefaults()
        let subject = store(defaults: defaults, outcome: { _ in
            AILimitReadOutcome(results: [
                .claude: .failure(AILimitReadError(.notInstalled)),
                .codex: .failure(AILimitReadError(.notInstalled)),
                .antigravity: .failure(AILimitReadError(.notInstalled))
            ])
        })
        await subject.refreshIfDue(now: amNow)
        #expect(subject.isAvailable == false)
        #expect(subject.visibleProviders.isEmpty)
        #expect(subject.listedProviders.isEmpty)
    }

    /// 숨기지 **않는** 실패(만료·429·네트워크)만 있어도 섹션은 보인다 — 그 사람은 그 도구를 쓰고 있다.
    ///
    /// 기준선이 위 테스트와 갈린다: 둘이 같은 답이면 `isAvailable` 을 `true` 로 고정해도 둘 다 초록이다.
    @Test
    func expiredOnlyStillShowsTheSection() async {
        let subject = store(defaults: amDefaults(), outcome: { _ in
            AILimitReadOutcome(results: [
                .claude: .failure(AILimitReadError(.expired)),
                .codex: .failure(AILimitReadError(.notInstalled)),
                .antigravity: .failure(AILimitReadError(.notInstalled))
            ])
        })
        await subject.refreshIfDue(now: amNow)
        #expect(subject.isAvailable == true)
        #expect(subject.listedProviders == [.claude])
        #expect(subject.noticeText(provider: .claude) == "클로드 코드를 한 번 실행해 주세요")
    }

    /// 주기 10분 · 강제 갱신 하한 5분. ★ 하한이 없으면 팝오버 여닫기만으로 Claude 가 429 로 잠긴다.
    @Test
    func intervalAndForcedFloor() async {
        let subject = store(defaults: amDefaults(), outcome: { _ in Self.claudeOutcome() })
        await subject.refreshIfDue(now: amNow)
        #expect(subject.runnerCallCount == 1)
        // 1분 뒤: 평상시도 force 도 안 돈다.
        await subject.refreshIfDue(now: amNow.addingTimeInterval(60))
        await subject.refreshIfDue(now: amNow.addingTimeInterval(60), force: true)
        #expect(subject.runnerCallCount == 1, "강제 갱신이 하한을 무시했다 — 여닫기만으로 429 를 맞는다")
        // 5분: force 만 돈다(평상시 주기는 10분이다).
        await subject.refreshIfDue(now: amNow.addingTimeInterval(300))
        #expect(subject.runnerCallCount == 1, "평상시 주기가 5분으로 내려갔다")
        await subject.refreshIfDue(now: amNow.addingTimeInterval(300), force: true)
        #expect(subject.runnerCallCount == 2)
        await subject.refreshIfDue(now: amNow.addingTimeInterval(301))
        #expect(subject.runnerCallCount == 2, "마지막 시도 1초 뒤에 또 돌았다")
        // 마지막 시도(+300)에서 10분 뒤.
        await subject.refreshIfDue(now: amNow.addingTimeInterval(900))
        #expect(subject.runnerCallCount == 3)
        #expect(AILimitStore.refreshInterval == 600)
        #expect(AILimitStore.forcedRefreshFloor == 300)
    }

    /// 429 를 받으면 `retry-after` 까지 **완전히 침묵한다**(30초마다 다시 노크하지 않는다).
    @Test
    func rateLimitSilencesUntilRetryAfter() async {
        let subject = store(defaults: amDefaults(), outcome: { _ in
            AILimitReadOutcome(results: [.claude: .failure(AILimitReadError(.rateLimited, retryAfter: 300))])
        })
        await subject.refreshIfDue(now: amNow)
        #expect(subject.runnerCallCount == 1)
        // force 도 못 뚫는다 — 금지창 안에서 노크하는 것이 바로 그 금지창을 길게 만든다.
        await subject.refreshIfDue(now: amNow.addingTimeInterval(299), force: true)
        #expect(subject.runnerCallCount == 1, "429 금지창 안에서 다시 노크했다")
        await subject.refreshIfDue(now: amNow.addingTimeInterval(301), force: true)
        #expect(subject.runnerCallCount == 2)
        #expect(subject.noticeText(provider: .claude) == "잠시 뒤 다시")
    }

    /// 읽기에 실패해도 **직전 값을 버리지 않는다**(사용률은 올라가기만 하므로 하한이다).
    @Test
    func failureKeepsTheLastNumbersAsAFloor() async {
        let defaults = amDefaults()
        let first = Self.claudeOutcome(used: 27, weekly: 60)
        let box = AMOutcomeBox(outcome: first)
        let subject = AILimitStore(defaults: defaults, clock: { amNow }, runner: { _ in box.outcome })
        await subject.refreshIfDue(now: amNow)
        #expect(subject.visibleProviders.count == 1)

        // 네트워크가 끊겼다.
        box.outcome = AILimitReadOutcome(results: [.claude: .failure(AILimitReadError(.network))])
        await subject.refreshIfDue(now: amNow.addingTimeInterval(601))
        #expect(subject.visibleProviders.count == 1, "네트워크 실패에 숫자를 버렸다")
        #expect(subject.bundle?.provider(.claude)?.window(.fiveHour)?.usedPercent == 27)
        // 네트워크 실패에는 **문구가 없다** — 빨간 글씨로 사용자를 놀래지 않는다.
        #expect(subject.noticeText(provider: .claude) == nil)

        // 반면 로그아웃(미로그인)은 숫자까지 지운다 — 기기를 넘겨준 사람의 옛 숫자를 남기지 않는다.
        box.outcome = AILimitReadOutcome(results: [.claude: .failure(AILimitReadError(.notLoggedIn))])
        await subject.refreshIfDue(now: amNow.addingTimeInterval(1_202))
        #expect(subject.visibleProviders.isEmpty, "로그아웃 뒤에도 옛 숫자를 들고 있다")
    }

    /// 디스크에 영속되고 재시작 뒤 복원된다(하한으로 쓰인다).
    @Test
    func snapshotsPersistAcrossRestart() async {
        let defaults = amDefaults()
        let first = store(defaults: defaults, outcome: { _ in Self.claudeOutcome(used: 42, weekly: 71) })
        await first.refreshIfDue(now: amNow)
        #expect(first.bundle != nil)

        let reborn = AILimitStore(defaults: defaults, clock: { amNow }, runner: { _ in AILimitReadOutcome() })
        #expect(reborn.bundle?.provider(.claude)?.window(.fiveHour)?.usedPercent == 42)
        #expect(reborn.bundle?.provider(.claude)?.window(.weekly)?.usedPercent == 71)
        #expect(reborn.isAvailable == true)
        // ★ 간격은 **재시작을 넘어 산다.** 방금(amNow) 시도한 장부가 디스크에 남아 있으므로 바로는 안 된다 —
        //   안 그러면 앱을 몇 번 켜는 것만으로 Claude 의 5분/5회 상한을 넘겨 사용자 계정이 잠긴다
        //   (`AILimitStore` 머리말 ★). 주기(600초)가 지나면 다시 열린다.
        #expect(reborn.isDue(now: amNow) == false)
        #expect(reborn.isDue(now: amNow.addingTimeInterval(601)) == true)
    }

    /// **새로 읽은 값이 통째로 이긴다** — 리셋을 지난 창은 값이 내려가는 것이 정답이다.
    ///
    /// 없으면: `max(옛, 새)` 로 바꿔도 초록이고, 그러면 리셋이 지나도 사용률이 영원히 안 내려간다
    /// (폐기된 `max(로컬, 계정)` 증폭기와 같은 사고).
    @Test
    func freshReadReplacesTheOldValueEvenWhenLower() async {
        let box = AMOutcomeBox(outcome: Self.claudeOutcome(used: 90, weekly: 95))
        let subject = AILimitStore(defaults: amDefaults(), clock: { amNow }, runner: { _ in box.outcome })
        await subject.refreshIfDue(now: amNow)
        #expect(subject.bundle?.provider(.claude)?.window(.fiveHour)?.usedPercent == 90)
        box.outcome = Self.claudeOutcome(used: 3, weekly: 95, observedAt: amNow.addingTimeInterval(601))
        await subject.refreshIfDue(now: amNow.addingTimeInterval(601))
        #expect(subject.bundle?.provider(.claude)?.window(.fiveHour)?.usedPercent == 3,
                "새 값이 더 작아서 버려졌다 — 리셋 뒤 사용률이 영원히 안 내려간다")
    }

    /// `inert()` 는 아무것도 읽지 않는다(주입을 잊은 테스트의 fail-closed).
    @Test
    func inertStoreReadsNothing() async {
        let subject = AILimitStore.inert()
        await subject.refreshIfDue(now: amNow, force: true)
        #expect(subject.isAvailable == false)
        #expect(subject.bundle?.providers.isEmpty ?? true)
    }

    /// `inert()` 가 바퀴를 돌아도 `~/Library/Preferences` 에 **한 항목도** 안 남는다.
    ///
    /// 왜 이 그물이 필요한가 — `PreferencesLeakGateTests` 의 소스 검사는 `Tests/` 만 훑는다. 그래서 **프로덕션**
    /// 코드가 평범한 이름으로 스위트를 열면 그 게이트가 못 본다. 초안 `inert()` 가 정확히 그랬고
    /// (`"check.aiLimits.inert.\(UUID())"`), `refresh` 끝의 `persist()` 가 실패 표를 빈 사전이라도 쓰는 바람에
    /// **inert 인스턴스마다 plist 하나**가 떨어졌다 — 전체 스위트 한 바퀴에 1,454개(2026-10-07 실측). 62만 개가
    /// `cfprefsd` 를 죽인 그 사고와 같은 가족이다. `WorkTimerStore` 의 기본값이라 바퀴 수가 테스트 수에 비례한다.
    ///
    /// 측정 방식은 그 게이트를 본떴다: 폴더의 **전체 항목** 집합을 찍고(접두사로 안 좁힌다 — 다음 접두사를 또
    /// 놓친다), 여러 회차의 **최솟값**으로 건다(남의 1회성 쓰기가 세 회차에 모두 걸릴 일은 없다).
    @Test
    func inertStoreLeavesNoPlistInLibraryPreferences() async throws {
        let sanity = try amPreferencesEntries()
        #expect(sanity.contains(".GlobalPreferences.plist"),
                "~/Library/Preferences 를 못 읽고 있다(\(sanity.count)개) — 이 단언은 공허하다")

        var added: [Set<String>] = []
        for _ in 0..<3 {
            let before = try amPreferencesEntries()
            for _ in 0..<4 {
                // 바퀴를 **돌린다.** 생성만 하면 `persist()` 가 안 불려 아무것도 안 쓰고, 그러면 누수가 없는
                // 워크로드라 아래 단언이 장식이 된다(기준선이 같은 입력이면 그 테스트는 영원히 초록이다).
                await AILimitStore.inert().refreshIfDue(now: amNow, force: true)
            }
            // 미뤄진 쓰기를 창 안으로 끌어온다 — 안 하면 "after" 가 거짓이고 누수를 놓치는 쪽으로 기운다.
            _ = CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            added.append(try amPreferencesEntries().subtracting(before))
        }

        let quietest = added.min(by: { $0.count < $1.count }) ?? []
        #expect(quietest.isEmpty, """
            inert() 가 ~/Library/Preferences 에 새 항목을 남겼다(회차별 \(added.map(\.count))개).
            앞 5개: \(quietest.sorted().prefix(5).joined(separator: ", "))
            → 스위트 이름이 절대 경로가 아니게 됐다는 뜻이다. AILimitStore.inert() 의 ★★ 주석을 보라.
            """)

        // 워크로드가 **진짜로** plist 를 만들었는지 — 안 만들었으면 위 단언이 아무것도 안 지킨 채 초록이다.
        // 떨어지는 자리는 $TMPDIR 이어야 한다(고정 이름이라 기계당 한 개).
        let landing = FileManager.default.temporaryDirectory
            .appendingPathComponent("check-ai-limits-inert.plist").path
        var landed = FileManager.default.fileExists(atPath: landing)
        for _ in 0..<50 where !landed {          // cfprefsd 의 flush 는 비동기다.
            try? await Task.sleep(for: .milliseconds(20))
            landed = FileManager.default.fileExists(atPath: landing)
        }
        #expect(landed, "inert() 가 $TMPDIR 에 plist 를 안 만들었다(\(landing)) — 위 단언이 공허해진다")
    }

    /// 한 줄 요약은 **창 종류별 최악**을 둘로 합친다(제공자가 셋이어도 숫자는 둘이다).
    @Test
    func summaryCombinesWorstPerWindow() async {
        let subject = store(defaults: amDefaults(), outcome: { _ in
            AILimitReadOutcome(results: [
                .claude: .success(AILimitProviderSnapshot(provider: .claude, windows: [
                    AILimitWindowSnapshot(window: .fiveHour, usedPercent: 27, resetsAt: nil, observedAt: amNow, source: .local),
                    AILimitWindowSnapshot(window: .weekly, usedPercent: 60, resetsAt: nil, observedAt: amNow, source: .local)
                ])),
                .codex: .success(AILimitProviderSnapshot(provider: .codex, windows: [
                    AILimitWindowSnapshot(window: .fiveHour, usedPercent: 88, resetsAt: nil, observedAt: amNow, source: .local),
                    AILimitWindowSnapshot(window: .weekly, usedPercent: 12, resetsAt: nil, observedAt: amNow, source: .local)
                ]))
            ])
        })
        await subject.refreshIfDue(now: amNow)
        #expect(CheckAILimitsRow.valueText(store: subject, now: amNow) == "88% · 60%",
                "창별 최악이 아니라 평균·첫 제공자를 썼다")
        #expect(subject.summary(now: amNow).percent == 88)
    }
}

/// 러너 결과를 테스트 중에 갈아 끼우는 상자(값 타입 캡처로는 두 번째 결과를 줄 수 없다).
private final class AMOutcomeBox: @unchecked Sendable {
    var outcome: AILimitReadOutcome
    init(outcome: AILimitReadOutcome) { self.outcome = outcome }
}

// MARK: - 업로드 본문

@Suite("AILimitsMac — 업로드 본문: 키 집합·클램프·장부")
struct AILimitsMacUploadTests {
    private func snapshot(
        _ provider: AILimitProvider,
        fiveHour: Double?,
        weekly: Double?,
        plan: String? = nil,
        fingerprint: String? = nil
    ) -> AILimitProviderSnapshot {
        var windows: [AILimitWindowSnapshot] = []
        if let fiveHour {
            windows.append(AILimitWindowSnapshot(window: .fiveHour, usedPercent: fiveHour,
                                                 resetsAt: amNow.addingTimeInterval(3_600),
                                                 observedAt: amNow, source: .local))
        }
        if let weekly {
            windows.append(AILimitWindowSnapshot(window: .weekly, usedPercent: weekly,
                                                 resetsAt: nil, observedAt: amNow, source: .local))
        }
        return AILimitProviderSnapshot(provider: provider, windows: windows,
                                       planLabel: plan, accountFingerprint: fingerprint)
    }

    /// ★★ **키 집합이 모든 행에서 같다.**
    ///
    /// PostgREST 는 배열 본문의 키 집합이 행마다 다르면 스키마를 보기도 전에 400 PGRST102 로 **본문 전체**를
    /// 거절하고, 400 은 조용히 삼켜져 그 사람의 행이 **영원히 한 줄도** 안 올라간다(v0.2.41 실제 사고).
    ///
    /// 픽스처는 그 혼합이 실제로 생기는 모양이다: Claude 는 두 창 + 플랜, Codex 는 5시간만 + 지문,
    /// 안티그래비티는 주간만 + 플랜·지문 없음. 합성 `Encodable` 이면 세 행의 키가 전부 다르다.
    @Test
    func everyUploadRowHasTheSameKeySet() throws {
        let rows = [
            AILimitUpsertRow(userId: "u", deviceId: "d", provider: "claude",
                             fiveHourPercent: 27, fiveHourResetsAt: "2026-10-06T19:00:00Z",
                             weeklyPercent: 60, weeklyResetsAt: "2026-10-12T03:00:00Z",
                             planLabel: "max", accountFingerprint: nil, observedAt: "2026-10-07T00:00:00Z"),
            AILimitUpsertRow(userId: "u", deviceId: "d", provider: "codex",
                             fiveHourPercent: 0, fiveHourResetsAt: nil,
                             weeklyPercent: nil, weeklyResetsAt: nil,
                             planLabel: nil, accountFingerprint: "0123456789abcdef",
                             observedAt: "2026-10-07T00:00:00Z"),
            AILimitUpsertRow(userId: "u", deviceId: "d", provider: "antigravity",
                             fiveHourPercent: nil, fiveHourResetsAt: nil,
                             weeklyPercent: 75, weeklyResetsAt: nil,
                             planLabel: nil, accountFingerprint: nil, observedAt: "2026-10-07T00:00:00Z")
        ]
        let data = try JSONEncoder().encode(rows)
        let decoded = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        #expect(decoded.count == 3)
        let expected = Set(AILimitUpsertRow.CodingKeys.allCases.map(\.rawValue))
        #expect(expected.count == 10, "컬럼이 \(expected.count) 개다 — 더하거나 뺐으면 이 숫자도 함께 봐라")
        for (index, row) in decoded.enumerated() {
            #expect(Set(row.keys) == expected,
                    "\(index)번 행의 키가 \(Set(row.keys).symmetricDifference(expected)) 만큼 다르다 — PGRST102 로 본문 전체가 거절된다")
        }
        // ★ nil 이 **생략이 아니라 null** 로 나갔는지 확인한다(키가 있다는 것만으로는 부족하다 —
        //   JSONSerialization 은 null 을 NSNull 로 준다).
        #expect(decoded[1]["weekly_percent"] is NSNull, "nil 이 생략됐다 — 합성 Encodable 로 돌아갔다")
        #expect(decoded[2]["five_hour_percent"] is NSNull)
        #expect(decoded[0]["account_fingerprint"] is NSNull)
        // `updated_at` 은 **서버가 쥔다**(터치 트리거). 보내면 버려지지만 키 집합을 흔들 자리를 만들지 않는다.
        #expect(!expected.contains("updated_at"))
    }

    /// 퍼센트는 0…100 으로 클램프하고 NaN·무한은 **버린다**(null).
    ///
    /// 서버 CHECK 가 23514 로 그 행을 통째로 거절하고 거절은 조용하다. NaN 은 더 나쁘다 — PostgREST 가
    /// JSON 아닌 `NaN` 을 내려보내 폰의 응답 파싱이 세 제공자 모두 통째로 깨진다.
    @Test
    func percentIsClampedAndNonFiniteIsDropped() {
        #expect(SupabaseWorkService.aiLimitPercent(27) == 27)
        #expect(SupabaseWorkService.aiLimitPercent(-3) == 0)
        #expect(SupabaseWorkService.aiLimitPercent(100.0000001) == 100)
        #expect(SupabaseWorkService.aiLimitPercent(101) == 100)
        #expect(SupabaseWorkService.aiLimitPercent(.nan) == nil)
        #expect(SupabaseWorkService.aiLimitPercent(.infinity) == nil)
        #expect(SupabaseWorkService.aiLimitPercent(nil) == nil)
    }

    /// 플랜 라벨은 32자까지. 넘으면 **버린다**(잘라 뜻이 반쯤 남은 라벨보다 없는 쪽이 정직하다).
    @Test
    func planLabelContract() {
        #expect(AILimitPlanLabelContract.normalized("plus") == "plus")
        #expect(AILimitPlanLabelContract.normalized("  max  ") == "max")
        #expect(AILimitPlanLabelContract.normalized("") == nil)
        #expect(AILimitPlanLabelContract.normalized("   ") == nil)
        #expect(AILimitPlanLabelContract.normalized(String(repeating: "x", count: 33)) == nil)
        #expect(AILimitPlanLabelContract.normalized(String(repeating: "x", count: 32))?.count == 32)
        #expect(AILimitPlanLabelContract.normalized(nil) == nil)
    }

    /// 계정 지문은 **해시만** — `@` 가 든 값은 서버 CHECK 가 거부한다(이메일을 그 칸에 넣는 사고).
    @Test
    func accountFingerprintIsNeverRawIdentity() throws {
        let fingerprint = try #require(AILimitFingerprint.make("someone@example.com"))
        #expect(!fingerprint.contains("@"), "이메일이 지문 칸에 그대로 들어갔다")
        #expect(fingerprint.count == AILimitFingerprint.hexLength)
        #expect(fingerprint.allSatisfy { $0.isHexDigit })
        #expect(AILimitFingerprint.make("") == nil)
        #expect(AILimitFingerprint.make("   ") == nil)
    }

    /// 충돌키는 PK 그대로다(기기별 행 — 맥 두 대가 서로를 덮지 않는다).
    @Test
    func conflictKeyIsThePrimaryKey() {
        #expect(SupabaseWorkService.aiLimitsConflictKey == "user_id,device_id,provider")
        #expect(SupabaseWorkService.aiLimitsPath == "/rest/v1/ai_limits")
    }

    /// 칸 경계에 **맞춰 놓은** 관측 시각. 칸 안/밖을 결정적으로 고르기 위해서다 — amNow 가 칸 어디에
    /// 떨어지는지에 기대면 상수를 바꾸는 날 이 테스트가 이유 없이 뜻을 잃는다.
    private var bucketStart: Date {
        Date(timeIntervalSince1970: Double(AILimitUploadLedger.observedBucket(amNow))
            * AILimitUploadLedger.observedBucketSeconds)
    }

    private func claudeSnapshot(percent: Double, observedAt: Date, resetsAt: Date?) -> AILimitSnapshotBundle {
        AILimitSnapshotBundle(providers: [AILimitProviderSnapshot(
            provider: .claude,
            windows: [
                AILimitWindowSnapshot(window: .fiveHour, usedPercent: percent,
                                      resetsAt: resetsAt, observedAt: observedAt, source: .local),
                AILimitWindowSnapshot(window: .weekly, usedPercent: 60, resetsAt: nil,
                                      observedAt: observedAt, source: .local)
            ],
            planLabel: "max"
        )])
    }

    /// ★ 장부 지문은 **조건 둘**을 본다: 값이 바뀌었나 · 관측 시각이 한 칸 넘게 움직였나.
    ///
    /// 초안은 `observedAt` 을 통째로 뺐다("보면 게이트가 영원히 참이다"). 그 결과 서버 `observed_at` 이
    /// "마지막으로 **값이 바뀐** 시각"이 됐고, 폰·위젯의 신선도 축은 그 칸 하나로 서 있어서 — 맥이 10분마다
    /// 정상으로 읽는데 사용률이 몇 시간 그대로면 — 폰은 `60% 이상 · 4시간 전`, 같은 순간 맥 팝오버는
    /// `60% · 방금` 이었다. 그래서 관측 시각을 **거친 칸**으로 지문에 넣는다(초 단위면 게이트가 없는 것과 같다).
    @Test
    func uploadLedgerResendsWhenTheObservationBucketMoves() {
        let early = claudeSnapshot(percent: 27, observedAt: bucketStart, resetsAt: amNow.addingTimeInterval(3_600))
        // ① 같은 칸 안에서 다시 봤다 → 보내지 않는다(게이트가 살아 있다 — 10분마다 같은 본문을 쏘지 않는다).
        let sameBucket = claudeSnapshot(
            percent: 27,
            observedAt: bucketStart.addingTimeInterval(AILimitUploadLedger.observedBucketSeconds - 1),
            resetsAt: amNow.addingTimeInterval(3_600)
        )
        #expect(AILimitUploadLedger.fingerprint(early) == AILimitUploadLedger.fingerprint(sameBucket),
                "같은 칸 안의 재관측으로 재전송한다 — 변경 게이트가 없는 것과 같다")
        // ② 칸이 넘어갔다 → **값이 같아도** 보낸다(폰의 나이 캡션이 다시 젊어져야 한다).
        let nextBucket = claudeSnapshot(
            percent: 27,
            observedAt: bucketStart.addingTimeInterval(AILimitUploadLedger.observedBucketSeconds),
            resetsAt: amNow.addingTimeInterval(3_600)
        )
        #expect(AILimitUploadLedger.fingerprint(early) != AILimitUploadLedger.fingerprint(nextBucket),
                "관측이 한 칸 넘게 움직였는데 안 올린다 — 폰이 맥보다 낡아 보인다")
        // 칸 크기는 신선도 경계보다 **넉넉히** 짧아야 한다: 10분 주기 × 칸 하나면 재전송 간격이
        // 최대 (주기 + 칸)이고, 그게 "이상"이 붙는 경계(recentWithin)를 넘으면 맥이 켜져 있는데도 폰이 하한이 된다.
        #expect(AILimitStore.refreshInterval + AILimitUploadLedger.observedBucketSeconds
                < AILimitFreshnessRule.recentWithin,
                "칸(\(AILimitUploadLedger.observedBucketSeconds)초)이 너무 크다 — 맥이 깨어 있는데 폰이 `이상`을 붙인다")
        // 기준선이 갈려야 위 단언이 뜻을 갖는다: **같은 칸에서** 사용률만 바뀌어도 지문이 바뀐다
        // (칸만 보는 지문으로 퇴화하면 여기서 빨개진다).
        let moved = claudeSnapshot(percent: 28, observedAt: bucketStart, resetsAt: amNow.addingTimeInterval(3_600))
        #expect(AILimitUploadLedger.fingerprint(early) != AILimitUploadLedger.fingerprint(moved))
        // 리셋 시각이 바뀌어도 올린다(창 경계가 움직인 것은 사용자에게 보이는 사실이다) — 역시 같은 칸에서.
        let rescheduled = claudeSnapshot(percent: 27, observedAt: bucketStart, resetsAt: amNow.addingTimeInterval(7_200))
        #expect(AILimitUploadLedger.fingerprint(early) != AILimitUploadLedger.fingerprint(rescheduled))
    }

    /// 미연동 제공자는 행을 만들지 않는다(빈 창을 0% 로 올리지 않는다).
    @Test
    func unlinkedProvidersProduceNoRow() {
        let bundle = AILimitSnapshotBundle(providers: [
            snapshot(.claude, fiveHour: 27, weekly: 60),
            AILimitProviderSnapshot(provider: .codex, windows: [])
        ])
        #expect(bundle.visibleProviders.count == 1)
        #expect(AILimitUploadLedger.fingerprint(bundle).contains("codex") == false)
    }
}

// MARK: - 팝오버 폭 (실측)

@Suite("AILimitsMac — 팝오버 한 줄 폭 예산")
@MainActor
struct AILimitsMacWidthTests {
    /// caption / caption2 는 macOS 에서 **둘 다 10pt** 다. 글자수가 아니라 폭으로 재는 자리의 기준이다.
    private func width(_ text: String, bold: Bool = false, mono: Bool = false) -> CGFloat {
        let font: NSFont = mono
            ? NSFont.monospacedDigitSystemFont(ofSize: 10, weight: bold ? .bold : .regular)
            : NSFont.systemFont(ofSize: 10, weight: bold ? .bold : .regular)
        return (text as NSString).size(withAttributes: [.font: font]).width
    }

    /// 전제: 두 글꼴 스타일이 같은 포인트다(이 값이 바뀌면 아래 실측 상수가 전부 거짓이 된다).
    @Test
    func captionStylesAreTenPointOnMac() {
        #expect(NSFont.preferredFont(forTextStyle: .caption1).pointSize == 10)
        #expect(NSFont.preferredFont(forTextStyle: .caption2).pointSize == 10)
    }

    /// 상수가 **실측과 같다**(0.5pt 안). 글꼴·문구가 바뀌면 여기서 먼저 빨개진다.
    @Test
    func measuredConstantsMatchTheRealGlyphWidths() {
        #expect(abs(width("AI 리밋") - AILimitRowWidthBudget.labelWidth) < 0.5,
                "\"AI 리밋\" 실측 \(width("AI 리밋"))")
        #expect(abs(width("자세히 ›") - AILimitRowWidthBudget.detailWidth) < 0.5,
                "\"자세히 ›\" 실측 \(width("자세히 ›"))")
        let worst = width("100% 이상 · 100% 이상", bold: true, mono: true)
        #expect(abs(worst - AILimitRowWidthBudget.worstValueWidth) < 0.5, "최악 문구 실측 \(worst)")
    }

    /// ★ **가장 넓은 문구가 말줄임 없이 들어간다.**
    ///
    /// 이 줄은 `lineLimit(1)` 이라 넘쳐도 높이가 안 변한다 = 렌더 높이 테스트로는 안 잡히고, 증상은
    /// 숫자 자릿수 오독이다(v0.2.41 의 "Codex 254만" → "Codex 25…" 와 같은 자리).
    @Test
    func theWidestPossibleSummaryFitsWithoutTruncation() {
        #expect(AILimitRowWidthBudget.innerWidth == 268, "본문 열 산식이 바뀌었다")
        let budget = AILimitRowWidthBudget.valueBudget
        #expect(budget > 0)
        #expect(AILimitRowWidthBudget.fits(valueWidth: AILimitRowWidthBudget.worstValueWidth),
                "최악 문구 \(AILimitRowWidthBudget.worstValueWidth)pt 가 예산 \(budget)pt 를 넘는다")
        // 규칙이 낼 수 있는 네 모양 전부를 실제로 재서 넣는다(상수 하나만 재면 다른 모양이 몰래 넘칠 수 있다).
        for text in ["27% · 60%", "0% · 0%", "— · —", "100% · 100%", "100% 이상 · 100% 이상", "99% 이상 · 99% 이상"] {
            let measured = width(text, bold: true, mono: true)
            #expect(AILimitRowWidthBudget.fits(valueWidth: measured),
                    "\"\(text)\" 가 \(measured)pt 로 예산 \(budget)pt 를 넘는다")
        }
        // ★ 기준선이 갈린다: 예산이 무한이 아니라는 것을 보인다(이 단언이 없으면 `fits` 를 `true` 로 고정해도 초록이다).
        #expect(!AILimitRowWidthBudget.fits(valueWidth: budget + 1))
        #expect(!AILimitRowWidthBudget.fits(valueWidth: AILimitRowWidthBudget.innerWidth))
    }

    /// 팝오버 높이 예산은 **산식**이다(뷰가 내용 높이를 고정하므로 상수가 거짓이 될 수 없다).
    @Test
    func popoverHeightBudgetIsDerivedFromTheView() {
        // 산식을 CGFloat 로 **명시해서** 센다(Int 리터럴과 섞으면 `#expect` 전개가 두 타입을 따로 평가한다).
        let derived: CGFloat = AILimitRowWidthBudget.contentHeight
            + AILimitRowWidthBudget.rowInsetY * 2 + AILimitRowWidthBudget.stackSpacing
        #expect(AILimitRowWidthBudget.budgetHeight == derived)
        #expect(CheckMenuView.aiLimitRowHeight == AILimitRowWidthBudget.budgetHeight)
        #expect(CheckMenuView.aiLimitRowHeight == 46)
    }

    /// 창 레이아웃: 제공자 수에 따라 높이가 자라고, 폭은 글 열 최악 + 큰 숫자가 들어가는 값이다.
    @Test
    func windowLayoutFitsTheWidestCardRow() {
        let tile = AILimitWindowLayout.tileSide
        let caption = width("초기화됨 · 확인 못 함")
        let name = width("안티그래비티")
        let big = ("100% 이상" as NSString)
            .size(withAttributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: 22, weight: .bold)]).width
        // v0.3.45: 큰 숫자 **앞에 창 라벨**이 선다(대표 창이 카드마다 다를 수 있어서 — `AILimitCardModel` 머리말).
        // 가장 넓은 라벨로 잰다.
        let label = AILimitWindow.allCases.map { width($0.displayName) }.max() ?? 0
        // 카드 한 줄: 타일 + 간격 10 + 글 열(이름/캡션 중 넓은 쪽) + Spacer 8 + [창 라벨 + 간격 10] + 큰 숫자.
        let needed = tile + 10 + max(caption, name) + 8 + label + 10 + big
        #expect(needed <= AILimitWindowLayout.cardInnerWidth,
                "카드 한 줄에 \(needed)pt 가 필요한데 안쪽 폭이 \(AILimitWindowLayout.cardInnerWidth)pt 다")
        let derivedWidth: CGFloat = AILimitWindowLayout.cardInnerWidth
            + AILimitWindowLayout.cardPadding * 2 + AILimitWindowLayout.contentPadding * 2
        #expect(AILimitWindowLayout.contentWidth == derivedWidth)
        #expect(AILimitWindowLayout.contentWidth == CGFloat(348))
        // 카드가 늘면 창도 커진다(세 장 > 한 장). 같은 답이면 산식이 상수로 굳은 것이다.
        #expect(AILimitWindowLayout.contentHeight(cards: 3) > AILimitWindowLayout.contentHeight(cards: 1))
        #expect(AILimitWindowLayout.defaultContentSize.height == AILimitWindowLayout.contentHeight(cards: 3))
        #expect(AILimitWindowLayout.minContentSize.height == AILimitWindowLayout.contentHeight(cards: 1))
    }

    /// 진행바 채움: 0% 는 0pt, 0 보다 크면 **보이는 폭**을 갖는다(1% 가 0pt 면 "안 썼다"로 보인다).
    @Test
    func barFillIsVisibleForAnyNonZeroUsage() {
        #expect(AILimitBar.fillWidth(total: 200, percent: 0, minimum: 6) == 0)
        #expect(AILimitBar.fillWidth(total: 200, percent: 1, minimum: 6) == 6, "1% 가 안 보인다")
        #expect(AILimitBar.fillWidth(total: 200, percent: 50, minimum: 6) == 100)
        #expect(AILimitBar.fillWidth(total: 200, percent: 100, minimum: 6) == 200)
        #expect(AILimitBar.fillWidth(total: 200, percent: 140, minimum: 6) == 200, "바가 트랙을 뚫었다")
        #expect(AILimitBar.fillWidth(total: 0, percent: 50, minimum: 6) == 0)
        // 단계 색: 제공자 색이 아니라 **사용량** 색이다.
        #expect(AILimitBar.tint(for: nil) == CheckTheme.secondaryText)
        #expect(AILimitBar.tint(for: 10) == CheckTheme.accent)
        #expect(AILimitBar.tint(for: 70) == CheckTheme.pending)
        #expect(AILimitBar.tint(for: 90) == CheckTheme.danger)
    }
}

// MARK: - 창 계약

@Suite("AILimitsMac — 창 계약")
@MainActor
struct AILimitsMacWindowTests {
    /// 창 식별자가 **독립 창 목록**에 있다. 빠지면 미니게임 창을 띄워 둔 사람의 스페이스가 삼켜진다.
    @Test
    func theWindowIsRegisteredAsAStandaloneWindow() {
        #expect(MiniGameSpaceKey.standaloneWindowIDs.contains(CheckAILimitsWindowController.frameAutosaveName))
    }

    /// 창은 **지연 생성**이다 — 리밋을 한 번도 안 보는 실행에서는 창이 안 생긴다.
    /// 그리고 배선 전에는 열리지 않는다(담을 게 없는 창을 만들지 않는다).
    @Test
    func theWindowIsLazyAndNeedsWiring() {
        let controller = CheckAILimitsWindowController(stuckWindowCheckSeconds: 60)
        #expect(controller.hasWindow == false)
        controller.show()
        #expect(controller.hasWindow == false, "배선 없이 창을 만들었다")
        #expect(controller.isOpen == false)
    }

    /// 열기는 **멱등**이고 창은 하나다. 그리고 테스트 실행에서는 알파 0 이라 사용자 화면에 안 뜬다.
    @Test
    func openingTwiceKeepsOneInvisibleWindow() {
        let controller = CheckAILimitsWindowController(stuckWindowCheckSeconds: 60)
        controller.configure(store: AILimitStore.inert(), content: { _ in AnyView(Color.clear) })
        defer { controller.close() }
        controller.show()
        controller.show()
        #expect(controller.hasWindow)
        #expect(controller.isOpen)
        #expect(CheckPanelVisibility.isRunningTests, "전제: 테스트 판정이 참이어야 알파 0 이 걸린다")
        // 자리를 저장한다(안 하면 사용자가 옮겨 둔 창이 가끔 중앙으로 돌아간다).
        #expect(controller.frameAutosaveActive)
        controller.close()
        #expect(controller.isOpen == false)
        #expect(controller.hasWindow, "닫으면서 창을 버렸다 — 다시 열 때 크기·스크롤이 초기화된다")
    }

    /// 창을 열면 `onOpen` 이 불린다(갱신을 당기는 자리 — 컨트롤러가 스토어 주기를 모르게 둔다).
    @Test
    func showCallsOnOpen() {
        let controller = CheckAILimitsWindowController(stuckWindowCheckSeconds: 60)
        controller.configure(store: AILimitStore.inert(), content: { _ in AnyView(Color.clear) })
        defer { controller.close() }
        var calls = 0
        controller.onOpen = { calls += 1 }
        controller.show()
        #expect(calls == 1)
    }

    /// 재생성 상한이 있다(창 서버가 계속 거부하는 극단에서 무한 루프가 되지 않게).
    @Test
    func stuckWindowRebuildsAreCapped() {
        let controller = CheckAILimitsWindowController(stuckWindowCheckSeconds: 60)
        controller.configure(store: AILimitStore.inert(), content: { _ in AnyView(Color.clear) })
        defer { controller.close() }
        controller.show()
        for _ in 0..<(CheckAILimitsWindowController.maxStuckWindowRebuilds + 3) {
            controller.rebuildStuckWindow()
        }
        #expect(controller.stuckWindowRebuilds == CheckAILimitsWindowController.maxStuckWindowRebuilds)
        // 재생성 뒤에도 자리 저장이 **다시 붙는다**(옛 창의 등록을 놓아줬다는 증거).
        #expect(controller.frameAutosaveActive, "재생성 뒤 자리 저장이 죽었다 — 옛 창의 autosave 이름을 안 놓아줬다")
    }

    /// 리셋 시각 캡션은 `오후 6:59` 꼴이다(초 이하를 쓰지 않는다 — 요청 시각의 잔여 분수가 섞여 온다).
    @Test
    func resetTimeCaptionHasNoSeconds() {
        let seoul = TimeZone(identifier: "Asia/Seoul")!
        // 2026-10-06T19:00:00Z = KST 2026-10-07 04:00.
        let text = AILimitResetTimeText.text(
            Date(timeIntervalSince1970: 1_791_313_200), timeZone: seoul
        )
        #expect(text.contains(":"))
        #expect(text.split(separator: ":").count == 2, "\(text) 에 초가 들어 있다")
        #expect(text.hasPrefix("오전") || text.hasPrefix("오후"), "\(text) 가 한국어 꼴이 아니다")
    }
}

// MARK: - 창 본문: 시각이 흐르면 다른 값을 그린다 (v0.3.45 P0)

/// 창 **본문**의 계약. 위 `AILimitsMacWindowTests` 가 창의 수명(지연 생성·멱등 열기·재생성)을 재는 반면
/// 이 스위트는 **그려지는 값**을 잰다 — 그 둘을 한 스위트에 섞어 두었더니 창 테스트 여섯 건이
/// `CheckAILimitsView` 를 **한 번도 만들지 않은 채** 초록이었고, 그 사이 본문의 시각이 얼어 있었다.
@Suite("AILimitsMac — 창 본문: 주입 시계·대표 창·단계 색")
@MainActor
struct AILimitsMacWindowContentTests {
    /// 검증자가 재현한 장면 그대로의 시각들(상대 간격이 전부다).
    private let opened = amNow                                   // 09:00Z — 창을 연다
    private let observed = amNow.addingTimeInterval(17_400)       // 13:50Z — 스토어가 88% 를 받는다
    private let resetsAt = amNow.addingTimeInterval(18_000)       // 14:00Z — 그 5시간 창이 0 으로 돌아간다
    private let viewed = amNow.addingTimeInterval(21_600)         // 15:00Z — 사용자가 **같은 창**을 본다

    /// 시각을 밖에서 미는 상자(뷰가 시계를 **그릴 때마다** 읽는지 재려면 값이 아니라 상자가 필요하다).
    private final class ClockBox: @unchecked Sendable {
        var now: Date
        init(_ now: Date) { self.now = now }
    }

    private func store(_ outcome: AILimitReadOutcome, at: Date,
                       function: String = #function, line: Int = #line) -> AILimitStore {
        let name = CheckTestScratch.uniqueSuitePath(function: function, line: line)
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        let subject = AILimitStore(defaults: defaults, clock: { at }, runner: { _ in AILimitReadOutcome() })
        subject.apply(outcome, now: at)
        return subject
    }

    /// 5시간 88% + 주간 60% 를 `observed` 에 받은 Claude.
    private var claudeAt88: AILimitReadOutcome {
        AILimitReadOutcome(results: [.claude: .success(AILimitProviderSnapshot(
            provider: .claude,
            windows: [
                AILimitWindowSnapshot(window: .fiveHour, usedPercent: 88, resetsAt: resetsAt,
                                      observedAt: observed, source: .local),
                AILimitWindowSnapshot(window: .weekly, usedPercent: 60,
                                      resetsAt: observed.addingTimeInterval(86_400),
                                      observedAt: observed, source: .local)
            ],
            planLabel: "max"
        ))])
    }

    /// ★★ **P0**: 창은 한 번 만들어 캐시되고 닫아도 파괴되지 않는다. 그 창이 **지금** 시각으로 그리는가.
    ///
    /// 재현(검증자 실측): 09:00Z 에 창을 연다 → 13:50Z 에 스토어가 5시간 88% · 리셋 14:00Z 를 받는다 →
    /// 15:00Z 에 같은 창을 본다. 초안은 `var now: Date = Date()` 가 **창을 만든 한 번**에 얼어서
    /// `88% · 방금` 을 그렸다. 맞는 값은 `0% · 초기화됨 · 확인 못 함` 이다 — 리셋이 한 시간 전에 지났는데
    /// 사용자는 "88% 썼다"를 보고 작업을 멈춘다.
    @Test
    func theWindowBodyReadsTheClockOnEveryDraw() throws {
        let subject = store(claudeAt88, at: observed)
        let clock = ClockBox(opened)
        // 창을 만든 시각은 `opened` 다 — 그때 스토어는 아직 아무것도 모른다.
        let view = CheckAILimitsView(store: subject, clock: { clock.now })
        clock.now = opened
        #expect(view.cards.isEmpty == false, "전제: 스토어에 Claude 카드가 있다")

        // ① 방금 받은 값을 보는 순간: 등호로 88%.
        clock.now = observed.addingTimeInterval(30)
        let fresh = try #require(view.cards.first)
        #expect(fresh.headValueText == "88%")
        #expect(fresh.head?.floorOnly == false)
        #expect(view.summaryCaption == "방금")

        // ② 같은 뷰, 시각만 흘렀다(리셋 + 유예를 지났고 그 뒤로 30분 넘게 아무것도 못 봤다).
        clock.now = viewed
        let later = try #require(view.cards.first)
        #expect(later.headValueText == "0%", "리셋이 지난 창을 \(later.headValueText) 로 그린다 — 창의 시각이 얼었다")
        #expect(later.headCaption == "초기화됨 · 확인 못 함")
        #expect(later.head?.percent == 0, "바가 옛 길이로 남았다")
        // 머리글의 나이 캡션도 같이 늙는다(주간 창이 말한다 — 그쪽은 리셋을 주장하지 않는다).
        #expect(view.summaryCaption == "1시간 전")
    }

    /// 시계는 **값이 아니라 클로저**이고 본문은 분마다 다시 그려진다(소스 계약).
    ///
    /// 위 테스트는 "흐르면 다른 값"을 재지만, 창이 **스스로** 다시 그리지 않으면 사용자는 그 다른 값을
    /// 보지 못한다(스토어가 갱신될 때까지 body 가 재평가되지 않는다). 그 틱은 값으로 잴 수 없으므로 소스로 잰다.
    @Test
    func theWindowTicksEveryMinuteAndHoldsNoFrozenDate() throws {
        let code = V0317ShopTests.stripped(try V0317ShopTests.source("CheckAILimitsWindow.swift"))
        #expect(!code.contains("var now: Date = Date()"),
                "기본 인자로 돌아갔다 — 그 한 번의 평가가 창 수명 내내 얼어붙는다(P0)")
        #expect(code.contains("let clock: () -> Date"), "시각을 값으로 받는다 — 팝오버 한 줄과 모양이 갈린다")
        #expect(code.contains("TimelineView(.periodic(from: clock(), by: Self.tickSeconds))"),
                "분 틱이 없다 — 창이 떠 있는 동안 캡션·리셋이 멈춘다")
        #expect(CheckAILimitsView.tickSeconds == 60)
        #expect(CheckAILimitsView.tickSeconds < AILimitFreshnessRule.clockSkewTolerance,
                "틱이 리셋 유예보다 길다 — 리셋이 한 틱 안에 드러나지 않는다")
        #expect(code.contains("CheckAILimitsView(store: store, clock: { Date() })"),
                "기본 배선이 시계를 클로저로 넣지 않는다")
        // 창 파일에서 `Date()` 를 읽는 자리는 **그 기본 배선 한 곳**뿐이다(본문·카드는 전부 주입을 쓴다).
        #expect(code.components(separatedBy: "Date()").count - 1 == 1,
                "창 파일이 `Date()` 를 \(code.components(separatedBy: "Date()").count - 1) 곳에서 읽는다")
    }

    /// ★ 머리 숫자는 **보이는 창**을 따라간다 — `.fiveHour` 를 무조건 머리로 쓰지 않는다.
    ///
    /// 5시간 창이 없는 계정(요금제·그룹 구성에 따라 주간만 온다)에서 초안 카드는 큰 글자에 `—`,
    /// 캡션에 `알 수 없음` 을 그리고 주간 42% 는 얇은 줄로만 남았다. 같은 데이터로 폰은 머리 줄을 안 그리고
    /// 위젯은 주간을 대표로 올린다 — 세 화면이 같은 숫자를 다르게 말한 것이다.
    @Test
    func theHeadNumberFollowsTheVisibleWindow() throws {
        let weeklyOnly = AILimitReadOutcome(results: [.antigravity: .success(AILimitProviderSnapshot(
            provider: .antigravity,
            windows: [AILimitWindowSnapshot(window: .weekly, usedPercent: 42,
                                            resetsAt: amNow.addingTimeInterval(86_400),
                                            observedAt: amNow, source: .local)]
        ))])
        let subject = store(weeklyOnly, at: amNow)
        let card = try #require(AILimitCardModel.all(store: subject, now: amNow).first)
        #expect(card.headValueText == "42%", "주간만 오는 계정의 머리 숫자가 \(card.headValueText) 다")
        #expect(card.headValueText != AILimitFreshnessRule.unknownValueText)
        #expect(card.headWindowLabel == AILimitWindow.weekly.displayName,
                "대표 창이 주간인데 라벨이 \(card.headWindowLabel ?? "없음") 다 — 옆 카드의 5시간과 같은 창으로 읽힌다")
        #expect(card.rest.isEmpty, "같은 값을 카드에 두 번 그린다")
        #expect(card.headCaption != AILimitCardModel.unknownCaption)

        // 기준선: 두 창이 다 있으면 머리는 **5시간**이고 주간은 아래 줄로 내려간다(선택 규칙이 고정이 아니다).
        let both = store(claudeAt88, at: observed)
        let full = try #require(AILimitCardModel.all(store: both, now: observed).first)
        #expect(full.headValueText == "88%")
        #expect(full.headWindowLabel == AILimitWindow.fiveHour.displayName)
        #expect(full.rest.map(\.window) == [.weekly])
        #expect(full.rest.first?.valueText == "60%")
        #expect(full.planLabel == "max")
    }

    /// 창이 하나도 없는 카드(만료만 아는 제공자)는 숫자를 **지어내지 않는다** — `—` · `알 수 없음` + 안내 한 줄.
    @Test
    func aProviderWeCannotReadShowsNoNumber() throws {
        let expired = AILimitReadOutcome(results: [.claude: .failure(AILimitReadError(.expired))])
        let subject = store(expired, at: amNow)
        let card = try #require(AILimitCardModel.all(store: subject, now: amNow).first)
        #expect(card.windows.isEmpty && card.head == nil)
        #expect(card.headValueText == AILimitFreshnessRule.unknownValueText, "0% 를 지어냈다")
        #expect(card.headCaption == AILimitCardModel.unknownCaption)
        #expect(card.headWindowLabel == nil)
        #expect(card.notice == "클로드 코드를 한 번 실행해 주세요")
    }

    /// ★ 단계 색과 숫자가 **같은 눈금**을 쓴다(반올림한 정수).
    ///
    /// 초안은 클램프도 안 된 날것 double 로 90 을 갈랐다 — 89.5% 는 규칙이 `90%` 라고 **적는데** 색은 평온한
    /// 강조색이었다. 한 자리에서 글자와 색이 다른 단계를 말한 셈이다.
    @Test
    func theTintUsesTheSameRoundedScaleAsTheNumber() {
        #expect(AILimitFreshnessRule.wholePercent(89.5) == 90, "전제: 규칙은 89.5 를 90% 로 적는다")
        #expect(AILimitBar.tint(for: 89.5) == CheckTheme.danger, "글자는 90% 인데 색은 경고 단계가 아니다")
        #expect(AILimitFreshnessRule.wholePercent(69.5) == 70, "전제")
        #expect(AILimitBar.tint(for: 69.5) == CheckTheme.pending)
        // 아래쪽 경계도 함께 잰다(둘 중 하나만 재면 `>=` 를 `>` 로 바꿔도 초록이다).
        #expect(AILimitBar.tint(for: 89.4) == CheckTheme.pending)
        #expect(AILimitBar.tint(for: 69.4) == CheckTheme.accent)
        // 전 구간: 글자의 수와 색의 단계가 **언제나** 같은 편이다.
        for step in 0...400 {
            let raw = Double(step) * 0.25
            let whole = AILimitFreshnessRule.wholePercent(raw)
            let expected = whole >= AILimitBar.dangerPercent
                ? CheckTheme.danger
                : (whole >= AILimitBar.warnPercent ? CheckTheme.pending : CheckTheme.accent)
            #expect(AILimitBar.tint(for: raw) == expected, "\(raw) → 글자 \(whole)% 인데 색이 다른 단계다")
        }
        // 범위 밖·비유한값도 규칙을 거친다(바가 트랙을 뚫지 않는 것과 같은 자리).
        #expect(AILimitBar.tint(for: 140) == CheckTheme.danger)
        #expect(AILimitBar.tint(for: .nan) == CheckTheme.accent, "NaN 이 색 단계를 흔든다")
        #expect(AILimitBar.tint(for: nil) == CheckTheme.secondaryText)
    }
}
