// W2-h1 — 증분 토큰 스캐너(Claude · Codex → TokenUsageMonthly).
// 원본: Sources/CheckCore/CheckTokenUsage.swift:906-1995(TokenUsageIncrementalScanner · TokenUsageScanner). 골든: contract/golden/token-usage/scan/scanner.json.
// Windows 차이(지시서 tokens.md §2):
//  · 홈은 [DesktopAiHomes] 하나 — Orca(codexHomes 둘째 이후·orcaUserDataDirectory)를 뺀다. 루트 쌍 모양 (sessions, archived_sessions) 은 유지.
//    홈이 하나면 Swift dedupeCodexAliases 는 아무것도 버리지 않는다(같은 홈 안 이름 겹침은 둘 다 센다) → 옮기지 않는다.
//  · 안티그래비티 집계 0(D-E27 전). 안티그래비티 칸은 0·빈 맵 그대로 둔다.
//  · INV-CheckTokenUsage-0519b37b 이식: 안티그래비티 합(캐시읽기 포함) 정의는 핀 TokenUsageMonthly.antigravityTotal — 스캐너는 안티그래비티 칸을 쓰지 않는다.
//  · INV-CheckTokenUsage-d6d43ba3 이식: 안티그래비티 일별 = 월 합과 같은 네 값 정의 — Windows 는 집계 0(빈 맵)이라 어긋날 값이 없다.
//  · INV-CheckTokenUsage-249560a5 이식: total 에 안티그래비티를 넣지 않는다 — 핀 TokenUsageMonthly.total 그대로(골든 total 칸이 잰다).
//  · 맥 전용(옮기지 않음 → inv-na): ★ :1002 눈먼 안티그래비티 스캔 · ★ :1799·:1839 autoreleasepool.
// 내용 필드(message.content 등)는 읽지도 보관하지도 않는다 — usage·id·requestId·timestamp·type 만 본다(:925-927).
package com.yehsung.aingcheck.feature.desktop.tokens.scan

import com.yehsung.aingcheck.core.rules.insights.WorkDailyGrid
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.feature.desktop.DesktopAiHomes
import com.yehsung.aingcheck.feature.desktop.tokens.TokenUsageMonthly
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import java.io.IOException
import java.nio.ByteBuffer
import java.nio.channels.FileChannel
import java.nio.charset.CharacterCodingException
import java.nio.charset.CodingErrorAction
import java.nio.file.FileVisitResult
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.SimpleFileVisitor
import java.nio.file.StandardOpenOption
import java.nio.file.attribute.BasicFileAttributes
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneOffset
import kotlin.math.floor
import kotlin.math.roundToLong

object TokenUsageIncrementalScanner {
    /** 보관 경계 = 창 시작(Claude)·월 시작(Codex) − 48시간(월 경계 straddle 만 남긴다). */
    const val RETENTION_SLACK_SECONDS: Long = 48 * 3_600

    /** Claude Code 기본 cleanupPeriodDays(30) − 하루 여유. 가장 오래된 projects 파일이 이보다 오래면 그 다음 날부터 완전. */
    const val CLAUDE_CLEANUP_FLOOR_SECONDS: Long = 29 * 86_400

    private val KST: ZoneOffset = ZoneOffset.ofHours(9)
    private const val CHUNK = 1 shl 20
    private val USAGE_PATTERN = "\"usage\"".encodeToByteArray()
    private val ASSISTANT_PATTERN = "\"assistant\"".encodeToByteArray()
    private val TOKEN_COUNT_PATTERN = "token_count".encodeToByteArray()

    class Stats {
        var claudeFilesStatted = 0
        var claudeFilesRead = 0
        var claudeBytesRead = 0L
        var codexFilesStatted = 0
        var codexFilesRead = 0
        var codexBytesRead = 0L
        var codexForkCopyEvents = 0
        var entriesChanged = false
        var statesChanged = false
        val cacheChanged: Boolean get() = entriesChanged || statesChanged
        val changedParts: Set<TokenUsageCacheStore.Part>
            get() = buildSet {
                if (entriesChanged) add(TokenUsageCacheStore.Part.ENTRIES)
                if (statesChanged) add(TokenUsageCacheStore.Part.STATE)
            }
    }

    class Result(val cache: TokenUsageCache, val usage: TokenUsageMonthly, val stats: Stats)

