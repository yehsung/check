// 원본: Sources/check/WorkTimerStorePoke.swift:841-856 loadTokenUsagePrivacyIfNeeded(로그인 중 받을 때까지 · 받으면 tokenUsageCollect 와
//       tokenUsageCollectLoaded) · :407(로그인 중 15초 폴링이 근무 게이트 앞에서 부른다) · WorkTimerStore.swift:1433-1436(수신 플래그) ·
//       :1455-1462(profiles.token_usage_collect 미러 — 앱에서 바꾸는 값이 아니라 서버가 정한다) · :4112(로그아웃 리셋)
//       · W-14 #10(tokenUsageCollect 서버 설정 공급자 — 업로드 자체는 여전히 tokenUpload 빌드 깃발이 막는다)
package com.yehsung.aingcheck.desktop.wiring

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.launch

/**
 * 서버 수집 설정(`profiles.token_usage_collect`)의 미러. 계정마다 한 번 받는다 — 실패하면 [retryMillis] 뒤 다시(맥은 15초 폴링이
 * 받을 때까지 부른다). 받기 전·로그아웃·계정 전환 직후는 **false**: 맥은 미러 기본값이 true 지만 외부 프로세스·업로드 게이트는
 * `tokenUsageCollectLoaded` 와 함께 본다(WorkTimerStoreSync.swift:790) — 여기는 두 값을 하나로 접어 '받은 뒤 참'만 참이다.
 */
class TokenUsageCollectSource(
    private val accountIds: Flow<String?>,
    private val fetchCollects: suspend () -> Boolean,
    private val retryMillis: Long = RETRY_MILLIS,
) {
    /** 서버에서 받은 값이 참일 때만 참(받기 전·실패 중·로그아웃은 거짓). */
    @Volatile var collects: Boolean = false
        private set

    /** 이 계정의 서버 값이 실제로 도착했는가(맥 tokenUsageCollectLoaded). */
    @Volatile var loaded: Boolean = false
        private set

    private var job: Job? = null

    fun start(scope: CoroutineScope) {
        if (job != null) return
        job = scope.launch {
            accountIds.distinctUntilChanged().collectLatest { id ->
                // 계정에 묶인 값 — 남기면 다음 계정이 서버 설정을 받기 전에 앞 사람 값으로 돈다(맥 :4112).
                collects = false
                loaded = false
                if (id == null) return@collectLatest
                while (true) {
                    val value = try {
                        fetchCollects()
                    } catch (e: CancellationException) {
                        throw e
                    } catch (_: Throwable) {
                        null
                    }
                    if (value != null) {
                        collects = value
                        loaded = true
                        return@collectLatest
                    }
                    delay(retryMillis)
                }
            }
        }
    }

    fun stop() {
        job?.cancel()
        job = null
    }

    companion object {
        /** 맥 수신 찔림 폴링 주기(WorkTimerStorePoke.swift — 로그인 중 15초)와 같은 재시도 간격. */
        const val RETRY_MILLIS = 15_000L
    }
}
