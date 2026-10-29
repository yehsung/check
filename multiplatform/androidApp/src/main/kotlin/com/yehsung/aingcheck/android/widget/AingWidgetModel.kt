// 원본: Sources/CheckWidgetsKit/AingWidgetModel.swift @ 3bd04bd (위젯 4종의 값 · 순수 계산 · 문구 — 투영 · 고르기 · 서식 · AI 리밋 줄)
//
// 위젯은 앱이 쓴 스냅숏만 읽는다(네트워크는 할 일 체크의 todo_sync 한 번뿐 — WidgetTodoToggle). 이 파일은 그 스냅숏을 **칸 시각으로 투영**해
// 그릴 값(얼굴 — AingWidgetFaces)을 만든다. 스냅숏의 형식·파일·쓰기는 W2-f(feature/phone …/widget WidgetSnapshot · FileWidgetSnapshotFile)
// 몫이고 이 갈래 기준(xplat/main)에는 아직 없다 — 그래서 읽기 모양 [AingWidgetInput] 을 Swift WidgetSnapshot 과 **필드 1:1** 로 두고,
// 조립(K11)이 W2-f WidgetSnapshot 을 이 값으로 옮긴다(assembly.md — 리밋 칸은 이미 같은 타입 MeAILimitWidgetPanel).
//
// 옮기지 않은 것(Android 에 자리가 없다 — 보고): 15분 타임라인 계획(AingWidgetTimelinePlan · AingWidgetLimitsTimelinePlan — Glance 는 타임라인이
// 아니라 앱의 updateAll 로 다시 그린다) · 미디움 pt 예산(AingWidgetLimitsMediumBudget — iOS 칸 실측) · 틴트 모드 잉크(AingWidgetLimitInk —
// Android 위젯에는 틴트 렌더 모드가 없다) · 예시 데이터 · anon 키 설정.
package com.yehsung.aingcheck.android.widget

import com.yehsung.aingcheck.core.rules.ailimit.AILimitDeviceNameParts
import com.yehsung.aingcheck.core.rules.ailimit.AILimitDisplay
import com.yehsung.aingcheck.core.rules.ailimit.AILimitFreshnessRule
import com.yehsung.aingcheck.core.rules.ailimit.AILimitProvider
import com.yehsung.aingcheck.core.rules.ailimit.AILimitProviderSnapshot
import com.yehsung.aingcheck.core.rules.ailimit.AILimitSource
import com.yehsung.aingcheck.core.rules.ailimit.AILimitWindow
import com.yehsung.aingcheck.core.rules.ailimit.AILimitWindowSnapshot
import com.yehsung.aingcheck.core.rules.format.TokenNumberFormatter
import com.yehsung.aingcheck.core.rules.insights.KstCalendar
import com.yehsung.aingcheck.core.rules.text.TextScalars
import com.yehsung.aingcheck.core.rules.todo.TodoRules
import com.yehsung.aingcheck.core.stores.me.AILimitColumnText
import com.yehsung.aingcheck.core.stores.me.AILimitGhostRow
import com.yehsung.aingcheck.core.stores.me.AILimitSurfaceText
import com.yehsung.aingcheck.core.stores.me.MeAILimitWidgetPanel
import com.yehsung.aingcheck.core.wire.CenterLabel
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.models.TeamWeeklyGoal
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min

