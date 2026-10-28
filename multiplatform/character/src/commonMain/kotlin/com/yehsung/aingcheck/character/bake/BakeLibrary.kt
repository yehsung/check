// 원본: Sources/check/CheckOverlayWindow.swift @ 1b8260d (울트라 접기 :1797-1799 — 모르는 캐릭터 · 그릴 수 없는 마감은 아잉으로) + 설계 F §7 "모르는 id 는 아잉으로 · 모르는 굽기 판은 legacy 로"
package com.yehsung.aingcheck.character.bake

import com.yehsung.aingcheck.character.pose.CellSelector
import com.yehsung.aingcheck.core.rules.character.CharacterCatalog

/**
 * 구운 자산 읽기 입구. 경로는 굽기 뿌리(`multiplatform/assets/aing-bake/`) 기준 상대 경로(`aing-gold/S-rest-0.webp`).
 * 앱은 Compose 리소스 · Android 자산에서, 시험은 저장소 파일에서 읽는다. 없는 파일은 null(묶음마다 싣는 파일이 다르다 —
 * Android 기본 묶음은 L 단 · 트랙 2개만, G §8-12).
 */
interface BakeFiles {
    fun read(path: String): ByteArray?

    /** 후광 원본 PNG(`Sources/check/Resources` 의 파일 이름 그대로 — Gradle Sync, git 사본 0). */
    fun readHalo(fileName: String): ByteArray?
}

/** 마감 하나(아잉 · 황금 · 무지개) — 폴더 = 파일 id(`aing-gold`), 서버 id 는 [characterId](`aing_gold`). */
class BakedFinish(val folder: String, val manifest: BakedManifest, private val files: BakeFiles) {
    val bake: BakeExtension = manifest.bake ?: throw BakeFormatException("$folder: bake 가 없다(${manifest.bakeRejected})")
    val characterId: String get() = bake.characterId

    private val cellsByTier = HashMap<String, BakeCells?>()
    private val selectors = HashMap<Pair<String, Boolean>, CellSelector?>()

    /** 이 묶음에 실린 단만(파일이 없으면 null). */
    fun cells(tier: String): BakeCells? = cellsByTier.getOrPut(tier) {
        val t = bake.tier(tier) ?: return@getOrPut null
        files.read("$folder/${t.cellsFile}")?.decodeToString()?.let(BakeCells::decode)
    }

    /** 칸 고르기. 감은 눈이면 패치가 있는 칸만(골든 referenceSelection 과 같은 규칙). */
    fun selector(tier: String, closedEyes: Boolean): CellSelector? = selectors.getOrPut(tier to closedEyes) {
        val all = cells(tier)?.cells ?: return@getOrPut null
        val pool = if (closedEyes) all.filter { it.closedPatch != null } else all
        if (pool.isEmpty()) null else CellSelector(pool)
    }

    /** 실린 단 이름(S · L · U 중 셀 파일이 있는 것). */
    fun availableTiers(): List<BakeTier> = bake.tiers.filter { cells(it.name) != null }

    fun pagePath(page: Int): String = "$folder/${bake.pages[page]}"
}

/**
 * 구운 아잉이 전부(아잉 · 황금 · 무지개) + 공용 카메라 · 모션. **굽지 않은 캐릭터는 아잉으로 접는다**(§8-17 #7 — 케이크 둘은 굽지 않았다).
 */
