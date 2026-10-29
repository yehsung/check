// 원본: Sources/check/WorkTimerStoreSync.swift(2425-2518 일별 순수 계산 · 927-933 accountUploadKey · 1053-1060 진단 도장) ·
//       Sources/CheckCore/SupabaseWorkServiceMacOnly.swift(621-735 월·하트비트·일별 요청) · SupabaseWorkModels.swift(613-900 본문) ·
//       Sources/CheckCore/CheckTokenUsageDiagnostics.swift(compute) · Sources/CheckCore/CheckCodexAccountUsage.swift(26-100 · 386-445)
//       (골든 생성기 — W2-h3 토큰 업로드·계정·진단)
import CheckGoldenSupport
import Foundation
import Testing
@testable import check
@testable import CheckCore

// W2-h3 골든 넷(Kotlin 은 feature/desktop desktopTest …/tokens/{upload,account,diag} 가 대조한다):
//   · token-usage/upload/daily        TokenUsageDailyUpload.values · changedDays · rows(snake_case 본문, nil 키 생략)
//   · token-usage/upload/requests     월간(진단·계정 유무 · 미로그인 생략 · 안티그래비티) · 일별 배열(키 모양 묶음) · 하트비트 —
//                                     방법 · 경로 · 쿼리 · Prefer · 본문(가짜 URLProtocol 이 받은 바이트 그대로)
//   · token-usage/upload/diagnostics  CodexUsageDiagnosticsScanner.compute(합성 홈 SH/upload/diag-*, appBuild 1)
//   · token-usage/upload/account      CodexAccountUsageProbe.parse · requestLines · accountUploadKey · 진단 도장 · monthTotal
// 옛 표 token_usage_monthly 요청(upsertLegacyTokenUsage · fetchLegacyTokenUsageTotal)은 Windows 가 옮기지 않으므로 싣지 않는다(W-3 #11).

@Suite("GoldenExport token-usage — 업로드·계정·진단(upload/*)", .serialized)
struct GoldenExportTokenUpload {
    static let sources = [
        "Sources/check/WorkTimerStoreSync.swift",
        "Sources/CheckCore/SupabaseWorkServiceMacOnly.swift",
        "Sources/CheckCore/SupabaseWorkModels.swift",
        "Sources/CheckCore/CheckTokenUsageDiagnostics.swift",
        "Sources/CheckCore/CheckCodexAccountUsage.swift",
    ]

