// 원본: Sources/check/CheckApp.swift:222-241 @ a63fea2 (로그인 자동 실행 기본 켬 · 사용자가 끈 것은 존중 — 앱 토글 = 설정 값,
//       시스템에서 끈 것 = SMAppService .requiresApproval → 되살리지 않는다) · W-13 #6(MSIX 는 StartupTask, 끄면 StartupTask 끔 —
//       Run 키 안 씀, pfn 가드 유지) · 설계 D§5-5 · 매니페스트 desktopApp/packaging/AppxManifest.template.xml(TaskId="AingCheck", Enabled="true")
//
// Windows.ApplicationModel.StartupTask(WinRT)를 JNA 로 부른다: RoGetActivationFactory → IStartupTaskStatics.GetAsync(taskId) →
// IStartupTask.State / RequestEnableAsync / Disable. 비동기 결과는 IAsyncInfo.Status 를 짧게 돌려 본다(완료 콜백 COM 객체를 짓지 않는다).
// 상태값(StartupTaskState): Disabled 0 · DisabledByUser 1 · Enabled 2 · DisabledByPolicy 3 · EnabledByPolicy 4.
// 사용자가 작업 관리자·설정에서 끈 것(1)은 RequestEnableAsync 도 되살리지 못한다(Windows 규칙) — BLOCKED_BY_SYSTEM 으로 안내만.
// 실제 패키지 실행 대조는 VM 몫(러너는 패키지 신원이 없어 GetAsync 가 실패한다 → isEnabled 가 던지고 바인딩이 FAILED 로 본다).
package com.yehsung.aingcheck.desktop.platform.windows.login

import com.sun.jna.Function
import com.sun.jna.Library
import com.sun.jna.Native
import com.sun.jna.Pointer
import com.sun.jna.WString
import com.sun.jna.platform.win32.Guid
import com.sun.jna.ptr.IntByReference
import com.sun.jna.ptr.PointerByReference
import com.yehsung.aingcheck.core.foundation.platform.desktop.LoginItem

/** StartupTask 한 개에 대한 최소 문(시험은 가짜로 바꾼다). 값은 StartupTaskState 정수. */
interface StartupTaskPort {
    /** 지금 상태. 못 읽으면 던진다. */
    fun state(): Int
    /** RequestEnableAsync 의 결과 상태. */
    fun requestEnable(): Int
    fun disable()
}

object StartupTaskState {
    const val DISABLED = 0
    const val DISABLED_BY_USER = 1
    const val ENABLED = 2
    const val DISABLED_BY_POLICY = 3
    const val ENABLED_BY_POLICY = 4

    fun isEnabled(state: Int): Boolean = state == ENABLED || state == ENABLED_BY_POLICY

    /** 앱이 바꿀 수 없는 꺼짐(작업 관리자·그룹 정책) — 되살리지 않고 안내만. */
    fun isBlockedBySystem(state: Int): Boolean = state == DISABLED_BY_USER || state == DISABLED_BY_POLICY
}

/** MSIX 판 로그인 자동 실행. [LoginItem] 계약: setEnabled 는 실제로 바뀌었으면 true. */
class StartupTaskLoginItem(private val port: StartupTaskPort) : LoginItem {
    override fun isEnabled(): Boolean = StartupTaskState.isEnabled(port.state())

    override fun setEnabled(enabled: Boolean): Boolean {
        val before = port.state()
        if (enabled) {
            if (StartupTaskState.isEnabled(before) || StartupTaskState.isBlockedBySystem(before)) return false
            return StartupTaskState.isEnabled(port.requestEnable())
        }
        // 정책으로 켜진 것(4)은 앱이 끌 수 없다.
        if (before != StartupTaskState.ENABLED) return false
        port.disable()
        return !StartupTaskState.isEnabled(port.state())
    }

    /** 작업 관리자 '시작 앱'·정책에서 꺼졌나(LoginItemBinding 의 BLOCKED_BY_SYSTEM). */
    fun userDisabled(): Boolean = StartupTaskState.isBlockedBySystem(port.state())

    companion object {
        /** 매니페스트 `<desktop:StartupTask TaskId="AingCheck">` 와 같은 글자(구조 시험이 템플릿과 대조한다). */
        const val TASK_ID: String = "AingCheck"
    }
}

/** WinRT 실물. 부를 때마다 MTA 로 COM 을 열고(이미 열렸으면 그대로) 쓴 인터페이스는 모두 Release 한다. */
class WinRtStartupTaskPort(private val taskId: String = StartupTaskLoginItem.TASK_ID) : StartupTaskPort {
    @Suppress("FunctionName")
    private interface Combase : Library {
        fun RoInitialize(initType: Int): Int
        fun RoUninitialize()
        fun RoGetActivationFactory(activatableClassId: Pointer, iid: Guid.GUID.ByReference, factory: PointerByReference): Int
        fun WindowsCreateString(source: WString, length: Int, out: PointerByReference): Int
        fun WindowsDeleteString(string: Pointer?): Int

        companion object {
            val INSTANCE: Combase by lazy { Native.load("combase", Combase::class.java) }
        }
    }

    override fun state(): Int = withTask { task -> getInt(task, VT_TASK_GET_STATE) }

    override fun requestEnable(): Int = withTask { task ->
        val op = PointerByReference()
        check(task, VT_TASK_REQUEST_ENABLE_ASYNC, op.pointer, "RequestEnableAsync")
        try {
            awaitCompleted(op.value)
            getInt(op.value, VT_ASYNC_OP_GET_RESULTS)
        } finally {
            release(op.value)
        }
    }

