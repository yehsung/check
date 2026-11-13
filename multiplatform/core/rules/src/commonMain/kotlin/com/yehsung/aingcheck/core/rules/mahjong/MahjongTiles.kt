// 원본: Sources/CheckCore/MahjongTiles.swift @ e4995a3a(아잉 마작 — 패 · 표기 · 도라 · 부로) — Android 판 8
//
// 4인 리치 마작 규칙의 바탕. 직접 작성, 외부 판정 코드 없음 — 정본 rules.md MJ-01~MJ-56, 대조 reference.py · cases.json.
// 서버(plpgsql `mahjong_*`) · 맥/폰(Swift) · 이 파일들이 같은 판정을 따로 한다(이름 대응은 SPEC §2.1 표).
// 표기(MJ-03): 패 한 장 = 물리 패 번호 id 0~135(id = kind*4 + c). 적5 = c 0 인 5만·5통·5삭 = id 16·52·88. 종류 kind = id / 4.
// **id 와 종류를 섞지 않는다**: 손패·강·부로는 id([MahjongTile]), 대기·후리텐·쿠이카에·도라는 종류(Int).
package com.yehsung.aingcheck.core.rules.mahjong

/** 패 한 장 — 물리 패 번호(0~135). */
class MahjongTile private constructor(val id: Int) : Comparable<MahjongTile> {
    companion object {
        /** 범위 밖(−1 · 136…)은 null. */
        fun of(id: Int): MahjongTile? = if (id in 0..135) MahjongTile(id) else null
        fun of(id: Long): MahjongTile? = if (id in 0L..135L) MahjongTile(id.toInt()) else null
    }

    /** 종류 0~33 = id / 4. */
    val kind: Int get() = id / 4
    /** 적5 — id ∈ {16, 52, 88}(MJ-02). */
    val isRed: Boolean get() = id == 16 || id == 52 || id == 88
    val suit: MahjongSuit get() = MahjongSuit.of(kind)
    /** 수패 숫자 1~9. 자패는 null. */
    val number: Int? get() = if (kind < 27) kind % 9 + 1 else null
    /** "5m" · "0m"(적5) · "7z" — 진단 · 시험용. */
    val token: String get() = if (isRed) "0" + MahjongTiles.suitLetter(kind) else MahjongTiles.token(kind)

    override fun compareTo(other: MahjongTile): Int = id.compareTo(other.id)
    override fun equals(other: Any?): Boolean = other is MahjongTile && other.id == id
    override fun hashCode(): Int = id
    override fun toString(): String = "MahjongTile($id=$token)"
}

/** 색. 만 · 통 · 삭 · 자패. */
enum class MahjongSuit {
    man, pin, sou, honor;

    companion object {
        /** 종류 → 색. 0~8 만 · 9~17 통 · 18~26 삭 · 27~33 자패. */
        fun of(kind: Int): MahjongSuit = if (kind < 27) entries.getOrNull(kind / 9) ?: honor else honor
    }
}

/** 바람. 와이어 · 코퍼스 값 'E' · 'S' · 'W' · 'N'(= 1z~4z). */
enum class MahjongWind(val rawValue: String) {
    east("E"), south("S"), west("W"), north("N");

    companion object {
        fun of(raw: String): MahjongWind? = entries.firstOrNull { it.rawValue == raw }
    }
}

