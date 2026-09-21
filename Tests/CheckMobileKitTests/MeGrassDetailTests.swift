import CheckCore
import CoreGraphics
import Foundation
import Testing
@testable import CheckMobileKit

/// 잔디 상세 화면의 **순수 규칙**(0.3.31). 화면 코드는 `#if os(iOS)` 안이라 macOS `swift test` 가 컴파일조차 못 한다 —
/// 그래서 좌표 → 칸 역산 · 하루 이동 · 날짜 표기 · 값 문구 · 원값 왕복을 순수 함수로 빼서 여기서 값으로 잰다.
// 전부 순수 함수라 @MainActor 가 필요 없다 — 메인 액터를 붙이면 같이 도는 비동기 하네스 테스트의 대기를 굶긴다.
@Suite("잔디 상세(폰) 순수 규칙")
struct MeGrassDetailTests {
    /// 격자 좌우 여백은 `MobileTheme.sideMargin`(16) 하나뿐이다 — 카드가 없다.
    /// 숫자를 여기 적는 이유: `MobileTheme` 은 `#if os(iOS)` 라 macOS 테스트가 못 읽는다(여백을 키우면 이 테스트가 빨개져야 한다).
    private static let sideMargin: CGFloat = 16
    private static func gridWidth(device: CGFloat) -> CGFloat { device - sideMargin * 2 }

