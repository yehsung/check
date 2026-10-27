// 원본: Sources/CheckCore/CharacterKit/CharacterManifest.swift @ 1b8260d (+ GoldAing.swift 의 CharacterManifest.Finish — Kotlin 은 중첩 타입을 다른 파일에서 늘릴 수 없어 여기 둔다)
package com.yehsung.aingcheck.core.rules.character

import com.yehsung.aingcheck.core.rules.format.SwiftDecodingError
import com.yehsung.aingcheck.core.rules.format.SwiftValue
import com.yehsung.aingcheck.core.rules.format.parseSwiftJson
import com.yehsung.aingcheck.core.rules.text.Graphemes
import com.yehsung.aingcheck.core.rules.text.TextScalars
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject

/**
 * 캐릭터 한 종의 매니페스트(번들 `Characters/<id>/manifest.json`). **디코드 시점에 전부 검증해 throw** 한다 —
 * 카탈로그는 throw 한 캐릭터만 건너뛴다(C§3.2 B-5 · §8-1: 매니페스트·프레임 시계·카탈로그는 W1-c 한 곳, W5-a 는 import 해서 bake 확장만).
 * 좌표 규약: [Rect] 은 픽셀·좌상단 원점. 매니페스트 파일은 키 변환이 없는 기본 디코더로 읽는다(camelCase 키 그대로).
 */
