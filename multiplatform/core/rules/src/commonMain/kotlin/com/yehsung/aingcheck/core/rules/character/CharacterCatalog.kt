// 원본: Sources/CheckCore/CharacterKit/CharacterCatalog.swift @ 1b8260d
package com.yehsung.aingcheck.core.rules.character

/**
 * 이 빌드가 세울 수 있는 캐릭터 전부. **안전망이 이 타입의 존재 이유다** — 번들이 비어도(또는 전부 깨져도) 아잉이 있고,
 * 파일에서 읽은 캐릭터가 하나 깨지면 **그 하나만 건너뛴다**.
 *
 * 의존 방향 메모(배정표 round5 · W1-d 와 맞출 것): 와이어(`ShopCharacterRow.isPurchasable/isGiftOnly` · `CharacterGiftOffer.choosable`)가
 * 아래 내장 id 상수와 [isGachaOnlyBuiltIn] · [isGiftOnlyBuiltIn] · [giftOnlyBuiltInIDs] 를 부른다. rules 는 wire 에 기대고 거꾸로는 안 되므로
 * 병합 때 이 상수·판정을 core/wire(`BuiltInCharacterIds`)로 옮기고 여기서는 다시 쓰기만 한다(값은 골든 `gift/catalog` 가 잠근다).
 */
class CharacterCatalog(entries: List<Entry>) {
    /** 카탈로그 한 칸 — 매니페스트와 그 에셋이 있는 폴더(저장소·번들 상대 경로 글자). 내장 항목은 폴더가 없다. */
    data class Entry(val manifest: CharacterManifest, val directory: String?)

    private val entries: Map<String, Entry>

    init {
        // 아잉(과 내장 다섯)은 항상 들어가고 항상 이긴다 — 번들이 같은 id 를 실어 보내도 덮어쓰지 못한다.
        val map = LinkedHashMap<String, Entry>()
        val builtInIDs = builtIns.map { it.id }.toSet()
        for (entry in entries) if (entry.manifest.id !in builtInIDs) map[entry.manifest.id] = entry
        for (builtIn in builtIns) map[builtIn.id] = Entry(builtIn, null)
        this.entries = map
    }

    fun manifest(id: String): CharacterManifest? = entries[id]?.manifest

    fun entry(id: String): Entry? = entries[id]

    /** 표시 순서: **내장 다섯(내장 순서 그대로) 다음 나머지 id 정렬**. 케이크 둘은 정렬로는 금 앞이라 내장 순서가 아니면 자리가 틀린다. */
    val allIDs: List<String>
        get() {
            val builtInIDs = builtIns.map { it.id }
            return builtInIDs + entries.keys.filter { it !in builtInIDs }.sorted()
        }

    /** 아틀라스 파일 경로(폴더 + 파일 이름). 내장 · 3D 캐릭터는 null. */
    fun atlasPath(id: String): String? {
        val entry = entries[id] ?: return null
        val directory = entry.directory ?: return null
        val file = entry.manifest.atlas?.file ?: return null
        return "$directory/$file"
    }

