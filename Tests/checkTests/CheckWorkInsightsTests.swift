import Foundation
import Testing
@testable import check

// 개인 기록(히트맵·주간 회고) 순수 계산 + 토큰 순위 월 네비게이터 고정 검증.
// 전부 KST(TeamWeeklyGoal.kstCalendar) 규약이라 픽스처도 KST 컴포넌트로 만들고, 서버가 준 문자열을 파싱하는
// 실제 경로를 그대로 태우려 세션 행은 ISO8601 문자열로 넣는다(계산이 파서와 함께 맞는지까지 본다).

// MARK: - 픽스처 헬퍼

/// KST 벽시계 컴포넌트로 Date 를 만든다.
private func kst(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute
    return TeamWeeklyGoal.kstCalendar.date(from: components)!
}

private func isoText(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.string(from: date)
}

/// 완료 세션 행 픽스처. endedAt 이 nil 이면 진행 중 세션(집계 제외 대상)이다.
private func sessionRow(_ start: Date, _ end: Date?, id: String = UUID().uuidString) -> WorkSessionRow {
    WorkSessionRow(
        id: id,
        userId: "00000000-0000-0000-0000-000000000002",
        startedAt: isoText(start),
        endedAt: end.map(isoText),
        durationSeconds: end.map { Int($0.timeIntervalSince(start)) }
    )
}

// 기준 시각: 2026-07-22(수) 12:00 KST. 이 주의 시작은 2026-07-20(월), 8주 창 시작은 2026-06-01(월)이다.
private let insightsNow = kst(2026, 7, 22, 12)

// MARK: - 히트맵

@Test
func heatmapSplitsSessionAcrossHourAndMidnightBoundaries() {
    // 화 23:30 → 수 01:10 (총 6000초). 한 칸에 몰지 않고 화23시 1800 / 수0시 3600 / 수1시 600 으로 쪼개져야 한다.
    let sessions = [sessionRow(kst(2026, 7, 21, 23, 30), kst(2026, 7, 22, 1, 10))]

    let map = WorkRhythmHeatmap.build(sessions: sessions, now: insightsNow)

    #expect(map.buckets[1][23] == 1_800)   // 화요일 23시
    #expect(map.buckets[2][0] == 3_600)    // 수요일 0시
    #expect(map.buckets[2][1] == 600)      // 수요일 1시
    #expect(map.totalSeconds == 6_000)
    #expect(map.maxBucketSeconds == 3_600)
    if let peak = map.peakSlot {
        #expect(peak.day == 2)
        #expect(peak.hour == 0)
    } else {
        Issue.record("가장 진한 칸이 있어야 한다")
    }
}

@Test
func heatmapUsesMondayZeroWeekdayIndex() {
    // 월요일(2026-07-20) 09시 1시간, 일요일(2026-07-19) 09시 1시간 → 0번과 6번 칸에 각각 들어가야 한다.
    let sessions = [
        sessionRow(kst(2026, 7, 20, 9), kst(2026, 7, 20, 10)),
        sessionRow(kst(2026, 7, 19, 9), kst(2026, 7, 19, 10))
    ]

    let map = WorkRhythmHeatmap.build(sessions: sessions, now: insightsNow)

    #expect(map.buckets[0][9] == 3_600)
    #expect(map.buckets[6][9] == 3_600)
    #expect(map.totalSeconds == 7_200)
}

@Test
func heatmapDropsSessionsOutsideWindowAndClipsCrossingOnes() {
    // 8주 창 시작 = 2026-06-01(월) 00:00. 그 이전에 끝난 세션은 통째로 버리고,
    // 창 시작에 걸친 세션은 창 안쪽 구간만 남긴다(05-31 23:00~06-01 01:00 → 월 0시 3600 만).
    let sessions = [
        sessionRow(kst(2026, 5, 20, 9), kst(2026, 5, 20, 18)),          // 창 밖 — 전부 제외
        sessionRow(kst(2026, 5, 31, 23), kst(2026, 6, 1, 1))            // 창 경계 걸침 — 뒤쪽 1시간만
    ]

    let map = WorkRhythmHeatmap.build(sessions: sessions, now: insightsNow)

    #expect(map.totalSeconds == 3_600)
    #expect(map.buckets[0][0] == 3_600)   // 2026-06-01 은 월요일 00시
    #expect(map.buckets[6][23] == 0)      // 창 밖(일요일 23시)은 들어오지 않는다
}

