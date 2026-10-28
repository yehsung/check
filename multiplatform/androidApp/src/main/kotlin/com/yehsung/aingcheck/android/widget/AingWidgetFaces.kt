// 원본: Sources/CheckWidgetsKit/AingWidgetModel.swift @ 3bd04bd (위젯이 그리는 값의 모양 — AingWidgetWorking · AingWidgetMyTodayState · AingWidgetTodos · AingWidgetLimitsState)
// 원본: Sources/CheckWidgetsKit/AingWidgetModel.swift:20-27 @ 3bd04bd (signedOut · noData · signedOut*Hint — 스냅숏이 없을 때의 글자)
//
// 위젯 4종이 **그리는 값**(얼굴). 위젯은 앱이 쓴 스냅숏만 그린다(iOS AingWidgetModel.swift:4-5 · E§7.1) — 스냅숏 형식과 값 계산(AingWidgetModel)은
// W2-f 위젯 갈래(feature/phone …/widget) 몫이고 이 갈래는 W2-f 병합 전에 짰다(§8-18 8). 그래서 이 파일은 그리기에 필요한 **다 계산된 글자·수**의
// 모양만 정하고, 스냅숏 → 얼굴 잇기는 조립(K11)이 [AingWidgetRuntime.faces] 에 꽂는다(assembly.md). 꽂기 전(또는 로그아웃)에는 [AingWidgetFaces.SignedOut]
// — 남의 지난 값을 그리지 않는 쪽으로 틀린다.
package com.yehsung.aingcheck.android.widget

/** 사람 칸 하나(지금 근무 중). */
data class WorkingPersonFace(val name: String, val isTeammate: Boolean, val detail: String?, val characterId: String? = null)

sealed interface WorkingNowFace {
    data class SignedOut(val hint: String = AingWidgetDefaults.signedOutWorkingHint) : WorkingNowFace

    /**
     * @param shown 그릴 사람(S 는 얼굴 더미 6 · M 은 2×3 칸 — 열 먼저, 왼쪽 열이 우리 팀).
     * @param footer S 아래 줄 "우리 팀 3 · 외 3명"(없으면 null).
     * @param ago 오른쪽 아래 신선도 "2분 전".
     */
    data class People(
        val total: Int,
        val shown: List<WorkingPersonFace>,
        val namesLine: String,
        val teammateCount: Int,
        val otherCount: Int,
        val footer: String?,
        val ago: String,
    ) : WorkingNowFace
}

/** 근무 상태 색 뜻(내 오늘 상태 줄). */
enum class WidgetTone { Working, Lost, Off }

sealed interface MyTodayFace {
    data object SignedOut : MyTodayFace

    /** 소속 없음 · 아직 채워지지 않음(글자 한 줄 + 캐릭터). */
    data class Message(val text: String, val characterId: String) : MyTodayFace

    /**
     * @param timerStartEpochMillis 세는 중이면 근무 시작 시각(위젯이 스스로 흐르게 하는 자리 — 지금 판은 렌더 순간의 경과 [todayText] 를 쓴다), 아니면 null.
     * @param todayText 멈춘 값 "5시간 10분" 또는 렌더 순간의 경과.
     */
    data class Me(
        val characterId: String,
        val stateTitle: String,
        val tone: WidgetTone,
        val stateSubtitle: String,
        val timerStartEpochMillis: Long?,
        val todayText: String,
        val weekCaption: String,
        val percent: Int,
        val progress: Float,
        val isGoalComplete: Boolean,
    ) : MyTodayFace
}

/** 할 일 한 줄(줄 전체가 체크 단추 — 위젯에는 "눌러서 수정"이 없다). */
data class TodoRowFace(val id: String, val title: String, val isCompleted: Boolean, val carryBadge: String?)

sealed interface TodosFace {
    data class SignedOut(val hint: String = AingWidgetDefaults.signedOutTodoHint) : TodosFace

    /**
     * @param mediumTrailing M 머리 오른쪽 "남은 4개 · 외 2개".
     * @param largeSubtitle L 제목 아래 "9월 17일 목 · 5개 중 1개 완료".
     * @param largeFooter L 아래 "2분 전".
     */
    data class Rows(
        val rows: List<TodoRowFace>,
        val mediumTrailing: String,
        val largeSubtitle: String,
        val remaining: Int,
        val largeFooter: String,
    ) : TodosFace
}

