// 원본: 없음 — 아잉 뒤집기(판 7) 화면 스냅숏 장면과 손으로 짠 서버 모양 응답. 데스크톱·Android 가 같은 장면을 그린다(BoardSnapshot*Test).
//
// 서버 호출 없이 **서버 모양 JSON**(키는 `reversi_*` jsonb 그대로 — Tests/checkTests/Fixtures/reversi-rpc/_manifest.json 의 키 표)을 스토어의 픽스처 문
// (`applyLobby` · `applyState` · `applyWatch` · `applyRanking`)으로 넣는다. 판 글자와 기록은 **규칙 코어로 둔** 대국이다(손으로 적은 판이 규칙과 어긋나지 않게).
// 장면마다 스토어 묶음(BoardGameRig)을 **그 그림 안에서** 새로 세운다 — 화면이 내려갈 때 끝난 판을 접고(`windowDidClose`) 관전을 내리므로(`stopWatching`)
// 같은 스토어로 다시 그리면 두 번째 그림이 다른 장면이 된다. 장면마다 **한 군데만 다른** 짝(음성 기준선)을 같이 낸다.
package com.yehsung.aingcheck.ui.games.reversi

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.rules.reversi.ReversiPlay
import com.yehsung.aingcheck.core.rules.reversi.ReversiPoint
import com.yehsung.aingcheck.core.rules.reversi.ReversiRules
import com.yehsung.aingcheck.core.stores.reversi.ReversiStore
import com.yehsung.aingcheck.core.stores.reversi.aiMoveChooser
import com.yehsung.aingcheck.core.stores.reversi.applyRanking
import com.yehsung.aingcheck.core.stores.reversi.applyWatch
import com.yehsung.aingcheck.core.stores.reversi.startAIMatch
import com.yehsung.aingcheck.core.stores.reversi.startWatching
import com.yehsung.aingcheck.core.wire.games.ReversiActionResponse
import com.yehsung.aingcheck.core.wire.games.ReversiBoard
import com.yehsung.aingcheck.core.wire.games.ReversiColor
import com.yehsung.aingcheck.core.wire.games.ReversiLobbyResponse
import com.yehsung.aingcheck.core.wire.games.ReversiRankingResponse
import com.yehsung.aingcheck.core.wire.games.ReversiStatePayload
import com.yehsung.aingcheck.core.wire.json.SwiftJson
import com.yehsung.aingcheck.ui.components.CharacterMood
import com.yehsung.aingcheck.ui.games.gomoku.BoardGameMe
import com.yehsung.aingcheck.ui.games.gomoku.BoardGameRig
import com.yehsung.aingcheck.ui.games.gomoku.BoardScene
import com.yehsung.aingcheck.ui.games.gomoku.boardClock
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.launch

/** 손으로 짠 아잉 뒤집기 서버 응답(규칙 코어로 둔 판 · 키는 서버 jsonb 그대로). */
object ReversiHand {
    const val ME: String = "cccccccc-0000-4000-8000-0000000000a1"
    const val RIVAL: String = "cccccccc-0000-4000-8000-0000000000b2"
    const val MATCH: String = "dddddddd-0000-4000-8000-0000000000c3"
    const val LIVE: String = "dddddddd-0000-4000-8000-0000000000d4"
    const val INVITE_A: String = "dddddddd-0000-4000-8000-0000000000e5"
    const val INVITE_B: String = "dddddddd-0000-4000-8000-0000000000e6"

    /** 로비 목록 밖에서 대결 중인 사람(지금 대결 중 한 판의 b). */
    const val STAR: String = "cccccccc-0000-4000-8000-000000000006"
    val users: List<Triple<String, String, String>> = listOf(
        // (id, 별명, 성질) — 성질: ok(신청 가능) · outdated(옛 버전 — 서버 reversi_android_min_build 가 닫힌 동안의 안드로이드 상대) · busy(대결 중) · focus(집중)
        Triple("cccccccc-0000-4000-8000-000000000001", "솜사탕", "ok"),
        Triple("cccccccc-0000-4000-8000-000000000002", "구름빵", "ok"),
        Triple("cccccccc-0000-4000-8000-000000000003", "달토끼", "busy"),
        Triple("cccccccc-0000-4000-8000-000000000004", "옛폰", "outdated"),
        Triple("cccccccc-0000-4000-8000-000000000005", "고요", "focus"),
    )

