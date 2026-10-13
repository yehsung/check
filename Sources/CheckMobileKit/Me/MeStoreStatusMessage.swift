import CheckCore
import CheckMobileShared
import Foundation

/// 상태메시지(v0.3.51 · 폰 나 > 프로필). 사장님 결정: 40자(코드포인트) · 한 줄 · 만료 없음 · 비우면 지움 · 쿨타임 없음.
///
/// 맥 `WorkTimerStoreStatusMessage` 와 같은 규칙이다(문구·정규화·결과 해석은 코어 `StatusMessage`·`StatusMessageText` 한 벌):
///  ① 쓰기는 `set_status_message` RPC 하나 · 내 값 읽기는 **따로 GET**(`fetchMyStatusMessage` — 머리 GET 에 끼우면 칸이 없는
///     옛 서버에서 머리 전체가 죽는다).
///  ② 연타 가드 + 세대 가드 + **쓰기 표**(`statusMessageWriteKey`): 저장이 성공한 뒤 도착한 옛 GET 은 방금 쓴 값을 되돌리지 않는다
///     (별명의 rankme-verify R3 과 같은 경합).
///  ③ 상태는 사람이 쓴 문장이다 — 로그로 흘리지 마라.
extension MeStore {
    package static var statusMessageMaxLength: Int { StatusMessage.maxLength }

    /// 입력칸 카운터(서버와 같은 눈금 — 정규화 후 코드포인트).
    package var statusMessageDraftLength: Int { StatusMessage.length(statusMessageDraft) }

    /// [저장]을 살릴 조건: 왕복 중이 아니고 · 길이 안이고 · 지금 서버값과 다르다(비운 입력은 '지우기'라 값이 있을 때만 다르다).
    package var canSaveStatusMessage: Bool {
        guard !isUpdatingStatusMessage, statusMessageDraftLength <= Self.statusMessageMaxLength else { return false }
        return Self.statusMessageValue(statusMessageDraft) != statusMessage
    }

    /// [지우기]를 보일 조건: 저장된 상태가 있다.
    package var canClearStatusMessage: Bool { statusMessage != nil && !isUpdatingStatusMessage }

    /// 입력 → 보낼 값(nil = 지우기). 보이는 글자가 없으면 지우기로 읽는다(코어 규칙).
    nonisolated static func statusMessageValue(_ raw: String) -> String? {
        if case .ok(let normalized) = StatusMessage.validate(raw) { return normalized }
        return nil
    }

    /// 내 상태메시지 GET. 실패(칸 없는 옛 서버 포함)는 조용히 — 지난 값을 둔다.
    package func loadStatusMessage() async {
        guard context.session.isSignedIn else { return }
        let serial = nextSerial("statusMessage")
        let generation = context.generation
        let stamp = writeStamp(Self.statusMessageWriteKey)
        let service = context.service
        guard case .success(let value) = await attempt({ session in
            try await service.fetchMyStatusMessage(accessToken: session.accessToken, userID: session.userID)
        }) else { return }
        // 이 GET 이 떠 있는 사이 저장이 성공했거나 지금 저장 중이면 이 응답은 옛 값이다 — 버린다.
        guard generation == context.generation, isCurrent("statusMessage", serial), !isUpdatingStatusMessage,
              writeStamp(Self.statusMessageWriteKey) == stamp else { return }
        let previous = statusMessage
        statusMessage = value
        statusMessageLoaded = true
        // 편집 화면이 떠 있고 사용자가 아직 손대지 않았으면(비었거나 옛 값 그대로) 입력을 새 값으로 맞춘다.
        if isProfileVisible, statusMessageDraft.isEmpty || statusMessageDraft == (previous ?? "") {
            statusMessageDraft = value ?? ""
        }
    }

    /// 저장(입력이 비면 지우기). 성공이면 true.
    @discardableResult
    package func saveStatusMessage() async -> Bool {
        guard context.session.isSignedIn, !isUpdatingStatusMessage else { return false }
        let text: String?
        switch StatusMessage.validate(statusMessageDraft) {
        case .ok(let normalized): text = normalized
        case .empty: text = nil
        case .tooLong(let maxLength):
            statusMessageNotice = StatusMessageText.tooLong(maxLength)
            isStatusMessageNoticeError = true
            return false
        }
        isUpdatingStatusMessage = true
        let generation = context.generation
        defer { if generation == context.generation { isUpdatingStatusMessage = false } }
        let service = context.service
        do {
            let outcome = try await context.withMobileSessionRetry { session in
                try await service.setStatusMessage(accessToken: session.accessToken, text: text)
            }
            guard generation == context.generation else { return false }
            let notice = StatusMessageText.notice(for: outcome)
            statusMessageNotice = notice.text
            isStatusMessageNoticeError = notice.isError
            switch outcome {
            case .saved(let stored):
                noteLocalWrite(Self.statusMessageWriteKey)
                statusMessage = stored
                statusMessageLoaded = true
                statusMessageDraft = stored
                return true
            case .cleared:
                noteLocalWrite(Self.statusMessageWriteKey)
                statusMessage = nil
                statusMessageLoaded = true
                statusMessageDraft = ""
                return true
            case .tooLong, .notText, .serverNotReady, .invalid:
                return false
            }
        } catch {
            guard generation == context.generation else { return false }
            if AuthErrorRules.classify(error) == .cancelled { return false }
            statusMessageNotice = StatusMessageText.network
            isStatusMessageNoticeError = true
            return false
        }
    }

    /// [지우기]: 입력을 비우고 곧바로 지운다.
    @discardableResult
    package func clearStatusMessage() async -> Bool {
        guard !isUpdatingStatusMessage else { return false }
        statusMessageDraft = ""
        return await saveStatusMessage()
    }
}
