// 원본: Sources/CheckCore/AILimitReaders.swift(parseCredentials · parseUsage · ResetTrust · DateParser · HTTP.failure · JWT) ·
//       Sources/CheckCore/SupabaseWorkServiceAILimits.swift(aiLimitRow · aiLimitClearingRow · AILimitUpsertRow · AILimitPrefsUpsertRow) ·
//       Sources/check/WorkTimerStoreAILimits.swift(AILimitUploadLedger) @ a90d8623
// W2-h2 골든 둘: `token-usage/limits/readers` · `token-usage/limits/upload`. Kotlin 대조:
//   multiplatform/feature/desktop/src/desktopTest/kotlin/com/yehsung/aingcheck/feature/desktop/ailimits/{AILimitReaderGoldenTest,AILimitUploadBodyGoldenTest}.kt
// 입력은 전부 합성(실제 홈·실제 토큰·실제 계정 0). JWT 는 서명 없는 합성 토큰이다. 네트워크·UserDefaults·키체인을 쓰지 않는다.
import CheckGoldenSupport
import Foundation
import Testing
@testable import check
@testable import CheckCore

@Suite("GoldenExport AILimit — 리밋 리더 파싱 · 업로드 본문(W2-h2)")
struct GoldenExportAILimit {
    // MARK: 도우미

    fileprivate static func opt(_ text: String?) -> GoldenJSON { text.map(GoldenJSON.string) ?? .null }
    fileprivate static func optBits(_ value: Double?) -> GoldenJSON { value.map(GoldenJSON.bits) ?? .null }
    fileprivate static func dateBits(_ date: Date?) -> GoldenJSON { optBits(date?.timeIntervalSince1970) }

