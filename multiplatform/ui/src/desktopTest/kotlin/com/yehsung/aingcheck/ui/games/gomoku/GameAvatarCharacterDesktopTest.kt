// 원본: Sources/CheckMobileKit/Components/PersonComponents.swift @ 3bd04bd (PersonAvatar — 사진 → 착용 캐릭터 → 이니셜) ·
//       Sources/CheckMobileKit/Games/GamesGomokuScreen.swift:398·443·528(로비 줄 · 신청 카드 · 신청 줄이 userID 를 넘긴다)
//
// 8c 스토어 04: 메시지 화면에선 캐릭터로 보이는 사람이 오목 로비에선 이니셜 원이었다 — 게임 아바타 두 벌(오목·체스 BoardAvatar ·
// 테트리스·미니게임 GamesKit.PersonAvatar)이 착용 캐릭터 표(LocalAppUserCharacters)를 보지 않았다.
// 표가 이 사람을 알면 그림이 이니셜 때와 달라야 한다(기준선: 빈 표로 두 번 그리면 같다 — 비교가 렌더 흔들림에 속지 않게).
package com.yehsung.aingcheck.ui.games.gomoku

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.wire.models.AppUserCharacterDirectory
import com.yehsung.aingcheck.core.wire.models.AppUserCharacterRow
import com.yehsung.aingcheck.ui.components.CharacterArt
import com.yehsung.aingcheck.ui.components.DesktopSnapshots
import com.yehsung.aingcheck.ui.components.PixelImage
import com.yehsung.aingcheck.ui.components.SnapshotCompare
import com.yehsung.aingcheck.ui.games.minigame.kit.PersonAvatar
import com.yehsung.aingcheck.ui.screens.session.kit.LocalAppUserCharacters
import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class GameAvatarCharacterDesktopTest {
    private val userID = "aaaaaaaa-0000-4000-8000-000000000001"
    private val empty = AppUserCharacterDirectory(CharacterArt.portraitIds)
    // 서버 착용값 null = 아잉(늘 아는 캐릭터).
    private val knows = AppUserCharacterDirectory(CharacterArt.portraitIds, listOf(AppUserCharacterRow(userID, null)))

    private fun render(directory: AppUserCharacterDirectory, face: @Composable () -> Unit): PixelImage =
        DesktopSnapshots.render(64, 64) {
            CompositionLocalProvider(LocalAppUserCharacters provides directory) {
                BoardTestTheme(dark = true) { Box(Modifier.padding(10.dp)) { face() } }
            }
        }

    private fun checkDrawsCharacter(what: String, face: @Composable () -> Unit) {
        val initials = render(empty, face)
        assertTrue(SnapshotCompare.diff(initials, render(empty, face)).identical, "$what: 빈 표로 두 번 그린 그림이 다르다 — 렌더가 굳지 않았다")
        assertFalse(
            SnapshotCompare.diff(initials, render(knows, face)).identical,
            "$what: 표가 아는 사람(아잉 착용)인데 이니셜 원 그대로다 — 메시지 화면과 같은 사람이 다르게 보인다",
        )
    }

    @Test
    fun gameAvatarsDrawTheWornCharacterTheDirectoryKnows() {
        checkDrawsCharacter("오목·체스 BoardAvatar") { BoardAvatar("서연", userID, 44.dp) }
        checkDrawsCharacter("테트리스·미니게임 PersonAvatar") { PersonAvatar("서연", userID, 44.dp) }
    }
}
