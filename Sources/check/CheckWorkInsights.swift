import Foundation

// 개인 근무 기록 인사이트(히트맵·주간 회고)의 순수 계산 계층.
// 서버는 work_sessions 원본 행만 주고, 요일/시간대 분해와 주간 요약은 전부 여기서 결정적으로 계산한다
// (뷰·스토어·테스트가 같은 함수를 공유 — 표시와 검증이 어긋나지 않게).
// 모든 시간 경계는 KST(TeamWeeklyGoal.kstCalendar) 규약을 따른다.

/// 파싱을 끝낸 완료 세션 한 건(시작·종료 Date). 히트맵과 회고가 **같은 배열을 나눠 쓰기 위한** 중간 표현이다.
/// 예전에는 두 계산이 각자 원본 행을 훑으며 startedAt/endedAt 을 파싱해 행당 ISO8601 파싱이 4회 일어났고,
/// 그 비용이 전체의 98%를 차지해 2000행(서버 limit 상한)에서 메인스레드가 350ms 넘게 멈췄다.
/// 이제 파싱은 여기서 행당 2회만 하고, 두 계산은 파싱된 값을 재사용한다.
struct WorkInsightsSession: Equatable {
    let start: Date
    let end: Date
}

/// 히트맵과 회고가 **정확히 같은 주**를 보도록 주 경계를 한곳에서만 정하는 계산기.
/// 두 계산이 각자 경계를 세면 같은 패널 안에서 "지난주 32시간"(회고 카드)과 합이 다른 히트맵이 나란히 놓인다
/// — 그런 어긋남이 생길 자리를 아예 없앤다(조회 창 계산도 이 값을 쓴다).
enum WorkInsightsWeekWindow {
    /// now 가 속한 KST 주의 **직전 주** 창.
    /// - start: 지난주 월요일 00:00, - end: 이번 주 월요일 00:00(배타), - previousStart: 그 전주 월요일 00:00
    ///   (회고의 '전주 대비 증감' 비교선이자 서버 조회 창의 시작).
    static func lastWeek(now: Date) -> (start: Date, end: Date, previousStart: Date)? {
        let calendar = TeamWeeklyGoal.kstCalendar
        let thisWeekStart = TeamWeeklyGoal.koreanWeekStart(for: now)
        guard let start = calendar.date(byAdding: .weekOfYear, value: -1, to: thisWeekStart),
              let previousStart = calendar.date(byAdding: .weekOfYear, value: -2, to: thisWeekStart)
        else {
            return nil
        }
        return (start, thisWeekStart, previousStart)
    }
}

/// 개인 근무 리듬 히트맵: 요일(0=월 … 6=일) × 시간대(0…23) 칸에 **지난주 한 주** 동안 근무한 초.
/// 세션이 여러 시간대·여러 날에 걸치면 경계로 쪼개 각 칸에 실제로 머문 초만 넣는다.
struct WorkRhythmHeatmap: Equatable {
    static let dayCount = 7
    static let hourCount = 24

    /// buckets[요일][시간] = 누적 초. 한 주만 집계하므로 한 칸의 최대는 정확히 3600초다.
    var buckets: [[Int]]
    /// 전체 누적 초(= 지난주 총 근무 초. 회고 카드의 totalSeconds 와 같은 값이다).
    var totalSeconds: Int

    static var empty: WorkRhythmHeatmap {
        WorkRhythmHeatmap(
            buckets: Array(repeating: Array(repeating: 0, count: hourCount), count: dayCount),
            totalSeconds: 0
        )
    }

    /// 가장 진한 칸의 초(0이면 데이터 없음). 색 농도의 분모는 **이 값이 아니라** 3600초 고정이다
    /// — 진하기가 "그 시간대를 얼마나 채웠는지"를 그대로 뜻하도록(사람마다·주마다 기준이 흔들리지 않게).
    /// 여기 남은 건 요약/검증용 지표다.
    var maxBucketSeconds: Int {
        buckets.reduce(0) { partial, row in max(partial, row.max() ?? 0) }
    }

    /// 지난주 중 가장 근무가 많았던 (요일, 시간) — 표시 문구용. 데이터가 없으면 nil.
    var peakSlot: (day: Int, hour: Int)? {
        var best: (day: Int, hour: Int, seconds: Int)?
        for day in 0..<Self.dayCount {
            for hour in 0..<Self.hourCount where buckets[day][hour] > (best?.seconds ?? 0) {
                best = (day, hour, buckets[day][hour])
            }
        }
        guard let best else { return nil }
        return (best.day, best.hour)
    }

