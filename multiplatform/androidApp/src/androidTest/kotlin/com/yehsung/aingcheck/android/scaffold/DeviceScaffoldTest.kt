package com.yehsung.aingcheck.android.scaffold

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.yehsung.aingcheck.android.generated.BuildIdentity
import com.yehsung.aingcheck.android.generated.ProdConfig
import com.yehsung.aingcheck.android.http.HttpEngineFactory
import com.yehsung.aingcheck.core.foundation.identity.ClientIdentity
import com.yehsung.aingcheck.core.foundation.identity.ClientPlatform
import okhttp3.OkHttpClient
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.IOException
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.Socket
import kotlin.concurrent.thread

/**
 * 기기 계측 뼈대(W0 통합, gate-full.sh → emu.sh instrumented). 에뮬레이터(api36, 봉인 기본) 위 ART 에서 돈다.
 * 판정마다 기준선을 짝으로 둔다 — 같은 코드가 다른 입력에서 다른 결과를 내야 단언이 산다(기억 comparison-baseline-must-differ).
 */
@RunWith(AndroidJUnit4::class)
class DeviceScaffoldTest {
    private val args get() = InstrumentationRegistry.getArguments()
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext

    private fun connect(address: InetSocketAddress): String = try {
        Socket().use { it.connect(address, 3_000) }
        "connected"
    } catch (e: IOException) {
        "blocked(${e.javaClass.simpleName}: ${e.message})"
    }

    /**
     * 봉인(A-X7): 손님 안에서 바깥 TCP 는 실패하고, 같은 코드로 기기 안 루프백은 붙는다(기준선).
     * INTERNET 권한이 없으면 소켓 자체가 막혀 '봉인'처럼 보이므로 권한부터 단언한다.
     * emu.sh instrumented 만 aingcheckSealed 인자를 준다 — 인자가 없거나 1 이 아니면 게이트 실행이 아니다(빨강).
     */
    @Test
    fun outboundIsSealedWhileLoopbackWorks() {
        assertEquals("emu.sh instrumented(봉인) 로만 도는 시험이다 — aingcheckSealed 인자", "1", args.getString("aingcheckSealed"))
        assertEquals(
            "앱에 INTERNET 권한이 없다 — 소켓이 권한으로 막혀 카나리아가 아무것도 재지 않는다",
            PackageManager.PERMISSION_GRANTED,
            context.checkSelfPermission(Manifest.permission.INTERNET),
        )
        val loopback = ServerSocket(0, 1, InetAddress.getByName("127.0.0.1")).use { server ->
            val acceptor = thread { runCatching { server.accept().close() } }
            val r = connect(InetSocketAddress(InetAddress.getByName("127.0.0.1"), server.localPort))
            acceptor.join(3_000)
            r
        }
        val outbound = connect(InetSocketAddress(InetAddress.getByAddress(byteArrayOf(1, 1, 1, 1)), 443))
        println("AINGCHECK-DEVICE-CANARY sdk=${Build.VERSION.SDK_INT} loopback=$loopback outbound=$outbound")
        assertEquals("기준선: 기기 안 루프백 연결이 안 된다 — 소켓 경로가 죽어 있으면 봉인 판정이 비어 있다", "connected", loopback)
        assertTrue("봉인이 새고 있다 — 손님 안에서 1.1.1.1:443 이 열렸다($outbound)", outbound.startsWith("blocked"))
    }

    /** §8-5 · K4: 계측이 도는 debug 변형은 언제나 `.invalid` 이고, 신원은 version.properties 에서 온 android 축이다. */
    @Test
    fun debugBuildCarriesNoProductionConfigOnDevice() {
        assertEquals("https://aingcheck.invalid", ProdConfig.SUPABASE_URL)
        assertEquals("", ProdConfig.SUPABASE_ANON_KEY)
        val identity = ClientIdentity.fromGenerated(BuildIdentity.PLATFORM, BuildIdentity.BUILD, BuildIdentity.VERSION)
        assertEquals(ClientPlatform.ANDROID, identity.platform)
        val pkg = context.packageManager.getPackageInfo(context.packageName, 0)
        assertEquals("BuildIdentity.BUILD 가 설치된 versionCode 와 다르다", pkg.longVersionCode, identity.build)
        assertEquals(pkg.versionName, identity.version)
    }

    /**
     * G §8-12 · C-X6 의 ART 몫: 팩토리 원시 OkHttp 클라이언트가 기기 런타임에서도 재전송 끔을 지닌다.
     * 끊긴 연결 재현(POST 도착 수)은 호스트 시험(androidApp HttpEngineFactoryTest, Robolectric)과 desktopApp 시험이 잰다 —
     * 기기 앱은 targetSdk 36 기본 정책으로 cleartext 를 막아 localhost http 모의 서버를 못 부른다(W0 통합 실측:
     * "CLEARTEXT communication to localhost not permitted by network security policy"). debug 전용 localhost 예외를 둘지는
     * 네트워크 보안 설정을 정하는 W1-g 가 정한다. Ktor 쪽은 속성으로 못 잰다(기본 config 가 바탕의 retry(false) 를 덮는다 — 실측).
     */
    @Test
    fun httpEngineFactoryDisablesRetryOnArt() {
        val client = HttpEngineFactory.okHttpClient()
        val baseline = OkHttpClient.Builder().build()
        println("AINGCHECK-HTTP-FACTORY art okhttp baseline retry=${baseline.retryOnConnectionFailure} factory retry=${client.retryOnConnectionFailure}")
        assertTrue("기준선: OkHttp 기본값이 재전송 켬이 아니다 — 판정이 비었다", baseline.retryOnConnectionFailure)
        assertFalse("팩토리 OkHttp 가 기기에서 재전송을 켠 채다", client.retryOnConnectionFailure)
    }
}
