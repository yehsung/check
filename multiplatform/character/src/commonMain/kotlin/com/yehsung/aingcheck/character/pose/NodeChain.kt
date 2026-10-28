// 원본: Sources/check/CheckCharacter3DView.swift @ 1b8260d (노드 사슬 root → check.reactionWrapper → check.facingWrapper → 캐릭터, :156-163 · idle :560-573)
package com.yehsung.aingcheck.character.pose

import com.yehsung.aingcheck.character.bake.IdleSpec
import com.yehsung.aingcheck.character.bake.PoseSample
import com.yehsung.aingcheck.character.math.Angles
import com.yehsung.aingcheck.character.math.Mat4
import com.yehsung.aingcheck.character.math.Quat
import com.yehsung.aingcheck.character.math.Vec3

/**
 * 맥 노드 사슬의 world 행렬을 다시 짓는다(F §5.1 NodeChain). 세 칸:
 *  - wrapper: 리액션 트랙 표본(위치는 모델 단위로 이미 바꾼 것)
 *  - facing: 드래그 · 보드 바라보기 y 스냅(−40° / 0 / +40°)
 *  - character: idle 부유(y 이동) · 살랑(y 회전)
 * world(character) = W · F · C. 칸 고르기 · 4점 정합 · 후광이 전부 이 값 하나를 본다.
 */
data class NodeChain(val wrapper: Mat4, val facing: Mat4, val character: Mat4) {
    companion object {
        /**
         * @param wrapperPose 리액션 자세. 위치는 **모델 단위**(트랙이 extent 단위면 호출부가 extent 를 곱해 넘긴다).
         * @param facingDeg facing 노드 y 각(도) — 3D 는 방향 × 40°, 스프라이트는 언제나 0(텍스처로만 돈다).
         * @param idleBob · idleSway 캐릭터 노드 idle(모델 단위 · 라디안).
         */
        fun of(wrapperPose: PoseSample, facingDeg: Double, idleBob: Double, idleSway: Double): NodeChain {
            val w = Mat4.trs(wrapperPose.position, wrapperPose.rotation, wrapperPose.scale)
            val f = w * Mat4.rotationY(Angles.rad(facingDeg))
            val c = f * Mat4.trs(Vec3(0.0, idleBob, 0.0), Quat.axisAngle(Vec3.UP, idleSway), Vec3(1.0, 1.0, 1.0))
            return NodeChain(w, f, c)
        }

        /** idle 공식으로 캐릭터 노드를 채운다(t = idle 시작 기준 장면 초). */
        fun of(wrapperPose: PoseSample, facingDeg: Double, idle: IdleSpec, idleTime: Double): NodeChain {
            val (bob, sway) = idle.evaluate(idleTime)
            return of(wrapperPose, facingDeg, bob, sway)
        }
    }
}
