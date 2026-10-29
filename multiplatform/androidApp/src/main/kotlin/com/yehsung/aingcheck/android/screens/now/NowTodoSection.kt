// 원본: Sources/CheckMobileKit/Now/NowTodoSection.swift @ 3bd04bd (NowTodoSection · NowUndoToast · NowGoalSheet · NowCheckButton · NowAddGlyph)
// 원본: Sources/CheckMobileKit/Now/NowTeamJoinCard.swift @ 3bd04bd (NowTeamJoinSection — 무소속 카드)
//
// 오늘 할 일(입력 · 줄 · 오래된 항목 · 삭제 되돌리기 토스트) · 주간 목표 시트 · 무소속 팀 합류 카드.
//
// 할 일 입력은 **자르지 않는다**(E§8.2 ④): iOS 는 100자를 넘는 입력을 되돌렸다(NowTodoDraft.accepted) — 조합 중 되돌리기는 IME 를 깬다.
// 여기서는 넘치면 카운터를 빨갛게 하고 [추가]·[완료]를 막는다(TodoInputRules). 엔진(TodoListStore)도 상한 초과를 받지 않는다.
package com.yehsung.aingcheck.android.screens.now

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.text.input.TextFieldState
import androidx.compose.foundation.text.input.clearText
import androidx.compose.foundation.text.input.rememberTextFieldState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.session.team.TeamJoinStore
import com.yehsung.aingcheck.core.stores.now.NowStore
import com.yehsung.aingcheck.core.stores.now.NowText
import com.yehsung.aingcheck.core.stores.now.NowTodoDraft
import com.yehsung.aingcheck.core.stores.now.NowTodoRow
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.screens.messages.TodoInputRules
import com.yehsung.aingcheck.ui.screens.session.TeamJoinFields
import com.yehsung.aingcheck.ui.screens.session.TeamModeSwitch
import com.yehsung.aingcheck.ui.screens.session.kit.AingButton
import com.yehsung.aingcheck.ui.screens.session.kit.AingButtonSize
import com.yehsung.aingcheck.ui.screens.session.kit.AingCard
import com.yehsung.aingcheck.ui.screens.session.kit.AingTextInput
import com.yehsung.aingcheck.ui.screens.session.kit.InlineNotice
import com.yehsung.aingcheck.ui.screens.session.kit.NoticeKind
import com.yehsung.aingcheck.ui.screens.session.kit.SectionHeader
import com.yehsung.aingcheck.ui.screens.session.kit.SheetHeader
import com.yehsung.aingcheck.ui.screens.session.kit.sf
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.launch

/** 오늘 할 일 절. */
@Composable
internal fun NowTodoSection(store: NowStore) {
    val colors = AingTheme.colors
    val rows = store.todoRows()
    val remaining = store.remainingTodoCount
    val draft = rememberTextFieldState()
    var oldExpanded by rememberSaveable { mutableStateOf(false) }
    val isEmpty = rows.main.isEmpty() && rows.old.isEmpty()
    SectionHeader(NowText.todoTitle, if (remaining > 0) NowText.todoRemaining(remaining) else null)
    Column(Modifier.padding(horizontal = AingDimens.sideMargin).fillMaxWidth().background(colors.surface, RoundedCornerShape(AingDimens.groupRadius))) {
        TodoInputRow(store, draft)
        if (isEmpty) {
            Divider(TEXT_LEADING)
            Column(Modifier.padding(16.dp).semantics(mergeDescendants = true) {}, verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(NowText.todoEmptyTitle, style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.SemiBold), color = colors.label)
                Text(NowText.todoEmptyHint, style = MaterialTheme.typography.bodySmall, color = colors.label2)
            }
        }
        for (row in rows.main) {
            Divider(TEXT_LEADING)
            TodoRow(store, row)
        }
        if (rows.old.isNotEmpty()) {
            Divider(AingDimens.cardPadding)
            Row(
                Modifier.fillMaxWidth().heightIn(min = 44.dp).clickable { oldExpanded = !oldExpanded }
                    .semantics { contentDescription = NowText.todoOldSection(rows.old.size); stateDescription = if (oldExpanded) "펼침" else "접힘" }
                    .padding(horizontal = AingDimens.cardPadding),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Text(NowText.todoOldTitle, style = MaterialTheme.typography.titleSmall.copy(fontWeight = FontWeight.Normal), color = colors.label, modifier = Modifier.weight(1f))
                Text("${rows.old.size}", style = MaterialTheme.typography.bodyMedium, color = colors.label2)
                AingIcon(if (oldExpanded) sf("chevron.down", AppIcon.ExpandMore) else sf("chevron.right", AppIcon.ChevronRight), null, size = 18.dp, tint = colors.label3)
            }
            if (oldExpanded) {
                for (row in rows.old) {
                    Divider(TEXT_LEADING)
                    TodoRow(store, row)
                }
            }
        }
    }
}

