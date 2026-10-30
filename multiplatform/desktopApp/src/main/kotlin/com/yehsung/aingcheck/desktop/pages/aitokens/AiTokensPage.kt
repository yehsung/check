// 원본: Sources/check/CheckTokenUsageRow.swift(얇은 줄 — ✦ + "N월 AI 토큰 소모량" + 콤마 숫자, 강조 테두리 · 스캔 중 0.55 ·
//       숫자 없으면 [AI 토큰 순위] 입구 줄) · Sources/CheckCore/CheckTokenRowDisplay.swift:118-146(서버 내 행 > 로컬, 로컬 게이트 셋) ·
//       Sources/check/CheckSettingsView.swift:1739-1742(AIToolConsentSettingsText) · WorkTimerStoreMacEdition.swift:54-64(동의 = 읽기·올리기의 유일한 문)
//
// 동의 전(tokenUsageCollect 거짓)에는 숫자를 그리지 않고 동의 카드만 — 이 페이지는 스캔을 직접 부르지 않는다(스캔 문은 TokenUsageStore 의
// isScanPermitted). 숫자 표기는 core TokenNumberFormatter.grouped. 툴팁 글자(갈래별 내역)는 페이지라 줄 아래에 펼친다.
package com.yehsung.aingcheck.desktop.pages.aitokens

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.yehsung.aingcheck.core.rules.format.TokenNumberFormatter
import com.yehsung.aingcheck.core.rules.token.TokenRowDisplay
import com.yehsung.aingcheck.core.rules.token.TokenRowDisplayRule
import com.yehsung.aingcheck.core.rules.token.TokenRowServerValue
import com.yehsung.aingcheck.desktop.pages.desktopsettings.CaptionLine
import com.yehsung.aingcheck.desktop.pages.desktopsettings.DesktopPageScaffold
import com.yehsung.aingcheck.desktop.pages.desktopsettings.DesktopSettingsStore
import com.yehsung.aingcheck.desktop.pages.desktopsettings.MacPanel
import com.yehsung.aingcheck.desktop.pages.desktopsettings.MacSection
import com.yehsung.aingcheck.desktop.shellapi.FlyoutNavigator
import com.yehsung.aingcheck.desktop.shellapi.FlyoutPageHost
import com.yehsung.aingcheck.desktop.shellapi.FlyoutRoute
import com.yehsung.aingcheck.feature.desktop.tokens.TokenUsageMonthly
import com.yehsung.aingcheck.feature.desktop.tokens.account.CodexAccountUsage
import com.yehsung.aingcheck.feature.desktop.tokens.account.detailTooltip
import com.yehsung.aingcheck.feature.desktop.tokens.account.displayTotal
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

/** 맥 AIToolConsentSettingsText(:1739-1742) — '이 맥의' 자리만 '이 PC의'(W-13 #8 · 데스크톱 자기 호칭 'PC'). */
object AiToolConsentText {
    const val TITLE = "AI 사용 기록 읽기"
    const val DETAIL = "이 PC의 AI 코딩 도구 기록에서 토큰 숫자만 세어 순위에 올려요. 끄면 읽지도 올리지도 않아요."
    const val ALLOW = "허용"
    const val LATER = "PC 설정에서 언제든 바꿀 수 있어요."
}

/** 페이지가 그릴 것 한 가지. */
sealed interface AiTokensView {
    data object NeedsConsent : AiTokensView
    data class Usage(val display: TokenRowDisplay) : AiTokensView {
        val numberText: String get() = TokenNumberFormatter.grouped(display.total)
        val titleText: String get() = "${display.monthNumber}월 AI 토큰 소모량"
        val breakdown: List<String> get() = display.tooltip.lines().filter { it.isNotBlank() }
    }
    /** 숫자가 없다 — 순위 입구 줄만(맥 boardEntryRow). */
    data object BoardOnly : AiTokensView
}

object AiTokensModel {
    /** 맥 TokenRowDisplayRule.resolve 의 로컬 갈래(Swift :133-145) — 로컬 총합·계정 월합·안티그래비티 중 하나라도 있으면. */
    fun resolveLocal(local: TokenUsageMonthly?, account: CodexAccountUsage?): TokenRowDisplay? {
        if (local == null) return null
        if (!(local.total > 0 || (account?.monthTotal(local.month) ?: 0) > 0 || local.antigravityTotal > 0)) return null
        val monthNumber = local.month.substringAfterLast('-').toIntOrNull() ?: 0
        return TokenRowDisplay(local.displayTotal(account), local.detailTooltip(account), monthNumber, false)
    }

    /** 동의 > 서버 내 행 > 로컬 > 순위 입구. */
    fun resolve(
        consent: Boolean,
        local: TokenUsageMonthly?,
        account: CodexAccountUsage?,
        server: TokenRowServerValue?,
        userID: String?,
        currentMonth: String,
    ): AiTokensView {
        if (!consent) return AiTokensView.NeedsConsent
        val shown = TokenRowDisplayRule.resolveServer(server, userID, currentMonth) ?: resolveLocal(local, account)
        return if (shown != null) AiTokensView.Usage(shown) else AiTokensView.BoardOnly
    }
}