    fileprivate static func b64url(_ text: String) -> String {
        Data(text.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }

    /// 서명 없는 합성 JWT(머리.본문.꼬리).
    fileprivate static func jwt(_ payload: String) -> String { "\(b64url(#"{"alg":"none","typ":"JWT"}"#)).\(b64url(payload)).c2lnbmF0dXJl" }

    fileprivate static func error(_ e: AILimitReadError) -> GoldenJSON {
        ["failure": .string(e.failure.rawValue), "retryAfterBits": optBits(e.retryAfter)]
    }

    fileprivate static func snapshot(_ s: AILimitProviderSnapshot) -> GoldenJSON {
        [
            "provider": .string(s.provider.rawValue),
            "planLabel": opt(s.planLabel),
            "accountFingerprint": opt(s.accountFingerprint),
            "windows": .array(s.windows.map { w in
                [
                    "window": .string(w.window.rawValue),
                    "usedPercentBits": .bits(w.usedPercent),
                    "resetsAtBits": dateBits(w.resetsAt),
                    "observedAtBits": .bits(w.observedAt.timeIntervalSince1970),
                    "source": .string(w.source.rawValue),
                ]
            }),
        ]
    }

    fileprivate static func usageOutcome(_ r: Result<AILimitProviderSnapshot, AILimitReadError>) -> GoldenJSON {
        switch r {
        case .success(let s): return ["ok": snapshot(s)]
        case .failure(let e): return ["err": error(e)]
        }
    }

    // MARK: readers

    static let observedAt = Date(timeIntervalSince1970: 1_793_390_000.25)

    static let claudeCredentials: [(String, String)] = [
        ("valid", #"{"claudeAiOauth":{"accessToken":"synthetic-oat-token","refreshToken":"synthetic-ort-token","expiresAt":1793404800000,"scopes":["user:inference"],"subscriptionType":"max"}}"#),
        ("no-expiry", #"{"claudeAiOauth":{"accessToken":"tok-a","subscriptionType":"pro"}}"#),
        ("empty-token", #"{"claudeAiOauth":{"accessToken":"","expiresAt":1793404800000}}"#),
        ("number-token", #"{"claudeAiOauth":{"accessToken":123}}"#),
        ("missing-oauth", #"{"other":{}}"#),
        ("oauth-not-object", #"{"claudeAiOauth":"x"}"#),
        ("not-json", "not json"),
        ("top-array", "[]"),
        ("expires-fraction-ms", #"{"claudeAiOauth":{"accessToken":"tok-b","expiresAt":1793404800123}}"#),
        ("expires-string", #"{"claudeAiOauth":{"accessToken":"tok-c","expiresAt":"1793404800000"}}"#),
        ("expires-bool", #"{"claudeAiOauth":{"accessToken":"tok-d","expiresAt":true}}"#),
        ("plan-too-long", #"{"claudeAiOauth":{"accessToken":"tok-e","subscriptionType":"0123456789012345678901234567890123456789"}}"#),
        ("plan-whitespace", "{\"claudeAiOauth\":{\"accessToken\":\"tok-f\",\"subscriptionType\":\"  max \\n\"}}"),
        ("plan-empty", #"{"claudeAiOauth":{"accessToken":"tok-g","subscriptionType":"   "}}"#),
    ]

    static let claudeUsage: [(String, String)] = [
        ("both-windows", #"{"five_hour":{"utilization":27.0,"resets_at":"2026-10-30T05:00:00.123456+00:00"},"seven_day":{"utilization":61.5,"resets_at":"2026-11-02T00:00:00Z"},"iguana_necktie":{"utilization":99,"limit_dollars":250}}"#),
        ("zero-five-hour", #"{"five_hour":{"utilization":0,"resets_at":"2026-10-30T05:00:00Z"},"seven_day":{"utilization":12,"resets_at":"2026-11-02T00:00:00.5Z"}}"#),
        ("weekly-only", #"{"five_hour":null,"seven_day":{"utilization":3.25,"resets_at":"2026-11-02T00:00:00Z"}}"#),
        ("both-null", #"{"five_hour":null,"seven_day":null}"#),
        ("utilization-string", #"{"five_hour":{"utilization":"27","resets_at":"2026-10-30T05:00:00Z"}}"#),
        ("reset-unparseable", #"{"five_hour":{"utilization":44,"resets_at":"soon"}}"#),
        ("is-active-false", #"{"five_hour":{"utilization":27,"resets_at":"2026-10-30T05:00:00Z","is_active":false},"limits":[{"is_active":false}]}"#),
        ("over-and-negative", #"{"five_hour":{"utilization":100.5,"resets_at":"2026-10-30T05:00:00Z"},"seven_day":{"utilization":-3,"resets_at":"2026-11-02T00:00:00Z"}}"#),
        ("not-json", "{"),
        ("reset-null", #"{"seven_day":{"utilization":8,"resets_at":null}}"#),
    ]

    static var codexCredentials: [(String, String)] {
        let full = jwt(#"{"exp":1794000000,"chatgpt_plan_type":"plus","chatgpt_account_id":"acct-claim"}"#)
        let nested = jwt(#"{"exp":1794000000.5,"https://api.openai.com/auth":{"chatgpt_plan_type":"pro","chatgpt_account_id":"acct-nested"}}"#)
        let noExp = jwt(#"{"chatgpt_plan_type":"team"}"#)
        return [
            ("file-account-wins", #"{"tokens":{"access_token":"\#(full)","account_id":"acct-file","refresh_token":"rt-SYNTHETIC"}}"#),
            ("claim-account", #"{"tokens":{"access_token":"\#(full)","account_id":""}}"#),
            ("nested-claims", #"{"tokens":{"access_token":"\#(nested)"}}"#),
            ("no-exp", #"{"tokens":{"access_token":"\#(noExp)"}}"#),
            ("opaque-token", #"{"tokens":{"access_token":"opaque"}}"#),
            ("bad-payload", #"{"tokens":{"access_token":"a.@@@.c"}}"#),
            ("empty-token", #"{"tokens":{"access_token":""}}"#),
            ("no-tokens", #"{"OPENAI_API_KEY":"synthetic-api-key"}"#),
            ("tokens-null", #"{"OPENAI_API_KEY":null,"tokens":null}"#),
            ("not-json", "nope"),
        ]
    }

    static let codexUsage: [(String, String, String?, String?)] = [
        ("two-windows", #"{"plan_type":"plus","rate_limit":{"primary_window":{"used_percent":12.5,"limit_window_seconds":18000,"reset_after_seconds":9000,"reset_at":1793399000},"secondary_window":{"used_percent":40,"limit_window_seconds":604800,"reset_after_seconds":300000,"reset_at":1793690000}}}"#, nil, "acct-1"),
        ("zero-used", #"{"rate_limit":{"primary_window":{"used_percent":0,"limit_window_seconds":18000,"reset_after_seconds":18000,"reset_at":1793408000}}}"#, "plus", nil),
        ("projected-window", #"{"rate_limit":{"primary_window":{"used_percent":5,"limit_window_seconds":18000,"reset_after_seconds":18000.4,"reset_at":1793408000}}}"#, nil, nil),
        ("weekly-as-primary", #"{"plan_type":"pro","rate_limit":{"primary_window":{"used_percent":33,"limit_window_seconds":604800,"reset_after_seconds":100000,"reset_at":1793490000},"secondary_window":null}}"#, nil, "acct-2"),
        ("both-null", #"{"rate_limit":{"primary_window":null,"secondary_window":null}}"#, nil, nil),
        ("no-rate-limit", #"{"plan_type":"plus"}"#, nil, nil),
        ("unknown-length", #"{"rate_limit":{"primary_window":{"used_percent":7,"limit_window_seconds":86400,"reset_after_seconds":100,"reset_at":1793390100}}}"#, "plus", nil),
        ("two-weekly", #"{"rate_limit":{"primary_window":{"used_percent":10,"limit_window_seconds":604800,"reset_at":1793600000},"secondary_window":{"used_percent":20,"limit_window_seconds":604800,"reset_at":1793700000}}}"#, nil, nil),
        ("fraction-reset", #"{"rate_limit":{"primary_window":{"used_percent":1.5,"limit_window_seconds":18000,"reset_after_seconds":60,"reset_at":1793390060.5}}}"#, nil, nil),
        ("used-string", #"{"rate_limit":{"primary_window":{"used_percent":"9","limit_window_seconds":18000}}}"#, nil, nil),
        ("plan-blank", #"{"plan_type":" ","rate_limit":{"secondary_window":{"used_percent":2,"reset_at":1793700000}}}"#, "fallback", nil),
    ]

    static let resetTrust: [(Double, Double?, Double?)] = [
        (0, nil, nil), (-1, nil, nil), (0.01, nil, nil), (50, 18000, 18000), (50, 18000.9, 18000), (50, 18001, 18000),
        (50, 17999.1, 18000), (50, 100, 0), (50, nil, 18000), (50, 100, nil), (100, 604800, 604800),
    ]

    static let dates: [String?] = [
        nil, "", "2026-10-30T05:00:00Z", "2026-10-30T05:00:00.123Z", "2026-10-30T05:00:00.123456+00:00", "2026-10-30T14:00:00+09:00",
        "2026-10-30 05:00:00Z", "soon", "2026-10-30T05:00:00.5Z",
    ]

    static let retryHeaders: [String] = ["300", "120.5", " 300", "abc", "1e2", "", "Wed, 21 Oct 2026 07:28:00 GMT", "-5", "+7", ".5", "5."]

    @Test("token-usage/limits/readers — Claude·Codex 자격 증명 · 사용량 · 리셋 신뢰 · 날짜 · HTTP 분류 · 문구표")
    func readers() {
        var cases: [GoldenJSON] = []
        for (id, input) in Self.claudeCredentials {
            let out: GoldenJSON
            switch AILimitClaudeReader.parseCredentials(Data(input.utf8)) {
            case .success(let c):
                out = ["ok": ["accessToken": .string(c.accessToken), "expiresAtBits": Self.dateBits(c.expiresAt), "planLabel": Self.opt(c.planLabel)]]
            case .failure(let e): out = ["err": Self.error(e)]
            }
            cases.append(["id": .string("claude-credentials-\(id)"), "kind": "claudeCredentials", "input": .string(input), "output": out])
        }
        for (id, input) in Self.claudeUsage {
            for plan in [nil, "max"] as [String?] {
                let r = AILimitClaudeReader.parseUsage(Data(input.utf8), observedAt: Self.observedAt, planLabel: plan)
                cases.append([
                    "id": .string("claude-usage-\(id)-\(plan ?? "noplan")"), "kind": "claudeUsage", "input": .string(input),
                    "observedAtBits": .bits(Self.observedAt.timeIntervalSince1970), "planLabel": Self.opt(plan), "output": Self.usageOutcome(r),
                ])
            }
        }
        for (id, input) in Self.codexCredentials {
            let out: GoldenJSON
            switch AILimitCodexReader.parseCredentials(Data(input.utf8)) {
            case .success(let c):
                out = ["ok": [
                    "accessToken": .string(c.accessToken), "accountID": Self.opt(c.accountID), "planLabel": Self.opt(c.planLabel),
                    "expiresAtBits": Self.dateBits(c.expiresAt),
                ]]
            case .failure(let e): out = ["err": Self.error(e)]
            }
            cases.append(["id": .string("codex-credentials-\(id)"), "kind": "codexCredentials", "input": .string(input), "output": out])
        }
        for (id, input, fallback, account) in Self.codexUsage {
            let r = AILimitCodexReader.parseUsage(Data(input.utf8), observedAt: Self.observedAt, fallbackPlanLabel: fallback, accountID: account)
            cases.append([
                "id": .string("codex-usage-\(id)"), "kind": "codexUsage", "input": .string(input),
                "observedAtBits": .bits(Self.observedAt.timeIntervalSince1970), "fallbackPlanLabel": Self.opt(fallback),
                "accountID": Self.opt(account), "output": Self.usageOutcome(r),
            ])
        }
        for (i, (used, after, window)) in Self.resetTrust.enumerated() {
            cases.append([
                "id": .string("reset-trust-\(i)"), "kind": "resetTrust", "usedPercentBits": .bits(used),
                "resetAfterBits": Self.optBits(after), "windowSecondsBits": Self.optBits(window),
                "trusts": .bool(AILimitResetTrust.trusts(usedPercent: used, resetAfterSeconds: after, windowSeconds: window)),
            ])
        }
        for (i, raw) in Self.dates.enumerated() {
            cases.append(["id": .string("date-\(i)"), "kind": "date", "raw": Self.opt(raw), "outBits": Self.dateBits(AILimitDateParser.date(raw))])
        }
        for status in [200, 204, 299, 300, 400, 401, 403, 404, 429, 500, 503] {
            for retry in [nil, 300, 12.5] as [Double?] {
                let out = AILimitHTTP.failure(status: status, retryAfter: retry).map(Self.error) ?? .null
                cases.append([
                    "id": .string("http-\(status)-\(retry.map { "\($0)" } ?? "none")"), "kind": "httpFailure", "status": .int(status),
                    "retryAfterBits": Self.optBits(retry), "output": out,
                ])
            }
        }
        for (i, raw) in Self.retryHeaders.enumerated() {
            // `AILimitHTTP.fetcher` 가 헤더에 하는 일 그대로: `TimeInterval.init(String)`.
            cases.append(["id": .string("retry-after-\(i)"), "kind": "retryAfterHeader", "raw": .string(raw), "outBits": Self.optBits(TimeInterval(raw))])
        }
        let failures: [AILimitReadFailure] = [.notInstalled, .notLoggedIn, .blocked, .expired, .unauthorized, .rateLimited, .network, .malformed, .noPlan]
        for failure in failures {
            for provider in [AILimitProvider.claude, .codex, .antigravity] {
                cases.append([
                    "id": .string("failure-\(failure.rawValue)-\(provider.rawValue)"), "kind": "failureTable",
                    "failure": .string(failure.rawValue), "provider": .string(provider.rawValue),
                    "noticeText": Self.opt(failure.noticeText(for: provider)), "hidesProvider": .bool(failure.hidesProvider),
                ])
            }
        }
        goldenEmit(GoldenFile(
            golden: "token-usage/limits/readers",
            equivalence: .bit,
            swiftSources: ["Sources/CheckCore/AILimitReaders.swift", "Sources/CheckCore/JWTClaims.swift"],
            spec: [
                "claudeUsageURL": .string(AILimitClaudeReader.usageURL.absoluteString),
                "claudeBetaHeader": .string(AILimitClaudeReader.betaHeader),
                "codexUsageURL": .string(AILimitCodexReader.usageURL.absoluteString),
                "timeoutBits": .bits(AILimitHTTP.timeout),
                "userAgent": .string(AILimitHTTP.userAgent(appVersion: "1.2.3", note: "ai-limits")),
                "doubles": "…Bits = IEEE754 16진. 시각은 timeIntervalSince1970.",
            ],
            cases: cases
        ))
    }

    // MARK: upload

    fileprivate struct WindowSpec { let window: AILimitWindow; let used: Double; let resets: Double?; let observed: Double }
    fileprivate struct ProviderSpec { let provider: AILimitProvider; let plan: String?; let fingerprint: String?; let windows: [WindowSpec] }

    fileprivate static func bundle(_ specs: [ProviderSpec]) -> AILimitSnapshotBundle {
        AILimitSnapshotBundle(providers: specs.map { p in
            AILimitProviderSnapshot(
                provider: p.provider,
                windows: p.windows.map {
                    AILimitWindowSnapshot(window: $0.window, usedPercent: $0.used, resetsAt: $0.resets.map(Date.init(timeIntervalSince1970:)),
                                          observedAt: Date(timeIntervalSince1970: $0.observed), source: .local)
                },
                planLabel: p.plan, accountFingerprint: p.fingerprint
            )
        })
    }

    fileprivate static func bundleJSON(_ specs: [ProviderSpec]) -> GoldenJSON {
        .array(specs.map { p in
            [
                "provider": .string(p.provider.rawValue), "planLabel": opt(p.plan), "accountFingerprint": opt(p.fingerprint),
                "windows": .array(p.windows.map {
                    ["window": .string($0.window.rawValue), "usedPercentBits": .bits($0.used), "resetsAtBits": optBits($0.resets),
                     "observedAtBits": .bits($0.observed)]
                }),
            ]
        })
    }

    fileprivate static func rowJSON(_ row: AILimitUpsertRow) -> GoldenJSON {
        [
            "user_id": .string(row.userId), "device_id": .string(row.deviceId), "device_label": opt(row.deviceLabel),
            "provider": .string(row.provider), "five_hour_percent": optBits(row.fiveHourPercent), "five_hour_resets_at": opt(row.fiveHourResetsAt),
            "weekly_percent": optBits(row.weeklyPercent), "weekly_resets_at": opt(row.weeklyResetsAt), "plan_label": opt(row.planLabel),
            "observed_at": .string(row.observedAt),
        ]
    }

    /// 실제 JSONEncoder 출력에서 행마다 (키 정렬 목록, null 인 키 정렬 목록). 손글씨 인코더가 null 을 **적었는지** 바이트로 잰다.
    fileprivate static func encodedShape(_ rows: [AILimitUpsertRow]) throws -> GoldenJSON {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase   // SupabaseWorkService.encoder 와 같은 설정
        let data = try encoder.encode(rows)
        guard let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { throw GoldenJSONError("행 배열이 아니다") }
        return .array(array.map { row in
            ["keys": .array(row.keys.sorted().map(GoldenJSON.string)),
             "nullKeys": .array(row.filter { $0.value is NSNull }.keys.sorted().map(GoldenJSON.string))]
        })
    }

    static let user = "00000000-0000-4000-8000-00000000a11e"
    static let device = "win:5f1c0de0aa11b22c"

    @Test("token-usage/limits/upload — 값 행 · 비우는 행 · 명시 null · 지문 키 없음 · 중복 PK 접기 · 메인 기기 본문 · 장부 지문")
    func upload() async throws {
        let service = SupabaseWorkService(projectURL: URL(string: "https://golden.invalid")!, anonKey: nil)
        let longLabel = String(repeating: "가", count: 70)
        let w5 = AILimitWindow.fiveHour, w7 = AILimitWindow.weekly
        let scenarios: [(String, [ProviderSpec], String?, [AILimitProvider], Double)] = [
            ("values-two-providers", [
                ProviderSpec(provider: .claude, plan: "max", fingerprint: nil, windows: [
                    WindowSpec(window: w5, used: 27, resets: 1_793_408_400, observed: 1_793_390_000.25),
                    WindowSpec(window: w7, used: 61.5, resets: 1_793_664_000, observed: 1_793_390_000.25)]),
                ProviderSpec(provider: .codex, plan: "plus", fingerprint: "0123456789abcdef", windows: [
                    WindowSpec(window: w7, used: 40, resets: nil, observed: 1_793_390_001.75)]),
            ], "  DESKTOP-SYNTH1 \n", [], 1_793_390_100),
            ("clear-codex-keep-claude", [
                ProviderSpec(provider: .claude, plan: nil, fingerprint: nil, windows: [WindowSpec(window: w5, used: 5, resets: nil, observed: 1_793_390_000)]),
            ], nil, [.codex], 1_793_390_100.9),
            ("clear-dedupe", [
                ProviderSpec(provider: .claude, plan: "pro", fingerprint: nil, windows: [WindowSpec(window: w5, used: 5, resets: 1_793_400_000.5, observed: 1_793_390_000)]),
            ], "PC", [.claude, .codex, .codex, .antigravity], 1_793_390_100),
            ("clear-only", [], "PC", [.codex, .claude], 1_793_390_200),
            ("clamp-and-nan", [
                ProviderSpec(provider: .claude, plan: String(repeating: "p", count: 33), fingerprint: nil, windows: [
                    WindowSpec(window: w5, used: 100.0000001, resets: 1_793_408_400, observed: 1_793_390_000),
                    WindowSpec(window: w7, used: -2, resets: nil, observed: 1_793_390_000)]),
                ProviderSpec(provider: .codex, plan: nil, fingerprint: nil, windows: [WindowSpec(window: w5, used: .nan, resets: nil, observed: 1_793_390_000)]),
            ], longLabel, [], 1_793_390_000),
            ("unlinked-and-empty", [ProviderSpec(provider: .codex, plan: "plus", fingerprint: nil, windows: [])], "PC", [], 1_793_390_000),
            ("blank-label", [
                ProviderSpec(provider: .codex, plan: nil, fingerprint: nil, windows: [WindowSpec(window: w5, used: 0, resets: nil, observed: 1_793_390_000.999)]),
            ], " \t ", [], 1_793_390_000),
        ]
        var cases: [GoldenJSON] = []
        for (id, specs, label, cleared, clearedAt) in scenarios {
            let bundle = Self.bundle(specs)
            // `upsertAILimits` 의 본문 조립 그대로(그 함수는 HTTP 를 보내므로 같은 두 줄을 여기서 부른다).
            var valueRows: [AILimitUpsertRow] = []
            for snapshot in bundle.visibleProviders {
                if let row = await service.aiLimitRow(userID: Self.user, deviceID: Self.device, deviceLabel: label, snapshot: snapshot) { valueRows.append(row) }
            }
            let taken = Set(valueRows.map(\.provider))
            var seen = Set<AILimitProvider>()
            var clearingRows: [AILimitUpsertRow] = []
            for provider in cleared where !taken.contains(provider.rawValue) && seen.insert(provider).inserted {
                clearingRows.append(await service.aiLimitClearingRow(
                    userID: Self.user, deviceID: Self.device, deviceLabel: label, provider: provider, observedAt: Date(timeIntervalSince1970: clearedAt)))
            }
            let rows = valueRows + clearingRows
            cases.append([
                "id": .string("rows-\(id)"), "kind": "rows", "userID": .string(Self.user), "deviceID": .string(Self.device),
                "deviceLabel": Self.opt(label), "bundle": Self.bundleJSON(specs), "clearedProviders": .array(cleared.map { .string($0.rawValue) }),
                "clearedAtBits": .bits(clearedAt), "rows": .array(rows.map(Self.rowJSON)), "encoded": try Self.encodedShape(rows),
                "fingerprint": .string(AILimitUploadLedger.fingerprint(bundle)),
            ])
        }
        for (i, raw) in ([nil, "win:abc", "  win:abc \n", "", "   ", String(repeating: "x", count: 128), String(repeating: "x", count: 129)] as [String?]).enumerated() {
            let row = AILimitPrefsUpsertRow(userId: Self.user, mainDeviceId: AILimitMainDeviceIDContract.normalized(raw))
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            guard let object = (try JSONSerialization.jsonObject(with: encoder.encode([row])) as? [[String: Any]])?.first else { throw GoldenJSONError("prefs 본문이 아니다") }
            cases.append([
                "id": .string("prefs-\(i)"), "kind": "prefs", "raw": Self.opt(raw), "mainDeviceID": Self.opt(row.mainDeviceId),
                "keys": .array(object.keys.sorted().map(GoldenJSON.string)),
                "nullKeys": .array(object.filter { $0.value is NSNull }.keys.sorted().map(GoldenJSON.string)),
            ])
        }
        for (i, value) in ([0, 12.3456, 0.0625, 0.0005, 0.0015, -0.0001, 100, 99.9995, 33.3333333] as [Double]).enumerated() {
            cases.append(["id": .string("percent-text-\(i)"), "kind": "percentText", "valueBits": .bits(value), "text": .string(String(format: "%.3f", value))])
        }
        for (i, value) in ([-1, 0, 50.5, 100, 100.0000001, .infinity, -.infinity, .nan] as [Double]).enumerated() {
            cases.append(["id": .string("percent-\(i)"), "kind": "percent", "valueBits": .bits(value), "outBits": Self.optBits(SupabaseWorkService.aiLimitPercent(value))])
        }
        for (i, t) in ([0, 899.999, 900, 1_793_390_000.25, -0.5, -900.5] as [Double]).enumerated() {
            cases.append(["id": .string("bucket-\(i)"), "kind": "bucket", "secondsBits": .bits(t), "bucket": .int(AILimitUploadLedger.observedBucket(Date(timeIntervalSince1970: t)))])
        }
        goldenEmit(GoldenFile(
            golden: "token-usage/limits/upload",
            equivalence: .bit,
            swiftSources: ["Sources/CheckCore/SupabaseWorkServiceAILimits.swift", "Sources/check/WorkTimerStoreAILimits.swift"],
            spec: [
                "path": .string(SupabaseWorkService.aiLimitsPath),
                "method": "POST",
                "onConflict": .string(SupabaseWorkService.aiLimitsConflictKey),
                "prefer": "resolution=merge-duplicates,return=minimal",
                "prefsPath": .string(SupabaseWorkService.aiLimitsPrefsPath),
                "prefsOnConflict": .string(SupabaseWorkService.aiLimitsPrefsConflictKey),
                "rowKeys": .array(AILimitUpsertRow.CodingKeys.allCases.map { .string($0.rawValue) }),
                "deviceId": "Windows 기기 id 는 win:… (합성). account_fingerprint 는 본문에 없다.",
            ],
            cases: cases
        ))
    }
}