    /** 서버 시각(ms) — 스냅숏 고정 시계([boardClock])와 같은 눈금이라 마감 = 지금 + 남은 초. */
    val nowMs: Long = (boardClock.timeIntervalSince1970 * 1000).toLong()

    data class Played(val board: ReversiBoard, val plies: List<String>, val turn: ReversiColor?, val moveCount: Int)

    /**
     * 시작 판에서 [picks] 대로 둔다 — 차례마다 합법 수 목록(오름차순)의 `pick % size` 번째. 둘 곳이 없으면 넘김 줄을 적는다. [autoSeqs] 의 seq 는 자동 착수로 적는다.
     * 결과는 규칙 코어가 계산한 판 · 기록(서버 `moves` 줄 JSON) · 다음 차례.
     */
    fun play(picks: List<Int>, autoSeqs: Set<Int> = emptySet()): Played {
        var board = ReversiBoard.start
        var turn: ReversiColor? = ReversiColor.black
        val plies = ArrayList<String>()
        var seq = 0
        for (pick in picks) {
            val color = turn ?: break
            val legal = ReversiRules.legalMoves(board, color)
            seq += 1
            if (legal.isEmpty()) {
                plies += """{"seq":$seq,"color":"${color.rawValue}","kind":"pass","idx":null,"flipped":[],"auto":false,"at_ms":$nowMs}"""
                turn = color.opponent
                continue
            }
            val idx = legal[pick % legal.size]
            val outcome = (ReversiRules.play(board, color, idx) as ReversiPlay.Played).outcome
            plies += """{"seq":$seq,"color":"${color.rawValue}","kind":"stone","idx":$idx,"flipped":[${outcome.flipped.joinToString(",")}],"auto":${seq in autoSeqs},"at_ms":$nowMs}"""
            board = outcome.board
            turn = outcome.next
        }
        return Played(board, plies, turn, seq)
    }

    private fun q(v: String?): String = if (v == null) "null" else "\"$v\""

    private fun player(id: String, name: String, character: String?): String =
        """{"user_id":"$id","display_name":"$name","avatar_url":null,"character":${q(character)},"center":null}"""

    /** reversi_state 의 `state` 한 벌(내 판). 나는 [ME](흑 또는 백), 상대는 [RIVAL]("라이벌"). */
    fun stateJson(
        played: Played,
        myColor: ReversiColor = ReversiColor.black,
        remainingSeconds: Int = 21,
        finished: Boolean = false,
        result: String? = null,
        endReason: String? = null,
        stake: Int = 5,
        myAutoStreak: Int = 0,
        watchers: Int = 0,
        opponentName: String = "라이벌",
    ): String {
        val black = if (myColor == ReversiColor.black) ME else RIVAL
        val white = if (myColor == ReversiColor.black) RIVAL else ME
        val turn = if (finished) null else played.turn?.rawValue
        val legal = if (!finished && played.turn == myColor) ReversiRules.legalMoves(played.board, myColor) else emptyList()
        val winner = when (result) {
            "black_win" -> black
            "white_win" -> white
            else -> null
        }
        val counts = played.board.counts
        val deadline = if (finished) "null" else "${nowMs + remainingSeconds * 1000L}"
        val started = if (finished) "null" else "${nowMs - (30 - remainingSeconds) * 1000L}"
        val myStreakKey = if (myColor == ReversiColor.black) "black_auto_streak" else "white_auto_streak"
        val otherStreakKey = if (myColor == ReversiColor.black) "white_auto_streak" else "black_auto_streak"
        return """
            {"match":{"id":"$MATCH","status":"${if (finished) "finished" else "active"}","stake":$stake,"challenger":"$RIVAL","opponent":"$ME",
            "black":"$black","white":"$white","move_count":${played.moveCount},"turn":${q(turn)},"turn_started_ms":$started,"deadline_ms":$deadline,
            "invite_expires_ms":null,"started_ms":${nowMs - 95_000},"finished_ms":${if (finished) nowMs else "null"},"result":${q(result)},
            "end_reason":${q(endReason)},"winner":${q(winner)},"board":"${played.board.string}",
            "discs":{"black":${counts.black},"white":${counts.white},"empty":${counts.empty}},"score":null},
            "moves":[${played.plies.joinToString(",")}],
            "black_user":${player(black, if (black == ME) "나" else opponentName, if (black == ME) "fox" else "aing")},
            "white_user":${player(white, if (white == ME) "나" else opponentName, if (white == ME) "fox" else "aing")},
            "opponent":${player(RIVAL, opponentName, "aing")},
            "my_color":"${myColor.rawValue}","legal_moves":[${legal.joinToString(",")}],
            "$myStreakKey":$myAutoStreak,"$otherStreakKey":0,"my_auto_streak":$myAutoStreak,"opponent_auto_streak":0,
            "auto_abandon_streak":3,"turn_seconds":30,"grace_ms":2000,"ruby_balance":null,"watchers":$watchers,"server_now_ms":$nowMs}
        """.trimIndent()
    }

