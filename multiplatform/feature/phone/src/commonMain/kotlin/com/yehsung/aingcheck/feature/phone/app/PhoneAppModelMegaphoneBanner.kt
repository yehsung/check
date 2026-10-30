// 원본: Sources/CheckMobileKit/App/MobileAppModel+MegaphoneBanner.swift @ a6791165(57810a8e)
// 확성기 배너 · 폰 앱 모델 배선(계약 docs/plan/megaphone-banner-contract.md — 폰 배너).
// 뷰(androidApp MegaphoneBannerOverlay)는 그리기·손짓만 하고, 미룸 판정과 [답장]은 여기서 한다(JVM 시험이 잰다).
package com.yehsung.aingcheck.feature.phone.app

import com.yehsung.aingcheck.core.rules.text.MegaphoneBanner
import com.yehsung.aingcheck.feature.phone.messages.MegaphoneBannerPhoneRules

/** 지금 배너를 미뤄야 하는가 — 시트·대화상자 · 오목·체스·테트리스 화면 · 미니게임 판 진행 중. 스토어의 isBannerDeferred 가 이 값을 본다. */
val PhoneAppModel.isMegaphoneBannerDeferred: Boolean
    get() = MegaphoneBannerPhoneRules.isDeferred(
        modalPresented = megaphoneModalProbe(),
        matchScreenVisible = games.isAnyMatchScreenVisible,
        miniGameRoundPlaying = games.miniGames.controller?.isPlaying ?: false,
    )

/** 미룸이 바뀌었으면 스토어에 알린다(배너 오버레이가 대결 화면 변화 · 1초 다시 보기에서 부른다). */
fun PhoneAppModel.syncMegaphoneBannerDeferral() {
    val store = megaphoneBanner
    if (!MegaphoneBannerPhoneRules.needsDeferralSync(isMegaphoneBannerDeferred, store.current != null, store.queue.isNotEmpty())) return
    store.deferralChanged()
}

/** [답장]: 보낸 사람과의 1:1 대화를 열고(이름·아바타를 함께 넘긴다) 배너를 닫는다. 내 배너·상대 모름은 닫기만. */
fun PhoneAppModel.replyToMegaphoneBanner(banner: MegaphoneBanner) {
    MegaphoneBannerPhoneRules.replyRoute(banner)?.let { route ->
        val name = banner.senderName.takeIf { it != MegaphoneBanner.fallbackSenderName }
        messages.rememberPeerHint(route.peerID, name, banner.senderAvatarURL)
        openRoute(route)
    }
    megaphoneBanner.dismissCurrent()
}
