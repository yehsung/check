import Foundation

// 스캐너 전용 받침(AING_SCAN 빌드에만 있다 — 심볼릭 링크가 아닌 진짜 파일).
//
// CheckTokenUsage.swift 가 부르는 앱 쪽 달력 함수 하나(WorkDailyGrid.windowStart)를 같은 산식으로 둔다.
// 원본은 Sources/CheckCore/CheckWorkInsights.swift(WorkDailyGrid) + SupabaseWorkModels.swift(TeamWeeklyGoal)인데,
// 그 두 파일은 근무·팀 모델 전체를 끌고 와 스캐너에 넣을 수 없다. 산식이 갈리면 Claude 일별 창이 앱과 달라지므로
// AingScanTests 의 windowStart 표본 테스트가 고정값으로 못 박는다 — 원본을 바꾸면 이 파일과 그 테스트도 함께 바꿔라.
package struct WorkDailyGrid {
    /// 원본: WorkDailyGrid.defaultWeeks(13주 잔디 창).
    package static let defaultWeeks = 13

    /// 원본: TeamWeeklyGoal.kstCalendar — 그레고리력 · Asia/Seoul · 월요일 시작.
    private static let kstCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? TimeZone(secondsFromGMT: 9 * 3600)!
        calendar.firstWeekday = 2
        return calendar
    }()

    /// 원본과 같은 산식: 이번 주(KST 월요일 0시) − (weeks − 1)주.
    package static func windowStart(now: Date, weeks: Int = defaultWeeks) -> Date? {
        let thisWeekStart = kstCalendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        return kstCalendar.date(byAdding: .weekOfYear, value: -(max(1, weeks) - 1), to: thisWeekStart)
    }
}
