import Foundation
import Testing
@testable import check

// v0.3.30 — 할 일 동기화 서버↔앱 **응답 계약**(실제 SQL 출력).
//
// 픽스처 `Fixtures/todo-rpc/*.json` 은 스텁 추측이 아니다. 로컬 하네스(마이그레이션 체인 + 20260917110000_todo_sync.sql)에
// harness.login 으로 authenticated 흉내를 내 `public.todo_sync` 를 **실제로 부른 jsonb 출력 그대로**다
// (`select public.todo_sync(p_changes, p_since_ms)::text`). 호출자·요청 인자(p_changes · p_since_ms)·앞 응답 watermark 는
// `_manifest.json` 에 있다. watermark_ms 와 눌린 시각은 생성한 순간의 서버 now() 라 값을 박지 않고 **서로의 관계**로 본다.
//
// 여기서 보는 것:
// ① 모든 응답이 앱의 응답 모델(`TodoSyncResponse`)로 throw 없이 읽히고, 행 하나도 버려지지 않는다(버려지면 full 이 꺼진다).
// ② 서버가 돌려준 ms → Date → ms 가 정수 그대로다(7칸 전부, 제목은 바이트까지).
// ③ 기기가 만드는 요청(`TodoSyncRequest`)이 서버가 받아 그 응답을 만든 인자와 같다.
// ④ 그 응답을 `TodoListStore.applySync` 에 먹이면 계약 1.2·명세 A4-3 의 병합 결과가 나온다
//    (full 삭제 · 겹침 멱등 · LWW 진 수정의 수렴 · 같은 ms 동률 · 미래 누름 · 새 항목 거절 · quota).
// ⑤ ok 가 아닌 응답(unauthorized · invalid · too_many)은 엔진이 병합하지 않고 pending·watermark·파일을 그대로 둔다.
// ⑥ 프로덕션 전송(PostgREST 경로 · 세션 전송)으로 같은 바이트를 받아도 결과가 같다.

// MARK: - 픽스처 도구

private struct TodoContractError: Error, CustomStringConvertible {
    let description: String
}

private let todoContractDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appendingPathComponent("Fixtures/todo-rpc", isDirectory: true)

/// 계약 시나리오의 기기 시계(2024-09-16T15:20:10Z). 픽스처 항목 시각(1726500000xxx) 바로 뒤라 90일 정리에 걸리지 않는다.
private let todoContractClockMs: Int64 = 1_726_500_010_000

private func todoContractData(_ name: String) throws -> Data {
    try Data(contentsOf: todoContractDirectory.appendingPathComponent("\(name).json"))
}

private func todoContractResponse(_ name: String) throws -> TodoSyncResponse {
    try TodoSyncResponse.decode(todoContractData(name))
}

private func todoContractRaw(_ name: String) throws -> [String: Any] {
    guard let object = try JSONSerialization.jsonObject(with: todoContractData(name)) as? [String: Any] else {
        throw TodoContractError(description: "\(name) 는 JSON 객체가 아니다")
    }
    return object
}

private func todoContractManifest() throws -> [String: Any] {
    try todoContractRaw("_manifest")
}

private func todoContractEntry(_ name: String) throws -> [String: Any] {
    guard let entry = (try todoContractManifest()["fixtures"] as? [String: Any])?[name] as? [String: Any] else {
        throw TodoContractError(description: "manifest 에 \(name) 가 없다")
    }
    return entry
}

private func todoContractFixtureNames() throws -> [String] {
    guard let fixtures = try todoContractManifest()["fixtures"] as? [String: Any] else {
        throw TodoContractError(description: "manifest.fixtures 없음")
    }
    return fixtures.keys.sorted()
}

