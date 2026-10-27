// 원본: Sources/CheckCore/SupabaseWorkService.swift:1601-1771(오목 RPC) · ChessWire.swift:373-501(체스 RPC) · TetrisWire.swift:347-412(테트리스 RPC) · DuelRPC.swift @ 1b8260d
package com.yehsung.aingcheck.core.net

import com.yehsung.aingcheck.core.wire.games.ChessActionResponse
import com.yehsung.aingcheck.core.wire.games.ChessChallengeRequest
import com.yehsung.aingcheck.core.wire.games.ChessLobbyResponse
import com.yehsung.aingcheck.core.wire.games.ChessMatchRequest
import com.yehsung.aingcheck.core.wire.games.ChessMoveRequest
import com.yehsung.aingcheck.core.wire.games.ChessProtocolRequest
import com.yehsung.aingcheck.core.wire.games.ChessRankingResponse
import com.yehsung.aingcheck.core.wire.games.ChessRespondRequest
import com.yehsung.aingcheck.core.wire.games.ChessSinceRequest
import com.yehsung.aingcheck.core.wire.games.ChessStateResponse
import com.yehsung.aingcheck.core.wire.games.ChessWatchResponse
import com.yehsung.aingcheck.core.wire.games.GomokuActionResponse
import com.yehsung.aingcheck.core.wire.games.GomokuChallengeRequest
import com.yehsung.aingcheck.core.wire.games.GomokuChatKind
import com.yehsung.aingcheck.core.wire.games.GomokuChatMuteRequest
import com.yehsung.aingcheck.core.wire.games.GomokuChatResponse
import com.yehsung.aingcheck.core.wire.games.GomokuChatSendRequest
import com.yehsung.aingcheck.core.wire.games.GomokuInboxRequest
import com.yehsung.aingcheck.core.wire.games.GomokuInboxResponse
import com.yehsung.aingcheck.core.wire.games.GomokuLeaveResponse
import com.yehsung.aingcheck.core.wire.games.GomokuLobbyRequest
import com.yehsung.aingcheck.core.wire.games.GomokuLobbyResponse
import com.yehsung.aingcheck.core.wire.games.GomokuMatchRequest
import com.yehsung.aingcheck.core.wire.games.GomokuMoveRequest
import com.yehsung.aingcheck.core.wire.games.GomokuRankingRequest
import com.yehsung.aingcheck.core.wire.games.GomokuRankingResponse
import com.yehsung.aingcheck.core.wire.games.GomokuRespondRequest
import com.yehsung.aingcheck.core.wire.games.GomokuStateRequest
import com.yehsung.aingcheck.core.wire.games.GomokuStateResponse
import com.yehsung.aingcheck.core.wire.games.GomokuWatchRequest
import com.yehsung.aingcheck.core.wire.games.GomokuWatchResponse
import com.yehsung.aingcheck.core.wire.games.TetrisActionResponse
import com.yehsung.aingcheck.core.wire.games.TetrisChallengeRequest
import com.yehsung.aingcheck.core.wire.games.TetrisLobbyResponse
import com.yehsung.aingcheck.core.wire.games.TetrisMatchRequest
import com.yehsung.aingcheck.core.wire.games.TetrisProtocolRequest
import com.yehsung.aingcheck.core.wire.games.TetrisRankingResponse
import com.yehsung.aingcheck.core.wire.games.TetrisReportRequest
import com.yehsung.aingcheck.core.wire.games.TetrisRespondRequest
import com.yehsung.aingcheck.core.wire.games.TetrisWatchResponse

// ======================================================================== 오목(p_protocol 2 를 언제나 — C§4 #10, 쓰기 RPC 는 40P01 한 번 재시도)

suspend fun SupabaseWorkService.gomokuLobby(accessToken: String): GomokuLobbyResponse =
    duelRPC("gomoku_lobby", encode(GomokuLobbyRequest.serializer(), GomokuLobbyRequest()), accessToken, GomokuLobbyResponse.serializer())

suspend fun SupabaseWorkService.gomokuChallenge(accessToken: String, opponentID: String, stake: Long): GomokuActionResponse =
    duelRPC("gomoku_challenge", encode(GomokuChallengeRequest.serializer(), GomokuChallengeRequest(pOpponent = opponentID, pStake = stake)), accessToken, GomokuActionResponse.serializer(), true)

