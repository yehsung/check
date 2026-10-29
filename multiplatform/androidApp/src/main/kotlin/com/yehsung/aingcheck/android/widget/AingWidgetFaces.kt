// 원본: Sources/CheckWidgetsKit/AingWidgetModel.swift @ 3bd04bd (위젯이 그리는 값의 모양 — AingWidgetWorking · AingWidgetMyTodayState · AingWidgetTodos · AingWidgetLimitsState)
// 원본: Sources/CheckWidgetsKit/AingWidgetModel.swift:20-27 @ 3bd04bd (signedOut · noData · signedOut*Hint — 스냅숏이 없을 때의 글자)
//
// 위젯 4종이 **그리는 값**(얼굴). 위젯은 앱이 쓴 스냅숏만 그린다(iOS AingWidgetModel.swift:4-5 · E§7.1). 스냅숏 형식·파일은 W2-f(feature/phone …/widget),
// 값 계산(투영 · 고르기 · 서식 — AingWidgetModel)은 이 갈래(AingWidgetModel.kt)고, 스냅숏 → 얼굴은 [AingWidgetSnapshotFaces] 가 한다.
// 조립(K11)은 W2-f 스냅숏 파일을 읽어 AingWidgetInput 으로 옮기는 함수 하나를 [AingWidgetSnapshotFaces] 에 넘겨 [AingWidgetRuntime.faces] 에 꽂는다.
// 꽂기 전(또는 로그아웃)에는 [AingWidgetFaces.SignedOut] — 남의 지난 값을 그리지 않는 쪽으로 틀린다.
package com.yehsung.aingcheck.android.widget

/** 사람 칸 하나(지금 근무 중). */
data class WorkingPersonFace(val name: String, val isTeammate: Boolean, val detail: String?, val characterId: String? = null)

sealed interface WorkingNowFace {
    data class SignedOut(val hint: String = AingWidgetText.signedOutWorkingHint) : WorkingNowFace

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
    data class SignedOut(val hint: String = AingWidgetText.signedOutTodoHint) : TodosFace

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
    data class SignedOut(val hint: String = AingWidgetText.limitsSignedOutHint) : AILimitsFace

    /** 아직 한 번도 못 받았다 / 받았는데 그릴 줄이 0건(글자가 다르다 — 앱을 열어도 채워지지 않는 쪽은 "앱을 열면"이 아니다). */
    data class Message(val text: String) : AILimitsFace

    data class Limits(
        val rows: List<LimitRowFace>,
        /** 머리 꼬리 "· 예성의 MacBook Pro"(맥이 한 대면 null — 글자를 만들지 않는다). 좁으면 이쪽만 잘린다. */
        val deviceName: String?,
        /** 이름이 겹친 맥의 꼬리 "(A1B2)" — **절대 안 잘린다**(두 쌍둥이를 가르는 유일한 글자). */
        val deviceTail: String? = null,
        /** 읽어 줄 맥 이름(가운뎃점 없이 꼬리까지). */
        val deviceSpoken: String? = null,
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
