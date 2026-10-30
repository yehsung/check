// 원본: Sources/CheckCore/GachaMachine/GachaMachineView.swift @ 3bd04bd (GachaMachineView · GachaMachineScaler)
//
// 캡슐 뽑기 기계(0.3.54). 기계는 **호스트가 넘긴 값만 보여 준다** — 잔액 · 조각을 스스로 바꾸지 않는다.
//  - balance/cost: 모자라면 손잡이가 안 돌고 안내가 뜬다(pull 을 부르지 않는다).
//  - isActive: 보이는가(앱이 앞 · 덮개가 떠 있음 · 확률 시트가 안 가림). false 면 매 프레임 그리기를 멈추고 **커밋 전 예약(자동 회전 ·
//    [한 번 더])을 거둔다** — 안 보이는 기계는 루비를 쓰지 않는다.
//  - pull: 한 바퀴를 다 돌린 순간 **한 번** 부른다. 던지면 한 줄을 2.4초 띄우고 처음으로 — 공개는 없다.
//  - onUnrevealedChanged: 루비를 낸 판의 결과를 사용자가 아직 못 봤는가(감독 hasUnrevealedTurn — 맥 GachaMachineLink)가 바뀔 때만 부른다.
//    맥은 호스트(뽑기 창)가 열 때 감독에게 묻고, 여기는 값을 밀어 준다. 기본 {} — 기계 동작은 그대로다.
// 프레임: 감독이 그림을 원할 때(framesWanted)만 매 프레임 시계를 읽는다(잦아든 뒤엔 CPU 0).
package com.yehsung.aingcheck.ui.gacha.machine

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.delay
import kotlin.math.min
import kotlin.time.TimeSource

@Composable
fun GachaMachineView(
    balance: Long,
    cost: Long,
    shards: Long,
    art: GachaMachineArt,
    portrait: GachaRevealPortrait,
    ruby: ImageBitmap?,
    pull: suspend () -> GachaRevealOutcome,
    onClose: () -> Unit,
    modifier: Modifier = Modifier,
    haptics: GachaMachineHaptics = GachaMachineHaptics.None,
    isActive: Boolean = true,
    blockedReason: String? = null,
    againEnabled: Boolean = true,
    reduceMotion: Boolean = false,
    teaseChance: Double = 0.3,
    onAgain: () -> Unit = {},
    onUnrevealedChanged: (Boolean) -> Unit = {},
) {
    val origin = remember { TimeSource.Monotonic.markNow() }
    val clock = remember(origin) { { origin.elapsedNow().inWholeNanoseconds / 1e9 } }
    val scope = rememberCoroutineScope()
    val d = remember { GachaMachineDirector(clock, scope) }
    val env = GachaMachineEnv(
        balance = balance, cost = cost, shards = shards, art = art, teaseChance = teaseChance, haptics = haptics,
        pull = pull, onAgain = onAgain, onClose = onClose, blockedReason = blockedReason, againEnabled = againEnabled,
        isActive = isActive, reduceMotion = reduceMotion,
    )
    // 그릴 때마다 호스트 값을 넘긴다(관찰되지 않는 칸만 바뀐다 — Swift 와 같은 자리).
    d.update(env)
    val sprites = remember(art) { GachaCapsuleSprites(art) }
    val running = isActive && d.framesWanted
    var now by remember { mutableStateOf(clock()) }
    LaunchedEffect(running) {
        now = clock()
        if (running) while (true) {
            withFrameNanos { }
            now = clock()
        }
    }
    // 박자가 바뀐 순간의 햅틱(Swift onChange(of: beats)).
    val beats = d.beats(now)
    val lastBeats = remember { arrayOfNulls<GBeats>(1) }
    SideEffect {
        val old = lastBeats[0]
        if (old != null && old != beats) d.emitBeats(old, beats, now)
        lastBeats[0] = beats
    }
    LaunchedEffect(isActive) {
        // 안 보이게 됐다 → 커밋 전 예약을 거둔다(감독의 깨우기도 같은 일을 한다 — 어느 쪽이 먼저 와도 루비가 안 나간다).
        if (isActive) d.touched(clock()) else d.cancelPendingTurn(clock())
    }
    LaunchedEffect(reduceMotion, balance, blockedReason) { d.touched(clock()) }
    DisposableEffect(d) { onDispose { d.stop() } }

    // 루비 낸 판 미공개(공용 패치 5). 그릴 때마다 감독 시계로 다시 재고(왕복·결과·터짐은 스냅숏 상태라 바뀌면 다시 그린다 — 프레임이 도는 동안은
    // 매 프레임) 값이 바뀐 그 그리기에서만 호스트에 알린다. 숨는 순간의 판정(안 보이는 동안 자리 잡은 공개 = 못 봄)은 위 d.update 가 먼저 적는다.
    val unrevealed = d.hasUnrevealedTurn(clock())
    val onUnrevealed by rememberUpdatedState(onUnrevealedChanged)
    val reportedUnrevealed = remember { arrayOfNulls<Boolean>(1) }
    SideEffect {
        if (reportedUnrevealed[0] != unrevealed) {
            reportedUnrevealed[0] = unrevealed
            onUnrevealed(unrevealed)
        }
    }
    // 보이는 채로 프레임이 먼저 잦아들고 공개가 그 뒤에 자리 잡는 판(판 도중 움직임 줄이기)은 다시 그릴 일이 없다 — 자리 잡는 때 한 번만 깨운다.
    LaunchedEffect(unrevealed, running, isActive) {
        val b = d.burstTime
        val r = d.result
        if (!unrevealed || running || !isActive || b == null || r == null) return@LaunchedEffect
        val wait = b + d.goldBuild + d.buttonsAt(r.kind) - clock()
        if (wait > 0) delay((wait * 1000).toLong() + 1)
        now = clock()
    }

    GachaMachineScaler(modifier) {
        GachaMachineStage(d, env, GachaMachineTheme.of(AingTheme.colors.isDark), sprites, now, portrait, ruby)
    }
}

/**
 * 설계 무대(380×460)를 받은 자리에 비율 그대로 맞춰 가운데 둔다. 바탕 · 무대 조명 · 황금 어둠 · 섬광은 무대 밖까지 번지게 그려(폰 세로 화면에서
 * 위아래가 비지 않게) 이 테두리로 자른다.
 */
@Composable
fun GachaMachineScaler(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    BoxWithConstraints(modifier.fillMaxSize().clipToBounds()) {
        val s = min(maxWidth.value / GLayout.size.width, maxHeight.value / GLayout.size.height)
        Box(Modifier.align(Alignment.Center).graphicsLayer { scaleX = s; scaleY = s }) { content() }
    }
}
