import AppKit
import Foundation
import Testing
@testable import check
@testable import CheckCore

// MARK: - v0.2.38 트랙 γ: 토큰 사용량 캐시 가벼워지기 (Q5 저장 스로틀 · Q6 48h 보관 경계 · M4 해시 키/핫·콜드 분리)
//
// 계측으로 확정된 출발점(이 맥, v0.2.37): dedupe 캐시 ≈16MB 상주(엔트리 70,766 개 중 73% 가 지난달), 팝오버 열림 중
// 30초마다 1,595 파일 순회 + 변경 시 7.6MB JSON 전체 재기록(21분에 64MB 디스크 쓰기), 첫 스캔 peak footprint 405MB.
//
// 여기 테스트는 전부 임시 홈의 픽스처만 읽는다(~/.claude/projects 실데이터 금지). defaults 스위트 이름은 고정이다.

/// 스캔 기준 시각(고정): 2026-07-14 12:33:20 KST → 현재 KST 월 "2026-07".
/// 월 시작 = KST 07-01 00:00 = UTC 06-30 15:00. 보관 경계(Q6) = 월 시작 − 48h = KST 06-29 00:00 = UTC 06-28 15:00.
private let v0238Now = Date(timeIntervalSince1970: 1_784_000_000)
private let v0238MonthStart = v0238UTC("2026-06-30T15:00:00Z")

private func v0238UTC(_ iso: String) -> Date {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    f.timeZone = TimeZone(identifier: "UTC")
    return f.date(from: iso)!
}

private func v0238ISO(_ date: Date) -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    f.timeZone = TimeZone(identifier: "UTC")
    return f.string(from: date)
}

/// 스캐너와 같은 산식의 ts14(UTC YYYYMMDDHHMMSS).
private func v0238TS14(_ date: Date) -> Int {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
    return ((((c.year! * 100 + c.month!) * 100 + c.day!) * 100 + c.hour!) * 100 + c.minute!) * 100 + c.second!
}

/// 테스트별 임시 폴더. `tag` 가 한 테스트 안의 자리를 가른다 — 이름이 UUID 면 실행마다 $TMPDIR 에 폴더가 쌓인다.
private func v0238TempDir(_ tag: String, function: String = #function) -> URL {
    CheckTestScratch.directory(tag, function: function)
}

/// 격리 캐시 베이스 URL(스토어가 여기서 .state.json / .entries.json 을 파생한다).
private func v0238CacheURL(in dir: URL) -> URL {
    dir.appendingPathComponent("cache.json", isDirectory: false)
}

private func v0238Write(_ contents: String, to url: URL, modified: Date = v0238Now) {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? Data(contents.utf8).write(to: url)
    try? FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
}

private func v0238Append(_ contents: String, to url: URL, modified: Date) {
    if let h = try? FileHandle(forWritingTo: url) {
        _ = try? h.seekToEnd()
        try? h.write(contentsOf: Data(contents.utf8))
        try? h.close()
    }
    try? FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
}

private func v0238ClaudeURL(_ home: URL, _ project: String, _ file: String) -> URL {
    home.appendingPathComponent(".claude/projects/\(project)/\(file)", isDirectory: false)
}

private func v0238CodexURL(_ home: URL, _ path: String) -> URL {
    home.appendingPathComponent(".codex/sessions/\(path)", isDirectory: false)
}

private func v0238ClaudeLine(id: String, req: String, at date: Date, usage: String, filler: Int = 0) -> String {
    let content = filler > 0 ? ",\"content\":[{\"type\":\"text\",\"text\":\"\(String(repeating: "x", count: filler))\"}]" : ""
    return "{\"type\":\"assistant\",\"timestamp\":\"\(v0238ISO(date))\",\"requestId\":\"\(req)\","
        + "\"message\":{\"id\":\"\(id)\",\"usage\":\(usage)\(content)}}"
}

private func v0238UserLine(at date: Date) -> String {
    "{\"type\":\"user\",\"timestamp\":\"\(v0238ISO(date))\",\"message\":{\"role\":\"user\",\"content\":\"hi\"}}"
}

private func v0238CodexLine(input: Int, output: Int, at date: Date) -> String {
    "{\"timestamp\":\"\(v0238ISO(date))\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\","
        + "\"info\":{\"total_token_usage\":{\"input_tokens\":\(input),\"cached_input_tokens\":0,"
        + "\"output_tokens\":\(output),\"total_tokens\":0}}}}"
}

private func v0238Defaults(_ name: String) -> UserDefaults {
    // **이름을 여기서 접는다.** 받은 String 을 그대로 열면 호출자가 평범한 이름을 주는 순간 plist 가
    // ~/Library/Preferences 로 떨어지는데, 소스 게이트는 String 파라미터에서 추적을 멈추므로 그 되돌림이
    // 무음이다(같은 수리가 `NudgeAutoStartContractTests.makeSuppressionStore` 에도 있다 — 그쪽 주석에 실측).
    // 이미 스크래치 절대 경로면 그대로 둔다 — 호출자가 `suite` 로 직접 여는 스위트(정리·리그)와 갈리면 안 된다.
    let path = name.hasPrefix(CheckTestScratch.root.path + "/") ? name : CheckTestScratch.suitePath(named: name)
    let d = UserDefaults(suiteName: path)!
    d.removePersistentDomain(forName: path)
    return d
}

// MARK: - 오라클 픽스처 (구현 전 코드로 채취한 값과 동일해야 한다)

/// 결정적 픽스처. Claude 두 프로젝트(포크 복제·스트리밍 스냅샷·지난달 48h 안/밖·오늘·부분 라인) + Codex rollout 하나.
/// 반환: (a.jsonl 완결 바이트, b.jsonl 바이트, rollout 바이트).
private func v0238WriteOracleFixture(into home: URL) -> (aConsumed: Int, bSize: Int, codexSize: Int) {
    let inMonth = v0238Now.addingTimeInterval(-5 * 86_400)              // 07-09 KST
    let today = v0238UTC("2026-07-14T02:00:00Z")                         // KST 07-14 11:00 (오늘)
    let prevWithin48h = v0238MonthStart.addingTimeInterval(-3_600)      // KST 06-30 23:00 (지난달, 보관 창 안)
    let prevOutside48h = v0238MonthStart.addingTimeInterval(-10 * 86_400) // KST 06-21 (지난달, 월 시작 − 48h 밖 — v0.2.43 부터는 12주 창 안이라 보관, 합계 밖)

    let k1 = v0238ClaudeLine(id: "msg_k1", req: "req_k1", at: inMonth,
        usage: "{\"input_tokens\":100,\"output_tokens\":50,\"cache_read_input_tokens\":10,\"cache_creation_input_tokens\":5}")
    let k2a = v0238ClaudeLine(id: "msg_k2", req: "req_k2", at: inMonth, usage: "{\"input_tokens\":10,\"output_tokens\":2}")
    let k2b = v0238ClaudeLine(id: "msg_k2", req: "req_k2", at: inMonth, usage: "{\"input_tokens\":11,\"output_tokens\":688}")
    let k3 = v0238ClaudeLine(id: "msg_k3", req: "req_k3", at: prevWithin48h, usage: "{\"input_tokens\":1000}")
    let k4 = v0238ClaudeLine(id: "msg_k4", req: "req_k4", at: prevOutside48h, usage: "{\"input_tokens\":5000}")
    let k5 = v0238ClaudeLine(id: "msg_k5", req: "req_k5", at: today, usage: "{\"input_tokens\":7,\"output_tokens\":3}")
    let partial = "{\"type\":\"assistant\",\"timestamp\":\"" // 개행 없는 꼬리(아직 쓰는 중)

    let aComplete = [k1, v0238UserLine(at: inMonth), k2a, k1, k2b, k3, k4].joined(separator: "\n") + "\n"
    v0238Write(aComplete + partial, to: v0238ClaudeURL(home, "proj-a", "a.jsonl"))
    let b = [k1, k5].joined(separator: "\n") + "\n"
    v0238Write(b, to: v0238ClaudeURL(home, "proj-b", "b.jsonl"))

    let codex = [
        v0238CodexLine(input: 900, output: 100, at: v0238UTC("2026-07-05T00:00:00Z")),   // cum 1000 → 첫 관측(기준선)
        v0238CodexLine(input: 1400, output: 100, at: v0238UTC("2026-07-05T01:00:00Z")),  // cum 1500 → +500 (7월)
        "{\"payload\":{\"type\":\"token_count\",\"info\":{\"rate_limits\":{}}}}",          // 무효(건너뜀)
        v0238CodexLine(input: 1600, output: 100, at: today)                              // cum 1700 → +200 (오늘)
    ].joined(separator: "\n") + "\n"
    v0238Write(codex, to: v0238CodexURL(home, "2026/07/05/rollout-2026-07-05T00-00-00-aaaa.jsonl"))
    return (aComplete.utf8.count, b.utf8.count, codex.utf8.count)
}

/// 구현 전(v0.2.37) 스캐너로 위 픽스처를 돌려 채취한 오라클. 합계·오늘분·파일 진행 상태가 구현 후에도 그대로여야 한다.
/// (엔트리 보관 수는 Q6 로 5 → 4 가 되는 것이 의도된 변화라 여기 오라클에 넣지 않는다.)
@Test
func fixtureScanTotalsAndFileProgressMatchPreChangeOracle() {
    let home = v0238TempDir("oracle")
    defer { try? FileManager.default.removeItem(at: home) }
    let sizes = v0238WriteOracleFixture(into: home)

    let r = TokenUsageIncrementalScanner.update(TokenUsageCache(), homeDirectory: home, now: v0238Now)

    // Claude: k1(100/50/10/5, 세 번 등장해도 1회) + k2(max-output 688 레코드의 11) + k5(7/3). k3·k4 는 지난달이라 합계 밖.
    #expect(r.usage.claudeInput == 118)
    #expect(r.usage.claudeOutput == 741)
    #expect(r.usage.claudeCacheRead == 10)
    #expect(r.usage.claudeCacheCreation == 5)
    // Codex: 첫 관측 기준선 → +500 +200. 무효 라인은 기준선을 건드리지 않는다.
    #expect(r.usage.codexInput == 700)
    #expect(r.usage.codexOutput == 0)
    #expect(r.usage.total == 1_574)
    // 오늘: k5(10) + Codex 오늘 델타(200).
    #expect(r.usage.todayDate == "2026-07-14")
    #expect(r.usage.todayTotal == 210)
    #expect(r.usage.month == "2026-07")

    // 파일 진행 상태: a 는 부분 라인 앞까지, b 와 rollout 은 끝까지.
    let claudeStates = Dictionary(uniqueKeysWithValues: r.cache.claudeFileStates.map { (($0.key as NSString).lastPathComponent, $0.value) })
    #expect(claudeStates["a.jsonl"]?.consumedOffset == sizes.aConsumed)
    #expect(claudeStates["a.jsonl"]?.size == sizes.aConsumed + "{\"type\":\"assistant\",\"timestamp\":\"".utf8.count)
    #expect(claudeStates["b.jsonl"]?.consumedOffset == sizes.bSize)
    #expect(r.cache.codexFileStates.values.first?.consumedOffset == sizes.codexSize)
    #expect(r.cache.codexFileStates.values.first?.prevCumulative == 1_700)
    #expect(r.cache.codexFileStates.values.first?.monthContribTotal == 700)
    #expect(r.cache.codexFileStates.values.first?.dayContrib == ["2026-07-14": 200, "2026-07-05": 500])   // v0.2.41: 일별 맵(과제 E 선행)
    #expect(r.stats.claudeFilesRead == 2)
    #expect(r.stats.codexFilesRead == 1)
    #expect(r.stats.cacheChanged == true)

    // 무변경 재갱신: 재읽기 0, 캐시 무변경, 합계 동일.
    let r2 = TokenUsageIncrementalScanner.update(r.cache, homeDirectory: home, now: v0238Now)
    #expect(r2.stats.claudeBytesRead == 0)
    #expect(r2.stats.codexBytesRead == 0)
    #expect(r2.stats.cacheChanged == false)
    #expect(r2.usage == r.usage)
}

