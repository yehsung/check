import Foundation
import Testing
@testable import check

// MARK: - 증분 경로 vs 전량 재파싱 차분(differential) 조사
//
// 배경: 프로덕션 한 행에 (a) 증분 스캐너가 만든 codex_input 과 (b) 전량 재파싱 진단(dedupTotal)이 함께 실려 있는데
// 무거운 사용자에서 (a)가 (b)의 1.07~2.02배로 벌어졌다(dup_events 0 / drops 0). 이 파일은 "증분 경로가 전량
// 재파싱보다 많이 세는 순간"이 합성 픽스처로 재현되는지를 못 박는다.
//
// 계약(이 파일이 검증하는 불변식): **캐시를 이어 여러 번 돌린 증분 결과는 언제나 같은 순간의 빈 캐시 전량
// 스캔과 같아야 한다.** 어긋나는 첫 순간이 곧 원인이다.
//
// 조사 결과(2026-08-17): append / 부분 라인 / 1MB 청크 경계 / stat-read 경합 / 절단 / mtime 역행은 전부 일치했다.
// **갈리는 유일한 순간은 rollout 파일이 그 경로에서 사라질 때다**(삭제 · 다른 경로로 이동). totals() 가 캐시에 남은
// monthContribTotal 을 계속 더하기 때문이고, 파일이 새 경로로 옮겨지면 옛 키와 새 키가 함께 더해져 **정확히 2배**가 된다.
// 실사용 방아쇠: Codex CLI 가 오래된 rollout 을 압축하고(`codex.rollout_compression.*`) 세션을
// `~/.codex/archived_sessions` 로 옮긴다(codex-cli 0.144.1 바이너리 확인) — 둘 다 sessions/ 에서 그 파일을 없앤다.
// 수정은 scanCodex 끝의 "사라진 파일 정리"다(v0.2.31 로는 고쳐지지 않았다 — 스키마 승격은 1회 청소일 뿐 재발한다).
//
// 픽스처는 임시 홈에 ~/.codex/sessions/**/rollout-*.jsonl 을 직접 쓰고 mtime 을 조작해
// 실제 순회·이어읽기·무변경 판정 경로를 그대로 태운다.
//
// 왜 퍼저까지 두는가: 결정적 시나리오만으로는 놓친다. 실제로 "헤더만 있는 갓 만든 rollout 을 한 번 스캔한 뒤
// 첫 이벤트가 붙는" 순서는 시나리오 1이 못 만들었고(같은 단계에서 둘을 함께 썼다) 퍼저만 잡아냈다(뮤테이션 실증).

private let divNow = Date(timeIntervalSince1970: 1_784_000_000)   // KST 2026-07-14 12:33:20 → 월 "2026-07"

private func divISO(_ date: Date) -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    f.timeZone = TimeZone(identifier: "UTC")
    return f.string(from: date)
}

private func divTempHome() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("check-codex-div-\(UUID().uuidString)", isDirectory: true)
}

private func divRollout(_ home: URL, _ path: String) -> URL {
    home.appendingPathComponent(".codex/sessions/\(path)", isDirectory: false)
}

/// token_count 라인 한 줄(개행 미포함). cum = input + output 이 델타의 기준이다.
private func divEvent(cum: Int, at date: Date) -> String {
    "{\"timestamp\":\"\(divISO(date))\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\","
    + "\"info\":{\"total_token_usage\":{\"input_tokens\":\(cum),\"cached_input_tokens\":0,"
    + "\"output_tokens\":0,\"total_tokens\":\(cum)}}}}"
}

/// token_count 가 아닌 잡음 라인(세션 헤더/사용자 메시지 자리) — 프리체크에서 걸러진다.
private func divNoise(_ n: Int) -> String {
    "{\"type\":\"response_item\",\"payload\":{\"type\":\"message\",\"seq\":\(n)}}"
}

private func divAppend(_ text: String, to url: URL, mtime: Date) {
    try? FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    if FileManager.default.fileExists(atPath: url.path) {
        if let h = try? FileHandle(forWritingTo: url) {
            _ = try? h.seekToEnd()
            try? h.write(contentsOf: Data(text.utf8))
            try? h.close()
        }
    } else {
        try? Data(text.utf8).write(to: url)
    }
    try? FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: url.path)
}

