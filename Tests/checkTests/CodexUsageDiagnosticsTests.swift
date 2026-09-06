import Foundation
import Testing
@testable import check

// MARK: - Codex 집계 진단 스캐너 테스트
//
// 목적: CodexUsageDiagnosticsScanner.compute 의 각 신호가 **실제로 발화하는지**를 합성 픽스처로 못 박는다.
// 순위판에서 Codex 코호트의 하루당 토큰 중앙값이 Claude 코호트의 20배로 나온 원인을 가르는 계측이므로,
// "신호가 켜져야 할 때 켜지고, 켜지면 안 될 때 안 켜지는가"가 전부다.
//
// v0.2.30 에서 원인이 확정됐다 — **resume 카운터 이월**. 파일마다 기준선 0 에서 시작해 첫 token_count 의 누적치
// 전액(실측 평균 6.6억)을 이번 달 델타로 계상하고 있었다. 수정: **파일에서 처음 만나는 유효 이벤트는 델타를
// 만들지 않고 기준선만 세운다.** 그래서 이 파일의 기대값 대부분이 "첫 이벤트 몫"만큼 줄었다.
//
// 픽스처 설계 규약 두 가지 — 지우기 전에 읽어라:
//  1) **중복 계상을 재현하려면 복제 이벤트가 파일의 첫 이벤트가 아니어야 한다.** 첫 이벤트는 델타가 0 이라
//     dupTokens 에 0 을 더하고, 그러면 "파일 간 중복이 총합을 부풀린다"는 현상 자체가 재현되지 않는다.
//     그래서 중복 픽스처들은 복제분 앞에 이벤트를 하나씩 깔아 둔다(아래 각 테스트 주석 참조).
//  2) **기여를 재는 픽스처는 이벤트가 최소 2개여야 한다.** 이벤트 1개짜리 파일은 기여가 언제나 0 이라
//     `dedupTotal == 0` 단언이 "스캐너가 전부 0 을 돌려줘도 통과"하는 죽은 단언이 된다.
//
// 픽스처는 임시 홈에 ~/.codex/sessions/**/rollout-*.jsonl 을 직접 써서 실제 파일 순회·스트리밍·파싱 경로를
// 그대로 태운다. 순수 함수만 다루므로 창을 띄우지 않는다.

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

/// 간격(gap) 테스트용 타임스탬프 조립기. 날짜를 고정하고 시:분:초만 바꿔 간격을 눈으로 검산할 수 있게 한다.
private func diagTS(_ hms: String, day: String = "2026-07-15") -> String {
    "\(day)T\(hms).000Z"
}

/// info 가 null 인 이벤트. 프리체크("token_count")는 통과하지만 total 이 없어 건너뛰어야 하고,
/// **기준선을 갱신하면 안 된다**(다음 유효 이벤트의 델타가 이 구간을 흡수한다).
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

// MARK: - 0. 핵심 규칙: 파일의 첫 이벤트는 기준선만 세운다

// 이 릴리스가 고치는 버그 그 자체. 실측에서 파일이 평균 6.6억 토큰에서 시작하는데, 옛 산식은 그 전액을
// 이번 달 델타로 계상했다. 새 산식은 첫 이벤트를 "카운터가 이미 거기 와 있었다"는 정보로만 쓴다.
@Test
func codexDiagnosticsFirstEventSetsBaselineWithoutContributing() {
    let home = diagTempHome()
    diagWrite([
        diagEvent(ts: diagTS("01:00:00"), cum: 660_000_000),   // resume 로 이어받은 카운터 — 기여 0
        diagEvent(ts: diagTS("01:00:10"), cum: 660_001_000)    // 이번에 실제로 쓴 양 = 1,000
    ].joined(separator: "\n") + "\n",
    to: diagRolloutURL(home, "2026/07/15/rollout-2026-07-15T01-00-00-aaaa.jsonl"))

    let d = diagCompute(home)
    let production = TokenUsageScanner.scan(homeDirectory: home, now: diagNow)

    #expect(d.dedupTotal == 1_000)               // 6.6억이 아니라 1,000.
    #expect(production.codexInput == 1_000)      // 프로덕션도 같이 고쳐졌다.
    #expect(d.maxDelta == 1_000)
    #expect(d.maxDeltaGapSeconds == 10)
    #expect(d.eventsMonth == 2)
    #expect(d.finalSum == 660_001_000)           // 대조 산식은 마지막 누적치 그대로.
    // 옛 산식은 여전히 관측 가능하다 — 그 차이가 이월분의 정확값이다.
    #expect(d.legacyTotal == 660_001_000)
    #expect(d.legacyTotal - d.dedupTotal - d.dupTokens == 660_000_000)
    #expect(d.carryFiles == 1)
    #expect(d.carryTotal == 660_000_000)
    diagCleanup(home)
}

// MARK: - 1. dupEvents / dupTokens — 파일 간 재출현만 센다

