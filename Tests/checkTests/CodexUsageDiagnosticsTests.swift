import Foundation
import Testing
@testable import check

// MARK: - Codex 집계 진단 스캐너 테스트
//
// 목적: CodexUsageDiagnosticsScanner.compute 의 각 신호가 **실제로 발화하는지**를 합성 픽스처로 못 박는다.
// 순위판에서 Codex 코호트의 하루당 토큰 중앙값이 Claude 코호트의 20배로 나오는 원인을 현장에서 가르는 계측이므로,
// "신호가 켜져야 할 때 켜지고, 켜지면 안 될 때 안 켜지는가"가 전부다. 특히 dupEvents 는 **파일 간** 재출현만 세야 한다 —
// 같은 파일 안의 반복은 cum == prev 라 델타 0 이고 총합을 부풀리지 않기 때문이다.
//
// 픽스처는 임시 홈 디렉터리에 ~/.codex/sessions/**/rollout-*.jsonl 을 직접 써서 실제 파일 순회·스트리밍·파싱 경로를
// 그대로 태운다(번들 리소스 등록 불필요). 순수 함수만 다루므로 창을 띄우지 않는다.

// MARK: 픽스처 헬퍼

/// 프로덕션 산식과의 대조에 쓰는 고정 시각. 기존 CheckTokenUsageTests 와 같은 값이라 월 해석이 일치한다.
/// 실제 KST 값: 2026-07-14 12:33:20 KST → 현재 KST 월 = "2026-07".
private let diagNow = Date(timeIntervalSince1970: 1_784_000_000)

/// 대상 월(KST). 픽스처 타임스탬프는 전부 이 월 기준으로 설계한다.
private let diagMonth = "2026-07"

/// 고유한 임시 홈 디렉터리(아직 만들지 않음 — 파일을 쓸 때 상위 폴더가 생긴다).
private func diagTempHome() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("check-codex-diag-\(UUID().uuidString)", isDirectory: true)
}

private func diagRolloutURL(_ home: URL, _ path: String) -> URL {
    home.appendingPathComponent(".codex/sessions/\(path)", isDirectory: false)
}

/// 파일을 쓰고 mtime 을 지정한다(기본 diagNow — 프로덕션 스캐너의 mtime 프리필터를 통과시킨다).
/// 진단 스캐너 자체는 mtime 프리필터가 없지만, 대조 산식(TokenUsageScanner)과 같은 픽스처를 공유하려면 필요하다.
@discardableResult
private func diagWrite(_ contents: String, to url: URL, modified: Date = diagNow) -> URL {
    try? FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    try? Data(contents.utf8).write(to: url)
    try? FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
    return url
}

/// Codex token_count 이벤트 한 줄(개행 미포함). cum = input + output 이므로 output 은 0 으로 두고 input 으로 누적치를 준다.
/// timestamp 는 UTC ISO8601 문자열을 그대로 받는다 — 스캐너가 앞 19자만 고정폭으로 읽으므로 소수초 유무는 무관하다.
private func diagEvent(ts: String, cum: Int, output: Int = 0) -> String {
    "{\"timestamp\":\"\(ts)\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\","
    + "\"info\":{\"total_token_usage\":{\"input_tokens\":\(cum),\"cached_input_tokens\":0,"
    + "\"output_tokens\":\(output),\"total_tokens\":0}}}}"
}

/// info 가 null 인 이벤트. 프리체크("token_count")는 통과하지만 total 이 없어 건너뛰어야 하고,
/// **prevCumulative 를 갱신하면 안 된다**(다음 유효 이벤트의 델타가 이 구간을 흡수한다).
private func diagNullInfoEvent(ts: String) -> String {
    "{\"timestamp\":\"\(ts)\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\",\"info\":null}}"
}

/// payload.type 이 token_count 가 아닌 라인. 타입 문자열에 "token_count" 가 부분 문자열로 들어 있어
/// 바이트 프리체크는 통과하지만 타입 비교에서 걸러져야 한다(프리체크만으로 계상되면 이 테스트가 잡는다).
private func diagWrongTypeEvent(ts: String, cum: Int) -> String {
    "{\"timestamp\":\"\(ts)\",\"type\":\"event_msg\",\"payload\":{\"type\":\"not_token_count\","
    + "\"info\":{\"total_token_usage\":{\"input_tokens\":\(cum),\"output_tokens\":0}}}}"
}

/// JSON 으로 파싱되지 않는 깨진 라인(프리체크는 통과).
private let diagBrokenLine = "{\"payload\":{\"type\":\"token_count\", this is not json"

private func diagCompute(_ home: URL, month: String = diagMonth, appBuild: Int = 4242) -> CodexUsageDiagnostics {
    CodexUsageDiagnosticsScanner.compute(homeDirectory: home, month: month, appBuild: appBuild)
}

private func diagCleanup(_ home: URL) {
    try? FileManager.default.removeItem(at: home)
}

// MARK: - 1. dupEvents / dupTokens — 파일 간 재출현만 센다

