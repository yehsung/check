import Foundation
import Testing
@testable import check

// MARK: - v0.3.30 할 일 동기화 ④ 거절 항목 붙잡기(부록 B-3 · X2 F1·F2)
//
// 서버가 `rejected` 로 돌려준 id 는 pending 에서 빼고 **붙잡는다**(`heldRejectedIDs`):
// · 붙잡힌 id 는 서버 항목이 와도 로컬 사본을 덮지 않는다 — X2 F1: 60초 겹침 창 안이면 서버가 그 행(옛 값)을 돌려주고,
//   예전 병합은 "pending 이 아니면 서버 것"으로 거절된 수정을 곧바로 옛 값으로 되돌렸다(창 밖이면 남아 시점에 따라 갈렸다).
// · full 동기화에서도 지우지 않는다 — X2 F2: 예전 응답에서 거절된 id 는 어디에도 기억되지 않아 81일 뒤 full 이 조용히 지웠다
//   (quota 로 거절된 새 줄도 같은 길).
// · 사용자가 그 줄을 다시 고치면 pending 으로 돌아가고 붙잡기에서 빠진다. 삭제·로컬 정리로 줄이 사라지면 붙잡기에서도 뺀다.
// · 파일 2세대의 **선택 필드**다(없으면 빈 목록) — 옛 앱·옛 파일과 서로 읽힌다.
//
// 기기에서 거절될 수정이 새로 생기는 길은 막혀 있다(제목 상한). 그래서 거절될 수정은 **파일로 주입**한다 — 0.3.29 로 내렸다
// 다시 올린 맥이 쓴 줄, 서버 규칙이 나중에 좁아진 경우와 같은 모양이다(주입 뒤 `reload`, 앱 실행 때 읽는 길 그대로).

private let base: Int64 = 1_726_500_000_000
private let userA = "11111111-1111-4111-8111-111111111111"

/// 글자 100 · 코드 포인트 1100 — 기기 글자 상한 안, 서버 코드 포인트 상한(1000) 밖.
private let heavyTitle: String = {
    let marks = (0x0363..<0x036D).compactMap { Unicode.Scalar($0) }.map(String.init).joined()
    return String(repeating: "x" + marks, count: 100)
}()

private struct HeldTestError: Error, CustomStringConvertible {
    let description: String
}

private func row(_ title: String, id: UUID = UUID(), updated: Int64, deleted: Int64? = nil) -> TodoItem {
    TodoItem(
        id: id, title: title,
        createdAt: TodoRules.date(milliseconds: base),
        updatedAt: TodoRules.date(milliseconds: updated),
        deletedAt: deleted.map(TodoRules.date(milliseconds:)),
        originDayKey: "20260916"
    )
}

/// 파일에 "서버가 거절할 수정"을 적고 다시 읽는다(보낼 것에 넣는다 · watermark 는 그대로 — 증분 동기화 창을 유지한다).
@MainActor
func todoHeldInjectEdit(_ list: TodoListStore, id: UUID, title: String, updatedMs: Int64) throws {
    var file = try TodoFileStore.load(from: list.fileURL)
    guard let index = file.items.firstIndex(where: { $0.id == id }) else {
        throw HeldTestError(description: "주입할 줄이 파일에 없다")
    }
    file.items[index].title = title
    file.items[index].updatedAt = TodoRules.date(milliseconds: updatedMs)
    if !file.sync.pendingIDs.contains(id) { file.sync.pendingIDs.append(id) }
    try TodoFileStore.save(file, to: list.fileURL)
    list.reload()
}

// MARK: F1 — 거절된 수정이 서버의 옛 행에 덮이지 않는다

