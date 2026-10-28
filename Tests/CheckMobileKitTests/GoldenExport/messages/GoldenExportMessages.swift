// 원본: 없음 — W2-b 메시지 골든 생성기(Sources/CheckMobileKit/Messages/MessagesRules.swift · Sources/CheckCore/MessagePokeLog.swift:314-526 ·
// Sources/CheckCore/SupabaseWorkModels.swift `sortedForPokeDisplay` 를 잰다). Kotlin 은 core/stores/…/messages(MessagesGoldenTest).
@testable import CheckCore
import CheckGoldenSupport
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

// G §2-3 W2-b · 배정표 round5-lane-map.md:21·44·45·50 — 네 무리 정렬 · 찌르기 기록 · 메시지 탭 규칙.
//
//   · messages/poke-display-sort  콕 목록 네 무리 정렬(안 읽음 → 근무 중(workKnown 일 때만) → 이름 localizedStandardCompare → userID) +
//                                  사람 찾기 검색(대소문자·발음 구별 무시 · 초성)
//   · messages/thread-list        대화 목록 줄(찌르기 낀 재료 · 미리보기 · 시각 · 배지 · 4단 정렬 · 보이스오버)
//   · messages/poke-log           찌르기 기록 규칙(순서표 · 안 본 상대 · 경계 · 표시 순서) · 대화 줄 끼워 넣기 · 찌르기 문구 · 대화 화면 줄
//   · messages/store-rules        탭 배지 · 자리 말풍선 정산 · 입력 카운터 · 미리보기 · 목록 시각 · 근무 판 · 머리 · 빈 자리 · 보내기 문구
//
// 이름 비교는 `localizedStandardCompare`(= 기기 로캘)다. 골든은 **ko 로캘**의 답이다(Android·Windows 는 W1-c NaturalKoCollation 으로 ko 를
// 흉내 낸다 — 골든 sort/natural-ko). 그래서 이 생성기는 로캘이 ko 가 아닌 기계에서는 빨갛다(값을 다른 로캘로 쓰지 않는다).
// 달력은 언제나 KST(`MobileRelativeTime.kst`). 집합·사전은 정렬해 싣는다(Swift 의 해시 순서는 프로세스마다 다르다).

@MainActor
@Suite("GoldenExport messages W2-b — 네 무리 정렬 · 찌르기 기록 · 메시지 탭 규칙")
struct GoldenExportMessages {
    static let base = 1_792_998_000.0   // 2026-10-26 16:00 KST
    static let kst = MobileRelativeTime.kst
    static let peers = [
        "00000000-0000-4000-8000-00000000000a", "00000000-0000-4000-8000-00000000000b", "00000000-0000-4000-8000-00000000000c",
        "00000000-0000-4000-8000-00000000000d", "00000000-0000-4000-8000-00000000000e",
    ]
    static let names = ["한결", "민트", "Ann", "ann", "bob", "Émile", "이름2", "이름10", "가나", "고양", "ＡＢＣ", "zed", "아잉 데모", "두리"]
    static let bodies = [
        "안녕", "안녕\n  하세요", " 공백  여러  칸 ", "[아잉:기쁨]", "[아잉:하트]", "탭\t글자", "\u{3000}전각\u{3000}공백", "e\u{0301}스페", "👍🏽 좋아",
        "줄1\r\n줄2", "끝 공백  ", "ㅋㅋㅋ",
    ]

    struct Gen {
        var rng: MiniGameRandom
        mutating func r(_ n: Int) -> Int { Int(rng.next() % UInt64(n)) }
        mutating func chance(_ k: Int) -> Bool { r(k) == 0 }
        mutating func pick<T>(_ list: [T]) -> T { list[r(list.count)] }
        mutating func subset(_ list: [String]) -> Set<String> { Set(list.filter { _ in r(2) == 0 }) }
        mutating func shuffled<T>(_ list: [T]) -> [T] {
            var out = list
            if out.count > 1 { for j in stride(from: out.count - 1, to: 0, by: -1) { out.swapAt(j, r(j + 1)) } }
            return out
        }
    }

    // MARK: - 싣기 도우미

    static func s(_ value: String?) -> GoldenJSON { value.map(GoldenJSON.string) ?? .null }
    static func i(_ value: Int?) -> GoldenJSON { value.map(GoldenJSON.int) ?? .null }
    static func b(_ value: Bool?) -> GoldenJSON { value.map(GoldenJSON.bool) ?? .null }
    static func strings(_ list: [String]) -> GoldenJSON { .array(list.map(GoldenJSON.string)) }
    static func sortedScalars(_ list: some Sequence<String>) -> [String] { list.sorted { $0.unicodeScalars.lexicographicallyPrecedes($1.unicodeScalars) } }
    static func set(_ value: Set<String>) -> GoldenJSON { strings(sortedScalars(value)) }
    static func map(_ value: [String: Int]) -> GoldenJSON {
        .array(sortedScalars(value.keys).map { [.string($0), .int(value[$0]!)] })
    }
    static func dateBits(_ date: Date) -> GoldenJSON { .bits(date.timeIntervalSince1970) }