// 같은 (timestamp, cum) 이 **서로 다른 두 파일**에 나타나면 앱 산식은 두 번 다 델타로 계상한다.
//
// 픽스처 주의: 각 파일의 **첫 줄은 그 파일 고유의 기준선 이벤트**다. 지우지 마라 — 지우면 복제 이벤트가
// 파일의 첫 이벤트가 되어 델타 0 이 되고, dupTokens 가 0 으로 떨어져 중복 계상 현상 자체가 재현되지 않는다.
@Test
func codexDiagnosticsCountsDuplicateEventAcrossTwoFiles() {
    let home = diagTempHome()
    let sharedTs = "2026-07-05T01:00:00.000Z"
    diagWrite([
        diagEvent(ts: "2026-07-05T00:30:00.000Z", cum: 500),   // A 고유 기준선(필수)
        diagEvent(ts: sharedTs, cum: 1_500)                    // 복제되는 이벤트 — 델타 1,000
    ].joined(separator: "\n") + "\n",
    to: diagRolloutURL(home, "2026/07/05/rollout-2026-07-05T01-00-00-aaaa.jsonl"))
    diagWrite([
        diagEvent(ts: "2026-07-05T00:40:00.000Z", cum: 500),   // B 고유 기준선(ts 가 달라 중복 키가 아니다)
        diagEvent(ts: sharedTs, cum: 1_500)                    // 같은 (ts, cum) 이 다른 파일에 또 — 델타 1,000
    ].joined(separator: "\n") + "\n",
    to: diagRolloutURL(home, "2026/07/05/rollout-2026-07-05T02-00-00-bbbb.jsonl"))

    let d = diagCompute(home)

    #expect(d.dupEvents == 1)              // (ts, cum) 키가 2개 파일에 나타났다.
    #expect(d.dupTokens == 1_000)          // 두 번째 출현의 델타가 총합을 부풀린 몫 — 0 이면 픽스처가 죽은 것이다.
    #expect(d.dedupTotal == 1_000)         // 앱 산식 2,000 에서 중복분을 뺀 값.
    #expect(d.finalSum == 3_000)           // 파일별 마지막 누적치 합(1,500 + 1,500).
    #expect(d.filesTotal == 2)
    #expect(d.filesMonth == 2)
    #expect(d.eventsMonth == 4)
    diagCleanup(home)
}

// 한 파일 안에서 같은 (timestamp, cum) 이 반복되는 건 **중복이 아니다** — cum == 기준선이라 델타가 0 이고
// 총합에 아무 영향이 없다. 이걸 중복으로 세면 진단이 무고한 파일을 범인으로 지목한다.
// (첫 줄은 기준선 이벤트다. 없으면 반복 3줄의 델타가 전부 0 이 되어 dedupTotal 단언이 죽는다.)
@Test
func codexDiagnosticsIgnoresRepeatedEventWithinSameFile() {
    let home = diagTempHome()
    let ts = "2026-07-06T01:00:00.000Z"
    let line = diagEvent(ts: ts, cum: 1_000)
    diagWrite([
        diagEvent(ts: "2026-07-06T00:30:00.000Z", cum: 200),   // 기준선(필수)
        line, line, line                                        // 같은 이벤트 3연속
    ].joined(separator: "\n") + "\n",
    to: diagRolloutURL(home, "2026/07/06/rollout-2026-07-06T01-00-00-aaaa.jsonl"))

    let d = diagCompute(home)

    #expect(d.dupEvents == 0)              // 파일 수 1 → 중복 아님.
    #expect(d.dupTokens == 0)
    #expect(d.eventsMonth == 4)
    #expect(d.dedupTotal == 800)           // 첫 반복만 델타 800, 나머지 둘은 0.
    #expect(d.maxDelta == 800)
    diagCleanup(home)
}

// 같은 파일 안의 반복이지만 사이에 누적 리셋이 끼어 두 번째 출현의 델타가 **0 이 아닌** 경우.
// '출현 횟수 ≥ 2' 로 중복을 판정하면 여기서 dupTokens 가 600 만큼 잘못 부풀고 dedupTotal 이 깎인다.
@Test
func codexDiagnosticsIgnoresSameFileRepeatEvenWhenDeltaIsNonZero() {
    let home = diagTempHome()
    let ts1 = "2026-07-07T01:00:00.000Z"
    let lines = [
        diagEvent(ts: ts1, cum: 1_000),                        // 첫 이벤트 = 기준선(델타 0)
        diagEvent(ts: "2026-07-07T02:00:00.000Z", cum: 400),   // 리셋(drop): delta 0, 기준선 400
        diagEvent(ts: ts1, cum: 1_000)                         // 같은 키 재출현: delta 600 (같은 파일이라 중복 아님)
    ].joined(separator: "\n")
    diagWrite(lines + "\n", to: diagRolloutURL(home, "2026/07/07/rollout-2026-07-07T01-00-00-aaaa.jsonl"))

    let d = diagCompute(home)

    #expect(d.dupEvents == 0)
    #expect(d.dupTokens == 0)
    #expect(d.dedupTotal == 600)     // 0 + 0 + 600
    #expect(d.drops == 1)
    #expect(d.eventsMonth == 3)
    diagCleanup(home)
}

