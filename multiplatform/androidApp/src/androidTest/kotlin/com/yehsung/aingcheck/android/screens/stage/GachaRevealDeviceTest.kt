// 원본: 없음 — 8b reveal 갈래(사용자 결정 "첫 판부터 한 바퀴" — G §8-19 #6②). Swift 짝 없음(iOS 공개는 초상만).
// 기기에서 뽑기 기계 무대(ui GachaMachineStage)가 **첫 결과**(황금 아잉이)를 공개할 때, 앱 껍데기(AingShell)와 같은 배선의 살아 있는
// 미리보기(AingStage · revealKey = 공개 번호)가 그 자리에서 한 바퀴 돌아 등이 보이는지 잰다. 감독은 손 시계로 공개 직전까지 몰고,
// 공개부터는 실제 시각으로 흐른다. 화면은 UiAutomation 연속 스크린숏으로 찍어 추가 출력 폴더(additionalTestOutputDir)에 남긴다.
package com.yehsung.aingcheck.android.screens.stage

import android.graphics.Bitmap
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.PixelCopy
import android.view.Window
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.yehsung.aingcheck.character.player.CharacterFrame
import com.yehsung.aingcheck.ui.gacha.machine.GachaCapsuleSprites
import com.yehsung.aingcheck.ui.gacha.machine.GachaMachineArt
import com.yehsung.aingcheck.ui.gacha.machine.GachaMachineDirector
import com.yehsung.aingcheck.ui.gacha.machine.GachaMachineEnv
import com.yehsung.aingcheck.ui.gacha.machine.GachaMachineHaptics
import com.yehsung.aingcheck.ui.gacha.machine.GachaMachineScaler
import com.yehsung.aingcheck.ui.gacha.machine.GachaMachineStage
import com.yehsung.aingcheck.ui.gacha.machine.GachaMachineTheme
import com.yehsung.aingcheck.ui.gacha.machine.GachaRevealKind
import com.yehsung.aingcheck.ui.gacha.machine.GachaRevealOutcome
import com.yehsung.aingcheck.ui.shop.LiveCharacterPreview
import com.yehsung.aingcheck.ui.shop.LocalLiveCharacterPreview
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicLong
import kotlin.test.assertEquals
import kotlin.test.assertTrue

@RunWith(AndroidJUnit4::class)
class GachaRevealDeviceTest {
    private class Shot(val t: Double, val yawBefore: Int?, val yawAfter: Int?, val image: Bitmap)

    private companion object {
        const val SLOWDOWN = 8.0

        /** 공개 몇 초 전부터 그리나(결과가 온 뒤 톡톡 · 모음 동안 — 공개 전 데움이 이때 무대를 세운다). 프레임 이름의 t 는 공개 기준. */
        const val LEAD = 2.0
    }

    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val outDir: File = (InstrumentationRegistry.getArguments().getString("additionalTestOutputDir")?.let { File(it, "gacha-reveal") }
        ?: File(instrumentation.targetContext.filesDir, "gacha-reveal")).apply { deleteRecursively(); mkdirs() }

    private fun note(line: String) = println("AINGCHECK-R8B-REVEAL api=${Build.VERSION.SDK_INT} $line")

    /** 칸 요(°)를 0…360 으로 접어 정면에서 벗어난 각(0 = 정면, 180 = 등). */
    private fun awayFromFront(yaw: Int): Int = (((yaw % 360) + 360) % 360).let { if (it > 180) 360 - it else it }