    companion object {
        /** 아잉의 고정 id — "모르는 캐릭터 → 아잉" 폴백이 전부 이 값을 쓴다. */
        const val builtInAingID = "aing"

        /** 번들 안 캐릭터 폴더 이름. */
        const val charactersSubdirectory = "Characters"

        val builtInAing = CharacterManifest(id = builtInAingID, displayName = "아잉", kind = CharacterManifest.Kind.scene3D)

        /**
         * 황금 아잉이(v0.3.54)의 고정 id. 서버 CHECK·가격표·`gacha_pool` 의 id 와 같다.
         * INV-CharacterCatalog-ccf7c186 이식: 매니페스트 파일로는 못 싣는다(파일 id 문법 `[a-z0-9-]` 은 밑줄 금지 · scene3D 는 초상을 못 가진다) — 코드에 박는다.
         */
        const val goldAingID = "aing_gold"
        val builtInGoldAing = CharacterManifest(id = goldAingID, displayName = "황금 아잉이", kind = CharacterManifest.Kind.scene3D)

        /** 무지개 아잉이(v0.3.59). */
        const val rainbowAingID = "aing_rainbow"
        val builtInRainbowAing = CharacterManifest(id = rainbowAingID, displayName = "무지개 아잉이", kind = CharacterManifest.Kind.scene3D)

        /** 딸기 · 초코 케이크 아잉이(v0.3.66 — 생일 선물 전용: 루비 · 뽑기 · 조각으로 못 얻고 운영자가 지급한 선물에서 골라 받는다). */
        const val cakeStrawberryAingID = "aing_cake_strawberry"
        const val cakeChocoAingID = "aing_cake_choco"
        val builtInCakeStrawberryAing = CharacterManifest(id = cakeStrawberryAingID, displayName = "딸기 케이크 아잉이", kind = CharacterManifest.Kind.scene3D)
        val builtInCakeChocoAing = CharacterManifest(id = cakeChocoAingID, displayName = "초코 케이크 아잉이", kind = CharacterManifest.Kind.scene3D)

        /** 내장 항목 전부 — **표시 순서 그대로**(아잉, 황금, 무지개, 딸기, 초코). */
        val builtIns: List<CharacterManifest> = listOf(
            builtInAing, builtInGoldAing, builtInRainbowAing, builtInCakeStrawberryAing, builtInCakeChocoAing,
        )

        /** 앞뒤 공백·대소문자를 봐주지 않는다(서버 값은 정확히 그 id 다). */
        fun isGoldAing(id: String?): Boolean = id == goldAingID
        fun isRainbowAing(id: String?): Boolean = id == rainbowAingID

        /** 루비로 **절대** 안 파는 내장(황금 · 무지개) — 서버 표식이 빠져도 뽑기 · 조각으로만 얻는다. */
        fun isGachaOnlyBuiltIn(id: String?): Boolean = isGoldAing(id) || isRainbowAing(id)

        /** 희귀 내장의 표시 순서 — 황금 먼저, 무지개 다음. */
        val gachaOnlyBuiltInIDs: List<String> = listOf(goldAingID, rainbowAingID)

        fun isCakeAing(id: String?): Boolean = id == cakeStrawberryAingID || id == cakeChocoAingID

        /**
         * 생일 선물로만 얻는 내장(딸기 · 초코 케이크) — 서버 `gift_only` 표식이 빠져도 루비 · 뽑기 · 조각으로는 못 얻는다.
         * INV-CharacterCatalog-d7d845ac 이식: [isGachaOnlyBuiltIn] 과 **겹치지 않는다**(케이크는 뽑기 전용이 아니다 — 뽑기 화면 · 확률표 ·
         * 교환 목록에 서지 않는다). 서버가 케이크 행에 `gacha_only = true` 도 싣지만 '뽑기 전용' 판정은 선물 전용을 먼저 본다.
         */
        fun isGiftOnlyBuiltIn(id: String?): Boolean = isCakeAing(id)

        /** 생일 선물 내장의 순서 — **딸기 먼저, 초코 다음**(표시 순서 · 선물 선택지 순서가 같다). */
        val giftOnlyBuiltInIDs: List<String> = listOf(cakeStrawberryAingID, cakeChocoAingID)

        /** 폴더 없는 매니페스트만으로 만드는 편의 생성자(시험·메모리 카탈로그). */
        fun of(manifests: List<CharacterManifest>): CharacterCatalog = CharacterCatalog(manifests.map { Entry(it, null) })

        /**
         * 폴더 이름 → manifest.json 글자 목록으로 카탈로그를 만든다(파일 읽기는 플랫폼 몫 — 이 함수는 규칙만).
         * 규칙: 폴더 이름 = 캐릭터 id 여야 한다(다르면 건너뛴다). 깨진 매니페스트는 그 하나만 건너뛴다. 폴더 이름 순서로 본다.
         */
        fun load(manifestsByFolder: List<Pair<String, String>>, directoryOf: (String) -> String = { "$charactersSubdirectory/$it" }): CharacterCatalog {
            val loaded = ArrayList<Entry>()
            for ((name, text) in manifestsByFolder.sortedBy { it.first }) {
                val manifest = try {
                    CharacterManifest.decode(text)
                } catch (e: Exception) {
                    if (e is kotlin.coroutines.cancellation.CancellationException) throw e
                    continue
                }
                if (manifest.id != name) continue
                loaded += Entry(manifest, directoryOf(name))
            }
            return CharacterCatalog(loaded)
        }
    }
}
