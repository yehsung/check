// 원본: Sources/CheckCore/SupabaseWorkServicePrivateStorage.swift:40-77(PrivateStorage 경로 규칙) ·
//       Sources/CheckCore/MessagePhotoWire.swift:29-133(MessagePhotoText 상수 · MessagePhotoAttachment init? · MessagePhotoPath) @ main 341eb4e3
package com.yehsung.aingcheck.core.wire.messages

import com.yehsung.aingcheck.core.wire.models.MessagePhotoAttachment

/**
 * 비공개 버킷 경로 규칙(순수 — 맥 0.3.86 메시지 사진 · 제보 캡처가 같이 쓴다). 서버 정책이 첫 폴더를 `auth.uid()::text` 와 글자 그대로
 * 견주므로 **소문자**로 만든다. 이상한 값이 서명 URL 을 엉뚱한 곳으로 돌리지 못하게 안전 글자만 받는다.
 */
object PrivateStorage {
    /** `<owner 소문자>/<name 소문자>.<ext>`. */
    fun objectPath(owner: String, name: String, ext: String = "jpg"): String = "${owner.lowercase()}/${name.lowercase()}.${ext.lowercase()}"

    /** `<폴더…>/<name>.<ext>`(소문자). */
    fun objectPath(folders: List<String>, name: String, ext: String = "jpg"): String =
        (folders.map { it.lowercase() } + "${name.lowercase()}.${ext.lowercase()}").joinToString("/")

    /** 소문자 · 숫자 · `-_.` 만, 마디 둘 이상, 빈 마디 · `.` · `..` 없음, 512 글자 이하. */
    fun isSafeObjectPath(path: String): Boolean {
        if (path.isEmpty() || path.length > 512) return false
        val segments = path.split("/")
        if (segments.size < 2) return false
        return segments.all { s -> s.isNotEmpty() && s != "." && s != ".." && s.all { it in SAFE } }
    }

    /** 버킷 이름은 소문자 · 숫자 · `-` 만. */
    fun isSafeBucket(bucket: String): Boolean = bucket.isNotEmpty() && bucket.all { it in 'a'..'z' || it in '0'..'9' || it == '-' }

    private const val SAFE = "abcdefghijklmnopqrstuvwxyz0123456789-_."
}

/** 메시지 사진의 전선 상수(서버 §2 — 버킷 · 크기 범위 · 확장자). 화면 글자는 rules(`MessagePhotoText`)에 있다. */
object MessagePhotoWire {
    const val bucket = "message-photos"
    const val signedURLSeconds = 3_600L
    /** 열린 대화의 사진 칸을 받을 때 `message_page` 한 번이 받는 줄 수(머리 24시간에는 사진 칸이 없다). */
    const val metaPageLimit = 30
    val sideRange: LongRange = 1L..20_000L
    val serverExtensions: Set<String> = setOf("jpg", "png", "heic", "webp")
    const val uploadExtension = "jpg"
    /** 사진만 보낸 줄의 대체 글(서버 `message_photo_fallback_body()` 와 같은 글). */
    const val photoFallbackBody = "📷 사진"

    /** 서버 값 → 사진(Swift `MessagePhotoAttachment.init?`). 경로가 서버 모양이 아니거나 크기가 범위 밖이면 null(그 줄은 글로 그린다). */
    fun attachment(path: String?, width: Long?, height: Long?): MessagePhotoAttachment? {
        if (path == null || !isServerShaped(path) || width == null || height == null) return null
        if (width !in sideRange || height !in sideRange) return null
        return MessagePhotoAttachment(path, width, height)
    }

    /** `<내 uid 소문자>/<id 소문자>.jpg`. */
    fun uploadPath(owner: String, id: String): String = PrivateStorage.objectPath(owner, id, uploadExtension)

    /** 서버 정규식 `^<uuid>/<uuid>\.(jpg|png|heic|webp)$` 와 같은 판정(소문자 16진 8-4-4-4-12). */
    fun isServerShaped(path: String): Boolean {
        val parts = path.split("/")
        if (parts.size != 2 || !isLowercaseUUID(parts[0])) return false
        val file = parts[1].split(".")
        if (file.size != 2 || !isLowercaseUUID(file[0]) || file[1] !in serverExtensions) return false
        return PrivateStorage.isSafeObjectPath(path)
    }

    fun isLowercaseUUID(text: String): Boolean {
        val groups = text.split("-")
        if (groups.map { it.length } != listOf(8, 4, 4, 4, 12)) return false
        return groups.all { g -> g.all { it in '0'..'9' || it in 'a'..'f' } }
    }
}