    static func entryJSON(_ e: MessageHistoryEntry) -> GoldenJSON {
        ["id": .string(e.id), "peer": .string(e.peerUserID), "name": .string(e.peerName), "avatar": s(e.peerAvatarURL?.absoluteString),
         "body": .string(e.body), "createdAtBits": dateBits(e.createdAt), "mine": .bool(e.isMine), "readByPeer": b(e.readByPeer),
         "unread": b(e.isUnread)]
    }

    static func pokeJSON(_ p: MessagePokeLogEntry) -> GoldenJSON {
        ["id": .string(p.id), "peer": .string(p.peerUserID), "name": .string(p.peerName), "avatar": s(p.peerAvatarURL?.absoluteString),
         "createdAtBits": dateBits(p.createdAt), "mine": .bool(p.isMine), "kind": .string(p.kind.rawValue), "unread": b(p.isUnread)]
    }

    static func optimisticJSON(_ value: [String: MessageOptimisticRead]) -> GoldenJSON {
        .array(sortedScalars(value.keys).map { key in
            let o = value[key]!
            return ["peer": .string(key), "throughID": .string(o.throughID), "recordedSerial": .int(o.recordedSerial),
                    "settledSerial": i(o.settledSerial), "failed": .bool(o.failed)]
        })
    }

    static func entryDate(_ g: inout Gen) -> Date {
        let offsets: [Double] = [0, 0, 1, 2, -60, -3_600, -7_200, -57_600, -86_400, -90_000, 28_800]
        return Date(timeIntervalSince1970: base + g.pick(offsets) + (g.chance(5) ? 0.5 : 0))
    }

    static func makeEntries(_ g: inout Gen, count: Int, peers: [String]) -> [MessageHistoryEntry] {
        var out: [MessageHistoryEntry] = []
        for k in 0..<count {
            let peer = g.pick(peers)
            let mine = g.chance(3)
            out.append(MessageHistoryEntry(
                id: String(format: "m-%02d", k), peerUserID: peer, peerName: g.pick(names),
                peerAvatarURL: g.chance(3) ? nil : URL(string: "https://example.invalid/a/\(peer.suffix(1))\(k).png"),
                body: g.pick(bodies), createdAt: entryDate(&g), isMine: mine,
                readByPeer: mine ? [nil, true, false][g.r(3)] : nil,
                isUnread: mine ? nil : [nil, true, false][g.r(3)]
            ))
        }
        return g.shuffled(out)
    }

    static func makePokes(_ g: inout Gen, count: Int, peers: [String]) -> [MessagePokeLogEntry] {
        var out: [MessagePokeLogEntry] = []
        for k in 0..<count {
            let peer = g.pick(peers)
            let mine = g.chance(3)
            out.append(MessagePokeLogEntry(
                id: String(format: "p-%02d", k), peerUserID: peer, peerName: g.pick(names),
                peerAvatarURL: g.chance(2) ? nil : URL(string: "https://example.invalid/p/\(peer.suffix(1))\(k).png"),
                createdAt: entryDate(&g), isMine: mine, kind: g.chance(3) ? .ultra : .poke,
                isUnread: mine ? nil : [nil, true, false][g.r(3)]
            ))
        }
        return g.shuffled(out)
    }

    /// 서버 시각 순위표(0부터 · 겹치지 않음). 일부 id 는 빠진다(서버가 모르는 즉시 삽입분).
    static func makeChronology(_ g: inout Gen, ids: [String]) -> [String: Int] {
        var order: [String: Int] = [:]
        var rank = 0
        for id in g.shuffled(ids) where !g.chance(5) {
            order[id] = rank
            rank += 1 + (g.chance(4) ? 1 : 0)
        }
        return order
    }

    static func makeOptimistic(_ g: inout Gen, peers: [String], ids: [String]) -> [String: MessageOptimisticRead] {
        var out: [String: MessageOptimisticRead] = [:]
        for peer in peers where g.chance(2) {
            out[peer] = MessageOptimisticRead(throughID: ids.isEmpty || g.chance(5) ? "gone" : g.pick(ids), recordedSerial: g.r(6),
                                              settledSerial: g.chance(3) ? nil : g.r(6), failed: g.chance(4))
        }
        return out
    }

    static func nowChoice(_ g: inout Gen) -> Date {
        let offsets: [Double] = [0, 30, 3_600, 18_000, 28_800, 86_400, -3_600]
        return Date(timeIntervalSince1970: base + g.pick(offsets))
    }

    // MARK: - messages/poke-display-sort