suspend fun SupabaseWorkService.gomokuCancel(accessToken: String, matchID: String): GomokuActionResponse =
    duelRPC("gomoku_cancel", encode(GomokuMatchRequest.serializer(), GomokuMatchRequest(pMatchId = matchID)), accessToken, GomokuActionResponse.serializer(), true)

suspend fun SupabaseWorkService.gomokuRespond(accessToken: String, matchID: String, accept: Boolean): GomokuActionResponse =
    duelRPC("gomoku_respond", encode(GomokuRespondRequest.serializer(), GomokuRespondRequest(pMatchId = matchID, pAccept = accept)), accessToken, GomokuActionResponse.serializer(), true)

suspend fun SupabaseWorkService.gomokuMove(accessToken: String, matchID: String, expectedSeq: Long, x: Long, y: Long): GomokuActionResponse =
    duelRPC(
        "gomoku_move", encode(GomokuMoveRequest.serializer(), GomokuMoveRequest(pMatchId = matchID, pExpectedSeq = expectedSeq, pX = x, pY = y)),
        accessToken, GomokuActionResponse.serializer(), true,
    )

suspend fun SupabaseWorkService.gomokuResign(accessToken: String, matchID: String): GomokuActionResponse =
    duelRPC("gomoku_resign", encode(GomokuMatchRequest.serializer(), GomokuMatchRequest(pMatchId = matchID)), accessToken, GomokuActionResponse.serializer(), true)

/** 판 조회 — 시간 판정을 돌리지만 Swift 는 재시도하지 않는다(오목만 — 체스·테트리스 state 는 재시도). */
suspend fun SupabaseWorkService.gomokuState(accessToken: String, matchID: String, sinceSeq: Long, sinceChatSeq: Long): GomokuStateResponse =
    duelRPC(
        "gomoku_state", encode(GomokuStateRequest.serializer(), GomokuStateRequest(pMatchId = matchID, pSinceSeq = sinceSeq, pSinceChatSeq = sinceChatSeq)),
        accessToken, GomokuStateResponse.serializer(),
    )

suspend fun SupabaseWorkService.gomokuInbox(accessToken: String): GomokuInboxResponse =
    duelRPC("gomoku_inbox", encode(GomokuInboxRequest.serializer(), GomokuInboxRequest()), accessToken, GomokuInboxResponse.serializer())

suspend fun SupabaseWorkService.gomokuChatSend(accessToken: String, matchID: String, kind: GomokuChatKind, body: String): GomokuChatResponse =
    duelRPC(
        "gomoku_chat_send", encode(GomokuChatSendRequest.serializer(), GomokuChatSendRequest(pMatchId = matchID, pKind = kind.rawValue, pBody = body)),
        accessToken, GomokuChatResponse.serializer(), true,
    )

suspend fun SupabaseWorkService.gomokuLeave(accessToken: String, matchID: String): GomokuLeaveResponse =
    duelRPC("gomoku_leave", encode(GomokuMatchRequest.serializer(), GomokuMatchRequest(pMatchId = matchID)), accessToken, GomokuLeaveResponse.serializer(), true)

suspend fun SupabaseWorkService.gomokuChatMute(accessToken: String, matchID: String, muted: Boolean): GomokuChatResponse =
    duelRPC("gomoku_chat_mute", encode(GomokuChatMuteRequest.serializer(), GomokuChatMuteRequest(pMatchId = matchID, pMuted = muted)), accessToken, GomokuChatResponse.serializer(), true)

suspend fun SupabaseWorkService.gomokuRanking(accessToken: String): GomokuRankingResponse =
    duelRPC("gomoku_ranking", encode(GomokuRankingRequest.serializer(), GomokuRankingRequest()), accessToken, GomokuRankingResponse.serializer())

suspend fun SupabaseWorkService.gomokuWatch(accessToken: String, matchID: String, sinceSeq: Long): GomokuWatchResponse =
    duelRPC("gomoku_watch", encode(GomokuWatchRequest.serializer(), GomokuWatchRequest(pMatchId = matchID, pSinceSeq = sinceSeq)), accessToken, GomokuWatchResponse.serializer())

