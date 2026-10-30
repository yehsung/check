// 원본: 맥은 UserDefaults(.standard) — Sources/check/WorkTimerStore.swift(큐·잠자기 마커·소유 id 를 defaults 에 둔다) ·
//       Sources/check/CheckApp.swift:222-241(defaults 로 자동 실행 플래그) @ a63fea2. 파일 꼴은 새 코드(설계 D§2-5 데이터 폴더, W-9 #1 W3-d).
//
// 맥 UserDefaults 는 cfprefsd 가 다른 프로세스에서 들고 있다 → 앱이 죽어도 방금 쓴 값이 남는다. 여기는 한 프로세스라 그 몫을
// 이렇게 진다:
//  - 메모리 지도가 진실, 디스크는 묶어 쓴다([debounceMillis] — 연속 put 을 한 번에). 종료 훅은 [flush] 로 바로 쓴다(조정자 종료 단계).
//  - 예외(W-13 #2): [immediateKeys](근무 큐 `check.workQueue.pending`)는 put 자리에서 **바로** 쓴다 — 강제 종료·정전이 묶음 창(≤250ms)
//    안에 오면 오프라인 근무 기록을 잃는다. 맥은 cfprefsd 가 그 몫을 진다. 바로 쓰기가 막히면 예약 쓰기로 다시 한다(값은 메모리에).
//  - 쓰기 = 같은 폴더 임시 파일 → FileChannel.force(true)(fsync) → ATOMIC_MOVE 교체. 교체 전에 죽으면 옛 파일이 그대로 남는다
//    (임시만 남음 → 다음 시작이 임시를 지우고 옛 값을 읽는다).
//  - 깨진 파일(JSON 아님·모양 다름) → `<이름>.corrupt-<n>` 으로 옮기고 빈 상태로 시작한다. 앱은 죽지 않는다.
//  - 쓰기는 한 줄(writeLock)로 직렬화 — 예약 쓰기·flush·close 가 같은 자물쇠를 쓴다. 지도 갱신은 짧은 mapLock 만.
//  - 교체가 막히면(Windows: 백신·색인기가 대상 파일을 FILE_SHARE_DELETE 없이 잡음) 몇 번 다시 하고, 그래도 안 되면 더럽힘 표시를 남겨
//    다음 예약 쓰기가 다시 한다(값은 메모리에 있다 — 잃지 않는다).
// 비밀(토큰)은 여기 두지 않는다 — TokenVault(DPAPI) 몫(DesktopKeyValueStore 계약).
package com.yehsung.aingcheck.desktop.platform.windows.store

import com.yehsung.aingcheck.feature.desktop.DesktopKeyValueStore
import com.yehsung.aingcheck.feature.desktop.work.queue.DesktopWorkQueue
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.nio.ByteBuffer
import java.nio.channels.FileChannel
import java.nio.file.AtomicMoveNotSupportedException
import java.nio.file.Files
import java.nio.file.NoSuchFileException
import java.nio.file.Path
import java.nio.file.StandardCopyOption
import java.nio.file.StandardOpenOption
import java.util.TreeMap
import java.util.concurrent.ScheduledThreadPoolExecutor
import java.util.concurrent.TimeUnit

