// 원본: Sources/CheckMobileKit/Now/NowTeamJoin.swift @ 1b8260d
package com.yehsung.aingcheck.core.session.team

import com.yehsung.aingcheck.core.session.context.SessionContext
import com.yehsung.aingcheck.core.session.rethrowIfOwnCancellation
import com.yehsung.aingcheck.core.session.signup.SignUpText
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * '지금' 탭 무소속 카드의 팀 합류·만들기(Swift `NowTeamJoinStore`). 화면 자리는 W2-b(지금 탭)지만 규칙은 팀 칸 한 벌([TeamJoinForm])과
 * 함께 세션 층에 둔다(C§3.2 D-1) — 가입 화면과 같은 왕복·가드·문구다.
 *
 * **역할(role)은 지어내지 않는다.** 합류·생성이 끝나면 [onTeamSettled] 로 알리고, 받는 쪽(지금 탭)이 소속을 서버에서 다시 읽는다 —
 * `join_team`/`create_team` 은 역할을 돌려주지 않아서, 추측해 넣으면 팀장 아닌 사람이 한 왕복 동안 팀장으로 보인다.
 */
class TeamJoinStore(private val context: SessionContext) {
    /** 팀 칸 한 벌(코드 ↔ 만들기 · 미리보기). 화면이 바인딩한다. */
    val form: TeamJoinForm = TeamJoinForm(context.service, context.sessionStore.scope)

    private val _notice = MutableStateFlow<String?>(null)
    private val _isSubmitting = MutableStateFlow(false)

    /** 카드 한 줄(가드 이유 · 실패 원인) — 여기 서는 문구는 전부 거절·실패라 늘 오류색이다(성공하면 카드가 사라진다). */
    val notice: String? get() = _notice.value
    val noticeFlow: StateFlow<String?> = _notice.asStateFlow()
    val isSubmitting: Boolean get() = _isSubmitting.value
    val isSubmittingFlow: StateFlow<Boolean> = _isSubmitting.asStateFlow()

    /** 팀이 정해졌다 — 지금 탭이 받아 소속을 다시 읽는다. */
    var onTeamSettled: (() -> Unit)? = null

    /** 제출 왕복 세대(늦은 응답 버리기). 계정 세대와 따로 센다 — 같은 계정 안에서도 겹칠 수 있다. */
    private var submitGeneration = 0

    val previewLine: TeamJoinForm.PreviewLine? get() = form.previewLine

    /** 주 버튼 글자. 만들기 모드는 "새 팀 만들기"(가입 화면의 "팀 만들고 시작하기"는 계정을 막 만든 자리의 말이다). */
    val primaryTitle: String get() = if (form.isCreateTeamMode.value) SignUpText.switchToCreate else SignUpText.join

    /** 주 버튼을 **켜 둘** 수 있는가. 막는 일은 [submit] 의 가드가 한다(키보드 제출 경로가 따로 있다). */
    val canSubmit: Boolean get() = !_isSubmitting.value && context.sessionStore.isSignedIn && form.isPrepared

    fun toggleCreateTeamMode() {
        form.toggleCreateTeamMode()
        _notice.value = null
    }

    /** 화면을 떠날 때. 날아가 있는 미리보기만 끊는다(친 값은 그대로). */
    fun cancelPendingWork() {
        form.cancelPendingPreview()
    }

    /** 로그아웃·계정 전환. 앞 사람의 코드·팀 이름을 다음 사람 화면에 남기지 않는다. */
    fun reset() {
        submitGeneration += 1
        _isSubmitting.value = false
        _notice.value = null
        form.cancelPendingPreview()
        form.isCreateTeamMode.value = false
        form.teamCode.value = ""
        form.joinPreview.value = null
        form.joinPreviewMessage.value = ""
        form.createTeamName.value = ""
        form.createTeamGoalHours.value = TeamJoinForm.DEFAULT_GOAL_HOURS
    }

    /**
     * 가드에 걸리면 **문구를 세우고 null**(가입 화면과 같은 계약). 도는 중이면 null 이라 두 번 누른 탭이 왕복을 겹쳐 내지 않는다
     * (같은 코드로 join_team 두 번 = 둘째는 이미 팀원이라 0행이다).
     */
    fun submit(): Job? {
        if (_isSubmitting.value || !context.sessionStore.isSignedIn) return null
        val message = form.guardMessage()
        if (message != null) {
            _notice.value = message
            return null
        }
        _notice.value = null
        _isSubmitting.value = true
        submitGeneration += 1
        val generation = submitGeneration
        val appGeneration = context.generation
        val userID = context.sessionStore.userID
        val fallback = form.failureFallback
        val job = context.sessionStore.scope.launch(start = CoroutineStart.LAZY) {
            perform(generation, appGeneration, userID, fallback)
        }
        job.start()
        return job
    }

    private suspend fun perform(generation: Int, appGeneration: Int, userID: String?, fallback: String) {
        val outcome: TeamJoinForm.Outcome = try {
            TeamJoinForm.Outcome.Settled(context.withSessionRetry { session -> form.runTeamStep(session.accessToken) })
        } catch (error: Throwable) {
            rethrowIfOwnCancellation(error)
            TeamJoinForm.Outcome.Failed(TeamJoinForm.failureMessage(error, fallback))
        }
        // 늦은 응답은 버린다: 그 사이 다시 눌렀거나(세대) 다른 계정이 들어왔다(계정 세대 · 사용자).
        if (generation != submitGeneration || appGeneration != context.generation || userID != context.sessionStore.userID) return
        _isSubmitting.value = false
        when (outcome) {
            is TeamJoinForm.Outcome.Settled -> when (outcome.settled) {
                is TeamJoinForm.Settled.Joined, is TeamJoinForm.Settled.Created -> {
                    _notice.value = null
                    onTeamSettled?.invoke()
                }
                // 코드 칸 아래 줄은 폼이 이미 '다른 센터 팀이에요' 로 바꿔 놓았다 — 카드는 그대로 두고 다시 치게 한다.
                TeamJoinForm.Settled.Blocked -> Unit
            }
            is TeamJoinForm.Outcome.Failed -> _notice.value = outcome.message
        }
    }
}
