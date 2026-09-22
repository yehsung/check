import Foundation
import Testing
@testable import check
@testable import CheckCore

// v0.3.36 — 공유 Codex 계정 사용자의 **개인 표시 == 순위표**.
//
// 결함(2026-09-22 프로덕션 실측): 팝오버의 "N월 AI 토큰 소모량" 은 `TokenUsageDisplay.effectiveTotal` 로 계산해
// **계정 원본**을 그대로 띄웠다(분배 계수가 한 번도 안 곱해진 값). 순위판은 서버가 나눈 내 몫을 띄운다.
// 같은 사람의 두 숫자가 갈렸고, 어느 쪽이 맞는지 사용자가 가릴 방법이 없었다.
//   · ㅂ보예성   개인 5,784,713,585 vs 순위 2,844,663,420
//   · 맥주밤거리엠버서더 개인 11,154,164,635 vs 순위 4,614,662,772 (약 2.4배)
//   · 수 빈      개인 6,455,604,017 vs 순위 6,952,033,183 (**올라가는 사람도 있다**)
//
// 왜 기존 패리티 테스트가 이걸 8일간 놓쳤나: `v0312DisplayTotalIsTheTwinOfTheServerBoardFormula` 가 좌우 양변을
// **같은 픽스처·같은 Swift 함수**로 계산했다. 분배 계수가 0.275 여도 영원히 초록인 동어반복이다
// (메모리 '비교 기준선이 달라야 한다'). 그래서 이 파일의 기준선은 **서버가 실제로 내려준 고정 JSON** 이다 —
// 아래 두 골든 벡터는 2026-09-22 KST 에 프로덕션 `token_usage_board('2026-09')` 를 읽기 전용으로 호출해 받은
// 응답 그대로이고, 클라 쪽 값은 같은 시각의 `token_usage_device_monthly` 행에서 왔다.
//
// 여기서 고정하는 것:
//  ⓐ 공유 사용자: 로컬 산식 ≠ 서버 total 임을 **먼저** 못 박고(두 기준선이 실제로 다르다), resolve 가 서버 total 로 붙인다.
//  ⓑ 비공유 사용자: resolve 결과가 로컬 경로와 바이트 동일, 비율 정확히 1.0.
//  ⓒ 옛 서버 응답(codex_effective 키 없음) → 서버 행을 만들지 않는다(폐기된 max 증폭기로 떨어지지 않게).
//  ⓓ 잔디 비율과 계정 버킷 축소.
//  ⓔ/ⓕ 달 가드·userID 가드.
//  ⓖ SQL 계약(보드 14번 칸이 '내 몫'이라는 사실).

// MARK: - 골든 벡터 (2026-09-22 KST 프로덕션 읽기)

/// 서비스가 쓰는 것과 **같은 디코더 규약**(convertFromSnakeCase). 서버 응답 JSON 을 그대로 통과시킨다.
private func scdDecodeBoard(_ json: String) throws -> [TokenBoardRow] {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode([TokenBoardRow].self, from: Data(json.utf8))
}

private let scdSharedUserID = "d5fd403e-b857-4792-9b3b-269f84d47de1"
private let scdMonth = "2026-09"
private let scdNow = Date(timeIntervalSince1970: 1_790_000_000)

/// 공유 계정 사용자 'ㅂ보예성' 의 실제 보드 행(2026-09-22 KST).
/// total 2,844,663,420 = claude 1,081,155,290 + codex_effective 1,288,774,633 + 안티그래비티 474,733,497.
/// `codex_account_month` 1,191,490,526 은 **이미 나눈 내 몫**이다(SQL `e.codex_account_share as codex_account`).
private let scdSharedBoardJSON = """
[{"user_id":"d5fd403e-b857-4792-9b3b-269f84d47de1","display_name":"ㅂ보예성","avatar_url":null,
  "claude_input":7966,"claude_output":4062560,"claude_cache_read":1054514044,"claude_cache_creation":22570720,
  "codex_input":1294176063,"codex_output":5798903,"total":2844663420,
  "today_total":46102503,"today_date":"2026-09-22","codex_cache_read":1249377024,
  "codex_account_month":1191490526,"codex_effective":1288774633,"center":"seoul"}]
"""

/// 비공유 계정 사용자 '향룡' 의 실제 보드 행(같은 시각). `codex_account_month` 2,454,958,224 == 이 맥이 본 계정 월합이라
/// 비율이 **정확히 1.0** 이고, 개인 산식과 보드 total 이 이미 같다(차 0).
private let scdSoloBoardJSON = """
[{"user_id":"b9af636b-123d-4dee-ac58-bbd147ff7910","display_name":"향룡","avatar_url":null,
  "claude_input":644,"claude_output":237106,"claude_cache_read":71486887,"claude_cache_creation":3175361,
  "codex_input":1940374290,"codex_output":9572544,"total":3132426288,
  "today_total":0,"today_date":"2026-09-22","codex_cache_read":1887328128,
  "codex_account_month":2454958224,"codex_effective":3057526290,"center":"seoul"}]
"""

/// 'ㅂ보예성' 의 맥이 그 시각에 들고 있던 값(token_usage_device_monthly + 일별 행에서 재구성).
/// 이 맥의 계정 월합 4,228,824,798 · 마지막 버킷 2026-09-21(209,866,413) · 그 날 로컬은 버킷보다 작아 꼬리가 0 이다
/// → `CodexEffectiveRule.month` 가 계정 월합을 **그대로** 돌려준다(= 분배가 한 번도 안 곱해진 값).
private func scdSharedLocal() -> (TokenUsageMonthly, CodexAccountUsage) {
    var usage = TokenUsageMonthly(month: scdMonth)
    // Claude 1,081,155,290 — 보드의 네 칸 합과 같다(서버·클라가 같은 값을 본다).
    usage.claudeInput = 7_966
    usage.claudeOutput = 4_062_560
    usage.claudeCacheRead = 1_054_514_044
    usage.claudeCacheCreation = 22_570_720
    usage.codexInput = 1_294_176_063
    usage.codexOutput = 5_798_903
    usage.codexCacheRead = 1_249_377_024
    // 안티그래비티 474,733,497(보드 잔차와 같다).
    usage.antigravityInput = 474_733_497
    usage.codexDailyUTC = ["2026-09-21": 150_000_000]   // 마지막 버킷 날의 로컬 < 버킷 → 꼬리 0
    let account = CodexAccountUsage(
        fetchedAt: scdNow,
        lifetimeTokens: nil,
        buckets: ["2026-09-01": 4_018_958_385, "2026-09-21": 209_866_413]   // 합 4,228,824,798
    )
    return (usage, account)
}

