// 원본: Tests/checkTests/V03xxReversiFixtureContractTests.swift @ 12624739 (① 손 픽스처 C1 · ② 서버 원문 C2 — 마이그레이션을 읽는 두 시험은 손으로 옮긴 인자 표·매니페스트 키로)
package com.yehsung.aingcheck.core.wire.games

import com.yehsung.aingcheck.core.wire.json.SwiftJson
import com.yehsung.aingcheck.testkit.fixtures.RepoFiles
import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerializationStrategy
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull
import java.io.File
import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * 아잉 뒤집기(reversi) — 와이어 디코딩 계약. 두 겹이다(맥 시험과 같은 나눔):
 *  ① 설계서 §3.5·§3.6 모양의 **손 픽스처**를 앱 디코더(SwiftJson — Swift convertFromSnakeCase 와 같은 판정)로 읽어 값까지 대조한다
 *     (원문에 없는 값 — 센터 글자·패스 줄의 빠진 키·모르는 어휘 — 을 일부러 싣는다).
 *  ② 서버 갈래 픽스처 **원문 51장**(`Tests/checkTests/Fixtures/reversi-rpc/` — 실제 RPC 응답, 저장소 원본을 그대로 읽는다)을
 *     매니페스트 · 봉투 키 = 매니페스트 `keys`(= 마이그레이션 사후 단언 `v_*_keys`) · 관전 칸 · 자동 착수 시계로 잰다.
 * 옵셔널 칸은 키 이름이 한 글자만 어긋나도 **조용히 null** 이 되어 초록이 된다 — 그래서 "디코드된다" 가 아니라 **값이 원문과 같다** 를 잰다.
 * 시험은 supabase/ 를 읽지 않는다(공개 저장소·CI·워크트리에 없다 — RepoFiles 규칙). 요청 인자 이름은 마이그레이션 20261108200000 에서 손으로 옮겼다.
 */
class ReversiWireContractTest {
    private val me = "a1000000-0000-4000-8000-000000000001"
    private val peer = "b2000000-0000-4000-8000-000000000002"
    private val matchID = "c3000000-0000-4000-8000-000000000003"

    private fun <T> decode(deserializer: kotlinx.serialization.DeserializationStrategy<T>, json: String): T = SwiftJson.decode(deserializer, json)

    @OptIn(ExperimentalSerializationApi::class)
    private fun KSerializer<*>.fieldNames(): Set<String> = (0 until descriptor.elementsCount).map { descriptor.getElementName(it) }.toSet()

    private fun <T> keys(serializer: SerializationStrategy<T>, body: T): Set<String> = (SwiftJson.encodeToElement(serializer, body) as JsonObject).keys

    // ---------- ① 손 픽스처 ----------

    private val lobbyJSON = """
        {"status":"ok","server_now_ms":1793659950010,"stakes":[3,5,10],"turn_seconds":30,"turn_grace_seconds":2,
         "invite_ttl_seconds":60,"auto_abandon_streak":3,
         "me":{"ruby_balance":95,"wins":4,"losses":2,"draws":1,"active_match_id":null,
               "incoming":[{"match_id":"$matchID","from":{"id":"$peer","display_name":"상대01","avatar_url":"https://x/a.png","character":"aing"},
                            "stake":5,"expires_at_ms":1793660010009}],
               "outgoing":null},
         "users":[{"id":"$peer","display_name":"상대01","avatar_url":null,"character":"aing","center":"seoul",
                   "is_working":true,"in_match":false,"capable":true,"focus_mode":false}],
         "matches":[{"id":"d4000000-0000-4000-8000-000000000004","a":{"id":"$me","display_name":"나","avatar_url":null,"character":null},
                     "b":{"id":"$peer","display_name":"상대01","avatar_url":null,"character":null},
                     "stake":10,"watchers":2,"started_at_ms":1793659940000}]}
    """.trimIndent()

    private val activeStateJSON = """
        {"status":"ok","state":{
         "match":{"id":"$matchID","status":"active","stake":5,"challenger":"$me","opponent":"$peer",
                  "black":"$peer","white":"$me","move_count":1,"turn":"white",
                  "turn_started_ms":1793659950000,"deadline_ms":1793659980000,"invite_expires_ms":1793660010009,
                  "started_ms":1793659918000,"finished_ms":null,"result":null,"end_reason":null,"winner":null,
                  "board":"...................b.......bb......bw...........................",
                  "discs":{"black":4,"white":1,"empty":59},"score":null},
         "moves":[{"seq":1,"color":"black","kind":"stone","idx":19,"flipped":[27],"auto":true,"at_ms":1793659950000}],
         "black_user":{"user_id":"$peer","display_name":"상대01","avatar_url":null,"character":null,"center":"busan"},
         "white_user":{"user_id":"$me","display_name":"나","avatar_url":null,"character":"aing","center":null},
         "opponent":{"user_id":"$peer","display_name":"상대01","avatar_url":null,"character":null,"center":"busan"},
         "my_color":"white","legal_moves":[18,20,34],
         "black_auto_streak":1,"white_auto_streak":0,"my_auto_streak":0,"opponent_auto_streak":1,
         "auto_abandon_streak":3,"turn_seconds":30,"grace_ms":2000,"ruby_balance":95,"watchers":4,"server_now_ms":1793659951000}}
    """.trimIndent()

