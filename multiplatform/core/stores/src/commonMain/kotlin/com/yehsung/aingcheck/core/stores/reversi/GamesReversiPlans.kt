// 원본: Sources/CheckMobileKit/Games/GamesReversiLobby.swift:19-129(LobbyPlan · Respond · InviteBanner · StakeSend.toggled/send) ·
//       GamesReversiMatch.swift:24-248(MatchChrome · MoveLog) · GamesReversiAI.swift:23-70(AIColorChoice · AIEntry) ·
//       GamesReversiRanking.swift:21-72(RankingPlan) · GamesReversiWatch.swift:32-166(WatchPlan · WatchStatus · WatchBudget) ·
//       GamesReversiBoard.swift:23-84(BoardGeometry · BoardLayout · BoardCells) · GamesReversiRules.swift:12-59(RuleExample) @ ios-1017-int 879c9952
//
// 폰 아잉 뒤집기 화면의 **순수 판정**. iOS 가 `#if os(iOS)` 밖에 둔 판정 몫을 같은 이름으로 옮겼다 — Compose 화면(ui/games/reversi)은 이 값을 배치만 한다
// (판정을 화면에 묻으면 JVM 시험이 값으로 못 잰다). 색·글꼴은 고르지 않는다 — 색은 **뜻**([ReversiMatchTint])만 말하고 토큰은 화면이 고른다.
//
// Android 가 iOS 와 다른 자리(두 곳):
//  ① 로비 상대 목록·순위의 '불러오지 못함' 갈래 — Kotlin 스토어에는 `lobbyLoadFailed`·`rankingLoadFailed` 깃발이 있다(iOS 코어에는 없어 로딩 줄로 남는다).
//     문구는 체스 표의 같은 문장을 빌린다(새 글자 없음).
//  ② 판돈 대결 깃발(§8-17 #1 `duelsLocked`) — 수락 문도 그 깃발을 본다(체스와 같다 · 스토어 `respond` 도 막는다 — 짝으로 막는다).
package com.yehsung.aingcheck.core.stores.reversi

import com.yehsung.aingcheck.core.rules.ai.ReversiAIGame
import com.yehsung.aingcheck.core.rules.duel.DuelFee
import com.yehsung.aingcheck.core.rules.reversi.ReversiPlay
import com.yehsung.aingcheck.core.rules.reversi.ReversiRules
import com.yehsung.aingcheck.core.stores.games.GamesStore
import com.yehsung.aingcheck.core.stores.games.GamesWatcherCount
import com.yehsung.aingcheck.core.stores.games.MobileLoadKnowledge
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.games.ReversiBoard
import com.yehsung.aingcheck.core.wire.games.ReversiColor
import com.yehsung.aingcheck.core.wire.games.ReversiCounts
import com.yehsung.aingcheck.core.wire.games.ReversiEndReason
import com.yehsung.aingcheck.core.wire.games.ReversiPly

/** 표가 말하는 색의 **뜻**(토큰은 화면이 고른다 — 체스 `ChessMatchTint` 와 같은 넷). */
enum class ReversiMatchTint { good, bad, warn, quiet }

/** 글자 한 줄 + 그 뜻. */
data class ReversiMatchLine(val text: String, val tint: ReversiMatchTint)

// MARK: - 로비

/** 로비 절들의 판정(스토어 값만 읽는다). */
object GamesReversiLobbyPlan {
    /** 상대 고르기 절이 그릴 것. */
    enum class Users { rows, empty, failed, loading }

    /**
     * ★ "없다"는 **한 번 받은 뒤에만** 말한다(공용 [MobileLoadKnowledge] 규약). Kotlin 스토어는 `hasLoadedLobby`·`lobbyLoadFailed` 를 들고 있다 — iOS 는 이
     *   깃발이 없어 `record != null` 을 "받았다"로 읽는다(그 표지도 함께 본다 — 로비 ok 는 전적을 반드시 세운다).
     */
    fun users(store: GamesStore): Users {
        val reversi = store.reversi ?: return Users.loading
        val placeholder = MobileLoadKnowledge.placeholder(
            hasRows = store.reversiLobbyUsers.isNotEmpty(),
            hasLoaded = reversi.hasLoadedLobby || reversi.record != null,
            lastFailed = reversi.lobbyLoadFailed,
        )
        return when (placeholder) {
            MobileLoadKnowledge.Placeholder.rows -> Users.rows
            MobileLoadKnowledge.Placeholder.empty -> Users.empty
            MobileLoadKnowledge.Placeholder.failed -> Users.failed
            MobileLoadKnowledge.Placeholder.loading -> Users.loading
        }
    }

    /**
     * 사람에게 신청하는 절들(받은·보낸 신청 · 상대 · 관전 · 순위)을 세우는가. 이 기기·서버 조합에서 할 수 없으면(업데이트 필요 · 서버 준비 중) 그 절들은 서지
     * 않는다 — 신청은 전부 거절된다. **로봇 연습은 서버를 안 타므로 그때도 연다**.
     */
    fun showsPeopleSections(reversi: ReversiStore): Boolean = reversi.availability == ReversiAvailability.available

