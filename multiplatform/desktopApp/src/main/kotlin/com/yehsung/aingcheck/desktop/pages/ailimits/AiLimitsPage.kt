// 원본: Sources/check/CheckAILimitsRow.swift:49-79(색 — 5시간 파랑 · 주간 보라) · :113-124(70/90 % 경고색) · :206-289(폭·높이 예산) ·
//       :291-412(카드 모델 · 툴팁 · 리셋 글자 "a h:mm 리셋") · :414-533(카드 — 머리 줄 "AI 리밋" + 5시간/주간 머리 · 제공자 줄) ·
//       :535-588(제공자 줄 — 알림만 있으면 그 한 줄) · CheckSettingsView.swift:187-260(표시 설정 — 마스터 + 제공자 스위치)
//
// Windows 는 호버 툴팁 대신 카드 아래에 툴팁 글자(제공자별 · 리셋 시각)를 그대로 늘어놓는다(페이지라 자리가 있다).
// 밝은 화면의 바·구분선 바탕만 테마 색을 쓴다 — 맥 고정 색(#30343B 등)은 어두운 판 전용이다.
package com.yehsung.aingcheck.desktop.pages.ailimits

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.yehsung.aingcheck.core.rules.ailimit.AILimitDisplay
import com.yehsung.aingcheck.core.rules.ailimit.AILimitFreshness
import com.yehsung.aingcheck.core.rules.ailimit.AILimitFreshnessRule
import com.yehsung.aingcheck.core.rules.ailimit.AILimitProvider
import com.yehsung.aingcheck.core.rules.ailimit.AILimitWindow
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.desktop.pages.desktopsettings.CaptionLine
import com.yehsung.aingcheck.desktop.pages.desktopsettings.DesktopPageScaffold
import com.yehsung.aingcheck.desktop.pages.desktopsettings.MacPanel
import com.yehsung.aingcheck.desktop.pages.desktopsettings.MacSection
import com.yehsung.aingcheck.desktop.shellapi.FlyoutNavigator
import com.yehsung.aingcheck.desktop.shellapi.FlyoutPageHost
import com.yehsung.aingcheck.desktop.shellapi.FlyoutRoute
import com.yehsung.aingcheck.feature.desktop.ailimits.AILimitStore
import com.yehsung.aingcheck.feature.desktop.ailimits.DesktopAILimitSync
import com.yehsung.aingcheck.ui.screens.settingscommon.ToggleRow
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Locale

/** 페이지가 쓰는 문(시험은 가짜로). 조립은 [DesktopAILimitSync.asActions]. */
interface AiLimitsActions {
    suspend fun setVisible(enabled: Boolean)
    suspend fun setProviderEnabled(provider: AILimitProvider, enabled: Boolean)
    suspend fun loadDevices(force: Boolean = false)
    suspend fun setMainDevice(deviceID: String)
}

fun DesktopAILimitSync.asActions(clock: () -> SwiftDate): AiLimitsActions = object : AiLimitsActions {
    override suspend fun setVisible(enabled: Boolean) = setAILimitsVisible(enabled)
    override suspend fun setProviderEnabled(provider: AILimitProvider, enabled: Boolean) = setAILimitProviderEnabled(provider, enabled)
    override suspend fun loadDevices(force: Boolean) = loadAILimitDevicesIfNeeded(clock(), force)
    override suspend fun setMainDevice(deviceID: String) = setAILimitMainDevice(deviceID)
}

/** 맥 AILimitUsageTint(:113-124) — 정수 % 로 가른다(반올림 경계는 core wholePercent). */
enum class AiLimitTint {
    NORMAL, WARN, DANGER, NONE;

    companion object {
        const val WARN_PERCENT = 70
        const val DANGER_PERCENT = 90

        fun of(percent: Double?): AiLimitTint {
            if (percent == null) return NONE
            val whole = AILimitFreshnessRule.wholePercent(percent)
            return when {
                whole >= DANGER_PERCENT -> DANGER
                whole >= WARN_PERCENT -> WARN
                else -> NORMAL
            }
        }
    }
}

/** 리셋 시각 글자(맥 AILimitResetTimeText — ko_KR "a h:mm"). */
object AiLimitResetTimeText {
    private val formatter: DateTimeFormatter = DateTimeFormatter.ofPattern("a h:mm", Locale.KOREAN)

