// 원본: Sources/CheckMobileKit/Rankings/RankingsTab.swift @ 3bd04bd (RankingsStore.myCharacterID · myCharacterMood · RankingsEmptyCard 갈림 · RankingsNameLine.Chip)
// 원본: Sources/CheckMobileKit/Rankings/RankingsBoardSections.swift @ 3bd04bd (빈 카드 · 다시 시도 · 칩 · 메달 · 상품 줄 판정)
//
// 순위 탭의 **화면 판정**(순수 — JVM 시험이 닿는다). Composable 은 이 답을 그리기만 한다.
// **오늘 순위만**(G §8-18 #7): 미니게임 판은 [오늘|역대] 전환이 없다 — 폰 1.0.15 몫(역대 순위)은 이 판에 들어오지 않는다.
// 미니게임 종류는 폰 목록(MiniGameKind.phoneCases)만 — 길건너 아잉이는 숨김(§8-18 #7).
package com.yehsung.aingcheck.ui.screens.rankings

import com.yehsung.aingcheck.core.rules.minigame.MiniGameKind
import com.yehsung.aingcheck.core.stores.now.NowMyCard
import com.yehsung.aingcheck.core.stores.rankings.RankingsBoard
import com.yehsung.aingcheck.core.stores.rankings.RankingsLoadState
import com.yehsung.aingcheck.core.stores.rankings.RankingsText
import com.yehsung.aingcheck.core.wire.CenterLabel
import com.yehsung.aingcheck.ui.components.CharacterMood

/** 빈 목록 자리 한 장: 글자 · [다시 시도] 를 세우는가 · 불러오는 중 돌이를 세우는가. */
data class RankingsEmptyCardState(val text: String, val showsRetry: Boolean, val isLoading: Boolean)

/** 이름 줄 칩(Swift `RankingsNameLine.Chip`). */
enum class RankingsChip { MyTeam, Me, PrivateUsage }

/** 순위의 '나' 행 얼굴: 착용 캐릭터 + 표정(= 지금 근무 상태). */
data class RankingsMyFace(val characterId: String?, val mood: CharacterMood)

/** 메달(1–3 금은동). 4위부터는 null(숫자만). */
enum class RankingsMedal { Gold, Silver, Bronze }

object RankingsScreenRules {
    /** 세그먼트 순서(팀 리그 · AI 토큰 · 미니게임) — 열거 순서 그대로. */
    val boards: List<RankingsBoard> = RankingsBoard.entries

    /** 미니게임 메뉴에 보일 종류 — 폰 목록만(길건너 숨김, §8-18 #7). */
    val miniGameKinds: List<MiniGameKind> = MiniGameKind.phoneCases

    fun leagueEmpty(state: RankingsLoadState, unfilteredCount: Int, isPastWeek: Boolean, leagueIsEmpty: Boolean): RankingsEmptyCardState =
        RankingsEmptyCardState(
            text = RankingsText.leagueEmpty(state.hasLoaded, state.isLoading, state.hasFailed, unfilteredCount, isPastWeek),
            showsRetry = state.hasFailed && !state.isLoading && leagueIsEmpty,
            isLoading = state.isLoading && !state.hasLoaded,
        )

    fun tokenEmpty(state: RankingsLoadState, isCurrentMonth: Boolean): RankingsEmptyCardState = RankingsEmptyCardState(
        text = RankingsText.tokenEmpty(state.hasLoaded, state.isLoading, state.hasFailed, isCurrentMonth),
        showsRetry = state.hasFailed && !state.isLoading && !state.hasLoaded,
        isLoading = state.isLoading && !state.hasLoaded,
    )

    fun miniGameEmpty(state: RankingsLoadState): RankingsEmptyCardState = RankingsEmptyCardState(
        text = RankingsText.miniGameEmptyText(state.hasLoaded, state.hasFailed),
        showsRetry = state.hasFailed && !state.hasLoaded && !state.isLoading,
        isLoading = state.isLoading && !state.hasLoaded,
    )

    /** 목록이 있을 때 위에 거는 경고 한 줄(지난 조회가 실패했다 — 받아 둔 목록은 그대로 보인다). */
    fun showsFailedNotice(state: RankingsLoadState, hasRows: Boolean): Boolean = hasRows && state.hasFailed

