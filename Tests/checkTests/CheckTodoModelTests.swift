import Foundation
import Testing
@testable import check

// MARK: - 픽스처 (시간은 전부 주입 · 실제 '지금'을 절대 읽지 않는다)

// 이 파일의 모든 시각은 KST 로 고정한 값이다. 자정 근처(예: 새벽 0시 10분)에 CI 를 돌려도
// 결과가 바뀌지 않아야 하고, 반대로 "자정을 넘겼다"는 상황을 실제로 기다리지 않고 재현해야 한다.

private let kstTimeZone = TimeZone(identifier: "Asia/Seoul")!

private var kstCal: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = kstTimeZone
    return c
}

/// KST 기준 시각 하나를 만든다(달력 계산은 전부 이걸 통해서만 — 초 산술로 하면 하루 경계가 어긋난다).
private func kst(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    var comps = DateComponents()
    comps.year = year
    comps.month = month
    comps.day = day
    comps.hour = hour
    comps.minute = minute
    return kstCal.date(from: comps)!
}

private func kstDays(_ count: Int, from date: Date) -> Date {
    kstCal.date(byAdding: .day, value: count, to: date)!
}

/// 픽스처 항목. originDayKey 는 createdAt 에서 뽑아 실제 생성 경로와 같은 값을 갖게 한다.
private func makeItem(
    _ title: String,
    createdAt: Date,
    completedAt: Date? = nil,
    deletedAt: Date? = nil
) -> TodoItem {
    TodoItem(
        id: UUID(),
        title: title,
        createdAt: createdAt,
        updatedAt: createdAt,
        completedAt: completedAt,
        deletedAt: deletedAt,
        originDayKey: TodoRules.dayKey(createdAt)
    )
}

/// 실제 Application Support 를 건드리지 않는 고유 임시 경로(상위 폴더는 저장 시 생성된다).
private func makeTempTodoURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("check-todo-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("todos.local.json", isDirectory: false)
}

// MARK: - 하루 경계 (KST)

/// dayKey 가 UTC 가 아니라 KST 로 끊기는지. KST 00:30 은 UTC 로는 전날 15:30 이라,
/// 시간대를 잘못 잡으면 새벽에 적은 항목이 통째로 '어제 것'이 된다.
@Test
func todoDayKeyBreaksAtKoreanMidnight() {
    #expect(TodoRules.dayKey(kst(2026, 8, 11, 23, 59)) == "20260811")
    #expect(TodoRules.dayKey(kst(2026, 8, 12, 0, 30)) == "20260812")
    #expect(TodoRules.dayKey(kst(2026, 8, 12, 23, 59)) == "20260812")
}

/// 제품 규칙의 핵심 한 줄: **어제 완료한 항목은 자정을 넘기면 사라지고, 어제 못 끝낸 항목은 그대로 남는다.**
@Test
func todoCompletedYesterdayDisappearsButUnfinishedCarriesOver() {
    let yesterday = kst(2026, 8, 11, 22, 0)
    let today = kst(2026, 8, 12, 9, 0)
    let todayKey = TodoRules.dayKey(today)

    let doneYesterday = makeItem("어제 끝낸 일", createdAt: yesterday, completedAt: yesterday)
    let openYesterday = makeItem("어제 못 끝낸 일", createdAt: yesterday)
    let doneToday = makeItem("오늘 끝낸 일", createdAt: today, completedAt: kst(2026, 8, 12, 10, 0))

    #expect(TodoRules.isVisible(doneYesterday, todayKey: todayKey) == false)
    #expect(TodoRules.isVisible(openYesterday, todayKey: todayKey) == true)
    #expect(TodoRules.isVisible(doneToday, todayKey: todayKey) == true)

    // 어제 것이었을 때는 보였다는 것도 함께 못박는다(사라진 이유가 '자정'임을 값으로 보인다).
    #expect(TodoRules.isVisible(doneYesterday, todayKey: TodoRules.dayKey(yesterday)) == true)

    // 이월된 미완료엔 '어제' 배지가 붙는다.
    let days = TodoRules.carriedDays(originDayKey: openYesterday.originDayKey, todayKey: todayKey)
    #expect(days == 1)
    #expect(TodoRules.carryBadge(days: days) == "어제")

    // 톰스톤은 오늘이든 어제든 안 보인다.
    let deleted = makeItem("지운 일", createdAt: today, deletedAt: today)
    #expect(TodoRules.isVisible(deleted, todayKey: todayKey) == false)
}

