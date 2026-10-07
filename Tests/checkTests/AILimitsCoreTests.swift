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

/// 리셋을 **주장하는** 기여자 하나. `resetAgo` 가 유예(120초)를 넘겨야 주장이 선다.
/// 창이 5시간이면 `observedAgo - resetAgo` 가 창 길이 + 허용오차 안에 있어야 건전성 검사를 통과한다.
private func aiResetClaimDisplay(
    window: AILimitWindow = .fiveHour,
    used: Double = 40,
    observedAgo: TimeInterval = 2 * aiHour,
    resetAgo: TimeInterval = 90 * 60
) -> AILimitDisplay {
    AILimitFreshnessRule.display(
        aiSnapshot(window: window, used: used, observedAgo: observedAgo,
                   resetsAt: aiNow.addingTimeInterval(-resetAgo)),
        now: aiNow
    )
}

/// 리셋을 주장하지 **않는** 기여자 하나(리셋 시각을 모른다 → 하한만 유지).
private func aiPlainDisplay(
    window: AILimitWindow = .fiveHour,
    used: Double,
    observedAgo: TimeInterval
) -> AILimitDisplay {
    AILimitFreshnessRule.display(aiSnapshot(window: window, used: used, observedAgo: observedAgo), now: aiNow)
}

/// ★ **숫자와 글자는 절대 모순되지 않는다** — 이 구조체가 지켜야 하는 일반 불변식.
///
/// 2026-10-07 검증: 옛 `combine` 이 `percent 90` 과 `valueText "0%"` 를 같은 구조체에 담아 내보냈다.
/// 소비자 하나는 바를 90% 길이로 그리고 다른 둘은 글자를 `0%` 로 그린다 — 같은 화면이 두 사실을 말한다.
/// 그래서 **값을 쓰는 모든 테스트가 이 함수를 통과**하게 두고, 모순이 생길 수 있는 경로를 전부 여기서 막는다.
private func aiExpectValueMatchesPercent(_ display: AILimitDisplay, _ label: String) {
    guard let percent = display.percent else {
        // 숫자가 없으면 글자도 '모름'이어야 한다 — `0%` 는 "안 썼다"는 거짓이다.
        #expect(display.valueText == AILimitFreshnessRule.unknownValueText,
                "\(label): 숫자가 없는데 글자가 '\(display.valueText)' 다")
        #expect(display.freshness == .unknown, "\(label): 숫자가 없는데 등급이 \(display.freshness) 다")
        #expect(display.floorOnly == false, "\(label): 숫자가 없는데 하한 깃발이 서 있다")
        return
    }
    let whole = AILimitFreshnessRule.wholePercent(percent)
    #expect(display.valueText == (display.floorOnly ? "\(whole)% 이상" : "\(whole)%"),
            "\(label): percent \(percent)(→ \(whole)%) 인데 글자가 '\(display.valueText)' 다 — 바와 숫자가 다른 사실을 말한다")
    // ★ `0% 이상` 은 **아무 말도 아니다**(모든 값이 0 이상이다). 어느 경로로도 그 글자가 나오지 않는다 —
    //   하한 깃발까지 함께 내려가야 바가 하한 색인데 글자는 등호인 조합도 안 생긴다(v0.3.45 P2).
    #expect(display.valueText != "0% 이상", "\(label): 아무 말도 아닌 글자가 화면에 나간다")
    #expect(!(whole == 0 && display.floorOnly),
            "\(label): 숫자가 0% 인데 하한 깃발이 서 있다 — 글자는 '0%' 인데 바가 하한 색으로 흐려진다")
    if display.freshness.isResetClaim {
        // 리셋을 확신하면 숫자도 0 이어야 한다. "0% 이상"은 아무 말도 아니므로 하한 깃발도 내려간다.
        #expect(percent == 0, "\(label): 리셋을 주장하면서 숫자가 \(percent) 다")
        #expect(display.valueText == "0%", "\(label): 리셋 주장의 글자가 '\(display.valueText)' 다")
        #expect(display.floorOnly == false, "\(label): 리셋 주장에 하한 깃발이 섰다")
    }
}

/// `agy -p /usage` 봉투(실측 모양) — 한 그룹에 5시간·주간 버킷 하나씩.
/// `reset_time` 을 **호출부가 정하는** 것이 이 픽스처의 전부다(투영 지문을 1초 단위로 재야 한다).
private func aiAntigravityCLIJSON(
    fiveHourRemaining: Double,
    fiveHourReset: Date,
    weeklyRemaining: Double,
    weeklyReset: Date
) -> String {
    """
    {"status":"SUCCESS","command":{"name":"usage","data":{"groups":[
      {"name":"Gemini Models","buckets":[
        {"id":"gemini-5h","window":"5h","remaining_fraction":\(fiveHourRemaining),
         "reset_time":"\(aiISO8601(fiveHourReset))"},
        {"id":"gemini-weekly","window":"weekly","remaining_fraction":\(weeklyRemaining),
         "reset_time":"\(aiISO8601(weeklyReset))"}]}]}}}
    """
}

