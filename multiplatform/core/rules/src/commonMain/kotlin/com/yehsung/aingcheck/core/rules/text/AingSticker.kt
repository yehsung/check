// 원본: Sources/CheckCore/AingSticker.swift @ 1b8260d (판정·문구 몫 — 그림 읽기 AingStickerArt 는 화면 갈래가 Compose 로, 그림 6장은 Gradle Sync)
package com.yehsung.aingcheck.core.rules.text

/**
 * 아잉이 이모티콘 여섯 종(v0.3.62 — 서버를 하나도 안 고치는 전선 규약). **case 순서가 고르는 그리드의 순서다.**
 *
 * 전선은 평문 토큰이다(`send_message` 가 받는 글자 그대로). 받는 쪽은 본문이 토큰과 **통째로 같을 때만** 그림으로 그린다 —
 * 구버전은 `[아잉:기쁨]` 이라는 읽을 수 있는 글자로 본다(능력 협상이 필요 없다). 토큰 글자([token])와 화면 글자([label])는
 * 따로 둔다 — 화면 문구를 다듬는 커밋이 전선 규약을 조용히 바꾸지 않게(토큰 여섯은 골든 `stickers/tokens` 가 글자 그대로 잠근다).
 *
 * 판정은 언제나 [parse] 다 — [tokenPrefix] 만으로 참을 내지 않는다(`[아잉:없는것]` 도 그 머리를 갖는다).
 * [rawValue] 는 그림 파일 이름의 꼬리(`sticker-<rawValue>.png`)이고 전선에 나가지 않는다.
 */
enum class AingSticker(val rawValue: String, val token: String, val label: String) {
    joy("joy", "[아잉:기쁨]", "기쁨"),
    heart("heart", "[아잉:하트]", "하트"),
    sad("sad", "[아잉:슬픔]", "슬픔"),
    angry("angry", "[아잉:화남]", "화남"),
    sleepy("sleepy", "[아잉:졸림]", "졸림"),
    surprised("surprised", "[아잉:놀람]", "놀람"),
    ;

    /** 번들 그림 이름(확장자 없음). */
    val resourceName: String get() = "sticker-$rawValue"

    companion object {
        /** 토큰의 머리 — "이모티콘인 것 같다"를 싸게 묻는 자리. 이것만으로 참을 내지 마라. */
        const val tokenPrefix: String = "[아잉:"

        /**
         * 본문이 이모티콘 하나인가. **통째로 같을 때만** 참이다(`MessageBody.sanitized` 뒤 토큰과 정확히 같다).
         *
         * INV-AingSticker-c811ca4a 이식: 앞에 둘 수 있는 것은 **정규화와 무관한 검사뿐**이다 — 첫 글자(앞 공백류를 건너뛴)가 `[` 인가 하나. `[` 는 ASCII 라
         * 정규화가 건드리지 않는다. 자모 분해(NFD)로 들어온 한글 토큰도 그림이어야 한다(머리 검사에서 빠지면 안 된다).
         * INV-AingSticker-6615f703 · INV-AingSticker-ea235ead 이식: 건너뛰는 집합은 아래 sanitized 의 trim 집합과 **글자 하나까지 같아야 한다**(Foundation `.whitespacesAndNewlines` —
         * White_Space 속성으로 재면 U+200B 하나가 어긋나 그림이 글자가 된다, v0.3.62 검토 지적 ②).
         */
        fun parse(body: String): AingSticker? {
            val cps = body.codePointArray()
            val head = cps.firstOrNull { !TextScalars.inWhitespacesAndNewlines(it) } ?: return null
            if (head != '['.code) return null
            val normalized = MessageBody.sanitized(body)
            if (!normalized.startsWith(tokenPrefix)) return null
            return entries.firstOrNull { it.token == normalized }
        }
    }
}

/** 이모티콘 문구 한 벌(맥·폰·Android·알림이 같은 말을 쓴다). */
object AingStickerText {
    const val gridTitle = "아잉이 이모티콘"
    const val buttonLabel = "아잉이 이모티콘 보내기"
    const val closeGridLabel = "이모티콘 닫기"
    /** 못 보내는 상태(= 왕복 중)에서 칸을 고른 경우의 한 줄 — 조용히 닫지 않는다. */
    const val sendingNowNotice = "보내는 중이에요. 잠시 후 다시 눌러 주세요"

    /** 그림 한 장의 보이스오버("아잉이 기쁨"). */
    fun accessibilityLabel(sticker: AingSticker): String = "아잉이 ${sticker.label}"

    /**
     * **글자만 들어가는 자리**(대화 목록 한 줄 · 안 읽음 요약 · 알림)에 쓸 한 줄. 이모티콘이 아니면 **원문 그대로** —
     * 평범한 메시지를 건드리면 그게 곧 "내가 보낸 말이 화면에서 달라지는" 버그다.
     */
    fun preview(body: String): String {
        val sticker = AingSticker.parse(body) ?: return body
        return accessibilityLabel(sticker)
    }
}

/**
 * 그림 폴더 이름(Swift `AingStickerArt.folderName`) — Android·Windows 는 Gradle Sync 로 같은 6장을 읽는다(git 사본 0).
 *
 * 그림 읽기(`AingStickerArt`)는 화면 갈래(W3-a 메시지 화면 · Compose)가 옮긴다. 그 몫의 규약은 이 자리에서 이름만 넘긴다:
 *  - INV-AingSticker-4d915e2f 이식(화면 갈래 몫 — 여기는 판정만): 그림이 없으면 빈 말풍선이 아니라 [AingStickerText.preview] 글자로 접는다.
 *  - INV-AingSticker-a6bb0ef6 이식(화면 갈래 몫): "그림으로 그리는가"를 판정하는 자리는 하나 — [AingSticker.parse] + 그림 있음을 한 함수로.
 *  - INV-AingSticker-630f7c45 해당 없음(SwiftUI `Image(decorative:)` 의 보이스오버 문구 소실 — Compose 는 contentDescription 을 그림에 직접 단다).
 *  - INV-AingSticker-2828fac0 해당 없음(NSLock 재귀 금지 캐시 — Compose 리소스 캐시는 화면 갈래 몫).
 */
object AingStickerArtNames {
    const val folderName = "Stickers"
}
