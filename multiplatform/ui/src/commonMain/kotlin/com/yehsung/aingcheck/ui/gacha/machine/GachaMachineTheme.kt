// 원본: Sources/CheckCore/GachaMachine/GachaMachineTheme.swift @ 3bd04bd
// 원본: Sources/CheckCore/GachaMachine/GachaMachineDirector.swift @ 3bd04bd (GPalette — 테마와 무관한 캡슐·금색)
//
// 기계의 색은 **브랜드 자리**(G §8-15 — 뽑기는 보라 판)라 앱 주요색(iOS 파랑) 대신 맥 기계 색 그대로다. 숫자는 Swift 원문 그대로.
package com.yehsung.aingcheck.ui.gacha.machine

import androidx.compose.ui.graphics.Color

object GPalette {
    fun hex(v: Long, a: Float = 1f): Color =
        Color(((v shr 16) and 0xFF).toInt() / 255f, ((v shr 8) and 0xFF).toInt() / 255f, (v and 0xFF).toInt() / 255f, a)

    val lav = hex(0xCFBAFE)
    val lavDeep = hex(0x9979E6)
    val lavInk = hex(0x6A4FC8)
    val plum = hex(0x2D2150)
    val gold = hex(0xFFD24A)
    val goldDeep = hex(0xE5A200)
    val goldLight = hex(0xFFF2C2)

    val capsulePairs: List<Pair<Color, Color>> = listOf(
        hex(0xFF8FC0) to hex(0x6FC4FF), hex(0x78E0BC) to hex(0xFFB15A), hex(0xB79BFF) to hex(0xFFD84F),
        hex(0x6FD0FF) to hex(0xFF7B8F), hex(0xFFD45E) to hex(0x9C7BFF), hex(0x8EE58E) to hex(0xFF8FC0),
        hex(0xFFA36B) to hex(0x62CFE8),
    )
}

/** 밝은 화면 · 어두운 화면 색. 기계 그림(라벤더 몸통 · 캡슐)은 둘 다에서 같고, 바탕 · 글자 · 칩 · 빛이 갈린다. */
data class GachaMachineTheme(
    val dark: Boolean,
    val bgTop: Color,
    val bgBottom: Color,
    val bgGlow: Color,
    /** 안내 글자(손잡이를 돌려서 뽑기 · 두근두근 · 톡톡). */
    val ink: Color,
    /** 결과 이름. */
    val title: Color,
    /** 조각 "+1" 처럼 강조한 글자(결과 글줄 · 24pt). */
    val accent: Color,
    /** 칩 아래 "+1 조각" 처럼 작은 알약 속 글자. */
    val accentStrong: Color,
    val chipFill: Color,
    val chipStroke: Color,
    val chipText: Color,
    val pillFill: Color,
    val warn: Color,
    val badgeFill: Color,
    val badgeText: Color,
    val closeFill: Color,
    val closeStroke: Color,
    val closeText: Color,
    /** "-50". */
    val spend: Color,
    /** 바닥 그림자 진하기. */
    val floorShadow: Float,
    /** 유리 돔 뒷면(우윳빛)과 아래 틴트. */
    val glassBack: Pair<Color, Color>,
    val glassTint: Color,
    /** 일반 공개의 무대(가장자리가 가라앉아 빛이 보이게) — (위치, 색). */
    val spotlight: List<Pair<Float, Color>>,
    val flash: Color,
    val flashPeak: Float,
    /** 일반 공개 빛줄기가 어두운 바탕 기준인가. */
    val raysOnDark: Boolean,
    val shardTrail: Color,
    val shardOrbEdge: Color,
    val shardOutline: Color,
) {
    companion object {
        private val hex = GPalette::hex

        val light = GachaMachineTheme(
            dark = false,
            bgTop = hex(0xF8F5FF, 1f), bgBottom = hex(0xECE4FF, 1f), bgGlow = Color.White.copy(alpha = 0.9f),
            ink = GPalette.lavInk, title = GPalette.plum, accent = GPalette.lavInk, accentStrong = GPalette.lavInk,
            chipFill = Color.White.copy(alpha = 0.92f), chipStroke = hex(0xD9CBFF, 1f), chipText = GPalette.plum,
            pillFill = Color.White.copy(alpha = 0.9f), warn = hex(0xB0477A, 1f),
            badgeFill = Color.White.copy(alpha = 0.92f), badgeText = GPalette.lavInk,
            closeFill = Color.White.copy(alpha = 0.92f), closeStroke = hex(0xD9CBFF, 1f), closeText = GPalette.lavInk,
            spend = hex(0xD9468F, 1f),
            floorShadow = 0.13f,
            glassBack = Color.White.copy(alpha = 0.55f) to hex(0xE6DBFF, 0.55f), glassTint = hex(0xB9A0F5, 0.18f),
            spotlight = listOf(
                0f to hex(0xF4EEFF, 0f),
                0.36f to hex(0xC2A9FF, 0.55f),
                0.72f to hex(0x8A68E6, 0.85f),
                1f to hex(0x6E4DD2, 0.95f),
            ),
            flash = Color.White, flashPeak = 0.8f, raysOnDark = false,
            shardTrail = hex(0x7B5CE6, 1f), shardOrbEdge = hex(0x6A4FC8, 1f), shardOutline = hex(0x3B2A78, 0.85f),
        )

        val night = GachaMachineTheme(
            dark = true,
            bgTop = hex(0x221A3D, 1f), bgBottom = hex(0x120C22, 1f), bgGlow = hex(0x6F55C8, 0.38f),
            ink = hex(0xCDBDFF, 1f), title = hex(0xF4EFFF, 1f), accent = hex(0xC4B0FF, 1f), accentStrong = hex(0xE4D8FF, 1f),
            chipFill = hex(0x2B2148, 0.94f), chipStroke = hex(0x5C4A99, 1f), chipText = hex(0xF0EAFF, 1f),
            pillFill = hex(0x2B2148, 0.94f), warn = hex(0xFF97C2, 1f),
            badgeFill = hex(0x2B2148, 0.94f), badgeText = hex(0xD9CCFF, 1f),
            closeFill = Color.White.copy(alpha = 0.12f), closeStroke = Color.White.copy(alpha = 0.24f), closeText = Color.White,
            spend = hex(0xFF86BC, 1f),
            floorShadow = 0.42f,
            glassBack = Color.White.copy(alpha = 0.20f) to hex(0xB9A0F5, 0.26f), glassTint = hex(0x7B5CE6, 0.22f),
            spotlight = listOf(
                0f to hex(0x2A1D55, 0f),
                0.36f to hex(0x2A1D55, 0.55f),
                0.72f to hex(0x160E30, 0.88f),
                1f to hex(0x0B0717, 0.96f),
            ),
            flash = hex(0xECE4FF, 1f), flashPeak = 0.5f, raysOnDark = true,
            shardTrail = hex(0xB49BFF, 1f), shardOrbEdge = hex(0x8C6CF2, 1f), shardOutline = hex(0x120A26, 0.6f),
        )

        fun of(dark: Boolean): GachaMachineTheme = if (dark) night else light
    }
}