/// manifest 의 p_changes(배열) 또는 p_changes_text(원문) → JSON 원소 배열.
private func todoContractSentObjects(_ name: String) throws -> [Any] {
    let entry = try todoContractEntry(name)
    if let array = entry["p_changes"] as? [Any] { return array }
    if let text = entry["p_changes_text"] as? String,
       let array = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [Any] {
        return array
    }
    throw TodoContractError(description: "\(name) 의 p_changes 를 읽을 수 없다")
}

/// 서버가 받은 요청 항목 중 **기기가 만들 수 있는 모양**(id 가 uuid 문자열, 시각이 정수)만 로컬 항목으로.
private func todoContractSentItems(_ name: String, ids: Set<String>? = nil) throws -> [TodoItem] {
    try todoContractSentObjects(name).compactMap { element -> TodoItem? in
        guard let object = element as? [String: Any], let id = object["id"] as? String else { return nil }
        if let ids, !ids.contains(id) { return nil }
        let data = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(TodoSyncWireItem.self, from: data).todoItem()
    }
}

private func todoContractSince(_ name: String) throws -> Int64? {
    (try todoContractEntry(name)["p_since_ms"] as? NSNumber)?.int64Value
}

private func todoContractRows(_ name: String) throws -> [TodoItem] {
    let rows = try todoContractResponse(name).items ?? []
    let items = rows.compactMap { $0.todoItem() }
    guard items.count == rows.count else { throw TodoContractError(description: "\(name) 에 못 읽는 행이 있다") }
    return items
}

private func todoContractID(_ suffix: String) -> UUID {
    UUID(uuidString: "00000000-0000-4000-8000-0000000000\(suffix)")!
}

private func todoContractSorted(_ items: [TodoItem]) -> [TodoItem] {
    items.sorted { $0.id.uuidString < $1.id.uuidString }
}

/// 파일을 직접 써서 연 목록(로컬 상태를 계약 시나리오 그대로 만든다 — 스토어 편집 API 는 updatedAt 을 지금으로 민다).
@MainActor
private func todoContractList(items: [TodoItem], pending: [UUID], watermarkMs: Int64?) throws -> TodoListStore {
    let url = todoSyncV0330TempURL("todos.contract.json")
    try TodoFileStore.save(
        TodoFile(items: items, sync: TodoFileSyncState(watermarkMs: watermarkMs, pendingIDs: pending)), to: url
    )
    return TodoListStore(fileURL: url, clock: { TodoRules.date(milliseconds: todoContractClockMs) })
}

/// 요청을 찍고 → 그 요청이 manifest 의 서버 인자와 같은지 보고 → 픽스처 응답을 합친다.
@MainActor
@discardableResult
private func todoContractApply(_ name: String, to list: TodoListStore) throws -> TodoSyncOutgoing {
    let outgoing = list.makeSyncRequest(ids: list.pendingIDs.sorted { $0.uuidString < $1.uuidString })
    let result = try #require(try todoContractResponse(name).mergeableResult(), "\(name) 은 병합 가능한 응답이어야 한다")
    #expect(list.applySync(result, for: outgoing), "\(name): 세대 가드가 막았다")
    return outgoing
}

/// 두 JSON 값이 같은가(키 순서 무관 · 문자열은 글자 그대로).
private func todoContractJSONEqual(_ lhs: Any, _ rhs: Any) -> Bool {
    (lhs as AnyObject).isEqual(rhs)
}

// MARK: - ① 디코드

