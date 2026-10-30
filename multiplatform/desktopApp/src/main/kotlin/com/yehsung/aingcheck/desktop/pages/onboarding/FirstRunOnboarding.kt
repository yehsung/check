// 원본: Sources/CheckCore/MacEdition.swift:176-185(AI 도구 기록 읽기 동의 — 키가 없으면 거절) · Sources/check/CheckApp.swift:757·856-861
//       (로그인 시 자동 실행 — 기본 켜짐, 사용자가 끈 사실만 남긴다) · 맥 AIToolConsentSettingsText(:1739-1742)
// 결정: W-13 #5(동의 — Store 10.5.2: 첫 실행 동의 화면 + 설정 스위치, 동의 전 토큰 스캔·AI 리밋 자격 파일 읽기·codex.exe 실행·업로드 0)
//       · W-13 #6(자동 실행 10.2.8: 첫 실행 화면에 "로그인할 때 켜기" 스위치, 기본 켬 = 맥) · W-12 막힘 ③(설명 문구)
//
// 첫 실행 화면 — 맥엔 없는 Windows 전용 화면(맥 Developer ID 판은 동의를 묻지 않고, MAS 판은 설정 행만). 순수 모델([FirstRunModel])이
// 결과를 DesktopSettingsStore(c4 — 그 키들의 유일한 쓰는 쪽)에 쓴다. 띄울 때 = 설정에 동의·자동 실행 값 중 하나라도 없을 때 한 번
// (DesktopSettingsStore.firstRunPending). [켜기]·[나중에] 어느 쪽이든 두 값을 함께 적고 다시 뜨지 않는다 — 바꾸기는 PC 설정에서.
package com.yehsung.aingcheck.desktop.pages.onboarding

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.desktop.pages.aitokens.AiToolConsentText
import com.yehsung.aingcheck.desktop.pages.desktopsettings.DesktopSettingsStore
import com.yehsung.aingcheck.desktop.pages.desktopsettings.MacSection
import com.yehsung.aingcheck.desktop.shellapi.FlyoutNavigator
import com.yehsung.aingcheck.desktop.shellapi.FlyoutPageHost
import com.yehsung.aingcheck.ui.screens.settingscommon.ToggleRow
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

object FirstRunText {
    const val TITLE = "아잉체크를 시작해요"
    const val SUBTITLE = "두 가지만 정하면 돼요. 나중에 PC 설정에서 언제든 바꿀 수 있어요."
    const val CONSENT_SECTION = AiToolConsentText.TITLE

    /**
     * W-12 막힘 ③ — 켜면 무엇을 하는지 빠짐없이(토큰 스캔 · AI 리밋 로그인 정보 파일 읽기 · codex 실행 · 숫자 업로드). 켜기 전엔 그 넷이 0 이다
     * (TokensWiring isScanPermitted · 업로드 게이트 — cb2fb82e).
     */
    const val CONSENT_BODY =
        "켜면 이 PC의 AI 코딩 도구(Claude Code·Codex) 기록에서 토큰 숫자만 세어 순위에 올리고, AI 리밋을 보여 주려고 " +
            "그 도구의 로그인 정보 파일을 읽고 codex 를 실행해요. 대화 내용은 올리지 않아요."
    const val CONSENT_OFF = "켜기 전에는 아무것도 읽지 않아요."
    const val LAUNCH_SECTION = "실행"
    const val LAUNCH_TITLE = "로그인할 때 켜기"
    const val LAUNCH_DETAIL = "Windows 에 로그인하면 작업 표시줄 알림 영역에 자동으로 올라와요."
    const val ALLOW = "켜기"
    const val LATER = "나중에"
}

/** 첫 실행이 정한 값(조립이 동의 뒤 스캔을 깨우는 데 쓴다). */
data class FirstRunResult(val consent: Boolean, val launchAtLogin: Boolean)

