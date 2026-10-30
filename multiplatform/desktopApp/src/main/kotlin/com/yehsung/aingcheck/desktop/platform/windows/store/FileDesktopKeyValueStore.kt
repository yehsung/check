// 원본: 맥은 UserDefaults(.standard) — Sources/check/WorkTimerStore.swift(큐·잠자기 마커·소유 id 를 defaults 에 둔다) ·
//       Sources/check/CheckApp.swift:222-241(defaults 로 자동 실행 플래그) @ a63fea2. 파일 꼴은 새 코드(설계 D§2-5 데이터 폴더, W-9 #1 W3-d).
//
// 맥 UserDefaults 는 cfprefsd 가 다른 프로세스에서 들고 있다 → 앱이 죽어도 방금 쓴 값이 남는다. 여기는 한 프로세스라 그 몫을
// 이렇게 진다:
//  - 메모리 지도가 진실, 디스크는 묶어 쓴다([debounceMillis] — 연속 put 을 한 번에). 종료 훅은 [flush] 로 바로 쓴다(조정자 종료 단계).
//  - 예외(W-13 #2): [immediateKeys](근무 큐 `check.workQueue.pending` · 소유 세션 · AI 기록 동의)는 put 자리에서 **바로** 쓴다 — 강제 종료·정전이 묶음 창(≤250ms)
//    안에 오면 오프라인 근무 기록을 잃는다. 맥은 cfprefsd 가 그 몫을 진다. 바로 쓰기가 막히면 예약 쓰기로 다시 한다(값은 메모리에).
//  - 쓰기 = 같은 폴더 임시 파일 → FileChannel.force(true)(fsync) → ATOMIC_MOVE 교체. 교체 전에 죽으면 옛 파일이 그대로 남는다.
//    (W-14 #6) 다음 시작에서 임시가 **온전한 JSON**(판 1·값 모두 문자열)이고 본 파일보다 오래되지 않았으면 임시를 채택한다 —
//    fsync 와 move 사이에서 죽으면 그 직전 즉시 쓰기(근무 큐 마지막 항목·소유 세션 id)가 임시에만 있다. 반쯤 쓴 임시는 버린다.
//  - 깨진 파일(W-14 #6): 값 하나가 깨져도 파일 전체를 버리지 않는다 — 읽을 수 있는 키는 살리고 못 읽은 키만 버린다(손실 = 그 키뿐).
//    원본은 `<이름>.corrupt-<n>` 으로 보존하고 살린 값으로 본 파일을 다시 쓴다([LoadOutcome.SALVAGED]). 살린 키가 하나도 없거나
//    판이 다르면(미래 판의 뜻을 짐작하지 않는다) 원본을 옮기고 빈 상태로 시작한다([LoadOutcome.CORRUPT_QUARANTINED]). 앱은 죽지 않는다.
//  - 쓰기는 한 줄(writeLock)로 직렬화 — 예약 쓰기·flush·close 가 같은 자물쇠를 쓴다. 지도 갱신은 짧은 mapLock 만.
//  - 교체가 막히면(Windows: 백신·색인기가 대상 파일을 FILE_SHARE_DELETE 없이 잡음) 몇 번 다시 하고, 그래도 안 되면 더럽힘 표시를 남겨
//    다음 예약 쓰기가 다시 한다(값은 메모리에 있다 — 잃지 않는다).
// 비밀(토큰)은 여기 두지 않는다 — TokenVault(DPAPI) 몫(DesktopKeyValueStore 계약).
package com.yehsung.aingcheck.desktop.platform.windows.store

