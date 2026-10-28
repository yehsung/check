// 원본: Sources/CheckMobileKit/Session/MobileSignUpView.swift @ 3bd04bd (teamBlock · modeSwitch · 팀 코드 정규화 + 미리보기 디바운스)
// 원본: Sources/CheckMobileKit/Now/NowTeamJoinCard.swift @ 3bd04bd (같은 모양의 팀 칸 — 무소속 카드)
// 원본: Sources/CheckMobileKit/Session/MobileTeamJoinForm.swift @ 3bd04bd (goalHoursRange 1~168)
//
// 팀 칸 한 벌(코드로 합류 ↔ 새 팀 만들기). 가입 화면과 지금 탭 무소속 카드가 같은 것을 쓴다(스토어도 한 벌 — W2-a TeamJoinForm).
//
// 칸 → 스토어는 한 방향이다(칸이 쥐고, 바뀔 때마다 스토어 흐름에 싣는다). Compose 의 칸 글에는 조합 중 글자가 들어 있으므로
// 스토어는 늘 마지막 음절까지 본다 — iOS 가 "포커스를 내려 조합을 확정한 뒤 다음 차례에 제출"한 까닭(마지막 음절이 바인딩에 없다)이
// 여기서는 생기지 않는다. 팀 코드 정규화(대문자 · 공백/하이픈 제거)는 **조합 중이 아닐 때만** 칸을 고친다(조합 중 편집은 IME 를 깬다).
package com.yehsung.aingcheck.ui.screens.session

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.text.input.TextFieldState
import androidx.compose.foundation.text.input.setTextAndPlaceCursorAtEnd
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.net.normalizeInviteCode
import com.yehsung.aingcheck.core.session.signup.SignUpText
import com.yehsung.aingcheck.core.session.team.TeamJoinForm
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.screens.session.kit.AingButton
import com.yehsung.aingcheck.ui.screens.session.kit.AingButtonKind
import com.yehsung.aingcheck.ui.screens.session.kit.AingButtonSize
import com.yehsung.aingcheck.ui.screens.session.kit.AingTextInput
import com.yehsung.aingcheck.ui.screens.session.kit.GroupRow
import com.yehsung.aingcheck.ui.screens.session.kit.InlineNotice
import com.yehsung.aingcheck.ui.screens.session.kit.InsetGroup
import com.yehsung.aingcheck.ui.screens.session.kit.NoticeKind
import com.yehsung.aingcheck.ui.screens.session.kit.isComposing
import com.yehsung.aingcheck.ui.screens.session.kit.sf
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow

/** 팀 칸 규칙(순수 — 시험이 잰다). */
object TeamFieldRules {
    /** 코드 미리보기 디바운스(Swift `MobileSignUpView.previewDebounceSeconds`). */
    const val PREVIEW_DEBOUNCE_MILLIS = 500L

    /** 칸에 정규화한 코드를 되쓸지: 조합 중이 아니고 정규화가 글을 바꿀 때만(되쓰면 다시 바뀌지 않아 고리가 없다). */
    fun normalizedCodeToWrite(text: String, composing: Boolean): String? {
        if (composing) return null
        val normalized = normalizeInviteCode(text)
        return if (normalized != text) normalized else null
    }

    /** 미리보기 줄 색: 찾음 · 확인 중은 안내, 그 밖(못 찾음 · 다른 센터)은 오류. */
    fun previewIsError(line: TeamJoinForm.PreviewLine): Boolean = !(line.isSuccess || line.text == SignUpText.previewChecking)

    /** 주간 목표 한 칸 올리기·내리기(1~168 안에서만). */
    fun stepGoal(current: Long, delta: Long): Long = (current + delta).coerceIn(TeamJoinForm.GOAL_HOURS_RANGE)
}

/** 칸 하나를 스토어 흐름에 잇는다(칸 → 흐름 한 방향 · 처음 값은 흐름에서). */
@Composable
fun rememberFlowField(flow: MutableStateFlow<String>): TextFieldState {
    val state = remember(flow) { TextFieldState(flow.value) }
    LaunchedEffect(state, flow) {
        snapshotFlow { state.text.toString() }.collect { text -> if (flow.value != text) flow.value = text }
    }
    return state
}

/**
 * 팀 칸(코드 ↔ 만들기) + 미리보기 줄. [onSubmit] 은 칸의 [가기] 키(제출은 부르는 쪽 단추와 같은 문). 모드 바꾸기 줄은 [TeamModeSwitch].
 */