    /** 목록 아래 풀이 줄(지금 목록에 있는 까닭만). */
    fun lockLegends(store: GamesStore): List<String> = ReversiPhoneText.lockLegends(store.reversiLobbyUsers)
}

/** 받은 신청에 답하는 **한 문**. 로비 카드 · 판 화면 띠 · 로봇 판 확인이 모두 이것을 부른다(세 자리가 각자 `respond` 를 부르면 한 자리만 가드가 빠진다). */
object GamesReversiRespond {
    /** [수락]을 눌렀을 때 갈 길. */
    enum class AcceptRoute {
        /** 곧바로 수락 요청을 낸다. */
        send,

        /** 두던 **로봇 연습 판**이 있다 — 먼저 묻는다(코어 `respond` 에 AI 가드가 없어 1:1 판이 서는 순간 연습 판이 말없이 사라진다). */
        confirmRobot,

        /** 누를 수 없다 — 요청이 오가는 중 · **다른 게임의 판**이 흐른다 · 판돈 대결이 잠긴 빌드. */
        blocked,
    }

    fun canAccept(store: GamesStore): Boolean {
        val reversi = store.reversi ?: return false
        return !reversi.isBusy && !reversi.duelsLocked && store.reversiEntryBlock == null
    }

    /** 거절은 다른 게임 판이 흘러도 된다(판돈이 안 움직인다) — 요청이 오가는 중만 막는다. */
    fun canDecline(store: GamesStore): Boolean = store.reversi?.isBusy == false

    fun acceptRoute(store: GamesStore): AcceptRoute = when {
        !canAccept(store) -> AcceptRoute.blocked
        store.hasLiveReversiAIGame -> AcceptRoute.confirmRobot
        else -> AcceptRoute.send
    }

    /** 실제 수락. 확인의 [끝내고 수락] 도 이 문을 지난다 — 그 사이 다른 게임 판이 섰으면 요청 0건. 요청을 냈으면 true. */
    suspend fun accept(store: GamesStore, inviteID: String): Boolean {
        if (!canAccept(store)) return false
        store.reversi?.respond(inviteID, accept = true) ?: return false
        return true
    }

    suspend fun decline(store: GamesStore, inviteID: String): Boolean {
        if (!canDecline(store)) return false
        store.reversi?.respond(inviteID, accept = false) ?: return false
        return true
    }
}

/**
 * 판 id 가 바뀔 때 규칙 시트를 접는가(아이폰 1.0.17 검토 수리 33727592 `GamesReversiRulesSheetRule` 이식 — 판 7 검토 S-F3 · U-F1). **새 판이 섰을 때만** 접는다 —
 * 로비에서 규칙을 읽으며 수락을 기다리던 사람(흑은 서버가 무작위로 고른다)이 시트 아래서 30초를 흘려 자동 착수 · 3회 패(판돈)를 맞지 않게. 판 중에 책 단추로
 * 연 시트는 판 id 가 그대로라 접지 않고, 판이 끝나 로비로 돌아갈 때(새 id 가 null)도 접지 않는다.
 */
object GamesReversiRulesSheetRule {
    fun closesOnMatchChange(old: String?, new: String?): Boolean {
        if (new == null) return false
        return new != old
    }
}

/**
 * 판 화면(로봇 연습 · 끝난 판) 위에 세울 **받은 신청 띠**의 판정. 판·결과 화면이 로비를 통째로 덮어 60초 신청이 만료되는 길을 막는다.
 * ★ **두는 중인 1:1 판 위에는 세우지 않는다** — 서버가 수락을 `busy` 로 거절하고(한 사람 한 판), 띠가 30초 시계·판을 밀어 내린다.
 */
object GamesReversiInviteBanner {
    fun invite(reversi: ReversiStore): ReversiInvite? {
        val match = reversi.match ?: return null
        if (!(match.isAI || match.isFinished)) return null
        return reversi.visibleIncoming
    }

    /** 띠에 못 실은 나머지 신청 수(0 이면 꼬리를 안 단다). */
    fun moreCount(reversi: ReversiStore): Int {
        if (invite(reversi) == null) return 0
        return maxOf(0, reversi.visibleIncomingInvites.size - 1)
    }
}

/** 고른 판돈을 다시 누르면 해제(체스·테트리스 시트와 같은 규약 — 처음엔 아무것도 안 골라진 채 열린다). */
fun GamesReversiStakeSend.toggled(current: ReversiStake?, tapped: ReversiStake): ReversiStake? = if (current == tapped) null else tapped

/**
 * 판돈 시트의 [N 걸고 도전하기] — 신청이 나가는 **유일한 문**. 마지막 문 판정([GamesReversiStakeSend.sendable])을 지난 판돈만 스토어에 적고 신청한다
 * (코어 `challenge` 는 `selectedStake` 로 보낸다 — 적고 보내는 두 줄이 갈리면 고른 것과 다른 판돈이 나간다). 요청을 냈으면 true.
 */
suspend fun GamesReversiStakeSend.send(selected: ReversiStake?, userID: String, games: GamesStore): Boolean {
    val reversi = games.reversi ?: return false
    val stake = sendable(selected, reversi, games.rubyBalance, games.reversiEntryBlock) ?: return false
    reversi.selectedStake = stake
    reversi.challenge(userID)
    return true
}

