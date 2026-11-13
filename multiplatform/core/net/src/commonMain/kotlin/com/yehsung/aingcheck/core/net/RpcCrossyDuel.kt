// 원본: Sources/CheckCore/CrossyDuelWire.swift:463-541(길건너 1:1 RPC 8개 · CrossyDuelLockNotAvailable) @ e4995a3a — Android 판 8
//
// 몸통은 공용 [SupabaseWorkService.duelRPC] 하나다. 교착 재시도는 challenge · cancel · respond · resign · state 에 켠다(SPEC §8.2).
// 로비·순위는 읽기 전용이라 끄고, 보고는 뜨거운 길이라 끈다(실패하면 다음 걸음이 누계를 다시 보낸다).
package com.yehsung.aingcheck.core.net

import com.yehsung.aingcheck.core.wire.games.CrossyDuelActionResponse
import com.yehsung.aingcheck.core.wire.games.CrossyDuelChallengeRequest
import com.yehsung.aingcheck.core.wire.games.CrossyDuelLobbyRequest
import com.yehsung.aingcheck.core.wire.games.CrossyDuelLobbyResponse
import com.yehsung.aingcheck.core.wire.games.CrossyDuelMatchRequest
import com.yehsung.aingcheck.core.wire.games.CrossyDuelProtocolRequest
import com.yehsung.aingcheck.core.wire.games.CrossyDuelRankingResponse
import com.yehsung.aingcheck.core.wire.games.CrossyDuelReportBody
import com.yehsung.aingcheck.core.wire.games.CrossyDuelReportRequest
import com.yehsung.aingcheck.core.wire.games.CrossyDuelRespondRequest
import com.yehsung.aingcheck.core.wire.games.CrossyDuelWire

/** 보고가 서버 `lock_timeout`(SQLSTATE 55P03)으로 끊겼다. **실패가 아니다** — 다음 걸음에 다시 보낸다(§3.1 CC-21). */
class CrossyDuelLockNotAvailable : Exception("crossy_duel_report lock_timeout") {
    override fun equals(other: Any?): Boolean = other is CrossyDuelLockNotAvailable
    override fun hashCode(): Int = SQL_STATE.hashCode()

    companion object {
        const val SQL_STATE = "55P03"
    }
}

/** [users] 가 false 면 가벼운 로비(팝오버 경로 — `me` 만, v1.1 CS-4). */
suspend fun SupabaseWorkService.crossyDuelLobby(accessToken: String, users: Boolean = true): CrossyDuelLobbyResponse =
    duelRPC(CrossyDuelWire.RPC.lobby, encode(CrossyDuelLobbyRequest.serializer(), CrossyDuelLobbyRequest(pUsers = users)), accessToken, CrossyDuelLobbyResponse.serializer())

suspend fun SupabaseWorkService.crossyDuelChallenge(accessToken: String, opponentID: String, stake: Long): CrossyDuelActionResponse =
    duelRPC(
        CrossyDuelWire.RPC.challenge, encode(CrossyDuelChallengeRequest.serializer(), CrossyDuelChallengeRequest(pOpponent = opponentID, pStake = stake)),
        accessToken, CrossyDuelActionResponse.serializer(), true,
    )

suspend fun SupabaseWorkService.crossyDuelCancel(accessToken: String, matchID: String): CrossyDuelActionResponse =
    duelRPC(CrossyDuelWire.RPC.cancel, encode(CrossyDuelMatchRequest.serializer(), CrossyDuelMatchRequest(pMatchId = matchID)), accessToken, CrossyDuelActionResponse.serializer(), true)

suspend fun SupabaseWorkService.crossyDuelRespond(accessToken: String, matchID: String, accept: Boolean): CrossyDuelActionResponse =
    duelRPC(
        CrossyDuelWire.RPC.respond, encode(CrossyDuelRespondRequest.serializer(), CrossyDuelRespondRequest(pMatchId = matchID, pAccept = accept)),
        accessToken, CrossyDuelActionResponse.serializer(), true,
    )

/**
 * 판 보고(첫 보고가 준비다). 서버가 `lock_timeout`(55P03)으로 끊었으면 [CrossyDuelLockNotAvailable] 을 던진다 — 스토어가 실패로 세지 않고
 * 다음 걸음에 다시 보낸다. 공용 duelRPC 는 SQLSTATE 를 잃으므로 이 한 RPC 만 몸통을 따로 둔다.
 */
suspend fun SupabaseWorkService.crossyDuelReport(accessToken: String, matchID: String, report: CrossyDuelReportBody): CrossyDuelActionResponse {
    val body = encode(CrossyDuelReportRequest.serializer(), CrossyDuelReportRequest.of(matchID, report))
    val r = rawRequest("/rest/v1/rpc/${CrossyDuelWire.RPC.report}", "POST", emptyList(), body, "application/json", accessToken, null, emptyMap())
    if (r.statusCode in 200..299) return decode(CrossyDuelActionResponse.serializer(), r.body)
    if (postgrestErrorCode(r.body) == CrossyDuelLockNotAvailable.SQL_STATE) throw CrossyDuelLockNotAvailable()
    throw serviceError(r.statusCode, r.body)
}

/** 상태(참가자 전용). 읽기처럼 보이지만 서버가 시간 판정을 돌려 판을 닫을 수 있다. */
suspend fun SupabaseWorkService.crossyDuelState(accessToken: String, matchID: String): CrossyDuelActionResponse =
    duelRPC(CrossyDuelWire.RPC.state, encode(CrossyDuelMatchRequest.serializer(), CrossyDuelMatchRequest(pMatchId = matchID)), accessToken, CrossyDuelActionResponse.serializer(), true)

suspend fun SupabaseWorkService.crossyDuelResign(accessToken: String, matchID: String): CrossyDuelActionResponse =
    duelRPC(CrossyDuelWire.RPC.resign, encode(CrossyDuelMatchRequest.serializer(), CrossyDuelMatchRequest(pMatchId = matchID)), accessToken, CrossyDuelActionResponse.serializer(), true)

suspend fun SupabaseWorkService.crossyDuelRanking(accessToken: String): CrossyDuelRankingResponse =
    duelRPC(CrossyDuelWire.RPC.ranking, encode(CrossyDuelProtocolRequest.serializer(), CrossyDuelProtocolRequest()), accessToken, CrossyDuelRankingResponse.serializer())