// 같은 (timestamp, cum) 이 **서로 다른 두 파일**에 나타나면 앱 산식은 두 번 다 델타로 계상한다(파일마다 prevCumulative 가
// 0 에서 시작하므로). 그게 총합을 부풀리는 유일한 경로이고, 진단은 그 몫을 dupTokens 로 떼어 놓아야 한다.
@Test
func codexDiagnosticsCountsDuplicateEventAcrossTwoFiles() {
    let home = diagTempHome()
    let sharedTs = "2026-07-05T01:00:00.000Z"
    // 두 파일이 같은 이벤트를 담는다(세션 resume/포크로 앞부분이 복제된 모양).
    diagWrite(diagEvent(ts: sharedTs, cum: 1_000) + "\n",
              to: diagRolloutURL(home, "2026/07/05/rollout-2026-07-05T01-00-00-aaaa.jsonl"))
    diagWrite(diagEvent(ts: sharedTs, cum: 1_000) + "\n",
              to: diagRolloutURL(home, "2026/07/05/rollout-2026-07-05T02-00-00-bbbb.jsonl"))

    let d = diagCompute(home)

    #expect(d.dupEvents == 1)              // (ts, cum) 키가 2개 파일에 나타났다.
    #expect(d.dupTokens == 1_000)          // 두 번째 출현의 델타가 총합을 부풀린 몫.
    #expect(d.dedupTotal == 1_000)         // 앱 산식 2,000 에서 중복분을 뺀 값.
    #expect(d.finalSum == 2_000)           // 파일별 마지막 누적치 합(1,000 + 1,000).
    #expect(d.filesTotal == 2)
    #expect(d.filesMonth == 2)
    #expect(d.eventsMonth == 2)
    diagCleanup(home)
}

// 한 파일 안에서 같은 (timestamp, cum) 이 반복되는 건 **중복이 아니다** — cum == prevCumulative 라 델타가 0 이고
// 총합에 아무 영향이 없다. 이걸 중복으로 세면 진단이 무고한 파일을 범인으로 지목한다.
@Test
func codexDiagnosticsIgnoresRepeatedEventWithinSameFile() {
    let home = diagTempHome()
    let ts = "2026-07-06T01:00:00.000Z"
    let line = diagEvent(ts: ts, cum: 1_000)
    diagWrite("\(line)\n\(line)\n\(line)\n",
              to: diagRolloutURL(home, "2026/07/06/rollout-2026-07-06T01-00-00-aaaa.jsonl"))

    let d = diagCompute(home)

    #expect(d.dupEvents == 0)              // 파일 수 1 → 중복 아님.
    #expect(d.dupTokens == 0)
    #expect(d.eventsMonth == 3)            // 이벤트 자체는 3건으로 센다.
    #expect(d.dedupTotal == 1_000)         // 2·3번째 델타는 0.
    #expect(d.maxDelta == 1_000)
    diagCleanup(home)
}

// 같은 파일 안의 반복이지만 사이에 누적 리셋이 끼어 두 번째 출현의 델타가 **0 이 아닌** 경우.
// '출현 횟수 ≥ 2' 로 중복을 판정하면 여기서 dupTokens 가 600 만큼 잘못 부풀고 dedupTotal 이 깎인다.
// '파일 수 ≥ 2' 판정만이 이 파일을 무고하게 남긴다.
@Test
func codexDiagnosticsIgnoresSameFileRepeatEvenWhenDeltaIsNonZero() {
    let home = diagTempHome()
    let ts1 = "2026-07-07T01:00:00.000Z"
    let lines = [
        diagEvent(ts: ts1, cum: 1_000),                        // delta 1000, prev=1000
        diagEvent(ts: "2026-07-07T02:00:00.000Z", cum: 400),   // 리셋(drop): delta 0, prev=400
        diagEvent(ts: ts1, cum: 1_000)                         // 같은 키 재출현: delta 600 (같은 파일이라 중복 아님)
    ].joined(separator: "\n")
    diagWrite(lines + "\n", to: diagRolloutURL(home, "2026/07/07/rollout-2026-07-07T01-00-00-aaaa.jsonl"))

    let d = diagCompute(home)

    #expect(d.dupEvents == 0)
    #expect(d.dupTokens == 0)
    #expect(d.dedupTotal == 1_600)   // 1000 + 0 + 600
    #expect(d.drops == 1)
    #expect(d.eventsMonth == 3)
    diagCleanup(home)
}

// 세 파일에 걸친 재출현: 중복 **키**는 1개지만 dupTokens 는 2·3번째 출현분을 모두 더한다.
@Test
func codexDiagnosticsAccumulatesDuplicateTokensAcrossThreeFiles() {
    let home = diagTempHome()
    let ts = "2026-07-08T01:00:00.000Z"
    for name in ["aaaa", "bbbb", "cccc"] {
        diagWrite(diagEvent(ts: ts, cum: 700) + "\n",
                  to: diagRolloutURL(home, "2026/07/08/rollout-2026-07-08T01-00-00-\(name).jsonl"))
    }

    let d = diagCompute(home)

    #expect(d.dupEvents == 1)        // 키는 하나.
    #expect(d.dupTokens == 1_400)    // 2·3번째 출현의 델타(700 + 700).
    #expect(d.dedupTotal == 700)     // 앱 산식 2,100 − 1,400
    #expect(d.filesMonth == 3)
    diagCleanup(home)
}

// MARK: - 2. carryFiles / carryTotal — 20만 '초과'만, 경계값은 제외

