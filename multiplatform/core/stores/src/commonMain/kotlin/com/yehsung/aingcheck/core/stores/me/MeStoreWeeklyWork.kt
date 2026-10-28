// 원본: Sources/CheckMobileKit/Me/MeStoreWeeklyWork.swift @ 1b8260d
package com.yehsung.aingcheck.core.stores.me

import com.yehsung.aingcheck.core.net.AuthErrorDisposition
import com.yehsung.aingcheck.core.net.AuthErrorRules
import com.yehsung.aingcheck.core.net.weeklyWorkClaimRaw
import com.yehsung.aingcheck.core.net.weeklyWorkStatusRaw
import com.yehsung.aingcheck.core.rules.weekly.WeeklyWorkStatus

// 이번 주 누적 근무 보상(v0.3.55) — `weekly_work_status()` 를 부르고 옮기기만 한다. 규칙은 MeWeeklyWork.kt.
// 언제 읽나: 앱이 앞에 올 때(탭이 안 보여도) · 나 탭이 보일 때 · 당겨서 새로고침 — 셋 다 60초 스로틀. 폰 [근무 종료] 직후는 스로틀 없이
// 한 번(weeklyWorkDidChange). 주가 바뀌었으면(월요일 0시를 넘었으면) 스로틀 없이.

/** 카드를 세울지: 서버에 함수가 있고 · 값이 있거나 첫 조회 중이거나 첫 조회가 실패했다(자리를 지키고 한 줄만 바꾼다). */
val MeStore.showsWeeklyWork: Boolean
    get() {
        if (!weeklyWorkAvailable || !context.sessionStore.isSignedIn) return false
        return weeklyWork != null || weeklyWorkState.isLoading || weeklyWorkState.hasFailed
    }

/** [받기 +N] 을 세우는가(v0.3.58) — 받기 서버이고 받을 단계가 있다. 옛 서버는 언제나 거짓. */
val MeStore.showsWeeklyClaim: Boolean get() = showsWeeklyWork && weeklyWork?.hasClaimable == true

/** 버튼의 숫자 — 받을 루비 합(어느 주든). */
val MeStore.weeklyClaimableRuby: Long get() = if (!weeklyWorkAvailable) 0 else weeklyWork?.pendingRuby ?: 0

/** 지금 누를 수 있는가(떠 있는 받기가 없고 받을 것이 있다). */
val MeStore.canClaimWeeklyWork: Boolean get() = !weeklyClaimInFlight && showsWeeklyClaim

/**
 * 낡았으면 읽는다(60초 스로틀 · 주가 바뀌었으면 바로). '떠 있다'는 **띄우는 이 자리에서 바로** 적는다 — 안에서 적으면 같은 차례의
 * 두 번째 호출이 또 띄운다(콜드 스타트에 세 번 나갔다 — 검토 지적 2026-10-16. 하나하나가 서버에서 지갑 자물쇠를 잡는 정산이다).
 */
fun MeStore.refreshWeeklyWorkIfStale() {
    if (!context.sessionStore.isSignedIn || weeklyWorkState.isLoading) return
    val rolled = WeeklyWorkRules.weekHasRolled(weeklyWork, context.clock.now())
    if (!rolled && !isStale(weeklyWorkState)) return
    weeklyWorkState.isLoading = true
    launch { loadWeeklyWork() }
}

/** 근무가 막 끝났다(폰 [근무 종료]) — 스로틀 없이 한 번. 떠 있는 조회는 순번에 밀려 버려진다(종료 전에 떠난 값이라서). */
fun MeStore.weeklyWorkDidChange() {
    if (!context.sessionStore.isSignedIn) return
    launch { loadWeeklyWork() }
}

/** `weekly_work_status()` 한 번. 세대 · 순번 · 받기 도장 가드. */
suspend fun MeStore.loadWeeklyWork() {
    if (!context.sessionStore.isSignedIn) {
        // 띄우는 자리가 미리 적어 둔 '떠 있음'을 거둔다.
        weeklyWorkState.isLoading = false
        return
    }
    val serial = nextSerial("weekly")
    val generation = context.generation
    // 루비 미러에 쓴 횟수를 떠날 때 찍는다 — 도착했을 때 그 사이 누가 썼으면 그쪽이 더 새 값일 수 있다.
    val rubyWriteAtDeparture = context.ruby.rubyWriteSerial
    // 받기를 옮긴 횟수도 찍는다(v0.3.58) — 받기 뒤에 도착한 **받기 전** 조회를 덮어쓰기에서 막는다.
    val claimStamp = writeStamp(MeStore.WEEKLY_CLAIM_WRITE_KEY)
    weeklyWorkState.isLoading = true
    try {
        val service = context.service
        val status = try {
            WeeklyWorkStatus.decode(context.withSessionRetry { s -> service.weeklyWorkStatusRaw(s.accessToken) })
        } catch (e: Throwable) {
            if (generation != context.generation || !isCurrent("weekly", serial)) return
            if (AuthErrorRules.classify(e) == AuthErrorDisposition.cancelled) return
            if (MeWireBridge.isMissingFunction(e)) {
                // 함수가 없는 서버 — 카드를 접고, 스로틀 간격 뒤에 다시 묻는다.
                weeklyWorkAvailable = false
                weeklyWork = null
                weeklyWorkState.hasFailed = false
                weeklyWorkState.loadedAt = context.clock.now()
                return
            }
            // 못 읽었다 — 지난 값을 그대로 둔다(0 시간으로 지어내지 않는다).
            weeklyWorkState.hasFailed = true
            return
        }
        if (generation != context.generation || !isCurrent("weekly", serial)) return
        // 떠난 뒤 받기 응답이 옮겨졌다 — 이 답은 받기 **전**의 서버를 말할 수 있다. 버린다.
        if (writeStamp(MeStore.WEEKLY_CLAIM_WRITE_KEY) != claimStamp) return
        applyWeeklyWorkStatus(status, rubyWriteAtDeparture)
    } finally {
        if (isCurrent("weekly", serial)) weeklyWorkState.isLoading = false
    }
}