    data class MonthBounds(val start: Long, val end: Long, val retentionStart: Long, val month: String)
    data class DayBounds(val start: Long, val end: Long, val date: String)
    data class WindowBounds(val start: Long, val retentionStart: Long, val startKey: String)
    data class MonthDayKeys(val month: String, val day: String, val utcDay: String)

    /** 처음부터 스캔(Swift TokenUsageScanner.scan). */
    fun scan(homes: DesktopAiHomes, now: SwiftDate): TokenUsageMonthly = update(TokenUsageCache(), homes, now).usage

    /**
     * 증분 스캔 한 번. 입력 캐시는 바꾸지 않는다(복사본을 고쳐 [Result.cache] 로 돌려준다).
     * 경로는 [homes] 로만 얻는다(홈 격리 — user.home·환경 변수를 직접 읽지 않는다). codexHome 은 부를 때마다 다시 푼다.
     */
    fun update(input: TokenUsageCache, homes: DesktopAiHomes, now: SwiftDate): Result {
        val cache = input.deepCopy()
        val stats = Stats()
        val nowSec = now.timeIntervalSince1970
        val month = monthBounds(nowSec)
        val monthStartTs14 = ts14(month.start)
        val monthEndTs14 = ts14(month.end)
        val codexRetentionMicros = month.retentionStart * 1_000_000
        val window = windowBounds(nowSec)
        val windowStartTs14 = ts14(window.start)
        val claudeRetentionTs14 = ts14(window.retentionStart)
        val claudeRetentionMicros = window.retentionStart * 1_000_000
        val todayDate = dayBounds(nowSec).date
        val dayBuckets = kstDayBuckets(window.start, month.end)

        evict(cache, claudeRetentionTs14, claudeRetentionMicros, codexRetentionMicros, stats)
        val oldestClaudeMtime = scanClaude(cache, homes.claudeDir(), window.start * 1_000_000, claudeRetentionTs14, stats)
        val roots = codexRoots(homes.codexHome())
        scanCodexFiles(
            cache, listCodexFiles(roots, month.start * 1_000_000), roots, month.month, utcRetainFromKey(month.month), stats,
        )
        val usage = totals(cache, month.month, monthStartTs14, monthEndTs14, windowStartTs14, dayBuckets, todayDate,
            utcRetainFromKey(month.month))
            .copy(windowStart = window.startKey, claudeCompleteFrom = claudeCompleteFromKey(oldestClaudeMtime, nowSec))
        return Result(cache, usage, stats)
    }

    // ── 경계 ────────────────────────────────────────────────────────────────────────────

    fun monthBounds(nowSeconds: Double): MonthBounds {
        val local = LocalDateTime.ofEpochSecond(floor(nowSeconds).toLong(), 0, KST)
        val first = LocalDate.of(local.year, local.monthValue, 1)
        val start = first.atStartOfDay().toEpochSecond(KST)
        return MonthBounds(start, first.plusMonths(1).atStartOfDay().toEpochSecond(KST), start - RETENTION_SLACK_SECONDS,
            monthString(local.year, local.monthValue))
    }

    fun kstMonthString(now: SwiftDate): String = monthBounds(now.timeIntervalSince1970).month

    fun dayBounds(nowSeconds: Double): DayBounds {
        val date = LocalDateTime.ofEpochSecond(floor(nowSeconds).toLong(), 0, KST).toLocalDate()
        return DayBounds(date.atStartOfDay().toEpochSecond(KST), date.plusDays(1).atStartOfDay().toEpochSecond(KST), dayString(date))
    }

    /** 일별 창 = 이번 주 월요일(KST) − 12주(WorkDailyGrid.windowStart, 13주). Claude 보관 하한은 그 − 48시간. */
    fun windowBounds(nowSeconds: Double): WindowBounds {
        val start = floor(WorkDailyGrid.windowStart(nowSeconds)).toLong()
        return WindowBounds(start, start - RETENTION_SLACK_SECONDS, dayBounds(start.toDouble()).date)
    }

    /** 가장 오래된 projects 파일 mtime 이 29일보다 오래면 그 KST 날의 다음 날, 아니면 "". transcripts 는 보지 않는다(:1291-1297). */
    fun claudeCompleteFromKey(oldestMtimeMicros: Long?, nowSeconds: Double): String {
        if (oldestMtimeMicros == null) return ""
        val oldest = oldestMtimeMicros.toDouble() / 1_000_000
        if (nowSeconds - oldest < CLAUDE_CLEANUP_FLOOR_SECONDS) return ""
        return dayBounds(dayBounds(oldest).end.toDouble()).date
    }