/// 증분(캐시 이어받기) 값과 같은 순간의 전량 재파싱 값을 나란히 얻는다.
private struct DivProbe {
    var incremental: Int
    var full: Int
    var cache: TokenUsageCache
    var diverged: Bool { incremental != full }
}

private func probe(_ cache: TokenUsageCache, home: URL, now: Date = divNow) -> DivProbe {
    let inc = TokenUsageIncrementalScanner.update(cache, homeDirectory: home, now: now)
    let full = TokenUsageIncrementalScanner.update(TokenUsageCache(), homeDirectory: home, now: now)
    return DivProbe(incremental: inc.usage.codexInput, full: full.usage.codexInput, cache: inc.cache)
}

// MARK: 1) append-only 다단계 성장 — 증분과 전량은 매 단계 일치해야 한다

@Test
func incrementalMatchesFullParseAcrossManyAppendSteps() {
    let home = divTempHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let base = divNow.addingTimeInterval(-6 * 86_400)
    // 3개 세션 파일이 서로 다른 리듬으로 자란다(실사용에 가깝게 이월 누적치에서 시작).
    let files = [
        (divRollout(home, "2026/07/08/rollout-2026-07-08T00-00-00-aaaa.jsonl"), 665_000_000),
        (divRollout(home, "2026/07/09/rollout-2026-07-09T00-00-00-bbbb.jsonl"), 12_345),
        (divRollout(home, "2026/07/10/rollout-2026-07-10T00-00-00-cccc.jsonl"), 420_000_000)
    ]
    var cum = files.map { $0.1 }
    var cache = TokenUsageCache()
    var firstDivergence: String?

    for step in 0..<24 {
        for (i, f) in files.enumerated() {
            // 매 단계마다 파일 하나씩 걸러 성장시킨다(무변경 판정 경로도 함께 태운다).
            guard (step + i) % 2 == 0 else { continue }
            var chunk = ""
            if step == 0 { chunk += divNoise(i) + "\n" }              // 세션 헤더 먼저(토큰 이벤트 없음)
            cum[i] += 1_000 * (i + 1) * (step + 1)
            chunk += divEvent(cum: cum[i], at: base.addingTimeInterval(Double(step) * 3600)) + "\n"
            divAppend(chunk, to: f.0, mtime: base.addingTimeInterval(Double(step) * 3600 + 60))
        }
        let p = probe(cache, home: home)
        cache = p.cache
        if p.diverged, firstDivergence == nil {
            firstDivergence = "step \(step): incremental=\(p.incremental) full=\(p.full)"
        }
    }
    #expect(firstDivergence == nil, "\(firstDivergence ?? "")")
}

// MARK: 2) 스캔 사이에 "개행 없는 부분 라인"이 남는다 — Codex 가 실시간으로 쓰는 실제 모양

@Test
func incrementalMatchesFullParseWithPartialTrailingLines() {
    let home = divTempHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let url = divRollout(home, "2026/07/08/rollout-2026-07-08T00-00-00-dddd.jsonl")
    let base = divNow.addingTimeInterval(-5 * 86_400)
    var cache = TokenUsageCache()
    var cum = 100_000_000
    var firstDivergence: String?

    for step in 0..<12 {
        cum += 5_000
        let line = divEvent(cum: cum, at: base.addingTimeInterval(Double(step) * 600))
        // 라인을 반으로 쪼개 앞부분만 쓴 상태에서 한 번 스캔 → 뒷부분 + 개행을 쓰고 다시 스캔.
        let mid = line.index(line.startIndex, offsetBy: line.count / 2)
        divAppend(String(line[line.startIndex..<mid]), to: url,
                  mtime: base.addingTimeInterval(Double(step) * 600 + 10))
        var p = probe(cache, home: home)
        cache = p.cache
        if p.diverged, firstDivergence == nil {
            firstDivergence = "partial step \(step): inc=\(p.incremental) full=\(p.full)"
        }
        divAppend(String(line[mid...]) + "\n", to: url,
                  mtime: base.addingTimeInterval(Double(step) * 600 + 20))
        p = probe(cache, home: home)
        cache = p.cache
        if p.diverged, firstDivergence == nil {
            firstDivergence = "complete step \(step): inc=\(p.incremental) full=\(p.full)"
        }
    }
    #expect(firstDivergence == nil, "\(firstDivergence ?? "")")
}

