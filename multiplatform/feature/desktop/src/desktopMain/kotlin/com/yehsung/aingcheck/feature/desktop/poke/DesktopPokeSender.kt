// W2-g2 찌르기 발신 — Swift Sources/check/WorkTimerStorePoke.swift 104-159(sendPoke) · 160-238(sendUltraPoke 의 발신 몫) · 366-372(쿨타임)
// · WorkTimerStoreMessagePokes.swift 151-155(refreshConversationAfterPokeSent — 이음새로만). 지갑 호출은 UltraWalletTrigger(W2-g4) 문으로.
package com.yehsung.aingcheck.feature.desktop.poke

import com.yehsung.aingcheck.core.net.AuthErrorDisposition
import com.yehsung.aingcheck.core.session.context.SessionHost
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.models.PokeSendOutcome
import com.yehsung.aingcheck.core.wire.models.PokeSendResponse
import com.yehsung.aingcheck.feature.desktop.poke.net.sendPoke
import com.yehsung.aingcheck.feature.desktop.poke.net.sendUltraPoke
import com.yehsung.aingcheck.feature.desktop.socialapi.UltraSyncReason
import com.yehsung.aingcheck.feature.desktop.socialapi.UltraWalletTrigger
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** 안내 칸 변경. Keep = 건드리지 않는다(Swift 가 그 갈래에서 pokeNotice 에 대입하지 않는다). */
sealed interface PokeNoticeChange {
    data object Keep : PokeNoticeChange
    data class Set(val notice: String?) : PokeNoticeChange
}

/** 발사 결과 한 건이 일으키는 일(P2). 순수 표 — [PokeSendEffects.of] 가 만든다. */
data class PokeSendEffect(
    val notice: PokeNoticeChange,
    /** 이 대상의 쿨타임 미러(초). null = 손대지 않는다. */
    val cooldownSeconds: Double? = null,
    /** 디렉터리 다시 읽기(target_not_working 만 — target_on_phone 은 낡은 게 아니라 다시 읽지 않는다). */
    val reloadDirectory: Boolean = false,
    /** 울트라 잔량에 쓸 서버값. null = 덮지 않는다. */
    val ultraBalance: Long? = null,
    /** 지갑 `.missionCandidate`(울트라 ok 만 — 잔량이 줄어드는 유일한 순간). */
    val walletMissionCandidate: Boolean = false,
    /** 그 사람과의 대화가 떠 있으면 이력 갱신(ok 만). */
    val refreshConversation: Boolean = false,
)

object PokeSendEffects {
    /** P2 결과별 처리. [knownUltraBalance] 는 ultra ok 안내에서 서버가 잔량을 안 실었을 때 쓰는 직전 잔량(Swift `?? ultraBalance`). */
    fun of(ultra: Boolean, response: PokeSendResponse, knownUltraBalance: Long?): PokeSendEffect =
        when (val outcome = PokeSendOutcome.of(response)) {
            PokeSendOutcome.Ok -> if (!ultra) {
                PokeSendEffect(PokeNoticeChange.Set(null), cooldownSeconds = DesktopPokeRules.COOLDOWN_SECONDS, refreshConversation = true)
            } else {
                PokeSendEffect(
                    PokeNoticeChange.Set(DesktopPokeRules.ultraSentNotice(response.ultraBalanceForDisplay ?: knownUltraBalance)),
                    cooldownSeconds = DesktopPokeRules.COOLDOWN_SECONDS,
                    ultraBalance = response.ultraBalanceForDisplay,
                    walletMissionCandidate = true,
                    refreshConversation = true,
                )
            }
            is PokeSendOutcome.Cooldown -> PokeSendEffect(
                if (ultra) PokeNoticeChange.Set(DesktopPokeRules.ULTRA_COOLDOWN_NOTICE) else PokeNoticeChange.Keep,
                cooldownSeconds = outcome.retryAfterSeconds.toDouble(),
            )
            // poke_user 는 이 status 를 내지 않는다(도달 불가) — 그래도 삼키지 않는다. 울트라는 status 자체가 '재화 없음'의 권위(없으면 0).
            is PokeSendOutcome.UltraUsedToday -> PokeSendEffect(
                PokeNoticeChange.Set(DesktopPokeRules.ULTRA_EMPTY_NOTICE),
                ultraBalance = if (ultra) response.ultraBalanceForDisplay ?: 0L else null,
            )
            PokeSendOutcome.NotWorking -> PokeSendEffect(PokeNoticeChange.Set(DesktopPokeRules.NOT_WORKING_NOTICE))
            PokeSendOutcome.TargetNotWorking -> PokeSendEffect(PokeNoticeChange.Set(DesktopPokeRules.TARGET_NOT_WORKING_NOTICE), reloadDirectory = true)
            // 집중·폰은 재화보다 **앞에서** 거절된다 — 잔량을 건드리지 않는다.
            PokeSendOutcome.TargetFocused -> PokeSendEffect(PokeNoticeChange.Set(DesktopPokeRules.TARGET_FOCUSED_NOTICE))
            PokeSendOutcome.TargetOnPhone -> PokeSendEffect(PokeNoticeChange.Set(DesktopPokeRules.TARGET_ON_PHONE_NOTICE))
            PokeSendOutcome.Invalid -> PokeSendEffect(PokeNoticeChange.Set(DesktopPokeRules.INVALID_NOTICE))
        }
}