// 세 파일에 걸친 재출현: 중복 **키**는 1개지만 dupTokens 는 2·3번째 출현분을 모두 더한다.
// (각 파일의 첫 줄은 고유 기준선. 지우면 복제분이 첫 이벤트가 되어 dupTokens 가 0 으로 죽는다.)
@Test
func codexDiagnosticsAccumulatesDuplicateTokensAcrossThreeFiles() {
    let home = diagTempHome()
    let ts = "2026-07-08T01:00:00.000Z"
    for (i, name) in ["aaaa", "bbbb", "cccc"].enumerated() {
        diagWrite([
            diagEvent(ts: "2026-07-08T00:1\(i):00.000Z", cum: 100),   // 파일마다 다른 ts 의 기준선
            diagEvent(ts: ts, cum: 800)                               // 복제 이벤트 — 델타 700
        ].joined(separator: "\n") + "\n",
        to: diagRolloutURL(home, "2026/07/08/rollout-2026-07-08T01-00-00-\(name).jsonl"))
    }

    let d = diagCompute(home)

    #expect(d.dupEvents == 1)        // 키는 하나.
    #expect(d.dupTokens == 1_400)    // 2·3번째 출현의 델타(700 + 700).
    #expect(d.dedupTotal == 700)     // 앱 산식 2,100 − 1,400
    #expect(d.filesMonth == 3)
    #expect(d.eventsMonth == 6)
    diagCleanup(home)
}

// MARK: - 2. carryFiles / carryTotal — 20만 '초과'만, 경계값은 제외

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

// carry 는 '첫' 누적치로만 판정한다 — 나중에 100만을 넘겨도 작게 출발한 파일은 이월이 아니다.
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

// MARK: - 3. legacyTotal — 이월분의 정확값 회수 (문턱과 무관)

// `legacyTotal − dedupTotal − dupTokens` == 대상 월에 첫 이벤트를 가진 파일들의 첫 누적치 합.
// carryTotal(20만 문턱 위만) 은 그 하한일 뿐이라는 것까지 같은 픽스처에서 보인다.
@Test
func codexDiagnosticsRecoversExactCarryAmountFromLegacyTotal() {
    let home = diagTempHome()
    // F1: 첫 15만(문턱 아래) + 델타 1만
    diagWrite([
        diagEvent(ts: "2026-07-12T01:00:00.000Z", cum: 150_000),
        diagEvent(ts: "2026-07-12T02:00:00.000Z", cum: 160_000)
    ].joined(separator: "\n") + "\n",
    to: diagRolloutURL(home, "2026/07/12/rollout-2026-07-12T01-00-00-aaaa.jsonl"))
    // F2: 첫 30만(문턱 위) + 델타 5천
    diagWrite([
        diagEvent(ts: "2026-07-12T03:00:00.000Z", cum: 300_000),
        diagEvent(ts: "2026-07-12T04:00:00.000Z", cum: 305_000)
    ].joined(separator: "\n") + "\n",
    to: diagRolloutURL(home, "2026/07/12/rollout-2026-07-12T03-00-00-bbbb.jsonl"))
    // F3: 첫 1천(아주 작음) + 델타 2천
    diagWrite([
        diagEvent(ts: "2026-07-12T05:00:00.000Z", cum: 1_000),
        diagEvent(ts: "2026-07-12T06:00:00.000Z", cum: 3_000)
    ].joined(separator: "\n") + "\n",
    to: diagRolloutURL(home, "2026/07/12/rollout-2026-07-12T05-00-00-cccc.jsonl"))

    let d = diagCompute(home)
    let production = TokenUsageScanner.scan(homeDirectory: home, now: diagNow)

    #expect(d.dedupTotal == 17_000)                 // 10,000 + 5,000 + 2,000
    #expect(production.codexInput == 17_000)
    #expect(d.legacyTotal == 468_000)               // 160,000 + 305,000 + 3,000
    // 이월 정확값 = 첫 누적치 합. 문턱과 무관하게 전부 잡힌다.
    #expect(d.legacyTotal - d.dedupTotal - d.dupTokens == 451_000)   // 150,000 + 300,000 + 1,000
    // carryTotal 은 문턱 위 한 파일만 봐서 451,000 중 300,000 만 설명한다 — 하한이지 총량이 아니다.
    #expect(d.carryFiles == 1)
    #expect(d.carryTotal == 300_000)
    diagCleanup(home)
}