@Test
func heatmapClipsFutureTailAtNowAndIgnoresOpenSessions() {
    // now(수 12:00) 이후 구간은 세지 않고, 진행 중(ended_at 없음) 세션은 통째로 무시한다.
    let sessions = [
        sessionRow(kst(2026, 7, 22, 11), kst(2026, 7, 22, 13)),
        sessionRow(kst(2026, 7, 22, 8), nil)
    ]

    let map = WorkRhythmHeatmap.build(sessions: sessions, now: insightsNow)

    #expect(map.totalSeconds == 3_600)
    #expect(map.buckets[2][11] == 3_600)
    #expect(map.buckets[2][12] == 0)
    #expect(map.buckets[2][8] == 0)
}

@Test
func heatmapWithNoSessionsStillReportsWindowWeeks() {
    let map = WorkRhythmHeatmap.build(sessions: [], now: insightsNow, weeks: 8)

    #expect(map.totalSeconds == 0)
    #expect(map.maxBucketSeconds == 0)
    #expect(map.peakSlot == nil)
    #expect(map.weeks == 8)
    #expect(map.buckets.count == WorkRhythmHeatmap.dayCount)
    #expect(map.buckets.allSatisfy { $0.count == WorkRhythmHeatmap.hourCount })
}

@Test
func heatmapParsesFractionalSecondTimestamps() {
    // PostgREST 는 마이크로초 소수초를 붙여 내려주기도 한다 — 파싱 실패로 세션이 통째로 사라지면 안 된다.
    let row = WorkSessionRow(
        id: "s1",
        userId: "u1",
        startedAt: "2026-07-22T00:00:00.123456+00:00",
        endedAt: "2026-07-22T01:00:00.654321+00:00",
        durationSeconds: 3_600
    )

    let map = WorkRhythmHeatmap.build(sessions: [row], now: insightsNow)

    // 00:00 UTC = 09:00 KST(수요일).
    #expect(map.buckets[2][9] == 3_600)
    #expect(map.totalSeconds == 3_600)
}

// MARK: - 지난주 회고

@Test
func retroClipsSessionsToLastWeekAndCountsPreviousWeek() {
    // 대상 주 = 2026-07-13(월) ~ 2026-07-20(월) 직전. 앞뒤 경계에 걸친 세션은 겹치는 구간만 귀속한다.
    let sessions = [
        sessionRow(kst(2026, 7, 12, 22), kst(2026, 7, 13, 2)),    // 앞 경계: 지난주 몫 2h, 그 전 주 몫 2h
        sessionRow(kst(2026, 7, 15, 9), kst(2026, 7, 15, 18)),    // 수요일 9h
        sessionRow(kst(2026, 7, 19, 22), kst(2026, 7, 20, 2))     // 뒤 경계: 지난주 몫 2h(이번 주 몫은 제외)
    ]

    let retro = WeeklyRetro.build(sessions: sessions, now: insightsNow, goalSeconds: 40 * 3_600)

    #expect(retro?.weekStart == kst(2026, 7, 13))
    #expect(retro?.totalSeconds == 7_200 + 32_400 + 7_200)
    #expect(retro?.sessionCount == 3)
    #expect(retro?.previousWeekSeconds == 7_200)
    #expect(retro?.busiestDayIndex == 2)          // 수요일
    #expect(retro?.busiestDaySeconds == 32_400)
    #expect(retro?.deltaSeconds == 46_800 - 7_200)
    #expect(retro?.metGoal == false)
}

