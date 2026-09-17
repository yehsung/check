@testable import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit
@testable import CheckWidgetsKit

/// 위젯 3종의 값(투영 · 고르기 · 타임라인) · 체크 인텐트 본문(토큰 갱신 없음 · 조정 파일 · 병합) · 색 표 일치 · 지금 탭 데모 픽스처.
@MainActor
@Suite(.serialized) struct NowWidgetTests {
    nonisolated static let now = MobileClock.demoInstant // 2026-09-17 14:05 KST(목)

    // MARK: - 내 오늘 투영

    @Test("내 오늘: 근무 중이면 스냅샷 뒤로 흐른 시간을 더해 센다 · 멈춘 값은 그대로 · 타이머 시작점")
    func meProjectionTicks() {
        let me = WidgetSnapshot.Me(working: true, sessionStartedAt: Self.now.addingTimeInterval(-13_500), todaySeconds: 18_600, weekSeconds: 89_280, goalHours: 40)
        let at = Self.now.addingTimeInterval(600)
        let projected = AingWidgetMe(me: me, generatedAt: Self.now, at: at)
        #expect(projected.isWorking && projected.isTicking)
        #expect(projected.todaySeconds == 19_200 && projected.weekSeconds == 89_880)
        #expect(projected.timerStart(at: at) == at.addingTimeInterval(-19_200))
        #expect(projected.percent == 62 && projected.weekCaption == "24.9/40시간")

        let idle = WidgetSnapshot.Me(working: false, sessionStartedAt: nil, todaySeconds: 4_020, weekSeconds: 146_000, goalHours: 40)
        let still = AingWidgetMe(me: idle, generatedAt: Self.now, at: at)
        #expect(!still.isTicking && still.todaySeconds == 4_020 && still.timerStart(at: at) == nil)
        #expect(still.isGoalComplete && still.progress == 1 && still.percent == 101)

        // 연결이 끊긴 세션(앱이 시작 시각을 싣지 않음)은 근무 중이어도 세지 않는다.
        let stale = WidgetSnapshot.Me(working: true, sessionStartedAt: nil, todaySeconds: 100, weekSeconds: 200, goalHours: 40)
        let frozen = AingWidgetMe(me: stale, generatedAt: Self.now, at: at)
        #expect(frozen.isWorking && !frozen.isTicking && frozen.todaySeconds == 100)
    }

    @Test("내 오늘: 스냅샷 뒤 자정이 지나면 오늘은 자정부터(근무 중) 또는 0 · 월요일이면 주도 새로 · 12시간 넘게 낡으면 멈춘다")
    func meProjectionBoundaries() {
        let midnight = TeamWeeklyGoal.koreanDayStart(for: Self.now).addingTimeInterval(86_400) // 9/18 00:00 KST
        let generatedAt = midnight.addingTimeInterval(-600)
        let working = WidgetSnapshot.Me(working: true, sessionStartedAt: midnight.addingTimeInterval(-7_200), todaySeconds: 30_000, weekSeconds: 100_000, goalHours: 40)
        let afterMidnight = AingWidgetMe(me: working, generatedAt: generatedAt, at: midnight.addingTimeInterval(300))
        #expect(afterMidnight.todaySeconds == 300, "어제 누적이 오늘로 넘어왔다")
        #expect(afterMidnight.weekSeconds == 100_900, "같은 주는 이어 센다")

        let idle = WidgetSnapshot.Me(working: false, sessionStartedAt: nil, todaySeconds: 30_000, weekSeconds: 100_000, goalHours: 40)
        #expect(AingWidgetMe(me: idle, generatedAt: generatedAt, at: midnight.addingTimeInterval(300)).todaySeconds == 0)

        let monday = TeamWeeklyGoal.koreanWeekStart(for: Self.now).addingTimeInterval(7 * 86_400)
        let beforeMonday = monday.addingTimeInterval(-60)
        let weekWorking = WidgetSnapshot.Me(working: true, sessionStartedAt: monday.addingTimeInterval(-3_600), todaySeconds: 3_540, weekSeconds: 150_000, goalHours: 40)
        let newWeek = AingWidgetMe(me: weekWorking, generatedAt: beforeMonday, at: monday.addingTimeInterval(120))
        #expect(newWeek.weekSeconds == 120 && newWeek.todaySeconds == 120)
        #expect(AingWidgetMe(me: idle, generatedAt: beforeMonday, at: monday.addingTimeInterval(120)).weekSeconds == 0)

        let old = AingWidgetMe(
            me: WidgetSnapshot.Me(working: true, sessionStartedAt: Self.now.addingTimeInterval(-1_000), todaySeconds: 1_000, weekSeconds: 1_000, goalHours: 40),
            generatedAt: TeamWeeklyGoal.koreanDayStart(for: Self.now).addingTimeInterval(60),
            at: TeamWeeklyGoal.koreanDayStart(for: Self.now).addingTimeInterval(60 + 13 * 3_600)
        )
        #expect(!old.isTicking, "12시간 넘은 스냅샷을 계속 셌다")
        #expect(old.todaySeconds == 1_000 + 12 * 3_600, "12시간 지점에서 멈춘다")
    }

