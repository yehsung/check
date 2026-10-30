// 원본: Sources/check/CheckChessWindow.swift:201-205(자리 키가 겹치면 setFrameAutosaveName 이 false — 자리 저장이 조용히 죽는다) ·
//       CheckMiniGameWindow.swift:57 · CheckGomokuWindow.swift:147 · CheckTetrisDuelWindow.swift:139 · CheckGachaWindow.swift:337 ·
//       CheckCakeGiftWindow.swift:248 (W4-d)
package com.yehsung.aingcheck.desktop.windows.kit

import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals

class WindowKeysDistinctTest {
    private val macNames = mapOf(
        GameWindowKind.MiniGame to "check.miniGameWindow",
        GameWindowKind.Gomoku to "check.gomoku.window",
        GameWindowKind.Chess to "check.chess.window",
        GameWindowKind.TetrisDuel to "check.tetris-duel.window",
        GameWindowKind.Gacha to "check.gacha.window",
        GameWindowKind.CakeGift to "check.cakeGift.window",
    )
    private val swiftFiles = mapOf(
        GameWindowKind.MiniGame to "CheckMiniGameWindow.swift",
        GameWindowKind.Gomoku to "CheckGomokuWindow.swift",
        GameWindowKind.Chess to "CheckChessWindow.swift",
        GameWindowKind.TetrisDuel to "CheckTetrisDuelWindow.swift",
        GameWindowKind.Gacha to "CheckGachaWindow.swift",
        GameWindowKind.CakeGift to "CheckCakeGiftWindow.swift",
    )

    /** ★ 자리 키 여섯은 서로 다르다(대소문자 무시까지 — 저장소 키가 파일 이름이 될 수 있다). */
    @Test
    fun boundsKeysAreDistinct() {
        val keys = GameWindowKind.entries.map { it.boundsKey }
        assertEquals(6, keys.size)
        assertEquals(keys.size, keys.toSet().size, "자리 키 중복: $keys")
        assertEquals(keys.size, keys.map { it.lowercase() }.toSet().size, "대소문자만 다른 자리 키: $keys")
    }

    @Test
    fun boundsKeysAreMacAutosaveNames() {
        for (kind in GameWindowKind.entries) assertEquals(macNames.getValue(kind), kind.boundsKey, "$kind")
    }

    /** Swift 원본이 체크아웃에 있으면(맥·CI 전체 체크아웃) 그 리터럴과도 대조한다. 없으면 위 표가 정본. */
    @Test
    fun boundsKeysMatchSwiftSourceWhenPresent() {
        val sources = File(KitGoldens.mpRoot(), "../Sources/check").canonicalFile
        if (!sources.isDirectory) return
        val re = Regex("""static let frameAutosaveName = "([^"]+)"""")
        for ((kind, file) in swiftFiles) {
            val f = File(sources, file)
            if (!f.isFile) continue
            val found = re.find(f.readText())?.groupValues?.get(1)
            assertEquals(found, kind.boundsKey, "$file frameAutosaveName")
        }
    }
}
