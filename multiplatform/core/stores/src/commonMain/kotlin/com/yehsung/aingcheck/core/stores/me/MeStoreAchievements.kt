// 원본: Sources/CheckMobileKit/Me/MeStoreAchievements.swift @ 1b8260d
package com.yehsung.aingcheck.core.stores.me

import com.yehsung.aingcheck.core.net.AuthErrorDisposition
import com.yehsung.aingcheck.core.net.AuthErrorRules
import com.yehsung.aingcheck.core.net.achievementClaimRaw
import com.yehsung.aingcheck.core.net.achievementsStatusRaw
import com.yehsung.aingcheck.core.net.dailyMissionClaimRaw
import com.yehsung.aingcheck.core.rules.achievements.AchievementStatus
import com.yehsung.aingcheck.core.rules.achievements.DailyMissionStatus
import com.yehsung.aingcheck.core.wire.SwiftDate
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import kotlin.math.floor

// 도전 미션 · 받기 — 폰 배선(서버 20261019120000 · 맥 0.3.58). 사장님 확정(2026-10-19): 달성 → [받기] → 지급. 3시간 랩(+3)은 자동이고
// 폰은 그 지급을 부르지 않는다(지갑 동기화는 폰 금지 목록). 모델 · 디코드 · 계열 접기 · 받음 되돌림 방지는 코어(rules achievements) 한 벌이고
// 이 파일은 **부르고 옮기기만** 한다 — 제목 · 보상 · 목표 · 순서는 전부 서버 응답이다.
//
// 폰이 더하는 것(맥 `WorkTimerStoreAchievements` 와 같은 구조):
//  ① 박자 — 새 타이머 없음. 나 탭 루트 새로고침 · 당겨서 새로고침 · 앱이 앞에 올 때(탭이 안 보여도 — 받을 보상 수가 탭 막대 배지다).
//     스로틀 60초. '떠 있음'은 **띄우는 자리에서** 적는다(같은 차례의 두 번째 호출이 또 띄우지 않게 — 주간 보상 실측: 콜드 스타트 세 번).
//  ② 받기 — 같은 키는 한 번에 하나 · 전부 받기가 떠 있으면 낱개도 기다린다. 실패는 **그 줄**이 말한다.
//  ③ 순서 — 잔량은 **그 사이 미러에 다른 쓰기가 없었을 때만** 옮긴다(WeeklyWorkRules.shouldApplyRuby). 못 썼는데 받은 게 있으면
//     상점을 다시 읽어 맞춘다. 받기 **전**에 떠난 조회가 받기 **뒤**에 도착하면 버린다(achievementClaimWriteKey). 겹친 받기 둘의 답이
//     뒤바뀌어 와도 받음은 되돌아가지 않는다(merged).
//  ④ 세대 · 순번 가드. ⑤ 연출 상태는 스토어가 쥔다.
// v0.3.64 일일 미션: ⑥ 판 끝 이벤트 박자(하루 첫 판만 · 일일 모르는 서버엔 0건 · 떠 있는 조회면 깃발 후 한 번 더) ⑦ `daily_mission_claim`
// (장부는 누적과 따로) ⑧ 날짜 넘김은 서버 시각(server_now_ms 로 잰 시계 차)으로 ⑨ 배지 = 일일 + 누적 + 주간(날을 넘긴 일일 줄은 뺀다).

/** 받기 연출 한 번(어느 줄에 · 얼마를 · 몇 번째로). 줄은 [target] 으로 자기 연출을 찾고 [serial] 로 처음부터 다시 그린다. */
class MeClaimBurst(val serial: Int, val target: String, amount: Long) {
    val amount: Long = maxOf(0L, amount)

    override fun equals(other: Any?): Boolean =
        other is MeClaimBurst && other.serial == serial && other.target == target && other.amount == amount

    override fun hashCode(): Int = (serial * 31 + target.hashCode()) * 31 + amount.hashCode()
    override fun toString(): String = "MeClaimBurst(serial=$serial, target=$target, amount=$amount)"

    companion object {
        /** 도전 미션 줄의 자리 — **계열**이다(콕 10 을 받으면 같은 줄이 콕 50 으로 바뀌어도 연출은 그 줄 위에 남는다). */
        fun achievementTarget(series: String): String = "achievement:$series"
        const val WEEKLY_TARGET = "weekly"

        /** 일일 미션 줄의 자리(키마다 한 줄). 누적 자리와 겹치지 않는다. */
        fun dailyTarget(key: String): String = "daily:$key"
    }
}

