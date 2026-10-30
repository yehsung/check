// W2-h3 Codex 사용량 진단 스캐너 — <codexHome>/{sessions,archived_sessions} 전량 1회 순회(빌드·KST 날짜당 1회).
// 원본: Sources/CheckCore/CheckTokenUsageDiagnostics.swift:179-648 · 포크 규칙 Sources/CheckCore/CheckTokenUsage.swift:670-812
// Windows 차이: Orca 홈이 없어 루트는 둘뿐 → dedupeCodexAliases(홈이 둘 이상일 때만 지운다)는 할 일이 없다(tokens.md §2 h1).
// autoreleasepool(맥 전용)은 해당 없음. 포크 규칙은 W2-h1 tokens/scan 의 같은 규칙 사본 — h1 이 공개하면 병합 때 그것을 부른다.
package com.yehsung.aingcheck.feature.desktop.tokens.diag

import com.yehsung.aingcheck.feature.desktop.tokens.scan.CodexForkRule
import com.yehsung.aingcheck.feature.desktop.tokens.scan.CodexForkTracker
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import java.io.ByteArrayOutputStream
import java.nio.file.Files
import java.nio.file.Path
import kotlin.streams.toList

object CodexUsageDiagnosticsScanner {
    /** "한 턴으로 설명할 수 없는 델타" 문턱(200만). */
    const val BIG_DELTA_THRESHOLD: Long = 2_000_000
    /** 파일 첫 이벤트가 이 값을 넘으면 resume 이월로 의심(carryFiles). */
    const val CARRY_THRESHOLD: Long = 200_000

    private val parser = Json { isLenient = false }

    /**
     * month 는 KST 'YYYY-MM'. 산식은 프로덕션 Codex 경로의 거울: 파일 첫 유효 token_count 는 기준선만(★), 그다음 필드별
     * `max(0, cum − 기준선)` 을 이벤트 timestamp(KST) 월에 귀속, info/total/timestamp 결손은 건너뛰되 기준선 유지,
     * 포크 복사 구간(자기 session_meta + 5초)은 앱 산식에 더하지 않고 forkCopyTokens 로만 잰다. legacyTotal 만 옛 세대 산식.
     */
    fun compute(codexHome: Path, month: String, appBuild: Long): CodexUsageDiagnostics {
        val files = listOf(codexHome.resolve("sessions"), codexHome.resolve("archived_sessions")).flatMap { rolloutFiles(it) }
        if (files.isEmpty()) return CodexUsageDiagnostics(appBuild = appBuild)
        val state = ScanState(month)
        files.forEachIndexed { index, file ->
            state.beginFile(index)
            streamLines(file) { state.ingest(it) }
            state.endFile()
        }
        return CodexUsageDiagnostics(
            filesTotal = files.size.toLong(),
            filesMonth = state.filesMonth,
            eventsMonth = state.eventsMonth,
            maxDelta = state.maxDelta,
            maxDeltaGapSeconds = state.maxDeltaGapSeconds,
            bigDeltaCount = state.bigDeltaCount,
            bigDeltaTotal = state.bigDeltaTotal,
            bigGapMedianSeconds = state.bigGapMedianSeconds(),
            carryFiles = state.carryFiles,
            carryTotal = state.carryTotal,
            dupEvents = state.duplicateKeyCount(),
            dupTokens = state.dupTokens,
            finalSum = state.finalSum,
            dedupTotal = state.appTotal - state.dupTokens,
            legacyTotal = state.legacyTotal,
            drops = state.drops,
            topFile = state.topFile,
            appBuild = appBuild,
            forkFiles = state.forkFiles,
            forkCopyTokens = state.forkCopyTokens,
        )
    }

    /** 루트 아래 `rollout-*.jsonl` 정규 파일, 경로 순(루트 상대 경로를 '/' 로 — Windows 구분자와 무관한 순서). */
    private fun rolloutFiles(root: Path): List<Path> {
        if (!Files.isDirectory(root)) return emptyList()
        val found = Files.walk(root).use { stream ->
            stream.filter { p ->
                val name = p.fileName?.toString() ?: return@filter false
                name.startsWith("rollout-") && name.substringAfterLast('.', "") == "jsonl" && Files.isRegularFile(p)
            }.toList()
        }
        return found.sortedBy { root.relativize(it).toString().replace('\\', '/') }
    }

