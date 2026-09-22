import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// v0.3.34 — 신고 관리자 화면(맥 "받은 제보" 탭 안의 [신고] 칸) · 코어 디코드 · 스토어 · 메뉴바 점 · 렌더.
//
// SPEC w20 갈래 A 의 테스트 목록 그대로다: 스토어(목록 · 상태 변경 · 늦은 응답 · 비운영자에게 표면 없음) ·
// 렌더(신고 행 · 원문 인용) · 코어 디코드. 마이그레이션 계약은 `V0334ReportAdminMigrationTests` 가 따로 본다.
//
// ★ 이 파일의 픽스처 글(상세 · 메시지 원문 · 메모)은 전부 **합성 문자열**이다. 실제 신고를 옮겨 오지 마라 —
//   테스트 파일은 퍼블릭 저장소에 남고, 신고는 남에게 보여 주려고 쓴 글이 아니다.
//
// 네트워크는 아래 `ReportAdminURLProtocol`(테스트별 고유 호스트)로 격리한다. 제보 테스트의 `FeedbackURLProtocol` 을 쓰지 않는
// 이유는 **응답을 붙잡아 두는 손잡이**가 필요해서다 — "늦은 응답"과 "낙관 반영 없음"은 왕복이 떠 있는 동안의 화면을 재야
// 증명된다(즉시 답하는 스텁으로는 두 경우 모두 초록인 채로 아무것도 안 잰다).

private let raUserID = "00000000-0000-0000-0000-00000000a001"
private let raListPath = "/rest/v1/rpc/report_admin_list"
private let raUpdatePath = "/rest/v1/rpc/report_admin_update"
private let raCountPath = "/rest/v1/rpc/report_open_count"

// MARK: - 붙잡을 수 있는 네트워크

final class ReportAdminURLProtocol: URLProtocol {
    struct Reply {
        let status: Int
        let body: String
        init(status: Int = 200, body: String = "[]") {
            self.status = status
            self.body = body
        }
    }

    private static let lock = NSLock()
    private nonisolated(unsafe) static var replies: [String: [String: Reply]] = [:]
    private nonisolated(unsafe) static var bodies: [String: [String: [String]]] = [:]
    private nonisolated(unsafe) static var counts: [String: [String: Int]] = [:]
    private nonisolated(unsafe) static var holding: [String: Set<String>] = [:]
    private nonisolated(unsafe) static var held: [String: [String: [ReportAdminURLProtocol]]] = [:]

    static func set(_ reply: Reply, host: String, path: String) {
        lock.lock(); defer { lock.unlock() }
        replies[host, default: [:]][path] = reply
    }

    static func reset(host: String) {
        lock.lock(); defer { lock.unlock() }
        replies[host] = nil
        bodies[host] = nil
        counts[host] = nil
        holding[host] = nil
        held[host] = nil
    }

    /// 이 경로로 오는 요청을 **답하지 않고 붙잡는다**(`release` 로 하나씩 푼다).
    static func hold(host: String, path: String) {
        lock.lock(); defer { lock.unlock() }
        holding[host, default: []].insert(path)
    }

    static func stopHolding(host: String, path: String) {
        lock.lock(); defer { lock.unlock() }
        holding[host]?.remove(path)
    }

    static func heldCount(host: String, path: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        return held[host]?[path]?.count ?? 0
    }

    /// 붙잡아 둔 요청 중 `index` 번째(도착 순)를 주어진 응답으로 푼다.
    static func release(host: String, path: String, index: Int = 0, with reply: Reply) {
        lock.lock()
        guard var queue = held[host]?[path], queue.indices.contains(index) else { lock.unlock(); return }
        let request = queue.remove(at: index)
        held[host]?[path] = queue
        lock.unlock()
        request.deliver(reply)
    }

    static func count(host: String, path: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        return counts[host]?[path] ?? 0
    }

    static func sentBodies(host: String, path: String) -> [String] {
        lock.lock(); defer { lock.unlock() }
        return bodies[host]?[path] ?? []
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReportAdminURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    private static func bodyText(from request: URLRequest) -> String {
        if let body = request.httpBody { return String(data: body, encoding: .utf8) ?? "" }
        guard let stream = request.httpBodyStream else { return "" }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let size = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: size)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    override func startLoading() {
        let host = request.url?.host ?? ""
        let path = request.url?.path ?? ""
        let text = Self.bodyText(from: request)
        Self.lock.lock()
        Self.counts[host, default: [:]][path, default: 0] += 1
        Self.bodies[host, default: [:]][path, default: []].append(text)
        if Self.holding[host]?.contains(path) == true {
            Self.held[host, default: [:]][path, default: []].append(self)
            Self.lock.unlock()
            return
        }
        let reply = Self.replies[host]?[path] ?? Reply()
        Self.lock.unlock()
        deliver(reply)
    }

    fileprivate func deliver(_ reply: Reply) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: reply.status,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

// MARK: - 픽스처

/// 격리 defaults. 이름을 테스트 신원(+호스트)에서 뽑아 `CheckTestScratch.root`($TMPDIR)에 둔다 —
/// UUID 이름은 실행마다 ~/Library/Preferences 에 plist 를 하나씩 영구히 남긴다(그 파일 주석의 2026-09-22 사고).
@MainActor
private func raDefaults(_ label: String = "", function: String = #function) -> UserDefaults {
    CheckTestScratch.defaults(label, function: function)
}

@MainActor
private func raStore(host: String, admin: Bool = true, signedIn: Bool = true,
                     function: String = #function) -> WorkTimerStore {
    ReportAdminURLProtocol.reset(host: host)
    let service = SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!,
        anonKey: "anon-test-key",
        session: ReportAdminURLProtocol.session()
    )
    let store = WorkTimerStore(
        service: service,
        environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
        defaults: raDefaults(host, function: function)
    )
    if signedIn {
        store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: raUserID)
    }
    store.ultraUnlimited = admin
    store.appVersionProvider = { AppVersionReport(build: 90, version: "0.3.34") }
    store.osVersionProvider = { "15.6" }
    return store
}

@MainActor
private func raService(host: String) -> SupabaseWorkService {
    ReportAdminURLProtocol.reset(host: host)
    return SupabaseWorkService(
        projectURL: URL(string: "http://\(host)")!,
        anonKey: "anon-test-key",
        session: ReportAdminURLProtocol.session()
    )
}

/// 200×5ms 폴링(≈1초 상한).
@MainActor
private func raWait(_ condition: @MainActor () -> Bool) async {
    for _ in 0..<200 {
        if condition() { return }
        try? await Task.sleep(for: .milliseconds(5))
    }
}

/// 서버 행 한 줄(JSON). 칸은 서버 반환 이름 그대로(스네이크). 값은 전부 합성이다.
private func raRowJSON(
    id: String,
    reporterID: String? = "u-reporter",
    reporterName: String? = "신고자",
    targetID: String = "u-target",
    targetName: String? = "대상",
    reason: String = "harassment",
    detail: String? = "샘플 상세",
    messageBody: String? = "샘플 메시지 원문",
    status: String = "open",
    adminNote: String? = nil,
    createdAt: String = "2026-09-19T16:07:03.591038+00:00",
    handledAt: String? = nil
) -> String {
    func quoted(_ value: String?) -> String {
        guard let value else { return "null" }
        let data = try! JSONSerialization.data(withJSONObject: [value])
        let array = String(data: data, encoding: .utf8)!
        return String(array.dropFirst().dropLast())
    }
    return """
    {"id":\(quoted(id)),"reporter_id":\(quoted(reporterID)),"reporter_name":\(quoted(reporterName)),\
    "reporter_avatar_url":null,"target_id":\(quoted(targetID)),"target_name":\(quoted(targetName)),"target_avatar_url":null,\
    "reason":\(quoted(reason)),"detail":\(quoted(detail)),"message_body":\(quoted(messageBody)),"status":\(quoted(status)),\
    "admin_note":\(quoted(adminNote)),"created_at":\(quoted(createdAt)),"handled_at":\(quoted(handledAt))}
    """
}