/** 위젯이 읽는 스냅숏의 모양(Swift `WidgetSnapshot` — 필드 1:1). 조립이 W2-f WidgetSnapshot 을 옮겨 담는다. */
data class AingWidgetInput(
    val generatedAt: SwiftDate,
    val me: Me? = null,
    val working: List<Person> = emptyList(),
    val todosPreview: List<Todo> = emptyList(),
    /** 내 착용 캐릭터(위젯 초상). 모르면 null → 아잉. */
    val characterID: String? = null,
    /** AI 리밋 칸. null = 옛 스냅숏 · 앱을 한 번도 안 열었다. */
    val aiLimits: MeAILimitWidgetPanel? = null,
) {
    /** 근무 상태 세 갈래(Swift `WidgetSnapshot.WorkState`). */
    enum class WorkState { working, disconnected, off }

    data class Me(
        val working: Boolean,
        val sessionStartedAt: SwiftDate?,
        val todaySeconds: Int,
        val weekSeconds: Int,
        val goalHours: Int,
        val status: WorkState? = null,
    ) {
        /** 옛 스냅숏은 working 깃발로(Swift `resolvedStatus`). */
        val resolvedStatus: WorkState
            get() = if (!working) WorkState.off else if (status == WorkState.disconnected) WorkState.disconnected else WorkState.working
    }

    data class Person(val name: String, val center: String?, val teammate: Boolean, val startedAt: SwiftDate?, val characterID: String? = null)

    data class Todo(val id: String, val title: String, val isCompleted: Boolean, val carryOverDays: Int = 0)
}

// MARK: - 문구

/** 위젯 글자(Swift `AingWidgetText`). 값이 드는 글자는 함수다. */
object AingWidgetText {
    const val signedOut = "앱에서 로그인해 주세요"
    const val noData = "앱을 열면 채워져요"

    /** 소속 없는 사용자의 "내 오늘". iOS 의 "맥 앱에서 …"는 폰 가입이 생긴 뒤 낡은 글자라 Android 판은 처음부터 "앱에서"(E§7.1). */
    const val noTeam = "앱에서 팀에 참여하면 보여요"

    const val workingTitle = "지금 근무 중"
    const val workingEmpty = "지금 근무 중인 사람이 없어요"
    const val teammate = "우리 팀"
    fun people(count: Int): String = "${count}명"
    fun morePeople(count: Int): String = "외 ${count}명"

    const val notWorking = "근무 안 함"
    const val stateWorking = "근무 중"
    const val stateDisconnected = "연결 끊김"
    const val todayAccumulated = "오늘 누적"
    fun asOf(ago: String): String = "$ago 기준"
    const val thisWeek = "이번 주"
    fun weekLine(caption: String): String = "$thisWeek $caption"
    const val workingShortTitle = "근무 중"
    fun teammates(count: Int): String = "우리 팀 $count"
    fun otherTeams(count: Int): String = "다른 팀 $count"
    const val workingEmptyTitle = "아직 아무도 없어요"
    const val workingEmptyHint = "누가 근무를 시작하면 여기에 떠요"
    const val signedOutWorkingHint = "로그인하면 지금 근무 중인 사람이 떠요"
    const val signedOutTodoHint = "로그인하면 여기서 바로 체크해요"
    const val todoEmptyLarge = "적어 둔 일이 없어요"

    const val todoTitle = "오늘 할 일"
    const val todoEmpty = "오늘 할 일이 비어 있어요"
    const val todoEmptyHint = "앱에서 추가해 보세요"
    const val todoMarkDone = "완료로 표시"
    const val todoMarkUndone = "완료 취소"
    const val todoAddInApp = "앱에서 추가"
    fun todoRemaining(count: Int): String = "남은 ${count}개"
    fun more(count: Int): String = "외 ${count}개"
    fun todoProgress(total: Int, done: Int): String = "${total}개 중 ${done}개 완료"

    /** 여러 조각을 " · " 로 잇는다(빈 조각은 뺀다). */
    fun joined(parts: List<String?>): String = parts.filterNotNull().filter { it.isNotEmpty() }.joinToString(" · ")

    const val limitsTitle = "AI 리밋"
    const val limitsNoData = noData

    /** 받았는데 그릴 줄이 0건 — **"앱을 열면"이 아니다**(앱을 열어도 채워지지 않는다). 폰 카드와 같은 상수. */
    const val limitsNoProviders = AILimitSurfaceText.noVisibleProviders
    const val limitsSignedOutHint = "로그인하면 AI 사용률이 떠요"