// 파일의 **첫** token_count 가 이미 큰 누적치로 시작하면 그 앞 누적은 다른 세션에서 온 것이고,
// 앱 산식은 그 전부를 이 파일의 첫 델타로 이 달에 계상한다(= resume 카운터 이월).
@Test
func codexDiagnosticsFlagsCarryOverOnlyAboveThreshold() {
    let home = diagTempHome()
    // 초과: 200,001 → 걸려야 한다.
    diagWrite(diagEvent(ts: "2026-07-09T01:00:00.000Z", cum: 200_001) + "\n",
              to: diagRolloutURL(home, "2026/07/09/rollout-2026-07-09T01-00-00-aaaa.jsonl"))
    // 경계: 정확히 200,000 → 걸리면 안 된다.
    diagWrite(diagEvent(ts: "2026-07-09T02:00:00.000Z", cum: 200_000) + "\n",
              to: diagRolloutURL(home, "2026/07/09/rollout-2026-07-09T02-00-00-bbbb.jsonl"))
    // 미만: 100 → 당연히 안 걸린다.
    diagWrite(diagEvent(ts: "2026-07-09T03:00:00.000Z", cum: 100) + "\n",
              to: diagRolloutURL(home, "2026/07/09/rollout-2026-07-09T03-00-00-cccc.jsonl"))

    let d = diagCompute(home)

    #expect(d.carryFiles == 1)
    #expect(d.carryTotal == 200_001)
    #expect(d.filesMonth == 3)
    diagCleanup(home)
}

// carry 는 '첫' 누적치로만 판정한다 — 나중에 100만을 넘겨도 0 에서 출발한 파일은 이월이 아니다.
@Test
func codexDiagnosticsCarryUsesFirstCumulativeNotLargest() {
    let home = diagTempHome()
    let lines = [
        diagEvent(ts: "2026-07-10T01:00:00.000Z", cum: 5_000),
        diagEvent(ts: "2026-07-10T02:00:00.000Z", cum: 1_000_000)
    ].joined(separator: "\n")
    diagWrite(lines + "\n", to: diagRolloutURL(home, "2026/07/10/rollout-2026-07-10T01-00-00-aaaa.jsonl"))

    let d = diagCompute(home)

    #expect(d.carryFiles == 0)
    #expect(d.carryTotal == 0)
    #expect(d.maxDelta == 995_000)   // 큰 점프 자체는 maxDelta 로 드러난다.
    diagCleanup(home)
}

// carryTotal 은 이월 의심 파일들의 첫 누적치 **합**이다.
@Test
func codexDiagnosticsSumsCarryTotalAcrossFiles() {
    let home = diagTempHome()
    diagWrite(diagEvent(ts: "2026-07-11T01:00:00.000Z", cum: 250_000) + "\n",
              to: diagRolloutURL(home, "2026/07/11/rollout-2026-07-11T01-00-00-aaaa.jsonl"))
    diagWrite(diagEvent(ts: "2026-07-11T02:00:00.000Z", cum: 400_000) + "\n",
              to: diagRolloutURL(home, "2026/07/11/rollout-2026-07-11T02-00-00-bbbb.jsonl"))

    let d = diagCompute(home)

    #expect(d.carryFiles == 2)
    #expect(d.carryTotal == 650_000)
    diagCleanup(home)
}

// MARK: - 3. drops — 누적 감소 이벤트 수 + 델타 0 클램프

@Test
func codexDiagnosticsCountsCumulativeDropsAndClampsDeltaToZero() {
    let home = diagTempHome()
    let lines = [
        diagEvent(ts: "2026-07-12T01:00:00.000Z", cum: 5_000),   // delta 5000
        diagEvent(ts: "2026-07-12T02:00:00.000Z", cum: 1_000),   // 감소 → drop, delta 0(클램프)
        diagEvent(ts: "2026-07-12T03:00:00.000Z", cum: 1_500)    // delta 500
    ].joined(separator: "\n")
    diagWrite(lines + "\n", to: diagRolloutURL(home, "2026/07/12/rollout-2026-07-12T01-00-00-aaaa.jsonl"))

    let d = diagCompute(home)

    #expect(d.drops == 1)
    // 클램프가 없으면 5000 + (−4000) + 500 = 1,500 이 된다. 5,500 이어야 한다.
    #expect(d.dedupTotal == 5_500)
    #expect(d.maxDelta == 5_000)
    #expect(d.finalSum == 1_500)
    diagCleanup(home)
}

@Test
func codexDiagnosticsCountsEveryDropSeparately() {
    let home = diagTempHome()
    let lines = [
        diagEvent(ts: "2026-07-13T01:00:00.000Z", cum: 9_000),
        diagEvent(ts: "2026-07-13T02:00:00.000Z", cum: 3_000),   // drop 1
        diagEvent(ts: "2026-07-13T03:00:00.000Z", cum: 8_000),
        diagEvent(ts: "2026-07-13T04:00:00.000Z", cum: 2_000),   // drop 2
        diagEvent(ts: "2026-07-13T05:00:00.000Z", cum: 2_000)    // 동률은 감소가 아니다.
    ].joined(separator: "\n")
    diagWrite(lines + "\n", to: diagRolloutURL(home, "2026/07/13/rollout-2026-07-13T01-00-00-aaaa.jsonl"))

    let d = diagCompute(home)

    #expect(d.drops == 2)
    #expect(d.dedupTotal == 14_000)   // 9000 + 0 + 5000 + 0 + 0
    diagCleanup(home)
}

