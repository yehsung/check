// 원본: Sources/check/CheckTodoBoardView.swift:358-621(CheckTodoBoardView) · :622-753(TodoBoardRowStack) · :754-839(TodoBoardDraftField) ·
//       :931-960(닫기 단추) · :961-1194(TodoBoardRowView) · :1195-1249(TodoBoardTitleEditor) @ ef9fab11
// 외양 조절(진하기 슬라이더·글자 후광·⌥+스크롤 — CheckTodoBoardAppearance)은 다음 웨이브(W-3 #9). 색은 테마 토큰만(AingTheme.colors).
package com.yehsung.aingcheck.desktop.overlay.todoboard

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.hoverable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsHoveredAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.yehsung.aingcheck.core.rules.todo.TodoItem
import com.yehsung.aingcheck.core.rules.todo.TodoRules
import com.yehsung.aingcheck.ui.theme.AingTheme

/** 보드가 그리는 값(맥 CheckTodoBoardView 의 let 들). 뷰는 store 를 모른다 — 픽스처만으로 렌더 검증된다. */
data class TodoBoardViewState(
    val sections: TodoBoardSections,
    val todayKey: String,
    val draft: String,
    val isOldSectionExpanded: Boolean = false,
    val editingID: String? = null,
    val pendingDeleteID: String? = null,
)

/** 보드가 부르는 동작(맥 클로저 묶음). */
class TodoBoardActions(
    val onDraftChange: (String) -> Unit = {},
    val onSubmitDraft: () -> Unit = {},
    val onToggleDone: (String) -> Unit = {},
    val onBeginEdit: (String) -> Unit = {},
    val onCommitEdit: (String, String) -> Unit = { _, _ -> },
    val onCancelEdit: () -> Unit = {},
    val onDelete: (String) -> Unit = {},
    val onUndoDelete: (String) -> Unit = {},
    val onToggleOldSection: () -> Unit = {},
    val onClose: () -> Unit = {},
)

/** 시험이 노드를 찾는 꼬리표. */
object TodoBoardTags {
    const val BOARD = "todo.board"
    const val DRAFT = "todo.draft"
    const val CLOSE = "todo.close"
    const val OLD_SECTION = "todo.old"
    const val EMPTY = "todo.empty"
    fun check(id: String) = "todo.check.$id"
    fun title(id: String) = "todo.title.$id"
    fun delete(id: String) = "todo.delete.$id"
    fun undo(id: String) = "todo.undo.$id"
    fun editor(id: String) = "todo.editor.$id"
}

/** 보드 치수(DIP). 창 크기는 [TodoBoardAnchor] 가 정본이다. */
object TodoBoardMetrics {
    const val CORNER_RADIUS = 14
    const val PADDING = 12
    const val ROW_MIN_HEIGHT = 30
    const val CHECK_SIZE = 16
    /** 행 사이 선 들여쓰기 = 체크 원(16) + 행 간격(8) — 선이 글자 컬럼에서 시작한다. */
    const val SEPARATOR_INSET = 24
}

/** 앱 경로: 컨트롤러에 물린 보드(Compose 상태를 읽어 바뀌면 다시 그린다). */
@Composable
fun TodoBoardRoot(controller: TodoBoardController, modifier: Modifier = Modifier, cornerRadiusDp: Int = TodoBoardMetrics.CORNER_RADIUS) {
    val ui = controller.ui
    val state = TodoBoardViewState(
        sections = controller.sections(),
        todayKey = ui.todayKey,
        draft = ui.draft,
        isOldSectionExpanded = ui.isOldSectionExpanded,
        editingID = ui.editingID,
        pendingDeleteID = ui.pendingDeleteID,
    )
    val actions = remember(controller) {
        TodoBoardActions(
            onDraftChange = controller::setDraft,
            onSubmitDraft = controller::submitDraft,
            onToggleDone = controller::toggleDone,
            onBeginEdit = controller::beginEdit,
            onCommitEdit = controller::commitEdit,
            onCancelEdit = controller::cancelEdit,
            onDelete = controller::requestDelete,
            onUndoDelete = controller::undoDelete,
            onToggleOldSection = controller::toggleOldSection,
            onClose = controller::close,
        )
    }
    TodoBoardView(state, actions, modifier, cornerRadiusDp = cornerRadiusDp)
}

