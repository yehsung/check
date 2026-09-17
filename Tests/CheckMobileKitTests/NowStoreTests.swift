@testable import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit
@testable import CheckWidgetsKit

/// 지금 탭 스토어 시나리오(SPEC-ios §3.2 · §4 스냅샷): 읽기 · 세대 가드 · 실패 · 주간 목표 · 할 일 · background · 계정 전환 · 금지 호출 0.
@MainActor
@Suite(.serialized) struct NowStoreTests {
    nonisolated static let now = MobileClock.demoInstant

    // MARK: - 읽기

    @Test("읽기: 내 카드(오늘 5:10:00 · 이번 주 24.8시간 62%) · 근무 중(우리 팀 오래 일한 순 → 다른 팀 이름순, 나·비근무 제외) · 위젯 스냅샷 · 금지 호출 0")
    func readFlow() async throws {
        let h = NowHarness()
        defer { h.tearDown() }
        await h.launch()
        await h.activate()

        #expect(h.store.membership == NowMembership(teamID: NowStubServer.teamID, teamName: "지금팀", goalHours: 40, role: "member"))
        let card = try #require(h.store.myCard(now: Self.now))
        #expect(card.isWorking && !card.isStale)
        #expect(card.sessionStartedAt == ISO8601DateFormatter().date(from: "2026-09-17T01:20:00Z"))
        #expect(card.todaySeconds == 18_600)
        #expect(card.weekSeconds == 89_280)
        #expect(card.weekLine == "이번 주 24.8시간 · 목표 40시간 · 62%")
        #expect(NowFormat.clock(card.todaySeconds) == "5:10:00")

        // 1초마다 폰이 센다(서버 세션 시작 시각 기준)
        let later = try #require(h.store.myCard(now: Self.now.addingTimeInterval(61)))
        #expect(later.todaySeconds == 18_661 && later.weekSeconds == 89_341)

        let people = h.store.workingPeople(now: Self.now)
        #expect(people.map(\.id) == [NowStubServer.mint, NowStubServer.bori, NowStubServer.lime, NowStubServer.morae, NowStubServer.coral, NowStubServer.haneul])
        #expect(people.prefix(3).allSatisfy(\.isTeammate) && people.dropFirst(3).allSatisfy { !$0.isTeammate })
        try #require(people.count >= 3, "근무 중 목록이 비면 아래 인덱스 읽기가 프로세스를 죽인다")
        #expect(people[0].elapsedSeconds == 15_000 && people[0].center == "seoul")
        #expect(people[1].isStale && people[1].elapsedSeconds == 10_320, "끊긴 신호는 마지막 신호에서 멈춘다")
        #expect(people[2].avatarURL?.absoluteString == "https://x.invalid/lime.jpg")
        #expect(people.dropFirst(3).allSatisfy { $0.elapsedSeconds == nil && $0.startedAt == nil }, "다른 팀은 시간이 없다")
        #expect(people[3].avatarURL?.absoluteString == "https://x.invalid/morae.jpg")

        let snapshot = try #require(h.model.widgetSnapshots.current)
        #expect(snapshot.me == WidgetSnapshot.Me(working: true, sessionStartedAt: card.sessionStartedAt, todaySeconds: 18_600, weekSeconds: 89_280, goalHours: 40))
        #expect(snapshot.working.map(\.name) == ["민트", "보리", "라임", "모래", "코랄", "하늘"])
        #expect(snapshot.working.map(\.teammate) == [true, true, true, false, false, false])
        #expect(snapshot.working.dropFirst(3).allSatisfy { $0.startedAt == nil })
        let onDisk = try #require(WidgetSnapshotCodec.read(from: h.storage.widgetSnapshotURL))
        #expect(onDisk.working == snapshot.working, "파일에도 같은 값")

        #expect(h.store.notice == nil)
        #expect(h.requests("work_statuses").allSatisfy { $0.method == "GET" })
        #expect(h.requests.filter { $0.path.contains("work_") }.allSatisfy { $0.method == "GET" }, "근무 표는 읽기만")
        #expect(!h.requests.contains { $0.path.contains("take_pokes") || $0.path.contains("work_tick") })
        #expect(h.violations.isEmpty, "\(h.violations)")
    }

    @Test("우리 팀 상태를 아직 못 받았으면 다른 팀을 가르지 않는다 — 우리 팀원이 시간 없이 '다른 팀'에 섞이지 않게")
    func othersWaitForTeam() async {
        let h = NowHarness()
        defer { h.tearDown() }
        h.server.override("work_statuses", .networkFailure())
        await h.launch()
        await h.activate()
        #expect(h.store.hasLoadedDirectory && !h.store.hasLoadedTeam)
        #expect(h.store.workingPeople(now: Self.now).isEmpty)
        #expect(h.store.notice == NowText.networkFailed)
        #expect(h.store.myCard(now: Self.now) == nil)
        #expect(h.model.widgetSnapshots.current?.working.isEmpty ?? true, "모르는 칸은 스냅샷에 쓰지 않는다")
    }

    @Test("소속 없음: 카드 대신 안내, 다른 팀 근무자는 보이고, 스냅샷 me 는 '소속 없음'(목표 0) — 위젯은 팀 참여 안내를 그린다")
    func noTeam() async throws {
        let h = NowHarness()
        defer { h.tearDown() }
        h.server.override("memberships", .json("[]"))
        await h.launch()
        await h.activate()
        #expect(h.store.hasNoTeam && h.store.membership == nil)
        #expect(h.store.myCard(now: Self.now) == nil)
        #expect(h.requests("work_statuses").isEmpty, "팀이 없으면 팀 상태를 부르지 않는다")
        let people = h.store.workingPeople(now: Self.now)
        #expect(people.count == 6 && people.allSatisfy { !$0.isTeammate })
        #expect(h.store.teamLoadState == .loaded && h.store.workingLoadState == .loaded)
        let snapshot = try #require(WidgetSnapshotCodec.read(from: h.storage.widgetSnapshotURL))
        #expect(snapshot.me == NowStore.widgetNoTeamMe)
        #expect(AingWidgetMyTodayState(snapshot: snapshot, at: Self.now) == .noTeam, "앱을 열어도 채워지지 않는 '앱을 열면 채워져요'를 그렸다")
    }

