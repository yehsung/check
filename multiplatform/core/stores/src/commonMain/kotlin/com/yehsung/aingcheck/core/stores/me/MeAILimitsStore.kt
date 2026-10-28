// 원본: Sources/CheckMobileKit/Me/MeAILimitsStore.swift · Sources/CheckMobileShared/AILimitSurfaceRules.swift:28-42(AILimitGhostRow) · Sources/CheckMobileShared/WidgetSnapshot.swift:176-211 · 224-273(AILimitRow · AILimitPanel — 값 모양만, 디코더 init(from:) 은 위젯 갈래 W2-f) @ 1b8260d
package com.yehsung.aingcheck.core.stores.me

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import com.yehsung.aingcheck.core.net.AuthErrorDisposition
import com.yehsung.aingcheck.core.net.AuthErrorRules
import com.yehsung.aingcheck.core.net.fetchAILimitMainDeviceID
import com.yehsung.aingcheck.core.rules.ailimit.AILimitDevice
import com.yehsung.aingcheck.core.rules.ailimit.AILimitDeviceNameParts
import com.yehsung.aingcheck.core.rules.ailimit.AILimitDeviceObservation
import com.yehsung.aingcheck.core.rules.ailimit.AILimitDeviceRoster
import com.yehsung.aingcheck.core.rules.ailimit.AILimitDisplay
import com.yehsung.aingcheck.core.rules.ailimit.AILimitFreshnessRule
import com.yehsung.aingcheck.core.rules.ailimit.AILimitMainDeviceRule
import com.yehsung.aingcheck.core.rules.ailimit.AILimitProvider
import com.yehsung.aingcheck.core.rules.ailimit.AILimitProviderSnapshot
import com.yehsung.aingcheck.core.rules.ailimit.AILimitSnapshotBundle
import com.yehsung.aingcheck.core.rules.ailimit.AILimitSource
import com.yehsung.aingcheck.core.rules.ailimit.AILimitWindow
import com.yehsung.aingcheck.core.rules.ailimit.AILimitWindowSnapshot
import com.yehsung.aingcheck.core.rules.insights.TokenDailyGrid
import com.yehsung.aingcheck.core.rules.insights.WorkRhythmHeatmap
import com.yehsung.aingcheck.core.wire.SwiftDate
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

// AI 리밋 스토어(v0.3.47 — 폰 · 기기별).
// **하는 것**: `ai_limits` 에서 내 행만 읽어 **기기별로 묶고**, 기기 안에서 제공자별 최신 관측을 고르고, 코어 규칙(AILimitFreshnessRule)에
// 통과시켜 카드가 그릴 값을 내놓고, **메인 맥 하나의** 값을 위젯 패널 모양으로 바꿔 지금 탭에 넘긴다. 요청은 **맥이 한 대면 GET 하나**다 —
// 둘 이상일 때만 `ai_limits_prefs` 를 한 번 더 묻고, 그 조회는 실패해도 카드를 비우지 않는다.
// INV-MeAILimitsStore-311fb541 이식: v0.3.47 에서 바뀐 것 하나 — **기기를 접지 않는다**. 0.3.46 까지는 "제공자당 observed_at 이 가장 최신인 행 하나"를
//   골라 두 맥을 한 줄로 뭉갰다 → ① 맥 A 에서 끈 제공자가 되살아나고 ② 누구 값인지 말하지 않았다. 지금은 맥 둘 이상이면 기기 이름으로 묶어
//   **전부** 보여 주고(한 대면 이름 없이), 위젯은 좁으니 **메인 맥 하나**만. 토큰은 **합산 유지**(2026-10-08 사용자 결정).
// INV-MeAILimitsStore-de81f96a 이식: 기기 목록·이름·순서·기본 선택의 규칙은 **코어에 한 벌**이다(AILimitDeviceRoster · AILimitMainDeviceRule) —
//   설정 고르개가 가리키는 맥과 폰이 그리는 맥이 갈리면 그 어긋남은 조용하다. 이 파일에는 그 규칙의 **사본이 없다**.
// **안 하는 것**(구조로 막혀 있다): 제공자 API 직접 호출(이 파일의 호스트는 Supabase 뿐) · `ai_limits` 쓰기 · `ai_limits_prefs` 쓰기(고르개는
//   데스크톱 설정에만 — 폰이 쓰면 "어느 맥에서 바꿔도 같은 한 값"이 깨진다; 시험이 쓰기 0 을 센다) · 폴링 · 위젯 스냅숏 직접 쓰기(값만 넘긴다).
// 왜 MeStore 안이 아니라 별 스토어인가: 리밋은 토큰과 **다른 축**이다 — 한 recordsState 를 공유하면 "토큰 조회가 실패하면 리밋도 사라진다".
// 늦은 응답 가드 셋: 세대 · 요청 순번 · 사용자 도장(userID).

