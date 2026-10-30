// 원본: Sources/check/CheckFocusModeButton.swift 1-207(버튼·겉모습 표·문구) · CheckMenuView.swift 3275-3284(PokeFocusNotice) @ 35649bee
// W3-c3 집중 모드 단추. 판정·요청은 feature/desktop FocusModeController(W2-g4)가 하고, 이 파일은 값(FocusStageFace)을 그리기만 한다.
// 단계 표기·남은 시간은 FocusStagePolicy(TIMED_DURATION_SECONDS)에서만 파생한다 — 문구에 "3시간"을 베껴 두지 않는다.
package com.yehsung.aingcheck.desktop.pages.focus

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.TooltipArea
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.feature.desktop.focus.FocusModeController
import com.yehsung.aingcheck.feature.desktop.focus.FocusStage
import com.yehsung.aingcheck.feature.desktop.focus.FocusStageFace
import com.yehsung.aingcheck.feature.desktop.focus.FocusStagePolicy
import com.yehsung.aingcheck.ui.icons.AingIcon
import com.yehsung.aingcheck.ui.icons.AppIcon
import com.yehsung.aingcheck.ui.theme.AingColors
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.delay

/** 단추 문구(순수 — Swift FocusModeButtonText 그대로). */
object FocusModeText {
    /** 1단 남은 시간. "2시간 12분" / 정각 "3시간" / 1시간 미만 "42분" / 1분 미만 "곧 해제". 분은 **내림**(Swift 167-173). */
    fun remaining(seconds: Int): String {
        if (seconds < 60) return "곧 해제"
        val totalMinutes = seconds / 60
        val hours = totalMinutes / 60
        val minutes = totalMinutes % 60
        if (hours == 0) return "${minutes}분"
        return if (minutes == 0) "${hours}시간" else "${hours}시간 ${minutes}분"
    }

    /** 1단 길이를 말로 — 상수에서 파생한다. */
    val timedDurationText: String get() = remaining(FocusStagePolicy.TIMED_DURATION_SECONDS.toInt())

    /** 캡슐 글자: 꺼짐 "집중" · "1단" · "2단"(사용자 지시 2026-09-11 원문). */
    fun label(face: FocusStageFace): String = when (face.stage) {
        FocusStage.OFF -> "집중"
        FocusStage.TIMED -> "1단"
        FocusStage.ALWAYS -> "2단"
    }

    /** 툴팁 = 지금 상태(1단이면 남은 시간) — 다음 누름. */
    fun tooltip(face: FocusStageFace): String {
        val now = when (face.stage) {
            FocusStage.OFF -> "집중 모드 꺼짐"
            FocusStage.TIMED -> "1단 · ${remaining(face.remainingSeconds ?: 0)} 남음"
            FocusStage.ALWAYS -> "2단 · 끌 때까지 계속"
        }
        return "$now — ${help(face.stage)}"
    }

    /** 다음 누름. */
    fun help(stage: FocusStage): String = when (stage) {
        FocusStage.OFF -> "누르면 $timedDurationText 집중"
        FocusStage.TIMED -> "한 번 더 누르면 끌 때까지 계속"
        FocusStage.ALWAYS -> "누르면 집중 모드 해제"
    }

    /** 화면 낭독기가 읽는 지금 상태(툴팁은 다음 동작). */
    fun accessibilityValue(face: FocusStageFace): String = when (face.stage) {
        FocusStage.OFF -> "꺼짐"
        FocusStage.TIMED -> "1단, ${remaining(face.remainingSeconds ?: 0)} 남음"
        FocusStage.ALWAYS -> "2단, 끌 때까지 계속"
    }

    /** 콕 목록 안내줄(Swift PokeFocusNotice.text) — 남은 시간은 넣지 않는다(툴팁이 말한다). */
    fun pokeNotice(stage: FocusStage): String? = when (stage) {
        FocusStage.OFF -> null
        FocusStage.TIMED -> "집중 모드 1단 — $timedDurationText 동안 콕찌르기를 받지 않아요"
        FocusStage.ALWAYS -> "집중 모드 2단 — 해제 전까지 콕찌르기를 받지 않아요"
    }
}

/** 단계별 겉모습 표(Swift FocusModeButtonStyle). 어느 두 단계 사이에도 바탕·달·글자 중 둘 이상이 다르다(색에만 기대지 않는다). */
data class FocusModeStyle(val stage: FocusStage) {
    /** 꺼짐 0 · 1단 1 · 2단 2 — 단 번호 그대로. */
    val fillLevel: Int get() = when (stage) {
        FocusStage.OFF -> 0
        FocusStage.TIMED -> 1
        FocusStage.ALWAYS -> 2
    }

