import Foundation

// 개인 근무 기록 인사이트(히트맵·주간 회고)의 순수 계산 계층.
// 서버는 work_sessions 원본 행만 주고, 요일/시간대 분해와 주간 요약은 전부 여기서 결정적으로 계산한다
// (뷰·스토어·테스트가 같은 함수를 공유 — 표시와 검증이 어긋나지 않게).
// 모든 시간 경계는 KST(TeamWeeklyGoal.kstCalendar) 규약을 따른다.

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

    /// 완료 세션 목록에서 히트맵을 만든다. (구현: wave-T)
    /// - sessions: 완료(ended_at 있음) 세션 행. 미완료 행은 무시한다.
    /// - now: 기준 시각(오늘 진행 중 세션은 포함하지 않는다 — 완료분만 집계).
    /// - weeks: 최근 몇 주를 볼지(기본 8). 그 이전 세션은 버린다.
    static func build(sessions: [WorkSessionRow], now: Date, weeks: Int = 8) -> WorkRhythmHeatmap {
        _ = (sessions, now, weeks)
        return .empty // TODO(wave-T)
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

    /// 완료 세션 목록에서 지난주 회고를 만든다. (구현: wave-T)
    /// - sessions: 최근 세션 행(지난주+그 전주를 포함할 만큼 넉넉히).
    /// - now: 기준 시각. 이 시점이 속한 주의 '직전 주'가 회고 대상이다.
    /// - goalSeconds: 현재 1인 주간 목표 초.
    /// 지난주 근무가 전혀 없으면 nil(보여줄 회고가 없다).
    static func build(sessions: [WorkSessionRow], now: Date, goalSeconds: Int) -> WeeklyRetro? {
        _ = (sessions, now, goalSeconds)
        return nil // TODO(wave-T)
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