/// 배지 문구. 오늘 만든 항목엔 배지가 없어야 한다(목록 대부분이 오늘 것이라 배지가 신호 구실을 못 하게 된다).
@Test
func todoCarryBadgeWording() {
    #expect(TodoRules.carryBadge(days: 0) == nil)
    #expect(TodoRules.carryBadge(days: -3) == nil)     // 시계 되돌림 방어
    #expect(TodoRules.carryBadge(days: 1) == "어제")
    #expect(TodoRules.carryBadge(days: 3) == "3일 전")
    #expect(TodoRules.carryBadge(days: 42) == "42일 전")
}

/// 이월 일수는 **시간 차가 아니라 달력 날짜 차**다. 23:50 에 적고 00:10 에 봐도 '어제'여야 한다(경과는 20분뿐).
@Test
func todoCarriedDaysCountsCalendarDaysNotElapsedHours() {
    let lateNight = kst(2026, 8, 11, 23, 50)
    let justAfterMidnight = kst(2026, 8, 12, 0, 10)
    #expect(
        TodoRules.carriedDays(
            originDayKey: TodoRules.dayKey(lateNight),
            todayKey: TodoRules.dayKey(justAfterMidnight)
        ) == 1
    )
    // 깨진 키는 0(손상 파일의 쓰레기 문자열이 엉뚱한 배지를 만들지 않게).
    #expect(TodoRules.carriedDays(originDayKey: "쓰레기", todayKey: "20260812") == 0)
    #expect(TodoRules.carriedDays(originDayKey: "20260812", todayKey: "20260805") == 0)
}

// MARK: - 오래된 항목

/// 7일 이월된 **미완료**만 '오래된 항목'으로 내려간다. 6일은 아직 목록에 그대로 있고, 완료 항목은 대상이 아니다.
@Test
func todoSevenDayCarryBecomesOldButCompletedNeverDoes() {
    let today = kst(2026, 8, 12, 9, 0)
    let todayKey = TodoRules.dayKey(today)

    let sixDays = makeItem("6일 된 일", createdAt: kstDays(-6, from: today))
    let sevenDays = makeItem("7일 된 일", createdAt: kstDays(-7, from: today))
    let tenDaysDoneToday = makeItem(
        "10일 전에 적고 오늘 끝낸 일",
        createdAt: kstDays(-10, from: today),
        completedAt: today
    )

    #expect(TodoRules.isOld(sixDays, todayKey: todayKey) == false)
    #expect(TodoRules.isOld(sevenDays, todayKey: todayKey) == true)
    #expect(TodoRules.isOld(tenDaysDoneToday, todayKey: todayKey) == false)

    // '오래된 항목'은 숨기는 것이지 지우는 것이 아니다 — 여전히 보이는 목록의 일부다.
    #expect(TodoRules.isVisible(sevenDays, todayKey: todayKey) == true)
}

// MARK: - 정렬

/// 미완료가 항상 위(최근 생성 순), 완료는 그 아래에 최근 완료 순으로 쌓인다. 어제 완료분은 아예 빠진다.
@Test
func todoVisibleSortsUnfinishedFirstThenTodaysCompleted() {
    let today = kst(2026, 8, 12, 9, 0)
    let todayKey = TodoRules.dayKey(today)

    let oldOpen = makeItem("오래된 미완료", createdAt: kst(2026, 8, 10, 9, 0))
    let newOpen = makeItem("방금 적은 미완료", createdAt: kst(2026, 8, 12, 8, 0))
    let doneEarly = makeItem("오늘 아침에 끝낸 일", createdAt: kst(2026, 8, 9, 9, 0), completedAt: kst(2026, 8, 12, 7, 0))
    let doneLate = makeItem("방금 끝낸 일", createdAt: kst(2026, 8, 11, 9, 0), completedAt: kst(2026, 8, 12, 8, 30))
    let doneYesterday = makeItem("어제 끝낸 일", createdAt: kst(2026, 8, 11, 9, 0), completedAt: kst(2026, 8, 11, 20, 0))

    let sorted = TodoRules.visible([doneEarly, oldOpen, doneYesterday, doneLate, newOpen], todayKey: todayKey)
    #expect(sorted.map(\.title) == ["방금 적은 미완료", "오래된 미완료", "방금 끝낸 일", "오늘 아침에 끝낸 일"])
}

