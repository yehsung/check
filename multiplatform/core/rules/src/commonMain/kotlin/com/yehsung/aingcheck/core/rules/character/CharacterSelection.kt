// 원본: Sources/CheckCore/CharacterKit/CharacterSelection.swift @ 1b8260d (UserDefaults → foundation KeyValueStore)
package com.yehsung.aingcheck.core.rules.character

import com.yehsung.aingcheck.core.foundation.platform.KeyValueStore

/**
 * 지금 착용한 캐릭터의 영속 선택. **모르는 id 는 언제나 아잉으로 접는다** — 저장값은 지우지 않는다(그 캐릭터가 돌아오는 빌드에서
 * 선택이 되살아나게, 읽기 시점에만 접는다).
 */
class CharacterSelection(private val defaults: KeyValueStore, private val catalog: CharacterCatalog) {
    /** 현재 선택. 저장값이 없거나 카탈로그에 없으면 아잉. */
    val selectedID: String
        get() {
            val stored = defaults.getString(defaultsKey)
            return if (stored != null && catalog.manifest(stored) != null) stored else CharacterCatalog.builtInAingID
        }

    /** 현재 선택의 매니페스트(카탈로그가 아잉을 반드시 가지므로 null 이 아니다). */
    val selectedManifest: CharacterManifest
        get() = catalog.manifest(selectedID) ?: CharacterCatalog.builtInAing

    /** 선택을 바꾼다. 카탈로그에 없는 id 면 **저장하지 않고** false(옛 저장값을 모르는 값으로 덮지 않게). */
    fun select(id: String): Boolean {
        if (catalog.manifest(id) == null) return false
        defaults.putString(defaultsKey, id)
        return true
    }

    companion object {
        /** 저장 키 — 마이그레이션·진단이 이 이름을 그대로 쓴다. */
        const val defaultsKey = "check.character.selected"
    }
}