    /** 머리 줄 제목 뒤에 붙는 메인 맥 이름 — `AI 리밋 · 예성의 MacBook Pro`. 맥이 한 대면 만들지 않는다. */
    fun limitsDeviceName(name: String): String = "· $name"
    const val limitsFiveHour = "5시간"
    const val limitsWeekly = "주간"
    const val limitsTokenTitle = "AI 토큰"
    const val limitsTokenToday = "오늘"
    const val limitsTokenRecent = "12주"
    fun limitsResetIn(remaining: String): String = "$remaining 뒤 초기화"
}

// MARK: - 서식

object AingWidgetFormat {
    /** 오른쪽 아래 "N분 전"(스냅숏을 만든 시각 기준). 미래(시계 차)는 "방금". 단위마다 내림(Swift `Int(x)` — 0 쪽으로 자른다). */
    fun ago(generatedAt: SwiftDate, now: SwiftDate): String {
        val seconds = now.timeIntervalSince(generatedAt)
        if (seconds < 60) return "방금"
        if (seconds < 3600) return "${(seconds / 60).toInt()}분 전"
        if (seconds < 86_400) return "${(seconds / 3600).toInt()}시간 전"
        return "${(seconds / 86_400).toInt()}일 전"
    }

    /** "3시간 25분"(멈춘 시간 표시 · 읽어 주기). */
    fun hoursMinutes(seconds: Int): String {
        val s = max(0, seconds)
        val hours = s / 3600
        val minutes = (s % 3600) / 60
        return if (hours == 0) "${minutes}분" else "${hours}시간 ${minutes}분"
    }

    /** 소수 한 자리 시간(내림) "24.8". */
    fun hoursOneDecimal(seconds: Int): String {
        val tenths = max(0, seconds) * 10 / 3600
        return "${tenths / 10}.${tenths % 10}"
    }

    /** 목표 퍼센트(반올림 · 0~999). Swift `.rounded()` 는 반을 0 에서 멀리 — 값이 0 이상이라 floor(x + 0.5) 와 같다(Kotlin round 는 짝수 쪽이라 쓰지 않는다). */
    fun percent(workedSeconds: Int, goalSeconds: Int): Int {
        val raw = floor(max(0, workedSeconds).toDouble() / max(1, goalSeconds).toDouble() * 100 + 0.5).toInt()
        return min(999, max(0, raw))
    }

    /** 경과 "4:10"(시:분 내림). 미래 시작(시계 차)은 "0:00". */
    fun elapsedClock(start: SwiftDate, now: SwiftDate): String {
        val seconds = max(0, now.timeIntervalSince(start).toInt())
        return "${seconds / 3600}:" + ((seconds % 3600) / 60).toString().padStart(2, '0')
    }

    /** 세는 중인 오늘 누적 "5:10:00"(Android 위젯은 그 칸을 렌더 순간 값으로 적는다 — iOS 의 Text(timerInterval:) 자리). */
    fun elapsedLong(seconds: Int): String {
        val s = max(0, seconds)
        return "${s / 3600}:" + ((s % 3600) / 60).toString().padStart(2, '0') + ":" + (s % 60).toString().padStart(2, '0')
    }

    private val weekdays = listOf("월", "화", "수", "목", "금", "토", "일")

    /** "9월 17일 목"(KST — 할 일 L 머리). */
    fun dayLabel(date: SwiftDate): String {
        val local = KstCalendar.localDate(date.timeIntervalSince1970)
        val weekday = weekdays[local.dayOfWeek.ordinal]
        return "${local.month.ordinal + 1}월 ${local.day}일 $weekday"
    }
}

// MARK: - 칸 배치 수

