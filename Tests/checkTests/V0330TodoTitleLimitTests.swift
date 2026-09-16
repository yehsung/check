import Foundation
import Testing
@testable import check

// MARK: - v0.3.30 할 일 제목 상한 — 기기(글자 100) × 서버(코드 포인트 1000)
//
// 서버 `todo_items.title` 은 `char_length(title) between 1 and 1000` 이고, UTF-8 DB 의 char_length 는 **코드 포인트**를 센다.
// 맥의 100 은 **글자(그래핌)** 다. 이모지 한 글자가 코드 포인트 11개일 수 있어서(👨🏽‍👩🏽‍👧🏽‍👦🏽 = 사람 넷 × 2 + ZWJ 3),
// 글자 100 만 보면 코드 포인트 1100 짜리 제목이 맥에 저장되고 서버에서 영구 거절된다 — 다른 기기에 끝내 안 가고 알림도 없다
// (a4-verify PROBE-P8 · 실서버 하네스 `rejected=[invalid]`). 그래서 기기가 **두 잣대를 함께** 본다:
// · 입력칸(뷰)·초안(컨트롤러)·추가·수정 네 문이 같은 판정 `TodoRules.titleFitsLimits` 를 쓴다(자르지 않고 막는다 — 기존 제품 결정).
// · 이미 파일에 있는 넘친 줄(0.3.29 는 글자만 셌다)은 서버가 거절해 **이 기기에만 남는다**. full 병합이 그 줄을
//   "서버가 정리한 줄"로 오인해 지우면 안 된다(X2 S7a 에서 81일 뒤 full 로 조용히 사라졌다).

/// 코드 포인트 `perGrapheme` 개짜리 글자 하나. 결합 문자(U+0363…)는 NFC 로 합쳐지지 않아 정규화 뒤에도 개수가 그대로다.
private func todoTitleLimitGrapheme(scalars perGrapheme: Int) -> String {
    precondition(perGrapheme >= 1 && perGrapheme <= 12)
    let marks = (0x0363..<(0x0363 + perGrapheme - 1)).compactMap { Unicode.Scalar($0) }.map(String.init).joined()
    return "x" + marks
}

private func todoTitleLimitTitle(graphemes: Int, scalarsEach: Int) -> String {
    String(repeating: todoTitleLimitGrapheme(scalars: scalarsEach), count: graphemes)
}

private let todoTitleLimitFamily = "👨🏽\u{200D}👩🏽\u{200D}👧🏽\u{200D}👦🏽"

@Test("픽스처 전제 — 결합 문자 글자와 가족 이모지는 정규화 뒤에도 글자·코드 포인트 수가 그대로다")
func todoTitleLimitFixturesSurviveNormalization() {
    let heavy = todoTitleLimitTitle(graphemes: 100, scalarsEach: 11)
    #expect(heavy.count == 100 && heavy.unicodeScalars.count == 1100)
    #expect(TodoRules.normalizedTitle(heavy) == heavy)
    let family = String(repeating: todoTitleLimitFamily, count: 100)
    #expect(family.count == 100 && family.unicodeScalars.count == 1100)
    #expect(TodoRules.normalizedTitle(family) == family)
}

