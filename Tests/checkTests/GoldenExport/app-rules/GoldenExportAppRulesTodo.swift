import CheckGoldenSupport
import Foundation
import Testing
@testable import CheckCore

// W1-c 앱 규칙 — 할 일(C§5.1 E12: LWW 병합 · 워터마크 · 배치 · 정렬, C§4 #10 p_since_ms null 싣기). Kotlin 은 core/rules/…/todo.
//
//   · todo/rules   제목 정규화 · 상한 · 날짜 키 · 이월 배지 · 노출 · 정렬 · 정리 · 정수 ms · mergedSync 시나리오
//   · todo/wire    todo_sync 응답(실서버 기록 픽스처 Tests/checkTests/Fixtures/todo-rpc) 디코드 · 합칠 결과 · 요청 본문 · 배치(500)

@Suite("GoldenExport app-rules — 할 일(todo)")
struct GoldenExportAppRulesTodo {
    static func n(_ value: Int64?) -> GoldenJSON {
        guard let value else { return .null }
        if value >= -Int64(GoldenJSON.maxSafeInteger) && value <= Int64(GoldenJSON.maxSafeInteger) { return .int(Int(value)) }
        return .string("int:\(value)")
    }
    static func s(_ value: String?) -> GoldenJSON { value.map(GoldenJSON.string) ?? .null }
    static func d(_ value: Date?) -> GoldenJSON { value.map { .bits($0.timeIntervalSince1970) } ?? .null }
    static func cps(_ text: String) -> String {
        text.unicodeScalars.map { String($0.value, radix: 16) }.map { String(repeating: "0", count: max(0, 4 - $0.count)) + $0 }.joined(separator: " ")
    }

