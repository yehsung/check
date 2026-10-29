// 원본: Sources/check/CheckMiniGameWindow.swift:217-300 · CheckGomokuWindow.swift:274-380 · CheckChessWindow.swift:333-430 ·
//       CheckTetrisDuelWindow.swift:242-330 · CheckGachaWindow.swift:48-78·441-510 · CheckCakeGiftWindow.swift:340-376
//       (W4-d 창 공통 부품 — games.md §4. 판정은 core·ui 스토어에 있고, 이 파일은 창 사건 → 스토어 통지 표 한 곳이다)
package com.yehsung.aingcheck.desktop.windows.kit

/**
 * 맥의 별도 창 여섯. [boundsKey] 는 맥 `frameAutosaveName` 그대로다 — ★ 창마다 **서로 달라야 한다**
 * (맥에서 같은 이름이면 `setFrameAutosaveName` 이 false 를 돌려주고 자리 저장이 조용히 죽었다. CheckChessWindow.swift:201-205).
 * 크기: 조정자 결정 W-3 #2 — 게임 창은 공용 세로 화면을 크기 조절 창에 그대로(기본 440×720dp, 최소 400×600).
 * 뽑기 420×552(CheckGachaWindow.swift) · 케이크 선물 440×430(CheckCakeGiftWindow.swift:20).
 */
enum class GameWindowKind(
    val boundsKey: String,
    val defaultWidthDp: Int,
    val defaultHeightDp: Int,
    val minWidthDp: Int,
    val minHeightDp: Int,
    /** 키 상실·화면 이동에 프레임 루프가 반응하는 창(미니게임·테트리스 대결). IME 를 떼는 창도 이 둘뿐이다([ImeGate]). */
    val realtime: Boolean,
) {
    MiniGame("check.miniGameWindow", 440, 720, 400, 600, realtime = true),
    Gomoku("check.gomoku.window", 440, 720, 400, 600, realtime = false),
    Chess("check.chess.window", 440, 720, 400, 600, realtime = false),
    TetrisDuel("check.tetris-duel.window", 440, 720, 400, 600, realtime = true),
    Gacha("check.gacha.window", 420, 552, 420, 552, realtime = false),
    CakeGift("check.cakeGift.window", 440, 430, 440, 430, realtime = false),
    ;

    /** 판돈 대결 창(오목·체스·테트리스 대결) — 스토어 창 문(GamesBoardGameLink: windowDidShow/Hide/Close·windowOcclusionDidChange)을 가진다. */
    val isBoardGame: Boolean get() = this == Gomoku || this == Chess || this == TetrisDuel
}

/** 껍데기가 Win32/AWT 에서 읽는 창 사건. 맥 NSWindowDelegate 콜백의 Windows 짝. */
sealed interface WindowEvent {
    /** 창이 섰다(처음 열기·다시 열기 — 맥 show()). */
    data object Shown : WindowEvent
    /** 최소화(맥 windowDidMiniaturize). '안 보임'이지 닫기가 아니다. */
    data object Minimized : WindowEvent
    /** 최소화에서 되살림(맥 windowDidDeminiaturize). */
    data object Restored : WindowEvent
    /** 사용자가 닫기(×)를 눌렀다(맥 windowWillClose). */
    data object UserClosed : WindowEvent
    /** 프로그램이 내렸다 — 로그아웃·계정 전환·closeAll(맥 close() = orderOut). */
    data object AppClosed : WindowEvent
    /** 키(포커스)를 잃었다(맥 windowDidResignKey). */
    data object FocusLost : WindowEvent
    /** 키를 얻었다(맥 windowDidBecomeKey). */
    data object FocusGained : WindowEvent
    /** 세션 잠금·가상 데스크톱 cloak(맥 occlusionState). Windows 엔 '완전히 덮임'이 없어 그 경우는 보임으로 남는다(위험 ③ 수용). */
    data class Visibility(val visible: Boolean) : WindowEvent
    /** 다른 모니터로 옮겨졌다(맥 windowDidChangeScreen). */
    data object ScreenChanged : WindowEvent

    companion object {
        /** 표의 열 순서(골든 순서). Visibility 는 참·거짓 둘을 다 잰다. */
        val TABLE: List<WindowEvent> = listOf(
            Shown, Minimized, Restored, UserClosed, AppClosed, FocusLost, FocusGained,
            Visibility(true), Visibility(false), ScreenChanged,
        )
    }
}

