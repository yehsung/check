// 원본: Sources/CheckMobileKit/Games/GamesAlkkagiBoardModel.swift @ 928d5562(폰 1.0.18 — 맥 AlkkagiLocalModel 의 폰 꼴) — Android 판 8
//
// 판 진행 · 조준 · 굴림 되살리기(서버 시각 따라잡기 · 끝난 판이 먼저 오면 마저 굴리기) · 멈칫 · 숨긴 배치 끌기는 **맥 · 아이폰과 같은 식**이다 —
// 같은 서버 판을 두 기기가 다르게 그리면 안 된다. 소리는 없다(폰 앱엔 소리가 없다). 진동은 [haptic] 갈래로 화면이 낸다.
// 서버 판이면 [onlineStore] 가 있고, 없으면 한 폰에서 둘이 번갈아 두는 연습 판이다(루비 · 전적에 남지 않는다).
// 이 파일은 그리기를 모른다(Compose 상태만 쓴다) — 시험이 값으로 잰다.
package com.yehsung.aingcheck.core.stores.alkkagi

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableDoubleStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.yehsung.aingcheck.core.rules.alkkagi.AlkkagiGame
import com.yehsung.aingcheck.core.rules.alkkagi.AlkkagiVector
import com.yehsung.aingcheck.core.wire.games.AlkkagiMatchPhase
import com.yehsung.aingcheck.core.wire.games.AlkkagiPlayerWire
import kotlinx.coroutines.launch
import kotlin.math.exp
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin

/** 판 모델이 화면에 부탁하는 진동. */
sealed interface AlkkagiPhoneHaptic {
    data object Select : AlkkagiPhoneHaptic
    data object Power : AlkkagiPhoneHaptic
    data object Place : AlkkagiPhoneHaptic
    data class Launch(val strength: Double) : AlkkagiPhoneHaptic
    data class Impact(val strength: Double) : AlkkagiPhoneHaptic
}

data class AlkkagiPhoneHit(val position: AlkkagiVector, val strength: Double, val ringOut: Boolean, val age: Double = 0.0)
data class AlkkagiPhoneFall(val position: AlkkagiVector, val owner: AlkkagiGame.Player, val outward: AlkkagiVector, val age: Double = 0.0)
data class AlkkagiPhoneLaunch(val stoneID: Int, val direction: AlkkagiVector, val power: Double, val age: Double = 0.0)

class GamesAlkkagiBoardModel {
    companion object {
        const val maxHitStopPerShot = 0.16
        const val maxReplayLag = 0.6
        const val replayCatchUpRate = 0.5
        const val replayDrainRate = 1.0
        const val maxReplayDrain = 1.2
    }

    /** 판 값(관찰 칸 — 값이 바뀔 때마다 새 사본을 넣는다). */
    var game: AlkkagiGame by mutableStateOf(AlkkagiGame.newGame())
        private set
    var selectedID: Int? by mutableStateOf(null)
    var pull: AlkkagiVector by mutableStateOf(AlkkagiVector.zero)
    var placementID: Int? by mutableStateOf(0)
    var dragPlacementID: Int? by mutableStateOf(null)
    var placementPoint: AlkkagiVector? by mutableStateOf(null)
    var notice: String? by mutableStateOf(null)
    var hits: List<AlkkagiPhoneHit> by mutableStateOf(emptyList())
        private set
    var falls: List<AlkkagiPhoneFall> by mutableStateOf(emptyList())
        private set
    var launch: AlkkagiPhoneLaunch? by mutableStateOf(null)
        private set
    var time: Double by mutableDoubleStateOf(0.0)
        private set
    var jolt: Double by mutableDoubleStateOf(0.0)
        private set
    var onlineStore: AlkkagiOnlineStore? by mutableStateOf(null)
        private set

    /** 화면이 단다(진동). 시험은 엿듣는다. */
    var haptic: ((AlkkagiPhoneHaptic) -> Unit)? = null
    var hitStopEnabled = true
    private var lastTime: Double? = null
    private var clockTime = 0.0
    private var powerBand = 0
    private var gestureIsActive = false
    private var ignoresCurrentGesture = false
    private var onlineRevision = -1L
    private var onlineMatchID: String? = null
    private var onlineReplayElapsed = 0.0
    private var replayShotID: String? = null
    private var deferredRevision: Long? = null
    private var hitStop = 0.0
    private var hitStopSpent = 0.0

