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

    /// 조합값은 **창 종류별 최악**을 둘로 합친다(제공자가 셋이어도 숫자는 둘이다 — 카드 제목 툴팁이 그걸 말한다).
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
        let combined = CheckAILimitsCard.combinedWindows(store: subject, now: amNow)
        #expect(combined.map(\.window) == [.fiveHour, .weekly])
        #expect(combined.map(\.valueText) == ["88%", "60%"], "창별 최악이 아니라 평균·첫 제공자를 썼다")
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
    /// 픽스처는 그 혼합이 실제로 생기는 모양이다: Claude 는 두 창 + 플랜, Codex 는 5시간만 + 플랜 없음,
    /// 안티그래비티는 주간만. 합성 `Encodable` 이면 세 행의 키가 전부 다르다.
    @Test
    func everyUploadRowHasTheSameKeySet() throws {
        let rows = [
            AILimitUpsertRow(userId: "u", deviceId: "d", provider: "claude",
                             fiveHourPercent: 27, fiveHourResetsAt: "2026-10-06T19:00:00Z",
                             weeklyPercent: 60, weeklyResetsAt: "2026-10-12T03:00:00Z",
                             planLabel: "max", observedAt: "2026-10-07T00:00:00Z"),
            AILimitUpsertRow(userId: "u", deviceId: "d", provider: "codex",
                             fiveHourPercent: 0, fiveHourResetsAt: nil,
                             weeklyPercent: nil, weeklyResetsAt: nil,
                             planLabel: nil, observedAt: "2026-10-07T00:00:00Z"),
            AILimitUpsertRow(userId: "u", deviceId: "d", provider: "antigravity",
                             fiveHourPercent: nil, fiveHourResetsAt: nil,
                             weeklyPercent: 75, weeklyResetsAt: nil,
                             planLabel: nil, observedAt: "2026-10-07T00:00:00Z")
        ]
        let data = try JSONEncoder().encode(rows)
        let decoded = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        #expect(decoded.count == 3)
        let expected = Set(AILimitUpsertRow.CodingKeys.allCases.map(\.rawValue))
        #expect(expected.count == 9, "컬럼이 \(expected.count) 개다 — 더하거나 뺐으면 이 숫자도 함께 봐라")
        for (index, row) in decoded.enumerated() {
            #expect(Set(row.keys) == expected,
                    "\(index)번 행의 키가 \(Set(row.keys).symmetricDifference(expected)) 만큼 다르다 — PGRST102 로 본문 전체가 거절된다")
        }
        // ★ nil 이 **생략이 아니라 null** 로 나갔는지 확인한다(키가 있다는 것만으로는 부족하다 —
        //   JSONSerialization 은 null 을 NSNull 로 준다).
        #expect(decoded[1]["weekly_percent"] is NSNull, "nil 이 생략됐다 — 합성 Encodable 로 돌아갔다")
        #expect(decoded[2]["five_hour_percent"] is NSNull)
        #expect(decoded[0]["plan_label"] as? String == "max", "플랜 라벨은 **올린다**(폰 카드가 그린다)")
        #expect(decoded[1]["plan_label"] is NSNull)
        // `updated_at` 은 **서버가 쥔다**(터치 트리거). 보내면 버려지지만 키 집합을 흔들 자리를 만들지 않는다.
        #expect(!expected.contains("updated_at"))
        // ★ 계정 지문 칸은 **아예 없다**(v0.3.45 P1 — 공개 처리방침의 "계정 식별자는 올리지 않는다").
        //   null 로 보내는 것과도 다르다: 키가 있으면 다음 사람이 "이미 올리는 칸"으로 읽고 값을 채운다.
        #expect(!expected.contains("account_fingerprint"),
                "업로드 본문에 계정 지문 칸이 돌아왔다 — 공개 처리방침과 어긋난다")
        #expect(decoded.allSatisfy { !$0.keys.contains { $0.contains("fingerprint") } })
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

    /// 계정 지문은 **되돌릴 수 없는 해시**다 — 모양이 아니라 **결과**를 잰다.
    ///
    /// ## 왜 모양으로는 부족한가 (2026-10-07 뮤테이션 실증)
    /// 초안의 단언은 ①`@` 없음 ②길이 16 ③전부 16진수 셋뿐이었다. 그 셋은 `SHA256.hash` 를
    /// **'원문을 hex 로 적기'** 로 바꿔도 전부 통과한다 — 그런데 그 구현은 계정 식별자 **앞 8바이트를 평문으로**
    /// 내놓는다: `someone@example.com` → `736f6d656f6e6540` → 되돌리면 `"someone@"` 이다.
    /// 모양을 재고 결과를 안 잰 테스트의 교과서적인 모양이다(이 저장소가 반복해 겪은 그 구멍).
    ///
    /// 그래서 아래 단언 셋이 **결과**를 못 박는다:
    ///  · 알려진 입력의 SHA-256 앞 16자와 **글자 그대로 같다**(위 변형은 여기서 즉사한다).
    ///  · 지문의 hex 를 바이트로 되돌려도 원문의 앞머리가 **안 나온다**.
    ///  · 앞머리가 같고 꼬리만 다른 두 식별자는 **다른 지문**이다(앞 8바이트만 보는 구현은 여기서도 죽는다).
    @Test
    func accountFingerprintIsNeverRawIdentity() throws {
        let identity = "someone@example.com"
        let fingerprint = try #require(AILimitFingerprint.make(identity))

        // ★ 결과 동치. `printf 'someone@example.com' | shasum -a 256` 의 앞 16자다(2026-10-07 실측).
        #expect(fingerprint == "72497f475e4f76d0",
                "지문이 SHA-256 앞 16자가 아니다(\(fingerprint)) — 해시 말고 다른 변환을 쓰면 원문이 새어 나간다")

        // 원문을 hex 로 적는 변형이 내놓을 값. **지문과 같으면 평문 유출이다.**
        let rawHex = identity.utf8.prefix(AILimitFingerprint.hexLength / 2)
            .map { String(format: "%02x", $0) }.joined()
        #expect(rawHex == "736f6d656f6e6540", "전제: 이 변형이 내놓는 값(= 평문 'someone@')")
        #expect(fingerprint != rawHex, "지문이 원문의 hex 다 — 앞 8바이트가 평문으로 올라간다")

        // 되돌릴 수 없다: hex 를 바이트로 풀어 UTF-8 로 읽어도 원문의 앞머리가 나오지 않는다.
        let bytes = stride(from: 0, to: fingerprint.count, by: 2).compactMap { offset -> UInt8? in
            let start = fingerprint.index(fingerprint.startIndex, offsetBy: offset)
            return UInt8(fingerprint[start..<fingerprint.index(start, offsetBy: 2)], radix: 16)
        }
        #expect(bytes.count == AILimitFingerprint.hexLength / 2)
        let roundTrip = String(decoding: bytes, as: UTF8.self)
        #expect(!identity.hasPrefix(roundTrip), "지문을 되돌리니 원문의 앞머리가 나왔다: \(roundTrip)")

        // 앞머리가 같고 꼬리만 다른 두 식별자 → 다른 지문(앞 8바이트만 보는 구현은 여기서 같아진다).
        #expect(AILimitFingerprint.make(identity) != AILimitFingerprint.make("someone@example.org"))
        // 같은 입력은 같은 지문이다(게이트가 "안 바뀌었다"를 판정할 수 있는 근거).
        #expect(AILimitFingerprint.make(identity) == fingerprint)

        // 모양도 그대로 잰다(서버 CHECK 가 `@` 가 든 값을 23514 로 거부한다 — 그 규약의 클라 쪽 짝).
        #expect(!fingerprint.contains("@"), "이메일이 지문 칸에 그대로 들어갔다")
        #expect(fingerprint.count == AILimitFingerprint.hexLength)
        #expect(fingerprint.allSatisfy { $0.isHexDigit })
        #expect(AILimitFingerprint.make("") == nil)
        #expect(AILimitFingerprint.make("   ") == nil)
    }

    /// ★★ 계정 지문은 **본문에 실리지 않는다** — 그러나 업로드 게이트에서는 계속 쓴다(v0.3.45 P1).
    ///
    /// 공개 처리방침은 "계정 식별자는 올리지 않는다"를 단정한다. 초안은 그 약속과 어긋나게 SHA-256 앞 16자를
    /// 실어 보냈고, 서버에서 그 값을 **소비·표시·비교하는 호출부는 0건**이었다(폰은 일부러 안 받아 온다).
    /// 그래서 네트워크로 가는 쪽만 끊는다 — 게이트(로컬 비교)는 그대로 둬야 "같은 값을 다시 안 올린다"가 산다.
    @Test
    func uploadBodyNeverCarriesTheAccountFingerprintButTheGateStillDoes() async throws {
        let fingerprint = try #require(AILimitFingerprint.make("someone@example.test"))
        let codex = snapshot(.codex, fiveHour: 41, weekly: nil, plan: "plus", fingerprint: fingerprint)
        let service = SupabaseWorkService()   // 네트워크를 쓰지 않는다 — 행만 만든다
        let made = await service.aiLimitRow(userID: "u", deviceID: "d", snapshot: codex)
        let row = try #require(made, "전제: 창이 있으니 행이 만들어진다")
        let json = try #require(String(data: try JSONEncoder().encode([row]), encoding: .utf8))

        #expect(!json.contains(fingerprint), "업로드 본문에 계정 지문이 실렸다: \(json)")
        #expect(!json.lowercased().contains("fingerprint"), "지문 칸이 돌아왔다: \(json)")
        // 전제가 갈려야 이 단언이 뜻을 갖는다: 같은 본문에 플랜 라벨은 **그대로** 실린다(폰 카드가 그린다).
        #expect(json.contains("\"plan_label\":\"plus\""), "플랜 라벨이 빠졌다 — 폰 카드가 빈칸이 된다: \(json)")

        // ★ 게이트 지문에는 **그대로 남아 있다**(그 문자열은 이 맥을 벗어나지 않는다). 지문 생성을 지우는
        //   변형은 여기서 걸린다 — 계정이 바뀌어도 "안 바뀌었다"로 읽혀 업로드가 멈춘다.
        let bundle = AILimitSnapshotBundle(providers: [codex])
        let other = AILimitSnapshotBundle(providers: [
            snapshot(.codex, fiveHour: 41, weekly: nil, plan: "plus",
                     fingerprint: AILimitFingerprint.make("other@example.test"))
        ])
        #expect(AILimitUploadLedger.fingerprint(bundle).contains(fingerprint),
                "게이트가 계정 지문을 더 이상 안 본다 — 계정이 바뀐 주기를 '안 바뀌었다'로 읽는다")
        #expect(AILimitUploadLedger.fingerprint(bundle) != AILimitUploadLedger.fingerprint(other))
    }

    /// ★★ **올리는 칸과 두 공개 문서가 같은 말을 한다.** (v0.3.45 P1)
    ///
    /// ## 왜 이 테스트가 있는가
    /// `docs/privacy.md` 는 공개 URL 로 가입 화면·App Store 에 걸리고, 거기서 "올라가는 것은 … **뿐**입니다"로
    /// **단정**한다. 그런데 초안은 두 칸(`plan_label`·`account_fingerprint`)을 더 실어 보내면서 그 문장을
    /// 고치지 않았다. 내부 문서 `docs/ai-limits.md` §5 는 한 술 더 떠 플랜 이름을 **'안 올라간다'** 칸에 적어
    /// 코드와 정반대를 말했다 — 그 문서가 "올리는 항목이 바뀌면 코드보다 먼저 고친다"를 스스로 규약으로
    /// 적어 둔 당사자인데 **그물이 없었다.** 문서는 아무도 되묻지 않으면 조용히 거짓이 된다.
    ///
    /// ## 어떻게 재는가
    /// 칸 목록은 `AILimitUpsertRow.CodingKeys` **전수**에서 온다(설명이 아니라 실제로 인코딩되는 집합이다).
    /// 칸을 더하거나 빼면 아래 대조표와 **두 문서를 같이 고치지 않는 한** 빨개진다.
    ///
    /// ★ §5 표는 **왼쪽·오른쪽 칸을 갈라서** 읽는다. 한 줄을 통째로 `contains` 하면 '안 올라간다' 쪽에 적힌
    ///   글자가 '올라간다'를 만족시켜 — 바로 이 결함이 — 그대로 산다.
    @Test
    func uploadedColumnsMatchTheTwoPublicDocuments() throws {
        let root = try amRepositoryRoot()
        let privacy = try String(contentsOf: root.appendingPathComponent("docs/privacy.md"), encoding: .utf8)
        let internalDoc = try String(contentsOf: root.appendingPathComponent("docs/ai-limits.md"), encoding: .utf8)

        // 공개 약속의 **그 한 줄**만 본다 — 문서 어딘가에 글자가 있다는 것으로는 '약속했다'가 아니다.
        let promise = try #require(
            privacy.split(separator: "\n", omittingEmptySubsequences: false)
                .first { $0.contains("**어디로 가는가**") }.map(String.init),
            "처리방침에서 '어디로 가는가' 줄이 사라졌다 — 공개 약속의 정본이다"
        )
        let (uploaded, withheld) = try amUploadSectionColumns(internalDoc)

        // 칸 → 두 문서에서 되물을 글자. **CodingKeys 전수**와 아래 `routing` 의 합집합이어야 한다.
        let documented: [AILimitUpsertRow.CodingKeys: (promise: String, table: String)] = [
            .provider: ("제공자 이름", "제공자 구분"),
            .fiveHourPercent: ("사용률 퍼센트", "사용률 퍼센트"),
            .weeklyPercent: ("창 종류(5시간/주간)", "창 종류(5시간 / 주간)"),
            .fiveHourResetsAt: ("리셋 시각", "리셋 시각"),
            .weeklyResetsAt: ("리셋 시각", "리셋 시각"),
            .planLabel: ("요금제 이름", "플랜 라벨"),
            .observedAt: ("읽은 시각", "관측(읽은) 시각")
        ]
        // 우리 쪽 **라우팅 키**다(제공자에서 읽은 값이 아니다). `user_id` 는 RLS 의 주인이고 `device_id` 는
        // 어느 맥이 올렸는지다 — 처리방침은 그 둘을 '기기 식별자'·'본인만'으로 따로 적는다.
        let routing: Set<AILimitUpsertRow.CodingKeys> = [.userId, .deviceId]
        #expect(Set(AILimitUpsertRow.CodingKeys.allCases) == Set(documented.keys).union(routing),
                "업로드 칸이 바뀌었는데 이 대조표가 그대로다 — 칸을 더하거나 뺐으면 두 문서를 먼저 고쳐라")

        for (key, text) in documented {
            #expect(promise.contains(text.promise),
                    "'\(key.rawValue)' 를 올리는데 공개 처리방침의 열거에 없다(찾은 글자: \(text.promise))")
            #expect(uploaded.contains(text.table),
                    "'\(key.rawValue)' 를 올리는데 ai-limits.md §5 '올라간다' 칸에 없다(찾은 글자: \(text.table))")
            #expect(!withheld.contains(text.table),
                    "'\(key.rawValue)' 가 §5 '안 올라간다' 칸에 적혀 있다 — 코드와 정반대다")
        }
        // 라우팅 키도 **본문에 실린다**. "…뿐입니다"로 끝나는 문장이라 그 사실을 같은 줄에 적어 둬야 한다.
        #expect(promise.contains("기기 식별자"),
                "행에 device_id 가 실리는데 공개 열거가 그 말을 안 한다 — '뿐입니다'가 거짓이 된다")
        #expect(!withheld.contains("플랜"),
                "§5 '안 올라간다' 칸이 플랜 라벨을 말한다 — 코드는 올린다(폰 '나' 탭 카드가 그 이름을 그린다)")

        // ★ 계정 지문: **칸이 없고**, 두 문서가 그렇게 적는다.
        #expect(!AILimitUpsertRow.CodingKeys.allCases.contains { $0.rawValue.contains("fingerprint") },
                "업로드 본문에 계정 지문 칸이 돌아왔다 — 처리방침은 '계정 식별자는 올리지 않는다'고 단정한다")
        #expect(promise.contains("계정 식별자는 올리지 않"), "공개 약속의 그 문장이 사라졌다")
        #expect(withheld.contains("계정 지문"), "§5 가 계정 지문을 '안 올라간다' 칸에 적지 않았다")
        #expect(!uploaded.contains("지문"), "§5 '올라간다' 칸이 지문을 말한다 — 코드는 안 올린다")
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