/**
 * 희귀 공개(황금 · 무지개 — v0.3.59)의 빛깔. 연출의 **모양**은 둘이 같고 **색만** 갈린다 — 금은 따뜻한 한 색, 무지개는 빛줄기 · 고리 ·
 * 제목 글자가 일곱 빛을 돌고 한 색이 필요한 자리(새는 빛 · 그림자 · 섬광 심)는 옅은 분홍빛 흰색이다. 무지개도 정적이다.
 */
enum class GRare {
    Gold,
    Rainbow;

    /** 한 색이 필요한 자리의 주 색(새는 빛 · 결정 테 · 초상 그림자 · 빛 고리 기본). */
    val primary: Color get() = if (this == Gold) GPalette.gold else GPalette.hex(0xF2B6FF)

    /** 밝은 심(금 사이 밝은 선 · 반전 고리 · 부제 글자). */
    val light: Color get() = if (this == Gold) GPalette.goldLight else GPalette.hex(0xFFF0FB)

    /** 빛줄기 i(전체 n)의 색 — 금은 한 색, 무지개는 둘레를 따라 일곱 빛. */
    fun ray(i: Int, of: Int): Color = when (this) {
        Gold -> GPalette.hex(0xFFE08A)
        Rainbow -> spectrum[(i * spectrum.size / maxOf(1, of)) % spectrum.size]
    }

    /** 퍼지는 빛 고리 k 번째의 색. */
    fun ring(k: Int): Color = when (this) {
        Gold -> GPalette.gold
        Rainbow -> spectrum[(k * 2) % spectrum.size]
    }

    /** 가운데 심 광채. */
    val core: Color get() = if (this == Gold) GPalette.hex(0xFFE9A8) else GPalette.hex(0xFFF3FC)

    /** 터지는 순간의 섬광(가운데 → 가장자리, 더하기 합성). */
    val flash: List<Color>
        get() = when (this) {
            Gold -> listOf(GPalette.hex(0xFFE7A6), GPalette.hex(0xFFC94A, 0.85f), GPalette.hex(0xB07A10, 0.5f))
            Rainbow -> listOf(GPalette.hex(0xFFF5FD), GPalette.hex(0xF0C4FF, 0.85f), GPalette.hex(0x6F55D8, 0.5f))
        }

    /** 어두운 무대 가운데에 도는 빛(금 = 갈색 온기 · 무지개 = 보랏빛). */
    val dimGlow: Color get() = if (this == Gold) GPalette.hex(0x7A5212) else GPalette.hex(0x5A3296)

    /** 반짝 제목의 글자 칠 정지점 — 금은 위 → 아래, 무지개는 왼쪽 → 오른쪽. */
    val titleStops: List<Color>
        get() = when (this) {
            Gold -> listOf(GPalette.hex(0xFFF0B0), GPalette.gold, GPalette.hex(0xF0A800))
            Rainbow -> spectrum
        }
    val titleVertical: Boolean get() = this == Gold

    /** 제목 둘레 빛 · 글자 아래 테. */
    val titleGlow: Color get() = if (this == Gold) GPalette.gold.copy(alpha = 0.65f) else GPalette.hex(0xE6A6FF, 0.65f)
    val titleEdge: Color get() = if (this == Gold) GPalette.hex(0x7A4D00, 0.35f) else GPalette.hex(0x3B2370, 0.45f)

    companion object {
        /** 무지개 일곱 빛(빨 · 주 · 노 · 초 · 파 · 남 · 보). 어두운 무대에 더하기 합성으로 얹어도 형광으로 안 튀는 밝은 파스텔. */
        val spectrum: List<Color> = listOf(
            GPalette.hex(0xFF7A90), GPalette.hex(0xFFAE5E), GPalette.hex(0xFFE35A), GPalette.hex(0x7EDF8C),
            GPalette.hex(0x6CB8FF), GPalette.hex(0x9C8CFF), GPalette.hex(0xE08CFF),
        )

        fun of(kind: GachaRevealKind): GRare? = when (kind) {
            GachaRevealKind.Gold -> Gold
            GachaRevealKind.Rainbow -> Rainbow
            GachaRevealKind.New, GachaRevealKind.Duplicate -> null
        }
    }
}
