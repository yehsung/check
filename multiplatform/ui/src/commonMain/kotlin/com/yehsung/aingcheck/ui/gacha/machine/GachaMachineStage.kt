// 원본: Sources/CheckCore/GachaMachine/GachaMachineView.swift @ 3bd04bd (GachaMachineStage — 시간 → 그림)
//
// 무대(설계 좌표 380×460, 1 = 1dp). **시각 [now] 와 감독 상태만으로 그린다** — 같은 상태 · 같은 시각이면 같은 그림이다(프레임 스냅숏이
// 이 성질에 기댄다). 바탕 · 무대 조명 · 황금 어둠 · 섬광은 무대 밖까지 번지게 그리고, 감싸는 쪽([GachaMachineView])이 자른다.
//
// 이식 차이(Swift → Compose):
//  - 불투명도는 전부 [GachaFade](직선)다. Swift 가 불투명도에 건 smooth · exp · pow 는 같은 구간의 직선으로 바꿨다(위치·크기·회전은 원문 곡선).
//  - `.blur` · `.shadow` 는 그리지 않는다(기기마다 같은 픽셀 — 넓은 반투명 획 · 방사형 그라데이션으로 대신).
//  - 미리 데우기 층(prewarmLayer)은 옮기지 않았다 — SwiftUI 첫 그리기 지연을 숨기던 장치다. Compose 는 그림을 미리 풀어 둔다(호출부).
package com.yehsung.aingcheck.ui.gacha.machine

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.remember
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.drawscope.rotate
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.layout
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.rules.character.CharacterCatalog
import com.yehsung.aingcheck.core.rules.character.CharacterManifest
import com.yehsung.aingcheck.ui.components.CharacterStageMetrics
import com.yehsung.aingcheck.ui.shop.LocalLiveCharacterPreview
import com.yehsung.aingcheck.ui.shop.MeLiveOrPortrait
import com.yehsung.aingcheck.ui.theme.AingTextPaint
import kotlin.math.PI
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.pow
import kotlin.math.sin

/** 공개된 캐릭터를 그리는 자리. 기본은 초상 그림 — 살아 있는 미리보기(W5-c)가 이 자리를 갈아 끼울 수 있다(조립 — assembly.md). */
fun interface GachaRevealPortrait {
    /** [id] 의 그림(없으면 null — 그 자리를 비운다). */
    fun image(id: String): ImageBitmap?
}

/**
 * 공개 자리에 살아 있는 미리보기([LocalLiveCharacterPreview] — Android 무대)를 쓰는 캐릭터 = 구운 3D 아잉이(아잉 · 황금 · 무지개 · 케이크 둘은
 * 무대가 아잉으로 접는다). 스프라이트(여우 …) · 모르는 id 는 지금처럼 초상 캔버스. 동작 줄이기도 초상(iOS 와 같은 정지 그림).
 */
fun gachaRevealUsesLive(characterId: String): Boolean =
    CharacterCatalog.builtIns.any { it.id == characterId && it.kind == CharacterManifest.Kind.scene3D }

/** 무대 한 장. [now] 는 감독 시계와 같은 축(초). */
@Composable
fun GachaMachineStage(
    d: GachaMachineDirector,
    env: GachaMachineEnv,
    theme: GachaMachineTheme,
    sprites: GachaCapsuleSprites,
    now: Double,
    portrait: GachaRevealPortrait,
    ruby: ImageBitmap?,
    modifier: Modifier = Modifier,
) {
    val ph = d.phase(now)
    val still = d.reduced || env.reduceMotion
    val f = StageFrame(d, env, theme, sprites, now, ph, still, portrait, hasLive = LocalLiveCharacterPreview.current != null)
    Box(
        modifier
            .requiredSize(GLayout.size.width.dp, GLayout.size.height.dp)
            .pointerInput(d) {
                awaitEachGesture {
                    awaitFirstDown(requireUnconsumed = true)
                    if (!d.pressing) { d.pressing = true; d.press() }
                    try {
                        do {
                            val event = awaitPointerEvent()
                        } while (event.changes.any { it.pressed })
                    } finally {
                        // 놓았거나 취소됐다(전화 · 시스템 알림) — 어느 쪽이든 누름을 푼다(안 풀면 기계가 영영 매 프레임 그린다).
                        if (d.pressing) d.pressEnded()
                    }
                }
            },
    ) {
        CompositionLocalProvider(LocalStageRuby provides ruby) {
            Canvas(Modifier.fillMaxSize()) { design { f.drawBackground(this) } }
            MachineGroup(f)
            Canvas(Modifier.fillMaxSize()) { design { f.drawSpotlight(this); f.drawGoldDim(this) } }
            Canvas(Modifier.fillMaxSize()) { design { f.drawCapsule(this) } }
            Canvas(Modifier.fillMaxSize()) { design { f.drawReveal(this); f.drawOutgoing(this) } }
            f.warmId?.let { WarmLive(it) }
            if (f.liveId != null) {
                RevealLive(f)
                Canvas(Modifier.fillMaxSize()) { design { f.drawShardsOverLive(this) } }
            }
            TextLayer(f)
            Chips(f)
            Buttons(f)
            Canvas(Modifier.fillMaxSize()) { design { f.drawFlash(this) } }
        }
    }
}

/** 설계 좌표(1 = 1dp)로 그린다. */
private inline fun DrawScope.design(block: DrawScope.() -> Unit) {
    val k = density
    withTransform({ scale(k, k, Offset.Zero) }) { block() }
}

/** 무대 안 한 점(설계 좌표)에 가운데를 맞춰 놓는다. */
private fun Modifier.centerAt(x: Float, y: Float): Modifier = layout { measurable, constraints ->
    val placeable = measurable.measure(constraints.copy(minWidth = 0, minHeight = 0))
    layout(constraints.maxWidth, constraints.maxHeight) {
        placeable.place((x.dp.toPx() - placeable.width / 2f).roundToInt(), (y.dp.toPx() - placeable.height / 2f).roundToInt())
    }
}

/**
 * 공개 자리의 살아 있는 미리보기(W5-c · 사용자 결정 "첫 판부터 한 바퀴"): 구운 3D 아잉이는 초상 대신 무대가 그리고, 결과마다 오르는
 * [GachaMachineDirector.revealSerial] 로 한 바퀴 돈다. 자리 · 배율 · 불투명도는 초상 캔버스와 같은 [StageFrame.characterPose](타이밍 그대로).
 * 무대 칸(그림 + 6 × 그림 + 12, 그림 바닥 여백 [CharacterStageMetrics.artBottomPadding])의 그림 가운데를 초상 가운데에 맞춘다.
 */
@Composable
private fun RevealLive(f: StageFrame) {
    val id = f.liveId ?: return
    val r = f.d.result ?: return
    val rt = f.revealT ?: return
    val p = f.characterPose(r, rt)
    val boxH = p.size + 12f
    val artCenterFromTop = boxH - CharacterStageMetrics.artBottomPadding.value - p.size / 2
    Box(
        Modifier
            .centerAt(p.center.x, p.center.y + (boxH / 2 - artCenterFromTop))
            .graphicsLayer {
                scaleX = p.scale
                scaleY = p.scale
                alpha = p.opacity
                transformOrigin = TransformOrigin(0.5f, artCenterFromTop / boxH)
            },
    ) { MeLiveOrPortrait(id, p.size.dp, revealSerial = f.d.revealSerial) }
}

/**
 * 공개 전 데움: 결과가 온 뒤 공개까지(1~2초) 같은 캐릭터의 살아 있는 미리보기를 무대 구석에 1dp · 투명으로 세워 둔다. 무대 자산 읽기 · 칸 굽기
 * (기기에 따라 수백 ms~수 초)가 공개 순간의 빈 자리로 보이지 않게 — 무대 저장소는 캐릭터마다 하나라 공개 자리가 그것을 이어 쓴다.
 * 번호 0 이라도 숨은 자리의 반응은 보이지 않는다(한 바퀴 칸도 이때 데워진다).
 */
@Composable
private fun WarmLive(id: String) {
    Box(Modifier.centerAt(0f, 0f).graphicsLayer { alpha = 0f }) { MeLiveOrPortrait(id, 1.dp, revealSerial = 0) }
}

@Composable
private fun designSp(points: Float): TextUnit = with(LocalDensity.current) { points.dp.toSp() }

@Composable
private fun stageText(points: Float, weight: FontWeight): TextStyle =
    MaterialTheme.typography.bodyMedium.copy(fontSize = designSp(points), lineHeight = designSp(points * 1.25f), fontWeight = weight, fontFeatureSettings = "tnum")