/// '향룡' 의 맥. 계정 월합 2,454,958,224 + 마지막 버킷 뒤 꼬리 602,568,066 = 3,057,526,290(보드 codex_effective 와 같다).
private func scdSoloLocal() -> (TokenUsageMonthly, CodexAccountUsage) {
    var usage = TokenUsageMonthly(month: scdMonth)
    usage.claudeInput = 644
    usage.claudeOutput = 237_106
    usage.claudeCacheRead = 71_486_887
    usage.claudeCacheCreation = 3_175_361
    usage.codexInput = 1_940_374_290
    usage.codexOutput = 9_572_544
    usage.codexCacheRead = 1_887_328_128
    usage.codexDailyUTC = ["2026-09-17": 602_568_066]   // 마지막 버킷(09-16) 뒤 = 미반영 꼬리, 그대로 더해진다
    let account = CodexAccountUsage(
        fetchedAt: scdNow,
        lifetimeTokens: nil,
        buckets: ["2026-09-01": 2_054_113_698, "2026-09-16": 400_844_526]   // 합 2,454,958,224
    )
    return (usage, account)
}

// MARK: - ⓐ 공유: 기준선이 실제로 다르고, resolve 가 서버로 붙인다

@Test
func v0336SharedAccountLocalFormulaDisagreesWithTheServerAndResolveFixesIt() throws {
    let entry = try #require(scdDecodeBoard(scdSharedBoardJSON).toTokenBoardEntries().first)
    let (usage, account) = scdSharedLocal()

    // ① 두 기준선이 **실제로 다르다**(이 줄이 없으면 아래 단언이 동어반복인지 알 수 없다).
    //    로컬 산식은 계정 원본을 그대로 쓴다: 1,081,155,290 + 4,228,824,798 + 474,733,497.
    #expect(usage.displayTotal(account: account) == 5_784_713_585)
    #expect(entry.total == 2_844_663_420)
    #expect(usage.displayTotal(account: account) != entry.total)
    #expect(usage.displayTotal(account: account) - entry.total == 2_940_050_165)
    // 갈라진 자리는 Codex 한 항이다 — 클로드·안티그래비티는 서버와 한 톨도 다르지 않다.
    #expect(usage.claudeTotal == entry.claudeTotal)
    #expect(usage.antigravityTotal == entry.antigravityEffective)
    #expect(TokenUsageDisplay.codexEffective(local: usage, account: account) == 4_228_824_798)
    #expect(entry.codexEffective == 1_288_774_633)

    // ② 수리: 팝오버가 서버 total 을 그대로 그린다.
    let server = try #require(TokenRowServerValue(entry: entry, month: scdMonth, fetchedAt: scdNow))
    let shown = try #require(TokenRowDisplayRule.resolve(
        local: usage, account: account, server: server, userID: scdSharedUserID, currentMonth: scdMonth
    ))
    #expect(shown.total == entry.total)
    #expect(shown.isFromServer)
    #expect(shown.monthNumber == 9)

    // ③ 툴팁도 순위판 카드와 **글자 하나 다르지 않다**(같은 숫자를 두 어휘로 부르지 않는다).
    #expect(shown.tooltip == entry.detailTooltip)
    #expect(shown.tooltip == "Claude 1,081,155,290 · Codex 1,288,774,633 · 안티그래비티 474,733,497")
    // 툴팁 세 값의 합 == 굵은 총합(검산 가능한 불변식).
    #expect(entry.claudeTotal + entry.codexEffective + entry.antigravityEffective == shown.total)
}

// MARK: - ⓑ 비공유: 바이트 동일 · 비율 정확히 1.0

@Test
func v0336SoloAccountIsUnchangedByTheFix() throws {
    let entry = try #require(scdDecodeBoard(scdSoloBoardJSON).toTokenBoardEntries().first)
    let (usage, account) = scdSoloLocal()

    // 비공유는 서버 몫 = 계정값이라 두 기준선이 이미 같다(2026-09-22 실측: 계정 있는 비공유 기기 15대 전원 차 0).
    #expect(usage.displayTotal(account: account) == entry.total)
    #expect(entry.codexAccountMonth == account.monthTotal(scdMonth))

    let server = try #require(TokenRowServerValue(entry: entry, month: scdMonth, fetchedAt: scdNow))
    let viaServer = try #require(TokenRowDisplayRule.resolve(
        local: usage, account: account, server: server,
        userID: "b9af636b-123d-4dee-ac58-bbd147ff7910", currentMonth: scdMonth
    ))
    let viaLocal = try #require(TokenRowDisplayRule.resolve(
        local: usage, account: account, server: nil, userID: nil, currentMonth: scdMonth
    ))
    // 값·툴팁·월 라벨이 전부 같다 — 바뀌는 것은 출처뿐(그리고 그 사실은 화면에 드러내지 않는다).
    #expect(viaServer.total == viaLocal.total)
    #expect(viaServer.tooltip == viaLocal.tooltip)
    #expect(viaServer.monthNumber == viaLocal.monthNumber)
    #expect(viaServer.isFromServer && !viaLocal.isFromServer)

    // 잔디 비율도 정확히 1.0 — 우연이 아니라 구조다(분모가 '이 맥이 본 계정 월합'이므로).
    #expect(TokenRowDisplayRule.accountShareRatio(server: server, account: account, currentMonth: scdMonth) == 1.0)
}

// MARK: - ⓒ 옛 서버 응답: 폐기된 max 증폭기로 떨어지지 않는다

@Test
func v0336OldServerResponseNeverFeedsThePopover() throws {
    // codex_effective 키가 **아예 없는** 응답(v0.2.43 이전 RPC). 나머지는 공유 사용자 행 그대로.
    let legacyRPC = scdSharedBoardJSON.replacingOccurrences(of: "\"codex_effective\":1288774633,", with: "")
    let entry = try #require(scdDecodeBoard(legacyRPC).toTokenBoardEntries().first)
    #expect(!entry.hasServerCodexEffective)
    // 그때 entry.codexEffective 는 max(로컬, 계정) 미러다 — 이 프로젝트가 폐기한 증폭기.
    #expect(entry.codexEffective == max(entry.codexLocalTotal, entry.codexAccountMonth ?? 0))
    // 그래서 서버 행 자체를 만들지 않는다(구조적 자물쇠).
    #expect(TokenRowServerValue(entry: entry, month: scdMonth, fetchedAt: scdNow) == nil)

    let (usage, account) = scdSharedLocal()
    let shown = try #require(TokenRowDisplayRule.resolve(
        local: usage, account: account, server: nil, userID: scdSharedUserID, currentMonth: scdMonth
    ))
    #expect(!shown.isFromServer)
    #expect(shown.total == usage.displayTotal(account: account))

    // 서버 total 이 0 인 행(업로드가 아직 안 닿음)도 표시로 읽지 않는다 — 첫 설치 사용자의 행이 0 으로 굳지 않게.
    let zeroJSON = scdSharedBoardJSON.replacingOccurrences(of: "\"total\":2844663420", with: "\"total\":0")
    let zeroEntry = try #require(scdDecodeBoard(zeroJSON).toTokenBoardEntries().first)
    let zeroServer = try #require(TokenRowServerValue(entry: zeroEntry, month: scdMonth, fetchedAt: scdNow))
    let zeroShown = try #require(TokenRowDisplayRule.resolve(
        local: usage, account: account, server: zeroServer, userID: scdSharedUserID, currentMonth: scdMonth
    ))
    #expect(!zeroShown.isFromServer)
}

