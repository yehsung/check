// 원본: Sources/CheckMobileKit/Games/GamesTetrisDuelMatch.swift:1-325(GamesTetrisDuelTone · GamesTetrisDuelChrome · GamesTetrisDuelTouch) @ 1b8260d
package com.yehsung.aingcheck.core.stores.tetris

import com.yehsung.aingcheck.core.rules.duel.DuelFee
import com.yehsung.aingcheck.core.rules.minigame.MiniGamePoint
import com.yehsung.aingcheck.core.rules.minigame.MiniGameSize
import com.yehsung.aingcheck.core.rules.tetris.TetrisLayout
import com.yehsung.aingcheck.core.stores.games.TetrisGestureStep
import com.yehsung.aingcheck.core.stores.games.TetrisGestureThresholds
import com.yehsung.aingcheck.core.stores.games.TetrisGestureTracker
import com.yehsung.aingcheck.core.wire.SwiftDate
import kotlin.math.ceil

// 폰 1:1 테트리스 **대결 화면**의 판정 몫(맥 `TetrisDuelPanel` 의 대결 절 · 폰 체스 문법). 단계는 넷이다: 준비 대기 → 카운트다운 3·2·1 → 판 →
// 결과 카드. 단계를 정하는 것은 코어(`store.tetris.phase`)이고 화면(W4-b)은 **그리기와 손가락 전달**만 한다.
//
// ── 지키는 계약 ──
//  ① INV-GamesTetrisDuelMatch-73ec0105 이식: **판(`store.tetris.duel`)은 관찰 대상이 아니다**(Compose 상태가 아니다 — TetrisDuelStore 머리말 ⑦).
//     프레임마다 바뀌는 값이라 관찰하면 그 값을 읽는 모든 화면이 매 걸음 무효화된다. 판 칸·떨어지는 조각을 읽는 자리는 화면의 프레임 루프
//     안 하나뿐이고, 조각이 굳을 때만 바뀌는 숫자는 관찰 가능한 `store.tetris.myStats` 로 읽는다.
//  ② 프레임 루프는 화면이 보일 때만 돈다. 판은 화면과 무관하게 스토어의 판 루프가 0.05초로 민다(D10).
//  ③ 시간을 읽는 자리는 잎 셋뿐이다(경과 시계 · 준비 남은 초 · 상대 침묵) — 아래 `GamesTetrisDuelChrome` 의 정적 순수 함수.
//  ④ INV-GamesTetrisDuelMatch-8e645457 이식: **"판 중에 앱을 나가면 져요" 는 판 위에 늘 있다**(P7 · [GamesTetrisDuelChrome.showsLeaveWarning]).
//     규칙 시트에만 두면 안 된다 — OS 가 앱을 멈추면 판 루프가 멎고 서버는 15초 침묵에 그쪽 패로 닫으며(D5), 돌아오면 따라잡기가 30초까지만
//     돈다. 그래서 판을 멈추거나 시계를 되감지 않는다(D10). 화면이 말하는 것이 유일한 방어다.
//  ⑤ 하드드롭에 제스처를 주지 않는다(P9). 끌기·탭은 `TetrisGestureTracker`(순수)가 판정하고, 엔진에 한 칸을 먹이는 길은 코어 문 셋뿐이다.
//  ⑥ 조작 버튼에 확인 대화상자를 넣지 않는다. **기권만** 확인을 받는다(판돈을 잃는다).
//  ⑦ 판돈·전적·루비는 서버가 말한 값만 쓴다. 결과 카드의 사유는 코어 표이고 루비 증감은 `match.rubyDelta`(없으면 `DuelFee` 로 같은 식)다.

/** 화면 표가 말하는 색. 화면 칠(W4-b)이 토큰으로 옮긴다 — 이 표에는 **뜻만** 둔다. */
enum class GamesTetrisDuelTone {
    /** 초록 — 이김 · 내가 보낸 공격. */
    good,

    /** 빨강 — 짐 · 꼭대기 · 들어올 줄. */
    bad,

    /** 앰버 — 기다림 · 가속 · 연결 확인 중. */
    warn,

    /** 회색 — 무승부 · 보조. */
    quiet,
}

/**
 * 대결 화면이 그리는 것을 **값으로** 내놓는 표. 화면은 이 표를 배치만 한다.
 * 시간에 따라 매초 바뀌는 값(경과 초 · 준비 남은 초 · 상대 침묵)은 **여기 들어오지 않는다** — 잎이 아래 정적 순수 함수로 센다(계약 ③).
 */
