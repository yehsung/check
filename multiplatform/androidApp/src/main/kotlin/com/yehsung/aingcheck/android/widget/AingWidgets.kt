// 원본: Sources/CheckWidgetsKit/Widgets/AingWidgets.swift @ 3bd04bd (위젯 셋 — 지금 근무 중 S·M · 내 오늘 S · 오늘 할 일 M·L, ToggleTodoIntent)
// 원본: Sources/CheckWidgetsKit/Widgets/AingLimitsWidget.swift @ 3bd04bd (AI 리밋 M)
// 원본: ios/Widgets/AingCheckWidgetsBundle.swift @ 3bd04bd (위젯 묶음 — 넷을 나열)
//
// Glance 위젯 4종(E§7.1). 그리는 값은 [AingWidgetRuntime.faces](조립이 W2-f 스냅숏으로 꽂는다)뿐이고, 네트워크는 할 일 체크의 `todo_sync` 한 번뿐이다
// (WidgetTodoToggle — 토큰 갱신 없음). 칸 밖을 누르면 앱의 지금 탭(명시적 Intent + 라우트 extra — E§4.6).
// 색은 ui 토큰(AingColors.Light/Dark)의 낮·밤 짝이다 — 위젯은 앱 화면 모드가 아니라 **기기 설정**을 따른다(AppearanceText.widgetNote).
// 수신자 클래스 이름은 AingWidgetKind 표에 고정돼 있다(바꾸면 홈 화면 위젯이 사라진다). 매니페스트 선언·위젯 정보 XML 은 조정자 패치(0001).
package com.yehsung.aingcheck.android.widget

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.LocalContext
import androidx.glance.LocalSize
import androidx.glance.action.ActionParameters
import androidx.glance.action.actionParametersOf
import androidx.glance.action.clickable
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.LinearProgressIndicator
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.action.ActionCallback
import androidx.glance.appwidget.action.actionRunCallback
import androidx.glance.appwidget.action.actionStartActivity
import androidx.glance.appwidget.cornerRadius
import androidx.glance.appwidget.provideContent
import androidx.glance.appwidget.updateAll
import androidx.glance.background
import androidx.glance.color.ColorProvider
import androidx.glance.layout.Alignment
import androidx.glance.layout.Box
import androidx.glance.layout.Column
import androidx.glance.layout.Row
import androidx.glance.layout.Spacer
import androidx.glance.layout.fillMaxHeight
import androidx.glance.layout.fillMaxSize
import androidx.glance.layout.fillMaxWidth
import androidx.glance.layout.height
import androidx.glance.layout.padding
import androidx.glance.layout.size
import androidx.glance.layout.width
import androidx.glance.semantics.contentDescription
import androidx.glance.semantics.semantics
import androidx.glance.text.FontWeight
import androidx.glance.text.Text
import androidx.glance.text.TextDecoration
import androidx.glance.text.TextStyle
import androidx.glance.unit.ColorProvider
import com.yehsung.aingcheck.android.routing.RouteIntents
import com.yehsung.aingcheck.android.routing.RouteRequest
import com.yehsung.aingcheck.core.rules.ailimit.AILimitFreshnessRule
import com.yehsung.aingcheck.ui.screens.me.AILimitUsageStage
import com.yehsung.aingcheck.ui.theme.AingColors

/**
 * 위젯의 프로세스 자리(조립 K11 이 Application.onCreate 에서 채운다 — assembly.md). 위젯 콜백이 콜드 스타트한 프로세스도 같은 Application 을 지나므로
 * 같은 값을 본다(E§5.2 "프로세스 안 조정자 하나만 갱신").
 */
object AingWidgetRuntime {
    /** 그릴 얼굴의 원천. 조립 전 · 로그아웃이면 로그인 안내(남의 지난 값을 그리지 않는다). */
    @Volatile
    var faces: AingWidgetFaceSource = AingWidgetFaces.SignedOut

    /** 할 일 체크 한 번(조립이 WidgetTodoToggle.run 에 앱의 창구·서비스를 묶어 꽂는다). null 이면 체크는 아무 일도 안 한다. */
    @Volatile
    var toggleTodo: (suspend (todoID: String) -> WidgetTodoToggle.Outcome)? = null

    /** 렌더 순간(앱 모듈 main 은 벽시계를 만들 수 있다 — 구조 시험 R2. 시험은 고정 시각을 꽂는다). */
    @Volatile
    var nowMillis: () -> Long = { System.currentTimeMillis() }
}