    /** 판 값을 고친 뒤 관찰자에게 알린다(같은 객체를 고쳤으므로 사본으로 갈아 끼운다). */
    private fun mutate(block: (AlkkagiGame) -> Unit) {
        val next = game.copy()
        block(next)
        game = next
    }

    val isOnline: Boolean get() = onlineStore != null
    val myColor: AlkkagiGame.Player get() = onlineStore?.state?.myColor?.rules() ?: AlkkagiGame.Player.black
    val canInteract: Boolean get() = onlineStore?.let { it.canPlace || it.canShoot } ?: true
    val selectedStone: AlkkagiGame.Stone? get() = game.stones.firstOrNull { it.id == selectedID && it.isPlaced && !it.isOut }
    val power: Double get() = min(1.0, pull.length / AlkkagiGame.maxPull)
    val remainingSeconds: Double
        get() = onlineStore?.remainingSeconds ?: if (game.phase == AlkkagiGame.Phase.placing) game.placementRemaining else game.turnRemaining

    val launchRecoil: AlkkagiVector
        get() {
            val l = launch ?: return AlkkagiVector.zero
            return l.direction * (-sin(l.age * 38) * exp(-l.age * 17) * l.power * 6)
        }

    /** 상태 한 줄(맥과 같은 서열 — 폰 손짓 글자만 다르다). */
    val status: String
        get() {
            val store = onlineStore
            val state = store?.state
            if (store != null && state != null) {
                if (store.isBusy) return AlkkagiPhoneText.waitBusy
                if (state.phase == AlkkagiMatchPhase.finished) return AlkkagiPhoneText.outcomeTitle(store.outcome)
                if (state.phase == AlkkagiMatchPhase.rolling) return AlkkagiPhoneText.rolling
                if (state.phase == AlkkagiMatchPhase.placing) {
                    return if (state.myReady) AlkkagiPhoneText.placingReadyWaiting else AlkkagiPhoneText.placingMine(state.myColor.rules())
                }
                if (!store.isMyTurn) {
                    val peer = if (state.currentPlayer == AlkkagiPlayerWire.black) state.black else state.white
                    return AlkkagiPhoneText.opponentTurn(peer.displayName)
                }
            }
            return when (game.phase) {
                AlkkagiGame.Phase.placing -> AlkkagiPhoneText.placingPractice(game.currentPlayer)
                AlkkagiGame.Phase.aiming -> if (game.isFirstShotLimited) {
                    if (selectedID == null) AlkkagiPhoneText.firstShotHint else AlkkagiPhoneText.firstShotRelease
                } else {
                    if (selectedID == null) AlkkagiPhoneText.aimHint(game.currentPlayer) else AlkkagiPhoneText.aimRelease
                }
                AlkkagiGame.Phase.rolling -> AlkkagiPhoneText.rolling
                AlkkagiGame.Phase.finished -> AlkkagiPhoneText.practiceResult(game.result)
            }
        }

    // MARK: 손짓(판 좌표 — 화면이 점을 판 600 칸으로 바꿔 넘긴다)

    fun aim(start: AlkkagiVector, translation: AlkkagiVector) {
        gestureIsActive = true
        if (ignoresCurrentGesture || !canInteract) return
        val g = game
        if (g.phase == AlkkagiGame.Phase.placing) {
            if (dragPlacementID == null) {
                dragPlacementID = g.stones.firstOrNull {
                    it.owner == g.currentPlayer && it.isPlaced && !it.isOut && (it.position - start).length < AlkkagiGame.stoneRadius * 1.4
                }?.id ?: placementID ?: g.stones.firstOrNull { it.owner == g.currentPlayer && !it.isPlaced }?.id
            }
            if (dragPlacementID == null) return
            placementPoint = start + translation
            notice = null
            return
        }
        if (g.phase != AlkkagiGame.Phase.aiming) return
        if (selectedID == null) {
            // 손가락은 마우스보다 굵다 — 잡는 반경 1.9배(판 600 칸에서 38).
            selectedID = g.stones.filter {
                it.isPlaced && !it.isOut && it.owner == g.currentPlayer && (it.position - start).length < AlkkagiGame.stoneRadius * 1.9
            }.minByOrNull { (it.position - start).length }?.id
            if (selectedID != null) haptic?.invoke(AlkkagiPhoneHaptic.Select)
        }
        if (selectedID == null) return
        // 판의 첫 수(흑)는 화살이 60%(당김 81)에서 멈춘다 — 서버가 저장 전에 같은 값으로 줄인다.
        val limit = g.shotPullLimit
        pull = if (translation.length > limit) translation * (limit / translation.length) else translation
        val band = (power * 4).toInt()
        if (band > powerBand) haptic?.invoke(AlkkagiPhoneHaptic.Power)
        powerBand = band
    }