@Test("할 일 계약 ① 모든 실제 응답이 TodoSyncResponse 로 읽히고 행·거절·full·watermark 가 원문과 같다")
func todoContractEveryFixtureDecodes() throws {
    let names = try todoContractFixtureNames()
    let files = try FileManager.default.contentsOfDirectory(atPath: todoContractDirectory.path)
        .filter { $0.hasSuffix(".json") && $0 != "_manifest.json" }
        .map { String($0.dropLast(5)) }
        .sorted()
    #expect(names == files, "manifest 와 픽스처 파일 목록이 다르다")
    #expect(names.count == 13)

    for name in names {
        let raw = try todoContractRaw(name)
        let response = try todoContractResponse(name)
        #expect(response.status == raw["status"] as? String, "\(name)")
        if response.status == "ok" {
            let rawItems = try #require(raw["items"] as? [[String: Any]], "\(name)")
            #expect(response.items?.count == rawItems.count, "\(name)")
            #expect(response.items?.allSatisfy { $0.todoItem() != nil } == true, "\(name): 버려지는 행이 있다")
            #expect(response.watermarkMs == (raw["watermark_ms"] as? NSNumber)?.int64Value, "\(name)")
            #expect(response.rejected?.count == (raw["rejected"] as? [Any])?.count, "\(name)")
            let result = try #require(response.mergeableResult(), "\(name)")
            #expect(result.full == (raw["full"] as? Bool), "\(name): 행을 다 읽었는데 full 이 꺼졌다")
            #expect(result.items.count == rawItems.count, "\(name)")
        } else {
            #expect(response.mergeableResult() == nil, "\(name): ok 가 아닌 응답이 병합 가능하다고 나왔다")
        }
    }
    #expect(try todoContractResponse("todo_sync__too_many").max == 500)
    let entry = try todoContractEntry("todo_sync__too_many")
    #expect((entry["rows_before"] as? NSNumber) == (entry["rows_after"] as? NSNumber), "too_many 인데 서버 행 수가 변했다")
}

// MARK: - ② ms 왕복

@Test("할 일 계약 ② 서버가 돌려준 모든 행의 ms → Date → ms 가 정수 그대로다(7칸, 제목은 바이트까지)")
func todoContractMillisecondsRoundTripExactly() throws {
    var checked = 0
    for name in try todoContractFixtureNames() {
        guard let rawItems = try todoContractRaw(name)["items"] as? [[String: Any]] else { continue }
        let wires = try #require(try todoContractResponse(name).items)
        for (wire, rawItem) in zip(wires, rawItems) {
            let item = try #require(wire.todoItem(), "\(name) \(wire.id ?? "nil")")
            let back = TodoSyncWireItem(item: item)
            #expect(back == wire, "\(name) \(wire.id ?? "nil"): 왕복 뒤 값이 바뀌었다")
            #expect(Array(item.title.utf8) == Array(((rawItem["title"] as? String) ?? "").utf8), "\(name): 제목 바이트")
            let reencoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(back))
            #expect(todoContractJSONEqual(reencoded, rawItem), "\(name) \(wire.id ?? "nil"): 다시 실은 모양이 서버 행과 다르다")
            checked += 1
        }
    }
    #expect(checked >= 40)
}

// MARK: - ③ 요청 모양

@Test("할 일 계약 ③ 기기가 만드는 요청이 서버가 그 응답을 만든 인자와 같다(p_changes 원소·키 7개·null · p_since_ms)")
func todoContractDeviceRequestMatchesServerArguments() throws {
    for name in ["todo_sync__first_upload_full", "todo_sync__lww_lost_and_won", "todo_sync__same_ms_tie",
                 "todo_sync__future_clamped", "todo_sync__quota"] {
        let items = try todoContractSentItems(name)
        let sent = try todoContractSentObjects(name)
        #expect(items.count == sent.count, "\(name): 기기가 만들 수 없는 항목이 섞였다")
        let request = TodoSyncRequest(changes: items.map(TodoSyncWireItem.init(item:)), sinceMs: try todoContractSince(name))
        let changes = try JSONSerialization.jsonObject(with: request.changesJSON())
        #expect(todoContractJSONEqual(changes, sent), "\(name): p_changes 가 서버가 받은 것과 다르다")
        let body = try #require(try JSONSerialization.jsonObject(with: request.rpcBody()) as? [String: Any])
        #expect(Set(body.keys) == ["p_changes", "p_since_ms"], "\(name)")
        #expect(todoContractJSONEqual(body["p_since_ms"] as Any, (try todoContractEntry(name)["p_since_ms"]) as Any), "\(name)")
    }
}