private func raList(_ rows: String...) -> String { "[" + rows.joined(separator: ",") + "]" }

private func raItem(
    id: String,
    status: ContentReportStatus = .open,
    reporterID: String? = "u-reporter",
    reason: String = "harassment",
    detail: String? = "샘플 상세",
    messageBody: String? = "샘플 메시지 원문",
    adminNote: String? = nil,
    createdAt: Date = Date(timeIntervalSince1970: 1_789_000_000),
    handledAt: Date? = nil
) -> ContentReportAdminItem {
    ContentReportAdminItem(
        id: id,
        reporterID: reporterID,
        reporterName: reporterID == nil ? ReportAdminNames.departedReporter : "신고자\(id)",
        reporterAvatarURL: nil,
        targetID: "u-target",
        targetName: "대상\(id)",
        targetAvatarURL: nil,
        reason: reason,
        detail: detail,
        messageBody: messageBody,
        status: status,
        adminNote: adminNote,
        createdAt: createdAt,
        handledAt: handledAt
    )
}

private func raPayload(_ raw: String) -> [String: Any] {
    ((try? JSONSerialization.jsonObject(with: Data(raw.utf8))) as? [String: Any]) ?? [:]
}

// MARK: - 코어 디코드

@MainActor
@Test
func 신고_목록_디코드는_칸_하나가_어긋나도_목록을_살린다() async throws {
    let host = "ra-decode"
    let service = raService(host: host)
    let full = raRowJSON(id: "r1", adminNote: "  ", handledAt: "2026-09-19T17:00:00+00:00")
    let departed = raRowJSON(id: "r2", reporterID: nil, reporterName: nil, reason: "spam", detail: nil, messageBody: nil)
    // 칸 하나의 **타입**이 어긋난 행(상세가 숫자) — 배열 디코드가 통째로 throw 되면 목록 전체가 사라진다.
    let wrongType = raRowJSON(id: "r3").replacingOccurrences(of: "\"detail\":\"샘플 상세\"", with: "\"detail\":5")
    // 칸이 **없는** 행(서버가 칸을 덜 실은 날) — 모르는 상태 · 모르는 사유도 섞는다.
    let sparse = #"{"id":"r4","status":"escalated","reason":"doxxing"}"#
    // id 가 없는 행 — 처리 버튼을 걸 곳이 없으니 버린다.
    let noID = #"{"reporter_id":"u-x","status":"open"}"#
    ReportAdminURLProtocol.set(.init(body: raList(full, departed, wrongType, sparse, noID)), host: host, path: raListPath)

    let items = try await service.fetchReportAdminList(accessToken: "t", status: nil, limit: 200)
    #expect(items.map(\.id) == ["r1", "r2", "r3", "r4"], "id 없는 행만 버려야 한다: \(items.map(\.id))")

    let first = items[0]
    #expect(first.reporterID == "u-reporter" && first.reporterName == "신고자" && first.targetName == "대상")
    #expect(first.reasonLabel == "욕설·괴롭힘", "사유 라벨이 폰 신고 시트의 글자와 다르다: \(first.reasonLabel)")
    #expect(first.detail == "샘플 상세" && first.messageBody == "샘플 메시지 원문" && first.isMessageReport)
    #expect(first.adminNote == nil, "공백만 남은 메모를 메모로 그렸다 — 빈 판이 서면 운영자는 뭔가 적힌 줄 안다")
    #expect(first.createdAt != nil, "소수초 6자리 timestamptz 를 못 읽었다")
    #expect(first.handledAt != nil)
    #expect(first.status == .open)

    let second = items[1]
    #expect(second.reporterDeparted && second.reporterName == ReportAdminNames.departedReporter,
            "계정을 지운 신고자를 '\(second.reporterName)'(으)로 그렸다")
    #expect(!second.isMessageReport && second.reasonLabel == "스팸")

    #expect(items[2].detail == nil && items[2].messageBody == "샘플 메시지 원문", "타입이 어긋난 칸 하나 때문에 다른 칸을 잃었다")

    let fourth = items[3]
    #expect(fourth.status == .other("escalated") && fourth.status.reportLabel == "escalated",
            "모르는 상태를 접었다 — 처리된 신고가 미해결로 오배달된다")
    #expect(fourth.reasonLabel == "doxxing", "모르는 사유를 접었다")
    #expect(fourth.targetName == ReportAdminNames.unnamed && fourth.reporterDeparted)

    // 전체 조회는 p_status 키를 **빼고** 보낸다(서버 기본값 null — 앱이 생략하는 인자).
    let sent = raPayload(try #require(ReportAdminURLProtocol.sentBodies(host: host, path: raListPath).first))
    #expect(Set(sent.keys) == ["p_limit"] && sent["p_limit"] as? Int == 200, "목록 본문이 계약과 다르다: \(sent)")
}

