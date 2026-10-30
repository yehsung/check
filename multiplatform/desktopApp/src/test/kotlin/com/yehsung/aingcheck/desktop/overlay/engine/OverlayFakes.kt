package com.yehsung.aingcheck.desktop.overlay.engine

import com.yehsung.aingcheck.character.player.WakeKind
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.models.PokeKind
import com.yehsung.aingcheck.feature.desktop.socialapi.MessageBubbleInbox
import com.yehsung.aingcheck.feature.desktop.socialapi.QueuedBubbleMessage
import com.yehsung.aingcheck.feature.desktop.socialapi.ReceivedPoke
import kotlin.math.ceil
import kotlin.random.Random

/** 합성 픽스처만(실제 홈·로그·계정 0). */
class FakeSink(var characterId: String = "aing") : CharacterSink {
    val calls = ArrayList<String>()
    override val currentCharacterId: String get() = characterId
    override fun play(reaction: String, now: Double): Boolean { calls += "play:$reaction"; return true }
    override fun interrupt(now: Double) { calls += "interrupt" }
    override fun beginSleep(now: Double): Boolean { calls += "beginSleep"; return true }
    override fun wake(kind: WakeKind, now: Double): Boolean { calls += "wake:${kind.name}"; return true }
    override fun blink(now: Double): Boolean { calls += "blink"; return true }
    override fun setEyesClosed(closed: Boolean) { calls += "eyes:$closed" }
    override fun setFacing(direction: Int, moving: Boolean, now: Double) { calls += "facing:$direction,$moving" }
    override fun swapCharacter(id: String?, now: Double) { calls += "swap:$id"; characterId = id ?: "aing" }
    override fun setSuspended(value: Boolean, now: Double): Boolean { calls += "suspended:$value"; return true }
    fun clear() = calls.clear()
}

/**
 * 가짜 측정기 — 한글·CJK 10pt, 그 밖 글자 5.5pt, 공백 3pt, 이모지(보조 평면) 12pt.
 * 줄 수는 낱말 단위 탐욕 줄바꿈(낱말이 한 줄보다 길면 글자 단위로 넘친다).
 */
class FakeMeasure(private val hangul: Double = 10.0, private val latin: Double = 5.5) : BubbleTextMeasure {
    val widthCalls = ArrayList<String>()
    private fun charWidth(cp: Int): Double = when {
        cp == ' '.code -> 3.0
        cp > 0xFFFF -> 12.0
        cp in 0xFE00..0xFE0F || cp == 0x200D -> 0.0
        BubbleForm.isCjk(cp.toChar()) -> hangul
        Character.isWhitespace(cp) -> 0.0
        else -> latin
    }
    override fun width(t: String): Double { widthCalls += t; return t.codePoints().toArray().sumOf { charWidth(it) } }
    override fun lineCount(t: String, widthPt: Double): Int {
        if (t.isEmpty()) return 0
        var lines = 1
        var cur = 0.0
        for (word in t.split(' ')) {
            val w = word.codePoints().toArray().sumOf { charWidth(it) }
            val add = if (cur == 0.0) w else cur + 3.0 + w
            if (add <= widthPt) { cur = add; continue }
            if (cur > 0.0) { lines += 1; cur = 0.0 }
            if (w > widthPt) { lines += (ceil(w / widthPt).toInt() - 1); cur = w - (ceil(w / widthPt) - 1) * widthPt } else cur = w
        }
        return lines
    }
}

class FakeInbox : MessageBubbleInbox {
    val queue = ArrayDeque<QueuedBubbleMessage>()
    var consumed = 0
    override val current: QueuedBubbleMessage? get() = queue.firstOrNull()
    override fun consumeCurrent() { if (queue.isNotEmpty()) { queue.removeFirst(); consumed += 1 } }
    fun add(id: String, name: String, body: String, from: String? = "u-$id") {
        queue.addLast(QueuedBubbleMessage(id, name, body, SwiftDate.fromEpochMillis(0), fromUserID = from))
    }
}

class FakeBoard(var enabled: Boolean = false) : BoardHost {
    var open = false
    val calls = ArrayList<String>()
    override fun isEnabled(): Boolean = enabled
    override fun isOpen(): Boolean = open
    override fun toggle(anchor: OverlayRect, work: OverlayRect) { open = !open; calls += "toggle:$open" }
    override fun reposition(anchor: OverlayRect, work: OverlayRect) { calls += "reposition" }
    override fun close() { open = false; calls += "close" }
    override fun facing(): Int = if (open) -1 else 0
}

object Mon {
    val primary = MonitorInfo("DISPLAY1", OverlayRect(0.0, 0.0, 1920.0, 1080.0), OverlayRect(0.0, 0.0, 1920.0, 1040.0), primary = true)
    val second = MonitorInfo("DISPLAY2", OverlayRect(1920.0, 0.0, 2560.0, 1440.0), OverlayRect(1920.0, 0.0, 2560.0, 1400.0))
}

fun poke(id: String, name: String, kind: PokeKind = PokeKind.normal, character: String? = null) =
    ReceivedPoke(id, name, SwiftDate.fromEpochMillis(0), kind, character)

class Fixture(seed: Int = 7, boardEnabled: Boolean = false) {
    val sink = FakeSink()
    val measure = FakeMeasure()
    val inbox = FakeInbox()
    val board = FakeBoard(boardEnabled)
    val d = OverlayDirector(sink, measure, inbox, board, Random(seed))
    init {
        d.onMonitors(listOf(Mon.primary, Mon.second))
        d.onSurfaceFrame(OverlayGeometry.defaultFrame(Mon.primary.work))
    }
    /** 근무 중·캐릭터 켬 상태로 만들고 출근 리액션이 끝난 시각을 돌려준다. */
    fun working(now: Double = 0.0): Double {
        d.onWorking(isWorking = true, overlayEnabled = true, now = now)
        return now + 10.0
    }
}