@Test("F1 순수 — 거절된 수정과 같은 응답에 서버의 옛 행이 와도(60초 겹침) 로컬 수정이 남고 pending 에서 빠진다, 두 번 합쳐도 같다")
func todoHeldRejectedEditSurvivesReturnedServerRow() {
    let id = UUID()
    let old = row("올라간 줄", id: id, updated: base)
    let edit = row(heavyTitle, id: id, updated: base + 10_000)
    for full in [false, true] {
        for protected: Set<UUID> in [[], [id]] {
            let once = TodoRules.mergedSync(
                local: [edit], pending: [id], sent: [id: edit.updatedAtMs],
                server: [old], rejected: [id], full: full, protected: protected
            )
            #expect(once.items == [edit], "full=\(full) protected=\(protected.count): 거절된 수정이 서버 옛 값으로 되돌아갔다")
            #expect(once.pending.isEmpty, "full=\(full): 서버가 영원히 거절할 수정을 다시 보낼 것으로 남겼다")
            #expect(once.deferredIDs.isEmpty, "붙잡은 줄을 보호 미룸으로 다시 보내려 했다")
            #expect(once.heldRejectedIDs == [id], "full=\(full): 거절된 id 를 붙잡지 않았다")
            let twice = TodoRules.mergedSync(
                local: once.items, pending: once.pending, sent: [id: edit.updatedAtMs],
                server: [old], rejected: [id], full: full, held: once.heldRejectedIDs, protected: protected
            )
            #expect(twice == once, "full=\(full): 멱등이 깨졌다")
            // 다음 응답(이번엔 보내지도 거절하지도 않았다)에 옛 행이 또 와도 — 붙잡기만으로 로컬이 남는다.
            let later = TodoRules.mergedSync(
                local: once.items, pending: once.pending, sent: [:],
                server: [old], rejected: [], full: full, held: once.heldRejectedIDs, protected: protected
            )
            #expect(later.items == [edit] && later.pending.isEmpty && later.heldRejectedIDs == [id], "full=\(full): 다음 응답에서 되돌아갔다")
        }
    }
}

