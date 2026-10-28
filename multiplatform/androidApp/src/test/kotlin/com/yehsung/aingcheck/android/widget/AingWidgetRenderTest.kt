// 원본: Sources/CheckWidgetsKit/Widgets/AingWidgetPreviewCatalog.swift @ 3bd04bd (위젯을 앱 밖에서 구워 사람이 보는 목록 — 같은 갈래의 Android 판)
//
// 위젯 4종을 Glance → RemoteViews → 진짜 View 로 펼쳐(Robolectric NATIVE 그래픽) 글자가 서는지 재고 PNG 를 남긴다(사람 확인용 —
// build/aingcheck-snapshots/widgets). 얼굴(face)은 조립이 스냅숏에서 만드는 값의 모양 그대로다. 로그아웃 얼굴은 남의 값 없이 로그인 안내만 그린다.
package com.yehsung.aingcheck.android.widget

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.TextView
import androidx.compose.ui.unit.DpSize
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.compose
import androidx.test.core.app.ApplicationProvider
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode
import java.io.File

@RunWith(RobolectricTestRunner::class)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
@Config(sdk = [36], qualifiers = "w411dp-h891dp-xhdpi")
class AingWidgetRenderTest {
    private val context: Context get() = ApplicationProvider.getApplicationContext()

    private val sample = object : AingWidgetFaceSource {
        override fun workingNow(nowMillis: Long) = WorkingNowFace.People(
            total = 6,
            shown = listOf(
                WorkingPersonFace("새벽", true, "2:10"), WorkingPersonFace("라떼", true, "1:05"), WorkingPersonFace("구름", true, "0:40"),
                WorkingPersonFace("호두", false, "서울"), WorkingPersonFace("모카", false, "부산"), WorkingPersonFace("단비", false, "서울"),
            ),
            namesLine = "새벽, 라떼, 구름 외 3명", teammateCount = 3, otherCount = 3, footer = "우리 팀 3 · 외 3명", ago = "2분 전",
        )
        override fun myToday(nowMillis: Long) = MyTodayFace.Me(
            characterId = "fox", stateTitle = "근무 중", tone = WidgetTone.Working, stateSubtitle = "14:05부터 · 방금",
            timerStartEpochMillis = 1_789_610_000_000, todayText = "5:10:00", weekCaption = "이번 주 24.8/40시간", percent = 62, progress = 0.62f, isGoalComplete = false,
        )
        override fun todos(nowMillis: Long) = TodosFace.Rows(
            rows = listOf(
                TodoRowFace("0a000000-0000-4000-8000-00000000000a", "주간 보고 쓰기", false, null),
                TodoRowFace("0b000000-0000-4000-8000-00000000000b", "디자인 리뷰", true, null),
                TodoRowFace("0c000000-0000-4000-8000-00000000000c", "영수증 정리", false, "어제"),
            ),
            mediumTrailing = "남은 2개", largeSubtitle = "9월 17일 목 · 3개 중 1개 완료", remaining = 2, largeFooter = "2분 전",
        )
        override fun aiLimits(nowMillis: Long) = AILimitsFace.Limits(
            rows = listOf(
                LimitRowFace("Claude", "27%", 27.0, false, "60%", 60.0, false),
                LimitRowFace("Codex", "0%", 0.0, false, "94%", 94.0, false),
                LimitRowFace("안티그래비티", "없음", null, false, "8%", 8.0, false),
            ),
            deviceName = null, tokenToday = "2,595만", tokenRecent = "24.1억", ago = "2분 전",
        )
    }

    @After
    fun reset() {
        AingWidgetRuntime.faces = AingWidgetFaces.SignedOut
        AingWidgetRuntime.nowMillis = { System.currentTimeMillis() }
    }

    private fun render(widget: GlanceAppWidget, size: DpSize, name: String): View = runBlocking {
        val remote = widget.compose(context, size = size)
        val parent = FrameLayout(context)
        val view = remote.apply(context, parent)
        val density = context.resources.displayMetrics.density
        val w = (size.width.value * density).toInt()
        val h = (size.height.value * density).toInt()
        view.measure(View.MeasureSpec.makeMeasureSpec(w, View.MeasureSpec.EXACTLY), View.MeasureSpec.makeMeasureSpec(h, View.MeasureSpec.EXACTLY))
        view.layout(0, 0, w, h)
        val bitmap = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        view.draw(Canvas(bitmap))
        val out = File(requireNotNull(System.getProperty("aingcheck.mpRoot")), "androidApp/build/aingcheck-snapshots/widgets/$name.png")
        out.parentFile.mkdirs()
        out.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
        view
    }