/// 초 단위 ISO8601(실측 `reset_time` 과 같은 해상도).
private func aiISO8601(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter.string(from: date)
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
    /// 그래서 기대값은 "초기화됨"이 **아니다**. 마지막으로 본 0% 를 하한으로 두고 나이만 말한다 —
    /// 정보는 **캡션**이 나른다(거짓 자신감보다 싸다). 글자는 `0%` 다: `0% 이상` 은 아무 말도 아니다(P2).
    @Test func zeroPercentRowNeverClaimsReset() {
        let snapshot = aiSnapshot(used: 0, observedAgo: 3 * aiHour, resetsAt: aiNow.addingTimeInterval(-aiHour))
        let display = AILimitFreshnessRule.display(snapshot, now: aiNow)
        #expect(display.freshness == .stale)
        #expect(display.captionText == "3시간 전")
        #expect(display.captionText != "초기화됨")
        #expect(display.percent == 0)
        #expect(display.valueText == "0%", "낡은 0% 의 글자가 '\(display.valueText)' 다")
        #expect(display.floorOnly == false, "0% 에 하한 깃발이 섰다 — 바가 하한 색인데 글자는 등호다")
        aiExpectValueMatchesPercent(display, "낡은 0% (함정 ①)")
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

    // MARK: ⑫ 조합 — 리셋 주장이 섞여도 자기모순을 내보내지 않는다 (P0)
    //
    // 2026-10-07 검증자 **둘이 독립적으로** 재현한 결함: `combine` 이 숫자는 하한의 max 로, 글자는 *캡션을
    // 정한 다른 기여자*의 리셋 여부로 따로 만들어 `percent 90` 과 `valueText "0%"` 를 **같은 구조체에** 담았다.
    // 소비자 둘이 글자를 그리고(맥 팝오버 한 줄 · 폰 '나' 탭 요약 칩) 하나가 바를 그린다 — 한 화면이 두 사실을
    // 말한다. 아래 다섯 조합이 그 모양을 각각 다른 각도에서 막고, 마지막 하나가 **일반 불변식**으로 못 박는다.

    /// ★ 재현된 바로 그 상태: Claude 5시간 90%(5분 전 관측) + Codex 5시간 40%(2시간 전 관측 · 리셋 90분 전 지남).
    /// Codex 리더가 실패해도 `AILimitStore.apply` 가 옛 스냅샷을 남기므로 이건 **설계된 정상 상태**다.
    /// 하한 90 이 살아 있으면 글자도 90 계열이어야 한다 — 남의 리셋이 내 90% 를 0% 로 보이게 하지 않는다.
    @Test func combineKeepsTheLivingFloorWhenAnotherContributorReset() {
        let claude = aiPlainDisplay(used: 90, observedAgo: 5 * 60)
        let codex = aiResetClaimDisplay(used: 40, observedAgo: 2 * aiHour, resetAgo: 90 * 60)
        // 전제부터 못 박는다 — 기여자가 이 모습이 아니면 아래 단언은 다른 것을 재고 있다.
        #expect(claude.percent == 90 && claude.freshness == .recent)
        #expect(codex.freshness == .resetUnverified && codex.percent == 0)
        #expect(codex.claimAge! > claude.claimAge!, "전제: 리셋 기여자가 claimAge 로는 가장 '낡다'")

        let combined = AILimitFreshnessRule.combine([claude, codex])
        #expect(combined.percent == 90)
        #expect(combined.valueText == "90%", "하한 90 이 살아 있는데 글자가 '\(combined.valueText)' 다")
        #expect(combined.captionText == "5분 전")
        #expect(combined.freshness.isResetClaim == false)
        aiExpectValueMatchesPercent(combined, "리셋 기여자가 섞인 조합")
    }

    /// 리셋 주장**만** 남았을 때 — 그때만 숫자가 0 이다. 캡션은 그중 가장 낡은 쪽(여기선 15분 전 경계).
    @Test func combineOfOnlyResetClaimsSaysZero() {
        let fiveHour = aiResetClaimDisplay(used: 40, observedAgo: 3 * aiHour, resetAgo: 300)
        let weekly = aiResetClaimDisplay(window: .weekly, used: 70, observedAgo: 4 * aiHour, resetAgo: 900)
        #expect(fiveHour.freshness == .reset && weekly.freshness == .reset)

        let combined = AILimitFreshnessRule.combine([fiveHour, weekly])
        #expect(combined.freshness == .reset)
        #expect(combined.percent == 0)
        #expect(combined.valueText == "0%")
        #expect(combined.captionText == "초기화됨")
        #expect(combined.floorOnly == false)
        aiExpectValueMatchesPercent(combined, "전부 리셋 주장")
    }

    /// 리셋 주장 기여자가 **claimAge 로 가장 커도** 캡션을 가져가지 않는다.
    ///
    /// 축이 다르기 때문이다: 리셋 주장의 나이는 `now − resetsAt`(경계가 언제였나)이고 나머지는
    /// `now − observedAt`(언제 봤나)이다. 한 `max` 로 견주면 "경계가 오래전이다"가 "관측이 오래됐다"를 이긴다 —
    /// 뜻이 다른 두 수를 크기로만 비교한 것이다.
    @Test func combineCaptionComesFromTheSameAgeAxisAsTheNumber() {
        let plain = aiPlainDisplay(used: 55, observedAgo: 40 * 60)
        let claimed = aiResetClaimDisplay(window: .weekly, used: 80, observedAgo: 20 * aiHour, resetAgo: 10 * aiHour)
        #expect(claimed.claimAge == 10 * aiHour, "리셋 주장의 나이는 관측(20시간)이 아니라 경계(10시간)로 잰다")
        #expect(claimed.claimAge! > plain.claimAge!, "전제: 옛 비교에서는 이쪽이 캡션을 가져갔다")

        let combined = AILimitFreshnessRule.combine([plain, claimed])
        #expect(combined.valueText == "55% 이상")
        #expect(combined.captionText == "40분 전")
        #expect(combined.freshness == .stale)
        aiExpectValueMatchesPercent(combined, "축이 다른 두 나이")
    }

    /// 0% 를 **하한으로** 들고 있는 행(함정 ①: Codex 0% 는 리셋을 주장하지 않는다)이 남의 리셋 주장 때문에
    /// "초기화됨"으로 바뀌지 않는다. 옛 `combine` 은 캡션을 남의 행에서 가져와 **없던 사건을 단정**했다 —
    /// 그 거짓 자신감은 숫자가 틀린 것보다 비싸다(머리말 함정 ①).
    @Test func combineNeverBorrowsAResetEventForANonClaimingRow() {
        let zeroStale = aiPlainDisplay(used: 0, observedAgo: 3 * aiHour)
        let claimed = aiResetClaimDisplay(window: .weekly, used: 60, observedAgo: 2 * aiDay, resetAgo: aiDay)
        // 글자는 둘 다 `0%` 다(`0% 이상` 은 아무 말도 아니다 — P2). 그래서 "하한 0%" 와 "확신한 0%" 를
        // 가르는 신호는 **캡션과 등급**이다: `3시간 전`/`.stale` 인가 `초기화됨`/`.reset` 인가.
        #expect(zeroStale.freshness == .stale && zeroStale.valueText == "0%")
        #expect(claimed.freshness == .resetUnverified)

        let combined = AILimitFreshnessRule.combine([zeroStale, claimed])
        #expect(combined.captionText == "3시간 전")
        #expect(combined.captionText != "초기화됨", "리셋을 주장하지 않는 행에 없던 사건을 붙였다")
        #expect(combined.valueText == "0%")
        #expect(combined.percent == 0)
        #expect(combined.freshness == .stale, "하한 0% 가 '확신한 0%'(.reset) 로 바뀌었다 — 그 차이는 캡션·등급이 나른다")
        #expect(combined.floorOnly == false, "0% 에 하한 깃발이 섰다 — 글자는 '0%' 인데 바가 흐려진다")
        aiExpectValueMatchesPercent(combined, "0% 하한 + 남의 리셋")
    }

    /// 셋이 섞인 경우: 숫자는 **살아 있는** 하한의 max, "이상"은 그중 하나라도 하한이면, 캡션은 그중 가장 낡은 쪽.
    @Test func combineWithThreeContributorsPicksTheLivingWorst() {
        let freshHigh = aiPlainDisplay(used: 90, observedAgo: 10)
        let ancientLow = aiPlainDisplay(window: .weekly, used: 12, observedAgo: 3 * aiDay)
        let claimed = aiResetClaimDisplay(window: .weekly, used: 99, observedAgo: 5 * aiDay, resetAgo: 4 * aiDay)
        #expect(claimed.freshness == .resetUnverified && claimed.claimAge == 4 * aiDay)

        let combined = AILimitFreshnessRule.combine([claimed, ancientLow, freshHigh])
        #expect(combined.percent == 90)
        #expect(combined.valueText == "90% 이상")
        #expect(combined.captionText == "3일 전")
        #expect(combined.freshness == .ancient)
        aiExpectValueMatchesPercent(combined, "셋 섞임")
    }

    /// 숫자·글자·하한 깃발의 **입구 자체**를 잰다 — 도달 가능한 상태만 재면 이 결함이 다시 산다.
    ///
    /// 왜 입구를 따로 재는가(2026-10-07 뮤테이션 실증): 지금 `display`·`combine` 은 리셋 주장일 때 `percent` 를
    /// 이미 0 으로 넘기므로, "글자만 0% 로 덮기" 변형이 **살아남는다**(관측상 같은 답). 그런데 P0 결함이 생긴
    /// 경로가 바로 그것이었다 — 호출부 하나가 0 이 아닌 하한을 들고 들어온 것이다. 그래서 입구에서 못 박는다.
    @Test func valuePairNeverLetsTheNumberAndTheTextDiverge() {
        // 리셋을 주장하면 **숫자까지** 0 이다. 글자만 덮으면 바는 90% 길이로 남는다(그 결함의 모양).
        let claimed = AILimitFreshnessRule.value(percent: 90, floorOnly: true, isResetClaim: true)
        #expect(claimed.percent == 0, "리셋 주장에 숫자가 \(claimed.percent) 로 남았다 — 바가 그 길이로 그려진다")
        #expect(claimed.text == "0%")
        #expect(claimed.floorOnly == false, "'0% 이상'은 아무 말도 아니다")

        // 하한·등호·클램프 세 갈래 모두 글자의 수가 `percent` 를 반올림한 수와 같다.
        // ★ 0 에서는 하한 깃발이 **안 선다**(`0% 이상` 은 아무 말도 아니다 — 아래 전용 테스트가 그 자리를 잰다).
        for percent in [0, 0.4, 27, 90, 99.6, 101, -5] as [Double] {
            for floorOnly in [false, true] {
                let value = AILimitFreshnessRule.value(percent: percent, floorOnly: floorOnly, isResetClaim: false)
                let whole = AILimitFreshnessRule.wholePercent(value.percent)
                let expectedFloor = floorOnly && whole > 0
                #expect(value.text == (expectedFloor ? "\(whole)% 이상" : "\(whole)%"),
                        "percent \(percent) → 숫자 \(value.percent) · 글자 '\(value.text)' 가 어긋났다")
                #expect(value.floorOnly == expectedFloor)
                #expect(value.percent >= 0 && value.percent <= 100)
            }
        }
        // NaN 은 한 자리에서 접는다 — 한쪽만 접으면 바는 안 그려지는데 글자는 `0%` 다.
        let nan = AILimitFreshnessRule.value(percent: .nan, floorOnly: false, isResetClaim: false)
        #expect(nan.percent == 0 && nan.text == "0%")
        #expect(AILimitFreshnessRule.clampedPercent(.nan) == 0)
        #expect(AILimitFreshnessRule.clampedPercent(.infinity) == 0)
        #expect(AILimitFreshnessRule.clampedPercent(42) == 42)
    }

    /// ★★ **`0% 이상` 은 어느 경로로도 안 나온다.** (v0.3.45 P2)
    ///
    /// ## 왜 이게 결함이었나
    /// 하한 깃발을 내리는 자리가 **리셋 주장 하나**뿐이어서, 0% 가 **낡아서** 하한이 된 경우는 그 글자가
    /// 그대로 나갔다 — `value(0, floorOnly: true, isResetClaim: false) → "0% 이상"`. 모든 값이 0 이상이므로
    /// 그 글자는 아무 말도 아니다. 그리고 드문 조합도 아니었다: Codex 5시간 창은 실측에서 0% 가 흔하고
    /// (함정 ①: 그 행은 리셋도 주장하지 않는다) 맥이 **30분만** 자도 `.stale` 이 된다 → 맥 팝오버·폰 카드·위젯
    /// 세 화면에 평상시로 보였다.
    ///
    /// ## 어디를 재는가
    /// 입구(`value`) · 창 하나(`display`) · 조합(`combine`) **세 경로 전부**다. 한 곳만 재면 다른 호출부가
    /// 0 이 아닌 하한을 들고 들어오는 변형이 살아남는다(그게 P0 가 생긴 모양이다).
    /// 그리고 **0.4% 의 하한은 그대로 살아 있어야 한다**(`1% 이상`) — "0 이면 깃발을 내린다"를
    /// "하한이면 언제나 깃발을 내린다"로 넓히는 변형은 그 단언에서 죽는다.
    @Test func zeroPercentNeverGetsTheFloorSuffix() {
        // ① 입구. 0 과 음수(클램프되어 0) 양쪽에서.
        for percent in [0, -5, Double.nan] as [Double] {
            let value = AILimitFreshnessRule.value(percent: percent, floorOnly: true, isResetClaim: false)
            #expect(value.text == "0%", "percent \(percent) 의 글자가 '\(value.text)' 다 — 아무 말도 아닌 글자다")
            #expect(value.floorOnly == false, "percent \(percent) 에 하한 깃발이 섰다")
            #expect(value.percent == 0)
        }
        // ★ 기준선이 갈려야 이 테스트가 뜻을 갖는다: **0 이 아닌** 하한은 "이상"을 그대로 받는다.
        let tiny = AILimitFreshnessRule.value(percent: 0.4, floorOnly: true, isResetClaim: false)
        #expect(tiny.text == "1% 이상" && tiny.floorOnly, "0 이 아닌 하한까지 깃발을 내렸다 — 정보를 버렸다")
        let plain = AILimitFreshnessRule.value(percent: 0, floorOnly: false, isResetClaim: false)
        #expect(plain.text == "0%" && plain.floorOnly == false)

        // ② 창 하나. 리셋 시각을 모르는 0% 행(= Codex 5시간 창의 실측 모양)이 낡아 가는 두 지점.
        for ago in [31 * 60, Int(aiDay) + 1] {
            let display = AILimitFreshnessRule.display(aiSnapshot(used: 0, observedAgo: TimeInterval(ago)), now: aiNow)
            #expect(display.freshness.isFloorOnly, "전제: \(ago)초 전이면 등급은 하한이다")
            #expect(display.valueText == "0%", "\(ago)초 전 0% 의 글자가 '\(display.valueText)' 다")
            #expect(display.floorOnly == false)
            #expect(display.percent == 0)
            // 낡았다는 사실은 사라지지 않는다 — **캡션**이 나른다(그게 사람에게 뜻이 있는 말이다).
            #expect(display.captionText != "방금" && display.captionText != "초기화됨")
            aiExpectValueMatchesPercent(display, "창 하나 · \(ago)초 전 0%")
        }

        // ③ 조합. 0% 하한만 모인 경우 — 메뉴바 한 줄·위젯 small 이 그리는 그 값이다.
        let combined = AILimitFreshnessRule.combine([
            aiPlainDisplay(used: 0, observedAgo: 3 * aiHour),
            aiPlainDisplay(window: .weekly, used: 0, observedAgo: 2 * aiDay)
        ])
        #expect(combined.valueText == "0%", "조합값의 글자가 '\(combined.valueText)' 다")
        #expect(combined.floorOnly == false)
        #expect(combined.percent == 0)
        #expect(combined.captionText == "2일 전", "조합 캡션은 가장 낡은 기여자 것이다")
        aiExpectValueMatchesPercent(combined, "0% 하한 둘")

        // ④ 제공자 카드 경로도 같은 입구를 쓴다(뷰가 자기 글자를 만들면 여기서 안 걸린다 — 그래서 값으로 잰다).
        let card = AILimitFreshnessRule.displays(
            provider: AILimitProviderSnapshot(provider: .codex, windows: [
                aiSnapshot(window: .fiveHour, used: 0, observedAgo: 3 * aiHour),
                aiSnapshot(window: .weekly, used: 12, observedAgo: 3 * aiHour)
            ]),
            now: aiNow
        )
        #expect(card.map(\.valueText) == ["0%", "12% 이상"], "카드 줄의 글자가 \(card.map(\.valueText)) 다")
        #expect(card.map(\.floorOnly) == [false, true])
    }

    /// ★ **일반 불변식**: 낱개든 짝이든 셋이든, `percent` 와 `valueText` 가 어긋나는 조합이 하나도 없다.
    /// 숫자와 글자를 다른 입력으로 따로 만드는 구현은 이 행렬의 어딘가에서 반드시 걸린다.
    @Test func percentAndValueTextNeverContradictAcrossTheMatrix() {
        var pool: [AILimitDisplay] = []
        for used in [0, 0.4, 27, 90, 99.6, 101] as [Double] {
            for ago in [0, 59, 61, 1_800, 1_801, aiDay + 1] as [TimeInterval] {
                pool.append(aiPlainDisplay(used: used, observedAgo: ago))
            }
        }
        // 유예 양쪽 · 확신/미확인 양쪽.
        for resetAgo in [119, 120, 121, 1_800, 1_801, 3 * aiHour] as [TimeInterval] {
            pool.append(aiResetClaimDisplay(used: 40, observedAgo: 4 * aiHour, resetAgo: resetAgo))
        }
        pool.append(AILimitFreshnessRule.display(nil, now: aiNow))                       // 스냅샷 없음
        pool.append(AILimitFreshnessRule.display(                                        // 건전성 모순
            aiSnapshot(used: 30, observedAgo: 60, resetsAt: aiNow.addingTimeInterval(-120)), now: aiNow))
        // 기준선이 갈리는지 — 풀에 리셋 주장과 하한과 '모름'이 다 들어 있어야 이 테스트가 뜻을 갖는다.
        #expect(pool.contains { $0.freshness.isResetClaim })
        #expect(pool.contains { $0.floorOnly })
        #expect(pool.contains { $0.freshness == .unknown })

        for (index, display) in pool.enumerated() {
            aiExpectValueMatchesPercent(display, "낱개 #\(index)")
        }
        for (left, lhs) in pool.enumerated() {
            for (right, rhs) in pool.enumerated() {
                aiExpectValueMatchesPercent(AILimitFreshnessRule.combine([lhs, rhs]), "짝 #\(left)·#\(right)")
            }
        }
        for (index, extra) in pool.enumerated() {
            let trio = [pool[0], pool[pool.count - 1], extra]
            aiExpectValueMatchesPercent(AILimitFreshnessRule.combine(trio), "셋 #\(index)")
        }
    }

    // MARK: ⑬ 상수와 경계의 **정확히 그 점** — 한쪽만 재면 뮤테이션이 산다

    /// 상수를 **이름으로** 되묻는다. 숫자를 흘리면(120 → 121) 유예가 조용히 넓어지는데, 경계 테스트가
    /// 상대값으로만 적혀 있으면 함께 밀려 전부 초록이다.
    @Test func toleranceConstantsAreTheMeasuredOnes() {
        #expect(AILimitFreshnessRule.clockSkewTolerance == 120)
        #expect(AILimitFreshnessRule.sameWindowTolerance == 600)
        #expect(AILimitFreshnessRule.freshWithin == 60)
        #expect(AILimitFreshnessRule.recentWithin == 1_800)
        #expect(AILimitFreshnessRule.staleWithin == 86_400)
        // 창 종류 허용오차는 시계 유예보다 **느슨해야** 한다(머리말: 거짓 unknown 이 더 비싸다).
        #expect(AILimitFreshnessRule.sameWindowTolerance > AILimitFreshnessRule.clockSkewTolerance)
        // '방금'의 경계는 `FeedbackText.ageText` 와 **같은 숫자**(60)에서 갈린다. 포함 여부만 1초 다르다 —
        // 등급은 `<= 60`, 문구는 `< 60` 이라 정확히 60초인 행은 `.fresh` 인데 캡션이 "1분 전"이다.
        // 값이 갈리지는 않는다(`.fresh` 와 `.recent` 는 둘 다 등호로 말한다). 그 1초를 여기 적어 둬서,
        // 숫자를 흘리는 뮤테이션(60 → 59/61)이 둘 중 어느 쪽에서든 걸리게 한다.
        #expect(FeedbackText.ageText(aiNow.addingTimeInterval(-(AILimitFreshnessRule.freshWithin - 1)), now: aiNow) == "방금")
        #expect(FeedbackText.ageText(aiNow.addingTimeInterval(-AILimitFreshnessRule.freshWithin), now: aiNow) == "1분 전")
        #expect(AILimitFreshnessRule.grade(age: AILimitFreshnessRule.freshWithin, resetClaimed: false) == .fresh)
        #expect(AILimitFreshnessRule.grade(age: AILimitFreshnessRule.freshWithin + 1, resetClaimed: false) == .recent)
    }

    /// 유예의 **정확히 그 점**(리셋 + 120초)에서 주장이 선다. `>=` → `>` 뮤테이션은 여기서만 죽는다
    /// (−119/−121 만 재는 스위트에서는 살아남았다 — 2026-10-07 실증).
    @Test func resetGraceClaimsExactlyAtTheTolerance() {
        let snapshot = aiSnapshot(
            used: 40, observedAgo: 2 * aiHour,
            resetsAt: aiNow.addingTimeInterval(-AILimitFreshnessRule.clockSkewTolerance)
        )
        let atTolerance = AILimitFreshnessRule.display(snapshot, now: aiNow)
        #expect(atTolerance.freshness == .reset, "정확히 유예만큼 지난 점에서 주장하지 않았다")
        #expect(atTolerance.valueText == "0%")
        // 1초 앞(= 유예 안쪽)에서는 아직 하한이다 — 양쪽에서 못 박는다.
        let oneSecondEarlier = AILimitFreshnessRule.display(snapshot, now: aiNow.addingTimeInterval(-1))
        #expect(oneSecondEarlier.freshness == .stale)
        #expect(oneSecondEarlier.valueText == "40% 이상")
    }

    /// 창 종류 건전성의 **정확히 그 점**(창 길이 + 허용오차)은 멀쩡한 행이다. `>` → `>=` 뮤테이션은 여기서만 죽는다
    /// (+300/+601 만 재는 스위트에서는 살아남았다 — 2026-10-07 실증).
    @Test func sameWindowToleranceIncludesItsExactPoint() {
        let observed = aiNow.addingTimeInterval(-60)
        func display(beyond: TimeInterval) -> AILimitDisplay {
            AILimitFreshnessRule.display(
                AILimitWindowSnapshot(
                    window: .fiveHour,
                    usedPercent: 30,
                    resetsAt: observed.addingTimeInterval(AILimitWindow.fiveHour.lengthSeconds + beyond),
                    observedAt: observed,
                    source: .local
                ),
                now: aiNow
            )
        }
        #expect(display(beyond: AILimitFreshnessRule.sameWindowTolerance).freshness == .fresh,
                "허용오차의 정확히 그 점을 '다른 창'으로 버렸다 — 거짓 unknown 은 정보를 통째로 버린다")
        #expect(display(beyond: AILimitFreshnessRule.sameWindowTolerance + 1).freshness == .unknown)
    }

    // MARK: ⑭ 미래 관측 시각 — 유예를 넘으면 '모른다'

    /// 맥 시계가 3시간 빠른 채로 올린 숫자를 음수 경과 → 0 으로 접으면, 폰이 3시간 묵은 값을 "방금"이라고
    /// **등호로** 단정한다(하한도 아니다). 반대쪽 모순(`resetsAt < observedAt`)은 이미 `unknown` 인데
    /// 이쪽만 봐주면 더 비싼 거짓을 통과시키는 셈이다.
    @Test func futureObservationBeyondToleranceIsUnknown() {
        func display(ahead: TimeInterval) -> AILimitDisplay {
            AILimitFreshnessRule.display(
                AILimitWindowSnapshot(
                    window: .fiveHour,
                    usedPercent: 27,
                    resetsAt: aiNow.addingTimeInterval(ahead + 3 * aiHour),
                    observedAt: aiNow.addingTimeInterval(ahead),
                    source: .local
                ),
                now: aiNow
            )
        }
        // 유예 안쪽(정확히 그 점까지)은 지금처럼 0 으로 접어 '방금'이다 — NTP 떨림으로 행을 버리지 않는다.
        let atTolerance = display(ahead: AILimitFreshnessRule.clockSkewTolerance)
        #expect(atTolerance.freshness == .fresh)
        #expect(atTolerance.captionText == "방금")
        #expect(atTolerance.valueText == "27%")

        // 1초만 넘으면 '모른다'. 숫자를 지어내지 않고, 자리는 남긴다.
        let justOver = display(ahead: AILimitFreshnessRule.clockSkewTolerance + 1)
        #expect(justOver.freshness == .unknown, "유예를 넘는 미래 관측을 '방금'이라고 단정했다")
        #expect(justOver.valueText == "—")
        #expect(justOver.percent == nil)
        #expect(justOver.isVisible)
        #expect(justOver.captionText == "알 수 없음")

        // 맥 시계가 3시간 빠른 실전 모양.
        #expect(display(ahead: 3 * aiHour).freshness == .unknown)
        aiExpectValueMatchesPercent(justOver, "미래 관측")
    }

    // MARK: ⑮ 안티그래비티 — 안 쓴 창이 아니어도 `reset_time` 이 투영일 수 있다
    //
    // 호출부가 `trusts(usedPercent:resetAfterSeconds:windowSeconds:)` 에 `nil, nil` 을 넘기면 실질 조건이
    // `usedPercent > 0` **하나뿐**이라 가드가 절반만 걸린다. 안티그래비티는 절대 시각을 주지만
    // `reset_time − observedAt` 가 곧 상대 초이므로 지문을 그대로 잴 수 있다(FACTS §3 '미확인').

    /// 0 < 사용률인데 5시간 창의 `reset_time` 이 정확히 `관측시각 + 창길이` 다 → 경계가 아니라 투영이다.
    /// 주간 창은 관측 + 3일이라 지문이 아니다 → **그쪽은 믿는다**(기준선이 갈려야 이 테스트가 뜻을 갖는다).
    @Test func antigravityFoldsResetTimeThatTracksTheObservation() throws {
        let json = aiAntigravityCLIJSON(
            fiveHourRemaining: 0.5,
            fiveHourReset: aiNow.addingTimeInterval(AILimitWindow.fiveHour.lengthSeconds),
            weeklyRemaining: 0.5,
            weeklyReset: aiNow.addingTimeInterval(3 * aiDay)
        )
        let snapshot = try AILimitAntigravityReader.parseCLI(Data(json.utf8), observedAt: aiNow).get()
        #expect(snapshot.window(.fiveHour)?.usedPercent == 50, "전제: 남은 0.5 → 50% 썼다")
        #expect(snapshot.window(.fiveHour)?.resetsAt == nil,
                "0 < 사용률이라고 투영을 경계로 믿었다 — 화면의 리셋 시각이 분마다 바뀐다")
        #expect(snapshot.window(.weekly)?.resetsAt != nil, "진짜 경계까지 버렸다")
    }

    /// 지문의 폭(1초)을 양쪽에서. 느슨하면 진짜 경계를 버리고, 없으면 투영을 통과시킨다.
    @Test func antigravityProjectionFingerprintIsOneSecondWide() throws {
        func fiveHourReset(beyondWindow: TimeInterval) throws -> Date? {
            let json = aiAntigravityCLIJSON(
                fiveHourRemaining: 0.5,
                fiveHourReset: aiNow.addingTimeInterval(AILimitWindow.fiveHour.lengthSeconds + beyondWindow),
                weeklyRemaining: 0.5,
                weeklyReset: aiNow.addingTimeInterval(3 * aiDay)
            )
            return try AILimitAntigravityReader.parseCLI(Data(json.utf8), observedAt: aiNow).get().window(.fiveHour)?.resetsAt
        }
        #expect(try fiveHourReset(beyondWindow: 0) == nil)
        #expect(try fiveHourReset(beyondWindow: 1) != nil)
        #expect(try fiveHourReset(beyondWindow: -1) != nil)
    }
}

