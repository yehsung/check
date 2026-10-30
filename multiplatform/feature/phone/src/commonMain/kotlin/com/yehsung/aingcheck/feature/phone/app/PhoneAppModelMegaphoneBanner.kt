// 원본: Sources/CheckMobileKit/App/MobileAppModel+MegaphoneBanner.swift @ f3360b47(8e83aa35)
// 확성기 배너 · 폰 앱 모델 배선(계약 docs/plan/megaphone-banner-contract.md — 폰 배너).
// 뷰(androidApp MegaphoneBannerOverlay)는 그리기·손짓만 하고, 미룸 판정은 여기서 한다(JVM 시험이 잰다). 단추는 [닫기]뿐 — 스토어를 바로 부른다.
package com.yehsung.aingcheck.feature.phone.app

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
