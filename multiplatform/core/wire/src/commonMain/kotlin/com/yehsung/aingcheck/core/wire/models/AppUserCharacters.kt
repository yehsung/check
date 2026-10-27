// 원본: Sources/CheckCore/AppUserCharacters.swift:77-232(AppUserCharacterDirectory · AppUserAvatar — 순수 모델) @ 1b8260d · C§3.2 C-1(AppUserCharacters → core.wire)
package com.yehsung.aingcheck.core.wire.models

import com.yehsung.aingcheck.core.wire.SwiftURL
import com.yehsung.aingcheck.core.wire.character.BuiltInCharacterIds

/**
 * 사용자 id → 아바타에 그릴 캐릭터 id(값 타입 — 네트워크를 모른다). 표는 서버 응답으로 **통째로** 갈아 끼운다([replace]).
 *
 * INV-AppUserCharacters-2f712094 이식: 접기 규칙(이 파일의 계약)
 *  · 서버 null(안 골랐다) = **아잉**. 표에 있는 사람은 전원 사진 아니면 캐릭터가 뜬다.
 *  · 이 빌드가 **모르는** 캐릭터 id 는 아잉으로 접지 않고 **null(이니셜)** — 남의 사실을 그리는 자리라 구버전이 새 캐릭터를 아잉으로
 *    단정하면 틀린 사실을 그린다(열거값 확장엔 능력 협상).
 *  · 표에 없는 사람(첫 조회 전 · 실패 · 숨김 격리 밖)도 null.
 *  · 서버에 함수가 없으면(404 PGRST202) 조회는 조용히 빈 표(서비스 `fetchAppUserCharacters`).
 *  · "아는 캐릭터"의 정본은 그 플랫폼이 **초상을 그릴 수 있는** id 다 — 목록은 호출부가 준다(Android = 초상 번들). 아잉은 늘 안다.
 *
 * 맥 전용 `init(catalog:)`(번들 카탈로그 = W1-c `CharacterCatalog`)는 옮기지 않는다 — wire 는 rules 에 기댈 수 없다. 호출부가
 * `catalog.allIDs` 를 [knownIDs] 로 넘기면 같은 값이다.
 */
class AppUserCharacterDirectory(knownIDs: Iterable<String>, rows: List<AppUserCharacterRow> = emptyList()) {
    /** 이 빌드가 초상을 그릴 수 있는 캐릭터 id(아잉은 늘 들어 있다). */
    val knownIDs: Set<String> = buildSet {
        for (id in knownIDs) normalizedCharacterID(id)?.let(::add)
        add(BuiltInCharacterIds.builtInAingID)
    }

    /** 소문자 user id → 접은 착용값(null·공백 → aing). 모르는 id 도 원문 그대로 보관한다(모름 판정은 읽을 때). */
    private var equipped: Map<String, String> = emptyMap()

    init {
        replace(rows)
    }

    /** 아는 사람 수(모르는 캐릭터를 입은 사람 포함). */
    val count: Int get() = equipped.size
    val isEmpty: Boolean get() = equipped.isEmpty()

    /** 아바타에 그릴 캐릭터 id. null = 모른다 → 이니셜. */
    fun characterID(userID: String?): String? {
        val id = equippedID(userID) ?: return null
        return if (id in knownIDs) id else null
    }

    /** 서버 착용값을 접은 것(null → 아잉, 모르는 id 는 원문). null = 이 사람을 표에서 모른다. */
    fun equippedID(userID: String?): String? {
        val key = normalizedUserID(userID) ?: return null
        return equipped[key]
    }

    /** 사진 → 캐릭터 → 이니셜. 사진이 있으면 실패했을 때 떨어질 캐릭터를 함께 준다. */
    fun avatar(userID: String?, photoURL: SwiftURL?): AppUserAvatar {
        val character = characterID(userID)
        if (photoURL != null) return AppUserAvatar.Photo(photoURL, character)
        if (character != null) return AppUserAvatar.Character(character)
        return AppUserAvatar.Initials
    }

