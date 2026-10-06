import Foundation
import Testing
@testable import CheckCore

// MARK: - AI 리밋 코어 — 신선도·하한 규칙 경계 고정 (v0.3.45)
//
// 이 스위트가 지키는 것은 **"숫자가 등호인가 하한인가"** 하나다. 규칙의 전제(한 창 안에서 사용률은
// 올라가기만 한다)와 함정 셋은 `AILimitFreshnessRule.swift` 머리말에 있다.
//
// 전부 `Date` 를 주입한 순수 계산이다 — 파일도 네트워크도 `Date()` 도 없다. 그래서 경계를 1초 단위로
// 실증할 수 있고, 스위트 전체가 100ms 아래다(빠른 게이트에 든다).
//
// ⚠️ 경계를 **양쪽에서** 잰다(59초/61초처럼). 한쪽만 재면 임계를 통째로 지워도 초록인 테스트가 된다.

/// 고정 기준 시각. 모든 픽스처가 여기서 파생된다(절대 벽시계에 기대지 않는다).
private let aiNow = Date(timeIntervalSince1970: 1_791_000_000)

private let aiHour: TimeInterval = 3_600
private let aiDay: TimeInterval = 86_400

/// 창 하나의 관측값 픽스처. 기본은 "5시간 창을 방금 봤고 27% 썼다".
private func aiSnapshot(
    window: AILimitWindow = .fiveHour,
    used: Double = 27,
    observedAgo: TimeInterval = 0,
    resetsAt: Date? = nil,
    source: AILimitSource = .local
) -> AILimitWindowSnapshot {
    AILimitWindowSnapshot(
        window: window,
        usedPercent: used,
        resetsAt: resetsAt,
        observedAt: aiNow.addingTimeInterval(-observedAgo),
        source: source
    )
}

@Suite("AILimitsCore — 리밋 신선도·하한 규칙")
struct AILimitsCoreTests {

    // MARK: ① 신선도 경계 — 양쪽에서 잰다

    /// 59초: '방금'. `.fresh` 는 등호로 말한다("이상" 없음).
    @Test func freshBoundaryJustUnder() {
        let display = AILimitFreshnessRule.display(aiSnapshot(observedAgo: 59), now: aiNow)
        #expect(display.freshness == .fresh)
        #expect(display.valueText == "27%")
        #expect(display.captionText == "방금")
        #expect(display.floorOnly == false)
        #expect(display.isVisible)
    }

    /// 61초: 더는 '방금'이 아니다. 하지만 아직 등호다(30분 안).
    @Test func freshBoundaryJustOver() {
        let display = AILimitFreshnessRule.display(aiSnapshot(observedAgo: 61), now: aiNow)
        #expect(display.freshness == .recent)
        #expect(display.valueText == "27%")
        #expect(display.captionText == "1분 전")
        #expect(display.floorOnly == false)
    }

    /// 29분: 아직 `.recent` — 숫자를 등호로 말한다.
    @Test func staleBoundaryJustUnder() {
        let display = AILimitFreshnessRule.display(aiSnapshot(observedAgo: 29 * 60), now: aiNow)
        #expect(display.freshness == .recent)
        #expect(display.valueText == "27%")
        #expect(display.captionText == "29분 전")
    }

    /// 31분: `.stale` 로 넘어가 **"이상"이 붙는다**. 이 전환이 이 기능의 핵심 한 줄이다.
    @Test func staleBoundaryJustOver() {
        let display = AILimitFreshnessRule.display(aiSnapshot(observedAgo: 31 * 60), now: aiNow)
        #expect(display.freshness == .stale)
        #expect(display.valueText == "27% 이상")
        #expect(display.captionText == "31분 전")
        #expect(display.floorOnly)
        #expect(display.percent == 27)
    }