    fun state(json: String): ReversiStatePayload = SwiftJson.decode(ReversiStatePayload.serializer(), json)

    /** 관전 응답(reversi_watch — 내 색 없음). 흑 [blackName] · 백 [whiteName]. */
    fun watchJson(played: Played, blackName: String, whiteName: String, remainingSeconds: Int = 14, watchers: Int = 3): String {
        val a = users[2].first
        val b = STAR
        val counts = played.board.counts
        return """
            {"status":"ok","state":{"match":{"id":"$LIVE","status":"active","stake":10,"challenger":"$a","opponent":"$b","black":"$a","white":"$b",
            "move_count":${played.moveCount},"turn":${q(played.turn?.rawValue)},"turn_started_ms":${nowMs - (30 - remainingSeconds) * 1000L},
            "deadline_ms":${nowMs + remainingSeconds * 1000L},"invite_expires_ms":null,"started_ms":${nowMs - 95_000},"finished_ms":null,"result":null,
            "end_reason":null,"winner":null,"board":"${played.board.string}","discs":{"black":${counts.black},"white":${counts.white},"empty":${counts.empty}},"score":null},
            "moves":[${played.plies.joinToString(",")}],
            "black_user":${player(a, blackName, "shiba")},"white_user":${player(b, whiteName, "fox")},
            "opponent":null,"my_color":null,"legal_moves":[],"black_auto_streak":0,"white_auto_streak":1,"my_auto_streak":null,"opponent_auto_streak":null,
            "auto_abandon_streak":3,"turn_seconds":30,"grace_ms":2000,"ruby_balance":null,"watchers":$watchers,"server_now_ms":$nowMs}}
        """.trimIndent()
    }

    /** 로비 응답 한 벌 — 다섯 사람(신청 가능 둘 · 대결 중 · 옛 버전 · 집중) · 받은 신청 둘 · 지금 대결 중 한 판 · 전적 6승 2패 1무. */
    fun lobbyJson(ruby: Int = 100, incoming: Boolean = true, live: Boolean = true): String {
        val rows = users.mapIndexed { index, (id, name, kind) ->
            """{"id":"$id","display_name":"$name","avatar_url":null,"character":${q(if (index == 0) "fox" else null)},"center":${q(if (index == 0) "seoul" else null)},
            "is_working":${index % 2 == 0},"in_match":${kind == "busy"},"capable":${kind != "outdated"},"focus_mode":${kind == "focus"}}"""
        }
        val invites = if (!incoming) "[]" else """[
            {"match_id":"$INVITE_A","from":{"id":"${users[1].first}","display_name":"${users[1].second}","avatar_url":null,"character":null},"stake":5,"expires_at_ms":${nowMs + 42_000}},
            {"match_id":"$INVITE_B","from":{"id":"${users[0].first}","display_name":"${users[0].second}","avatar_url":null,"character":"fox"},"stake":10,"expires_at_ms":${nowMs + 51_000}}]"""
        val matches = if (!live) "[]" else """[{"id":"$LIVE","a":{"id":"${users[2].first}","display_name":"${users[2].second}","avatar_url":null,"character":"shiba"},
            "b":{"id":"$STAR","display_name":"별사탕","avatar_url":null,"character":"fox"},"stake":10,"watchers":3,"started_at_ms":${nowMs - 95_000}}]"""
        return """
            {"status":"ok","server_now_ms":$nowMs,"stakes":[3,5,10],"turn_seconds":30,"turn_grace_seconds":2,"invite_ttl_seconds":60,"auto_abandon_streak":3,
            "me":{"ruby_balance":$ruby,"wins":6,"losses":2,"draws":1,"active_match_id":null,"incoming":$invites,"outgoing":null},
            "users":[${rows.joinToString(",")}],"matches":$matches}
        """.trimIndent()
    }