@MainActor
@Test
func 처리_요청은_서버_어휘로_가고_시각을_못_읽어도_성공이다() async throws {
    let host = "ra-update-wire"
    let service = raService(host: host)
    ReportAdminURLProtocol.set(.init(body: #""2026-09-20T01:02:03.456789+00:00""#), host: host, path: raUpdatePath)
    let at = try await service.updateReportAdmin(accessToken: "t", id: "r1", status: .held, note: "")
    #expect(at != nil)
    let sent = raPayload(try #require(ReportAdminURLProtocol.sentBodies(host: host, path: raUpdatePath).first))
    #expect(sent["p_id"] as? String == "r1")
    #expect(sent["p_status"] as? String == "wontfix", "화면 라벨('무시')·케이스 이름이 아니라 서버 어휘를 보내야 한다")
    #expect(sent["p_note"] as? String == "", "빈 메모(= 지운다)가 키째 빠졌다 — 서버는 '그대로 둔다'로 읽는다")

    // 서버가 이미 저장했는데 시각 모양이 낯설다고 실패로 뒤집지 않는다(운영자가 같은 처리를 또 누른다).
    ReportAdminURLProtocol.set(.init(body: #""yesterday""#), host: host, path: raUpdatePath)
    let odd = try await service.updateReportAdmin(accessToken: "t", id: "r1", status: .done, note: nil)
    #expect(odd == nil)
    let second = raPayload(ReportAdminURLProtocol.sentBodies(host: host, path: raUpdatePath).last ?? "")
    #expect(Set(second.keys) == ["p_id", "p_status"], "메모를 안 건드리는 처리가 p_note 를 실었다: \(second.keys.sorted())")

    // 건수: 숫자면 그 값, 모양이 어긋나면 0(배지 하나 때문에 실패를 올리지 않는다).
    ReportAdminURLProtocol.set(.init(body: "4"), host: host, path: raCountPath)
    #expect(try await service.fetchReportOpenCount(accessToken: "t") == 4)
    ReportAdminURLProtocol.set(.init(body: "{}"), host: host, path: raCountPath)
    #expect(try await service.fetchReportOpenCount(accessToken: "t") == 0)
    #expect(raPayload(ReportAdminURLProtocol.sentBodies(host: host, path: raCountPath).first ?? "x").isEmpty,
            "인자 없는 RPC 의 본문이 {} 가 아니다")
}

@Test
func 처리_메모는_코드포인트_500에서_자르고_비우면_빈_문자열이다() {
    #expect(ReportAdminNote.outgoing("  메모  \n") == "메모")
    #expect(ReportAdminNote.outgoing("   ") == "", "비운 칸은 빈 문자열(= 지운다)로 나가야 한다")
    #expect(ReportAdminNote.outgoing(String(repeating: "가", count: 600)).count == 500)
    // 이모지 하나가 코드포인트 여럿이다 — 자소 묶음으로 500을 자르면 서버(char_length)가 REPORT_NOTE_TOO_LONG 으로 거절한다.
    let family = String(repeating: "👨‍👩‍👧‍👦", count: 100)   // 자소 100 · 코드포인트 700
    let clamped = ReportAdminNote.outgoing(family)
    #expect(clamped.unicodeScalars.count <= 500, "코드포인트로 500을 넘겨 보낸다(\(clamped.unicodeScalars.count))")
    #expect(clamped.count == 71, "자소 묶음을 반으로 갈랐거나 너무 많이 버렸다(\(clamped.count))")
    #expect(ReportAdminNote.maxLength == FeedbackComposer.maxNoteLength, "메모 상한이 제보함 답장 메모와 갈렸다")
}

@Test
func 신고_라벨과_실패_문구는_서버_어휘를_화면에_흘리지_않는다() {
    #expect(ContentReportStatus.reportTransitions.map(\.reportLabel) == ["미해결", "처리 중", "조치함", "무시"])
    // 제보 라벨은 그대로다(같은 타입을 쓰지만 제보 화면의 글자는 한 자도 안 바뀐다).
    #expect(FeedbackStatus.known.map(\.label) == ["미해결", "진행", "완료", "보류"])
    let cases: [(String, String)] = [
        ("REPORT_FORBIDDEN", ReportAdminText.forbidden),
        ("REPORT_BAD_STATUS", ReportAdminText.badStatus),
        ("REPORT_NOTE_TOO_LONG", ReportAdminText.noteTooLong),
        ("REPORT_NOT_FOUND", ReportAdminText.notFound),
        ("SOMETHING_NEW", ReportAdminText.failedUpdate),
    ]
    for (code, expected) in cases {
        let notice = ReportAdminFailure.notice(for: SupabaseWorkServiceError.authMessage(code))
        #expect(notice == expected, "\(code) → \(notice)")
        #expect(!notice.contains("_"), "서버 예외 이름이 화면으로 샜다: \(notice)")
    }
    #expect(ReportAdminFailure.notice(for: SupabaseWorkServiceError.databaseSchemaMissing) == ReportAdminText.schemaMissing)
    #expect(ReportAdminText.isSuccessNotice(ReportAdminText.saved(.done)))
    #expect(!ReportAdminText.isSuccessNotice(ReportAdminText.forbidden))
}

// MARK: - 스토어: 목록

@MainActor
@Test
func 신고_칸을_고르면_목록과_건수를_한_번씩_받고_미해결_먼저_세운다() async throws {
    let host = "ra-store-list"
    let store = raStore(host: host)
    ReportAdminURLProtocol.set(.init(body: raList(
        raRowJSON(id: "done-new", status: "done", createdAt: "2026-09-19T18:00:00+00:00"),
        raRowJSON(id: "open-old", createdAt: "2026-09-18T10:00:00+00:00"),
        raRowJSON(id: "open-new", createdAt: "2026-09-19T12:00:00+00:00")
    )), host: host, path: raListPath)
    ReportAdminURLProtocol.set(.init(body: "2"), host: host, path: raCountPath)
    store.feedbackShowsInbox = true

    store.selectInboxSegment(reports: true)
    #expect(store.showsReportAdmin)
    #expect(store.reportAdminLoading, "첫 프레임에 '불러오는 중…'이 안 선다")
    await raWait { store.reportOpenCount == 2 }

    #expect(store.visibleReports.map(\.id) == ["open-new", "open-old", "done-new"], "미해결 먼저 · 최신순이 아니다")
    #expect(store.reportAdminLoaded && !store.reportAdminLoading && !store.reportAdminFailed)
    #expect(ReportAdminURLProtocol.count(host: host, path: raListPath) == 1, "칸을 고를 때 목록 조회가 여러 번 나갔다")
    #expect(ReportAdminURLProtocol.count(host: host, path: raCountPath) == 1)
    // 레일 [제보] 배지·받은 제보 탭 배지가 읽는 합.
    store.feedbackOpenCount = 3
    #expect(store.adminInboxOpenCount == 5)

    // 필터·펼침은 왕복을 내지 않는다(무료 플랜 — 거르기는 순수 계산).
    store.selectReportFilter(.done)
    #expect(store.visibleReports.map(\.id) == ["done-new"])
    store.selectReportFilter(nil)
    store.reportAdminList[0].adminNote = "앞선 메모"
    store.toggleReportExpansion(store.reportAdminList[0].id)
    #expect(store.reportNoteDraft == "앞선 메모", "펼칠 때 저장된 메모를 안 실었다 — 상태 버튼 한 번에 메모가 지워진다")
    store.selectReportFilter(.held)
    #expect(store.expandedReportID == nil && store.reportNoteDraft.isEmpty)
    await raWait { false }
    #expect(ReportAdminURLProtocol.count(host: host, path: raListPath) == 1, "필터·펼침이 서버에 물었다")
}

@MainActor
@Test
func 서버가_아직_신고_함수를_모르면_신고가_없다고_단정하지_않는다() async throws {
    // 신고 표(content_reports)와 신고 입력(report_content)은 20260918180000 부터 운영 중이다. 목록 RPC 만 없는 창
    // (brew 가 db push 보다 먼저 나간 경우)에 "받은 신고가 없어요"를 띄우면 거짓이다 — 표에는 행이 쌓이는 중이다.
    // 제보함이 이 창을 빈 목록으로 접는 근거("표 자체가 없다 = 정말 0건")가 여기서는 성립하지 않는다.
    let host = "ra-store-schema-missing"
    let store = raStore(host: host)
    ReportAdminURLProtocol.set(
        .init(status: 404, body: #"{"code":"PGRST202","message":"Could not find the function public.report_admin_list(p_limit) in the schema cache"}"#),
        host: host, path: raListPath
    )
    store.feedbackShowsInbox = true
    store.selectInboxSegment(reports: true)
    await raWait { ReportAdminURLProtocol.count(host: host, path: raListPath) == 1 && !store.reportAdminLoading }
    await raWait { false }

    // 뷰가 읽는 값 그대로(`ReportAdminInboxView` 는 `store.reportAdminEmptyState` · `store.reportAdminShowsRetry` 를 그린다).
    let state = store.reportAdminEmptyState
    #expect(state.text != ReportAdminText.empty, "서버 함수가 없는데 '받은 신고가 없어요'라고 단정했다 — 표에는 신고가 쌓이는 중이다")
    #expect(state.hint != ReportAdminText.emptyHint, "할 일이 없다는 보조 줄이 떴다 — 24시간 약속이 조용히 깨진다")
    #expect(state.text != ReportAdminText.loading, "응답이 왔는데 '불러오는 중…'에 멈췄다")
    #expect(state == FeedbackEmptyState(
        text: ReportAdminText.schemaMissingList, hint: ReportAdminText.schemaMissingListHint,
        symbol: FeedbackEmptyMessage.loadingSymbol
    ))
    #expect(ReportAdminText.schemaMissingListHint.contains("[\(FeedbackText.retry)]"), "보조 줄이 화면에 없는 버튼을 부른다")
    #expect(!store.reportAdminFailed, "db push 전 창을 빨간 실패로 칠했다 — 운영자에게 필요한 말은 '서버가 아직'이다")
    #expect(store.reportAdminShowsRetry, "db push 뒤 다시 불러올 길이 없다")
    let view = raStripSwiftComments(try raSource("CheckReportAdminView.swift"))
    #expect(view.contains("state: store.reportAdminEmptyState"), "뷰가 스토어 판정을 안 읽는다 — 테스트와 화면이 갈린다")
    #expect(view.contains("showsRetry: store.reportAdminShowsRetry"))

    // 서버가 올라온 뒤 [다시 시도] → 목록이 서고 부재 상태가 풀린다.
    ReportAdminURLProtocol.set(.init(body: raList(raRowJSON(id: "r1"))), host: host, path: raListPath)
    store.loadReportAdmin()
    await raWait { store.reportAdminLoaded }
    #expect(store.reportAdminLoaded && !store.reportAdminSchemaMissing && store.visibleReports.map(\.id) == ["r1"])
    #expect(!store.reportAdminShowsRetry)
}

// MARK: - 스토어: 처리(낙관 반영 없음 · 잠금 · 실패)

@MainActor
@Test
func 처리는_저장되기_전에는_화면을_안_바꾸고_떠_있는_동안_버튼을_잠근다() async throws {
    let host = "ra-store-update"
    let store = raStore(host: host)
    store.feedbackShowsInbox = true
    store.feedbackInboxShowsReports = true
    store.reportAdminList = [raItem(id: "r1"), raItem(id: "r2")]
    store.reportAdminLoaded = true
    store.toggleReportExpansion("r1")
    store.reportNoteDraft = "  경고함  "
    ReportAdminURLProtocol.hold(host: host, path: raUpdatePath)
    ReportAdminURLProtocol.set(.init(body: raList(raRowJSON(id: "r1", status: "doing", adminNote: "경고함",
                                                            handledAt: "2026-09-20T01:00:00+00:00"))),
                               host: host, path: raListPath)
    ReportAdminURLProtocol.set(.init(body: "0"), host: host, path: raCountPath)

    store.applyReportStatus(id: "r1", status: .inProgress)
    await raWait { ReportAdminURLProtocol.heldCount(host: host, path: raUpdatePath) == 1 }

    // ★ 왕복이 떠 있는 동안: 행은 **그대로**, 버튼은 잠김, 두 번째 처리는 나가지 않는다.
    #expect(store.reportAdminList.first { $0.id == "r1" }?.status == .open, "저장되기 전에 칩이 바뀌었다 — 실패해도 된 것처럼 보인다")
    #expect(!store.canUpdateReport && store.reportUpdatingID == "r1")
    store.applyReportStatus(id: "r1", status: .done)
    await raWait { false }
    #expect(ReportAdminURLProtocol.count(host: host, path: raUpdatePath) == 1, "떠 있는 처리 위에 두 번째 처리가 나갔다")

    let sent = raPayload(try #require(ReportAdminURLProtocol.sentBodies(host: host, path: raUpdatePath).first))
    #expect(sent["p_id"] as? String == "r1" && sent["p_status"] as? String == "doing")
    #expect(sent["p_note"] as? String == "경고함", "메모 칸의 글(다듬은 것)이 함께 안 갔다: \(sent)")

    ReportAdminURLProtocol.release(host: host, path: raUpdatePath, with: .init(body: #""2026-09-20T01:00:00+00:00""#))
    await raWait { store.reportAdminNotice != nil && ReportAdminURLProtocol.count(host: host, path: raListPath) >= 1 }
    await raWait { store.reportAdminList.count == 1 }

    #expect(store.reportAdminNotice == ReportAdminText.saved(.inProgress))
    #expect(ReportAdminText.isSuccessNotice(store.reportAdminNotice ?? ""))
    #expect(store.canUpdateReport, "성공했는데 잠금이 안 풀렸다")
    // 성공 때만 재조회한다(정렬·건수·메뉴바 점을 서버 사실에 맞춘다).
    #expect(ReportAdminURLProtocol.count(host: host, path: raListPath) == 1)
    let saved = try #require(store.reportAdminList.first { $0.id == "r1" })
    #expect(saved.status == .inProgress && saved.adminNote == "경고함" && saved.handledAt != nil)
}

@MainActor
@Test
func 처리가_거절되면_목록은_한_글자도_안_바뀌고_이유를_사람_말로_말한다() async {
    let host = "ra-store-forbidden"
    let store = raStore(host: host)
    store.feedbackShowsInbox = true
    store.feedbackInboxShowsReports = true
    let before = [raItem(id: "r1", adminNote: "원래 메모")]
    store.reportAdminList = before
    store.reportAdminLoaded = true
    store.toggleReportExpansion("r1")
    store.reportNoteDraft = "새 메모"
    ReportAdminURLProtocol.set(
        .init(status: 400, body: #"{"code":"P0001","message":"REPORT_FORBIDDEN","details":null,"hint":null}"#),
        host: host, path: raUpdatePath
    )

    store.applyReportStatus(id: "r1", status: .done)
    await raWait { store.reportAdminNotice != nil }

    #expect(store.reportAdminList == before, "거절됐는데 목록이 바뀌었다")
    #expect(store.reportAdminNotice == ReportAdminText.forbidden)
    #expect(!(store.reportAdminNotice ?? "").uppercased().contains("REPORT"), "서버 예외 이름이 화면으로 샜다")
    #expect(store.reportNoteDraft == "새 메모", "실패했는데 쓰던 메모를 지웠다")
    #expect(store.canUpdateReport, "실패했는데 잠금이 안 풀렸다 — 다시 누를 수 없다")
    #expect(ReportAdminURLProtocol.count(host: host, path: raListPath) == 0, "실패했는데 재조회했다")
}

// MARK: - 스토어: 늦은 응답

@MainActor
@Test
func 늦게_도착한_옛_목록은_새_목록을_덮지_않는다() async {
    let host = "ra-store-late-list"
    let store = raStore(host: host)
    store.feedbackShowsInbox = true
    store.feedbackInboxShowsReports = true
    ReportAdminURLProtocol.hold(host: host, path: raListPath)

    // ① 첫 조회가 떠 있다(패널 열기).
    store.loadReportAdmin()
    await raWait { ReportAdminURLProtocol.heldCount(host: host, path: raListPath) == 1 }
    // ② 두 번째 조회(처리 성공 뒤 재조회 자리)가 나가고 **먼저** 답을 받는다.
    store.loadReportAdmin()
    await raWait { ReportAdminURLProtocol.heldCount(host: host, path: raListPath) == 2 }
    ReportAdminURLProtocol.release(host: host, path: raListPath, index: 1,
                                   with: .init(body: raList(raRowJSON(id: "new", status: "done"))))
    await raWait { store.reportAdminList.map(\.id) == ["new"] }
    #expect(store.reportAdminList.map(\.id) == ["new"])

    // ③ 옛 조회가 이제야 도착한다 — 반영하면 방금 저장한 처리가 화면에서 되돌아간다.
    ReportAdminURLProtocol.release(host: host, path: raListPath, index: 0,
                                   with: .init(body: raList(raRowJSON(id: "new", status: "open"), raRowJSON(id: "old"))))
    await raWait { false }
    #expect(store.reportAdminList.map(\.id) == ["new"], "늦게 온 옛 목록이 새 목록을 덮었다")
    #expect(store.reportAdminList.first?.status == .done)
    #expect(!store.reportAdminLoading, "옛 응답이 로딩 깃발을 다시 세웠거나 안 내렸다")
}

@MainActor
@Test
func 로그아웃_뒤에_도착한_신고는_다음_계정_화면에_남지_않는다() async {
    let host = "ra-store-late-logout"
    let store = raStore(host: host)
    store.feedbackShowsInbox = true
    store.feedbackInboxShowsReports = true
    ReportAdminURLProtocol.hold(host: host, path: raListPath)
    ReportAdminURLProtocol.hold(host: host, path: raCountPath)
    store.loadReportAdmin()
    store.refreshReportOpenCount()
    await raWait {
        ReportAdminURLProtocol.heldCount(host: host, path: raListPath) == 1
            && ReportAdminURLProtocol.heldCount(host: host, path: raCountPath) == 1
    }

    store.signOut()
    ReportAdminURLProtocol.release(host: host, path: raListPath, with: .init(body: raList(raRowJSON(id: "someone-elses"))))
    ReportAdminURLProtocol.release(host: host, path: raCountPath, with: .init(body: "9"))
    await raWait { false }

    #expect(store.reportAdminList.isEmpty, "로그아웃 뒤 도착한 신고가 남았다 — 남이 쓴 글이 다음 사람 화면에 그려진다")
    #expect(store.reportOpenCount == 0, "로그아웃 뒤 도착한 건수가 메뉴바 점을 켰다")
    #expect(!store.feedbackInboxShowsReports && !store.showsReportAdmin)
}

@MainActor
@Test
func 관리자_깃발이_내려간_뒤_도착한_건수는_메뉴바_점을_다시_켜지_않는다() async {
    let host = "ra-store-late-flag"
    let store = raStore(host: host)
    store.reportOpenCount = 3
    ReportAdminURLProtocol.hold(host: host, path: raCountPath)
    store.refreshReportOpenCount()
    await raWait { ReportAdminURLProtocol.heldCount(host: host, path: raCountPath) == 1 }

    store.ultraUnlimited = false
    #expect(store.reportOpenCount == 0, "관리자 깃발이 내려갔는데 신고 건수가 남았다 — 열 수 없는 화면의 점이 뜬다")
    ReportAdminURLProtocol.release(host: host, path: raCountPath, with: .init(body: "5"))
    await raWait { false }
    #expect(store.reportOpenCount == 0, "깃발이 내려간 뒤 도착한 건수가 점을 다시 켰다")
    #expect(store.adminInboxOpenCount == 0)
}

// MARK: - 스토어: 비운영자에게는 표면이 없다

@MainActor
@Test
func 비운영자에게는_신고_표면도_요청도_없다() async {
    let host = "ra-store-nonadmin"
    let store = raStore(host: host, admin: false)
    ReportAdminURLProtocol.set(.init(body: "7"), host: host, path: raCountPath)
    ReportAdminURLProtocol.set(.init(body: raList(raRowJSON(id: "r1"))), host: host, path: raListPath)

    // 칸을 고르려 해도 문이 잠겨 있다(뷰가 칩을 안 그리지만 두 겹이다).
    store.feedbackShowsInbox = true
    store.selectInboxSegment(reports: true)
    #expect(!store.feedbackInboxShowsReports && !store.showsReportAdmin)
    // 낡은 선택이 남아 있어도(로그아웃 직전 운영자였다) 곱이라 그려지지 않는다.
    store.feedbackInboxShowsReports = true
    #expect(!store.showsReportAdmin, "관리자가 아닌데 신고 칸이 그려진다")

    // 팝오버 열기 · 패널 열기 · 직접 호출 — 어느 길로도 신고 RPC 가 나가지 않는다(40명이 매번 0 을 받으러 가지 않게).
    store.setMenuPresented(true)
    store.openFeedbackPanel()
    store.refreshReportOpenCount()
    store.loadReportAdmin()
    store.applyReportStatus(id: "r1", status: .done)
    await raWait { false }
    for path in [raListPath, raUpdatePath, raCountPath] {
        #expect(ReportAdminURLProtocol.count(host: host, path: path) == 0, "비운영자가 \(path) 를 불렀다")
    }
    #expect(store.reportOpenCount == 0 && store.reportAdminList.isEmpty)
    #expect(CheckFeedbackView.visibleTabs(isAdmin: false) == [.send], "받은 제보 탭(신고 칸의 유일한 문)이 비운영자에게 생겼다")
}

@MainActor
@Test
func 운영자는_팝오버를_열_때_신고_건수만_한_번_묻고_제보_왕복은_그대로다() async {
    let host = "ra-store-popover"
    let store = raStore(host: host)
    ReportAdminURLProtocol.set(.init(body: "2"), host: host, path: raCountPath)

    store.setMenuPresented(true)
    await raWait { store.reportOpenCount == 2 }
    #expect(store.reportOpenCount == 2)
    #expect(ReportAdminURLProtocol.count(host: host, path: raCountPath) == 1, "팝오버 한 번에 건수 조회가 여러 번 나갔다")
    #expect(ReportAdminURLProtocol.count(host: host, path: raListPath) == 0, "팝오버를 열었다고 신고 목록까지 받았다")
    // 제보 쪽은 팝오버 열기에서 예전처럼 건수·목록을 묻지 않는다(제보 동작은 한 걸음도 안 바뀐다).
    #expect(ReportAdminURLProtocol.count(host: host, path: "/rest/v1/rpc/feedback_open_count") == 0)
    #expect(ReportAdminURLProtocol.count(host: host, path: "/rest/v1/rpc/feedback_list") == 0)

    // [제보] 칸(기본)에서 패널을 열면 제보 왕복만 예전 그대로 나가고 신고 목록은 안 나간다.
    store.openFeedbackPanel()
    store.feedbackShowsInbox = true
    await raWait { store.feedbackLoaded }
    await raWait { false }
    #expect(ReportAdminURLProtocol.count(host: host, path: "/rest/v1/rpc/feedback_list") == 1)
    #expect(ReportAdminURLProtocol.count(host: host, path: "/rest/v1/rpc/feedback_open_count") == 1)
    #expect(ReportAdminURLProtocol.count(host: host, path: raListPath) == 0, "[제보] 칸인데 신고 목록을 받았다")
    #expect(!store.showsReportAdmin, "기본 칸이 [제보]가 아니다 — 받은 제보 탭을 여는 사람이 보던 화면이 바뀌었다")
}

@MainActor
@Test
func 팝오버를_안_열어도_폴링이_운영자의_신고_건수를_5분에_한_번_물어_메뉴바_점을_켠다() async {
    // 팝오버를 연 순간에만 물으면, 10:00 에 0건을 본 운영자는 10:05 에 들어온 신고를 다음에 팝오버를 직접 열 때까지 모른다
    // (자동 시작을 켜 두고 팝오버를 안 여는 날은 하루 종일). 기존 15초 폴링 tick 에 지갑 sync 와 같은 5분 스로틀로 얹는다.
    // 근무 여부와 무관하다 — 이 테스트는 근무 밖(startedAt == nil)에서 돈다.
    let host = "ra-store-poll"
    let store = raStore(host: host)
    let base = Date(timeIntervalSince1970: 1_789_000_000)
    var now = base
    store.clock = { now }
    ReportAdminURLProtocol.set(.init(body: "3"), host: host, path: raCountPath)
    #expect(store.startedAt == nil)

    await store.localExpiryTick()
    await raWait { store.reportOpenCount == 3 }
    #expect(store.reportOpenCount == 3, "팝오버를 안 연 운영자에게 새 신고가 메뉴바 점을 못 켰다")
    let label = MenuBarStatusLabel(
        snapshot: WorkStatusSnapshot(status: .offWork, elapsedSeconds: 0), title: "오프",
        hasOpenReports: store.reportOpenCount > 0
    )
    #expect(label.dotReasons.openReports)
    #expect(ReportAdminURLProtocol.count(host: host, path: raCountPath) == 1)

    // 5분 안의 tick 은 묻지 않는다(15초마다 묻지 않는다 — 무료 플랜).
    now = base.addingTimeInterval(WorkTimerStore.ultraWalletSyncThrottleSeconds - 1)
    await store.localExpiryTick()
    await raWait { false }
    #expect(ReportAdminURLProtocol.count(host: host, path: raCountPath) == 1, "5분 스로틀 안에서 건수를 다시 물었다")

    // 5분이 지나면 다시 묻는다 — 처리가 끝나 0 이 되면 점이 꺼지는 것도 같은 길이다.
    ReportAdminURLProtocol.set(.init(body: "0"), host: host, path: raCountPath)
    now = base.addingTimeInterval(WorkTimerStore.ultraWalletSyncThrottleSeconds)
    await store.localExpiryTick()
    await raWait { store.reportOpenCount == 0 }
    #expect(ReportAdminURLProtocol.count(host: host, path: raCountPath) == 2)
    #expect(store.reportOpenCount == 0)
    // 목록은 폴링하지 않는다(건수 한 줄만 — 사람이 쓴 글을 5분마다 내려받을 이유가 없다).
    #expect(ReportAdminURLProtocol.count(host: host, path: raListPath) == 0)

    // 비운영자는 폴링 tick 에서도 묻지 않는다(40명이 5분마다 0 을 받으러 가지 않게).
    let otherHost = "ra-store-poll-nonadmin"
    let other = raStore(host: otherHost, admin: false)
    other.clock = { now }
    await other.localExpiryTick()
    await raWait { false }
    #expect(ReportAdminURLProtocol.count(host: otherHost, path: raCountPath) == 0, "비운영자가 폴링 tick 에서 신고 건수를 물었다")
}

@MainActor
@Test
func 신고_칸이_골라진_채_패널을_다시_열면_신고_목록을_새로_받는다() async {
    // 제보 목록이 "패널 열기 = 새로 받기"인 것과 같은 규약. [뒤로] → [제보] 가 최신을 보는 길이다(새로고침 버튼은 없다).
    let host = "ra-store-reopen"
    let store = raStore(host: host)
    ReportAdminURLProtocol.set(.init(body: raList(raRowJSON(id: "r1"))), host: host, path: raListPath)
    store.feedbackShowsInbox = true
    store.selectInboxSegment(reports: true)
    await raWait { store.reportAdminLoaded }
    store.closeFeedbackPanel()
    ReportAdminURLProtocol.set(.init(body: raList(raRowJSON(id: "r1"), raRowJSON(id: "r2"))), host: host, path: raListPath)

    store.openFeedbackPanel()
    await raWait { store.reportAdminList.count == 2 }
    #expect(store.reportAdminList.count == 2, "패널을 다시 열었는데 신고 목록이 낡은 채다")
    #expect(ReportAdminURLProtocol.count(host: host, path: raListPath) == 2)
    #expect(store.showsReportAdmin, "패널을 닫았다 열었더니 고른 칸이 풀렸다")
}

@MainActor
@Test
func 로그아웃은_신고_칸의_모든_값을_비운다() {
    let store = raStore(host: "ra-store-signout")
    store.feedbackShowsInbox = true
    store.feedbackInboxShowsReports = true
    store.reportAdminList = [raItem(id: "r1")]
    store.reportAdminLoaded = true
    store.reportAdminNotice = ReportAdminText.saved(.done)
    store.reportFilter = .done
    store.expandedReportID = "r1"
    store.reportNoteDraft = "메모"
    store.reportUpdatingID = "r1"
    store.reportOpenCount = 4

    store.signOut()

    #expect(store.reportAdminList.isEmpty && !store.reportAdminLoaded && store.reportAdminNotice == nil)
    #expect(store.reportFilter == nil && store.expandedReportID == nil && store.reportNoteDraft.isEmpty)
    #expect(store.reportUpdatingID == nil && store.reportOpenCount == 0 && !store.feedbackInboxShowsReports)
}

// MARK: - 메뉴바 점 · 레일 배지

@MainActor
@Test
func 열린_신고는_기존_메뉴바_점과_레일_배지에_합쳐진다() throws {
    typealias R = MenuBarDotReasons
    #expect(R(openReports: true).accessibilityDescription == "처리할 신고")
    #expect(!R(openReports: true).isEmpty)
    #expect(R(unreadMessages: true, gomokuInvite: true, updateAvailable: true, openReports: true).accessibilityDescription
            == "새 메시지 · 오목 신청 · 처리할 신고 · 업데이트 있음", "사유 순서가 급한 것부터가 아니다")
    // 예전 세 사유만 켠 조합은 문구가 한 글자도 안 바뀐다.
    #expect(R(unreadMessages: true, gomokuInvite: true, updateAvailable: true).accessibilityDescription
            == "새 메시지 · 오목 신청 · 업데이트 있음")
    let label = MenuBarStatusLabel(
        snapshot: WorkStatusSnapshot(status: .offWork, elapsedSeconds: 0), title: "오프", hasOpenReports: true
    )
    #expect(label.dotReasons == R(openReports: true))

    // 배선: 앱이 스토어의 신고 건수를 라벨에 넘긴다(판정 없이 건수만 — 건수는 서버가 운영자에게만 준다).
    let app = raStripSwiftComments(try raSource("CheckApp.swift"))
    #expect(app.contains("hasOpenReports: appDelegate.store.reportOpenCount > 0"), "메뉴바 라벨이 열린 신고를 안 읽는다")
    #expect(!app.contains("ultraUnlimited"), "메뉴바 배선이 클라 관리자 깃발로 판정한다")
    // 레일 [제보] 배지와 받은 제보 탭 배지는 **같은 합**을 읽는다(새 배지를 만들지 않는다).
    let menu = raStripSwiftComments(try raSource("CheckMenuView.swift"))
    let rail = try #require(raStructBody(menu, name: "CheckMenuSideRail"))
    #expect(rail.contains("let count = store.adminInboxOpenCount"), "레일 배지가 신고를 안 합친다")
    #expect(!rail.contains("ultraUnlimited"), "레일 배지가 클라 관리자 깃발로 판정한다")
    let panel = raStripSwiftComments(try raSource("CheckFeedbackView.swift"))
    #expect(panel.contains("badge: tab == .inbox ? store.adminInboxOpenCount : 0"), "받은 제보 탭 배지가 신고를 안 합친다")

    let store = raStore(host: "ra-badge")
    store.feedbackOpenCount = 2
    store.reportOpenCount = 1
    #expect(store.adminInboxOpenCount == 3)
}

/// `//` · `/* */` 주석을 걷어낸다(문자열 리터럴 안의 `//` 는 남긴다 — 하우스 규칙: 설명을 지워야만 초록이 되는 테스트 금지).
private func raStripSwiftComments(_ source: String) -> String {
    var out = ""
    var inString = false, inLine = false, inBlock = false, escaped = false
    let chars = Array(source)
    var i = 0
    while i < chars.count {
        let c = chars[i]
        let next: Character? = i + 1 < chars.count ? chars[i + 1] : nil
        if inLine {
            if c == "\n" { inLine = false; out.append(c) }
        } else if inBlock {
            if c == "*", next == "/" { inBlock = false; i += 1 }
        } else if inString {
            out.append(c)
            if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { inString = false }
        } else if c == "/", next == "/" {
            inLine = true; i += 1
        } else if c == "/", next == "*" {
            inBlock = true; i += 1
        } else {
            if c == "\"" { inString = true }
            out.append(c)
        }
        i += 1
    }
    return out
}

/// `struct <name>` 선언의 본문(중괄호 짝을 센다). 없으면 nil.
private func raStructBody(_ source: String, name: String) -> String? {
    guard let head = source.range(of: "struct \(name)") else { return nil }
    guard let open = source[head.upperBound...].firstIndex(of: "{") else { return nil }
    var depth = 0
    var index = open
    while index < source.endIndex {
        let character = source[index]
        if character == "{" { depth += 1 }
        if character == "}" {
            depth -= 1
            if depth == 0 { return String(source[open...index]) }
        }
        index = source.index(after: index)
    }
    return nil
}

private func raSource(_ name: String) throws -> String {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Sources/check/\(name)")
    return try String(contentsOf: url, encoding: .utf8)
}

// MARK: - 렌더

private enum RARenderError: Error { case failed }
private let raRenderNow = Date(timeIntervalSince1970: 1_789_000_000)

@MainActor
private func raBitmap<Content: View>(_ view: Content) throws -> NSBitmapImageRep {
    let renderer = ImageRenderer(content: view)
    renderer.scale = 2
    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff)
    else { throw RARenderError.failed }
    return bitmap
}

/// 행 하나를 패널 폭(292pt)으로 그린다.
@MainActor
private func raRowBitmap(_ item: ContentReportAdminItem, expanded: Bool = false) throws -> NSBitmapImageRep {
    try raBitmap(
        ReportAdminRow(
            report: item, now: raRenderNow, isExpanded: expanded, note: .constant(item.adminNote ?? ""),
            rendersPlainNoteField: true, onToggle: {}, onStatus: { _ in }
        )
        .frame(width: FeedbackPanelLayout.contentWidth)
        .padding(12)
        .background(CheckTheme.background)
    )
}

/// 경고색(`CheckTheme.danger` 계열) 픽셀 수 — **빨강만 세다**. 호박색(미해결 칩 · `pending`)은 초록 성분이 커서 빠진다
/// (첫 판은 빨강 우세만 봐서 호박색까지 셌다). 인용 막대는 `danger`(1.0, 0.45, 0.46) 75% 가 어두운 판 위에 앉은 색이다.
private func raDangerPixels(_ bitmap: NSBitmapImageRep, xRange: Range<Int>? = nil) -> Int {
    var count = 0
    let columns = xRange.map { max(0, $0.lowerBound)..<min(bitmap.pixelsWide, $0.upperBound) } ?? 0..<bitmap.pixelsWide
    for y in 0..<bitmap.pixelsHigh {
        for x in columns {
            guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
            if color.redComponent > 0.55, color.greenComponent < 0.45, color.blueComponent < 0.45 {
                count += 1
            }
        }
    }
    return count
}

@MainActor
@Test
func 신고_행은_원문을_인용_판으로_그리고_사람_신고는_판이_없다() throws {
    let message = raItem(id: "m", messageBody: "샘플 메시지 원문 — " + String(repeating: "가나다라마바사 ", count: 12))
    let person = raItem(id: "p", messageBody: nil)
    let messageBitmap = try raRowBitmap(message)
    let personBitmap = try raRowBitmap(person)
    FeedbackSnapshots.save(messageBitmap, name: "panels-report-row-message.png")
    FeedbackSnapshots.save(personBitmap, name: "panels-report-row-person.png")

    // 원문 판은 **높이를 먹는다**(접힌 행에서도 3줄까지 보인다) — 안 그려졌으면 두 행 높이가 같다.
    let quoteExtra = Double(messageBitmap.pixelsHigh - personBitmap.pixelsHigh) / 2
    #expect(quoteExtra >= 40, "메시지 신고 행이 사람 신고 행보다 \(quoteExtra)pt 만 크다 — 원문 판이 안 그려졌다")
    // 인용 판 **그 자체**: 왼쪽 가장자리의 경고색 막대가 원문을 다른 글과 가른다. 같은 글을 처리 메모 판(막대 없음)에
    // 담아 대조한다 — 판 하나만 그려서 보면 아바타·사유 배지 같은 다른 경고색과 막대를 가를 수 없다.
    let quote = try raBitmap(ReportQuoteBlock(text: "샘플 메시지 원문", isExpanded: false)
        .frame(width: FeedbackPanelLayout.contentWidth - 16).background(CheckTheme.background))
    let plain = try raBitmap(ReportNoteBlock(note: "샘플 메시지 원문", at: nil, now: raRenderNow)
        .frame(width: FeedbackPanelLayout.contentWidth - 16).background(CheckTheme.background))
    FeedbackSnapshots.save(quote, name: "panels-report-quote.png")
    let bar = 0..<(6 * 2)   // 판 왼쪽 6pt(@2x) — 막대(3pt)가 서는 띠
    #expect(raDangerPixels(quote, xRange: bar) > 20, "신고된 메시지 원문 판에 인용 막대(경고색)가 안 그려졌다")
    #expect(raDangerPixels(plain, xRange: bar) == 0, "대조군(메모 판)에 경고색이 있다 — 이 측정이 막대를 가르지 못한다")
    #expect(quote.pixelsHigh > plain.pixelsHigh || quote.pixelsHigh == plain.pixelsHigh,
            "인용 판이 이름표 줄을 잃었다")

    // 추정 높이는 **큰 쪽**이어야 한다(과소평가는 잘림 — FeedbackPanelLayout 규약).
    for (item, bitmap) in [(message, messageBitmap), (person, personBitmap)] {
        let natural = Double(bitmap.pixelsHigh) / 2 - 24
        #expect(Double(ReportAdminLayout.rowHeight(item, expanded: false)) >= natural - 1,
                "행 높이 추정(\(ReportAdminLayout.rowHeight(item, expanded: false)))이 실제(\(natural))보다 작다 — 목록이 잘린다")
    }
    let expanded = try raRowBitmap(message, expanded: true)
    FeedbackSnapshots.save(expanded, name: "panels-report-row-expanded.png")
    #expect(Double(ReportAdminLayout.rowHeight(message, expanded: true)) >= Double(expanded.pixelsHigh) / 2 - 24 - 1,
            "펼친 행 높이 추정이 실제보다 작다")
    #expect(ReportAdminRow.accessibilitySummary(message) == "신고자m님이 대상m님을 신고 — 욕설·괴롭힘 · 미해결")
}

/// 받은 제보 탭의 [신고] 칸이 열린 **메인 화면** 스토어.
@MainActor
private func raMenuStore(host: String, rows: Int, function: String = #function) -> WorkTimerStore {
    let store = raStore(host: host, function: function)
    store.isMenuPresented = true
    store.displayNow = raRenderNow
    store.currentTeamID = URLProtocolStub.stubTeamID
    store.teamName = "아잉팀"
    store.snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 3_600)
    store.startedAt = raRenderNow.addingTimeInterval(-3_600)
    store.isFeedbackPanelVisible = true
    store.feedbackShowsInbox = true
    store.feedbackInboxShowsReports = true
    let statuses: [ContentReportStatus] = [.open, .open, .inProgress, .done, .held]
    store.reportAdminList = (0..<rows).map { index in
        raItem(
            id: "r\(index)",
            status: statuses[index % statuses.count],
            reporterID: index == 2 ? nil : "u-\(index)",
            reason: ["spam", "harassment", "inappropriate", "other"][index % 4],
            detail: index % 3 == 0 ? nil : "샘플 상세 \(index) — " + String(repeating: "가나다라 ", count: 10),
            messageBody: index % 2 == 0 ? "샘플 메시지 원문 \(index) — " + String(repeating: "가나다라마바사 ", count: 9) : nil,
            adminNote: index == 1 ? "샘플 처리 메모" : nil,
            createdAt: raRenderNow.addingTimeInterval(-Double(index) * 5_000),
            handledAt: index == 1 ? raRenderNow.addingTimeInterval(-600) : nil
        )
    }.sortedForReportList()
    store.reportAdminLoaded = true
    store.reportOpenCount = store.reportAdminList.filter { $0.status.isOpen }.count
    return store
}

