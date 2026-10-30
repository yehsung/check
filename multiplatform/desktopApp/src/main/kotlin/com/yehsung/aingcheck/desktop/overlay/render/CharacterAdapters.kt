// 원본: 없음(얇은 어댑터) — overlay.md §4 I-2 "b2 가 CharacterPlayer 를 얇게 감싼다" · F §5.3(CharacterFrames.compute/draw)
//
// 굽기 자산·스프라이트 아틀라스를 앱 자원으로 싣는 일(조정자 P2)은 여기 밖이다 — [storeFor]·[spriteAtlas] 는 조립(P3)이 넘긴다.
package com.yehsung.aingcheck.desktop.overlay.render

import com.yehsung.aingcheck.character.bake.BakedFinish
import com.yehsung.aingcheck.character.player.CharacterFrames
import com.yehsung.aingcheck.character.player.CharacterPlayer
import com.yehsung.aingcheck.character.player.WakeKind
import com.yehsung.aingcheck.character.render.BakeImageStore
import com.yehsung.aingcheck.character.render.DrawableImage
import com.yehsung.aingcheck.character.render.QuadCanvas
import com.yehsung.aingcheck.desktop.overlay.engine.CharacterSink

/** I-2 — 엔진의 캐릭터 문을 플레이어에 그대로 잇는다(판정 0). */
class CharacterPlayerSink(private val player: CharacterPlayer) : CharacterSink {
    override val currentCharacterId: String get() = player.currentCharacterId
    override fun play(reaction: String, now: Double): Boolean = player.play(reaction, now)
    override fun interrupt(now: Double) = player.interrupt(now)
    override fun beginSleep(now: Double): Boolean = player.beginSleep(now)
    override fun wake(kind: WakeKind, now: Double): Boolean = player.wake(kind, now)
    override fun blink(now: Double): Boolean = player.blink(now)
    override fun setEyesClosed(closed: Boolean) = player.setEyesClosed(closed)
    override fun setFacing(direction: Int, moving: Boolean, now: Double) = player.setFacing(direction, moving, now)
    override fun swapCharacter(id: String?, now: Double) = player.swapCharacter(id, now)
    override fun setSuspended(value: Boolean, now: Double): Boolean = player.setSuspended(value, now)
}

/**
 * 플레이어 자세 → 프레임 → 그리기. [drawHalo] 기본 **false**: 레이어드 창에서 후광 픽셀(알파>0)은 몸 둘레 클릭을 먹는다(D §9-1 —
 * 맥 판정은 후광을 몸에서 뺐고 클릭을 통과시켰다). 후광을 살릴지는 VM 눈 판정 뒤 결정(보고 unresolved).
 */
class PlayerCharacterLayer(
    private val player: CharacterPlayer,
    private val storeFor: (BakedFinish) -> BakeImageStore,
    private val spriteAtlas: (String) -> DrawableImage?,
    private val drawHalo: Boolean = false,
) : CharacterLayer {
    override fun draw(canvas: QuadCanvas, widthPx: Int, heightPx: Int, now: Double) {
        val frame = CharacterFrames.compute(player, now, widthPx.toDouble(), heightPx.toDouble()) ?: return
        CharacterFrames.draw(canvas, frame, storeFor, spriteAtlas, drawHalo)
    }
}
