// 원본: Sources/check/CheckMenuView.swift 3001-3012(UltraChargeStyle.holdSeconds) · 3040-3095(UltraBalanceText) · 3288-3293(PokeDirectoryEmptyMessage)
//       · 3502-3533(PokePanelOrder · PokeRowUnreadMark) · 3817(MessageAnytimeNotice.pokeOffWork) · 3825-3893(PokePanelNoticeLine.line)
//       · 4031-4053(찌르기 단추 네 갈래) · CheckComponents.swift 1615(PokeConnectionNotice.panelText)
//       · WorkTimerStoreBlocks.swift 130-134(visiblePokeDirectory) · WorkTimerStorePoke.swift 69-99(디렉터리 30초 갱신·정렬) @ 35649bee
// W3-c3 콕 목록 순수 규칙. 정렬은 core sortedForPokeDisplay(네 무리), 쿨타임 잔여는 feature DesktopPokeRules.cooldownRemaining 을 쓴다.
package com.yehsung.aingcheck.desktop.pages.poke

import com.yehsung.aingcheck.core.foundation.platform.Collation
import com.yehsung.aingcheck.core.wire.models.PokeDirectoryEntry
import com.yehsung.aingcheck.core.wire.models.sortedForPokeDisplay
import com.yehsung.aingcheck.desktop.pages.focus.FocusModeText
import com.yehsung.aingcheck.desktop.shellapi.FlyoutRoute
import com.yehsung.aingcheck.feature.desktop.DesktopAppConfig
import com.yehsung.aingcheck.feature.desktop.focus.FocusStage

/** 깃발 → 보일 표면(W-6 #1 · W-9 3차 #2: 꺼진 기능의 라우트·레일 칸이 숨는 판정을 페이지 쪽이 낸다). */
data class SocialSurfaces(
    /** 콕 목록 라우트·레일 [콕] 칸. */
    val pokeList: Boolean,
    /** 행 단추 3초 꾹 = 울트라(ultra_poke_user). poke·ultra 둘 다 켜져야 한다(발신자는 poke 가 만든다). */
    val ultraPoke: Boolean,
    /** 울트라 화면 라우트(구매 진입 — W-3 #15). */
    val ultraPage: Boolean,
    /** 울트라 사기(buy_ultra). */
    val ultraPurchase: Boolean,
    /** 지갑 잔량 숫자(콕 목록 제목 배지 · 울트라 화면). */
    val walletBalance: Boolean,
    /** 집중 모드 단추 — 맥처럼 콕 목록 제목 행에만 선다. */
    val focusControl: Boolean,
)

object SocialPageFlags {
    /**
     * 이 갈래 라우트 중 보일 것. poke=false → 콕 목록 숨김(그 안의 울트라 콕도), ultra=false → 울트라 화면(구매·발신) 숨김.
     * SharedRouter.isEnabled 와 같은 답이어야 한다(시험이 네 조합을 견준다).
     */
    fun visibleRoutes(config: DesktopAppConfig): Set<FlyoutRoute> = buildSet {
        if (config.poke) add(FlyoutRoute.PokeList)
        if (config.ultra) add(FlyoutRoute.Ultra)
    }

    /**
     * 표면 판정. 지갑 잔량은 **맥과 같게** — 맥은 깃발 없이, 잔량을 보이는 두 자리(콕 목록 제목 배지 · 울트라 화면)가 서 있으면 늘 그린다.
     * Windows 에서 그 두 자리는 ultra 깃발 뒤에 있다(배지의 문구는 "3초 꾹 = 울트라", 누르면 울트라 화면) — 그래서 잔량 = ultra.
     * 지갑 sync 자체는 깃발과 무관하게 돈다(W-6 #1 — SocialWiring) — 숫자를 안 그릴 뿐 서버 몫은 받는다.
     */
    fun surfaces(config: DesktopAppConfig): SocialSurfaces = SocialSurfaces(
        pokeList = config.poke,
        ultraPoke = config.poke && config.ultra,
        ultraPage = config.ultra,
        ultraPurchase = config.ultra,
        walletBalance = config.ultra,
        focusControl = config.poke,
    )
}

