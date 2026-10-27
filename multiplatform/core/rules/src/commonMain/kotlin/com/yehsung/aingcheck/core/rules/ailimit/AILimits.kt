// 원본: Sources/CheckCore/AILimits.swift @ 1b8260d (리밋 축 값 타입 — 네트워크 · UI · 파일 I/O 없음)
package com.yehsung.aingcheck.core.rules.ailimit

import com.yehsung.aingcheck.core.rules.text.Graphemes
import com.yehsung.aingcheck.core.rules.text.TextScalars
import com.yehsung.aingcheck.core.rules.text.codePointCountCompat

// AI 사용량 리밋(v0.3.45). **토큰 축과 섞지 않는다**(출처 · 단위 · 수명 · 공개 범위가 다르다) — 리밋 축 코드는 토큰 축 파일을 읽지도 쓰지도 않는다.
// 단위는 "쓴 비율 0…100" 하나(안티그래비티의 남은 비율은 AILimitWindowSnapshot.fromRemainingFraction 한 곳에서만 뒤집는다).
// 시각은 전부 절대 시각(1970 기준 초 Double) — '남은 초'를 들고 다니지 않는다(위젯이 몇 시간 뒤에 그린다).

/** 리밋을 읽는 제공자. rawValue = 서버 컬럼 값. 모르는 값은 null — 접는 default 를 두지 않는다(그 행은 버린다). */
enum class AILimitProvider(val rawValue: String) {
    claude("claude"),
    codex("codex"),
    antigravity("antigravity"),
    ;

    /** 토큰 툴팁과 같은 어휘. */
    val displayName: String
        get() = when (this) {
            claude -> "Claude"
            codex -> "Codex"
            antigravity -> "안티그래비티"
        }

    /** 좁은 자리용 — 색 대신 쓰는 식별자. */
    val compactName: String
        get() = when (this) {
            claude -> "Claude"
            codex -> "Codex"
            antigravity -> "AG"
        }

    val sortOrder: Int get() = ordinal

    companion object {
        fun of(raw: String): AILimitProvider? = entries.firstOrNull { it.rawValue == raw }
    }
}

/** 사용률이 리셋되는 창. rawValue = 서버 컬럼 값. */
enum class AILimitWindow(val rawValue: String) {
    fiveHour("five_hour"),
    weekly("weekly"),
    ;

    val lengthSeconds: Double
        get() = when (this) {
            fiveHour -> 18_000.0
            weekly -> 604_800.0
        }

    val displayName: String
        get() = when (this) {
            fiveHour -> "5시간"
            weekly -> "주간"
        }

    val sortOrder: Int get() = ordinal

    companion object {
        fun of(raw: String): AILimitWindow? = entries.firstOrNull { it.rawValue == raw }

        /**
         * 서버가 말한 **창 길이로** 창을 가린다 — 이름보다 먼저다.
         * INV-AILimits-fac7cbe9 이식: Codex 는 플랜에 따라 **주간 창 하나만** `primary_window` 이름으로 보낸다(2026-10-23 실측 —
         * 이름만 믿으면 그 주간 값이 5시간 칸에 앉는다). 두 창 어느 쪽과도 비가 2 안이 아니면 null(가까운 쪽에 억지로 끼우지 않는다).
         */
        fun matching(lengthSeconds: Double?): AILimitWindow? {
            if (lengthSeconds == null || !(lengthSeconds > 0)) return null
            return entries
                .map { it to maxOf(lengthSeconds, it.lengthSeconds) / minOf(lengthSeconds, it.lengthSeconds) }
                .filter { it.second <= 2 }
                .minByOrNull { it.second }
                ?.first
        }

        /** 제공자 창 이름 → 열거값. 모르는 값(같은 길이의 셋째 창 포함)은 null — 지어내지 않는다. */
        fun ofProviderWindowName(raw: String): AILimitWindow? = when (raw) {
            "five_hour", "fiveHour", "5h", "primary", "primary_window" -> fiveHour
            "weekly", "seven_day", "sevenDay", "7d", "secondary", "secondary_window" -> weekly
            else -> null
        }
    }
}

/**
 * 이 값이 이 기기에 어떻게 닿았는가.
 * INV-AILimits-96ce8059 이식: **화면 문구에 쓰지 않는다**(진단 어휘다 — 캡션은 나이만 말한다).
 */