object AingWidgetLayout {
    /** 지금 근무 중 S 얼굴 더미 · 이름 줄. */
    const val WORKING_SMALL_FACES = 3
    /** 지금 근무 중 M 사람 칸(2열 × 3행, 열 먼저). */
    const val WORKING_MEDIUM_ROWS = 3
    const val WORKING_MEDIUM_COLUMNS = 2
    const val WORKING_MEDIUM_CELLS = WORKING_MEDIUM_ROWS * WORKING_MEDIUM_COLUMNS
    /** 오늘 할 일 M 3줄 · L 5줄. */
    const val TODO_ROWS_MEDIUM = 3
    const val TODO_ROWS_LARGE = 5
    /** AI 리밋 줄 수 — 미디움 한 종류뿐이고 제공자가 셋이라 상한이 곧 전부다. */
    const val LIMIT_ROWS_MEDIUM = 3
}

// MARK: - 내 오늘 · 이번 주(칸 시각 투영)

/**
 * 스냅숏의 "나"를 칸 시각으로 옮긴 값. 앱이 스냅숏을 쓴 뒤로 흐른 시간을 위젯이 스스로 더한다.
 * - 근무 중이고 세션 시작 시각이 있으면 **센다**(오늘·이번 주 모두). 연결이 끊긴 세션은 앱이 시작 시각을 싣지 않아 멈춘 값이다.
 * - 스냅숏 뒤 KST 자정이 지났으면 오늘은 0 부터(근무 중이면 자정부터 센다). 주(월요일 0시)도 같다.
 * - 스냅숏이 12시간 넘게 낡았으면 세지 않는다 — 끝없이 늘어나는 숫자는 거짓말이다(12시간 지점에서 멈춘다).
 */
class AingWidgetMe(me: AingWidgetInput.Me, generatedAt: SwiftDate, at: SwiftDate) {
    val isWorking: Boolean = me.working
    val status: AingWidgetInput.WorkState = me.resolvedStatus
    val isTicking: Boolean
    val todaySeconds: Int
    val weekSeconds: Int
    val goalHours: Int = max(0, me.goalHours)
    val ageSeconds: Double = max(0.0, at.timeIntervalSince(generatedAt))

    init {
        val canTick = me.working && me.sessionStartedAt != null
        val ticking = canTick && ageSeconds < MAX_TICKING_AGE
        // 더할 시간: 세는 동안은 흐른 만큼, 낡아서 멈췄으면 12시간 지점까지, 원래 멈춘 값이면 0.
        val elapsed = if (canTick) min(ageSeconds, MAX_TICKING_AGE).toInt() else 0
        val start = me.sessionStartedAt ?: generatedAt
        // 스냅숏과 칸이 다른 날(주)이면 스냅숏의 누적은 지난 날(주) 몫이다 — 세는 중이면 경계부터 새로 세고, 아니면 0(모른다).
        val dayStart = TeamWeeklyGoal.koreanDayStart(at)
        todaySeconds = if (TeamWeeklyGoal.koreanDayStart(generatedAt) == dayStart) {
            max(0, me.todaySeconds) + elapsed
        } else if (ticking) {
            max(0, at.timeIntervalSince(maxOf(start, dayStart)).toInt())
        } else 0
        val weekStart = TeamWeeklyGoal.koreanWeekStart(at)
        weekSeconds = if (TeamWeeklyGoal.koreanWeekStart(generatedAt) == weekStart) {
            max(0, me.weekSeconds) + elapsed
        } else if (ticking) {
            max(0, at.timeIntervalSince(maxOf(start, weekStart)).toInt())
        } else 0
        isTicking = ticking
    }

    val goalSeconds: Int get() = max(1, goalHours) * 3600
    val progress: Double get() = min(1.0, weekSeconds.toDouble() / goalSeconds.toDouble())
    val percent: Int get() = AingWidgetFormat.percent(weekSeconds, goalSeconds)
    val isGoalComplete: Boolean get() = weekSeconds >= goalSeconds

    /** 세는 중일 때 오늘 누적이 시작된 시각(= 칸 시각 − 오늘 누적). */
    fun timerStart(at: SwiftDate): SwiftDate? = if (isTicking) at.addingTimeInterval(-todaySeconds.toDouble()) else null