/** 위젯 넷을 다시 그린다(앱이 스냅숏을 쓴 뒤 — W2-f 쓰기 창구의 30초 스로틀 뒤 · 할 일 체크 뒤 · 로그아웃 뒤). */
object AingWidgetUpdater {
    suspend fun updateAll(context: Context) {
        WorkingNowWidget().updateAll(context)
        MyTodayWidget().updateAll(context)
        TodosWidget().updateAll(context)
        AILimitsWidget().updateAll(context)
    }

    /** 홈 화면에 놓인 위젯 수(kind 별) — 진단·기기 시나리오가 읽는다. */
    suspend fun placedCount(context: Context, kind: AingWidgetKind): Int {
        val manager = GlanceAppWidgetManager(context)
        val type = when (kind) {
            AingWidgetKind.WorkingNow -> WorkingNowWidget::class.java
            AingWidgetKind.MyToday -> MyTodayWidget::class.java
            AingWidgetKind.Todos -> TodosWidget::class.java
            AingWidgetKind.AILimits -> AILimitsWidget::class.java
        }
        return manager.getGlanceIds(type).size
    }
}

/** 칸 크기(iOS systemSmall · systemMedium · systemLarge 자리 — dp). */
object AingWidgetSizes {
    val small = DpSize(170.dp, 170.dp)
    val medium = DpSize(360.dp, 170.dp)
    val large = DpSize(360.dp, 380.dp)

    fun isSmall(size: DpSize): Boolean = size.width < 250.dp
    fun isLarge(size: DpSize): Boolean = size.height >= 300.dp
}

// ---------------------------------------------------------------- 위젯 넷 + 수신자 넷

class WorkingNowWidget : GlanceAppWidget() {
    override val sizeMode: SizeMode = SizeMode.Responsive(setOf(AingWidgetSizes.small, AingWidgetSizes.medium))
    override suspend fun provideGlance(context: Context, id: GlanceId) {
        provideContent { WidgetContainer { WorkingNowContent(AingWidgetRuntime.faces.workingNow(AingWidgetRuntime.nowMillis())) } }
    }
}

class MyTodayWidget : GlanceAppWidget() {
    override val sizeMode: SizeMode = SizeMode.Single
    override suspend fun provideGlance(context: Context, id: GlanceId) {
        provideContent { WidgetContainer { MyTodayContent(AingWidgetRuntime.faces.myToday(AingWidgetRuntime.nowMillis())) } }
    }
}

class TodosWidget : GlanceAppWidget() {
    override val sizeMode: SizeMode = SizeMode.Responsive(setOf(AingWidgetSizes.medium, AingWidgetSizes.large))
    override suspend fun provideGlance(context: Context, id: GlanceId) {
        provideContent { WidgetContainer { TodosContent(AingWidgetRuntime.faces.todos(AingWidgetRuntime.nowMillis())) } }
    }
}

class AILimitsWidget : GlanceAppWidget() {
    override val sizeMode: SizeMode = SizeMode.Single
    override suspend fun provideGlance(context: Context, id: GlanceId) {
        provideContent { WidgetContainer { AILimitsContent(AingWidgetRuntime.faces.aiLimits(AingWidgetRuntime.nowMillis())) } }
    }
}

class WorkingNowWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = WorkingNowWidget()
}

class MyTodayWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = MyTodayWidget()
}

class TodosWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = TodosWidget()
}

class AILimitsWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = AILimitsWidget()
}

/** 할 일 줄 체크(iOS ToggleTodoIntent). 위젯 프로세스(= 앱 프로세스)의 다른 스레드에서 돈다 — 본문은 WidgetTodoToggle(토큰 갱신 없음). */
class ToggleTodoAction : ActionCallback {
    override suspend fun onAction(context: Context, glanceId: GlanceId, parameters: ActionParameters) {
        val id = parameters[TODO_ID] ?: return
        AingWidgetRuntime.toggleTodo?.invoke(id)
        AingWidgetUpdater.updateAll(context)
    }

    companion object {
        val TODO_ID = ActionParameters.Key<String>("todoID")
    }
}

// ---------------------------------------------------------------- 색(ui 토큰의 낮·밤 짝)

internal object WidgetInk {
    private fun pair(pick: (AingColors) -> androidx.compose.ui.graphics.Color): ColorProvider =
        ColorProvider(day = pick(AingColors.Light), night = pick(AingColors.Dark))