// MARK: - ⓓ 잔디 비율과 계정 버킷 축소

@Test
func v0336GrassShrinksOnlyTheAccountBucket() throws {
    let entry = try #require(scdDecodeBoard(scdSharedBoardJSON).toTokenBoardEntries().first)
    let server = try #require(TokenRowServerValue(entry: entry, month: scdMonth, fetchedAt: scdNow))
    let (usage, account) = scdSharedLocal()

    // 공유: 0 < r < 1. 분모는 **이 맥이 본 계정 월합**이다(서버의 진짜 share_ratio 가 아니다 — 그쪽 분모는 그룹 max 스냅샷).
    let ratio = TokenRowDisplayRule.accountShareRatio(server: server, account: account, currentMonth: scdMonth)
    #expect(ratio > 0 && ratio < 1)
    #expect(abs(ratio - 1_191_490_526.0 / 4_228_824_798.0) < 1e-12)
    // 이 비율을 이 맥의 버킷에 곱하면 잔디의 이번 달 Codex 합이 정확히 **내 몫**이 된다(잔디가 '계정의 잔디'가 아니게).
    let scaledSum = account.buckets.values.reduce(0) { $0 + TokenRowDisplayRule.scaledAccountBucket($1, ratio: ratio) }
    #expect(abs(scaledSum - 1_191_490_526) <= 1)

    // 분모가 없거나 달이 다르면 1.0(모르면 줄이지 않는다).
    #expect(TokenRowDisplayRule.accountShareRatio(server: server, account: nil, currentMonth: scdMonth) == 1.0)
    #expect(TokenRowDisplayRule.accountShareRatio(server: server, account: account, currentMonth: "2026-08") == 1.0)
    let emptyAccount = CodexAccountUsage(fetchedAt: scdNow, lifetimeTokens: nil, buckets: [:])
    #expect(TokenRowDisplayRule.accountShareRatio(server: server, account: emptyAccount, currentMonth: scdMonth) == 1.0)

    // **상한 1.0 클램프**: 그룹 월합은 멤버 중 가장 최신 스냅샷이라 내 몫이 이 맥이 본 계정 월합을 넘을 수 있다.
    // 2026-09-22 실측 '수 빈': 이 맥의 계정 월합 667,859,401 인데 서버 몫이 1,164,288,567(비율 1.74).
    // 클램프가 없으면 그 사람 잔디가 통째로 밝아진다 — 관측하지 않은 사용량을 그리지 않는다.
    let subinBoard = scdSharedBoardJSON
        .replacingOccurrences(of: "\"codex_account_month\":1191490526", with: "\"codex_account_month\":1164288567")
    let subinEntry = try #require(scdDecodeBoard(subinBoard).toTokenBoardEntries().first)
    let subinServer = try #require(TokenRowServerValue(entry: subinEntry, month: scdMonth, fetchedAt: scdNow))
    let smallAccount = CodexAccountUsage(fetchedAt: scdNow, lifetimeTokens: nil, buckets: ["2026-09-20": 667_859_401])
    #expect(TokenRowDisplayRule.accountShareRatio(
        server: subinServer, account: smallAccount, currentMonth: scdMonth) == 1.0)

    // 옛 표가 이긴 행(codex_account_month = null · codex_effective = 로컬): 서버 행은 **만들어지고**(codex_effective 가 왔다)
    // 비율은 1.0(분자 nil) → 잔디 무변화, 표시는 서버 total = 순위판과 일치.
    let legacyWon = scdSharedBoardJSON
        .replacingOccurrences(of: "\"codex_account_month\":1191490526", with: "\"codex_account_month\":null")
    let legacyEntry = try #require(scdDecodeBoard(legacyWon).toTokenBoardEntries().first)
    let legacyServer = try #require(TokenRowServerValue(entry: legacyEntry, month: scdMonth, fetchedAt: scdNow))
    #expect(legacyServer.codexAccountShare == nil)
    #expect(TokenRowDisplayRule.accountShareRatio(
        server: legacyServer, account: account, currentMonth: scdMonth) == 1.0)
    let legacyShown = try #require(TokenRowDisplayRule.resolve(
        local: usage, account: account, server: legacyServer, userID: scdSharedUserID, currentMonth: scdMonth
    ))
    #expect(legacyShown.isFromServer && legacyShown.total == legacyEntry.total)
}