    override fun disable() {
        withTask { task -> check(task, VT_TASK_DISABLE, null, "Disable") }
    }

    private fun <T> withTask(block: (task: Pointer) -> T): T {
        val api = Combase.INSTANCE
        val init = api.RoInitialize(RO_INIT_MULTITHREADED)
        val ownsInit = init == S_OK || init == S_FALSE
        try {
            val statics = PointerByReference()
            withHString(CLASS_ID) { h ->
                hr(api.RoGetActivationFactory(h, Guid.GUID.ByReference(IID_STARTUP_TASK_STATICS), statics), "RoGetActivationFactory")
            }
            try {
                val op = PointerByReference()
                withHString(taskId) { h -> check(statics.value, VT_STATICS_GET_ASYNC, op.pointer, "GetAsync", h) }
                try {
                    awaitCompleted(op.value)
                    val task = PointerByReference()
                    check(op.value, VT_ASYNC_OP_GET_RESULTS, task.pointer, "GetResults")
                    try {
                        return block(task.value)
                    } finally {
                        release(task.value)
                    }
                } finally {
                    release(op.value)
                }
            } finally {
                release(statics.value)
            }
        } finally {
            if (ownsInit) api.RoUninitialize()
        }
    }

    private fun <T> withHString(text: String, block: (Pointer) -> T): T {
        val api = Combase.INSTANCE
        val out = PointerByReference()
        hr(api.WindowsCreateString(WString(text), text.length, out), "WindowsCreateString")
        try {
            return block(out.value)
        } finally {
            api.WindowsDeleteString(out.value)
        }
    }

    /** IAsyncInfo.Status 가 Started 를 벗어날 때까지(상한 [ASYNC_TIMEOUT_MILLIS]). Completed 가 아니면 던진다. */
    private fun awaitCompleted(op: Pointer) {
        val info = PointerByReference()
        // 구조체 그대로 넘긴다 — JNA 가 호출 전에 메모리에 써 준다(.pointer 만 넘기면 빈 IID).
        hr(vcall(op, VT_QUERY_INTERFACE, Guid.GUID.ByReference(IID_ASYNC_INFO), info.pointer), "QueryInterface(IAsyncInfo)")
        try {
            val deadline = System.nanoTime() + ASYNC_TIMEOUT_MILLIS * 1_000_000
            while (true) {
                val status = getInt(info.value, VT_INFO_GET_STATUS)
                if (status == ASYNC_COMPLETED) return
                if (status != ASYNC_STARTED) error("StartupTask 비동기 실패(status=$status)")
                if (System.nanoTime() > deadline) error("StartupTask 비동기 상한 초과")
                Thread.sleep(POLL_MILLIS)
            }
        } finally {
            release(info.value)
        }
    }

    private fun getInt(obj: Pointer, index: Int): Int {
        val out = IntByReference()
        hr(vcall(obj, index, out.pointer), "vtable[$index]")
        return out.value
    }

    private fun check(obj: Pointer, index: Int, out: Pointer?, what: String, vararg leading: Any?) {
        val args = if (out == null) arrayOf(*leading) else arrayOf(*leading, out)
        hr(vcall(obj, index, *args), what)
    }

    private fun release(obj: Pointer?) {
        if (obj != null) runCatching { vcall(obj, VT_RELEASE) }
    }

    private fun vcall(obj: Pointer, index: Int, vararg args: Any?): Int {
        val vtbl = obj.getPointer(0)
        val fn = Function.getFunction(vtbl.getPointer(index.toLong() * Native.POINTER_SIZE), Function.ALT_CONVENTION)
        return fn.invokeInt(arrayOf(obj, *args))
    }

    private fun hr(code: Int, what: String) {
        if (code < 0) error("$what 실패 hr=0x${Integer.toHexString(code)}")
    }

    companion object {
        const val CLASS_ID = "Windows.ApplicationModel.StartupTask"
        /** IStartupTaskStatics. */
        val IID_STARTUP_TASK_STATICS = Guid.GUID("{EE5B60BD-A148-41A7-B26E-E8B88A1E62F8}")
        /** IAsyncInfo. */
        val IID_ASYNC_INFO = Guid.GUID("{00000036-0000-0000-C000-000000000046}")

        private const val RO_INIT_MULTITHREADED = 1
        private const val S_OK = 0
        private const val S_FALSE = 1
        private const val ASYNC_STARTED = 0
        private const val ASYNC_COMPLETED = 1
        private const val ASYNC_TIMEOUT_MILLIS = 5_000L
        private const val POLL_MILLIS = 10L

        // vtable 자리(IUnknown 0-2 · IInspectable 3-5 뒤).
        private const val VT_QUERY_INTERFACE = 0
        private const val VT_RELEASE = 2
        private const val VT_STATICS_GET_ASYNC = 7 // GetForCurrentPackageAsync 6 · GetAsync 7
        private const val VT_ASYNC_OP_GET_RESULTS = 8 // put_Completed 6 · get_Completed 7 · GetResults 8
        private const val VT_INFO_GET_STATUS = 7 // get_Id 6 · get_Status 7
        private const val VT_TASK_REQUEST_ENABLE_ASYNC = 6
        private const val VT_TASK_DISABLE = 7
        private const val VT_TASK_GET_STATE = 8
    }
}