    val background = pair { it.widgetBackground }
    val primary = pair { it.label }
    val secondary = pair { it.label2 }
    val tertiary = pair { it.label3Text }
    val separator = pair { it.separator }
    val fill = pair { it.fill }
    val accent = pair { it.accent }
    val accentFill = pair { it.accentFill }
    val onAccentFill = pair { it.onAccentFill }
    val working = pair { it.working }
    val workingDot = pair { it.workingDot }
    val pending = pair { it.pending }
    val offWork = pair { it.offWork }
    val offWorkDot = pair { it.offWorkDot }
    val aiToken = pair { it.aiToken }
    val danger = pair { it.danger }

    fun tone(tone: WidgetTone): ColorProvider = when (tone) {
        WidgetTone.Working -> working
        WidgetTone.Lost -> pending
        WidgetTone.Off -> offWork
    }
}

private fun style(size: Int, weight: FontWeight = FontWeight.Normal, color: ColorProvider = WidgetInk.primary, decoration: TextDecoration? = null) =
    TextStyle(color = color, fontSize = size.sp, fontWeight = weight, textDecoration = decoration)

// ---------------------------------------------------------------- 공통 껍데기

/** 바탕(흰색 / 남색) · 모서리 · 탭하면 지금 탭. */
@Composable
private fun WidgetContainer(content: @Composable () -> Unit) {
    val context = LocalContext.current
    val open = RouteIntents.explicit(context, RouteRequest(AingWidgetLinks.now), proof = null)
    Box(
        GlanceModifier
            .fillMaxSize()
            .background(WidgetInk.background)
            .cornerRadius(22.dp)
            .padding(14.dp)
            .clickable(actionStartActivity(open)),
    ) { content() }
}

@Composable
private fun Head(title: String, active: Boolean) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Box(GlanceModifier.size(7.dp).cornerRadius(4.dp).background(if (active) WidgetInk.workingDot else WidgetInk.offWorkDot)) {}
        Spacer(GlanceModifier.width(5.dp))
        Text(title, style = style(13, FontWeight.Medium, WidgetInk.secondary), maxLines = 1)
    }
}

@Composable
private fun SignedOutContent(hint: String?) {
    Column(GlanceModifier.fillMaxSize(), verticalAlignment = Alignment.CenterVertically, horizontalAlignment = Alignment.Start) {
        Text(AingWidgetDefaults.signedOut, style = style(15, FontWeight.Bold), maxLines = 2)
        if (hint != null) {
            Spacer(GlanceModifier.height(4.dp))
            Text(hint, style = style(12, color = WidgetInk.secondary), maxLines = 2)
        }
    }
}

// ---------------------------------------------------------------- 지금 근무 중

@Composable
private fun WorkingNowContent(face: WorkingNowFace) {
    when (face) {
        is WorkingNowFace.SignedOut -> SignedOutContent(face.hint)
        is WorkingNowFace.People -> if (AingWidgetSizes.isSmall(LocalSize.current)) WorkingSmall(face) else WorkingMedium(face)
    }
}

@Composable
private fun WorkingSmall(face: WorkingNowFace.People) {
    Column(GlanceModifier.fillMaxSize()) {
        Head(AingWidgetDefaults.workingTitle, face.total > 0)
        Spacer(GlanceModifier.height(6.dp))
        Text(AingWidgetDefaults.people(face.total), style = style(34, FontWeight.Bold), maxLines = 1)
        if (face.total == 0) {
            Text(AingWidgetDefaults.workingEmpty, style = style(12, color = WidgetInk.secondary), maxLines = 2)
        } else {
            Spacer(GlanceModifier.height(6.dp))
            Text(face.namesLine, style = style(13, FontWeight.Medium), maxLines = 1)
        }
        Spacer(GlanceModifier.defaultWeight())
        Row(GlanceModifier.fillMaxWidth()) {
            Text(face.footer ?: "", style = style(11, color = WidgetInk.secondary), maxLines = 1, modifier = GlanceModifier.defaultWeight())
            Text(face.ago, style = style(11, color = WidgetInk.secondary), maxLines = 1)
        }
    }
}