@Test
func v0336DailyMergeScalesAccountBucketsButNotLocalTails() {
    // 손으로 적은 기대값. 계정 버킷 1,000(반영된 날)·마지막 버킷 날 09-03(400) 뒤의 꼬리 09-04(700).
    var usage = TokenUsageMonthly(month: "2026-09")
    usage.claudeDaily = ["2026-09-02": 50]
    usage.codexDailyUTC = ["2026-09-02": 999, "2026-09-03": 100, "2026-09-04": 700]
    let account = CodexAccountUsage(
        fetchedAt: scdNow, lifetimeTokens: nil, buckets: ["2026-09-02": 1_000, "2026-09-03": 400]
    )

    let full = TokenDailyMerge.localTotals(usage: usage, account: account)
    // 비율 1.0 은 **항등**이다(비공유 사용자의 잔디는 한 칸도 다르지 않다).
    #expect(TokenDailyMerge.localTotals(usage: usage, account: account, accountShareRatio: 1.0) == full)
    #expect(full["2026-09-02"] == 50 + 1_000)          // 반영된 날 = 계정 버킷(로컬 999 는 안 쓴다)
    #expect(full["2026-09-03"] == 400)                 // 마지막 버킷 날 = max(버킷 400, 로컬 100)
    #expect(full["2026-09-04"] == 700)                 // 꼬리 = 로컬 그대로

    let half = TokenDailyMerge.localTotals(usage: usage, account: account, accountShareRatio: 0.5)
    #expect(half["2026-09-02"] == 50 + 500)            // 계정 버킷만 절반
    // 마지막 버킷 날은 max(줄인 버킷 200, 로컬 100) = 200. 내 로컬은 이미 내 것이라 줄이지 않는다.
    #expect(half["2026-09-03"] == 200)
    #expect(half["2026-09-04"] == 700)                 // **로컬 꼬리는 그대로** — 서버도 꼬리엔 share_ratio 를 안 건다

    // 마지막 버킷 날짜 판정은 **축소 전** 키로 한다 — 비율이 0.27 이어도 날짜가 밀리면 안 된다.
    let tiny = TokenDailyMerge.localTotals(usage: usage, account: account, accountShareRatio: 0.001)
    #expect(tiny["2026-09-02"] == 50 + 1)              // round(1000 * 0.001) = 1, 여전히 '반영된 날'
    #expect(tiny["2026-09-04"] == 700)

    // 서버 원천도 같은 규칙(계정 버킷 하나만 곱한다).
    let rows = [
        TokenUsageDailyRow(day: "2026-09-02", deviceId: "A", claudeTotal: 50, codexTotal: 999,
                           codexAccount: 1_000, codexUtcTotal: 999),
        TokenUsageDailyRow(day: "2026-09-03", deviceId: "A", claudeTotal: 0, codexTotal: 100,
                           codexAccount: 400, codexUtcTotal: 100),
        TokenUsageDailyRow(day: "2026-09-04", deviceId: "A", claudeTotal: 0, codexTotal: 700,
                           codexAccount: nil, codexUtcTotal: 700),
    ]
    #expect(TokenDailyMerge.serverTotals(rows) == TokenDailyMerge.serverTotals(rows, accountShareRatio: 1.0))
    let halfServer = TokenDailyMerge.serverTotals(rows, accountShareRatio: 0.5)
    #expect(halfServer["2026-09-02"] == 50 + 500)      // 반영된 날 = 줄인 계정 버킷
    #expect(halfServer["2026-09-03"] == 200)           // 마지막 버킷 날 = max(줄인 버킷 200, 로컬 100)
    #expect(halfServer["2026-09-04"] == 700)           // 꼬리는 로컬 그대로
}

// MARK: - ⓔ/ⓕ 달 가드 · userID 가드

@Test
func v0336ServerRowIsIgnoredForAnotherMonthOrAnotherPerson() throws {
    let entry = try #require(scdDecodeBoard(scdSharedBoardJSON).toTokenBoardEntries().first)
    let (usage, account) = scdSharedLocal()
    let localTotal = usage.displayTotal(account: account)

    // ‹ › 로 8월 보드를 보다 닫고 나와도 팝오버는 이번 달이다.
    let august = try #require(TokenRowServerValue(entry: entry, month: "2026-08", fetchedAt: scdNow))
    let shownAug = try #require(TokenRowDisplayRule.resolve(
        local: usage, account: account, server: august, userID: scdSharedUserID, currentMonth: "2026-09"
    ))
    #expect(!shownAug.isFromServer && shownAug.total == localTotal)

    // 로그아웃/계정 전환 직후 한 프레임이라도 앞 사람 숫자가 뜨지 않게.
    let server = try #require(TokenRowServerValue(entry: entry, month: scdMonth, fetchedAt: scdNow))
    let shownOther = try #require(TokenRowDisplayRule.resolve(
        local: usage, account: account, server: server, userID: "00000000-0000-0000-0000-000000000000",
        currentMonth: scdMonth
    ))
    #expect(!shownOther.isFromServer && shownOther.total == localTotal)
    let shownNoID = try #require(TokenRowDisplayRule.resolve(
        local: usage, account: account, server: server, userID: nil, currentMonth: scdMonth
    ))
    #expect(!shownNoID.isFromServer)

    // 낡음을 이유로 되돌아가지 않는다 — fetchedAt 이 한참 전이어도 서버값을 유지한다(그게 곧 max 증폭기의 재발명이다).
    let stale = try #require(TokenRowServerValue(entry: entry, month: scdMonth, fetchedAt: scdNow.addingTimeInterval(-86_400 * 3)))
    let shownStale = try #require(TokenRowDisplayRule.resolve(
        local: usage, account: account, server: stale, userID: scdSharedUserID, currentMonth: scdMonth
    ))
    #expect(shownStale.isFromServer && shownStale.total == entry.total)

    // 로컬도 서버도 없으면 그릴 것이 없다(뷰는 순위판 진입 행으로 간다).
    #expect(TokenRowDisplayRule.resolve(local: nil, account: nil, server: nil, userID: nil, currentMonth: scdMonth) == nil)
    // 로컬 게이트 승계: 세 값이 전부 0 이면 nil.
    #expect(TokenRowDisplayRule.resolve(
        local: TokenUsageMonthly(month: scdMonth), account: nil, server: nil, userID: nil, currentMonth: scdMonth
    ) == nil)
    // 로컬 총합이 0 이어도 계정 월합이 있으면 그린다(`.zst` 만 남은 채 설치한 사람 — 게이트는 짝으로 있어야 한다).
    #expect(TokenRowDisplayRule.resolve(
        local: TokenUsageMonthly(month: scdMonth), account: account, server: nil, userID: nil, currentMonth: scdMonth
    ) != nil)

    // 영속 왕복(재시작 첫 프레임의 깜빡임을 없애는 자리).
    let data = try JSONEncoder().encode(server)
    #expect(try JSONDecoder().decode(TokenRowServerValue.self, from: data) == server)
}

// MARK: - ⓖ SQL 계약 — 보드 14번 칸이 '내 몫'이다