// MARK: - 스토어: 간격과 429 금지창은 **프로세스 수명보다 오래 산다**
//
// 초안은 숫자와 실패 분류만 영속해서, 앱을 다시 켜면 `lastAttemptAt == nil` → `isDue` 즉시 참이고
// `silentUntil == nil` → `retry-after` 가 남아 있어도 바로 노크했다. Claude 는 **5분에 5회**가 상한이라
// (실측 2026-10-07) 5분 안에 앱이 여러 번 켜지면 사용자 본인 계정이 잠긴다 — 스토어가 막겠다고 선언한
// 바로 그 사고를 스토어가 만든다.
//
// 이 스위트는 `Date` 를 주입한 순수 계산이다. 러너는 아무것도 읽지 않는 클로저라 프로세스도 네트워크도 없다
// (★ 특히 **Claude 를 실제로 부르는 테스트를 만들면 안 된다** — 스위트가 5회를 넘기면 계정이 5분간 잠긴다).
@Suite("AILimitsCore — 스토어: 간격·금지창 영속")
@MainActor
struct AILimitsCoreScheduleTests {
    /// 격리 UserDefaults. ★ 이름은 **반드시** `CheckTestScratch` 의 절대 경로다 — 평범한 도메인 이름을 주면
    /// `~/Library/Preferences` 에 plist 가 쌓인다(62만 개가 `cfprefsd` 를 죽인 그 사고와 같은 가족).
    private func isolatedDefaults(_ function: String = #function, line: Int = #line) -> UserDefaults {
        let name = CheckTestScratch.uniqueSuitePath(function: function, line: line)
        let defaults = UserDefaults(suiteName: name) ?? .standard
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    private func store(_ defaults: UserDefaults, now: @escaping () -> Date) -> AILimitStore {
        AILimitStore(defaults: defaults, clock: now, runner: { _ in AILimitReadOutcome() })
    }

    /// 재시작해도 **간격이 이어진다.** 없으면 앱을 다섯 번 켜는 것만으로 5분/5회 상한을 넘긴다.
    @Test func attemptStampSurvivesRestart() async {
        let defaults = isolatedDefaults()
        let first = store(defaults, now: { aiNow })
        await first.refreshIfDue(now: aiNow)
        #expect(first.runnerCallCount == 1, "전제: 첫 바퀴는 돈다")

        // 앱을 1분 뒤에 다시 켠다 — 같은 디스크.
        let reborn = store(defaults, now: { aiNow.addingTimeInterval(60) })
        #expect(reborn.lastAttemptAt == aiNow, "시도 시각이 복원되지 않았다")
        #expect(reborn.isDue(now: aiNow.addingTimeInterval(60)) == false, "재시작이 10분 주기를 리셋했다")
        #expect(reborn.isDue(now: aiNow.addingTimeInterval(60), force: true) == false, "재시작이 5분 하한을 뚫었다")
        await reborn.refreshIfDue(now: aiNow.addingTimeInterval(60), force: true)
        #expect(reborn.runnerCallCount == 0, "재시작 직후 노크했다 — 5분에 5회 상한을 이렇게 넘긴다")
        // 기준선이 갈린다: 하한이 지나면 반드시 돈다(영원히 막히면 위 단언들이 공허하다).
        #expect(reborn.isDue(now: aiNow.addingTimeInterval(300), force: true))
    }

    /// 러너를 부르기 **직전에** 디스크로 내려간다 — 바퀴 도중에 앱이 죽어도 그 시도가 장부에 남아야 한다.
    /// (`apply` 끝에서만 쓰면 멈춘 러너·강제 종료가 스탬프를 통째로 삼킨다.)
    @Test func attemptStampLandsBeforeTheRunner() async {
        let defaults = isolatedDefaults()
        // `UserDefaults` 는 스레드 안전하지만 `Sendable` 이 아니다 — 러너는 `@Sendable` 이라 상자로 넘긴다.
        let box = AILimitDefaultsBox(defaults: defaults)
        let subject = AILimitStore(defaults: defaults, clock: { aiNow }, runner: { _ in
            // 러너 안에서 이미 디스크에 적혀 있어야 한다.
            #expect(box.defaults.object(forKey: AILimitStore.lastAttemptKey) as? Double == aiNow.timeIntervalSince1970,
                    "시도 스탬프가 러너 뒤에 적힌다 — 바퀴 도중에 죽으면 그 시도가 사라진다")
            return AILimitReadOutcome()
        })
        await subject.refreshIfDue(now: aiNow)
        #expect(subject.runnerCallCount == 1)
    }

