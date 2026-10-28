// 원본: Sources/CheckWidgetsKit/AingWidgetModel.swift:10-18 @ 3bd04bd (AingWidgetKind — 위젯 kind 넷)
// 원본: Sources/CheckWidgetsKit/Widgets/AingWidgets.swift @ 3bd04bd (AingWidgetLinks.now · 지원 크기 · 갤러리 이름)
//
// 위젯 4종의 **이름(kind)** — iOS 와 같은 글자다(②). iOS 는 kind 를 바꾸면 사용자가 홈 화면에 둔 위젯이 사라진다. Android 에서 같은 일을 하는
// 이름은 **수신자 클래스 이름**(AppWidgetProvider 컴포넌트)이다 — 그래서 수신자 클래스 이름도 여기 한 표에 묶어 같이 고정한다(바꾸면 홈 화면 위젯이
// 사라진다). 위젯 정보 XML(res/xml/aing_widget_<kind 소문자>.xml)과 매니페스트 수신자 선언은 조정자 몫이다(patches/ 의 0001).
package com.yehsung.aingcheck.android.widget

import com.yehsung.aingcheck.android.routing.AingRoute

/** 위젯 한 종류. [kind] = iOS AingWidgetKind 글자. [receiverClassName] = 홈 화면이 기억하는 이름(바꾸지 않는다). */
enum class AingWidgetKind(
    val kind: String,
    val receiverClassName: String,
    /** 위젯 정보 XML 이름(res/xml/<이름>.xml — 조정자 패치가 만든다). */
    val providerInfoName: String,
    /** 갤러리 이름·설명(iOS AingWidgetText.*GalleryName/Description — 위젯 정보 XML 의 description 과 같은 글자). */
    val galleryName: String,
    val galleryDescription: String,
) {
    WorkingNow(
        "AingWorkingNow", "com.yehsung.aingcheck.android.widget.WorkingNowWidgetReceiver", "aing_widget_working_now",
        "지금 근무 중", "지금 근무 중인 사람을 우리 팀부터 보여 줘요.",
    ),
    MyToday(
        "AingMyToday", "com.yehsung.aingcheck.android.widget.MyTodayWidgetReceiver", "aing_widget_my_today",
        "내 오늘", "내 캐릭터와 오늘 누적, 이번 주 목표를 보여 줘요.",
    ),
    Todos(
        "AingTodos", "com.yehsung.aingcheck.android.widget.TodosWidgetReceiver", "aing_widget_todos",
        "오늘 할 일", "체크하면 앱을 열지 않아도 완료로 표시돼요.",
    ),
    AILimits(
        "AingAILimits", "com.yehsung.aingcheck.android.widget.AILimitsWidgetReceiver", "aing_widget_ai_limits",
        "AI 리밋", "클로드·코덱스·안티그래비티의 5시간·주간 사용률을 보여 줘요.",
    ),
    ;

    companion object {
        /** iOS `AingWidgetKind.all` 과 같은 순서. */
        val all: List<String> = entries.map { it.kind }

        fun fromKind(kind: String): AingWidgetKind? = entries.firstOrNull { it.kind == kind }
    }
}

/** 위젯을 누르면 여는 곳(iOS `AingWidgetLinks.now` — 칸 밖을 누르면 지금 탭). 앱 안 이동이라 명시적 Intent + 라우트 extra 다(E§4.6). */
object AingWidgetLinks {
    val now: AingRoute = AingRoute.Now
}
