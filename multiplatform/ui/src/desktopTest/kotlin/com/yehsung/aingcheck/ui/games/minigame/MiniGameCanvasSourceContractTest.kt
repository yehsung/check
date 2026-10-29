// 원본: Sources/CheckMobileKit/Games/GamesTetrisCanvas.swift:41-68 @ 3bd04bd (소스 계약 — 있어야/없어야 할 문자열) ·
//       Sources/CheckMobileKit/Games/GamesTetrisDuelCanvas.swift:38-42 @ 3bd04bd · Sources/CheckCore/MiniGameEngine.swift:312-316 @ 3bd04bd(간격은 한 곳)
//
// Swift 의 캔버스 소스 계약을 Compose 판 문법으로 옮겼다(주석은 걷어 내고 잰다 — 기억 source-contract-tests-need-comment-stripping).
//  · 필터(blur) 금지 · 안 멈추는 반복 애니메이션 금지 · 프레임 간격 리터럴(1/60) 금지 · 키보드 흉내(setLeftHeld…) 금지 · 정적 조작 안내(controlHint) 금지
//  · 캔버스 글자는 **배율을 곱한 값**으로만(canvasSp(기준값 * scale)) — 기준값 8·9 금지(iOS 캡션 하한 10)
//  · 테트리스 판은 painter 한 벌(drawBoard) · 배경은 하늘만(terrain = false) · 무대는 advance 로 고른다
//  · 이 갈래의 `TextStyle(` 은 전부 테마 글꼴(canvasFont())로 시작한다 — 비우면 OS 기본 글꼴로 떨어져 러너마다 글자가 갈린다
//  · 프레임 루프는 **한 곳**(MiniGameFrameLoop 의 withFrameNanos) — 다른 파일이 프레임 시계를 따로 돌리지 않는다
package com.yehsung.aingcheck.ui.games.minigame