    fun release() {
        try {
            if (ignoresCurrentGesture || !canInteract) return
            val g = game
            if (g.phase == AlkkagiGame.Phase.placing) {
                val id = dragPlacementID ?: return
                val at = placementPoint ?: return
                val store = onlineStore
                if (store != null) {
                    if (!g.canPlace(id, at)) {
                        notice = AlkkagiPhoneText.placementInvalid
                        return
                    }
                    store.scope.launch {
                        store.place(id, at)
                        synchronizeOnline(force = true)
                    }
                    return
                }
                var placed = false
                mutate { placed = it.placeStone(id, at) }
                if (placed) {
                    placementID = game.stones.firstOrNull { it.owner == game.currentPlayer && !it.isPlaced }?.id
                    notice = null
                    haptic?.invoke(AlkkagiPhoneHaptic.Place)
                } else {
                    notice = AlkkagiPhoneText.placementInvalid
                }
                return
            }
            val id = selectedID ?: return
            if (selectedStone == null) return
            val shotPull = pull
            val shotPower = power
            val actionID = randomUUIDString()
            var shot = false
            mutate { shot = it.shoot(id, shotPull) }
            if (!shot) return
            launch = AlkkagiPhoneLaunch(id, shotPull * (-1 / shotPull.length), shotPower)
            hitStop = 0.0
            hitStopSpent = 0.0
            haptic?.invoke(AlkkagiPhoneHaptic.Launch(0.3 + shotPower * 0.6))
            val store = onlineStore ?: return
            replayShotID = actionID
            deferredRevision = null
            onlineReplayElapsed = 0.0
            store.scope.launch {
                store.shoot(id, shotPull, actionID)
                synchronizeOnline(force = true)
            }
        } finally {
            finishGesture()
        }
    }

    fun cancelAim() {
        if (gestureIsActive) ignoresCurrentGesture = true
        selectedID = null
        pull = AlkkagiVector.zero
        powerBand = 0
        dragPlacementID = null
        placementPoint = null
    }

    fun finishGesture() {
        cancelAim()
        gestureIsActive = false
        ignoresCurrentGesture = false
    }

    fun confirmPlacement() {
        val store = onlineStore
        if (store != null) {
            store.scope.launch {
                store.confirmPlacement()
                synchronizeOnline(force = true)
            }
            return
        }
        val old = game.copy()
        var ok = false
        mutate { ok = it.confirmPlacement() }
        if (ok) changed(old)
    }

    /** 연습 판 새로 시작(서버 판에서는 쓰지 않는다). */
    fun restartPractice() {
        if (onlineStore != null) return
        val physics = game.physics
        game = AlkkagiGame.newGame().also { it.physics = physics }
        cancelAim()
        placementID = 0
        notice = null
        hits = emptyList()
        falls = emptyList()
        launch = null
        jolt = 0.0
        lastTime = null
        clockTime = 0.0
    }

    private fun changed(old: AlkkagiGame) {
        if (isOnline) return
        if (old.phase == game.phase && old.currentPlayer == game.currentPlayer) return
        cancelAim()
        notice = null
        clockTime = 0.0
        if (old.phase == AlkkagiGame.Phase.placing) placementID = game.stones.firstOrNull { it.owner == game.currentPlayer && !it.isPlaced }?.id
    }

    // MARK: 걸음(화면 주사율 — 프레임 루프가 부른다)