    private val passMovesJSON = """
        [{"seq":7,"color":"white","kind":"pass","idx":null,"flipped":[],"auto":false,"at_ms":1793659960000},
         {"seq":8,"color":"black","kind":"pass","idx":null,"at_ms":1793659960000},
         {"seq":9,"color":"white","kind":"stone","idx":63,"flipped":[54,62],"auto":false,"at_ms":1793659961000}]
    """.trimIndent()

    private val finishedStateJSON = """
        {"status":"ok","state":{
         "match":{"id":"$matchID","status":"finished","stake":5,"challenger":"$me","opponent":"$peer",
                  "black":"$me","white":"$peer","move_count":60,"turn":null,
                  "turn_started_ms":1793659990000,"deadline_ms":null,"invite_expires_ms":1793660010009,
                  "started_ms":1793659940000,"finished_ms":1793659999000,"result":"black_win","end_reason":"board_full",
                  "winner":"$me",
                  "board":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbwwwwwwwwwwwwwwwwwwwwwww",
                  "discs":{"black":41,"white":23,"empty":0},"score":{"black":41,"white":23}},
         "moves":[],"black_user":null,"white_user":null,"opponent":null,"my_color":"black","legal_moves":[],
         "black_auto_streak":0,"white_auto_streak":0,"my_auto_streak":0,"opponent_auto_streak":0,
         "auto_abandon_streak":3,"turn_seconds":30,"grace_ms":2000,"ruby_balance":105,"watchers":0,"server_now_ms":1793659999100}}
    """.trimIndent()

    private val watchJSON = """
        {"status":"ok","state":{
         "match":{"id":"$matchID","status":"active","stake":3,"challenger":"$me","opponent":"$peer",
                  "black":"$peer","white":"$me","move_count":0,"turn":"black",
                  "turn_started_ms":1793659950099,"deadline_ms":1793659980099,"invite_expires_ms":1793660010098,
                  "started_ms":1793659950099,"finished_ms":null,"result":null,"end_reason":null,"winner":null,
                  "board":"...........................wb......bw...........................",
                  "discs":{"black":2,"white":2,"empty":60},"score":null},
         "moves":[],"black_user":{"user_id":"$peer","display_name":"상대01","avatar_url":null,"character":null,"center":null},
         "white_user":{"user_id":"$me","display_name":"나","avatar_url":null,"character":null,"center":null},
         "opponent":null,"my_color":null,"legal_moves":[],
         "black_auto_streak":0,"white_auto_streak":0,"my_auto_streak":null,"opponent_auto_streak":null,
         "auto_abandon_streak":3,"turn_seconds":30,"grace_ms":2000,"ruby_balance":null,"watchers":7,"server_now_ms":1793659950100}}
    """.trimIndent()

    // 없으면: 로비 키 이름이 어긋나도(예: `expires_at_ms`) 옵셔널이 null 로 접혀 받은 신청·만료·관전자 수가 화면에서 조용히 사라진 채 초록이다.
    @Test
    fun lobbyHandFixtureReadsEveryValue() {
        val lobby = decode(ReversiLobbyResponse.serializer(), lobbyJSON)
        assertEquals(ReversiRPCStatus.ok, lobby.status)
        assertEquals(1_793_659_950_010.0, lobby.serverNowMs)
        assertEquals(listOf(3L, 5L, 10L), lobby.stakes)
        assertEquals(30L, lobby.turnSeconds)
        assertEquals(2L, lobby.turnGraceSeconds)
        assertEquals(60L, lobby.inviteTtlSeconds)
        assertEquals(3L, lobby.autoAbandonStreak)
        val mine = assertNotNull(lobby.me)
        assertEquals(95L, mine.rubyBalance)
        assertTrue(mine.wins == 4L && mine.losses == 2L && mine.draws == 1L)
        assertNull(mine.activeMatchId)
        assertNull(mine.outgoing)
        assertEquals(1, mine.incoming?.size)
        val invite = assertNotNull(mine.incoming?.first())
        assertEquals(matchID, invite.matchId)
        assertEquals(peer, invite.from?.id)
        assertEquals("상대01", invite.from?.displayName)
        assertEquals("https://x/a.png", invite.from?.avatarUrl)
        assertEquals("aing", invite.from?.character)
        assertNull(invite.to)
        assertEquals(5L, invite.stake)
        assertEquals(1_793_660_010_009.0, invite.expiresAtMs)
        val user = assertNotNull(lobby.users?.first())
        assertEquals(peer, user.id)
        assertEquals("seoul", user.center)
        assertEquals(true, user.isWorking)
        assertEquals(false, user.inMatch)
        assertEquals(true, user.capable)
        assertEquals(false, user.focusMode)
        val live = assertNotNull(lobby.matches?.first())
        assertEquals(me, live.a?.id)
        assertEquals("상대01", live.b?.displayName)
        assertEquals(10L, live.stake)
        assertEquals(2L, live.watchers)
        assertEquals(1_793_659_940_000.0, live.startedAtMs)
    }