class FileDesktopKeyValueStore internal constructor(
    val file: Path,
    private val debounceMillis: Long,
    /** 임시 → 대상 교체. 시험이 '교체 전에 죽음'을 흉내 내려고 바꾼다. */
    private val commit: (tmp: Path, target: Path) -> Unit,
    private val log: (String) -> Unit,
    /** put 즉시 디스크에 쓰는 키(W-13 #2 — 근무 큐). 나머지는 [debounceMillis] 묶음. */
    val immediateKeys: Set<String>,
) : DesktopKeyValueStore, AutoCloseable {

    internal constructor(file: Path, debounceMillis: Long, commit: (tmp: Path, target: Path) -> Unit, log: (String) -> Unit) :
        this(file, debounceMillis, commit, log, emptySet())

    constructor(file: Path, debounceMillis: Long = DEFAULT_DEBOUNCE_MILLIS, immediateKeys: Set<String> = emptySet()) :
        this(file, debounceMillis, ::atomicReplace, { System.err.println("aingcheck-kv: $it") }, immediateKeys)

    /** 시작할 때 무엇을 읽었나(진단·시험). */
    enum class LoadOutcome { MISSING, LOADED, CORRUPT_QUARANTINED }

    private val mapLock = Any()
    private val writeLock = Any()
    private val values = TreeMap<String, String>()
    private var generation = 0L
    private var writtenGeneration = 0L
    private val schedLock = Any()
    private var scheduled = false
    @Volatile private var closed = false

    private val tmp: Path = file.resolveSibling(file.fileName.toString() + ".tmp")

    private val writer = ScheduledThreadPoolExecutor(1) { r -> Thread(r, "aingcheck-kv-writer").apply { isDaemon = true } }.apply {
        // close 뒤에는 미뤄 둔 예약을 버린다 — close 가 부른 쪽에서 직접 쓴다.
        executeExistingDelayedTasksAfterShutdownPolicy = false
    }

    val loadOutcome: LoadOutcome

    /** 깨진 파일을 옮긴 자리(없으면 null). */
    var quarantinedTo: Path? = null
        private set

    init {
        file.toAbsolutePath().parent?.let { Files.createDirectories(it) }
        // 교체 전에 죽은 흔적. 대상 파일이 옛 값을 들고 있으므로 임시는 버린다(반쯤 쓴 것일 수 있다).
        runCatching { Files.deleteIfExists(tmp) }
        loadOutcome = load()
    }

    private fun load(): LoadOutcome {
        val bytes = try {
            Files.readAllBytes(file)
        } catch (_: NoSuchFileException) {
            return LoadOutcome.MISSING
        }
        val parsed = runCatching { decode(String(bytes, Charsets.UTF_8)) }.getOrNull()
        if (parsed == null) {
            quarantinedTo = quarantine()
            log("깨진 kv 파일을 ${quarantinedTo?.fileName} 로 옮기고 빈 상태로 시작한다")
            return LoadOutcome.CORRUPT_QUARANTINED
        }
        values.putAll(parsed)
        return LoadOutcome.LOADED
    }

    private fun quarantine(): Path? {
        for (n in 1..MAX_QUARANTINE) {
            val target = file.resolveSibling("${file.fileName}.corrupt-$n")
            if (Files.exists(target)) continue
            return runCatching { Files.move(file, target); target }.getOrNull()
        }
        // 옮길 자리가 다 찼다 — 지우고 시작한다(앱이 죽는 것보다 낫다).
        runCatching { Files.deleteIfExists(file) }
        return null
    }

    override fun getString(key: String): String? = synchronized(mapLock) { values[key] }

    override fun putString(key: String, value: String?) {
        synchronized(mapLock) {
            val before = values[key]
            if (before == value) return
            if (value == null) values.remove(key) else values[key] = value
            generation += 1
        }
        if (key in immediateKeys) {
            // 근무 큐: 묶음 창을 기다리지 않는다. 같은 스냅숏에 그때까지의 다른 변경도 실린다(잃는 것 없음). 막히면 예약으로 다시.
            if (!flush()) scheduleAfter(RETRY_MILLIS)
            return
        }
        schedule()
    }

    override fun keys(prefix: String): List<String> = synchronized(mapLock) {
        values.keys.filter { it.startsWith(prefix) }
    }

    fun snapshot(): Map<String, String> = synchronized(mapLock) { TreeMap(values) }

    /** 쓰지 않은 변경이 있나. */
    val isDirty: Boolean get() = synchronized(mapLock) { generation != writtenGeneration }

    private fun schedule() {
        if (closed) {
            // 종료 뒤의 put(늦은 콜백) — 예약자가 내려갔으니 부른 쪽에서 바로 쓴다.
            flush()
            return
        }
        scheduleAfter(debounceMillis)
    }

    /**
     * 예약 깃발은 짧은 schedLock 만 쓴다(put 이 UI 줄기에서 fsync 를 기다리지 않게). 예약 일은 **스냅숏을 뜨기 전에** 깃발을 내리므로
     * 그 뒤의 put 은 새 예약을 걸고, 그 전의 put 은 이번 스냅숏에 실린다 — 잃는 갱신이 없다.
     */
    private fun scheduleAfter(delayMillis: Long) {
        synchronized(schedLock) {
            if (scheduled || closed) return
            scheduled = true
            runCatching {
                writer.schedule({
                    synchronized(schedLock) { scheduled = false }
                    if (!writeIfDirty()) scheduleAfter(RETRY_MILLIS)
                }, delayMillis, TimeUnit.MILLISECONDS)
            }.onFailure { scheduled = false }
        }
    }

    /** 지금 디스크에 쓴다(종료 단계·시험). 썼거나 쓸 것이 없었으면 true, 교체 실패면 false(값은 메모리에 남는다). */
    fun flush(): Boolean = writeIfDirty()

    private fun writeIfDirty(): Boolean {
        synchronized(writeLock) {
            val work = synchronized(mapLock) { if (generation == writtenGeneration) null else generation to TreeMap(values) }
                ?: return true
            val ok = writeSnapshot(work.second)
            if (ok) synchronized(mapLock) { if (work.first > writtenGeneration) writtenGeneration = work.first }
            return ok
        }
    }

    private fun writeSnapshot(snapshot: Map<String, String>): Boolean {
        val bytes = encode(snapshot).toByteArray(Charsets.UTF_8)
        var last: Throwable? = null
        repeat(COMMIT_ATTEMPTS) { attempt ->
            try {
                FileChannel.open(tmp, StandardOpenOption.CREATE, StandardOpenOption.TRUNCATE_EXISTING, StandardOpenOption.WRITE).use { ch ->
                    val buf = ByteBuffer.wrap(bytes)
                    while (buf.hasRemaining()) ch.write(buf)
                    ch.force(true)
                }
                commit(tmp, file)
                return true
            } catch (t: Throwable) {
                last = t
                if (attempt < COMMIT_ATTEMPTS - 1) Thread.sleep(COMMIT_BACKOFF_MILLIS)
            }
        }
        runCatching { Files.deleteIfExists(tmp) }
        log("kv 쓰기 실패(${COMMIT_ATTEMPTS}번): $last")
        return false
    }

    /** 남은 변경을 쓰고 예약자를 내린다. 뒤의 put 도 받는다(바로 쓴다). */
    override fun close() {
        if (closed) return
        closed = true
        writer.shutdown()
        writeIfDirty()
    }

    companion object {
        const val DEFAULT_DEBOUNCE_MILLIS = 250L
        /** 데이터 폴더 안 파일 이름(D§2-5 `%LOCALAPPDATA%\aing-check\`). */
        const val FILE_NAME = "prefs.json"
        const val FORMAT_VERSION = 1
        private const val RETRY_MILLIS = 1_000L
        private const val COMMIT_ATTEMPTS = 3
        private const val COMMIT_BACKOFF_MILLIS = 40L
        private const val MAX_QUARANTINE = 50

        /** 즉시 쓰기 키(W-13 #2): 근무 큐 한 칸. 이름은 큐 쪽 상수 그대로(글자를 두 벌 적지 않는다). */
        val WORK_QUEUE_IMMEDIATE_KEYS: Set<String> = setOf(DesktopWorkQueue.pendingWorkQueueKey)

        /** 앱 자리: [dataDir](WindowsAppPaths.dataDir — 패키지 안이면 이미 LocalCache 경로)/prefs.json. 근무 큐는 즉시 쓰기. */
        fun inDataDir(
            dataDir: String,
            debounceMillis: Long = DEFAULT_DEBOUNCE_MILLIS,
            immediateKeys: Set<String> = WORK_QUEUE_IMMEDIATE_KEYS,
        ): FileDesktopKeyValueStore = FileDesktopKeyValueStore(Path.of(dataDir, FILE_NAME), debounceMillis, immediateKeys)

        internal fun atomicReplace(tmp: Path, target: Path) {
            try {
                Files.move(tmp, target, StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
            } catch (_: AtomicMoveNotSupportedException) {
                Files.move(tmp, target, StandardCopyOption.REPLACE_EXISTING)
            }
        }

        /** `{"v":1,"values":{…}}` — 키 정렬(같은 값이면 같은 바이트). */
        internal fun encode(values: Map<String, String>): String {
            val inner = JsonObject(values.toSortedMap().mapValues { JsonPrimitive(it.value) })
            return JsonObject(mapOf("v" to JsonPrimitive(FORMAT_VERSION), "values" to inner)).toString()
        }

        /** 모양이 다르면 예외(→ 깨진 파일). 값은 문자열만 받는다. */
        internal fun decode(text: String): Map<String, String> {
            val root = Json.parseToJsonElement(text).jsonObject
            val v = root["v"]?.jsonPrimitive?.content?.toIntOrNull()
            require(v == FORMAT_VERSION) { "모르는 판: $v" }
            val inner = requireNotNull(root["values"]) { "values 없음" }.jsonObject
            return inner.mapValues { (_, e) ->
                val p = e.jsonPrimitive
                require(p.isString) { "문자열 아닌 값" }
                p.content
            }
        }
    }
}
