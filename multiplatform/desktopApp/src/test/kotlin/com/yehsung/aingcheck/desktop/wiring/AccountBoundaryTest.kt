// 계정 경계 감사(int-w4a L-signout) — 맥 Sources/check/WorkTimerStore.swift clearPersistedSession(4028-4350) · adoptWorkStateOwner(4356-4375)
// 가 비우는 계정 묶음 상태의 데스크톱 짝을 **실제 조립 그래프**(AppGraph.assemble + MockEngine `.invalid`)로 잰다:
//   A 로그인 → A 의 상태를 채운다 → (로그아웃 | A → B 직행 전환) → B 의 화면 상태에 A 의 것이 0 · 전환 뒤 A 토큰 요청 0 · 계정 묶음 창은 닫힌다.
// 맥 줄(main @ af712521):
//   메시지 초안 4115 · 차단/신고 clearBlockReportState 4134 · 확성기 작성 megaphone.reset 4224 — 데스크톱 MessagesStore.reset
//   리그 표·보던 주 4054-4060 · 토큰 공개 4141 · 미니게임 순위 행 4270-4283 — RankingsStore.reset
//   별명·캐릭터·뽑기 resetGachaState 4228 · 케이크 resetCakeGiftState 4230 · 회고 배너 4328 · 제보 초안 4314 — MeStore.reset
//   미니게임 토큰 4286-4293 · 공개 4283 · 제출 안내 4305 — GamesStore.reset(miniGames.reset)
//   미니게임 창 close() 4268(★ v0.2.48: 깃발만 내리면 빈 창이 남는다 — 4237-4250) — GamesWiring closeAll(오목·체스·테트리스·뽑기·케이크)
// 일부러 남기는 것(맥과 같게): 미니게임 보기 선택(miniGameBoardScope — "앱 실행의 것" 4277).
// 망은 MockEngine(`.invalid`)뿐 · 픽스처는 합성.
@file:OptIn(ExperimentalCoroutinesApi::class, ExperimentalTime::class)

package com.yehsung.aingcheck.desktop.wiring

import com.yehsung.aingcheck.core.foundation.platform.InstallationIdentity
import com.yehsung.aingcheck.core.foundation.platform.MonotonicClock
import com.yehsung.aingcheck.core.foundation.platform.RunningTests
import com.yehsung.aingcheck.core.foundation.platform.SingleInstanceGuard
import com.yehsung.aingcheck.core.foundation.platform.TokenVault
import com.yehsung.aingcheck.core.foundation.platform.desktop.AppPaths
import com.yehsung.aingcheck.core.foundation.platform.desktop.EnvReader
import com.yehsung.aingcheck.core.foundation.platform.desktop.HotkeyChord
import com.yehsung.aingcheck.core.foundation.platform.desktop.HotkeyRegistrationResult
import com.yehsung.aingcheck.core.foundation.platform.desktop.HotkeyService
import com.yehsung.aingcheck.core.foundation.platform.desktop.LoginItem
import com.yehsung.aingcheck.core.foundation.platform.desktop.PowerEvent
import com.yehsung.aingcheck.core.foundation.platform.desktop.PowerEvents
import com.yehsung.aingcheck.core.foundation.platform.desktop.RasterImage
import com.yehsung.aingcheck.core.foundation.platform.desktop.Registration
import com.yehsung.aingcheck.core.foundation.platform.desktop.TrayClick
import com.yehsung.aingcheck.core.foundation.platform.desktop.TrayHost
import com.yehsung.aingcheck.core.rules.minigame.MiniGameKind
import com.yehsung.aingcheck.core.wire.SupabaseSession
import com.yehsung.aingcheck.core.wire.models.MiniGameBoardScope
import com.yehsung.aingcheck.desktop.AppGraph
import com.yehsung.aingcheck.desktop.AppSeams
import com.yehsung.aingcheck.desktop.AppWirings
import com.yehsung.aingcheck.desktop.DesktopPlatform
import com.yehsung.aingcheck.desktop.SilentCharacterSink
import com.yehsung.aingcheck.core.stores.me.loadCakeGift
import com.yehsung.aingcheck.desktop.overlay.engine.FakeMeasure
import com.yehsung.aingcheck.desktop.pages.desktopsettings.DesktopSettingsKeys
import com.yehsung.aingcheck.desktop.shell.flyout.FlyoutScreen
import com.yehsung.aingcheck.desktop.shell.flyout.SyntheticScreen
import com.yehsung.aingcheck.feature.desktop.DesktopAiHomes
import com.yehsung.aingcheck.feature.desktop.DesktopAppConfig
import com.yehsung.aingcheck.feature.desktop.InMemoryDesktopKeyValueStore
import com.yehsung.aingcheck.feature.desktop.ailimits.AILimitReadOutcome
import com.yehsung.aingcheck.feature.desktop.ailimits.AILimitRunner
import com.yehsung.aingcheck.testkit.vault.InMemoryTokenVault
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.MockEngineConfig
import io.ktor.client.engine.mock.respond
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.http.headersOf
import kotlinx.coroutines.CoroutineExceptionHandler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import java.nio.file.Path
import java.util.concurrent.Executor
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue
import kotlin.time.Clock
import kotlin.time.ExperimentalTime
import kotlin.time.Instant