    // 없으면: state 의 판·시계·합법 수·연속 자동 착수 칸 하나가 잘못 읽혀도(null·0) 스토어가 "판 없음/내 차례 아님" 으로 그려 초록이다.
    @Test
    fun activeStateHandFixtureReadsEveryValue() {
        val response = decode(ReversiActionResponse.serializer(), activeStateJSON)
        assertEquals(ReversiRPCStatus.ok, response.status)
        val state = assertNotNull(response.state)
        val match = assertNotNull(state.match)
        assertEquals(matchID, match.id)
        assertEquals(ReversiMatchStatus.active, match.matchStatus)
        assertEquals(5L, match.stake)
        assertTrue(match.challenger == me && match.opponent == peer)
        assertTrue(match.black == peer && match.white == me)
        assertEquals(1, match.moveCount)
        assertEquals(ReversiColor.white, match.turn)
        assertEquals(1_793_659_950_000.0, match.turnStartedMs)
        assertEquals(1_793_659_980_000.0, match.deadlineMs)
        assertEquals(1_793_660_010_009.0, match.inviteExpiresMs)
        assertEquals(1_793_659_918_000.0, match.startedMs)
        assertTrue(match.finishedMs == null && match.result == null && match.endReason == null && match.winner == null)
        assertEquals("...................b.......bb......bw...........................", match.board?.string)
        assertEquals(ReversiCounts(4, 1, 59), match.discs)
        assertNull(match.score)
        assertEquals(listOf(ReversiPly(1, ReversiColor.black, ReversiPly.Kind.stone, 19, listOf(27), true)), state.moves)
        assertEquals(peer, state.blackUser?.userId)
        assertEquals("busan", state.blackUser?.center)
        assertEquals(me, state.whiteUser?.userId)
        assertEquals("aing", state.whiteUser?.character)
        assertEquals(peer, state.opponent?.userId)
        assertEquals("상대01", state.opponent?.displayName)
        assertEquals(ReversiColor.white, state.myColor)
        assertEquals(listOf(18, 20, 34), state.legalMoves)
        assertTrue(state.blackAutoStreak == 1L && state.whiteAutoStreak == 0L)
        assertTrue(state.myAutoStreak == 0L && state.opponentAutoStreak == 1L)
        assertEquals(3L, state.autoAbandonStreak)
        assertEquals(30L, state.turnSeconds)
        assertEquals(2000L, state.graceMs)
        assertEquals(95L, state.rubyBalance)
        assertEquals(4L, state.watchers)
        assertEquals(1_793_659_951_000.0, state.serverNowMs)
    }

    // 없으면: 패스 줄(idx null)이나 `flipped`·`auto` 키가 빠진 줄 하나가 state 디코드를 통째로 깨 판이 안 읽힌다.
    @Test
    fun passRowsAndMissingKeysDecode() {
        val moves = decode(ListSerializer(ReversiPly.serializer()), passMovesJSON)
        assertEquals(
            listOf(
                ReversiPly(7, ReversiColor.white, ReversiPly.Kind.pass, null, emptyList(), false),
                ReversiPly(8, ReversiColor.black, ReversiPly.Kind.pass, null, emptyList(), false),
                ReversiPly(9, ReversiColor.white, ReversiPly.Kind.stone, 63, listOf(54, 62), false),
            ),
            moves,
        )
        // 필수 칸(seq · color · kind)이 빠지거나 모르는 글자면 던진다(Swift 와 같은 자리) — 기준선.
        assertTrue(runCatching { decode(ReversiPly.serializer(), """{"color":"white","kind":"pass"}""") }.isFailure, "seq 없음")
        assertTrue(runCatching { decode(ReversiPly.serializer(), """{"seq":1,"color":"white","kind":"skip"}""") }.isFailure, "모르는 kind")
    }

    // 없으면: 자연 종료의 결과·끝 사유·WOF 점수가 null 로 읽혀 결과 카드가 "끝났는데 무승부도 승패도 아닌" 판을 그린 채 초록이다.
    @Test
    fun finishedStateCarriesResultAndScore() {
        val response = decode(ReversiActionResponse.serializer(), finishedStateJSON)
        val match = assertNotNull(response.state?.match)
        assertEquals(ReversiMatchStatus.finished, match.matchStatus)
        assertNull(match.turn)
        assertNull(match.deadlineMs)
        assertEquals(ReversiResult.blackWin, match.result)
        assertEquals(ReversiEndReason.boardFull, match.endReason)
        assertEquals(me, match.winner)
        assertEquals(1_793_659_999_000.0, match.finishedMs)
        assertEquals(ReversiScoreRow(41, 23), match.score)
        assertEquals(ReversiCounts(41, 23, 0), match.discs)
        assertEquals(emptyList(), response.state?.moves)
        assertNull(response.state?.blackUser)
        assertEquals(emptyList(), response.state?.legalMoves)
        assertEquals(105L, response.state?.rubyBalance)
    }