    @Test("messages/poke-display-sort — 네 무리 정렬(sortedForPokeDisplay) · 사람 찾기 검색(MessagesDirectoryRules)")
    func pokeDisplaySort() {
        #expect(Locale.current.identifier.hasPrefix("ko"), "이 골든은 ko 로캘의 localizedStandardCompare 답이다 — 로캘이 \(Locale.current.identifier)")
        var g = Gen(rng: MiniGameRandom(seed: 0x4D53_4732_0001))
        var cases: [GoldenJSON] = []
        let ids = (0..<12).map { String(format: "00000000-0000-4000-8000-0000000000%02x", $0 + 0xa0) }
        for index in 0..<50 {
            let count = 1 + g.r(7)
            let chosen = Array(g.shuffled(ids).prefix(count))
            var entries: [PokeDirectoryEntry] = []
            for id in chosen {
                entries.append(PokeDirectoryEntry(userID: id, name: g.pick(Self.names), avatarURL: nil, isWorking: g.chance(2)))
            }
            let unread = g.subset(chosen)
            let workKnown = !g.chance(4)
            let sorted = entries.sortedForPokeDisplay(unreadPeerIDs: unread, workKnown: workKnown)
            cases.append([
                "id": .string(String(format: "sort-%03d", index)),
                "entries": .array(entries.map { ["id": .string($0.userID), "name": .string($0.name), "working": .bool($0.isWorking)] }),
                "unread": Self.set(unread),
                "workKnown": .bool(workKnown),
                "sorted": Self.strings(sorted.map(\.userID)),
            ])
        }
        // 사람 찾기: 같은 명부에 검색어 여럿(보통 검색 · 초성 · 공백 · 대소문자 · 발음 구별).
        let directoryNames = ["한결", "한가람", "민트", "Ann Lee", "anna", "Émile", "emile", "José", "ÅSA", "이름2", "이름10", "푸른 바다", "씨앗", "Øyvind"]
        let queries = ["", "  ", "한", "ㅎㄱ", "ㅎ ㄱ", "ㅎㄱ씨", "ann", "ANN", "emile", "EMILE", "jose", "asa", "abc", "ＡＢＣ", "이름1", "른 바", "ㅁㅌ",
                       "e\u{0301}mile", "oyvind", "가", "ㄱ", "lee", " 민트 "]
        for index in 0..<2 {
            var entries: [PokeDirectoryEntry] = []
            for (k, name) in directoryNames.enumerated() {
                entries.append(PokeDirectoryEntry(userID: String(format: "00000000-0000-4000-8000-0000000001%02x", k), name: name,
                                                  avatarURL: nil, isWorking: g.chance(2)))
            }
            let unread = g.subset(entries.map(\.userID))
            var results: [GoldenJSON] = []
            for query in queries {
                let filtered = MessagesDirectoryRules.filter(entries, query: query, unreadPeerIDs: unread)
                results.append(["query": .string(query), "ids": Self.strings(filtered.map(\.userID))])
            }
            cases.append([
                "id": .string("directory-\(index)"),
                "entries": .array(entries.map { ["id": .string($0.userID), "name": .string($0.name), "working": .bool($0.isWorking)] }),
                "unread": Self.set(unread),
                "results": .array(results),
                "initials": .array(directoryNames.map { ["name": .string($0), "initials": .string(MessagesDirectoryRules.initials(of: $0))] }),
            ])
        }
        goldenEmit(GoldenFile(
            golden: "messages/poke-display-sort",
            equivalence: .bit,
            swiftSources: ["Sources/CheckCore/SupabaseWorkModels.swift", "Sources/CheckMobileKit/Messages/MessagesRules.swift"],
            spec: [
                "sort": "PokeDirectoryEntry.sortedForPokeDisplay(unreadPeerIDs:workKnown:): 안 읽음 → 근무 중(workKnown 일 때만) → 이름 localizedStandardCompare → userID(<). Kotlin 은 Collation = NaturalKoCollation(W1-c sort/natural-ko)",
                "locale": "ko — 생성기는 Locale.current 가 ko 가 아니면 빨갛다(사용자 기기 로캘 = ko_KR)",
                "names": "Foundation 비교가 전순서가 아닌 쌍은 이름 표에 넣지 않는다(실측: 전각 'ＡＢＣ' ↔ 'ÅSA' 는 양쪽으로 1 · 종성 음절 ↔ 같은 초·중성 + 음절 — W1-c sort/natural-ko inconsistent). 그런 쌍은 Swift 정렬 결과가 알고리즘에 달려 대조할 수 없다",
                "directory": "MessagesDirectoryRules.filter(_:query:unreadPeerIDs:): 앞뒤 공백 걷기 → 정렬(workKnown true) → 빈 검색어면 전부 · 한글 자음만이면 초성열 포함 · 아니면 range(of:options:[.caseInsensitive, .diacriticInsensitive])",
                "platformSensitive": "false — 이름 비교는 번들 순위표(NaturalKoCollation), 발음 구별 접기는 NFD(java.text.Normalizer) + 번들 범주표(Mn)",
            ],
            cases: cases
        ))
    }

    // MARK: - messages/thread-list