data class CharacterManifest(
    val id: String,
    val displayName: String,
    val kind: Kind,
    val atlas: Atlas? = null,
    val portrait: Portrait? = null,
    /** 픽셀아트인가(없으면 false — 옛 매니페스트 호환). 켜면 재질 필터 `.nearest`(굽는 쪽과 둘 다 해야 소용 있다). */
    val pixelArt: Boolean? = null,
) {
    enum class Kind(val rawValue: String) {
        /** 아잉처럼 SceneKit 씬을 그대로 쓰는 캐릭터. */
        scene3D("scene3D"),
        /** 아틀라스 평면 한 장으로 서는 2D 캐릭터. */
        sprite("sprite"),
    }

    data class Atlas(val file: String, val width: Long, val height: Long, val states: Map<String, State>)

    data class State(val frames: List<Rect>, val durationsMs: List<Long>, val loop: Boolean)

    /** 아틀라스 안의 한 셀(픽셀·좌상단 원점). */
    data class Rect(val x: Long, val y: Long, val w: Long, val h: Long)

    data class Portrait(val neutral: String, val negative: String)

    /** 상태 키 상수(팩 스크립트와 런타임이 소리 없이 갈리지 않게 한 곳). */
    object StateKey {
        const val frontIdle = "frontIdle"
        const val sideIdle = "sideIdle"
        const val sideWalk = "sideWalk"
    }

    /**
     * 3D 캐릭터의 표면 마감(GoldAing.swift). **id 에서 파생한다**(매니페스트 칸이 아니다).
     * INV-GoldAing-a5e5d18e 이식: [isRare] 는 **열거**로 판정한다 — 케이크는 희귀가 아니다(`!= standard` 로 두면 마감이 늘 때 희귀가 저절로 넓어진다).
     */
    enum class Finish {
        standard,
        gold,
        rainbow,
        /** 딸기 케이크 아잉이(v0.3.66 생일 선물 전용). */
        cakeStrawberry,
        cakeChoco,
        ;

        /** 희귀(뽑기 전용 내장 — 황금 · 무지개). 확률표 강조 · 결과 연출 · 교환 목록 맨 위가 이 값으로 갈린다. */
        val isRare: Boolean
            get() = when (this) {
                gold, rainbow -> true
                standard, cakeStrawberry, cakeChoco -> false
            }

        /** 케이크 마감(딸기 · 초코)인가. */
        val isCake: Boolean
            get() = when (this) {
                cakeStrawberry, cakeChoco -> true
                standard, gold, rainbow -> false
            }

        companion object {
            /** id → 마감. 매니페스트가 없는 자리(뽑기 결과 · 확률표 줄 · 남의 착용 id)도 같은 판정. */
            fun of(characterID: String?): Finish = when {
                CharacterCatalog.isGoldAing(characterID) -> gold
                CharacterCatalog.isRainbowAing(characterID) -> rainbow
                characterID == CharacterCatalog.cakeStrawberryAingID -> cakeStrawberry
                characterID == CharacterCatalog.cakeChocoAingID -> cakeChoco
                else -> standard
            }
        }
    }

    /** 이 캐릭터의 마감(id 에서 파생). */
    val finish: Finish get() = Finish.of(id)

    /** 매니페스트 불변식. 어기면 [CharacterManifestError]. */
    fun validate() {
        if (!isValidID(id)) throw CharacterManifestError.invalidID(id)
        if (TextScalars.trimmingWhitespacesAndNewlines(displayName).isEmpty()) throw CharacterManifestError.emptyDisplayName(id)
        when (kind) {
            Kind.scene3D -> {
                if (atlas != null) throw CharacterManifestError.unexpectedAtlas(id)
                if (portrait != null) throw CharacterManifestError.unexpectedPortrait(id)
            }
            Kind.sprite -> {
                val atlas = atlas ?: throw CharacterManifestError.missingAtlas(id)
                val portrait = portrait ?: throw CharacterManifestError.missingPortrait(id)
                validateAssetFile(atlas.file, id)
                validateAssetFile(portrait.neutral, id)
                validateAssetFile(portrait.negative, id)
                if (atlas.width <= 0 || atlas.height <= 0) throw CharacterManifestError.invalidAtlasSize(id)
                val front = atlas.states[StateKey.frontIdle]
                if (front == null || front.frames.isEmpty()) throw CharacterManifestError.missingRequiredState(id, StateKey.frontIdle)
                // 키 정렬 순서로 — 어떤 오류가 먼저 보고될지 결정적이어야 한다(Swift 도 sorted()).
                for (key in atlas.states.keys.sortedWith(SWIFT_STRING_ORDER)) {
                    validateState(atlas.states.getValue(key), key, id, atlas)
                }
            }
        }
    }

    companion object {
        /** Swift `String <`(유니코드 스칼라 순 — 정준 동치는 NFC 비교). 매니페스트 키는 ASCII 라 코드포인트 순과 같다. */
        private val SWIFT_STRING_ORDER: Comparator<String> = Comparator { a, b -> a.compareTo(b) }

        private fun validateState(state: State, key: String, id: String, atlas: Atlas) {
            if (state.frames.isEmpty()) throw CharacterManifestError.emptyFrames(id, key)
            if (state.frames.size != state.durationsMs.size) {
                throw CharacterManifestError.frameDurationMismatch(id, key, state.frames.size, state.durationsMs.size)
            }
            state.durationsMs.forEachIndexed { index, ms -> if (ms < 0) throw CharacterManifestError.negativeDuration(id, key, index) }
            // 프레임이 둘 이상인데 합이 0ms 면 영원히 첫 프레임에 멈춘다(조용한 오류 — 여기서 잡는다).
            if (state.frames.size > 1 && state.durationsMs.sum() <= 0) throw CharacterManifestError.zeroTotalDuration(id, key)
            state.frames.forEachIndexed { index, r ->
                if (!(r.w > 0 && r.h > 0 && r.x >= 0 && r.y >= 0 && r.x + r.w <= atlas.width && r.y + r.h <= atlas.height)) {
                    throw CharacterManifestError.rectOutsideAtlas(id, key, index)
                }
            }
        }

        /** id 문자 집합: 소문자·숫자·하이픈, **글자(그래핌)** 1~32(Swift `id.count`). */
        fun isValidID(id: String): Boolean {
            val clusters = Graphemes.clusters(id)
            if (clusters.size !in 1..32) return false
            return clusters.all { cluster ->
                cluster.length == 1 && cluster[0].let { it in 'a'..'z' || it in '0'..'9' || it == '-' }
            }
        }

        private fun validateAssetFile(name: String, id: String) {
            if (name.isEmpty() || name.contains('/') || name.contains('\\') || name.startsWith(".")) {
                throw CharacterManifestError.invalidAssetFileName(id, name)
            }
        }

        /**
         * 매니페스트 파일 글자 → 검증된 매니페스트. 실패면 [CharacterManifestError](검증) 또는 [SwiftDecodingError](모양).
         * 합성 Codable 그대로: id · displayName · kind 는 필수, atlas · portrait · pixelArt 는 있으면 모양이 맞아야 한다.
         */
        fun decode(text: String): CharacterManifest = decode(parseSwiftJson(text))

        fun decode(element: JsonElement): CharacterManifest {
            val c = SwiftValue.obj(element)
            fun req(key: String): JsonElement {
                val v = c[key] ?: throw SwiftDecodingError("keyNotFound", "칸 '$key' 가 없다")
                if (v is JsonNull) throw SwiftDecodingError("valueNotFound", "칸 '$key' 가 null")
                return v
            }
            fun opt(key: String): JsonElement? = c[key]?.takeIf { it !is JsonNull }
            val kindRaw = SwiftValue.string(req("kind"))
            val kind = Kind.entries.firstOrNull { it.rawValue == kindRaw }
                ?: throw SwiftDecodingError("dataCorrupted", "모르는 kind '$kindRaw'")
            val manifest = CharacterManifest(
                id = SwiftValue.string(req("id")),
                displayName = SwiftValue.string(req("displayName")),
                kind = kind,
                atlas = opt("atlas")?.let(::decodeAtlas),
                portrait = opt("portrait")?.let(::decodePortrait),
                pixelArt = opt("pixelArt")?.let(SwiftValue::bool),
            )
            manifest.validate()
            return manifest
        }

        private fun field(o: JsonObject, key: String): JsonElement {
            val v = o[key] ?: throw SwiftDecodingError("keyNotFound", "칸 '$key' 가 없다")
            if (v is JsonNull) throw SwiftDecodingError("valueNotFound", "칸 '$key' 가 null")
            return v
        }

        private fun decodeAtlas(element: JsonElement): Atlas {
            val o = SwiftValue.obj(element)
            val states = SwiftValue.obj(field(o, "states")).mapValues { (_, value) -> decodeState(value) }
            return Atlas(SwiftValue.string(field(o, "file")), SwiftValue.int(field(o, "width")), SwiftValue.int(field(o, "height")), states)
        }

        private fun decodeState(element: JsonElement): State {
            val o = SwiftValue.obj(element)
            val frames = SwiftValue.array(field(o, "frames")).map { frame ->
                val r = SwiftValue.obj(frame)
                Rect(SwiftValue.int(field(r, "x")), SwiftValue.int(field(r, "y")), SwiftValue.int(field(r, "w")), SwiftValue.int(field(r, "h")))
            }
            val durations = SwiftValue.array(field(o, "durationsMs")).map(SwiftValue::int)
            return State(frames, durations, SwiftValue.bool(field(o, "loop")))
        }

        private fun decodePortrait(element: JsonElement): Portrait {
            val o = SwiftValue.obj(element)
            return Portrait(SwiftValue.string(field(o, "neutral")), SwiftValue.string(field(o, "negative")))
        }
    }
}

