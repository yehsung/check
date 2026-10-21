// 원본: Sources/CheckCore/CheckCodexAccountUsage.swift:204-210 @ a63fea2 (맥은 로그인 셸에 CODEX_HOME 을 묻는다) — 시험은 새 코드:
//       G §8-13(CODEX_HOME 은 HKCU → HKLM → 프로세스 환경) · 설계 D§12-1(REG_EXPAND_SZ 펼치기 · ExpandEnvironmentStrings 뜻)
//       · R2 검증 지적(프로세스 먼저면 로그인 때의 낡은 값이 레지스트리 변경을 늘 가린다)
package com.yehsung.aingcheck.desktop.platform.windows.env

import com.yehsung.aingcheck.desktop.platform.windows.env.WindowsEnvironment.CodexHomeSource
import com.yehsung.aingcheck.desktop.platform.windows.paths.EnvReaderMap
import kotlin.test.Test
import kotlin.test.assertEquals

/** G §8-13 CODEX_HOME 찾기 순서(HKCU → HKLM → 프로세스 환경 → 기본)와 D§12-1 REG_EXPAND_SZ 펼치기. */
class WindowsEnvironmentTest {
    private fun env(
        process: Map<String, String> = mapOf("USERPROFILE" to "C:\\Users\\tester"),
        user: Map<String, RegistryString> = emptyMap(),
        machine: Map<String, RegistryString> = emptyMap(),
    ) = WindowsEnvironment(EnvReaderMap(process), { user[it] }, { machine[it] })

    @Test
    fun userRegistryBeatsAStaleProcessEnvironment() {
        // 로그인 때 받은 프로세스 값(D:\codex-old)이 남아 있어도, 그 뒤 사용자가 바꾼 HKCU 값이 이긴다.
        val e = env(
            process = mapOf("CODEX_HOME" to "D:\\codex-old", "USERPROFILE" to "C:\\Users\\tester"),
            user = mapOf("CODEX_HOME" to RegistryString("D:\\codex-user", false)),
            machine = mapOf("CODEX_HOME" to RegistryString("D:\\codex-machine", false)),
        )
        assertEquals(WindowsEnvironment.CodexHome("D:\\codex-user", CodexHomeSource.USER_REGISTRY), e.codexHome())
    }

    @Test
    fun machineRegistryAlsoBeatsTheProcessEnvironment() {
        val e = env(
            process = mapOf("CODEX_HOME" to "D:\\codex-old", "USERPROFILE" to "C:\\Users\\tester"),
            machine = mapOf("CODEX_HOME" to RegistryString("D:\\codex-machine", false)),
        )
        assertEquals(WindowsEnvironment.CodexHome("D:\\codex-machine", CodexHomeSource.MACHINE_REGISTRY), e.codexHome())
    }

    @Test
    fun processEnvironmentIsUsedOnlyWhenTheRegistryHasNoValue() {
        // 터미널에서 set CODEX_HOME=… 하고 띄운 경우: 레지스트리에는 없고 프로세스에만 있다.
        val e = env(process = mapOf("CODEX_HOME" to " D:\\codex-proc ", "USERPROFILE" to "C:\\Users\\tester"))
        assertEquals(WindowsEnvironment.CodexHome("D:\\codex-proc", CodexHomeSource.PROCESS_ENV), e.codexHome())
        // 레지스트리 값이 비어 있으면(빈 글자) 없는 것으로 보고 프로세스로 내려간다.
        val blankRegistry = env(
            process = mapOf("CODEX_HOME" to "D:\\codex-proc", "USERPROFILE" to "C:\\Users\\tester"),
            user = mapOf("CODEX_HOME" to RegistryString("  ", false)),
            machine = mapOf("CODEX_HOME" to RegistryString("", true)),
        )
        assertEquals(CodexHomeSource.PROCESS_ENV, blankRegistry.codexHome().source)
    }