import com.yehsung.aingcheck.core.stores.tetris.TetrisDuelStore
import com.yehsung.aingcheck.desktop.pages.desktopsettings.DesktopSettingsKeys
import com.yehsung.aingcheck.feature.desktop.DesktopKeyValueStore
import com.yehsung.aingcheck.feature.desktop.work.queue.DesktopWorkQueue
import com.yehsung.aingcheck.feature.desktop.work.state.OwnedSessionLedger
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.nio.ByteBuffer
import java.nio.channels.FileChannel
import java.nio.charset.CodingErrorAction
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
    /** put 즉시 디스크에 쓰는 키(W-13 #2 근무 큐 · W-14 #6 소유 세션 id·강도 · AI 기록 동의). 나머지는 [debounceMillis] 묶음. */
    val immediateKeys: Set<String>,
    /**
     * put 즉시 디스크에 쓰는 **키 머리**(사용자별 키 — 이름 끝에 사용자 id 가 붙어 [immediateKeys] 의 고정 글자로는 못 고른다).
     * 테트리스 '이 기기가 연 판' 기록(vc3 · TetrisDuelStore.ownedMatchesKey) — 맥 TetrisDuelStoreGame.swift:406 은 수락·신청 ok
     * 자리에서 UserDefaults.set(cfprefsd 가 지킨다)이라 판을 연 직후 강제 종료돼도 남는다.
     */
    val immediateKeyPrefixes: Set<String> = emptySet(),
) : DesktopKeyValueStore, AutoCloseable {

    internal constructor(file: Path, debounceMillis: Long, commit: (tmp: Path, target: Path) -> Unit, log: (String) -> Unit) :
        this(file, debounceMillis, commit, log, emptySet())

    constructor(
        file: Path,
        debounceMillis: Long = DEFAULT_DEBOUNCE_MILLIS,
        immediateKeys: Set<String> = emptySet(),
        immediateKeyPrefixes: Set<String> = emptySet(),
    ) : this(file, debounceMillis, ::atomicReplace, { System.err.println("aingcheck-kv: $it") }, immediateKeys, immediateKeyPrefixes)

    /** 이 키는 put 자리에서 바로 쓴다([immediateKeys] 글자 그대로 · [immediateKeyPrefixes] 머리). */
    fun isImmediate(key: String): Boolean = key in immediateKeys || immediateKeyPrefixes.any { key.startsWith(it) }

    /** 시작할 때 무엇을 읽었나(진단·시험). */
    enum class LoadOutcome {
        MISSING,
        LOADED,
        /** 일부 키만 깨졌다 — 나머지를 살렸다(원본은 [quarantinedTo] 에 사본, 본 파일은 살린 값으로 다시 썼다). */
        SALVAGED,
        /** 교체 전에 죽은 온전한 임시를 채택했다(본 파일보다 새것). */
        TMP_ADOPTED,
        /** 살릴 것이 없었다(전체가 JSON 아님·판 다름·키 0) — 원본을 옮기고 빈 상태. */
        CORRUPT_QUARANTINED,
    }

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

    /** 깨진 원본을 보존한 자리(없으면 null). */
    var quarantinedTo: Path? = null
        private set

    /** 시작 때 버린 키(깨진 값·읽을 수 없는 항목 — 진단·시험). 읽을 수 없는 키 이름은 [UNREADABLE_KEY]. */
    var droppedKeys: List<String> = emptyList()
        private set

    init {
        file.toAbsolutePath().parent?.let { Files.createDirectories(it) }
        loadOutcome = adoptIntactTmp() ?: run {
            // 반쯤 쓴(또는 본 파일보다 낡은) 임시 — 대상 파일이 값을 들고 있으므로 버린다.
            runCatching { Files.deleteIfExists(tmp) }
            load()
        }
    }

    /**
     * fsync 와 ATOMIC_MOVE 사이에서 죽은 흔적. 임시는 마지막 성공 교체 **뒤에** 쓰인 것이라(교체가 임시를 옮겨 없앤다) 온전하면 본 파일보다
     * 새 값이다. 같은 시각도 채택한다(시각 해상도가 거친 파일 시스템 — 임시가 남아 있다는 것 자체가 교체 뒤라는 뜻). 본 파일이 더 새것이면
     * (시계가 뒤로 간 기기 등) 믿지 않는다.
     */
    private fun adoptIntactTmp(): LoadOutcome? {
        if (!Files.exists(tmp)) return null
        val tmpTime = runCatching { Files.getLastModifiedTime(tmp) }.getOrNull() ?: return null
        val fileTime = runCatching { Files.getLastModifiedTime(file) }.getOrNull()
        if (fileTime != null && tmpTime < fileTime) return null
        val parsed = runCatching { decode(strictUtf8(Files.readAllBytes(tmp))) }.getOrNull() ?: return null
        values.putAll(parsed)
        if (runCatching { commit(tmp, file) }.isFailure) {
            // 교체가 또 막혔다 — 값은 메모리에 있다. 임시는 남겨 둔다(다시 죽어도 다음 시작이 또 채택). 다음 쓰기가 덮어 교체한다.
            generation += 1
            scheduleAfter(RETRY_MILLIS)
        }
        log("교체 전에 남은 온전한 임시를 채택했다(키 ${parsed.size}개)")
        return LoadOutcome.TMP_ADOPTED
    }

    private fun load(): LoadOutcome {
        val bytes = try {
            Files.readAllBytes(file)
        } catch (_: NoSuchFileException) {
            return LoadOutcome.MISSING
        }
        val salvage = runCatching { salvage(bytes) }.getOrNull()
        if (salvage != null && !salvage.damaged) {
            values.putAll(salvage.values)
            return LoadOutcome.LOADED
        }
        droppedKeys = salvage?.dropped ?: listOf(UNREADABLE_KEY)
        if (salvage == null || salvage.values.isEmpty()) {
            quarantinedTo = quarantine(move = true)
            log("깨진 kv 파일을 ${quarantinedTo?.fileName} 로 옮기고 빈 상태로 시작한다")
            return LoadOutcome.CORRUPT_QUARANTINED
        }
        // 원본을 사본으로 보존한 뒤 살린 값으로 본 파일을 다시 쓴다(다음 시작이 같은 살리기를 되풀이하지 않게).
        quarantinedTo = quarantine(move = false)
        values.putAll(salvage.values)
        generation += 1
        if (!writeIfDirty()) scheduleAfter(RETRY_MILLIS)
        log("kv 파일의 키 ${droppedKeys.size}개를 버리고 ${salvage.values.size}개를 살렸다(원본 ${quarantinedTo?.fileName})")
        return LoadOutcome.SALVAGED
    }

    private fun quarantine(move: Boolean): Path? {
        for (n in 1..MAX_QUARANTINE) {
            val target = file.resolveSibling("${file.fileName}.corrupt-$n")
            if (Files.exists(target)) continue
            return runCatching { if (move) Files.move(file, target) else Files.copy(file, target); target }.getOrNull()
        }
        // 옮길 자리가 다 찼다 — 옮기기면 지우고 시작한다(앱이 죽는 것보다 낫다). 사본이면 보존만 건너뛴다.
        if (move) runCatching { Files.deleteIfExists(file) }
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
        if (isImmediate(key)) {
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

        /** [droppedKeys] 에서 이름조차 못 읽은 항목. */
        const val UNREADABLE_KEY = "<읽을 수 없는 키>"

        /**
         * 즉시 쓰기 키: 근무 큐 한 칸(W-13 #2) + 소유 세션 id·강도(W-14 #6 — 강제 종료가 묶음 창 안에 오면 다음 실행이 자기가 연 세션을
         * '남의 것'으로 읽는다. 맥 isOwnedByThisMac 은 cfprefsd 가 그 값을 지킨다) + AI 도구 기록 동의(W-13 #5 — 철회가 묶음 창 안의
         * 강제 종료로 사라지면 다음 실행이 동의=참으로 AI 기록을 다시 읽는다. 맥 MacEdition.swift:176-185 는 UserDefaults 라 철회가 남는다).
         * 이름은 소비자 상수 그대로(글자를 두 벌 적지 않는다).
         */
        val WORK_IMMEDIATE_KEYS: Set<String> = setOf(
            DesktopWorkQueue.pendingWorkQueueKey,
            OwnedSessionLedger.OWNED_ID_KEY,
            OwnedSessionLedger.OWNED_STRENGTH_KEY,
            DesktopSettingsKeys.AI_TOOL_DATA_CONSENT,
        )

        /**
         * 즉시 쓰기 키 머리: 테트리스 '이 기기가 연 판'(사용자별 `tetris.duel.ownedMatches.<id>` — 옛 서버(my_device 없음)에서 판을 연 직후
         * 강제 종료되면 다음 실행이 자기 판을 '다른 기기 판'으로 읽어 준비·보고를 안 내고 no_show/침묵 패로 접힌다. 맥 TetrisDuelStoreGame.swift:406
         * UserDefaults.set · TetrisDuelStore.swift:1092(신청 ok)·1170(수락 ok)). 머리는 소비자 함수에서 뽑는다(글자를 두 벌 적지 않는다).
         */
        val WORK_IMMEDIATE_KEY_PREFIXES: Set<String> = setOf(TetrisDuelStore.ownedMatchesKey(""))

        /** 앱 자리: [dataDir](WindowsAppPaths.dataDir — 패키지 안이면 이미 LocalCache 경로)/prefs.json. 근무 큐·소유 세션은 즉시 쓰기. */
        fun inDataDir(
            dataDir: String,
            debounceMillis: Long = DEFAULT_DEBOUNCE_MILLIS,
            immediateKeys: Set<String> = WORK_IMMEDIATE_KEYS,
            immediateKeyPrefixes: Set<String> = WORK_IMMEDIATE_KEY_PREFIXES,
        ): FileDesktopKeyValueStore = FileDesktopKeyValueStore(Path.of(dataDir, FILE_NAME), debounceMillis, immediateKeys, immediateKeyPrefixes)

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

        /** 엄격 해석(임시 채택·시험): 모양이 다르거나 값 하나라도 문자열이 아니면 예외. 값은 문자열만 받는다. */
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

        /** 살리기 한 번의 결과. [damaged] = 원본이 온전하지 않았다(버린 키가 없어도 — 끝이 잘림 등). */
        internal class Salvage(val values: Map<String, String>, val dropped: List<String>, val damaged: Boolean)

        internal fun strictUtf8(bytes: ByteArray): String =
            Charsets.UTF_8.newDecoder()
                .onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT)
                .decode(ByteBuffer.wrap(bytes))
                .toString()

        /**
         * 키별 살리기(W-14 #6). null = 살릴 틀이 없다(머리 `{"v":1,"values":{` 를 못 읽음 · 판이 1 이 아님). 순서:
         * ① 온전한 JSON 이면 문자열 값만 살리고 나머지 키만 버린다. ② JSON 이 깨졌으면 항목을 하나씩 훑어 `"키":"값"` 으로 끝까지 읽히고
         * 뒤가 `,`·`}`·끝인 항목만 살린다 — 못 읽은 항목은 그 키만 버리고 다음 `,"` 경계로 건너간다(인코더는 값 안의 `"` 를 늘 `\"` 로
         * 쓰므로 값 안에 `,"` 는 생기지 않는다). UTF-8 이 깨진 파일이면 대체 문자(U+FFFD)가 든 항목도 버린다(글자 하나가 바뀐 큐 JSON 을
         * 살린 척하지 않는다).
         */
        internal fun salvage(bytes: ByteArray): Salvage? {
            val strict = runCatching { strictUtf8(bytes) }.getOrNull()
            val text = strict ?: String(bytes, Charsets.UTF_8)
            if (strict != null) {
                val root = runCatching { Json.parseToJsonElement(text) }.getOrNull()
                if (root != null) {
                    val obj = root as? JsonObject ?: return null
                    val v = (obj["v"] as? JsonPrimitive)?.content?.toIntOrNull()
                    if (v != FORMAT_VERSION) return null
                    val inner = obj["values"] as? JsonObject ?: return null
                    val kept = TreeMap<String, String>()
                    val dropped = mutableListOf<String>()
                    for ((k, e) in inner) {
                        val p = e as? JsonPrimitive
                        if (p != null && p.isString) kept[k] = p.content else dropped += k
                    }
                    return Salvage(kept, dropped, damaged = dropped.isNotEmpty())
                }
            }
            return scan(text, utf8Damaged = strict == null)
        }

        private val HEADER = Regex("^\\s*\\{\\s*\"v\"\\s*:\\s*(\\d+)\\s*,\\s*\"values\"\\s*:\\s*\\{")

        private fun scan(text: String, utf8Damaged: Boolean): Salvage? {
            val header = HEADER.find(text) ?: return null
            if (header.groupValues[1].toIntOrNull() != FORMAT_VERSION) return null
            val kept = TreeMap<String, String>()
            val dropped = mutableListOf<String>()
            var pos = header.range.last + 1
            var resyncing = false
            while (true) {
                pos = skipWs(text, pos)
                if (pos >= text.length) break
                if (!resyncing && text[pos] == '}') break
                val entryStart = pos
                val key = readJsonString(text, pos)
                var value: Pair<String, Int>? = null
                if (key != null) {
                    var p = skipWs(text, key.second)
                    if (p < text.length && text[p] == ':') {
                        p = skipWs(text, p + 1)
                        value = readJsonString(text, p)
                        if (value != null) {
                            val after = skipWs(text, value.second)
                            if (after < text.length && text[after] != ',' && text[after] != '}') value = null
                        }
                    }
                }
                if (key != null && value != null) {
                    resyncing = false
                    if (utf8Damaged && (REPLACEMENT in key.first || REPLACEMENT in value.first)) {
                        dropped += key.first
                    } else {
                        kept[key.first] = value.first
                    }
                    val after = skipWs(text, value.second)
                    if (after >= text.length || text[after] == '}') break
                    pos = after + 1
                    continue
                }
                // 못 읽은 항목 — 이 구간의 첫 실패만 버린 키로 센다(경계 후보를 훑는 동안의 실패는 같은 손상이다).
                if (!resyncing) dropped += key?.first ?: UNREADABLE_KEY
                resyncing = true
                val next = text.indexOf(",\"", entryStart + 1)
                if (next < 0) break
                pos = next + 1
            }
            return Salvage(kept, dropped, damaged = true)
        }

        private const val REPLACEMENT = '\uFFFD'

        private fun skipWs(text: String, from: Int): Int {
            var i = from
            while (i < text.length && (text[i] == ' ' || text[i] == '\n' || text[i] == '\r' || text[i] == '\t')) i++
            return i
        }

        /** [from] 의 `"` 부터 JSON 문자열 하나. 성공이면 (내용, 닫는 따옴표 다음 자리), 아니면 null. */
        private fun readJsonString(text: String, from: Int): Pair<String, Int>? {
            if (from >= text.length || text[from] != '"') return null
            val out = StringBuilder()
            var i = from + 1
            while (i < text.length) {
                val c = text[i]
                when {
                    c == '"' -> return out.toString() to i + 1
                    c == '\\' -> {
                        if (i + 1 >= text.length) return null
                        when (val e = text[i + 1]) {
                            '"', '\\', '/' -> out.append(e)
                            'b' -> out.append('\b')
                            'f' -> out.append('\u000C')
                            'n' -> out.append('\n')
                            'r' -> out.append('\r')
                            't' -> out.append('\t')
                            'u' -> {
                                if (i + 6 > text.length) return null
                                val code = text.substring(i + 2, i + 6).toIntOrNull(16) ?: return null
                                out.append(code.toChar())
                                i += 4
                            }
                            else -> return null
                        }
                        i += 2
                    }
                    c < ' ' -> return null
                    else -> {
                        out.append(c)
                        i += 1
                    }
                }
            }
            return null
        }
    }
}
