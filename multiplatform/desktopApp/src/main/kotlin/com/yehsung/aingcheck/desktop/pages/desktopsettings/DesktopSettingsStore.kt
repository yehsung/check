// 원본: Sources/check/WorkTimerStore.swift:3557-3575(설정 키) · :1935-1938(기본값 — 오버레이·할 일·자동 시작·단축키 모두 켜짐) ·
//       :3596-3660(설정 문 — 단축키는 허용 안 되는 조합이면 아무것도 바꾸지 않는다) ·
//       Sources/check/CheckApp.swift:757·856-861(로그인 시 자동 실행 — 사용자가 끈 사실만 남긴다, 기본 켜짐) ·
//       Sources/CheckCore/MacEdition.swift:176-185(AI 도구 기록 읽기 동의 — 키가 없으면 거절로 읽는다) ·
//       Sources/check/CheckTodoBoardAppearance.swift:379(보드 진하기 키) · W-9 #3(키 이름은 맥 UserDefaults 키 · 적용은 W3-d)
//
// Windows 설정 한 벌. **바뀜 흐름만** 낸다 — RunKey/StartupTask·RegisterHotKey 적용은 W3-d 가 [hotkey]·[launchAtLogin] 을 구독해 한다.
// 이 저장소가 이 키들의 **유일한 쓰는 쪽**이다(넛지 두 키만 예외 — AutoStartSuppression 이 쓰고 여기는 [reloadNudge] 로 다시 읽는다).
package com.yehsung.aingcheck.desktop.pages.desktopsettings