    /** [start, end) 의 KST 날마다 (그날 시작의 ts14(UTC), "yyyy-MM-dd"). KST 는 일광절약이 없어 하루 = 86,400초. */
    fun kstDayBuckets(start: Long, end: Long): List<Pair<Long, String>> {
        val out = ArrayList<Pair<Long, String>>()
        var day = start
        while (day < end) {
            out += ts14(day) to dayBounds(day.toDouble()).date
            day += 86_400
        }
        return out
    }

    /** Codex 루트 쌍 — 홈 하나(Windows: Orca 없음). */
    fun codexRoots(codexHome: Path): List<Path> = listOf(codexHome.resolve("sessions"), codexHome.resolve("archived_sessions"))

    /**
     * 사라진 rollout 의 압축 쌍둥이 후보: 같은 자리 `.zst` · archived_sessions/<이름>.zst · sessions/y/m/d/<이름>.zst.
     * 하나라도 있으면 상태를 동결(기여 유지)한다 — `.zst` 자체는 읽지 않는다(:1680-1705).
     */
    fun compressedTwinCandidates(path: String, roots: List<Path>): List<String> {
        val out = mutableListOf("$path.zst")
        val name = Path.of(path).fileName?.toString() ?: return out
        if (roots.size < 2 || !name.startsWith("rollout-")) return out
        val sessionsRoot = roots[0]
        val archivedRoot = roots[1]
        val archived = archivedRoot.resolve("$name.zst").toString()
        if (archived != out[0]) out += archived
        val date = name.removePrefix("rollout-")
        if (date.length >= 10) {
            val y = date.substring(0, 4)
            val m = date.substring(5, 7)
            val d = date.substring(8, 10)
            if (y.all(Char::isDigit) && m.all(Char::isDigit) && d.all(Char::isDigit)) {
                val restored = sessionsRoot.resolve(y).resolve(m).resolve(d).resolve("$name.zst").toString()
                if (restored !in out) out += restored
            }
        }
        return out
    }

    /** 이벤트 timestamp(앞 19자 UTC) → (KST 월, KST 일, UTC 일 = 앞 10자). 숫자 자리가 아니면 null. 범위 밖 칸은 달력처럼 넘긴다. */
    fun kstMonthDayKeys(s: String): MonthDayKeys? {
        val b = s.encodeToByteArray()
        if (b.size < 19) return null
        for (i in intArrayOf(0, 1, 2, 3, 5, 6, 8, 9, 11, 12, 14, 15, 17, 18)) {
            if (b[i] < 48 || b[i] > 57) return null
        }
        fun num(start: Int, len: Int): Long {
            var v = 0L
            for (k in start until start + len) v = v * 10 + (b[k] - 48)
            return v
        }
        val utc = try {
            LocalDate.of(num(0, 4).toInt(), 1, 1).plusMonths(num(5, 2) - 1).plusDays(num(8, 2) - 1).atStartOfDay()
                .plusHours(num(11, 2)).plusMinutes(num(14, 2)).plusSeconds(num(17, 2))
        } catch (e: java.time.DateTimeException) {
            return null
        }
        val k = LocalDateTime.ofEpochSecond(utc.toEpochSecond(ZoneOffset.UTC), 0, KST)
        return MonthDayKeys(monthString(k.year, k.monthValue), dayString(k.toLocalDate()), s.take(10))
    }

    /** UTC 일별 보존 하한 = 그 KST 월 1일의 전날("2026-10" → "2026-09-30"). 형식이 아니면 "". */
    fun utcRetainFromKey(monthString: String): String {
        val parts = monthString.split('-')
        if (parts.size != 2) return ""
        val y = parts[0].toIntOrNull() ?: return ""
        val m = parts[1].toIntOrNull() ?: return ""
        if (m !in 1..12) return ""
        return dayString(LocalDate.of(y, m, 1).minusDays(1))
    }

    // ── Claude ─────────────────────────────────────────────────────────────────────────