    /// 수 시간(리셋 전): `27% 이상 · 3시간 전`. 캡션 표의 그 줄.
    @Test func staleHoursShowsFloorWithAge() {
        let observed = aiNow.addingTimeInterval(-3 * aiHour)
        let snapshot = aiSnapshot(observedAgo: 3 * aiHour, resetsAt: observed.addingTimeInterval(4 * aiHour))
        let display = AILimitFreshnessRule.display(snapshot, now: aiNow)
        #expect(display.freshness == .stale)
        #expect(display.valueText == "27% 이상")
        #expect(display.captionText == "3시간 전")
    }

    /// 1일 초과(주간 창, 리셋 전): `60% 이상 · 3일 전`. `.ancient` 지만 숫자는 그대로 하한이다.
    @Test func ancientThreeDaysKeepsFloor() {
        let observed = aiNow.addingTimeInterval(-3 * aiDay)
        let snapshot = AILimitWindowSnapshot(
            window: .weekly,
            usedPercent: 60,
            resetsAt: observed.addingTimeInterval(5 * aiDay),   // 아직 안 지났다
            observedAt: observed,
            source: .server
        )
        let display = AILimitFreshnessRule.display(snapshot, now: aiNow)
        #expect(display.freshness == .ancient)
        #expect(display.valueText == "60% 이상")
        #expect(display.captionText == "3일 전")
        #expect(display.floorOnly)
    }

    /// `.stale` → `.ancient` 경계(1일)를 양쪽에서. 둘 다 하한이라 숫자 문구는 같고 캡션 단위만 갈린다.
    @Test func ancientBoundaryBothSides() {
        let justUnder = AILimitFreshnessRule.display(aiSnapshot(observedAgo: aiDay - 1), now: aiNow)
        let justOver = AILimitFreshnessRule.display(aiSnapshot(observedAgo: aiDay + 1), now: aiNow)
        #expect(justUnder.freshness == .stale)
        #expect(justOver.freshness == .ancient)
        #expect(justUnder.floorOnly && justOver.floorOnly)
    }

    // MARK: ② 리셋 유예 밴드 (함정 ②) — 이르게 0% 를 말하지 않는다

    /// 리셋을 지난 지 60초: **아직 주장하지 않는다.** 유예(120초) 안이라 하한을 유지한다.
    /// 이르게 0% 를 말하면 사용자가 큰 작업을 걸고 벽을 맞는다 — 늦게 인정하는 쪽은 손해가 없다.
    @Test func resetGraceBandHoldsClaim() {
        let snapshot = aiSnapshot(used: 40, observedAgo: 2 * aiHour, resetsAt: aiNow.addingTimeInterval(-60))
        let display = AILimitFreshnessRule.display(snapshot, now: aiNow)
        #expect(display.freshness == .stale)
        #expect(display.valueText == "40% 이상")
        #expect(display.captionText == "2시간 전")
        #expect(display.percent == 40)
    }

    /// 유예 직전(119초)에도 주장하지 않는다 — 경계를 반대쪽에서 한 번 더 못 박는다.
    @Test func resetGraceBandHoldsAtEdge() {
        let snapshot = aiSnapshot(used: 40, observedAgo: 2 * aiHour, resetsAt: aiNow.addingTimeInterval(-119))
        #expect(AILimitFreshnessRule.display(snapshot, now: aiNow).freshness == .stale)
    }

    /// 리셋을 지난 지 121초: 유예를 넘었으므로 **0% 를 확신한다**.
    @Test func resetClaimedAfterGrace() {
        let snapshot = aiSnapshot(used: 40, observedAgo: 2 * aiHour, resetsAt: aiNow.addingTimeInterval(-121))
        let display = AILimitFreshnessRule.display(snapshot, now: aiNow)
        #expect(display.freshness == .reset)
        #expect(display.valueText == "0%")
        #expect(display.captionText == "초기화됨")
        #expect(display.percent == 0)
        #expect(display.floorOnly == false)   // 0 은 하한이 아니라 확신이다
    }

    /// 리셋 시각이 **아직 안 왔으면** 당연히 주장하지 않는다.
    @Test func resetNotClaimedBeforeBoundary() {
        let snapshot = aiSnapshot(used: 40, observedAgo: 10 * 60, resetsAt: aiNow.addingTimeInterval(600))
        let display = AILimitFreshnessRule.display(snapshot, now: aiNow)
        #expect(display.freshness == .recent)
        #expect(display.valueText == "40%")
    }

