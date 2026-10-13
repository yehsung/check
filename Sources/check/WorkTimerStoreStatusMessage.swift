import Foundation
import CheckCore

// MARK: - 상태메시지 (v0.3.51 · 맥)
//
// 사장님 결정(2026-10-14): 40자(코드포인트) · 한 줄 · 만료 없음 · 비우면 지움 · 쿨타임 없음. 맥은 설정 창 '내 정보'의 별명 옆에서 고친다.
// 남의 상태는 콕 찌르기 목록 행(두 번째 줄)과 1:1 대화 머리(이름 아래)에 보인다 — 둘 다 `app_user_directory` 의 마지막 칸이고,
// 그 목록은 팝오버가 콕 화면을 보여 주는 동안 30초마다 다시 받는다(새 요청 0).
//
// ── 이 파일이 지키는 것 ──
// ① 쓰기는 `set_status_message` RPC 하나다(서버가 update grant 를 안 준다 — PATCH 는 403).
// ② 내 값 읽기는 **따로 GET** 이다(`fetchMyStatusMessage`). 설정 GET 에 끼우면 칸이 없는 옛 서버에서 42703 으로 토큰·집중 모드
//    설정까지 같이 죽는다(소속 센터와 같은 규약).
// ③ 연타 가드 + 세대 가드: 저장 왕복 중에는 다시 안 보내고, 로그아웃 뒤 도착한 응답은 다음 계정의 미러·문구를 건드리지 않는다.
// ④ 서버가 아직 없는 창(앱이 db push 보다 먼저 나간 창)에서는 "고장"이 아니라 "준비가 끝나면"이라고 말한다(`.serverNotReady`).
// ⑤ 상태는 사람이 쓴 문장이다. `print`/`Logger` 로 흘리지 마라(메시지 파일 공통 규약).
// ⑥ 내 값은 폰에서도 바뀐다. 설정 창을 열 때마다 다시 받는다(`refreshMyStatusMessageForSettings`) — 세션당 한 번만 받으면
//    폰에서 바꾼 상태가 맥 설정 행에 영영 안 보이고 [저장]까지 잠긴다(검토 지적, v0.3.51).
extension WorkTimerStore {
    /// 상태메시지 최대 길이(코드포인트). 코어 상수로 가는 얇은 전달 — 설정 행 카운터가 이 이름으로 읽는다.
    static var statusMessageMaxLength: Int { StatusMessage.maxLength }

    /// 내 상태메시지를 **아직 모를 때만** 서버에서 받아 온다(로그인 뒤 설정 로드 체인 — 세션당 한 번 돈다).
    ///
    /// 실패와 '없음'을 가르는 것이 요점이다(`loadMyCenterIfNeeded` 와 같은 관용구): 실패면 플래그를 안 세워 다음 기회에 다시 묻고,
    /// 성공이면 값이 nil 이어도(= 상태를 안 쓴 사람) 플래그를 세운다. `try?` 를 쓰지 않는 이유가 그것이다 — 두 nil 이 뭉개진다.
    func loadMyStatusMessageIfNeeded() async {
        guard !myStatusMessageLoaded else { return }
        await fetchMyStatusMessageFromServer()
    }

    /// 설정 창을 **열 때마다** 부른다(`CheckSettingsWindowController.show()`). 받아 둔 값이 있어도 다시 묻는다.
    ///
    /// ★ 왜 '모를 때만'으로는 안 되는가: 같은 계정이 폰(나 > 프로필)에서도 상태를 고친다. 맥이 세션당 한 번만 받으면 폰에서 바꾼 값이
    ///   맥 설정 행에 영영 안 보이고, 낡은 미러 때문에 [저장]이 잠겨(같은 값으로 보인다) 맥에서 옛 문장을 다시 올릴 수도 없다.
    ///   설정 행의 `onAppear` 는 이 자리가 못 된다 — 이 창은 닫아도 뷰가 붙어 있어 onAppear 가 창 수명에 한 번뿐이다(실측 2026-09-15).
    /// 지난 결과 한 줄(저장했어요 등)도 여기서 접는다 — 폰에서 값이 바뀐 뒤라면 그 문장은 이미 거짓이다(폰은 화면을 떠날 때 접는다).
    func refreshMyStatusMessageForSettings() {
        if !isUpdatingStatusMessage {
            statusMessageNotice = nil
            isStatusMessageNoticeError = false
        }
        guard session != nil else { return }
        Task { @MainActor in await self.fetchMyStatusMessageFromServer() }
    }