@MainActor
@Test("F1 엔진 — 올라간 줄에 거절될 수정이 생기면 60초 겹침 창 안·밖 모두 로컬에 남고, 다음 맞춤에도 그대로다")
func todoHeldRejectedEditInsideAndOutsideOverlap() async throws {
    for window in ["inside60s", "outside60s"] {
        var nowMs = base
        let server = TodoSyncV0330Server(nowMs: nowMs)
        let transport = TodoSyncV0330Transport { userID, request in server.respond(userID: userID, request: request) }
        let list = TodoListStore(fileURL: todoSyncV0330TempURL(), clock: { TodoRules.date(milliseconds: nowMs) })
        let sync = TodoSync(list: list, transport: transport, scheduler: TodoSyncV0330Scheduler(), clock: { TodoRules.date(milliseconds: nowMs) })
        let x = try #require(list.add("올라간 줄"))
        sync.activate(userID: userA)
        await todoSyncV0330Idle(sync)
        #expect(server.items(for: userA).map(\.title) == ["올라간 줄"])

        if window == "outside60s" {
            // 한 번 더 맞춰 watermark 를 행 쓰기 시각 + 61초로 올린다 → 다음 증분 응답의 겹침 창 밖.
            nowMs += 61_000
            server.nowMs = nowMs
            sync.requestSync(.periodic)
            await todoSyncV0330Idle(sync)
        }
        nowMs += 1_000
        server.nowMs = nowMs
        try todoHeldInjectEdit(list, id: x.id, title: heavyTitle, updatedMs: nowMs)
        #expect(list.pendingIDs == [x.id])
        sync.requestSync(.periodic)
        await todoSyncV0330Idle(sync)

        let last = try #require(transport.requests.last)
        #expect(last.request.changes.map(\.id) == [x.id.uuidString.lowercased()], "\(window): 주입한 수정을 싣지 않았다(검사 공허)")
        #expect(sync.lastOutcome == .synced)
        #expect(list.items.first { $0.id == x.id }?.title == heavyTitle, "\(window): 거절된 수정이 서버 옛 값으로 되돌아갔다(X2 F1)")
        #expect(!list.pendingIDs.contains(x.id), "\(window): 거절된 수정이 보낼 것에 남았다")
        #expect(server.items(for: userA).map(\.title) == ["올라간 줄"], "\(window): 서버 모형이 넘친 제목을 받았다")

        // 겹침 창 안에서 한 번 더 맞춰도(같은 옛 행이 또 온다) 그대로다.
        nowMs += 1_000
        server.nowMs = nowMs
        sync.requestSync(.periodic)
        await todoSyncV0330Idle(sync)
        #expect(list.items.first { $0.id == x.id }?.title == heavyTitle, "\(window): 두 번째 맞춤에서 되돌아갔다")
        #expect(list.heldRejectedIDs == [x.id], "\(window)")
        let reread = TodoListStore(fileURL: list.fileURL, clock: { TodoRules.date(milliseconds: nowMs) })
        #expect(reread.items.first { $0.id == x.id }?.title == heavyTitle && !reread.pendingIDs.contains(x.id), "\(window): 파일에 남지 않았다")
        #expect(reread.heldRejectedIDs == [x.id], "\(window): 붙잡기가 파일에 안 실렸다 — 다시 켜면 옛 행에 덮인다")

        // 다른 기기가 그 줄을 정상 제목으로 더 나중에 고쳤다 → 붙잡힌 동안은 서버 행이 와도 로컬을 덮지 않는다(B-3).
        nowMs += 5_000
        server.nowMs = nowMs
        var elsewhere = try #require(server.items(for: userA).first)
        elsewhere.title = "다른 기기가 고친 줄"
        elsewhere.updatedAt = TodoRules.date(milliseconds: nowMs)
        server.seed(userID: userA, elsewhere)
        sync.requestSync(.periodic)
        await todoSyncV0330Idle(sync)
        #expect(list.items.first { $0.id == x.id }?.title == heavyTitle, "\(window): 붙잡힌 줄이 다른 기기 행에 덮였다")
        #expect(list.heldRejectedIDs == [x.id])

        // 사용자가 다시 고친다 → 붙잡기에서 빠지고 보낼 것으로 돌아가 서버 LWW 로 수렴한다.
        nowMs += 1_000
        server.nowMs = nowMs
        list.rename(x.id, to: "사용자가 다시 고친 줄")
        #expect(list.heldRejectedIDs.isEmpty && list.pendingIDs == [x.id], "\(window): 다시 고쳤는데 붙잡기가 안 풀렸다")
        sync.requestSync(.edit)
        await todoSyncV0330Idle(sync)
        #expect(list.pendingIDs.isEmpty && list.heldRejectedIDs.isEmpty)
        #expect(list.items.sorted { $0.id.uuidString < $1.id.uuidString } == server.items(for: userA), "\(window): 풀린 뒤 서버와 갈렸다")
        #expect(server.items(for: userA).first?.title == "사용자가 다시 고친 줄")
    }
}

// MARK: F2 — 거절돼 로컬에만 남은 새 줄이 full 동기화에서 지워지지 않는다

