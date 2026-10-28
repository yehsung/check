// 원본: Tests/checkTests/AingBakeSuite.swift @ 1b8260d (늘 도는 시험 ① 구운 매니페스트 = 기존 형식의 상위집합) — 설계 F §6 T0
package com.yehsung.aingcheck.character

import com.yehsung.aingcheck.character.bake.BakeCell
import com.yehsung.aingcheck.character.bake.BakeLibrary
import com.yehsung.aingcheck.character.bake.BakedManifest
import com.yehsung.aingcheck.character.math.Vec3
import com.yehsung.aingcheck.character.player.CharacterPlayer
import com.yehsung.aingcheck.character.render.DecodeClamp
import com.yehsung.aingcheck.character.render.PlatformRaster
import com.yehsung.aingcheck.character.render.asPremultiplied
import com.yehsung.aingcheck.core.rules.character.CharacterCatalog
import com.yehsung.aingcheck.core.rules.character.CharacterManifest
import java.io.File
import kotlin.math.abs
import kotlin.math.pow
import kotlin.math.roundToInt
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/**
 * T0 형식: 구운 3마감 매니페스트가 **기존 2D 디코더(W1-c)를 그대로 지나고** `bake` 확장까지 읽힌다 · 칸 파일 · 페이지 · 트랙이 메타와 맞다 ·
 * 모르는 굽기 판은 legacy 로 내려간다 · 굽지 않은 캐릭터(케이크 둘 · 모르는 id)는 아잉으로 접힌다(§8-17 #7).
 */
class BakeFormatTest {
    private val lib = RepoBake.library

    @Test
    fun 구운_세_마감은_기존_디코더를_지나고_bake_확장까지_읽힌다() {
        assertEquals(emptyMap(), lib.rejected, "버린 폴더가 없어야 한다")
        assertEquals(listOf("aing", "aing_gold", "aing_rainbow"), lib.bakedIds.toList())
        for ((folder, id) in BakeLibrary.FOLDER_IDS) {
            val text = File(RepoBake.bakeRoot, "$folder/manifest.json").readText()
            val legacy = CharacterManifest.decode(text) // W1-c 디코더 — bake 를 모르는 키로 무시해야 한다
            assertEquals(folder, legacy.id)
            assertEquals(CharacterManifest.Kind.sprite, legacy.kind)
            val atlas = assertNotNull(legacy.atlas)
            assertEquals(setOf("frontIdle", "sideIdle"), atlas.states.keys, "legacy 2칸")
            val f = assertNotNull(lib.finish(id))
            assertEquals(id, f.characterId)
            assertEquals(mapOf("aing" to "standard", "aing_gold" to "gold", "aing_rainbow" to "rainbow").getValue(id), f.bake.finish)
            assertEquals("premultiplied", f.bake.pagesAlpha)
            assertEquals(listOf("S", "L", "U"), f.bake.tiers.map { it.name })
            assertEquals(id != CharacterCatalog.builtInAingID, f.bake.halo != null, "후광은 금 · 무지개만")
            f.bake.halo?.let { h -> assertEquals(36, h.cellFiles.size) }
        }
    }

    @Test
    fun 칸_파일은_단_메타와_맞고_정준_순서다() {
        for (id in lib.bakedIds) {
            val f = lib.finish(id)!!
            for (tier in f.bake.tiers) {
                val cells = assertNotNull(f.cells(tier.name), "${id}/${tier.name}")
                assertEquals(tier.cellCount, cells.cells.size, "$id ${tier.name} 칸 수")
                assertEquals(cells.cells.sortedWith(BakeCell.canonicalOrder).map { it.id }, cells.cells.map { it.id }, "칸 번호(동점 깨기)는 정준 순서")
                for (c in cells.cells) {
                    assertTrue(c.page in f.bake.pages.indices && f.bake.pages[c.page] in tier.pages, "${c.id} 페이지 ${c.page}")
                    c.closedPatch?.let { p -> assertTrue(f.bake.pages[p.page] in tier.pages, "${c.id} 패치 페이지") }
                    // 칸 id = 단:요(부호 3자리):기울기(소수 1자리) — 굽기 BakeCell.id 문법.
                    val expected = "${tier.name}:${if (c.yawDeg >= 0) "+" else "-"}${abs(c.yawDeg).toString().padStart(3, '0')}:${String.format(java.util.Locale.ROOT, "%.1f", c.tiltDeg)}"
                    assertEquals(expected, c.id)
                }
            }
            assertEquals(f.cells("S")!!.cells.size, f.selector("S", false)!!.cells.size)
            assertTrue(f.selector("S", true)!!.cells.all { it.closedPatch != null })
        }
    }

