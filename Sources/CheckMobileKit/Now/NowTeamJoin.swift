import CheckCore
import CheckMobileShared
import Foundation
import Observation

/// '지금' 탭 무소속 카드의 팀 합류·만들기(w16 검증 high 수리).
///
/// **왜 여기 있나.** 폰에서 팀에 들어갈 길이 가입 화면 하나뿐이었다. 로그인 화면의 "이메일 확인 필요" 출구로 들어온 사람은
/// 팀 칸을 채운 적이 없어 인증만 끝내고 무소속으로 떨어지고, 가입 도중(인증 성공 ~ 팀 합류 전) 앱을 껐던 사람과 맥에서
/// 가입만 해 둔 사람도 같은 자리에 선다. 그 사람들에게 '지금' 탭은 "맥 앱에서 팀에 참여하면 …"이라고만 말했다 —
/// 맥이 없는 앱스토어 사용자에게는 **로그인은 되는데 아무것도 없는 앱**이다.
///
/// **규칙은 새로 쓰지 않았다.** 왕복(`lookup_team_by_code` → `join_team`/`create_team`) · 가드 · 문구는 가입 화면과
/// 한 벌(`MobileTeamJoinForm` · `MobileSignUpText`)이다. 여기서 정하는 것은 **이 화면이 그 결과로 무엇이 되는가**뿐이다.
///
/// **역할(role)은 지어내지 않는다.** 합류·생성이 끝나면 소속을 서버에서 다시 읽는다(맥 `confirmMembership` 과 같은 규칙) —
/// `join_team`/`create_team` 은 역할을 돌려주지 않아서, 추측해 넣으면 팀장 아닌 사람이 한 왕복 동안 팀장으로 보인다.
/// 그 사이 무소속 카드는 내린다(`NowStore.isSettlingTeam`) — 방금 들어간 사람이 코드를 또 치게 두지 않는다.
@MainActor
@Observable
package final class NowTeamJoinStore {
    /// 팀 칸 한 벌(코드 ↔ 만들기 · 미리보기). 화면이 바인딩한다.
    @ObservationIgnored package let form: MobileTeamJoinForm
    /// 카드 한 줄(가드 이유 · 실패 원인) — **여기 서는 문구는 전부 거절·실패라 늘 오류색이다**(성공하면 카드가 사라진다).
    /// 미리보기 문구는 `previewLine` 으로 따로 간다(코드 칸 바로 아래).
    package private(set) var notice: String?
    package private(set) var isSubmitting = false

    @ObservationIgnored private let context: MobileContext
    /// 팀이 정해졌다 — 지금 탭이 받아 소속을 다시 읽는다.
    @ObservationIgnored package var onTeamSettled: (() -> Void)?
    /// 제출 왕복 세대(늦은 응답 버리기). 계정 세대(`context.generation`)와 따로 센다 — 같은 계정 안에서도 겹칠 수 있다.
    @ObservationIgnored private var submitGeneration = 0

    package init(context: MobileContext) {
        self.context = context
        self.form = MobileTeamJoinForm(service: context.service)
    }

    // MARK: - 화면이 읽는 값

    package var previewLine: (text: String, isSuccess: Bool)? { form.previewLine }

    /// 주 버튼 글자. 만들기 모드는 "새 팀 만들기" — 가입 화면의 "팀 만들고 시작하기"는 계정을 막 만든 자리의 말이라 여기선 쓰지 않는다
    /// (둘 다 `MobileSignUpText` 의 있는 문구다 — 새로 짓지 않았다).
    package var primaryTitle: String {
        form.isCreateTeamMode ? MobileSignUpText.switchToCreate : MobileSignUpText.join
    }

    /// 주 버튼을 **켜 둘** 수 있는가. 막는 일은 `submit()` 의 가드가 한다 — 비활성만 두면 왜 막혔는지 말할 기회가 없다
    /// (가입 화면 `canSubmit` 과 같은 이유: 키보드 제출 경로가 따로 있다).
    package var canSubmit: Bool {
        !isSubmitting && context.session.isSignedIn && form.isPrepared
    }

    // MARK: - 입력

    package func toggleCreateTeamMode() {
        form.toggleCreateTeamMode()
        notice = nil
    }

    /// 화면을 떠날 때. 날아가 있는 미리보기만 끊는다(친 값은 그대로 — 돌아오면 이어서 친다).
    package func cancelPendingWork() {
        form.cancelPendingPreview()
    }

    /// 로그아웃·계정 전환. 앞 사람의 코드·팀 이름을 다음 사람 화면에 남기지 않는다.
    package func reset() {
        submitGeneration &+= 1
        isSubmitting = false
        notice = nil
        form.cancelPendingPreview()
        form.isCreateTeamMode = false
        form.teamCode = ""
        form.joinPreview = nil
        form.joinPreviewMessage = ""
        form.createTeamName = ""
        form.createTeamGoalHours = MobileTeamJoinForm.defaultGoalHours
    }

    // MARK: - 제출

    /// 가드에 걸리면 **문구를 세우고 nil**(가입 화면과 같은 계약 — 화면은 이 값을 보지 않고 부른다).
    /// 도는 중이면 nil 이라 두 번 누른 탭이 왕복을 겹쳐 내지 않는다(같은 코드로 `join_team` 두 번 = 둘째는 이미 팀원이라 0행이다).
    @discardableResult
    package func submit() -> Task<Void, Never>? {
        guard !isSubmitting, context.session.isSignedIn else { return nil }
        if let message = form.guardMessage() {
            notice = message
            return nil
        }
        notice = nil
        isSubmitting = true
        submitGeneration &+= 1
        let generation = submitGeneration
        let appGeneration = context.generation
        let userID = context.session.userID
        let fallback = form.failureFallback
        return Task { [weak self] in
            guard let self else { return }
            await self.perform(generation: generation, appGeneration: appGeneration, userID: userID, fallback: fallback)
        }
    }

    private func perform(generation: Int, appGeneration: Int, userID: String?, fallback: String) async {
        let outcome: MobileTeamJoinForm.Outcome
        do {
            let settled = try await context.withMobileSessionRetry { [form] session in
                try await form.runTeamStep(accessToken: session.accessToken)
            }
            outcome = .settled(settled)
        } catch {
            outcome = .failed(message: MobileTeamJoinForm.failureMessage(error, fallback: fallback))
        }
        // 늦은 응답은 버린다: 그 사이 다시 눌렀거나(세대) 다른 계정이 들어왔다(계정 세대 · 사용자).
        guard generation == submitGeneration, appGeneration == context.generation, userID == context.session.userID else { return }
        isSubmitting = false
        switch outcome {
        case .settled(.joined), .settled(.created):
            notice = nil
            onTeamSettled?()
        case .settled(.blocked):
            // 코드 칸 아래 줄은 폼이 이미 '다른 센터 팀이에요' 로 바꿔 놓았다 — 카드는 그대로 두고 다시 치게 한다.
            break
        case .failed(let message):
            notice = message
        }
    }
}
