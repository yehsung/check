// 원본: Sources/CheckMobileKit/Games/GamesReversiText.swift(카드 절) · Sources/CheckMobileKit/Games/GamesReversiScreen.swift:17-130(GamesReversiCard ·
//       GamesReversiUnavailable · GamesReversiChallengeGate · GamesReversiStakeSend) @ ios-1017-int 91ea495d
package com.yehsung.aingcheck.core.stores.reversi

import com.yehsung.aingcheck.core.stores.games.GamesBusyGame
import com.yehsung.aingcheck.core.stores.games.GamesBusyText
import com.yehsung.aingcheck.core.stores.games.GamesStore
import com.yehsung.aingcheck.core.stores.games.GamesText

// 폰 아잉 뒤집기의 **판정**(게임 탭 카드 한 줄 · 할 수 없음 안내 · [도전] 게이트 · 판돈 보내기 마지막 문)과 카드 문구. 그림(화면 갈래)은 이 값을 받아 그리기만
// 한다 — 판정을 화면에 묻으면 JVM 시험이 값으로 못 잰다(체스 `GamesChessChallengeGate` 머리말과 같은 까닭).
//
// ── 어디까지가 이 표의 몫인가 ── 안내·결과 사유는 코어 [ReversiNoticeText] 가 쥔다(맥과 폰이 같은 서버 응답을 같은 말로 옮긴다). 이 표는 카드에 붙는 글자만.
// ── 상표 ── 게임 이름은 '아잉 뒤집기'뿐이다. '리버시'는 **규칙 설명**으로만 쓴다(부제 — 맥 `ReversiText.subtitle` 과 같은 자리).
// 글자는 iOS 1.0.17 `ReversiPhoneText` 와 한 글자도 다르지 않다.

/** 폰 아잉 뒤집기 카드 문구 표(iOS `ReversiPhoneText` 카드 절). */
object ReversiPhoneText {
    const val title: String = ReversiNoticeText.gameName

    /** 게임 탭 카드 부제 · 로비 머리글 부제(맥 `ReversiText.subtitle` 과 같은 한 줄 — 규칙 · 선공 · 한 수 시간). */
    const val subtitle: String = "리버시 규칙 · 흑 선공 · 한 수 30초"
    const val cardSubtitle: String = subtitle

    /** 게임 탭 카드의 화면 읽기 힌트(막히지 않았을 때). */
    const val cardOpenHint: String = "${ReversiNoticeText.gameName} 대결 화면을 열어요"

    /** 카드 칩: 받은 신청이 있다(몇 건인지는 칩이 말한다 — 탭 배지와 같은 수). */
    fun incomingChip(count: Int): String = "받은 신청 ${count}건"

    /** 카드 보조 줄: 보낸 신청의 답을 기다린다. */
    const val outgoingLine: String = "보낸 신청의 답을 기다리고 있어요"

    /** 칩도 보조 줄 재료도 없을 때의 카드 한 줄(= 할 일을 말한다). AI 연습이 있다는 것도 함께 말한다. */
    const val idleLine: String = "사람을 골라 신청하거나 로봇과 연습해 보세요"

    const val recordTitle: String = "내 전적"

    fun record(wins: Int, losses: Int, draws: Int): String = "${wins}승 ${losses}패 ${draws}무"

    fun record(record: ReversiRecord?): String = if (record == null) record(0, 0, 0) else record(record.wins, record.losses, record.draws)
}

/**
 * 게임 탭 **아잉 뒤집기 카드**가 그리는 한 줄의 판정(칩 + 보조 줄). 서열을 한 열거로 못 박는다(테트리스·큐브 카드와 같은 까닭 — 자리마다 삼항으로 고르면
 * 서열이 두 벌이 되어 한쪽만 고쳐진다): 차단 > 진행 중 판 > 받은 신청 > 보낸 신청 > 전적 > 기본 한 줄. 스토어가 없는 조립은 카드를 세우지 않는다(화면 몫 —
 * `store.reversi == null` 이면 카드 없음).
 */
object GamesReversiCard {
    enum class Line {
        /** 다른 게임 판이 흐른다 — 카드가 흐려지고 눌리지 않는다. */
        blocked,

        /** 내 판이 흐른다(1:1 — 같은 계정 다른 기기의 판 포함 · AI 연습 판은 받은 신청이 없을 때만). */
        activeMatch,
        incoming,
        outgoing,
        record,

        /** 칩도 보조 줄 재료도 없다 — **할 일**을 말한다. */
        idle,
    }

    fun line(store: GamesStore): Line {
        val reversi = store.reversi ?: return Line.idle
        if (store.reversiEntryBlock != null) return Line.blocked
        val incoming = reversi.visibleIncomingInvites.size
        // AI 연습 판은 사람의 신청을 가리지 않는다 — 오목·체스 카드와 같은 규칙(`GamesText.hubShowsActiveMatch`).
        if (GamesText.hubShowsActiveMatch(store.hasActiveReversiMatch, reversi.isAIMatch, incoming)) return Line.activeMatch
        if (incoming > 0) return Line.incoming
        if (reversi.outgoing != null) return Line.outgoing
        return if (reversi.record != null) Line.record else Line.idle
    }