/** 도전 미션 절을 어떻게 그리는가 — 스토어 값 셋(응답 · 함수 없음 · 실패)에서 **한 곳**([achievementSection])이 고른다. */
sealed interface MeAchievementSection {
    /** 절이 없다 — 이 서버엔 도전 미션이 없다 또는 줄이 하나도 없다. */
    data object Hidden : MeAchievementSection
    data object Loading : MeAchievementSection

    /** 한 번도 못 받았는데 마지막 조회가 실패했다 — 실패 문장 + [다시 시도]. */
    data object Failed : MeAchievementSection

    /** 계열마다 한 줄 + 받을 것의 수(계열로 접기 **전**). */
    data class Loaded(val rows: List<AchievementStatus.Mission>, val claimableCount: Int) : MeAchievementSection
}

// MARK: 화면 값

val MeStore.achievementSection: MeAchievementSection
    get() {
        if (!achievementsAvailable || !context.sessionStore.isSignedIn) return MeAchievementSection.Hidden
        val status = achievements
        if (status != null) {
            // 받아 둔 값이 있으면 실패해도 그 값을 그린다(알던 줄을 지우지 않는다).
            val rows = status.seriesRows
            return if (rows.isEmpty()) MeAchievementSection.Hidden else MeAchievementSection.Loaded(rows, status.claimableCount)
        }
        return if (achievementsState.hasFailed) MeAchievementSection.Failed else MeAchievementSection.Loading
    }

val MeStore.achievementRows: List<AchievementStatus.Mission>
    get() = (achievementSection as? MeAchievementSection.Loaded)?.rows ?: emptyList()

/** 받을 도전 미션 수(계열로 접기 **전**). 서버에 기능이 없으면 0. */
val MeStore.achievementClaimableCount: Int
    get() = if (!achievementsAvailable) 0 else achievements?.claimableCount ?: 0

/** 받을 도전 미션의 루비 합([전부 받기] 버튼의 숫자). */
val MeStore.achievementClaimableRuby: Long
    get() = if (!achievementsAvailable) 0 else achievements?.claimableRuby ?: 0

/** 지금 받을 수 있는 것 전부의 수 = 일일(날을 넘긴 줄 제외) + 누적 + 이번 주 근무 단계(어느 주든). 배지 · 머리 문구가 같은 수를 말한다. */
val MeStore.missionClaimableCount: Int
    get() = dailyMissionClaimableCount + achievementClaimableCount + (if (weeklyWorkAvailable) weeklyWork?.pendingCount ?: 0 else 0)

/** 루트에 [미션] 줄을 세우는가 — 주간·도전 미션 둘 중 하나라도 그릴 것이 있을 때. */
val MeStore.showsMissionsRow: Boolean get() = showsWeeklyWork || achievementSection != MeAchievementSection.Hidden

/** 미션 화면이 둘 다 못 그리는가(들어간 **뒤** 서버가 기능을 잃을 수 있어 화면이 할 말을 갖는다). */
val MeStore.missionsPageIsEmpty: Boolean get() = !showsWeeklyWork && achievementSection == MeAchievementSection.Hidden

/** 이 줄의 [받기]가 떠 있는가. 전부 받기가 떠 있으면 낱개 줄도 떠 있는 것으로 본다. */
fun MeStore.isClaimingAchievement(key: String): Boolean =
    key in achievementClaimsInFlight || MeStore.ACHIEVEMENT_CLAIM_ALL_SLOT in achievementClaimsInFlight

fun MeStore.achievementClaimDidFail(key: String): Boolean = key in achievementClaimFailedKeys

fun MeStore.claimBurst(series: String): MeClaimBurst? = missionClaimBursts[MeClaimBurst.achievementTarget(series)]

val MeStore.weeklyClaimBurst: MeClaimBurst? get() = missionClaimBursts[MeClaimBurst.WEEKLY_TARGET]

// MARK: 조회

/** 낡았으면 읽는다(60초 스로틀). 떠 있으면 겹쳐 띄우지 않는다 — '떠 있다'를 **띄우는 이 자리에서 바로** 적는다. */
fun MeStore.refreshAchievementsIfStale() {
    if (!context.sessionStore.isSignedIn || achievementsState.isLoading || !isStale(achievementsState)) return
    achievementsState.isLoading = true
    launch { loadAchievements() }
}