/**
 * 관전 + 관전자 수(v0.3.65 `gomoku_watch_live`). 서버에 없으면(databaseSchemaMissing) 호출부(W2-d)가 깃발을 세우고 `gomoku_watch` 로
 * 접는다 — 관전 입구는 잠그지 않는다(깃발 겸업 금지).
 */
suspend fun SupabaseWorkService.gomokuWatchLive(accessToken: String, matchID: String, sinceSeq: Long): GomokuWatchResponse =
    duelRPC("gomoku_watch_live", encode(GomokuWatchRequest.serializer(), GomokuWatchRequest(pMatchId = matchID, pSinceSeq = sinceSeq)), accessToken, GomokuWatchResponse.serializer())

// ======================================================================== 체스(p_protocol 1)

suspend fun SupabaseWorkService.chessLobby(accessToken: String): ChessLobbyResponse =
    duelRPC("chess_lobby", encode(ChessProtocolRequest.serializer(), ChessProtocolRequest()), accessToken, ChessLobbyResponse.serializer())

suspend fun SupabaseWorkService.chessChallenge(accessToken: String, opponentID: String, stake: Long): ChessActionResponse =
    duelRPC("chess_challenge", encode(ChessChallengeRequest.serializer(), ChessChallengeRequest(pOpponent = opponentID, pStake = stake)), accessToken, ChessActionResponse.serializer(), true)

suspend fun SupabaseWorkService.chessCancel(accessToken: String, matchID: String): ChessActionResponse =
    duelRPC("chess_cancel", encode(ChessMatchRequest.serializer(), ChessMatchRequest(pMatchId = matchID)), accessToken, ChessActionResponse.serializer(), true)

suspend fun SupabaseWorkService.chessRespond(accessToken: String, matchID: String, accept: Boolean): ChessActionResponse =
    duelRPC("chess_respond", encode(ChessRespondRequest.serializer(), ChessRespondRequest(pMatchId = matchID, pAccept = accept)), accessToken, ChessActionResponse.serializer(), true)

suspend fun SupabaseWorkService.chessMove(accessToken: String, matchID: String, expectedPly: Long, uci: String): ChessActionResponse =
    duelRPC("chess_move", encode(ChessMoveRequest.serializer(), ChessMoveRequest(pMatchId = matchID, pExpectedPly = expectedPly, pUci = uci)), accessToken, ChessActionResponse.serializer(), true)

suspend fun SupabaseWorkService.chessResign(accessToken: String, matchID: String): ChessActionResponse =
    duelRPC("chess_resign", encode(ChessMatchRequest.serializer(), ChessMatchRequest(pMatchId = matchID)), accessToken, ChessActionResponse.serializer(), true)

suspend fun SupabaseWorkService.chessOfferDraw(accessToken: String, matchID: String): ChessActionResponse =
    duelRPC("chess_offer_draw", encode(ChessMatchRequest.serializer(), ChessMatchRequest(pMatchId = matchID)), accessToken, ChessActionResponse.serializer(), true)

suspend fun SupabaseWorkService.chessRespondDraw(accessToken: String, matchID: String, accept: Boolean): ChessActionResponse =
    duelRPC("chess_respond_draw", encode(ChessRespondRequest.serializer(), ChessRespondRequest(pMatchId = matchID, pAccept = accept)), accessToken, ChessActionResponse.serializer(), true)

suspend fun SupabaseWorkService.chessState(accessToken: String, matchID: String, sinceSeq: Long): ChessStateResponse =
    duelRPC("chess_state", encode(ChessSinceRequest.serializer(), ChessSinceRequest(pMatchId = matchID, pSinceSeq = sinceSeq)), accessToken, ChessStateResponse.serializer(), true)

suspend fun SupabaseWorkService.chessRanking(accessToken: String): ChessRankingResponse =
    duelRPC("chess_ranking", encode(ChessProtocolRequest.serializer(), ChessProtocolRequest()), accessToken, ChessRankingResponse.serializer())

suspend fun SupabaseWorkService.chessWatch(accessToken: String, matchID: String, sinceSeq: Long): ChessWatchResponse =
    duelRPC("chess_watch", encode(ChessSinceRequest.serializer(), ChessSinceRequest(pMatchId = matchID, pSinceSeq = sinceSeq)), accessToken, ChessWatchResponse.serializer())

