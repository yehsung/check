// 원본: Sources/CheckMobileKit/Games/GamesChessWatch.swift:1-191(관전 판정 겹 — Plan · Status · Budget) @ 1b8260d
package com.yehsung.aingcheck.core.stores.chess

import com.yehsung.aingcheck.core.rules.chess.ChessColor
import com.yehsung.aingcheck.core.rules.chess.ChessSquare
import com.yehsung.aingcheck.core.stores.gomoku.BoardSize

// 체스 **관전 절**(폰)의 **판정 겹**만 옮긴다(192~759 줄의 화면 몫은 W4-a). 판정을 화면에 묻어 두면 게이트를 되돌려도 전부 초록이 된다 —
// 오목에서 실제로 613건이 그랬다. 판정을 떼어 두면 시험이 **부르는 자리와 결과**를 값으로 잰다.
//
// INV-GamesChessWatch-6f02ebb8 이식: 스토어 자리는 **`ChessStore`** 다(로봇 입구와 같은 규약) — 로비가 `store.chess` 를 넘긴다(통합이 고친 자리).
//
// ── 자리 계약(부르는 쪽이 지킨다) ── 관전은 **로비 스크롤 안의 한 절**이다(새 라우트·새 화면이 아니다 — 자식 화면을 push 하면 체스 화면이
// 사라지며 `windowDidHide()` 로 폴링이 죽는다). ── 관전은 판만이다 ── 채팅이 없다. 관전자 수는 `store.spectatorCount` 한 칸(0 이면 안 그린다).
// ── 입력이 하나도 없다 ── 판은 순수 그림이고 탭 처리기에 null 이 간다. 판 방향은 **백이 아래**다.

/** 관전 입구·관전 판의 **순수 판정**. 색·글꼴은 고르지 않는다. */
object GamesChessWatchPlan {
    /** 로비 "지금 대결 중" 한 행의 오른쪽 끝에 서는 것. */
    enum class Entry {
        /** 아무것도 두지 않는다(주 스위치가 꺼진 배선). */
        absent,
        /** 내 판 — 캡션만. */
        myMatch,
        /** 서버에 `chess_watch` 가 아직 없다 — 캡션만. */
        soon,
        /** [관전] 칩. */
        chip,
    }

    /**
     * 관전 입구 판정. **판돈 깃발(§8-17 #1)과는 무관하다** — 관전은 판돈 진입이 아니다.
     * INV-GamesChessWatch-f53df830 이식: **주 스위치가 꺼진 배선에서는 칩 자체를 두지 않는다** — `startWatching` 이 `spectatorFeaturesEnabled` 를
     * 먼저 보고 조용히 돌아서므로 눌러도 아무 일이 없는 버튼이 된다.
     * INV-GamesChessWatch-cd7c32f9 이식: **잠금은 `watchUnavailable` 하나로 판정한다** — `rankingUnavailable` 로 만든 게이트는 순위 행을 들고 있는
     * 사용자에게 영영 열려 404 를 무한히 낸다(게이트와 신호는 짝으로 움직인다).
     */
    fun entry(store: ChessStore, isMine: Boolean): Entry {
        if (!store.spectatorFeaturesEnabled) return Entry.absent
        if (isMine) return Entry.myMatch
        if (store.watchUnavailable) return Entry.soon
        return Entry.chip
    }

    // MARK: 관전 판에 넘기는 값 — 입력이 0건인 자리

    /**
     * 판의 탭 처리기. INV-GamesChessWatch-bdbfb750 이식: **늘 null 이다** — 관전자는 아무것도 쓰지 못한다. 값으로 떼어 둔 까닭은 재기 위해서다
     * (화면 안에 null 을 적어 두면 누가 거기에 처리기를 끼워도 시험이 모른다).
     */
    val boardTapHandler: ((ChessSquare) -> Unit)? = null
    /** 고른 말 표시 없음(관전에는 선택이 없다). */
    val boardSelection: ChessSquare? = null
    /** 도착 점 없음. */
    val boardLegalTargets: Set<ChessSquare> = emptySet()
    /** INV-GamesChessWatch-230cf548 이식: **백이 아래**다 — 관전자에게는 내 색이 없고, 체스 관례가 백 아래다. */
    const val boardWhiteAtBottom: Boolean = true