    /** 1MB 조각으로 읽어 '\n' 마다 한 줄. 개행 없이 끝나는 마지막 줄도 넘긴다(진단은 다음이 없다). */
    private fun streamLines(file: Path, body: (ByteArray) -> Unit) {
        val input = try { Files.newInputStream(file) } catch (_: Exception) { return }
        input.use { stream ->
            val carry = ByteArrayOutputStream()
            val buffer = ByteArray(1 shl 20)
            while (true) {
                val n = stream.read(buffer)
                if (n <= 0) break
                var start = 0
                for (i in 0 until n) {
                    if (buffer[i] == 0x0A.toByte()) {
                        carry.write(buffer, start, i - start)
                        body(carry.toByteArray())
                        carry.reset()
                        start = i + 1
                    }
                }
                if (start < n) carry.write(buffer, start, n - start)
            }
            if (carry.size() > 0) body(carry.toByteArray())
        }
    }

    private class ScanState(private val month: String) {
        private class KeySighting(var lastFileIndex: Int, var fileCount: Int)
        private class FirstEvent(val cumulative: Long, val inMonth: Boolean)

        private var fileIndex = 0
        private var baseline: Long? = null
        private var baselineInput = 0L
        private var baselineOutput = 0L
        private var prevEventEpoch: Long? = null
        private var firstEvent: FirstEvent? = null
        private var monthContrib = 0L
        private var monthContribLegacy = 0L
        private var lastCumulativeInMonth = 0L
        private var touched = false
        private var fork = CodexForkTracker(startedAtZero = true, deadlineMicros = 0)
        private var forkCopyMonth = 0L

        var appTotal = 0L; private set
        var legacyTotal = 0L; private set
        var finalSum = 0L; private set
        var filesMonth = 0L; private set
        var eventsMonth = 0L; private set
        var maxDelta = 0L; private set
        var maxDeltaGapSeconds = 0L; private set
        var bigDeltaCount = 0L; private set
        var bigDeltaTotal = 0L; private set
        private val bigGaps = ArrayList<Long>()
        var drops = 0L; private set
        var carryFiles = 0L; private set
        var carryTotal = 0L; private set
        var topFile = 0L; private set
        var dupTokens = 0L; private set
        var forkFiles = 0L; private set
        var forkCopyTokens = 0L; private set
        private val sightings = HashMap<String, KeySighting>()

        fun beginFile(index: Int) {
            fileIndex = index
            baseline = null
            baselineInput = 0
            baselineOutput = 0
            prevEventEpoch = null
            firstEvent = null
            monthContrib = 0
            monthContribLegacy = 0
            lastCumulativeInMonth = 0
            touched = false
            fork = CodexForkTracker(startedAtZero = true, deadlineMicros = 0)
            forkCopyMonth = 0
        }

        fun endFile() {
            if (!touched) return
            filesMonth += 1
            if (fork.deadlineMicros > 0) forkFiles += 1
            forkCopyTokens += forkCopyMonth
            appTotal += monthContrib
            legacyTotal += monthContribLegacy
            finalSum += lastCumulativeInMonth
            topFile = maxOf(topFile, monthContrib)
            val first = firstEvent
            if (first != null && first.inMonth && first.cumulative > CARRY_THRESHOLD) {
                carryFiles += 1
                carryTotal += first.cumulative
            }
        }

        fun ingest(bytes: ByteArray) {
            val line = bytes.decodeToString()
            if (line.contains("session_meta")) {
                val meta = parseObject(line)
                if (meta != null && CodexForkRule.isSessionMeta(meta)) {
                    fork.observeSessionMeta(meta)
                    return
                }
            }
            if (!line.contains("token_count")) return
            val obj = parseObject(line) ?: return
            val payload = obj["payload"] as? JsonObject ?: return
            if (stringField(payload["type"]) != "token_count") return
            val info = payload["info"] as? JsonObject ?: return
            val total = info["total_token_usage"] as? JsonObject ?: return
            val timestamp = stringField(obj["timestamp"]) ?: return
            val monthKey = kstMonthKey(timestamp) ?: return
            val isCopy = fork.isCopy(timestamp)
            val inputCum = intField(total["input_tokens"])
            val outputCum = intField(total["output_tokens"])
            val cum = inputCum + outputCum
            val inMonth = monthKey == month
            if (firstEvent == null) firstEvent = FirstEvent(cum, inMonth)
            val prev = baseline
            if (inMonth && prev != null && cum < prev) drops += 1
            // ★ 기준선을 못 봤으면 델타 0(기준선만). 필드별 클램프.
            val delta = if (prev == null) 0L else maxOf(0L, inputCum - baselineInput) + maxOf(0L, outputCum - baselineOutput)
            val legacyDelta = maxOf(0L, cum - (prev ?: 0L))
            val epoch = utcEpochSeconds(timestamp)
            val previousEpoch = prevEventEpoch
            val gap = if (epoch == null || previousEpoch == null) 0L else maxOf(0L, epoch - previousEpoch)
            baseline = cum
            baselineInput = inputCum
            baselineOutput = outputCum
            prevEventEpoch = epoch
            if (!inMonth) return
            if (isCopy) {
                forkCopyMonth += delta
                monthContribLegacy += legacyDelta
                eventsMonth += 1
                touched = true
                lastCumulativeInMonth = cum
                return
            }
            monthContrib += delta
            monthContribLegacy += legacyDelta
            eventsMonth += 1
            touched = true
            lastCumulativeInMonth = cum
            if (delta > maxDelta) {
                maxDelta = delta
                maxDeltaGapSeconds = gap
            }
            if (delta > BIG_DELTA_THRESHOLD) {
                bigDeltaCount += 1
                bigDeltaTotal += delta
                bigGaps += gap
            }
            val key = "$timestamp\u0000$cum"
            val seen = sightings[key]
            if (seen != null) {
                if (seen.lastFileIndex != fileIndex) {
                    seen.lastFileIndex = fileIndex
                    seen.fileCount += 1
                    dupTokens += delta
                }
            } else {
                sightings[key] = KeySighting(fileIndex, 1)
            }
        }