    /** 빈 달 ↔ 찬 달. */
    val icon: AppIcon get() = if (stage == FocusStage.OFF) AppIcon.DarkMode else AppIcon.DarkModeFill

    fun tint(c: AingColors): Color = when (fillLevel) {
        0 -> c.label2
        1 -> c.accent
        else -> c.onAccentFill
    }

    fun fill(c: AingColors): Color = when (fillLevel) {
        0 -> c.fill
        1 -> c.accentTint
        else -> c.accentFill
    }

    fun stroke(c: AingColors): Color = when (fillLevel) {
        0 -> c.separator
        1 -> c.accentLine
        else -> c.accent
    }

    companion object {
        /** 캡슐 폭(맥 50pt — 단계마다 글자 폭이 달라도 고정). */
        const val WIDTH_DP: Int = 50
        /** 캡슐 키(맥 20pt) · 바깥 틀(맥 27pt — 제목 행 높이). */
        const val CAPSULE_HEIGHT_DP: Int = 20
        const val FRAME_HEIGHT_DP: Int = 27
    }
}

/** 값 → 픽셀. 시계를 모른다(스냅숏이 그대로 그린다). */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun FocusModeControl(face: FocusStageFace, onPress: () -> Unit, modifier: Modifier = Modifier) {
    val c = AingTheme.colors
    val style = FocusModeStyle(face.stage)
    val tint = style.tint(c)
    TooltipArea(
        tooltip = {
            Box(Modifier.background(c.surface2, RoundedCornerShape(6.dp)).border(1.dp, c.separator, RoundedCornerShape(6.dp)).padding(6.dp)) {
                Text(FocusModeText.tooltip(face), style = MaterialTheme.typography.labelSmall, color = c.label)
            }
        },
        modifier = modifier,
    ) {
        Box(Modifier.height(FocusModeStyle.FRAME_HEIGHT_DP.dp), contentAlignment = Alignment.Center) {
            Row(
                Modifier
                    .size(FocusModeStyle.WIDTH_DP.dp, FocusModeStyle.CAPSULE_HEIGHT_DP.dp)
                    .background(style.fill(c), CircleShape)
                    .border(1.dp, style.stroke(c), CircleShape)
                    .clickable(onClick = onPress)
                    .semantics {
                        contentDescription = "집중 모드"
                        stateDescription = FocusModeText.accessibilityValue(face)
                    },
                horizontalArrangement = Arrangement.spacedBy(3.dp, Alignment.CenterHorizontally),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                AingIcon(style.icon, contentDescription = null, size = 11.dp, tint = tint)
                Text(FocusModeText.label(face), style = MaterialTheme.typography.labelSmall, fontWeight = FontWeight.Bold, color = tint, maxLines = 1)
            }
        }
    }
}

/** 단추 몫의 문(누름 = 순환 한 번 · 겉모습 = 컨트롤러의 순수 face). 서버 갱신은 컨트롤러가 한 번에 하나(F5). */
class FocusModeModel(private val controller: FocusModeController, private val clock: () -> SwiftDate) {
    fun face(): FocusStageFace = controller.focusStageFace(clock())

    /** 끔 → 3시간 → 계속 → 끔. */
    fun press() = controller.cycleFocusStage()

    internal val focusMode get() = controller.focusMode
    internal val revision get() = controller.revision
}

/**
 * 살아 있는 단추. 1단일 때만 1초마다 다시 읽는다(남은 시간 툴팁) — 꺼짐·2단에선 박자가 돌지 않는다(Swift MenuClockLeaf 와 같은 뜻).
 * 박자는 이 잎 안에만 있다 — 부르는 쪽(콕 목록)이 매초 다시 그려지지 않는다.
 */
@Composable
fun FocusModeButton(model: FocusModeModel, modifier: Modifier = Modifier) {
    val on by model.focusMode.collectAsState()
    val revision by model.revision.collectAsState()
    val tick = remember { mutableIntStateOf(0) }
    val face = remember(on, revision, tick.intValue) { model.face() }
    LaunchedEffect(face.stage) {
        while (face.stage == FocusStage.TIMED) {
            delay(1_000)
            tick.intValue += 1
        }
    }
    FocusModeControl(face, onPress = { model.press(); tick.intValue += 1 }, modifier = modifier)
}