    @Test("내 오늘 상태: me 없음 → 앱을 열면 채워져요 · 목표 0(소속 없음 표시) → 팀 참여 안내 · 목표 1 이상 → 내 값")
    func myTodayState() {
        let empty = WidgetSnapshot(generatedAt: Self.now)
        #expect(AingWidgetMyTodayState(snapshot: empty, at: Self.now) == .noData)

        var noTeam = empty
        noTeam.me = NowStore.widgetNoTeamMe
        #expect(AingWidgetMyTodayState(snapshot: noTeam, at: Self.now) == .noTeam)
        #expect(NowStore.widgetNoTeamMe.goalHours == 0 && !NowStore.widgetNoTeamMe.working)

        var member = empty
        member.me = .init(working: false, sessionStartedAt: nil, todaySeconds: 0, weekSeconds: 0, goalHours: 1)
        guard case .me(let me) = AingWidgetMyTodayState(snapshot: member, at: Self.now) else {
            Issue.record("목표 1시간인 팀원을 소속 없음으로 그렸다")
            return
        }
        #expect(me.goalHours == 1 && me.percent == 0)
        #expect(AingWidgetText.noTeam != AingWidgetText.noData)
    }

    // MARK: - 고르기 · 서식 · 타임라인

    @Test("지금 근무 중 고르기: 우리 팀 먼저(순서 유지) · 한도 · 외 N명 / 할 일 고르기: 한도 · 남은 수 · 이월 배지")
    func selections() {
        let working: [WidgetSnapshot.WorkingPerson] = [
            .init(name: "코랄", center: nil, teammate: false, startedAt: nil),
            .init(name: "민트", center: "seoul", teammate: true, startedAt: Self.now),
            .init(name: "하늘", center: nil, teammate: false, startedAt: nil),
            .init(name: "라임", center: nil, teammate: true, startedAt: Self.now),
        ]
        let small = AingWidgetWorking(working, limit: 3)
        #expect(small.shown.map(\.name) == ["민트", "라임", "코랄"])
        #expect(small.total == 4 && small.hiddenCount == 1)
        #expect(AingWidgetWorking([], limit: 6).total == 0)

        let todos: [WidgetSnapshot.TodoPreview] = (0..<5).map {
            .init(id: "id\($0)", title: "t\($0)", isCompleted: $0 == 1, carryOverDays: $0)
        }
        let medium = AingWidgetTodos(todos, limit: 3)
        #expect(medium.rows.map(\.id) == ["id0", "id1", "id2"] && medium.hiddenCount == 2 && medium.remaining == 4)
        #expect(AingWidgetTodos.carryBadge(todos[0]) == nil && AingWidgetTodos.carryBadge(todos[1]) == "어제" && AingWidgetTodos.carryBadge(todos[3]) == "3일 전")
    }

    @Test("서식 · 15분 타임라인(1분 간격 16칸)")
    func formatAndTimeline() {
        #expect(AingWidgetFormat.ago(from: Self.now, now: Self.now.addingTimeInterval(59)) == "방금")
        #expect(AingWidgetFormat.ago(from: Self.now, now: Self.now.addingTimeInterval(-30)) == "방금")
        #expect(AingWidgetFormat.ago(from: Self.now, now: Self.now.addingTimeInterval(125)) == "2분 전")
        #expect(AingWidgetFormat.ago(from: Self.now, now: Self.now.addingTimeInterval(7_300)) == "2시간 전")
        #expect(AingWidgetFormat.ago(from: Self.now, now: Self.now.addingTimeInterval(200_000)) == "2일 전")
        #expect(AingWidgetFormat.hoursMinutes(12_300) == "3시간 25분" && AingWidgetFormat.hoursMinutes(59) == "0분")
        let dates = AingWidgetTimelinePlan.entryDates(now: Self.now)
        #expect(dates.count == 16 && dates.first == Self.now && dates.last == Self.now.addingTimeInterval(900))
        #expect(zip(dates, dates.dropFirst()).allSatisfy { $1.timeIntervalSince($0) == 60 })
        #expect(AingWidgetTimelinePlan.nextReload(now: Self.now) == Self.now.addingTimeInterval(900))
        #expect(Set(AingWidgetKind.all).count == 3)
    }