@Composable
private fun WorkingMedium(face: WorkingNowFace.People) {
    Row(GlanceModifier.fillMaxSize()) {
        Column(GlanceModifier.width(84.dp)) {
            Head(AingWidgetDefaults.workingShortTitle, face.total > 0)
            Spacer(GlanceModifier.height(6.dp))
            Text(AingWidgetDefaults.people(face.total), style = style(34, FontWeight.Bold), maxLines = 1)
            if (face.teammateCount > 0) Text(AingWidgetDefaults.teammates(face.teammateCount), style = style(12, color = WidgetInk.secondary), maxLines = 1)
            if (face.otherCount > 0) Text(AingWidgetDefaults.otherTeams(face.otherCount), style = style(12, color = WidgetInk.secondary), maxLines = 1)
            Spacer(GlanceModifier.defaultWeight())
            Text(face.ago, style = style(11, color = WidgetInk.secondary), maxLines = 1)
        }
        Spacer(GlanceModifier.width(14.dp))
        Box(GlanceModifier.width(1.dp).fillMaxHeight().background(WidgetInk.separator)) {}
        Spacer(GlanceModifier.width(14.dp))
        if (face.total == 0) {
            Column(GlanceModifier.defaultWeight(), verticalAlignment = Alignment.CenterVertically) {
                Text(AingWidgetDefaults.workingEmptyTitle, style = style(14, FontWeight.Bold), maxLines = 1)
                Text(AingWidgetDefaults.workingEmptyHint, style = style(12, color = WidgetInk.secondary), maxLines = 2)
            }
        } else {
            WorkingGrid(face.shown, GlanceModifier.defaultWeight())
        }
    }
}

/** 2×3 사람 칸(열 먼저 — 왼쪽 열이 우리 팀). */
@Composable
private fun WorkingGrid(people: List<WorkingPersonFace>, modifier: GlanceModifier) {
    val columns = WorkingGridLayout.columns(people)
    Row(modifier) {
        columns.forEachIndexed { index, column ->
            if (index > 0) Spacer(GlanceModifier.width(12.dp))
            Column(GlanceModifier.defaultWeight()) {
                column.forEach { person ->
                    Row(GlanceModifier.fillMaxWidth().height(40.dp).semantics { contentDescription = WorkingGridLayout.spoken(person) }, verticalAlignment = Alignment.CenterVertically) {
                        Text(person.name, style = style(14, FontWeight.Medium), maxLines = 1, modifier = GlanceModifier.defaultWeight())
                        if (person.detail != null) Text(person.detail, style = style(12, color = WidgetInk.secondary), maxLines = 1)
                    }
                }
            }
        }
    }
}

/** 사람 칸 배치(순수 — iOS AingWidgetLayout.workingMedium* · AingWidgetWorking.columns). */
object WorkingGridLayout {
    const val COLUMNS = 2
    const val ROWS = 3

    /** 열 먼저 채운다(위→아래, 왼쪽 열부터) — 칸 수(6)를 넘는 사람은 버린다(머리 숫자가 전체를 말한다). */
    fun columns(people: List<WorkingPersonFace>): List<List<WorkingPersonFace>> =
        people.take(COLUMNS * ROWS).chunked(ROWS)

    /** 칸 하나의 소리(이름 · 우리 팀 · 경과/센터). */
    fun spoken(person: WorkingPersonFace): String = listOfNotNull(person.name, if (person.isTeammate) "우리 팀" else null, person.detail).joinToString(" · ")
}

// ---------------------------------------------------------------- 내 오늘

@Composable
private fun MyTodayContent(face: MyTodayFace) {
    when (face) {
        MyTodayFace.SignedOut -> SignedOutContent(null)
        is MyTodayFace.Message -> Column(GlanceModifier.fillMaxSize(), verticalAlignment = Alignment.CenterVertically) {
            Text(face.text, style = style(14, FontWeight.Bold), maxLines = 3)
        }
        is MyTodayFace.Me -> Column(GlanceModifier.fillMaxSize()) {
            Column {
                Text(face.stateTitle, style = style(13, FontWeight.Bold, WidgetInk.tone(face.tone)), maxLines = 1)
                Text(face.stateSubtitle, style = style(11, color = WidgetInk.secondary), maxLines = 1)
            }
            Spacer(GlanceModifier.height(12.dp))
            Text(face.todayText, style = style(if (face.timerStartEpochMillis != null) 28 else 24, FontWeight.Bold), maxLines = 1)
            Spacer(GlanceModifier.defaultWeight())
            Row(GlanceModifier.fillMaxWidth()) {
                Text(face.weekCaption, style = style(11, color = WidgetInk.secondary), maxLines = 1, modifier = GlanceModifier.defaultWeight())
                Text("${face.percent}%", style = style(11, FontWeight.Bold), maxLines = 1)
            }
            Spacer(GlanceModifier.height(5.dp))
            LinearProgressIndicator(
                progress = face.progress.coerceIn(0f, 1f),
                modifier = GlanceModifier.fillMaxWidth().height(5.dp),
                color = if (face.isGoalComplete) WidgetInk.workingDot else WidgetInk.accentFill,
                backgroundColor = WidgetInk.fill,
            )
        }
    }
}