/** 한 프레임의 파생 값 묶음(Swift `GachaMachineStage` 의 계산 속성들). */
private class StageFrame(
    val d: GachaMachineDirector,
    val env: GachaMachineEnv,
    val theme: GachaMachineTheme,
    val sprites: GachaCapsuleSprites,
    val now: Double,
    val ph: GPhase,
    val still: Boolean,
    val portrait: GachaRevealPortrait,
    hasLive: Boolean,
) {
    /** 기계가 뒤로 물러난 정도(움직임 — smooth). */
    val recede: Double = when (ph) {
        is GPhase.Dropping -> if (d.reduced) GMath.smooth(d.drop.land, d.drop.total, ph.t) else GMath.smooth(d.drop.jump0 - 0.06, d.drop.jump1 - 0.1, ph.t)
        is GPhase.Tapping, is GPhase.Building, is GPhase.Reveal -> 1.0
        GPhase.Idle -> d.returnTime?.let { 1 - GMath.smooth(0.0, 0.5, now - it) } ?: 0.0
        else -> 0.0
    }

    /** 물러남의 **직선** 판(불투명도 자리 — 같은 구간). */
    val recedeFade: Double = when (ph) {
        is GPhase.Dropping -> if (d.reduced) GachaFade.rise(d.drop.land, d.drop.total, ph.t) else GachaFade.rise(d.drop.jump0 - 0.06, d.drop.jump1 - 0.1, ph.t)
        is GPhase.Tapping, is GPhase.Building, is GPhase.Reveal -> 1.0
        GPhase.Idle -> d.returnTime?.let { GachaFade.fall(0.0, 0.5, now - it) } ?: 0.0
        else -> 0.0
    }

    val revealT: Double? = (ph as? GPhase.Reveal)?.t

    /** 공개 자리를 살아 있는 미리보기가 그리는가(그 캐릭터 id) — 그러면 캔버스는 초상을 그리지 않는다. */
    val liveId: String? = d.result?.characterID?.takeIf { hasLive && revealT != null && !still && gachaRevealUsesLive(it) }

    /** 결과는 왔고 아직 공개 전(떨어짐 · 톡톡 · 모음) — 그 캐릭터의 무대를 미리 세워 둘 id. */
    val warmId: String? = d.result?.characterID?.takeIf { hasLive && revealT == null && !still && gachaRevealUsesLive(it) }

    /** 희귀 캡슐(황금 · 무지개)이 지금 보이는가 — 반전(tease)이면 둘째 톡부터. */
    val rareShown: Boolean = d.isRare && (!d.tease || d.tapTimes.size >= 2 || d.burstTime != null)

    /** 지금 무대의 희귀 빛깔(결과 → 막 끝난 결과 순). */
    val stageRare: GRare? = d.rare ?: d.outgoing?.let { GRare.of(it.kind) }

    /** 황금 어둠의 세기(불투명도 — 직선). */
    val dimAmount: Double = run {
        if (d.isRare) {
            when (ph) {
                is GPhase.Dropping -> return@run if (d.tease) 0.0 else 0.42 * GachaFade.rise(0.0, 0.5, ph.t)
                is GPhase.Tapping -> {
                    if (d.tease) {
                        if (d.tapTimes.size < 2) return@run 0.0
                        return@run 0.45 * GachaFade.rise(0.0, 0.3, now - d.tapTimes[1])
                    }
                    return@run 0.45
                }
                is GPhase.Building -> return@run GMath.lerp(0.45, 0.84, GachaFade.rise(0.0, 0.6, ph.t))
                is GPhase.Reveal -> return@run if (d.reduced) GMath.lerp(0.42, 0.84, GachaFade.rise(0.0, 0.35, ph.t)) else 0.84
                else -> Unit
            }
        }
        val rt = d.returnTime
        if (ph == GPhase.Idle && d.outgoing?.kind?.isRare == true && rt != null) 0.84 * GachaFade.fall(0.0, 0.45, now - rt) else 0.0
    }

    fun portraitSize(rare: Boolean): Float = if (rare) 172f else 150f

    // MARK: 바탕

    fun drawBackground(s: DrawScope) = with(s) {
        val r = bleedRect()
        drawRect(Brush.verticalGradient(listOf(theme.bgTop, theme.bgBottom), 0f, GLayout.size.height), r.topLeft, r.sizeOf())
        val glowC = Offset(GLayout.midX, 0.28f * GLayout.size.height)
        drawRect(
            Brush.radialGradient(0f to theme.bgGlow, (10f / 260f) to theme.bgGlow, 1f to theme.bgGlow.copy(alpha = 0f), center = glowC, radius = 260f),
            r.topLeft, r.sizeOf(),
        )
    }

    // MARK: 기계

    /** 기계 무리의 흔들림 · 찌그러짐(설계 좌표). */
    val shake: Triple<Double, Double, Double> = run {
        var ox = 0.0
        var oy = 0.0
        var squash = 0.0
        val commit = d.commitTime
        if (!still && commit != null) {
            val tc = now - commit
            d.kickTimes(now).forEachIndexed { i, kt ->
                val tau = tc - kt
                if (tau < 0 || tau >= 1.2) return@forEachIndexed
                val amp = if (i == 0) 1.0 else 0.5
                oy += amp * 5 * GMath.ringCos(tau, 6.0, 10.0)
                ox += amp * 3 * GMath.ring(tau, 13.0, 8.0)
                squash += amp * 0.03 * GMath.ringCos(tau, 6.0, 10.0)
            }
        }
        if (!still && ph is GPhase.Failed) ox += 6 * GMath.ring(ph.t, 7.0, 6.0)
        Triple(ox, oy, squash)
    }

    val knobAngle: Double = d.knobAngle(now)
    val idle: Boolean = ph == GPhase.Idle

    fun drawMachineBack(s: DrawScope) = with(s) {
        // 바닥 그림자
        drawOval(
            Brush.radialGradient(listOf(Color.Black.copy(alpha = theme.floorShadow), Color.Black.copy(alpha = 0f)), center = Offset(GLayout.midX, 404f), radius = 125f),
            Offset(GLayout.midX - 125f, 404f - 16f), Size(250f, 32f),
        )
        // 기계가 뒤로 완전히 물러나면(흐릿) 돔 속 들썩임을 멈춘다.
        val ds = d.dropStart
        val domeNow = if (recede >= 0.999 && ds != null) ds + max(0.0, d.drop.jump1 - 0.1) else now
        drawDome(domeNow, d.kickTimes(now), d.commitTime, sprites, d.ambient(now), d.ambientLinear(now), still, theme)
        drawCap(env.art)
        drawMachineBody(env.art)
    }

    fun flapOpen(): Double = (ph as? GPhase.Dropping)?.let { GachaMachineDirector.flapOpen(it.t, d.drop, d.reduced) } ?: 0.0

    fun drawMachineFront(s: DrawScope) = with(s) {
        drawChuteGlow(this)
        val lit = if (d.commitTime != null) 8 else min(8, ((knobAngle + 0.5) / 45).toInt())
        val litAlpha = d.commitTime?.let { GachaFade.fall(0.35, 1.0, now - it) } ?: 1.0
        drawNotchRing(lit, litAlpha.toFloat())
        val canPull = env.canPull
        val hintAlpha = if (idle && canPull) GachaFade.fall(4.0, 40.0, knobAngle) * (1 - recedeFade) * (if (d.dragging) 0.4 else 1.0) else 0.0
        drawHintArc(now, GLayout.knobCenter, GLayout.notchR + 11f, hintAlpha, d.ambientLinear(now))
        // 처음 보는 사람에게: 손잡이가 가끔 살짝 '돌려 봐' 하고 까딱인다(잔잔한 움직임이 잦아들면 멈춘다)
        val nudge = if (idle && !d.touchedHandle && canPull) d.ambient(now) * 10 * max(0.0, sin(2 * PI * now / 2.8)).pow(14) else 0.0
        drawKnob(env.art, (knobAngle + nudge).toFloat(), d.knobPop(now).toFloat(), if (canPull) 1f else 0.35f, if (canPull) 1f else 0.8f)
    }

    /** 희귀(황금 · 무지개): 캡슐이 나오기 전부터 배출구가 그 빛깔로 샌다. */
    private fun drawChuteGlow(s: DrawScope) = with(s) {
        val td = (ph as? GPhase.Dropping)?.t ?: return@with
        val rare = d.rare ?: return@with
        if (d.tease || td >= d.drop.emerge1 + 0.3) return@with
        val a = GachaFade.rise(0.0, 0.3, td) * GachaFade.fall(d.drop.emerge1 - 0.05, d.drop.emerge1 + 0.3, td)
        val flicker = if (still) 1.0 else 0.78 + 0.22 * sin(2 * PI * 6 * td)
        val chute = GLayout.chuteRect
        val inner = Rect(chute.left + 3f, chute.top + 3f + 6f, chute.right - 3f, chute.bottom - 3f + 6f)
        val brush = if (rare == GRare.Rainbow) Brush.horizontalGradient(GRare.spectrum.map { it.copy(alpha = GachaFade.f(0.55 * a * flicker)) }, inner.left, inner.right)
        else Brush.horizontalGradient(listOf(rare.primary.copy(alpha = GachaFade.f(0.55 * a * flicker)), rare.primary.copy(alpha = GachaFade.f(0.55 * a * flicker))))
        drawRoundRect(brush, inner.topLeft, inner.sizeOf(), CornerRadius(12f), blendMode = BlendMode.Plus)
        val c = Offset(chute.center.x, chute.center.y + 6f)
        drawCircle(Brush.radialGradient(listOf(rare.light.copy(alpha = GachaFade.f(0.9 * a * flicker)), rare.primary.copy(alpha = 0f)), center = c, radius = 70f), 75f, c, blendMode = BlendMode.Plus)
    }

    // MARK: 무대 조명 · 어둠

    fun drawSpotlight(s: DrawScope) = with(s) {
        val burstBoost = revealT?.let { GachaFade.rise(0.0, 0.3, it) } ?: 0.0
        val a = min(1.0, 0.8 * recedeFade + 0.2 * burstBoost)
        if (a <= 0.01) return@with
        val r = bleedRect()
        drawRect(
            Brush.radialGradient(*theme.spotlight.map { (p, c) -> p to c }.toTypedArray(), center = GLayout.stageCenter, radius = 400f),
            r.topLeft, r.sizeOf(), alpha = GachaFade.f(a),
        )
    }

    fun drawGoldDim(s: DrawScope) = with(s) {
        val a = dimAmount
        if (a <= 0.005) return@with
        // 가운데는 덜, 가장자리는 더 — 회색 장막 대신 깊은 자줏빛 비네트
        val focus = if (ph is GPhase.Dropping) Offset(GLayout.midX, 0.72f * GLayout.size.height) else GLayout.stageCenter
        val r = bleedRect()
        drawRect(
            Brush.radialGradient(
                0f to GPalette.hex(0x2A1460, GachaFade.f(a * 0.72)),
                (20f / 360f) to GPalette.hex(0x2A1460, GachaFade.f(a * 0.72)),
                1f to GPalette.hex(0x140A2E, GachaFade.f(a * 1.12)),
                center = focus, radius = 360f,
            ),
            r.topLeft, r.sizeOf(),
        )
        val glow = (stageRare ?: GRare.Gold).dimGlow
        drawRect(
            Brush.radialGradient(listOf(glow.copy(alpha = GachaFade.f(0.5 * a)), glow.copy(alpha = 0f)), center = focus, radius = 260f),
            r.topLeft, r.sizeOf(),
        )
    }

    // MARK: 캡슐

    class Pose(var c: Offset, var d: Float, var sx: Double = 1.0, var sy: Double = 1.0, var rot: Double = 0.0, var alpha: Double = 1.0, var bright: Double = 0.0)

    fun capsulePose(): Pose? {
        val ds = d.dropStart ?: return null
        if (now < ds) return null
        if (ph !is GPhase.Dropping && ph !is GPhase.Tapping && ph !is GPhase.Building) return null
        val td = now - ds
        val tt = d.drop
        val p = Pose(GLayout.tray, GLayout.capsuleSmall)
        if (d.reduced) {
            // 동작 줄이기: 배출구에서 미끄러져 나와 쟁반에 앉는다(튀거나 돌지 않는다)
            val lin = GMath.ramp(tt.emerge0, tt.emerge1, td)
            val eased = GMath.easeOutCubic(lin)
            p.c = GMath.lerp(GLayout.chuteInside, GLayout.tray, eased)
            p.d = GLayout.capsuleSmall * GMath.lerp(0.62, 1.0, eased).toFloat()
            p.bright = GMath.lerp(-0.45, 0.0, eased)
            p.alpha = GachaFade.rise(0.0, 0.3, lin)
            return p
        }
        if (td < tt.jump0) {
            val e = GMath.ramp(tt.emerge0, tt.emerge1, td)
            val start = GLayout.chuteInside
            p.c = Offset(
                GMath.lerp(start.x.toDouble(), GLayout.tray.x.toDouble(), e).toFloat(),
                (GMath.lerp(start.y.toDouble(), GLayout.tray.y.toDouble(), GMath.easeInCubic(e)) - 12 * sin(PI * e)).toFloat(),
            )
            p.d = GLayout.capsuleSmall * GMath.lerp(0.62, 1.0, GMath.easeOutCubic(e)).toFloat()
            p.bright = GMath.lerp(-0.45, 0.0, e)
            p.alpha = GachaFade.rise(0.0, 0.2, e)
            p.rot = GMath.lerp(-50.0, 0.0, GMath.easeOutCubic(e))
            val tau = td - tt.land
            if (tau > 0) {
                val s = 0.22 * GMath.ringCos(tau, 4.5, 11.0)
                p.sx += s; p.sy -= s
                p.c = Offset(p.c.x, (p.c.y - 5 * kotlin.math.abs(GMath.ring(tau, 2.6, 7.0))).toFloat())
            }
            // 뛰기 직전 웅크림
            val tc = td - (tt.jump0 - 0.08)
            if (tc > 0) { val s = 0.14 * sin(PI * min(1.0, tc / 0.08)); p.sx += s * 0.6; p.sy -= s }
        } else {
            val q = GMath.ramp(tt.jump0, tt.jump1, td)
            val e = 0.5 * (GMath.easeInOutCubic(q) + GMath.easeOutCubic(q))
            p.c = GMath.bezier(GLayout.tray, Offset(300f, 95f), GLayout.stageCenter, e)
            p.d = (GLayout.capsuleSmall + (GLayout.capsuleBig - GLayout.capsuleSmall) * GMath.smooth(0.0, 1.0, q)).toFloat()
            p.rot = -360 * e
            // 공중에서 살짝 늘어남
            val air = sin(PI * q)
            p.sy += 0.08 * air; p.sx -= 0.05 * air
            val tau = td - tt.jump1
            if (tau > 0) {
                val s = 0.16 * GMath.ringCos(tau, 3.2, 8.0)
                p.sx += s; p.sy -= s
                // 둥실(잔잔한 움직임 — 잦아들면 제자리)
                val ramp = GMath.smooth(0.2, 0.8, tau) * d.ambient(now)
                p.c = Offset(p.c.x, (p.c.y + 3.5 * sin(2 * PI * 0.55 * tau) * ramp).toFloat())
                p.rot += 2.5 * sin(2 * PI * 0.4 * tau) * ramp
            }
        }
        d.tapTimes.lastOrNull()?.let { last ->
            val tau = now - last
            val k = d.tapTimes.size
            val amp = listOf(0.75, 0.95, 1.15)[min(k, 3) - 1]
            val s = 0.17 * amp * GMath.ringCos(tau, 3.6, 9.0)
            p.sx += s; p.sy -= s
            p.c = Offset((p.c.x + 7 * amp * GMath.ring(tau, 9.0, 9.0)).toFloat(), p.c.y)
            p.rot += 7 * amp * GMath.ring(tau, 6.0, 8.0)
        }
        if (ph is GPhase.Building) {
            val k = ph.t / GTiming.goldBuild
            p.c = Offset((p.c.x + (1.2 + 4 * k) * sin(2 * PI * 23 * ph.t)).toFloat(), (p.c.y + (0.8 + 2 * k) * sin(2 * PI * 19 * ph.t + 1)).toFloat())
            p.d *= (1 + 0.12 * GMath.easeInCubic(k)).toFloat()
            p.bright = 0.22 * k
        }
        return p
    }

    fun drawCapsule(s: DrawScope) = with(s) {
        val p = capsulePose() ?: return@with
        val pair = d.dropPair
        val cracks = GCracks.make(d.seed)
        val rare = if (rareShown) d.rare else null
        val gold = rare != null
        val taps = d.tapTimes.size
        val lastTau = d.tapTimes.lastOrNull()?.let { now - it } ?: 9.0
        // 원문 exp(−6τ) 톡 섬광의 자리 — 직선으로 0.5초.
        val tapFlash = GachaFade.decay(lastTau, 0.5)
        val buildK = (ph as? GPhase.Building)?.let { it.t / GTiming.goldBuild } ?: 0.0
        // 금빛이 은은하게 숨 쉰다(잔잔한 움직임 — 잦아들면 가운데 값)
        val goldPulse = 0.5 + 0.5 * sin(2 * PI * 1.6 * now) * d.ambientLinear(now)
        val halo = if (gold) min(1.4, 0.55 + 0.2 * goldPulse + 0.12 * taps + 0.4 * buildK) * p.alpha
        else min(1.0, 0.22 * taps + 0.35 * tapFlash * (if (taps > 0) 1.0 else 0.0))
        val beams = taps * 0.55 + 0.3 * tapFlash * (if (taps > 0) 1.0 else 0.0) + 1.2 * buildK
        val crackGlow = taps * 0.45 + 0.4 * tapFlash + 1.0 * buildK
        val flipT = if (d.tease && d.tapTimes.size >= 2) now - d.tapTimes[1] else null
        val goldMix = if (gold) (flipT?.let { GachaFade.rise(0.0, 0.22, it) } ?: 1.0) else 0.0

        // 바닥 그림자(무대 위에서)
        val shadowC = Offset(p.c.x, GLayout.stageCenter.y + GLayout.capsuleBig * 0.62f)
        drawOval(
            Brush.radialGradient(listOf(Color.Black.copy(alpha = GachaFade.f((if (theme.dark) 0.32 else 0.16) * recedeFade)), Color.Black.copy(alpha = 0f)), center = shadowC, radius = p.d * 0.45f),
            Offset(shadowC.x - p.d * 0.45f, shadowC.y - p.d * 0.1f), Size(p.d * 0.9f, p.d * 0.2f),
        )
        if (halo > 0.001 || beams > 0.001) {
            drawLeakLight(cracks, d.tapTimes, now, beams, halo, rare, p.c, p.d, p.rot.toFloat(), if (gold) BlendMode.Plus else BlendMode.SrcOver)
        }
        val ballAlpha = p.alpha
        withTransform({
            rotate(p.rot.toFloat(), p.c)
            scale(p.sx.toFloat(), p.sy.toFloat(), p.c)
        }) {
            val rect = rectCentered(p.c, p.d)
            val filter = brightnessFilter(p.bright.toFloat())
            drawHeroBall(sprites, rect, pair, null, GachaFade.f(ballAlpha * (1 - goldMix)), filter)
            if (goldMix > 0 && rare != null) drawHeroBall(sprites, rect, pair, rare, GachaFade.f(ballAlpha * goldMix), filter)
            if (rare != null) {
                drawCircle(
                    Brush.radialGradient(listOf(rare.light.copy(alpha = GachaFade.f(0.35 * goldPulse * ballAlpha)), Color.Transparent), center = Offset(rect.left + rect.width * 0.4f, rect.top + rect.height * 0.35f), radius = p.d * 0.5f),
                    p.d / 2, p.c, blendMode = BlendMode.Plus,
                )
            }
            if (taps > 0) {
                drawCrackOverlay(cracks, d.tapTimes, now, crackGlow, rare, p.c, p.d)
                // 톡 칠 때마다 안쪽이 환해진다
                drawCircle(
                    Brush.radialGradient(listOf(Color.White.copy(alpha = GachaFade.f((0.55 * tapFlash + 0.3 * buildK) * ballAlpha)), Color.Transparent), center = p.c, radius = p.d * 0.55f),
                    p.d / 2, p.c, blendMode = BlendMode.Plus,
                )
            }
        }
        // 반전: 황금(무지개)으로 바뀌는 순간 빛 고리
        if (flipT != null && flipT < 0.7) {
            val grow = 1 + 1.6 * GMath.easeOutCubic(flipT / 0.7)
            drawCircle(
                (rare ?: GRare.Gold).light.copy(alpha = GachaFade.f(0.9 * GachaFade.fall(0.0, 0.7, flipT))),
                (p.d * grow / 2).toFloat(), p.c, style = Stroke((10 * (1 - flipT / 0.7) + 1).toFloat()), blendMode = BlendMode.Plus,
            )
        }
    }

    // MARK: 공개(터짐 · 캐릭터 · 조각)

    fun drawReveal(s: DrawScope) = with(s) {
        val rt = revealT ?: return@with
        val r = d.result ?: return@with
        val rare = GRare.of(r.kind)
        val gold = rare != null
        if (d.reduced) {
            drawLightBurst(rt, rare, GLayout.stageCenter, gold || theme.raysOnDark, 0.0, reduced = true)
            val fade = GTiming.Reduced.fade
            if (rt < fade) drawHeroBall(sprites, rectCentered(GLayout.tray, GLayout.capsuleSmall), d.dropPair, rare, GachaFade.f(GachaFade.fall(0.0, fade, rt)))
            val cond = if (r.kind == GachaRevealKind.Duplicate) GMath.smooth(GTiming.Reduced.dupSwap, GTiming.Reduced.dupSwap + fade, rt) else 0.0
            val condFade = if (r.kind == GachaRevealKind.Duplicate) GachaFade.rise(GTiming.Reduced.dupSwap, GTiming.Reduced.dupSwap + fade, rt) else 0.0
            val img = portrait.image(r.characterID) ?: return@with
            val size = portraitSize(gold)
            drawImageIn(
                img, rectCentered(GLayout.stageCenter, size),
                alpha = GachaFade.f(GachaFade.rise(0.0, fade, rt) * GMath.lerp(1.0, 0.25, condFade)),
                colorFilter = saturationBrightnessFilter((1 - cond).toFloat(), 0f),
            )
            return@with
        }
        drawLightBurst(rt, rare, GLayout.stageCenter, gold || theme.raysOnDark, burstSpin(r, rt))
        drawCapsuleHalves(this, r, rt)
        drawCharacter(this, r, rt)
        if (r.kind == GachaRevealKind.Duplicate && liveId == null) drawShardFlight(this, rt)
    }

    /** 살아 있는 미리보기 위로 날아가는 조각(초상일 때와 같은 겹 순서 — 캐릭터 위). */
    fun drawShardsOverLive(s: DrawScope) = with(s) {
        val rt = revealT ?: return@with
        if (d.result?.kind == GachaRevealKind.Duplicate) drawShardFlight(this, rt)
    }

    /** 빛줄기 회전 각: 처음엔 돌다가 잔잔한 움직임이 잦아드는 동안 같이 멈춘다(각속도 × 봉투의 적분 — 튀지 않는다). */
    private fun burstSpin(r: GachaRevealOutcome, rt: Double): Double {
        val speed = if (r.kind.isRare) 0.10 else 0.16
        val end = GTiming.revealOneShotEnd(r.kind) + GTiming.revealAmbientGrace
        return speed * GMath.fadeIntegral(end, end + GTiming.ambientFade, rt)
    }

    private fun drawCapsuleHalves(s: DrawScope, r: GachaRevealOutcome, rt: Double) = with(s) {
        if (rt >= 0.8) return@with
        val rare = GRare.of(r.kind)
        val gold = rare != null
        val center = GLayout.stageCenter
        val capD = GLayout.capsuleBig * (if (gold) 1.12f else 1f)
        val g = 900.0
        val k = if (gold) 1.15 else 1.0
        val fade = GachaFade.fall(0.18, if (gold) 0.7 else 0.55, rt)
        val scale = (1 + 0.15 * rt).toFloat()
        fun half(upper: Boolean, x: Double, y: Double, angle: Double) {
            val c = Offset(x.toFloat(), y.toFloat())
            withTransform({ rotate(angle.toFloat(), c); scale(scale, scale, c) }) {
                drawImageIn(sprites.heroHalf(upper, d.dropPair, rare), rectCentered(c, capD), GachaFade.f(fade))
            }
        }
        half(true, center.x - 150 * rt * k, center.y - 320 * rt * k + 0.5 * g * rt * rt, -230 * rt * k)
        half(false, center.x + 125 * rt * k, center.y + 30 * rt * k + 0.5 * g * rt * rt, 170 * rt * k)
    }

    /** 공개 캐릭터 한 장의 자리 · 배율 · 불투명도(초상 캔버스와 살아 있는 미리보기가 같이 쓴다). */
    class CharacterPose(val center: Offset, val scale: Float, val opacity: Float, val size: Float, val cond: Double)

    fun characterPose(r: GachaRevealOutcome, rt: Double): CharacterPose {
        val gold = GRare.of(r.kind) != null
        val delay = if (gold) 0.08 else 0.02
        val s0 = if (gold) 0.3 else 0.25
        val sp = GMath.spring(rt - delay, if (gold) 0.42 else 0.40, if (gold) 1.6 else 2.3)
        val rise = GMath.spring(rt - delay, 0.5, if (gold) 1.5 else 2.0)
        val scale = s0 + (1 - s0) * sp
        // 둥실(잔잔한 움직임 — 잦아들면 제자리)
        val bob = -4 * sin(2 * PI * 0.45 * (rt - 0.8)) * GMath.smooth(0.7, 1.3, rt) * d.ambient(now)
        val cond = if (r.kind == GachaRevealKind.Duplicate) GMath.smooth(GTiming.dupCondense0, GTiming.dupCondense1, rt) else 0.0
        val condFade = if (r.kind == GachaRevealKind.Duplicate) GachaFade.rise(GTiming.dupCondense0, GTiming.dupCondense1, rt) else 0.0
        val c = Offset(GLayout.stageCenter.x, (GLayout.stageCenter.y + 26 * (1 - rise) + bob).toFloat())
        val sc = (scale * (1 - 0.12 * cond)).toFloat()
        val opacity = GachaFade.f(GachaFade.rise(delay, delay + 0.08, rt) * GMath.lerp(1.0, 0.2, condFade))
        return CharacterPose(c, sc, opacity, portraitSize(gold), cond)
    }

    private fun drawCharacter(s: DrawScope, r: GachaRevealOutcome, rt: Double) = with(s) {
        val rare = GRare.of(r.kind)
        val gold = rare != null
        val delay = if (gold) 0.08 else 0.02
        val p = characterPose(r, rt)
        val img = if (liveId != null) null else portrait.image(r.characterID) ?: return@with
        val c = p.center
        val sc = p.scale
        val size = p.size
        // 희귀는 그 빛깔 빛무리(원문 그림자의 자리 — 흐림 대신 방사형)
        val glow = rare?.primary ?: GPalette.hex(0x5B3FB8)
        val glowA = (if (gold) 0.5 else 0.25) * GachaFade.rise(delay, delay + 0.08, rt)
        drawCircle(Brush.radialGradient(listOf(glow.copy(alpha = GachaFade.f(glowA * 0.6)), glow.copy(alpha = 0f)), center = c, radius = size * 0.55f * sc), size * 0.55f * sc, c)
        // 살아 있는 미리보기가 그리는 캐릭터는 여기서 그리지 않는다(빛무리만 — 그 위에 [RevealLive]).
        if (img == null) return@with
        withTransform({ scale(sc, sc, c) }) {
            drawImageIn(
                img, rectCentered(c, size),
                alpha = p.opacity,
                colorFilter = saturationBrightnessFilter((1 - p.cond).toFloat(), (0.5 * sin(PI * min(1.0, p.cond * 1.15))).toFloat()),
            )
        }
    }

    /** 중복: 캐릭터의 빛이 모여 결정이 되고, 칩으로 날아간다. */
    private fun drawShardFlight(s: DrawScope, rt: Double) = with(s) {
        val c0 = GTiming.dupCondense0
        val c1 = GTiming.dupCondense1
        val fly1 = GTiming.dupFly1
        if (rt <= c0 || rt >= fly1) return@with
        val gather = GMath.smooth(c0, c1, rt)
        val gatherFade = GachaFade.rise(c0, c1, rt)
        val born = GMath.easeOutBack(GMath.ramp(c0 + 0.6 * (c1 - c0), c1 + 0.05, rt))
        val q = GMath.ramp(c1, fly1, rt)
        val ctrl = Offset(40f, 190f)
        fun path(x: Double): Offset = GMath.bezier(GLayout.stageCenter, ctrl, GLayout.shardChip, GMath.easeInOutCubic(x))
        val size = GMath.lerp(46.0, 18.0, GMath.easeInCubic(q)) * born
        val orbR = (GMath.lerp(120.0, 34.0, GMath.easeInOutCubic(gather)) * GMath.lerp(1.0, 0.5, q)).toFloat()
        val orbA = (0.25 + 0.7 * gatherFade) * (1 - 0.4 * q)
        // 빛 꼬리(진한 보라 → 옅게)
        if (q > 0) {
            for (i in 1 until 7) {
                val qq = max(0.0, q - i * 0.04)
                val k = 1 - i / 7.0
                drawCircle(theme.shardTrail.copy(alpha = GachaFade.f(0.55 * k)), (size * (1.0 - i * 0.1) / 2).toFloat().coerceAtLeast(0f), path(qq))
            }
        }
        val at = path(q)
        drawCircle(
            Brush.radialGradient(
                0f to Color.White.copy(alpha = GachaFade.f(orbA)),
                0.35f to GPalette.hex(0xD6C4FF, GachaFade.f(0.75 * orbA)),
                0.7f to theme.shardOrbEdge.copy(alpha = GachaFade.f(0.45 * orbA)),
                1f to theme.shardOrbEdge.copy(alpha = 0f),
                center = at, radius = orbR.coerceAtLeast(1f),
            ),
            orbR.coerceAtLeast(1f), at,
        )
        if (born > 0.01) drawShardGem(at, size.toFloat(), theme.shardOutline, (-20 + 380 * GMath.easeInOutCubic(q)).toFloat())
    }

    fun drawOutgoing(s: DrawScope) = with(s) {
        val o = d.outgoing ?: return@with
        val ot = d.outgoingTime ?: return@with
        val tt = now - ot
        if (tt >= 0.35) return@with
        val img = portrait.image(o.characterID) ?: return@with
        val size = portraitSize(o.kind.isRare)
        val sc = if (still) 1f else (1 - 0.25 * tt / 0.35).toFloat()
        val a = if (o.kind == GachaRevealKind.Duplicate) 0.2 * GachaFade.fall(0.0, 0.3, tt) else GachaFade.fall(0.0, 0.3, tt)
        withTransform({ scale(sc, sc, GLayout.stageCenter) }) { drawImageIn(img, rectCentered(GLayout.stageCenter, size), GachaFade.f(a)) }
    }

    // MARK: 섬광

    fun drawFlash(s: DrawScope) = with(s) {
        // 일반: 흰 섬광(밝은 바탕) · 옅은 라벤더(어두운 바탕). 황금: 더하기 합성의 따뜻한 빛. 동작 줄이기: 섬광 없음.
        val rare = d.rare
        val gold = rare != null
        val a = if (d.reduced) 0.0 else when (ph) {
            // 원문 0.95·e^(−4.5t) · peak·e^(−7.5t) 의 자리 — 같은 꼭대기에서 직선으로.
            is GPhase.Reveal -> if (gold) GachaFade.decay(ph.t, 0.55, 0.95) else GachaFade.decay(ph.t, 0.35, theme.flashPeak.toDouble())
            is GPhase.Building -> if (gold) 0.22 * GachaFade.rise(GTiming.goldBuild - 0.3, GTiming.goldBuild, ph.t) else 0.0
            is GPhase.Tapping -> if (d.tease && d.tapTimes.size >= 2) GachaFade.decay(now - d.tapTimes[1], 0.3, 0.45) else 0.0
            else -> 0.0
        }
        if (a <= 0.005) return@with
        val r = bleedRect()
        if (rare != null) {
            drawRect(Brush.radialGradient(rare.flash, center = GLayout.stageCenter, radius = 380f), r.topLeft, r.sizeOf(), alpha = GachaFade.f(a), blendMode = BlendMode.Plus)
        } else {
            drawRect(theme.flash, r.topLeft, r.sizeOf(), alpha = GachaFade.f(a))
        }
    }
}