// MARK: - 대국 · 결과

/** 대국·결과 화면이 그리는 것을 **값으로** 내놓는 표. 돈이 갈리는 판정(결과 · 루비 · 무승부 환불 · 동작 줄)은 전부 여기다. */
data class GamesReversiMatchChrome(
    val isAI: Boolean,
    val showsStake: Boolean,
    val stake: Int,
    val stakeSuffix: String?,
    /** 상대 카드의 이름(로봇 판은 '로봇' · 모르는 상대는 '상대'). */
    val opponentName: String,
    val actionRow: ActionRow,
    /** 상태 둘째 줄 — 스토어 안내가 먼저, 그다음 **방금 일어난 패스**. 끝난 판은 null. */
    val detailLine: ReversiMatchLine?,
    /** 판 위 회색 점의 뜻(끝난 판·자동 돌 없음이면 null). */
    val autoPlacedLine: String?,
    /** 한 번 더 놓치면 지는 순간의 빨강 한 줄. */
    val autoStreakWarning: String?,
    /** 시계 규칙 한 줄(1:1 은 서버 시계 · 로봇 판은 떠나면 멈춘다). */
    val clockLine: String,
    /** 30초 링이 가득 찬 값(초). 1:1 은 로비가 말한 값, 로봇 판은 로컬 판의 값. */
    val turnSeconds: Int,
    val resignConfirmTitle: String,
    val resignConfirmMessage: String,
    val result: Result?,
) {
    sealed interface ActionRow {
        /** 두는 중 — [기권]. 왕복 중이면 눌리지 않는다. */
        data class playing(val canResign: Boolean) : ActionRow

        /** 끝난 판 — [로비로](로봇 판은 [같은 색으로 다시 두기] 가 함께 선다). */
        data class finished(val showsPlayAgain: Boolean) : ActionRow
    }

    /** 끝난 판 한 장. */
    data class Result(
        val title: String,
        val reason: String,
        val tint: ReversiMatchTint,
        /** 이 판으로 내 루비가 변한 양(승 +순이익 · 패 −판돈 · 무 0). */
        val rubyDelta: Int,
        val rubyDeltaText: String,
        /** 로봇 판은 루비를 안 그린다(±0 을 그리면 걸었다가 돌려받은 것처럼 읽힌다). */
        val showsRubyDelta: Boolean,
        /** 무승부 환불 한 줄 · 로봇 판의 "기록 없음" 한 줄. */
        val rubyNote: String?,
        /** 점수 줄(자연 종료는 흑 : 백 점수 · 기권·자리 비움은 판 위 돌 수만). */
        val scoreLine: String,
        val opponentLine: String,
        val isDraw: Boolean,
    )

    companion object {
        /** [serverTurnSeconds] 는 로비가 말한 한 수 시간(코어 `turnSeconds` — 응답이 없으면 30). 로봇 판은 쓰지 않는다. */
        fun make(match: ReversiMatchState, notice: String?, isBusy: Boolean, serverTurnSeconds: Int): GamesReversiMatchChrome {
            val isAI = match.isAI
            val name = match.opponent.displayName.trim()
            val opponentName = if (isAI) ReversiPhoneText.aiName else name.ifEmpty { ReversiPhoneText.opponentFallbackName }
            val turnSeconds = if (isAI) ReversiAIGame.turnSeconds.toInt() else maxOf(1, serverTurnSeconds)
            val lossStreak = maxOf(1, match.autoAbandonStreak)
            val finished = match.isFinished
            return GamesReversiMatchChrome(
                isAI = isAI,
                showsStake = !isAI,
                stake = match.stake,
                stakeSuffix = if (isAI) null else ReversiPhoneText.stakeGainSuffix(match.stake),
                opponentName = opponentName,
                actionRow = if (finished) ActionRow.finished(showsPlayAgain = isAI) else ActionRow.playing(canResign = !isBusy),
                detailLine = when {
                    finished -> null
                    notice != null -> ReversiMatchLine(notice, ReversiMatchTint.warn)
                    else -> passLine(match, opponentName)?.let { ReversiMatchLine(it, ReversiMatchTint.quiet) }
                },
                autoPlacedLine = if (finished || match.autoStones.isEmpty()) null else ReversiPhoneText.autoPlacedCount(match.autoStones.size),
                autoStreakWarning = if (finished) null else ReversiPhoneText.autoStreakWarning(match.myAutoStreak, lossStreak),
                clockLine = ReversiPhoneText.clockLine(isAI, turnSeconds, lossStreak),
                turnSeconds = turnSeconds,
                resignConfirmTitle = if (isAI) ReversiPhoneText.aiResignConfirmTitle else ReversiPhoneText.resignConfirmTitle,
                resignConfirmMessage = if (isAI) ReversiPhoneText.aiNoRecord else ReversiPhoneText.resignConfirmMessage,
                result = if (finished) makeResult(match, isAI) else null,
            )
        }

        /**
         * 마지막 기록이 패스면 그 사실 한 줄(맥 `ReversiMatchStatusText.passLine` 과 같은 판정). 상대가 넘겨 내 차례가 이어지면 상대 이름으로, 내가 넘겼으면
         * "차례가 넘어가요". 스토어의 패스 안내(`notice`)는 다음 수가 오면 걷히므로 그 뒤에도 판에서 안 보이는 이 사실을 기록에서 읽는다.
         */
        fun passLine(match: ReversiMatchState, opponentName: String): String? {
            if (match.isFinished) return null
            val last = match.plies.maxByOrNull { it.seq } ?: return null
            if (last.kind != ReversiPly.Kind.pass) return null
            val turn = match.turn ?: return null
            if (last.color != match.myColor && turn == match.myColor) return ReversiNoticeText.opponentPassed(opponentName)
            if (last.color == match.myColor && turn != match.myColor) return ReversiNoticeText.myPass
            return null
        }

        /** 이 판으로 내 루비가 변한 양. 승자 순이익은 `DuelFee.winnerNet`(서버와 같은 식 — 수수료 0 이라 +판돈) · 패 −판돈 · 무 0. */
        fun rubyDelta(outcome: ReversiMatchOutcome?, stake: Int): Int = when (outcome) {
            ReversiMatchOutcome.won -> DuelFee.winnerNet(stake)
            ReversiMatchOutcome.lost -> -stake
            ReversiMatchOutcome.draw, null -> 0
        }

        /** 점수 줄. 자연 종료는 WOF 점수(흑 : 백 고정), 기권·자리 비움은 판 위 돌 수만(점수가 없다). */
        fun scoreLine(match: ReversiMatchState): String = when (match.endReason) {
            ReversiEndReason.resign, ReversiEndReason.abandoned, ReversiEndReason.unknown, null -> ReversiPhoneText.boardOnlyLine(match.counts)
            ReversiEndReason.wipeout, ReversiEndReason.boardFull, ReversiEndReason.noMoves -> {
                val score = match.score ?: ReversiRules.score(match.board)
                if (score == null) ReversiPhoneText.boardOnlyLine(match.counts) else ReversiPhoneText.scoreLine(score, match.counts)
            }
        }

        private fun makeResult(match: ReversiMatchState, isAI: Boolean): Result {
            val outcome = match.outcome
            val delta = if (isAI) 0 else rubyDelta(outcome, match.stake)
            val isDraw = outcome == ReversiMatchOutcome.draw
            val tint = when (outcome) {
                ReversiMatchOutcome.won -> ReversiMatchTint.good
                ReversiMatchOutcome.lost -> ReversiMatchTint.bad
                else -> ReversiMatchTint.quiet
            }
            // 환불 한 줄은 **무승부일 때만**이고 로봇 판에는 없다(걸린 루비가 없다 — 대신 기록이 안 남는다는 한 줄).
            val note = when {
                isAI -> ReversiPhoneText.aiNoRecord
                isDraw && match.stake > 0 -> ReversiPhoneText.drawRefund(match.stake)
                else -> null
            }
            val subject = if (isAI) ReversiPhoneText.aiName else ReversiPhoneText.opponentFallbackName
            val name = match.opponent.displayName.trim()
            return Result(
                title = ReversiPhoneText.outcomeTitle(outcome),
                reason = ReversiPhoneText.endReason(match.endReason, outcome, subject, maxOf(1, match.autoAbandonStreak)),
                tint = tint, rubyDelta = delta, rubyDeltaText = ReversiPhoneText.rubyDelta(delta),
                showsRubyDelta = !isAI, rubyNote = note, scoreLine = scoreLine(match),
                opponentLine = if (isAI) ReversiPhoneText.aiOpponentLine else ReversiPhoneText.opponentLine(name.ifEmpty { ReversiPhoneText.opponentFallbackName }),
                isDraw = isDraw,
            )
        }

        /** 카드 부제 "흑 · 12개 · 자동 1/3". */
        fun cardSubtitle(color: ReversiColor, counts: ReversiCounts, autoStreak: Int, limit: Int): String {
            val discs = ReversiPhoneText.discLine(color, if (color == ReversiColor.black) counts.black else counts.white)
            val streak = ReversiPhoneText.autoStreak(autoStreak, maxOf(1, limit)) ?: return discs
            return "$discs · $streak"
        }

        // MARK: 시간을 받는 것 — **잎 전용**(⑥)

        /**
         * 차례 한 줄. [now] 는 잎의 **스토어 시계**다. 1:1 판의 마감 + 서버 유예가 지나면 "자동으로 놓이는 중"이라고 말한다(서버가 정산하는 중 — 폴링이 그 정산을
         * 부른다). 로봇 판은 코어 시계 작업이 마감에 곧바로 두므로 이 갈래가 없다.
         */
        fun turnLine(match: ReversiMatchState, now: SwiftDate, graceSeconds: Double, isAIThinking: Boolean): ReversiMatchLine {
            if (match.isFinished) {
                val tint = when (match.outcome) {
                    ReversiMatchOutcome.won -> ReversiMatchTint.good
                    ReversiMatchOutcome.lost -> ReversiMatchTint.bad
                    else -> ReversiMatchTint.quiet
                }
                return ReversiMatchLine(ReversiPhoneText.outcomeTitle(match.outcome), tint)
            }
            if (isAIThinking) return ReversiMatchLine(ReversiPhoneText.aiThinking, ReversiMatchTint.quiet)
            val deadline = match.deadline
            if (!match.isAI && deadline != null && now >= deadline.addingTimeInterval(maxOf(0.0, graceSeconds))) {
                return ReversiMatchLine(if (match.isMyTurn) ReversiPhoneText.mySettling else ReversiPhoneText.opponentSettling, ReversiMatchTint.warn)
            }
            return if (match.isMyTurn) ReversiMatchLine(ReversiPhoneText.myTurn, ReversiMatchTint.good)
            else ReversiMatchLine(ReversiPhoneText.opponentTurn, ReversiMatchTint.quiet)
        }

        /** 30초 링의 채움(0…1) — 남은 초 / 한 수 시간. */
        fun ringFraction(remaining: Double, turnSeconds: Int): Double {
            if (!remaining.isFinite()) return 0.0
            return minOf(1.0, maxOf(0.0, remaining / maxOf(1, turnSeconds).toDouble()))
        }

        /** 링 색의 뜻: 넉넉하면 초록 · 10초 이하 앰버 · 5초 이하 빨강(폰 오목 링과 같은 문턱). */
        fun ringTint(remaining: Double): ReversiMatchTint = when {
            remaining <= 5 -> ReversiMatchTint.bad
            remaining <= 10 -> ReversiMatchTint.warn
            else -> ReversiMatchTint.good
        }
    }
}

