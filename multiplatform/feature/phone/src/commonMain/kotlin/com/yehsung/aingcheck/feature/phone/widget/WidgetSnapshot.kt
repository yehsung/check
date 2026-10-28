// 원본: Sources/CheckMobileShared/WidgetSnapshot.swift @ 3bd04bd
package com.yehsung.aingcheck.feature.phone.widget

import com.yehsung.aingcheck.core.rules.ailimit.AILimitProvider
import com.yehsung.aingcheck.core.rules.text.TextScalars
import com.yehsung.aingcheck.core.stores.me.MeAILimitWidgetPanel
import com.yehsung.aingcheck.core.stores.me.MeAILimitWidgetRow
import com.yehsung.aingcheck.core.wire.SwiftDate
import com.yehsung.aingcheck.core.wire.json.SwiftDecodableSerializer
import com.yehsung.aingcheck.core.wire.json.SwiftDecoding
import com.yehsung.aingcheck.core.wire.json.SwiftJson
import com.yehsung.aingcheck.core.wire.json.SwiftKeyed
import com.yehsung.aingcheck.core.wire.json.SwiftValueDecoder
import kotlinx.serialization.json.JsonNull
import com.yehsung.aingcheck.core.wire.json.lossyList
import com.yehsung.aingcheck.core.wire.json.swiftTry
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * 위젯이 읽는 **유일한 모양**(SPEC-ios §4). 앱이 데이터를 받을 때마다 앱 전용 폴더의 `widget-snapshot.json` 에 쓴다(Android 는 위젯도
 * 같은 프로세스라 App Group 이 없다 — E§7.1).
 *
 * 규칙(Swift 그대로)
 * - 위젯은 네트워크를 쓰지 않고 이 파일만 그린다. 할 일 체크만 예외(같은 할 일 파일 + 조정 구간).
 * - **더하기만 한다.** 새 칸은 옵셔널로 더하고 [version] 을 올리지 않는다. 디코드는 모든 칸을 관대하게 읽는다(없는 칸은 기본값, 모르는 칸은 무시) —
 *   업데이트 직후 옛 앱이 쓴 파일을 새 위젯이(또는 반대로) 읽는 창이 실재한다.
 * - 파일이 없으면 = 로그아웃 상태. 로그아웃은 파일을 지운다.
 *
 * 리밋 칸의 값 모양은 나 탭(W2-c)의 [MeAILimitWidgetPanel] · [MeAILimitWidgetRow] 를 그대로 쓴다(두 벌 금지) — 이 파일은 그 값의
 * **직렬화 · 관대한 디코더**(Swift `init(from:)`)를 맡는다.
 */