/// 삭제 되돌리기 창 동안 톰스톤이 **그 자리에** 남는지. 순서가 흔들리면 '되돌리기' 버튼이 다른 줄에 붙어 보인다.
@Test
func todoPendingDeleteStaysInPlaceForUndoWindow() {
    let today = kst(2026, 8, 12, 9, 0)
    let todayKey = TodoRules.dayKey(today)

    let first = makeItem("첫째", createdAt: kst(2026, 8, 12, 8, 0))
    let second = makeItem("둘째", createdAt: kst(2026, 8, 12, 7, 0), deletedAt: today)
    let third = makeItem("셋째", createdAt: kst(2026, 8, 12, 6, 0))
    let all = [first, second, third]

    // 기본 목록에서는 빠지고,
    #expect(TodoRules.visible(all, todayKey: todayKey).map(\.title) == ["첫째", "셋째"])
    // 되돌리기 대상으로 지정하면 원래 자리(가운데)에 그대로 남는다.
    #expect(
        TodoRules.visible(all, todayKey: todayKey, keepingDeleted: second.id).map(\.title)
        == ["첫째", "둘째", "셋째"]
    )
}

// MARK: - 제목 규칙

/// 정규화: 앞뒤 공백 제거 · 연속 공백 1칸 · 제어문자 제거. 단 줄바꿈/탭은 **공백으로 살린다**
/// (여러 줄을 붙여 넣었을 때 단어가 들러붙으면 안 된다).
@Test
func todoTitleNormalization() {
    #expect(TodoRules.normalizedTitle("   보고서   쓰기  ") == "보고서 쓰기")
    #expect(TodoRules.normalizedTitle("회의\n준비") == "회의 준비")
    #expect(TodoRules.normalizedTitle("탭\t정리") == "탭 정리")
    #expect(TodoRules.normalizedTitle("제어\u{0007}문자") == "제어문자")
    #expect(TodoRules.normalizedTitle("   ") == "")
    #expect(TodoRules.normalizedTitle("\n\t  \n") == "")
    // 상한 초과여도 정규화 단계에선 자르지 않는다 — 절단은 이 앱의 규칙이 아니다(거절만 한다).
    #expect(TodoRules.normalizedTitle(String(repeating: "가", count: 150)).count == 150)
}

/// 100자는 통과, 101자는 거부. 거부는 **아무 일도 안 하는 것**이라 목록이 변하지 않아야 한다.
@MainActor
@Test
func todoRejectsTitleOverLimitWithoutTruncating() {
    let now = kst(2026, 8, 12, 9, 0)
    let store = TodoListStore(fileURL: makeTempTodoURL(), clock: { now })

    let exactly100 = String(repeating: "가", count: TodoRules.maxTitleLength)
    let over101 = String(repeating: "가", count: TodoRules.maxTitleLength + 1)

    #expect(store.add(exactly100)?.title.count == TodoRules.maxTitleLength)
    #expect(store.items.count == 1)

    #expect(store.add(over101) == nil)
    #expect(store.items.count == 1)                       // 잘려서 들어간 항목이 없다
    #expect(store.items[0].title.count == TodoRules.maxTitleLength)

    // 카운터는 90자부터 보인다는 계약값도 함께 못박는다(뷰가 이 값을 읽는다).
    #expect(TodoRules.counterVisibleFrom == 90)
}

