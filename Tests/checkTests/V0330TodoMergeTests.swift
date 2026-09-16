import Foundation
import Testing
@testable import check

// MARK: - v0.3.30 할 일 동기화 ② 병합 규칙(순수) · 멱등 · 두 기기 수렴
//
// 병합 규칙은 `TodoRules.mergedSync` 하나다. 표로 한 줄씩 못 박고, 속성 두 개로 전체를 흔든다:
// · 멱등 — 같은 응답을 두 번 합쳐도 결과(items·pending)가 같다.
// · 수렴 — 두 기기가 무작위 순서로 고치고 맞추는 것을 **서버 LWW 모형**(아래 `TodoSyncV0330Server`, 계약 1.2 를 옮긴 것)과
//   함께 돌리면 끝에 두 기기와 서버가 같은 값에 선다.

// MARK: 서버 모형(계약 1.2)

/// `todo_sync` 의 Swift 모형. **실서버 왕복은 X2(psql) 몫**이고, 이건 엔진·병합을 검증하기 위한 참조 구현이다 —
/// 계약 문장을 그대로 옮겼다(검증 · 미래 시각 누름 · quota · LWW · since−60초 겹침 · 이번 id 의 현재 행 · full 80일).
@MainActor
final class TodoSyncV0330Server {
    struct Row: Equatable {
        var item: TodoSyncWireItem
        var serverUpdatedMs: Int64
    }

    /// userID → 소문자 id → 행
    private(set) var rows: [String: [String: Row]] = [:]
    /// 서버 '지금'(트랜잭션 시각). 테스트가 민다.
    var nowMs: Int64
    var quota = 5000
    private(set) var callCount = 0

    init(nowMs: Int64) {
        self.nowMs = nowMs
    }

    func respond(userID: String, request: TodoSyncRequest) -> TodoSyncResponse {
        callCount += 1
        let now = nowMs
        guard request.changes.count <= 500 else { return TodoSyncResponse(status: "too_many", max: 500) }
        var table = rows[userID] ?? [:]
        var rejected: [TodoSyncRejection] = []
        var validIDs: [String] = []
        for change in request.changes {
            guard let rawID = change.id, let uuid = UUID(uuidString: rawID),
                  let title = change.title, !Self.isBlankTitle(title),
                  // 서버 char_length 는 코드 포인트를 센다(글자 수로 세면 이모지 제목을 실서버와 달리 받아 준다 — X2 S15 heavyTitle).
                  title.unicodeScalars.count <= 1000,
                  let created = change.createdAtMs, created >= 0,
                  let updated = change.updatedAtMs, updated >= 0,
                  (change.completedAtMs ?? 0) >= 0, (change.deletedAtMs ?? 0) >= 0,
                  let day = change.originDayKey, day.count == 8, day.allSatisfy({ $0.isASCII && $0.isNumber })
            else {
                rejected.append(TodoSyncRejection(id: change.id, reason: "invalid"))
                continue
            }
            let id = uuid.uuidString.lowercased()
            func clamp(_ value: Int64?) -> Int64? { value.map { $0 > now + 300_000 ? now : $0 } }
            let incoming = TodoSyncWireItem(
                id: id, title: title, createdAtMs: clamp(created), updatedAtMs: clamp(updated),
                completedAtMs: clamp(change.completedAtMs), deletedAtMs: clamp(change.deletedAtMs), originDayKey: day
            )
            if table[id] == nil, table.count >= quota {
                rejected.append(TodoSyncRejection(id: change.id, reason: "quota"))
                continue
            }
            validIDs.append(id)
            if let existing = table[id], (incoming.updatedAtMs ?? 0) <= (existing.item.updatedAtMs ?? 0) {
                continue                                    // 같거나 작으면 서버 것 유지
            }
            table[id] = Row(item: incoming, serverUpdatedMs: now)
        }
        rows[userID] = table
        let eightyDays: Int64 = 80 * 86_400_000
        // 미래 since 도 full(S2 최종 SQL 이 명세 식에 더한 안전 규칙 — X2 S15 futureSince).
        let full = request.sinceMs.map { $0 < now - eightyDays || $0 > now } ?? true
        var picked: [String: Row] = [:]
        if full {
            picked = table
        } else if let since = request.sinceMs {
            for (id, row) in table where row.serverUpdatedMs >= since - 60_000 { picked[id] = row }
            for id in validIDs { if let row = table[id] { picked[id] = row } }
        }
        return TodoSyncResponse(
            status: "ok",
            items: picked.keys.sorted().compactMap { picked[$0]?.item },
            watermarkMs: now,
            rejected: rejected,
            full: full
        )
    }

