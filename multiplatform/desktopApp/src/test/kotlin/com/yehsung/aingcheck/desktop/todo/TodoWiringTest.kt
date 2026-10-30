// 데스크톱 할 일 배선 시험 — 진짜 SessionStore · 진짜 TodoListStore/TodoSync · core NowTodoSyncTransport · MockEngine 녹음(본문·인증 머리까지)
// · 임시 폴더의 진짜 파일. 정답: 맥 TodoSyncCoordinator.swift(맞추는 때 다섯) · CheckApp.swift:279(계정별 파일) · WorkTimerStoreTodoSync.swift(전송).
package com.yehsung.aingcheck.desktop.todo

import com.yehsung.aingcheck.core.foundation.identity.ClientIdentity
import com.yehsung.aingcheck.core.foundation.identity.ClientPlatform
import com.yehsung.aingcheck.core.foundation.platform.InstallationIdentity
import com.yehsung.aingcheck.core.foundation.platform.SingleInstanceGuard
import com.yehsung.aingcheck.core.foundation.platform.desktop.PowerEvent
import com.yehsung.aingcheck.core.net.SupabaseWorkService
import com.yehsung.aingcheck.core.rules.text.RulesWireTextRules
import com.yehsung.aingcheck.core.session.SessionStore
import com.yehsung.aingcheck.core.session.app.AppInfo
import com.yehsung.aingcheck.core.session.app.SessionClock
import com.yehsung.aingcheck.core.session.context.SessionContext
import com.yehsung.aingcheck.core.stores.now.todo.TodoFileStore
import com.yehsung.aingcheck.core.stores.now.todo.TodoSyncOutcome
import com.yehsung.aingcheck.core.wire.SupabaseSession
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.desktop.wiring.FakePower
import com.yehsung.aingcheck.desktop.wiring.MemoryPrefs
import com.yehsung.aingcheck.desktop.wiring.TodoWiring
import com.yehsung.aingcheck.desktop.wiring.TodoWiringDeps
import com.yehsung.aingcheck.testkit.vault.InMemoryTokenVault
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.MockEngineConfig
import io.ktor.client.engine.mock.respond
import io.ktor.client.engine.mock.toByteArray
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.http.headersOf
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineExceptionHandler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.nio.file.AccessDeniedException
import java.nio.file.Files
import java.nio.file.Path
import kotlin.io.path.exists
import kotlin.io.path.listDirectoryEntries
import kotlin.io.path.name
import kotlin.io.path.readBytes
import kotlin.io.path.readText
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

@OptIn(ExperimentalCoroutinesApi::class)
class TodoWiringTest {
    private val dirs = mutableListOf<Path>()

    @AfterTest
    fun cleanup() {
        dirs.forEach { d -> d.toFile().deleteRecursively() }
    }

    /** 녹음한 요청 한 건(경로 · 인증 머리 · 본문 그대로). */
    data class Call(val method: String, val path: String, val auth: String?, val body: String)

