import CheckCore
import Foundation
import Observation

/// 팀 칸 한 벌(코드 합류 ↔ 팀 만들기) — **가입 화면과 '지금' 탭 무소속 카드가 함께 쓴다.**
///
/// 원래 이 규칙은 `MobileSignUpStore` 안에만 있었다. 그런데 팀에 들어갈 길이 가입 화면 하나뿐이라, 로그인 화면의
/// "이메일 확인 필요" 출구로 들어온 사람 · 가입 도중 앱을 껐던 사람 · 맥에서 가입만 해 둔 사람은 **무소속으로 떨어진 채
/// 맥 없이는 영영 팀에 못 들어갔다**(w16 검증 high). 그래서 규칙을 새로 쓰지 않고 이 자리로 **그대로 옮겨** 둘이 나눠 쓴다 —
/// 같은 왕복(`lookup_team_by_code` → `join_team`/`create_team`) · 같은 가드 · 같은 문구(`MobileSignUpText`).
///
/// 이 타입은 **화면 상태를 모른다.** 왕복 결과를 `Outcome` 으로만 돌려주고, 그 뒤에 무엇이 되는지(가입 화면의 `stage`,
/// 지금 탭의 팀 화면 전환)는 부르는 쪽이 정한다. 두 화면이 같은 사실에 다른 이름을 붙이지 않게 하려는 갈라짐 지점이 여기 하나다.
///
/// 맥 원본은 `WorkTimerStoreAuth.performPreviewTeamCode / joinTeamAfterSignup / createTeamAfterSignup` 이다.
@MainActor
@Observable
package final class MobileTeamJoinForm {
    /// 팀이 정해진 모양(서버가 답을 준 갈래). 실패는 던져서 부르는 쪽의 세션 갱신 재시도가 401 을 볼 수 있게 한다.
    package enum Settled: Equatable, Sendable {
        case joined(teamID: String, name: String, goalHours: Int)
        case created(teamID: String, name: String, inviteCode: String, goalHours: Int)
        /// `join_team` 0행 — **코드는 맞았는데** 서버가 막았다(센터 게이트). 코드 칸 아래 줄은 이미 그 사실을 말하고 있다.
        case blocked
    }

    /// 팀 왕복 한 번의 결과. 문구는 이 타입이 정하고(같은 입력에 두 화면이 다른 말을 하지 않게), 화면 상태는 부르는 쪽이 정한다.
    package enum Outcome: Equatable, Sendable {
        case settled(Settled)
        /// 실패. `message` 가 nil 이면 취소(사용자에게 아무 말도 하지 않는다).
        case failed(message: String?)
    }

    /// 코드 입력 ↔ 팀 만들기. 사람은 늘 코드 입력으로 시작한다(맥 `switchMode` 와 같다 — 데모 스크린샷만 만들기로 시작).
    package var isCreateTeamMode: Bool
    package var teamCode = ""
    /// 미리보기 결과(nil = 미확인/불일치). 코드 모드는 이것이 있어야 왕복이 시작된다.
    package var joinPreview: TeamJoinPreview?
    package var joinPreviewMessage = ""
    package var createTeamName = ""
    package var createTeamGoalHours = MobileTeamJoinForm.defaultGoalHours

    @ObservationIgnored private let service: SupabaseWorkService
    /// 코드 미리보기 재입력 경합 방지(마지막 요청 우선). 세션과 무관 — 비로그인에서도 쓴다.
    @ObservationIgnored private var previewGeneration = 0

    /// 맥 `createTeamGoalHours` 기본값 · `WeeklyGoalStepper` 범위와 같다.
    package nonisolated static let defaultGoalHours = 60
    package nonisolated static let goalHoursRange = 1...168

    package init(service: SupabaseWorkService, createTeam: Bool = false) {
        self.service = service
        self.isCreateTeamMode = createTeam
    }

    // MARK: - 화면이 읽는 값

    /// 코드 칸 아래 한 줄: 안내/실패·확인 중(문구) · 찾은 팀 요약. 없으면 nil.
    ///
    /// **문구가 요약보다 먼저다.** 문구는 요약보다 늘 나중 사실이다(새 코드를 확인하기 시작했거나, 서버가 요약을 부정했거나).
    /// 요약을 먼저 돌려주면 문구를 세우고 요약을 안 지운 모든 곳이 화면에서 사라진다 — join_team 0행의 '다른 센터 팀이에요' 가
    /// 스토어 필드에만 있고 화면엔 성공 요약 + [참여하기] 만 남았던 결함(w16 검증)이 그 첫 사례였다.
    package var previewLine: (text: String, isSuccess: Bool)? {
        if !joinPreviewMessage.isEmpty { return (joinPreviewMessage, false) }
        if let joinPreview { return (MobileSignUpText.previewLine(joinPreview), true) }
        return nil
    }

    /// 팀 단계를 **왕복 없이** 시작할 수 있는가(문구를 세우지 않는 순수 판정 — 가드 문구는 `guardMessage()` 몫).
    package var isPrepared: Bool {
        isCreateTeamMode ? !createTeamName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty : joinPreview != nil
    }

    /// 코드 모드: 미리보기가 확인되어야(joinPreview != nil) 시작할 수 있다. 만들기 모드: 팀 이름 필수. (맥 signUp())
    /// 통과면 nil, 막히면 **화면에 세울 문구**를 돌려준다 — 막는 판정과 그 이유가 갈리지 않게 한 함수다.
    package func guardMessage() -> String? {
        if isCreateTeamMode {
            guard !createTeamName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return MobileSignUpText.teamNameRequired
            }
        } else {
            guard joinPreview != nil else { return MobileSignUpText.codeUnverified }
        }
        return nil
    }

    // MARK: - 팀 코드 미리보기(맥 previewTeamCode/performPreviewTeamCode)

    /// 디바운스는 화면 몫이고 여기선 재입력 경합만 막는다(마지막 요청 우선). 테스트가 기다릴 수 있게 Task 를 돌려준다.
    @discardableResult
    package func previewTeamCode() -> Task<Void, Never> {
        previewGeneration &+= 1
        return Task { await performPreviewTeamCode() }
    }

    package func performPreviewTeamCode() async {
        let generation = previewGeneration
        let code = teamCode
        let normalized = SupabaseWorkService.normalizeInviteCode(code)
        guard !normalized.isEmpty else {
            joinPreview = nil
            joinPreviewMessage = ""
            return
        }
        joinPreviewMessage = MobileSignUpText.previewChecking
        do {
            let preview = try await service.lookupTeamByCode(code: code)
            guard generation == previewGeneration else { return }
            if let preview {
                joinPreview = preview
                joinPreviewMessage = ""
            } else {
                joinPreview = nil
                joinPreviewMessage = MobileSignUpText.previewMiss
            }
        } catch {
            guard generation == previewGeneration else { return }
            joinPreview = nil
            joinPreviewMessage = MobileSignUpText.previewMiss
        }
    }

    /// 코드 입력 ↔ 팀 만들기 전환. 이전 코드 미리보기 잔상을 지워 혼동을 막는다(맥 `toggleCreateTeamMode`).
    /// 화면의 안내 줄(`notice`)은 부르는 쪽이 지운다 — 그 줄의 주인이 화면마다 다르다.
    package func toggleCreateTeamMode() {
        isCreateTeamMode.toggle()
        joinPreview = nil
        joinPreviewMessage = ""
    }

    /// 날아가 있는 미리보기 응답을 버린다(화면을 떠날 때). 값은 그대로 둔다.
    package func cancelPendingPreview() {
        previewGeneration &+= 1
    }

    // MARK: - 팀 왕복(맥 joinTeamAfterSignup / createTeamAfterSignup)

    /// 계정이 있는 상태에서 팀을 정한다. 세션 토큰은 부르는 쪽이 준다(가입은 방금 받은 세션, 지금 탭은 로그인 세션).
    ///
    /// **던진다** — 401 을 삼키면 부르는 쪽의 세션 갱신 재시도(`withMobileSessionRetry`)가 볼 것이 없어진다.
    /// 문구까지 원하면 `performTeamStep(accessToken:)` 을 쓴다.
    package func runTeamStep(accessToken: String) async throws -> Settled {
        if isCreateTeamMode {
            let name = createTeamName.trimmingCharacters(in: .whitespacesAndNewlines)
            let goal = createTeamGoalHours
            let team = try await service.createTeam(accessToken: accessToken, name: name, goalHours: goal)
            return .created(teamID: team.teamID, name: team.name, inviteCode: team.inviteCode, goalHours: team.goalHours)
        }
        let code = teamCode
        guard let joined = try await service.joinTeam(accessToken: accessToken, code: code) else {
            // ★ **여기까지 왔으면 코드는 맞았다** — 미리보기(`lookup_team_by_code`)가 팀을 찾아 `joinPreview` 를 세웠다.
            //   그런데도 서버가 0행을 냈다면 남은 이유는 하나다: **다른 센터 팀**이다(`join_team` 의 센터 게이트,
            //   20260912185423_join_team_center_gate.sql — 둘 다 알 때만 막고, 0행은 코드 불일치와 같은 모양이다).
            //   "코드를 확인해 주세요"라고 말하면 사용자는 멀쩡한 코드를 몇 번이고 다시 친다(맥 performJoinTeamWithCode 주석).
            //   미리보기는 **비운다** — 서버가 '이 팀엔 못 들어간다' 고 답한 뒤에도 요약을 두면 (1) 화면 줄이 요약을 그려 이 문구가
            //   안 보이고 (2) 같은 코드로 [참여하기] 가 헛왕복(같은 0행)을 무한히 돈다. 비우면 같은 코드 재제출은 가드가
            //   왕복 없이 막고, 다른 코드를 치면 미리보기부터 다시 선다.
            joinPreview = nil
            joinPreviewMessage = MobileSignUpText.teamlessJoinBlocked
            return .blocked
        }
        return .joined(teamID: joined.teamID, name: joined.name, goalHours: joined.goalHours)
    }

    /// 실패를 삼켜 화면 한 줄로 바꾸는 갈래(가입 화면 — 방금 받은 세션이라 갱신 재시도가 없다).
    package func performTeamStep(accessToken: String) async -> Outcome {
        do {
            return .settled(try await runTeamStep(accessToken: accessToken))
        } catch {
            return .failed(message: Self.failureMessage(error, fallback: failureFallback))
        }
    }

    /// 지금 모드의 실패 폴백 문구(맥 `authMessage(for:fallback:)` 의 fallback 그대로).
    package var failureFallback: String {
        isCreateTeamMode ? MobileSignUpText.createTeamFailed : MobileSignUpText.joinFailed
    }

    /// 실패 → 화면 한 줄. 취소는 nil(아무 말도 하지 않는다).
    package nonisolated static func failureMessage(_ error: Error, fallback: String) -> String? {
        switch AuthErrorRules.classify(error) {
        case .cancelled: return nil
        case .transient: return MobileSessionText.network
        case .fatal: return AuthErrorRules.message(for: error, fallback: fallback)
        }
    }
}