/// Tests/ 전체에 `codex_account_group`·`codex_shared_account_split` 참조가 **0개**였다(2026-09-22 확인).
/// 분배가 일어나는 그 자리를 아무 테스트도 보지 않았다 — 여기서 메운다.
/// ※ 워크트리에는 supabase 폴더가 없다(추적 안 되는 폴더) — 이 테스트는 **메인 저장소에서만** 의미가 있다.
@Test
func v0336BoardSQLExportsMyShareNotTheWholeAccount() throws {
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    let sql = root.appendingPathComponent("supabase/migrations/20260917160000_hidden_accounts.sql")
    guard FileManager.default.fileExists(atPath: sql.path) else { return }   // 워크트리(supabase 폴더 없음)
    // 주석을 걷어낸다 — 안 걷으면 **설명을 지워야만 초록이 되는** 테스트가 된다.
    let body = try String(contentsOf: sql, encoding: .utf8)
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map { line -> Substring in
            guard let range = line.range(of: "--") else { return line }
            return line[line.startIndex..<range.lowerBound]
        }
        .joined(separator: "\n")

    // ① 분배는 codex_account_group(p_month) 이 계산한다.
    #expect(body.contains("public.codex_account_group(p_month)"))
    // ② 보드 14번 칸은 **내 몫**이다(계정 원본이 아니다) — 클라가 이 칸을 잔디 비율의 분자로 쓴다.
    #expect(body.contains("e.codex_account_share as codex_account"))
    // ③ total 의 세 항. 팝오버가 그리는 숫자가 곧 이 식의 값이다.
    #expect(body.contains("(e.claude_total + e.codex_effective + e.antigravity_total)::bigint as total"))
    // ④ codex_effective 는 merged 에서 coalesce(…, 0) → 현행 서버는 언제나 non-null.
    //    그래서 `hasServerCodexEffective == false` 는 곧 '구버전 RPC 로 떨어졌다'는 뜻이고, 그때만 로컬로 돌아간다.
    #expect(body.contains("else g_codex_effective end, 0)::bigint as codex_effective"))
    // ⑤ 비공개로 꺼 둬도 **내 행은 내려온다** — 이 or 가 없으면 비공개 사용자의 팝오버가 영영 로컬로 남는다.
    #expect(body.contains("coalesce(p.token_usage_public, true) or m.uid = auth.uid()"))
}

// MARK: - ⓗ 픽셀까지 닿는가(짝 게이트의 나머지 반쪽)

import SwiftUI

@MainActor
private func scdTokenStore(_ usage: TokenUsageMonthly, label: String = "",
                           function: String = #function) throws -> TokenUsageStore {
    // 역DNS 이름(check.tests.v0336.…)은 ~/Library/Preferences 직행이었다 — 이름도 자리도 CheckTestScratch 에 맡긴다.
    let defaults = CheckTestScratch.defaults(label, function: function)
    defaults.set(try JSONEncoder().encode(usage), forKey: TokenUsageStore.snapshotKey)
    let tmp = CheckTestScratch.directory(label, function: function)
    return TokenUsageStore(
        defaults: defaults,
        homeDirectory: tmp.appendingPathComponent("home", isDirectory: true),
        cacheURL: tmp.appendingPathComponent("cache.json", isDirectory: false),
        clock: { scdNow },
        notificationCenter: NotificationCenter()
    )
}

@MainActor
private func scdRenderPNG(_ view: some View) throws -> Data {
    let renderer = ImageRenderer(content: view.frame(width: 292).fixedSize())
    renderer.scale = 3
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
          let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:])
    else { throw ScdRenderError.failed }
    return png
}

private enum ScdRenderError: Error { case failed }

/// 로컬 산식만으로 정확히 `total` 을 그리는 '거울' 스토어. Claude 한 항에 전부 몰면
/// `displayTotal(account: nil)` = claudeTotal + 0 + 0 = total 이라, 서버 행이 그려야 할 숫자와 **같은 글자**가 나온다.
@MainActor
private func scdMirrorStore(total: Int, label: String = "",
                            function: String = #function) throws -> TokenUsageStore {
    var usage = TokenUsageMonthly(month: TokenUsageMonthKey.current())
    usage.claudeInput = total
    return try scdTokenStore(usage, label: "mirror-" + label, function: function)
}

/// 값이 **픽셀까지** 서버 행으로 바뀌는가. 규칙만 고치고 뷰 인자를 안 넘기면 단위 테스트는 전부 초록인 채
/// 화면만 옛 숫자를 그린다(이 저장소의 '클라 게이트는 짝으로 있다') — 그 사고를 그림으로 잡는다.
///
/// ── **지운 단언과 그 이유**(2026-09-22) ──────────────────────────────────────────────
/// 예전 주 단언은 `local != viaServer`("서버 행을 넘겼는데 그림이 그대로다")였는데, **수리를 끈 사본에서도
/// 통과했다**(18,789B vs 18,786B). 못 잡는 단언은 없느니만 못해서 지웠다. 무엇이 대신 그 회귀를 잡는가는
/// 아래 ①②③ 이다 — 부등호가 아니라 **등호**로 잡는다.
///
/// ── **ImageRenderer 출력의 실제 불안정 폭**(같은 날, 이 맥에서 직접 측정) ─────────────
///  · 프로세스의 첫 렌더들이 뒤따르는 렌더와 다르다. 같은 뷰 12회 연속 = PNG 18,789 · 18,789 · 18,786 …
///    raw RGBA 332,880B 중 **2,719B(0.8%)** 가 다르다.
///  · 서로 다른 내용을 섞으면 정착이 더 늦다(빈 행 3회 워밍업 뒤에도 4~6번째 렌더에서 18,561 → 18,485 로 한 번 더 움직였다).
///  · **여섯 뷰를 전부 한 번 그려 본 뒤로는 완전히 결정적이다**: 같은 6장을 10회전 반복해 바이트가 한 번도 안 흔들렸다.
///  · 값이 실제로 바뀌었을 때의 차이는 4,352B(1.3%)다.
/// 노이즈 2,719 와 신호 4,352 는 허용오차로 가르기엔 너무 가깝다. 그래서 **버리는 1회전(dry pass)** 을 먼저 돌리고
/// 그 뒤의 그림만 정확 비교한다(허용오차 없음).
@MainActor
@Test
func v0336ServerRowIsTheNumberTheRowActuallyDraws() throws {
    let entry = try #require(scdDecodeBoard(scdSharedBoardJSON).toTokenBoardEntries().first)
    let month = TokenUsageMonthKey.current()
    let server = try #require(TokenRowServerValue(entry: entry, month: month, fetchedAt: scdNow))
    // 스냅샷의 달을 '지금'에 맞춘다 — 행은 currentMonth 로 판정한다.
    var usage = scdSharedLocal().0
    usage.month = month
    // 네 스토어가 **서로 다른** 스위트를 써야 한다 — 이름이 같으면 뒤에 만든 쪽이 앞선 쪽의 스냅샷을 비운다.
    let bloated = try scdTokenStore(usage, label: "bloated")    // 수리 전 팝오버가 그리던 로컬 산식
    let mirror = try scdMirrorStore(total: entry.total, label: "a")  // 서버 total 을 로컬만으로 그린 기준 그림
    let emptyStore = try scdTokenStore(TokenUsageMonthly(month: month), label: "empty")
    let emptyMirror = try scdMirrorStore(total: entry.total, label: "b")

    @MainActor
    func renderAll() throws -> (withServer: Data, mirror: Data, local: Data,
                                emptyLocal: Data, emptyWithServer: Data, emptyMirror: Data) {
        (
            try scdRenderPNG(CheckTokenUsageRow(store: bloated, serverRow: server, userID: scdSharedUserID)),
            try scdRenderPNG(CheckTokenUsageRow(store: mirror)),
            try scdRenderPNG(CheckTokenUsageRow(store: bloated)),
            try scdRenderPNG(CheckTokenUsageRow(store: emptyStore, onOpenBoard: {})),
            try scdRenderPNG(CheckTokenUsageRow(store: emptyStore, serverRow: server,
                                                userID: scdSharedUserID, onOpenBoard: {})),
            try scdRenderPNG(CheckTokenUsageRow(store: emptyMirror, onOpenBoard: {}))
        )
    }
    _ = try renderAll()                                          // 버리는 1회전(위 측정의 정착 지점)
    let shot = try renderAll()

    // ① 두 기준선이 **실제로 다르다**. 이 줄이 없으면 ② 의 등호가 동어반복인지 알 수 없다
    //    (메모리 '비교 기준선이 달라야 한다').
    #expect(shot.local != shot.mirror, "부푼 로컬과 서버 total 이 같은 그림이면 이 테스트는 아무것도 못 잡는다")
    // ② 수리: 서버 행을 넘긴 그림이 '서버 total 을 그린 그림'과 **바이트 동일**이다.
    //    뷰가 serverRow 를 안 읽거나 규칙의 서버 분기가 죽으면 이 등호가 곧바로 깨진다.
    #expect(shot.withServer == shot.mirror, "뷰가 서버 행의 숫자를 안 그린다 — 화면은 여전히 분배 전 값이다")
    // ③ 렌더 게이트도 값과 **같은 판정**에서 나온다: 로컬 0 + 서버 행이면 행이 사라지지 않고(순위판 진입 행이 아니고),
    //    그 그림은 '로컬만으로 같은 숫자를 그린 행'과 바이트 동일이다.
    #expect(shot.emptyWithServer != shot.emptyLocal, "로컬 0 + 서버 행 있음에서 숫자 행이 안 떴다")
    #expect(shot.emptyWithServer == shot.emptyMirror, "로컬 0 + 서버 행이 그린 숫자가 서버 total 이 아니다")

    // 남의 행이면 규칙이 로컬 경로를 고른다(계정 전환 직후 한 프레임의 오염 방지). 여기만 픽셀이 아니라 규칙으로 잰다 —
    // 두 그림이 '같아야 한다'가 아니라 '출처가 달라야 한다'는 주장이라 그림으로는 표현되지 않는다(총합이 같을 수도 있다).
    #expect(TokenRowDisplayRule.resolve(
        local: usage, account: nil, server: server,
        userID: "00000000-0000-0000-0000-000000000000", currentMonth: month
    )?.isFromServer == false)

    // ※ 툴팁은 이 그림에 안 나온다(거울 스토어의 툴팁은 "Claude 2,844,663,420" 으로 서버 행과 다른데 바이트가 같다).
    //   툴팁 일치는 위 ⓐ 테스트가 규칙 수준에서 글자 그대로 못 박는다.
}

