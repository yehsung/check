// 원본: Sources/CheckMobileKit/Me/MeTab.swift @ 3bd04bd (MeStageCard.stage — 무대 132pt + 발밑 빛(근무 상태 색). 그림 자리만 살아 있는 아잉이로)
// 원본: Sources/check/CheckOverlayReactions.swift @ 3bd04bd (몸 클릭 → hit · 유휴 6 / 활성 30fps · 렌더 정지 — 무대가 쓰는 몫)
package com.yehsung.aingcheck.android.screens.stage

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.neverEqualPolicy
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.yehsung.aingcheck.character.bake.BakeLibrary
import com.yehsung.aingcheck.character.math.Vec2
import com.yehsung.aingcheck.character.player.CharacterFrame
import com.yehsung.aingcheck.character.player.FramePacer
import com.yehsung.aingcheck.character.render.quadCanvasOf
import com.yehsung.aingcheck.core.stores.me.MeCharacterCards
import com.yehsung.aingcheck.ui.components.CharacterMood
import com.yehsung.aingcheck.ui.components.CharacterStage
import com.yehsung.aingcheck.ui.components.CharacterStageMetrics
import com.yehsung.aingcheck.ui.components.rememberStageArt
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull

/** 무대 시계(초, 단조). 앱은 [System], 시험은 손으로 민다. */
fun interface StageClock {
    fun now(): Double

    companion object {
        val System: StageClock = StageClock { java.lang.System.nanoTime() / 1e9 }
    }
}

/** 무대를 밖에서 보는 창(시험 · 진단). 앱 화면은 넘기지 않는다. */
class StageHandle {
    /** 마지막 구성에서 본 착용 id 와 실린 구운 마감(null = 라이브러리를 아직 못 읽음). */
    var characterId: String? = null
        internal set
    var bakedIds: Set<String>? = null
        internal set
    var mode: StageMode? = null
        internal set
    var director: StageDirector? = null
        internal set
    var store: StageStore? = null
        internal set
    var placement: StageFraming.Placement? = null
        internal set
    var lastTap: TapOutcome? = null
        internal set
    /** 새로 내보낸 프레임 수(같은 칸 · 0.25px 미만 이동은 세지 않는다 — F §5.4). */
    var framesPublished: Int = 0
        internal set
    /** 마지막으로 내보낸 프레임. */
    var lastFrame: CharacterFrame? = null
        internal set
}

/**
 * 살아 있는 아잉이 무대(결정 #2 — 나 탭 무대 · 캐릭터 고르기 · 뽑기 결과 공개 뒤). ui `CharacterStage(art, mood, artSize)` 와 **같은 자리 ·
 * 같은 크기**(그림 + 6 × 그림 + 12, 발밑 빛 그대로)라 무대를 그리던 화면이 칸(slot) 하나로 바꿔 끼운다(assembly.md).
 *  - 구운 아잉이(아잉 · 황금 · 무지개, 케이크 둘은 아잉으로 접힘)는 부유 · 살랑 · 깜빡임으로 살아 있고, 몸을 두드리면 hit.
 *  - 스프라이트 6종 · 모르는 id 와 자산을 아직(또는 끝내) 못 읽은 동안은 iOS 와 같은 초상 무대다.
 *  - [revealKey] 가 새 값이 될 때마다 한 번 공개 반응(한 바퀴 — [StagePolicy.REVEAL_REACTION] · S 스핀 칸을 먼저 데운다). 같은 값은 화면을 다시 열어도 다시 하지 않는다.
 *  - 화면에서 사라지면(ON_PAUSE) 장면 시계를 멈추고 그리기를 쉰다(맥 렌더 정지와 같은 규칙).
 */
