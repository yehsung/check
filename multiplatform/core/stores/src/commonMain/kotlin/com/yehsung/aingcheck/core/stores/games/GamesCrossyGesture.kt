// 원본: Sources/CheckMobileKit/Games/GamesCrossyGesture.swift @ 1a5eeca6
package com.yehsung.aingcheck.core.stores.games

import com.yehsung.aingcheck.core.rules.minigame.MiniGamePoint
import com.yehsung.aingcheck.core.rules.minigame.MiniGameSize
import com.yehsung.aingcheck.core.rules.minigame.crossy.CrossyGame
import kotlin.math.abs
import kotlin.math.hypot

/**
 * 길건너 판 위 제스처 판정의 임계값 전부 — **순수 계산만** 한다(화면 없음). 그래서 JVM 시험이 "손가락 좌표 → 아잉이가 뛴 방향"을 화면 없이 구동한다.
 *
 * [swipeMinDistance] 20 의 근거(Swift 주석 그대로): 탭 문턱 8 바로 위(10~12)면 탭하려던 손가락이 방향으로 새고, 그 오인식은 길건너에서 **차에 치이는 것**이다.
 * 테트리스의 한 칸 문턱(화면 셀 폭)은 되돌릴 수 있는 이동이라 더 민감해도 되지만 길건너는 한 칸이 생사라 한 단계 둔하게 잡았다.
 * 값은 Swift 와 같게 둔다(두 플랫폼 감도가 갈리지 않게). **실기로 아직 안 쟀다** — "쓸어도 안 간다"가 나오면 이 수부터 내린다.
 * [tapMaxDistance]·[tapMaxDuration] 은 테트리스와 같은 수다(같은 손가락, 같은 뜻).
 */
data class CrossyGestureThresholds(val swipeMinDistance: Double = 20.0, val tapMaxDistance: Double = 8.0, val tapMaxDuration: Double = 0.25)

/**
 * 한 번의 접촉(손을 댄 순간 ~ 뗀 순간)을 **뛰기 한 번** 또는 **탭 한 번**으로 바꾼다.
 *
 * **왜 테트리스 트래커를 못 쓰나**: 테트리스는 누적 소비량 방식이다 — 한 번의 끌기가 셀 폭마다 한 칸씩, 여러 칸을 낸다. 길건너에서 앞으로 한 칸은 0.12초 애니메이션이고
 * 엔진은 뛰는 중 입력을 한 칸만 줄 세운다 — 한 번의 끌기로 세 칸을 밀어 넣어도 두 칸은 그냥 사라지고, 손가락이 간 거리와 아잉이가 간 거리가 어긋난다. 그래서 **한 접촉 = 한 칸**이다.
 *
 * **떼기를 기다리지 않는다**: 연타 게임이라 손을 떼고 나서 뛰면 늦다 — 문턱을 넘는 그 순간 방향 하나를 내고 접촉을 소진 표시한다.
 *
 * 상태는 둘뿐이다: 지금 따라가는 접촉의 시작점과 "이 접촉이 이미 한 칸을 냈는가". 시작점으로 새 접촉을 알아보는 까닭은 테트리스 트래커와 같다 — 끌기 끝은 늘 오지 않는다
 * (시스템 제스처·전화 수신으로 취소되면 안 온다). 불리언 하나로 두면 소진 표시가 참인 채 굳어 다음 쓸기가 통째로 죽는다.
 */
class CrossyGestureTracker(val thresholds: CrossyGestureThresholds = CrossyGestureThresholds()) {
    private var startLocation: MiniGamePoint? = null

    /** 이 접촉이 이미 한 칸을 냈는가(끌어서 여러 칸 가기는 없다). */
    var isSpent: Boolean = false
        private set

    /**
     * 시작점부터의 누적 이동을 주면 **이번에 새로 생긴 방향 하나**를 돌려준다(없으면 null). 큰 축 하나만 고른다 — 대각으로 끌어도 두 방향이 같이 나가지 않는다.
     * **동률이면 세로를 고른다** — 앞으로 가는 게임이고, 45° 쓸기의 의도는 거의 늘 '앞'이다.
     */
    fun drag(startLocation: MiniGamePoint, translation: MiniGameSize): CrossyGame.Direction? {
        if (this.startLocation != startLocation) {
            this.startLocation = startLocation
            isSpent = false
        }
        if (isSpent) return null
        val dx = translation.width
        val dy = translation.height
        if (maxOf(abs(dx), abs(dy)) < thresholds.swipeMinDistance) return null
        isSpent = true
        if (abs(dx) > abs(dy)) return if (dx > 0) CrossyGame.Direction.right else CrossyGame.Direction.left
        // 화면 위(−height)가 앞이다 — 엔진의 줄 번호는 앞이 +.
        return if (dy < 0) CrossyGame.Direction.forward else CrossyGame.Direction.back
    }

    /**
     * 끌기 끝 — 이 접촉이 **탭**이었는가. 상태를 비워 다음 접촉을 받는다. 한 칸을 이미 낸 접촉은 탭이 아니다(안 그러면 한 번 쓸기가 **두 칸**이 된다).
     * **죽은 구간이 있다**: 8 이상 20 미만을 움직이고 떼면 아무 일도 안 난다. 0.25초를 넘겨 천천히 떼도 같다 — 틀린 방향은 되돌릴 수 없어(차·강이 기다린다) 애매한 입력을 확정하지 않는다.
     */
    fun end(translation: MiniGameSize, elapsed: Double): Boolean {
        val moved = hypot(translation.width, translation.height)
        val isTap = !isSpent && moved < thresholds.tapMaxDistance && elapsed < thresholds.tapMaxDuration
        startLocation = null
        isSpent = false
        return isTap
    }
}
