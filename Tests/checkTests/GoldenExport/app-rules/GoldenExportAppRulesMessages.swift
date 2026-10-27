// 원본: 없음(W1-c 골든 생성기 — Sources/CheckCore/{MessageRules,BlockReportRules,Megaphone}.swift 를 잰다)
import CheckGoldenSupport
import Foundation
import Testing
@testable import CheckCore

// W1-c 앱 규칙 — 메시지 글자 규칙(C§3.2 B-4 · §4 #26). Kotlin 은 core/rules/…/text/{MessageRules,BlockReportRules,Megaphone}.kt.
//
//   · text/message-rules  안내 문구 · 정렬(서버 순서 · 도착 순서) · 대화 묶음 · 읽음 판정 · 날짜 구분선(시간대 다섯)
//   · text/block-report   차단·신고 문구(폰·맥) · 오류 갈래 · 신고 자유 입력 판정
//   · text/megaphone      확성기 요청·응답 · 결과 · 본문 판정 · 정보 · 보내기 전 판정 · request_id 쥐기(실제 MegaphoneStore 를 몰아 잰다)

@Suite("GoldenExport app-rules — 메시지 글자 규칙(MessageRules · BlockReportRules · Megaphone)")
struct GoldenExportAppRulesMessages {
    static func cps(_ text: String) -> String {
        text.unicodeScalars.map { String($0.value, radix: 16) }.map { String(repeating: "0", count: max(0, 4 - $0.count)) + $0 }.joined(separator: " ")
    }
    static func s(_ value: String?) -> GoldenJSON { value.map(GoldenJSON.string) ?? .null }
    static func i(_ value: Int?) -> GoldenJSON { value.map(GoldenJSON.int) ?? .null }
    static func b(_ value: Bool?) -> GoldenJSON { value.map(GoldenJSON.bool) ?? .null }
    static func strings(_ list: [String]) -> GoldenJSON { .array(list.map(GoldenJSON.string)) }
    static func set(_ value: Set<String>) -> GoldenJSON { strings(value.sorted { $0.unicodeScalars.lexicographicallyPrecedes($1.unicodeScalars) }) }
    /// id → 수 표. id 에 ASCII 밖 글자가 있을 수 있어(골든 객체 키는 ASCII 만) [키, 값] 쌍의 배열로 싣는다(키의 스칼라 순).
    static func map(_ value: [String: Int]) -> GoldenJSON {
        .array(value.sorted { $0.key.unicodeScalars.lexicographicallyPrecedes($1.key.unicodeScalars) }.map { [.string($0.key), .int($0.value)] })
    }

    // MARK: - text/message-rules

    static func entryJSON(_ e: MessageHistoryEntry) -> GoldenJSON {
        ["id": .string(e.id), "peer": .string(e.peerUserID), "name": .string(e.peerName), "avatar": s(e.peerAvatarURL?.absoluteString),
         "mine": .bool(e.isMine), "unread": b(e.isUnread), "createdAtBits": .bits(e.createdAt.timeIntervalSince1970)]
    }

    static let messageBase = 1_792_998_000.0   // 2026-10-26 16:00 KST