    /// 완료 세션 목록에서 히트맵을 만든다.
    /// - sessions: 완료(ended_at 있음) 세션 행. 미완료 행은 무시한다.
    /// - now: 기준 시각. 이 시점이 속한 주의 **직전 주**가 집계 대상이다(같은 패널의 회고 카드와 같은 주).
    ///
    /// 집계 창은 WorkInsightsWeekWindow.lastWeek 하나뿐이다(지난주 월요일 00:00 ~ 이번 주 월요일 00:00).
    /// 창에 걸친 세션은 겹치는 구간만 쓰고, 그 구간을 다시 KST 시간 경계로 쪼개 각 (요일, 시간) 칸에 실제로
    /// 머문 초만 더한다 — 자정/정시 경계를 넘긴 세션이 한 칸에 통째로 몰려 리듬을 왜곡하지 않게 하는 것이
    /// 이 함수의 존재 이유다.
    /// 예전에는 최근 8주를 합산했는데, 그러면 한 칸에 다른 주 기여가 겹겹이 얹혀 "어제 일요일에 쭉 일했는데
    /// 왜 시간대마다 색이 다르냐"가 된다(회귀 지점). 한 주만 보면 한 칸의 최대가 정확히 3600초로 고정된다.
    static func build(sessions: [WorkSessionRow], now: Date) -> WorkRhythmHeatmap {
        build(parsed: WorkInsightsDate.parseSessions(sessions), now: now)
    }

    /// 파싱을 끝낸 세션으로 히트맵을 만든다(회고와 파싱 결과를 공유하는 실제 계산 경로).
    static func build(parsed sessions: [WorkInsightsSession], now: Date) -> WorkRhythmHeatmap {
        let calendar = TeamWeeklyGoal.kstCalendar
        guard let window = WorkInsightsWeekWindow.lastWeek(now: now) else { return .empty }

        var buckets = Array(repeating: Array(repeating: 0, count: hourCount), count: dayCount)
        var total = 0

        for session in sessions {
            // 창 밖(그 전주 이전이거나 이번 주)이면 버리고, 걸치면 겹치는 구간만 남긴다.
            // 창의 끝이 이미 과거(이번 주 월요일 00:00)라 진행 중 세션의 '지금 이후'가 새어 들어올 자리도 없다.
            var cursor = max(session.start, window.start)
            let end = min(session.end, window.end)
            guard cursor < end else { continue }

            while cursor < end {
                guard let hourStart = WorkInsightsCalendar.hourStart(for: cursor),
                      let nextHour = calendar.date(byAdding: .hour, value: 1, to: hourStart),
                      nextHour > cursor
                else {
                    break
                }
                let sliceEnd = min(nextHour, end)
                guard sliceEnd > cursor else { break }
                let seconds = Int(sliceEnd.timeIntervalSince(cursor))
                if seconds > 0 {
                    buckets[WorkInsightsCalendar.weekdayIndex(for: hourStart)][calendar.component(.hour, from: hourStart)] += seconds
                    total += seconds
                }
                cursor = sliceEnd
            }
        }

        return WorkRhythmHeatmap(buckets: buckets, totalSeconds: total)
    }
}

/// 지난주 회고 요약. 월요일 첫 팝오버에 배너로 한 번 안내하고, 개인 기록 패널에서 언제든 다시 볼 수 있다.
struct WeeklyRetro: Equatable {
    /// 회고 대상 주의 시작(KST 월요일 00:00).
    let weekStart: Date
    /// 그 주 총 근무 초.
    let totalSeconds: Int
    /// 그 주의 1인 주간 목표 초(비교선).
    let goalSeconds: Int
    /// 그 전 주 총 근무 초(증감 표시용).
    let previousWeekSeconds: Int
    /// 완료 세션 수.
    let sessionCount: Int
    /// 가장 많이 일한 요일(0=월). 데이터 없으면 nil.
    let busiestDayIndex: Int?
    /// 그 요일의 근무 초.
    let busiestDaySeconds: Int

    /// 목표 달성 여부.
    var metGoal: Bool { goalSeconds > 0 && totalSeconds >= goalSeconds }

    /// 전주 대비 증감 초(양수면 더 일함). 전주가 0이면 증감 표시는 하지 않는다.
    var deltaSeconds: Int { totalSeconds - previousWeekSeconds }

    /// 주 집계는 그대로 두고 목표선만 갈아 끼운 사본.
    /// 팀 목표(teams.weekly_goal_hours)는 멤버십 응답이 도착해야 확정되는데, 콜드 런치 첫 팝오버에서는
    /// 인사이트 응답이 그보다 먼저 올 수 있어 회고가 기본 목표(40시간)로 굳는다. 목표에 의존하는 값은
    /// goalSeconds(와 그 파생 metGoal)뿐이므로, 세션을 다시 받아 오지 않고 이 사본으로 목표선만 바로잡는다.
    func withGoal(_ goalSeconds: Int) -> WeeklyRetro {
        WeeklyRetro(
            weekStart: weekStart,
            totalSeconds: totalSeconds,
            goalSeconds: goalSeconds,
            previousWeekSeconds: previousWeekSeconds,
            sessionCount: sessionCount,
            busiestDayIndex: busiestDayIndex,
            busiestDaySeconds: busiestDaySeconds
        )
    }