/** 찌르기 단추 네 갈래(Swift 4031-4053 순서 그대로: 쿨타임 > 내 비근무 > 대상 자리비움 > 가능). 가능 말고는 단추가 아니다(제스처 대상 없음). */
enum class PokeButtonState(val tooltip: String?) {
    COOLDOWN("잠시 후 다시 찌를 수 있어요"),
    MYSELF_OFF_WORK("내가 근무 중일 때만 콕 찌를 수 있어요"),
    TARGET_AWAY("자리비움 상태에는 찌를 수 없어요"),
    READY(null),
}

/** 행 말풍선 단추의 안 읽음(Swift PokeRowUnreadMark). */
enum class PokeRowUnreadMark {
    NONE, MESSAGES, POKES_ONLY;

    val showsDot: Boolean get() = this != NONE

    fun tooltip(name: String): String = when (this) {
        NONE -> "${name}님과의 대화 열기"
        MESSAGES -> "${name}님과의 대화 — 안 읽은 메시지가 있어요"
        POKES_ONLY -> "${name}님과의 대화 — 안 본 찌르기가 있어요"
    }

    companion object {
        fun of(userID: String, unreadMessagePeerIDs: Set<String>, unreadPokePeerIDs: Set<String>): PokeRowUnreadMark = when (userID) {
            in unreadMessagePeerIDs -> MESSAGES
            in unreadPokePeerIDs -> POKES_ONLY
            else -> NONE
        }
    }
}

/** 안내줄 한 줄(경고면 주황). */
data class PokeNoticeLine(val text: String, val isWarning: Boolean)

object PokeListRules {
    /** 화면이 열려 있는 동안 디렉터리 다시 읽기(초 — 맥 refresh 루프). 닫히면 0건. */
    const val DIRECTORY_REFRESH_SECONDS: Double = 30.0

    const val TITLE: String = "콕 찌르기"
    const val NO_OTHERS: String = "아직 다른 사용자가 없어요"
    const val LOADING: String = "불러오는 중…"
    const val POKE_OFF_WORK: String = "콕 찌르기는 근무 중에만 · 메시지는 언제든 보낼 수 있어요"
    const val DISCONNECTED: String = "찌르기 연결이 끊겼어요 — 새로고침을 눌러 보세요"
    const val WORKING_CHIP: String = "근무중"
    const val AWAY_CHIP: String = "자리비움"

    /**
     * 화면에 세울 사람. 서버(app_user_directory)가 이미 나와 차단 사이를 빼지만, 맥은 차단 직후(재조회 전) 숨김 집합으로 한 번 더 거른다
     * (visiblePokeDirectory). 나 자신은 서버가 빼는 것을 믿되 같은 자리에서 한 번 더 거른다(대소문자 무시 — uuid 표기 차이).
     * 정렬은 화면 몫(안 읽음 → 근무중 → 이름 → id, core sortedForPokeDisplay · workKnown=true).
     */
    fun visibleEntries(
        directory: List<PokeDirectoryEntry>,
        myUserID: String?,
        hiddenBlockedPeerIDs: Set<String>,
        unreadMessagePeerIDs: Set<String>,
        unreadPokePeerIDs: Set<String>,
        collation: Collation,
    ): List<PokeDirectoryEntry> = directory
        .filter { e -> e.userID !in hiddenBlockedPeerIDs && (myUserID == null || !e.userID.equals(myUserID, ignoreCase = true)) }
        .sortedForPokeDisplay(unreadMessagePeerIDs + unreadPokePeerIDs, workKnown = true, collation = collation)