/** 스토어(또는 창 안 화면)로 옮길 통지. 이름은 맥 스토어 문 그대로. */
sealed interface StoreNotice {
    /** store.windowDidShow() — 폴링은 창이 보일 때만 돈다. */
    data object DidShow : StoreNotice
    /** store.windowDidHide() */
    data object DidHide : StoreNotice
    /** store.windowDidClose() · 케이크는 cakeGiftDidClose(). ★ DidHide 와 갈라 둔다(CheckGomokuWindow.swift:314). */
    data object DidClose : StoreNotice
    /** store.windowOcclusionDidChange(visible) — isWindowVisible 은 건드리지 않는다(CheckGomokuWindow.swift:340-346). */
    data class Occlusion(val visible: Boolean) : StoreNotice
    /** store.requestMiniGamePause() — 멈출지 말지는 화면이 정한다(PauseState.resigningKey, 0.3.62). */
    data object PauseIfPlaying : StoreNotice
    /** endRound(closing: true) — 창 닫기 = 판 끝(CheckMiniGameWindow.swift:247). */
    data object EndRound : StoreNotice
    /** 창이 선 **뒤** 그 화면 주사율을 다시 읽는다(CheckMiniGameWindow.swift:225-233·276). 간격 판정은 core MiniGameFrameRate. */
    data object ReadRefreshRate : StoreNotice
    /** 뽑기 기계가 움직여도 된다(isActive = 열림 ∧ ¬최소화 ∧ ¬가림). */
    data object MachineActive : StoreNotice
    /** 뽑기 기계를 멈춘다 + 커밋 전 예약을 거둔다(닫아도 루비 안 나감). */
    data object MachineInactive : StoreNotice
}

/**
 * 창의 표시 사실(맥 GachaWindowState 의 일반형). 사건을 접어 [isActive] 를 낸다.
 * FocusGained 는 맥처럼 열림만 맞춘다(windowDidBecomeKey — 다른 경로로 창이 올라와도 isOpen 이 사실과 갈리지 않게).
 */
data class WindowPresence(val open: Boolean = false, val minimized: Boolean = false, val occluded: Boolean = false) {
    val isActive: Boolean get() = open && !minimized && !occluded

    fun after(event: WindowEvent): WindowPresence = when (event) {
        WindowEvent.Shown -> WindowPresence(open = true, minimized = false, occluded = false)
        WindowEvent.Minimized -> copy(minimized = true)
        WindowEvent.Restored -> copy(minimized = false)
        WindowEvent.UserClosed, WindowEvent.AppClosed -> copy(open = false)
        WindowEvent.FocusGained -> copy(open = true)
        WindowEvent.FocusLost, WindowEvent.ScreenChanged -> this
        // 닫힌 창의 가림 통지는 무시한다(CheckGomokuWindow.swift:349 applyOcclusion 의 guard isOpen).
        is WindowEvent.Visibility -> if (open) copy(occluded = !event.visible) else this
    }
}

/** 창 사건 → 스토어 통지 판정 한 곳. W4-e·f 껍데기는 이 표만 부른다. */
object GameWindowEvents {

    /** 상태 없는 표(골든 `windows/kit/golden/window-events.golden.txt`). */
    fun notices(kind: GameWindowKind, event: WindowEvent): List<StoreNotice> = when (kind) {
        GameWindowKind.MiniGame -> miniGame(event)
        GameWindowKind.Gomoku, GameWindowKind.Chess -> boardGame(event, readsRefreshRate = false)
        GameWindowKind.TetrisDuel -> boardGame(event, readsRefreshRate = true)
        GameWindowKind.Gacha -> gacha(event)
        GameWindowKind.CakeGift -> cakeGift(event)
    }

    /**
     * 상태를 아는 판정. [before] 는 사건 직전의 창 표시 사실.
     * ① 닫힌 창의 Visibility 는 통지하지 않는다(맥 applyOcclusion 의 guard isOpen — 닫기가 이미 '안 보임'을 알렸다).
     * ② 뽑기의 Machine* 는 사건 뒤 [WindowPresence.isActive] 로 정한다(최소화된 채 잠금 해제돼도 기계가 깨어나지 않게).
     */
    fun notices(kind: GameWindowKind, event: WindowEvent, before: WindowPresence): List<StoreNotice> {
        if (event is WindowEvent.Visibility && !before.open) return emptyList()
        val base = notices(kind, event)
        if (kind != GameWindowKind.Gacha) return base
        val active = before.after(event).isActive
        return base.map {
            if (it == StoreNotice.MachineActive || it == StoreNotice.MachineInactive) {
                if (active) StoreNotice.MachineActive else StoreNotice.MachineInactive
            } else it
        }
    }