// MARK: - 팝오버 카드 폭·높이 (실측)

@Suite("AILimitsMac — 팝오버 카드 폭·높이 예산")
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

    /// 실측 상수가 **실제 글리프 폭과 같다**(0.5pt 안). 글꼴·문구가 바뀌면 여기서 먼저 빨개진다.
    @Test
    func measuredConstantsMatchTheRealGlyphWidths() {
        // 숫자 칸의 최악 문구 = "100% 이상"(bold monospacedDigit 10pt).
        let worst = width("100% 이상", bold: true, mono: true)
        #expect(abs(worst - AILimitRowWidthBudget.worstValueWidth) < 0.5, "최악 문구 실측 \(worst)")
        // ★ 기준선이 갈린다: 그 문구가 **다른 네 모양보다 넓다**. 같은 답이면 "최악"을 잘못 고른 것이고,
        //   아래 `fits` 대조는 더 넓은 모양을 통과시킨다.
        for narrower in ["100%", "99% 이상", "0%", AILimitFreshnessRule.unknownValueText,
                         AILimitCardModel.absentValueText] {
            #expect(width(narrower, bold: true, mono: true) < worst, "\"\(narrower)\" 가 최악보다 넓다")
        }
    }

    /// ★ **가장 넓은 숫자 문구가 고정 칸 안에 말줄임 없이 들어간다.**
    ///
    /// 이 칸은 `lineLimit(1)` + 고정 폭이라 넘쳐도 높이가 안 변한다 = 렌더 높이 테스트로는 안 잡히고,
    /// 증상은 숫자 자릿수 오독이다(v0.2.41 의 "Codex 254만" → "Codex 25…" 와 같은 자리).
    @Test
    func theWidestValueFitsItsFixedCellWithoutTruncation() {
        #expect(AILimitRowWidthBudget.innerWidth == 292, "카드 안쪽 폭 산식이 바뀌었다")
        #expect(AILimitRowWidthBudget.cardOuterWidth == CheckMenuView.contentColumnWidth,
                "카드가 팝오버 본문 열과 다른 폭을 전제한다")
        // 규칙이 낼 수 있는 모양 **전부** + 이 카드가 더한 `없음` 을 실제로 재서 넣는다
        // (상수 하나만 재면 다른 모양이 몰래 넘칠 수 있다).
        for text in ["100% 이상", "100%", "99% 이상", "27% 이상", "27%", "0%",
                     AILimitFreshnessRule.unknownValueText, AILimitCardModel.absentValueText] {
            let measured = width(text, bold: true, mono: true)
            #expect(AILimitRowWidthBudget.fits(valueWidth: measured),
                    "\"\(text)\" 가 \(measured)pt 로 칸 \(AILimitRowWidthBudget.valueWidth)pt 를 넘는다")
        }
        // ★ 기준선이 갈린다: 칸이 무한이 아니다(이 단언이 없으면 `fits` 를 `true` 로 고정해도 초록이다).
        #expect(!AILimitRowWidthBudget.fits(valueWidth: AILimitRowWidthBudget.valueWidth + 1))
        #expect(!AILimitRowWidthBudget.fits(valueWidth: AILimitRowWidthBudget.innerWidth))
        // 그리고 칸에 **여유가 과하지 않다** — 최악 문구가 칸의 8할은 쓴다(아니면 바에게 줄 폭을 묶어 둔 것이다).
        #expect(AILimitRowWidthBudget.worstValueWidth > AILimitRowWidthBudget.valueWidth * 0.8,
                "숫자 칸 \(AILimitRowWidthBudget.valueWidth)pt 가 최악 문구 \(AILimitRowWidthBudget.worstValueWidth)pt 보다 너무 넓다")
    }

    /// ★ 한 줄의 가로 합이 **정확히** 카드 안쪽 폭이고, 열 머리가 자기 열 숫자 칸에 **자리로** 맞는다.
    ///
    /// 자리는 짝을 알려 주는 세 단서 가운데 하나다(열 머리 글자 · 색 · 좌우 자리). 머리 글자가 다른 열의
    /// 숫자 위에 서면 그 단서가 **거짓말**이 되고, 틴트 모드처럼 색이 사라지는 표면에서는 남는 단서가 둘뿐이다.
    @Test
    func theRowAddsUpToTheCardInnerWidthAndHeadersSitOverTheirOwnColumn() {
        let b = AILimitRowWidthBudget.self
        // ① 한 줄: 마크 | 간격 | 바 | 간격 | 숫자 | 열 간격 | 바 | 간격 | 숫자 = 안쪽 폭.
        let row = b.markSide + b.markGap
            + b.barWidth + b.barValueGap + b.valueWidth
            + b.columnGap
            + b.barWidth + b.barValueGap + b.valueWidth
        #expect(abs(row - b.innerWidth) < 0.01, "한 줄이 \(row)pt 로 안쪽 폭 \(b.innerWidth)pt 와 다르다")
        // ② 바가 실제로 보일 만큼 남았다(이름 글자를 넣었을 때의 ~60pt 보다 넓다 — 그게 이름을 뺀 이유다).
        #expect(b.barWidth == 69, "바 폭이 \(b.barWidth)pt 다")
        #expect(b.barWidth > 60, "바가 \(b.barWidth)pt 로 줄었다 — 8% 와 0% 가 눈으로 안 갈린다")
        // ③ 열 머리의 오른쪽 끝 = 그 열 숫자 칸의 오른쪽 끝.
        //    머리 줄 = [제목 flexible][5시간 칸 52][headerCellGap][주간 칸 52]
        //    제공자 줄 = [마크 20][8][바 69][6][숫자 52][10][바 69][6][숫자 52]
        let headerFixed = b.valueWidth + b.headerCellGap + b.valueWidth
        let titleRegion = b.innerWidth - headerFixed
        let fiveHourValueStart = b.markSide + b.markGap + b.barWidth + b.barValueGap
        #expect(abs(titleRegion - fiveHourValueStart) < 0.01,
                "5시간 열 머리가 \(titleRegion)pt 에서 시작하는데 숫자 칸은 \(fiveHourValueStart)pt 다 — 머리가 다른 열을 가리킨다")
        #expect(b.headerCellGap == b.barWidth + b.barValueGap + b.columnGap)
        // ④ 제목("⏲ AI 리밋")이 그 자리에 든다 — 안 들면 말줄임이 나고, 카드가 무엇의 카드인지 사라진다.
        #expect(width("AI 리밋") + 11 + 4 < titleRegion,
                "제목이 \(titleRegion)pt 에 안 든다")
    }

    /// 카드 높이는 **제공자 수의 산식**이다(뷰가 `.frame(height:)` 로 못 박으므로 거짓이 될 수 없다).
    /// 0 · 1 · 2 · 3 을 다 센다 — 0 은 카드를 안 그리는 자리라 간격까지 0 이어야 한다.
    @Test
    func cardHeightFollowsTheProviderCountZeroThroughThree() {
        let b = AILimitRowWidthBudget.self
        #expect(b.cardHeight(providers: 0) == 0, "제공자가 없는데 카드 높이를 잡았다")
        #expect(b.budgetHeight(providers: 0) == 0, "안 그리는 카드가 VStack 간격을 먹는다")
        for count in 1...3 {
            let derived: CGFloat = b.rowInsetY * 2 + b.titleRowHeight + b.titleRowGap
                + CGFloat(count) * b.providerRowHeight + CGFloat(count - 1) * b.separatorHeight
            #expect(b.cardHeight(providers: count) == derived, "제공자 \(count)명")
            #expect(b.budgetHeight(providers: count) == derived + b.stackSpacing)
            #expect(CheckMenuView.aiLimitCardHeight(providers: count) == b.budgetHeight(providers: count))
        }
        // 실측 값으로도 못 박는다(산식만 재면 양쪽을 같이 고치는 변경이 조용히 지나간다).
        #expect(b.cardHeight(providers: 1) == 65)
        #expect(b.cardHeight(providers: 2) == 90)
        #expect(b.cardHeight(providers: 3) == 115)
        #expect(CheckMenuView.aiLimitCardHeight(providers: 3) == 125)
        // 제공자가 늘면 카드도 **자란다**(같은 답이면 산식이 상수로 굳은 것이다).
        #expect(b.cardHeight(providers: 3) > b.cardHeight(providers: 1))
        // 그래도 팝오버 상한(700pt)에 비해 작다 — "세로로 길어지더라도 너무 길어지진 않게"(사용자 지시).
        #expect(b.budgetHeight(providers: 3) < 160,
                "제공자 셋 카드가 \(b.budgetHeight(providers: 3))pt 다 — 목록 행을 너무 많이 밀어낸다")
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
        // 실제 바 폭에서도 같다(69pt 트랙에서 1% 는 0.69pt → 바 높이 6pt 로 올라선다).
        let real = AILimitBar.fillWidth(total: AILimitRowWidthBudget.barWidth, percent: 1,
                                       minimum: AILimitRowWidthBudget.barHeight)
        #expect(real == AILimitRowWidthBudget.barHeight, "실제 바에서 1% 가 \(real)pt 다")
        #expect(AILimitBar.fillWidth(total: AILimitRowWidthBudget.barWidth, percent: 0,
                                     minimum: AILimitRowWidthBudget.barHeight) == 0,
                "0% 가 1% 와 같은 폭이다 — 두 숫자가 눈으로 안 갈린다")
    }

    /// ★ 승인된 디자인의 16진수가 **그대로** 들어 있다(사람이 0…1 실수로 옮겨 적는 걸음에서 틀리지 않게).
    @Test
    func thePaletteCarriesTheApprovedHexValues() throws {
        func bytes(_ color: Color) throws -> (Int, Int, Int) {
            let ns = try #require(NSColor(color).usingColorSpace(.sRGB))
            return (Int((ns.redComponent * 255).rounded()),
                    Int((ns.greenComponent * 255).rounded()),
                    Int((ns.blueComponent * 255).rounded()))
        }
        #expect(try bytes(AILimitMacPalette.fiveHourBar) == (0x5B, 0x8D, 0xEF))
        #expect(try bytes(AILimitMacPalette.fiveHourHeader) == (0x7F, 0xA8, 0xF5))
        #expect(try bytes(AILimitMacPalette.weeklyBar) == (0x8A, 0x76, 0xE0))
        #expect(try bytes(AILimitMacPalette.weeklyHeader) == (0xA7, 0x96, 0xE8))
        #expect(try bytes(AILimitMacPalette.emptyTrack) == (0x30, 0x34, 0x3B))
        #expect(try bytes(AILimitMacPalette.separator) == (0x2C, 0x30, 0x37))
        #expect(try bytes(AILimitMacPalette.absentText) == (0x59, 0x5E, 0x67))
        #expect(try bytes(AILimitMacPalette.absentTrack) == (0x22, 0x26, 0x2C))
        // 열마다 **다른** 색이고, 머리 글자는 바보다 밝다(작은 글자가 바와 같은 명도면 배경에 묻힌다).
        #expect(AILimitMacPalette.barColor(.fiveHour) != AILimitMacPalette.barColor(.weekly),
                "두 열의 바가 같은 색이다 — 색 단서가 없다")
        #expect(AILimitMacPalette.headerColor(.fiveHour) != AILimitMacPalette.headerColor(.weekly))
        for window in AILimitWindow.allCases {
            let bar = try bytes(AILimitMacPalette.barColor(window))
            let head = try bytes(AILimitMacPalette.headerColor(window))
            #expect(head.0 + head.1 + head.2 > bar.0 + bar.1 + bar.2,
                    "\(window) 열 머리가 바보다 어둡다")
        }
        // 없는 칸의 트랙은 빈 트랙보다 **어둡다** — 같은 밝기면 "0% 라 비었다"로 읽힌다.
        let absent = try bytes(AILimitMacPalette.absentTrack)
        let empty = try bytes(AILimitMacPalette.emptyTrack)
        #expect(absent.0 + absent.1 + absent.2 < empty.0 + empty.1 + empty.2)
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