    fun lobby(json: String): ReversiLobbyResponse = SwiftJson.decode(ReversiLobbyResponse.serializer(), json)

    /** 순위 응답 — 일곱 행(한 사람은 0판 — 화면이 거른다) · 내 순위 2위(로비 전적 6승 2패 1무와 같다). */
    fun rankingJson(): String {
        val rows = listOf(
            listOf(1, "솜사탕", 9, 2, 1), listOf(2, "나", 6, 2, 1), listOf(3, "구름빵", 4, 2, 0), listOf(4, "달토끼", 3, 3, 2),
            listOf(5, "고요", 2, 3, 0), listOf(6, "옛폰", 1, 4, 1), listOf(7, "새내기", 0, 0, 0),
        ).mapIndexed { index, r ->
            val id = if (r[1] == "나") ME else "cccccccc-0000-4000-8000-0000000001" + index.toString().padStart(2, '0')
            val wins = r[2] as Int
            val losses = r[3] as Int
            """{"rank":${r[0]},"user_id":"$id","display_name":"${r[1]}","avatar_url":null,"character":null,"center":null,"wins":$wins,"losses":$losses,"draws":${r[4]},"points":${wins - losses}}"""
        }
        return """{"status":"ok","server_now_ms":$nowMs,"record_since_ms":null,"me":{"rank":2,"wins":6,"losses":2,"draws":1,"points":4},"rows":[${rows.joinToString(",")}]}"""
    }
}

/** 아잉 뒤집기 장면 표(판 7). 그룹 "games/reversi" — 골든은 ui/snapshots/games/reversi/{desktop,android}/<이름>.png. */
object ReversiScenes {
    const val WIDTH: Int = 390
    const val GROUP: String = "games/reversi"

    /** 장면 안에서 새 묶음을 세운다(그림마다 같은 첫 상태 — 머리말). [seed] 는 스토어에 응답을 넣는다. */
    @Composable
    private fun rememberRig(me: String?, ruby: Int, seed: (BoardGameRig, ReversiStore) -> Unit): BoardGameRig = remember {
        BoardGameRig(me = me, withReversi = true).also { rig ->
            rig.sharedRuby = ruby.toLong()
            seed(rig, requireNotNull(rig.reversi))
        }
    }

    private val meFox = BoardGameMe("나검정", "fox", CharacterMood.Working)

    @Composable
    private fun Screen(rig: BoardGameRig, me: BoardGameMe, widthDp: Int, heightDp: Int) {
        ReversiScreen(rig.games, me, onLeave = {}, modifier = Modifier.size(widthDp.dp, heightDp.dp))
    }

    /** 로비(사람 절 전부 + 순위 + 지금 대결 중). 기준선은 루비 하나. */
    fun lobby(dark: Boolean, ruby: Int = 100): BoardScene =
        BoardScene(GROUP, "reversi-lobby-${if (dark) "dark" else "light"}", WIDTH, 2000) { wrap ->
            val rig = rememberRig(null, ruby) { _, r ->
                r.applyLobby(ReversiHand.lobby(ReversiHand.lobbyJson(ruby)))
                r.applyRanking(SwiftJson.decode(ReversiRankingResponse.serializer(), ReversiHand.rankingJson()))
            }
            wrap(dark) { Screen(rig, BoardGameMe.unknown, WIDTH, 2000) }
        }

