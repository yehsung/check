import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// 주별 근무 리듬(2026-11-06 대표 결정 #d_V0mJ363LONEW).
// 대표 원문: "근무 리듬이 매주 실시간 쌓이고 있는게 보이게끔 하는식으로 구현하고 지난 기록들 누적 주차별로 볼 수 있게 추가."
// (제보 10-27: "근무 리듬도 토큰사용량/최근12주근무리듬 처럼 하루씩 바로바로 보이면 좋을거같아요 … 지금까지 근무리듬 싹 다 볼 수 있는 누적화면")
// → 기본 이번 주(진행 중 근무까지 1분마다 참) + ◀▶ 로 첫 주까지 넘겨보기. 새 화면 없이 내 기록 칸 안.
// 픽스처는 전부 합성이다(실제 사람 기록 아님).

private func kst(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    var c = DateComponents()
    c.year = year; c.month = month; c.day = day; c.hour = hour; c.minute = minute
    return TeamWeeklyGoal.kstCalendar.date(from: c)!
}

private func s(_ a: Date, _ b: Date) -> WorkInsightsSession { WorkInsightsSession(start: a, end: b) }

// 2026-11-06(금) 15:20 KST — 이번 주 월요일은 11-02.
private let now = kst(2026, 11, 6, 15, 20)

// MARK: - 순수: 주 나누기

@Test
func rhythmWeeksRunFromTheFirstSessionWeekToThisWeek() {
    let sessions = [
        s(kst(2026, 10, 20, 10), kst(2026, 10, 20, 12)),   // 10-19 주(화) 2시간
        s(kst(2026, 11, 3, 9), kst(2026, 11, 3, 10, 30)),   // 이번 주(화) 1시간 30분
    ]
    let weeks = WorkRhythmWeeks.build(parsed: sessions, now: now)
    #expect(weeks.weekStarts.first == kst(2026, 10, 19))
    #expect(weeks.weekStarts.last == kst(2026, 11, 2))
    #expect(weeks.weekStarts.count == 3)                 // 10-19 · 10-26(빈 주도 남는다) · 11-02
    #expect(weeks.maxOffset == 2)
    #expect(weeks.heatmap(offset: 0)?.totalSeconds == 5_400)
    #expect(weeks.heatmap(offset: 1)?.totalSeconds == 0)
    #expect(weeks.heatmap(offset: 2)?.totalSeconds == 7_200)
    #expect(weeks.heatmap(offset: 2)?.buckets[1][10] == 3_600)   // 화 10시 꽉 참
    #expect(weeks.heatmap(offset: 0)?.buckets[1][10] == 1_800)   // 화 10시 반
    #expect(weeks.heatmap(offset: 3) == nil)
    #expect(weeks.weekStart(offset: 1) == kst(2026, 10, 26))
}

@Test
func aSessionAcrossSundayMidnightSplitsIntoTwoWeeks() {
    // 일요일 23:00 ~ 월요일 01:00 — 한 시간씩 두 주에 나뉜다(주 경계에서 통째로 한쪽에 몰리면 리듬이 거짓말한다).
    let weeks = WorkRhythmWeeks.build(parsed: [s(kst(2026, 11, 1, 23), kst(2026, 11, 2, 1))], now: now)
    #expect(weeks.weekStarts == [kst(2026, 10, 26), kst(2026, 11, 2)])
    #expect(weeks.heatmap(offset: 1)?.buckets[6][23] == 3_600)
    #expect(weeks.heatmap(offset: 0)?.buckets[0][0] == 3_600)
    #expect(weeks.heatmap(offset: 0)?.totalSeconds == 3_600)
}

@Test
func withoutSessionsThereIsOnlyThisWeekAndFutureIsNeverCounted() {
    let empty = WorkRhythmWeeks.build(parsed: [], now: now)
    #expect(empty.weekStarts == [kst(2026, 11, 2)])
    #expect(empty.maxOffset == 0)
    #expect(empty.heatmap(offset: 0)?.totalSeconds == 0)
    // now 뒤로 넘어가는 세션(시계가 틀린 행)은 now 까지만 센다.
    let clipped = WorkRhythmWeeks.build(parsed: [s(kst(2026, 11, 6, 15), kst(2026, 11, 6, 18))], now: now)
    #expect(clipped.heatmap(offset: 0)?.totalSeconds == 20 * 60)
}

