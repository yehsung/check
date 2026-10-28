// 원본: Sources/CheckMobileKit/Games/GamesGomokuWatchText.swift @ 1b8260d
package com.yehsung.aingcheck.core.stores.gomoku

import com.yehsung.aingcheck.core.rules.renju.GomokuBoard
import com.yehsung.aingcheck.core.rules.renju.GomokuColor
import com.yehsung.aingcheck.core.rules.renju.GomokuEndReason
import com.yehsung.aingcheck.core.rules.renju.GomokuPoint
import com.yehsung.aingcheck.core.wire.SwiftDate

// 관전 화면(0.3.41) 문구 · 상태 판정. **맥과 같은 뜻이면 같은 문장이다**(맥 `GomokuText` 의 관전 절). 폰에서 처음 쓴 줄만 `// 폰`.
// 글자와 **순수 판정**뿐이라 데스크톱 JVM 시험이 값으로 잰다. 색은 여기서 고르지 않는다 — `Kind` 만 돌려주고 토큰은 화면이 고른다.
//
// Swift 는 이 절이 `extension GomokuPhoneText` 이다. 그 바탕 표(`GamesText.swift` 의 `GomokuPhoneText` — 판돈 제목 · 돌 짧은 이름)는
// **W2-e 몫**(core/stores/…/games/GamesText.kt)이고 같은 웨이브에서 따로 옮겨진다. 그래서 이 파일은 관전 절을 [GomokuPhoneWatchText]
// 한 객체로 두고, 바탕 표에서 빌리는 두 글자([stoneShort] · [stakeTitle])만 같은 글자로 둔다. W2-e 병합 뒤 조정자가 이 둘을
// `GomokuPhoneText.stoneShort`·`stakeTitle` 로 접는다(같은 글자인지는 GomokuPhoneWatchTextTest 가 손으로 적은 표로 못 박는다).

object GomokuPhoneWatchText {
    /** 바탕 표(`GomokuPhoneText.stoneShort`)와 같은 글자 — W2-e 병합 뒤 접는다(파일 머리말). */
    fun stoneShort(color: GomokuColor): String = if (color == GomokuColor.black) "흑" else "백"

    /** 바탕 표(`GomokuPhoneText.stakeTitle`)와 같은 글자 — W2-e 병합 뒤 접는다. */
    const val stakeTitle: String = "판돈"

    const val watching: String = "관전 중"
    /** 첫 응답 전(얼굴만 · 색 없음). 씨앗조차 없는 판도 같은 줄이다. **끝난 판에는 쓰지 마라** — 그때는 [watchPlayersUnknown]. */
    const val watchLoading: String = "판을 불러오고 있어요"
    /** 끝난 판인데 서버가 두 사람 행을 못 채웠다(끝난 판은 폴링이 멈춰 더 올 것이 없다 — 진행형으로 말하면 거짓말). */
    const val watchPlayersUnknown: String = "대국자를 불러오지 못했어요"

    /** 관전 플레이어 카드 부제 — **돌 색만** 말한다(관전 응답에는 `is_working` 키가 없다 — 모르는 것은 말하지 않는다). */
    fun watchPlayerSubtitle(color: GomokuColor): String = stoneShort(color)

    fun watchTurn(color: GomokuColor): String = "$watching · ${stoneShort(color)} 차례"

    /** 마감이 지났다. **"졌다"·"시간 초과"로 쓰지 않는다** — 따라잡기는 대국자 조회·매분 크론 몫이다. */
    const val watchAutoPending: String = "$watching · 시간이 지나 곧 자동으로 놓여요"

    /** 자동 착수 연속이 한 번 남은 사람. */
    fun watchStreakWarning(name: String): String = "${name}님이 한 번 더 놓치면 져요"

    const val watchEndedTitle: String = "대국이 끝났어요"

    /**
     * 끝난 판 한 줄. 이긴 사람이 없으면 무승부다. 사유는 **진 쪽의 것**이라 이긴 사람 이름 뒤에 그대로 붙이면 주어가 뒤집힌다 —
     * 승패가 갈린 줄은 승자 기준 표현([watchWinReason])을 쓰고, 주어가 없는 무승부 줄만 중립 표현([watchReason])을 쓴다.
     */
    fun watchEnded(winnerName: String?, reason: GomokuEndReason?): String {
        if (winnerName == null) return "무승부 · ${watchReason(reason)}"
        return "$watchEndedTitle · $winnerName 승 (${watchWinReason(reason)})"
    }

    /** 이긴 쪽 이름 뒤에 붙는 사유 — **주어가 이긴 사람으로 읽히지 않게** 진 쪽을 드러낸다. */
    fun watchWinReason(reason: GomokuEndReason?): String = when (reason) {
        GomokuEndReason.abandoned -> "상대 자리 비움"
        // 끝난 판의 **옛 어휘** `timeout`(0.3.27). 진행 중 마감이 지난 판을 "시간 초과"로 쓰지 않는 것과는 다른 자리다.
        GomokuEndReason.timeout -> "상대 시간 초과"
        else -> watchReason(reason)
    }

    /** 끝난 이유의 짧은 이름 — 관전자는 승패 당사자가 아니라 "상대가"·"내가" 없이 사실만 말한다. */
    fun watchReason(reason: GomokuEndReason?): String = when (reason) {
        GomokuEndReason.five -> "오목"
        GomokuEndReason.resign -> "기권"
        GomokuEndReason.abandoned -> "자리 비움"
        GomokuEndReason.timeout -> "시간이 다 됐어요"
        GomokuEndReason.boardFull -> "판이 가득 찼어요"
        null -> "끝"
    }