    /**
     * 위 판정에 **표가 이 사람을 모를 때만** 행이 실은 착용값(`characterHint`)을 쓴다 — 맥·폰 한 규칙.
     * 힌트는 이 빌드가 초상을 그릴 수 있는 id 일 때만, null 은 아잉으로 접지 않고, 표가 아는 사람은 표가 이긴다.
     */
    fun avatar(userID: String?, photoURL: SwiftURL?, characterHint: String?): AppUserAvatar {
        val resolved = avatar(userID, photoURL)
        if (characterID(userID) != null) return resolved
        val hint = normalizedCharacterID(characterHint) ?: return resolved
        if (hint !in knownIDs) return resolved
        if (resolved is AppUserAvatar.Photo) return AppUserAvatar.Photo(resolved.url, hint)
        return AppUserAvatar.Character(hint)
    }

    /** 서버 표로 **통째로** 갈아 끼운다. user id 가 빈 행은 버리고, 같은 id 가 두 번 오면 뒤의 것이 이긴다. */
    fun replace(rows: List<AppUserCharacterRow>) {
        val next = LinkedHashMap<String, String>()
        for (characterRow in rows) {
            val key = normalizedUserID(characterRow.userId) ?: continue
            next[key] = foldedEquippedID(characterRow.character)
        }
        equipped = next
    }

    /**
     * 한 사람의 착용값을 바로 고친다(내가 착용을 바꿨을 때). `serverValue` 는 서버 어휘: null·빈 글자 = 아잉.
     *
     * INV-AppUserCharacters-4da9862a 이식: 경합 — 내가 캐릭터를 바꾼 직후 그 전에 떠난 조회가 늦게 돌아오면 [replace] 가 옛 값으로
     * 덮는다. 호출부(스토어)는 표를 갈아 끼운 뒤 **자기가 아는 내 착용값을 다시 얹는다**(정본은 방금 set_character 가 ok 를 준 값).
     */
    fun setEquipped(serverValue: String?, userID: String) {
        val key = normalizedUserID(userID) ?: return
        equipped = LinkedHashMap(equipped).also { it[key] = foldedEquippedID(serverValue) }
    }

    /** 표를 비운다(로그아웃 · 계정 전환). [knownIDs] 는 빌드의 사실이라 그대로다. */
    fun removeAll() {
        equipped = emptyMap()
    }

    override fun equals(other: Any?): Boolean =
        other is AppUserCharacterDirectory && other.knownIDs == knownIDs && other.equipped == equipped

    override fun hashCode(): Int = 31 * knownIDs.hashCode() + equipped.hashCode()

    companion object {
        /** 서버 착용값 → 표에 적을 값. null·빈 글자·공백 = 아잉. 나머지는 앞뒤 공백만 걷은 원문. */
        fun foldedEquippedID(serverValue: String?): String = normalizedCharacterID(serverValue) ?: BuiltInCharacterIds.builtInAingID

        /** 사용자 id 의 표 열쇠(uuid 는 대소문자를 가리지 않는다). 비었으면 null — 행 디코드와 같은 한 규칙. */
        fun normalizedUserID(raw: String?): String? = AppUserCharacterRow.normalizedUserID(raw)

        /** Swift `CharacterSyncDecision.normalized`(앞뒤 공백·줄바꿈을 걷고 비면 null) — wire 가 rules 에 기댈 수 없어 같은 한 줄을 둔다. */
        internal fun normalizedCharacterID(id: String?): String? {
            val trimmed = id?.let(::swiftTrim) ?: return null
            return trimmed.ifEmpty { null }
        }
    }
}

/** 아바타 자리에 무엇을 그릴지(판정 결과). 그리는 방법은 각 플랫폼 화면의 몫이다. */
sealed interface AppUserAvatar {
    /** 올린 사진. 로딩이 실패하면 [fallbackCharacterID] 의 캐릭터로, 그것도 null 이면 이니셜로. */
    data class Photo(val url: SwiftURL, val fallbackCharacterID: String?) : AppUserAvatar

    /** 착용 캐릭터의 neutral 초상. */
    data class Character(val id: String) : AppUserAvatar

    /** 캐릭터를 모른다 — 이니셜 원. */
    data object Initials : AppUserAvatar

    /** 사진 로딩이 실패했을 때 대신 그릴 것. 사진이 아니면 자기 자신. */
    val afterPhotoFailure: AppUserAvatar
        get() = if (this is Photo) fallbackCharacterID?.let { Character(it) } ?: Initials else this
}