// 필드 실측이 그랬듯, 첫 이벤트가 전부 20만 아래면 carryTotal 은 **0** 인데 실제 이월은 0 이 아니다.
// 이 경우 legacyTotal 차이만이 이월을 드러낸다 — carryTotal 만 보면 "이월 없음"으로 오판한다.
@Test
func codexDiagnosticsRecoversCarryEvenWhenCarryTotalIsZero() {
    let home = diagTempHome()
    diagWrite([
        diagEvent(ts: "2026-07-13T01:00:00.000Z", cum: 100_000),
        diagEvent(ts: "2026-07-13T02:00:00.000Z", cum: 110_000)
    ].joined(separator: "\n") + "\n",
    to: diagRolloutURL(home, "2026/07/13/rollout-2026-07-13T01-00-00-aaaa.jsonl"))
    diagWrite([
        diagEvent(ts: "2026-07-13T03:00:00.000Z", cum: 50_000),
        diagEvent(ts: "2026-07-13T04:00:00.000Z", cum: 52_000)
    ].joined(separator: "\n") + "\n",
    to: diagRolloutURL(home, "2026/07/13/rollout-2026-07-13T03-00-00-bbbb.jsonl"))

    let d = diagCompute(home)

    #expect(d.carryFiles == 0)
    #expect(d.carryTotal == 0)                                       // 문턱이 통째로 놓친다.
    #expect(d.dedupTotal == 12_000)
    #expect(d.legacyTotal == 162_000)
    #expect(d.legacyTotal - d.dedupTotal - d.dupTokens == 150_000)   // 실제 이월은 15만.
    diagCleanup(home)
}

// MARK: - 4. drops — 누적 감소 이벤트 수 + 델타 0 클램프

@Test
func codexDiagnosticsCountsCumulativeDropsAndClampsDeltaToZero() {
    let home = diagTempHome()
    let lines = [
        diagEvent(ts: "2026-07-14T01:00:00.000Z", cum: 5_000),   // 기준선(델타 0)
        diagEvent(ts: "2026-07-14T02:00:00.000Z", cum: 1_000),   // 감소 → drop, delta 0(클램프)
        diagEvent(ts: "2026-07-14T03:00:00.000Z", cum: 1_500)    // delta 500
    ].joined(separator: "\n")
    diagWrite(lines + "\n", to: diagRolloutURL(home, "2026/07/14/rollout-2026-07-14T01-00-00-aaaa.jsonl"))

    let d = diagCompute(home)

    #expect(d.drops == 1)
    // 클램프가 없으면 0 + (−4,000) + 500 = −3,500 이 된다. 500 이어야 한다.
    #expect(d.dedupTotal == 500)
    #expect(d.maxDelta == 500)
    #expect(d.finalSum == 1_500)
    diagCleanup(home)
}

@Test
func codexDiagnosticsCountsEveryDropSeparately() {
    let home = diagTempHome()
    let lines = [
        diagEvent(ts: "2026-07-16T01:00:00.000Z", cum: 9_000),   // 기준선
        diagEvent(ts: "2026-07-16T02:00:00.000Z", cum: 3_000),   // drop 1
        diagEvent(ts: "2026-07-16T03:00:00.000Z", cum: 8_000),   // delta 5,000
        diagEvent(ts: "2026-07-16T04:00:00.000Z", cum: 2_000),   // drop 2
        diagEvent(ts: "2026-07-16T05:00:00.000Z", cum: 2_000)    // 동률은 감소가 아니다.
    ].joined(separator: "\n")
    diagWrite(lines + "\n", to: diagRolloutURL(home, "2026/07/16/rollout-2026-07-16T01-00-00-aaaa.jsonl"))

    let d = diagCompute(home)

    #expect(d.drops == 2)
    #expect(d.dedupTotal == 5_000)
    diagCleanup(home)
}

// MARK: - 5. 항등식: dedupTotal + dupTokens == 프로덕션 앱 산식 총합