    /// 429 금지창도 재시작을 넘어 산다. 없으면 `retry-after` 안에서 다시 노크해 금지창을 늘린다.
    @Test func rateLimitBanSurvivesRestart() async {
        let defaults = isolatedDefaults()
        let first = AILimitStore(defaults: defaults, clock: { aiNow }, runner: { _ in
            AILimitReadOutcome(results: [.claude: .failure(AILimitReadError(.rateLimited, retryAfter: 300))])
        })
        await first.refreshIfDue(now: aiNow)
        #expect(first.silentUntil == aiNow.addingTimeInterval(300), "전제: 금지창이 섰다")

        let reborn = store(defaults, now: { aiNow.addingTimeInterval(299) })
        #expect(reborn.silentUntil == aiNow.addingTimeInterval(300), "금지창이 재시작에 사라졌다")
        #expect(reborn.isDue(now: aiNow.addingTimeInterval(299), force: true) == false, "금지창 안에서 노크했다")
        await reborn.refreshIfDue(now: aiNow.addingTimeInterval(299), force: true)
        #expect(reborn.runnerCallCount == 0)
        // 금지창이 끝나면 돈다.
        #expect(reborn.isDue(now: aiNow.addingTimeInterval(301), force: true))
    }

    /// 성공하면 금지창이 사라지고 **디스크에서도** 사라진다(낡은 금지창이 다음 실행을 막지 않게).
    @Test func successClearsTheBanOnDiskToo() async {
        let defaults = isolatedDefaults()
        let box = AILimitScheduleOutcomeBox(
            outcome: AILimitReadOutcome(results: [.claude: .failure(AILimitReadError(.rateLimited, retryAfter: 300))])
        )
        let subject = AILimitStore(defaults: defaults, clock: { aiNow }, runner: { _ in box.outcome })
        await subject.refreshIfDue(now: aiNow)
        #expect(defaults.object(forKey: AILimitStore.silentUntilKey) != nil, "전제: 금지창이 적혔다")

        box.outcome = AILimitReadOutcome(results: [.claude: .success(
            AILimitProviderSnapshot(provider: .claude, windows: [
                AILimitWindowSnapshot(window: .fiveHour, usedPercent: 27, resetsAt: nil,
                                      observedAt: aiNow.addingTimeInterval(900), source: .local)
            ])
        )])
        await subject.refreshIfDue(now: aiNow.addingTimeInterval(900))
        #expect(subject.silentUntil == nil)
        #expect(defaults.object(forKey: AILimitStore.silentUntilKey) == nil, "성공 뒤에도 금지창이 디스크에 남았다")
    }

