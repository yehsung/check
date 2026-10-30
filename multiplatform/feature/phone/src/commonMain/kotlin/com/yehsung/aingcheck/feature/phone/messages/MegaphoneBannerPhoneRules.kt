// 원본: Sources/CheckMobileKit/Messages/MegaphoneBannerPhoneRules.swift · App/MobileAppModel+MegaphoneBanner.swift @ a6791165(57810a8e)
// 확성기 배너 · 폰 화면 규칙(계약 docs/plan/megaphone-banner-contract.md — 폰 배너). 뷰(androidApp MegaphoneBannerOverlay)는 그리기·손짓만 하고,
// 판정은 전부 여기 둔다 — 위로 쓸기 판정 · 끌림 오프셋 · 미룸 집계 · 미룸 다시 맞추기 · [답장] 라우트.
package com.yehsung.aingcheck.feature.phone.messages

import com.yehsung.aingcheck.core.rules.text.MegaphoneBanner
import com.yehsung.aingcheck.feature.phone.routing.PhoneRouteTarget

/** 배너 화면 판정(순수 함수). 길이는 dp. */
object MegaphoneBannerPhoneRules {
    /** 본문 최대 줄 수. */
    const val bodyLineLimit = 4

    /** 카드 모서리. */
    const val cornerRadius = 22f

    /** 상태바 아래 첫 틈. */
    const val topGap = 8f

    /** 이만큼 위로 끌고 놓으면 닫힌다. */
    const val dismissDistance = 36f

    /** 짧게 끌어도 이만큼 위로 튕기면(속도 × 0.25초 예측 끝점) 닫힌다. */
    const val dismissPredicted = 90f

    /** 아래로 끄는 것은 이만큼까지만 따라온다(고무줄). */
    const val downwardLimit = 16f

    /** 들어오기 전·나간 뒤 카드가 있는 자리: 카드 높이 + 상태바·틈을 넉넉히 넘는 값(화면 위 밖). */
    const val topClearance = 120f

    /** 시트·대결 화면·미니게임 판이 바뀌었는지 다시 보는 간격(배너가 떠 있거나 기다릴 때만 돈다). */
    const val deferralPollSeconds = 1.0

    /** 손을 뗐을 때 닫는가 — 위로 충분히 끌었거나, 위로 튕겼다. 아래로 끈 것은 닫지 않는다. */
    fun swipeDismisses(translation: Float, predictedEnd: Float): Boolean =
        translation <= -dismissDistance || predictedEnd <= -dismissPredicted

    /** 끄는 동안 카드가 따라오는 양 — 위로는 그대로, 아래로는 1/4 만큼 [downwardLimit] 까지. */
    fun dragOffset(translation: Float): Float = if (translation <= 0f) translation else minOf(translation * 0.25f, downwardLimit)

    /** 미끄러져 들어오고 나가는 거리(위로, 음수). 이동만 이징하고 불투명도는 건드리지 않는다. */
    fun slideOutOffset(cardHeight: Float): Float = -(maxOf(cardHeight, 0f) + topClearance)

    /** 배너를 미뤄야 하는가: 시트·대화상자(오버레이가 그 밑에 깔려 안 보인다) · 오목·체스·테트리스 화면 · 미니게임 판 진행 중. */
    fun isDeferred(modalPresented: Boolean, matchScreenVisible: Boolean, miniGameRoundPlaying: Boolean): Boolean =
        modalPresented || matchScreenVisible || miniGameRoundPlaying

    /** 스토어에 deferralChanged() 를 알려야 하는가 — 미루는데 떠 있거나(줄로 되돌린다), 풀렸는데 기다리는 것이 있다(띄운다). */
    fun needsDeferralSync(isDeferred: Boolean, hasCurrent: Boolean, hasQueue: Boolean): Boolean =
        if (isDeferred) hasCurrent else (!hasCurrent && hasQueue)

    /** 다시 보기 고리의 열쇠. 떠 있는 것도 기다리는 것도 없으면 null(고리를 돌리지 않는다). */
    fun deferralPollKey(currentID: String?, queueCount: Int): String? =
        if (currentID == null && queueCount <= 0) null else "${currentID ?: "-"}#$queueCount"

    /** [답장]이 여는 곳 — 상대를 알고 내가 보낸 것이 아닐 때만 1:1 대화. */
    fun replyRoute(banner: MegaphoneBanner): PhoneRouteTarget.Message? {
        if (!banner.canReply) return null
        val peerID = safeID(banner.senderID) ?: return null
        return PhoneRouteTarget.Message(peerID)
    }

    /** Swift `PushPayload.safeID`: 다듬고, 1~64자 영문·숫자·`-`·`_` 이면 소문자로(라우트 id 규칙). */
    fun safeID(raw: String?): String? {
        val trimmed = raw?.trim() ?: return null
        if (trimmed.isEmpty() || trimmed.length > 64) return null
        if (!trimmed.all { it in 'a'..'z' || it in 'A'..'Z' || it in '0'..'9' || it == '-' || it == '_' }) return null
        return trimmed.lowercase()
    }
}

/** 배너에 보이는 글자. */
object MegaphoneBannerPhoneText {
    const val reply = "답장"
    const val close = "닫기"
    fun accessibilityLabel(name: String, body: String): String = "${name}님의 확성기, $body"
    const val accessibilityHint = "위로 쓸면 닫혀요. 누르고 있으면 멈춰요."
}