    fun text(epochSeconds: Double, zone: ZoneId): String =
        formatter.format(Instant.ofEpochMilli((epochSeconds * 1000).toLong()).atZone(zone))
}

/** 제공자 한 줄(맥 AILimitCardModel). */
data class AiLimitCardModel(
    val provider: AILimitProvider,
    val windows: List<AILimitDisplay>,
    val notice: String?,
    val planLabel: String?,
    val resetTexts: Map<AILimitWindow, String>,
) {
    fun display(window: AILimitWindow): AILimitDisplay? = windows.firstOrNull { it.window == window }
    val saysNothingButNotice: Boolean get() = windows.isEmpty() && notice != null

    /** 맥 tooltipText(:330-350) — 줄 단위. */
    val tooltipLines: List<String>
        get() {
            val lines = mutableListOf(listOfNotNull(provider.displayName, planLabel).joinToString(" "))
            for (window in AILimitWindow.entries.sortedBy { it.sortOrder }) {
                val d = display(window)
                if (d != null) {
                    val parts = mutableListOf("${window.displayName} ${d.valueText}", d.captionText)
                    resetTexts[window]?.let { parts += it }
                    lines += parts.joinToString(" · ")
                } else if (windows.isNotEmpty()) {
                    lines += "${window.displayName} $ABSENT_VALUE_TEXT"
                }
            }
            if (windows.isEmpty()) lines += unknownCaption
            notice?.let { lines += it }
            return lines
        }

    companion object {
        const val ABSENT_VALUE_TEXT = "없음"
        val unknownCaption: String get() = AILimitFreshnessRule.captionText(AILimitFreshness.unknown, 0.0, 0.0)

        fun all(store: AILimitStore, now: SwiftDate, zone: ZoneId): List<AiLimitCardModel> =
            store.listedProviders.map { make(store, it, now, zone) }

        fun make(store: AILimitStore, provider: AILimitProvider, now: SwiftDate, zone: ZoneId): AiLimitCardModel {
            val windows = AILimitWindow.entries.sortedBy { it.sortOrder }.map { store.display(provider, it, now) }.filter { it.isVisible }
            val resets = buildMap {
                for (d in windows) {
                    val w = d.window ?: continue
                    resetText(d, now, zone)?.let { put(w, it) }
                }
            }
            return AiLimitCardModel(provider, windows, store.noticeText(provider), store.bundle?.provider(provider)?.planLabel, resets)
        }

        /** 리셋 주장(초기화됨)이 아니고 미래일 때만(맥 :399-404). */
        fun resetText(display: AILimitDisplay, now: SwiftDate, zone: ZoneId): String? {
            if (display.freshness.isResetClaim) return null
            val at = display.resetsAt ?: return null
            if (at <= now.timeIntervalSince1970) return null
            return "${AiLimitResetTimeText.text(at, zone)} 리셋"
        }
    }
}

/** 라우트·레일 칸 판정(W-9 #2): 리밋이 보일 때만 AI 리밋 칸을 연다(맥: isAvailable 이 아니면 카드 자체가 없다). */
object AiLimitsRouteRule {
    fun showsRoute(store: AILimitStore): Boolean = store.isAvailable
}

/**
 * 맥 고정 색(#5B8DEF 파랑 · #8A76E0 보라 · 바탕 #30343B)은 앱 셸 색 리터럴 금지(DesignRules D5 · G §8-15) 때문에 테마 색으로 옮긴다:
 * 5시간 = accent(파랑) · 주간 = aiToken(보라) · 바탕 = fill · 구분선 = separator · 값 없음 = label3.
 */
private object AiLimitPalette {
    @Composable
    fun bar(window: AILimitWindow): Color = if (window == AILimitWindow.fiveHour) AingTheme.colors.accent else AingTheme.colors.aiToken

    @Composable
    fun header(window: AILimitWindow): Color = bar(window).copy(alpha = 0.85f)
}

private const val VALUE_WIDTH = 52
private const val MARK_SIDE = 20