    /// 디스크의 **미래** 스탬프는 지금으로 접는다 — 시계가 뒤로 간 맥에서 리밋 축이 영구고착되지 않게.
    /// (이 저장소의 '세션 영구고착'과 같은 결의 결함이다: 디스크 값 하나가 기능을 영원히 끈다.)
    @Test func futureStampsOnDiskDoNotWedgeTheStore() {
        let defaults = isolatedDefaults()
        let faraway = aiNow.addingTimeInterval(10 * aiDay).timeIntervalSince1970
        defaults.set(faraway, forKey: AILimitStore.lastAttemptKey)
        defaults.set(faraway, forKey: AILimitStore.silentUntilKey)

        let subject = store(defaults, now: { aiNow })
        #expect(subject.lastAttemptAt == aiNow, "미래 스탬프를 그대로 믿었다 — 10일 동안 한 번도 안 갱신한다")
        #expect(subject.silentUntil == aiNow.addingTimeInterval(AILimitStore.defaultBackoff),
                "금지창을 기본 백오프보다 길게 믿었다")
        #expect(subject.isDue(now: aiNow) == false)                        // 접은 값만큼은 지킨다
        #expect(subject.isDue(now: aiNow.addingTimeInterval(601)), "한 주기 뒤에도 막혀 있다")
    }

    /// 한 번도 안 돌았으면 간격은 **없다**(첫 실행이 즉시 읽는다). 디스크가 비어 있을 때의 기준선.
    @Test func afreshInstallIsDueImmediately() {
        let subject = store(isolatedDefaults(), now: { aiNow })
        #expect(subject.lastAttemptAt == nil)
        #expect(subject.silentUntil == nil)
        #expect(subject.isDue(now: aiNow))
    }
}

/// 러너가 돌려줄 결과를 바꿔 끼우는 상자(러너는 `@Sendable` 이라 값을 바깥에서 들고 있어야 한다).
private final class AILimitScheduleOutcomeBox: @unchecked Sendable {
    var outcome: AILimitReadOutcome
    init(outcome: AILimitReadOutcome) { self.outcome = outcome }
}

/// `UserDefaults` 를 `@Sendable` 러너 안으로 들고 들어가는 상자(스레드 안전하지만 `Sendable` 이 아니다).
private struct AILimitDefaultsBox: @unchecked Sendable {
    let defaults: UserDefaults
}
