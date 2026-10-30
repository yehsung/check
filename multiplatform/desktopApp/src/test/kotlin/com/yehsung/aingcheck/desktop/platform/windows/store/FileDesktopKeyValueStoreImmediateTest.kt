// W-13 #2: 근무 큐 키는 put 자리에서 바로 디스크에, 나머지는 250ms 묶음(+ 종료 flush). 강제 종료가 묶음 창 안에 와도 큐는 남는다.
// int-w3 반박 검증 must_fix: AI 도구 기록 동의(check.mas.aiToolDataConsent)도 즉시 — 철회가 묶음 창 안의 강제 종료로 사라지면 다음 실행이
// 동의=참으로 AI 기록을 다시 읽는다(맥은 UserDefaults·cfprefsd 가 철회를 지킨다 — Sources/CheckCore/MacEdition.swift:176-185).
package com.yehsung.aingcheck.desktop.platform.windows.store

import com.yehsung.aingcheck.desktop.pages.desktopsettings.DesktopSettingsKeys
import com.yehsung.aingcheck.desktop.pages.desktopsettings.DesktopSettingsStore
import com.yehsung.aingcheck.feature.desktop.work.queue.DesktopWorkQueue
import java.nio.file.Files
import java.nio.file.Path
import kotlin.test.AfterTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class FileDesktopKeyValueStoreImmediateTest {
    private val dir: Path = Files.createTempDirectory("kv-immediate")
    private val opened = mutableListOf<FileDesktopKeyValueStore>()

    @AfterTest
    fun cleanup() {
        opened.forEach { runCatching { it.close() } }
        dir.toFile().deleteRecursively()
    }

    /** 다른 프로세스가 지금 파일을 읽으면 무엇이 보이나(= 강제 종료 직후 다음 실행이 읽을 것). */
    private fun onDisk(file: Path): Map<String, String> =
        if (Files.exists(file)) FileDesktopKeyValueStore.decode(Files.readString(file)) else emptyMap()

    @Test
    fun 앱_자리는_근무_큐_키를_즉시_쓰기로_연다() {
        val kv = FileDesktopKeyValueStore.inDataDir(dir.toString(), debounceMillis = 60_000).also { opened += it }
        assertEquals(FileDesktopKeyValueStore.WORK_IMMEDIATE_KEYS, kv.immediateKeys)
        assertTrue(DesktopWorkQueue.pendingWorkQueueKey in kv.immediateKeys)
        kv.putString(DesktopWorkQueue.pendingWorkQueueKey, """[{"op":"start"}]""")
        assertEquals("""[{"op":"start"}]""", onDisk(kv.file)[DesktopWorkQueue.pendingWorkQueueKey], "묶음 창(60초)을 기다리지 않는다")
        assertFalse(kv.isDirty)
    }

    @Test
    fun 다른_키는_묶음_창_안에선_디스크에_없다__음성_대조() {
        val kv = FileDesktopKeyValueStore.inDataDir(dir.toString(), debounceMillis = 60_000).also { opened += it }
        kv.putString("check.overlay.position", "1,2")
        assertNull(onDisk(kv.file)["check.overlay.position"])
        assertTrue(kv.isDirty)
        // 큐 쓰기가 오면 그때까지의 다른 변경도 같은 스냅숏에 실린다(잃는 것 없음).
        kv.putString(DesktopWorkQueue.pendingWorkQueueKey, "[]")
        assertEquals("1,2", onDisk(kv.file)["check.overlay.position"])
        assertFalse(kv.isDirty)
    }

    @Test
    fun 즉시_키가_없으면_큐도_묶음__음성_대조() {
        val kv = FileDesktopKeyValueStore(dir.resolve("plain.json"), debounceMillis = 60_000).also { opened += it }
        kv.putString(DesktopWorkQueue.pendingWorkQueueKey, "[]")
        assertNull(onDisk(kv.file)[DesktopWorkQueue.pendingWorkQueueKey])
        assertTrue(kv.flush())
        assertEquals("[]", onDisk(kv.file)[DesktopWorkQueue.pendingWorkQueueKey])
    }

    @Test
    fun 큐_지움도_즉시() {
        val kv = FileDesktopKeyValueStore.inDataDir(dir.toString(), debounceMillis = 60_000).also { opened += it }
        kv.putString(DesktopWorkQueue.pendingWorkQueueKey, "[1]")
        kv.putString(DesktopWorkQueue.pendingWorkQueueKey, null)
        assertFalse(onDisk(kv.file).containsKey(DesktopWorkQueue.pendingWorkQueueKey), "드레인 뒤 빈 큐가 다음 실행에서 되살아나지 않게")
    }

    /** 강제 종료 흉내: 앞 인스턴스를 닫지 않고(= flush 없이) 같은 파일을 새로 연다 — 다음 실행이 읽을 것. */
    private fun reopenAfterKill(): FileDesktopKeyValueStore =
        FileDesktopKeyValueStore.inDataDir(dir.toString(), debounceMillis = 60_000).also { opened += it }

    @Test
    fun 동의_철회는_묶음_창_안의_강제_종료에도_남는다() {
        val kv = FileDesktopKeyValueStore.inDataDir(dir.toString(), debounceMillis = 60_000).also { opened += it }
        val settings = DesktopSettingsStore(kv)
        settings.setTokenUsageCollect(true)
        assertTrue(kv.flush())
        settings.setTokenUsageCollect(false) // 설정 화면 스위치·AI 토큰 페이지와 같은 문(DesktopSettingsStore.write → kv.putBoolean)
        assertEquals("false", onDisk(kv.file)[DesktopSettingsKeys.AI_TOOL_DATA_CONSENT], "철회는 묶음 창(60초)을 기다리지 않는다")
        assertFalse(kv.isDirty)
        assertFalse(DesktopSettingsStore(reopenAfterKill()).tokenUsageCollect.value, "다음 실행이 동의=참으로 AI 기록을 다시 읽으면 안 된다")
    }

    @Test
    fun 동의_부여도_즉시() {
        val kv = FileDesktopKeyValueStore.inDataDir(dir.toString(), debounceMillis = 60_000).also { opened += it }
        DesktopSettingsStore(kv).setTokenUsageCollect(true)
        assertEquals("true", onDisk(kv.file)[DesktopSettingsKeys.AI_TOOL_DATA_CONSENT])
        assertTrue(DesktopSettingsStore(reopenAfterKill()).tokenUsageCollect.value)
    }

    @Test
    fun 다른_설정은_여전히_묶음__음성_대조() {
        // 즉시 키를 넓힌 것이 설정 전부를 즉시로 바꾸지 않았음(= 위 단언이 흉내로 손실을 잡을 수 있음)을 같은 흉내로 본다.
        val kv = FileDesktopKeyValueStore.inDataDir(dir.toString(), debounceMillis = 60_000).also { opened += it }
        val settings = DesktopSettingsStore(kv)
        settings.setOverlayEnabled(false)
        assertNull(onDisk(kv.file)[DesktopSettingsKeys.OVERLAY_ENABLED])
        assertTrue(kv.isDirty)
        assertTrue(DesktopSettingsStore(reopenAfterKill()).overlayEnabled.value, "묶음 창 안의 강제 종료면 기본값(켜짐)으로 돌아간다")
    }
}