// MARK: - 4. 항등식: dedupTotal + dupTokens == 프로덕션 앱 산식 총합

// 진단이 앱 산식과 갈라지면 "앱이 왜 그 숫자를 냈는가"를 못 가른다. 중복·리셋·이월이 모두 섞인 픽스처에서
// dedupTotal + dupTokens 가 프로덕션 TokenUsageScanner 의 codexInput 과 정확히 같아야 한다.
// (라인은 전부 개행으로 종결한다 — 증분 스캐너는 개행 없는 꼬리를 소비하지 않으므로 그래야 같은 입력을 본다.)
@Test
func codexDiagnosticsDedupTotalPlusDupTokensMatchesProductionScanner() {
    let home = diagTempHome()
    let sharedTs = "2026-07-01T02:00:00.000Z"

    // A: 첫 누적이 30만(이월 의심) + 뒤이어 5만 증가.
    diagWrite([
        diagEvent(ts: sharedTs, cum: 300_000),
        diagEvent(ts: "2026-07-01T03:00:00.000Z", cum: 350_000)
    ].joined(separator: "\n") + "\n",
    to: diagRolloutURL(home, "2026/07/01/rollout-2026-07-01T00-00-00-aaaa.jsonl"))

    // B: A 의 첫 이벤트를 그대로 복제(파일 간 중복) + 자기 이벤트 하나.
    diagWrite([
        diagEvent(ts: sharedTs, cum: 300_000),
        diagEvent(ts: "2026-07-02T04:00:00.000Z", cum: 310_000)
    ].joined(separator: "\n") + "\n",
    to: diagRolloutURL(home, "2026/07/02/rollout-2026-07-02T00-00-00-bbbb.jsonl"))

    // C: 누적 리셋이 있는 파일.
    diagWrite([
        diagEvent(ts: "2026-07-03T01:00:00.000Z", cum: 5_000),
        diagEvent(ts: "2026-07-03T02:00:00.000Z", cum: 1_000),
        diagEvent(ts: "2026-07-03T03:00:00.000Z", cum: 4_000)
    ].joined(separator: "\n") + "\n",
    to: diagRolloutURL(home, "2026/07/03/rollout-2026-07-03T00-00-00-cccc.jsonl"))

    let d = diagCompute(home)
    let production = TokenUsageScanner.scan(homeDirectory: home, now: diagNow)

    // 픽스처가 항등식을 자명하게 만들지 않는지(중복·리셋·이월이 실제로 발화했는지) 먼저 못 박는다.
    #expect(d.dupTokens == 300_000)
    #expect(d.dupEvents == 1)
    #expect(d.drops == 1)
    #expect(d.carryFiles == 2)
    #expect(d.carryTotal == 600_000)

    #expect(production.codexInput == 668_000)               // 350,000 + 310,000 + 8,000
    #expect(d.dedupTotal == 368_000)                        // 668,000 − 300,000
    #expect(d.dedupTotal + d.dupTokens == production.codexInput)
    #expect(d.finalSum == 664_000)                          // 350,000 + 310,000 + 4,000
    #expect(d.topFile == 350_000)
    #expect(d.maxDelta == 300_000)
    #expect(d.eventsMonth == 7)
    #expect(d.filesTotal == 3)
    #expect(d.filesMonth == 3)
    diagCleanup(home)
}

// 중복·리셋이 하나도 없는 평범한 픽스처에서도 항등식이 서야 한다(dupTokens == 0 인 경우).
@Test
func codexDiagnosticsMatchesProductionScannerWithoutDuplicates() {
    let home = diagTempHome()
    diagWrite([
        diagEvent(ts: "2026-07-04T01:00:00.000Z", cum: 1_200),
        diagEvent(ts: "2026-07-04T02:00:00.000Z", cum: 4_500)
    ].joined(separator: "\n") + "\n",
    to: diagRolloutURL(home, "2026/07/04/rollout-2026-07-04T00-00-00-aaaa.jsonl"))
    diagWrite(diagEvent(ts: "2026-07-04T03:00:00.000Z", cum: 900) + "\n",
              to: diagRolloutURL(home, "2026/07/04/rollout-2026-07-04T01-00-00-bbbb.jsonl"))

    let d = diagCompute(home)
    let production = TokenUsageScanner.scan(homeDirectory: home, now: diagNow)

    #expect(d.dupTokens == 0)
    #expect(production.codexInput == 5_400)
    #expect(d.dedupTotal == 5_400)
    #expect(d.dedupTotal + d.dupTokens == production.codexInput)
    diagCleanup(home)
}

// MARK: - 5. finalSum — 파일별 '그 달 마지막 이벤트의 누적치' 합

