// 원본: Sources/check/CheckMenuView.swift:59-96(TopBanner 순위 주석) · 130-133(isMainScreen) · 270-287(topBanner 고르기)
//       · 466-531(그리는 자리 — 업데이트·공지·회고·답장·케이크는 헤더 위, 12시간은 헤더 바로 위 형제, 대결 신청은 헤더 아래)
// W3-c2 — 홈 배너 큐. **한 번에 하나**(맥 팝오버 700pt 예산과 같은 이유 — 플라이아웃도 위 모서리 고정). 판정은 스토어가 끝내 둔 값만
// 읽는다(시각 비교 금지 — 맥 136-140 경고). 밀린 배너는 상태를 소비하지 않아 다음에 뜬다.
package com.yehsung.aingcheck.desktop.pages.banners

import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.models.AppNotice

/** 맥 `CheckMenuView.TopBanner` 와 같은 순서(급한 것 먼저). [swiftCase] 는 맥 case 이름 — 소스 계약 시험이 맥 순서와 대조한다. */
enum class TopBanner(val swiftCase: String) {
    /** 12시간 확인 — 무응답 30분이면 자동 마감되므로 가장 급하다. */
    LONG_SESSION("longSession"),
    /** 받은 오목 신청(TTL 60초). */
    GOMOKU_INVITE("gomokuInvite"),
    /** 받은 체스 신청 — 오목과 같은 급함, 오목 바로 뒤. */
    CHESS_INVITE("chessInvite"),
    /** 받은 테트리스 신청 — 체스 바로 뒤. */
    TETRIS_INVITE("tetrisInvite"),
    /** 지난주 회고(주 1회). */
    RETRO("retro"),
    /** 내 제보에 답장. */
    FEEDBACK_REPLY("feedbackReply"),
    /** 받을 생일 선물(닫기 없음). */
    CAKE_GIFT("cakeGift"),
    /** 새 버전 안내. */
    UPDATE("update"),
    /** 서버 공지 — 업데이트와 절대 같이 뜨지 않는다(가장 마지막). */
    APP_NOTICE("appNotice"),
}

/** 대결 신청 배너 한 장의 재료(오목·체스·테트리스 스토어의 표시 신청을 조립이 이 모양으로 옮긴다). */
data class DuelInviteBanner(val matchId: String, val peerName: String, val stake: Long, val expiresAt: SwiftDate)

/**
 * 배너 후보(전부 스토어가 끝내 둔 판정 결과). 이름은 맥 판정 줄의 재료 그대로:
 * [longSessionPrompt] = `store.isLongSessionPromptActive`(코틀린 `DesktopWorkSnapshot.longSessionPromptShownAt != null`),
 * [gomoku] = `store.gomoku.bannerInvite`, [chess]·[tetris] = `visibleIncoming`, [retroDue] = `showsRetroBanner`,
 * [feedbackReplyUnseen] = `showsFeedbackReplyBanner`, [cakeGiftOpen] = `showsCakeGiftCard`,
 * [updateAvailable] = `updateCheck.isUpdateAvailable`(데스크톱 `DesktopUpdateState.updateAvailable`), [appNotice] = `store.appNotice`(닫았으면 null).
 */
data class BannerCandidates(
    val isSignedIn: Boolean,
    val isTeamless: Boolean,
    val longSessionPrompt: Boolean = false,
    val gomoku: DuelInviteBanner? = null,
    val chess: DuelInviteBanner? = null,
    val tetris: DuelInviteBanner? = null,
    val retroDue: Boolean = false,
    val feedbackReplyUnseen: Boolean = false,
    val cakeGiftOpen: Boolean = false,
    val updateAvailable: Boolean = false,
    val appNotice: AppNotice? = null,
    /** Windows 기능 깃발(DesktopAppConfig.duels). 꺼짐이면 대결 신청 배너 셋은 후보가 아니다(W-3 #7 · W-6 #1). */
    val duelsEnabled: Boolean = false,
)

object BannerQueue {
    /** 맥 `isMainScreen`(130-133): 로그인 + 소속 팀 확정. 12시간 배너만 이것을 본다. */
    fun isMainScreen(c: BannerCandidates): Boolean = c.isSignedIn && !c.isTeamless

