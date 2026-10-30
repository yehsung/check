// 원본: Sources/check/CheckMenuView.swift:1351-1396 @ a90d8623 (MenuBarDotReasons — 사유 여섯 OR, 보이스오버 글 순서 고정)
//       · :1298 (MenuBarStatusLabel.updateDotAccessibilityDescription "업데이트 있음") · CheckApp.swift:55-80 (점 사유 배선)
//       · W-windows-resume W-3 #7(대결 깃발 꺼짐 → 신청 안내 없음) · #14(운영자 미해결 신고 점은 Windows 1차 false)
//
// ★1 점은 하나다 — 사유가 몇 개든 같은 빨간 점(TrayIconSpec.redDot), 무엇 때문인지는 툴팁 글이 " · " 로 잇는다.
// ★2 글 순서 = 새 메시지 · 오목 신청 · 체스 신청 · 테트리스 신청 · 처리할 신고 · 업데이트 있음(선언 순서와 무관 — 맥 주석).
// ⚠️6 신청·메시지 점은 근무 여부를 보지 않는다(근무 밖에도 온다) — 그래서 이 값에는 근무 입력이 없다.
package com.yehsung.aingcheck.desktop.shell.tray

import com.yehsung.aingcheck.desktop.shellapi.DesktopUpdateState
import com.yehsung.aingcheck.feature.desktop.DesktopAppConfig

/** 트레이 빨간 점을 켜는 사유들(순수 값, 맥 MenuBarDotReasons 이식). */
data class TrayDotReasons(
    val unreadMessages: Boolean = false,
    val gomokuInvite: Boolean = false,
    val chessInvite: Boolean = false,
    val tetrisInvite: Boolean = false,
    val openReports: Boolean = false,
    val updateAvailable: Boolean = false,
) {
    val isEmpty: Boolean
        get() = !unreadMessages && !gomokuInvite && !chessInvite && !tetrisInvite && !updateAvailable && !openReports

    /** 켜진 사유들의 글(순서 고정, ★2). 하나도 없으면 null — 점이 없으니 설명할 것도 없다. */
    val accessibilityDescription: String?
        get() {
            val parts = mutableListOf<String>()
            if (unreadMessages) parts += UNREAD_MESSAGES_TEXT
            if (gomokuInvite) parts += GOMOKU_INVITE_TEXT
            if (chessInvite) parts += CHESS_INVITE_TEXT
            if (tetrisInvite) parts += TETRIS_INVITE_TEXT
            if (openReports) parts += OPEN_REPORTS_TEXT
            if (updateAvailable) parts += UPDATE_AVAILABLE_TEXT
            return if (parts.isEmpty()) null else parts.joinToString(SEPARATOR)
        }

    companion object {
        const val UNREAD_MESSAGES_TEXT = "새 메시지"
        const val GOMOKU_INVITE_TEXT = "오목 신청"
        const val CHESS_INVITE_TEXT = "체스 신청"
        const val TETRIS_INVITE_TEXT = "테트리스 신청"
        const val OPEN_REPORTS_TEXT = "처리할 신고"
        const val UPDATE_AVAILABLE_TEXT = "업데이트 있음"
        const val SEPARATOR = " · "

        /**
         * 스토어 값 → 사유. 대결 셋은 [DesktopAppConfig.duels] 가 켜졌을 때만(W-3 #7), 신고는 늘 false(W-3 #14 — Kotlin 신고 스토어 없음),
         * 업데이트는 [DesktopUpdateState.updateAvailable] 만 읽는다(shell.md §4-6).
         */
        fun of(
            flags: DesktopAppConfig,
            unreadMessageCount: Int,
            gomokuInvite: Boolean = false,
            chessInvite: Boolean = false,
            tetrisInvite: Boolean = false,
            update: DesktopUpdateState? = null,
        ): TrayDotReasons = TrayDotReasons(
            unreadMessages = unreadMessageCount >= 1,
            gomokuInvite = flags.duels && gomokuInvite,
            chessInvite = flags.duels && chessInvite,
            tetrisInvite = flags.duels && tetrisInvite,
            openReports = false,
            updateAvailable = update?.updateAvailable == true,
        )
    }
}
