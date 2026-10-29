// 원본: Sources/CheckMobileKit/Games/GamesText.swift(GomokuPhoneText 중 오목 스토어 타입에 기대는 함수) · Sources/CheckMobileKit/Games/GamesGomokuRankingText.swift · Sources/CheckMobileKit/Games/GamesGomokuAI.swift:139-186(GomokuPhoneMatchChrome 글자 몫) · Sources/CheckMobileKit/Games/GamesComponents.swift:154-170(관전 칩 문구) @ 3bd04bd
//
// 오목 화면 문구 중 **W2-e 표(core/stores …/games/GamesText.kt `GomokuPhoneText`)가 옮기지 못한 몫** — 그 표의 머리말이 "W2-d 스토어 타입에
// 기대는 함수(record · status · endReason · aiEndReason · livePair · opponentStatus · autoPlacedCount · cellAccessibility · boardAccessibility)는
// 병합 때 더한다"고 적어 둔 자리다. core/stores 의 games 패키지는 닫힌 갈래(조정자) 자리라 화면 갈래가 여기(ui/games/gomoku)에 둔다.
// 글자는 Swift 와 같은 문장이다(시험 GomokuScreenTextTest 가 손으로 적은 표로 잰다). 통합 때 GomokuPhoneText 로 접을 수 있다(보고).
package com.yehsung.aingcheck.ui.games.gomoku

import com.yehsung.aingcheck.core.rules.renju.GomokuBoard
import com.yehsung.aingcheck.core.rules.renju.GomokuColor
import com.yehsung.aingcheck.core.rules.renju.GomokuEndReason
import com.yehsung.aingcheck.core.rules.renju.GomokuForbiddenReason
import com.yehsung.aingcheck.core.rules.renju.GomokuOutcome
import com.yehsung.aingcheck.core.rules.renju.GomokuPoint
import com.yehsung.aingcheck.core.stores.games.GomokuPhoneText
import com.yehsung.aingcheck.core.stores.gomoku.GomokuLiveMatch
import com.yehsung.aingcheck.core.stores.gomoku.GomokuMatchState
import com.yehsung.aingcheck.core.stores.gomoku.GomokuMyRank
import com.yehsung.aingcheck.core.stores.gomoku.GomokuNoticeText
import com.yehsung.aingcheck.core.stores.gomoku.GomokuPhoneMatchChrome
import com.yehsung.aingcheck.core.stores.gomoku.GomokuRankEntry
import com.yehsung.aingcheck.core.stores.gomoku.GomokuRecord
import com.yehsung.aingcheck.core.stores.gomoku.GomokuUser
import com.yehsung.aingcheck.core.wire.SwiftDate

object GomokuScreenText {
    fun record(record: GomokuRecord?): String {
        if (record == null) return "전적 —"
        return "${record.wins}승 ${record.losses}패 ${record.draws}무"
    }

    /** 상대 행 상태 칩. 우선순위: 대국 중 > 업데이트 필요 > 근무 중/근무 안 함. */
    fun status(user: GomokuUser): String {
        if (user.inMatch) return "대국 중"
        if (!user.isCapable) return "업데이트 필요"
        return if (user.isWorking) "근무 중" else "근무 안 함"
    }

    fun endReason(reason: GomokuEndReason?, outcome: GomokuOutcome?): String = when (reason) {
        GomokuEndReason.five -> if (outcome == GomokuOutcome.won) "5목을 완성했어요" else "상대가 5목을 완성했어요"
        GomokuEndReason.timeout -> if (outcome == GomokuOutcome.won) "상대의 시간이 다 됐어요" else "시간이 다 됐어요"
        GomokuEndReason.resign -> if (outcome == GomokuOutcome.won) "상대가 기권했어요" else "기권했어요"
        GomokuEndReason.boardFull -> "판이 가득 찼어요 · 건 루비는 돌려받아요"
        GomokuEndReason.abandoned -> GomokuNoticeText.abandoned(outcome)
        null -> ""
    }

    /** AI 판 결과 이유(1:1 문구는 루비·"상대"를 말해 AI 판에 쓰지 않는다 — 맥 `aiEndReason` 과 같은 표). */
    fun aiEndReason(reason: GomokuEndReason?, outcome: GomokuOutcome?): String = when (reason) {
        GomokuEndReason.five -> if (outcome == GomokuOutcome.won) "5목을 완성했어요" else "AI가 5목을 완성했어요"
        GomokuEndReason.resign -> "기권했어요"
        GomokuEndReason.boardFull -> "판이 가득 찼어요"
        GomokuEndReason.abandoned -> GomokuNoticeText.abandoned(outcome)
        GomokuEndReason.timeout -> "시간이 다 됐어요"
        null -> ""
    }

    /** "민트별 · 달토끼". */
    fun livePair(live: GomokuLiveMatch): String = live.a.displayName + " · " + live.b.displayName

