// 원본: Sources/CheckMobileKit/Messages/MegaphoneBannerPhoneRules.swift · App/MobileAppModel+MegaphoneBanner.swift @ a3d59e74(a3d59e74)
// 확성기 배너 · 폰 화면 규칙(계약 docs/plan/megaphone-banner-contract.md — 폰 배너). 뷰(androidApp MegaphoneBannerOverlay)는 그리기·손짓만 하고,
// 판정은 전부 여기 둔다 — 위로 쓸기 판정 · 끌림 오프셋 · 미룸 집계 · 미룸 다시 맞추기. 단추는 [닫기] 하나뿐이다([답장]은 2026-10-30 걷었다).
package com.yehsung.aingcheck.feature.phone.messages

import com.yehsung.aingcheck.core.rules.text.ChatMarkdown

/** 배너 화면 판정(순수 함수). 길이는 dp. */
object MegaphoneBannerPhoneRules {
    /** 본문 최대 줄 수. */
    const val bodyLineLimit = 4

    /**
     * 본문이 접힌 배너([bodyLineLimit] 줄)에 다 안 들어가는가 — [더 보기]를 세울지(판 8 · 폰 1.0.18 `needsMore` 와 같은 결정). 폰은 같은 폭 ·
     * 같은 글꼴의 전체 높이를 따로 재지만 Compose 는 접힌 글의 배치 결과가 넘침을 바로 말한다(`TextLayoutResult.hasVisualOverflow`).
     * 펼친 뒤에는 단추가 없다(다음 배너는 다시 접혀 선다).
     */
    fun needsMore(hasVisualOverflow: Boolean, isExpanded: Boolean): Boolean = !isExpanded && hasVisualOverflow

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

    /**
     * 배너를 미뤄야 하는가: 시트·대화상자(오버레이가 그 밑에 깔려 안 보인다) · 오목·체스·테트리스·큐브 화면 · 미니게임 판 진행 중 · 아잉 큐브 손댄 판에서 내 자리 playing
     * (맥 `MegaphoneBannerDeferral` 의 `rummyLive` — 끌기 중인 타일 위를 덮지 않게. 놀던 기기 · 기권 뒤 구경은 코어가 거짓을 낸다).
     */
    fun isDeferred(modalPresented: Boolean, matchScreenVisible: Boolean, miniGameRoundPlaying: Boolean, rummyLive: Boolean = false): Boolean =
        modalPresented || matchScreenVisible || miniGameRoundPlaying || rummyLive

    /** 스토어에 deferralChanged() 를 알려야 하는가 — 미루는데 떠 있거나(줄로 되돌린다), 풀렸는데 기다리는 것이 있다(띄운다). */
    fun needsDeferralSync(isDeferred: Boolean, hasCurrent: Boolean, hasQueue: Boolean): Boolean =
        if (isDeferred) hasCurrent else (!hasCurrent && hasQueue)

    /** 다시 보기 고리의 열쇠. 떠 있는 것도 기다리는 것도 없으면 null(고리를 돌리지 않는다). */
    fun deferralPollKey(currentID: String?, queueCount: Int): String? =
        if (currentID == null && queueCount <= 0) null else "${currentID ?: "-"}#$queueCount"
}

/** 배너에 보이는 글자. */
object MegaphoneBannerPhoneText {
    const val close = "닫기"

    /** 긴 확성기(4줄을 넘는 글)를 같은 자리에서 전체 글로 펼치는 단추(판 8 · 폰 1.0.18 · 맥 0.3.81 과 같은 글자 — 대표 결정 11-10). */
    const val more = "더 보기"

    /**
     * 배너 카드에 보일 본문 — 서식 기호(`## ` · `**` · `[글](주소)`)와 이모티콘 토큰(`[아잉:기쁨]` → "아잉이 기쁨")을 벗긴 한 줄 글
     * (판 7 · iOS 1.0.17 MegaphoneBannerPhoneText.shownBody · 맥 배너와 같은 ChatMarkdown.plainPreview). 링크는 누를 수 없는 글자다.
     * 평범한 한 줄 본문은 한 글자도 안 바뀐다.
     */
    fun shownBody(body: String): String = ChatMarkdown.plainPreview(body)

    /** 화면 읽기 라벨 — 본문은 화면과 **같은 글**([shownBody])이다(화면만 벗기면 TalkBack 이 기호 · 토큰을 또박또박 읽는다). */
    fun accessibilityLabel(name: String, body: String): String = "${name}님의 확성기, ${shownBody(body)}"
    /**
     * 화면 읽기만 읽는 글이다 — 그 사용자에게 배너는 저절로 닫히지 않는다(코어 holdsAutoDismiss · Swift a3d59e74). 손짓(쓸기·누르기)
     * 말고 닫는 길을 말한다. Swift 는 보이스오버 동작 목록("위아래로 쓸어 닫기 동작을 고르세요")을, 안드로이드는 TalkBack 이 따로 짚는
     * [닫기] 단추를 가리킨다.
     */
    const val accessibilityHint = "저절로 닫히지 않아요. 닫기 단추를 두 번 탭해 닫으세요."
}