@Composable
fun AingStage(
    characterId: String,
    mood: CharacterMood?,
    modifier: Modifier = Modifier,
    artSize: Dp = CharacterStageMetrics.artSize,
    revealKey: Any? = null,
    onTap: ((TapOutcome) -> Unit)? = null,
    assets: StageAssets = StageAssets.of(LocalContext.current),
    clock: StageClock = StageClock.System,
    handle: StageHandle? = null,
) {
    val library by produceState<BakeLibrary?>(null, assets) {
        value = withContext(Dispatchers.IO) { assets.libraryOrNull() }
    }
    val mode = StagePolicy.mode(characterId, library?.bakedIds ?: emptySet())
    handle?.let { it.characterId = characterId; it.bakedIds = library?.bakedIds; it.mode = mode }
    val finish = (mode as? StageMode.Live)?.let { library?.finish(it.drawnId) }
    val store by produceState<StageStore?>(null, assets, finish) {
        val f = finish ?: run { value = null; return@produceState }
        // 빌리기는 끊기지 않게(취소되면 빌린 수가 새어 저장소가 닫히지 않는다) — 페이지 디코드 · 데움은 배경에서.
        val s = withContext(NonCancellable + Dispatchers.Default) { assets.acquire(f) }
            ?: run { value = null; return@produceState } // 메모리 부족 · 깨진 자산 — 초상으로 선다(실패 이유는 assets.failureReason)
        try {
            value = s
            awaitCancellation()
        } finally {
            assets.release(s)
        }
    }
    val ready = store?.takeIf { it.finish === finish }
    handle?.store = ready
    Box(modifier.size(artSize + 6.dp, artSize + 12.dp).testTag(STAGE_TAG)) {
        // 바탕 = ui 무대 그대로(발밑 빛). 살아 있는 아잉이가 준비되기 전 · 초상 모드에서는 초상까지 그린다.
        val art = if (ready == null) rememberStageArt(characterId, (mood ?: CharacterMood.Plain).expression, artSize.value) else null
        CharacterStage(art = art, mood = mood, artSize = artSize)
        val lib = library
        if (ready != null && lib != null) {
            StageLive(lib, ready, characterId, (mode as StageMode.Live).folded, artSize, revealKey, onTap, clock, handle)
        }
    }
}

const val STAGE_TAG = "aing-stage"
const val STAGE_LIVE_TAG = "aing-stage-live"

/** 같은 그림인지(칸 · 감은 눈 · 후광 칸) — 다시 그릴지 판단(F §5.4)의 열쇠. */
internal fun frameKey(frame: CharacterFrame): String = when (frame) {
    is CharacterFrame.Impostor -> "${frame.frame.placement.cell.id}|${frame.frame.closedEyes}|${frame.frame.halo?.cell}"
    is CharacterFrame.Sprite -> "${frame.characterId}|${frame.frameRect}|${frame.mirrored}"
}

