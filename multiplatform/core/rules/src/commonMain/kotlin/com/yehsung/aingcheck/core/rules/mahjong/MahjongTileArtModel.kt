// 원본: Sources/CheckCore/MahjongTileArtModel.swift @ e4995a3a(패 그림 순수 값 — 면 · 크기 · 상태 · 배치 · 팔레트 · 그림 선택지) — Android 판 8
//
// 화면은 이 값만 읽어 그린다. 전통 배치(통의 원 개수 · 자리, 萬 · 東 글자)는 보편 관례라 따르고, 선 · 색 · 1삭 · 뒷면은 우리가 정한다.
// 폰은 받은 팔레트(Storage)를 쓰지 않는다 — 코드 팔레트(대표가 고른 'A 지금 그대로')만. 그래서 Storage 받기 판정은 옮기지 않았다.
package com.yehsung.aingcheck.core.rules.mahjong

/** 패 한 면 — 앞면(종류 · 적도라) 또는 뒷면. */
sealed interface MahjongTileFace {
    data class Tile(val kindValue: Int, val red: Boolean) : MahjongTileFace
    data object Back : MahjongTileFace

    val kind: Int? get() = (this as? Tile)?.kindValue
    val isRed: Boolean get() = (this as? Tile)?.red == true

    /** 접근성 이름("5만, 적도라" · "동"). */
    val spokenName: String
        get() {
            val t = this as? Tile ?: return "뒷면"
            return MahjongTileArtModel.koreanName(t.kindValue) + if (t.red) ", 적도라" else ""
        }

    companion object {
        /** 물리 패 → 면. 적5 는 id 16 · 52 · 88 만. */
        fun of(tile: MahjongTile): MahjongTileFace = Tile(tile.kind, tile.isRed)

        /** 34 종류 + 적5 셋 + 뒷면 = 38면. */
        val all: List<MahjongTileFace> = (0 until 34).map { Tile(it, false) } + listOf(4, 13, 22).map { Tile(it, true) } + Back
    }
}

/** 크기 7종. 24×32 이하는 단순화(보조 글자 없음 · 8 · 9삭 막대 사이 넓힘). */
enum class MahjongTileSize(val width: Float, val height: Float) {
    /** 내 손패 46×62. */
    hand(46f, 62f),
    /** 결과 화면 손 40×54. */
    result(40f, 54f),
    /** 강(버린 패) 36×48. */
    discard(36f, 48f),
    /** 내 울음 34×46. */
    meld(34f, 46f),
    /** 30×40(옛 강 · 도라 크기). */
    river(30f, 40f),
    /** 상대 울음 24×32. */
    smallMeld(24f, 32f),
    /** 상대 손 뒷면 18×24. */
    back(18f, 24f);

    val isSimplified: Boolean get() = width <= 24f
}

/** 그림 상태 — 쯔모기리 한 단 어둡게 · 울려 간 패 흐리게 · 못 버리는 패 흐림 · 하이라이트. */
enum class MahjongTileState { normal, tsumogiri, taken, disabled, highlighted }

/** 정규 좌표(0~1, 얼굴 칸 기준 — 위가 0). */
data class MahjongArtPoint(val x: Double, val y: Double)

/** 잉크 이름 — 실제 색은 팔레트가 정한다. */
enum class MahjongTileInk { navy, red, green, blue, gold, lavender }

/** 한 면의 배치 — 그리는 쪽은 이 값만 읽는다. */
data class MahjongTileLayout(
    val pips: List<Pip> = emptyList(),
    val sticks: List<Stick> = emptyList(),
    val glyphs: List<Glyph> = emptyList(),
    /** 1삭 — 막대 대신 우리 모양. */
    val sprout: Boolean = false,
    /** 白 — 라벤더 둥근 사각 테두리. */
    val hakuFrame: Boolean = false,
    /** 적5 — 오른쪽 위 금색 점. */
    val goldDot: Boolean = false,
    val isBack: Boolean = false,
    /** 모서리 보조 글자. */
    val cornerLabel: String? = null,
) {
    data class Pip(val center: MahjongArtPoint, val radius: Double, val ink: MahjongTileInk)
    data class Stick(val center: MahjongArtPoint, val length: Double, val ink: MahjongTileInk)
    data class Glyph(val text: String, val center: MahjongArtPoint, val size: Double, val ink: MahjongTileInk)
}

