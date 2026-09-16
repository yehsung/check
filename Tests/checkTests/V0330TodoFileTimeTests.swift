import Foundation
import Testing
@testable import check

// MARK: - v0.3.30 할 일 동기화 ① 시각 정규화 · 파일 2세대
//
// 지키는 것:
// · ms 변환은 한 함수, 반올림 규칙 하나 — 서버에서 온 ms → Date → ms 가 **항상** 같은 정수로 돌아온다(2020~2100 속성).
// · 만들 때·고칠 때의 Date 는 ms 격자 위에 있다(파일 저장→로드 왕복에서도).
// · 1세대(또는 version 없음) 파일은 items 그대로 + **모든 id 가 pending** (업데이트 후 첫 동기화 = 전원 자동 전환).
// · 0.3.29 의 디코더(아래 사본)가 2세대 파일을 읽어도 items 가 읽힌다(모르는 키 무시).

/// 시드 고정 난수(SplitMix64) — 속성 테스트가 실패하면 같은 입력으로 다시 돌릴 수 있어야 한다.
struct TodoSyncV0330RNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// 실제 Application Support 를 건드리지 않는 고유 임시 경로.
func todoSyncV0330TempURL(_ name: String = "todos.local.json") -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("check-v0330-todo-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent(name, isDirectory: false)
}

private let msAt2020: Int64 = 1_577_836_800_000     // 2020-01-01T00:00:00Z
private let msAt2100: Int64 = 4_102_444_800_000     // 2100-01-01T00:00:00Z

// MARK: 시각

@Test("서버 ms → Date → ms 는 2020~2100 임의 값 5000개에서 전부 같은 정수로 돌아온다(파일 JSON 왕복 포함)")
func todoMillisecondsRoundTripIsExactAcrossCentury() throws {
    var rng = TodoSyncV0330RNG(seed: 0x0330_7D0)
    var samples: [Int64] = (0..<5000).map { _ in Int64.random(in: msAt2020...msAt2100, using: &rng) }
    // 경계: ms 자리 000·999·001, 소수 오차가 가장 커지는 2100 근처
    samples += [msAt2020, msAt2100, 1_726_500_000_000, 1_726_500_000_999, 1_726_500_000_001, msAt2100 - 1]
    var mismatches: [Int64] = []
    for ms in samples {
        let date = TodoRules.date(milliseconds: ms)
        if TodoRules.milliseconds(date) != ms { mismatches.append(ms) }
        // 정규화는 이미 격자 위에 있는 값을 건드리지 않는다.
        if TodoRules.normalizedTime(date) != date { mismatches.append(-ms) }
    }
    #expect(mismatches.isEmpty, "왕복이 어긋난 ms: \(mismatches.prefix(5))")

    // 파일 경로(Date 기본 인코딩 = 참조일 기준 Double)로도 같은 정수가 돌아온다.
    let items = samples.prefix(400).map { ms in
        TodoItem(
            id: UUID(), title: "t", createdAt: TodoRules.date(milliseconds: ms),
            updatedAt: TodoRules.date(milliseconds: ms), completedAt: TodoRules.date(milliseconds: ms),
            deletedAt: nil, originDayKey: "20260916"
        )
    }
    let url = todoSyncV0330TempURL()
    try TodoFileStore.save(TodoFile(items: items), to: url)
    let loaded = try TodoFileStore.load(from: url)
    #expect(loaded.items == items)
    #expect(zip(loaded.items, samples.prefix(400)).allSatisfy { $0.updatedAtMs == $1 && TodoRules.milliseconds($0.completedAt!) == $1 })
}

@Test("변환은 반올림 하나다 — 0.4ms 는 내리고 0.6ms 는 올린다, 손상된 천문학적 값에서도 죽지 않는다")
func todoMillisecondsUseOneRoundingRule() {
    let base = Date(timeIntervalSince1970: 1_726_500_000)
    #expect(TodoRules.milliseconds(base.addingTimeInterval(0.1234)) == 1_726_500_000_123)
    #expect(TodoRules.milliseconds(base.addingTimeInterval(0.1236)) == 1_726_500_000_124)
    #expect(TodoRules.milliseconds(Date(timeIntervalSinceReferenceDate: .greatestFiniteMagnitude)) > 0)
    #expect(TodoRules.milliseconds(Date(timeIntervalSinceReferenceDate: -.greatestFiniteMagnitude)) < 0)
}

@MainActor
@Test("만들 때·고칠 때의 시각은 ms 격자 위에 저장된다 — 소수 ms 시계여도")
func todoStoreStampsMillisecondTimes() throws {
    var now = Date(timeIntervalSince1970: 1_726_500_000.123_456_7)
    let url = todoSyncV0330TempURL()
    let store = TodoListStore(fileURL: url, clock: { now })
    let item = try #require(store.add("정규화"))
    #expect(item.createdAt == TodoRules.date(milliseconds: 1_726_500_000_123))
    #expect(item.updatedAt == item.createdAt)

    now = Date(timeIntervalSince1970: 1_726_500_060.987_654_3)
    store.toggleDone(item.id)
    let done = try #require(store.items.first)
    #expect(done.completedAt == TodoRules.date(milliseconds: 1_726_500_060_988))
    #expect(done.updatedAt == TodoRules.date(milliseconds: 1_726_500_060_988))

    let reread = TodoListStore(fileURL: url, clock: { now })
    #expect(reread.items == store.items)
}

