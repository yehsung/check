// 조정자 핀(W-windows-resume W-3·xplat-w2/pins.md) — 갈래는 읽기만
// 출처: pins.md C · W-3 #17. 지시서의 DesktopFeatureFlags(shell.md)·tokenUploadEnabled(tokens.md)는 전부 이것 하나로 접는다.
package com.yehsung.aingcheck.feature.desktop

import com.yehsung.aingcheck.core.session.app.AppConfig

/**
 * Windows 기능 깃발 **한 자리**(W-3 #17). 값의 출처는 desktopApp 생성 상수 DesktopFlags(-Paingcheck.windows.<이름>) 이고,
 * AppGraph 의 fromBuild() 한 곳에서만 만든다. 기본값을 true 로 바꾸지 않는다 — 서버 ⑥ 으로 상수를 내리는 빌드에서 사용자 승인 뒤 켠다.
 */
data class DesktopAppConfig(
    /** 판돈 대결 진입(오목·체스·테트리스 1:1). 꺼지면 신청 안내도 띄우지 않는다(W-3 #7). */
    val duels: Boolean = false,
    val poke: Boolean = false,
    val ultra: Boolean = false,
    val chatToast: Boolean = false,
    val forkSafe: Boolean = false,
    /** token_usage_* 표(월·일·하트비트) 쓰기. 서버 ④(M5)+⑥ 전엔 false(W-3 #11). */
    val tokenUpload: Boolean = false,
    /** 조정 ⑤: 흡수 세션 찌르기 소비(poke.md 공용 패치 A 대신). */
    val adoptedPokeConsume: Boolean = false,
    /** 관전·순위(W-3 #4 — 맥과 같게 켠다). */
    val spectator: Boolean = true,
) {
    /** core/session AppConfig 의 깃발은 여기서만 채운다(W-3 #17). */
    fun toAppConfig(): AppConfig = AppConfig(duelsEnabled = duels)

    companion object
}
