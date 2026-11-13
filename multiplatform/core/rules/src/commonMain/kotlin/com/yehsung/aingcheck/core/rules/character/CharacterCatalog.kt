// 원본: Sources/CheckCore/CharacterKit/CharacterCatalog.swift @ e4995a3a(이슬 · 빼빼로 · 흑우 · 루비 · 개발 · 지역 아잉이 · 선물 목록)
package com.yehsung.aingcheck.core.rules.character

import com.yehsung.aingcheck.core.wire.character.BuiltInCharacterIds
import com.yehsung.aingcheck.core.wire.character.RegionAingNames

/**
 * 이 빌드가 세울 수 있는 캐릭터 전부. **안전망이 이 타입의 존재 이유다** — 번들이 비어도(또는 전부 깨져도) 아잉이 있고,
 * 파일에서 읽은 캐릭터가 하나 깨지면 **그 하나만 건너뛴다**.
 *
 * 내장 id 상수와 [isGachaOnlyBuiltIn] · [isGiftOnlyBuiltIn] · [giftOnlyBuiltInIDs] 는 와이어(`core.wire.character.BuiltInCharacterIds`, W1-d)가
 * 한 벌로 갖고 여기서는 다시 쓰기만 한다(배정표 round5 36행 — 와이어 `ShopCharacterRow` · `CharacterGiftOffer.choosable` 가 부른다).
 * 값 · 차례는 골든 `gift/catalog` 가 이 겉을 거쳐 와이어 상수까지 잰다.
 */
class CharacterCatalog(entries: List<Entry>) {
    /** 카탈로그 한 칸 — 매니페스트와 그 에셋이 있는 폴더(저장소·번들 상대 경로 글자). 내장 항목은 폴더가 없다. */
    data class Entry(val manifest: CharacterManifest, val directory: String?)

    private val entries: Map<String, Entry>

    init {
        // 아잉(과 내장 열둘)은 항상 들어가고 항상 이긴다 — 번들이 같은 id 를 실어 보내도 덮어쓰지 못한다.
        val map = LinkedHashMap<String, Entry>()
        val builtInIDs = builtIns.map { it.id }.toSet()
        for (entry in entries) if (entry.manifest.id !in builtInIDs) map[entry.manifest.id] = entry
        for (builtIn in builtIns) map[builtIn.id] = Entry(builtIn, null)
        this.entries = map
    }

    fun manifest(id: String): CharacterManifest? = entries[id]?.manifest

    fun entry(id: String): Entry? = entries[id]

    /** 표시 순서: **내장 열둘(내장 순서 그대로) 다음 나머지 id 정렬**. 케이크 둘은 정렬로는 금 앞이라 내장 순서가 아니면 자리가 틀린다. */
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
        const val builtInAingID = BuiltInCharacterIds.builtInAingID

        /** 번들 안 캐릭터 폴더 이름. */
        const val charactersSubdirectory = "Characters"

        val builtInAing = CharacterManifest(id = builtInAingID, displayName = "아잉", kind = CharacterManifest.Kind.scene3D)

        /**
         * 황금 아잉이(v0.3.54)의 고정 id. 서버 CHECK·가격표·`gacha_pool` 의 id 와 같다.
         * INV-CharacterCatalog-ccf7c186 이식: 매니페스트 파일로는 못 싣는다(파일 id 문법 `[a-z0-9-]` 은 밑줄 금지 · scene3D 는 초상을 못 가진다) — 코드에 박는다.
         */
        const val goldAingID = BuiltInCharacterIds.goldAingID
        val builtInGoldAing = CharacterManifest(id = goldAingID, displayName = "황금 아잉이", kind = CharacterManifest.Kind.scene3D)

        /** 무지개 아잉이(v0.3.59). */
        const val rainbowAingID = BuiltInCharacterIds.rainbowAingID
        val builtInRainbowAing = CharacterManifest(id = rainbowAingID, displayName = "무지개 아잉이", kind = CharacterManifest.Kind.scene3D)

        /** 딸기 · 초코 케이크 아잉이(v0.3.66 — 생일 선물 전용: 루비 · 뽑기 · 조각으로 못 얻고 운영자가 지급한 선물에서 골라 받는다). */
        const val cakeStrawberryAingID = BuiltInCharacterIds.cakeStrawberryAingID
        const val cakeChocoAingID = BuiltInCharacterIds.cakeChocoAingID
        val builtInCakeStrawberryAing = CharacterManifest(id = cakeStrawberryAingID, displayName = "딸기 케이크 아잉이", kind = CharacterManifest.Kind.scene3D)
        val builtInCakeChocoAing = CharacterManifest(id = cakeChocoAingID, displayName = "초코 케이크 아잉이", kind = CharacterManifest.Kind.scene3D)

