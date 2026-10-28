// 원본: Sources/CheckCore/CharacterKit/SpriteCharacterNode.swift @ 1b8260d (planeSize · contentsTransform · atlasUV — 평면 기하만, SceneKit 노드는 없다)
package com.yehsung.aingcheck.character.sprite

import com.yehsung.aingcheck.character.math.Vec2
import com.yehsung.aingcheck.character.math.Vec3
import com.yehsung.aingcheck.core.rules.character.CharacterManifest

/**
 * 2D 스프라이트 캐릭터의 평면 한 장(F §5.1: 스프라이트도 맥에서는 3D 씬 안의 평면이라, 네 꼭짓점을 같은 카메라로 투영해
 * 호모그래피로 그리면 맥과 기하가 **정확히** 같다 — 울트라의 x ±12° 와 뒷면 미러 포함).
 */
object SpritePlane {
    /** 평면의 최장변(모델 단위) — `aing.scn` bbox 실측(x 폭 1.9210). 카메라 구도와 리액션 진폭이 이 값 하나로 따라온다. 바꾸지 마라. */
    const val TARGET_EXTENT = 1.9210

    /** 프레임 종횡비를 지키며 최장변을 [TARGET_EXTENT] 로 맞춘 평면 (너비, 높이). */
    fun planeSize(frame: CharacterManifest.Rect): Pair<Double, Double> {
        val w = frame.w.toDouble(); val h = frame.h.toDouble()
        if (!(w > 0 && h > 0)) return TARGET_EXTENT to TARGET_EXTENT
        return if (w >= h) TARGET_EXTENT to TARGET_EXTENT * h / w else TARGET_EXTENT * w / h to TARGET_EXTENT
    }

    /**
     * INV-SpriteCharacterNode-0d867c0f 이식: 평면 크기는 **frontIdle 첫 프레임으로 한 번만** 정한다. 프레임마다 다시 재면 걷는 동안
     * 캐릭터가 커졌다 작아진다(4족 passing 프레임이 18.7% 주저앉은 실측). 프레임 전환은 텍스처 좌표만 바꾼다.
     */
    fun planeSize(manifest: CharacterManifest): Pair<Double, Double>? {
        val first = manifest.atlas?.states?.get(CharacterManifest.StateKey.frontIdle)?.frames?.firstOrNull() ?: return null
        return planeSize(first)
    }

    /** 평면 국소 네 꼭짓점(TL · TR · BR · BL, z = 0) — SCNPlane 은 중심 원점, 그림 위 = +y. */
    fun localCorners(size: Pair<Double, Double>): List<Vec3> {
        val hw = size.first / 2; val hh = size.second / 2
        return listOf(Vec3(-hw, hh, 0.0), Vec3(hw, hh, 0.0), Vec3(hw, -hh, 0.0), Vec3(-hw, -hh, 0.0))
    }

    /**
     * 셀을 평면 전체에 앉힐 때 평면의 네 꼭짓점(TL · TR · BR · BL)이 가리키는 **아틀라스 픽셀**(연속 좌표).
     * 정방향 `u' = u·w + x`, v 는 뒤집지 않는다(rect 도 UV 도 위 → 아래). 미러는 좌우 꼭짓점을 바꾼다(`u' = (1−u)·w + x`).
     */
    fun frameCorners(frame: CharacterManifest.Rect, mirrored: Boolean): List<Vec2> {
        val x0 = frame.x.toDouble(); val y0 = frame.y.toDouble()
        val x1 = (frame.x + frame.w).toDouble(); val y1 = (frame.y + frame.h).toDouble()
        return if (!mirrored) listOf(Vec2(x0, y0), Vec2(x1, y0), Vec2(x1, y1), Vec2(x0, y1))
        else listOf(Vec2(x1, y0), Vec2(x0, y0), Vec2(x0, y1), Vec2(x1, y1))
    }

    /**
     * 평면 UV → 아틀라스 전체 UV(`atlasUV(planeUV:frame:mirrored:atlasSize:)`). 히트가 주는 UV 는 재질 변환 **전**의 평면 UV 라
     * 마스크에 넘기기 전에 현재 프레임 · 미러를 여기서 다시 먹인다 — 두 식이 갈리면 걷는 동안만 클릭이 빗나간다.
     */
    fun atlasUV(planeU: Double, planeV: Double, frame: CharacterManifest.Rect, mirrored: Boolean, atlasWidth: Int, atlasHeight: Int): Vec2 {
        if (atlasWidth <= 0 || atlasHeight <= 0 || frame.w <= 0 || frame.h <= 0) return Vec2(planeU, planeV)
        val u = if (mirrored) 1 - planeU else planeU
        return Vec2((u * frame.w + frame.x) / atlasWidth, (planeV * frame.h + frame.y) / atlasHeight)
    }
}