@MainActor
@Test("고친 시각은 이전보다 반드시 커진다 — 같은 ms 두 번째 수정·시계 역행에도 서버 LWW 에서 지지 않게")
func todoUpdatedAtIsStrictlyIncreasing() throws {
    var now = Date(timeIntervalSince1970: 1_726_500_000)
    let store = TodoListStore(fileURL: todoSyncV0330TempURL(), clock: { now })
    let item = try #require(store.add("체크했다 곧바로 푼다"))
    store.toggleDone(item.id)            // 같은 ms
    let first = try #require(store.items.first).updatedAtMs
    #expect(first == item.updatedAtMs + 1)
    store.toggleDone(item.id)            // 또 같은 ms
    #expect(try #require(store.items.first).updatedAtMs == first + 1)

    now = now.addingTimeInterval(-600)   // 시계가 10분 뒤로 갔다
    store.rename(item.id, to: "시계가 돌아간 뒤 고침")
    #expect(try #require(store.items.first).updatedAtMs == first + 2)
}

// MARK: 파일 세대

/// 0.3.29 의 파일 디코더 **사본**(CheckTodoModel.swift @ ac06073 에서 글자 그대로 옮김). 옛 앱이 새 파일을 읽을 수 있는지를
/// 현재 코드가 아니라 이 사본으로 잰다 — 현재 디코더로 재면 거울 테스트가 된다.
private struct LegacyV0329TodoItem: Codable, Equatable {
    let id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var completedAt: Date? = nil
    var deletedAt: Date? = nil
    var originDayKey: String
}

private struct LegacyV0329TodoFile: Codable, Equatable {
    var version: Int
    var items: [LegacyV0329TodoItem]

    enum CodingKeys: String, CodingKey {
        case version, items
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        items = try c.decode([LegacyV0329TodoItem].self, forKey: .items)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version, forKey: .version)
        try c.encode(items, forKey: .items)
    }
}

private func legacyItem(_ title: String, ms: Int64) -> LegacyV0329TodoItem {
    LegacyV0329TodoItem(
        id: UUID(), title: title,
        // 옛 앱은 ms 로 자르지 않았다 — 소수 ms 가 남은 값을 그대로 쓴다.
        createdAt: Date(timeIntervalSince1970: Double(ms) / 1000 + 0.000_4),
        updatedAt: Date(timeIntervalSince1970: Double(ms) / 1000 + 0.000_7),
        completedAt: nil, deletedAt: nil, originDayKey: "20260915"
    )
}

@MainActor
@Test("1세대 파일(version 1·version 없음)은 items 그대로 + 모든 id 가 pending, watermark 없음 — 읽자마자 2세대로 다시 쓴다")
func todoFirstGenerationFileMarksEverythingPending() throws {
    let now = Date(timeIntervalSince1970: 1_726_500_000)
    let legacy = LegacyV0329TodoFile(legacyItems: [legacyItem("하나", ms: 1_726_400_000_000), legacyItem("둘", ms: 1_726_400_100_000)])

    for withVersionKey in [true, false] {
        let url = todoSyncV0330TempURL()
        var data = try JSONEncoder().encode(legacy)
        if !withVersionKey {
            var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            object["version"] = nil
            data = try JSONSerialization.data(withJSONObject: object)
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url)

        // 디코더 자체의 규칙
        let decoded = try TodoFileStore.load(from: url)
        #expect(decoded.items.map(\.id) == legacy.items.map(\.id))
        #expect(Set(decoded.sync.pendingIDs) == Set(legacy.items.map(\.id)), "1세대 파일의 id 가 전부 pending 이 아니다")
        #expect(decoded.sync.watermarkMs == nil)

        // 스토어가 읽으면 시각을 ms 로 올리고 2세대로 다시 쓴다
        let store = TodoListStore(fileURL: url, clock: { now })
        #expect(store.pendingIDs == Set(legacy.items.map(\.id)))
        #expect(store.watermarkMs == nil)
        #expect(store.items.map(\.title) == ["하나", "둘"])
        #expect(store.items.allSatisfy { TodoRules.normalizedTime($0.updatedAt) == $0.updatedAt })
        let raw = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        #expect(raw["version"] as? Int == 2)
        let sync = try #require(raw["sync"] as? [String: Any])
        #expect(sync["watermarkMs"] is NSNull, "watermarkMs 는 키를 빼지 않고 null 로 싣는다")
        #expect((sync["pendingIDs"] as? [String])?.count == 2)
    }
}

private extension LegacyV0329TodoFile {
    init(legacyItems items: [LegacyV0329TodoItem]) {
        version = 1
        self.items = items
    }
}

