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

/// 개인 근무 리듬 히트맵: 요일(0=월 … 6=일) × 시간대(0…23) 칸에 누적된 근무 초.
/// 세션이 여러 시간대·여러 날에 걸치면 경계로 쪼개 각 칸에 실제로 머문 초만 넣는다.
struct WorkRhythmHeatmap: Equatable {
    static let dayCount = 7
    static let hourCount = 24

    /// buckets[요일][시간] = 누적 초.
    var buckets: [[Int]]
    /// 집계 대상 주 수(표시 문구용).
    var weeks: Int
    /// 전체 누적 초.
    var totalSeconds: Int

    static var empty: WorkRhythmHeatmap {
        WorkRhythmHeatmap(
            buckets: Array(repeating: Array(repeating: 0, count: hourCount), count: dayCount),
            weeks: 0,
            totalSeconds: 0
        )
    }

    /// 색 농도 정규화 기준(가장 진한 칸). 0이면 데이터 없음.
    var maxBucketSeconds: Int {
        buckets.reduce(0) { partial, row in max(partial, row.max() ?? 0) }
    }

    /// 가장 근무가 많았던 (요일, 시간) — 표시 문구용. 데이터가 없으면 nil.
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
    /// - now: 기준 시각(오늘 진행 중 세션은 포함하지 않는다 — 완료분만 집계).
    /// - weeks: 최근 몇 주를 볼지(기본 8). 그 이전 세션은 버린다.
    ///
    /// 집계 창은 now 가 속한 KST 주의 시작에서 (weeks-1)주 전 월요일 00:00 ~ now 다. 창에 걸친 세션은
    /// 겹치는 구간만 쓰고, 그 구간을 다시 KST 시간 경계로 쪼개 각 (요일, 시간) 칸에 실제로 머문 초만 더한다
    /// — 자정/시각 경계를 넘긴 세션이 한 칸에 통째로 몰려 리듬을 왜곡하지 않게 하는 것이 이 함수의 존재 이유다.
    static func build(sessions: [WorkSessionRow], now: Date, weeks: Int = 8) -> WorkRhythmHeatmap {
        build(parsed: WorkInsightsDate.parseSessions(sessions), now: now, weeks: weeks)
    }

    /// 파싱을 끝낸 세션으로 히트맵을 만든다(회고와 파싱 결과를 공유하는 실제 계산 경로).
    static func build(parsed sessions: [WorkInsightsSession], now: Date, weeks: Int = 8) -> WorkRhythmHeatmap {
        let calendar = TeamWeeklyGoal.kstCalendar
        let effectiveWeeks = max(1, weeks)
        let thisWeekStart = TeamWeeklyGoal.koreanWeekStart(for: now)
        guard let windowStart = calendar.date(
            byAdding: .weekOfYear,
            value: -(effectiveWeeks - 1),
            to: thisWeekStart
        ) else {
            return .empty
        }

        var buckets = Array(repeating: Array(repeating: 0, count: hourCount), count: dayCount)
        var total = 0

        for session in sessions {
            // 창 밖(전체가 과거이거나 미래)이면 버리고, 걸치면 겹치는 구간만 남긴다.
            var cursor = max(session.start, windowStart)
            let end = min(session.end, now)
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

        return WorkRhythmHeatmap(buckets: buckets, weeks: effectiveWeeks, totalSeconds: total)
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
        let thisWeekStart = TeamWeeklyGoal.koreanWeekStart(for: now)
        guard let lastWeekStart = calendar.date(byAdding: .weekOfYear, value: -1, to: thisWeekStart),
              let previousWeekStart = calendar.date(byAdding: .weekOfYear, value: -2, to: thisWeekStart)
        else {
            return nil
        }

        var dayTotals = Array(repeating: 0, count: WorkRhythmHeatmap.dayCount)
        var total = 0
        var sessionCount = 0
        var previousTotal = 0

        for session in sessions {
            let started = session.start
            let ended = session.end
            // 회고가 보는 창은 '지난주 + 그 전주' 2주뿐이다. 조회는 히트맵 때문에 8주치를 받아 오므로
            // 대부분의 행은 여기서 걸러진다 — 남은 6주치까지 하루 경계로 쪼개 봐야 전부 버려질 뿐이다.
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

/// 개인 기록 계산 결과 묶음(히트맵 + 회고). 두 계산이 같은 파싱 결과를 나눠 쓰도록 한곳에 묶고,
/// 스토어가 이 함수를 **메인액터 밖에서** 한 번에 돌린 뒤 결과만 받아 반영하게 하는 것이 존재 이유다.
/// (예전엔 응답 도착 직후 메인액터에서 두 계산을 연속 동기 호출해, 세션이 많은 계정에서 팝오버를 열 때마다
///  초 카운터가 멈추고 클릭이 씹혔다 — 2000행 기준 350ms 이상.)
struct WorkInsightsComputation: Equatable {
    let heatmap: WorkRhythmHeatmap
    let retro: WeeklyRetro?

    /// 순수 계산이라 어느 스레드에서 불러도 결과가 같다(전역 상태·시계 접근 없음 — now 는 인자로 받는다).
    /// - ongoingStart: **지금 진행 중인 내 세션**의 시작 시각(없으면 nil). 서버 조회는 완료 세션(ended_at not null)만
    ///   주므로, 이 값을 주지 않으면 방금 시작한 근무가 히트맵에 한 칸도 남지 않는다. 완료 세션이 0건인 계정
    ///   (=가입 첫날, 첫 [근무 종료] 전)에서는 그 결과가 heatmap.totalSeconds == 0 이라 '내 기록' 패널이
    ///   "아직 기록이 쌓이지 않았어요"로 단정하는데, 같은 팝오버 헤더는 진행분을 더한 이번 주 누적을
    ///   시간 단위로 세고 있었다(같은 화면 두 문장이 서로 모순 — 회귀 지점).
    static func build(
        rows: [WorkSessionRow],
        now: Date,
        weeks: Int,
        goalSeconds: Int,
        ongoingStart: Date? = nil
    ) -> WorkInsightsComputation {
        var parsed = WorkInsightsDate.parseSessions(rows)
        // 진행 중 세션은 '지금까지'만 기여한다(헤더의 라이브 주간 기여와 같은 규약 — 미래는 세지 않는다).
        if let ongoingStart, ongoingStart < now {
            parsed.append(WorkInsightsSession(start: ongoingStart, end: now))
        }
        return WorkInsightsComputation(
            heatmap: WorkRhythmHeatmap.build(parsed: parsed, now: now, weeks: weeks),
            retro: WeeklyRetro.build(parsed: parsed, now: now, goalSeconds: goalSeconds)
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