    /** projects·transcripts 아래(재귀)의 .jsonl. 돌려주는 값 = projects 파일 중 가장 오래된 mtime(완전성 하한의 근거, transcripts 제외). */
    private fun scanClaude(cache: TokenUsageCache, claudeDir: Path, cutoffMicros: Long, evictTs14: Long, stats: Stats): Long? {
        val isJsonl: (Path) -> Boolean = { pathExtension(it) == "jsonl" }
        val projectFiles = recentFiles(claudeDir.resolve("projects"), cutoffMicros, isJsonl)
        val files = projectFiles + recentFiles(claudeDir.resolve("transcripts"), cutoffMicros, isJsonl)
        val oldest = projectFiles.minOfOrNull { it.mtimeMicros }
        for (f in files) {
            stats.claudeFilesStatted += 1
            val key = f.path.toString()
            val prior = cache.claudeFileStates[key]
            if (prior != null && prior.size == f.size && prior.mtimeMicros == f.mtimeMicros) continue
            // 커졌고 mtime 이 뒤로 가지 않았으면 마지막 완결 줄 끝부터, 아니면(줄었거나 교체) 0 부터 — 엔트리는 키로 중복 제거되니 다시 읽어도 안전.
            val startOffset = if (prior != null && f.size >= prior.size && f.mtimeMicros >= prior.mtimeMicros) prior.consumedOffset else 0L
            var touched = false
            val read = readTail(f.path, startOffset) { bytes, from, to ->
                if (ingestClaudeLine(bytes, from, to, cache.claudeEntries, evictTs14)) touched = true
            } ?: continue
            stats.claudeFilesRead += 1
            stats.claudeBytesRead += read.second
            cache.claudeFileStates[key] = FileProgress(f.size, f.mtimeMicros, read.first)
            stats.statesChanged = true
            if (touched) stats.entriesChanged = true
        }
        return oldest
    }

    /** type=="assistant" + message.usage 줄만. 키 (message.id, requestId) — 없으면 "". 보관 하한(ts14 < evict) 밖은 담지 않는다. */
    private fun ingestClaudeLine(
        b: ByteArray, from: Int, to: Int, entries: MutableMap<ClaudeEntryKey, ClaudeEntry>, evictTs14: Long,
    ): Boolean {
        if (!contains(b, from, to, USAGE_PATTERN) || !contains(b, from, to, ASSISTANT_PATTERN)) return false
        val obj = parseObject(b, from, to) ?: return false
        if (obj.string("type") != "assistant") return false
        val timestamp = obj.string("timestamp") ?: return false
        val message = obj["message"] as? JsonObject ?: return false
        val usage = message["usage"] as? JsonObject ?: return false
        val ts = ts14FromTimestampPrefix(timestamp) ?: return false
        if (ts < evictTs14) return false
        val key = ClaudeEntryKey.of(message.string("id") ?: "", obj.string("requestId") ?: "")
        return ingest(key, ts, usage, entries)
    }

    /**
     * 같은 키가 여러 번(스트리밍 부분 줄·다른 파일) 오면 output 이 큰 쪽이 이긴다. ts14 는 언제나 max(창 귀속이 앞으로 당겨지지 않게).
     * output 이 같거나 작으면 값은 그대로 두고 ts14 만 올린다.
     */
    private fun ingest(key: ClaudeEntryKey, ts: Long, usage: JsonObject, entries: MutableMap<ClaudeEntryKey, ClaudeEntry>): Boolean {
        val output = intField(usage["output_tokens"])
        val existing = entries[key]
        if (existing != null) {
            val windowTs14 = maxOf(existing.ts14, ts)
            if (existing.output >= output) {
                if (windowTs14 != existing.ts14) {
                    entries[key] = existing.copy(ts14 = windowTs14)
                    return true
                }
                return false
            }
            entries[key] = entryOf(windowTs14, usage, output)
            return true
        }
        entries[key] = entryOf(ts, usage, output)
        return true
    }

    private fun entryOf(ts: Long, usage: JsonObject, output: Long) = ClaudeEntry(
        ts14 = ts,
        input = intField(usage["input_tokens"]),
        output = output,
        cacheRead = intField(usage["cache_read_input_tokens"]),
        cacheCreation = intField(usage["cache_creation_input_tokens"]),
    )

    // ── Codex ──────────────────────────────────────────────────────────────────────────

    private fun listCodexFiles(roots: List<Path>, cutoffMicros: Long): List<Listed> = roots.flatMap { root ->
        recentFiles(root, cutoffMicros) { it.fileName.toString().startsWith("rollout-") && pathExtension(it) == "jsonl" }
    }