// 진단이 앱 산식과 갈라지면 "앱이 왜 그 숫자를 냈는가"를 못 가른다.
//
// 픽스처 구조(resume 세션의 실제 모양): B 는 A 를 이어받은 세션이라 A 의 이벤트 둘을 **그대로 replay** 한 뒤
// 자기 이벤트를 잇는다. 새 산식에서 B 의 첫 줄(= A 의 첫 이벤트 replay)은 기준선이 되어 델타 0 이지만,
// **두 번째 replay(A 의 두 번째 이벤트)는 실제 델타 50,000 을 만든다** — 이게 지금도 살아 있는 중복 계상 경로다.
// B 의 replay 두 줄을 지우면 dupTokens 가 0 이 되어 항등식이 자명해진다. 지우지 마라.
@Test
func codexDiagnosticsDedupTotalPlusDupTokensMatchesProductionScanner() {
    let home = diagTempHome()
    let ts1 = "2026-07-01T02:00:00.000Z"
    let ts2 = "2026-07-01T03:00:00.000Z"

    // A: 첫 누적이 30만(이월 의심) + 뒤이어 5만 증가.
    diagWrite([
        diagEvent(ts: ts1, cum: 300_000),
        diagEvent(ts: ts2, cum: 350_000)
    ].joined(separator: "\n") + "\n",
    to: diagRolloutURL(home, "2026/07/01/rollout-2026-07-01T00-00-00-aaaa.jsonl"))

    // B: A 의 두 이벤트를 replay 한 뒤 자기 이벤트 하나.
    diagWrite([
        diagEvent(ts: ts1, cum: 300_000),                        // replay #1 → 기준선(델타 0)
        diagEvent(ts: ts2, cum: 350_000),                        // replay #2 → 델타 50,000 이 중복 계상된다
        diagEvent(ts: "2026-07-02T04:00:00.000Z", cum: 360_000)  // B 고유 → 델타 10,000
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
    #expect(d.dupTokens == 50_000)     // 0 이면 픽스처가 죽었다 — replay 이벤트를 지웠는지 확인해라.
    #expect(d.dupEvents == 2)          // ts1·ts2 두 키가 각각 2개 파일에 나타났다.
    #expect(d.drops == 1)
    #expect(d.carryFiles == 2)
    #expect(d.carryTotal == 600_000)

    #expect(production.codexInput == 113_000)               // 50,000 + 60,000 + 3,000
    #expect(d.dedupTotal == 63_000)                         // 113,000 − 50,000
    #expect(d.dedupTotal + d.dupTokens == production.codexTotal)   // v0.2.41: 입력+출력 분리 후에도 항등식은 총합 기준
    #expect(d.finalSum == 714_000)                          // 350,000 + 360,000 + 4,000
    #expect(d.legacyTotal == 718_000)                       // 옛 산식(첫 이벤트 전액 포함)
    #expect(d.legacyTotal - d.dedupTotal - d.dupTokens == 605_000)   // 300,000 + 300,000 + 5,000
    #expect(d.topFile == 60_000)
    #expect(d.maxDelta == 50_000)
    #expect(d.eventsMonth == 8)
    #expect(d.filesTotal == 3)
    #expect(d.filesMonth == 3)
    diagCleanup(home)
}

// 중복이 하나도 없는 평범한 픽스처에서도 항등식이 서야 한다(dupTokens == 0 인 경우).
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
    #expect(production.codexInput == 3_300)     // A 의 델타만(3,300). B 는 첫 이벤트뿐이라 0.
    #expect(d.dedupTotal == 3_300)
    #expect(d.dedupTotal + d.dupTokens == production.codexTotal)   // v0.2.41: 입력+출력 분리 후에도 항등식은 총합 기준
    #expect(d.legacyTotal - d.dedupTotal - d.dupTokens == 2_100)   // 1,200 + 900
    diagCleanup(home)
}

// MARK: - 6. finalSum — 파일별 '그 달 마지막 이벤트의 누적치' 합

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
    #expect(d.dedupTotal == 600)      // 0(기준선) + 600 + 0(기준선)
    #expect(d.topFile == 600)
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
    #expect(d.dedupTotal == 0)   // 이 달 파일은 첫 이벤트 하나뿐 → 기여 0.
    #expect(d.carryFiles == 0)   // 5월 파일은 첫 누적이 20만을 넘지만 이 달 이벤트가 없어 집계 밖이다.
    diagCleanup(home)
}

// MARK: - 7. 월 렌즈 — carry/drops 는 대상 월에 일어난 일만 센다

// 6월에 시작해 7월까지 이어진 세션. 첫 이벤트는 **6월** 몫이라 이 달 합계엔 1만만 들어간다.
// 이 파일이 이 달에 잘못 넣은 양은 0 이므로 carry 는 0 이 맞다.
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
    #expect(d.dedupTotal == 10_000)    // 기준선이 지난달 이벤트로 전진했다는 증거.
    #expect(d.legacyTotal == 10_000)   // 첫 이벤트가 이 달 밖이라 옛 산식과 차이가 없다.
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

// 첫 이벤트가 **대상 월**일 때의 임계 양쪽. 200,000 은 제외, 200,001 은 포함.
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

// MARK: - 8. bigDelta — "한 턴으로 설명 불가능한 점프" 문턱 200만 (초과만)

@Test
func codexDiagnosticsBigDeltaThresholdIsExclusive() {
    let home = diagTempHome()
    // A: 델타가 정확히 2,000,000 → 제외.
    diagWrite([
        diagEvent(ts: diagTS("01:00:00"), cum: 10),
        diagEvent(ts: diagTS("01:00:10"), cum: 2_000_010)
    ].joined(separator: "\n") + "\n",
    to: diagRolloutURL(home, "2026/07/15/rollout-2026-07-15T01-00-00-aaaa.jsonl"))
    // B: 델타가 2,000,001 → 포함.
    diagWrite([
        diagEvent(ts: diagTS("02:00:00"), cum: 10),
        diagEvent(ts: diagTS("02:00:10"), cum: 2_000_011)
    ].joined(separator: "\n") + "\n",
    to: diagRolloutURL(home, "2026/07/15/rollout-2026-07-15T02-00-00-bbbb.jsonl"))

    let d = diagCompute(home)

    #expect(d.bigDeltaCount == 1)
    #expect(d.bigDeltaTotal == 2_000_001)
    #expect(d.bigGapMedianSeconds == 10)
    #expect(d.maxDelta == 2_000_001)
    diagCleanup(home)
}