/**
 * 수 기록 칩 한 줄(가로 스크롤). **색으로** 짝을 짓는다 — 흑이 줄을 열고 백이 그 줄을 닫는다(맥 `ReversiMoveLog` 와 같은 판정).
 * 홀짝으로 자르면 패스·기록 구멍에서 번호가 통째로 밀린다. 줄 번호는 그 줄의 첫 칩에만 붙는다.
 */
object GamesReversiMoveLog {
    data class Chip(val id: Int, val number: Int?, val color: ReversiColor, val text: String, val isPass: Boolean, val isAuto: Boolean)

    fun chips(plies: List<ReversiPly>): List<Chip> {
        val chips = ArrayList<Chip>()
        var rows = 0
        var openRowHasBlack = false
        for (ply in plies.sortedBy { it.seq }) {
            val opensRow = when (ply.color) {
                ReversiColor.black -> { openRowHasBlack = true; true }
                ReversiColor.white -> { val opens = !openRowHasBlack; openRowHasBlack = false; opens }
            }
            if (opensRow) rows += 1
            chips += Chip(ply.seq, if (opensRow) rows else null, ply.color, ReversiPhoneText.plyText(ply), ply.kind == ReversiPly.Kind.pass, ply.auto)
        }
        return chips
    }
}

// MARK: - 로봇 연습

