// 원본: Sources/CheckMobileKit/Games/GamesChessMatch.swift:1-297(GamesChessMatchTint · GamesChessMatchLine · GamesChessMatchChrome — 플랫폼 무관 화면 표) @ 3bd04bd
//
// 폰 1:1 체스 대국 화면이 그리는 것을 **값으로** 내놓는 표. 돈이 갈리는 화면이라 판정이 들어가는 자리는 전부 여기 둔다 — Compose 는 이 표를 배치만 한다
// (데스크톱 JVM 시험 ChessMatchChromeTest 가 값으로 잰다).
//
// 지키는 계약(Swift 머리 그대로):
//  ① 시계는 서버가 쥔다 — 화면은 한 번도 세지 않는다(시간 상수도 베끼지 않는다: 총시간은 로비 `initialMs`, 가산은 이 판 행의 `incrementMs`).
//  ② 유예는 판·사람당 1회 예산 — 판정은 `ChessMatchState.isFlagOverdue` 하나(부등호도 서버와 같은 `>`).
//  ③ FIDE 6.9 — `timeout`(패)과 `timeout_insufficient`(무)는 다른 문장(결과 표에 else 를 쓰지 않는다 — 문구 표가 갈래마다 쥔다).
//  ④ 합법 수를 클라가 만들지 않는다(`match.legalMoves` 한 칸 — 화면에 `ChessRules` 가 안 나온다).
//  ⑤ 승격은 2단(코어 `promotion` 이 섰는지만 본다).  ⑦ 착수 재시도 단추가 없다(`expected_ply` 를 두 번 보내면 둘째는 stale — 입구는 탭과 승격뿐).
//  ⑧ INV-GamesChessMatch-3821e15e 이식: **낙관적 표시가 없다.** 판은 `match.position`(서버가 확인한 국면)만 그리고 내 수는 응답이 와야 미끄러진다(0.1~0.3초).
//     사용자 결정이 필요한 자리다 — 넣으면 서버가 확인하지 않은 판을 보여 준다(이 갈래는 넣지 않는다).
package com.yehsung.aingcheck.ui.games.chess

import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.rules.chess.ChessColor
import com.yehsung.aingcheck.core.rules.chess.ChessSquare
import com.yehsung.aingcheck.core.rules.duel.DuelFee
import com.yehsung.aingcheck.core.stores.chess.ChessMatchOutcome
import com.yehsung.aingcheck.core.stores.chess.ChessMatchState
import com.yehsung.aingcheck.core.stores.chess.ChessPhoneText
import com.yehsung.aingcheck.core.stores.chess.ChessPromotionPrompt
import com.yehsung.aingcheck.core.stores.chess.GamesChessBoardMetrics
import com.yehsung.aingcheck.core.stores.chess.GamesChessCheckMark
import com.yehsung.aingcheck.core.stores.gomoku.BoardSize
import com.yehsung.aingcheck.core.wire.SwiftDate

/** 표가 말하는 색의 **뜻**(토큰은 화면이 고른다). */
enum class ChessMatchTint { good, bad, warn, quiet }

/** 글자 한 줄 + 그 뜻. */
data class ChessMatchLine(val text: String, val tint: ChessMatchTint)