// MARK: - 첫 스캔 메모리 상한 (autoreleasepool 세 층 × 세 경로)
//
// 토큰 스캐너의 풀은 **세 층**이고 층마다 막는 것이 다르다. 하나만 있어도 다른 층의 결함은 그대로 산다.
//   ① 청크 풀 — `readTail` · 진단 `streamLines` 의 1MB 청크 루프. `FileHandle.read` 가 주는 Data 는 autorelease 라
//      풀이 없으면 한 장도 안 풀리고 **읽은 총 바이트 ≈ 메모리**가 된다(램 1GB 신고의 원인).
//   ② 라인 풀 — `ingestClaudeLine` · Codex 라인 클로저 · 진단 `ingest`. JSONSerialization 이 라인마다 만드는 브리지
//      객체를 그 라인 안에서 돌려준다. ① 이 있어도 **한 청크 분량**(1MB 원문이 부푼 만큼)은 그대로 쌓인다.
//   ③ 항목 풀 — `recentFiles` · 진단 `rolloutFiles` 의 폴더 순회. `url.resourceValues(forKeys:)` 가 돌려주는
//      NSDate·NSNumber 도, enumerator 가 주는 NSURL 도 autorelease 다.
//
// **아래 값 테스트가 잡는 것은 ①②뿐이다.** ③ 은 값으로 잡을 수 없다 — 쌓이는 양이 읽은 바이트가 아니라 훑은
// **파일 개수**에 비례해서(프로덕션 주석의 실측: 항목 8,912개에서 호출마다 +1.8MB) 파일 한두 개짜리 픽스처에서는
// 신호가 아예 0 이다. 실측(변종 E — 항목 풀 둘만 no-op 으로 되돌림): 아래 세 값 테스트가 **전부 초록**이었고
// 회차 값도 1.16/1.37/1.43MB 로 꿈쩍도 안 했다. 픽스처를 수천 파일로 키우면 이번엔 그 파일을 **만드는** 비용이
// 측정 창을 덮는다. 그래서 ③ 은 뒤 '소스 계약' 절이 자리로만 지킨다 — 그 절이 ①②③ 일곱 자리를 전부 본다.
//
// ── 게이지를 바꾼 까닭 (v0.3.35, 이 맥에서 실측) ──────────────────────────────────────────────
// 옛 두 테스트는 스캔이 **끝난 뒤** phys_footprint 델타를 쟀다. 그 자리에서는 ② 가 **보이지 않는다** — 마지막 청크의
// 풀이 이미 비워져 임시 객체가 남아 있지 않아서다(끝나고 잰 malloc size_in_use 델타는 라인 풀 유무와 무관하게 0.00MB).
// 그래서 **스캔이 도는 동안의 피크**를 잰다(배경 스레드가 0.25ms 간격 표본). 지표도 phys_footprint 가 아니라
// malloc `size_in_use`(지금 잡고 있는 바이트)다:
//   · 고수위가 아니라 현재값이라, 이웃이 잠깐 부풀렸다 놓은 자국이 남지 않는다.
//   · 직전에 해제한 픽스처 힙을 재사용해도 **다시 올라간다** — phys_footprint 는 이미 상주한 페이지라 안 올라가서
//     "픽스처를 만들고 바로 재면 델타가 작게 나오는" 가림이 있었는데, 이 지표엔 그 가림이 없다.
//
// ── 다섯 조합 실측 (2026-09-22 · 아래 픽스처 그대로 · 저장소 사본에서 풀만 no-op 으로 바꿔 60회차 · 단위 MB) ──
//        경로     A(현재)  B(라인 풀)  C(청크 풀)  D(B+C = v0.3.34)  E(항목 풀)
//        Codex     1.15      7.15       7.99          53.42            1.16
//        Claude    1.37      7.33       8.25          53.77            1.37
//        진단      1.42      7.40       8.28          53.68            1.43
//   (B·C·D·E 는 그 풀만 no-op 래퍼로 바꾼 되돌림이다 — 중괄호가 그대로라 다른 차이가 섞이지 않는다.
//    적은 값이 60회차의 **최솟값**인 것이 요점이다: 아래 판정이 "상한 아래 회차가 있는가"이므로 되돌림 쪽에서
//    위험한 것은 큰 값이 아니라 가장 작은 값이다. B 는 60회차, C·D 는 24회차가 전부 그 값 위였다 — 한 회차도 상한 아래로 못 내려왔다.)
//   → 옛 Codex 테스트의 고정 8MB 상한은 위 B 값(7.15MB)을 그냥 통과시켰다 — 라인 풀 세 개가 무방비였다.
//     진단 경로는 테스트가 아예 0건이었다. E 열이 ③ 을 값으로 못 잡는다는 증거다.
//
// ── 상한 원칙: 바이트에는 안 붙고 **엔트리 수에는 붙는다** ──────────────────────────────────
// 지키려는 성질은 "메모리가 **읽은 바이트**를 따라가지 않는다"이다. 그래서 상한을 픽스처 바이트에 비례시키면 안 된다 —
// 실제로 옛 Claude 테스트의 픽스처×8 상한은 "읽은 바이트만큼 부푸는" 결함을 v0.3.34 까지 통과시켰다.
// 실측(라인 수만 바꿔 9회차 최솟값)으로 A 는 읽은 바이트를 따라가지 않는다:
//        Codex  픽스처 7.88MB→75.68MB(라인 2,500→24,000) 인데 **1.15MB 로 네 크기 전부 동일**.
//
// 다만 **'고정 절대 상한'이라는 말은 절반만 맞다** — A 를 움직이는 것이 하나 있다. 스캔이 캐시에 **보관하는 엔트리 수**다:
//        Claude  라인 2,500 → 1.37MB · 6,000 → 1.60MB · 12,000 → 2.06MB · 24,000 → 3.91MB
//        진단    라인 2,500 → 1.42MB · 24,000 → 3.72MB
// 즉 픽스처 라인 수를 키우면 **회귀가 하나도 없어도** 언젠가 상한을 넘는다. 그래서 라인 수를 상수(v0238PeakFixtureLines)로
// 묶고, 그 상수와 상한·바닥·더미 크기를 `peakCeilingIsCalibratedForThisFixture` 가 못 박는다 — 픽스처를 건드리는 손은
// 거기서 멈춰 서서 상한을 **다시 재게** 된다. 상한을 올려야 할 것 같으면 먼저 풀이 빠졌는지부터 봐라.
//
// ── P0: 병렬 이웃과 '거짓 빨강' (v0.3.35 에서 통계를 갈아 끼웠다) ───────────────────────────
// `size_in_use` 는 프로세스 전역이라 같은 프로세스에서 병렬로 도는 이웃이 섞인다. 옛 설계(회차 7 · **최솟값** · 3.5MiB)는
// 회귀가 전혀 없는 트리에서 **전체 스위트(2,988개)와 같은 프로세스로 돌리니 2회 중 1회가 빨개졌다**
// (Codex 회차 [0.90, 5.92, 7.12, 12.53, 17.24, 30.83, 38.01] → 유효 최솟값 5.92MB > 상한 3.67MB).
// 사용자는 이 스위트를 40분에 한 번 돌린다 — 거기서 헛되게 빨개지면 그 40분을 통째로 버린다.
//
// 오염은 **양쪽으로** 튄다. 둘을 따로 막는다.
//   (위로) 이웃이 우리 창 안에서 메모리를 **잡으면** 피크가 올라간다. → 통계를 '최솟값'에서 **'존재'**로 바꿨다:
//     상한 아래로 내려간 유효 회차가 나오면 초록이고, 나올 때까지 예산(60회차)만큼 회차를 갈아 본다.
//     회귀가 있으면 참값 자체가 상한 위라 **어느 회차도** 못 내려간다 — 그래서 예산을 키워도 탐지력이 한 치도 안 깎인다.
//     '상한만 올리는' 처방과 결정적으로 다른 점이 이것이다(상한만 5MiB 로 올리면 B 의 밴드를 통째로 통과시킬 수 있다).
//     초록은 대개 2~3회차에 끝나므로 예산을 다 쓰는 것은 진짜 빨강뿐이다.
//   (아래로) 이웃이 우리 창 안에서 메모리를 **놓으면** 피크가 기준선에 못 미쳐 rise 가 깎인다. 이쪽이 더 위험하다 —
//     **회귀를 상한 아래로 밀어 넣기** 때문이다. 실측: 변종 B(참값 7.15MB)의 Codex 한 회차가 **4.67MB** 로 나와
//     상한을 통과했다(= 거짓 초록). 회귀 없는 트리에서도 같은 회차가 0.03~0.43MB(참값 1.16MB)로 나왔다. 범인은 같은
//     순간 소스 계약 테스트가 읽어 들인 소스 버퍼 수 MB 를 놓은 것이었다.
//     → 그래서 표본 스레드가 피크뿐 아니라 **골(trough)**도 잰다. 한 회차가 증명하는 것은 `참값 < rise + dip` 이고
//       (이웃이 dip 만큼 놓았다면 그만큼 rise 가 깎였을 수 있으므로), 그 **상계가 v0238PeakProvenBound(6.0MB) 위인
//       회차는 버린다**. 되돌림 중 가장 작은 값이 7.15MB 이므로 남는 회차로는 되돌림을 절대 통과시킬 수 없다.
//       고정 딥 문턱보다 이쪽이 엄밀하면서 동시에 **더 너그럽다**: rise 가 작은 회차는 딥을 크게 봐줘도 결론이 안
//       바뀐다(부하 실측의 `rise 1.64MB ↓dip 2.94MB` 는 "참값 < 4.58MB" 를 그대로 증명한다). 고정 1MiB 문턱이었다면
//       그 회차를 버리고 부하 속에서 쓸 회차가 동나 **거짓 빨강**이 났다 — 실제로 그렇게 한 번 났다.
//       (상계에 안 잡히는 가림은 원리적으로 남는다 — 이웃이 하필 우리 피크 순간에만 놓았다 곧바로 다시 잡으면 골이
//        안 파인다. 그 자리는 아래 '한 번 더'와 60회차 예산이 맡는다: 회귀가 통과하려면 **서로 다른 두 회차**에서
//        같은 가림이 일어나야 한다. 전체 스위트 부하에서 변종 B 를 돌려 보면 그런 회차가 한 번도 안 나온다.)
//   (한 번 더) 상한 아래 유효 회차를 **둘** 모을 때까지 통과시키지 않는다 — 모르는 헛측정이 또 있을 때의 보험이다.
//
// 상한은 3.5MiB → **4.5MiB** 로 한 칸만 올렸다. '존재' 판정에서 상한이 하는 일은 "가장 깨끗한 회차가 이만큼의 잔여
// 오염까지는 견딘다"이다(A 1.15~1.42MB 에 4.72MB 면 3.3MB 까지 봐준다). 전체 스위트 부하에서 실제로 Codex 확정 회차가
// 3.53/3.50MB, Claude 가 4.71MB 로 찍힌 적이 있다 — 옛 3.67MB 상한이었다면 그 회차들은 빨강이었다.
//
// 검증자가 제안한 '별도 프로세스로 뽑기'는 **안 골랐다**: 그러면 `swift test` 한 번으로 안 돌아가서 사용자가 전체
// 스위트를 돌릴 때 이 세 테스트만 빠진다. 아무도 안 돌리는 테스트가 되기 쉽고, 빠뜨렸는지를 스위트가 알려 주지도 못한다.
// 지금 설계는 전체 스위트 안에서 그대로 돌고, 초록이면 회차 두세 번에 끝나 **더 빨라졌다**(무부하에서 세 테스트 합 18.5초 → 2.6초).

/// 이 프로세스가 **지금 잡고 있는** malloc 바이트(size_in_use). 고수위가 아니라 현재값이다.
private func v0238LiveBytes() -> Int {
    var stats = malloc_statistics_t()
    malloc_zone_statistics(nil, &stats)
    return Int(stats.size_in_use)
}

/// 작업이 도는 동안 v0238LiveBytes 를 0.25ms 간격으로 훑어 **최댓값과 최솟값**을 남긴다. (쉬지 않고 훑으면 malloc 존
/// 잠금을 두고 스캔 스레드와 다퉈 스캔이 수십 배 느려진다 — 실측으로 확인하고 간격을 넣었다.)
/// 최솟값을 같이 재는 까닭은 절 머리 'P0' 의 (아래로) 항목에 있다.
private final class V0238PeakSampler {
    private let lock = NSLock()
    private var stopped = false
    private var peak = Int.min
    private var trough = Int.max
    private var baseline = 0
    private var thread: Thread?

    /// 표본 스레드를 띄우고 **첫 표본을 찍을 때까지 기다린 뒤** 그 첫 표본을 기준선으로 돌려준다.
    /// 기준선을 표본 스레드가 직접 찍게 해야 기준선과 이후 표본이 같은 자에서 나온다(부르는 쪽에서 미리 재면
    /// 스레드가 뜨는 사이의 변화가 통째로 델타에 섞인다).
    func startAndBaseline() -> Int {
        let ready = DispatchSemaphore(value: 0)
        let worker = Thread { [self] in
            let first = v0238LiveBytes()
            lock.lock(); peak = first; trough = first; baseline = first; lock.unlock()
            ready.signal()
            while true {
                lock.lock(); let done = stopped; lock.unlock()
                if done { break }
                let live = v0238LiveBytes()
                lock.lock()
                if live > peak { peak = live }
                if live < trough { trough = live }
                lock.unlock()
                usleep(250)
            }
        }
        worker.qualityOfService = .userInitiated
        thread = worker
        worker.start()
        ready.wait()
        lock.lock(); defer { lock.unlock() }
        return baseline
    }

    func stop() -> (peak: Int, trough: Int) {
        lock.lock(); stopped = true; lock.unlock()
        while thread?.isFinished == false { usleep(200) }
        lock.lock(); defer { lock.unlock() }
        return (peak, trough)
    }
}