data class WidgetSnapshot(
    val version: Int = CURRENT_VERSION,
    /** 앱이 이 스냅숏을 만든 시각. 위젯 오른쪽 아래 "N분 전". */
    val generatedAt: SwiftDate,
    /** 내 상태. 아직 못 받았으면 null(지금 탭이 한 번이라도 불러오기 전). */
    val me: Me? = null,
    /** 지금 근무 중인 사람(우리 팀 먼저 정렬해 쓴다). */
    val working: List<WorkingPerson> = emptyList(),
    /** 오늘 할 일 앞부분. */
    val todosPreview: List<TodoPreview> = emptyList(),
    /** 착용 캐릭터 id(이 빌드가 아는 id 로 접은 값). null = 아직 모른다. 읽을 때 모르는 id·null 은 아잉으로 선다(그리는 쪽). */
    val characterID: String? = null,
    /**
     * AI 구독 리밋(v0.3.45). null = 아직 못 받았다(옛 스냅숏 포함).
     *
     * INV-WidgetSnapshot-5dc1a78a 이식: **`Me` 안이 아니라 최상위**에 둔다 — 지금 탭은 `snapshot.me == widgetNoTeamMe`(모든 칸이 0 인
     *   `Me`)로 '소속 없음'을 판정한다([NowWidgetSnapshotSink.noTeamMe]). `Me` 에 칸이 하나 늘면 그 센티넬 비교가 리밋 값에 흔들려, 소속 없는
     *   사용자에게 "팀에 참여하면 보여요"가 새거나 반대로 안 나온다. 리밋은 팀과 아무 상관이 없으므로 **다른 칸**이다(시험이 둘을 함께 잰다).
     */
    val aiLimits: MeAILimitWidgetPanel? = null,
) {
    /** 내 근무 상태(위젯 초상 표정·링). 옛 스냅숏은 [Me.working] 깃발만 있다 — 그때는 근무 중/안 함 둘로 읽는다. */
    enum class WorkState(val rawValue: String) {
        /** 근무 중(신호 신선). */
        working("working"),

        /** 근무 중인데 신호가 끊겼다(90초 넘게). */
        disconnected("disconnected"),

        /** 근무 안 함. */
        off("off");

        companion object {
            fun of(raw: String): WorkState? = entries.firstOrNull { it.rawValue == raw }
        }
    }

    data class Me(
        /** 근무 중인가(서버 세션 기준). */
        val working: Boolean,
        /** 근무 중이면 서버 세션 시작 시각 — 위젯이 스스로 센다. */
        val sessionStartedAt: SwiftDate?,
        /** 스냅숏 시각 기준 오늘 누적 초(진행 중 세션 포함). */
        val todaySeconds: Int,
        /** 스냅숏 시각 기준 이번 주 누적 초. */
        val weekSeconds: Int,
        /** 팀 1인당 주간 목표(시간). 0 = 소속 없음 표시(서버 목표는 1~168). */
        val goalHours: Int,
        /** 근무 상태 3갈래. null = 옛 스냅숏 · 이 빌드가 모르는 값 — 읽을 때는 [resolvedStatus]. */
        val status: WorkState? = null,
    ) {
        /** 상태 칸이 있으면 그 값, 없으면 [working] 깃발로. 상태가 깃발과 어긋나면 깃발을 믿는다(근무 안 함인데 "연결 끊김"을 그리지 않는다). */
        val resolvedStatus: WorkState
            get() {
                if (!working) return WorkState.off
                return if (status == WorkState.disconnected) WorkState.disconnected else WorkState.working
            }
    }

    data class WorkingPerson(
        val name: String,
        /** 센터 서버값. 모르면 null. */
        val center: String?,
        /** 우리 팀인가. 다른 팀 사람은 경과 시간을 모른다(startedAt null). */
        val teammate: Boolean,
        val startedAt: SwiftDate?,
        /** 얼굴에 그릴 착용 캐릭터 id. null = 모른다 → 이니셜. */
        val characterID: String? = null,
    ) {
        /** Swift `id`(목록 식별 — 직렬화하지 않는다). */
        val id: String
            get() = "${if (teammate) "t" else "o"}:$name:${WidgetSnapshotCodec.millisText(startedAt?.timeIntervalSince1970 ?: 0.0)}"
    }

    data class TodoPreview(
        /** 할 일 id(UUID 소문자). 위젯 체크가 이 id 로 할 일 파일을 고친다. */
        val id: String,
        val title: String,
        val isCompleted: Boolean,
        /** 이월 일수(0 = 오늘 만든 것). */
        val carryOverDays: Int = 0,
    )

    companion object {
        /** 이 코드가 쓰는 판. 읽을 때는 1 이상이면 받는다. */
        const val CURRENT_VERSION: Int = 1
    }
}

/**
 * 위젯 리밋 칸의 **읽는 쪽 접기**(Swift `CheckWidgetsKit` 이 `provider` 문자열을 열거값으로 접는 자리).
 *
 * INV-WidgetSnapshot-c1b06494 이식(소비 쪽): provider 는 문자열로 싣고 **모르는 값은 버린다** — 지어내 claude 로 접으면 남의 사용률이 내
 *   Claude 줄에 그려진다(열거값 확장 함정). 생산 쪽(나 탭)은 이미 거른 줄만 싣지만, 다음 판 앱이 쓴 파일을 이 판 위젯이 읽는 창이 있다.
 */
fun MeAILimitWidgetPanel.knownProviderRows(): List<Pair<AILimitProvider, MeAILimitWidgetRow>> =
    providers.mapNotNull { row -> AILimitProvider.of(row.provider)?.let { it to row } }

