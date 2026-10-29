// 원본: Sources/CheckMobileKit/Demo/MobileStubURLProtocol.swift @ 3bd04bd (스텁 서버 — 요청 기록 · 모르는 요청은 404 PGRST202)
// 원본: Sources/CheckMobileKit/App/MobileRootView.swift @ 3bd04bd (루트 단계 분기 — 시험 셸이 같은 분기를 그린다)
//
// 기기 계측(스텁 픽스처)의 서버와 앱 조립. 기기는 저장소를 못 읽어 데모 픽스처 파일 대신 **이 시험만의 작은 응답**을 쓴다(데모 바이트 사본이 아니다 —
// 사람 둘 · 메시지 넷 · 찌르기 하나). 소켓 0(Ktor MockEngine) — 봉인 에뮬레이터 안에서 돈다. 보낸 메시지는 다음 이력에 실린다(상태 있는 스텁).
//
// 셸은 조립(K11)이 할 일을 시험용으로 짧게 흉내 낸다: 세션 단계 → (로그아웃) SignedOutEntry · (로그인) 탭 둘(지금 · 메시지) + 메시지 탭 경로.
// 실제 NavGraph·AppContainer 배선은 조정자 몫이다(assembly.md) — 이 셸은 진입 함수와 화면이 그 배선 없이 끝까지 도는지를 잰다.
package com.yehsung.aingcheck.android.screens.messages

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import com.yehsung.aingcheck.android.screens.now.NowHomeEntry
import com.yehsung.aingcheck.android.screens.session.LaunchEntry
import com.yehsung.aingcheck.android.screens.session.SignedOutEntry
import com.yehsung.aingcheck.android.screens.session.UpdateRequiredEntry
import com.yehsung.aingcheck.core.foundation.identity.ClientIdentity
import com.yehsung.aingcheck.core.foundation.identity.ClientPlatform
import com.yehsung.aingcheck.core.foundation.platform.InstallationIdentity
import com.yehsung.aingcheck.core.foundation.platform.KeyValueStore
import com.yehsung.aingcheck.core.foundation.platform.SingleInstanceGuard
import com.yehsung.aingcheck.core.net.SupabaseWorkService
import com.yehsung.aingcheck.core.rules.text.RulesWireTextRules
import com.yehsung.aingcheck.core.session.SessionPhase
import com.yehsung.aingcheck.core.session.SessionStore
import com.yehsung.aingcheck.core.session.app.AppInfo
import com.yehsung.aingcheck.core.session.app.SessionClock
import com.yehsung.aingcheck.core.session.context.SessionContext
import com.yehsung.aingcheck.core.stores.messages.MessagesStore
import com.yehsung.aingcheck.core.stores.messages.NaturalKoNameCollation
import com.yehsung.aingcheck.core.stores.now.NowStore
import com.yehsung.aingcheck.core.stores.now.NowTodoStorage
import com.yehsung.aingcheck.core.stores.now.todo.JvmTodoFileSystem
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.testkit.vault.InMemoryTokenVault
import com.yehsung.aingcheck.ui.screens.session.kit.LocalScreenTicking
import com.yehsung.aingcheck.ui.theme.AingTheme
import io.ktor.client.HttpClient
import io.ktor.client.engine.mock.MockEngine
import io.ktor.client.engine.mock.respond
import io.ktor.http.HttpHeaders
import io.ktor.http.HttpStatusCode
import io.ktor.http.content.OutgoingContent
import io.ktor.http.headersOf
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.io.File
import java.util.Base64
import java.util.concurrent.CopyOnWriteArrayList

/** 스텁이 받은 요청 한 건. */
data class StubCall(val method: String, val path: String, val body: String) {
    val rpc: String? get() = if (path.startsWith("/rest/v1/rpc/")) path.removePrefix("/rest/v1/rpc/") else null

    /** 본문 JSON 의 한 칸(글자). */
    fun field(name: String): String? = runCatching {
        val element = Json.parseToJsonElement(body).jsonObject[name]
        if (element == null || element is kotlinx.serialization.json.JsonNull) null else element.jsonPrimitive.content
    }.getOrNull()
}

/** 기기 시험의 사람들(데모 id 꼴 — 지어낸 이름). */
object StubPeople {
    const val ME = "d0000000-0000-4000-8000-000000000001"
    const val HANGYEOL = "d0000000-0000-4000-8000-0000000000b1"
    const val SORA = "d0000000-0000-4000-8000-0000000000b2"
    const val RECEIVED_MESSAGE = "d0000000-0000-4000-8000-00000000e001"
}

/**
 * 상태 있는 스텁 서버. 데모 시각(2026-09-17 14:05 KST) 하루 안의 대화: 한결 셋(받은 둘 · 보낸 하나) + 찌르기 하나, 소라 하나.
 * `send_message` 를 받으면 그 글을 다음 이력에 싣는다.
 */