@Test
func codexDiagnosticsFinalSumAddsLastInMonthCumulativePerFile() {
    let home = diagTempHome()
    // A: 이 달 이벤트 두 개 → 마지막 누적치 700.
    diagWrite([
        diagEvent(ts: "2026-07-20T01:00:00.000Z", cum: 100),
        diagEvent(ts: "2026-07-20T02:00:00.000Z", cum: 700)
    ].joined(separator: "\n") + "\n",
    to: diagRolloutURL(home, "2026/07/20/rollout-2026-07-20T00-00-00-aaaa.jsonl"))
    // B: 이 달 이벤트 뒤에 **다음 달**(KST 8/1) 이벤트가 온다 → finalSum 은 이 달 마지막인 50 을 써야 한다.
    diagWrite([
        diagEvent(ts: "2026-07-21T01:00:00.000Z", cum: 50),
        diagEvent(ts: "2026-07-31T15:00:00.000Z", cum: 9_999)   // KST 2026-08-01 00:00 → 다음 달
    ].joined(separator: "\n") + "\n",
    to: diagRolloutURL(home, "2026/07/21/rollout-2026-07-21T00-00-00-bbbb.jsonl"))

    let d = diagCompute(home)

    #expect(d.finalSum == 750)        // 700 + 50 (9,999 는 다음 달이라 제외)
    #expect(d.eventsMonth == 3)       // 이 달 이벤트만: 100, 700, 50
    #expect(d.dedupTotal == 750)      // 100 + 600 + 50
    #expect(d.topFile == 700)
    diagCleanup(home)
}

// 이 달 이벤트가 하나도 없는 파일은 filesMonth·finalSum 어디에도 들어가지 않는다(filesTotal 에는 잡힌다).
@Test
func codexDiagnosticsExcludesFilesWithNoEventsInTargetMonth() {
    let home = diagTempHome()
    diagWrite(diagEvent(ts: "2026-07-22T01:00:00.000Z", cum: 500) + "\n",
              to: diagRolloutURL(home, "2026/07/22/rollout-2026-07-22T00-00-00-aaaa.jsonl"))
    diagWrite(diagEvent(ts: "2026-05-22T01:00:00.000Z", cum: 999_999) + "\n",
              to: diagRolloutURL(home, "2026/05/22/rollout-2026-05-22T00-00-00-bbbb.jsonl"))

    let d = diagCompute(home)

    #expect(d.filesTotal == 2)
    #expect(d.filesMonth == 1)
    #expect(d.finalSum == 500)
    #expect(d.dedupTotal == 500)
    #expect(d.carryFiles == 0)   // 5월 파일은 첫 누적이 20만을 넘지만 이 달 이벤트가 없어 집계 밖이다.
    diagCleanup(home)
}

// MARK: 월 렌즈 — carry/drops 는 대상 월에 일어난 일만 센다
//
// 13개 필드는 전부 같은 렌즈(대상 월)를 쓴다. 예외는 filesTotal(전기간 분모)과 appBuild(출처 표기)뿐이다.
// 걸어가는 방식은 렌즈와 무관하다 — prevCumulative 는 지난달 이벤트로도 계속 전진해야 이 달 첫 델타의 기준선이 맞는다.
// 아래 두 테스트는 "무엇을 세느냐"와 "어떻게 걸어가느냐"가 분리돼 있는지를 월 경계를 넘나드는 파일로 못 박는다.

// 6월에 시작해 7월까지 이어진 세션. 첫 이벤트(누적 30만)는 prevCumulative==0 을 만나 델타가 전액이 되지만
// 그건 **6월** 몫이라 이 달 합계엔 1만(=310,000−300,000)만 들어간다. 즉 이 파일이 이 달에 잘못 넣은 양은 0 이므로
// carry 는 0 이 맞다 — 이월 신호는 '이 달 과다계상분'을 가리켜야 하고, 그러려면 첫 이벤트가 이 달이어야 한다.
@Test
func codexDiagnosticsIgnoresCarryWhenFirstEventPredatesTargetMonth() {
    let home = diagTempHome()
    diagWrite([
        diagEvent(ts: "2026-06-20T01:00:00.000Z", cum: 300_000),   // KST 6/20 → 지난달(첫 이벤트)
        diagEvent(ts: "2026-07-20T01:00:00.000Z", cum: 310_000)    // KST 7/20 → 이 달
    ].joined(separator: "\n") + "\n",
    to: diagRolloutURL(home, "2026/06/20/rollout-2026-06-20T00-00-00-aaaa.jsonl"))

    let d = diagCompute(home)

    #expect(d.carryFiles == 0)         // 첫 이벤트가 지난달이라 이 달엔 무해하다.
    #expect(d.carryTotal == 0)
    #expect(d.eventsMonth == 1)
    #expect(d.dedupTotal == 10_000)    // 30만이 아니라 1만 — prevCumulative 가 지난달 이벤트로 전진했다는 증거.
    #expect(d.finalSum == 310_000)
    #expect(d.drops == 0)
    diagCleanup(home)
}

