// 원본: Sources/CheckCore/OmokStoneSkin.swift(스킨 열거 · 두 색 묶음 · 돌 번호 · 상점 상태 · 쓰기 응답 — 그림 식은 ui `OmokStoneArt`) @ e4995a3a
// 원본: Sources/CheckMobileKit/Me/MeStoreOmokSkins.swift(OmokSkinPhoneText — 폰 1.0.18 글자) @ 928d5562
//
// 오목알 스킨(맥 0.3.81 · 0.3.82 손질 · 폰 1.0.18 · Android 판 8). 대표 결정(되묻지 않는다): 받는 방식 #d_UVBJ8vJua1jD "상점 루비 (스킨마다 100)" ·
// 보이는 범위 #d_RR2dyBIHDMW5 "상대에게도 보임" · 11-10 "네온 흑백 다이아 3개 빼" → 주사위 · 고양이 · 픽셀(서버 20261111140000_omok_skins_trim).
// 상점 상태의 lossy 디코드가 미션 응답과 같은 부품(AchievementLossy)을 써서 achievements 갈래에 둔다(모듈 안 공유 — 맥은 같은 helper 를 쓴다).
package com.yehsung.aingcheck.core.rules.achievements

import com.yehsung.aingcheck.core.rules.format.SwiftKeyed
import com.yehsung.aingcheck.core.rules.format.SwiftValue
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/** 오목알 스킨 하나(서버 원문 = 상수 이름). 새 스킨은 서버 정의표 · 여기 · 그림 식 셋을 같이 더한다. */
enum class OmokStoneSkin {
    dice, cat, pixel;

    val wireValue: String get() = name

    val displayName: String
        get() = when (this) {
            dice -> "주사위"
            cat -> "고양이"
            pixel -> "픽셀"
        }

    companion object {
        /** 스킨 능력 번호(서버 `omok_skins_state(p_protocol)` — 이 번호가 아는 스킨만 싣는다). 맥 · 폰 · Android 모두 1. */
        const val protocolVersion = 1

        /** 서버 원문 → 스킨. 정확히 그 값만(공백 · 대소문자를 봐주지 않는다). 모르는 값(빠진 네온 등)은 null = 일반 돌. */
        fun fromWire(wire: String?): OmokStoneSkin? = entries.firstOrNull { it.name == wire }
    }
}

/** 한 판의 흑 · 백 스킨(서버 `match.black_skin` · `white_skin`). null = 일반 돌. */
data class OmokStoneSkins(val black: OmokStoneSkin? = null, val white: OmokStoneSkin? = null) {
    fun skin(isBlack: Boolean): OmokStoneSkin? = if (isBlack) black else white

    companion object {
        val plain = OmokStoneSkins()

        fun ofWire(blackWire: String?, whiteWire: String?): OmokStoneSkins =
            OmokStoneSkins(OmokStoneSkin.fromWire(blackWire), OmokStoneSkin.fromWire(whiteWire))

        /** AI 판 · 미리보기처럼 한 색만 스킨인 판. */
        fun ofColor(isBlack: Boolean, skin: OmokStoneSkin?): OmokStoneSkins =
            OmokStoneSkins(if (isBlack) skin else null, if (isBlack) null else skin)

        /** 돌 번호(주사위 눈 같은 돌마다 다른 그림의 씨앗) — 맥과 같은 식(32비트 감김). */
        fun seed(x: Int, y: Int): Int = x * 31 + y * 17 + 5
    }
}

/** `omok_skins_state` 응답(상점 '오목알' 절). 칸 하나가 깨져도 나머지는 산다 — 모르는 스킨 줄은 버린다. */
data class OmokSkinsState(
    val status: String? = "ok",
    val rubyBalance: Long? = null,
    val equipped: OmokStoneSkin? = null,
    val rows: List<Row> = emptyList(),
) {
    data class Row(val skin: OmokStoneSkin, val name: String, val price: Long?, val owned: Boolean, val equipped: Boolean) {
        val id: String get() = skin.wireValue

        companion object {
            fun of(skin: OmokStoneSkin, name: String? = null, price: Long? = null, owned: Boolean = false, equipped: Boolean = false): Row =
                Row(skin, name?.takeIf { it.isNotEmpty() } ?: skin.displayName, price?.let { maxOf(0L, it) }, owned, equipped)
        }
    }

    val isOK: Boolean get() = status == "ok"

    /** 사기 · 끼기 뒤의 상태(서버 응답 없이 화면을 먼저 맞춘다 — 맥 `applying` 과 같다). */
    fun applying(owned: OmokStoneSkin? = null, equipped: OmokStoneSkin?, rubyBalance: Long? = null): OmokSkinsState = copy(
        equipped = equipped,
        rubyBalance = rubyBalance ?: this.rubyBalance,
        rows = rows.map { row -> row.copy(owned = row.owned || row.skin == owned, equipped = row.skin == equipped) },
    )

    companion object {
        /** 같은 스킨 줄은 앞의 것만. */
        fun of(status: String? = "ok", rubyBalance: Long? = null, equipped: OmokStoneSkin? = null, rows: List<Row> = emptyList()): OmokSkinsState {
            val seen = HashSet<String>()
            return OmokSkinsState(status, rubyBalance, equipped, rows.filter { seen.add(it.id) })
        }

        /** 관대한 디코드(서비스 디코더 — 키는 convertFromSnakeCase). 최상위가 객체가 아니면 [com.yehsung.aingcheck.core.rules.format.SwiftDecodingError]. */
        fun decode(element: JsonElement): OmokSkinsState {
            val c = SwiftKeyed(SwiftValue.obj(element))
            val rows = AchievementLossy.list(c, "skins")?.mapNotNull { e ->
                val o = e as? JsonObject ?: return@mapNotNull null
                val k = SwiftKeyed(o)
                val skin = OmokStoneSkin.fromWire(k.lossyString("id")) ?: return@mapNotNull null
                Row.of(skin, k.lossyString("name"), AchievementLossy.int(k, "price"), k.lossyBool("owned") ?: false, k.lossyBool("equipped") ?: false)
            } ?: emptyList()
            return of(
                status = c.lossyString("status"),
                rubyBalance = AchievementLossy.int(c, "rubyBalance"),
                equipped = OmokStoneSkin.fromWire(c.lossyString("equipped")),
                rows = rows,
            )
        }
    }
}