    @Test
    fun userRegistryBeforeMachineRegistry() {
        val e = env(
            user = mapOf("CODEX_HOME" to RegistryString("D:\\codex-user", false)),
            machine = mapOf("CODEX_HOME" to RegistryString("D:\\codex-machine", false)),
        )
        assertEquals(CodexHomeSource.USER_REGISTRY, e.codexHome().source)
        assertEquals("D:\\codex-user", e.codexHome().path)
        val m = env(machine = mapOf("CODEX_HOME" to RegistryString("D:\\codex-machine", false)))
        assertEquals(WindowsEnvironment.CodexHome("D:\\codex-machine", CodexHomeSource.MACHINE_REGISTRY), m.codexHome())
    }

    @Test
    fun defaultIsDotCodexUnderProfile() {
        assertEquals(WindowsEnvironment.CodexHome("C:\\Users\\tester\\.codex", CodexHomeSource.DEFAULT), env().codexHome())
    }

    @Test
    fun blankValuesAreTreatedAsMissing() {
        val e = env(
            process = mapOf("CODEX_HOME" to "  ", "USERPROFILE" to "C:\\Users\\tester"),
            user = mapOf("CODEX_HOME" to RegistryString("", false)),
            machine = mapOf("CODEX_HOME" to RegistryString("D:\\m", false)),
        )
        assertEquals(CodexHomeSource.MACHINE_REGISTRY, e.codexHome().source)
        // 셋 다 비면 기본(~\.codex).
        val none = env(process = mapOf("CODEX_HOME" to "  ", "USERPROFILE" to "C:\\Users\\tester"), user = mapOf("CODEX_HOME" to RegistryString("", false)))
        assertEquals(CodexHomeSource.DEFAULT, none.codexHome().source)
    }

    @Test
    fun expandableRegistryValuesAreExpandedButPlainOnesAreNot() {
        val expandable = env(
            process = mapOf("USERPROFILE" to "C:\\Users\\홍길동"),
            user = mapOf("CODEX_HOME" to RegistryString("%USERPROFILE%\\codex-home", expandable = true)),
        )
        assertEquals("C:\\Users\\홍길동\\codex-home", expandable.codexHome().path)
        val plain = env(
            process = mapOf("USERPROFILE" to "C:\\Users\\홍길동"),
            user = mapOf("CODEX_HOME" to RegistryString("%USERPROFILE%\\codex-home", expandable = false)),
        )
        assertEquals("%USERPROFILE%\\codex-home", plain.codexHome().path)
    }

    @Test
    fun expansionFollowsExpandEnvironmentStringsSemantics() {
        val vars = mapOf("A" to "x", "PATHY" to "C:\\p")
        val look: (String) -> String? = { vars[it] }
        assertEquals("x\\y", WindowsEnvironment.expandEnvironmentStrings("%A%\\y", look))
        // 정의 안 된 이름은 그대로 둔다.
        assertEquals("%NOPE%\\y", WindowsEnvironment.expandEnvironmentStrings("%NOPE%\\y", look))
        // 이름은 대소문자를 가리지 않는다(Windows 환경 변수).
        assertEquals("C:\\p", WindowsEnvironment.expandEnvironmentStrings("%pathy%", look))
        // 짝 없는 % 와 빈 %% 는 글자 그대로.
        assertEquals("100%", WindowsEnvironment.expandEnvironmentStrings("100%", look))
        assertEquals("a%%b", WindowsEnvironment.expandEnvironmentStrings("a%%b", look))
        // 값 안의 %…% 는 다시 펼치지 않는다(한 번만).
        assertEquals("%A%", WindowsEnvironment.expandEnvironmentStrings("%B%") { if (it == "B") "%A%" else vars[it] })
        // 정의 안 된 이름 뒤의 % 는 새 이름의 시작이 될 수 있다.
        assertEquals("%NOPEx", WindowsEnvironment.expandEnvironmentStrings("%NOPE%A%", look))
    }
}
