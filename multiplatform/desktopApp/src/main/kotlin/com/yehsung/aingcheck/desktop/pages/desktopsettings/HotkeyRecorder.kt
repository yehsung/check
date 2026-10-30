// 원본: Sources/check/CheckSettingsView.swift:907-1132(안내 고르기 :933-950 · 안내 다섯 줄 :956-960 · 색 :1124-1129 · 키캡 :1069-1095 ·
//       [기본값으로] :1096-1110 · WorkShortcutRecorderRow :1016) · Sources/check/WorkShortcut.swift:105-107(표에 없는 키는 "키 <코드>") · :199-211(상태) ·
//       설계 D§6(Win 키·F12 예약 · RegisterHotKey 실패 = 다른 앱과 겹침) · W-9 #4
//
// 판정은 [HotkeyPolicy] 하나(금지 조합). 겹침은 적용 쪽(W3-d)의 RegisterHotKey 결과([HotkeyRegistrationStatus.CONFLICT])로만 안다.
package com.yehsung.aingcheck.desktop.pages.desktopsettings

import com.yehsung.aingcheck.core.foundation.platform.desktop.HotkeyChord
import com.yehsung.aingcheck.desktop.platform.windows.hotkey.HotkeyPolicy

/** 키캡 글자(Windows 관례 "Ctrl+Alt+Shift+Space"). 왼쪽 Alt 기준(오른쪽 Alt 는 한/영 — D§6). */
object WindowsKeyNames {
    private val named: Map<Int, String> = buildMap {
        put(0x08, "Backspace"); put(0x09, "Tab"); put(0x0D, "Enter"); put(0x13, "Pause"); put(0x1B, "Esc"); put(0x20, "Space")
        put(0x21, "PgUp"); put(0x22, "PgDn"); put(0x23, "End"); put(0x24, "Home")
        put(0x25, "←"); put(0x26, "↑"); put(0x27, "→"); put(0x28, "↓")
        put(0x2C, "PrtSc"); put(0x2D, "Insert"); put(0x2E, "Delete")
        for (d in 0..9) put(0x30 + d, d.toString())
        for (c in 'A'..'Z') put(c.code, c.toString())
        for (n in 0..9) put(0x60 + n, "Num $n")
        put(0x6A, "Num *"); put(0x6B, "Num +"); put(0x6D, "Num -"); put(0x6E, "Num ."); put(0x6F, "Num /")
        for (f in 1..24) put(0x6F + f, "F$f")
        put(0xBA, ";"); put(0xBB, "="); put(0xBC, ","); put(0xBD, "-"); put(0xBE, "."); put(0xBF, "/"); put(0xC0, "`")
        put(0xDB, "["); put(0xDC, "\\"); put(0xDD, "]"); put(0xDE, "'")
    }

    fun key(vk: Int): String = named[vk] ?: "키 $vk"

    fun display(chord: HotkeyChord): String = (
        listOfNotNull("Ctrl".takeIf { chord.ctrl }, "Alt".takeIf { chord.alt }, "Shift".takeIf { chord.shift }, "Win".takeIf { chord.win }) +
            key(chord.keyCode)
        ).joinToString("+")

    /** 화면 읽기용("컨트롤 알트 시프트 스페이스" 대신 키 이름을 띄어 읽는다). */
    fun spoken(chord: HotkeyChord): String = display(chord).replace("+", " ")
}

/**
 * AWT 키 코드(Compose 데스크톱 `KeyEvent.nativeKeyCode`) → Windows 가상 키. 글자·숫자·F1~F12·화살표·숫자판은 같은 값이고
 * 나머지는 표로 옮긴다. 모르는 키는 null(기록기가 무시). AWT 가 IME 처리 키를 VK_UNDEFINED(0)로 줄 때는 VK_PROCESSKEY 로 접어
 * 정책이 KEY_IS_IME 로 거절하게 한다(D§13-1 — 한글 상태 글자 키). ★ 실제 IME 이벤트 모양은 VM 확인 몫.
 */
object AwtToWindowsVk {
    private val table: Map<Int, Int> = buildMap {
        put(0, 0xE5); put(229, 0xE5)
        put(8, 0x08); put(9, 0x09); put(10, 0x0D); put(19, 0x13); put(20, 0x14); put(27, 0x1B); put(32, 0x20)
        for (c in 33..40) put(c, c) // PgUp·PgDn·End·Home·←↑→↓ (0x21~0x28 같은 값)
        put(127, 0x2E); put(155, 0x2D); put(154, 0x2C); put(144, 0x90); put(145, 0x91)
        put(16, 0x10); put(17, 0x11); put(18, 0x12); put(524, 0x5B); put(157, 0x5B)
        put(21, 0x15); put(24, 0x18); put(25, 0x19)
        for (c in 0x30..0x39) put(c, c)
        for (c in 0x41..0x5A) put(c, c)
        for (c in 96..107) put(c, c); put(108, 0x6C); put(109, 0x6D); put(110, 0x6E); put(111, 0x6F)
        for (f in 0..11) put(112 + f, 0x70 + f)
        for (f in 0..11) put(61440 + f, 0x7C + f) // F13~F24
        put(59, 0xBA); put(61, 0xBB); put(44, 0xBC); put(45, 0xBD); put(46, 0xBE); put(47, 0xBF); put(192, 0xC0)
        put(91, 0xDB); put(92, 0xDC); put(93, 0xDD); put(222, 0xDE)
    }