/// 공백/줄바꿈만 있는 입력은 항목을 만들지 않는다(Enter 를 잘못 눌러 빈 줄이 쌓이는 걸 막는다).
@MainActor
@Test
func todoRejectsBlankTitle() {
    let now = kst(2026, 8, 12, 9, 0)
    let store = TodoListStore(fileURL: makeTempTodoURL(), clock: { now })

    #expect(store.add("") == nil)
    #expect(store.add("    ") == nil)
    #expect(store.add("\n\t ") == nil)
    #expect(store.items.isEmpty)
}

// MARK: - 스토어 상태 전이

/// 새 항목은 맨 앞에 오고, originDayKey 는 만든 날로 찍힌다.
@MainActor
@Test
func todoAddPutsNewestFirstAndStampsOriginDay() {
    var now = kst(2026, 8, 12, 9, 0)
    let store = TodoListStore(fileURL: makeTempTodoURL(), clock: { now })

    store.add("먼저 적은 일")
    now = kst(2026, 8, 12, 10, 0)
    store.add("나중에 적은 일")

    #expect(store.items.map(\.title) == ["나중에 적은 일", "먼저 적은 일"])
    #expect(store.items.allSatisfy { $0.originDayKey == "20260812" })
    #expect(store.todayKey == "20260812")
}

/// 완료/완료취소 왕복. **originDayKey 는 절대 변하지 않는다** — 이월 배지의 기준이기 때문이다.
@MainActor
@Test
func todoToggleDoneRoundTripKeepsOriginDayKey() {
    var now = kst(2026, 8, 11, 15, 0)          // 어제 적었다
    let store = TodoListStore(fileURL: makeTempTodoURL(), clock: { now })
    let item = store.add("어제 적은 일")!

    now = kst(2026, 8, 12, 11, 0)              // 오늘 체크
    store.toggleDone(item.id)
    #expect(store.items[0].isDone == true)
    #expect(store.items[0].completedAt == now)
    #expect(store.items[0].originDayKey == "20260811")

    now = kst(2026, 8, 12, 11, 30)             // 다시 풀기
    store.toggleDone(item.id)
    #expect(store.items[0].isDone == false)
    #expect(store.items[0].completedAt == nil)
    #expect(store.items[0].originDayKey == "20260811")

    // 배지는 완료 왕복과 무관하게 '어제' 그대로다.
    let days = TodoRules.carriedDays(originDayKey: store.items[0].originDayKey, todayKey: store.todayKey)
    #expect(TodoRules.carryBadge(days: days) == "어제")
}

/// 삭제는 톰스톤이라 배열에서 사라지지 않고, 되돌리기가 제목·완료 상태·id 를 그대로 되살린다.
@MainActor
@Test
func todoDeleteIsTombstoneAndUndoRestoresEverything() {
    var now = kst(2026, 8, 12, 9, 0)
    let store = TodoListStore(fileURL: makeTempTodoURL(), clock: { now })
    let item = store.add("지웠다 되살릴 일")!
    store.toggleDone(item.id)                  // 완료 상태로 지운다(되살릴 때 상태 보존을 확인하려고)
    let completedAt = store.items[0].completedAt

    now = kst(2026, 8, 12, 9, 5)
    store.delete(item.id)
    #expect(store.items.count == 1)            // 물리 삭제가 아니다
    #expect(store.items[0].deletedAt == now)
    #expect(TodoRules.isVisible(store.items[0], todayKey: store.todayKey) == false)
    #expect(TodoRules.visible(store.items, todayKey: store.todayKey).isEmpty)

    now = kst(2026, 8, 12, 9, 8)
    store.undoDelete(item.id)
    #expect(store.items[0].deletedAt == nil)
    #expect(store.items[0].id == item.id)
    #expect(store.items[0].title == "지웠다 되살릴 일")
    #expect(store.items[0].completedAt == completedAt)
    #expect(TodoRules.visible(store.items, todayKey: store.todayKey).count == 1)

    // 되돌리기 창 길이는 계약값(뷰 타이머가 이 값을 읽는다).
    #expect(TodoRules.undoSeconds == 5)
}

