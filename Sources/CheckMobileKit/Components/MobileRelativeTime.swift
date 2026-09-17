import Foundation

/// 상대 시각 문구(순수 — `RelativeTimeText` 가 그린다). 한국 시간(KST) 달력 기준.
///
///     1분 미만 "방금" · 1시간 미만 "N분 전" · 같은 날 "N시간 전" · 어제 "어제" · 그 전(올해) "M월 d일" · 다른 해 "yyyy. M. d."
/// 미래(기기 시계가 서버보다 느림)는 "방금"으로 접는다 — "-3분 전"을 보이지 않는다.
package enum MobileRelativeTime {
    package static let kst: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        calendar.locale = Locale(identifier: "ko_KR")
        return calendar
    }()

    package static func text(for date: Date, now: Date, calendar: Calendar = kst) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "방금" }
        if seconds < 3600 { return "\(Int(seconds / 60))분 전" }
        if calendar.isDate(date, inSameDayAs: now) { return "\(Int(seconds / 3600))시간 전" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "어제"
        }
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let nowYear = calendar.component(.year, from: now)
        if parts.year == nowYear {
            return "\(parts.month ?? 0)월 \(parts.day ?? 0)일"
        }
        return "\(parts.year ?? 0). \(parts.month ?? 0). \(parts.day ?? 0)."
    }

    /// 머리 날짜 "9월 17일 목"(지금 탭 · KST).
    package static func headerDate(_ date: Date, calendar: Calendar = kst) -> String {
        let parts = calendar.dateComponents([.month, .day, .weekday], from: date)
        let weekdays = ["일", "월", "화", "수", "목", "금", "토"]
        let weekday = parts.weekday.map { weekdays[($0 - 1 + 7) % 7] } ?? ""
        return "\(parts.month ?? 0)월 \(parts.day ?? 0)일 \(weekday)"
    }
}