// bigDelta 가 하나도 없으면 세 필드 모두 0 이다(중앙값 계산이 빈 배열에서 크래시하지 않는지도 함께).
@Test
func codexDiagnosticsReportsZeroBigDeltaFieldsWhenNoJumpExists() {
    let home = diagTempHome()
    diagWrite([
        diagEvent(ts: diagTS("03:00:00"), cum: 1_000),
        diagEvent(ts: diagTS("03:00:10"), cum: 900_000)
    ].joined(separator: "\n") + "\n",
    to: diagRolloutURL(home, "2026/07/15/rollout-2026-07-15T03-00-00-aaaa.jsonl"))

    let d = diagCompute(home)

    #expect(d.bigDeltaCount == 0)
    #expect(d.bigDeltaTotal == 0)
    #expect(d.bigGapMedianSeconds == 0)
    #expect(d.maxDelta == 899_000)          // 큰 델타이긴 하나 문턱 아래.
    #expect(d.maxDeltaGapSeconds == 10)
    diagCleanup(home)
}

// MARK: - 9. maxDeltaGapSeconds — 최대 델타가 진짜 사용량인지 카운터 점프인지 가르는 결정타

// 같은 이벤트 구성에서 **최대 델타가 어느 이벤트냐**에 따라 간격이 달라져야 한다.
// 짧은 간격(10초)에 큰 델타 = 카운터 점프 의심 / 긴 간격(6시간)에 큰 델타 = 진짜 사용량.
@Test
func codexDiagnosticsMaxDeltaGapDistinguishesShortAndLongIntervals() {
    // A: 최대 델타가 6시간 뒤에 왔다 → 21,600초.
    let homeA = diagTempHome()
    diagWrite([
        diagEvent(ts: diagTS("01:00:00"), cum: 100),
        diagEvent(ts: diagTS("01:00:10"), cum: 200),      // delta 100, gap 10
        diagEvent(ts: diagTS("07:00:10"), cum: 5_000)     // delta 4,800, gap 21,600 ← 최대
    ].joined(separator: "\n") + "\n",
    to: diagRolloutURL(homeA, "2026/07/15/rollout-2026-07-15T01-00-00-aaaa.jsonl"))

    let a = diagCompute(homeA)

    #expect(a.maxDelta == 4_800)
    #expect(a.maxDeltaGapSeconds == 21_600)
    diagCleanup(homeA)

    // B: 같은 시각 배치인데 최대 델타가 10초 뒤 이벤트다 → 10초.
    let homeB = diagTempHome()
    diagWrite([
        diagEvent(ts: diagTS("01:00:00"), cum: 100),
        diagEvent(ts: diagTS("01:00:10"), cum: 9_000),    // delta 8,900, gap 10 ← 최대
        diagEvent(ts: diagTS("07:00:10"), cum: 9_100)     // delta 100, gap 21,600
    ].joined(separator: "\n") + "\n",
    to: diagRolloutURL(homeB, "2026/07/15/rollout-2026-07-15T01-00-00-bbbb.jsonl"))

    let b = diagCompute(homeB)

    #expect(b.maxDelta == 8_900)
    #expect(b.maxDeltaGapSeconds == 10)
    diagCleanup(homeB)
}

// 달을 걸친 resume 이야말로 카운터 불연속의 전형이다. 간격을 대상 월 안으로 자르면 바로 그 경우의
// 판별력이 사라지므로, 직전 이벤트가 지난달이어도 간격을 그대로 재야 한다(자르면 0 이 된다).
@Test
func codexDiagnosticsMeasuresGapAcrossMonthBoundary() {
    let home = diagTempHome()
    diagWrite([
        diagEvent(ts: "2026-06-30T09:00:00.000Z", cum: 1_000),      // KST 6/30 18:00 → 지난달
        diagEvent(ts: "2026-06-30T15:00:00.000Z", cum: 3_000_000)   // KST 7/1 00:00 → 이 달, 6시간 뒤
    ].joined(separator: "\n") + "\n",
    to: diagRolloutURL(home, "2026/06/30/rollout-2026-06-30T00-00-00-aaaa.jsonl"))

    let d = diagCompute(home)

    #expect(d.eventsMonth == 1)
    #expect(d.maxDelta == 2_999_000)
    #expect(d.maxDeltaGapSeconds == 21_600)      // 6시간. 월 안으로 자르면 0 이 된다.
    #expect(d.bigDeltaCount == 1)
    #expect(d.bigDeltaTotal == 2_999_000)
    #expect(d.bigGapMedianSeconds == 21_600)     // 분포 쪽도 같이 월 경계를 넘는다.
    diagCleanup(home)
}

// maxDeltaGapSeconds == 0 은 두 가지 뜻이다. 둘 다 못 박아 둔다 —
// (가) 양의 델타가 아예 없다(파일이 첫 이벤트뿐), (나) 최대 델타가 직전 이벤트와 같은 초에 찍혔다.
@Test
func codexDiagnosticsMaxDeltaGapIsZeroForBaselineOnlyFileAndForSameSecondJump() {
    // (가) 첫 이벤트뿐 → 델타가 없으니 잴 간격도 없다.
    let homeA = diagTempHome()
    diagWrite(diagEvent(ts: diagTS("01:00:00"), cum: 5_000_000) + "\n",
              to: diagRolloutURL(homeA, "2026/07/15/rollout-2026-07-15T01-00-00-aaaa.jsonl"))

    let a = diagCompute(homeA)

    #expect(a.eventsMonth == 1)
    #expect(a.maxDelta == 0)
    #expect(a.maxDeltaGapSeconds == 0)
    diagCleanup(homeA)

    // (나) 같은 초에 큰 델타가 찍혔다 → 델타는 크지만 간격은 진짜로 0 이다(= 카운터 점프의 가장 강한 신호).
    let homeB = diagTempHome()
    diagWrite([
        diagEvent(ts: diagTS("01:00:00"), cum: 100),
        diagEvent(ts: diagTS("01:00:00"), cum: 9_000)   // 같은 초, delta 8,900
    ].joined(separator: "\n") + "\n",
    to: diagRolloutURL(homeB, "2026/07/15/rollout-2026-07-15T01-00-00-bbbb.jsonl"))

    let b = diagCompute(homeB)

    #expect(b.maxDelta == 8_900)
    #expect(b.maxDeltaGapSeconds == 0)
    diagCleanup(homeB)
}