import com.yehsung.aingcheck.core.foundation.platform.desktop.HotkeyChord
import com.yehsung.aingcheck.desktop.platform.windows.hotkey.HotkeyPolicy
import com.yehsung.aingcheck.feature.desktop.DesktopKeyValueStore
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** 맥 UserDefaults 키 그대로(W-9 #3). 값의 모양이 맥과 다른 것은 [WORK_SHORTCUT_COMBO] 하나(맥은 WorkShortcut JSON Data, 여기는 [HotkeyChordCodec]). */
object DesktopSettingsKeys {
    const val OVERLAY_ENABLED = "check.overlayEnabled"
    const val TODO_ENABLED = "check.todoEnabled"
    const val TODO_BOARD_OPACITY = "check.todoBoardOpacity"
    const val AUTO_WORK_START = "check.work.autoStartEnabled"
    const val WORK_SHORTCUT_ENABLED = "check.workShortcut.enabled"
    const val WORK_SHORTCUT_COMBO = "check.workShortcut.combo"
    const val LAUNCH_AT_LOGIN_USER_TURNED_OFF = "check.launchAtLogin.userTurnedOff"
    /** 맥 앱스토어 판의 `AIToolDataConsent.key` — Windows 는 판과 무관하게 늘 묻는다(tokenUsageCollect, 기본 거절). */
    const val AI_TOOL_DATA_CONSENT = "check.mas.aiToolDataConsent"
    /** 넛지 억제 두 키 — 쓰는 쪽은 `feature.desktop.work.nudge.AutoStartSuppression`(같은 글자). */
    const val NUDGE_AUTO_START_SUPPRESSED = "check.nudge.autoStartSuppressed"
    const val NUDGE_LAST_ALIVE_AT = "check.nudge.lastAliveAt"
}

data class HotkeySetting(val enabled: Boolean, val chord: HotkeyChord)

/** 넛지 억제 상태(읽기 전용 사본). lastAliveAtMillis 는 AutoStartSuppression 이 쓰는 epoch ms. */
data class NudgeSetting(val autoStartSuppressed: Boolean, val lastAliveAtMillis: Long?)

/** 할 일 보드. opacity null = 아직 고른 적 없음(기본값은 보드 외양 쪽 W5-b4 가 정한다). */
data class TodoBoardSetting(val enabled: Boolean, val opacity: Double?)

/** 전역 단축키 등록 결과(맥 WorkShortcutStatus — WorkShortcut.swift:199-211). 적용 쪽(W3-d)이 [DesktopSettingsStore.noteHotkeyStatus] 로 알린다. */
enum class HotkeyRegistrationStatus { ACTIVE, OFF, PAUSED, CONFLICT, FAILED }

/** 조합 ↔ 저장 글자. `ctrl,alt,shift,win:<vk 10진>` — 깨졌거나 정책이 거절하는 값은 null(읽는 쪽이 기본값으로). */
object HotkeyChordCodec {
    fun encode(chord: HotkeyChord): String {
        val mods = listOfNotNull("ctrl".takeIf { chord.ctrl }, "alt".takeIf { chord.alt }, "shift".takeIf { chord.shift }, "win".takeIf { chord.win })
        return mods.joinToString(",") + ":" + chord.keyCode
    }

    fun decode(raw: String?): HotkeyChord? {
        if (raw == null) return null
        val colon = raw.lastIndexOf(':')
        if (colon < 0) return null
        val vk = raw.substring(colon + 1).toIntOrNull() ?: return null
        val mods = raw.substring(0, colon).split(',').filter { it.isNotEmpty() }
        if (mods.any { it !in setOf("ctrl", "alt", "shift", "win") }) return null
        val chord = HotkeyChord(ctrl = "ctrl" in mods, alt = "alt" in mods, shift = "shift" in mods, win = "win" in mods, keyCode = vk)
        return chord.takeIf { HotkeyPolicy.validate(it) == HotkeyPolicy.Verdict.Ok }
    }
}

class DesktopSettingsStore(private val kv: DesktopKeyValueStore) {
    private val autoWorkStartState = MutableStateFlow(kv.getBoolean(DesktopSettingsKeys.AUTO_WORK_START) ?: true)
    private val overlayState = MutableStateFlow(kv.getBoolean(DesktopSettingsKeys.OVERLAY_ENABLED) ?: true)
    private val collectState = MutableStateFlow(kv.getBoolean(DesktopSettingsKeys.AI_TOOL_DATA_CONSENT) ?: false)
    private val hotkeyState = MutableStateFlow(
        HotkeySetting(
            enabled = kv.getBoolean(DesktopSettingsKeys.WORK_SHORTCUT_ENABLED) ?: true,
            chord = HotkeyChordCodec.decode(kv.getString(DesktopSettingsKeys.WORK_SHORTCUT_COMBO)) ?: HotkeyPolicy.DEFAULT,
        ),
    )
    private val launchState = MutableStateFlow(kv.getBoolean(DesktopSettingsKeys.LAUNCH_AT_LOGIN_USER_TURNED_OFF) != true)
    private val nudgeState = MutableStateFlow(readNudge())
    private val todoState = MutableStateFlow(
        TodoBoardSetting(
            enabled = kv.getBoolean(DesktopSettingsKeys.TODO_ENABLED) ?: true,
            opacity = kv.getString(DesktopSettingsKeys.TODO_BOARD_OPACITY)?.toDoubleOrNull(),
        ),
    )
    private val recordingState = MutableStateFlow(false)
    private val statusState = MutableStateFlow(if (hotkeyState.value.enabled) HotkeyRegistrationStatus.ACTIVE else HotkeyRegistrationStatus.OFF)

    /** 자동 근무 시작(넛지). 기본 켜짐(맥 :1937). 소비: WorkWiring.autoWorkStartEnabled. */
    val autoWorkStart: StateFlow<Boolean> = autoWorkStartState.asStateFlow()
    /** 캐릭터 오버레이. 기본 켜짐(맥 :1935). 소비: OverlayWiring. */
    val overlayEnabled: StateFlow<Boolean> = overlayState.asStateFlow()
    /** AI 도구 기록 읽기 동의 = 토큰 사용량 수집. **기본 거절** — 거짓이면 스캔·업로드 0(W-9 #3). */
    val tokenUsageCollect: StateFlow<Boolean> = collectState.asStateFlow()
    val hotkey: StateFlow<HotkeySetting> = hotkeyState.asStateFlow()
    /** 사용자 뜻(맥 userTurnedOff 의 반대). 실제 등록 상태가 다르면 W3-d 가 [reflectLaunchAtLoginActual] 로 되돌린다. */
    val launchAtLogin: StateFlow<Boolean> = launchState.asStateFlow()
    val nudge: StateFlow<NudgeSetting> = nudgeState.asStateFlow()
    val todoBoard: StateFlow<TodoBoardSetting> = todoState.asStateFlow()
    /** 기록 중이면 W3-d 가 전역 등록을 잠시 내린다(맥 .paused — 지금 조합을 다시 눌러 지정할 때 근무가 토글되면 안 된다). */
    val hotkeyRecording: StateFlow<Boolean> = recordingState.asStateFlow()
    val hotkeyStatus: StateFlow<HotkeyRegistrationStatus> = statusState.asStateFlow()

    fun setAutoWorkStart(enabled: Boolean) = write(autoWorkStartState, DesktopSettingsKeys.AUTO_WORK_START, enabled)

    fun setOverlayEnabled(enabled: Boolean) = write(overlayState, DesktopSettingsKeys.OVERLAY_ENABLED, enabled)

    fun setTokenUsageCollect(granted: Boolean) = write(collectState, DesktopSettingsKeys.AI_TOOL_DATA_CONSENT, granted)

    fun setHotkeyEnabled(enabled: Boolean) {
        if (hotkeyState.value.enabled == enabled) return
        kv.putBoolean(DesktopSettingsKeys.WORK_SHORTCUT_ENABLED, enabled)
        hotkeyState.value = hotkeyState.value.copy(enabled = enabled)
        // 끄는 순간 기록도 끝낸다(맥 WorkShortcutRecorderRow onChange — 기록을 끝내는 집은 하나).
        if (!enabled) recordingState.value = false
    }

    /** 새 조합 저장. 정책이 거절하면 **아무것도 바꾸지 않고** false(맥 setWorkShortcut — 기록기가 걸러도 이 문이 최종 관문). */
    fun setHotkey(chord: HotkeyChord): Boolean {
        if (HotkeyPolicy.validate(chord) != HotkeyPolicy.Verdict.Ok) return false
        if (hotkeyState.value.chord != chord) {
            kv.putString(DesktopSettingsKeys.WORK_SHORTCUT_COMBO, HotkeyChordCodec.encode(chord))
            hotkeyState.value = hotkeyState.value.copy(chord = chord)
        }
        return true
    }

    /** [기본값으로] — 키를 지운다(다음 실행도 기본값). */
    fun resetHotkey() {
        kv.remove(DesktopSettingsKeys.WORK_SHORTCUT_COMBO)
        if (hotkeyState.value.chord != HotkeyPolicy.DEFAULT) hotkeyState.value = hotkeyState.value.copy(chord = HotkeyPolicy.DEFAULT)
    }

    fun setHotkeyRecording(recording: Boolean) {
        recordingState.value = recording && hotkeyState.value.enabled
    }

    fun noteHotkeyStatus(status: HotkeyRegistrationStatus) {
        statusState.value = status
    }

    /** 스위치(맥 applyUserToggle): 끈 사실만 남긴다 — 켜면 표식을 내린다. */
    fun setLaunchAtLogin(enabled: Boolean) {
        kv.putBoolean(DesktopSettingsKeys.LAUNCH_AT_LOGIN_USER_TURNED_OFF, !enabled)
        launchState.value = enabled
    }

    /** 적용 뒤 실제 상태(쓰기 실패·작업 관리자에서 끔). 스위치가 거짓말하지 않게 값만 맞춘다 — 사용자 뜻 키는 건드리지 않는다. */
    fun reflectLaunchAtLoginActual(actual: Boolean) {
        launchState.value = actual
    }

    fun setTodoEnabled(enabled: Boolean) {
        if (todoState.value.enabled == enabled) return
        kv.putBoolean(DesktopSettingsKeys.TODO_ENABLED, enabled)
        todoState.value = todoState.value.copy(enabled = enabled)
    }

    fun setTodoBoardOpacity(opacity: Double?) {
        kv.putString(DesktopSettingsKeys.TODO_BOARD_OPACITY, opacity?.toString())
        todoState.value = todoState.value.copy(opacity = opacity)
    }

    /** 넛지 키를 다시 읽는다(쓰는 쪽이 따로 있다 — 플라이아웃 열림·틱에서 부른다). */
    fun reloadNudge() {
        nudgeState.value = readNudge()
    }

    private fun readNudge() = NudgeSetting(
        autoStartSuppressed = kv.getBoolean(DesktopSettingsKeys.NUDGE_AUTO_START_SUPPRESSED) == true,
        lastAliveAtMillis = kv.getLong(DesktopSettingsKeys.NUDGE_LAST_ALIVE_AT),
    )

    private fun write(state: MutableStateFlow<Boolean>, key: String, value: Boolean) {
        if (state.value == value && kv.getBoolean(key) == value) return
        kv.putBoolean(key, value)
        state.value = value
    }
}
