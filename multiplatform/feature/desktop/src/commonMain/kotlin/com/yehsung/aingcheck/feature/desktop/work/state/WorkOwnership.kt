// W2-g5 근무 상태 코어 — 소유 장부·반납 규칙.
// 원본: Sources/check/WorkTimerStore.swift 3699-3850(SessionClaimStrength · 영속 키 · claim/release) ·
//       Sources/check/WorkTimerStoreSync.swift 2415(yieldsToClaim) @ a90d8623.
package com.yehsung.aingcheck.feature.desktop.work.state

import com.yehsung.aingcheck.feature.desktop.DesktopKeyValueStore
import com.yehsung.aingcheck.feature.desktop.work.WorkSessionIds

/**
 * 이 기기의 소유 주장이 어디서 왔는가 — **반납 규칙의 유일한 결정자**(Swift SessionClaimStrength).
 * - STRONG: 이 기기가 그 세션을 실제로 열었다(start · 이 기기가 보낸 되돌리기 재개 성공).
 * - WEAK: 백스톱이 '아무도 안 돌보는 것 같다'고 세운 추측.
 * 모르는 값은 언제나 WEAK(모를 때 '내가 열었다'고 우기면 진짜 소유자가 그 앞에서 물러난다).
 */
enum class SessionClaimStrength(val raw: String) {
    STRONG("strong"),
    WEAK("weak"),
    ;

    companion object {
        fun fromRaw(raw: String?): SessionClaimStrength = entries.firstOrNull { it.raw == raw } ?: WEAK
    }
}

/**
 * 소유 세션 id·강도의 영속(Swift ownedWorkSessionIDKey·ownedWorkSessionStrengthKey 3702·3706).
 * Windows 자체 영속이라 맥 plist 와 바이트 호환은 요구하지 않지만 키 이름은 같게 둔다(지시서 §6 미확인 4).
 */
class OwnedSessionLedger(private val kv: DesktopKeyValueStore) {
    /** 읽을 때도 정규화 — 옛 판이 대문자로 남긴 값의 재시작 판정 구제(C#22). */
    val ownedSessionId: String? get() = WorkSessionIds.canonical(kv.getString(OWNED_ID_KEY))

    /** 없거나 해석 불가면 WEAK. */
    val strength: SessionClaimStrength get() = SessionClaimStrength.fromRaw(kv.getString(OWNED_STRENGTH_KEY))

    /** 둘 중 하나라도 없으면 '모른다' = 거짓(Swift isOwnedByThisMac). 비교는 정규화 경유. */
    fun isOwned(sessionId: String?): Boolean {
        val canonical = WorkSessionIds.canonical(sessionId) ?: return false
        val owned = ownedSessionId ?: return false
        return canonical == owned
    }

    /**
     * Swift setOwnedWorkSessionID — 강도를 먼저 맞추고(같은 id 라도 강도는 바뀐다), id 는 **저장된 원문**과 비교해
     * 정규화본이 다르면 다시 쓴다(옛 대문자 값 이관). 값이 같으면 쓰지 않는다.
     */
    fun set(sessionId: String?, strength: SessionClaimStrength = SessionClaimStrength.WEAK) {
        val canonical = WorkSessionIds.canonical(sessionId)
        val storedStrength = if (sessionId == null) null else strength.raw
        if (kv.getString(OWNED_STRENGTH_KEY) != storedStrength) kv.putString(OWNED_STRENGTH_KEY, storedStrength)
        if (kv.getString(OWNED_ID_KEY) == canonical) return
        kv.putString(OWNED_ID_KEY, canonical)
    }

    companion object {
        const val OWNED_ID_KEY = "check.session.ownedWorkSessionID"
        const val OWNED_STRENGTH_KEY = "check.session.ownedWorkSessionStrength"
    }
}

/** ⑯ 반납 규칙(Swift yieldsToClaim 2415). 서버·맥이 'win:' 행을 "다른 맥"으로 읽으므로 **정확히** 같아야 한다. */
object WorkClaimRules {
    /**
     * 강·약이 갈리면 약한 쪽이 물러난다(상대가 강하면 true). 동급이면 `claim.deviceID < myDeviceID` 일 때 물러난다.
     * 비교는 UTF-16 코드 단위 사전식(Swift String `<` 와 ASCII 범위에서 같다) — 'win:'(0x77) 은 맥의 대문자 UUID(0-9·A-F)
     * 보다 뒤라 둘 다 약하면 Windows 가 물러나고 맥은 버틴다. 기기 id 가 없으면(빈 문자열) 동급에서 절대 물러나지 않는다
     * (Swift hasDeviceIdentity=false 의 deviceID "" 와 같다 — 그 기기는 기기 행을 쓰지 않으니 상대도 그를 못 본다).
     */
    fun yieldsToClaim(claimDeviceId: String, claimOpenedSession: Boolean, ownsStrongly: Boolean, myDeviceId: String?): Boolean {
        if (claimOpenedSession != ownsStrongly) return claimOpenedSession
        return claimDeviceId < (myDeviceId ?: "")
    }
}
