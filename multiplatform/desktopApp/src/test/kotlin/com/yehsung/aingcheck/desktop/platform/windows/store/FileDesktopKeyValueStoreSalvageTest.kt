// W-14 #6 — kv 단단히: 값 하나가 깨져도 파일 전체를 버리지 않는다(손실 = 그 키뿐, 원본 .corrupt-<n> 보존) · 온전한 .tmp 가 본 파일보다
// 새로우면 채택(fsync 와 move 사이 죽음) · 소유 세션 id·강도는 즉시 쓰기. int-w2 프로브(outcome=CORRUPT_QUARANTINED queue=null
// consent=null)를 뒤집는다. 픽스처는 합성만(임시 폴더). 키 이름은 소비자 상수 그대로.
package com.yehsung.aingcheck.desktop.platform.windows.store

import com.yehsung.aingcheck.desktop.DesktopPrefs
import com.yehsung.aingcheck.feature.desktop.work.queue.DesktopWorkQueue
import com.yehsung.aingcheck.feature.desktop.work.state.OwnedSessionLedger
import com.yehsung.aingcheck.feature.desktop.work.state.SessionClaimStrength
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.StandardCopyOption
import java.nio.file.attribute.FileTime
import kotlin.io.path.exists
import kotlin.io.path.readBytes
import kotlin.io.path.readText
import kotlin.io.path.writeBytes
import kotlin.io.path.writeText
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class FileDesktopKeyValueStoreSalvageTest {
    private val dir: Path = Files.createTempDirectory("aingcheck-kv-salvage")
    private val file: Path = dir.resolve(FileDesktopKeyValueStore.FILE_NAME)
    private val tmp: Path = dir.resolve(FileDesktopKeyValueStore.FILE_NAME + ".tmp")
    private val opened = mutableListOf<FileDesktopKeyValueStore>()

    private fun open(commit: ((Path, Path) -> Unit)? = null, immediate: Set<String> = emptySet()): FileDesktopKeyValueStore =
        FileDesktopKeyValueStore(file, 60_000, commit ?: FileDesktopKeyValueStore::atomicReplace, { }, immediate).also { opened += it }

    @AfterTest
    fun cleanup() {
        opened.forEach { runCatching { it.close() } }
        dir.toFile().deleteRecursively()
    }

    private companion object {
        const val QUEUE = DesktopWorkQueue.pendingWorkQueueKey
        const val CONSENT = "aingcheck.desktop.aiToolDataConsent"
        const val QUEUE_JSON = """[{"id":"8f14e45f-ceea-467a-9575-1c2d3b4a5e6f","kind":"start","at":1761800000.5}]"""

        /** 인코더가 쓰는 그대로의 온전한 파일(큐 JSON 의 따옴표는 \" 로 이스케이프된다). */
        fun intact(vararg pairs: Pair<String, String>): String = FileDesktopKeyValueStore.encode(mapOf(*pairs))
    }

    @Test
    fun `값 하나가 문자열이 아님 — 그 키만 버리고 근무 큐·동의는 산다, 원본은 corrupt-1 에 그대로`() {
        val original = """{"v":1,"values":{"$QUEUE":${jsonString(QUEUE_JSON)},"check.broken":5,"$CONSENT":"granted"}}"""
        file.writeText(original)
        val a = open()
        assertEquals(FileDesktopKeyValueStore.LoadOutcome.SALVAGED, a.loadOutcome)
        assertEquals(listOf("check.broken"), a.droppedKeys)
        assertEquals(QUEUE_JSON, a.getString(QUEUE))
        assertEquals("granted", a.getString(CONSENT))
        assertNull(a.getString("check.broken"))
        assertEquals("${FileDesktopKeyValueStore.FILE_NAME}.corrupt-1", a.quarantinedTo?.fileName.toString())
        assertEquals(original, a.quarantinedTo!!.readText(), "깨진 원본을 보존하지 않았다")
        // 본 파일은 살린 값으로 다시 쓰였다 — 다음 시작은 온전히 읽고 corrupt 를 또 만들지 않는다.
        assertFalse(a.isDirty)
        val b = open()
        assertEquals(FileDesktopKeyValueStore.LoadOutcome.LOADED, b.loadOutcome)
        assertEquals(QUEUE_JSON, b.getString(QUEUE))
        assertFalse(dir.resolve("${FileDesktopKeyValueStore.FILE_NAME}.corrupt-2").exists())
    }

    @Test
    fun `JSON 이 깨짐(이스케이프 망가짐) — 훑어서 읽히는 항목은 살리고 깨진 키만 버린다`() {
        val good = intact(QUEUE to QUEUE_JSON, "check.mid" to "x", CONSENT to "granted")
        // check.mid 값 안에 JSON 에 없는 이스케이프(\q) — 엄격 해석은 파일 전체를 거부한다.
        val broken = good.replace("\"check.mid\":\"x\"", "\"check.mid\":\"x\\q\"")
        assertTrue(runCatching { FileDesktopKeyValueStore.decode(broken) }.isFailure, "기준선: 엄격 해석은 전체를 버린다")
        file.writeText(broken)
        val a = open()
        assertEquals(FileDesktopKeyValueStore.LoadOutcome.SALVAGED, a.loadOutcome)
        assertEquals(listOf("check.mid"), a.droppedKeys)
        assertEquals(QUEUE_JSON, a.getString(QUEUE), "큐(이스케이프된 따옴표·쉼표가 든 값)를 경계로 오인했다")
        assertEquals("granted", a.getString(CONSENT))
    }

    @Test
    fun `닫는 따옴표가 바이트 하나로 사라짐 — 다음 경계에서 다시 붙잡아 뒤 키를 살린다`() {
        val good = intact("a.first" to "1", "b.mid" to "xyz", CONSENT to "granted", QUEUE to QUEUE_JSON)
        val broken = good.replace("\"xyz\",", "\"xyz#,")
        file.writeText(broken)
        val a = open()
        assertEquals(FileDesktopKeyValueStore.LoadOutcome.SALVAGED, a.loadOutcome)
        assertEquals("1", a.getString("a.first"))
        assertNull(a.getString("b.mid"), "망가진 값을 살린 척했다")
        assertEquals("granted", a.getString(CONSENT))
        assertEquals(QUEUE_JSON, a.getString(QUEUE))
        assertEquals(listOf("b.mid"), a.droppedKeys)
    }

    @Test
    fun `UTF-8 이 깨진 바이트 — 대체 문자가 든 항목만 버린다`() {
        val good = intact(QUEUE to QUEUE_JSON, "check.name" to "아잉", CONSENT to "granted").toByteArray(Charsets.UTF_8)
        val idx = String(good, Charsets.UTF_8).let { s -> s.substring(0, s.indexOf("아잉")).toByteArray(Charsets.UTF_8).size }
        val broken = good.copyOf().also { it[idx] = 0xFF.toByte() }
        file.writeBytes(broken)
        val a = open()
        assertEquals(FileDesktopKeyValueStore.LoadOutcome.SALVAGED, a.loadOutcome)
        assertEquals(listOf("check.name"), a.droppedKeys)
        assertEquals(QUEUE_JSON, a.getString(QUEUE))
        assertEquals("granted", a.getString(CONSENT))
        assertContentEquals(broken, a.quarantinedTo!!.readBytes())
    }

    @Test
    fun `음성 대조 — 온전한 파일은 LOADED, 사본 없음 · 판 다름·머리 깨짐·살릴 키 0 은 전체 격리`() {
        file.writeText(intact(QUEUE to QUEUE_JSON, CONSENT to "granted"))
        val ok = open()
        assertEquals(FileDesktopKeyValueStore.LoadOutcome.LOADED, ok.loadOutcome)
        assertEquals(emptyList(), ok.droppedKeys)
        assertNull(ok.quarantinedTo)
        assertFalse(dir.resolve("${FileDesktopKeyValueStore.FILE_NAME}.corrupt-1").exists())
        ok.close()

        // 미래 판의 뜻은 짐작하지 않는다(값이 멀쩡해도 살리지 않는다).
        file.writeText("""{"v":2,"values":{"$CONSENT":"granted"}}""")
        assertEquals(FileDesktopKeyValueStore.LoadOutcome.CORRUPT_QUARANTINED, open().loadOutcome)
        // 머리가 깨지면 틀을 못 읽는다.
        file.writeText("""{"v":1,"valu""" + "\u0000" + """es":{"$CONSENT":"granted"}}""")
        assertEquals(FileDesktopKeyValueStore.LoadOutcome.CORRUPT_QUARANTINED, open().loadOutcome)
        // 키가 하나뿐이고 그게 깨졌다 — 살린 것 0 → 옮기고 빈 상태(사본이 아니라 이동).
        file.writeText("""{"v":1,"values":{"a":5}}""")
        val empty = open()
        assertEquals(FileDesktopKeyValueStore.LoadOutcome.CORRUPT_QUARANTINED, empty.loadOutcome)
        assertEquals(listOf("a"), empty.droppedKeys)
        assertFalse(file.exists(), "살린 것이 없으면 원본을 옮긴다")
    }

    @Test
    fun `온전한 tmp 가 본 파일보다 새것 — 채택하고 본 파일로 옮긴다`() {
        file.writeText(intact(QUEUE to "[]", CONSENT to "granted"))
        tmp.writeText(intact(QUEUE to QUEUE_JSON, CONSENT to "granted"))
        Files.setLastModifiedTime(file, FileTime.fromMillis(1_000_000))
        Files.setLastModifiedTime(tmp, FileTime.fromMillis(2_000_000))
        val a = open()
        assertEquals(FileDesktopKeyValueStore.LoadOutcome.TMP_ADOPTED, a.loadOutcome)
        assertEquals(QUEUE_JSON, a.getString(QUEUE))
        assertFalse(tmp.exists(), "채택한 임시가 남았다")
        assertEquals(QUEUE_JSON, FileDesktopKeyValueStore.decode(file.readText())[QUEUE], "본 파일로 옮기지 않았다")
        assertFalse(a.isDirty)
    }

    @Test
    fun `음성 대조 — tmp 가 본 파일보다 낡았거나 반쯤 쓰였으면 버리고 본 파일`() {
        file.writeText(intact(QUEUE to "[]"))
        tmp.writeText(intact(QUEUE to QUEUE_JSON))
        Files.setLastModifiedTime(file, FileTime.fromMillis(2_000_000))
        Files.setLastModifiedTime(tmp, FileTime.fromMillis(1_000_000))
        val older = open()
        assertEquals(FileDesktopKeyValueStore.LoadOutcome.LOADED, older.loadOutcome)
        assertEquals("[]", older.getString(QUEUE))
        assertFalse(tmp.exists())
        older.close()

        // 반쯤 쓴 임시(값 하나라도 엄격 해석이 거부) — 살리기 대상이 아니다(임시는 온전할 때만).
        tmp.writeText(intact(QUEUE to QUEUE_JSON).dropLast(3))
        Files.setLastModifiedTime(tmp, FileTime.fromMillis(9_000_000_000))
        val half = open()
        assertEquals(FileDesktopKeyValueStore.LoadOutcome.LOADED, half.loadOutcome)
        assertEquals("[]", half.getString(QUEUE))
        assertFalse(tmp.exists())
    }

    @Test
    fun `강제 종료 흉내 — fsync 뒤 move 전에 죽음, 다음 실행이 큐와 소유 세션을 되찾는다`() {
        val first = open(immediate = FileDesktopKeyValueStore.WORK_IMMEDIATE_KEYS)
        first.putString(CONSENT, "granted")
        first.putString(QUEUE, "[]")
        first.close()
        val crashImage = dir.resolve("crash-image")
        // 교체 직전에 프로세스가 죽는다: 그 순간의 임시(fsync 까지 끝남)를 떠 두고 던진다. 실제 죽음엔 실패 뒤 청소·재시도가 없으므로
        // 죽은 순간의 디스크(본 파일 + 떠 둔 임시)를 새 폴더로 옮겨 다음 실행을 그 위에서 연다(죽은 쪽의 재시도 스레드가 끼어들 수 없게).
        var dead = false
        val dying = open(
            commit = { t, target ->
                if (dead) FileDesktopKeyValueStore.atomicReplace(t, target) else {
                    Files.copy(t, crashImage, StandardCopyOption.REPLACE_EXISTING)
                    throw IllegalStateException("교체 전에 죽음")
                }
            },
            immediate = FileDesktopKeyValueStore.WORK_IMMEDIATE_KEYS,
        )
        val ledger = OwnedSessionLedger(dying)
        ledger.set("3F2A0000-0000-4000-8000-0000000000AB", SessionClaimStrength.STRONG)
        dying.putString(QUEUE, QUEUE_JSON)
        assertEquals("[]", FileDesktopKeyValueStore.decode(file.readText())[QUEUE], "기준선: 본 파일은 옛 값")
        val nextDir = Files.createDirectories(dir.resolve("next"))
        val nextFile = nextDir.resolve(FileDesktopKeyValueStore.FILE_NAME)
        Files.copy(file, nextFile)
        Files.copy(crashImage, nextDir.resolve(FileDesktopKeyValueStore.FILE_NAME + ".tmp"))
        Files.setLastModifiedTime(nextFile, FileTime.fromMillis(1_000_000))
        Files.setLastModifiedTime(nextDir.resolve(FileDesktopKeyValueStore.FILE_NAME + ".tmp"), FileTime.fromMillis(1_000_001))
        dead = true

        val next = FileDesktopKeyValueStore(nextFile, 60_000, FileDesktopKeyValueStore::atomicReplace, { }, FileDesktopKeyValueStore.WORK_IMMEDIATE_KEYS)
            .also { opened += it }
        assertEquals(FileDesktopKeyValueStore.LoadOutcome.TMP_ADOPTED, next.loadOutcome)
        assertEquals(QUEUE_JSON, next.getString(QUEUE), "죽기 직전 큐 항목을 잃었다")
        val nextLedger = OwnedSessionLedger(next)
        assertTrue(nextLedger.isOwned("3f2a0000-0000-4000-8000-0000000000ab"), "자기가 연 세션을 남의 것으로 읽는다")
        assertEquals(SessionClaimStrength.STRONG, nextLedger.strength)
        assertEquals("granted", next.getString(CONSENT))
    }

    @Test
    fun `소유 세션 id·강도는 즉시 쓰기 — 묶음 창(60초) 안에도 디스크에 있다, 다른 키는 없다`() {
        val kv = FileDesktopKeyValueStore.inDataDir(dir.toString(), debounceMillis = 60_000).also { opened += it }
        assertEquals(
            setOf(QUEUE, OwnedSessionLedger.OWNED_ID_KEY, OwnedSessionLedger.OWNED_STRENGTH_KEY),
            kv.immediateKeys,
        )
        kv.putString("check.overlay.position", "1,2")
        assertFalse(file.exists(), "음성 대조: 묶음 키는 창 안에 디스크에 없다")
        OwnedSessionLedger(kv).set("3f2a0000-0000-4000-8000-0000000000ab", SessionClaimStrength.STRONG)
        val onDisk = FileDesktopKeyValueStore.decode(file.readText())
        assertEquals("3f2a0000-0000-4000-8000-0000000000ab", onDisk[OwnedSessionLedger.OWNED_ID_KEY])
        assertEquals(SessionClaimStrength.STRONG.raw, onDisk[OwnedSessionLedger.OWNED_STRENGTH_KEY])
        // 즉시 쓰기 스냅숏에 그때까지의 묶음 키도 실린다(잃는 것 없음).
        assertEquals("1,2", onDisk["check.overlay.position"])
        // 음성 대조: 즉시 키가 아닌 열쇠는 그 뒤에도 창 안에서 디스크에 없다.
        kv.putString("check.overlay.position", "3,4")
        assertEquals("1,2", FileDesktopKeyValueStore.decode(file.readText())["check.overlay.position"])
        assertTrue(DesktopPrefs(kv).getString("check.overlay.position") == "3,4")
    }

    private fun jsonString(raw: String): String = kotlinx.serialization.json.JsonPrimitive(raw).toString()
}