@Test
func retroBreaksBusiestDayTieTowardEarlierWeekday() {
    // 월요일과 수요일이 똑같이 1시간 → 앞선 요일(월=0)이 이겨야 한다.
    let sessions = [
        sessionRow(kst(2026, 7, 15, 9), kst(2026, 7, 15, 10)),
        sessionRow(kst(2026, 7, 13, 9), kst(2026, 7, 13, 10))
    ]

    let retro = WeeklyRetro.build(sessions: sessions, now: insightsNow, goalSeconds: 3_600)

    #expect(retro?.busiestDayIndex == 0)
    #expect(retro?.busiestDaySeconds == 3_600)
    #expect(retro?.totalSeconds == 7_200)
    #expect(retro?.metGoal == true)
}

@Test
func retroIsNilWhenLastWeekHasNoWork() {
    // 그 전 주에만 근무가 있으면 보여줄 회고가 없다.
    let sessions = [sessionRow(kst(2026, 7, 8, 9), kst(2026, 7, 8, 18))]

    #expect(WeeklyRetro.build(sessions: sessions, now: insightsNow, goalSeconds: 40 * 3_600) == nil)
}

@Test
func retroIgnoresOpenSessionsAndReportsNegativeDelta() {
    // 지난주 2시간 vs 그 전 주 5시간 → 증감은 음수. 진행 중 세션은 어느 쪽에도 들어가지 않는다.
    let sessions = [
        sessionRow(kst(2026, 7, 14, 9), kst(2026, 7, 14, 11)),
        sessionRow(kst(2026, 7, 7, 9), kst(2026, 7, 7, 14)),
        sessionRow(kst(2026, 7, 16, 9), nil)
    ]

    let retro = WeeklyRetro.build(sessions: sessions, now: insightsNow, goalSeconds: 40 * 3_600)

    #expect(retro?.totalSeconds == 7_200)
    #expect(retro?.previousWeekSeconds == 18_000)
    #expect(retro?.deltaSeconds == -10_800)
    #expect(retro?.sessionCount == 1)
}

// MARK: - 파싱 1회 공유 · 메인액터 밖 계산

@Test
func insightsParseSessionsRunsOncePerRowAndKeepsBothCalculationsIdentical() {
    // 회귀 지점: 히트맵과 회고가 각각 원본 행을 훑으며 startedAt/endedAt 을 파싱해 **행당 ISO8601 파싱이 4회**
    // 일어났고, 그 비용이 전체의 98%였다(2000행 = 서버 limit 상한에서 두 계산 합계 178ms). 이제 파싱은
    // parseSessions 가 행당 2회만 하고 두 계산이 그 결과를 나눠 쓴다 — 결과는 예전과 한 칸도 달라지면 안 된다.
    let rows = [
        sessionRow(kst(2026, 7, 15, 9), kst(2026, 7, 15, 18)),   // 지난주 완료
        sessionRow(kst(2026, 6, 3, 9), kst(2026, 6, 3, 12)),     // 8주 창 안이지만 회고 창 밖
        sessionRow(kst(2026, 7, 16, 9), nil),                    // 진행 중 → 두 계산 모두 제외
        sessionRow(kst(2026, 7, 14, 10), kst(2026, 7, 14, 10)),  // 길이 0 → 어느 칸에도 안 들어간다
        WorkSessionRow(id: "bad", userId: "u1", startedAt: "not-a-date",
                       endedAt: "2026-07-15T00:00:00Z", durationSeconds: 1),
        WorkSessionRow(id: "frac", userId: "u1", startedAt: "2026-07-14T00:00:00.123456+00:00",
                       endedAt: "2026-07-14T02:00:00.654321+00:00", durationSeconds: 7_200)
    ]

    // 파싱 결과에는 '두 계산 모두 쓸 수 있는' 완료 세션만 남는다(진행 중·길이 0·파싱 실패 제거).
    let parsed = WorkInsightsDate.parseSessions(rows)
    #expect(parsed.count == 3)
    #expect(parsed.allSatisfy { $0.end > $0.start })
    #expect(parsed.contains(WorkInsightsSession(start: kst(2026, 7, 15, 9), end: kst(2026, 7, 15, 18))))

    // 파싱본 경로와 원본 행 경로가 완전히 같은 값을 낸다.
    #expect(WorkRhythmHeatmap.build(parsed: parsed, now: insightsNow, weeks: 8)
        == WorkRhythmHeatmap.build(sessions: rows, now: insightsNow, weeks: 8))
    #expect(WeeklyRetro.build(parsed: parsed, now: insightsNow, goalSeconds: 40 * 3_600)
        == WeeklyRetro.build(sessions: rows, now: insightsNow, goalSeconds: 40 * 3_600))

    // 묶음 계산도 같은 답을 낸다(스토어가 실제로 부르는 경로).
    let computed = WorkInsightsComputation.build(rows: rows, now: insightsNow, weeks: 8, goalSeconds: 40 * 3_600)
    #expect(computed.heatmap == WorkRhythmHeatmap.build(sessions: rows, now: insightsNow, weeks: 8))
    #expect(computed.retro == WeeklyRetro.build(sessions: rows, now: insightsNow, goalSeconds: 40 * 3_600))
    // 소수초 세션(7/14 09:00~11:00 KST)이 회고 최다 요일에 온전히 반영됐는지 — 파싱 경로 공유 후에도 유실 없음.
    #expect(computed.retro?.totalSeconds == 9 * 3_600 + 2 * 3_600)
}