@Composable
private fun Divider(start: androidx.compose.ui.unit.Dp) =
    HorizontalDivider(Modifier.padding(start = start), thickness = AingDimens.hairline, color = AingTheme.colors.separator)

private val TEXT_LEADING = 50.dp

/** 누르는 칸(44)이 보이는 원(22)보다 넘치는 한쪽 폭. */
private val CHECK_OVERHANG = 11.dp

/** 입력 줄: (+) · 칸 · 카운터(90자부터) · [추가]. 연달아 적을 수 있게 추가한 뒤에도 칸에 남는다. */
@Composable
private fun TodoInputRow(store: NowStore, draft: TextFieldState) {
    val colors = AingTheme.colors
    val text = draft.text.toString()
    val enabled = store.canEditTodos
    fun submit() {
        if (!TodoInputRules.canSubmit(text)) return
        if (store.addTodo(draft.text.toString())) draft.clearText()
    }
    Row(
        Modifier.fillMaxWidth().heightIn(min = 48.dp).padding(horizontal = AingDimens.cardPadding, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        AingIcon(sf("plus.circle.fill", AppIcon.AddCircleFill), null, size = 22.dp, tint = if (enabled) colors.accent else colors.label3)
        AingTextInput(draft, NowText.todoPlaceholder, Modifier.weight(1f), style = MaterialTheme.typography.titleSmall.copy(fontWeight = FontWeight.Normal),
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done), onSubmit = ::submit, enabled = enabled, tag = NowTags.TODO_FIELD)
        NowTodoDraft.counterText(text)?.let { counter ->
            Text(counter, style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.Normal),
                color = if (TodoInputRules.isOverLimit(text)) colors.danger else colors.label2)
        }
        if (TodoInputRules.showsAdd(text)) {
            AingButton(NowText.todoAdd, ::submit, Modifier.testTag(NowTags.TODO_ADD),
                kind = com.yehsung.aingcheck.ui.screens.session.kit.AingButtonKind.Plain, size = AingButtonSize.Sm, enabled = TodoInputRules.canSubmit(text))
        }
    }
}