    private fun texts(view: View): List<String> = when (view) {
        is TextView -> listOf(view.text.toString())
        is ViewGroup -> (0 until view.childCount).flatMap { texts(view.getChildAt(it)) }
        else -> emptyList()
    }

    @Test
    fun signedOutFacesNeverDrawSomeoneElsesData() {
        AingWidgetRuntime.faces = AingWidgetFaces.SignedOut
        val view = render(WorkingNowWidget(), AingWidgetSizes.small, "working-now-signed-out")
        val t = texts(view)
        assertTrue(t.toString(), t.contains(AingWidgetText.signedOut))
        assertTrue(t.toString(), t.contains(AingWidgetText.signedOutWorkingHint))
        assertTrue(texts(render(TodosWidget(), AingWidgetSizes.medium, "todos-signed-out")).contains(AingWidgetText.signedOutTodoHint))
        assertTrue(texts(render(AILimitsWidget(), AingWidgetSizes.medium, "ai-limits-signed-out")).contains(AingWidgetText.limitsSignedOutHint))
        assertTrue(texts(render(MyTodayWidget(), AingWidgetSizes.small, "my-today-signed-out")).contains(AingWidgetText.signedOut))
    }

    @Test
    fun facesRenderTheirValues() {
        AingWidgetRuntime.faces = sample
        val small = texts(render(WorkingNowWidget(), AingWidgetSizes.small, "working-now-small"))
        assertTrue(small.toString(), small.containsAll(listOf("지금 근무 중", "6명", "새벽, 라떼, 구름 외 3명", "우리 팀 3 · 외 3명", "2분 전")))
        val medium = texts(render(WorkingNowWidget(), AingWidgetSizes.medium, "working-now-medium"))
        assertTrue(medium.toString(), medium.containsAll(listOf("근무 중", "6명", "우리 팀 3", "다른 팀 3", "새벽", "단비", "2:10", "부산")))
        val today = texts(render(MyTodayWidget(), AingWidgetSizes.small, "my-today"))
        assertTrue(today.toString(), today.containsAll(listOf("근무 중", "5:10:00", "이번 주 24.8/40시간", "62%")))
        val todosM = texts(render(TodosWidget(), AingWidgetSizes.medium, "todos-medium"))
        assertTrue(todosM.toString(), todosM.containsAll(listOf("오늘 할 일", "남은 2개", "주간 보고 쓰기", "디자인 리뷰", "어제")))
        val todosL = texts(render(TodosWidget(), AingWidgetSizes.large, "todos-large"))
        assertTrue(todosL.toString(), todosL.containsAll(listOf("9월 17일 목 · 3개 중 1개 완료", "+ 앱에서 추가", "2분 전")))
        val limits = texts(render(AILimitsWidget(), AingWidgetSizes.medium, "ai-limits"))
        assertTrue(limits.toString(), limits.containsAll(listOf("AI 리밋", "5시간", "주간", "Claude", "27%", "94%", "없음")))
        assertFalse("맥이 한 대면 기기 이름 꼬리를 만들지 않는다", limits.any { it.startsWith("·") })
    }

