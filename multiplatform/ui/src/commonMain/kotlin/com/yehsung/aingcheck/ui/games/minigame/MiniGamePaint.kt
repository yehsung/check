// 원본: Sources/CheckCore/MiniGameEngine.swift @ 3bd04bd (MiniGameStage 의 색 — skyTop … glow, 무대 다섯)
// 원본: Sources/CheckCore/CheckTheme.swift @ 3bd04bd (게임 캔버스가 쓰는 맥 패널 색 — panel · panelElevated · border · 글자 · 뜻 색)
// 원본: Sources/CheckCore/TimingBarGame.swift @ 3bd04bd (Verdict.tint — 판정 색. 등급·라벨·글리프는 core/rules 가 옮겼다)
//
// 게임 캔버스의 색. 캔버스는 무대 하늘이 늘 어두워 라이트·다크와 무관하게 **같은 그림**이다(Swift GamesCanvasKit 머리말) — 그래서 이 색들은
// AingTheme.colors(라이트·다크로 갈리는 뜻 색)가 아니라 맥 패널 색(CheckTheme) 값 그대로다. 규칙 몫(무대 id·경계·고르기)은 core/rules
// `MiniGameStage` 이고, 색은 그림의 것이라 여기(W4-b)가 옮긴다(C§3.2 "—" 행).
package com.yehsung.aingcheck.ui.games.minigame

import androidx.compose.ui.graphics.Color
import com.yehsung.aingcheck.core.rules.minigame.MiniGameStage
import com.yehsung.aingcheck.core.rules.minigame.TimingBarGame

/** 맥 `CheckTheme` 의 게임 캔버스 몫(값 그대로). */
object GamesCanvasColors {
    val panel = Color(0.17f, 0.18f, 0.24f)
    val panelElevated = Color(0.21f, 0.22f, 0.29f)
    val border = Color.White.copy(alpha = 0.14f)
    val primaryText = Color.White.copy(alpha = 0.94f)
    val secondaryText = Color.White.copy(alpha = 0.68f)
    val working = Color(0.35f, 0.88f, 0.63f)
    val offWork = Color(0.58f, 0.68f, 0.80f)
    val pending = Color(1.0f, 0.72f, 0.33f)
    val accent = Color(0.33f, 0.67f, 1.0f)
    val danger = Color(1.0f, 0.45f, 0.46f)

    /** 타이밍 바 100점(완벽)만 쓰는 금색 — 테마에 없는 색이다(초록을 90점대와 나눠 쓰면 완벽과 훌륭이 한눈에 안 갈린다). */
    val perfectGold = Color(1.00f, 0.84f, 0.52f)
}

/** 무대 한 장의 색(Swift `MiniGameStage` 의 Color 칸 아홉). */
class MiniGameStagePaint(
    val skyTop: Color,
    val skyBottom: Color,
    /** 먼 능선(가장 느린 패럴랙스 층). */
    val far: Color,
    /** 가까운 언덕(빠른 층). */
    val near: Color,
    /** 밝은 구조색 — 면적이 큰 몸통에는 쓰지 않는다(타이밍 바 목표 구간처럼 작고 조준해야 하는 곳). */
    val structure: Color,
    /** 기둥 본체(위쪽·가장 어두운 쪽). 캐릭터와 3:1 이상 벌어지는 대역이다(밝은 색으로 채우면 한낮 1.01:1 — 캐릭터가 사라졌다). */
    val structureDeep: Color,
    /** 기둥 본체(아래쪽) = structureDeep + 채널당 0.08. */
    val structureDeepLit: Color,
    /** 기둥·트랙 테두리(밝은 쪽) — 어두워진 본체를 윤곽으로 세운다. */
    val structureEdge: Color,
    /** 강조(별·마커·명중 링·점수 팝). */
    val glow: Color,
)