// MARK: - ⓗ 폰 [나] 탭 잔디: 관측 분모로 만드는 공유 비율 (v0.3.36)
//
// 결함: 폰은 `TokenDailyMerge.serverTotals` 를 **비율 인자 없이** 불러(`MeStoreRecords`) 계정 버킷
// (= 공유 그룹 전체의 하루 사용량)을 그대로 '내 잔디'로 그렸다. 맥은 같은 함수를 `WorkTimerStoreInsights` 에서
// 비율과 함께 부른다 — **폰에만 빠져 있었다**. 2026-09-22 조사 기준 공유 그룹 11명의 오차는 1.05~19.15배
// (맥주밤거리엠버서더 19.15 · 아 4.80 · 김공룡 3.61 · ㅂ보예성 3.40 · 수 빈 2.72 …).
//
// 폰은 맥과 **분모가 다르다**: 폰에는 로컬 스캐너가 없어 `CodexAccountUsage` 자체가 만들어지지 않는다.
// 그래서 분모를 서버 일별 계정 버킷의 그 달 합(`TokenDailyMerge.accountBucketSum`)으로 만들고,
// 분자는 맥과 같은 값(보드 14번 칸 `codex_account_month` = 이미 나눈 내 몫)을 쓴다.

private func scdPhoneRow(
    _ day: String, _ device: String, claude: Int = 0, codex: Int = 0, account: Int? = nil
) -> TokenUsageDailyRow {
    TokenUsageDailyRow(day: day, deviceId: device, claudeTotal: claude, codexTotal: codex,
                       codexAccount: account, codexUtcTotal: codex)
}

@Test
func v0336PhoneAccountBucketSumIsMaxPerDayWithinOneMonth() {
    let rows = [
        // 같은 날 기기 두 대. 둘 다 같은 계정을 읽지만 스냅샷 시각이 달라 값이 어긋난다 → **max**(더하면 기기 수만큼 뻥튀기).
        scdPhoneRow("2026-09-10", "MAC-A", claude: 5_000, codex: 100, account: 1_000),
        scdPhoneRow("2026-09-10", "MAC-B", claude: 7_000, codex: 200, account: 600),
        scdPhoneRow("2026-09-11", "MAC-A", codex: 300, account: 400),
        scdPhoneRow("2026-09-12", "MAC-A", codex: 700, account: nil),   // 버킷 미보고 — 안 센다("0" 과 다르다)
        scdPhoneRow("2026-08-31", "MAC-A", codex: 50, account: 9_999),  // 다른 달 — 빠진다
    ]
    #expect(TokenDailyMerge.accountBucketSum(rows, month: "2026-09") == 1_400, "기기 간 sum(2,000) 으로 셌다")
    #expect(TokenDailyMerge.accountBucketSum(rows, month: "2026-08") == 9_999)
    #expect(TokenDailyMerge.accountBucketSum(rows, month: "2026-07") == 0)
    #expect(TokenDailyMerge.accountBucketSum([], month: "2026-09") == 0)
    // 계정 버킷이 하나도 없으면 0 — Codex 계정이 없는 사람은 여기서 게이트에 걸려 보드 RPC 를 한 번도 안 쏜다.
    #expect(TokenDailyMerge.accountBucketSum([scdPhoneRow("2026-09-10", "MAC-A", codex: 700)], month: "2026-09") == 0)
    // 접두어에 '-' 를 붙이는 이유: '2026-0' 이 '2026-09-10' 에 걸리면 안 된다.
    #expect(TokenDailyMerge.accountBucketSum(rows, month: "2026-0") == 0)
    // Claude 는 분모에 끼지 않는다(비율은 계정 버킷에만 곱한다).
    #expect(TokenDailyMerge.accountBucketSum(
        [scdPhoneRow("2026-09-10", "MAC-A", claude: 999_999, account: 10)], month: "2026-09") == 10)
}

