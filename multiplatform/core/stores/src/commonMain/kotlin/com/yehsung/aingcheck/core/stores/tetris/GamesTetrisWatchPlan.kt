// 원본: Sources/CheckMobileKit/Games/GamesTetrisWatch.swift:1-247(GamesTetrisWatchPlan · GamesTetrisWatchStatus · GamesTetrisWatchBudget) @ 1b8260d
package com.yehsung.aingcheck.core.stores.tetris

import com.yehsung.aingcheck.core.rules.tetris.TetrisGame
import com.yehsung.aingcheck.core.stores.games.GamesWatcherCount

// 1:1 테트리스 **관전 절**(폰 · 0.3.65) — 남의 진행 중인 판을 **읽기 전용**으로 본다. 본은 폰 체스 관전이다.
//
// ── 자리 계약(부르는 쪽이 지킨다) ── 이 절은 **로비 스크롤 안의 한 절**이다. 새 라우트도, 새 화면도 아니다: 자식 화면을 쌓으면 테트리스
// 화면이 사라짐 → `tetrisScreenDidDisappear()` 로 스토어 폴링이 죽어 판이 갱신되지 않는다.
// ── 입력이 하나도 없다 ── 탭·끌기·버튼·기권이 전부 없다. 값으로 떼어 둔 까닭은 재기 위해서다([GamesTetrisWatchPlan.boardTapHandler] 등).
// ── 승자는 서버가 말한 것만 ──
// INV-GamesTetrisWatch-8d7ae830 이식: 끝난 판의 승자는 **서버가 실은 `match.winner`(uuid)** 한 곳에서만 온다 — 코어가 그 uuid 가 어느 자리의
//   사람인지만 보고 `aWon`·`bWon` 을 세운다. `result`('challenger_win'…)로 역산하지 마라: a/b 는 **uuid 오름차순 자리**일 뿐이다.
// INV-GamesTetrisWatch-a7612e2c 이식: **둘 다 거짓인 정상 상태가 있다**(무승부 · 진행 중 · 승자 칸을 모르는 옛 서버 · 그 자리의 사람을 아직
//   못 받은 틱). 그때는 승자를 말하지 않는다. 승자를 말할 때도 **3인칭**이다("밥 승리"). 탑아웃한 쪽은 `side.toppedOut` 이 **직접** 말한다.

/** 관전 입구·관전 판의 **순수 판정**. 색·글꼴은 고르지 않는다. */
object GamesTetrisWatchPlan {
    /** 로비 "지금 대결 중" 한 행의 오른쪽 끝에 서는 것(체스 `GamesChessWatchPlan.Entry` 와 같은 표). */
    enum class Entry {
        /** 아무것도 두지 않는다(주 스위치가 꺼진 배선). */
        absent,

        /** 내 판 — 캡션만(관전에 못 들어간다). */
        myMatch,

        /** 서버에 `tetris_watch` 가 아직 없다 — 캡션만. */
        soon,

        /** [관전] 칩. */
        chip,
    }

    /**
     * 관전 입구 판정.
     * INV-GamesTetrisWatch-3f0ead17 이식: **주 스위치가 꺼진 배선에서는 칩 자체를 두지 않는다.** `startWatching` 이 `spectatorFeaturesEnabled` 를
     *   먼저 보고 조용히 돌아서므로 눌러도 아무 일이 없는 버튼이 된다.
     * INV-GamesTetrisWatch-b73fef11 이식: **잠금은 `watchUnavailable` 하나로 판정한다.** `rankingUnavailable`·`spectatorCountUnavailable` 과
     *   **겸업시키지 마라** — 뒤엣것으로 잠그면 "관전자 수가 없다" 는 이유로 멀쩡한 관전이 통째로 막힌다.
     */
    fun entry(store: TetrisDuelStore, isMine: Boolean): Entry {
        if (!store.spectatorFeaturesEnabled) return Entry.absent
        if (isMine) return Entry.myMatch
        if (store.watchUnavailable) return Entry.soon
        return Entry.chip
    }

    // MARK: 관전 판에 넘기는 값 — 입력이 0건인 자리

    /** 판의 탭 처리기. INV-GamesTetrisWatch-4dce0bfe 이식: **늘 null 이다** — 관전자는 조각을 못 움직인다. */
    val boardTapHandler: (() -> Unit)? = null

    /** 판 위 끌기 처리기. INV-GamesTetrisWatch-4399c6c5 이식: 늘 null. */
    val boardDragHandler: ((Double, Double) -> Unit)? = null

    /** 조작 버튼(홀드·회전·바로 내리기). INV-GamesTetrisWatch-d54181a2 이식: 늘 비어 있다. */
    val controls: List<String> = emptyList()