@Composable
fun TodoBoardView(
    state: TodoBoardViewState,
    actions: TodoBoardActions,
    modifier: Modifier = Modifier,
    autoFocusDraft: Boolean = true,
    /** 창 경로는 0 — 모서리는 DWM 이 둥글린다(Windows 11, 창 배경이 모서리로 새지 않게). */
    cornerRadiusDp: Int = TodoBoardMetrics.CORNER_RADIUS,
) {
    val colors = AingTheme.colors
    val shape = RoundedCornerShape(cornerRadiusDp.dp)
    Column(
        modifier
            .testTag(TodoBoardTags.BOARD)
            .fillMaxSize()
            .clip(shape)
            .background(colors.boardTint, shape)
            .border(1.dp, colors.separator, shape)
            .padding(TodoBoardMetrics.PADDING.dp),
    ) {
        Header(actions.onClose)
        Divider(Modifier.padding(vertical = 8.dp))
        DraftField(state.draft, autoFocus = autoFocusDraft && state.editingID == null, actions)
        Box(Modifier.weight(1f).fillMaxWidth().padding(top = 6.dp)) { ListArea(state, actions) }
        Divider(Modifier.padding(top = 8.dp))
        Text(
            TodoBoardStrings.FOOTER,
            style = captionStyle(),
            color = colors.label2,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.padding(top = 6.dp),
        )
    }
}

@Composable private fun bodyStyle(): TextStyle = MaterialTheme.typography.bodySmall
@Composable private fun captionStyle(): TextStyle = MaterialTheme.typography.labelSmall.copy(fontWeight = FontWeight.Normal)

@Composable
private fun Divider(modifier: Modifier = Modifier) {
    Box(modifier.fillMaxWidth().height(1.dp).background(AingTheme.colors.separator))
}