@Test
func v0336PhoneBucketSumAndServerTotalsShareTheSameFold() {
    // 계정 날의 로컬을 0 으로 둬 계정 버킷만 잔디에 남게 한다(마지막 버킷 날도 max(줄인 버킷, 0) = 줄인 버킷).
    let days = ["2026-09-02", "2026-09-03", "2026-09-04", "2026-09-05"]
    var rows: [TokenUsageDailyRow] = []
    for (index, day) in days.enumerated() {
        let bucket = 1_000 + index * 337
        rows.append(scdPhoneRow(day, "MAC-A", account: bucket))
        rows.append(scdPhoneRow(day, "MAC-B", account: bucket - 11))   // 뒤처진 기기 — max 가 이긴다
    }
    rows.append(scdPhoneRow("2026-09-06", "MAC-A", claude: 12_345, codex: 6_789))   // 계정 없는 꼬리
    let bucketSum = TokenDailyMerge.accountBucketSum(rows, month: "2026-09")
    #expect(bucketSum == days.indices.reduce(0) { $0 + 1_000 + $1 * 337 })

    let ratio = 0.375
    let full = TokenDailyMerge.serverTotals(rows)
    let scaled = TokenDailyMerge.serverTotals(rows, accountShareRatio: ratio)
    let drop = days.reduce(0) { $0 + (full[$1] ?? 0) - (scaled[$1] ?? 0) }
    // 줄어든 총량 == 분모 × (1 − 비율). 분모를 **다른 루프**로 만들면(예: 기기 간 sum) 여기서 곧바로 어긋난다.
    #expect(abs(Double(drop) - Double(bucketSum) * (1 - ratio)) <= Double(days.count) / 2,
            "분모와 잔디가 같은 fold 를 안 쓴다: drop \(drop), 분모 \(bucketSum)")
    // 계정이 없는 꼬리 날은 한 토큰도 안 줄었다(로컬은 이미 내 것이다).
    #expect(full["2026-09-06"] == scaled["2026-09-06"])
}

@Test
func v0336PhoneShareRatioFromObservedBucketSum() {
    // share == nil → 1.0(옛 표가 이긴 행·미로그인 기기). **share == 0 은 nil 과 다르다** — 진짜 몫 0.
    #expect(TokenRowDisplayRule.accountShareRatio(share: nil, bucketSum: 1_000) == 1.0)
    #expect(TokenRowDisplayRule.accountShareRatio(share: 0, bucketSum: 1_000) == 0.0)
    // 0 나눗셈 가드(분모가 0 이면 곱할 버킷도 없어 산술적으로 무변화다).
    #expect(TokenRowDisplayRule.accountShareRatio(share: 250, bucketSum: 0) == 1.0)
    #expect(TokenRowDisplayRule.accountShareRatio(share: 250, bucketSum: -5) == 1.0)
    // 상한 클램프: 분자는 그룹에서 가장 최신인 남의 스냅샷, 분모는 내가 관측한 버킷이라 넘을 수 있다('수 빈' 1.74).
    #expect(TokenRowDisplayRule.accountShareRatio(share: 1_500, bucketSum: 1_000) == 1.0)
    #expect(TokenRowDisplayRule.accountShareRatio(share: -20, bucketSum: 1_000) == 0.0)
    #expect(TokenRowDisplayRule.accountShareRatio(share: 250, bucketSum: 1_000) == 0.25)
    #expect(abs(TokenRowDisplayRule.accountShareRatio(share: 1_191_490_526, bucketSum: 4_228_824_798)
                - 1_191_490_526.0 / 4_228_824_798.0) < 1e-12)
}

/// 위임 **전** 맥 판의 본체를 글자 그대로 옮긴 기준선. 같은 함수로 좌우를 재면 동어반복이라
/// (메모리 '비교 기준선이 달라야 한다') 기준선을 여기 따로 적는다.
private func scdLegacyMacRatio(
    server: TokenRowServerValue?, account: CodexAccountUsage?, currentMonth: String
) -> Double {
    guard let server, server.month == currentMonth, let share = server.codexAccountShare,
          let whole = account?.monthTotal(currentMonth), whole > 0
    else { return 1.0 }
    return min(1.0, max(0.0, Double(share) / Double(whole)))
}

@Test
func v0336PhoneMacRatioKeepsItsAnswersAfterDelegating() throws {
    let base = try #require(scdDecodeBoard(scdSharedBoardJSON).toTokenBoardEntries().first)
    func server(share: String) throws -> TokenRowServerValue {
        let json = scdSharedBoardJSON.replacingOccurrences(
            of: "\"codex_account_month\":1191490526", with: "\"codex_account_month\":\(share)")
        let entry = try #require(scdDecodeBoard(json).toTokenBoardEntries().first)
        return try #require(TokenRowServerValue(entry: entry, month: scdMonth, fetchedAt: scdNow))
    }
    let normal = try #require(TokenRowServerValue(entry: base, month: scdMonth, fetchedAt: scdNow))
    let overflowing = try server(share: "9999999999")   // 몫 > 이 맥의 계정 월합(클램프)
    let legacyWon = try server(share: "null")           // 몫 nil
    let zeroShare = try server(share: "0")              // 몫 0
    let account = scdSharedLocal().1
    let emptyAccount = CodexAccountUsage(fetchedAt: scdNow, lifetimeTokens: nil, buckets: [:])

    let cases: [(String, TokenRowServerValue?, CodexAccountUsage?, String)] = [
        ("일반", normal, account, scdMonth),
        ("클램프", overflowing, account, scdMonth),
        ("몫 nil", legacyWon, account, scdMonth),
        ("몫 0", zeroShare, account, scdMonth),
        ("달 불일치", normal, account, "2026-08"),
        ("account nil", normal, nil, scdMonth),
        ("whole 0", normal, emptyAccount, scdMonth),
        ("server nil", nil, account, scdMonth),
    ]
    for (label, s, a, month) in cases {
        #expect(TokenRowDisplayRule.accountShareRatio(server: s, account: a, currentMonth: month)
                == scdLegacyMacRatio(server: s, account: a, currentMonth: month), "위임이 '\(label)' 의 답을 바꿨다")
    }
    // 맥 호출부의 분모는 여전히 **이 맥의 계정 월합**이다(폰의 관측 분모와 다르다 — 두 판이 섞이지 않았는가).
    #expect(TokenRowDisplayRule.accountShareRatio(server: normal, account: account, currentMonth: scdMonth)
            == TokenRowDisplayRule.accountShareRatio(share: 1_191_490_526, bucketSum: 4_228_824_798))
}

