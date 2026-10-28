// 원본: Sources/check/CheckOverlayReactions.swift @ 1b8260d (setDragFacing 가드 · runReaction 의 정지 중 거절 · blink 가드 · wakeQuietly · beginWake · reconcileAfterResume · 몸 클릭 판정) — 설계 F §5.2 경계 API · §5.4 프레임 정책
package com.yehsung.aingcheck.character

import com.yehsung.aingcheck.character.bake.PoseSample
import com.yehsung.aingcheck.character.math.Vec2
import com.yehsung.aingcheck.character.player.CharacterFrame
import com.yehsung.aingcheck.character.player.CharacterFrames
import com.yehsung.aingcheck.character.player.CharacterPlayer
import com.yehsung.aingcheck.character.player.FramePacer
import com.yehsung.aingcheck.character.render.BakeImageStore
import com.yehsung.aingcheck.character.render.PlatformRaster
import com.yehsung.aingcheck.core.rules.character.CharacterCatalog
import kotlin.math.abs
import kotlin.math.nextDown
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue

class CharacterPlayerTest {
    private val lib = RepoBake.library

    @Test
    fun 리액션은_단위로_스냅한_뒤_재생하고_끝나면_단위다() {
        val p = CharacterPlayer(lib, initialCharacterId = CharacterCatalog.builtInAingID)
        assertEquals(PoseSample.IDENTITY, p.wrapperPose(0.0))
        assertTrue(p.play("hit", 1.0))
        assertEquals("hit", p.activeReaction)
        assertNotEquals(PoseSample.IDENTITY, p.wrapperPose(1.1))
        // 다른 리액션이 끼어들면 그 자리에서 단위로 스냅 → 새 트랙 첫 표본(= 단위 근처)부터.
        assertTrue(p.play("greeting", 1.2))
        val first = p.wrapperPose(1.2)
        assertTrue((first.position).length < 1e-6 && abs(first.scale.y - 1) < 1e-6)
        assertEquals(PoseSample.IDENTITY, p.wrapperPose(1.2 + lib.track("greeting")!!.durationS + 0.01))
        assertEquals(null, p.activeReaction)
        assertFalse(p.play("no-such-reaction", 3.0))
        assertFalse(p.play("wake", 3.0), "깨기는 wake() 로만")
    }

    @Test
    fun 졸기는_끝_자세를_쥐고_감은_눈이다() {
        val p = CharacterPlayer(lib)
        assertTrue(p.beginSleep(0.0))
        val end = p.wrapperPose(5.0)
        val sleep = lib.motion.sleepPose
        assertTrue(abs(end.position.y - sleep.position.y * lib.motion.extent) < 1e-4)
        assertEquals(end, p.wrapperPose(50.0), "몇 초가 지나도 같은 자세")
        assertTrue(p.eyesClosed && p.sleeping)
        assertEquals(null, p.reactionEndsAt(), "끝 자세를 쥔 졸기는 활성 fps 를 붙들지 않는다")
        p.interrupt(51.0)
        assertFalse(p.eyesClosed); assertFalse(p.sleeping)
    }

    @Test
    fun 바라보기는_즉시_스냅이고_같은_값은_무시한다() {
        val p = CharacterPlayer(lib, initialCharacterId = CharacterCatalog.goldAingID)
        p.setFacing(1, moving = false, now = 0.0)
        assertEquals(40.0, p.facingDegrees())
        p.setFacing(-1, moving = false, now = 0.1)
        assertEquals(-40.0, p.facingDegrees())
        p.setFacing(5, moving = false, now = 0.2)
        assertEquals(40.0, p.facingDegrees(), "방향은 −1 · 0 · +1 로 접힌다")
        p.setFacing(0, moving = true, now = 0.3)
        assertFalse(p.walking, "정면을 보며 걷지는 않는다")
    }

