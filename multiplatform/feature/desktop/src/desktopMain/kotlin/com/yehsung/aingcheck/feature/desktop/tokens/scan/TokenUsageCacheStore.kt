// W2-h1 — 증분 캐시의 디스크 저장(핫/콜드 두 파일).
// 원본: Sources/CheckCore/CheckTokenUsage.swift:484-503·552-656(압축 튜플 인코딩)·814-904(TokenUsageCacheStore).
// <base 확장자 뺀 이름>.state.json = {"schemaVersion":2,"state":{claudeFileStates, claudeEntries:{}, codexFileStates, codexSchemaVersion}}
// <base 확장자 뺀 이름>.entries.json = {16진 키: [ts14, input, output, cacheRead, cacheCreation]}
// 레이아웃 버전이 다르거나 엔트리 파일이 상했으면(16진 아닌 키 하나라도) 통째로 버리고 빈 캐시(전체 재스캔 1회).
// 위치(base)는 조립 지점이 앱 데이터 폴더로 넘긴다 — 이 파일은 홈·환경 변수를 읽지 않는다.
package com.yehsung.aingcheck.feature.desktop.tokens.scan

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.longOrNull
import kotlinx.serialization.json.put
import java.io.IOException
import java.nio.file.AtomicMoveNotSupportedException
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.StandardCopyOption

object TokenUsageCacheStore {
    const val CURRENT_SCHEMA_VERSION = 2

    enum class Part { STATE, ENTRIES }

    fun stateFile(base: Path): Path = base.resolveSibling(stem(base) + ".state.json")

    fun entriesFile(base: Path): Path = base.resolveSibling(stem(base) + ".entries.json")

    fun load(base: Path): TokenUsageCache {
        try {
            Files.deleteIfExists(base)   // 옛 모놀리식 파일(맥 v0.2.37 이하 모양) — Windows 엔 없지만 같은 규칙.
        } catch (e: IOException) {
            // 무시 — 다음 로드에서 다시.
        }
        return try {
            val envelope = Json.parseToJsonElement(Files.readString(stateFile(base))) as? JsonObject ?: return TokenUsageCache()
            if ((envelope["schemaVersion"] as? JsonPrimitive)?.longOrNull != CURRENT_SCHEMA_VERSION.toLong()) return TokenUsageCache()
            val state = envelope["state"] as? JsonObject ?: return TokenUsageCache()
            val entries = decodeEntries(Json.parseToJsonElement(Files.readString(entriesFile(base))) as? JsonObject ?: return TokenUsageCache(),
                strict = true) ?: return TokenUsageCache()
            decodeState(state).also { it.claudeEntries.putAll(entries) }
        } catch (e: Exception) {
            TokenUsageCache()
        }
    }

    /** 요청한 쪽만 다시 쓴다. 한쪽 파일이 없으면 그쪽도 쓴다(짝이 어긋난 채 남지 않게). 임시 파일 → 원자 이름바꾸기. */
    fun save(cache: TokenUsageCache, parts: Set<Part>, base: Path): Boolean {
        return try {
            base.parent?.let { Files.createDirectories(it) }
            val todo = parts.toMutableSet()
            if (!Files.exists(entriesFile(base))) todo += Part.ENTRIES
            if (!Files.exists(stateFile(base))) todo += Part.STATE
            if (Part.ENTRIES in todo) writeAtomic(entriesFile(base), encodeEntries(cache.claudeEntries).toString())
            if (Part.STATE in todo) {
                val envelope = buildJsonObject {
                    put("schemaVersion", CURRENT_SCHEMA_VERSION)
                    put("state", encodeState(cache))
                }
                writeAtomic(stateFile(base), envelope.toString())
            }
            true
        } catch (e: IOException) {
            false
        }
    }

    internal fun encodeState(cache: TokenUsageCache): JsonObject = buildJsonObject {
        put("claudeFileStates", JsonObject(cache.claudeFileStates.mapValues { (_, p) -> longs(p.size, p.mtimeMicros, p.consumedOffset) }))
        put("claudeEntries", JsonObject(emptyMap()))
        put("codexFileStates", JsonObject(cache.codexFileStates.mapValues { (_, p) ->
            buildJsonArray {
                add(JsonPrimitive(p.size)); add(JsonPrimitive(p.mtimeMicros)); add(JsonPrimitive(p.consumedOffset))
                add(JsonPrimitive(p.prevInput)); add(JsonPrimitive(p.prevOutput)); add(JsonPrimitive(p.prevCached))
                add(JsonPrimitive(p.monthKey))
                add(JsonPrimitive(p.monthInput)); add(JsonPrimitive(p.monthOutput)); add(JsonPrimitive(p.monthCached))
                add(longMap(p.dayContrib))
                add(JsonPrimitive(p.forkCopyDeadlineMicros))
                add(longMap(p.dayContribUTC))
            }
        }))
        put("codexSchemaVersion", cache.codexSchemaVersion)
    }