@MainActor
@Test("F2 엔진 — quota 로 거절된 새 줄(제목은 정상)은 로컬에 남고, 81일 못 맞춘 뒤 full 동기화에서도 남는다")
func todoHeldQuotaRejectedNewItemSurvivesFull() async throws {
    var nowMs = base
    let server = TodoSyncV0330Server(nowMs: nowMs)
    server.quota = 1
    let transport = TodoSyncV0330Transport { userID, request in server.respond(userID: userID, request: request) }
    let list = TodoListStore(fileURL: todoSyncV0330TempURL(), clock: { TodoRules.date(milliseconds: nowMs) })
    let sync = TodoSync(list: list, transport: transport, scheduler: TodoSyncV0330Scheduler(), clock: { TodoRules.date(milliseconds: nowMs) })
    let first = try #require(list.add("첫 줄"))
    sync.activate(userID: userA)
    await todoSyncV0330Idle(sync)
    #expect(server.items(for: userA).map(\.id) == [first.id])

    nowMs += 1_000
    server.nowMs = nowMs
    let over = try #require(list.add("quota 에 걸린 새 줄"))
    sync.requestSync(.edit)
    await todoSyncV0330Idle(sync)
    #expect(list.items.contains { $0.id == over.id })
    #expect(!list.pendingIDs.contains(over.id))
    #expect(server.items(for: userA).map(\.id) == [first.id], "서버 모형이 quota 를 안 걸었다(검사 공허)")

    // 81일 동안 못 맞췄다 → full(서버에 없는 비-pending 로컬 줄을 지우는 응답).
    nowMs += 81 * 86_400_000
    server.nowMs = nowMs
    sync.requestSync(.periodic)
    await todoSyncV0330Idle(sync)
    #expect(sync.lastOutcome == .synced)
    let since = try #require(transport.requests.last?.request.sinceMs)
    #expect(since < nowMs - 80 * 86_400_000, "full 조건이 아니다(검사 공허)")
    #expect(list.items.contains { $0.id == over.id }, "거절돼 로컬에만 남긴 새 줄이 full 동기화에서 조용히 지워졌다(X2 F2)")
    #expect(list.items.contains { $0.id == first.id })
    #expect(!list.pendingIDs.contains(over.id))
    #expect(list.heldRejectedIDs == [over.id])

    // 자리가 나고(quota) 사용자가 그 줄을 다시 고치면 풀려서 올라간다.
    server.quota = 5000
    nowMs += 1_000
    server.nowMs = nowMs
    list.toggleDone(over.id)
    #expect(list.heldRejectedIDs.isEmpty && list.pendingIDs == [over.id])
    sync.requestSync(.edit)
    await todoSyncV0330Idle(sync)
    #expect(server.items(for: userA).contains { $0.id == over.id && $0.isDone }, "다시 고친 줄이 올라가지 않았다")
    #expect(list.pendingIDs.isEmpty && list.heldRejectedIDs.isEmpty)
}

// MARK: 규칙 표

