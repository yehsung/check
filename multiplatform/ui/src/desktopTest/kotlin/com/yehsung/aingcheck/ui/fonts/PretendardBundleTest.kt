// W1-e 완료 기준 ①: Pretendard 번들 로드(데스크톱). Android 판은 조정자 패치(호스트 시험 — androidResources 켬 뒤)에 있다.
//  - 번들 바이트 = 공식 배포본(sha256) · 출처 표(ui/snapshots/fonts/pretendard-source.tsv)와 같은 값
//  - Skia 가 연 글꼴의 가족 이름 "Pretendard" · 굵기 · 한글 11,172 음절 전부와 화면 문장부호에 글리프가 있다
//  - Compose 렌더가 실제로 이 글꼴을 쓴다: 같은 글자를 기본 글꼴로 그리면 픽셀이 다르고, 굵기끼리도 다르다
//  - OFL 라이선스 원문이 앱 리소스로 같이 나간다
package com.yehsung.aingcheck.ui.fonts

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Text
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.yehsung.aingcheck.ui.components.DesktopSnapshots
import com.yehsung.aingcheck.ui.components.SnapshotCompare
import com.yehsung.aingcheck.ui.resources.Res
import kotlinx.coroutines.runBlocking
import org.jetbrains.compose.resources.ExperimentalResourceApi
import org.jetbrains.skia.Data
import org.jetbrains.skia.FontMgr
import java.io.File
import java.security.MessageDigest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

@OptIn(ExperimentalResourceApi::class)
class PretendardBundleTest {
    private fun sha256(b: ByteArray) = MessageDigest.getInstance("SHA-256").digest(b).joinToString("") { "%02x".format(it) }

    @Test
    fun bundledFacesAreTheOfficialFilesAndCoverHangul() {
        val table = File(DesktopSnapshots.mpRoot, "ui/snapshots/fonts/pretendard-source.tsv").readLines()
            .filter { it.isNotBlank() && !it.startsWith("#") }.map { it.split('\t') }.associateBy { it[0] }
        assertEquals(5, Pretendard.faces.size)
        val syllables = IntArray(11_172) { 0xAC00 + it }
        val punctuation = (0x20..0x7E).toList() + listOf(0x00B7, 0x2014, 0x2013, 0x2026, 0x2192, 0x00D7)
        for (face in Pretendard.faces) {
            val bytes = runBlocking { Res.readBytes(face.path) }
            assertEquals(face.sha256, sha256(bytes), "${face.path}: 번들 바이트가 공식 배포본이 아니다")
            val row = table[face.path] ?: error("출처 표에 ${face.path} 가 없다")
            assertEquals(face.sha256, row[2], "${face.path}: 출처 표 sha256")
            assertEquals(bytes.size.toString(), row[3], "${face.path}: 출처 표 바이트")
            val typeface = requireNotNull(FontMgr.default.makeFromData(Data.makeFromBytes(bytes))) { "${face.path}: Skia 가 글꼴을 못 열었다" }
            assertEquals(Pretendard.FAMILY_NAME, typeface.familyName, "${face.path}: 가족 이름")
            assertEquals(face.weight.weight, typeface.fontStyle.weight, "${face.path}: 굵기")
            val glyphs = typeface.getUTF32Glyphs(syllables)
            val missing = glyphs.indices.filter { glyphs[it].toInt() == 0 }
            assertTrue(missing.isEmpty(), "${face.path}: 한글 음절 ${missing.size}개에 글리프가 없다(첫 U+${"%04X".format(syllables[missing.firstOrNull() ?: 0])})")
            val p = typeface.getUTF32Glyphs(punctuation.toIntArray())
            assertTrue(p.none { it.toInt() == 0 }, "${face.path}: 라틴·문장부호 글리프 빠짐")
            typeface.close()
        }
    }

    @Test
    fun licenseShipsAsResource() {
        // Windows 러너는 git 이 글자 파일 줄끝을 CRLF 로 바꿔 꺼낸다(core.autocrlf, CI 실측) — 원문 대조는 LF 로 되돌려 잰다.
        val text = runBlocking { Res.readBytes(Pretendard.LICENSE_PATH) }.decodeToString().replace("\r\n", "\n").encodeToByteArray()
        assertEquals("b04538c9abec39a3db75108cf0af0fd9c77032fe8aa2cf38345b4d250e98e38e", sha256(text))
        val s = text.decodeToString()
        assertTrue(s.contains("SIL Open Font License, Version 1.1") && s.contains("Reserved Font Name Pretendard"))
        val apache = runBlocking { Res.readBytes("files/licenses/MaterialSymbols-Apache-2.0.txt") }.decodeToString()
        assertTrue(apache.contains("Apache License") && apache.contains("Version 2.0"))
    }

    /** Compose 가 실제로 번들 글꼴로 그린다(글꼴을 못 열면 기본 글꼴로 접혀 두 장이 같아진다 — 그 결함을 잡는다). */
    @Test
    fun composeRendersWithBundledFontNotSystemDefault() {
        val sample = "Pretendard 0123 아잉체크 WMiil"
        fun shot(family: @androidx.compose.runtime.Composable () -> FontFamily, weight: FontWeight) = DesktopSnapshots.render(320, 40) {
            Text(
                sample,
                Modifier.size(320.dp, 40.dp).background(Color.White),
                style = TextStyle(fontFamily = family(), fontWeight = weight, fontSize = 20.sp, color = Color.Black),
            )
        }
        val pretendard = shot({ pretendardFontFamily() }, FontWeight.Normal)
        val pretendardAgain = shot({ pretendardFontFamily() }, FontWeight.Normal)
        val system = shot({ FontFamily.Default }, FontWeight.Normal)
        val bold = shot({ pretendardFontFamily() }, FontWeight.Bold)
        assertTrue(pretendard.distinctColors() > 8, "글자가 그려지지 않았다")
        assertTrue(SnapshotCompare.diff(pretendard, pretendardAgain).identical, "같은 글꼴 두 번이 다르다")
        assertFalse(SnapshotCompare.diff(pretendard, system).identical, "번들 글꼴과 기본 글꼴이 같은 픽셀 — 번들 글꼴이 안 실렸다")
        assertFalse(SnapshotCompare.diff(pretendard, bold).identical, "Regular 와 Bold 가 같은 픽셀 — 굵기가 안 실렸다")
    }
}