    // MARK: ③ 함정 ① — used 0% 행은 리셋을 주장하지 않는다

    /// Codex 실측(2026-10-07): used 0% 일 때 `reset_at` 이 **요청마다 미끄러지는 "지금+5시간" 투영**이었다.
    /// 창 경계가 아니다. 숫자는 어차피 0 이라 안 바뀌지만, 이걸 리셋으로 읽으면 캡션이 **없던 사건을 단정한다**.
    ///
    /// 그래서 기대값은 "초기화됨"이 **아니다**. 마지막으로 본 0% 를 하한으로 두고 나이만 말한다
    /// (`0% 이상`은 동어반복처럼 보이지만 참이고, 정보는 캡션이 나른다 — 거짓 자신감보다 싸다).
    @Test func zeroPercentRowNeverClaimsReset() {
        let snapshot = aiSnapshot(used: 0, observedAgo: 3 * aiHour, resetsAt: aiNow.addingTimeInterval(-aiHour))
        let display = AILimitFreshnessRule.display(snapshot, now: aiNow)
        #expect(display.freshness == .stale)
        #expect(display.captionText == "3시간 전")
        #expect(display.captionText != "초기화됨")
        #expect(display.percent == 0)
    }

    // MARK: ④ 함정 ③ — 리셋 뒤 나이는 `now - resetsAt` 하나로만 잰다

    /// 주간 창을 9일 전에 봤고 리셋은 3일 전에 지났다 → 0% 는 맞지만 **그 뒤로 확인을 못 했다**.
    /// 다음 경계를 창 길이로 추정하지 않는다(Claude 주간은 월요일 고정, Codex 주간은 계정별 롤링 앵커 — 실측).
    @Test func weeklyNineDayOldResetIsUnverified() {
        let observed = aiNow.addingTimeInterval(-9 * aiDay)
        let snapshot = AILimitWindowSnapshot(
            window: .weekly,
            usedPercent: 73,
            resetsAt: observed.addingTimeInterval(6 * aiDay),   // = 지금으로부터 3일 전
            observedAt: observed,
            source: .server
        )
        let display = AILimitFreshnessRule.display(snapshot, now: aiNow)
        #expect(display.freshness == .resetUnverified)
        #expect(display.valueText == "0%")
        #expect(display.captionText == "초기화됨 · 확인 못 함")
        #expect(display.claimAge == 3 * aiDay)   // 관측(9일)이 아니라 리셋(3일)으로 잰다
    }

    /// `.reset` → `.resetUnverified` 경계(30분)를 양쪽에서.
    @Test func resetVerifiedBoundaryBothSides() {
        func display(resetAgo: TimeInterval) -> AILimitDisplay {
            AILimitFreshnessRule.display(
                aiSnapshot(used: 55, observedAgo: 4 * aiHour, resetsAt: aiNow.addingTimeInterval(-resetAgo)),
                now: aiNow
            )
        }
        #expect(display(resetAgo: 1_800).freshness == .reset)
        #expect(display(resetAgo: 1_801).freshness == .resetUnverified)
        #expect(display(resetAgo: 1_800).captionText == "초기화됨")
        #expect(display(resetAgo: 1_801).captionText == "초기화됨 · 확인 못 함")
    }

    // MARK: ⑤ 건전성 — 모순은 숫자를 지어내지 않고 '모른다'로 떨어진다

    /// 리셋 시각이 관측 시각보다 **과거**다 → 모순. 관측 전에 리셋이 있었다면 그 값은 이미 리셋 뒤 값이어야 한다.
    @Test func resetBeforeObservationIsUnknown() {
        let snapshot = aiSnapshot(used: 30, observedAgo: 60, resetsAt: aiNow.addingTimeInterval(-120))
        let display = AILimitFreshnessRule.display(snapshot, now: aiNow)
        #expect(display.freshness == .unknown)
        #expect(display.valueText == "—")
        #expect(display.captionText == "알 수 없음")
        #expect(display.percent == nil)       // 바를 0 으로 그리면 "안 썼다"는 거짓이 된다
        #expect(display.isVisible)            // 자리는 있다 — 거짓 대신 '모름'을 그린다
    }