    /** 토큰 행 칩: 나 → (내 토큰 공개가 꺼져 있으면) 비공개. */
    fun tokenChips(isMe: Boolean, myTokenUsagePublic: Boolean?): List<RankingsChip> = buildList {
        if (isMe) add(RankingsChip.Me)
        if (isMe && myTokenUsagePublic == false) add(RankingsChip.PrivateUsage)
    }

    /** 나인가 — 내 id 를 모르면 아무도 '나'가 아니다(지어내지 않는다). */
    fun isMe(rowUserID: String, myUserID: String?): Boolean = myUserID != null && rowUserID == myUserID

    fun medal(rank: Int): RankingsMedal? = when (rank) {
        1 -> RankingsMedal.Gold
        2 -> RankingsMedal.Silver
        3 -> RankingsMedal.Bronze
        else -> null
    }

    /**
     * 순위의 '나' 행 얼굴(Swift `RankingsStore.myCharacterID` · `myCharacterMood`). **새 서버 호출 없음** — 나 탭이 이미 알아 온 값, 모르면 위젯
     * 스냅숏의 지난 값(둘 다 없으면 null = 아잉). 표정은 지금 탭 카드 → 없으면 스냅숏 상태 → 모르면 근무 안 함.
     */
    fun myFace(
        meEquippedLoaded: Boolean,
        meEquippedCharacterID: String?,
        snapshotCharacterID: String?,
        nowCard: NowMyCard?,
        snapshotMood: CharacterMood?,
    ): RankingsMyFace {
        val id = if (meEquippedLoaded) meEquippedCharacterID else snapshotCharacterID
        val mood = when {
            nowCard != null -> if (nowCard.isWorking) (if (nowCard.isStale) CharacterMood.Lost else CharacterMood.Working) else CharacterMood.Off
            snapshotMood != null -> snapshotMood
            else -> CharacterMood.Off
        }
        return RankingsMyFace(id, mood)
    }

    /** 상품 아래 정족수 줄 — 사람 수를 **알 때만**(모르면 null: 불러오지 못한 순위를 "아무도 안 했어요"로 말하지 않는다). */
    fun quorumLine(knowsPlayerCount: Boolean, players: Int): String? = if (knowsPlayerCount) RankingsText.quorumCaption(players) else null

    /**
     * 센터 배지에 넘길 **서버값**. 와이어 모델마다 센터 칸이 화면 글자("서울" — 토큰판 toTokenBoardEntries 가 바꾼다)이거나 서버값("seoul" — 리그·미니게임
     * 디코드 그대로)이다. iOS 는 늘 화면 글자를 들고 `CenterLabel.serverValue(forDisplay:)` 로 되돌렸다 — 여기서는 둘 다 받아 한 곳에서 접는다.
     */
    fun centerServerValue(raw: String?): String? =
        CenterLabel.serverValue(forDisplay = raw) ?: raw?.takeIf { CenterLabel.isKnown(it) }

    /** 어제 1등이 루비를 받았으면 그 수(칩), 아니면 null. */
    fun championAward(awarded: Boolean): Int? = if (awarded) RankingsText.rubyPrizes[0] else null
}

/**
 * 프로세스 죽음 뒤 세그먼트 복원 규칙(⑥). 목적지 인자(Dest.RankingsHome.board — 딥링크가 정한 판)는 프로세스 죽음 뒤에도 저장 상태로 돌아오지만
 * 스토어는 새로 만들어져 기본(팀 리그)이다. 화면은 저장한 선택([saved] — rememberSaveable)이 있으면 그것을, 없으면 인자를 스토어에 건다.
 * 사용자가 세그먼트를 바꾸면 [saved] 가 바뀌므로, 딥링크가 연 판에서 다른 판으로 옮긴 뒤 죽어도 옮긴 판으로 돌아온다.
 */
object RankingsBoardRestore {
    fun boardToApply(navArgRaw: String?, saved: String?): RankingsBoard? =
        (saved ?: navArgRaw)?.let { RankingsBoard.fromRaw(it) }
}
