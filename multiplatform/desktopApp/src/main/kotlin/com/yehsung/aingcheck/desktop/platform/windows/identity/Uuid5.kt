// 원본: 없음(새 코드) — RFC 9562 §5.5(UUIDv5 = SHA-1 이름 기반) · 설계 D§2-5 · G §5-1 #6 · K6
package com.yehsung.aingcheck.desktop.platform.windows.identity

import java.nio.ByteBuffer
import java.security.MessageDigest
import java.util.UUID

object Uuid5 {
    /** RFC 9562 부록의 이름공간 URL(6ba7b811-…). */
    val NAMESPACE_URL: UUID = UUID.fromString("6ba7b811-9dad-11d1-80b4-00c04fd430c8")

    /** RFC 9562 부록의 이름공간 DNS(6ba7b810-…) — 시험 벡터(uuid5(DNS,"python.org"))용. */
    val NAMESPACE_DNS: UUID = UUID.fromString("6ba7b810-9dad-11d1-80b4-00c04fd430c8")

    fun nameBased(namespace: UUID, name: String): UUID {
        val ns = ByteBuffer.allocate(16).putLong(namespace.mostSignificantBits).putLong(namespace.leastSignificantBits).array()
        val sha1 = MessageDigest.getInstance("SHA-1")
        sha1.update(ns)
        sha1.update(name.toByteArray(Charsets.UTF_8))
        val h = sha1.digest()
        h[6] = ((h[6].toInt() and 0x0F) or 0x50).toByte() // 판 5
        h[8] = ((h[8].toInt() and 0x3F) or 0x80).toByte() // 변형 RFC
        val bb = ByteBuffer.wrap(h, 0, 16)
        return UUID(bb.long, bb.long)
    }
}

/**
 * Windows 설치 식별자(K6, G §5-1 #6): `UUIDv5(ns, "aing-check|" + MachineGuid + "|" + 사용자 SID)` 소문자.
 * 서버 `device_id` 는 `'win:'` + 이 값(B§0) — 맥 device_id 는 대문자 UUID 라 접두와 겹치지 않는다.
 */
object WindowsDeviceIdentity {
    /**
     * 이름공간 = UUIDv5(NAMESPACE_URL, [NAMESPACE_NAME]) = `aafb227d-cd3f-5244-9eb4-8496576dbc12`(Python uuid 로 대조).
     * **영구 식별자다** — 첫 출시 뒤 바꾸면 모든 Windows 기기가 새 기기로 보여 순위표가 두 배가 된다(기억 device-identity-must-not-be-invented).
     */
    const val NAMESPACE_NAME = "https://github.com/yehsung/check#windows-installation-id/v1"
    val NAMESPACE: UUID = UUID.fromString("aafb227d-cd3f-5244-9eb4-8496576dbc12")

    const val DEVICE_ID_PREFIX = "win:"

    private val SID = Regex("""^S-1-\d+(-\d+)+$""")

    /** MachineGuid·SID 를 다듬어 이름을 만든다. 모양이 틀리면 null(→ 무작위 폴백 경로). */
    fun name(machineGuid: String, sid: String): String? {
        val guid = machineGuid.trim().lowercase()
        val s = sid.trim().uppercase()
        val parsed = runCatching { UUID.fromString(guid) }.getOrNull() ?: return null
        if (parsed.toString() != guid) return null // "1-2-3-4-5" 같은 느슨한 꼴을 받지 않는다
        if (!SID.matches(s)) return null
        return "aing-check|$guid|$s"
    }

    fun installationId(machineGuid: String, sid: String): String? =
        name(machineGuid, sid)?.let { Uuid5.nameBased(NAMESPACE, it).toString().lowercase() }

    fun deviceId(installationId: String?): String? = installationId?.let { DEVICE_ID_PREFIX + it.lowercase() }
}