/**
 * 서버에 남아 **영원히 늙는** 행을 목록에서 가리는 문턱(3일). 폰 카드와 위젯이 **이 한 상수**를 쓴다(위젯 — W2-f — 은 이 모듈을 본다:
 * stores ← feature). 위젯은 그리는 칸 시각으로 **다시** 재야 한다(쓸 때는 안 유령이어도 그릴 때는 유령인 창이 열린다).
 */
object AILimitGhostRow {
    const val maxObservationAge: Double = 3.0 * 86_400

    /** 미래 시각은 여기서 가리지 않는다(기기 시계 어긋남 — 코어 규칙이 unknown 으로 판정한다). 재는 것은 '너무 오래됐나' 하나다. */
    fun isGhost(observedAt: SwiftDate, now: SwiftDate): Boolean = now.timeIntervalSince(observedAt) >= maxObservationAge
}

/** 제공자 한 줄이 그릴 것. 값·캡션·표시여부는 **전부 코어 규칙에서** 나온다. */
data class AILimitDisplayRow(
    val provider: AILimitProvider,
    /** "plus" 같은 제공자 플랜 라벨(없으면 null). */
    val planLabel: String?,
    /** 5시간 창. 그 창이 없으면 null — **줄을 만들지 않는다**(Starter 요금제는 주간만 온다). */
    val fiveHour: AILimitDisplay?,
    val weekly: AILimitDisplay?,
) {
    val id: String get() = provider.rawValue

    val visibleWindows: List<AILimitDisplay> get() = listOfNotNull(fiveHour, weekly).filter { it.isVisible }

    /** 그 열이 그릴 값. **null = 그 창이 이 계정에 아예 없다** → `없음`. 판정 불가는 값이 있는 쪽(글자는 `—`) — 두 사실을 같은 글자로 말하지 않는다. */
    fun display(window: AILimitWindow): AILimitDisplay? {
        val value = if (window == AILimitWindow.fiveHour) fiveHour else weekly
        return value?.takeIf { it.isVisible }
    }

    val hasAnyWindow: Boolean get() = visibleWindows.isNotEmpty()
}

/** 맥 한 대 + 그 맥이 올린 제공자 묶음(**읽은 값** — 코어 규칙의 입력 모양을 그대로 품는다; 기기 축은 그 앞단이다). */
data class AILimitDeviceGroup(val device: AILimitDevice, val bundle: AILimitSnapshotBundle) {
    val id: String get() = device.deviceID
}

/**
 * 카드가 그릴 기기 묶음 하나 — 이름까지 정해진 모양.
 * INV-MeAILimitsStore-ac5cf067 이식: 이름은 **겹침을 가른 뒤의 글자**다(AILimitDeviceRoster.displayNameParts) — 맥 미니 두 대는 이름이 글자 그대로
 *   같고 맥들은 서로를 모르므로 가르는 일은 **읽는 쪽**이 한다(같은 이름이 둘 이상이면 꼬리 `(A1B2)`).
 * INV-MeAILimitsStore-99a5eaa8 이식: 이름을 한 번도 올린 적 없는 맥은 `이름 모를 맥 A1B2` 로 선다(코어 AILimitDevice.baseName).
 * INV-MeAILimitsStore-645a1b6d 이식: 이름은 **조각으로** 들고 있다(base + 겹침 꼬리) — 합친 글자 하나면 말줄임이 꼬리부터 먹어 두 쌍둥이가
 *   똑같아진다. 그리는 쪽은 base 만 잘리게 한다.
 */
data class AILimitDeviceDisplayGroup(val device: AILimitDevice, val nameParts: AILimitDeviceNameParts, val rows: List<AILimitDisplayRow>) {
    val id: String get() = device.deviceID

    /** 꼬리까지 합친 한 글자 — **잘릴 자리가 없는 곳**에서만(보이스오버 · 위젯 패널 · 시험). 조각에서 만든다. */
    val name: String get() = nameParts.combined
}

/**
 * 위젯 패널에 싣는 제공자 한 줄(Swift `WidgetSnapshot.AILimitRow` — 날것 값과 절대 시각만; 하한·나이·투영은 위젯이 자기 칸 시각으로).
 * INV-WidgetSnapshot-af897ec6 이식: 담는 것은 **절대 시각**뿐이다(resetsAt · observedAt) — "남은 초"처럼 매초 바뀌는 수를 실으면 위젯 쓰기(W2-f)의
 *   중복 제거(같은 값이면 파일·새로고침을 건드리지 않는다)가 무력해져 60초마다 파일을 다시 쓰고 위젯 예산을 태운다. 남은 시간은 위젯이 투영한다.
 * INV-WidgetSnapshot-c1b06494 이식: [provider] 는 **문자열**(서버 칸 값)이다 — 위젯 확장은 이 값 모양만 받고, 열거값으로 접는 것은 읽는 쪽이며
 *   **모르는 값은 버린다**(지어내 claude 로 접으면 남의 사용률이 내 Claude 줄에 그려진다). 이 스토어는 AILimitProvider 로 이미 거른 줄만
 *   rawValue 로 싣는다. 읽는 쪽(W2-f 위젯)의 버리기는 그 갈래가 따로 지킨다.
 */
