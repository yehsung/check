// W2-g5 골든 대조 — Swift Tests/checkTests/GoldenExport/desktop-work-state/GoldenExportDesktopWorkState.swift 가 낸
// contract/golden/desktop-work-state/ownership.json 의 장면을 DesktopWorkStore 로 그대로 밟아 덤프가 바이트 값까지 같은지 잰다.
// (SessionOwnershipTests · AdoptedSessionStoreTests · V0236SyncTests 의 장면 — 지시서 work.md §5 ws)
package com.yehsung.aingcheck.feature.desktop.work.state

import com.yehsung.aingcheck.feature.desktop.work.AutoCloseReason
import com.yehsung.aingcheck.feature.desktop.work.PendingWorkOperation
import com.yehsung.aingcheck.feature.desktop.work.WorkStartOrigin
import com.yehsung.aingcheck.core.wire.models.StatusDeviceClaim
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.testkit.golden.Golden
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class DesktopWorkStateGoldenTest {
    private val golden = Golden.load("desktop-work-state/ownership")

    private fun off(date: SwiftDate?): JsonElement = date?.let { JsonPrimitive(it.timeIntervalSince(T0).toLong()) } ?: JsonNull
    private fun str(value: String?, start: String?): JsonElement = when {
        value == null -> JsonNull
        start != null && value == start -> JsonPrimitive("\$start")
        else -> JsonPrimitive(value)
    }

    /** Swift dump(_:gen0:start:) 와 같은 키·같은 값. */
    private fun dump(r: WorkStateRig, gen0: Int, start: String?): JsonObject {
        val s = r.store
        val snap = s.snapshot.value
        val items = r.queue.items.value.map { item ->
            val op = item.operation
            JsonObject(
                mapOf(
                    "sessionID" to str(item.sessionId, start),
                    "sessionStartedAt" to off(item.sessionStartedAt),
                    "endedAt" to off(item.endedAt),
                    "owner" to (item.ownerUserId?.let { JsonPrimitive(it) } ?: JsonNull),
                    "reason" to (item.autoCloseReason?.let { JsonPrimitive(it.raw) } ?: JsonNull),
                    "op" to JsonPrimitive(if (op is PendingWorkOperation.Stop) "stop" else "start"),
                    "duration" to (if (op is PendingWorkOperation.Stop) JsonPrimitive(op.durationSeconds) else JsonNull),
                ),
            )
        }
        val last = snap.lastAutoClose?.let {
            JsonObject(mapOf("reason" to JsonPrimitive(it.reason.raw), "endedAt" to off(it.endedAt), "seconds" to JsonPrimitive(it.seconds)))
        } ?: JsonNull
        return JsonObject(
            mapOf(
                "working" to JsonPrimitive(s.startedAt != null),
                "startedAt" to off(s.startedAt),
                "sessionID" to str(snap.sessionId, start),
                "sessionIDIsLowercase" to JsonPrimitive(s.currentSessionId?.let { it == it.lowercase() } ?: true),
                "confirmedSessionID" to str(s.confirmedSessionId, start),
                "adopted" to JsonPrimitive(s.adoptedRemoteSession),
                "ownsStrongly" to JsonPrimitive(s.ownsCurrentSessionStrongly),
                "ownedIDStored" to str(r.kv.getString(OwnedSessionLedger.OWNED_ID_KEY), start),
                "ownedStrengthStored" to (r.kv.getString(OwnedSessionLedger.OWNED_STRENGTH_KEY)?.let { JsonPrimitive(it) } ?: JsonNull),
                "generationDelta" to JsonPrimitive(s.workStateWriteGeneration - gen0),
                "items" to JsonArray(items),
                "lastAutoClose" to last,
            ),
        )
    }

    private fun startAt(r: WorkStateRig, offset: Int = 0): String? {
        r.store.start(WorkStartOrigin.MANUAL, at(offset))
        return r.store.currentSessionId
    }

    private fun yieldScene(device: String, own: SessionClaimStrength, claimDevice: String, claimOpened: Boolean): (WorkStateRig) -> String? = { r ->
        r.own(SESSION_S, own)
        listOf(at(-20), at(-20), at(10)).forEachIndexed { i, seen ->
            val claims = if (i == 0) emptyList() else listOf(StatusDeviceClaim(claimDevice, SESSION_S, seen, claimOpened))
            r.apply(working(SESSION_S, at(-3_600), at(-10), claims))
        }
        null
    }

    /** 장면 id → (기기 id, 단계). Swift 쪽 cases.append 순서와 같다. */
    private val scenes: List<Triple<String, String?, (WorkStateRig) -> String?>> = listOf(
        Triple("start", null) { r -> startAt(r) },
        Triple("start-stop", null) { r -> startAt(r).also { r.queue.drain(); r.store.stop(at(5_400)) } },
        Triple("restart-uppercase-rescue", null) { r ->
            r.kv.putString(OwnedSessionLedger.OWNED_ID_KEY, SESSION_S.uppercase())
            r.kv.putString(OwnedSessionLedger.OWNED_STRENGTH_KEY, "strong")
            r.apply(working(SESSION_S, at(-3 * 3_600), at(-20)))
            null
        },
        Triple("adopt-foreign", null) { r -> r.apply(working(SESSION_X, at(-600), at(-15))); null },
        Triple("late-response-dropped", null) { r ->
            val stale = r.store.workStateWriteGeneration
            startAt(r).also { r.queue.drain(); r.apply(offWork(0, at(-30)), stale) }
        },
        Triple("server-closed-a-live", null) { r ->
            startAt(r).also { id ->
                r.queue.drain()
                r.policy.marker = SleepCloseMarker(id!!, T0, at(3_600), at(3_000))
                r.now = at(7_200)
                r.apply(offWork(0, at(3_600)))
            }
        },
        Triple("server-closed-b-relaunch", null) { r ->
            r.own(SESSION_S, SessionClaimStrength.STRONG)
            r.policy.marker = SleepCloseMarker(SESSION_S, at(-7_200), at(-3_600), null)
            r.apply(offWork(0, at(-3_600)))
            null
        },
        Triple("remote-abandoned", null) { r ->
            startAt(r).also { r.queue.drain(); r.now = at(3_600); r.apply(offWork(2_900, at(2_900))) }
        },
        Triple("remote-ended-elsewhere", null) { r ->
            startAt(r).also { r.queue.drain(); r.now = at(3_600); r.apply(offWork(3_500, at(3_500))) }
        },
        Triple("stamp-c-then-adopt", null) { r ->
            startAt(r).also { id ->
                r.queue.drain()
                r.store.setConfirmedServerSessionId(id)
                r.apply(working(SESSION_X, at(60), at(90)))
            }
        },
        Triple("auto-close-sleep", null) { r ->
            startAt(r).also {
                r.queue.drain()
                r.store.closeOwnedSessionLocally(at(1_800), AutoCloseReason.SLEEP, WorkStateConstants.SLEEP_CLOSE_MESSAGE)
            }
        },
        Triple("auto-close-adopted-noop", null) { r ->
            r.apply(working(SESSION_X, at(-600), at(-15)))
            r.store.closeOwnedSessionLocally(T0, AutoCloseReason.SLEEP, WorkStateConstants.SLEEP_CLOSE_MESSAGE)
            null
        },
        Triple("yield-weak-win-vs-weak-mac", WIN_DEVICE, yieldScene(WIN_DEVICE, SessionClaimStrength.WEAK, MAC_DEVICE, false)),
        Triple("yield-weak-mac-vs-weak-win", MAC_DEVICE, yieldScene(MAC_DEVICE, SessionClaimStrength.WEAK, WIN_DEVICE, false)),
        Triple("yield-strong-win-vs-weak-mac", WIN_DEVICE, yieldScene(WIN_DEVICE, SessionClaimStrength.STRONG, MAC_DEVICE, false)),
        Triple("yield-weak-win-vs-strong-mac", WIN_DEVICE, yieldScene(WIN_DEVICE, SessionClaimStrength.WEAK, MAC_DEVICE, true)),
        Triple("yield-strong-mac-vs-strong-win", MAC_DEVICE, yieldScene(MAC_DEVICE, SessionClaimStrength.STRONG, WIN_DEVICE, true)),
    )

    private fun run(id: String): JsonObject {
        val (_, device, steps) = scenes.first { it.first == id }
        val r = WorkStateRig(deviceId = device)
        val gen0 = r.store.workStateWriteGeneration
        val start = steps(r)
        return dump(r, gen0, start)
    }

    @Test
    fun everySwiftSceneHasAKotlinSceneAndViceVersa() {
        val swiftIds = golden.cases.map { it["id"]!!.jsonPrimitive.content }
        assertEquals(swiftIds, scenes.map { it.first }, "장면 목록·순서가 Swift 골든과 같아야 한다(이름 누락 0)")
    }

    @Test
    fun scenesMatchSwiftDumps() {
        val failures = golden.cases.mapNotNull { case ->
            val id = case["id"]!!.jsonPrimitive.content
            val expected = case["dump"]!!.jsonObject
            val actual = run(id)
            if (expected == actual) null else "[$id]\n  swift=$expected\n  kotlin=$actual"
        }
        assertTrue(failures.isEmpty(), failures.joinToString("\n"))
    }

    /** ⑯ 'win:' 대 맥 대문자 id 의 동급(둘 다 약함) 반납은 정확히 한쪽 — Windows 만 물러난다. */
    @Test
    fun rule16_equalWeakClaimsYieldOnExactlyOneSide() {
        val win = run("yield-weak-win-vs-weak-mac")["adopted"]!!.jsonPrimitive.content
        val mac = run("yield-weak-mac-vs-weak-win")["adopted"]!!.jsonPrimitive.content
        assertEquals("true" to "false", win to mac)
    }
}