    @Test
    fun 정지_중에는_리액션을_걸지_않고_재개하면_벽시계로_만료된_잔여를_걷는다() {
        val p = CharacterPlayer(lib)
        p.setSuspended(true, 0.0)
        assertFalse(p.play("hit", 0.5), "정지 중엔 모션을 걸지 않는다(맥 runReaction)")
        p.setSuspended(false, 1.0)
        assertTrue(p.play("poked", 1.0))
        p.setSuspended(true, 1.2)
        val frozen = p.wrapperPose(1.2)
        assertEquals(frozen, p.wrapperPose(30.0), "정지 동안 장면 시계가 멈춘다")
        p.setSuspended(false, 30.0) // 찔림 2.5s 는 벽시계로 이미 지났다 → 잔여를 걷는다
        assertEquals(PoseSample.IDENTITY, p.wrapperPose(30.0))

        // 아직 안 지났으면 이어서 재생(0.x초 잔여).
        assertTrue(p.play("poked", 40.0))
        p.setSuspended(true, 40.5)
        p.setSuspended(false, 41.0)
        assertNotEquals(PoseSample.IDENTITY, p.wrapperPose(41.0))
    }

    @Test
    fun 재개_정리는_깨기_보간도_벽시계로_걷는다() {
        // 화들짝 깨기: 맥 activeUntil = now + ReactionKind.wake.duration(0.4s). 되튀기까지 0.15s + wakeBounce 동안 정지했다가
        // 벽시계로 0.4s 가 지난 뒤 재개하면 남은 되튀기를 걷는다(재개 첫 프레임에 옛 모션이 튀지 않게).
        val wakeState = lib.motion.reaction("wake")!!.durationS!!
        val p = CharacterPlayer(lib)
        assertTrue(p.beginSleep(0.0))
        p.wrapperPose(5.0)
        assertTrue(p.wake(com.yehsung.aingcheck.character.player.WakeKind.startled, 5.0))
        assertFalse(p.setSuspended(true, 5.05))
        assertNotEquals(PoseSample.IDENTITY, p.wrapperPose(5.05))
        assertTrue(p.setSuspended(false, 5.0 + wakeState + 0.01), "만료된 깨기 잔여를 걷었다고 알린다")
        assertEquals(PoseSample.IDENTITY, p.wrapperPose(5.0 + wakeState + 0.01))
        // 아직 만료 전이면 이어서(0.x초 잔여).
        assertTrue(p.beginSleep(10.0)); p.wrapperPose(15.0)
        assertTrue(p.wake(com.yehsung.aingcheck.character.player.WakeKind.startled, 15.0))
        p.setSuspended(true, 15.05)
        assertFalse(p.setSuspended(false, 15.1))
        assertNotEquals(PoseSample.IDENTITY, p.wrapperPose(15.1))

        // 조용한 기상은 상태가 없다(맥 wakeQuietly 는 activeKind 를 두지 않는다) — 재개 때 남은 0.9s 보간을 언제나 걷는다.
        assertTrue(p.beginSleep(20.0)); p.wrapperPose(25.0)
        assertTrue(p.wake(com.yehsung.aingcheck.character.player.WakeKind.quiet, 25.0))
        p.setSuspended(true, 25.1)
        assertNotEquals(PoseSample.IDENTITY, p.wrapperPose(25.1))
        assertTrue(p.setSuspended(false, 25.2), "0.1s 만에 재개해도 조용한 기상 잔여는 걷는다")
        assertEquals(PoseSample.IDENTITY, p.wrapperPose(25.2))

        // 정지 중 조용한 기상은 보간 없이 단위로 선다(맥: 잠금 화면 뒤에서 깬 잠은 스냅).
        assertTrue(p.beginSleep(30.0)); p.wrapperPose(35.0)
        p.setSuspended(true, 35.0)
        assertTrue(p.wake(com.yehsung.aingcheck.character.player.WakeKind.quiet, 36.0))
        assertFalse(p.sleeping)
        assertEquals(PoseSample.IDENTITY, p.wrapperPose(36.0))
        assertFalse(p.setSuspended(false, 37.0))

        // 자는 중(끝 자세를 쥔 졸기)은 재개 정리가 건드리지 않는다.
        assertTrue(p.beginSleep(40.0))
        val held = p.wrapperPose(45.0)
        p.setSuspended(true, 45.0)
        assertFalse(p.setSuspended(false, 90.0))
        assertEquals(held, p.wrapperPose(90.0))
        assertTrue(p.sleeping)
    }