enum class AILimitSource(val rawValue: String) {
    local("local"),
    server("server"),
}

/** 창 하나의 관측값(서버 행과 1:1). usedPercent 는 클램프하지 않는다(진단이 되게) — 화면 클램프는 FreshnessRule 한 곳. */
data class AILimitWindowSnapshot(
    val window: AILimitWindow,
    val usedPercent: Double,
    val resetsAt: Double?,
    val observedAt: Double,
    val source: AILimitSource,
) {
    companion object {
        /** **남은 비율(0…1)을 주는 제공자(안티그래비티) 전용 입구** — 호출부에 `1 -` 가 보이면 그게 결함이다. */
        fun fromRemainingFraction(window: AILimitWindow, remainingFraction: Double, resetsAt: Double?, observedAt: Double, source: AILimitSource) =
            AILimitWindowSnapshot(window, AILimitScale.usedPercent(remainingFraction), resetsAt, observedAt, source)

        /** **상대 초**로 리셋을 주는 제공자의 입구 — 받는 자리에서 절대 시각으로 굳힌다. 0 이하는 null. */
        fun fromResetsAfterSeconds(window: AILimitWindow, usedPercent: Double, resetsAfterSeconds: Double?, observedAt: Double, source: AILimitSource) =
            AILimitWindowSnapshot(window, usedPercent,
                resetsAfterSeconds?.takeIf { it > 0 }?.let { observedAt + it }, observedAt, source)

        /** 창마다 **가장 많이 쓴 것 하나**(동률이면 리셋이 빠른 쪽, 리셋 있음이 없음을 이긴다). 5시간 → 주간 순. */
        fun worstPerWindow(candidates: List<AILimitWindowSnapshot>): List<AILimitWindowSnapshot> {
            val best = LinkedHashMap<AILimitWindow, AILimitWindowSnapshot>()
            for (candidate in candidates) {
                val held = best[candidate.window]
                if (held == null) {
                    best[candidate.window] = candidate
                    continue
                }
                if (candidate.usedPercent > held.usedPercent) {
                    best[candidate.window] = candidate
                } else if (candidate.usedPercent == held.usedPercent) {
                    val mine = candidate.resetsAt
                    val theirs = held.resetsAt
                    if (mine != null && theirs != null && mine < theirs) best[candidate.window] = candidate
                    else if (mine != null && theirs == null) best[candidate.window] = candidate
                }
            }
            return best.values.sortedBy { it.window.sortOrder }
        }
    }
}

/** 제공자 하나의 관측 묶음. 창이 비면 '미연동'(목록에서 숨는다 — 0% 로 지어내지 않는다). */
data class AILimitProviderSnapshot(
    val provider: AILimitProvider,
    val windows: List<AILimitWindowSnapshot>,
    val planLabel: String? = null,
    /**
     * 계정 해시.
     * INV-AILimits-cebdf591 이식: **서버로 가지 않는다** — 쓰임은 업로드 게이트의 로컬 비교 하나(맥 · Windows 업로더 W2-h).
     */
    val accountFingerprint: String? = null,
) {
    fun window(window: AILimitWindow): AILimitWindowSnapshot? = windows.firstOrNull { it.window == window }

    val orderedWindows: List<AILimitWindowSnapshot> get() = windows.sortedBy { it.window.sortOrder }

    /** 창들이 한 경로로 왔으면 그 경로, 섞였거나 비면 null(파생값 — 따로 들지 않는다). */
    val source: AILimitSource?
        get() {
            val first = windows.firstOrNull() ?: return null
            return if (windows.all { it.source == first.source }) first.source else null
        }

    val latestObservedAt: Double? get() = windows.maxOfOrNull { it.observedAt }

    val isLinked: Boolean get() = windows.isNotEmpty()
}

/** 디스크 · 위젯 · 서버 응답의 봉투(위젯은 앱과 따로 갱신된다 — 판을 둔다). */
data class AILimitSnapshotBundle(val schemaVersion: Int = currentSchemaVersion, val providers: List<AILimitProviderSnapshot>) {
    val visibleProviders: List<AILimitProviderSnapshot> get() = providers.filter { it.isLinked }.sortedBy { it.provider.sortOrder }

    fun provider(provider: AILimitProvider): AILimitProviderSnapshot? = providers.firstOrNull { it.provider == provider }