    /// 5시간 칸에 **창 길이보다 먼** 리셋이 들어왔다 → 그 창 종류의 리셋이 아니다.
    @Test func resetFartherThanWindowLengthIsUnknown() {
        let observed = aiNow.addingTimeInterval(-60)
        let snapshot = AILimitWindowSnapshot(
            window: .fiveHour,
            usedPercent: 30,
            resetsAt: observed.addingTimeInterval(AILimitWindow.fiveHour.lengthSeconds + 601),
            observedAt: observed,
            source: .local
        )
        #expect(AILimitFreshnessRule.display(snapshot, now: aiNow).freshness == .unknown)
    }

    /// 허용오차(600초) 안이면 멀쩡한 행이다 — 제공자가 경계를 몇 분 미루는 날 거짓 `unknown` 을 내지 않는다.
    @Test func resetWithinSameWindowToleranceStaysKnown() {
        let observed = aiNow.addingTimeInterval(-60)
        let snapshot = AILimitWindowSnapshot(
            window: .fiveHour,
            usedPercent: 30,
            resetsAt: observed.addingTimeInterval(AILimitWindow.fiveHour.lengthSeconds + 300),
            observedAt: observed,
            source: .local
        )
        let display = AILimitFreshnessRule.display(snapshot, now: aiNow)
        #expect(display.freshness == .fresh)
        #expect(display.valueText == "30%")
    }

    /// 스냅샷이 아예 없다 → 안 보임 + '모름'. 미연동 제공자가 0% 로 그려지는 일을 막는다.
    @Test func missingSnapshotIsHiddenUnknown() {
        let display = AILimitFreshnessRule.display(nil, now: aiNow)
        #expect(display.freshness == .unknown)
        #expect(display.isVisible == false)
        #expect(display.valueText == "—")
        #expect(display.percent == nil)
    }

    // MARK: ⑥ 시계·범위

    /// 관측 시각이 미래(기기 시계가 뒤로 갔다) → 음수 나이를 0 으로 보고 '방금'. 미래를 "−1분 전"으로 적지 않는다.
    @Test func futureObservationReadsAsJustNow() {
        let snapshot = AILimitWindowSnapshot(
            window: .fiveHour,
            usedPercent: 27,
            resetsAt: aiNow.addingTimeInterval(3 * aiHour),
            observedAt: aiNow.addingTimeInterval(30),
            source: .local
        )
        let display = AILimitFreshnessRule.display(snapshot, now: aiNow)
        #expect(display.freshness == .fresh)
        #expect(display.captionText == "방금")
        #expect(display.valueText == "27%")
    }

    /// 리셋 시각을 모르면(nil) 하한만 유지한다 — 지나갔다고도 안 지났다고도 말하지 않는다.
    @Test func missingResetKeepsFloor() {
        let display = AILimitFreshnessRule.display(aiSnapshot(used: 42, observedAgo: 2 * aiHour), now: aiNow)
        #expect(display.freshness == .stale)
        #expect(display.valueText == "42% 이상")
        #expect(display.resetsAt == nil)
    }

    /// 제공자가 101 을 주는 날 → 100 으로 접는다(바가 화면을 뚫지 않게).
    @Test func overHundredPercentClamps() {
        let display = AILimitFreshnessRule.display(aiSnapshot(used: 101, observedAgo: 10), now: aiNow)
        #expect(display.percent == 100)
        #expect(display.valueText == "100%")
    }

    /// 두 끝의 거짓을 막는다: 0 보다 크면 `0%` 로, 100 보다 작으면 `100%` 로 적지 않는다.
    @Test func wholePercentNeverLiesAtTheEnds() {
        #expect(AILimitFreshnessRule.wholePercent(0.4) == 1)
        #expect(AILimitFreshnessRule.wholePercent(99.6) == 99)
        #expect(AILimitFreshnessRule.wholePercent(0) == 0)
        #expect(AILimitFreshnessRule.wholePercent(100) == 100)
        #expect(AILimitFreshnessRule.wholePercent(-5) == 0)
    }

