package com.yehsung.aingcheck.desktop.platform.windows.env

import com.yehsung.aingcheck.desktop.platform.windows.env.WindowsEnvironment.CodexHomeSource
import com.yehsung.aingcheck.desktop.platform.windows.paths.EnvReaderMap
import kotlin.test.Test
import kotlin.test.assertEquals

/** D§12-1 CODEX_HOME 찾기 순서와 REG_EXPAND_SZ 펼치기. */
class WindowsEnvironmentTest {
    private fun env(
        process: Map<String, String> = mapOf("USERPROFILE" to "C:\\Users\\tester"),
        user: Map<String, RegistryString> = emptyMap(),
        machine: Map<String, RegistryString> = emptyMap(),
    ) = WindowsEnvironment(EnvReaderMap(process), { user[it] }, { machine[it] })

    @Test
    fun processEnvironmentWins() {
        val e = env(
            process = mapOf("CODEX_HOME" to "D:\\codex-proc", "USERPROFILE" to "C:\\Users\\tester"),
            user = mapOf("CODEX_HOME" to RegistryString("D:\\codex-user", false)),
            machine = mapOf("CODEX_HOME" to RegistryString("D:\\codex-machine", false)),
        )
        assertEquals(WindowsEnvironment.CodexHome("D:\\codex-proc", CodexHomeSource.PROCESS_ENV), e.codexHome())
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