    /** [기권] 을 그리는가. INV-GamesTetrisWatch-1174a9d9 이식: 늘 거짓 — 관전자에게는 걸린 판돈이 없다. */
    const val showsResign: Boolean = false

    /** 이 자리를 흐리게 그리는가 — **탑아웃은 서버가 말한 사실**이다(`tetris_players.topped_out`). 시간·결과로 역산하지 않는다. */
    fun dims(side: TetrisSpectateSide): Boolean = side.toppedOut

    /**
     * 로비 줄의 **오른쪽 끝 슬롯이 무엇이든 그리는가** — 입구(위) 또는 관전자 수.
     * INV-GamesTetrisWatch-ce46f243 이식: 줄의 폭 재보기와 슬롯 내용이 **이 하나**를 본다. 조건을 두 곳에 적으면 한쪽만 고쳐져
     *   "빈 슬롯 때문에 줄을 접는" 꼴이 되고, 그 상태가 초록으로 남는다.
     * INV-GamesTetrisWatch-c69879fb 이식: 관전자 수는 **주 스위치와 무관**하다: 로비 응답이 실어 온 사실이고, 관전에 들어갈 수 있는가와는
     *   다른 축이다(스위치가 꺼진 배선에서도 수는 보인다).
     */
    fun hasTrailingContent(store: TetrisDuelStore, live: TetrisDuelLiveMatch): Boolean =
        entry(store, store.isMine(live)) != Entry.absent || GamesWatcherCount.shows(live.watchers)

    // MARK: 탭 — "안 보이는데 ping 한다" 를 0 으로

    /** 관전 판이 **그려지는** 탭인가. 관전 판은 로비 "지금 대결 중" 자리를 갈아 끼우는 절이고 그 자리는 [상대] 탭에만 있다. */
    fun showsWatch(tab: GamesTetrisLobbyTab): Boolean = tab == GamesTetrisLobbyTab.opponents

    /**
     * 로비 탭이 바뀌었다 — **관전 판이 안 보이게 되는 탭으로 가면 관전을 내린다.**
     * 코어의 `shouldPollWatch` 는 **탭을 모른다** — 그래서 아무것도 안 보이는 사람이 2초마다 `tetris_watch_live` 를 쳐서 남의 카드에 관전자
     * 1명으로 잡혔다. 눈에서 사라지는 것과 요청이 끊기는 것을 같은 순간으로 묶는다(돌아와도 관전이 되살아나지 않는다 — 그것이 값이다).
     * `leaveWatch()` 가 문 하나다. 관전 중이 아닐 때는 아무것도 하지 않는다(헛 조회를 내지 않는다).
     */
    fun tabDidChange(store: TetrisDuelStore, tab: GamesTetrisLobbyTab) {
        if (showsWatch(tab) || !store.isSpectating) return
        store.leaveWatch()
    }
}

/**
 * 관전 상태 한 줄의 판정(순수).
 * INV-GamesTetrisWatch-689c68b5 이식: **마감이 지나도 결과를 지어내지 않는다** — `tetris_watch` 는 읽기 전용이라 상한이 지난 판을 닫지
 *   않는다. 그래서 이 판정에는 **시각이 들어오지 않는다**(시각이 바꿀 문구가 없다 = 상태 상자에 타이머가 없다).
 */
object GamesTetrisWatchStatus {
    enum class Kind {
        /** 첫 응답 전(두 판을 아직 모른다). */
        loading,
        live,
        ended,
    }

    fun kind(watch: TetrisSpectateState): Kind = when {
        watch.isFinished -> Kind.ended
        watch.hasServerState -> Kind.live
        else -> Kind.loading
    }

    /** 머리 한 줄. 끝난 판은 **이긴 사람을 3인칭으로** 부른다("밥 승리"). 승자를 모르는 정상 상태 셋에서는 **이름을 지어내지 않는다**. */
    fun headline(watch: TetrisSpectateState): String = when (kind(watch)) {
        Kind.ended -> winnerName(watch)?.let(TetrisPhoneText::watchEndedWin)
            ?: if (watch.result == "draw") TetrisPhoneText.watchEndedDraw else TetrisPhoneText.watchEnded
        Kind.loading -> TetrisPhoneText.watchLoading
        Kind.live -> TetrisPhoneText.playingNow
    }

    /** 이긴 사람의 **부를 수 있는 이름**. 승자를 모르면 null 이고, 승자는 아는데 이름이 비어 있어도 null 이다. */
    fun winnerName(watch: TetrisSpectateState): String? {
        val side = when {
            watch.aWon -> watch.a
            watch.bWon -> watch.b
            else -> return null
        }
        val name = side.user?.displayName ?: ""
        return name.ifEmpty { null }
    }