/** 절의 [다시 시도] — 스로틀 없이 한 번. 떠 있으면 요청 0건. */
fun MeStore.retryAchievements() {
    if (!context.sessionStore.isSignedIn || achievementsState.isLoading) return
    achievementsState.isLoading = true
    launch { loadAchievements() }
}

/** 미션 화면 당겨서 새로 고치기 — 이 화면에 있는 것만(일일은 `achievements_status` 의 `daily` 라 조회 하나가 일일·누적을 같이 데려온다). */
suspend fun MeStore.refreshMissions() {
    if (!context.sessionStore.isSignedIn) return
    coroutineScope {
        launch { loadWeeklyWork() }
        launch { loadAchievements() }
    }
}

/** `achievements_status()` 한 번 **+ 꼬리**: 떠 있는 동안 판이 끝났으면 끝난 뒤 정확히 한 번 더 묻는다(⑥). */
suspend fun MeStore.loadAchievements() {
    performAchievementsFetch()
    drainAchievementsGameRefetch()
}

/** 실제 왕복. 세대 · 순번 · 받기 가드. */
internal suspend fun MeStore.performAchievementsFetch() {
    if (!context.sessionStore.isSignedIn) {
        // 띄우는 자리가 미리 적어 둔 '떠 있음'을 거둔다 — 안 거두면 다음 조회가 영영 안 뜬다.
        achievementsState.isLoading = false
        return
    }
    val serial = nextSerial("achievements")
    val generation = context.generation
    // 루비 미러에 쓴 횟수와 받기를 옮긴 횟수를 **떠날 때** 찍는다.
    val rubyWriteAtDeparture = context.ruby.rubyWriteSerial
    val claimStamp = writeStamp(MeStore.ACHIEVEMENT_CLAIM_WRITE_KEY)
    achievementsState.isLoading = true
    try {
        val service = context.service
        val status = try {
            AchievementStatus.decode(context.withSessionRetry { s -> service.achievementsStatusRaw(s.accessToken) })
        } catch (e: Throwable) {
            if (generation != context.generation || !isCurrent("achievements", serial)) return
            if (AuthErrorRules.classify(e) == AuthErrorDisposition.cancelled) return
            if (MeWireBridge.isMissingFunction(e)) {
                // 함수가 없는 서버(db push 전) — 절을 조용히 감추고 스로틀 간격 뒤에 다시 묻는다. 알던 값도 버린다(서버가 기능을 거뒀다).
                achievementsAvailable = false
                achievements = null
                achievementsState.hasFailed = false
                achievementsState.loadedAt = context.clock.now()
                return
            }
            // 못 읽었다 — 지난 값을 그대로 둔다(빈 목록으로 지어내지 않는다).
            achievementsState.hasFailed = true
            return
        }
        if (generation != context.generation || !isCurrent("achievements", serial)) return
        // 떠난 뒤 받기 응답이 옮겨졌다 — 이 답은 받기 **전**의 서버를 말할 수 있다. 버린다(받기 응답이 이미 더 새 상태를 줬다).
        if (writeStamp(MeStore.ACHIEVEMENT_CLAIM_WRITE_KEY) != claimStamp) return
        applyAchievementStatus(status, rubyWriteAtDeparture)
    } finally {
        if (isCurrent("achievements", serial)) achievementsState.isLoading = false
    }
}

/**
 * 응답 반영(순수 상태 전이 — 네트워크 없음). 조회 · 받기 둘 다 여기를 지난다.
 * [rubyWriteSerialAtDeparture] = 요청이 떠날 때의 루비 미러 쓰기 횟수. null 이면 비교하지 않는다(직접 부르는 시험).
 */
