// 원본: Sources/CheckCore/RummyTableEdit.swift:1 @ 1a5eeca6
package com.yehsung.aingcheck.core.rules.rummy

import com.yehsung.aingcheck.core.wire.games.RummyFace
import com.yehsung.aingcheck.core.wire.games.RummyPoint
import kotlin.math.abs

// 아잉 큐브 3판(K3) — 판 편집 **손맛 규칙**.
//
// 여기 규칙은 전부 화면 편집 규칙이다 — 판정과 무관하다(확정은 여전히 서버 R-16, 클라 짝은 [RummyRules.judgeTurn] 이
// 면만 보고 한다). 그래도 남의 작업 판·확정 판을 저마다 그리므로 **결정적**이어야 한다: 정수만, 동점은 번호·쪽 순서로 끊는다. 골든 `rummy/table-edit`.
// 편집기([RummyTurnEditor.moveBlock] · [RummyTurnEditor.moveSet])가 부르고, 화면은 [RummyTurnEditor.previewDrop] 으로 놓기 전에 묻는다.
//
// ① 가운데 빼면 양쪽 유지([RummyTableEdit.split]): 묶음에서 타일을 빼면 남은 타일이 **이어진 토막마다** 따로 묶음이 된다. 토막의 점 =
//    원래 점 + 토막 첫 장의 원래 자리 × 타일폭 — 남은 타일은 화면에서 한 칸도 안 움직인다. 끝에서 빼면 짧아질 뿐이고
//    (왼끝을 빼면 점이 그만큼 오른쪽으로 — 역시 안 움직인다), 다 빼면 묶음이 사라진다. 그룹도 같은 규칙.
// ② 가까이 놓으면 붙기([RummyTableEdit.attachment]): 놓은 묶음의 한 끝이 다른 묶음의 반대 끝과 가로 |간격| ≤ attachGap(타일폭 0.6)
//    · 세로 차 ≤ attachRise(타일높이 0.5)이고, 이어 붙인 모양이 [isChainable](같은 색 연속 · 같은 수 다른 색,
//    조커 와일드, 길이 무관)이면 그 끝에 합친다. 합친 묶음은 **원래 있던 쪽(붙는 대상)이 제자리**([RummyTableEdit.attachedPoint]).
//    여럿이면 |간격| → 세로 차 → 묶음 번호 → 오른끝 먼저. 간격이 음수(살짝 겹침)도 같은 거리로 본다.
//    묶음 위에 꽂아(③) 자란 묶음도 **자란 쪽 끝만** 같은 규칙으로 본다 — 가운데를 메우면 양쪽 토막이 다시 하나가 되고,
//    자동 배치로 곁에(여백 16) 있던 이웃과는 안 합친다. 빈 곳 놓기·묶음 옮기기도 **블록 끝마다 한 번만** 붙는다. 첫 등록 전(R-12)엔
//    시작 판 타일이 든 묶음과는 붙지 않는다(붙으면 initial_table_touched 로 낼 수 없는 판이 저절로 된다).
// ③ 알맞은 자리에 자동 삽입([RummyTableEdit.insertionIndex]): 묶음 위에 놓으면 결과가 유효(R-04~R-06) > 이어질 수 있는 모양이 되는
//    자리에 넣는다. 그룹 모양(숫자 타일이 한 숫자)이면 **R-09 표시 순서 자리**(색 A→D, 조커 뒤), 런은 그런 자리 중 놓은 자리에 가장
//    가까운 곳(같으면 오른쪽). 맞는 자리가 없으면 놓은 자리 그대로(무효 표시는 판정 몫).
//    그리고 블록을 받은 묶음이 **맞는 세트가 되면 R-09 표시 순서로 늘어놓는다**(편집기 몫). 기존 타일이 가장 많이 제자리인 쪽으로 민다.
//    빼고 남은 토막도 맞는 세트면 표시 순서로(이웃은 안 건드린다 — 막히면 사각형 제자리에서 순서만).
// ④ 늘어난 묶음 앉히기([RummyTableEdit.settle], 편집기 전용): 그 자리가 막히면 늘어난 장수만큼 안에서 옆으로(왼쪽 먼저) 밀고,
//    그래도 막히면 만지던 묶음은 제자리에 두고 막은 이웃을 가장 가까운 빈자리로 비켜 놓는다.
// ⑤ 길게 눌러 집기([RummyTableEdit.pickRange]): 판 묶음 타일을 길게 누르면 누른 타일에서 **가까운 끝까지**.