/// 인라인 수정: 정규화해서 저장하고, 상한 초과·빈 제목은 무시한다(취소와 같은 결과 — 원문이 남는다).
@MainActor
@Test
func todoRenameNormalizesAndRejectsInvalidTitles() {
    var now = kst(2026, 8, 12, 9, 0)
    let store = TodoListStore(fileURL: makeTempTodoURL(), clock: { now })
    let item = store.add("원래 제목")!

    now = kst(2026, 8, 12, 9, 1)
    store.rename(item.id, to: "  고친   제목  ")
    #expect(store.items[0].title == "고친 제목")
    #expect(store.items[0].updatedAt == now)

    store.rename(item.id, to: "   ")
    #expect(store.items[0].title == "고친 제목")

    store.rename(item.id, to: String(repeating: "나", count: TodoRules.maxTitleLength + 1))
    #expect(store.items[0].title == "고친 제목")

    // 만든 시각·만든 날은 수정으로 흔들리지 않는다(정렬과 배지의 기준이라).
    #expect(store.items[0].createdAt == kst(2026, 8, 12, 9, 0))
    #expect(store.items[0].originDayKey == "20260812")
}

// MARK: - 파일 비대 방지

/// 90일 지난 완료/삭제만 파일에서 빠진다. **미완료는 아무리 오래돼도 남는다**(자동 삭제 없음).
@Test
func todoPrunedDropsOnlyAncientCompletedAndDeleted() {
    let now = kst(2026, 8, 12, 12, 0)
    let ancient = kstDays(-91, from: now)
    let recent = kstDays(-89, from: now)

    let ancientDone = makeItem("아주 오래전에 끝낸 일", createdAt: ancient, completedAt: ancient)
    let ancientDeleted = makeItem("아주 오래전에 지운 일", createdAt: ancient, deletedAt: ancient)
    let recentDone = makeItem("89일 전에 끝낸 일", createdAt: recent, completedAt: recent)
    let ancientOpen = makeItem("1년째 미루는 일", createdAt: kstDays(-365, from: now))

    let kept = TodoRules.pruned([ancientDone, ancientDeleted, recentDone, ancientOpen], now: now)
    #expect(kept.map(\.title) == ["89일 전에 끝낸 일", "1년째 미루는 일"])
    #expect(TodoRules.purgeDays == 90)
}

/// reload 는 pruned 를 적용하고, 줄어든 결과를 디스크에도 반영한다(다음 실행이 같은 걸 또 읽지 않게).
@MainActor
@Test
func todoReloadPrunesAndRewritesFile() throws {
    let url = makeTempTodoURL()
    let now = kst(2026, 8, 12, 12, 0)
    let ancient = kstDays(-100, from: now)

    try TodoFileStore.save(
        TodoFile(items: [
            makeItem("100일 전에 끝낸 일", createdAt: ancient, completedAt: ancient),
            makeItem("살아 있는 일", createdAt: kstDays(-3, from: now)),
        ]),
        to: url
    )

    let store = TodoListStore(fileURL: url, clock: { now })
    #expect(store.items.map(\.title) == ["살아 있는 일"])

    let onDisk = try TodoFileStore.load(from: url)
    #expect(onDisk.items.map(\.title) == ["살아 있는 일"])
}

// MARK: - 파일 저장소

/// 저장 → 로드 왕복에서 시각까지 그대로 살아 돌아온다(초 단위로 잘리면 자정 판정이 흔들린다).
@Test
func todoFileRoundTripsThroughDisk() throws {
    let url = makeTempTodoURL()
    let created = kst(2026, 8, 11, 22, 13)
    let completed = kst(2026, 8, 12, 9, 47)

    let original = TodoFile(items: [
        makeItem("완료한 일", createdAt: created, completedAt: completed),
        makeItem("지운 일", createdAt: created, deletedAt: completed),
        makeItem("남은 일", createdAt: created),
    ])

    try TodoFileStore.save(original, to: url)      // 상위 폴더가 없어도 만들어서 쓴다
    let loaded = try TodoFileStore.load(from: url)

    #expect(loaded == original)
    #expect(loaded.version == TodoFile.currentVersion)
    #expect(loaded.items[0].completedAt == completed)
    #expect(loaded.items[1].deletedAt == completed)
    #expect(loaded.items[2].completedAt == nil)

    // 파일이 아예 없으면 빈 파일로 출발한다(첫 실행은 예외가 아니라 정상 경로).
    let fresh = try TodoFileStore.load(from: makeTempTodoURL())
    #expect(fresh.items.isEmpty)
}