@Composable
private fun Header(onClose: () -> Unit) {
    val colors = AingTheme.colors
    Row(Modifier.fillMaxWidth().height(24.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(TodoBoardStrings.TITLE, style = bodyStyle().copy(fontWeight = FontWeight.Bold), color = colors.label, maxLines = 1)
        Spacer(Modifier.weight(1f))
        Box(
            Modifier
                .testTag(TodoBoardTags.CLOSE)
                .semantics { contentDescription = TodoBoardStrings.CLOSE }
                .size(20.dp)
                .clip(CircleShape)
                .background(colors.fill, CircleShape)
                .clickable(onClick = onClose),
            contentAlignment = Alignment.Center,
        ) { Cross(colors.label2, 8f) }
    }
}

/** ✕ 글리프(아이콘 묶음에 기대지 않는다). */
@Composable
private fun Cross(color: androidx.compose.ui.graphics.Color, sizeDp: Float) {
    Canvas(Modifier.size(sizeDp.dp)) {
        val w = 1.5.dp.toPx()
        drawLine(color, Offset(0f, 0f), Offset(size.width, size.height), w)
        drawLine(color, Offset(size.width, 0f), Offset(0f, size.height), w)
    }
}

@Composable
private fun DraftField(draft: String, autoFocus: Boolean, actions: TodoBoardActions) {
    val colors = AingTheme.colors
    val focus = remember { FocusRequester() }
    if (autoFocus) LaunchedEffect(Unit) { runCatching { focus.requestFocus() } }
    val counter = TodoDraftInput.counterText(draft)
    Row(
        Modifier
            .fillMaxWidth()
            .height(30.dp)
            .background(colors.fill, RoundedCornerShape(8.dp))
            .padding(horizontal = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.weight(1f), contentAlignment = Alignment.CenterStart) {
            if (draft.isEmpty()) Text(TodoBoardStrings.PLACEHOLDER, style = bodyStyle(), color = colors.label3, maxLines = 1)
            BasicTextField(
                value = draft,
                onValueChange = { actions.onDraftChange(TodoDraftInput.accepted(draft, it)) },
                singleLine = true,
                textStyle = bodyStyle().copy(color = colors.label),
                cursorBrush = SolidColor(colors.accent),
                modifier = Modifier
                    .testTag(TodoBoardTags.DRAFT)
                    .fillMaxWidth()
                    .focusRequester(focus)
                    .onPreviewKeyEvent { e ->
                        if (e.type == KeyEventType.KeyDown && (e.key == Key.Enter || e.key == Key.NumPadEnter)) {
                            actions.onSubmitDraft(); true
                        } else false
                    },
            )
        }
        if (counter != null) Text(counter, style = captionStyle(), color = colors.label2, modifier = Modifier.padding(start = 6.dp))
    }
}

@Composable
private fun ListArea(state: TodoBoardViewState, actions: TodoBoardActions) {
    val colors = AingTheme.colors
    val sections = state.sections
    if (sections.isEntirelyEmpty) {
        // 빈 판은 목록 영역 한가운데(맥 emptyStateIsVerticallyCentredInTheListArea…).
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { EmptyState() }
        return
    }
    val card = RoundedCornerShape(10.dp)
    Column(
        Modifier
            .fillMaxSize()
            .background(colors.fill2, card)
            .border(1.dp, colors.separator, card)
            .padding(horizontal = 8.dp, vertical = 6.dp)
            .verticalScroll(rememberScrollState()),
    ) {
        if (sections.active.isEmpty()) Box(Modifier.fillMaxWidth().padding(vertical = 24.dp)) { EmptyState() }
        else Rows(sections.active, state, actions)
        if (sections.old.isNotEmpty()) {
            Divider(Modifier.padding(top = 8.dp, bottom = 4.dp))
            Row(
                Modifier
                    .testTag(TodoBoardTags.OLD_SECTION)
                    .fillMaxWidth()
                    .height(26.dp)
                    .clickable(onClick = actions.onToggleOldSection),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Text(if (state.isOldSectionExpanded) "▾" else "▸", style = captionStyle(), color = colors.label2)
                Text(TodoBoardStrings.oldSection(sections.old.size), style = captionStyle().copy(fontWeight = FontWeight.SemiBold), color = colors.label2, maxLines = 1)
            }
            if (state.isOldSectionExpanded) Rows(sections.old, state, actions)
        }
    }
}

@Composable
private fun EmptyState() {
    val colors = AingTheme.colors
    Column(Modifier.testTag(TodoBoardTags.EMPTY).fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(TodoBoardStrings.EMPTY_TITLE, style = captionStyle().copy(fontWeight = FontWeight.SemiBold), color = colors.label2)
        Text(TodoBoardStrings.EMPTY_HINT, style = captionStyle(), color = colors.label3)
    }
}

@Composable
private fun Rows(list: List<TodoItem>, state: TodoBoardViewState, actions: TodoBoardActions) {
    list.forEachIndexed { index, item ->
        RowView(item, state.todayKey, state.editingID == item.id, state.pendingDeleteID == item.id, actions)
        if (index < list.size - 1) Divider(Modifier.padding(start = TodoBoardMetrics.SEPARATOR_INSET.dp))
    }
}

@Composable
private fun RowView(item: TodoItem, todayKey: String, isEditing: Boolean, isPendingDelete: Boolean, actions: TodoBoardActions) {
    val colors = AingTheme.colors
    val hover = remember { MutableInteractionSource() }
    val hovering by hover.collectIsHoveredAsState()
    val rowModifier = Modifier.fillMaxWidth().heightIn(min = TodoBoardMetrics.ROW_MIN_HEIGHT.dp).hoverable(hover)
    if (isPendingDelete) {
        Row(rowModifier.padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(TodoBoardStrings.DELETED, style = bodyStyle(), color = colors.label2, maxLines = 1, modifier = Modifier.weight(1f))
            Box(
                Modifier
                    .testTag(TodoBoardTags.undo(item.id))
                    .height(22.dp)
                    .clip(RoundedCornerShape(7.dp))
                    .background(colors.accentTint, RoundedCornerShape(7.dp))
                    .border(1.dp, colors.accentLine, RoundedCornerShape(7.dp))
                    .clickable { actions.onUndoDelete(item.id) }
                    .padding(horizontal = 9.dp),
                contentAlignment = Alignment.Center,
            ) { Text(TodoBoardStrings.UNDO, style = captionStyle().copy(fontWeight = FontWeight.Bold), color = colors.accent) }
        }
        return
    }
    Row(rowModifier.padding(vertical = 6.dp), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        CheckCircle(item, actions)
        if (isEditing) {
            TitleEditor(item, actions, Modifier.weight(1f))
        } else {
            Text(
                item.title,
                style = bodyStyle(),
                color = if (item.isDone) colors.label3 else colors.label,
                textDecoration = if (item.isDone) TextDecoration.LineThrough else null,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier
                    .testTag(TodoBoardTags.title(item.id))
                    .weight(1f)
                    .pointerInput(item.id) { detectTapGestures(onDoubleTap = { actions.onBeginEdit(item.id) }) },
            )
        }
        val badge = if (item.isDone) null else TodoRules.carryBadge(TodoRules.carriedDays(item.originDayKey, todayKey))
        if (badge != null) {
            Text(
                badge,
                style = captionStyle().copy(fontSize = 9.sp, fontWeight = FontWeight.SemiBold),
                color = colors.label2,
                modifier = Modifier
                    .semantics { contentDescription = TodoBoardStrings.carriedFrom(badge) }
                    .background(colors.fill, CircleShape)
                    .padding(horizontal = 6.dp, vertical = 2.dp),
            )
        }
        // 지우기 단추는 늘 자리를 차지하고 알파만 바꾼다(맥 hoverDeleteButtonDoesNotResizeTheRow).
        Box(
            Modifier
                .testTag(TodoBoardTags.delete(item.id))
                .semantics { contentDescription = TodoBoardStrings.DELETE_ITEM }
                .size(16.dp)
                .alpha(if (hovering) 1f else 0f)
                .clickable { actions.onDelete(item.id) },
            contentAlignment = Alignment.Center,
        ) { Cross(colors.label2, 7f) }
    }
}

@Composable
private fun CheckCircle(item: TodoItem, actions: TodoBoardActions) {
    val colors = AingTheme.colors
    val ring = if (item.isDone) colors.separator else colors.label3
    val glyph = colors.label2
    val fill = colors.fill
    Canvas(
        Modifier
            .testTag(TodoBoardTags.check(item.id))
            .semantics { contentDescription = if (item.isDone) TodoBoardStrings.MARK_UNDONE else TodoBoardStrings.MARK_DONE }
            .padding(top = 1.dp)
            .size(TodoBoardMetrics.CHECK_SIZE.dp)
            .clip(CircleShape)
            .clickable { actions.onToggleDone(item.id) },
    ) {
        val stroke = 1.5.dp.toPx()
        val r = size.minDimension / 2
        if (item.isDone) drawCircle(fill, r)
        drawCircle(ring, r - stroke / 2, style = Stroke(stroke))
        if (item.isDone) {
            val p = Path().apply {
                moveTo(size.width * 0.30f, size.height * 0.52f)
                lineTo(size.width * 0.45f, size.height * 0.66f)
                lineTo(size.width * 0.72f, size.height * 0.36f)
            }
            drawPath(p, glyph, style = Stroke(stroke))
        }
    }
}

/** 인라인 수정(맥 TodoBoardTitleEditor): Enter 저장 · Esc 취소. 길이 판정은 초안과 같은 [TodoDraftInput]. */
@Composable
private fun TitleEditor(item: TodoItem, actions: TodoBoardActions, modifier: Modifier) {
    val colors = AingTheme.colors
    var text by remember(item.id) { mutableStateOf(item.title) }
    val focus = remember { FocusRequester() }
    LaunchedEffect(item.id) { runCatching { focus.requestFocus() } }
    BasicTextField(
        value = text,
        onValueChange = { text = TodoDraftInput.accepted(text, it) },
        singleLine = true,
        textStyle = bodyStyle().copy(color = colors.label),
        cursorBrush = SolidColor(colors.accent),
        modifier = modifier
            .testTag(TodoBoardTags.editor(item.id))
            .semantics { contentDescription = TodoBoardStrings.EDIT_TITLE }
            .border(1.dp, colors.accentLine, RoundedCornerShape(5.dp))
            .padding(horizontal = 4.dp, vertical = 1.dp)
            .focusRequester(focus)
            .onPreviewKeyEvent { e ->
                if (e.type != KeyEventType.KeyDown) return@onPreviewKeyEvent false
                when (e.key) {
                    Key.Enter, Key.NumPadEnter -> { actions.onCommitEdit(item.id, text); true }
                    Key.Escape -> { actions.onCancelEdit(); true }
                    else -> false
                }
            },
    )
}
