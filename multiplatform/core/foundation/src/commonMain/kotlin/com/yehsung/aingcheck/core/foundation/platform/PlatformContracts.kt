// 원본: Sources/CheckCore/TokenVault.swift @ a63fea2 (금고 계약) · C§3.4 actual 목록
// K3 공용 플랫폼 인터페이스 — W0-a 는 **서명만** 정한다. 구현(actual)은 Android(W1-g)·Windows(W1-f)가,
// 시험용 구현은 testkit 이 둔다. 서명을 바꾸면 모든 갈래가 깨지므로 조정자 경유로만 고친다.
package com.yehsung.aingcheck.core.foundation.platform

/**
 * access/refresh 토큰의 보관 계약(TokenVault.swift 그대로).
 *
 * 에러 규약: **삼킨다**(던지지 않는다). 대신 write 가 실패한 키는 read 가 반드시 null 을 돌려준다.
 * 실패를 삼키고 **낡은 토큰**을 돌려주면 회전 전 refresh token 으로 grant 를 치게 되고, GoTrue
 * reuse-detection 이 근무 중 강제 로그아웃을 만든다. '없다'는 재로그인으로 끝나지만 '낡았다'는 사고다.
 * 계약 시험: testkit `TokenVaultContract`(InMemory·Keystore·DPAPI 셋 모두에서 초록이어야 한다).
 */
interface TokenVault {
    fun read(key: String): String?
    fun write(value: String, key: String)
    /** 멱등이다(없는 키를 지워도 조용하다). */
    fun delete(key: String)
}

/**
 * 비밀 아닌 설정(defaults 대응). Android 는 DataStore, Windows 는 %LOCALAPPDATA% 파일.
 * `java.util.prefs` 는 금지다(맥 plist·Windows HKCU 에 쓴다 — 구조 시험).
 */
interface KeyValueStore {
    fun getString(key: String): String?
    fun putString(key: String, value: String)
    fun getLong(key: String): Long?
    fun putLong(key: String, value: Long)
    fun getBoolean(key: String): Boolean?
    fun putBoolean(key: String, value: Boolean)
    fun remove(key: String)
}

/**
 * 설치(기기) 식별자. **저장 확인 뒤에만** 돌려준다(기억 device-identity-must-not-be-invented):
 * 써 놓고 다시 읽어 같을 때만 값이 있고, 아니면 null — 호출자는 null 이면 토큰 업로드 같은 기기 단위 쓰기를 하지 않는다.
 * Windows 는 UUIDv5(MachineGuid+SID) 재계산(K6), Android 는 백업에서 빠진 앱 전용 저장.
 */
interface InstallationIdentity {
    /** 소문자 UUID 문자열, 확인 실패면 null. */
    fun installationId(): String?
}

enum class LogLevel { DEBUG, INFO, WARN, ERROR }

/** Logcat(Android) · 파일(Windows) · 수집기(시험). 토큰·비밀번호를 메시지에 싣지 않는다. */
interface Logger {
    fun log(level: LogLevel, tag: String, message: String, error: Throwable? = null)
}

/** NFC 정규화(Swift precomposedStringWithCanonicalMapping). 비교 전에 반드시 거친다(C§2.5). */
interface TextNormalizer {
    fun nfc(text: String): String
}

/** 확장 그래핌 수(Swift String.count). 골든으로 Swift 와 대조한다(platformSensitive). */
interface GraphemeCounter {
    fun count(text: String): Int
}

/** 이름 정렬(Swift localizedStandardCompare 대응: 한국어 + 숫자 덩어리). 골든으로 대조한다. */
interface Collation {
    fun compare(a: String, b: String): Int
}

/** 시험 실행 감지: 참이면 실 전송자(소켓·실시간)를 만들지 않는다(RealtimeTransport.swift:206-219, C§4 #17). */
interface RunningTests {
    val isRunningTests: Boolean
}

/**
 * 단일 실행 가드. Windows 는 이름 있는 뮤텍스 `Local\AingCheck.Instance`(D§2-5). **세션 시작 전 필수** —
 * 두 번 실행되면 갱신 주체가 둘이 된다(C§9-10). Android 는 프로세스가 하나라 늘 참을 돌려주는 구현을 쓴다.
 */
interface SingleInstanceGuard {
    /** 처음 잡으면 true. 이미 다른 실행이 쥐고 있으면 false. */
    fun tryAcquire(): Boolean
    fun release()
}

/**
 * 단조 시계(경과 측정용, 벽시계 공백 감지의 짝). 벽시계는 stdlib `kotlin.time.Clock` 을 주입한다.
 * `Clock.System`·`System.currentTimeMillis` 는 앱 조립 지점 밖에서 금지(구조 시험).
 */
interface MonotonicClock {
    fun elapsedNanos(): Long
}
