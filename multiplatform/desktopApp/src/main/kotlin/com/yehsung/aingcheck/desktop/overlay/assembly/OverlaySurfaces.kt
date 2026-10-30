// 원본: 없음(조립) — W5-b2 coordinator_patches P3(WindowsOverlaySurface · OverlayCompositor · CharacterPlayerSink · OverlayPlacementStore ·
//       WindowsMonitors) · W5-b3 P3(TodoBoardController 를 BoardHost 로) · W-9 #1 W5-b4 · 맥 CheckOverlayWindow.swift :2211-2250 makePanel
//
// 오버레이의 **화면 쪽 한 벌**을 만든다: 캐릭터 문(구운 아잉이 재생기) · 발표자(FrameIntent → 픽셀 자리 → 레이어드 창) · 할 일 보드(외양 포함).
// Windows 밖(맥 개발 실행 · 시험 JVM)은 [OverlaySurfaces.None] — 엔진은 그대로 돌고 화면엔 아무것도 없다(AppGraph SilentCharacterSink 와 같은 뜻).
package com.yehsung.aingcheck.desktop.overlay.assembly

import com.yehsung.aingcheck.character.bake.BakeFiles
import com.yehsung.aingcheck.character.bake.BakeLibrary
import com.yehsung.aingcheck.character.bake.BakedFinish
import com.yehsung.aingcheck.character.player.CharacterPlayer
import com.yehsung.aingcheck.character.render.BakeImageStore
import com.yehsung.aingcheck.character.render.PlatformRaster
import com.yehsung.aingcheck.character.render.RasterFactory
import com.yehsung.aingcheck.core.stores.now.todo.TodoListStore
import com.yehsung.aingcheck.desktop.SilentCharacterSink
import com.yehsung.aingcheck.desktop.overlay.bubble.PretendardBubbleMeasure
import com.yehsung.aingcheck.desktop.overlay.engine.BoardHost
import com.yehsung.aingcheck.desktop.overlay.engine.CharacterSink
import com.yehsung.aingcheck.desktop.overlay.engine.MonitorInfo
import com.yehsung.aingcheck.desktop.overlay.engine.OverlayInputs
import com.yehsung.aingcheck.desktop.overlay.engine.PointerOutcome
import com.yehsung.aingcheck.desktop.overlay.render.CharacterLayer
import com.yehsung.aingcheck.desktop.overlay.render.CharacterPlayerSink
import com.yehsung.aingcheck.desktop.overlay.render.ComposedOverlay
import com.yehsung.aingcheck.desktop.overlay.render.OverlayCompositor
import com.yehsung.aingcheck.desktop.overlay.render.PlayerCharacterLayer
import com.yehsung.aingcheck.desktop.overlay.surface.OverlayPlacementStore
import com.yehsung.aingcheck.desktop.overlay.surface.OverlaySurfaceListener
import com.yehsung.aingcheck.desktop.overlay.surface.WindowsMonitors
import com.yehsung.aingcheck.desktop.overlay.surface.WindowsOverlaySurface
import com.yehsung.aingcheck.desktop.overlay.todoboard.BoardTimer
import com.yehsung.aingcheck.desktop.overlay.todoboard.SwingBoardTimer
import com.yehsung.aingcheck.desktop.overlay.todoboard.TodoBoardAppearanceStore
import com.yehsung.aingcheck.desktop.overlay.todoboard.TodoBoardController
import com.yehsung.aingcheck.desktop.overlay.todoboard.TodoBoardRoot
import com.yehsung.aingcheck.desktop.overlay.todoboard.TodoBoardSurface
import com.yehsung.aingcheck.desktop.overlay.todoboard.TodoBoardWindow
import com.yehsung.aingcheck.desktop.platform.windows.HostOs
import com.yehsung.aingcheck.desktop.platform.windows.WindowsPlatform
import com.yehsung.aingcheck.desktop.platform.windows.msg.Win32MessageThread
import com.yehsung.aingcheck.desktop.wiring.OverlayPresenter
import com.yehsung.aingcheck.feature.desktop.DesktopKeyValueStore
import java.io.File

/** 굽기 뿌리 폴더를 그대로 읽는 [BakeFiles](앱 자원 `aing-bake/` · 후광은 `aing-bake/halo/` — Android 자산과 같은 배치). */
class DirectoryBakeFiles(private val root: File, private val haloDir: File = File(root, HALO_DIR)) : BakeFiles {
    override fun read(path: String): ByteArray? = safe(root, path)?.takeIf { it.isFile }?.readBytes()
    override fun readHalo(fileName: String): ByteArray? = safe(haloDir, fileName)?.takeIf { it.isFile }?.readBytes()

    /** 뿌리 밖으로 나가는 경로(..)는 없는 것으로. */
    private fun safe(base: File, rel: String): File? {
        val f = File(base, rel).canonicalFile
        return f.takeIf { it.path.startsWith(base.canonicalFile.path + File.separator) }
    }

    companion object {
        const val HALO_DIR = "halo"
    }
}

