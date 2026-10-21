// K3 플랫폼 인터페이스의 Android actual(C§3.4) 중 셸이 쥐는 것: Logger · KeyValueStore · RunningTests · SingleInstanceGuard ·
// MonotonicClock. (TokenVault → vault/, InstallationIdentity → identity/. 글자 규칙 셋 TextNormalizer·GraphemeCounter·Collation 은
// 골든을 쥔 W1-c 가 정한다 — platformSensitive 대조가 거기 있다.)
package com.yehsung.aingcheck.android.app

import android.content.Context
import android.content.SharedPreferences
import android.os.Build
import android.os.SystemClock
import android.util.Log
import androidx.core.content.edit
import com.yehsung.aingcheck.core.foundation.platform.KeyValueStore
import com.yehsung.aingcheck.core.foundation.platform.LogLevel
import com.yehsung.aingcheck.core.foundation.platform.Logger
import com.yehsung.aingcheck.core.foundation.platform.MonotonicClock
import com.yehsung.aingcheck.core.foundation.platform.RunningTests
import com.yehsung.aingcheck.core.foundation.platform.SingleInstanceGuard

/** Logcat. 토큰·비밀번호를 메시지에 싣지 않는다(호출자 규약). */
class LogcatLogger : Logger {
    override fun log(level: LogLevel, tag: String, message: String, error: Throwable?) {
        when (level) {
            LogLevel.DEBUG -> Log.d(tag, message, error)
            LogLevel.INFO -> Log.i(tag, message, error)
            LogLevel.WARN -> Log.w(tag, message, error)
            LogLevel.ERROR -> Log.e(tag, message, error)
        }
    }
}

/**
 * 비밀 아닌 설정(defaults 대응). SharedPreferences — 인터페이스가 동기라 DataStore 대신 이것을 쓴다(C§3.4 "DataStore 또는 SP").
 * 쓰기는 commit(동기) — 호출자가 "써 놓고 다시 읽어 확인"하는 자리(RouteProof 등)가 있어 apply 의 늦은 실패를 피한다.
 */
class SharedPreferencesKeyValueStore(context: Context, name: String = DEFAULT_NAME) : KeyValueStore {
    private val prefs: SharedPreferences = context.getSharedPreferences(name, Context.MODE_PRIVATE)

    override fun getString(key: String): String? = runCatching { prefs.getString(key, null) }.getOrNull()
    override fun putString(key: String, value: String) = prefs.edit(commit = true) { putString(key, value) }
    override fun getLong(key: String): Long? = if (prefs.contains(key)) runCatching { prefs.getLong(key, 0L) }.getOrNull() else null
    override fun putLong(key: String, value: Long) = prefs.edit(commit = true) { putLong(key, value) }
    override fun getBoolean(key: String): Boolean? = if (prefs.contains(key)) runCatching { prefs.getBoolean(key, false) }.getOrNull() else null
    override fun putBoolean(key: String, value: Boolean) = prefs.edit(commit = true) { putBoolean(key, value) }
    override fun remove(key: String) = prefs.edit(commit = true) { remove(key) }

    companion object {
        const val DEFAULT_NAME = "aingcheck"
    }
}

/**
 * 시험 실행 감지(C§3.4 "계측 인자"): Robolectric(지문 "robolectric") 또는 기기 계측(AndroidJUnitRunner 가 등록한 Instrumentation).
 * 출시 APK 에는 androidx.test 가 없어(레지스트리 클래스 없음) 언제나 거짓이다. 이 값이 잘못 참이 되면 release 가
 * SKIP_RUNNING_TESTS 로 빠져 운영에서 FCM 이 영영 초기화되지 않는다 — 그래서 판정을 순수 함수로 떼어 짝으로 잰다(AndroidRunningTestsTest).
 */
object AndroidRunningTests : RunningTests {
    const val ROBOLECTRIC_FINGERPRINT = "robolectric"
    const val REGISTRY_CLASS = "androidx.test.platform.app.InstrumentationRegistry"

    override val isRunningTests: Boolean by lazy { detect(Build.FINGERPRINT) { registeredInstrumentation(REGISTRY_CLASS) } }

    /**
     * 순수 판정. [instrumentation] 은 등록된 계측을 돌려준다 — 클래스가 없거나(출시 APK) 등록 전이라 던지거나 null 이면 거짓.
     */
    fun detect(fingerprint: String?, instrumentation: () -> Any?): Boolean {
        if (fingerprint == ROBOLECTRIC_FINGERPRINT) return true
        return runCatching { instrumentation() != null }.getOrDefault(false)
    }

    /** [registryClass] 의 정적 getInstrumentation() 을 부른다. 클래스가 없으면 ClassNotFoundException, 등록 전이면 그 예외를 던진다. */
    fun registeredInstrumentation(registryClass: String): Any? =
        Class.forName(registryClass).getMethod("getInstrumentation").invoke(null)
}

/** Android 는 프로세스가 하나라 늘 잡힌다(C§3.4 — 단일 실행 가드는 Windows 몫). */
object ProcessSingleInstanceGuard : SingleInstanceGuard {
    override fun tryAcquire(): Boolean = true
    override fun release() = Unit
}

/** 부팅 뒤 경과(잠자는 동안 포함). 벽시계 공백 감지의 짝. */
object ElapsedRealtimeClock : MonotonicClock {
    override fun elapsedNanos(): Long = SystemClock.elapsedRealtimeNanos()
}
