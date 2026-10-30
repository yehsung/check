// 원본: Sources/CheckMobileKit/Me/MeGachaViews.swift @ 3bd04bd (MeGachaMachineScreen 의 isActive · 덮개 닫기 — Android 껍데기 몫)
// 원본: Sources/CheckMobileKit/Me/MeGachaHaptics.swift @ 3bd04bd (기계 햅틱 짝 — 톱니 · 막힘 · 한 바퀴 · 덜컹 · 떨어짐 · 톡톡 · 공개 · 조각)
//
// 상점 · 뽑기 · 미션 · 캐릭터 고르기 · 생일 선물 화면의 Android 껍데기. 화면 본문은 ui(공용 — 판정은 스토어)이고 여기는 Android 만 아는 것만 잇는다:
//  - 기계 isActive = 수명 RESUMED(앱이 뒤로 가면 기계가 멎고 커밋 전 예약을 거둔다 — 안 보이는 기계는 루비를 쓰지 않는다)
//  - 시스템 뒤로가기 = 기계 [닫기](iOS 덮개는 아래로 끌어 닫히지 않고 ✕ 로만 닫힌다 — Android 는 뒤로가 그 ✕ 다)
//  - 동작 줄이기 = 개발자 옵션 '애니메이션 배율 0'(ANIMATOR_DURATION_SCALE) — 접근성 '애니메이션 삭제'가 이 값을 0 으로 만든다
//  - 햅틱 = View.performHapticFeedback(사용자 진동 설정을 따른다 — 진동기를 직접 부르지 않는다)
// 조립(K11 — NavGraph · AppContainer)은 통합 갈래가 한다: 어느 목적지에 무엇을 거는지는 갈래 스크래치 assembly.md.
package com.yehsung.aingcheck.android.screens.shop

import androidx.core.view.WindowCompat
import androidx.compose.runtime.DisposableEffect
import android.content.ContextWrapper
import android.app.Activity
import android.content.Context
import android.os.Build
import android.provider.Settings
import android.view.HapticFeedbackConstants
import android.view.View
import androidx.activity.compose.BackHandler
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.currentStateAsState
import com.yehsung.aingcheck.core.stores.me.MeStore
import com.yehsung.aingcheck.ui.gacha.MeGachaMachineScreen
import com.yehsung.aingcheck.ui.gacha.MeGachaOddsSheetContent
import com.yehsung.aingcheck.ui.gacha.machine.GachaMachineHapticEvent
import com.yehsung.aingcheck.ui.gacha.machine.GachaMachineHaptics
import com.yehsung.aingcheck.ui.missions.MeMissionsScreen
import com.yehsung.aingcheck.ui.shop.MeCakeGiftSheetHost
import com.yehsung.aingcheck.ui.shop.MeCharacterPickerScreen
import com.yehsung.aingcheck.ui.shop.MeShopScreen

/** 상점(Dest.Shop). [onOpenOdds] 를 넘기면 확률 표를 목적지 대화상자(Dest.GachaOddsSheet)로 연다 — null 이면 화면 안 시트. */
@Composable
fun ShopRoute(store: MeStore, onBack: () -> Unit, onOpenMachine: () -> Unit, onOpenOdds: (() -> Unit)? = null) {
    MeShopScreen(store, onBack = onBack, onOpenMachine = onOpenMachine, onOpenOdds = onOpenOdds)
}

/** 확률 표(Dest.GachaOddsSheet — 대화상자 목적지). 서버 순서 그대로. */
@Composable
fun GachaOddsRoute(store: MeStore, onClose: () -> Unit) {
    MeGachaOddsSheetContent(store, onClose = onClose)
}

/** 캡슐 뽑기 기계(Dest.GachaMachine — 전체 화면). 뒤로가기 = [닫기]. 수명이 RESUMED 일 때만 기계가 돈다. */
@Composable
fun GachaMachineRoute(store: MeStore, onClose: () -> Unit) {
    val lifecycle by LocalLifecycleOwner.current.lifecycle.currentStateAsState()
    val view = LocalView.current
    val haptics = remember(view) { AndroidGachaHaptics(view) }
    BackHandler(onBack = onClose)
    LightSystemBarIcons(view)
    MeGachaMachineScreen(
        store,
        onClose = onClose,
        isAppActive = lifecycle.isAtLeast(Lifecycle.State.RESUMED),
        haptics = haptics,
        reduceMotion = rememberReduceMotion(),
    )
}

/**
 * 기계가 보이는 동안 상태 바 · 내비 막대 아이콘을 밝게(보라 배경 위 — 앱이 라이트 모드여도). 떠나면 들어올 때 값으로 되돌린다.
 * iOS fullScreenCover 의 어두운 덮개 위 흰 상태 바 자리(MeGachaViews.swift:174 `.ignoresSafeArea()` — 배경은 셸이 막대 뒤까지 깐다, ShellSystemBarRules).
 */