/** 돌 색 고르기 세 칸(맥 `ReversiAIPrompt` 와 같은 셋 — 순서도 같다). */
enum class GamesReversiAIColorChoice {
    black, white, random;

    /** 코어 `startAIMatch(humanColor)` 에 넘길 값. 무작위는 null(코어가 고른다 — 화면이 주사위를 굴리지 않는다). */
    val humanColor: ReversiColor?
        get() = when (this) {
            black -> ReversiColor.black
            white -> ReversiColor.white
            random -> null
        }

    val title: String
        get() = when (this) {
            black -> ReversiPhoneText.aiPlayBlack
            white -> ReversiPhoneText.aiPlayWhite
            random -> ReversiPhoneText.aiPlayRandom
        }
}

/** 로봇 연습 입구가 그리는 것(열렸는가 · 닫혔으면 까닭 한 줄). 여는 판정은 코어 [canStartAIMatch] **하나**다. */
data class GamesReversiAIEntry(val canStart: Boolean, val block: ReversiPhoneText.AIBlock?) {
    /** 입구 둘째 줄 — 열렸으면 무엇을 하는 곳인지, 닫혔으면 **언제 풀리는지**. */
    val caption: String get() = block?.let(ReversiPhoneText::aiBlock) ?: ReversiPhoneText.aiButtonHelp

    companion object {
        fun of(store: ReversiStore): GamesReversiAIEntry = GamesReversiAIEntry(store.canStartAIMatch, block(store))

        /** 닫힌 까닭 하나(열려 있으면 null). 서열: 판 > 보낸 신청 > 오가는 요청 — 보낸 신청은 **취소로 당장 풀 수 있는** 막힘이라 판과 다른 말을 들어야 한다. */
        fun block(store: ReversiStore): ReversiPhoneText.AIBlock? {
            if (store.canStartAIMatch) return null
            if (store.match != null || store.activeMatchID != null || store.phase != ReversiPhase.lobby) return ReversiPhoneText.AIBlock.playing
            if (store.outgoing != null) return ReversiPhoneText.AIBlock.outgoingInvite
            return ReversiPhoneText.AIBlock.busy
        }
    }
}

// MARK: - 순위

/** 순위 절의 순수 판정. **재정렬하지 않는다**(서버 순서가 권위 · 동률은 같은 rank). */
object GamesReversiRankingPlan {
    enum class Content { rows, soon, empty, failed, loading }

    const val collapsedRows: Int = ReversiPhoneText.rankCollapsedRows
    const val rowLimit: Int = ReversiPhoneText.rankRowLimit