// MARK: - 10. bigGapMedianSeconds — 점프가 사고인지 상습인지 가르는 분포

@Test
func codexDiagnosticsBigGapMedianPicksMiddleSampleOfThree() {
    let home = diagTempHome()
    diagWrite([
        diagEvent(ts: diagTS("01:00:00"), cum: 100),            // 기준선
        diagEvent(ts: diagTS("01:00:10"), cum: 3_000_100),      // big, gap 10
        diagEvent(ts: diagTS("01:01:50"), cum: 6_000_100),      // big, gap 100
        diagEvent(ts: diagTS("01:18:30"), cum: 9_000_100)       // big, gap 1,000
    ].joined(separator: "\n") + "\n",
    to: diagRolloutURL(home, "2026/07/15/rollout-2026-07-15T01-00-00-aaaa.jsonl"))

    let d = diagCompute(home)

    #expect(d.bigDeltaCount == 3)
    #expect(d.bigDeltaTotal == 9_000_000)
    #expect(d.bigGapMedianSeconds == 100)        // [10, 100, 1000] 의 가운데
    #expect(d.maxDelta == 3_000_000)
    #expect(d.maxDeltaGapSeconds == 10)          // 동점이면 먼저 나온 이벤트가 이긴다.
    diagCleanup(home)
}

@Test
func codexDiagnosticsBigGapMedianPicksLowerSampleWhenCountIsEven() {
    let home = diagTempHome()
    diagWrite([
        diagEvent(ts: diagTS("01:00:00"), cum: 100),            // 기준선
        diagEvent(ts: diagTS("01:00:10"), cum: 3_000_100),      // big, gap 10
        diagEvent(ts: diagTS("01:01:50"), cum: 6_000_100),      // big, gap 100
        diagEvent(ts: diagTS("01:18:30"), cum: 9_000_100),      // big, gap 1,000
        diagEvent(ts: diagTS("04:05:10"), cum: 12_000_100)      // big, gap 10,000
    ].joined(separator: "\n") + "\n",
    to: diagRolloutURL(home, "2026/07/15/rollout-2026-07-15T01-00-00-aaaa.jsonl"))

    let d = diagCompute(home)

    #expect(d.bigDeltaCount == 4)
    // [10, 100, 1000, 10000] → 아래쪽 중앙값 100. 평균을 내면 550(표본에 없는 값)이 된다.
    #expect(d.bigGapMedianSeconds == 100)
    diagCleanup(home)
}

// 파일의 첫 이벤트는 직전이 없어 간격을 잴 수 없다 — 그래서 애초에 델타가 0 이고 bigDelta 모집단에 못 들어간다.
// 이걸 '간격 0' 으로 모집단에 넣으면 중앙값이 바닥으로 끌려가 "상습 점프"로 오판하게 된다.
@Test
func codexDiagnosticsBigGapMedianExcludesFirstEventFromPopulation() {
    let home = diagTempHome()
    diagWrite([
        diagEvent(ts: diagTS("01:00:00"), cum: 5_000_000),      // 첫 이벤트: 누적은 크지만 델타 0 → 모집단 밖
        diagEvent(ts: diagTS("02:00:00"), cum: 8_000_000)       // big(델타 300만), gap 3,600
    ].joined(separator: "\n") + "\n",
    to: diagRolloutURL(home, "2026/07/15/rollout-2026-07-15T01-00-00-aaaa.jsonl"))

    let d = diagCompute(home)

    #expect(d.bigDeltaCount == 1)
    #expect(d.bigDeltaTotal == 3_000_000)
    // 첫 이벤트를 간격 0 으로 넣으면 [0, 3600] 이 되어 아래쪽 중앙값 0 이 나온다.
    #expect(d.bigGapMedianSeconds == 3_600)
    #expect(d.maxDeltaGapSeconds == 3_600)
    diagCleanup(home)
}

// MARK: - 11. KST 월 경계 (+9 오프셋)

// UTC 2026-06-30T15:00:00Z 는 KST 로 7월 1일 00:00 이다.
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
    #expect(july.dedupTotal == 2_000)   // 6월 이벤트가 기준선을 남긴다 → 델타 3,000 − 1,000
    #expect(june.eventsMonth == 1)
    #expect(june.finalSum == 1_000)
    #expect(june.dedupTotal == 0)       // 6월 쪽에선 그 이벤트가 파일의 첫 이벤트 = 기준선.
    #expect(june.legacyTotal == 1_000)  // 옛 산식이라면 1,000 을 계상했다.
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