internal fun MeStore.applyAchievementStatus(status: AchievementStatus, rubyWriteSerialAtDeparture: Int? = null) {
    achievementsAvailable = true
    // 서버 시계 − 이 폰 시계(일일 줄의 날짜 넘김을 **서버 시각**으로 판정). 서버가 안 알려 주면 이 폰 시계를 믿는다(0).
    achievementsServerClockOffsetMs = status.serverNowMs?.let { it - MeStore.epochMs(context.clock.now()) } ?: 0
    // 받기가 404 로 접혔던 서버가 daily 를 싣고 왔다 = 기능이 있다.
    if (status.daily != null && !dailyMissionsAvailable) dailyMissionsAvailable = true
    achievementsState.hasLoaded = true
    achievementsState.hasFailed = false
    achievementsState.loadedAt = context.clock.now()
    // 받음은 되돌아가지 않는다 — 겹친 받기 둘의 답이 뒤바뀌어 와도.
    achievements = status.merged(achievements)

    val departure = rubyWriteSerialAtDeparture ?: context.ruby.rubyWriteSerial
    val ruby = status.rubyBalance
    if (WeeklyWorkRules.shouldApplyRuby(ruby, departure, context.ruby.rubyWriteSerial) && ruby != null) {
        context.ruby.rubyBalance = maxOf(0L, ruby)
    } else if (status.claimedNowRuby > 0) {
        // 그 사이 다른 쓰기가 있어 이 잔량은 버렸다 — 그런데 루비가 늘었으니 사실을 다시 읽는다(옛 잔량이 화면에 남지 않게).
        launch { loadShop() }
    }
}

// MARK: 받기

/** 도전 미션 받기. [key] 가 null 이면 받을 것 전부. **같은 키가 떠 있으면 요청 0건**. */
fun MeStore.claimAchievement(key: String?) {
    if (!context.sessionStore.isSignedIn || !achievementsAvailable) return
    val slot = key ?: MeStore.ACHIEVEMENT_CLAIM_ALL_SLOT
    // 전부 받기가 떠 있으면 낱개도 기다린다 — 같은 행을 두 요청이 함께 잡지 않게.
    if (slot in achievementClaimsInFlight || MeStore.ACHIEVEMENT_CLAIM_ALL_SLOT in achievementClaimsInFlight) return
    // '떠 있음'은 띄우는 이 자리에서 적는다.
    achievementClaimsInFlight = achievementClaimsInFlight + slot
    val generation = context.generation
    val rubyWriteAtDeparture = context.ruby.rubyWriteSerial
    val service = context.service
    launch {
        try {
            val status = try {
                AchievementStatus.decode(context.withSessionRetry { s -> service.achievementClaimRaw(s.accessToken, key) })
            } catch (e: Throwable) {
                if (generation != context.generation) return@launch
                if (AuthErrorRules.classify(e) == AuthErrorDisposition.cancelled) return@launch
                if (MeWireBridge.isMissingFunction(e)) {
                    // 받기 함수가 없다 = 이 서버엔 받기가 없다 — 절을 감춘다.
                    achievementsAvailable = false
                    achievements = null
                    achievementsState.hasFailed = false
                    achievementsState.loadedAt = context.clock.now()
                    return@launch
                }
                // 실패는 그 줄이 말한다. 버튼은 그대로 남아 다시 누르는 것이 재시도다.
                markAchievementClaim(key, failed = true)
                return@launch
            }
            if (generation != context.generation) return@launch
            // 받기를 옮긴다 — 이 뒤에 도착하는 **받기 전** 조회는 버려진다.
            noteLocalWrite(MeStore.ACHIEVEMENT_CLAIM_WRITE_KEY)
            applyAchievementStatus(status, rubyWriteAtDeparture)
            markAchievementClaim(key, failed = false)
            celebrateAchievementClaims(status)
        } finally {
            if (generation == context.generation) achievementClaimsInFlight = achievementClaimsInFlight - slot
        }
    }
}

/** 받을 것 전부 받기(`achievement_claim(null)`) — 받을 것이 없으면 요청 0건. */
fun MeStore.claimAllAchievements() {
    if (achievementClaimableCount <= 0) return
    claimAchievement(null)
}

/** 받기 실패 표시를 세우거나 내린다. [key] 가 null(전부 받기)이면 지금 받을 수 있는 줄 전부. 바뀔 때만 대입한다. */
private fun MeStore.markAchievementClaim(key: String?, failed: Boolean) {
    val keys = key?.let { setOf(it) } ?: (achievements?.claimable?.map { it.key }?.toSet() ?: emptySet())
    val next = when {
        failed -> achievementClaimFailedKeys + keys
        // 전부 받기가 성공했다 — 이 장부를 통째로 비운다(여기 적히는 키는 **누적 키뿐** — 일일 실패 문장은 다른 장부다).
        key == null -> emptySet()
        else -> achievementClaimFailedKeys - keys
    }
    if (next != achievementClaimFailedKeys) achievementClaimFailedKeys = next
}

