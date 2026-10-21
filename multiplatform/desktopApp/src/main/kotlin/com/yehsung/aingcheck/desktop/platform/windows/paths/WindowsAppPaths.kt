// 원본: 없음(새 코드) — 설계 D§2-5(%LOCALAPPDATA%\aing-check\ — 로밍 아님) · G §8-12(MSIX 안에서 %LOCALAPPDATA% 쓰기는
// Packages 아래로 리디렉션된다 — 경로 설계에 반영) · W0-e 러너 실측(Packages\<PFN>\LocalCache\Local 로 감)
//
// 반영 방식: 패키지(MSIX) 안에서 돌면 **리디렉션이 보낼 바로 그 자리**를 처음부터 경로로 쓴다
// (`%LOCALAPPDATA%\Packages\<PackageFamilyName>\LocalCache\Local\aing-check`). 그래서
//  - 앱 안에서 보는 경로와 디스크의 실제 경로가 같다(로그·진단·사용자 안내에 적는 경로가 참이다),
//  - Windows 판마다 다를 수 있는 파일 시스템 가상화 규칙(유연한 가상화 등)에 기대지 않는다,
//  - 한계: MSIX 를 지우면 이 폴더도 지워진다(금고·무작위 ID 폴백 포함) — 기기 ID 를 다시 계산하는 이유(D§2-5).
// 패키지 밖(MSI·개발 실행)은 `%LOCALAPPDATA%\aing-check`. 사용자 홈(.claude·.codex 읽기)은 리디렉션되지 않는다(W0-e: 패키지 안 .claude 읽기 일치).
package com.yehsung.aingcheck.desktop.platform.windows.paths

import com.sun.jna.ptr.IntByReference
import com.yehsung.aingcheck.core.foundation.platform.desktop.AppPaths
import com.yehsung.aingcheck.core.foundation.platform.desktop.EnvReader
import com.yehsung.aingcheck.desktop.platform.windows.jna.Kernel32X
import com.yehsung.aingcheck.desktop.platform.windows.jna.Win32

data class WindowsAppPaths(
    /** 앱 데이터 뿌리(설정·할 일·금고·기기 ID 폴백). */
    override val dataDir: String,
    override val cacheDir: String,
    override val logDir: String,
    override val userHome: String,
    /** 금고 폴더(D§7). */
    val vaultDir: String,
    /** 레지스트리를 못 읽을 때의 무작위 기기 ID 파일(G §5-1 #6). */
    val installationIdFile: String,
    /** MSIX 패키지 패밀리 이름. 패키지 밖이면 null. */
    val packageFamilyName: String?,
) : AppPaths {
    companion object {
        const val APP_DIR = "aing-check"

        /**
         * 순수 함수. [localAppData]·[userProfile] 은 환경 값(시험은 격리 폴더), [packageFamilyName] 은 GetCurrentPackageFamilyName.
         * 경로는 OS 표기(역슬래시)다. 끝 역슬래시는 떼어 낸다.
         */
        fun resolve(localAppData: String, userProfile: String, packageFamilyName: String?): WindowsAppPaths {
            val lad = localAppData.trimEnd('\\', '/')
            require(lad.isNotEmpty()) { "LOCALAPPDATA 가 비었다" }
            val root = if (packageFamilyName.isNullOrBlank()) {
                "$lad\\$APP_DIR"
            } else {
                require(PFN.matches(packageFamilyName)) { "패키지 패밀리 이름 모양이 아니다: $packageFamilyName" }
                "$lad\\Packages\\$packageFamilyName\\LocalCache\\Local\\$APP_DIR"
            }
            return WindowsAppPaths(
                dataDir = root,
                cacheDir = "$root\\cache",
                logDir = "$root\\logs",
                userHome = userProfile.trimEnd('\\', '/'),
                vaultDir = "$root\\vault",
                installationIdFile = "$root\\installation-id",
                packageFamilyName = packageFamilyName?.takeIf { it.isNotBlank() },
            )
        }

        /** 환경에서 읽는다. LOCALAPPDATA 가 없으면 %USERPROFILE%\AppData\Local(기본 자리). */
        fun fromEnvironment(env: EnvReader, packageFamilyName: String?): WindowsAppPaths {
            val profile = env["USERPROFILE"]?.takeIf { it.isNotBlank() } ?: System.getProperty("user.home")
            val lad = env["LOCALAPPDATA"]?.takeIf { it.isNotBlank() } ?: "$profile\\AppData\\Local"
            return resolve(lad, profile, packageFamilyName)
        }

        /** 이름_게시자해시(13자, base32 꼴). 경로에 끼우므로 모양을 좁게 본다. */
        private val PFN = Regex("""^[A-Za-z0-9.\-]{1,64}_[a-z0-9]{13}$""")
    }
}

object PackageIdentity {
    /** (패키지 패밀리 이름 또는 null, Win32 결과 코드). 패키지 밖이면 (null, 15700). Windows 8 미만·실패면 (null, 코드). */
    fun currentFamilyName(): Pair<String?, Int> {
        val len = IntByReference(0)
        val first = Kernel32X.INSTANCE.GetCurrentPackageFamilyName(len, null)
        if (first == Win32.APPMODEL_ERROR_NO_PACKAGE) return null to first
        if (first != Win32.ERROR_INSUFFICIENT_BUFFER || len.value <= 0) return null to first
        val buf = CharArray(len.value)
        val second = Kernel32X.INSTANCE.GetCurrentPackageFamilyName(len, buf)
        if (second != 0) return null to second
        return String(buf, 0, maxOf(0, len.value - 1)).trimEnd('\u0000') to 0
    }
}