    @Test
    fun 깜빡임은_0_12초_가드_넷을_지킨다() {
        val blink = lib.motion.engine.blinkSeconds
        assertEquals(0.12, blink)
        val p = CharacterPlayer(lib, initialCharacterId = CharacterCatalog.builtInAingID)
        assertTrue(p.blink(1.0))
        assertTrue(p.eyesClosedAt(1.0) && p.eyesClosedAt(1.0 + blink - 1e-6), "0.12s 동안 감는다")
        assertFalse(p.eyesClosedAt(1.0 + blink), "0.12s 뒤 뜬다")
        assertTrue(p.isActive(1.05), "깜빡이는 동안 활성 fps")
        assertFalse(p.isActive(1.0 + blink + 0.01))
        // 그리기가 같은 시각의 눈을 본다: 깜빡이는 동안 감은 눈 패치 칸.
        val during = assertNotNull(CharacterFrames.compute(p, 1.05, 280.0, 340.0)) as CharacterFrame.Impostor
        assertTrue(during.frame.closedEyes && during.frame.placement.cell.closedPatch != null)
        val after = assertNotNull(CharacterFrames.compute(p, 1.2, 280.0, 340.0)) as CharacterFrame.Impostor
        assertFalse(after.frame.closedEyes)

        // ④ 리액션 상태(벽시계 만료 전)엔 깜빡이지 않는다 — 찔림 2.5s.
        assertTrue(p.play("poked", 2.0))
        assertFalse(p.blink(3.0)); assertFalse(p.eyesClosedAt(3.0))
        assertTrue(p.blink(4.6), "상태 만료(2.5s) 뒤엔 깜빡인다")
        // ② 정지 중엔 물러난다.
        p.setSuspended(true, 5.0)
        assertFalse(p.blink(5.1)); assertFalse(p.eyesClosedAt(5.1))
        p.setSuspended(false, 5.2)
        // ③ 자는 중엔 깜빡이지 않고, setEyesClosed(false) 로도 눈을 뜨지 않는다(졸기가 눈의 주인).
        assertTrue(p.beginSleep(6.0))
        assertFalse(p.blink(6.5))
        p.setEyesClosed(false)
        assertTrue(p.eyesClosedAt(6.5) && p.eyesClosed, "졸기 중 눈을 뜨지 않는다")
        p.interrupt(7.0)
        assertFalse(p.eyesClosedAt(7.0))
        // 깜빡이는 사이 잠들면 눈을 다시 뜨지 않는다 — 깨면 바로 뜬다.
        assertTrue(p.blink(8.0))
        assertTrue(p.beginSleep(8.05))
        assertTrue(p.eyesClosedAt(8.05 + blink + 0.5), "깜빡임 끝 시각이 지나도 자는 동안 감음")
        p.wrapperPose(12.0)
        assertTrue(p.wake(com.yehsung.aingcheck.character.player.WakeKind.startled, 12.0))
        assertFalse(p.eyesClosedAt(12.0), "깨면 눈을 뜬다")
        // 깜빡임 0.12s 안에 잠들었다 깨도 깨는 순간 눈을 뜬다(맥 endSleep → restoreEyes — 깜빡임 잔여를 버린다).
        p.interrupt(20.0)
        assertTrue(p.blink(20.0))
        assertTrue(p.beginSleep(20.02))
        assertTrue(p.wake(com.yehsung.aingcheck.character.player.WakeKind.startled, 20.05))
        assertFalse(p.eyesClosedAt(20.06), "깜빡임 끝(20.12) 전이어도 깨면 뜬다")
        // 엔진이 쥔 감은 눈(setEyesClosed)은 깜빡임과 따로 — 깨기가 함께 푼다.
        p.setEyesClosed(true)
        assertTrue(p.eyesClosedAt(13.0) && p.isActive(13.0))
        p.setEyesClosed(false)
        assertFalse(p.eyesClosedAt(13.0))
    }