@Test
func liveWorkFillsThisWeekUpToNowAndNeverOverflowsACell() {
    let base = WorkRhythmWeeks.build(parsed: [s(kst(2026, 11, 6, 9), kst(2026, 11, 6, 9, 30))], now: now)
    let week = try! #require(base.weekStart(offset: 0))
    let map = try! #require(base.heatmap(offset: 0))
    // 진행 중: 오늘 14:00 시작 → 15:20 까지 = 14시 3600 + 15시 1200.
    let live = map.addingLive(from: kst(2026, 11, 6, 14), now: now, weekStart: week)
    #expect(live.buckets[4][14] == 3_600)
    #expect(live.buckets[4][15] == 1_200)
    #expect(live.totalSeconds == 1_800 + 4_800)
    #expect(map.addingLive(from: nil, now: now, weekStart: week) == map)
    // 지난주 칸에는 얹지 않는다(그 주와 겹치지 않는다).
    let lastWeek = try! #require(base.weekStart(offset: 0)).addingTimeInterval(-604_800)
    #expect(WorkRhythmHeatmap.empty.addingLive(from: kst(2026, 11, 6, 14), now: now, weekStart: lastWeek) == .empty)
    // 완료분과 겹친 기록이 있어도 한 칸은 3600초를 넘지 않는다.
    let overlapped = map.addingLive(from: kst(2026, 11, 6, 9), now: kst(2026, 11, 6, 10), weekStart: week)
    #expect(overlapped.buckets[4][9] == 3_600)
}

// MARK: - 순수: 문구 · 미래 칸

@Test
func rhythmTitlesKeepThePeriodInsideTheCaption() {
    #expect(WorkRhythmWeekText.title(offset: 0, weekStart: kst(2026, 11, 2)) == "이번 주 근무 리듬")
    #expect(WorkRhythmWeekText.title(offset: 1, weekStart: kst(2026, 10, 26)) == "지난주 근무 리듬")
    #expect(WorkRhythmWeekText.title(offset: 2, weekStart: kst(2026, 10, 19)) == "10월 19일 주 근무 리듬")
    #expect(WorkRhythmWeekText.caption(.empty, offset: 0) == "이번 주 기록이 아직 없어요")
    #expect(WorkRhythmWeekText.caption(.empty, offset: 3) == "이 주는 기록이 없어요")
    var m = WorkRhythmHeatmap.empty
    m.buckets[1][15] = 3_600; m.buckets[1][16] = 1_800; m.totalSeconds = 5_400
    #expect(WorkRhythmWeekText.caption(m, offset: 0) == "1시간 30분 · 가장 활발한 시간: 화요일 15시")
}

@Test
func futureCellsStartRightAfterTheCurrentHourOnlyThisWeek() {
    let f = try! #require(WorkRhythmWeekText.futureFrom(offset: 0, now: now))
    #expect(f.day == 4 && f.hour == 16)
    #expect(WorkRhythmWeekText.futureFrom(offset: 1, now: now) == nil)
    #expect(!WorkRhythmHeatmapGrid.isFuture(day: 4, hour: 15, from: f))   // 지금 시간 칸은 차는 중
    #expect(WorkRhythmHeatmapGrid.isFuture(day: 4, hour: 16, from: f))
    #expect(WorkRhythmHeatmapGrid.isFuture(day: 5, hour: 0, from: f))
    #expect(!WorkRhythmHeatmapGrid.isFuture(day: 3, hour: 23, from: f))
    #expect(!WorkRhythmHeatmapGrid.isFuture(day: 6, hour: 23, from: nil))
}

// MARK: - 스토어 · 배선

