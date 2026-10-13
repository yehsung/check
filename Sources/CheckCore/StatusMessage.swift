import Foundation

// v0.3.51 · 상태메시지(사장님 결정 2026-10-14): 40자(코드포인트) · 한 줄 · 맥과 폰. 만료 없음 · 비우면 지움 · 쿨타임 없음.
//
// 서버 정본은 `supabase/migrations/20261014121000_status_message.sql` 의 `set_status_message` 다. 여기 있는 것은
//   ① 입력 카운터("n/40")와 저장 게이트가 서버와 **같은 눈금**으로 세게 하는 정규화(서버 ①②③ 을 글자 집합까지 그대로),
//   ② 남의 상태를 화면에 올리기 전에 거르는 관문(display),
//   ③ RPC 응답 → 결과 · 안내 문구(맥·폰이 같은 말을 한다).
// 판정의 최종 권위는 서버다(글자 규칙 not_text 는 클라가 흉내 내지 않는다 — 두 벌이면 갈린다, MessageBody 와 같은 규약).

/// 상태메시지 입력의 사전 판정 결과. `.empty` 는 **지우기**다(사장님: 비우면 지움) — 오류가 아니다.
package enum StatusMessageValidation: Equatable, Sendable {
    /// 실제로 보낼 문자열(정규화 완료). 원문이 아니라 이 값을 보낸다.
    case ok(String)
    /// 비었거나 눈에 보이는 글자가 없다 → 지운다.
    case empty
    case tooLong(maxLength: Int)
}

package enum StatusMessage {
    /// 상한. **단위는 유니코드 스칼라(코드포인트)** — 서버 `char_length` · `status_message_max_length()` 와 같은 눈금이다.
    package static var maxLength: Int { CheckCoreShared.statusMessageMaxLength }

    /// 줄바꿈류: 이것이 **하나라도 든** 공백·줄바꿈류 묶음은 공백 하나로 접힌다(서버 ②).
    /// 서버 식 `[\0009\000a\000b\000c\000d\0085\2028\2029]` 와 같은 집합이다 — 하나를 바꾸면 둘 다 바꿔라.
    private static let lineBreakScalars: Set<UInt32> = [0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x85, 0x2028, 0x2029]
    /// 앞뒤에서 지우는 글자(서버 ③ btrim 집합). Foundation 의 `.whitespacesAndNewlines` 를 쓰지 않는 이유: 집합이 다르다
    /// (그쪽은 U+2002 같은 폭 있는 공백을 지우고 ZWSP·BOM 은 안 지운다) — 그러면 카운터와 서버가 한 글자씩 갈린다.
    private static let trimScalars: Set<UInt32> = [0x20, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0xA0, 0x200B, 0xFEFF, 0x3000]

    /// 사용자 입력 → 서버가 저장할 문자열과 같은 값(서버 정규화 ①②③).
    ///   ① NFC(맥 한글 입력기·파인더 붙여넣기의 자모 분해를 합친다 — 안 합치면 '한글'이 6자로 세어진다)
    ///   ② 줄바꿈류가 든 공백·줄바꿈류의 최대 묶음 → 공백 하나(줄바꿈 없는 두 칸 공백은 그대로)
    ///   ③ 앞뒤 공백류 제거
    package static func sanitized(_ raw: String) -> String {
        let scalars = Array(raw.precomposedStringWithCanonicalMapping.unicodeScalars)
        var folded = String.UnicodeScalarView()
        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            let isSpace = scalar.value == 0x20
            let isBreak = lineBreakScalars.contains(scalar.value)
            guard isSpace || isBreak else {
                folded.append(scalar)
                index += 1
                continue
            }
            // 공백·줄바꿈류의 최대 묶음을 하나로 본다.
            var end = index
            var hasBreak = false
            while end < scalars.count, scalars[end].value == 0x20 || lineBreakScalars.contains(scalars[end].value) {
                if lineBreakScalars.contains(scalars[end].value) { hasBreak = true }
                end += 1
            }
            if hasBreak {
                folded.append(" ")
            } else {
                folded.append(contentsOf: scalars[index..<end])
            }
            index = end
        }
        var view = Array(folded)
        while let first = view.first, trimScalars.contains(first.value) { view.removeFirst() }
        while let last = view.last, trimScalars.contains(last.value) { view.removeLast() }
        var result = String.UnicodeScalarView()
        result.append(contentsOf: view)
        return String(result)
    }

    /// 서버와 같은 눈금의 길이(정규화 후 코드포인트 수). 카운터 "n/40" 이 이 값을 쓴다.
    package static func length(_ raw: String) -> Int { sanitized(raw).unicodeScalars.count }

    /// 저장 전 사전 판정. 빈 판정이 먼저다(공백만 41자 친 입력에 "40자까지예요"라고 하지 않는다).
    /// 보이는 글자 판정은 메시지와 같은 함수다(한글 채움 U+3164 같은 폭 0 '글자'만 있으면 빈 것으로 본다 → 지우기).
    package static func validate(_ raw: String) -> StatusMessageValidation {
        let normalized = sanitized(raw)
        if normalized.isEmpty || !MessageBody.hasVisibleContent(normalized) { return .empty }
        if normalized.unicodeScalars.count > maxLength { return .tooLong(maxLength: maxLength) }
        return .ok(normalized)
    }

    /// 남의(또는 내) 상태를 **화면에 올리기 전** 관문. nil · 빈 값 · 보이는 글자 없는 값은 nil(줄을 안 그린다).
    /// 서버가 이미 정규화해 저장하지만, 운영자 SQL 로 들어간 값이나 옛 서버의 이상한 값이 줄을 비워 그리지 않게 한 번 더 접는다.
    package static func display(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let normalized = sanitized(raw)
        guard !normalized.isEmpty, MessageBody.hasVisibleContent(normalized) else { return nil }
        return normalized
    }

    /// 입력칸 카운터 문구("12/40").
    package static func counterText(_ raw: String) -> String { "\(length(raw))/\(maxLength)" }
}