// ---------------------------------------------------------------- 오늘 할 일

@Composable
private fun TodosContent(face: TodosFace) {
    when (face) {
        is TodosFace.SignedOut -> SignedOutContent(face.hint)
        is TodosFace.Rows -> {
            val large = AingWidgetSizes.isLarge(LocalSize.current)
            if (face.rows.isEmpty()) {
                Column(GlanceModifier.fillMaxSize(), verticalAlignment = Alignment.CenterVertically) {
                    Text(if (large) AingWidgetDefaults.todoEmptyLarge else AingWidgetDefaults.todoEmpty, style = style(15, FontWeight.Bold), maxLines = 2)
                    if (!large) Text(AingWidgetDefaults.todoEmptyHint, style = style(12, color = WidgetInk.secondary), maxLines = 1)
                }
            } else {
                Column(GlanceModifier.fillMaxSize()) {
                    Row(GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                        Column(GlanceModifier.defaultWeight()) {
                            Text(AingWidgetDefaults.todoTitle, style = style(if (large) 17 else 15, FontWeight.Bold), maxLines = 1)
                            if (large) Text(face.largeSubtitle, style = style(12, color = WidgetInk.secondary), maxLines = 1)
                        }
                        Text(if (large) AingWidgetDefaults.todoRemaining(face.remaining) else face.mediumTrailing, style = style(12, color = WidgetInk.secondary), maxLines = 1)
                    }
                    Spacer(GlanceModifier.height(4.dp))
                    val limit = if (large) TodoRowLimits.LARGE else TodoRowLimits.MEDIUM
                    face.rows.take(limit).forEach { row -> TodoRow(row, large) }
                    if (large) {
                        Spacer(GlanceModifier.defaultWeight())
                        Row(GlanceModifier.fillMaxWidth()) {
                            Text(face.largeFooter, style = style(11, color = WidgetInk.secondary), maxLines = 1, modifier = GlanceModifier.defaultWeight())
                            Text("+ ${AingWidgetDefaults.todoAddInApp}", style = style(11, FontWeight.Medium, WidgetInk.accent), maxLines = 1)
                        }
                    }
                }
            }
        }
    }
}

/** 줄 전체가 체크 단추(체크 → ToggleTodoAction). 끝난 줄은 3단 글자 + 취소선, 이월 배지는 회색 칩. */
@Composable
private fun TodoRow(row: TodoRowFace, large: Boolean) {
    Row(
        GlanceModifier
            .fillMaxWidth()
            .height(if (large) TodoRowLimits.LARGE_HEIGHT.dp else TodoRowLimits.MEDIUM_HEIGHT.dp)
            .clickable(actionRunCallback<ToggleTodoAction>(actionParametersOf(ToggleTodoAction.TODO_ID to row.id)))
            .semantics { contentDescription = TodoRowLimits.spoken(row) },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            GlanceModifier.size(18.dp).cornerRadius(9.dp).background(if (row.isCompleted) WidgetInk.accentFill else WidgetInk.fill),
            contentAlignment = Alignment.Center,
        ) { if (row.isCompleted) Text("✓", style = style(11, FontWeight.Bold, WidgetInk.onAccentFill)) }
        Spacer(GlanceModifier.width(10.dp))
        Text(
            row.title,
            style = style(if (large) 15 else 14, color = if (row.isCompleted) WidgetInk.tertiary else WidgetInk.primary, decoration = if (row.isCompleted) TextDecoration.LineThrough else null),
            maxLines = 1,
            modifier = GlanceModifier.defaultWeight(),
        )
        if (row.carryBadge != null) {
            Box(GlanceModifier.background(WidgetInk.fill).cornerRadius(9.dp).padding(horizontal = 6.dp, vertical = 2.dp)) {
                Text(row.carryBadge, style = style(11, FontWeight.Medium, WidgetInk.secondary), maxLines = 1)
            }
        }
    }
}

