// 원본: 없음 (W5-c 완료 ①·②·③ 기기 몫 — 설치된 APK 의 구운 묶음 예산 · T7 부분집합을 무대 길(앱 자산 → 감독 → drawStageFrame → HWUI)로 · 기기 위 실제 탭 · G §8-18 1 맥 렌더 비교 그림)
package com.yehsung.aingcheck.android.screens.stage

import android.graphics.Bitmap
import android.graphics.HardwareRenderer
import android.graphics.PixelFormat
import android.graphics.RenderNode
import android.hardware.HardwareBuffer
import android.media.ImageReader
import android.os.Build
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.graphics.drawscope.CanvasDrawScope
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.test.click
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.LayoutDirection
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.yehsung.aingcheck.android.BuildConfig
import com.yehsung.aingcheck.character.bake.BakeCells
import com.yehsung.aingcheck.character.bake.BakeLibrary
import com.yehsung.aingcheck.character.math.Vec2
import com.yehsung.aingcheck.character.parity.Golden
import com.yehsung.aingcheck.character.parity.GoldenClass
import com.yehsung.aingcheck.character.parity.GoldenReplay
import com.yehsung.aingcheck.character.parity.GoldenSet
import com.yehsung.aingcheck.character.parity.ParityRules
import com.yehsung.aingcheck.character.player.CharacterFrame
import com.yehsung.aingcheck.character.pose.PoseImpostor
import com.yehsung.aingcheck.character.render.ImageMetrics
import com.yehsung.aingcheck.character.render.PlatformRaster
import com.yehsung.aingcheck.character.render.RgbaImage
import com.yehsung.aingcheck.character.render.asPremultiplied
import com.yehsung.aingcheck.ui.components.CharacterMood
import com.yehsung.aingcheck.ui.theme.AingTheme
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.nio.ByteBuffer
import java.util.concurrent.TimeUnit
import java.util.zip.ZipFile
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.random.Random
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * 기기(에뮬레이터 -no-window) 위 살아 있는 미리보기.
 *  ① 설치된 APK 의 `assets/aing-bake/` 아래 항목을 zip 목록으로 잰다: L 단 ≤ 4MB · 묶음 ≤ 설정 예산(BuildConfig.STAGE_BUNDLE_BUDGET ← config.json) ·
 *     S 는 스핀 행(페이지 셋 + cells-S)만 · U 단 · 골든 0.
 *  ② T7 부분집합: **앱 자산**(AssetBakeFiles — 시험 자원이 아니다)으로 선 감독이 탭 · 공개 · 깜빡임으로 자세를 만들고, 앱 Canvas 와 같은
 *     `drawStageFrame` 이 Compose 캔버스 → HWUI(RenderNode → HardwareRenderer → ImageReader, 창 없음) · 소프트웨어 Bitmap 두 길로 그린다.
 *     맥 골든과 T3 와 같은 규칙(ParityRules — 무리 문턱 · 음성 대조)으로 맞댄다. 부분집합 = 무대가 쓰는 리액션(idle · blink · hit — 공개 한 바퀴는 ④) 중
 *     정면(무대는 돌아보지 않는다) · 참조 칸 기울기 13°(L 쉬는 행이 그리는 기울기) · 입자/격자 거칠음 아닌 장 — 13장(골든이 바뀌면 빨강).
 *  ③ 실제 화면: AingStage 를 띄워 몸을 두드리면 hit 가 걸리고 그림이 바뀐다.
 * 비교 그림 재료(G §8-18 1): 무대 길로 그린 그림을 앱 files/stage-compare/ 에 남긴다(run-as 로 꺼내 맥 골든 옆에 붙인다 — 저장소 밖).
 */
@RunWith(AndroidJUnit4::class)
class StageDeviceTest {
    @get:Rule
    val compose = createComposeRule()

    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val target = instrumentation.targetContext
    private val outDir = File(target.filesDir, "stage-compare").apply { mkdirs() }

    private fun note(line: String) = println("AINGCHECK-W5C-DEVICE api=${Build.VERSION.SDK_INT} $line")

    /** 시험 APK 자원(골든 · S 칸 표 — 판정 무리를 가르는 Swift 참조 칸). 무대 자산은 여기서 읽지 않는다. */
    private fun testResource(path: String): ByteArray =
        requireNotNull(StageDeviceTest::class.java.classLoader!!.getResourceAsStream("aing-bake/$path")) { "시험 자원 없음: $path" }.use { it.readBytes() }