// MARK: - 전선 위 모양

/// `set_status_message(p_text text default null)` 요청. **p_text 키를 언제나 싣는다**(nil 이면 JSON null) —
/// PostgREST 는 본문의 키 집합으로 함수를 고르므로, 지우기를 `{}` 로 보내면 서버 기본값에 기대게 된다. 기본값이 바뀌는 날
/// 지우기가 조용히 다른 뜻이 되지 않게 키를 명시한다(SetCharacterRequest 와 같은 관용구).
package struct SetStatusMessageRequest: Encodable, Equatable {
    package let pText: String?

    package init(pText: String?) { self.pText = pText }

    /// 카멜로 적는다 — 인코더가 `.convertToSnakeCase` 로 `p_text` 를 만든다.
    package enum CodingKeys: String, CodingKey { case pText }

    package func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(pText, forKey: .pText)   // encodeIfPresent 가 아니다 — 위 주석.
    }
}

/// set_status_message 응답: { status: ok|cleared|too_long|not_text|unauthorized, status_message?, max_length? }.
package struct SetStatusMessageResponse: Decodable, Equatable {
    package let status: String
    package var statusMessage: String?
    package var maxLength: Int?

    package init(status: String, statusMessage: String? = nil, maxLength: Int? = nil) {
        self.status = status
        self.statusMessage = statusMessage
        self.maxLength = maxLength
    }

    package enum CodingKeys: String, CodingKey { case status, statusMessage, maxLength }

    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = try c.decode(String.self, forKey: .status)
        statusMessage = try c.decodeIfPresent(String.self, forKey: .statusMessage)
        maxLength = try c.decodeIfPresent(Int.self, forKey: .maxLength)
    }
}

/// 내 상태메시지 GET 의 1칸 행(`profiles?select=status_message&id=eq.<me>`). **별도 GET 이다** — 기존 select 에 끼우면
/// 칸이 없는 서버에서 42703 으로 그 요청 전체가 죽는다(ProfileCenterRow 와 같은 규약).
package struct ProfileStatusMessageRow: Decodable, Equatable {
    package let statusMessage: String?
}

/// 저장 결과(스토어·화면 공유). 모르는 status 는 `.invalid` 로 접는다.
package enum StatusMessageSaveOutcome: Equatable, Sendable {
    /// 저장됐다 — 값은 **서버가 저장한 문자열**이다(정규화 결과). 화면은 이 값을 그대로 쓴다.
    case saved(String)
    case cleared
    case tooLong(maxLength: Int)
    case notText
    /// 서버에 함수가 아직 없다(PGRST202 · 404 — db push 전 창).
    case serverNotReady
    /// unauthorized · 모르는 status.
    case invalid

    package init(response: SetStatusMessageResponse) {
        switch response.status {
        case "ok":
            // ok 인데 값이 없거나 비면 서버가 지운 것과 같다(그럴 일은 없지만 빈 줄을 그리지 않는다).
            if let stored = StatusMessage.display(response.statusMessage) {
                self = .saved(stored)
            } else {
                self = .cleared
            }
        case "cleared":
            self = .cleared
        case "too_long":
            self = .tooLong(maxLength: response.maxLength ?? StatusMessage.maxLength)
        case "not_text":
            self = .notText
        default:
            self = .invalid
        }
    }
}

/// 맥·폰이 같이 쓰는 문구(짧은 해요체 — 별명 안내와 같은 결).
package enum StatusMessageText {
    package static let title = "상태메시지"
    package static let placeholder = "지금 어떤지 한 줄로 남겨요"
    package static let save = "저장"
    package static let clear = "지우기"
    package static let saved = "상태메시지를 바꿨어요"
    package static let cleared = "상태메시지를 지웠어요"
    package static let notText = "쓸 수 없는 글자가 있어요"
    package static let invalid = "지금은 상태메시지를 바꿀 수 없어요"
    package static let serverNotReady = "상태메시지는 서버 준비가 끝나면 쓸 수 있어요"
    package static let network = "연결이 불안정해요. 잠시 후 다시 시도해 주세요"
    /// 기본 안내 한 줄. **맥 설정 행에서 한 줄에 들어야 한다**(카드 안쪽 폭 328 · caption2 · 카운터 포함) — 줄이 늘면 설정 창 높이 계약이 흔들린다.
    package static let hint = "다른 사람에게 보여요 · 비우면 지워져요"

    package static func tooLong(_ maxLength: Int) -> String { "상태메시지는 \(maxLength)자까지 쓸 수 있어요" }

    /// 결과 → (문구, 오류 여부). 성공·지움은 오류가 아니다.
    package static func notice(for outcome: StatusMessageSaveOutcome) -> (text: String, isError: Bool) {
        switch outcome {
        case .saved: return (saved, false)
        case .cleared: return (cleared, false)
        case .tooLong(let maxLength): return (tooLong(maxLength), true)
        case .notText: return (notText, true)
        case .serverNotReady: return (serverNotReady, true)
        case .invalid: return (invalid, true)
        }
    }
}