    // MARK: - 수리(now-fix) 회귀

    @Test("끊김 판정은 받은 시각에: 5분 background 뒤 active — 응답을 기다리는 동안 내 카드가 '연결 끊김'으로 뒤집히거나 오늘 누적이 뒤로 가지 않고, 위젯 스냅샷은 응답 뒤에만 쓴다")
    func presenceHeldAcrossForeground() async throws {
        let h = NowHarness()
        defer { h.tearDown() }
        await h.launch()
        await h.activate()
        let before = try #require(h.store.myCard(now: h.clock.now))
        #expect(!before.isStale && before.todaySeconds == 18_600)
        let snapshotBefore = try #require(h.model.widgetSnapshots.current)
        #expect(snapshotBefore.me?.sessionStartedAt != nil)

        h.store.appDidEnterBackground()
        await h.settle()
        h.clock.advance(300) // 폰만 5분 잠겼다(맥은 계속 근무 · 30초 하트비트)
        h.server.override("work_statuses", MobileStubResponse(
            status: 200, body: Data(NowHarness.statuses(meSeen: "2026-09-17T05:09:50Z").utf8), delay: 0.4
        ))
        h.store.appDidBecomeActive()

        // 응답 전: 받은 시각(05:05:00)의 판정을 유지하고 now 까지 센다.
        #expect(h.store.refreshTask != nil)
        let during = try #require(h.store.myCard(now: h.clock.now))
        #expect(!during.isStale, "응답을 기다리는 동안 멀쩡한 맥이 '연결 끊김'으로 뒤집혔다")
        #expect(during.todaySeconds == 18_900, "오늘 누적이 마지막 신호 지점으로 뒤로 뛰었다(\(during.todaySeconds))")
        let people = h.store.workingPeople(now: h.clock.now)
        #expect(people.first { $0.id == NowStubServer.mint }?.isStale == false)
        #expect(people.first { $0.id == NowStubServer.mint }?.elapsedSeconds == 15_300, "민트 경과(00:55 → 05:10)가 마지막 신호에서 멈췄다")
        #expect(people.first { $0.id == NowStubServer.bori }?.isStale == true, "받을 때 이미 끊겼던 사람은 그대로 멈춘다")
        #expect(h.model.widgetSnapshots.current == snapshotBefore, "응답 전 추정(몇 분 전 판정)으로 위젯 스냅샷을 썼다")

        await h.settle()
        let after = try #require(h.store.myCard(now: h.clock.now))
        #expect(!after.isStale && after.todaySeconds == 18_900)
        let snapshot = try #require(h.model.widgetSnapshots.current)
        #expect(snapshot.generatedAt == h.clock.now)
        #expect(snapshot.me?.sessionStartedAt == ISO8601DateFormatter().date(from: "2026-09-17T01:20:00Z") && snapshot.me?.todaySeconds == 18_900)
        #expect(h.violations.isEmpty)
    }

    @Test("끊김 판정은 받은 시각에: 받을 때 29초 묵은 신호면 60초 뒤 다음 응답 전까지도 끊김이 아니다 · 다음 응답이 90초 넘게 끊긴 신호를 싣고 오면 그때 멈추고 위젯도 세지 않는다")
    func presenceHeldBetweenRefreshes() async throws {
        let h = NowHarness()
        defer { h.tearDown() }
        h.server.override("work_statuses", .json(NowHarness.statuses(meSeen: "2026-09-17T05:04:31Z")))
        await h.launch()
        await h.activate()
        #expect(h.store.myCard(now: h.clock.now)?.isStale == false)

        // 60초 주기 새로고침이 떠났다. 그사이 맥이 멈췄다 — 다음 응답은 90초 넘게 끊긴 신호(05:04:20)를 싣고 온다.
        h.server.override("work_statuses", .json(NowHarness.statuses(meSeen: "2026-09-17T05:04:20Z")))
        h.clock.advance(60)
        h.scheduler.advance(60)
        #expect(h.store.refreshTask != nil)
        for step in 1...4 {
            h.clock.advance(0.5)
            let card = try #require(h.store.myCard(now: h.clock.now))
            #expect(!card.isStale, "응답 전 t+\(60 + Double(step) * 0.5)초에 끊김으로 뒤집혔다")
            #expect(card.todaySeconds == 18_660 + step / 2, "오늘 누적이 뒤로 뛰었다(\(card.todaySeconds))")
        }

        await h.settle()
        let card = try #require(h.store.myCard(now: h.clock.now))
        #expect(card.isStale, "다음 응답의 신호가 90초 넘게 끊겼는데 계속 셌다")
        #expect(card.todaySeconds == 5_100 + 13_460, "마지막 신호(05:04:20)에서 멈춘다")
        let me = try #require(h.model.widgetSnapshots.current?.me)
        #expect(me.working && me.sessionStartedAt == nil, "끊긴 세션은 위젯이 스스로 세지 않게 시작 시각을 싣지 않는다")
        #expect(me.todaySeconds == 18_560)
    }

    @Test("팀 상태 요청이 실패하면 모르는 채로 살려 두지 않는다: 끊김은 화면 시각으로(마지막 신호에서 멈춤) · 다시 받으면 풀린다")
    func presenceFallsBackToNowAfterFailure() async throws {
        let h = NowHarness()
        defer { h.tearDown() }
        await h.launch()
        await h.activate()
        h.clock.advance(120)
        h.server.override("work_statuses", .networkFailure())
        await h.store.refreshNow()
        #expect(h.store.teamStatusFailedSinceFetch)
        #expect(h.store.presenceJudgedAt(now: h.clock.now) == h.clock.now)
        let card = try #require(h.store.myCard(now: h.clock.now))
        #expect(card.isStale && card.todaySeconds == 5_100 + 13_480, "나: 마지막 신호 05:04:40 에서 멈춘다")
        #expect(h.model.widgetSnapshots.current?.me?.sessionStartedAt == nil)

        h.server.override("work_statuses", .json(NowHarness.statuses(meSeen: "2026-09-17T05:06:50Z")))
        await h.store.refreshNow()
        #expect(!h.store.teamStatusFailedSinceFetch)
        let fresh = try #require(h.store.myCard(now: h.clock.now))
        #expect(!fresh.isStale && fresh.todaySeconds == 5_100 + 13_620, "05:07:00 까지 다시 센다")
    }