@Test("붙잡기 규칙 표 — 서버 행·full·보호에도 로컬 유지 · 로컬에 없으면 버림 · pending 과 겹치면 pending · 보낸 뒤 또 고친 거절은 붙잡지 않음")
func todoHeldMergeRuleTable() {
    let id = UUID()
    let local = row("붙잡힌 줄", id: id, updated: base + 5)
    let newerServer = row("서버의 더 새 값", id: id, updated: base + 50)
    let tombstone = row("서버의 더 새 값", id: id, updated: base + 50, deleted: base + 50)

    // (a) 붙잡힌 id 에 더 새 서버 행·톰스톤이 와도 로컬 유지, pending 아님, 보호여도 미루지 않음.
    for incoming in [newerServer, tombstone] {
        for protected: Set<UUID> in [[], [id]] {
            let result = TodoRules.mergedSync(
                local: [local], pending: [], sent: [:], server: [incoming], rejected: [], full: false,
                held: [id], protected: protected
            )
            #expect(result.items == [local] && result.pending.isEmpty && result.heldRejectedIDs == [id] && result.deferredIDs.isEmpty,
                    "incoming deleted=\(incoming.deletedAt != nil) protected=\(protected.count)")
        }
    }
    // (b) full 인데 서버에 없다 → 붙잡힌 줄은 남는다(대조: 붙잡지 않은 줄은 지운다).
    let other = row("붙잡히지 않은 줄", updated: base + 6)
    let full = TodoRules.mergedSync(
        local: [local, other], pending: [], sent: [:], server: [], rejected: [], full: true, held: [id]
    )
    #expect(full.items == [local] && full.heldRejectedIDs == [id])

    // (c) 로컬에 없는 붙잡기 id 는 버린다(정리·계정 전환 뒤 찌꺼기).
    let ghost = TodoRules.mergedSync(
        local: [other], pending: [], sent: [:], server: [], rejected: [], full: false, held: [id]
    )
    #expect(ghost.heldRejectedIDs.isEmpty)

    // (d) pending 과 겹치면 pending 이 이긴다 — 보통의 LWW 를 탄다(서버가 더 새로우면 서버 값).
    let overlap = TodoRules.mergedSync(
        local: [local], pending: [id], sent: [:], server: [newerServer], rejected: [], full: false, held: [id]
    )
    #expect(overlap.heldRejectedIDs.isEmpty)
    #expect(overlap.items == [newerServer] && overlap.pending.isEmpty)

    // (e) 거절됐지만 보낸 뒤 또 고쳤다 → 붙잡지 않고 pending(입력 pending 에 없었어도 — 새 값은 서버가 받을 수 있다).
    let editedInFlight = TodoRules.mergedSync(
        local: [local], pending: [], sent: [id: base + 4], server: [], rejected: [id], full: true, held: [id]
    )
    #expect(editedInFlight.heldRejectedIDs.isEmpty && editedInFlight.pending == [id])
    #expect(editedInFlight.items == [local], "보낸 뒤 또 고친 거절 줄을 full 이 지웠다")

    // (f) 거절된 id 가 로컬에 없으면 붙잡지 않는다 — 서버에서 새로 붙는 줄이어도(붙잡을 로컬 수정이 없다).
    for server in [[], [newerServer]] {
        let absent = TodoRules.mergedSync(
            local: [other], pending: [], sent: [:], server: server, rejected: [id], full: false
        )
        #expect(absent.heldRejectedIDs.isEmpty && absent.pending.isEmpty, "server rows \(server.count)")
        #expect(absent.items.map(\.id) == [other.id] + server.map(\.id))
    }

    // (g) 서버가 로컬과 똑같은 행을 돌려줬으면 거절돼도 붙잡지 않는다(지킬 로컬 수정이 없다 — 멱등의 조건).
    let identical = TodoRules.mergedSync(
        local: [local], pending: [id], sent: [id: local.updatedAtMs], server: [local], rejected: [id], full: false
    )
    #expect(identical.heldRejectedIDs.isEmpty && identical.pending.isEmpty && identical.items == [local])
    // (h) 보낸 뒤 또 고친 거절이어도 서버 행이 로컬과 똑같으면 다시 보낼 것이 없다(편집 보호 중이어도 pending 으로 안 넣는다).
    let identicalEdited = TodoRules.mergedSync(
        local: [local], pending: [], sent: [id: base + 4], server: [local], rejected: [id], full: false, protected: [id]
    )
    #expect(identicalEdited.pending.isEmpty && identicalEdited.heldRejectedIDs.isEmpty && identicalEdited.deferredIDs.isEmpty)
}

@Test("F2 순수 — 앞 응답에서 거절돼 붙잡힌 새 줄은 뒤 full 응답에 없어도 남는다(대조: 붙잡기를 넘기지 않으면 지운다)")
func todoHeldEarlierRejectionSurvivesLaterFull() {
    let kept = row("처음부터 서버에 있던 줄", updated: base + 1)
    let fresh = row("quota 에 걸린 새 줄", updated: base + 2)
    let first = TodoRules.mergedSync(
        local: [kept, fresh], pending: [fresh.id], sent: [fresh.id: fresh.updatedAtMs],
        server: [kept], rejected: [fresh.id], full: false
    )
    #expect(first.items == [kept, fresh] && first.pending.isEmpty && first.heldRejectedIDs == [fresh.id])
    let later = TodoRules.mergedSync(
        local: first.items, pending: first.pending, sent: [:], server: [kept], rejected: [], full: true,
        held: first.heldRejectedIDs
    )
    #expect(later.items == [kept, fresh], "앞 응답에서 거절된 새 줄이 full 에서 지워졌다(X2 F2)")
    #expect(later.heldRejectedIDs == [fresh.id])
    let forgotten = TodoRules.mergedSync(
        local: first.items, pending: first.pending, sent: [:], server: [kept], rejected: [], full: true
    )
    #expect(forgotten.items == [kept], "대조 실패 — 붙잡기 없이도 남으면 이 테스트는 붙잡기를 재지 않는다")
}