/// 한 회차의 관측. rise = 기준선 위로 오른 최대치(우리가 재려는 값), dip = 기준선 **아래로** 파인 최대치
/// (= 이웃이 창 안에서 놓은 양. 우리 작업만 돌면 0 이다 — 스캔은 기준선 위로만 쌓는다).
private struct V0238Trial {
    let rise: Int
    let dip: Int
    /// 이 회차가 **증명하는 상계**. 이웃이 창 안에서 dip 만큼 놓았다면 그만큼 rise 가 깎였을 수 있으므로,
    /// 이 회차로 말할 수 있는 것은 "참값 < rise + dip" 까지다.
    var provenUpperBound: Int { rise + dip }
    /// 이 회차를 믿어도 되는가. 바닥 미만이면 표본을 거의 다 놓친 것이고(스캔은 1MiB 버퍼를 반드시 잡는다),
    /// 상계가 되돌림 밴드에 닿으면 이 회차로는 아무것도 못 가른다.
    func isValid(floor: Int, bound: Int = v0238PeakProvenBound) -> Bool { rise >= floor && provenUpperBound < bound }
}

private func v0238Describe(_ trials: [V0238Trial]) -> [String] {
    trials.map { $0.dip > 0 ? "\(v0238MB($0.rise))↓\(v0238MB($0.dip))" : v0238MB($0.rise) }
}

/// 한 회차: 표본 스레드를 세우고(첫 표본 = 기준선) work 를 돌린 뒤 rise·dip 을 돌려준다.
private func v0238PeakTrial(_ work: () -> Void) -> V0238Trial {
    var trial = V0238Trial(rise: 0, dip: 0)
    autoreleasepool {
        let sampler = V0238PeakSampler()
        let before = sampler.startAndBaseline()
        work()
        let seen = sampler.stop()
        trial = V0238Trial(rise: seen.peak - before, dip: max(0, before - seen.trough))
    }
    return trial
}

/// 예산 밖의 **데우기 회차**. 첫 회차는 재기만 하고 버린다 — 캐시·lazy 초기화가 첫 회차에만 섞이고,
/// `.serialized` 스위트의 첫 테스트는 같은 순간 출발하는 이웃(소스 계약 테스트의 소스 버퍼 해제)과 자주 겹친다.
private func v0238WarmUpPeakGauge(_ work: () -> Void) {
    _ = v0238PeakTrial(work)
}

/// work 를 trials 번 돌려 회차마다 rise·dip 을 잰다(게이지 교정용 — 상한 판정은 아래 '존재' 쪽).
private func v0238PeakTrials(count: Int, _ work: () -> Void) -> [V0238Trial] {
    v0238WarmUpPeakGauge(work)
    var out: [V0238Trial] = []
    for _ in 0..<count { out.append(v0238PeakTrial(work)) }
    return out
}

/// **게이지 교정 전용**의 '가장 깨끗한 회차'. 위 상한 판정과 규칙이 다르다 — 거기서는 한 회차가 증명하는 상계
/// (rise+dip)가 되돌림 밴드를 안 건드려야 하지만, 여기서는 두 대조군의 **최솟값**끼리 견주기 때문이다:
/// 위로 부푼 회차는 최솟값이 스스로 비켜 주므로 버릴 까닭이 없고(버리면 부하 속에서 쓸 회차가 동나 거짓 빨강이
/// 난다 — 실측으로 한 번 겪었다), **아래로 깎인 회차만** 버리면 된다. 유효 회차가 3 미만이면 nil(측정 실패).
private func v0238CleanestPeak(_ trials: [V0238Trial], floor: Int, maxDip: Int = v0238GaugeMaxDip) -> Int? {
    let valid = trials.filter { $0.rise >= floor && $0.dip <= maxDip }
    guard valid.count >= 3 else { return nil }
    return valid.map(\.rise).min()
}

/// 상한 판정 결과. 절 머리의 'P0' 항목이 왜 최솟값이 아니라 '존재'인지 적고 있다.
private enum V0238PeakVerdict {
    /// 상한 아래로 내려간 유효 회차를 필요한 수만큼 찾았다(그 자리에서 멈췄다).
    case under(peak: Int, trials: [V0238Trial])
    /// 예산을 다 썼는데 유효 회차가 상한 아래로 충분히 못 모였다 = 회귀.
    case over(trials: [V0238Trial])
    /// 유효 회차가 3 미만 — 이웃이 측정 창을 내내 흔들었다. 초록으로 넘기지 않는다.
    case unmeasurable(trials: [V0238Trial])
}

/// 상한 아래 유효 회차가 **두 번** 나올 때까지 재고, 모이면 그 자리에서 멈춘다(최대 budget 회차).
private func v0238PeakUnderCeiling(
    budget: Int = v0238PeakTrialBudget,
    confirmations: Int = v0238PeakConfirmations,
    ceiling: Int = v0238PeakCeiling,
    floor: Int = v0238PeakFloor,
    _ work: () -> Void
) -> V0238PeakVerdict {
    v0238WarmUpPeakGauge(work)
    var trials: [V0238Trial] = []
    var under: [Int] = []
    for _ in 0..<budget {
        let trial = v0238PeakTrial(work)
        trials.append(trial)
        if trial.isValid(floor: floor), trial.rise < ceiling {
            under.append(trial.rise)
            if under.count >= confirmations { return .under(peak: under.max() ?? trial.rise, trials: trials) }
        }
    }
    // '측정이 됐는가'와 '그 회차로 통과를 확정할 수 있는가'는 다른 물음이다. 앞엣것만으로 갈라야 한다 —
    // 회귀가 있으면 rise 자체가 상계 위라 **모든** 회차가 확정 자격을 잃는데, 그걸 '측정 실패'라고 보고하면
    // 사람이 풀을 고치는 대신 테스트를 다시 돌린다(실측으로 그 모양이 나와서 고쳤다).
    let measured = trials.filter { $0.rise >= floor }
    return measured.count >= 3 ? .over(trials: trials) : .unmeasurable(trials: trials)
}

/// 세 상한 테스트의 공통 보고. culprits 는 빨개졌을 때 **어느 풀을 보라**고 짚는 문장이다.
/// 회차 표기 "1.16MB↓2.40MB" 는 rise 1.16MB · dip 2.40MB(이웃이 창 안에서 놓은 양) 라는 뜻이다.
private func v0238ExpectPeakUnderCeiling(_ label: String, _ verdict: V0238PeakVerdict, culprits: String) {
    switch verdict {
    case let .under(peak, trials):
        print("=== V0238 PEAK(\(label)): peak=\(v0238MB(peak)) 회차=\(trials.count)/\(v0238PeakTrialBudget) "
            + "trials=\(v0238Describe(trials)) ceiling=\(v0238MB(v0238PeakCeiling)) ===")
    case let .over(trials):
        Issue.record("""
            \(label) 첫 스캔 피크가 \(trials.count)회차 **내내** 고정 상한 \(v0238MB(v0238PeakCeiling)) 아래로 못 내려왔다 — \(culprits)
            회차(rise↓dip): \(v0238Describe(trials))
            (병렬 이웃이 위로 올린 회차는 다음 회차에서 비켜 준다. 예산을 다 쓰도록 '상한 아래 + 상계 \(v0238MB(v0238PeakProvenBound)) 미만'
             회차가 \(v0238PeakConfirmations) 번 못 모였다면 그것은 이웃이 아니라 참값이 올라간 것이다 — 절 머리 'P0' 항목 참조.
             위 목록의 rise 가 되돌림 밴드(7.15MB~)에 몰려 있으면 풀이 빠진 것이고, ↓dip 이 큰 회차만 잔뜩이면
             기계가 유난히 시끄러웠던 것이니 한 번 더 돌려 봐라.)
            """)
    case let .unmeasurable(trials):
        Issue.record("""
            \(label) 측정 실패: rise 가 바닥(\(v0238MB(v0238PeakFloor)))을 넘은 회차가 3 미만이다 — \(v0238Describe(trials)).
            스캔은 1MiB 청크 버퍼를 반드시 잡으므로 이건 게이지가 스캔을 못 본 것이다(표본 스레드가 안 돌았거나
            이웃이 창 안에서 그만큼을 놓았다). 다시 돌려라 — 이 상태를 초록으로 넘기지 않는다.
            """)
    }
}

/// 세 경로 공통 고정 상한(4.5MiB). 근거는 이 절 머리의 실측 표와 'P0' 항목에 있다.
private let v0238PeakCeiling = 4_718_592
/// 유효 회차의 바닥. 프로덕션 `readTail`/`streamLines` 의 chunkSize 가 `1 << 20` 이라 스캔은 1MiB 버퍼를 반드시
/// 잡는다 — 그보다 작은 rise 는 우리 것이 아니라 표본을 놓쳤거나 이웃이 깎아낸 것이다(픽스처가 8MB 라 청크는 항상 꽉 찬다).
private let v0238PeakFloor = 1_048_576
/// 회차가 증명해야 하는 상계(6.0MB). `rise + dip` 이 이보다 커진 회차는 이웃 때문에 아무것도 못 가르므로 버린다.
/// 되돌림 중 가장 작은 값이 7.15MB 이므로 1.15MB 의 탐지 여유가 남는다 — 이 간격이 좁아지면 이 값을 줄여라.
/// 고정 문턱(옛 '허용 딥 1MiB')보다 넉넉하면서 더 엄밀하다: rise 가 작은 회차일수록 딥을 더 봐주는데,
/// 그때는 실제로 봐줘도 결론이 안 바뀌기 때문이다(rise 1.64 ↓dip 2.94 → 참값 < 4.58MB 로 이미 판정이 선다).
private let v0238PeakProvenBound = 6_000_000
/// 회차 예산. 초록은 상한 아래 회차 둘을 찾으면 멈추므로 이 수는 **빨강일 때만** 다 쓴다.
/// 60 인 까닭: 부하가 심하면 쓸 만한 회차가 드물어진다(실측 — 전체 스위트 셋을 한 기계에서 동시에 돌리면
/// Codex 가 12회차에서야 확정된 적이 있다). 예산을 키워도 탐지력은 한 치도 안 깎이므로 넉넉히 잡는다.
private let v0238PeakTrialBudget = 60
/// 초록에 필요한 '상한 아래 유효 회차' 수. 1 이면 헛측정 한 번이 곧 거짓 초록이다.
private let v0238PeakConfirmations = 2
/// 게이지 교정에서 '아래로 깎였다'고 보는 딥(2MiB). 풀 없는 대조군의 참값이 6.29MB 라, 이만큼 깎여도
/// 두 대조군의 간격(3MiB 이상)이라는 결론은 안 바뀐다.
private let v0238GaugeMaxDip = 2 * 1_048_576
/// 게이지 회차 수. 부하에서 유효 회차 3을 남기려는 것이다.
private let v0238GaugeTrials = 15
/// 게이지 대조군의 라인 수. **청크 한 장 분량이면 충분하다** — 대조군도 1MB 어치씩 풀로 감싸므로 피크는
/// 청크당 값이고 라인을 더 넣어도 안 커진다(풀 없는 쪽 6.29MB 는 2,500줄이든 400줄이든 같다).
/// 짧게 잡는 까닭은 **측정 창이 짧을수록 이웃이 덜 섞이기** 때문이다: 2,500줄(창 ≈0.4초)일 때 부하에서
/// 이웃의 3.5MB 가 열두 회차에 내리 끼어 거짓 빨강이 났다(pooled 최솟값 3.54MB). 400줄이면 창이 ≈1/8 이다.
private let v0238GaugeLines = 400
/// 픽스처 라인 수 = 스캔이 캐시에 **보관하는 엔트리 수**. 상한은 바이트가 아니라 이 수에 붙어 있다(절 머리 실측).
/// 바꾸려면 `peakCeilingIsCalibratedForThisFixture` 를 지나야 하고, 지나려면 상한을 다시 재야 한다.
private let v0238PeakFixtureLines = 2_500

private func v0238MB(_ bytes: Int) -> String { String(format: "%.2fMB", Double(bytes) / 1_000_000) }

/// 라인 하나에 붙이는 중첩 배열 더미. 라인 풀이 막는 양은 **한 청크 안에서 파서가 만드는 임시 객체의 총량**이라
/// 원문 1바이트가 몇 바이트로 부푸는지가 신호 크기를 정한다(픽스처를 키워도 안 커진다 — 청크가 1MB 고정이므로).
/// 중첩 배열은 원문 대비 팽창이 가장 큰 모양이라(실측 ~6배) A 와 B 의 간격을 1.15MB 대 7.15MB 로 벌려 준다.
/// 실제 로그에도 중첩 구조는 흔하다(Claude 의 message.content 블록 배열, Codex 의 rate_limits).
private let v0238NestedPad: String = (0..<180).map { ",\"p\($0)\":[[[[1]]]]" }.joined()

