// 원본: Sources/CheckMobileKit/Games/GamesTetrisDuelScreen.swift:1-184(판정 — 탭 · 카드 · 신청 게이트 · 판돈 보내기 · 판돈 고르기 · 못 쓰는 기기) @ 1b8260d
// (수락 게이트 GamesTetrisDuelAcceptGate 는 원본 없음 — G §8-17 #1 판돈 대결 빌드 깃발의 Android 몫.)
package com.yehsung.aingcheck.core.stores.tetris

import com.yehsung.aingcheck.core.stores.games.GamesBusyGame
import com.yehsung.aingcheck.core.stores.games.GamesBusyText
import com.yehsung.aingcheck.core.stores.games.GamesStore
import com.yehsung.aingcheck.core.stores.games.GamesText

// 폰 1:1 테트리스 **화면 하나**(설계서 P6) — 로비 · 대결 · 결과를 한 화면이 갈아 끼운다. 본은 폰 체스이고, 테트리스에서 달라지는 자리만 바꿨다.
//
// 아래 **판정**(카드 · 신청 게이트 · 판돈 보내기 · 판돈 고르기)은 화면(W4-b Compose) **밖**에 있다. 화면 안에 판정을 묻어 두면 "판돈을 안
// 골랐는데 신청이 나갔다"·"칩 서열이 뒤집혔다" 를 재는 그물을 걸 자리가 없다. 그림(화면)은 판정을 받아 그리기만 한다.
//
// 수명은 **직접 코어를 부르지 않는다** — 화면이 나타남 → `GamesStore.tetrisScreenDidAppear()`, 사라짐 → `…DidDisappear()` 뿐이다.
//
// G §8-17 #1(Android): 판돈 대결의 **신청·수락 진입**은 `duelsEnabled` 가 켜진 빌드에서만 선다. 꺼진 빌드는 신청 게이트·판돈 보내기·
// 수락 게이트가 모두 닫히고(요청 0건 — 스토어도 같은 깃발로 막는다), 카드는 받을 수 없는 신청을 칩으로 내세우지 않는다.
// 관전·순위·전적은 깃발과 무관하다.

/**
 * 로비 안 탭 둘(설계서 P6).
 * INV-GamesTetrisDuelScreen-b9e8b768 이식: **자식 화면이 아니라 탭**이다: 자식 라우트를 쌓으면 이 화면이 사라짐 → `windowDidHide()` 로
 *   폴링이 죽어 순위·로비가 갱신되지 않는다(오목·체스에서 실증된 자리).
 */
enum class GamesTetrisLobbyTab {
    opponents, ranking;

    val title: String
        get() = when (this) {
            opponents -> TetrisPhoneText.usersTab
            ranking -> TetrisPhoneText.rankTab
        }
}

/**
 * 게임 탭 **1:1 테트리스 카드**가 그리는 한 줄의 판정(칩 + 보조 줄).
 *
 * INV-GamesTetrisDuelScreen-46e24d31 이식: **서열을 한 열거로 못 박는다**([Line]). 칩과 보조 줄을 자리마다 삼항으로 고르면 서열이 두 벌이
 *   되어 한쪽만 고쳐지고, 그 상태가 **초록인 채로** 남는다. 서열은 설계서 P2: 차단 > 진행 중 판 > 받은 신청 > 보낸 신청 > 전적 > 기본 한 줄.
 */
object GamesTetrisDuelCard {
    /** 카드가 지금 말하는 **한 가지**. 서열이 뒤집히면 이 값이 바뀐다. */
    enum class Line {
        /** 다른 게임 판이 흐른다 — 카드가 흐려지고 눌리지 않는다. */
        blocked,

        /** 내 테트리스 판이 흐른다(결과 카드는 판이 아니다 — `hasActiveTetrisMatch`). */
        activeMatch,
        incoming,
        outgoing,
        record,

        /** 칩도 보조 줄 재료도 없다 — **할 일**을 말한다. */
        idle,
    }

    fun line(store: GamesStore): Line {
        // ① 차단이 맨 앞이다. 다른 게임 판이 흐르는 동안 이 카드를 열어 두면 로비 [수락]으로 테트리스가 서고 흐르던 판이 조용히 시간패한다.
        if (store.tetrisEntryBlock != null) return Line.blocked
        // ② 내 판이 흐르면 그것이 가장 급한 사실이다(받은 신청보다 먼저 — 판돈이 걸려 있다).
        if (store.hasActiveTetrisMatch) return Line.activeMatch
        // ③ 받은 신청 — Android 는 **수락할 수 있는 빌드에서만** 내세운다(§8-17 #1). 꺼진 빌드에서 칩을 세우면 눌러도 수락할 문이 없다.
        if (store.tetris.duelsEnabled && store.tetris.visibleIncoming != null) return Line.incoming
        if (store.tetris.outgoing != null) return Line.outgoing
        return if (store.tetris.record != null) Line.record else Line.idle
    }

    /** 칩(없으면 null). 막힌 칩은 **두는 판의 이름**을 말한다(막힘 문구 표 한 곳이 조립한다 — 화면이 지어내지 않는다). */
    fun chip(store: GamesStore): String? = when (line(store)) {
        Line.blocked -> GamesBusyText.entryBlock(store.tetrisEntryBlock)
        Line.activeMatch -> GamesText.activeMatchChip
        Line.incoming -> TetrisPhoneText.incomingChip
        Line.outgoing, Line.record, Line.idle -> null
    }

