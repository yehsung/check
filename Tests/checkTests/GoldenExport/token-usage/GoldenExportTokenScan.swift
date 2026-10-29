import CheckGoldenSupport
import Foundation
import Testing
@testable import CheckCore

// W2-h1 토큰 스캐너 골든(Windows 이식 — xplat-w1/briefs/tokens.md §5).
// 합성 홈 계획(SH/scan/plan.json)을 사례마다 새 임시 홈에 단계별로 깐다(put = 조각 복사 · append = 덧붙이기 · delete, 그때마다
// mtime 을 표대로 찍는다). 단계마다 캐시를 이어 가며 TokenUsageIncrementalScanner.update 를 부르고 월·일·UTC 일 합 · 통계 ·
// 파일 진행 상태 · Claude 엔트리(SHA-256 앞 16바이트 키)를 남긴다. fresh 단계는 같은 홈을 빈 캐시로 다시 스캔해 증분과 같아야 한다.
// Kotlin `TokenScanGoldenTest` 가 이 골든의 ops 를 그대로 되풀이해 비트 비교한다. 경로는 임시 홈 기준 상대 경로만(절대 경로 0).
// 임시 홈에는 Orca·안티그래비티 폴더가 없다 → Swift 쪽도 홈 하나·안티그래비티 0 (Windows 판의 범위와 같다).
@Suite("GoldenExport token-usage — 토큰 스캐너(증분 · 포크 복사 · .zst 동결 · CRLF · 월 넘김)")
struct GoldenExportTokenScan {
    static let fixtureDir = "multiplatform/feature/desktop/src/desktopTest/resources/synthetic-home/scan"

    struct Plan: Decodable { var cases: [PlanCase] }
    struct PlanCase: Decodable { var id: String; var note: String; var steps: [PlanStep] }
    struct PlanStep: Decodable { var now: Int; var fresh: Bool; var ops: [PlanOp] }
    struct PlanOp: Decodable { var op: String; var to: String; var from: String?; var mtime: Int? }

    static func intMap(_ m: [String: Int]) -> GoldenJSON { .object(m.mapValues { .int($0) }) }

    static func usageJSON(_ u: TokenUsageMonthly) -> GoldenJSON {
        [
            "month": .string(u.month),
            "claudeInput": .int(u.claudeInput), "claudeOutput": .int(u.claudeOutput),
            "claudeCacheRead": .int(u.claudeCacheRead), "claudeCacheCreation": .int(u.claudeCacheCreation),
            "codexInput": .int(u.codexInput), "codexOutput": .int(u.codexOutput), "codexCacheRead": .int(u.codexCacheRead),
            "antigravityInput": .int(u.antigravityInput), "antigravityOutput": .int(u.antigravityOutput),
            "antigravityThinking": .int(u.antigravityThinking), "antigravityCacheRead": .int(u.antigravityCacheRead),
            "todayTotal": .int(u.todayTotal), "todayDate": .string(u.todayDate),
            "claudeDaily": intMap(u.claudeDaily), "codexDaily": intMap(u.codexDaily), "codexDailyUTC": intMap(u.codexDailyUTC),
            "antigravityDaily": intMap(u.antigravityDaily),
            "windowStart": .string(u.windowStart), "claudeCompleteFrom": .string(u.claudeCompleteFrom),
            "total": .int(u.total),
        ]
    }

    static func statsJSON(_ s: TokenUsageIncrementalScanner.Stats) -> GoldenJSON {
        [
            "claudeFilesStatted": .int(s.claudeFilesStatted), "claudeFilesRead": .int(s.claudeFilesRead),
            "claudeBytesRead": .int(s.claudeBytesRead),
            "codexFilesStatted": .int(s.codexFilesStatted), "codexFilesRead": .int(s.codexFilesRead),
            "codexBytesRead": .int(s.codexBytesRead), "codexForkCopyEvents": .int(s.codexForkCopyEvents),
            "entriesChanged": .bool(s.entriesChanged), "statesChanged": .bool(s.statesChanged),
        ]
    }

    static func opJSON(_ op: PlanOp) -> GoldenJSON {
        var o: [String: GoldenJSON] = ["op": .string(op.op), "to": .string(op.to)]
        if let from = op.from { o["from"] = .string(from) }
        if let mtime = op.mtime { o["mtime"] = .int(mtime) }
        return .object(o)
    }