    fun map(awtKeyCode: Int): Int? = table[awtKeyCode]
}

/** 안내 한 줄(맥 :956-960 의 다섯 + Windows 만의 IME 한 줄). 색 뜻: HINT 회색 · RETRY 주황 · DANGER 빨강. */
enum class HotkeyNotice(val text: String, val tone: Tone) {
    RECORDING("Ctrl Alt Shift 중 두 개 이상과 함께 눌러요 · Esc 취소", Tone.HINT),
    REJECTED_SHAPE("Ctrl Alt Shift 중 두 개 이상을 함께 눌러 주세요", Tone.RETRY),
    REJECTED_SYSTEM("Windows 예약 키와 겹쳐요. 다른 조합을 눌러 주세요", Tone.RETRY),
    REJECTED_IME("한/영 키와 한글 입력은 쓸 수 없어요. 영문 상태로 눌러 주세요", Tone.RETRY),
    CONFLICT("다른 앱이 쓰는 조합이에요. 다른 키로 바꿔 주세요.", Tone.DANGER),
    FAILED("단축키를 등록하지 못했어요.", Tone.DANGER),
    ;

    enum class Tone { HINT, RETRY, DANGER }

    companion object {
        /** 맥 안내 고르기(:933-950): 기록 중이면 기록 안내(거절이 있으면 그 줄), 아니면 등록 결과의 겹침·실패만. 끈 사람에게 옛 겹침은 안 보인다. */
        fun resolve(recording: Boolean, rejection: HotkeyPolicy.Rejection?, status: HotkeyRegistrationStatus, enabled: Boolean): HotkeyNotice? {
            if (recording) {
                return when (rejection) {
                    null -> RECORDING
                    HotkeyPolicy.Rejection.WIN_KEY_RESERVED, HotkeyPolicy.Rejection.RESERVED_KEY -> REJECTED_SYSTEM
                    HotkeyPolicy.Rejection.KEY_IS_IME -> REJECTED_IME
                    HotkeyPolicy.Rejection.TOO_FEW_MODIFIERS, HotkeyPolicy.Rejection.KEY_IS_MODIFIER,
                    HotkeyPolicy.Rejection.KEY_OUT_OF_RANGE -> REJECTED_SHAPE
                }
            }
            if (!enabled) return null
            return when (status) {
                HotkeyRegistrationStatus.CONFLICT -> CONFLICT
                HotkeyRegistrationStatus.FAILED -> FAILED
                HotkeyRegistrationStatus.ACTIVE, HotkeyRegistrationStatus.OFF, HotkeyRegistrationStatus.PAUSED -> null
            }
        }
    }
}

/** 키 하나를 받은 결과. */
sealed interface HotkeyKeyResult {
    data object Ignored : HotkeyKeyResult
    data object Cancelled : HotkeyKeyResult
    data class Rejected(val reason: HotkeyPolicy.Rejection) : HotkeyKeyResult
    data class Saved(val chord: HotkeyChord) : HotkeyKeyResult
}

/**
 * 기록기(순수 — Compose 는 키를 넘기기만 한다). 기록 시작 = 저장소 `hotkeyRecording` 참(W3-d 가 등록을 내린다).
 * 수식키만 누른 동안은 기다린다 · 수식키 없는 Esc 는 취소 · 거절은 안내만 바꾸고 기록을 이어 간다(맥과 같다) · 통과하면 저장하고 끝.
 */
class HotkeyRecorder(private val settings: DesktopSettingsStore) {
    var lastRejection: HotkeyPolicy.Rejection? = null
        private set

    val isRecording: Boolean get() = settings.hotkeyRecording.value

    fun start() {
        if (!settings.hotkey.value.enabled) return
        lastRejection = null
        settings.setHotkeyRecording(true)
    }

    fun stop() {
        lastRejection = null
        settings.setHotkeyRecording(false)
    }

    fun onKey(vk: Int?, ctrl: Boolean, alt: Boolean, shift: Boolean, win: Boolean): HotkeyKeyResult {
        if (!isRecording || vk == null) return HotkeyKeyResult.Ignored
        if (vk == VK_ESCAPE && !ctrl && !alt && !shift && !win) {
            stop()
            return HotkeyKeyResult.Cancelled
        }
        if (vk in PURE_MODIFIERS) return HotkeyKeyResult.Ignored
        val chord = HotkeyChord(ctrl = ctrl, alt = alt, shift = shift, win = win, keyCode = vk)
        return when (val verdict = HotkeyPolicy.validate(chord)) {
            HotkeyPolicy.Verdict.Ok -> {
                if (!settings.setHotkey(chord)) return HotkeyKeyResult.Ignored
                stop()
                HotkeyKeyResult.Saved(chord)
            }
            is HotkeyPolicy.Verdict.Rejected -> {
                lastRejection = verdict.reason
                HotkeyKeyResult.Rejected(verdict.reason)
            }
        }
    }

    companion object {
        const val VK_ESCAPE = 0x1B
        /** 누르고 있는 동안 조합을 만드는 키(Shift·Ctrl·Alt 좌우 · Win). CapsLock 은 여기 없다 — 정책이 KEY_IS_MODIFIER 로 거절한다. */
        private val PURE_MODIFIERS = setOf(0x10, 0x11, 0x12, 0xA0, 0xA1, 0xA2, 0xA3, 0xA4, 0xA5, 0x5B, 0x5C)
    }
}