// MARK: 스토어 · 파일

@MainActor
private func heldStore(
    items: [TodoItem], pending: [UUID] = [], held: [UUID], watermarkMs: Int64? = base, nowMs: Int64 = base + 60_000
) throws -> TodoListStore {
    let url = todoSyncV0330TempURL()
    try TodoFileStore.save(
        TodoFile(items: items, sync: TodoFileSyncState(watermarkMs: watermarkMs, pendingIDs: pending, heldRejectedIDs: held)),
        to: url
    )
    return TodoListStore(fileURL: url, clock: { TodoRules.date(milliseconds: nowMs) })
}

@MainActor
@Test("사용자가 붙잡힌 줄을 다시 고치면(완료·수정·삭제·되돌리기) 붙잡기에서 빠지고 pending 으로 돌아간다 — 파일에도")
func todoHeldReleasedByEveryUserEdit() throws {
    let edits: [(String, @MainActor (TodoListStore, UUID) -> Void)] = [
        ("toggleDone", { $0.toggleDone($1) }),
        ("rename", { $0.rename($1, to: "다시 고친 제목") }),
        ("delete", { $0.delete($1) }),
        ("undoDelete", { $0.undoDelete($1) }),
    ]
    for (name, edit) in edits {
        let heldItem = row(heavyTitle, updated: base + 1, deleted: name == "undoDelete" ? base + 1 : nil)
        let bystander = row("다른 붙잡힌 줄", updated: base + 2)
        let list = try heldStore(items: [heldItem, bystander], held: [heldItem.id, bystander.id])
        #expect(list.heldRejectedIDs == [heldItem.id, bystander.id], "\(name): 파일의 붙잡기를 못 읽었다(전제)")
        edit(list, heldItem.id)
        #expect(list.heldRejectedIDs == [bystander.id], "\(name): 다시 고쳤는데 붙잡기가 안 풀렸다 — 그 수정은 서버로 영영 안 간다")
        #expect(list.pendingIDs == [heldItem.id], "\(name)")
        let disk = try TodoFileStore.load(from: list.fileURL)
        #expect(disk.sync.heldRejectedIDs == [bystander.id] && disk.sync.pendingIDs == [heldItem.id], "\(name): 파일에 안 실렸다")
    }
}

@MainActor
@Test("붙잡힌 줄이 90일 정리로 사라지면 붙잡기에서도 빠진다 — 읽을 때 · 병합 뒤 둘 다, 파일까지")
func todoHeldDroppedWhenPruned() async throws {
    // 읽을 때: 100일 전에 지운 줄.
    let ancientMs = base - 100 * 86_400_000
    let ancient = row("100일 전에 지운 넘친 줄", updated: ancientMs, deleted: ancientMs)
    let alive = row("살아 있는 붙잡힌 줄", updated: base)
    let list = try heldStore(items: [ancient, alive], held: [ancient.id, alive.id])
    #expect(list.items == [alive])
    #expect(list.heldRejectedIDs == [alive.id])
    #expect(try TodoFileStore.load(from: list.fileURL).sync.heldRejectedIDs == [alive.id], "정리 뒤 파일의 붙잡기를 다시 쓰지 않았다")

    // 병합 뒤: 지운 줄이 quota 로 거절돼 붙잡힌 채 앱을 켜 두고 91일이 지났다.
    var nowMs = base
    let server = TodoSyncV0330Server(nowMs: nowMs)
    server.quota = 0
    let transport = TodoSyncV0330Transport { userID, request in server.respond(userID: userID, request: request) }
    let running = TodoListStore(fileURL: todoSyncV0330TempURL(), clock: { TodoRules.date(milliseconds: nowMs) })
    let sync = TodoSync(list: running, transport: transport, scheduler: TodoSyncV0330Scheduler(), clock: { TodoRules.date(milliseconds: nowMs) })
    let doomed = try #require(running.add("지우고 거절될 줄"))
    running.delete(doomed.id)
    sync.activate(userID: userA)
    await todoSyncV0330Idle(sync)
    #expect(running.heldRejectedIDs == [doomed.id], "quota 0 인데 붙잡지 않았다(전제)")
    nowMs += 91 * 86_400_000
    server.nowMs = nowMs
    sync.requestSync(.periodic)
    await todoSyncV0330Idle(sync)
    #expect(running.items.isEmpty)
    #expect(running.heldRejectedIDs.isEmpty, "정리된 줄의 id 가 붙잡기에 남았다")
    #expect(try TodoFileStore.load(from: running.fileURL).sync.heldRejectedIDs.isEmpty)
}