    @Test("위젯 색 표는 앱 토큰(MobileThemePalette)을 위젯 바탕에 겹친 값과 같다")
    func paletteMatchesApp() {
        func same(_ widget: AingWidgetPalette.Pair, _ app: MobileThemePalette.Pair, _ name: String) {
            let backdrop = MobileThemePalette.widgetBackground
            for (hex, rgb, base) in [(widget.light, app.light, backdrop.light), (widget.dark, app.dark, backdrop.dark)] {
                let expected = rgb.alpha < 1 ? rgb.composited(over: base) : rgb
                let c = AingWidgetPalette.components(hex)
                let delta = max(abs(c.r - expected.r), abs(c.g - expected.g), abs(c.b - expected.b))
                #expect(delta <= 0.5 / 255 + 1e-9, "\(name) 이 앱 토큰과 다르다(\(String(hex, radix: 16)))")
            }
        }
        same(AingWidgetPalette.background, MobileThemePalette.widgetBackground, "background")
        same(AingWidgetPalette.cardElevated, MobileThemePalette.fill, "cardElevated")
        same(AingWidgetPalette.track, MobileThemePalette.fill, "track")
        same(AingWidgetPalette.primaryText, MobileThemePalette.label, "primaryText")
        same(AingWidgetPalette.secondaryText, MobileThemePalette.label2, "secondaryText")
        same(AingWidgetPalette.working, MobileThemePalette.working, "working")
        same(AingWidgetPalette.offWork, MobileThemePalette.offWork, "offWork")
        same(AingWidgetPalette.pending, MobileThemePalette.pending, "pending")
        same(AingWidgetPalette.accent, MobileThemePalette.accent, "accent")
    }

    // MARK: - 체크 인텐트 본문

    /// 위젯 한 벌: 공용 저장소 · 키체인 흉내 · 할 일 파일(앱이 만든 두 줄, 둘 다 서버에 올라간 상태).
    @MainActor
    final class WidgetRig {
        let storage = BaseStub.makeStorage()
        let vault = CountingVault()
        let userID = "u-widget"
        var clockNow = NowWidgetTests.now
        var first: TodoItem!
        var second: TodoItem!

        var url: URL { storage.todoFileURL(userID: userID) }

        @MainActor
        init(tokenValidFor seconds: TimeInterval = 600) {
            storage.defaults.set(userID, forKey: AingSharedKeys.userID)
            vault.write(BaseStub.jwt(exp: NowWidgetTests.now.addingTimeInterval(seconds), subject: userID), key: AingKeychain.accessTokenKey)
            vault.write("refresh-never-read", key: AingKeychain.refreshTokenKey)
            vault.readKeys = []
            let list = TodoListStore(fileURL: url, clock: { NowWidgetTests.now })
            first = list.add("위젯에서 체크")
            second = list.add("그대로 둘 일")
            // 서버에 올라갔다고 치고 pending 을 비운다(watermark 도 세운다).
            let outgoing = list.makeSyncRequest(ids: Array(list.pendingIDs))
            list.applySync(TodoSyncResult(items: list.items, rejectedIDs: [], full: false, watermarkMs: 1_000), for: outgoing)
            try? WidgetSnapshotCodec.write(
                WidgetSnapshot(generatedAt: NowWidgetTests.now, todosPreview: [
                    .init(id: second.id.uuidString.lowercased(), title: second.title, isCompleted: false),
                    .init(id: first.id.uuidString.lowercased(), title: first.title, isCompleted: false),
                ]),
                to: storage.widgetSnapshotURL
            )
        }

        var shared: WidgetSharedData {
            WidgetSharedData(storage: storage, vault: vault, now: { NowWidgetTests.now })
        }

        func file() throws -> TodoFile { try TodoFileStore.load(from: url) }

        func tearDown() { BaseStub.tearDown(host: "none", storage: storage) }
    }

    final class CountingVault: TokenVault, @unchecked Sendable {
        private var values: [String: String] = [:]
        var readKeys: [String] = []
        func read(_ key: String) -> String? { readKeys.append(key); return values[key] }
        func write(_ value: String, key: String) { values[key] = value }
        func delete(_ key: String) { values[key] = nil }
    }

