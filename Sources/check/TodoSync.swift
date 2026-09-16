import AppKit
import Foundation
import Observation

// MARK: - 할 일 서버 동기화 (v0.3.30 · 계약 1.2 `todo_sync`)
//
// 흐름: 고칠 때마다 로컬 파일에 저장하고 id 를 "보낼 것"에 넣는다 → `todo_sync(p_changes, p_since_ms)` 한 번에
// 보낼 항목 + 마지막 watermark 를 싣는다 → 서버가 LWW 로 반영하고 바뀐 행·새 watermark·거절 목록을 돌려준다 →
// `TodoRules.mergedSync`(서버와 같은 규칙)로 합쳐 파일에 쓴다.
//
// 이 파일에 있는 것:
// · 전선 모양(`TodoSyncWireItem` · `TodoSyncRequest` · `TodoSyncResponse`) — 서버 JSON 과 글자 단위로 같다(snake_case).
//   서비스의 공용 인코더(convertToSnakeCase)를 **쓰지 않는다**: 전송 계층이 바뀌어도(psql 왕복 프로브) 같은 바이트여야 한다.
// · 전송 프로토콜(`TodoSyncTransport`) — 프로덕션은 `WorkTimerStoreTodoSyncTransport`(세션 갱신 경로를 탄다),
//   테스트·왕복 프로브는 가짜나 psql 전송을 꽂는다.
// · 엔진(`TodoSync`) — 한 번에 하나만 돌고, 500개씩 나눠 보내고, 실패하면 pending 을 그대로 둔다.
// · 조정자(`TodoSyncCoordinator`) — 언제 맞출지(실행·로그인 · 보드 열기 · 고친 뒤 1.5초 · 5분마다 · 깨어날 때)와
//   계정 전환(파일 바꾸기)을 잇는다.

// MARK: - 전선 모양

/// 요청·응답에 같은 모양으로 실리는 항목 하나. **응답 디코드는 필드 전부 Optional** 이다 — 앱이 먼저 나가고 서버가
/// 늦은 창, 혹은 한 행이 깨져도 나머지 행은 읽혀야 한다(한 필드 타입 불일치가 배열 전체 디코드를 죽이지 않게 `try?`).
struct TodoSyncWireItem: Codable, Equatable, Sendable {
    var id: String?
    var title: String?
    var createdAtMs: Int64?
    var updatedAtMs: Int64?
    var completedAtMs: Int64?
    var deletedAtMs: Int64?
    var originDayKey: String?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case createdAtMs = "created_at_ms"
        case updatedAtMs = "updated_at_ms"
        case completedAtMs = "completed_at_ms"
        case deletedAtMs = "deleted_at_ms"
        case originDayKey = "origin_day_key"
    }

    init(
        id: String?, title: String?, createdAtMs: Int64?, updatedAtMs: Int64?,
        completedAtMs: Int64?, deletedAtMs: Int64?, originDayKey: String?
    ) {
        self.id = id
        self.title = title
        self.createdAtMs = createdAtMs
        self.updatedAtMs = updatedAtMs
        self.completedAtMs = completedAtMs
        self.deletedAtMs = deletedAtMs
        self.originDayKey = originDayKey
    }

    /// 로컬 항목 → 전선. id 는 소문자(서버 uuid 출력과 같은 글자)로 싣는다.
    init(item: TodoItem) {
        self.init(
            id: item.id.uuidString.lowercased(),
            title: item.title,
            createdAtMs: TodoRules.milliseconds(item.createdAt),
            updatedAtMs: TodoRules.milliseconds(item.updatedAt),
            completedAtMs: item.completedAt.map(TodoRules.milliseconds),
            deletedAtMs: item.deletedAt.map(TodoRules.milliseconds),
            originDayKey: item.originDayKey
        )
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try? c.decodeIfPresent(String.self, forKey: .id)
        title = try? c.decodeIfPresent(String.self, forKey: .title)
        createdAtMs = try? c.decodeIfPresent(Int64.self, forKey: .createdAtMs)
        updatedAtMs = try? c.decodeIfPresent(Int64.self, forKey: .updatedAtMs)
        completedAtMs = try? c.decodeIfPresent(Int64.self, forKey: .completedAtMs)
        deletedAtMs = try? c.decodeIfPresent(Int64.self, forKey: .deletedAtMs)
        originDayKey = try? c.decodeIfPresent(String.self, forKey: .originDayKey)
    }

    /// **키 7개를 언제나 전부 싣는다**(nil 은 null). 합성 인코더는 nil 키를 빼는데, 그러면 완료 안 한 항목과 완료한 항목의
    /// 모양이 달라져 서버 검증이 한쪽만 거절하는 일이 스텁 테스트에서는 안 보인다(work_tick 요청과 같은 규약).
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(createdAtMs, forKey: .createdAtMs)
        try c.encode(updatedAtMs, forKey: .updatedAtMs)
        try c.encode(completedAtMs, forKey: .completedAtMs)
        try c.encode(deletedAtMs, forKey: .deletedAtMs)
        try c.encode(originDayKey, forKey: .originDayKey)
    }

    /// 서버 행 → 로컬 항목. 뼈대(id·제목·만든/고친 시각·만든 날)가 하나라도 없으면 nil — 반쪽 행으로 사용자 목록을 덮지 않는다.
    func todoItem() -> TodoItem? {
        guard let id = id.flatMap(UUID.init(uuidString:)),
              let title,
              let createdAtMs,
              let updatedAtMs,
              let originDayKey
        else { return nil }
        return TodoItem(
            id: id,
            title: title,
            createdAt: TodoRules.date(milliseconds: createdAtMs),
            updatedAt: TodoRules.date(milliseconds: updatedAtMs),
            completedAt: completedAtMs.map(TodoRules.date(milliseconds:)),
            deletedAt: deletedAtMs.map(TodoRules.date(milliseconds:)),
            originDayKey: originDayKey
        )
    }
}