    // MARK: ⑦ 나이 문구는 한 곳에서 온다

    /// 캡션은 `FeedbackText.ageText` 를 **그대로** 쓴다. 네 벌째 사본을 만들면 화면마다 '방금'의 경계가 갈린다.
    @Test func captionDelegatesToSharedAgeText() {
        for ago in [0, 59, 61, 29 * 60, 31 * 60, 3 * 3_600, 3 * 86_400] as [TimeInterval] {
            let snapshot = aiSnapshot(observedAgo: ago)
            let display = AILimitFreshnessRule.display(snapshot, now: aiNow)
            #expect(display.captionText == FeedbackText.ageText(snapshot.observedAt, now: aiNow))
        }
    }

    /// **출처는 화면 문구에 쓰지 않는다**(2026-09-22 사용자 결정과 같은 규약). 모델엔 남지만 캡션은 나이만 말한다.
    @Test func captionNeverMentionsSource() {
        for source in [AILimitSource.local, .server] {
            for ago in [10, 31 * 60, 3 * 86_400] as [TimeInterval] {
                let display = AILimitFreshnessRule.display(aiSnapshot(observedAgo: ago, source: source), now: aiNow)
                #expect(display.source == source)
                for word in ["서버", "맥", "로컬", "직접"] {
                    #expect(display.captionText.contains(word) == false, "캡션이 출처를 말한다: \(display.captionText)")
                }
            }
        }
    }

    // MARK: ⑧ 조합 — 숫자 하나만 보이는 자리

    /// 하한은 **max**, 캡션은 **가장 낡은** 기여자 것. 평균을 내면 99% 인 제공자를 "50%" 라고 말한다.
    @Test func combineTakesMaxFloorAndWorstCaption() {
        let fresh = AILimitFreshnessRule.display(aiSnapshot(used: 20, observedAgo: 10), now: aiNow)
        let old = AILimitFreshnessRule.display(aiSnapshot(used: 55, observedAgo: 2 * aiHour), now: aiNow)
        let combined = AILimitFreshnessRule.combine([fresh, old])
        #expect(combined.percent == 55)
        #expect(combined.captionText == "2시간 전")
        #expect(combined.valueText == "55% 이상")
        #expect(combined.floorOnly)
        #expect(combined.isVisible)
    }

    /// 가장 많이 쓴 쪽이 **신선해도** 캡션은 낡은 쪽이 정하고, "이상"은 기여자 중 하나라도 하한이면 붙는다 —
    /// 그래야 숫자와 캡션이 같은 이야기를 한다.
    @Test func combineMarksFloorWhenAnyContributorIsFloor() {
        let freshHigh = AILimitFreshnessRule.display(aiSnapshot(used: 80, observedAgo: 5), now: aiNow)
        let oldLow = AILimitFreshnessRule.display(aiSnapshot(used: 10, observedAgo: 3 * aiDay), now: aiNow)
        let combined = AILimitFreshnessRule.combine([freshHigh, oldLow])
        #expect(combined.percent == 80)
        #expect(combined.valueText == "80% 이상")
        #expect(combined.captionText == "3일 전")
    }

    /// `unknown` 기여자는 하한을 올리지도 내리지도 않는다 — '모른다'는 0 이 아니다.
    @Test func combineIgnoresUnknownContributors() {
        let unknown = AILimitFreshnessRule.display(nil, now: aiNow)
        let known = AILimitFreshnessRule.display(aiSnapshot(used: 30, observedAgo: 5), now: aiNow)
        let combined = AILimitFreshnessRule.combine([unknown, known])
        #expect(combined.percent == 30)
        #expect(combined.valueText == "30%")
        #expect(combined.captionText == "방금")
    }