    /// 완료 세션 목록에서 지난주 회고를 만든다.
    /// - sessions: 최근 세션 행(지난주+그 전주를 포함할 만큼 넉넉히).
    /// - now: 기준 시각. 이 시점이 속한 주의 '직전 주'가 회고 대상이다.
    /// - goalSeconds: 현재 1인 주간 목표 초.
    /// 지난주 근무가 전혀 없으면 nil(보여줄 회고가 없다).
    ///
    /// 주 경계에 걸친 세션(일요일 밤~월요일 새벽)은 겹치는 구간만 클리핑해 귀속한다 — 저장된
    /// duration_seconds 를 통째로 쓰면 지난주 합이 옆 주 근무까지 삼킨다(서버 clippedContribution 과 동일 규약).
    static func build(sessions: [WorkSessionRow], now: Date, goalSeconds: Int) -> WeeklyRetro? {
        build(parsed: WorkInsightsDate.parseSessions(sessions), now: now, goalSeconds: goalSeconds)
    }

    /// 파싱을 끝낸 세션으로 회고를 만든다(히트맵과 파싱 결과를 공유하는 실제 계산 경로).
    static func build(parsed sessions: [WorkInsightsSession], now: Date, goalSeconds: Int) -> WeeklyRetro? {
        let calendar = TeamWeeklyGoal.kstCalendar
        // 주 경계는 히트맵과 **같은 헬퍼**에서만 얻는다 — 두 곳이 각자 세면 회고 합계와 히트맵 합이 어긋난다.
        guard let window = WorkInsightsWeekWindow.lastWeek(now: now) else { return nil }
        let lastWeekStart = window.start
        let thisWeekStart = window.end
        let previousWeekStart = window.previousStart

        var dayTotals = Array(repeating: 0, count: WorkRhythmHeatmap.dayCount)
        var total = 0
        var sessionCount = 0
        var previousTotal = 0

        for session in sessions {
            let started = session.start
            let ended = session.end
            // 회고가 보는 창은 '지난주 + 그 전주' 2주뿐이다(조회 창도 딱 그만큼이지만, 이번 주 행과
            // 경계에 맞닿기만 한 행은 여기서 걸러 낸다 — 하루 경계로 쪼개 봐야 전부 버려질 뿐이다).
            guard ended > previousWeekStart, started < thisWeekStart else { continue }

            // 지난주 [lastWeekStart, thisWeekStart) 와 겹치는 구간을 하루 경계로 쪼개 요일별로 더한다.
            var cursor = max(started, lastWeekStart)
            let weekEnd = min(ended, thisWeekStart)
            if cursor < weekEnd {
                sessionCount += 1
                while cursor < weekEnd {
                    let dayStart = TeamWeeklyGoal.koreanDayStart(for: cursor)
                    guard let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart), nextDay > cursor else {
                        break
                    }
                    let sliceEnd = min(nextDay, weekEnd)
                    guard sliceEnd > cursor else { break }
                    let seconds = Int(sliceEnd.timeIntervalSince(cursor))
                    if seconds > 0 {
                        dayTotals[WorkInsightsCalendar.weekdayIndex(for: dayStart)] += seconds
                        total += seconds
                    }
                    cursor = sliceEnd
                }
            }

            // 그 전 주 [previousWeekStart, lastWeekStart) 합(증감 비교선)도 같은 클리핑 규약으로 센다.
            let previousStart = max(started, previousWeekStart)
            let previousEnd = min(ended, lastWeekStart)
            if previousEnd > previousStart {
                previousTotal += Int(previousEnd.timeIntervalSince(previousStart))
            }
        }

        guard total > 0 else { return nil }

        // 최다 근무 요일. 동률이면 앞선 요일(월요일 쪽)이 이기도록 강부등호로 갱신한다.
        var busiestDayIndex: Int?
        var busiestDaySeconds = 0
        for index in 0..<WorkRhythmHeatmap.dayCount where dayTotals[index] > busiestDaySeconds {
            busiestDayIndex = index
            busiestDaySeconds = dayTotals[index]
        }

        return WeeklyRetro(
            weekStart: lastWeekStart,
            totalSeconds: total,
            goalSeconds: goalSeconds,
            previousWeekSeconds: previousTotal,
            sessionCount: sessionCount,
            busiestDayIndex: busiestDayIndex,
            busiestDaySeconds: busiestDaySeconds
        )
    }
}

/// 최근 13주(이번 주 + 지난 12주)의 **일별** 근무 초 — 깃허브 잔디와 같은 모양(주 열 × 요일 행)의 순수 데이터.
/// 히트맵(지난주 한 주의 시간대)과 회고(지난주 합계)가 답하지 못하는 "요즘 꾸준히 일하고 있나"를 한눈에 보이는 것이
/// 존재 이유다(이슈 #3). 서버 조회 창을 이만큼 넓혀 같은 세션 배열에서 계산하므로, 세션을 KST 일 경계로 쪼개
/// 귀속하는 규칙은 회고의 하루 클리핑과 정확히 같다 — 자정을 넘긴 세션이 한 날에 통째로 몰리면 잔디가 거짓말한다.
struct WorkDailyGrid: Equatable, Sendable {
    /// 기본 창 폭(주). 이번 주 열 하나 + 지난 12주 = 13열(팝오버 폭 안에 16pt 칸으로 들어가는 최대치).
    static let defaultWeeks = 13
    /// 잔디 농도의 분모(초) = 하루 8시간. 히트맵의 3600초 고정 분모와 같은 철학이다 — 자기 최대값 기준
    /// 상대 농도로 두면 같은 8시간이 그 주 다른 날에 따라 색이 달라지고, 사람마다 기준이 흔들린다.
    static let fullDaySeconds = 8 * 3_600

