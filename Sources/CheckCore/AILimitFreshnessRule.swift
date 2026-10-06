import Foundation

// MARK: - 리밋 표시의 단 하나의 규칙 (순수) — 이 기능의 심장
//
// ## 이 파일이 푸는 문제
// 맥만 자격증명을 읽는다. 그러니 폰·위젯은 **맥이 깨어 있던 마지막 순간의 숫자**를 본다. 맥이 자는 사이
// 사용률은 올라갔을 수도 있고, 창이 리셋돼 0 이 됐을 수도 있다. 그 둘을 구별하지 않고 마지막 숫자를
// 그대로 그리면 두 가지 거짓이 생긴다:
//   ⓐ 리셋이 지났는데 "90% 썼다"를 보여 준다 → 사용자가 멈춘다(쓸 수 있는데 안 쓴다).
//   ⓑ 몇 시간 전 27% 를 "지금 27%" 로 보여 준다 → 큰 작업을 걸고 벽을 맞는다(**비싼 오류**).
//
// ## 왜 이게 해결 가능한가 — 단조성
// **한 창 안에서 사용률은 올라가기만 한다.** 중간에 내려가는 길이 없다(창이 끝나야 0 으로 돌아간다).
// 그래서 마지막으로 본 값은 **지금 값의 안전한 하한**이다: "적어도 이만큼은 썼다". 그리고 리셋 시각을
// 지나면 그 하한이 0 으로 떨어진다. 틀린 값 대신 보수적인 값을 말할 수 있는 근거가 이 한 줄이다.
//
// 그래서 표시 규칙은 "신선한가/낡았는가"가 아니라 **"이 숫자가 등호인가 하한인가"** 를 가른다.
// 낡으면 숫자를 버리는 게 아니라 `27% 이상` 으로 바꿔 말한다 — 정보를 잃지 않고 거짓만 뗀다.
//
// ## 함정 셋 (실측으로 드러난 것들, 전부 이 파일이 막는다)
//  ① **`usedPercent == 0` 인 행은 리셋을 주장하지 않는다.** Codex 실측(2026-10-07)에서 used 0% 일 때
//     `reset_at` 이 "지금 + 5시간"으로 **요청마다 미끄러지는 투영**이었다. 창 경계가 아니다. 숫자는 어차피
//     0 이라 안 바뀌지만, 그걸 리셋으로 읽으면 캡션이 "초기화됨"이라고 **없던 사건을 단정한다.**
//     사용자는 "방금 리셋됐구나"로 읽고 쓰기 계획을 세운다 — 틀린 자신감이 숫자보다 비싸다.
//  ② **리셋은 유예(120초) 뒤에만 주장한다.** 이르게 0% 를 말하면 사용자가 큰 작업을 걸고 벽을 맞는다.
//     늦게 인정하면 "27% 이상 · 3시간 전"을 몇 분 더 보는 것뿐 — 손해가 없다. 비대칭이라 한쪽으로 기운다.
//  ③ **리셋 뒤 '다음 경계'를 창 길이로 추정하지 않는다.** Claude 주간은 월요일 12:00 KST 고정이고
//     Codex 주간은 계정별 롤링 앵커다(실측). 창 길이를 더해 다음 경계를 만들면 계정마다 몇 시간씩 틀린
//     시각을 단정한다. 리셋 뒤 등급은 `now - resetsAt` **하나로만** 잰다.
//
// ## 규약
//  · `Date()` 를 부르지 않는다. `now` 는 전부 인자다(테스트가 모든 경계를 실증할 수 있어야 한다).
//  · 나이 문구는 `FeedbackText.ageText(_:now:)` 를 **부른다**. 저장소에 이미 세 벌 복제돼 있어,
//    네 벌째를 만들면 화면마다 '방금'의 경계가 갈린다.
//  · 값 · 캡션 · 표시여부가 **한 함수에서** 나온다. 스토어만 고치고 뷰는 그대로여서 테스트는 초록인데
//    화면은 아무것도 안 바뀌는 사고를 구조로 막는다(이 저장소 관례: '클라 게이트는 짝으로 있다').
//  · 출처(`AILimitSource`)는 캡션에 **쓰지 않는다**. 모델엔 남기되 사람에게는 나이만 말한다.