    static func gj(_ any: Any) -> GoldenJSON {
        if any is NSNull { return .null }
        if let s = any as? String { return .string(s) }
        if let n = any as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return .bool(n.boolValue) }
            return .int(n.intValue)
        }
        if let a = any as? [Any] { return .array(a.map { gj($0) }) }
        if let d = any as? [String: Any] { return .object(d.mapValues { gj($0) }) }
        return .string("\(any)")
    }

    static func gj(data: Data) -> GoldenJSON {
        guard !data.isEmpty, let any = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { return .null }
        return gj(any)
    }

    static func gj(json: String) -> GoldenJSON { gj(data: Data(json.utf8)) }

    static func opt(_ x: Int?) -> GoldenJSON { x.map { .int($0) } ?? .null }

    static func valueJSON(_ v: TokenUsageDailyValue) -> GoldenJSON {
        ["claude": opt(v.claude), "codex": opt(v.codex), "codexUTC": opt(v.codexUTC), "codexAccount": opt(v.codexAccount),
         "antigravity": opt(v.antigravity)]
    }

    static func intMap(_ m: [String: Int]) -> GoldenJSON { .object(m.mapValues { .int($0) }) }

    // MARK: daily

    @Test("upload/daily — TokenUsageDailyUpload.values · changedDays · rows")
    func daily() throws {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        struct Case { let id: String; let usage: String; let buckets: [String: Int]?; let last: [String: TokenUsageDailyValue] }
        let cases: [Case] = [
            Case(id: "window-mixed",
                 usage: #"{"month":"2026-10","windowStart":"2026-08-10","claudeCompleteFrom":"2026-09-01","claudeInput":100,"#
                    + #""claudeDaily":{"2026-08-05":5,"2026-08-20":10,"2026-09-15":20,"2026-10-01":30,"2026-10-04":-3},"#
                    + #""codexDaily":{"2026-10-01":7,"2026-10-03":9},"codexDailyUTC":{"2026-09-30":3,"2026-10-01":6,"2026-10-03":8},"#
                    + #""antigravityDaily":{"2026-10-03":4,"2026-09-20":2}}"#,
                 buckets: ["2026-07-01": 99, "2026-09-15": 50, "2026-10-02": 0, "2026-10-03": -1],
                 last: ["2026-10-01": TokenUsageDailyValue(claude: 30, codex: 7, codexUTC: 6, codexAccount: nil, antigravity: nil),
                        "2026-09-15": TokenUsageDailyValue(claude: 20, codex: nil, codexUTC: nil, codexAccount: 49, antigravity: nil),
                        "2026-08-30": TokenUsageDailyValue(claude: 1, codex: nil, codexUTC: nil, codexAccount: nil, antigravity: nil)]),
            Case(id: "old-snapshot",
                 usage: #"{"month":"2026-10","claudeDaily":{"2026-09-28":5,"2026-10-02":11},"codexDaily":{"2026-10-02":3}}"#,
                 buckets: nil, last: [:]),
            Case(id: "account-only",
                 usage: #"{"month":"2026-10","windowStart":"2026-08-07"}"#,
                 buckets: ["2026-10-05": 1234, "2026-08-01": 5], last: [:]),
            Case(id: "empty-usage", usage: #"{"month":"2026-10"}"#, buckets: nil, last: [:]),
        ]
        var out: [GoldenJSON] = []
        for c in cases {
            let usage = try JSONDecoder().decode(TokenUsageMonthly.self, from: Data(c.usage.utf8))
            let account = c.buckets.map { CodexAccountUsage(fetchedAt: Date(timeIntervalSince1970: 1_793_322_123), lifetimeTokens: 1, buckets: $0) }
            let values = TokenUsageDailyUpload.values(usage: usage, account: account)
            let changed = TokenUsageDailyUpload.changedDays(current: values, lastUploaded: c.last)
            let rows = TokenUsageDailyUpload.rows(userID: "u-1", deviceID: "win:dev-1", days: changed, values: values)
            let accountJSON: GoldenJSON = c.buckets.map { b -> GoldenJSON in ["buckets": Self.intMap(b)] } ?? .null
            out.append([
                "id": .string(c.id),
                "usage": Self.gj(json: c.usage),
                "account": accountJSON,
                "lastUploaded": .object(c.last.mapValues { Self.valueJSON($0) }),
                "values": .object(values.mapValues { Self.valueJSON($0) }),
                "changedDays": .array(changed.map { .string($0) }),
                "rows": Self.gj(data: try encoder.encode(rows)),
            ])
        }
        goldenEmit(GoldenFile(
            golden: "token-usage/upload/daily",
            equivalence: .bit,
            swiftSources: Self.sources,
            spec: [
                "values": "TokenUsageDailyUpload.values(usage:account:) — 창(windowStartDay) 안 날짜별 값. null = 모른다(본문 키 생략).",
                "changedDays": "changedDays(current:lastUploaded:) — 장부와 다른 날, 오름차순.",
                "rows": "rows(userID: \"u-1\", deviceID: \"win:dev-1\", days: changedDays, values:) 를 convertToSnakeCase 로 인코드(nil 키 없음).",
                "account": "CodexAccountUsage 는 buckets 만 값에 든다(fetchedAt·lifetime 은 일별 값과 무관).",
            ],
            cases: out
        ))
    }

    // MARK: requests

    static let fetchedAtEpoch = 1_793_322_123          // 2026-10-30T01:02:03Z
    static let scannedAtEpoch = 1_793_325_600          // 2026-10-30T02:00:00Z

    static let usageJSON = #"{"month":"2026-10","claudeInput":1000,"claudeOutput":200,"claudeCacheRead":3000,"claudeCacheCreation":400,"#
        + #""codexInput":500,"codexOutput":60,"codexCacheRead":70,"todayTotal":123,"todayDate":"2026-10-30"}"#
    static let usageAntigravityJSON = #"{"month":"2026-10","claudeInput":10,"codexInput":5,"antigravityInput":1,"antigravityOutput":2,"#
        + #""antigravityThinking":3,"antigravityCacheRead":4,"todayTotal":0,"todayDate":"2026-10-30"}"#

    static func diag() -> CodexUsageDiagnostics {
        CodexUsageDiagnostics(
            filesTotal: 1, filesMonth: 2, eventsMonth: 3, maxDelta: 4, maxDeltaGapSeconds: 5, bigDeltaCount: 6, bigDeltaTotal: 7,
            bigGapMedianSeconds: 8, carryFiles: 9, carryTotal: 10, dupEvents: 11, dupTokens: 12, finalSum: 13, dedupTotal: 14,
            legacyTotal: 15, drops: 16, topFile: 17, appBuild: 1, forkFiles: 18, forkCopyTokens: 19)
    }

    static func diagJSON(_ d: CodexUsageDiagnostics) -> GoldenJSON {
        ["filesTotal": .int(d.filesTotal), "filesMonth": .int(d.filesMonth), "eventsMonth": .int(d.eventsMonth),
         "maxDelta": .int(d.maxDelta), "maxDeltaGapSeconds": .int(d.maxDeltaGapSeconds), "bigDeltaCount": .int(d.bigDeltaCount),
         "bigDeltaTotal": .int(d.bigDeltaTotal), "bigGapMedianSeconds": .int(d.bigGapMedianSeconds), "carryFiles": .int(d.carryFiles),
         "carryTotal": .int(d.carryTotal), "dupEvents": .int(d.dupEvents), "dupTokens": .int(d.dupTokens), "finalSum": .int(d.finalSum),
         "dedupTotal": .int(d.dedupTotal), "legacyTotal": .int(d.legacyTotal), "drops": .int(d.drops), "topFile": .int(d.topFile),
         "appBuild": .int(d.appBuild), "forkFiles": .int(d.forkFiles), "forkCopyTokens": .int(d.forkCopyTokens)]
    }

    static func account() -> CodexAccountUsage {
        CodexAccountUsage(fetchedAt: Date(timeIntervalSince1970: TimeInterval(fetchedAtEpoch)), lifetimeTokens: 987_654,
                          buckets: ["2026-09-29": 11, "2026-10-01": 100, "2026-10-29": 200])
    }

    static func accountJSON(_ a: CodexAccountUsage) -> GoldenJSON {
        ["fetchedAtEpoch": .int(Int(a.fetchedAt.timeIntervalSince1970)), "lifetimeTokens": opt(a.lifetimeTokens), "buckets": intMap(a.buckets)]
    }

    static func rowJSON(_ r: TokenUsageDailyUpsertRow) -> GoldenJSON {
        ["userId": .string(r.userId), "day": .string(r.day), "deviceId": .string(r.deviceId), "claudeTotal": opt(r.claudeTotal),
         "codexTotal": opt(r.codexTotal), "codexUtcTotal": opt(r.codexUtcTotal), "codexAccount": opt(r.codexAccount),
         "antigravityTotal": opt(r.antigravityTotal)]
    }

    @Test("upload/requests — upsertTokenUsage · upsertTokenUsageDaily · sendTokenScanHeartbeat 의 요청")
    func requests() async throws {
        let usage = try JSONDecoder().decode(TokenUsageMonthly.self, from: Data(Self.usageJSON.utf8))
        let usageAG = try JSONDecoder().decode(TokenUsageMonthly.self, from: Data(Self.usageAntigravityJSON.utf8))
        let acct = Self.account()
        var out: [GoldenJSON] = []

        func monthly(_ id: String, _ usageText: String, _ u: TokenUsageMonthly, account: CodexAccountUsage?,
                     status: CodexAccountProbeStatus?, diagnostics: CodexUsageDiagnostics?) async throws {
            let host = "h3-\(id).invalid"
            try await Self.service(host).upsertTokenUsage(accessToken: "access-token", userID: "u-1", usage: u, deviceID: "win:dev-1",
                                                          account: account, accountStatus: status, diagnostics: diagnostics)
            out.append([
                "id": .string(id), "kind": "monthly", "usage": Self.gj(json: usageText),
                "account": account.map { Self.accountJSON($0) } ?? .null, "accountStatus": Self.opt(status?.rawValue),
                "diagnostics": diagnostics.map { Self.diagJSON($0) } ?? .null,
                "requests": .array(GoldenExportTokenUploadRecorder.take(host: host)),
            ])
        }
        try await monthly("monthly-plain", Self.usageJSON, usage, account: nil, status: nil, diagnostics: nil)
        try await monthly("monthly-account-ok-diag", Self.usageJSON, usage, account: acct, status: .ok, diagnostics: Self.diag())
        try await monthly("monthly-not-logged-in", Self.usageJSON, usage, account: acct, status: .notLoggedIn, diagnostics: nil)
        try await monthly("monthly-status-only", Self.usageJSON, usage, account: nil, status: .timeout, diagnostics: nil)
        try await monthly("monthly-account-no-status", Self.usageJSON, usage, account: acct, status: nil, diagnostics: nil)
        try await monthly("monthly-antigravity", Self.usageAntigravityJSON, usageAG, account: nil, status: .codexNotInstalled, diagnostics: Self.diag())

        let rows = [
            TokenUsageDailyUpsertRow(userId: "u-1", day: "2026-10-01", deviceId: "win:dev-1", claudeTotal: 1, codexTotal: 2, codexUtcTotal: 3,
                                     codexAccount: 4, antigravityTotal: 5),
            TokenUsageDailyUpsertRow(userId: "u-1", day: "2026-10-02", deviceId: "win:dev-1", claudeTotal: 10),
            TokenUsageDailyUpsertRow(userId: "u-1", day: "2026-10-03", deviceId: "win:dev-1", claudeTotal: 20, codexTotal: 0),
            TokenUsageDailyUpsertRow(userId: "u-1", day: "2026-10-04", deviceId: "win:dev-1", claudeTotal: 30),
            TokenUsageDailyUpsertRow(userId: "u-1", day: "2026-09-20", deviceId: "win:dev-1", codexAccount: 0),
        ]
        for (id, input) in [("daily-shapes", rows), ("daily-empty", [TokenUsageDailyUpsertRow]())] {
            let host = "h3-\(id).invalid"
            try await Self.service(host).upsertTokenUsageDaily(accessToken: "access-token", rows: input)
            out.append(["id": .string(id), "kind": "daily", "rows": .array(input.map { Self.rowJSON($0) }),
                        "requests": .array(GoldenExportTokenUploadRecorder.take(host: host))])
        }

        let host = "h3-heartbeat.invalid"
        try await Self.service(host).sendTokenScanHeartbeat(accessToken: "access-token", userID: "u-1", month: "2026-10", deviceID: "win:dev-1",
                                                            files: 42, scannedAt: Date(timeIntervalSince1970: TimeInterval(Self.scannedAtEpoch)))
        out.append(["id": "heartbeat", "kind": "heartbeat", "month": "2026-10", "files": 42, "scannedAtEpoch": .int(Self.scannedAtEpoch),
                    "requests": .array(GoldenExportTokenUploadRecorder.take(host: host))])

        goldenEmit(GoldenFile(
            golden: "token-usage/upload/requests",
            equivalence: .bit,
            swiftSources: Self.sources,
            spec: [
                "common": "userID \"u-1\" · deviceID \"win:dev-1\" · accessToken \"access-token\". 요청 = method · path · query([이름, 값]) · prefer · body(받은 JSON).",
                "monthly": "upsertTokenUsage — nil 옵셔널은 키째 빠진다(합성 Encodable). 미로그인(3)이면 계정 스냅샷 네 키를 싣지 않고 status 만.",
                "daily": "upsertTokenUsageDaily — 옵셔널 다섯의 유무 비트(claude 16 · codex 8 · utc 4 · account 2 · antigravity 1) 내림차순 묶음마다 한 요청. 빈 배열이면 0.",
                "heartbeat": "sendTokenScanHeartbeat — 본문은 user_id · month · device_id · last_scan_at · scan_files 다섯뿐(토큰 칸 0).",
                "time": "fetchedAtEpoch·scannedAtEpoch 는 1970 기준 초 — ISO8601DateFormatter 기본(초 단위 UTC 'Z').",
            ],
            cases: out
        ))
    }

    static func service(_ host: String) -> SupabaseWorkService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GoldenExportTokenUploadRecorder.self]
        return SupabaseWorkService(projectURL: URL(string: "http://\(host)")!, anonKey: "anon-test-key",
                                   session: URLSession(configuration: configuration))
    }

    // MARK: diagnostics

    @Test("upload/diagnostics — CodexUsageDiagnosticsScanner.compute(합성 홈)")
    func diagnostics() {
        let base = GoldenRepo.url("multiplatform/feature/desktop/src/desktopTest/resources/synthetic-home/upload")
        var out: [GoldenJSON] = []
        for (id, home, month) in [("basic-oct", "diag-basic", "2026-10"), ("basic-sep", "diag-basic", "2026-09"),
                                  ("fork-dup-oct", "diag-fork-dup", "2026-10"), ("empty", "diag-empty", "2026-10")] {
            let h = base.appendingPathComponent(home, isDirectory: true)
            let d = CodexUsageDiagnosticsScanner.compute(homeDirectory: h, codexHome: h.appendingPathComponent(".codex", isDirectory: true),
                                                         month: month, appBuild: 1)
            out.append(["id": .string(id), "home": .string(home), "month": .string(month), "appBuild": 1, "result": Self.diagJSON(d)])
        }
        goldenEmit(GoldenFile(
            golden: "token-usage/upload/diagnostics",
            equivalence: .bit,
            swiftSources: Self.sources,
            spec: [
                "input": "feature/desktop desktopTest resources synthetic-home/upload/<home>/.codex/{sessions,archived_sessions}/**/rollout-*.jsonl.",
                "compute": "compute(homeDirectory: <home>, codexHome: <home>/.codex, month:, appBuild: 1) — Windows 는 Orca 홈이 없어 루트가 둘뿐.",
            ],
            cases: out
        ))
    }

    // MARK: account

    @Test("upload/account — 프로브 응답 파싱 · 요청 줄 · 계정 키 · 진단 도장 · 월 합")
    @MainActor
    func account() {
        var out: [GoldenJSON] = []
        let parseCases: [(String, [String])] = [
            ("ok-buckets", [
                #"{"id":1,"result":{"userAgent":"x"}}"#,
                #"{"method":"remoteControl/status/changed","params":{}}"#,
                #"{"id":2,"result":{"summary":{"lifetimeTokens":555000},"dailyUsageBuckets":[{"startDate":"2026-10-01","tokens":100},"#
                    + #"{"startDate":"2026-10-01T09:00:00Z","tokens":5},{"startDate":"2026-10-29","tokens":7.9},{"startDate":"2026-08-01","tokens":3},"#
                    + #"{"startDate":"short","tokens":1},{"startDate":"2026-10-02"},{"tokens":4}]}}"#,
            ]),
            ("ok-nulls", [#"{"id":2,"result":{"summary":{"lifetimeTokens":null},"dailyUsageBuckets":null}}"#]),
            ("ok-id-double", [#"{"id":2.0,"result":{}}"#]),
            ("id-string-ignored", [#"{"id":"2","result":{}}"#]),
            ("auth-error", [#"{"id":2,"error":{"code":-32000,"message":"Not AUTHenticated: login required"}}"#]),
            ("other-error", [#"{"id":2,"error":{"code":-32601,"message":"method not found"}}"#]),
            ("result-missing", [#"{"id":2}"#]),
            ("no-response", [#"{"id":1,"result":{}}"#, "not json", ""]),
            ("garbled-then-ok", ["{\"id\":2,\"res", #"  {"id":2,"result":{"summary":{"lifetimeTokens":1}}}  "#]),
        ]
        let fetchedAt = Date(timeIntervalSince1970: TimeInterval(Self.fetchedAtEpoch))
        for (id, lines) in parseCases {
            let result = CodexAccountUsageProbe.parse(lines: lines, fetchedAt: fetchedAt)
            var c: [String: GoldenJSON] = ["id": .string("parse-\(id)"), "kind": "parse", "lines": .array(lines.map { .string($0) }),
                                          "fetchedAtEpoch": .int(Self.fetchedAtEpoch)]
            switch result {
            case .success(let usage):
                c["status"] = 1
                c["lifetimeTokens"] = Self.opt(usage.lifetimeTokens)
                c["buckets"] = Self.intMap(usage.buckets)
                c["confirms"] = .bool(CodexAccountUsageProbe.confirmsToolchain(result))
            case .failure(let failure):
                c["status"] = .int(failure.status.rawValue)
                c["reason"] = .string(failure.reason)
                c["confirms"] = .bool(CodexAccountUsageProbe.confirmsToolchain(result))
            }
            out.append(.object(c))
        }
        for (id, version) in [("plain", "1"), ("quoted", "1.0.\"1\"")] {
            out.append(["id": .string("request-lines-\(id)"), "kind": "requestLines", "appVersion": .string(version),
                        "lines": .array(CodexAccountUsageProbe.requestLines(appVersion: version).map { .string($0) })])
        }
        let acct = Self.account()
        let keyCases: [(String, CodexAccountUsage?, CodexAccountProbeStatus?)] = [
            ("none", nil, nil), ("status-only", nil, .notLoggedIn), ("account-ok", acct, .ok), ("account-nostatus", acct, nil),
            ("lifetime-nil", CodexAccountUsage(fetchedAt: fetchedAt, lifetimeTokens: nil, buckets: [:]), .failed),
        ]
        for (id, a, s) in keyCases {
            out.append(["id": .string("account-key-\(id)"), "kind": "accountKey", "account": a.map { Self.accountJSON($0) } ?? .null,
                        "accountStatus": Self.opt(s?.rawValue), "month": "2026-10",
                        "key": WorkTimerStore.accountUploadKey(account: a, month: "2026-10", status: s).map { .string($0) } ?? .null])
        }
        for (id, epoch) in [("kst-before-midnight", 1_793_285_999), ("kst-midnight", 1_793_286_000), ("utc-evening", 1_793_376_000)] {
            let now = Date(timeIntervalSince1970: TimeInterval(epoch))
            out.append(["id": .string("stamp-\(id)"), "kind": "stamp", "build": 1, "nowEpoch": .int(epoch),
                        "stamp": .string(WorkTimerStore.codexDiagnosticsStamp(build: 1, now: now))])
        }
        for month in ["2026-10", "2026-09", "2026-11"] {
            out.append(["id": .string("month-\(month)"), "kind": "month", "account": Self.accountJSON(acct), "month": .string(month),
                        "monthTotal": .int(acct.monthTotal(month)), "latestBucketDate": acct.latestBucketDate(in: month).map { .string($0) } ?? .null])
        }
        let wide = CodexAccountUsage(fetchedAt: fetchedAt, lifetimeTokens: 1,
                                     buckets: ["2026-08-20": 1, "2026-08-21": 2, "2026-08-22": 3, "2026-10-30": 4, "2025-12-31": 5])
        out.append(["id": "pruned-70d", "kind": "pruned", "account": Self.accountJSON(wide), "result": Self.intMap(wide.pruned().buckets)])
        goldenEmit(GoldenFile(
            golden: "token-usage/upload/account",
            equivalence: .bit,
            swiftSources: Self.sources,
            spec: [
                "parse": "CodexAccountUsageProbe.parse(lines:fetchedAt:) — status 1 = 성공(그때 lifetimeTokens·buckets), 그 밖은 실패 상태 원시값과 reason. confirms = confirmsToolchain.",
                "requestLines": "requestLines(appVersion:) — JSONL 3줄(따옴표는 지운다).",
                "accountKey": "WorkTimerStore.accountUploadKey(account:month:status:) — 월간 변경 게이트의 계정 키.",
                "stamp": "WorkTimerStore.codexDiagnosticsStamp(build:now:) — \"<빌드>:<KST 날짜>\".",
                "month": "CodexAccountUsage.monthTotal · latestBucketDate(in:) — 버킷은 UTC 일자.",
                "pruned": "pruned() — fetchedAt − 70일(UTC 일자) 이전 버킷을 버린다.",
            ],
            cases: out
        ))
    }
}

/// 이 스위트 전용 가짜 URLProtocol — 요청을 host 별로 적고 201 빈 본문을 돌려준다(바깥 연결 0).
final class GoldenExportTokenUploadRecorder: URLProtocol {
    private nonisolated(unsafe) static var log: [String: [GoldenJSON]] = [:]
    private static let lock = NSLock()

    static func take(host: String) -> [GoldenJSON] {
        lock.lock(); defer { lock.unlock() }
        let items = log[host] ?? []
        log[host] = nil
        return items
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buffer, maxLength: buffer.count)
                if n <= 0 { break }
                body.append(buffer, count: n)
            }
            stream.close()
        }
        let url = request.url!
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let entry: GoldenJSON = [
            "method": .string(request.httpMethod ?? ""),
            "path": .string(url.path),
            "query": .array(items.map { .array([.string($0.name), .string($0.value ?? "")]) }),
            "prefer": request.value(forHTTPHeaderField: "Prefer").map { .string($0) } ?? .null,
            "body": GoldenExportTokenUpload.gj(data: body),
        ]
        Self.lock.lock()
        Self.log[url.host ?? "", default: []].append(entry)
        Self.lock.unlock()
        let response = HTTPURLResponse(url: url, statusCode: 201, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