    // ★ 미니게임: 키 상실 = 일시정지만(0.3.62) · 닫기 = 판 끝 · 프로그램 닫기(close() = orderOut)는 판을 건드리지 않는다.
    //   최소화·잠금도 키 상실과 같은 일시정지다(맥은 최소화가 resignKey 를 부른다 — Windows 는 사건 순서가 보장되지 않아 표에 적는다).
    private fun miniGame(event: WindowEvent): List<StoreNotice> = when (event) {
        WindowEvent.Shown -> listOf(StoreNotice.ReadRefreshRate)
        WindowEvent.Minimized -> listOf(StoreNotice.PauseIfPlaying)
        WindowEvent.Restored -> emptyList()
        WindowEvent.UserClosed -> listOf(StoreNotice.EndRound)
        WindowEvent.AppClosed -> emptyList()
        WindowEvent.FocusLost -> listOf(StoreNotice.PauseIfPlaying)
        WindowEvent.FocusGained -> emptyList()   // 재개는 사용자의 [이어하기] 뿐(카운트다운).
        is WindowEvent.Visibility -> if (event.visible) emptyList() else listOf(StoreNotice.PauseIfPlaying)
        WindowEvent.ScreenChanged -> listOf(StoreNotice.ReadRefreshRate)
    }

    // ★ 대결 창 셋(오목·체스·테트리스 대결): 키 상실·닫기로 대국을 끝내지 않는다(windowDidResignKey 없음이 계약 —
    //   상대 시간 인질 금지). 최소화 = '안 보임'(DidHide 만, DidClose 금지 — CheckGomokuWindow.swift:314).
    //   닫기는 맥 :302-320 순서대로 DidHide 뒤 DidClose. 프로그램 닫기(로그아웃)도 닫기다(:296 — orderOut 은 windowWillClose 를 안 보낸다).
    private fun boardGame(event: WindowEvent, readsRefreshRate: Boolean): List<StoreNotice> = when (event) {
        WindowEvent.Shown -> if (readsRefreshRate) listOf(StoreNotice.DidShow, StoreNotice.ReadRefreshRate) else listOf(StoreNotice.DidShow)
        WindowEvent.Minimized -> listOf(StoreNotice.DidHide)
        WindowEvent.Restored -> listOf(StoreNotice.DidShow)
        WindowEvent.UserClosed, WindowEvent.AppClosed -> listOf(StoreNotice.DidHide, StoreNotice.DidClose)
        WindowEvent.FocusLost, WindowEvent.FocusGained -> emptyList()
        is WindowEvent.Visibility -> listOf(StoreNotice.Occlusion(event.visible))
        WindowEvent.ScreenChanged -> if (readsRefreshRate) listOf(StoreNotice.ReadRefreshRate) else emptyList()
    }

    // ★ 뽑기: isActive = 열림 ∧ ¬최소화 ∧ ¬가림. 거짓이면 기계 멈춤 + 커밋 전 예약 거둠(CheckGachaWindow.swift:58-75).
    private fun gacha(event: WindowEvent): List<StoreNotice> = when (event) {
        WindowEvent.Shown, WindowEvent.Restored -> listOf(StoreNotice.MachineActive)
        WindowEvent.Minimized, WindowEvent.UserClosed, WindowEvent.AppClosed -> listOf(StoreNotice.MachineInactive)
        WindowEvent.FocusLost, WindowEvent.FocusGained, WindowEvent.ScreenChanged -> emptyList()
        is WindowEvent.Visibility -> listOf(if (event.visible) StoreNotice.MachineActive else StoreNotice.MachineInactive)
    }

    // 케이크 선물: 사용자 닫기만 cakeGiftDidClose(고르지 않고 닫으면 선물은 남는다 — CheckCakeGiftWindow.swift:368-375).
    //   프로그램 닫기(close())는 아무 통지도 하지 않는다(:361-366).
    private fun cakeGift(event: WindowEvent): List<StoreNotice> = when (event) {
        WindowEvent.UserClosed -> listOf(StoreNotice.DidClose)
        else -> emptyList()
    }

    /** 골든·로그용 이름. */
    fun label(event: WindowEvent): String = when (event) {
        is WindowEvent.Visibility -> "Visibility(${event.visible})"
        else -> event.toString()
    }

    fun label(notice: StoreNotice): String = when (notice) {
        is StoreNotice.Occlusion -> "Occlusion(${notice.visible})"
        else -> notice.toString()
    }
}