@MainActor
@Test("파일 2세대 선택 필드 — 키가 없으면 빈 목록(나머지 sync 그대로) · 저장→로드 왕복 · 깨졌으면 sync 통째로 전부 보낼 것 · pending 과 겹치면 pending")
func todoHeldFileFieldIsOptional() throws {
    let a = row("줄 a", updated: base + 1)
    let b = row("줄 b", updated: base + 2)
    let itemsJSON = String(decoding: try JSONEncoder().encode([a, b]), as: UTF8.self)
    func write(_ syncJSON: String) throws -> URL {
        let url = todoSyncV0330TempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{\"version\":2,\"items\":\(itemsJSON),\"sync\":\(syncJSON)}".utf8).write(to: url)
        return url
    }
    let now: () -> Date = { TodoRules.date(milliseconds: base + 60_000) }

    // 키 없음(붙잡기 이전 2세대) → 빈 목록, watermark·pending 은 그대로 살고 다시 쓰지 않는다.
    let withoutKey = try write("{\"watermarkMs\":77,\"pendingIDs\":[\"\(b.id.uuidString)\"]}")
    let before = try Data(contentsOf: withoutKey)
    let legacyGen2 = TodoListStore(fileURL: withoutKey, clock: now)
    #expect(legacyGen2.heldRejectedIDs.isEmpty && legacyGen2.watermarkMs == 77 && legacyGen2.pendingIDs == [b.id])
    #expect(try Data(contentsOf: withoutKey) == before, "읽기만 했는데 파일을 다시 썼다")

    // 왕복
    let roundTrip = try heldStore(items: [a, b], pending: [b.id], held: [a.id])
    #expect(roundTrip.heldRejectedIDs == [a.id])
    let raw = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: roundTrip.fileURL)) as? [String: Any])
    let sync = try #require(raw["sync"] as? [String: Any])
    #expect((sync["heldRejectedIDs"] as? [String]) == [a.id.uuidString])

    // 깨진 붙잡기 → 빈 목록으로 접지 않고 sync 통째로 "전부 보낼 것"(다시 보내면 또 거절돼 다시 붙잡힌다). 목록은 산다.
    for broken in ["\"not-a-uuid\"", "42", "[\"nope\"]"] {
        let url = try write("{\"watermarkMs\":77,\"pendingIDs\":[],\"heldRejectedIDs\":\(broken)}")
        let store = TodoListStore(fileURL: url, clock: now)
        #expect(store.items.count == 2, "\(broken): 목록이 사라졌다")
        #expect(store.pendingIDs == [a.id, b.id] && store.watermarkMs == nil && store.heldRejectedIDs.isEmpty, "\(broken)")
        let backups = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
            .filter { $0.contains("corrupt") }
        #expect(backups.isEmpty, "\(broken): 멀쩡한 목록을 손상 백업으로 치웠다")
    }

    // 붙잡기와 pending 이 겹친 파일 → pending 이 이긴다(보낸다), 다시 쓴다.
    let overlap = try heldStore(items: [a, b], pending: [a.id], held: [a.id, b.id])
    #expect(overlap.pendingIDs == [a.id] && overlap.heldRejectedIDs == [b.id])
    #expect(try TodoFileStore.load(from: overlap.fileURL).sync.heldRejectedIDs == [b.id])
}