/** 패 문자열 · 장수 · 도라(reference parse · physical_ids · counts34 · dora_of_indicator · tiles_str). */
object MahjongTiles {
    /**
     * MJ-03 문자열 → 패. 같은 종류는 c 가 작은 것부터, 적5('0') 는 c 0, 보통 5 는 c 1~3. 모르는 글자 · 숫자 없는 색 글자 · '0z' · '8z' · '9z' ·
     * 같은 패 다섯 장(보통 5 는 넷)은 null. 빈 문자열은 빈 목록. 공백은 건너뛴다.
     */
    fun parse(text: String): List<MahjongTile>? {
        val digits = mutableListOf<Int>()
        val taken = mutableSetOf<Int>()
        val out = mutableListOf<MahjongTile>()
        for (ch in text) {
            if (ch == ' ') continue
            if (ch in '0'..'9') {
                digits += ch - '0'
                continue
            }
            val offset = suitOffset(ch) ?: return null
            if (digits.isEmpty()) return null
            for (d in digits) {
                val red = d == 0
                if (ch == 'z' && d !in 1..7) return null
                val k = offset + (if (red) 5 else d) - 1
                val candidates = when {
                    red -> listOf(k * 4)
                    k == 4 || k == 13 || k == 22 -> listOf(k * 4 + 1, k * 4 + 2, k * 4 + 3)
                    else -> listOf(k * 4, k * 4 + 1, k * 4 + 2, k * 4 + 3)
                }
                val id = candidates.firstOrNull { it !in taken } ?: return null
                val tile = MahjongTile.of(id) ?: return null
                taken += id
                out += tile
            }
            digits.clear()
        }
        return if (digits.isEmpty()) out else null
    }

    /** 종류 34칸 장수(적5 는 5 로 센다). */
    fun counts34(tiles: List<MahjongTile>): IntArray {
        val counts = IntArray(34)
        for (t in tiles) counts[t.kind] += 1
        return counts
    }

    /** MJ-10 표시패 종류의 다음 종류. 수패 9→1, 동→남→서→북→동, 백→발→중→백. 범위 밖은 그대로. */
    fun doraKind(ofIndicator: Int): Int {
        val kind = ofIndicator
        if (kind !in 0..33) return kind
        if (kind < 27) return if (kind % 9 == 8) kind - 8 else kind + 1
        if (kind <= 30) return if (kind == 30) 27 else kind + 1
        return if (kind == 33) 31 else kind + 1
    }

    /** 종류 목록 → 정렬한 "123m45p" 꼴(적5 정보 없음, 진단). 범위 밖 종류는 건너뛴다. */
    fun text(kinds: List<Int>): String {
        val groups = linkedMapOf<Char, MutableList<Int>>()
        for (k in kinds.sorted()) if (k in 0..33) groups.getOrPut(suitLetter(k)) { mutableListOf() } += k
        val out = StringBuilder()
        for (letter in listOf('m', 'p', 's', 'z')) {
            val ks = groups[letter] ?: continue
            if (ks.isEmpty()) continue
            for (k in ks) out.append(digit(k))
            out.append(letter)
        }
        return out.toString()
    }

    internal fun suitOffset(ch: Char): Int? = when (ch) {
        'm' -> 0
        'p' -> 9
        's' -> 18
        'z' -> 27
        else -> null
    }

    internal fun suitLetter(kind: Int): Char = if (kind >= 27) 'z' else listOf('m', 'p', 's')[kind / 9]
    internal fun digit(kind: Int): Int = if (kind >= 27) kind - 26 else kind % 9 + 1

    /** 종류 → 보통 패 토큰("5m" · "7z"). */
    internal fun token(kind: Int): String = "${digit(kind)}${suitLetter(kind)}"

    /** 요구패(1·9·자패) 종류. */
    val yaochu: List<Int> = listOf(0, 8, 9, 17, 18, 26, 27, 28, 29, 30, 31, 32, 33)

    /** 바람패 종류(동남서북). */
    val winds: List<Int> = listOf(27, 28, 29, 30)
}

/** 부로 종류. 와이어 MELD.type 값 그대로. */
enum class MahjongMeldType(val rawValue: String) {
    chi("chi"), pon("pon"), minkan("minkan"), kakan("kakan"), ankan("ankan");

    companion object {
        fun of(raw: String): MahjongMeldType? = entries.firstOrNull { it.rawValue == raw }
    }
}

/** 부로 한 묶음 = 와이어 MELD {type, tiles, called, from_seat}. */
data class MahjongMeld(
    val type: MahjongMeldType,
    /** 묶음의 패 id(깡은 4장). */
    val tiles: List<MahjongTile>,
    /** 남에게서 가져온 패. 암깡은 null. */
    val called: MahjongTile?,
    /** 가져온 자리(0~3). 암깡은 null. */
    val fromSeat: Int?,
)
