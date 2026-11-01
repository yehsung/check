// 원본: Sources/check/RummyTableCanvas.swift:79-176 (RummyBoardTile · RummyBoardMeld · RummyBoardPreview) · Sources/check/RummyPanelMatch.swift:97 (RummySeatArrangement) ·
//       Sources/check/RummyReactionOverlay.swift:39 (RummySeatCompass) · Sources/check/RummyArt.swift:16,151,171 (RummyArtKind · isAcceptable · outcome) ·
//       Sources/check/RummyTileView.swift:16,50 (RummyTilePalette · RummyTileSize) @ 1a5eeca6
package com.yehsung.aingcheck.core.rules.rummy

import com.yehsung.aingcheck.core.rules.format.roundedHalfAwayFromZero
import com.yehsung.aingcheck.core.wire.games.RummyFace

// 아잉 큐브 판 화면의 순수 값 — 맥 화면 파일(SwiftUI)에 있던 표들. 그리기 값과 판정만 옮겼고 플랫폼 타입(Color · NSImage · CGRect)은 값 타입으로 바꿨다.
// 자리 번호는 와이어와 같은 Long 이다. 맥 `RummySeatCompass.fallbackRect` 는 창 크기 값이라 옮기지 않는다(폰은 화면 단계가 자리 앵커를 잰다).

// MARK: - 자리

/** 상대 자리 배치 — 나 다음 사람부터 왼쪽 → 위 → 오른쪽(둘이면 위, 셋이면 왼·오른). 순수. */
data class RummySeatArrangement(val left: Long? = null, val top: Long? = null, val right: Long? = null) {
    /** 폰 상대 줄의 가로 순서(내 다음 차례부터 — 왼·위·오른이 곧 그 순서다). */
    val ordered: List<Long> get() = listOfNotNull(left, top, right)

    companion object {
        /** [seatNos] = 판의 자리 번호들, [mine] = 내 자리. 내 자리가 없으면 번호 순으로 그대로. */
        fun arrange(seatNos: List<Long>, mine: Long?): RummySeatArrangement {
            val sorted = seatNos.sorted()
            val at = if (mine == null) -1 else sorted.indexOf(mine)
            if (at < 0) return place(sorted)
            return place(sorted.subList(at + 1, sorted.size) + sorted.subList(0, at))
        }

        private fun place(others: List<Long>): RummySeatArrangement = when (others.size) {
            0 -> RummySeatArrangement()
            1 -> RummySeatArrangement(top = others[0])
            2 -> RummySeatArrangement(left = others[0], right = others[1])
            else -> RummySeatArrangement(left = others[0], top = others[1], right = others[2])
        }
    }
}

/** B 배치의 방위 — 나는 아래, 나머지는 내 다음 자리부터 시계 방향으로 왼 · 위 · 오른. 둘이면 마주 보고(위), 셋이면 왼·오른, 넷이면 왼·위·오른. */
enum class RummySeatCompass {
    bottom, left, top, right;

    companion object {
        fun of(seatNo: Long, mySeatNo: Long?, seatNos: List<Long>): RummySeatCompass {
            if (mySeatNo == null || seatNo == mySeatNo) return bottom
            val others = seatNos.toSet().minus(mySeatNo).sortedBy { relative(it, mySeatNo) }
            val index = others.indexOf(seatNo)
            if (index < 0) return top
            return when (others.size) {
                1 -> top
                2 -> if (index == 0) left else right
                else -> listOf(left, top, right)[minOf(index, 2)]
            }
        }

        /** 내 자리에서 시계 방향으로 몇 칸(자리 번호 0~3). */
        private fun relative(seat: Long, mine: Long): Long = ((seat - mine) % 4 + 4) % 4
    }
}

// MARK: - 판 위 그릴 값

/** 판 위에 그릴 타일 한 장(편집 가능한 판 = 편집기 타일 id, 남의/확정 판 = id 없음). */
data class RummyBoardTile(val id: Int?, val face: RummyFace, val highlighted: Boolean)

/** 판 위 묶음 하나(그릴 값). */
data class RummyBoardMeld(
    /** 모션 키 — 편집 중엔 첫 타일 id, 남의/확정 판은 면 글자 + 같은 키 안 순번(세트에는 id 가 없다). */
    val id: String,
    val tiles: List<RummyBoardTile>,
    val frame: RummyRect,
    val invalid: Boolean,
) {
    companion object {
        /** 모션 키 붙이기(면 글자 + 순번). */
        fun faceKeys(sets: List<List<RummyFace>>): List<String> {
            val seen = HashMap<String, Int>()
            return sets.map { set ->
                val key = RummyRules.compareKey(set).joinToString(",") { it.text }
                val n = seen[key] ?: 0
                seen[key] = n + 1
                "f:$key#$n"
            }
        }
    }
}

/**
 * 판 위 놓기 미리보기(3판 — 편집기 `previewDrop`·`previewMoveSet` 의 계획을 그릴 값으로, 논리 좌표).
 * 놓기 전에 "어디에 어떻게 들어가는가"를 보인다: 붙을 끝에 자석 · 끼울 자리 캐럿 · 새 묶음 점선.
 * 색: 놓은 뒤 그 묶음이 맞는 세트면 초록(+ 체크), 아직 아니면 파랑.
 */