import com.yehsung.aingcheck.ui.theme.SwiftStyleComments
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class MiniGameCanvasSourceContractTest {
    private val mp = File(requireNotNull(System.getProperty("aingcheck.mpRoot")))
    private val gamesMain = File(mp, "ui/src/commonMain/kotlin/com/yehsung/aingcheck/ui/games")

    private fun code(relative: String): String = SwiftStyleComments.strip(File(gamesMain, relative).readText())

    private val canvases = listOf(
        "minigame/GamesTimingBarCanvas.kt", "minigame/GamesFlappyCanvas.kt", "minigame/GamesTetrisCanvas.kt",
        "tetris/GamesTetrisDuelCanvas.kt", "tetris/TetrisBoardPainter.kt", "minigame/MiniGameDraw.kt", "minigame/GamesCanvasKit.kt",
    )

    @Test
    fun canvasesKeepTheForbiddenListEmpty() {
        val forbidden = listOf(
            "blur(", "BlurEffect", "RenderEffect", "infiniteRepeatable", "rememberInfiniteTransition", "repeatForever",
            "1.0 / 60", "1f / 60", "1.0/60", "System.nanoTime", // 벽시계(Clock.System · System.currentTimeMillis)는 구조 규칙 R2 가 나무 전체에서 막는다
            "setLeftHeld", "setRightHeld", "setSoftDropHeld", "MiniGameKind.controlHint",
            "canvasSp(8", "canvasSp(9", "object TetrisLayout", "class TetrisLayout",
        )
        for (file in canvases) {
            val text = code(file)
            for (word in forbidden) assertTrue(word !in text, "$file: 금지 문자열 '$word'")
        }
    }

    @Test
    fun everyTextStyleStartsWithTheThemeFont() {
        val style = Regex("""(?<![A-Za-z.])TextStyle\(""")
        val themed = Regex("""^\s*fontFamily = canvasFont\(\)""")
        var seen = 0
        gamesMain.walkTopDown().filter { it.isFile && it.extension == "kt" && (it.path.contains("/minigame/") || it.path.contains("/tetris/") || it.path.contains("\\minigame\\") || it.path.contains("\\tetris\\")) }.forEach { f ->
            val text = SwiftStyleComments.strip(f.readText()).lines().filterNot { it.trimStart().startsWith("import ") }.joinToString("\n")
            for (m in style.findAll(text)) {
                seen++
                assertTrue(themed.containsMatchIn(text.substring(m.range.last + 1)), "${f.name}: TextStyle( 이 테마 글꼴 없이 시작한다 — OS 기본 글꼴로 떨어진다(canvasFont())")
            }
        }
        assertTrue(seen >= 17, "TextStyle( 을 $seen 개만 봤다 — 시험이 소스를 못 읽는다")
    }

    @Test
    fun canvasTextIsScaledFromTenUp() {
        // 캔버스 글자 크기는 전부 canvasSp(기준값 * 배율) — 기준값은 10 이상(iOS 캡션 하한). INV-GamesTetrisCanvas-6f5f324b 의 계약.
        val call = Regex("""canvasSp\(([^()]*)\)""")
        for (file in listOf("minigame/GamesTetrisCanvas.kt", "tetris/GamesTetrisDuelCanvas.kt", "minigame/GamesTimingBarCanvas.kt", "minigame/GamesFlappyCanvas.kt")) {
            val calls = call.findAll(code(file)).map { it.groupValues[1].trim() }.toList()
            assertTrue(calls.isNotEmpty(), "$file: canvasSp 호출이 없다")
            for (arg in calls) {
                assertTrue("scale" in arg, "$file: 배율을 곱하지 않은 글자 크기 canvasSp($arg)")
                val base = Regex("""^(\d+)""").find(arg)?.groupValues?.get(1)?.toInt()
                assertTrue(base == null || base >= 10, "$file: 기준값 $base 는 캡션 하한(10) 아래")
            }
        }
    }

    @Test
    fun tetrisCanvasUsesTheOnePainterAndAdvanceStage() {
        val solo = code("minigame/GamesTetrisCanvas.kt")
        for (word in listOf(
            "TetrisBoardPainter.drawBoard(", "duel = false", "MiniGameStage.forTetrisAdvance(game.advance)", "MiniGameProjection",
            "GamesOverlayCard", "GamesStageChip", "GamesScorePop", "\"Lv \" + game.scoreLevel.toString()", "game.lines.toString() + \"줄\"",
            "GamesMiniGameText.howToPlay(MiniGameKind.tetris)",
        )) assertTrue(word in solo, "솔로 캔버스: '$word' 가 없다")
        val duel = code("tetris/GamesTetrisDuelCanvas.kt")
        for (word in listOf("TetrisBoardPainter.drawBoard(", "duel = true", "TetrisBoardPainter.drawMiniBoard(", "TetrisPhoneText.")) {
            assertTrue(word in duel, "대결 캔버스: '$word' 가 없다")
        }
        for (word in listOf("drawMeter", "garbageMask", "isGarbage")) assertTrue(word !in duel, "대결 캔버스가 painter 대신 직접 칠한다: '$word'")
        val painter = code("tetris/TetrisBoardPainter.kt")
        assertTrue("terrain = false" in painter && "terrain = true" !in painter, "테트리스 판 배경은 하늘만")
        assertTrue("TetrisLayout." in painter && "TetrisPalette." in painter, "배치·색은 core 표 한 벌")
    }

    @Test
    fun rankingsAreTodayOnly() {
        // Android 첫 판(G §8-18 7): 미니게임 순위는 **오늘만** — 역대 순위(맥 0.3.67 · allTime 판)는 이 판에 없다(허브 · 게임 화면 둘 다).
        for (file in listOf("minigame/GamesMiniGameScreen.kt", "minigame/hub/GamesHubScreen.kt")) {
            val text = code(file)
            for (word in listOf("allTime", "AllTime", "MiniGameBoardScope", "역대")) assertTrue(word !in text, "$file: 역대 순위 흔적 '$word'")
        }
        // 기준선: 오늘 순위(hub.boards — 허브의 오늘 표)는 읽는다(빈 파일이면 위 '없음'이 거저 초록이다).
        assertTrue("hub.boards[kind]" in code("minigame/GamesMiniGameScreen.kt"), "게임 화면이 오늘 순위(hub.boards)를 읽지 않는다")
    }

    @Test
    fun theFrameClockRunsInOnePlace() {
        // 범위는 미니게임·테트리스 폴더(위 글꼴 시험과 같은 자리). 체스 판(W4-a ChessBoardCanvas)은 말 비행 애니메이션 동안만 제 프레임을 센다
        //   (INV-GamesChessBoardCanvas-8161a594 — 비행 없으면 한 틱도 안 돎) — 미니게임 시계와 다른 규약이라 이 단언 밖이다(int-j 병합 때 좁힘).
        val owners = gamesMain.walkTopDown().filter { it.isFile && it.name.endsWith(".kt") }
            .filter { it.path.contains("/minigame/") || it.path.contains("/tetris/") || it.path.contains("\\minigame\\") || it.path.contains("\\tetris\\") }
            .filter { "withFrameNanos" in SwiftStyleComments.strip(it.readText()) }
            .map { it.relativeTo(gamesMain).invariantSeparatorsPath }.toList()
        assertEquals(listOf("minigame/MiniGameFrameLoop.kt"), owners, "프레임 시계(withFrameNanos)는 MiniGameFrameLoop 한 곳에서만 돈다")
    }
}