/// 손상 파일은 **던지고**, 스토어는 원본을 백업으로 옮긴 뒤 빈 목록으로 출발한다.
/// 사용자가 손으로 쓴 문장이라 조용히 덮어써서 잃어버리면 안 된다(캐시와 다른 점).
@MainActor
@Test
func todoCorruptedFileIsBackedUpNotDiscarded() throws {
    let url = makeTempTodoURL()
    try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    let garbage = "{ 이건 JSON 이 아니다"
    try Data(garbage.utf8).write(to: url)

    // 저장소는 삼키지 않고 던진다.
    #expect(throws: (any Error).self) { try TodoFileStore.load(from: url) }

    let now = kst(2026, 8, 12, 13, 45)
    let backup = TodoFileStore.corruptedBackupURL(for: url, now: now)
    #expect(backup.lastPathComponent == "todos.local.json.corrupt-20260812-134500")

    let store = TodoListStore(fileURL: url, clock: { now })
    #expect(store.items.isEmpty)                                        // 빈 목록으로 출발하고
    #expect(FileManager.default.fileExists(atPath: backup.path))        // 원본은 백업으로 살아 있다
    let backedUp = String(data: try Data(contentsOf: backup), encoding: .utf8)
    #expect(backedUp == garbage)

    // 백업 후에도 계속 쓸 수 있다(새 항목이 정상 저장된다).
    store.add("새로 시작")
    let rewritten = try TodoFileStore.load(from: url)
    #expect(rewritten.items.map(\.title) == ["새로 시작"])
}

/// 스토어 변경이 디스크에 남아 다음 인스턴스가 그대로 이어받는지(로컬 전용이라 이 왕복이 유일한 영속 경로다).
@MainActor
@Test
func todoStorePersistsAcrossInstances() {
    let url = makeTempTodoURL()
    var now = kst(2026, 8, 12, 9, 0)

    let first = TodoListStore(fileURL: url, clock: { now })
    let keep = first.add("남길 일")!
    let done = first.add("끝낼 일")!
    let gone = first.add("지울 일")!
    now = kst(2026, 8, 12, 9, 30)
    first.toggleDone(done.id)
    first.delete(gone.id)

    let second = TodoListStore(fileURL: url, clock: { now })
    #expect(second.items.count == 3)                                    // 톰스톤까지 그대로 실린다
    #expect(second.items.first(where: { $0.id == keep.id })?.title == "남길 일")
    #expect(second.items.first(where: { $0.id == done.id })?.completedAt == kst(2026, 8, 12, 9, 30))
    #expect(second.items.first(where: { $0.id == gone.id })?.deletedAt == kst(2026, 8, 12, 9, 30))

    // 화면에 뜨는 건 톰스톤을 뺀 둘, 그중 미완료가 위.
    #expect(TodoRules.visible(second.items, todayKey: second.todayKey).map(\.title) == ["남길 일", "끝낼 일"])
}

/// 로그인 전/후 파일이 갈리고, 외부에서 온 userID 가 경로를 탈출하지 못한다.
@Test
func todoDefaultURLSeparatesUsersAndResistsPathEscape() {
    let anonymous = TodoFileStore.defaultURL(userID: nil)
    #expect(anonymous.lastPathComponent == "todos.local.json")
    #expect(anonymous.deletingLastPathComponent().lastPathComponent == "aing-check")

    #expect(TodoFileStore.defaultURL(userID: "").lastPathComponent == "todos.local.json")
    #expect(TodoFileStore.defaultURL(userID: "7f3a-42bc").lastPathComponent == "todos.7f3a-42bc.json")

    // 구분자·점이 섞여도 파일명 안에 머문다(폴더는 언제나 aing-check 하나).
    let escaping = TodoFileStore.defaultURL(userID: "../../etc/passwd")
    #expect(escaping.lastPathComponent == "todos.etcpasswd.json")
    #expect(escaping.deletingLastPathComponent().lastPathComponent == "aing-check")
}
