// 원본: Sources/CheckMobileKit/Messages/MessagesComposerView.swift @ 3bd04bd (★ 한글 조합 중에는 보내지 않는다 — 확정한 뒤 보낸다)
//
// G §2-3 W3-a ③④ · E§8.3: 기기의 **진짜 키보드(Gboard)** 로 입력줄에 친다(`adb input text` 글쇠 — Gboard 두벌식이면 IME 가 한글로 조합한다).
// 공용 한국어 AVD(aingcheck-api36-ko · emu.sh ko-check 준비 상태)에서는 한글 기대값을, 그 밖의 기기(공용 api36 — Gboard 영문)에서는 친 글쇠
// 그대로를 기대한다 — 어느 쪽이든 "보낸 글 = 기대 글 · 비운 뒤 빈칸 유지 · 예외 0 · 상한에서 자르지 않음"을 잰다.
// 같이 IME 호출열을 녹화해(ImeProbe) 파일과 로그(AINGCHECK-IME-REC)로 낸다 — 한국어 녹화가 재생 시험(ImeReplayDeviceTest)의 픽스처다.
package com.yehsung.aingcheck.android.screens.messages

import android.os.Build
import android.os.ParcelFileDescriptor
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
import androidx.compose.runtime.CompositionLocalProvider
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

@RunWith(AndroidJUnit4::class)
@OptIn(ExperimentalTestApi::class)
class ImeGboardLiveDeviceTest {
    @get:Rule
    val compose = createComposeRule()

    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    private lateinit var app: DeviceApp
    private val recorder = ImeRecorder()

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

    private fun shell(command: String): String {
        val pfd = instrumentation.uiAutomation.executeShellCommand(command)
        return ParcelFileDescriptor.AutoCloseInputStream(pfd).bufferedReader().use { it.readText() }.trim()
    }

    private fun field(): String =
        compose.onNodeWithTag(MessagesTags.COMPOSER_FIELD).fetchSemanticsNode().config.getOrElseNullable(SemanticsProperties.EditableText) { null }?.text
            ?: error("입력칸 글을 못 읽었다")

    private fun counter(): String? = compose.onAllNodesWithTag(MessagesTags.COUNTER, useUnmergedTree = true).fetchSemanticsNodes().firstOrNull()
        ?.config?.getOrElseNullable(SemanticsProperties.Text) { null }?.joinToString("") { it.text }

    /** 칸 글이 [expected] 가 될 때까지(Gboard 는 글쇠를 비동기로 조합한다). 시한 안에 안 되면 지금 글을 돌려준다. */
    private fun awaitField(expected: String, timeout: Long = 10_000): String {
        val until = System.currentTimeMillis() + timeout
        while (System.currentTimeMillis() < until) {
            compose.waitForIdle()
            if (field() == expected) return expected
            Thread.sleep(150)
        }
        return field()
    }

    /** 친 글쇠를 기기 키보드로 보낸다. 공백은 %s. */
    private fun type(keys: String) {
        shell("input text $keys")
        compose.waitForIdle()
    }

    private fun backspace() {
        shell("input keyevent 67")
        compose.waitForIdle()
    }

    /** [deletesKo] · [deletesLatin] = 보내기 전 지우기 횟수(두벌식은 조합 중 지우기가 자모 하나 · 영문은 글자 하나). */
    private data class Plan(
        val name: String, val keys: String, val prefill: String, val deletesKo: Int, val deletesLatin: Int,
        val korean: String, val latin: String, val overflowFirst: Boolean = false,
    )