    // 없으면: 관전 모양(참가자 칸 null)에서 디코드가 깨지거나, 참가자 전용 칸이 0·빈 값으로 지어져 관전자에게 "내 차례" 가 보인다.
    @Test
    fun watchStateReadsWithEmptyParticipantFields() {
        val state = assertNotNull(decode(ReversiActionResponse.serializer(), watchJSON).state)
        assertNull(state.myColor)
        assertNull(state.opponent)
        assertTrue(state.myAutoStreak == null && state.opponentAutoStreak == null)
        assertNull(state.rubyBalance)
        assertEquals(emptyList(), state.legalMoves)
        assertEquals(7L, state.watchers)
        assertEquals(peer, state.blackUser?.userId)
        assertEquals(ReversiBoard.start, state.match?.board)
    }

    // 없으면: 서버가 어휘를 넓히는 날(새 status·새 끝 사유·새 불법 이유) 디코드가 던져 대결 화면이 통째로 죽는다.
    // 기준선: 아는 값은 제 이름으로 읽힌다(`unknown` 으로 다 접는 변이도 빨갛다).
    @Test
    fun unknownVocabularyFoldsAndKnownStaysPut() {
        val unknown = decode(ReversiActionResponse.serializer(), """{"status":"one_writer","reason":"diagonal_only"}""")
        assertEquals(ReversiRPCStatus.unknown, unknown.status)
        assertEquals("diagonal_only", unknown.reason)
        assertNull(unknown.illegalReason)
        val illegal = decode(ReversiActionResponse.serializer(), """{"status":"illegal","reason":"no_flip"}""")
        assertEquals(ReversiRPCStatus.illegal, illegal.status)
        assertEquals(ReversiIllegalReason.noFlip, illegal.illegalReason)
        val auto = decode(ReversiActionResponse.serializer(), """{"status":"auto_placed","auto_placed_count":2}""")
        assertEquals(ReversiRPCStatus.autoPlaced, auto.status)
        assertEquals(2L, auto.autoPlacedCount)
        assertEquals(ReversiRPCStatus.stale, decode(ReversiActionResponse.serializer(), """{"status":"stale"}""").status)
        assertEquals(ReversiRPCStatus.notYourTurn, decode(ReversiActionResponse.serializer(), """{"status":"not_your_turn"}""").status)
        // §3.4 어휘 전체가 제 이름으로 읽힌다(서버 원문 그대로 — target_focused · target_outdated · busy · target_busy · insufficient · blackout …).
        val vocabulary = listOf(
            "ok", "unauthorized", "unsupported_client", "invalid", "blackout", "target_focused", "target_outdated",
            "busy", "target_busy", "already_pending", "insufficient", "not_found", "not_pending", "expired",
            "not_active", "not_your_turn", "stale", "illegal", "auto_placed",
        )
        for (word in vocabulary) {
            val decoded = decode(ReversiActionResponse.serializer(), """{"status":"$word"}""").status
            assertNotEquals(ReversiRPCStatus.unknown, decoded, "$word 가 unknown 으로 접혔다")
            assertEquals(word, decoded.rawValue)
        }
        assertEquals(vocabulary + "unknown", ReversiRPCStatus.entries.map { it.rawValue }, "어휘 집합이 맥 ReversiRPCStatus 와 같다(순서까지)")
        val row = decode(ReversiMatchRow.serializer(), """{"status":"paused","end_reason":"timeout_new"}""")
        assertEquals(ReversiMatchStatus.unknown, row.matchStatus)
        assertEquals(ReversiEndReason.unknown, row.endReason)
        // status 는 필수다(Swift `let status`) — 없으면 던진다.
        assertTrue(runCatching { decode(ReversiActionResponse.serializer(), """{"state":null}""") }.isFailure)
    }

    // 없으면: 쓰기 응답의 부가 칸(신청 id·만료·잔액·부족분·수락 여부)이 null 로 읽혀 신청 카드·잔액 칩·부족 문구가 틀린 채 초록이다.
    @Test
    fun writeResponseExtrasDecode() {
        val challenge = decode(
            ReversiActionResponse.serializer(),
            """{"status":"ok","match_id":"$matchID","ruby_balance":100,"server_now_ms":1793659950009,"invite_expires_ms":1793660010009}""",
        )
        assertEquals(matchID, challenge.matchId)
        assertEquals(1_793_660_010_009.0, challenge.inviteExpiresMs)
        assertEquals(100L, challenge.rubyBalance)
        assertEquals(1_793_659_950_009.0, challenge.serverNowMs)
        val short = decode(ReversiActionResponse.serializer(), """{"status":"insufficient","side":"challenger","need":3,"have":null}""")
        assertEquals(ReversiRPCStatus.insufficient, short.status)
        assertEquals("challenger", short.side)
        assertTrue(short.need == 3L && short.have == null)
        assertEquals(false, decode(ReversiActionResponse.serializer(), """{"status":"ok","accepted":false}""").accepted)
        assertEquals(listOf(3L, 5L, 10L), decode(ReversiActionResponse.serializer(), """{"status":"invalid","stakes":[3,5,10]}""").stakes)
    }