    @Test("오프라인 첫 화면: 새로고침이 끝나면 '불러오는 중'에 머물지 않고 '불러오지 못함'(머리글 숫자 숨김) · 다시 시도 중에도 깜빡이지 않고 · 받으면 채워진다")
    func offlineColdStartIsNotLoadingForever() async throws {
        let h = NowHarness()
        defer { h.tearDown() }
        let keys = ["memberships", "rpc.app_user_directory", "work_statuses"]
        for key in keys { h.server.override(key, .networkFailure()) }
        await h.launch()
        #expect(h.store.teamLoadState == .loading && h.store.workingLoadState == .loading, "시도 전은 불러오는 중")
        await h.activate()
        #expect(h.store.notice == NowText.networkFailed)
        #expect(!h.store.isRefreshing && h.store.refreshTask == nil, "도는 요청이 없다")
        #expect(h.store.teamLoadState == .failed, "도는 요청이 없는데 내 카드 자리가 '불러오는 중'이다")
        #expect(h.store.workingLoadState == .failed)
        #expect(NowText.workingTitle(count: nil) == "지금 근무 중", "모를 때 '지금 근무 중 0' 이라고 하지 않는다")

        for key in keys { h.server.override(key, nil) }
        h.store.refresh()
        #expect(h.store.teamLoadState == .failed, "다시 시도하는 동안 실패 줄 ↔ 스피너로 깜빡인다")
        await h.settle()
        #expect(h.store.teamLoadState == .loaded && h.store.workingLoadState == .loaded)
        #expect(h.store.myCard(now: h.clock.now) != nil && h.store.notice == nil)

        h.store.reset()
        #expect(h.store.teamLoadState == .loading, "세대가 바뀌면 처음부터")
    }