class GamesTetrisDuelChrome(
    match: TetrisDuelMatchState, phase: TetrisDuelPhase, myStats: TetrisDuelMyStats?, notice: String?, connectionTrouble: Boolean,
) {
    /** 지금 어느 단계인가(코어 흐름에서 왔고 `.lobby` 는 이 화면이 뜨지 않는 단계다). */
    enum class Stage { waiting, countdown, playing, finished }

    /** 끝난 판 한 장. */
    data class Result(
        /** 이겼어요 / 졌어요 / 무승부예요. */
        val title: String,
        /** 끝난 이유(코어 표 — 맥과 같은 문장). */
        val reason: String,
        /** 이 판으로 내 루비가 변한 양. 서버가 말한 값이 있으면 그것이고, 없으면 승패에서 같은 식으로 센다. */
        val rubyDelta: Int,
        val rubyDeltaText: String,
        val tone: GamesTetrisDuelTone,
        val isDraw: Boolean,
    )

    val stage: Stage
    val stake: Int = match.stake

    /** "5 · 이기면 +5" — 이기면 받는 **순이익**(결과 카드의 루비와 같은 숫자다). */
    val stakeLine: String = TetrisPhoneText.stakeLine(match.stake)

    /** 내가 꼭대기에 닿았다 — 판 위 덮개가 서고 입력이 끊긴다. */
    val toppedOut: Boolean = myStats?.toppedOut ?: false

    /**
     * INV-GamesTetrisDuelMatch-4170dbba 이식: 화면이 손가락·버튼을 엔진으로 보내는가. 준비·카운트다운·탑아웃·끝에서는 거짓이다.
     *   코어(`TetrisDuelSession.isLive`)가 이미 막지만 **화면도 눌림을 안 보내는 쪽**이 맞다 — 보내는 화면은 막는 쪽이 한 줄 바뀌면 조용히 되살아난다.
     */
    val acceptsInput: Boolean

    /** INV-GamesTetrisDuelMatch-6a8f1c81 이식: 판 위에 늘 보이는 경고(P7 · 계약 ④). 끝난 판에서만 내린다(그때는 나가도 잃을 것이 없다). */
    val showsLeaveWarning: Boolean

    /** 2분이 지나 가속이 걸렸다(D7 — 레벨 바닥이 1 을 넘었다). 끝난 판에서는 내린다. */
    val showsSpeedUp: Boolean

    /** 가속 바닥(표시용 — 10초마다 오른다). */
    val speedLevel: Int

    /** 내 보고가 연달아 실패하는 중(= 내 연결). */
    val connectionTrouble: Boolean

    /** 상대 판 숫자 셋(스냅숏 — 보고 응답에서만 바뀐다). */
    val opponentLines: Int = match.opponentBoard.lines
    val opponentAttack: Int = match.opponentBoard.attackSent
    val opponentPending: Int = match.opponentBoard.pending
    val opponentName: String = match.opponent.displayName

    /** 상대가 꼭대기에 닿았다(미니 판 위 글자). */
    val opponentToppedOut: Boolean = match.opponentBoard.toppedOut

    /** [기권] 을 그리는가. **카운트다운 중에도 참이다**(서버가 받는다 — D4 뒤의 판은 이미 판돈을 걷었다). */
    val canResign: Boolean
    val result: Result?

    /** 안내 한 줄(코어 `notice` — 신청·기권 응답 문구). 없으면 null. */
    val notice: String? = notice

    init {
        val finished = match.isFinished || phase == TetrisDuelPhase.finished
        stage = when (phase) {
            TetrisDuelPhase.playing -> if (finished) Stage.finished else Stage.playing
            TetrisDuelPhase.countdown -> if (finished) Stage.finished else Stage.countdown
            TetrisDuelPhase.ready -> if (finished) Stage.finished else Stage.waiting
            // `.lobby` 로 떨어지는 길은 실질적으로 없다(이 화면은 판이 있을 때만 선다) — 떨어지면 끝난 판으로 읽는다.
            TetrisDuelPhase.finished, TetrisDuelPhase.lobby -> Stage.finished
        }
        // INV-GamesTetrisDuelMatch-29bd9a0f 이식: 입력은 **판이 흐르는 동안만**이다. 탑아웃한 판은 서버 응답을 기다리는 중이고 조각이 없다.
        acceptsInput = stage == Stage.playing && !(myStats?.toppedOut ?: false)
        showsLeaveWarning = stage != Stage.finished
        val floor = myStats?.levelFloor ?: 1
        showsSpeedUp = floor > 1 && stage != Stage.finished
        speedLevel = floor
        this.connectionTrouble = connectionTrouble && stage != Stage.finished
        canResign = stage != Stage.finished
        result = if (finished) result(match) else null
    }

    /** 판 위 덮개가 설 자리인가 — 준비·카운트다운·탑아웃·결과. 판이 흐르는 동안에는 아무것도 덮지 않는다. */
    val showsBoardOverlay: Boolean
        get() = when (stage) {
            Stage.waiting, Stage.countdown, Stage.finished -> true
            Stage.playing -> toppedOut
        }

    override fun equals(other: Any?): Boolean =
        other is GamesTetrisDuelChrome && other.stage == stage && other.stake == stake && other.stakeLine == stakeLine &&
            other.acceptsInput == acceptsInput && other.showsLeaveWarning == showsLeaveWarning && other.showsSpeedUp == showsSpeedUp &&
            other.speedLevel == speedLevel && other.connectionTrouble == connectionTrouble && other.opponentLines == opponentLines &&
            other.opponentAttack == opponentAttack && other.opponentPending == opponentPending && other.opponentName == opponentName &&
            other.opponentToppedOut == opponentToppedOut && other.toppedOut == toppedOut && other.canResign == canResign &&
            other.result == result && other.notice == notice

    override fun hashCode(): Int = stage.hashCode() * 31 + stake

    companion object {
        /** 상대 보고가 이만큼 끊기면 "상대 연결 확인 중" 을 띄운다(서버 침묵 판정 15초의 1/3 — 맥과 같은 값이다). */
        const val opponentSilenceHintSeconds: Double = 5.0

        /** 준비 마감을 모를 때 보여 줄 기본 남은 초(서버 `tetris_ready_timeout_seconds()`). */
        const val readyTimeoutSeconds: Int = 30

        /**
         * 상대 미니 판 한 칸(pt). **여기 있는 까닭**: 이 수가 판 폭을 깎고 판 폭이 곧 제스처 한 칸 문턱이다(P11) — 화면에만 두면 아무도 안 재는
         * 수가 된다. 5pt → 54×104(칸 4pt · 여백 10%) — 작은 화면 판 폭이 343 → 304pt(−11%)로만 줄어든다.
         */
        const val miniBoardCell: Double = 5.0

        /** 미니 판이 머리글에서 먹을 수 있는 세로 상한(pt). 이 선을 넘으면 판이 300pt 아래로 깎인다. */
        const val miniBoardHeightBudget: Double = 110.0

        /** 끝난 판 한 장(순수). 사유는 **코어 표**이고 루비는 서버 값 우선이다(계약 ⑦). */
        fun result(match: TetrisDuelMatchState): Result {
            val outcome = match.outcome
            val delta = match.rubyDelta ?: when (outcome) {
                TetrisDuelOutcome.won -> DuelFee.winnerNet(match.stake)
                TetrisDuelOutcome.lost -> -match.stake
                TetrisDuelOutcome.draw, null -> 0
            }
            val tone = when (outcome) {
                TetrisDuelOutcome.won -> GamesTetrisDuelTone.good
                TetrisDuelOutcome.lost -> GamesTetrisDuelTone.bad
                TetrisDuelOutcome.draw, null -> GamesTetrisDuelTone.quiet
            }
            return Result(
                title = TetrisPhoneText.outcomeTitle(outcome),
                reason = TetrisDuelNoticeText.endReason(match.endReason, outcome),
                rubyDelta = delta, rubyDeltaText = TetrisPhoneText.rubyDelta(delta),
                tone = tone, isDraw = outcome == TetrisDuelOutcome.draw,
            )
        }

        /** 판 그림의 보이스오버 한 줄. **느린 값만**(지운 줄 · 들어올 줄) — 조각·행·열은 읽어 주는 동안 이미 틀린 값이 된다. */
        fun boardAccessibility(lines: Int, pendingGarbage: Int): String =
            "${TetrisPhoneText.myBoardLabel}, ${TetrisPhoneText.linesTitle} $lines, ${TetrisPhoneText.incomingLinesTitle} $pendingGarbage"

        // MARK: 시간을 읽는 셋 — **잎 전용**(계약 ③)

        /** 판 시계가 보여 줄 경과초. 끝난 판은 **엔진에 흘린 판 시간**에서 멈춘다 — 단조 시계로 재면 결과 화면에서도 경과가 계속 자란다. */
        fun elapsedSeconds(stage: Stage, matchElapsed: Double?, simulated: Double?): Double {
            if (stage == Stage.finished) return maxOf(0.0, simulated ?: 0.0)
            return maxOf(0.0, matchElapsed ?: 0.0)
        }

        /** 카운트다운 숫자(3·2·1). 남은 초를 **올림**해서 1 아래로 안 내려간다 — 0 을 보여 주면 "시작했는데 안 움직인다"가 된다. */
        fun countdownDigit(remaining: Double?): Int = maxOf(1, ceil(remaining ?: 0.0).toInt())

        /** 준비 마감까지 남은 초. 마감을 모르면 서버 기본값(30). */
        fun readySecondsLeft(deadline: SwiftDate?, now: SwiftDate): Int {
            if (deadline == null) return readyTimeoutSeconds
            return maxOf(0, ceil(deadline.timeIntervalSince(now)).toInt())
        }

        /** 상대 보고가 끊겼는가. 끝난 판·아직 준비 전인 상대는 **침묵이 아니다**(그때는 할 말이 따로 있다). */
        fun opponentIsSilent(silenceSeconds: Double?, opponentReady: Boolean, stage: Stage): Boolean {
            if (stage == Stage.finished || !opponentReady) return false
            return (silenceSeconds ?: 0.0) >= opponentSilenceHintSeconds
        }

        /** 상대 상태 한 줄. "준비 완료" 는 판이 서기 전까지만 — 판 중·끝난 뒤에도 남으면 상대가 아직 안 들어온 것처럼 읽힌다. */
        fun opponentStatus(board: TetrisDuelOpponentBoard, stage: Stage): String {
            if (board.toppedOut) return TetrisPhoneText.toppedOutTitle
            if (!board.ready) return TetrisPhoneText.notReady
            return when (stage) {
                Stage.finished -> TetrisPhoneText.finishedPresence
                Stage.playing -> TetrisPhoneText.playingNow
                Stage.waiting, Stage.countdown -> TetrisPhoneText.ready
            }
        }
    }
}