    // 없으면: 요청 본문 키가 서버 인자 이름과 한 글자만 달라도(PostgREST 는 본문 키 집합으로 함수를 고른다 → PGRST202) 스텁 시험은 전부 초록이다.
    // 기대 표는 마이그레이션 20261108200000_reversi.sql 의 `create or replace function public.reversi_*(…)` 인자 이름을 손으로 옮긴 것(첫 인자는 늘 p_protocol).
    @Test
    fun requestBodyKeysAreServerArgumentNames() {
        val serverArguments = mapOf(
            ReversiWire.RPC.lobby to listOf("p_protocol"),
            ReversiWire.RPC.ranking to listOf("p_protocol"),
            ReversiWire.RPC.challenge to listOf("p_protocol", "p_opponent", "p_stake"),
            ReversiWire.RPC.cancel to listOf("p_protocol", "p_match_id"),
            ReversiWire.RPC.resign to listOf("p_protocol", "p_match_id"),
            ReversiWire.RPC.respond to listOf("p_protocol", "p_match_id", "p_accept"),
            ReversiWire.RPC.state to listOf("p_protocol", "p_match_id", "p_since_seq"),
            ReversiWire.RPC.move to listOf("p_protocol", "p_match_id", "p_expected_seq", "p_idx"),
            ReversiWire.RPC.watch to listOf("p_protocol", "p_match_id", "p_since_seq"),
            ReversiWire.RPC.watchLive to listOf("p_protocol", "p_match_id", "p_since_seq"),
        )
        val bodies = mapOf(
            ReversiWire.RPC.lobby to keys(ReversiProtocolRequest.serializer(), ReversiProtocolRequest()),
            ReversiWire.RPC.ranking to keys(ReversiProtocolRequest.serializer(), ReversiProtocolRequest()),
            ReversiWire.RPC.challenge to keys(ReversiChallengeRequest.serializer(), ReversiChallengeRequest(pOpponent = peer, pStake = 3)),
            ReversiWire.RPC.cancel to keys(ReversiMatchRequest.serializer(), ReversiMatchRequest(pMatchId = matchID)),
            ReversiWire.RPC.resign to keys(ReversiMatchRequest.serializer(), ReversiMatchRequest(pMatchId = matchID)),
            ReversiWire.RPC.respond to keys(ReversiRespondRequest.serializer(), ReversiRespondRequest(pMatchId = matchID, pAccept = true)),
            ReversiWire.RPC.state to keys(ReversiStateRequest.serializer(), ReversiStateRequest(pMatchId = matchID, pSinceSeq = 0)),
            ReversiWire.RPC.move to keys(ReversiMoveRequest.serializer(), ReversiMoveRequest(pMatchId = matchID, pExpectedSeq = 0, pIdx = 19)),
            ReversiWire.RPC.watch to keys(ReversiWatchRequest.serializer(), ReversiWatchRequest(pMatchId = matchID, pSinceSeq = 0)),
            ReversiWire.RPC.watchLive to keys(ReversiWatchRequest.serializer(), ReversiWatchRequest(pMatchId = matchID, pSinceSeq = 0)),
        )
        assertEquals(ReversiWire.RPC.entries.toSet(), bodies.keys)
        for ((rpc, body) in bodies) assertEquals(serverArguments[rpc]!!.toSet(), body, "${rpc.rawValue}: 서버 인자 ${serverArguments[rpc]} · 앱 본문 ${body.sorted()}")
        val move = SwiftJson.encodeToElement(ReversiMoveRequest.serializer(), ReversiMoveRequest(pMatchId = matchID, pExpectedSeq = 3, pIdx = 19)) as JsonObject
        assertEquals(1L, move["p_protocol"]?.jsonPrimitive?.longOrNull)
        assertEquals(1L, ReversiWire.protocolVersion)
        assertEquals(3L, move["p_expected_seq"]?.jsonPrimitive?.longOrNull)
        assertEquals(19L, move["p_idx"]?.jsonPrimitive?.longOrNull)
        assertEquals(matchID, move["p_match_id"]?.jsonPrimitive?.content)
    }

    // 없으면: RPC 이름 하나가 빠지거나 오타여도 초록이고, 읽기 전용 RPC 에 교착 재시도가 켜지거나 상태 조회에서 꺼지는 것도 안 보인다.
    @Test
    fun tenRpcNamesAndDeadlockRetrySet() {
        assertEquals(
            listOf(
                "reversi_lobby", "reversi_challenge", "reversi_cancel", "reversi_respond", "reversi_state",
                "reversi_move", "reversi_resign", "reversi_ranking", "reversi_watch", "reversi_watch_live",
            ),
            ReversiWire.RPC.all,
        )
        assertEquals(
            setOf("reversi_challenge", "reversi_cancel", "reversi_respond", "reversi_state", "reversi_move", "reversi_resign"),
            ReversiWire.RPC.entries.filter { it.retriesDeadlockOnce }.map { it.rawValue }.toSet(),
        )
        // 실시간 초인종 이벤트 이름 = 서버 reversi__ring 의 realtime.send(…, 'reversi', …) 와 맥 RealtimeLinkConstants.reversiBroadcastEvent.
        assertEquals("reversi", ReversiWire.broadcastEvent)
    }