@MainActor
@Test
func rhythmOffsetClampsAndOpeningInsightsGoesBackToThisWeek() {
    let suite = CheckTestScratch.uniqueSuitePath()
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let service = SupabaseWorkService(projectURL: URL(string: "http://v0378-rhythm-offset")!, anonKey: "anon-test-key",
                                      session: URLSession(configuration: .stubbed))
    let store = WorkTimerStore(service: service, environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"], defaults: defaults)
    store.rhythmWeeks = WorkRhythmWeeks.build(parsed: [s(kst(2026, 10, 20, 10), kst(2026, 10, 20, 12))], now: now)
    store.setRhythmWeekOffset(5)
    #expect(store.rhythmWeekOffset == 2)
    store.setRhythmWeekOffset(-3)
    #expect(store.rhythmWeekOffset == 0)
    store.setRhythmWeekOffset(1)
    #expect(store.rhythmWeekOffset == 1)
    store.toggleInsightsPanel()           // 열기 — 이번 주로 돌아간다
    #expect(store.rhythmWeekOffset == 0)
    store.toggleInsightsPanel()
}

@MainActor
@Test
func sessionsAreFetchedFromTheServiceFirstWeekForTheRhythmHistory() throws {
    // 세션 조회만 서비스 첫 주(2026-06-29 00:00 KST)까지 넓힌다 — 토큰 일별 조회는 잔디 창 그대로.
    #expect(WorkTimerStore.rhythmHistoryStart == kst(2026, 6, 29))
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/check/WorkTimerStoreInsights.swift")
    let source = try String(contentsOf: url, encoding: .utf8)
    #expect(source.contains("since: min(since, Self.rhythmHistoryStart)"))
    #expect(source.contains("since: TokenDailyGrid.dayString(since)"))
}

// MARK: - 렌더

/// 대표 지적(2026-11-07): "아직 안다가온 부분 이런식으로 실선으로 표시하지말고 그냥 저 검정색 박스가 좀 더 흐리게 보이게해줘".
/// 안 온 칸 = 지난 빈 칸과 **같은 채운 박스**(테두리 없음)를 더 흐리게. 칸 한가운데가 바탕과 같으면(속이 빈 테두리 — 처음 판) 빨강,
/// 지난 빈 칸과 같으면(안 흐림) 빨강, 칸 가장자리와 한가운데가 다르면(테두리) 빨강.
@MainActor
@Test
func futureCellsAreTheSameFilledBoxOnlyFainter() throws {
    func grid(_ from: (day: Int, hour: Int)?) throws -> NSBitmapImageRep {
        try #require(CheckRenderSettle.bitmap(
            WorkRhythmHeatmapGrid(heatmap: .empty, futureFrom: from).frame(width: 290).background(CheckTheme.panel), scale: 2))
    }
    let past = try grid(nil)      // 모두 지난 빈 칸
    let future = try grid((0, 0)) // 모두 안 온 칸
    #expect(past.pixelsWide == future.pixelsWide && past.pixelsHigh == future.pixelsHigh)
    // 바이트로 직접 읽는다(색 변환 없이 — 같은 렌더러 · 같은 바탕끼리 비교).
    func luma(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int) -> Double {
        guard let data = rep.bitmapData, rep.samplesPerPixel >= 3 else { return -1 }
        let o = y * rep.bytesPerRow + x * rep.samplesPerPixel
        return 0.2126 * Double(data[o]) + 0.7152 * Double(data[o + 1]) + 0.0722 * Double(data[o + 2])
    }
    // 칸 (목, 12시)의 한가운데: 지난 빈 칸 그림에서 세로 · 가로로 바탕보다 어두운 띠를 찾아 잡는다(줄 높이는 요일 글자 높이를 따른다).
    let background = luma(past, 1, 1)
    let x = Int((WorkRhythmHeatmapGrid.labelWidth + WorkRhythmHeatmapGrid.cellGap + 12 * (WorkRhythmHeatmapGrid.cellSize + WorkRhythmHeatmapGrid.cellGap)
                 + WorkRhythmHeatmapGrid.cellSize / 2) * 2)
    var rows: [ClosedRange<Int>] = []
    var runStart: Int?
    for y in 0..<past.pixelsHigh {
        let dark = luma(past, x, y) < background - 3
        if dark, runStart == nil { runStart = y }
        if !dark, let a = runStart { rows.append(a...(y - 1)); runStart = nil }
    }
    #expect(rows.count == 7, "기준선: 지난 빈 칸 그림에서 칸 줄이 \(rows.count)개다(기대 7) — 칸이 바탕과 안 갈린다")
    let row = try #require(rows.count > 3 ? rows[3] : nil)
    let y = (row.lowerBound + row.upperBound) / 2
    let pastCenter = luma(past, x, y)
    let futureCenter = luma(future, x, y)
    let futureEdge = luma(future, x, row.lowerBound + 2)
    print(String(format: "[v0378-rhythm] 바탕 %.1f · 지난 빈 칸 %.1f · 안 온 칸 한가운데 %.1f · 가장자리 %.1f", background, pastCenter, futureCenter, futureEdge))
    #expect(futureCenter < background - 1.5, "안 온 칸 한가운데가 바탕과 같다 — 채운 박스가 아니라 테두리다")
    #expect(futureCenter > pastCenter + 1.5, "안 온 칸이 지난 빈 칸보다 흐리지 않다")
    #expect(abs(futureEdge - futureCenter) < 1.5, "안 온 칸 가장자리가 한가운데와 다르다 — 테두리가 남았다")
    #expect(WorkRhythmHeatmapGrid.futureCellOpacity > 0 && WorkRhythmHeatmapGrid.futureCellOpacity < 1)
}

