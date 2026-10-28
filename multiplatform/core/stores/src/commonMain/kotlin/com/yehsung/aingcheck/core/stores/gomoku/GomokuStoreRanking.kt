// 원본: Sources/CheckCore/GomokuStoreRanking.swift @ 1b8260d
package com.yehsung.aingcheck.core.stores.gomoku

import com.yehsung.aingcheck.core.net.gomokuRanking
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.games.GomokuRPCStatus
import com.yehsung.aingcheck.core.wire.games.GomokuRankRow
import com.yehsung.aingcheck.core.wire.games.GomokuRankingResponse
import com.yehsung.aingcheck.core.wire.games.GomokuUserRow
import kotlinx.coroutines.launch
import kotlin.jvm.JvmName

// 오목 스토어의 **순위표** 갈래(0.3.41) — 승점(승 − 패) 순위와 그 안의 내 자리.
//
// ── 정렬은 서버가 한다 ── 행 순서는 서버 `gomoku_ranking` 의 order by(points desc → wins desc → draws desc → user_id asc) 그대로 옮긴다.
// **여기서 다시 정렬하지 않는다.** [GomokuRankingOrder] 는 그 규칙을 옮긴 **판정**이지 정렬기가 아니다.
// ── 실패는 조용하다 ── 순위 조회 실패는 **안내줄(notice)로 새지 않는다**. `rankingLoadFailed` 깃발만 세우고 들고 있던 목록은 지우지 않는다.
// PGRST202 는 실패가 아니라 `rankingUnavailable` 이다.
// ── 내 순위는 한 출처(C16) ── 머리글이 읽을 순위·승점·전적은 전부 `ranking.me` 다. [myRankConsistentWithRecord] 가 그 가드다.
// ── 주 스위치(C11) ── `spectatorFeaturesEnabled` 가 꺼져 있으면 `loadRanking` 은 요청을 내지 않는다. **판돈 깃발(§8-17 #1)과는 무관하다.**

/** 순위표 한 번. 도는 중이면 **합치지 않고 버린다**(60초 주기 목록이라 뒤따르는 한 번이 필요 없다). */
suspend fun GomokuStore.loadRanking() {
    if (!spectatorFeaturesEnabled || host?.session == null) return
    val runtime = watchRuntime
    if (runtime.rankingInFlight) return
    runtime.rankingInFlight = true
    val generation = resetGeneration
    try {
        runtime.lastRankingRequestAt = clock()
        when (val result = perform { service, token -> service.gomokuRanking(token) }) {
            null -> Unit
            is CallResult.Success -> applyRanking(result.value)
            is CallResult.Failure -> {
                if (isSchemaMissing(result.error)) {
                    host.notice(GomokuStore.LOG_TAG, "ranking unavailable — function missing on server")
                    if (!rankingUnavailable) rankingUnavailable = true
                    if (rankingLoadFailed) rankingLoadFailed = false
                    // "받은 것"으로 센다 — 안 그러면 화면이 로딩 문구를 영영 든다. 60초 폴링은 그대로라 서버가 올라오면 저절로 회복한다.
                    if (!hasLoadedRanking) hasLoadedRanking = true
                } else {
                    host.notice(GomokuStore.LOG_TAG, "ranking request failed")
                    if (!rankingLoadFailed) rankingLoadFailed = true
                }
            }
        }
    } finally {
        if (generation == resetGeneration) runtime.rankingInFlight = false
    }
}

/** 순위 응답을 화면 값으로 옮긴다. status ok 만 — 거절은 실패 깃발이고 안내줄은 만들지 않는다. */
fun GomokuStore.applyRanking(response: GomokuRankingResponse) {
    if (response.status != GomokuRPCStatus.ok) {
        host.notice(GomokuStore.LOG_TAG, "ranking refused status=${response.status.rawValue}")
        // unsupported_client 도 여기서는 말하지 않는다 — 같은 순간 나가는 로비 조회가 같은 status 로 이미 말한다.
        if (!rankingLoadFailed) rankingLoadFailed = true
        return
    }
    noteServerNow(response.serverNowMs)
    if (rankingLoadFailed) rankingLoadFailed = false
    if (rankingUnavailable) rankingUnavailable = false
    if (!hasLoadedRanking) hasLoadedRanking = true
    val board = gomokuRankingBoard(response)
    if (ranking != board) ranking = board
}

/** 머리글 캡슐용 내 순위(C16). 순위 응답의 전적이 로비 전적과 같을 때만 — 다르면 한쪽이 늦은 것이라 null. 로비를 아직 못 받았으면 그대로 낸다. */
val GomokuStore.myRankConsistentWithRecord: GomokuMyRank?
    get() {
        val mine = ranking?.me ?: return null
        val record = record
        if (record != null && record != GomokuRecord(mine.wins, mine.losses, mine.draws)) return null
        return mine
    }

/** 내 판이 끝났다(applyState 의 justFinished) — 전적이 바뀐 순간 순위도 다시 읽는다. 주 스위치가 꺼진 폰은 안 낸다. */
fun GomokuStore.noteOwnMatchFinishedForRanking() {
    watchRuntime.lastRankingRequestAt = distantPast // 지금 못 나가도(도는 중) 다음 틱이 바로 읽게
    if (!spectatorFeaturesEnabled || host?.session == null) return
    scope.launch { loadRanking() }
}