    // 없으면: 순위 줄의 id 키(`user_id`)를 로비처럼 `id` 로 읽어 순위표가 전부 빈 사람으로 그려진 채 초록이다.
    @Test
    fun rankingResponseReadsEveryValue() {
        val ranking = decode(
            ReversiRankingResponse.serializer(),
            """
            {"status":"ok","server_now_ms":1793659950106,"record_since_ms":null,
             "me":{"rank":1,"wins":3,"losses":1,"draws":2,"points":2},
             "rows":[{"rank":1,"user_id":"$me","display_name":"나","avatar_url":null,"character":"aing","center":"seoul",
                      "wins":3,"losses":1,"draws":2,"points":2}]}
            """.trimIndent(),
        )
        assertEquals(ReversiRPCStatus.ok, ranking.status)
        assertNull(ranking.recordSinceMs)
        assertTrue(ranking.me?.rank == 1L && ranking.me?.points == 2L)
        val row = assertNotNull(ranking.rows?.first())
        assertEquals(me, row.userId)
        assertEquals("나", row.displayName)
        assertEquals("seoul", row.center)
        assertTrue(row.wins == 3L && row.losses == 1L && row.draws == 2L && row.points == 2L)
    }

    // 없으면: 판 문자열이 64자 '.bw' 가 아닌데도 디코드가 받아들여 엉뚱한 칸에 돌이 놓인 채 판정이 돈다(판의 권위).
    @Test
    fun malformedBoardFailsTheWholeResponse() {
        val bad = activeStateJSON.replace("\"board\":\"...................b", "\"board\":\"..................-b")
        assertNotEquals(activeStateJSON, bad)
        assertTrue(runCatching { decode(ReversiActionResponse.serializer(), bad) }.isFailure, "잘못된 판을 받아들였다")
        assertTrue(runCatching { decode(ReversiActionResponse.serializer(), activeStateJSON) }.isSuccess, "기준선")
        val badTurn = activeStateJSON.replace("\"turn\":\"white\"", "\"turn\":\"purple\"")
        assertTrue(runCatching { decode(ReversiActionResponse.serializer(), badTurn) }.isFailure, "모르는 색(Swift 합성 Codable 은 던진다)")
    }

    // ---------- ② 서버 원문 51장 ----------

    private val directory = "Tests/checkTests/Fixtures/reversi-rpc"

    private fun serverFiles(): List<String> {
        val root = File(requireNotNull(System.getProperty("aingcheck.repoRoot")) { "aingcheck.repoRoot 가 없다" }, directory)
        return root.list()!!.filter { it.endsWith(".json") && it != "_manifest.json" }.sorted()
    }

    private fun serverText(file: String): String = RepoFiles.readText("$directory/$file")

    private fun serverJSON(file: String): JsonObject = Json.parseToJsonElement(serverText(file)).jsonObject

    private fun JsonObject.keySet(key: String): Set<String> = (this[key] as? JsonObject)?.keys ?: emptySet()

    // 없으면: 서버 갈래가 픽스처를 다시 뽑다 한 갈래를 빠뜨리거나 이름·status 가 어긋나도 초록이고,
    // 앱 디코더가 원문 status 를 unknown 으로 접어도(어휘 한 글자 차이) 안 보인다. 51장 전부를 원문 그대로 디코드한다.
    @Test
    fun manifestMatchesDiskAndEveryServerFixtureDecodes() {
        val manifest = serverJSON("_manifest.json")
        val entries = manifest["files"]!!.jsonArray.map { it.jsonObject }
        val listed = entries.map { (it["file"] as JsonPrimitive).content }.sorted()
        val onDisk = serverFiles()
        assertEquals(onDisk, listed)
        assertEquals(51, onDisk.size, "픽스처 ${onDisk.size}장 — 줄면 어느 갈래가 사라진 것이다")
        var decodedStates = 0
        for (entry in entries) {
            val file = (entry["file"] as JsonPrimitive).content
            val rpc = (entry["rpc"] as JsonPrimitive).content
            val kase = (entry["case"] as JsonPrimitive).content
            assertEquals("${rpc}__$kase.json", file, "$file: 이름이 rpc__case 가 아니다")
            assertTrue(rpc in ReversiWire.RPC.all, "$file: 모르는 rpc $rpc")
            val top = serverJSON(file)
            val status = (top["status"] as? JsonPrimitive)?.content ?: error("$file: status 없음")
            assertEquals((entry["status"] as JsonPrimitive).content, status, "$file: 매니페스트 status 와 다르다")
            assertEquals((entry["has_state"] as JsonPrimitive).booleanOrNull, top.containsKey("state"), "$file: has_state 가 다르다")
            val text = serverText(file)
            val decoded: ReversiRPCStatus = when (rpc) {
                ReversiWire.RPC.lobby.rawValue -> SwiftJson.decode(ReversiLobbyResponse.serializer(), text).status
                ReversiWire.RPC.ranking.rawValue -> SwiftJson.decode(ReversiRankingResponse.serializer(), text).status
                else -> {
                    val action = SwiftJson.decode(ReversiActionResponse.serializer(), text)
                    assertEquals(top.containsKey("state"), action.state != null, "$file: state 디코드가 빠졌다")
                    if (top.containsKey("state")) {
                        assertNotNull(action.state?.match?.board, "$file: 판 문자열을 못 읽었다")
                        assertNotEquals(ReversiMatchStatus.unknown, action.state?.match?.matchStatus, "$file: 판 status 를 모른다")
                        decodedStates += 1
                    }
                    action.status
                }
            }
            assertEquals(status, decoded.rawValue, "$file: 앱이 status 를 $decoded 로 읽었다")
        }
        assertEquals(30, decodedStates, "상태가 실린 원문 ${decodedStates}장")
        val viewers = manifest["viewers"] as JsonObject
        assertEquals("b0000000-0000-4000-8000-000000000001", (viewers["A"] as JsonPrimitive).content)
        assertEquals("b0000000-0000-4000-8000-000000000002", (viewers["B"] as JsonPrimitive).content)
    }