    /** [now] = 단조 시계 초. */
    fun tick(now: Double) {
        val last = lastTime
        lastTime = now
        if (last == null) return
        val elapsed = max(0.0, now - last)
        val dt = min(1.0 / 20, elapsed)
        var rollDt = dt
        val frozen = hitStop > 0
        if (frozen) {
            val used = min(hitStop, dt)
            hitStop -= used
            rollDt = dt - used
        }
        var impacts: List<AlkkagiGame.Impact> = emptyList()
        val old = game.copy()
        val store = onlineStore
        if (store != null) {
            synchronizeOnline()
            if (game.phase == AlkkagiGame.Phase.rolling && replayShotID != null) {
                var step = rollDt
                if (!frozen) {
                    val behind = replayLag(store)
                    if (behind != null) {
                        // 신호를 놓쳐 아주 늦게 안 판 — 넘는 만큼만 효과 없이 건너뛴다.
                        if (behind > maxReplayLag) advanceReplay(behind - maxReplayLag)
                        if (behind > 0.001) step += min(behind, dt * replayCatchUpRate)
                    } else if (deferredRevision != null) {
                        step += dt * replayDrainRate
                    }
                }
                if (step > 0) impacts = advanceReplay(step)
                if (game.phase != AlkkagiGame.Phase.rolling && deferredRevision != null) {
                    deferredRevision = null
                    synchronizeOnline(force = true)
                }
            }
        } else if (game.phase == AlkkagiGame.Phase.placing || game.phase == AlkkagiGame.Phase.aiming) {
            // 초 단위 글자는 5Hz 로만 갱신한다. 화면 밖을 눌러도 제한 시간은 흐른다.
            clockTime += elapsed
            if (clockTime >= 0.2) {
                val deadlineExpired = clockTime + 1e-9 >= remainingSeconds
                val step = clockTime
                mutate { impacts = it.advance(step) }
                clockTime = 0.0
                if (deadlineExpired) cancelAim()
            }
        } else if (game.phase == AlkkagiGame.Phase.rolling && rollDt > 0) {
            val step = rollDt
            mutate { impacts = it.advance(step) }
        }
        changed(old)
        if (hits.isEmpty() && falls.isEmpty() && launch == null && impacts.isEmpty() && jolt <= 0) return
        time += dt
        val ageDt = if (frozen) 0.0 else dt
        launch?.let { l -> val a = l.copy(age = l.age + ageDt); launch = if (a.age < 0.3) a else null }
        hits = hits.mapNotNull { h -> h.copy(age = h.age + ageDt).takeIf { it.age < 0.32 } }
        falls = falls.mapNotNull { f -> f.copy(age = f.age + ageDt).takeIf { it.age < 0.9 } }
        jolt = max(0.0, jolt - dt * 9)
        val newHits = impacts.filter { it.strength > 0.08 }.map { AlkkagiPhoneHit(it.position, it.strength, it.isRingOut) }
        if (newHits.isNotEmpty()) hits = hits + newHits
        val newFalls = game.stones.filter { s -> s.isOut && old.stones.firstOrNull { it.id == s.id }?.isOut == false }.map { s ->
            val p = s.position
            val outward = AlkkagiVector(if (p.x < 0) -1.0 else if (p.x > AlkkagiGame.boardSize) 1.0 else 0.0, if (p.y < 0) -1.0 else if (p.y > AlkkagiGame.boardSize) 1.0 else 0.0)
            val edge = AlkkagiVector(min(AlkkagiGame.boardSize, max(0.0, p.x)), min(AlkkagiGame.boardSize, max(0.0, p.y)))
            AlkkagiPhoneFall(edge, s.owner, outward)
        }
        if (newFalls.isNotEmpty()) falls = falls + newFalls
        val impact = impacts.maxByOrNull { it.strength }
        if (impact != null && impact.strength > 0.12) {
            jolt = max(jolt, impact.strength.pow(1.3))
            if (hitStopEnabled && !impact.isRingOut && impact.strength > 0.3 && hitStopSpent < maxHitStopPerShot) {
                val stop = min(maxHitStopPerShot - hitStopSpent, 0.03 + 0.05 * min(1.0, impact.strength))
                hitStop = max(hitStop, stop)
                hitStopSpent += stop
            }
            if (impact.strength > 0.35) haptic?.invoke(AlkkagiPhoneHaptic.Impact(min(1.0, impact.strength)))
        }
    }

