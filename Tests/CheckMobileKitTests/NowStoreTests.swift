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

    @Test("소속 없음: 카드 대신 안내, 다른 팀 근무자는 보이고, 스냅샷 me 는 비운다")
    func noTeam() async {
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
        #expect(h.model.widgetSnapshots.current?.me == nil)
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
