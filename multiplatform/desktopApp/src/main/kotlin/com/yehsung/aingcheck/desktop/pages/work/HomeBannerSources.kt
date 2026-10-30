// 원본: Sources/check/CheckMenuView.swift @ db93317f — 142-170(오목 신청 배너: [수락] 서버 응답 → 창 → 팝오버 닫기 · [거절] 응답만 · [보기] 창 → 팝오버 닫기)
//       · 176-200(체스 — 같은 순서) · 216-240(테트리스 — 같은 순서) · 270-287(topBanner 순서) · 503-531(답장 [보기]=openFeedbackPanel · X=markFeedbackReplyBannerSeen
//       · 케이크 [고르기]=openCakeGiftWindow, 닫기 없음) · WorkTimerStore.swift:3083-3147(답장 배너 판정 · '봤음'은 서버가 준 마지막 답장 시각)
//       · WorkTimerStoreCakeGift.swift:61-63(showsCakeGiftCard = 열린 선물 있음) · 133-137(창 먼저, 팝오버 나중)
//
// int-w3(W-14 #5) 홈 배너 나머지 — 대결 신청(수락·거절·보기) · 제보 답장 · 케이크 선물. 이 파일은 공용 코어를 부르지 않는다 — 조립(AppGraph)이
// 스토어를 람다로 묶어 넘긴다(PagesWiring.HomeBannerStores). 깃발(DesktopAppConfig.duels) 꺼짐이면 대결 문은 **읽지도 부르지도 않는다**:
// 배너 후보가 서지 않고(BannerQueue 도 막는다), [수락]·[거절]이 잘못 불려도 응답 RPC 0(스토어의 거절 경로는 깃발을 안 본다 — GomokuStore.respond).
package com.yehsung.aingcheck.desktop.pages.work

import com.yehsung.aingcheck.desktop.pages.banners.DuelInviteBanner
import com.yehsung.aingcheck.desktop.pages.banners.TopBanner
import com.yehsung.aingcheck.desktop.shellapi.FlyoutNavigator
import com.yehsung.aingcheck.desktop.shellapi.FlyoutRoute

/** 한 게임(오목·체스·테트리스)의 받은 신청 배너 문. */
class DuelBannerSource(
    /** 스토어가 만료 판정을 끝낸 표시 신청(오목 `bannerInvite` · 체스·테트리스 `visibleIncoming`) — Compose 상태를 읽는 람다. */
    val invite: () -> DuelInviteBanner?,
    /** 서버 응답(스토어 `respond(inviteID, accept)`). */
    val respond: suspend (matchId: String, accept: Boolean) -> Unit,
    /** 그 신청에 초점을 둔 대결 창(DesktopGameWindows.openGomoku(focusMatchID) 등). */
    val openWindow: (matchId: String) -> Unit,
)

/** 제보 답장 배너 문. [unseen] = 안 본 답장이 있다(Compose 상태) · [markSeen] = X(서버가 준 마지막 답장 시각을 '봤음'으로). */
class FeedbackReplyBannerSource(val unseen: () -> Boolean, val markSeen: () -> Unit)

/** 생일 선물 '다시 열기' 배너 문. [open] = 열린 선물이 있다(받으면 내려간다) · [choose] = 축하 창을 띄운다(끝나면 플라이아웃을 닫는다). */
class CakeGiftBannerSource(val open: () -> Boolean, val choose: suspend () -> Unit)

/** 홈 배너 나머지 공급자 묶음. [launch] = 응답을 띄울 범위(조립: `{ scope.launch { it() } }`). */
class HomeBannerSources(
    val gomoku: DuelBannerSource? = null,
    val chess: DuelBannerSource? = null,
    val tetris: DuelBannerSource? = null,
    val feedbackReply: FeedbackReplyBannerSource? = null,
    val cakeGift: CakeGiftBannerSource? = null,
    val launch: (suspend () -> Unit) -> Unit,
)

