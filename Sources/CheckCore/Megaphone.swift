import Foundation
import Observation

// MARK: - 확성기(📢) — 루비 50개로 앱 사용자 모두에게 한마디 (v0.3.51 맥 · 1.0.7 폰)
//
// 서버 계약은 `supabase/migrations/20261014122000_megaphone.sql` 이 정본이다. 요점만:
//   · `send_megaphone(p_body, p_request_id)` 가 받는 사람마다 **평범한 1:1 메시지 한 줄**을 넣는다(본문 앞에 서버가 `📢 `).
//     그래서 받는 쪽 화면은 아무것도 새로 그리지 않는다 — 옛 앱(0.3.50 · 1.0.6)도 말풍선·대화·점·푸시로 그대로 받는다.
//   · 보내는 쪽 이력에서는 그 줄들이 빠진다(서버 message_history 가 거른다 — 대화 목록에 받는 사람 수만큼 스레드가 안 생긴다).
//   · `megaphone_info()` 가 작성 화면의 한 줄("지금 보내면 N명에게 가요")과 가격·쿨타임·잔량을 준다.
//
// ── 이 파일이 지키는 것 ──
// ① **이중 과금이 원리적으로 없다.** 작성 한 번마다 request_id 를 **하나** 만들고(`pendingRequestID`), 전송 중에는 두 번째 요청을
//    띄우지 않는다(`isSending`). 연결 오류로 결과를 모르면 그 id 를 **그대로 쥐고 있다가** 다시 누를 때 재사용한다 — 서버가 이미
//    처리했으면 처음 결과를 duplicate 로 돌려주고 아무것도 다시 깎지 않는다. id 를 버리는 것은 서버가 **답을 준 뒤**뿐이다.
// ② **2단 확인.** [보내기] 는 확인 단계로만 간다(`requestSend`) — 실제 요청은 확인 단계의 [보내기](`confirmSend`) 하나뿐이다.
//    상점이 "누르면 바로 사지는" 사고(2026-09-14)를 겪고 세운 규약과 같다. 루비 50개는 되돌릴 수 없다.
// ③ **루비는 서버가 말한다.** 응답이 실어 준 잔량으로만 미러(`host.rubyBalance`)를 고친다 — 클라가 스스로 빼지 않는다.
// ④ **맥과 폰이 한 벌이다.** 이 스토어는 `GomokuStoreHost`(맥 WorkTimerStore · 폰 MobileGomokuHost)를 빌려 쓰므로 두 앱의
//    판정·문구·세대 가드가 갈리지 않는다. 화면만 다르다(맥: 상점 패널 · 폰: 메시지 탭 시트).
// ⑤ 본문은 사람이 쓴 문장이다 — 로그로 흘리지 않는다.

// MARK: 전선 모양

/// `send_megaphone` 요청. **키 둘을 언제나 싣는다**(서버 인자는 둘 다 DEFAULT 지만, 키 집합이 흔들리면 PostgREST 가 다른 함수를 찾는다).
package struct SendMegaphoneRequest: Encodable, Equatable, Sendable {
    package let pBody: String
    package let pRequestId: String

    package init(pBody: String, pRequestId: String) {
        self.pBody = pBody
        self.pRequestId = pRequestId
    }
}

/// `megaphone_info()` 응답. 전 필드 옵셔널 — 키 하나 빠진 서버에서 통째로 throw 하지 않게(메시지 파일 공통 규약).
package struct MegaphoneInfoResponse: Decodable, Equatable, Sendable {
    package var status: String?
    package var enabled: Bool?
    package var price: Int?
    package var cooldownSeconds: Int?
    package var cooldownRemainingSeconds: Int?
    package var recipients: Int?
    package var maxLength: Int?
    package var rubyBalance: Int?

    package init(status: String? = "ok", enabled: Bool? = true, price: Int? = nil, cooldownSeconds: Int? = nil,
                 cooldownRemainingSeconds: Int? = nil, recipients: Int? = nil, maxLength: Int? = nil,
                 rubyBalance: Int? = nil) {
        self.status = status
        self.enabled = enabled
        self.price = price
        self.cooldownSeconds = cooldownSeconds
        self.cooldownRemainingSeconds = cooldownRemainingSeconds
        self.recipients = recipients
        self.maxLength = maxLength
        self.rubyBalance = rubyBalance
    }
}