/** 이 호출이 넣은 지급만큼 연출한다 — 줄(계열)마다 하나. */
private fun MeStore.celebrateAchievementClaims(status: AchievementStatus) {
    val perSeries = LinkedHashMap<String, Long>()
    for (claim in status.claimedNow) {
        if (claim.reward <= 0) continue
        val series = status.series(claim.key) ?: claim.key
        perSeries[series] = (perSeries[series] ?: 0L) + claim.reward
    }
    for ((series, amount) in perSeries) startClaimBurst(MeClaimBurst.achievementTarget(series), amount)
}

// MARK: 연출

/** 연출 하나를 세운다(순번을 올려 같은 줄의 두 번째 받기도 처음부터 다시 그려지게). */
internal fun MeStore.startClaimBurst(target: String, amount: Long) {
    if (amount <= 0) return
    missionClaimBurstSerial += 1
    missionClaimBursts = missionClaimBursts + (target to MeClaimBurst(missionClaimBurstSerial, target, amount))
}

fun MeStore.clearMissionClaimBursts() {
    if (missionClaimBursts.isNotEmpty()) missionClaimBursts = emptyMap()
}

fun MeStore.clearMissionClaimFailures() {
    if (achievementClaimFailedKeys.isNotEmpty()) achievementClaimFailedKeys = emptySet()
    if (dailyMissionClaimFailedKeys.isNotEmpty()) dailyMissionClaimFailedKeys = emptySet()
    if (weeklyClaimFailed) weeklyClaimFailed = false
}

/** 나 탭을 떠날 때: 연출과 실패 문장을 걷는다. 떠 있는 받기 요청은 끊지 않는다(응답은 화면이 없어도 옮겨진다). */
internal fun MeStore.missionsTabDidDisappear() {
    clearMissionClaimBursts()
    clearMissionClaimFailures()
}

// MARK: - 일일 미션 (v0.3.64) — 여기도 판정하지 않는다. 클라가 판정하는 것은 **하루가 끝났는가** 하나뿐이고,
// 그 판정도 응답의 reset_at_ms 와 server_now_ms 로만 한다(시계를 돌려 놓은 폰을 믿지 않는다).

/** 서버 시각의 추정(밀리초) = 이 폰 시계 + 마지막 응답이 잰 시계 차. */
internal fun MeStore.estimatedServerNowMs(): Long = MeStore.epochMs(context.clock.now()) + achievementsServerClockOffsetMs

/** Swift `Int((date.timeIntervalSince1970 * 1000).rounded(.down))`. */
internal fun MeStore.Companion.epochMs(date: SwiftDate): Long = floor(date.timeIntervalSince1970 * 1000).toLong()

/**
 * 이 응답의 줄을 판정할 서버 시각. 넘김을 **적어 둔** 응답이면 리셋 시각 아래로 내려가지 않는다(한 번 내린 [받기]가 되살아나지 않게).
 * INV-MeStoreAchievements-e9cb1830 이식: 이 읽기가 곧 관찰 등록이다 — [MeStore.dailyMissionRolloverNoted] 는 스냅숏 상태라
 *   그 값을 쓰면 이 값을 읽은 줄 · 배지가 다시 그려진다(시계는 관찰 밖이다).
 */
internal fun MeStore.dailyServerNowMs(daily: DailyMissionStatus): Long {
    val now = estimatedServerNowMs()
    val noted = dailyMissionRolloverNoted
    if (noted == null || noted != daily.resetAtMs) return now
    return maxOf(now, noted)
}

/** 일일 절이 그릴 줄. **null = 절을 통째로 감춘다**. 하루가 끝난 응답이면 새 날의 모양(진행 0 · [받기] 없음)이다. */
val MeStore.dailyMissionRows: List<DailyMissionStatus.Mission>?
    get() {
        if (!context.sessionStore.isSignedIn || !achievementsAvailable || !dailyMissionsAvailable) return null
        val daily = achievements?.daily ?: return null
        if (daily.missions.isEmpty()) return null
        return daily.rows(dailyServerNowMs(daily))
    }

/** 받을 수 있는 일일 줄의 수(날을 넘긴 줄은 안 센다). */
val MeStore.dailyMissionClaimableCount: Int get() = dailyMissionRows?.count { it.row.isClaimable } ?: 0

