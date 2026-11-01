// 원본: 없음 — 게임 탭 아잉 큐브 카드의 칩·보조 줄 서열(테트리스 GamesTetrisDuelCard 와 같은 꼴, Sources/CheckMobileKit/Games/GamesTetrisDuelScreen.swift 관례). 맥은 메뉴 배너라 짝이 없다.
package com.yehsung.aingcheck.core.stores.rummy

import com.yehsung.aingcheck.core.stores.games.GamesBusyGame
import com.yehsung.aingcheck.core.stores.games.GamesBusyText
import com.yehsung.aingcheck.core.stores.games.GamesStore
import com.yehsung.aingcheck.core.stores.games.GamesText
import com.yehsung.aingcheck.core.wire.games.RummyMatchStatus

/**
 * 게임 탭 아잉 큐브 카드. 칩과 보조 줄의 **서열은 여기 한 곳**이다(차단 > 내 방·판 > 받은 초대 > 전적 > 기본 한 줄) — 화면이 삼항으로 다시 고르지 않는다.
 * 스토어가 없는 조립(Windows)은 카드를 안 그린다 — 호출자가 `context.rummy` 로 거른다.
 */
object GamesRummyCard {
    enum class Line {
        /** 다른 게임 판이 흐른다 — 카드가 흐려지고 눌리지 않는다. */
        blocked,

        /** 내 큐브 판이 흐른다(결과 화면은 판이 아니다 — `hasLiveRummyMatch`). */
        activeMatch,

        /** 내가 방에 앉아 있다. */
        inRoom,

        /** 받은 초대(잠긴 빌드는 코어가 0 을 낸다). */
        incoming,
        record,

        /** 칩도 보조 줄 재료도 없다 — 할 일을 말한다. */
        idle,
    }

    fun line(store: GamesStore): Line {
        val rummy = store.context.rummy ?: return Line.idle
        if (store.rummyEntryBlock != null) return Line.blocked
        if (store.hasLiveRummyMatch) return if (rummy.match?.status == RummyMatchStatus.forming) Line.inRoom else Line.activeMatch
        if (rummy.pendingIncomingInviteCount > 0) return Line.incoming
        return if ((rummy.lobby?.me?.games ?: 0L) > 0L) Line.record else Line.idle
    }

    /** 칩(없으면 null). 막힌 칩은 두는 판의 이름을 말한다. */
    fun chip(store: GamesStore): String? = when (line(store)) {
        Line.blocked -> GamesBusyText.entryBlock(store.rummyEntryBlock)
        Line.activeMatch -> GamesText.activeMatchChip
        Line.inRoom -> RummyPhoneText.inRoomChip
        Line.incoming -> RummyPhoneText.incomingChip(store.context.rummy?.pendingIncomingInviteCount ?: 0)
        Line.record, Line.idle -> null
    }

    /** 보조 줄(없으면 null). 막혔을 때는 칩이 왜, 이 줄이 언제 풀리는지를 말한다. */
    fun detail(store: GamesStore): String? {
        val me = store.context.rummy?.lobby?.me
        val recordLine = if (me?.games != null) RummyPhoneText.recordTitle + " " + RummyPhoneText.record(me.games, me.wins) else null
        return when (line(store)) {
            Line.blocked -> GamesBusyText.entryBlockHint(store.rummyEntryBlock, GamesBusyGame.rummy)
            // 나가지 못한 자리는 칩만으로 모자란다 — 칩은 앉아 있는 사람에게도 같은 말이다.
            Line.inRoom -> if (store.isRummyLeaveUnconfirmed) RummyPhoneText.leaveUnconfirmedDetail else recordLine
            Line.activeMatch, Line.incoming, Line.record -> recordLine
            Line.idle -> RummyPhoneText.idleLine
        }
    }
}