    @Test
    fun 스프라이트는_깜빡이지_않는다() {
        val manifest = com.yehsung.aingcheck.core.rules.character.CharacterManifest.decode(
            java.io.File(RepoBake.repoRoot, "Sources/check/Characters/shiba/manifest.json").readText(),
        )
        val atlas = PlatformRaster.decodeRaw(java.io.File(RepoBake.repoRoot, "Sources/check/Characters/shiba/atlas.png").readBytes())
        val rt = com.yehsung.aingcheck.character.sprite.SpriteRuntime.make(
            manifest, atlas.width, atlas.height, com.yehsung.aingcheck.character.sprite.SpriteAlphaMask.of(atlas, manifest.atlas!!.states),
        )!!
        val p = CharacterPlayer(lib, spriteFor = { if (it == "shiba") rt else null }, initialCharacterId = "shiba")
        assertFalse(p.blink(1.0), "① 스프라이트는 깜빡임 경로를 타지 않는다(전용 프레임이 없다 — 막지 않으면 fps 만 오른다)")
        assertFalse(p.isActive(1.05))
    }

    @Test
    fun 캐릭터를_바꾸면_idle_위상이_0_으로_돌아간다() {
        val p = CharacterPlayer(lib, initialCharacterId = CharacterCatalog.builtInAingID, now = 0.0)
        val atFive = p.chain(5.0).character
        p.swapCharacter(CharacterCatalog.rainbowAingID, 5.0)
        assertEquals(0.0, p.idleTime(5.0))
        val (bob, sway) = lib.motion.idle.evaluate(0.0)
        assertEquals(0.0, bob); assertEquals(0.0, sway)
        assertNotEquals(atFive.translation, p.chain(5.0).character.translation)
    }

    @Test
    fun 프레임_간격은_vsync_정수배다() {
        // F §5.4 표: 활성 30 기준.
        val table = mapOf(60.0 to 2, 75.0 to 3, 90.0 to 3, 100.0 to 3, 120.0 to 4, 144.0 to 5, 165.0 to 6, 240.0 to 8)
        for ((hz, n) in table) assertEquals(n, FramePacer.vsyncInterval(hz, 30.0), "${hz}Hz")
        assertEquals(10, FramePacer.vsyncInterval(60.0, 6.0))
        assertTrue(FramePacer.vsyncInterval(75.0, 6.0) in 12..13)
        assertTrue(FramePacer.isActive(1.0, reactionEndsAt = 0.95, resetAfterS = 0.1, blinking = false, walking = false))
        assertFalse(FramePacer.isActive(1.06, reactionEndsAt = 0.95, resetAfterS = 0.1, blinking = false, walking = false))
        val q = listOf(Vec2(0.0, 0.0), Vec2(1.0, 0.0), Vec2(1.0, 1.0), Vec2(0.0, 1.0))
        assertFalse(FramePacer.needsRedraw("a", q, "a", q.map { Vec2(it.x + 0.2, it.y) }))
        assertTrue(FramePacer.needsRedraw("a", q, "a", q.map { Vec2(it.x + 0.3, it.y) }))
        assertTrue(FramePacer.needsRedraw("a", q, "b", q))
    }