    /** "24.8/40시간" */
    val weekCaption: String get() = "${AingWidgetFormat.hoursOneDecimal(weekSeconds)}/${goalHours}시간"

    val tone: WidgetTone
        get() = when (status) {
            AingWidgetInput.WorkState.working -> WidgetTone.Working
            AingWidgetInput.WorkState.disconnected -> WidgetTone.Lost
            AingWidgetInput.WorkState.off -> WidgetTone.Off
        }

    val stateTitle: String
        get() = when (status) {
            AingWidgetInput.WorkState.working -> AingWidgetText.stateWorking
            AingWidgetInput.WorkState.disconnected -> AingWidgetText.stateDisconnected
            AingWidgetInput.WorkState.off -> AingWidgetText.notWorking
        }

    /** 초상 옆 둘째 줄: 세는 값은 늘 지금 값이라 "오늘 누적", 멈춘 값이 한 시간 넘게 낡았으면 "3시간 전 기준". */
    fun stateSubtitle(generatedAt: SwiftDate, now: SwiftDate): String {
        if (isTicking || ageSeconds < 3600) return AingWidgetText.todayAccumulated
        return AingWidgetText.asOf(AingWidgetFormat.ago(generatedAt, now))
    }

    companion object {
        const val MAX_TICKING_AGE: Double = 12 * 3600.0
    }
}

/** "내 오늘" 위젯이 그릴 것. */
sealed interface AingWidgetMyTodayState {
    /** 앱이 아직 내 상태를 한 번도 못 받았다. */
    data object NoData : AingWidgetMyTodayState

    /** 팀 소속이 없다 — 앱은 **목표 0시간인 me** 로 싣는다(스냅숏에 소속 칸이 없다 · 서버 목표는 1~168). */
    data object NoTeam : AingWidgetMyTodayState
    class Me(val me: AingWidgetMe) : AingWidgetMyTodayState

    companion object {
        fun of(snapshot: AingWidgetInput, at: SwiftDate): AingWidgetMyTodayState {
            val me = snapshot.me ?: return NoData
            if (me.goalHours <= 0) return NoTeam
            return Me(AingWidgetMe(me, snapshot.generatedAt, at))
        }
    }
}

// MARK: - 지금 근무 중(고르기)

/** 우리 팀 먼저(앱이 준 순서 유지), 그다음 다른 팀. [limit] 명만 보이고 나머지는 "외 N명". */
class AingWidgetWorking(working: List<AingWidgetInput.Person>, limit: Int) {
    private val ordered = working.filter { it.teammate } + working.filterNot { it.teammate }
    val total: Int = ordered.size
    val shown: List<AingWidgetInput.Person> = ordered.take(max(0, limit))
    val hiddenCount: Int = max(0, total - shown.size)
    val teammateCount: Int = working.count { it.teammate }
    val otherCount: Int get() = total - teammateCount

    /** 얼굴 더미 아래 이름 줄 "민트 · 보리 · 라임". */
    val namesLine: String get() = shown.joinToString(" · ") { it.name }

    /** S 아래 줄 왼쪽 "우리 팀 3 · 외 3명"(둘 다 없으면 null). */
    val smallFooter: String?
        get() = AingWidgetText.joined(
            listOf(
                if (teammateCount > 0) AingWidgetText.teammates(teammateCount) else null,
                if (hiddenCount > 0) AingWidgetText.morePeople(hiddenCount) else null,
            ),
        ).ifEmpty { null }

    /** M 열 먼저(왼쪽 열 우리 팀). */
    fun columns(rows: Int): List<List<AingWidgetInput.Person>> = shown.chunked(max(1, rows))

