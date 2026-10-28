// 원본: Sources/CheckMobileKit/Messages/MessagesComposerView.swift @ 3bd04bd (★ 한글 조합 중에는 보내지 않는다 — 확정한 뒤 보낸다 · 비운 칸에 되살아나지 않는다)
//
// G §2-3 W3-a ③ IME 재생 시험(E§8.3): Gboard 한국어 두벌식으로 **녹화한** IME 호출열(ImeRecordings.GBOARD_KO — ImeGboardLiveDeviceTest 가
// 공용 aingcheck-api36-ko 에서 뜬 것)을 입력줄의 InputConnection 에 그대로 재생한다. 어느 기기·어느 키보드에서든 같은 호출열이다(키보드가 없어도 된다).
// 단언: 보낸 글 = 녹화 때 보낸 글 · [보내기] 뒤 칸이 비고 그대로 남는다(녹화된 뒤따름 호출까지 재생한 뒤) · 상한을 넘긴 조합은 잘리지 않고 막힌다 · 예외 0.
// 갤럭시(삼성 키보드) 녹화는 나중에 같은 꼴로 더한다(E§8.4 — 기기 도착 뒤).
package com.yehsung.aingcheck.android.screens.messages

import android.view.inputmethod.InputConnection
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.ExperimentalTestApi
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.yehsung.aingcheck.ui.screens.messages.ConversationScreen
import com.yehsung.aingcheck.ui.screens.messages.MessagesTags
import com.yehsung.aingcheck.ui.screens.session.kit.LocalScreenTicking
import com.yehsung.aingcheck.ui.theme.AingTheme
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
@OptIn(ExperimentalTestApi::class)
class ImeReplayDeviceTest {
    @get:Rule
    val compose = createComposeRule()

    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private lateinit var app: DeviceApp
    private val recorder = ImeRecorder()
    private val recording: ImeRecording = Json.decodeFromString(ImeRecording.serializer(), ImeRecordings.GBOARD_KO)

    @Before
    fun setUp() {
        instrumentation.runOnMainSync {
            app = DeviceApp(instrumentation.targetContext.filesDir)
            app.scope.launch {
                app.session.launch()
                app.session.signIn("me@stub.invalid", "pw-123456")
            }
        }
        compose.waitUntil(15_000) { app.session.isSignedIn }
    }

    @After
    fun tearDown() {
        instrumentation.runOnMainSync { app.close() }
    }

    private fun field(): String =
        compose.onNodeWithTag(MessagesTags.COMPOSER_FIELD).fetchSemanticsNode().config.getOrElseNullable(SemanticsProperties.EditableText) { null }?.text
            ?: error("입력칸 글을 못 읽었다")

    /** 녹화의 연결 번호 [recorded] 에 맞는 지금의 연결(입력을 다시 시작했으면 새 연결이 올 때까지 잠깐 기다린다). */
    private fun connectionFor(recorded: Int, offset: Int): InputConnection {
        val wanted = recorded + offset
        val until = System.currentTimeMillis() + 3_000
        while (recorder.connections.size <= wanted && System.currentTimeMillis() < until) {
            compose.waitForIdle()
            Thread.sleep(50)
        }
        return recorder.connections.getOrNull(wanted) ?: recorder.current ?: error("입력 연결이 없다")
    }

    private fun replay(calls: List<ImeCall>, offset: Int) {
        for (call in calls) {
            val ic = connectionFor(call.conn, offset)
            var thrown: Throwable? = null
            instrumentation.runOnMainSync { thrown = runCatching { ImeReplayer.apply(call, ic) }.exceptionOrNull() }
            assertEquals("재생 중 예외: $call", null, thrown)
            compose.waitForIdle()
        }
    }

    @Test
    fun recordedGboardKoreanCallsSendWholeTextAndLeaveFieldEmpty() {
        assertTrue("녹화가 한국어 두벌식이 아니다(${recording.ime} ${recording.subtype})", recording.korean)
        assertTrue("녹화 장면이 다섯이 아니다", recording.scenarios.size == 5)
        compose.setContent {
            AingTheme(dark = false) {
                CompositionLocalProvider(LocalScreenTicking provides false) {
                    ImeProbe(recorder) { ConversationScreen(app.messages, StubPeople.HANGYEOL, onBack = {}) }
                }
            }
        }
        compose.waitUntil(15_000) { compose.onAllNodesWithTag(MessagesTags.COMPOSER_FIELD).fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithTag(MessagesTags.COMPOSER_FIELD).performClick()
        compose.waitUntil(15_000) { recorder.current != null }

        for (scenario in recording.scenarios) {
            assertEquals("${scenario.name}: 시작 칸이 비어 있지 않다", "", field())
            val sendAt = scenario.calls.indexOfFirst { it.op == "#send" }
            assertTrue("${scenario.name}: 녹화에 #send 가 없다", sendAt > 0)
            val first = scenario.calls.first { !it.op.startsWith("#") }
            // 녹화의 첫 연결 = 지금 마지막 연결(장면마다 보내기가 입력을 다시 시작한다).
            val offset = (recorder.connections.size - 1) - first.conn
            if (scenario.prefill.isNotEmpty()) compose.onNodeWithTag(MessagesTags.COMPOSER_FIELD).performTextInput(scenario.prefill)
            val typing = scenario.calls.subList(0, sendAt).filter { !it.op.startsWith("#") }
            replay(typing, offset)
            assertEquals("${scenario.name}: 재생한 칸 글", scenario.fieldBeforeSend, field())
            val sentBefore = app.server.rpcCalls("send_message").size
            compose.onNodeWithTag(MessagesTags.SEND).performClick()
            compose.waitUntil(15_000) { app.server.rpcCalls("send_message").size == sentBefore + 1 }
            assertEquals("${scenario.name}: 보낸 글", scenario.sentBody, app.server.rpcCalls("send_message").last().field("p_body"))
            // 녹화된 뒤따름 호출(키보드가 보내기 뒤에 보낸 것)까지 재생해도 칸은 빈 채다.
            replay(scenario.calls.drop(sendAt + 1).filter { !it.op.startsWith("#") }, offset)
            compose.waitForIdle()
            assertEquals("${scenario.name}: 비운 칸에 글자가 되살아났다", "", field())
            println("AINGCHECK-IME-REPLAY scenario=${scenario.name} calls=${typing.size} composingAtSend=${scenario.composingAtSend} body=ok")
        }
        assertTrue("녹화의 '조합 중 보내기' 장면이 조합 중이 아니었다", recording.scenarios.single { it.name == "send-while-composing" }.composingAtSend)
    }
}