@MainActor
@Test("추가·수정은 글자 100 이하라도 코드 포인트 1000 을 넘으면 거절한다 — 경계 1000 은 받는다")
func todoTitleLimitStoreRejectsOverServerCodePoints() throws {
    let store = TodoListStore(fileURL: todoSyncV0330TempURL(), clock: { TodoRules.date(milliseconds: 1_726_500_000_000) })

    let atLimit = todoTitleLimitTitle(graphemes: 100, scalarsEach: 10)                 // 1000
    #expect(atLimit.unicodeScalars.count == 1000)
    let accepted = try #require(store.add(atLimit), "코드 포인트 1000 짜리(서버 경계 안) 제목을 거절했다")
    #expect(accepted.title == atLimit)

    let overByOne = todoTitleLimitTitle(graphemes: 99, scalarsEach: 10) + todoTitleLimitGrapheme(scalars: 11)   // 1001
    #expect(overByOne.count == 100 && overByOne.unicodeScalars.count == 1001)
    #expect(store.add(overByOne) == nil, "코드 포인트 1001 — 서버가 영구 거절할 줄을 맥에 저장했다")
    #expect(store.add(String(repeating: todoTitleLimitFamily, count: 100)) == nil, "가족 이모지 100자(코드 포인트 1100)를 저장했다")
    #expect(store.items.count == 1)
    #expect(store.pendingIDs == [accepted.id])

    let plain = try #require(store.add("평범한 줄"))
    store.rename(plain.id, to: overByOne)
    #expect(store.items.first { $0.id == plain.id }?.title == "평범한 줄", "서버가 거절할 제목으로 고쳐졌다 — 다른 기기에는 옛 제목이 남는다")
    store.rename(plain.id, to: atLimit)
    #expect(store.items.first { $0.id == plain.id }?.title == atLimit)
}

@MainActor
@Test("입력칸·초안도 같은 판정 — 넘치는 입력은 통째로 막고, 줄어드는 편집은 언제나 통과한다")
func todoTitleLimitDraftInputBlocksOverServerCodePoints() {
    let atLimit = todoTitleLimitTitle(graphemes: 100, scalarsEach: 10)
    let nearLimit = todoTitleLimitTitle(graphemes: 99, scalarsEach: 10)
    let overByOne = nearLimit + todoTitleLimitGrapheme(scalars: 11)
    let family100 = String(repeating: todoTitleLimitFamily, count: 100)

    // 뷰(입력 행·인라인 편집 공용)
    #expect(TodoDraftInput.accepted(current: nearLimit, proposed: atLimit) == atLimit)
    #expect(TodoDraftInput.accepted(current: nearLimit, proposed: overByOne) == nearLimit, "글자 수만 보고 코드 포인트 1001 을 받았다")
    #expect(TodoDraftInput.accepted(current: "", proposed: family100) == "", "붙여 넣은 가족 이모지 100자를 받았다")
    // 이미 넘친 값(옛 파일의 줄을 인라인 편집)은 지우는 방향으로 빠져나올 수 있다.
    let legacyHeavy = todoTitleLimitTitle(graphemes: 100, scalarsEach: 11)
    let shorter = String(legacyHeavy.dropLast())
    #expect(TodoDraftInput.accepted(current: legacyHeavy, proposed: shorter) == shorter)
    #expect(TodoDraftInput.accepted(current: legacyHeavy, proposed: "").isEmpty)

    // 컨트롤러(초안의 주인) — 뷰와 판정이 갈리면 화면엔 보이는데 초안은 안 바뀌는 엇갈림이 생긴다.
    let list = TodoListStore(fileURL: todoSyncV0330TempURL())
    let controller = CheckTodoBoardController(store: list)
    controller.setDraft(nearLimit)
    #expect(controller.draft == nearLimit)
    controller.setDraft(overByOne)
    #expect(controller.draft == nearLimit, "초안이 코드 포인트 1001 을 받았다")
    controller.setDraft(family100)
    #expect(controller.draft == nearLimit)
    controller.setDraft(atLimit)
    #expect(controller.draft == atLimit)
    controller.submitDraft()
    #expect(controller.draft.isEmpty)
    #expect(list.items.first?.title == atLimit)
}