/** 구운 아잉이 재생기 한 벌 — 엔진 문([sink])과 그리기 층([layer])이 **같은 플레이어**를 본다. 엔진 실행기 한 줄에서만. */
class BakedCharacter(
    val library: BakeLibrary,
    initialCharacterId: String? = null,
    private val raster: RasterFactory = PlatformRaster,
) : AutoCloseable {
    /** 스프라이트 캐릭터(fox · shiba …) 아틀라스는 아직 앱 자원에 없다 — 플레이어가 아잉으로 접는다(unresolved). */
    val player = CharacterPlayer(library, spriteFor = { null }, initialCharacterId = initialCharacterId)
    val sink: CharacterSink = CharacterPlayerSink(player)
    private val stores = HashMap<BakedFinish, BakeImageStore>()
    val layer: CharacterLayer = PlayerCharacterLayer(player, { f -> stores.getOrPut(f) { BakeImageStore(f, library.files, raster) } }, { null })

    override fun close() {
        stores.values.forEach { runCatching { it.close() } }
        stores.clear()
    }

    companion object {
        /** 뿌리가 없거나 묶음이 깨졌으면 null(앱은 그리지 않는 자리로 — 엔진 판정·서버 호출은 같다). */
        fun loadOrNull(root: File?, initialCharacterId: String? = null): BakedCharacter? {
            if (root == null || !File(root, "camera.json").isFile) return null
            return runCatching { BakedCharacter(BakeLibrary.load(DirectoryBakeFiles(root)), initialCharacterId) }.getOrNull()
        }

        /** Compose 앱 자원 폴더(`compose.application.resources.dir`)의 `aing-bake/` — 조정자 P2 가 싣는다. */
        fun defaultRoot(): File? = System.getProperty("compose.application.resources.dir")?.let { File(it, "aing-bake") }
    }
}

/** [WindowsOverlaySurface] → [OverlaySurfacePort]. */
class WindowsSurfacePort(val surface: WindowsOverlaySurface) : OverlaySurfacePort {
    override fun monitors(): List<MonitorInfo> = runCatching { WindowsMonitors.list() }.getOrDefault(emptyList())
    override fun dpiScale(): Double = surface.dpiScale()
    override fun present(frame: ComposedOverlay, xPx: Int, yPx: Int): Boolean = surface.present(frame, xPx, yPx).ok
    override fun moveTo(xPx: Int, yPx: Int) = surface.moveTo(xPx, yPx)
    override fun hide() = surface.hide()
    override fun setClickThrough(enabled: Boolean) { surface.setClickThrough(enabled) }
    override fun close() = surface.close()
}

/** [OverlaySurfaces.create] 가 받는 것(AppGraph 가 가진 값 그대로). */
data class OverlaySurfacesConfig(
    val keyValueStore: DesktopKeyValueStore,
    /** 할 일 목록 스토어. 없으면 보드 없음(BoardHost.None — 클릭은 때리기). */
    val todoStore: TodoListStore? = null,
    /** 설정의 할 일 켜짐(맥 isTodoEnabled — W-9 #3 DesktopSettingsStore.todoBoard). */
    val boardEnabled: () -> Boolean = { true },
    /** 보드를 열 때(맥 v0.3.30 서버와 맞춤 — TodoSync 새로 고침). */
    val onBoardOpened: (() -> Unit)? = null,
    /** 굽기 뿌리. 기본 = 앱 자원 `aing-bake/`. */
    val bakeRoot: File? = BakedCharacter.defaultRoot(),
    /** 착용 캐릭터(서버 id). null = 아잉. */
    val initialCharacterId: String? = null,
)

/**
 * 오버레이 화면 쪽 한 벌. [sink]·[presenter]·[board] 를 OverlayWiringDeps 에 넣고, 배선을 만든 뒤 [bind] 로 엔진·포인터를 잇는다.
 * [presenter]·[onPointerOutcome] 은 엔진 실행기(OverlayWiring 소비 코루틴, Swing Main)에서만 불린다.
 */