/** 할 일 한 줄: 체크(44 누름 칸) · 제목(누르면 고치기) · 이월 배지. 왼쪽으로 밀면 삭제(→ 5초 되돌리기 토스트). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun TodoRow(store: NowStore, row: NowTodoRow) {
    val colors = AingTheme.colors
    val editing = store.editingTodoID == row.id
    val dismiss = rememberSwipeToDismissBoxState(confirmValueChange = { value ->
        if (value == SwipeToDismissBoxValue.EndToStart) store.deleteTodo(row.id)
        false
    })
    SwipeToDismissBox(
        dismiss,
        backgroundContent = {
            Box(Modifier.fillMaxWidth().heightIn(min = 44.dp).background(colors.danger).padding(end = 20.dp), contentAlignment = Alignment.CenterEnd) {
                AingIcon(sf("trash", AppIcon.Delete), NowText.todoDelete, size = 20.dp, tint = colors.onAccentFill)
            }
        },
        enableDismissFromStartToEnd = false,
    ) {
        // 체크 칸은 누르는 자리 44 · 보이는 원 22(iOS 와 같은 자리 — 원은 줄 여백 16 에서 시작하고 글자는 50 에서 시작한다).
        Row(
            Modifier.fillMaxWidth().background(colors.surface).heightIn(min = 44.dp)
                .padding(start = AingDimens.cardPadding - CHECK_OVERHANG, end = AingDimens.cardPadding, top = 4.dp, bottom = 4.dp)
                .semantics { customActions = listOf(CustomAccessibilityAction(NowText.todoDelete) { store.deleteTodo(row.id); true }) }
                .testTag(NowTags.todoRow(row.id)),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(1.dp),
        ) {
            CheckButton(row.isDone, row.title, Modifier.testTag(NowTags.todoCheck(row.id))) { store.toggleTodo(row.id) }
            if (editing) {
                TodoEditField(store, row)
            } else {
                Text(
                    row.title,
                    style = MaterialTheme.typography.titleSmall.copy(fontWeight = FontWeight.Normal,
                        textDecoration = if (row.isDone) TextDecoration.LineThrough else TextDecoration.None),
                    color = if (row.isDone) colors.label3Text else colors.label,
                    modifier = Modifier.weight(1f).clickable(enabled = store.canEditTodos, onClickLabel = NowText.todoEdit) { store.beginEditing(row.id) },
                )
            }
            row.carryBadge?.let { badge ->
                Text(badge, style = MaterialTheme.typography.labelSmall, color = colors.label2,
                    modifier = Modifier.padding(start = 11.dp).background(colors.fill, RoundedCornerShape(6.dp)).padding(horizontal = 6.dp, vertical = 2.dp))
            }
        }
    }
}

/** 고치는 칸: [완료] 키 또는 포커스가 떠나면 확정(넘치면 막는다 — 원래 문장이 남는다). */
@Composable
private fun androidx.compose.foundation.layout.RowScope.TodoEditField(store: NowStore, row: NowTodoRow) {
    val state = remember(row.id) { TextFieldState(row.title) }
    fun commit() {
        val text = state.text.toString()
        if (TodoInputRules.canSubmit(text)) store.commitEditing(row.id, text) else store.cancelEditing()
    }
    DisposableEffect(row.id) {
        onDispose { if (store.editingTodoID == row.id) commit() }
    }
    AingTextInput(state, NowText.todoEditPlaceholder, Modifier.weight(1f), style = MaterialTheme.typography.titleSmall.copy(fontWeight = FontWeight.Normal),
        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done), onSubmit = ::commit)
}

/** 체크 원(22 · 누름 칸 44). */
@Composable
private fun CheckButton(isOn: Boolean, title: String, modifier: Modifier, onClick: () -> Unit) {
    val colors = AingTheme.colors
    Box(
        modifier.size(44.dp).clickable(role = Role.Checkbox, onClick = onClick)
            .semantics { contentDescription = if (isOn) NowText.todoMarkUndone else NowText.todoMarkDone; stateDescription = title },
        contentAlignment = Alignment.Center,
    ) {
        if (isOn) {
            Box(Modifier.size(22.dp).background(colors.accentFill, CircleShape), contentAlignment = Alignment.Center) {
                AingIcon(sf("checkmark", AppIcon.Check), null, size = 14.dp, tint = colors.onAccentFill)
            }
        } else {
            Box(Modifier.size(22.dp).border(1.8.dp, colors.label3, CircleShape))
        }
    }
}

/** "삭제됨 · 되돌리기" 토스트(5초 — 스토어 타이머). */
@Composable
internal fun NowUndoToast(store: NowStore, modifier: Modifier = Modifier) {
    val colors = AingTheme.colors
    if (store.undoTodoID == null) return
    Row(
        modifier.padding(horizontal = AingDimens.sideMargin, vertical = 12.dp).fillMaxWidth()
            .background(colors.glass, CircleShape).padding(start = 18.dp, end = 6.dp, top = 4.dp, bottom = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        AingIcon(sf("trash", AppIcon.Delete), null, size = 18.dp, tint = colors.label2)
        Text(NowText.todoDeleted, style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.SemiBold), color = colors.label, modifier = Modifier.weight(1f))
        Box(Modifier.heightIn(min = 44.dp).clickable(role = Role.Button) { store.undoDelete() }.padding(horizontal = 12.dp).testTag(NowTags.TODO_UNDO),
            contentAlignment = Alignment.Center) {
            Text(NowText.todoUndo, style = MaterialTheme.typography.bodyMedium.copy(fontWeight = FontWeight.Bold), color = colors.accent)
        }
    }
}