    /// 전부 모르면 모른다. 빈 목록도 마찬가지고, 그때는 자리도 만들지 않는다.
    @Test func combineOfNothingIsUnknown() {
        let allUnknown = AILimitFreshnessRule.combine([
            AILimitFreshnessRule.display(nil, now: aiNow),
            AILimitFreshnessRule.display(nil, now: aiNow)
        ])
        #expect(allUnknown.freshness == .unknown)
        #expect(allUnknown.valueText == "—")
        #expect(allUnknown.isVisible == false)

        let empty = AILimitFreshnessRule.combine([])
        #expect(empty.freshness == .unknown)
        #expect(empty.isVisible == false)
    }

    /// 기여자가 섞이면 꼬리표(제공자·창)를 **대표로 훔치지 않는다**. 같으면 유지한다.
    @Test func combineKeepsTagsOnlyWhenTheyAgree() {
        let claudeFive = AILimitFreshnessRule
            .display(aiSnapshot(used: 10, observedAgo: 5), now: aiNow)
        let claudeWeekly = AILimitFreshnessRule
            .display(aiSnapshot(window: .weekly, used: 20, observedAgo: 5), now: aiNow)
        #expect(AILimitFreshnessRule.combine([claudeFive, claudeWeekly]).window == nil)
        #expect(AILimitFreshnessRule.combine([claudeFive, claudeFive]).window == .fiveHour)
    }

    // MARK: ⑨ 단위 — 안티그래비티만 부호가 반대다

    /// `remaining_fraction` 1.0 = 하나도 안 씀 → 0%. 0.28 → 72%. 여기서 틀리면 0% 와 100% 가 통째로 뒤집힌다.
    @Test func antigravityRemainingFlipsToUsed() {
        #expect(AILimitScale.usedPercent(remainingFraction: 1.0) == 0)
        #expect(abs(AILimitScale.usedPercent(remainingFraction: 0.28) - 72) < 1e-9)
        #expect(AILimitScale.usedPercent(remainingFraction: 0) == 100)
        // 범위를 벗어난 입력은 접는다 — 바가 뒤로 자라거나 화면을 뚫지 않게.
        #expect(AILimitScale.usedPercent(remainingFraction: 1.2) == 0)
        #expect(AILimitScale.usedPercent(remainingFraction: -0.1) == 100)
    }

    /// 뒤집기는 **전용 init** 하나에서만 일어난다. 파서가 손으로 `1 -` 를 쓰면 그게 결함이다.
    @Test func antigravityInitProducesUsedPercent() {
        let full = AILimitWindowSnapshot(
            window: .fiveHour, remainingFraction: 1.0, resetsAt: nil, observedAt: aiNow, source: .local
        )
        let mostlyUsed = AILimitWindowSnapshot(
            window: .weekly, remainingFraction: 0.28, resetsAt: nil, observedAt: aiNow, source: .local
        )
        #expect(full.usedPercent == 0)
        #expect(abs(mostlyUsed.usedPercent - 72) < 1e-9)
        #expect(AILimitFreshnessRule.display(full, now: aiNow).valueText == "0%")
        #expect(AILimitFreshnessRule.display(mostlyUsed, now: aiNow).valueText == "72%")
    }

    /// 그룹이 둘인 안티그래비티는 **더 많이 쓴 쪽**이 대표다 — 적게 쓴 쪽을 세우면 "여유 있다"고 말한 뒤 벽을 맞는다.
    @Test func worstPerWindowKeepsTheHeavierGroup() {
        let geminiFive = aiSnapshot(used: 30)
        let thirdPartyFive = aiSnapshot(used: 70)
        let geminiWeekly = aiSnapshot(window: .weekly, used: 12)
        let kept = AILimitWindowSnapshot.worstPerWindow([geminiFive, thirdPartyFive, geminiWeekly])
        #expect(kept.count == 2)
        #expect(kept.first?.window == .fiveHour)       // 5시간이 먼저
        #expect(kept.first?.usedPercent == 70)
        #expect(kept.last?.usedPercent == 12)
    }

    // MARK: ⑩ 모델 — 어휘·숨김·지문