    /**
     * rollout 마다 token_count 이벤트의 누적치(total_token_usage)를 필드별 `max(0, cum − 기준선)` 델타로 바꿔 이벤트 시각의 월·KST 일·UTC 일에 귀속.
     * - 오프셋 0 파싱의 첫 유효 이벤트는 기준선만(이전 이력이 없으니 누적치 전체가 새 소비가 아니다).
     * - info null·total 결손·파싱 실패·timestamp 없음은 건너뛰되 기준선을 바꾸지 않는다(다음 유효 이벤트가 흡수, :1423-1430).
     * - 포크 복사 구간 이벤트는 기준선만(CodexForkTracker).
     * - size·mtime 같으면 재읽기 0(월이 바뀌었으면 월 기여만 0 으로), 커졌으면 이어 읽기, 줄었으면 0 부터 새로.
     * - 기준선이 아직 없으면(유효 이벤트 전) 오프셋을 시작점에 둔다 — 다음에 같은 자리부터 다시 읽어 첫 이벤트를 기준선으로.
     */
    internal fun scanCodexFiles(
        cache: TokenUsageCache, files: List<Listed>, roots: List<Path>, monthString: String, utcRetainFrom: String, stats: Stats,
    ) {
        val seenPaths = HashSet<String>()
        val nameCounts = HashMap<String, Int>()
        for (f in files) nameCounts.merge(f.path.fileName.toString(), 1, Int::plus)
        for (f in files) {
            stats.codexFilesStatted += 1
            val path = f.path.toString()
            val prior = cache.codexFileStates[path]
            var startOffset = 0L
            var baseline: LongArray? = null
            var monthInput = 0L
            var monthOutput = 0L
            var monthCached = 0L
            var dayContrib = HashMap<String, Long>()
            var dayContribUTC = HashMap<String, Long>()
            var fork = CodexForkTracker(startedAtZero = true, deadlineMicros = 0)
            var copyEvents = 0
            if (prior != null) {
                val sameMonth = prior.monthKey == monthString
                if (prior.size == f.size && prior.mtimeMicros == f.mtimeMicros) {
                    if ((nameCounts[f.path.fileName.toString()] ?: 0) > 1 && !Files.exists(f.path)) continue
                    seenPaths += path
                    if (!sameMonth) {
                        cache.codexFileStates[path] = prior.copy(
                            monthKey = monthString, monthInput = 0, monthOutput = 0, monthCached = 0, dayContrib = emptyMap(),
                            dayContribUTC = prior.dayContribUTC.filterKeys { it >= utcRetainFrom },
                        )
                        stats.statesChanged = true
                    }
                    continue
                }
                if (f.size >= prior.size && f.mtimeMicros >= prior.mtimeMicros) {
                    startOffset = prior.consumedOffset
                    baseline = if (prior.consumedOffset > 0) longArrayOf(prior.prevInput, prior.prevOutput, prior.prevCached) else null
                    fork = CodexForkTracker(startedAtZero = prior.consumedOffset == 0L, deadlineMicros = prior.forkCopyDeadlineMicros)
                    if (sameMonth) {
                        monthInput = prior.monthInput
                        monthOutput = prior.monthOutput
                        monthCached = prior.monthCached
                        dayContrib = HashMap(prior.dayContrib)
                    }
                    dayContribUTC = HashMap(prior.dayContribUTC.filterKeys { it >= utcRetainFrom })
                }
            }
            val read = readTail(f.path, startOffset) { b, from, to ->
                if (contains(b, from, to, CodexForkRule.SESSION_META_PATTERN)) {
                    val meta = parseObject(b, from, to)
                    if (meta != null && CodexForkRule.isSessionMeta(meta)) {
                        fork.observeSessionMeta(meta)
                        return@readTail
                    }
                }
                if (!contains(b, from, to, TOKEN_COUNT_PATTERN)) return@readTail
                val obj = parseObject(b, from, to) ?: return@readTail
                val payload = obj["payload"] as? JsonObject ?: return@readTail
                if (payload.string("type") != "token_count") return@readTail
                val info = payload["info"] as? JsonObject ?: return@readTail
                val total = info["total_token_usage"] as? JsonObject ?: return@readTail
                val ts = obj.string("timestamp") ?: return@readTail
                val keys = kstMonthDayKeys(ts) ?: return@readTail
                val input = intField(total["input_tokens"])
                val output = intField(total["output_tokens"])
                val cached = intField(total["cached_input_tokens"])
                if (fork.isCopy(ts)) {
                    baseline = longArrayOf(input, output, cached)
                    copyEvents += 1
                    return@readTail
                }
                val prev = baseline
                if (prev != null) {
                    val dIn = maxOf(0L, input - prev[0])
                    val dOut = maxOf(0L, output - prev[1])
                    val dCached = maxOf(0L, cached - prev[2])
                    if (keys.month == monthString) {
                        monthInput += dIn
                        monthOutput += dOut
                        monthCached += dCached
                        if (dIn + dOut > 0) dayContrib.merge(keys.day, dIn + dOut, Long::plus)
                    }
                    if (dIn + dOut > 0 && keys.utcDay >= utcRetainFrom) dayContribUTC.merge(keys.utcDay, dIn + dOut, Long::plus)
                }
                baseline = longArrayOf(input, output, cached)
            } ?: continue
            seenPaths += path
            stats.codexFilesRead += 1
            stats.codexBytesRead += read.second
            stats.codexForkCopyEvents += copyEvents
            val last = baseline
            cache.codexFileStates[path] = CodexFileProgress(
                size = f.size, mtimeMicros = f.mtimeMicros, consumedOffset = if (last == null) startOffset else read.first,
                prevInput = last?.get(0) ?: 0, prevOutput = last?.get(1) ?: 0, prevCached = last?.get(2) ?: 0,
                monthKey = monthString, monthInput = monthInput, monthOutput = monthOutput, monthCached = monthCached,
                dayContrib = dayContrib, forkCopyDeadlineMicros = fork.deadlineMicros, dayContribUTC = dayContribUTC,
            )
            stats.statesChanged = true
        }
        // 정리: 이번 달 상태인데 이번에 못 본 파일 — 아직 있으면 유지, 같은 이름을 다른 루트에서 봤으면(옮김) 지움,
        // 압축 쌍둥이가 있으면 동결(기여 유지), 아니면 지움. 지난달 상태는 그대로(evict 가 mtime 으로 정리).
        val before = cache.codexFileStates.size
        val seenNames = seenPaths.mapTo(HashSet()) { Path.of(it).fileName?.toString() ?: "" }
        cache.codexFileStates = cache.codexFileStates.filterTo(HashMap()) { (path, state) ->
            when {
                state.monthKey != monthString -> true
                path in seenPaths -> true
                Files.exists(Path.of(path)) -> true
                (Path.of(path).fileName?.toString() ?: "") in seenNames -> false
                else -> compressedTwinCandidates(path, roots).any { Files.exists(Path.of(it)) }
            }
        }
        if (cache.codexFileStates.size != before) stats.statesChanged = true
    }