@Composable
private fun StageLive(
    library: BakeLibrary,
    store: StageStore,
    characterId: String,
    folded: Boolean,
    artSize: Dp,
    revealKey: Any?,
    onTap: ((TapOutcome) -> Unit)?,
    clock: StageClock,
    handle: StageHandle?,
) {
    val director = remember(store) { StageDirector(library, store.finish, clock.now()) }
    handle?.director = director
    val density = LocalDensity.current
    var sizePx by remember { mutableStateOf(IntSize.Zero) }
    val placement = remember(sizePx, artSize, density) {
        if (sizePx.width <= 0 || sizePx.height <= 0) null else with(density) {
            val side = artSize.toPx().toDouble()
            val bottomPad = CharacterStageMetrics.artBottomPadding.toPx().toDouble()
            StageFraming.place((sizePx.width - side) / 2, sizePx.height - bottomPad - side, side)
        }
    }
    handle?.placement = placement
    val frameState = remember(director) { mutableStateOf<CharacterFrame?>(null, neverEqualPolicy()) }
    val kick = remember(director) { Channel<Unit>(Channel.CONFLATED) }
    val lifecycleState by LocalLifecycleOwner.current.lifecycle.currentStateFlow.collectAsState()
    val resumed = lifecycleState.isAtLeast(Lifecycle.State.RESUMED)
    val refreshHz = LocalView.current.display?.refreshRate?.toDouble()?.takeIf { it >= 1.0 } ?: 60.0

    LaunchedEffect(director, resumed, placement, refreshHz) {
        val p = placement
        if (!resumed || p == null) {
            director.setSuspended(true, clock.now())
            return@LaunchedEffect
        }
        director.setSuspended(false, clock.now())
        val period = 1.0 / refreshHz
        var lastKey: String? = null
        var lastQuad: List<Vec2>? = null
        var lastPublishAt = Double.NEGATIVE_INFINITY
        while (true) {
            withFrameNanos { }
            val now = director.monotonic(clock.now())
            director.tick(now)
            val n = FramePacer.vsyncInterval(refreshHz, director.targetFps(now))
            if (now - lastPublishAt >= (n - 0.5) * period) {
                lastPublishAt = now
                val f = director.frame(now, p.viewportWidth, p.viewportHeight)
                val key = f?.let(::frameKey)
                if (f == null || key == null || FramePacer.needsRedraw(lastKey, lastQuad, key, f.viewportQuad)) {
                    lastKey = key
                    lastQuad = f?.viewportQuad
                    frameState.value = f
                    handle?.let { it.framesPublished++; it.lastFrame = f }
                }
            }
            // 유휴(6fps)면 다음 차례 직전까지 잔다 — 탭 · 공개가 깨운다. 활성(30fps)은 vsync 마다 센다.
            val wait = lastPublishAt + (n - 1.5) * period - director.monotonic(clock.now())
            if (wait > period) withTimeoutOrNull((wait * 1000).toLong().coerceAtLeast(1)) { kick.receive() }
        }
    }

    val revealToken = revealKey?.toString()
    var playedReveal by rememberSaveable { mutableStateOf<String?>(null) }
    LaunchedEffect(director, revealToken) {
        if (revealToken != null && revealToken != playedReveal) {
            // 한 바퀴의 S 스핀 칸을 배경에서 먼저 굽는다(그리는 주 스레드에서 페이지를 풀지 않게). 메모리가 모자라면 스핀 없이 돈다.
            if (!withContext(Dispatchers.Default) { store.prewarmSpin(director.spinPrewarmCells()) }) director.spinEnabled = false
            director.reveal(clock.now())
            playedReveal = revealToken
            kick.trySend(Unit)
        }
    }

    fun tapAt(point: Vec2): TapOutcome {
        val p = placement ?: return TapOutcome.missed
        val now = clock.now()
        val outcome = synchronized(store.lock) {
            val frame = frameState.value ?: director.frame(now, p.viewportWidth, p.viewportHeight)
            director.tap(point, frame, StagePolicy.TAP_MARGIN_POINTS * 2 * p.scale, store, now)
        }
        handle?.lastTap = outcome
        if (outcome == TapOutcome.hit) kick.trySend(Unit)
        onTap?.invoke(outcome)
        return outcome
    }

    val name = MeCharacterCards.displayName(characterId)
    val description = if (folded) "$name 미리보기(아잉 모습) — 두드리면 반응해요" else "$name 미리보기 — 두드리면 반응해요"
    Canvas(
        Modifier
            .size(artSize + 6.dp, artSize + 12.dp)
            .onSizeChanged { sizePx = it }
            .testTag(STAGE_LIVE_TAG)
            .semantics {
                contentDescription = description
                role = Role.Button
                onClick(label = "두드리기") {
                    val p = placement ?: return@onClick false
                    // 몸 가운데(틀 280×340 의 (137.5, 137.5) — 정면 idle 몸 상자 가운데)를 두드린 것으로 본다.
                    tapAt(Vec2(StageFraming.BODY_CENTER_X * p.scale, 137.5 * p.scale)) == TapOutcome.hit
                }
            }
            .pointerInput(director, placement) {
                detectTapGestures { pos ->
                    val p = placement ?: return@detectTapGestures
                    tapAt(Vec2(pos.x - p.originX, pos.y - p.originY))
                }
            },
    ) {
        val f = frameState.value ?: return@Canvas
        val p = placement ?: return@Canvas
        drawStageFrame(f, p.originX, p.originY, store)
    }
}

/**
 * 무대 프레임 한 장 그리기(앱 Canvas · 기기 시험이 같은 함수를 지난다): 틀 원점으로 옮기고 Compose 캔버스 → 원근 사각형 표면
 * (Android = HWUI `nativeCanvas`)에 재생기와 같은 그리기(후광 → 몸 칸 — [StageStore.draw]).
 */
fun DrawScope.drawStageFrame(frame: CharacterFrame, originX: Double, originY: Double, store: StageStore) {
    translate(originX.toFloat(), originY.toFloat()) {
        drawIntoCanvas { c ->
            synchronized(store.lock) { store.draw(quadCanvasOf(c), frame) }
        }
    }
}