    static func makeScenario(_ rng: inout MiniGameRandom, index: Int) -> GoldenJSON {
        let peers = ["00000000-0000-4000-8000-00000000000a", "00000000-0000-4000-8000-00000000000b", "00000000-0000-4000-8000-00000000000c",
                     "00000000-0000-4000-8000-00000000000D"]
        let idPool = ["m-01", "m-02", "m-03", "m-04", "m-05", "m-06", "m-07", "m-08", "m-09", "m-10", "M-11", "m-1", "m-가", "m-é", "m-z"]
        func r(_ n: Int) -> Int { Int(rng.next() % UInt64(n)) }
        let count = 1 + r(10)
        var entries: [MessageHistoryEntry] = []
        for k in 0..<count {
            let peer = peers[r(peers.count)]
            let id = index % 7 == 3 && k > 0 && r(4) == 0 ? entries[r(entries.count)].id : idPool[r(idPool.count)]
            let unread: Bool? = [nil, true, false][r(3)]
            let created = messageBase + Double(r(5)) + (r(4) == 0 ? 0.5 : 0) + (r(6) == 0 ? -86_400 * Double(1 + r(2)) : 0)
            entries.append(MessageHistoryEntry(id: id, peerUserID: peer, peerName: "이름\(peer.suffix(1))-v\(k)",
                                               peerAvatarURL: r(3) == 0 ? nil : URL(string: "https://example.invalid/a/\(peer.suffix(1))\(k).png"),
                                               body: "본문 \(k)", createdAt: Date(timeIntervalSince1970: created), isMine: r(3) == 0,
                                               isUnread: unread))
        }
        let ids = entries.map(\.id)
        var serverOrder: [String: Int]? = nil
        if r(3) != 0 {
            var order: [String: Int] = [:]
            var shuffled = ids
            for j in stride(from: shuffled.count - 1, to: 0, by: -1) { shuffled.swapAt(j, r(j + 1)) }
            var position = 0
            for id in shuffled where order[id] == nil && r(5) != 0 {
                order[id] = position
                position += 1 + r(2)
            }
            serverOrder = order
        }
        var arrival: [String: Int] = [:]
        if r(2) == 0 { for id in ids where r(2) == 0 { arrival[id] = r(6) } }
        let sorted = entries.sortedForMessageHistory(serverOrder: serverOrder, arrivalOrder: arrival)
        let threads = MessageThreadBuilder.threads(from: entries, serverOrder: serverOrder, arrivalOrder: arrival)
        // 읽음 규칙.
        let historySnapshot: MessageHistoryReadSnapshot? = r(4) == 0 ? nil : MessageHistoryReadSnapshot(serial: r(6), serverOrder: serverOrder ?? [:])
        let summary: MessageUnreadSummarySnapshot? = r(3) == 0 ? nil : MessageUnreadSummarySnapshot(
            serial: r(6), summary: MessageUnreadSummary(total: 0, peers: peers.filter { _ in r(2) == 0 }.map {
                MessageUnreadPeer(peerUserID: $0, count: 1, lastMessageAt: nil)
            }))
        var optimistic: [String: MessageOptimisticRead] = [:]
        for peer in peers where r(3) == 0 {
            optimistic[peer] = MessageOptimisticRead(throughID: r(5) == 0 ? "gone" : ids[r(ids.count)], recordedSerial: r(6),
                                                     settledSerial: r(3) == 0 ? nil : r(6), failed: r(4) == 0)
        }
        var stamps: [String: Date] = [:]
        for peer in peers where r(2) == 0 { stamps[peer] = Date(timeIntervalSince1970: messageBase + Double(r(6)) - 0.5) }
        let unread = MessageUnreadRules.unreadPeerIDs(history: entries, historySnapshot: historySnapshot, summary: summary,
                                                      optimistic: optimistic, legacyStamps: stamps)
        let markSnapshot = historySnapshot ?? MessageHistoryReadSnapshot(serial: 0, serverOrder: serverOrder ?? [:])
        var marks: [GoldenJSON] = []
        for peer in peers {
            marks.append(["peer": .string(peer), "withRecord": s(MessageUnreadRules.markTarget(peer: peer, history: entries, snapshot: markSnapshot, optimistic: optimistic[peer])),
                          "withoutRecord": s(MessageUnreadRules.markTarget(peer: peer, history: entries, snapshot: markSnapshot, optimistic: nil))])
        }
        var alreadyRead: [GoldenJSON] = []
        for id in Array(Set(ids + ["missing"])).sorted() {
            alreadyRead.append(["id": .string(id),
                                "plain": .bool(MessageUnreadRules.isAlreadyRead(messageID: id, history: entries, snapshot: historySnapshot, optimistic: optimistic)),
                                "withSummary": .bool(MessageUnreadRules.isAlreadyRead(messageID: id, history: entries, snapshot: historySnapshot, optimistic: optimistic, summary: summary))])
        }
        return [
            "id": .string(String(format: "scenario-%03d", index)),
            "entries": .array(entries.map(Self.entryJSON)),
            "serverOrder": serverOrder.map(Self.map) ?? .null,
            "arrivalOrder": Self.map(arrival),
            "sorted": Self.strings(sorted.map(\.id)),
            "threads": .array(threads.map { t in
                ["peer": .string(t.peerUserID), "name": .string(t.peerName), "avatar": Self.s(t.peerAvatarURL?.absoluteString),
                 "ids": Self.strings(t.messages.map(\.id))]
            }),
            "effectiveOrder": Self.map(MessageUnreadRules.effectiveOrder(history: entries, serverOrder: serverOrder ?? [:])),
            "historySnapshot": historySnapshot.map { ["serial": .int($0.serial)] } ?? .null,
            "summary": summary.map { ["serial": .int($0.serial), "unreadPeerIDs": Self.set($0.summary.unreadPeerIDs)] } ?? .null,
            "optimistic": .object(optimistic.mapValues { o in
                ["throughID": .string(o.throughID), "recordedSerial": .int(o.recordedSerial), "settledSerial": Self.i(o.settledSerial), "failed": .bool(o.failed)]
            }),
            "legacyStamps": .object(stamps.mapValues { .bits($0.timeIntervalSince1970) }),
            "unreadPeerIDs": Self.set(unread),
            "markTargets": .array(marks),
            "alreadyRead": .array(alreadyRead),
        ]
    }