/** 붙는 쪽. 대상 묶음 기준이다. */
enum class RummyAttachSide(val rawValue: String) {
    /** 대상 왼끝 앞에(블록 + 대상). */
    left("left"),

    /** 대상 오른끝 뒤에(대상 + 블록). */
    right("right"),
}

/** ② 붙을 곳 — 대상 묶음 번호(넘겨준 sets 기준)와 쪽. */
data class RummyAttachment(val set: Int, val side: RummyAttachSide)

/** ① 남은 토막 하나 — 원래 묶음 안 자리 구간과 그 토막의 왼쪽 위 점. Swift `Range<Int>` 는 `from until to` 다. */
data class RummySplitPiece(val range: IntRange, val point: RummyPoint)

/** ③ 꽂을 자리 — [fits] 가 거짓이면 맞는 자리가 없어 놓은 자리 그대로다. */
data class RummyInsertion(val index: Int, val fits: Boolean)

/** 놓기 계획(놓기 전에 화면이 미리 그릴 것). 묶음 번호는 **옮기기 전 화면** 번호다(쪼개진 토막이면 그 원래 묶음). */
sealed interface RummyDropPlan {
    /** 받침대로. */
    data object Rack : RummyDropPlan

    /** 묶음 [set] 의 [side] 끝에 붙는다(규칙 ②). */
    data class Attach(val set: Int, val side: RummyAttachSide) : RummyDropPlan

    /** 묶음 [set] 위에 놓아 [index] 자리에 꽂힌다(규칙 ③). [index] = 끌린 타일을 뺀 그 묶음에서 블록 첫 장의 자리. */
    data class Insert(val set: Int, val index: Int) : RummyDropPlan

    /** 새 묶음 — 놓일 왼쪽 위 점(스냅 뒤). 묶음 통째 옮기기([RummyTurnEditor.moveSet])가 안 붙으면 이것. */
    data class NewSet(val point: RummyPoint) : RummyDropPlan
}

/** [RummyTurnEditor.previewDrop] · [RummyTurnEditor.previewMoveSet] 의 답: 계획 + 놓은 뒤 블록이 든 묶음(받침대행이면 null). */
data class RummyDropPreview(val plan: RummyDropPlan, val landing: Landing?) {
    data class Landing(
        /** 놓은 **뒤** 판에서의 묶음 번호. */
        val set: Int,
        /** 놓은 뒤 그 묶음의 면(화면 순). */
        val faces: List<RummyFace>,
        /** 놓은 뒤 그 묶음의 판 사각형(미리보기 윤곽). */
        val frame: RummyRect,
        /** 그 묶음 안 블록 첫 장의 자리. */
        val blockStart: Int,
        /** 그 묶음이 그대로 유효한 세트인가(R-04~R-06). */
        val valid: Boolean,
    )
}

object RummyTableEdit {
    /** ② 붙기 가로 거리(단위) = 타일폭 0.6. */
    const val attachGap: Long = RummyTableLayout.tileWidth * 3 / 5

    /** ② 붙기 세로 중심 차(단위) = 타일높이 0.5. */
    const val attachRise: Long = RummyTableLayout.tileHeight / 2

    /** ① [count] 장 묶음(점 [point])에서 [removing] 자리를 빼고 남는 이어진 토막들(왼쪽부터). 남는 게 없으면 빈 목록. */
    fun split(count: Int, point: RummyPoint, removing: Set<Int>): List<RummySplitPiece> {
        val pieces = ArrayList<RummySplitPiece>()
        var start: Int? = null
        for (index in 0..count) {
            val kept = index < count && index !in removing
            if (kept && start == null) start = index
            val from = start
            if (!kept && from != null) {
                pieces.add(RummySplitPiece(from until index, RummyPoint(point.x + from * RummyTableLayout.tileWidth, point.y)))
                start = null
            }
        }
        return pieces
    }