// MARK: 3) 1MB 청크 경계를 걸치는 거대 라인(툴 출력) 사이의 이어읽기

@Test
func incrementalMatchesFullParseAcrossChunkBoundary() {
    let home = divTempHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let url = divRollout(home, "2026/07/08/rollout-2026-07-08T00-00-00-eeee.jsonl")
    let base = divNow.addingTimeInterval(-4 * 86_400)
    var cache = TokenUsageCache()
    var cum = 7_000_000

    // 1MB 를 넘기는 잡음 라인 하나(청크 경계 carry 경로) → 이벤트 → 또 잡음 → 이벤트.
    let fat = "{\"type\":\"response_item\",\"payload\":{\"type\":\"message\",\"blob\":\""
        + String(repeating: "x", count: 1_200_000) + "\"}}"
    for step in 0..<4 {
        cum += 250_000
        divAppend(fat + "\n" + divEvent(cum: cum, at: base.addingTimeInterval(Double(step) * 900)) + "\n",
                  to: url, mtime: base.addingTimeInterval(Double(step) * 900 + 5))
        let p = probe(cache, home: home)
        cache = p.cache
        #expect(p.incremental == p.full, "chunk step \(step): inc=\(p.incremental) full=\(p.full)")
    }
}

// MARK: 4) stat 과 read 사이에 파일이 자란다(경합) — 캐시엔 낡은 size/mtime + 앞선 consumedOffset 이 남는다

@Test
func incrementalMatchesFullParseWhenFileGrowsBetweenStatAndRead() {
    let home = divTempHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let url = divRollout(home, "2026/07/08/rollout-2026-07-08T00-00-00-ffff.jsonl")
    let base = divNow.addingTimeInterval(-3 * 86_400)

    divAppend(divEvent(cum: 500_000, at: base) + "\n" + divEvent(cum: 600_000, at: base) + "\n",
              to: url, mtime: base.addingTimeInterval(10))
    var cache = probe(TokenUsageCache(), home: home).cache

    // 경합 모사: 이번 스캔의 stat 이 본 size/mtime 은 읽기 전 값이었다 — 캐시의 size/mtime 만 과거로 되돌린다
    // (consumedOffset 은 EOF 까지 읽은 값 그대로). 실제로 파일이 스캔 도중 자랐을 때 남는 상태와 같은 모양.
    let path = url.path
    if let p = cache.codexFileStates[path] {
        cache.codexFileStates[path] = CodexFileProgress(
            size: max(0, p.size - 120), mtimeMicros: p.mtimeMicros - 5_000_000,
            consumedOffset: p.consumedOffset, prevCumulative: p.prevCumulative,
            monthKey: p.monthKey, monthContribTotal: p.monthContribTotal,
            dayKey: p.dayKey, dayContribTotal: p.dayContribTotal
        )
    }
    divAppend(divEvent(cum: 900_000, at: base.addingTimeInterval(60)) + "\n",
              to: url, mtime: base.addingTimeInterval(70))
    let p = probe(cache, home: home)
    #expect(p.incremental == p.full, "race: inc=\(p.incremental) full=\(p.full)")
}

// MARK: 5) 파일이 사라진다(삭제·이동) — 캐시에 남은 기여가 계속 더해지는가

@Test
func cacheKeepsContributionOfVanishedFile() {
    let home = divTempHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let a = divRollout(home, "2026/07/08/rollout-2026-07-08T00-00-00-1111.jsonl")
    let b = divRollout(home, "2026/07/09/rollout-2026-07-09T00-00-00-2222.jsonl")
    let base = divNow.addingTimeInterval(-3 * 86_400)
    divAppend(divEvent(cum: 1_000, at: base) + "\n" + divEvent(cum: 51_000, at: base) + "\n",
              to: a, mtime: base.addingTimeInterval(10))
    divAppend(divEvent(cum: 2_000, at: base) + "\n" + divEvent(cum: 9_000, at: base) + "\n",
              to: b, mtime: base.addingTimeInterval(10))

    let first = probe(TokenUsageCache(), home: home)
    #expect(first.incremental == 57_000)     // 50,000 + 7,000
    #expect(first.full == 57_000)

    // a 를 지운다(= 사용자가 옛 세션을 정리했거나 다른 경로로 옮겼다).
    try? FileManager.default.removeItem(at: a)
    let after = probe(first.cache, home: home)
    // 전량 재파싱은 b 만 본다. 증분은 캐시에 남은 a 의 기여를 계속 더한다면 여기서 갈린다.
    #expect(after.full == 7_000)
    #expect(after.incremental == 7_000,
            "사라진 파일의 기여가 캐시에 남아 계속 계상된다: inc=\(after.incremental) full=\(after.full)")
}