// MARK: - 카드 본문: 두 열이 나란히 · 시각이 흐르면 다른 값 (v0.3.46)

/// 카드 **본문**의 계약. 위 `AILimitsMacWidthTests` 가 자리(폭·높이)를 재는 반면 이 스위트는
/// **그려지는 값과 글자**를 잰다 — 그 둘을 한 스위트에 섞어 두었더니 v0.3.45 의 창 테스트 여섯 건이
/// `CheckAILimitsView` 를 **한 번도 만들지 않은 채** 초록이었고, 그 사이 본문의 시각이 얼어 있었다.
@Suite("AILimitsMac — 카드 본문: 두 열·주입 시계·없음 vs 판정 불가")
@MainActor
struct AILimitsMacCardContentTests {
    /// 검증자가 재현한 장면 그대로의 시각들(상대 간격이 전부다).
    private let opened = amNow                                   // 09:00Z — 팝오버를 연다
    private let observed = amNow.addingTimeInterval(17_400)       // 13:50Z — 스토어가 88% 를 받는다
    private let resetsAt = amNow.addingTimeInterval(18_000)       // 14:00Z — 그 5시간 창이 0 으로 돌아간다
    private let viewed = amNow.addingTimeInterval(21_600)         // 15:00Z — 사용자가 **같은 카드**를 본다

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

