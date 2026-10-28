// 원본: 없음 (설계 F §6 T7 — T3 부분집합 20장을 에뮬레이터(-no-window)의 Android Canvas 경로로 · G §2-6 F-1 Android(HWUI) 원근 그리기)
package com.yehsung.aingcheck.character

import android.graphics.HardwareRenderer
import android.graphics.PixelFormat
import android.graphics.RenderNode
import android.hardware.HardwareBuffer
import android.media.ImageReader
import android.os.Build
import com.yehsung.aingcheck.character.bake.BakeFiles
import com.yehsung.aingcheck.character.bake.BakeLibrary
import com.yehsung.aingcheck.character.bake.PixelRect
import com.yehsung.aingcheck.character.math.Homography
import com.yehsung.aingcheck.character.math.Vec2
import com.yehsung.aingcheck.character.parity.GoldenClass
import com.yehsung.aingcheck.character.parity.GoldenReplay
import com.yehsung.aingcheck.character.parity.GoldenSet
import com.yehsung.aingcheck.character.parity.ParityRules
import com.yehsung.aingcheck.character.render.AndroidQuadCanvas
import com.yehsung.aingcheck.character.render.BakeImageStore
import com.yehsung.aingcheck.character.render.CpuRaster
import com.yehsung.aingcheck.character.render.DrawableImage
import com.yehsung.aingcheck.character.render.ImageMetrics
import com.yehsung.aingcheck.character.render.PlatformRaster
import com.yehsung.aingcheck.character.render.QuadCanvas
import com.yehsung.aingcheck.character.render.RasterFactory
import com.yehsung.aingcheck.character.render.RasterSurface
import com.yehsung.aingcheck.character.render.RgbaImage
import com.yehsung.aingcheck.character.render.asPremultiplied
import java.util.concurrent.TimeUnit
import kotlin.math.floor
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * T7: 골든 20장(깨끗한 장 — 세 마감 · 네 무리 · 감은 눈 포함)을 기기에서 디코드(BitmapFactory, inPremultiplied=false → premultiplied Bitmap 에
 * copyPixelsFromBuffer, G §8-12)하고 두 길로 그려 T3 와 **같은 규칙**([ParityRules])으로 판정한다:
 *  ① 소프트웨어 Canvas(Bitmap) ② HWUI(RenderNode → HardwareRenderer → ImageReader, 화면 창 없음 — 앱 미리보기가 실제로 타는 GPU 길).
 * T7-L: Android 기본 묶음이 **실제로 싣는 L 단**(쉬는 행 57칸 · 감은 눈 패치)을 280×340 몸 크기로 그려 쉬는 행 골든 부분집합과 같은 규칙으로 맞댄다.
 * F-1(Android): 체커보드 원근 그리기를 두 길로 해 순수 Kotlin CPU 워프 기준과 맞댄다.
 * 자원은 시험 APK 의 Java 자원(aing-bake/ · 후광 PNG — 조정자 패치의 androidDeviceTest 자원 뿌리).
 */
class CharacterDeviceTest {
    private object ApkFiles : BakeFiles {
        private val loader = CharacterDeviceTest::class.java.classLoader!!
        override fun read(path: String): ByteArray? = loader.getResourceAsStream("aing-bake/$path")?.use { it.readBytes() }
        override fun readHalo(fileName: String): ByteArray? = loader.getResourceAsStream(fileName)?.use { it.readBytes() }
    }

    private fun note(line: String) = println("AINGCHECK-W5A-T7 api=${Build.VERSION.SDK_INT} $line")

    /** HWUI 래스터: RenderNode 에 그대로 기록하고 HardwareRenderer 로 ImageReader 표면에 그린다(창 없음). */
    private class HwuiRaster : RasterFactory by PlatformRaster {
        override fun newSurface(width: Int, height: Int): RasterSurface = HwuiSurface(width, height)
    }