sealed interface RummyBoardPreview {
    /** 묶음 위에 놓아 맞는 자리에 끼운다 — 캐럿(지금 화면의 논리 x) + 놓은 뒤 묶음 윤곽. */
    data class Insert(val set: Int, val caretX: Long, val landing: RummyRect, val valid: Boolean) : RummyBoardPreview

    /** 다른 묶음 끝에 붙는다 — 대상 묶음의 그 끝에 자석 + 블록이 들어갈 칸 점선. */
    data class Attach(val set: Int, val side: RummyAttachSide, val slots: RummyRect, val landing: RummyRect, val valid: Boolean) : RummyBoardPreview

    /** 빈 곳에 새 묶음 · 묶음 옮기기 — 스냅된 자리 점선. */
    data class Ghost(val rect: RummyRect) : RummyBoardPreview

    /** 미리보기가 가리키는 묶음(테두리를 밝힌다). */
    val targetSet: Int?
        get() = when (this) {
            is Insert -> set
            is Attach -> set
            is Ghost -> null
        }

    /**
     * 자석이 설 이음 x(논리) — 블록 칸의 대상 쪽 끝. 대상 오른끝에 붙으면 칸 왼쪽, 왼끝에 붙으면 칸 오른쪽.
     * 대상이 지금 끌고 있는 묶음의 토막일 때 옮기기 전 묶음 끝(`frames[set]`)은 이음 자리가 아니다 — 늘 칸으로 잰다.
     */
    val magnetSeamX: Long?
        get() = if (this is Attach) (if (side == RummyAttachSide.right) slots.x else slots.maxX) else null

    /** 놓으면 그 묶음이 맞는 세트가 되는가(초록). */
    val completes: Boolean
        get() = when (this) {
            is Insert -> valid
            is Attach -> valid
            is Ghost -> false
        }

    /**
     * 첫 등록 전(R-12) 판 묶음에 꽂기: 세트는 맞아도 차례가 `initial_table_touched` 로 막힌다 — 초록·체크(맞음)를 거둔다(파랑 = 아직 아님).
     */
    fun beforeInitial(touchesTable: Boolean): RummyBoardPreview =
        if (touchesTable && this is Insert && valid) copy(valid = false) else this

    companion object {
        /**
         * 편집기 답 → 그릴 값. [meldTileIDs] = 지금 화면 묶음별 타일 id(화면 순), [frames] = 지금 묶음 사각형,
         * [dragged] = 손에 든 타일(제자리에 흐리게 남아 있다 — 캐럿은 그것을 뺀 타일 사이에 선다). 받침대행·거절은 null.
         */
        fun make(preview: RummyDropPreview?, blockCount: Int, meldTileIDs: List<List<Int>>, frames: List<RummyRect>, dragged: Set<Int>): RummyBoardPreview? {
            val landing = preview?.landing ?: return null
            val w = RummyTableLayout.tileWidth
            return when (val plan = preview.plan) {
                RummyDropPlan.Rack -> null
                is RummyDropPlan.NewSet -> Ghost(landing.frame)
                is RummyDropPlan.Attach -> {
                    if (plan.set !in frames.indices) return Ghost(landing.frame)
                    val slots = RummyRect(landing.frame.x + landing.blockStart * w, landing.frame.y, maxOf(1, blockCount) * w, RummyTableLayout.tileHeight)
                    Attach(plan.set, plan.side, slots, landing.frame, landing.valid)
                }
                is RummyDropPlan.Insert -> {
                    if (plan.set !in frames.indices || plan.set !in meldTileIDs.indices) return Ghost(landing.frame)
                    val ids = meldTileIDs[plan.set]
                    val kept = ids.indices.filter { ids[it] !in dragged }
                    val slot = when {
                        kept.isEmpty() -> 0
                        plan.index < kept.size -> kept[maxOf(0, plan.index)]
                        else -> kept[kept.size - 1] + 1
                    }
                    Insert(plan.set, frames[plan.set].x + slot * w, landing.frame, landing.valid)
                }
            }
        }
    }
}

// MARK: - 타일 값

/** 타일 팔레트 — 순수 상수(0xRRGGBB, 시험이 같은 값을 되묻는다). 그림 고유 값이라 테마 토큰이 아니다. */
object RummyTilePalette {
    const val bodyTop: Int = 0xFBF9FF
    const val bodyBottom: Int = 0xECE7F7

    /** 아래 베벨(몸체보다 한 단 진한 라벤더). */
    const val bevel: Int = 0xC9C0E3

    /** A 빨강 · B 파랑 · C 검정 · D 주황(밝은 몸체 위 진한 잉크). */
    val inks: List<Int> = listOf(0xDE2F45, 0x2563EB, 0x141318, 0xEA7A0C)

    /** 잉크 색 번호가 없을 때(조커 — 쓰지 않지만 표는 빠짐없이). */
    const val noInk: Int = 0x5A4E7A