/** 매니페스트 검증 실패 이유(어느 캐릭터의 어느 상태인지까지). 갈래 이름은 Swift 그대로. */
sealed class CharacterManifestError(message: String) : Exception(message) {
    abstract val caseName: String

    class invalidID(val id: String) : CharacterManifestError("id 형식이 아니다: '$id'") { override val caseName = "invalidID" }
    class emptyDisplayName(val id: String) : CharacterManifestError("[$id] displayName 이 비었다") { override val caseName = "emptyDisplayName" }
    class unexpectedAtlas(val id: String) : CharacterManifestError("[$id] scene3D 인데 atlas 가 있다") { override val caseName = "unexpectedAtlas" }
    class unexpectedPortrait(val id: String) : CharacterManifestError("[$id] scene3D 인데 portrait 가 있다") { override val caseName = "unexpectedPortrait" }
    class missingAtlas(val id: String) : CharacterManifestError("[$id] sprite 인데 atlas 가 없다") { override val caseName = "missingAtlas" }
    class missingPortrait(val id: String) : CharacterManifestError("[$id] sprite 인데 portrait 가 없다") { override val caseName = "missingPortrait" }
    class invalidAtlasSize(val id: String) : CharacterManifestError("[$id] atlas 크기가 0 이하다") { override val caseName = "invalidAtlasSize" }
    class invalidAssetFileName(val id: String, val file: String) : CharacterManifestError("[$id] 에셋 파일명이 잘못됐다: '$file'") { override val caseName = "invalidAssetFileName" }
    class missingRequiredState(val id: String, val state: String) : CharacterManifestError("[$id] 필수 상태 '$state' 가 없다") { override val caseName = "missingRequiredState" }
    class emptyFrames(val id: String, val state: String) : CharacterManifestError("[$id/$state] frames 가 비었다") { override val caseName = "emptyFrames" }
    class frameDurationMismatch(val id: String, val state: String, val frames: Int, val durations: Int) :
        CharacterManifestError("[$id/$state] frames($frames) 와 durationsMs($durations) 길이가 다르다") { override val caseName = "frameDurationMismatch" }
    class negativeDuration(val id: String, val state: String, val index: Int) : CharacterManifestError("[$id/$state] durationsMs[$index] 가 음수다") { override val caseName = "negativeDuration" }
    class zeroTotalDuration(val id: String, val state: String) : CharacterManifestError("[$id/$state] 프레임이 여럿인데 총 길이가 0ms 다") { override val caseName = "zeroTotalDuration" }
    class rectOutsideAtlas(val id: String, val state: String, val index: Int) : CharacterManifestError("[$id/$state] frames[$index] 가 아틀라스 밖이다") { override val caseName = "rectOutsideAtlas" }
}
