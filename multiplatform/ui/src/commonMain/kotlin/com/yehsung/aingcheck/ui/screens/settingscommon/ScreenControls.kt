// 원본: Sources/CheckMobileKit/Components/MobileComponents.swift @ 3bd04bd (AingCard · AingButton 종류 넷 · EmptyStateView · 칸 안 글자 수 입력줄)
//
// 화면 2(나 · 설정) 하위 화면이 같이 쓰는 조작 부품. 색은 전부 테마 토큰(D5 — 화면이 색 리터럴을 만들지 않는다).
// 원본: Sources/CheckMobileKit/Components/AingButtons.swift @ 3bd04bd (AingButtonStyle — 종류 · 캡슐 · 높이 50/30 · 비활성은 fill2 + label2)
//
// 버튼 종류의 뜻(Swift AingButton): 채운(filled) = 화면당 하나인 주 동작 · 틴트(tinted) = 드문 동작 · 회색(gray) = 지우기 같은 보조 · 글자(plain).
// 비활성은 라이트·다크 모두 회색 판(fill2) + 보조 글자(label2) — 흐리게만 하면 라이트에서 1.1~1.3:1 로 안 보였다(Swift w15 검증).
package com.yehsung.aingcheck.ui.screens.settingscommon

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.foundation.platform.GraphemeCounter
import com.yehsung.aingcheck.core.rules.text.Graphemes
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.theme.AingDimens
import com.yehsung.aingcheck.ui.theme.AingTheme

/** 카드 한 장(카드 면 · 모서리 22 · 안쪽 16 · 줄 간격 12). Swift `AingCard`. */
@Composable
fun AingCard(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Column(
        modifier
            .fillMaxWidth()
            .background(AingTheme.colors.surface, RoundedCornerShape(AingDimens.groupRadius))
            .padding(AingDimens.cardPadding),
        verticalArrangement = Arrangement.spacedBy(AingDimens.rowSpacing),
        content = content,
    )
}

/** 버튼 종류(뜻이 다르면 모양도 다르다 — 채운 버튼은 화면당 하나). */
enum class AingButtonKind { Filled, Tinted, Gray, Plain }

/**
 * Swift `AingButton`. [busy] 면 글자 대신 도는 표시를 세우고 누름을 막는다(두 번 눌러 두 번 보내지 않게).
 * [small] 은 목록 줄 끝의 작은 버튼(차단 해제 등 — Swift `.sm`) — 보이는 높이 30, 누름 영역은 줄이 44 를 채운다.
 */
@Composable
fun AingButton(
    title: String,
    kind: AingButtonKind,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    busy: Boolean = false,
    fillsWidth: Boolean = false,
    small: Boolean = false,
    icon: AppIcon? = null,
) {
    val colors = AingTheme.colors
    val (container, content) = when (kind) {
        AingButtonKind.Filled -> colors.accentFill to colors.onAccentFill
        AingButtonKind.Tinted -> colors.accentTint to colors.accent
        AingButtonKind.Gray -> colors.fill to colors.label
        AingButtonKind.Plain -> androidx.compose.ui.graphics.Color.Transparent to colors.accent
    }
    Button(
        onClick = { if (!busy) onClick() },
        enabled = enabled && !busy,
        modifier = (if (fillsWidth) modifier.fillMaxWidth() else modifier).heightIn(min = if (small) 30.dp else 50.dp),
        shape = RoundedCornerShape(percent = 50),
        colors = ButtonDefaults.buttonColors(
            containerColor = container,
            contentColor = content,
            disabledContainerColor = if (kind == AingButtonKind.Plain) container else colors.fill2,
            disabledContentColor = colors.label2,
        ),
        contentPadding = if (small) PaddingValues(horizontal = 12.dp, vertical = 4.dp) else ButtonDefaults.ContentPadding,
    ) {
        if (busy) {
            CircularProgressIndicator(Modifier.size(if (small) 14.dp else 18.dp), color = content, strokeWidth = 2.dp)
        } else {
            if (icon != null) {
                AingIcon(icon, contentDescription = null, size = if (small) 14.dp else 18.dp, tint = content)
                Box(Modifier.size(6.dp))
            }
            Text(
                title,
                style = if (small) MaterialTheme.typography.labelMedium else MaterialTheme.typography.labelLarge.copy(fontWeight = FontWeight.SemiBold),
                maxLines = 1,
            )
        }
    }
}

/** 빈 상태(기호 · 제목 · 한 줄). Swift `EmptyStateView`. */
@Composable
fun EmptyStateView(icon: AppIcon, title: String, message: String?, modifier: Modifier = Modifier) {
    val colors = AingTheme.colors
    Column(
        modifier.fillMaxWidth().padding(vertical = AingDimens.space3),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(AingDimens.space1),
    ) {
        AingIcon(icon, contentDescription = null, size = 28.dp, tint = colors.label3)
        Text(title, style = MaterialTheme.typography.titleSmall, color = colors.label, textAlign = TextAlign.Center)
        if (message != null) Text(message, style = MaterialTheme.typography.bodySmall, color = colors.label2, textAlign = TextAlign.Center)
    }
}

/** 화면 글자 수(Swift `String.count` — 확장 그래핌). 코어 규칙이 GraphemeCounter 를 받는 자리에 넘긴다. */
object ScreenGraphemes : GraphemeCounter {
    override fun count(text: String): Int = Graphemes.count(text)
}

/**
 * 한 줄 입력칸 + 칸 **안** 오른쪽 글자 수("7/12" — 넘치면 위험색). Swift 프로필 별명·상태메시지 칸(w11 캡처 35: 칸 밖에 두면 칸이 짧아졌다).
 *
 * 글자를 자르지 않는다 — 조합 중(한글 IME)에 잘라내면 조합이 깨진다(E§8). 넘친 값은 저장 단추가 막는다(스토어 canSave…).
 */
@Composable
fun CountedTextField(
    value: String,
    onValueChange: (String) -> Unit,
    placeholder: String,
    count: Int,
    max: Int,
    accessibilityLabel: String,
    modifier: Modifier = Modifier,
    fieldModifier: Modifier = Modifier,
    enabled: Boolean = true,
    onDone: () -> Unit = {},
) {
    val colors = AingTheme.colors
    val over = count > max
    Row(
        modifier
            .fillMaxWidth()
            .heightIn(min = AingDimens.minimumTarget)
            .background(colors.fill, RoundedCornerShape(AingDimens.innerRadius))
            .padding(horizontal = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(AingDimens.space2),
    ) {
        Box(Modifier.weight(1f).padding(vertical = 10.dp)) {
            BasicTextField(
                value = value,
                onValueChange = onValueChange,
                enabled = enabled,
                singleLine = true,
                textStyle = MaterialTheme.typography.bodyLarge.copy(color = if (enabled) colors.label else colors.label2),
                cursorBrush = SolidColor(colors.accent),
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done, autoCorrectEnabled = false),
                keyboardActions = KeyboardActions(onDone = { onDone() }),
                modifier = fieldModifier.fillMaxWidth().semantics { contentDescription = accessibilityLabel },
            )
            if (value.isEmpty()) Text(placeholder, style = MaterialTheme.typography.bodyLarge, color = colors.label3Text)
        }
        Text(
            "$count/$max",
            style = MaterialTheme.typography.bodySmall,
            color = if (over) colors.danger else colors.label3Text,
            modifier = Modifier.semantics { contentDescription = "${count}자, 최대 ${max}자" },
        )
    }
}