/// 대량 Codex 픽스처(라인 2,500개 ≈ 7.9MB, 1MB 청크 여덟 장). 만드는 자리를 측정과 떼어 놓는다 —
/// 큰 문자열이 이 함수 안에서 죽어야 측정 창에 픽스처 힙이 섞이지 않는다.
private func v0238WriteBulkCodexFixture(into home: URL, lines: Int) -> Int {
    let ts = v0238ISO(v0238Now.addingTimeInterval(-2 * 86_400))
    var text = ""
    text.reserveCapacity(lines * 3_400)
    for i in 0..<lines {
        // 누적 카운터라 입력이 단조 증가한다(첫 줄은 기준선이라 델타를 내지 않는다 — 프로덕션 규약).
        text += "{\"timestamp\":\"\(ts)\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\","
            + "\"info\":{\"total_token_usage\":{\"input_tokens\":\(i),\"cached_input_tokens\":0,"
            + "\"output_tokens\":0,\"total_tokens\":0}}}\(v0238NestedPad)}\n"
    }
    v0238Write(text, to: v0238CodexURL(home, "2026/rollout-2026-07-01T00-00-00-aaaa.jsonl"))
    return text.utf8.count
}

/// 대량 Claude 픽스처(라인 2,500개 ≈ 7.9MB). 더미는 message 안에 둔다 — 프리체크(usage·assistant)를 지나
/// 라인이 실제로 파싱되는 경로여야 라인 풀의 효과가 드러난다.
private func v0238WriteBulkClaudeFixture(into home: URL, lines: Int) -> Int {
    let ts = v0238ISO(v0238Now.addingTimeInterval(-2 * 86_400))
    var text = ""
    text.reserveCapacity(lines * 3_400)
    for i in 0..<lines {
        text += "{\"type\":\"assistant\",\"timestamp\":\"\(ts)\",\"requestId\":\"req_\(i)\","
            + "\"message\":{\"id\":\"msg_\(i)\",\"usage\":{\"input_tokens\":\(i),\"output_tokens\":1,"
            + "\"cache_read_input_tokens\":2,\"cache_creation_input_tokens\":3}\(v0238NestedPad)}}\n"
    }
    v0238Write(text, to: v0238ClaudeURL(home, "big", "a.jsonl"))
    return text.utf8.count
}

/// 게이지 교정용 대조군: 같은 라인 묶음을 1MB 어치씩 풀로 감싸 파싱한다(프로덕션 청크 풀 모사).
/// perLinePool 이면 라인마다 한 겹 더 — 프로덕션의 라인 풀이 하는 일 그대로다.
private func v0238ParseChunked(_ lines: [Data], perLinePool: Bool) {
    var index = 0
    while index < lines.count {
        var bytes = 0
        var end = index
        while end < lines.count, bytes < 1 << 20 { bytes += lines[end].count; end += 1 }
        autoreleasepool {
            for k in index..<end {
                if perLinePool {
                    autoreleasepool { _ = try? JSONSerialization.jsonObject(with: lines[k]) as? [String: Any] }
                } else {
                    _ = try? JSONSerialization.jsonObject(with: lines[k]) as? [String: Any]
                }
            }
        }
        index = end
    }
}

private func v0238PadLines(_ count: Int) -> [Data] {
    (0..<count).map { Data("{\"i\":\($0)\(v0238NestedPad)}".utf8) }
}

/// 세 경로의 메모리 상한. `.serialized` 로 묶는 까닭은 셋이 같은 프로세스 전역 지표를 보기 때문이다 —
/// 서로 겹치면 상대의 피크를 제 것으로 읽는다. (스위트 **안**만 직렬이라 다른 스위트와의 병렬은 못 막는다.
/// 그쪽은 '상한 아래 유효 회차의 존재' 판정 · 상계(rise+dip) 가드 · 60회차 예산이 맡는다 — 절 머리 'P0' 항목 참조.)
@Suite(.serialized)
struct V0238ScannerMemoryCeilings {

    /// Codex 경로. 라인 풀(프로덕션 Codex 라인 클로저)과 청크 풀(readTail)을 **둘 다** 가른다.
    /// 뮤테이션: 둘 중 아무 풀이나 no-op 으로 바꾸면 60회차가 전부 7.15MB / 7.99MB 위가 되어 빨강(저장소 사본에서 실측).
    @Test
    func firstScanPeakOnCodexFixtureStaysUnderFixedCeiling() {
        let home = v0238TempDir("peak-codex")
        defer { try? FileManager.default.removeItem(at: home) }
        let lines = v0238PeakFixtureLines
        let fixtureBytes = v0238WriteBulkCodexFixture(into: home, lines: lines)

        var scanned: TokenUsageIncrementalScanner.Result?
        let verdict = v0238PeakUnderCeiling {
            scanned = TokenUsageIncrementalScanner.update(TokenUsageCache(), homeDirectory: home, now: v0238Now)
        }
        print("=== V0238 FIXTURE(codex): \(v0238MB(fixtureBytes)) lines=\(lines) ===")

        // 값이 맞게 나왔는지부터(메모리만 재고 결과가 틀리면 지키는 것이 없다). 첫 줄은 기준선이라 델타 밖.
        #expect(scanned?.usage.codexInput == lines - 1)
        #expect(scanned?.stats.codexFilesRead == 1)
        v0238ExpectPeakUnderCeiling(
            "Codex", verdict,
            culprits: "readTail 의 청크 풀이나 Codex 라인 풀이 빠졌다(되돌림 실측 7.15MB / 7.99MB).")
    }

    /// Claude 경로. 라인 풀은 `ingestClaudeLine` 안에 있다(v0.2.37 부터). 청크 풀은 Codex 와 같은 readTail 을 쓴다.
    @Test
    func firstScanPeakOnClaudeFixtureStaysUnderFixedCeiling() {
        let home = v0238TempDir("peak-claude")
        defer { try? FileManager.default.removeItem(at: home) }
        let lines = v0238PeakFixtureLines
        let fixtureBytes = v0238WriteBulkClaudeFixture(into: home, lines: lines)

        var scanned: TokenUsageIncrementalScanner.Result?
        let verdict = v0238PeakUnderCeiling {
            scanned = TokenUsageIncrementalScanner.update(TokenUsageCache(), homeDirectory: home, now: v0238Now)
        }
        print("=== V0238 FIXTURE(claude): \(v0238MB(fixtureBytes)) lines=\(lines) "
            + "entries=\(scanned?.cache.claudeEntries.count ?? -1) ===")

        #expect(scanned?.cache.claudeEntries.count == lines)
        #expect(scanned?.usage.claudeInput == (0..<lines).reduce(0, +))
        v0238ExpectPeakUnderCeiling(
            "Claude", verdict,
            culprits: "readTail 의 청크 풀이나 ingestClaudeLine 의 라인 풀이 빠졌다(되돌림 실측 7.33MB / 8.25MB).")
    }

    /// 진단 경로(CodexUsageDiagnosticsScanner). v0.3.34 까지 이 경로의 풀 두 개는 **테스트가 0건**이라
    /// 통째로 지워도 스위트가 초록이었다. 진단은 이어읽기가 없는 **전량 스캔**이라 풀이 빠지면 증분보다 더 분다.
    @Test
    func diagnosticsScanPeakStaysUnderFixedCeiling() {
        let home = v0238TempDir("peak-diagnostics")
        defer { try? FileManager.default.removeItem(at: home) }
        let lines = v0238PeakFixtureLines
        let fixtureBytes = v0238WriteBulkCodexFixture(into: home, lines: lines)

        var diagnostics: CodexUsageDiagnostics?
        let verdict = v0238PeakUnderCeiling {
            diagnostics = CodexUsageDiagnosticsScanner.compute(homeDirectory: home, month: "2026-07", appBuild: 1)
        }
        print("=== V0238 FIXTURE(diagnostics): \(v0238MB(fixtureBytes)) lines=\(lines) "
            + "dedup=\(diagnostics?.dedupTotal ?? -1) ===")

        #expect(diagnostics?.filesTotal == 1)
        #expect(diagnostics?.dedupTotal == lines - 1)
        v0238ExpectPeakUnderCeiling(
            "진단", verdict,
            culprits: "streamLines 의 청크 풀이나 ingest 의 라인 풀이 빠졌다(되돌림 실측 7.40MB / 8.28MB).")
    }

    /// 게이지 교정. 위 세 상한은 "피크가 작다"를 단언하므로, 게이지가 **눈이 멀면 전부 조용히 초록**이 된다
    /// (옛 게이지가 라인 풀에 대해 실제로 그랬다). 그래서 같은 기계로 **풀 있는 파싱 / 없는 파싱**을 재서
    /// 둘이 갈리는지 확인한다 — 기준선이 같은 입력이면 그 테스트는 영원히 초록이므로, 비교 대상은 반드시 달라야 한다.
    ///
    /// 두 대조군에 **각자의 바닥·유효 회차 가드**를 씌운다. 이 자리는 상한 테스트와 바닥이 다르다:
    /// 대조군은 파일을 열지 않아(메모리에 이미 있는 Data 를 파싱만 한다) 1MiB 청크 버퍼를 안 잡는다.
    ///   · 풀 있는 쪽(참값 0.03MB): 아래 단언이 **상한**(1.05MB 미만)이라 이웃은 위로만 해칠 수 있다. 다만 rise 가
    ///     0 이나 음수로 깎이면 두 단언이 **공짜로** 통과한다 — 그 길을 막으려고 4KiB 바닥을 둔다.
    ///   · 풀 없는 쪽(참값 6.29MB): 이쪽은 **커야** 하는 값이라 이웃이 깎으면 곧바로 거짓 빨강이 된다
    ///     (합성 이웃 200MB 아래서 실제로 무너졌다). 3MiB 바닥으로 깎인 회차를 버린다.
    /// 두 쪽 모두 **아래로 깎인 회차**(dip 2MiB 초과)는 버린다. 위로 부푼 회차는 안 버린다 — 두 단언이 모두
    /// **최솟값**을 보므로 부푼 회차는 스스로 비켜 주고, 버리면 부하 속에서 쓸 회차가 동나 거짓 빨강이 난다
    /// (전체 스위트 셋을 동시에 돌렸을 때 실제로 그렇게 한 번 빨개져서 규칙을 갈랐다).
    /// 어느 쪽이든 유효 회차가 3 미만이면 '측정 실패'로 빨개진다 — 조용한 초록은 없다.
    @Test
    func peakMemoryGaugeSeparatesPooledFromUnpooledParsing() {
        let lines = v0238PadLines(v0238GaugeLines)
        let pooledFloor = 4_096
        let unpooledFloor = 3 * 1_048_576
        let pooled = v0238PeakTrials(count: v0238GaugeTrials) { v0238ParseChunked(lines, perLinePool: true) }
        let unpooled = v0238PeakTrials(count: v0238GaugeTrials) { v0238ParseChunked(lines, perLinePool: false) }
        print("=== V0238 GAUGE: pooled=\(v0238Describe(pooled)) unpooled=\(v0238Describe(unpooled)) ===")

        guard let low = v0238CleanestPeak(pooled, floor: pooledFloor) else {
            Issue.record("게이지 측정 실패(풀 있는 쪽): 유효 회차(rise ≥ 4KiB, dip ≤ \(v0238MB(v0238GaugeMaxDip)))가 3 미만이다 — \(v0238Describe(pooled)).")
            return
        }
        guard let high = v0238CleanestPeak(unpooled, floor: unpooledFloor) else {
            Issue.record("""
                게이지 측정 실패(풀 없는 쪽): 유효 회차(rise ≥ 3.15MB, dip ≤ \(v0238MB(v0238GaugeMaxDip)))가 3 미만이다 — \(v0238Describe(unpooled)).
                이웃이 창 안에서 메모리를 놓아 회차가 깎였거나, 게이지가 '풀 없는 파싱'을 아예 못 본다.
                후자라면 위 세 상한이 결함을 조용히 통과시킨다 — 먼저 무부하에서 다시 재 봐라(참값 6.29MB).
                """)
            return
        }
        #expect(low < 1_048_576, "라인 풀을 씌운 파싱의 피크가 1.05MB 를 넘는다(\(v0238MB(low))) — 게이지가 이웃에 절였다")
        #expect(high - low >= 3 * 1_048_576,
                "게이지가 '풀 없는 파싱'과 '풀 있는 파싱'을 못 가른다(\(v0238MB(high)) vs \(v0238MB(low))). 이 상태에서는 위 세 상한이 결함을 조용히 통과시킨다 — 게이지부터 고쳐라.")
    }

    /// 상한 교정의 **입력**을 못 박는다. 위 세 상한은 "이 픽스처에서 잰 값"이라, 픽스처를 키우면 회귀가 하나도 없어도
    /// 상한을 넘는다 — Claude 는 보관 엔트리 수에 비례한다(절 머리 실측: 2,500줄 1.37MB → 24,000줄 3.91MB).
    /// 그래서 픽스처·상한·바닥·증명 상계를 바꾸는 손이 반드시 여기서 멈춰 서게 한다. 바꿨다면 다섯 조합(A~E)을
    /// **다시 재고** 절 머리 표와 이 상수들을 같이 고쳐라. 숫자만 맞춰 여기를 지나가면 상한이 무엇을 지키는지
    /// 아무도 모르게 된다.
    @Test
    func peakCeilingIsCalibratedForThisFixture() {
        #expect(v0238PeakFixtureLines == 2_500,
                "픽스처 라인 수가 바뀌었다(\(v0238PeakFixtureLines)). 상한은 보관 엔트리 수에 비례한다 — 상한을 다시 재라.")
        #expect(v0238NestedPad.utf8.count == 2_950,
                "라인 더미 크기가 바뀌었다(\(v0238NestedPad.utf8.count)B). 파서 팽창률이 바뀌므로 A 와 B 의 간격을 다시 재라.")
        #expect(v0238PeakCeiling == 4_718_592,
                "상한이 바뀌었다(\(v0238MB(v0238PeakCeiling))). 되돌림 B 의 최솟값(7.15MB)과의 여유를 다시 확인했는가.")
        #expect(v0238PeakFloor == 1_048_576,
                "바닥이 바뀌었다(\(v0238MB(v0238PeakFloor))). 바닥은 프로덕션 chunkSize(1 << 20)와 같아야 한다.")
        // 초록의 보증은 '통과한 회차의 상계 < v0238PeakProvenBound' 다. 이 값이 되돌림 최솟값(7.15MB)에 닿으면 회귀가 통과한다.
        #expect(v0238PeakProvenBound <= 6_000_000,
                "증명 상계가 \(v0238MB(v0238PeakProvenBound)) 라 되돌림 최솟값 7.15MB 에 너무 가깝다 — 줄여라.")
        #expect(v0238PeakCeiling < v0238PeakProvenBound,
                "상한이 증명 상계보다 크면 상한은 아무 일도 안 한다.")
    }
}