// MARK: - 진행 중 세션(첫 근무가 아직 안 끝난 신규 사용자)

@Test
func insightsCountTheSessionThatIsStillRunningSoTheFirstDayPanelIsNotEmpty() {
    // 회귀 지점: 서버 조회는 완료 세션(ended_at not null)만 준다. 그래서 완료 세션이 0건인 계정
    // (=가입 첫날, 첫 [근무 종료] 전)에서는 heatmap.totalSeconds 가 0이 되어 '내 기록' 패널이
    // "아직 기록이 쌓이지 않았어요"라고 단정했는데, 같은 팝오버 헤더 캡션은 진행 중 세션 기여를 더한
    // 이번 주 누적("3시간 00분 / 40시간")을 세고 있었다 — 한 화면 두 문장이 서로를 반박했다.
    // 이제 진행 중 세션의 시작 시각을 넘기면 '지금까지'만 잘라 함께 집계한다.
    let ongoingStart = kst(2026, 7, 22, 9)   // 수 09:00 KST 출근, insightsNow(수 12:00)까지 근무 중

    let computed = WorkInsightsComputation.build(
        rows: [],
        now: insightsNow,
        weeks: 8,
        goalSeconds: 40 * 3_600,
        ongoingStart: ongoingStart
    )

    #expect(computed.heatmap.totalSeconds == 3 * 3_600)
    // 수요일(2) 09·10·11시 칸에 한 시간씩 — 한 칸에 몰리지 않고 시간 경계로 쪼개진다.
    #expect(computed.heatmap.buckets[2][9] == 3_600)
    #expect(computed.heatmap.buckets[2][10] == 3_600)
    #expect(computed.heatmap.buckets[2][11] == 3_600)
    // now 이후는 세지 않는다(미래 칸 0).
    #expect(computed.heatmap.buckets[2][12] == 0)
    // 지난주 회고는 이번 주 진행 세션에 영향을 받지 않는다(대상 주가 다르다).
    #expect(computed.retro == nil)
    // 패널이 더 이상 "기록 없음"으로 단정하지 않는다 — 헤더 캡션과 같은 사실을 말한다.
    #expect(InsightsEmptyMessage.text(hasLoaded: true, totalSeconds: computed.heatmap.totalSeconds) == nil)

    // 같은 시점 헤더 값과 자릿수가 맞는지: 진행 세션만 있는 계정의 라이브 주간 누적도 3시간이다.
    let mine = TeamMemberStatus(
        id: "00000000-0000-0000-0000-000000000002",
        name: "나",
        status: .working,
        updatedAt: insightsNow,
        currentSessionStartedAt: ongoingStart,
        weeklyDurationSeconds: 0,
        todayDurationSeconds: 0,
        lastSeenAt: insightsNow
    )
    #expect(mine.liveWeeklyDurationSeconds(now: insightsNow) == computed.heatmap.totalSeconds)
}

