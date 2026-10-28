// 원본: Sources/CheckMobileKit/App/MobileContext.swift(허브가 읽는 칸 — session · storage · clock · links.me) @ 1b8260d
package com.yehsung.aingcheck.core.stores.minigame

import com.yehsung.aingcheck.core.foundation.platform.Collation
import com.yehsung.aingcheck.core.session.context.SessionContext
import kotlinx.coroutines.CoroutineScope

/**
 * 미니게임 허브가 기대는 문맥 — Swift `MobileContext` 중 허브가 실제로 읽는 칸만(W2-a [SessionContext] 를 넓힌다).
 *
 * - [scope]: 허브의 일이 도는 곳(Swift `@MainActor` 의 `Task {}`). 앱은 메인 디스패처, 시험은 시험 디스패처.
 * - [collation]: 오늘 순위 이름 정렬(Swift `localizedStandardCompare`).
 * - [refreshAchievementsAfterGameResult]: 판이 서버에 남은 직후 일일 미션 재조회(Swift `context.links.me?.…` — 나 스토어(W2-c)와의
 *   약한 고리). 조립 지점(W2-f 폰 문맥)이 나 스토어로 잇는다. 고리가 없으면 아무 일도 안 한다.
 */
interface GamesMiniGameContext : SessionContext {
    val scope: CoroutineScope
    val collation: Collation

    fun refreshAchievementsAfterGameResult(game: String)
}
