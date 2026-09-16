import AppKit
import Foundation
import Observation
import Testing
@testable import check

// MARK: - v0.3.30 할 일 동기화 ③ 엔진 · 전송 · 조정자
//
// 지키는 것(명세 A4-4~8):
// · 디바운스 1.5초 · 한 번에 하나(도는 중 요청은 끝나고 한 번 더) · 500개 분할 · watermark 갱신·파일 저장
// · 404/PGRST202 → 조용히 멈추고 pending 유지 · 네트워크 실패 → pending 유지 · unauthorized/401 → 세션 갱신 경로
// · 계정 전환: 파일을 바꾸고, **앞 계정의 늦은 응답이 새 계정 파일에 들어가지 않는다**
// · 편집 중인 줄·되돌리기 창은 서버 병합에 깨지지 않는다
// · 맞추는 때: 실행·로그인 · 보드 열기 · 고친 뒤 1.5초 · 5분마다 · 깨어날 때 / 로그아웃 파일은 맞추지 않는다
// · "이 맥에만 저장" 문구가 남아 있지 않다

// MARK: 테스트 도우미(다른 V0330Todo 파일도 쓴다)

/// 가짜 전송. 부를 때마다 기록하고 `respond` 로 답한다.
@MainActor
final class TodoSyncV0330Transport: TodoSyncTransport {
    private(set) var requests: [(userID: String, request: TodoSyncRequest)] = []
    var respond: @MainActor (String, TodoSyncRequest) async throws -> TodoSyncResponse

    init(respond: @escaping @MainActor (String, TodoSyncRequest) async throws -> TodoSyncResponse) {
        self.respond = respond
    }

    func todoSync(userID: String, request: TodoSyncRequest) async throws -> TodoSyncResponse {
        requests.append((userID, request))
        return try await respond(userID, request)
    }
}

/// 손으로 미는 시계·타이머. 실제 1.5초·5분을 기다리지 않는다.
@MainActor
final class TodoSyncV0330Scheduler: TodoSyncScheduler {
    @MainActor
    final class Entry: TodoSyncCancellable {
        let fireAt: Double
        let order: Int
        let action: @MainActor () -> Void
        var cancelled = false
        init(fireAt: Double, order: Int, action: @escaping @MainActor () -> Void) {
            self.fireAt = fireAt
            self.order = order
            self.action = action
        }
        func cancel() { cancelled = true }
    }

    private(set) var now: Double = 0
    private var entries: [Entry] = []
    private var counter = 0

    func schedule(after seconds: Double, _ action: @escaping @MainActor () -> Void) -> any TodoSyncCancellable {
        counter += 1
        let entry = Entry(fireAt: now + seconds, order: counter, action: action)
        entries.append(entry)
        return entry
    }

    func advance(by seconds: Double) {
        let target = now + seconds
        while let next = entries
            .filter({ !$0.cancelled && $0.fireAt <= target + 1e-9 })
            .min(by: { ($0.fireAt, $0.order) < ($1.fireAt, $1.order) }) {
            entries.removeAll { $0 === next }
            now = next.fireAt
            next.action()
        }
        now = target
        entries.removeAll { $0.cancelled }
    }
}

/// 전송을 붙잡아 두는 문(응답 전 상태를 만들려고). **영원히 붙잡지 않는다** — 테스트가 예상보다 한 번 더 부르면
/// (변이·회귀) 아무도 풀어 주지 않아 스위트가 멈추는데, 그건 빨강이 아니라 교착이다. 3초 뒤 스스로 풀고 `timedOut` 을 센다.
@MainActor
final class TodoSyncV0330Gate {
    private var continuations: [Int: CheckedContinuation<Void, Never>] = [:]
    private(set) var arrivals = 0
    private(set) var timedOut = 0

    func wait() async {
        arrivals += 1
        let ticket = arrivals
        await withCheckedContinuation { continuation in
            continuations[ticket] = continuation
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(3))
                guard let self, let stuck = self.continuations.removeValue(forKey: ticket) else { return }
                self.timedOut += 1
                stuck.resume()
            }
        }
    }

    func release() {
        let waiting = continuations
        continuations = [:]
        waiting.values.forEach { $0.resume() }
    }
}

/// 엔진이 조용해질 때까지 기다린다(재실행까지 포함).
@MainActor
func todoSyncV0330Idle(_ sync: TodoSync) async {
    while sync.isRunning, let task = sync.runTask {
        await task.value
    }
}