private let raWorstNotes = [
    "내 기록 패널에 근무 리듬·지난주 회고 추가",
    "AI 토큰 순위를 지난달까지 넘겨봐요",
    "맥을 여러 대 써도 토큰이 합산돼요",
    "자리 비움으로 자동 종료된 근무를 되돌릴 수 있어요 — 폭을 넘는 아주 긴 문구"
]

@MainActor
private func raPanelBitmap(_ store: WorkTimerStore, worstChrome: Bool = false) throws -> NSBitmapImageRep {
    try raBitmap(CheckMenuView(
        store: store,
        previewClipsOverflowList: true,
        previewGoalEditing: worstChrome,
        previewUpdateBanner: worstChrome,
        previewUpdateNotes: worstChrome ? raWorstNotes : [],
        previewPlainTextEditors: true
    ))
}

@MainActor
@Test
func 신고_칸은_팝오버_안에서_최악_조합에도_700pt_를_넘지_않는다() throws {
    // 보통 화면: 행 셋.
    let plain = raMenuStore(host: "ra-render-plain", rows: 3)
    let plainBitmap = try raPanelBitmap(plain)
    FeedbackSnapshots.save(plainBitmap, name: "panels-report-inbox.png")
    #expect(Double(plainBitmap.pixelsHigh) / 2 <= 700, "신고 칸 보통 화면이 700pt 를 넘었다")

    // 최악: 행 12 · 하나 펼침(긴 메모) · 안내 한 줄 · 배너+패치노트 4줄+목표 편집(241pt).
    let worst = raMenuStore(host: "ra-render-worst", rows: 12)
    worst.expandedReportID = "r0"
    worst.reportNoteDraft = "샘플 메모"
    worst.reportAdminNotice = ReportAdminText.noteTooLong
    let worstBitmap = try raPanelBitmap(worst, worstChrome: true)
    FeedbackSnapshots.save(worstBitmap, name: "panels-report-inbox-tallest.png")
    let height = Double(worstBitmap.pixelsHigh) / 2
    #expect(height <= 700, "신고 칸 최악 조합이 \(height)pt — 푸터(로그아웃·종료)가 화면 밖으로 잘린다")

    // 같은 스토어를 [제보] 칸으로 돌리면 그림이 달라야 한다(칸 전환이 실제로 화면을 바꾼다).
    worst.feedbackInboxShowsReports = false
    let feedbackBitmap = try raPanelBitmap(worst, worstChrome: true)
    #expect(Double(feedbackBitmap.pixelsHigh) / 2 <= 700, "칩 줄이 더해진 [제보] 칸 최악 조합이 700pt 를 넘었다")
    var differs = feedbackBitmap.pixelsHigh != worstBitmap.pixelsHigh
    if !differs {
        outer: for y in stride(from: 0, to: worstBitmap.pixelsHigh, by: 6) {
            for x in stride(from: 0, to: worstBitmap.pixelsWide, by: 6)
            where worstBitmap.colorAt(x: x, y: y) != feedbackBitmap.colorAt(x: x, y: y) {
                differs = true
                break outer
            }
        }
    }
    #expect(differs, "[신고] 칸과 [제보] 칸이 똑같이 그려졌다")

    // 비운영자: 같은 낡은 선택이 남아 있어도 받은 제보 탭(= 신고 칸) 자체가 없다.
    let user = raMenuStore(host: "ra-render-user", rows: 3)
    user.ultraUnlimited = false
    #expect(!user.showsFeedbackInbox && !user.showsReportAdmin)
    let userBitmap = try raPanelBitmap(user)
    FeedbackSnapshots.save(userBitmap, name: "panels-report-nonadmin.png")
    var userDiffers = userBitmap.pixelsHigh != plainBitmap.pixelsHigh
    if !userDiffers {
        outer: for y in stride(from: 0, to: plainBitmap.pixelsHigh, by: 6) {
            for x in stride(from: 0, to: plainBitmap.pixelsWide, by: 6)
            where plainBitmap.colorAt(x: x, y: y) != userBitmap.colorAt(x: x, y: y) {
                userDiffers = true
                break outer
            }
        }
    }
    #expect(userDiffers, "비운영자 화면이 운영자의 신고 칸과 똑같이 그려졌다")
}

