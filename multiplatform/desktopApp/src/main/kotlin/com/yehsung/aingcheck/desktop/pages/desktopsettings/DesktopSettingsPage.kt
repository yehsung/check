// 원본: Sources/check/CheckSettingsView.swift:1515-1655(설정 본문 — '일반' 절 행 순서: 로그인 시 자동 실행 · 자동 근무 시작 · 단축키 묶음(간격 8) ·
//       캐릭터를 눌러 할 일 열기 · …, 'AI 리밋' 절은 맨 아래이고 연동 도구가 없으면 절 자체가 없다) · :1016-1132(단축키 기록 행) ·
//       :1572-1580(앱스토어 판 AI 기록 읽기 동의 행) · CheckSettingsWindow.swift(창 — Windows 는 플라이아웃 페이지)
//
// 맥과 다른 곳: 동의 행은 맥 '내 정보' 절 안이지만, 내 정보는 공용 설정(FlyoutRoute.Settings) 몫이라 여기선 'AI 사용 기록' 절로 둔다.
// 아이폰 QR·소속 센터·별명 등 계정 행은 공용 설정에 있다. 오버레이 켜기/끄기는 맥처럼 설정 창이 아니라 쓰던 자리(홈)에 둔다 — 저장소 흐름만 낸다.
package com.yehsung.aingcheck.desktop.pages.desktopsettings

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.isAltPressed
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.isCtrlPressed
import androidx.compose.ui.input.key.isMetaPressed
import androidx.compose.ui.input.key.isShiftPressed
import androidx.compose.ui.input.key.nativeKeyCode
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.yehsung.aingcheck.desktop.pages.ailimits.AiLimitVisibilityRows
import com.yehsung.aingcheck.desktop.pages.ailimits.AiLimitsActions
import com.yehsung.aingcheck.desktop.pages.aitokens.AiToolConsentText
import com.yehsung.aingcheck.desktop.pages.devices.DevicePickerModel
import com.yehsung.aingcheck.desktop.pages.devices.DevicePickerSection
import com.yehsung.aingcheck.desktop.platform.windows.hotkey.HotkeyPolicy
import com.yehsung.aingcheck.desktop.shellapi.FlyoutNavigator
import com.yehsung.aingcheck.core.session.app.AppLinks
import com.yehsung.aingcheck.desktop.pages.ailimits.LinkLine
import com.yehsung.aingcheck.desktop.shellapi.FlyoutPageHost
import com.yehsung.aingcheck.feature.desktop.ailimits.AILimitStore
import com.yehsung.aingcheck.ui.screens.settingscommon.ToggleRow
import com.yehsung.aingcheck.ui.theme.AingTheme

/** 행 글자(맥 :1520-1548 — '맥에 로그인하면 메뉴바에' · '메뉴바를 열지 않아도' 두 자리만 Windows 말로). */
object DesktopSettingsText {
    const val TITLE = "PC 설정"
    const val SECTION_GENERAL = "일반"
    const val SECTION_AI_DATA = "AI 사용 기록"
    const val SECTION_AI_LIMITS = "AI 리밋"
    const val LAUNCH_TITLE = "로그인 시 자동 실행"
    const val LAUNCH_DETAIL = "Windows 에 로그인하면 작업 표시줄 알림 영역에 자동으로 올라와요."
    const val AUTO_START_TITLE = "자동 근무 시작"
    const val AUTO_START_DETAIL = "PC를 5분쯤 쓰면 알아서 근무를 시작해요. 끄면 직접 눌러야 해요."
    const val SHORTCUT_TITLE = "근무 시작·종료 단축키"
    const val SHORTCUT_DETAIL = "알림 영역을 열지 않아도 이 키로 근무를 시작하거나 끝내요."
    const val TODO_TITLE = "캐릭터를 눌러 할 일 열기"
    const val TODO_DETAIL = "켜면 캐릭터 클릭이 할 일 보드를 열고, 끄면 캐릭터가 콕 반응만 해요."
    const val KEYCAP_RECORDING = "새 조합을 누르세요"
    const val RESET = "기본값으로"
    /** W-12 막힘(11.12 · 10.5.1) · W-13 #10: 설정에서 이용약관·개인정보 처리방침에 닿는다. */
    const val SECTION_LEGAL = "약관·정책"
    const val TERMS = "이용약관"
    const val PRIVACY = "개인정보 처리방침"
}