    /// 세 제공자가 같은 것을 세 어휘로 부른다. 표는 한 곳이고, **모르는 값은 nil 이다**(지어내지 않는다).
    @Test func providerWindowNamesMapToOneVocabulary() {
        #expect(AILimitWindow(providerWindowName: "five_hour") == .fiveHour)
        #expect(AILimitWindow(providerWindowName: "primary_window") == .fiveHour)
        #expect(AILimitWindow(providerWindowName: "5h") == .fiveHour)
        #expect(AILimitWindow(providerWindowName: "seven_day") == .weekly)
        #expect(AILimitWindow(providerWindowName: "secondary_window") == .weekly)
        #expect(AILimitWindow(providerWindowName: "weekly") == .weekly)
        // Claude 의 셋째 창은 두 칸에 밀어 넣지 않는다 — 넣으면 한 창이 다른 창을 덮어쓴다.
        #expect(AILimitWindow(providerWindowName: "seven_day_sonnet") == nil)
        #expect(AILimitWindow(providerWindowName: "") == nil)
    }

    /// 창 길이는 건전성 검사의 눈금이다. 상수를 흘리면 검사가 조용히 무력해진다.
    @Test func windowLengthsAreTheRealOnes() {
        #expect(AILimitWindow.fiveHour.lengthSeconds == 18_000)
        #expect(AILimitWindow.weekly.lengthSeconds == 604_800)
    }

    /// 미연동 제공자는 **목록에서 사라진다**. 창을 지어내 0% 로 채우지 않는다(Starter 는 weekly 만 온다).
    @Test func unlinkedProvidersAreHidden() {
        let bundle = AILimitSnapshotBundle(providers: [
            AILimitProviderSnapshot(provider: .antigravity, windows: []),
            AILimitProviderSnapshot(provider: .codex, windows: [aiSnapshot()]),
            AILimitProviderSnapshot(provider: .claude, windows: [aiSnapshot(window: .weekly)])
        ])
        #expect(bundle.visibleProviders.map(\.provider) == [.claude, .codex])
        #expect(bundle.provider(.antigravity)?.isLinked == false)
    }

    /// 카드는 5시간 → 주간 순서로 줄을 만들고, **없는 창은 줄을 만들지 않는다**.
    @Test func providerDisplaysAreOrderedAndSparse() {
        let snapshot = AILimitProviderSnapshot(
            provider: .codex,
            windows: [aiSnapshot(window: .weekly, used: 56), aiSnapshot(used: 0)],
            planLabel: "plus"
        )
        let rows = AILimitFreshnessRule.displays(provider: snapshot, now: aiNow)
        #expect(rows.map(\.window) == [.fiveHour, .weekly])
        #expect(rows.allSatisfy { $0.provider == .codex })

        let weeklyOnly = AILimitProviderSnapshot(provider: .antigravity, windows: [aiSnapshot(window: .weekly)])
        #expect(AILimitFreshnessRule.displays(provider: weeklyOnly, now: aiNow).count == 1)
        // 없는 창을 물으면 '안 보임'이다 — 0% 로 그리지 않는다.
        let missing = AILimitFreshnessRule.display(provider: weeklyOnly, window: .fiveHour, now: aiNow)
        #expect(missing.isVisible == false)
        #expect(missing.provider == .antigravity)
    }

    /// 상대 초는 받는 자리에서 **절대 시각**으로 굳힌다. 상대값을 저장하면 위젯이 "4시간 남음"을 영원히 말한다.
    @Test func resetAfterSecondsBecomesAbsoluteDate() {
        let snapshot = AILimitWindowSnapshot(
            window: .fiveHour, usedPercent: 12, resetsAfterSeconds: 4 * aiHour, observedAt: aiNow, source: .local
        )
        #expect(snapshot.resetsAt == aiNow.addingTimeInterval(4 * aiHour))
        // 이미 지난 상대값은 리셋 시각이 아니라 관측 실패다.
        let bogus = AILimitWindowSnapshot(
            window: .fiveHour, usedPercent: 12, resetsAfterSeconds: -5, observedAt: aiNow, source: .local
        )
        #expect(bogus.resetsAt == nil)
    }