/// 붙잡기 이전 2세대 디코더(a829b87 의 TodoFileSyncState 모양 — 키 두 개). 붙잡기 키를 모르는 빌드가 새 파일을 읽어도 sync 가 산다.
private struct PreHeldSyncState: Decodable, Equatable {
    var watermarkMs: Int64?
    var pendingIDs: [UUID]
}

private struct PreHeldFile: Decodable {
    var version: Int
    var items: [TodoItem]
    var sync: PreHeldSyncState
}

@MainActor
@Test("붙잡기가 실린 파일을 붙잡기 이전 디코더가 읽어도 목록·watermark·pending 이 그대로다")
func todoHeldFileReadableByOlderDecoders() throws {
    let a = row("줄 a", updated: base + 1)
    let b = row("줄 b", updated: base + 2)
    let list = try heldStore(items: [a, b], pending: [b.id], held: [a.id], watermarkMs: 99)
    let bytes = try Data(contentsOf: list.fileURL)
    #expect(String(decoding: bytes, as: UTF8.self).contains("heldRejectedIDs"))
    let preHeld = try JSONDecoder().decode(PreHeldFile.self, from: bytes)
    #expect(preHeld.version == 2 && preHeld.items == [a, b])
    #expect(preHeld.sync == PreHeldSyncState(watermarkMs: 99, pendingIDs: [b.id]))
}

// MARK: 엔진 — 계정 전환

@MainActor
@Test("붙잡기는 계정 파일마다 따로다 — 전환하면 새 계정 파일의 붙잡기를 읽고, 앞 계정의 늦은 응답은 붙잡기도 안 바꾼다")
func todoHeldFollowsAccountFile() async throws {
    let fileA = todoSyncV0330TempURL("todos.A.json")
    let fileB = todoSyncV0330TempURL("todos.B.json")
    let bItem = row("B 계정의 붙잡힌 줄", updated: base + 1)
    try TodoFileStore.save(
        TodoFile(items: [bItem], sync: TodoFileSyncState(watermarkMs: base, pendingIDs: [], heldRejectedIDs: [bItem.id])), to: fileB
    )
    let bBefore = try Data(contentsOf: fileB)

    let server = TodoSyncV0330Server(nowMs: base)
    server.quota = 0
    let gate = TodoSyncV0330Gate()
    let transport = TodoSyncV0330Transport { userID, request in
        await gate.wait()
        return server.respond(userID: userID, request: request)
    }
    let list = TodoListStore(fileURL: fileA, clock: { TodoRules.date(milliseconds: base) })
    let aItem = try #require(list.add("A 에서 거절될 줄"))
    let sync = TodoSync(list: list, transport: transport, scheduler: TodoSyncV0330Scheduler())
    sync.activate(userID: userA)
    await todoSyncV0330Eventually { gate.arrivals == 1 }
    sync.switchAccount(userID: "22222222-2222-4222-8222-222222222222", fileURL: fileB)
    #expect(list.heldRejectedIDs == [bItem.id], "새 계정 파일의 붙잡기를 읽지 않았다")
    gate.release()                                   // A 의 응답(A 줄 거절)이 늦게 온다
    await todoSyncV0330Eventually { gate.arrivals == 2 }
    #expect(list.heldRejectedIDs == [bItem.id], "앞 계정 응답의 거절이 새 계정 붙잡기에 섞였다")
    #expect(try Data(contentsOf: fileB) == bBefore)
    gate.release()
    await todoSyncV0330Idle(sync)
    #expect(gate.timedOut == 0)
    #expect(list.heldRejectedIDs == [bItem.id])
    let aDisk = try TodoFileStore.load(from: fileA)
    #expect(aDisk.sync.pendingIDs == [aItem.id] && aDisk.sync.heldRejectedIDs.isEmpty, "버려진 응답이 앞 계정 파일을 바꿨다")
}