    /** 큰 글꼴(글꼴 배율 1.3) · 작은 폰(360dp) 로비. 기준선은 루비 하나. */
    fun lobbyLargeFont(ruby: Int = 100): BoardScene =
        BoardScene(GROUP, "reversi-lobby-largefont-360", 360, 2000) { wrap ->
            val rig = rememberRig(null, ruby) { _, r ->
                r.applyLobby(ReversiHand.lobby(ReversiHand.lobbyJson(ruby)))
                r.applyRanking(SwiftJson.decode(ReversiRankingResponse.serializer(), ReversiHand.rankingJson()))
            }
            wrap(false) {
                val density = LocalDensity.current
                CompositionLocalProvider(LocalDensity provides Density(density.density, fontScale = 1.3f)) { Screen(rig, BoardGameMe.unknown, 360, 2000) }
            }
        }

    /** 판 진행 — 흑(나) 차례 · 10수 · 마감 21초 · 관전자 2. 기준선은 내 이름. */
    fun match(dark: Boolean, meName: String = "나검정"): BoardScene =
        BoardScene(GROUP, "reversi-match-${if (dark) "dark" else "light"}", WIDTH, 1000) { wrap ->
            val rig = rememberRig(ReversiHand.ME, 100) { _, r ->
                r.applyState(ReversiHand.state(ReversiHand.stateJson(ReversiHand.play(listOf(0, 1, 2, 0, 1, 3, 2, 1, 0, 2)), watchers = 2)))
            }
            wrap(dark) { Screen(rig, meFox.copy(name = meName), WIDTH, 1000) }
        }

    /**
     * 자동 착수 경고 — 내 차례 마지막 2초(판 테두리 빛) · 내 돌 둘이 시간 초과로 자동으로 놓였다(회색 점 · '자동 2/3' · 빨강 한 줄 '한 번 더 시간이 지나면 져요').
     * 기준선은 내 이름.
     */
    fun matchWarning(meName: String = "나검정"): BoardScene =
        BoardScene(GROUP, "reversi-match-warning-light", WIDTH, 1000) { wrap ->
            val rig = rememberRig(ReversiHand.ME, 100) { _, r ->
                val played = ReversiHand.play(listOf(0, 1, 2, 0, 1, 3, 2, 1, 0, 2), autoSeqs = setOf(7, 9))
                r.applyState(ReversiHand.state(ReversiHand.stateJson(played, remainingSeconds = 2, myAutoStreak = 2)))
            }
            wrap(false) { Screen(rig, meFox.copy(name = meName), WIDTH, 1000) }
        }

    /** 결과 — 상대 기권으로 이겼다(판돈 5 → +5). 받은 신청 하나가 판 위 띠로 선다(끝난 판 위). 기준선은 내 이름. */
    fun result(meName: String = "나검정"): BoardScene =
        BoardScene(GROUP, "reversi-result-light", WIDTH, 1200) { wrap ->
            val rig = rememberRig(ReversiHand.ME, 105) { _, r ->
                r.applyLobby(ReversiHand.lobby(ReversiHand.lobbyJson(105)))
                val played = ReversiHand.play(listOf(0, 1, 2, 0, 1, 3, 2, 1, 0, 2, 1, 0, 2, 1))
                r.applyState(ReversiHand.state(ReversiHand.stateJson(played, finished = true, result = "black_win", endReason = "resign")))
            }
            wrap(false) { Screen(rig, meFox.copy(name = meName), WIDTH, 1200) }
        }

    /** 결과(다크) — 무승부 환불 한 줄(판 위 돌이 같은 끝난 판). 기준선은 내 이름. */
    fun resultDraw(meName: String = "나검정"): BoardScene =
        BoardScene(GROUP, "reversi-result-draw-dark", WIDTH, 1000) { wrap ->
            val rig = rememberRig(ReversiHand.ME, 100) { _, r ->
                // 둘 다 둘 곳이 없는 판(흑 셋 · 백 셋 — 같은 수) — 규칙 코어가 무승부로 친다.
                val board = requireNotNull(ReversiBoard.fromString("bbb" + ".".repeat(53) + "www....."))
                val played = ReversiHand.Played(board, emptyList(), null, 6)
                r.applyState(ReversiHand.state(ReversiHand.stateJson(played, finished = true, result = "draw", endReason = "no_moves")))
            }
            wrap(true) { Screen(rig, meFox.copy(name = meName), WIDTH, 1000) }
        }