    /** 맥 `topBanner`(270-287)의 줄 순서 그대로. 업데이트만 로그인을 보지 않는다(283). */
    fun pick(c: BannerCandidates): TopBanner? {
        if (isMainScreen(c) && c.longSessionPrompt) return TopBanner.LONG_SESSION
        if (c.isSignedIn && c.duelsEnabled && c.gomoku != null) return TopBanner.GOMOKU_INVITE
        if (c.isSignedIn && c.duelsEnabled && c.chess != null) return TopBanner.CHESS_INVITE
        if (c.isSignedIn && c.duelsEnabled && c.tetris != null) return TopBanner.TETRIS_INVITE
        if (c.isSignedIn && c.retroDue) return TopBanner.RETRO
        if (c.isSignedIn && c.feedbackReplyUnseen) return TopBanner.FEEDBACK_REPLY
        if (c.isSignedIn && c.cakeGiftOpen) return TopBanner.CAKE_GIFT
        if (c.updateAvailable) return TopBanner.UPDATE
        if (c.isSignedIn && c.appNotice != null) return TopBanner.APP_NOTICE
        return null
    }

    /** 그 배너가 고른 대결 신청(오목·체스·테트리스 아니면 null). */
    fun duelInvite(banner: TopBanner?, c: BannerCandidates): DuelInviteBanner? = when (banner) {
        TopBanner.GOMOKU_INVITE -> c.gomoku
        TopBanner.CHESS_INVITE -> c.chess
        TopBanner.TETRIS_INVITE -> c.tetris
        else -> null
    }

    /** 그리는 자리(맥 466-531·551-579): 헤더 위 / 헤더 바로 위 형제 / 헤더 바로 아래. */
    enum class Slot { ABOVE_HEADER, HEADER_SIBLING, BELOW_HEADER }

    fun slotOf(banner: TopBanner): Slot = when (banner) {
        TopBanner.LONG_SESSION -> Slot.HEADER_SIBLING
        TopBanner.GOMOKU_INVITE, TopBanner.CHESS_INVITE, TopBanner.TETRIS_INVITE -> Slot.BELOW_HEADER
        TopBanner.RETRO, TopBanner.FEEDBACK_REPLY, TopBanner.CAKE_GIFT, TopBanner.UPDATE, TopBanner.APP_NOTICE -> Slot.ABOVE_HEADER
    }
}

/** 배너 문구(맥 원문). 줄 번호는 원본 자리. */
object BannerText {
    /** CheckMenuView.swift:488. */
    const val retroTitle = "지난주 근무 기록이 준비됐어요"
    /** CheckMenuView.swift:509. */
    const val feedbackReplyTitle = "제보에 답장이 왔어요"
    /** 회고·답장 [보기](490·510). */
    const val view = "보기"
    /** CheckMenuView.swift:1486(`새 버전 \(versionText)가 나왔어요`). */
    fun updateTitle(versionText: String): String = "새 버전 ${versionText}가 나왔어요"
    /** CheckMenuView.swift:389-392 — 버전 글자에 v 를 붙인다(이미 있으면 그대로). 없으면 맥 기본 "v0.3.0". */
    fun versionText(raw: String?): String {
        val v = raw ?: "v0.3.0"
        return if (v.startsWith("v") || v.startsWith("V")) v else "v$v"
    }
    /** 업데이트 [지금 업데이트](Windows 는 설치 관리자를 받는 길 하나). */
    const val updateNow = "지금 업데이트"
    /** GomokuPanel.swift:242 · ChessPanel.swift:122 · TetrisDuelPanel.swift:73. */
    fun duelInviteTitle(banner: TopBanner, name: String): String = when (banner) {
        TopBanner.CHESS_INVITE -> "${name}님이 체스 대결을 신청했어요"
        TopBanner.TETRIS_INVITE -> "${name}님이 테트리스 대결을 신청했어요"
        else -> "${name}님이 오목 대결을 신청했어요"
    }
    /** GomokuPanel.swift:245(오목) · ChessPanel.swift:123 · TetrisDuelPanel.swift:74(체스·테트리스). */
    fun duelInviteSubtitle(banner: TopBanner): String =
        if (banner == TopBanner.GOMOKU_INVITE) "수락하면 대결 창이 열려요" else "1분 안에 응답하세요"
    /** ChessPanel.swift:108 · TetrisDuelPanel.swift:62. */
    const val stakeLabel = "판돈"
    /** CheckCore/CharacterGift.swift:287-288. */
    const val cakeGiftTitle = "생일 선물이 도착했어요"
    const val cakeGiftButton = "고르기"
    /** GomokuPanel.swift:116-117 · 247. */
    const val accept = "수락"
    const val decline = "거절"
    const val dismiss = "닫기"
}
