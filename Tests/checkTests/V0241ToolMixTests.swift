import Foundation
import Testing
@testable import check

// v0.2.41 — 순위판에 "누가 어떤 AI 를 얼마나 썼는지"(GitHub issue #5).
//
// 서버는 이미 사람마다 Claude 4필드 · Codex 로컬/캐시/계정 집계를 내려주고 있었고(token_usage_board),
// TokenBoardRow/TokenBoardEntry 도 전부 담아 나르고 있었다 — **화면에서만 안 쓰고 있었다**.
// 여기서 고정하는 것은 그 값을 좁은 캡션 한 줄로 옮기는 순수 규칙 셋이다:
//   1) TokenNumberFormatter.compactKorean — 억/만 축약(캡션 전용).
//   2) TokenBoardEntry.toolUsageLabel     — 0 이 아닌 도구만 잇고, 둘 다 0 이면 nil(줄 자체가 없다).
//   3) TokenBoardEntry.detailTooltip      — 툴팁은 여전히 grouped 로 1의 자리까지.

// MARK: - C1. 축약 포맷터

@Test
func compactKoreanAbbreviatesOnlyAboveTheManAndEokBoundaries() {
    // 1만 미만은 축약하지 않는다 — grouped 그대로다(이 구간은 좁은 캡션에도 통째로 들어간다).
    #expect(TokenNumberFormatter.compactKorean(0) == "0")
    #expect(TokenNumberFormatter.compactKorean(999) == "999")
    #expect(TokenNumberFormatter.compactKorean(8_432) == "8,432")
    // 만 경계: 9,999 는 아직 아니고 10,000 부터 만 단위다(경계는 >= 10_000).
    #expect(TokenNumberFormatter.compactKorean(9_999) == "9,999")
    #expect(TokenNumberFormatter.compactKorean(10_000) == "1만")
    // 만 단위는 정수 반올림 — 254만(2,543,110 → 254.311만) · 올림 쪽(2,545,000 → 255만)도 함께 못 박는다.
    #expect(TokenNumberFormatter.compactKorean(2_543_110) == "254만")
    #expect(TokenNumberFormatter.compactKorean(2_545_000) == "255만")
    #expect(TokenNumberFormatter.compactKorean(12_340_000) == "1,234만")
    // 억 경계: 99,999,999 는 아직 만이고 100,000,000 부터 억이다(경계는 >= 100_000_000).
    #expect(TokenNumberFormatter.compactKorean(99_990_000) == "9,999만")
    #expect(TokenNumberFormatter.compactKorean(100_000_000) == "1억")
    // 억 단위는 소수 첫째 자리까지. 이슈에 나온 실측값(196.5896…억)이 196.6억으로 반올림된다.
    #expect(TokenNumberFormatter.compactKorean(19_658_964_272) == "196.6억")
    #expect(TokenNumberFormatter.compactKorean(640_000_000) == "6.4억")
    // 소수 첫째 자리가 0 이면 소수를 뗀다 — "200.0억" 은 좁은 캡션에서 두 글자를 헛되이 먹는다.
    #expect(TokenNumberFormatter.compactKorean(20_000_000_000) == "200억")
    #expect(TokenNumberFormatter.compactKorean(4_564_338_243) == "45.6억")
    // 1000억 이상은 소수 없이 천단위 콤마.
    #expect(TokenNumberFormatter.compactKorean(123_400_000_000) == "1,234억")
    // 소수 자리가 있어도 1000억 위에서는 반올림해 없앤다("1,234.5억"은 좁은 캡션에서 폭만 먹는다).
    #expect(TokenNumberFormatter.compactKorean(123_450_000_000) == "1,235억")
    #expect(TokenNumberFormatter.compactKorean(100_000_000_000) == "1,000억")
    // 1000억 경계 바로 아래도 소수 자리가 0 이라 "999.99…억" 이 아니라 정수로 반올림돼 나온다(표기 어휘 일관).
    #expect(TokenNumberFormatter.compactKorean(99_999_999_999) == "1,000억")
    // 만 반올림이 1억(=10,000만)에 닿으면 억 표기로 올린다 — 같은 크기를 두 어휘로 부르지 않는다.
    #expect(TokenNumberFormatter.compactKorean(99_995_000) == "1억")
    // 음수는 grouped 와 같은 방어적 클램프.
    #expect(TokenNumberFormatter.compactKorean(-1) == "0")
    #expect(TokenNumberFormatter.compactKorean(-9_999_999) == "0")
}

