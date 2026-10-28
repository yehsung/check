// 원본: 없음 — G §2-3 W2-e ④ "미니게임 표시 깃발: 해당 골든이 초록인 빌드에서만 켠다(B§10-5, 서버 게이트 없음)".
package com.yehsung.aingcheck.core.stores.minigame

import com.yehsung.aingcheck.core.rules.minigame.MiniGameKind

/**
 * Android(·Windows) 에 **보이는** 미니게임 — 미니게임 표시 깃발(G §2-3 W2-e ④ · B§10-5).
 *
 * 왜 필요한가(B§10-5): 미니게임 점수에는 서버 상수 게이트가 없다 — Android 판이 내는 점수가 **iOS·맥과 같은 순위표**에 바로 올라간다.
 * 그래서 엔진 물리·시간 하한이 Swift 와 같다는 대조(W1-a 골든)가 **이 빌드에서 초록**인 게임만 화면에 세운다.
 *
 * 깃발 = 증거 골든 목록([evidenceGoldens]). 한 게임은 그 게임의 **모든** 증거 골든이
 *  ① `contract/golden/_manifest.json` 에 있고 ② 게이트가 돌리는 Kotlin 시험이 그 이름을 `Golden.load` 로 대조할 때만 켜진다.
 * ①② 는 `MiniGameExposureGoldenTest`(core/stores desktopTest)가 잰다 — 그 시험과 증거 골든의 대조 시험(W1-a)이 같은 게이트에서
 * 돌므로 "깃발이 켜진 빌드 = 그 골든이 초록인 빌드" 다(빨간 골든이면 게이트가 빌드를 막는다). 골든이 하나라도 빠지면 그 게임은
 * 여기서 빠지고 허브·게임 탭이 그 게임을 열지 않는다.
 *
 * 폰 노출 규칙(`MiniGameKind.phoneCases` — 길건너는 폰 1.0.15 때 W4-b 가 정한다, G §8-16)이 먼저다: 증거가 있어도 폰 목록 밖이면
 * 보이지 않는다. 깃발은 그 위에 **좁히기만** 한다.
 */
object MiniGameExposure {
    /**
     * 게임마다 대조가 초록이어야 하는 골든(W1-a 소유 — 이름은 `contract/golden/<영역>/<이름>.json`). 엔진 규칙표 · 대본 재생이 핵심이고,
     * 테트리스는 조각열(bags)·방해 줄 구멍·손으로 짠 판까지 본다. 길건너는 폰에 아직 없지만 증거는 적어 둔다(1.0.15 때 그대로 쓴다).
     */
    val evidenceGoldens: Map<MiniGameKind, List<String>> = mapOf(
        MiniGameKind.timingBar to listOf("timing-bar/rules", "timing-bar/scripted"),
        MiniGameKind.flappy to listOf("flappy/rules", "flappy/scripted"),
        MiniGameKind.tetris to listOf("tetris/rules", "tetris/scripted", "tetris/bags", "tetris/garbage-holes", "tetris/fixtures"),
        MiniGameKind.crossy to listOf("crossy/rules", "crossy/lanes", "crossy/scripted"),
    )

    /** 폰 노출 규칙 ∩ 증거가 있는 게임(입력 순서 = 화면 순서). 시험이 증거 표를 바꿔 넣어 좁혀지는지 잰다. */
    fun visibleKinds(evidence: Map<MiniGameKind, List<String>> = evidenceGoldens): List<MiniGameKind> =
        MiniGameKind.phoneCases.filter { !evidence[it].isNullOrEmpty() }

    /** 이 빌드에 보이는 게임. */
    val visible: List<MiniGameKind> = visibleKinds()

    fun isVisible(kind: MiniGameKind): Boolean = kind in visible
}