/**
 * 응답 → 순위표(순수, Swift `GomokuStore.rankingBoard(from:)`). **행 순서는 입력 그대로**. user_id 나 rank 가 빠진 행은 싣지 않는다.
 * [GomokuRankingBoard.recordSince] 는 기기 시계 보정 없이 서버 순간 그대로다(마감 카운트다운이 아니라 "M월 d일부터" 캡션의 달력 값).
 */
fun gomokuRankingBoard(response: GomokuRankingResponse): GomokuRankingBoard {
    val entries = (response.rows ?: emptyList()).mapNotNull { row ->
        // CenterLabel 변환점은 `user(from:)` 하나다 — 행 모양이 GomokuUserRow 와 같아 그대로 태운다(근무·가능·대국 중은 이 표에 없다 → false).
        val userRow = GomokuUserRow(
            userId = row.userId, displayName = row.displayName, avatarUrl = row.avatarUrl, character = row.character,
            center = row.center, isWorking = null, capable = null, inMatch = null,
        )
        val rank = row.rank ?: return@mapNotNull null
        val user = GomokuStore.user(userRow) ?: return@mapNotNull null
        val wins = row.wins ?: 0
        val losses = row.losses ?: 0
        val draws = row.draws ?: 0
        GomokuRankEntry(user.id, rank, user, wins, losses, draws, row.points ?: (wins - losses))
    }
    val mine = response.me?.let { me ->
        val wins = me.wins ?: 0
        val losses = me.losses ?: 0
        GomokuMyRank(me.rank, wins, losses, me.draws ?: 0, me.points ?: (wins - losses))
    }
    val since = response.recordSinceMs?.let { if (it > 0) SwiftDate(it / 1000) else null }
    return GomokuRankingBoard(entries, mine, since)
}

/**
 * 서버 `gomoku_ranking` 의 정렬 규칙을 옮긴 **판정**(정렬기가 아니다 — 스토어는 재정렬하지 않는다).
 * `order by points desc, wins desc, draws desc, user_id asc` · `rank()` 는 앞 세 축만 본다(동률은 같은 숫자, 다음은 건너뛴다: 3,3,5).
 */
object GomokuRankingOrder {
    /** 한 줄의 정렬 키. */
    data class Key private constructor(val points: Long, val wins: Long, val draws: Long, val userID: String) {
        companion object {
            fun of(points: Long, wins: Long, draws: Long, userID: String): Key = Key(points, wins, draws, userID.lowercase())

            fun of(entry: GomokuRankEntry): Key = of(entry.points, entry.wins, entry.draws, entry.id)

            /** user_id 가 없는 행은 키가 없다(순서를 말할 수 없다). */
            fun of(row: GomokuRankRow): Key? {
                val id = row.userId
                if (id.isNullOrEmpty()) return null
                val wins = row.wins ?: 0
                val losses = row.losses ?: 0
                return of(row.points ?: (wins - losses), wins, row.draws ?: 0, id)
            }
        }
    }

    /**
     * lhs 가 rhs 보다 **엄격히** 앞서는가. 승점 desc → 승 desc → 무 desc → user_id asc.
     * `draws desc` 의 뜻: 같은 승점·같은 승수면 **더 많이 둔 쪽이 위**다 — (1승 1패 1무) 가 (1승 1패 0무) 앞에 선다(서버 실측).
     */
    fun precedes(lhs: Key, rhs: Key): Boolean {
        if (lhs.points != rhs.points) return lhs.points > rhs.points
        if (lhs.wins != rhs.wins) return lhs.wins > rhs.wins
        if (lhs.draws != rhs.draws) return lhs.draws > rhs.draws
        return lhs.userID < rhs.userID
    }

    /** 앞 세 축이 같은가 = `rank()` 가 같은 순위를 주는 쌍. */
    fun ties(lhs: Key, rhs: Key): Boolean = lhs.points == rhs.points && lhs.wins == rhs.wins && lhs.draws == rhs.draws

    /** 배열이 서버 규칙대로 서 있는가(엄격 — user_id 까지 같은 두 줄은 있을 수 없다). */
    @JvmName("isSortedKeys")
    fun isSorted(keys: List<Key>): Boolean = keys.zipWithNext().all { (a, b) -> precedes(a, b) }

    @JvmName("isSortedEntries")
    fun isSorted(entries: List<GomokuRankEntry>): Boolean = isSorted(entries.map(Key::of))

    /** 응답 행 그대로. 키를 못 만드는 행이 하나라도 있으면 false — 그 목록은 순서를 말할 수 없다. */
    @JvmName("isSortedRows")
    fun isSorted(rows: List<GomokuRankRow>): Boolean {
        val keys = rows.mapNotNull { Key.of(it) }
        if (keys.size != rows.size) return false
        return isSorted(keys)
    }

    /** 서버가 매긴 `rank` 가 `rank()` 의 모양인가: 순위 = 1 + 자기보다 (앞 세 축에서) 엄격히 앞선 줄 수. **정렬된 배열에서만** 뜻이 있다. */
    fun ranksMatchServerRule(entries: List<GomokuRankEntry>): Boolean {
        val keys = entries.map(Key::of)
        for ((index, entry) in entries.withIndex()) {
            val better = keys.take(index).count { !ties(it, keys[index]) }
            if (entry.rank != (better + 1).toLong()) return false
        }
        return true
    }
}
