// 원본: 없음 (W5-c 완료 ① — G §2-3 "L 단 자산 ≤ 4MB 단언" · §8-12 Android 기본 묶음 예산 4.5MB. 설치된 APK 로는 기기 시험 StageDeviceTest 가 다시 잰다)
package com.yehsung.aingcheck.android.screens.stage

import com.yehsung.aingcheck.character.bake.BakeLibrary
import com.yehsung.aingcheck.character.player.CharacterFrame
import com.yehsung.aingcheck.character.player.CharacterFrames
import com.yehsung.aingcheck.character.player.CharacterPlayer
import com.yehsung.aingcheck.core.rules.character.CharacterCatalog
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class StageBundleTest {
    private val bundle = StageBundleFiles.bundle()

    /** L 단 자산 = 세 마감의 L 페이지(쉬는 행 · 감은 눈 패치) + cells-L.json. */
    private fun isLTier(rel: String) = Regex("""^(aing|aing-gold|aing-rainbow)/(L-[^/]+\.webp|cells-L\.json)$""").matches(rel)

    @Test
    fun L단_자산은_4MB_이하이고_묶음은_45MB_이하다() {
        val lBytes = bundle.bytesWhere(::isLTier)
        val total = bundle.totalBytes
        println("AINGCHECK-W5C-BUNDLE files=${bundle.bakeFiles.size}+halo ${bundle.haloFiles.size} L=$lBytes total=$total")
        assertEquals(9, bundle.bakeFiles.keys.count(::isLTier), "L 단 파일 = 마감 셋 × (L-rest · L-patch · cells-L)")
        assertTrue(lBytes in 1..4_000_000, "L 단 자산 ≤ 4MB(G §2-3 W5-c ①): $lBytes")
        assertTrue(total <= 4_500_000, "Android 기본 묶음 ≤ 4.5MB(G §8-12): $total")
    }

    @Test
    fun 묶음에는_S_U_단도_골든도_다른_트랙도_없다() {
        val stray = bundle.bakeFiles.keys.filter { rel ->
            Regex("""(^|/)(S|U)-[^/]+\.webp$|cells-(S|U)\.json$""").containsMatchIn(rel) || rel.startsWith("golden/") ||
                (rel.startsWith("tracks/") && rel !in setOf("tracks/hit.f32", "tracks/greeting.f32"))
        }
        assertEquals(emptyList(), stray, "Android 묶음 밖 파일")
        // 무대가 쓰는 두 리액션의 트랙이 실려 있다(탭 = hit · 공개 = greeting).
        assertTrue("tracks/${StagePolicy.TAP_REACTION}.f32" in bundle.bakeFiles)
        assertTrue("tracks/${StagePolicy.REVEAL_REACTION}.f32" in bundle.bakeFiles)
        // 후광 원본: 금 · 무지개 각 36칸(정면 aing_*-halo.png + 10° 간격 35장) = 매니페스트 halo.cellFiles 그대로(맥 원본 — git 사본 0).
        val lib = BakeLibrary.load(StageBundleFiles.Files(bundle))
        for (id in listOf(CharacterCatalog.goldAingID, CharacterCatalog.rainbowAingID)) {
            val cellFiles = lib.finish(id)!!.bake.halo!!.cellFiles
            assertEquals(36, cellFiles.size, id)
            assertEquals(cellFiles.toSet(), bundle.haloFiles.keys.filter { it.startsWith("$id-halo") }.toSet(), "$id 후광 칸 = 실린 PNG")
        }
        assertEquals(72, bundle.haloFiles.size)
    }

    @Test
    fun 무대는_묶음만으로_선다() {
        val files = StageBundleFiles.Files(bundle)
        val lib = BakeLibrary.load(files)
        assertEquals(setOf(CharacterCatalog.builtInAingID, CharacterCatalog.goldAingID, CharacterCatalog.rainbowAingID), lib.bakedIds)
        for (id in lib.bakedIds) assertEquals(listOf("L"), lib.finish(id)!!.availableTiers().map { it.name }, id)
        assertNotNull(lib.track(StagePolicy.TAP_REACTION))
        assertNotNull(lib.track(StagePolicy.REVEAL_REACTION))
        assertNull(lib.track("goalAchieved"), "묶음에 없는 트랙")
        // 무대 리액션 표가 맥 값 그대로(hit 우선 3 · 0.6s, 인사 우선 1 · 1.0s, 쿨다운 0.6s · 유휴 6 · 활성 30fps).
        val hit = lib.motion.reaction(StagePolicy.TAP_REACTION)!!
        val greet = lib.motion.reaction(StagePolicy.REVEAL_REACTION)!!
        assertEquals(3 to 0.6, hit.priority to hit.durationS)
        assertEquals(1 to 1.0, greet.priority to greet.durationS)
        assertEquals(listOf(0.6, 6.0, 30.0), listOf(lib.motion.engine.hitCooldownS, lib.motion.engine.idleFPS, lib.motion.engine.activeFPS))
        // 그림(페이지)은 묶음 밖을 찾지 않는다 — 단 고르기가 S · U 칸 표를 물어보고(없음 = null) L 만 남긴다.
        val p = CharacterPlayer(lib, initialCharacterId = CharacterCatalog.goldAingID)
        val frame = CharacterFrames.compute(p, 1.0, StageFraming.FRAME_WIDTH, StageFraming.FRAME_HEIGHT) as CharacterFrame.Impostor
        assertEquals("L", frame.frame.tier.name)
        val pageReads = files.reads.filter { it.endsWith(".webp") }
        assertEquals(emptyList(), pageReads.filterNot { it in bundle.bakeFiles }, "묶음 밖 그림 읽기")
        assertEquals(emptyList(), files.reads.filter { it.startsWith("tracks/") && it !in bundle.bakeFiles && it != "tracks/goalAchieved.f32" }, "무대가 묶음 밖 트랙을 찾았다")
    }

    @Test
    fun 기준선_다른_입력_S단을_더하면_예산을_넘는다() {
        // 같은 판정이 늘 초록인 판정이 아님을 보인다(기억 comparison-baseline-must-differ): S 단 스핀 페이지를 실으면 묶음 예산을 넘는다.
        val withSpin = StageBundleFiles.bundle(extraAssetGlobs = listOf("*/S-spin-*.webp", "*/cells-S.json"))
        println("AINGCHECK-W5C-BUNDLE +S-spin total=${withSpin.totalBytes} (+${withSpin.totalBytes - bundle.totalBytes})")
        assertTrue(withSpin.totalBytes > 4_500_000, "S 스핀을 더한 묶음이 예산 안이다: ${withSpin.totalBytes}")
    }
}
