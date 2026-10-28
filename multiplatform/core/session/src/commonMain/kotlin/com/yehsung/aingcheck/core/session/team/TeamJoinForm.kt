// 원본: Sources/CheckMobileKit/Session/MobileTeamJoinForm.swift @ 1b8260d
package com.yehsung.aingcheck.core.session.team

import com.yehsung.aingcheck.core.net.AuthErrorDisposition
import com.yehsung.aingcheck.core.net.AuthErrorRules
import com.yehsung.aingcheck.core.net.SupabaseWorkService
import com.yehsung.aingcheck.core.net.createTeam
import com.yehsung.aingcheck.core.net.joinTeam
import com.yehsung.aingcheck.core.net.lookupTeamByCode
import com.yehsung.aingcheck.core.net.normalizeInviteCode
import com.yehsung.aingcheck.core.session.SessionText
import com.yehsung.aingcheck.core.session.rethrowIfOwnCancellation
import com.yehsung.aingcheck.core.session.signup.SignUpText
import com.yehsung.aingcheck.core.wire.models.TeamJoinPreview
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import kotlin.coroutines.cancellation.CancellationException

/**
 * 팀 칸 한 벌(코드 합류 ↔ 팀 만들기) — **가입 화면과 '지금' 탭 무소속 카드가 함께 쓴다**(Swift `MobileTeamJoinForm`).
 *
 * 팀에 들어갈 길이 가입 화면 하나뿐이면 "이메일 확인 필요" 출구로 들어온 사람 · 가입 도중 앱을 껐던 사람 · 맥에서 가입만 해 둔 사람은
 * 무소속으로 떨어진 채 영영 팀에 못 들어간다. 그래서 규칙을 이 자리 한 벌로 두고 둘이 나눠 쓴다 — 같은 왕복(`lookup_team_by_code` →
 * `join_team`/`create_team`) · 같은 가드 · 같은 문구([SignUpText]).
 *
 * 이 타입은 **화면 상태를 모른다.** 왕복 결과를 [Outcome] 으로만 돌려주고, 그 뒤에 무엇이 되는지는 부르는 쪽이 정한다.
 * 입력 칸은 화면이 쓰고 읽는 [MutableStateFlow] 다(K8).
 */
