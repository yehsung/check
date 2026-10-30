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
// int-w4b(L-acct): 늦은 응답(전환 전에 떠난 A 의 요청을 붙잡았다 전환 뒤 풀기 — 리그·케이크·판 토큰·지갑) · 토큰 업로드 장부·내 행(4072-4088,
//   깃발 tokenUpload 를 켠 그래프) · A → B 직행 뒤 B 의 안 읽음 요약 · 센터(4145)·상태메시지(4149)·버전 도장(4140 — 데스크톱은 기기 등록 서명).
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
import com.yehsung.aingcheck.core.stores.me.loadStatusMessage
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.models.TokenUsageDayKey
import com.yehsung.aingcheck.core.wire.models.TokenUsageMonthKey
import com.yehsung.aingcheck.feature.desktop.socialapi.UltraSyncReason
import com.yehsung.aingcheck.feature.desktop.work.WorkStartOrigin
import com.yehsung.aingcheck.feature.desktop.tokens.TokenUsageMonthly
import com.yehsung.aingcheck.feature.desktop.tokens.upload.TokenUploadCoordinator
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
import io.ktor.http.content.OutgoingContent
import io.ktor.http.content.TextContent
import kotlinx.coroutines.CompletableDeferred
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
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
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
    const val PEER_OF_B = "e0000000-0000-4000-8000-0000000000ff"
    fun token(user: String) = "tok-$user"
}