    // ── 합계 ────────────────────────────────────────────────────────────────────────────

    /**
     * ★ INV-CheckTokenUsage-0719ed57 이식: usage.total 과 usage.todayTotal 의 정의는 건드리지 않는다(서버가 옛 표와 같은 단위로 읽는다) —
     * total 은 핀 TokenUsageMonthly.total(Codex 캐시읽기·안티그래비티 제외), todayTotal = 오늘 claudeDaily + codexDaily.
     */
    private fun totals(
        cache: TokenUsageCache, month: String, monthStartTs14: Long, monthEndTs14: Long, windowStartTs14: Long,
        dayBuckets: List<Pair<Long, String>>, todayDate: String, utcRetainFrom: String,
    ): TokenUsageMonthly {
        var cIn = 0L
        var cOut = 0L
        var cRead = 0L
        var cCreate = 0L
        val claudeDaily = HashMap<String, Long>()
        for (e in cache.claudeEntries.values) {
            if (e.ts14 < windowStartTs14 || e.ts14 >= monthEndTs14) continue
            if (e.ts14 >= monthStartTs14) {
                cIn += e.input
                cOut += e.output
                cRead += e.cacheRead
                cCreate += e.cacheCreation
            }
            dayKey(e.ts14, dayBuckets)?.let { claudeDaily.merge(it, e.input + e.output + e.cacheRead + e.cacheCreation, Long::plus) }
        }
        var xIn = 0L
        var xOut = 0L
        var xCached = 0L
        val codexDaily = HashMap<String, Long>()
        val codexDailyUTC = HashMap<String, Long>()
        for (s in cache.codexFileStates.values) {
            if (s.monthKey == month) {
                xIn += s.monthInput
                xOut += s.monthOutput
                xCached += s.monthCached
                for ((day, delta) in s.dayContrib) codexDaily.merge(day, delta, Long::plus)
            }
            for ((day, delta) in s.dayContribUTC) if (day >= utcRetainFrom) codexDailyUTC.merge(day, delta, Long::plus)
        }
        return TokenUsageMonthly(
            month = month, claudeInput = cIn, claudeOutput = cOut, claudeCacheRead = cRead, claudeCacheCreation = cCreate,
            codexInput = xIn, codexOutput = xOut, codexCacheRead = xCached,
            todayTotal = (claudeDaily[todayDate] ?: 0) + (codexDaily[todayDate] ?: 0), todayDate = todayDate,
            claudeDaily = claudeDaily, codexDaily = codexDaily, codexDailyUTC = codexDailyUTC,
        )
    }