    /// ★★ **P0 의 그물**: 카드는 **그릴 때마다** 시계를 읽는다.
    ///
    /// v0.3.45 의 별도 창은 `var now: Date = Date()` 를 들고 있었다. 기본 인자는 **딱 한 번** 평가되고
    /// 창은 캐시돼 닫아도 파괴되지 않으므로 그 `now` 가 앱 수명 내내 얼어붙었다.
    /// 재현: 09:00Z 에 연다 → 13:50Z 에 5시간 88% · 리셋 14:00Z 를 받는다 → 15:00Z 에 같은 자리를 본다.
    /// 얼어붙은 쪽은 `88% · 방금` 을 그렸다. 맞는 값은 `0% · 초기화됨 · 확인 못 함` 이다 — 리셋이 한 시간
    /// 전에 지났는데 사용자는 "88% 썼다"를 보고 작업을 멈춘다.
    ///
    /// 창이 사라져도 함정은 남는다(카드가 `Date` 를 저장하면 똑같다). 그래서 ① 값으로 되묻고
    /// ② 소스로 "저장된 `Date` 가 없다"를 못 박는다.
    @Test
    func theCardReadsTheClockOnEveryDraw() throws {
        let subject = store(claudeAt88, at: observed)
        #expect(AILimitCardModel.all(store: subject, now: opened).isEmpty == false, "전제: Claude 줄이 있다")

        // ① 방금 받은 값을 보는 순간: 등호로 88%.
        let fresh = try #require(AILimitCardModel.all(store: subject, now: observed.addingTimeInterval(30)).first)
        #expect(fresh.display(.fiveHour)?.valueText == "88%")
        #expect(fresh.display(.fiveHour)?.floorOnly == false)

        // ② 같은 데이터, 시각만 흘렀다(리셋 + 유예를 지났고 그 뒤로 30분 넘게 아무것도 못 봤다).
        let later = try #require(AILimitCardModel.all(store: subject, now: viewed).first)
        let head = try #require(later.display(.fiveHour))
        #expect(head.valueText == "0%", "리셋이 지난 창을 \(head.valueText) 로 그린다 — 카드의 시각이 얼었다")
        #expect(head.captionText == "초기화됨 · 확인 못 함")
        #expect(head.percent == 0, "바가 옛 길이로 남았다")

        // ③ 소스 계약: 뷰가 시각을 **클로저로 받아 body 에서 읽고**, `Date()` 를 스스로 부르지 않는다.
        let code = V0317ShopTests.stripped(try V0317ShopTests.source("CheckAILimitsRow.swift"))
        #expect(code.contains("let clock: () -> Date"), "시각을 값으로 받는다")
        #expect(!code.contains("var now: Date = Date()"),
                "기본 인자로 돌아갔다 — 그 한 번의 평가가 얼어붙는다(v0.3.45 P0)")
        #expect(code.contains("let now = clock()"), "body 가 시계를 읽지 않는다")
        #expect(code.contains("AILimitCardModel.all(store: store, now: now)"),
                "뷰가 그 시각으로 줄을 만들지 않는다")
        let dateCalls = code.components(separatedBy: "Date()").count - 1
        #expect(dateCalls == 0, "카드 파일이 `Date()` 를 \(dateCalls) 곳에서 읽는다 — 시각은 주입만이다")
    }

    /// ★ 창마다 **자기 칸**이 있다 — 대표 창을 고르지 않는다(v0.3.46 이 그 선택을 없앴다).
    ///
    /// v0.3.45 는 머리 숫자 하나를 크게 쓰느라 "어느 창을 머리로 세우나"를 골라야 했고, 초안이 `.fiveHour` 를
    /// 무조건 세워 5시간 창이 **없는** 계정에서 큰 글자가 `—` 가 되고 주간 42% 는 얇은 줄로만 남았다.
    /// 두 열을 나란히 세우면 그 선택이 아예 없다.
    @Test
    func everyWindowGetsItsOwnCell() throws {
        let weeklyOnly = AILimitReadOutcome(results: [.antigravity: .success(AILimitProviderSnapshot(
            provider: .antigravity,
            windows: [AILimitWindowSnapshot(window: .weekly, usedPercent: 42,
                                            resetsAt: amNow.addingTimeInterval(86_400),
                                            observedAt: amNow, source: .local)]
        ))])
        let one = try #require(AILimitCardModel.all(store: store(weeklyOnly, at: amNow), now: amNow).first)
        #expect(one.display(.weekly)?.valueText == "42%", "주간만 오는 계정의 주간 칸이 비었다")
        #expect(one.isAbsent(.fiveHour), "없는 5시간 창에 값을 지어냈다")
        #expect(one.saysNothingButNotice == false, "읽은 창이 있는데 줄이 안내로 바뀌었다")

        // 기준선: 두 창이 다 있으면 **두 칸이 다 찬다**(위 단언이 "언제나 비어 있다"를 재는 게 아니다).
        let both = try #require(AILimitCardModel.all(store: store(claudeAt88, at: observed), now: observed).first)
        #expect(both.display(.fiveHour)?.valueText == "88%")
        #expect(both.display(.weekly)?.valueText == "60%")
        #expect(!both.isAbsent(.fiveHour) && !both.isAbsent(.weekly))
        #expect(both.planLabel == "max")
        #expect(both.windows.map(\.window) == [.fiveHour, .weekly], "열 순서가 5시간 → 주간이 아니다")
    }

    /// ★ **`없음` 과 `—` 는 다른 말이다**(승인된 문법 ⑤).
    ///
    /// `—` 는 규칙이 "판정 불가(= 못 읽었다)"로 못 박은 글자다. 5시간 창이 **아예 없는** 계정에 그 글자를
    /// 쓰면 "이 계정엔 그 창이 없다"를 읽기 실패로 말하는 셈이고, 사용자는 고장으로 읽는다.
    /// 반대로 창은 있는데 판정이 불가한 경우(맥 시계가 세 시간 빠르다)는 `—` 가 **맞는 말**이다.
    @Test
    func anAbsentWindowIsNeverCalledUnreadable() throws {
        #expect(AILimitCardModel.absentValueText == "없음")
        #expect(AILimitCardModel.absentValueText != AILimitFreshnessRule.unknownValueText,
                "두 사실을 같은 글자로 말한다")

        // ① 그 창이 없다 → `없음`(화면도 툴팁도).
        let weeklyOnly = AILimitReadOutcome(results: [.antigravity: .success(AILimitProviderSnapshot(
            provider: .antigravity,
            windows: [AILimitWindowSnapshot(window: .weekly, usedPercent: 42,
                                            resetsAt: amNow.addingTimeInterval(86_400),
                                            observedAt: amNow, source: .local)]
        ))])
        let absent = try #require(AILimitCardModel.all(store: store(weeklyOnly, at: amNow), now: amNow).first)
        #expect(absent.display(.fiveHour) == nil)
        #expect(absent.tooltipText.contains("5시간 없음"), "툴팁: \(absent.tooltipText)")
        #expect(!absent.tooltipText.contains(AILimitFreshnessRule.unknownValueText),
                "없는 창을 '읽기 실패'로 말한다: \(absent.tooltipText)")

        // ② 창은 **있는데** 판정이 불가하다(관측 시각이 유예를 넘겨 미래) → 두 칸이 `—` 다.
        let skewed = AILimitReadOutcome(results: [.claude: .success(AILimitProviderSnapshot(
            provider: .claude,
            windows: [
                AILimitWindowSnapshot(window: .fiveHour, usedPercent: 27, resetsAt: nil,
                                      observedAt: amNow.addingTimeInterval(10_800), source: .local),
                AILimitWindowSnapshot(window: .weekly, usedPercent: 60, resetsAt: nil,
                                      observedAt: amNow.addingTimeInterval(10_800), source: .local)
            ]
        ))])
        let unknown = try #require(AILimitCardModel.all(store: store(skewed, at: amNow), now: amNow).first)
        #expect(unknown.display(.fiveHour)?.valueText == AILimitFreshnessRule.unknownValueText)
        #expect(unknown.display(.weekly)?.valueText == AILimitFreshnessRule.unknownValueText)
        #expect(!unknown.isAbsent(.fiveHour), "읽기 실패를 '창이 없다'로 접었다")
        #expect(unknown.display(.fiveHour)?.percent == nil, "판정 불가인데 바를 채웠다")

        // ③ 카드 제목 툴팁(창 종류별 최악)도 같은 규약이다 — 없는 창을 `—` 로 말하지 않는다.
        let weeklyStore = store(weeklyOnly, at: amNow)
        let combined = CheckAILimitsCard.combinedWindows(store: weeklyStore, now: amNow)
        #expect(combined.map(\.window) == [.weekly], "없는 창을 조합값이 세웠다")
        let summary = CheckAILimitsCard.summaryTooltip(
            windows: combined, caption: weeklyStore.summary(now: amNow).captionText
        )
        #expect(summary.hasPrefix("주간 42%"), "조합 툴팁에 창 라벨이 없다(5시간으로 읽힌다): \(summary)")
        #expect(!summary.contains(AILimitFreshnessRule.unknownValueText), "조합 툴팁: \(summary)")
        // ★ 기준선: 두 창이 다 있으면 둘을 라벨과 함께 적는다.
        let bothStore = store(claudeAt88, at: observed)
        let bothSummary = CheckAILimitsCard.summaryTooltip(
            windows: CheckAILimitsCard.combinedWindows(store: bothStore, now: observed),
            caption: bothStore.summary(now: observed).captionText
        )
        #expect(bothSummary == "5시간 88% · 주간 60%\n방금", "조합 툴팁: \(bothSummary)")
    }

    /// 읽은 창이 하나도 없는 제공자(만료만 아는)는 숫자를 **지어내지 않고** 할 일을 한 줄로 말한다.
    ///
    /// 그 줄을 `없음 없음` 으로 그리면 "이 계정엔 두 창이 없다"는 거짓이 된다 — 사실은 "지금 못 읽었다"다.
    @Test
    func aProviderWeCannotReadSaysWhatToDoInsteadOfInventingNumbers() throws {
        let expired = AILimitReadOutcome(results: [.claude: .failure(AILimitReadError(.expired))])
        let subject = store(expired, at: amNow)
        #expect(subject.isAvailable, "전제: 만료만 아는 제공자도 카드에 선다")
        let card = try #require(AILimitCardModel.all(store: subject, now: amNow).first)
        #expect(card.windows.isEmpty)
        #expect(card.notice == "클로드 코드를 한 번 실행해 주세요")
        #expect(card.saysNothingButNotice, "두 칸을 '없음' 으로 비웠다 — 창이 없는 것과 못 읽은 것은 다르다")
        // ★ '없음' 글자 자체로 재지 마라 — 규칙의 '판정 불가' 캡션이 **"알 수 없음"** 이라 그 안에 들어 있다
        //   (2026-10-07 이 테스트가 처음 빨개진 자리). 재야 하는 것은 **창 라벨이 붙은 칸 문구**다.
        for window in AILimitWindow.allCases {
            #expect(!card.tooltipText.contains("\(window.displayName) \(AILimitCardModel.absentValueText)"),
                    "툴팁이 못 읽은 \(window.displayName) 창을 '없음' 이라 말한다: \(card.tooltipText)")
        }
        #expect(card.tooltipText.contains(AILimitCardModel.unknownCaption))
        #expect(card.tooltipText.contains("클로드 코드를 한 번 실행해 주세요"))
        // ★ 기준선: 값이 있는 제공자는 안내 줄로 바뀌지 않는다.
        let healthy = try #require(AILimitCardModel.all(store: store(claudeAt88, at: observed), now: observed).first)
        #expect(healthy.saysNothingButNotice == false)
        // 그리고 안내 문구는 안쪽 폭 안에 든다(말줄임이 나면 할 일이 안 읽힌다).
        let room = AILimitRowWidthBudget.innerWidth - AILimitRowWidthBudget.markSide - AILimitRowWidthBudget.markGap
        for notice in ["클로드 코드를 한 번 실행해 주세요", "코덱스를 한 번 실행해 주세요",
                       "안티그래비티를 한 번 실행해 주세요", "구독 리밋 없음", "잠시 뒤 다시"] {
            let measured = (notice as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 10)]).width
            #expect(measured <= room, "\"\(notice)\" 가 \(measured)pt 로 \(room)pt 를 넘는다")
        }
    }

    /// ★ 사용량 단계 색과 숫자가 **같은 눈금**을 쓴다(반올림한 정수).
    ///
    /// v0.3.45 초안은 클램프도 안 된 날것 double 로 90 을 갈랐다 — 89.5% 는 규칙이 `90%` 라고 **적는데**
    /// 색은 평온했다. 한 자리에서 글자와 색이 다른 단계를 말한 셈이다.
    ///
    /// v0.3.46 에서 그 색은 **바가 아니라 숫자 글자**가 쥔다(바는 열을 가른다). 평온 단계가 강조색이 아니라
    /// 본문색인 이유가 그것이다 — 파란 글자는 5시간 열 색과 겹쳐 읽힌다.
    @Test
    func theUsageTintUsesTheSameRoundedScaleAsTheNumber() {
        #expect(AILimitFreshnessRule.wholePercent(89.5) == 90, "전제: 규칙은 89.5 를 90% 로 적는다")
        #expect(AILimitUsageTint.color(for: 89.5) == CheckTheme.danger, "글자는 90% 인데 색은 경고 단계가 아니다")
        #expect(AILimitFreshnessRule.wholePercent(69.5) == 70, "전제")
        #expect(AILimitUsageTint.color(for: 69.5) == CheckTheme.pending)
        // 아래쪽 경계도 함께 잰다(둘 중 하나만 재면 `>=` 를 `>` 로 바꿔도 초록이다).
        #expect(AILimitUsageTint.color(for: 89.4) == CheckTheme.pending)
        #expect(AILimitUsageTint.color(for: 69.4) == CheckTheme.primaryText)
        // 전 구간: 글자의 수와 색의 단계가 **언제나** 같은 편이다.
        for step in 0...400 {
            let raw = Double(step) * 0.25
            let whole = AILimitFreshnessRule.wholePercent(raw)
            let expected = whole >= AILimitUsageTint.dangerPercent
                ? CheckTheme.danger
                : (whole >= AILimitUsageTint.warnPercent ? CheckTheme.pending : CheckTheme.primaryText)
            #expect(AILimitUsageTint.color(for: raw) == expected, "\(raw) → 글자 \(whole)% 인데 색이 다른 단계다")
        }
        // 범위 밖·비유한값도 규칙을 거친다(바가 트랙을 뚫지 않는 것과 같은 자리).
        #expect(AILimitUsageTint.color(for: 140) == CheckTheme.danger)
        #expect(AILimitUsageTint.color(for: .nan) == CheckTheme.primaryText, "NaN 이 색 단계를 흔든다")
        #expect(AILimitUsageTint.color(for: nil) == CheckTheme.secondaryText)
        // ★ 평온 단계가 **열 색과 겹치지 않는다** — 겹치면 "파란 글자"가 두 뜻을 갖는다.
        #expect(AILimitUsageTint.color(for: 10) != AILimitMacPalette.fiveHourBar)
        #expect(AILimitUsageTint.color(for: 10) != AILimitMacPalette.weeklyBar)
    }

    /// ★ 툴팁이 **이름·요금제·관측 나이·리셋 시각**을 갚는다(v0.3.46 의 핵심 교환).
    ///
    /// 카드에 이름 글자가 없는 것은 바 폭을 사기 위한 교환이다. 그 값을 안 치르면 사용자는 어느 줄이
    /// 누구인지(마크만으로), 그 숫자가 얼마나 묵었는지를 **아예** 알 수 없다. 숫자의 "이상"과 바의 투명도는
    /// "30분을 넘었다"까지만 알리고 3시간인지 3일인지는 말하지 못한다(`AILimitFreshnessRule` 머리말 ⓑ).
    ///
    /// 덤으로: 리셋이 **유예(120초) 안쪽에서 이미 지난** 동안 값은 아직 90% 가 맞는데 캡션은 `오후 2:04 리셋`
    /// 이라고 **지난 시각을 미래처럼** 말했다(2026-10-07 실측 — 지금이 2:05).
    @Test
    func theTooltipRepaysTheNameAndPlanAndAgeAndReset() throws {
        // ① 나이 + 리셋 시각이 **둘 다** 선다.
        let aged = AILimitReadOutcome(results: [.claude: .success(AILimitProviderSnapshot(
            provider: .claude,
            windows: [AILimitWindowSnapshot(window: .fiveHour, usedPercent: 27,
                                            resetsAt: amNow.addingTimeInterval(3_600),
                                            observedAt: amNow.addingTimeInterval(-10_800), source: .local)],
            planLabel: "max"
        ))])
        let card = try #require(AILimitCardModel.all(store: store(aged, at: amNow), now: amNow).first)
        #expect(card.display(.fiveHour)?.valueText == "27% 이상", "전제: 그 숫자는 하한이다")
        let reset = try #require(card.resetTexts[.fiveHour], "리셋 시각을 통째로 버렸다")
        #expect(reset == "\(AILimitResetTimeText.text(amNow.addingTimeInterval(3_600))) 리셋")
        let lines = card.tooltipText.split(separator: "\n").map(String.init)
        #expect(lines.first == "Claude max", "툴팁 머리에 이름·요금제가 없다: \(lines)")
        #expect(lines.contains("5시간 27% 이상 · 3시간 전 · \(reset)"), "툴팁: \(card.tooltipText)")
        #expect(card.tooltipText.contains("3시간 전"), "관측 나이를 말하지 않는다")
        // 캡션 문구를 규칙 밖에서 따로 만들지 않았다.
        #expect(card.display(.fiveHour)?.captionText == "3시간 전")

        // ② ★ **이미 지난** 리셋 시각을 미래처럼 적지 않는다(유예 안쪽 — 값은 아직 90% 가 맞다).
        let justPassed = AILimitReadOutcome(results: [.claude: .success(AILimitProviderSnapshot(
            provider: .claude,
            windows: [AILimitWindowSnapshot(window: .fiveHour, usedPercent: 90,
                                            resetsAt: amNow.addingTimeInterval(-60),
                                            observedAt: amNow.addingTimeInterval(-1_800), source: .local)]
        ))])
        let grace = try #require(AILimitCardModel.all(store: store(justPassed, at: amNow), now: amNow).first)
        #expect(grace.display(.fiveHour)?.valueText == "90%", "전제: 유예 안쪽이라 값은 아직 90% 다")
        #expect(grace.resetTexts[.fiveHour] == nil, "지난 리셋 시각을 적었다 — 미래로 읽힌다")
        #expect(grace.tooltipText.contains("5시간 90% · 30분 전"))
        #expect(!grace.tooltipText.contains("리셋"), "지난 리셋이 툴팁에 남았다: \(grace.tooltipText)")
        // 요금제가 없으면 이름만 적는다(빈 칸·공백이 남지 않는다).
        #expect(grace.tooltipText.split(separator: "\n").first == "Claude")

        // ③ 리셋을 **이미 주장한** 창은 규칙의 문구만 말한다(같은 사실을 두 번 적지 않는다).
        let claimed = AILimitReadOutcome(results: [.claude: .success(AILimitProviderSnapshot(
            provider: .claude,
            windows: [AILimitWindowSnapshot(window: .fiveHour, usedPercent: 88,
                                            resetsAt: amNow.addingTimeInterval(-300),
                                            observedAt: amNow.addingTimeInterval(-1_800), source: .local)]
        ))])
        let after = try #require(AILimitCardModel.all(store: store(claimed, at: amNow), now: amNow).first)
        #expect(after.display(.fiveHour)?.valueText == "0%" && after.display(.fiveHour)?.captionText == "초기화됨")
        #expect(after.resetTexts[.fiveHour] == nil)
        #expect(after.tooltipText.contains("5시간 0% · 초기화됨"))
    }

    /// ★ 뷰가 승인된 문법을 **실제로** 그린다(값으로는 안 보이는 자리라 소스로 잰다 — 이름 없음 · 열 머리
    /// 한 번 · 구분선 전폭 · 고정 높이 · 고정 숫자 칸 · tabular-nums).
    @Test
    func theCardViewDrawsTheApprovedGrammar() throws {
        let code = V0317ShopTests.stripped(try V0317ShopTests.source("CheckAILimitsRow.swift"))
        // ① 줄에 **이름 글자가 없다**(마크만). 있으면 바가 각 60pt 로 줄어 8% 와 0% 가 안 갈린다.
        #expect(code.contains("AIProviderTile(provider: model.provider, size: AILimitRowWidthBudget.markSide)"))
        #expect(!code.contains("provider.displayName)") || !code.contains("Text(model.provider.displayName)"),
                "줄에 제공자 이름을 글자로 그렸다 — 그 폭은 바의 것이다")
        #expect(!code.contains("Text(provider.displayName)"), "줄에 제공자 이름을 글자로 그렸다")
        // ② 열 머리는 **머리 줄에 한 번**이다(줄마다 반복하지 않는다).
        #expect(code.components(separatedBy: "columnHeader(").count - 1 == 3,
                "열 머리 호출이 둘(머리 줄) + 정의 하나가 아니다")
        #expect(code.contains("AILimitMacPalette.headerColor(window)"), "열 머리를 그 열 색으로 물들이지 않는다")
        // ③ 구분선은 좌우 패딩을 **안 받는다**(카드 안쪽 여백 바깥까지 긋는다). 줄은 받는다.
        #expect(code.contains("Rectangle() .fill(AILimitMacPalette.separator) .frame(height: AILimitRowWidthBudget.separatorHeight)"))
        #expect(code.contains("AILimitProviderRow(model: model) .padding(.horizontal, AILimitRowWidthBudget.rowInsetX)"))
        // ④ 높이를 뷰가 못 박는다(예산이 조용히 거짓이 되지 않게).
        #expect(code.contains(".frame(height: AILimitRowWidthBudget.cardHeight(providers: models.count))"))
        #expect(code.contains(".frame(height: AILimitRowWidthBudget.providerRowHeight)"))
        // ⑤ 숫자는 고정 칸 · 오른쪽 정렬 · tabular-nums.
        #expect(code.contains(".frame(width: AILimitRowWidthBudget.valueWidth, alignment: .trailing)"))
        #expect(code.components(separatedBy: ".monospacedDigit()").count - 1 >= 1, "tabular-nums 가 없다")
        // ⑥ 바 색은 **열 색**이고 폭은 산식에서 온다.
        #expect(code.contains("tint: AILimitMacPalette.barColor(window)"))
        #expect(code.contains(".frame(width: AILimitRowWidthBudget.barWidth)"))
        // ⑦ 하한은 **불투명도**로 말한다(폰·위젯과 같은 수 — 교차 모듈 계약 테스트가 그 숫자를 되묻는다).
        #expect(code.contains("floorOnly ? 0.55 : 1"))
        // ⑧ 자격증명이 없으면 아무것도 그리지 않는다(간격도 없다).
        #expect(code.contains("if store.isAvailable") && code.contains("EmptyView()"))
    }

    /// ★ **별도 창이 사라졌다**(2026-10-07 사용자 지시: "메인 화면 자체에 다 뜨게끔").
    ///
    /// 없으면: 창 파일만 지우고 배선·등록이 남아도 컴파일은 통과한다(지금은 통과하지 않지만, 창을 되살리는
    /// 변경이 이 자리들을 조용히 반쪽만 되살릴 수 있다). "자세히 ›" 한 줄이 남아 있으면 누를 데가 없는 버튼이다.
    @Test
    func theStandaloneLimitsWindowIsGone() throws {
        let sources = try V0325TooltipTests.strippedSources()
        #expect(sources["CheckAILimitsWindow.swift"] == nil, "창 파일이 아직 있다")
        let haunted = sources.filter { $0.value.contains("CheckAILimitsWindowController") }.keys.sorted()
        #expect(haunted.isEmpty, "사라진 창 컨트롤러를 아직 부르는 파일: \(haunted)")
        #expect(sources["CheckAILimitsRow.swift"]?.contains("자세히 ›") == false,
                "누를 데가 없는 '자세히 ›' 가 남았다")
        // 독립 창 목록에서도 빠졌다(없는 창의 식별자가 남으면 "등록이 빠졌다"로 읽힌다).
        #expect(MiniGameSpaceKey.standaloneWindowIDs.count == 3)
        #expect(!MiniGameSpaceKey.standaloneWindowIDs.contains("check.aiLimitsWindow"))
        // 팝오버가 갱신을 당기는 길은 **남아 있다**(창의 `onOpen` 이 하던 일 — 그게 사라지면 팝오버를 열어도
        // 숫자가 안 갱신된다). 스토어의 5분 하한이 난사를 막는 것도 그대로다.
        #expect(sources["WorkTimerStore.swift"]?.contains("refreshAILimitsIfNeeded(force: true)") == true,
                "팝오버 열림이 리밋 갱신을 당기지 않는다")
    }
}