    /// 서버의 "공백뿐인 제목" 정규식 `^[[:space:]\u0085\u00a0\u1680\u180e\u2000-\u200b\u2028\u2029\u202f\u205f\u3000\ufeff]*$` 와
    /// 같은 집합(하네스 로캘 C 의 [[:space:]] 는 ASCII 공백류). Foundation 의 whitespacesAndNewlines 는 U+200B·U+180E·U+FEFF 를
    /// 공백으로 안 봐 실서버가 거절하는 제목을 받아 줬다(X2 S15 cfOnlyTitle).
    private static func isBlankTitle(_ title: String) -> Bool {
        title.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 0x09...0x0D, 0x20, 0x85, 0xA0, 0x1680, 0x180E, 0x2000...0x200B, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF:
                return true
            default:
                return false
            }
        }
    }

    /// 서버가 들고 있는 이 사용자의 할 일(로컬 모양, id 순).
    func items(for userID: String) -> [TodoItem] {
        (rows[userID] ?? [:]).values.compactMap { $0.item.todoItem() }.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    /// 다른 기기가 직접 쓴 것처럼 행을 넣는다.
    func seed(userID: String, _ item: TodoItem) {
        let wire = TodoSyncWireItem(item: item)
        rows[userID, default: [:]][wire.id!] = Row(item: wire, serverUpdatedMs: nowMs)
    }
}

// MARK: 픽스처

private let base: Int64 = 1_726_500_000_000

private func item(
    _ title: String, id: UUID = UUID(), updated: Int64, completed: Int64? = nil, deleted: Int64? = nil
) -> TodoItem {
    TodoItem(
        id: id, title: title,
        createdAt: TodoRules.date(milliseconds: base),
        updatedAt: TodoRules.date(milliseconds: updated),
        completedAt: completed.map(TodoRules.date(milliseconds:)),
        deletedAt: deleted.map(TodoRules.date(milliseconds:)),
        originDayKey: "20260916"
    )
}

// MARK: 규칙 표

@Test("같은 id — 로컬이 pending 이고 더 새로우면 로컬 유지(pending 유지), 아니면 서버 것(pending 에서 뺌), 같은 ms 는 서버")
func todoMergeLastWriterWinsTable() {
    let id = UUID()
    struct Row { let localMs: Int64; let serverMs: Int64; let pending: Bool; let expectLocal: Bool; let expectPending: Bool }
    let table: [Row] = [
        Row(localMs: base + 20, serverMs: base + 10, pending: true, expectLocal: true, expectPending: true),
        Row(localMs: base + 10, serverMs: base + 20, pending: true, expectLocal: false, expectPending: false),
        Row(localMs: base + 10, serverMs: base + 10, pending: true, expectLocal: false, expectPending: false),
        Row(localMs: base + 20, serverMs: base + 10, pending: false, expectLocal: false, expectPending: false),
        Row(localMs: base + 10, serverMs: base + 20, pending: false, expectLocal: false, expectPending: false),
    ]
    for row in table {
        let local = item("로컬", id: id, updated: row.localMs)
        let server = item("서버", id: id, updated: row.serverMs)
        let result = TodoRules.mergedSync(
            local: [local], pending: row.pending ? [id] : [], sent: [:],
            server: [server], rejected: [], full: false
        )
        #expect(result.items == [row.expectLocal ? local : server], "local \(row.localMs - base) server \(row.serverMs - base) pending \(row.pending)")
        #expect(result.pending.contains(id) == row.expectPending)
    }
}

