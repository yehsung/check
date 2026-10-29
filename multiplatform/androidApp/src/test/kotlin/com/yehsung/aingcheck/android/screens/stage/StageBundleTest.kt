// 원본: 없음 (W5-c 완료 ① — G §2-3 "L 단 자산 ≤ 4MB 단언" · §8-12 Android 기본 묶음 예산 → §8-19 #6② · §8-20 #5 공개 한 바퀴(S 스핀 행) 실측+여유 6.9MB. 설치된 APK 로는 기기 시험 StageDeviceTest 가 다시 잰다)
package com.yehsung.aingcheck.android.screens.stage

import com.yehsung.aingcheck.android.BuildConfig
import com.yehsung.aingcheck.character.bake.BakeCell
import com.yehsung.aingcheck.character.bake.BakeLibrary
import com.yehsung.aingcheck.character.player.CharacterFrame
import com.yehsung.aingcheck.core.rules.character.CharacterCatalog
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.random.Random

class StageBundleTest {
    private val bundle = StageBundleFiles.bundle()

    /** L 단 자산 = 세 마감의 L 페이지(쉬는 행 · 감은 눈 패치) + cells-L.json. */
    private fun isLTier(rel: String) = Regex("""^(aing|aing-gold|aing-rainbow)/(L-[^/]+\.webp|cells-L\.json)$""").matches(rel)

    /** S 스핀 행 = 세 마감의 S-spin 페이지 셋 + cells-S.json(공개 한 바퀴 — G §8-19 #6②). */
    private fun isSpin(rel: String) = Regex("""^(aing|aing-gold|aing-rainbow)/(S-spin-[^/]+\.webp|cells-S\.json)$""").matches(rel)

    @Test
    fun 묶음은_설정_예산_안이고_예산은_실측에_여유만큼이다() {
        val budget = requireNotNull(bundle.budget) { "config.json bundles.androidDefault.budget 이 없다" }
        val lBytes = bundle.bytesWhere(::isLTier)
        val spinBytes = bundle.bytesWhere(::isSpin)
        val total = bundle.totalBytes
        println("AINGCHECK-SPIN-BUNDLE files=${bundle.bakeFiles.size}+halo ${bundle.haloFiles.size} L=$lBytes spin=$spinBytes total=$total budget=$budget")
        assertEquals(9, bundle.bakeFiles.keys.count(::isLTier), "L 단 파일 = 마감 셋 × (L-rest · L-patch · cells-L)")
        assertEquals(12, bundle.bakeFiles.keys.count(::isSpin), "S 스핀 파일 = 마감 셋 × (S-spin 페이지 셋 + cells-S)")
        assertTrue(lBytes in 1..4_000_000, "L 단 자산 ≤ 4MB(G §2-3 W5-c ①): $lBytes")
        assertTrue(total <= budget, "Android 기본 묶음 ≤ 예산(config.json): $total > $budget")
        // 예산은 실측 + 여유(≤ 300KB ≈ 4.5%) — 묶음이 줄었는데 예산만 남아 큰 파일이 소리 없이 들어올 틈이 되지 않게(G §8-20 #5 '실측+여유').
        assertTrue(budget - total <= 300_000, "예산 여유가 너무 크다: 예산 $budget − 실측 $total")
        // 기기 시험(StageDeviceTest)이 설치된 APK 를 잴 때 쓰는 값도 같은 한 곳(build.gradle.kts 가 config.json 을 읽어 BuildConfig 로).
        assertEquals(budget, BuildConfig.STAGE_BUNDLE_BUDGET.toLong())
    }

