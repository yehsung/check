// 알림 작은 아이콘 · 강조색(W 8b shell). 시스템 기본 아이콘(stat_notify_chat — 흰 말풍선)으로 돌아가면 빨강.
//  ① 게시한 알림(본 알림 · 묶음 요약 둘 다)의 작은 아이콘 = res/drawable/ic_stat_aing
//  ② 색 = AingPalette.accent(라이트 · 다크 — values-night)
//  ③ 아이콘 그림은 흰 단색 + 투명 바탕(시스템은 알파만 본다 — 유채색 픽셀 0, 불투명 픽셀은 흰색, 눈 구멍이 있어 가운데 위 칸에 투명 픽셀)
package com.yehsung.aingcheck.android.push

import android.app.NotificationManager
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import androidx.core.content.ContextCompat
import androidx.test.core.app.ApplicationProvider
import com.yehsung.aingcheck.android.R
import com.yehsung.aingcheck.android.routing.AingRoute
import com.yehsung.aingcheck.android.routing.RouteRequest
import com.yehsung.aingcheck.ui.theme.AingPalette
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [36])
class NotificationAccentTest {
    private val context: Context get() = ApplicationProvider.getApplicationContext()

    @Test
    @Config(qualifiers = "+notnight")
    fun lightNotificationUsesAingIconAndAccent() = check(AingPalette.accent.light.argb())

    @Test
    @Config(qualifiers = "+night")
    fun darkNotificationUsesAingIconAndAccent() = check(AingPalette.accent.dark.argb())

    @Test
    fun smallIconIsWhiteSilhouetteWithEyeHoles() {
        val drawable = requireNotNull(ContextCompat.getDrawable(context, R.drawable.ic_stat_aing))
        val side = 96
        val bitmap = Bitmap.createBitmap(side, side, Bitmap.Config.ARGB_8888)
        drawable.setBounds(0, 0, side, side)
        drawable.draw(Canvas(bitmap))
        val px = IntArray(side * side).also { bitmap.getPixels(it, 0, side, 0, 0, side, side) }
        val opaque = px.filter { (it ushr 24) == 0xFF }
        val colored = opaque.count { it and 0xFFFFFF != 0xFFFFFF }
        // 눈 칸: 가운데 줄(위 1/3 ~ 1/2) 왼쪽 · 오른쪽 사분 지점 근처에 투명 픽셀이 있어야 한다(덩어리만 있으면 아잉이로 안 읽힌다).
        val eyeHoles = (side * 30 / 100 until side * 46 / 100).sumOf { y -> (side * 25 / 100 until side * 75 / 100).count { x -> (px[y * side + x] ushr 24) == 0 } }
        println("AINGCHECK-NOTIF-ICON opaque=${opaque.size} colored=$colored eyeHoles=$eyeHoles")
        // 증거 PNG(어두운 바탕에 얹어 — 상태 표시줄처럼). 시험 작업 밖(속성 없음)이면 건너뛴다.
        System.getProperty("aingcheck.mpRoot")?.let { mp ->
            val shown = Bitmap.createBitmap(side, side, Bitmap.Config.ARGB_8888).apply { eraseColor(0xFF1A1C26.toInt()) }
            Canvas(shown).drawBitmap(bitmap, 0f, 0f, null)
            val out = java.io.File(mp, "androidApp/build/aingcheck-snapshots/shell/ic_stat_aing.png").apply { parentFile?.mkdirs() }
            out.outputStream().use { shown.compress(Bitmap.CompressFormat.PNG, 100, it) }
        }
        assertEquals("알림 아이콘에 흰색이 아닌 불투명 픽셀이 있다", 0, colored)
        assertTrue("알림 아이콘이 거의 비었다(${opaque.size})", opaque.size > side * side / 3)
        assertTrue("알림 아이콘에 눈 구멍이 없다($eyeHoles)", eyeHoles > 40)
    }

    private fun check(accent: Int) {
        val poster = NotificationPoster(context, acceptProof = { null })
        val spec = NotificationSpec(
            channel = AingChannel.entries.first(),
            title = "아잉체크",
            body = "알림 아이콘 시험",
            tag = "accent-test",
            group = "accent-group",
            tap = RouteRequest(AingRoute.Now),
            actions = emptyList(),
            category = android.app.Notification.CATEGORY_MESSAGE,
        )
        assertTrue("게시하지 못했다", poster.post(spec))
        val manager = context.getSystemService(NotificationManager::class.java)
        val posted = shadowOf(manager).allNotifications
        assertEquals("본 알림 + 묶음 요약", 2, posted.size)
        for (n in posted) {
            assertEquals("작은 아이콘이 아잉이 실루엣이 아니다", R.drawable.ic_stat_aing, n.smallIcon.resId)
            assertEquals("알림 색이 accent 가 아니다", accent, n.color)
        }
    }

    private fun com.yehsung.aingcheck.ui.theme.AingRgb.argb(): Int {
        fun byte(v: Double) = Math.round(v * 255).toInt().coerceIn(0, 255)
        return (0xFF shl 24) or (byte(r) shl 16) or (byte(g) shl 8) or byte(b)
    }
}