    /**
     * 보조 줄(없으면 null).
     * INV-GamesTetrisDuelScreen-2cd896dd 이식: 막혔을 때 **두 자리를 다 그린다**: 칩은 왜 막혔는지, 이 줄은 **언제 풀리는지**를 말한다.
     *   한 자리만 그리면 사용자가 기다릴 끝을 모른다(폰엔 호버 툴팁이 없다).
     */
    fun detail(store: GamesStore): String? {
        val recordLine = store.tetris.record?.let { TetrisPhoneText.recordTitle + " " + TetrisPhoneText.record(it) }
        return when (line(store)) {
            Line.blocked -> GamesBusyText.entryBlockHint(store.tetrisEntryBlock, GamesBusyGame.tetris)
            // 칩이 급한 사실을 말했으니 이 줄은 전적이다(모르면 비운다 — 꾸미지 않는다).
            Line.activeMatch, Line.incoming -> recordLine
            Line.outgoing -> TetrisPhoneText.outgoingLine
            Line.record -> recordLine
            Line.idle -> TetrisPhoneText.idleLine
        }
    }
}

/**
 * 상대 줄 [신청] 버튼이 **눌리는가**. 체스 게이트와 같은 자리·같은 뜻이고, 테트리스에는 로봇 판이 없어 가를 것이 하나 적은 대신
 * **집중 모드**가 있다(서버 `target_focused`). Android 는 판돈 대결 빌드 깃발(§8-17 #1)을 먼저 본다.
 *
 * INV-GamesTetrisDuelScreen-533e4110 이식: `user.canBeChallenged` 를 그대로 쓴다(코어 한 곳 — `isCapable && !inMatch && !isFocused`).
 *   여기서 세 조건을 다시 적으면 서버가 축을 하나 더하는 날 두 벌이 갈린다.
 */
object GamesTetrisDuelChallengeGate {
    fun isEnabled(user: TetrisDuelUser, store: TetrisDuelStore, blockedBy: GamesBusyGame?): Boolean =
        store.duelsEnabled &&
            blockedBy == null &&
            user.canBeChallenged &&
            store.outgoing == null &&
            // 내 판이 있으면(끝난 판이어도 결과 카드가 떠 있는 상태다) 로비가 화면에 없다 — 열려 있으면 그 사이 들어온 로비 응답으로
            // 버튼이 되살아날 수 있다.
            store.match == null &&
            !store.isBusy
}

/**
 * 판돈 시트의 [신청] 이 **실제로 요청을 낼 수 있는가**(낼 수 있으면 그 판돈, 못 내면 null).
 *
 * INV-GamesTetrisDuelScreen-12b3ff2e 이식: 왜 화면이 아니라 여기 있나: 신청이 나가는 **마지막 문**이라 "버튼이 비활성"이 아니라
 *   **요청 0건**을 재야 하고, 화면은 JVM 시험이 못 본다. 특히 **아무것도 안 고른 채**(null)가 null 로 떨어지는 것이 설계 결정이다.
 */
object GamesTetrisDuelStakeSend {
    fun sendable(selected: TetrisDuelStake?, store: TetrisDuelStore, balance: Int?, blockedBy: GamesBusyGame?): TetrisDuelStake? {
        if (selected == null || !store.duelsEnabled) return null
        if (!GamesTetrisStakeSelection.affordable(selected, balance)) return null
        if (store.isBusy || blockedBy != null) return null
        // 게이트가 열린 뒤 상태가 바뀐 틈을 막는다(시트가 떠 있는 동안 판이 서거나 신청이 나갔다).
        if (store.match != null || store.outgoing != null) return null
        return selected
    }
}

/**
 * 받은 신청 카드의 [수락] 이 **눌리는가**(G §8-17 #1 — Android 만의 문. Swift 화면은 수락 버튼을 늘 그리고 서버·한 사람 한 판이 막는다).
 * 깃발이 꺼진 빌드는 수락 진입을 세우지 않는다(스토어 `respond(accept=true)` 도 요청 0건이다 — 짝). [거절] 은 판돈이 움직이지 않아 막지 않는다.
 * 다른 게임 판이 흐르면 수락도 막는다(오목 서버 게이트는 테트리스를 모른다 — 한 사람 한 판).
 */
object GamesTetrisDuelAcceptGate {
    fun isEnabled(store: TetrisDuelStore, blockedBy: GamesBusyGame?): Boolean =
        store.duelsEnabled && blockedBy == null && store.match == null && !store.isBusy
}

/** 판돈 고르기(체스와 같은 규약 — 고른 판돈을 다시 누르면 해제 · **잔액을 모르면 막지 않는다**). 판돈 표(3·5·10)의 주인은 서버 CHECK 다. */
object GamesTetrisStakeSelection {
    fun toggled(current: TetrisDuelStake?, tapped: TetrisDuelStake): TetrisDuelStake? = if (current == tapped) null else tapped

    /** 이 판돈을 걸 수 있는가. **잔액을 모르면(null) 막지 않는다** — 서버가 거절하면 그때 안내한다. */
    fun affordable(stake: TetrisDuelStake, balance: Int?): Boolean = balance == null || balance >= stake.rawValue
}

/** 이 기기가 지금 대결을 할 수 없다(코어 `availability`) — 로비 대신 세울 안내. **문구는 코어 것**이다(맥과 같은 말이어야 한다). */
object GamesTetrisDuelUnavailable {
    fun title(availability: TetrisDuelAvailability): String? = when (availability) {
        TetrisDuelAvailability.available -> null
        TetrisDuelAvailability.updateRequired -> TetrisDuelNoticeText.updateMine
        TetrisDuelAvailability.serverMissing -> TetrisDuelNoticeText.unavailable
    }

    /** SF Symbol 이름(Material Symbols 대응은 ui 의 SfSymbols 표). */
    fun icon(availability: TetrisDuelAvailability): String = if (availability == TetrisDuelAvailability.updateRequired) "arrow.up.circle" else "clock"
}