    /** 자리의 표시 이름. 사람을 모르거나 **이름이 빈 문자열**이면 "—". */
    fun displayName(side: TetrisSpectateSide): String {
        val name = side.user?.displayName ?: ""
        return name.ifEmpty { TetrisPhoneText.watchUnknownName }
    }

    /** 둘째 줄. **끝난 판에만 있다**(진행 중에는 머리 한 줄로 끝 — 지어낼 말이 없다). 사유는 **3인칭**이다. */
    fun detail(watch: TetrisSpectateState): String? {
        if (!watch.isFinished) return null
        return TetrisPhoneText.watchEndReason(watch.endReason).ifEmpty { null }
    }
}

/**
 * 두 판을 나란히 세울 때의 **칸 변(pt) 예산**(순수 — 산수만 잰다).
 * INV-GamesTetrisWatch-9220bc68 이식: **폭만 보면 아래가 잘린다**: 테트리스 판은 세로가 가로의 두 배다(10×20). 폭으로만 칸을 정하면 작은 화면에서
 *   판 높이가 300pt 를 넘어 상태 상자·캡션이 화면 밖으로 밀린다. 그래서 **폭과 높이 둘 다** 보고 작은 쪽을 쓴다.
 */
object GamesTetrisWatchBudget {
    /** 상대 미니 판 테두리 안쪽 여백(Swift `TetrisMiniBoardLayout.inset` — 그리기 파일 TetrisBoardPainter.swift:38, 그리기는 W4-b). */
    const val miniBoardInset: Double = 2.0

    /** 두 판 사이 틈 — `MobileTheme.space3`(12). */
    const val columnGap: Double = 12.0

    /** 칸 변 하한. 이보다 작으면 방해 줄 회색과 조각 색이 구분되지 않는다. */
    const val minimumCell: Double = 5.0

    /** 칸 변 상한. 큰 화면에서 판 두 장이 화면을 통째로 먹지 않게 — 12pt 면 한 판이 124×244 다. */
    const val maximumCell: Double = 12.0

    /** 절 머리: 위 22 + title3 24 + 아래 8 = 54. */
    const val sectionHeader: Double = 22.0 + 24.0 + 8.0

    /**
     * 판 아래 이름·숫자 카드: 이름 줄 21 + 숫자 세 줄(16×3) + 위아래 8씩 = 85.
     * INV-GamesTetrisWatch-c06bc96c 이식: "위아래 8" 은 **8×2** 다(이 표의 `sectionHeader` 만 위 22·아래 8 로 비대칭이다). 이 주석이 유일한
     *   검산표다 — 8pt 틀린 예산을 전제로 상태 상자에 줄을 더하면 접근성 글자에서 판이 하한으로 쪼그라드는 경계가 어긋난다.
     */
    const val playerCard: Double = 21.0 + 16.0 * 3 + 8.0 * 2

    /** 상태 상자: 두 줄(20×2) + 위아래 10 = 60(끝난 판이 두 줄이다). */
    const val statusBox: Double = 20.0 * 2 + 10.0 * 2

    /** 판돈 줄 한 칸: 부제 18 + 위아래 10 = 38. */
    const val stakeRow: Double = 18.0 + 10.0 * 2

    /** 블록 사이 간격 — 8. */
    const val gap: Double = 8.0

    /** 판 위·아래에서 자리를 먹는 블록의 합(간격 포함). 캡션은 세지 않는다 — 스크롤로 닿으면 되는 것이다. */
    fun blocksAroundBoards(): Double {
        val blocks = listOf(sectionHeader, playerCard, statusBox, stakeRow)
        return blocks.sum() + gap * blocks.size
    }

    /**
     * 한 칸 변(pt).
     * @param availableWidth 절이 쓸 수 있는 가로(양옆 여백을 이미 뺀 값).
     * @param viewportHeight 로비 스크롤의 **보이는 높이**(0 이면 아직 모른다 → 폭만 본다).
     */
    fun cell(availableWidth: Double, viewportHeight: Double): Double {
        val inset = miniBoardInset
        val column = maxOf(0.0, (availableWidth - columnGap) / 2)
        var cell = (column - inset * 2) / TetrisGame.columns
        if (viewportHeight.isFinite() && viewportHeight > 0) {
            val budget = viewportHeight - blocksAroundBoards()
            cell = minOf(cell, (budget - inset * 2) / TetrisGame.visibleRows)
        }
        return minOf(maximumCell, maxOf(minimumCell, cell))
    }
}