@Composable
private fun LightSystemBarIcons(view: View) {
    DisposableEffect(view) {
        val window = view.context.findActivity()?.window ?: return@DisposableEffect onDispose {}
        val bars = WindowCompat.getInsetsController(window, view)
        val status = bars.isAppearanceLightStatusBars
        val navigation = bars.isAppearanceLightNavigationBars
        bars.isAppearanceLightStatusBars = false
        bars.isAppearanceLightNavigationBars = false
        onDispose {
            bars.isAppearanceLightStatusBars = status
            bars.isAppearanceLightNavigationBars = navigation
        }
    }
}

private tailrec fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> null
}

/** 「미션」 화면(조립이 목적지를 더한다 — iOS MeDestination.missions, 딥링크 없음). */
@Composable
fun MissionsRoute(store: MeStore, onBack: () -> Unit) {
    MeMissionsScreen(store, onBack = onBack, reduceMotion = rememberReduceMotion())
}

/** 캐릭터 고르기(Dest.CharacterPicker). 머리 그림은 살아 있는 미리보기 자리(LocalLiveCharacterPreview — W5-c). */
@Composable
fun CharacterPickerRoute(store: MeStore, onBack: () -> Unit, onOpenShop: () -> Unit, onOpenMachine: () -> Unit) {
    MeCharacterPickerScreen(store, onBack = onBack, onOpenShop = onOpenShop, onOpenMachine = onOpenMachine)
}

/** 생일 선물 고르기 창 — 탭 막대 위(어느 탭에 있든 뜬다). 스토어의 cakeGiftSheet 가 서면 연다. */
@Composable
fun CakeGiftSheetRoute(store: MeStore) {
    MeCakeGiftSheetHost(store)
}

/** 애니메이션 배율 0 이면 동작 줄이기(톡톡 · 흔들기 · 빛줄기 없이 겹쳐 바뀌는 공개). */
@Composable
fun rememberReduceMotion(): Boolean {
    val context = LocalContext.current
    return remember(context) { ReduceMotion.isOn(context) }
}

object ReduceMotion {
    fun isOn(context: Context): Boolean = isOn(Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f))

    /** 배율 0 = 꺼짐. 그 밖(0.5 · 1 · 1.5 …)은 연출 그대로. */
    fun isOn(animatorScale: Float): Boolean = animatorScale == 0f
}

/**
 * 기계 햅틱 → Android 햅틱 상수. iOS 짝(MeGachaHaptics): 톱니 = 선택 틱 · 막힘 = 경고 · 한 바퀴 = 묵직 · 덜컹 = 부드럽게 · 떨어짐 = 단단 ·
 * 톡톡 = 단단(1 → 3 으로 세진다 — Android 상수는 세기가 없어 셋째만 '확인') · 공개 = 성공 · 조각 = 가볍게.
 */
class AndroidGachaHaptics(private val view: View) : GachaMachineHaptics {
    override fun play(event: GachaMachineHapticEvent) {
        for (constant in AndroidGachaHapticMap.constants(event, Build.VERSION.SDK_INT)) view.performHapticFeedback(constant)
    }
}

object AndroidGachaHapticMap {
    /** 사건 → 낼 상수(차례대로). [sdk] 30 미만은 CONFIRM · REJECT 가 없어 가까운 것으로 접는다. */
    fun constants(event: GachaMachineHapticEvent, sdk: Int): List<Int> {
        val confirm = if (sdk >= 30) HapticFeedbackConstants.CONFIRM else HapticFeedbackConstants.VIRTUAL_KEY
        val reject = if (sdk >= 30) HapticFeedbackConstants.REJECT else HapticFeedbackConstants.LONG_PRESS
        return when (event) {
            GachaMachineHapticEvent.Ratchet -> listOf(HapticFeedbackConstants.CLOCK_TICK)
            GachaMachineHapticEvent.Refuse -> listOf(reject)
            GachaMachineHapticEvent.Commit -> listOf(HapticFeedbackConstants.LONG_PRESS)
            GachaMachineHapticEvent.Rumble -> listOf(HapticFeedbackConstants.CLOCK_TICK)
            GachaMachineHapticEvent.Land -> listOf(HapticFeedbackConstants.VIRTUAL_KEY)
            is GachaMachineHapticEvent.Tap -> listOf(if (event.count >= 3) confirm else HapticFeedbackConstants.KEYBOARD_TAP)
            GachaMachineHapticEvent.GoldFlip, GachaMachineHapticEvent.Reveal -> listOf(confirm)
            GachaMachineHapticEvent.GoldReveal -> listOf(HapticFeedbackConstants.LONG_PRESS, confirm)
            GachaMachineHapticEvent.Shard -> listOf(HapticFeedbackConstants.CLOCK_TICK)
        }
    }
}