    private fun dayKey(ts14: Long, buckets: List<Pair<Long, String>>): String? {
        var lo = 0
        var hi = buckets.size
        while (lo < hi) {
            val mid = (lo + hi) / 2
            if (buckets[mid].first <= ts14) lo = mid + 1 else hi = mid
        }
        return if (lo > 0) buckets[lo - 1].second else null
    }

    private fun evict(cache: TokenUsageCache, claudeEvictTs14: Long, claudeEvictMicros: Long, codexEvictMicros: Long, stats: Stats) {
        val beforeEntries = cache.claudeEntries.size
        cache.claudeEntries.values.removeIf { it.ts14 < claudeEvictTs14 }
        if (cache.claudeEntries.size != beforeEntries) stats.entriesChanged = true
        val beforeClaude = cache.claudeFileStates.size
        cache.claudeFileStates.values.removeIf { it.mtimeMicros < claudeEvictMicros }
        val beforeCodex = cache.codexFileStates.size
        cache.codexFileStates.values.removeIf { it.mtimeMicros < codexEvictMicros }
        if (cache.claudeFileStates.size != beforeClaude || cache.codexFileStates.size != beforeCodex) stats.statesChanged = true
    }

    // ── 파일 ────────────────────────────────────────────────────────────────────────────

    internal class Listed(val path: Path, val size: Long, val mtimeMicros: Long)

    /** root 아래(재귀, 심볼릭 링크 안 따름) 일반 파일 중 이름이 맞고 mtime ≥ cutoff 인 것. 경로 글자 순(결정적). 없는 root 는 빈 목록. */
    private fun recentFiles(root: Path, cutoffMicros: Long, matching: (Path) -> Boolean): List<Listed> {
        if (!Files.isDirectory(root)) return emptyList()
        val out = ArrayList<Listed>()
        try {
            Files.walkFileTree(root, object : SimpleFileVisitor<Path>() {
                override fun visitFile(file: Path, attrs: BasicFileAttributes): FileVisitResult {
                    if (!matching(file) || !attrs.isRegularFile) return FileVisitResult.CONTINUE
                    val mtime = micros(attrs)
                    if (mtime >= cutoffMicros) out += Listed(file, attrs.size(), mtime)
                    return FileVisitResult.CONTINUE
                }

                override fun visitFileFailed(file: Path, exc: IOException): FileVisitResult = FileVisitResult.CONTINUE
            })
        } catch (e: IOException) {
            // 열거 중 사라진 폴더 등 — 그때까지 모은 것만.
        }
        out.sortBy { it.path.toString() }
        return out
    }

    private fun micros(attrs: BasicFileAttributes): Long {
        val t = attrs.lastModifiedTime().toInstant()
        return t.epochSecond * 1_000_000 + (t.nano / 1_000.0).roundToLong()
    }

    private fun pathExtension(path: Path): String {
        val name = path.fileName?.toString() ?: return ""
        val dot = name.lastIndexOf('.')
        return if (dot > 0) name.substring(dot + 1) else ""
    }