/** 주간 목표 시트(1인당 · 1~168시간 · 팀 전체가 같이 바뀐다). 저장하면 닫는다. */
@Composable
fun NowGoalSheet(store: NowStore, onClose: () -> Unit, modifier: Modifier = Modifier) {
    val colors = AingTheme.colors
    var hours by rememberSaveable { mutableIntStateOf(store.goalHours.coerceIn(NowStore.goalRange)) }
    val scope = rememberCoroutineScope()
    DisposableEffect(store) { onDispose { store.clearGoalNotice() } }
    Column(modifier.fillMaxWidth().background(colors.background).testTag(NowTags.GOAL_SHEET)) {
        SheetHeader(NowText.goalSheetTitle, onClose, closeLabel = NowText.close)
        Column(Modifier.verticalScroll(rememberScrollState()).padding(horizontal = AingDimens.sideMargin, vertical = AingDimens.rowSpacing),
            verticalArrangement = Arrangement.spacedBy(AingDimens.rowSpacing)) {
            AingCard {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f).semantics(mergeDescendants = true) { stateDescription = "${hours}시간" }) {
                        Text(NowText.goalStepperLabel, style = MaterialTheme.typography.bodyMedium, color = colors.label2)
                        Text("${hours}시간", style = MaterialTheme.typography.headlineSmall, color = colors.label)
                    }
                    com.yehsung.aingcheck.ui.screens.session.StepperButtons(
                        onMinus = { hours = (hours - 1).coerceIn(NowStore.goalRange) },
                        onPlus = { hours = (hours + 1).coerceIn(NowStore.goalRange) },
                        canMinus = hours > NowStore.goalRange.first, canPlus = hours < NowStore.goalRange.last,
                    )
                }
            }
            InlineNotice(NowText.goalExplain, NoticeKind.Info)
            store.goalNotice?.let { InlineNotice(it, NoticeKind.Error) }
            AingButton(NowText.goalSave, { scope.launch { if (store.saveGoal(hours)) onClose() } }, Modifier.testTag(NowTags.GOAL_SAVE),
                size = AingButtonSize.Lg, fillsWidth = true, isBusy = store.isSavingGoal)
        }
    }
}

/**
 * 무소속 카드: 안내 · 팀 칸(가입 화면과 같은 한 벌) · 미리보기 줄 · 실패 줄 · [참여하기]/[새 팀 만들기] · 모드 바꾸기.
 * INV-NowTeamJoinCard-06d6baf6 이식: 팀 이름의 한글 조합 — iOS 는 포커스를 내려 마지막 음절을 확정한 뒤 다음 차례에 제출했다. Compose 칸은 조합 글을
 *   글 안에 들고 바뀔 때마다 스토어 흐름에 싣는다(TeamJoinFields · rememberFlowField) — 제출 순간 스토어는 마지막 음절까지 본다.
 */
@Composable
internal fun NowTeamJoinSection(store: TeamJoinStore) {
    val colors = AingTheme.colors
    val notice by store.noticeFlow.collectAsState()
    val submitting by store.isSubmittingFlow.collectAsState()
    val createMode by store.form.isCreateTeamMode.collectAsState()
    DisposableEffect(store) { onDispose { store.cancelPendingWork() } }
    Column(Modifier.fillMaxWidth().testTag(NowTags.TEAM_JOIN), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        AingCard {
            Text(NowText.noTeamTitle, style = MaterialTheme.typography.titleMedium, color = colors.label)
            Text(NowText.noTeamBody, style = MaterialTheme.typography.bodyMedium, color = colors.label2)
        }
        TeamJoinFields(store.form, onSubmit = { store.submit() })
        notice?.let { InlineNotice(it, NoticeKind.Error) }
        AingButton(store.primaryTitle, { store.submit() }, size = AingButtonSize.Lg, fillsWidth = true, isBusy = submitting, enabled = store.canSubmit)
        TeamModeSwitch(createMode, enabled = !submitting) { store.toggleCreateTeamMode() }
    }
}