        /**
         * 이슬 아잉이(맥 0.3.74 · Android 판 7 — '술 한잔' 선물 전용: 루비 · 뽑기 · 조각으로 못 얻고 운영자가 지급한 술 선물에서 고를 것 없이 받는다).
         * 서버 CHECK·가격표(`gift_only = true` · `gift_kind = 'drink'`)의 id 와 같다. Android 는 3D 를 그리지 않고 정지 초상을 쓴다(케이크와 같다).
         */
        const val isulAingID = BuiltInCharacterIds.isulAingID
        val builtInIsulAing = CharacterManifest(id = isulAingID, displayName = "이슬 아잉이", kind = CharacterManifest.Kind.scene3D)

        /** 빼빼로 아잉이(맥 0.3.77 · 11-11 빼빼로 데이 기간 선물 전용 — 고를 것 없이 받는다). Android 는 정지 초상(폰 판 — 상자 글자 없음). */
        const val peperoAingID = BuiltInCharacterIds.peperoAingID
        const val peperoAingDisplayName = BuiltInCharacterIds.peperoAingDisplayName
        val builtInPeperoAing = CharacterManifest(id = peperoAingID, displayName = peperoAingDisplayName, kind = CharacterManifest.Kind.scene3D)

        /** 흑우 아잉이(맥 0.3.78 · 조각 20개로만 교환 — 뽑기 확률 0). */
        const val hwooAingID = BuiltInCharacterIds.hwooAingID
        val builtInHwooAing = CharacterManifest(id = hwooAingID, displayName = "흑우 아잉이", kind = CharacterManifest.Kind.scene3D)

        /** 루비 아잉이(맥 0.3.78 · 상점 루비 1000 — 보통 상점 캐릭터, 값은 서버 가격표 행이 정한다). */
        const val rubyAingID = BuiltInCharacterIds.rubyAingID
        val builtInRubyAing = CharacterManifest(id = rubyAingID, displayName = "루비 아잉이", kind = CharacterManifest.Kind.scene3D)

        /** 개발에 찌든 아잉이(맥 0.3.81 · 도전 미션 '누적 근무 100시간' 보상). */
        const val devAingID = BuiltInCharacterIds.devAingID
        val builtInDevAing = CharacterManifest(id = devAingID, displayName = "개발에 찌든 아잉이", kind = CharacterManifest.Kind.scene3D)

        /** 부산 갈매기 · 서울의 밤 아잉이(지역 아잉이 — 센터 선물, 번호 10). Android 는 그림이 없어 번호 10 을 말하지 않는다. */
        const val busanAingID = BuiltInCharacterIds.busanAingID
        const val seoulAingID = BuiltInCharacterIds.seoulAingID
        val builtInBusanAing = CharacterManifest(id = busanAingID, displayName = RegionAingNames.busanDisplayName, kind = CharacterManifest.Kind.scene3D)
        val builtInSeoulAing = CharacterManifest(id = seoulAingID, displayName = RegionAingNames.seoulDisplayName, kind = CharacterManifest.Kind.scene3D)

        /**
         * 내장 항목 전부 — **표시 순서 그대로**(아잉, 황금, 무지개, 딸기, 초코, 이슬, 빼빼로, 흑우, 루비, 개발, 부산, 서울).
         */
        val builtIns: List<CharacterManifest> = listOf(
            builtInAing, builtInGoldAing, builtInRainbowAing, builtInCakeStrawberryAing, builtInCakeChocoAing, builtInIsulAing,
            builtInPeperoAing, builtInHwooAing, builtInRubyAing, builtInDevAing, builtInBusanAing, builtInSeoulAing,
        )

        /** 앞뒤 공백·대소문자를 봐주지 않는다(서버 값은 정확히 그 id 다). */
        fun isGoldAing(id: String?): Boolean = BuiltInCharacterIds.isGoldAing(id)
        fun isRainbowAing(id: String?): Boolean = BuiltInCharacterIds.isRainbowAing(id)

        /** 루비로 **절대** 안 파는 내장(황금 · 무지개 · 흑우) — 서버 표식이 빠져도 뽑기 · 조각으로만 얻는다. */
        fun isGachaOnlyBuiltIn(id: String?): Boolean = BuiltInCharacterIds.isGachaOnlyBuiltIn(id)