    @Test
    fun 묶음에는_S_스핀_밖의_S_U_단도_골든도_다른_트랙도_없다() {
        val stray = bundle.bakeFiles.keys.filter { rel ->
            (Regex("""(^|/)(S|U)-[^/]+\.webp$|cells-(S|U)\.json$""").containsMatchIn(rel) && !isSpin(rel)) || rel.startsWith("golden/") ||
                (rel.startsWith("tracks/") && rel !in setOf("tracks/${StagePolicy.TAP_REACTION}.f32", "tracks/${StagePolicy.REVEAL_REACTION}.f32"))
        }
        assertEquals(emptyList(), stray, "Android 묶음 밖 파일")
        // 무대가 쓰는 두 리액션의 트랙이 실려 있다(탭 = hit · 공개 = 한 바퀴 commuteStart).
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
        for (id in lib.bakedIds) assertEquals(listOf("S", "L"), lib.finish(id)!!.availableTiers().map { it.name }, id)
        assertNotNull(lib.track(StagePolicy.TAP_REACTION))
        assertNotNull(lib.track(StagePolicy.REVEAL_REACTION))
        assertNull(lib.track("goalAchieved"), "묶음에 없는 트랙")
        // 무대 리액션 표가 맥 값 그대로(hit 우선 3 · 0.6s, 한 바퀴 우선 3 · 0.6s, 쿨다운 0.6s · 유휴 6 · 활성 30fps).
        val hit = lib.motion.reaction(StagePolicy.TAP_REACTION)!!
        val spin = lib.motion.reaction(StagePolicy.REVEAL_REACTION)!!
        assertEquals(3 to 0.6, hit.priority to hit.durationS)
        assertEquals(3 to 0.6, spin.priority to spin.durationS)
        assertEquals(listOf(0.6, 6.0, 30.0), listOf(lib.motion.engine.hitCooldownS, lib.motion.engine.idleFPS, lib.motion.engine.activeFPS))
        // 무대 틀(280×340 — 재생기 단 고르기라면 S)에서도 평소엔 L, 한 바퀴의 등 쪽은 S 스핀 칸. 그림은 묶음 밖을 찾지 않는다.
        val d = StageDirector(lib, lib.finish(CharacterCatalog.goldAingID)!!, 0.0, Random(0))
        val idle = d.frame(1.0, StageFraming.FRAME_WIDTH, StageFraming.FRAME_HEIGHT) as CharacterFrame.Impostor
        assertEquals("L", idle.frame.tier.name)
        assertTrue(d.reveal(2.0))
        val back = d.frame(2.3, StageFraming.FRAME_WIDTH, StageFraming.FRAME_HEIGHT) as CharacterFrame.Impostor
        assertEquals("S", back.frame.tier.name, "한 바퀴 한가운데(등)")
        assertEquals(BakeCell.Group.spin, back.frame.placement.cell.group)
        assertTrue(kotlin.math.abs(back.frame.placement.cell.yawDeg) >= 150, "등 쪽 칸: ${back.frame.placement.cell.id}")
        assertNotNull(files.read(back.frame.finish.pagePath(back.frame.placement.cell.page)), "등 쪽 칸의 페이지가 묶음에 있다")
        val after = d.frame(2.8, StageFraming.FRAME_WIDTH, StageFraming.FRAME_HEIGHT) as CharacterFrame.Impostor
        assertEquals("L", after.frame.tier.name, "한 바퀴가 끝나면 L")
        val pageReads = files.reads.filter { it.endsWith(".webp") }
        assertTrue(pageReads.isNotEmpty())
        assertEquals(emptyList(), pageReads.filterNot { it in bundle.bakeFiles }, "묶음 밖 그림 읽기")
        assertEquals(emptyList(), files.reads.filter { it.startsWith("tracks/") && it !in bundle.bakeFiles && it != "tracks/goalAchieved.f32" }, "무대가 묶음 밖 트랙을 찾았다")
    }

    @Test
    fun 기준선_다른_입력_S_쉬는_행을_더하면_예산을_넘는다() {
        // 같은 판정이 늘 초록인 판정이 아님을 보인다(기억 comparison-baseline-must-differ): S 쉬는 행 페이지를 실으면 묶음 예산을 넘는다.
        val withRest = StageBundleFiles.bundle(extraAssetGlobs = listOf("*/S-rest-*.webp"))
        println("AINGCHECK-SPIN-BUNDLE +S-rest total=${withRest.totalBytes} (+${withRest.totalBytes - bundle.totalBytes})")
        assertTrue(withRest.totalBytes > bundle.budget!!, "S 쉬는 행을 더한 묶음이 예산 안이다: ${withRest.totalBytes}")
    }
}