    private class HwuiSurface(override val width: Int, override val height: Int) : RasterSurface {
        private val ops = ArrayList<(QuadCanvas) -> Unit>()
        override fun clear() { ops.clear() }
        override fun drawImageQuad(image: DrawableImage, srcRect: PixelRect, srcToDst: Homography, linear: Boolean, alpha: Float) {
            ops += { it.drawImageQuad(image, srcRect, srcToDst, linear, alpha) }
        }
        override fun fillQuad(quad: List<Vec2>, color: Int, additive: Boolean) { ops += { it.fillQuad(quad, color, additive) } }
        override fun close() {}

        override fun readPixels(): RgbaImage {
            // GPU 가 그리고(COLOR_OUTPUT) CPU 가 읽는다(CPU_READ_OFTEN — 없으면 getPlanes 가 'lock buffer failed' 로 멈춘다, 실측).
            val reader = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, 2, HardwareBuffer.USAGE_GPU_COLOR_OUTPUT or HardwareBuffer.USAGE_CPU_READ_OFTEN)
            val node = RenderNode("w5a-t7")
            node.setPosition(0, 0, width, height)
            val rc = node.beginRecording(width, height)
            try {
                val quad = AndroidQuadCanvas(rc)
                for (op in ops) op(quad)
            } finally {
                node.endRecording()
            }
            val renderer = HardwareRenderer()
            try {
                renderer.setSurface(reader.surface)
                renderer.setContentRoot(node)
                renderer.isOpaque = false
                renderer.createRenderRequest().setWaitForPresent(true).syncAndDraw()
                var image = reader.acquireLatestImage()
                val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(5)
                while (image == null && System.nanoTime() < deadline) { Thread.sleep(10); image = reader.acquireLatestImage() }
                checkNotNull(image) { "HWUI 가 ImageReader 에 그리지 않았다" }
                image.use { img ->
                    val plane = img.planes[0]
                    val buf = plane.buffer
                    val out = ByteArray(width * height * 4)
                    for (y in 0 until height) {
                        buf.position(y * plane.rowStride)
                        buf.get(out, y * width * 4, width * 4)
                    }
                    return RgbaImage(width, height, out, true)
                }
            } finally {
                renderer.destroy()
                reader.close()
            }
        }
    }

    private val goldens by lazy { GoldenSet.parse(ApkFiles.read("golden/golden.json")!!.decodeToString()) }
    private val library by lazy { BakeLibrary.load(ApkFiles) }

    private fun run(raster: RasterFactory, label: String, tier: String = "S", subset: Set<Int> = GoldenReplay.T7_SUBSET) {
        val chosen = goldens.entries.filter { it.index in subset }
        assertEquals(subset.size, chosen.size)
        val problems = ArrayList<String>()
        var worstIou = 1.0; var worstMean = 0.0; var minRatio = Double.MAX_VALUE
        for ((folder, entries) in chosen.groupBy { it.finishFolder }) {
            val finish = library.finish(BakeLibrary.FOLDER_IDS.getValue(folder))!!
            val store = BakeImageStore(finish, ApkFiles, PlatformRaster, pageCapacity = 2)
            try {
                for (g in entries) {
                    val golden = PlatformRaster.decodeRaw(ApkFiles.read("golden/${g.file}")!!).asPremultiplied()
                    val v = GoldenReplay.verdict(library, raster, store, g, golden, tier)
                    if (v.tier != tier) problems += "${g.id}: $tier 단이 아니라 ${v.tier} 단으로 그렸다"
                    if (v.cls != GoldenClass.clean) problems += "${g.id}: 부분집합은 깨끗한 장이어야 한다(${v.cls})"
                    problems += v.problems().map { "${g.id} [${v.band}] $it" }
                    worstIou = minOf(worstIou, v.composite.iou); worstMean = maxOf(worstMean, v.composite.mean); minRatio = minOf(minRatio, v.negativeRatio)
                    note("$label ${g.id} band=${v.band} IoU=${"%.4f".format(v.composite.iou)} mean=${"%.2f".format(v.composite.mean)} negRatio=${"%.2f".format(v.negativeRatio)}")
                }
            } finally {
                store.close()
            }
        }
        note("$label ${chosen.size}장 최저 IoU=${"%.4f".format(worstIou)} 최대 평균=${"%.2f".format(worstMean)} 음성 대조 최소 비=${"%.2f".format(minRatio)} 문제=${problems.size}")
        assertTrue(problems.isEmpty(), "T7($label) 실패 ${problems.size}건:\n" + problems.joinToString("\n"))
    }

    @Test
    fun T7_소프트웨어_Canvas_20장() = run(PlatformRaster, "software")

    @Test
    fun T7_HWUI_20장() = run(HwuiRaster(), "hwui")

    @Test
    fun T7_L단_소프트웨어_Canvas() = run(PlatformRaster, "L-software", "L", GoldenReplay.T7_L_SUBSET)

    @Test
    fun T7_L단_HWUI() = run(HwuiRaster(), "L-hwui", "L", GoldenReplay.T7_L_SUBSET)

    private fun checker(): RgbaImage {
        val n = 64
        val px = ByteArray(n * n * 4)
        for (y in 2 until n - 2) for (x in 2 until n - 2) {
            val o = (y * n + x) * 4
            val on = ((x / 8) + (y / 8)) % 2 == 0
            val q = (if (x < n / 2) 0 else 1) + (if (y < n / 2) 0 else 2)
            val base = intArrayOf(0xE03030, 0x30C030, 0x3030E0, 0xE0C030)[q]
            val c = if (on) base else 0x202020
            px[o] = (c shr 16).toByte(); px[o + 1] = (c shr 8).toByte(); px[o + 2] = c.toByte(); px[o + 3] = 0xFF.toByte()
        }
        return RgbaImage(n, n, px, true)
    }

    private fun drawChecker(raster: RasterFactory, h: Homography): RgbaImage {
        val s = raster.newSurface(280, 340)
        s.clear()
        val img = raster.imageFromPremultiplied(checker())
        s.drawImageQuad(img, PixelRect(0, 0, 64, 64), h)
        val out = s.readPixels()
        s.close()
        return out
    }

    @Test
    fun F1_안드로이드_원근_그리기_두_길() {
        val corners = listOf(Vec2(0.0, 0.0), Vec2(64.0, 0.0), Vec2(64.0, 64.0), Vec2(0.0, 64.0))
        val quad = listOf(Vec2(70.3, 40.6), Vec2(190.2, 52.1), Vec2(236.8, 287.4), Vec2(30.9, 262.2))
        val h = Homography.fromQuads(corners, quad)!!
        val cpu = drawChecker(CpuRaster(PlatformRaster), h)
        for ((label, raster) in listOf("software" to PlatformRaster, "hwui" to HwuiRaster())) {
            val got = drawChecker(raster, h)
            val d = ImageMetrics.diff(got, cpu)
            note("F-1 $label IoU=${"%.5f".format(d.iou)} mean=${"%.3f".format(d.mean)} big=${"%.4f".format(d.big)}")
            assertTrue(d.iou >= 0.995 && d.mean <= 2.0, "F-1 $label: 원근 그리기가 기준과 다르다 $d")
            // 칸 중심 하나의 자리 · 색(아핀이면 수 px 밀린다).
            val c = h.map(Vec2(52.0, 52.0))
            val o = (floor(c.y).toInt() * 280 + floor(c.x).toInt()) * 4
            val rgb = ((got.px[o].toInt() and 0xFF) shl 16) or ((got.px[o + 1].toInt() and 0xFF) shl 8) or (got.px[o + 2].toInt() and 0xFF)
            assertEquals(0xE0C030, rgb, "F-1 $label 오른쪽 아래 사분면 칸 중심")
        }
        // 음성 대조: 아핀(세 점)으로 그리면 문턱을 넘는다.
        val affine = Homography.fromQuads(corners, listOf(quad[0], quad[1], Vec2(quad[1].x + quad[3].x - quad[0].x, quad[1].y + quad[3].y - quad[0].y), quad[3]))!!
        val wrong = ImageMetrics.diff(drawChecker(PlatformRaster, affine), cpu)
        assertTrue(wrong.iou < 0.98 || wrong.mean > 8.0, "아핀 그리기가 문턱 안이다 $wrong")
    }
}