    @Test("체크: 토큰이 60초 안에 만료되면 파일·스냅샷만 고치고 보내지 않는다(갱신 없음 · refresh token 을 읽지도 않는다)")
    func toggleWithoutUsableToken() async throws {
        let rig = WidgetRig(tokenValidFor: 30)
        defer { rig.tearDown() }
        var calls = 0
        let outcome = await WidgetTodoToggle.run(todoID: rig.first.id.uuidString, shared: rig.shared, now: { NowWidgetTests.now.addingTimeInterval(5) }) { _, _ in
            calls += 1
            return TodoSyncResponse(status: "ok")
        }
        #expect(outcome == .savedLocally(.tokenUnusable))
        #expect(calls == 0)
        let file = try rig.file()
        #expect(file.items.first { $0.id == rig.first.id }?.completedAt != nil)
        #expect(file.items.first { $0.id == rig.second.id }?.completedAt == nil)
        #expect(file.sync.pendingIDs == [rig.first.id], "앱이 다음에 올리게 pending 으로 남는다")
        let snapshot = try #require(WidgetSnapshotCodec.read(from: rig.storage.widgetSnapshotURL))
        #expect(snapshot.todosPreview.map(\.isCompleted) == [false, true], "스냅샷의 그 줄만 체크 · 순서 그대로")
        #expect(!rig.vault.readKeys.contains(AingKeychain.refreshTokenKey))
    }

    @Test("체크: 쓸 수 있는 토큰이면 todo_sync 를 정확히 한 번 · 병합으로 pending 이 비고 watermark 가 오른다 · 다시 누르면 해제")
    func toggleSyncsOnce() async throws {
        let rig = WidgetRig()
        defer { rig.tearDown() }
        let server = NowFakeTodoServer()
        var requests: [TodoSyncRequest] = []
        let sync: WidgetTodoToggle.Sync = { token, request in
            #expect(JWTClaims.expiry(accessToken: token) != nil)
            requests.append(request)
            let stub = MobileStubRequest(method: "POST", host: "h", path: "/rest/v1/rpc/todo_sync", query: "", headers: [:], bodyText: String(decoding: try request.rpcBody(), as: UTF8.self))
            return try TodoSyncResponse.decode(server.respond(stub).body)
        }
        let outcome = await WidgetTodoToggle.run(todoID: rig.first.id.uuidString.lowercased(), shared: rig.shared, now: { NowWidgetTests.now.addingTimeInterval(5) }, sync: sync)
        #expect(outcome == .synced)
        #expect(requests.count == 1)
        #expect(requests.first?.changes.map(\.id) == [rig.first.id.uuidString.lowercased()])
        #expect(requests.first?.sinceMs == 1_000)
        let file = try rig.file()
        #expect(file.sync.pendingIDs.isEmpty)
        #expect(file.sync.watermarkMs == server.watermarkMs)
        #expect(file.items.first { $0.id == rig.first.id }?.completedAt != nil)
        #expect(server.row(rig.first.id.uuidString)?["completed_at_ms"] is NSNumber)

        let again = await WidgetTodoToggle.run(todoID: rig.first.id.uuidString, shared: rig.shared, now: { NowWidgetTests.now.addingTimeInterval(9) }, sync: sync)
        #expect(again == .synced)
        #expect(try rig.file().items.first { $0.id == rig.first.id }?.completedAt == nil)
        #expect(WidgetSnapshotCodec.read(from: rig.storage.widgetSnapshotURL)?.todosPreview.last?.isCompleted == false)
        #expect(!rig.vault.readKeys.contains(AingKeychain.refreshTokenKey))
    }

