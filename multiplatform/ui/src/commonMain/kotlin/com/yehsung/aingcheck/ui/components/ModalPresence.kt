// 원본: Sources/CheckMobileKit/Messages/MegaphoneBannerPhoneRules.swift MegaphoneBannerModalProbe.isModalPresented @ a6791165(57810a8e)
// 화면 안에서 직접 띄운 시트·대화상자(ModalBottomSheet · AlertDialog — 액티비티 위 **별도 창**)를 센다. 셸이 내려 준다.
// 확성기 배너는 탭 셸 위에 그려져 이런 창 밑에 깔린다 — 떠 있는 동안 배너를 미뤄야 한다(계약 '미룸: 시트·풀스크린 커버가 떠 있을 때').
// iOS 는 떠 있는 presentedViewController 를 모두 본다. Compose 는 창 목록을 물을 길이 없어 띄우는 자리가 스스로 알린다:
// 시트·대화상자를 띄우는 if 갈래 안(또는 띄울 때만 그리는 함수 머리)에서 [ModalPresenceMark] 를 한 번 부른다.
// nav 대화상자 목적지(시트 라우트)는 셸이 목적지로 따로 본다 — 여기서 세지 않는다. 데스크톱 · 미리보기는 제공자가 없어 아무것도 안 한다.
package com.yehsung.aingcheck.ui.components

import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf

/** 떠 있는 화면 안 시트·대화상자의 수. [onChange] 는 수가 바뀐 **뒤** 부른다(셸: 배너 미룸 다시 맞추기). */
class ModalPresence(private val onChange: () -> Unit = {}) {
    var depth: Int by mutableIntStateOf(0)
        private set

    val isPresented: Boolean get() = depth > 0

    fun enter() {
        depth += 1
        onChange()
    }

    fun exit() {
        depth = maxOf(0, depth - 1)
        onChange()
    }
}

/** 셸이 내려 주는 계수기. null = 세지 않는다(데스크톱 · 미리보기 · 시험). */
val LocalModalPresence = staticCompositionLocalOf<ModalPresence?> { null }

/** 이 자리가 그려지는 동안 시트·대화상자 하나가 떠 있다고 알린다. 띄우는 if 갈래 안에서 시트·대화상자 바로 앞에 부른다. */
@Composable
fun ModalPresenceMark() {
    val presence = LocalModalPresence.current ?: return
    DisposableEffect(presence) {
        presence.enter()
        onDispose { presence.exit() }
    }
}