@Test("보낸 스냅샷 — 응답 시점의 로컬 updatedAtMs 가 보낸 값과 같을 때만 pending 에서 뺀다(보낸 뒤 또 고쳤으면 남는다)")
func todoMergeRemovesPendingOnlyWhenUnchangedSinceSent() {
    let unchanged = item("안 고침", updated: base + 100)
    let editedAgain = item("보낸 뒤 또 고침", updated: base + 150)
    let result = TodoRules.mergedSync(
        local: [unchanged, editedAgain],
        pending: [unchanged.id, editedAgain.id],
        sent: [unchanged.id: base + 100, editedAgain.id: base + 100],
        server: [unchanged, item("보낸 뒤 또 고침(서버엔 옛 값)", id: editedAgain.id, updated: base + 100)],
        rejected: [], full: false
    )
    #expect(!result.pending.contains(unchanged.id))
    #expect(result.pending.contains(editedAgain.id), "응답 전에 또 고친 항목이 pending 에서 빠졌다 — 그 수정은 서버로 영영 안 간다")
    #expect(result.items.first { $0.id == editedAgain.id } == editedAgain, "응답이 방금 고친 로컬 값을 옛 서버 값으로 덮었다")
}

@Test("서버가 미래 시각을 눌러 더 작은 값으로 돌려줘도, 안 고친 항목은 서버 값으로 수렴한다")
func todoMergeConvergesWhenServerClampedFutureTime() {
    let future = item("시계가 10분 빠른 맥", updated: base + 600_000)
    let clamped = item("시계가 10분 빠른 맥", id: future.id, updated: base)
    let result = TodoRules.mergedSync(
        local: [future], pending: [future.id], sent: [future.id: future.updatedAtMs],
        server: [clamped], rejected: [], full: false
    )
    #expect(result.items == [clamped])
    #expect(result.pending.isEmpty)
}

@Test("rejected — pending 에서 빼고 로컬엔 남긴다(full 이어도 안 지운다). 보낸 뒤 또 고쳤으면 다시 보낼 수 있게 남긴다")
func todoMergeRejectedStaysLocal() {
    let rejected = item("거절된 줄", updated: base + 5)
    let rejectedButEdited = item("거절됐지만 그새 고친 줄", updated: base + 9)
    for full in [false, true] {
        let result = TodoRules.mergedSync(
            local: [rejected, rejectedButEdited], pending: [rejected.id, rejectedButEdited.id],
            sent: [rejected.id: base + 5, rejectedButEdited.id: base + 7],
            server: [], rejected: [rejected.id, rejectedButEdited.id], full: full
        )
        #expect(result.items == [rejected, rejectedButEdited], "full=\(full)")
        #expect(!result.pending.contains(rejected.id))
        #expect(result.pending.contains(rejectedButEdited.id))
    }
}

@Test("full — 서버에 없고 pending 도 아닌 로컬 항목만 지운다. 서버에만 있는 항목은 붙고, full 이 아니면 아무것도 안 지운다")
func todoMergeFullDeletesOnlyNonPendingLocalOnly() {
    let synced = item("서버가 정리한 줄", updated: base + 1)
    let newLocal = item("아직 안 보낸 새 줄", updated: base + 2)
    let onBoth = item("양쪽에 있는 줄", updated: base + 3)
    let serverOnly = item("다른 기기가 만든 줄", updated: base + 4)

    let full = TodoRules.mergedSync(
        local: [synced, newLocal, onBoth], pending: [newLocal.id], sent: [:],
        server: [onBoth, serverOnly], rejected: [], full: true
    )
    #expect(full.items == [newLocal, onBoth, serverOnly])
    #expect(full.pending == [newLocal.id])

    let partial = TodoRules.mergedSync(
        local: [synced, newLocal, onBoth], pending: [newLocal.id], sent: [:],
        server: [onBoth, serverOnly], rejected: [], full: false
    )
    #expect(partial.items == [synced, newLocal, onBoth, serverOnly])
}