    /** 관전은 판만이다 — 서버 응답에 채팅 키 자체가 없다. */
    const val watchNoChat: String = "대국자 채팅은 보이지 않아요"

    fun watchMoves(count: Int): String = "${count}수"

    const val leaveWatch: String = "나가기"
    /** 폰: [나가기] 보이스오버 힌트. */
    const val leaveWatchHint: String = "로비로 돌아가요"
    /** 폰: 판돈을 아직 모른다(씨앗 없이 들어온 판의 첫 응답 전). */
    const val watchStakeUnknown: String = "$stakeTitle —"

    /** 보이스오버: 돌이 하나도 없는 판. **`lastMove` 가 아니라 돌 개수로만** 판정한다. */
    const val watchEmptyBoard: String = "아직 둔 돌이 없어요"
    /** 보이스오버: 돌은 있는데 마지막 수 자리를 모른다(서버 `board` 만 오고 `moves` 가 비어 온 응답). */
    const val watchLastMoveUnknown: String = "마지막 수는 몰라요"

    /** 보이스오버: 관전 판 전체를 한 요소로(돌 수 · 마지막 수 · 누구 차례). 관전은 입력이 없다. */
    fun watchBoardAccessibility(watch: GomokuSpectateState): String {
        var black = 0
        var white = 0
        for (y in 0 until GomokuBoard.size) {
            for (x in 0 until GomokuBoard.size) {
                val point = GomokuPoint.at(x, y) ?: continue
                when (watch.board[point]) {
                    GomokuColor.black -> black += 1
                    GomokuColor.white -> white += 1
                    null -> Unit
                }
            }
        }
        val parts = mutableListOf("오목판", "흑 ${black}개", "백 ${white}개")
        // **`lastMove == null` 은 "빈 판"이 아니다.** 서버 `board` 문자열이 권위라 돌은 이미 서 있고 `lastMove` 만 null 로 남을 수 있다.
        val lastMove = watch.lastMove
        when {
            lastMove != null -> parts.add("마지막 수 ${lastMove.notation}")
            black + white == 0 -> parts.add(watchEmptyBoard)
            else -> parts.add(watchLastMoveUnknown)
        }
        val turn = watch.turn
        when {
            watch.isFinished -> parts.add(watchEndedTitle)
            turn != null -> parts.add(watchTurn(turn))
            else -> parts.add(watchLoading)
        }
        return parts.joinToString(", ")
    }
}

/**
 * 관전 상태 한 줄의 판정(순수 — 맥 `GomokuWatchStatusRule` 과 같은 표). 시각은 **잎이 넘긴다**. **마감이 지나도 "졌다"가 아니다** —
 * 화면은 "곧 자동으로 놓여요"만 말하고 결과는 서버가 finished 를 준 뒤에만 말한다.
 */
object GomokuPhoneWatchStatus {
    sealed interface Kind {
        /** 첫 응답 전(색·차례를 모른다). */
        data object loading : Kind
        data class turn(val color: GomokuColor) : Kind
        /** 마감이 지났는데 아직 진행 중 — 자동 착수 대기. */
        data object overdue : Kind
        data object ended : Kind
    }

    fun kind(watch: GomokuSpectateState, now: SwiftDate): Kind {
        if (watch.isFinished) return Kind.ended
        val turn = watch.turn
        if (!watch.hasServerState || turn == null) return Kind.loading
        val deadline = watch.deadline
        if (deadline != null && deadline <= now) return Kind.overdue
        return Kind.turn(turn)
    }

    fun text(watch: GomokuSpectateState, now: SwiftDate): String = when (val kind = kind(watch, now)) {
        Kind.loading -> GomokuPhoneWatchText.watchLoading
        is Kind.turn -> GomokuPhoneWatchText.watchTurn(kind.color)
        Kind.overdue -> GomokuPhoneWatchText.watchAutoPending
        Kind.ended -> GomokuPhoneWatchText.watchEnded(winnerName(watch), watch.endReason)
    }

    /** 이긴 사람의 이름. 이긴 색은 있는데 사람 행이 없으면 색 이름으로 — 무승부로 읽히면 안 된다. */
    fun winnerName(watch: GomokuSpectateState): String? = when (watch.winner) {
        GomokuColor.black -> displayName(watch.black, GomokuColor.black)
        GomokuColor.white -> displayName(watch.white, GomokuColor.white)
        null -> null
    }

    /** 이름이 비면 색 이름으로 접는다(코어 경계 `peerUser` 는 이름을 모를 때 null 이 아니라 `""` 를 넣는다 — `?:` 로는 못 잡는다). */
    private fun displayName(user: GomokuUser?, color: GomokuColor): String {
        val name = user?.displayName ?: ""
        return name.ifEmpty { GomokuPhoneWatchText.stoneShort(color) }
    }

    /**
     * 자동 착수 연속이 **한 번 남은** 사람의 경고(끝난 판·첫 응답 전에는 없다). 둘 다면 흑부터 — 한 줄만 둔다.
     * 이름이 비면 줄을 **아예 세우지 않는다**(주어 없는 문장 금지 — 누구인지 못 말하면 말하지 않는다).
     */
    fun streakWarning(watch: GomokuSpectateState, lossStreak: Int): String? {
        if (watch.isFinished || !watch.hasServerState) return null
        val blackName = watch.black?.displayName
        if (watch.blackAutoStreak == lossStreak - 1 && !blackName.isNullOrEmpty()) return GomokuPhoneWatchText.watchStreakWarning(blackName)
        val whiteName = watch.white?.displayName
        if (watch.whiteAutoStreak == lossStreak - 1 && !whiteName.isNullOrEmpty()) return GomokuPhoneWatchText.watchStreakWarning(whiteName)
        return null
    }
}