    static func uuid(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", n))! }

    static func item(_ n: Int, title: String = "할 일", created: Double, updated: Double? = nil, completed: Double? = nil,
                     deleted: Double? = nil, origin: String = "20261026") -> TodoItem {
        TodoItem(id: uuid(n), title: title, createdAt: Date(timeIntervalSince1970: created),
                 updatedAt: Date(timeIntervalSince1970: updated ?? created), completedAt: completed.map { Date(timeIntervalSince1970: $0) },
                 deletedAt: deleted.map { Date(timeIntervalSince1970: $0) }, originDayKey: origin)
    }

    static func itemJSON(_ item: TodoItem) -> GoldenJSON {
        ["id": .string(item.id.uuidString.lowercased()), "title": .string(cps(item.title)), "createdAt": d(item.createdAt),
         "updatedAt": d(item.updatedAt), "completedAt": d(item.completedAt), "deletedAt": d(item.deletedAt),
         "originDayKey": .string(item.originDayKey)]
    }

    static func ids(_ set: Set<UUID>) -> GoldenJSON { .array(set.map { $0.uuidString.lowercased() }.sorted().map(GoldenJSON.string)) }

    static let titleCorpus: [String] = [
        "", " ", "회의 준비", "  회의   준비  ", "회의\n준비", "회의\t\t준비", "회의\u{0007}준비", "회의\u{200B}준비", "회의\u{200D}준비",
        "👨‍👩‍👧‍👦 가족", "\u{1112}\u{1161}\u{11AB}\u{1100}\u{1173}\u{11AF}", " \u{0301}x", "a\u{00A0}b", "a\u{3000}b", "a\u{2028}b",
        "a\u{0085}b", "a\u{FEFF}b", "a\u{202E}b", "a\u{3164}b", "\u{200D}", "\r\n두 줄\r\n", String(repeating: "가", count: 100),
        String(repeating: "가", count: 101), String(repeating: "👨🏽‍👩🏽‍👧🏽‍👦🏽", count: 90), String(repeating: "👨🏽‍👩🏽‍👧🏽‍👦🏽", count: 91),
        String(repeating: "e\u{0301}", count: 100), "a\u{180E}b", "a\u{2060}b", "끝 ",
    ]

    @Test("todo/rules — 제목 · 상한 · 날짜 · 이월 · 노출 · 정렬 · 정리 · ms · 병합")
    func todoRules() {
        var cases: [GoldenJSON] = []
        cases.append(["id": "titles", "rows": .array(Self.titleCorpus.map { raw in
            let normalized = TodoRules.normalizedTitle(raw)
            return ["cps": .string(Self.cps(raw)), "normalized": .string(Self.cps(normalized)),
                    "fits": .bool(TodoRules.titleFitsLimits(normalized)), "fitsRaw": .bool(TodoRules.titleFitsLimits(raw))]
        }), "constants": ["maxTitleLength": .int(TodoRules.maxTitleLength), "maxTitleCodePoints": .int(TodoRules.maxTitleCodePoints),
                          "counterVisibleFrom": .int(TodoRules.counterVisibleFrom), "oldItemDays": .int(TodoRules.oldItemDays),
                          "purgeDays": .int(TodoRules.purgeDays), "undoSecondsBits": .bits(TodoRules.undoSeconds)]])
        let keys = ["20261026", "20261025", "20261019", "20261001", "20260101", "20261231", "20270101", "20261027", "2026102", "202610266",
                    "2026-10-", "abcdefgh", "２０２６１０２６", "20261326", "20261000", "00000101"]
        var carried: [GoldenJSON] = []
        for origin in keys {
            for today in ["20261026", "20261102", "20250101"] {
                let days = TodoRules.carriedDays(originDayKey: origin, todayKey: today)
                carried.append(["origin": .string(origin), "today": .string(today), "days": .int(days), "badge": Self.s(TodoRules.carryBadge(days: days))])
            }
        }
        cases.append(["id": "carried", "rows": .array(carried), "badges": .array([-1, 0, 1, 2, 7, 100].map { ["days": .int($0), "badge": Self.s(TodoRules.carryBadge(days: $0))] })])
        // 노출 · 정렬 · 오래된 항목 · 정리.
        let base = 1_792_940_400.0   // 2026-10-26 00:00 KST(월)
        let items: [TodoItem] = [
            Self.item(1, created: base + 100),
            Self.item(2, created: base + 200, completed: base + 300),
            Self.item(3, created: base - 86_400 * 8, origin: "20261018"),
            Self.item(4, created: base + 50, completed: base - 10),
            Self.item(5, created: base + 60, deleted: base + 70),
            Self.item(6, created: base + 200, completed: base + 400),
            Self.item(7, created: base + 200),
            Self.item(8, created: base - 86_400 * 100, completed: base - 86_400 * 95),
            Self.item(9, created: base - 86_400 * 100, deleted: base - 86_400 * 91),
            Self.item(10, created: base - 86_400 * 100, deleted: base - 86_400 * 89),
            Self.item(11, created: base - 86_400 * 100, origin: "20260718"),
            Self.item(12, created: base + 200, completed: base + 300),
        ]
        var visibility: [GoldenJSON] = []
        for today in ["20261026", "20261025", "20261027"] {
            visibility.append([
                "today": .string(today),
                "visible": .array(TodoRules.visible(items, todayKey: today).map { .string($0.id.uuidString.lowercased()) }),
                "visibleKeeping5": .array(TodoRules.visible(items, todayKey: today, keepingDeleted: Self.uuid(5)).map { .string($0.id.uuidString.lowercased()) }),
                "old": .array(items.filter { TodoRules.isOld($0, todayKey: today) }.map { .string($0.id.uuidString.lowercased()) }),
            ])
        }
        cases.append(["id": "visibility", "items": .array(items.map(Self.itemJSON)), "rows": .array(visibility),
                      "pruned": .array(TodoRules.pruned(items, now: Date(timeIntervalSince1970: base)).map { .string($0.id.uuidString.lowercased()) })])
        // 정수 ms.
        let times: [Double] = [0, 1.0005, 1.0004999, -1.0005, 1_792_940_400.123456, 1_792_940_400.1235, 4_102_444_800.122_999_99, 9e15, -9e15, .infinity, -.infinity, .nan]
        cases.append(["id": "milliseconds", "rows": .array(times.map { t in
            let ms = TodoRules.milliseconds(Date(timeIntervalSince1970: t))
            return ["secondsBits": .bits(t), "ms": Self.n(ms), "roundTripBits": .bits(TodoRules.date(milliseconds: ms).timeIntervalSince1970),
                    "normalizedBits": .bits(TodoRules.normalizedTime(Date(timeIntervalSince1970: t)).timeIntervalSince1970)]
        })])
        // mergedSync 시나리오.
        func merge(_ name: String, local: [TodoItem], pending: Set<UUID>, sent: [UUID: Int64], server: [TodoItem], rejected: Set<UUID>,
                   full: Bool, held: Set<UUID> = [], protected: Set<UUID> = []) -> GoldenJSON {
            let result = TodoRules.mergedSync(local: local, pending: pending, sent: sent, server: server, rejected: rejected, full: full,
                                              held: held, protected: protected)
            let again = TodoRules.mergedSync(local: result.items, pending: result.pending, sent: sent, server: server, rejected: rejected,
                                             full: full, held: result.heldRejectedIDs, protected: protected)
            return [
                "id": .string("merge-\(name)"),
                "local": .array(local.map(Self.itemJSON)), "pending": Self.ids(pending),
                "sent": .object(Dictionary(uniqueKeysWithValues: sent.map { ($0.key.uuidString.lowercased(), Self.n($0.value)) })),
                "server": .array(server.map(Self.itemJSON)), "rejected": Self.ids(rejected), "full": .bool(full), "held": Self.ids(held),
                "protected": Self.ids(protected),
                "result": ["items": .array(result.items.map(Self.itemJSON)), "pending": Self.ids(result.pending),
                           "heldRejectedIDs": Self.ids(result.heldRejectedIDs), "deferredIDs": Self.ids(result.deferredIDs)],
                "idempotent": .bool(again.items == result.items && again.pending == result.pending && again.heldRejectedIDs == result.heldRejectedIDs),
            ]
        }
        let a = Self.item(1, title: "가", created: base, updated: base + 10)
        let aServerOld = Self.item(1, title: "가 서버", created: base, updated: base + 5)
        let aServerNew = Self.item(1, title: "가 서버 새것", created: base, updated: base + 20)
        let aServerSame = Self.item(1, title: "가 서버 동률", created: base, updated: base + 10)
        let b = Self.item(2, title: "나", created: base + 1)
        let bServer = Self.item(2, title: "나 서버", created: base + 1, updated: base + 30)
        let c = Self.item(3, title: "다", created: base + 2)
        let dServerOnly = Self.item(4, title: "라(서버만)", created: base + 3)
        let aEditedAfterSend = Self.item(1, title: "가 또 고침", created: base, updated: base + 15)
        let aMs = TodoRules.milliseconds(a.updatedAt)
        cases.append(merge("plain", local: [a, b, c], pending: [], sent: [:], server: [aServerNew, bServer, dServerOnly], rejected: [], full: false))
        cases.append(merge("local-newer-pending", local: [a, b], pending: [Self.uuid(1)], sent: [:], server: [aServerOld], rejected: [], full: false))
        cases.append(merge("same-ms-server-wins", local: [a], pending: [Self.uuid(1)], sent: [:], server: [aServerSame], rejected: [], full: false))
        cases.append(merge("sent-unchanged", local: [a], pending: [Self.uuid(1)], sent: [Self.uuid(1): aMs], server: [aServerOld], rejected: [], full: false))
        cases.append(merge("sent-then-edited", local: [aEditedAfterSend], pending: [Self.uuid(1)], sent: [Self.uuid(1): aMs], server: [aServerOld], rejected: [], full: false))
        cases.append(merge("rejected-unchanged", local: [a, b], pending: [Self.uuid(1)], sent: [Self.uuid(1): aMs], server: [aServerOld], rejected: [Self.uuid(1), Self.uuid(9)], full: false))
        cases.append(merge("rejected-edited", local: [aEditedAfterSend], pending: [Self.uuid(1)], sent: [Self.uuid(1): aMs], server: [aServerOld], rejected: [Self.uuid(1)], full: false))
        cases.append(merge("rejected-same-row", local: [a], pending: [Self.uuid(1)], sent: [Self.uuid(1): aMs], server: [a], rejected: [Self.uuid(1)], full: false))
        cases.append(merge("held-keeps-local", local: [a, b], pending: [], sent: [:], server: [aServerNew], rejected: [], full: false, held: [Self.uuid(1), Self.uuid(8)]))
        cases.append(merge("held-vs-pending", local: [a], pending: [Self.uuid(1)], sent: [:], server: [aServerOld], rejected: [], full: false, held: [Self.uuid(1)]))
        cases.append(merge("full-drops", local: [a, b, c], pending: [Self.uuid(3)], sent: [:], server: [b], rejected: [], full: true, held: [Self.uuid(1)]))
        cases.append(merge("full-protected", local: [a, b, c], pending: [], sent: [:], server: [], rejected: [], full: true, protected: [Self.uuid(2)]))
        cases.append(merge("protected-defers", local: [a, b], pending: [], sent: [:], server: [aServerNew, b], rejected: [], full: false, protected: [Self.uuid(1), Self.uuid(2)]))
        cases.append(merge("duplicates", local: [a, a, b], pending: [Self.uuid(7)], sent: [:], server: [bServer, bServer, dServerOnly, dServerOnly], rejected: [], full: false))
        cases.append(merge("empty", local: [], pending: [], sent: [:], server: [], rejected: [], full: true))
        goldenEmit(GoldenFile(
            golden: "todo/rules",
            equivalence: .bit,
            swiftSources: ["Sources/CheckCore/CheckTodoModel.swift", "Sources/CheckCore/MilestoneTracker.swift"],
            platformSensitive: true,
            spec: [
                "titles": "normalizedTitle — NFC → 스칼라마다(ZWJ 는 둔다 · 제어 Cc/서식 Cf 는 White_Space 면 공백, 아니면 버림) → 글자(그래핌) 중 첫 스칼라가 White_Space 인 것을 가르개로 나눠 공백 하나로 잇기. titleFitsLimits = 그래핌 ≤ 100 · 스칼라 ≤ 1000",
                "carried": "carriedDays — 'yyyyMMdd'(ASCII 숫자 8자) 두 개를 KST 0시로(lenient) 바꿔 달력 날 차(음수 0). 배지: 0 이하 없음 · 1 '어제' · N 'N일 전'",
                "visibility": "isVisible = 삭제 아님 + (미완료 또는 완료 날 == 오늘) · 정렬 = 미완료 먼저 → 완료끼리는 완료 시각 최신 → 만든 시각 최신 → id(대문자 uuid 글자) · isOld = 미완료이고 이월 7일 이상 · pruned = 90일(KST 달력) 전보다 오래된 완료/삭제",
                "milliseconds": "(초 × 1000).rounded()(0.5 → 0 에서 먼 쪽), NaN → 0, ±8.64e15 로 누름",
                "merge": "mergedSync — ⓪ 없는 id 버림 · pending 이 붙잡기를 이김 ① 보낸 값과 같으면 pending 해제 ② rejected: 안 고쳤으면 붙잡기(서버 행이 같으면 아무것도) · 고쳤으면 pending ③ 같은 id: 붙잡힘 → 로컬, pending 이고 로컬이 더 새것 → 로컬, 보호 → 로컬 + 미룸, 아니면 서버 ④ full 이면 서버에 없고 pending·붙잡기 아닌 로컬 삭제(보호는 미룸) ⑤ 서버에만 있는 것 뒤에(서버 순서). idempotent = 같은 응답을 한 번 더 합쳐도 같다",
                "platformSensitive": "true — NFC · 그래핌 · KST 달력",
            ],
            cases: cases
        ))
    }

    @Test("todo/wire — todo_sync 응답(실서버 기록) 디코드 · 합칠 결과 · 요청 본문 · 배치")
    @MainActor
    func todoWire() throws {
        var cases: [GoldenJSON] = []
        let directory = GoldenRepo.url("Tests/checkTests/Fixtures/todo-rpc")
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).filter { $0.hasPrefix("todo_sync__") }.sorted()
        #expect(names.count >= 13, "todo-rpc 픽스처가 \(names.count) 개뿐이다")
        var bodies: [(String, String)] = names.map { name in
            (name, (try? String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)) ?? "")
        }
        bodies += [
            ("synthetic-bad-rows", #"{"status":"ok","watermark_ms":1792940400123,"full":true,"items":[{"id":"00000000-0000-4000-8000-000000000001","title":"가","created_at_ms":1,"updated_at_ms":2,"origin_day_key":"20261026"},{"id":"not-a-uuid","title":"나","created_at_ms":1,"updated_at_ms":2,"origin_day_key":"20261026"},{"id":"00000000-0000-4000-8000-000000000003","title":7,"created_at_ms":1,"updated_at_ms":2,"origin_day_key":"20261026"},{"id":"00000000-0000-4000-8000-000000000004","title":"라","created_at_ms":1.5,"updated_at_ms":"2","origin_day_key":"20261026","completed_at_ms":3,"deleted_at_ms":null}],"rejected":[{"id":"00000000-0000-4000-8000-00000000000A","reason":"too_long"},{"id":"zz","reason":"x"},{"reason":"only"},5],"max":"500"}"#),
            ("synthetic-status-only", #"{"status":"ok"}"#),
            ("synthetic-not-object", #"[1,2]"#),
            ("synthetic-upper-id", #"{"status":"ok","watermark_ms":5,"items":[{"id":"ABCDEF00-0000-4000-8000-000000000001","title":"대문자","created_at_ms":1,"updated_at_ms":1,"origin_day_key":"20261026"}]}"#),
        ]
        for (name, text) in bodies {
            let response: TodoSyncResponse
            do {
                response = try TodoSyncResponse.decode(Data(text.utf8))
            } catch {
                cases.append(["id": .string("response-\(name)"), "json": .string(text), "throws": true])
                continue
            }
            let result = response.mergeableResult()
            cases.append([
                "id": .string("response-\(name)"), "json": .string(text),
                "status": Self.s(response.status), "watermarkMs": Self.n(response.watermarkMs), "full": response.full.map(GoldenJSON.bool) ?? .null,
                "max": response.max.map { .int($0) } ?? .null,
                "items": response.items.map { .array($0.map { w in
                    ["id": Self.s(w.id), "title": w.title.map { .string(Self.cps($0)) } ?? .null, "createdAtMs": Self.n(w.createdAtMs),
                     "updatedAtMs": Self.n(w.updatedAtMs), "completedAtMs": Self.n(w.completedAtMs), "deletedAtMs": Self.n(w.deletedAtMs),
                     "originDayKey": Self.s(w.originDayKey), "todoItem": w.todoItem().map(Self.itemJSON) ?? .null]
                }) } ?? .null,
                "rejected": response.rejected.map { .array($0.map { ["id": Self.s($0.id), "reason": Self.s($0.reason)] }) } ?? .null,
                "mergeable": result.map { ["items": .array($0.items.map(Self.itemJSON)), "rejectedIDs": Self.ids($0.rejectedIDs),
                                           "full": .bool($0.full), "watermarkMs": Self.n($0.watermarkMs)] } ?? .null,
            ])
        }
        // 요청 본문(키를 언제나 싣는다 — p_since_ms null 포함).
        let base = 1_792_940_400.0
        let wireItems = [Self.item(1, title: "가/나", created: base + 0.001, updated: base + 0.0015, completed: base + 2, origin: "20261026"),
                         Self.item(2, title: "😀", created: base, deleted: base + 3)].map(TodoSyncWireItem.init(item:))
        for (index, since) in [nil, Int64(0), Int64(1_792_940_400_123)].enumerated() {
            let request = TodoSyncRequest(changes: index == 0 ? [] : wireItems, sinceMs: since)
            cases.append(["id": .string("request-\(index)"), "rpcBody": .string(String(data: try request.rpcBody(), encoding: .utf8)!),
                          "changesJSON": .string(String(data: try request.changesJSON(), encoding: .utf8)!)])
        }
        // 배치(대문자 uuid 글자 순 · 500 개씩 · 비면 빈 묶음 하나).
        var counts: [GoldenJSON] = []
        for count in [0, 1, 499, 500, 501, 1_000, 1_001] {
            let ids = (0..<count).map { Self.uuid(($0 * 7919) % 100_003) }
            let sorted = ids.sorted { $0.uuidString < $1.uuidString }
            var batches: [[UUID]] = stride(from: 0, to: sorted.count, by: TodoSync.batchLimit).map { Array(sorted[$0..<min($0 + TodoSync.batchLimit, sorted.count)]) }
            if batches.isEmpty { batches = [[]] }
            counts.append(["count": .int(count), "sizes": .array(batches.map { .int($0.count) }),
                           "firsts": .array(batches.map { Self.s($0.first?.uuidString.lowercased()) })])
        }
        cases.append(["id": "batches", "batchLimit": .int(TodoSync.batchLimit), "debounceBits": .bits(TodoSync.debounceSeconds),
                      "periodicBits": .bits(TodoSync.periodicSeconds), "cooldownBits": .bits(TodoSync.serverMissingCooldownSeconds),
                      "rows": .array(counts)])
        goldenEmit(GoldenFile(
            golden: "todo/wire",
            equivalence: .bit,
            swiftSources: ["Sources/CheckCore/TodoSync.swift", "Sources/CheckCore/CheckTodoModel.swift", "Tests/checkTests/Fixtures/todo-rpc/_manifest.json"],
            platformSensitive: false,
            spec: [
                "response": "TodoSyncResponse — 칸마다 try?(모양이 틀리면 null), 최상위가 객체가 아니면 throw. todoItem = id 가 uuid 이고 제목 · 만든/고친 ms · 원래 날이 있을 때만(소문자로 접는다)",
                "mergeable": "status 'ok' 이고 items · watermark 가 있을 때만. full 은 모든 행을 읽었을 때만 참(못 읽은 행이 있으면 full 병합을 끈다 — C§3.2 B-3)",
                "request": "rpcBody = {p_changes, p_since_ms}(null 도 싣는다 · 키 정렬 · 슬래시 이스케이프 없음) — 전선 키는 snake 고정",
                "batches": "pending id 를 대문자 uuid 글자 순으로 500 개씩, 비면 빈 묶음 하나(watermark 만 묻는다)",
            ],
            cases: cases
        ))
    }
}