private class BoundaryPlatform(dataDir: Path) : DesktopPlatform {
    override val paths = object : AppPaths {
        // 시험이 끝나면 TempDataDirs.close 가 안의 todos.*.json·로그째 지운다(deleteOnExit 는 빈 폴더만 — int-w4a polish ⑥).
        override val dataDir: String = dataDir.toString()
        override val cacheDir = "C"; override val logDir = "L"; override val userHome = "H"
    }
    override val env = object : EnvReader { override fun get(name: String): String? = null }
    override val tokenVault: TokenVault = InMemoryTokenVault()
    override val installationIdentity = object : InstallationIdentity {
        override fun installationId(): String = WiringTestRig.INSTALLATION
    }
    override val singleInstance = object : SingleInstanceGuard { override fun tryAcquire() = true; override fun release() {} }
    override val tray = object : TrayHost {
        override fun show(icon: RasterImage, tooltip: String) {}
        override fun update(icon: RasterImage, tooltip: String) {}
        override fun remove() {}
        override fun addClickListener(listener: (click: TrayClick, screenX: Int, screenY: Int) -> Unit) = Registration { }
    }
    override val hotkeys = object : HotkeyService {
        override fun register(chord: HotkeyChord, onPressed: () -> Unit) = HotkeyRegistrationResult.Conflict(0)
    }
    override val idle = FakeIdle()
    override val power = object : PowerEvents {
        override fun addListener(listener: (PowerEvent) -> Unit): Registration = Registration { }
    }
    override val session = FakeSessionEvents()
    override val loginItem: LoginItem? = null
}

private object Accounts {
    const val A = "a0000000-0000-4000-8000-0000000000aa"
    const val B = "b0000000-0000-4000-8000-0000000000bb"
    const val PEER = "d0000000-0000-4000-8000-0000000000ee"
    fun token(user: String) = "tok-$user"
}

/** 앱 한 벌 — 실제 AppGraph 조립(start 포함). 요청은 (누구의 토큰, 경로)로 적는다. */
private class BoundaryRig(test: TestScope, dataDir: Path) {
    data class Sent(val user: String?, val path: String)