    /** 로봇 연습 — 흑(나)으로 시작해 한 수씩 주고받은 판(로봇은 첫 합법 수를 두는 결정적 가짜). 기준선은 내 이름. */
    fun ai(meName: String = "나검정"): BoardScene =
        BoardScene(GROUP, "reversi-ai-light", WIDTH, 1000) { wrap ->
            val rig = rememberRig(null, 100) { rig, r ->
                r.aiMoveChooser = { board, color -> ReversiRules.legalMoves(board, color).firstOrNull() }
                r.aiRuntime.minimumThinkSeconds = 0.0
                r.startAIMatch(ReversiColor.black)
                // 사람 한 수(d3) → 로봇 한 수(가상 시간 안에서 끝까지).
                val d3 = requireNotNull(ReversiPoint.fromCoord("d3")).idx
                rig.scope.launch { r.place(d3) }
                rig.settle()
                rig.advance(1.0)
                rig.settle()
            }
            wrap(false) { Screen(rig, meFox.copy(name = meName), WIDTH, 1000) }
        }

    /** 관전 — 지금 대결 중 판을 [관전]으로 열었다(흑 달토끼 · 백 별사탕 · 관전자 3). 기준선은 관전 응답의 흑 이름 하나. */
    fun watch(blackName: String = "달토끼"): BoardScene =
        BoardScene(GROUP, "reversi-watch-light", WIDTH, 2000) { wrap ->
            val rig = rememberRig(ReversiHand.ME, 100) { _, r ->
                r.applyLobby(ReversiHand.lobby(ReversiHand.lobbyJson(100, incoming = false)))
                r.startWatching(ReversiHand.LIVE)
                val played = ReversiHand.play(listOf(1, 0, 2, 1, 0, 3, 1, 2, 0))
                r.applyWatch(SwiftJson.decode(ReversiActionResponse.serializer(), ReversiHand.watchJson(played, blackName, "별사탕")))
            }
            wrap(false) { Screen(rig, BoardGameMe.unknown, WIDTH, 2000) }
        }

    /** 순위 절만(펼친 상태 · 내 순위 줄 · 0판 거르기). 기준선은 펼침 여부. */
    fun ranking(expanded: Boolean = true): BoardScene =
        BoardScene(GROUP, "reversi-ranking-light", WIDTH, 900) { wrap ->
            val rig = rememberRig(ReversiHand.ME, 100) { _, r ->
                r.applyLobby(ReversiHand.lobby(ReversiHand.lobbyJson(100)))
                r.applyRanking(SwiftJson.decode(ReversiRankingResponse.serializer(), ReversiHand.rankingJson()))
            }
            val state = remember { ReversiScreenState().also { it.rankingExpanded = expanded } }
            wrap(false) {
                Box(Modifier.size(WIDTH.dp, 900.dp).background(AingTheme.colors.background)) {
                    Column(Modifier.padding(horizontal = 16.dp)) { ReversiRankingSection(requireNotNull(rig.reversi), state) }
                }
            }
        }

    /** 규칙 시트(로비 위 · 숫자는 로비 응답 값). 기준선은 한 수 초(30 → 300 — 한 줄의 글자 수가 바뀌어 굵은 대조도 잡는다). */
    fun rules(turnSeconds: Int = 30): BoardScene =
        BoardScene(GROUP, "reversi-rules-light", WIDTH, 1600) { wrap ->
            val rig = rememberRig(null, 100) { _, r ->
                r.applyLobby(ReversiHand.lobby(ReversiHand.lobbyJson(100).replace("\"turn_seconds\":30", "\"turn_seconds\":$turnSeconds")))
                r.isRulesVisible = true
            }
            wrap(false) { Screen(rig, BoardGameMe.unknown, WIDTH, 1600) }
        }
}