@Test("full 병합은 서버가 받을 수 없는 제목의 로컬 줄(옛 파일에서 온 것)을 '서버가 정리한 줄'로 오인해 지우지 않는다")
func todoTitleLimitFullMergeKeepsLocalOnlyOverLimitRow() {
    let base: Int64 = 1_726_500_000_000
    func row(_ title: String, _ updated: Int64) -> TodoItem {
        TodoItem(
            id: UUID(), title: title, createdAt: TodoRules.date(milliseconds: base),
            updatedAt: TodoRules.date(milliseconds: updated), originDayKey: "20260915"
        )
    }
    let heavy = row(todoTitleLimitTitle(graphemes: 100, scalarsEach: 11), base + 1)     // 거절돼 이 기기에만 남은 줄
    let purged = row("서버가 정리한 줄", base + 2)
    let result = TodoRules.mergedSync(
        local: [heavy, purged], pending: [], sent: [:], server: [], rejected: [], full: true
    )
    #expect(result.items == [heavy], "거절돼 로컬에만 남긴 할 일이 full 동기화에서 지워졌다")
    #expect(result.pending.isEmpty, "서버가 영원히 거절할 줄을 다시 보낼 것으로 되돌렸다")
    // 멱등
    let again = TodoRules.mergedSync(
        local: result.items, pending: result.pending, sent: [:], server: [], rejected: [], full: true
    )
    #expect(again.items == result.items && again.pending == result.pending)
}

@MainActor
@Test("옛 파일의 넘친 줄 — 첫 업로드에서 거절되면 pending 에서 빠지고 로컬에 남으며, 81일 뒤 full 동기화에서도 남는다")
func todoTitleLimitLegacyOverLimitRowSurvivesRejectAndFull() async throws {
    let base: Int64 = 1_726_500_000_000
    let heavyTitle = todoTitleLimitTitle(graphemes: 100, scalarsEach: 11)
    let heavy = TodoItem(
        id: UUID(), title: heavyTitle, createdAt: TodoRules.date(milliseconds: base - 86_400_000),
        updatedAt: TodoRules.date(milliseconds: base - 86_400_000), originDayKey: "20260915"
    )
    let normal = TodoItem(
        id: UUID(), title: "평범한 옛 줄", createdAt: TodoRules.date(milliseconds: base - 86_400_000),
        updatedAt: TodoRules.date(milliseconds: base - 86_400_000), originDayKey: "20260915"
    )
    let url = todoSyncV0330TempURL()
    try TodoFileStore.save(TodoFile(version: 1, items: [heavy, normal]), to: url)
    var nowMs = base
    let list = TodoListStore(fileURL: url, clock: { TodoRules.date(milliseconds: nowMs) })
    #expect(list.pendingIDs == [heavy.id, normal.id])
    let server = TodoSyncV0330Server(nowMs: base)
    let transport = TodoSyncV0330Transport { userID, request in server.respond(userID: userID, request: request) }
    let sync = TodoSync(list: list, transport: transport, scheduler: TodoSyncV0330Scheduler(), clock: { TodoRules.date(milliseconds: nowMs) })
    sync.activate(userID: "11111111-1111-4111-8111-111111111111")
    await todoSyncV0330Idle(sync)

    let firstSentIDs = try #require(transport.requests.first).request.changes.map(\.id)
    #expect(firstSentIDs.contains(heavy.id.uuidString.lowercased()), "첫 업로드가 옛 줄을 싣지 않았다(검사 공허)")
    #expect(server.items(for: "11111111-1111-4111-8111-111111111111").map(\.id) == [normal.id], "서버 모형이 코드 포인트 1100 줄을 받았다 — 실서버와 다르다")
    #expect(list.items.contains { $0.id == heavy.id })
    #expect(list.pendingIDs.isEmpty)

    // 81일 동안 못 맞췄다 → full
    nowMs += 81 * 86_400_000
    server.nowMs = nowMs
    sync.requestSync(.periodic)
    await todoSyncV0330Idle(sync)
    #expect(sync.lastOutcome == .synced)
    #expect(list.items.contains { $0.id == heavy.id }, "거절돼 로컬에만 남긴 옛 줄이 81일 뒤 full 동기화에서 조용히 지워졌다")
    #expect(list.pendingIDs.isEmpty)
}
