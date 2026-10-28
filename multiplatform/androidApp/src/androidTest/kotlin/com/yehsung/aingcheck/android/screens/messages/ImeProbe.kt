// 원본: 없음 — E§8.3 IME 호출열 녹화·재생(에뮬레이터 헤드리스). iOS 짝 없음(iOS 는 UITextView 로 marked text 를 직접 본다).
//
// 입력줄 칸의 InputConnection 을 감싸 키보드(IME)가 부른 것을 차례대로 적는다(setComposingText · commitText · finishComposingText ·
// deleteSurroundingText · setComposingRegion · setSelection · sendKeyEvent · 일괄 편집). 감싸는 자리는 Compose 의 공식 가로채기
// (InterceptPlatformTextInput) — 앱 코드(입력줄)는 녹화기를 모른다. 녹화(Gboard 실기)는 ImeGboardLiveDeviceTest, 재생은 ImeReplayDeviceTest.
package com.yehsung.aingcheck.android.screens.messages

import android.view.KeyEvent
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputConnection
import android.view.inputmethod.InputConnectionWrapper
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.platform.InterceptPlatformTextInput
import androidx.compose.ui.platform.PlatformTextInputInterceptor
import androidx.compose.ui.platform.PlatformTextInputMethodRequest
import kotlinx.serialization.Serializable
import java.util.concurrent.CopyOnWriteArrayList

/**
 * IME 호출 한 건. [conn] = 이 녹화에서 몇 번째 연결인가(0부터 — 입력을 다시 시작하면 새 연결). 표식(`#…`)은 시험이 남긴 줄이다:
 * `#scenario`(text = 이름) · `#prefill`(text = 시험이 IME 를 거치지 않고 넣은 글) · `#send`([보내기]를 누른 자리) · `#end`.
 */
@Serializable
data class ImeCall(val conn: Int, val op: String, val text: String? = null, val a: Int = 0, val b: Int = 0)

/** 녹화기: 호출 목록 + 연결 목록(차례). 메인 스레드·바인더 스레드에서 같이 쓴다. */
class ImeRecorder {
    val calls = CopyOnWriteArrayList<ImeCall>()
    val connections = CopyOnWriteArrayList<InputConnection>()

    val current: InputConnection? get() = connections.lastOrNull()

    fun add(call: ImeCall) {
        calls += call
    }

    fun mark(op: String, text: String? = null) = add(ImeCall(maxOf(0, connections.size - 1), op, text))

    /** 표식 [from] 뒤 호출만(표식 제외). */
    fun callsSince(index: Int): List<ImeCall> = calls.drop(index).filter { !it.op.startsWith("#") }
}

/** 감싼 InputConnection — 적고 나서 그대로 넘긴다(결과는 원본의 것). */
class RecordingInputConnection(target: InputConnection, private val conn: Int, private val sink: (ImeCall) -> Unit) : InputConnectionWrapper(target, false) {
    override fun setComposingText(text: CharSequence?, newCursorPosition: Int): Boolean {
        sink(ImeCall(conn, "setComposingText", text?.toString(), newCursorPosition))
        return super.setComposingText(text, newCursorPosition)
    }

    override fun commitText(text: CharSequence?, newCursorPosition: Int): Boolean {
        sink(ImeCall(conn, "commitText", text?.toString(), newCursorPosition))
        return super.commitText(text, newCursorPosition)
    }

    override fun finishComposingText(): Boolean {
        sink(ImeCall(conn, "finishComposingText"))
        return super.finishComposingText()
    }

    override fun deleteSurroundingText(beforeLength: Int, afterLength: Int): Boolean {
        sink(ImeCall(conn, "deleteSurroundingText", null, beforeLength, afterLength))
        return super.deleteSurroundingText(beforeLength, afterLength)
    }