/** 발신이 바깥에 닿는 이음새(디렉터리·대화·울트라 잔량 칸). 조립(AppGraph)이 채운다. */
interface PokeSendHooks {
    fun reloadDirectory() {}
    fun refreshConversationAfterPokeSent(peerUserID: String) {}
    /** 울트라 잔량 칸(Swift applyUltraBalance — W2-g4 지갑이 가진다). */
    fun applyUltraBalance(balance: Long) {}
    val currentUltraBalance: Long? get() = null

    object None : PokeSendHooks
}

class DesktopPokeSender(
    private val host: SessionHost,
    private val scope: CoroutineScope,
    private val clock: () -> SwiftDate,
    /** P1 선게이트 값 — Swift `startedAt != nil`(isWorking 아님). 조립은 PokeFactsSource().localSessionOpen 을 넘긴다. */
    private val localSessionOpen: () -> Boolean,
    private val wallet: UltraWalletTrigger,
    private val hooks: PokeSendHooks = PokeSendHooks.None,
) {
    private val _notice = MutableStateFlow<String?>(null)
    private val _cooldownUntil = MutableStateFlow<Map<String, SwiftDate>>(emptyMap())

    val notice: StateFlow<String?> = _notice.asStateFlow()
    val cooldownUntil: StateFlow<Map<String, SwiftDate>> = _cooldownUntil.asStateFlow()

    fun clearNotice() {
        _notice.value = null
    }

    fun cooldownRemaining(userID: String, now: SwiftDate): Int = DesktopPokeRules.cooldownRemaining(_cooldownUntil.value[userID], now)

    /** 지난 쿨타임 엔트리 정리(디렉터리 로드 성공마다 — 맵 무한 성장 방지). */
    fun pruneExpiredCooldowns(now: SwiftDate) {
        _cooldownUntil.update { map -> map.filterValues { it > now } }
    }

    /**
     * 계정 순번 — [resetForAccount] 가 올린다. 세대(host.sessionGeneration)는 로그아웃에만 오르고 A → B 직행에선 그대로라(core
     * SessionStore.adoptSignedInSession), 전환 전에 떠난 A 의 발신 응답이 B 의 울트라 잔량(지갑)·안내·쿨타임에 닿았다(int-w4b 반박 검증 P5).
     * 맥은 응답 뒤 세대만 보고(WorkTimerStorePoke.swift:175·232) 계정이 바뀌면 clearPersistedSession 이 세대를 올린다(WorkTimerStore.swift:4034).
     * 데스크톱은 [Ticket] 의 세 값(세대·순번·주인 userID)이 **모두** 그대로일 때만 적는다 — 주인 대조는 리스너의 reset 이 돌기 전 틈도 막는다.
     */
    private var accountEpoch = 0

    /** 발신 때 잡는 값들. 응답 때 하나라도 바뀌었으면 그 응답은 앞 계정의 것이다. */
    private class Ticket(val generation: Int, val epoch: Int, val owner: String?)

    private fun ticket() = Ticket(host.sessionGeneration, accountEpoch, host.session?.userID)

    private fun isStale(t: Ticket) =
        t.generation != host.sessionGeneration || t.epoch != accountEpoch || t.owner != host.session?.userID

    /** 로그아웃·계정 전환(맥 clearPersistedSession 의 `pokeCooldownUntil = [:]` · `pokeNotice = nil` — WorkTimerStore.swift:4091-4092). 떠 있던 응답은 버린다. */
    fun resetForAccount() {
        accountEpoch += 1
        _notice.value = null
        _cooldownUntil.value = emptyMap()
    }

    fun sendPoke(to: String): Job? = send(to, ultra = false)

    /** 울트라 — 선게이트는 일반과 **정확히 같다**. 로컬 잔량으로 막지 않는다(잔량은 그날 중에 늘어난다 — 서버 판정이 발사 허용). */
    fun sendUltraPoke(to: String): Job? = send(to, ultra = true)

    private fun send(to: String, ultra: Boolean): Job? {
        if (host.session == null) return null
        if (!localSessionOpen()) {
            _notice.value = DesktopPokeRules.NOT_WORKING_NOTICE
            return null
        }
        val ticket = ticket()
        return scope.launch {
            val response = try {
                host.withSessionRetry { session ->
                    if (ultra) host.service.sendUltraPoke(session.accessToken, to) else host.service.sendPoke(session.accessToken, to)
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Throwable) {
                if (host.classifyAuthError(e) == AuthErrorDisposition.cancelled) return@launch
                if (isStale(ticket)) return@launch
                // 마이그레이션 미적용 서버(PGRST202)도 여기 — 울트라만 조용히 못 쓰고 일반 찌르기는 산다.
                _notice.value = DesktopPokeRules.NETWORK_NOTICE
                return@launch
            }
            if (isStale(ticket)) return@launch
            apply(to, PokeSendEffects.of(ultra, response, hooks.currentUltraBalance))
        }
    }

    private fun apply(to: String, effect: PokeSendEffect) {
        effect.cooldownSeconds?.let { seconds -> _cooldownUntil.update { it + (to to clock().addingTimeInterval(seconds)) } }
        effect.ultraBalance?.let(hooks::applyUltraBalance)
        val change = effect.notice
        if (change is PokeNoticeChange.Set) _notice.value = change.notice
        if (effect.walletMissionCandidate) wallet.sync(UltraSyncReason.MissionCandidate)
        if (effect.refreshConversation) hooks.refreshConversationAfterPokeSent(to)
        if (effect.reloadDirectory) hooks.reloadDirectory()
    }
}