    @Test("messages/thread-list — 대화 목록 줄(찌르기 낀 재료 · 미리보기 · 시각 · 배지 · 4단 정렬 · 보이스오버)")
    func threadList() {
        var g = Gen(rng: MiniGameRandom(seed: 0x4D53_4732_0002))
        var cases: [GoldenJSON] = []
        let pokePeers = Self.peers + ["00000000-0000-4000-8000-0000000000ff"]
        for index in 0..<20 {
            let entries = Self.makeEntries(&g, count: g.r(7), peers: Self.peers)
            let pokes = Self.makePokes(&g, count: g.chance(4) ? 0 : g.r(6), peers: pokePeers)
            let chronology = Self.makeChronology(&g, ids: entries.map(\.id) + pokes.map(\.id))
            var serverOrder: [String: Int]? = nil
            if !g.chance(3) {
                var order: [String: Int] = [:]
                for (k, id) in g.shuffled(entries.map(\.id)).enumerated() where !g.chance(5) { order[id] = k }
                serverOrder = order
            }
            let threads = MessageThreadBuilder.threads(from: entries, serverOrder: serverOrder)
            let messageUnread = g.subset(Self.peers)
            let pokeUnread = g.subset(pokePeers)
            var counts: [String: Int] = [:]
            for peer in Self.sortedScalars(messageUnread) where !g.chance(4) { counts[peer] = [0, 1, 2, 7, 99, 100, 150][g.r(7)] }
            let working = g.subset(pokePeers)
            let workKnown = !g.chance(3)
            let now = Self.nowChoice(&g)
            let rows = MessagesThreadListRules.rows(
                threads: threads, pokes: pokes, chronology: chronology, messageUnreadPeerIDs: messageUnread,
                pokeUnreadPeerIDs: pokeUnread, unreadCounts: counts, workingPeerIDs: working, workKnown: workKnown, now: now
            )
            cases.append([
                "id": .string(String(format: "rows-%03d", index)),
                "entries": .array(entries.map(Self.entryJSON)),
                "pokes": .array(pokes.map(Self.pokeJSON)),
                "chronology": Self.map(chronology),
                "serverOrder": serverOrder.map(Self.map) ?? .null,
                "messageUnread": Self.set(messageUnread),
                "pokeUnread": Self.set(pokeUnread),
                "counts": Self.map(counts),
                "working": Self.set(working),
                "workKnown": .bool(workKnown),
                "nowBits": Self.dateBits(now),
                "rows": .array(rows.map { row in
                    ["peer": .string(row.peerUserID), "name": .string(row.peerName), "avatar": Self.s(row.peerAvatarURL?.absoluteString),
                     "messageIDs": Self.strings(row.thread.messages.map(\.id)), "pokeIDs": Self.strings(row.pokes.map(\.id)),
                     "lastActivityBits": Self.dateBits(row.lastActivityAt), "preview": .string(row.previewText),
                     "lastIsMine": .bool(row.lastIsMine), "previewIsPoke": .bool(row.previewIsPoke), "timeText": .string(row.timeText),
                     "isUnread": .bool(row.isUnread), "countBadge": Self.s(row.countBadge), "group": .int(row.group),
                     "a11y": .string(MessagesThreadListRules.accessibilityText(row: row, presenceLine: nil)),
                     "a11yPresence": .string(MessagesThreadListRules.accessibilityText(row: row, presenceLine: "근무 중"))]
                }),
            ])
        }
        // 무리 번호 표(안 읽음 × 근무 × 근무를 아는가).
        var ranks: [GoldenJSON] = []
        for unread in [false, true] {
            for working in [false, true] {
                for known in [false, true] {
                    ranks.append(["unread": .bool(unread), "working": .bool(working), "known": .bool(known),
                                  "rank": .int(MessagesSortRules.rank(isUnread: unread, isWorking: working, workKnown: known))])
                }
            }
        }
        cases.append(["id": "rank-table", "ranks": .array(ranks)])
        goldenEmit(GoldenFile(
            golden: "messages/thread-list",
            equivalence: .bit,
            swiftSources: ["Sources/CheckMobileKit/Messages/MessagesRules.swift", "Sources/CheckCore/MessagePokeLog.swift", "Sources/CheckCore/MessageRules.swift"],
            spec: [
                "rows": "MessagesThreadListRules.rows(threads: MessageThreadBuilder.threads(from: entries, serverOrder:), pokes:, chronology:, messageUnreadPeerIDs:, pokeUnreadPeerIDs:, unreadCounts:, workingPeerIDs:, workKnown:, now:, calendar: KST)",
                "a11y": "MessagesThreadListRules.accessibilityText(row:presenceLine:) — presenceLine nil / \"근무 중\"",
                "calendar": "MobileRelativeTime.kst(그레고리력 · Asia/Seoul)",
                "platformSensitive": "false — 시각은 kotlinx-datetime 의 Asia/Seoul(고정 +9), 글자 접기는 번들 표",
            ],
            cases: cases
        ))
    }

    // MARK: - messages/poke-log