    /**
     * 체크 덮개가 설 칸. INV-GamesChessWatch-44d800c3 이식: **관전에도 그린다** — 선택·도착 점은 버리지만 체크는 판의 사실이고 글자로만 말해서는
     * 안 되는 정보다.
     * INV-GamesChessWatch-987fb8c8 이식: 깃발은 **응답이 준 값**이다(`chess_watch` 의 `in_check`) — 관전 화면은 합법 수를 만들지 않는다.
     */
    fun boardCheckSquare(watch: ChessSpectateState): ChessSquare? =
        GamesChessCheckMark.square(watch.isInCheck, watch.isFinished, watch.turn, watch.position)
}

/**
 * 관전 상태 한 줄의 판정(순수 — 맥 `ChessWatchStatusText` 와 같은 표).
 * INV-GamesChessWatch-e1f67bd1 이식: **마감이 지나도 결과를 지어내지 않는다** — `chess_watch` 는 읽기 전용이라 시간이 다 된 판을 닫지 않으므로
 * 상태는 여전히 "그 사람 차례"다. 그래서 이 판정에는 **시각이 들어오지 않는다**.
 */
object GamesChessWatchStatus {
    sealed interface Kind {
        /** 첫 응답 전(색·차례를 모른다). */
        data object loading : Kind
        data class turn(val color: ChessColor) : Kind
        data object ended : Kind
    }

    fun kind(watch: ChessSpectateState): Kind {
        if (watch.isFinished) return Kind.ended
        val turn = watch.turn
        if (!watch.hasServerState || turn == null) return Kind.loading
        return Kind.turn(turn)
    }

    fun headline(watch: ChessSpectateState): String = when (val kind = kind(watch)) {
        Kind.ended -> watch.winner?.let(ChessPhoneText::endedWin) ?: ChessPhoneText.endedDraw
        Kind.loading -> ChessPhoneText.watchLoading
        is Kind.turn -> ChessPhoneText.watchingTurn(kind.color)
    }

    /** 둘째 줄. **끝난 판에만 있다**. 사유는 **3인칭**(`watchEndReason`) — 내 기준 표를 쓰면 "흑 승리 / 기권했어요" 자기모순이 된다. */
    fun detail(watch: ChessSpectateState): String? {
        if (!watch.isFinished) return null
        val reason = ChessPhoneText.watchEndReason(watch.endReason, watch.winner)
        return reason.ifEmpty { null }
    }
}

/**
 * 관전 절의 세로 예산(pt · **기본 글자 크기**). 판 한 변의 **세로 상한**을 정할 때 쓴다.
 * INV-GamesChessWatch-bc0585e5 이식: **너비만 보면 아래가 잘린다** — 관전에서 가장 중요한 상태(누구 차례 · 남은 시간 · 끝났는가)가 판보다 먼저다
 * (오목 관전이 글자 크기만 보다가 작은 폰에서 상태 상자가 통째로 화면 밖이었다).
 */
object GamesChessWatchBudget {
    /** `MobileTheme.space2`(8) — 그 토큰은 화면 전용이라 숫자를 옮겨 적는다. */
    const val gap: Double = 8.0

    /**
     * 절 머리(`SectionHeader(padded: true)` + 오른쪽 [나가기]): 위 22 + title3 24 + 아래 8 = 54.
     * INV-GamesChessWatch-9b086244 이식: 관전은 **로비 스크롤 안의 절**이라 [나가기]가 떠 있는 아래 막대가 아니라 이 머리에 붙는다.
     */
    const val sectionHeader: Double = 22.0 + 24.0 + 8.0
    /** 플레이어 카드 한 장: 초상 44 + 위아래 8 = 60. */
    const val playerCard: Double = 44.0 + 8.0 * 2
    /** 상태 상자: subheadline **두 줄**(20×2) + 위아래 10 = 60. */
    const val statusBox: Double = 20.0 * 2 + 10.0 * 2

    /** 판 위·아래에서 **상태 상자까지** 자리를 먹는 블록의 합(간격 포함). */
    fun blocksAroundBoard(): Double {
        val blocks = listOf(sectionHeader, playerCard, playerCard, statusBox)
        return blocks.sum() + gap * blocks.size
    }

    /** 판의 **세로 상한**. null 이면 아직 뷰포트를 모른다(그때는 상한 없이 폭이 정한다). 8의 배수로 내리는 것은 판 부품 한 곳에서 한다. */
    fun boardCap(viewportHeight: Double): Double? {
        if (!viewportHeight.isFinite() || viewportHeight <= 0) return null
        val budget = viewportHeight - blocksAroundBoard()
        return GamesChessBoardMetrics.side(BoardSize(Double.MAX_VALUE, budget))
    }
}
