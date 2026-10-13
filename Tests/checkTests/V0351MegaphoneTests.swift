import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// v0.3.51 확성기(📢) — 코어(전선 모양 · 결과 접기 · 본문 규칙 · 문구) + 맥 배선(상점 작성기 · 2단 확인 · 요청 id · 잔량 · 예산).
//
// 서버 행동은 하네스가 증명했다(V0351MegaphoneMigrationTests 머리말). 여기서는 **클라가 그 계약을 지키는가**를 잰다:
//   ① 한 작성 = 요청 id 하나 · 전송 중 두 번째 요청 없음 · 연결 오류 뒤 재시도는 **같은 id**(이중 과금이 원리적으로 없다)
//   ② 확인 단계를 지나야만 요청이 나간다(첫 [보내기] 는 요청을 안 낸다)
//   ③ 거절 문구는 서버 숫자로 · 잔량은 서버 값으로만
//   ④ 작성기는 상점 팝오버 700pt 예산을 안 깬다(렌더로 잰다)
// 실네트워크 없음 — 전부 호스트별 스텁(`MegaphoneStubProtocol`)이다.

// MARK: - 스텁 서버

final class MegaphoneStubProtocol: URLProtocol, @unchecked Sendable {
    struct Request: Sendable {
        let path: String
        let body: String
        var rpc: String { path.replacingOccurrences(of: "/rest/v1/rpc/", with: "") }
        var json: [String: Any] {
            (try? JSONSerialization.jsonObject(with: Data(body.utf8))) as? [String: Any] ?? [:]
        }
    }

    enum Reply: Sendable {
        case json(Int, String)
        case fail(URLError.Code)
    }

    typealias Responder = @Sendable (Request) -> Reply

    private static let lock = NSLock()
    private nonisolated(unsafe) static var responders: [String: Responder] = [:]
    private nonisolated(unsafe) static var recorded: [String: [Request]] = [:]

    static func register(host: String, _ responder: @escaping Responder) {
        lock.lock(); defer { lock.unlock() }
        responders[host] = responder
        recorded[host] = []
    }

