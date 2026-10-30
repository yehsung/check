// 원본: Sources/check/CheckSettingsView.swift:261-345(AILimitMainDeviceSettingsRow — 제목·설명 + 기기 줄, 고른 줄은 게이지 색 + ✓) ·
//       Sources/check/AILimitDevicePickerLayout.swift(줄 높이 26 · 간격 6 · 좌우 10 · ✓ 칸 12 · 글자 12) ·
//       CheckCore AILimitDeviceRoster.displayNameParts(이름이 겹치면 꼬리 "(…)") · AILimitMainDeviceRule(고른 기기가 없으면 가장 최근)
//
// 문구: 맥의 '맥'·'아이폰' 자리를 데스크톱 새 문구 '컴퓨터'·'폰'으로 쓴다(W-9 #5 — 폰 쪽 '맥' 문구는 손대지 않는다).
package com.yehsung.aingcheck.desktop.pages.devices

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.yehsung.aingcheck.core.rules.ailimit.AILimitDevice
import com.yehsung.aingcheck.core.rules.ailimit.AILimitDeviceNameParts
import com.yehsung.aingcheck.core.rules.ailimit.AILimitDeviceRoster
import com.yehsung.aingcheck.core.rules.ailimit.AILimitMainDeviceRule
import com.yehsung.aingcheck.desktop.pages.ailimits.AiLimitsActions
import com.yehsung.aingcheck.desktop.pages.desktopsettings.CaptionLine
import com.yehsung.aingcheck.desktop.pages.desktopsettings.DesktopPageScaffold
import com.yehsung.aingcheck.desktop.pages.desktopsettings.MacSection
import com.yehsung.aingcheck.desktop.shellapi.FlyoutNavigator
import com.yehsung.aingcheck.desktop.shellapi.FlyoutPageHost
import com.yehsung.aingcheck.feature.desktop.ailimits.AILimitStore
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.launch

object DevicePickerText {
    const val TITLE = "폰·위젯에 보여줄 컴퓨터"
    const val DETAIL = "폰 위젯은 컴퓨터 한 대만 보여줘요. 컴퓨터 화면은 늘 그 컴퓨터 자신의 값이에요."
    const val SINGLE = "이 계정의 컴퓨터가 한 대뿐이라 고를 게 없어요."
}

/** 기기 한 줄. */
data class DevicePickerRow(val deviceID: String, val parts: AILimitDeviceNameParts, val selected: Boolean)

object DevicePickerModel {
    /** 줄 순서 = 스토어 순서(최근 순 — Roster.fold). 고른 표시 = MainDeviceRule(맥 effectiveMainDevice). */
    fun rows(devices: List<AILimitDevice>, mainDeviceID: String?): List<DevicePickerRow> {
        val names = AILimitDeviceRoster.displayNameParts(devices)
        val selected = AILimitMainDeviceRule.resolve(devices, mainDeviceID)?.deviceID
        return devices.map { DevicePickerRow(it.deviceID, names[it.deviceID] ?: AILimitDeviceNameParts(it.baseName, null), it.deviceID == selected) }
    }

    /** 맥 showsMainDevicePicker — 두 대 이상일 때만 고른다. 라우트·레일 칸 판정도 이것(W-9 #2). */
    fun showsPicker(devices: List<AILimitDevice>): Boolean = devices.size >= 2
}

private val gaugeGradient = Brush.horizontalGradient(listOf(Color(0xFF5B8DEF), Color(0xFF8A76E0)))

/** 맥 devicePicker(:300-345). 누르면 먼저 화면, 다음 서버(실패하면 되돌린다 — DesktopAILimitSync.setAILimitMainDevice). */
@Composable
fun DevicePickerList(store: AILimitStore, actions: AiLimitsActions) {
    val state by store.state.collectAsState()
    val scope = rememberCoroutineScope()
    val colors = AingTheme.colors
    Column(verticalArrangement = Arrangement.spacedBy(6.dp)) {
        for (row in DevicePickerModel.rows(state.devices, state.mainDeviceID)) {
            val shape = RoundedCornerShape(8.dp)
            val bg = if (row.selected) Modifier.background(gaugeGradient, shape) else Modifier.background(colors.fill, shape).border(1.dp, colors.separator, shape)
            val ink = if (row.selected) Color.White else colors.label
            Row(
                Modifier.fillMaxWidth().height(26.dp).then(bg)
                    .clickable(role = Role.Button) { scope.launch { actions.setMainDevice(row.deviceID) } }
                    .padding(horizontal = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                // 이름은 잘려도 꼬리는 안 잘린다(맥 fixedSize + layoutPriority) — 이름 묶음이 남은 폭을 다 갖고 ✓ 는 오른쪽 끝.
                Row(Modifier.weight(1f), horizontalArrangement = Arrangement.spacedBy(6.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text(row.parts.base, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = ink, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f, fill = false))
                    row.parts.tail?.let { Text(AILimitDeviceNameParts.tailText(it), fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = ink, maxLines = 1) }
                }
                Box(Modifier.width(12.dp).alpha(if (row.selected) 1f else 0f)) { AingIcon(AppIcon.Check, contentDescription = null, size = 12.dp, tint = ink) }
            }
        }
    }
}

/** 제목·설명 + 목록(맥 AILimitMainDeviceSettingsRow). */
@Composable
fun DevicePickerSection(store: AILimitStore, actions: AiLimitsActions) {
    val colors = AingTheme.colors
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Column(verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(DevicePickerText.TITLE, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = colors.label)
            CaptionLine(DevicePickerText.DETAIL)
        }
        DevicePickerList(store, actions)
    }
}

class DevicesFlyoutPage(private val store: AILimitStore, private val actions: AiLimitsActions) : FlyoutPageHost {
    @Composable
    override fun Content(nav: FlyoutNavigator, widthDip: Double) {
        DevicesPageContent(store, actions, onBack = { nav.back() }, modifier = Modifier.width(widthDip.dp).fillMaxHeight())
    }
}

@Composable
fun DevicesPageContent(store: AILimitStore, actions: AiLimitsActions, onBack: () -> Unit, modifier: Modifier = Modifier) {
    val state by store.state.collectAsState()
    // 맥 .task { loadAILimitDevicesIfNeeded() } — 열 때 한 번(간격은 스토어 devicesAreDue 가 정한다).
    LaunchedEffect(Unit) { actions.loadDevices() }
    DesktopPageScaffold(title = "기기 고르기", onBack = onBack, modifier = modifier) {
        MacSection("AI 리밋") {
            if (DevicePickerModel.showsPicker(state.devices)) {
                DevicePickerSection(store, actions)
            } else {
                Text(DevicePickerText.TITLE, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = AingTheme.colors.label, modifier = Modifier.padding(bottom = 2.dp))
                CaptionLine(DevicePickerText.SINGLE)
            }
        }
    }
}