// MARK: - 풀이 **루프 안**에 있다는 소스 계약
//
// 위 세 상한은 값으로 재고 이쪽은 자리로 못 박는다. 둘 다 두는 까닭:
//   · 값 쪽은 프로세스 전역 지표라 병렬 이웃 때문에 여유를 둘 수밖에 없다. 자리 쪽은 오염이 없어 되돌림을
//     한 치도 봐주지 않고 0.02초에 끝난다.
//   · 값 쪽은 "이 경로의 풀 둘 중 하나가 빠졌다"까지만 말한다. 자리 쪽은 **어느 자리인지** 짚는다.
//   · **항목 풀(recentFiles · 진단 rolloutFiles)은 값 쪽이 원리적으로 못 잡는다** — 절 머리 ③ 과 변종 E 실측 참조.
//     이 두 자리는 오직 여기서만 지킨다.
//   · 풀이 루프 **밖**으로 나가는 되돌림(`autoreleasepool { while … }`)도 여기서 잡힌다.
// 주석은 걷어내고 본다: 프로덕션 주석이 풀의 까닭을 길게 적고 있어, 안 걷으면 그 설명을 지워야만 초록이 된다.
//
// ── 낱말 순서만으로는 모자랐다: '빈 풀 미끼' (v0.3.35 실측) ────────────────────────────────
// 옛 계약은 낱말이 그 순서로 나오기만 하면 초록이었다. 그래서 루프 안에 `autoreleasepool { }` **빈 껍데기**를 두고
// 본문을 풀 밖으로 빼는 되돌림(변종 F)에 그대로 속았다 — 낱말은 전부 제 순서에 있는데 풀은 아무것도 안 감싼다.
// 지금은 여는 중괄호의 **짝을 세어** 본문 범위를 구하고, 핵심 호출이 그 범위 **안**에 있는지 본다.
// 실측(같은 빌드에서 옛 검사기를 나란히 돌려 비교): 변종 F 에서 옛 '낱말 순서만' 검사기는 **다섯 자리 전부 초록**,
// 지금 검사기는 **일곱 자리 전부 빨강**이었다.

/// `//` 줄 주석과 `/* */` 블록 주석을 걷어낸다(하우스 규칙). 문자열 리터럴 안의 `//` 는 남긴다.
private func v0238StrippingComments(_ source: String) -> String {
    var result = ""
    var inString = false, inLine = false, inBlock = false
    var previous: Character = " "
    let characters = Array(source)
    var index = 0
    while index < characters.count {
        let character = characters[index]
        let next: Character? = index + 1 < characters.count ? characters[index + 1] : nil
        if inLine {
            if character == "\n" { inLine = false; result.append(character) }
        } else if inBlock {
            if character == "*", next == "/" { inBlock = false; index += 1 }
        } else if inString {
            if character == "\"", previous != "\\" { inString = false }
            result.append(character)
        } else if character == "/", next == "/" {
            inLine = true; index += 1
        } else if character == "/", next == "*" {
            inBlock = true; index += 1
        } else {
            if character == "\"" { inString = true }
            result.append(character)
        }
        previous = character
        index += 1
    }
    return result
}

/// needle 이 from 이후 처음 나오는 자리(시작·끝). 없으면 nil.
private func v0238Find(_ hay: [Character], _ needle: String, _ from: Int) -> (start: Int, end: Int)? {
    let n = Array(needle)
    guard !n.isEmpty, n.count <= hay.count else { return nil }
    var i = max(0, from)
    while i <= hay.count - n.count {
        var k = 0
        while k < n.count, hay[i + k] == n[k] { k += 1 }
        if k == n.count { return (i, i + n.count) }
        i += 1
    }
    return nil
}

/// openIndex 의 `{` 와 짝이 되는 `}` 자리. 문자열 리터럴 안의 중괄호는 세지 않는다(주석은 이미 걷혀 있다).
private func v0238MatchingBrace(_ hay: [Character], openIndex: Int) -> Int? {
    guard openIndex < hay.count, hay[openIndex] == "{" else { return nil }
    var depth = 0
    var i = openIndex
    var inString = false, inMultiline = false
    while i < hay.count {
        let c = hay[i]
        if inMultiline {
            if c == "\"", i + 2 < hay.count, hay[i + 1] == "\"", hay[i + 2] == "\"" { inMultiline = false; i += 3; continue }
            i += 1; continue
        }
        if inString {
            if c == "\\" { i += 2; continue }
            if c == "\"" || c == "\n" { inString = false }
            i += 1; continue
        }
        if c == "\"" {
            if i + 2 < hay.count, hay[i + 1] == "\"", hay[i + 2] == "\"" { inMultiline = true; i += 3; continue }
            inString = true; i += 1; continue
        }
        if c == "{" { depth += 1 } else if c == "}" {
            depth -= 1
            if depth == 0 { return i }
        }
        i += 1
    }
    return nil
}

/// 계약 한 자리를 본다. `from`…`to` 조각 안에서 `before` 낱말이 순서대로 나오고, **그 뒤 첫** `autoreleasepool {` 의
/// 중괄호 **본문 안**에 `inside` 낱말이 순서대로 있어야 한다. 어긋나면 사람이 읽을 사유를, 맞으면 nil.
private func v0238PoolContractViolation(
    _ source: [Character], from: String, to: String, before: [String], inside: [String]
) -> String? {
    guard let head = v0238Find(source, from, 0) else {
        return "계약이 가리키는 머리('\(from)')를 못 찾았다 — 프로덕션이 옮겨 갔으면 이 계약도 같이 옮겨라(지우지 마라)."
    }
    guard let tail = v0238Find(source, to, head.end) else {
        return "계약이 가리키는 꼬리('\(to)')를 못 찾았다 — 프로덕션이 옮겨 갔으면 이 계약도 같이 옮겨라(지우지 마라)."
    }
    var cursor = head.end
    for needle in before {
        guard let hit = v0238Find(source, needle, cursor), hit.start < tail.start else {
            return "'\(needle)' 를 조각 안에서 못 찾았다 — 루프/클로저 모양이 바뀌었다."
        }
        cursor = hit.end
    }
    let anchor = before.last.map { "'\($0)' 뒤" } ?? "조각 머리 뒤"
    guard let pool = v0238Find(source, "autoreleasepool {", cursor), pool.start < tail.start else {
        return "\(anchor)에 autoreleasepool 이 없다 — 풀이 빠졌거나 루프/클로저 **밖**으로 나갔다."
    }
    let open = pool.end - 1          // 'autoreleasepool {' 의 마지막 글자가 여는 중괄호다
    guard let close = v0238MatchingBrace(source, openIndex: open) else {
        return "\(anchor)의 autoreleasepool 에서 중괄호 짝을 못 찾았다 — 계약 검사기가 못 읽는 모양이다."
    }
    var bodyCursor = open + 1
    for needle in inside {
        guard let hit = v0238Find(source, needle, bodyCursor), hit.start < close else {
            return "'\(needle)' 가 autoreleasepool **본문 안**에 없다 — 빈 풀 껍데기만 두고 본문을 풀 밖으로 뺐거나(변종 F) 풀이 옮겨 갔다."
        }
        bodyCursor = hit.end
    }
    return nil
}

/// 일곱 자리 전부: 청크 풀 둘(증분·진단) + 라인 풀 셋(Claude·Codex·진단) + **항목 풀 둘**(recentFiles·진단 rolloutFiles).
/// `before` 는 "풀이 이 루프/클로저 **안**에 있다"를, `inside` 는 "그 풀이 **본문을 실제로 감싼다**"를 못 박는다.
///
/// 항목 풀 둘은 값 테스트가 원리적으로 못 잡는 자리라(훑은 파일 개수에 비례 — 픽스처로는 신호 0, 변종 E 실측),
/// 이 계약이 유일한 그물이다. 진단 `rolloutFiles` 는 `recentFiles` 의 쌍둥이인데 mtime 프리필터가 없어 **전량**을
/// 훑고, `codexDiagnosticsIfUnreported` 가 빌드×날짜 도장으로 하루 1회 자동 실행한다.
@Test
func tokenScannerWrapsEveryChunkAndLineLoopInAnAutoreleasePool() throws {
    let scanner = Array(v0238StrippingComments(try CheckCoreSourceLayout.joinedSplitSource("CheckTokenUsage.swift")))
    let diagnosticsURL = CheckCoreSourceLayout.coreDirectory.appendingPathComponent("CheckTokenUsageDiagnostics.swift")
    let diagnostics = Array(v0238StrippingComments(try String(contentsOf: diagnosticsURL, encoding: .utf8)))

    let sites: [(name: String, source: [Character], from: String, to: String, before: [String], inside: [String])] = [
        ("readTail 청크 풀", scanner, "private static func readTail(", "return (consumed, bytesRead)",
         ["while"], ["handle.read(upToCount:"]),
        ("scanCodex 라인 풀", scanner, "private static func scanCodex(", "stats.codexFilesRead += 1",
         ["readTail(at: f.url, from: startOffset, { line in"], ["JSONSerialization.jsonObject("]),
        ("ingestClaudeLine 라인 풀", scanner, "private static func ingestClaudeLine(", "private static func ingest(",
         ["contains(line, usagePattern)"], ["JSONSerialization.jsonObject("]),
        ("recentFiles 항목 풀", scanner, "private static func recentFiles(", "return out",
         ["for case let url as URL in enumerator"], ["url.resourceValues(forKeys:"]),
        ("진단 streamLines 청크 풀", diagnostics, "private static func streamLines(", "if !carry.isEmpty",
         ["while"], ["handle.read(upToCount:"]),
        ("진단 ingest 라인 풀", diagnostics, "func ingest(_ line: UnsafeRawBufferPointer) {", "sightings[key] = KeySighting(",
         [], ["JSONSerialization.jsonObject("]),
        ("진단 rolloutFiles 항목 풀", diagnostics, "private static func rolloutFiles(", "return out",
         ["for case let url as URL in enumerator"], ["url.resourceValues(forKeys:"]),
    ]

    for site in sites {
        if let violation = v0238PoolContractViolation(
            site.source, from: site.from, to: site.to, before: site.before, inside: site.inside
        ) {
            Issue.record("""
                \(site.name): \(violation)
                풀이 빠지거나 본문을 안 감싸면 한 청크 분량(라인 풀) · 읽은 바이트 전부(청크 풀) · 훑은 파일 개수에
                비례한 메타데이터(항목 풀)가 그대로 메모리에 쌓인다.
                """)
        }
    }
}

// MARK: - M4 해시 키 (정의 고정 · 16진 왕복 · 문자열 조회 호환)