    /// 가장 오래된 주의 월요일 00:00(KST). 열 인덱스 0 의 시작이자 툴팁·월 라벨 날짜 계산의 원점.
    let weekStart: Date
    /// 열 수(주). empty 는 0.
    let weeks: Int
    /// seconds[주][요일 0=월 … 6=일] = 그 날 근무한 초. 미래 칸은 항상 0 이지만 "0 = 근무 없음"과 구분하기 위해
    /// 센티널을 쓰지 않고 isFuture(week:weekday:) 로 따로 가른다(값 배열은 어느 소비자든 그대로 합산해도 안전).
    var seconds: [[Int]]
    /// 오늘까지의 날 수(weekStart 부터 오늘 포함). 이 값 이상인 칸(주×7+요일)은 미래다.
    let days: Int

    static let empty = WorkDailyGrid(weekStart: .distantPast, weeks: 0, seconds: [], days: 0)

    /// 전체 누적 초. 패널 자리 문구 판정(지난주가 비어도 잔디에 기록이 있으면 본문을 그린다)에 쓴다.
    var totalSeconds: Int {
        seconds.reduce(0) { $0 + $1.reduce(0, +) }
    }

    /// (주, 요일) 칸이 오늘보다 뒤인지. 범위 밖 인덱스도 미래로 취급해 뷰가 어떤 인덱스로 물어도 안전하다.
    func isFuture(week: Int, weekday: Int) -> Bool {
        week * WorkRhythmHeatmap.dayCount + weekday >= days
    }

    /// (주, 요일) 칸의 KST 날짜(그 날 00:00). 툴팁 "9월 3일" 표기용.
    func date(week: Int, weekday: Int) -> Date? {
        TeamWeeklyGoal.kstCalendar.date(byAdding: .day, value: week * WorkRhythmHeatmap.dayCount + weekday, to: weekStart)
    }

    /// 잔디 칸 툴팁의 값 문구. 0 은 "근무 없음"(옅은 바탕 칸을 가리켰을 때 "0시간 00분"보다 뜻이 분명하다),
    /// 그 외는 헤더와 같은 "4시간 12분" 표기. 그리드 뷰가 날짜를 앞에 붙여 "9월 3일 · 4시간 12분"이 된다.
    static func tooltipValueText(_ seconds: Int) -> String {
        seconds > 0 ? MenuBarStatusFormatter.hoursMinutes(seconds) : "근무 없음"
    }

    /// 창의 시작 = now 가 속한 KST 주의 월요일 − (weeks − 1)주. 이번 주가 마지막 열이 되도록 잡는다.
    static func windowStart(now: Date, weeks: Int = defaultWeeks) -> Date? {
        let thisWeekStart = TeamWeeklyGoal.koreanWeekStart(for: now)
        return TeamWeeklyGoal.kstCalendar.date(byAdding: .weekOfYear, value: -(max(1, weeks) - 1), to: thisWeekStart)
    }