class OverlaySurfaces internal constructor(
    val sink: CharacterSink,
    val presenter: OverlayPresenter,
    val board: BoardHost,
    val boardAppearance: TodoBoardAppearanceStore?,
    /** 실물 발표자(Windows 에서만). */
    val surfacePresenter: OverlaySurfacePresenter?,
    private val pointerRelay: PointerRelay?,
    private val closer: () -> Unit,
) : AutoCloseable {
    /** 화면에 실제로 그리는가(Windows + 창 생성 성공). */
    val isLive: Boolean get() = surfacePresenter != null

    /** 배선 뒤 한 번: 엔진 되먹이기(onMonitors·onSurfaceFrame) + 창 포인터 → 배선. */
    fun bind(director: OverlayInputs, pointer: OverlaySurfaceListener) {
        surfacePresenter?.bind(director)
        pointerRelay?.target = pointer
    }

    /** OverlayWiringDeps.onPointerOutcome 에서 먼저 부른다(끌기 = 창 옮기기). */
    fun onPointerOutcome(outcome: PointerOutcome) {
        surfacePresenter?.onPointerOutcome(outcome)
    }

    /** WM_DISPLAYCHANGE·배율 변경 때. */
    fun onDisplayChanged() {
        surfacePresenter?.invalidateMonitors()
    }

    override fun close() = closer()

    /** 창 메시지 스레드의 포인터를 배선이 만들어진 뒤에 잇는 중계(bind 전 포인터는 버린다). */
    internal class PointerRelay : OverlaySurfaceListener {
        @Volatile var target: OverlaySurfaceListener? = null
        override fun onPointer(kind: com.yehsung.aingcheck.desktop.overlay.engine.PointerKind, ptDip: com.yehsung.aingcheck.desktop.overlay.engine.OverlayPoint, target: com.yehsung.aingcheck.desktop.overlay.engine.HitTarget) {
            this.target?.onPointer(kind, ptDip, target)
        }
    }

    companion object {
        /** 화면 없음(맥 개발 실행 · 시험). 보드도 없다. */
        fun none(): OverlaySurfaces = OverlaySurfaces(SilentCharacterSink(), OverlayPresenter.None, BoardHost.None, null, null, null) {}

        /**
         * [isWindows] 가 아니면 [none]. Windows 면 [thread] 위 레이어드 창 · 구운 재생기(뿌리가 없으면 그리지 않는 자리) · 보드(스토어가 있으면).
         * 창 생성이 실패하면(세션 0 등) 화면 없음으로 내려간다 — 엔진은 그대로.
         */
        fun create(
            platform: WindowsPlatform?,
            config: OverlaySurfacesConfig,
            isWindows: Boolean = HostOs.isWindows(),
        ): OverlaySurfaces = createOn(if (isWindows) platform?.messageThread else null, config, isWindows)

        /** [create] 의 몸통 — 러너 시험은 자기 메시지 스레드로 부른다. */
        fun createOn(
            thread: Win32MessageThread?,
            config: OverlaySurfacesConfig,
            isWindows: Boolean = HostOs.isWindows(),
        ): OverlaySurfaces {
            if (!isWindows || thread == null) return none()
            val relay = PointerRelay()
            val surface = runCatching { WindowsOverlaySurface(thread, listener = relay) }.getOrNull() ?: return none()
            val character = BakedCharacter.loadOrNull(config.bakeRoot, config.initialCharacterId)
            val compositor = OverlayCompositor(PretendardBubbleMeasure.bundled)
            val placements = OverlayPlacementStore(config.keyValueStore)
            val presenter = OverlaySurfacePresenter(
                WindowsSurfacePort(surface),
                { view, w, h, scale, now -> compositor.compose(view, w, h, scale, now, character?.layer) },
                placements::load,
            )
            val appearance = TodoBoardAppearanceStore(config.keyValueStore)
            val (board, window) = buildBoard(config, appearance)
            return OverlaySurfaces(
                sink = character?.sink ?: SilentCharacterSink(),
                presenter = presenter,
                board = board,
                boardAppearance = appearance,
                surfacePresenter = presenter,
                pointerRelay = relay,
            ) {
                window?.let { w -> runCatching { javax.swing.SwingUtilities.invokeLater { w.dispose() } } }
                surface.close()
                compositor.close()
                character?.close()
            }
        }

        /** W5-b3 P3 그대로 + 외양(투명 · 어두움 고정 · 진하기). 보드 창은 EDT 에서 처음 열릴 때 만들어진다. */
        internal fun buildBoard(config: OverlaySurfacesConfig, appearance: TodoBoardAppearanceStore): Pair<BoardHost, TodoBoardWindow?> {
            val store = config.todoStore ?: return BoardHost.None to null
            lateinit var controller: TodoBoardController
            val window = TodoBoardWindow(
                content = { TodoBoardRoot(controller, appearanceStore = appearance) },
                onDeactivated = { controller.onDeactivated() },
                translucent = true,
            )
            controller = boardController(config, store, window)
            return controller to window
        }

        /**
         * 보드 판정 한 곳(창과 무관 — 시험은 가짜 표면): 설정 켜짐([OverlaySurfacesConfig.boardEnabled])이면 캐릭터 클릭이 보드,
         * 꺼짐이면 엔진이 콕 반응(때리기)으로 돌린다(맥 CheckApp.swift:617-622 `guard …, isTodoEnabled() else { return false }`).
         * 닫혀 있다 열린 순간에만 [OverlaySurfacesConfig.onBoardOpened](맥 TodoSyncCoordinator.swift:49 `board?.onOpened = { sync.requestSync(.boardOpened) }`).
         */
        internal fun boardController(
            config: OverlaySurfacesConfig,
            store: TodoListStore,
            surface: TodoBoardSurface,
            timer: BoardTimer = SwingBoardTimer,
        ): TodoBoardController =
            TodoBoardController(store, surface, timer, enabled = config.boardEnabled).also { it.onOpened = config.onBoardOpened }
    }
}