/** 무대 id → 색. 순서는 core `MiniGameStage.all` 과 같다(인덱스 = id). */
object MiniGameStagePalette {
    val dawn = MiniGameStagePaint(
        skyTop = Color(0.14f, 0.11f, 0.23f), skyBottom = Color(0.36f, 0.23f, 0.37f),
        far = Color(0.23f, 0.17f, 0.32f), near = Color(0.14f, 0.10f, 0.22f),
        structure = Color(0.49f, 0.42f, 0.81f), structureDeep = Color(0.13f, 0.11f, 0.34f),
        structureDeepLit = Color(0.21f, 0.19f, 0.42f), structureEdge = Color(0.73f, 0.66f, 1.00f),
        glow = Color(1.00f, 0.77f, 0.54f),
    )
    val day = MiniGameStagePaint(
        skyTop = Color(0.09f, 0.20f, 0.31f), skyBottom = Color(0.18f, 0.43f, 0.59f),
        far = Color(0.11f, 0.27f, 0.39f), near = Color(0.08f, 0.19f, 0.27f),
        structure = Color(0.27f, 0.72f, 0.48f), structureDeep = Color(0.11f, 0.29f, 0.19f),
        structureDeepLit = Color(0.19f, 0.37f, 0.27f), structureEdge = Color(0.54f, 0.94f, 0.75f),
        glow = Color(1.00f, 0.91f, 0.66f),
    )
    val dusk = MiniGameStagePaint(
        skyTop = Color(0.23f, 0.14f, 0.31f), skyBottom = Color(0.71f, 0.33f, 0.24f),
        far = Color(0.35f, 0.18f, 0.27f), near = Color(0.17f, 0.09f, 0.19f),
        structure = Color(0.88f, 0.54f, 0.29f), structureDeep = Color(0.35f, 0.22f, 0.12f),
        structureDeepLit = Color(0.43f, 0.30f, 0.20f), structureEdge = Color(1.00f, 0.76f, 0.48f),
        glow = Color(1.00f, 0.82f, 0.48f),
    )
    val night = MiniGameStagePaint(
        skyTop = Color(0.03f, 0.05f, 0.12f), skyBottom = Color(0.09f, 0.13f, 0.25f),
        far = Color(0.06f, 0.10f, 0.20f), near = Color(0.03f, 0.05f, 0.10f),
        structure = Color(0.31f, 0.48f, 0.85f), structureDeep = Color(0.12f, 0.19f, 0.34f),
        structureDeepLit = Color(0.20f, 0.27f, 0.42f), structureEdge = Color(0.62f, 0.75f, 1.00f),
        glow = Color(0.55f, 0.89f, 1.00f),
    )
    val aurora = MiniGameStagePaint(
        skyTop = Color(0.01f, 0.06f, 0.10f), skyBottom = Color(0.05f, 0.23f, 0.22f),
        far = Color(0.04f, 0.17f, 0.20f), near = Color(0.02f, 0.08f, 0.10f),
        structure = Color(0.21f, 0.84f, 0.66f), structureDeep = Color(0.08f, 0.33f, 0.25f),
        structureDeepLit = Color(0.16f, 0.41f, 0.33f), structureEdge = Color(0.61f, 1.00f, 0.88f),
        glow = Color(0.49f, 1.00f, 0.83f),
    )

    /** 인덱스 = 무대 id. */
    val all: List<MiniGameStagePaint> = listOf(dawn, day, dusk, night, aurora)

    /** 무대의 색. **빠짐없는 when** — 무대가 늘면 컴파일러가 여기를 멈춰 세운다(else 로 접지 않는다). */
    fun of(stage: MiniGameStage): MiniGameStagePaint = when (stage) {
        MiniGameStage.dawn -> dawn
        MiniGameStage.day -> day
        MiniGameStage.dusk -> dusk
        MiniGameStage.night -> night
        MiniGameStage.aurora -> aurora
    }
}

/** 무대의 색(줄임). */
val MiniGameStage.paint: MiniGameStagePaint get() = MiniGameStagePalette.of(this)

/** 타이밍 바 판정 색(Swift `Verdict.tint`). 100점만 금색, 나머지는 테마 뜻 색 — 색만으로 말하지 않으려 글리프가 따로 있다. */
val TimingBarGame.Verdict.tint: Color
    get() = when (this) {
        TimingBarGame.Verdict.perfect -> GamesCanvasColors.perfectGold
        TimingBarGame.Verdict.great -> GamesCanvasColors.working
        TimingBarGame.Verdict.good -> GamesCanvasColors.accent
        TimingBarGame.Verdict.close -> GamesCanvasColors.pending
        TimingBarGame.Verdict.miss -> GamesCanvasColors.danger
    }
