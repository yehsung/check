// 원본: Sources/CheckCore/ChessStoreRanking.swift @ 1b8260d
package com.yehsung.aingcheck.core.stores.chess

import com.yehsung.aingcheck.core.net.chessRanking
import com.yehsung.aingcheck.core.stores.gomoku.CallResult
import com.yehsung.aingcheck.core.stores.gomoku.distantPast
import com.yehsung.aingcheck.core.stores.gomoku.isSchemaMissing
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.games.ChessRPCStatus
import com.yehsung.aingcheck.core.wire.games.ChessRankRow
import com.yehsung.aingcheck.core.wire.games.ChessRankingResponse
import com.yehsung.aingcheck.core.wire.games.ChessUserRow
import kotlinx.coroutines.launch
import kotlin.jvm.JvmName

// 체스 스토어의 **순위표** 갈래 — 승점(승 − 패) 순위와 그 안의 내 자리.
// ── 정렬은 서버가 한다 ── `chess_ranking` 의 order by 그대로. **여기서 다시 정렬하지 않는다** — [ChessRankingOrder] 는 판정이지 정렬기가 아니다.
// ── 실패는 조용하다 ── 순위 조회 실패는 **안내줄(notice)로 새지 않는다**. PGRST202 는 실패가 아니라 `rankingUnavailable` 이다.
// ── 내 순위는 한 출처 ── 머리글이 읽을 순위·승점·전적은 전부 `ranking.me` 다. [myRankConsistentWithRecord] 가 그 가드다.
// ── 전적은 오목과 합치지 않는다(B9) ── 서버가 `chess__record`·`chess_record_epoch` 를 따로 들고 있다.
// **판돈 깃발(§8-17 #1)과는 무관하다.**

/** 순위표 한 줄(화면 값). */
data class ChessRankEntry(
    val id: String,
    /** 서버가 매긴 순위(동률은 같은 숫자, 다음은 건너뛴다 — rank()). */
    val rank: Long,
    val user: ChessUser,
    val wins: Long,
    val losses: Long,
    val draws: Long,
    /** 승점 = 승 − 패. 서버 값 그대로. */
    val points: Long,
)

/** 내 순위 한 줄. [rank] 는 **0판이면 null**(순위 밖) — 전적은 그래도 있다. */
data class ChessMyRank(val rank: Long?, val wins: Long, val losses: Long, val draws: Long, val points: Long)

/** 순위표 전체. **[entries] 는 서버 순서 그대로**(재정렬 금지). */
data class ChessRankingBoard(val entries: List<ChessRankEntry>, val me: ChessMyRank?, val recordSince: SwiftDate?)

/** 순위표 한 번. 도는 중이면 **합치지 않고 버린다**. */
suspend fun ChessStore.loadRanking() {
    if (!spectatorFeaturesEnabled || host?.session == null) return
    val runtime = watchRuntime
    if (runtime.rankingInFlight) return
    runtime.rankingInFlight = true
    val generation = resetGeneration
    try {
        runtime.lastRankingRequestAt = clock()
        when (val result = perform { service, token -> service.chessRanking(token) }) {
            null -> Unit
            is CallResult.Success -> applyRanking(result.value)
            is CallResult.Failure -> {
                if (isSchemaMissing(result.error)) {
                    log("ranking unavailable — function missing on server")
                    if (!rankingUnavailable) rankingUnavailable = true
                    if (rankingLoadFailed) rankingLoadFailed = false
                    // "받은 것" 으로 센다 — 안 그러면 화면이 로딩 문구를 영영 든다.
                    if (!hasLoadedRanking) hasLoadedRanking = true
                } else {
                    log("ranking request failed")
                    if (!rankingLoadFailed) rankingLoadFailed = true
                }
            }
        }
    } finally {
        if (generation == resetGeneration) runtime.rankingInFlight = false
    }
}

/** 순위 응답을 화면 값으로 옮긴다. status ok 만 — 거절은 실패 깃발이고 **안내줄은 만들지 않는다**. */
fun ChessStore.applyRanking(response: ChessRankingResponse) {
    if (response.status != ChessRPCStatus.ok) {
        log("ranking refused status=${response.status.rawValue}")
        if (!rankingLoadFailed) rankingLoadFailed = true
        return
    }
    noteServerNow(response.serverNowMs)
    if (rankingLoadFailed) rankingLoadFailed = false
    if (rankingUnavailable) rankingUnavailable = false
    if (!hasLoadedRanking) hasLoadedRanking = true
    val board = chessRankingBoard(response)
    if (ranking != board) ranking = board
}