    /** 합성 서버 + 진짜 세션 + 진짜 파일. 서버는 계정(토큰)별 행을 들고 `todo_sync` 를 흉내 낸다(p_changes 를 받아 그 계정 행 전체를 돌려준다). */
    inner class Rig(val test: TestScope) {
        val dir: Path = Files.createTempDirectory("aingcheck-todo").also { dirs.add(it) }
        val calls = mutableListOf<Call>()
        val uncaught = mutableListOf<Throwable>()
        val serverRows = mutableMapOf<String, LinkedHashMap<String, JsonObject>>()

        /** 계정 → 응답 방식("ok" · "invalid" · "missing"). */
        var behavior: (user: String?) -> String = { "ok" }

        /** 계정 → 응답 전에 기다릴 시간(ms, 진행 중 요청을 만든다). */
        var holdMillis: (user: String?) -> Long = { 0L }
        private var watermark = 1_000L

        private val job = SupervisorJob()
        val scope = CoroutineScope(test.coroutineContext.minusKey(Job) + job + CoroutineExceptionHandler { _, e -> uncaught += e })
        val sessionClock = SessionClock { SwiftDate.fromEpochMillis(BASE_MS + test.testScheduler.currentTime) }
        val clock: () -> Double = { (BASE_MS + test.testScheduler.currentTime) / 1000.0 }

        private val engine = MockEngine(
            MockEngineConfig().apply {
                dispatcher = StandardTestDispatcher(test.testScheduler)
                addHandler { request ->
                    val auth = request.headers[HttpHeaders.Authorization]
                    val body = request.body.toByteArray().decodeToString()
                    val path = request.url.encodedPath
                    calls += Call(request.method.value, path, auth, body)
                    val json = headersOf(HttpHeaders.ContentType, "application/json")
                    if (!path.endsWith("/rpc/todo_sync")) {
                        return@addHandler respond("""{"code":"PGRST202","message":"no fixture"}""", HttpStatusCode.NotFound, json)
                    }
                    val user = auth?.removePrefix("Bearer tok-")
                    val hold = holdMillis(user)
                    if (hold > 0) delay(hold)
                    when (behavior(user)) {
                        "invalid" -> respond("""{"status":"invalid"}""", HttpStatusCode.OK, json)
                        "missing" -> respond("""{"code":"PGRST202","message":"Could not find the function public.todo_sync(p_changes, p_since_ms) in the schema cache"}""", HttpStatusCode.NotFound, json)
                        else -> {
                            val rows = serverRows.getOrPut(user ?: "?") { LinkedHashMap() }
                            Json.parseToJsonElement(body).jsonObject["p_changes"]!!.jsonArray.forEach { change ->
                                rows[change.jsonObject["id"]!!.jsonPrimitive.content] = change.jsonObject
                            }
                            watermark += 1_000
                            respond(
                                """{"status":"ok","items":${JsonArray(rows.values.toList())},"watermark_ms":$watermark,"full":true}""",
                                HttpStatusCode.OK,
                                json,
                            )
                        }
                    }
                }
            },
        )
        val service = SupabaseWorkService(
            projectURL = "https://todo.invalid",
            anonKey = "stub-anon-key",
            client = HttpClient(engine) { SupabaseWorkService.clientConfig(this) },
            clock = { sessionClock.now() },
            text = RulesWireTextRules,
            newUUIDString = { "ABCDEF12-0000-4000-8000-000000000000" },
        )
        val sessionStore = SessionStore(
            service = service,
            vault = InMemoryTokenVault(),
            prefs = MemoryPrefs(),
            appInfo = AppInfo(ClientIdentity(ClientPlatform.WINDOWS, 7L, "0.1.0"), "Windows 11"),
            installationIdentity = object : InstallationIdentity {
                override fun installationId(): String = "11111111-2222-4333-8444-555555555555"
            },
            clock = sessionClock,
            instanceGuard = object : SingleInstanceGuard {
                override fun tryAcquire(): Boolean = true
                override fun release() {}
            },
            parentScope = scope,
            newCleanupID = { "cleanup-1" },
        )
        val power = FakePower()
        val resets = mutableListOf<String>()
        var files = DesktopTodoFileSystem()
        private val made = mutableListOf<TodoWiring>()

        fun wiring(wakeNetworkReady: (suspend () -> Unit)? = null): TodoWiring {
            lateinit var w: TodoWiring
            w = TodoWiring(
                TodoWiringDeps(
                    dataDir = dir,
                    transport = TodoWiring.sessionTransport(SessionContext(sessionStore)),
                    accountIds = sessionStore.sessionFlow.map { it?.userID },
                    currentUserID = { sessionStore.session?.userID },
                    clock = clock,
                    files = files,
                    power = power,
                    wakeNetworkReady = wakeNetworkReady,
                    // 보드 정리는 파일을 바꾸기 **전**이어야 한다 — 그 순간 목록이 아직 앞 계정 파일인지 적는다.
                    beforeAccountSwitch = { resets += Path.of(w.list.filePath).name },
                ),
                scope,
            )
            made += w
            return w
        }

        fun signIn(user: String) = sessionStore.adoptSignedInSession(SupabaseSession("tok-$user", "ref-$user", user), "dawn@aing.example")

        fun todoCalls(): List<Call> = calls.filter { it.path.endsWith("/rpc/todo_sync") }

        fun file(user: String?): Path = Path.of(DesktopTodoFileSystem.path(dir, user))

        /** 만든 배선을 모두 닫고 줄기를 거둔다. 단언이 중간에 실패해도 [todoTest] 가 부른다 — 안 닫으면 runTest 의 끝 정리가 5분 주기를 영원히 돈다. */
        fun close() {
            made.forEach { it.close() }
            job.cancel()
        }
    }

