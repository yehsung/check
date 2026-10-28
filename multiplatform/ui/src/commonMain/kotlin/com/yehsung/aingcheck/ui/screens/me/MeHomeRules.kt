// 원본: Sources/CheckMobileKit/Me/MeTab.swift @ 3bd04bd (MeStageCard.presence · identity · statusLine · MeMenuGroup 행 · MeAnchor)
// 원본: Sources/CheckMobileKit/Me/MeRecordsViews.swift @ 3bd04bd (MeRecordsPhase · MeRhythmMetrics · MeRhythmSection.caption)
// 원본: Sources/CheckMobileKit/Me/MeMissionsView.swift:40-63 @ 3bd04bd (MeMissionsRow — 루트 [미션] 줄)
//
// 나 탭 루트의 **화면 판정**(순수 — JVM 시험이 닿는다). Composable 은 이 답을 그리기만 한다(E§3 끝 · 기억 ios-views-invisible-to-mac-suite).
package com.yehsung.aingcheck.ui.screens.me

import com.yehsung.aingcheck.core.rules.insights.WorkRhythmHeatmap
import com.yehsung.aingcheck.core.stores.me.MeCharacterCards
import com.yehsung.aingcheck.core.stores.me.MeDestination
import com.yehsung.aingcheck.core.stores.me.MeGrassAxis
import com.yehsung.aingcheck.core.stores.me.MeLoadState
import com.yehsung.aingcheck.core.stores.me.MeStageMood
import com.yehsung.aingcheck.core.stores.me.MeText
import com.yehsung.aingcheck.core.stores.now.NowMyCard
import com.yehsung.aingcheck.ui.components.CharacterMood
import com.yehsung.aingcheck.ui.icons.AppIcon
import kotlin.math.max
import kotlin.math.min

/** 기록 덩어리의 세 상태(Swift `ContributionGridPhase`). */
enum class MeRecordsPhase { Ready, Loading, Failed }

/** 착용 줄의 세 모양(값 · 실패 · 불러오는 중) — 색이 갈린다. */
enum class MeWearKind { Value, Failed, Loading }

/** 메뉴 그룹 한 행(프로필 · 제보 · 설정). */
data class MeMenuRow(
    val destination: MeDestination,
    val title: String,
    val detail: String,
    val icon: AppIcon,
    /** '새 답장' 배지(제보 행만). 서면 보조 글자 대신 배지가 선다. */
    val showsReply: Boolean = false,
)

/**
 * 루트 스크롤 앵커 이름(Swift `MeAnchor`). 이름은 데모 스크린샷 인자다 — 바꾸면 저장소 밖 스크린샷 스크립트가 깨진다.
 * Compose 는 testTag(`me-anchor:<이름>`)로 같은 자리를 연다.
 */
enum class MeAnchor(val raw: String) {
    Header("header"), Records("records"), TokenGrass("tokenGrass"), Characters("characters"), Menu("menu"),
    Rhythm("rhythm"), Missions("missions"), DailyMissions("dailyMissions"), AILimits("aiLimits"),
    ;

    val tag: String get() = "me-anchor:$raw"
}

object MeHomeRules {
    /**
     * 내 근무 상태 → 무대 기분. 지금 탭 내 카드(가장 새 값)가 있으면 그것, 없으면 위젯 스냅숏의 지난 값([snapshotMood]),
     * 둘 다 없으면 null(모름 — 지어내지 않는다). Swift `MeStageCard.presence` 순서 그대로.
     */
    fun presence(card: NowMyCard?, snapshotMood: MeStageMood? = null): MeStageMood? {
        if (card != null) return MeText.stageMood(isWorking = card.isWorking, isStale = card.isStale)
        return snapshotMood
    }

    /** 무대 기분 → 초상 기분(ui). null 은 null(모름). */
    fun characterMood(mood: MeStageMood?): CharacterMood? = when (mood) {
        MeStageMood.working -> CharacterMood.Working
        MeStageMood.lost -> CharacterMood.Lost
        MeStageMood.off -> CharacterMood.Off
        MeStageMood.plain -> CharacterMood.Plain
        null -> null
    }

    /**
     * 무대 제목. 별명 → (프로필을 **받았을 때만**) 이메일 → "나". 못 받은 채(오프라인) 이메일을 제목으로 세우던 결함(통합 검증 E-me)을 되풀이하지 않는다.
     */
    fun identityName(displayName: String?, headerLoaded: Boolean, email: String?): String =
        displayName ?: (if (headerLoaded) email else null) ?: MeText.meFallbackName