/// `send_megaphone` 응답(jsonb `{status, …}`). 합성 디코더(옵셔널은 decodeIfPresent) — 커스텀 init(from:) 의 "키만 더하고
/// 디코드 줄을 빼먹는" 함정(PokeSendResponse)을 만들지 않으려고 손으로 쓰지 않는다.
package struct MegaphoneSendResponse: Decodable, Equatable, Sendable {
    package let status: String
    package var megaphoneId: String?
    package var recipients: Int?
    package var price: Int?
    package var rubyBalance: Int?
    package var duplicate: Bool?
    package var need: Int?
    package var have: Int?
    package var maxLength: Int?
    package var retryAfterSeconds: Int?
    package var cooldownSeconds: Int?

    package init(status: String, megaphoneId: String? = nil, recipients: Int? = nil, price: Int? = nil,
                 rubyBalance: Int? = nil, duplicate: Bool? = nil, need: Int? = nil, have: Int? = nil,
                 maxLength: Int? = nil, retryAfterSeconds: Int? = nil, cooldownSeconds: Int? = nil) {
        self.status = status
        self.megaphoneId = megaphoneId
        self.recipients = recipients
        self.price = price
        self.rubyBalance = rubyBalance
        self.duplicate = duplicate
        self.need = need
        self.have = have
        self.maxLength = maxLength
        self.retryAfterSeconds = retryAfterSeconds
        self.cooldownSeconds = cooldownSeconds
    }
}

/// 전송 결과의 도메인 표현. **모르는 status 는 `.failed`** 로 접는다(일반 안내 한 줄 — 새 어휘가 생겨도 화면이 죽지 않는다).
package enum MegaphoneSendOutcome: Equatable, Sendable {
    /// 보냈다(또는 같은 요청을 이미 보냈다 — duplicate). 받는 사람 수는 서버가 센 값.
    case sent(recipients: Int, duplicate: Bool)
    case insufficient(need: Int?, have: Int?)
    case cooldown(retryAfterSeconds: Int?)
    case noRecipients
    case empty
    case tooLong(maxLength: Int?)
    case notText
    /// 킬스위치가 내려가 있다(`megaphone_enabled()` = false).
    case disabled
    case blackout
    /// 서버에 확성기 함수가 아직 없다(PGRST202 · 404 — 앱이 db push 보다 먼저 나간 창). status 가 아니라 **throw 로 오는** 실패라
    /// `init?(error:)` 만 이 값을 만든다. 함수를 못 찾았다 = 서버에서 아무것도 안 돌았다(루비도 안 깎였다).
    case unavailable
    /// 우리가 모르는 실패(unauthorized · no_profile · 새 어휘).
    case failed

    package init(response: MegaphoneSendResponse) {
        switch response.status {
        case "ok":            self = .sent(recipients: response.recipients ?? 0, duplicate: response.duplicate ?? false)
        case "insufficient":  self = .insufficient(need: response.need, have: response.have)
        case "cooldown":      self = .cooldown(retryAfterSeconds: response.retryAfterSeconds)
        case "no_recipients": self = .noRecipients
        case "empty":         self = .empty
        case "too_long":      self = .tooLong(maxLength: response.maxLength)
        case "not_text":      self = .notText
        case "disabled":      self = .disabled
        case "blackout":      self = .blackout
        default:              self = .failed
        }
    }

    /// throw 로 온 실패 중 **결과를 아는 것**만 값으로 만든다: 함수 없음(PGRST202 · 404) → `.unavailable`.
    /// 그 밖(오프라인 · 5xx · 응답 해석 실패)은 nil — 서버가 처리했는지 모르므로 호출부가 요청 id 를 쥔 채 다시 묻게 둔다.
    package init?(error: Error) {
        guard let known = error as? SupabaseWorkServiceError, BlockReportRules.isMissingFunction(known) else { return nil }
        self = .unavailable
    }
}

// MARK: 본문 규칙

