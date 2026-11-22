// 원본: Sources/CheckCore/RegionGift.swift:49-71(region_gift_ensure 본문 · 응답) @ main 341eb4e3 (맥 0.3.85 — 우리 센터 선물)
package com.yehsung.aingcheck.core.wire.gift

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/** `region_gift_ensure(p_protocol)` 본문 — 우리 센터 선물이 없으면 만들어 달라고(있으면 그대로) 서버에 말한다. 키를 언제나 싣는다. */
@Serializable
data class RegionGiftEnsureRequest(@SerialName("p_protocol") val pProtocol: Long)

/**
 * `region_gift_ensure` 응답 — `{"status":"granted"|"pending"|"owned"|"no_center"|"needs_update"|"unauthorized", …}`.
 * 화면은 이 값으로 아무것도 그리지 않는다(뒤이은 `character_gift_pending` 이 선물을 싣는다) — 진단용이다. 모르는 칸은 버린다.
 */
@Serializable
data class RegionGiftEnsureResponse(val status: String)