/// 숫자를 얼마나 믿을 수 있는가. **캡션 문구와 1:1 이다** — 등급이 늘면 문구도 반드시 늘어난다.
package enum AILimitFreshness: String, Equatable, Sendable {
    /// 60초 이내. 지금 값이다.
    case fresh
    /// 30분 이내. 등호로 말해도 되는 범위(5시간 창에서 30분은 사용률이 크게 안 움직인다).
    case recent
    /// 1일 이내. 숫자는 **하한**이다 — "이상" 을 붙인다.
    case stale
    /// 1일 초과. 역시 하한.
    case ancient
    /// 리셋 시각을 지났고 그 사실을 최근(30분 내)에 알았다 → 0% 를 확신한다.
    case reset
    /// 리셋 시각을 지났지만 그 뒤로 30분 넘게 아무것도 못 봤다 → 0% 지만 "확인 못 함"을 덧붙인다.
    case resetUnverified
    /// 판정 불가(값이 없거나 서로 모순). 숫자를 지어내지 않는다.
    case unknown

    /// 이 등급의 숫자는 등호가 아니라 하한인가.
    package var isFloorOnly: Bool {
        self == .stale || self == .ancient
    }

    /// 리셋을 주장하는 등급인가.
    package var isResetClaim: Bool {
        self == .reset || self == .resetUnverified
    }
}

/// 한 자리(카드의 한 줄 · 메뉴바 요약 · 위젯 칸)가 **그대로 그릴 것**. 값·캡션·표시여부가 전부 여기 있다.
///
/// 뷰는 이 구조체의 필드만 읽는다 — 퍼센트를 다시 반올림하거나 나이를 다시 세면 그 순간 규칙이 둘이 된다.
package struct AILimitDisplay: Equatable, Sendable {
    /// 그릴 것이 있는가. `false` 는 "이 자리를 아예 만들지 마라"(미연동 제공자·없는 창).
    /// 그래도 `valueText`/`captionText` 는 정직한 '모름' 문구를 담는다 — 이 깃발을 무시한 뷰가
    /// 거짓을 그리지는 않게.
    package let isVisible: Bool
    /// `27%` · `27% 이상` · `0%` · `—`. 숫자 조립은 이 한 곳에서만 한다.
    package let valueText: String
    /// `방금` · `12분 전` · `3일 전` · `초기화됨` · `초기화됨 · 확인 못 함` · `알 수 없음`.
    /// **출처는 말하지 않는다.** 나이만 말한다.
    package let captionText: String
    /// 바·링을 채울 비율 0…100. `unknown` 이면 nil(= 바를 그리지 마라, 0% 로 그리면 "안 썼다"는 거짓이다).
    package let percent: Double?
    /// `percent` 가 하한인가(= 숫자에 "이상"이 붙었는가). 색·경고 판정도 이걸 봐야 한다.
    package let floorOnly: Bool
    package let freshness: AILimitFreshness
    /// 이 값이 몇 초 묵었는가(리셋 주장이면 리셋 시각으로부터). 진단·정렬용. `unknown` 이면 nil.
    package let claimAge: TimeInterval?
    /// 어느 제공자/창의 줄인가. 조합값(`combine`)에서 기여자가 섞이면 nil.
    package let provider: AILimitProvider?
    package let window: AILimitWindow?
    /// 경로. **화면 문구에 쓰지 마라**(모델 전용). 섞이면 nil.
    package let source: AILimitSource?
    /// 이 창이 0 으로 돌아가는 절대 시각(알면). 위젯이 "N시간 뒤 초기화"를 투영할 재료다 —
    /// 남은 초를 저장하지 않는 까닭은 `AILimits.swift` 머리말에 있다.
    package let resetsAt: Date?

    package init(
        isVisible: Bool,
        valueText: String,
        captionText: String,
        percent: Double?,
        floorOnly: Bool,
        freshness: AILimitFreshness,
        claimAge: TimeInterval?,
        provider: AILimitProvider?,
        window: AILimitWindow?,
        source: AILimitSource?,
        resetsAt: Date?
    ) {
        self.isVisible = isVisible
        self.valueText = valueText
        self.captionText = captionText
        self.percent = percent
        self.floorOnly = floorOnly
        self.freshness = freshness
        self.claimAge = claimAge
        self.provider = provider
        self.window = window
        self.source = source
        self.resetsAt = resetsAt
    }
}

