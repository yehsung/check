// 데스크톱 앱의 HTTP 엔진을 만드는 **단일 자리**(G §8-12, C-X6). 조립 파일(K11) — 고칠 때는 조정자 경유.
//
// - 끊긴 재사용 연결에서 OkHttp 기본값은 같은 POST 를 두 번 보낸다(C-X6 실측: 찌르기·메시지 이중 전송 위험).
//   그래서 여기서 만드는 모든 클라이언트는 retryOnConnectionFailure(false) 를 지닌다.
// - 이 파일 밖 main 에서 `OkHttpClient(`·`.newBuilder(`·엔진을 고르는 `HttpClient {}`·`HttpClient()`·`HttpClient(OkHttp…)` 를 쓰면
//   구조 시험 R3c 가 빨갛다. 다른 모듈(core/net)은 여기서 만든 클라이언트나 엔진을 주입받는다.
// - 재전송 끔은 desktopApp 시험 HttpEngineFactoryTest 가 실행해서 단언한다(속성 + 끊긴 연결 재현으로 POST 도착 수, OkHttp·Ktor).
// - androidApp 에 같은 꼴의 팩토리가 하나 더 있다(앱 모듈마다 한 파일, 두 앱 사이 공용 JVM 소스셋은 두지 않는다 — G §2-0).
package com.yehsung.aingcheck.desktop.http

import io.ktor.client.HttpClient
import io.ktor.client.HttpClientConfig
import io.ktor.client.engine.okhttp.OkHttp
import okhttp3.OkHttpClient

object HttpEngineFactory {
    /** 새 OkHttp 클라이언트(재전송 끔). 이 파일이 내는 모든 클라이언트가 이 한 줄을 지난다. */
    private fun newOkHttpClient(): OkHttpClient = OkHttpClient.Builder()
        .retryOnConnectionFailure(false)
        .build()

    /** 원시 OkHttp 가 필요한 자리(WebSocket 등)가 나눠 쓰는 클라이언트(연결 풀·디스패처 공유). */
    private val shared: OkHttpClient by lazy { newOkHttpClient() }

    fun okHttpClient(): OkHttpClient = shared

    /**
     * Ktor 클라이언트.
     * - `preconfigured` 의 retry(false) 만으로는 **안 된다**: Ktor OkHttp 엔진의 기본 `config` 가 바탕을 복제한 뒤
     *   retryOnConnectionFailure(true) 를 다시 건다(W0 통합 실측 — 바탕만 넘긴 판은 끊긴 연결에서 POST 2회).
     *   그래서 엔진 `config { }` 에서 한 번 더 끈다(기본 config 뒤에 이어 붙는다).
     * - 엔진 OkHttp 는 클라이언트마다 새로 짓는다 — Ktor 는 클라이언트를 닫을 때 엔진 OkHttp 의 디스패처를 내리므로
     *   (HttpEngineFactoryTest 실측) [shared] 를 넘기면 한 화면이 닫을 때 앱 전체 원시 OkHttp 가 죽는다.
     * - 엔진 설정을 여기 밖에서 바꿀 길을 두지 않으려고 [configure] 는 엔진 형식을 모르는 `HttpClientConfig<*>` 로 받는다.
     */
    fun ktorClient(configure: HttpClientConfig<*>.() -> Unit = {}): HttpClient = HttpClient(OkHttp) {
        engine {
            preconfigured = newOkHttpClient()
            config { retryOnConnectionFailure(false) }
        }
        configure()
    }
}