// MARK: 6) 같은 내용의 파일이 새 경로로 복제된다(경로 변경) — 두 키로 두 번 세는가

@Test
func cacheDoesNotDoubleCountWhenFileMovesToNewPath() {
    let home = divTempHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let a = divRollout(home, "2026/07/08/rollout-2026-07-08T00-00-00-3333.jsonl")
    let b = divRollout(home, "2026/07/09/rollout-2026-07-08T00-00-00-3333.jsonl")
    let base = divNow.addingTimeInterval(-3 * 86_400)
    divAppend(divEvent(cum: 1_000, at: base) + "\n" + divEvent(cum: 101_000, at: base) + "\n",
              to: a, mtime: base.addingTimeInterval(10))
    let first = probe(TokenUsageCache(), home: home)
    #expect(first.incremental == 100_000)

    try? FileManager.default.createDirectory(
        at: b.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    try? FileManager.default.moveItem(at: a, to: b)
    try? FileManager.default.setAttributes(
        [.modificationDate: base.addingTimeInterval(10)], ofItemAtPath: b.path
    )
    let after = probe(first.cache, home: home)
    #expect(after.full == 100_000)
    #expect(after.incremental == 100_000,
            "경로가 바뀌면 옛 키와 새 키가 함께 계상된다: inc=\(after.incremental) full=\(after.full)")
}

// MARK: 6b) 무작위 차분 퍼저 — 어떤 변형이 증분을 부풀리는지 전수로 가른다
//
// 결정적 시드(선형합동)로 실제로 일어날 법한 변형만 던진다: append / 부분라인 / 잡음 / mtime 전진·역행 /
// 절단 / 같은 크기 내용 교체 / 삭제 / 경로 이동 / 신규 생성. 매 변형 뒤 (증분, 전량)을 재고 갈리면 기록한다.

