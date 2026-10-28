// 원본: Sources/CheckMobileKit/App/AppUserCharacterStore.swift @ 1b8260d
package com.yehsung.aingcheck.core.stores.characters

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.yehsung.aingcheck.core.net.fetchAppUserCharacters
import com.yehsung.aingcheck.core.session.context.SessionContext
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.models.AppUserCharacterDirectory
import com.yehsung.aingcheck.core.wire.models.AppUserCharacterRow
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/**
 * 폰의 **캐릭터 한 표**(`app_user_characters()` — 기본 아바타 = 착용 캐릭터). 앱 조립이 하나 만들어 나눠 주고, 사람 아바타는 호출부가 넘긴
 * **사용자 id** 로 이 표에서 캐릭터를 찾아 사진 → 캐릭터 → 이니셜 순으로 그린다(판정은 와이어 `AppUserCharacterDirectory`).
 *
 * 갱신(무료 플랜 — **폴링을 새로 만들지 않는다**)
 * - 로그인 직후 한 번([refresh]).
 * - 그 뒤로는 기존 갱신 시점(앱 active · 탭 바꾸기)에 [refreshIfStale] — 마지막 **시도**에서 60초가 안 지났거나 조회가 떠 있으면 아무것도 안 한다.
 *   실패도 시도로 센다(오프라인 연타에 요청이 쌓이지 않는다).
 * - 서버에 함수가 아직 없으면(404) 와이어가 조용히 빈 표를 준다. 그 밖의 실패는 **가진 표를 그대로 둔다**.
 *
 * 내 칸: 착용을 바꾸거나 나 탭이 착용값을 읽으면 [noteMyEquipped] 로 **즉시** 고치고, 표를 갈아 끼울 때 그 값을 다시 얹는다
 * (와이어 `setEquipped` 경합 주석 — 저장 전에 떠난 조회가 늦게 와도 방금 입은 캐릭터를 되돌리지 않는다).
 *
 * 로그아웃([reset])하면 표 · 내 칸 · 시도 시각을 모두 비우고 떠 있는 조회를 버린다.
 */
class AppUserCharacterStore(
    val context: SessionContext,
    parentScope: CoroutineScope,
    /** 이 빌드가 초상을 그릴 수 있는 캐릭터(기본 = 초상 번들 — 조립이 ui 의 그림 목록을 넘긴다). 모르는 id 를 입은 사람은 이니셜이다. */
    private val knownIDs: List<String>,
) {
    val scope: CoroutineScope = CoroutineScope(parentScope.coroutineContext + SupervisorJob(parentScope.coroutineContext[Job]))

    /** 지금 표. 바뀔 때만 새 값을 쓴다(같은 표로 갈아 끼우면 화면을 다시 그리지 않는다). */
    var directory: AppUserCharacterDirectory by mutableStateOf(AppUserCharacterDirectory(knownIDs))
        private set

    /** 마지막 조회를 **떠난** 시각(성공·실패 무관 — 스로틀 기준). null = 이 세션에서 아직 안 물었다. */
    var lastAttemptAt: SwiftDate? = null
        private set
    var isLoading: Boolean = false
        private set

    /** 떠 있는 조회(시험이 기다린다). */
    var inflight: Job? = null
        private set

    /** 표가 실제로 바뀌었을 때(위젯 스냅숏의 근무 중 얼굴을 다시 쓰게 — 조립이 지금 탭에 잇는다). */
    var onDirectoryChange: (() -> Unit)? = null

    private var serial = 0

    /** 이 폰이 아는 내 착용값(서버 어휘 — null = 기본/아잉). 칸 자체가 null = 아직 모른다. */
    private var mine: Pair<String, String?>? = null

    /** 표의 원재료(마지막으로 받은 행). 표를 다시 세울 때 쓴다(와이어 표는 제자리에서 바뀌는 타입이라 사본을 뜨지 않고 새로 세운다). */
    private var rows: List<AppUserCharacterRow> = emptyList()

    /** 로그인 직후: 스로틀과 무관하게 한 번. */
    fun refresh() {
        if (!context.sessionStore.isSignedIn || isLoading) return
        start()
    }

    /** 기존 갱신 시점: 마지막 시도에서 [refreshIntervalSeconds] 가 지났을 때만. */
    fun refreshIfStale() {
        if (!context.sessionStore.isSignedIn || isLoading) return
        val last = lastAttemptAt
        if (last != null && context.clock.now().timeIntervalSince(last) < refreshIntervalSeconds) return
        start()
    }

    /** 내 착용값을 표에 바로 쓴다(`serverValue` 는 서버 어휘 — null·빈 글자 = 아잉). 다음 조회가 와도 이 값이 이긴다. */
    fun noteMyEquipped(serverValue: String?) {
        val userID = context.sessionStore.userID
        if (!context.sessionStore.isSignedIn || userID == null) return
        mine = userID to serverValue
        apply(build(rows))
    }

    /** 로그아웃 · 계정 전환: 표 · 내 칸 · 시도 시각을 비우고 떠 있는 조회를 버린다. */
    fun reset() {
        serial += 1
        inflight?.cancel()
        inflight = null
        isLoading = false
        lastAttemptAt = null
        mine = null
        rows = emptyList()
        val next = AppUserCharacterDirectory(knownIDs)
        if (next != directory) directory = next
    }

    /** 지금 조회의 순번(떠날 때마다 · [reset] 때마다 오른다). */
    val requestSerial: Int get() = serial

    private fun start() {
        serial += 1
        val mySerial = serial
        val generation = context.generation
        isLoading = true
        lastAttemptAt = context.clock.now()
        val service = context.service
        val job = scope.launch(start = CoroutineStart.LAZY) {
            val fetched = try {
                context.withSessionRetry { session -> service.fetchAppUserCharacters(session.accessToken) }
            } catch (error: Throwable) {
                null // 일시 장애 · 세션 만료: 가진 표를 그대로 둔다.
            }
            finish(fetched, mySerial, generation)
        }
        inflight = job
        job.start()
    }

    /**
     * 조회 결과를 옮긴다(null = 실패 — 가진 표를 둔다). **떠날 때의 순번·세대가 아니면 아무것도 안 한다** — 로그아웃 뒤 메인 차례를 기다리던
     * 앞 계정의 표가 다음 계정 화면에 들어가면 안 된다. 순번이 다르면 진행 표시도 건드리지 않는다(스로틀이 풀려 같은 조회가 겹친다).
     * 그 창은 실제 요청으로는 결정적으로 못 만든다 — 이 함수로 떼어 직접 시험한다.
     */
    fun finish(fetched: List<AppUserCharacterRow>?, serial: Int, generation: Int) {
        if (this.serial != serial) return
        isLoading = false
        inflight = null
        if (fetched == null || generation != context.generation || !context.sessionStore.isSignedIn) return
        rows = fetched
        apply(build(fetched))
    }

    private fun build(source: List<AppUserCharacterRow>): AppUserCharacterDirectory {
        val next = AppUserCharacterDirectory(knownIDs, source)
        val own = mine
        if (own != null &&
            AppUserCharacterDirectory.normalizedUserID(own.first) == AppUserCharacterDirectory.normalizedUserID(context.sessionStore.userID)
        ) {
            next.setEquipped(own.second, own.first)
        }
        return next
    }

    private fun apply(next: AppUserCharacterDirectory) {
        if (next == directory) return
        directory = next
        onDirectoryChange?.invoke()
    }

    companion object {
        /** 기존 갱신 시점마다 다시 묻는 최소 간격(초). */
        const val refreshIntervalSeconds: Double = 60.0
    }
}
