import CheckCore
import Foundation

// MARK: - 맥 앱스토어 판의 동의 · 계정 삭제 (v0.3.51)
//
// 두 덩어리다.
//  ① **AI 도구 기록 읽기 동의**(앱스토어 판만). 판정은 `aiToolDataAllowed` 하나이고, 토큰 업로드·일별 업로드·스캔 하트비트·
//     배경 스캔·Codex 계정 프로브·리밋 읽기·리밋 값 업로드가 전부 이 값을 본다(스캔 자체의 입구는 `TokenUsageStore.startScan` 이
//     같은 키를 따로 본다 — 두 자리가 같은 키 `AIToolDataConsent.key` 를 읽는다). Developer ID 판은 언제나 참이다.
//  ② **계정 삭제**(두 판 모두 — 심사 지침 5.1.1(v): 앱에서 가입할 수 있으면 앱에서 지울 수도 있어야 한다).
//     폰(`MobileSessionStore.deleteAccount`)과 같은 순서·같은 서버 함수다: 비밀번호로 재로그인 → 사진 → `delete_my_account` →
//     로컬 정리. 재로그인이 실패하면 RPC 를 부르지 않는다(잠금 풀린 맥을 집은 사람이 로그인 상태만으로 계정을 못 지운다).

/// 계정 삭제 화면의 문구 한 벌. **순수 값이라 테스트가 글자 그대로 되묻는다** — 폰의 문장(`MeText`)과 같은 결이고,
/// 다른 것은 "아이폰 앱도 같이 로그아웃돼요"(폰은 "맥 앱도") 한 줄뿐이다.
enum AccountDeletionText {
    /// 설정 '내 정보' 머리 줄의 링크 · 이 화면의 제목.
    static let entry = "계정 삭제"
    static let title = "계정 삭제"
    static let lede = "이 계정의 모든 것이 서버에서 지워져요."
    /// 지워지는 것(서버 계약 — FK cascade). 순서는 사용자가 아까워할 것부터(폰과 같다).
    static let items = ["근무 기록", "메시지", "할 일", "캐릭터와 루비", "순위 기록"]
    static let irreversible = "되돌릴 수 없어요. 아이폰 앱도 같이 로그아웃돼요."
    /// 제보는 `feedback_reports.user_id` 가 set null 이라 내용만 익명으로 남는다(서버 계약). 숨기지 않고 밝힌다.
    static let feedbackNote = "보낸 제보는 작성자 없이 내용만 남아요."
    static let passwordPrompt = "비밀번호 확인"
    static let passwordHelp = "본인 확인을 위해 비밀번호를 다시 입력해 주세요."
    /// 1단계 버튼. 누르면 같은 자리가 [취소]+[영구 삭제]로 바뀐다(설정 창의 2단 확인 관례 — 사진 되돌리기·차단 해제).
    static let action = "계정 삭제"
    static let confirmQuestion = "정말 지울까요? 누르면 바로 지워지고 되돌릴 수 없어요."
    static let confirm = "영구 삭제"
    static let cancel = "취소"
    static let inFlight = "지우는 중…"
    static let back = "설정으로"

    static let signedOut = "로그인하면 계정을 지울 수 있어요"
    static let passwordRequired = "비밀번호를 입력해 주세요"
    static let emailUnknown = "로그인 이메일을 알 수 없어요 — 로그아웃한 뒤 다시 로그인해서 시도해 주세요"
    static let wrongPassword = "비밀번호가 맞지 않아요"
    static let accountMismatch = "지금 로그인한 계정과 다른 계정이에요 — 로그아웃한 뒤 다시 시도해 주세요"
    static let network = "연결을 확인한 뒤 다시 시도해 주세요"
    /// 앱이 서버 배포보다 먼저 나간 창 — "고장"이 아니라 "아직"이라고 말한다(폰과 같은 문장).
    static let serverNotReady = "계정 삭제가 아직 서버에 준비되지 않았어요 — 잠시 뒤 다시 시도하거나 제보로 알려 주세요"
    static let rejected = "계정을 지우지 못했어요 — 잠시 뒤 다시 시도해 주세요"
}

extension WorkTimerStore {
    /// 로그인 화면 상태줄에 남기는 결과 한 줄(삭제가 끝나면 설정 화면이 사라지고 로그인 화면이 선다).
    /// `AuthMessageKind` 가 이 상수를 **성공**으로 분류한다 — 없으면 기본값(빨간 경고)으로 그려진다.
    static let accountDeletedMessage = "계정을 지웠어요"

    // MARK: AI 도구 기록 읽기 동의

