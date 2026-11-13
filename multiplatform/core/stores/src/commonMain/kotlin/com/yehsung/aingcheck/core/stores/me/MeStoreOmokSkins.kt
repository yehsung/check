// 원본: Sources/CheckMobileKit/Me/MeStoreOmokSkins.swift @ 928d5562(폰 1.0.18 — 맥 0.3.81 `WorkTimerStoreOmokSkins` 와 같은 규약)
package com.yehsung.aingcheck.core.stores.me

import com.yehsung.aingcheck.core.net.AuthErrorDisposition
import com.yehsung.aingcheck.core.net.AuthErrorRules
import com.yehsung.aingcheck.core.rules.achievements.OmokSkinPhoneText
import com.yehsung.aingcheck.core.rules.achievements.OmokSkinsState
import com.yehsung.aingcheck.core.rules.achievements.OmokStoneSkin
import com.yehsung.aingcheck.core.rules.format.SharedText
import com.yehsung.aingcheck.core.stores.service.buyOmokSkin
import com.yehsung.aingcheck.core.stores.service.omokSkinsState
import com.yehsung.aingcheck.core.stores.service.setOmokSkin

// 오목알 스킨 — 상점(판 8 · 폰 1.0.18 과 같은 규약). 서버: omok_skins_state(p_protocol) · buy_omok_skin(p_skin, p_protocol) · set_omok_skin(p_skin).
//  ① 상점 '오목알' 절: '일반 돌' + 서버가 말한 스킨 칸. 안 가진 칸을 누르면 확인 뒤 산다(사면 서버가 바로 끼운다). 가진 칸을 누르면 낀다.
//  ② 낀 스킨은 서버 대국 · 관전 응답(match.black_skin · white_skin)으로 상대 · 관전자 판에 그려진다. AI 판만 로컬이라 [MeLinks.noteEquippedOmokSkin].
//  ③ 잔량은 캐릭터 사기와 같은 규약 — 쓰기 응답의 서버 값을 루비 미러에 옮긴다.

/** 상점이 처음 서면 한 번 읽는다(이미 알거나 · 서버에 없거나 · 떠 있으면 요청 0건). */
fun MeStore.refreshOmokSkinsIfNeeded() {
    if (!context.sessionStore.isSignedIn || omokSkins != null || omokSkinsUnavailable || omokSkinsLoading) return
    omokSkinsLoading = true
    launch { loadOmokSkins() }
}

suspend fun MeStore.loadOmokSkins() {
    if (!context.sessionStore.isSignedIn) {
        omokSkinsLoading = false
        return
    }
    omokSkinsLoading = true
    val generation = context.generation
    val service = context.service
    try {
        val state = context.withSessionRetry { s -> service.omokSkinsState(s.accessToken) }
        if (generation != context.generation || !state.isOK) return
        applyOmokSkins(state)
    } catch (e: Throwable) {
        if (generation != context.generation) return
        if (AuthErrorRules.classify(e) == AuthErrorDisposition.cancelled) return
        if (MeWireBridge.isMissingFunction(e)) omokSkinsUnavailable = true
    } finally {
        if (generation == context.generation) omokSkinsLoading = false
    }
}

internal fun MeStore.applyOmokSkins(state: OmokSkinsState) {
    if (omokSkinsUnavailable) omokSkinsUnavailable = false
    if (omokSkins != state) omokSkins = state
    context.meLinks.noteEquippedOmokSkin(state.equipped)
}

/** 상점에 '오목알' 절을 세우는가 — 서버가 스킨 줄을 하나라도 말했을 때만. */
val MeStore.showsOmokSkins: Boolean get() = !omokSkinsUnavailable && omokSkins?.rows?.isNotEmpty() == true

val MeStore.equippedOmokSkin: OmokStoneSkin? get() = omokSkins?.equipped

fun MeStore.isOmokSkinOwned(skin: OmokStoneSkin): Boolean = omokSkins?.rows?.firstOrNull { it.skin == skin }?.owned == true

fun MeStore.omokSkinPrice(skin: OmokStoneSkin): Long? = omokSkins?.rows?.firstOrNull { it.skin == skin }?.price

/** 낀다(null = 일반 돌). 이미 낀 것이면 그 사실만 말한다. */
fun MeStore.equipOmokSkin(skin: OmokStoneSkin?) {
    if (!context.sessionStore.isSignedIn || omokSkinBusy != null) return
    if (omokSkins?.equipped == skin && omokSkins != null) {
        omokSkinNotice = OmokSkinPhoneText.alreadyEquipped(skin)
        return
    }
    omokSkinBusy = "equip"
    omokSkinNotice = null
    val generation = context.generation
    val service = context.service
    launch {
        try {
            val response = try {
                context.withSessionRetry { s -> service.setOmokSkin(s.accessToken, skin) }
            } catch (e: Throwable) {
                if (generation != context.generation) return@launch
                if (AuthErrorRules.classify(e) == AuthErrorDisposition.cancelled) return@launch
                omokSkinNotice = OmokSkinPhoneText.equipFailed
                return@launch
            }
            if (generation != context.generation) return@launch
            when (response.status) {
                "ok" -> {
                    val equipped = OmokStoneSkin.fromWire(response.equipped)
                    omokSkins?.let { applyOmokSkins(it.applying(equipped = equipped)) }
                    omokSkinNotice = OmokSkinPhoneText.equipped(equipped)
                }
                "not_owned" -> {
                    omokSkinNotice = OmokSkinPhoneText.notOwned
                    loadOmokSkins()
                }
                else -> omokSkinNotice = OmokSkinPhoneText.equipFailed
            }
        } finally {
            if (generation == context.generation) omokSkinBusy = null
        }
    }
}

/** 산다(확인 대화상자의 [구매하기]만 부른다). 사면 서버가 바로 끼운다. */
fun MeStore.buyOmokSkin(skin: OmokStoneSkin) {
    if (!context.sessionStore.isSignedIn || omokSkinBusy != null) return
    omokSkinBusy = skin.wireValue
    omokSkinNotice = null
    val generation = context.generation
    val service = context.service
    launch {
        try {
            val response = try {
                context.withSessionRetry { s -> service.buyOmokSkin(s.accessToken, skin) }
            } catch (e: Throwable) {
                if (generation != context.generation) return@launch
                if (AuthErrorRules.classify(e) == AuthErrorDisposition.cancelled) return@launch
                omokSkinNotice = MeText.buyFailed
                return@launch
            }
            if (generation != context.generation) return@launch
            response.rubyBalance?.let { context.ruby.rubyBalance = it }
            when (response.status) {
                "ok" -> {
                    val equipped = OmokStoneSkin.fromWire(response.equipped) ?: skin
                    omokSkins?.let { applyOmokSkins(it.applying(owned = skin, equipped = equipped, rubyBalance = response.rubyBalance)) }
                    omokSkinNotice = OmokSkinPhoneText.bought(skin)
                }
                "already_owned" -> {
                    omokSkinNotice = MeText.alreadyOwned
                    loadOmokSkins()
                }
                "insufficient" -> omokSkinNotice = SharedText.shortfallNotice(response.need, response.have)
                "needs_update" -> omokSkinNotice = OmokSkinPhoneText.needsUpdate
                else -> omokSkinNotice = MeText.buyFailed
            }
        } finally {
            if (generation == context.generation) omokSkinBusy = null
        }
    }
}