    @Test
    fun 구운_황금_아잉이_첫_공개는_한_바퀴_돌아_등이_보인다() {
        val gold = GachaRevealOutcome("aing_gold", "황금 아잉이", GachaRevealKind.Gold, shardCount = 23)
        var clock = 100.0
        val d = GachaMachineDirector(clock = { clock }, scope = CoroutineScope(Dispatchers.Unconfined + Job()), seedSource = { 0x5EED_CAFEuL }, random = { 0.9 })
        d.autoSchedule = false
        val env = GachaMachineEnv(
            balance = 120, cost = 50, shards = 23, art = GachaMachineArt.Vector, teaseChance = 0.0, haptics = GachaMachineHaptics.None, pull = { gold },
        )
        d.update(env)
        d.touched(clock)
        d.autoTurn(clock)
        clock += d.autoTurnDuration
        d.advance(clock)
        val ds = requireNotNull(d.dropStart) { "결과가 안 왔다" }
        clock = ds + d.drop.total + 0.05
        d.advance(clock)
        repeat(3) { d.press(clock); clock += 0.2 }
        val revealAt = requireNotNull(d.burstTime) { "세 번째 톡에 터지지 않았다" } + d.goldBuild
        assertEquals(1, d.revealSerial, "첫 결과의 공개 번호")

        val handle = StageHandle()
        // AingShell 과 같은 배선(id · 크기 · revealKey = 공개 번호) + 진단 창 하나. 무대 시계만 [SLOWDOWN] 배 느리게 민다 — 창 복사가 한 장에
        // 0.3~0.5초(부하 걸린 에뮬레이터)라 실시간 0.6초 한 바퀴는 두세 장밖에 못 찍는다(실시간 실행 기록: 요 4° → 90° → 7°, logs/device-2).
        val origin = System.nanoTime() / 1e9
        val slow = StageClock { origin + (System.nanoTime() / 1e9 - origin) / SLOWDOWN }
        val preview = LiveCharacterPreview { id, size, m, serial -> AingStage(id, null, m, artSize = size, revealKey = serial, clock = slow, handle = handle.takeIf { serial > 0 }) }
        val shown = AtomicLong(0L)
        val shots = ArrayList<Shot>()
        var window: Window? = null
        ActivityScenario.launch(ComponentActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                window = activity.window
                activity.setContent {
                    AingTheme(dark = true) {
                        CompositionLocalProvider(LocalLiveCharacterPreview provides preview) {
                            var now by remember { mutableDoubleStateOf(revealAt - LEAD) }
                            LaunchedEffect(Unit) {
                                val start = System.nanoTime()
                                shown.set(start)
                                while (true) {
                                    withFrameNanos { }
                                    now = revealAt - LEAD + (System.nanoTime() - start) / 1e9
                                }
                            }
                            Box(Modifier.fillMaxSize().background(Color.Black)) {
                                GachaMachineScaler {
                                    GachaMachineStage(
                                        d, env, GachaMachineTheme.of(true), remember { GachaCapsuleSprites(GachaMachineArt.Vector) }, now,
                                        portrait = { null }, ruby = null,
                                    )
                                }
                            }
                        }
                    }
                }
            }
            // 창 PixelCopy(UiAutomation 스크린숏은 한 장에 0.4초 넘게 걸려 0.6초 한 바퀴를 놓친다). 요는 복사 앞뒤로 무대 창에서 읽는다.
            val win = requireNotNull(window)
            val main = Handler(Looper.getMainLooper())
            fun yawNow(): Int? = (handle.lastFrame as? CharacterFrame.Impostor)?.frame?.placement?.cell?.yawDeg
            val deadline = System.nanoTime() + 25_000_000_000L
            var spinEndAt = Long.MAX_VALUE
            var fallbackKept = 0
            while (System.nanoTime() < minOf(deadline, spinEndAt)) {
                val start = shown.get()
                val view = win.decorView
                if (start == 0L || view.width <= 0) { Thread.sleep(16); continue }
                val live = handle.director != null
                // 살아 있는 무대가 서기 전(초상 무대)은 세 장만 남긴다.
                if (!live && fallbackKept >= 3) { Thread.sleep(200); continue }
                val yaw0 = yawNow()
                val full = Bitmap.createBitmap(view.width, view.height, Bitmap.Config.ARGB_8888)
                val done = CountDownLatch(1)
                var ok = false
                PixelCopy.request(win, full, { r -> ok = r == PixelCopy.SUCCESS; done.countDown() }, main)
                done.await(3, TimeUnit.SECONDS)
                val yaw1 = yawNow()
                val t = (System.nanoTime() - start) / 1e9 - LEAD
                if (!ok) { full.recycle(); continue }
                // 화면 가운데 정사각(무대 공개 자리)만 반으로 줄여 남긴다.
                val side = minOf(full.width, full.height)
                val top = ((full.height - side) / 2).coerceAtLeast(0)
                val crop = Bitmap.createBitmap(full, 0, top, side, side)
                shots += Shot(t, yaw0, yaw1, Bitmap.createScaledBitmap(crop, side / 2, side / 2, true))
                crop.recycle()
                full.recycle()
                if (!live) fallbackKept++
                // 등을 한 번 지나 정면으로 돌아오면 1초 더 찍고 끝낸다.
                if (spinEndAt == Long.MAX_VALUE && shots.any { (it.yawBefore?.let(::awayFromFront) ?: 0) >= 120 } && (yaw1?.let(::awayFromFront) ?: 0) < 20) {
                    spinEndAt = System.nanoTime() + 1_000_000_000L
                }
                if (shots.size >= 90) break
            }
        }
        val lines = shots.mapIndexed { i, s ->
            val name = "%03d-t%05d-yaw%s-%s.png".format(i, (s.t * 1000).toInt(), s.yawBefore?.toString() ?: "na", s.yawAfter?.toString() ?: "na")
            File(outDir, name).outputStream().use { s.image.compress(Bitmap.CompressFormat.PNG, 100, it) }
            "$name away=${s.yawBefore?.let(::awayFromFront)}..${s.yawAfter?.let(::awayFromFront)}"
        }
        File(outDir, "frames.txt").writeText(lines.joinToString("\n") + "\n")
        note("mode=${handle.mode} id=${handle.characterId} serial=${d.revealSerial} shots=${shots.size} dir=${outDir.absolutePath}")
        lines.forEach { note(it) }
        assertEquals("aing_gold", handle.characterId, "공개 자리가 살아 있는 미리보기를 부르지 않았다")
        assertTrue(handle.mode is StageMode.Live, "황금 아잉이가 구운 무대로 서지 않았다: ${handle.mode}")
        // 복사 앞뒤 요가 둘 다 정면에서 120° 넘게 돌아 있던 장 = 등이 찍힌 장.
        val back = shots.filter { s -> listOf(s.yawBefore, s.yawAfter).all { it != null && awayFromFront(it) >= 120 } }
        note("back=${back.size} first=${back.firstOrNull()?.let { "t=${it.t} yaw=${it.yawBefore}..${it.yawAfter}" }}")
        assertTrue(back.isNotEmpty(), "한 바퀴 동안 등(정면에서 120° 이상)이 보이는 프레임을 못 찍었다 — ${shots.size}장")
    }
}
