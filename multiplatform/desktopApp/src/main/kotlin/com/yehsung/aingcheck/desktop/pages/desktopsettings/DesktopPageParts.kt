// 원본: Sources/check/CheckSettingsView.swift:1660-1683(절 — 작은 회색 머리 + 패널 카드, 행 간격 12) · :158-185(설정 행) ·
//       CheckTheme.panelStyle(모서리 12). c4 네 페이지(AI 토큰·AI 리밋·기기·컴퓨터 설정)가 같이 쓰는 뼈대.
package com.yehsung.aingcheck.desktop.pages.desktopsettings

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.theme.AingTheme

/** 페이지 뼈대: 뒤로 + 제목 한 줄, 아래는 스크롤(맥 설정 창 ViewThatFits — 넘치면 잘리는 대신 스크롤). 바깥 여백 14(맥 :1488). */
@Composable
fun DesktopPageScaffold(title: String, onBack: () -> Unit, modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    val colors = AingTheme.colors
    Column(modifier.fillMaxSize().background(colors.background)) {
        Row(
            Modifier.fillMaxWidth().height(44.dp).padding(horizontal = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                Modifier.size(32.dp).clickable(role = Role.Button, onClick = onBack),
                contentAlignment = Alignment.Center,
            ) { AingIcon(AppIcon.ChevronLeft, contentDescription = "뒤로", size = 20.dp, tint = colors.label) }
            Text(title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, color = colors.label)
        }
        Column(
            Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(start = 14.dp, end = 14.dp, bottom = 14.dp),
            verticalArrangement = Arrangement.spacedBy(14.dp),
            content = content,
        )
    }
}

/** 절 하나(맥 section — 머리 caption2 semibold 회색 · 들여 2 · 카드 안 간격 12 · 안쪽 여백 12). */
@Composable
fun MacSection(title: String, trailing: (@Composable RowScope.() -> Unit)? = null, content: @Composable ColumnScope.() -> Unit) {
    val colors = AingTheme.colors
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(Modifier.fillMaxWidth().padding(start = 2.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(title, fontSize = 11.sp, fontWeight = FontWeight.SemiBold, color = colors.label2, modifier = Modifier.weight(1f))
            if (trailing != null) trailing()
        }
        MacPanel(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(12.dp), content = content)
        }
    }
}

/** 패널 면(맥 panelStyle — 모서리 12, 옅은 테두리). */
@Composable
fun MacPanel(modifier: Modifier = Modifier, content: @Composable () -> Unit) {
    val colors = AingTheme.colors
    val shape = RoundedCornerShape(12.dp)
    Box(modifier.background(colors.surface, shape).border(1.dp, colors.separator, shape)) { content() }
}

@Composable
fun PanelDivider() {
    Box(Modifier.fillMaxWidth().height(1.dp).background(AingTheme.colors.separator))
}

/** 설명 한 줄(맥 caption2 회색). */
@Composable
fun CaptionLine(text: String, modifier: Modifier = Modifier) {
    Text(text, fontSize = 11.sp, lineHeight = 15.sp, color = AingTheme.colors.label2, modifier = modifier)
}

@Composable
fun VerticalGap(height: Int) = Spacer(Modifier.height(height.dp))