    @Test
    fun 페이지는_곱하지_않고_디코드하며_클램프가_알파_0_빛을_지운다() {
        val f = lib.finish(CharacterCatalog.goldAingID)!!
        // 클램프 표는 manifest tableFormula 를 독립 계산한 값과 같다: table[a] = min(255, round(255·srgb(a/255)) + 1), table[0] = 0.
        fun srgb(x: Double) = if (x <= 0.0031308) 12.92 * x else 1.055 * x.pow(1 / 2.4) - 0.055
        val expected = IntArray(256) { a -> if (a == 0) 0 else minOf(255, (255 * srgb(a / 255.0)).roundToInt() + 1) }
        assertEquals(expected.toList(), f.bake.clamp.table.toList())

        val bytes = File(RepoBake.bakeRoot, f.pagePath(0)).readBytes()
        val raw = PlatformRaster.decodeRaw(bytes).asPremultiplied()
        val glowBefore = (0 until raw.width * raw.height).count { i -> raw.px[i * 4 + 3].toInt() == 0 && (0 until 3).any { raw.px[i * 4 + it].toInt() != 0 } }
        assertTrue(glowBefore > 0, "손실 RGB 는 알파 0 자리에 코덱 빛을 남긴다(클램프가 할 일이 있다)")
        val changed = DecodeClamp.applyInPlace(raw, f.bake.clamp)
        assertTrue(changed > 0)
        for (i in 0 until raw.width * raw.height) {
            val a = raw.px[i * 4 + 3].toInt() and 0xFF
            for (c in 0 until 3) assertTrue((raw.px[i * 4 + c].toInt() and 0xFF) <= f.bake.clamp.table[a], "픽셀 $i 채널 $c")
        }
        // 알파 평면은 무손실: 페이지 알파에 0 · 255 말고도 반투명 가장자리가 있다(직선으로 바꾸지 않았다는 증거는 색 > 알파 픽셀).
        val colorOverAlpha = (0 until raw.width * raw.height).count { i ->
            val a = raw.px[i * 4 + 3].toInt() and 0xFF
            a in 1..254 && (0 until 3).any { (raw.px[i * 4 + it].toInt() and 0xFF) > a }
        }
        assertTrue(colorOverAlpha > 1000, "SceneKit 프리멀티(색 > 알파) 바이트가 그대로 있어야 한다: $colorOverAlpha")
    }

    @Test
    fun 저장소가_내주는_칸은_클램프를_지났고_감은_눈은_패치를_덮어썼다() {
        val f = lib.finish(CharacterCatalog.builtInAingID)!!
        val store = com.yehsung.aingcheck.character.render.BakeImageStore(f, RepoBake.files, PlatformRaster)
        try {
            val cells = f.cells("S")!!.cells
            for (c in listOf(cells.first(), cells[cells.size / 2], cells.last())) {
                val rgba = store.cellRgba(c, closedEyes = false)
                assertEquals(c.rect.w, rgba.width); assertEquals(c.rect.h, rgba.height)
                for (i in 0 until rgba.width * rgba.height) {
                    val a = rgba.px[i * 4 + 3].toInt() and 0xFF
                    for (ch in 0 until 3) assertTrue((rgba.px[i * 4 + ch].toInt() and 0xFF) <= f.bake.clamp.table[a], "${c.id} 픽셀 $i 이 클램프 밖")
                }
            }
            assertTrue(store.clampedChannels > 0)
            val withPatch = cells.first { it.closedPatch != null }
            val open = store.cellRgba(withPatch, closedEyes = false)
            val closed = store.cellRgba(withPatch, closedEyes = true)
            val p = withPatch.closedPatch!!
            var diff = 0
            for (y in 0 until open.height) for (x in 0 until open.width) {
                val inside = x >= p.atX && y >= p.atY && x < p.atX + p.rect.w && y < p.atY + p.rect.h
                val same = (0 until 4).all { open.px[(y * open.width + x) * 4 + it] == closed.px[(y * open.width + x) * 4 + it] }
                if (!inside) assertTrue(same, "패치 밖 ($x,$y) 은 그대로") else if (!same) diff++
            }
            assertTrue(diff > 100, "패치가 눈을 바꿨다: $diff")
        } finally {
            store.close()
        }
    }

    @Test
    fun 트랙과_모션_메타가_맞다() {
        val m = lib.motion
        assertEquals(480, m.sampleHz)
        for ((name, info) in m.tracks) {
            val t = assertNotNull(lib.track(name), name)
            assertEquals(info.count, t.count, name)
        }
        // idle 공식 = 녹화 트랙(굽기가 ≤ 1e-6 로 잰 것을 Kotlin 식으로 다시 확인).
        val idle = lib.track("idle")!!
        for (k in 0 until idle.count step 37) {
            val (bob, sway) = m.idle.evaluate(k / 480.0)
            val s = idle.sampleAt(k)
            assertTrue(abs(s.position.y - bob) < 1e-5, "idle 부유 $k")
            assertTrue(abs(2 * kotlin.math.atan2(s.rotation.y, s.rotation.w) - sway) < 1e-5, "idle 살랑 $k")
        }
        assertEquals(Vec3(1.0, 1.0, 1.0), m.sleepPose.scale)
    }