// MARK: - ④ 병합

@MainActor
@Test("할 일 계약 ④-1 첫 업로드 full — 보낸 4줄은 서버 행으로 확정(pending 0), 서버에 없고 pending 도 아닌 로컬 줄은 지운다")
func todoContractFirstUploadFullMerge() throws {
    let sent = try todoContractSentItems("todo_sync__first_upload_full")
    let stale = TodoItem(
        id: UUID(uuidString: "00000000-0000-4000-8000-00000000dead")!, title: "서버가 정리한 옛 줄",
        createdAt: TodoRules.date(milliseconds: 1_726_400_000_000), updatedAt: TodoRules.date(milliseconds: 1_726_400_000_000),
        originDayKey: "20240915"
    )
    let list = try todoContractList(items: sent + [stale], pending: sent.map(\.id), watermarkMs: nil)
    let outgoing = try todoContractApply("todo_sync__first_upload_full", to: list)

    #expect(todoContractJSONEqual(try JSONSerialization.jsonObject(with: outgoing.request.changesJSON()),
                                  try todoContractSentObjects("todo_sync__first_upload_full")))
    #expect(outgoing.request.sinceMs == nil)
    #expect(todoContractSorted(list.items) == todoContractSorted(try todoContractRows("todo_sync__first_upload_full")))
    #expect(!list.items.contains { $0.id == stale.id }, "full 인데 서버에 없는 로컬 줄이 남았다")
    #expect(list.pendingIDs.isEmpty)
    #expect(list.watermarkMs == (try todoContractResponse("todo_sync__first_upload_full").watermarkMs))
    let disk = try TodoFileStore.load(from: list.fileURL)
    #expect(disk.sync.pendingIDs.isEmpty && disk.sync.watermarkMs == list.watermarkMs)
    #expect(todoContractSorted(disk.items) == todoContractSorted(list.items))
}

@MainActor
@Test("할 일 계약 ④-2 60초 겹침 — 방금 쓴 행이 다시 와도(두 번 합쳐도) 목록·pending 이 그대로, watermark 만 오른다")
func todoContractIncrementalOverlapIsIdempotent() throws {
    let rows = try todoContractRows("todo_sync__first_upload_full")
    let firstWatermark = try #require(try todoContractResponse("todo_sync__first_upload_full").watermarkMs)
    #expect(try todoContractSince("todo_sync__incremental_overlap") == firstWatermark)
    let overlap = try todoContractResponse("todo_sync__incremental_overlap")
    #expect(overlap.full == false && overlap.items?.count == rows.count, "겹침 창에 방금 쓴 행이 안 왔다(검사 공허)")

    let list = try todoContractList(items: rows, pending: [], watermarkMs: firstWatermark)
    let before = list.items
    let outgoing = try todoContractApply("todo_sync__incremental_overlap", to: list)
    #expect(outgoing.request.changes.isEmpty && outgoing.request.sinceMs == firstWatermark)
    #expect(list.items == before && list.pendingIDs.isEmpty)
    #expect(list.watermarkMs == overlap.watermarkMs)
    try todoContractApply("todo_sync__incremental_overlap", to: list)
    #expect(list.items == before && list.pendingIDs.isEmpty)
}