    /// 파싱을 끝낸 완료 세션 + 진행 중 세션으로 잔디를 만든다.
    /// - parsed: 완료 세션(히트맵·회고와 공유하는 파싱 결과).
    /// - now: 기준 시각. 창은 [이번 주 월요일 − (weeks−1)주, now) 이고, now 가 속한 날이 마지막 유효 칸이다.
    /// - ongoingStart: 진행 중인 내 세션의 시작(없으면 nil). 서버는 완료 세션만 주므로 이 값이 없으면 오늘 칸이
    ///   퇴근 전까지 비어 있다 — 헤더가 이미 세고 있는 오늘 근무가 잔디에만 없으면 "왜 오늘은 회색이냐"가 된다.
    ///   '지금까지'만 더한다(미래는 세지 않는다).
    static func build(
        parsed: [WorkInsightsSession],
        now: Date,
        ongoingStart: Date? = nil,
        weeks: Int = defaultWeeks
    ) -> WorkDailyGrid {
        let calendar = TeamWeeklyGoal.kstCalendar
        let weeks = max(1, weeks)
        guard let weekStart = windowStart(now: now, weeks: weeks),
              let todayOffset = calendar.dateComponents([.day], from: weekStart, to: TeamWeeklyGoal.koreanDayStart(for: now)).day
        else {
            return .empty
        }
        let dayCount = WorkRhythmHeatmap.dayCount
        var seconds = Array(repeating: Array(repeating: 0, count: dayCount), count: weeks)

        var sessions = parsed
        if let ongoingStart, ongoingStart < now {
            sessions.append(WorkInsightsSession(start: ongoingStart, end: now))
        }

        for session in sessions {
            // 창 앞쪽(12주보다 오래된 구간)은 버리고, 끝은 now 로 자른다 — 시계가 앞선 기기가 남긴 '미래' 종료가
            // 들어와도 오늘 뒤의 칸으로 새지 않는다(미래 칸 = 0 불변식).
            var cursor = max(session.start, weekStart)
            let end = min(session.end, now)
            guard cursor < end else { continue }

            // 회고(WeeklyRetro.build)와 같은 하루 경계 클리핑 — 자정을 넘긴 세션은 두 날에 실제 머문 초만큼 나뉜다.
            while cursor < end {
                let dayStart = TeamWeeklyGoal.koreanDayStart(for: cursor)
                guard let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart), nextDay > cursor else { break }
                let sliceEnd = min(nextDay, end)
                guard sliceEnd > cursor else { break }
                let slice = Int(sliceEnd.timeIntervalSince(cursor))
                if slice > 0,
                   let offset = calendar.dateComponents([.day], from: weekStart, to: dayStart).day,
                   offset >= 0, offset < weeks * dayCount {
                    seconds[offset / dayCount][offset % dayCount] += slice
                }
                cursor = sliceEnd
            }
        }

        return WorkDailyGrid(weekStart: weekStart, weeks: weeks, seconds: seconds, days: todayOffset + 1)
    }
}

/// 최근 13주(이번 주 + 지난 12주)의 **일별 AI 토큰** — 근무 잔디(WorkDailyGrid)와 같은 모양(주 열 × 요일 행), 값은 토큰(이슈 #3 의
/// 토큰 절반). 원천은 셋을 날짜별로 **max** 로 합친 맵이다(TokenDailyMerge): 서버 일별 표(기기 합, 지난 달까지 기억) ·
/// 이 맥의 로컬 일별 맵(현재 월 + 48시간, 오늘은 서버보다 최신) · Codex 계정 버킷(다른 기기·클라우드 포함, ~70일).
/// 창·미래 칸·툴팁 날짜 규칙은 근무 잔디와 정확히 같아야 한다 — 같은 패널에 두 잔디가 나란히 서므로 하루만 어긋나도 결함으로 보인다.
struct TokenDailyGrid: Equatable, Sendable {
    /// 잔디 농도의 분모(토큰/일) = **5천만 고정**. 근무 잔디의 8시간·히트맵의 3600초와 같은 철학(자기 최대값 기준이면 사람마다·
    /// 주마다 기준이 흔들린다). 근거: 2026년 8월 실측에서 헤비 유저(월 1.6B·2.7B·3.2B — 20260902090000 머리 주석)의 하루 최대치가
    /// 이 언저리였다 — 그 이상은 가장 진한 칸으로 클램프되고, 하루 1,250만(1/4) 이하가 첫 단계다.
    static let fullDayTokens = 50_000_000

    /// 가장 오래된 주의 월요일 00:00(KST). 근무 잔디와 같은 원점(WorkDailyGrid.windowStart).
    let weekStart: Date
    /// 열 수(주). empty 는 0.
    let weeks: Int
    /// tokens[주][요일 0=월 … 6=일] = 그 날 유효 토큰. 미래 칸은 항상 0(isFuture 로 가른다 — 근무 잔디와 같은 규약).
    var tokens: [[Int]]
    /// 오늘까지의 날 수(weekStart 부터 오늘 포함). 이 값 이상인 칸은 미래다.
    let days: Int

    static let empty = TokenDailyGrid(weekStart: .distantPast, weeks: 0, tokens: [], days: 0)

    /// 전체 누적 토큰(검증·요약용).
    var totalTokens: Int {
        tokens.reduce(0) { $0 + $1.reduce(0, +) }
    }

    /// (주, 요일) 칸이 오늘보다 뒤인지. 범위 밖 인덱스도 미래로 취급한다(WorkDailyGrid 와 같다).
    func isFuture(week: Int, weekday: Int) -> Bool {
        week * WorkRhythmHeatmap.dayCount + weekday >= days
    }

    /// 잔디 칸 툴팁의 값 문구. 0 은 "사용 없음"(옅은 바탕 칸을 가리켰을 때 "0 토큰"보다 뜻이 분명하다), 그 외는 토큰 행과 같은
    /// 콤마 전체 숫자 + "토큰"(축약 없음 — 순위판·내 행이 전부 전체 숫자라 여기만 "1.2M" 이면 단위가 어긋나 보인다).
    /// 그리드 뷰가 날짜를 앞에 붙여 "9월 3일 · 12,345,678 토큰"이 된다.
    static func tooltipValueText(_ tokens: Int) -> String {
        tokens > 0 ? "\(TokenNumberFormatter.grouped(tokens)) 토큰" : "사용 없음"
    }