/** 순수 모델. 동의 기본 꺼짐([나중에] = 거절을 적는다), 자동 실행 기본 켬(W-13 #6). */
class FirstRunModel(private val settings: DesktopSettingsStore) {
    private val pendingState = MutableStateFlow(settings.firstRunPending())
    private val launchState = MutableStateFlow(DEFAULT_LAUNCH_AT_LOGIN)

    /** 띄울 때인가(끝내면 거짓 — 다시 뜨지 않는다). */
    val pending: StateFlow<Boolean> = pendingState.asStateFlow()
    val launchAtLogin: StateFlow<Boolean> = launchState.asStateFlow()

    fun setLaunchAtLogin(on: Boolean) {
        launchState.value = on
    }

    /** [켜기]([consent]=참) 또는 [나중에](거짓). 두 값을 설정에 함께 쓴다 — 한 번만(두 번째 누름은 무시). */
    fun finish(consent: Boolean): FirstRunResult? {
        if (!pendingState.value) return null
        settings.setTokenUsageCollect(consent)
        settings.setLaunchAtLogin(launchState.value)
        pendingState.value = false
        return FirstRunResult(consent, launchState.value)
    }

    companion object {
        const val DEFAULT_CONSENT = false
        const val DEFAULT_LAUNCH_AT_LOGIN = true
    }
}

object FirstRunTags {
    const val ALLOW = "firstRun.allow"
    const val LATER = "firstRun.later"
}

/**
 * 첫 실행 페이지(플라이아웃 전체 폭 — 레일 없음). 공용 호스트가 [pending] 동안 다른 페이지 대신 이것을 그린다(SharedPagesDeps.firstRun).
 * @param onFinished 고른 뒤(조립: 동의면 tokens.scan.refreshNow() — 스캔 문은 같은 동의를 다시 본다).
 */
class FirstRunOnboarding(settings: DesktopSettingsStore, private val onFinished: suspend (FirstRunResult) -> Unit = {}) : FlyoutPageHost {
    val model = FirstRunModel(settings)
    val pending: StateFlow<Boolean> get() = model.pending

    @Composable
    override fun Content(nav: FlyoutNavigator, widthDip: Double) {
        val scope = rememberCoroutineScope()
        FirstRunScreen(model, onChoose = { consent ->
            model.finish(consent)?.let { result -> scope.launch { onFinished(result) } }
        }, modifier = Modifier.width(widthDip.dp).fillMaxHeight())
    }
}

@Composable
fun FirstRunScreen(model: FirstRunModel, onChoose: (Boolean) -> Unit, modifier: Modifier = Modifier) {
    val colors = AingTheme.colors
    val launch by model.launchAtLogin.collectAsState()
    Column(modifier.background(colors.background).padding(16.dp), verticalArrangement = Arrangement.spacedBy(14.dp)) {
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(FirstRunText.TITLE, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, color = colors.label)
            Text(FirstRunText.SUBTITLE, style = MaterialTheme.typography.bodySmall, color = colors.label2)
        }
        Column(Modifier.weight(1f, fill = false).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(14.dp)) {
            MacSection(FirstRunText.CONSENT_SECTION) {
                Text(FirstRunText.CONSENT_BODY, style = MaterialTheme.typography.bodyMedium, color = colors.label)
                Text(FirstRunText.CONSENT_OFF, style = MaterialTheme.typography.bodySmall, color = colors.label2)
            }
            MacSection(FirstRunText.LAUNCH_SECTION) {
                ToggleRow(FirstRunText.LAUNCH_TITLE, FirstRunText.LAUNCH_DETAIL, launch, true, model::setLaunchAtLogin)
            }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            OutlinedButton(onClick = { onChoose(false) }, modifier = Modifier.weight(1f).testTag(FirstRunTags.LATER)) { Text(FirstRunText.LATER) }
            Button(onClick = { onChoose(true) }, modifier = Modifier.weight(1f).testTag(FirstRunTags.ALLOW)) { Text(FirstRunText.ALLOW) }
        }
    }
}