    @Test
    fun gboardTypingSendsWholeTextAndLeavesFieldEmpty() {
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

        val ime = shell("settings get secure default_input_method")
        val subtype = shell("settings get secure selected_input_method_subtype")
        val korean = ime.startsWith(GBOARD) && subtype == KOREAN_DUBEOLSIK
        println("AINGCHECK-IME-LIVE ime=$ime subtype=$subtype korean=$korean sdk=${Build.VERSION.SDK_INT}")

        val prefill199 = "가".repeat(199)
        val plans = listOf(
            Plan("greet", "dkssudgktpdy%sdhahr%sgks%svks?", "", 0, 0, "안녕하세요 오목 한 판?", "dkssudgktpdy dhahr gks vks?"),
            Plan("kkk", "zzz", "", 0, 0, "ㅋㅋㅋ", "zzz"),
            Plan("double-final-delete", "dlfr", "", 1, 1, "일", "dlf"),
            Plan("send-while-composing", "dkssud", "", 0, 0, "안녕", "dkssud"),
            Plan("limit-200", "dkss", prefill199, 1, 3, prefill199 + "안", prefill199 + "d", overflowFirst = true),
        )
        val scenarios = mutableListOf<ImeScenario>()
        for (plan in plans) {
            assertEquals("${plan.name}: 시작 칸이 비어 있지 않다(앞 장면이 되살아났다)", "", field())
            val start = recorder.calls.size
            recorder.mark("#scenario", plan.name)
            if (plan.prefill.isNotEmpty()) {
                recorder.mark("#prefill", plan.prefill)
                compose.onNodeWithTag(MessagesTags.COMPOSER_FIELD).performTextInput(plan.prefill)
                awaitField(plan.prefill)
            }
            type(plan.keys)
            if (plan.overflowFirst) {
                // 상한 넘김: 조합 중에도 **자르지 않는다** — 칸은 201자 이상 그대로, 카운터는 넘침, [보내기]는 막힌다.
                val over = if (korean) plan.prefill + "안ㄴ" else plan.prefill + "dkss"
                assertEquals("${plan.name}: 상한을 넘긴 글이 잘렸다", over, awaitField(over))
                assertEquals("${plan.name}: 카운터", "${over.codePointCount(0, over.length)}/200", counter())
                val before = app.server.rpcCalls("send_message").size
                compose.onNodeWithTag(MessagesTags.SEND).performClick()
                compose.waitForIdle()
                Thread.sleep(300)
                assertEquals("${plan.name}: 넘친 글이 나갔다", before, app.server.rpcCalls("send_message").size)
                assertEquals("${plan.name}: 막힌 [보내기]가 칸을 건드렸다", over, field())
            }
            repeat(if (korean) plan.deletesKo else plan.deletesLatin) { backspace() }
            val expected = if (korean) plan.korean else plan.latin
            assertEquals("${plan.name}: 칸 글", expected, awaitField(expected))
            val beforeSend = recorder.callsSince(start)
            val composingAtSend = beforeSend.lastOrNull { it.op != "beginBatchEdit" && it.op != "endBatchEdit" && it.op != "setSelection" }?.op == "setComposingText"
            recorder.mark("#send")
            val sentBefore = app.server.rpcCalls("send_message").size
            compose.onNodeWithTag(MessagesTags.SEND).performClick()
            compose.waitUntil(15_000) { app.server.rpcCalls("send_message").size == sentBefore + 1 }
            val body = app.server.rpcCalls("send_message").last().field("p_body")
            assertEquals("${plan.name}: 보낸 글", expected.trim(), body)
            // 비운 뒤 빈칸 유지 — 조합 중이던 글자가 되살아나지 않는다(키보드가 새 연결에 무엇을 보내든).
            assertEquals("${plan.name}: 보낸 뒤 칸", "", awaitField(""))
            Thread.sleep(800)
            compose.waitForIdle()
            assertEquals("${plan.name}: 비운 칸에 글자가 되살아났다", "", field())
            recorder.mark("#end")
            val calls = recorder.calls.subList(start, recorder.calls.size).toList()
            scenarios += ImeScenario(plan.name, plan.keys, plan.prefill, expected, expected.trim(), composingAtSend, calls)
            println("AINGCHECK-IME-LIVE scenario=${plan.name} korean=$korean calls=${calls.count { !it.op.startsWith("#") }} composingAtSend=$composingAtSend")
        }
        if (korean) {
            // 한국어 두벌식이면 "조합 중 [보내기]" 장면이 진짜로 조합 중이었어야 한다(아니면 그 길을 재지 않은 것이다).
            assertTrue("send-while-composing: 보낼 때 조합 중이 아니었다", scenarios.single { it.name == "send-while-composing" }.composingAtSend)
            assertTrue("한글 조합 호출이 하나도 없다", scenarios.sumOf { s -> s.calls.count { it.op == "setComposingText" } } > 0)
        }
        val recording = ImeRecording(ime, subtype, korean, Build.VERSION.SDK_INT, scenarios)
        val text = Json.encodeToString(ImeRecording.serializer(), recording)
        val dir = File(instrumentation.targetContext.getExternalFilesDir(null), "ime").apply { mkdirs() }
        val out = File(dir, "gboard-${if (korean) "ko" else "latin"}.json")
        out.writeText(text)
        println("AINGCHECK-IME-REC file=${out.absolutePath} bytes=${text.length}")
        text.chunked(1800).forEachIndexed { i, chunk -> println("AINGCHECK-IME-REC ${i + 1}/${(text.length + 1799) / 1800} $chunk") }
    }

    private companion object {
        const val GBOARD = "com.google.android.inputmethod.latin/"
        /** Gboard 한국어 두벌식(emu.sh ko-check 와 같은 값). */
        const val KOREAN_DUBEOLSIK = "-1906255757"
    }
}
