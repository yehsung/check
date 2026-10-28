// 원본: Sources/check/CheckOverlayReactions.swift @ 1b8260d (ReactionEngine 이 노드에 하던 일 — resetPose · runReaction · blink · setDragFacing · applySpriteFacing · wakeQuietly · beginWake · stopSleeping · reconcileAfterResume) — 설계 F §5.2 경계 API
package com.yehsung.aingcheck.character.player

import com.yehsung.aingcheck.character.bake.BakeLibrary
import com.yehsung.aingcheck.character.bake.BakedFinish
import com.yehsung.aingcheck.character.bake.MotionCurve
import com.yehsung.aingcheck.character.bake.MotionTrack
import com.yehsung.aingcheck.character.bake.PoseSample
import com.yehsung.aingcheck.character.math.SceneKitEuler
import com.yehsung.aingcheck.character.math.Vec3
import com.yehsung.aingcheck.character.pose.NodeChain
import com.yehsung.aingcheck.character.sprite.SpritePlane
import com.yehsung.aingcheck.character.sprite.SpriteRuntime
import com.yehsung.aingcheck.core.rules.character.CharacterCatalog
import com.yehsung.aingcheck.core.rules.character.CharacterManifest

/** 지금 그리는 캐릭터. 구운 아잉이(3마감) 또는 스프라이트(6종 · legacy 2칸). */
sealed interface ResolvedCharacter {
    val id: String
    /** 모델 최장변(리액션 진폭 단위). */
    val extent: Double

    class Baked(val finish: BakedFinish, override val extent: Double) : ResolvedCharacter {
        override val id: String get() = finish.characterId
    }

    class Sprite(override val id: String, val runtime: SpriteRuntime) : ResolvedCharacter {
        override val extent: Double get() = SpritePlane.TARGET_EXTENT
        val pixelArt: Boolean get() = runtime.manifest.pixelArt == true
    }
}

/** 화들짝 깨기(클릭 — 0.15s easeOut 스냅 + 되튀기) · 조용한 기상(낮잠 타이머 — 0.9s smoothstep). */
enum class WakeKind { startled, quiet }

/**
 * 캐릭터 재생기(K10 · F §5.2). 맥 `ReactionEngine` 이 노드에 하던 일만 받는다 — 우선순위 · 말풍선 · 쿨다운 · 졸기 스케줄은 오버레이 몫(W5-b).
 * **시계를 읽지 않는다**: 모든 호출이 `now`(벽시계 초, 단조)를 받는다. 장면 시계(초)는 정지(setSuspended) 동안 멈춘다.
 *
 * 채널(F §5.2 표): wrapper(Idle · Playing · Holding · ToIdentity) / facing(−1·0·+1 즉시 스냅) / idle(장면 시계, 캐릭터 교체 때 위상 0) /
 * 눈(뜸 · 감음) / 스프라이트 상태(frontIdle · sideIdle · sideWalk + 미러).
 *
 * **굽지 않은 캐릭터는 아잉으로 접는다**(§8-17 #7 케이크 둘 · 모르는 id): [swapCharacter] 가 [currentCharacterId] 를 아잉으로 둔다.
 */
