// 원본: Tests/CheckMobileKitTests/WidgetSnapshotTests.swift · WidgetAILimitsTests.swift(생 JSON 호환 · 관대한 디코드 · 더하기만) ·
//       Sources/CheckMobileShared/WidgetSnapshot.swift @ 3bd04bd
// 디코더 INV 셋(0f12bb0d · 99e06a6c · f5226477 — "이 줄을 빼먹으면 컴파일은 통과하고 영원히 nil")은 **생 JSON** 으로만 잡힌다:
// 값 왕복 시험은 인코더·디코더가 같이 빠져도 초록이다. 그래서 Swift 가 쓴 꼴의 글자를 직접 읽는다.
package com.yehsung.aingcheck.feature.phone.widget

import com.yehsung.aingcheck.core.rules.ailimit.AILimitProvider
import com.yehsung.aingcheck.core.stores.me.MeAILimitWidgetPanel
import com.yehsung.aingcheck.core.stores.me.MeAILimitWidgetRow
import com.yehsung.aingcheck.core.wire.SwiftDate
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class WidgetSnapshotCodecTest {
    private fun ms(ms: Long) = SwiftDate.fromEpochMillis(ms)

    /** Swift `WidgetSnapshotCodec.encode`(sortedKeys · ms 날짜)가 쓰는 꼴 + 다음 판·옛 판·깨진 칸을 섞은 파일. */
    private val swiftShaped = """
        {"aiLimits":{"deviceName":"  Mac mini (A1B2)  ","deviceNameTail":" A1B2 ","providers":[
            {"fiveHourPercent":27.5,"fiveHourResetsAt":1789630500000,"observedAt":1789621400000,"provider":"claude","weeklyPercent":40,"weeklyResetsAt":1790000000000},
            {"observedAt":1789621400000,"provider":"gemini","fiveHourPercent":"높음"},
            {"provider":"codex"}],
          "recentTokens":120000,"todayTokens":-5},
         "characterID":"fox","generatedAt":1789621500000,
         "me":{"goalHours":40,"sessionStartedAt":1789608000000,"status":"disconnected","todaySeconds":18600,"weekSeconds":-3,"working":true},
         "todosPreview":[{"carryOverDays":2,"id":"t-1","isCompleted":false,"title":"리뷰"},{"title":"id 없음"},{"id":"t-3","carryOverDays":-1}],
         "version":1,
         "working":[{"center":"seoul","characterID":"aing","name":"민트","startedAt":1789607700000,"teammate":true},7,{"teammate":false}],
         "nextVersionField":{"anything":true}}
    """.trimIndent()

    @Test
    fun swiftShapedFileDecodesEveryFieldIncludingTheThreeDecoderLines() {
        val s = WidgetSnapshotCodec.decode(swiftShaped.encodeToByteArray())
        assertNotNull(s)
        assertEquals(1, s.version)
        assertEquals(ms(1_789_621_500_000), s.generatedAt)
        assertEquals("fox", s.characterID)
        // INV-WidgetSnapshot-f5226477: aiLimits 줄 — 빠지면 파일에 값이 있어도 영원히 null.
        val panel = assertNotNull(s.aiLimits, "aiLimits 칸을 디코더가 읽어야 한다")
        // INV-WidgetSnapshot-0f12bb0d: deviceName 줄 · INV-WidgetSnapshot-281daaa3: 합친 한 글자 그대로(공백만 걷는다).
        assertEquals("Mac mini (A1B2)", panel.deviceName, "deviceName 칸을 디코더가 읽어야 한다")
        // INV-WidgetSnapshot-99e06a6c: deviceNameTail 줄 — 꼬리는 따로 선다.
        assertEquals("A1B2", panel.deviceNameTail, "deviceNameTail 칸을 디코더가 읽어야 한다")
        assertEquals(0L, panel.todayTokens, "음수 토큰은 0 으로")
        assertEquals(120_000L, panel.recentTokens)
        // 깨진 제공자 줄(observedAt 없음)만 버리고 나머지는 산다. 퍼센트 칸 하나가 글자여도 그 칸만 null.
        assertEquals(listOf("claude", "gemini"), panel.providers.map { it.provider })
        val claude = panel.providers[0]
        assertEquals(27.5, claude.fiveHourPercent)
        assertEquals(ms(1_789_630_500_000), claude.fiveHourResetsAt)
        assertEquals(40.0, claude.weeklyPercent)
        assertNull(panel.providers[1].fiveHourPercent)

        val me = assertNotNull(s.me)
        assertEquals(WidgetSnapshot.WorkState.disconnected, me.status)
        assertEquals(WidgetSnapshot.WorkState.disconnected, me.resolvedStatus)
        assertEquals(0, me.weekSeconds, "음수 누적은 0 으로")
        assertEquals(ms(1_789_608_000_000), me.sessionStartedAt)

        assertEquals(listOf("t-1", "t-3"), s.todosPreview.map { it.id }, "id 없는 할 일만 버린다")
        assertEquals(WidgetSnapshot.TodoPreview("t-3", "", false, 0), s.todosPreview[1], "빠진 칸은 기본값 · 음수 이월은 0")
        assertEquals(listOf("민트", "사용자"), s.working.map { it.name }, "객체가 아닌 원소는 버리고, 이름 없는 사람은 '사용자'")
        assertEquals(WidgetSnapshot.WorkingPerson("민트", "seoul", true, ms(1_789_607_700_000), "aing"), s.working[0])
    }

    @Test
    fun readerDropsUnknownProviderInsteadOfFoldingIntoClaude() {
        // INV-WidgetSnapshot-c1b06494(소비 쪽): 모르는 제공자는 버린다 — 지어내 claude 로 접으면 남의 사용률이 내 Claude 줄에 그려진다.
        val panel = WidgetSnapshotCodec.decode(swiftShaped.encodeToByteArray())!!.aiLimits!!
        val known = panel.knownProviderRows()
        assertEquals(listOf(AILimitProvider.claude), known.map { it.first })
        assertEquals(27.5, known.single().second.fiveHourPercent)
    }

    @Test
    fun brokenOrForeignFilesAreLoggedOutNotCrashes() {
        assertNull(WidgetSnapshotCodec.decode("".encodeToByteArray()))
        assertNull(WidgetSnapshotCodec.decode("{".encodeToByteArray()))
        assertNull(WidgetSnapshotCodec.decode("[]".encodeToByteArray()))
        assertNull(WidgetSnapshotCodec.decode("""{"generatedAt":1}""".encodeToByteArray()), "version 이 없으면 못 읽는다")
        assertNull(WidgetSnapshotCodec.decode("""{"version":0,"generatedAt":1}""".encodeToByteArray()), "version 0 은 받지 않는다")
        assertNull(WidgetSnapshotCodec.decode("""{"version":1}""".encodeToByteArray()), "generatedAt 이 없으면 못 읽는다")
        assertNull(WidgetSnapshotCodec.decode("""{"version":1,"generatedAt":"2026-09-17"}""".encodeToByteArray()), "날짜는 ms 수")
        // 칸 하나의 모양이 틀려도(me 가 수 · working 이 객체) 스냅숏 전체는 산다.
        val tolerant = WidgetSnapshotCodec.decode("""{"version":2,"generatedAt":1000,"me":5,"working":{"a":1},"todosPreview":null,"aiLimits":[]}""".encodeToByteArray())
        assertNotNull(tolerant)
        assertEquals(2, tolerant.version, "뜻이 바뀐 다음 판(2)도 1 이상이면 받는다")
        assertNull(tolerant.me)
        assertEquals(emptyList(), tolerant.working)
        assertNull(tolerant.aiLimits)
    }

    @Test
    fun oldSnapshotWithoutStatusReadsWorkingFlagAndFlagWinsOverStatus() {
        val old = WidgetSnapshotCodec.decode("""{"version":1,"generatedAt":1000,"me":{"working":true,"todaySeconds":10,"weekSeconds":20,"goalHours":40}}""".encodeToByteArray())!!
        val oldMe = assertNotNull(old.me)
        assertNull(oldMe.status)
        assertEquals(WidgetSnapshot.WorkState.working, oldMe.resolvedStatus)
        val contradicting = WidgetSnapshot.Me(false, null, 0, 0, 40, WidgetSnapshot.WorkState.disconnected)
        assertEquals(WidgetSnapshot.WorkState.off, contradicting.resolvedStatus, "근무 안 함인데 '연결 끊김'을 그리지 않는다")
        val unknown = WidgetSnapshotCodec.decode("""{"version":1,"generatedAt":1000,"me":{"working":true,"status":"onBreak"}}""".encodeToByteArray())!!
        assertNull(unknown.me!!.status, "모르는 상태는 null(깃발로 읽는다)")
    }

    @Test
    fun encodeIsSortedOmitsNullsAndRoundTrips() {
        val snapshot = WidgetSnapshot(
            generatedAt = ms(1_789_621_500_000),
            me = WidgetSnapshot.Me(true, ms(1_789_608_000_123), 18_600, 89_280, 40, WidgetSnapshot.WorkState.working),
            working = listOf(WidgetSnapshot.WorkingPerson("라임", null, false, null, null)),
            todosPreview = listOf(WidgetSnapshot.TodoPreview("t-1", "리뷰", true, 1)),
            characterID = null,
            aiLimits = MeAILimitWidgetPanel(
                providers = listOf(MeAILimitWidgetRow("codex", 12.0, null, null, null, ms(1_789_621_000_000))),
                deviceName = "Mac mini (A1B2)",
                deviceNameTail = "A1B2",
                todayTokens = 7,
            ),
        )
        val text = WidgetSnapshotCodec.encode(snapshot).decodeToString()
        assertEquals(
            """{"aiLimits":{"deviceName":"Mac mini (A1B2)","deviceNameTail":"A1B2","providers":[{"fiveHourPercent":12.0,"observedAt":1789621000000,"provider":"codex"}],"todayTokens":7},""" +
                """"generatedAt":1789621500000,"me":{"goalHours":40,"sessionStartedAt":1789608000123,"status":"working","todaySeconds":18600,"weekSeconds":89280,"working":true},""" +
                """"todosPreview":[{"carryOverDays":1,"id":"t-1","isCompleted":true,"title":"리뷰"}],"version":1,"working":[{"name":"라임","teammate":false}]}""",
            text,
            "키 정렬 · null 칸 생략 · ms 정수(Swift .sortedKeys · .millisecondsSince1970)",
        )
        assertEquals(snapshot, WidgetSnapshotCodec.decode(text.encodeToByteArray()))
        assertTrue(snapshot.working[0].id.startsWith("o:라임:"), "목록 id 는 직렬화하지 않는 계산 값")
    }
}