        fun bigGapMedianSeconds(): Long {
            if (bigGaps.isEmpty()) return 0
            val sorted = bigGaps.sorted()
            return sorted[(sorted.size - 1) / 2]
        }

        fun duplicateKeyCount(): Long = sightings.values.count { it.fileCount > 1 }.toLong()
    }

    internal fun parseObject(line: String): JsonObject? = try {
        parser.parseToJsonElement(line) as? JsonObject
    } catch (_: Exception) {
        null
    }

    internal fun stringField(element: Any?): String? = (element as? JsonPrimitive)?.takeIf { it.isString }?.content

    /** NSNumber.int64Value — 글자·null·없음은 0. */
    private fun intField(element: Any?): Long {
        val p = element as? JsonPrimitive ?: return 0
        if (p.isString || p.content == "null") return 0
        p.booleanOrNull?.let { return if (it) 1 else 0 }
        return p.content.toLongOrNull() ?: p.content.toDoubleOrNull()?.toLong() ?: 0
    }

    private fun digitsAt(b: ByteArray): Boolean {
        if (b.size < 19) return false
        for (i in intArrayOf(0, 1, 2, 3, 5, 6, 8, 9, 11, 12, 14, 15, 17, 18)) if (b[i] < 48 || b[i] > 57) return false
        return true
    }

    private fun num(b: ByteArray, start: Int, len: Int): Int {
        var v = 0
        for (k in start until start + len) v = v * 10 + (b[k] - 48)
        return v
    }

    internal fun daysInMonth(year: Int, month: Int): Int = when (month) {
        1, 3, 5, 7, 8, 10, 12 -> 31
        4, 6, 9, 11 -> 30
        2 -> if ((year % 4 == 0 && year % 100 != 0) || year % 400 == 0) 29 else 28
        else -> 0
    }

    /** UTC 시각 글자 → KST 'YYYY-MM'(+9시간 넘어가면 다음 날). */
    internal fun kstMonthKey(s: String): String? {
        val b = s.encodeToByteArray()
        if (!digitsAt(b)) return null
        var year = num(b, 0, 4)
        var month = num(b, 5, 2)
        var day = num(b, 8, 2)
        val hour = num(b, 11, 2)
        if (month < 1 || month > 12 || day < 1 || day > daysInMonth(year, month) || hour > 23) return null
        if (hour + 9 >= 24) {
            day += 1
            if (day > daysInMonth(year, month)) {
                day = 1
                month += 1
                if (month > 12) { month = 1; year += 1 }
            }
        }
        return "${year.toString().padStart(4, '0')}-${month.toString().padStart(2, '0')}"
    }

    internal fun epochDays(year: Int, month: Int, day: Int): Long {
        val y = (if (month <= 2) year - 1 else year).toLong()
        val era = (if (y >= 0) y else y - 399) / 400
        val yearOfEra = y - era * 400
        val dayOfYear = (153 * (month + (if (month > 2) -3 else 9)) + 2) / 5 + day - 1
        val dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    internal fun utcEpochSeconds(s: String): Long? {
        val b = s.encodeToByteArray()
        if (!digitsAt(b)) return null
        val year = num(b, 0, 4); val month = num(b, 5, 2); val day = num(b, 8, 2)
        val hour = num(b, 11, 2); val minute = num(b, 14, 2); val second = num(b, 17, 2)
        if (month < 1 || month > 12 || day < 1 || day > daysInMonth(year, month) || hour > 23 || minute > 59 || second > 60) return null
        return epochDays(year, month, day) * 86_400 + hour * 3_600L + minute * 60L + second
    }
}