// MARK: - 기계 무리(몸통 · 덮개 · 손잡이 — 한 덩어리로 물러난다)

@Composable
private fun MachineGroup(f: StageFrame) {
    val d = f.d
    val r = f.recede
    val (ox, oy, squash) = f.shake
    val scale = if (f.still) 1.0 else 1 - 0.06 * r
    Box(
        Modifier
            .fillMaxSize()
            .graphicsLayer {
                scaleX = (scale + squash * 0.4).toFloat()
                scaleY = (scale - squash).toFloat()
                transformOrigin = TransformOrigin(0.5f, 0.88f)
                translationX = (ox * density).toFloat()
                translationY = ((oy + if (f.still) 0.0 else 6 * r) * density).toFloat()
                alpha = GachaFade.f(1 - 0.76 * f.recedeFade)
            },
    ) {
        Canvas(Modifier.fillMaxSize()) { design { f.drawMachineBack(this) } }
        ChuteFlap(f)
        Canvas(Modifier.fillMaxSize()) { design { f.drawMachineFront(this) } }
        KnobTarget(f)
    }
}

/** 배출구 덮개. 캡슐이 나올 때 위 경첩을 축으로 바깥으로 젖혀졌다가 닫힌다(닫힐 때 살짝 흔들린다). */
@Composable
private fun ChuteFlap(f: StageFrame) {
    val open = f.flapOpen()
    val art = f.env.art
    val moving = kotlin.math.abs(open) > 0.002
    val r = GLayout.flapRect
    val body = art.body
    if (body != null && !moving) return // 닫힌 순간엔 아무것도 안 그린다 — 몸통 그림 그대로다.
    // 원래 덮개 자리 = 배출구 안쪽
    Canvas(Modifier.fillMaxSize()) {
        design {
            if (!moving) return@design
            val inner = Rect(r.left + 2f, r.top + 2f, r.right - 2f, r.bottom - 2f)
            if (body != null) {
                drawRoundRect(Brush.verticalGradient(listOf(GPalette.hex(0x1D0F2B), GPalette.hex(0x2A1638)), inner.top, inner.bottom), inner.topLeft, inner.sizeOf(), CornerRadius(GLayout.flapCorner))
            } else {
                drawRoundRect(GPalette.hex(0x2C1F57), inner.topLeft, inner.sizeOf(), CornerRadius(GLayout.flapCorner))
            }
        }
    }
    Box(
        Modifier
            .centerAt(r.center.x, r.center.y)
            .size(r.width.dp, r.height.dp)
            .graphicsLayer {
                rotationX = (MAX_FLAP_ANGLE * open).toFloat()
                transformOrigin = TransformOrigin(0.5f, 0f)
                cameraDistance = 6f * density
            },
    ) {
        Canvas(Modifier.fillMaxSize()) {
            design {
                val shape = Path().apply { addRoundRect(androidx.compose.ui.geometry.RoundRect(Rect(0f, 0f, r.width, r.height), CornerRadius(GLayout.flapCorner))) }
                if (body != null) {
                    clipPath(shape) {
                        drawImageIn(
                            body, Rect(GLayout.bodyOrigin.x - r.left, GLayout.bodyOrigin.y - r.top, GLayout.bodyOrigin.x - r.left + GLayout.bodySize.width, GLayout.bodyOrigin.y - r.top + GLayout.bodySize.height),
                            colorFilter = brightnessFilter((0.06 * max(0.0, open)).toFloat()),
                        )
                    }
                } else {
                    drawPath(shape, Brush.verticalGradient(listOf(GPalette.hex(0xE9DEFF, 0.55f), GPalette.hex(0xB9A0F5, 0.45f)), 0f, r.height))
                    drawPath(shape, Color.White.copy(alpha = 0.6f), style = Stroke(1.2f))
                }
            }
        }
    }
}

