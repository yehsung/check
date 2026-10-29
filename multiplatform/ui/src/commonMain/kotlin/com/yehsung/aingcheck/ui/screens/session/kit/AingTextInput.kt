// 원본: Sources/CheckMobileKit/Session/MobileSessionViews.swift @ 3bd04bd (입력 줄 — 자리표시는 3단 회색 글자)
// 원본: Sources/CheckMobileKit/Messages/MessagesComposerView.swift @ 3bd04bd (조합 중이면 자리표시를 그리지 않는다 · 바깥 값으로 덮지 않는다)
//
// 입력칸 한 벌(E§8.2 ①: 상태 기반 BasicTextField(state = TextFieldState) — 값·콜백 방식보다 IME 와 상태가 한 곳에 있다).
//
// ★ 이 파일의 입력칸은 **글자를 자르지 않는다**(E§8.2 ④ · G §2-3 W3-a ④ "조합 중 자르기 0"). InputTransformation 도, 값 콜백에서의
//   take(…) 도 없다 — 상한(메시지 200 · 확성기 · 할 일 100 · 신고 1000 · 별명)은 카운터를 빨갛게 하고 [보내기]/[저장]에서 막는다.
//   조합 중 잘라내기가 IME 를 깨는 주범이다(삼성 키보드 StringIndexOutOfBounds · 자모 분리 보고 — E§8.1). 구조 시험
//   `NoTruncationWhileComposingStructureTest` 가 이 갈래의 화면 소스에서 자르는 꼴을 찾는다.
package com.yehsung.aingcheck.ui.screens.session.kit

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.text.BasicSecureTextField
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.text.input.KeyboardActionHandler
import androidx.compose.foundation.text.input.TextFieldLineLimits
import androidx.compose.foundation.text.input.TextFieldState
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.style.TextOverflow
import com.yehsung.aingcheck.ui.theme.AingTheme

/** 조합 중인가(조합 영역이 있다). 판정은 순수 함수가 받는 사실 하나다 — 화면은 이 값만 넘긴다. */
val TextFieldState.isComposing: Boolean get() = composition != null

/** 자리표시를 그릴지: 글이 비었고 조합 중이 아닐 때만(iOS `draft.isEmpty && !isComposing`). */
fun placeholderVisible(text: CharSequence, composing: Boolean): Boolean = text.isEmpty() && !composing

/**
 * 한 줄 · 여러 줄 입력칸. 자리표시는 3단 회색 글자(파랑이면 미리 채운 값처럼 읽힌다).
 * [secure] 면 비밀번호 칸(가림).
 */
@Composable
fun AingTextInput(
    state: TextFieldState,
    placeholder: String,
    modifier: Modifier = Modifier,
    style: TextStyle = MaterialTheme.typography.bodyLarge,
    keyboardOptions: KeyboardOptions = KeyboardOptions.Default,
    onSubmit: (() -> Unit)? = null,
    lineLimits: TextFieldLineLimits = TextFieldLineLimits.SingleLine,
    enabled: Boolean = true,
    secure: Boolean = false,
    tag: String? = null,
) {
    val colors = AingTheme.colors
    val textStyle = style.copy(color = colors.label)
    val handler = onSubmit?.let { submit -> KeyboardActionHandler { submit() } }
    val fieldModifier = Modifier.fillMaxWidth()
        .semantics { contentDescription = placeholder }
        .then(if (tag != null) Modifier.testTag(tag) else Modifier)
    Box(modifier) {
        if (placeholderVisible(state.text, state.isComposing)) {
            Text(placeholder, style = style, color = colors.label3Text, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        if (secure) {
            BasicSecureTextField(
                state = state,
                modifier = fieldModifier,
                enabled = enabled,
                textStyle = textStyle,
                keyboardOptions = keyboardOptions,
                onKeyboardAction = handler,
                cursorBrush = SolidColor(colors.accent),
            )
        } else {
            BasicTextField(
                state = state,
                modifier = fieldModifier,
                enabled = enabled,
                textStyle = textStyle,
                keyboardOptions = keyboardOptions,
                onKeyboardAction = handler,
                lineLimits = lineLimits,
                cursorBrush = SolidColor(colors.accent),
            )
        }
    }
}
