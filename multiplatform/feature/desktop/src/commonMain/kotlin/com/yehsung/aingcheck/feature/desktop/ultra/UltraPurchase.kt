// 원본: Sources/check/WorkTimerStoreAuth.swift 805-846(buyUltra) · 615-617(noteShopMutation) · Sources/CheckCore/CheckCoreShared.swift 23-26 @ a90d8623
// 울트라 구매(W2-g4). 진입 화면은 다음 웨이브(W-3 #15, W3-c3 pages/ultra) — 여기는 동작과 판정만.
package com.yehsung.aingcheck.feature.desktop.ultra

import com.yehsung.aingcheck.core.net.AuthErrorDisposition
import com.yehsung.aingcheck.core.rules.format.SharedText
import com.yehsung.aingcheck.core.session.context.SessionHost
import com.yehsung.aingcheck.core.stores.me.RubyBalanceMirror
import com.yehsung.aingcheck.feature.desktop.ultra.net.BuyUltraResponse
import com.yehsung.aingcheck.feature.desktop.ultra.net.buyUltra
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/**
 * buy_ultra(U5). 결과는 **서버 값**으로 루비·울트라에 적는다 — 클라가 잔액을 빼거나 더하지 않는다.
 *
 * - 루비 칸은 하나다([RubyBalanceMirror] — 조립이 상점·뽑기·게임과 같은 칸을 건넨다). 칸이 둘이면 화면마다 잔액이 갈린다.
 *   응답에 ruby_balance 가 있을 때만 쓴다(쓸 때마다 그 칸의 serial 이 +1 — 늦은 응답 판정이 횟수로 묻는다).
 * - 상태 판정은 status 문자열 그대로: ok → "울트라 N개를 샀어요!", insufficient → 모자란 루비, 그 밖·오류 → "구매 실패". 취소는 조용히.
 * - 한 번에 하나(Swift `purchasingID`). 맥은 캐릭터 구매와 한 깃발을 나누지만 Windows 1차 상점엔 울트라 칸이 없어 따로 둔다
 *   (W3-c3 가 상점 칸을 붙일 때 [isPurchasing] 을 상점 깃발과 묶는다).
 */
class UltraPurchase(
    private val host: SessionHost,
    private val ruby: RubyBalanceMirror,
    private val wallet: UltraWalletStore,
    private val scope: CoroutineScope,
    /** 상점이 아는 울트라 1개 값(shop_state.ultra_price). 모르면 null. */
    private val ultraPrice: () -> Long?,
    /** Swift `noteShopMutation()` — 상점 상태를 다시 읽을 이유(shopMutationSerial). */
    private val onShopMutation: () -> Unit = {},
) {
    private val _notice = MutableStateFlow<String?>(null)
    val notice: StateFlow<String?> = _notice.asStateFlow()

    private val _purchasing = MutableStateFlow(false)
    val isPurchasing: StateFlow<Boolean> = _purchasing.asStateFlow()

    /**
     * 계정 순번 — [resetForAccount] 가 올린다. A → B 직행은 세대가 그대로라(core SessionStore.adoptSignedInSession) 세대만 보면
     * 전환 전에 떠난 A 의 구매 응답이 B 의 루비 칸·울트라 잔량·안내에 닿는다(int-w4b 반박 검증 — DesktopPokeSender 와 같은 모양).
     * 맥은 세대만 보고(WorkTimerStoreAuth.swift:817·835) 계정 바뀜엔 clearPersistedSession 이 세대를 올린다(WorkTimerStore.swift:4034).
     * 세대·순번·주인 userID 가 **모두** 그대로일 때만 적는다.
     */
    private var accountEpoch = 0

    private fun isStale(generation: Int, epoch: Int, owner: String?) =
        generation != host.sessionGeneration || epoch != accountEpoch || owner != host.session?.userID

    /** 로그아웃·계정 전환 — 안내를 지우고 떠 있던 앞 계정의 응답을 버린다(구매 깃발은 그 응답의 finally 가 내린다). */
    fun resetForAccount() {
        accountEpoch += 1
        _notice.value = null
    }

    fun buy(count: Int = 1): Job? {
        if (_purchasing.value) return null
        _purchasing.value = true
        _notice.value = null
        val generation = host.sessionGeneration
        val epoch = accountEpoch
        val owner = host.session?.userID
        return scope.launch {
            try {
                val response = try {
                    host.withSessionRetry { s -> host.service.buyUltra(s.accessToken, count) }
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Throwable) {
                    if (isStale(generation, epoch, owner)) return@launch
                    if (host.classifyAuthError(e) == AuthErrorDisposition.cancelled) return@launch
                    _notice.value = FAILED
                    return@launch
                }
                if (isStale(generation, epoch, owner)) return@launch
                apply(response, count)
            } finally {
                _purchasing.value = false
            }
        }
    }

    /** 응답 반영(순수). 순서가 뜻이다 — 루비를 먼저 적고, insufficient 의 have 폴백은 **적은 뒤의** 루비를 읽는다(Swift 그대로). */
    fun apply(response: BuyUltraResponse, count: Int) {
        onShopMutation()
        response.rubyBalance?.let { ruby.rubyBalance = it }
        response.ultraBalance?.let { wallet.setBalanceFromPurchase(it) }
        _notice.value = when (response.status) {
            "ok" -> "울트라 ${count}개를 샀어요!"
            "insufficient" -> SharedText.shortfallNotice(
                need = response.need ?: ultraPrice()?.let { it * count },
                have = response.have ?: ruby.rubyBalance,
            )
            else -> FAILED
        }
    }

    fun clearNotice() {
        _notice.value = null
    }

    companion object {
        const val FAILED: String = "구매 실패"
    }
}