    /// Date → KST 'YYYY-MM-DD'(claudeDaily/codexDaily·서버 day 컬럼과 같은 축). 서버 조회의 since 와 칸 귀속이 이 문자열을 쓴다.
    static func dayString(_ date: Date) -> String {
        let c = TeamWeeklyGoal.kstCalendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 1970, c.month ?? 1, c.day ?? 1)
    }

    /// 'YYYY-MM-DD' → 그 날 KST 00:00. 형이 어긋나면 nil(그 키는 버린다 — 잔디 전체를 못 그리는 것보다 낫다).
    static func date(fromDay day: String) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var c = DateComponents()
        c.year = parts[0]
        c.month = parts[1]
        c.day = parts[2]
        return TeamWeeklyGoal.kstCalendar.date(from: c)
    }

    /// 날짜별 토큰 맵으로 잔디를 만든다. 창은 근무 잔디와 같은 [이번 주 월요일 − (weeks−1)주, 오늘] 이고, 창 밖·미래 날짜는
    /// 버린다(시계가 앞선 기기가 서버에 남긴 '내일' 행이 미래 칸을 칠하지 않게 — 미래 칸 = 0 불변식).
    static func build(daily: [String: Int], now: Date, weeks: Int = WorkDailyGrid.defaultWeeks) -> TokenDailyGrid {
        let calendar = TeamWeeklyGoal.kstCalendar
        let weeks = max(1, weeks)
        guard let weekStart = WorkDailyGrid.windowStart(now: now, weeks: weeks),
              let todayOffset = calendar.dateComponents([.day], from: weekStart, to: TeamWeeklyGoal.koreanDayStart(for: now)).day
        else {
            return .empty
        }
        let dayCount = WorkRhythmHeatmap.dayCount
        let days = todayOffset + 1
        var tokens = Array(repeating: Array(repeating: 0, count: dayCount), count: weeks)
        for (day, value) in daily where value > 0 {
            guard let date = date(fromDay: day),
                  let offset = calendar.dateComponents([.day], from: weekStart, to: date).day,
                  offset >= 0, offset < weeks * dayCount, offset < days
            else { continue }
            tokens[offset / dayCount][offset % dayCount] += value
        }
        return TokenDailyGrid(weekStart: weekStart, weeks: weeks, tokens: tokens, days: days)
    }
}

/// 토큰 잔디의 세 원천을 날짜별 **유효 토큰** 한 맵으로 합치는 순수 규칙(스토어·테스트가 같은 함수를 쓴다).
/// 유효 토큰 = claude 합 + max(codex 로컬 합, codex 계정값) — 서버 보드 RPC(20260903160000)의 greatest 산식을 하루 단위로 옮긴 것이다.
enum TokenDailyMerge {
    /// 서버 일별 행(기기별)을 날짜별로 합친다. claude/codex 로컬 합은 기기 **sum**(각 맥의 자기 로그), codex_account 는 기기 간 **max**
    /// (모든 맥이 같은 계정값을 올리므로 더하면 기기 수만큼 뻥튀기 — 월 표와 같은 성질). null 인 기기는 max 에서 빠진다.
    static func serverTotals(_ rows: [TokenUsageDailyRow]) -> [String: Int] {
        var claude: [String: Int] = [:]
        var codexLocal: [String: Int] = [:]
        var codexAccount: [String: Int] = [:]
        for row in rows {
            claude[row.day, default: 0] += max(0, row.claudeTotal)
            codexLocal[row.day, default: 0] += max(0, row.codexTotal)
            if let account = row.codexAccount {
                codexAccount[row.day] = max(codexAccount[row.day] ?? 0, account)
            }
        }
        var result: [String: Int] = [:]
        for day in Set(claude.keys).union(codexLocal.keys).union(codexAccount.keys) {
            result[day] = (claude[day] ?? 0) + max(codexLocal[day] ?? 0, codexAccount[day] ?? 0)
        }
        return result
    }

    /// 이 맥의 로컬 일별 유효 토큰: claudeDaily + max(codexDaily, 계정 버킷). 계정 버킷은 UTC 일자 키지만 같은 문자열 키로 맞춘다
    /// (경계 9시간 차 — 월간 순위와 같은 문서화된 미결). 버킷은 ~70일이라 현재 월 밖의 Codex 날도 채워 준다(로컬 맵은 현재 월뿐).
    static func localTotals(usage: TokenUsageMonthly?, account: CodexAccountUsage?) -> [String: Int] {
        let claude = usage?.claudeDaily ?? [:]
        let codex = usage?.codexDaily ?? [:]
        let buckets = account?.buckets ?? [:]
        var result: [String: Int] = [:]
        for day in Set(claude.keys).union(codex.keys).union(buckets.keys) {
            let value = max(0, claude[day] ?? 0) + max(max(0, codex[day] ?? 0), max(0, buckets[day] ?? 0))
            if value > 0 { result[day] = value }
        }
        return result
    }