/**
 * [sources] 를 배너 후보·동작에 싣는다(없으면 그대로). 대결 문은 [HomePageDeps.duelsEnabled] 일 때만 — 꺼짐이면 셋 다 버린다.
 * [nav] 는 '창 먼저, 플라이아웃 나중' 의 나중(맥 WindowTopAnchor.dismissMenuPopover)과 답장 [보기](FlyoutRoute.Feedback)에 쓴다.
 */
fun HomePageDeps.withBannerSources(sources: HomeBannerSources?, nav: FlyoutNavigator): HomePageDeps {
    if (sources == null) return this
    val base = this
    val duels = base.duelsEnabled
    val gomoku = sources.gomoku.takeIf { duels }
    val chess = sources.chess.takeIf { duels }
    val tetris = sources.tetris.takeIf { duels }
    val reply = sources.feedbackReply
    val cake = sources.cakeGift
    fun duelOf(banner: TopBanner): DuelBannerSource? = when (banner) {
        TopBanner.GOMOKU_INVITE -> gomoku
        TopBanner.CHESS_INVITE -> chess
        TopBanner.TETRIS_INVITE -> tetris
        else -> null
    }
    val a = base.actions
    val actions = HomeBannerActions(
        openRecords = a.openRecords,
        dismissRetro = a.dismissRetro,
        retroDisplayed = a.retroDisplayed,
        // 토글이 아니라 '열기'(맥 openFeedbackPanel) — 제보 화면을 떠날 때 '봤음'이 적힌다(MeStore.feedbackDidDisappear).
        openFeedback = if (reply == null) a.openFeedback else { { nav.navigate(FlyoutRoute.Feedback) } },
        dismissFeedbackReply = if (reply == null) a.dismissFeedbackReply else reply.markSeen,
        openCakeGift = if (cake == null) {
            a.openCakeGift
        } else {
            {
                sources.launch {
                    cake.choose()
                    nav.hide()
                }
            }
        },
        installUpdate = a.installUpdate,
        dismissNotice = a.dismissNotice,
        acceptDuel = { banner, invite ->
            val src = duelOf(banner)
            if (src == null) {
                a.acceptDuel(banner, invite)
            } else {
                // 서버 수락 → 창 → 플라이아웃 닫기. 수락이 실패해도(만료 등) 창은 연다 — 로비 안내줄이 이유를 말한다(맥 145-147).
                sources.launch {
                    src.respond(invite.matchId, true)
                    src.openWindow(invite.matchId)
                    nav.hide()
                }
            }
        },
        declineDuel = { banner, invite ->
            val src = duelOf(banner)
            // 거절은 서버에 알리기만 — 창도 플라이아웃 닫기도 없다(맥 157-163).
            if (src == null) a.declineDuel(banner, invite) else sources.launch { src.respond(invite.matchId, false) }
        },
        openDuel = { banner, invite ->
            val src = duelOf(banner)
            if (src == null) {
                a.openDuel(banner, invite)
            } else {
                src.openWindow(invite.matchId)
                nav.hide()
            }
        },
    )
    return HomePageDeps(
        work = base.work,
        commands = base.commands,
        teamStatuses = base.teamStatuses,
        clock = base.clock,
        isSignedIn = base.isSignedIn,
        isTeamless = base.isTeamless,
        myUserId = base.myUserId,
        teamName = base.teamName,
        teamGoalSeconds = base.teamGoalSeconds,
        duelsEnabled = base.duelsEnabled,
        update = base.update,
        syncMessage = base.syncMessage,
        inviteCode = base.inviteCode,
        canSync = base.canSync,
        bannerFeed = {
            val f = base.bannerFeed()
            f.copy(
                gomoku = f.gomoku ?: gomoku?.invite?.invoke(),
                chess = f.chess ?: chess?.invite?.invoke(),
                tetris = f.tetris ?: tetris?.invite?.invoke(),
                feedbackReplyUnseen = f.feedbackReplyUnseen || reply?.unseen?.invoke() == true,
                cakeGiftOpen = f.cakeGiftOpen || cake?.open?.invoke() == true,
            )
        },
        actions = actions,
        tickMillis = base.tickMillis,
        middle = base.middle,
    )
}