    /** 스키마 게이트: codexSchemaVersion 이 현재와 다르면 codex 상태만 버린다(Claude 상태는 유지) — 다음 스캔에서 codex 전체 재파싱. */
    internal fun decodeState(state: JsonObject): TokenUsageCache {
        val cache = TokenUsageCache()
        (state["claudeFileStates"] as? JsonObject)?.forEach { (path, v) ->
            val a = v as? JsonArray ?: return@forEach
            if (a.size >= 3) cache.claudeFileStates[path] = FileProgress(a.long(0), a.long(1), a.long(2))
        }
        (state["claudeEntries"] as? JsonObject)?.let { raw -> decodeEntries(raw, strict = false)?.let(cache.claudeEntries::putAll) }
        val version = (state["codexSchemaVersion"] as? JsonPrimitive)?.longOrNull ?: 0
        if (version == TokenUsageCache.CURRENT_CODEX_SCHEMA_VERSION.toLong()) {
            (state["codexFileStates"] as? JsonObject)?.forEach { (path, v) ->
                val a = v as? JsonArray ?: return@forEach
                if (a.size < 3) return@forEach
                cache.codexFileStates[path] = CodexFileProgress(
                    size = a.long(0), mtimeMicros = a.long(1), consumedOffset = a.long(2),
                    prevInput = a.long(3), prevOutput = a.long(4), prevCached = a.long(5),
                    monthKey = (a.getOrNull(6) as? JsonPrimitive)?.takeIf { it.isString }?.content ?: "",
                    monthInput = a.long(7), monthOutput = a.long(8), monthCached = a.long(9),
                    dayContrib = a.map(10), forkCopyDeadlineMicros = a.long(11), dayContribUTC = a.map(12),
                )
            }
        }
        cache.codexSchemaVersion = TokenUsageCache.CURRENT_CODEX_SCHEMA_VERSION
        return cache
    }

    internal fun encodeEntries(entries: Map<ClaudeEntryKey, ClaudeEntry>): JsonObject =
        JsonObject(entries.entries.associate { (k, e) -> k.hex to longs(e.ts14, e.input, e.output, e.cacheRead, e.cacheCreation) })

    /** strict 면 16진이 아닌 키 하나라도 있으면 null(상한 콜드 파일 → 폐기). lenient 면 옛 문자열 키("id\0req")를 해시해 받는다. */
    internal fun decodeEntries(raw: JsonObject, strict: Boolean): Map<ClaudeEntryKey, ClaudeEntry>? {
        val out = HashMap<ClaudeEntryKey, ClaudeEntry>(raw.size * 2)
        for ((s, v) in raw) {
            val a = v as? JsonArray ?: if (strict) return null else continue
            val key = ClaudeEntryKey.fromHex(s) ?: if (strict) return null else ClaudeEntryKey.ofDedupeString(s)
            out[key] = ClaudeEntry(a.long(0), a.long(1), a.long(2), a.long(3), a.long(4))
        }
        return out
    }

    private fun longs(vararg v: Long): JsonArray = JsonArray(v.map { JsonPrimitive(it) })

    private fun longMap(m: Map<String, Long>): JsonObject = JsonObject(m.mapValues { JsonPrimitive(it.value) })

    private fun JsonArray.long(i: Int): Long = (getOrNull(i) as? JsonPrimitive)?.longOrNull ?: 0

    private fun JsonArray.map(i: Int): Map<String, Long> =
        (getOrNull(i) as? JsonObject)?.mapNotNull { (k, v) -> (v as? JsonPrimitive)?.longOrNull?.let { k to it } }?.toMap() ?: emptyMap()

    private fun stem(base: Path): String {
        val name = base.fileName.toString()
        val dot = name.lastIndexOf('.')
        return if (dot > 0) name.substring(0, dot) else name
    }

    private fun writeAtomic(target: Path, text: String) {
        val tmp = target.resolveSibling(target.fileName.toString() + ".tmp")
        Files.writeString(tmp, text)
        try {
            Files.move(tmp, target, StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE)
        } catch (e: AtomicMoveNotSupportedException) {
            Files.move(tmp, target, StandardCopyOption.REPLACE_EXISTING)
        }
    }

    @Suppress("unused")
    private fun JsonElement.asObject(): JsonObject? = this as? JsonObject
}