    /** 상대 행 부제(칩 대신 회색 글). 대국 중이면 누구와 두는지(로비의 대결 중 목록에서 찾는다). */
    fun opponentStatus(user: GomokuUser, liveMatches: List<GomokuLiveMatch>): String {
        if (user.inMatch) {
            val partner = liveMatches.firstOrNull { it.a.id == user.id || it.b.id == user.id }
                ?.let { if (it.a.id == user.id) it.b.displayName else it.a.displayName }
            return partner?.let { "대국 중 · $it${GomokuPhoneText.withParticle(it)}" } ?: "대국 중"
        }
        if (!user.isCapable) return GomokuPhoneText.needsUpdate
        return if (user.isWorking) "근무 중" else "근무 안 함"
    }

    fun autoPlacedCount(count: Int): String = "${GomokuNoticeText.autoPlacedStone} ${count}개"

    /** 칸 접근성("H8, 비어 있음"). 사실만 말한다 — 둘 수 있는지는 금수·차례 줄이 말한다. */
    fun cellAccessibility(
        point: GomokuPoint, stone: GomokuColor?, isLastMove: Boolean, isAuto: Boolean, forbidden: GomokuForbiddenReason?, isPreview: Boolean,
    ): String {
        val parts = mutableListOf(point.notation)
        when (stone) {
            GomokuColor.black -> parts.add("흑돌")
            GomokuColor.white -> parts.add("백돌")
            null -> when {
                isPreview -> parts.add("미리보기 돌 · 한 번 더 누르면 둬요")
                forbidden != null -> parts.add(GomokuPhoneText.reasonLabel(forbidden))
                else -> parts.add("비어 있음")
            }
        }
        if (stone != null && isLastMove) parts.add("마지막 수")
        if (stone != null && isAuto) parts.add(GomokuNoticeText.autoPlacedStone)
        return parts.joinToString(", ")
    }

    /** 판 전체 요약(접근성 머리). */
    fun boardAccessibility(match: GomokuMatchState, forbiddenCount: Int): String {
        var black = 0
        var white = 0
        for (y in 0 until GomokuBoard.size) for (x in 0 until GomokuBoard.size) {
            val point = GomokuPoint.at(x, y) ?: continue
            when (match.board[point]) {
                GomokuColor.black -> black += 1
                GomokuColor.white -> white += 1
                null -> Unit
            }
        }
        val parts = mutableListOf("오목판", "흑 ${black}개", "백 ${white}개")
        parts.add(match.lastMove?.let { "마지막 수 ${it.notation}" } ?: "아직 둔 돌이 없어요")
        if (match.isFinished) {
            parts.add("대국이 끝났어요")
        } else {
            parts.add(if (match.turn == match.myColor) GomokuPhoneText.myTurn else GomokuPhoneText.opponentTurn)
        }
        if (forbiddenCount > 0) parts.add("금수 자리 ${forbiddenCount}곳")
        return parts.joinToString(", ")
    }

    // MARK: 관전 입구 칩(GamesComponents.swift 의 `extension GomokuPhoneText` — 맥과 같은 낱말)

    const val watchChip: String = "관전"
    const val watchChipHint: String = "이 판을 지켜봐요"
    const val myMatchCaption: String = "내 판"
    const val watchSoonCaption: String = "곧 열려요"

    // MARK: 순위표(GamesGomokuRankingText.swift)

    const val rankTitle: String = "오목 순위"
    const val rankCaption: String = "승점 = 승 − 패"
    const val rankWholePeriod: String = "전체 기간"

    /** "10월 1일부터" — 컷은 서버가 정한 KST 자정이라 **KST 로 못 박는다**(기기 시간대로 조립하면 비KST 기기에서 하루 밀린다). */
    fun rankSince(date: SwiftDate): String {
        val kstSeconds = date.timeIntervalSince1970 + 9 * 3600
        val days = kotlin.math.floor(kstSeconds / 86_400.0).toLong()
        val (month, day) = civilMonthDay(days)
        return "${month}월 ${day}일부터"
    }

    /** 1970-01-01 기준 일수 → (월, 일)(그레고리력 — Howard Hinnant civil_from_days). */
    private fun civilMonthDay(daysSinceEpoch: Long): Pair<Int, Int> {
        val z = daysSinceEpoch + 719_468
        val era = (if (z >= 0) z else z - 146_096) / 146_097
        val doe = z - era * 146_097
        val yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365
        val doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        val mp = (5 * doy + 2) / 153
        val d = doy - (153 * mp + 2) / 5 + 1
        val m = if (mp < 10) mp + 3 else mp - 9
        return m.toInt() to d.toInt()
    }

    /** 승점의 부호 있는 짧은 꼴("+9" · "−3" · "0"). 음수 기호는 루비 변화와 같은 '−'(U+2212). */
    fun signedPoints(points: Long): String = when {
        points > 0 -> "+$points"
        points < 0 -> "−${-points}"
        else -> "0"
    }

    fun points(points: Long): String = "승점 ${signedPoints(points)}"