    companion object {
        const val currentSchemaVersion = 1
    }
}

/** 제공자 숫자를 쓴 비율 0…100 으로 맞춘다. */
object AILimitScale {
    /** 남은 비율(0…1) → 쓴 비율(0…100). 범위 밖은 클램프, 무한 · NaN 은 0. */
    fun usedPercent(remainingFraction: Double): Double {
        if (!remainingFraction.isFinite()) return 0.0
        val remaining = minOf(maxOf(remainingFraction, 0.0), 1.0)
        return (1 - remaining) * 100
    }
}

/**
 * 계정 원문 → 되돌릴 수 없는 짧은 지문(SHA-256 앞 16 hex).
 * INV-AILimits-3eb27a9b 이식: 이 값은 **서버로 가지 않는다**(업로드 게이트 로컬 비교 하나).
 * INV-AILimits-d493b2f6 이식: **SHA-256 이어야 한다** — '원문 hex'로 바꿔도 모양 시험은 통과하지만 식별자 앞 8바이트를 흘린다(시험은 알려진 입력의 값으로 잰다).
 */
object AILimitFingerprint {
    const val hexLength = 16

    fun make(raw: String?): String? {
        if (raw == null) return null
        val trimmed = TextScalars.trimmingWhitespacesAndNewlines(raw)
        if (trimmed.isEmpty()) return null
        return Sha256.hex(trimmed.encodeToByteArray()).take(hexLength)
    }
}

/**
 * 기기 이름(`ai_limits.device_label`)의 규칙 — 자르되 빈 값만 버린다.
 * INV-AILimits-e57fe0e1 이식: 자르는 눈금은 **유니코드 스칼라**(서버 CHECK char_length 1…64) — 자소는 쪼개지 않는다(한 자소를 더해 넘치면 그 자소를 넣지 않고 멈춘다).
 */
object AILimitDeviceLabelContract {
    const val maxScalars = 64

    fun normalized(raw: String?): String? {
        if (raw == null) return null
        val trimmed = TextScalars.trimmingWhitespacesAndNewlines(raw)
        if (trimmed.isEmpty()) return null
        val out = StringBuilder()
        var scalars = 0
        for (cluster in Graphemes.clusters(trimmed)) {
            val next = scalars + cluster.codePointCountCompat()
            if (next > maxScalars) break
            out.append(cluster)
            scalars = next
        }
        return out.toString().ifEmpty { null }
    }
}

/** 서버 행에서 읽은 관측 하나(제공자별로 흩어져 있다). */
data class AILimitDeviceObservation(val deviceID: String, val label: String?, val observedAt: Double?)

/** 내 맥(Windows PC) 한 대. */
data class AILimitDevice(val deviceID: String, val label: String?, val lastObservedAt: Double?) {
    val id: String get() = deviceID

    /** 이름이 겹치지 않는다고 가정했을 때의 이름. */
    val baseName: String get() = if (!label.isNullOrEmpty()) label else "$unnamedPrefix ${shortTail(deviceID)}"

    companion object {
        const val unnamedPrefix = "이름 모를 맥"

        /** 식별자 꼬리(대문자 4자) — 두 줄을 가르는 데만. */
        fun shortTail(deviceID: String): String = deviceID.uppercase().takeLast(4)
    }
}

/**
 * 화면에 적을 기기 이름의 두 조각.
 * INV-AILimits-c504dbdc 이식: 합친 글자 하나로 내놓지 않는다 — 말줄임이 꼬리 `(A1B2)` 를 먹으면 두 쌍둥이 머리글이 글자 그대로 같아진다.
 */
data class AILimitDeviceNameParts(val base: String, val tail: String?) {
    /** 잘릴 자리가 없는 곳에서만(보이스오버 · 위젯 패널). */
    val combined: String get() = if (tail == null) base else "$base ${tailText(tail)}"

    companion object {
        fun tailText(tail: String): String = "($tail)"
    }
}