/**
 * 스냅숏 파일 읽고 쓰기(순수 직렬화). 날짜는 **epoch ms**(Swift `.millisecondsSince1970`) — 기기 로캘과 무관하고 왕복이 정확하다.
 * 쓰기는 키를 정렬하고(Swift `.sortedKeys`) null 칸을 뺀다(Swift 합성 Encodable 의 `encodeIfPresent`).
 */
object WidgetSnapshotCodec {
    fun encode(snapshot: WidgetSnapshot): ByteArray = encodeToJson(snapshot).toString().encodeToByteArray()

    /** 못 읽으면 null(= 위젯은 로그아웃 화면). version 이 1 미만이거나 없으면 null. */
    fun decode(bytes: ByteArray): WidgetSnapshot? {
        val snapshot = swiftTry { SwiftJson.decode(SnapshotSerializer, bytes.decodeToString()) } ?: return null
        return if (snapshot.version >= 1) snapshot else null
    }

    fun encodeToJson(snapshot: WidgetSnapshot): JsonObject = sorted(
        "version" to JsonPrimitive(snapshot.version),
        "generatedAt" to millis(snapshot.generatedAt),
        "me" to snapshot.me?.let(::meJson),
        "working" to JsonArray(snapshot.working.map(::personJson)),
        "todosPreview" to JsonArray(snapshot.todosPreview.map(::todoJson)),
        "characterID" to snapshot.characterID?.let(::JsonPrimitive),
        "aiLimits" to snapshot.aiLimits?.let(::panelJson),
    )

    private fun meJson(me: WidgetSnapshot.Me): JsonObject = sorted(
        "working" to JsonPrimitive(me.working),
        "sessionStartedAt" to me.sessionStartedAt?.let(::millis),
        "todaySeconds" to JsonPrimitive(me.todaySeconds),
        "weekSeconds" to JsonPrimitive(me.weekSeconds),
        "goalHours" to JsonPrimitive(me.goalHours),
        "status" to me.status?.let { JsonPrimitive(it.rawValue) },
    )

    private fun personJson(p: WidgetSnapshot.WorkingPerson): JsonObject = sorted(
        "name" to JsonPrimitive(p.name),
        "center" to p.center?.let(::JsonPrimitive),
        "teammate" to JsonPrimitive(p.teammate),
        "startedAt" to p.startedAt?.let(::millis),
        "characterID" to p.characterID?.let(::JsonPrimitive),
    )

    private fun todoJson(t: WidgetSnapshot.TodoPreview): JsonObject = sorted(
        "id" to JsonPrimitive(t.id),
        "title" to JsonPrimitive(t.title),
        "isCompleted" to JsonPrimitive(t.isCompleted),
        "carryOverDays" to JsonPrimitive(t.carryOverDays),
    )

    private fun panelJson(panel: MeAILimitWidgetPanel): JsonObject = sorted(
        "providers" to JsonArray(panel.providers.map(::rowJson)),
        "deviceName" to panel.deviceName?.let(::JsonPrimitive),
        "deviceNameTail" to panel.deviceNameTail?.let(::JsonPrimitive),
        "todayTokens" to panel.todayTokens?.let(::JsonPrimitive),
        "recentTokens" to panel.recentTokens?.let(::JsonPrimitive),
    )

    private fun rowJson(row: MeAILimitWidgetRow): JsonObject = sorted(
        "provider" to JsonPrimitive(row.provider),
        "fiveHourPercent" to row.fiveHourPercent?.let(::JsonPrimitive),
        "fiveHourResetsAt" to row.fiveHourResetsAt?.let(::millis),
        "weeklyPercent" to row.weeklyPercent?.let(::JsonPrimitive),
        "weeklyResetsAt" to row.weeklyResetsAt?.let(::millis),
        "observedAt" to millis(row.observedAt),
    )

    /** null 칸을 빼고 키를 정렬한 객체(Swift `.sortedKeys` — 키가 전부 ASCII 라 코드 단위 순서와 같다). */
    private fun sorted(vararg pairs: Pair<String, JsonElement?>): JsonObject =
        JsonObject(pairs.filter { it.second != null }.sortedBy { it.first }.associate { it.first to it.second!! })

    /** epoch ms. 정수 ms 면 정수 글자로(Swift JSONEncoder 가 소수부 없는 Double 을 정수 꼴로 쓰는 것과 같다). */
    private fun millis(date: SwiftDate): JsonPrimitive {
        val ms = date.timeIntervalSince1970 * 1000.0
        val whole = ms.toLong()
        return if (whole.toDouble() == ms) JsonPrimitive(whole) else JsonPrimitive(ms)
    }