class DeviceStubServer(private val now: SwiftDate) {
    val calls = CopyOnWriteArrayList<StubCall>()
    private val sent = CopyOnWriteArrayList<Pair<String, String>>() // (상대, 본문)

    fun rpcCalls(name: String): List<StubCall> = calls.filter { it.rpc == name }

    private val base = now.timeIntervalSince1970.toLong()

    private fun row(id: String, peer: String, name: String, body: String?, mine: Boolean, secondsAgo: Long, kind: String = "message", unread: Boolean? = null) =
        """{"id":"$id","from_user":"${if (mine) StubPeople.ME else peer}","to_user":"${if (mine) peer else StubPeople.ME}",""" +
            """"body":${body?.let { kotlinx.serialization.json.JsonPrimitive(it).toString() } ?: "null"},"created_at":null,"is_mine":$mine,""" +
            """"peer_user_id":"$peer","peer_display_name":"$name","peer_avatar_url":null,"created_epoch":${base - secondsAgo},""" +
            """"read_by_peer":${if (mine) "false" else "null"},"unread":${unread ?: if (mine) "null" else "false"},"kind":"$kind"}"""

    private fun history(): String {
        val rows = mutableListOf(
            row(StubPeople.RECEIVED_MESSAGE, StubPeople.HANGYEOL, "한결", "오늘 점심 같이 드실래요?", false, 3_600),
            row("d0000000-0000-4000-8000-00000000e002", StubPeople.HANGYEOL, "한결", "좋아요! 12시에 1층에서 봬요", true, 3_500),
            row("d0000000-0000-4000-8000-00000000f001", StubPeople.HANGYEOL, "한결", null, false, 1_800, kind = "poke"),
            row("d0000000-0000-4000-8000-00000000e003", StubPeople.HANGYEOL, "한결", "[아잉:하트]", false, 1_200),
            row("d0000000-0000-4000-8000-00000000e004", StubPeople.SORA, "소라", "공지 채널에도 올려 두었어요", false, 600, unread = true),
        )
        sent.forEachIndexed { i, (peer, body) ->
            rows += row("d0000000-0000-4000-8000-0000000a%04d".format(i), peer, if (peer == StubPeople.HANGYEOL) "한결" else "소라", body, true, 10L - i)
        }
        return rows.joinToString(",", "[", "]")
    }

    private fun jwt(userID: String): String {
        val exp = base + 3_600
        val b64 = Base64.getUrlEncoder().withoutPadding()
        return "hdr." + b64.encodeToString("""{"sub":"$userID","exp":$exp}""".toByteArray()) + ".sig"
    }

    /** (상태, 본문). 모르는 요청은 404 PGRST202 — 스토어가 옛 서버처럼 조용히 접어야 한다. */
    fun respond(call: StubCall): Pair<Int, String> = when {
        call.path == "/auth/v1/token" -> 200 to """{"access_token":"${jwt(StubPeople.ME)}","refresh_token":"r1","user":{"id":"${StubPeople.ME}"}}"""
        call.path == "/rest/v1/memberships" -> 200 to """[{"team_id":"d0000000-0000-4000-8000-000000007ea1","role":"member","teams":{"name":"아잉 데모팀","weekly_goal_hours":40}}]"""
        call.rpc == "client_release" -> 200 to """{"status":"ok","platform":"android","min_build":1,"latest_build":1}"""
        call.rpc == "register_device_fcm" || call.rpc == "register_device" -> 200 to """{"status":"ok","device_id":"dev-1"}"""
        call.rpc == "message_history_with_pokes" -> 200 to history()
        call.rpc == "message_unread_summary" ->
            200 to """{"status":"ok","total":1,"peers":[{"peer_user_id":"${StubPeople.SORA}","count":1,"last_epoch_ms":${(base - 600) * 1000}}]}"""
        call.rpc == "mark_conversation_read" -> 200 to """{"status":"ok","advanced":true,"unread":0,"poke_advanced":true,"poke_unread":0}"""
        call.rpc == "send_message" -> {
            val to = call.field("p_to") ?: ""
            call.field("p_body")?.let { sent += to to it }
            200 to """{"status":"ok","body":"보냈어요","ring":"sent"}"""
        }
        call.rpc == "app_user_directory" -> 200 to (
            """[{"user_id":"${StubPeople.HANGYEOL}","display_name":"한결","avatar_url":null,"is_working":true,"message_capable":true,"center":"seoul","status_message":"오늘은 회의 많은 날"},""" +
                """{"user_id":"${StubPeople.SORA}","display_name":"소라","avatar_url":null,"is_working":false,"message_capable":true,"center":"busan","status_message":null}]"""
            )
        call.rpc == "block_user" || call.rpc == "report_content" -> 200 to "{}"
        else -> 404 to """{"code":"PGRST202","message":"Could not find the function in the schema cache"}"""
    }