    /// 날짜별 max(서버, 로컬). 서버는 기기 합이라 보통 크지만, 오늘·최근은 로컬이 더 최신이고(업로드는 60초 게이트), 현재 월의
    /// 앞쪽 48시간 꼬리는 로컬이 부분값이라 서버가 크다 — 어느 쪽이 진실에 가까운지 날마다 다르므로 큰 쪽을 쓴다(더하면 이중 계상).
    static func merged(server: [String: Int], local: [String: Int]) -> [String: Int] {
        var result = server
        for (day, value) in local { result[day] = max(result[day] ?? 0, value) }
        return result
    }
}

/// 개인 기록 계산 결과 묶음(히트맵 + 회고). 두 계산이 같은 파싱 결과를 나눠 쓰도록 한곳에 묶고,
/// 스토어가 이 함수를 **메인액터 밖에서** 한 번에 돌린 뒤 결과만 받아 반영하게 하는 것이 존재 이유다.
/// (예전엔 응답 도착 직후 메인액터에서 두 계산을 연속 동기 호출해, 세션이 많은 계정에서 팝오버를 열 때마다
///  초 카운터가 멈추고 클릭이 씹혔다 — 2000행 기준 350ms 이상.)
struct WorkInsightsComputation: Equatable {
    let heatmap: WorkRhythmHeatmap
    let retro: WeeklyRetro?
    /// 최근 12주 일별 잔디. 같은 파싱 결과에서 한 번에 계산해 세 결과가 같은 세션 집합을 본다.
    let dailyGrid: WorkDailyGrid

    /// 순수 계산이라 어느 스레드에서 불러도 결과가 같다(전역 상태·시계 접근 없음 — now 는 인자로 받는다).
    /// - ongoingStart: **지금 진행 중인 내 세션**의 시작 시각(없으면 nil). 서버 조회는 완료 세션(ended_at not null)만
    ///   주므로, 이 값을 주지 않으면 주말을 넘겨 아직 끝나지 않은 근무(일요일 밤 시작 → 월요일까지 진행 중)의
    ///   지난주 몫이 히트맵·회고 양쪽에서 통째로 사라진다. 창이 지난주뿐이라 이번 주 진행분은 어차피 잘려 나간다.
    static func build(
        rows: [WorkSessionRow],
        now: Date,
        goalSeconds: Int,
        ongoingStart: Date? = nil
    ) -> WorkInsightsComputation {
        let completed = WorkInsightsDate.parseSessions(rows)
        var parsed = completed
        // 진행 중 세션은 '지금까지'만 기여한다(헤더의 라이브 주간 기여와 같은 규약 — 미래는 세지 않는다).
        if let ongoingStart, ongoingStart < now {
            parsed.append(WorkInsightsSession(start: ongoingStart, end: now))
        }
        return WorkInsightsComputation(
            heatmap: WorkRhythmHeatmap.build(parsed: parsed, now: now),
            retro: WeeklyRetro.build(parsed: parsed, now: now, goalSeconds: goalSeconds),
            // 잔디는 진행 세션을 스스로 얹는다(완료본 + ongoingStart) — 이미 얹은 parsed 를 주면 이중 계상이다.
            dailyGrid: WorkDailyGrid.build(parsed: completed, now: now, ongoingStart: ongoingStart)
        )
    }
}

/// 인사이트 계산 전용 KST 달력 헬퍼. 요일 인덱스 규약(0=월)과 시간 경계 절삭을 한곳에 모아,
/// 히트맵/회고가 같은 규약을 쓰도록 강제한다(뷰 표시 라벨도 이 인덱스를 그대로 쓴다).
enum WorkInsightsCalendar {
    /// KST 요일 인덱스(0=월 … 6=일). Calendar 의 weekday 는 1=일 … 7=토 라 +5 회전으로 월요일 기준으로 옮긴다.
    static func weekdayIndex(for date: Date) -> Int {
        (TeamWeeklyGoal.kstCalendar.component(.weekday, from: date) + 5) % 7
    }

    /// 그 시각이 속한 KST '정시'의 시작. KST 는 DST 가 없어 시간 경계가 항상 60분 간격이다.
    static func hourStart(for date: Date) -> Date? {
        let calendar = TeamWeeklyGoal.kstCalendar
        return calendar.date(from: calendar.dateComponents([.year, .month, .day, .hour], from: date))
    }
}