class CharacterPlayer(
    val library: BakeLibrary,
    /** 스프라이트 런타임 찾기(fox · shiba … · legacy 2칸). 구운 마감이 아닌 id 에만 묻는다. 없으면 null. */
    private val spriteFor: (String) -> SpriteRuntime? = { null },
    initialCharacterId: String? = null,
    now: Double = 0.0,
) {
    private sealed interface Wrapper {
        data object Idle : Wrapper
        data class Playing(val reaction: String, val track: MotionTrack, val startScene: Double, val startWall: Double, val wallDuration: Double, val holdsEnd: Boolean) : Wrapper
        data class Holding(val pose: PoseSample) : Wrapper

        /**
         * 현재 자세 → 단위(깨기). [wallDuration] 은 맥 상태 만료(벽시계): 화들짝은 `activeUntil = now + ReactionKind.wake.duration`,
         * 조용한 기상은 상태가 없어(`wakeQuietly` 는 activeKind 를 두지 않는다) 0 — 재개 정리에서 남은 보간을 언제나 걷는다.
         */
        data class ToIdentity(
            val fromEuler: Vec3,
            val fromPosition: Vec3,
            val fromScale: Vec3,
            val startScene: Double,
            val seconds: Double,
            val curve: MotionCurve,
            val bounce: MotionTrack?,
            val startWall: Double,
            val wallDuration: Double,
        ) : Wrapper
    }

    private var wrapper: Wrapper = Wrapper.Idle

    // 장면 시계: 정지 중엔 멈춘다(맥 wrapper isPaused).
    private var suspended = false
    private var frozenScene = 0.0
    private var wallBase = now

    private var idleOriginScene = 0.0

    var character: ResolvedCharacter = resolve(initialCharacterId)
        private set

    /** 요청받은 id(접히기 전). 진단용 — 그리기는 [currentCharacterId] 를 본다. */
    var requestedCharacterId: String? = initialCharacterId
        private set

    val currentCharacterId: String get() = character.id

    var facing: Int = 0
        private set
    var walking: Boolean = false
        private set
    private var lastWalkAt = Double.NEGATIVE_INFINITY

    /** 엔진이 [setEyesClosed] 로 쥔 감은 눈(졸기 · 깜빡임과 따로). */
    private var heldClosed = false

    /** 깜빡임이 끝나는 벽시계 시각(맥 `blinkTask` 의 0.12s). */
    private var blinkEndsAt = Double.NEGATIVE_INFINITY

    var sleeping: Boolean = false
        private set

    /**
     * 시각과 무관한 감은 눈: 졸기 · [setEyesClosed]. 깜빡임은 끝나는 시각이 있어 [eyesClosedAt] 이 본다 — **그리기는 [eyesClosedAt]**.
     */
    val eyesClosed: Boolean get() = sleeping || heldClosed

    /** 이 시각에 깜빡이는 중인가. */
    fun isBlinking(now: Double): Boolean = now < blinkEndsAt

    /** 이 시각 그릴 눈(졸기 · [setEyesClosed] · 깜빡임). 스프라이트는 그리기가 무시한다(전용 프레임이 없다). */
    fun eyesClosedAt(now: Double): Boolean = eyesClosed || isBlinking(now)

    val isSuspended: Boolean get() = suspended

    fun sceneTime(now: Double): Double = if (suspended) frozenScene else frozenScene + (now - wallBase)

    // ---------------------------------------------------------------- 캐릭터

    private fun resolve(id: String?): ResolvedCharacter {
        val wanted = id?.takeIf { it.isNotEmpty() }
        if (wanted != null) {
            library.finish(wanted)?.let { return ResolvedCharacter.Baked(it, library.motion.extent) }
            spriteFor(wanted)?.let { return ResolvedCharacter.Sprite(wanted, it) }
        }
        // 굽지 않은 캐릭터(케이크 · 모르는 id · 빈 값)는 아잉으로 접는다. 아잉 굽기가 없으면 아잉 legacy 2칸.
        library.finish(CharacterCatalog.builtInAingID)?.let { return ResolvedCharacter.Baked(it, library.motion.extent) }
        spriteFor(CharacterCatalog.builtInAingID)?.let { return ResolvedCharacter.Sprite(CharacterCatalog.builtInAingID, it) }
        error("아잉조차 그릴 수 없다(구운 자산 · legacy 모두 없음)")
    }

    /**
     * 캐릭터 교체. idle 위상을 0 으로 되돌린다(새 노드가 idle 을 새로 단다 — `CheckCharacter3DView.swift:233-236`).
     * wrapper(리액션)는 그대로 둔다(wrapper 는 캐릭터와 따로 산다). 스프라이트는 지금 방향을 프레임으로 다시 건다.
     */
    fun swapCharacter(id: String?, now: Double) {
        requestedCharacterId = id
        character = resolve(id)
        idleOriginScene = sceneTime(now)
        applyFacing(now)
    }

    // ---------------------------------------------------------------- 리액션

    private fun trackFor(name: String): MotionTrack? {
        if (character is ResolvedCharacter.Sprite) library.track("$name.flat")?.let { return it }
        return library.track(name)
    }

    /** 리액션 시작 — 먼저 단위로 스냅(resetPose)한 뒤 재생. 트랙이 묶음에 없거나 정지 중이면 모션 없이 false(맥: 정지 중엔 걸지 않는다). */
    fun play(reaction: String, now: Double): Boolean {
        val spec = library.motion.reaction(reaction) ?: return false
        val trackName = spec.track ?: return false
        if (spec.toIdentitySeconds != null) return false // wake 계열은 wake() 로
        if (suspended) return false
        val track = trackFor(trackName) ?: return false
        if (reaction != DROWSY) endSleep()
        val holds = spec.holdsEnd || track.holdsEnd
        wrapper = Wrapper.Playing(reaction, track, sceneTime(now), now, spec.durationS ?: track.durationS, holds)
        return true
    }

    /** 리액션을 끊고 단위로 스냅. 자는 중이면 잠도 끝낸다(눈을 뜬다). */
    fun interrupt(now: Double) {
        wrapper = Wrapper.Idle
        endSleep()
        applyFacing(now)
    }

    /**
     * 졸기 진입: drowsySink 트랙(끝 자세를 쥔다) + 감은 눈. 깜빡이던 중이면 그 깜빡임을 버린다 — 졸기가 눈의 주인이다
     * (맥 blink: "깜빡이는 사이 잠들었으면 눈을 뜨지 않는다"). 깨면 눈을 바로 뜬다(맥 endSleep → restoreEyes).
     */
    fun beginSleep(now: Double): Boolean {
        if (!play(DROWSY, now)) return false
        sleeping = true
        blinkEndsAt = Double.NEGATIVE_INFINITY
        return true
    }

    /**
     * 깨기 — **현재 자세에서 출발**해 단위로(화들짝은 되튀기까지). 눈을 뜬다.
     * 정지 중 조용한 기상은 보간하지 않고 단위로 세운다(맥 `wakeQuietly`: 정지 중 건 액션은 재개 순간 뒤늦게 재생된다 — 잠금 화면 뒤에서 깬 잠은 스냅).
     * 화들짝은 정지 중에도 건다(맥 `beginWake` 는 정지를 보지 않는다) — 재개 때 벽시계로 만료됐으면 [setSuspended] 가 걷는다.
     */
    fun wake(kind: WakeKind, now: Double): Boolean {
        val name = if (kind == WakeKind.startled) WAKE else QUIET_RISE
        val spec = library.motion.reaction(name) ?: return false
        val seconds = spec.toIdentitySeconds ?: return false
        val curve = spec.toIdentityCurve ?: return false
        if (kind == WakeKind.quiet && suspended) {
            wrapper = Wrapper.Idle
            endSleep()
            return true
        }
        val from = wrapperPose(now)
        val bounce = if (kind == WakeKind.startled) spec.track?.let(::trackFor) else null
        val wallDuration = if (kind == WakeKind.startled) spec.durationS ?: (seconds + (bounce?.durationS ?: 0.0)) else 0.0
        wrapper = Wrapper.ToIdentity(SceneKitEuler.fromQuat(from.rotation), from.position, from.scale, sceneTime(now), seconds, curve, bounce, now, wallDuration)
        endSleep()
        return true
    }

    /** 잠 상태만 푼다: 눈을 뜬다(엔진이 쥔 감은 눈 · 깜빡임까지 — 맥 endSleep → restoreEyes). */
    private fun endSleep() {
        if (sleeping) {
            sleeping = false
            heldClosed = false
            blinkEndsAt = Double.NEGATIVE_INFINITY
        }
    }

    /**
     * 엔진이 눈을 직접 감기거나 뜬다. **졸기 중엔 무시한다** — 졸기가 눈의 주인이다(맥: 자는 눈과 깜빡임이 같은 자산이라 졸기 중 눈을 뜨면 안 된다).
     * 스프라이트는 값만 들고 그리기가 무시한다(전용 프레임이 없다). 깜빡임은 [blink] 가 0.12s 를 쥔다.
     */
    fun setEyesClosed(closed: Boolean) {
        if (sleeping) return
        heldClosed = closed
    }

    /**
     * 눈 한 번 깜빡이기(맥 `ReactionEngine.blink`, 0.12s = motion.json `engine.blinkSeconds`). 가드 넷 — 하나라도 걸리면 false 이고 아무것도 바꾸지 않는다:
     *  ① 스프라이트는 깜빡이지 않는다(전용 프레임이 없다 — 막지 않으면 fps 만 오른다)
     *  ② 정지 중엔 물러난다(아무도 못 본다)
     *  ③ 자는 중엔 이미 눈이 감겼다(깜빡이면 오히려 눈을 뜬다)
     *  ④ 리액션 상태(벽시계 만료 전)엔 그 연출이 표정을 쓴다 — idle 일 때만
     * 깜빡이는 사이 잠들면 눈을 다시 뜨지 않는다([beginSleep] 이 깜빡임을 버린다).
     */
    fun blink(now: Double): Boolean {
        if (character is ResolvedCharacter.Sprite) return false
        if (suspended || sleeping) return false
        if (reactionStateActive(now)) return false
        blinkEndsAt = now + library.motion.engine.blinkSeconds
        return true
    }

    /** 맥 `state != .idle` 의 재생기 쪽 판정: 리액션 상태가 벽시계로 아직 만료되지 않았다(끝 자세를 쥔 졸기는 [sleeping] 이 따로 본다). */
    private fun reactionStateActive(now: Double): Boolean = when (val w = wrapper) {
        is Wrapper.Playing -> !w.holdsEnd && now - w.startWall < w.wallDuration
        is Wrapper.ToIdentity -> now - w.startWall < w.wallDuration
        else -> false
    }

    // ---------------------------------------------------------------- 방향

    /**
     * 드래그 · 보드 바라보기: −1(왼쪽) · 0 · +1(오른쪽). 즉시 스냅(보간 없음). 같은 값 재요청은 무시 —
     * 단 **걷기 스탬프는 가드보다 먼저** 찍는다(같은 방향으로 계속 끌 때 걷기 감시가 '멈췄다'로 주저앉지 않게).
     */
    fun setFacing(direction: Int, moving: Boolean, now: Double) {
        val dir = direction.coerceIn(-1, 1)
        val walk = dir != 0 && moving
        if (walk) lastWalkAt = now
        if (dir == facing && walk == walking) return
        facing = dir
        walking = walk
        applyFacing(now)
    }

    private fun applyFacing(now: Double) {
        val sprite = (character as? ResolvedCharacter.Sprite)?.runtime ?: return
        val key = when {
            facing == 0 -> CharacterManifest.StateKey.frontIdle
            walking && sprite.hasState(CharacterManifest.StateKey.sideWalk) -> CharacterManifest.StateKey.sideWalk
            else -> CharacterManifest.StateKey.sideIdle
        }
        sprite.setState(key, mirrored = facing < 0, now = now)
    }

    /** 스프라이트 걷기 틱(맥 50ms 루프). 0.18s 동안 이동이 없으면 걷기를 멈춘다. 바뀌었으면 true. */
    fun tickSprite(now: Double): Boolean {
        val sprite = (character as? ResolvedCharacter.Sprite)?.runtime ?: return false
        if (walking && now - lastWalkAt > library.motion.engine.walkStopTimeoutS) {
            walking = false
            applyFacing(now)
            return true
        }
        return sprite.tick(now)
    }

    // ---------------------------------------------------------------- 정지

    /**
     * 화면 슬립 · 잠금 · 창 숨김. 정지 동안 장면 시계가 멈춘다. 재개 순간 정지 중 **벽시계로** 만료된 리액션은 잔여 모션을 걷어 단위로 세운다
     * (맥 reconcileAfterResume — 안 걷으면 재개 첫 프레임에 옛 모션이 뒤늦게 튄다): 리액션 재생 · 화들짝 깨기(되튀기 포함) · 조용한 기상(상태가 없어 언제나).
     * 아직 만료 전이면 이어서 재생하고(0.x초 잔여), 자는 중(끝 자세를 쥔 졸기)은 건드리지 않는다.
     *
     * **입자 · 💤 는 호출부 계약이다**: 맥은 같은 정리에서 색종이 · 스파크 · 흡수 방출구도 걷는다(만료됐고 자는 중이 아니면 모션이 남지 않았어도).
     * 재생기는 입자를 쥐지 않으므로([ParticleBurst] 는 호출부가 들고 그린다) 재개 때 엔진 상태가 만료됐고 [sleeping] 이 아니면 호출부가 버스트를 버린다.
     * @return 재개하면서 남은 모션을 걷었으면 true(호출부가 같은 순간 입자를 버리는 신호로 쓸 수 있다). 정지로 들어갈 때는 언제나 false.
     */
    fun setSuspended(value: Boolean, now: Double): Boolean {
        if (value == suspended) return false
        if (value) {
            frozenScene = sceneTime(now)
            suspended = true
            return false
        }
        wallBase = now
        suspended = false
        val expired = when (val w = wrapper) {
            is Wrapper.Playing -> !w.holdsEnd && now - w.startWall >= w.wallDuration
            is Wrapper.ToIdentity -> now - w.startWall >= w.wallDuration
            else -> false
        }
        if (expired) wrapper = Wrapper.Idle
        return expired
    }

    // ---------------------------------------------------------------- 자세

    /** 지금 리액션 모션이 끝나는 장면 시각(fps 정책). 재생 중이 아니면 null. */
    fun reactionEndsAt(): Double? = when (val w = wrapper) {
        is Wrapper.Playing -> if (w.holdsEnd) null else w.startScene + w.track.durationS
        is Wrapper.ToIdentity -> w.startScene + w.seconds + (w.bounce?.durationS ?: 0.0)
        else -> null
    }

    val activeReaction: String? get() = (wrapper as? Wrapper.Playing)?.reaction

    /**
     * wrapper 자세(위치는 **모델 단위**). 트랙이 끝난 것을 보면 그 자리에서 상태를 접는다(끝 자세를 쥐는 졸기 → Holding, 나머지 → Idle) —
     * 그래서 `now` 는 단조로 준다(시간을 거꾸로 묻지 않는다).
     */
    fun wrapperPose(now: Double): PoseSample {
        val scene = sceneTime(now)
        return when (val w = wrapper) {
            Wrapper.Idle -> PoseSample.IDENTITY
            is Wrapper.Holding -> w.pose
            is Wrapper.Playing -> {
                val t = scene - w.startScene
                if (t >= w.track.durationS) {
                    if (w.holdsEnd) {
                        val end = toModel(w.track.sampleAt(w.track.count - 1), w.track)
                        wrapper = Wrapper.Holding(end)
                        end
                    } else {
                        wrapper = Wrapper.Idle
                        PoseSample.IDENTITY
                    }
                } else {
                    toModel(w.track.sample(t), w.track)
                }
            }
            is Wrapper.ToIdentity -> {
                val t = scene - w.startScene
                if (t <= w.seconds) {
                    val k = 1 - w.curve.apply(if (w.seconds > 0) t / w.seconds else 1.0)
                    PoseSample(
                        Vec3(1 + (w.fromScale.x - 1) * k, 1 + (w.fromScale.y - 1) * k, 1 + (w.fromScale.z - 1) * k),
                        SceneKitEuler.toQuat(w.fromEuler * k),
                        w.fromPosition * k,
                    )
                } else {
                    val b = w.bounce
                    if (b != null && t - w.seconds < b.durationS) toModel(b.sample(t - w.seconds), b)
                    else { wrapper = Wrapper.Idle; PoseSample.IDENTITY }
                }
            }
        }
    }

    private fun toModel(s: PoseSample, track: MotionTrack): PoseSample =
        if (track.positionUnits == "extent") PoseSample(s.scale, s.rotation, s.position * character.extent) else s

    /** facing 노드 각(도) — 3D 는 방향 × 40°, 스프라이트는 언제나 0(텍스처로만 돈다 — 평면을 돌리면 카드가 기울어 보인다). */
    fun facingDegrees(): Double = if (character is ResolvedCharacter.Sprite) 0.0 else facing * library.motion.engine.dragFacingDeg

    /** idle 시각(장면 초, 캐릭터 교체 기준). */
    fun idleTime(now: Double): Double = sceneTime(now) - idleOriginScene

    /** 노드 사슬 world. */
    fun chain(now: Double): NodeChain = NodeChain.of(wrapperPose(now), facingDegrees(), library.motion.idle, idleTime(now))

    /** 맥 기준 activeFPS(30) 를 쓸 때인가 — 리액션 재생 + 0.1s, 깜빡임(엔진이 쥔 감은 눈 포함 — 졸기는 아니다), 걷기. */
    fun isActive(now: Double, blinking: Boolean = isBlinking(now) || (heldClosed && !sleeping)): Boolean =
        FramePacer.isActive(sceneTime(now), reactionEndsAt(), library.motion.engine.fpsResetAfterS, blinking, walking)

    companion object {
        const val DROWSY = "drowsy"
        const val WAKE = "wake"
        const val QUIET_RISE = "quietRise"
    }
}
