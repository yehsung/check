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
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.runComposeUiTest
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.wire.models.AppUserCharacterDirectory
import com.yehsung.aingcheck.core.wire.models.AppUserCharacterRow
import com.yehsung.aingcheck.ui.components.CharacterArt
import com.yehsung.aingcheck.ui.components.DesktopSnapshots
import com.yehsung.aingcheck.ui.components.PixelImage
import com.yehsung.aingcheck.ui.components.SnapshotCompare
import com.yehsung.aingcheck.ui.games.minigame.kit.PersonAvatar
import com.yehsung.aingcheck.ui.screens.session.kit.AvatarPhotoLoader
import com.yehsung.aingcheck.ui.screens.session.kit.LocalAppUserCharacters
import com.yehsung.aingcheck.ui.screens.session.kit.LocalScreenArt
import com.yehsung.aingcheck.ui.screens.session.kit.ScreenArt
import kotlin.test.Test
import kotlin.test.assertEquals
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

    /** 표가 비어도 행이 실은 착용값으로 캐릭터를 그린다(Swift `characterHint` — 착용 표가 안 찬 세션에서 순위표 전원이 이니셜이 되던 꼴). */
    @Test
    fun gameAvatarsDrawTheRowsCharacterHintWhenTheDirectoryIsEmpty() {
        for ((what, plain, hinted) in listOf<Triple<String, @Composable () -> Unit, @Composable () -> Unit>>(
            Triple("BoardAvatar", { BoardAvatar("서연", userID, 44.dp) }, { BoardAvatar("서연", userID, 44.dp, characterHint = "fox") }),
            Triple("PersonAvatar", { PersonAvatar("서연", userID, 44.dp) }, { PersonAvatar("서연", userID, 44.dp, characterHint = "fox") }),
        )) {
            assertFalse(SnapshotCompare.diff(render(empty, plain), render(empty, hinted)).identical, "$what: 힌트를 받고도 이니셜 원이다")
            // 표가 아는 사람은 표가 이긴다 — 아잉을 입은 사람에게 여우 힌트가 와도 같은 그림.
            assertTrue(SnapshotCompare.diff(render(knows, plain), render(knows, hinted)).identical, "$what: 표가 아는 사람인데 힌트가 이겼다")
        }
    }

    /** 사진 주소를 받으면 그 사진을 청한다(읽개가 받은 주소로 잰다). 주소가 없으면 묻지 않는다. */
    @OptIn(ExperimentalTestApi::class)
    @Test
    fun gameAvatarsAskForThePhotoTheyAreGiven() {
        for ((what, face) in listOf<Pair<String, @Composable (String?) -> Unit>>(
            "BoardAvatar" to { url -> BoardAvatar("서연", userID, 44.dp, url = url) },
            "PersonAvatar" to { url -> PersonAvatar("서연", userID, 44.dp, url = url) },
        )) {
            val asked = ArrayList<String>()
            val art = ScreenArt(AvatarPhotoLoader { url -> asked += url; ImageBitmap(4, 4) })
            runComposeUiTest {
                setContent {
                    BoardTestTheme(dark = true) {
                        CompositionLocalProvider(LocalScreenArt provides art) {
                            face(null)
                            face("https://example.com/p.jpg")
                        }
                    }
                }
                waitForIdle()
            }
            assertEquals(listOf("https://example.com/p.jpg"), asked, what)
        }
    }

    @Test
    fun gameAvatarsDrawTheWornCharacterTheDirectoryKnows() {
        checkDrawsCharacter("오목·체스 BoardAvatar") { BoardAvatar("서연", userID, 44.dp) }
        checkDrawsCharacter("테트리스·미니게임 PersonAvatar") { PersonAvatar("서연", userID, 44.dp) }
    }
}