@MainActor
@Test("할 일 계약 ④-3 LWW — 서버보다 옛 수정은 서버 행으로 수렴(진 항목도 온다), 더 새 수정은 확정, 둘 다 pending 에서 빠진다")
func todoContractLastWriterWinsMerge() throws {
    let rows = try todoContractRows("todo_sync__first_upload_full")
    let edits = try todoContractSentItems("todo_sync__lww_lost_and_won")
    let a1 = todoContractID("a1"), a2 = todoContractID("a2")
    let local = rows.map { row in edits.first { $0.id == row.id } ?? row }
    let list = try todoContractList(items: local, pending: [a1, a2],
                                    watermarkMs: try todoContractSince("todo_sync__lww_lost_and_won"))
    try todoContractApply("todo_sync__lww_lost_and_won", to: list)

    let server = try todoContractRows("todo_sync__lww_lost_and_won")
    #expect(list.items.first { $0.id == a1 } == server.first { $0.id == a1 })
    #expect(list.items.first { $0.id == a1 }?.title == "배포 노트 정리", "진 수정이 로컬에 남았다")
    #expect(list.items.first { $0.id == a2 }?.title == "새 수정(이긴다)")
    #expect(list.items.first { $0.id == a2 }?.completedAt == nil, "이긴 수정이 모든 칸(완료 해제)을 덮지 않았다")
    #expect(list.pendingIDs.isEmpty)
    #expect(todoContractSorted(list.items) == todoContractSorted(server))
}

@MainActor
@Test("할 일 계약 ④-4 같은 ms 동률 — 서버 것이 남고 로컬도 서버 값으로, pending 에서 빠진다")
func todoContractSameMillisecondTieMerge() throws {
    let rows = try todoContractRows("todo_sync__lww_lost_and_won")
    let tie = try #require(try todoContractSentItems("todo_sync__same_ms_tie").first)
    let local = rows.map { $0.id == tie.id ? tie : $0 }
    let list = try todoContractList(items: local, pending: [tie.id],
                                    watermarkMs: try todoContractSince("todo_sync__same_ms_tie"))
    try todoContractApply("todo_sync__same_ms_tie", to: list)
    let server = try #require(try todoContractRows("todo_sync__same_ms_tie").first { $0.id == tie.id })
    #expect(server.updatedAtMs == tie.updatedAtMs && server.title != tie.title, "동률 조건이 아니다(검사 공허)")
    #expect(list.items.first { $0.id == tie.id } == server)
    #expect(list.pendingIDs.isEmpty)
}

@MainActor
@Test("할 일 계약 ④-5 5분 넘는 미래 시각 — 서버가 watermark 로 눌러 돌려준 값으로 수렴하고 pending 에서 빠진다")
func todoContractFutureClampMerge() throws {
    let rows = try todoContractRows("todo_sync__same_ms_tie")
    let future = try #require(try todoContractSentItems("todo_sync__future_clamped").first)
    let list = try todoContractList(items: rows + [future], pending: [future.id],
                                    watermarkMs: try todoContractSince("todo_sync__future_clamped"))
    try todoContractApply("todo_sync__future_clamped", to: list)
    let response = try todoContractResponse("todo_sync__future_clamped")
    let watermark = try #require(response.watermarkMs)
    let server = try #require(try todoContractRows("todo_sync__future_clamped").first { $0.id == future.id })
    #expect(server.updatedAtMs == watermark && TodoRules.milliseconds(server.createdAt) == watermark, "서버가 누르지 않았다")
    #expect(future.updatedAtMs > watermark + 300_000)
    #expect(list.items.first { $0.id == future.id } == server)
    #expect(list.pendingIDs.isEmpty)
}