/** `buy_omok_skin` · `set_omok_skin` 응답. 모든 칸이 있을 수도 없을 수도 있다(관대하게). */
data class OmokSkinWriteResponse(
    val status: String?,
    val skin: String? = null,
    val price: Long? = null,
    val rubyBalance: Long? = null,
    val equipped: String? = null,
    val need: Long? = null,
    val have: Long? = null,
) {
    companion object {
        fun decode(element: JsonElement): OmokSkinWriteResponse {
            val c = SwiftKeyed(SwiftValue.obj(element))
            return OmokSkinWriteResponse(
                status = c.lossyString("status"),
                skin = c.lossyString("skin"),
                price = AchievementLossy.int(c, "price"),
                rubyBalance = AchievementLossy.int(c, "rubyBalance"),
                equipped = c.lossyString("equipped"),
                need = AchievementLossy.int(c, "need"),
                have = AchievementLossy.int(c, "have"),
            )
        }
    }
}

/** 요청 본문 셋(키를 언제나 싣는다 — `p_skin` 이 null 이면 일반 돌로 되돌리기). */
object OmokSkinRequests {
    fun state(protocolNumber: Int = OmokStoneSkin.protocolVersion): JsonObject = JsonObject(mapOf("p_protocol" to JsonPrimitive(protocolNumber)))

    fun buy(skin: OmokStoneSkin, protocolNumber: Int = OmokStoneSkin.protocolVersion): JsonObject =
        JsonObject(mapOf("p_skin" to JsonPrimitive(skin.wireValue), "p_protocol" to JsonPrimitive(protocolNumber)))

    fun set(skin: OmokStoneSkin?): JsonObject = JsonObject(mapOf("p_skin" to (skin?.let { JsonPrimitive(it.wireValue) } ?: JsonNull)))
}

/** 폰 · Android 상점 '오목알' 절 글자(폰 1.0.18 `OmokSkinPhoneText` 그대로). */
object OmokSkinPhoneText {
    const val title = "오목알"
    const val plainName = "일반 돌"
    const val equippedBadge = "착용 중"
    const val owned = "보유"
    const val note = "내 돌은 상대 화면에도 이 스킨으로 보여요"
    const val notOwned = "그 스킨을 갖고 있지 않아요"
    const val equipFailed = "바꾸지 못했어요. 잠시 후 다시 시도해 주세요"
    const val needsUpdate = "앱을 업데이트하면 살 수 있어요"

    fun name(skin: OmokStoneSkin?): String = skin?.displayName ?: plainName
    fun bought(skin: OmokStoneSkin): String = "샀어요! 이제 내 돌은 ${skin.displayName}"
    fun equipped(skin: OmokStoneSkin?): String = "내 돌을 ${name(skin)}${ro(name(skin))} 바꿨어요"
    fun alreadyEquipped(skin: OmokStoneSkin?): String = "이미 ${name(skin)}${eul(name(skin))} 쓰고 있어요"
    fun confirmTitle(skin: OmokStoneSkin): String = "${skin.displayName} 오목알을 살까요?"

    private fun finalConsonant(word: String): Int {
        val last = word.lastOrNull()?.code ?: return 0
        return if (last in 0xAC00..0xD7A3) (last - 0xAC00) % 28 else 0
    }

    private fun ro(word: String): String = if (finalConsonant(word) == 0 || finalConsonant(word) == 8) "로" else "으로"
    private fun eul(word: String): String = if (finalConsonant(word) == 0) "를" else "을"
}
