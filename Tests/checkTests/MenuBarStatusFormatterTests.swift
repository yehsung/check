import Testing
@testable import check

@Test
func workingShowsDotAndElapsedTime() {
    let snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 84)

    // v0.2.43: 제목은 항상 시:분이다(84초 → "00:01"). 종전 "01:24"(MM:SS)는 팝오버 안 duration(_:) 에만 남는다.
    #expect(MenuBarStatusFormatter.title(for: snapshot) == "00:01")
    #expect(MenuBarStatusFormatter.titleDuration(84) == "00:01")
    #expect(MenuBarStatusFormatter.titleDuration(3_661) == "01:01")
    #expect(MenuBarStatusFormatter.duration(84) == "01:24")
    #expect(MenuBarStatusFormatter.symbolName(for: snapshot) == "figure.run.circle.fill")
}

@Test
func offWorkShowsEndedLabel() {
    let snapshot = WorkStatusSnapshot(status: .offWork, elapsedSeconds: 0)

    #expect(MenuBarStatusFormatter.title(for: snapshot) == "오프")
    #expect(MenuBarStatusFormatter.symbolName(for: snapshot) == "pause.circle.fill")
}

@Test
func workStatusLocalizesForTeamRows() {
    #expect(WorkStatus.working.localizedStatus == "근무중")
    #expect(WorkStatus.offWork.localizedStatus == "근무종료")
}

@Test
func pendingSyncShowsWaitingLabel() {
    let snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 84, pendingSync: true)

    #expect(MenuBarStatusFormatter.title(for: snapshot) == "대기")
    #expect(MenuBarStatusFormatter.symbolName(for: snapshot) == "exclamationmark.icloud.fill")
}

@Test
func hoursMinutesShowsKoreanHourSummary() {
    #expect(MenuBarStatusFormatter.hoursMinutes(7_260) == "2시간 01분")
}

@Test
func teamWeeklyGoalTracksSixtyHourTarget() {
    let goal = TeamWeeklyGoal(workedSeconds: 30 * 60 * 60)

    #expect(goal.goalSeconds == 60 * 60 * 60)
    #expect(goal.progress == 0.5)
    #expect(!goal.isComplete)
    #expect(goal.remainingSeconds == 30 * 60 * 60)
}

@Test
func teamWeeklyGoalCompletesAtSixtyHours() {
    let goal = TeamWeeklyGoal(workedSeconds: 61 * 60 * 60)

    #expect(goal.progress == 1)
    #expect(goal.isComplete)
    #expect(goal.remainingSeconds == 0)
}