    @Test
    fun 프레임_정책의_경계() {
        // 다시 그리기: 꼭짓점 이동이 정확히 0.25px 이면 그린다(F §5.4 "0.25px 미만이면 그리지 않는다"), 바로 아래면 안 그린다.
        val q = listOf(Vec2(10.0, 10.0), Vec2(20.0, 10.0), Vec2(20.0, 20.0), Vec2(10.0, 20.0))
        val exact = q.mapIndexed { i, v -> if (i == 2) Vec2(v.x + 0.25, v.y) else v }
        assertTrue(FramePacer.needsRedraw("a", q, "a", exact), "정확히 0.25px")
        val below = q.mapIndexed { i, v -> if (i == 2) Vec2(v.x, v.y + 0.25 - 1e-9) else v }
        assertFalse(FramePacer.needsRedraw("a", q, "a", below), "0.25px 바로 아래")
        assertTrue(FramePacer.needsRedraw("a", null, "a", q), "처음 프레임")
        assertTrue(FramePacer.needsRedraw("a", q.take(3), "a", q), "꼭짓점 수가 다르면")
        // 활성: 리액션 끝 + 0.1s 의 **바로 전까지** 30fps, 그 시각부터 유휴(맥 scheduleFPSReset(after: duration + 0.1)).
        assertTrue(FramePacer.isActive(1.0.nextDown(), reactionEndsAt = 0.875, resetAfterS = 0.125, blinking = false, walking = false))
        assertFalse(FramePacer.isActive(1.0, reactionEndsAt = 0.875, resetAfterS = 0.125, blinking = false, walking = false))
        assertTrue(FramePacer.isActive(9.0, reactionEndsAt = null, resetAfterS = 0.1, blinking = false, walking = true), "걷기")
        assertFalse(FramePacer.isActive(9.0, reactionEndsAt = null, resetAfterS = 0.1, blinking = false, walking = false))
        // 재생기: 트랙 끝 + fpsResetAfterS 경계.
        val p = CharacterPlayer(lib)
        assertTrue(p.play("hit", 0.0))
        val end = p.reactionEndsAt()!!
        assertEquals(lib.track("hit")!!.durationS, end)
        val reset = lib.motion.engine.fpsResetAfterS
        assertTrue(p.isActive((end + reset).nextDown()))
        assertFalse(p.isActive(end + reset + 1e-9))
        // 동점이면 작은 n: 60Hz · 목표 45 → n=1(60fps) · n=2(30fps) 둘 다 15 차.
        assertEquals(1, FramePacer.vsyncInterval(60.0, 45.0), "|60−45| = 15 = |30−45| 동점 → 작은 n")
    }

    @Test
    fun 몸_클릭은_칸_알파로_가르고_후광은_빠진다() {
        val p = CharacterPlayer(lib, initialCharacterId = CharacterCatalog.goldAingID)
        val frame = assertNotNull(CharacterFrames.compute(p, 1.0, 280.0, 340.0)) as CharacterFrame.Impostor
        assertEquals("S", frame.frame.tier.name)
        val store = BakeImageStore(frame.frame.finish, RepoBake.files, PlatformRaster)
        try {
            val stores = { _: com.yehsung.aingcheck.character.bake.BakedFinish -> store }
            val pivot = lib.camera.project(p.chain(1.0).character.translation, 280.0, 340.0)
            assertTrue(CharacterFrames.hitTest(frame, pivot, 24.0, stores), "몸 중심")
            assertFalse(CharacterFrames.hitTest(frame, Vec2(2.0, 2.0), 24.0, stores), "구석은 상자 밖")
            // 후광 판 안이지만 몸 밖인 점: 후광 사각형 위 변 가운데 근처.
            val h = frame.frame.halo!!.quad
            val haloTop = Vec2((h[0].x + h[1].x) / 2, (h[0].y + h[1].y) / 2 + 10)
            assertFalse(CharacterFrames.hitTest(frame, haloTop, 24.0, stores), "후광은 몸이 아니다")
            // 상자 + 여백 안이어도 알파가 32 이하면 아니다: 몸 상자 왼쪽 위 모서리 바로 안.
            val q = frame.viewportQuad
            val corner = Vec2(q.minOf { it.x } + 1, q.minOf { it.y } + 1)
            assertFalse(CharacterFrames.hitTest(frame, corner, 24.0, stores), "투명 여백")

            // 실제 구운 칸의 알파는 4X MSAA 라 0 · 64 · 128 · 191 · 255 뿐이다 — 가장 옅은 가장자리(64)는 몸, 0 은 아니다.
            val cell = frame.frame.placement.cell
            val toViewport = frame.frame.placement.cellToViewport
            val rgba = store.cellRgba(cell, frame.frame.closedEyes)
            assertEquals(setOf(0, 64, 128, 191, 255), (0 until rgba.width * rgba.height).map { rgba.px[it * 4 + 3].toInt() and 0xFF }.toSet(), "구운 칸 알파 단계")
            fun inBox(p: Vec2) = p.x in (q.minOf { it.x } - 23)..(q.maxOf { it.x } + 23) && p.y in (q.minOf { it.y } - 23)..(q.maxOf { it.y } + 23)
            for ((a, expected) in listOf(0 to false, 64 to true)) {
                val (x, y) = (0 until rgba.height).asSequence().flatMap { y -> (0 until rgba.width).asSequence().map { x -> x to y } }
                    .first { (x, y) -> rgba.alpha(x, y) == a && inBox(toViewport.map(Vec2(x + 0.5, y + 0.5))) }
                assertEquals(expected, CharacterFrames.hitTest(frame, toViewport.map(Vec2(x + 0.5, y + 0.5)), 24.0, stores), "구운 칸 알파 $a")
            }
        } finally {
            store.close()
        }
    }