data class MeAILimitWidgetRow(
    val provider: String,
    val fiveHourPercent: Double?,
    val fiveHourResetsAt: SwiftDate?,
    val weeklyPercent: Double?,
    val weeklyResetsAt: SwiftDate?,
    val observedAt: SwiftDate,
)

/** 지금 탭에 넘길 위젯 모양(Swift `WidgetSnapshot.AILimitPanel`). 직렬화 · 파일 쓰기는 위젯 갈래(W2-f)가 한다. */
data class MeAILimitWidgetPanel(
    /**
     * 보일 제공자들 — **맥 한 대의 것**(메인 맥). 비어 있으면 위젯은 "앱을 열면 채워져요".
     * INV-WidgetSnapshot-ec94c89f 이식: v0.3.47 부터 이 목록은 **맥 한 대의 것**이다(메인 맥 — 폰이 골라 싣는다). "제공자당 가장 최신 행"으로
     *   섞으면 맥 A 에서 끈 제공자가 맥 B 의 더 새로운 행에 밀려 **되살아난다**(근거: [AILimitsStore.widgetPanel] 이 메인 맥 묶음에서만 만든다).
     */
    val providers: List<MeAILimitWidgetRow>,
    /**
     * 이 목록이 어느 맥의 것인가. null = 맥이 한 대뿐(이름을 적지 않는다). 겹침 꼬리까지 붙은 합친 글자.
     * INV-WidgetSnapshot-9401d735 이식: 이름은 **폰이 정한다**(AILimitDeviceRoster 의 displayNameParts) — 같은 이름이 둘이면 꼬리가 붙은 값이
     *   이미 들어 있다. 위젯은 받은 글자를 그대로 적는다(가르는 규칙이 두 벌이면 폰 카드와 위젯이 같은 맥을 다른 이름으로 부른다).
     * INV-WidgetSnapshot-281daaa3 이식: 이 칸은 **합친 한 글자**(`Mac mini (A1B2)`)다 — 소리(보이스오버)와 옛 위젯이 읽는 값이라 그대로 둔다.
     *   그리는 쪽은 꼬리를 따로 세워야 하므로 꼬리만 [deviceNameTail] 에 한 번 더 싣는다.
     */
    val deviceName: String? = null,
    /** 이름에 붙은 겹침 꼬리(괄호 없이). 위젯이 꼬리를 말줄임에 내주지 않게 따로 싣는다. */
    val deviceNameTail: String? = null,
    /**
     * 오늘(KST) 쓴 AI 토큰 — **계정 전체**(합산 유지). null = 모른다(0 은 거짓이다).
     * INV-WidgetSnapshot-24b9211f 이식: 토큰은 **합산 유지**다(2026-10-08 사용자 결정) — 리밋만 메인 맥을 따른다. 그래서 이 칸은 [deviceName] 이
     *   가리키는 맥의 것이 아니라 **계정 전체**의 수다(순위표와 같은 장부 — [AILimitsStore.phoneTokenTotals]).
     */
    val todayTokens: Long? = null,
    /** 최근 12주 합. */
    val recentTokens: Long? = null,
)