object AILimitDeviceRoster {
    /** 행 → 기기. 최근 순(관측 없음은 뒤 · 동률은 id). 이름은 라벨 있는 가장 최근 행(이름 모르는 옛 행이 이름을 지우지 않게). */
    fun fold(observations: List<AILimitDeviceObservation>): List<AILimitDevice> {
        data class Held(var label: String?, var labelAt: Double?, var lastAt: Double?)
        val byDevice = LinkedHashMap<String, Held>()
        for (row in observations) {
            val id = TextScalars.trimmingWhitespacesAndNewlines(row.deviceID)
            if (id.isEmpty()) continue
            val held = byDevice.getOrPut(id) { Held(null, null, null) }
            val observedAt = row.observedAt
            if (observedAt != null) held.lastAt = held.lastAt?.let { maxOf(it, observedAt) } ?: observedAt
            val label = AILimitDeviceLabelContract.normalized(row.label)
            if (label != null) {
                val heldAt = held.labelAt
                val isNewer = when {
                    heldAt == null -> true
                    observedAt == null -> false
                    else -> observedAt >= heldAt
                }
                if (isNewer) {
                    held.label = label
                    held.labelAt = observedAt ?: held.labelAt
                }
            }
        }
        return byDevice.map { (id, held) -> AILimitDevice(id, held.label, held.lastAt) }.sortedWith { lhs, rhs ->
            val mine = lhs.lastObservedAt
            val theirs = rhs.lastObservedAt
            when {
                mine != null && theirs != null && mine != theirs -> if (mine > theirs) -1 else 1
                mine != null && theirs == null -> -1
                mine == null && theirs != null -> 1
                else -> lhs.deviceID.compareTo(rhs.deviceID)
            }
        }
    }

    /**
     * 기기 id → 이름 조각. 같은 이름이 둘 이상이면 꼬리를 붙인다(겹치지 않으면 꼬리 없음).
     * INV-AILimits-f2bc3b27 이식: 조각으로 돌려준다 — 합친 글자가 필요한 곳은 [displayNames].
     */
    fun displayNameParts(devices: List<AILimitDevice>): Map<String, AILimitDeviceNameParts> {
        val counts = HashMap<String, Int>()
        for (device in devices) counts[device.baseName] = (counts[device.baseName] ?: 0) + 1
        val out = LinkedHashMap<String, AILimitDeviceNameParts>()
        for (device in devices) {
            val base = device.baseName
            out[device.deviceID] = AILimitDeviceNameParts(base, if ((counts[base] ?: 0) > 1) AILimitDevice.shortTail(device.deviceID) else null)
        }
        return out
    }

    fun displayNames(devices: List<AILimitDevice>): Map<String, String> = displayNameParts(devices).mapValues { it.value.combined }
}

/**
 * "폰·위젯에 보여 줄 맥"의 단 하나의 규칙 — 고른 값이 목록에 있으면 그것, 없으면 가장 최근에 일한 맥.
 * INV-AILimits-c12aae7c 이식: 이 규칙을 **두 표면이 같은 입력(명부 전체)으로** 돌린다 — 폰은 명부 전체로 한 번 더 돌려 자기가 그리는 맥과 견준다(W2-c).
 */
object AILimitMainDeviceRule {
    fun resolve(devices: List<AILimitDevice>, chosen: String?): AILimitDevice? {
        if (chosen != null) devices.firstOrNull { it.deviceID == chosen }?.let { return it }
        // 호출부의 배열 순서에 기대지 않고 다시 고른다(Swift `max(by:)` — 같은 "최대"가 여럿이면 뒤의 것).
        var best: AILimitDevice? = null
        for (device in devices) {
            val current = best
            if (current == null || isLess(current, device)) best = device   // 같으면 앞의 것을 둔다(Swift max(by:))
        }
        return best
    }

    /** Swift `max(by:)` 의 areInIncreasingOrder. */
    private fun isLess(lhs: AILimitDevice, rhs: AILimitDevice): Boolean {
        val mine = lhs.lastObservedAt
        val theirs = rhs.lastObservedAt
        return when {
            mine != null && theirs != null && mine != theirs -> mine < theirs
            mine == null && theirs != null -> true
            mine != null && theirs == null -> false
            else -> lhs.deviceID > rhs.deviceID
        }
    }
}