/// `todo_sync` 호출 한 번의 인자.
struct TodoSyncRequest: Equatable, Sendable {
    let changes: [TodoSyncWireItem]
    /// 마지막 watermark. nil 이면 서버가 전체를 돌려준다(full).
    let sinceMs: Int64?

    private struct Body: Encodable {
        let changes: [TodoSyncWireItem]
        let sinceMs: Int64?
        enum CodingKeys: String, CodingKey {
            case changes = "p_changes"
            case sinceMs = "p_since_ms"
        }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(changes, forKey: .changes)
            // null 을 싣는다 — 보낸 키 집합이 늘 같아야 PostgREST 함수 해석이 상태에 따라 갈리지 않는다.
            try c.encode(sinceMs, forKey: .sinceMs)
        }
    }

    /// PostgREST `POST /rest/v1/rpc/todo_sync` 본문: `{"p_changes":[…],"p_since_ms":int|null}`.
    func rpcBody() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(Body(changes: changes, sinceMs: sinceMs))
    }

    /// `p_changes` 배열만(JSON). psql 왕복 프로브가 `select public.todo_sync('<이 값>'::jsonb, <sinceMs>)` 로 쓴다.
    func changesJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(changes)
    }
}

/// 거절 한 건 `{"id": 원문|null, "reason": "invalid"|"quota"}`.
struct TodoSyncRejection: Decodable, Equatable, Sendable {
    var id: String?
    var reason: String?

    enum CodingKeys: String, CodingKey { case id, reason }

    init(id: String?, reason: String?) {
        self.id = id
        self.reason = reason
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try? c.decodeIfPresent(String.self, forKey: .id)
        reason = try? c.decodeIfPresent(String.self, forKey: .reason)
    }
}

/// `todo_sync` 응답. `{"status":"ok","items":[…],"watermark_ms":int,"rejected":[…],"full":bool}` ·
/// `{"status":"unauthorized"}` · `{"status":"invalid"}` · `{"status":"too_many","max":500}`. 필드는 전부 Optional.
struct TodoSyncResponse: Decodable, Equatable, Sendable {
    var status: String?
    var items: [TodoSyncWireItem]?
    var watermarkMs: Int64?
    var rejected: [TodoSyncRejection]?
    var full: Bool?
    var max: Int?

    enum CodingKeys: String, CodingKey {
        case status, items, rejected, full, max
        case watermarkMs = "watermark_ms"
    }

