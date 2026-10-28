// 원본: 없음 — CoreGraphics `CGPoint` · `CGSize` · `CGRect` 의 공용 자리(폰 판 좌표 판정 GamesGomokuBoardLayout · GamesChessBoardLayout 이 쓴다).
package com.yehsung.aingcheck.core.stores.gomoku

// 판 좌표 판정은 순수 산수라 스토어 층(commonMain)에서 잰다 — Compose 의 Offset·Size 는 ui 모듈 것이라 여기서 쓰지 않는다(의존 방향 stores ← ui).
// 단위는 Swift 와 같이 pt(화면 갈래가 dp 로 넘긴다). CGFloat 은 64비트 Double 이다(맥·iOS 64비트).

/** Swift `CGPoint`. */
data class BoardPoint(val x: Double, val y: Double)

/** Swift `CGSize`. */
data class BoardSize(val width: Double, val height: Double)

/** Swift `CGRect`(원점 + 크기). */
data class BoardRect(val x: Double, val y: Double, val width: Double, val height: Double) {
    val minX: Double get() = x
    val minY: Double get() = y
    val midX: Double get() = x + width / 2
    val midY: Double get() = y + height / 2
}