    internal fun millisText(seconds: Double): String {
        val ms = seconds * 1000.0
        val whole = ms.toLong()
        return if (whole.toDouble() == ms) whole.toString() else ms.toString()
    }

    /** Swift `.millisecondsSince1970` 디코드: 수(Double) ÷ 1000. 수가 아니면 typeMismatch(던진다). */
    private fun dateOf(decoder: SwiftValueDecoder): SwiftDate = SwiftDate(decoder.decodeDouble() / 1000.0)

    private fun SwiftKeyed.date(key: String): SwiftDate = dateOf(decoder(key))

    /** `try? c.decodeIfPresent(Date.self, forKey:)`. */
    private fun SwiftKeyed.lossyDate(key: String): SwiftDate? = swiftTry {
        val raw = raw(key)
        if (raw == null || raw is JsonNull) null else dateOf(decoder(key))
    }

    /** 앞뒤 공백·줄바꿈을 걷고 비면 null(Swift `trimmingCharacters(in: .whitespacesAndNewlines)` + 빈 글자 → nil). */
    private fun trimmedOrNull(value: String?): String? =
        value?.let { TextScalars.trimmingWhitespacesAndNewlines(it) }?.takeIf { it.isNotEmpty() }

    private object SnapshotSerializer : SwiftDecodableSerializer<WidgetSnapshot>("WidgetSnapshot") {
        override fun deserialize(decoder: Decoder): WidgetSnapshot {
            val c = SwiftDecoding.keyedPlain(decoder)
            return WidgetSnapshot(
                version = c.int("version"),
                generatedAt = c.date("generatedAt"),
                me = c.lossy("me", MeSerializer),
                // 칸 하나가 깨져도 스냅숏 전체를 버리지 않는다 — 원소 단위로 건너뛴다(위젯이 통째로 비는 것보다 낫다).
                working = swiftTry { c.decoderIfPresent("working")?.lossyList(PersonSerializer) } ?: emptyList(),
                todosPreview = swiftTry { c.decoderIfPresent("todosPreview")?.lossyList(TodoSerializer) } ?: emptyList(),
                characterID = c.lossyString("characterID"),
                // INV-WidgetSnapshot-f5226477 이식: 이 줄을 빼먹으면 **컴파일은 통과하고** 파일에 값이 있어도 영원히 null 이다(값 왕복 시험만으론
                //   초록인 채 위젯에 아무것도 안 뜬다). 생 JSON 호환 시험(WidgetSnapshotCodecTest)이 이 줄을 지킨다.
                aiLimits = c.lossy("aiLimits", PanelSerializer),
            )
        }
    }

    private object MeSerializer : SwiftDecodableSerializer<WidgetSnapshot.Me>("WidgetSnapshot.Me") {
        override fun deserialize(decoder: Decoder): WidgetSnapshot.Me {
            val c = SwiftDecoding.keyedPlain(decoder)
            return WidgetSnapshot.Me(
                working = c.lossyBool("working") ?: false,
                sessionStartedAt = c.lossyDate("sessionStartedAt"),
                todaySeconds = maxOf(0, c.lossyInt("todaySeconds") ?: 0),
                weekSeconds = maxOf(0, c.lossyInt("weekSeconds") ?: 0),
                goalHours = c.lossyInt("goalHours") ?: 0,
                // 모르는 문자열(다음 판이 더한 상태)은 null — 깃발로 읽는다.
                status = c.lossyString("status")?.let(WidgetSnapshot.WorkState::of),
            )
        }
    }

    private object PersonSerializer : SwiftDecodableSerializer<WidgetSnapshot.WorkingPerson>("WidgetSnapshot.WorkingPerson") {
        override fun deserialize(decoder: Decoder): WidgetSnapshot.WorkingPerson {
            val c = SwiftDecoding.keyedPlain(decoder)
            return WidgetSnapshot.WorkingPerson(
                name = c.lossyString("name") ?: "사용자",
                center = c.lossyString("center"),
                teammate = c.lossyBool("teammate") ?: false,
                startedAt = c.lossyDate("startedAt"),
                // 칸이 없거나(옛 앱이 쓴 스냅숏) 타입이 어긋나면 null — 이니셜로 선다(더하기만 하는 규칙).
                characterID = c.lossyString("characterID"),
            )
        }
    }