    private val goldens by lazy { GoldenSet.parse(testResource("golden/golden.json").decodeToString()) }
    private val appAssets by lazy { StageAssets(AssetBakeFiles(target.assets)) }
    private val library: BakeLibrary by lazy { requireNotNull(appAssets.libraryOrNull()) { "앱 자산 묶음을 못 읽었다: ${appAssets.failureReason}" } }

    // ---------------------------------------------------------------- ① 설치된 APK

    @Test
    fun 설치된_APK_의_구운_묶음은_L단_4MB_묶음은_설정_예산_이하() {
        val entries = ZipFile(target.applicationInfo.sourceDir).use { z ->
            z.entries().asSequence().filter { it.name.startsWith("assets/aing-bake/") && !it.isDirectory }.associate { it.name.removePrefix("assets/aing-bake/") to it.size }
        }
        val lTier = entries.filterKeys { Regex("""^(aing|aing-gold|aing-rainbow)/(L-[^/]+\.webp|cells-L\.json)$""").matches(it) }
        val spin = entries.filterKeys { Regex("""^(aing|aing-gold|aing-rainbow)/(S-spin-[^/]+\.webp|cells-S\.json)$""").matches(it) }
        val stray = entries.keys.filter { Regex("""(^|/)(S|U)-[^/]+\.webp$|cells-(S|U)\.json$|^golden/""").containsMatchIn(it) && it !in spin }
        val total = entries.values.sum()
        val budget = BuildConfig.STAGE_BUNDLE_BUDGET.toLong()
        note("apk aing-bake files=${entries.size} L=${lTier.values.sum()} (${lTier.size}) spin=${spin.values.sum()} (${spin.size}) total=$total budget=$budget halo=${entries.keys.count { it.startsWith("halo/") }} stray=${stray.size}")
        assertEquals(9, lTier.size)
        assertEquals(12, spin.size, "S 스핀 = 마감 셋 × (S-spin 페이지 셋 + cells-S)")
        assertTrue(lTier.values.sum() <= 4_000_000, "L 단 ≤ 4MB: ${lTier.values.sum()}")
        assertTrue(total <= budget, "묶음 ≤ 예산 $budget: $total")
        assertEquals(emptyList(), stray)
        assertEquals(72, entries.keys.count { it.startsWith("halo/") })
        assertEquals(setOf("aing", "aing_gold", "aing_rainbow"), library.bakedIds)
    }

    // ---------------------------------------------------------------- ② T7 부분집합(무대 길)

    /** 무대 부분집합 규칙(위 ②). 결과 번호 목록을 잠근다. */
    private fun stageSubset(): List<Golden> = goldens.entries.filter {
        it.reaction in setOf("idle", "blink", "hit") && it.facingDeg == 0.0 && it.referenceCellId.endsWith(":13.0")
    }

    private val referenceCells = HashMap<String, BakeCells>()
    private fun referenceCell(g: Golden) = referenceCells.getOrPut(g.finishFolder) {
        BakeCells.decode(testResource("${g.finishFolder}/cells-S.json").decodeToString())
    }.cell(g.referenceCellId) ?: error("참조 칸 ${g.referenceCellId}")

    /** 무대 감독으로 골든 시각의 자세를 만든다(GoldenReplay 와 같은 시각 순서 — 리액션은 무대 입구 탭 · 공개 · 깜빡임으로). */
    private fun replay(g: Golden, store: StageStore): Pair<StageDirector, Double> {
        val d = StageDirector(library, store.finish, 0.0, Random(0))
        val attach = 10.0
        d.player.swapCharacter(store.finish.characterId, attach)
        val t0 = attach + GoldenReplay.roundHalfAway(g.swayPhaseS * GoldenReplay.HZ) / GoldenReplay.HZ.toDouble()
        val now = t0 + g.sampleIndex / GoldenReplay.HZ.toDouble()
        d.player.setFacing(if (g.facingDeg > 0) 1 else if (g.facingDeg < 0) -1 else 0, moving = false, now = t0)
        when (g.reaction) {
            "idle" -> {}
            "blink" -> check(d.player.blink(now - 0.05)) { "깜빡임 거절" }
            "hit" -> {
                val f0 = d.frame(t0, StageFraming.FRAME_WIDTH, StageFraming.FRAME_HEIGHT)
                val outcome = d.tap(Vec2(137.5, 137.5), f0, StagePolicy.TAP_MARGIN_POINTS * 2, store, t0)
                check(outcome == TapOutcome.hit) { "${g.id}: 탭이 hit 를 걸지 않았다($outcome)" }
            }
            StagePolicy.REVEAL_REACTION -> check(d.reveal(t0)) { "${g.id}: 공개가 한 바퀴를 걸지 않았다" }
            else -> error("무대 리액션이 아니다: ${g.reaction}")
        }
        return d to now
    }