    /// 내 값 GET 한 번. 실패는 조용히 지나간다 — 플래그·미러를 안 바꾸므로 설정 창을 다시 열 때(또는 로그인 체인이 다시 돌 때) 또 묻는다.
    /// 칸이 없는 옛 서버(42703)도 여기로 온다.
    ///
    /// 버리는 응답 셋: 세대가 바뀌었다(로그아웃) · 뒤에 나간 GET 이 있다(순번) · 이 GET 이 떠 있는 사이 저장이 나갔거나 지금 나가 있다
    /// (저장 전의 값이다 — 방금 쓴 문장을 되돌리면 안 된다).
    func fetchMyStatusMessageFromServer() async {
        guard session != nil, !isUpdatingStatusMessage else { return }
        statusMessageFetchSerial &+= 1
        let serial = statusMessageFetchSerial
        let writeSerial = statusMessageWriteSerial
        let generation = sessionGeneration
        do {
            let serverValue = try await withSessionRetry { activeSession in
                try await service.fetchMyStatusMessage(accessToken: activeSession.accessToken, userID: activeSession.userID)
            }
            guard generation == sessionGeneration,
                  serial == statusMessageFetchSerial,
                  writeSerial == statusMessageWriteSerial,
                  !isUpdatingStatusMessage else { return }
            if myStatusMessage != serverValue { myStatusMessage = serverValue }
            myStatusMessageLoaded = true
        } catch {
            // 조용히 무시한다 — 위 머리말.
        }
    }

    /// 상태메시지를 저장한다(빈 입력 = 지우기). 성공하면 true.
    ///
    /// 사전 판정(`StatusMessage.validate`)은 헛왕복을 줄이는 장치이고 최종 판정은 서버다 — 글자 규칙(not_text)은 서버만 안다.
    /// 성공하면 **서버가 저장한 값**으로 미러를 맞춘다(정규화 결과가 입력과 다를 수 있다: NFC · 줄바꿈 접기 · 앞뒤 공백).
    @discardableResult
    func updateStatusMessage(_ raw: String) async -> Bool {
        // 연타 가드 — 저장 왕복 중에 두 번째 요청이 나가면 늦게 온 쪽이 방금 세운 결과 문구를 덮는다.
        guard session != nil, !isUpdatingStatusMessage else { return false }
        let text: String?
        switch StatusMessage.validate(raw) {
        case .ok(let normalized):
            text = normalized
        case .empty:
            text = nil   // 비우면 지움(사장님). 보이는 글자 없는 입력(한글 채움 등)도 지우기로 읽는다.
        case .tooLong(let maxLength):
            statusMessageNotice = StatusMessageText.tooLong(maxLength)
            isStatusMessageNoticeError = true
            return false
        }
        // 이미 같은 값이면 왕복하지 않는다(서버에도 바뀔 것이 없다). 받아 둔 값이 있을 때만 이 판정을 믿는다 —
        // 그 값은 설정 창을 열 때마다 새로 받는다(⑥). 창을 연 채 폰에서 바꾼 값은 창을 다시 열어야 보인다(폴링 없음).
        if myStatusMessageLoaded, text == myStatusMessage {
            statusMessageNotice = nil
            isStatusMessageNoticeError = false
            return true
        }
        isUpdatingStatusMessage = true
        // 떠 있는 GET 은 이제 저장 전의 값이다 — 도착해도 버리게 표를 올린다(실패한 저장도 서버에 닿았을 수 있다).
        statusMessageWriteSerial &+= 1
        let generation = sessionGeneration
        defer {
            // 로그아웃으로 세대가 바뀌었으면 리셋이 이미 내렸다 — 다음 계정의 왕복 중 표시를 건드리지 않는다.
            if generation == sessionGeneration { isUpdatingStatusMessage = false }
        }
        do {
            let outcome = try await withSessionRetry { activeSession in
                try await service.setStatusMessage(accessToken: activeSession.accessToken, text: text)
            }
            guard generation == sessionGeneration else { return false }
            let notice = StatusMessageText.notice(for: outcome)
            statusMessageNotice = notice.text
            isStatusMessageNoticeError = notice.isError
            switch outcome {
            case .saved(let stored):
                if myStatusMessage != stored { myStatusMessage = stored }
                myStatusMessageLoaded = true
                return true
            case .cleared:
                if myStatusMessage != nil { myStatusMessage = nil }
                myStatusMessageLoaded = true
                return true
            case .tooLong, .notText, .serverNotReady, .invalid:
                return false
            }
        } catch {
            guard generation == sessionGeneration else { return false }
            if case .cancelled = classifyAuthError(error) { return false }
            statusMessageNotice = StatusMessageText.network
            isStatusMessageNoticeError = true
            return false
        }
    }
}