// MARK: - 카드 렌더 (픽셀 실측 — 소스 계약이 증명할 수 없는 것)

/// ★ **바가 열 색으로 그려졌는가**를 실제 픽셀에서 되묻는다.
///
/// 소스 계약(`theCardViewDrawsTheApprovedGrammar`)은 "그 상수를 넘겼는가"까지만 잰다. `tint:` 에 맞는 색을
/// 넣고도 바가 안 보이는 조합이 있다(폭 0 · 트랙이 채움을 덮음 · 프레임이 접힘) — 그걸 가르는 길은 굽는 것뿐이다.
/// 그리고 이 자리는 **승인된 디자인이 눈으로 맞는지** 사람이 볼 수 있는 유일한 산출물이기도 하다
/// (`CHECK_SNAPSHOT_DIR` 에 PNG 가 남는다).
@Suite("AILimitsMac — 카드 렌더: 열 색·없는 칸·안내 줄")
@MainActor
struct AILimitsMacCardRenderTests {
    /// 제공자 `n` 명짜리 스토어(1 = Claude · 2 = + Codex · 3 = + 안티그래비티).
    private func store(providers: Int, function: String = #function, line: Int = #line) -> AILimitStore {
        let name = CheckTestScratch.uniqueSuitePath(function: function, line: line + providers)
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        let subject = AILimitStore(defaults: defaults, clock: { amNow }, runner: { _ in AILimitReadOutcome() })
        var results: [AILimitProvider: Result<AILimitProviderSnapshot, AILimitReadError>] = [
            .claude: .success(AILimitProviderSnapshot(provider: .claude, windows: [
                AILimitWindowSnapshot(window: .fiveHour, usedPercent: 82,
                                      resetsAt: amNow.addingTimeInterval(3_600), observedAt: amNow, source: .local),
                AILimitWindowSnapshot(window: .weekly, usedPercent: 31,
                                      resetsAt: amNow.addingTimeInterval(200_000), observedAt: amNow, source: .local)
            ], planLabel: "max"))
        ]
        if providers >= 2 {
            results[.codex] = .success(AILimitProviderSnapshot(provider: .codex, windows: [
                AILimitWindowSnapshot(window: .weekly, usedPercent: 12,
                                      resetsAt: amNow.addingTimeInterval(300_000), observedAt: amNow, source: .local)
            ], planLabel: "plus"))
        }
        if providers >= 3 { results[.antigravity] = .failure(AILimitReadError(.expired)) }
        subject.apply(AILimitReadOutcome(results: results), now: amNow)
        return subject
    }