    /** ★ **0판인 사람은 안 낀다** — 서버가 이미 거르지만 화면이 그 약속을 다시 지킨다. */
    fun playable(entries: List<ReversiRankEntry>): List<ReversiRankEntry> = entries.filter { it.wins + it.losses + it.draws > 0 }

    fun held(store: ReversiStore): List<ReversiRankEntry> = playable(store.ranking?.entries.orEmpty())

    fun visible(store: ReversiStore, isExpanded: Boolean): List<ReversiRankEntry> = held(store).take(if (isExpanded) rowLimit else collapsedRows)

    fun total(store: ReversiStore): Int = minOf(held(store).size, rowLimit)

    fun showsToggle(store: ReversiStore): Boolean = total(store) > collapsedRows

    /** ★ **분기 순서**: 행 → 준비 중 → 빈·실패·로딩. 행 갈래가 맨 앞이다(깃발을 먼저 보면 받아 둔 행을 버리고 "곧 열려요"를 말한다). */
    fun content(store: ReversiStore): Content {
        if (held(store).isNotEmpty()) return Content.rows
        if (store.rankingUnavailable) return Content.soon
        return when (MobileLoadKnowledge.placeholder(false, store.hasLoadedRanking || store.ranking != null, store.rankingLoadFailed)) {
            MobileLoadKnowledge.Placeholder.rows, MobileLoadKnowledge.Placeholder.loading -> Content.loading
            MobileLoadKnowledge.Placeholder.empty -> Content.empty
            MobileLoadKnowledge.Placeholder.failed -> Content.failed
        }
    }

    /** 목록 **밖**의 내 순위. 순위 응답의 전적이 로비 전적과 어긋나면 null(코어 판정 하나). */
    fun myRank(store: ReversiStore): ReversiMyRank? = store.myRankConsistentWithRecord

    /** 머리 오른쪽 캡션. **한 번도 못 받았으면 아무것도 말하지 않는다** — 컷을 모르는데 "전체 기간"은 거짓이다. */
    fun sinceCaption(store: ReversiStore): String? {
        val ranking = store.ranking ?: return null
        return ranking.recordSince?.let(ReversiPhoneText::rankSince) ?: ReversiPhoneText.rankWholePeriod
    }
}

// MARK: - 관전

/** 관전 입구·관전 판의 순수 판정. */
object GamesReversiWatchPlan {
    /** 로비 "지금 대결 중" 한 행의 오른쪽 끝에 서는 것(체스·테트리스와 같은 표). */
    enum class Entry { absent, myMatch, soon, chip }

    /** ★ 잠금은 `watchUnavailable` **하나**로 판정한다 — 순위·관전자 수 깃발과 겸업시키면 멀쩡한 관전이 통째로 막힌다. */
    fun entry(store: ReversiStore, isMine: Boolean): Entry {
        if (!store.spectatorFeaturesEnabled) return Entry.absent
        if (isMine) return Entry.myMatch
        if (store.watchUnavailable) return Entry.soon
        return Entry.chip
    }

    /** 줄 오른쪽 끝 슬롯이 무엇이든 그리는가 — 입구 또는 관전자 수(관전자 수는 주 스위치와 무관하다 — 로비 응답이 실어 온 사실이다). */
    fun hasTrailingContent(store: ReversiStore, live: ReversiLiveMatch): Boolean =
        entry(store, store.isMine(live)) != Entry.absent || GamesWatcherCount.shows(live.watchers)

    /** 판의 탭 처리기. ★ **늘 null** — 관전자는 아무것도 두지 못한다. */
    val boardTapHandler: ((Int) -> Unit)? = null

    /** 둘 수 있는 칸 점. ★ 늘 비었다(관전자의 차례는 없다). */
    val boardLegalTargets: Set<Int> = emptySet()

    /** [기권]을 그리는가. ★ 늘 거짓 — 관전자에게는 걸린 판돈이 없다. */
    const val showsResign: Boolean = false
}

/** 관전 상태 상자의 판정(맥 `ReversiWatchStatusText` 와 같은 표 + 승자 이름). ★ **시각이 들어오지 않는다** — 마감이 지나도 결과를 지어내지 않는다. */
object GamesReversiWatchStatus {
    sealed interface Kind {
        /** 첫 응답 전(색·차례를 모른다). */
        data object loading : Kind
        data class turn(val color: ReversiColor) : Kind
        data object ended : Kind
    }

    fun kind(watch: ReversiSpectating): Kind {
        if (watch.isFinished) return Kind.ended
        // 색이 서기 전(첫 응답 전)에는 차례를 말하지 않는다 — 씨앗 얼굴(a/b)은 uuid 순서라 색이 아니다.
        val turn = watch.turn
        if (watch.blackUser == null || watch.whiteUser == null || turn == null) return Kind.loading
        return Kind.turn(turn)
    }

    /** 끝난 판의 이긴 색 — 서버 판 행에서 옮긴 값 하나. 끝나지 않았으면 null(진행 중에 승자를 말하지 않는다). */
    fun winnerColor(watch: ReversiSpectating): ReversiColor? = if (watch.isFinished) watch.winner else null