    /** 동점 끊기 열쇠: |간격| → 세로 차 → 묶음 번호 → 오른끝 먼저. */
    private class AttachKey(val gap: Long, val rise: Long, val index: Int, val sideRank: Int) {
        fun isBefore(other: AttachKey): Boolean = when {
            gap != other.gap -> gap < other.gap
            rise != other.rise -> rise < other.rise
            index != other.index -> index < other.index
            else -> sideRank < other.sideRank
        }
    }

    /**
     * ② 사각형 [frame] 에 놓인 블록(면 [block])이 묶음들([sets] · [frames], 같은 길이) 중 어느 끝에 붙는가. 없으면 null.
     * [sides] = 볼 쪽(대상 기준). 묶음 위에 꽂아 한쪽으로 자란 묶음은 자란 쪽만 본다(편집기 몫 — 원래 곁에 있던 이웃과는 안 합친다).
     */
    fun attachment(
        block: List<RummyFace>,
        frame: RummyRect,
        sets: List<List<RummyFace>>,
        frames: List<RummyRect>,
        sides: List<RummyAttachSide> = listOf(RummyAttachSide.right, RummyAttachSide.left),
    ): RummyAttachment? {
        if (block.isEmpty()) return null
        var bestKey: AttachKey? = null
        var bestHit: RummyAttachment? = null
        for (index in sets.indices) {
            if (index >= frames.size || sets[index].isEmpty()) continue
            val other = frames[index]
            val rise = abs(frame.y - other.y)
            if (rise > attachRise) continue
            for (side in listOf(RummyAttachSide.right, RummyAttachSide.left)) {
                if (side !in sides) continue
                val gap = if (side == RummyAttachSide.right) frame.x - other.maxX else other.x - frame.maxX
                if (abs(gap) > attachGap) continue
                val joined = if (side == RummyAttachSide.right) sets[index] + block else block + sets[index]
                if (!RummyRules.isChainable(joined)) continue
                val key = AttachKey(abs(gap), rise, index, if (side == RummyAttachSide.right) 0 else 1)
                val current = bestKey
                if (current != null && !key.isBefore(current)) continue
                bestKey = key
                bestHit = RummyAttachment(index, side)
            }
        }
        return bestHit
    }

    /** ② 합친 묶음의 점 — 대상(점 [target])이 제자리다. 왼쪽에 붙으면 블록 장수만큼 왼쪽으로 늘어난다. */
    fun attachedPoint(target: RummyPoint, side: RummyAttachSide, blockCount: Int): RummyPoint = when (side) {
        RummyAttachSide.right -> target
        RummyAttachSide.left -> RummyPoint(target.x - blockCount * RummyTableLayout.tileWidth, target.y)
    }

    /** ③ 블록([block], 넘긴 순서 그대로 한 덩어리)을 묶음 [meld] 의 어디에 꽂을까. [preferred] = 놓은 자리(0…장수로 자른다). */
    fun insertionIndex(block: List<RummyFace>, meld: List<RummyFace>, preferred: Int): RummyInsertion {
        val wantedSlot = minOf(maxOf(preferred, 0), meld.size)
        var bestTier: Int? = null
        var fits = ArrayList<Int>()
        for (index in 0..meld.size) {
            val result = meld.subList(0, index) + block + meld.subList(index, meld.size)
            // analyze 는 순서를 안 본다(판정은 다중집합) — 자리는 순서를 보는 isChainable 이 가른다.
            if (!RummyRules.isChainable(result)) continue
            val tier = if (RummyRules.analyze(result).valid) 0 else 1
            val currentTier = bestTier
            if (currentTier == null || tier < currentTier) {
                bestTier = tier
                fits = arrayListOf(index)
            } else if (tier == currentTier) {
                fits.add(index)
            }
        }
        if (fits.isEmpty()) return RummyInsertion(wantedSlot, false)
        val numbers = (meld + block).mapNotNull { it.number }.toSet()
        // 그룹 모양: R-09 표시 순서 자리(블록 첫 장보다 뒤에 올 첫 타일 앞 — 색 A→D, 조커 맨 뒤). 놓은 자리는 안 본다.
        val wanted = if (numbers.size == 1) {
            meld.indexOfFirst { RummyFaceOrder.compare(block[0], it) < 0 }.takeIf { it >= 0 } ?: meld.size
        } else {
            wantedSlot
        }
        // 놓은 자리에 가장 가까운 곳, 같으면 오른쪽.
        val best = fits.minWith { a, b ->
            val da = abs(a - wanted)
            val db = abs(b - wanted)
            if (da != db) da.compareTo(db) else b.compareTo(a)
        }
        return RummyInsertion(best, true)
    }