    private fun todoTest(body: suspend TestScope.(Rig) -> Unit) = runTest {
        val r = Rig(this)
        try {
            body(r)
        } finally {
            r.close()
        }
    }

    @Test
    fun 로그인_직후_한_번__고친_뒤_1_5초_묶음__5분_주기() = todoTest { r ->
        val w = r.wiring()
        w.start()
        runCurrent()
        // 로그아웃(세션 없음) = 깃발 꺼짐과 같은 자리 — todo_sync 0.
        assertEquals(0, r.todoCalls().size)
        assertEquals("todos.local.json", Path.of(w.list.filePath).name)

        r.signIn(A)
        runCurrent()
        val loginAt = testScheduler.currentTime
        assertEquals(1, r.todoCalls().size, "로그인 직후 한 번")
        assertEquals("Bearer tok-$A", r.todoCalls().single().auth)
        assertEquals("todos.$A.json", Path.of(w.list.filePath).name)
        assertEquals(TodoSyncOutcome.synced, w.sync.lastOutcome)

        w.list.add("하나")
        advanceTimeBy(500)
        w.list.add("둘")
        advanceTimeBy(1_499)
        runCurrent()
        assertEquals(1, r.todoCalls().size, "마지막 고침 뒤 1.5초 전에는 보내지 않는다")
        advanceTimeBy(1)
        runCurrent()
        assertEquals(2, r.todoCalls().size, "1.5초 조용하면 한 번에 묶어 보낸다")
        val body = r.todoCalls()[1].body
        assertTrue("하나" in body && "둘" in body, body)
        assertTrue(w.list.pendingIDs.isEmpty())

        advanceTimeBy(loginAt + 300_000 - testScheduler.currentTime - 1)
        runCurrent()
        assertEquals(2, r.todoCalls().size, "5분 전에는 주기 없음")
        advanceTimeBy(1)
        runCurrent()
        assertEquals(3, r.todoCalls().size, "로그인 5분 뒤 주기")
        advanceTimeBy(300_000)
        runCurrent()
        assertEquals(4, r.todoCalls().size, "다시 5분 뒤")
        assertTrue(r.uncaught.isEmpty(), r.uncaught.toString())
        w.close()
        r.close()
    }

