// 원본: multiplatform/core/rules/…/ailimit/AILimits.kt:229-310(AILimitDevice.baseName · AILimitDeviceRoster.displayNameParts — 맥 이식, '이름 모를 맥')
// 결정: W-13 #8 · W-11(폰 AI 리밋 기기 표기 '기기마다 맥/PC') · W-12 15시(Windows 호칭 'PC' 통일 — AI 리밋 기기 이름 + 근무 출처).
//
// 데스크톱 화면의 기기 낱말: device_id 가 'win:' 로 시작하면 'PC', 그 밖은 '맥'. 종류를 모르는(빈) 자리만 '컴퓨터'.
// 'win:' 은 **소문자만**이다 — 서버 desktop_device_platform 거울(ai_limits.device_id like 'win:%')과 같은 답(W-11 14:4x 모바일).
// 이름 겹침 꼬리 규칙은 코어 그대로(같은 기본 이름이 둘 이상이면 꼬리) — 기본 이름만 기기마다 낱말을 바꾼다.
package com.yehsung.aingcheck.desktop.pages.devices

import com.yehsung.aingcheck.core.rules.ailimit.AILimitDevice
import com.yehsung.aingcheck.core.rules.ailimit.AILimitDeviceNameParts
import com.yehsung.aingcheck.desktop.platform.windows.identity.WindowsDeviceIdentity

object DesktopDeviceWord {
    const val PC = "PC"
    const val MAC = "맥"
    /** 종류를 모르는 자리(빈 id)만. */
    const val UNKNOWN = "컴퓨터"
    /** 접두 글자는 기기 id 를 짓는 상수 한 곳(WindowsDeviceIdentity.DEVICE_ID_PREFIX — DeviceIdSingleSourceTest).*/
    const val WINDOWS_PREFIX = WindowsDeviceIdentity.DEVICE_ID_PREFIX

    fun of(deviceID: String?): String = when {
        deviceID.isNullOrBlank() -> UNKNOWN
        deviceID.trim().startsWith(WINDOWS_PREFIX) -> PC
        else -> MAC
    }
}

object DesktopDeviceNames {
    /** 라벨이 있으면 라벨(사용자가 붙인 이름은 그대로), 없으면 '이름 모를 PC|맥 <꼬리>'. */
    fun baseName(device: AILimitDevice): String =
        device.label?.takeIf { it.isNotEmpty() } ?: "이름 모를 ${DesktopDeviceWord.of(device.deviceID)} ${AILimitDevice.shortTail(device.deviceID)}"

    /** 코어 displayNameParts 와 같은 꼬리 규칙 — 기본 이름만 [baseName]. */
    fun parts(devices: List<AILimitDevice>): Map<String, AILimitDeviceNameParts> {
        val counts = HashMap<String, Int>()
        for (device in devices) counts[baseName(device)] = (counts[baseName(device)] ?: 0) + 1
        val out = LinkedHashMap<String, AILimitDeviceNameParts>()
        for (device in devices) {
            val base = baseName(device)
            out[device.deviceID] = AILimitDeviceNameParts(base, if ((counts[base] ?: 0) > 1) AILimitDevice.shortTail(device.deviceID) else null)
        }
        return out
    }
}
