package com.yehsung.aingcheck.desktop.scaffold

import com.yehsung.aingcheck.core.foundation.identity.ClientIdentity
import com.yehsung.aingcheck.core.foundation.identity.ClientPlatform
import com.yehsung.aingcheck.desktop.generated.BuildIdentity
import com.yehsung.aingcheck.desktop.generated.ProdConfig
import java.io.File
import java.util.Properties
import kotlin.test.Test
import kotlin.test.assertEquals

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
}