    init(
        status: String?, items: [TodoSyncWireItem]? = nil, watermarkMs: Int64? = nil,
        rejected: [TodoSyncRejection]? = nil, full: Bool? = nil, max: Int? = nil
    ) {
        self.status = status
        self.items = items
        self.watermarkMs = watermarkMs
        self.rejected = rejected
        self.full = full
        self.max = max
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = try? c.decodeIfPresent(String.self, forKey: .status)
        items = try? c.decodeIfPresent([TodoSyncWireItem].self, forKey: .items)
        watermarkMs = try? c.decodeIfPresent(Int64.self, forKey: .watermarkMs)
        rejected = try? c.decodeIfPresent([TodoSyncRejection].self, forKey: .rejected)
        full = try? c.decodeIfPresent(Bool.self, forKey: .full)
        max = try? c.decodeIfPresent(Int.self, forKey: .max)
    }

    /// 원문 바이트 → 응답. PostgREST 전송이든 psql 전송이든 **이 함수 하나로** 읽는다.
    static func decode(_ data: Data) throws -> TodoSyncResponse {
        try JSONDecoder().decode(TodoSyncResponse.self, from: data)
    }

    /// 병합할 수 있는 응답이면 그 값. status 가 ok 가 아니거나 뼈대(items·watermark)가 없으면 nil — 반쪽 응답으로
    /// pending 을 비우거나 watermark 를 올리면 그 사이 변경을 영원히 놓친다.
    ///
    /// 행 하나라도 못 읽었으면 **full 을 끈다**. full 병합은 "서버에 없는 로컬 항목"을 지우는데, 못 읽은 행은
    /// 서버에 있는데도 없는 것으로 보여 멀쩡한 할 일을 지운다.
    func mergeableResult() -> TodoSyncResult? {
        guard status == "ok", let items, let watermarkMs else { return nil }
        let decoded = items.compactMap { $0.todoItem() }
        let everyRowRead = decoded.count == items.count
        return TodoSyncResult(
            items: decoded,
            rejectedIDs: Set((rejected ?? []).compactMap { $0.id.flatMap(UUID.init(uuidString:)) }),
            full: (full ?? false) && everyRowRead,
            watermarkMs: watermarkMs
        )
    }
}

/// 병합에 들어가는 응답(검증을 통과한 값).
struct TodoSyncResult: Equatable, Sendable {
    let items: [TodoItem]
    let rejectedIDs: Set<UUID>
    let full: Bool
    let watermarkMs: Int64
}

/// 보낸 요청 한 건의 스냅샷. 응답을 합칠 때 이 값을 같이 넘긴다.
struct TodoSyncOutgoing: Equatable, Sendable {
    /// 찍을 때의 `TodoListStore.fileGeneration`(계정 전환 뒤 늦은 응답을 버리는 기준).
    let fileGeneration: Int
    let request: TodoSyncRequest
    /// id → 보낸 updatedAtMs.
    let sent: [UUID: Int64]
}

// MARK: - 전송 계층(주입)

/// 전송이 던지는 분류. 이 밖의 오류는 전부 "일시 실패"(pending 유지 · 다음 기회에 재시도)로 읽는다.
enum TodoSyncTransportError: Error, Equatable, Sendable {
    /// 서버에 `todo_sync` 가 아직 없다(HTTP 404 / PGRST202). 조용히 멈추고 pending 을 둔다.
    case functionMissing
    /// 지금 세션이 요청한 계정이 아니다(전환 중). 보내지 않는다 — 앞 계정의 할 일이 새 계정에 올라가면 안 된다.
    case accountMismatch
}

/// `todo_sync` 를 부르는 방법. **여기를 갈아 끼우면 엔진은 그대로다** — 프로덕션은 PostgREST(세션 갱신 포함),
/// 테스트는 가짜, 왕복 프로브(X2)는 psql 로 실제 함수를 부른다.
///
/// 구현 규약:
/// · `userID` 계정으로만 보낸다. 지금 세션이 다른 계정이면 보내지 말고 `.accountMismatch` 를 던진다.
/// · 서버가 `{"status":"unauthorized"}` 를 주면 세션을 갱신해 다시 시도하고(프로덕션은 `withSessionRetry`),
///   그래도 안 되면 던지거나 그 응답을 그대로 돌려준다(엔진은 ok 가 아닌 응답을 병합하지 않는다).
/// · 함수가 없으면 `.functionMissing`.
@MainActor
protocol TodoSyncTransport: AnyObject {
    func todoSync(userID: String, request: TodoSyncRequest) async throws -> TodoSyncResponse
}