/**
 * 판 위 한 손가락(끌기·탭)을 엔진 걸음으로 옮긴다. 화면 상태가 **참조로** 들고 있다(터치마다 화면이 다시 그려지지 않게).
 * 끌기 값에는 **시작 시각이 없다** — 탭 판정의 elapsed 를 내려면 누군가 첫 시각을 기억해야 한다. 그 자리가 여기다.
 * 이 타입은 화면이 없다 — JVM 시험이 **손가락 좌표 → 조각 위치**를 구동한다.
 */
class GamesTetrisDuelTouch(cellWidth: Double = TetrisLayout.cell) {
    private val tracker = TetrisGestureTracker(TetrisGestureThresholds(cellWidth))

    /** 지금 따라가는 접촉의 시작점 — 새 끌기를 알아보는 기준(끌기 끝은 늘 오지 않는다). */
    private var startLocation: MiniGamePoint? = null
    private var startedAt: SwiftDate? = null

    /** 한 칸 문턱을 화면 셀 폭으로 갈아 끼운다(논리 13 × 그려진 배율 — P11). */
    fun updateCellWidth(width: Double) {
        tracker.updateCellWidth(width)
    }

    /**
     * 끌기 변화 — 새로 생긴 걸음을 **그 자리에서** 엔진에 먹인다.
     * INV-GamesTetrisDuelMatch-7c509432 이식: 걸음 사이·가로 걸음의 누름/뗌 쌍 사이에 `tick`·`advance` 를 끼우지 마라 — 그 순간 자동 반복이
     *   살아나 한 걸음이 여러 칸이 된다. 코어 문 하나가 쌍을 통째로 쥔다.
     */
    fun changed(startLocation: MiniGamePoint, translation: MiniGameSize, time: SwiftDate, store: TetrisDuelStore) {
        if (this.startLocation != startLocation) {
            this.startLocation = startLocation
            startedAt = time
        }
        for (step in tracker.drag(startLocation, translation)) feed(step, store)
    }