    @Test("messages/poke-log — 찌르기 규칙 · 대화 줄 끼워 넣기 · 문구 · 대화 화면 줄")
    func pokeLog() {
        var g = Gen(rng: MiniGameRandom(seed: 0x4D53_4732_0003))
        var cases: [GoldenJSON] = []
        for index in 0..<16 {
            let pokes = Self.makePokes(&g, count: 1 + g.r(6), peers: Self.peers)
            let entries = Self.makeEntries(&g, count: g.r(6), peers: Self.peers)
            let chronology = Self.makeChronology(&g, ids: entries.map(\.id) + pokes.map(\.id))
            let snapshot = MessageHistoryReadSnapshot(serial: g.r(6), serverOrder: chronology)
            let optimistic = Self.makeOptimistic(&g, peers: Self.peers, ids: pokes.map(\.id))
            var arrival: [String: Int] = [:]
            if g.chance(2) { for p in pokes where g.chance(2) { arrival[p.id] = g.r(5) } }
            let now = Self.nowChoice(&g)
            var marks: [GoldenJSON] = []
            for peer in Self.peers {
                marks.append(["peer": .string(peer),
                              "withRecord": Self.s(MessagePokeLogRules.markTarget(peer: peer, log: pokes, snapshot: snapshot, optimistic: optimistic[peer])),
                              "withoutRecord": Self.s(MessagePokeLogRules.markTarget(peer: peer, log: pokes, snapshot: snapshot, optimistic: nil))])
            }
            let sortedPokes = MessagePokeLogRules.sorted(pokes, chronology: chronology)
            let sortedMessages = entries.sortedForMessageHistory(serverOrder: chronology)
            let lines = MessageConversationTimeline.lines(messages: sortedMessages, pokes: sortedPokes, chronology: chronology, now: now, calendar: Self.kst)
            // 대화 화면 줄: 한 사람(첫 찌르기의 상대)의 메시지 · 찌르기 · 자리 말풍선.
            let peer = pokes[0].peerUserID
            let thread = MessageThreadBuilder.threads(from: entries, serverOrder: chronology).first { $0.peerUserID == peer }
            var pending: [MessagesPendingOutgoing] = []
            for k in 0..<g.r(3) {
                pending.append(MessagesPendingOutgoing(id: "local-\(k)", peerUserID: peer, body: g.pick(Self.bodies),
                                                       createdAt: now, state: g.chance(2) ? .sending : .sent(settledSerial: g.r(5))))
            }
            let receipts = g.chance(2)
            let items = MessagesConversationRules.items(
                messages: thread?.messages ?? [], pokes: pokes.filter { $0.peerUserID == peer }, chronology: chronology,
                pending: pending, receiptsAvailable: receipts, now: now
            )
            cases.append([
                "id": .string(String(format: "log-%03d", index)),
                "pokes": .array(pokes.map(Self.pokeJSON)),
                "entries": .array(entries.map(Self.entryJSON)),
                "chronology": Self.map(chronology),
                "snapshotSerial": .int(snapshot.serial),
                "optimistic": Self.optimisticJSON(optimistic),
                "arrival": Self.map(arrival),
                "nowBits": Self.dateBits(now),
                "effectiveOrder": Self.map(MessagePokeLogRules.effectiveOrder(log: pokes, serverOrder: chronology)),
                "unreadPeerIDs": Self.set(MessagePokeLogRules.unreadPeerIDs(log: pokes, snapshot: snapshot, optimistic: optimistic)),
                "markTargets": .array(marks),
                "sorted": Self.strings(MessagePokeLogRules.sorted(pokes, chronology: chronology, arrivalOrder: arrival).map(\.id)),
                "sortedMessages": Self.strings(sortedMessages.map(\.id)),
                "lines": .array(lines.map { line in
                    switch line {
                    case .day(let key, let label): return ["kind": "day", "key": .string(key), "label": .string(label)]
                    case .bubble(let entry): return ["kind": "bubble", "id": .string(entry.id)]
                    case .poke(let entry): return ["kind": "poke", "id": .string(entry.id), "lineID": .string(line.id)]
                    }
                }),
                "texts": .array(pokes.map { p in
                    ["id": .string(p.id), "line": .string(MessagePokeLogText.line(for: p, calendar: Self.kst)),
                     "symbol": .string(MessagePokeLogText.symbol(p.kind)), "preview": .string(MessagesSortRules.pokePreview(p))]
                }),
                "conversationPeer": .string(peer),
                "pending": .array(pending.map { item in
                    var state: GoldenJSON = "sending"
                    if case .sent(let settled) = item.state { state = .int(settled) }
                    return ["id": .string(item.id), "body": .string(item.body), "state": state]
                }),
                "receipts": .bool(receipts),
                "items": .array(items.map { item in
                    switch item {
                    case .day(let key, let label): return ["kind": "day", "id": .string(item.id), "key": .string(key), "label": .string(label)]
                    case .bubble(let line):
                        return ["kind": "bubble", "id": .string(item.id), "clock": .string(line.clockText), "showsTime": .bool(line.showsTime),
                                "startsGroup": .bool(line.startsGroup), "unreadOne": .bool(line.showsUnreadOne), "mine": .bool(item.isMine)]
                    case .poke(let line):
                        return ["kind": "poke", "id": .string(item.id), "text": .string(line.text), "symbol": .string(line.symbol), "mine": .bool(item.isMine)]
                    case .pending: return ["kind": "pending", "id": .string(item.id)]
                    }
                }),
            ])
        }
        goldenEmit(GoldenFile(
            golden: "messages/poke-log",
            equivalence: .bit,
            swiftSources: ["Sources/CheckCore/MessagePokeLog.swift", "Sources/CheckMobileKit/Messages/MessagesRules.swift", "Sources/CheckCore/MessageRules.swift"],
            spec: [
                "rules": "MessagePokeLogRules.effectiveOrder · unreadPeerIDs(snapshot = (serial, chronology)) · markTarget(record 있음/없음) · sorted(chronology, arrivalOrder)",
                "lines": "MessageConversationTimeline.lines(messages: entries.sortedForMessageHistory(serverOrder: chronology), pokes: sorted, chronology, now, calendar: KST)",
                "items": "MessagesConversationRules.items(messages: 그 사람 대화(threads(from:serverOrder: chronology)), pokes: 그 사람 찌르기, chronology, pending, receiptsAvailable, now) — pending createdAt = now",
                "texts": "MessagePokeLogText.line(for:calendar: KST) · symbol · MessagesSortRules.pokePreview",
                "platformSensitive": "false",
            ],
            cases: cases
        ))
    }