    static func records(host: String) -> [Request] {
        lock.lock(); defer { lock.unlock() }
        return recorded[host] ?? []
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MegaphoneStubProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    private static func bodyText(_ request: URLRequest) -> String {
        if let body = request.httpBody { return String(decoding: body, as: UTF8.self) }
        guard let stream = request.httpBodyStream else { return "" }
        stream.open(); defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count)
            guard n > 0 else { break }
            data.append(buffer, count: n)
        }
        return String(decoding: data, as: UTF8.self)
    }

    override func startLoading() {
        let host = request.url?.host ?? ""
        let record = Request(path: request.url?.path ?? "", body: Self.bodyText(request))
        let responder: Responder? = {
            Self.lock.lock(); defer { Self.lock.unlock() }
            Self.recorded[host, default: []].append(record)
            return Self.responders[host]
        }()
        switch responder?(record) ?? .json(599, #"{"message":"no stub"}"#) {
        case .fail(let code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        case .json(let status, let text):
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                           headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(text.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}

/// 정보 응답(서버 모양 그대로).
private func infoJSON(recipients: Int = 12, cooldown: Int = 0, enabled: Bool = true, ruby: Int? = 120) -> String {
    var text = #"{"status":"ok","enabled":\#(enabled),"price":50,"cooldown_seconds":600,"cooldown_remaining_seconds":\#(cooldown),"#
        + #""recipients":\#(recipients),"max_length":198"#
    if let ruby { text += #","ruby_balance":\#(ruby)"# }
    return text + "}"
}

private let missingFunction = #"{"code":"PGRST202","message":"Could not find the function public.send_megaphone in the schema cache"}"#

// MARK: - 코어

@Suite struct V0351MegaphoneCoreTests {
    @Test("요청 본문: rpc/send_megaphone · 키 둘(p_body 정규화 · p_request_id) · 표식은 서버가 붙인다")
    func requestShape() async throws {
        let host = "mega-core-request"
        MegaphoneStubProtocol.register(host: host) { _ in .json(200, #"{"status":"ok","recipients":3,"ruby_balance":10,"duplicate":false}"#) }
        let service = SupabaseWorkService(projectURL: URL(string: "http://\(host)")!, anonKey: "anon",
                                          session: MegaphoneStubProtocol.session())
        // NFD 한글 + 앞뒤 공백 → NFC · trim 해서 보낸다(서버와 같은 눈금).
        let nfd = "  \u{1112}\u{1161}\u{11AB}\u{1100}\u{1173}\u{11AF}  "
        let response = try await service.sendMegaphone(accessToken: "t", body: nfd, requestID: "req-1")
        #expect(response.status == "ok" && response.recipients == 3 && response.rubyBalance == 10)
        let record = try #require(MegaphoneStubProtocol.records(host: host).first)
        #expect(record.path == "/rest/v1/rpc/send_megaphone")
        #expect(Set(record.json.keys) == ["p_body", "p_request_id"])
        #expect(record.json["p_body"] as? String == "한글")
        #expect(record.json["p_request_id"] as? String == "req-1")
        #expect(!(record.json["p_body"] as? String ?? "").hasPrefix("\u{1F4E2}"), "클라가 표식을 붙였다 — 서버가 한 번 더 붙이면 📢 📢")
    }

    @Test("빈 글 · 199자는 요청을 내지 않고 서버와 같은 status 로 즉답한다")
    func localRejectionsDoNotHitTheNetwork() async throws {
        let host = "mega-core-local"
        MegaphoneStubProtocol.register(host: host) { _ in .json(200, #"{"status":"ok"}"#) }
        let service = SupabaseWorkService(projectURL: URL(string: "http://\(host)")!, anonKey: "anon",
                                          session: MegaphoneStubProtocol.session())
        let empty = try await service.sendMegaphone(accessToken: "t", body: " \n\u{3164} ", requestID: "a")
        #expect(empty.status == "empty")
        let long = try await service.sendMegaphone(accessToken: "t", body: String(repeating: "가", count: 199), requestID: "b")
        #expect(long.status == "too_long" && long.maxLength == 198)
        let ok = try await service.sendMegaphone(accessToken: "t", body: String(repeating: "가", count: 198), requestID: "c")
        #expect(ok.status == "ok")
        #expect(MegaphoneStubProtocol.records(host: host).count == 1, "로컬 거절이 네트워크를 탔다")
    }

    @Test("응답 디코드: 모든 어휘 · 키 빠짐 · 모르는 status 는 failed")
    func decodeAndFold() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        func outcome(_ json: String) throws -> MegaphoneSendOutcome {
            MegaphoneSendOutcome(response: try decoder.decode(MegaphoneSendResponse.self, from: Data(json.utf8)))
        }
        #expect(try outcome(#"{"status":"ok","megaphone_id":"m","recipients":46,"price":50,"ruby_balance":70,"duplicate":false,"body":"📢 hi","ring_sent":46,"ring_failed":0}"#)
                == .sent(recipients: 46, duplicate: false))
        #expect(try outcome(#"{"status":"ok","duplicate":true,"recipients":46}"#) == .sent(recipients: 46, duplicate: true))
        #expect(try outcome(#"{"status":"insufficient","need":50,"have":20,"ruby_balance":20,"price":50,"recipients":46}"#)
                == .insufficient(need: 50, have: 20))
        #expect(try outcome(#"{"status":"cooldown","retry_after_seconds":301,"cooldown_seconds":600}"#) == .cooldown(retryAfterSeconds: 301))
        #expect(try outcome(#"{"status":"no_recipients","recipients":0}"#) == .noRecipients)
        #expect(try outcome(#"{"status":"empty","max_length":198}"#) == .empty)
        #expect(try outcome(#"{"status":"too_long","max_length":198}"#) == .tooLong(maxLength: 198))
        #expect(try outcome(#"{"status":"not_text","max_length":198}"#) == .notText)
        #expect(try outcome(#"{"status":"disabled"}"#) == .disabled)
        #expect(try outcome(#"{"status":"blackout"}"#) == .blackout)
        #expect(try outcome(#"{"status":"unauthorized"}"#) == .failed)
        #expect(try outcome(#"{"status":"no_profile"}"#) == .failed)
        #expect(try outcome(#"{"status":"something_new"}"#) == .failed)
        // throw 로 온 실패: 함수 없음만 결과를 안다(.unavailable) · 오프라인·5xx 는 모른다(nil — id 를 쥔 채 다시 묻는다).
        #expect(MegaphoneSendOutcome(error: SupabaseWorkServiceError.databaseSchemaMissing) == .unavailable)
        #expect(MegaphoneSendOutcome(error: SupabaseWorkServiceError.invalidResponse(404)) == .unavailable)
        #expect(MegaphoneSendOutcome(error: SupabaseWorkServiceError.invalidResponse(503)) == nil)
        #expect(MegaphoneSendOutcome(error: URLError(.notConnectedToInternet)) == nil)
        let info = try decoder.decode(MegaphoneInfoResponse.self, from: Data(infoJSON(recipients: 7, cooldown: 30).utf8))
        #expect(info.recipients == 7 && info.price == 50 && info.cooldownRemainingSeconds == 30 && info.maxLength == 198
                && info.rubyBalance == 120 && info.enabled == true && info.cooldownSeconds == 600)
        // 키가 하나도 없어도 디코드된다(옛 서버·장애) — 숫자는 nil 로.
        let bare = try decoder.decode(MegaphoneInfoResponse.self, from: Data("{}".utf8))
        #expect(bare.price == nil && bare.recipients == nil)
    }

    @Test("본문 규칙: 198 코드포인트 경계 · 이모지는 스칼라로 센다 · 빈 판정이 먼저")
    func bodyRules() {
        #expect(MegaphoneBody.maxLength == 198)
        #expect(MegaphoneBody.prefix.unicodeScalars.count == 2)
        if case .ok = MegaphoneBody.validate(String(repeating: "a", count: 198)) {} else { Issue.record("198자가 거절됐다") }
        #expect(MegaphoneBody.validate(String(repeating: "a", count: 199)) == .tooLong(maxLength: 198))
        // 가족 이모지 = 자소 1 · 스칼라 7. 28개 = 196 스칼라(통과) · 29개 = 203(거절).
        let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}"
        if case .ok = MegaphoneBody.validate(String(repeating: family, count: 28)) {} else { Issue.record("196 스칼라가 거절됐다") }
        #expect(MegaphoneBody.validate(String(repeating: family, count: 29)) == .tooLong(maxLength: 198))
        #expect(MegaphoneBody.validate(String(repeating: " ", count: 300)) == .empty, "공백 300자에 길이를 말하면 안 된다")
        #expect(MegaphoneBody.length("  가나  ") == 2)
    }

    @Test("문구: 쿨타임은 분으로 올림 · 부족은 상점과 같은 문장 · 서버 숫자 그대로")
    func texts() {
        #expect(MegaphoneText.cooldown(seconds: 1) == "1분 뒤에 다시 보낼 수 있어요")
        #expect(MegaphoneText.cooldown(seconds: 60) == "1분 뒤에 다시 보낼 수 있어요")
        #expect(MegaphoneText.cooldown(seconds: 61) == "2분 뒤에 다시 보낼 수 있어요")
        #expect(MegaphoneText.cooldown(seconds: 600) == "10분 뒤에 다시 보낼 수 있어요")
        #expect(MegaphoneText.shortfall(need: 50, have: 20) == "루비 30개 더 필요해요")
        #expect(MegaphoneText.shortfall(need: 50, have: 20) == CheckCoreShared.shortfallNotice(need: 50, have: 20))
        #expect(MegaphoneText.sent(recipients: 46) == "보냈어요 · 46명에게")
        #expect(MegaphoneText.reach(recipients: 46) == "지금 보내면 46명에게 가요")
        #expect(MegaphoneText.confirm(price: 50, recipients: 46) == "루비 50개로 46명에게 보낼까요?")
        #expect(MegaphoneText.noRecipients == "받을 사람이 없어요")
        #expect(MegaphoneText.unavailable == "지금은 보낼 수 없어요")
    }
}

// MARK: - 맥 배선

@MainActor
@Suite struct V0351MegaphoneMacTests {
    static func store(host: String, function: String = #function,
                      _ responder: @escaping MegaphoneStubProtocol.Responder) -> WorkTimerStore {
        MegaphoneStubProtocol.register(host: host, responder)
        let service = SupabaseWorkService(projectURL: URL(string: "http://\(host)")!, anonKey: "anon-test-key",
                                          session: MegaphoneStubProtocol.session())
        let store = WorkTimerStore(service: service,
                                   environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
                                   defaults: CheckTestScratch.defaults("mega-" + host, function: function))
        store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "me")
        store.characterDefaults = CheckTestScratch.defaults("mega-character-" + host, function: function)
        return store
    }

    @discardableResult
    static func waitUntil(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<600 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    static func sends(_ host: String) -> [MegaphoneStubProtocol.Request] {
        MegaphoneStubProtocol.records(host: host).filter { $0.rpc == "send_megaphone" }
    }

    /// 작성기를 열고 정보를 받고 글을 쓴 상태.
    static func ready(_ store: WorkTimerStore, text: String = "오늘 3시 라운지에서 간식 나눠요") async {
        store.isShopPanelVisible = true
        store.toggleMegaphoneComposer()
        await waitUntil { store.megaphone.info != nil || store.megaphone.infoFailed || store.megaphone.serverUnavailable }
        store.megaphone.setDraft(text)
    }

    @Test("첫 [보내기] 는 요청을 안 낸다 · 확인 [보내기] 를 연타해도 요청은 하나 · 잔량은 서버 값")
    func doubleClickSendsOnce() async throws {
        let host = "mega-mac-double"
        let wallet = Wallet(120)
        let store = Self.store(host: host) { request in
            switch request.rpc {
            case "megaphone_info": return .json(200, infoJSON(recipients: 12, ruby: wallet.value))
            case "send_megaphone":
                let left = wallet.spend(50)
                return .json(200, #"{"status":"ok","duplicate":false,"megaphone_id":"m1","recipients":12,"price":50,"ruby_balance":\#(left)}"#)
            default: return .json(404, missingFunction)
            }
        }
        await Self.ready(store)
        #expect(store.rubyBalance == 120, "정보 응답의 잔량이 미러에 안 들어갔다")
        store.megaphone.requestSend()
        #expect(store.megaphone.isConfirming)
        #expect(Self.sends(host).isEmpty, "첫 [보내기] 가 요청을 냈다 — 2단 확인이 아니다")
        #expect(store.megaphone.confirmQuestion == "루비 50개로 12명에게 보낼까요?")
        let first = store.megaphone.confirmSend()
        let second = store.megaphone.confirmSend()
        let third = store.megaphone.confirmSend()
        #expect(first && !second && !third)
        await Self.waitUntil { !store.megaphone.isSending }
        await Self.waitUntil { !store.megaphone.infoLoading }
        #expect(Self.sends(host).count == 1, "연타가 요청 \(Self.sends(host).count)건을 냈다")
        #expect(store.megaphone.notice == "보냈어요 · 12명에게")
        #expect(store.megaphone.noticeIsError == false)
        #expect(store.rubyBalance == 70, "잔량이 서버 값(70)이 아니다")
        #expect(store.megaphone.draft.isEmpty, "보낸 글이 남았다 — 다음 [보내기] 에 같은 말이 또 나간다")
        #expect(store.megaphone.pendingRequestID == nil, "서버가 답했는데 id 를 쥐고 있다")
        #expect(store.megaphone.isConfirming == false)
    }

    @Test("연결 오류 뒤 다시 누르면 **같은 요청 id** · 성공 뒤 새 작성은 새 id")
    func retryAfterTransportErrorReusesTheID() async throws {
        let host = "mega-mac-retry"
        let state = Counter()
        let store = Self.store(host: host) { request in
            switch request.rpc {
            case "megaphone_info": return .json(200, infoJSON(ruby: nil))
            case "send_megaphone":
                return state.next() == 1 ? .fail(.networkConnectionLost)
                    : .json(200, #"{"status":"ok","duplicate":true,"recipients":12,"ruby_balance":150}"#)
            default: return .json(404, missingFunction)
            }
        }
        store.megaphone.makeRequestID = { "req-\(UUID().uuidString.prefix(8))" }
        store.rubyBalance = 200
        await Self.ready(store)
        store.megaphone.requestSend()
        store.megaphone.confirmSend()
        await Self.waitUntil { !store.megaphone.isSending && store.megaphone.notice != nil }
        #expect(store.megaphone.notice == MegaphoneText.connection)
        #expect(store.megaphone.noticeIsError)
        let held = try #require(store.megaphone.pendingRequestID, "연결 오류 뒤 id 를 버렸다 — 재시도가 두 번 깎을 수 있다")
        #expect(store.megaphone.isConfirming, "연결 오류 뒤 확인 단계에서 다시 누를 수 없다")
        store.megaphone.confirmSend()
        await Self.waitUntil { !store.megaphone.isSending && store.megaphone.notice != MegaphoneText.connection }
        let ids = Self.sends(host).compactMap { $0.json["p_request_id"] as? String }
        #expect(ids == [held, held], "재시도의 id 가 다르다: \(ids)")
        #expect(store.megaphone.notice == "이미 보냈어요 · 12명에게", "duplicate 를 '보냈어요'와 구별하지 않았다")
        #expect(store.megaphone.pendingRequestID == nil)
        #expect(store.rubyBalance == 150)
        await Self.waitUntil { !store.megaphone.infoLoading }
        // 새 작성은 새 id.
        store.megaphone.applyInfo(MegaphoneInfoResponse(price: 50, cooldownSeconds: 600, cooldownRemainingSeconds: 0,
                                                       recipients: 12, maxLength: 198, rubyBalance: 150))
        store.megaphone.setDraft("두 번째 방송")
        store.megaphone.requestSend()
        store.megaphone.confirmSend()
        await Self.waitUntil { !store.megaphone.isSending }
        let after = Self.sends(host).compactMap { $0.json["p_request_id"] as? String }
        #expect(after.count == 3 && after[2] != held, "새 작성이 옛 id 를 재사용했다: \(after)")
    }

    @Test("거절 문구: 부족 · 쿨타임 · 받는 사람 없음 · 꺼짐 · 모르는 status · 함수 없음 — 서버 숫자로")
    func refusalCopy() async throws {
        let cases: [(String, String, Bool)] = [
            (#"{"status":"insufficient","need":50,"have":20,"ruby_balance":20}"#, "루비 30개 더 필요해요", false),
            (#"{"status":"cooldown","retry_after_seconds":125}"#, "3분 뒤에 다시 보낼 수 있어요", false),
            (#"{"status":"no_recipients","recipients":0}"#, "받을 사람이 없어요", false),
            (#"{"status":"disabled"}"#, "지금은 보낼 수 없어요", false),
            (#"{"status":"brand_new_status"}"#, MegaphoneText.failed, false),
            (missingFunction, "지금은 보낼 수 없어요", true),
        ]
        for (index, (json, expected, isMissing)) in cases.enumerated() {
            let host = "mega-mac-refusal-\(index)"
            let store = Self.store(host: host) { request in
                switch request.rpc {
                case "megaphone_info": return .json(200, infoJSON(ruby: 500))
                case "send_megaphone": return isMissing ? .json(404, json) : .json(200, json)
                default: return .json(404, missingFunction)
                }
            }
            await Self.ready(store)
            store.megaphone.requestSend()
            store.megaphone.confirmSend()
            await Self.waitUntil { !store.megaphone.isSending && store.megaphone.notice != nil }
            #expect(store.megaphone.notice == expected, "\(json) → \(String(describing: store.megaphone.notice))")
            #expect(store.megaphone.noticeIsError)
            #expect(store.megaphone.pendingRequestID == nil, "\(json): 서버가 답했는데(또는 함수가 없는데) id 를 쥐고 있다")
            #expect(store.megaphone.draft.isEmpty == false, "\(json): 거절됐는데 글이 사라졌다")
            if isMissing { #expect(store.megaphone.serverUnavailable) }
        }
    }

    @Test("첫 단계의 지금-시계 판정: 쿨타임 · 잔량 부족 · 받는 사람 0 · 빈 글 — 요청 0")
    func localGatesBeforeConfirm() async throws {
        let host = "mega-mac-gates"
        let store = Self.store(host: host) { request in
            request.rpc == "megaphone_info" ? .json(200, infoJSON(recipients: 3, cooldown: 90, ruby: 120)) : .json(404, missingFunction)
        }
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        store.megaphone.clock = { now }
        await Self.ready(store)
        store.megaphone.requestSend()
        #expect(store.megaphone.notice == "2분 뒤에 다시 보낼 수 있어요" && !store.megaphone.isConfirming)
        // 시계가 지나면 같은 정보로도 열린다(버튼 잠금을 그리는 시각에 맡기지 않는다).
        now = now.addingTimeInterval(91)
        store.megaphone.requestSend()
        #expect(store.megaphone.isConfirming, "쿨타임이 지났는데도 막혔다")
        store.megaphone.cancelConfirm()
        store.rubyBalance = 49
        store.megaphone.requestSend()
        #expect(store.megaphone.notice == "루비 1개 더 필요해요" && !store.megaphone.isConfirming)
        store.rubyBalance = 120
        store.megaphone.applyInfo(MegaphoneInfoResponse(price: 50, cooldownSeconds: 600, cooldownRemainingSeconds: 0,
                                                       recipients: 0, maxLength: 198))
        store.megaphone.requestSend()
        #expect(store.megaphone.notice == "받을 사람이 없어요" && !store.megaphone.isConfirming)
        store.megaphone.setDraft("   ")
        #expect(store.megaphone.canRequestSend == false)
        store.megaphone.requestSend()
        #expect(store.megaphone.notice == "보낼 말을 적어 주세요")
        #expect(Self.sends(host).isEmpty, "첫 단계가 요청을 냈다")
        // 글을 고치면 확인 단계가 풀린다(확인한 글과 보낼 글이 달라지면 안 된다).
        store.megaphone.applyInfo(MegaphoneInfoResponse(price: 50, cooldownSeconds: 600, cooldownRemainingSeconds: 0,
                                                       recipients: 5, maxLength: 198))
        store.megaphone.setDraft("확인 받은 글")
        store.megaphone.requestSend()
        #expect(store.megaphone.isConfirming)
        store.megaphone.setDraft("확인 받은 글 + 더")
        #expect(!store.megaphone.isConfirming)
        #expect(store.megaphone.confirmSend() == false, "확인이 풀렸는데 보냈다")
    }

    @Test("로그아웃은 글·id·정보를 비우고, 나가 있던 응답은 다음 계정에 안 닿는다")
    func signOutResets() async throws {
        let host = "mega-mac-signout"
        let store = Self.store(host: host) { request in
            switch request.rpc {
            case "megaphone_info": return .json(200, infoJSON())
            case "send_megaphone": return .fail(.timedOut)
            default: return .json(404, missingFunction)
            }
        }
        await Self.ready(store, text: "앞 사람의 글")
        store.megaphone.requestSend()
        store.megaphone.confirmSend()
        await Self.waitUntil { !store.megaphone.isSending }
        #expect(store.megaphone.pendingRequestID != nil)
        store.signOut()
        #expect(store.megaphone.draft.isEmpty)
        #expect(store.megaphone.pendingRequestID == nil)
        #expect(store.megaphone.info == nil)
        #expect(store.megaphone.isComposerOpen == false)
        #expect(store.megaphone.notice == nil)
    }

    @Test("카드 배선: 작성기를 열면 고른 상품이 풀리고, 상품을 고르면 작성기가 접히고, 상점을 닫으면 접힌다")
    func cardWiring() async throws {
        let host = "mega-mac-wiring"
        let store = Self.store(host: host) { request in
            request.rpc == "megaphone_info" ? .json(200, infoJSON()) : .json(404, missingFunction)
        }
        store.isShopPanelVisible = true
        store.applyShopState(ShopStateResponse(rubyBalance: 100, ultraBalance: 1, ultraPrice: 3, characters: []))
        store.shopLoaded = true
        store.selectShopItem(.ultra)
        #expect(store.shopSelection == .ultra)
        store.toggleMegaphoneComposer()
        #expect(store.megaphone.isComposerOpen && store.shopSelection == nil)
        await Self.waitUntil { store.megaphone.info != nil }
        store.megaphone.setDraft("남는 글")
        store.selectShopItem(.ultra)
        #expect(!store.megaphone.isComposerOpen && store.shopSelection == .ultra)
        #expect(store.megaphone.draft == "남는 글", "접었더니 쓰던 글이 사라졌다")
        store.toggleMegaphoneComposer()
        store.closeShopPanel()
        #expect(!store.megaphone.isComposerOpen)
    }

    /// 리뷰 지적(2026-10-14): 카드의 가격 칩이 `megaphone_info` 를 읽은 **뒤에만** 섰고, 그 읽기는 작성기를 열 때뿐이었다 —
    /// 그래서 비용(💎50)을 카드가 아니라 확인 질문에서야 처음 봤다. 상점을 여는 순간 미리 읽는다.
    /// 기준선: 열기 전 `price == nil`(카드에 칩 없음) · 미리 읽기는 작성기를 안 열고 · 잔량 미러는 `shop_state` 몫이다(늦은 정보 응답이
    /// 그 사이 구매 결과를 옛 잔량으로 덮지 않게 — 정보 응답은 일부러 **다른** 잔량 999 를 말한다).
    @Test("상점을 열면 확성기 값을 미리 읽어 카드가 처음부터 가격을 말한다 · 작성기는 안 열고 · 잔량은 shop_state 몫")
    func openingTheShopPrefetchesThePrice() async throws {
        let host = "mega-mac-prefetch"
        let store = Self.store(host: host) { request in
            switch request.rpc {
            case "shop_state":
                return .json(200, #"{"status":"ok","ruby_balance":80,"ultra_balance":1,"ultra_price":3,"characters":[]}"#)
            case "megaphone_info": return .json(200, infoJSON(recipients: 12, ruby: 999))
            default: return .json(404, missingFunction)
            }
        }
        #expect(store.megaphone.price == nil, "기준선이 틀렸다 — 열기 전부터 가격을 알면 이 테스트는 공허하다")
        store.toggleShopPanel()
        await Self.waitUntil { store.shopLoaded && store.megaphone.price != nil && !store.megaphone.infoLoading }
        #expect(store.isShopPanelVisible)
        #expect(store.megaphone.price == 50, "상점을 열었는데 확성기 가격을 모른다 — 카드가 💎 없이 선다")
        #expect(store.megaphone.isComposerOpen == false, "미리 읽기가 작성기를 열었다")
        let rpcs = MegaphoneStubProtocol.records(host: host).map(\.rpc)
        #expect(rpcs.filter { $0 == "megaphone_info" }.count == 1, "정보 요청이 \(rpcs) — 한 번이어야 한다")
        #expect(!rpcs.contains("send_megaphone"), "상점을 열기만 했는데 전송이 나갔다")
        #expect(store.rubyBalance == 80, "미리 읽기가 잔량 미러를 덮었다(\(String(describing: store.rubyBalance))) — shop_state 몫이다")
        // 지키려는 경합을 순서 그대로 만든다: 구매 응답이 미러를 고친 **뒤에** 미리 읽기 응답이 도착한다(두 응답이 동시에 나가는
        // 첫 열기만으로는 도착 순서가 갈려 미러 회귀가 초록으로 숨을 수 있다 — 뮤테이션으로 확인했다).
        store.rubyBalance = 30
        store.prefetchMegaphoneInfo()
        await Self.waitUntil { Self.infoCalls(host) == 2 && !store.megaphone.infoLoading }
        #expect(Self.infoCalls(host) == 2)
        #expect(store.rubyBalance == 30, "늦게 도착한 미리 읽기가 구매 뒤 잔량(30)을 옛 값 \(String(describing: store.rubyBalance))로 덮었다")
        // 작성기를 열면 그때는 잔량도 정보 응답이 말한다(작성 화면의 판정 재료 — 기존 규약 그대로).
        store.toggleMegaphoneComposer()
        await Self.waitUntil { !store.megaphone.infoLoading && store.rubyBalance == 999 }
        #expect(store.rubyBalance == 999, "작성기의 정보 읽기는 잔량을 고쳐야 한다")
        // 닫았다 다시 열면 또 읽는다(가격·받는 사람 수는 그 사이 바뀐다).
        store.closeShopPanel()
        store.toggleShopPanel()
        await Self.waitUntil { Self.infoCalls(host) == 4 && !store.megaphone.infoLoading }
        #expect(Self.infoCalls(host) == 4)
    }

    static func infoCalls(_ host: String) -> Int {
        MegaphoneStubProtocol.records(host: host).filter { $0.rpc == "megaphone_info" }.count
    }

    /// 가격 칩(RubyBalanceChip — 아이콘 13pt + 위아래 2pt)은 글자 한 줄보다 높다. 칩이 카드 줄을 키우면 크롬이 늘어 격자 상한
    /// (`chromeOutsideGrid`)이 거짓이 된다 — 미리 읽기 뒤로는 **칩이 서 있는 것이 평소 모습**이므로 그 모습으로 잰다.
    /// 기준선: 같은 패널을 칩 없이(정보 모름) 재서 **둘 다** 상수와 맞아야 한다(칩 유무로 높이가 갈리면 안 된다).
    @Test("가격 칩이 서도 상점 크롬은 상수 그대로다 — 칩 유무로 카드 높이가 안 갈린다")
    func priceChipKeepsTheChromeConstant() throws {
        func chrome(cards: Int, withPrice: Bool) throws -> CGFloat {
            let store = V0317ShopTests.plainStore()
            store.applyShopState(ShopStateResponse(rubyBalance: 10, ultraBalance: 1, ultraPrice: 3,
                                                   characters: V0317ShopTests.rows(ownedIDs: [], limit: cards)))
            store.shopLoaded = true
            if withPrice {
                store.megaphone.applyInfo(MegaphoneInfoResponse(price: 50, cooldownSeconds: 600, cooldownRemainingSeconds: 0,
                                                               recipients: 46, maxLength: 198))
            }
            #expect((store.megaphone.price != nil) == withPrice, "준비 실패 — 칩 유무 기준선이 안 갈렸다")
            let panel = CheckShopPanel(store: store, onBack: {})
            // ImageRenderer 는 첫 두 장을 다르게 굽는다 — 높이만 쓰지만 세 번째 장으로 잰다.
            _ = V0317ShopTests.height(panel, width: CheckMenuView.contentColumnWidth)
            _ = V0317ShopTests.height(panel, width: CheckMenuView.contentColumnWidth)
            let height = try #require(V0317ShopTests.height(panel, width: CheckMenuView.contentColumnWidth))
            return height - ShopPanelGridBudget.naturalHeight(rowCount: ShopPanelGridBudget.rowCount(cardCount: cards))
        }
        for cards in [3, 6] {
            let bare = try chrome(cards: cards, withPrice: false)
            let priced = try chrome(cards: cards, withPrice: true)
            print("[v0351] 상점 크롬 카드 \(cards): 칩 없음 \(bare)pt · 칩 있음 \(priced)pt · 상수 \(ShopPanelGridBudget.chromeOutsideGrid)pt")
            #expect(abs(priced - ShopPanelGridBudget.chromeOutsideGrid) < 1.0,
                    "카드 \(cards): 가격 칩이 선 크롬 \(priced)pt ≠ 상수 \(ShopPanelGridBudget.chromeOutsideGrid)pt — 격자 상한이 거짓이 된다")
            #expect(abs(priced - bare) < 1.0, "카드 \(cards): 칩 유무로 크롬이 갈린다(\(bare) → \(priced))")
        }
    }

    // MARK: 렌더 — 예산

    @Test("작성기를 연 상점 패널은 격자를 연 패널보다 높지 않다 · 최악 조합도 700pt 안")
    func composerFitsTheBudget() throws {
        func panelHeight(composer: Bool, cards: Int, extra: CGFloat) -> CGFloat? {
            let store = V0317ShopTests.plainStore()
            store.applyShopState(ShopStateResponse(rubyBalance: 100, ultraBalance: 1, ultraPrice: 3,
                                                   characters: V0317ShopTests.rows(ownedIDs: [], limit: cards)))
            store.shopLoaded = true
            if composer {
                store.megaphone.open()   // 세션이 없어 네트워크는 안 나간다
                store.megaphone.applyInfo(MegaphoneInfoResponse(price: 50, cooldownSeconds: 600, cooldownRemainingSeconds: 0,
                                                               recipients: 46, maxLength: 198, rubyBalance: 100))
                store.megaphone.setDraft("오늘 3시 라운지에서 간식 나눠요")
            }
            let panel = CheckShopPanel(store: store, extraChromeHeight: extra, onBack: {})
            return V0317ShopTests.height(panel, width: CheckMenuView.contentColumnWidth)
        }
        // 격자가 가장 낮은 경우(카드 3장 = 1행)와 최악 예산(목표 편집 92pt)에서도 작성기가 격자 자리를 넘지 않는다.
        for (cards, extra) in [(3, CGFloat(0)), (6, 0), (6, 92), (3, 92)] {
            let grid = try #require(panelHeight(composer: false, cards: cards, extra: extra))
            let composer = try #require(panelHeight(composer: true, cards: cards, extra: extra))
            print("[v0351] 상점 패널 카드 \(cards) · 추가 크롬 \(extra): 격자 \(grid)pt vs 작성기 \(composer)pt")
            #expect(composer <= grid, "카드 \(cards) · 추가 \(extra): 작성기 \(composer)pt > 격자 \(grid)pt — 예산이 거짓이 된다")
        }
        // 작성기 상수 자체가 격자 구획 최소(소제목 + 4 + 카드 112) + 7 + 바 38 보다 작다.
        #expect(MegaphoneComposer.height <= 14 + 4 + ShopPanelGridBudget.minGridHeight + 7 + CheckShopPanel.purchaseBarHeight)
    }

    @Test("작성기 렌더: 입력칸 자리(노란 상자) · 확인 단계 문구 · 팝오버 최악 조합 700pt")
    func composerRenders() throws {
        let store = V0317ShopTests.teamStore(members: 8)
        // toggleShopPanel 은 부르지 않는다 — 세션이 있는 스토어라 상점 로드가 실서버로 나간다. 깃발만 세운다.
        store.isShopPanelVisible = true
        store.applyShopState(ShopStateResponse(rubyBalance: 120, ultraBalance: 7, ultraPrice: 3,
                                               characters: V0317ShopTests.rows(ownedIDs: [])))
        store.shopLoaded = true
        store.megaphone.applyInfo(MegaphoneInfoResponse(price: 50, cooldownSeconds: 600, cooldownRemainingSeconds: 0,
                                                       recipients: 46, maxLength: 198, rubyBalance: 120))
        store.isEditingWeeklyGoal = true
        let view = CheckMenuView(store: store, previewClipsOverflowList: true, previewGoalEditing: true,
                                 characterDefaults: V0317ShopTests.isolatedDefaults())
        storeOpenComposerWithoutNetwork(store)
        let height = try #require(V0317ShopTests.popoverHeight(view))
        print("[v0351] 최악 조합(목표 편집 + 작성기) 팝오버 \(height)pt")
        #expect(height <= 700, "작성기를 연 팝오버가 \(height)pt — 700pt 상한을 넘는다")

        let panel = CheckShopPanel(store: store, onBack: {})
        let bitmap = try #require(V0317ShopTests.bitmap(panel, width: CheckMenuView.contentColumnWidth))
        // TextField 자리는 ImageRenderer 가 노란 상자로 그린다 — 상자가 **있어야** 입력칸이 선 것이다.
        #expect(V0317ShopTests.longestYellowRun(bitmap) >= 200, "작성기 입력칸이 안 그려졌다")
        V0317ShopTests.save(bitmap, name: "v0351-megaphone-composer.png")
        store.megaphone.setDraft("오늘 3시 라운지에서 간식 나눠요")
        store.megaphone.requestSend()
        #expect(MegaphoneComposer.barTitle(store.megaphone) == "루비 50개로 46명에게 보낼까요?")
        #expect(MegaphoneComposer.barDetail(store.megaphone) == "보내면 되돌릴 수 없어요")
        let confirming = try #require(V0317ShopTests.bitmap(CheckShopPanel(store: store, onBack: {}),
                                                            width: CheckMenuView.contentColumnWidth))
        V0317ShopTests.save(confirming, name: "v0351-megaphone-confirm.png")
    }

    /// 작성기 깃발만 세운다(세션이 있는 스토어에서 open 을 부르면 가짜 토큰으로 정보 요청이 나간다 — 렌더 테스트는 네트워크를 안 탄다).
    private func storeOpenComposerWithoutNetwork(_ store: WorkTimerStore) {
        let saved = store.session
        store.session = nil
        store.megaphone.open()
        store.session = saved
    }

    // MARK: 한글 조합 — 마지막 음절

    /// 확성기 칸에 "모두 안녕하세" + 조합 중 "요" 를 심고 [보내기](첫 단계)의 문을 지나게 한다. 문이 그 자리의 조합을 확정해야
    /// 확인 단계로 가는 글이 화면에 보이던 문장 전체다(루비 50개짜리 방송이 마지막 음절 없이 나가면 안 된다).
    @Test("조합 중인 마지막 음절까지 확인 단계로 간다(.megaphone 자리의 확정 문)")
    func compositionIsCommittedBeforeTheFirstStep() throws {
        let store = WorkTimerStore(environment: ["CHECK_SUPABASE_ANON_KEY": "anon-test-key"],
                                   defaults: CheckTestScratch.defaults("mega-ime"))
        // 세션은 requestSend 의 문턱만 넘게 둔다 — open()/loadInfo 를 부르지 않으므로 네트워크는 안 나간다.
        store.session = SupabaseSession(accessToken: "access-token", refreshToken: nil, userID: "me")
        store.megaphone.applyInfo(MegaphoneInfoResponse(price: 50, cooldownSeconds: 600, cooldownRemainingSeconds: 0,
                                                       recipients: 5, maxLength: 198, rubyBalance: 100))
        let width = CheckMenuView.contentColumnWidth
        let hosting = NSHostingView(rootView: MegaphoneComposer(store: store).frame(width: width, height: MegaphoneComposer.height))
        hosting.frame = NSRect(x: 0, y: 0, width: width, height: MegaphoneComposer.height)
        let window = MegaKeyWindow(contentRect: hosting.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        Self.spin()
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        Self.spin()
        try #require(FeedbackReplySend.window(for: .megaphone) === window, "확성기 칸이 자기 창을 확정 문에 안 알렸다")
        let field = try #require(Self.allViews(hosting).compactMap { $0 as? NSTextField }.first { $0.isEditable },
                                 "확성기 입력칸(NSTextField)이 없다")
        _ = window.makeFirstResponder(field)
        Self.spin()
        let editor = try #require(field.currentEditor() as? NSTextView, "필드 에디터가 안 섰다")
        for character in "모두 안녕하세" {
            editor.insertText(String(character), replacementRange: NSRange(location: NSNotFound, length: 0))
            Self.spin(0.01)
        }
        editor.setMarkedText("요", selectedRange: NSRange(location: 1, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        Self.spin()
        try #require(editor.hasMarkedText(), "조합을 못 심었다 — 이 테스트가 재는 것이 없다")
        print("[v0351] 조합 중 바인딩 = \(store.megaphone.draft.debugDescription) · 화면 = \(editor.string.debugDescription)")
        // 세계의 사실(전제): 문 없이 읽으면 바인딩은 한 음절 늦다 — 그래서 문이 필요하다(V0321 과 같은 사실).
        #expect(store.megaphone.draft == "모두 안녕하세", "전제가 바뀌었다 — 조합 중 바인딩이 늦지 않다면 이 테스트를 다시 따져라")
        FeedbackReplySend.commitThenSend(slot: .megaphone) { store.megaphone.requestSend() }
        #expect(store.megaphone.draft == "모두 안녕하세요", "확인 단계로 간 글이 마지막 음절을 잃었다: \(store.megaphone.draft.debugDescription)")
        #expect(store.megaphone.isConfirming, "첫 단계가 확인으로 안 갔다: \(String(describing: store.megaphone.notice))")
        #expect(!editor.hasMarkedText())
    }

    static func spin(_ seconds: Double = 0.05) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }

    static func allViews(_ view: NSView) -> [NSView] {
        view.subviews + view.subviews.flatMap { allViews($0) }
    }

    // MARK: 소스 계약

    @Test("요청은 확인 단계 버튼 하나에서만 · 두 버튼 다 조합 확정 문을 지난다 · 서비스 호출은 코어 한 곳")
    func sourceContracts() throws {
        let composer = V0317ShopTests.stripped(try V0317ShopTests.source("CheckMegaphoneComposer.swift"))
        #expect(composer.components(separatedBy: "mega.confirmSend()").count - 1 == 1, "confirmSend 를 부르는 자리가 하나가 아니다")
        #expect(composer.contains("FeedbackReplySend.commitThenSend(slot: .megaphone) { mega.confirmSend() }"),
                "확인 [보내기] 가 조합 확정을 안 거친다 — 한글 마지막 음절이 빠진 채 모두에게 간다")
        #expect(composer.contains("FeedbackReplySend.commitThenSend(slot: .megaphone) { mega.requestSend() }"))
        #expect(composer.contains("FeedbackReplyWindowAnchor(slot: .megaphone)"), "입력칸이 창을 조합 확정 문에 안 알린다")
        #expect(!composer.contains("sendMegaphone("), "뷰가 서비스를 직접 부른다")
        let panel = V0317ShopTests.stripped(try V0317ShopTests.source("CheckShopPanel.swift"))
        #expect(panel.contains("store.toggleMegaphoneComposer()") && panel.contains("MegaphoneComposer(store: store)"))
        #expect(!panel.contains("confirmSend()"), "상점 카드가 바로 보낸다 — 2단 확인이 우회된다")
        // 서비스의 sendMegaphone 을 부르는 자리는 코어 스토어 하나뿐(맥·폰 한 벌).
        let macDir = CheckCoreSourceLayout.macDirectory
        for name in try FileManager.default.contentsOfDirectory(atPath: macDir.path) where name.hasSuffix(".swift") {
            let code = V0317ShopTests.stripped(try String(contentsOf: macDir.appendingPathComponent(name), encoding: .utf8))
            #expect(!code.contains(".sendMegaphone("), "\(name) 이 sendMegaphone 을 직접 부른다")
        }
        let store = V0317ShopTests.stripped(try String(contentsOf: macDir.appendingPathComponent("WorkTimerStore.swift"), encoding: .utf8))
        #expect(store.contains("megaphone.attach(host: self)"), "확성기 스토어에 호스트를 안 넘긴다 — 세션·루비 미러가 없다")
        #expect(store.contains("megaphone.reset()"), "로그아웃이 확성기 글·id 를 안 비운다")
    }
}

/// 필드 에디터는 창이 key 가 될 수 있을 때만 선다(V0314 · V0321 하네스와 같은 이유).
private final class MegaKeyWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// 스텁 서버의 루비 지갑(정보 응답과 전송 응답이 같은 값을 말하게).
private final class Wallet: @unchecked Sendable {
    private let lock = NSLock()
    private var balance: Int
    init(_ balance: Int) { self.balance = balance }
    var value: Int { lock.lock(); defer { lock.unlock() }; return balance }
    func spend(_ amount: Int) -> Int { lock.lock(); defer { lock.unlock() }; balance -= amount; return balance }
}

/// 스텁 응답기에서 호출 순번을 세는 잠금 카운터.
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func next() -> Int { lock.lock(); defer { lock.unlock() }; value += 1; return value }
}