/// 키의 정의는 "옛 dedupe 문자열 id\0requestId 의 SHA-256 앞 16바이트"다. 앱 재시작·업그레이드 뒤에도 디스크의 키가
/// 같은 엔트리를 가리켜야 하므로 벡터로 못 박는다(프로세스 시드가 섞이는 Swift Hasher 를 쓰면 매 실행 다른 키가 된다).
@Test
func entryKeyIsSHA256PrefixOfLegacyDedupeString() {
    let k = ClaudeEntryKey(messageID: "a", requestID: "b")
    #expect(k.hex == "59b271ae1bbcb1d31d41929817f4b16f")                   // python: sha256(b"a\x00b").hexdigest()[:32]
    #expect(k == ClaudeEntryKey(dedupeString: "a\u{0}b"))                  // 두 이니셜라이저는 같은 정의
    #expect(ClaudeEntryKey(messageID: "msg_k1", requestID: "req_k1").hex == "684fd34e08540c6376199d3587d6252f")
    // NUL 구분자: ("ab","") 와 ("a","b") 와 ("","ab") 는 서로 다른 키다.
    #expect(ClaudeEntryKey(messageID: "ab", requestID: "").hex == "969caaeb3626c0d5695eefa6aea53305")
    #expect(ClaudeEntryKey(messageID: "ab", requestID: "") != k)
    #expect(ClaudeEntryKey(messageID: "", requestID: "ab") != k)
    #expect(ClaudeEntryKey(messageID: "", requestID: "ab") != ClaudeEntryKey(messageID: "ab", requestID: ""))
}

@Test
func entryKeyRoundTripsThroughHexAndCodable() throws {
    let k = ClaudeEntryKey(messageID: "msg_01ABCDEFGHIJKLMNOPQRSTUV", requestID: "req_011CSXYZ0123456789abcdef")
    #expect(k.hex.count == 32)
    #expect(ClaudeEntryKey(hex: k.hex) == k)
    #expect(ClaudeEntryKey(hex: k.hex.uppercased()) == k)              // 대문자도 받는다
    #expect(ClaudeEntryKey(hex: String(k.hex.dropLast())) == nil)      // 31자
    #expect(ClaudeEntryKey(hex: k.hex + "0") == nil)                    // 33자
    #expect(ClaudeEntryKey(hex: "zz" + String(k.hex.dropFirst(2))) == nil) // 16진 아님
    #expect(ClaudeEntryKey(hex: "msg\u{0}req") == nil)                  // 옛 문자열 키는 절대 16진으로 안 읽힌다
    // Codable 은 단일값 16진 문자열.
    let data = try JSONEncoder().encode(k)
    #expect(String(decoding: data, as: UTF8.self) == "\"\(k.hex)\"")
    #expect(try JSONDecoder().decode(ClaudeEntryKey.self, from: data) == k)
    #expect(throws: DecodingError.self) { try JSONDecoder().decode(ClaudeEntryKey.self, from: Data("\"nope\"".utf8)) }
}

/// 문자열 조회(옛 dedupe 문자열)는 프로덕션 ingest 가 (id, requestId) 로 넣은 엔트리에 닿고, 저장→로드 뒤에도 같다.
@Test
func entryKeyLookupByLegacyStringMatchesIngestAndSurvivesDiskRoundTrip() {
    let home = v0238TempDir("keylookup")
    let dir = v0238TempDir("keylookup-cache")
    defer { try? FileManager.default.removeItem(at: home); try? FileManager.default.removeItem(at: dir) }
    _ = v0238WriteOracleFixture(into: home)
    let r = TokenUsageIncrementalScanner.update(TokenUsageCache(), homeDirectory: home, now: v0238Now)

    #expect(r.cache.claudeEntries["msg_k1\u{0}req_k1"]?.input == 100)
    #expect(r.cache.claudeEntries["msg_k2\u{0}req_k2"]?.output == 688)
    #expect(r.cache.claudeEntries[ClaudeEntryKey(messageID: "msg_k5", requestID: "req_k5")]?.input == 7)
    #expect(r.cache.claudeEntries["msg_k4\u{0}req_k4"]?.input == 5000)   // 6/21 은 12주 창 안(v0.2.43) — 보관되나 합계 밖
    #expect(r.cache.claudeEntries.count == 5)                            // k1 k2 k3 k4 k5

    let base = v0238CacheURL(in: dir)
    #expect(TokenUsageCacheStore.save(r.cache, parts: .all, to: base))
    let loaded = TokenUsageCacheStore.load(from: base)
    #expect(loaded == r.cache)
    #expect(loaded.claudeEntries["msg_k3\u{0}req_k3"]?.input == 1000)
    // 콜드 파일은 16진 키 오브젝트다(옛 NUL 문자열 키 없음).
    let cold = try! JSONSerialization.jsonObject(with: Data(contentsOf: TokenUsageCacheStore.entriesURL(for: base))) as! [String: Any]
    #expect(cold.count == 5)
    #expect(cold.keys.allSatisfy { ClaudeEntryKey(hex: $0) != nil })
}

// MARK: - Q6 보관 경계 (월 시작 − 48h)

/// Claude 는 12주 잔디 창 시작 − 48h(KST 04-18 00:00) 부터 남고 그 이전은 지워진다(엔트리·파일상태). Codex 파일상태는 월 시작 − 48h
/// (KST 06-29) 그대로다(v0.2.43 — Codex 는 월 창 유지). v0.2.38~42 는 Claude 도 월 시작 − 48h 였고, v0.2.37 은 직전 월 1일부터였다.
/// 뮤테이션: Claude 경계를 월 시작 − 48h 로 되돌리면 창 안 엔트리(−20d)가 사라져 빨강, Codex 경계를 창으로 옮기면 drop-rollout 이 살아남아 빨강.
@Test
func retentionKeepsTheTwelveWeekWindowAndEvictsOlder() {
    let window = TokenUsageIncrementalScanner.windowBounds(now: v0238Now)
    #expect(window.startKey == "2026-04-20")                               // 07-14(화) 의 주 월요일 07-13 − 12주
    let boundary = window.retentionStart                                  // KST 04-18 00:00
    let codexBoundary = v0238MonthStart.addingTimeInterval(-48 * 3_600)   // KST 06-29 00:00
    var cache = TokenUsageCache()
    cache.claudeEntries["in\u{0}m"] = ClaudeEntry(ts14: v0238TS14(v0238Now.addingTimeInterval(-5 * 86_400)), input: 111, output: 0, cacheRead: 0, cacheCreation: 0)
    cache.claudeEntries["edge-in\u{0}m"] = ClaudeEntry(ts14: v0238TS14(boundary), input: 222, output: 0, cacheRead: 0, cacheCreation: 0)                       // 경계 정각 → 보관
    cache.claudeEntries["edge-out\u{0}m"] = ClaudeEntry(ts14: v0238TS14(boundary.addingTimeInterval(-1)), input: 333, output: 0, cacheRead: 0, cacheCreation: 0) // 1초 전 → 퇴거
    cache.claudeEntries["prev\u{0}m"] = ClaudeEntry(ts14: v0238TS14(v0238MonthStart.addingTimeInterval(-20 * 86_400)), input: 444, output: 0, cacheRead: 0, cacheCreation: 0) // 지난달 본체(6/11, 창 안) → 보관
    let micros = { (d: Date) in Int((d.timeIntervalSince1970 * 1_000_000).rounded()) }
    cache.claudeFileStates["/keep.jsonl"] = FileProgress(size: 1, mtimeMicros: micros(boundary.addingTimeInterval(3_600)), consumedOffset: 1)
    cache.claudeFileStates["/drop.jsonl"] = FileProgress(size: 1, mtimeMicros: micros(boundary.addingTimeInterval(-3_600)), consumedOffset: 1)
    cache.codexFileStates["/keep-rollout.jsonl"] = CodexFileProgress(size: 1, mtimeMicros: micros(codexBoundary), consumedOffset: 1, prevInput: 1, prevOutput: 0, prevCached: 0, monthKey: "2026-06", monthInput: 0, monthOutput: 0, monthCached: 0, dayContrib: [:])
    cache.codexFileStates["/drop-rollout.jsonl"] = CodexFileProgress(size: 1, mtimeMicros: micros(codexBoundary.addingTimeInterval(-1)), consumedOffset: 1, prevInput: 1, prevOutput: 0, prevCached: 0, monthKey: "2026-06", monthInput: 0, monthOutput: 0, monthCached: 0, dayContrib: [:])

    let home = v0238TempDir("retention")   // 로그 없음 — 퇴거/합계만
    let r = TokenUsageIncrementalScanner.update(cache, homeDirectory: home, now: v0238Now)

    #expect(r.cache.claudeEntries["in\u{0}m"] != nil)
    #expect(r.cache.claudeEntries["edge-in\u{0}m"] != nil)
    #expect(r.cache.claudeEntries["edge-out\u{0}m"] == nil)
    #expect(r.cache.claudeEntries["prev\u{0}m"] != nil)
    #expect(r.cache.claudeEntries.count == 3)
    #expect(r.cache.claudeFileStates.keys.sorted() == ["/keep.jsonl"])
    #expect(r.cache.codexFileStates.keys.sorted() == ["/keep-rollout.jsonl"])
    #expect(r.usage.claudeInput == 111)                 // 합계는 여전히 현재 월만(보관된 4/18·6/11 엔트리는 합계 밖)
    #expect(r.usage.claudeDaily["2026-06-11"] == 444)   // 창 안의 지난 날은 일별 맵(잔디)에 남는다
    #expect(r.usage.claudeDaily["2026-04-18"] == nil)   // 창 앞 48h straddle 분은 부분값이라 일별 맵에 넣지 않는다
    #expect(r.stats.entriesChanged == true)             // 콜드 변경
    #expect(r.stats.statesChanged == true)              // 핫 변경
    #expect(r.stats.changedParts == .all)
}

/// ingest 가드도 같은 경계다(v0.2.43: 12주 창 시작 − 48h): 파일이 열리더라도 창 시작 −49h 라인은 저장조차 안 되고 −47h 라인은 저장된다(합계 밖).
@Test
func ingestGuardUsesSameRetentionBoundaryAsEviction() {
    let home = v0238TempDir("ingestguard")
    defer { try? FileManager.default.removeItem(at: home) }
    let windowStart = TokenUsageIncrementalScanner.windowBounds(now: v0238Now).start   // KST 04-20 00:00
    let inside = v0238ClaudeLine(id: "i", req: "i", at: windowStart.addingTimeInterval(-47 * 3_600), usage: "{\"input_tokens\":10}")
    let outside = v0238ClaudeLine(id: "o", req: "o", at: windowStart.addingTimeInterval(-49 * 3_600), usage: "{\"input_tokens\":20}")
    let current = v0238ClaudeLine(id: "c", req: "c", at: v0238Now, usage: "{\"input_tokens\":30}")
    v0238Write([inside, outside, current].joined(separator: "\n") + "\n", to: v0238ClaudeURL(home, "p", "s.jsonl"))

    let r = TokenUsageIncrementalScanner.update(TokenUsageCache(), homeDirectory: home, now: v0238Now)

    #expect(r.cache.claudeEntries["i\u{0}i"] != nil)
    #expect(r.cache.claudeEntries["o\u{0}o"] == nil)
    #expect(r.cache.claudeEntries.count == 2)
    #expect(r.usage.claudeInput == 30)
}