@Test
func v0336PhoneSoloUserGrassIsUnchangedToTheCell() {
    // 비공유: 버킷을 올린 스냅샷이 하나뿐이고, 보드가 준 내 몫이 그 버킷 합과 **같다**(서버 SQL 의 구조적 결과 —
    // group_key 가 null 인 사람은 `r.codex_account` 가 그대로 몫이 된다).
    let rows = [
        scdPhoneRow("2026-09-01", "MAC-A", claude: 3_000, codex: 120, account: 4_018_958_385),
        scdPhoneRow("2026-09-21", "MAC-A", claude: 900, codex: 150_000_000, account: 209_866_413),
        scdPhoneRow("2026-09-22", "MAC-A", claude: 10, codex: 77_000),   // 꼬리
    ]
    let bucketSum = TokenDailyMerge.accountBucketSum(rows, month: "2026-09")
    #expect(bucketSum == 4_228_824_798)
    let ratio = TokenRowDisplayRule.accountShareRatio(share: bucketSum, bucketSum: bucketSum)
    #expect(ratio == 1.0, "비공유 비율이 1.0 이 아니면 그 사람 잔디가 이유 없이 어두워진다")
    // 항등 — 수리 전후 잔디가 한 칸도 다르지 않다(fold 를 쪼갠 뒤에도).
    #expect(TokenDailyMerge.serverTotals(rows, accountShareRatio: ratio) == TokenDailyMerge.serverTotals(rows))
    #expect(TokenDailyMerge.serverTotals(rows) == TokenDailyMerge.serverTotals(rows, accountShareRatio: 1.0))
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    #expect(TokenDailyGrid.build(daily: TokenDailyMerge.serverTotals(rows, accountShareRatio: ratio), now: now)
            == TokenDailyGrid.build(daily: TokenDailyMerge.serverTotals(rows), now: now))
}

@Test
func v0336PhoneSharedUserMonthGrassSumsToMyShare() {
    // 마지막 버킷 날의 로컬이 '줄인 버킷' 보다 작은 모양(그래야 그 달 Codex 합이 정확히 내 몫이 된다).
    let rows = [
        scdPhoneRow("2026-09-01", "MAC-A", account: 4_018_958_385),
        scdPhoneRow("2026-09-21", "MAC-A", codex: 10_000_000, account: 209_866_413),
    ]
    let share = 1_191_490_526
    let bucketSum = TokenDailyMerge.accountBucketSum(rows, month: "2026-09")
    let ratio = TokenRowDisplayRule.accountShareRatio(share: share, bucketSum: bucketSum)
    #expect(ratio > 0 && ratio < 1)
    let totals = TokenDailyMerge.serverTotals(rows, accountShareRatio: ratio)
    let monthSum = totals.reduce(0) { $0 + ($1.key.hasPrefix("2026-09-") ? $1.value : 0) }
    // Σround 의 반올림만큼만 어긋난다(날짜 수 / 2).
    #expect(abs(monthSum - share) <= 1, "그 달 잔디 합 \(monthSum) 이 내 몫 \(share) 과 다르다")
    // 수리 전(비율 없음)이었다면 계정 전체(= 그룹 전체)를 그렸다 — 두 기준선이 실제로 다르다.
    let before = TokenDailyMerge.serverTotals(rows).reduce(0) { $0 + ($1.key.hasPrefix("2026-09-") ? $1.value : 0) }
    #expect(before == bucketSum)
    #expect(before > monthSum * 3, "기준선이 안 다르면 이 테스트는 아무것도 못 잡는다")
}

@Test
func v0336PhoneRatioReachesEveryMonthInTheWindow() {
    // 잔디 창은 13주(`MeText.insightsWindowStart`)이고 일별 조회도 `day gte since` 라 계정 버킷이 **3~4개 달**에 걸친다.
    // 비율은 '이번 달' 보드 행 하나에서 나오지만 **창 전체**에 건다(의도한 근사 — serverTotals 머리 주석).
    // 이 단언이 없으면 '마지막 버킷 날과 같은 달만 줄인다' 로 바꿔도 전부 초록이고, 공유 사용자 잔디의 앞 2~3개 달이
    // 계정 전체(최대 19.15배)로 조용히 되돌아간다.
    let rows = [
        scdPhoneRow("2026-07-20", "MAC-A", account: 1_000),
        scdPhoneRow("2026-08-20", "MAC-A", account: 1_000),
        scdPhoneRow("2026-09-10", "MAC-A", account: 1_000),
        scdPhoneRow("2026-09-11", "MAC-A", account: 1_000),   // 마지막 버킷 날(로컬 0 이라 max 가 줄인 버킷을 고른다)
    ]
    let totals = TokenDailyMerge.serverTotals(rows, accountShareRatio: 0.25)
    #expect(totals["2026-07-20"] == 250, "지난지난 달 버킷이 안 줄었다 — 비율이 이번 달에만 걸린다")
    #expect(totals["2026-08-20"] == 250, "지난 달 버킷이 안 줄었다 — 비율이 이번 달에만 걸린다")
    #expect(totals["2026-09-10"] == 250)
    #expect(totals["2026-09-11"] == 250)
    // 기준선이 실제로 다르다(비율 없이는 네 칸 모두 계정 전체다).
    let before = TokenDailyMerge.serverTotals(rows)
    #expect(before["2026-07-20"] == 1_000 && before["2026-08-20"] == 1_000)
}

@Test
func v0336PhoneLastBucketDayComesFromPreScaleKeys() {
    // 마지막 버킷 날의 버킷이 아주 작으면(줄이면 0 으로 반올림) '축소 **후** 키'로 lastDay 를 뽑는 구현은
    // 날짜가 하루 앞으로 밀린다 → 그 앞 칸이 통째로 '마지막 날 = max(버킷, 로컬)' 로 갈아타 잔디 모양이 바뀐다.
    let rows = [
        scdPhoneRow("2026-09-10", "MAC-A", codex: 900, account: 1_000),
        scdPhoneRow("2026-09-11", "MAC-A", codex: 700, account: 1),
    ]
    let totals = TokenDailyMerge.serverTotals(rows, accountShareRatio: 0.27)
    #expect(TokenRowDisplayRule.scaledAccountBucket(1, ratio: 0.27) == 0, "전제: 마지막 버킷이 0 으로 반올림된다")
    // 09-10 은 여전히 '반영된 날' = 줄인 버킷 270(로컬 900 을 쓰지 않는다). lastDay 가 밀리면 900 이 된다.
    #expect(totals["2026-09-10"] == 270, "마지막 버킷 날짜가 축소 뒤 키에서 나왔다")
    #expect(totals["2026-09-11"] == 700)   // 마지막 버킷 날 = max(0, 로컬 700)
}
