// 원본: 없음 — 화면 스냅숏 하네스(W3-a · Roborazzi 판정 규칙을 부품 스냅숏 GallerySnapshotAndroidTest 와 같게).
//
// 화면 한 장 = 폰(w360dp)·sw600dp(w600dp) × 밝음·어두움 중 하나. 골든: ui/snapshots/screens/<영역>/android/<이름>.png.
// 세 가지를 잰다: ① 새로 두 번 그려도 같다(굳었다) ② 골든과 같다(기록 기계는 픽셀 그대로, 다른 러너는 굵은 대조 — SnapshotPolicy)
// ③ 한 군데 다른 같은 크기 장면은 다르다(기준선이 다른 입력 — 비교가 내용을 본다). 기록은 AINGCHECK_SNAPSHOT_RECORD=1(그 실행은 실패로 끝난다).
// 사람이 볼 사본(evidence)은 aingcheck.evidenceDir 가 있으면 거기에도 쓴다(사용자 확인용 — iOS 화면과 나란히).
package com.yehsung.aingcheck.ui.screens.session.kit

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.runComposeUiTest
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.rules.text.AingSticker
import com.yehsung.aingcheck.core.wire.models.AppUserCharacterDirectory
import com.yehsung.aingcheck.ui.components.AndroidSnapshots
import com.yehsung.aingcheck.ui.components.CharacterArt
import com.yehsung.aingcheck.ui.components.CharacterExpression
import com.yehsung.aingcheck.ui.components.PixelImage
import com.yehsung.aingcheck.ui.components.SnapshotCompare
import com.yehsung.aingcheck.ui.components.SnapshotPolicy
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import java.io.File

/** 화면 틀(폰 · sw600dp). 높이는 화면 한 장 — 스크롤 아래는 찍지 않는다. */
enum class ScreenFrame(val width: Dp, val height: Dp, val suffix: String) {
    Phone(360.dp, 760.dp, "phone"),
    Tablet(600.dp, 900.dp, "sw600dp"),
}

object ScreenSnapshots {
    private const val TAG = "aingcheck-screen"

    /** 그림 캐시를 미리 채운다(초상 두 표정 · 이모티콘) — 첫 그리기부터 그림이 서게(비동기 디코드가 캡처와 겨루지 않게). */
    suspend fun prewarm(art: ScreenArt) {
        for (id in CharacterArt.portraitIds) for (e in CharacterExpression.entries) art.bundled.get(CharacterArt.portraitPath(id, e))
        for (s in AingSticker.entries) art.bundled.get(StickerArt.path(s))
    }

    /** 테마 + 화면 지역값(멈춘 시계 · 캐시 · 착용 캐릭터 표). */
    @Composable
    fun Frame(dark: Boolean, art: ScreenArt, characters: AppUserCharacterDirectory?, content: @Composable () -> Unit) {
        AingTheme(dark = dark) {
            CompositionLocalProvider(
                LocalScreenTicking provides false,
                LocalScreenArt provides art,
                LocalAppUserCharacters provides (characters ?: AppUserCharacterDirectory(CharacterArt.portraitIds)),
                content = content,
            )
        }
    }

    @OptIn(ExperimentalTestApi::class)
    fun render(frame: ScreenFrame, art: ScreenArt, content: @Composable () -> Unit): PixelImage {
        var out: PixelImage? = null
        runComposeUiTest {
            // Compose 리소스 읽개는 Android 문맥(활동)이 선 뒤에 연다 — 그래서 이 블록 안에서 채운다.
            runBlocking { prewarm(art) }
            setContent {
                Box(Modifier.wrapContentSize(Alignment.TopStart, unbounded = true).testTag(TAG)) {
                    Box(Modifier.size(frame.width, frame.height)) { content() }
                }
            }
            waitForIdle()
            out = AndroidSnapshots.pixels(onNodeWithTag(TAG).captureToImage())
        }
        return requireNotNull(out)
    }

    /**
     * [scene] 의 골든 판정 + 음성 기준선([other] — 한 군데만 다른 같은 크기 장면). [group] 은 `screens/messages` 처럼 골든 폴더.
     */
    fun check(group: String, name: String, frame: ScreenFrame, art: ScreenArt, scene: @Composable () -> Unit, other: @Composable () -> Unit) {
        val first = render(frame, art, scene)
        val second = render(frame, art, scene)
        val out = AndroidSnapshots.outDir()
        val again = SnapshotCompare.diff(first, second)
        if (!again.identical) {
            AndroidSnapshots.writePng(second, File(out, "$name-render2.png"))
            fail("$name: 두 번 그린 장면이 다르다($again) — 렌더가 굳지 않았다")
        }
        assertTrue("$name: 색이 ${first.distinctColors()}개뿐 — 장면이 그려지지 않았다", first.distinctColors() >= 64)
        evidence(first, name)
        val golden = AndroidSnapshots.golden(group, name)
        if (AndroidSnapshots.recording()) {
            AndroidSnapshots.writePng(first, golden)
            fail("$name: 골든을 기록했다(${golden.path}) — 기록 실행은 실패로 끝난다. 기록 변수 없이 다시 돌려 대조한다.")
        }
        assertTrue("$name: 골든이 없다(${golden.path}) — 이 맥에서 ${SnapshotCompare.RECORD_ENV}=1 로 기록한다", golden.isFile)
        val expected = AndroidSnapshots.readPng(golden)
        val exact = SnapshotPolicy.isRecordingHost(System.getProperty("os.name"), System.getProperty("os.arch"))
        val diff = SnapshotCompare.diff(expected, first)
        val coarse = SnapshotCompare.coarse(expected, first)
        println("AINGCHECK-SNAPSHOT android $group/$name mode=${if (exact) "exact" else "coarse"} ${first.width}x${first.height} diff=$diff coarse=$coarse")
        if (!(if (exact) diff.identical else coarse.withinTolerance)) {
            AndroidSnapshots.writePng(first, File(out, "$name-actual.png"))
            SnapshotCompare.diffImage(expected, first)?.let { AndroidSnapshots.writePng(it, File(out, "$name-diff.png")) }
            fail("$name: 골든과 다르다(${if (exact) "픽셀 그대로" else "굵은 대조"} — $diff · $coarse) — build/aingcheck-snapshots/android/$name-{actual,diff}.png")
        }
        val baseline = render(frame, art, other)
        assertEquals("$name: 기준선 크기가 다르다", first.width to first.height, baseline.width to baseline.height)
        val negative = SnapshotCompare.diff(first, baseline)
        val negativeCoarse = SnapshotCompare.coarse(first, baseline)
        println("AINGCHECK-SNAPSHOT-NEGATIVE android $group/$name diff=$negative coarse=$negativeCoarse")
        assertFalse("$name: 한 군데 다른 장면인데 같은 픽셀 — 비교가 내용을 못 본다", negative.identical)
        assertTrue("$name: 기준선 차이 ${negative.differingPixels}px — 한 군데만 달라야 한다", negative.differingPixels in 1 until first.argb.size / 10)
        assertFalse("$name: 굵은 대조가 한 군데 다른 장면을 못 잡는다($negativeCoarse)", negativeCoarse.withinTolerance)
    }

    /** 사용자 확인용 사본(시험 결과와 무관 — 쓰기 실패는 무시한다). */
    private fun evidence(image: PixelImage, name: String) {
        val dir = System.getenv("AINGCHECK_EVIDENCE_DIR") ?: return
        runCatching { AndroidSnapshots.writePng(image, File(dir, "android-$name.png")) }
    }
}