    /**
     * startOffset 부터 끝까지 1MB 조각으로 읽어 완결 줄(0x0A 앞, \r 은 남는다 — JSON 공백)마다 body 를 부른다.
     * 돌려주는 값 = (마지막 완결 줄 끝의 절대 오프셋, 읽은 바이트). 개행 없는 꼬리는 소비하지 않는다. 열 수 없으면 null.
     * 읽기는 공유 모드(다른 프로세스가 쓰는 중인 파일 — Windows NIO 기본 FILE_SHARE_READ|WRITE|DELETE).
     */
    private fun readTail(path: Path, startOffset: Long, body: (ByteArray, Int, Int) -> Unit): Pair<Long, Long>? {
        val channel = try {
            FileChannel.open(path, StandardOpenOption.READ)
        } catch (e: IOException) {
            return null
        } catch (e: SecurityException) {
            return null
        }
        channel.use { ch ->
            if (startOffset > 0) {
                try {
                    ch.position(startOffset)
                } catch (e: IOException) {
                    return null
                }
            }
            val buffer = ByteBuffer.allocate(CHUNK)
            var carry = ByteArray(0)
            var carryLen = 0
            var consumed = startOffset
            var absBase = startOffset
            var bytesRead = 0L
            while (true) {
                buffer.clear()
                val n = try {
                    ch.read(buffer)
                } catch (e: IOException) {
                    -1
                }
                if (n <= 0) break
                bytesRead += n
                val a = buffer.array()
                var start = 0
                for (i in 0 until n) {
                    if (a[i] != 0x0A.toByte()) continue
                    if (carryLen == 0) {
                        body(a, start, i)
                    } else {
                        carry = append(carry, carryLen, a, start, i)
                        carryLen += i - start
                        body(carry, 0, carryLen)
                        carryLen = 0
                    }
                    consumed = absBase + i + 1
                    start = i + 1
                }
                if (start < n) {
                    carry = append(carry, carryLen, a, start, n)
                    carryLen += n - start
                }
                absBase += n
            }
            return consumed to bytesRead
        }
    }

    private fun append(carry: ByteArray, carryLen: Int, src: ByteArray, from: Int, to: Int): ByteArray {
        val need = carryLen + (to - from)
        val dst = if (need <= carry.size) carry else carry.copyOf(maxOf(need, carry.size * 2))
        src.copyInto(dst, carryLen, from, to)
        return dst
    }

    private fun contains(h: ByteArray, from: Int, to: Int, needle: ByteArray): Boolean {
        val n = needle.size
        if (n == 0 || to - from < n) return false
        val first = needle[0]
        val limit = to - n
        var i = from
        while (i <= limit) {
            if (h[i] == first) {
                var j = 1
                while (j < n && h[i + j] == needle[j]) j += 1
                if (j == n) return true
            }
            i += 1
        }
        return false
    }

    /** UTF-8(엄격) → JSON 객체. 잘못된 UTF-8·깨진 JSON·객체가 아닌 값은 null(Swift JSONSerialization `as? [String: Any]`). */
    private fun parseObject(b: ByteArray, from: Int, to: Int): JsonObject? {
        val text = try {
            Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT)
                .decode(ByteBuffer.wrap(b, from, to - from)).toString()
        } catch (e: CharacterCodingException) {
            return null
        }
        return try {
            Json.parseToJsonElement(text) as? JsonObject
        } catch (e: Exception) {
            null
        }
    }

    /** Swift `(value as? NSNumber).int64Value` — 숫자는 0 쪽으로 버림, 불은 1/0, 글자·null·없음은 0. */
    internal fun intField(value: JsonElement?): Long {
        val p = value as? JsonPrimitive ?: return 0
        if (p.isString) return 0
        p.booleanOrNull?.let { return if (it) 1 else 0 }
        return p.content.toLongOrNull() ?: p.content.toDoubleOrNull()?.toLong() ?: 0
    }

    /** 타임스탬프 앞 19자의 숫자 14개(yyyyMMddHHmmss) — 뒤의 오프셋 표기는 보지 않는다(UTC 로 읽음). */
    internal fun ts14FromTimestampPrefix(s: String): Long? {
        val b = s.encodeToByteArray()
        if (b.size < 19) return null
        var v = 0L
        for (i in intArrayOf(0, 1, 2, 3, 5, 6, 8, 9, 11, 12, 14, 15, 17, 18)) {
            val c = b[i]
            if (c < 48 || c > 57) return null
            v = v * 10 + (c - 48)
        }
        return v
    }

    internal fun ts14(epochSeconds: Long): Long {
        val t = LocalDateTime.ofEpochSecond(epochSeconds, 0, ZoneOffset.UTC)
        return ((((t.year.toLong() * 100 + t.monthValue) * 100 + t.dayOfMonth) * 100 + t.hour) * 100 + t.minute) * 100 + t.second
    }

    private fun monthString(year: Int, month: Int): String = pad(year, 4) + "-" + pad(month, 2)

    private fun dayString(d: LocalDate): String = pad(d.year, 4) + "-" + pad(d.monthValue, 2) + "-" + pad(d.dayOfMonth, 2)

    private fun pad(v: Int, width: Int): String = v.toString().padStart(width, '0')
}