    @Test("체크: 401·오프라인·함수 없는 서버는 재시도·갱신 없이 한 번에 접고 pending 을 남긴다 · 로그아웃·모르는 id 는 파일을 건드리지 않는다")
    func toggleFailures() async throws {
        let rig = WidgetRig()
        defer { rig.tearDown() }
        let cases: [(Error, WidgetTodoToggle.SkipReason)] = [
            (SupabaseWorkServiceError.sessionExpired, .failed),
            (URLError(.notConnectedToInternet), .failed),
            (SupabaseWorkServiceError.databaseSchemaMissing, .serverMissing),
        ]
        for (index, (error, reason)) in cases.enumerated() {
            var calls = 0
            let outcome = await WidgetTodoToggle.run(todoID: rig.first.id.uuidString, shared: rig.shared, now: { NowWidgetTests.now.addingTimeInterval(Double(10 + index)) }) { _, _ in
                calls += 1
                throw error
            }
            #expect(outcome == .savedLocally(reason))
            #expect(calls == 1, "실패를 다시 보냈다")
            #expect(try rig.file().sync.pendingIDs.contains(rig.first.id))
        }
        let refused = await WidgetTodoToggle.run(todoID: rig.first.id.uuidString, shared: rig.shared, now: { NowWidgetTests.now.addingTimeInterval(20) }) { _, _ in
            TodoSyncResponse(status: "unauthorized")
        }
        #expect(refused == .savedLocally(.refused("unauthorized")))

        let before = try Data(contentsOf: rig.url)
        let unknown = await WidgetTodoToggle.run(todoID: UUID().uuidString, shared: rig.shared, now: { NowWidgetTests.now }) { _, _ in
            Issue.record("모르는 id 인데 보냈다")
            return TodoSyncResponse(status: "ok")
        }
        #expect(unknown == .notFound)
        let malformed = await WidgetTodoToggle.run(todoID: "not-a-uuid", shared: rig.shared, now: { NowWidgetTests.now }) { _, _ in
            TodoSyncResponse(status: "ok")
        }
        #expect(malformed == .notFound)
        #expect(try Data(contentsOf: rig.url) == before)
        rig.storage.defaults.removeObject(forKey: AingSharedKeys.userID)
        let signedOut = await WidgetTodoToggle.run(todoID: rig.first.id.uuidString, shared: rig.shared, now: { NowWidgetTests.now }) { _, _ in
            TodoSyncResponse(status: "ok")
        }
        #expect(signedOut == .signedOut)
        #expect(try Data(contentsOf: rig.url) == before)
    }

    @Test("체크 응답을 기다리는 사이 앱이 다른 줄을 고쳤으면, 병합은 그 파일 위에서 하고 앱의 변경을 pending 으로 지킨다")
    func toggleMergesOverConcurrentAppEdit() async throws {
        let rig = WidgetRig()
        defer { rig.tearDown() }
        let server = NowFakeTodoServer()
        let outcome = await WidgetTodoToggle.run(todoID: rig.first.id.uuidString, shared: rig.shared, now: { NowWidgetTests.now.addingTimeInterval(5) }) { _, request in
            // 앱(다른 프로세스)이 같은 파일의 둘째 줄을 고친다.
            let app = TodoListStore(fileURL: rig.url, clock: { NowWidgetTests.now.addingTimeInterval(6) })
            app.rename(rig.second.id, to: "앱에서 고친 제목")
            let stub = MobileStubRequest(method: "POST", host: "h", path: "/rest/v1/rpc/todo_sync", query: "", headers: [:], bodyText: String(decoding: try request.rpcBody(), as: UTF8.self))
            return try TodoSyncResponse.decode(server.respond(stub).body)
        }
        #expect(outcome == .synced)
        let file = try rig.file()
        #expect(file.items.first { $0.id == rig.second.id }?.title == "앱에서 고친 제목", "위젯 병합이 앱의 수정을 덮었다")
        #expect(file.sync.pendingIDs == [rig.second.id])
        #expect(file.items.first { $0.id == rig.first.id }?.completedAt != nil)
    }

    @Test("실제 서비스로: 위젯 체크는 rpc/todo_sync 한 경로만 · 인증 갱신(/auth/v1/token) 0 · 금지 호출 0")
    func toggleUsesOnlyTodoSyncPath() async throws {
        let rig = WidgetRig()
        defer { rig.tearDown() }
        let host = BaseStub.makeHost("widget")
        let server = NowFakeTodoServer()
        MobileStubURLProtocol.register(host: host) { request in
            request.rpcName == "todo_sync" ? server.respond(request) : BaseStub.jwtExpired
        }
        defer { MobileStubURLProtocol.unregister(host: host) }
        let service = BaseStub.makeService(host: host)
        let outcome = await WidgetTodoToggle.run(todoID: rig.first.id.uuidString, shared: rig.shared, now: { NowWidgetTests.now.addingTimeInterval(5) }) { token, request in
            try await service.todoSync(accessToken: token, request: request)
        }
        #expect(outcome == .synced)
        let requests = MobileStubURLProtocol.requests(host: host)
        #expect(requests.map(\.path) == ["/rest/v1/rpc/todo_sync"])
        let sync = try #require(requests.first, "todo_sync 가 나가지 않았다 — 인덱스 읽기 전에 멈춘다")
        #expect(BaseStub.bearer(sync).hasPrefix("Bearer "))
        #expect(MobileForbiddenCalls.violations(in: requests).isEmpty)

        // 401 이면 갱신하지 않고 한 번으로 끝난다.
        server.failure = BaseStub.jwtExpired
        MobileStubURLProtocol.clearRequests(host: host)
        let expired = await WidgetTodoToggle.run(todoID: rig.second.id.uuidString, shared: rig.shared, now: { NowWidgetTests.now.addingTimeInterval(8) }) { token, request in
            try await service.todoSync(accessToken: token, request: request)
        }
        #expect(expired == .savedLocally(.failed))
        #expect(MobileStubURLProtocol.requests(host: host).map(\.path) == ["/rest/v1/rpc/todo_sync"])
    }