// MARK: - 시계·타이머(주입)

/// 취소 가능한 예약 하나.
@MainActor
protocol TodoSyncCancellable: AnyObject {
    func cancel()
}

/// 디바운스·주기 타이머. 테스트는 수동으로 시간을 미는 구현을 꽂는다(실제 1.5초·5분을 기다리지 않는다).
@MainActor
protocol TodoSyncScheduler: AnyObject {
    func schedule(after seconds: Double, _ action: @escaping @MainActor () -> Void) -> any TodoSyncCancellable
}

/// 프로덕션 타이머(Task.sleep). 취소 검사가 없으면 cancel() 이 곧 즉시 실행이 된다.
@MainActor
final class TodoSyncTaskScheduler: TodoSyncScheduler {
    private final class Handle: TodoSyncCancellable {
        let task: Task<Void, Never>
        init(_ task: Task<Void, Never>) { self.task = task }
        func cancel() { task.cancel() }
    }

    func schedule(after seconds: Double, _ action: @escaping @MainActor () -> Void) -> any TodoSyncCancellable {
        Handle(Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            action()
        })
    }
}

// MARK: - 엔진

/// 왜 맞추는가(진단·스로틀 판정용).
enum TodoSyncReason: String, Equatable, Sendable {
    case launch, login, boardOpened, edit, periodic, wake
}

/// 마지막 시도의 결말(진단 · 테스트 판정 지점). 사용자 화면에는 띄우지 않는다 — 동기화는 조용한 기능이다.
enum TodoSyncOutcome: Equatable, Sendable {
    case synced
    /// 서버에 함수가 아직 없다(404/PGRST202). pending 유지.
    case serverMissing
    /// 네트워크·세션·디코드 실패. pending 유지.
    case failed
    /// 서버가 ok 가 아닌 응답을 줬다(unauthorized·invalid·too_many 등). pending 유지.
    case refused(String?)
    /// 응답이 왔지만 그 사이 계정(파일)이 바뀌어 버렸다.
    case discardedStale
}

/// 할 일 동기화 엔진. **한 번에 하나만 돈다** — 도는 중에 또 부르면 끝난 뒤 한 번 더 돈다(몇 번을 불러도 한 번).
@MainActor
final class TodoSync {
    /// 고친 뒤 이만큼 조용하면 보낸다. 타이핑·연속 체크마다 요청이 나가지 않게.
    static let debounceSeconds: Double = 1.5
    /// 로그인 중 이 간격으로 맞춘다(다른 기기의 변경을 받으려고).
    static let periodicSeconds: Double = 300
    /// 한 요청에 싣는 최대 항목 수(서버 상한 500 — 넘으면 서버가 통째로 too_many).
    static let batchLimit = 500
    /// 서버에 함수가 없다고 확인한 뒤 이 시간 동안은 **고칠 때·보드 열 때** 다시 치지 않는다(주기·깨어남·로그인은 친다).
    /// db push 보다 앱이 먼저 나간 창에서 체크 한 번마다 404 를 쏘지 않게.
    static let serverMissingCooldownSeconds: Double = 300

    let list: TodoListStore
    private let transport: any TodoSyncTransport
    private let scheduler: any TodoSyncScheduler
    private let clock: () -> Date

    /// 동기화 대상 계정. nil = 로그아웃(`todos.local.json`) — 맞추지 않는다.
    private(set) var userID: String?
    private(set) var isRunning = false
    private(set) var lastOutcome: TodoSyncOutcome?
    /// 전송을 실제로 부른 횟수(진단).
    private(set) var transportCallCount = 0
    /// 지금 도는 작업(테스트가 끝나기를 기다리는 문).
    private(set) var runTask: Task<Void, Never>?

    private var rerunRequested = false
    private var debounce: (any TodoSyncCancellable)?
    private var periodic: (any TodoSyncCancellable)?
    private var serverMissingAt: Date?

    init(
        list: TodoListStore,
        transport: any TodoSyncTransport,
        scheduler: any TodoSyncScheduler = TodoSyncTaskScheduler(),
        clock: @escaping () -> Date = { Date() }
    ) {
        self.list = list
        self.transport = transport
        self.scheduler = scheduler
        self.clock = clock
    }