    @Test
    fun 계정_전환__다른_계정_할_일이_파일에도_요청에도_섞이지_않는다() = todoTest { r ->
        val w = r.wiring()
        w.start()
        r.signIn(A)
        runCurrent()
        w.list.add("A의 비밀 메모")
        advanceTimeBy(1_600)
        runCurrent()
        val secretId = w.list.items.single().id
        assertTrue(r.serverRows[A]!!.containsKey(secretId))

        // A 의 다음 요청을 10초 붙잡아 두고(진행 중), 그 사이 B 로 바꾼다.
        r.holdMillis = { if (it == A) 10_000 else 0 }
        w.list.add("A 둘째")
        advanceTimeBy(1_600)
        runCurrent()
        val inFlight = r.todoCalls().last()
        assertEquals("Bearer tok-$A", inFlight.auth)
        assertTrue("A 둘째" in inFlight.body)

        r.signIn(B)
        runCurrent()
        assertEquals(listOf("todos.local.json", "todos.$A.json"), r.resets, "보드 정리는 파일을 바꾸기 전(앞 계정 파일일 때) — 로그인 한 번 · 전환 한 번")
        assertEquals("todos.$B.json", Path.of(w.list.filePath).name)
        advanceTimeBy(20_000)
        runCurrent()
        // 늦게 온 A 응답(A 의 두 줄)은 B 목록에 합쳐지지 않는다.
        assertTrue(w.list.items.none { "A" in it.title }, w.list.items.toString())
        w.list.add("B 메모")
        advanceTimeBy(1_600)
        runCurrent()

        val bCalls = r.todoCalls().filter { it.auth == "Bearer tok-$B" }
        assertTrue(bCalls.size >= 2, "B 로그인 직후 + B 고침")
        bCalls.forEach { c ->
            assertFalse("A의 비밀" in c.body || "A 둘째" in c.body || secretId in c.body, "B 토큰 요청에 A 할 일: ${c.body}")
        }
        assertTrue(r.todoCalls().filter { it.auth == "Bearer tok-$A" }.none { "B 메모" in it.body }, "A 토큰 요청에 B 할 일")
        assertTrue(r.serverRows[A]!!.values.none { "B 메모" in it.toString() })
        assertTrue(r.serverRows[B]!!.values.none { "A의 비밀" in it.toString() || "A 둘째" in it.toString() })

        val bText = r.file(B).readText()
        val aText = r.file(A).readText()
        assertTrue("B 메모" in bText && "A의 비밀" !in bText && "A 둘째" !in bText, bText)
        assertTrue("A의 비밀" in aText && "A 둘째" in aText && "B 메모" !in aText, aText)

        // 다시 A — A 파일 그대로(아직 못 보낸 'A 둘째' 도 pending 으로 살아 있다) · B 줄 없음.
        r.holdMillis = { 0 }
        r.signIn(A)
        runCurrent()
        assertEquals("todos.$A.json", Path.of(w.list.filePath).name)
        assertEquals(setOf("A의 비밀 메모", "A 둘째"), w.list.items.map { it.title }.toSet())
        assertTrue(r.todoCalls().last().let { it.auth == "Bearer tok-$A" && "A 둘째" in it.body && "B 메모" !in it.body })
        assertTrue(r.uncaught.isEmpty(), r.uncaught.toString())
        w.close()
        r.close()
    }

    @Test
    fun 로그아웃_뒤_todo_sync_요청_0__로컬_파일로_바뀐다() = todoTest { r ->
        val w = r.wiring()
        w.start()
        r.signIn(A)
        runCurrent()
        w.list.add("A 할 일")
        advanceTimeBy(1_600)
        runCurrent()
        val before = r.todoCalls().size
        assertEquals(2, before)

        r.scope.launch { r.sessionStore.signOut() }
        runCurrent()
        assertEquals("todos.local.json", Path.of(w.list.filePath).name)
        assertEquals(null, w.activeUserID)
        w.list.add("로그아웃 메모")
        advanceTimeBy(30 * 60_000)
        r.power.emit(PowerEvent.WAKE)
        w.onBoardOpened()
        w.requestSync(com.yehsung.aingcheck.core.stores.now.todo.TodoSyncReason.periodic)
        advanceTimeBy(30 * 60_000)
        runCurrent()
        assertEquals(before, r.todoCalls().size, "로그아웃 뒤 todo_sync 0")
        assertTrue("로그아웃 메모" in r.file(null).readText())
        assertFalse("로그아웃 메모" in r.file(A).readText())
        w.close()
        r.close()
    }

