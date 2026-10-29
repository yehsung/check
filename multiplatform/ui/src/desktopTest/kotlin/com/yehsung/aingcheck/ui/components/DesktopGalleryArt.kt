// 원본: 없음 — 데스크톱 스냅숏 하네스의 ui 전용 조각(시험 도구).
//
// 하네스 본체(DesktopSnapshots)는 testkit desktopMain 으로 옮겼다(공용 패치 7 — desktopApp 시험도 같이 쓴다).
// 갤러리 그림은 ui 의 GalleryArt·CharacterStageMetrics·RubyGlyph 를 알아야 해서 ui 를 모르는 testkit 으로 못 가고, 여기 확장으로 남는다.
package com.yehsung.aingcheck.ui.components

fun DesktopSnapshots.galleryArt(): GalleryArt {
    val stagePath = if (CharacterStageMetrics.prefersStageArt("fox", CharacterExpression.Neutral, 120f, DENSITY))
        "Sources/CheckMobileKit/Resources/Art/stage-fox-neutral.png" else "Sources/check/Characters/fox/portrait-neutral.png"
    return GalleryArt(
        portraitNeutral = repoImage("Sources/check/Characters/fox/portrait-neutral.png"),
        portraitNegative = repoImage("Sources/check/Characters/fox/portrait-negative.png"),
        stage = repoImage(stagePath),
        ruby = repoImage("Sources/CheckMobileKit/Resources/Art/${RubyGlyph.assetName(24f, DENSITY)}.png"),
    )
}