@MainActor
private func rhythmPanel(_ weeks: WorkRhythmWeeks, offset: Int, live: Date?) -> some View {
    InsightsPanel(
        heatmap: weeks.heatmap(offset: 1) ?? .empty,
        retro: nil,
        dailyGrid: .empty,
        rhythmWeeks: weeks,
        rhythmOffset: offset,
        liveStart: live,
        onRhythmOffset: { _ in },
        rhythmNow: now,
        hasLoaded: true,
        extraChromeHeight: -5000,
        onBack: {}
    )
    .frame(width: 316)
    .fixedSize()
}

@MainActor
@Test
func thisWeekRendersLiveWorkAndWeeksLookDifferent() throws {
    let sessions = [
        s(kst(2026, 10, 27, 10), kst(2026, 10, 27, 18)),   // 지난주 화 10~18
        s(kst(2026, 11, 3, 9), kst(2026, 11, 3, 12)),      // 이번 주 화 9~12
    ]
    let weeks = WorkRhythmWeeks.build(parsed: sessions, now: now)
    func bitmap(_ v: some View) throws -> NSBitmapImageRep { try #require(CheckRenderSettle.bitmap(v, scale: 2)) }
    let thisWeek = try bitmap(rhythmPanel(weeks, offset: 0, live: nil))
    let thisWeekLive = try bitmap(rhythmPanel(weeks, offset: 0, live: kst(2026, 11, 6, 13)))
    let lastWeek = try bitmap(rhythmPanel(weeks, offset: 1, live: kst(2026, 11, 6, 13)))
    // 높이는 주가 바뀌어도 같다(머리 줄 · 칸 · 한 줄 캡션 — 내 기록 본문 높이 예산이 흔들리지 않게).
    #expect(thisWeek.pixelsHigh == lastWeek.pixelsHigh)
    #expect(thisWeek.pixelsHigh == thisWeekLive.pixelsHigh)
    // 진행 중 근무가 칸을 칠한다(실시간).
    #expect(thisWeek.tiffRepresentation != thisWeekLive.tiffRepresentation, "진행 중 근무가 이번 주 칸에 안 얹혔다")
    #expect(thisWeekLive.tiffRepresentation != lastWeek.tiffRepresentation)
    // 육안 확인 그림.
    let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("v0378-rhythm", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try? thisWeekLive.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("this-week-live.png"))
    try? lastWeek.representation(using: .png, properties: [:])?.write(to: dir.appendingPathComponent("last-week.png"))
}