    // 없으면: 서버가 키를 하나 빼거나 이름을 바꿔도(= 그 자리 화면이 조용히 빈다) 아무도 모른다. 늘기만 하면 디코더는 무사하지만 줄면 빈다 —
    // 그래서 **정확 집합**을 매니페스트 `keys`(서버 갈래가 마이그레이션 사후 단언 `v_*_keys` 에서 뽑은 것)와 재고, 그 키를 와이어 모델이 다 아는지도 잰다.
    @Test
    fun envelopeKeysMatchManifestAndWireModels() {
        val manifestKeys = (serverJSON("_manifest.json")["keys"] as JsonObject).mapValues { (_, v) -> v.jsonArray.map { (it as JsonPrimitive).content }.toSet() }
        for (name in listOf("state", "match", "move", "user", "lobby", "lobby_me", "lobby_user", "lobby_match", "peer")) {
            assertNotNull(manifestKeys[name], "매니페스트에 keys.$name 이 없다")
        }
        var states = 0
        for (file in serverFiles()) {
            val state = serverJSON(file)["state"] as? JsonObject ?: continue
            states += 1
            assertEquals(manifestKeys["state"], state.keys, "$file: state 키")
            assertEquals(manifestKeys["match"], state.keySet("match"), "$file: match 키")
            for (move in (state["moves"] as? JsonArray ?: JsonArray(emptyList()))) assertEquals(manifestKeys["move"], move.jsonObject.keys, "$file: moves[] 키")
            for (key in listOf("black_user", "white_user", "opponent")) {
                if (state[key] is JsonObject) assertEquals(manifestKeys["user"], state.keySet(key), "$file: $key 키")
            }
        }
        assertEquals(30, states, "상태가 실린 픽스처 ${states}장")
        var lobbies = 0
        for (file in serverFiles().filter { it.startsWith("reversi_lobby__") }) {
            val top = serverJSON(file)
            if ((top["status"] as JsonPrimitive).content != "ok") continue
            lobbies += 1
            assertEquals(manifestKeys["lobby"], top.keys, "$file: lobby 키")
            val me = top["me"] as JsonObject
            assertEquals(manifestKeys["lobby_me"], me.keys, "$file: me 키")
            for (user in (top["users"] as? JsonArray ?: JsonArray(emptyList()))) assertEquals(manifestKeys["lobby_user"], user.jsonObject.keys, "$file: users[] 키")
            for (row in (me["incoming"] as? JsonArray ?: JsonArray(emptyList()))) assertEquals(manifestKeys["peer"], row.jsonObject.keySet("from"), "$file: incoming[].from 키")
            (me["outgoing"] as? JsonObject)?.let { assertEquals(manifestKeys["peer"], it.keySet("to"), "$file: outgoing.to 키") }
        }
        assertEquals(3, lobbies)
        // 와이어 모델이 서버 키를 다 안다(at_ms 는 화면이 쓰지 않아 일부러 안 읽는다 — Swift ReversiPly 와 같다).
        assertEquals(manifestKeys["state"], ReversiStatePayload.serializer().fieldNames())
        assertEquals(manifestKeys["match"], ReversiMatchRow.serializer().fieldNames())
        assertEquals(manifestKeys["user"], ReversiPlayerRow.serializer().fieldNames())
        assertEquals(manifestKeys["peer"], ReversiPeerRow.serializer().fieldNames())
        assertEquals(manifestKeys["lobby"], ReversiLobbyResponse.serializer().fieldNames())
        assertEquals(manifestKeys["lobby_me"], ReversiLobbyMe.serializer().fieldNames())
        assertEquals(manifestKeys["lobby_user"], ReversiLobbyUserRow.serializer().fieldNames())
        assertEquals(manifestKeys["lobby_match"], ReversiLobbyMatchRow.serializer().fieldNames())
        assertEquals(manifestKeys["move"]!! - "at_ms", setOf("seq", "color", "kind", "idx", "flipped", "auto"))
    }