    val sent = mutableListOf<Sent>()
    val hosts = mutableSetOf<String>()
    val uncaught = mutableListOf<Throwable>()
    val factory = FakeGameFactory()
    private val engine = MockEngine(
        MockEngineConfig().apply {
            dispatcher = StandardTestDispatcher(test.testScheduler)
            addHandler { request ->
                hosts += request.url.host
                val p = request.url.encodedPath
                val auth = request.headers[HttpHeaders.Authorization].orEmpty()
                val user = listOf(Accounts.A, Accounts.B).firstOrNull { auth.contains(it) }
                sent += Sent(user, p)
                val json = headersOf(HttpHeaders.ContentType, "application/json")
                when {
                    // A 의 팀 리그 한 줄(합성). B 의 몫은 비어 있다 — B 화면에 줄이 보이면 그건 A 의 것이 남은 것이다.
                    p.endsWith("/rpc/team_weekly_leaderboard") && user == Accounts.A ->
                        respond(
                            """[{"team_id":"t-a","team_name":"A 의 팀","weekly_goal_hours":40,"total_seconds":3600,"working_count":1,"member_count":3}]""",
                            HttpStatusCode.OK, json,
                        )
                    p.endsWith("/rpc/team_weekly_leaderboard") -> respond("[]", HttpStatusCode.OK, json)
                    // A 에게 온 케이크 선물(합성 — 딸기·초코). B 의 몫엔 없다.
                    p.endsWith("/rpc/character_gift_pending") && user == Accounts.A ->
                        respond("""{"status":"ok","gift":{"id":"gift-of-a","options":["aing_cake_strawberry","aing_cake_choco"]}}""", HttpStatusCode.OK, json)
                    p.endsWith("/rpc/character_gift_pending") -> respond("""{"status":"none"}""", HttpStatusCode.OK, json)
                    // 미니게임 판 토큰(서버가 소유자를 대조한다 — 맥 4286). A 의 것만 합성.
                    p.endsWith("/rpc/minigame_start_round") && user == Accounts.A ->
                        respond("""{"status":"ok","token":"round-of-a","expires_at":"2099-01-01T00:00:00Z"}""", HttpStatusCode.OK, json)
                    p.endsWith("/rpc/take_pokes") -> respond("[]", HttpStatusCode.OK, json)
                    else -> respond("""{"code":"PGRST202","message":"no fixture"}""", HttpStatusCode.NotFound, json)
                }
            }
        },
    )
    val graph = AppGraph(
        platform = BoundaryPlatform(dataDir),
        clock = object : Clock {
            override fun now(): Instant = Instant.fromEpochMilliseconds(WiringTestRig.BASE_MS + test.testScheduler.currentTime)
        },
        monotonic = object : MonotonicClock {
            override fun elapsedNanos(): Long = test.testScheduler.currentTime * 1_000_000
        },
        desktopConfig = DesktopAppConfig(duels = true),
        backend = AppGraph.Backend("https://probe.invalid", "stub-anon-key"),
        osVersion = "Windows 11",
        httpFactory = { configure -> HttpClient(engine) { configure() } },
    )
    private val job = SupervisorJob()
    val scope = CoroutineScope(test.coroutineContext.minusKey(Job) + job + CoroutineExceptionHandler { _, e -> uncaught += e })
    private val kv = InMemoryDesktopKeyValueStore().apply {
        // 첫 실행 화면을 이미 지난 설치.
        putBoolean(DesktopSettingsKeys.AI_TOOL_DATA_CONSENT, false)
        putBoolean(DesktopSettingsKeys.LAUNCH_AT_LOGIN_USER_TURNED_OFF, false)
    }
    val app: AppWirings = graph.assemble(
        AppSeams(
            events = Executor { it.run() },
            mainDispatcher = StandardTestDispatcher(test.testScheduler),
            window = FakeWindowPort(),
            screen = FlyoutScreen { SyntheticScreen.facts },
            characterSink = SilentCharacterSink(),
            bubbleMeasure = FakeMeasure(),
            gameWindows = factory,
            homes = DesktopAiHomes(Path.of("synthetic-home")) { Path.of("synthetic-home", ".codex") },
            tokenCacheFile = null,
            aiLimitRunner = AILimitRunner { _, _ -> AILimitReadOutcome(emptyMap()) },
            codexAccountRunner = { _ -> awaitCancellation() },
            computeDiagnostics = { _, _ -> null },
            runningTests = object : RunningTests { override val isRunningTests: Boolean = true },
            keyValueStore = kv,
        ),
        scope,
    )

    /** A 가 보던 주로 넘기기 전의 주(= 이번 주). 다음 사람은 이번 주부터 본다(맥 4055). */
    var currentWeekKey: String = ""

    fun signIn(user: String) = app.sessionStore.adoptSignedInSession(
        SupabaseSession(Accounts.token(user), "ref-$user", user),
        "$user@aing.example",
    )

    fun close() {
        app.tetris.reset()
        job.cancel()
    }
}

class AccountBoundaryTest {
    private val dirs = TempDataDirs()

    @AfterTest
    fun cleanupDataDirs() = dirs.close()