/// 서버가 준 타임스탬프 문자열 파서. PostgREST 는 소수초를 붙이기도(마이크로초 6자리) 안 붙이기도 하는데
/// ISO8601DateFormatter 는 옵션에 딱 맞는 형태만 받으므로, 두 옵션을 차례로 시도하고 그래도 실패하면
/// 소수부를 잘라 내고 한 번 더 시도한다(파싱 실패 = 그 세션이 통째로 사라지는 것이라 관대하게 받는다).
enum WorkInsightsDate {
    // 옵션 세팅 후 읽기 전용으로만 쓰는 파서라 공유해도 안전하다(Foundation 날짜 포매터의 파싱/포맷은 스레드 안전).
    // 세션 수백 건을 훑으므로 호출마다 새로 만들지 않는다.
    nonisolated(unsafe) private static let plainFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    nonisolated(unsafe) private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// 파싱 결과는 항상 **초 단위로 내림**해서 돌려준다. 히트맵은 세션을 시간 경계로 쪼갠 뒤 각 조각의 초를
    /// Int 로 잘라 더하므로, 소수초가 남아 있으면 조각마다 최대 1초씩 사라져(예: 09:00:00.12~10:00:00.65 가
    /// 3600초가 아니라 3599초로 집계) 누적 총량이 실제보다 줄어든다.
    static func parse(_ value: String) -> Date? {
        guard let date = parseRaw(value) else { return nil }
        return Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
    }

    /// 서버 행 배열을 **한 번만** 훑어 완료 세션(시작<종료)만 파싱해 돌려준다.
    /// 히트맵과 회고가 이 결과를 공유한다 — 예전처럼 각자 파싱하면 행당 4회가 되어 2000행에서 350ms 가 넘는다.
    /// 미완료(ended_at 없음)·파싱 실패·길이 0 이하 행은 두 계산 모두 어차피 버리므로 여기서 미리 떨군다.
    static func parseSessions(_ rows: [WorkSessionRow]) -> [WorkInsightsSession] {
        var parsed: [WorkInsightsSession] = []
        parsed.reserveCapacity(rows.count)
        for row in rows {
            guard let endedText = row.endedAt,
                  let started = parse(row.startedAt),
                  let ended = parse(endedText),
                  ended > started
            else {
                continue
            }
            parsed.append(WorkInsightsSession(start: started, end: ended))
        }
        return parsed
    }

    private static func parseRaw(_ value: String) -> Date? {
        if let date = plainFormatter.date(from: value) { return date }
        if let date = fractionalFormatter.date(from: value) { return date }
        guard let dot = value.firstIndex(of: ".") else { return nil }
        // 소수부만 도려내고 타임존 표기는 살린다("…:00.123456+00:00" → "…:00+00:00").
        var trimmed = String(value[value.startIndex..<dot])
        let rest = value[value.index(after: dot)...]
        if let firstNonDigit = rest.firstIndex(where: { !$0.isNumber }) {
            trimmed += String(rest[firstNonDigit...])
        } else {
            // 소수초로 끝나 타임존 표기가 없으면 UTC 로 본다(PostgREST timestamptz 관례).
            trimmed += "Z"
        }
        return plainFormatter.date(from: trimmed)
    }
}

/// 회고 배너를 이번 주에 이미 보여줬는지 기록하는 키 생성기(주 단위 1회 노출 규약).
/// 'YYYY-MM-DD' 형식의 KST 월요일 날짜를 그대로 키로 쓴다.
enum RetroWeekKey {
    static func current(_ now: Date = Date()) -> String {
        let start = TeamWeeklyGoal.koreanWeekStart(for: now)
        let c = TeamWeeklyGoal.kstCalendar.dateComponents([.year, .month, .day], from: start)
        return String(format: "%04d-%02d-%02d", c.year ?? 1970, c.month ?? 1, c.day ?? 1)
    }
}

/// 토큰 순위판 월 이동용 키 계산(KST 'YYYY-MM'). 현재 월보다 미래로는 갈 수 없다.
enum TokenBoardMonthNavigator {
    /// 월 키를 delta 개월만큼 이동한다(음수=과거). 결과가 현재 월을 넘어가면 현재 월로 클램프한다.
    static func step(_ monthKey: String, by delta: Int, now: Date = Date()) -> String {
        let cal = TeamWeeklyGoal.kstCalendar
        let parts = monthKey.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2 else { return TokenUsageMonthKey.current(now) }
        var comps = DateComponents()
        comps.year = parts[0]
        comps.month = parts[1]
        comps.day = 1
        guard let base = cal.date(from: comps),
              let moved = cal.date(byAdding: .month, value: delta, to: base)
        else {
            return TokenUsageMonthKey.current(now)
        }
        let movedKey = TokenUsageMonthKey.current(moved)
        let currentKey = TokenUsageMonthKey.current(now)
        return movedKey > currentKey ? currentKey : movedKey
    }

    /// 다음 달(미래 방향)로 더 갈 수 있는지 — 현재 월이면 불가.
    static func canStepForward(from monthKey: String, now: Date = Date()) -> Bool {
        monthKey < TokenUsageMonthKey.current(now)
    }

    /// 'YYYY-MM' → 표시용 "N월" (연도가 올해와 다르면 "YYYY년 N월").
    static func displayTitle(_ monthKey: String, now: Date = Date()) -> String {
        let parts = monthKey.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2 else { return monthKey }
        let currentYear = TeamWeeklyGoal.kstCalendar.component(.year, from: now)
        return parts[0] == currentYear ? "\(parts[1])월" : "\(parts[0])년 \(parts[1])월"
    }
}
