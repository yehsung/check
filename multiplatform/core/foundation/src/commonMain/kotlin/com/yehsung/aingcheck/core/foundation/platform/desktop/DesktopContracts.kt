// 원본: D§2-1 인터페이스 목록 · CheckWorkNudge.swift:41-56(입력·시계·세션 판정이 전부 주입) @ a63fea2
// K3 데스크톱 플랫폼 인터페이스 — W0-a 는 **서명만** 정한다. Windows 구현은 desktopApp/platform/windows(W1-f, JNA),
// 시험은 가짜 구현으로 맥 JVM 에서 돈다. android 대상에서도 컴파일되지만 androidApp 은 쓰지 않는다.
package com.yehsung.aingcheck.core.foundation.platform.desktop

import kotlin.time.Duration
import kotlin.time.Instant

/** 해제 손잡이(리스너·등록을 거둘 때). */
fun interface Registration {
    fun close()
}

/** 입력 종류. 자리 비움·자동 근무 시작 판정은 **이동만**을 입력으로 치지 않는다(D-E05, §8-7 넛지). */
enum class InputKind { KEY, CLICK, WHEEL, MOVE }

/** 전역 입력 시각(내용은 보지 않는다 — 시각만). Windows 는 Raw Input(RIDEV_INPUTSINK). */
interface IdleSource {
    /** 주어진 종류 중 가장 최근 입력 시각. 아직 없으면 null. */
    fun lastInput(kinds: Set<InputKind>): Instant?
    fun addListener(listener: (kind: InputKind, at: Instant) -> Unit): Registration
}

enum class PowerEvent { SLEEP, WAKE }

/** 잠자기·깨어남(JDK SystemSleepListener 또는 WM_POWERBROADCAST, D§2-3). */
interface PowerEvents {
    fun addListener(listener: (PowerEvent) -> Unit): Registration
}

enum class SessionEvent { LOCK, UNLOCK, CONSOLE_CONNECT, CONSOLE_DISCONNECT, REMOTE_CONNECT, REMOTE_DISCONNECT, LOGOFF }

/** 화면 잠금·사용자 전환·로그오프(JDK UserSessionListener + shutdown hook, D§2-3). */
interface SessionEvents {
    fun addListener(listener: (SessionEvent) -> Unit): Registration
}

/** 전역 단축키 조합. 기본값은 Ctrl+Alt+Shift+Space(§5-4). */
data class HotkeyChord(val ctrl: Boolean, val alt: Boolean, val shift: Boolean, val win: Boolean, val keyCode: Int)

sealed interface HotkeyRegistrationResult {
    data class Registered(val registration: Registration) : HotkeyRegistrationResult
    /** 다른 앱·시스템과 겹쳐 등록이 거절됐다(Win32 오류 코드). */
    data class Conflict(val systemErrorCode: Int) : HotkeyRegistrationResult
}

interface HotkeyService {
    fun register(chord: HotkeyChord, onPressed: () -> Unit): HotkeyRegistrationResult
}

/** 래스터 한 장(ARGB, 줄 우선). 트레이 아이콘·오버레이 프레임이 같이 쓴다. */
class RasterImage(val width: Int, val height: Int, val argb: IntArray) {
    init {
        require(width > 0 && height > 0 && argb.size == width * height) { "크기와 픽셀 수가 맞지 않는다" }
    }
}

enum class TrayClick { PRIMARY, SECONDARY, DOUBLE }

/** 알림 영역 아이콘(Shell_NotifyIcon). Explorer 재시작(TaskbarCreated) 뒤 다시 붙는 책임은 구현에 있다(D§2-2). */
interface TrayHost {
    fun show(icon: RasterImage, tooltip: String)
    fun update(icon: RasterImage, tooltip: String)
    fun remove()
    /** 클릭 위치는 화면 좌표(물리 픽셀). 플라이아웃 배치는 순수 함수가 한다(W1-f). */
    fun addClickListener(listener: (click: TrayClick, screenX: Int, screenY: Int) -> Unit): Registration
}

data class DesktopNotification(val id: String, val title: String, val body: String, val deepLink: String?)

/** OS 알림(토스트/풍선). 같은 사건은 한 표면에만(중재 함수는 W3-c1, §8-3). */
interface Notifier {
    /** 실제로 띄웠으면 true(권한·집중 지원 등으로 못 띄우면 false). */
    fun notify(notification: DesktopNotification): Boolean
    fun addActivationListener(listener: (notificationId: String) -> Unit): Registration
}

/** 레이어드 창 표면(K10: 재생기가 그린 래스터를 UpdateLayeredWindow 로 올린다, D§9-1). */
interface OverlaySurface {
    fun present(frame: RasterImage, screenX: Int, screenY: Int)
    /** 알파 0 픽셀은 클릭 통과. 이 표면 전체를 통과로 둘지. */
    fun setClickThrough(enabled: Boolean)
    fun hide()
}

enum class ProcessStdin { NULL_DEVICE, CLOSED }

data class ProcessResult(val exitCode: Int?, val stdout: String, val stderr: String, val timedOut: Boolean)

/**
 * 자식 프로세스 실행기. 표준 입출력을 상속하지 않는다 — 상속하면 CREATE_NO_WINDOW 가 빠져 콘솔 창이 번쩍인다(D§2-4).
 * `codex app-server` 는 NUL 입력으로 띄운다(D-E19, 기억 codex-exec-stdin-trap).
 */
interface ProcessRunner {
    suspend fun run(
        command: List<String>,
        stdin: ProcessStdin = ProcessStdin.NULL_DEVICE,
        timeout: Duration,
        environment: Map<String, String> = emptyMap(),
    ): ProcessResult
}

/** 환경 변수 읽기(CLAUDE_CONFIG_DIR·CODEX_HOME 등). 시험은 가짜 표를 준다(홈 격리). */
interface EnvReader {
    operator fun get(name: String): String?
}

/** 저장 위치. Windows 는 %LOCALAPPDATA%\aing-check\(로밍 아님, D§2-5). 경로는 OS 표기 문자열이다. */
interface AppPaths {
    val dataDir: String
    val cacheDir: String
    val logDir: String
    val userHome: String
}

/** 로그인 시 자동 실행(맥 A8). MSIX 는 StartupTask, MSI 는 Run 키(D§5-5). */
interface LoginItem {
    fun isEnabled(): Boolean
    /** 실제로 바뀌었으면 true. */
    fun setEnabled(enabled: Boolean): Boolean
}