@MainActor
@Test("0.3.29 디코더가 2세대 파일을 읽어도 items 가 그대로 읽힌다(모르는 sync 키 무시)")
func todoLegacyAppReadsSecondGenerationFile() throws {
    var now = Date(timeIntervalSince1970: 1_726_500_000)
    let url = todoSyncV0330TempURL()
    let store = TodoListStore(fileURL: url, clock: { now })
    let a = try #require(store.add("새 앱이 쓴 줄"))
    now = now.addingTimeInterval(30)
    let b = try #require(store.add("지운 줄"))
    store.delete(b.id)
    store.toggleDone(a.id)

    let bytes = try Data(contentsOf: url)
    #expect(String(decoding: bytes, as: UTF8.self).contains("\"sync\""))
    let legacy = try JSONDecoder().decode(LegacyV0329TodoFile.self, from: bytes)
    #expect(legacy.version == 2)
    #expect(legacy.items.map(\.id) == store.items.map(\.id))
    #expect(legacy.items.map(\.title) == store.items.map(\.title))
    #expect(legacy.items.map(\.completedAt) == store.items.map(\.completedAt))
    #expect(legacy.items.map(\.deletedAt) == store.items.map(\.deletedAt))
    #expect(legacy.items.map(\.updatedAt) == store.items.map(\.updatedAt))
}

@MainActor
@Test("2세대 파일의 sync 가 없거나 깨졌으면 목록은 살리고(백업으로 치우지 않는다) 전부 pending 으로 읽는다")
func todoBrokenSyncStateFallsBackToAllPending() throws {
    let now = Date(timeIntervalSince1970: 1_726_500_000)
    let item = TodoItem(
        id: UUID(), title: "살아야 하는 줄", createdAt: TodoRules.date(milliseconds: 1_726_400_000_000),
        updatedAt: TodoRules.date(milliseconds: 1_726_400_000_000), originDayKey: "20260915"
    )
    let itemsJSON = String(decoding: try JSONEncoder().encode([item]), as: UTF8.self)
    for syncFragment in ["", ",\"sync\":{\"watermarkMs\":12,\"pendingIDs\":[\"not-a-uuid\"]}", ",\"sync\":42"] {
        let url = todoSyncV0330TempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{\"version\":2,\"items\":\(itemsJSON)\(syncFragment)}".utf8).write(to: url)
        let store = TodoListStore(fileURL: url, clock: { now })
        #expect(store.items == [item], "sync 조각 \(syncFragment) 때문에 목록이 사라졌다")
        #expect(store.pendingIDs == [item.id])
        #expect(store.watermarkMs == nil)
        let backups = try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
            .filter { $0.contains("corrupt") }
        #expect(backups.isEmpty)
    }
}

@MainActor
@Test("2세대 파일의 watermark·pending 은 저장→로드 왕복에서 그대로 살아남는다")
func todoSecondGenerationSyncStateRoundTrips() throws {
    let now = Date(timeIntervalSince1970: 1_726_500_000)
    let items = (0..<3).map { index in
        TodoItem(
            id: UUID(), title: "줄 \(index)", createdAt: TodoRules.date(milliseconds: 1_726_400_000_000 + Int64(index)),
            updatedAt: TodoRules.date(milliseconds: 1_726_400_000_000 + Int64(index)), originDayKey: "20260915"
        )
    }
    let url = todoSyncV0330TempURL()
    try TodoFileStore.save(
        TodoFile(items: items, sync: TodoFileSyncState(watermarkMs: 1_726_499_999_999, pendingIDs: [items[1].id])),
        to: url
    )
    let store = TodoListStore(fileURL: url, clock: { now })
    #expect(store.pendingIDs == [items[1].id])
    #expect(store.watermarkMs == 1_726_499_999_999)
}

@MainActor
@Test("90일 정리로 빠진 항목은 pending 에서도 빠진다(명세 A4-9)")
func todoPruneAlsoDropsPendingIDs() throws {
    let now = Date(timeIntervalSince1970: 1_726_500_000)
    let ancient = now.addingTimeInterval(-100 * 86_400)
    let old = TodoItem(
        id: UUID(), title: "100일 전에 끝낸 일", createdAt: TodoRules.normalizedTime(ancient),
        updatedAt: TodoRules.normalizedTime(ancient), completedAt: TodoRules.normalizedTime(ancient), originDayKey: "20260608"
    )
    let alive = TodoItem(
        id: UUID(), title: "살아 있는 일", createdAt: TodoRules.normalizedTime(now),
        updatedAt: TodoRules.normalizedTime(now), originDayKey: "20260917"
    )
    let url = todoSyncV0330TempURL()
    try TodoFileStore.save(TodoFile(items: [old, alive], sync: TodoFileSyncState(watermarkMs: 5, pendingIDs: [old.id, alive.id])), to: url)
    let store = TodoListStore(fileURL: url, clock: { now })
    #expect(store.items == [alive])
    #expect(store.pendingIDs == [alive.id])
    #expect(try TodoFileStore.load(from: url).sync.pendingIDs == [alive.id])
}