    /** 이긴 사람의 부를 수 있는 이름 — **서버가 말한 흑·백 사람**에서만. 모르거나 이름이 비었으면 null. */
    fun winnerName(watch: ReversiSpectating): String? {
        val color = winnerColor(watch) ?: return null
        val user = if (color == ReversiColor.black) watch.blackUser else watch.whiteUser
        return user?.displayName?.trim()?.ifEmpty { null }
    }

    fun headline(watch: ReversiSpectating): String = when (val kind = kind(watch)) {
        Kind.ended -> winnerColor(watch)?.let { ReversiPhoneText.watchEndedWin(it, winnerName(watch)) } ?: ReversiPhoneText.watchEndedDraw
        Kind.loading -> ReversiPhoneText.watchLoading
        is Kind.turn -> ReversiPhoneText.watchingTurn(kind.color)
    }

    /** 둘째 줄 — **끝난 판에만** 있다. 사유는 3인칭이고 자리 비움 횟수는 서버 값이다. */
    fun detail(watch: ReversiSpectating, lossStreak: Int): String? {
        if (!watch.isFinished) return null
        return ReversiPhoneText.watchEndReason(watch.endReason, winnerColor(watch), maxOf(1, lossStreak)).ifEmpty { null }
    }

    /** 카드 이름 — 사람을 모르거나 이름이 빈 문자열이면 "—". */
    fun displayName(user: ReversiUser?): String = user?.displayName?.trim()?.ifEmpty { null } ?: ReversiPhoneText.watchUnknownName

    /** 관전 시계 색의 뜻. ★ **0 은 주황**(대기색)이다 — 0 을 빨갛게 하면 색만으로 "졌다"로 읽힌다. */
    fun clockTint(remaining: Double): ReversiMatchTint = if (remaining <= 0) ReversiMatchTint.warn else GamesReversiMatchChrome.ringTint(remaining)
}

/**
 * 관전 판 한 변(dp). 판은 로비 스크롤 **안**이라 높이를 못 읽는다 — 열 폭과 스크롤 뷰포트 높이를 받아 정한다(관전에서 가장 중요한 상태가 판보다 먼저다).
 * 블록 숫자는 iOS 토큰을 옮겨 적은 것이다(Android 토큰과 같은 값 — space2 8 · 절 머리 22+24+8 · 카드 44+16 · 상태 상자 40+20).
 */
object GamesReversiWatchBudget {
    const val gap: Double = 8.0
    const val sectionHeader: Double = 22.0 + 24.0 + 8.0
    const val playerCard: Double = 44.0 + 8.0 * 2
    const val statusBox: Double = 20.0 * 2 + 10.0 * 2

    fun blocksAroundBoard(): Double {
        val blocks = listOf(sectionHeader, playerCard, playerCard, statusBox)
        return blocks.sum() + gap * blocks.size
    }

    /** 바닥은 [GamesReversiBoardLayout.minimumSide](열이 더 좁으면 열 폭) · 칸이 정수가 되게 8의 배수로 내린다. 뷰포트를 모르면(0) 폭만 본다. */
    fun side(column: Double, viewportHeight: Double): Double {
        if (!column.isFinite() || column <= 0) return GamesReversiBoardLayout.minimumSide
        var side = column
        if (viewportHeight.isFinite() && viewportHeight > 0) side = minOf(side, viewportHeight - blocksAroundBoard())
        side = maxOf(minOf(GamesReversiBoardLayout.minimumSide, column), side)
        return maxOf(8.0, kotlin.math.floor(side / 8) * 8)
    }
}

// MARK: - 판 좌표

/** 판 좌표계. 여백이 없다(`cell = side / 8`) — 좌표 글자는 가장자리 칸 **안**에 그린다. **방향 뒤집기가 없다 — 1행이 위, a열이 왼쪽**(`idx = row*8 + col`). */
data class GamesReversiBoardGeometry(val side: Double) {
    val cell: Double get() = sideValue / 8
    private val sideValue: Double get() = if (side.isFinite()) maxOf(0.0, side) else 0.0

    /** 그 칸의 왼쪽 위(x, y). col 0 = a열(왼쪽), row 0 = 1행(**위**). */
    fun origin(idx: Int): Pair<Double, Double> = (idx % 8) * cell to (idx / 8) * cell

    fun center(idx: Int): Pair<Double, Double> = origin(idx).let { (x, y) -> x + cell / 2 to y + cell / 2 }

    /** 손가락이 닿은 칸(판 밖이면 null). **반 칸 관용이 없다**. */
    fun idx(x: Double, y: Double): Int? {
        if (cell <= 0 || !x.isFinite() || !y.isFinite() || x < 0 || y < 0 || x >= sideValue || y >= sideValue) return null
        val col = minOf(7, (x / cell).toInt())
        val row = minOf(7, (y / cell).toInt())
        return row * 8 + col
    }
}