/** 맥 CheckAILimitsCard — 머리 줄 + 제공자 줄(구분선 1). */
@Composable
fun AiLimitsCard(models: List<AiLimitCardModel>, modifier: Modifier = Modifier) {
    val colors = AingTheme.colors
    val separator = colors.separator
    MacPanel(modifier.fillMaxWidth()) {
        Column(Modifier.padding(vertical = 10.dp)) {
            Box(Modifier.fillMaxWidth().padding(horizontal = 12.dp).height(14.dp)) {
                // 머리 글자는 값 칸 오른쪽 끝에 맞춘다(맥 headerCellGap = 바 + 6 + 10) — 제공자 줄과 같은 칸 나눔을 쓴다.
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Spacer(Modifier.width((MARK_SIDE + 8).dp))
                    for ((i, window) in listOf(AILimitWindow.fiveHour, AILimitWindow.weekly).withIndex()) {
                        if (i > 0) Spacer(Modifier.width(10.dp))
                        Box(Modifier.weight(1f), contentAlignment = Alignment.CenterEnd) {
                            Text(window.displayName, fontSize = 10.sp, lineHeight = 12.sp, fontWeight = FontWeight.SemiBold, color = AiLimitPalette.header(window), maxLines = 1)
                        }
                    }
                }
                Text("AI 리밋", fontSize = 11.sp, lineHeight = 13.sp, color = colors.label2, maxLines = 1, modifier = Modifier.align(Alignment.CenterStart))
            }
            Spacer(Modifier.height(7.dp))
            for ((index, model) in models.withIndex()) {
                if (index > 0) Box(Modifier.fillMaxWidth().height(1.dp).background(separator))
                AiLimitProviderRow(model, Modifier.padding(horizontal = 12.dp))
            }
        }
    }
}

@Composable
private fun AiLimitProviderRow(model: AiLimitCardModel, modifier: Modifier = Modifier) {
    val colors = AingTheme.colors
    Row(modifier.fillMaxWidth().height(24.dp), verticalAlignment = Alignment.CenterVertically) {
        ProviderMark(model.provider)
        Spacer(Modifier.width(8.dp))
        val notice = model.notice
        if (model.saysNothingButNotice && notice != null) {
            Text(notice, fontSize = 11.sp, color = colors.pending, maxLines = 1, overflow = TextOverflow.Ellipsis, modifier = Modifier.weight(1f))
        } else {
            LimitCell(model.display(AILimitWindow.fiveHour), AILimitWindow.fiveHour, Modifier.weight(1f))
            Spacer(Modifier.width(10.dp))
            LimitCell(model.display(AILimitWindow.weekly), AILimitWindow.weekly, Modifier.weight(1f))
        }
    }
}

/** 맥 AIProviderTile 자리 — 로고 대신 이름 첫 글자 칩(상표 그림을 싣지 않는다). */
@Composable
private fun ProviderMark(provider: AILimitProvider) {
    val colors = AingTheme.colors
    val tint = when (provider) {
        AILimitProvider.claude -> colors.pending
        AILimitProvider.codex -> colors.working
        AILimitProvider.antigravity -> colors.accent
    }
    Box(Modifier.size(MARK_SIDE.dp).background(tint, RoundedCornerShape(5.dp)), contentAlignment = Alignment.Center) {
        Text(provider.displayName.take(1), fontSize = 11.sp, fontWeight = FontWeight.Bold, color = colors.onAccentFill, maxLines = 1)
    }
}

@Composable
private fun LimitCell(display: AILimitDisplay?, window: AILimitWindow, modifier: Modifier) {
    val colors = AingTheme.colors
    val track = if (display == null) colors.fill.copy(alpha = colors.fill.alpha * 0.5f) else colors.fill
    val valueColor = when (if (display == null) null else AiLimitTint.of(display.percent)) {
        null -> colors.label3
        AiLimitTint.DANGER -> colors.danger
        AiLimitTint.WARN -> colors.pending
        AiLimitTint.NONE -> colors.label2
        AiLimitTint.NORMAL -> colors.label
    }
    Row(modifier, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        BoxWithConstraints(Modifier.weight(1f).height(6.dp).background(track, CircleShape)) {
            val percent = display?.percent
            if (percent != null) {
                val clamped = percent.coerceIn(0.0, 100.0)
                if (clamped > 0) {
                    val w = (maxWidth * (clamped / 100).toFloat()).coerceAtLeast(6.dp).coerceAtMost(maxWidth)
                    Box(
                        Modifier.width(w).fillMaxHeight()
                            .background(AiLimitPalette.bar(window).copy(alpha = if (display.floorOnly) 0.55f else 1f), CircleShape),
                    )
                }
            }
        }
        Text(
            display?.valueText ?: AiLimitCardModel.ABSENT_VALUE_TEXT, fontSize = 12.sp, fontWeight = FontWeight.Bold, color = valueColor,
            textAlign = TextAlign.End, maxLines = 1, modifier = Modifier.width(VALUE_WIDTH.dp),
        )
    }
}