    /// 지금 파일 그대로 이 계정으로 맞추기 시작한다(실행 직후 — 파일은 이미 그 계정 것으로 열려 있다).
    func activate(userID: String?, reason: TodoSyncReason = .launch) {
        self.userID = Self.normalizedUserID(userID)
        restartTimers()
        requestSync(reason)
    }

    /// 계정이 바뀌었다. 예약을 전부 거두고 → 파일을 바꾸고(세대가 올라 진행 중 응답은 버려진다) → 새 계정이면 곧바로 맞춘다.
    func switchAccount(userID: String?, fileURL: URL) {
        debounce?.cancel()
        debounce = nil
        rerunRequested = false
        serverMissingAt = nil
        self.userID = Self.normalizedUserID(userID)
        list.switchFile(to: fileURL)
        restartTimers()
        requestSync(.login)
    }

    /// 사용자가 고쳤다 — 1.5초 디바운스.
    func noteLocalChange() {
        guard userID != nil else { return }
        debounce?.cancel()
        debounce = scheduler.schedule(after: Self.debounceSeconds) { [weak self] in
            guard let self else { return }
            self.debounce = nil
            self.requestSync(.edit)
        }
    }

    /// 맞춰 달라. 로그아웃이면 아무것도 안 한다. 도는 중이면 끝난 뒤 한 번 더.
    func requestSync(_ reason: TodoSyncReason) {
        guard userID != nil else { return }
        if reason == .edit || reason == .boardOpened,
           let missingAt = serverMissingAt,
           clock().timeIntervalSince(missingAt) < Self.serverMissingCooldownSeconds {
            return
        }
        if isRunning {
            rerunRequested = true
            return
        }
        isRunning = true
        runTask = Task { @MainActor [weak self] in
            await self?.drain()
        }
    }

    private func drain() async {
        repeat {
            rerunRequested = false
            await runOnce()
        } while rerunRequested && userID != nil
        isRunning = false
    }

    private func restartTimers() {
        periodic?.cancel()
        periodic = nil
        guard userID != nil else {
            debounce?.cancel()
            debounce = nil
            return
        }
        armPeriodic()
    }

    private func armPeriodic() {
        periodic = scheduler.schedule(after: Self.periodicSeconds) { [weak self] in
            guard let self, self.userID != nil else { return }
            self.requestSync(.periodic)
            self.armPeriodic()
        }
    }

    /// 한 바퀴: pending 을 500개씩 나눠(없으면 빈 요청 하나 — 받기만) 차례로 보내고 합친다.
    /// 어느 요청이든 실패하면 **거기서 멈춘다**(pending 은 파일에 그대로 남아 다음 기회에 다시 실린다).
    private func runOnce() async {
        guard let userID else { return }
        let ids = list.pendingIDs.sorted { $0.uuidString < $1.uuidString }
        var batches: [[UUID]] = stride(from: 0, to: ids.count, by: Self.batchLimit).map {
            Array(ids[$0..<min($0 + Self.batchLimit, ids.count)])
        }
        if batches.isEmpty { batches = [[]] }

        // 계정 전환은 응답을 기다리는 동안에만 끼어들 수 있다(메인 액터라 그 밖에서는 이 루프가 끊기지 않는다). 그 경우
        // `applySync` 가 세대 불일치로 false 를 돌려주고 여기서 멈추므로, 남은 묶음을 새 계정 파일에서 찍어 앞 계정으로
        // 보내는 일은 없다 — 세대 판정은 스토어의 그 문 하나에만 둔다(두 곳에 두면 한쪽을 지워도 초록이다).
        for batch in batches {
            let outgoing = list.makeSyncRequest(ids: batch)
            transportCallCount += 1
            let response: TodoSyncResponse
            do {
                response = try await transport.todoSync(userID: userID, request: outgoing.request)
            } catch TodoSyncTransportError.functionMissing {
                serverMissingAt = clock()
                lastOutcome = .serverMissing
                return
            } catch {
                lastOutcome = .failed
                return
            }
            guard let result = response.mergeableResult() else {
                lastOutcome = .refused(response.status)
                return
            }
            guard list.applySync(result, for: outgoing) else {
                lastOutcome = .discardedStale
                return
            }
        }
        serverMissingAt = nil
        lastOutcome = .synced
    }