/// 월 경계를 걸치는 세션(월말 밤 시작 → 월초 새벽까지). 증분(6월 마지막 스캔의 캐시 이어받기)과 전량(빈 캐시) 결과가
/// 월초·월중·다음 달까지 매 시점 같아야 한다 — 48h 보관이 straddle dedupe(같은 키의 지난달/이번달 라인)를 정확히 덮는 증명.
@Test
func monthBoundaryStraddleTotalsAreInvariantBetweenIncrementalAndFullScan() {
    let home = v0238TempDir("straddle")
    defer { try? FileManager.default.removeItem(at: home) }
    let url = v0238ClaudeURL(home, "p", "session.jsonl")
    let kst = { (utc: String) in v0238UTC(utc) }
    let now1 = kst("2026-06-30T14:50:00Z")   // KST 06-30 23:50 (6월)
    let now2 = kst("2026-06-30T16:00:00Z")   // KST 07-01 01:00 (7월 초)
    let now3 = kst("2026-07-20T03:00:00Z")   // KST 07-20 12:00 (7월 중)
    let now4 = kst("2026-08-02T15:00:00Z")   // KST 08-03 00:00 (8월)

    // 6월 밤: a(6월만), b 의 첫 스냅샷.
    let a = v0238ClaudeLine(id: "a", req: "a", at: kst("2026-06-30T13:00:00Z"), usage: "{\"input_tokens\":10,\"output_tokens\":1}")
    let b1 = v0238ClaudeLine(id: "b", req: "b", at: kst("2026-06-30T14:40:00Z"), usage: "{\"input_tokens\":1,\"output_tokens\":5}")
    v0238Write([a, b1].joined(separator: "\n") + "\n", to: url, modified: now1)
    let june = TokenUsageIncrementalScanner.update(TokenUsageCache(), homeDirectory: home, now: now1)
    #expect(june.usage.month == "2026-06")
    #expect(june.usage.claudeInput == 11)

    // 자정 넘김: b 의 최종 스냅샷(7월, 더 큰 output), c(7월), d 는 reverse-straddle(6월 라인이 더 큰 output, 7월 라인이 더 최신).
    let b2 = v0238ClaudeLine(id: "b", req: "b", at: kst("2026-06-30T15:00:20Z"), usage: "{\"input_tokens\":2,\"output_tokens\":700}")
    let c = v0238ClaudeLine(id: "c", req: "c", at: kst("2026-06-30T15:30:00Z"), usage: "{\"input_tokens\":100}")
    let d1 = v0238ClaudeLine(id: "d", req: "d", at: kst("2026-06-30T14:59:50Z"), usage: "{\"input_tokens\":9,\"output_tokens\":300}")
    let d2 = v0238ClaudeLine(id: "d", req: "d", at: kst("2026-06-30T15:00:05Z"), usage: "{\"input_tokens\":3,\"output_tokens\":100}")
    v0238Append([b2, c, d1, d2].joined(separator: "\n") + "\n", to: url, modified: now2)

    let inc2 = TokenUsageIncrementalScanner.update(june.cache, homeDirectory: home, now: now2)
    let full2 = TokenUsageIncrementalScanner.update(TokenUsageCache(), homeDirectory: home, now: now2)
    #expect(inc2.usage.month == "2026-07")
    // 7월: b(2/700) + c(100) + d(max-output 300 레코드의 9, 관측 최대 ts 가 7월이라 7월로). a 는 6월이라 밖.
    #expect(inc2.usage.claudeInput == 111)
    #expect(inc2.usage.claudeOutput == 1_000)
    #expect(inc2.usage == full2.usage)
    #expect(inc2.cache.claudeEntries == full2.cache.claudeEntries)
    #expect(inc2.cache.claudeEntries["a\u{0}a"] != nil)      // 6/30 라인은 48h 창 안이라 보관(합계 밖)
    #expect(inc2.stats.claudeBytesRead == [b2, c, d1, d2].joined(separator: "\n").utf8.count + 1)   // 이어읽기(새 바이트만)

    // 7월 중: 파일 무변경. 증분은 재읽기 0 이고, 전량과 같다. 6월 straddle 엔트리는 아직 보관(경계는 7월 내내 6/29).
    let inc3 = TokenUsageIncrementalScanner.update(inc2.cache, homeDirectory: home, now: now3)
    let full3 = TokenUsageIncrementalScanner.update(TokenUsageCache(), homeDirectory: home, now: now3)
    #expect(inc3.stats.claudeBytesRead == 0)
    #expect(inc3.stats.cacheChanged == false)
    #expect(inc3.usage == full3.usage)
    #expect(inc3.usage.claudeOutput == 1_000)
    #expect(inc3.cache.claudeEntries.count == 4)

    // 8월(v0.2.43): 12주 창(05-11~)이라 6/30·7/1 엔트리는 아직 보관되고 파일(mtime 7/1)도 창 안이라 열린다 — 8월 합계는 0 이고
    // 증분·전량이 같으며, 일별 맵에는 지난 두 달의 날이 남는다(잔디가 보는 값). 재읽기·퇴거는 없다.
    let inc4 = TokenUsageIncrementalScanner.update(inc3.cache, homeDirectory: home, now: now4)
    let full4 = TokenUsageIncrementalScanner.update(TokenUsageCache(), homeDirectory: home, now: now4)
    #expect(inc4.usage.month == "2026-08")
    #expect(inc4.usage.total == 0)
    #expect(inc4.usage == full4.usage)
    #expect(inc4.cache.claudeEntries.count == 4)
    #expect(inc4.cache.claudeFileStates.count == 1)
    #expect(inc4.usage.claudeDaily["2026-07-01"] == 1_111)   // KST 7/1: b(2+700) + c(100) + d(max-output 레코드 9+300)
    #expect(inc4.usage.claudeDaily["2026-06-30"] == 11)      // a(10+1)
    #expect(inc4.stats.claudeBytesRead == 0 && inc4.stats.cacheChanged == false)

    // 10월(KST 10-05 월요일 0시): 창이 7/13 로 옮겨(보관 하한 7/11) 6·7월 초 엔트리가 전부 퇴거되고 파일(mtime 7/1)도 창 밖이라 닫힌다. 전량도 0.
    let now5 = kst("2026-10-04T15:00:00Z")   // KST 10-05 00:00 (10월)
    let inc5 = TokenUsageIncrementalScanner.update(inc4.cache, homeDirectory: home, now: now5)
    let full5 = TokenUsageIncrementalScanner.update(TokenUsageCache(), homeDirectory: home, now: now5)
    #expect(inc5.usage.month == "2026-10")
    #expect(inc5.usage.total == 0)
    #expect(inc5.usage == full5.usage)
    #expect(inc5.cache.claudeEntries.isEmpty)
    #expect(inc5.cache.claudeFileStates.isEmpty)
    #expect(inc5.stats.entriesChanged == true && inc5.stats.statesChanged == true)
}

// MARK: - 핫/콜드 분리 (파일 레이아웃 · 부분 저장 · 세대 게이트)

private func v0238FileBytes(_ url: URL) -> Data? { try? Data(contentsOf: url) }

/// 저장은 더러워진 쪽만 다시 쓴다: codex 만 바뀐 저장은 콜드 파일을 한 바이트도 안 건드리고, 로드는 두 파일의 합이다.
@Test
func partialSaveRewritesOnlyDirtyFileAndLoadMergesBoth() {
    let dir = v0238TempDir("partial")
    defer { try? FileManager.default.removeItem(at: dir) }
    let base = v0238CacheURL(in: dir)
    let stateURL = TokenUsageCacheStore.stateURL(for: base)
    let entriesURL = TokenUsageCacheStore.entriesURL(for: base)
    #expect(stateURL.lastPathComponent == "cache.state.json")
    #expect(entriesURL.lastPathComponent == "cache.entries.json")

    var cache = TokenUsageCache()
    cache.claudeEntries["m1\u{0}r1"] = ClaudeEntry(ts14: 20_260_710_000_000, input: 1, output: 2, cacheRead: 3, cacheCreation: 4)
    cache.claudeFileStates["/a.jsonl"] = FileProgress(size: 10, mtimeMicros: 999, consumedOffset: 8)
    cache.codexFileStates["/r.jsonl"] = CodexFileProgress(size: 5, mtimeMicros: 1, consumedOffset: 5, prevInput: 100, prevOutput: 0, prevCached: 0, monthKey: "2026-07", monthInput: 7, monthOutput: 0, monthCached: 0, dayContrib: ["2026-07-14": 7])

    // 처음엔 어느 부분만 요청해도 둘 다 만들어진다(없는 파일은 항상 채운다 — 핫만 있는 쌍은 로드에서 폐기되므로).
    #expect(TokenUsageCacheStore.save(cache, parts: [.state], to: base))
    #expect(FileManager.default.fileExists(atPath: entriesURL.path))
    #expect(TokenUsageCacheStore.load(from: base) == cache)
    let coldBytes1 = v0238FileBytes(entriesURL)
    let hotBytes1 = v0238FileBytes(stateURL)

    // codex 상태만 바뀐 저장(핫만): 콜드 파일 불변.
    cache.codexFileStates["/r.jsonl"]?.monthInput = 70
    #expect(TokenUsageCacheStore.save(cache, parts: [.state], to: base))
    #expect(v0238FileBytes(entriesURL) == coldBytes1)
    #expect(v0238FileBytes(stateURL) != hotBytes1)
    #expect(TokenUsageCacheStore.load(from: base) == cache)
    let hotBytes2 = v0238FileBytes(stateURL)

    // 엔트리만 바뀐 저장(콜드만): 핫 파일 불변.
    cache.claudeEntries["m2\u{0}r2"] = ClaudeEntry(ts14: 20_260_711_000_000, input: 5, output: 6, cacheRead: 7, cacheCreation: 8)
    #expect(TokenUsageCacheStore.save(cache, parts: [.entries], to: base))
    #expect(v0238FileBytes(stateURL) == hotBytes2)
    #expect(v0238FileBytes(entriesURL) != coldBytes1)
    #expect(TokenUsageCacheStore.load(from: base) == cache)

    // 핫 파일 본문엔 엔트리가 비어 있다(엔트리는 콜드에만).
    let hot = try! JSONSerialization.jsonObject(with: v0238FileBytes(stateURL)!) as! [String: Any]
    #expect(hot["schemaVersion"] as? Int == TokenUsageCacheStore.currentSchemaVersion)
    #expect(((hot["state"] as? [String: Any])?["claudeEntries"] as? [String: Any])?.isEmpty == true)
}

/// 스캐너의 changedParts 가 핫/콜드를 가른다: codex 만 자라면 핫만, Claude usage 라인이 붙으면 둘 다, 무변경이면 없음.
@Test
func scannerReportsWhichCachePartChanged() {
    let home = v0238TempDir("parts")
    defer { try? FileManager.default.removeItem(at: home) }
    let evt = v0238UTC("2026-07-05T00:00:00Z")
    let rollout = v0238CodexURL(home, "2026/07/05/rollout-2026-07-05T00-00-00-aaaa.jsonl")
    v0238Write(v0238CodexLine(input: 100, output: 0, at: evt) + "\n", to: rollout)
    let claude = v0238ClaudeURL(home, "p", "s.jsonl")
    v0238Write(v0238ClaudeLine(id: "a", req: "a", at: evt, usage: "{\"input_tokens\":1}") + "\n", to: claude)

    let r1 = TokenUsageIncrementalScanner.update(TokenUsageCache(), homeDirectory: home, now: v0238Now)
    #expect(r1.stats.changedParts == .all)

    let r2 = TokenUsageIncrementalScanner.update(r1.cache, homeDirectory: home, now: v0238Now)
    #expect(r2.stats.changedParts.isEmpty)

    v0238Append(v0238CodexLine(input: 200, output: 0, at: evt) + "\n", to: rollout, modified: v0238Now.addingTimeInterval(1))
    let r3 = TokenUsageIncrementalScanner.update(r2.cache, homeDirectory: home, now: v0238Now)
    #expect(r3.stats.changedParts == [.state])
    #expect(r3.usage.codexInput == 100)

    // Claude 파일이 자랐지만 usage 라인이 아니면(사용자 메시지) 핫만.
    v0238Append(v0238UserLine(at: evt) + "\n", to: claude, modified: v0238Now.addingTimeInterval(2))
    let r4 = TokenUsageIncrementalScanner.update(r3.cache, homeDirectory: home, now: v0238Now)
    #expect(r4.stats.changedParts == [.state])

    v0238Append(v0238ClaudeLine(id: "b", req: "b", at: evt, usage: "{\"input_tokens\":2}") + "\n", to: claude, modified: v0238Now.addingTimeInterval(3))
    let r5 = TokenUsageIncrementalScanner.update(r4.cache, homeDirectory: home, now: v0238Now)
    #expect(r5.stats.changedParts == .all)
    #expect(r5.usage.claudeInput == 3)
}

/// 세대 게이트: v0.2.37 이하의 단일 파일은 읽지 않고 지운다. 핫의 schemaVersion 이 다르거나, 두 파일 중 하나가 없거나,
/// 콜드가 손상(16진 아닌 키)이면 전부 빈 캐시(→ 재스캔). 손상 처리 경로 하나로 모인다.
@Test
func cacheLoadDiscardsLegacyAndMismatchedGenerations() throws {
    let dir = v0238TempDir("gate")
    defer { try? FileManager.default.removeItem(at: dir) }
    let base = v0238CacheURL(in: dir)
    let stateURL = TokenUsageCacheStore.stateURL(for: base)
    let entriesURL = TokenUsageCacheStore.entriesURL(for: base)

    // 1) 옛 단일 파일(모놀리식, 문자열 키)만 있는 맥: 빈 캐시 + 파일 삭제.
    let legacy = """
    {"claudeFileStates":{"/a/b.jsonl":[10,999,8]},"claudeEntries":{"msg\\u0000req":[20260722103000,1,2,3,4]},\
    "codexFileStates":{"/p/rollout.jsonl":[10,20,30,40,"2026-07",50,"2026-07-14",60]},"codexSchemaVersion":3}
    """
    v0238Write(legacy, to: base)
    #expect(TokenUsageCacheStore.load(from: base) == TokenUsageCache())
    #expect(FileManager.default.fileExists(atPath: base.path) == false)

    // 2) 정상 쌍은 그대로 왕복한다.
    var cache = TokenUsageCache()
    cache.claudeEntries["m\u{0}r"] = ClaudeEntry(ts14: 20_260_710_000_000, input: 1, output: 2, cacheRead: 3, cacheCreation: 4)
    cache.claudeFileStates["/a.jsonl"] = FileProgress(size: 10, mtimeMicros: 999, consumedOffset: 8)
    #expect(TokenUsageCacheStore.save(cache, parts: .all, to: base))
    #expect(TokenUsageCacheStore.load(from: base) == cache)

    // 3) 핫의 세대가 다르면(옛 세대) 전부 폐기.
    var hot = try JSONSerialization.jsonObject(with: Data(contentsOf: stateURL)) as! [String: Any]
    hot["schemaVersion"] = TokenUsageCacheStore.currentSchemaVersion - 1
    try JSONSerialization.data(withJSONObject: hot).write(to: stateURL)
    #expect(TokenUsageCacheStore.load(from: base) == TokenUsageCache())
    hot["schemaVersion"] = TokenUsageCacheStore.currentSchemaVersion
    try JSONSerialization.data(withJSONObject: hot).write(to: stateURL)
    #expect(TokenUsageCacheStore.load(from: base) == cache)

    // 4) 콜드가 없으면(핫만 살아남은 쌍) 폐기 — 핫이 앞서면 "소비한 오프셋인데 엔트리 없음" = 과소집계라서.
    let coldBytes = try Data(contentsOf: entriesURL)
    try FileManager.default.removeItem(at: entriesURL)
    #expect(TokenUsageCacheStore.load(from: base) == TokenUsageCache())
    try coldBytes.write(to: entriesURL)
    #expect(TokenUsageCacheStore.load(from: base) == cache)

    // 5) 콜드 손상(16진 아닌 키): 폐기.
    try Data("{\"msg\\u0000req\":[20260722103000,1,2,3,4]}".utf8).write(to: entriesURL)
    #expect(TokenUsageCacheStore.load(from: base) == TokenUsageCache())

    // 6) 핫만 없어도 폐기(콜드만으론 이어읽기 기준이 없다 — 재스캔이 dedupe 로 같은 값을 만든다).
    try coldBytes.write(to: entriesURL)
    try FileManager.default.removeItem(at: stateURL)
    #expect(TokenUsageCacheStore.load(from: base) == TokenUsageCache())
}