/** 맥 AILimitVisibilitySettingsRows(:187-260) — 마스터 + 제공자 스위치(마스터를 끄면 흐리게 잠긴다) + 안내 한 줄. */
@Composable
fun AiLimitVisibilityRows(store: AILimitStore, actions: AiLimitsActions) {
    val colors = AingTheme.colors
    val scope = rememberCoroutineScope()
    val state by store.state.collectAsState()
    val master = state.visibility.masterEnabled
    ToggleRow(
        title = "AI 사용량 리밋 보기",
        detail = "끄면 사용량을 읽지도 올리지도 않아요. 폰·위젯에서도 사라져요.",
        checked = master,
        enabled = true,
        onCheckedChange = { scope.launch { actions.setVisible(it) } },
    )
    Column(Modifier.padding(start = 16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        for (provider in store.configurableProviders) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(provider.displayName, fontSize = 14.sp, color = if (master) colors.label else colors.label3, modifier = Modifier.weight(1f))
                Switch(
                    checked = state.visibility.isProviderOn(provider),
                    onCheckedChange = if (master) { on -> scope.launch { actions.setProviderEnabled(provider, on) } } else null,
                    enabled = master,
                )
            }
        }
        CaptionLine("연동 안 된 도구는 여기 안 보여요.")
    }
}

/** AI 리밋 페이지. */
class AiLimitsFlyoutPage(
    private val store: AILimitStore,
    private val actions: AiLimitsActions,
    private val clock: () -> SwiftDate,
    private val zone: ZoneId = ZoneId.systemDefault(),
) : FlyoutPageHost {
    @Composable
    override fun Content(nav: FlyoutNavigator, widthDip: Double) {
        AiLimitsPageContent(store, clock, zone, onBack = { nav.back() }, onOpenDevices = { nav.navigate(FlyoutRoute.Devices) },
            onOpenSettings = { nav.navigate(FlyoutRoute.DesktopSettings) }, modifier = Modifier.width(widthDip.dp).fillMaxHeight())
    }
}

@Composable
fun AiLimitsPageContent(
    store: AILimitStore,
    clock: () -> SwiftDate,
    zone: ZoneId,
    onBack: () -> Unit,
    onOpenDevices: () -> Unit,
    onOpenSettings: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val state by store.state.collectAsState()
    val now = clock()
    DesktopPageScaffold(title = "AI 리밋", onBack = onBack, modifier = modifier) {
        if (!store.isAvailable) {
            MacSection("AI 리밋") {
                CaptionLine(if (!state.visibility.masterEnabled) "AI 사용량 리밋 보기가 꺼져 있어요." else "연동된 AI 도구가 없어요. 클로드 코드나 코덱스를 한 번 실행해 주세요.")
                LinkLine("PC 설정 열기", onOpenSettings)
            }
            return@DesktopPageScaffold
        }
        val models = AiLimitCardModel.all(store, now, zone)
        AiLimitsCard(models)
        MacSection("자세히") {
            CaptionLine(store.summary(now).captionText)
            for (model in models) {
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    for ((i, line) in model.tooltipLines.withIndex()) {
                        if (i == 0) Text(line, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = AingTheme.colors.label)
                        else CaptionLine(line)
                    }
                }
            }
        }
        if (store.showsMainDevicePicker) LinkLine("폰·위젯에 보여줄 컴퓨터 고르기", onOpenDevices)
        LinkLine("보일 도구 고르기 · PC 설정", onOpenSettings)
    }
}

@Composable
internal fun LinkLine(text: String, onClick: () -> Unit) {
    Text(
        text, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = AingTheme.colors.accent,
        modifier = Modifier.padding(start = 2.dp).clickable(onClick = onClick),
    )
}