    /**
     * A 의 계정 묶음 상태를 채운다 — 화면이 쓰는 공개 문(초안 입력 · 보드 넘기기 · 공개 고르기 · 창 열기)과 서버 응답(합성 픽스처)으로만.
     * 스토어 안쪽 값을 직접 꽂지 않는다(코어가 막아 두기도 했다) — 화면·서버가 채우는 그 길로 채워야 지우는 길도 그 길에서 잰다.
     */
    private suspend fun TestScope.fillA(rig: BoundaryRig) {
        val app = rig.app
        // 메시지(맥 4115 초안 · 4224 확성기 작성 글).
        app.messages.setDraft("A 가 쓰다 만 말", Accounts.PEER)
        app.messages.megaphone.open()
        app.messages.megaphone.setDraft("A 의 확성기 글")
        // 순위(맥 4054-4060 리그 표·보던 주 · 4141 토큰 공개).
        app.rankings.loadLeague()
        runCurrent()
        rig.currentWeekKey = app.rankings.leagueWeekKey
        app.rankings.stepLeagueWeek(-1)
        app.rankings.noteTokenUsagePublic(false)
        runCurrent()
        // 나(맥 4230 케이크 선물 · 4314 제보 초안 · 4233 별명 초안).
        app.me.loadCakeGift()
        runCurrent()
        app.me.feedbackDraft = "A 가 쓰던 제보"
        app.me.displayNameDraft = "A 의 새 별명"
        // 미니게임(맥 4286-4293 판 토큰) — 보기 선택은 앱 실행의 것(4277 — 남긴다).
        val mini = app.gamesStore.miniGames
        mini.prefetchRoundToken(MiniGameKind.timingBar)
        runCurrent()
        mini.selectBoardScope(MiniGameBoardScope.allTime)
        runCurrent()
        // 게임 탭 화면 깃발(폰 games.reset).
        app.gamesStore.tetrisScreenDidAppear()
        // 루비 미러(폰 sessionDidSignOut `ruby.rubyBalance = null` · 맥 gomoku.reset 의 루비 미러).
        app.ruby.rubyBalance = 97
        // 계정 묶음 창(맥 4268 close()): 뽑기·케이크를 연 채로.
        app.games.handle.windows.openGacha()
        app.games.handle.windows.openCakeGift()
        runCurrent()
        val before = leftovers(rig)
        assertEquals(EXPECTED, before.map { it.substringBefore('=') }.toSet(), "전제: A 의 상태가 다 서 있다 — $before")
    }

    /** 다음 사람에게 남으면 안 되는 A 의 것(항목 이름 = 왼쪽 열). */
    private fun leftovers(rig: BoundaryRig): List<String> = buildList {
        val app = rig.app
        if (app.messages.drafts.values.any { it.isNotEmpty() }) add("messages.drafts=${app.messages.drafts}")
        if (app.messages.megaphone.isComposerOpen || app.messages.megaphone.draft.isNotEmpty()) add("messages.megaphone")
        if (app.rankings.league.isNotEmpty()) add("rankings.league=${app.rankings.league.map { it.name }}")
        if (app.rankings.leagueWeekKey != rig.currentWeekKey) add("rankings.leagueWeekKey=${app.rankings.leagueWeekKey}")
        if (app.rankings.myTokenUsagePublic != null) add("rankings.myTokenUsagePublic")
        if (app.me.cakeGift != null) add("me.cakeGift=${app.me.cakeGift?.id}")
        if (app.me.feedbackDraft.isNotEmpty()) add("me.feedbackDraft")
        if (app.me.displayNameDraft.isNotEmpty()) add("me.displayNameDraft")
        if (app.gamesStore.miniGames.hasUsableRoundToken(MiniGameKind.timingBar)) add("miniGames.roundToken")
        if (app.gamesStore.isTetrisScreenVisible) add("games.tetrisScreen")
        if (app.ruby.rubyBalance != null) add("ruby=${app.ruby.rubyBalance}")
        if (rig.factory.gachaOpens > rig.factory.gachaCloses) add("window.gacha")
        if (rig.factory.cakeOpens > rig.factory.cakeCloses) add("window.cake")
    }