/** 줄 수·높이(iOS AingWidgetLayout.todoRows* · todoRowHeight*). */
object TodoRowLimits {
    const val MEDIUM = 3
    const val LARGE = 6
    const val MEDIUM_HEIGHT = 34
    const val LARGE_HEIGHT = 46

    /** 줄 하나의 소리: 할 일 제목 + 무엇을 하는 단추인지(완료로 표시 · 완료 취소). */
    fun spoken(row: TodoRowFace): String = "${row.title}, ${if (row.isCompleted) AingWidgetDefaults.todoMarkUndone else AingWidgetDefaults.todoMarkDone}"
}

// ---------------------------------------------------------------- AI 리밋

@Composable
private fun AILimitsContent(face: AILimitsFace) {
    when (face) {
        is AILimitsFace.SignedOut -> SignedOutContent(face.hint)
        is AILimitsFace.Message -> Column(GlanceModifier.fillMaxSize()) {
            Text(AingWidgetDefaults.limitsTitle, style = style(13, FontWeight.Bold), maxLines = 1)
            Spacer(GlanceModifier.defaultWeight())
            Text(face.text, style = style(13, color = WidgetInk.secondary), maxLines = 3)
            Spacer(GlanceModifier.defaultWeight())
        }
        is AILimitsFace.Limits -> Column(GlanceModifier.fillMaxSize()) {
            Row(GlanceModifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text(AingWidgetDefaults.limitsTitle, style = style(13, FontWeight.Bold), maxLines = 1)
                if (face.deviceName != null) {
                    Spacer(GlanceModifier.width(4.dp))
                    Text(face.deviceName, style = style(12, color = WidgetInk.secondary), maxLines = 1, modifier = GlanceModifier.defaultWeight())
                } else {
                    Spacer(GlanceModifier.defaultWeight())
                }
                Text(AingWidgetDefaults.limitsFiveHour, style = style(11, FontWeight.Medium, WidgetInk.accent), maxLines = 1)
                Spacer(GlanceModifier.width(10.dp))
                Text(AingWidgetDefaults.limitsWeekly, style = style(11, FontWeight.Medium, WidgetInk.aiToken), maxLines = 1)
            }
            Spacer(GlanceModifier.height(6.dp))
            face.rows.take(3).forEach { row ->
                Row(GlanceModifier.fillMaxWidth().height(28.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(row.providerName, style = style(13, FontWeight.Medium), maxLines = 1, modifier = GlanceModifier.defaultWeight())
                    LimitValue(row.fiveHourText, row.fiveHourPercent)
                    Spacer(GlanceModifier.width(10.dp))
                    LimitValue(row.weeklyText, row.weeklyPercent)
                }
            }
            Spacer(GlanceModifier.defaultWeight())
            if (face.tokenToday != null || face.ago != null) {
                Row(GlanceModifier.fillMaxWidth()) {
                    Text(
                        listOfNotNull(face.tokenToday?.let { "${AingWidgetDefaults.limitsTokenToday} $it" }, face.tokenRecent?.let { "${AingWidgetDefaults.limitsTokenRecent} $it" }).joinToString(" · "),
                        style = style(11, color = WidgetInk.secondary), maxLines = 1, modifier = GlanceModifier.defaultWeight(),
                    )
                    Text(face.ago ?: "", style = style(11, color = WidgetInk.secondary), maxLines = 1)
                }
            }
        }
    }
}

/** 값 칸(글자 — 사용량 단계는 글자 색이 말한다: 70 이상 주의 · 90 이상 위험, 모르는 값은 평온). */
@Composable
private fun LimitValue(text: String, percent: Double?) {
    // 경계·반올림은 폰 카드와 한 벌(ui AILimitUsageStage · 코어 wholePercent) — 글자가 `90%` 라고 적으면 색도 거기서 갈린다.
    val color = if (percent == null) WidgetInk.tertiary else when (AILimitUsageStage.stage(AILimitFreshnessRule.wholePercent(percent))) {
        AILimitUsageStage.calm -> WidgetInk.primary
        AILimitUsageStage.warn -> WidgetInk.pending
        AILimitUsageStage.danger -> WidgetInk.danger
    }
    Box(GlanceModifier.width(62.dp), contentAlignment = Alignment.CenterEnd) {
        Text(text, style = style(12, FontWeight.Bold, color), maxLines = 1)
    }
}