// drops 도 대상 월 렌즈 안이다. 두 픽스처는 구조가 같고 **리셋이 떨어지는 달**만 다르다 — 그래서 게이트가
// '항상 0' 으로 죽어 있는 경우와 구분된다(A 는 0, B 는 1). 두 경우 모두 이 달 기여는 3,000 으로 같다.
@Test
func codexDiagnosticsCountsDropOnlyWhenTheResetFallsInTargetMonth() {
    // A: 리셋이 지난달에 있다 → 이 달 drops 는 0.
    let homeA = diagTempHome()
    diagWrite([
        diagEvent(ts: "2026-06-15T01:00:00.000Z", cum: 9_000),
        diagEvent(ts: "2026-06-15T02:00:00.000Z", cum: 1_000),     // 지난달의 리셋
        diagEvent(ts: "2026-07-15T01:00:00.000Z", cum: 4_000)      // 이 달: delta 3,000
    ].joined(separator: "\n") + "\n",
    to: diagRolloutURL(homeA, "2026/06/15/rollout-2026-06-15T00-00-00-aaaa.jsonl"))

    let a = diagCompute(homeA)

    #expect(a.drops == 0)              // 이 달 이벤트엔 감소가 없다.
    #expect(a.eventsMonth == 1)
    #expect(a.dedupTotal == 3_000)
    #expect(a.carryFiles == 0)
    diagCleanup(homeA)

    // B: 같은 모양인데 리셋이 이 달에 있다 → drops 는 1. (대조군 — 게이트가 상수 0 이면 여기서 죽는다.)
    let homeB = diagTempHome()
    diagWrite([
        diagEvent(ts: "2026-06-15T01:00:00.000Z", cum: 9_000),
        diagEvent(ts: "2026-07-15T01:00:00.000Z", cum: 1_000),     // 이 달의 리셋
        diagEvent(ts: "2026-07-15T02:00:00.000Z", cum: 4_000)      // 이 달: delta 3,000
    ].joined(separator: "\n") + "\n",
    to: diagRolloutURL(homeB, "2026/06/15/rollout-2026-06-15T00-00-00-bbbb.jsonl"))

    let b = diagCompute(homeB)

    #expect(b.drops == 1)
    #expect(b.eventsMonth == 2)
    #expect(b.dedupTotal == 3_000)     // A 와 같다 — 오직 drops 만 갈린다.
    #expect(b.finalSum == 4_000)
    diagCleanup(homeB)
}

// 첫 이벤트가 **대상 월**일 때의 임계 양쪽. 200,000 은 제외, 200,001 은 포함 —
// 위의 '지난달 첫 이벤트는 0' 규약과 합쳐 carry 의 발화 조건이 (대상 월 ∧ 20만 초과)임을 못 박는다.
@Test
func codexDiagnosticsCarryThresholdIsExclusiveWhenFirstEventIsInTargetMonth() {
    let home = diagTempHome()
    diagWrite(diagEvent(ts: "2026-07-17T01:00:00.000Z", cum: 200_000) + "\n",
              to: diagRolloutURL(home, "2026/07/17/rollout-2026-07-17T01-00-00-aaaa.jsonl"))
    diagWrite(diagEvent(ts: "2026-07-17T02:00:00.000Z", cum: 200_001) + "\n",
              to: diagRolloutURL(home, "2026/07/17/rollout-2026-07-17T02-00-00-bbbb.jsonl"))

    let d = diagCompute(home)

    #expect(d.carryFiles == 1)
    #expect(d.carryTotal == 200_001)   // 경계값 200,000 은 더해지지 않는다.
    #expect(d.filesMonth == 2)
    diagCleanup(home)
}

// MARK: - 6. KST 월 경계 (+9 오프셋)

// UTC 2026-06-30T15:00:00Z 는 KST 로 7월 1일 00:00 이다. 이 이벤트는 7월에 귀속되고 6월에는 잡히면 안 된다.
@Test
func codexDiagnosticsAttributesUTCMonthEndEveningToNextKSTMonth() {
    let home = diagTempHome()
    let url = diagRolloutURL(home, "2026/06/30/rollout-2026-06-30T00-00-00-aaaa.jsonl")
    diagWrite([
        diagEvent(ts: "2026-06-30T14:59:59.000Z", cum: 1_000),   // KST 6/30 23:59:59 → 6월
        diagEvent(ts: "2026-06-30T15:00:00.000Z", cum: 3_000)    // KST 7/01 00:00:00 → 7월
    ].joined(separator: "\n") + "\n", to: url)

    let july = diagCompute(home, month: "2026-07")
    let june = diagCompute(home, month: "2026-06")

    #expect(july.eventsMonth == 1)
    #expect(july.finalSum == 3_000)
    #expect(july.dedupTotal == 2_000)   // 델타 = 3000 − 1000 (6월 이벤트가 prevCumulative 를 남긴다)
    #expect(june.eventsMonth == 1)
    #expect(june.finalSum == 1_000)
    #expect(june.dedupTotal == 1_000)
    diagCleanup(home)
}

// 연말 경계: UTC 2026-12-31T15:00:00Z 는 KST 2027-01-01 이다(일·월·연이 한꺼번에 올라간다).
@Test
func codexDiagnosticsRollsYearOverAtKSTNewYear() {
    let home = diagTempHome()
    let url = diagRolloutURL(home, "2026/12/31/rollout-2026-12-31T00-00-00-aaaa.jsonl")
    diagWrite([
        diagEvent(ts: "2026-12-31T14:59:59.000Z", cum: 400),     // KST 2026-12-31 23:59:59 → 2026-12
        diagEvent(ts: "2026-12-31T15:00:00.000Z", cum: 900)      // KST 2027-01-01 00:00:00 → 2027-01
    ].joined(separator: "\n") + "\n", to: url)

    let dec = diagCompute(home, month: "2026-12")
    let jan = diagCompute(home, month: "2027-01")

    #expect(dec.eventsMonth == 1)
    #expect(dec.finalSum == 400)
    #expect(jan.eventsMonth == 1)
    #expect(jan.finalSum == 900)
    #expect(jan.dedupTotal == 500)
    diagCleanup(home)
}