    @Test
    fun 구운_칸_클릭_임계_32_의_양쪽() {
        // 맥 SpriteAlphaMask(임계 32) 를 구운 칸도 쓴다(F §5.3). 실제 칸엔 알파 1…63 이 없어(4X MSAA) 임계 0 · 32 가 구별되지 않으므로,
        // 이 칸의 페이지를 합성 PNG(칸 왼쪽 절반 알파 20 · 오른쪽 절반 33, 색 0)로 바꿔 끼워 같은 저장소 · 같은 hitTest 길로 잰다.
        val p = CharacterPlayer(lib, initialCharacterId = CharacterCatalog.goldAingID)
        val frame = assertNotNull(CharacterFrames.compute(p, 1.0, 280.0, 340.0)) as CharacterFrame.Impostor
        val f = frame.frame
        val cell = f.placement.cell
        val pagePath = f.finish.pagePath(cell.page)
        val real = PlatformRaster.decodeRaw(RepoBake.files.read(pagePath)!!)
        val img = java.awt.image.BufferedImage(real.width, real.height, java.awt.image.BufferedImage.TYPE_INT_ARGB)
        for (y in cell.rect.y until cell.rect.y + cell.rect.h) for (x in cell.rect.x until cell.rect.x + cell.rect.w) {
            val a = if (x - cell.rect.x < cell.rect.w / 2) 20 else 33
            img.setRGB(x, y, a shl 24)
        }
        val png = java.io.ByteArrayOutputStream().also { javax.imageio.ImageIO.write(img, "png", it) }.toByteArray()
        val store = BakeImageStore(f.finish, RepoBake.Files(override = mapOf(pagePath to png)), PlatformRaster)
        try {
            val stores = { _: com.yehsung.aingcheck.character.bake.BakedFinish -> store }
            val rgba = store.cellRgba(cell, f.closedEyes)
            assertEquals(20, rgba.alpha(cell.rect.w / 4, cell.rect.h / 2)); assertEquals(33, rgba.alpha(3 * cell.rect.w / 4, cell.rect.h / 2))
            val h = f.placement.cellToViewport
            val left = h.map(Vec2(cell.rect.w / 4 + 0.5, cell.rect.h / 2 + 0.5))
            val right = h.map(Vec2(3 * cell.rect.w / 4 + 0.5, cell.rect.h / 2 + 0.5))
            assertFalse(CharacterFrames.hitTest(frame, left, 24.0, stores), "알파 20 — 임계 32 아래라 몸이 아니다")
            assertTrue(CharacterFrames.hitTest(frame, right, 24.0, stores), "알파 33 — 몸")
            assertFalse(store.cellMask(cell, f.closedEyes).isOpaque(cell.rect.w / 4, cell.rect.h / 2))
            assertTrue(store.cellMask(cell, f.closedEyes).isOpaque(3 * cell.rect.w / 4, cell.rect.h / 2))
        } finally {
            store.close()
        }
    }

    @Test
    fun 단은_몸_크기로_고르고_없는_단은_있는_단으로() {
        val f = lib.finish(CharacterCatalog.builtInAingID)!!
        assertEquals("S", com.yehsung.aingcheck.character.render.ImpostorRenderer.chooseTier(f, 170.0)!!.name)
        assertEquals("L", com.yehsung.aingcheck.character.render.ImpostorRenderer.chooseTier(f, 250.0)!!.name)
        assertEquals("L", com.yehsung.aingcheck.character.render.ImpostorRenderer.chooseTier(f, 900.0)!!.name, "U 는 울트라 전용")
        assertEquals("U", com.yehsung.aingcheck.character.render.ImpostorRenderer.chooseTier(f, 700.0, allowUltra = true)!!.name)
    }
}