    companion object {
        /** M 사람 칸 오른쪽 작은 글자: 우리 팀은 경과 "4:10", 다른 팀은 센터("서울"), 모르면 null. */
        fun detail(person: AingWidgetInput.Person, now: SwiftDate): String? {
            val started = person.startedAt
            if (person.teammate && started != null) return AingWidgetFormat.elapsedClock(started, now)
            return CenterLabel.display(person.center)
        }
    }
}

// MARK: - 오늘 할 일(고르기)

class AingWidgetTodos(previews: List<AingWidgetInput.Todo>, limit: Int) {
    val rows: List<AingWidgetInput.Todo> = previews.take(max(0, limit))
    /** 스냅숏 안의 미완료 수(위젯이 체크한 줄도 반영된다). */
    val remaining: Int = previews.count { !it.isCompleted }
    val hiddenCount: Int = max(0, previews.size - rows.size)
    val total: Int = previews.size
    val doneCount: Int get() = total - remaining

    /** M 머리 오른쪽 "남은 4개 · 외 2개". */
    val mediumTrailing: String
        get() = AingWidgetText.joined(listOf(AingWidgetText.todoRemaining(remaining), if (hiddenCount > 0) AingWidgetText.more(hiddenCount) else null))

    /** L 머리 둘째 줄 "9월 17일 목 · 5개 중 1개 완료". */
    fun largeSubtitle(at: SwiftDate): String =
        AingWidgetText.joined(listOf(AingWidgetFormat.dayLabel(at), AingWidgetText.todoProgress(total, doneCount)))

    /** L 아래 줄 왼쪽 "2분 전" 또는 "외 1개 · 2분 전". */
    fun largeFooter(ago: String): String = AingWidgetText.joined(listOf(if (hiddenCount > 0) AingWidgetText.more(hiddenCount) else null, ago))

    companion object {
        /** "어제" · "3일 전"(코어 규칙과 같은 문구). */
        fun carryBadge(preview: AingWidgetInput.Todo): String? = TodoRules.carryBadge(preview.carryOverDays)
    }
}

// MARK: - AI 리밋(칸 시각 투영)

/** 리밋 줄 하나(제공자 하나). 값·캡션·표시여부는 **전부 코어 규칙**(AILimitFreshnessRule)이 만든다. */
data class AingWidgetLimitRow(
    val provider: AILimitProvider,
    /** 5시간 창. 그 창이 없으면 null — 지어내 0% 로 그리지 않는다. */
    val fiveHour: AILimitDisplay?,
    val weekly: AILimitDisplay?,
    /** 맥이 이 제공자에게서 값을 받은 시각 — 머리의 나이 글자가 이 값으로 선다(폰이 파일을 쓴 시각이 아니다). */
    val observedAt: SwiftDate?,
) {
    /** 그 열이 그릴 값. null = 그 창이 이 계정에 아예 없다 → `없음`. 판정 불가(시계 어긋남)는 값이 있고 글자가 `—` — 두 사실을 같은 글자로 말하지 않는다. */
    fun display(window: AILimitWindow): AILimitDisplay? {
        val value = if (window == AILimitWindow.fiveHour) fiveHour else weekly
        return value?.takeIf { it.isVisible }
    }

    val hasAnyWindow: Boolean get() = fiveHour != null || weekly != null
    val name: String get() = provider.displayName
    val compactName: String get() = provider.compactName
}

/** 머리 줄의 맥 이름 — 보이는 두 조각(이름 · 겹침 꼬리)과 읽어 줄 한 글자. */
data class AingWidgetLimitsHeaderDevice(
    /** 보이는 이름 `· 예성의 MacBook Pro` — 좁으면 **이쪽만** 잘린다. */
    val name: String,
    /** 겹침 꼬리 `(A1B2)` — 이름이 겹칠 때만. **절대 안 잘린다**(두 쌍둥이를 가르는 유일한 글자). */
    val tail: String?,
    /** 읽어 줄 글자(가운뎃점 없이 꼬리까지). */
    val spoken: String,
) {
    val text: String get() = tail?.let { "$name $it" } ?: name
}