    // MARK: - 데모 픽스처

    @Test("데모 픽스처(장면 now): 지금 탭이 서버 계약 모양 그대로 채워진다 — 카드 · 근무 중 6 · 할 일(이월·오래됨) · 금지 호출 0")
    func demoFixturesFillNowTab() async throws {
        let host = BaseStub.makeHost("nowdemo")
        let index = MobileDemoFixtures.load()
        #expect(index.duplicateKeys.isEmpty, "\(index.duplicateKeys)")
        MobileStubURLProtocol.register(host: host) { request in index.response(for: request, scenario: "now") }
        let storage = BaseStub.makeStorage()
        defer { BaseStub.tearDown(host: host, storage: storage) }
        let vault = InMemoryTokenVault()
        vault.write(MobileDemo.accessToken, key: AingKeychain.accessTokenKey)
        vault.write("demo-refresh-token", key: AingKeychain.refreshTokenKey)
        storage.defaults.set(MobileDemo.userID, forKey: AingSharedKeys.userID)
        let model = MobileAppModel(environment: MobileEnvironment(
            service: BaseStub.makeService(host: host), vault: vault, storage: storage, appInfo: BaseStub.appInfo,
            clock: .fixed(Self.now), installationID: MobileDemo.installationID, realtimeTransport: nil,
            runsTimers: false, reloadWidgetTimelines: {}
        ))
        model.session.clientReleaseTimeoutSeconds = 0   // 벽시계 상한 없음
        model.start()
        #expect(await baseWaitUntil { model.session.phase == .signedIn })
        model.sceneDidBecomeActive()
        let store = model.now
        #expect(await baseWaitUntil { store.hasLoadedTeam && store.todos.items.count >= 5 })
        await store.refreshTask?.value

        #expect(store.membership?.teamName == "아잉 데모팀")
        let card = try #require(store.myCard(now: Self.now))
        #expect(card.weekLine == "이번 주 24.8시간 · 목표 40시간 · 62%")
        #expect(NowFormat.clock(card.todaySeconds) == "5:10:00")
        let people = store.workingPeople(now: Self.now)
        #expect(people.map(\.name) == ["민트", "보리", "라임", "모래", "코랄", "하늘"])
        try #require(people.count >= 2, "근무 중 목록이 안 섰다 — 인덱스 읽기 전에 멈춘다")
        #expect(people[1].isStale)
        let rows = store.todoRows()
        #expect(rows.main.map(\.carryBadge) == [nil, "어제", "3일 전", nil])
        #expect(rows.main.last?.isDone == true)
        #expect(rows.old.map(\.title) == ["온보딩 문서 링크 모으기"])
        #expect(store.notice == nil)

        // 계약(SPEC-wave1 §1.2): full = (p_since_ms is null) or 80일보다 오래됨. 데모 첫 동기화는 워터마크가 없다.
        let firstSync = try #require(MobileStubURLProtocol.requests(host: host).first { $0.rpcName == "todo_sync" })
        let syncBody = try #require(try JSONSerialization.jsonObject(with: Data(firstSync.bodyText.utf8)) as? [String: Any])
        #expect(syncBody["p_since_ms"] is NSNull, "데모 첫 동기화에 since 가 실렸다")
        let fixture = index.response(for: firstSync, scenario: "now")
        let reply = try #require(try JSONSerialization.jsonObject(with: fixture.body) as? [String: Any])
        #expect(reply["full"] as? Bool == true, "since=null 요청에 full:false 픽스처")
        #expect(MobileForbiddenCalls.violations(in: MobileStubURLProtocol.requests(host: host)).isEmpty)
        model.sceneDidEnterBackground()
    }
}