    /** 착용 줄: "여우 착용 중" · 실패 문구 · 불러오는 중. */
    fun wearLine(equippedLoaded: Boolean, equippedLoadFailed: Boolean, equippedCharacterID: String): Pair<String, MeWearKind> = when {
        equippedLoaded -> MeText.wearing(MeCharacterCards.displayName(equippedCharacterID)) to MeWearKind.Value
        equippedLoadFailed -> MeText.equippedLoadFailed to MeWearKind.Failed
        else -> MeText.loading to MeWearKind.Loading
    }

    /** 프로필 머리를 **한 번도 못 받았고** 마지막이 실패면 [다시 시도] 줄을 세운다. */
    fun showsHeaderRetry(state: MeLoadState): Boolean = state.hasFailed && !state.hasLoaded

    /** 기록 단계(Swift `MeRecordsPhase.phase`). */
    fun recordsPhase(state: MeLoadState): MeRecordsPhase = when {
        state.hasLoaded -> MeRecordsPhase.Ready
        state.hasFailed -> MeRecordsPhase.Failed
        else -> MeRecordsPhase.Loading
    }

    /** 리듬 칸 아래 한 줄. */
    fun rhythmCaption(phase: MeRecordsPhase, heatmap: WorkRhythmHeatmap): String = when (phase) {
        MeRecordsPhase.Ready -> MeText.rhythmCaption(heatmap)
        MeRecordsPhase.Loading -> MeText.loading
        MeRecordsPhase.Failed -> MeText.recordsFailed
    }

    /** 메뉴 그룹 세 행(순서 = 프로필 · 제보 · 설정). 받을 답장이 있으면 제보 행이 배지를 단다. */
    fun menuRows(hasUnseenFeedbackReply: Boolean): List<MeMenuRow> = listOf(
        MeMenuRow(MeDestination.Profile, MeText.profileTitle, MeText.profileMenuDetail, AppIcon.PersonFill),
        MeMenuRow(MeDestination.Feedback, MeText.feedbackTitle, MeText.feedbackMenuDetail, AppIcon.FeedbackFill, showsReply = hasUnseenFeedbackReply),
        MeMenuRow(MeDestination.Settings, MeText.settingsTitle, MeText.settingsMenuDetail, AppIcon.SettingsFill),
    )

    /**
     * 루트 [미션] 줄의 오른쪽 글자: 받을 것이 있으면 "받을 보상 N개"(탭 막대 배지와 **같은 함수** `missionClaimableCount` 를 지난 수),
     * 없으면 보조 글자. 반쪽 값을 쓰면 배지는 "1"인데 줄은 아무 말도 안 하는 날이 온다(Swift 주석 그대로).
     */
    fun missionsTrailing(missionClaimableCount: Int): Pair<String, Boolean> {
        val hint = MeText.claimPendingHint(missionClaimableCount)
        return if (hint != null) hint to true else MeText.missionsRowDetail to false
    }

    /** 잔디 축 → 상세 목적지. */
    fun grassDestination(axis: MeGrassAxis): MeDestination = MeDestination.Grass(axis)
}

/** 지난주 근무 리듬 격자 치수(Swift `MeRhythmMetrics`). */
object MeRhythmMetrics {
    val markedHours: List<Int> = listOf(0, 6, 12, 18)
    const val GAP: Float = 2f
    const val MAXIMUM_CELL: Float = 13f
    const val LABEL_WIDTH: Float = 18f
    const val HOUR_LABEL_HEIGHT: Float = 15f

    fun cellSize(width: Float, labelWidth: Float = LABEL_WIDTH): Float {
        val columns = WorkRhythmHeatmap.HOUR_COUNT.toFloat()
        val available = width - labelWidth - GAP * (columns - 1)
        return max(3f, min(MAXIMUM_CELL, available / columns))
    }

    fun height(width: Float, labelWidth: Float = LABEL_WIDTH, hourLabelHeight: Float = HOUR_LABEL_HEIGHT): Float {
        val rows = WorkRhythmHeatmap.DAY_COUNT.toFloat()
        val cell = cellSize(width, labelWidth)
        return hourLabelHeight + cell * rows + GAP * (rows - 1)
    }
}

/** 나 탭 화면 글자 중 스토어 문구(MeText)에 없는 것. */
object MeScreenText {
    /** 탭 이름(Swift `AingTab.me.title`) — 큰 제목. */
    const val tabTitle: String = "나"
}
