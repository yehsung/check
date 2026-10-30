package com.yehsung.aingcheck.desktop.scaffold

import com.yehsung.aingcheck.core.foundation.identity.ClientIdentity
import com.yehsung.aingcheck.core.foundation.identity.ClientPlatform
import com.yehsung.aingcheck.desktop.fromBuild
import com.yehsung.aingcheck.desktop.generated.BuildIdentity
import com.yehsung.aingcheck.desktop.generated.DesktopFlags
import com.yehsung.aingcheck.desktop.generated.ProdConfig
import com.yehsung.aingcheck.feature.desktop.DesktopAppConfig
import java.io.File
import java.util.Properties
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * §8-5: 데스크톱 운영 구성은 Gradle 속성 → 생성 소스 한 파일(ProdConfig.kt). 시험·CI 빌드는 속성을 주지 않으므로 `.invalid` 다.
 * K4: BuildIdentity 는 version.properties 에서 온다(다른 곳에서 숫자를 짓지 않는다).
 */
class GeneratedConfigTest {
    @Test
    fun prodConfigDefaultsToInvalidHostWithoutReleaseProperties() {
        assertEquals("https://aingcheck.invalid", ProdConfig.SUPABASE_URL)
        assertEquals("", ProdConfig.SUPABASE_ANON_KEY)
    }

    @Test
    fun buildIdentityMatchesVersionProperties() {
        val props = Properties().apply {
            File(System.getProperty("aingcheck.mpRoot"), "version.properties").inputStream().use { load(it) }
        }
        val identity = ClientIdentity.fromGenerated(BuildIdentity.PLATFORM, BuildIdentity.BUILD, BuildIdentity.VERSION)
        assertEquals(ClientPlatform.WINDOWS, identity.platform)
        assertEquals(props.getProperty("windowsBuild").toLong(), identity.build)
        assertEquals(props.getProperty("windowsVersion"), identity.version)
    }

    @Test
    fun buildStampDefaultsWithoutReleaseProperties() {
        // package.md P1: 출시 속성(-Paingcheck.buildTime·gitSha)이 없으면 "dev"·"unknown". releaseAssembly=true 는 이 값을 거부한다.
        assertEquals("dev", BuildIdentity.BUILD_TIME)
        assertEquals("unknown", BuildIdentity.GIT_SHA)
    }

    @Test
    fun desktopFlagsDefaultTableAndSingleSource() {
        // W-3 #17: 생성 상수 기본값 표 — 전부 꺼짐, 관전만 켬. -Paingcheck.windows.<이름> 없이 빌드한 시험 JVM 이다.
        val generated = mapOf(
            "DUELS" to DesktopFlags.DUELS, "POKE" to DesktopFlags.POKE, "ULTRA" to DesktopFlags.ULTRA,
            "CHAT_TOAST" to DesktopFlags.CHAT_TOAST, "FORK_SAFE" to DesktopFlags.FORK_SAFE, "TOKEN_UPLOAD" to DesktopFlags.TOKEN_UPLOAD,
            "ADOPTED_POKE_CONSUME" to DesktopFlags.ADOPTED_POKE_CONSUME, "SPECTATOR" to DesktopFlags.SPECTATOR,
        )
        assertEquals(
            mapOf("DUELS" to false, "POKE" to false, "ULTRA" to false, "CHAT_TOAST" to false, "FORK_SAFE" to false,
                "TOKEN_UPLOAD" to false, "ADOPTED_POKE_CONSUME" to false, "SPECTATOR" to true),
            generated,
        )
        // fromBuild() 는 생성 상수를 그대로 옮긴다 = 핀의 기본값과 같다. AppConfig 는 그 값에서만 나온다.
        assertEquals(DesktopAppConfig(), DesktopAppConfig.fromBuild())
        assertEquals(false, DesktopAppConfig.fromBuild().toAppConfig().duelsEnabled)
    }

    /**
     * W-6 #5(W6-b2): 생성 상수는 `@JvmField val` — 쓰는 클래스가 값을 품지 않고 generated 필드를 읽는다. `const val` 로 돌아가면
     * 운영 값이 SelfCheck·AppGraph 같은 generated/ 밖 클래스에 인라인되어 다시 싸기(repack.sh)의 jar 교체 허용 목록(generated/)이 깨진다.
     */
    @Test
    fun generatedConstantsAreReadNotInlinedOutsideGeneratedPackage() {
        val root = File(ProdConfig::class.java.protectionDomain.codeSource.location.toURI())
        val genDir = "com/yehsung/aingcheck/desktop/generated/"
        val outside = root.walkTopDown()
            .filter { it.isFile && it.name.endsWith(".class") && !it.relativeTo(root).invariantSeparatorsPath.startsWith(genDir) }
            .associate { it.relativeTo(root).invariantSeparatorsPath to it.readBytes().toString(Charsets.ISO_8859_1) }
        assertTrue(outside.size > 50, "앱 main 클래스 디렉터리를 못 찾았다: $root (${outside.size})")
        val inlined = outside.filterValues { it.contains(ProdConfig.SUPABASE_URL) }.keys
        assertEquals(emptySet(), inlined, "운영 주소 값이 generated/ 밖 클래스에 인라인됐다(const val 회귀)")
        for (obj in listOf("ProdConfig", "BuildIdentity", "DesktopFlags")) {
            val readers = outside.filterValues { it.contains(genDir + obj) }.keys
            assertTrue(readers.isNotEmpty(), "$obj 를 필드로 읽는 클래스가 없다 — 값이 인라인됐다(const val 회귀)")
        }
    }
}