    /// Claude(5시간 82% · 주간 31%) · Codex(주간 12% 만 — 5시간 창이 **없다**) · 안티그래비티(만료 — 안내 줄).
    /// 세 줄이 세 가지 모양을 한 그림에 담는다.
    private func demoStore(function: String = #function, line: Int = #line) -> AILimitStore {
        let name = CheckTestScratch.uniqueSuitePath(function: function, line: line)
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        let subject = AILimitStore(defaults: defaults, clock: { amNow }, runner: { _ in AILimitReadOutcome() })
        subject.apply(AILimitReadOutcome(results: [
            .claude: .success(AILimitProviderSnapshot(provider: .claude, windows: [
                AILimitWindowSnapshot(window: .fiveHour, usedPercent: 82,
                                      resetsAt: amNow.addingTimeInterval(3_600), observedAt: amNow, source: .local),
                AILimitWindowSnapshot(window: .weekly, usedPercent: 31,
                                      resetsAt: amNow.addingTimeInterval(200_000), observedAt: amNow, source: .local)
            ], planLabel: "max")),
            .codex: .success(AILimitProviderSnapshot(provider: .codex, windows: [
                AILimitWindowSnapshot(window: .weekly, usedPercent: 12,
                                      resetsAt: amNow.addingTimeInterval(300_000), observedAt: amNow, source: .local)
            ], planLabel: "plus")),
            .antigravity: .failure(AILimitReadError(.expired))
        ]), now: amNow)
        return subject
    }