@Test
func headlineAndTooltipNumbersStayUnabbreviated() {
    // 축약은 좁은 캡션 한 줄에서만 쓴다는 규약 — 헤드라인/툴팁이 쓰는 grouped 는 여전히 1의 자리까지다.
    // (이 두 함수가 같은 값을 다르게 쓰는 것이 의도된 설계임을 못 박는다.)
    #expect(TokenNumberFormatter.grouped(19_658_964_272) == "19,658,964,272")
    #expect(TokenNumberFormatter.compactKorean(19_658_964_272) == "196.6억")
}

// MARK: - C2. 캡션 · 툴팁 (순수)

/// 보드 엔트리 픽스처. 기본은 전부 0 이라 각 테스트가 필요한 축만 채운다.
private func toolMixEntry(
    claudeInput: Int = 0,
    claudeOutput: Int = 0,
    claudeCacheRead: Int = 0,
    claudeCacheCreation: Int = 0,
    codexInput: Int = 0,
    codexOutput: Int = 0,
    codexCacheRead: Int = 0,
    codexAccountMonth: Int? = nil
) -> TokenBoardEntry {
    let claude = claudeInput + claudeOutput + claudeCacheRead + claudeCacheCreation
    let codex = max(codexInput + codexOutput, codexAccountMonth ?? 0)
    return TokenBoardEntry(
        userID: "u1", name: "영식", avatarURL: nil,
        // 서버 규약과 같은 총합(claude 합 + greatest(codex 로컬, codex 계정))을 픽스처에서도 지킨다.
        total: claude + codex,
        claudeInput: claudeInput, claudeOutput: claudeOutput,
        claudeCacheRead: claudeCacheRead, claudeCacheCreation: claudeCacheCreation,
        codexInput: codexInput, codexOutput: codexOutput,
        codexCacheRead: codexCacheRead, codexAccountMonth: codexAccountMonth
    )
}

@Test
func toolUsageLabelJoinsOnlyTheToolsThatWereActuallyUsed() {
    // 둘 다 있으면 ` · ` 로 잇는다.
    let both = toolMixEntry(claudeInput: 19_658_964_272, codexInput: 2_543_110)
    #expect(both.toolUsageLabel == "Claude 196.6억 · Codex 254만")
    // 한쪽만 쓴 사람은 그 한쪽만 — 안 쓴 도구를 "Codex 0" 으로 적으면 안 쓴 것과 못 읽은 것이 구분되지 않는다.
    #expect(toolMixEntry(claudeInput: 19_658_964_272).toolUsageLabel == "Claude 196.6억")
    #expect(toolMixEntry(codexInput: 2_543_110).toolUsageLabel == "Codex 254만")
    // Claude 는 4필드 합이 기준이다(캐시만 쌓인 사람도 캡션이 뜬다).
    #expect(toolMixEntry(claudeCacheRead: 12_345).toolUsageLabel == "Claude 1만")
}

@Test
func toolUsageLabelIsNilWhenNobodyUsedAnything() {
    // 둘 다 0 이면 nil — 뷰가 줄 자체를 그리지 않아, 한 번도 안 올린 사람의 행이 한 줄로 유지된다.
    #expect(toolMixEntry().toolUsageLabel == nil)
    // 계정 집계까지 0 이어도 마찬가지(0 은 "안 썼다"이지 "모른다"가 아니다).
    #expect(toolMixEntry(codexAccountMonth: 0).toolUsageLabel == nil)
    // 계정 집계가 nil(옛 RPC — "모름")이고 로컬도 0 이면 역시 없다.
    #expect(toolMixEntry(codexAccountMonth: nil).toolUsageLabel == nil)
}

@Test
func toolUsageLabelUsesEffectiveCodexNotTheLocalSum() {
    // 계정 집계가 로컬보다 크면 순위(우측 굵은 총합)에 쓰인 값이 계정값이다 — 캡션도 같은 값을 써야
    // 두 값의 합이 총합과 맞물린다. 로컬(1,200만)만 쓰면 캡션이 총합보다 작아 그 자체로 모순이 된다.
    let entry = toolMixEntry(claudeInput: 1_000, codexInput: 12_000_000, codexAccountMonth: 300_000_000)
    #expect(entry.codexLocalTotal == 12_000_000)
    #expect(entry.codexEffective == 300_000_000)
    #expect(entry.toolUsageLabel == "Claude 1,000 · Codex 3억")
    // 반대로 계정 집계가 로컬보다 작으면(기기가 더 많이 봤다) 로컬이 기준이다.
    let localWins = toolMixEntry(codexInput: 300_000_000, codexAccountMonth: 12_000_000)
    #expect(localWins.toolUsageLabel == "Codex 3억")
}