/// 확성기 본문의 사전 판정. 서버와 **같은 눈금**(정규화 후 코드포인트)이고, 상한은 메시지 상한에서 서버 표식(`📢 `, 2)을 뺀 198 이다.
/// 판정의 권위는 서버다 — 여기는 헛왕복을 줄이는 문이다.
package enum MegaphoneBody {
    /// 서버가 붙이는 표식(`megaphone_prefix()`). 클라는 이 글자를 붙여 보내지 않는다 — 화면 미리보기에만 쓴다.
    package static let prefix = "\u{1F4E2} "
    /// 사용자가 쓸 수 있는 코드포인트 수(서버 `megaphone_max_length()` = 198).
    package static var maxLength: Int { MessageBody.maxLength - prefix.unicodeScalars.count }

    /// 화면 카운터("n/198")와 같은 눈금의 길이.
    package static func length(_ raw: String) -> Int { MessageBody.length(raw) }

    /// 빈 판정이 먼저다(공백만 친 입력에 "198자까지예요"라고 하지 않는다 — MessageBody.validate 와 같은 순서).
    package static func validate(_ raw: String, maxLength limit: Int? = nil) -> MessageBodyValidation {
        let normalized = MessageBody.sanitized(raw)
        if !MessageBody.hasVisibleContent(normalized) { return .empty }
        let cap = limit ?? maxLength
        if normalized.unicodeScalars.count > cap { return .tooLong(maxLength: cap) }
        return .ok(normalized)
    }
}

// MARK: 문구(맥·폰 한 벌)

package enum MegaphoneText {
    package static let title = "확성기"
    package static let icon = "\u{1F4E2}"
    /// 상점 카드·버튼 제목("📢 확성기").
    package static var badgeTitle: String { "\(icon) \(title)" }
    package static let explainer = "앱을 쓰는 모두에게 메시지로 가요 · 집중 중인 사람은 빼요"
    package static let placeholder = "모두에게 할 말을 적어 주세요"
    package static let sendButton = "보내기"
    package static let cancelButton = "취소"

    package static func sent(recipients: Int) -> String { "보냈어요 · \(recipients)명에게" }
    package static func alreadySent(recipients: Int) -> String { "이미 보냈어요 · \(recipients)명에게" }
    /// 모자란 루비(상점·오목과 같은 문구를 쓴다 — 새로 만들지 않는다).
    package static func shortfall(need: Int?, have: Int?) -> String { CheckCoreShared.shortfallNotice(need: need, have: have) }
    /// 쿨타임. 분 단위로 올림한다(남은 1초도 "1분 뒤")— 0 이하는 부르지 않는다.
    package static func cooldown(seconds: Int) -> String {
        "\(cooldownMinutes(seconds: seconds))분 뒤에 다시 보낼 수 있어요"
    }
    package static func cooldownMinutes(seconds: Int) -> Int { max(1, (max(0, seconds) + 59) / 60) }
    package static let noRecipients = "받을 사람이 없어요"
    package static let unavailable = "지금은 보낼 수 없어요"
    package static let empty = "보낼 말을 적어 주세요"
    package static func tooLong(maxLength: Int?) -> String {
        "확성기는 \(maxLength ?? MegaphoneBody.maxLength)자까지예요. 줄여서 보내 주세요"
    }
    package static let notText = MessageNoticeText.notText
    package static let blackout = MessageNoticeText.blackout
    package static let connection = "연결이 불안정해요. 잠시 후 다시 시도해 주세요"
    package static let failed = "보내지 못했어요. 잠시 후 다시 시도해 주세요"
    package static let loadingInfo = "받을 사람을 세는 중이에요"
    package static let infoFailed = "받을 사람 수를 못 읽었어요"

    /// 작성 화면의 한 줄.
    package static func reach(recipients: Int) -> String { "지금 보내면 \(recipients)명에게 가요" }
    /// 확인 단계의 질문.
    package static func confirm(price: Int, recipients: Int) -> String { "루비 \(price)개로 \(recipients)명에게 보낼까요?" }
    /// 카운터("12/198").
    package static func counter(length: Int, maxLength: Int) -> String { "\(length)/\(maxLength)" }
}

// MARK: - 서비스

extension SupabaseWorkService {
    package nonisolated static let sendMegaphonePath = "/rest/v1/rpc/send_megaphone"
    package nonisolated static let megaphoneInfoPath = "/rest/v1/rpc/megaphone_info"

