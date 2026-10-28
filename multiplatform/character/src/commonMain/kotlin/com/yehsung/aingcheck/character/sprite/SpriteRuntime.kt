// 원본: Sources/CheckCore/CharacterKit/SpriteRuntime.swift @ 1b8260d
package com.yehsung.aingcheck.character.sprite

import com.yehsung.aingcheck.core.rules.character.CharacterManifest
import com.yehsung.aingcheck.core.rules.character.SpriteFramePlayer

/**
 * 스프라이트 캐릭터 한 마리의 **살아 있는 상태** — 지금 어느 상태(frontIdle/sideIdle/sideWalk)의 몇 번 프레임을, 뒤집어서 그리는가.
 * 프레임 시계(W1-c [SpriteFramePlayer])와 마스크를 한 캐릭터 분량으로 묶는다: 그리기 · 걷기 틱 · 클릭 알파 판정이 **같은 값**을 보게.
 * 폴백은 여기 한 곳(`frontIdle`)에서 접는다.
 */
class SpriteRuntime private constructor(
    val manifest: CharacterManifest,
    val atlasWidth: Int,
    val atlasHeight: Int,
    val mask: SpriteAlphaMask,
    private val spec: CharacterManifest.Atlas,
) {
    private val players: Map<String, SpriteFramePlayer> = spec.states.mapValues { SpriteFramePlayer(it.value) }

    /** 지금 재생 중인 상태 키 — **폴백까지 접힌 결과값**(요청값이 아니다). */
    var stateKey: String = CharacterManifest.StateKey.frontIdle
        private set
    var mirrored: Boolean = false
        private set
    var frameIndex: Int = 0
        private set
    var stateStartedAt: Double = 0.0
        private set

    /** 지금 그릴 셀. 범위를 벗어나면 frontIdle 첫 프레임(캐릭터가 사라지는 것보다 낫다). */
    val currentFrame: CharacterManifest.Rect
        get() {
            val state = spec.states[stateKey]
            if (state == null || state.frames.isEmpty()) {
                return spec.states[CharacterManifest.StateKey.frontIdle]?.frames?.firstOrNull()
                    ?: CharacterManifest.Rect(0, 0, spec.width, spec.height)
            }
            return state.frames[frameIndex.coerceIn(0, state.frames.size - 1)]
        }

    fun totalDuration(key: String): Double = players[resolve(key)]?.totalDuration ?: 0.0

    /** 상태가 매니페스트에 **실제로** 있는가(폴백 없이). */
    fun hasState(key: String): Boolean = spec.states[key]?.frames?.isNotEmpty() == true

    /** 상태 전환. **같은 (상태, 미러) 재호출은 no-op**(드래그가 매 이벤트 같은 방향을 다시 준다 — 리셋하면 걷기가 첫 프레임에 머문다). */
    fun setState(key: String, mirrored: Boolean, now: Double) {
        val resolved = resolve(key)
        if (resolved == stateKey && mirrored == this.mirrored) return
        stateKey = resolved
        this.mirrored = mirrored
        stateStartedAt = now
        frameIndex = players[resolved]?.frameIndex(0.0) ?: 0
    }

    /** 프레임 진행. 바뀌었으면 true(호출부는 그때만 다시 그린다). */
    fun tick(now: Double): Boolean {
        val player = players[stateKey] ?: return false
        val next = player.frameIndex(now - stateStartedAt)
        if (next == frameIndex) return false
        frameIndex = next
        return true
    }

    /** 평면 UV → 알파. **atlasUV 를 반드시 거친다**(현재 프레임 · 미러). */
    fun isOpaque(planeU: Double, planeV: Double): Boolean {
        val uv = SpritePlane.atlasUV(planeU, planeV, currentFrame, mirrored, atlasWidth, atlasHeight)
        return mask.isOpaque(uv.x, uv.y)
    }

    private fun resolve(key: String): String = if (spec.states[key]?.frames?.isNotEmpty() == true) key else CharacterManifest.StateKey.frontIdle

    companion object {
        /**
         * 스프라이트가 아니거나, 매니페스트가 말하는 아틀라스 크기와 실제 그림이 다르거나, 마스크를 못 구우면 null —
         * **호출부는 아잉으로 접는다**(`SpriteRuntime.init?` · `SpriteCharacterNode.make` 와 같은 판정).
         */
        fun make(manifest: CharacterManifest, atlasWidth: Int, atlasHeight: Int, mask: SpriteAlphaMask?): SpriteRuntime? {
            if (manifest.kind != CharacterManifest.Kind.sprite) return null
            val spec = manifest.atlas ?: return null
            if (spec.width != atlasWidth.toLong() || spec.height != atlasHeight.toLong()) return null
            if (mask == null || mask.width != atlasWidth || mask.height != atlasHeight) return null
            if (spec.states[CharacterManifest.StateKey.frontIdle]?.frames?.isNotEmpty() != true) return null
            return SpriteRuntime(manifest, atlasWidth, atlasHeight, mask, spec)
        }
    }
}