@Test("로컬에 없는 pending id 는 버린다 · 보호 중인 id 는 로컬 그대로 두고 pending 으로 되돌린다")
func todoMergeGhostPendingAndProtection() {
    let ghost = UUID()
    let editing = item("편집 중", updated: base + 1)
    let tombstone = item("다른 기기에서 지움", id: editing.id, updated: base + 50, deleted: base + 50)
    let result = TodoRules.mergedSync(
        local: [editing], pending: [ghost], sent: [:], server: [tombstone], rejected: [], full: false,
        protected: [editing.id]
    )
    #expect(result.items == [editing])
    #expect(result.pending == [editing.id])
    #expect(result.deferredIDs == [editing.id])

    let purged = TodoRules.mergedSync(
        local: [editing], pending: [], sent: [:], server: [], rejected: [], full: true, protected: [editing.id]
    )
    #expect(purged.items == [editing], "full 정리가 편집 중인 줄을 지웠다")
    #expect(purged.deferredIDs == [editing.id])

    // 바뀔 것이 없으면 미루지도 않는다.
    let same = TodoRules.mergedSync(
        local: [editing], pending: [], sent: [:], server: [editing], rejected: [], full: false, protected: [editing.id]
    )
    #expect(same.deferredIDs.isEmpty && same.pending.isEmpty)
}

// MARK: 속성 — 멱등

@Test("같은 응답을 두 번 합쳐도 결과가 같다(무작위 3000건)")
func todoMergeIsIdempotent() {
    var rng = TodoSyncV0330RNG(seed: 0xA4_1DE)
    let pool = (0..<8).map { _ in UUID() }
    func randomItem(_ id: UUID) -> TodoItem {
        let deleted: Int64? = Bool.random(using: &rng) ? nil : base + Int64.random(in: 0...40, using: &rng)
        return item("t\(Int.random(in: 0...3, using: &rng))", id: id, updated: base + Int64.random(in: 0...40, using: &rng), deleted: deleted)
    }
    for round in 0..<3000 {
        let local = pool.filter { _ in Bool.random(using: &rng) }.map(randomItem)
        let server = pool.filter { _ in Bool.random(using: &rng) }.map(randomItem)
        let pending = Set(pool.filter { _ in Bool.random(using: &rng) })
        var sent: [UUID: Int64] = [:]
        for id in pool where Bool.random(using: &rng) { sent[id] = base + Int64.random(in: 0...40, using: &rng) }
        let rejected = Set(pool.filter { _ in Int.random(in: 0..<6, using: &rng) == 0 })
        let full = Bool.random(using: &rng)
        let protected = Set(pool.filter { _ in Int.random(in: 0..<6, using: &rng) == 0 })

        let once = TodoRules.mergedSync(local: local, pending: pending, sent: sent, server: server, rejected: rejected, full: full, protected: protected)
        let twice = TodoRules.mergedSync(local: once.items, pending: once.pending, sent: sent, server: server, rejected: rejected, full: full, protected: protected)
        #expect(once.items == twice.items && once.pending == twice.pending, "round \(round)")
        if once.items != twice.items || once.pending != twice.pending { return }
    }
}

// MARK: 속성 — 두 기기 수렴

/// 기기 하나(파일·시계·엔진). 전송은 서버 모형에 직접 붙는다. `duringFlight` 가 있으면 **요청이 서버에 반영된 뒤,
/// 응답이 기기에 닿기 전에** 그 편집을 끼워 넣는다("응답 전 재수정").
@MainActor
final class TodoSyncV0330Device {
    /// 시계 상자(목록 init 이 곧바로 시계를 읽으므로 기기보다 먼저 선다).
    final class Clock: @unchecked Sendable {
        var nowMs: Int64
        init(nowMs: Int64) { self.nowMs = nowMs }
    }

    let list: TodoListStore
    let sync: TodoSync
    let transport: TodoSyncV0330Transport
    let clock: Clock
    var duringFlight: (@MainActor () -> Void)?

    var nowMs: Int64 {
        get { clock.nowMs }
        set { clock.nowMs = newValue }
    }

