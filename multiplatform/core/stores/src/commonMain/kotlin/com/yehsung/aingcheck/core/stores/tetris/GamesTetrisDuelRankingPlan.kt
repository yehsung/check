// 원본: Sources/CheckMobileKit/Games/GamesTetrisDuelRanking.swift:1-122(GamesTetrisDuelRankingPlan) @ 1b8260d
package com.yehsung.aingcheck.core.stores.tetris

import com.yehsung.aingcheck.core.stores.games.MobileLoadKnowledge

// 1:1 테트리스 **순위 탭**(폰 · D11) — 승점(승 − 패) 순위와 그 안의 내 자리. 0판 제외 · 최대 100행.
//
// ── 왜 로비 안 탭인가 ── 코어 `loadRanking` 은 `rankingEnabled` 와 세션을 요구하고, 그것을 거는 자리들이 전부 **창이 보이고 단계가
// 로비일 때**다. 자식 화면을 쌓으면 테트리스 화면이 사라짐 → `windowDidHide()` 로 폴링이 죽어 값이 갱신되는 자리가 사라진다.
// ── 실패는 이 탭 안에서만 말한다 ── 순위 조회 실패를 안내줄(notice)로 올리지 않는다(코어가 일부러 안 한다).

/** 순위 탭의 **순수 판정**(JVM 시험이 돈다). 색·글꼴은 고르지 않는다 — 화면이 고른다. */
object GamesTetrisDuelRankingPlan {
    /** 탭이 그릴 것. **이 순서로** 본다([content] 머리말). */
    enum class Content {
        rows,

        /** 서버에 `tetris_ranking` 이 아직 없다(PGRST202) — "순위는 곧 열려요". */
        soon,
        empty,
        failed,

        /** 아직 모른다 — 불러오는 중 한 줄. */
        loading,
    }

    /** 접힌 줄 수 · 펼쳤을 때의 상한. **숫자를 다시 적지 않는다** — 문구 표가 한 출처다. */
    val collapsedRows: Int get() = TetrisPhoneText.rankCollapsedRows
    val rowLimit: Int get() = TetrisPhoneText.rankRowLimit

    /**
     * INV-GamesTetrisDuelRanking-c2bc59d0 이식: **0판인 사람은 안 낀다**(D11). 서버 `tetris_ranking` 이 이미 걸러 주지만 그 약속을 화면이 다시
     * 지킨다 — 0승 0패 0무 줄은 순위표에 아무 정보도 주지 않고, 서버가 한 번 느슨해지면 순위표가 통째로 그 줄로 덮인다.
     */
    fun playable(entries: List<TetrisDuelRankEntry>): List<TetrisDuelRankEntry> = entries.filter { it.wins + it.losses + it.draws > 0 }

    /** 들고 있는 순위 행. **재정렬하지 않는다** — 서버 순서가 권위다. 거르고 자르기만 한다. */
    fun held(store: TetrisDuelStore): List<TetrisDuelRankEntry> = playable(store.ranking?.entries ?: emptyList())

    fun visible(store: TetrisDuelStore, isExpanded: Boolean): List<TetrisDuelRankEntry> =
        held(store).take(if (isExpanded) rowLimit else collapsedRows)

    fun total(store: TetrisDuelStore): Int = minOf(held(store).size, rowLimit)

    fun showsToggle(store: TetrisDuelStore): Boolean = total(store) > collapsedRows

    /**
     * INV-GamesTetrisDuelRanking-6e285014 이식: **분기 순서**: 행 → 준비 중 → 빈·실패·로딩.
     * ① **행 갈래가 맨 앞이다.** `rankingUnavailable` 을 먼저 보면 순위를 받아 둔 채 그 깃발이 남아 있는 창에서 들고 있는 행을 버리고
     *   "곧 열려요"를 말한다. ② **준비 중(`soon`)은 `placeholder` 보다 먼저** 본다 — 코어가 PGRST202 창을 "받은 것"으로 세기 때문에
     *   `placeholder` 는 `.failed` 가 아니라 **`.empty`** 로 떨어진다.
     */
    fun content(store: TetrisDuelStore): Content {
        if (held(store).isNotEmpty()) return Content.rows
        if (store.rankingUnavailable) return Content.soon
        return when (MobileLoadKnowledge.placeholder(false, store.hasLoadedRanking, store.rankingLoadFailed)) {
            // 닿지 않는다 — hasRows false 로 계산했다. 사실이 아닌 값을 꾸미지 않고 로딩으로 접는다.
            MobileLoadKnowledge.Placeholder.rows -> Content.loading
            MobileLoadKnowledge.Placeholder.empty -> Content.empty
            MobileLoadKnowledge.Placeholder.failed -> Content.failed
            MobileLoadKnowledge.Placeholder.loading -> Content.loading
        }
    }

    /**
     * 목록 **밖**의 내 순위.
     * INV-GamesTetrisDuelRanking-01980e3d 이식: 순위 응답의 `me` 와 **로비 전적이 어긋나면 그리지 않는다**(한쪽이 늦었다는 뜻이다). 섞으면
     *   "8승 3패 · 승점 +4" 같은 자기모순 문장이 뜬다. 전적을 **아직 모르면** 막지 않는다(그때는 어긋남을 말할 근거가 없다).
     */
    fun myRank(store: TetrisDuelStore): TetrisDuelMyRank? {
        val mine = store.ranking?.me ?: return null
        val record = store.record ?: return mine
        if (record.wins != mine.wins || record.losses != mine.losses || record.draws != mine.draws) return null
        return mine
    }

    /** 머리 오른쪽 캡션. **한 번도 못 받았으면 아무것도 말하지 않는다** — 컷을 모르는데 "전체 기간"은 거짓이다. */
    fun sinceCaption(store: TetrisDuelStore, sinceText: (com.yehsung.aingcheck.core.wire.SwiftDate) -> String = { TetrisPhoneText.rankSince(it) }): String? {
        val ranking = store.ranking ?: return null
        return ranking.recordSince?.let(sinceText) ?: TetrisPhoneText.rankWholePeriod
    }

    /**
     * 순위 탭을 고른 그 순간의 조회(60초 스로틀은 코어가 쥔다 — `refreshRankingIfStale`).
     * INV-GamesTetrisDuelRanking-d2ecec2e 이식: **단계 가드가 이 함수의 알맹이다.** 판이 흐르는 동안 순위를 당기면 ① 판 보고와 같은 연결을 두고
     *   다투고 ② 코어 폴링도 로비 단계에서만 당기므로 두 자리가 갈린다. 순위 **탭이 아닐 때는** 쏘지 않는다.
     */
    fun shouldRefresh(store: TetrisDuelStore, tab: GamesTetrisLobbyTab): Boolean =
        store.rankingEnabled && tab == GamesTetrisLobbyTab.ranking && store.phase == TetrisDuelPhase.lobby

    fun refreshIfNeeded(store: TetrisDuelStore, tab: GamesTetrisLobbyTab) {
        if (!shouldRefresh(store, tab)) return
        store.refreshRankingIfStale()
    }
}