    /// 점 좌표 → 픽셀 좌표(scale 3). 위에서 아래로 세는 비트맵 좌표계다.
    private func rgb(_ bitmap: NSBitmapImageRep, x: CGFloat, y: CGFloat) throws -> (Int, Int, Int) {
        let scale: CGFloat = 3
        let color = try #require(bitmap.colorAt(x: Int(x * scale), y: Int(y * scale)))
        let srgb = try #require(color.usingColorSpace(.sRGB))
        return (Int((srgb.redComponent * 255).rounded()),
                Int((srgb.greenComponent * 255).rounded()),
                Int((srgb.blueComponent * 255).rounded()))
    }

    /// 후보 색들의 **렌더된** 값. 정의값(sRGB 바이트)과 바로 견주면 안 된다 —
    /// `ImageRenderer` 의 색 관리가 채널당 10여 단위를 들어 올려(2026-10-07 실측: 패널 (43,46,61) → (57,61,78))
    /// 어두운 두 트랙이 서로의 정의값보다 **상대의 렌더값에 더 가까워진다**. 그래서 기준도 **같은 기계로 굽는다**:
    /// 후보를 한 줄 띠로 구워 그 픽셀을 표로 쓴다. 이 저장소의 원칙 그대로 — 재는 자와 재는 물건을 같은 자로 잰다.
    private static let candidates: [(String, Color)] = [
        ("5시간바", AILimitMacPalette.fiveHourBar),
        ("주간바", AILimitMacPalette.weeklyBar),
        ("빈트랙", AILimitMacPalette.emptyTrack),
        ("없는칸트랙", AILimitMacPalette.absentTrack),
        ("구분선", AILimitMacPalette.separator),
        ("카드배경", CheckTheme.panel),
    ]

    /// 후보 띠를 굽고 각 칸 복판을 읽어 표로 만든다.
    private func renderedReference() throws -> [(String, (Int, Int, Int))] {
        let side: CGFloat = 12
        let strip = HStack(spacing: 0) {
            ForEach(Array(Self.candidates.enumerated()), id: \.offset) { _, entry in
                Rectangle().fill(entry.1).frame(width: side, height: side)
            }
        }
        let bitmap = try #require(CheckRenderSettle.bitmap(strip, scale: 3), "기준 띠를 굽지 못했다")
        var table: [(String, (Int, Int, Int))] = []
        for (index, entry) in Self.candidates.enumerated() {
            table.append((entry.0, try rgb(bitmap, x: side * CGFloat(index) + side / 2, y: side / 2)))
        }
        // 전제: 여섯 기준이 서로 **다르게** 구워졌다. 둘이 같으면 아래 '가장 가까운 색' 판정이 동전 던지기다.
        for i in table.indices {
            for j in table.indices where j > i {
                #expect(table[i].1 != table[j].1, "\(table[i].0) 와 \(table[j].0) 가 같은 색으로 구워졌다")
            }
        }
        return table
    }

    /// 후보 가운데 **가장 가까운** 색의 이름. 절대 일치로 재지 않는 이유: `ImageRenderer` 가 같은 내용에서도
    /// 채널당 ≤2 를 흔들고(이 저장소 실측), 거기에 허용오차를 키우면 이번엔 두 후보가 같이 든다.
    /// "어느 색에 가장 가까운가"는 그 떨림에 흔들리지 않으면서도 **열이 바뀌면 반드시 빨개진다.**
    private func nearest(_ probe: (Int, Int, Int), in table: [(String, (Int, Int, Int))]) -> String {
        var best = ("", Int.max)
        for (name, c) in table {
            let d = (probe.0 - c.0) * (probe.0 - c.0) + (probe.1 - c.1) * (probe.1 - c.1) + (probe.2 - c.2) * (probe.2 - c.2)
            if d < best.1 { best = (name, d) }
        }
        return best.0
    }

    @Test
    func theBarsCarryTheirColumnColourAndAbsentCellsStayEmpty() throws {
        let b = AILimitRowWidthBudget.self
        let reference = try renderedReference()
        let card = CheckAILimitsCard(store: demoStore(), clock: { amNow })
            .frame(width: b.cardOuterWidth)
        let bitmap = try #require(CheckRenderSettle.bitmap(card, scale: 3), "카드를 굽지 못했다")
        amSaveSnapshot(bitmap, name: "ai-limits-card-316.png")
        func at(_ x: CGFloat, _ y: CGFloat) throws -> String { nearest(try rgb(bitmap, x: x, y: y), in: reference) }

        // ① 크기 = 예산 산식. 뷰가 자연 높이로 자라면 팝오버 높이 예산이 조용히 거짓이 된다.
        #expect(bitmap.pixelsWide == Int(b.cardOuterWidth * 3))
        #expect(bitmap.pixelsHigh == Int(b.cardHeight(providers: 3) * 3),
                "카드가 \(Double(bitmap.pixelsHigh) / 3)pt 다 — 예산은 \(b.cardHeight(providers: 3))pt")