    init(server: TodoSyncV0330Server, userID: String, nowMs: Int64, fileURL: URL = todoSyncV0330TempURL()) {
        let clock = Clock(nowMs: nowMs)
        self.clock = clock
        let list = TodoListStore(fileURL: fileURL, clock: { TodoRules.date(milliseconds: clock.nowMs) })
        self.list = list
        let transport = TodoSyncV0330Transport { _, _ in TodoSyncResponse(status: "invalid") }
        self.transport = transport
        self.sync = TodoSync(list: list, transport: transport, scheduler: TodoSyncV0330Scheduler())
        transport.respond = { [unowned self, server] uid, request in
            let response = server.respond(userID: uid, request: request)
            if let edit = self.duringFlight {
                self.duringFlight = nil
                edit()
            }
            return response
        }
        sync.activate(userID: userID)
    }

    func syncNow() async {
        sync.requestSync(.periodic)
        await todoSyncV0330Idle(sync)
    }
}

@MainActor
@Test("두 기기가 무작위로 고치고 맞춰도(응답 전 재수정·삭제 vs 수정·되돌리기 포함) 끝에 두 기기와 서버가 같은 값에 선다")
func todoTwoDevicesConvergeWithServerLWW() async throws {
    for seed in UInt64(1)...12 {
        var rng = TodoSyncV0330RNG(seed: seed &* 7919)
        let server = TodoSyncV0330Server(nowMs: base)
        let a = TodoSyncV0330Device(server: server, userID: "u1", nowMs: base)
        let b = TodoSyncV0330Device(server: server, userID: "u1", nowMs: base + 90_000)   // B 시계는 1.5분 빠르다
        await todoSyncV0330Idle(a.sync)
        await todoSyncV0330Idle(b.sync)

        func randomEdit(_ device: TodoSyncV0330Device) {
            let ids = device.list.items.map(\.id)
            switch Int.random(in: 0..<6, using: &rng) {
            case 0:
                device.list.add("할 일 \(Int.random(in: 0...999, using: &rng))")
            case 1:
                if let id = ids.randomElement(using: &rng) { device.list.toggleDone(id) }
            case 2:
                if let id = ids.randomElement(using: &rng) { device.list.rename(id, to: "고침 \(Int.random(in: 0...999, using: &rng))") }
            case 3:
                if let id = ids.randomElement(using: &rng) { device.list.delete(id) }
            case 4:
                if let id = ids.randomElement(using: &rng) { device.list.undoDelete(id) }
            default:
                device.list.add("또 \(Int.random(in: 0...999, using: &rng))")
            }
        }

        for _ in 0..<150 {
            let step = Int64.random(in: 1...4_000, using: &rng)
            server.nowMs += step
            a.nowMs += step
            b.nowMs += step
            let device = Bool.random(using: &rng) ? a : b
            switch Int.random(in: 0..<10, using: &rng) {
            case 0..<6:
                randomEdit(device)
            case 6..<8:
                await device.syncNow()
            default:
                device.duringFlight = { randomEdit(device) }
                await device.syncNow()
            }
        }
        // 조용해진 뒤 번갈아 맞춘다.
        for device in [a, b, a, b] {
            server.nowMs += 1_000
            a.nowMs += 1_000
            b.nowMs += 1_000
            await device.syncNow()
        }
        let sortedA = a.list.items.sorted { $0.id.uuidString < $1.id.uuidString }
        let sortedB = b.list.items.sorted { $0.id.uuidString < $1.id.uuidString }
        #expect(sortedA == sortedB, "seed \(seed): 두 기기가 갈렸다")
        #expect(sortedA == server.items(for: "u1"), "seed \(seed): 기기와 서버가 갈렸다")
        #expect(a.list.pendingIDs.isEmpty && b.list.pendingIDs.isEmpty, "seed \(seed): 끝났는데 보낼 것이 남았다")
        #expect(!sortedA.isEmpty)
        if sortedA != sortedB || sortedA != server.items(for: "u1") { return }
    }
}
