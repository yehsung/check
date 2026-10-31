// 원본: Sources/CheckMobileKit/Games/GamesMiniGameScreen.swift:482 · GamesComponents.swift:325,329 · GamesGomokuRanking.swift:306-308 · GamesGomokuMatch.swift:486 · GamesChessRanking.swift:355 · GamesChessWatch.swift:296-302 · GamesTetrisDuelRanking.swift:367
//
// 소스 계약: 게임 화면이 그리는 사람 얼굴(BoardAvatar · 게임 PersonAvatar)은 **전부** 사진 주소를 넘긴다 — 이름만 넘기면 같은 사람이 로비에선 사진,
// 순위·관전·결과에선 캐릭터로 갈린다(이 자리들이 그렇게 11곳 있었다). 줄이 착용값을 들고 있으면 그것도 넘긴다(표가 안 찬 세션에서 전원 이니셜이 되지 않게).
// 주석은 걷어 내고 잰다(기억 source-contract-tests-need-comment-stripping).
package com.yehsung.aingcheck.ui.games

import com.yehsung.aingcheck.ui.theme.SwiftStyleComments
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class GameAvatarCallSiteContractTest {
    private val mp = File(requireNotNull(System.getProperty("aingcheck.mpRoot")))
    private val gamesMain = File(mp, "ui/src/commonMain/kotlin/com/yehsung/aingcheck/ui/games")

    /** (파일 · 호출 글자) — 괄호 짝을 세어 한 호출을 통째로 뽑는다. 선언(`fun BoardAvatar(`)은 뺀다. */
    private fun calls(): List<Pair<String, String>> {
        val out = ArrayList<Pair<String, String>>()
        val head = Regex("(?<![A-Za-z.])(BoardAvatar|PersonAvatar)\\(")
        gamesMain.walkTopDown().filter { it.isFile && it.name.endsWith(".kt") }.forEach { file ->
            val code = SwiftStyleComments.strip(file.readText())
            for (m in head.findAll(code)) {
                if (code.substring(maxOf(0, m.range.first - 4), m.range.first) == "fun ") continue
                var depth = 0
                var i = m.range.last
                while (i < code.length) {
                    if (code[i] == '(') depth++
                    if (code[i] == ')' && --depth == 0) break
                    i++
                }
                out += file.relativeTo(gamesMain).invariantSeparatorsPath to code.substring(m.range.first, i + 1)
            }
        }
        return out
    }

    @Test
    fun everyGameFacePassesThePhoto() {
        val all = calls()
        assertTrue(all.size >= 20, "호출을 못 찾는다(${all.size}건) — 시험이 아무것도 안 재고 초록이 된다")
        assertEquals(emptyList(), all.filter { "url = " !in it.second }.map { "${it.first}: ${it.second}" })
    }

    /** 순위 줄 · 관전 줄 · 결과 줄은 행이 실은 착용값까지 넘긴다(iOS 대응 자리). 미니게임 순위는 서버가 착용값을 싣지 않아 사진만이다. */
    @Test
    fun rankingLiveAndResultRowsPassTheCharacterHint() {
        val rows = calls().filter { (file, call) ->
            file.endsWith("GomokuRanking.kt") || file.endsWith("ChessRanking.kt") || file.endsWith("GamesTetrisDuelRankingSection.kt") ||
                file.endsWith("ChessWatch.kt") || file.endsWith("GomokuMatch.kt") || file.endsWith("GamesHubScreen.kt") || "live." in call
        }
        assertEquals(10, rows.size, rows.joinToString("\n") { it.second })
        assertEquals(emptyList(), rows.filter { "characterHint = " !in it.second }.map { "${it.first}: ${it.second}" })
    }
}
