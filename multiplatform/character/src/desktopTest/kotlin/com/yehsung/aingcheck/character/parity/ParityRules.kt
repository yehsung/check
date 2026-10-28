// 원본: 없음 (설계 F §6 T3 무리 · 문턱 · 음성 대조 — 골든 쪽 사실로 가르는 규칙. 데스크톱 T3 와 Android T7 이 같은 규칙을 쓴다)
package com.yehsung.aingcheck.character.parity

import com.yehsung.aingcheck.character.bake.BakeCell
import com.yehsung.aingcheck.character.render.ImageDiff
import com.yehsung.aingcheck.character.render.ParityBand
import com.yehsung.aingcheck.character.render.RgbaImage
import kotlin.math.abs
import kotlin.math.max

/**
 * 골든 한 장의 판정 갈래 — **전부 골든 쪽 사실로 정한다**(재생기 출력으로 정하면 결함이 스스로를 면제한다).
 *  - [clean]: F §6 문턱(IoU > 127 · 합집합 평균)을 그대로 통과해야 한다.
 *  - [particles]: 골든에 입자가 남아 있다(golden.json 은 "particles: off" 인데 굽기 `removeTransientNodes` 가 방출구 노드만 걷고
 *    SceneKit 이 살려 둔 입자는 남는다 — W0-d 굽기 결함, 조정자 패치로 다시 굽는다). 증거: 불투명(α > 200) 덩어리가 둘 이상,
 *    또는 표준 마감(라벤더 몸)에 채도 높은 노랑(스파크)이 100픽셀 이상. 픽셀 판정에서 뺀다.
 *  - [haloLag]: 골든의 후광이 맥 순수 함수보다 2px 넘게 어긋났다(golden.json `sceneKitQuadMaxDiffPx` — SceneKit 제약이 이징 액션 중
 *    옛 부모 사슬을 본다, `GoldAingFinish.swift` ⚠ 알려진 한계). 후광을 맞대지 않고 **몸 영역**(우리 몸 그림 α > 0) 평균만 문턱 안이어야 한다.
 *  - [gridCoarse]: 울트라 찔림 표본 288(z 34° · x 12° · 크기 1.14/0.88 · 기울기 28°, 옆 띠 4° × 띠 행 3° 격자) — 이 격자로는 문턱을
 *    못 맞춘다(굽기 F-9 보고: "속도별 허용 각은 지금 격자로는 못 맞춘다"). 넘는 것을 잠그고(나아지면 빨강), 몸 영역 평균 ≤ 문턱 × 2 로 퇴행만 막는다.
 */
enum class GoldenClass { clean, particles, haloLag, gridCoarse }

object ParityRules {
    const val HALO_LAG_PX = 2.0
    const val YELLOW_EVIDENCE_PX = 100
    /** 음성 대조: 틀린 칸(요 격자 두 칸 옆)의 몸 영역 오차가 맞는 칸의 이 배 이상이어야 한다. */
    const val NEGATIVE_MIN_RATIO = 1.25

    /** 크기가 이만큼 넘게 1 에서 벗어나면 몸이 변형된 장(찌부 · 늘림)이다 — 강체(F §6: idle · 살랑 · 깜빡임 · 졸기 · 절 · 인사 · 롤)는 크기가 1 이다. */
    const val DEFORMED_SCALE = 0.02

    /**
     * T3 무리(F §6 표): 고른 칸의 무리로 가른다 — 스핀 행 → 스핀(10° × 4°), 몸이 변형된 장(hit · 크기 편차 > 2%) → 찌부 · 늘림,
     * 띠 행(3° 기울기 · 2/4° 요) → 띠 행 · 울트라, 쉬는 행(1°) → 강체.
     */
    fun band(g: Golden, cell: BakeCell): ParityBand {
        if (cell.group == BakeCell.Group.spin) return ParityBand.spin
        val scaleDev = (0 until 3).maxOf { abs(g.wrapper.column(it).length - 1.0) }
        if (g.reaction == "hit" || scaleDev > DEFORMED_SCALE) return ParityBand.squashStretch
        return when (cell.group) {
            BakeCell.Group.band, BakeCell.Group.ultra -> ParityBand.bandUltra
            else -> ParityBand.rigid
        }
    }

    fun classify(g: Golden, golden: RgbaImage): GoldenClass = when {
        particleEvidence(g, golden) -> GoldenClass.particles
        g.reaction == "ultraPoked" && g.sampleIndex == 288 -> GoldenClass.gridCoarse
        (g.haloSceneKitMaxDiffPx ?: 0.0) > HALO_LAG_PX -> GoldenClass.haloLag
        else -> GoldenClass.clean
    }