/** 관전 + 관전자 수(v0.3.65). 없으면 W2-d 가 `chess_watch` 로 접는다. */
suspend fun SupabaseWorkService.chessWatchLive(accessToken: String, matchID: String, sinceSeq: Long): ChessWatchResponse =
    duelRPC("chess_watch_live", encode(ChessSinceRequest.serializer(), ChessSinceRequest(pMatchId = matchID, pSinceSeq = sinceSeq)), accessToken, ChessWatchResponse.serializer())

// ======================================================================== 테트리스(p_protocol 1 — DuelRPC.swift 공용 몸통)

suspend fun SupabaseWorkService.tetrisLobby(accessToken: String): TetrisLobbyResponse =
    duelRPC("tetris_lobby", encode(TetrisProtocolRequest.serializer(), TetrisProtocolRequest()), accessToken, TetrisLobbyResponse.serializer())

suspend fun SupabaseWorkService.tetrisChallenge(accessToken: String, opponentID: String, stake: Long): TetrisActionResponse =
    duelRPC("tetris_challenge", encode(TetrisChallengeRequest.serializer(), TetrisChallengeRequest(pOpponent = opponentID, pStake = stake)), accessToken, TetrisActionResponse.serializer(), true)

suspend fun SupabaseWorkService.tetrisCancel(accessToken: String, matchID: String): TetrisActionResponse =
    duelRPC("tetris_cancel", encode(TetrisMatchRequest.serializer(), TetrisMatchRequest(pMatchId = matchID)), accessToken, TetrisActionResponse.serializer(), true)

suspend fun SupabaseWorkService.tetrisRespond(accessToken: String, matchID: String, accept: Boolean): TetrisActionResponse =
    duelRPC("tetris_respond", encode(TetrisRespondRequest.serializer(), TetrisRespondRequest(pMatchId = matchID, pAccept = accept)), accessToken, TetrisActionResponse.serializer(), true)

/** 보고 — 칸은 W1-a `TetrisDuelReport` 에서 호출부가 옮겨 담는다. */
suspend fun SupabaseWorkService.tetrisReport(accessToken: String, report: TetrisReportRequest): TetrisActionResponse =
    duelRPC("tetris_report", encode(TetrisReportRequest.serializer(), report), accessToken, TetrisActionResponse.serializer(), true)

suspend fun SupabaseWorkService.tetrisState(accessToken: String, matchID: String): TetrisActionResponse =
    duelRPC("tetris_state", encode(TetrisMatchRequest.serializer(), TetrisMatchRequest(pMatchId = matchID)), accessToken, TetrisActionResponse.serializer(), true)

suspend fun SupabaseWorkService.tetrisResign(accessToken: String, matchID: String): TetrisActionResponse =
    duelRPC("tetris_resign", encode(TetrisMatchRequest.serializer(), TetrisMatchRequest(pMatchId = matchID)), accessToken, TetrisActionResponse.serializer(), true)

suspend fun SupabaseWorkService.tetrisRanking(accessToken: String): TetrisRankingResponse =
    duelRPC("tetris_ranking", encode(TetrisProtocolRequest.serializer(), TetrisProtocolRequest()), accessToken, TetrisRankingResponse.serializer())

/**
 * 테트리스 관전(v0.3.64 새 봉투 — me/opponent·seed 없음, a/b 는 uuid 오름차순 자리). `tetris_state` 를 관전에 쓰지 않는다(W2-e).
 * INV-TetrisWire-973492d2 이식: `result`/`reason` 은 서버가 판을 닫았을 때만 찬다 — 관전 쪽이 시간으로 끝을 지어내지 않는다.
 */
suspend fun SupabaseWorkService.tetrisWatchLive(accessToken: String, matchID: String): TetrisWatchResponse =
    duelRPC("tetris_watch_live", encode(TetrisMatchRequest.serializer(), TetrisMatchRequest(pMatchId = matchID)), accessToken, TetrisWatchResponse.serializer())

suspend fun SupabaseWorkService.tetrisWatch(accessToken: String, matchID: String): TetrisWatchResponse =
    duelRPC("tetris_watch", encode(TetrisMatchRequest.serializer(), TetrisMatchRequest(pMatchId = matchID)), accessToken, TetrisWatchResponse.serializer())