    val engine = MockEngine { request ->
        val body = (request.body as? OutgoingContent.ByteArrayContent)?.bytes()?.decodeToString() ?: ""
        val call = StubCall(request.method.value, request.url.encodedPath, body)
        calls += call
        val (status, text) = respond(call)
        respond(text, HttpStatusCode.fromValue(status), headersOf(HttpHeaders.ContentType, "application/json"))
    }
}

/** 시험 앱 한 벌(세션 · 지금 · 메시지 스토어). 스토어는 메인 디스패처에서 돈다(앱과 같다). */
class DeviceApp(filesDir: File, val clock: SessionClock = SessionClock.fixed(SessionClock.demoInstant)) {
    val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    val server = DeviceStubServer(clock.now())
    private val prefs = object : KeyValueStore {
        val values = HashMap<String, Any>()
        override fun getString(key: String) = values[key] as? String
        override fun putString(key: String, value: String) { values[key] = value }
        override fun getLong(key: String) = values[key] as? Long
        override fun putLong(key: String, value: Long) { values[key] = value }
        override fun getBoolean(key: String) = values[key] as? Boolean
        override fun putBoolean(key: String, value: Boolean) { values[key] = value }
        override fun remove(key: String) { values.remove(key) }
    }
    val session = SessionStore(
        service = SupabaseWorkService("https://stub.invalid", "stub-anon-key", HttpClient(server.engine) { SupabaseWorkService.clientConfig(this) },
            { clock.now() }, RulesWireTextRules, { "ABCDEF12-0000-4000-8000-000000000000" }),
        vault = InMemoryTokenVault(),
        prefs = prefs,
        appInfo = AppInfo(ClientIdentity(ClientPlatform.ANDROID, 1, "0.1.0"), "Android 16"),
        installationIdentity = object : InstallationIdentity { override fun installationId() = "d0000000-0000-4000-8000-0000000000aa" },
        clock = clock,
        instanceGuard = object : SingleInstanceGuard {
            override fun tryAcquire() = true
            override fun release() {}
        },
        parentScope = scope,
    )
    val context = SessionContext(session)
    val messages = MessagesStore(context, scope, NaturalKoNameCollation, newLocalID = { "local-" + System.nanoTime() })
    val now = NowStore(context, scope, NowTodoStorage(File(filesDir, "w3a-todo").also { it.mkdirs() }.absolutePath, JvmTodoFileSystem()))

    init {
        messages.nowStore = now
        session.onSignedIn = {
            messages.appDidBecomeActive()
            now.appDidBecomeActive()
        }
    }

    fun close() = scope.cancel()
}

/** 시험 셸 탭(지금 · 메시지). */
enum class ShellTab(val title: String) { NOW("지금"), MESSAGES("메시지") }

/** 조립을 흉내 낸 셸: 세션 단계 → 화면 · 탭 막대 · 메시지 탭 경로(목록 → 대화). */
@Composable
fun W3aDeviceShell(app: DeviceApp) {
    AingTheme(dark = false) {
        CompositionLocalProvider(LocalScreenTicking provides false) {
            val phase by app.session.phaseFlow.collectAsState()
            when (val p = phase) {
                SessionPhase.Launching, SessionPhase.AnotherInstanceRunning -> LaunchEntry()
                is SessionPhase.NeedsUpdate -> UpdateRequiredEntry(p.minBuild, 1)
                SessionPhase.SignedOut -> SignedOutEntry(app.session)
                SessionPhase.SignedIn -> SignedInTabs(app)
            }
        }
    }
}

@Composable
private fun SignedInTabs(app: DeviceApp) {
    var tab by rememberSaveable { mutableStateOf(ShellTab.NOW) }
    var conversation by rememberSaveable { mutableStateOf<String?>(null) }
    Scaffold(
        bottomBar = {
            NavigationBar(Modifier.testTag("tab-bar")) {
                ShellTab.entries.forEach { t ->
                    NavigationBarItem(selected = tab == t, onClick = { tab = t }, icon = {}, label = { Text(t.title) },
                        modifier = Modifier.testTag("tab:${t.name.lowercase()}"))
                }
            }
        },
    ) { padding ->
        Box(Modifier.padding(padding)) {
            when (tab) {
                ShellTab.NOW -> NowHomeEntry(app.now, work = null, characterID = null, open = {}, openRoute = { route ->
                    MessagesRouting.children(route)?.let { children ->
                        tab = ShellTab.MESSAGES
                        conversation = (children.lastOrNull() as? com.yehsung.aingcheck.android.nav.Dest.Conversation)?.peerId
                    }
                })
                ShellTab.MESSAGES -> {
                    val peer = conversation
                    if (peer == null) {
                        MessagesListEntry(app.messages, open = { dest ->
                            (dest as? com.yehsung.aingcheck.android.nav.Dest.Conversation)?.let { conversation = it.peerId }
                        })
                    } else {
                        BackHandler { conversation = null }
                        ConversationEntry(app.messages, peer, back = { conversation = null }, leaveToList = { conversation = null })
                    }
                }
            }
        }
    }
    LaunchedEffect(Unit) { app.messages.appDidBecomeActive() }
}
