// 원본: 없음(새 코드) — 설계 D§2-4(네이티브 DLL 을 %TEMP% 에 풀지 않는다: 패키지 안 DLL + jna.boot.library.path + jna.nounpack=true)
//       · W0-e 관측(MSI·app-image 둘 다 jnidispatch.dll 이 %TEMP%\jna--* 에 풀렸다 — 서명 없는 임시 DLL 은 Smart App Control·
//         백신에 막힐 수 있다, D-E23 미확인)
//
// JNA 클래스가 처음 로드되기 **전에**(Main 첫 줄) 시스템 속성을 정한다. 패키지가 jnidispatch.dll 을 앱 자원 폴더에 실었을 때만
// nounpack 을 켠다 — DLL 이 없는데 켜면 JNA 가 아예 못 뜬다(개발 실행·시험). 자원 폴더는 Compose 패키징이
// `compose.application.resources.dir` 로 알려 준다(appResourcesRootDir 의 <os>-<arch> 몫). DLL 을 싣는 빌드 설정은 조정자 패치로 냈다.
package com.yehsung.aingcheck.desktop.platform.windows.jna

import java.io.File

object JnaBootstrap {
    const val DISPATCH_DLL = "jnidispatch.dll"
    const val RESOURCES_DIR_PROPERTY = "compose.application.resources.dir"

    /** 순수 판단: 정할 시스템 속성(비었으면 아무것도 안 바꾼다). */
    fun decide(resourcesDir: String?, isFile: (String) -> Boolean): Map<String, String> {
        if (resourcesDir.isNullOrBlank()) return emptyMap()
        val dll = File(resourcesDir, DISPATCH_DLL).path
        if (!isFile(dll)) return emptyMap()
        return mapOf(
            "jna.boot.library.path" to resourcesDir,
            "jna.nounpack" to "true",
            // 시스템 경로(System32 등)의 다른 판 jnidispatch 를 집지 않는다.
            "jna.nosys" to "true",
        )
    }

    /** Main 첫 줄에서. 이미 사용자가 정한 속성은 덮지 않는다. 정한 속성을 돌려준다(selfcheck 진단). */
    fun apply(): Map<String, String> {
        val decided = decide(System.getProperty(RESOURCES_DIR_PROPERTY)) { File(it).isFile }
        val applied = LinkedHashMap<String, String>()
        for ((k, v) in decided) {
            if (System.getProperty(k) == null) {
                System.setProperty(k, v)
                applied[k] = v
            }
        }
        return applied
    }
}