private const val MAX_FLAP_ANGLE = 74.0

/** 손잡이 잡는 자리(보이지 않음, 112 원). 대기 중 · 자동 회전 · [한 번 더] 예약이 없을 때만 받는다. */
@Composable
private fun KnobTarget(f: StageFrame) {
    val d = f.d
    val active = f.idle && d.autoTurnStart == null && d.againAt == null
    val side = 112f
    val origin = Offset(GLayout.knobCenter.x - side / 2, GLayout.knobCenter.y - side / 2)
    val input = if (!active) Modifier else Modifier.pointerInput(d) {
        awaitEachGesture {
            val down = awaitFirstDown()
            down.consume()
            val start = down.position
            fun design(p: Offset) = Offset(origin.x + p.x / density, origin.y + p.y / density)
            var ended = false
            try {
                d.dragChanged(design(down.position), Offset.Zero)
                while (true) {
                    val event = awaitPointerEvent()
                    val change = event.changes.firstOrNull { it.id == down.id } ?: break
                    if (!change.pressed) {
                        ended = true
                        d.dragEnded()
                        break
                    }
                    change.consume()
                    d.dragChanged(design(change.position), (change.position - start) / density)
                }
            } finally {
                // 취소(전화 · 시스템 알림 · 창이 내려감): 클릭으로 치지 않고 풀기만 한다(루비가 안 나간다).
                if (!ended) d.dragCancelled()
            }
        }
    }
    Box(
        Modifier
            .centerAt(GLayout.knobCenter.x, GLayout.knobCenter.y)
            .size(side.dp)
            .then(input)
            .semantics {
                role = Role.Button
                contentDescription = GachaMachineText.handleLabel
                onClick(label = GachaMachineText.handleHint(f.env.cost)) { d.autoTurn(); true }
            },
    )
}

