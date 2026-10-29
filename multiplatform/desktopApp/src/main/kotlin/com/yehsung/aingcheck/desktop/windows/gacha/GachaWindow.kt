// 원본: Sources/check/CheckGachaWindow.swift:1-30(머리 규약) · :48-78(GachaWindowState) · :441-500(show · close · windowWillClose · 최소화 · 가림)
//       Sources/CheckCore/GachaMachine/GachaMachineView.swift:128(GachaMachineLink.hasUnrevealedTurn)
//       (W4-f — 뽑기 창. 창 수명은 kit GameWindowSlot, 사건 → 통지 판정은 kit GameWindowEvents 표 한 곳)
//
// 이 창만의 규칙(맥 머리 주석 번호 그대로):
//   ★① 안 보이면 기계를 멈춘다 — isActive = 열림 ∧ ¬최소화 ∧ ¬가림. 거짓이면 기계가 프레임을 멈추고 **커밋 전 예약(손잡이 자동 회전 ·
//       [한 번 더])을 거둔다** — 손잡이를 누르고 바로 닫아도 루비가 안 나간다(닫아도 창이 파괴되지 않아 onDispose 가 안 오므로 이 값이 유일한 문).
//   ★② 다시 열면 새 기계(contentID+1). 단 왕복 중이거나 루비를 낸 판의 결과를 아직 못 봤으면 그 기계 그대로(CheckGachaWindow.swift:445).
//   ③ 외관은 시스템을 따른다(다른 창들은 앱 다크 고정). ④ 420×552 고정.
package com.yehsung.aingcheck.desktop.windows.gacha

import androidx.compose.foundation.background
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.yehsung.aingcheck.core.stores.me.MeStore
import com.yehsung.aingcheck.desktop.platform.windows.flyout.PxRect
import com.yehsung.aingcheck.desktop.windows.kit.GameWindowHandle
import com.yehsung.aingcheck.desktop.windows.kit.GameWindowKind
import com.yehsung.aingcheck.desktop.windows.kit.GameWindowSlot
import com.yehsung.aingcheck.desktop.windows.kit.StoreNotice
import com.yehsung.aingcheck.desktop.windows.kit.WindowBoundsStore
import com.yehsung.aingcheck.desktop.windows.kit.WindowEvent
import com.yehsung.aingcheck.ui.gacha.MeGachaMachineScreen
import com.yehsung.aingcheck.ui.theme.AingTheme

/** 기계의 사실 — 스토어·기계 값을 그대로 읽는다(판정 없음). */
interface GachaMachineFacts {
    /** 뽑기 왕복 중(스토어 isPulling — 맥 store.gachaPulling). */
    val isPulling: Boolean

    /** 루비를 낸 판의 결과를 사용자가 아직 못 봤다(맥 GachaMachineLink.hasUnrevealedTurn — 왕복 중 · 공개 전 · 안 보이는 동안 공개가 끝남). */
    fun hasUnrevealedTurn(): Boolean
}

/**
 * 기계가 '루비 낸 판 미공개'를 알려 오는 칸.
 * 공용 패치 P2 전 임시: ui MeGachaMachineScreen 이 GachaMachineDirector.hasUnrevealedTurn 을 밖에 내지 않는다 → 아무도 쓰지 않아 늘 false
 * (그동안은 '왕복 중'만 기계를 지킨다 — 왕복 0.3초 · 공개 2.4~3.8초라 공개 중에 닫았다 다시 열면 새 기계가 선다).
 * P2(`onUnrevealedChanged: (Boolean) -> Unit`) 뒤에는 [GachaWindowContent] 가 그 콜백을 이 칸에 잇는다.
 */
class GachaUnrevealedCell {
    @Volatile
    var value: Boolean = false
}

/** 나 탭 스토어를 기계 사실로 읽는다. */
fun MeStore.gachaMachineFacts(unrevealed: GachaUnrevealedCell = GachaUnrevealedCell()): GachaMachineFacts {
    val store = this
    return object : GachaMachineFacts {
        override val isPulling: Boolean get() = store.isPulling
        override fun hasUnrevealedTurn(): Boolean = unrevealed.value
    }
}