@MainActor
@Test("할 일 계약 ④-6 거절 — 기기가 만들 수 있는 새 항목의 거절(공백 제목 · 1100 코드 포인트 · day key · 음수)은 로컬에 남고 pending 에서 빠진다, 정상 항목은 확정")
func todoContractRejectedNewItemsMerge() throws {
    let response = try todoContractResponse("todo_sync__rejected_mixed")
    let result = try #require(response.mergeableResult())
    let rejectedIDs: Set<UUID> = [todoContractID("a6"), todoContractID("a7"), todoContractID("a8"), todoContractID("a9"),
                                  todoContractID("b2"), todoContractID("b3")]
    #expect(result.rejectedIDs == rejectedIDs, "uuid 가 아닌 원문 id·null id 는 버리고 나머지 거절 id 는 읽어야 한다")
    #expect(response.rejected?.contains { $0.id == nil && $0.reason == "invalid" } == true, "숫자 id 거절은 id null 로 온다")
    #expect(response.rejected?.contains { $0.id == "not-a-uuid" } == true)

    let wanted: Set<String> = ["a6", "a7", "a8", "a9", "b0"].reduce(into: []) { $0.insert("00000000-0000-4000-8000-0000000000\($1)") }
    let newItems = try todoContractSentItems("todo_sync__rejected_mixed", ids: wanted)
    #expect(newItems.count == 5)
    let heavy = try #require(newItems.first { $0.id == todoContractID("a7") })
    #expect(heavy.title.count == 100 && heavy.title.unicodeScalars.count == 1100, "기기 100자 상한 안인데 서버 1000 코드 포인트 밖인 제목이어야 한다")
    let rows = try todoContractRows("todo_sync__future_clamped")
    let list = try todoContractList(items: rows + newItems, pending: newItems.map(\.id),
                                    watermarkMs: try todoContractSince("todo_sync__rejected_mixed"))
    let outgoing = try todoContractApply("todo_sync__rejected_mixed", to: list)

    // 기기가 실은 원소는 서버가 받은 원문의 해당 원소와 같다.
    let sentByID = Dictionary(uniqueKeysWithValues: try todoContractSentObjects("todo_sync__rejected_mixed").compactMap { element -> (String, Any)? in
        guard let object = element as? [String: Any], let id = object["id"] as? String, wanted.contains(id) else { return nil }
        return (id, object)
    })
    let deviceChanges = try #require(try JSONSerialization.jsonObject(with: outgoing.request.changesJSON()) as? [[String: Any]])
    #expect(deviceChanges.count == 5)
    for change in deviceChanges {
        let id = try #require(change["id"] as? String)
        #expect(todoContractJSONEqual(change, sentByID[id] as Any), "\(id)")
    }

    for suffix in ["a6", "a7", "a8", "a9"] {
        let id = todoContractID(suffix)
        #expect(list.items.first { $0.id == id } == newItems.first { $0.id == id }, "거절된 \(suffix) 가 로컬에서 바뀌거나 사라졌다")
    }
    let b0 = try #require(try todoContractRows("todo_sync__rejected_mixed").first { $0.id == todoContractID("b0") })
    #expect(list.items.first { $0.id == b0.id } == b0)
    #expect(list.pendingIDs.isEmpty, "거절·확정 항목이 pending 에 남았다")
    // 부록 B-3: 로컬에 있는 거절 id 만 붙잡는다(b2·b3 는 기기가 만들 수 없는 모양이라 로컬에 없다).
    #expect(list.heldRejectedIDs == [todoContractID("a6"), todoContractID("a7"), todoContractID("a8"), todoContractID("a9")],
            "실제 거절 응답을 붙잡지 않았다 — 다음 응답의 서버 행·full 에 덮이거나 지워진다")
    #expect(Set(try TodoFileStore.load(from: list.fileURL).sync.heldRejectedIDs) == list.heldRejectedIDs)
}

@MainActor
@Test("할 일 계약 ④-7 quota — 5000행 사용자의 새 id 는 로컬에 남고 pending 에서 빠진다, 있는 id 의 더 새 수정은 확정(겹침 창 밖이라 items 는 보낸 id 행만)")
func todoContractQuotaMerge() throws {
    let response = try todoContractResponse("todo_sync__quota")
    #expect(response.rejected == [TodoSyncRejection(id: "00000000-0000-4000-8000-00000000c0de", reason: "quota")])
    #expect(response.items?.count == 1 && response.full == false)
    let sent = try todoContractSentItems("todo_sync__quota")
    let seeded = TodoItem(
        id: UUID(uuidString: "00000000-0000-4000-8000-000000000001")!, title: "심은 줄 1",
        createdAt: TodoRules.date(milliseconds: 1_726_500_000_000), updatedAt: TodoRules.date(milliseconds: 1_726_500_000_000),
        originDayKey: "20240917"
    )
    let edit = try #require(sent.first { $0.id == seeded.id })
    let fresh = try #require(sent.first { $0.id != seeded.id })
    let list = try todoContractList(items: [edit, fresh], pending: [edit.id, fresh.id],
                                    watermarkMs: try todoContractSince("todo_sync__quota"))
    try todoContractApply("todo_sync__quota", to: list)
    #expect(list.items.first { $0.id == fresh.id } == fresh, "quota 로 거절된 새 줄이 로컬에서 사라졌다")
    #expect(list.items.first { $0.id == edit.id } == (try todoContractRows("todo_sync__quota").first))
    #expect(list.pendingIDs.isEmpty)
    #expect(list.heldRejectedIDs == [fresh.id], "quota 로 거절된 새 줄을 붙잡지 않았다 — 뒤 full 동기화에서 지워진다(X2 F2)")
}