class DesktopSettingsDeps(
    val settings: DesktopSettingsStore,
    /** null 이면 AI 리밋 절이 없다(조립 전·시험). */
    val aiLimits: AILimitStore?,
    val aiLimitActions: AiLimitsActions?,
    /** 동의를 막 켰다(조립: 토큰 스캔 refreshNow). */
    val onConsentGranted: suspend () -> Unit = {},
    /** 링크 열기(조립: SharedPagesDeps.openUrl 과 같은 Desktop.browse). */
    val openUrl: (String) -> Unit = {},
)

class DesktopSettingsFlyoutPage(private val deps: DesktopSettingsDeps) : FlyoutPageHost {
    @Composable
    override fun Content(nav: FlyoutNavigator, widthDip: Double) {
        DesktopSettingsPageContent(deps, onBack = { nav.back() }, modifier = Modifier.width(widthDip.dp).fillMaxHeight())
    }
}

@Composable
fun DesktopSettingsPageContent(deps: DesktopSettingsDeps, onBack: () -> Unit, modifier: Modifier = Modifier) {
    val s = deps.settings
    val launch by s.launchAtLogin.collectAsState()
    val autoStart by s.autoWorkStart.collectAsState()
    val hotkey by s.hotkey.collectAsState()
    val todo by s.todoBoard.collectAsState()
    val consent by s.tokenUsageCollect.collectAsState()
    var grantTick by remember { mutableStateOf(0) }
    LaunchedEffect(grantTick) { if (grantTick > 0) deps.onConsentGranted() }
    DesktopPageScaffold(title = DesktopSettingsText.TITLE, onBack = onBack, modifier = modifier) {
        MacSection(DesktopSettingsText.SECTION_GENERAL) {
            ToggleRow(DesktopSettingsText.LAUNCH_TITLE, DesktopSettingsText.LAUNCH_DETAIL, launch, true, s::setLaunchAtLogin)
            PanelDivider()
            ToggleRow(DesktopSettingsText.AUTO_START_TITLE, DesktopSettingsText.AUTO_START_DETAIL, autoStart, true, s::setAutoWorkStart)
            PanelDivider()
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                ToggleRow(DesktopSettingsText.SHORTCUT_TITLE, DesktopSettingsText.SHORTCUT_DETAIL, hotkey.enabled, true, s::setHotkeyEnabled)
                HotkeyRecorderRow(s)
            }
            PanelDivider()
            ToggleRow(DesktopSettingsText.TODO_TITLE, DesktopSettingsText.TODO_DETAIL, todo.enabled, true, s::setTodoEnabled)
        }
        MacSection(DesktopSettingsText.SECTION_AI_DATA) {
            ToggleRow(AiToolConsentText.TITLE, AiToolConsentText.DETAIL, consent, true, onCheckedChange = { on ->
                s.setTokenUsageCollect(on)
                if (on) grantTick += 1
            })
        }
        MacSection(DesktopSettingsText.SECTION_LEGAL) {
            LinkLine(DesktopSettingsText.TERMS) { deps.openUrl(AppLinks.termsOfService) }
            LinkLine(DesktopSettingsText.PRIVACY) { deps.openUrl(AppLinks.privacyPolicy) }
        }
        val limits = deps.aiLimits
        val actions = deps.aiLimitActions
        if (limits != null && actions != null) {
            val state by limits.state.collectAsState()
            // ★ 연동 도구가 없으면 절 자체가 없다(맥 :1630-1636) — 맨 아래라 생기고 사라져도 위 행이 안 움직인다.
            if (limits.configurableProviders.isNotEmpty()) {
                LaunchedEffect(Unit) { actions.loadDevices() }
                MacSection(DesktopSettingsText.SECTION_AI_LIMITS) {
                    AiLimitVisibilityRows(limits, actions)
                    if (DevicePickerModel.showsPicker(state.devices)) {
                        PanelDivider()
                        DevicePickerSection(limits, actions)
                    }
                }
            }
        }
    }
}