    // MARK: - messages/store-rules

    @Test("messages/store-rules — 배지 · 자리 말풍선 · 카운터 · 미리보기 · 시각 · 근무 판 · 머리 · 빈 자리 · 보내기 문구")
    func storeRules() {
        var g = Gen(rng: MiniGameRandom(seed: 0x4D53_4732_0004))
        var cases: [GoldenJSON] = []
        // 배지(이력 · 요약 · 낙관 읽음 · 옛 도장).
        for index in 0..<16 {
            let entries = Self.makeEntries(&g, count: g.r(7), peers: Self.peers)
            let ids = entries.map(\.id)
            let serverOrder = Dictionary(uniqueKeysWithValues: g.shuffled(ids).enumerated().map { ($0.element, $0.offset) })
            let historySnapshot: MessageHistoryReadSnapshot? = g.chance(4) ? nil : MessageHistoryReadSnapshot(serial: g.r(6), serverOrder: serverOrder)
            let summary: MessageUnreadSummarySnapshot? = g.chance(3) ? nil : MessageUnreadSummarySnapshot(
                serial: g.r(6),
                summary: MessageUnreadSummary(total: 0, peers: Self.peers.filter { _ in g.chance(2) }.map {
                    MessageUnreadPeer(peerUserID: $0, count: 1 + g.r(4), lastMessageAt: nil)
                })
            )
            let optimistic = Self.makeOptimistic(&g, peers: Self.peers, ids: ids)
            var stamps: [String: Date] = [:]
            for peer in Self.peers where g.chance(2) { stamps[peer] = Date(timeIntervalSince1970: Self.base + Double(g.r(6)) - 0.5 - Double(g.r(2)) * 3_600) }
            let total = MessagesBadgeRules.unreadCount(history: entries, historySnapshot: historySnapshot, summary: summary,
                                                       optimistic: optimistic, legacyStamps: stamps)
            let byPeer = MessagesBadgeRules.unreadCountsByPeer(history: entries, historySnapshot: historySnapshot, summary: summary,
                                                               optimistic: optimistic, legacyStamps: stamps)
            cases.append([
                "id": .string(String(format: "badge-%03d", index)),
                "entries": .array(entries.map(Self.entryJSON)),
                "serverOrder": Self.map(serverOrder),
                "historySerial": Self.i(historySnapshot?.serial),
                "summary": summary.map { s in
                    ["serial": .int(s.serial), "peers": .array(s.summary.peers.map { ["peer": .string($0.peerUserID), "count": .int($0.count)] })]
                } ?? .null,
                "optimistic": Self.optimisticJSON(optimistic),
                "legacyStamps": .array(Self.sortedScalars(stamps.keys).map { ["peer": .string($0), "atBits": Self.dateBits(stamps[$0]!)] }),
                "unreadCount": .int(total),
                "countsByPeer": Self.map(byPeer),
            ])
        }
        // 자리 말풍선 정산.
        for index in 0..<12 {
            let applied = Self.makeEntries(&g, count: g.r(6), peers: Self.peers)
            let previous = Set(applied.map(\.id).filter { _ in g.chance(3) })
            var pending: [MessagesPendingOutgoing] = []
            for k in 0..<(1 + g.r(4)) {
                let template = applied.isEmpty || g.chance(3) ? nil : g.pick(applied)
                let created = Date(timeIntervalSince1970: Self.base + [0, 300, 599, 601, -600, -700][g.r(6)])
                pending.append(MessagesPendingOutgoing(
                    id: "local-\(k)", peerUserID: template?.peerUserID ?? g.pick(Self.peers), body: template?.body ?? g.pick(Self.bodies),
                    createdAt: created, state: g.chance(2) ? .sending : .sent(settledSerial: g.r(6))
                ))
            }
            let serial = g.r(6)
            let kept = MessagesPendingRules.reconcile(pending: pending, previousHistoryIDs: previous, applied: applied, appliedSerial: serial)
            cases.append([
                "id": .string(String(format: "pending-%03d", index)),
                "applied": .array(applied.map(Self.entryJSON)),
                "previous": Self.set(previous),
                "pending": .array(pending.map { item in
                    var state: GoldenJSON = "sending"
                    if case .sent(let settled) = item.state { state = .int(settled) }
                    return ["id": .string(item.id), "peer": .string(item.peerUserID), "body": .string(item.body),
                            "createdAtBits": Self.dateBits(item.createdAt), "state": state]
                }),
                "appliedSerial": .int(serial),
                "kept": Self.strings(kept.map(\.id)),
            ])
        }
        // 미리보기 · 카운터 · 목록 시각 · 개수 배지 · 부제 · 보내기 문구 · 머리 · 빈 자리.
        let drafts = ["", "가", String(repeating: "가", count: 179), String(repeating: "가", count: 180), String(repeating: "a", count: 200),
                      String(repeating: "👍🏽", count: 95), String(repeating: "나", count: 201), "  " + String(repeating: "x", count: 185) + "\n",
                      "e\u{0301}" + String(repeating: "e", count: 180)]
        cases.append([
            "id": "text",
            "previews": .array((Self.bodies + ["", "   ", "\n\n", "a\u{2028}b", "a\u{00A0}b", "[아잉:놀람] ", " [아잉:졸림]", "[아잉:없음]"]).map {
                ["body": .string($0), "preview": .string(MessagesListRules.preview($0))]
            }),
            "counters": .array(drafts.map {
                ["draft": .string($0), "counter": Self.s(MessagesComposerRules.counterText(for: $0)),
                 "overflow": .bool(MessagesComposerRules.isOverflowing($0))]
            }),
            "countBadges": .array([nil, 0, 1, 5, 99, 100, 250].flatMap { count in
                [false, true].map { unread in
                    ["count": Self.i(count), "unread": .bool(unread), "badge": Self.s(MessagesListRules.countBadge(isUnread: unread, count: count))]
                }
            }),
            "subtitles": .array([0, 1, 3, 120].map { ["count": .int($0), "subtitle": Self.s(MessagesListRules.subtitle(unreadCount: $0))] }),
            "notices": .array(([MessageSendOutcome.ok, .notWorking, .targetNotWorking, .targetFocused, .tooLong, .notText, .blackout, .flood, .invalid]
                as [MessageSendOutcome]).flatMap { outcome in
                    [nil, 40].map { max in
                        ["outcome": .string(String(describing: outcome)), "max": Self.i(max),
                         "notice": Self.s(MessagesSendRules.notice(for: outcome, maxLength: max))]
                    }
                }),
            "connectionNotice": .string(MessagesSendRules.connectionNotice),
            "headers": .array(([nil, "", "  ", "한결", " 민트 ", "\n"] as [String?]).flatMap { name in
                [false, true].map { resolving in
                    let h = MessagesConversationRules.header(peerName: name, isResolving: resolving)
                    return ["name": Self.s(name), "resolving": .bool(resolving), "title": .string(h.title),
                            "avatarName": Self.s(h.avatarName), "a11y": .string(h.accessibilityLabel)]
                }
            }),
            "empty": .array([(false, false), (false, true), (true, false), (true, true)].map { loaded, failed in
                let e = MessagesConversationRules.emptyState(loaded: loaded, failed: failed)
                return ["loaded": .bool(loaded), "failed": .bool(failed), "symbol": .string(e.symbol), "title": .string(e.title),
                        "hint": Self.s(e.hint), "retry": .bool(e.showsRetry)]
            }),
        ])
        var times: [GoldenJSON] = []
        for _ in 0..<16 {
            let date = Date(timeIntervalSince1970: Self.base + Double(g.r(200_000)) - 150_000 + (g.chance(4) ? 0.25 : 0))
            let now = Date(timeIntervalSince1970: Self.base + Double(g.r(40_000)))
            times.append(["dateBits": Self.dateBits(date), "nowBits": Self.dateBits(now),
                          "text": .string(MessagesListRules.timeText(date, now: now)),
                          "relative": .string(MobileRelativeTime.text(for: date, now: now)),
                          "blockedAt": .string(BlockReportText.blockedAtLine(date, now: now))])
        }
        cases.append(["id": "times", "times": .array(times)])
        // 근무 판(MessagesPresenceRules.board · headerLine · statuses).
        let centers: [String?] = [nil, "seoul", "busan", "nowhere"]
        let displayCenters: [String?] = [nil, "서울", "부산", "제주"]
        let statusPool: [String?] = [nil, "집중 중", "  ", "회의\n중", "🍀"]
        for index in 0..<12 {
            let me: String? = g.chance(3) ? nil : g.pick(Self.peers)
            let messagesDirectory: [PokeDirectoryEntry]? = g.chance(3) ? nil : Self.peers.filter { _ in g.chance(2) }.map {
                PokeDirectoryEntry(userID: $0, name: g.pick(Self.names), avatarURL: g.chance(2) ? nil : URL(string: "https://example.invalid/d/\($0.suffix(1)).png"),
                                   isWorking: g.chance(2), center: g.pick(displayCenters), statusMessage: g.pick(statusPool))
            }
            let nowDirectory: [PokeDirectoryRow]? = g.chance(3) ? nil : Self.peers.filter { _ in g.chance(2) }.map {
                PokeDirectoryRow(userId: $0, displayName: g.pick(Self.names), avatarUrl: g.chance(2) ? nil : "https://example.invalid/n/\($0.suffix(1)).png",
                                 isWorking: g.chance(2), center: g.pick(centers), statusMessage: g.pick(statusPool))
            }
            let teamIDs: Set<String> = g.chance(2) ? [] : g.subset(Self.peers)
            var working: [MessagesPresenceRules.Working] = []
            for peer in Self.peers where g.chance(3) {
                working.append(MessagesPresenceRules.Working(id: peer, name: g.pick(Self.names), avatarURL: g.chance(2) ? nil : URL(string: "https://example.invalid/w/\(peer.suffix(1)).png"),
                                                             center: g.pick(centers), isStale: g.chance(3)))
            }
            if !working.isEmpty, g.chance(4) { working.append(working[0]) }
            let board = MessagesPresenceRules.board(nowWorking: working, teamMemberIDs: teamIDs, nowDirectory: nowDirectory,
                                                    messagesDirectory: messagesDirectory, me: me)
            cases.append([
                "id": .string(String(format: "presence-%03d", index)),
                "me": Self.s(me),
                "messagesDirectory": messagesDirectory.map { list in
                    .array(list.map { ["id": .string($0.userID), "name": .string($0.name), "avatar": Self.s($0.avatarURL?.absoluteString),
                                       "working": .bool($0.isWorking), "center": Self.s($0.center), "status": Self.s($0.statusMessage)] })
                } ?? .null,
                "nowDirectory": nowDirectory.map { list in
                    .array(list.map { ["id": .string($0.userId), "name": .string($0.displayName), "avatar": Self.s($0.avatarUrl),
                                       "working": .bool($0.isWorking), "center": Self.s($0.center), "status": Self.s($0.statusMessage)] })
                } ?? .null,
                "teamIDs": Self.set(teamIDs),
                "nowWorking": .array(working.map { ["id": .string($0.id), "name": .string($0.name), "avatar": Self.s($0.avatarURL?.absoluteString),
                                                    "center": Self.s($0.center), "stale": .bool($0.isStale)] }),
                "isKnown": .bool(board.isKnown),
                "peers": .array(Self.sortedScalars(board.peers.keys).map { id in
                    let p = board.peers[id]!
                    return ["id": .string(id), "status": .string(p.status.rawValue), "center": Self.s(p.center),
                            "headerLine": Self.s(MessagesPresenceRules.headerLine(p))]
                }),
                "boardWorking": .array(board.working.map { ["id": .string($0.id), "name": .string($0.name), "avatar": Self.s($0.avatarURL?.absoluteString),
                                                            "status": .string($0.status.rawValue), "center": Self.s($0.center)] }),
                "statuses": .array(Self.sortedScalars(board.statuses.keys).map { ["id": .string($0), "text": .string(board.statuses[$0]!)] }),
                "workingPeerIDs": Self.set(MessagesSortRules.workingPeerIDs(board)),
            ])
        }
        goldenEmit(GoldenFile(
            golden: "messages/store-rules",
            equivalence: .bit,
            swiftSources: ["Sources/CheckMobileKit/Messages/MessagesRules.swift", "Sources/CheckMobileKit/Messages/MessagesBlockRules.swift",
                           "Sources/CheckMobileKit/Components/MobileRelativeTime.swift"],
            spec: [
                "badge": "MessagesBadgeRules.unreadCount · unreadCountsByPeer(history, historySnapshot(serial, serverOrder), summary(serial, peers), optimistic, legacyStamps)",
                "pending": "MessagesPendingRules.reconcile(pending:previousHistoryIDs:applied:appliedSerial:)",
                "text": "MessagesListRules.preview · MessagesComposerRules.counterText/isOverflowing · countBadge · subtitle · MessagesSendRules.notice · header · emptyState",
                "times": "MessagesListRules.timeText(_:now:) · MobileRelativeTime.text(for:now:) · BlockReportText.blockedAtLine(_:now:) — KST",
                "presence": "MessagesPresenceRules.board(nowWorking:teamMemberIDs:nowDirectory:messagesDirectory:me:) · headerLine · MessagesSortRules.workingPeerIDs",
                "platformSensitive": "false",
            ],
            cases: cases
        ))
    }
}