    /** 이번 차례에 낸 타일 강조 링. */
    const val highlight: Int = 0xFFD14A

    /** 무효 세트 테두리. */
    const val invalid: Int = 0xFF4D4F

    /** 조커 그림을 못 읽었을 때의 원. */
    const val jokerFallback: Int = 0x7B61FF

    /** 접근성 이름(빨강 7 · 조커). */
    val colorNames: List<String> = listOf("빨강", "파랑", "검정", "주황")

    fun ink(colorIndex: Long?): Int {
        val index = colorIndex?.toInt() ?: return noInk
        return inks.getOrElse(index) { noInk }
    }

    fun accessibilityName(face: RummyFace): String {
        val color = face.color ?: return "조커"
        val number = face.number ?: return "조커"
        return "${colorNames[color.toInt()]} $number"
    }
}

/** 타일 크기(dp). 글자·표식·베벨·모서리는 전부 크기에서 나온다(배율이 바뀌어도 같은 타일로 보이게). */
data class RummyTileSize(val size: RummyCanvasSize) {
    val bevel: Double get() = maxOf(2.0, size.height * 0.075)
    val corner: Double get() = maxOf(3.0, size.width * 0.19)
    val numberFont: Double get() = size.width * 0.6

    /** 색약 표식 — 숫자보다 한참 작게(2판: '작게 유지'). */
    val markSize: Double get() = maxOf(3.5, size.width * 0.17)
    val topPadding: Double get() = maxOf(1.0, size.height * 0.055)
    val stackSpacing: Double get() = maxOf(0.5, size.height * 0.035)

    companion object {
        /** 결과 줄 · 규칙 예시. */
        val table = RummyTileSize(RummyCanvasSize(32.0, 44.0))

        /** 맥 받침대. */
        val rack = RummyTileSize(RummyRackGeometry.standardTile)

        /** 폰 받침대 기준(칸이 좁으면 [RummyRackGeometry.phone] 의 tileSize 를 쓴다). */
        val phoneRack = RummyTileSize(RummyRackGeometry.phoneTile)

        /** 판 캔버스 타일(논리 40×56) × 배율. */
        fun canvas(scale: Double): RummyTileSize =
            RummyTileSize(RummyCanvasSize(RummyTableLayout.tileWidth.toDouble() * scale, RummyTableLayout.tileHeight.toDouble() * scale))
    }
}

// MARK: - 받침대·펠트 그림 판정

/** 그림 두 장(받침대 · 펠트). 사용자가 다시 고를 수 있게 Storage 에서 받아 캐시한다(메모리 assets-users-iterate-must-not-be-baked-in). */
enum class RummyArtKind(val rawValue: String) {
    rack("rack"), table("table");

    /** 공개 버킷 `game-art` 안의 경로. */
    val remotePath: String get() = "rummy/$rawValue.png"

    /** 번들 폴백 사본 이름. */
    val bundleName: String get() = "rummy-$rawValue"
}

/** 조건부 요청 결과 → 할 일. */
enum class RummyArtOutcome {
    /** 새 그림으로 바꾼다(캐시에 쓰고 화면도). */
    replace,

    /** 그대로(304 · 일시 실패 · 못 쓰는 그림). */
    keep,

    /** 서버에서 지워졌다(404) — 캐시를 지우고 번들 사본으로. */
    revert,
}

object RummyArtRules {
    /** 받는 그림 상한(바이트). */
    const val maxBytes: Int = 8 * 1024 * 1024

    /** 펠트 반복 한 칸(dp) — 받은 그림이 1024px 이어도 같은 결로. */
    const val feltTile: Double = 512.0

    /** 받은 그림을 써도 되나 — 받침대는 가로로 긴 판(3.5~7.5:1, 600px 이상), 펠트는 정사각에 가까운 128px 이상. */
    fun isAcceptable(kind: RummyArtKind, width: Int, height: Int): Boolean {
        if (width <= 0 || height <= 0) return false
        val ratio = width.toDouble() / height.toDouble()
        return when (kind) {
            RummyArtKind.rack -> width >= 600 && ratio in 3.5..7.5
            RummyArtKind.table -> width >= 128 && ratio in 0.5..2.0
        }
    }

    /** 응답 판단. [decoded] = 본문을 읽어 낸 그림 크기(못 읽었으면 null). */
    fun outcome(status: Int, byteCount: Int, decoded: Pair<Int, Int>?, kind: RummyArtKind): RummyArtOutcome = when (status) {
        200 -> if (byteCount <= maxBytes && decoded != null && isAcceptable(kind, decoded.first, decoded.second)) RummyArtOutcome.replace else RummyArtOutcome.keep
        404 -> RummyArtOutcome.revert
        else -> RummyArtOutcome.keep
    }

    /** 3-슬라이스 끝캡 폭(px). 그림이 너무 좁아 못 나누면 null. */
    fun rackCapPixels(width: Int, height: Int): Int? {
        if (height <= 0) return null
        val cap = roundedHalfAwayFromZero(RummyRackArtMetrics.capFraction * width).toInt()
        return if (width > cap * 2 + 2) cap else null
    }
}