// ── 점을 보고 들어온 운영자가 낡은 목록을 본다(2026-09-20 재검증 medium) ─────────────────────────────
//
// 평소 흐름: 운영자가 [신고] 칸을 보다가 팝오버를 닫는다(칸 선택은 스토어에 남는다) → 새 신고가 5분 폴링으로 점을 켠다 →
// 점을 보고 팝오버를 연다. 예전에는 여는 순간 **건수만** 다시 묻고 목록은 안 받아서, 알림을 따라 들어온 바로 그 화면이
// "받은 신고가 없어요"(또는 어제 처리한 행만)를 말했다. 켜진 [신고] 칩을 다시 눌러도 guard 에서 빠져 요청이 0건이었다.
@MainActor
@Test
func 점을_보고_팝오버를_열면_신고_칸이_새_목록을_받는다() async throws {
    // host 는 테스트마다 달라야 한다 — 요청 수 스텁이 host 로 갈린다(같은 이름을 쓰면 병렬로 도는 테스트끼리 수를 나눠 가진다).
    let host = "ra-store-dot-reopen"
    let store = raStore(host: host)
    ReportAdminURLProtocol.set(.init(body: raList(
        raRowJSON(id: "old-done", status: "done", createdAt: "2026-09-19T08:00:00+00:00")
    )), host: host, path: raListPath)
    ReportAdminURLProtocol.set(.init(body: "0"), host: host, path: raCountPath)
    store.feedbackShowsInbox = true
    store.selectInboxSegment(reports: true)
    await raWait { store.reportAdminLoaded }
    #expect(store.visibleReports.map(\.id) == ["old-done"])

    // 팝오버를 닫은 사이 새 신고가 들어왔다.
    store.setMenuPresented(false)
    ReportAdminURLProtocol.set(.init(body: raList(
        raRowJSON(id: "new-open", createdAt: "2026-09-20T09:00:00+00:00"),
        raRowJSON(id: "old-done", status: "done", createdAt: "2026-09-19T08:00:00+00:00")
    )), host: host, path: raListPath)
    ReportAdminURLProtocol.set(.init(body: "1"), host: host, path: raCountPath)

    // 점을 보고 다시 연다 — [신고] 칸이 골라져 있으면 목록부터 새로 받는다.
    store.setMenuPresented(true)
    await raWait { store.visibleReports.first?.id == "new-open" }
    #expect(store.visibleReports.map(\.id) == ["new-open", "old-done"], "알림을 따라 들어온 화면이 새 신고를 안 보인다")
    #expect(ReportAdminURLProtocol.count(host: host, path: raListPath) == 2)

    // 켜진 [신고] 칩을 다시 누르면 새로 받는다(당겨서 새로고침이 없는 표면의 유일한 손잡이다).
    store.selectInboxSegment(reports: true)
    await raWait { ReportAdminURLProtocol.count(host: host, path: raListPath) == 3 }
    #expect(ReportAdminURLProtocol.count(host: host, path: raListPath) == 3, "켜진 [신고] 칩 재탭이 조회를 내지 않았다")

    // [신고] 칸이 아니면 팝오버를 열어도 목록을 받지 않는다(제보 칸의 왕복 수는 그대로).
    store.selectInboxSegment(reports: false)
    store.setMenuPresented(false)
    store.setMenuPresented(true)
    await raWait { false }
    #expect(ReportAdminURLProtocol.count(host: host, path: raListPath) == 3, "[제보] 칸인데 신고 목록을 받았다")
}