    /// 지금 AI 도구 기록을 읽고 그 숫자를 올려도 되는가. **Developer ID 판은 언제나 참**(지금 동작 그대로)이고,
    /// 앱스토어 판은 사용자가 첫 실행 안내나 설정에서 켰을 때만 참이다.
    ///
    /// 물러난 실행(v0.3.53 — 같은 맥에 설치된 앱스토어 판이 있다)은 판과 무관하게 **거짓**이다. 이 값 하나가 토큰 스캔·업로드·
    /// 일별 업로드·스캔 하트비트·Codex 계정 프로브·리밋 읽기를 함께 막는다(그 판에는 이 갈래가 없다).
    var aiToolDataAllowed: Bool {
        #if !CHECK_MAS
        if retiredForAppStoreEdition { return false }
        #endif
        return !macEdition.asksBeforeReadingAITools || aiToolDataConsent
    }

    /// 앱스토어 판의 동의 스위치. 첫 실행 안내의 [허용]/[나중에]와 설정 스위치가 **이 함수만** 부른다.
    ///
    /// 끄면: 키를 내리고(토큰 스캐너가 같은 키를 본다), 리밋 축을 **마스터 끄기**로 잠재운다 — 끄기는 그 순간 올라가 있던 리밋 행을
    /// 비우는 행으로 덮으므로(`setAILimitsVisible`) 폰·위젯에서도 사라진다. 그때 마스터가 켜져 있었다는 사실을 따로 적어 둔다.
    /// 켜면: 동의 때문에 꺼 둔 마스터만 되살린다(사용자가 원래 꺼 둔 마스터는 건드리지 않는다). 그 사이 사용자가 설정에서 마스터를
    /// 직접 만졌으면 표식이 지워져 있어(`setAILimitsVisible` 가 지운다) 그 선택을 덮지 않는다.
    /// Developer ID 판에서는 아무 일도 하지 않는다(그 판에는 이 스위치가 없다).
    ///
    /// ★ 마스터를 바꾸는 길은 설정 스위치와 **같은 문**(`setAILimitsVisible`) 하나다 — 따로 `aiLimits` 를 만지면 "끈 순간 서버 행을
    ///   비운다"가 빠진다(V0347 의 호출 지점 계약이 이 파일의 한 자리를 함께 센다).
    func setAIToolDataConsent(_ granted: Bool) {
        guard macEdition.asksBeforeReadingAITools else { return }
        defaults.set(granted, forKey: AIToolDataConsent.key)
        guard aiToolDataConsent != granted else { return }
        aiToolDataConsent = granted
        let pausedByConsent = defaults.bool(forKey: Self.aiLimitsPausedByConsentKey)
        let master: Bool?
        if granted {
            master = pausedByConsent ? true : nil
        } else {
            master = aiLimits.visibility.masterEnabled ? false : nil
        }
        guard let master else { return }
        setAILimitsVisible(master)
        if !master { defaults.set(true, forKey: Self.aiLimitsPausedByConsentKey) }
    }

    /// 동의를 거두면서 리밋 마스터를 **우리가** 껐다는 표식(켜면 그것만 되살린다).
    static let aiLimitsPausedByConsentKey = "check.mas.aiLimitsPausedByConsent"

    // MARK: 계정 삭제

    /// 설정 → [계정 삭제]를 연다(본문 자리 바꿈). 로그인 전이면 열지 않는다(지울 계정이 없다).
    func openAccountDeletionSettings() {
        guard session != nil else { return }
        resetAccountDeletionState()
        showsAccountDeletionInSettings = true
    }

    /// 설정 본문으로 돌아간다(설정 창이 열릴 때·닫힐 때도 부른다 — 다시 열면 본문부터, 비밀번호 칸은 비어 있다).
    /// 삭제 왕복이 도는 동안에는 닫지 않는다(닫힌 뒤 성공하면 사용자가 왜 로그인 화면인지 모른다).
    func closeAccountDeletionSettings() {
        guard !isDeletingAccount else { return }
        if showsAccountDeletionInSettings { showsAccountDeletionInSettings = false }
        resetAccountDeletionState()
    }

    private func resetAccountDeletionState() {
        if !accountDeletionPassword.isEmpty { accountDeletionPassword = "" }
        if isConfirmingAccountDeletion { isConfirmingAccountDeletion = false }
        if accountDeletionNotice != nil { accountDeletionNotice = nil }
    }

    /// [영구 삭제]를 누를 수 있는가(버튼 활성 전용 — 막는 일은 `deleteMyAccount` 가 한 번 더 한다).
    var canDeleteAccount: Bool {
        session != nil && !accountDeletionPassword.isEmpty && !isDeletingAccount
    }