    /** 끌기 끝 — 탭(8pt 미만 · 0.25초 안)이면 **시계 회전**이다. @return 이 끌기가 탭이었는가. */
    fun ended(translation: MiniGameSize, time: SwiftDate, store: TetrisDuelStore): Boolean {
        val elapsed = startedAt?.let { maxOf(0.0, time.timeIntervalSince(it)) } ?: 0.0
        startLocation = null
        startedAt = null
        if (!tracker.end(translation, elapsed)) return false
        store.rotate(clockwise = true)
        return true
    }

    /** 화면이 사라졌다·앱이 내려갔다·판이 끝났다 — 잠금과 소비량을 비운다. */
    fun reset() {
        tracker.end(MiniGameSize(0.0, 0.0), 0.0)
        startLocation = null
        startedAt = null
    }

    companion object {
        /** 걸음 하나 → 코어 문 하나. **`setLeftHeld` 로 흉내 내지 마라**(P9): 제스처는 거리를 주고 눌린 시간을 주지 않는다. */
        fun feed(step: TetrisGestureStep, store: TetrisDuelStore) {
            when (step) {
                TetrisGestureStep.moveLeft -> store.moveLeftOneCell()
                TetrisGestureStep.moveRight -> store.moveRightOneCell()
                TetrisGestureStep.softDrop -> store.softDropOneCell()
            }
        }
    }
}