@Test
func fuzzIdentifiesWhichMutationsInflateIncremental() {
    var seed: UInt64 = 0x5EED_1234
    func rnd(_ n: Int) -> Int {
        seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Int((seed >> 33) % UInt64(n))
    }
    let base = divNow.addingTimeInterval(-9 * 86_400)
    var inflating: [String: Int] = [:]     // 변형 종류 → 증분이 전량보다 커진 횟수
    var deflating: [String: Int] = [:]

    for trial in 0..<12 {
        let home = divTempHome()
        defer { try? FileManager.default.removeItem(at: home) }
        var paths: [String] = []
        var cum: [String: Int] = [:]
        var cache = TokenUsageCache()
        var clock = base
        var lastGap = 0

        for _ in 0..<40 {
            clock = clock.addingTimeInterval(Double(60 + rnd(600)))
            let kind = rnd(11)   // 10 = 삭제(default). 9 = 신규 생성(아래 if 가 먼저 가로챈다).
            var label = ""
            if paths.isEmpty || kind == 9 {
                label = "create"
                let p = "2026/07/\(String(format: "%02d", 5 + rnd(8)))/rollout-2026-07-05T00-00-00-\(rnd(100000)).jsonl"
                if !paths.contains(p) { paths.append(p); cum[p] = rnd(700_000_000) }
                let url = divRollout(home, p)
                divAppend(divNoise(1) + "\n", to: url, mtime: clock)
            } else {
                let p = paths[rnd(paths.count)]
                let url = divRollout(home, p)
                switch kind {
                case 0, 1, 2, 3:
                    label = "append-event"
                    cum[p, default: 0] += 1_000 + rnd(50_000)
                    divAppend(divEvent(cum: cum[p]!, at: clock) + "\n", to: url, mtime: clock)
                case 4:
                    label = "append-partial"
                    cum[p, default: 0] += 1_000 + rnd(50_000)
                    let line = divEvent(cum: cum[p]!, at: clock)
                    divAppend(String(line.prefix(line.count / 2)), to: url, mtime: clock)
                case 5:
                    label = "append-noise"
                    divAppend(divNoise(rnd(1000)) + "\n", to: url, mtime: clock)
                case 6:
                    label = "mtime-back"
                    try? FileManager.default.setAttributes(
                        [.modificationDate: clock.addingTimeInterval(-3600)], ofItemAtPath: url.path
                    )
                case 7:
                    label = "truncate"
                    if let h = try? FileHandle(forWritingTo: url) {
                        let size = (try? h.seekToEnd()) ?? 0
                        try? h.truncate(atOffset: size / 2)
                        try? h.close()
                    }
                    try? FileManager.default.setAttributes([.modificationDate: clock], ofItemAtPath: url.path)
                case 8:
                    label = "move"
                    let np = "2026/07/\(String(format: "%02d", 5 + rnd(8)))/\(url.lastPathComponent)"
                    if np != p, !paths.contains(np) {
                        let nurl = divRollout(home, np)
                        try? FileManager.default.createDirectory(
                            at: nurl.deletingLastPathComponent(), withIntermediateDirectories: true
                        )
                        try? FileManager.default.moveItem(at: url, to: nurl)
                        try? FileManager.default.setAttributes([.modificationDate: clock], ofItemAtPath: nurl.path)
                        paths.removeAll { $0 == p }
                        paths.append(np)
                        cum[np] = cum[p]
                    } else { label = "move-noop" }
                default:
                    label = "delete"
                    try? FileManager.default.removeItem(at: url)
                    paths.removeAll { $0 == p }
                }
            }
            let pr = probe(cache, home: home)
            cache = pr.cache
            // 격차의 **증가분**을 만든 변형만 범인으로 센다(한 번 벌어진 격차는 이후 모든 단계에 그대로 남는다).
            let gap = pr.incremental - pr.full
            if gap > lastGap { inflating[label, default: 0] += 1 }
            if gap < lastGap { deflating[label, default: 0] += 1 }
            lastGap = gap
        }
        _ = trial
    }
    print("[FUZZ] 증분 > 전량 (과다계상):", inflating.sorted { $0.value > $1.value })
    print("[FUZZ] 증분 < 전량 (과소계상):", deflating.sorted { $0.value > $1.value })
    // 이 단언은 "과다계상 경로가 하나도 없어야 한다"는 계약이다. 지금은 깨진다 — 깨진 이름이 곧 원인이다.
    #expect(inflating.isEmpty, "증분이 전량보다 커지는 변형: \(inflating)")
}

// MARK: 7) 실홈 프로브 — 빈 캐시 전량 1회 vs 캐시를 이어 여러 번 (환경변수로만 켠다)

@Test
func realHomeIncrementalMatchesFullParse() throws {
    guard ProcessInfo.processInfo.environment["CHECK_REAL_HOME_PROBE"] == "1" else { return }
    let home = FileManager.default.homeDirectoryForCurrentUser
    // 실홈은 이번 달 Codex 활동이 없을 수 있으므로 월을 인자로 받는다(기본: 지금).
    let now: Date = {
        guard let s = ProcessInfo.processInfo.environment["CHECK_PROBE_NOW"],
              let t = TimeInterval(s) else { return Date() }
        return Date(timeIntervalSince1970: t)
    }()
    var cache = TokenUsageCache()
    var values: [Int] = []
    for _ in 0..<5 {
        let r = TokenUsageIncrementalScanner.update(cache, homeDirectory: home, now: now)
        cache = r.cache
        values.append(r.usage.codexInput)
    }
    let full = TokenUsageIncrementalScanner.update(TokenUsageCache(), homeDirectory: home, now: now).usage.codexInput
    print("[REAL-HOME] incremental sequence=\(values) full=\(full)")
    #expect(values.last == full, "real home: inc=\(values.last ?? -1) full=\(full)")
}