    /**
     * ⑤ [count] 장 묶음에서 [pressed] 번째 타일을 길게 눌러 집을 구간 — 누른 타일에서 **가까운 끝까지**.
     *  · 오른쪽 절반(타일 가운데가 묶음 가운데보다 오른쪽) → 그 타일부터 끝까지.
     *  · 왼쪽 절반 → 처음부터 그 타일까지.
     *  · 정확히 가운데(홀수 장의 가운데 타일) → 묶음 전체(두 끝이 같은 거리 — 어느 쪽도 고를 까닭이 없다).
     * 끝 타일을 누르면 그 한 장이다(한 장 끌기와 같다). 묶음 통째는 손잡이가 맡는다. 반 칸 단위 정수 비교라 경계가 흔들리지 않는다.
     */
    fun pickRange(count: Int, pressed: Int): IntRange {
        if (count <= 0 || pressed !in 0 until count) return 0 until 0
        val center = 2 * pressed + 1 // 누른 타일 가운데 × 2 (묶음 가운데 × 2 = count)
        return when {
            center > count -> pressed until count
            center < count -> 0 until pressed + 1
            else -> 0 until count
        }
    }

    /**
     * ④ 늘어난 묶음 [index] 를 판에 앉힌 뒤 모든 묶음의 점. `frames[index]` = 바라는 자리(남은 타일 제자리), [grown] = 이번에
     * 늘어난 장수(옆으로 밀 수 있는 거리 = 그 장수 × 타일폭 — 민 뒤에도 원래 타일 자리를 덮어 묶음이 멀리 튀지 않는다).
     *  1. 판 안이고 안 겹치면 그대로.
     *  2. 1 단위씩 넓혀 가며 옆으로 — 같은 거리면 **왼쪽 먼저**(오른쪽이 막혀 왼쪽으로 늘어나는 것).
     *  3. 그래도 막히면 만지던 묶음은 제자리(판 밖으로 나가면 안으로만 당긴다)에 두고, 그와 겹치는 이웃을 번호 순으로 저마다
     *     가장 가까운 빈자리([RummyTableLayout.freeSpot] — 최소 거리)로 비켜 놓는다. 빈자리가 없는 이웃은 그대로(판이 꽉 찼다).
     * 정수만 · 순서 고정이라 결정적이다. 편집기 전용([RummyTableLayout.place] 계약과 무관) — 결과는 작업 배치로 나간다.
     */
    fun settle(frames: List<RummyRect>, index: Int, grown: Int): List<RummyPoint> {
        val points = frames.map { it.origin }.toMutableList()
        if (index !in frames.indices) return points
        fun frame(j: Int) = RummyRect(points[j].x, points[j].y, frames[j].width, frames[j].height)
        fun others(skip: Int): List<RummyRect> = frames.indices.filter { it != skip }.map { frame(it) }
        val mine = frames[index]
        val obstacles = others(index)
        if (RummyTableLayout.isClear(mine, obstacles)) return points
        val reach = maxOf(grown, 0) * RummyTableLayout.tileWidth
        if (reach > 0) {
            for (step in 1L..reach) {
                for (x in listOf(mine.x - step, mine.x + step)) {
                    val moved = RummyRect(x, mine.y, mine.width, mine.height)
                    if (RummyTableLayout.isClear(moved, obstacles)) {
                        points[index] = moved.origin
                        return points
                    }
                }
            }
        }
        val tiles = (mine.width / RummyTableLayout.tileWidth).toInt()
        points[index] = RummyTableLayout.clampInside(mine.origin, tiles)
        val placed = frame(index)
        for (j in frames.indices) {
            if (j == index || !RummyTableLayout.overlaps(frame(j), placed)) continue
            val spot = RummyTableLayout.freeSpot(points[j], (frames[j].width / RummyTableLayout.tileWidth).toInt(), others(j))
            if (spot != null) points[j] = spot
        }
        return points
    }
}