    @Test("소속 없음인데 디렉터리를 못 받으면 '근무 중인 사람이 없어요'가 아니라 불러오지 못함")
    func noTeamWithoutDirectoryIsUnknown() async {
        let h = NowHarness()
        defer { h.tearDown() }
        h.server.override("memberships", .json("[]"))
        h.server.override("rpc.app_user_directory", .json(#"{"message":"boom"}"#, status: 503))
        await h.launch()
        await h.activate()
        #expect(h.store.teamLoadState == .loaded, "내 카드 자리는 소속 없음 안내")
        #expect(h.store.workingLoadState == .failed)
        #expect(h.store.notice == NowText.loadFailed)
    }

    @Test("값이 같은 새로고침도 위젯 'N분 전'을 방금으로: 세지 않는 스냅샷은 generatedAt 만 옮기고 위젯을 새로고침한다 · 60초 안이거나 실패면 그대로")
    func idleSnapshotIsTouchedAfterRefresh() async throws {
        let h = NowHarness()
        defer { h.tearDown() }
        h.server.override("work_statuses", .json(NowHarness.idleStatuses))
        await h.launch()
        await h.activate()
        let first = try #require(WidgetSnapshotCodec.read(from: h.storage.widgetSnapshotURL))
        #expect(first.generatedAt == Self.now && first.me?.working == false)

        h.clock.advance(30)
        var reloads = h.widgetReloadCount
        await h.store.refreshNow()
        #expect(WidgetSnapshotCodec.read(from: h.storage.widgetSnapshotURL)?.generatedAt == first.generatedAt, "60초 안이면 옮기지 않는다")
        #expect(h.widgetReloadCount == reloads)

        h.clock.advance(20 * 60)
        reloads = h.widgetReloadCount
        await h.store.refreshNow()
        let refreshedAt = try #require(h.store.lastRefreshedAt)
        let touched = try #require(WidgetSnapshotCodec.read(from: h.storage.widgetSnapshotURL))
        #expect(touched.generatedAt == refreshedAt, "방금 새로고침했는데 위젯은 '\(AingWidgetFormat.ago(from: touched.generatedAt, now: refreshedAt))'")
        #expect(AingWidgetFormat.ago(from: touched.generatedAt, now: refreshedAt) == "방금")
        #expect(touched.me == first.me && touched.working == first.working && touched.todosPreview == first.todosPreview, "시각만 옮긴다")
        #expect(h.widgetReloadCount == reloads + 1, "옮긴 뒤 위젯을 한 번 새로고침한다")

        h.clock.advance(10 * 60)
        h.server.override("work_statuses", .networkFailure())
        await h.store.refreshNow()
        #expect(WidgetSnapshotCodec.read(from: h.storage.widgetSnapshotURL)?.generatedAt == touched.generatedAt, "실패한 새로고침은 방금이라고 하지 않는다")
    }

    @Test("앞 실행이 남긴 스냅샷: 우리 팀 상태를 못 받은 첫 새로고침은 근무 중 · 내 칸을 비우지 않는다(모르는 칸은 쓰지 않는다)")
    func unknownTeamKeepsPreviousSnapshot() async throws {
        let seed = WidgetSnapshot(
            generatedAt: Self.now.addingTimeInterval(-600),
            me: .init(working: true, sessionStartedAt: Self.now.addingTimeInterval(-3_600), todaySeconds: 3_000, weekSeconds: 9_000, goalHours: 40),
            working: [
                .init(name: "민트", center: "seoul", teammate: true, startedAt: Self.now.addingTimeInterval(-7_200)),
                .init(name: "코랄", center: "busan", teammate: false, startedAt: nil),
            ]
        )
        let h = NowHarness(seedSnapshot: seed)
        defer { h.tearDown() }
        h.server.override("work_statuses", .networkFailure())
        await h.launch()
        await h.activate()
        #expect(h.store.hasLoadedDirectory && !h.store.hasLoadedTeam)
        let snapshot = try #require(WidgetSnapshotCodec.read(from: h.storage.widgetSnapshotURL))
        #expect(snapshot.working == seed.working, "모르는 근무 중 칸을 빈 목록으로 덮었다")
        #expect(snapshot.me == seed.me)
    }

    @Test("팀이 있다가 소속 없음으로 바뀌면 옛 팀원을 비운다 — 다른 팀 근무자만 남고 위젯 '내 오늘'은 팀 참여 안내")
    func teamToNoTeamClearsTeammates() async throws {
        let h = NowHarness()
        defer { h.tearDown() }
        await h.launch()
        await h.activate()
        #expect(h.store.workingPeople(now: Self.now).filter(\.isTeammate).count == 3)
        #expect(AingWidgetMyTodayState(snapshot: try #require(h.model.widgetSnapshots.current), at: Self.now) != .noTeam)

        h.server.override("memberships", .json("[]"))
        await h.store.refreshNow()
        #expect(h.store.hasNoTeam && h.store.teamMembers.isEmpty && !h.store.hasLoadedTeam)
        let people = h.store.workingPeople(now: Self.now)
        #expect(people.count == 6 && people.allSatisfy { !$0.isTeammate && $0.elapsedSeconds == nil }, "옛 팀원이 '우리 팀'으로 남았다")
        let snapshot = try #require(h.model.widgetSnapshots.current)
        #expect(snapshot.working.allSatisfy { !$0.teammate })
        #expect(AingWidgetMyTodayState(snapshot: snapshot, at: Self.now) == .noTeam)

        // 다시 팀에 들어왔는데 팀 상태는 아직 못 받았다 — "팀에 참여하면 보여요"를 남기지 않는다(모름).
        h.server.override("memberships", nil)
        h.server.override("work_statuses", .networkFailure())
        await h.store.refreshNow()
        #expect(h.store.membership != nil && !h.store.hasLoadedTeam)
        let rejoined = try #require(h.model.widgetSnapshots.current)
        #expect(AingWidgetMyTodayState(snapshot: rejoined, at: Self.now) == .noData, "팀에 들어왔는데 위젯은 여전히 팀 참여 안내")
        h.server.override("work_statuses", nil)
        await h.store.refreshNow()
        guard case .me = AingWidgetMyTodayState(snapshot: try #require(h.model.widgetSnapshots.current), at: Self.now) else {
            Issue.record("팀 상태를 받았는데 위젯 내 오늘이 채워지지 않았다")
            return
        }
    }

    @Test("목표 저장 응답이 로그아웃 뒤에 오면 버린다: 시트를 닫지 않고(false) 새 계정의 목표를 바꾸지 않는다")
    func lateGoalSaveAfterAccountSwitchIsDropped() async throws {
        let h = NowHarness()
        defer { h.tearDown() }
        await h.launch()
        await h.activate()
        h.server.override("rpc.set_team_weekly_goal", .json(#"[{"weekly_goal_hours":45}]"#, delay: 0.8))
        let save = Task { await h.store.saveGoal(hours: 45) }
        _ = await baseWaitUntil { h.requests("rpc.set_team_weekly_goal").count == 1 }

        await h.model.session.signOut()
        h.store.reset()
        h.server.override("memberships", .json(#"[{"team_id":"team-other","role":"member","teams":{"name":"다른팀","weekly_goal_hours":30}}]"#))
        await h.signIn(as: "u-other")
        #expect(h.model.session.userID == "u-other")
        h.store.appDidBecomeActive()
        await h.settle()
        #expect(h.store.membership?.teamID == "team-other" && h.store.goalHours == 30)

        #expect(await save.value == false, "앞 계정 저장 응답에 시트를 닫았다")
        #expect(h.store.goalHours == 30, "앞 계정의 늦은 저장 응답이 새 계정 목표를 바꿨다")
        #expect(h.model.widgetSnapshots.current?.me?.goalHours != 45)
    }

    @Test("새로고침은 한 번에 하나: 도는 중에 여러 번 불러도 겹치지 않고 끝난 뒤 한 번만 더 돈다")
    func refreshIsSingleFlight() async {
        let h = NowHarness(runsPeriodicRefresh: false)
        defer { h.tearDown() }
        await h.launch()
        // 디렉터리는 지금 탭만 부른다(멤버십은 세션의 프로필 조회도 부른다).
        h.server.override("rpc.app_user_directory", .json(NowStubServer.directory, delay: 0.3))
        h.store.refresh()
        _ = await baseWaitUntil { h.requests("rpc.app_user_directory").count == 1 }
        // 첫 새로고침이 도는 중에 두 번 더 — 겹치지 않고, 끝난 뒤 한 번으로 합쳐 돈다.
        h.store.refresh()
        h.store.refresh()
        #expect(h.store.refreshCount == 1)
        await h.store.refreshTask?.value
        try? await Task.sleep(for: .milliseconds(500))
        #expect(h.store.refreshCount == 2, "겹친 새로고침 \(h.store.refreshCount)번")
        #expect(h.requests("rpc.app_user_directory").count == 2)
    }

    @Test("탭을 다시 볼 때 30초 안에 받았으면 새로고침을 건너뛰고, 그보다 오래됐으면 한 번 받는다")
    func tabAppearSkipsFreshData() async {
        let h = NowHarness(runsPeriodicRefresh: false)
        defer { h.tearDown() }
        await h.launch()
        await h.activate()
        let count = h.store.refreshCount
        h.clock.advance(29)
        h.store.tabDidAppear()
        await h.settle()
        #expect(h.store.refreshCount == count, "30초 안에 받은 값을 다시 받았다")
        h.clock.advance(2)
        h.store.tabDidAppear()
        await h.settle()
        #expect(h.store.refreshCount == count + 1)
    }

    @Test("60초 주기는 조립이 켤 때만(runsPeriodicRefresh) — 끈 조립은 시간이 흘러도 스스로 새로고침하지 않는다")
    func periodicRefreshNeedsOptIn() async {
        let h = NowHarness(runsPeriodicRefresh: false)
        defer { h.tearDown() }
        await h.launch()
        await h.activate()
        let count = h.store.refreshCount
        h.scheduler.advance(180)
        await h.settle()
        #expect(h.store.refreshCount == count)
    }

    @Test("할 일 미리보기는 지금 계정 파일일 때만: 로그인 직후 active 전(로그아웃 파일을 든 채)에는 스냅샷에 싣지 않는다")
    func todoPreviewNeedsCurrentAccountFile() async {
        let h = NowHarness()
        defer { h.tearDown() }
        await h.launch()
        await h.activate()
        await h.model.session.signOut()
        h.store.reset()
        _ = h.store.todos.add("로그아웃 파일의 줄") // todos.local.json
        await h.signIn(as: "u-other")
        #expect(h.store.todoSync.userID == nil && h.model.session.isSignedIn)
        h.store.writeWidgetSnapshot()
        #expect(!(h.model.widgetSnapshots.current?.todosPreview.contains { $0.title == "로그아웃 파일의 줄" } ?? false), "로그아웃 파일의 할 일이 새 계정 위젯에 샜다")
    }

    @Test("background 로 가면 되돌리기 토스트를 닫는다(삭제는 파일에 남는다)")
    func backgroundClosesUndoWindow() async throws {
        let h = NowHarness()
        defer { h.tearDown() }
        await h.launch()
        await h.activate()
        #expect(h.store.addTodo("지울 일"))
        let item = try #require(h.store.todos.items.first)
        h.store.deleteTodo(item.id)
        #expect(h.store.undoTodoID == item.id)
        h.store.appDidEnterBackground()
        #expect(h.store.undoTodoID == nil, "돌아왔을 때 몇 시간 지난 되돌리기 토스트가 남는다")
        #expect(h.store.todoRows().main.isEmpty)
    }

    @Test("할 일 전송: 응답을 기다리는 사이 로그아웃했다가 같은 계정으로 다시 들어와도(세대가 바뀜) 앞 세대 응답은 버린다")
    func transportDropsResponseAcrossGenerations() async throws {
        let h = NowHarness()
        defer { h.tearDown() }
        await h.launch()
        let transport = NowTodoSyncTransport(context: h.model.context)
        h.server.todo.delay = 0.8
        let call = Task { try await transport.todoSync(userID: NowStubServer.me, request: TodoSyncRequest(changes: [], sinceMs: nil)) }
        _ = await baseWaitUntil { h.server.todo.calls == 1 }
        await h.model.session.signOut()
        h.server.todo.delay = 0
        await h.signIn(as: NowStubServer.me)
        #expect(h.model.session.userID == NowStubServer.me)
        await #expect(throws: TodoSyncTransportError.accountMismatch) {
            _ = try await call.value
        }
    }

    // MARK: - 세대 가드 · 실패

    @Test("세대 가드: 느린 팀 상태 응답이 로그아웃 뒤에 도착하면 버린다 · 로그아웃 뒤 목록 변화가 스냅샷 파일을 다시 만들지 않는다")
    func lateResponseAfterSignOutIsDropped() async {
        let h = NowHarness()
        defer { h.tearDown() }
        await h.launch()
        h.server.override("work_statuses", MobileStubResponse(status: 200, body: Data(NowStubServer.statuses.utf8), delay: 0.6))
        h.store.appDidBecomeActive()
        #expect(h.store.addTodo("로그아웃 전 할 일"), "reset 이 목록을 비우며 스냅샷 쓰기를 깨우게 한 줄 둔다")
        _ = await baseWaitUntil { h.requests("work_statuses").count == 1 }
        await h.model.session.signOut()
        h.store.reset()
        await h.store.refreshTask?.value
        try? await Task.sleep(for: .milliseconds(100))
        #expect(h.store.todos.items.isEmpty)
        #expect(h.store.teamMembers.isEmpty && h.store.teamFetchedAt == nil)
        #expect(h.store.membership == nil && h.store.directory.isEmpty)
        #expect(h.store.myCard(now: Self.now) == nil)
        #expect(WidgetSnapshotCodec.read(from: h.storage.widgetSnapshotURL) == nil, "로그아웃 뒤 스냅샷을 다시 쓰면 위젯이 앞 계정을 그린다")
        #expect(!h.store.canEditTodos)
    }

    @Test("실패: 네트워크 오류는 안내 한 줄, 받아 둔 값은 그대로 · 디렉터리 함수가 없는 서버는 조용히 빈 목록")
    func failuresKeepData() async {
        let h = NowHarness()
        defer { h.tearDown() }
        h.server.override("rpc.app_user_directory", .missingFunction("app_user_directory"))
        await h.launch()
        await h.activate()
        #expect(h.store.notice == nil, "함수 없는 서버는 안내 없이 접는다")
        #expect(h.store.workingPeople(now: Self.now).map(\.id) == [NowStubServer.mint, NowStubServer.bori, NowStubServer.lime])

        h.server.override("work_statuses", .networkFailure())
        await h.store.refreshNow()
        #expect(h.store.notice == NowText.networkFailed)
        #expect(h.store.teamMembers.count == 5, "실패가 받아 둔 팀 상태를 지우지 않는다")

        h.server.override("work_statuses", .json(#"{"message":"boom"}"#, status: 500))
        await h.store.refreshNow()
        #expect(h.store.notice == NowText.loadFailed)

        h.server.override("work_statuses", nil)
        await h.store.refreshNow()
        #expect(h.store.notice == nil)
    }

    // MARK: - 주간 목표

    @Test("주간 목표: 1~168 밖은 요청 없이 거절 · 저장하면 목표·스냅샷 반영 · 저장 전에 떠난 조회가 옛 목표로 되돌리지 못한다")
    func weeklyGoal() async throws {
        let h = NowHarness()
        defer { h.tearDown() }
        await h.launch()
        await h.activate()

        #expect(await h.store.saveGoal(hours: 0) == false)
        #expect(await h.store.saveGoal(hours: 169) == false)
        #expect(h.requests("rpc.set_team_weekly_goal").isEmpty)

        // 옛 목표(40)를 싣고 늦게 오는 멤버십 조회를 먼저 띄운다.
        h.server.override("memberships", MobileStubResponse(
            status: 200,
            body: Data(#"[{"team_id":"team-now","role":"member","teams":{"name":"지금팀","weekly_goal_hours":40}}]"#.utf8),
            delay: 0.5
        ))
        let membershipCalls = h.requests("memberships").count
        h.store.refresh()
        _ = await baseWaitUntil { h.requests("memberships").count > membershipCalls }
        #expect(await h.store.saveGoal(hours: 45))
        let saveBody = try #require(h.requests("rpc.set_team_weekly_goal").last?.bodyText)
        #expect(saveBody.contains("45"))
        #expect(h.store.goalHours == 45)
        await h.store.refreshTask?.value
        #expect(h.store.goalHours == 45, "저장 전에 떠난 조회가 목표를 40 으로 되돌렸다")
        #expect(h.store.myCard(now: Self.now)?.weekLine == "이번 주 24.8시간 · 목표 45시간 · 55%")
        #expect(h.model.widgetSnapshots.current?.me?.goalHours == 45)

        h.server.override("rpc.set_team_weekly_goal", .json(#"{"message":"boom"}"#, status: 500))
        #expect(await h.store.saveGoal(hours: 50) == false)
        #expect(h.store.goalNotice == NowText.goalFailed)
        h.server.override("rpc.set_team_weekly_goal", .networkFailure())
        #expect(await h.store.saveGoal(hours: 50) == false)
        #expect(h.store.goalNotice == MobileSessionText.network)
        #expect(h.store.goalHours == 45, "실패는 목표를 바꾸지 않는다")
        #expect(h.violations.isEmpty)
    }

    // MARK: - 할 일

    @Test("할 일: 추가·체크·수정·삭제(되돌리기 5초)가 App Group 파일에 남고, 1.5초 디바운스 뒤 todo_sync 로 올라가 pending 이 빈다 · 스냅샷 미리보기")
    func todoEditsSync() async throws {
        let h = NowHarness()
        defer { h.tearDown() }
        await h.launch()
        await h.activate()
        let fileURL = h.storage.todoFileURL(userID: NowStubServer.me)
        #expect(h.store.todos.fileURL == fileURL)
        #expect(h.store.canEditTodos)
        let firstSyncs = h.server.todo.calls
        #expect(firstSyncs == 1, "active 진입에 한 번 맞춘다")

        #expect(h.store.addTodo("  회고   쓰기 "))
        #expect(!h.store.addTodo("   "), "빈 제목은 거절")
        #expect(!h.store.addTodo(String(repeating: "가", count: 101)), "100자 초과는 잘라 넣지 않고 거절")
        let item = try #require(h.store.todos.items.first)
        #expect(item.title == "회고 쓰기")
        h.store.toggleTodo(item.id)
        #expect(h.store.todos.pendingIDs.contains(item.id))
        let file = try TodoFileStore.load(from: fileURL)
        #expect(file.items.first?.completedAt != nil && file.sync.pendingIDs.contains(item.id), "변경은 곧바로 파일에")

        #expect(h.server.todo.calls == firstSyncs, "디바운스 전에는 보내지 않는다")
        h.scheduler.advance(1.5)
        await h.settle()
        #expect(h.server.todo.calls == firstSyncs + 1)
        #expect(h.server.todo.changeIDs == [item.id.uuidString.lowercased()])
        #expect(h.store.todos.pendingIDs.isEmpty)

        _ = await baseWaitUntil { h.model.widgetSnapshots.current?.todosPreview.first?.isCompleted == true }
        let preview = try #require(h.model.widgetSnapshots.current?.todosPreview.first)
        #expect(preview.id == item.id.uuidString.lowercased() && preview.title == "회고 쓰기" && preview.isCompleted)

        // 수정
        h.store.beginEditing(item.id)
        #expect(h.store.editingTodoID == item.id)
        h.store.commitEditing(item.id, title: "주간 회고 쓰기")
        #expect(h.store.editingTodoID == nil && h.store.todos.items.first?.title == "주간 회고 쓰기")

        // 삭제 → 5초 되돌리기
        h.store.deleteTodo(item.id)
        #expect(h.store.undoTodoID == item.id)
        #expect(h.store.todoRows().main.isEmpty, "지운 줄은 곧바로 목록에서 빠진다")
        h.store.undoDelete()
        #expect(h.store.undoTodoID == nil)
        #expect(h.store.todoRows().main.map(\.id) == [item.id])
        h.store.deleteTodo(item.id)
        h.scheduler.advance(4.9)
        #expect(h.store.undoTodoID == item.id)
        h.scheduler.advance(0.2)
        #expect(h.store.undoTodoID == nil, "5초 뒤 토스트가 닫힌다")
        await h.settle()
        #expect(h.server.todo.row(item.id.uuidString)?["deleted_at_ms"] is NSNumber, "삭제 톰스톤이 서버에 올라갔다")
        #expect(h.violations.isEmpty)
    }

    @Test("할 일 보호: 고치는 줄은 다른 기기의 변경이 와도 덮이지 않고, 끝나면 다시 맞춘다")
    func editingIsProtected() async throws {
        let h = NowHarness()
        defer { h.tearDown() }
        await h.launch()
        await h.activate()
        #expect(h.store.addTodo("원래 제목"))
        h.scheduler.advance(1.5)
        await h.settle()
        let item = try #require(h.store.todos.items.first)

        // 다른 기기가 제목을 바꿨다(서버 행이 더 새롭다).
        var remote = try #require(h.server.todo.row(item.id.uuidString))
        remote["title"] = "다른 기기 제목"
        remote["updated_at_ms"] = NSNumber(value: item.updatedAtMs + 10_000)
        h.server.todo.seed(remote)

        h.store.beginEditing(item.id)
        h.store.todoSync.requestSync(.periodic)
        await h.settle()
        #expect(h.store.todos.items.first?.title == "원래 제목", "편집 중인 줄을 덮었다")
        #expect(h.store.todos.pendingIDs.contains(item.id))
        h.store.cancelEditing()
        h.scheduler.advance(1.5)
        await h.settle()
        #expect(h.store.todos.items.first?.title == "다른 기기 제목", "보호가 끝나면 서버 값으로 수렴")
    }

    // MARK: - background · active

    @Test("background: 미룬 변경은 곧바로 한 번 보내고, 주기(60초 새로고침 · 5분 동기화)는 멈춘다 · active 로 오면 다시")
    func backgroundPausesTimers() async {
        let h = NowHarness()
        defer { h.tearDown() }
        await h.launch()
        await h.activate()
        let refreshes = h.store.refreshCount
        h.scheduler.advance(60)
        await h.settle()
        #expect(h.store.refreshCount == refreshes + 1, "active 동안은 60초마다 새로고침")

        #expect(h.store.addTodo("잠그기 직전"))
        let syncs = h.server.todo.calls
        h.store.appDidEnterBackground()
        await h.settle()
        #expect(h.server.todo.calls == syncs + 1, "background 직전의 변경은 1.5초를 기다리지 않고 보낸다")
        #expect(h.store.todos.pendingIDs.isEmpty)

        let pausedRefreshes = h.store.refreshCount
        let pausedSyncs = h.server.todo.calls
        h.scheduler.advance(900)
        await h.settle()
        #expect(h.store.refreshCount == pausedRefreshes, "background 에서 새로고침이 돌았다")
        #expect(h.server.todo.calls == pausedSyncs, "background 에서 주기 동기화가 돌았다")

        h.store.appDidBecomeActive()
        await h.settle()
        #expect(h.store.refreshCount == pausedRefreshes + 1)
        #expect(h.server.todo.calls == pausedSyncs + 1)
        h.scheduler.advance(300)
        await h.settle()
        #expect(h.server.todo.calls >= pausedSyncs + 2, "active 로 돌아오면 5분 주기가 다시 걸린다")
        #expect(h.violations.isEmpty)
    }

    @Test("위젯이 뒤에서 체크한 파일을 active 진입 때 다시 읽는다(앱 메모리의 옛 목록으로 덮지 않는다)")
    func activeReloadsWidgetChanges() async throws {
        let h = NowHarness()
        defer { h.tearDown() }
        await h.launch()
        await h.activate()
        #expect(h.store.addTodo("위젯에서 체크할 일"))
        h.scheduler.advance(1.5)
        await h.settle()
        let item = try #require(h.store.todos.items.first)
        h.store.appDidEnterBackground()
        await h.settle()

        // 위젯 인텐트(다른 프로세스 흉내): 토큰은 60초 안에 만료 → 파일만 고친다.
        h.clock.advance(3_560)
        let shared = WidgetSharedData(storage: h.storage, vault: h.vault, now: { h.clock.now })
        let outcome = await WidgetTodoToggle.run(todoID: item.id.uuidString, shared: shared, now: { h.clock.now }) { _, _ in
            Issue.record("토큰이 곧 만료되는데 위젯이 보냈다")
            return TodoSyncResponse(status: "ok")
        }
        #expect(outcome == .savedLocally(.tokenUnusable))
        #expect(h.store.todos.items.first?.isDone == false, "아직 앱 메모리는 옛 값")

        h.store.appDidBecomeActive()
        #expect(h.store.todos.items.first?.isDone == true, "active 진입에 파일을 다시 읽었다")
        #expect(h.store.todos.pendingIDs.contains(item.id))
        await h.settle()
        #expect(h.server.todo.row(item.id.uuidString)?["completed_at_ms"] is NSNumber, "위젯 체크가 앱 동기화로 올라갔다")
    }

    @Test("계정 전환: 로그아웃하면 할 일 동기화가 멈추고 목록을 비우며, 다른 계정으로 들어오면 그 계정 파일로 바꾼다 · 앞 계정 늦은 응답은 버린다")
    func accountSwitch() async throws {
        let h = NowHarness()
        defer { h.tearDown() }
        await h.launch()
        await h.activate()
        #expect(h.store.addTodo("앞 계정 할 일"))
        h.server.todo.delay = 0.6
        h.store.todoSync.requestSync(.periodic)
        _ = await baseWaitUntil { h.server.todo.calls >= 2 }

        await h.model.session.signOut()
        h.store.reset()
        #expect(h.store.todos.items.isEmpty, "앞 계정 목록이 메모리에 남았다")
        #expect(!h.store.canEditTodos && !h.store.addTodo("로그아웃 중"))
        #expect(h.store.todoSync.userID == nil)
        await h.store.todoSync.runTask?.value
        #expect(h.store.todos.items.isEmpty, "앞 계정의 늦은 응답이 들어왔다")
        let firstFile = try TodoFileStore.load(from: h.storage.todoFileURL(userID: NowStubServer.me))
        #expect(firstFile.items.map(\.title) == ["앞 계정 할 일"], "로그아웃은 파일을 지우지 않는다")

        h.server.todo.delay = 0
        h.vault.write(BaseStub.jwt(exp: h.clock.now.addingTimeInterval(3600), subject: "u-other"), key: AingKeychain.accessTokenKey)
        h.storage.defaults.set("u-other", forKey: AingSharedKeys.userID)
        h.server.override("auth.token", BaseStub.authResponse(access: BaseStub.jwt(exp: h.clock.now.addingTimeInterval(3600), subject: "u-other"), refresh: "r2", userID: "u-other"))
        await h.model.session.signIn(email: "o@x.invalid", password: "pw")
        #expect(h.model.session.userID == "u-other")
        h.store.appDidBecomeActive()
        await h.settle()
        #expect(h.store.todos.fileURL == h.storage.todoFileURL(userID: "u-other"))
        #expect(h.store.todoSync.userID == "u-other")
        #expect(h.violations.isEmpty)
    }

    @Test("할 일 전송: 요청 계정이 지금 세션이 아니면 보내지 않는다 · 200 unauthorized 는 세션 갱신 1회 뒤 재시도 · 함수 없는 서버는 functionMissing")
    func transportGuards() async throws {
        let h = NowHarness()
        defer { h.tearDown() }
        await h.launch()
        let transport = NowTodoSyncTransport(context: h.model.context)
        let request = TodoSyncRequest(changes: [], sinceMs: nil)

        await #expect(throws: TodoSyncTransportError.accountMismatch) {
            _ = try await transport.todoSync(userID: "u-someone-else", request: request)
        }
        #expect(h.server.todo.calls == 0, "다른 계정 요청을 지금 세션 토큰으로 보냈다")

        _ = try await transport.todoSync(userID: NowStubServer.me, request: request)
        #expect(h.server.todo.calls == 1)

        // 200 {"status":"unauthorized"} → 조정자 경유 갱신 → 새 토큰으로 한 번 더.
        let fresh = BaseStub.jwt(exp: h.clock.now.addingTimeInterval(7200), subject: NowStubServer.me, salt: "fresh")
        h.server.override("auth.token", BaseStub.authResponse(access: fresh, refresh: "refresh-2", userID: NowStubServer.me))
        h.server.todo.failure = .json(#"{"status":"unauthorized"}"#)
        let unauthorizedCalls = h.server.todo.calls
        do {
            _ = try await transport.todoSync(userID: NowStubServer.me, request: request)
        } catch {}
        #expect(h.server.todo.calls == unauthorizedCalls + 2, "unauthorized 뒤 갱신·재시도가 없었다")
        #expect(h.requests("auth.token").count == 1)
        #expect(h.model.session.session?.accessToken == fresh)

        h.server.todo.failure = .missingFunction("todo_sync")
        await #expect(throws: TodoSyncTransportError.functionMissing) {
            _ = try await transport.todoSync(userID: NowStubServer.me, request: request)
        }

        h.server.todo.failure = nil
        await h.model.session.signOut()
        let afterSignOut = h.server.todo.calls
        await #expect(throws: TodoSyncTransportError.accountMismatch) {
            _ = try await transport.todoSync(userID: NowStubServer.me, request: request)
        }
        #expect(h.server.todo.calls == afterSignOut)
        #expect(h.violations.isEmpty)
    }

    // MARK: - 앱 전체

    @Test("앱 전체 조립: scenePhase active 로 모든 탭 스토어가 깨어나도 금지 호출 0, 지금 탭은 채워진다 · 로그아웃 reset")
    func wholeAppScenario() async throws {
        let h = NowHarness()
        defer { h.tearDown() }
        await h.launch()
        h.model.sceneDidBecomeActive()
        let now = h.model.now
        _ = await baseWaitUntil { now.hasLoadedTeam && now.hasLoadedDirectory }
        await now.refreshTask?.value
        #expect(now.myCard(now: Self.now)?.weekLine == "이번 주 24.8시간 · 목표 40시간 · 62%")
        #expect(now.workingPeople(now: Self.now).count == 6)
        #expect(now.badgeCount == 0)
        h.model.sceneDidEnterBackground()
        await h.model.session.signOut()
        #expect(now.membership == nil && now.teamMembers.isEmpty && !now.canEditTodos)
        #expect(h.violations.isEmpty, "\(h.violations)")
    }

    // MARK: - 순수

    @Test("시간 계산: 자정을 넘긴 진행 세션은 오늘을 자정부터 · 받은 뒤 날이 바뀌면 어제 합은 버린다 · 주도 같다")
    func timeMath() {
        let kst = TeamWeeklyGoal.kstCalendar
        let midnight = kst.startOfDay(for: Self.now)
        var member = TeamMemberStatus(id: "x", name: "x", status: .working, updatedAt: nil, currentSessionStartedAt: midnight.addingTimeInterval(-3_600))
        member.todayDurationSeconds = 100
        member.weeklyDurationSeconds = 1_000
        let at = midnight.addingTimeInterval(1_800)
        #expect(NowTimeMath.todaySeconds(member, fetchedAt: at, now: at) == 100 + 1_800, "어제 몫 1시간은 오늘이 아니다")
        #expect(member.liveTodayDurationSeconds(now: at) == 100 + 5_400, "대조: 코어 식은 자정 전 몫까지 더한다")
        #expect(NowTimeMath.todaySeconds(member, fetchedAt: midnight.addingTimeInterval(-60), now: at) == 1_800, "받은 뒤 날이 바뀌었다")
        let weekStart = TeamWeeklyGoal.koreanWeekStart(for: Self.now)
        #expect(NowTimeMath.weekSeconds(member, fetchedAt: weekStart.addingTimeInterval(-10), now: at) == 5_400)
        member.status = .offWork
        #expect(NowTimeMath.todaySeconds(member, fetchedAt: at, now: at) == 100)

        #expect(NowFormat.hoursOneDecimal(143_999) == "39.9", "내림 — 40.0 으로 올리지 않는다")
        #expect(NowFormat.percent(workedSeconds: 89_280, goalSeconds: 144_000) == 62)
        #expect(NowFormat.percent(workedSeconds: 10_000_000, goalSeconds: 3_600) == 999)
        #expect(NowFormat.hoursMinutes(15_000) == "4:10" && NowFormat.clock(3_725) == "1:02:05")
    }

    @Test("입력 규칙: 늘리는 방향은 100자(코드 포인트 1000)까지 되돌리고, 지우는 방향은 늘 통과 · 카운터는 90자부터")
    func draftRules() {
        let ninetyNine = String(repeating: "가", count: 99)
        #expect(NowTodoDraft.accepted(current: ninetyNine, proposed: ninetyNine + "나") == ninetyNine + "나")
        #expect(NowTodoDraft.accepted(current: ninetyNine + "나", proposed: ninetyNine + "나다") == ninetyNine + "나")
        let over = String(repeating: "가", count: 120)
        #expect(NowTodoDraft.accepted(current: over, proposed: String(over.dropLast())) == String(over.dropLast()))
        #expect(NowTodoDraft.counterText(String(repeating: "a", count: 89)) == nil)
        #expect(NowTodoDraft.counterText(String(repeating: "a", count: 90)) == "90/100")
        #expect(NowStore.notice(for: [CancellationError()]) == nil)
        #expect(NowStore.notice(for: [URLError(.timedOut), SupabaseWorkServiceError.invalidResponse(500)]) == NowText.networkFailed)
    }
}