val MeStore.dailyMissionClaimableRuby: Long get() = dailyMissionRows?.filter { it.row.isClaimable }?.sumOf { it.row.reward } ?: 0

/** 일일 절을 어떻게 그리는가 — 받을 수 · 루비는 **줄에서** 센다(날을 넘긴 줄이 빠진 뒤의 수). */
val MeStore.dailyMissionSection: MeDailyMissionSection
    get() {
        if (!dailyMissionsAvailable) return MeDailyMissionSection.Hidden
        val rows = dailyMissionRows
        if (rows.isNullOrEmpty()) return MeDailyMissionSection.Hidden
        return MeDailyMissionSection.Loaded(rows, dailyMissionClaimableCount, dailyMissionClaimableRuby)
    }

/** 이 일일 줄의 [받기]가 떠 있는가. 누적 받기는 **세지 않는다**. */
fun MeStore.isClaimingDailyMission(key: String): Boolean =
    key in dailyMissionClaimsInFlight || MeStore.ACHIEVEMENT_CLAIM_ALL_SLOT in dailyMissionClaimsInFlight

fun MeStore.dailyMissionClaimDidFail(key: String): Boolean = key in dailyMissionClaimFailedKeys

fun MeStore.dailyClaimBurst(key: String): MeClaimBurst? = missionClaimBursts[MeClaimBurst.dailyTarget(key)]

// MARK: 날 넘김

/** 서버 시각으로 이 응답의 하루가 끝났으면 그 사실을 **한 번** 적는다. 적었으면 참. 아니면 아무것도 쓰지 않는다. */
fun MeStore.noteDailyMissionRollover(): Boolean {
    val daily = achievements?.daily ?: return false
    val reset = daily.resetAtMs ?: return false
    if (dailyMissionRolloverNoted == reset || !daily.hasRolledOver(estimatedServerNowMs())) return false
    dailyMissionRolloverNoted = reset
    return true
}

/** 날을 넘겼으면 적고 **스로틀을 건너뛰어** 새 날을 묻는다. 안 넘겼으면 요청 0건. */
internal fun MeStore.refreshAchievementsIfDayRolledOver() {
    if (!noteDailyMissionRollover()) return
    retryAchievements()
}

// MARK: 판 끝난 뒤 조회(⑥)

/**
 * 게임 한 판이 서버에 남은 직후의 조회 — **이벤트로만** 부른다(미니게임 제출 성공 · 1:1 판이 끝난 것을 처음 본 순간). [game] 은
 * `MiniGameKind` 원시값 또는 `gomoku` · `chess` · `tetris_duel`.
 *  · 오늘 그 게임 줄을 이미 채웠으면 요청 0건. · 떠 있는 조회가 있으면 0건이되 깃발을 세운다(끝난 뒤 한 번 더).
 *  · 이 서버가 일일을 모르면 0건(안 막으면 마이그레이션 전 서버에서 판마다 한 건씩 는다).
 */
fun MeStore.refreshAchievementsAfterGameResult(game: String) {
    if (!context.sessionStore.isSignedIn || !achievementsAvailable || !dailyMissionsAvailable) return
    val daily = achievements?.daily ?: return
    if (daily.rows(dailyServerNowMs(daily)).firstOrNull { it.key == DailyMissionStatus.key(game) }?.row?.achieved == true) return
    if (achievementsState.isLoading) {
        achievementsRefetchAfterGame = true
        return
    }
    achievementsState.isLoading = true
    launch { loadAchievements() }
}

/** 조회 하나가 끝난 꼬리에서 깃발을 배수한다. */
internal fun MeStore.drainAchievementsGameRefetch() {
    if (!achievementsRefetchAfterGame) return
    if (!context.sessionStore.isSignedIn || !achievementsAvailable) {
        // 물을 곳이 없다 — 깃발을 들고 있으면 다음 조회 꼬리에서 엉뚱하게 터진다.
        achievementsRefetchAfterGame = false
        return
    }
    // 다른 조회가 아직 떠 있다(내가 버려진 순번이다) — 그쪽 꼬리가 배수한다.
    if (achievementsState.isLoading) return
    achievementsRefetchAfterGame = false
    achievementsState.isLoading = true
    launch { loadAchievements() }
}

// MARK: 일일 받기(⑦)