// MARK: - 글자

@Composable
private fun WarnPill(f: StageFrame, rf: Double, modifier: Modifier, content: @Composable () -> Unit) {
    val dx = if (f.still) 0.0 else 6 * GMath.ring(rf, 7.0, 7.0)
    val sc = if (f.still) 1.0 else 1 + 0.06 * kotlin.math.exp(-8 * rf)
    Box(
        modifier
            .graphicsLayer { translationX = (dx * density).toFloat(); scaleX = sc.toFloat(); scaleY = sc.toFloat() }
            .widthMax(344f)
            .background(f.theme.pillFill, CircleShape)
            .padding(horizontal = 12.dp, vertical = 6.dp),
    ) { content() }
}

private fun Modifier.widthMax(points: Float): Modifier = layout { m, c ->
    val p = m.measure(c.copy(maxWidth = min(c.maxWidth, points.dp.roundToPx())))
    layout(p.width, p.height) { p.place(0, 0) }
}

@Composable
private fun TextLayer(f: StageFrame) {
    val d = f.d
    val theme = f.theme
    val env = f.env
    Box(Modifier.fillMaxSize()) {
        when (val ph = f.ph) {
            GPhase.Idle -> {
                val rf = d.refuseTime?.let { f.now - it } ?: 9.0
                val reason = env.blockedReason
                val style = stageText(13f, FontWeight.SemiBold)
                if (reason != null) {
                    WarnPill(f, rf, Modifier.centerAt(GLayout.midX, GLayout.hintY).alpha(GachaFade.f(1 - f.recedeFade))) {
                        Text(reason, style = style, color = theme.warn, textAlign = TextAlign.Center, maxLines = 2)
                    }
                } else if (env.canPay) {
                    Row(
                        Modifier.centerAt(GLayout.midX, GLayout.hintY).alpha(GachaFade.f((1 - f.recedeFade) * (if (d.dragging) 0.5 else 1.0))),
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp),
                    ) {
                        Text(GachaMachineText.idleHint, style = style, color = theme.ink)
                        RubyGlyph(f, 15f)
                        Text("${env.cost}", style = style, color = theme.ink)
                    }
                } else {
                    WarnPill(f, rf, Modifier.centerAt(GLayout.midX, GLayout.hintY).alpha(GachaFade.f(1 - f.recedeFade))) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                            Text(GachaMachineText.shortHead, style = style, color = theme.warn)
                            RubyGlyph(f, 15f)
                            Text(GachaMachineText.shortTail(env.cost), style = style, color = theme.warn)
                        }
                    }
                }
            }
            is GPhase.Shaking -> if (ph.pending && ph.t > 0.9) {
                val dots = ((ph.t * 3) % 4).toInt()
                val pulse = if (f.still) 1.0 else 1 + 0.05 * sin(2 * PI * 1.6 * ph.t)
                Box(Modifier.centerAt(GLayout.midX + 28f, GLayout.hintY).width(120.dp)) {
                    Text(
                        GachaMachineText.waiting + "·".repeat(if (f.still) 3 else dots),
                        style = stageText(13f, FontWeight.SemiBold), color = theme.ink,
                        modifier = Modifier.graphicsLayer { scaleX = pulse.toFloat(); scaleY = pulse.toFloat() }.alpha(GachaFade.f(GachaFade.rise(0.9, 1.2, ph.t))),
                    )
                }
            }
            is GPhase.Failed -> WarnPill(
                f, 9.0,
                Modifier.centerAt(GLayout.midX, GLayout.hintY).alpha(GachaFade.f(GachaFade.rise(0.0, 0.15, ph.t) * GachaFade.fall(GTiming.failHold - 0.3, GTiming.failHold, ph.t))),
            ) { Text(d.failText, style = stageText(13f, FontWeight.SemiBold), color = theme.warn, textAlign = TextAlign.Center, maxLines = 2) }
            is GPhase.Tapping -> TapHint(f, ph.taps)
            is GPhase.Reveal -> {
                val r = d.result
                if (r != null) {
                    Box(
                        Modifier.fillMaxSize().clearAndSetSemantics {
                            contentDescription = GachaMachineText.announcement(r)
                            liveRegion = LiveRegionMode.Polite
                        },
                    ) { RevealTexts(f, r, ph.t) }
                }
            }
            else -> Unit
        }
    }
}