/** 팔레트 — 몸체 위 · 아래 · 베벨 · 뒷면 두 색 · 뒷면 테두리 · 글자 남색 + 고정 잉크. 색은 "#RRGGBB". */
data class MahjongTilePalette(
    val bodyTop: String, val bodyBottom: String, val bevel: String, val backTop: String, val backBottom: String, val backRim: String, val ink: String,
) {
    /** 고정 잉크(전통 색 구분). */
    fun hex(ink: MahjongTileInk): String = when (ink) {
        MahjongTileInk.navy -> this.ink
        MahjongTileInk.red -> "#DE2F45"
        MahjongTileInk.green -> "#12B886"
        MahjongTileInk.blue -> "#2563EB"
        MahjongTileInk.gold -> "#F5B700"
        MahjongTileInk.lavender -> "#9B8BD6"
    }

    companion object {
        /** 코드 팔레트 — 몸체 · 베벨 · 글자 남색은 고정, 뒷면 세 색은 고른 뒷면 짝. */
        fun code(back: MahjongTileBackScheme): MahjongTilePalette {
            val c = back.colors
            return MahjongTilePalette("#FBF9FF", "#ECE7F7", "#C9C0E3", c.first, c.second, c.third, "#1F2A5A")
        }

        val standard: MahjongTilePalette get() = code(MahjongTileArtStyle.chosen.backScheme)

        /** "#RRGGBB" → 0~1 세 채널. 틀리면 null. */
        fun rgb(hex: String): Triple<Double, Double, Double>? {
            var text = hex.trim()
            if (text.startsWith("#")) text = text.drop(1)
            if (text.length != 6) return null
            val v = text.toIntOrNull(16) ?: return null
            return Triple(((v shr 16) and 0xFF) / 255.0, ((v shr 8) and 0xFF) / 255.0, (v and 0xFF) / 255.0)
        }
    }
}

object MahjongTileArtModel {
    /** 만 위 글자(1~9). 5 는 전통대로 伍. */
    val manNumerals = listOf("一", "二", "三", "四", "伍", "六", "七", "八", "九")
    const val manSuffix = "萬"
    /** 자패 글자(종류 27~33 = 동남서북백발중). 白 은 글자 대신 테두리로 그린다. */
    val honorGlyphs = listOf("東", "南", "西", "北", "白", "發", "中")
    val honorCornerLabels = listOf("동", "남", "서", "북", "백", "발", "중")

    /** 한글 이름("5만" · "동"). */
    fun koreanName(kind: Int): String = when (kind) {
        in 0 until 9 -> "${kind + 1}만"
        in 9 until 18 -> "${kind - 8}통"
        in 18 until 27 -> "${kind - 17}삭"
        in 27 until 34 -> honorCornerLabels[kind - 27]
        else -> "?"
    }

    /** 방위 → 시계 방향 90° 회전 수(그 사람 쪽이 패의 아래). 나 0 · 하가(오른쪽) 3 · 대면 2 · 상가(왼쪽) 1. */
    fun rotation(compass: MahjongCompass): Int = when (compass) {
        MahjongCompass.bottom -> 0
        MahjongCompass.right -> 3
        MahjongCompass.top -> 2
        MahjongCompass.left -> 1
    }