@Test
func insightsIgnoreOngoingStartThatIsNotInTheFutureOrAlreadyCoveredByCompletedRows() {
    // (a) ongoingStart 가 없으면 예전과 완전히 동일한 결과(하위호환 — 근무 중이 아닌 사용자).
    let rows = [sessionRow(kst(2026, 7, 21, 9), kst(2026, 7, 21, 12))]
    let base = WorkInsightsComputation.build(rows: rows, now: insightsNow, weeks: 8, goalSeconds: 40 * 3_600)
    #expect(base.heatmap.totalSeconds == 3 * 3_600)

    // (b) 시작이 now 이후(시계 되돌림 등)면 아무것도 더하지 않는다 — 음수/미래 칸 오염 금지.
    let future = WorkInsightsComputation.build(
        rows: rows, now: insightsNow, weeks: 8, goalSeconds: 40 * 3_600,
        ongoingStart: insightsNow.addingTimeInterval(600)
    )
    #expect(future.heatmap == base.heatmap)

    // (c) 진행 세션이 주 경계를 넘겨 지난주에 걸쳐 있으면 그 몫만 회고에 들어간다(완료 세션과 같은 클리핑 규약).
    let acrossWeeks = WorkInsightsComputation.build(
        rows: [], now: insightsNow, weeks: 8, goalSeconds: 40 * 3_600,
        ongoingStart: kst(2026, 7, 19, 22)   // 지난주 일요일 22:00 시작 → 지난주 몫 2시간
    )
    #expect(acrossWeeks.retro?.totalSeconds == 2 * 3_600)
    #expect(acrossWeeks.retro?.busiestDayIndex == 6)   // 일요일
}

@Test
func retroSkipsSessionsOutsideItsTwoWeekWindowWithoutChangingTotals() {
    // 회고는 '지난주 + 그 전주' 2주만 쓰는데도 8주치 전 행을 하루 경계로 쪼개고 있었다. 이제 창 밖 행은
    // 먼저 걸러 내는데, 경계에 **걸친** 행까지 잘려 나가면 합이 줄어든다 — 그 경계를 고정한다.
    // 그 전주 시작 = 2026-07-06(월) 00:00, 이번 주 시작 = 2026-07-20(월) 00:00.
    let sessions = [
        sessionRow(kst(2026, 7, 5, 20), kst(2026, 7, 6, 0)),      // 그 전주 시작에 '맞닿기만' 함 → 제외
        sessionRow(kst(2026, 7, 5, 22), kst(2026, 7, 6, 2)),      // 경계에 걸침 → 그 전주 몫 2h 만
        sessionRow(kst(2026, 7, 20, 0), kst(2026, 7, 20, 3)),     // 이번 주 → 제외
        sessionRow(kst(2026, 7, 14, 9), kst(2026, 7, 14, 13)),    // 지난주 4h
        sessionRow(kst(2026, 6, 10, 9), kst(2026, 6, 10, 18))     // 8주 창 안이지만 회고 창 밖 → 제외
    ]

    let retro = WeeklyRetro.build(sessions: sessions, now: insightsNow, goalSeconds: 40 * 3_600)

    #expect(retro?.totalSeconds == 4 * 3_600)
    #expect(retro?.sessionCount == 1)
    #expect(retro?.previousWeekSeconds == 2 * 3_600)
}