@Composable
private fun TapHint(f: StageFrame, n: Int) {
    val d = f.d
    val arrive = d.dropStart?.let { f.now - it - d.drop.jump1 } ?: 0.0
    val a = GachaFade.rise(0.1, 0.4, arrive)
    val dark = f.rareShown || f.dimAmount > 0.3 || f.theme.dark
    val ink = if (f.rareShown || f.dimAmount > 0.3) Color.White else f.theme.ink
    val pulse = 1 + 0.04 * sin(2 * PI * 1.2 * f.now) * d.ambient(f.now)
    Column(
        Modifier.centerAt(GLayout.midX, 300f).alpha(GachaFade.f(a)).clearAndSetSemantics { },
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(7.dp),
    ) {
        Text(
            when (n) { 0 -> GachaMachineText.tapFirst; 1 -> GachaMachineText.tapSecond; else -> GachaMachineText.tapLast },
            style = stageText(15f, FontWeight.Bold), color = ink,
            modifier = Modifier.graphicsLayer { scaleX = pulse.toFloat(); scaleY = pulse.toFloat() },
        )
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            repeat(3) { i -> Box(Modifier.size(7.dp).background(if (i < n) ink else ink.copy(alpha = 0.28f), CircleShape)) }
        }
    }
    // 건너뛰기(톡백은 이걸로 캡슐을 연다). 밝은 바탕엔 [닫기] 와 같은 흰 알약 + 진한 라벤더 글자(≥ 4.5:1).
    Box(
        Modifier
            .centerAt(336f, GLayout.hintY)
            .alpha(GachaFade.f(a))
            .background(if (dark) Color.White.copy(alpha = 0.12f) else f.theme.closeFill, CircleShape)
            .border(1.dp, if (dark) Color.Transparent else f.theme.closeStroke, CircleShape)
            .clickable(remember { MutableInteractionSource() }, null) { d.skipTaps() }
            .semantics { contentDescription = GachaMachineText.openCapsule; role = Role.Button }
            .padding(horizontal = 10.dp, vertical = 5.dp),
    ) {
        Text(GachaMachineText.skip, style = stageText(12f, FontWeight.SemiBold), color = if (dark) ink.copy(alpha = 0.75f) else f.theme.closeText)
    }
}