    private val EXPECTED = setOf(
        "messages.drafts", "messages.megaphone",
        "rankings.league", "rankings.leagueWeekKey", "rankings.myTokenUsagePublic",
        "me.cakeGift", "me.feedbackDraft", "me.displayNameDraft",
        "miniGames.roundToken", "games.tetrisScreen", "ruby",
        "window.gacha", "window.cake",
    )

    private suspend fun TestScope.startedWithA(): BoundaryRig {
        val rig = BoundaryRig(this, dirs.new("boundary-data"))
        rig.app.start()
        runCurrent()
        rig.signIn(Accounts.A)
        runCurrent()
        fillA(rig)
        return rig
    }

    private fun assertKeptLikeMac(rig: BoundaryRig) {
        // 맥 4277: 보기 선택(miniGameBoardScope)은 앱 실행의 것이라 그대로 둔다.
        assertEquals(MiniGameBoardScope.allTime, rig.app.gamesStore.miniGames.boardScope, "미니게임 보기 선택까지 걷었다(맥은 남긴다)")
        assertTrue(rig.factory.board.closeAlls >= 1, "계정 묶음 창(미니게임·오목·체스·테트리스)을 닫지 않았다 — 깃발만 내리면 빈 창이 남는다(맥 4237-4250)")
        assertTrue(rig.hosts.all { it == "probe.invalid" }, "망은 MockEngine 의 .invalid 만: ${rig.hosts}")
        assertTrue(rig.uncaught.isEmpty(), "잡히지 않은 예외: ${rig.uncaught}")
    }

    /** A → B 직행 전환(맥 adoptWorkStateOwner 4356-4375 + 로그아웃 경로): B 의 화면에 A 의 것 0 · 전환 뒤 A 토큰 요청 0. */
    @Test
    fun accountSwitchLeavesNothingOfThePreviousPerson() = runTest {
        val rig = startedWithA()
        try {
            val mark = rig.sent.size
            rig.signIn(Accounts.B)
            advanceTimeBy(5_000)
            runCurrent()
            assertEquals(Accounts.B, rig.app.sessionStore.session?.userID, "전제: B 로 바뀌었다")
            val left = leftovers(rig)
            assertTrue(left.isEmpty(), "계정 전환 뒤 앞 사람(A)의 것이 B 에게 남았다: $left")
            val aAfter = rig.sent.drop(mark).filter { it.user == Accounts.A }
            assertTrue(aAfter.isEmpty(), "전환 뒤 A 의 토큰으로 요청이 나갔다: $aAfter")
            // B 가 리그를 다시 읽어도 A 의 줄은 안 돌아온다(B 의 몫은 비어 있다).
            rig.app.rankings.loadLeague()
            runCurrent()
            assertTrue(rig.app.rankings.league.isEmpty(), "B 의 리그에 A 의 줄: ${rig.app.rankings.league}")
            assertKeptLikeMac(rig)
        } finally {
            rig.close()
        }
    }

    /** 로그아웃(맥 clearPersistedSession 4028-4350): 같은 목록이 0. */
    @Test
    fun signOutLeavesNothingOfThePreviousPerson() = runTest {
        val rig = startedWithA()
        try {
            val mark = rig.sent.size
            rig.scope.launch { rig.app.sessionStore.signOut() }
            advanceTimeBy(5_000)
            runCurrent()
            assertNull(rig.app.sessionStore.session, "전제: 로그아웃했다")
            val left = leftovers(rig)
            assertTrue(left.isEmpty(), "로그아웃 뒤 앞 사람의 것이 남았다: $left")
            // 로그아웃 자체의 정리(SessionStore.kt:325 — unregister_device → logout?scope=local) 말고는 A 의 토큰으로 새 일을 벌이지 않는다.
            val aAfter = rig.sent.drop(mark).filter { it.user == Accounts.A && !it.path.endsWith("/rpc/unregister_device") && !it.path.contains("/auth/v1/logout") }
            assertTrue(aAfter.isEmpty(), "로그아웃 뒤 A 의 토큰으로 요청이 나갔다: $aAfter")
            assertKeptLikeMac(rig)
        } finally {
            rig.close()
        }
    }
}