    /**
     * 스냅숏 → 값 계산(AingWidgetModel) → 얼굴 → Glance 까지 한 줄로(Swift AingWidgetSamples 장면 · 데모 시각 고정). 이름이 겹친 맥은 머리에
     * 이름과 꼬리가 따로 선다. 기준선(다른 입력): 같은 장면을 로그아웃(스냅숏 없음)으로 그리면 그 값이 하나도 서지 않는다.
     */
    @Test
    fun snapshotModelRendersEndToEnd() {
        val now = com.yehsung.aingcheck.core.session.app.SessionClock.demoInstant
        fun at(offset: Double) = now.addingTimeInterval(offset)
        val input = AingWidgetInput(
            generatedAt = at(-120.0),
            me = AingWidgetInput.Me(true, at(-13_620.0), 18_480, 89_280, 40, AingWidgetInput.WorkState.working),
            working = listOf(
                AingWidgetInput.Person("민트", "seoul", true, at(-15_000.0), "shiba"),
                AingWidgetInput.Person("보리", "busan", true, at(-10_320.0), "aing"),
                AingWidgetInput.Person("라임", "seoul", true, at(-5_700.0), "jellyfish"),
                AingWidgetInput.Person("모래", "seoul", false, null, "ghost"),
                AingWidgetInput.Person("코랄", "busan", false, null, "squirrel"),
                AingWidgetInput.Person("하늘", null, false, null),
            ),
            todosPreview = listOf(
                AingWidgetInput.Todo("5A0F2D8E-1B4E-4B7A-9E0B-3E8E2A6D2C11", "디자인 리뷰 피드백 반영하기", false, 0),
                AingWidgetInput.Todo("6B1F2D8E-1B4E-4B7A-9E0B-3E8E2A6D2C12", "주간 회고 초안 쓰기", false, 1),
                AingWidgetInput.Todo("7C2F2D8E-1B4E-4B7A-9E0B-3E8E2A6D2C13", "팀 회의 안건 정리", false, 3),
                AingWidgetInput.Todo("8D3F2D8E-1B4E-4B7A-9E0B-3E8E2A6D2C14", "점심 전에 PR 올리기", true, 0),
                AingWidgetInput.Todo("9E4F2D8E-1B4E-4B7A-9E0B-3E8E2A6D2C15", "온보딩 문서 링크 모으기", false, 9),
            ),
            characterID = "fox",
            aiLimits = com.yehsung.aingcheck.core.stores.me.MeAILimitWidgetPanel(
                providers = listOf(
                    com.yehsung.aingcheck.core.stores.me.MeAILimitWidgetRow("claude", 27.0, at(9_300.0), 60.0, at(450_000.0), at(-120.0)),
                    com.yehsung.aingcheck.core.stores.me.MeAILimitWidgetRow("codex", 0.0, null, 56.0, at(352_000.0), at(-300.0)),
                    com.yehsung.aingcheck.core.stores.me.MeAILimitWidgetRow("antigravity", null, null, 8.0, at(540_000.0), at(-600.0)),
                ),
                deviceName = "Mac mini (A1B2)",
                deviceNameTail = "A1B2",
                todayTokens = 12_345_678,
                recentTokens = 19_658_964_272,
            ),
        )
        AingWidgetRuntime.nowMillis = { (now.timeIntervalSince1970 * 1000).toLong() }
        AingWidgetRuntime.faces = AingWidgetSnapshotFaces { input }
        val small = texts(render(WorkingNowWidget(), AingWidgetSizes.small, "snapshot-working-now-small"))
        assertTrue(small.toString(), small.containsAll(listOf("6명", "민트 · 보리 · 라임", "우리 팀 3 · 외 3명", "2분 전")))
        val medium = texts(render(WorkingNowWidget(), AingWidgetSizes.medium, "snapshot-working-now-medium"))
        assertTrue(medium.toString(), medium.containsAll(listOf("우리 팀 3", "다른 팀 3", "4:10", "부산")))
        val today = texts(render(MyTodayWidget(), AingWidgetSizes.small, "snapshot-my-today"))
        assertTrue(today.toString(), today.containsAll(listOf("근무 중", "5:10:00", "이번 주 24.8/40시간", "62%")))
        val todos = texts(render(TodosWidget(), AingWidgetSizes.large, "snapshot-todos-large"))
        assertTrue(todos.toString(), todos.containsAll(listOf("9월 17일 목 · 5개 중 1개 완료", "어제", "3일 전", "9일 전", "2분 전")))
        val limits = texts(render(AILimitsWidget(), AingWidgetSizes.medium, "snapshot-ai-limits"))
        assertTrue(limits.toString(), limits.containsAll(listOf("· Mac mini (A1B2)", "10분 전", "Claude", "27%", "0%", "56%", "없음", "8%")))

        AingWidgetRuntime.faces = AingWidgetSnapshotFaces { null }
        val signedOut = texts(render(WorkingNowWidget(), AingWidgetSizes.medium, "snapshot-working-now-signed-out"))
        assertFalse("로그아웃인데 스냅숏 값을 그렸다: $signedOut", signedOut.any { it == "민트" || it == "6명" })
    }

    /** 사람 칸 배치(열 먼저 · 6칸 상한)와 할 일 줄 소리. */
    @Test
    fun layoutRules() {
        val people = (1..8).map { WorkingPersonFace("p$it", it <= 3, null) }
        val columns = WorkingGridLayout.columns(people)
        assertTrue(columns.toString(), columns.map { col -> col.map { it.name } } == listOf(listOf("p1", "p2", "p3"), listOf("p4", "p5", "p6")))
        assertTrue(TodoRowLimits.spoken(TodoRowFace("x", "빨래", false, null)) == "빨래, 완료로 표시")
        assertTrue(TodoRowLimits.spoken(TodoRowFace("x", "빨래", true, null)) == "빨래, 완료 취소")
    }
}