    private fun RgbaImage.toBitmap(): Bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888).also {
        it.isPremultiplied = true
        it.copyPixelsFromBuffer(ByteBuffer.wrap(px))
    }

    private fun Bitmap.toRgba(): RgbaImage {
        val buf = ByteBuffer.allocate(width * height * 4)
        copyPixelsToBuffer(buf)
        return RgbaImage(width, height, buf.array(), true)
    }

    /** 소프트웨어: Compose ImageBitmap(= android Bitmap 캔버스) 위에 drawStageFrame. */
    private fun renderSoftware(frame: CharacterFrame, store: StageStore): RgbaImage = renderSoftwareSized(frame, store, 280, 340)

    private fun renderSoftwareSized(frame: CharacterFrame, store: StageStore, w: Int, h: Int): RgbaImage {
        val img = ImageBitmap(w, h)
        CanvasDrawScope().draw(Density(1f), LayoutDirection.Ltr, androidx.compose.ui.graphics.Canvas(img), Size(w.toFloat(), h.toFloat())) {
            drawStageFrame(frame, 0.0, 0.0, store)
        }
        return img.asAndroidBitmap().toRgba()
    }

    /** HWUI: RenderNode 기록 캔버스를 Compose 캔버스로 감싸 drawStageFrame → HardwareRenderer → ImageReader(창 없음 — 앱 화면이 타는 GPU 길). */
    private fun renderHwui(frame: CharacterFrame, store: StageStore): RgbaImage = renderHwuiSized(frame, store, 280, 340)

    private fun renderHwuiSized(frame: CharacterFrame, store: StageStore, w: Int, h: Int): RgbaImage {
        val reader = ImageReader.newInstance(w, h, PixelFormat.RGBA_8888, 2, HardwareBuffer.USAGE_GPU_COLOR_OUTPUT or HardwareBuffer.USAGE_CPU_READ_OFTEN)
        val node = RenderNode("w5c-stage")
        node.setPosition(0, 0, w, h)
        val rc = node.beginRecording(w, h)
        try {
            CanvasDrawScope().draw(Density(1f), LayoutDirection.Ltr, androidx.compose.ui.graphics.Canvas(rc), Size(w.toFloat(), h.toFloat())) {
                drawStageFrame(frame, 0.0, 0.0, store)
            }
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
                val out = ByteArray(w * h * 4)
                for (y in 0 until h) { buf.position(y * plane.rowStride); buf.get(out, y * w * 4, w * 4) }
                return RgbaImage(w, h, out, true)
            }
        } finally {
            renderer.destroy()
            reader.close()
        }
    }

    private fun save(img: RgbaImage, name: String) {
        File(outDir, name).outputStream().use { img.toBitmap().compress(Bitmap.CompressFormat.PNG, 100, it) }
    }

    private fun verdict(g: Golden, label: String, render: (CharacterFrame, StageStore) -> RgbaImage, store: StageStore): ParityRules.Verdict {
        val (d, now) = replay(g, store)
        val frame = d.frame(now, StageFraming.FRAME_WIDTH, StageFraming.FRAME_HEIGHT) as CharacterFrame.Impostor
        val f = frame.frame
        val golden = PlatformRaster.decodeRaw(testResource("golden/${g.file}")).asPremultiplied()
        val ours = render(frame, store)
        val oursBody = render(CharacterFrame.Impostor(f.copy(halo = null)), store)
        val wrong = GoldenReplay.wrongCell(f.finish, f)
        val body = d.player.chain(now).character
        val plane = PoseImpostor.Plane(PoseImpostor.limbDepth(library.camera), f.tier.viewportWidth.toDouble(), f.tier.viewportHeight.toDouble())
        val wp = PoseImpostor.placeWith(wrong, body, library.camera, f.finish.bake.quadHalfUnits, f.viewportWidth, f.viewportHeight, plane)
            ?: error("틀린 칸 정합 실패 ${g.id}")
        val wrongImg = render(CharacterFrame.Impostor(f.copy(placement = wp)), store)
        val wrongBody = render(CharacterFrame.Impostor(f.copy(placement = wp, halo = null)), store)
        if (label == "hwui") save(ours, "${g.id}.png")
        return ParityRules.Verdict(
            golden = g,
            cls = ParityRules.classify(g, golden),
            band = ParityRules.band(g, referenceCell(g)),
            tier = f.tier.name,
            cellId = f.placement.cell.id,
            composite = ImageMetrics.diff(ours, golden),
            bodyMean = ParityRules.bodyRegionMean(ours, golden, oursBody),
            wrongCellId = wrong.id,
            wrongComposite = ImageMetrics.diff(wrongImg, golden),
            wrongBodyMean = ParityRules.bodyRegionMean(wrongImg, golden, wrongBody),
        )
    }

    private fun runSubset(label: String, render: (CharacterFrame, StageStore) -> RgbaImage, all: Boolean = false) {
        val chosen = if (all) goldens.entries.filter { it.reaction in setOf("idle", "blink", "hit") } else stageSubset()
        if (!all) assertEquals(
            listOf(3, 72, 75, 78, 82, 85, 154, 157, 158, 164, 233, 236, 238),
            chosen.map { it.index },
            "무대 부분집합(골든이 바뀌었다 — 규칙을 다시 본다)",
        )
        val problems = ArrayList<String>()
        val lines = ArrayList<String>()
        var worstIou = 1.0; var worstMean = 0.0; var minRatio = Double.MAX_VALUE
        for ((folder, entries) in chosen.groupBy { it.finishFolder }) {
            val store = requireNotNull(appAssets.acquire(library.finish(BakeLibrary.FOLDER_IDS.getValue(folder))!!)) { "칸 굽기 실패: ${appAssets.failureReason}" }
            try {
                for (g in entries) {
                    val v = verdict(g, label, render, store)
                    lines += "${g.id}\t${v.cls}\t${v.band}\t${v.cellId}\t${"%.4f".format(v.composite.iou)}\t${"%.2f".format(v.composite.mean)}\t${"%.2f".format(v.bodyMean)}\t${"%.2f".format(v.negativeRatio)}"
                    if (all) continue
                    if (v.tier != "L") problems += "${g.id}: L 단이 아니라 ${v.tier}"
                    if (v.cls == GoldenClass.particles || v.cls == GoldenClass.gridCoarse) problems += "${g.id}: 부분집합에 ${v.cls}"
                    problems += v.problems().map { "${g.id} [${v.band}/${v.cls}] $it" }
                    worstIou = minOf(worstIou, v.composite.iou); worstMean = maxOf(worstMean, v.composite.mean); minRatio = minOf(minRatio, v.negativeRatio)
                    note("$label ${g.id} cls=${v.cls} band=${v.band} cell=${v.cellId} IoU=${"%.4f".format(v.composite.iou)} mean=${"%.2f".format(v.composite.mean)} body=${"%.2f".format(v.bodyMean)} negRatio=${"%.2f".format(v.negativeRatio)}")
                }
            } finally {
                appAssets.release(store)
            }
        }
        File(outDir, "verdicts-$label${if (all) "-all" else ""}.tsv").writeText("id\tclass\tband\tcell\tiou\tmean\tbodyMean\tnegRatio\n" + lines.joinToString("\n") + "\n")
        if (all) return
        note("$label ${chosen.size}장 최저 IoU=${"%.4f".format(worstIou)} 최대 평균=${"%.2f".format(worstMean)} 음성 대조 최소 비=${"%.2f".format(minRatio)} 문제=${problems.size}")
        assertTrue(problems.isEmpty(), "T7 무대($label) 실패 ${problems.size}건:\n" + problems.joinToString("\n"))
    }

    @Test
    fun T7_무대_길_HWUI_13장() = runSubset("hwui", ::renderHwui)

    @Test
    fun T7_무대_길_소프트웨어_13장() = runSubset("software", ::renderSoftware)

    /** 비교 그림 재료: 무대 리액션 셋의 골든 42장(마감 셋 × idle 6 · blink 2 · hit 6) 전부를 무대 길(HWUI)로(판정 없음 — 수치는 verdicts-hwui-all.tsv). */
    @Test
    fun 비교_그림_재료_42장() = runSubset("hwui", ::renderHwui, all = true)

    // ---------------------------------------------------------------- ③ 실제 화면

    // ---------------------------------------------------------------- ④ 공개 한 바퀴(공개 화면 크기)

    /**
     * 공개 한 바퀴(G §8-19 #6② · §8-20 #5): 정면 골든 6장(마감 셋 × 2)을 무대 감독(공개 → 한 바퀴 · S 스핀 칸 데움)으로 재생해 **공개 화면 크기**
     * — L 단 뷰포트 420×510(틀 1.5배, 무대가 L 단을 고르는 크기) — 로 HWUI 에 그리고, 넓이 평균으로 280×340 에 줄여 맥 골든과 T3 규칙(골든 참조 칸의
     * 무리 문턱)으로 맞댄다. 문턱에 못 미치면 S 스핀을 키워 쓰는 길을 버리고 L 단 스핀 행을 굽는다(§8-20 #5). 그림은 files/stage-compare/reveal-*.png.
     */
    @Test
    fun 공개_한_바퀴를_공개_화면_크기로_그려_맥_골든과_맞댄다() {
        val chosen = goldens.entries.filter { it.reaction == StagePolicy.REVEAL_REACTION && it.facingDeg == 0.0 }
        assertEquals(listOf(8, 11, 87, 90, 166, 169), chosen.map { it.index }, "공개 한 바퀴 정면 골든")
        val w = (StageFraming.FRAME_WIDTH * 1.5).toInt()
        val h = (StageFraming.FRAME_HEIGHT * 1.5).toInt()
        val lines = ArrayList<String>()
        val problems = ArrayList<String>()
        var spinFrames = 0
        // 앱 화면 길(HWUI). API 26 에뮬레이터는 GPU 읽기 ImageReader 조합을 받지 않아(Format usage combination is not supported) 소프트웨어 길로 —
        // 거기서 재는 것은 48MB 힙에서 L 데움 + 스핀 데움(페이지 하나씩)이 버티는가다.
        val render: (CharacterFrame, StageStore) -> RgbaImage =
            if (Build.VERSION.SDK_INT >= 29) { f, s -> renderHwuiSized(f, s, w, h) } else { f, s -> renderSoftwareSized(f, s, w, h) }
        for ((folder, entries) in chosen.groupBy { it.finishFolder }) {
            val store = requireNotNull(appAssets.acquire(library.finish(BakeLibrary.FOLDER_IDS.getValue(folder))!!)) { "칸 굽기 실패: ${appAssets.failureReason}" }
            try {
                for (g in entries) {
                    val (d, now) = replay(g, store)
                    assertTrue(store.prewarmSpin(d.spinPrewarmCells()), "${g.id}: 스핀 데움 실패")
                    val frame = d.frame(now, w.toDouble(), h.toDouble()) as CharacterFrame.Impostor
                    if (frame.frame.tier.name == StagePolicy.SPIN_TIER) spinFrames++
                    val big = render(frame, store)
                    val ours = big.areaDownsample(280, 340)
                    val oursBody = render(CharacterFrame.Impostor(frame.frame.copy(halo = null)), store).areaDownsample(280, 340)
                    val golden = PlatformRaster.decodeRaw(testResource("golden/${g.file}")).asPremultiplied()
                    val cls = ParityRules.classify(g, golden)
                    val band = ParityRules.band(g, referenceCell(g))
                    val diff = ImageMetrics.diff(ours, golden)
                    val bodyMean = ParityRules.bodyRegionMean(ours, golden, oursBody)
                    save(big, "reveal-${g.id}-x1.5.png")
                    save(ours, "reveal-${g.id}.png")
                    val line = "${g.id}\t${frame.frame.tier.name}\t${frame.frame.placement.cell.id}\t${g.referenceCellId}\t$cls\t$band\t${"%.4f".format(diff.iou)}\t${"%.2f".format(diff.mean)}\t${"%.2f".format(bodyMean)}"
                    lines += line
                    note("reveal $line")
                    when (cls) {
                        GoldenClass.clean -> if (!band.passes(diff)) problems += "${g.id} [$band] IoU ${"%.4f".format(diff.iou)} · 평균 ${"%.2f".format(diff.mean)}"
                        GoldenClass.haloLag -> if (bodyMean > band.maxMean) problems += "${g.id} [$band/후광 지연] 몸 영역 평균 ${"%.2f".format(bodyMean)}"
                        else -> problems += "${g.id}: 공개 골든이 ${cls}"
                    }
                }
            } finally {
                appAssets.release(store)
            }
        }
        note("reveal ${chosen.size}장 path=${if (Build.VERSION.SDK_INT >= 29) "hwui" else "software"} 최저 IoU=${lines.minOf { it.split('\t')[6] }} 스핀 장=$spinFrames 문제=${problems.size}")
        File(outDir, "verdicts-reveal.tsv").writeText("id\ttier\tcell\treference\tclass\tband\tiou\tmean\tbodyMean\n" + lines.joinToString("\n") + "\n")
        assertTrue(spinFrames >= 4, "등 쪽 장이 S 스핀 칸으로 그려지지 않았다: $spinFrames")
        assertTrue(problems.isEmpty(), "공개 한 바퀴(공개 화면 크기) 문턱 밖 ${problems.size}건:\n" + problems.joinToString("\n"))
    }

    /** 넓이 평균 축소(프리멀티 RGBA — 비정수 배율). 공개 화면 크기 그림을 골든 280×340 에 맞댄다. */
    private fun RgbaImage.areaDownsample(tw: Int, th: Int): RgbaImage {
        val sx = width.toDouble() / tw
        val sy = height.toDouble() / th
        val out = ByteArray(tw * th * 4)
        val acc = DoubleArray(4)
        for (ty in 0 until th) for (tx in 0 until tw) {
            val x0 = tx * sx; val x1 = x0 + sx; val y0 = ty * sy; val y1 = y0 + sy
            acc.fill(0.0)
            var wsum = 0.0
            var y = floor(y0).toInt()
            while (y < y1 && y < height) {
                val wy = min(y1, y + 1.0) - max(y0, y.toDouble())
                var x = floor(x0).toInt()
                while (x < x1 && x < width) {
                    val wgt = (min(x1, x + 1.0) - max(x0, x.toDouble())) * wy
                    val i = (y * width + x) * 4
                    for (c in 0 until 4) acc[c] += wgt * (px[i + c].toInt() and 0xFF)
                    wsum += wgt
                    x++
                }
                y++
            }
            for (c in 0 until 4) out[(ty * tw + tx) * 4 + c] = (acc[c] / wsum).roundToInt().coerceIn(0, 255).toByte()
        }
        return RgbaImage(tw, th, out, true)
    }

    @Test
    fun 기기에서_무대를_두드리면_hit() {
        val handle = StageHandle()
        compose.setContent {
            AingTheme(dark = false) { AingStage("aing_gold", CharacterMood.Working, assets = appAssets, handle = handle) }
        }
        compose.waitUntil(30_000) { handle.store != null && handle.placement != null && handle.lastFrame != null }
        Thread.sleep(300)
        compose.waitForIdle()
        val node = compose.onNodeWithTag(STAGE_LIVE_TAG)
        val idle = node.captureToImage().asAndroidBitmap()
        val p = handle.placement!!
        node.performTouchInput { click(androidx.compose.ui.geometry.Offset((p.originX + 137.5 * p.scale).toFloat(), (p.originY + 137.5 * p.scale).toFloat())) }
        compose.waitForIdle()
        assertEquals(TapOutcome.hit, handle.lastTap)
        Thread.sleep(60)
        compose.waitForIdle()
        val hit = node.captureToImage().asAndroidBitmap()
        File(outDir, "device-stage-idle.png").outputStream().use { idle.compress(Bitmap.CompressFormat.PNG, 100, it) }
        File(outDir, "device-stage-hit.png").outputStream().use { hit.compress(Bitmap.CompressFormat.PNG, 100, it) }
        val d = ImageMetrics.diff(idle.toRgba(), hit.toRgba())
        note("tap gold hit=${handle.director!!.hits} 화면 차 평균=${"%.2f".format(d.mean)} framesPublished=${handle.framesPublished}")
        assertTrue(d.mean > 1.0, "두드린 뒤 화면이 바뀌지 않았다: $d")
        assertEquals(1, handle.director!!.hits)
    }
}