    /// **계정을 영구 삭제한다**(심사 지침 5.1.1(v)). 성공하면 true — 로그인 화면으로 돌아가 있다.
    ///
    /// 순서가 계약이다(폰 `MobileSessionStore.deleteAccount` 와 같다):
    ///  1. 재로그인 — 저장된 로그인 이메일 + 입력한 비밀번호로 `signIn` 한 번. 실패하면 **RPC 를 부르지 않는다.**
    ///     받은 세션의 userID 가 지금 계정과 다르면 거기서 멈춘다(엉뚱한 계정을 지우지 않는다).
    ///  2. 프로필 사진 — 서버 함수가 Storage 를 못 지워 `avatars/<uid>.jpg` 가 남는다. 실패는 무시한다(사진 한 장이 계정 삭제를
    ///     막으면 '앱 안에서 지울 수 있다'가 통째로 깨진다).
    ///  3. `delete_my_account` — 재로그인으로 받은 **새 토큰**으로(방금 발급돼 401 재시도가 필요 없다).
    ///  4. 성공하면 로그아웃과 같은 로컬 정리 — 서버에 로그아웃을 알리지 않는다(세션이 cascade 로 이미 없다). 로그인 이메일·
    ///     표시 이름도 잊는다(지운 계정의 이메일이 로그인 칸에 남지 않게). 실패하면 로그인 상태를 **그대로** 두고 이유를 말한다.
    /// 재로그인이 만든 두 번째 서버 세션은 RPC 가 실패했을 때 닫는다(성공했으면 cascade 로 이미 없다).
    @discardableResult
    func deleteMyAccount() async -> Bool {
        guard let current = session else {
            accountDeletionNotice = AccountDeletionText.signedOut
            return false
        }
        guard !isDeletingAccount else { return false }
        let password = accountDeletionPassword
        guard !password.isEmpty else {
            accountDeletionNotice = AccountDeletionText.passwordRequired
            return false
        }
        let loginEmail = (defaults.string(forKey: Self.emailKey) ?? email).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !loginEmail.isEmpty else {
            accountDeletionNotice = AccountDeletionText.emailUnknown
            return false
        }
        isDeletingAccount = true
        defer { isDeletingAccount = false }
        accountDeletionNotice = nil
        let generation = sessionGeneration

        let reauth: SupabaseSession
        do {
            reauth = try await service.signIn(email: loginEmail, password: password)
        } catch {
            guard generation == sessionGeneration else { return false }
            switch classifyAuthError(error) {
            case .cancelled, .transient:
                accountDeletionNotice = AccountDeletionText.network
            case .fatal:
                accountDeletionNotice = (error as? SupabaseWorkServiceError) == .invalidLoginCredentials
                    ? AccountDeletionText.wrongPassword
                    : authMessage(for: error, fallback: AccountDeletionText.rejected)
            }
            return false
        }
        // 그 사이 로그아웃·계정 전환이 있었거나, 재로그인이 다른 계정을 가리키면 **지우지 않는다** — 재로그인 세션만 닫는다.
        guard generation == sessionGeneration, reauth.userID == current.userID else {
            await service.signOut(accessToken: reauth.accessToken)
            if generation == sessionGeneration { accountDeletionNotice = AccountDeletionText.accountMismatch }
            return false
        }

        await service.deleteAvatarIfAny(accessToken: reauth.accessToken, userID: reauth.userID)

        do {
            try await service.deleteMyAccount(accessToken: reauth.accessToken)
        } catch {
            await service.signOut(accessToken: reauth.accessToken)
            guard generation == sessionGeneration else { return false }
            if let serviceError = error as? SupabaseWorkServiceError, BlockReportRules.isMissingFunction(serviceError) {
                accountDeletionNotice = AccountDeletionText.serverNotReady
                return false
            }
            switch classifyAuthError(error) {
            case .cancelled, .transient:
                accountDeletionNotice = AccountDeletionText.network
            case .fatal:
                accountDeletionNotice = AccountDeletionText.rejected
            }
            return false
        }

        // 서버가 지웠다. 그 사이 세대가 바뀌었으면(이미 로그아웃) 로컬은 이미 비었다 — 다시 비우지 않는다.
        guard generation == sessionGeneration else { return true }
        showsAccountDeletionInSettings = false
        resetAccountDeletionState()
        signOut(notifyServer: false)
        email = ""
        defaults.removeObject(forKey: Self.emailKey)
        displayName = ""
        defaults.removeObject(forKey: Self.displayNameKey)
        syncMessage = Self.accountDeletedMessage
        return true
    }
}