@MainActor
@Test("할 일 계약 ④-8 since 81일 전·미래 → full — 서버 행 전부(톰스톤 포함)가 오고, 서버에 없는 비-pending 로컬 줄은 지우고 pending 은 남긴다")
func todoContractLongAbsenceFullMerge() throws {
    for name in ["todo_sync__since_81days_full", "todo_sync__since_future_full"] {
        let response = try todoContractResponse(name)
        let prev = try #require((try todoContractEntry(name)["prev_watermark_ms"] as? NSNumber)?.int64Value)
        let since = try #require(try todoContractSince(name))
        #expect(response.full == true, "\(name)")
        #expect(name.contains("81days") ? since < prev - 80 * 86_400_000 : since > (response.watermarkMs ?? .max), "\(name): 경계 조건이 아니다")
        let rows = try todoContractRows(name)
        #expect(rows.contains { $0.deletedAt != nil }, "\(name): full 인데 톰스톤이 안 왔다")

        let gone = TodoItem(id: UUID(), title: "서버가 정리한 줄", createdAt: TodoRules.date(milliseconds: 1_726_400_000_000),
                            updatedAt: TodoRules.date(milliseconds: 1_726_400_000_000), originDayKey: "20240915")
        let unsent = TodoItem(id: UUID(), title: "아직 못 보낸 새 줄", createdAt: TodoRules.date(milliseconds: 1_726_500_009_000),
                              updatedAt: TodoRules.date(milliseconds: 1_726_500_009_000), originDayKey: "20240917")
        let list = try todoContractList(items: rows + [gone, unsent], pending: [], watermarkMs: since)
        // pending 은 파일로 주고, 요청에는 싣지 않는다(서버가 이 응답을 만든 요청은 빈 배열이었다).
        let outgoing = TodoSyncOutgoing(fileGeneration: list.fileGeneration,
                                        request: TodoSyncRequest(changes: [], sinceMs: since), sent: [:])
        let withPending = try todoContractList(items: rows + [gone, unsent], pending: [unsent.id], watermarkMs: since)
        let result = try #require(response.mergeableResult())
        #expect(list.applySync(result, for: outgoing))
        #expect(withPending.applySync(result, for: TodoSyncOutgoing(fileGeneration: withPending.fileGeneration,
                                                                    request: outgoing.request, sent: [:])))
        #expect(todoContractSorted(list.items) == todoContractSorted(rows), "\(name): full 병합 뒤 서버 행과 다르다")
        #expect(!withPending.items.contains { $0.id == gone.id } && withPending.items.contains { $0.id == unsent.id }, "\(name)")
        #expect(withPending.pendingIDs == [unsent.id], "\(name)")
    }
}

// MARK: - ⑤ ok 가 아닌 응답