    private static func normalizedUserID(_ userID: String?) -> String? {
        guard let userID, !userID.isEmpty else { return nil }
        return userID
    }
}

// MARK: - 조정자(언제 맞추나 · 계정 전환)

/// 동기화 시점과 계정 전환을 잇는 **유일한** 배선. AppDelegate 안 private 메서드로 두면 앱을 띄우지 않고는 한 줄도 검증할 수
/// 없다(`TodoBoardWiring` 을 밖으로 꺼낸 것과 같은 이유) — 테스트는 이 타입을 그대로 쓴다.
///
/// 맞추는 때(명세 A4-5): 실행·로그인 직후 · 보드를 열 때 · 고친 뒤 1.5초 · 로그인 중 5분마다 · 잠에서 깰 때.
@MainActor
final class TodoSyncCoordinator {
    let sync: TodoSync
    private weak var board: CheckTodoBoardController?
    private let userID: @MainActor () -> String?
    private let fileURL: (String?) -> URL
    private let wakeNotifications: NotificationCenter?
    private var lastUserID: String?
    /// 깨어남 구독 토큰. 조정자는 앱 수명 동안 살고 구독 블록은 self 를 weak 로만 잡으므로 따로 떼지 않는다.
    private var wakeToken: NSObjectProtocol?
    private var started = false

    /// - Parameters:
    ///   - userID: 지금 세션의 사용자 id(관찰 가능한 값을 읽어야 계정 전환을 스스로 알아챈다).
    ///   - fileURL: 계정 → 할 일 파일(프로덕션은 `TodoFileStore.defaultURL(userID:)`).
    ///   - wakeNotifications: 깨어남 통지가 오는 곳(프로덕션은 NSWorkspace 의 센터, 테스트는 자기 센터).
    init(
        sync: TodoSync,
        board: CheckTodoBoardController?,
        userID: @escaping @MainActor () -> String?,
        fileURL: @escaping (String?) -> URL,
        wakeNotifications: NotificationCenter?
    ) {
        self.sync = sync
        self.board = board
        self.userID = userID
        self.fileURL = fileURL
        self.wakeNotifications = wakeNotifications
    }

    /// 배선을 건다(멱등).
    func start() {
        guard !started else { return }
        started = true
        let list = sync.list
        list.onLocalChange = { [weak self] in self?.sync.noteLocalChange() }
        list.syncProtectedIDs = { [weak self] in self?.board?.syncProtectedIDs ?? [] }
        board?.onOpened = { [weak self] in self?.sync.requestSync(.boardOpened) }
        if let wakeNotifications {
            wakeToken = wakeNotifications.addObserver(
                forName: NSWorkspace.didWakeNotification, object: nil, queue: nil
            ) { [weak self] _ in
                Task { @MainActor in self?.sync.requestSync(.wake) }
            }
        }

        let current = userID()
        lastUserID = current
        let expected = fileURL(current)
        if list.fileURL != expected {
            // 목록을 만든 뒤 세션이 바뀌었다(실행 직후 복구·로그아웃). 그 계정 파일로 바꿔 연다.
            board?.resetForAccountSwitch()
            sync.switchAccount(userID: current, fileURL: expected)
        } else {
            sync.activate(userID: current, reason: .launch)
        }
        arm()
    }

    /// 세션 사용자가 바뀌었는지 보고, 바뀌었으면 보드 입력 상태를 정리하고 파일·동기화 대상을 바꾼다.
    /// (관찰 콜백이 부르는 문. 테스트도 이 문으로 직접 부를 수 있다.)
    func accountMayHaveChanged() {
        let current = userID()
        guard current != lastUserID else { return }
        lastUserID = current
        // 되돌리기 창의 삭제는 **앞 계정 파일에** 확정하고, 편집·초안은 버린다(다음 사람이 앞 사람의 적다 만 글을 보면 안 된다).
        board?.resetForAccountSwitch()
        sync.switchAccount(userID: current, fileURL: fileURL(current))
    }

    private func arm() {
        withObservationTracking {
            _ = userID()
        } onChange: { [weak self] in
            // onChange 는 값이 바뀌기 **직전**(willSet)에 온다 — 한 틱 뒤 메인 액터에서 새 값을 읽는다.
            Task { @MainActor in
                guard let self else { return }
                self.accountMayHaveChanged()
                self.arm()
            }
        }
    }
}