    /// 확성기를 보낸다. `send_megaphone(p_body, p_request_id)`.
    ///
    /// **빈 글·198자 초과는 요청을 내지 않고** 서버와 같은 status 로 즉답한다(sendMessage 와 같은 규약 — 로컬 거절과 서버 거절이
    /// 같은 switch 로 간다). 보내는 문자열은 정규화된 값이다. 표식(`📢 `)은 **서버가** 붙인다.
    /// 함수가 없는 서버는 PGRST202 → `.databaseSchemaMissing` 으로 던진다(스토어가 "지금은 보낼 수 없어요"로 접는다).
    package func sendMegaphone(accessToken: String, body: String, requestID: String) async throws -> MegaphoneSendResponse {
        switch MegaphoneBody.validate(body) {
        case .empty:
            return MegaphoneSendResponse(status: "empty", maxLength: MegaphoneBody.maxLength)
        case .tooLong(let maxLength):
            return MegaphoneSendResponse(status: "too_long", maxLength: maxLength)
        case .ok(let normalized):
            let data = try await send(
                path: Self.sendMegaphonePath,
                method: "POST",
                body: SendMegaphoneRequest(pBody: normalized, pRequestId: requestID),
                accessToken: accessToken,
                prefer: nil
            )
            return try decoder.decode(MegaphoneSendResponse.self, from: data)
        }
    }

    /// 작성 화면 정보. `megaphone_info()` — 인자 없는 RPC 라 본문은 `{}` 다.
    package func megaphoneInfo(accessToken: String) async throws -> MegaphoneInfoResponse {
        let data = try await send(
            path: Self.megaphoneInfoPath,
            method: "POST",
            body: EmptyBody(),
            accessToken: accessToken,
            prefer: nil
        )
        return try decoder.decode(MegaphoneInfoResponse.self, from: data)
    }
}

// MARK: - 스토어(맥·폰 공용)

/// 작성 화면이 아는 서버 사실 한 벌(`megaphone_info` 한 번). 쿨타임은 **끝나는 시각**으로 들고 있다 — 남은 초를 들고 있으면
/// 화면이 다시 그려질 때마다 같은 숫자를 말한다.
package struct MegaphoneInfo: Equatable, Sendable {
    package var enabled: Bool
    package var price: Int
    package var recipients: Int
    package var maxLength: Int
    package var cooldownSeconds: Int
    package var cooldownEndsAt: Date?

    package init(enabled: Bool, price: Int, recipients: Int, maxLength: Int, cooldownSeconds: Int, cooldownEndsAt: Date?) {
        self.enabled = enabled
        self.price = price
        self.recipients = recipients
        self.maxLength = maxLength
        self.cooldownSeconds = cooldownSeconds
        self.cooldownEndsAt = cooldownEndsAt
    }

    /// 지금 남은 쿨타임(초, 올림). 없으면 0.
    package func cooldownRemaining(now: Date) -> Int {
        guard let cooldownEndsAt else { return 0 }
        let left = cooldownEndsAt.timeIntervalSince(now)
        return left > 0 ? Int(left.rounded(.up)) : 0
    }
}