/**
 * 일일 미션 받기. [key] 가 null 이면 오늘 받을 것 전부. **지금 받을 수 있는 줄이 아니면 요청 0건** · 같은 키(또는 전부)가 떠 있어도 0건.
 * 받을 수 있던 줄인데 리셋을 넘겨 막혔으면 넘김을 적고(버튼이 그 자리에서 내려간다) 조회를 한 번 부른다(반응 없는 버튼 금지).
 */
fun MeStore.claimDailyMission(key: String?) {
    if (!context.sessionStore.isSignedIn || !achievementsAvailable || !dailyMissionsAvailable) return
    val daily = achievements?.daily ?: return
    val claimable = daily.claimable(dailyServerNowMs(daily))
    val wanted = if (key != null) claimable.any { it.key == key } else claimable.isNotEmpty()
    if (!wanted) {
        val wasClaimable = if (key != null) daily.mission(key)?.row?.isClaimable == true else daily.missions.any { it.row.isClaimable }
        if (wasClaimable && daily.hasRolledOver(dailyServerNowMs(daily))) {
            noteDailyMissionRollover()
            retryAchievements()
        }
        return
    }
    val slot = key ?: MeStore.ACHIEVEMENT_CLAIM_ALL_SLOT
    if (slot in dailyMissionClaimsInFlight || MeStore.ACHIEVEMENT_CLAIM_ALL_SLOT in dailyMissionClaimsInFlight) return
    dailyMissionClaimsInFlight = dailyMissionClaimsInFlight + slot
    val generation = context.generation
    val rubyWriteAtDeparture = context.ruby.rubyWriteSerial
    val service = context.service
    launch {
        try {
            val status = try {
                AchievementStatus.decode(context.withSessionRetry { s -> service.dailyMissionClaimRaw(s.accessToken, key) })
            } catch (e: Throwable) {
                if (generation != context.generation) return@launch
                if (AuthErrorRules.classify(e) == AuthErrorDisposition.cancelled) return@launch
                if (MeWireBridge.isMissingFunction(e)) {
                    // 받기 함수가 없다 = 이 서버엔 일일 미션이 없다 — **일일 절만** 접는다(누적 · 주간은 그대로).
                    dailyMissionsAvailable = false
                    return@launch
                }
                markDailyMissionClaim(key, failed = true)
                return@launch
            }
            if (generation != context.generation) return@launch
            // 누적 받기와 같은 도장을 쓴다: 응답이 같은 모양 전체(누적 + 일일 + 잔량)라 늦은 조회가 덮으면 양쪽이 되돌아간다.
            noteLocalWrite(MeStore.ACHIEVEMENT_CLAIM_WRITE_KEY)
            applyAchievementStatus(status, rubyWriteAtDeparture)
            markDailyMissionClaim(key, failed = false)
            celebrateDailyMissionClaims(status)
        } finally {
            if (generation == context.generation) dailyMissionClaimsInFlight = dailyMissionClaimsInFlight - slot
        }
    }
}

/**
 * 오늘 받을 일일 전부 받기(`daily_mission_claim(null)`).
 * INV-MeStoreAchievements-88b2550f 이식: 여기서 "받을 것이 있는가"를 **미리 세지 않는다** — 세면 날을 넘긴 순간 그냥 돌아와 화면에 남은
 *   어제 [전부 받기]가 **반응 없는 버튼**이 된다. 판정 · 넘김 처리는 낱개와 같은 길([claimDailyMission]) 하나가 한다.
 */
fun MeStore.claimAllDailyMissions() {
    claimDailyMission(null)
}

private fun MeStore.markDailyMissionClaim(key: String?, failed: Boolean) {
    val claimable = achievements?.daily?.let { d -> d.claimable(dailyServerNowMs(d)).map { it.key } } ?: emptyList()
    val keys = key?.let { setOf(it) } ?: claimable.toSet()
    val next = when {
        failed -> dailyMissionClaimFailedKeys + keys
        // 일일 전부 받기가 성공했다 — **이 장부만** 비운다(누적 줄의 실패 문장은 그대로 선다).
        key == null -> emptySet()
        else -> dailyMissionClaimFailedKeys - keys
    }
    if (next != dailyMissionClaimFailedKeys) dailyMissionClaimFailedKeys = next
}

private fun MeStore.celebrateDailyMissionClaims(status: AchievementStatus) {
    for (claim in status.claimedNow) {
        if (claim.reward > 0) startClaimBurst(MeClaimBurst.dailyTarget(claim.key), claim.reward)
    }
}
