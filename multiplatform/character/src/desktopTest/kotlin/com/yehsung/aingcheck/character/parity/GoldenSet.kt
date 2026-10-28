// 원본: Tests/checkTests/AingBakeSuite.swift @ 1b8260d (bakeGoldens · renderGolden — golden.json 의 항목 모양)
// 이 폴더(parity/)는 순수 Kotlin 이다(java.io 없음) — 데스크톱 시험과 Android 기기 시험(T7)이 같은 판정을 쓴다.
package com.yehsung.aingcheck.character.parity

import com.yehsung.aingcheck.character.math.Mat4
import com.yehsung.aingcheck.character.math.Vec2
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.double
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/** 골든 한 장 — 맥 SceneKit 진짜 렌더(280×340, 후광 켬, 파티클 끔)와 그 프레임의 노드 world · Swift 참조 칸. */
data class Golden(
    val index: Int,
    val id: String,
    val file: String,
    /** 마감 폴더 id(`aing` · `aing-gold` · `aing-rainbow`). */
    val finishFolder: String,
    val reaction: String,
    val track: String,
    val sampleIndex: Int,
    val tS: Double,
    val facingDeg: Double,
    val swayPhaseS: Double,
    val eyesClosed: Boolean,
    val wrapper: Mat4,
    val facing: Mat4,
    val character: Mat4,
    val viewYawDeg: Double,
    val viewTiltDeg: Double,
    val referenceCellId: String,
    val referenceAngleDeg: Double,
    val haloCell: Int?,
    val haloQuad: List<Vec2>?,
    val haloSceneKitMaxDiffPx: Double?,
)

class GoldenSet(val viewportWidth: Int, val viewportHeight: Int, val entries: List<Golden>) {
    companion object {
        fun parse(text: String): GoldenSet {
            val root = Json.parseToJsonElement(text).jsonObject
            val vp = root.getValue("viewport").jsonArray
            val entries = root.getValue("entries").jsonArray.mapIndexed { i, e ->
                val o = e.jsonObject
                fun mat(key: String) = Mat4.of(o.getValue("world").jsonObject.getValue(key).jsonArray.map { it.jsonPrimitive.double })
                val halo = o["halo"]?.takeIf { it !is JsonNull }?.jsonObject
                val ref = o.getValue("referenceCell").jsonObject
                val view = o.getValue("view").jsonObject
                Golden(
                    index = i,
                    id = o.getValue("id").jsonPrimitive.content,
                    file = o.getValue("file").jsonPrimitive.content,
                    finishFolder = o.getValue("finish").jsonPrimitive.content,
                    reaction = o.getValue("reaction").jsonPrimitive.content,
                    track = o.getValue("track").jsonPrimitive.content,
                    sampleIndex = o.getValue("sampleIndex").jsonPrimitive.int,
                    tS = o.getValue("tS").jsonPrimitive.double,
                    facingDeg = o.getValue("facingDeg").jsonPrimitive.double,
                    swayPhaseS = o.getValue("swayPhaseS").jsonPrimitive.double,
                    eyesClosed = o.getValue("eyesClosed").jsonPrimitive.boolean,
                    wrapper = mat("wrapper"), facing = mat("facing"), character = mat("character"),
                    viewYawDeg = view.getValue("yawDeg").jsonPrimitive.double,
                    viewTiltDeg = view.getValue("tiltDeg").jsonPrimitive.double,
                    referenceCellId = ref.getValue("id").jsonPrimitive.content,
                    referenceAngleDeg = ref.getValue("angleDeg").jsonPrimitive.double,
                    haloCell = halo?.get("cell")?.jsonPrimitive?.int,
                    haloQuad = halo?.get("quadPx")?.jsonArray?.map { p -> p.jsonArray.let { Vec2(it[0].jsonPrimitive.double, it[1].jsonPrimitive.double) } },
                    haloSceneKitMaxDiffPx = halo?.get("sceneKitQuadMaxDiffPx")?.jsonPrimitive?.double,
                )
            }
            return GoldenSet(vp[0].jsonPrimitive.int, vp[1].jsonPrimitive.int, entries)
        }
    }
}