// 윤년이 아닌 2월 말(28일)에서도 +9 올림이 월을 정확히 넘긴다.
@Test
func codexDiagnosticsRollsMonthOverAtNonLeapFebruaryEnd() {
    let home = diagTempHome()
    let url = diagRolloutURL(home, "2026/02/28/rollout-2026-02-28T00-00-00-aaaa.jsonl")
    diagWrite(diagEvent(ts: "2026-02-28T15:00:00.000Z", cum: 1_234) + "\n", to: url)

    #expect(diagCompute(home, month: "2026-03").eventsMonth == 1)
    #expect(diagCompute(home, month: "2026-02").eventsMonth == 0)
    diagCleanup(home)
}

// MARK: - 7. 견고성 (결손·깨짐·꼬리·오탐·빈 파일)

// info: null 이벤트는 건너뛰되 prevCumulative 를 갱신하지 않아야 한다 — 그 구간은 다음 유효 이벤트의 델타로 흡수된다.
// prevCumulative 를 0 으로 리셋해 버리면 다음 델타가 2,500 으로 부풀고 없던 drop 이 생긴다.
@Test
func codexDiagnosticsSkipsNullInfoEventWithoutResettingPreviousCumulative() {
    let home = diagTempHome()
    let lines = [
        diagEvent(ts: "2026-07-23T01:00:00.000Z", cum: 1_000),
        diagNullInfoEvent(ts: "2026-07-23T02:00:00.000Z"),
        diagEvent(ts: "2026-07-23T03:00:00.000Z", cum: 2_500)
    ].joined(separator: "\n")
    diagWrite(lines + "\n", to: diagRolloutURL(home, "2026/07/23/rollout-2026-07-23T00-00-00-aaaa.jsonl"))

    let d = diagCompute(home)

    #expect(d.eventsMonth == 2)        // 결손 이벤트는 세지 않는다.
    #expect(d.dedupTotal == 2_500)     // 1,000 + 1,500 (2,500 이 아니라 1,500 이 두 번째 델타)
    #expect(d.maxDelta == 1_500)
    #expect(d.drops == 0)              // 리셋이 아니므로 감소로 잡히면 안 된다.
    #expect(d.finalSum == 2_500)
    diagCleanup(home)
}

// 깨진 JSON · payload.type 오탐 · token_count 무관 라인이 섞여도 유효 이벤트만 계상한다.
@Test
func codexDiagnosticsIgnoresBrokenAndNonTokenCountLines() {
    let home = diagTempHome()
    let lines = [
        diagBrokenLine,
        "{\"payload\":{\"type\":\"agent_message\",\"text\":\"hello\"}}",
        diagWrongTypeEvent(ts: "2026-07-24T01:00:00.000Z", cum: 999_999),
        diagEvent(ts: "2026-07-24T02:00:00.000Z", cum: 800),
        "",                                                       // 빈 줄
        diagEvent(ts: "2026-07-24T03:00:00.000Z", cum: 1_100)
    ].joined(separator: "\n")
    diagWrite(lines + "\n", to: diagRolloutURL(home, "2026/07/24/rollout-2026-07-24T00-00-00-aaaa.jsonl"))

    let d = diagCompute(home)

    #expect(d.eventsMonth == 2)
    #expect(d.dedupTotal == 1_100)     // 800 + 300 — 999,999 짜리 오탐이 새어 들면 즉시 깨진다.
    #expect(d.carryFiles == 0)         // 첫 '유효' 이벤트는 800 이다(999,999 가 첫 값으로 잡히면 안 된다).
    #expect(d.drops == 0)
    diagCleanup(home)
}

// 진단 스캐너는 1회성 전량 스캔이라 **개행 없이 끝나는 마지막 라인도 파싱**한다(증분 스캐너와의 의도된 차이).
@Test
func codexDiagnosticsParsesFinalLineWithoutTrailingNewline() {
    let home = diagTempHome()
    let lines = [
        diagEvent(ts: "2026-07-25T01:00:00.000Z", cum: 300),
        diagEvent(ts: "2026-07-25T02:00:00.000Z", cum: 1_300)
    ].joined(separator: "\n")           // 마지막 개행 없음
    diagWrite(lines, to: diagRolloutURL(home, "2026/07/25/rollout-2026-07-25T00-00-00-aaaa.jsonl"))

    let d = diagCompute(home)

    #expect(d.eventsMonth == 2)
    #expect(d.dedupTotal == 1_300)
    #expect(d.finalSum == 1_300)
    diagCleanup(home)
}