sealed interface AingWidgetLimitsState {
    /** 스냅숏에 리밋 칸이 아직 없다 → "앱을 열면 채워져요". */
    data object NoData : AingWidgetLimitsState

    /** 받았는데 그릴 줄이 하나도 없다(연동 없음 · 맥에서 껐다 · 전부 유령) — 앱을 열어도 채워지지 않는다. */
    data object NoProviders : AingWidgetLimitsState
    data class Limits(val limits: AingWidgetLimits) : AingWidgetLimitsState

    companion object {
        fun of(snapshot: AingWidgetInput, at: SwiftDate): AingWidgetLimitsState {
            val panel = snapshot.aiLimits ?: return NoData
            val limits = AingWidgetLimits.of(panel, at)
            return if (limits.rows.isEmpty()) NoProviders else Limits(limits)
        }
    }
}

/** 제공자 줄들(메인 맥 한 대의 것 — 폰이 골라 싣는다, 위젯은 고르지 않는다) + 토큰(계정 전체 합 — 다른 축). */
data class AingWidgetLimits(
    val rows: List<AingWidgetLimitRow>,
    /** 합친 한 글자(소리 전용). null = 맥이 한 대뿐 → 머리에 적지 않는다. */
    val deviceName: String?,
    val deviceNameParts: AILimitDeviceNameParts?,
    /** 오늘 쓴 AI 토큰. null = 모른다 → 토큰 줄을 그리지 않는다(0 은 "안 썼다"는 거짓이다). */
    val todayTokens: Long?,
    val recentTokens: Long?,
) {
    /** 보이는 줄 중 **가장 낡은** 관측 시각(조합값의 신뢰도는 가장 낡은 기여자가 정한다). */
    val oldestObservedAt: SwiftDate? get() = rows.mapNotNull { it.observedAt }.minOrNull()

    /** 머리 나이 글자("3시간 전"). 관측 시각을 모르면 null(폰이 파일을 쓴 시각을 리밋의 나이처럼 적지 않는다). */
    fun observationAgeText(now: SwiftDate): String? = oldestObservedAt?.let { AingWidgetFormat.ago(it, now) }

    val headerDevice: AingWidgetLimitsHeaderDevice?
        get() {
            val spoken = deviceName ?: return null
            val parts = deviceNameParts ?: return null
            return AingWidgetLimitsHeaderDevice(
                name = AingWidgetText.limitsDeviceName(parts.base),
                tail = parts.tail?.let(AILimitDeviceNameParts::tailText),
                spoken = spoken,
            )
        }

    fun shown(limit: Int): List<AingWidgetLimitRow> = rows.take(max(0, limit))
    val hasTokens: Boolean get() = todayTokens != null

    companion object {
        fun of(panel: MeAILimitWidgetPanel, at: SwiftDate): AingWidgetLimits {
            val rows = panel.providers.mapNotNull { row ->
                // ★ 모르는 제공자는 **버린다**(구버전이 조용히 claude 로 접으면 남의 사용률이 내 줄에 그려진다).
                val provider = AILimitProvider.of(row.provider) ?: return@mapNotNull null
                // ★ 유령 행 게이트를 **칸 시각으로 다시** 지난다 — 패널은 앱이 열릴 때만 다시 써지고 위젯은 그 뒤에 그린다. 문턱은 폰과 같은 상수.
                if (AILimitGhostRow.isGhost(row.observedAt, at)) return@mapNotNull null
                val observed = row.observedAt.timeIntervalSince1970
                val windows = buildList {
                    row.fiveHourPercent?.let { add(AILimitWindowSnapshot(AILimitWindow.fiveHour, it, row.fiveHourResetsAt?.timeIntervalSince1970, observed, AILimitSource.server)) }
                    row.weeklyPercent?.let { add(AILimitWindowSnapshot(AILimitWindow.weekly, it, row.weeklyResetsAt?.timeIntervalSince1970, observed, AILimitSource.server)) }
                }
                val snapshot = AILimitProviderSnapshot(provider, windows)
                // ★ 보이는 창이 0개인 제공자는 줄을 세우지 않는다(맥 설정에서 끈 제공자의 '전부 null' 행 — 사흘을 기다리지 않는다).
                //   주간만 오는 제공자(안티그래비티)와 섞지 않는다: 그쪽은 창이 1개라 여기를 지난다.
                if (!snapshot.isLinked) return@mapNotNull null
                fun display(window: AILimitWindow): AILimitDisplay? {
                    if (snapshot.window(window) == null) return null
                    val value = AILimitFreshnessRule.display(snapshot, window, at.timeIntervalSince1970)
                    return value.takeIf { it.isVisible }
                }
                AingWidgetLimitRow(provider, display(AILimitWindow.fiveHour), display(AILimitWindow.weekly), row.observedAt)
            }.sortedBy { it.provider.sortOrder }
            // 공백뿐인 이름은 없는 것으로(머리에 빈 `· ` 만 남지 않게).
            val name = panel.deviceName?.let { TextScalars.trimmingWhitespacesAndNewlines(it) }?.ifEmpty { null }
            return AingWidgetLimits(
                rows = rows,
                deviceName = name,
                deviceNameParts = name?.let { deviceNameParts(it, panel.deviceNameTail) },
                todayTokens = panel.todayTokens,
                recentTokens = panel.recentTokens,
            )
        }

        /** 합친 글자 + 꼬리 → 두 조각. 짝이 맞을 때만 가른다(괄호를 찾아 자르지 않는다 — 이름에 괄호가 든 맥에서 틀린다). */
        fun deviceNameParts(combined: String, tail: String?): AILimitDeviceNameParts {
            val trimmedTail = tail?.let { TextScalars.trimmingWhitespacesAndNewlines(it) }
            if (trimmedTail.isNullOrEmpty()) return AILimitDeviceNameParts(combined, null)
            val suffix = " " + AILimitDeviceNameParts.tailText(trimmedTail)
            if (!combined.endsWith(suffix)) return AILimitDeviceNameParts(combined, null)
            val base = combined.dropLast(suffix.length)
            val parts = AILimitDeviceNameParts(base, trimmedTail)
            if (TextScalars.trimmingWhitespacesAndNewlines(base).isEmpty() || parts.combined != combined) return AILimitDeviceNameParts(combined, null)
            return parts
        }
    }
}