    @Test
    fun 서버_거절이면_로컬_보존__함수_없음은_조용히_멈춘다() = todoTest { r ->
        r.behavior = { "invalid" }
        val w = r.wiring()
        w.start()
        r.signIn(A)
        runCurrent()
        val item = w.list.add("거절돼도 남는다")!!
        advanceTimeBy(1_600)
        runCurrent()
        assertEquals(TodoSyncOutcome.refused("invalid"), w.sync.lastOutcome)
        assertTrue(item.id in w.list.pendingIDs)
        val onDisk = TodoFileStore.decode(r.file(A).readText())
        assertEquals(listOf("거절돼도 남는다"), onDisk.items.map { it.title })
        assertTrue(item.id in onDisk.sync.pendingIDs, "파일의 pending 에도 남는다")

        // 서버가 돌아오면 다음 주기에 실려 간다.
        r.behavior = { "ok" }
        advanceTimeBy(300_000)
        runCurrent()
        assertEquals(TodoSyncOutcome.synced, w.sync.lastOutcome)
        assertTrue(r.serverRows[A]!!.containsKey(item.id))
        assertTrue(w.list.pendingIDs.isEmpty())

        // 함수 없음(PGRST202 404) → serverMissing · 5분 안의 고침·보드 열기는 서버를 치지 않는다(맥 쿨다운).
        r.behavior = { "missing" }
        w.list.add("함수 없음")
        advanceTimeBy(1_600)
        runCurrent()
        assertEquals(TodoSyncOutcome.serverMissing, w.sync.lastOutcome)
        val n = r.todoCalls().size
        w.list.add("또 고침")
        advanceTimeBy(1_600)
        w.onBoardOpened()
        runCurrent()
        assertEquals(n, r.todoCalls().size, "함수 없음 뒤 5분은 고침·보드 열기로 다시 치지 않는다")
        assertEquals(setOf("거절돼도 남는다", "함수 없음", "또 고침"), w.list.items.map { it.title }.toSet())
        w.close()
        r.close()
    }

    @Test
    fun 깨진_파일은_격리하고_빈_목록__손실_범위_보고() = todoTest { r ->
        val reports = mutableListOf<TodoQuarantine>()
        r.files = DesktopTodoFileSystem(onQuarantine = { reports += it })
        val garbage = "{\"version\":2,\"items\":[{\"id\":\"깨짐\"".toByteArray()
        Files.write(r.file(A), garbage)
        r.signIn(A)
        val w = r.wiring()
        assertTrue(w.list.items.isEmpty())
        val q = reports.single()
        assertEquals(r.file(A).toString(), q.originalPath)
        assertEquals(garbage.size.toLong(), q.bytes)
        assertTrue(q.moved && q.preserved)
        assertTrue(Path.of(q.backupPath).name.startsWith("todos.$A.json.corrupt-"))
        assertContentEquals(garbage, Path.of(q.backupPath).readBytes(), "백업에 원본 바이트 그대로")
        assertEquals(r.files.quarantines, reports)

        w.start()
        runCurrent()
        assertEquals(1, r.todoCalls().size)
        assertTrue(r.resets.isEmpty(), "처음 연 파일이 세션 계정 것이면 갈아 끼우지 않는다(맥 start 의 둘째 갈래 activate)")
        w.list.add("새로 시작")
        advanceTimeBy(1_600)
        runCurrent()
        assertContentEquals(garbage, Path.of(q.backupPath).readBytes(), "다음 저장이 백업을 건드리지 않는다")
        assertEquals(1, reports.size)
        w.close()
        r.close()
    }

    @Test
    fun 옮기지_못하면_베껴_둔다__다음_저장이_원본을_덮어도_문장은_남는다() = todoTest { r ->
        r.files = DesktopTodoFileSystem(mover = { from, _ -> throw AccessDeniedException(from.toString()) })
        val garbage = "not json at all — 사용자 문장".toByteArray()
        Files.write(r.file(A), garbage)
        r.signIn(A)
        val w = r.wiring()
        val q = r.files.quarantines.single()
        assertFalse(q.moved)
        assertTrue(q.preserved)
        w.start()
        w.list.add("덮어쓰기")
        runCurrent()
        assertTrue("덮어쓰기" in r.file(A).readText())
        assertContentEquals(garbage, Path.of(q.backupPath).readBytes())
        w.close()
        r.close()
    }

