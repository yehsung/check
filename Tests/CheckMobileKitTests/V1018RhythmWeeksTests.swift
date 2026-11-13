@testable import CheckCore
import Foundation
import Testing
@testable import CheckMobileKit

// 폰 1.0.18 — 근무 리듬을 주별로(대표 결정 #d_V0mJ363LONEW "근무 리듬이 매주 실시간 쌓이고 있는게 보이게끔 … 지난 기록들 누적 주차별로").
// 맥 0.3.78 과 같은 코어(WorkRhythmWeeks · WorkRhythmWeekText). 폰은 세션 조회만 서비스 첫 주부터 받는다.
@Suite("폰 1.0.18 — 주별 근무 리듬")
struct V1018RhythmWeeksTests {
    @Test("첫 주 = 맥과 같은 날(2026-06-29 00:00 KST) · ◀▶ 글자")
    func constants() throws {
        let c = TeamWeeklyGoal.kstCalendar.dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: MeText.rhythmHistoryStart)
        #expect(c.year == 2026 && c.month == 6 && c.day == 29 && c.hour == 0 && c.minute == 0 && c.weekday == 2, "\(c)")
        let mac = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/check/WorkTimerStoreInsights.swift"), encoding: .utf8)
        #expect(mac.contains("static let rhythmHistoryStart = Date(timeIntervalSince1970: 1_782_658_800)"), "맥 첫 주 값이 바뀌었다")
        #expect(MeText.rhythmPreviousWeek == "이전 주" && MeText.rhythmNextWeek == "다음 주")
    }

    @Test("배선: 세션 조회는 첫 주부터 · 주별 값을 옮기고 범위 밖 주는 붙인다 · 화면은 주별이 있으면 ◀▶ — 주석을 걷고 본다")
    @MainActor
    func wiring() throws {
        let records = try IntegrationContractTests.code("Sources/CheckMobileKit/Me/MeStoreRecords.swift").filter { !$0.isWhitespace }
        #expect(records.contains("since:min(since,MeText.rhythmHistoryStart)"))
        #expect(records.contains("rhythmWeeks=output.insights.rhythmWeeks"))
        #expect(records.contains("ifrhythmWeekOffset>rhythmWeeks.maxOffset{rhythmWeekOffset=rhythmWeeks.maxOffset}"))
        let views = try IntegrationContractTests.code("Sources/CheckMobileKit/Me/MeRecordsViews.swift").filter { !$0.isWhitespace }
        #expect(views.contains("WorkRhythmWeekText.title(offset:offset,weekStart:weekStart)"))
        #expect(views.contains("store.setRhythmWeekOffset(offset+1)") && views.contains("store.setRhythmWeekOffset(offset-1)"))
        #expect(views.contains("addingLive(from:store.rhythmLiveStart,now:timeline.date"))
        #expect(views.contains("futureFrom:WorkRhythmWeekText.futureFrom(offset:offset,now:timeline.date)"))
    }

    @Test("주 넘기기: 범위 안으로 붙는다 · 0 아래 · 마지막 위로 안 간다")
    @MainActor
    func offsetClamps() async {
        let harness = await RankMeHarness(label: "v1018-rhythm") { _ in nil }
        defer { harness.tearDown() }
        let store = harness.me
        store.setRhythmWeekOffset(3)
        #expect(store.rhythmWeekOffset == 0, "주별 자료가 없으면 0 에 머문다")
        store.setRhythmWeekOffset(-1)
        #expect(store.rhythmWeekOffset == 0)
    }
}