        /** 희귀 내장의 표시 순서 — 황금 먼저, 무지개 다음, 흑우 끝. */
        val gachaOnlyBuiltInIDs: List<String> = BuiltInCharacterIds.gachaOnlyBuiltInIDs

        fun isCakeAing(id: String?): Boolean = BuiltInCharacterIds.isCakeAing(id)

        /** 이슬 아잉이인가(정확히 `aing_isul` 만). */
        fun isIsulAing(id: String?): Boolean = BuiltInCharacterIds.isIsulAing(id)

        fun isPeperoAing(id: String?): Boolean = BuiltInCharacterIds.isPeperoAing(id)
        fun isHwooAing(id: String?): Boolean = BuiltInCharacterIds.isHwooAing(id)
        fun isRubyAing(id: String?): Boolean = BuiltInCharacterIds.isRubyAing(id)
        fun isDevAing(id: String?): Boolean = BuiltInCharacterIds.isDevAing(id)
        fun isRegionAing(id: String?): Boolean = BuiltInCharacterIds.isRegionAing(id)

        /** 조각 교환으로만 얻는 내장(흑우) — 뽑기 전용의 부분집합(얻는 길 문구 "조각 N개로 교환"). */
        fun isShardOnlyBuiltIn(id: String?): Boolean = BuiltInCharacterIds.isShardOnlyBuiltIn(id)

        /** 도전 미션 보상으로만 얻는 내장(개발 아잉이). */
        fun isMissionRewardBuiltIn(id: String?): Boolean = BuiltInCharacterIds.isMissionRewardBuiltIn(id)

        /** 조각 교환 전용(흑우 — 번호 7) · 상점(루비 — 번호 8) · 개발(번호 9) 뜻 자리 목록. */
        val shardOnlyBuiltInIDs: List<String> = BuiltInCharacterIds.shardOnlyBuiltInIDs
        val shopBuiltInIDs: List<String> = BuiltInCharacterIds.shopBuiltInIDs
        val devBuiltInIDs: List<String> = BuiltInCharacterIds.devBuiltInIDs

        /**
         * 선물로만 얻는 내장(딸기 · 초코 케이크 · 이슬) — 서버 `gift_only` 표식이 빠져도 루비 · 뽑기 · 조각으로는 못 얻는다.
         * INV-CharacterCatalog-d7d845ac 이식: [isGachaOnlyBuiltIn] 과 **겹치지 않는다**(선물 전용은 뽑기 전용이 아니다 — 뽑기 화면 · 확률표 ·
         * 교환 목록에 서지 않는다). 서버가 선물 행에 `gacha_only = true` 도 싣지만 '뽑기 전용' 판정은 선물 전용을 먼저 본다.
         * ★ '루비로 못 산다 · 잠긴 칸' 뜻으로만 쓴다 — 케이크(생일) 뜻이면 [birthdayGiftBuiltInIDs], 종류별 문구는 `CharacterGiftKind.ofBuiltIn`.
         */
        fun isGiftOnlyBuiltIn(id: String?): Boolean = BuiltInCharacterIds.isGiftOnlyBuiltIn(id)

        /** 생일 선물 내장의 순서 — **딸기 먼저, 초코 다음**(표시 순서 · 선물 선택지 순서가 같다). 상점 번호 4 의 재료다. */
        val birthdayGiftBuiltInIDs: List<String> = BuiltInCharacterIds.birthdayGiftBuiltInIDs

        /** 술 한잔 선물 내장(이슬 하나). 상점 번호 5 의 재료다. */
        val drinkGiftBuiltInIDs: List<String> = BuiltInCharacterIds.drinkGiftBuiltInIDs

        /** 빼빼로 데이 선물 내장(빼빼로 하나). 상점 번호 6 의 재료다. */
        val peperoGiftBuiltInIDs: List<String> = BuiltInCharacterIds.peperoGiftBuiltInIDs

        /** 우리 센터 선물 내장(부산 → 서울). 상점 번호 10 의 재료다(두 센터 그림이 다 있어야). */
        val regionGiftBuiltInIDs: List<String> = BuiltInCharacterIds.regionGiftBuiltInIDs

        /** 선물 전용 내장 **전부**(생일 → 술 → 빼빼로 → 지역, 표시 순서) — '루비로 못 산다 · 잠긴 칸' 뜻으로만. 케이크 뜻 자리에 쓰지 마라(설계서 §2). */
        val giftOnlyBuiltInIDs: List<String> = BuiltInCharacterIds.giftOnlyBuiltInIDs

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