/**
 * 판 한 변. 기본 글자에서는 **열 폭 그대로**(화면 폭 − 좌우 여백)다 — 판이 열보다 넓으면 같은 열의 카드가 전부 오른쪽으로 넘친다. 글자가 커지면 보이는
 * 높이에 맞춰 줄인다(대국에서 가장 중요한 상태가 판보다 먼저다). 칸이 정수가 되게 8 의 배수로 내린다.
 * ★ Android 몫(판 7 검토 U-F2 — 아이폰은 세로 고정이라 없다): 판 한 장이 **보이는 높이에도 안 들어가면**(큰 화면 가로 — sw≥600 은 방향을 풀어 두고
 *   Android 16 은 방향 요청을 무시한다 · 화면 나눔) 기본 글자에서도 보이는 높이의 52%(오목 `compactHeight` 와 같은 몫)로 줄인다. 열 폭 그대로면 판이
 *   1248dp 가 되어 내 카드의 30초 링 · '내 차례예요' · 3회 패 줄이 스크롤 아래로 밀린다. 폰 세로는 열이 보이는 높이보다 늘 좁아 값이 그대로다(아이폰과 같다).
 */
object GamesReversiBoardLayout {
    /** 판이 이보다 작아지지 않는다(열이 더 좁으면 열 폭). */
    const val minimumSide: Double = 200.0

    /** 판 한 장이 보이는 높이에 안 들어갈 때(가로 · 화면 나눔) 판이 차지할 보이는 높이의 몫. */
    const val shortHeightFraction: Double = 0.52

    fun side(visibleWidth: Double, visibleHeight: Double, sideMargin: Double, isLargeText: Boolean, isAccessibilitySize: Boolean): Double {
        val column = maxOf(0.0, visibleWidth - sideMargin * 2)
        // 첫 배치에서 폭이 0 인 한 틱 — 0 으로 그리면 판이 사라졌다 돌아온다. 그 틱은 바닥값으로 선다.
        if (column <= 0) return minimumSide
        var side = column
        if (visibleHeight > 0) {
            val fraction = when {
                isLargeText -> if (isAccessibilitySize) 0.40 else 0.52
                visibleHeight < column -> shortHeightFraction
                else -> null
            }
            if (fraction != null) side = minOf(side, kotlin.math.round(visibleHeight * fraction))
        }
        side = maxOf(minOf(minimumSide, column), side)
        return maxOf(8.0, kotlin.math.floor(side / 8) * 8)
    }
}

/** 칸 하나의 화면 읽기(칸 이름 · 돌 · 둘 수 있는가). 판정은 코어 값만 읽는다. */
object GamesReversiBoardCells {
    fun label(idx: Int, board: ReversiBoard, legalTargets: Set<Int>, lastStoneIdx: Int?, autoStones: Set<Int>): String =
        ReversiPhoneText.cellAccessibility(idx, board[idx], idx in legalTargets, lastStoneIdx == idx, idx in autoStones)
}

// MARK: - 규칙 예시

/** 규칙 시트의 예시 판 한 장. 판·점·고리를 **규칙 코어로 계산**해 만든다 — 손으로 적은 그림이 규칙과 어긋나지 않게(맥 `ReversiRuleExample` 과 같은 네 장). */
data class GamesReversiRuleExample(
    val id: String,
    val title: String,
    val detail: String,
    val board: ReversiBoard,
    /** 점(그 장면에서 둘 수 있는 칸). */
    val dots: Set<Int> = emptySet(),
    /** 방금 둔 돌(빨간 점). */
    val lastStone: Int? = null,
    /** 방금 뒤집힌 돌(주황 고리). */
    val flipped: Set<Int> = emptySet(),
) {
    companion object {
        val all: List<GamesReversiRuleExample>
            get() = buildList {
                // ① 시작 — 흑 차례 둘 수 있는 네 칸(d3 · c4 · f5 · e6).
                val start = ReversiBoard.start
                add(GamesReversiRuleExample("start", "흑이 먼저", "점이 흑이 둘 수 있는 칸이에요", start, dots = ReversiRules.legalMoves(start, ReversiColor.black).toSet()))
                // ② 여러 줄이 한 번에 — c3 에 흑을 두면 가로·세로·대각 세 방향이 함께 뒤집힌다.
                val before = ReversiBoard.fromString("...................wwb...www......b.w........w........b.........")
                val played = before?.let { ReversiRules.play(it, ReversiColor.black, 18) } as? ReversiPlay.Played
                if (played != null) {
                    add(GamesReversiRuleExample("lines", "여러 줄이 한 번에", "c3에 두면 주황 고리 돌이 모두 흑이 돼요", played.outcome.board,
                        lastStone = 18, flipped = played.outcome.flipped.toSet()))
                }
                // ③ 넘김 — 흑은 둘 곳이 없어(백 a1 은 모서리) 백 차례가 이어진다.
                ReversiBoard.fromString("wb" + ".".repeat(62))?.let { pass ->
                    add(GamesReversiRuleExample("pass", "둘 곳이 없으면 넘김", "흑은 둘 곳이 없어 백 차례가 이어져요", pass, dots = ReversiRules.legalMoves(pass, ReversiColor.white).toSet()))
                }
                // ④ 끝과 점수 — 둘 다 둘 곳이 없다. 빈칸은 이긴 쪽 몫.
                val end = ReversiBoard.fromString("bbb" + ".".repeat(53) + "w.......")
                val score = end?.let { ReversiRules.score(it) }
                if (end != null && score != null) {
                    add(GamesReversiRuleExample("end", "끝과 점수", "둘 다 못 두면 끝 · 빈칸은 이긴 쪽 몫 (${score.black} : ${score.white})", end))
                }
            }
    }
}
