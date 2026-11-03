// 원본: 없음 — 와이어(W1-d core/wire) 모양을 규칙(W1-c core/rules) 모양으로 옮기는 다리. Swift 는 두 층이 한 타입이라 이 파일이 없다
// (Gacha.swift · CharacterGift.swift 의 와이어 몫과 규칙 몫이 Kotlin 에서 갈렸다 — rules 는 wire 에 기대지 않는 칸 이름 같은 사본을 들고 있다).
package com.yehsung.aingcheck.core.stores.me

import com.yehsung.aingcheck.core.net.isMissingDeviceFunction
import com.yehsung.aingcheck.core.rules.character.gift.CharacterGiftClaimOutcome
import com.yehsung.aingcheck.core.rules.gacha.GachaExchangeResponse
import com.yehsung.aingcheck.core.rules.gacha.GachaExchangeStatus
import com.yehsung.aingcheck.core.rules.gacha.GachaInfo
import com.yehsung.aingcheck.core.rules.gacha.GachaOddsEntry
import com.yehsung.aingcheck.core.rules.gacha.GachaPullResponse
import com.yehsung.aingcheck.core.rules.gacha.GachaPullStatus
import com.yehsung.aingcheck.core.rules.gacha.GachaShopRow
import com.yehsung.aingcheck.core.rules.gacha.ShopWire
import com.yehsung.aingcheck.core.wire.gift.CharacterGiftClaimResponse
import com.yehsung.aingcheck.core.wire.models.ShopCharacterRow
import com.yehsung.aingcheck.core.wire.models.GachaExchangeResponse as WireGachaExchangeResponse
import com.yehsung.aingcheck.core.wire.models.GachaInfo as WireGachaInfo
import com.yehsung.aingcheck.core.wire.models.GachaPullResponse as WireGachaPullResponse

/**
 * K9 그림 집합 → 상점 능력 번호의 재료. 번들에 초상 두 장(`<id>-neutral` · `<id>-negative`)이 **실제로 실린** 캐릭터 id 를 준다.
 * Android 는 ui 의 Gradle Sync 가 싣은 초상 파일 목록(`CharacterArt.drawableCharacterIDs()` — 조정자 패치)을 넘긴다. 숫자를 적는 자리가 아니다.
 */
fun interface DrawableCharacterSource {
    suspend fun drawableCharacterIDs(): Set<String>

    /**
     * 이 플랫폼이 '술 한잔' 선물 캐릭터(이슬 아잉이)를 **아는 캐릭터**로 다루는가 — 상점 능력 번호 5 를 말하는 플랫폼(Android 판 7)만 참.
     * 서버는 번호 5 미만에게 이슬 행을 **가진 사람에게도** 싣지 않고(20261108122000 §5-2), 그 설계 전제가 '옛 클라는 모르는 착용 id 를 아잉으로
     * 접는다'이다. 거짓이면 나 탭(착용값 · 고르기 목록 · 상점 자리표시)이 이슬을 0.3.73 처럼 아잉으로 접는다(검토 ISUL-1 — Windows v1).
     * 그림 집합과 달리 **곧바로**(suspend 없이) 답한다 — 착용값은 그림 목록을 읽기 전에도 그려진다. 기본 거짓(모르는 재료는 0.3.73 쪽으로 틀린다).
     * 조립은 ui `CharacterArt.drawableCharacterSource`(플랫폼 문 `CharacterArt.takesDrinkGift` 하나)를 넘긴다.
     */
    val takesDrinkGift: Boolean get() = false

    companion object {
        /** 고정 집합(시험 · 데모). 술 선물 문은 그 집합이 말하는 번호에서 판다(5 = 이슬까지 다 그린다 → 참) — 그림 집합과 문이 어긋나지 않는다. */
        fun of(ids: Iterable<String>): DrawableCharacterSource {
            val fixed = ids.toSet()
            val drinks = ShopWire.supportsDrinkGift(ShopWire.protocolVersion(fixed))
            return object : DrawableCharacterSource {
                override suspend fun drawableCharacterIDs(): Set<String> = fixed
                override val takesDrinkGift: Boolean get() = drinks
            }
        }
    }
}

internal object MeWireBridge {
    fun gachaInfo(wire: WireGachaInfo?): GachaInfo? = wire?.let {
        GachaInfo(
            price = it.price,
            shards = it.shards,
            odds = it.odds?.map { e -> GachaOddsEntry(e.characterID, e.percent) },
            shardCosts = it.shardCosts,
        )
    }

    fun pullResponse(wire: WireGachaPullResponse): GachaPullResponse = GachaPullResponse(
        status = GachaPullStatus.of(wire.status.raw),
        characterID = wire.characterID,
        duplicate = wire.duplicate,
        shardsGained = wire.shardsGained,
        shards = wire.shards,
        rubyBalance = wire.rubyBalance,
        price = wire.price,
        requestID = wire.requestID,
        replayed = wire.replayed,
        need = wire.need,
        have = wire.have,
    )

    fun exchangeResponse(wire: WireGachaExchangeResponse): GachaExchangeResponse = GachaExchangeResponse(
        status = GachaExchangeStatus.of(wire.status.raw),
        characterID = wire.characterID,
        shards = wire.shards,
        cost = wire.cost,
        requestID = wire.requestID,
        replayed = wire.replayed,
        need = wire.need,
        have = wire.have,
    )

    fun shopRows(rows: List<ShopCharacterRow>): List<GachaShopRow> = rows.map { GachaShopRow(it.id, it.price, it.gachaOnly) }

    fun giftClaimOutcome(response: CharacterGiftClaimResponse, requestedID: String): CharacterGiftClaimOutcome =
        CharacterGiftClaimOutcome.from(response.status, response.characterId, response.replayed, requestedID)

    /** Swift `MobileDeviceRPC.isMissingFunction`(PGRST202 → databaseSchemaMissing · 404) — db push 전 서버. */
    fun isMissingFunction(error: Throwable): Boolean = isMissingDeviceFunction(error)
}
