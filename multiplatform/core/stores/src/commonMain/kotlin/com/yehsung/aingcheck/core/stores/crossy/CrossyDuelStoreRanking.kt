// 원본: Sources/CheckCore/CrossyDuelStoreRanking.swift:56-120 @ e4995a3a(순위 적재) — Android 판 8
// 적재는 테트리스 꼴: 주 스위치(`rankingEnabled`) · 도는 중이면 버림 · PGRST202 → `rankingUnavailable` ·
// 실패는 안내줄로 새지 않는다 — 들고 있던 목록은 지우지 않는다.
package com.yehsung.aingcheck.core.stores.crossy

import com.yehsung.aingcheck.core.net.crossyDuelRanking
import com.yehsung.aingcheck.core.stores.tetris.DISTANT_PAST
import com.yehsung.aingcheck.core.stores.tetris.DuelCall
import com.yehsung.aingcheck.core.stores.tetris.clampedInt
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.games.CrossyDuelRPCStatus
import com.yehsung.aingcheck.core.wire.games.CrossyDuelRankingResponse
import kotlinx.coroutines.launch

/** 순위표 한 번(60초 주기). `rankingEnabled` 가 꺼져 있으면 아무것도 안 한다. */
suspend fun CrossyDuelStore.refreshRanking() {
    if (!rankingEnabled || host?.session == null || rankingInFlight) return
    rankingInFlight = true
    val generation = resetGeneration
    try {
        lastRankingRequestAt = clock()
        val result = perform { service, token -> service.crossyDuelRanking(token) } ?: return
        when (result) {
            is DuelCall.Success -> applyRanking(result.value)
            is DuelCall.Failure -> if (isSchemaMissing(result.error)) {
                if (!rankingUnavailable) rankingUnavailable = true
            } else {
                logNotice("ranking request failed")
            }
        }
    } finally {
        if (generation == resetGeneration) rankingInFlight = false
    }
}

/** 순위 응답을 옮긴다(ok 만 — 값이 같으면 쓰지 않는다). */
fun CrossyDuelStore.applyRanking(response: CrossyDuelRankingResponse) {
    if (response.status != CrossyDuelRPCStatus.ok) {
        logNotice("ranking refused status=${response.status.rawValue}")
        return
    }
    noteServerNow(response.serverNowMs)
    if (rankingUnavailable) rankingUnavailable = false
    val board = rankingBoard(response)
    if (ranking != board) ranking = board
}

/** 내 판이 끝났다 — 전적이 바뀐 순간 순위도 다시 읽는다(창이 안 보여도 사건에 대한 한 번). */
internal fun CrossyDuelStore.noteOwnMatchFinishedForRanking() {
    lastRankingRequestAt = DISTANT_PAST
    if (!rankingEnabled || host?.session == null) return
    scope.launch { refreshRanking() }
}

/** 응답 → 순위표(순수). **행 순서는 입력 그대로**. id 나 rank 가 빠진 행은 싣지 않는다. */
fun rankingBoard(response: CrossyDuelRankingResponse): CrossyDuelRankingBoard {
    val entries = (response.rows ?: emptyList()).mapNotNull { row ->
        val rank = row.rank ?: return@mapNotNull null
        val id = row.id?.lowercase()?.takeIf { it.isNotEmpty() } ?: return@mapNotNull null
        val user = CrossyDuelUser(id = id, displayName = row.displayName ?: "", avatarURL = row.avatarUrl, characterID = row.character)
        val wins = (row.wins ?: 0).clampedInt()
        val losses = (row.losses ?: 0).clampedInt()
        CrossyDuelRankEntry(id, rank.clampedInt(), user, wins, losses, (row.draws ?: 0).clampedInt(), row.points?.clampedInt() ?: (wins - losses))
    }
    val mine = response.me?.let { me ->
        val wins = (me.wins ?: 0).clampedInt()
        val losses = (me.losses ?: 0).clampedInt()
        CrossyDuelMyRank(me.rank?.clampedInt(), wins, losses, (me.draws ?: 0).clampedInt(), me.points?.clampedInt() ?: (wins - losses))
    }
    val since = response.recordSinceMs?.takeIf { it > 0 }?.let { SwiftDate(it / 1000) }
    return CrossyDuelRankingBoard(entries, mine, since)
}
