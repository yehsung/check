// 원본: Sources/CheckCore/CharacterKit/CharacterSync.swift @ 1b8260d
package com.yehsung.aingcheck.core.rules.character

import com.yehsung.aingcheck.core.rules.text.TextScalars

/**
 * 착용 캐릭터를 **서버 기준**으로 맞출 때 무엇을 할지(순수 판정). 실행·로그인·팝오버 때는 **읽기만** 하고, 쓰기는 사용자가 이 기기에서
 * 직접 고른 순간뿐이다. 옮겨 가기(한 번만): 이 버전으로 처음 판정할 때만 서버 null 을 "한 번도 안 밀었다"로 읽어 로컬의 비기본 선택을 민다.
 */
sealed interface CharacterSyncDecision {
    /** 로컬이 이미 목표와 같다. */
    data object keep : CharacterSyncDecision
    /** 로컬 선택을 이 id 로 바꾸고 방송한다. */
    data class adopt(val id: String) : CharacterSyncDecision
    /** 옮겨 가기: 서버에 이 id 를 **한 번** 민다(로컬은 그대로). */
    data class migrate(val id: String) : CharacterSyncDecision

    companion object {
        /** 옮겨 가기 판정을 끝냈는가의 도장(설정 저장소, Bool). */
        const val migrationDefaultsKey = "check.character.serverAuthorityMigrated"

        fun decide(
            serverID: String?,
            localID: String,
            migrated: Boolean,
            isKnown: (String) -> Boolean,
            isUnlocked: (String) -> Boolean,
        ): CharacterSyncDecision {
            val server = normalized(serverID)
            if (server == null && !migrated && localID != CharacterCatalog.builtInAingID) return migrate(localID)
            var target = server ?: CharacterCatalog.builtInAingID
            if (!isKnown(target) || !isUnlocked(target)) target = CharacterCatalog.builtInAingID
            return if (target == localID) keep else adopt(target)
        }

        /** 옮겨 가기 밀기의 응답이 판정을 끝냈는가 — 서버가 대답한 어휘면 끝이다. null · unauthorized 는 끝나지 않았다. */
        fun migrationSettled(byStatus: String?): Boolean = when (byStatus) {
            "ok", "not_owned", "unknown_character", "no_profile" -> true
            else -> false
        }

        /** nil · 빈 글 · 공백뿐 = 기본(아잉)이라 null. 앞뒤 whitespacesAndNewlines 를 지운다. */
        fun normalized(id: String?): String? {
            val trimmed = id?.let(TextScalars::trimmingWhitespacesAndNewlines) ?: return null
            return trimmed.ifEmpty { null }
        }
    }
}

/** 서버 착용값을 읽는 **때**. 스로틀은 팝오버(60초)에만 건다. */
enum class CharacterSyncReason { launch, signIn, popover }