data class ChessMatchChrome(
    val isRobotMatch: Boolean,
    val showsStake: Boolean,
    val stake: Long,
    val stakeSuffix: String?,
    val actionRow: ActionRow,
    /** 승격 시트가 떠 있는가 — **코어가 2단을 판정한다**(도착 칸이 같은 합법 수가 넷). 여기서 다시 세지 않는다. */
    val showsPromotionSheet: Boolean,
    val statusLine: ChessMatchLine?,
    val drawsBoard: Boolean,
    /** 내 색이 아래인가(체스는 내 색이 아래여야 읽힌다 — 관전은 백 아래, 다른 화면이다). */
    val whiteAtBottom: Boolean,
    /**
     * 체크 덮개가 설 칸.
     * INV-GamesChessMatch-ab912f59 이식: 문구(`turnLine` 의 inCheck)와 **같은 값**(`match.isInCheck`)에서 나온다 — 체스에서 체크는 글자로만 말하면 안 되는
     *   정보다(왕이 어디서 맞고 있는지 판에서 보여야 한다). 규칙을 돌리지 않는다(칸은 배치에서 읽는다 — GamesChessCheckMark).
     */
    val checkSquare: ChessSquare?,
    val plyLine: String,
    /**
     * 시간 규칙 + "앱을 나가도 차례 시간은 흘러요".
     * INV-GamesChessMatch-f500266d 이식: 숫자는 **서버가 준 값**에서 조립한다(총시간 로비 `initialMs` · 가산 행의 `incrementMs` — 10-12 에 5분이 10분으로 늘었다).
     */
    val clockLine: String,
    val result: Result?,
) {
    sealed interface ActionRow {
        data class playing(val canOfferDraw: Boolean, val canResign: Boolean) : ActionRow
        data object answerDrawOffer : ActionRow
        data class finished(val showsPlayAgain: Boolean) : ActionRow
    }

    data class Result(
        val title: String,
        /** 끝난 이유. INV-GamesChessMatch-9b402764 이식: `timeout`(패)과 `timeout_insufficient`(FIDE 6.9 무승부)가 **다른 문장**이다(문구 표가 갈래마다 쥔다). */
        val reason: String,
        val tint: ChessMatchTint,
        val rubyDelta: Long,
        val rubyDeltaText: String,
        /** 로봇 판은 루비를 안 그린다(±0 은 걸었다가 돌려받은 것처럼 읽힌다). */
        val showsRubyDelta: Boolean,
        val rubyNote: String?,
        val isDraw: Boolean,
    )

    companion object {
        /** [기권]을 화면이 뜬 직후에는 받지 않는다(오목 `GomokuPhoneResignGuard` 와 같은 1초). */
        const val RESIGN_ARM_DELAY: Double = 1.0

        fun acceptsResignTap(shownAt: SwiftDate?, now: SwiftDate): Boolean {
            if (shownAt == null) return true
            return now.timeIntervalSince(shownAt) >= RESIGN_ARM_DELAY
        }

        fun make(match: ChessMatchState, promotion: ChessPromotionPrompt?, notice: String?, isBusy: Boolean, isRobotMatch: Boolean, initialMs: Long): ChessMatchChrome {
            val actionRow: ActionRow = when {
                match.isFinished -> ActionRow.finished(showsPlayAgain = isRobotMatch)
                match.drawOfferedByOpponent -> ActionRow.answerDrawOffer
                // 로봇 판에는 무승부 제안이 없다(합의할 상대가 없다 — 서버 왕복이 아예 안 나간다).
                else -> ActionRow.playing(canOfferDraw = !isRobotMatch && !isBusy && !match.drawOfferedByMe, canResign = !isBusy)
            }
            val statusLine: ChessMatchLine? = when {
                notice != null -> ChessMatchLine(notice, ChessMatchTint.warn)
                !match.isFinished && match.drawOfferedByOpponent -> ChessMatchLine(ChessPhoneText.drawOfferedByOpponent, ChessMatchTint.warn)
                !match.isFinished && match.drawOfferedByMe -> ChessMatchLine(ChessPhoneText.drawOfferedByMe, ChessMatchTint.quiet)
                match.position == null -> ChessMatchLine(ChessPhoneText.unreadableBoard, ChessMatchTint.warn)
                else -> null
            }
            return ChessMatchChrome(
                isRobotMatch = isRobotMatch,
                showsStake = !isRobotMatch,
                stake = match.stake,
                stakeSuffix = if (isRobotMatch) null else ChessPhoneText.stakeGainSuffix(match.stake),
                actionRow = actionRow,
                showsPromotionSheet = promotion != null,
                statusLine = statusLine,
                drawsBoard = match.position != null,
                whiteAtBottom = match.myColor == ChessColor.white,
                checkSquare = GamesChessCheckMark.square(match.isInCheck, match.isFinished, match.turn, match.position),
                plyLine = ChessPhoneText.plyLine(match.plyCount),
                clockLine = ChessPhoneText.clockPhrase(initialMs, match.clock.incrementMs) + " · " + ChessPhoneText.clockRunsInBackground,
                result = if (match.isFinished) makeResult(match, isRobotMatch) else null,
            )
        }

        private fun makeResult(match: ChessMatchState, isRobotMatch: Boolean): Result {
            // 승자 순이익 = DuelFee.winnerNet(v0.3.64 부터 수수료 0 → +판돈). 서버가 값을 주면 그 값이 이긴다.
            val delta = match.rubyDelta ?: when (match.outcome) {
                ChessMatchOutcome.won -> DuelFee.winnerNet(match.stake.toInt()).toLong()
                ChessMatchOutcome.lost -> -match.stake
                else -> 0L
            }
            val isDraw = match.outcome == ChessMatchOutcome.draw
            val tint = when (match.outcome) {
                ChessMatchOutcome.won -> ChessMatchTint.good
                ChessMatchOutcome.lost -> ChessMatchTint.bad
                else -> ChessMatchTint.quiet
            }
            // 환불 한 줄은 **무승부일 때만**이고 로봇 판에는 없다(걸린 루비가 없다 — 대신 "기록 없음").
            val note = when {
                isRobotMatch -> ChessPhoneText.robotNoRecord
                isDraw && match.stake > 0 -> ChessPhoneText.drawRefund(match.stake)
                else -> null
            }
            // 로봇 판은 **다른 표**를 쓴다(루비·'상대' 어휘가 없다).
            val reason = if (isRobotMatch) ChessPhoneText.robotEndReason(match.endReason, match.outcome) else ChessPhoneText.endReason(match.endReason, match.outcome)
            return Result(
                title = ChessPhoneText.outcomeTitle(match.outcome), reason = reason, tint = tint,
                rubyDelta = delta, rubyDeltaText = ChessPhoneText.rubyDelta(delta), showsRubyDelta = !isRobotMatch, rubyNote = note, isDraw = isDraw,
            )
        }

        /**
         * 차례 한 줄 — 잎(시간을 받는 자리)에서만 부른다.
         * INV-GamesChessMatch-b56d24f0 이식: 깃발 판정은 `ChessMatchState.isFlagOverdue(now, graceSeconds)` **하나뿐**이다 — 그 함수가 그 사람의 남은 유예 예산을
         *   먼저 쓰고 부등호도 서버와 같다. [graceSecondsFallback](로비 전역 grace)은 서버가 그 칸을 안 줬을 때만 쓰는 폴백이다 — 여기서 손으로 비교하면
         *   예산을 다 쓴 사람의 판이 서버에서 끝났는데 화면이 최대 2초를 더 "상대 차례 · 0.0"으로 그린다.
         */
        fun turnLine(match: ChessMatchState, now: SwiftDate, graceSecondsFallback: Double, isRobotThinking: Boolean = false): ChessMatchLine {
            if (match.isFinished) {
                return ChessMatchLine(ChessPhoneText.outcomeTitle(match.outcome), when (match.outcome) {
                    ChessMatchOutcome.won -> ChessMatchTint.good
                    ChessMatchOutcome.lost -> ChessMatchTint.bad
                    else -> ChessMatchTint.quiet
                })
            }
            if (match.isFlagOverdue(now, graceSecondsFallback)) return ChessMatchLine(ChessPhoneText.flagSettling, ChessMatchTint.warn)
            if (isRobotThinking) return ChessMatchLine(ChessPhoneText.robotThinking, ChessMatchTint.quiet)
            if (match.isInCheck) return ChessMatchLine(if (match.isMyTurn) ChessPhoneText.inCheck else ChessPhoneText.opponentInCheck, ChessMatchTint.bad)
            return if (match.isMyTurn) ChessMatchLine(ChessPhoneText.myTurn, ChessMatchTint.good) else ChessMatchLine(ChessPhoneText.opponentTurn, ChessMatchTint.quiet)
        }

        /** 시계 한 칸의 글자·뜻 — 값을 세지 않는다(서버 네 칸에서 파생한 초를 글자로만). 10초 이하 빨강 · 30초 이하 앰버. */
        fun clockFace(seconds: Double, isTurn: Boolean): ChessMatchLine {
            val tint = when {
                !isTurn -> ChessMatchTint.quiet
                seconds <= 10 -> ChessMatchTint.bad
                seconds <= 30 -> ChessMatchTint.warn
                else -> ChessMatchTint.good
            }
            return ChessMatchLine(ChessPhoneText.clock(seconds), tint)
        }

        /** 판 한 변을 **글자가 커질 때만**(높이가 좁을 때만) 줄인다 — 기본 글자에서는 판 레인 값을 한 픽셀도 건드리지 않는다. */
        fun boardSide(laneDefault: Dp, visibleHeight: Dp, isLargeText: Boolean, isAccessibilitySize: Boolean): Dp {
            if (!isLargeText || visibleHeight <= 0.dp) return laneDefault
            val fraction = if (isAccessibilitySize) 0.40f else 0.52f
            return maxOf(240.dp, minOf(laneDefault, visibleHeight * fraction))
        }

        /**
         * 판 레인(`GamesChessBoardMetrics.side`)에 넘기는 예산 — 화면 크기에서 **열 좌우 여백을 뺀 폭**.
         * INV-GamesChessMatch-32d7075b 이식: 여기서 빼지 않으면 판 한 변이 "화면 폭"으로 정해져 판이 열을 벌리고, 같은 열의 자식 전부(결과 카드 · 사람 카드 ·
         *   시계)가 함께 오른쪽으로 넘친다(402pt 실측: 판 오른쪽 모서리가 화면 밖 14pt).
         * INV-GamesChessMatch-c90593fa 이식: 식으로도 **늘** 넘친다 — 넘치는 양은 `floor(W/8)*8 − W + 2·sideMargin` 이고 8의 배수 내림 때문에 모든 폭에서 10~16pt 다.
         * INV-GamesChessMatch-4cf27e8d 이식: 큰 글자에서만 판이 줄어 잘림이 사라졌다 — **기본 글자 전용** 결함이었고 그래서 재는 자리가 여기다(시험이 기본 폭으로 잰다).
         */
        fun boardBudget(width: Dp, height: Dp, sideMargin: Dp): BoardSize =
            BoardSize(width = maxOf(0.0, (width - sideMargin * 2).value.toDouble()), height = height.value.toDouble())

        /** 판이 열보다 넓어질 수 없다(열 폭이 0 이면 첫 배치 한 틱 — 자르지 않는다). */
        fun cagedSide(side: Dp, columnWidth: Dp): Dp = if (columnWidth <= 0.dp) side else minOf(side, columnWidth)

        /** 판 한 변(판 레인 → 큰 글자 줄임 → 열 가둠). */
        fun side(width: Dp, height: Dp, sideMargin: Dp, isLargeText: Boolean, isAccessibilitySize: Boolean): Dp {
            val budget = boardBudget(width, height, sideMargin)
            val lane = GamesChessBoardMetrics.side(budget).dp
            return cagedSide(boardSide(lane, height, isLargeText, isAccessibilitySize), budget.width.dp)
        }
    }
}