    /**
     * "6승 2패 1무".
     * INV-GamesGomokuRankingText-575cbfe0 이식: **승점만 띄우지 않는다**(사용자 지시). 순위 행과 내 순위 줄이 같은 이 표를 쓴다 —
     *   순위 행 컴포저블(GomokuRanking.kt)은 승점 아래 이 줄을 늘 같이 그린다.
     */
    fun record(wins: Long, losses: Long, draws: Long): String = "${wins}승 ${losses}패 ${draws}무"

    const val myRankTitle: String = "내 순위"
    const val outOfRank: String = "순위 밖"

    fun myRankLine(mine: GomokuMyRank): String {
        val record = record(mine.wins, mine.losses, mine.draws)
        val rank = mine.rank ?: return "$outOfRank · $record"
        return "${rank}위 · ${points(mine.points)} · $record"
    }

    const val noRanking: String = "아직 전적이 없어요"
    const val noRankingHint: String = "첫 판이 끝나면 순위가 올라와요"
    const val rankingUnavailable: String = "순위는 곧 열려요"
    const val rankingLoadFailed: String = "순위를 불러오지 못했어요"
    const val rankingLoadFailedHint: String = "계속 안 되면 앱을 업데이트해 주세요"
    const val rankCollapsedRows: Int = 5
    const val rankRowLimit: Int = 100

    fun rankSeeAll(total: Int): String = "전체 보기 · ${GomokuPhoneText.peopleCount(total)}"
    const val rankCollapse: String = "접기"

    fun rankRowAccessibility(entry: GomokuRankEntry, isMe: Boolean): String {
        val parts = mutableListOf("${entry.rank}위")
        if (isMe) parts.add(GomokuPhoneText.me)
        parts.add(entry.user.displayName)
        val center = entry.user.center
        if (!center.isNullOrEmpty()) parts.add("${center}센터")
        parts.add(points(entry.points))
        parts.add(record(entry.wins, entry.losses, entry.draws))
        return parts.joinToString(", ")
    }

    // MARK: 판 종류별 표의 글자 몫(GomokuPhoneMatchChrome — 판정 몫은 core/stores GamesGomokuAI.kt 가 쥔다)

    fun resignConfirmTitle(chrome: GomokuPhoneMatchChrome): String =
        if (chrome.isAI) GomokuPhoneText.aiResignConfirm else GomokuPhoneText.resignConfirm

    fun resignConfirmMessage(chrome: GomokuPhoneMatchChrome): String =
        if (chrome.isAI) GomokuPhoneText.aiNoRecord else GomokuPhoneText.resignConfirmMessage

    /** 판 아래 시계 안내. 사람 판은 서버 시계(앱을 나가도 흐른다), AI 판은 로컬 시계(떠나면 멈춘다). */
    fun clockLine(chrome: GomokuPhoneMatchChrome): String =
        if (chrome.isAI) GomokuPhoneText.aiClockPauses else GomokuPhoneText.clockRunsInBackground

    fun rematchTitle(chrome: GomokuPhoneMatchChrome): String = if (chrome.isAI) GomokuPhoneText.aiRematch else GomokuPhoneText.rematch

    fun waitingLine(chrome: GomokuPhoneMatchChrome, myColor: GomokuColor): String =
        if (chrome.isAI) GomokuPhoneText.stoneShort(myColor) + " · " + GomokuPhoneText.aiThinking else GomokuPhoneText.myWaitingLine(myColor)

    fun opponentSubtitle(chrome: GomokuPhoneMatchChrome, color: GomokuColor, isWorking: Boolean): String =
        if (chrome.isAI) GomokuPhoneText.stoneName(color) else GomokuPhoneText.playerSubtitle(color, isWorking)

    fun endReason(chrome: GomokuPhoneMatchChrome, reason: GomokuEndReason?, outcome: GomokuOutcome?): String =
        if (chrome.isAI) aiEndReason(reason, outcome) else endReason(reason, outcome)

    fun opponentLine(chrome: GomokuPhoneMatchChrome, name: String): String =
        if (chrome.isAI) GomokuPhoneText.aiOpponentLine else GomokuPhoneText.resultOpponent(name)

    // MARK: 안드로이드 몫(폰 iOS 에 없는 줄 — 뒤로가기 확인 · E:56)

    /** 사람과의 판이 흐르는 중에 뒤로가기 — "대국은 계속 흘러요" 확인(E§1.3 예측 뒤로가기 표). 폰 */
    const val leaveConfirmTitle: String = "대국 화면을 나갈까요?"
    const val leaveConfirmMessage: String = "나가도 대국은 계속 흘러요. 한 수 30초가 지나면 자동으로 놓이고, 세 번 놓치면 져요."
    const val leaveConfirm: String = "나가기"
    const val leaveCancel: String = "계속 두기"

    /** [도전] 단추의 보이스오버 힌트(Swift GamesGomokuScreen.swift:417 이 그 자리에 적은 문장 — 체스 짝은 `ChessPhoneText.challengeHint`). */
    fun challengeHint(name: String): String = "${name}님에게 판돈을 골라 신청해요"
}