/** SHA-256(순수 Kotlin — 플랫폼 MessageDigest 없이 JVM · ART 같은 값). */
internal object Sha256 {
    private val K: IntArray = longArrayOf(
        0x428a2f98L, 0x71374491L, 0xb5c0fbcfL, 0xe9b5dba5L, 0x3956c25bL, 0x59f111f1L, 0x923f82a4L, 0xab1c5ed5L,
        0xd807aa98L, 0x12835b01L, 0x243185beL, 0x550c7dc3L, 0x72be5d74L, 0x80deb1feL, 0x9bdc06a7L, 0xc19bf174L,
        0xe49b69c1L, 0xefbe4786L, 0x0fc19dc6L, 0x240ca1ccL, 0x2de92c6fL, 0x4a7484aaL, 0x5cb0a9dcL, 0x76f988daL,
        0x983e5152L, 0xa831c66dL, 0xb00327c8L, 0xbf597fc7L, 0xc6e00bf3L, 0xd5a79147L, 0x06ca6351L, 0x14292967L,
        0x27b70a85L, 0x2e1b2138L, 0x4d2c6dfcL, 0x53380d13L, 0x650a7354L, 0x766a0abbL, 0x81c2c92eL, 0x92722c85L,
        0xa2bfe8a1L, 0xa81a664bL, 0xc24b8b70L, 0xc76c51a3L, 0xd192e819L, 0xd6990624L, 0xf40e3585L, 0x106aa070L,
        0x19a4c116L, 0x1e376c08L, 0x2748774cL, 0x34b0bcb5L, 0x391c0cb3L, 0x4ed8aa4aL, 0x5b9cca4fL, 0x682e6ff3L,
        0x748f82eeL, 0x78a5636fL, 0x84c87814L, 0x8cc70208L, 0x90befffaL, 0xa4506cebL, 0xbef9a3f7L, 0xc67178f2L,
    ).map { it.toInt() }.toIntArray()

    fun hex(input: ByteArray): String = digest(input).joinToString("") { (it.toInt() and 0xff).toString(16).padStart(2, '0') }

    fun digest(input: ByteArray): ByteArray {
        val h = longArrayOf(0x6a09e667L, 0xbb67ae85L, 0x3c6ef372L, 0xa54ff53aL, 0x510e527fL, 0x9b05688cL, 0x1f83d9abL, 0x5be0cd19L)
            .map { it.toInt() }.toIntArray()
        val bitLength = input.size.toLong() * 8
        val padded = ByteArray(((input.size + 9 + 63) / 64) * 64)
        input.copyInto(padded)
        padded[input.size] = 0x80.toByte()
        for (i in 0 until 8) padded[padded.size - 1 - i] = (bitLength ushr (8 * i)).toByte()
        val w = IntArray(64)
        for (block in padded.indices step 64) {
            for (t in 0 until 16) {
                val o = block + t * 4
                w[t] = ((padded[o].toInt() and 0xff) shl 24) or ((padded[o + 1].toInt() and 0xff) shl 16) or
                    ((padded[o + 2].toInt() and 0xff) shl 8) or (padded[o + 3].toInt() and 0xff)
            }
            for (t in 16 until 64) {
                val s0 = w[t - 15].rotateRight(7) xor w[t - 15].rotateRight(18) xor (w[t - 15] ushr 3)
                val s1 = w[t - 2].rotateRight(17) xor w[t - 2].rotateRight(19) xor (w[t - 2] ushr 10)
                w[t] = w[t - 16] + s0 + w[t - 7] + s1
            }
            var a = h[0]; var b = h[1]; var c = h[2]; var d = h[3]; var e = h[4]; var f = h[5]; var g = h[6]; var hh = h[7]
            for (t in 0 until 64) {
                val s1 = e.rotateRight(6) xor e.rotateRight(11) xor e.rotateRight(25)
                val ch = (e and f) xor (e.inv() and g)
                val temp1 = hh + s1 + ch + K[t] + w[t]
                val s0 = a.rotateRight(2) xor a.rotateRight(13) xor a.rotateRight(22)
                val maj = (a and b) xor (a and c) xor (b and c)
                val temp2 = s0 + maj
                hh = g; g = f; f = e; e = d + temp1; d = c; c = b; b = a; a = temp1 + temp2
            }
            h[0] += a; h[1] += b; h[2] += c; h[3] += d; h[4] += e; h[5] += f; h[6] += g; h[7] += hh
        }
        val out = ByteArray(32)
        for (i in 0 until 8) for (j in 0 until 4) out[i * 4 + j] = (h[i] ushr (24 - 8 * j)).toByte()
        return out
    }
}