    @Test
    fun 모르는_굽기_판은_legacy_로_내려가고_모양이_틀린_bake_도_legacy_는_산다() {
        val folder = "aing-gold"
        val text = File(RepoBake.bakeRoot, "$folder/manifest.json").readText()
        val future = text.replaceFirst("\"format\": 1", "\"format\": 2")
        check(future != text) { "치환 실패 — 매니페스트 모양이 바뀌었다" }
        val m = BakedManifest.decode(future)
        assertNull(m.bake)
        assertEquals("aing-gold", m.legacy.id)
        val broken = BakedManifest.decode(text.replaceFirst("\"tiers\"", "\"tiersX\""))
        assertNull(broken.bake)
        assertTrue(broken.bakeRejected!!.contains("tiers"))

        val lib2 = BakeLibrary.load(RepoBake.Files(override = mapOf("$folder/manifest.json" to future.encodeToByteArray())))
        assertNull(lib2.finish(CharacterCatalog.goldAingID))
        assertNotNull(lib2.legacyOnly(CharacterCatalog.goldAingID))
        assertEquals("aing-gold/legacy.webp", lib2.legacyAtlasPath(CharacterCatalog.goldAingID))
        assertTrue(lib2.rejected.getValue(folder).contains("모르는 굽기 형식 2"))
    }

    @Test
    fun 굽지_않은_캐릭터는_아잉으로_접힌다() {
        val cases = mapOf(
            CharacterCatalog.cakeStrawberryAingID to CharacterCatalog.builtInAingID,
            CharacterCatalog.cakeChocoAingID to CharacterCatalog.builtInAingID,
            "fox" to CharacterCatalog.builtInAingID, // 스프라이트 런타임을 주지 않았다
            "no-such" to CharacterCatalog.builtInAingID,
            "" to CharacterCatalog.builtInAingID,
            CharacterCatalog.goldAingID to CharacterCatalog.goldAingID,
            CharacterCatalog.rainbowAingID to CharacterCatalog.rainbowAingID,
        )
        for ((requested, drawn) in cases) {
            val p = CharacterPlayer(lib, initialCharacterId = requested)
            assertEquals(drawn, p.currentCharacterId, "요청 '$requested'")
            assertEquals(requested, p.requestedCharacterId)
        }
        val p = CharacterPlayer(lib, initialCharacterId = CharacterCatalog.goldAingID)
        p.swapCharacter(CharacterCatalog.cakeChocoAingID, 1.0)
        assertEquals(CharacterCatalog.builtInAingID, p.currentCharacterId)
        assertNull(lib.finish(CharacterCatalog.cakeStrawberryAingID), "케이크는 굽지 않았다(§8-17 #7) — 굽게 되면 이 시험을 고친다")
    }

    @Test
    fun 안드로이드_기본_묶음만으로도_선다() {
        // config.json bundles.androidDefault: L 칸 · 메타 · legacy · camera · motion · hit/greeting 트랙(+ 후광 PNG).
        val keep = Regex("""^(aing|aing-gold|aing-rainbow)/(L-.*\.webp|manifest\.json|cells-L\.json|legacy\.webp)$|^camera\.json$|^motion\.json$|^tracks/(hit|greeting)\.f32$""")
        val all = RepoBake.bakeRoot.walkTopDown().filter { it.isFile }.map { it.relativeTo(RepoBake.bakeRoot).invariantSeparatorsPath }.toSet()
        val hidden = all.filterNot { keep.matches(it) }.toSet()
        val android = BakeLibrary.load(RepoBake.Files(hide = hidden))
        assertEquals(3, android.bakedIds.size)
        for (id in android.bakedIds) {
            val f = android.finish(id)!!
            assertEquals(listOf("L"), f.availableTiers().map { it.name })
        }
        assertNotNull(android.track("hit")); assertNotNull(android.track("greeting")); assertNull(android.track("poked"))
        val p = CharacterPlayer(android, initialCharacterId = CharacterCatalog.goldAingID)
        assertTrue(p.play("hit", 1.0))
        assertTrue(!p.play("poked", 1.0), "묶음에 없는 트랙은 모션 없이 거절")
        val size = all.minus(hidden).sumOf { File(RepoBake.bakeRoot, it).length() } +
            RepoBake.haloRoot.listFiles()!!.filter { it.name.startsWith("aing_gold-halo") || it.name.startsWith("aing_rainbow-halo") }.sumOf { it.length() }
        assertTrue(size <= 4_500_000, "Android 기본 묶음 예산 4.5MB(G §8-12): $size")
    }
}