/** 공개 글자. 정상 연출과 동작 줄이기가 **같은 글자**를 쓴다(시각 · 움직임만 다르다). */
@Composable
private fun RevealTexts(f: StageFrame, r: GachaRevealOutcome, rt: Double) {
    val reduced = f.d.reduced
    val theme = f.theme
    val badgeAt = if (reduced) GTiming.Reduced.badgeAt else GTiming.badgeAt
    val nameAt = if (reduced) GTiming.Reduced.nameAt else GTiming.nameAt
    val badgeT = rt - badgeAt
    val badgeS = if (reduced) 1.0 else 0.5 + 0.5 * GMath.spring(badgeT, 0.45, 2.6)
    val badgeA = GachaFade.rise(0.0, if (reduced) 0.25 else 0.1, badgeT)
    val nameA = GachaFade.rise(nameAt, nameAt + if (reduced) 0.3 else 0.2, rt)
    val nameY = if (reduced) 0.0 else 8 * (1 - GMath.easeOutCubic((rt - nameAt) / 0.3))
    val title = stageText(24f, FontWeight.ExtraBold)
    when (r.kind) {
        GachaRevealKind.New, GachaRevealKind.Duplicate -> {
            val filled = r.kind == GachaRevealKind.New
            Badge(f, GachaMachineText.badge(r) ?: "", filled, Modifier.centerAt(GLayout.midX, 92f).graphicsLayer { scaleX = badgeS.toFloat(); scaleY = badgeS.toFloat() }.alpha(GachaFade.f(badgeA)))
            val nameModifier = Modifier.centerAt(GLayout.midX, 300f).graphicsLayer { translationY = (nameY * density).toFloat() }.alpha(GachaFade.f(nameA))
            if (filled) {
                Text(GachaMachineText.title(r), style = title, color = theme.title, modifier = nameModifier)
            } else {
                val swap = if (reduced) GTiming.Reduced.dupSwap else GTiming.dupCondense1
                val fadeLen = if (reduced) GTiming.Reduced.fade else 0.16
                val out = GachaFade.rise(swap - if (reduced) 0.0 else 0.15, swap + if (reduced) fadeLen else 0.0, rt)
                val inn = GachaFade.rise(swap - if (reduced) 0.0 else 0.04, swap + fadeLen, rt)
                val outMove = GMath.easeInCubic(GMath.ramp(swap - if (reduced) 0.0 else 0.15, swap + if (reduced) fadeLen else 0.0, rt))
                val innMove = GMath.easeOutCubic(GMath.ramp(swap - if (reduced) 0.0 else 0.04, swap + fadeLen, rt))
                val innScale = if (reduced) 1.0 else 0.92 + 0.08 * GMath.spring(rt - swap, 0.45, 2.6)
                Box(nameModifier, contentAlignment = Alignment.Center) {
                    Text(
                        r.name, style = title, color = theme.title,
                        modifier = Modifier.graphicsLayer { translationY = (if (reduced) 0.0 else -12 * outMove).toFloat() * density }.alpha(GachaFade.f(1 - out)),
                    )
                    Row(
                        Modifier.graphicsLayer {
                            translationY = (if (reduced) 0.0 else 12 * (1 - innMove)).toFloat() * density
                            scaleX = innScale.toFloat(); scaleY = innScale.toFloat()
                        }.alpha(GachaFade.f(inn)),
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        Text(GachaMachineText.shardLine(r), style = title, color = theme.title)
                        Text(GachaMachineText.shardGain(r), style = title, color = theme.accent)
                    }
                }
            }
        }
        GachaRevealKind.Gold, GachaRevealKind.Rainbow -> {
            val rare = GRare.of(r.kind) ?: GRare.Gold
            val titleAt = if (reduced) GTiming.Reduced.nameAt else GTiming.goldTitleAt
            val subAt = if (reduced) GTiming.Reduced.nameAt + 0.3 else GTiming.goldSubAt
            val tt = rt - titleAt
            val sc = if (reduced) 1.0 else 0.6 + 0.4 * GMath.spring(tt, 0.45, 2.0)
            ShimmerTitle(
                GachaMachineText.title(r), 30f, max(0.0, rt - titleAt - 0.3), if (reduced) 0 else 2, rare,
                Modifier.centerAt(GLayout.midX, 306f).graphicsLayer { scaleX = sc.toFloat(); scaleY = sc.toFloat() }.alpha(GachaFade.f(GachaFade.rise(0.0, if (reduced) 0.3 else 0.15, tt))),
            )
            Text(
                GachaMachineText.goldSubtitle(r), style = stageText(14f, FontWeight.SemiBold), color = rare.light.copy(alpha = 0.9f),
                modifier = Modifier.centerAt(GLayout.midX, 340f).alpha(GachaFade.f(GachaFade.rise(subAt, subAt + 0.3, rt))),
            )
        }
    }
}

@Composable
private fun Badge(f: StageFrame, text: String, filled: Boolean, modifier: Modifier) {
    val theme = f.theme
    val fill = if (filled) Brush.verticalGradient(listOf(GPalette.hex(0xB197FF), GPalette.hex(0x8C6CF2))) else Brush.verticalGradient(listOf(theme.badgeFill, theme.badgeFill))
    Box(
        modifier
            .background(fill, CircleShape)
            .border(1.dp, if (filled) Color.White.copy(alpha = 0.5f) else theme.chipStroke.copy(alpha = if (theme.dark) 1f else 0f), CircleShape)
            .padding(horizontal = 14.dp, vertical = 6.dp),
    ) {
        Text(text, style = stageText(14f, FontWeight.Bold), color = if (filled) Color.White else theme.badgeText)
    }
}

/** 금빛(무지개빛) 글자 + 지나가는 반짝임([passes] 번 뒤엔 멈춘 글자). 글자 붓은 [AingTextPaint] 로만 건다(짧은 글자 그라데이션 금지 규칙). */
@Composable
private fun ShimmerTitle(text: String, size: Float, t: Double, passes: Int, rare: GRare, modifier: Modifier) {
    val base = stageText(size, FontWeight.ExtraBold)
    val cycle = 2.4
    val index = (max(0.0, t) / cycle).toInt()
    val p = if (index < passes) (t % cycle) / 1.2 else 2.0
    val fill = AingTextPaint.textBrushOrNull(text, rare.titleStops)?.let { horizontal ->
        if (rare.titleVertical) Brush.verticalGradient(rare.titleStops) else horizontal
    }
    Box(modifier) {
        // 둘레 빛(원문 shadow 의 자리 — 살짝 큰 테두리 글자 대신 같은 글자를 빛 색으로 한 번 깐다)
        Text(text, style = base, color = rare.titleEdge, modifier = Modifier.graphicsLayer { translationY = density })
        if (fill != null) Text(text, style = AingTextPaint.withBrush(base, fill)) else Text(text, style = base, color = AingTextPaint.solidFor(rare.titleStops, rare.primary))
        if (p < 1) {
            val x = GMath.lerp(-0.4, 1.4, GMath.easeInOutCubic(p))
            val band = AingTextPaint.textBrushOrNull(text, listOf(Color.Transparent, Color.White.copy(alpha = 0.95f), Color.Transparent))
            if (band != null) {
                val shifted = ShimmerBand(x.toFloat())
                Text(text, style = AingTextPaint.withBrush(base, shifted))
            }
        }
    }
}

/** 지나가는 흰 띠(글자 폭 비율 [x] 에 가운데). */
private class ShimmerBand(private val x: Float) : androidx.compose.ui.graphics.ShaderBrush() {
    override fun createShader(size: Size): androidx.compose.ui.graphics.Shader =
        androidx.compose.ui.graphics.LinearGradientShader(
            from = Offset(size.width * (x - 0.18f), size.height * 0.2f),
            to = Offset(size.width * (x + 0.18f), size.height * 0.8f),
            colors = listOf(Color.Transparent, Color.White.copy(alpha = 0.95f), Color.Transparent),
        )
}