    /** 한 면의 배치. */
    fun layout(face: MahjongTileFace): MahjongTileLayout {
        val t = face as? MahjongTileFace.Tile ?: return MahjongTileLayout(isBack = true)
        val kind = t.kindValue
        val layout = when (kind) {
            in 0 until 9 -> man(kind + 1)
            in 9 until 18 -> pin(kind - 8)
            in 18 until 27 -> sou(kind - 17)
            else -> honor(kind - 27)
        }
        if (!t.red) return layout
        return layout.copy(
            pips = layout.pips.map { it.copy(ink = MahjongTileInk.red) },
            sticks = layout.sticks.map { it.copy(ink = MahjongTileInk.red) },
            glyphs = layout.glyphs.map { it.copy(ink = MahjongTileInk.red) },
            goldDot = true,
        )
    }

    private fun pt(x: Double, y: Double) = MahjongArtPoint(x, y)

    private fun man(n: Int) = MahjongTileLayout(
        glyphs = listOf(
            MahjongTileLayout.Glyph(manNumerals[n - 1], pt(0.5, 0.30), 0.36, MahjongTileInk.navy),
            MahjongTileLayout.Glyph(manSuffix, pt(0.5, 0.71), 0.40, MahjongTileInk.red),
        ),
        cornerLabel = "$n",
    )

    private fun pin(n: Int): MahjongTileLayout {
        val l = 0.28
        val c = 0.5
        val r = 0.72
        fun p(x: Double, y: Double, radius: Double, ink: MahjongTileInk) = MahjongTileLayout.Pip(pt(x, y), radius, ink)
        val b = MahjongTileInk.blue
        val g = MahjongTileInk.green
        val rd = MahjongTileInk.red
        val pips = when (n) {
            1 -> listOf(p(c, 0.5, 0.36, rd))
            2 -> listOf(p(c, 0.27, 0.19, b), p(c, 0.73, 0.19, g))
            3 -> listOf(p(0.26, 0.2, 0.15, b), p(c, 0.5, 0.15, rd), p(0.74, 0.8, 0.15, g))
            4 -> listOf(p(l, 0.28, 0.17, b), p(r, 0.28, 0.17, g), p(l, 0.72, 0.17, g), p(r, 0.72, 0.17, b))
            5 -> listOf(p(0.26, 0.22, 0.14, b), p(0.74, 0.22, 0.14, g), p(c, 0.5, 0.14, rd), p(0.26, 0.78, 0.14, g), p(0.74, 0.78, 0.14, b))
            6 -> listOf(p(l, 0.18, 0.13, g), p(r, 0.18, 0.13, g), p(l, 0.52, 0.13, rd), p(r, 0.52, 0.13, rd), p(l, 0.82, 0.13, rd), p(r, 0.82, 0.13, rd))
            7 -> listOf(
                p(0.24, 0.13, 0.11, g), p(c, 0.24, 0.11, g), p(0.76, 0.35, 0.11, g),
                p(l, 0.6, 0.11, rd), p(r, 0.6, 0.11, rd), p(l, 0.86, 0.11, rd), p(r, 0.86, 0.11, rd),
            )
            8 -> listOf(0.12, 0.37, 0.63, 0.88).flatMap { y -> listOf(p(l, y, 0.115, b), p(r, y, 0.115, b)) }
            else -> listOf(0.18 to b, 0.5 to rd, 0.82 to g).flatMap { (y, ink) -> listOf(p(0.2, y, 0.12, ink), p(c, y, 0.12, ink), p(0.8, y, 0.12, ink)) }
        }
        return MahjongTileLayout(pips = pips, cornerLabel = "$n")
    }

