package com.yehsung.aingcheck.android.scaffold

import com.yehsung.aingcheck.android.generated.BuildIdentity
import com.yehsung.aingcheck.android.generated.ProdConfig
import com.yehsung.aingcheck.core.foundation.identity.ClientIdentity
import com.yehsung.aingcheck.core.foundation.identity.ClientPlatform
import java.io.File
import java.util.Properties
import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * §8-5 Android: 운영 구성은 release 조립 지점에서만 들어간다. debug 변형(이 시험이 도는 변형)은 언제나 `.invalid`.
 * K4: versionCode·versionName 은 version.properties 에서 온다.
 */
class GeneratedConfigTest {
    @Test
    fun debugVariantNeverCarriesProductionConfig() {
        assertEquals("https://aingcheck.invalid", ProdConfig.SUPABASE_URL)
        assertEquals("", ProdConfig.SUPABASE_ANON_KEY)
    }

    @Test
    fun buildIdentityMatchesVersionProperties() {
        val props = Properties().apply {
            File(System.getProperty("aingcheck.mpRoot"), "version.properties").inputStream().use { load(it) }
        }
        val identity = ClientIdentity.fromGenerated(BuildIdentity.PLATFORM, BuildIdentity.BUILD, BuildIdentity.VERSION)
        assertEquals(ClientPlatform.ANDROID, identity.platform)
        assertEquals(props.getProperty("androidVersionCode").toLong(), identity.build)
        assertEquals(props.getProperty("androidVersionName"), identity.version)
    }
}