/// 리밋 표시의 단 하나의 규칙. 전부 순수 함수다.
package enum AILimitFreshnessRule {
    // MARK: 상수
    //
    // 값은 다 '어느 방향으로 틀리는 게 싼가'로 정했다. 숫자를 바꾸려면 그 비대칭부터 다시 봐야 한다.

    /// 기기 시계 오차 + 제공자 경계 처리의 여유. **리셋 주장의 유예**다(함정 ②).
    /// 120초: 맥·폰·서버 시계가 NTP 로 맞춰져도 몇십 초는 흔들리고, 제공자 경계도 정확히 그 초에 떨어지지 않는다.
    package static let clockSkewTolerance: TimeInterval = 120
    /// 이 안이면 '방금'. `FeedbackText.ageText` 의 '방금' 경계(60초)와 **같은 숫자**다.
    package static let freshWithin: TimeInterval = 60
    /// 이 안이면 등호로 말해도 된다. 넘으면 "이상"을 붙인다.
    package static let recentWithin: TimeInterval = 1_800
    /// 이 안이면 `.stale`, 넘으면 `.ancient`. 둘 다 하한이지만 캡션의 단위가 달라진다(시간 vs 일).
    package static let staleWithin: TimeInterval = 86_400
    /// "이 리셋 시각이 **그 창 종류**의 것인가"를 재는 허용오차.
    ///
    /// 왜 `clockSkewTolerance` 가 아니라 600초인가: 이 검사가 잡아야 하는 결함은 **창 종류 혼동**
    /// (5시간 칸에 주간 리셋이 들어왔다)이고, 그건 몇 **일** 단위로 벗어난다. 반면 너무 빡빡하게 잡으면
    /// 제공자가 경계를 몇 분 미루는 날 멀쩡한 행이 통째로 `unknown` 이 된다 — 거짓 `unknown` 은 정보를
    /// 통째로 버리는 쪽이라 더 비싸다. 그래서 느슨한 쪽으로 기운다.
    package static let sameWindowTolerance: TimeInterval = 600

    // MARK: 본체

    /// 창 하나가 그릴 것. **이 함수가 값·캡션·표시여부를 동시에 내보낸다.**
    ///
    /// 순서대로:
    ///  1. 스냅샷이 없다 → `unknown`, 안 보임.
    ///  2. 건전성: 리셋 시각이 관측 시각보다 **과거**다 → 모순이다(관측한 뒤에 리셋이 올 수는 있어도
    ///     관측 전에 올 수는 없다 — 그러면 그 값은 이미 리셋 뒤 값이어야 한다) → `unknown`.
    ///  3. 건전성: 리셋이 관측보다 **창 길이 + 허용오차**보다 멀다 → 그 창 종류의 리셋이 아니다 → `unknown`.
    ///  4. 리셋 주장 여부(함정 ①②): `usedPercent > 0` 이고 리셋 시각을 알고 now ≥ 리셋 + 유예.
    ///  5. 주장하면 floor = 0 · 나이 기준점 = 리셋 시각(함정 ③). 아니면 floor = clamp(사용률) · 기준점 = 관측 시각.
    ///  6. 등급 → 캡션 → 숫자 문구.
    package static func display(_ snapshot: AILimitWindowSnapshot?, now: Date) -> AILimitDisplay {
        guard let snapshot else { return unknownDisplay(isVisible: false, provider: nil, window: nil, source: nil) }

        if let resetsAt = snapshot.resetsAt {
            // ② 리셋이 관측보다 과거 — 기기 시계가 뒤로 갔거나 두 값이 다른 요청에서 섞였다.
            if resetsAt < snapshot.observedAt {
                return unknownDisplay(
                    isVisible: true,
                    provider: nil,
                    window: snapshot.window,
                    source: snapshot.source
                )
            }
            // ③ 이 리셋은 이 창 종류의 것이 아니다(5시간 칸에 주간 경계가 들어왔다 등).
            if resetsAt.timeIntervalSince(snapshot.observedAt) > snapshot.window.lengthSeconds + sameWindowTolerance {
                return unknownDisplay(
                    isVisible: true,
                    provider: nil,
                    window: snapshot.window,
                    source: snapshot.source
                )
            }
        }

        // ④ 리셋 주장. 세 조건이 **모두** 참이어야 한다.
        //    · usedPercent > 0  — 0% 행의 reset_at 은 미끄러지는 투영이다(함정 ①).
        //    · resetsAt != nil  — 모르는 경계는 지났다고 말할 수 없다.
        //    · now ≥ resetsAt + 유예 — 이르게 0% 를 말하지 않는다(함정 ②).
        let resetClaimed: Bool = {
            guard snapshot.usedPercent > 0, let resetsAt = snapshot.resetsAt else { return false }
            return now >= resetsAt.addingTimeInterval(clockSkewTolerance)
        }()

        let floor: Double
        let reference: Date
        if resetClaimed, let resetsAt = snapshot.resetsAt {
            floor = 0
            reference = resetsAt          // 함정 ③: 다음 경계를 추정하지 않는다. 나이는 이 시각으로만.
        } else {
            floor = min(max(snapshot.usedPercent, 0), 100)
            reference = snapshot.observedAt
        }

        // 기기 시계가 뒤로 갔으면(관측 시각이 미래) 음수가 나온다 → 0 으로 본다.
        // `FeedbackText.ageText` 도 같은 클램프를 하므로 등급과 문구가 갈리지 않는다.
        let age = max(0, now.timeIntervalSince(reference))
        let freshness = grade(age: age, resetClaimed: resetClaimed)
        let caption = captionText(freshness: freshness, reference: reference, now: now)

        return AILimitDisplay(
            isVisible: true,
            valueText: valueText(percent: floor, freshness: freshness),
            captionText: caption,
            percent: floor,
            floorOnly: freshness.isFloorOnly,
            freshness: freshness,
            claimAge: age,
            provider: nil,
            window: snapshot.window,
            source: snapshot.source,
            resetsAt: snapshot.resetsAt
        )
    }

    /// 제공자 스냅샷에서 창 하나를 뽑아 그린다. `display(_:now:)` 와 같은 규칙이고 `provider` 만 채운다.
    /// 창이 없으면 안 보임 — 창을 지어내 0% 로 그리지 않는다(Starter 요금제는 weekly 만 온다).
    package static func display(
        provider snapshot: AILimitProviderSnapshot?,
        window: AILimitWindow,
        now: Date
    ) -> AILimitDisplay {
        guard let snapshot else {
            return unknownDisplay(isVisible: false, provider: nil, window: window, source: nil)
        }
        guard let row = snapshot.window(window) else {
            return unknownDisplay(isVisible: false, provider: snapshot.provider, window: window, source: nil)
        }
        let base = display(row, now: now)
        return base.withProvider(snapshot.provider)
    }

    /// 제공자 카드가 그릴 줄들(5시간 → 주간). 없는 창은 **줄을 만들지 않는다.**
    package static func displays(provider snapshot: AILimitProviderSnapshot, now: Date) -> [AILimitDisplay] {
        snapshot.orderedWindows.map { display($0, now: now).withProvider(snapshot.provider) }
    }

    /// 숫자 하나만 보이는 자리(메뉴바 한 줄 요약 · 위젯 small)를 위한 조합.
    ///
    /// 규칙:
    ///  · **하한은 max.** 여러 창·여러 제공자 중 가장 많이 쓴 쪽이 먼저 막는 벽이다. 평균을 내면
    ///    한 제공자가 99% 인데 "50%" 라고 말한다 — 가장 비싼 거짓이다.
    ///  · **캡션은 claimAge 가 가장 큰 행 것.** 조합값의 신뢰도는 가장 낡은 기여자가 정한다.
    ///  · **"이상"은 기여자 중 하나라도 하한이면 붙는다.** 그래야 숫자와 캡션이 같은 이야기를 한다.
    ///  · `unknown` 기여자는 하한을 올리지도 내리지도 않는다('모른다'는 0 이 아니다). 전부 unknown 이면 unknown.
    package static func combine(_ displays: [AILimitDisplay]) -> AILimitDisplay {
        let known = displays.filter { $0.freshness != .unknown }
        guard !known.isEmpty else {
            let provider = common(displays.map(\.provider))
            let window = common(displays.map(\.window))
            let source = common(displays.map(\.source))
            return unknownDisplay(
                isVisible: displays.contains { $0.isVisible },
                provider: provider,
                window: window,
                source: source
            )
        }

        let floor = known.compactMap(\.percent).max() ?? 0
        // 가장 낡은 기여자(동률이면 등급이 더 나쁜 쪽)가 캡션을 정한다.
        let worst = known.max { lhs, rhs in
            let left = lhs.claimAge ?? 0
            let right = rhs.claimAge ?? 0
            if left != right { return left < right }
            return !lhs.floorOnly && rhs.floorOnly
        }
        // `known` 이 비어 있지 않으므로 `worst` 는 항상 값이 있다. 그래도 강제 풀기를 쓰지 않는다 —
        // 이 규칙이 크래시로 앱을 죽이는 경로를 아예 만들지 않는다.
        let caption = worst?.captionText ?? ""
        let freshness = worst?.freshness ?? .unknown
        let floorOnly = known.contains { $0.floorOnly } || freshness.isFloorOnly

        return AILimitDisplay(
            isVisible: true,
            valueText: valueText(percent: floor, floorOnly: floorOnly, isResetClaim: freshness.isResetClaim),
            captionText: caption,
            percent: floor,
            floorOnly: floorOnly,
            freshness: freshness,
            claimAge: worst?.claimAge,
            provider: common(known.map(\.provider)),
            window: common(known.map(\.window)),
            source: common(known.map(\.source)),
            resetsAt: nil   // 조합값에 '그 창의 리셋 시각'은 없다. 지어내지 않는다.
        )
    }

    // MARK: 등급·문구

    /// 나이(초) → 등급. 리셋 주장이면 `.reset` / `.resetUnverified` 로 갈린다.
    package static func grade(age: TimeInterval, resetClaimed: Bool) -> AILimitFreshness {
        if resetClaimed {
            return age <= recentWithin ? .reset : .resetUnverified
        }
        if age <= freshWithin { return .fresh }
        if age <= recentWithin { return .recent }
        if age <= staleWithin { return .stale }
        return .ancient
    }

    /// 캡션. 나이 문구는 **`FeedbackText.ageText` 를 부른다** — 네 벌째 사본을 만들면 화면마다 '방금'의 경계가 갈린다.
    package static func captionText(freshness: AILimitFreshness, reference: Date, now: Date) -> String {
        switch freshness {
        case .unknown: return "알 수 없음"
        case .reset: return "초기화됨"
        case .resetUnverified: return "초기화됨 · 확인 못 함"
        case .fresh, .recent, .stale, .ancient: return FeedbackText.ageText(reference, now: now)
        }
    }

    /// 숫자 문구. `unknown` 은 `—`, 리셋 주장은 `0%`, 하한이면 `N% 이상`, 아니면 `N%`.
    package static func valueText(percent: Double, freshness: AILimitFreshness) -> String {
        if freshness == .unknown { return unknownValueText }
        return valueText(percent: percent, floorOnly: freshness.isFloorOnly, isResetClaim: freshness.isResetClaim)
    }

    package static func valueText(percent: Double, floorOnly: Bool, isResetClaim: Bool) -> String {
        // 리셋을 주장하면 숫자는 0 이다 — 하한이든 아니든 "0% 이상"은 아무 말도 아니다.
        if isResetClaim { return "0%" }
        let whole = wholePercent(percent)
        return floorOnly ? "\(whole)% 이상" : "\(whole)%"
    }

    /// 판정 불가의 숫자 자리. em dash 하나 — `0%` 도 `?` 도 아니다(`0%` 는 거짓, `?` 는 고장으로 읽힌다).
    package static let unknownValueText = "—"

    /// 0…100 클램프 + 정수 반올림. **두 끝의 거짓을 막는다**:
    ///  · 0 보다 크면 절대 `0%` 로 적지 않는다(0.4% → `1%`). `0%` 는 "안 썼다"는 단정이다.
    ///  · 100 보다 작으면 절대 `100%` 로 적지 않는다(99.6% → `99%`). `100%` 는 "이미 막혔다"는 단정이다.
    /// 101 처럼 범위를 넘는 입력은 100 으로 접는다(제공자가 넘겨 주는 날 바가 화면을 뚫지 않게).
    package static func wholePercent(_ value: Double) -> Int {
        guard value.isFinite else { return 0 }
        let clamped = min(max(value, 0), 100)
        var whole = Int(clamped.rounded())
        if clamped > 0, whole == 0 { whole = 1 }
        if clamped < 100, whole == 100 { whole = 99 }
        return whole
    }

    // MARK: 내부

    private static func unknownDisplay(
        isVisible: Bool,
        provider: AILimitProvider?,
        window: AILimitWindow?,
        source: AILimitSource?
    ) -> AILimitDisplay {
        AILimitDisplay(
            isVisible: isVisible,
            valueText: unknownValueText,
            captionText: "알 수 없음",
            percent: nil,
            floorOnly: false,
            freshness: .unknown,
            claimAge: nil,
            provider: provider,
            window: window,
            source: source,
            resetsAt: nil
        )
    }

    /// 전부 같은 값이면 그 값, 섞이면 nil. 조합값이 한 기여자의 꼬리표를 **대표로 훔치지 않게** 한다.
    private static func common<T: Equatable>(_ values: [T?]) -> T? {
        let present = values.compactMap { $0 }
        guard let first = present.first, present.count == values.count else { return nil }
        return present.allSatisfy { $0 == first } ? first : nil
    }
}

extension AILimitDisplay {
    /// `provider` 만 채운 사본. 규칙 함수가 창 단위로 계산한 뒤 제공자 꼬리표를 붙이는 자리.
    fileprivate func withProvider(_ provider: AILimitProvider) -> AILimitDisplay {
        AILimitDisplay(
            isVisible: isVisible,
            valueText: valueText,
            captionText: captionText,
            percent: percent,
            floorOnly: floorOnly,
            freshness: freshness,
            claimAge: claimAge,
            provider: provider,
            window: window,
            source: source,
            resetsAt: resetsAt
        )
    }
}