class BakeLibrary private constructor(
    val files: BakeFiles,
    val camera: SceneCamera,
    val motion: MotionLibrary,
    private val finishes: Map<String, BakedFinish>,
    /** `bake` 를 못 읽었지만(모르는 큰 판 · 모양 틀림) 기존 형식은 산 마감 — legacy 2칸 스프라이트로 내려간다(F §7). 서버 id → 매니페스트. */
    private val legacyOnly: Map<String, BakedManifest>,
    /** 읽다가 버린 폴더와 이유(진단). */
    val rejected: Map<String, String>,
) {
    private val tracks = HashMap<String, MotionTrack?>()

    /** 서버 id → 구운 마감. 없으면 null. */
    fun finish(characterId: String): BakedFinish? = finishes[characterId]

    val bakedIds: Set<String> get() = finishes.keys

    /** 구운 칸은 못 쓰지만 legacy 2칸(`legacy.webp`, 직선 알파)으로는 설 수 있는 마감. */
    fun legacyOnly(characterId: String): BakedManifest? = legacyOnly[characterId]

    /** legacy 아틀라스 경로(마감 폴더 기준). */
    fun legacyAtlasPath(characterId: String): String? {
        val folder = FOLDER_IDS.entries.firstOrNull { it.value == characterId }?.key ?: return null
        val m = finishes[characterId]?.manifest ?: legacyOnly[characterId] ?: return null
        return "$folder/${m.legacy.atlas?.file ?: return null}"
    }

    /**
     * 착용 id → 그릴 마감. 구운 마감이 있으면 그것, 아니면 **아잉**(케이크 · 모르는 id · 빈 값). 아잉마저 없으면 null(초상으로 내려간다).
     * 스프라이트 캐릭터(fox 등)는 호출부가 먼저 스프라이트로 고른다 — 이 함수는 3D 계열 접기만 한다.
     */
    fun resolve(characterId: String?): BakedFinish? = characterId?.let { finishes[it] } ?: finishes[CharacterCatalog.builtInAingID]

    /** 트랙 바이트(없으면 null — 묶음에 안 실렸다). */
    fun track(name: String): MotionTrack? = tracks.getOrPut(name) {
        val info = motion.tracks[name] ?: return@getOrPut null
        val bytes = files.read(info.file) ?: return@getOrPut null
        MotionTrack.fromBytes(name, info.variant, info.sampleHz, info.positionUnits, bytes, info.holdsEnd).also {
            if (it.count != info.count) throw BakeFormatException("트랙 $name: 표본 ${it.count} ≠ 메타 ${info.count}")
        }
    }

    companion object {
        /**
         * 구운 마감 폴더(파일 id) → 서버 id. 순서는 내장 순서(아잉 · 황금 · 무지개). 파일 id 문법은 밑줄 금지라 둘이 다르다(F §3.5).
         * 케이크 둘은 없다 — 굽지 않았다(§8-17 #7).
         */
        val FOLDER_IDS: Map<String, String> = linkedMapOf(
            "aing" to CharacterCatalog.builtInAingID,
            "aing-gold" to CharacterCatalog.goldAingID,
            "aing-rainbow" to CharacterCatalog.rainbowAingID,
        )
        val FOLDERS: List<String> = FOLDER_IDS.keys.toList()

        fun load(files: BakeFiles, folders: List<String> = FOLDERS): BakeLibrary {
            val camera = SceneCamera.decode(files.read("camera.json")?.decodeToString() ?: throw BakeFormatException("camera.json 이 없다"))
            val motion = MotionLibrary.decode(files.read("motion.json")?.decodeToString() ?: throw BakeFormatException("motion.json 이 없다"))
            val finishes = LinkedHashMap<String, BakedFinish>()
            val legacy = LinkedHashMap<String, BakedManifest>()
            val rejected = LinkedHashMap<String, String>()
            for (folder in folders) {
                val text = files.read("$folder/manifest.json")?.decodeToString()
                if (text == null) { rejected[folder] = "manifest.json 이 없다"; continue }
                val manifest = try {
                    BakedManifest.decode(text)
                } catch (e: Exception) {
                    if (e is kotlin.coroutines.cancellation.CancellationException) throw e
                    rejected[folder] = "매니페스트 검증 실패: ${e.message}"; continue
                }
                if (manifest.legacy.id != folder) { rejected[folder] = "폴더 이름 ≠ id(${manifest.legacy.id})"; continue }
                val serverId = FOLDER_IDS[folder]
                if (manifest.bake == null) {
                    rejected[folder] = manifest.bakeRejected ?: "bake 없음"
                    if (serverId != null) legacy[serverId] = manifest
                    continue
                }
                if (serverId != null && manifest.bake.characterId != serverId) {
                    rejected[folder] = "bake.characterId ${manifest.bake.characterId} ≠ $serverId"; continue
                }
                val f = BakedFinish(folder, manifest, files)
                finishes[f.characterId] = f
            }
            return BakeLibrary(files, camera, motion, finishes, legacy, rejected)
        }
    }
}