@MainActor
@Observable
package final class MegaphoneStore {
    /// 서버 쿨타임의 설계값(서버가 말해 주기 전의 자리값 — 판정은 서버가 한다).
    package nonisolated static let defaultCooldownSeconds = 600

    /// 네트워크·세션·루비 미러를 빌리는 곳(맥 WorkTimerStore · 폰 MobileGomokuHost). 약참조 — 소유자가 이 스토어를 쥔다.
    @ObservationIgnored package private(set) weak var host: (any GomokuStoreHost)?
    /// 시각(폰 데모·테스트는 주입 시계).
    @ObservationIgnored package var clock: () -> Date = { Date() }
    /// 요청 id 를 만드는 곳(테스트가 바꾼다).
    @ObservationIgnored package var makeRequestID: () -> String = { UUID().uuidString.lowercased() }

    /// 작성 칸(화면이 바인딩한다 — 고칠 때는 `setDraft` 를 지난다).
    package private(set) var draft = ""
    /// 작성 화면이 열려 있는가(맥: 상점 패널 안의 작성기 · 폰: 시트).
    package private(set) var isComposerOpen = false
    /// 2단 확인의 둘째 단계("루비 50개로 N명에게 보낼까요?").
    package private(set) var isConfirming = false
    /// 전송 왕복 중(한 번에 하나 — 두 번째 요청은 만들지 않는다).
    package private(set) var isSending = false
    /// 작성 화면 한 줄(결과·거절). nil = 없음.
    package private(set) var notice: String?
    /// 위 한 줄이 실패인가(빨강) 알림인가.
    package private(set) var noticeIsError = false
    /// 서버가 말해 준 작성 정보. nil = 아직 모른다.
    package private(set) var info: MegaphoneInfo?
    package private(set) var infoLoading = false
    package private(set) var infoFailed = false
    /// 서버에 확성기 함수가 아직 없다(PGRST202 — 앱이 db push 보다 먼저 나간 창).
    package private(set) var serverUnavailable = false
    /// 이 작성의 요청 id. **서버가 답을 준 뒤에만** 버린다(머리말 ①). 테스트가 읽는다.
    package private(set) var pendingRequestID: String?

    @ObservationIgnored private var resetGeneration = 0

    package init(host: (any GomokuStoreHost)? = nil) {
        self.host = host
    }

    /// 소유자가 자기 초기화를 끝낸 뒤 자신을 넘긴다(맥 WorkTimerStore — 저장 프로퍼티를 다 채우기 전에는 self 를 넘길 수 없다).
    package func attach(host: any GomokuStoreHost) {
        self.host = host
    }

    // MARK: 파생값

    /// 지금 쓸 수 있는 길이(서버가 말해 준 값이 이긴다).
    package var maxLength: Int { info?.maxLength ?? MegaphoneBody.maxLength }
    package var draftLength: Int { MegaphoneBody.length(draft) }
    package var isOverLength: Bool { draftLength > maxLength }
    package var counterText: String { MegaphoneText.counter(length: draftLength, maxLength: maxLength) }
    /// 가격(서버 값만 — 모르면 nil, 숫자를 지어내지 않는다).
    package var price: Int? { info?.price }

    /// [보내기](첫 단계)를 누를 수 있는가. 판정의 나머지(쿨타임·잔량·받는 사람)는 누르는 순간 `requestSend` 가 **그때의 시계로** 본다 —
    /// 버튼 잠금을 화면 그리는 시각에 맡기면 쿨타임이 끝난 뒤에도 다시 그려질 때까지 잠겨 있다.
    package var canRequestSend: Bool {
        guard !isSending, host?.session != nil, !serverUnavailable else { return false }
        if case .ok = MegaphoneBody.validate(draft, maxLength: maxLength) { return true }
        return false
    }

    /// 작성 화면 한 줄(정보). 결과 한 줄(`notice`)과 자리를 나눠 쓴다.
    package func infoLine(now: Date) -> String {
        if serverUnavailable { return MegaphoneText.unavailable }
        guard let info else {
            if infoFailed { return MegaphoneText.infoFailed }
            return MegaphoneText.loadingInfo
        }
        if !info.enabled { return MegaphoneText.unavailable }
        let left = info.cooldownRemaining(now: now)
        if left > 0 { return MegaphoneText.cooldown(seconds: left) }
        if info.recipients <= 0 { return MegaphoneText.noRecipients }
        return MegaphoneText.reach(recipients: info.recipients)
    }

    /// 확인 단계의 질문(값을 모르면 nil — 그때는 확인 단계에 들어가지 않는다).
    package var confirmQuestion: String? {
        guard let info else { return nil }
        return MegaphoneText.confirm(price: info.price, recipients: info.recipients)
    }

    // MARK: 화면 사건

    /// 작성 화면을 연다. 글은 남겨 둔다(닫았다 열어도 쓰던 말이 있다) · 확인 단계는 내린다 · 정보를 다시 읽는다.
    /// 결과 한 줄은 **여기서 지우지 않는다** — 보내 놓고 바로 닫은 사람이 다시 열었을 때 그 사이 도착한 결과("보냈어요 · N명에게")를
    /// 봐야 한다. 지난 결과는 닫을 때(`close`) 지운다(상점 안내 문구와 같은 규약).
    package func open() {
        isComposerOpen = true
        isConfirming = false
        loadInfo()
    }

    /// 작성 화면을 닫는다. 왕복 중이면 결과 한 줄을 남겨 둔다(곧 도착할 결과가 들어갈 자리다).
    package func close() {
        isComposerOpen = false
        isConfirming = false
        if !isSending { setNotice(nil) }
    }

    /// 글을 고친다. 고치면 확인 단계는 풀린다(확인한 글과 보낼 글이 달라지면 안 된다) · 지난 결과 한 줄도 내린다.
    package func setDraft(_ text: String) {
        guard draft != text else { return }
        draft = text
        if isConfirming { isConfirming = false }
        if notice != nil { setNotice(nil) }
    }

    /// 첫 단계 [보내기]. **요청을 내지 않는다** — 막을 것을 지금 시계로 보고, 통과하면 확인 단계로 간다.
    package func requestSend() {
        guard !isSending, host?.session != nil else { return }
        if serverUnavailable { setNotice(MegaphoneText.unavailable, error: true); return }
        switch MegaphoneBody.validate(draft, maxLength: maxLength) {
        case .empty: setNotice(MegaphoneText.empty, error: true); return
        case .tooLong(let limit): setNotice(MegaphoneText.tooLong(maxLength: limit), error: true); return
        case .ok: break
        }
        guard let info else {
            // 가격·받는 사람을 모르면 묻지 않는다(확인 질문에 숫자를 지어낼 수 없다). 다시 읽는다.
            setNotice(infoFailed ? MegaphoneText.infoFailed : MegaphoneText.loadingInfo, error: infoFailed)
            loadInfo()
            return
        }
        if !info.enabled { setNotice(MegaphoneText.unavailable, error: true); return }
        let left = info.cooldownRemaining(now: clock())
        if left > 0 { setNotice(MegaphoneText.cooldown(seconds: left), error: true); return }
        if info.recipients <= 0 { setNotice(MegaphoneText.noRecipients, error: true); return }
        if let have = host?.rubyBalance, have < info.price {
            setNotice(MegaphoneText.shortfall(need: info.price, have: have), error: true)
            return
        }
        setNotice(nil)
        isConfirming = true
    }

    package func cancelConfirm() {
        isConfirming = false
    }

    /// 확인 단계 [보내기] — **실제 요청은 여기 하나뿐이다.** 반환: 요청을 띄웠는가.
    @discardableResult
    package func confirmSend() -> Bool {
        guard isConfirming, !isSending, let host, host.session != nil else { return false }
        guard case .ok(let body) = MegaphoneBody.validate(draft, maxLength: maxLength) else {
            isConfirming = false
            return false
        }
        let requestID = pendingRequestID ?? makeRequestID()
        pendingRequestID = requestID
        isSending = true
        setNotice(nil)
        let sessionGeneration = host.sessionGeneration
        let generation = resetGeneration
        let service = host.service
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let response = try await host.withSessionRetry { session in
                    try await service.sendMegaphone(accessToken: session.accessToken, body: body, requestID: requestID)
                }
                guard host.sessionGeneration == sessionGeneration, generation == self.resetGeneration else { return }
                self.isSending = false
                self.apply(response, requestID: requestID)
            } catch {
                guard host.sessionGeneration == sessionGeneration, generation == self.resetGeneration else { return }
                self.isSending = false
                // 취소(창 닫기·세대 교체)는 실패가 아니다 — 문구를 남기지 않는다. id 는 쥔다(서버가 처리했을 수 있다).
                if case .cancelled = host.classifyAuthError(error) { return }
                if MegaphoneSendOutcome(error: error) == .unavailable {
                    // 함수를 못 찾았다 = 서버에서 아무것도 안 돌았다. id 를 버려도 안전하다.
                    self.pendingRequestID = nil
                    self.serverUnavailable = true
                    self.isConfirming = false
                    self.setNotice(MegaphoneText.unavailable, error: true)
                    return
                }
                // 결과를 모른다(오프라인·5xx·응답 해석 실패). **id 를 쥔 채** 확인 단계에 남는다 — 다시 누르면 같은 id 로 묻는다.
                self.setNotice(MegaphoneText.connection, error: true)
            }
        }
        return true
    }

    /// 서버 답(어떤 status 든)을 화면에 옮긴다. 서버가 답을 줬으니 id 는 여기서 버린다.
    package func apply(_ response: MegaphoneSendResponse, requestID: String) {
        if pendingRequestID == requestID { pendingRequestID = nil }
        isConfirming = false
        if let ruby = response.rubyBalance { host?.rubyBalance = ruby }
        let now = clock()
        switch MegaphoneSendOutcome(response: response) {
        case .sent(let recipients, let duplicate):
            draft = ""
            setNotice(duplicate ? MegaphoneText.alreadySent(recipients: recipients) : MegaphoneText.sent(recipients: recipients))
            if var known = info {
                if !duplicate { known.cooldownEndsAt = now.addingTimeInterval(TimeInterval(known.cooldownSeconds)) }
                info = known
            }
            loadInfo()
        case .insufficient(let need, let have):
            setNotice(MegaphoneText.shortfall(need: need, have: have), error: true)
        case .cooldown(let seconds):
            let left = max(1, seconds ?? info?.cooldownSeconds ?? Self.defaultCooldownSeconds)
            if var known = info {
                known.cooldownEndsAt = now.addingTimeInterval(TimeInterval(left))
                info = known
            }
            setNotice(MegaphoneText.cooldown(seconds: left), error: true)
        case .noRecipients:
            if var known = info { known.recipients = 0; info = known }
            setNotice(MegaphoneText.noRecipients, error: true)
        case .empty:
            setNotice(MegaphoneText.empty, error: true)
        case .tooLong(let limit):
            setNotice(MegaphoneText.tooLong(maxLength: limit), error: true)
        case .notText:
            setNotice(MegaphoneText.notText, error: true)
        case .disabled:
            if var known = info { known.enabled = false; info = known }
            setNotice(MegaphoneText.unavailable, error: true)
        case .blackout:
            setNotice(MegaphoneText.blackout, error: true)
        case .unavailable:
            serverUnavailable = true
            setNotice(MegaphoneText.unavailable, error: true)
        case .failed:
            setNotice(MegaphoneText.failed, error: true)
        }
    }

    /// `megaphone_info` 를 읽는다(작성 화면이 열릴 때 · 보낸 뒤). 겹치지 않는다.
    package func loadInfo() {
        guard let host, host.session != nil, !infoLoading else { return }
        infoLoading = true
        let sessionGeneration = host.sessionGeneration
        let generation = resetGeneration
        let service = host.service
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let response = try await host.withSessionRetry { session in
                    try await service.megaphoneInfo(accessToken: session.accessToken)
                }
                guard host.sessionGeneration == sessionGeneration, generation == self.resetGeneration else { return }
                self.infoLoading = false
                self.applyInfo(response)
            } catch {
                guard host.sessionGeneration == sessionGeneration, generation == self.resetGeneration else { return }
                self.infoLoading = false
                if case .cancelled = host.classifyAuthError(error) { return }
                if MegaphoneSendOutcome(error: error) == .unavailable {
                    self.serverUnavailable = true
                    return
                }
                self.infoFailed = true
            }
        }
    }

    /// 정보 응답을 화면 값으로. ok 가 아니면 실패로 센다(숫자를 지어내지 않는다).
    package func applyInfo(_ response: MegaphoneInfoResponse) {
        guard response.status == "ok", let price = response.price, let recipients = response.recipients else {
            infoFailed = true
            return
        }
        let cooldown = response.cooldownSeconds ?? Self.defaultCooldownSeconds
        let left = max(0, response.cooldownRemainingSeconds ?? 0)
        info = MegaphoneInfo(
            enabled: response.enabled ?? true,
            price: price,
            recipients: max(0, recipients),
            maxLength: response.maxLength ?? MegaphoneBody.maxLength,
            cooldownSeconds: cooldown,
            cooldownEndsAt: left > 0 ? clock().addingTimeInterval(TimeInterval(left)) : nil
        )
        infoFailed = false
        serverUnavailable = false
        if let ruby = response.rubyBalance { host?.rubyBalance = ruby }
    }

    /// 로그아웃·계정 전환. 계정에 묶인 값(글·id·정보)을 전부 비우고, 나가 있던 응답은 세대로 버린다.
    package func reset() {
        resetGeneration += 1
        draft = ""
        isComposerOpen = false
        isConfirming = false
        isSending = false
        notice = nil
        noticeIsError = false
        info = nil
        infoLoading = false
        infoFailed = false
        serverUnavailable = false
        pendingRequestID = nil
    }

    private func setNotice(_ text: String?, error: Bool = false) {
        if notice != text { notice = text }
        let isError = text != nil && error
        if noticeIsError != isError { noticeIsError = isError }
    }
}