/** 페이지 재료(조립: TokensWiring 의 scan·account·upload + 세션 + 설정). */
class AiTokensPageDeps(
    val settings: DesktopSettingsStore,
    val usage: StateFlow<TokenUsageMonthly?>,
    val scanning: StateFlow<Boolean>,
    val account: () -> CodexAccountUsage?,
    val serverRow: () -> TokenRowServerValue?,
    val userID: () -> String?,
    val currentMonth: () -> String,
    /** 동의를 막 켰다 — 조립은 `tokens.scan.refreshNow()`(스캔 문은 같은 동의를 다시 본다). */
    val onConsentGranted: suspend () -> Unit,
)

class AiTokensFlyoutPage(private val deps: AiTokensPageDeps) : FlyoutPageHost {
    @Composable
    override fun Content(nav: FlyoutNavigator, widthDip: Double) {
        AiTokensPageContent(
            deps, onBack = { nav.back() }, onOpenBoard = { nav.navigate(FlyoutRoute.Rankings(TOKENS_BOARD)) },
            modifier = Modifier.width(widthDip.dp).fillMaxHeight(),
        )
    }

    companion object {
        /** RankingsBoard.tokens.raw. */
        const val TOKENS_BOARD = "tokens"
    }
}

@Composable
fun AiTokensPageContent(deps: AiTokensPageDeps, onBack: () -> Unit, onOpenBoard: () -> Unit, modifier: Modifier = Modifier) {
    val consent by deps.settings.tokenUsageCollect.collectAsState()
    val usage by deps.usage.collectAsState()
    val scanning by deps.scanning.collectAsState()
    val scope = rememberCoroutineScope()
    val view = AiTokensModel.resolve(consent, usage, deps.account(), deps.serverRow(), deps.userID(), deps.currentMonth())
    DesktopPageScaffold(title = "AI 토큰", onBack = onBack, modifier = modifier) {
        when (view) {
            AiTokensView.NeedsConsent -> MacSection("AI 토큰") {
                Text(AiToolConsentText.TITLE, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = AingTheme.colors.label)
                CaptionLine(AiToolConsentText.DETAIL)
                Button(
                    onClick = {
                        deps.settings.setTokenUsageCollect(true)
                        scope.launch { deps.onConsentGranted() }
                    },
                    modifier = Modifier.heightIn(min = 36.dp),
                ) { Text(AiToolConsentText.ALLOW) }
                CaptionLine(AiToolConsentText.LATER)
            }
            is AiTokensView.Usage -> {
                UsageRow(view, scanning, onOpenBoard)
                if (view.breakdown.isNotEmpty()) {
                    MacSection("자세히") { for (line in view.breakdown) CaptionLine(line) }
                }
            }
            AiTokensView.BoardOnly -> BoardEntryRow(onOpenBoard)
        }
    }
}

/** 맥 slimRow — 강조 테두리 0.45 · 스캔 중 0.55. */
@Composable
private fun UsageRow(view: AiTokensView.Usage, scanning: Boolean, onOpenBoard: () -> Unit) {
    val colors = AingTheme.colors
    val shape = RoundedCornerShape(12.dp)
    Row(
        Modifier.fillMaxWidth().alpha(if (scanning) 0.55f else 1f)
            .background(colors.surface, shape).border(1.dp, colors.accent.copy(alpha = 0.45f), shape)
            .padding(horizontal = 12.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        AingIcon(AppIcon.AutoAwesome, contentDescription = null, size = 12.dp, tint = colors.label2)
        Text(view.titleText, fontSize = 11.sp, color = colors.label2, maxLines = 1)
        Spacer(Modifier.weight(1f))
        Text(view.numberText, fontSize = 12.sp, fontWeight = FontWeight.Bold, color = colors.label, maxLines = 1)
        BoardButton(onOpenBoard)
    }
}

/** 맥 boardEntryRow. */
@Composable
private fun BoardEntryRow(onOpenBoard: () -> Unit) {
    val colors = AingTheme.colors
    MacPanel(Modifier.fillMaxWidth()) {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            AingIcon(AppIcon.AutoAwesome, contentDescription = null, size = 12.dp, tint = colors.label2)
            Text("AI 토큰 순위", fontSize = 11.sp, color = colors.label2, maxLines = 1)
            Spacer(Modifier.weight(1f))
            BoardButton(onOpenBoard)
        }
    }
    CaptionLine("앱 사용자 전체의 AI 토큰 순위를 봅니다", Modifier.padding(start = 2.dp))
}

@Composable
private fun BoardButton(onOpenBoard: () -> Unit) {
    Column(Modifier.clickable(role = Role.Button, onClick = onOpenBoard).padding(4.dp)) {
        AingIcon(AppIcon.Group, contentDescription = "AI 토큰 순위", size = 16.dp, tint = AingTheme.colors.label2)
    }
}
