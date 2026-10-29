// 조정자 핀(W-windows-resume W-3·xplat-w2/pins.md) — 갈래는 읽기만
// 출처: xplat-w1/briefs/shell.md §4 4 + overlay.md I-7 + pins.md E 조정 ⑧⑨. 중재 규칙 = W-3 #6(말풍선 > 토스트 > 빨간 점, 점은 늘).
// 시그니처만 — 중재 구현은 W3-c1, 풍선 구현은 W1-f2(platform/windows/tray). core/foundation TrayHost 는 고치지 않는다.
package com.yehsung.aingcheck.desktop.shellapi

enum class NotifyKind { MESSAGE, POKE, DUEL_INVITE, UPDATE }

enum class NotifySurface { BUBBLE, TOAST, DOT_ONLY }

/** 집중 모드 판정은 W2-g 가 계산한 불 값으로만 받는다(다시 만들지 않음). W5-b 는 overlayVisible 만 넘긴다(G §8-3). */
data class NotifyContext(
    val overlayVisible: Boolean,
    val fullscreenQuiet: Boolean,
    val bubbleAllowedByFocus: Boolean,
    val toastEnabled: Boolean,
)

/** 표면 고르기 판정 한 곳(W3-c1 구현). 같은 사건은 한 표면만. */
fun interface NotifyArbiter {
    fun surface(kind: NotifyKind, ctx: NotifyContext): NotifySurface
}

/** overlay.md I-7: 오버레이가 지금 보이나 · 숨은 캐릭터를 8초 peek 할 수 있나(사용자가 끈 경우만 false — W-3 #6). */
data class OverlayAvailability(val visibleNow: Boolean, val canPeek: Boolean) {
    companion object {
        val NONE = OverlayAvailability(visibleNow = false, canPeek = false)
    }
}

/** 조정 ⑨: 트레이 풍선(토스트). 구현은 W1-f2, 사용은 W3-c1. 반환 = 실제로 띄웠나. */
interface BalloonNotifier {
    fun showBalloon(title: String, body: String, kind: NotifyKind, respectQuietTime: Boolean): Boolean
    fun setOnBalloonClick(handler: (NotifyKind) -> Unit)

    /** 조립 전·시험 자리: 띄우지 않는다. */
    object None : BalloonNotifier {
        override fun showBalloon(title: String, body: String, kind: NotifyKind, respectQuietTime: Boolean): Boolean = false
        override fun setOnBalloonClick(handler: (NotifyKind) -> Unit) {}
    }
}