    private fun sou(n: Int): MahjongTileLayout {
        fun s(x: Double, y: Double, length: Double, ink: MahjongTileInk = MahjongTileInk.green) = MahjongTileLayout.Stick(pt(x, y), length, ink)
        val red = MahjongTileInk.red
        if (n == 1) return MahjongTileLayout(sprout = true, cornerLabel = "1")
        val sticks = when (n) {
            2 -> listOf(s(0.5, 0.27, 0.36), s(0.5, 0.73, 0.36))
            3 -> listOf(s(0.5, 0.27, 0.36), s(0.3, 0.73, 0.36), s(0.7, 0.73, 0.36))
            4 -> listOf(s(0.3, 0.27, 0.36), s(0.7, 0.27, 0.36), s(0.3, 0.73, 0.36), s(0.7, 0.73, 0.36))
            5 -> listOf(s(0.24, 0.27, 0.36), s(0.76, 0.27, 0.36), s(0.5, 0.5, 0.36, red), s(0.24, 0.73, 0.36), s(0.76, 0.73, 0.36))
            6 -> listOf(0.27, 0.73).flatMap { y -> listOf(0.22, 0.5, 0.78).map { s(it, y, 0.36) } }
            7 -> listOf(s(0.5, 0.15, 0.24, red)) + listOf(0.47, 0.8).flatMap { y -> listOf(0.22, 0.5, 0.78).map { s(it, y, 0.28) } }
            8 -> listOf(0.27, 0.73).flatMap { y -> listOf(0.16, 0.39, 0.61, 0.84).map { s(it, y, 0.36) } }
            else -> listOf(0.17, 0.5, 0.83).flatMap { y -> listOf(s(0.2, y, 0.26), s(0.5, y, 0.26, red), s(0.8, y, 0.26)) }
        }
        return MahjongTileLayout(sticks = sticks, cornerLabel = "$n")
    }

    private fun honor(index: Int): MahjongTileLayout {
        val label = honorCornerLabels[index]
        return when (index) {
            4 -> MahjongTileLayout(hakuFrame = true, cornerLabel = label)
            5 -> MahjongTileLayout(glyphs = listOf(MahjongTileLayout.Glyph(honorGlyphs[index], pt(0.5, 0.52), 0.56, MahjongTileInk.green)), cornerLabel = label)
            6 -> MahjongTileLayout(glyphs = listOf(MahjongTileLayout.Glyph(honorGlyphs[index], pt(0.5, 0.52), 0.56, MahjongTileInk.red)), cornerLabel = label)
            else -> MahjongTileLayout(glyphs = listOf(MahjongTileLayout.Glyph(honorGlyphs[index], pt(0.5, 0.52), 0.56, MahjongTileInk.navy)), cornerLabel = label)
        }
    }
}

/** ① 패 뒷면. */
enum class MahjongTileBackScheme {
    navyPink, violetPink, raspberryBlush, lavenderPink;

    /** (위 · 아래 · 테두리). */
    val colors: Triple<String, String, String>
        get() = when (this) {
            navyPink -> Triple("#2A3270", "#1B2150", "#FF6FA5")
            violetPink -> Triple("#5B3FB2", "#3A2680", "#FF8DC7")
            raspberryBlush -> Triple("#C2407E", "#8A2456", "#FFD3E8")
            lavenderPink -> Triple("#8B7BE0", "#5F4FBF", "#FF7EB8")
        }
}

/** ② 1삭 그림. */
enum class MahjongOneSouMotif { sprout, aingFace, bambooNode }

/** ③ 모서리 보조 글자. */
enum class MahjongCornerLabelStyle {
    numbersAndHonors, numbersOnly, hidden;

    fun label(layout: MahjongTileLayout, face: MahjongTileFace): String? = when (this) {
        numbersAndHonors -> layout.cornerLabel
        numbersOnly -> if ((face.kind ?: 99) < 27) layout.cornerLabel else null
        hidden -> null
    }
}

/** 패 그림 선택지 한 벌. 대표가 그림으로 고르면 [chosen] 한 줄만 바꾼다. */
data class MahjongTileArtStyle(val backScheme: MahjongTileBackScheme, val oneSouMotif: MahjongOneSouMotif, val cornerLabel: MahjongCornerLabelStyle) {
    companion object {
        val chosen = MahjongTileArtStyle(MahjongTileBackScheme.navyPink, MahjongOneSouMotif.sprout, MahjongCornerLabelStyle.numbersAndHonors)
    }
}
