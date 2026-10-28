// 원본: Sources/CheckCore/CheckTodoModel.swift:45-135(TodoFileSyncState · TodoFile 의 Codable 관용) · :446-503(TodoFileStore) @ 1b8260d
package com.yehsung.aingcheck.core.stores.now.todo

import com.yehsung.aingcheck.core.rules.format.SwiftDecodingError
import com.yehsung.aingcheck.core.rules.format.SwiftValue
import com.yehsung.aingcheck.core.rules.format.parseSwiftJson
import com.yehsung.aingcheck.core.rules.insights.KstCalendar
import com.yehsung.aingcheck.core.rules.todo.TodoFile
import com.yehsung.aingcheck.core.rules.todo.TodoFileSyncState
import com.yehsung.aingcheck.core.rules.todo.TodoItem
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * 할 일 파일이 사는 곳(바이트만 나른다). 프로덕션은 [JvmTodoFileSystem](Android 앱 전용 폴더 · 데스크톱 홈 폴더), 시험은 메모리판.
 * 경로는 절대 경로 글자다(조립이 폴더를 정한다 — Swift `AingSharedStorage.todoFileURL(userID:)`).
 */
interface TodoFileSystem {
    /** 파일 내용. 없으면 null. 읽다 실패하면 던진다(호출부가 손상으로 보고 백업한다). */
    fun read(path: String): ByteArray?

    /** 상위 폴더를 만들고 **원자적으로** 쓴다(같은 폴더의 임시 파일 → 이름 바꾸기). 쓰다 만 파일을 남기지 않는다. */
    fun writeAtomically(path: String, bytes: ByteArray)

    /** 옮긴다(손상 파일 백업). 실패는 삼킨다. */
    fun move(from: String, to: String)
}

/**
 * todos.json 의 로드/세이브(Swift `TodoFileStore`). 캐시와 **한 가지가 다르다** — 사용자가 손으로 쓴 문장이라 다시 만들 길이 없다.
 * 그래서 [load] 는 실패를 삼키지 않고 던지고(호출부가 원본을 백업하게), [save] 는 원자적으로 쓴다.
 *
 * 파일 모양(2세대, Swift Codable 과 같은 키): `{"version":2,"items":[…],"sync":{"watermarkMs":int|null,"pendingIDs":[uuid…],"heldRejectedIDs":[uuid…]}}`.
 * 항목 키는 `id · title · createdAt · updatedAt · completedAt? · deletedAt? · originDayKey`, 시각은 **참조일(2001-01-01) 기준 초**(Swift 기본 Date 전략).
 * Kotlin [TodoItem] 의 시각은 1970 기준 초라 `t − 978307200` 으로 쓰고 `+ 978307200` 으로 읽는다 — 시각은 이미 참조일 왕복을 거친 값이라
 * (`SwiftDate.since1970`) 두 수의 비가 2 안이어서 빼기가 정확하고(Sterbenz) 왕복이 비트까지 같다. id 는 소문자 uuid 로 쓴다
 * (읽기는 대소문자 무관 — Swift `UUID(uuidString:)`).
 *
 * 디코드 관용은 **비대칭**이다(Swift 그대로):
 * - version 없음 → 1세대. 있는데 정수가 아니면 손상.
 * - items 없음·깨짐(한 줄이라도) → **던진다**(손상 파일이 빈 목록으로 둔갑해 덮어써지지 않게 — 호출부가 백업).
 * - sync 없음·깨짐 → **던지지 않는다**. 파생 상태라 "전부 보낼 것 + watermark 없음"으로 출발한다(서버 LWW 가 같은 값을 다시 받아도 같다).
 * - 1세대(version 없음·1)는 모든 id 가 보낼 것이다.
 * - `heldRejectedIDs` 는 선택 칸: 없으면 빈 목록, 있는데 깨졌으면 sync 통째로 위 관용(전부 보낼 것)을 탄다.
 */
object TodoFileStore {
    private const val REFERENCE_DATE_OFFSET = 978_307_200.0

    /**
     * 사용자별 파일(Swift `TodoSharedFile.url(in:userID:)` · 맥 `TodoFileStore.defaultURL`). userID 는 파일명에 안전한 글자
     * (ASCII 영문·숫자·`-`·`_`)만 남긴다 — 그대로 붙이면 `..` 하나로 폴더를 벗어난다. 로그인 전(null · 빈 값)은 `todos.local.json`.
     */
    fun path(directory: String, userID: String?): String {
        val safe = (userID ?: "").filter { it in 'a'..'z' || it in 'A'..'Z' || it in '0'..'9' || it == '-' || it == '_' }
        val suffix = if (safe.isEmpty()) "local" else safe
        return directory.trimEnd('/') + "/todos.$suffix.json"
    }

    /** 파일이 없거나 비어 있으면 **빈 파일**로 시작한다(첫 실행 = 정상 경로). 내용이 있는데 읽을 수 없으면 던진다. */
    fun load(files: TodoFileSystem, path: String): TodoFile {
        val data = files.read(path) ?: return TodoFile(items = emptyList())
        if (data.isEmpty()) return TodoFile(items = emptyList())
        return decode(data.decodeToString())
    }

    fun save(files: TodoFileSystem, file: TodoFile, path: String) {
        files.writeAtomically(path, encode(file).encodeToByteArray())
    }