/** 응답을 화면에 옮긴다: 상태 · 루비(더 새 값을 되돌리지 않게) · '받았어요' 알림(+ 햅틱 순번) · 이 기기가 본 칸 저장. */
internal fun MeStore.applyWeeklyWorkStatus(status: WeeklyWorkStatus, rubyWriteSerialAtDeparture: Int) {
    weeklyWorkAvailable = true
    // 카드를 그릴 만큼 모르는 응답(누적초 · 칸 표가 빠진 서버 어긋남)은 알던 값을 덮지 않는다 — 모르는 누적초를 0 으로 그리면 거짓이다.
    if (status.isUsable) weeklyWork = status
    weeklyWorkState.hasLoaded = true
    weeklyWorkState.hasFailed = false
    weeklyWorkState.loadedAt = context.clock.now()

    val previous = loadWeeklyWorkSeen()
    val grants = WeeklyWorkRules.newGrants(previous, status)
    // 본 기록도 칸 표를 알 때만 옮긴다 — 표가 빠진 응답으로 '본 칸 없음'을 적으면 다음 조회가 받은 칸을 다 새로 알린다.
    if (status.tiers.isNotEmpty()) WeeklyWorkRules.seen(status)?.let(::storeWeeklyWorkSeen)

    val ruby = status.rubyBalance
    if (WeeklyWorkRules.shouldApplyRuby(ruby, rubyWriteSerialAtDeparture, context.ruby.rubyWriteSerial) && ruby != null) {
        context.ruby.rubyBalance = ruby
    } else if (grants.isNotEmpty() || status.grantedNow.isNotEmpty() || status.claimedNow.isNotEmpty()) {
        // 받은 게 있는데 그 사이 미러가 바뀌어 잔량을 못 썼다 — 상점을 다시 읽어 지급이 들어간 잔량으로 맞춘다.
        launch { loadShop() }
    }

    val notice = WeeklyWorkRules.notice(grants) ?: return
    weeklyGrantNotice = notice
    weeklyGrantSerial += 1
    weeklyGrantNoticeSeen = isTabVisible
}

/**
 * 이번 주 근무 받기 — **받을 것 전부(어느 주든)** 한 번에(`weekly_work_claim(null, null)`). 떠 있으면 요청 0건, 받을 것이 없으면 나가지 않는다.
 * 받음을 알리는 것은 **연출**이다(자동 지급 칩은 쓰지 않는다 — 같은 일을 두 번 알린다).
 */
fun MeStore.claimWeeklyWork() {
    if (!context.sessionStore.isSignedIn || weeklyClaimInFlight || weeklyWork?.hasClaimable != true) return
    weeklyClaimInFlight = true
    val generation = context.generation
    val rubyWriteAtDeparture = context.ruby.rubyWriteSerial
    val service = context.service
    launch {
        try {
            val status = try {
                WeeklyWorkStatus.decode(context.withSessionRetry { s -> service.weeklyWorkClaimRaw(s.accessToken) })
            } catch (e: Throwable) {
                if (generation != context.generation) return@launch
                if (AuthErrorRules.classify(e) == AuthErrorDisposition.cancelled) return@launch
                // 함수 없음(404)도 여기서는 그냥 실패다 — 상태 · 받기는 한 마이그레이션이라 조용히 삼키면 누른 사람에게 아무 일도 안 일어난다.
                if (!weeklyClaimFailed) weeklyClaimFailed = true
                return@launch
            }
            if (generation != context.generation) return@launch
            // 받기 전에 떠난 주간 조회가 이 뒤에 도착하면 버린다.
            noteLocalWrite(MeStore.WEEKLY_CLAIM_WRITE_KEY)
            applyWeeklyWorkStatus(status, rubyWriteAtDeparture)
            if (weeklyClaimFailed) weeklyClaimFailed = false
            // 이 호출이 **실제로 넣은** 지급만큼 연출한다.
            startClaimBurst(MeClaimBurst.WEEKLY_TARGET, status.claimedNowRuby)
        } finally {
            if (generation == context.generation) weeklyClaimInFlight = false
        }
    }
}

/** 나 탭을 떠날 때: 본 알림은 걷는다. 안 본 알림(탭이 안 보일 때 들어온 것)은 남긴다. */
internal fun MeStore.weeklyTabDidDisappear() {
    if (!weeklyGrantNoticeSeen) return
    weeklyGrantNotice = null
    weeklyGrantNoticeSeen = false
}

/** 계정별 키 — 같은 폰에서 계정을 바꿔도 앞 사람의 '본 칸'을 물려받지 않는다. */
private val MeStore.weeklyWorkSeenKey: String? get() = context.sessionStore.userID?.let { "aing.me.weeklyWorkSeen.$it" }

private fun MeStore.loadWeeklyWorkSeen(): WeeklyWorkSeen? {
    val key = weeklyWorkSeenKey ?: return null
    return WeeklyWorkSeen.decode(context.keyValueStore.getString(key))
}

private fun MeStore.storeWeeklyWorkSeen(seen: WeeklyWorkSeen) {
    val key = weeklyWorkSeenKey ?: return
    context.keyValueStore.putString(key, seen.encoded)
}