/** 맥 WorkShortcutRecorderRow — 키캡(기록 중엔 강조 테두리 + "새 조합을 누르세요") · [기본값으로](기본이 아닐 때만) · 안내 한 줄. */
@Composable
fun HotkeyRecorderRow(settings: DesktopSettingsStore) {
    val colors = AingTheme.colors
    val hotkey by settings.hotkey.collectAsState()
    val recording by settings.hotkeyRecording.collectAsState()
    val status by settings.hotkeyStatus.collectAsState()
    val recorder = remember(settings) { HotkeyRecorder(settings) }
    var rejection by remember { mutableStateOf<HotkeyPolicy.Rejection?>(null) }
    val focus = remember { FocusRequester() }
    // 페이지를 떠나면 기록을 끝낸다(등록이 내려간 채로 남지 않게).
    DisposableEffect(recorder) { onDispose { recorder.stop() } }
    LaunchedEffect(recording) { if (recording) runCatching { focus.requestFocus() } else rejection = null }
    val notice = HotkeyNotice.resolve(recording, rejection, status, hotkey.enabled)
    Column(Modifier.alpha(if (hotkey.enabled) 1f else 0.4f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            val shape = RoundedCornerShape(7.dp)
            val label = if (recording) DesktopSettingsText.KEYCAP_RECORDING else WindowsKeyNames.display(hotkey.chord)
            Text(
                label,
                fontSize = 14.sp,
                fontWeight = FontWeight.SemiBold,
                color = if (recording) colors.accent else colors.label,
                maxLines = 1,
                modifier = Modifier
                    .height(28.dp)
                    .widthIn(min = 92.dp)
                    .background(colors.fill, shape)
                    .border(if (recording) 1.5.dp else 1.dp, if (recording) colors.accent else colors.separator, shape)
                    .focusRequester(focus)
                    .focusable()
                    .onPreviewKeyEvent { e ->
                        if (!recording || e.type != KeyEventType.KeyDown) return@onPreviewKeyEvent false
                        val r = recorder.onKey(AwtToWindowsVk.map(e.key.nativeKeyCode), e.isCtrlPressed, e.isAltPressed, e.isShiftPressed, e.isMetaPressed)
                        rejection = (r as? HotkeyKeyResult.Rejected)?.reason
                        r != HotkeyKeyResult.Ignored
                    }
                    .clickable(enabled = hotkey.enabled, role = Role.Button) { if (recording) recorder.stop() else recorder.start() }
                    .semantics { contentDescription = if (recording) DesktopSettingsText.KEYCAP_RECORDING else WindowsKeyNames.spoken(hotkey.chord) }
                    .padding(horizontal = 12.dp, vertical = 5.dp),
            )
            if (hotkey.chord != HotkeyPolicy.DEFAULT) {
                Text(
                    DesktopSettingsText.RESET, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = colors.label,
                    modifier = Modifier.height(26.dp).background(colors.fill, RoundedCornerShape(7.dp))
                        .clickable(enabled = hotkey.enabled, role = Role.Button) { recorder.stop(); settings.resetHotkey() }
                        .padding(horizontal = 12.dp, vertical = 5.dp),
                )
            }
        }
        if (notice != null) {
            Text(
                notice.text, fontSize = 11.sp,
                color = when (notice.tone) {
                    HotkeyNotice.Tone.HINT -> colors.label2
                    HotkeyNotice.Tone.RETRY -> colors.pending
                    HotkeyNotice.Tone.DANGER -> colors.danger
                },
            )
        }
    }
}