    fun particleEvidence(g: Golden, golden: RgbaImage): Boolean =
        opaqueBlobs(golden) >= 2 || (g.finishFolder == "aing" && saturatedYellow(golden) >= YELLOW_EVIDENCE_PX)

    /** α > 200 인 4-연결 덩어리 수. 몸(+ 후광 심)은 한 덩어리다. */
    fun opaqueBlobs(img: RgbaImage, threshold: Int = 200): Int {
        val w = img.width; val h = img.height
        val seen = BooleanArray(w * h)
        val stack = IntArray(w * h)
        var n = 0
        for (s in 0 until w * h) {
            if (seen[s] || (img.px[s * 4 + 3].toInt() and 0xFF) <= threshold) continue
            n++
            var top = 0
            stack[top++] = s; seen[s] = true
            while (top > 0) {
                val j = stack[--top]; val x = j % w; val y = j / w
                fun push(k: Int) { if (!seen[k] && (img.px[k * 4 + 3].toInt() and 0xFF) > threshold) { seen[k] = true; stack[top++] = k } }
                if (x > 0) push(j - 1); if (x < w - 1) push(j + 1); if (y > 0) push(j - w); if (y < h - 1) push(j + w)
            }
        }
        return n
    }

    /** 채도 높은 노랑(스파크 1, 0.8, 0) 픽셀 수 — 라벤더 몸 · 분홍 볼 · 검은 눈에는 없다. */
    fun saturatedYellow(img: RgbaImage): Int {
        var n = 0
        for (i in 0 until img.width * img.height) {
            val a = img.px[i * 4 + 3].toInt() and 0xFF
            if (a == 0) continue
            val r = img.px[i * 4].toInt() and 0xFF; val g = img.px[i * 4 + 1].toInt() and 0xFF; val b = img.px[i * 4 + 2].toInt() and 0xFF
            if (r > 150 && g > 110 && b < g / 2) n++
        }
        return n
    }

    /** 몸 영역 평균: [mask](우리 몸만 그린 그림)의 α > 0 픽셀에서 RGBA 평균 절대차. 후광 빛이 합집합을 묽히지 않는다. */
    fun bodyRegionMean(ours: RgbaImage, golden: RgbaImage, mask: RgbaImage): Double {
        var s = 0L; var n = 0
        for (i in 0 until ours.width * ours.height) {
            if ((mask.px[i * 4 + 3].toInt() and 0xFF) == 0) continue
            n++
            for (c in 0 until 4) s += abs((ours.px[i * 4 + c].toInt() and 0xFF) - (golden.px[i * 4 + c].toInt() and 0xFF))
        }
        return s.toDouble() / max(1, n * 4)
    }

    /** 한 장의 판정 결과. */
    data class Verdict(
        val golden: Golden,
        val cls: GoldenClass,
        val band: ParityBand,
        val cellId: String,
        val composite: ImageDiff,
        val bodyMean: Double,
        val wrongCellId: String,
        val wrongComposite: ImageDiff,
        val wrongBodyMean: Double,
    ) {
        val compositePasses: Boolean get() = band.passes(composite)
        val wrongExceedsThreshold: Boolean get() = !band.passes(wrongComposite) || wrongBodyMean > band.maxMean
        val negativeRatio: Double get() = wrongBodyMean / max(bodyMean, 1e-9)

        /** 이 장이 지켜야 할 것(갈래별). 빈 글이면 통과. */
        fun problems(): List<String> {
            val out = ArrayList<String>()
            when (cls) {
                GoldenClass.particles -> return out
                GoldenClass.clean -> if (!compositePasses) out += "문턱 밖 ${band.name}: IoU ${"%.4f".format(composite.iou)} · 평균 ${"%.2f".format(composite.mean)}"
                GoldenClass.haloLag -> if (bodyMean > band.maxMean) out += "후광 지연 장의 몸 영역 평균 ${"%.2f".format(bodyMean)} > ${band.maxMean}"
                GoldenClass.gridCoarse -> {
                    if (compositePasses) out += "격자 거칠음으로 잠근 장이 문턱을 통과한다 — 잠금을 풀어라"
                    if (bodyMean > 2 * band.maxMean) out += "격자 거칠음 장 퇴행: 몸 영역 평균 ${"%.2f".format(bodyMean)} > ${2 * band.maxMean}"
                }
            }
            if (negativeRatio < NEGATIVE_MIN_RATIO) out += "음성 대조 실패: 틀린 칸 $wrongCellId 몸 영역 ${"%.2f".format(wrongBodyMean)} / 맞는 칸 ${"%.2f".format(bodyMean)} = ${"%.2f".format(negativeRatio)}"
            return out
        }
    }
}