    /** 칩(없으면 null). 막힌 칩은 **두는 판의 이름**을 말한다(문구 표 한 곳이 조립한다 — 화면이 지어내지 않는다). */
    fun chip(store: GamesStore): String? = when (line(store)) {
        Line.blocked -> GamesBusyText.entryBlock(store.reversiEntryBlock)
        Line.activeMatch -> GamesText.activeMatchChip
        Line.incoming -> ReversiPhoneText.incomingChip(store.reversi?.visibleIncomingInvites?.size ?: 0)
        Line.outgoing, Line.record, Line.idle -> null
    }

    /** 보조 줄(없으면 null). 막혔을 때 칩은 왜 막혔는지, 이 줄은 **언제 풀리는지**를 말한다(폰엔 호버 툴팁이 없다). */
    fun detail(store: GamesStore): String? {
        val recordLine = store.reversi?.record?.let { ReversiPhoneText.recordTitle + " " + ReversiPhoneText.record(it) }
        return when (line(store)) {
            Line.blocked -> GamesBusyText.entryBlockHint(store.reversiEntryBlock, GamesBusyGame.reversi)
            Line.activeMatch, Line.incoming, Line.record -> recordLine
            Line.outgoing -> ReversiPhoneText.outgoingLine
            Line.idle -> ReversiPhoneText.idleLine
        }
    }
}

/** 이 기기·서버 조합에서 아잉 뒤집기를 할 수 없다(코어 `availability`) — 로비 대신 세울 안내. 문구는 코어 것이다(맥과 같은 말). 아이콘은 화면 몫. */
object GamesReversiUnavailable {
    fun title(availability: ReversiAvailability): String? = when (availability) {
        ReversiAvailability.available -> null
        ReversiAvailability.updateRequired -> ReversiNoticeText.updateRequired
        ReversiAvailability.serverMissing -> ReversiNoticeText.unavailable
    }
}

/**
 * 상대 줄 [도전] 버튼이 **눌리는가** — 맥 `ReversiPanel` 의 상대 줄 게이트(`isCapable && !inMatch && !focusMode && !isBusy`)에 폰에서 셋을 더한 것이다:
 * 보낸 신청 · 내 판(**AI 연습 포함**) · **다른 게임의 판**(한 사람 한 판, 다섯 방향). Android 는 넷째로 **판돈 대결 빌드 깃발**(G §8-17 #1)을 더한다.
 * ★ `store.match == null` 이 **AI 연습 판까지** 막는 자리다 — 코어 `challenge` 에는 AI 가드가 없어 여기를 열면 1:1 판이 서는 순간 두던 AI 판이 사라진다.
 * ★ `user.isCapable` 은 서버 `capable` 이 **null 이면 false** 다 — 서버 `reversi_android_min_build` 가 닫혀 있으면 안드로이드 상대는 전부 false 다.
 */
object GamesReversiChallengeGate {
    fun isEnabled(user: ReversiUser, store: ReversiStore, blockedBy: GamesBusyGame?): Boolean =
        !store.duelsLocked &&
            blockedBy == null &&
            user.isCapable &&
            !user.inMatch &&
            !user.focusMode &&
            store.outgoing == null &&
            store.match == null &&
            // 서버가 진행 중이라 말한 내 판(같은 계정 다른 기기 · 판을 아직 못 읽음) — 신청은 `busy` 로 돌아온다.
            store.activeMatchID == null &&
            !store.isBusy
}

/**
 * 판돈 시트의 [도전하기] 가 **실제로 요청을 낼 수 있는가**(낼 수 있으면 그 판돈, 못 내면 null). 신청이 나가는 **마지막 문**이라 "버튼이 비활성"이 아니라
 * **요청 0건**을 재야 한다. 게이트가 열린 뒤 상태가 바뀐 틈(시트가 떠 있는 동안 AI 연습을 시작했다 · 다른 기기에서 판이 섰다)을 막는다.
 * 판돈 표(3·5·10)는 서버 CHECK 가 쥔다([ReversiStake]). 잔액을 **모르면 막지 않는다**(맥 0.3.29 규칙 — 서버가 거절하면 그때 안내한다).
 */
object GamesReversiStakeSend {
    fun sendable(selected: ReversiStake?, store: ReversiStore, balance: Long?, blockedBy: GamesBusyGame?): ReversiStake? {
        if (selected == null || store.duelsLocked) return null
        if (!affordable(selected, balance)) return null
        if (store.isBusy || blockedBy != null) return null
        if (store.match != null || store.outgoing != null || store.activeMatchID != null) return null
        return selected
    }

    fun affordable(stake: ReversiStake, balance: Long?): Boolean = balance == null || balance >= stake.rawValue
}