@Test
func boardDetailTooltipKeepsTheMyBoxVocabularyAndFullPrecision() {
    // 내 팝오버 행(TokenUsageMonthly.detailTooltip)과 같은 어휘·같은 정밀도(grouped) — 순위판과 내 박스가
    // 같은 숫자를 다르게 부르면 그 자체가 결함으로 읽힌다. 캡션의 축약이 실제로 몇인지 확인하는 유일한 자리다.
    let full = toolMixEntry(
        claudeInput: 1, claudeOutput: 2, claudeCacheRead: 3, claudeCacheCreation: 4,
        codexInput: 100, codexOutput: 20, codexCacheRead: 60, codexAccountMonth: 1_000
    )
    // 계정 집계가 쓰였으면 내 박스와 **같은 문구**로 "총합은 계정 집계 기준"이 붙는다 — 이 한 마디가 없으면
    // 툴팁에 Codex 숫자가 둘(로컬 120 · 계정 1,000) 나란히 놓이는데 캡션·굵은 총합이 어느 쪽인지 알 수 없다.
    // v0.2.43: 계정을 아는 행은 로컬 줄에 "로컬 집계" 라벨이 붙는다(두 숫자가 대칭으로 읽히게 — issue #6 제보자 요구).
    #expect(
        full.detailTooltip
            == "Claude 10 (입력 1 · 출력 2 · 캐시읽기 3 · 캐시생성 4) · Codex 로컬 집계 120 (캐시 60) "
            + "· Codex 계정 집계 1,000 · 총합은 계정 집계 기준"
    )
    // 문구는 리터럴로 두 곳에 흩뿌리지 않고 내 박스 상수를 그대로 쓴다(어휘가 갈리는 것을 막는 배선).
    #expect(full.detailTooltip.hasSuffix(TokenUsageMonthly.accountDrivenTotalNote))
    #expect(TokenUsageMonthly.accountDrivenTotalNote == "총합은 계정 집계 기준")
    // v0.2.43: 계정 집계는 로컬보다 작거나 같아도 **함께** 적는다(제보자 요구: 계정·로컬 둘 다 노출). 옛 RPC(codex_effective 없음)에서
    // 동률(120 == 120)이면 총합은 로컬 기준이라 "총합은 계정 집계 기준" 문구만 빠진다.
    let localWins = toolMixEntry(claudeInput: 10, codexInput: 120, codexCacheRead: 60, codexAccountMonth: 120)
    #expect(localWins.detailTooltip == "Claude 10 (입력 10 · 출력 0 · 캐시읽기 0 · 캐시생성 0) · Codex 로컬 집계 120 (캐시 60) · Codex 계정 집계 120")
    // 값이 0 인 소스는 통째로 뺀다(기존 관용구와 동일).
    #expect(toolMixEntry(codexInput: 120, codexCacheRead: 60).detailTooltip == "Codex 120 (캐시 60)")
    #expect(toolMixEntry(claudeInput: 10).detailTooltip == "Claude 10 (입력 10 · 출력 0 · 캐시읽기 0 · 캐시생성 0)")
    // 아무것도 안 쓴 사람은 빈 문자열. `.help("")` 의 동작(빈 말풍선?)은 AppKit 버전마다 갈리고 ImageRenderer 로
    // 확인할 수도 없어(.help 는 픽셀에 안 그려진다) 검증 불가능한 가정을 남기지 않는다 —
    // 뷰가 이 빈 문자열을 보고 툴팁 자체를 안 건다(tokenBoardRowWiresTheToolMixCaptionAndTooltipToTheEntry 가 배선을 고정).
    #expect(toolMixEntry().detailTooltip == "")
    // 큰 값도 축약하지 않는다(캡션은 196.6억, 툴팁은 19,658,964,272 — 같은 카드에서 둘 다 보인다).
    let big = toolMixEntry(claudeInput: 19_658_964_272, codexInput: 2_543_110, codexCacheRead: 1_800_000)
    #expect(big.toolUsageLabel == "Claude 196.6억 · Codex 254만")
    #expect(
        big.detailTooltip
            == "Claude 19,658,964,272 (입력 19,658,964,272 · 출력 0 · 캐시읽기 0 · 캐시생성 0) "
            + "· Codex 2,543,110 (캐시 1,800,000)"
    )
    // 로컬이 0 인데 계정 집계만 있는 사람(기기가 아직 못 읽었지만 계정에는 잡힌다) — 계정 줄만 남는다.
    let accountOnly = toolMixEntry(codexAccountMonth: 300_000_000)
    #expect(accountOnly.detailTooltip == "Codex 계정 집계 300,000,000 · 총합은 계정 집계 기준")
    #expect(accountOnly.toolUsageLabel == "Codex 3억")
}