        // 자리 산식(점). x: 여백 12 | 마크 20 | 8 | 바 69 | 6 | 숫자 52 | 10 | 바 69 | 6 | 숫자 52
        let fiveHourBarX = b.rowInsetX + b.markSide + b.markGap
        let weeklyBarX = fiveHourBarX + b.barWidth + b.barValueGap + b.valueWidth + b.columnGap
        // y: 여백 10 | 머리 14 | 7 | 줄 24 | 선 1 | 줄 24 | 선 1 | 줄 24
        func rowCenterY(_ index: Int) -> CGFloat {
            b.rowInsetY + b.titleRowHeight + b.titleRowGap
                + CGFloat(index) * (b.providerRowHeight + b.separatorHeight) + b.providerRowHeight / 2
        }

        // ② Claude 줄: 5시간 채움은 **5시간 색**, 주간 채움은 **주간 색**. 둘이 섞이면 열 단서가 거짓이 된다.
        let claudeY = rowCenterY(0)
        #expect(try at(fiveHourBarX + 20, claudeY) == "5시간바", "5시간 채움이 5시간 색이 아니다")
        #expect(try at(weeklyBarX + 8, claudeY) == "주간바", "주간 채움이 주간 색이 아니다")
        // 채움 밖은 빈 트랙이다(82% → 69pt 중 56.6pt 까지만 찬다 · 31% → 21.4pt).
        #expect(try at(fiveHourBarX + b.barWidth - 4, claudeY) == "빈트랙", "5시간 바가 82% 인데 끝까지 찼다")
        #expect(try at(weeklyBarX + b.barWidth - 4, claudeY) == "빈트랙")

        // ③ Codex 줄: 5시간 창이 **없다** → 더 어두운 트랙만(채움 없음). 주간 12% 는 앞쪽만 찬다.
        let codexY = rowCenterY(1)
        #expect(try at(fiveHourBarX + 20, codexY) == "없는칸트랙",
                "없는 5시간 칸에 채움이나 보통 트랙을 그렸다 — '0% 라 비었다'로 읽힌다")
        #expect(try at(weeklyBarX + 3, codexY) == "주간바", "주간 12% 가 안 보인다")
        #expect(try at(weeklyBarX + b.barWidth - 4, codexY) == "빈트랙")

        // ④ 안티그래비티 줄(만료): 바가 **하나도 없다** — 두 칸을 '없음' 으로 비우지 않고 안내 한 줄을 말한다.
        let agY = rowCenterY(2)
        #expect(try at(weeklyBarX + 20, agY) == "카드배경",
                "못 읽은 제공자 줄에 트랙을 그렸다 — '창이 없다'로 읽힌다")
        #expect(try at(weeklyBarX + b.barWidth - 4, agY) == "카드배경")

        // ⑤ 제공자 사이 구분선이 **카드 안쪽 여백 바깥까지** 간다(좌우 끝 모두).
        let separatorY = b.rowInsetY + b.titleRowHeight + b.titleRowGap + b.providerRowHeight + 0.5
        for x in [CGFloat(2), b.rowInsetX / 2, b.cardOuterWidth - 3] {
            #expect(try at(x, separatorY) == "구분선", "구분선이 x=\(x)pt 에서 끊겼다")
        }
        // ★ 기준선이 갈린다: 같은 x 의 **줄 안쪽**은 구분선 색이 아니다 — 같은 답이면 위 단언은
        //   "카드 배경이 원래 그 색이다"를 잰 것이고 선을 통째로 지워도 초록이다.
        #expect(try at(2, separatorY + 6) == "카드배경", "줄 안쪽도 구분선 색이다 — 위 단언이 아무것도 안 잰다")
        // 두 번째 구분선도 있다(선 하나만 그리고 나머지를 빼먹는 변경을 잡는다).
        let secondSeparatorY = separatorY + b.providerRowHeight + b.separatorHeight
        #expect(try at(b.cardOuterWidth / 2, secondSeparatorY) == "구분선", "두 번째 구분선이 없다")
    }

    /// ★ 뷰가 **예산과 같은 높이**로 굽힌다 — 제공자 1·2·3 전부. 산식만 재면(위 폭 스위트) 뷰가 자연 높이로
    /// 자라는 변경이 조용히 지나가고, 그 순간 팝오버 높이 상한(700pt) 계산이 통째로 거짓이 된다.
    @Test
    func theRenderedHeightMatchesTheBudgetForOneTwoAndThreeProviders() throws {
        let b = AILimitRowWidthBudget.self
        for count in 1...3 {
            let subject = store(providers: count)
            #expect(subject.listedProviders.count == count, "전제: 제공자 \(count)명")
            let card = CheckAILimitsCard(store: subject, clock: { amNow }).frame(width: b.cardOuterWidth)
            let bitmap = try #require(CheckRenderSettle.bitmap(card, scale: 3), "제공자 \(count)명 카드를 굽지 못했다")
            #expect(bitmap.pixelsHigh == Int(b.cardHeight(providers: count) * 3),
                    "제공자 \(count)명 카드가 \(Double(bitmap.pixelsHigh) / 3)pt — 예산은 \(b.cardHeight(providers: count))pt")
            amSaveSnapshot(bitmap, name: "ai-limits-card-\(count).png")
        }
        // 제공자 0명은 **아무것도 안 그린다**(빈 카드를 0% 로 지어내지 않는다 · 간격도 안 먹는다).
        let empty = AILimitStore.inert()
        #expect(empty.isAvailable == false)
        #expect(b.budgetHeight(providers: empty.listedProviders.count) == 0)
    }
}

/// 사람이 볼 그림을 남긴다. 세션 전용 절대 경로를 소스에 박지 않는다 — 퍼블릭 저장소에 개인 머신 경로가 남는다.
private func amSaveSnapshot(_ bitmap: NSBitmapImageRep, name: String) {
    let dir = ProcessInfo.processInfo.environment["CHECK_SNAPSHOT_DIR"].map {
        URL(fileURLWithPath: $0, isDirectory: true)
    } ?? FileManager.default.temporaryDirectory.appendingPathComponent("check-ai-limits", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    guard let png = bitmap.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: dir.appendingPathComponent(name))
}

// MARK: - 문서 대조 헬퍼 (업로드 칸 ↔ 두 공개 문서)

private struct AMDocError: Error, CustomStringConvertible {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}

/// `docs/` 가 있는 저장소 뿌리. 워크트리·본 저장소 어느 쪽에서 돌려도 찾는다(`docs/` 는 추적되는 폴더다 —
/// `supabase/` 와 달리 워크트리에도 있다).
private func amRepositoryRoot() throws -> URL {
    var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    var visited: [String] = []
    while directory.path != "/" {
        if FileManager.default.fileExists(atPath: directory.appendingPathComponent("docs/privacy.md").path) {
            return directory
        }
        visited.append(directory.path)
        directory = directory.deletingLastPathComponent()
    }
    throw AMDocError("docs/privacy.md 를 못 찾았다. 훑은 조상: \(visited.joined(separator: ", "))")
}

/// `docs/ai-limits.md` §5 표를 **두 칸으로 갈라서** 돌려준다(올라간다 / 안 올라간다).
///
/// ★ 칸을 갈라야 하는 이유: 한 줄에 두 열이 같이 있어서 통째로 `contains` 하면 '안 올라간다' 쪽 글자가
///   '올라간다' 단언을 만족시킨다 — 이 테스트가 잡으려는 결함이 바로 그 모양이었다.
/// 머리행·구분행은 버린다. 표가 사라지거나 절 제목이 바뀌면 **던진다**(조용히 빈 문자열을 돌려주면
/// 모든 `!contains` 단언이 공짜로 초록이 된다).
private func amUploadSectionColumns(_ doc: String) throws -> (uploaded: String, withheld: String) {
    let lines = doc.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    guard let start = lines.firstIndex(where: { $0.hasPrefix("## 5. 서버에 올라가는 것과 안 올라가는 것") }) else {
        throw AMDocError("ai-limits.md 에서 §5 절을 못 찾았다 — 올리는 항목의 내부 정본이다")
    }
    var uploaded: [String] = []
    var withheld: [String] = []
    for line in lines[start...].drop(while: { !$0.hasPrefix("|") }).prefix(while: { $0.hasPrefix("|") }) {
        let cells = line.split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard cells.count >= 4 else { continue }          // ["", 왼쪽, 오른쪽, ""]
        let (left, right) = (cells[1], cells[2])
        if left.hasPrefix("---") || left == "올라간다" { continue }   // 구분행·머리행
        uploaded.append(left)
        withheld.append(right)
    }
    guard uploaded.count >= 5, withheld.count == uploaded.count else {
        throw AMDocError("§5 표의 행이 \(uploaded.count) 개다 — 표가 깨졌거나 모양이 바뀌었다")
    }
    return (uploaded.joined(separator: "\n"), withheld.joined(separator: "\n"))
}