    /**
     * 손상 파일을 옮겨 둘 경로: 같은 폴더의 `todos.local.json.corrupt-20260812-134500`(KST). 확장자를 .json 으로 두지 않는 이유는 다음 실행이
     * 그걸 다시 목록으로 착각해 집어삼키지 않게, 시각을 붙이는 이유는 손상이 반복돼도 이전 백업을 덮어쓰지 않게(사용자 문장은 한 번도 못 버린다).
     */
    fun corruptedBackupPath(path: String, now: Double): String {
        val t = KstCalendar.localDateTime(now)
        fun p(n: Int, w: Int = 2) = n.toString().padStart(w, '0')
        val stamp = "${p(t.year, 4)}${p(t.month.ordinal + 1)}${p(t.day)}-${p(t.hour)}${p(t.minute)}${p(t.second)}"
        return "$path.corrupt-$stamp"
    }

    // ---------------------------------------------------------------- 인코드

    fun encode(file: TodoFile): String {
        val sync = JsonObject(linkedMapOf(
            // null 을 **싣는다**(키를 빼지 않는다) — 명세의 파일 모양 `watermarkMs: int|null` 을 글자 그대로 지킨다.
            "watermarkMs" to (file.sync.watermarkMs?.let { JsonPrimitive(it) } ?: JsonNull),
            "pendingIDs" to JsonArray(file.sync.pendingIDs.map { JsonPrimitive(it.lowercase()) }),
            "heldRejectedIDs" to JsonArray(file.sync.heldRejectedIDs.map { JsonPrimitive(it.lowercase()) }),
        ))
        return JsonObject(linkedMapOf(
            "version" to JsonPrimitive(file.version),
            "items" to JsonArray(file.items.map(::encodeItem)),
            "sync" to sync,
        )).toString()
    }

    private fun encodeItem(item: TodoItem): JsonObject {
        val fields = linkedMapOf<String, JsonElement>(
            "id" to JsonPrimitive(item.id.lowercase()),
            "title" to JsonPrimitive(item.title),
            "createdAt" to JsonPrimitive(item.createdAt - REFERENCE_DATE_OFFSET),
            "updatedAt" to JsonPrimitive(item.updatedAt - REFERENCE_DATE_OFFSET),
        )
        // 합성 Codable 의 Optional 은 nil 이면 키를 뺀다(encodeIfPresent).
        item.completedAt?.let { fields["completedAt"] = JsonPrimitive(it - REFERENCE_DATE_OFFSET) }
        item.deletedAt?.let { fields["deletedAt"] = JsonPrimitive(it - REFERENCE_DATE_OFFSET) }
        fields["originDayKey"] = JsonPrimitive(item.originDayKey)
        return JsonObject(fields)
    }

    // ---------------------------------------------------------------- 디코드

    /** 원문 → 파일. 읽을 수 없으면 [SwiftDecodingError]. */
    fun decode(text: String): TodoFile {
        val root = SwiftValue.obj(parseSwiftJson(text))
        val version = present(root, "version")?.let { SwiftValue.int(it).toInt() } ?: 1
        val itemsElement = present(root, "items") ?: throw SwiftDecodingError("keyNotFound", "items 가 없다")
        val items = SwiftValue.array(itemsElement).map(::decodeItem)
        val sync = if (version >= 2) {
            try {
                present(root, "sync")?.let(::decodeSync)
            } catch (e: SwiftDecodingError) {
                null
            }
        } else {
            null
        }
        return TodoFile(version, items, sync ?: TodoFileSyncState(null, items.map { it.id }))
    }

    private fun present(o: JsonObject, key: String): JsonElement? = o[key]?.takeIf { it !is JsonNull }

    private fun required(o: JsonObject, key: String): JsonElement =
        o[key]?.also { if (it is JsonNull) throw SwiftDecodingError("valueNotFound", "$key 가 null 이다") }
            ?: throw SwiftDecodingError("keyNotFound", "$key 가 없다")

    private fun uuid(element: JsonElement): String {
        val text = SwiftValue.string(element)
        if (!UUID_RE.matches(text)) throw SwiftDecodingError("dataCorrupted", "uuid 가 아니다: $text")
        return text.lowercase()
    }

    private fun date(element: JsonElement): Double = SwiftValue.double(element) + REFERENCE_DATE_OFFSET

    private fun decodeItem(element: JsonElement): TodoItem {
        val o = SwiftValue.obj(element)
        return TodoItem(
            id = uuid(required(o, "id")),
            title = SwiftValue.string(required(o, "title")),
            createdAt = date(required(o, "createdAt")),
            updatedAt = date(required(o, "updatedAt")),
            completedAt = present(o, "completedAt")?.let(::date),
            deletedAt = present(o, "deletedAt")?.let(::date),
            originDayKey = SwiftValue.string(required(o, "originDayKey")),
        )
    }

    private fun decodeSync(element: JsonElement): TodoFileSyncState {
        val o = SwiftValue.obj(element)
        val watermark = present(o, "watermarkMs")?.let(SwiftValue::int)
        val pending = SwiftValue.array(required(o, "pendingIDs")).map(::uuid)
        // 키가 없으면 빈 목록. 키가 있는데 깨졌으면 **던진다**(sync 통째로 "전부 보낼 것" — 붙잡힌 줄이 어정쩡하게 남지 않게).
        val held = present(o, "heldRejectedIDs")?.let { SwiftValue.array(it).map(::uuid) } ?: emptyList()
        return TodoFileSyncState(watermark, pending, held)
    }

    private val UUID_RE = Regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")
}