    @Test
    fun 깨어남과_보드_열기는_한_번씩_맞춘다__깨어남은_망_준비를_기다린다() = todoTest { r ->
        val ready = CompletableDeferred<Unit>()
        val w = r.wiring(wakeNetworkReady = { ready.await() })
        r.signIn(A)
        w.start()
        runCurrent()
        assertEquals(1, r.todoCalls().size, "목록을 만든 뒤 로그인됐다 — start 가 그 계정 파일로 바꿔 한 번")
        assertEquals(listOf("todos.local.json"), r.resets, "맥 start 의 첫 갈래: 만든 파일(local)과 세션 계정이 다르면 정리 후 전환")
        assertEquals("todos.$A.json", Path.of(w.list.filePath).name)
        r.power.emit(PowerEvent.SLEEP)
        r.power.emit(PowerEvent.WAKE)
        runCurrent()
        assertEquals(1, r.todoCalls().size, "망 준비 전에는 보내지 않는다")
        ready.complete(Unit)
        runCurrent()
        assertEquals(2, r.todoCalls().size, "깨어남 한 번")
        w.onBoardOpened()
        runCurrent()
        assertEquals(3, r.todoCalls().size, "보드 열기 한 번")
        w.close()
        r.close()
    }

    @Test
    fun close_뒤_요청_0__타이머_구독_모두_거둔다() = todoTest { r ->
        val w = r.wiring()
        r.signIn(A)
        w.start()
        runCurrent()
        val n = r.todoCalls().size
        w.list.add("닫기 직전")
        w.close()
        w.close()
        assertFalse(w.isStarted)
        advanceTimeBy(60 * 60_000)
        r.power.emit(PowerEvent.WAKE)
        w.onBoardOpened()
        r.signIn(B)
        runCurrent()
        assertEquals(n, r.todoCalls().size)
        assertEquals("todos.$A.json", Path.of(w.list.filePath).name, "닫힌 뒤 계정 흐름을 보지 않는다")
        assertTrue("닫기 직전" in r.file(A).readText(), "파일은 고칠 때 이미 쓰였다")
        r.close()
    }

    @Test
    fun 파일_자리는_맥_이름_규칙__원자_쓰기는_임시_파일을_남기지_않는다() {
        val dir = Files.createTempDirectory("aingcheck-todo-fs").also { dirs.add(it) }
        assertEquals(dir.resolve("todos.local.json").toAbsolutePath().toString(), DesktopTodoFileSystem.path(dir, null))
        assertEquals(dir.resolve("todos.local.json").toAbsolutePath().toString(), DesktopTodoFileSystem.path(dir, ""))
        assertEquals(dir.resolve("todos.$A.json").toAbsolutePath().toString(), DesktopTodoFileSystem.path(dir, A))
        assertEquals(dir.resolve("todos.evil.json").toAbsolutePath().toString(), DesktopTodoFileSystem.path(dir, "../..\\evil"))

        val fs = DesktopTodoFileSystem()
        val target = dir.resolve("sub").resolve("todos.x.json")
        assertEquals(null, fs.read(target.toString()))
        fs.writeAtomically(target.toString(), "첫".toByteArray())
        fs.writeAtomically(target.toString(), "둘째".toByteArray())
        assertEquals("둘째", target.readText())
        assertEquals(listOf("todos.x.json"), target.parent.listDirectoryEntries().map { it.name })
        assertTrue(target.exists())
    }

    companion object {
        const val BASE_MS = 1_789_623_900_000L
        const val A = "a0000000-0000-4000-8000-00000000000a"
        const val B = "b0000000-0000-4000-8000-00000000000b"
    }
}
