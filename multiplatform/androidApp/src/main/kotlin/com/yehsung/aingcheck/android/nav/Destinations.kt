// 목적지 전부(E§3 화면 지도 — 시트 포함). 타입 안전 라우트(@Serializable)라 인자가 프로세스 죽음 뒤에도 저장 상태로 돌아온다.
// 화면 본문은 갈래 폴더의 자리표시(screens/<갈래>/Placeholder.kt)가 그리고, 화면 갈래(W3·W4·W5)가 자기 화면을 내면
// 조정자가 NavGraph.kt 의 그 줄을 바꾼다(K11).
//
// 대국 안 위젯(오목 채팅 서랍·체스 승격 시트·무승부 제안)은 화면 안 상태라 목적지가 아니다(E§3: 오목·체스·테트리스는 "한 화면 안 탭" —
// 자식 화면을 push 하면 화면이 사라져 폴링이 죽는다).
package com.yehsung.aingcheck.android.nav

import kotlinx.serialization.Serializable

object Dest {
    // ---- 세션 단계(E§3.1). 실행 중·업데이트 필요는 단계 화면이라 목적지가 아니다(셸이 직접 그린다) ----
    @Serializable data object SessionGraph
    @Serializable data object Login
    @Serializable data object SignUp
    @Serializable data object PasswordReset

    // ---- 탭: 지금 ----
    @Serializable data object NowGraph
    @Serializable data object NowHome
    @Serializable data object TeamGoalSheet
    @Serializable data object TeamJoinSheet

    // ---- 탭: 메시지 ----
    @Serializable data object MessagesGraph
    @Serializable data object MessagesList
    @Serializable data class Conversation(val peerId: String)
    @Serializable data object NewConversationSheet
    @Serializable data object MegaphoneSheet
    /** 신고(대화 ⋮ · 받은 말풍선 길게 누르기 · 오목 채팅 서랍 ⋮ — 세 입구가 같은 시트). [subjectId] = 신고 대상(사람 또는 메시지). */
    @Serializable data class ReportSheet(val subjectId: String)
    @Serializable data class BlockConfirm(val peerId: String)

    // ---- 탭: 순위 ----
    @Serializable data object RankingsGraph
    /** 세그먼트 셋(league·tokens·minigame) — RankingsBoard.raw. */
    @Serializable data class RankingsHome(val board: String = "league")

    // ---- 탭: 게임 ----
    @Serializable data object GamesGraph
    @Serializable data object GamesHome
    /** AingMiniGame.raw(timing·flappy·tetris). */
    @Serializable data class MiniGame(val game: String)
    /** 오목 한 화면(로비·신청·대국·관전·순위·AI 를 화면 안 탭으로). [section] = GameSection.raw. */
    @Serializable data class Gomoku(val section: String, val matchId: String? = null)
    /** 체스 한 화면(오목과 같은 구조, 로봇 포함). */
    @Serializable data class Chess(val section: String, val matchId: String? = null)
    /** 테트리스 1:1(로비·대결·결과 한 화면). */
    @Serializable data object TetrisDuel
    /** 판돈 고르기(오목·체스·테트리스 — 판돈 목록은 서버값). [game] = gomoku·chess·tetris. */
    @Serializable data class StakeSheet(val game: String)

    // ---- 탭: 나 ----
    @Serializable data object MeGraph
    @Serializable data object MeHome
    @Serializable data object Shop
    @Serializable data object GachaOddsSheet
    @Serializable data object GachaMachine
    @Serializable data object CharacterPicker
    @Serializable data object Profile
    /** null = 제보 목록. */
    @Serializable data class Feedback(val reportId: String? = null)
    @Serializable data object Settings
    @Serializable data object BlockedPeople
    @Serializable data object AccountDeletion
    /** 잔디 상세(축: work·tokens …). */
    @Serializable data class GrassDetail(val axis: String)
    /** 미션(iOS MeDestination.missions — 딥링크 없음, 7차 조립 K11 · W4-c MissionsRoute). */
    @Serializable data object Missions

    // ---- 공통 ----
    @Serializable data object NotificationPrimerSheet
}

/** 오목·체스 화면 안 탭(목적지 인자). */
enum class GameSection(val raw: String) {
    LOBBY("lobby"),
    INVITE("invite"),
    MATCH("match"),
    WATCH("watch"),
    RANKING("ranking"),
    AI("ai"),
}
