// 원본: Sources/check/CheckCodexAccountUsage.swift:204-210 @ a63fea2 (맥은 로그인 셸에 CODEX_HOME 을 묻는다)
//       · 설계 D§12-1(CODEX_HOME 찾기: ① 프로세스 환경 → ② HKCU\Environment → ③ HKLM\…\Session Manager\Environment,
//         레지스트리는 스캔마다 다시 읽는다, REG_EXPAND_SZ 는 펼친다) · gh:openai/codex codex-rs/utils/home-dir(기본 ~/.codex)
//
// 왜 레지스트리까지 보나: 실행 중인 프로세스는 로그인 뒤 사용자가 바꾼 환경 변수를 모른다(트레이 앱은 로그인 때 떠서 며칠 산다).
// PowerShell 프로필을 실행해 묻는 길은 부작용·지연이 있어 쓰지 않는다(D§12-1).
// CLAUDE_CONFIG_DIR 은 일부러 넓히지 않는다 — 맥도 두 번째 계정을 못 본다, 플랫폼마다 세는 범위가 다르면 순위가 불공정하다(D§12-1).
package com.yehsung.aingcheck.desktop.platform.windows.env

import com.sun.jna.Pointer
import com.sun.jna.platform.win32.Advapi32
import com.sun.jna.platform.win32.Advapi32Util
import com.sun.jna.platform.win32.WinError
import com.sun.jna.platform.win32.WinNT
import com.sun.jna.platform.win32.WinReg
import com.sun.jna.ptr.IntByReference
import com.yehsung.aingcheck.core.foundation.platform.desktop.EnvReader

/** 레지스트리 문자열 값과 그 형(REG_EXPAND_SZ 면 펼쳐야 한다). */
data class RegistryString(val value: String, val expandable: Boolean)

/** 환경 변수 하나를 레지스트리에서 읽는다(시험은 가짜 표). */
fun interface RegistryEnvironmentReader {
    fun read(name: String): RegistryString?
}

class WindowsEnvironment(
    private val process: EnvReader,
    private val userRegistry: RegistryEnvironmentReader,
    private val machineRegistry: RegistryEnvironmentReader,
) : EnvReader {
    override fun get(name: String): String? = process[name]

    enum class CodexHomeSource { PROCESS_ENV, USER_REGISTRY, MACHINE_REGISTRY, DEFAULT }

    data class CodexHome(val path: String, val source: CodexHomeSource)

    /** 부를 때마다 레지스트리를 다시 읽는다(스캔마다). 빈 값은 없는 것으로 본다. */
    fun codexHome(): CodexHome {
        process[CODEX_HOME]?.takeIf { it.isNotBlank() }?.let { return CodexHome(it.trim(), CodexHomeSource.PROCESS_ENV) }
        userRegistry.read(CODEX_HOME)?.let { v ->
            expandIfNeeded(v)?.let { return CodexHome(it, CodexHomeSource.USER_REGISTRY) }
        }
        machineRegistry.read(CODEX_HOME)?.let { v ->
            expandIfNeeded(v)?.let { return CodexHome(it, CodexHomeSource.MACHINE_REGISTRY) }
        }
        val profile = process["USERPROFILE"]?.takeIf { it.isNotBlank() } ?: System.getProperty("user.home")
        return CodexHome(profile.trimEnd('\\', '/') + "\\.codex", CodexHomeSource.DEFAULT)
    }

    private fun expandIfNeeded(v: RegistryString): String? {
        val text = if (v.expandable) expandEnvironmentStrings(v.value) { process[it] } else v.value
        return text.trim().takeIf { it.isNotEmpty() }
    }

    companion object {
        const val CODEX_HOME = "CODEX_HOME"
        const val USER_ENV_KEY = "Environment"
        const val MACHINE_ENV_KEY = "SYSTEM\\CurrentControlSet\\Control\\Session Manager\\Environment"

        /**
         * ExpandEnvironmentStrings 와 같은 뜻(순수 함수): `%이름%` 을 값으로 바꾸고(이름은 대소문자 무시), 정의되지 않은 것은
         * `%이름%` 그대로 둔다. 짝이 없는 `%` 는 글자 그대로. 한 번만 펼친다(값 안의 `%…%` 는 다시 펼치지 않는다).
         */
        fun expandEnvironmentStrings(raw: String, lookup: (String) -> String?): String {
            val out = StringBuilder(raw.length)
            var i = 0
            while (i < raw.length) {
                val c = raw[i]
                if (c == '%') {
                    val end = raw.indexOf('%', i + 1)
                    if (end > i + 1) {
                        val name = raw.substring(i + 1, end)
                        val value = lookup(name) ?: lookupIgnoringCase(name, lookup)
                        if (value != null) {
                            out.append(value)
                            i = end + 1
                            continue
                        }
                        out.append(raw, i, end)
                        i = end
                        continue
                    }
                }
                out.append(c)
                i++
            }
            return out.toString()
        }

        private fun lookupIgnoringCase(name: String, lookup: (String) -> String?): String? =
            lookup(name.uppercase()) ?: lookup(name.lowercase())

        fun system(): WindowsEnvironment = WindowsEnvironment(
            process = SystemEnvReader,
            userRegistry = registryReader(WinReg.HKEY_CURRENT_USER, USER_ENV_KEY),
            machineRegistry = registryReader(WinReg.HKEY_LOCAL_MACHINE, MACHINE_ENV_KEY),
        )

        /**
         * 형을 가려 읽는다: REG_SZ 는 그대로, REG_EXPAND_SZ 는 펼친다(같은 문자열이라도 뜻이 다르다).
         * jna-platform 의 registryGetStringValue 는 REG_EXPAND_SZ 도 받아 버린다(windows-latest 러너 실측, run 39621457060) —
         * 그래서 형은 RegQueryValueEx 로 따로 묻는다.
         */
        fun registryReader(root: WinReg.HKEY, key: String) = RegistryEnvironmentReader { name ->
            runCatching {
                when (registryValueType(root, key, name)) {
                    WinNT.REG_SZ -> RegistryString(Advapi32Util.registryGetStringValue(root, key, name), expandable = false)
                    WinNT.REG_EXPAND_SZ -> RegistryString(Advapi32Util.registryGetExpandableStringValue(root, key, name), expandable = true)
                    else -> null
                }
            }.getOrNull()
        }

        /** 값의 레지스트리 형(REG_SZ=1, REG_EXPAND_SZ=2 …). 키·값이 없으면 null. */
        fun registryValueType(root: WinReg.HKEY, key: String, name: String): Int? {
            val hk = WinReg.HKEYByReference()
            if (Advapi32.INSTANCE.RegOpenKeyEx(root, key, 0, WinNT.KEY_READ, hk) != WinError.ERROR_SUCCESS) return null
            try {
                val type = IntByReference()
                val size = IntByReference()
                val rc = Advapi32.INSTANCE.RegQueryValueEx(hk.value, name, 0, type, null as Pointer?, size)
                return if (rc == WinError.ERROR_SUCCESS || rc == WinError.ERROR_MORE_DATA) type.value else null
            } finally {
                Advapi32.INSTANCE.RegCloseKey(hk.value)
            }
        }
    }
}

/** 프로세스 환경(Windows 는 이름 대소문자를 가리지 않는다 — System.getenv 가 그렇게 찾는다). */
object SystemEnvReader : EnvReader {
    override fun get(name: String): String? = System.getenv(name)
}