// MARK: - 칩

@Composable
private fun RubyGlyph(f: StageFrame, side: Float) {
    val ruby = LocalStageRuby.current
    Canvas(Modifier.size(side.dp)) { if (ruby != null) design { drawImageIn(ruby, Rect(0f, 0f, side, side)) } }
}

private val LocalStageRuby = staticCompositionLocalOf<ImageBitmap?> { null }

@Composable
private fun Chips(f: StageFrame) {
    val d = f.d
    val theme = f.theme
    val r = d.result
    val land = r?.let { GTiming.shardLandAt(it, d.reduced) }
    val rt = f.revealT
    val count: Long
    val landT: Double?
    if (r != null && land != null) {
        if (rt != null && rt >= land) { count = r.shardCountAfter; landT = rt - land } else { count = r.shardCountBefore; landT = null }
    } else if (r != null) {
        count = r.shardCountAfter; landT = null
    } else {
        count = f.env.shards; landT = null
    }
    val pulse = if (f.still) 1.0 else landT?.let { 1 + 0.32 * GMath.ringCos(it, 2.6, 7.0) } ?: 1.0
    // 원문 e^(−2.2t) 의 자리 — 직선으로 1.2초.
    val glow = landT?.let { GachaFade.decay(it, 1.2) } ?: 0.0
    run {
        Box(Modifier.fillMaxSize()) {
            // 조각 칩
            Row(
                Modifier
                    .centerAt(GLayout.shardChip.x, GLayout.shardChip.y)
                    .graphicsLayer { scaleX = pulse.toFloat(); scaleY = pulse.toFloat() }
                    .background(theme.chipFill, CircleShape)
                    .background(GPalette.hex(if (theme.dark) 0x6A4FC8 else 0xD9C8FF, GachaFade.f(0.95 * glow)), CircleShape)
                    .border(1.dp, theme.chipStroke.copy(alpha = GachaFade.f(1 - glow)), CircleShape)
                    .border(2.dp, GPalette.hex(if (theme.dark) 0xE4D8FF else 0x7B5CE6, GachaFade.f(glow)), CircleShape)
                    .clearAndSetSemantics { contentDescription = GachaMachineText.shardLabel(count) }
                    .padding(horizontal = 10.dp, vertical = 5.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp),
            ) {
                Canvas(Modifier.size(15.dp)) { design { drawShardGem(Offset(7.5f, 7.5f), 15f) } }
                Text("조각 $count", style = stageText(13f, FontWeight.Bold), color = theme.chipText)
            }
            if (landT != null && landT < 1.6) {
                // 들어온 순간 칩에서 퍼지는 고리(동작 줄이기: 없음)
                if (!f.still && landT < 0.6) {
                    val p = landT / 0.6
                    Canvas(Modifier.fillMaxSize()) {
                        design {
                            val w = (84 + 50 * GMath.easeOutCubic(p)).toFloat()
                            val h = (28 + 30 * GMath.easeOutCubic(p)).toFloat()
                            val rr = Rect(GLayout.shardChip.x - w / 2, GLayout.shardChip.y - h / 2, GLayout.shardChip.x + w / 2, GLayout.shardChip.y + h / 2)
                            drawRoundRect(theme.shardTrail.copy(alpha = GachaFade.f(0.85 * GachaFade.fall(0.0, 1.0, p))), rr.topLeft, rr.sizeOf(), CornerRadius(h / 2), style = Stroke((3 * (1 - p) + 1).toFloat()))
                        }
                    }
                }
                val dy = 30 + if (f.still) 0.0 else 8 * GMath.easeOutCubic(landT / 0.8)
                Box(
                    Modifier
                        .centerAt(GLayout.shardChip.x, (GLayout.shardChip.y + dy).toFloat())
                        .alpha(GachaFade.f(GachaFade.rise(0.0, 0.1, landT) * GachaFade.fall(1.0, 1.6, landT)))
                        .background(theme.chipFill, CircleShape)
                        .border(1.dp, theme.chipStroke, CircleShape)
                        .clearAndSetSemantics { }
                        .padding(horizontal = 8.dp, vertical = 3.dp),
                ) {
                    Text(GachaMachineText.chipGain(r ?: GachaRevealOutcome("", "", GachaRevealKind.Duplicate)), style = stageText(12f, FontWeight.ExtraBold), color = theme.accentStrong)
                }
            }
            // 루비 칩
            val ct = d.commitTime?.let { f.now - it }
            val rubyPulse = if (f.still) 1.0 else ct?.let { 1 + 0.08 * GMath.ringCos(it, 3.0, 9.0) } ?: 1.0
            Row(
                Modifier
                    .centerAt(GLayout.rubyChip.x, GLayout.rubyChip.y)
                    .graphicsLayer { scaleX = rubyPulse.toFloat(); scaleY = rubyPulse.toFloat() }
                    .background(theme.chipFill, CircleShape)
                    .border(1.dp, theme.chipStroke, CircleShape)
                    .clearAndSetSemantics { contentDescription = GachaMachineText.rubyLabel(f.env.balance) }
                    .padding(horizontal = 10.dp, vertical = 5.dp),
                verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp),
            ) {
                RubyGlyph(f, 18f)
                Text("${f.env.balance}", style = stageText(14f, FontWeight.Bold), color = theme.chipText)
            }
            if (ct != null && ct < 1.1 && d.failTime == null) {
                val dy = 22 + if (f.still) 6.0 else 14 * GMath.easeOutCubic(ct / 0.9)
                Text(
                    "-${f.env.cost}", style = stageText(13f, FontWeight.ExtraBold), color = theme.spend,
                    modifier = Modifier.centerAt(GLayout.rubyChip.x, (GLayout.rubyChip.y + dy).toFloat())
                        .alpha(GachaFade.f(GachaFade.rise(0.0, 0.08, ct) * GachaFade.fall(0.6, 1.1, ct)))
                        .clearAndSetSemantics { },
                )
            }
        }
    }
}

// MARK: - 버튼

@Composable
private fun Buttons(f: StageFrame) {
    val d = f.d
    val rt = f.revealT ?: return
    val r = d.result ?: return
    val b = d.buttonsAt(r.kind)
    val a = GachaFade.rise(b, b + if (d.reduced) 0.3 else 0.22, rt)
    if (a <= 0) return
    val env = f.env
    val dark = r.kind.isRare
    val canAgain = env.canPull && env.againEnabled && !d.pullInFlight
    val dy = if (d.reduced) 0.0 else 16 * (1 - GMath.spring(rt - b, 0.6, 2.4))
    val style = stageText(15f, FontWeight.Bold)
    run {
        Box(Modifier.fillMaxSize()) {
            Row(
                Modifier.centerAt(GLayout.midX, 404f).graphicsLayer { translationY = (dy * density).toFloat() }.alpha(GachaFade.f(a)),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                val againShape = RoundedCornerShape(23.dp)
                Row(
                    Modifier
                        .size(170.dp, 46.dp)
                        .alpha(if (canAgain) 1f else 0.55f)
                        .background(Brush.verticalGradient(listOf(GPalette.hex(0xB197FF), GPalette.hex(0x8B6BF0))), againShape)
                        .border(1.dp, Color.White.copy(alpha = 0.35f), againShape)
                        .clickable(enabled = canAgain && a > 0.5, role = Role.Button) { d.again() }
                        .semantics { contentDescription = GachaMachineText.againLabel(env.cost) },
                    horizontalArrangement = Arrangement.spacedBy(5.dp, Alignment.CenterHorizontally), verticalAlignment = Alignment.CenterVertically,
                ) {
                    if (env.blockedReason == null && env.canPay) {
                        Text(GachaMachineText.again, style = style, color = Color.White)
                        RubyGlyph(f, 16f)
                        Text("${env.cost}", style = style, color = Color.White)
                    } else if (env.blockedReason == null) {
                        Text(GachaMachineText.againShort, style = style, color = Color.White)
                    } else {
                        Text(GachaMachineText.againBlocked, style = style, color = Color.White)
                    }
                }
                Box(
                    Modifier
                        .size(104.dp, 46.dp)
                        .background(if (dark) Color.White.copy(alpha = 0.14f) else f.theme.closeFill, againShape)
                        .border(1.dp, if (dark) Color.White.copy(alpha = 0.25f) else f.theme.closeStroke, againShape)
                        .clickable(enabled = a > 0.5, role = Role.Button) { env.onClose() },
                    contentAlignment = Alignment.Center,
                ) {
                    Text(GachaMachineText.close, style = style, color = if (dark) Color.White else f.theme.closeText)
                }
            }
        }
    }
}