    /// 계정 지문은 **해시만**이고 길이가 고정이다. 원문(이메일·account_id)은 모델에 담을 자리가 없다.
    @Test func fingerprintIsHashOnly() {
        let one = AILimitFingerprint.make("someone@example.test")
        let same = AILimitFingerprint.make("someone@example.test")
        let other = AILimitFingerprint.make("other@example.test")
        #expect(one?.count == AILimitFingerprint.hexLength)
        #expect(one == same)
        #expect(one != other)
        #expect(one?.contains("@") == false)
        // "없음"을 해시로 만들면 모든 미연동 계정이 **같은 지문**을 갖는다.
        #expect(AILimitFingerprint.make("") == nil)
        #expect(AILimitFingerprint.make("   ") == nil)
        #expect(AILimitFingerprint.make(nil) == nil)
    }

    /// 봉투가 그대로 왕복한다(App Group 파일·서버 응답이 이 모양이다).
    @Test func bundleRoundTripsThroughCodable() throws {
        let bundle = AILimitSnapshotBundle(providers: [
            AILimitProviderSnapshot(
                provider: .claude,
                windows: [
                    aiSnapshot(used: 26, resetsAt: aiNow.addingTimeInterval(2 * aiHour)),
                    aiSnapshot(window: .weekly, used: 60, resetsAt: aiNow.addingTimeInterval(5 * aiDay))
                ],
                planLabel: "max20",
                accountFingerprint: AILimitFingerprint.make("someone@example.test")
            )
        ])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(AILimitSnapshotBundle.self, from: encoder.encode(bundle))
        #expect(decoded == bundle)
        #expect(decoded.schemaVersion == AILimitSnapshotBundle.currentSchemaVersion)
    }

    // MARK: ⑪ 로고 — 진짜 벡터가 들어 있는가

    /// 세 로고 모두 패스가 비어 있지 않고, `rect` 안에 비율을 지켜 중앙 정렬된다.
    /// (좌표가 원본 SVG 와 픽셀 동일인지는 전사 단계에서 래스터 비교로 확인했다 — 여기서는 스케일 계약만 못 박는다.)
    @Test func providerMarksScaleAndCenterInsideRect() {
        for provider in AILimitProvider.allCases {
            let square = AIProviderLogoPath.path(for: provider, in: CGRect(x: 0, y: 0, width: 100, height: 100))
            #expect(square.isEmpty == false, "\(provider) 패스가 비었다")
            #expect(square.boundingRect.minX >= -0.01 && square.boundingRect.maxX <= 100.01)
            #expect(square.boundingRect.minY >= -0.01 && square.boundingRect.maxY <= 100.01)

            // 가로로 긴 rect: 짧은 변에 맞추고 가로 중앙에 둔다(찌그러지지 않는다).
            let wide = AIProviderLogoPath.path(for: provider, in: CGRect(x: 0, y: 0, width: 200, height: 100))
            let bounds = wide.boundingRect
            #expect(abs((bounds.midX - 100)) < 1.0, "\(provider) 가 가로 중앙에 없다")
            #expect(bounds.width <= 100.01)

            // 빈 rect 는 빈 패스다 — 0 으로 나눈 NaN 이 섞이면 그 프레임이 통째로 안 그려진다.
            #expect(AIProviderLogoPath.path(for: provider, in: .zero).isEmpty)
        }
    }

    /// 제공자는 **색으로만** 구분되지 않는다 — 위젯 틴트 모드가 색을 버린다. 이름 글자가 셋 다 서로 달라야 한다.
    @Test func providerNamesAreDistinctAndNonEmpty() {
        let names = AILimitProvider.allCases.map(\.compactName)
        #expect(Set(names).count == AILimitProvider.allCases.count)
        #expect(names.allSatisfy { !$0.isEmpty })
        #expect(Set(AILimitProvider.allCases.map(\.displayName)).count == 3)
        // 카드 순서는 자격증명 유무와 무관하게 고정이다.
        #expect(AILimitProvider.allCases.sorted { $0.sortOrder < $1.sortOrder } == [.claude, .codex, .antigravity])
    }
}
