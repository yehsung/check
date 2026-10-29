// 원본: 없음(새 코드) — 설계 D-windows-platform §3-3 "토글 경합: 열린 상태에서 아이콘을 누르면 '비활성화로 닫힘 → 클릭으로 다시 열림'이
//       된다. 비활성화로 닫힌 지 300ms 안에 같은 아이콘 클릭이 오면 무시한다."
package com.yehsung.aingcheck.desktop.shell.flyout

/** 순수 판정. 시각은 단조 밀리초. 경계: 닫힌 시각 t 에서 t+299 클릭은 무시, t+300 은 연다. */
class FlyoutToggleGuard {
    private var closedByDeactivationAt: Long? = null

    fun markClosedByDeactivation(nowMillis: Long) {
        closedByDeactivationAt = nowMillis
    }

    fun shouldIgnoreClick(nowMillis: Long): Boolean {
        val t = closedByDeactivationAt ?: return false
        return nowMillis - t in 0 until GUARD_MILLIS
    }

    companion object {
        const val GUARD_MILLIS = 300L
    }
}