    // 없으면: 관전 응답에 참가자 전용 칸(내 색·남의 지갑·둘 수 있는 칸)이 섞여 나가도(= 제3자에게 남의 루비가 간다) 초록이다.
    @Test
    fun watchFixturesCarryNoParticipantFields() {
        for (file in listOf("reversi_watch__ok.json", "reversi_watch_live__ok.json")) {
            val raw = serverJSON(file)["state"] as JsonObject
            for (key in listOf("my_color", "opponent", "my_auto_streak", "opponent_auto_streak", "ruby_balance")) {
                assertTrue(raw[key] is JsonNull, "$file: $key 가 실렸다")
            }
            assertTrue((raw["legal_moves"] as JsonArray).isEmpty(), "$file: legal_moves 가 실렸다")
            val decoded = assertNotNull(SwiftJson.decode(ReversiActionResponse.serializer(), serverText(file)).state)
            assertTrue(decoded.myColor == null && decoded.opponent == null && decoded.rubyBalance == null)
        }
        // watch 는 관전자 수를 안 센다(0) — watch_live 만 센다(1, 관전자 D 한 명).
        assertEquals(0L, SwiftJson.decode(ReversiActionResponse.serializer(), serverText("reversi_watch__ok.json")).state?.watchers)
        assertEquals(1L, SwiftJson.decode(ReversiActionResponse.serializer(), serverText("reversi_watch_live__ok.json")).state?.watchers)
    }

    // 없으면: 서버가 자동 착수 뒤 다음 차례 시계를 **지난 마감**에서 시작해 다음 사람이 응답을 받는 순간 이미 몇 초를 잃어도, 스토어 시험은 원문을
    // 그대로 믿어 초록이다. 새 시계는 이번 따라잡기 시각(= 자동 착수 기록 시각 · 응답의 server_now)에서 시작하고, 받는 순간 남은 시간은 한 차례 거의 그대로다.
    @Test
    fun autoPlacedClockStartsAtCatchUp() {
        val file = "reversi_move__auto_placed.json"
        val top = serverJSON(file)
        val response = SwiftJson.decode(ReversiActionResponse.serializer(), serverText(file))
        assertEquals(ReversiRPCStatus.autoPlaced, response.status)
        assertEquals(1L, response.autoPlacedCount, "$file: 한 번의 따라잡기에 자동 착수는 많아야 한 수다")
        val state = assertNotNull(response.state)
        val match = assertNotNull(state.match)
        assertEquals(ReversiMatchStatus.active, match.matchStatus, "$file: 자동 착수 뒤 판이 끝났다 — 시계를 잴 다음 차례가 없다")
        val rawMoves = ((top["state"] as JsonObject)["moves"] as JsonArray).map { it.jsonObject }
        val autoRow = assertNotNull(rawMoves.lastOrNull { (it["auto"] as? JsonPrimitive)?.booleanOrNull == true }, "$file: 자동 착수 줄이 없다")
        val placedAt = assertNotNull((autoRow["at_ms"] as JsonPrimitive).doubleOrNull)
        val autoPly = assertNotNull(state.moves?.lastOrNull { it.auto })
        val serverNow = assertNotNull(state.serverNowMs)
        val started = assertNotNull(match.turnStartedMs)
        val deadline = assertNotNull(match.deadlineMs)
        val turnMs = (state.turnSeconds ?: 0L) * 1000.0
        assertTrue(turnMs > 0, "$file: turn_seconds 가 없다")
        assertNotEquals(autoPly.color, match.turn, "$file: 자동 착수 뒤 차례가 넘어가지 않았다")
        assertTrue(abs(started - placedAt) < 1000, "$file: 새 차례 시작 $started · 자동 착수 $placedAt — 시계가 소급된다")
        assertTrue(started <= serverNow, "$file: 새 차례가 응답 시각보다 늦게 시작한다")
        assertTrue(deadline - serverNow > turnMs - 1000, "$file: 응답 순간 남은 시간 ${deadline - serverNow}ms — 한 차례 ${turnMs}ms 를 다 못 받는다")
    }

    @Test
    fun matchStatusFoldsWireWords() {
        assertEquals(
            listOf("pending", "declined", "cancelled", "expired", "active", "finished"),
            ReversiMatchStatus.entries.filter { it != ReversiMatchStatus.unknown }.map { it.rawValue },
        )
        for (status in ReversiMatchStatus.entries) assertEquals(status, ReversiMatchStatus.wire(status.rawValue))
        assertEquals(ReversiMatchStatus.unknown, ReversiMatchStatus.wire(null))
        assertEquals(ReversiMatchStatus.unknown, ReversiMatchStatus.wire("ACTIVE"))
        assertFalse(ReversiMatchStatus.wire("active") == ReversiMatchStatus.unknown, "기준선")
    }
}
