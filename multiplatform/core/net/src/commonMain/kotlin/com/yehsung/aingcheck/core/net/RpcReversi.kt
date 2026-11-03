// 원본: Sources/CheckCore/ReversiWire.swift:487-559(`extension SupabaseWorkService` — 아잉 뒤집기 RPC 10개) @ 12624739
package com.yehsung.aingcheck.core.net

import com.yehsung.aingcheck.core.wire.games.ReversiActionResponse
import com.yehsung.aingcheck.core.wire.games.ReversiChallengeRequest
import com.yehsung.aingcheck.core.wire.games.ReversiLobbyResponse
import com.yehsung.aingcheck.core.wire.games.ReversiMatchRequest
import com.yehsung.aingcheck.core.wire.games.ReversiMoveRequest
import com.yehsung.aingcheck.core.wire.games.ReversiProtocolRequest
import com.yehsung.aingcheck.core.wire.games.ReversiRankingResponse
import com.yehsung.aingcheck.core.wire.games.ReversiRespondRequest
import com.yehsung.aingcheck.core.wire.games.ReversiStateRequest
import com.yehsung.aingcheck.core.wire.games.ReversiWatchRequest
import com.yehsung.aingcheck.core.wire.games.ReversiWire
import kotlinx.serialization.DeserializationStrategy

// 아잉 뒤집기 RPC 10개. 몸통은 공용 [SupabaseWorkService.duelRPC] 하나다(오목·체스·테트리스·큐브와 같은 꼴 — `p_protocol` 1 을 언제나).
// 교착(40P01) 한 번 재시도 여부는 [ReversiWire.RPC.retriesDeadlockOnce] 가 정한다(쓰기 전부 + 상태 조회 · 로비·순위·관전은 끔).
// 오목·체스 RpcGames.kt 와 파일을 나눈 까닭: 판 7 의 다른 갈래(집중·채팅)가 그 파일을 고칠 수 있어 합칠 때 겹치지 않게.

suspend fun SupabaseWorkService.reversiLobby(accessToken: String): ReversiLobbyResponse =
    reversiCall(ReversiWire.RPC.lobby, encode(ReversiProtocolRequest.serializer(), ReversiProtocolRequest()), accessToken, ReversiLobbyResponse.serializer())

suspend fun SupabaseWorkService.reversiChallenge(accessToken: String, opponentID: String, stake: Long): ReversiActionResponse =
    reversiCall(
        ReversiWire.RPC.challenge,
        encode(ReversiChallengeRequest.serializer(), ReversiChallengeRequest(pOpponent = opponentID, pStake = stake)),
        accessToken, ReversiActionResponse.serializer(),
    )

suspend fun SupabaseWorkService.reversiCancel(accessToken: String, matchID: String): ReversiActionResponse =
    reversiCall(ReversiWire.RPC.cancel, encode(ReversiMatchRequest.serializer(), ReversiMatchRequest(pMatchId = matchID)), accessToken, ReversiActionResponse.serializer())

suspend fun SupabaseWorkService.reversiRespond(accessToken: String, matchID: String, accept: Boolean): ReversiActionResponse =
    reversiCall(
        ReversiWire.RPC.respond,
        encode(ReversiRespondRequest.serializer(), ReversiRespondRequest(pMatchId = matchID, pAccept = accept)),
        accessToken, ReversiActionResponse.serializer(),
    )

/** 상태(참가자 전용). 읽기처럼 보이지만 서버가 시간 초과 자동 착수를 따라잡아 판을 바꾸거나 닫을 수 있다(그래서 교착 재시도를 켠다). */
suspend fun SupabaseWorkService.reversiState(accessToken: String, matchID: String, sinceSeq: Long = 0): ReversiActionResponse =
    reversiCall(
        ReversiWire.RPC.state,
        encode(ReversiStateRequest.serializer(), ReversiStateRequest(pMatchId = matchID, pSinceSeq = sinceSeq)),
        accessToken, ReversiActionResponse.serializer(),
    )

/** 착수. [expectedSeq] 는 화면이 본 `move_count`(패스 포함 기록 수) — 다르면 `stale`. [idx] 는 칸 0~63. */
suspend fun SupabaseWorkService.reversiMove(accessToken: String, matchID: String, expectedSeq: Long, idx: Long): ReversiActionResponse =
    reversiCall(
        ReversiWire.RPC.move,
        encode(ReversiMoveRequest.serializer(), ReversiMoveRequest(pMatchId = matchID, pExpectedSeq = expectedSeq, pIdx = idx)),
        accessToken, ReversiActionResponse.serializer(),
    )

suspend fun SupabaseWorkService.reversiResign(accessToken: String, matchID: String): ReversiActionResponse =
    reversiCall(ReversiWire.RPC.resign, encode(ReversiMatchRequest.serializer(), ReversiMatchRequest(pMatchId = matchID)), accessToken, ReversiActionResponse.serializer())

suspend fun SupabaseWorkService.reversiRanking(accessToken: String): ReversiRankingResponse =
    reversiCall(ReversiWire.RPC.ranking, encode(ReversiProtocolRequest.serializer(), ReversiProtocolRequest()), accessToken, ReversiRankingResponse.serializer())

/** 관전(읽기 전용 · 관전자 수 0). `reversi_watch_live` 가 아직 없는 서버로 한 번 접을 때 쓴다. */
suspend fun SupabaseWorkService.reversiWatch(accessToken: String, matchID: String, sinceSeq: Long = 0): ReversiActionResponse =
    reversiCall(
        ReversiWire.RPC.watch,
        encode(ReversiWatchRequest.serializer(), ReversiWatchRequest(pMatchId = matchID, pSinceSeq = sinceSeq)),
        accessToken, ReversiActionResponse.serializer(),
    )

/** 관전 + 생존 신호. **`reversi_state` 를 대신 부르지 마라** — 참가자 게이트에 걸려 관전자는 not_found 만 받는다. */
suspend fun SupabaseWorkService.reversiWatchLive(accessToken: String, matchID: String, sinceSeq: Long = 0): ReversiActionResponse =
    reversiCall(
        ReversiWire.RPC.watchLive,
        encode(ReversiWatchRequest.serializer(), ReversiWatchRequest(pMatchId = matchID, pSinceSeq = sinceSeq)),
        accessToken, ReversiActionResponse.serializer(),
    )

private suspend fun <T> SupabaseWorkService.reversiCall(rpc: ReversiWire.RPC, body: ByteArray, accessToken: String, response: DeserializationStrategy<T>): T =
    duelRPC(rpc.rawValue, body, accessToken, response, rpc.retriesDeadlockOnce)