    private object TodoSerializer : SwiftDecodableSerializer<WidgetSnapshot.TodoPreview>("WidgetSnapshot.TodoPreview") {
        override fun deserialize(decoder: Decoder): WidgetSnapshot.TodoPreview {
            val c = SwiftDecoding.keyedPlain(decoder)
            return WidgetSnapshot.TodoPreview(
                id = c.string("id"),
                title = c.lossyString("title") ?: "",
                isCompleted = c.lossyBool("isCompleted") ?: false,
                carryOverDays = maxOf(0, c.lossyInt("carryOverDays") ?: 0),
            )
        }
    }

    private object RowSerializer : SwiftDecodableSerializer<MeAILimitWidgetRow>("WidgetSnapshot.AILimitRow") {
        override fun deserialize(decoder: Decoder): MeAILimitWidgetRow {
            val c = SwiftDecoding.keyedPlain(decoder)
            return MeAILimitWidgetRow(
                provider = c.string("provider"),
                observedAt = c.date("observedAt"),
                fiveHourPercent = c.lossyDouble("fiveHourPercent"),
                fiveHourResetsAt = c.lossyDate("fiveHourResetsAt"),
                weeklyPercent = c.lossyDouble("weeklyPercent"),
                weeklyResetsAt = c.lossyDate("weeklyResetsAt"),
            )
        }
    }

    private object PanelSerializer : SwiftDecodableSerializer<MeAILimitWidgetPanel>("WidgetSnapshot.AILimitPanel") {
        override fun deserialize(decoder: Decoder): MeAILimitWidgetPanel {
            val c = SwiftDecoding.keyedPlain(decoder)
            return MeAILimitWidgetPanel(
                // 칸 하나가 깨져도 나머지 제공자를 살린다(위젯이 통째로 비는 것보다 낫다 — `working` 과 같은 규약).
                providers = swiftTry { c.decoderIfPresent("providers")?.lossyList(RowSerializer) } ?: emptyList(),
                // INV-WidgetSnapshot-0f12bb0d 이식: 이 줄을 빼먹으면 **컴파일은 통과하고** 파일에 이름이 있어도 영원히 null 이다(값 왕복 시험만으론
                //   초록인 채 위젯 머리에 맥 이름이 안 뜬다 — `aiLimits` 칸이 밟은 그 함정). 생 JSON 시험이 지킨다.
                // INV-WidgetSnapshot-9401d735 이식(소비 쪽): 이름은 폰이 정한 글자를 **그대로** 읽는다 — 공백만 걷고 꼬리·괄호를 다시 가르지 않는다.
                // INV-WidgetSnapshot-281daaa3 이식(소비 쪽): 이 칸은 합친 한 글자(`Mac mini (A1B2)`) 그대로다 — 꼬리는 아래 칸에서 따로 읽는다.
                deviceName = trimmedOrNull(c.lossyString("deviceName")),
                // INV-WidgetSnapshot-99e06a6c 이식: 같은 함정이 이 칸에도 있다 — 줄을 빼먹으면 컴파일은 통과하고 꼬리는 영원히 null 이라, 위젯 머리는
                //   소리 없이 합친 글자 한 줄로 돌아가 상한 길이 쌍둥이를 다시 못 가른다(생 JSON 시험이 지킨다).
                deviceNameTail = trimmedOrNull(c.lossyString("deviceNameTail")),
                todayTokens = c.lossyLong("todayTokens")?.let { maxOf(0, it) },
                recentTokens = c.lossyLong("recentTokens")?.let { maxOf(0, it) },
            )
        }
    }

    /** `try? c.decodeIfPresent(LossyArray<…>.self, forKey:)` 의 바깥 몫 — 없음·null 은 null, 배열이 아니면 던진다(호출부 `try?` 가 빈 목록으로). */
    private fun SwiftKeyed.decoderIfPresent(key: String): SwiftValueDecoder? {
        val raw = raw(key) ?: return null
        if (raw is JsonNull) return null
        return decoder(key)
    }
}