    // MARK: 서버 판 맞추기(맥 · 아이폰과 같은 식)

    /** 서버 굴림 시각보다 내 화면 굴림이 뒤처진 초(앞서면 음수). 서버가 같은 쏘기를 굴리는 중일 때만 — 아니면 null. */
    private fun replayLag(store: AlkkagiOnlineStore): Double? {
        val state = store.state ?: return null
        if (state.phase != AlkkagiMatchPhase.rolling) return null
        val shot = state.shot ?: return null
        if (replayShotID?.equals(shot.id, ignoreCase = true) != true || !shot.startedAtMs.isFinite()) return null
        val serverElapsed = min(shot.duration, max(0.0, (store.estimatedServerNowMs - shot.startedAtMs) / 1000))
        val lag = serverElapsed - onlineReplayElapsed
        return if (lag.isFinite()) lag else null
    }

    private fun advanceReplay(seconds: Double): List<AlkkagiGame.Impact> {
        val impacts = mutableListOf<AlkkagiGame.Impact>()
        var remaining = seconds
        val next = game.copy()
        while (remaining > 1e-9 && next.phase == AlkkagiGame.Phase.rolling) {
            val slice = min(0.25, remaining)
            impacts += next.advance(slice)
            remaining -= slice
            onlineReplayElapsed += slice
        }
        game = next
        return impacts
    }

    fun attachOnline(store: AlkkagiOnlineStore?) {
        store ?: return
        onlineStore = store
        synchronizeOnline(force = true)
    }

    fun synchronizeOnline(force: Boolean = false) {
        val store = onlineStore ?: return
        val state = store.state ?: return
        if (!force && onlineMatchID == state.id && onlineRevision == state.revision) return
        // 굴림 뒤 판이 내 굴림보다 먼저 왔다 — 같은 쏘기를 마저 굴린 뒤 받는다(남은 굴림이 길면 바로 받는다).
        if (state.phase != AlkkagiMatchPhase.rolling && onlineMatchID == state.id && game.phase == AlkkagiGame.Phase.rolling &&
            replayShotID != null && game.shotCount.toLong() == state.shotCount
        ) {
            if (deferredRevision == state.revision) return
            val probe = game.copy()
            var left = maxReplayDrain
            while (probe.phase == AlkkagiGame.Phase.rolling && left > 0) {
                probe.advance(0.25)
                left -= 0.25
            }
            if (probe.phase != AlkkagiGame.Phase.rolling) {
                deferredRevision = state.revision
                return
            }
        }
        deferredRevision = null
        val myColor = state.myColor.rules()
        // 상대의 숨긴 배치가 내 끌기를 끊지 않게.
        if (!force && onlineMatchID == state.id && state.phase == AlkkagiMatchPhase.placing && !state.myReady &&
            game.phase == AlkkagiGame.Phase.placing && game.currentPlayer == myColor && game.stones == state.stones.map { it.rules() }
        ) {
            onlineRevision = state.revision
            return
        }
        cancelAim()
        notice = null
        val keepsReplay = state.phase == AlkkagiMatchPhase.rolling &&
            replayShotID?.equals(state.shot?.id ?: "", ignoreCase = true) == true && game.shotCount.toLong() == state.shotCount
        val replay = state.shotReplayGame
        if (state.phase == AlkkagiMatchPhase.rolling && !keepsReplay && replay != null) {
            game = replay
            replayShotID = state.shot?.id
            onlineReplayElapsed = 0.0
        } else if (!keepsReplay) {
            state.canonicalGame(store.estimatedServerNowMs)?.let { canonical ->
                game = canonical
                if (state.phase != AlkkagiMatchPhase.rolling) replayShotID = null
                onlineReplayElapsed = 0.0
            }
        }
        onlineMatchID = state.id
        onlineRevision = state.revision
        placementID = game.stones.firstOrNull { it.owner == myColor && !it.isPlaced }?.id
    }
}