/** 앱 한 벌 — 실제 AppGraph 조립(start 포함). 요청은 (누구의 토큰, 경로)로 적는다. */
private class BoundaryRig(
    test: TestScope,
    dataDir: Path,
    config: DesktopAppConfig = DesktopAppConfig(duels = true),
    /** AI 도구 기록 동의(W-13 #5) — 업로드 조정자의 수집 게이트가 서버 설정과 **함께** 본다. 토큰 업로드 시험만 켠다. */
    aiConsent: Boolean = false,
) {
    data class Sent(val user: String?, val path: String)
    data class Wire(val user: String?, val url: String, val body: String)

    val sent = mutableListOf<Sent>()
    /** 본문까지 적은 요청(늦은 응답·업로드 본문 시험). */
    val wires = mutableListOf<Wire>()
    /** 참이면 A 의 [gated] 경로 요청을 [gate] 가 풀릴 때까지 붙잡는다 — 전환 **뒤에** A 의 응답을 늦게 떨어뜨린다. */
    var gateArmed = false
    var gated = listOf("/rpc/team_weekly_leaderboard", "/rpc/character_gift_pending", "/rpc/minigame_start_round")
    val gate = CompletableDeferred<Unit>()
    val held = mutableListOf<String>()
    /** 서버 수집 설정(profiles.token_usage_collect) 픽스처 — 토큰 업로드 시험만 켠다(다른 시험의 공개 설정 판정에 끼지 않게). */
    var tokenCollect = false
    /** 참이면 B 의 첫 기기 등록(로그인 때)만 500 — 버전 도장 시험이 포그라운드 재등록 길을 잰다. */
    var failFirstBRegister = false
    var bRegisters = 0
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
                val bodyText = when (val b = request.body) {
                    is TextContent -> b.text
                    is OutgoingContent.ByteArrayContent -> b.bytes().decodeToString()
                    else -> ""
                }
                wires += Wire(user, request.url.toString(), bodyText)
                if (gateArmed && user == Accounts.A && gated.any { p.endsWith(it) }) { held += p; gate.await() }
                val json = headersOf(HttpHeaders.ContentType, "application/json")
                val select = request.url.parameters["select"].orEmpty()
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
                    // 울트라 지갑(합성 잔량 777 — A 의 것).
                    p.endsWith("/rpc/ultra_wallet_sync") && user == Accounts.A ->
                        respond("""{"status":"ok","balance":777,"day":"2026-10-30"}""", HttpStatusCode.OK, json)
                    // A 의 울트라 발신 성공(합성 잔량 4)·울트라 구매 성공(합성 울트라 9 · 루비 31) — 늦은 응답 시험(int-w4b 반박 검증 P5).
                    p.endsWith("/rpc/ultra_poke_user") && user == Accounts.A ->
                        respond("""{"status":"ok","ultra_balance":4}""", HttpStatusCode.OK, json)
                    p.endsWith("/rpc/buy_ultra") && user == Accounts.A ->
                        respond("""{"status":"ok","ultra_balance":9,"ruby_balance":31,"unit":10,"count":1}""", HttpStatusCode.OK, json)
                    // 안 읽음 요약 — A 5통 · B 2통(서로 다른 사람에게서). 함수 이름은 배너 스토어가 고른다(_v2 포함).
                    p.contains("/rpc/message_unread_summary") && user == Accounts.A ->
                        respond("""{"status":"ok","total":5,"peers":[{"peer_user_id":"${Accounts.PEER}","count":5}]}""", HttpStatusCode.OK, json)
                    p.contains("/rpc/message_unread_summary") && user == Accounts.B ->
                        respond("""{"status":"ok","total":2,"peers":[{"peer_user_id":"${Accounts.PEER_OF_B}","count":2}]}""", HttpStatusCode.OK, json)
                    // 기기 등록(버전 보고 — 맥 4140 reportedAppVersionStamp 의 데스크톱 짝).
                    p.endsWith("/rpc/register_device") && user == Accounts.B && failFirstBRegister && bRegisters++ == 0 ->
                        respond("""{"message":"synthetic outage"}""", HttpStatusCode.InternalServerError, json)
                    p.endsWith("/rpc/register_device") && user != null ->
                        respond("""{"status":"ok","push_prefs":{"message":true}}""", HttpStatusCode.OK, json)
                    // 내 토큰 행(token_usage_board) — A 의 줄만. B 의 몫은 비어 있다.
                    p.endsWith("/rpc/token_usage_board") && user == Accounts.A ->
                        respond(
                            """[{"user_id":"${Accounts.A}","display_name":"A","avatar_url":null,"claude_input":1000,"claude_output":0,""" +
                                """"claude_cache_read":0,"claude_cache_creation":0,"codex_input":0,"codex_output":0,"total":1000,"codex_effective":0}]""",
                            HttpStatusCode.OK, json,
                        )
                    p.endsWith("/rpc/token_usage_board") -> respond("[]", HttpStatusCode.OK, json)
                    p.endsWith("/rest/v1/token_usage_device_monthly") || p.endsWith("/rest/v1/token_usage_device_daily") ->
                        respond("", HttpStatusCode.Created)
                    p.endsWith("/rest/v1/profiles") && select.contains("token_usage_collect") && tokenCollect ->
                        respond("""[{"token_usage_public":true,"token_usage_collect":true,"focus_mode":false}]""", HttpStatusCode.OK, json)
                    // A 의 센터·상태메시지(맥 4145·4149). B 의 몫은 픽스처가 없다(404) — 못 읽으면 지난 값을 두므로 남은 A 의 값이 그대로 보인다.
                    p.endsWith("/rest/v1/profiles") && select == "display_name,avatar_url" && user == Accounts.A ->
                        respond("""[{"display_name":"A","avatar_url":null}]""", HttpStatusCode.OK, json)
                    p.endsWith("/rest/v1/profiles") && select == "center" && user == Accounts.A ->
                        respond("""[{"center":"seoul"}]""", HttpStatusCode.OK, json)
                    p.endsWith("/rest/v1/profiles") && select == "status_message" && user == Accounts.A ->
                        respond("""[{"status_message":"A 의 상태"}]""", HttpStatusCode.OK, json)
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
        desktopConfig = config,
        backend = AppGraph.Backend("https://probe.invalid", "stub-anon-key"),
        osVersion = "Windows 11",
        httpFactory = { configure -> HttpClient(engine) { configure() } },
    )
    private val job = SupervisorJob()
    val scope = CoroutineScope(test.coroutineContext.minusKey(Job) + job + CoroutineExceptionHandler { _, e -> uncaught += e })
    val kv = InMemoryDesktopKeyValueStore().apply {
        // 첫 실행 화면을 이미 지난 설치.
        putBoolean(DesktopSettingsKeys.AI_TOOL_DATA_CONSENT, aiConsent)
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

    // ------------------------------------------------------------------ 늦은 응답(int-w4a 검증 프로브 → 상설)
    // 위 두 시험은 응답이 **끝난** 상태만 잰다. 전환 직전에 떠난 A 의 요청이 전환 **뒤에** 떨어지는 길은 여기서만 본다 — 리스너의 reset 이
    // 이미 지나간 뒤라, 각 스토어가 세대·순번으로 그 응답을 버리지 않으면 B 의 화면을 다시 채운다.

    private suspend fun TestScope.signedInA(rig: BoundaryRig): BoundaryRig {
        rig.app.start(); runCurrent()
        rig.signIn(Accounts.A); runCurrent()
        advanceTimeBy(5_000); runCurrent()
        return rig
    }

    private suspend fun TestScope.issueGatedLoadsAsA(rig: BoundaryRig) {
        val app = rig.app
        rig.gateArmed = true
        val t0 = testScheduler.currentTime
        rig.scope.launch { app.rankings.loadLeague() }
        rig.scope.launch { app.me.loadCakeGift() }
        app.gamesStore.miniGames.prefetchRoundToken(MiniGameKind.timingBar)
        runCurrent()
        assertEquals(3, rig.held.size, "전제: A 의 세 요청이 붙잡혔다 — ${rig.held}")
        assertEquals(t0, testScheduler.currentTime, "전제: 붙잡는 동안 가상 시간이 흐르지 않았다(시간 초과로 실패한 게 아니다)")
    }

    private fun lateLeft(rig: BoundaryRig): List<String> = buildList {
        val app = rig.app
        if (app.rankings.league.isNotEmpty()) add("rankings.league=${app.rankings.league.map { it.name }}")
        if (app.me.cakeGift != null) add("me.cakeGift=${app.me.cakeGift?.id}")
        if (app.gamesStore.miniGames.hasUsableRoundToken(MiniGameKind.timingBar)) add("miniGames.roundToken")
    }

    /** 음성 대조: 계정이 그대로면 붙잡았던 응답은 **반영된다**(가드가 모든 응답을 버리는 고장이면 여기서 빨개진다). */
    @Test
    fun lateResponsesLandWhenTheAccountIsUnchanged() = runTest {
        val rig = signedInA(BoundaryRig(this, dirs.new("late-control")))
        try {
            issueGatedLoadsAsA(rig)
            assertTrue(lateLeft(rig).isEmpty(), "붙잡힌 동안엔 없다: ${lateLeft(rig)}")
            rig.gate.complete(Unit); advanceTimeBy(2_000); runCurrent()
            assertEquals(setOf("rankings.league", "me.cakeGift", "miniGames.roundToken"), lateLeft(rig).map { it.substringBefore('=') }.toSet())
        } finally { rig.close() }
    }

    @Test
    fun lateResponsesOfAAfterSignOutThenBDoNotRefill() = runTest {
        val rig = signedInA(BoundaryRig(this, dirs.new("late-signout")))
        try {
            issueGatedLoadsAsA(rig)
            rig.scope.launch { rig.app.sessionStore.signOut() }
            advanceTimeBy(5_000); runCurrent()
            assertNull(rig.app.sessionStore.session, "전제: 로그아웃")
            rig.signIn(Accounts.B); advanceTimeBy(2_000); runCurrent()
            rig.gate.complete(Unit); advanceTimeBy(5_000); runCurrent()
            assertEquals(Accounts.B, rig.app.sessionStore.session?.userID)
            assertTrue(lateLeft(rig).isEmpty(), "로그아웃 직전 떠난 A 의 응답이 B 를 다시 채웠다: ${lateLeft(rig)}")
            assertTrue(rig.uncaught.isEmpty(), "예외: ${rig.uncaught}")
        } finally { rig.close() }
    }

    @Test
    fun lateResponsesOfAAfterDirectSwitchDoNotRefill() = runTest {
        val rig = signedInA(BoundaryRig(this, dirs.new("late-switch")))
        try {
            issueGatedLoadsAsA(rig)
            rig.signIn(Accounts.B); advanceTimeBy(2_000); runCurrent()
            rig.gate.complete(Unit); advanceTimeBy(5_000); runCurrent()
            assertEquals(Accounts.B, rig.app.sessionStore.session?.userID)
            assertTrue(lateLeft(rig).isEmpty(), "A→B 직행 전 떠난 A 의 응답이 B 를 다시 채웠다: ${lateLeft(rig)}")
            assertTrue(rig.uncaught.isEmpty(), "예외: ${rig.uncaught}")
        } finally { rig.close() }
    }

    /** A 의 지갑 요청(잔량 777)을 붙잡았다가 [mode] 뒤에 푼다 → 그때의 지갑 잔량. */
    private suspend fun TestScope.walletAfterLateA(mode: String): Long? {
        val rig = signedInA(BoundaryRig(this, dirs.new("wallet-$mode")))
        try {
            rig.gated = listOf("/rpc/ultra_wallet_sync")
            rig.gateArmed = true
            rig.app.social.wallet.sync(UltraSyncReason.MissionCandidate)
            runCurrent()
            assertTrue(rig.held.any { it.endsWith("ultra_wallet_sync") }, "전제: A 의 지갑 요청이 붙잡혔다 — ${rig.held}")
            when (mode) {
                "switch" -> { rig.signIn(Accounts.B); advanceTimeBy(2_000); runCurrent() }
                "signout" -> {
                    rig.scope.launch { rig.app.sessionStore.signOut() }; advanceTimeBy(5_000); runCurrent()
                    rig.signIn(Accounts.B); advanceTimeBy(2_000); runCurrent()
                }
            }
            if (mode != "control") assertNull(rig.app.social.wallet.state.value.balance, "전제: 전환이 지갑을 비웠다")
            rig.gate.complete(Unit); advanceTimeBy(3_000); runCurrent()
            assertTrue(rig.uncaught.isEmpty(), "예외: ${rig.uncaught}")
            return rig.app.social.wallet.state.value.balance
        } finally { rig.close() }
    }

    @Test fun lateWalletLandsWhenTheAccountIsUnchanged() = runTest { assertEquals(777L, walletAfterLateA("control")) }

    @Test fun lateWalletOfADoesNotLandOnBAfterSignOut() = runTest { assertNull(walletAfterLateA("signout"), "로그아웃 뒤 B 지갑에 A 의 잔량") }

    /** ② A→B 직행은 세대가 그대로다(core SessionStore.adoptSignedInSession) — 지갑이 스스로 순번을 올려 늦은 응답을 버려야 한다. */
    @Test fun lateWalletOfADoesNotLandOnBAfterDirectSwitch() = runTest { assertNull(walletAfterLateA("switch"), "A→B 직행 뒤 B 지갑에 A 의 잔량") }

    /**
     * A 의 울트라 발신(잔량 4)을 붙잡았다가 [mode] 뒤에 푼다 → (지갑 잔량, 발신 안내, PEER 쿨타임). int-w4b 반박 검증 P5 의 상설판.
     * 지갑 sync 의 순번을 지나치는 두 번째 쓰기 길(발신 성공 → applyUltraBalance → wallet.applyBalance)이다. 맥은 같은 자리를 세대로 막고
     * (WorkTimerStorePoke.swift:175) 계정 바뀜엔 clearPersistedSession 이 세대를 올린다(WorkTimerStore.swift:4033) — 직행은 세대가 그대로라
     * 발신기가 주인 계정·순번으로 막는다.
     */
    private suspend fun TestScope.ultraSendAfterLateA(mode: String): Triple<Long?, String?, Boolean> {
        val rig = signedInA(BoundaryRig(this, dirs.new("send-$mode"), DesktopAppConfig(duels = true, poke = true, ultra = true)))
        try {
            rig.app.work.commands.start(WorkStartOrigin.MANUAL); runCurrent(); advanceTimeBy(1_000); runCurrent()
            assertTrue(rig.app.work.store.pokeConsumeFacts().localSessionOpen, "전제: A 근무 중(로컬 세션)")
            rig.gated = listOf("/rpc/ultra_poke_user")
            rig.gateArmed = true
            assertNotNull(rig.app.social.actions.sendUltraPoke(Accounts.PEER), "전제: 발신 Job")
            runCurrent()
            assertTrue(rig.held.any { it.endsWith("ultra_poke_user") }, "전제: A 의 울트라 발신이 붙잡혔다 — ${rig.held}")
            switchAway(rig, mode)
            rig.gate.complete(Unit); advanceTimeBy(500); runCurrent()
            assertTrue(rig.uncaught.isEmpty(), "예외: ${rig.uncaught}")
            val sender = requireNotNull(rig.app.social.sender)
            return Triple(rig.app.social.wallet.state.value.balance, sender.notice.value, Accounts.PEER in sender.cooldownUntil.value)
        } finally { rig.close() }
    }

    private suspend fun TestScope.switchAway(rig: BoundaryRig, mode: String) {
        when (mode) {
            "switch" -> { rig.signIn(Accounts.B); advanceTimeBy(2_000); runCurrent() }
            "signout" -> {
                rig.scope.launch { rig.app.sessionStore.signOut() }; advanceTimeBy(5_000); runCurrent()
                rig.signIn(Accounts.B); advanceTimeBy(2_000); runCurrent()
            }
            // A → B → A 직행 두 번 — 주인은 다시 A 라 주인 대조로는 못 가른다. 리스너의 reset(순번)만 막는다(맥은 세대가 두 번 오른다).
            "roundtrip" -> {
                rig.signIn(Accounts.B); advanceTimeBy(2_000); runCurrent()
                rig.signIn(Accounts.A); advanceTimeBy(2_000); runCurrent()
            }
        }
        if (mode == "switch" || mode == "signout") {
            assertEquals(Accounts.B, rig.app.sessionStore.session?.userID, "전제: B 로 넘어갔다")
            assertNull(rig.app.social.wallet.state.value.balance, "전제: 전환이 지갑을 비웠다")
        }
        if (mode == "roundtrip") assertEquals(Accounts.A, rig.app.sessionStore.session?.userID, "전제: A 로 돌아왔다")
    }

    /** 음성 대조: 계정이 그대로면 붙잡았던 발신 응답은 잔량·안내·쿨타임에 **닿는다**(가드가 모든 응답을 버리는 고장이면 빨개진다). */
    @Test fun lateUltraSendLandsWhenTheAccountIsUnchanged() = runTest {
        val (balance, notice, cooldown) = ultraSendAfterLateA("control")
        assertNotNull(balance, "대조: 잔량이 선다(4 → 미션 후보 동기화 777)")
        assertNotNull(notice, "대조: 발신 안내")
        assertTrue(cooldown, "대조: PEER 쿨타임")
    }

    @Test fun lateUltraSendOfADoesNotLandOnBAfterSignOut() = runTest {
        assertEquals(Triple<Long?, String?, Boolean>(null, null, false), ultraSendAfterLateA("signout"), "로그아웃→B 뒤 A 의 늦은 울트라 발신 응답")
    }

    @Test fun lateUltraSendOfADoesNotLandOnBAfterDirectSwitch() = runTest {
        assertEquals(Triple<Long?, String?, Boolean>(null, null, false), ultraSendAfterLateA("switch"), "A→B 직행 뒤 A 의 늦은 울트라 발신 응답이 B 에 (잔량, 안내, PEER 쿨타임)")
    }

    /** A 의 울트라 구매(울트라 9 · 루비 31)를 붙잡았다가 [mode] 뒤에 푼다 → (지갑 잔량, 루비 칸, 구매 안내). 같은 모양의 세 번째 쓰기 길(UltraPurchase.apply). */
    private suspend fun TestScope.purchaseAfterLateA(mode: String): Triple<Long?, Long?, String?> {
        val rig = signedInA(BoundaryRig(this, dirs.new("buy-$mode"), DesktopAppConfig(duels = true, poke = true, ultra = true)))
        try {
            rig.gated = listOf("/rpc/buy_ultra")
            rig.gateArmed = true
            assertNotNull(rig.app.social.actions.buyUltra(1), "전제: 구매 Job")
            runCurrent()
            assertTrue(rig.held.any { it.endsWith("buy_ultra") }, "전제: A 의 구매가 붙잡혔다 — ${rig.held}")
            switchAway(rig, mode)
            if (mode == "switch" || mode == "signout") assertNull(rig.app.ruby.rubyBalance, "전제: 전환이 루비 칸을 비웠다")
            rig.gate.complete(Unit); advanceTimeBy(500); runCurrent()
            assertTrue(rig.uncaught.isEmpty(), "예외: ${rig.uncaught}")
            val purchase = requireNotNull(rig.app.social.purchase)
            assertFalse(purchase.isPurchasing.value, "구매 깃발은 어느 경우든 내려간다")
            return Triple(rig.app.social.wallet.state.value.balance, rig.app.ruby.rubyBalance, purchase.notice.value)
        } finally { rig.close() }
    }

    @Test fun latePurchaseLandsWhenTheAccountIsUnchanged() = runTest {
        assertEquals(Triple<Long?, Long?, String?>(9L, 31L, "울트라 1개를 샀어요!"), purchaseAfterLateA("control"), "대조: 계정 그대로면 서버 값이 선다")
    }

    @Test fun latePurchaseOfADoesNotLandOnBAfterSignOut() = runTest {
        assertEquals(Triple<Long?, Long?, String?>(null, null, null), purchaseAfterLateA("signout"), "로그아웃→B 뒤 A 의 늦은 구매 응답")
    }

    @Test fun latePurchaseOfADoesNotLandOnBAfterDirectSwitch() = runTest {
        assertEquals(Triple<Long?, Long?, String?>(null, null, null), purchaseAfterLateA("switch"), "A→B 직행 뒤 A 의 늦은 구매 응답이 B 에 (울트라, 루비, 안내)")
    }

    /** A → B → A: 돌아온 A 의 화면에도 전환 전 응답은 닿지 않는다(지갑 잔량은 A 의 새 sync 가 정당하게 채울 수 있어 안내·쿨타임으로 잰다). */
    @Test fun lateUltraSendDoesNotLandAfterRoundTrip() = runTest {
        val (_, notice, cooldown) = ultraSendAfterLateA("roundtrip")
        assertEquals(null to false, notice to cooldown, "A→B→A 뒤 떠 있던 발신 응답이 (안내, PEER 쿨타임)에")
    }

    @Test fun latePurchaseDoesNotLandAfterRoundTrip() = runTest {
        val (ultra, ruby, notice) = purchaseAfterLateA("roundtrip")
        assertTrue(ultra != 9L && ruby != 31L && notice == null, "A→B→A 뒤 떠 있던 구매 응답이 닿았다: ultra=$ultra ruby=$ruby notice=$notice")
    }

    /** 끝난 발신의 안내·쿨타임도 계정에 묶인다(맥 clearPersistedSession WorkTimerStore.swift:4091-4092) — B 는 A 가 찌른 PEER 를 바로 찌를 수 있다. */
    @Test fun settledSendStateOfADoesNotCarryOverToB() = runTest {
        for (mode in listOf("switch", "signout")) {
            val rig = signedInA(BoundaryRig(this, dirs.new("settled-$mode"), DesktopAppConfig(duels = true, poke = true, ultra = true)))
            try {
                rig.app.work.commands.start(WorkStartOrigin.MANUAL); runCurrent(); advanceTimeBy(1_000); runCurrent()
                assertNotNull(rig.app.social.actions.sendUltraPoke(Accounts.PEER)); advanceTimeBy(500); runCurrent()
                val sender = requireNotNull(rig.app.social.sender)
                assertTrue(sender.notice.value != null && Accounts.PEER in sender.cooldownUntil.value, "전제($mode): A 의 발신이 끝나 안내·쿨타임이 섰다")
                switchAway(rig, mode)
                assertEquals(null to emptyMap(), sender.notice.value to sender.cooldownUntil.value, "$mode 뒤 A 의 발신 안내·쿨타임이 B 에 남았다")
            } finally { rig.close() }
        }
    }

    // ------------------------------------------------------------------ ① 토큰 업로드 장부·내 행(맥 4074-4088)

    private fun TestScope.nowSwift(): SwiftDate = SwiftDate.fromEpochMillis(WiringTestRig.BASE_MS + testScheduler.currentTime)

    /** 이 기기의 이번 달 사용량(합성 — 1일과 오늘 이틀). 사람이 아니라 **기기**의 숫자라 A·B 가 같은 값을 올린다. */
    private fun TestScope.machineUsage(): Pair<TokenUsageMonthly, List<String>> {
        val now = nowSwift()
        val month = TokenUsageMonthKey.current(now)
        val days = listOf("$month-01", TokenUsageDayKey.current(now)).distinct()
        return TokenUsageMonthly(month = month, claudeInput = 1000, claudeDaily = days.associateWith { 500L }) to days
    }

    private fun tokenRig(test: TestScope, name: String) =
        BoundaryRig(test, dirs.new(name), DesktopAppConfig(duels = true, tokenUpload = true), aiConsent = true).apply { tokenCollect = true }

    /**
     * 깃발(tokenUpload)을 켠 그래프: A 가 월간·일별을 올리고 내 행을 받은 뒤 A → B 직행. 맥 4074-4088 처럼 내 행·영속본·업로드 장부가 비어야
     * B 의 첫 업로드가 "이미 올린 날"로 빠지지 않고, B 의 첫 내 행 조회가 A 의 300초 스로틀에 막히지 않는다. 본문에 A 의 줄 0.
     */
    @Test
    fun tokenLedgerAndMyRowStartOverForB() = runTest {
        val rig = signedInA(tokenRig(this, "token-switch"))
        try {
            val up = rig.app.tokens.upload
            val (usage, days) = machineUsage()
            up.uploadTokenUsageIfNeeded(usage, null, null, nowSwift())
            up.loadMyTokenRowIfDue(nowSwift(), force = true)
            runCurrent()
            val aPaths = rig.wires.filter { it.user == Accounts.A }.map { it.url.substringBefore('?') }
            assertTrue(aPaths.any { it.endsWith("/token_usage_device_monthly") } && aPaths.any { it.endsWith("/token_usage_device_daily") },
                "전제: A 의 월간·일별이 나갔다 — $aPaths")
            assertEquals(Accounts.A, up.myTokenRow?.userID, "전제: A 의 내 행이 섰다")
            assertNotNull(rig.kv.getString(TokenUploadCoordinator.MY_ROW_KEY), "전제: 내 행 영속본")

            val mark = rig.wires.size
            rig.signIn(Accounts.B); advanceTimeBy(5_000); runCurrent()
            assertEquals(Accounts.B, rig.app.sessionStore.session?.userID, "전제: B 로 바뀌었다")
            assertNull(up.myTokenRow, "B 화면에 A 의 내 행: ${up.myTokenRow}")
            assertNull(rig.kv.getString(TokenUploadCoordinator.MY_ROW_KEY), "A 의 내 행 영속본이 남았다(재실행하면 B 화면에 복원된다)")

            // 같은 기기 값 그대로 61초 뒤(60초 스로틀 밖): B 의 몫이 처음부터 다시 올라가야 한다.
            advanceTimeBy(61_000)
            up.uploadTokenUsageIfNeeded(usage, null, null, nowSwift())
            up.loadMyTokenRowIfDue(nowSwift())
            runCurrent()
            val after = rig.wires.drop(mark)
            val bMonthly = after.filter { it.user == Accounts.B && it.url.contains("/token_usage_device_monthly") }
            val bDaily = after.filter { it.user == Accounts.B && it.url.contains("/token_usage_device_daily") }
            assertEquals(1, bMonthly.size, "B 의 월간 업로드가 앞 사람 장부에 막혔다: ${after.map { it.user to it.url.substringBefore('?') }}")
            assertEquals(1, bDaily.size, "B 의 일별 업로드가 앞 사람 장부에 막혔다")
            days.forEach { d -> assertTrue(bDaily.single().body.contains("\"$d\""), "B 의 일별 본문에 $d 가 빠졌다('이미 올린 날'): ${bDaily.single().body}") }
            assertTrue(after.any { it.user == Accounts.B && it.url.contains("/rpc/token_usage_board") }, "B 의 내 행 조회가 A 의 300초 스로틀에 막혔다")
            val aTrace = after.filter { it.user == Accounts.B && (it.body.contains(Accounts.A) || it.url.contains(Accounts.A)) }
            assertTrue(aTrace.isEmpty(), "B 의 업로드 본문에 A 의 줄: $aTrace")
            assertTrue(after.none { it.user == Accounts.A }, "전환 뒤 A 의 토큰 요청: ${after.filter { it.user == Accounts.A }}")
        } finally { rig.close() }
    }

    /** A 의 월간 업로드가 전환을 건너 늦게 끝나도 B 의 장부를 채우지 않는다(세대는 그대로 — 조정자의 계정 순번이 버린다). */
    @Test
    fun lateTokenUploadOfADoesNotFillBLedger() = runTest {
        val rig = signedInA(tokenRig(this, "token-late"))
        try {
            val up = rig.app.tokens.upload
            val (usage, _) = machineUsage()
            rig.gated = listOf("/token_usage_device_monthly")
            rig.gateArmed = true
            rig.scope.launch { up.uploadTokenUsageIfNeeded(usage, null, null, nowSwift()) }
            runCurrent()
            assertEquals(1, rig.held.size, "전제: A 의 월간 업로드가 붙잡혔다 — ${rig.held}")
            rig.signIn(Accounts.B); advanceTimeBy(2_000); runCurrent()
            val mark = rig.wires.size
            rig.gate.complete(Unit); advanceTimeBy(2_000); runCurrent()
            advanceTimeBy(61_000)
            up.uploadTokenUsageIfNeeded(usage, null, null, nowSwift())
            runCurrent()
            val after = rig.wires.drop(mark)
            assertEquals(1, after.count { it.user == Accounts.B && it.url.contains("/token_usage_device_monthly") },
                "A 의 늦은 성공이 B 의 장부를 채워 B 의 월간 업로드가 빠졌다: ${after.map { it.user to it.url.substringBefore('?') }}")
            assertTrue(rig.uncaught.isEmpty(), "예외: ${rig.uncaught}")
        } finally { rig.close() }
    }

    // ------------------------------------------------------------------ ③ A → B 직행 뒤 안 읽음 요약

    /** 단계가 SignedIn 에 머무는 직행에서도 B 의 요약을 **바로** 읽는다(60초 주기를 기다리면 그동안 B 의 배지가 0). */
    @Test
    fun directSwitchReadsBUnreadSummaryAtOnce() = runTest {
        val rig = startedWithA()
        try {
            advanceTimeBy(1_000); runCurrent()
            assertEquals(5L, rig.app.messages.summary?.summary?.total, "전제: A 의 요약(5통)이 섰다")
            val mark = rig.sent.size
            rig.signIn(Accounts.B)
            advanceTimeBy(5_000); runCurrent()
            val bSummary = rig.sent.drop(mark).filter { it.user == Accounts.B && it.path.contains("/rpc/message_unread_summary") }
            assertTrue(bSummary.isNotEmpty(), "직행 뒤 5초 안에 B 의 요약을 읽지 않았다: ${rig.sent.drop(mark)}")
            assertEquals(2L, rig.app.messages.summary?.summary?.total, "B 의 요약(2통)이 서야 한다")
            assertEquals(setOf(Accounts.PEER_OF_B), rig.app.messages.summary?.summary?.unreadPeerIDs, "B 의 안 읽음에 A 의 상대")
        } finally { rig.close() }
    }

    // ------------------------------------------------------------------ ④ 버전 보고 · 센터 · 상태메시지(맥 4140 · 4145 · 4149)

    @Test
    fun versionReportCenterAndStatusMessageDoNotCarryOverToB() = runTest {
        val rig = signedInA(BoundaryRig(this, dirs.new("profile-switch")))
        try {
            val me = rig.app.me
            me.loadHeader()
            me.loadStatusMessage()
            runCurrent()
            assertEquals("seoul", me.centerServerValue, "전제: A 의 센터")
            assertNotNull(me.statusMessage, "전제: A 의 상태메시지")
            assertTrue(me.statusMessageLoaded, "전제: 상태메시지를 서버에서 받았다")
            assertTrue(rig.sent.any { it.user == Accounts.A && it.path.endsWith("/rpc/register_device") }, "전제: A 의 버전 보고(register_device)")

            val mark = rig.wires.size
            rig.signIn(Accounts.B); advanceTimeBy(5_000); runCurrent()
            // B 의 센터·상태메시지 조회는 실패(픽스처 없음)라 지난 값을 둔다 — 남은 값이 있으면 그건 A 의 것이다.
            me.loadHeader()
            me.loadStatusMessage()
            runCurrent()
            assertNull(me.centerServerValue, "B 의 설정 화면에 A 의 센터")
            assertNull(me.statusMessage, "B 의 설정 화면에 A 의 상태메시지")
            assertFalse(me.statusMessageLoaded, "A 의 상태메시지가 '서버가 확인해 준 B 의 값'으로 남았다")
            // 맥 4138-4140: 버전 도장이 남으면 B 프로필에 버전이 안 남아 B 가 메시지를 못 받는다.
            val bReport = rig.wires.drop(mark).filter { it.user == Accounts.B && it.url.contains("/rpc/register_device") }
            assertEquals(1, bReport.size, "B 의 버전 보고가 A 의 도장에 막혔다: ${rig.wires.drop(mark).map { it.user to it.url.substringBefore('?') }}")
            assertTrue(bReport.single().body.contains("p_app_version"), "B 의 버전 보고 본문: ${bReport.single().body}")
        } finally { rig.close() }
    }

    /**
     * ④ 데스크톱의 '버전 도장'은 기기 등록 서명(prefs deviceRegisteredSignature — core SessionStore.kt:593-621)이고 A → B 에 **지워지지 않는다**.
     * 로그인 등록은 서명을 보지 않지만(SessionStore.kt:597 — 포그라운드만 스로틀), B 의 로그인 등록이 실패하면 남은 A 의 도장이 B 의 포그라운드
     * 재등록과 비교된다 — 서명에 사용자 id 가 있어야(WindowsDeviceRegistration.signature) 막히지 않는다. 막히면 B 프로필에 버전이 안 남아
     * B 가 메시지를 못 받는다(맥 4138-4140 reportedAppVersionStamp = nil 이 막는 그 일).
     */
    @Test
    fun versionStampOfADoesNotBlockBForegroundReport() = runTest {
        val rig = signedInA(BoundaryRig(this, dirs.new("version-stamp")).apply { failFirstBRegister = true })
        try {
            assertTrue(rig.sent.any { it.user == Accounts.A && it.path.endsWith("/rpc/register_device") }, "전제: A 의 등록(도장)")
            rig.signIn(Accounts.B); advanceTimeBy(5_000); runCurrent()
            assertEquals(1, rig.bRegisters, "전제: B 의 로그인 등록 1회(실패 — 도장은 A 의 것 그대로)")
            val mark = rig.sent.size
            rig.app.sessionStore.appDidBecomeActive()
            advanceTimeBy(5_000); runCurrent()
            assertEquals(1, rig.sent.drop(mark).count { it.user == Accounts.B && it.path.endsWith("/rpc/register_device") },
                "B 의 포그라운드 재등록이 A 의 도장에 막혔다: ${rig.sent.drop(mark)}")
        } finally { rig.close() }
    }
}