    fun buttonState(remainingCooldown: Int, isMyselfWorking: Boolean, targetWorking: Boolean): PokeButtonState = when {
        remainingCooldown > 0 -> PokeButtonState.COOLDOWN
        !isMyselfWorking -> PokeButtonState.MYSELF_OFF_WORK
        !targetWorking -> PokeButtonState.TARGET_AWAY
        else -> PokeButtonState.READY
    }

    /** Swift PokePanelNoticeLine.line — 연결 끊김 > 메시지 안내 > 찌르기 안내 > 내 비근무(회색) > 집중 단계(회색) > 없음. */
    fun noticeLine(disconnected: Boolean, messageNotice: String?, notice: String?, isMyselfWorking: Boolean, focusStage: FocusStage): PokeNoticeLine? {
        if (disconnected) return PokeNoticeLine(DISCONNECTED, true)
        if (!messageNotice.isNullOrEmpty()) return PokeNoticeLine(messageNotice, true)
        if (!notice.isNullOrEmpty()) return PokeNoticeLine(notice, true)
        if (!isMyselfWorking) return PokeNoticeLine(POKE_OFF_WORK, false)
        return FocusModeText.pokeNotice(focusStage)?.let { PokeNoticeLine(it, false) }
    }

    /** 로드 성공했는데 비면 '아직 아무도 없음', 로드 전·실패면 [fallbackStatus]. */
    fun emptyText(hasLoaded: Boolean, fallbackStatus: String): String = if (hasLoaded) NO_OTHERS else fallbackStatus

    /** 행 높이(맥: 상태메시지가 있으면 62, 없으면 48). */
    fun rowHeightDp(entry: PokeDirectoryEntry): Int = if (entry.statusMessage.isNullOrEmpty()) 48 else 62
}

/** 울트라 잔량 배지·힌트 문구(Swift UltraBalanceText · UltraChargeStyle). */
object UltraBalanceText {
    const val HOLD_SECONDS: Double = 3.0
    const val UNLIMITED_BADGE: String = "∞"
    const val BADGE_MAX_NUMBER: Long = 99
    const val OVERFLOW_BADGE: String = "99+"
    const val EMPTY: String = "상점에서 사기"

    val holdSecondsText: String get() = if (HOLD_SECONDS == kotlin.math.floor(HOLD_SECONDS)) HOLD_SECONDS.toInt().toString() else HOLD_SECONDS.toString()
    val discover: String get() = "${holdSecondsText}초 꾹 = 울트라"
    val discoverShort: String get() = "${holdSecondsText}초 꾹"

    /** 잔량을 모르면 "—"(숫자를 지어내지 않는다). */
    fun badge(balance: Long?, unlimited: Boolean = false): String {
        if (unlimited) return UNLIMITED_BADGE
        val value = balance?.coerceAtLeast(0) ?: return "—"
        return if (value > BADGE_MAX_NUMBER) OVERFLOW_BADGE else value.toString()
    }

    fun badgeOverflows(balance: Long?, unlimited: Boolean = false): Boolean =
        !unlimited && balance != null && balance.coerceAtLeast(0) > BADGE_MAX_NUMBER

    fun hint(balance: Long?, unlimited: Boolean = false): String {
        if (unlimited) return discover
        if (balance == null) return discover
        if (balance <= 0) return EMPTY
        return if (badgeOverflows(balance)) discoverShort else discover
    }

    /** 가능 단추의 툴팁. 울트라 발신이 꺼진 빌드는 꾹 누르기가 없다 — 그 말을 하지 않는다. */
    fun rowTooltip(balance: Long?, unlimited: Boolean, ultraPoke: Boolean): String = when {
        !ultraPoke -> "콕 찌르기"
        unlimited || (balance ?: 1) > 0 -> "콕 찌르기 (${holdSecondsText}초 꾹 누르면 울트라)"
        else -> "콕 찌르기 (울트라 없음 — 상점에서 루비로)"
    }
}