// MARK: - 12. 견고성 (결손·깨짐·꼬리·오탐·빈 파일)

// info: null 이벤트는 건너뛰되 기준선을 갱신하지 않아야 한다 — 그 구간은 다음 유효 이벤트의 델타로 흡수된다.
// 기준선이 nil 로 되돌아가면 다음 이벤트가 '첫 이벤트' 취급이라 델타 0 이 되고, 0 으로 리셋되면 2,500 이 된다.
// 정답은 1,500 뿐이라 양쪽 오류를 다 잡는다.
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
    #expect(d.dedupTotal == 1_500)     // 기준선 1,000 이 살아 있어야 나오는 값.
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
    #expect(d.dedupTotal == 300)       // 800 이 기준선, 1,100 이 델타 300.
    // 999,999 짜리 오탐이 새어 들면 그게 첫 이벤트가 되어 아래 둘이 동시에 깨진다(carry 1, drop 1).
    #expect(d.carryFiles == 0)
    #expect(d.drops == 0)
    // 옛 산식은 첫 이벤트 800 까지 계상했다(800 + 300). 그 차이 800 이 곧 이월분이다.
    #expect(d.legacyTotal == 1_100)
    #expect(d.legacyTotal - d.dedupTotal - d.dupTokens == 800)
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

    #expect(d.eventsMonth == 2)        // 꼬리를 안 읽으면 1 이 된다.
    #expect(d.dedupTotal == 1_000)     // 꼬리를 안 읽으면 0 이 된다.
    #expect(d.finalSum == 1_300)
    diagCleanup(home)
}

// 빈 파일과 이름이 맞지 않는 파일들. filesTotal 은 rollout-*.jsonl 만 센다.
@Test
func codexDiagnosticsHandlesEmptyFileAndIgnoresNonRolloutFiles() {
    let home = diagTempHome()
    diagWrite("", to: diagRolloutURL(home, "2026/07/26/rollout-2026-07-26T00-00-00-empty.jsonl"))
    // 이벤트 2개 — 1개면 기여가 늘 0 이라 dedupTotal 단언이 죽는다.
    diagWrite([
        diagEvent(ts: "2026-07-26T01:00:00.000Z", cum: 600),
        diagEvent(ts: "2026-07-26T01:30:00.000Z", cum: 900)
    ].joined(separator: "\n") + "\n",
    to: diagRolloutURL(home, "2026/07/26/rollout-2026-07-26T01-00-00-aaaa.jsonl"))
    // 이름/확장자가 맞지 않는 파일들 — 순회 대상이 아니다.
    diagWrite(diagEvent(ts: "2026-07-26T02:00:00.000Z", cum: 500_000) + "\n",
              to: diagRolloutURL(home, "2026/07/26/session-2026-07-26.jsonl"))
    diagWrite(diagEvent(ts: "2026-07-26T03:00:00.000Z", cum: 500_000) + "\n",
              to: diagRolloutURL(home, "2026/07/26/rollout-2026-07-26T03-00-00-cccc.json"))

    let d = diagCompute(home)

    #expect(d.filesTotal == 2)     // 빈 rollout 파일 + 유효 rollout 파일만.
    #expect(d.filesMonth == 1)     // 빈 파일은 이 달 이벤트가 없다.
    #expect(d.dedupTotal == 300)
    #expect(d.carryFiles == 0)
    diagCleanup(home)
}

// MARK: - 13. 프라이버시 구조 보증 — 인코딩 결과에 문자열 값이 하나도 없어야 한다

// 이 진단은 경로·파일명·대화 본문을 절대 실어 나르면 안 된다. 문자열 필드가 하나라도 추가되면 이 테스트가 빨개진다.
@Test
func codexDiagnosticsEncodesWithoutAnyStringValues() throws {
    let sample = CodexUsageDiagnostics(
        filesTotal: 11, filesMonth: 22, eventsMonth: 33, maxDelta: 44,
        maxDeltaGapSeconds: 55, bigDeltaCount: 66, bigDeltaTotal: 77, bigGapMedianSeconds: 88,
        carryFiles: 99, carryTotal: 111, dupEvents: 222, dupTokens: 333,
        finalSum: 444, dedupTotal: 555, legacyTotal: 666, drops: 777,
        topFile: 888, appBuild: 999, forkFiles: 1010, forkCopyTokens: 1111
    )
    let data = try JSONEncoder().encode(sample)
    let object = try JSONSerialization.jsonObject(with: data)
    let root = try #require(object as? [String: Any])

    // 필드 수가 20 이어야 한다(18 + v0.2.43 포크 계수 2 — 추가/삭제를 이 테스트가 먼저 알아챈다).
    #expect(root.count == 20)

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

// MARK: - 14. ~/.codex 가 없는 기기 — 크래시 없이 전 필드 0

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