/** 머리글용 내 순위. 순위 응답의 전적이 로비 전적과 같을 때만 — 다르면 한쪽이 늦은 것이라 null. */
val ChessStore.myRankConsistentWithRecord: ChessMyRank?
    get() {
        val mine = ranking?.me ?: return null
        val record = record
        if (record != null && record != ChessRecord(mine.wins, mine.losses, mine.draws)) return null
        return mine
    }

/** 내 판이 끝났다 — 전적이 바뀐 순간 순위도 다시 읽는다. **사건에 대한 한 번**이다. 주 스위치가 꺼진 폰은 안 낸다. */
fun ChessStore.noteOwnMatchFinishedForRanking() {
    watchRuntime.lastRankingRequestAt = distantPast
    if (!spectatorFeaturesEnabled || host?.session == null) return
    scope.launch { loadRanking() }
}

/** 응답 → 순위표(순수, Swift `ChessStore.rankingBoard(from:)`). **행 순서는 입력 그대로**. */
fun chessRankingBoard(response: ChessRankingResponse): ChessRankingBoard {
    val entries = (response.rows ?: emptyList()).mapNotNull { row ->
        // 센터 글자 변환점은 `user(from:)` 하나다 — 행 모양이 ChessUserRow 와 같아 그대로 태운다.
        val userRow = ChessUserRow(
            userId = row.userId, displayName = row.displayName, avatarUrl = row.avatarUrl, character = row.character,
            center = row.center, isWorking = null, capable = null, inMatch = null,
        )
        val rank = row.rank ?: return@mapNotNull null
        val user = ChessStore.user(userRow) ?: return@mapNotNull null
        val wins = row.wins ?: 0
        val losses = row.losses ?: 0
        val draws = row.draws ?: 0
        ChessRankEntry(user.id, rank, user, wins, losses, draws, row.points ?: (wins - losses))
    }
    val mine = response.me?.let { me ->
        val wins = me.wins ?: 0
        val losses = me.losses ?: 0
        ChessMyRank(me.rank, wins, losses, me.draws ?: 0, me.points ?: (wins - losses))
    }
    val since = response.recordSinceMs?.let { if (it > 0) SwiftDate(it / 1000) else null }
    return ChessRankingBoard(entries, mine, since)
}

/** 서버 `chess_ranking` 의 정렬 규칙을 옮긴 **판정**(정렬기가 아니다). 오목과 같은 규칙이다 — 두 표가 서로를 설명할 수 있게. */
object ChessRankingOrder {
    data class Key private constructor(val points: Long, val wins: Long, val draws: Long, val userID: String) {
        companion object {
            fun of(points: Long, wins: Long, draws: Long, userID: String): Key = Key(points, wins, draws, userID.lowercase())

            fun of(entry: ChessRankEntry): Key = of(entry.points, entry.wins, entry.draws, entry.id)

            /** user_id 가 없는 행은 키가 없다. */
            fun of(row: ChessRankRow): Key? {
                val id = row.userId
                if (id.isNullOrEmpty()) return null
                val wins = row.wins ?: 0
                val losses = row.losses ?: 0
                return of(row.points ?: (wins - losses), wins, row.draws ?: 0, id)
            }
        }
    }

    /** lhs 가 rhs 보다 **엄격히** 앞서는가. `draws desc` 의 뜻: 같은 승점·같은 승수면 **더 많이 둔 쪽이 위**다. */
    fun precedes(lhs: Key, rhs: Key): Boolean {
        if (lhs.points != rhs.points) return lhs.points > rhs.points
        if (lhs.wins != rhs.wins) return lhs.wins > rhs.wins
        if (lhs.draws != rhs.draws) return lhs.draws > rhs.draws
        return lhs.userID < rhs.userID
    }

    fun ties(lhs: Key, rhs: Key): Boolean = lhs.points == rhs.points && lhs.wins == rhs.wins && lhs.draws == rhs.draws

    @JvmName("isSortedKeys")
    fun isSorted(keys: List<Key>): Boolean = keys.zipWithNext().all { (a, b) -> precedes(a, b) }

    @JvmName("isSortedEntries")
    fun isSorted(entries: List<ChessRankEntry>): Boolean = isSorted(entries.map { Key.of(it) })

    @JvmName("isSortedRows")
    fun isSorted(rows: List<ChessRankRow>): Boolean {
        val keys = rows.mapNotNull { Key.of(it) }
        if (keys.size != rows.size) return false
        return isSorted(keys)
    }

    /** 서버가 매긴 `rank` 가 `rank()` 의 모양인가. **정렬된 배열에서만** 뜻이 있다. */
    fun ranksMatchServerRule(entries: List<ChessRankEntry>): Boolean {
        val keys = entries.map { Key.of(it) }
        for ((index, entry) in entries.withIndex()) {
            val better = keys.take(index).count { !ties(it, keys[index]) }
            if (entry.rank != (better + 1).toLong()) return false
        }
        return true
    }
}
