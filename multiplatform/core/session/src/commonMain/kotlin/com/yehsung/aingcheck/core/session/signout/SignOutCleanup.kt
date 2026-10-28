// 원본: Sources/CheckMobileKit/Session/MobileSignOutCleanup.swift @ 1b8260d
package com.yehsung.aingcheck.core.session.signout

import com.yehsung.aingcheck.core.foundation.platform.TokenVault
import com.yehsung.aingcheck.core.session.SessionVaultKeys
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json

/**
 * 로그아웃 때 서버에 다 알리지 못한 정리 한 건(Swift `MobileSignOutCleanup`).
 *
 * 왜 남기는가: 서버 `client_devices` 행은 `unregister_device` 로만 지워진다. 만료된 access token(401)이나 오프라인으로 로그아웃하면 행이
 * 푸시 토큰을 든 채 남아, **로그아웃한 폰에 앞 계정의 메시지(보낸 사람·본문)가 계속 뜬다**. 그래서 못 한 정리를 옛 세션 토큰과 함께
 * 금고 장부에 적어 두고, 앱이 네트워크를 가질 기회(실행 · 포그라운드 · 로그인)마다 갚는다.
 */
@Serializable
data class SignOutCleanup(
    @SerialName("id") val id: String,
    @SerialName("userID") val userID: String,
    @SerialName("accessToken") val accessToken: String,
    @SerialName("refreshToken") val refreshToken: String? = null,
    /** unregister_device 를 마쳤다(또는 할 필요가 없다) — 남은 일은 logout?scope=local 뿐. */
    @SerialName("deviceUnregistered") val deviceUnregistered: Boolean = false,
    /** 1970 기준 초(Swift `.secondsSince1970`). */
    @SerialName("createdAt") val createdAt: Double,
)

/** 정리 장부(금고 한 칸의 JSON 배열). 토큰이 들어 있어 설정 저장소에 두지 않는다. 위젯은 이 칸을 읽지 않는다. */
object SignOutCleanupLedger {
    /** 장부 상한. 넘으면 오래된 것부터 버린다(오프라인 로그아웃이 쌓여도 금고 한 칸이 끝없이 크지 않게). */
    const val maxEntries: Int = 8

    /** 이보다 오래된 정리는 버린다 — 그 사이 서버가 10대 상한·토큰 이동으로 행을 치웠을 공산이 크다. */
    const val maxAgeSeconds: Double = 30.0 * 86_400.0

    private val json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
        explicitNulls = false
    }
    private val serializer = ListSerializer(SignOutCleanup.serializer())

    /** 못 읽으면(없음 · 깨짐) 빈 장부 — Swift `try? … ?? []` 와 같다. */
    fun load(vault: TokenVault): List<SignOutCleanup> {
        val text = vault.read(SessionVaultKeys.signOutCleanup) ?: return emptyList()
        return try {
            json.decodeFromString(serializer, text)
        } catch (e: Exception) {
            emptyList()
        }
    }

    fun save(entries: List<SignOutCleanup>, vault: TokenVault) {
        val kept = entries.takeLast(maxEntries)
        if (kept.isEmpty()) {
            vault.delete(SessionVaultKeys.signOutCleanup)
            return
        }
        vault.write(json.encodeToString(serializer, kept), SessionVaultKeys.signOutCleanup)
    }

    /** 장부를 읽어 고치고 다시 쓴다(늘 새로 읽는다 — 정리 도중 로그아웃이 새 줄을 더했을 수 있다). */
    fun update(vault: TokenVault, body: (MutableList<SignOutCleanup>) -> Unit) {
        val entries = load(vault).toMutableList()
        body(entries)
        save(entries, vault)
    }
}

/** 정리 한 건을 한 번 시도한 결과. */
sealed interface SignOutCleanupOutcome {
    /** 끝났다(서버에 알렸거나 · 더 알릴 방법이 없다) — 장부에서 뺀다. */
    data object Settled : SignOutCleanupOutcome

    /** 일시 실패(네트워크 · 5xx · 429) — 고친 상태(회전한 토큰 · 끝난 단계)로 남기고, 이번 차례의 나머지도 멈춘다. */
    data class RetryLater(val entry: SignOutCleanup) : SignOutCleanupOutcome
}