    @Test("text/message-rules — 문구 · 정렬 · 묶음 · 읽음 · 날짜 구분선")
    func messageRules() {
        var cases: [GoldenJSON] = []
        cases.append(["id": "notices", "historyHours": .int(MessageNoticeText.historyHours), "historyLimit": .int(MessageNoticeText.historyLimit),
                      "sent": .string(MessageNoticeText.sent), "notWorking": .string(MessageNoticeText.notWorking),
                      "targetNotWorking": .string(MessageNoticeText.targetNotWorking), "targetFocused": .string(MessageNoticeText.targetFocused),
                      "notText": .string(MessageNoticeText.notText), "blackout": .string(MessageNoticeText.blackout),
                      "invalid": .string(MessageNoticeText.invalid), "tooLongDefault": .string(MessageNoticeText.tooLong()),
                      "tooLong40": .string(MessageNoticeText.tooLong(maxLength: 40)), "expiry": .string(MessageNoticeText.expiry)])
        var rng = MiniGameRandom(seed: 0x4D53_0001)
        for index in 0..<100 { cases.append(Self.makeScenario(&rng, index: index)) }
        // 날짜 구분선 · 시각(기기 시간대 — 다섯 곳, DST 경계 포함).
        let zones = ["Asia/Seoul", "America/New_York", "Europe/London", "UTC", "Australia/Lord_Howe"]
        let instants: [Double] = [
            1_792_940_400, 1_792_940_399.5, 1_792_998_000, 1_793_026_799.999, 1_793_026_800,   // KST 10-26 0시 · 직전 · 16시 · 23:59:59.999 · 10-27 0시
            1_772_953_200, 1_772_960_400, 1_772_967_600,   // 2026-03-08 미 동부 DST 시작 앞뒤
            1_793_512_800, 1_793_520_000, 1_793_523_600,   // 2026-11-01 미 동부 DST 끝 앞뒤
            1_792_890_000, 1_792_893_600, 1_792_897_200,   // 2026-10-25 런던 DST 끝 앞뒤
            1_791_041_400, 1_791_043_200, 1_791_045_000,   // 2026-10-04 로드하우 30분 DST 시작 앞뒤
            1_767_225_599, 1_767_225_600, 1_735_689_600, 951_782_400, 0,
        ]
        for zone in zones {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: zone)!
            var rows: [GoldenJSON] = []
            for t in instants {
                let date = Date(timeIntervalSince1970: t)
                var labels: [GoldenJSON] = []
                for delta in [0.0, 3_600, 43_200, 86_400, 90_000, 172_800, 2_592_000, -86_400] {
                    let now = Date(timeIntervalSince1970: t + delta)
                    labels.append(["nowBits": .bits(now.timeIntervalSince1970), "label": .string(MessageThreadBuilder.dayLabel(date, now: now, calendar: calendar))])
                }
                rows.append(["tBits": .bits(t), "dayKey": .string(MessageThreadBuilder.dayKey(date, calendar: calendar)),
                             "clock": .string(MessageThreadBuilder.clockText(date, calendar: calendar)), "labels": .array(labels)])
            }
            let line = (0..<9).map { k in
                MessageHistoryEntry(id: "t-\(k)", peerUserID: "p", peerName: "이름", peerAvatarURL: nil, body: "b",
                                    createdAt: Date(timeIntervalSince1970: 1_792_940_400 - 86_400 + Double(k) * 21_600), isMine: k % 2 == 0)
            }
            let now = Date(timeIntervalSince1970: 1_793_000_000)
            let timeline = MessageThreadBuilder.timeline(line, now: now, calendar: calendar).map { item -> GoldenJSON in
                switch item {
                case .day(let key, let label): return ["day": .string(key), "label": .string(label), "id": .string(item.id)]
                case .bubble(let entry): return ["bubble": .string(entry.id), "id": .string(item.id)]
                }
            }
            cases.append(["id": .string("zone-\(zone)"), "zone": .string(zone), "rows": .array(rows),
                          "timelineEntries": .array(line.map(Self.entryJSON)), "timelineNowBits": .bits(now.timeIntervalSince1970),
                          "timeline": .array(timeline)])
        }
        goldenEmit(GoldenFile(
            golden: "text/message-rules",
            equivalence: .bit,
            swiftSources: ["Sources/CheckCore/MessageRules.swift", "Sources/CheckCore/SupabaseWorkServiceMessageReads.swift"],
            platformSensitive: true,
            spec: [
                "scenario": "MiniGameRandom(0x4D530001) 100판 — 이력(같은 초 · 반 초 · 하루 전 · 중복 id · 대소문자 · 한글 id) · 서버 순서(일부 빠짐) · 도착 순서 → sortedForMessageHistory · threads · effectiveOrder · unreadPeerIDs · markTarget(기록 있음/없음, 이력 스냅숏이 없으면 serial 0 스냅숏) · isAlreadyRead(요약 없음/있음)",
                "sort": "키 (초, 서버 자리 — 없으면 Int.max, 도착 번호 — 없으면 -1, id — Swift String < ) 사전식",
                "zone": "Calendar(gregorian, timeZone) — 기기 시간대 다섯(서울 · 뉴욕 · 런던 · UTC · 로드하우). dayKey 'y-M-d'(자리 채움 없음) · dayLabel 오늘/어제/M월 d일 · clockText HH:mm",
                "platformSensitive": "true — 시간대 규칙(tzdata)",
            ],
            cases: cases
        ))
    }

    // MARK: - text/block-report

    static func facts(_ error: Error) -> String {
        if case .cancelled = AuthErrorRules.classify(error) { return "cancelled" }
        guard let service = error as? SupabaseWorkServiceError else { return "notServiceError" }
        switch service {
        case .databaseSchemaMissing: return "databaseSchemaMissing"
        case .invalidResponse(let status): return "invalidResponse:\(status)"
        case .rateLimited: return "rateLimited"
        default: return "otherServiceError"
        }
    }

    struct PlainError: Error {}

    static let detailCorpus: [String] = [
        "", "   ", "\n\n", "욕설을 했어요", "  앞뒤 공백  ", "\u{1112}\u{1161}\u{11AB}", "\u{200B}", "\u{3164}",
        String(repeating: "가", count: 179), String(repeating: "가", count: 180), String(repeating: "가", count: 200),
        String(repeating: "가", count: 201), String(repeating: "\u{1100}\u{1161}", count: 200), String(repeating: "😀", count: 200),
        String(repeating: "😀", count: 201), " " + String(repeating: "a", count: 200) + " ", String(repeating: "e\u{301}", count: 201),
    ]

    @Test("text/block-report — 문구 · 오류 갈래 · 신고 자유 입력")
    func blockReport() {
        var cases: [GoldenJSON] = []
        for platform in BlockReportPlatform.allCases {
            let name = platform == .phone ? "phone" : "mac"
            cases.append(["id": .string("text-\(name)"), "platform": .string(name),
                          "blockConfirmItems": Self.strings(BlockReportText.blockConfirmItems(platform)),
                          "blockedListPath": .string(BlockReportText.blockedListPath(platform)),
                          "blockConfirmUndoNote": .string(BlockReportText.blockConfirmUndoNote(platform)),
                          "blockedListLede": .string(BlockReportText.blockedListLede(platform)),
                          "blockedEmptyMessage": .string(BlockReportText.blockedEmptyMessage(platform))])
        }
        var constants: [String: GoldenJSON] = [
            "menuAccessibilityLabel": .string(BlockReportText.menuAccessibilityLabel), "blockAction": .string(BlockReportText.blockAction),
            "reportAction": .string(BlockReportText.reportAction), "reportMessageAction": .string(BlockReportText.reportMessageAction),
            "blockedMessagesFact": .string(BlockReportText.blockedMessagesFact), "blockConfirmScopeNote": .string(BlockReportText.blockConfirmScopeNote),
            "blockConfirm": .string(BlockReportText.blockConfirm), "blockCancel": .string(BlockReportText.blockCancel),
            "reportTitle": .string(BlockReportText.reportTitle), "reportMessageLede": .string(BlockReportText.reportMessageLede),
            "reportReasonHeader": .string(BlockReportText.reportReasonHeader), "reportDetailHeader": .string(BlockReportText.reportDetailHeader),
            "reportDetailPlaceholder": .string(BlockReportText.reportDetailPlaceholder), "reportAlsoBlock": .string(BlockReportText.reportAlsoBlock),
            "reportAlsoBlockDetail": .string(BlockReportText.reportAlsoBlockDetail), "reviewPromise": .string(BlockReportText.reviewPromise),
            "reportSubmit": .string(BlockReportText.reportSubmit), "reportSending": .string(BlockReportText.reportSending),
            "reportReasonRequired": .string(BlockReportText.reportReasonRequired), "reportDetailOverflow200": .string(BlockReportText.reportDetailOverflow(200)),
            "blockedListTitle": .string(BlockReportText.blockedListTitle), "blockedListMenuDetail": .string(BlockReportText.blockedListMenuDetail),
            "blockedEmptyTitle": .string(BlockReportText.blockedEmptyTitle), "blockedListFailed": .string(BlockReportText.blockedListFailed),
            "unblockAction": .string(BlockReportText.unblockAction), "unblockConfirmMessage": .string(BlockReportText.unblockConfirmMessage),
            "unblockConfirm": .string(BlockReportText.unblockConfirm), "reportSentNotice": .string(BlockReportText.reportSentNotice),
            "serverNotReady": .string(BlockReportText.serverNotReady), "checkConnection": .string(BlockReportText.checkConnection),
            "counterThreshold": .int(BlockReportRules.counterThreshold), "detailMaxLength": .int(ContentReportDetail.maxLength),
        ]
        let names = ["아잉", "Bob", ""]
        for (index, name) in names.enumerated() {
            constants["blockConfirmTitle:\(index)"] = .string(BlockReportText.blockConfirmTitle(name))
            constants["reportLede:\(index)"] = .string(BlockReportText.reportLede(name))
            constants["unblockConfirmTitle:\(index)"] = .string(BlockReportText.unblockConfirmTitle(name))
            constants["blockedNotice:\(index)"] = .string(BlockReportText.blockedNotice(name))
            constants["blockedAtLine:\(index)"] = .string(BlockReportText.blockedAtLine(relative: name))
        }
        cases.append(["id": "constants", "names": Self.strings(names), "values": .object(constants)])
        let errors: [(String, Error)] = [
            ("CancellationError", CancellationError()), ("URLError.cancelled", URLError(.cancelled)),
            ("URLError.notConnectedToInternet", URLError(.notConnectedToInternet)), ("URLError.timedOut", URLError(.timedOut)),
            ("PlainError", PlainError()), ("databaseSchemaMissing", SupabaseWorkServiceError.databaseSchemaMissing),
            ("invalidResponse(404)", SupabaseWorkServiceError.invalidResponse(404)), ("invalidResponse(400)", SupabaseWorkServiceError.invalidResponse(400)),
            ("invalidResponse(409)", SupabaseWorkServiceError.invalidResponse(409)), ("invalidResponse(429)", SupabaseWorkServiceError.invalidResponse(429)),
            ("invalidResponse(499)", SupabaseWorkServiceError.invalidResponse(499)), ("invalidResponse(500)", SupabaseWorkServiceError.invalidResponse(500)),
            ("invalidResponse(503)", SupabaseWorkServiceError.invalidResponse(503)), ("invalidResponse(600)", SupabaseWorkServiceError.invalidResponse(600)),
            ("rateLimited(3)", SupabaseWorkServiceError.rateLimited(retryAfterSeconds: 3)), ("rateLimited(nil)", SupabaseWorkServiceError.rateLimited(retryAfterSeconds: nil)),
            ("sessionExpired", SupabaseWorkServiceError.sessionExpired), ("missingAnonKey", SupabaseWorkServiceError.missingAnonKey),
            ("authMessage", SupabaseWorkServiceError.authMessage("x")),
        ]
        for (label, error) in errors {
            let failure = BlockReportRules.classify(error)
            let missing = (error as? SupabaseWorkServiceError).map(BlockReportRules.isMissingFunction) ?? false
            func notice(_ action: BlockReportAction) -> GoldenJSON { Self.s(BlockReportRules.notice(for: failure, action: action)) }
            cases.append(["id": .string("error-\(label)"), "facts": .string(Self.facts(error)), "isMissingFunction": .bool(missing),
                          "failure": .string("\(failure)"), "noticeBlock": notice(.block), "noticeUnblock": notice(.unblock), "noticeReport": notice(.report)])
        }
        for (index, detail) in Self.detailCorpus.enumerated() {
            cases.append(["id": .string(String(format: "detail-%02d", index)), "cps": .string(Self.cps(detail)),
                          "sanitized": .string(Self.cps(ContentReportDetail.sanitized(detail))), "length": .int(ContentReportDetail.length(detail)),
                          "withinLimit": .bool(ContentReportDetail.isWithinLimit(detail)), "payload": ContentReportDetail.payload(detail).map { .string(Self.cps($0)) } ?? .null,
                          "counter": Self.s(BlockReportRules.detailCounterText(detail)), "overflowing": .bool(BlockReportRules.isDetailOverflowing(detail)),
                          "canSubmit": .bool(BlockReportRules.canSubmitReport(reason: .spam, detail: detail, isSending: false)),
                          "canSubmitNoReason": .bool(BlockReportRules.canSubmitReport(reason: nil, detail: detail, isSending: false)),
                          "canSubmitSending": .bool(BlockReportRules.canSubmitReport(reason: .harassment, detail: detail, isSending: true))])
        }
        goldenEmit(GoldenFile(
            golden: "text/block-report",
            equivalence: .bit,
            swiftSources: ["Sources/CheckCore/BlockReportRules.swift", "Sources/CheckCore/SupabaseWorkServiceBlocks.swift", "Sources/CheckCore/AuthErrorRules.swift"],
            platformSensitive: false,
            spec: [
                "facts": "Swift 오류 → 규칙이 읽는 사실: AuthErrorRules.classify 가 cancelled 면 cancelled, SupabaseWorkServiceError 가 아니면 notServiceError, 아니면 databaseSchemaMissing · invalidResponse:<n> · rateLimited · otherServiceError (전선·인증 갈래가 이 변환을 맡는다)",
                "classify": "cancelled → 함수 없음(스키마 없음 · 404) → 5xx 연결 / 그 밖 4xx 거절 → 레이트리밋 연결 → 그 밖 거절",
                "detail": "ContentReportDetail = MessageBody 정규화·눈금, 상한 200 · 카운터는 180 부터",
            ],
            cases: cases
        ))
    }

    // MARK: - text/megaphone

    @MainActor
    final class GoldenHost: GomokuStoreHost {
        var session: SupabaseSession? = SupabaseSession(accessToken: "golden", refreshToken: nil, userID: "u-golden")
        var sessionGeneration = 0
        let service = SupabaseWorkService(projectURL: URL(string: "http://127.0.0.1:9")!, anonKey: "golden-anon")
        var realtimeState: RealtimeState = .idle(.disabled)
        var rubyBalance: Int?
        var failure: Error = URLError(.timedOut)
        /// 네트워크에 나가지 않는다 — 언제나 [failure] 로 끝난다.
        func withSessionRetry<T>(_ operation: (SupabaseSession) async throws -> T) async throws -> T { throw failure }
        func classifyAuthError(_ error: Error) -> AuthErrorDisposition { AuthErrorRules.classify(error) }
    }

    @MainActor
    enum GoldenHostRetention { static var hosts: [GoldenHost] = [] }

    @MainActor
    static func store(now: Double, ruby: Int?) -> (MegaphoneStore, GoldenHost) {
        let host = GoldenHost()
        host.rubyBalance = ruby
        GoldenHostRetention.hosts.append(host)
        let store = MegaphoneStore(host: host)
        store.clock = { Date(timeIntervalSince1970: now) }
        return (store, host)
    }

    static func infoResponseJSON(_ r: MegaphoneInfoResponse) -> GoldenJSON {
        ["status": s(r.status), "enabled": b(r.enabled), "price": i(r.price), "cooldownSeconds": i(r.cooldownSeconds),
         "cooldownRemainingSeconds": i(r.cooldownRemainingSeconds), "recipients": i(r.recipients), "maxLength": i(r.maxLength), "rubyBalance": i(r.rubyBalance)]
    }

    static func infoJSON(_ info: MegaphoneInfo?) -> GoldenJSON {
        guard let info else { return .null }
        return ["enabled": .bool(info.enabled), "price": .int(info.price), "recipients": .int(info.recipients), "maxLength": .int(info.maxLength),
                "cooldownSeconds": .int(info.cooldownSeconds), "cooldownEndsAtBits": info.cooldownEndsAt.map { .bits($0.timeIntervalSince1970) } ?? .null]
    }

    static func sendResponseJSON(_ r: MegaphoneSendResponse) -> GoldenJSON {
        ["status": .string(r.status), "megaphoneId": s(r.megaphoneId), "recipients": i(r.recipients), "price": i(r.price), "rubyBalance": i(r.rubyBalance),
         "duplicate": b(r.duplicate), "need": i(r.need), "have": i(r.have), "maxLength": i(r.maxLength), "retryAfterSeconds": i(r.retryAfterSeconds),
         "cooldownSeconds": i(r.cooldownSeconds)]
    }

    @Test("text/megaphone — 요청·응답 · 결과 · 본문 · 정보 · 보내기 전 판정 · request_id")
    @MainActor
    func megaphone() async throws {
        var cases: [GoldenJSON] = []
        cases.append(["id": "constants", "prefix": .string(Self.cps(MegaphoneBody.prefix)), "maxLength": .int(MegaphoneBody.maxLength),
                      "defaultCooldownSeconds": .int(MegaphoneStore.defaultCooldownSeconds),
                      "title": .string(MegaphoneText.title), "icon": .string(Self.cps(MegaphoneText.icon)), "badgeTitle": .string(MegaphoneText.badgeTitle),
                      "explainer": .string(MegaphoneText.explainer), "placeholder": .string(MegaphoneText.placeholder),
                      "sendButton": .string(MegaphoneText.sendButton), "cancelButton": .string(MegaphoneText.cancelButton),
                      "noRecipients": .string(MegaphoneText.noRecipients), "unavailable": .string(MegaphoneText.unavailable),
                      "empty": .string(MegaphoneText.empty), "notText": .string(MegaphoneText.notText), "blackout": .string(MegaphoneText.blackout),
                      "connection": .string(MegaphoneText.connection), "failed": .string(MegaphoneText.failed),
                      "loadingInfo": .string(MegaphoneText.loadingInfo), "infoFailed": .string(MegaphoneText.infoFailed),
                      "tooLongNil": .string(MegaphoneText.tooLong(maxLength: nil)), "tooLong50": .string(MegaphoneText.tooLong(maxLength: 50)),
                      "counter": .string(MegaphoneText.counter(length: 12, maxLength: 197)),
                      "minutes": .array([-5, 0, 1, 59, 60, 61, 119, 120, 600, 3_601].map { ["seconds": .int($0), "minutes": .int(MegaphoneText.cooldownMinutes(seconds: $0)),
                                                                                              "text": .string(MegaphoneText.cooldown(seconds: $0))] }),
                      "numbers": .array([0, 1, 37].map { ["n": .int($0), "sent": .string(MegaphoneText.sent(recipients: $0)),
                                                          "alreadySent": .string(MegaphoneText.alreadySent(recipients: $0)),
                                                          "reach": .string(MegaphoneText.reach(recipients: $0)),
                                                          "confirm": .string(MegaphoneText.confirm(price: $0 + 5, recipients: $0))] }),
                      "shortfall": .array([(nil, nil), (5, nil), (5, 3), (5, 5), (3, 5)].map { (need: Int?, have: Int?) in
                          ["need": Self.i(need), "have": Self.i(have), "text": .string(MegaphoneText.shortfall(need: need, have: have))]
                      })])
        // 본문.
        let bodies = Self.detailCorpus + ["📢 확성기", String(repeating: "가", count: 197), String(repeating: "가", count: 198), "  안녕  "]
        for (index, body) in bodies.enumerated() {
            func v(_ result: MessageBodyValidation) -> GoldenJSON {
                switch result {
                case .ok(let value): return ["ok": .string(Self.cps(value))]
                case .empty: return ["empty": true]
                case .tooLong(let limit): return ["tooLong": .int(limit)]
                }
            }
            cases.append(["id": .string(String(format: "body-%02d", index)), "cps": .string(Self.cps(body)), "length": .int(MegaphoneBody.length(body)),
                          "validate": v(MegaphoneBody.validate(body)), "validate10": v(MegaphoneBody.validate(body, maxLength: 10))])
        }
        // 요청 본문(서비스 인코더와 같은 설정).
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys]
        for (index, request) in [SendMegaphoneRequest(pBody: "모두 안녕/하세요", pRequestId: "0000abcd-0000-4000-8000-000000000001"),
                                 SendMegaphoneRequest(pBody: "", pRequestId: "")].enumerated() {
            cases.append(["id": .string("request-\(index)"), "json": .string(String(data: try encoder.encode(request), encoding: .utf8)!)])
        }
        // 응답 디코드.
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let infoBodies = [
            #"{"status":"ok","enabled":true,"price":30,"cooldown_seconds":600,"cooldown_remaining_seconds":0,"recipients":41,"max_length":197,"ruby_balance":120}"#,
            #"{"status":"ok","price":30,"recipients":-3}"#, #"{"status":"ok","price":30,"recipients":5,"cooldown_remaining_seconds":125}"#,
            #"{"status":"ok","price":30,"recipients":5,"cooldown_remaining_seconds":-4,"cooldown_seconds":90,"enabled":false}"#,
            #"{"status":"ok","price":30}"#, #"{"status":"disabled","price":30,"recipients":5}"#, #"{"price":30,"recipients":5}"#,
            #"{"status":"ok","price":"30","recipients":5}"#, #"{"status":"ok","price":30.0,"recipients":5}"#, #"{"status":"ok","price":30.5,"recipients":5}"#,
            #"{"status":null,"price":30,"recipients":5}"#, #"{}"#, #"[]"#, #"{"status":"ok","price":30,"recipients":5,"max_length":null,"unknown":1}"#,
        ]
        for (index, text) in infoBodies.enumerated() {
            let id = String(format: "info-%02d", index)
            guard let response = try? decoder.decode(MegaphoneInfoResponse.self, from: Data(text.utf8)) else {
                cases.append(["id": .string(id), "json": .string(text), "throws": true])
                continue
            }
            var rows: [GoldenJSON] = []
            for ruby in [nil, 0, 120] as [Int?] {
                let now = 1_792_998_000.5
                let (store, host) = Self.store(now: now, ruby: ruby)
                store.applyInfo(response)
                rows.append(["ruby": Self.i(ruby), "info": Self.infoJSON(store.info), "infoFailed": .bool(store.infoFailed),
                             "rubyAfter": Self.i(host.rubyBalance),
                             "lines": .array([now, now + 60, now + 124.6, now + 125, now + 700].map {
                                 ["nowBits": .bits($0), "line": .string(store.infoLine(now: Date(timeIntervalSince1970: $0))),
                                  "remaining": .int(store.info?.cooldownRemaining(now: Date(timeIntervalSince1970: $0)) ?? -1)]
                             })])
            }
            cases.append(["id": .string(id), "json": .string(text), "response": Self.infoResponseJSON(response), "rows": .array(rows)])
        }
        // 보내기 응답 → 결과 · 문구 · 정보 갱신(실제 store.apply).
        let sendBodies = [
            #"{"status":"ok","megaphone_id":"x","recipients":41,"price":30,"ruby_balance":90}"#, #"{"status":"ok","recipients":41,"duplicate":true}"#,
            #"{"status":"ok"}"#, #"{"status":"insufficient","need":30,"have":12}"#, #"{"status":"insufficient"}"#,
            #"{"status":"cooldown","retry_after_seconds":125}"#, #"{"status":"cooldown","retry_after_seconds":0}"#, #"{"status":"cooldown"}"#,
            #"{"status":"no_recipients"}"#, #"{"status":"empty"}"#, #"{"status":"too_long","max_length":197}"#, #"{"status":"too_long"}"#,
            #"{"status":"not_text"}"#, #"{"status":"disabled"}"#, #"{"status":"blackout"}"#, #"{"status":"weird"}"#,
            #"{"recipients":3}"#, #"{"status":"ok","recipients":"3"}"#, #"{"status":"ok","duplicate":1}"#, #"{"status":"ok","need":null}"#,
        ]
        for (index, text) in sendBodies.enumerated() {
            let id = String(format: "send-%02d", index)
            guard let response = try? decoder.decode(MegaphoneSendResponse.self, from: Data(text.utf8)) else {
                cases.append(["id": .string(id), "json": .string(text), "throws": true])
                continue
            }
            var rows: [GoldenJSON] = []
            for withInfo in [false, true] {
                let now = 1_792_998_000.25
                let (store, host) = Self.store(now: now, ruby: 50)
                if withInfo { store.applyInfo(MegaphoneInfoResponse(status: "ok", enabled: true, price: 30, cooldownSeconds: 300, recipients: 9, maxLength: 197)) }
                let before = store.info
                store.apply(response, requestID: "req-1")
                rows.append(["withInfo": .bool(withInfo), "infoBefore": Self.infoJSON(before), "notice": Self.s(store.notice),
                             "noticeIsError": .bool(store.noticeIsError), "info": Self.infoJSON(store.info), "rubyAfter": Self.i(host.rubyBalance),
                             "serverUnavailable": .bool(store.serverUnavailable)])
            }
            cases.append(["id": .string(id), "json": .string(text), "response": Self.sendResponseJSON(response),
                          "outcome": .string("\(MegaphoneSendOutcome(response: response))"), "rows": .array(rows)])
        }
        // 보내기 전 판정(실제 store.requestSend).
        let gateInfos: [(String, MegaphoneInfoResponse?)] = [
            ("none", nil), ("ok", MegaphoneInfoResponse(status: "ok", enabled: true, price: 30, cooldownSeconds: 600, recipients: 9, maxLength: 197)),
            ("disabled", MegaphoneInfoResponse(status: "ok", enabled: false, price: 30, recipients: 9)),
            ("cooldown", MegaphoneInfoResponse(status: "ok", price: 30, cooldownRemainingSeconds: 61, recipients: 9)),
            ("zero", MegaphoneInfoResponse(status: "ok", price: 30, recipients: 0)),
            ("short", MegaphoneInfoResponse(status: "ok", price: 30, recipients: 9, maxLength: 5)),
        ]
        var gateRows: [GoldenJSON] = []
        for (infoName, infoResponse) in gateInfos {
            for draft in ["", "  ", "모두 안녕", "여섯 글자예요", String(repeating: "가", count: 198)] {
                for ruby in [nil, 10, 30] as [Int?] {
                    for flags in 0..<3 {   // 0 = 보통, 1 = 함수 없음(serverUnavailable), 2 = 정보 못 읽음(infoFailed)
                        let now = 1_792_998_000.0
                        let (store, host) = Self.store(now: now, ruby: ruby)
                        if let infoResponse { store.applyInfo(infoResponse) }
                        if flags == 2 { store.applyInfo(MegaphoneInfoResponse(status: "nope")) }
                        if flags == 1 {
                            // 함수 없음: 정보 읽기가 스키마 없음으로 끝난 상태(loadInfo 의 실패 길 — 네트워크에 나가지 않는다).
                            host.failure = SupabaseWorkServiceError.databaseSchemaMissing
                            store.loadInfo()
                            var spins = 0
                            while store.infoLoading && spins < 10_000 { await Task.yield(); spins += 1 }
                            host.failure = URLError(.timedOut)
                        }
                        store.setDraft(draft)
                        let unavailable = store.serverUnavailable
                        let infoFailed = store.infoFailed
                        let infoBefore = store.info
                        store.requestSend()
                        gateRows.append(["info": .string(infoName), "draft": .string(Self.cps(draft)), "ruby": Self.i(ruby), "flags": .int(flags),
                                         "infoBefore": Self.infoJSON(infoBefore), "serverUnavailable": .bool(unavailable), "infoFailed": .bool(infoFailed),
                                         "notice": Self.s(store.notice), "noticeIsError": .bool(store.noticeIsError),
                                         "confirming": .bool(store.isConfirming), "reloading": .bool(store.infoLoading)])
                    }
                }
            }
        }
        cases.append(["id": "gate", "nowBits": .bits(1_792_998_000.0), "rows": .array(gateRows)])
        // request_id 쥐기(C§4 #26) — 실제 confirmSend 를 몰아 실패 뒤 id 를 잰다.
        let failures: [(String, Error)] = [
            ("URLError.timedOut", URLError(.timedOut)), ("CancellationError", CancellationError()),
            ("invalidResponse(503)", SupabaseWorkServiceError.invalidResponse(503)), ("databaseSchemaMissing", SupabaseWorkServiceError.databaseSchemaMissing),
            ("invalidResponse(404)", SupabaseWorkServiceError.invalidResponse(404)), ("PlainError", PlainError()),
        ]
        var idRows: [GoldenJSON] = []
        for (label, error) in failures {
            let (store, host) = Self.store(now: 1_792_998_000, ruby: 100)
            var made = 0
            store.makeRequestID = { made += 1; return "REQ-\(made)" }
            store.applyInfo(MegaphoneInfoResponse(status: "ok", enabled: true, price: 30, cooldownSeconds: 600, recipients: 9, maxLength: 197))
            store.setDraft("모두 안녕")
            host.failure = error
            var steps: [GoldenJSON] = []
            for _ in 0..<2 {
                store.requestSend()
                let started = store.confirmSend()
                let sentID = store.pendingRequestID
                var spins = 0
                while store.isSending && spins < 10_000 { await Task.yield(); spins += 1 }
                steps.append(["started": .bool(started), "sentID": Self.s(sentID), "pendingAfter": Self.s(store.pendingRequestID),
                              "notice": Self.s(store.notice), "confirming": .bool(store.isConfirming), "serverUnavailable": .bool(store.serverUnavailable)])
            }
            let held = store.pendingRequestID
            if let held { store.apply(MegaphoneSendResponse(status: "ok", recipients: 9), requestID: held) }
            idRows.append(["failure": .string(label), "facts": .string(Self.facts(error)),
                           "isMissingFunction": .bool((error as? SupabaseWorkServiceError).map(BlockReportRules.isMissingFunction) ?? false),
                           "steps": .array(steps), "pendingAfterSettle": Self.s(store.pendingRequestID), "made": .int(made)])
        }
        cases.append(["id": "request-ids", "rows": .array(idRows)])
        goldenEmit(GoldenFile(
            golden: "text/megaphone",
            equivalence: .bit,
            swiftSources: ["Sources/CheckCore/Megaphone.swift"],
            platformSensitive: true,
            spec: [
                "decode": "JSONDecoder(convertFromSnakeCase) — 칸은 decodeIfPresent(모양이 틀리면 전체 throw), 보내기 응답은 status 필수",
                "send": "실제 MegaphoneStore.apply — 결과 → 문구(오류 여부) · 정보 갱신(새로 보냄 = 지금 + 쿨다운, cooldown = 서버 값 → 정보 쿨다운 → 600, 최소 1) · 루비 미러",
                "gate": "실제 MegaphoneStore.requestSend — 함수 없음 → 본문(빈 → 긺, 상한은 정보의 max_length) → 정보 모름(못 읽음이면 오류 · 다시 읽기) → 꺼짐 → 쿨다운 → 받는 사람 0 → 루비 부족(잔액을 알 때만) → 확인",
                "requestIds": "실제 confirmSend — 결과 모름(연결 · 5xx · 취소 · 그 밖)은 id 를 쥐고 다시 누르면 같은 id, 함수 없음(스키마 없음 · 404)은 버린다. 응답이 오면 버린다. id 는 소문자로 접지 않은 채 쓴다(Swift 는 생성기가 소문자를 만든다)",
                "platformSensitive": "true — 본문 판정이 NFC · 번들 표에 기댄다",
            ],
            cases: cases
        ))
    }
}