@Composable
fun TeamJoinFields(form: TeamJoinForm, onSubmit: () -> Unit, modifier: Modifier = Modifier) {
    val colors = AingTheme.colors
    val createMode by form.isCreateTeamMode.collectAsState()
    val goal by form.createTeamGoalHours.collectAsState()
    val previewMessage by form.joinPreviewMessage.collectAsState()
    val preview by form.joinPreview.collectAsState()
    val code = rememberFlowField(form.teamCode)
    val teamName = rememberFlowField(form.createTeamName)

    if (!createMode) {
        // 대문자 · 공백/하이픈 제거(맥 TeamCodeField) → 0.5초 디바운스 뒤 미리보기(마지막 요청 우선 — 스토어가 경합을 막는다).
        LaunchedEffect(code, form) {
            snapshotFlow { code.text.toString() to code.isComposing }.collect { (text, composing) ->
                TeamFieldRules.normalizedCodeToWrite(text, composing)?.let { code.setTextAndPlaceCursorAtEnd(it) }
            }
        }
        LaunchedEffect(form) {
            var last: String? = null
            snapshotFlow { normalizeInviteCode(code.text.toString()) }.collect { normalized ->
                if (normalized == last) return@collect
                last = normalized
                delay(TeamFieldRules.PREVIEW_DEBOUNCE_MILLIS)
                form.previewTeamCode()
            }
        }
    }

    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (createMode) {
            InsetGroup {
                FieldRow("person.3", AppIcon.Groups, divider = true) {
                    // 팀 이름은 한글 허용(ASCII 강제 없음 — 맥과 같다).
                    AingTextInput(teamName, SignUpText.teamName, Modifier.weight(1f),
                        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Go), onSubmit = onSubmit, tag = TeamTags.TEAM_NAME)
                }
                GroupRow(dividerInset = null, minHeight = FIELD_ROW_HEIGHT) {
                    AingIcon(sf("target", AppIcon.Target), null, size = 20.dp, tint = colors.label2, modifier = Modifier.size(FIELD_ICON))
                    Text(SignUpText.weeklyGoal, style = MaterialTheme.typography.bodyLarge, color = colors.label, modifier = Modifier.weight(1f))
                    Text(SignUpText.goalHours(goal), style = MaterialTheme.typography.bodyLarge, color = colors.label,
                        modifier = Modifier.semantics { contentDescription = SignUpText.weeklyGoal; stateDescription = SignUpText.goalHours(goal) })
                    StepperButtons(
                        onMinus = { form.createTeamGoalHours.value = TeamFieldRules.stepGoal(goal, -1) },
                        onPlus = { form.createTeamGoalHours.value = TeamFieldRules.stepGoal(goal, 1) },
                        canMinus = goal > TeamJoinForm.GOAL_HOURS_RANGE.first, canPlus = goal < TeamJoinForm.GOAL_HOURS_RANGE.last,
                    )
                }
            }
        } else {
            InsetGroup {
                FieldRow("key", AppIcon.Key, divider = false) {
                    AingTextInput(code, SignUpText.teamCode, Modifier.weight(1f),
                        keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Characters, autoCorrectEnabled = false,
                            keyboardType = KeyboardType.Ascii, imeAction = ImeAction.Go),
                        onSubmit = onSubmit, tag = TeamTags.TEAM_CODE)
                }
            }
            // 두 흐름을 읽어 구독하고(다시 그리기) 줄 값은 스토어 판정 그대로 쓴다(문구가 요약보다 먼저).
            val line = if (previewMessage.isEmpty() && preview == null) null else form.previewLine
            line?.let { InlineNotice(it.text, if (TeamFieldRules.previewIsError(it)) NoticeKind.Error else NoticeKind.Info) }
        }
    }
}

/** 모드 바꾸기 줄: "팀 코드가 없나요? [새 팀 만들기]" ↔ "[코드로 참여하기]". */
@Composable
fun TeamModeSwitch(createMode: Boolean, enabled: Boolean, onToggle: () -> Unit) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.Center, verticalAlignment = Alignment.CenterVertically) {
        if (!createMode) Text(SignUpText.noCodePrompt, style = MaterialTheme.typography.bodySmall, color = AingTheme.colors.label2)
        AingButton(if (createMode) SignUpText.switchToCode else SignUpText.switchToCreate, onToggle,
            kind = AingButtonKind.Plain, size = AingButtonSize.Sm, enabled = enabled)
    }
}

/** − / + 단추 한 쌍(iOS Stepper). */
@Composable
fun StepperButtons(onMinus: () -> Unit, onPlus: () -> Unit, canMinus: Boolean, canPlus: Boolean) {
    val colors = AingTheme.colors
    Row(horizontalArrangement = Arrangement.spacedBy(2.dp)) {
        for ((label, enabled, action) in listOf(Triple("−", canMinus, onMinus), Triple("+", canPlus, onPlus))) {
            Text(
                label,
                style = MaterialTheme.typography.titleMedium,
                color = if (enabled) colors.accent else colors.label3Text,
                modifier = Modifier
                    .size(44.dp)
                    .clickable(enabled = enabled, role = Role.Button, onClick = action)
                    .padding(top = 10.dp)
                    .semantics { contentDescription = if (label == "+") "늘리기" else "줄이기" },
                textAlign = androidx.compose.ui.text.style.TextAlign.Center,
            )
        }
    }
}

object TeamTags {
    const val TEAM_CODE = "team-code"
    const val TEAM_NAME = "team-name"
}