/** 리밋 한 줄(제공자 하나 · 두 창 나란히). [fiveHourPercent] null = 그 창이 없다(글자 `없음`) 또는 판정 불가(글자 `—`) — 글자는 [fiveHourText] 가 말한다. */
data class LimitRowFace(
    val providerName: String,
    val fiveHourText: String,
    val fiveHourPercent: Double?,
    val fiveHourFloorOnly: Boolean,
    val weeklyText: String,
    val weeklyPercent: Double?,
    val weeklyFloorOnly: Boolean,
)

sealed interface AILimitsFace {
    data class SignedOut(val hint: String = AingWidgetDefaults.limitsSignedOutHint) : AILimitsFace

    /** 아직 한 번도 못 받았다 / 받았는데 그릴 줄이 0건(글자가 다르다 — 앱을 열어도 채워지지 않는 쪽은 "앱을 열면"이 아니다). */
    data class Message(val text: String) : AILimitsFace

    data class Limits(
        val rows: List<LimitRowFace>,
        /** 머리 꼬리 "· 예성의 MacBook Pro"(맥이 한 대면 null — 글자를 만들지 않는다). */
        val deviceName: String?,
        val tokenToday: String?,
        val tokenRecent: String?,
        val ago: String?,
    ) : AILimitsFace
}

/** 위젯이 그릴 얼굴을 내는 원천(조립이 W2-f 스냅숏 + AingWidgetModel 로 만든다). [nowMillis] 는 렌더 순간(신선도·경과를 칸 시각으로 투영). */
interface AingWidgetFaceSource {
    fun workingNow(nowMillis: Long): WorkingNowFace
    fun myToday(nowMillis: Long): MyTodayFace
    fun todos(nowMillis: Long): TodosFace
    fun aiLimits(nowMillis: Long): AILimitsFace
}

/** 스냅숏이 없을 때(로그아웃 · 조립 전). 남의 지난 값을 그리지 않는다. */
object AingWidgetFaces {
    object SignedOut : AingWidgetFaceSource {
        override fun workingNow(nowMillis: Long): WorkingNowFace = WorkingNowFace.SignedOut()
        override fun myToday(nowMillis: Long): MyTodayFace = MyTodayFace.SignedOut
        override fun todos(nowMillis: Long): TodosFace = TodosFace.SignedOut()
        override fun aiLimits(nowMillis: Long): AILimitsFace = AILimitsFace.SignedOut()
    }
}

/**
 * 위젯 머리·빈 상태 글자(Swift `AingWidgetText` 의 그리기 몫). 값 계산 글자(남은 N개 · N분 전 …)는 얼굴이 이미 들고 온다.
 * ⚠️ 두 벌 위험(보고): W2-f 가 AingWidgetText 를 feature/phone 에 옮기면 이 표와 겹친다 — 조립 때 그쪽 상수를 가리키게 접는다(8차).
 */
object AingWidgetDefaults {
    const val signedOut = "앱에서 로그인해 주세요"
    const val signedOutWorkingHint = "로그인하면 지금 근무 중인 사람이 떠요"
    const val signedOutTodoHint = "로그인하면 여기서 바로 체크해요"
    const val limitsSignedOutHint = "로그인하면 AI 사용률이 떠요"
    const val workingTitle = "지금 근무 중"
    const val workingShortTitle = "근무 중"
    const val workingEmpty = "지금 근무 중인 사람이 없어요"
    const val workingEmptyTitle = "아직 아무도 없어요"
    const val workingEmptyHint = "누가 근무를 시작하면 여기에 떠요"
    const val todoTitle = "오늘 할 일"
    const val todoEmpty = "오늘 할 일이 비어 있어요"
    const val todoEmptyHint = "앱에서 추가해 보세요"
    const val todoEmptyLarge = "적어 둔 일이 없어요"
    const val todoAddInApp = "앱에서 추가"
    const val todoMarkDone = "완료로 표시"
    const val todoMarkUndone = "완료 취소"
    const val limitsTitle = "AI 리밋"
    const val limitsFiveHour = "5시간"
    const val limitsWeekly = "주간"
    const val limitsTokenToday = "오늘"
    const val limitsTokenRecent = "12주"

    fun people(count: Int): String = "${count}명"
    fun teammates(count: Int): String = "우리 팀 $count"
    fun otherTeams(count: Int): String = "다른 팀 $count"
    fun todoRemaining(count: Int): String = "남은 ${count}개"
}