/// 스토어 경로로 본 세대 업: 옛 단일 파일이 "이 픽스처는 이미 끝까지 소비했다"고 주장해도(엔트리는 없음) 믿지 않고
/// 재스캔해 값이 나온다. 믿었다면 0 이었을 것이다(과소집계). 옛 파일은 지워지고 새 쌍이 그 자리에 생긴다.
@MainActor
@Test
func storeRescansWhenOnDiskCacheIsFromOlderGeneration() async throws {
    let home = v0238TempDir("gen-home")
    let dir = v0238TempDir("gen-cache")
    let suite = CheckTestScratch.suitePath(named: "check-v0238-token-generation")
    let defaults = v0238Defaults(suite)
    defer {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: home); try? FileManager.default.removeItem(at: dir)
    }
    _ = v0238WriteOracleFixture(into: home)
    let base = v0238CacheURL(in: dir)

    // 실제 스캔으로 경로 키(심볼릭 정규화된 실경로)를 얻어, 엔트리만 비운 옛 모놀리식 JSON 을 베이스 자리에 놓는다.
    var stale = TokenUsageIncrementalScanner.update(TokenUsageCache(), homeDirectory: home, now: v0238Now).cache
    stale.claudeEntries = [:]
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try JSONEncoder().encode(stale).write(to: base)

    let center = NotificationCenter()
    let store = TokenUsageStore(defaults: defaults, homeDirectory: home, cacheURL: base, clock: { v0238Now }, notificationCenter: center)
    await store.refreshIfStale()

    #expect(store.currentMonthUsage?.claudeInput == 118)   // 옛 파일을 믿었다면 0
    #expect(store.currentMonthUsage?.total == 1_574)
    #expect(FileManager.default.fileExists(atPath: base.path) == false)

    // 종료 훅으로 저장을 강제하면 새 쌍이 생기고, 새 스토어는 그 쌍으로 재읽기 0 에 같은 값을 낸다.
    center.post(name: NSApplication.willTerminateNotification, object: nil)
    let reloaded = TokenUsageCacheStore.load(from: base)
    #expect(reloaded.claudeEntries.count == 5)   // k1 k2 k3 k4 k5 — 12주 창(v0.2.43)이라 6/21 의 k4 도 남는다
    let again = TokenUsageIncrementalScanner.update(reloaded, homeDirectory: home, now: v0238Now)
    #expect(again.stats.claudeBytesRead == 0)
    #expect(again.usage.total == 1_574)
}

// MARK: - Q5 저장 스로틀 · 루프 종료 저장 · 종료 훅

/// clock 주입용 참조 박스.
@MainActor
private final class V0238Clock {
    var now: Date
    init(_ now: Date) { self.now = now }
}

/// 스로틀 시나리오용 스토어 + 성장하는 픽스처. 매 단계 새 usage 라인을 붙여 스캔이 항상 캐시를 더럽히게 한다.
@MainActor
private struct V0238ThrottleRig {
    let home: URL
    let dir: URL
    let base: URL
    let url: URL
    let clock: V0238Clock
    let center = NotificationCenter()
    let store: TokenUsageStore
    var lines = 0

    init(suite: String, defaults: UserDefaults) {
        home = v0238TempDir("throttle-home-" + suite)
        dir = v0238TempDir("throttle-cache-" + suite)
        base = v0238CacheURL(in: dir)
        url = v0238ClaudeURL(home, "p", "s.jsonl")
        clock = V0238Clock(v0238Now)
        v0238Write("", to: url, modified: v0238Now)
        let box = clock
        store = TokenUsageStore(defaults: defaults, homeDirectory: home, cacheURL: base, clock: { box.now }, notificationCenter: center)
    }

    /// 시각을 t0+seconds 로 옮기고 usage 라인 하나를 붙인 뒤(mtime 도 그 시각) 갱신한다.
    mutating func advanceAppendAndRefresh(to seconds: TimeInterval) async {
        clock.now = v0238Now.addingTimeInterval(seconds)
        lines += 1
        v0238Append(v0238ClaudeLine(id: "m\(lines)", req: "r\(lines)", at: clock.now, usage: "{\"input_tokens\":1}") + "\n",
                    to: url, modified: clock.now)
        await store.refreshIfStale()
    }

    func entriesOnDisk() -> Int? {
        guard let data = try? Data(contentsOf: TokenUsageCacheStore.entriesURL(for: base)),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return obj.count
    }

    func tearDown() {
        try? FileManager.default.removeItem(at: home)
        try? FileManager.default.removeItem(at: dir)
    }
}

/// (a) 저장은 마지막 저장(스토어 생성 시점이 첫 기준) 후 300초 이상 지난 스캔 완료 시점에만. 그 사이 변경은 모였다가 한 번에.
/// 뮤테이션: persistIfDirty 의 간격 조건을 지우면 더러운 스캔마다 저장돼 t0+120 에서 이미 saveCount 1 → 빨강.
@MainActor
@Test
func cacheSaveIsThrottledToFiveMinutesByInjectedClock() async {
    #expect(TokenUsageStore.refreshPeriod == 120)
    #expect(TokenUsageStore.refreshTolerance == 20)
    #expect(TokenUsageStore.saveInterval == 300)
    let suite = CheckTestScratch.suitePath(named: "check-v0238-token-throttle")
    let defaults = v0238Defaults(suite)
    var rig = V0238ThrottleRig(suite: suite, defaults: defaults)
    defer { defaults.removePersistentDomain(forName: suite); rig.tearDown() }

    await rig.advanceAppendAndRefresh(to: 0)          // 첫 스캔: 더러움 1줄, 저장 0 (생성 후 0초)
    #expect(rig.store.scanCount == 1)
    #expect(rig.store.saveCount == 0)
    await rig.advanceAppendAndRefresh(to: 120)        // 120 < 300
    #expect(rig.store.scanCount == 2)
    #expect(rig.store.saveCount == 0)
    await rig.advanceAppendAndRefresh(to: 240)        // 240 < 300
    #expect(rig.store.saveCount == 0)
    #expect(rig.entriesOnDisk() == nil)               // 아직 디스크에 아무것도 없다
    await rig.advanceAppendAndRefresh(to: 300)        // 300 ≥ 300 → 저장 #1 (모인 4줄이 한 번에)
    #expect(rig.store.saveCount == 1)
    await rig.store.awaitPendingSaves()
    #expect(rig.entriesOnDisk() == 4)
    await rig.advanceAppendAndRefresh(to: 420)        // 마지막 저장(300) 후 120 → 저장 안 함
    #expect(rig.store.saveCount == 1)
    await rig.store.awaitPendingSaves()
    #expect(rig.entriesOnDisk() == 4)
    await rig.advanceAppendAndRefresh(to: 600)        // 300 → 저장 #2
    #expect(rig.store.saveCount == 2)
    await rig.store.awaitPendingSaves()
    #expect(rig.entriesOnDisk() == 6)
    // 무변경 스캔은 간격이 차도 저장하지 않는다(더러움 없음).
    rig.clock.now = v0238Now.addingTimeInterval(1_200)
    await rig.store.refreshIfStale()
    #expect(rig.store.scanCount == 7)
    #expect(rig.store.saveCount == 2)
    #expect(rig.store.currentMonthUsage?.claudeInput == 6)
}

/// (b) 팝오버가 닫혀 갱신 루프가 취소되면 더러운 캐시를 1회 저장한다(간격과 무관). 깨끗하면 저장하지 않는다.
@MainActor
@Test
func refreshLoopCancellationPersistsDirtyCacheOnce() async {
    let suite = CheckTestScratch.suitePath(named: "check-v0238-token-loop-cancel")
    let defaults = v0238Defaults(suite)
    var rig = V0238ThrottleRig(suite: suite, defaults: defaults)
    defer { defaults.removePersistentDomain(forName: suite); rig.tearDown() }
    rig.lines += 1
    v0238Append(v0238ClaudeLine(id: "m1", req: "r1", at: v0238Now, usage: "{\"input_tokens\":5}") + "\n", to: rig.url, modified: v0238Now)

    // 팝오버 열림(.task): 즉시 1회 스캔 → 120초 sleep. 스캔 완료까지 기다린 뒤 닫힘(취소)을 모사한다.
    let store = rig.store
    let loop = Task { await store.runRefreshLoop() }
    var spins = 0
    while store.scanCount == 0, spins < 2_000 {
        spins += 1
        try? await Task.sleep(for: .milliseconds(2))
    }
    await store.awaitScanCompletion()
    #expect(store.scanCount == 1)
    #expect(store.currentMonthUsage?.claudeInput == 5)
    #expect(store.saveCount == 0)                        // 300초 전 — 스로틀에 막혀 아직 안 씀

    loop.cancel()
    await loop.value                                     // 루프 종료 지점에서 1회 저장
    #expect(store.saveCount == 1)
    await store.awaitPendingSaves()
    #expect(rig.entriesOnDisk() == 1)
    #expect(TokenUsageCacheStore.load(from: rig.base).claudeEntries["m1\u{0}r1"]?.input == 5)

    // 다시 열었다 닫음(무변경): 스캔은 돌지만 깨끗하니 저장 없음 — "1회"가 "매 닫힘마다"가 아님을 못 박는다.
    rig.clock.now = v0238Now.addingTimeInterval(10)
    let loop2 = Task { await store.runRefreshLoop() }
    spins = 0
    while store.scanCount < 2, spins < 2_000 {
        spins += 1
        try? await Task.sleep(for: .milliseconds(2))
    }
    await store.awaitScanCompletion()
    loop2.cancel()
    await loop2.value
    #expect(store.scanCount == 2)
    #expect(store.saveCount == 1)
}

/// (c) 앱 종료 알림(NSApplication.willTerminateNotification)에서 더러운 캐시를 **동기로** 쓴다 — 알림이 돌아오면 프로세스가
/// 끝나므로 비동기 예약으로는 늦다. 장벽(awaitPendingSaves) 없이 곧바로 디스크에서 읽혀야 한다. 두 번째 알림은 무동작.
@MainActor
@Test
func terminationNotificationPersistsDirtyCacheSynchronously() async {
    let suite = CheckTestScratch.suitePath(named: "check-v0238-token-terminate")
    let defaults = v0238Defaults(suite)
    var rig = V0238ThrottleRig(suite: suite, defaults: defaults)
    defer { defaults.removePersistentDomain(forName: suite); rig.tearDown() }

    await rig.advanceAppendAndRefresh(to: 0)
    #expect(rig.store.saveCount == 0)
    #expect(rig.entriesOnDisk() == nil)

    rig.center.post(name: NSApplication.willTerminateNotification, object: nil)
    #expect(rig.store.saveCount == 1)
    #expect(rig.entriesOnDisk() == 1)                    // 장벽 없이 즉시 — 동기 저장
    #expect(FileManager.default.fileExists(atPath: TokenUsageCacheStore.stateURL(for: rig.base).path))

    rig.center.post(name: NSApplication.willTerminateNotification, object: nil)
    #expect(rig.store.saveCount == 1)                    // 깨끗하면 무동작

    // 종료 뒤 더러워진 변경도(예: 종료 직전 스캔) 다음 알림에 나간다.
    await rig.advanceAppendAndRefresh(to: 10)
    rig.center.post(name: NSApplication.willTerminateNotification, object: nil)
    #expect(rig.store.saveCount == 2)
    #expect(rig.entriesOnDisk() == 2)
}

