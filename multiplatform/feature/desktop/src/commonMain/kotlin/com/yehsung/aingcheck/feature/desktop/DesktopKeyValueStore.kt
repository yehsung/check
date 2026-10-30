// 조정자 핀(W-windows-resume W-3·xplat-w2/pins.md) — 갈래는 읽기만
// 출처: pins.md C. 큐·잠자기 마커·소유 id·창 자리 기억이 쓴다. 실영속(파일)은 다음 웨이브 W3-d.
package com.yehsung.aingcheck.feature.desktop

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.update

/** 비밀 아닌 작은 값 저장소. 비밀(토큰)은 TokenVault 로만. null 을 넣으면 지운다. */
interface DesktopKeyValueStore {
    fun getString(key: String): String?
    fun putString(key: String, value: String?)
    /** prefix 로 시작하는 키(정렬). */
    fun keys(prefix: String = ""): List<String>

    fun remove(key: String) = putString(key, null)
    fun getLong(key: String): Long? = getString(key)?.toLongOrNull()
    fun putLong(key: String, value: Long?) = putString(key, value?.toString())
    fun getBoolean(key: String): Boolean? = when (getString(key)) {
        "true" -> true
        "false" -> false
        else -> null
    }
    fun putBoolean(key: String, value: Boolean?) = putString(key, value?.toString())
}

/** 최소 구현(시험·W3-d 전 조립). 스레드 안전(원자 갱신). */
class InMemoryDesktopKeyValueStore(initial: Map<String, String> = emptyMap()) : DesktopKeyValueStore {
    private val values = MutableStateFlow(initial)

    override fun getString(key: String): String? = values.value[key]

    override fun putString(key: String, value: String?) {
        values.update { if (value == null) it - key else it + (key to value) }
    }

    override fun keys(prefix: String): List<String> = values.value.keys.filter { it.startsWith(prefix) }.sorted()

    fun snapshot(): Map<String, String> = values.value
}