/** 창의 표시 사실(맥 GachaWindowState). 컨트롤러가 적고 창 내용이 읽는다. */
@Stable
class GachaWindowState {
    /** 기계의 정체성 — 바뀌면 기계(감독 · 판)가 새로 선다. 닫힌 창을 다시 열 때만 올린다(★②). */
    var contentID: Int by mutableIntStateOf(0)
        private set

    /** 기계가 움직여도 되는가(★① — kit 표의 MachineActive/MachineInactive 를 그대로 옮긴다). */
    var isActive: Boolean by mutableStateOf(false)
        internal set

    /**
     * 열기 직전 판정(★② CheckGachaWindow.swift:445 `existed, !state.isOpen, !gachaPulling, !hasUnrevealedTurn`).
     * 처음 만드는 창 · 이미 열린 창(멱등 열기) · 왕복 중 · 미공개 판이면 그대로. 새 기계를 세웠으면 true.
     */
    fun beforeOpen(existed: Boolean, wasOpen: Boolean, facts: GachaMachineFacts): Boolean {
        if (!existed || wasOpen || facts.isPulling || facts.hasUnrevealedTurn()) return false
        contentID += 1
        return true
    }
}

/**
 * 뽑기 창 하나. 열기·닫기·창 사건을 받아 [state] 를 맞춘다. 실제 창은 [create] 뒤에 있어 시험은 창 0 으로 잰다.
 * 떠 있는 뽑기 왕복은 끊지 않는다(맥 close() — 서버 일은 스토어 몫이고 결과는 스토어에 옮겨진다).
 */
class GachaWindowController(
    private val facts: GachaMachineFacts,
    create: (onEvent: (WindowEvent) -> Unit) -> GameWindowHandle,
    bounds: WindowBoundsStore,
    workAreas: () -> List<PxRect>,
    scale: () -> Double,
) {
    val state = GachaWindowState()
    val slot: GameWindowSlot = GameWindowSlot(GameWindowKind.Gacha, { create(::onEvent) }, bounds, workAreas, scale, ::apply)

    /** 뽑기 창을 연다(멱등 — 최소화돼 있으면 되살린다). 닫혀 있던 창이면 기계를 새로 세운다(★②). */
    fun open() {
        state.beforeOpen(existed = slot.isCreated, wasOpen = slot.presence.open, facts = facts)
        slot.open()
    }

    /** 프로그램 닫기 — 기계의 [닫기] · 로그아웃 · 계정 전환. 창은 남는다. */
    fun close() = slot.closeFromApp()

    /** 껍데기가 Win32/AWT 사건을 넘긴다. */
    fun onEvent(event: WindowEvent) = slot.onEvent(event)

    private fun apply(notices: List<StoreNotice>) {
        for (n in notices) when (n) {
            StoreNotice.MachineActive -> state.isActive = true
            StoreNotice.MachineInactive -> state.isActive = false
            else -> Unit
        }
    }
}

/**
 * 뽑기 창 내용. 기계는 공용 ui 화면 그대로(공개 반응 동작은 건드리지 않는다) — 껍데기는 [GachaWindowState.isActive] 를 넘기고
 * [GachaWindowState.contentID] 로 기계를 새로 세우기만 한다(key — 감독·확률 시트·gachaMachineDidAppear 가 같이 새로 선다).
 * @param dark ③ 시스템 외관(기본). 시험이 고정한다.
 */
@Composable
fun GachaWindowContent(
    store: MeStore,
    state: GachaWindowState,
    onClose: () -> Unit,
    dark: Boolean = isSystemInDarkTheme(),
    reduceMotion: Boolean = false,
) {
    AingTheme(dark = dark) {
        Box(Modifier.size(GameWindowKind.Gacha.defaultWidthDp.dp, GameWindowKind.Gacha.defaultHeightDp.dp).background(AingTheme.colors.background)) {
            key(state.contentID) {
                MeGachaMachineScreen(store, onClose = onClose, isAppActive = state.isActive, reduceMotion = reduceMotion)
            }
        }
    }
}