    @Test("피치는 세 기기 폭에서 애플 최소 터치 대상 44pt 이상")
    func pitchMeetsMinimumTarget() {
        // 375 = iPhone SE(ios/project.yml TARGETED_DEVICE_FAMILY "1" — 아이폰 전용이라 이게 진짜 하한이다) · 393 · 440 = Pro Max.
        for device in [CGFloat(375), 393, 440] {
            let width = Self.gridWidth(device: device)
            let pitch = ContributionCalendarLayout.pitch(width: width)
            #expect(pitch >= ContributionCalendarLayout.minimumPitch,
                    "전치 캘린더가 44pt 를 못 지킨다 — 여백·틈을 되돌려라 (기기 \(device), 격자 \(width), 피치 \(pitch))")
            // 보이는 칸은 피치에서 틈만 뺀 값이고, 누름 영역은 피치 전체다.
            #expect(abs(ContributionCalendarLayout.cell(width: width) - (pitch - ContributionCalendarLayout.spacing)) < 0.001)
            #expect(ContributionCalendarLayout.rowHeight(width: width) == pitch)
        }
        #expect(abs(ContributionCalendarLayout.pitch(width: 343) - 49) < 0.001, "SE 실측 피치 49.0")
    }

    @Test("탭 좌표는 칸 사이 틈을 앞 칸에 귀속시킨다(죽은 틈도, 한 칸 밀림도 없다)")
    func weekdayFromTapX() {
        let width: CGFloat = 343
        let pitch = ContributionCalendarLayout.pitch(width: width)
        #expect(ContributionCalendarLayout.weekday(atX: 0, width: width) == 0)
        #expect(ContributionCalendarLayout.weekday(atX: pitch - 0.01, width: width) == 0, "칸 뒤 4pt 틈이 죽으면 안 된다")
        #expect(ContributionCalendarLayout.weekday(atX: pitch, width: width) == 1)
        #expect(ContributionCalendarLayout.weekday(atX: 6 * pitch + 1, width: width) == 6)
        #expect(ContributionCalendarLayout.weekday(atX: 7 * pitch, width: width) == nil, "격자 밖")
        #expect(ContributionCalendarLayout.weekday(atX: -1, width: width) == nil, "음수")
        #expect(ContributionCalendarLayout.weekday(atX: 10, width: 0) == nil, "폭 0")
    }

    @Test("하루 이동은 미래로 넘어가지 않고 창 밖에서 멈춘다")
    func steppedStopsAtToday() {
        // dayCount 87 = weekStart 부터 오늘까지 87일 → 마지막 유효 칸 오프셋 86 = (주 12, 요일 2).
        let cell = ContributionCell(week: 12, weekday: 1)
        #expect(MeGrassSelection.stepped(cell, by: 1, weeks: 13, dayCount: 87) == ContributionCell(week: 12, weekday: 2))
        #expect(MeGrassSelection.stepped(cell, by: 2, weeks: 13, dayCount: 87) == nil, "미래 칸을 고르면 막대가 0 을 말한다")
        #expect(MeGrassSelection.stepped(ContributionCell(week: 0, weekday: 0), by: -1, weeks: 13, dayCount: 87) == nil, "창 밖")
        #expect(MeGrassSelection.stepped(ContributionCell(week: 0, weekday: 0), by: 7, weeks: 13, dayCount: 87) == ContributionCell(week: 1, weekday: 0))
        #expect(MeGrassSelection.latest(weeks: 13, dayCount: 87) == ContributionCell(week: 12, weekday: 2))
        #expect(MeGrassSelection.latest(weeks: 13, dayCount: 0) == nil, "기록이 아예 없으면 고를 칸이 없다")
        #expect(MeGrassSelection.latest(weeks: 0, dayCount: 10) == nil)
    }

    @Test("날짜 표기는 맥 ContributionGridView.dateText 와 글자가 같다")
    func detailDateMatchesMac() {
        let weekStart = Self.kst(year: 2026, month: 8, day: 31)
        #expect(MeText.grassDetailDate(weekStart: weekStart, week: 0, weekday: 0) == "8월 31일 (월)")
        #expect(MeText.grassDetailDate(weekStart: weekStart, week: 0, weekday: 3) == "9월 3일 (목)")
        #expect(MeText.grassDetailDate(weekStart: weekStart, week: 1, weekday: 6) == "9월 13일 (일)")
        #expect(MeText.grassWeekAccessibility(weekStart: weekStart, week: 1) == "9월 7일 주")
    }

    @Test("보이스오버 라벨과 값 줄이 실제 값을 말한다(단계·자리표시자로 되돌아가지 않는다)")
    func valueTextSpeaksRealNumbers() {
        let weekStart = Self.kst(year: 2026, month: 8, day: 31)
        #expect(MeText.grassCellAccessibility(weekStart: weekStart, week: 0, weekday: 3,
                                              workSeconds: 15_120, tokens: 12_345_678, showsToken: true)
                == "9월 3일 목요일, 근무 4시간 12분, AI 12,345,678 토큰")
        #expect(MeText.grassCellAccessibility(weekStart: weekStart, week: 0, weekday: 3,
                                              workSeconds: 0, tokens: 0, showsToken: true)
                == "9월 3일 목요일, 근무 없음, 사용 없음", "'근무 근무 없음' 같은 접두어 중복")
        #expect(MeText.grassCellAccessibility(weekStart: weekStart, week: 0, weekday: 3,
                                              workSeconds: 15_120, tokens: 12_345_678, showsToken: false)
                == "9월 3일 목요일, 근무 4시간 12분", "토큰을 안 보는 사람에게 토큰 조각이 샌다")
        #expect(MeText.grassValueLine(workSeconds: 15_120, tokens: 12_345_678, showsToken: true) == "근무 4시간 12분 · AI 12,345,678 토큰")
        #expect(MeText.grassValueLine(workSeconds: 0, tokens: 0, showsToken: true) == "근무 없음 · 사용 없음")
        #expect(MeText.grassValueLine(workSeconds: 15_120, tokens: 12_345_678, showsToken: false) == "근무 4시간 12분")
        // 값 조각은 맥과 같은 코어 함수를 그대로 쓴다(맥 호출부 CheckMenuView.swift:3803·3836 과 같은 함수).
        #expect(MeText.grassValueLine(workSeconds: 15_120, tokens: 0, showsToken: false).hasSuffix(WorkDailyGrid.tooltipValueText(15_120)))
        #expect(MeText.grassValueLine(workSeconds: 0, tokens: 12_345_678, showsToken: true).hasSuffix(TokenDailyGrid.tooltipValueText(12_345_678)))
    }

    @Test("눈금 한 줄은 두 축의 분모를 사람 말로 밝힌다")
    func scaleLineNamesDenominator() {
        #expect(MeText.grassScale(.work) == "가장 진한 칸 = 하루 8시간")
        #expect(MeText.grassScale(.token) == "가장 진한 칸 = 하루 5천만 토큰")
        #expect(WorkDailyGrid.fullDaySeconds == 8 * 3_600)
        #expect(TokenDailyGrid.fullDayTokens == 50_000_000)
    }

    @Test("잔디 창 폭이 코어와 같다")
    func windowWidthMatchesCore() {
        #expect(ContributionGridLayout.defaultWeeks == WorkDailyGrid.defaultWeeks,
                "못 받았을 때와 받았을 때 열 수가 달라 격자가 튄다(.blank() 12열 / 실제 13열)")
        #expect(ContributionGridData.blank().weeks == WorkDailyGrid.defaultWeeks)
        // 13열에서도 잔디 두 벌은 홈 카드에서 나란히 선다(폭 329 → half 156.5 → 칸 9.73 ≥ 8).
        #expect(ContributionGridLayout.pairSideBySide(width: 329, isAccessibilitySize: false))
    }

    @Test("원값이 왕복한다 — 상세 화면이 말할 것을 생성자가 버리지 않는다")
    func gridDataKeepsRawValues() {
        let weekStart = Self.kst(year: 2026, month: 8, day: 31)
        let values = [[3_600, 0, 28_800, 15_120, 60, 0, 0], [7_200, 99, 1, 0, 0, 0, 0]]
        let data = ContributionGridData(weeks: 2, values: values, weekStart: weekStart, denominator: 28_800) { week, weekday in
            week == 1 && weekday >= 2
        }
        #expect(data.weekStart == weekStart, "원점을 잃으면 상세 화면이 '1월 1일'을 말한다")
        #expect(data.value(week: 0, weekday: 0) == 3_600)
        #expect(data.value(week: 0, weekday: 2) == 28_800)
        #expect(data.value(week: 0, weekday: 3) == 15_120)
        #expect(data.value(week: 1, weekday: 1) == 99)
        // 단계만으로는 60초와 7,200초가 같은 1단계다 — 그래서 원값이 남아야 한다.
        #expect(data.level(week: 0, weekday: 4) == data.level(week: 1, weekday: 0))
        #expect(data.value(week: 0, weekday: 4) != data.value(week: 1, weekday: 0))
        // 미래 칸: 단계 nil · 원값 0.
        #expect(data.level(week: 1, weekday: 2) == nil)
        #expect(data.value(week: 1, weekday: 2) == 0)
        // 범위 밖은 0(크래시 없음).
        #expect(data.value(week: 99, weekday: 0) == 0)
        #expect(data.value(week: 0, weekday: 99) == 0)
        #expect(ContributionGridData.blank().value(week: 0, weekday: 0) == 0)
    }

    @Test("달 구간은 과거 → 최신 순이고 주를 빠짐없이 덮는다")
    func monthSectionsCoverEveryWeek() {
        let weekStart = Self.kst(year: 2026, month: 8, day: 31)
        let sections = ContributionCalendarLayout.monthSections(weekStart: weekStart, weeks: 13)
        #expect(!sections.isEmpty)
        #expect(sections.first?.weeks.lowerBound == 0)
        #expect(sections.last?.weeks.upperBound == 13)
        var cursor = 0
        for section in sections {
            #expect(section.weeks.lowerBound == cursor, "주가 빠지거나 겹친다")
            cursor = section.weeks.upperBound
        }
        #expect(cursor == 13)
        // 첫 주(8/31 월 ~ 9/6 일)의 대표 달은 그 주 일요일의 달 = 9월(맥 monthLabels 와 같은 규칙).
        #expect(sections.first?.month == 9)
        #expect(ContributionCalendarLayout.monthSections(weekStart: weekStart, weeks: 0).isEmpty)
    }

    private static func kst(year: Int, month: Int, day: Int) -> Date {
        var c = DateComponents()
        c.year = year
        c.month = month
        c.day = day
        return TeamWeeklyGoal.kstCalendar.date(from: c)!
    }
}