@MainActor
@Test("할 일 계약 ⑤ unauthorized · invalid · too_many 실제 응답 — 엔진은 병합하지 않고 refused(status), pending·watermark·파일 그대로")
func todoContractRefusedResponsesKeepState() async throws {
    for (name, status) in [("todo_sync__unauthorized", "unauthorized"), ("todo_sync__invalid_not_array", "invalid"),
                           ("todo_sync__too_many", "too_many")] {
        let bytes = try todoContractData(name)
        let item = TodoItem(id: UUID(), title: "안 올라간 줄", createdAt: TodoRules.date(milliseconds: 1_726_500_000_000),
                            updatedAt: TodoRules.date(milliseconds: 1_726_500_000_000), originDayKey: "20240917")
        let list = try todoContractList(items: [item], pending: [item.id], watermarkMs: 1_726_400_000_000)
        let before = try Data(contentsOf: list.fileURL)
        let transport = TodoSyncV0330Transport { _, _ in try TodoSyncResponse.decode(bytes) }
        let sync = TodoSync(list: list, transport: transport, scheduler: TodoSyncV0330Scheduler(),
                            clock: { TodoRules.date(milliseconds: todoContractClockMs) })
        sync.activate(userID: "267a3495-643c-40cc-b1a7-14967166eae1")
        await todoSyncV0330Idle(sync)
        #expect(transport.requests.count == 1, "\(name)")
        #expect(sync.lastOutcome == .refused(status), "\(name)")
        #expect(list.pendingIDs == [item.id] && list.watermarkMs == 1_726_400_000_000, "\(name)")
        #expect(try Data(contentsOf: list.fileURL) == before, "\(name): 파일이 바뀌었다")
    }
}

// MARK: - ⑥ 프로덕션 전송

@MainActor
private func todoContractStore(host: String, userID: String) -> WorkTimerStore {
    let suite = "check-v0330-todo-contract-\(UUID().uuidString)"
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
    store.session = SupabaseSession(accessToken: "token-contract", refreshToken: "refresh-contract", userID: userID)
    return store
}

@MainActor
@Test("할 일 계약 ⑥ PostgREST 경로(세션 전송)로 실제 응답 바이트를 받아도 — 본문 인자는 서버가 받은 것과 같고 병합 결과도 같다")
func todoContractProductionTransportRoundTrip() async throws {
    let userID = try #require((try todoContractManifest()["users"] as? [String: String])?["A"])
    let host = "v0330-todo-contract-\(UUID().uuidString.prefix(8))"
    let bytes = try todoContractData("todo_sync__first_upload_full")
    TodoSyncV0330URLProtocol.set(host: host, path: "/rest/v1/rpc/todo_sync",
                                 [.init(status: 200, body: String(decoding: bytes, as: UTF8.self))])
    let store = todoContractStore(host: host, userID: userID)
    let sent = try todoContractSentItems("todo_sync__first_upload_full")
    let list = try todoContractList(items: sent, pending: sent.map(\.id), watermarkMs: nil)
    let sync = TodoSync(list: list, transport: WorkTimerStoreTodoSyncTransport(store: store),
                        scheduler: TodoSyncV0330Scheduler(), clock: { TodoRules.date(milliseconds: todoContractClockMs) })
    sync.activate(userID: userID)
    await todoSyncV0330Idle(sync)

    let log = TodoSyncV0330URLProtocol.log(host: host).filter { $0.path == "/rest/v1/rpc/todo_sync" }
    #expect(log.count == 1)
    let body = try #require(try JSONSerialization.jsonObject(with: Data((log.first?.body ?? "").utf8)) as? [String: Any])
    #expect(todoContractJSONEqual(body["p_changes"] as Any, try todoContractSentObjects("todo_sync__first_upload_full")))
    #expect(body["p_since_ms"] is NSNull)
    #expect(sync.lastOutcome == .synced)
    #expect(todoContractSorted(list.items) == todoContractSorted(try todoContractRows("todo_sync__first_upload_full")))
    #expect(list.pendingIDs.isEmpty)
    #expect(list.watermarkMs == (try todoContractResponse("todo_sync__first_upload_full").watermarkMs))
}