class TeamJoinForm(
    private val service: SupabaseWorkService,
    /** 미리보기 작업이 도는 자리(세션 스토어의 스코프). */
    private val scope: CoroutineScope,
    createTeam: Boolean = false,
) {
    /** 팀이 정해진 모양(서버가 답을 준 갈래). 실패는 던져서 부르는 쪽의 세션 갱신 재시도가 401 을 볼 수 있게 한다. */
    sealed interface Settled {
        data class Joined(val teamID: String, val name: String, val goalHours: Long) : Settled
        data class Created(val teamID: String, val name: String, val inviteCode: String, val goalHours: Long) : Settled

        /** `join_team` 0행 — **코드는 맞았는데** 서버가 막았다(센터 게이트). 코드 칸 아래 줄은 이미 그 사실을 말하고 있다. */
        data object Blocked : Settled
    }

    /** 팀 왕복 한 번의 결과. 문구는 이 타입이 정하고, 화면 상태는 부르는 쪽이 정한다. */
    sealed interface Outcome {
        data class Settled(val settled: TeamJoinForm.Settled) : Outcome

        /** 실패. [message] 가 null 이면 취소(사용자에게 아무 말도 하지 않는다). */
        data class Failed(val message: String?) : Outcome
    }

    /** 코드 입력 ↔ 팀 만들기. 사람은 늘 코드 입력으로 시작한다(맥과 같다). */
    val isCreateTeamMode: MutableStateFlow<Boolean> = MutableStateFlow(createTeam)
    val teamCode: MutableStateFlow<String> = MutableStateFlow("")

    /** 미리보기 결과(null = 미확인/불일치). 코드 모드는 이것이 있어야 왕복이 시작된다. */
    val joinPreview: MutableStateFlow<TeamJoinPreview?> = MutableStateFlow(null)
    val joinPreviewMessage: MutableStateFlow<String> = MutableStateFlow("")
    val createTeamName: MutableStateFlow<String> = MutableStateFlow("")
    val createTeamGoalHours: MutableStateFlow<Long> = MutableStateFlow(DEFAULT_GOAL_HOURS)

    /** 코드 미리보기 재입력 경합 방지(마지막 요청 우선). 세션과 무관 — 비로그인에서도 쓴다. */
    private var previewGeneration = 0

    /**
     * 코드 칸 아래 한 줄: 안내/실패·확인 중(문구) · 찾은 팀 요약. 없으면 null.
     * **문구가 요약보다 먼저다** — 문구는 요약보다 늘 나중 사실이다(새 코드를 확인하기 시작했거나 서버가 요약을 부정했거나).
     */
    val previewLine: PreviewLine?
        get() {
            val message = joinPreviewMessage.value
            if (message.isNotEmpty()) return PreviewLine(message, isSuccess = false)
            val preview = joinPreview.value ?: return null
            return PreviewLine(SignUpText.previewLine(preview), isSuccess = true)
        }

    /** 팀 단계를 **왕복 없이** 시작할 수 있는가(문구를 세우지 않는 순수 판정 — 가드 문구는 [guardMessage] 몫). */
    val isPrepared: Boolean
        get() = if (isCreateTeamMode.value) createTeamName.value.trim().isNotEmpty() else joinPreview.value != null

    /** 코드 모드: 미리보기가 확인되어야 시작할 수 있다. 만들기 모드: 팀 이름 필수. 통과면 null, 막히면 화면에 세울 문구. */
    fun guardMessage(): String? {
        if (isCreateTeamMode.value) {
            if (createTeamName.value.trim().isEmpty()) return SignUpText.teamNameRequired
        } else {
            if (joinPreview.value == null) return SignUpText.codeUnverified
        }
        return null
    }

    // ------------------------------------------------------------------ 팀 코드 미리보기

    /** 디바운스는 화면 몫이고 여기선 재입력 경합만 막는다(마지막 요청 우선). 시험이 기다릴 수 있게 작업을 돌려준다. */
    fun previewTeamCode(): Job {
        previewGeneration += 1
        return scope.launch { performPreviewTeamCode() }
    }

    suspend fun performPreviewTeamCode() {
        val generation = previewGeneration
        val code = teamCode.value
        if (normalizeInviteCode(code).isEmpty()) {
            joinPreview.value = null
            joinPreviewMessage.value = ""
            return
        }
        joinPreviewMessage.value = SignUpText.previewChecking
        try {
            val preview = service.lookupTeamByCode(code)
            if (generation != previewGeneration) return
            if (preview != null) {
                joinPreview.value = preview
                joinPreviewMessage.value = ""
            } else {
                joinPreview.value = null
                joinPreviewMessage.value = SignUpText.previewMiss
            }
        } catch (error: CancellationException) {
            throw error
        } catch (error: Throwable) {
            if (generation != previewGeneration) return
            joinPreview.value = null
            joinPreviewMessage.value = SignUpText.previewMiss
        }
    }

    /** 코드 입력 ↔ 팀 만들기 전환. 이전 코드 미리보기 잔상을 지운다. 화면의 안내 줄은 부르는 쪽이 지운다. */
    fun toggleCreateTeamMode() {
        isCreateTeamMode.value = !isCreateTeamMode.value
        joinPreview.value = null
        joinPreviewMessage.value = ""
    }

    /** 날아가 있는 미리보기 응답을 버린다(화면을 떠날 때). 값은 그대로 둔다. */
    fun cancelPendingPreview() {
        previewGeneration += 1
    }

    // ------------------------------------------------------------------ 팀 왕복

    /**
     * 계정이 있는 상태에서 팀을 정한다. 세션 토큰은 부르는 쪽이 준다(가입은 방금 받은 세션, 지금 탭은 로그인 세션).
     * **던진다** — 401 을 삼키면 부르는 쪽의 세션 갱신 재시도가 볼 것이 없어진다. 문구까지 원하면 [performTeamStep].
     */
    suspend fun runTeamStep(accessToken: String): Settled {
        if (isCreateTeamMode.value) {
            val name = createTeamName.value.trim()
            val team = service.createTeam(accessToken, name, createTeamGoalHours.value)
            return Settled.Created(team.teamID, team.name, team.inviteCode, team.goalHours)
        }
        val joined = service.joinTeam(accessToken, teamCode.value)
        if (joined == null) {
            // INV-MobileTeamJoinForm-d11a3161 이식: **여기까지 왔으면 코드는 맞았다** — 미리보기가 팀을 찾아 joinPreview 를 세웠다.
            //   그런데도 서버가 0행을 냈다면 남은 이유는 하나, **다른 센터 팀**이다(join_team 의 센터 게이트 — 0행은 코드 불일치와 같은 모양).
            //   "코드를 확인해 주세요"라고 말하면 멀쩡한 코드를 몇 번이고 다시 친다. 미리보기는 **비운다** — 요약을 두면 (1) 화면 줄이 요약을
            //   그려 이 문구가 안 보이고 (2) 같은 코드로 [참여하기] 가 헛왕복을 무한히 돈다. 비우면 같은 코드 재제출은 가드가 왕복 없이 막는다.
            joinPreview.value = null
            joinPreviewMessage.value = SignUpText.teamlessJoinBlocked
            return Settled.Blocked
        }
        return Settled.Joined(joined.teamID, joined.name, joined.goalHours)
    }

    /** 실패를 삼켜 화면 한 줄로 바꾸는 갈래(가입 화면 — 방금 받은 세션이라 갱신 재시도가 없다). */
    suspend fun performTeamStep(accessToken: String): Outcome = try {
        Outcome.Settled(runTeamStep(accessToken))
    } catch (error: Throwable) {
        rethrowIfOwnCancellation(error)
        Outcome.Failed(failureMessage(error, failureFallback))
    }

    /** 지금 모드의 실패 폴백 문구. */
    val failureFallback: String
        get() = if (isCreateTeamMode.value) SignUpText.createTeamFailed else SignUpText.joinFailed

    /** 코드 칸 아래 한 줄. */
    data class PreviewLine(val text: String, val isSuccess: Boolean)

    companion object {
        /** 맥 `createTeamGoalHours` 기본값 · `WeeklyGoalStepper` 범위와 같다. */
        const val DEFAULT_GOAL_HOURS: Long = 60
        val GOAL_HOURS_RANGE: LongRange = 1L..168L

        /** 실패 → 화면 한 줄. 취소는 null(아무 말도 하지 않는다). */
        fun failureMessage(error: Throwable, fallback: String): String? = when (AuthErrorRules.classify(error)) {
            AuthErrorDisposition.cancelled -> null
            AuthErrorDisposition.transient -> SessionText.network
            AuthErrorDisposition.fatal -> AuthErrorRules.message(error, fallback)
        }
    }
}