/// 조건이 설 때까지 짧게 양보하며 기다린다(관찰·통지 콜백이 한 틱 뒤에 오는 경로용).
@MainActor
func todoSyncV0330Eventually(_ condition: @MainActor () -> Bool) async {
    for _ in 0..<400 {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
}

/// 관찰 가능한 가짜 세션(조정자가 계정 전환을 스스로 알아채는지 보려고).
@MainActor
@Observable
final class TodoSyncV0330Session {
    var userID: String?
    init(userID: String?) { self.userID = userID }
}

private let base: Int64 = 1_726_500_000_000
private let userA = "11111111-1111-4111-8111-111111111111"
private let userB = "22222222-2222-4222-8222-222222222222"

@MainActor
private func fixedClock(_ ms: Int64) -> () -> Date {
    { TodoRules.date(milliseconds: ms) }
}

@MainActor
private func serverTransport(_ server: TodoSyncV0330Server) -> TodoSyncV0330Transport {
    TodoSyncV0330Transport { userID, request in server.respond(userID: userID, request: request) }
}

// MARK: 전선 모양

@Test("요청 본문은 키가 늘 같다 — p_changes·p_since_ms, 항목 키 7개(nil 은 null), id 소문자")
func todoSyncRequestBodyShape() throws {
    let id = UUID(uuidString: "ABCDEF01-2345-4678-9ABC-DEF012345678")!
    let item = TodoItem(
        id: id, title: "배포 \"노트\" / 정리", createdAt: TodoRules.date(milliseconds: base),
        updatedAt: TodoRules.date(milliseconds: base + 456), originDayKey: "20260916"
    )
    let body = try TodoSyncRequest(changes: [TodoSyncWireItem(item: item)], sinceMs: nil).rpcBody()
    #expect(String(decoding: body, as: UTF8.self) == """
    {"p_changes":[{"completed_at_ms":null,"created_at_ms":1726500000000,"deleted_at_ms":null,"id":"abcdef01-2345-4678-9abc-def012345678","origin_day_key":"20260916","title":"배포 \\"노트\\" / 정리","updated_at_ms":1726500000456}],"p_since_ms":null}
    """)
    let withSince = try TodoSyncRequest(changes: [], sinceMs: 42).rpcBody()
    #expect(String(decoding: withSince, as: UTF8.self) == #"{"p_changes":[],"p_since_ms":42}"#)
}

@Test("응답 디코드는 필드 전부 Optional — 깨진 행이 있으면 그 행만 버리고 full 을 끈다, ok 가 아니거나 뼈대가 없으면 병합 안 함")
func todoSyncResponseDecodeIsTolerant() throws {
    let good = "{\"id\":\"abcdef01-2345-4678-9abc-def012345678\",\"title\":\"t\",\"created_at_ms\":1,\"updated_at_ms\":2,\"completed_at_ms\":null,\"deleted_at_ms\":3,\"origin_day_key\":\"20260916\"}"
    let broken = "{\"id\":null,\"title\":\"t\",\"created_at_ms\":\"x\"}"
    let ok = try TodoSyncResponse.decode(Data("{\"status\":\"ok\",\"items\":[\(good),\(broken)],\"watermark_ms\":99,\"rejected\":[{\"id\":\"nope\",\"reason\":\"invalid\"},{\"id\":\"abcdef01-2345-4678-9abc-def012345679\",\"reason\":\"quota\"}],\"full\":true}".utf8))
    let result = try #require(ok.mergeableResult())
    #expect(result.items.count == 1)
    #expect(result.items[0].deletedAt == TodoRules.date(milliseconds: 3))
    #expect(result.full == false, "못 읽은 행이 있는데 full 병합을 하면 서버에 있는 줄을 지운다")
    #expect(result.rejectedIDs == [UUID(uuidString: "abcdef01-2345-4678-9abc-def012345679")!])
    #expect(result.watermarkMs == 99)

    for raw in ["{\"status\":\"unauthorized\"}", "{\"status\":\"too_many\",\"max\":500}", "{\"status\":\"ok\",\"items\":[]}", "{}"] {
        #expect(try TodoSyncResponse.decode(Data(raw.utf8)).mergeableResult() == nil, "\(raw) 를 병합하려 했다")
    }
}

// MARK: 엔진

@MainActor
@Test("고친 뒤 1.5초 디바운스 — 연달아 고치면 마지막 뒤 1.5초에 한 번만 보낸다")
func todoSyncDebouncesEdits() async throws {
    let server = TodoSyncV0330Server(nowMs: base)
    let transport = serverTransport(server)
    let scheduler = TodoSyncV0330Scheduler()
    let list = TodoListStore(fileURL: todoSyncV0330TempURL(), clock: fixedClock(base))
    let sync = TodoSync(list: list, transport: transport, scheduler: scheduler)
    sync.activate(userID: userA)
    await todoSyncV0330Idle(sync)
    #expect(transport.requests.count == 1)                 // 실행 직후 한 번

    for _ in 0..<3 {
        list.add("연달아")
        sync.noteLocalChange()
        scheduler.advance(by: 1.0)
        await todoSyncV0330Idle(sync)
    }
    #expect(transport.requests.count == 1, "디바운스 전에 보냈다")
    scheduler.advance(by: 0.49)
    await todoSyncV0330Idle(sync)
    #expect(transport.requests.count == 1)
    scheduler.advance(by: 0.01)
    await todoSyncV0330Idle(sync)
    #expect(transport.requests.count == 2)
    #expect(transport.requests.dropFirst().first?.request.changes.count == 3)
    #expect(list.pendingIDs.isEmpty)
}

@MainActor
@Test("한 번에 하나 — 도는 중에 세 번 불러도 끝난 뒤 한 번만 더 돈다")
func todoSyncIsSingleFlight() async throws {
    let server = TodoSyncV0330Server(nowMs: base)
    let gate = TodoSyncV0330Gate()
    let transport = TodoSyncV0330Transport { userID, request in
        await gate.wait()
        return server.respond(userID: userID, request: request)
    }
    let list = TodoListStore(fileURL: todoSyncV0330TempURL(), clock: fixedClock(base))
    let sync = TodoSync(list: list, transport: transport, scheduler: TodoSyncV0330Scheduler())
    sync.activate(userID: userA)
    await todoSyncV0330Eventually { gate.arrivals == 1 }
    for _ in 0..<3 { sync.requestSync(.boardOpened) }
    #expect(transport.requests.count == 1)
    gate.release()
    await todoSyncV0330Eventually { gate.arrivals == 2 }
    gate.release()
    await todoSyncV0330Idle(sync)
    #expect(transport.requests.count == 2)
    #expect(sync.lastOutcome == .synced)
    #expect(gate.timedOut == 0, "기다리지 않은 요청이 문에 걸렸다")
}

@MainActor
@Test("pending 이 1203개면 500·500·203 으로 나눠 보내고, 뒤 요청은 앞 응답의 watermark 를 since 로 싣는다")
func todoSyncSplitsIntoBatchesOf500() async throws {
    let server = TodoSyncV0330Server(nowMs: base)
    let transport = TodoSyncV0330Transport { userID, request in
        defer { server.nowMs += 1_000 }
        return server.respond(userID: userID, request: request)
    }
    let items = (0..<1203).map { index in
        TodoItem(
            id: UUID(), title: "줄 \(index)", createdAt: TodoRules.date(milliseconds: base),
            updatedAt: TodoRules.date(milliseconds: base), originDayKey: "20260916"
        )
    }
    let url = todoSyncV0330TempURL()
    try TodoFileStore.save(TodoFile(version: 1, items: items), to: url)
    let list = TodoListStore(fileURL: url, clock: fixedClock(base))
    #expect(list.pendingIDs.count == 1203)
    let sync = TodoSync(list: list, transport: transport, scheduler: TodoSyncV0330Scheduler())
    sync.activate(userID: userA)
    await todoSyncV0330Idle(sync)

    #expect(transport.requests.map(\.request.changes.count) == [500, 500, 203])
    #expect(transport.requests.map(\.request.sinceMs) == [nil, base, base + 1_000])
    #expect(list.pendingIDs.isEmpty)
    #expect(list.watermarkMs == base + 2_000)
    #expect(server.items(for: userA).count == 1203)
    let onDisk = try TodoFileStore.load(from: url)
    #expect(onDisk.sync.pendingIDs.isEmpty)
    #expect(onDisk.sync.watermarkMs == base + 2_000)
    #expect(onDisk.items.count == 1203)
}

@MainActor
@Test("네트워크 실패·ok 아닌 응답 — pending·watermark·파일이 그대로 남는다")
func todoSyncFailureKeepsPending() async throws {
    let url = todoSyncV0330TempURL()
    let list = TodoListStore(fileURL: url, clock: fixedClock(base))
    let item = try #require(list.add("못 보낸 줄"))
    let before = try Data(contentsOf: url)
    var mode = 0
    let transport = TodoSyncV0330Transport { _, _ in
        if mode == 0 { throw URLError(.notConnectedToInternet) }
        return TodoSyncResponse(status: "invalid")
    }
    let sync = TodoSync(list: list, transport: transport, scheduler: TodoSyncV0330Scheduler())
    sync.activate(userID: userA)
    await todoSyncV0330Idle(sync)
    #expect(sync.lastOutcome == .failed)
    mode = 1
    sync.requestSync(.periodic)
    await todoSyncV0330Idle(sync)
    #expect(sync.lastOutcome == .refused("invalid"))
    #expect(list.pendingIDs == [item.id])
    #expect(list.watermarkMs == nil)
    #expect(try Data(contentsOf: url) == before)
}

@MainActor
@Test("계정 전환 — 앞 계정의 늦은 응답은 새 계정 파일·목록에 들어가지 않는다(세대 가드), 새 계정은 곧바로 맞춘다")
func todoSyncAccountSwitchDropsLateResponse() async throws {
    let server = TodoSyncV0330Server(nowMs: base)
    // A 의 서버에는 다른 기기가 만든 줄이 있다 — 늦은 응답이 B 에 섞이면 이 줄이 B 목록에 보인다.
    let foreign = TodoItem(
        id: UUID(), title: "A 계정의 다른 기기 줄", createdAt: TodoRules.date(milliseconds: base - 5_000),
        updatedAt: TodoRules.date(milliseconds: base - 5_000), originDayKey: "20260916"
    )
    server.seed(userID: userA, foreign)
    let gate = TodoSyncV0330Gate()
    let transport = TodoSyncV0330Transport { userID, request in
        await gate.wait()
        return server.respond(userID: userID, request: request)
    }
    let fileA = todoSyncV0330TempURL("todos.A.json")
    let fileB = todoSyncV0330TempURL("todos.B.json")
    let bItem = TodoItem(
        id: UUID(), title: "B 의 줄", createdAt: TodoRules.date(milliseconds: base - 1_000),
        updatedAt: TodoRules.date(milliseconds: base - 1_000), originDayKey: "20260916"
    )
    try TodoFileStore.save(TodoFile(items: [bItem], sync: TodoFileSyncState(watermarkMs: base - 1_000, pendingIDs: [])), to: fileB)
    let bBefore = try Data(contentsOf: fileB)

    let list = TodoListStore(fileURL: fileA, clock: fixedClock(base))
    let aItem = try #require(list.add("A 의 줄"))
    let sync = TodoSync(list: list, transport: transport, scheduler: TodoSyncV0330Scheduler())
    sync.activate(userID: userA)
    await todoSyncV0330Eventually { gate.arrivals == 1 }

    sync.switchAccount(userID: userB, fileURL: fileB)
    #expect(list.fileURL == fileB)
    #expect(list.items == [bItem])
    gate.release()                                          // A 의 응답이 이제 도착한다
    await todoSyncV0330Eventually { gate.arrivals == 2 }
    #expect(list.items == [bItem], "앞 계정 응답이 새 계정 목록에 섞였다")
    #expect(try Data(contentsOf: fileB) == bBefore, "앞 계정 응답이 새 계정 파일에 쓰였다")
    gate.release()                                          // B 의 요청
    await todoSyncV0330Idle(sync)

    #expect(transport.requests.map(\.userID) == [userA, userB])
    #expect(gate.timedOut == 0)
    #expect(transport.requests.dropFirst().first?.request.sinceMs == base - 1_000)
    #expect(list.items == [bItem])
    #expect(sync.lastOutcome == .synced)
    // A 파일은 늦은 응답을 받지 않았으니 여전히 보낼 것을 들고 있다(다음에 A 로 들어오면 올라간다).
    let aFile = try TodoFileStore.load(from: fileA)
    #expect(aFile.sync.pendingIDs == [aItem.id])
    #expect(!aFile.items.contains { $0.id == foreign.id })
}

@MainActor
@Test("로그아웃(계정 없음)은 맞추지 않는다 — 고쳐도·주기에도 요청 0")
func todoSyncSkipsSignedOutFile() async throws {
    let transport = TodoSyncV0330Transport { _, _ in TodoSyncResponse(status: "ok", items: [], watermarkMs: 1, rejected: [], full: false) }
    let scheduler = TodoSyncV0330Scheduler()
    let list = TodoListStore(fileURL: todoSyncV0330TempURL(), clock: fixedClock(base))
    let sync = TodoSync(list: list, transport: transport, scheduler: scheduler)
    sync.activate(userID: nil)
    list.add("로그인 전에 적은 줄")
    sync.noteLocalChange()
    scheduler.advance(by: 1_000)
    sync.requestSync(.wake)
    #expect(!sync.isRunning && sync.runTask == nil, "로그아웃 상태에서 동기화 작업을 만들었다")
    await todoSyncV0330Idle(sync)
    #expect(transport.requests.isEmpty)
}

@MainActor
@Test("여러 묶음을 보내는 중 계정이 바뀌면 앞 계정의 남은 묶음을 보내지 않는다 — 다음 요청은 새 계정의 것")
func todoSyncAccountSwitchStopsRemainingBatches() async throws {
    let server = TodoSyncV0330Server(nowMs: base)
    let foreign = TodoItem(
        id: UUID(), title: "A 계정 서버 줄", createdAt: TodoRules.date(milliseconds: base - 5_000),
        updatedAt: TodoRules.date(milliseconds: base - 5_000), originDayKey: "20260916"
    )
    server.seed(userID: userA, foreign)
    let gate = TodoSyncV0330Gate()
    let transport = TodoSyncV0330Transport { userID, request in
        await gate.wait()
        return server.respond(userID: userID, request: request)
    }
    let items = (0..<501).map { index in
        TodoItem(
            id: UUID(), title: "A 줄 \(index)", createdAt: TodoRules.date(milliseconds: base),
            updatedAt: TodoRules.date(milliseconds: base), originDayKey: "20260916"
        )
    }
    let fileA = todoSyncV0330TempURL("todos.A.json")
    try TodoFileStore.save(TodoFile(version: 1, items: items), to: fileA)
    let fileB = todoSyncV0330TempURL("todos.B.json")
    try TodoFileStore.save(TodoFile(items: [], sync: TodoFileSyncState(watermarkMs: base - 1_000, pendingIDs: [])), to: fileB)
    let list = TodoListStore(fileURL: fileA, clock: fixedClock(base))
    let sync = TodoSync(list: list, transport: transport, scheduler: TodoSyncV0330Scheduler())
    sync.activate(userID: userA)
    await todoSyncV0330Eventually { gate.arrivals == 1 }
    sync.switchAccount(userID: userB, fileURL: fileB)
    gate.release()
    await todoSyncV0330Eventually { gate.arrivals == 2 }
    gate.release()
    await todoSyncV0330Idle(sync)
    #expect(transport.requests.map(\.userID) == [userA, userB], "앞 계정의 두 번째 묶음이 나갔다")
    #expect(gate.timedOut == 0)
    #expect(list.items.isEmpty, "앞 계정의 서버 줄이 새 계정 목록에 섞였다")
}

@MainActor
@Test("실행 중에 90일이 지나 병합 뒤 정리된 항목은 pending 에서도 빠진다(파일까지)")
func todoSyncPruneAfterMergeDropsPending() async throws {
    var nowMs = base
    let url = todoSyncV0330TempURL()
    let list = TodoListStore(fileURL: url, clock: { TodoRules.date(milliseconds: nowMs) })
    let item = try #require(list.add("오프라인에서 끝낸 줄"))
    list.toggleDone(item.id)
    #expect(list.pendingIDs == [item.id])
    nowMs += 91 * 86_400_000                      // 앱을 켠 채 91일(한 번도 못 맞춤)
    let transport = TodoSyncV0330Transport { _, _ in
        // 응답 전에 제목을 또 고쳤다 → 스냅샷 규칙으로는 pending 에 남는 항목. 그래도 정리되면 pending 에서 빠져야 한다.
        list.rename(item.id, to: "응답 전에 고친 제목")
        return TodoSyncResponse(status: "ok", items: [], watermarkMs: nowMs, rejected: [], full: false)
    }
    let sync = TodoSync(list: list, transport: transport, scheduler: TodoSyncV0330Scheduler())
    sync.activate(userID: userA)
    await todoSyncV0330Idle(sync)
    #expect(list.items.isEmpty)
    #expect(list.pendingIDs.isEmpty, "정리된 항목 id 가 pending 에 남았다")
    #expect(try TodoFileStore.load(from: url).sync.pendingIDs.isEmpty)
}

// MARK: 편집 중 병합

@MainActor
@Test("보드에서 고치는 줄·되돌리기 창의 줄은 서버 병합에 깨지지 않고, 보호가 끝나면 다시 맞춰 서버 값으로 수렴한다")
func todoSyncDefersMergeForEditingAndUndoRows() async throws {
    let server = TodoSyncV0330Server(nowMs: base)
    let transport = serverTransport(server)
    var nowMs = base
    let list = TodoListStore(fileURL: todoSyncV0330TempURL(), clock: { TodoRules.date(milliseconds: nowMs) })
    let editing = try #require(list.add("고치는 중인 줄"))
    nowMs += 1
    let undoing = try #require(list.add("되돌리기 창의 줄"))
    let board = CheckTodoBoardController(store: list, undoSeconds: 600)
    list.syncProtectedIDs = { [weak board] in board?.syncProtectedIDs ?? [] }
    var localChanges = 0
    list.onLocalChange = { localChanges += 1 }
    let sync = TodoSync(list: list, transport: transport, scheduler: TodoSyncV0330Scheduler())
    sync.activate(userID: userA)
    await todoSyncV0330Idle(sync)
    #expect(list.pendingIDs.isEmpty)

    // 다른 기기: 고치는 줄은 지웠고, 되돌리기 창의 줄은 제목을 바꿨다.
    nowMs += 10_000
    server.nowMs = nowMs
    var deletedElsewhere = editing
    deletedElsewhere.deletedAt = TodoRules.date(milliseconds: nowMs)
    deletedElsewhere.updatedAt = TodoRules.date(milliseconds: nowMs)
    server.seed(userID: userA, deletedElsewhere)
    var renamedElsewhere = undoing
    renamedElsewhere.title = "다른 기기에서 바꾼 제목"
    renamedElsewhere.updatedAt = TodoRules.date(milliseconds: nowMs)
    server.seed(userID: userA, renamedElsewhere)

    board.beginEdit(editing.id)
    board.requestDelete(undoing.id)
    localChanges = 0
    sync.requestSync(.periodic)
    await todoSyncV0330Idle(sync)

    #expect(list.items.first { $0.id == editing.id } == editing, "편집 중인 줄이 병합으로 바뀌었다 — 편집기가 사라진다")
    #expect(TodoRules.visible(list.items, todayKey: list.todayKey).contains { $0.id == editing.id })
    #expect(list.items.first { $0.id == undoing.id } == undoing)
    #expect(list.pendingIDs == [editing.id, undoing.id])
    #expect(board.editingID == editing.id && board.pendingDeleteID == undoing.id)

    board.cancelEdit()
    #expect(localChanges == 1, "편집이 끝났는데 미룬 병합을 다시 맞추자고 알리지 않았다")
    board.undoDelete(undoing.id)
    #expect(localChanges == 2)
    sync.requestSync(.edit)
    await todoSyncV0330Idle(sync)
    #expect(list.items.first { $0.id == editing.id } == deletedElsewhere)
    #expect(list.items.first { $0.id == undoing.id } == renamedElsewhere)
    #expect(list.pendingIDs.isEmpty)
}

// MARK: 프로덕션 전송(스토어 세션)

/// 호스트별 응답 대기열 + 요청 기록. 경로마다 응답을 차례로 꺼내고, 마지막 응답은 계속 되풀이한다.
final class TodoSyncV0330URLProtocol: URLProtocol {
    struct Reply: Sendable {
        let status: Int
        let body: String
        /// 응답을 이만큼 늦게 준다(응답을 기다리는 사이 세션이 바뀌는 창을 만들려고).
        var delay: TimeInterval = 0
    }

    private final class Delivery: @unchecked Sendable {
        let proto: TodoSyncV0330URLProtocol
        let response: HTTPURLResponse
        let data: Data
        init(proto: TodoSyncV0330URLProtocol, response: HTTPURLResponse, data: Data) {
            self.proto = proto
            self.response = response
            self.data = data
        }
        func run() {
            proto.client?.urlProtocol(proto, didReceive: response, cacheStoragePolicy: .notAllowed)
            proto.client?.urlProtocol(proto, didLoad: data)
            proto.client?.urlProtocolDidFinishLoading(proto)
        }
    }

    struct Logged: Sendable {
        let path: String
        let query: String?
        let authorization: String?
        let body: String
    }

    private static let lock = NSLock()
    private nonisolated(unsafe) static var replies: [String: [String: [Reply]]] = [:]
    private nonisolated(unsafe) static var logs: [String: [Logged]] = [:]

    static func set(host: String, path: String, _ queue: [Reply]) {
        lock.lock(); defer { lock.unlock() }
        replies[host, default: [:]][path] = queue
    }

    static func log(host: String) -> [Logged] {
        lock.lock(); defer { lock.unlock() }
        return logs[host] ?? []
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TodoSyncV0330URLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let host = request.url?.host ?? ""
        let path = request.url?.path ?? ""
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            let size = 4096
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
            while stream.hasBytesAvailable {
                let read = stream.read(buffer, maxLength: size)
                if read <= 0 { break }
                body.append(buffer, count: read)
            }
            buffer.deallocate()
            stream.close()
        }
        let reply: Reply
        Self.lock.lock()
        Self.logs[host, default: []].append(Logged(
            path: path, query: request.url?.query,
            authorization: request.value(forHTTPHeaderField: "Authorization"),
            body: String(decoding: body, as: UTF8.self)
        ))
        var queue = Self.replies[host]?[path] ?? []
        if queue.count > 1 {
            reply = queue.removeFirst()
            Self.replies[host]?[path] = queue
        } else {
            reply = queue.first ?? Reply(status: 200, body: "[]")
        }
        Self.lock.unlock()
        let response = HTTPURLResponse(
            url: request.url!, statusCode: reply.status, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        let delivery = Delivery(proto: self, response: response, data: Data(reply.body.utf8))
        if reply.delay > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + reply.delay) { delivery.run() }
        } else {
            delivery.run()
        }
    }

    override func stopLoading() {}
}

@MainActor
private func transportStore(host: String, userID: String = userA) -> WorkTimerStore {
    let suite = "check-v0330-todo-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!,
        anonKey: "anon-test-key",
        session: TodoSyncV0330URLProtocol.session()
    )
    let store = WorkTimerStore(
        service: service,
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: defaults,
        workspaceNotifications: nil
    )
    store.session = SupabaseSession(accessToken: "token-1", refreshToken: "refresh-1", userID: userID)
    return store
}

private let okBody = "{\"status\":\"ok\",\"items\":[],\"watermark_ms\":1726500000000,\"rejected\":[],\"full\":true}"

@MainActor
@Test("서버에 todo_sync 가 없으면(PGRST202·본문 없는 404) 조용히 멈추고 pending 유지, 쿨다운 동안 고칠 때는 다시 안 친다")
func todoSyncMissingFunctionFoldsQuietly() async throws {
    let bodies = [
        "{\"code\":\"PGRST202\",\"details\":\"Searched for the function public.todo_sync with parameters p_changes, p_since_ms or with a single unnamed json/jsonb parameter, but no matches were found in the schema cache.\",\"hint\":null,\"message\":\"Could not find the function public.todo_sync(p_changes, p_since_ms) in the schema cache\"}",
        "",
    ]
    for (index, body) in bodies.enumerated() {
        let host = "v0330-todo-missing-\(index)-\(UUID().uuidString.prefix(8))"
        TodoSyncV0330URLProtocol.set(host: host, path: "/rest/v1/rpc/todo_sync", [.init(status: 404, body: body)])
        let store = transportStore(host: host)
        var nowMs = base
        let url = todoSyncV0330TempURL()
        let list = TodoListStore(fileURL: url, clock: { TodoRules.date(milliseconds: nowMs) })
        let item = try #require(list.add("서버보다 앱이 먼저 나갔다"))
        let before = try Data(contentsOf: url)
        let scheduler = TodoSyncV0330Scheduler()
        let sync = TodoSync(
            list: list, transport: WorkTimerStoreTodoSyncTransport(store: store), scheduler: scheduler,
            clock: { TodoRules.date(milliseconds: nowMs) }
        )
        sync.activate(userID: userA)
        await todoSyncV0330Idle(sync)
        #expect(sync.lastOutcome == .serverMissing, "body #\(index)")
        #expect(list.pendingIDs == [item.id])
        #expect(try Data(contentsOf: url) == before)
        #expect(store.session != nil, "함수 부재를 세션 만료로 읽어 로그아웃시켰다")
        #expect(TodoSyncV0330URLProtocol.log(host: host).filter { $0.path == "/rest/v1/rpc/todo_sync" }.count == 1)

        nowMs += 60_000
        sync.noteLocalChange()
        scheduler.advance(by: 2)
        sync.requestSync(.boardOpened)
        await todoSyncV0330Idle(sync)
        #expect(TodoSyncV0330URLProtocol.log(host: host).filter { $0.path == "/rest/v1/rpc/todo_sync" }.count == 1, "쿨다운 중에 404 를 또 쳤다")

        sync.requestSync(.periodic)
        await todoSyncV0330Idle(sync)
        #expect(TodoSyncV0330URLProtocol.log(host: host).filter { $0.path == "/rest/v1/rpc/todo_sync" }.count == 2, "주기 동기화까지 막혔다")
    }
}

@MainActor
@Test("{\"status\":\"unauthorized\"} 와 401 JWT expired 는 세션 갱신 경로를 타고 새 토큰으로 한 번 더 보낸다")
func todoSyncUnauthorizedRefreshesSession() async throws {
    let first = [
        TodoSyncV0330URLProtocol.Reply(status: 200, body: "{\"status\":\"unauthorized\"}"),
        TodoSyncV0330URLProtocol.Reply(status: 401, body: "{\"code\":\"PGRST301\",\"message\":\"JWT expired\"}"),
    ]
    for (index, expired) in first.enumerated() {
        let host = "v0330-todo-auth-\(index)-\(UUID().uuidString.prefix(8))"
        TodoSyncV0330URLProtocol.set(host: host, path: "/rest/v1/rpc/todo_sync", [expired, .init(status: 200, body: okBody)])
        TodoSyncV0330URLProtocol.set(host: host, path: "/auth/v1/token", [.init(
            status: 200,
            body: "{\"access_token\":\"token-2\",\"refresh_token\":\"refresh-2\",\"user\":{\"id\":\"\(userA)\"}}"
        )])
        let store = transportStore(host: host)
        let list = TodoListStore(fileURL: todoSyncV0330TempURL(), clock: fixedClock(base))
        list.add("토큰이 만료된 채로 고쳤다")
        let sync = TodoSync(list: list, transport: WorkTimerStoreTodoSyncTransport(store: store), scheduler: TodoSyncV0330Scheduler())
        sync.activate(userID: userA)
        await todoSyncV0330Idle(sync)

        let log = TodoSyncV0330URLProtocol.log(host: host)
        #expect(log.map(\.path) == ["/rest/v1/rpc/todo_sync", "/auth/v1/token", "/rest/v1/rpc/todo_sync"], "case #\(index)")
        #expect(log.first?.authorization == "Bearer token-1")
        #expect(log.last?.authorization == "Bearer token-2")
        #expect(sync.lastOutcome == .synced)
        #expect(store.session?.accessToken == "token-2")
        #expect(list.pendingIDs.isEmpty)
    }
}

@MainActor
@Test("전송은 요청한 계정이 지금 세션이 아니면 보내지 않는다(요청 0)")
func todoSyncTransportRefusesOtherAccount() async throws {
    let host = "v0330-todo-mismatch-\(UUID().uuidString.prefix(8))"
    TodoSyncV0330URLProtocol.set(host: host, path: "/rest/v1/rpc/todo_sync", [.init(status: 200, body: okBody)])
    let store = transportStore(host: host, userID: userB)
    let transport = WorkTimerStoreTodoSyncTransport(store: store)
    await #expect(throws: TodoSyncTransportError.accountMismatch) {
        _ = try await transport.todoSync(userID: userA, request: TodoSyncRequest(changes: [], sinceMs: nil))
    }
    store.session = nil
    await #expect(throws: TodoSyncTransportError.accountMismatch) {
        _ = try await transport.todoSync(userID: userA, request: TodoSyncRequest(changes: [], sinceMs: nil))
    }
    #expect(TodoSyncV0330URLProtocol.log(host: host).isEmpty)
}

@MainActor
@Test("응답을 기다리는 사이 세션 세대가 바뀌면(로그아웃·재로그인) 그 응답을 돌려주지 않는다 — 세대 가드")
func todoSyncTransportDropsResponseAcrossSessionGeneration() async throws {
    let host = "v0330-todo-generation-\(UUID().uuidString.prefix(8))"
    TodoSyncV0330URLProtocol.set(host: host, path: "/rest/v1/rpc/todo_sync", [.init(status: 200, body: okBody, delay: 0.3)])
    let store = transportStore(host: host)
    let transport = WorkTimerStoreTodoSyncTransport(store: store)
    let call = Task { @MainActor in
        try await transport.todoSync(userID: userA, request: TodoSyncRequest(changes: [], sinceMs: nil))
    }
    await todoSyncV0330Eventually { !TodoSyncV0330URLProtocol.log(host: host).isEmpty }
    store.sessionGeneration += 1
    await #expect(throws: TodoSyncTransportError.accountMismatch) { _ = try await call.value }

    // 대조군: 세대가 그대로면 같은 응답이 그대로 돌아온다.
    let control = try await transport.todoSync(userID: userA, request: TodoSyncRequest(changes: [], sinceMs: nil))
    #expect(control.status == "ok")
}

// MARK: 조정자

@MainActor
@Test("맞추는 때: 실행 직후 · 고친 뒤 1.5초 · 보드를 열 때 · 깨어날 때 · 5분마다 / 로그아웃 파일은 안 맞춤 / 로그인하면 그 계정 파일로 바꿔 곧바로")
func todoSyncCoordinatorTriggersAndAccountSwitch() async throws {
    let server = TodoSyncV0330Server(nowMs: base)
    let transport = serverTransport(server)
    let scheduler = TodoSyncV0330Scheduler()
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("check-v0330-coord-\(UUID().uuidString)")
    let fileFor: (String?) -> URL = { directory.appendingPathComponent("todos.\($0 ?? "local").json") }
    let session = TodoSyncV0330Session(userID: userA)
    let list = TodoListStore(fileURL: fileFor(userA), clock: fixedClock(base))
    let board = CheckTodoBoardController(store: list)
    let center = NotificationCenter()
    let sync = TodoSync(list: list, transport: transport, scheduler: scheduler, clock: fixedClock(base))
    let coordinator = TodoSyncCoordinator(
        sync: sync, board: board, userID: { session.userID }, fileURL: fileFor, wakeNotifications: center
    )
    coordinator.start()
    await todoSyncV0330Idle(sync)
    #expect(transport.requests.count == 1, "실행 직후 맞추지 않았다")

    board.setDraft("고친 줄")
    board.submitDraft()
    scheduler.advance(by: 1.49)
    await todoSyncV0330Idle(sync)
    #expect(transport.requests.count == 1)
    scheduler.advance(by: 0.01)
    await todoSyncV0330Idle(sync)
    #expect(transport.requests.count == 2, "고친 뒤 1.5초에 맞추지 않았다")
    #expect(transport.requests.dropFirst().first?.request.changes.map(\.title) == ["고친 줄"])

    board.open(anchor: NSRect(x: 800, y: 400, width: 140, height: 170), screenVisibleFrame: NSRect(x: 0, y: 0, width: 1_280, height: 800))
    await todoSyncV0330Idle(sync)
    #expect(transport.requests.count == 3, "보드를 열 때 맞추지 않았다")
    board.close()

    center.post(name: NSWorkspace.didWakeNotification, object: nil)
    await todoSyncV0330Eventually { transport.requests.count == 4 }
    await todoSyncV0330Idle(sync)
    #expect(transport.requests.count == 4, "깨어날 때 맞추지 않았다")

    scheduler.advance(by: TodoSync.periodicSeconds - scheduler.now)
    await todoSyncV0330Idle(sync)
    #expect(transport.requests.count == 5, "5분 주기로 맞추지 않았다")

    // 로그아웃 → 로컬 파일, 맞추지 않음
    session.userID = nil
    await todoSyncV0330Eventually { list.fileURL == fileFor(nil) }
    #expect(list.fileURL == fileFor(nil))
    #expect(list.items.isEmpty, "로그아웃했는데 앞 계정 목록이 보인다")
    list.add("로그아웃 상태에서 적음")
    scheduler.advance(by: 1_000)
    center.post(name: NSWorkspace.didWakeNotification, object: nil)
    try? await Task.sleep(for: .milliseconds(50))
    await todoSyncV0330Idle(sync)
    #expect(transport.requests.count == 5, "로그아웃 파일을 서버로 보냈다")

    // B 로 로그인 → B 파일로 바꾸고 곧바로 맞춤
    session.userID = userB
    await todoSyncV0330Eventually { list.fileURL == fileFor(userB) }
    await todoSyncV0330Idle(sync)
    #expect(list.fileURL == fileFor(userB))
    #expect(transport.requests.count == 6)
    #expect(transport.requests.last?.userID == userB)
    #expect(!list.items.contains { $0.title == "로그아웃 상태에서 적음" }, "로그아웃 때 적은 줄이 B 계정에 섞였다")
    #expect(server.items(for: userB).isEmpty)
}

@MainActor
@Test("보드 열림 알림은 닫힘→열림에서만 온다 — 못 뜬 창을 다시 만드는 복구 경로는 요청을 더 쏘지 않는다")
func todoBoardOpenedFiresOnlyOnTransition() {
    let list = TodoListStore(fileURL: todoSyncV0330TempURL(), clock: fixedClock(base))
    let board = CheckTodoBoardController(store: list, stuckPanelCheckSeconds: 600)
    var opened = 0
    board.onOpened = { opened += 1 }
    let anchor = NSRect(x: 800, y: 400, width: 140, height: 170)
    let visible = NSRect(x: 0, y: 0, width: 1_280, height: 800)
    board.open(anchor: anchor, screenVisibleFrame: visible)
    #expect(opened == 1)
    board.rebuildStuckPanel(anchor: anchor, screenVisibleFrame: visible)
    board.open(anchor: anchor, screenVisibleFrame: visible)
    #expect(opened == 1, "이미 열린 보드를 다시 세우는 경로가 동기화를 또 불렀다")
    board.close()
    board.toggle(anchor: anchor, screenVisibleFrame: visible)
    #expect(opened == 2)
    board.close()
}

@MainActor
@Test("계정 전환은 되돌리기 창의 삭제를 앞 계정 파일에 확정하고, 편집·초안을 버린다")
func todoSyncAccountSwitchResetsBoardInputState() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("check-v0330-reset-\(UUID().uuidString)")
    let fileFor: (String?) -> URL = { directory.appendingPathComponent("todos.\($0 ?? "local").json") }
    let session = TodoSyncV0330Session(userID: userA)
    let list = TodoListStore(fileURL: fileFor(userA), clock: fixedClock(base))
    let doomed = try #require(list.add("지울 줄"))
    let editing = try #require(list.add("고치던 줄"))
    let board = CheckTodoBoardController(store: list, undoSeconds: 600)
    let transport = TodoSyncV0330Transport { _, _ in TodoSyncResponse(status: "invalid") }
    let sync = TodoSync(list: list, transport: transport, scheduler: TodoSyncV0330Scheduler())
    let coordinator = TodoSyncCoordinator(sync: sync, board: board, userID: { session.userID }, fileURL: fileFor, wakeNotifications: nil)
    coordinator.start()
    await todoSyncV0330Idle(sync)

    board.requestDelete(doomed.id)
    board.beginEdit(editing.id)
    board.setDraft("A 가 적다 만 글")
    session.userID = userB
    await todoSyncV0330Eventually { list.fileURL == fileFor(userB) }
    #expect(board.pendingDeleteID == nil && board.editingID == nil)
    #expect(board.draft.isEmpty, "다음 계정이 앞 사람의 초안을 본다")
    let aFile = try TodoFileStore.load(from: fileFor(userA))
    #expect(aFile.items.first { $0.id == doomed.id }?.deletedAt != nil, "되돌리기 창의 삭제가 앞 계정 파일에 확정되지 않았다")
    #expect(list.items.isEmpty)
}

// MARK: 문구

@Test("할 일이 '이 맥에만 저장'된다는 안내가 소스 어디에도 남아 있지 않다")
func todoNoLocalOnlyStorageCopyRemains() throws {
    #expect(!TodoBoardStrings.footer.contains("맥에만"))
    #expect(TodoBoardStrings.footer.contains("계정"))
    let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/check")
    let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "swift" }
    #expect(files.count > 20)
    for file in files {
        let text = try String(contentsOf: file, encoding: .utf8)
        // 문자열 리터럴 줄만 본다(주석의 옛 문구 인용은 허용).
        for line in text.split(separator: "\n") where !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
            for banned in ["내 맥에만 저장", "맥에만 저장돼", "서버로 가지 않"] where line.contains(banned) && line.contains("\"") {
                Issue.record("\(file.lastPathComponent): \(line)")
            }
        }
    }
}