// 빈 파일과 이름이 맞지 않는 파일들. filesTotal 은 rollout-*.jsonl 만 센다.
@Test
func codexDiagnosticsHandlesEmptyFileAndIgnoresNonRolloutFiles() {
    let home = diagTempHome()
    diagWrite("", to: diagRolloutURL(home, "2026/07/26/rollout-2026-07-26T00-00-00-empty.jsonl"))
    diagWrite(diagEvent(ts: "2026-07-26T01:00:00.000Z", cum: 600) + "\n",
              to: diagRolloutURL(home, "2026/07/26/rollout-2026-07-26T01-00-00-aaaa.jsonl"))
    // 이름/확장자가 맞지 않는 파일들 — 순회 대상이 아니다.
    diagWrite(diagEvent(ts: "2026-07-26T02:00:00.000Z", cum: 500_000) + "\n",
              to: diagRolloutURL(home, "2026/07/26/session-2026-07-26.jsonl"))
    diagWrite(diagEvent(ts: "2026-07-26T03:00:00.000Z", cum: 500_000) + "\n",
              to: diagRolloutURL(home, "2026/07/26/rollout-2026-07-26T03-00-00-cccc.json"))

    let d = diagCompute(home)

    #expect(d.filesTotal == 2)     // 빈 rollout 파일 + 유효 rollout 파일만.
    #expect(d.filesMonth == 1)     // 빈 파일은 이 달 이벤트가 없다.
    #expect(d.dedupTotal == 600)
    #expect(d.carryFiles == 0)
    diagCleanup(home)
}

// MARK: - 8. 프라이버시 구조 보증 — 인코딩 결과에 문자열 값이 하나도 없어야 한다

// 이 진단은 경로·파일명·대화 본문을 절대 실어 나르면 안 된다. 문자열 필드가 하나라도 추가되면 이 테스트가 빨개진다.
@Test
func codexDiagnosticsEncodesWithoutAnyStringValues() throws {
    let sample = CodexUsageDiagnostics(
        filesTotal: 11, filesMonth: 22, eventsMonth: 33, maxDelta: 44,
        carryFiles: 55, carryTotal: 66, dupEvents: 77, dupTokens: 88,
        finalSum: 99, dedupTotal: 111, drops: 222, topFile: 333, appBuild: 444
    )
    let data = try JSONEncoder().encode(sample)
    let object = try JSONSerialization.jsonObject(with: data)
    let root = try #require(object as? [String: Any])

    // 필드 수가 13 이어야 한다(추가/삭제를 이 테스트가 먼저 알아챈다).
    #expect(root.count == 13)

    // 값 트리를 재귀로 훑어 문자열이 하나라도 있으면 실패.
    func stringValues(in value: Any) -> [String] {
        if let s = value as? String { return [s] }
        if let dict = value as? [String: Any] { return dict.values.flatMap { stringValues(in: $0) } }
        if let array = value as? [Any] { return array.flatMap { stringValues(in: $0) } }
        return []
    }
    let leaked = stringValues(in: root).sorted()
    #expect(leaked.isEmpty, "진단 페이로드에 문자열 값이 들어 있다: \(leaked)")

    // 모든 값이 수치인지도 함께 못 박는다(Bool/Null 등 다른 타입이 끼어드는 것도 잡는다).
    let nonNumeric = root.filter { !($0.value is NSNumber) }.keys.sorted()
    #expect(nonNumeric.isEmpty, "수치가 아닌 값: \(nonNumeric)")

    // 왕복(부분 페이로드 흡수 규약이 값을 훼손하지 않는지).
    let roundTripped = try JSONDecoder().decode(CodexUsageDiagnostics.self, from: data)
    #expect(roundTripped == sample)
    // 누락 키는 0 으로 흡수한다(옛 빌드가 쓴 부분 페이로드를 새 빌드가 통째로 실패하지 않고 읽는다).
    let decodedPartial = try JSONDecoder().decode(
        CodexUsageDiagnostics.self, from: Data("{\"filesTotal\":7}".utf8)
    )
    #expect(decodedPartial == CodexUsageDiagnostics(filesTotal: 7))
}

// MARK: - 9. ~/.codex 가 없는 기기 — 크래시 없이 전 필드 0

@Test
func codexDiagnosticsReturnsZerosWhenCodexDirectoryIsAbsent() {
    // 홈은 존재하지만 .codex 가 없는 경우.
    let home = diagTempHome()
    try? FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)

    let d = diagCompute(home, appBuild: 7_777)

    #expect(d == CodexUsageDiagnostics(appBuild: 7_777))   // appBuild 외 전 필드 0.
    diagCleanup(home)
}

@Test
func codexDiagnosticsReturnsZerosWhenHomeDirectoryDoesNotExist() {
    let home = diagTempHome()   // 만들지 않는다.

    let d = diagCompute(home, appBuild: 1)

    #expect(d == CodexUsageDiagnostics(appBuild: 1))
}

// ~/.codex/sessions 는 있지만 rollout 파일이 하나도 없는 경우도 안전해야 한다.
@Test
func codexDiagnosticsReturnsZerosWhenSessionsDirectoryIsEmpty() {
    let home = diagTempHome()
    try? FileManager.default.createDirectory(
        at: home.appendingPathComponent(".codex/sessions/2026/07/27", isDirectory: true),
        withIntermediateDirectories: true
    )

    let d = diagCompute(home, appBuild: 9)

    #expect(d == CodexUsageDiagnostics(appBuild: 9))
    diagCleanup(home)
}