    override fun deleteSurroundingTextInCodePoints(beforeLength: Int, afterLength: Int): Boolean {
        sink(ImeCall(conn, "deleteSurroundingTextInCodePoints", null, beforeLength, afterLength))
        return super.deleteSurroundingTextInCodePoints(beforeLength, afterLength)
    }

    override fun setComposingRegion(start: Int, end: Int): Boolean {
        sink(ImeCall(conn, "setComposingRegion", null, start, end))
        return super.setComposingRegion(start, end)
    }

    override fun setSelection(start: Int, end: Int): Boolean {
        sink(ImeCall(conn, "setSelection", null, start, end))
        return super.setSelection(start, end)
    }

    override fun sendKeyEvent(event: KeyEvent?): Boolean {
        if (event != null) sink(ImeCall(conn, "sendKeyEvent", null, event.action, event.keyCode))
        return super.sendKeyEvent(event)
    }

    override fun beginBatchEdit(): Boolean {
        sink(ImeCall(conn, "beginBatchEdit"))
        return super.beginBatchEdit()
    }

    override fun endBatchEdit(): Boolean {
        sink(ImeCall(conn, "endBatchEdit"))
        return super.endBatchEdit()
    }
}

/** [content] 안의 입력칸이 여는 InputConnection 을 감싼다. */
@OptIn(ExperimentalComposeUiApi::class)
@Composable
fun ImeProbe(recorder: ImeRecorder, content: @Composable () -> Unit) {
    val interceptor = remember(recorder) {
        PlatformTextInputInterceptor { request, nextHandler ->
            nextHandler.startInputMethod(object : PlatformTextInputMethodRequest {
                override fun createInputConnection(outAttributes: EditorInfo): InputConnection {
                    val base = request.createInputConnection(outAttributes)
                    val wrapped = RecordingInputConnection(base, recorder.connections.size, recorder::add)
                    recorder.connections += wrapped
                    return wrapped
                }
            })
        }
    }
    InterceptPlatformTextInput(interceptor, content)
}

/** 기록 한 건을 InputConnection 에 그대로 건다(재생). 표식은 무시한다. */
object ImeReplayer {
    fun apply(call: ImeCall, ic: InputConnection): Boolean = when (call.op) {
        "setComposingText" -> ic.setComposingText(call.text ?: "", call.a)
        "commitText" -> ic.commitText(call.text ?: "", call.a)
        "finishComposingText" -> ic.finishComposingText()
        "deleteSurroundingText" -> ic.deleteSurroundingText(call.a, call.b)
        "deleteSurroundingTextInCodePoints" -> ic.deleteSurroundingTextInCodePoints(call.a, call.b)
        "setComposingRegion" -> ic.setComposingRegion(call.a, call.b)
        "setSelection" -> ic.setSelection(call.a, call.b)
        "sendKeyEvent" -> ic.sendKeyEvent(KeyEvent(call.a, call.b))
        "beginBatchEdit" -> ic.beginBatchEdit()
        "endBatchEdit" -> ic.endBatchEdit()
        else -> error("모르는 IME 호출: ${call.op}")
    }
}

/** 한 장면(녹화 파일의 한 덩어리). */
@Serializable
data class ImeScenario(
    val name: String,
    /** `adb input text` 로 친 글쇠(Gboard 두벌식이면 한글이 된다). */
    val keys: String,
    /** IME 를 거치지 않고 미리 넣은 글(경계 시험). */
    val prefill: String = "",
    /** [보내기] 직전 칸 글. */
    val fieldBeforeSend: String,
    /** 서버로 나간 본문. */
    val sentBody: String,
    /** [보내기] 순간 조합 중이었는가(녹화의 마지막 IME 호출이 setComposingText 이고 그 뒤 확정이 없다). */
    val composingAtSend: Boolean,
    val calls: List<ImeCall>,
)

@Serializable
data class ImeRecording(val ime: String, val subtype: String, val korean: Boolean, val sdk: Int, val scenarios: List<ImeScenario>)
