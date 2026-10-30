// 조정자 핀(W-windows-resume W-3·xplat-w2/pins.md) — 갈래는 읽기만
// 출처: xplat-w1/briefs/tokens.md §4 ②(규칙 공유 h1·h2·h3). java.nio 를 써서 desktopMain 에 둔다.
package com.yehsung.aingcheck.feature.desktop

import java.nio.file.Path

/**
 * AI 도구 홈 경로의 **유일한 출처**. tokens·ailimits 패키지는 `System.getProperty("user.home")`·`System.getenv`·`USERPROFILE` 을
 * 직접 읽지 않는다 — 경로는 이것으로만(홈 격리의 근거, 시험은 합성 홈을 넣는다).
 */
class DesktopAiHomes(val userHome: Path, private val resolveCodexHome: () -> Path) {
    fun claudeDir(): Path = userHome.resolve(".claude")

    /** 부를 때마다 다시 푼다: HKCU → HKLM → 프로세스 환경 → %USERPROFILE%\.codex (G §8-13, WindowsEnvironment.codexHome). */
    fun codexHome(): Path = resolveCodexHome()

    companion object {
        /** 시험·합성 홈: CODEX_HOME 은 `<home>/.codex` 고정. */
        fun synthetic(home: Path): DesktopAiHomes = DesktopAiHomes(home) { home.resolve(".codex") }
    }
}