    static func apply(_ op: PlanOp, home: URL, fixtures: URL) throws {
        let fm = FileManager.default
        let target = home.appendingPathComponent(op.to)
        switch op.op {
        case "delete":
            try fm.removeItem(at: target)
            return
        case "put", "append":
            let data = try Data(contentsOf: fixtures.appendingPathComponent(op.from!))
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            if op.op == "put" || !fm.fileExists(atPath: target.path) {
                try data.write(to: target)
            } else {
                let handle = try FileHandle(forWritingTo: target)
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            }
        default:
            Issue.record("모르는 op \(op.op)")
        }
        if let mtime = op.mtime {
            try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: TimeInterval(mtime))], ofItemAtPath: target.path)
        }
    }

    @Test("합성 홈 14사례 — 단계별 증분 스캔 결과")
    func scanner() throws {
        let fixtures = GoldenRepo.url(Self.fixtureDir)
        let plan = try JSONDecoder().decode(Plan.self, from: Data(contentsOf: fixtures.appendingPathComponent("plan.json")))
        let fm = FileManager.default
        let runID = "token-scan-golden-\(UUID().uuidString)"
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent(runID, isDirectory: true)
        defer { try? fm.removeItem(at: base) }
        var cases: [GoldenJSON] = []
        for c in plan.cases {
            let home = base.appendingPathComponent(c.id, isDirectory: true).appendingPathComponent("home", isDirectory: true)
            try fm.createDirectory(at: home, withIntermediateDirectories: true)
            // 임시 폴더는 /var ↔ /private/var 별칭이 섞일 수 있다 — 접두 대신 '/<실행 id>/<사례>/home/' 표지 뒤를 상대 경로로.
            let marker = "/\(runID)/\(c.id)/home/"
            func rel(_ path: String) -> String {
                guard let r = path.range(of: marker) else {
                    Issue.record("\(c.id): 홈 밖 경로가 상태에 있다")
                    return "<홈 밖>"
                }
                return String(path[r.upperBound...])
            }
            let codexHome = home.appendingPathComponent(".codex", isDirectory: true)
            var cache = TokenUsageCache()
            var steps: [GoldenJSON] = []
            for s in c.steps {
                for op in s.ops { try Self.apply(op, home: home, fixtures: fixtures) }
                let now = Date(timeIntervalSince1970: TimeInterval(s.now))
                let r = TokenUsageIncrementalScanner.update(cache, homeDirectory: home, codexHome: codexHome, now: now)
                cache = r.cache
                let claudeFiles: [GoldenJSON] = cache.claudeFileStates.map { (rel($0.key), $0.value) }.sorted { $0.0 < $1.0 }.map {
                    [.string($0.0), .int($0.1.size), .int($0.1.mtimeMicros), .int($0.1.consumedOffset)]
                }
                let entries: [GoldenJSON] = cache.claudeEntries.map { ($0.key.hex, $0.value) }.sorted { $0.0 < $1.0 }.map {
                    [.string($0.0), .int($0.1.ts14), .int($0.1.input), .int($0.1.output), .int($0.1.cacheRead), .int($0.1.cacheCreation)]
                }
                let codexFiles: [GoldenJSON] = cache.codexFileStates.map { (rel($0.key), $0.value) }.sorted { $0.0 < $1.0 }.map {
                    let p = $0.1
                    return [.string($0.0), .int(p.size), .int(p.mtimeMicros), .int(p.consumedOffset),
                            .int(p.prevInput), .int(p.prevOutput), .int(p.prevCached), .string(p.monthKey),
                            .int(p.monthInput), .int(p.monthOutput), .int(p.monthCached), Self.intMap(p.dayContrib),
                            .int(p.forkCopyDeadlineMicros), Self.intMap(p.dayContribUTC)]
                }
                if s.fresh {
                    let fresh = TokenUsageIncrementalScanner.update(TokenUsageCache(), homeDirectory: home, codexHome: codexHome, now: now)
                    #expect(fresh.usage == r.usage, "\(c.id): 증분 스캔과 처음부터 스캔이 다르다")
                }
                steps.append([
                    "now": .int(s.now), "fresh": .bool(s.fresh), "ops": .array(s.ops.map(Self.opJSON)),
                    "usage": Self.usageJSON(r.usage), "stats": Self.statsJSON(r.stats),
                    "claudeFiles": .array(claudeFiles), "claudeEntries": .array(entries), "codexFiles": .array(codexFiles),
                ])
            }
            cases.append(["id": .string(c.id), "note": .string(c.note), "steps": .array(steps)])
        }
        #expect(cases.count == 14)
        goldenEmit(GoldenFile(
            golden: "token-usage/scan/scanner",
            equivalence: .bit,
            swiftSources: ["Sources/CheckCore/CheckTokenUsage.swift"],
            platformSensitive: false,
            spec: [
                "fixtures": .string("\(Self.fixtureDir)/plan.json 의 단계(put·append·delete + mtime 초) — 조각 파일은 같은 폴더, 바이트 그대로(-text)"),
                "scanner": "TokenUsageIncrementalScanner.update(cache, homeDirectory: 임시 홈, codexHome: 임시 홈/.codex, now) — 단계마다 캐시를 잇는다",
                "claudeEntries": "[ClaudeEntryKey.hex(= SHA-256(\"id\\0requestId\") 앞 16바이트), ts14, input, output, cacheRead, cacheCreation] 16진 순",
                "codexFiles": "[홈 기준 상대 경로, size, mtimeMicros, consumedOffset, prevInput, prevOutput, prevCached, monthKey, monthInput, monthOutput, monthCached, dayContrib, forkCopyDeadlineMicros, dayContribUTC]",
                "fresh": "true 인 단계는 빈 캐시 전체 스캔 usage 가 증분 usage 와 같다(Swift #expect)",
                "zone": "KST 고정 +9 · UTC — tzdata 무관",
            ],
            cases: cases
        ))
    }
}