object AingWidgetLimitFormat {
    /** "3시간 뒤 초기화" — 절대 시각을 칸 시각으로 투영. 이미 지났거나 모르면 null(값 쪽 캡션이 "초기화됨"을 말한다). */
    fun resetIn(resetsAt: SwiftDate?, now: SwiftDate): String? {
        val at = resetsAt ?: return null
        val remaining = at.timeIntervalSince(now)
        if (remaining <= 0) return null
        return AingWidgetText.limitsResetIn(remainingText(remaining))
    }

    /** 60초 미만 "1분" · 1시간 미만 "N분" · 1일 미만 "N시간" · 그 위 "N일"(전부 내림, 0 은 없다). */
    fun remainingText(seconds: Double): String {
        if (seconds < 3_600) return "${max(1, (seconds / 60).toInt())}분"
        if (seconds < 86_400) return "${(seconds / 3_600).toInt()}시간"
        return "${(seconds / 86_400).toInt()}일"
    }

    /** 토큰 수 축약("196.6억") — 앱 카드와 같은 함수. */
    fun tokens(value: Long): String = TokenNumberFormatter.compactKorean(value)

    /** 창 칸 글자: 창이 없으면 `없음`(지어낸 0% 가 아니다), 있으면 코어가 만든 값 글자. */
    fun valueText(display: AILimitDisplay?): String = display?.valueText ?: AILimitColumnText.absentValueText
}