class AILimitsStore(
    val context: MeContext,
    parentScope: CoroutineScope,
    /** 토큰 축 숫자를 아는 나 탭 스토어(Swift `context.links.me` — 이 스토어의 주인). */
    private val me: () -> MeStore?,
) {
    private val work: Job = SupervisorJob(parentScope.coroutineContext[Job])
    private val scope: CoroutineScope = CoroutineScope(parentScope.coroutineContext + work)

    /** 서버에서 받은 **기기 묶음들**(최근에 일한 맥 먼저). null = 아직 한 번도 못 받았다 · 빈 목록 = 받았는데 그릴 맥이 없다(뜻이 다르다). */
    var groups by mutableStateOf<List<AILimitDeviceGroup>?>(null)
        internal set
    val state = MeLoadState()

    /**
     * 서버에 행이 있는 **내 맥 전부** — 숨긴 맥까지(3일 유령 · 그 맥에서 전부 껐다).
     * INV-MeAILimitsStore-d9c9c13d 이식: 왜 groups 와 따로 들고 있나(v0.3.47 P1) — 설정 고르개는 **기기 명부**를, 폰·위젯은 **그릴 묶음**을 봤다.
     *   고른 맥이 조용하면 칩은 그 맥에 불이 들어와 있는데 폰은 다른 맥을 그렸고, 묶음이 하나뿐이면 이름조차 안 적었다. 이 칸이 그 어긋남을
     *   없앤다 — 폰은 자기가 받은 행들로 **맥과 같은 함수**(fold)를 돌려 같은 명부를 만들고 "설정 칩이 가리키는 맥"을 스스로 계산한다.
     * INV-MeAILimitsStore-a527a2c4 이식: 남는 한 틈 — 이 조회에는 `limit=60` 이 걸려 있고 맥의 기기 조회에는 없다. 맥이 스무 대쯤 되는 사람은
     *   가장 오래된 맥의 행이 60줄 밖으로 밀려 명부에서 빠질 수 있다(그때 폰은 그 맥을 모르는 채 가장 최근 맥으로 접는다 — 틀린 이름은 안 적는다).
     */
    var roster by mutableStateOf<List<AILimitDevice>>(emptyList())
        internal set

    /**
     * 계정이 고른 메인 맥(`ai_limits_prefs.main_device_id`). null = 아직 안 골랐다 **또는 못 읽었다**.
     * INV-MeAILimitsStore-d796f064 이식: 두 뜻을 한 칸에 담아도 되는 까닭 — 폰에는 고르개가 없고 이 값으로 하는 일은 "위젯에 어느 맥을 실을까"
     *   하나다. 모르면 코어 규칙이 가장 최근에 일한 맥으로 접는다 — 위젯 머리에 **그 맥의 이름이 적히므로** 거짓말이 아니다.
     * INV-MeAILimitsStore-95ddb5dc 이식: **그 근거는 이름이 실제로 적힐 때만 성립한다.** 초안은 이름 조건을 `displayGroups.count > 1` 로 둬 접히는
     *   바로 그 경우에 이름이 안 적혔다 — 지금은 [settingsMainDevice] 와 그릴 묶음을 견주고 어긋나면 [showsDeviceNames] · [isShowingSubstituteDevice]
     *   가 둘 다 참이 된다.
     */
    var mainDeviceID by mutableStateOf<String?>(null)
        internal set

    private var serial = 0
    private var inflight: Job? = null

    /** 이 값을 받은 계정. 계정이 바뀌면 들고 있던 묶음을 버린다. */
    private var loadedUserID: String? = null

    companion object {
        /** 루트가 낡았다고 보는 초(나 탭과 같은 값). */
        const val STALE_SECONDS: Double = MeStore.STALE_SECONDS

        /**
         * 유령 문턱의 별칭(읽기 편의).
         * INV-MeAILimitsStore-adb46256 이식: 숫자는 여기 없다 — [AILimitGhostRow.maxObservationAge] **한 곳**에 있다(두 벌로 적으면 폰은 숨기고
         *   위젯은 그리는 날이 온다).
         */
        const val ghostRowAge: Double = AILimitGhostRow.maxObservationAge

        /**
         * 서버 행들 → **기기 묶음들**(최근에 일한 맥 먼저 · 그릴 것이 없는 맥은 빠진다). 기기가 **바깥 축**이고 제공자별 최신 고르기는 그 **안에서**.
         * 버리는 것 넷: 모르는 제공자(구버전이 'claude' 로 접으면 남의 사용률이 그려진다) · 유령 행(묶음을 세기 **전에** 걷어낸다) ·
         * 보이는 창이 0개인 행 · 그 결과 제공자가 0명이 된 기기(머리글만 남은 묶음을 만들지 않는다).
         * INV-MeAILimitsStore-2092066f 이식: 기기 축이 생기면서 "맥 설정에서 끈 제공자"(값 전부 null 로 덮은 행)가 **드디어 제대로 듣는다** —
         *   끈 맥의 그 줄만 사라지고 다른 맥의 줄은 자기 묶음에 남는다(옛날에는 다른 맥의 값이 이겨서 되살아났다).
         * INV-MeAILimitsStore-2bb995d1 이식: 판정은 **'보이는 창이 0개인가'** 하나다(AILimitProviderSnapshot.isLinked — 맥·위젯과 같은 술어).
         *   '5시간 창이 있나'로 재면 주간만 오는 제공자(안티그래비티)가 비워진 행과 함께 사라진다.
         * INV-MeAILimitsStore-25921381 이식: 비워진 행은 묶음의 providers 에는 **창 0개로 남는다**(visibleProviders 가 거른다) — "껐다"와 "연동이
         *   없다"를 가릴 단서지만 **그 단서로 문구를 가르지 않는다**(3일이면 단서도 사라져 문구가 혼자 바뀐다).
         */
        fun groups(rows: List<AILimitFetchedRow>, now: SwiftDate): List<AILimitDeviceGroup> {
            val alive = rows.filter { !AILimitGhostRow.isGhost(it.observedAt, now) }
            // 기기 목록·이름·순서는 **맥과 같은 규칙 하나**로 접는다.
            val devices = AILimitDeviceRoster.fold(alive.map { AILimitDeviceObservation(it.deviceID, it.deviceLabel, it.observedAt.timeIntervalSince1970) })
            val newestByDevice = LinkedHashMap<String, LinkedHashMap<AILimitProvider, AILimitFetchedRow>>()
            for (row in alive) {
                val provider = AILimitProvider.of(row.provider) ?: continue
                val held = newestByDevice.getOrPut(row.deviceID) { LinkedHashMap() }
                val seen = held[provider]
                if (seen != null && seen.observedAt >= row.observedAt) continue
                held[provider] = row
            }
            return devices.mapNotNull { device ->
                val byProvider = newestByDevice[device.deviceID] ?: return@mapNotNull null
                val bundle = AILimitSnapshotBundle(
                    providers = byProvider.entries.sortedBy { it.key.sortOrder }.map { snapshot(it.key, it.value) },
                )
                if (bundle.visibleProviders.isEmpty()) null else AILimitDeviceGroup(device, bundle)
            }
        }

        /** 서버 행들 → **기기 명부 전부**(숨긴 맥까지 — 아무것도 걸러내지 않는다). 맥 설정의 고르개와 **같은 함수·같은 입력**이다. */
        fun roster(rows: List<AILimitFetchedRow>): List<AILimitDevice> =
            AILimitDeviceRoster.fold(rows.map { AILimitDeviceObservation(it.deviceID, it.deviceLabel, it.observedAt.timeIntervalSince1970) })

        /** 행 하나 → 코어 규칙의 입력 모양. 창은 **퍼센트가 있는 것만** 만든다(없는 창을 0% 로 지어내지 않는다). */
        private fun snapshot(provider: AILimitProvider, row: AILimitFetchedRow): AILimitProviderSnapshot {
            val windows = ArrayList<AILimitWindowSnapshot>()
            val observed = row.observedAt.timeIntervalSince1970
            row.fiveHourPercent?.let {
                windows += AILimitWindowSnapshot(AILimitWindow.fiveHour, it, row.fiveHourResetsAt?.timeIntervalSince1970, observed, AILimitSource.server)
            }
            row.weeklyPercent?.let {
                windows += AILimitWindowSnapshot(AILimitWindow.weekly, it, row.weeklyResetsAt?.timeIntervalSince1970, observed, AILimitSource.server)
            }
            return AILimitProviderSnapshot(provider, windows, row.planLabel)
        }

        /**
         * 읽은 묶음들 → 카드가 그릴 묶음들(순수 함수 — 검증 하네스도 이 함수를 지난다).
         * INV-MeAILimitsStore-a25360ba 이식: 마지막에 hasAnyWindow 로 **한 번 더** 거른다 — visibleProviders 는 '창 데이터가 있나'를, 여기는
         *   **코어 규칙을 지난 뒤에도 그릴 칸이 남았나**를 잰다(없으면 `없음 · 없음` 인 빈 줄이 서고 카드가 빈 상태 안내 대신 제공자가 있다고 말한다).
         * INV-MeAILimitsStore-60d7e7be 이식: 기기 축에서는 그 그물이 **묶음까지** 걷는다 — 줄이 0개가 된 맥은 이름만 남은 머리글이 서지 않는다.
         * INV-MeAILimitsStore-c12e44f5 이식: 이름 겹침은 **여기 보이는 묶음들 사이에서만** 가른다(숨은 맥까지 세면 하나뿐인 `Mac mini` 에 꼬리가 붙는다).
         */
        fun displayGroups(groups: List<AILimitDeviceGroup>, now: SwiftDate): List<AILimitDeviceDisplayGroup> {
            val drawn = groups.mapNotNull { group ->
                val rows = rows(group.bundle, now)
                if (rows.isEmpty()) null else group.device to rows
            }
            val names = AILimitDeviceRoster.displayNameParts(drawn.map { it.first })
            return drawn.map { (device, rows) ->
                AILimitDeviceDisplayGroup(device, names[device.deviceID] ?: AILimitDeviceNameParts(device.baseName, null), rows)
            }
        }

        /** 묶음 하나 → 그릴 줄들. 값·캡션·표시여부는 **전부 코어 규칙**이 만든다. */
        private fun rows(bundle: AILimitSnapshotBundle, now: SwiftDate): List<AILimitDisplayRow> = bundle.visibleProviders.mapNotNull { snapshot ->
            fun display(window: AILimitWindow): AILimitDisplay? {
                if (snapshot.window(window) == null) return null
                val value = AILimitFreshnessRule.display(snapshot, window, now.timeIntervalSince1970)
                return if (value.isVisible) value else null
            }
            val row = AILimitDisplayRow(snapshot.provider, snapshot.planLabel, display(AILimitWindow.fiveHour), display(AILimitWindow.weekly))
            if (row.hasAnyWindow) row else null
        }

        /** 잔디의 **오늘 칸**. 격자가 비었거나 인덱스가 어긋나면 null(지어내지 않는다). */
        fun todayTokens(grid: TokenDailyGrid): Long? {
            if (grid.weeks <= 0 || grid.days <= 0) return null
            val offset = grid.days - 1
            val week = offset / WorkRhythmHeatmap.DAY_COUNT
            val weekday = offset % WorkRhythmHeatmap.DAY_COUNT
            return grid.tokens.getOrNull(week)?.getOrNull(weekday)
        }
    }

    // ------------------------------------------------------------------ 자리 API

    /** 낡았으면 다시 읽는다. **탭이 보이지 않아도 부른다** — 위젯이 소비자라 나 탭을 한 번도 열지 않는 사람의 위젯이 영원히 비지 않게. */
    fun refreshIfStale() {
        if (!context.sessionStore.isSignedIn || !isStale) return
        launch()
    }

    fun reset() {
        inflight?.cancel()
        inflight = null
        serial += 1
        groups = null
        // 명부도 비운다 — 남겨 두면 다음 사람의 카드가 앞 사람의 맥 이름으로 "다른 맥을 보여 준다"고 말한다.
        roster = emptyList()
        // INV-MeAILimitsStore-13e615a9 이식: 고른 맥도 **지운다** — 계정마다 다른 값이고, 남겨 두면 다음 사람의 위젯이 앞 사람이 고른 식별자로
        //   선다(코어 규칙이 모르는 식별자를 접어 주므로 증상은 조용하다).
        mainDeviceID = null
        state.reset()
        loadedUserID = null
    }

    private val isStale: Boolean
        get() {
            if (state.isLoading) return false
            val loadedAt = state.loadedAt
            if (loadedAt == null || state.hasFailed) return true
            return context.clock.now().timeIntervalSince(loadedAt) >= STALE_SECONDS
        }

    private fun launch() {
        inflight?.cancel()
        inflight = scope.launch { load() }
    }

    // ------------------------------------------------------------------ 읽기

    suspend fun load() {
        if (!context.sessionStore.isSignedIn) return
        val userID = context.sessionStore.userID ?: return
        serial += 1
        val mySerial = serial
        val generation = context.generation
        state.isLoading = true
        state.hasFailed = false
        try {
            val service = context.service
            val rows = try {
                context.withSessionRetry { s -> MeAILimitsService.fetchMyAILimits(service, s.accessToken, s.userID) }
            } catch (e: Throwable) {
                if (generation != context.generation || mySerial != serial) return
                if (AuthErrorRules.classify(e) == AuthErrorDisposition.cancelled) return
                // 실패는 조용히 — 들고 있던 값을 비우지 않는다(네트워크 없음은 빨간 문구가 아니라 낡은 나이로 말한다).
                state.hasFailed = true
                return
            }
            if (generation != context.generation || mySerial != serial || context.sessionStore.userID != userID) return
            groups = groups(rows, context.clock.now())
            // 명부는 **걸러내기 전 행들**로 접는다(맥 설정이 보는 것과 같은 입력).
            roster = roster(rows)
            // INV-MeAILimitsStore-c39ab82c 이식: 고른 맥은 **맥이 둘 이상일 때만** 묻는다 — 한 대뿐이면 고르기가 바꿀 수 있는 것이 없고, 혼자 쓰는
            //   사람(거의 모든 사용자)의 새로고침마다 GET 하나가 더 나가는 것을 피한다.
            // INV-MeAILimitsStore-24cde1b7 이식: 세는 것은 **명부**(roster)다 — 그릴 묶음이 아니다. `groups.count > 1` 은 이 결함이 사는 바로 그
            //   상태(맥 둘 중 한 대가 조용하다)에서 거짓이라 고른 맥을 영영 못 물었다.
            if (roster.size > 1) {
                loadMainDeviceID(userID)
                // 두 번째 조회를 기다리는 동안 계정이 바뀌거나 더 가까운 새로고침이 끼어들 수 있다 — 가드 셋을 **그 뒤에 한 번 더** 지난다.
                if (generation != context.generation || mySerial != serial || context.sessionStore.userID != userID) return
            }
            loadedUserID = userID
            state.hasLoaded = true
            state.hasFailed = false
            state.loadedAt = context.clock.now()
            pushToWidget()
        } finally {
            if (mySerial == serial) state.isLoading = false
        }
    }

    /**
     * 고른 메인 맥을 읽는다(`ai_limits_prefs`). **실패를 던지지 않는다** — 카드는 이 값을 쓰지 않으니 여기서 던지면 아무 이득 없이 카드가 빈다.
     * INV-MeAILimitsStore-9b199a66 이식: 읽기 실패와 "안 고름"을 가른다 — Swift `try?` 는 옵셔널 결과를 평탄화해 실패도 `.some(nil)` 로 만들었고
     *   조회 한 번 실패에 고른 맥이 지워졌다. 그래서 실패 갈래가 **코드에 보이는 자리**(catch)를 갖는다: 못 읽었으면 들고 있던 값을 지키고,
     *   읽었고 안 골랐으면 그 사실(null)을 반영한다.
     */
    private suspend fun loadMainDeviceID(userID: String) {
        val service = context.service
        val fetched: String? = try {
            context.withSessionRetry { s -> service.fetchAILimitMainDeviceID(s.accessToken, s.userID) }
        } catch (e: Throwable) {
            return // 못 읽었다 — 들고 있던 값을 **지킨다**(여기서 null 로 되돌리면 위젯이 다른 맥으로 튄다).
        }
        if (context.sessionStore.userID != userID) return
        mainDeviceID = fetched
    }

    // ------------------------------------------------------------------ 화면이 그릴 값

    /** 카드가 그릴 **기기 묶음들** — 최근에 일한 맥 먼저, 이름까지 정해진 모양. */
    val displayGroups: List<AILimitDeviceDisplayGroup> get() = displayGroups(groups ?: emptyList(), context.clock.now())

    /** 맥 설정의 칩이 **불을 켜는 맥** — 폰이 같은 답을 스스로 계산한다(명부 전체 + 고른 식별자 → 같은 함수). */
    val settingsMainDevice: AILimitDevice? get() = AILimitMainDeviceRule.resolve(roster, mainDeviceID)

    /**
     * 화면이 **설정 칩이 가리키는 맥 대신 다른 맥**을 그리고 있나 — 판정은 하나: 칩이 가리키는 맥이 그릴 묶음 안에 없다. 그릴 묶음이 없으면 거짓.
     * INV-MeAILimitsStore-6beffad1 이식: "고를 때만"으로 좁히지 않는다 — 사용자가 보는 것은 **칩의 체크 표시**다(안 골랐어도 체크는 한 맥에 붙어 있다).
     * INV-MeAILimitsStore-3103a1bc 이식: 거꾸로 "명부에 숨은 맥이 있으면 참"으로 넓히지도 않는다 — 지난주에 판 맥이 남은 사람에게 안내를 띄우면
     *   영원히 안 사라진다.
     */
    val isShowingSubstituteDevice: Boolean
        get() {
            val groups = displayGroups
            if (groups.isEmpty()) return false
            val expected = settingsMainDevice ?: return false
            return groups.none { it.device.deviceID == expected.deviceID }
        }

    /**
     * 기기 이름을 **그릴 것인가**. 맥이 한 대면 그리지 않는다(2026-10-08 사용자 결정).
     * INV-MeAILimitsStore-277d1d89 이식: 감추는 조건은 "묶음이 하나"가 아니다 — "**보여 줄 맥이 사용자가 아는 그 맥 하나뿐**"이다. 고른 맥이 조용해서
     *   다른 맥을 그릴 때 묶음이 하나뿐이면 이름이 안 적혀 사용자가 남의 숫자를 자기 맥 것으로 읽었다.
     * INV-MeAILimitsStore-62f6c1ef 이식: groups.count 로 세지 않는 것은 그대로다 — 맥은 둘인데 조용한 맥이 고른 맥도 아니면 이름을 그리는 순간
     *   있지도 않은 둘째 맥을 암시한다.
     */
    val showsDeviceNames: Boolean get() = displayGroups.size > 1 || isShowingSubstituteDevice

    /**
     * 카드가 그릴 줄 전부(기기 순서대로 펼친 것). 요약·빈 상태 판정이 쓴다.
     * INV-MeAILimitsStore-c268bd28 이식: **목록 키로 그대로 쓰지 마라** — [AILimitDisplayRow.id] 는 제공자다. 맥 두 대가 같은 Claude 를 올리면 키가
     *   겹친다. 그리는 쪽은 [displayGroups](묶음 키 = 기기)로 돌고 줄 키는 묶음 안에서만 쓴다.
     */
    val displayRows: List<AILimitDisplayRow> get() = displayGroups.flatMap { it.rows }

    /**
     * 카드 머리의 한 줄 요약(가장 많이 쓴 5시간 창). 그릴 줄이 없으면 null. 주간까지 섞으면 주간 90% 가 늘 이겨 5시간 여유가 안 보인다.
     * INV-MeAILimitsStore-91dd9c0b 이식: 맥 여러 대의 줄을 **다 넣는다** — 보이스오버가 카드 제목에서 읽는 말이고 묻는 것은 "어디서든 막힐 위험이
     *   있나"다. 신선도는 코어가 **가장 낡은 기여자**로 정한다(combine).
     */
    val fiveHourSummary: AILimitDisplay?
        get() {
            val displays = displayRows.mapNotNull { it.fiveHour }
            return if (displays.isEmpty()) null else AILimitFreshnessRule.combine(displays)
        }

    /**
     * 그릴 줄이 하나라도 있나.
     * INV-MeAILimitsStore-c87d8b9f 이식: **displayRows 로 답한다** — visibleProviders 를 따로 세면 "줄은 0개인데 제공자는 있다"는 조합이 생겨 빈 상태
     *   안내가 그려지지 않는다(두 판정이 갈릴 자리를 아예 없앤다).
     */
    val hasVisibleProviders: Boolean get() = displayRows.isNotEmpty()

    // ------------------------------------------------------------------ 메인 맥

    /**
     * 위젯에 실을 맥 — 고른 맥이 **지금 그릴 수 있는 묶음 안에** 있으면 그것, 없으면 가장 최근에 일한 맥. `main_device_id` 에는 외래키가 없다 —
     * 가리키는 것이 없는 상태는 **정상**이고 접는 일은 읽는 쪽이 한다(규칙은 맥과 같은 함수 하나).
     */
    val mainDisplayGroup: AILimitDeviceDisplayGroup?
        get() {
            val groups = displayGroups
            val device = AILimitMainDeviceRule.resolve(groups.map { it.device }, mainDeviceID) ?: return null
            return groups.firstOrNull { it.device.deviceID == device.deviceID }
        }

    // ------------------------------------------------------------------ 위젯으로 넘기기

    /**
     * 지금 탭에 넘길 위젯 모양 — **메인 맥 하나의 줄들**. 한 번도 못 받았으면 null(위젯은 "앱을 열면 채워져요"), 받았는데 그릴 줄이 0이면
     * **빈 목록**(뜻이 다르다).
     * INV-MeAILimitsStore-ec2a504a 이식: 왜 맥 하나뿐인가(2026-10-08 사용자 결정) — 미디움 칸은 줄 셋이면 꽉 찬다. 폰 카드는 전부, 위젯은 한 대를
     *   골라 **그 맥의 이름을 같이 실어** 머리에 적는다.
     * INV-MeAILimitsStore-d08ca1a2 이식: 맥이 **한 대뿐이면 이름을 싣지 않는다**(deviceName null) — 위젯은 지금과 똑같이 보인다.
     * INV-MeAILimitsStore-1c979b1a 이식: 토큰 둘은 **계정 전체의 합**이다(합산 유지). 메인 맥의 줄이 0개여도 토큰은 싣는다 — 다른 축이다.
     * INV-MeAILimitsStore-bd9c5766 이식: 설정에서 끈 제공자(창 값이 전부 null 인 행)는 visibleProviders 가 이미 걸렀으므로 **패널에 실리지 않는다** —
     *   비워진 행을 일부러 실어 "껐다"를 알리지 않는다(위젯 확장은 앱과 따로 갱신된다).
     */
    fun widgetPanel(): MeAILimitWidgetPanel? {
        val groups = groups ?: return null
        if (!state.hasLoaded) return null
        val tokens = phoneTokenTotals()
        val main = mainDisplayGroup
        // INV-MeAILimitsStore-662d269b 이식: 줄은 **묶음의 원본 값**(AILimitDeviceGroup.bundle)에서 만든다 — displayGroups 의 줄은 코어 규칙이 이미
        //   지나간 **표시값**이라 거기서 퍼센트를 되읽으면 하한("27% 이상")이 등호로 굳는다. 날것 값과 절대 시각만 싣는다.
        val bundle = main?.let { m -> groups.firstOrNull { it.device.deviceID == m.device.deviceID }?.bundle }
        val rows = (bundle?.visibleProviders ?: emptyList()).mapNotNull { snapshot ->
            val observed = snapshot.latestObservedAt ?: return@mapNotNull null
            val fiveHour = snapshot.window(AILimitWindow.fiveHour)
            val weekly = snapshot.window(AILimitWindow.weekly)
            MeAILimitWidgetRow(
                provider = snapshot.provider.rawValue,
                fiveHourPercent = fiveHour?.usedPercent,
                fiveHourResetsAt = fiveHour?.resetsAt?.let { SwiftDate(it) },
                weeklyPercent = weekly?.usedPercent,
                weeklyResetsAt = weekly?.resetsAt?.let { SwiftDate(it) },
                observedAt = SwiftDate(observed),
            )
        }
        val names = showsDeviceNames
        return MeAILimitWidgetPanel(
            providers = rows,
            // INV-MeAILimitsStore-073aefc8 이식: 이름을 싣는 조건은 **showsDeviceNames 하나**다(폰 카드와 같은 판정) — 고른 맥이 조용해서 다른 맥을
            //   실을 때 그 조건이 참이므로 위젯 머리에는 **언제나 그 맥의 이름이 적힌다**.
            deviceName = if (names) main?.name else null,
            // INV-MeAILimitsStore-ceedefe7 이식: 꼬리는 **따로 한 번 더** 싣는다(같은 조건 · 같은 조각에서) — 위젯은 맥 한 대만 그려 쌍둥이를 가르는
            //   글자가 이 꼬리 하나뿐이고, 합친 글자만 주면 위젯이 꼬리를 말줄임에 내준다.
            deviceNameTail = if (names) main?.nameParts?.tail else null,
            todayTokens = tokens.first,
            recentTokens = tokens.second,
        )
    }

    /** 위젯 스냅숏에 지금 값을 싣는다. **쓰는 주체는 지금 탭 하나다**(이 함수는 값을 넘기기만 한다). */
    fun pushToWidget() {
        val panel = widgetPanel() ?: return
        context.meLinks.noteAILimitPanel(panel)
    }

    /** 기존 **토큰 축** 숫자(나 탭 기록이 이미 알아 온 값 — 이 스토어는 서버에 묻지 않는다). 수집을 껐거나 아직 못 받았으면 둘 다 null. */
    fun phoneTokenTotals(): Pair<Long?, Long?> {
        val owner = me() ?: return null to null
        if (!owner.showsTokenGrid || !owner.recordsState.hasLoaded) return null to null
        return todayTokens(owner.tokenGrid) to owner.tokenGrid.totalTokens
    }
}