@Test
func insightsComputationRunsOffTheMainActor() async {
    // 회귀 지점: 이 계산이 메인액터에 묶여 있으면(@MainActor 로 되돌아가면) 응답 도착 순간 UI 가 통째로 멈춘다
    // — 2000행에서 90ms 이상, 예전 4회 파싱 시절엔 350ms 였다. 아래 Task.detached 호출은 계산이 메인액터에
    // 격리돼 있지 않을 때만 컴파일된다(입출력 타입이 Sendable 이어야 하는 것도 함께 고정된다).
    let rows = (0..<200).map { index -> WorkSessionRow in
        let start = kst(2026, 7, 14, 1).addingTimeInterval(Double(index) * 600)
        return sessionRow(start, start.addingTimeInterval(300))
    }
    let onMain = WorkInsightsComputation.build(rows: rows, now: insightsNow, weeks: 8, goalSeconds: 40 * 3_600)

    let offMain = await Task.detached { () -> (WorkInsightsComputation, Bool) in
        (WorkInsightsComputation.build(rows: rows, now: insightsNow, weeks: 8, goalSeconds: 40 * 3_600),
         pthread_main_np() != 0)
    }.value

    #expect(offMain.1 == false)          // 실제로 메인스레드 밖에서 돌았다.
    #expect(offMain.0 == onMain)         // 어디서 돌든 답은 같다(순수 계산 — now 는 인자로 받는다).
}

@Test
func insightsLoadDoesNotCalculateInlineOnTheMainActor() throws {
    // 위 테스트는 "계산을 메인액터 밖에서 돌릴 수 있다"까지만 고정한다. 정작 회귀는 스토어가 그 계산을
    // 응답 직후 메인액터에서 **그대로 부르는 것**이었으므로(팝오버 열 때마다 수십~수백 ms 정지),
    // 로딩 경로가 계산을 떼어 냈는지 소스에서 확인한다.
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // checkTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // repo root
    let source = try String(
        contentsOf: root.appendingPathComponent("Sources/check/WorkTimerStoreInsights.swift"),
        encoding: .utf8
    )

    #expect(source.contains("Task.detached"))
    #expect(source.contains("WorkInsightsComputation.build(rows: rows"))
    // 메인액터에서 직접 집계를 돌리던 두 호출은 남아 있으면 안 된다.
    #expect(!source.contains("WorkRhythmHeatmap.build("))
    #expect(!source.contains("WeeklyRetro.build("))
}

// MARK: - 주 키 / 월 네비게이터

@Test
func retroWeekKeyUsesKoreanMondayDate() {
    // 2026-07-22(수)가 속한 주의 월요일은 2026-07-20.
    #expect(RetroWeekKey.current(insightsNow) == "2026-07-20")
    // 일요일도 같은 주로 묶인다(월요일 시작 규약).
    #expect(RetroWeekKey.current(kst(2026, 7, 26, 23)) == "2026-07-20")
}

@Test
func tokenBoardMonthNavigatorClampsToCurrentMonth() {
    #expect(TokenBoardMonthNavigator.step("2026-07", by: -1, now: insightsNow) == "2026-06")
    #expect(TokenBoardMonthNavigator.step("2026-01", by: -1, now: insightsNow) == "2025-12")
    // 미래로는 못 간다 — 현재 월로 클램프.
    #expect(TokenBoardMonthNavigator.step("2026-07", by: 1, now: insightsNow) == "2026-07")
    #expect(TokenBoardMonthNavigator.step("2026-06", by: 5, now: insightsNow) == "2026-07")
    // 과거에서 +1 은 정상 이동.
    #expect(TokenBoardMonthNavigator.step("2026-05", by: 1, now: insightsNow) == "2026-06")
}

@Test
func tokenBoardMonthNavigatorGatesForwardStepAndFormatsTitle() {
    #expect(TokenBoardMonthNavigator.canStepForward(from: "2026-06", now: insightsNow))
    #expect(!TokenBoardMonthNavigator.canStepForward(from: "2026-07", now: insightsNow))

    #expect(TokenBoardMonthNavigator.displayTitle("2026-07", now: insightsNow) == "7월")
    #expect(TokenBoardMonthNavigator.displayTitle("2026-01", now: insightsNow) == "1월")
    #expect(TokenBoardMonthNavigator.displayTitle("2025-12", now: insightsNow) == "2025년 12월")
}
