import Foundation
import os

/// 이 빌드가 세울 수 있는 캐릭터 전부. 번들 `Characters/<id>/manifest.json` 들을 읽어 담는다.
///
/// **안전망이 이 타입의 존재 이유다.** 번들에 캐릭터 폴더가 하나도 없어도(또는 전부 깨져도) 카탈로그에는 늘
/// 아잉이 있고, 앱은 지금과 똑같이 돈다. 그래서 아잉은 매니페스트 파일 없이 코드에 박아 넣고(`builtInAing`),
/// 파일에서 읽은 캐릭터가 하나 깨져도 **그 하나만 건너뛴다**(전체 로드를 실패시키지 않는다).
package struct CharacterCatalog: Sendable {
    /// 아잉의 고정 id. "모르는 캐릭터 → 아잉" 폴백이 전부 이 값을 쓴다.
    package static let builtInAingID = "aing"

    /// 번들 안 캐릭터 폴더 이름. `Package.swift` 의 `.copy("Characters")` 가 구조를 그대로 보존한다
    /// (`.process` 는 하위 폴더를 평탄화해 동명 `atlas.png` 끼리 빌드를 죽인다 — 실측).
    package static let charactersSubdirectory = "Characters"

    /// 코드에 박힌 아잉. 파일이 없어도, 번들이 비어도 이 항목은 사라지지 않는다.
    package static let builtInAing = CharacterManifest(
        id: builtInAingID,
        displayName: "아잉",
        kind: .scene3D
    )

    /// 황금 아잉이(v0.3.54)의 고정 id. 서버 CHECK·가격표·`gacha_pool` 의 id 와 같다.
    ///
    /// ★ **매니페스트 파일로는 못 싣는다**: 파일 매니페스트의 id 문법은 `[a-z0-9-]{1,32}`(밑줄 금지,
    ///   `CharacterManifest.isValidID`)이고 서버 `shop_state` 는 CHECK 를 `[a-z_]+` 로 읽는다 — 두 문법이 다르다.
    ///   그리고 scene3D 매니페스트는 초상을 가질 수 없다. 그래서 아잉처럼 **코드에 박는다**(검증을 안 탄다).
    package static let goldAingID = "aing_gold"

    /// 코드에 박힌 황금 아잉이 — 아잉과 **같은 3D 메시**(aing.scn)에 금빛 마감을 입힌 변형이다.
    /// 렌더러가 "이건 금 아잉이다"를 아는 길은 `CharacterManifest.finish`(또는 `isGoldAing(_:)`) 하나다 —
    /// `kind` 는 아잉과 같은 `.scene3D` 라 kind 로 가르면 금 착용자 화면에 보라 아잉이 선다.
    /// 상점에서는 살 수 없고 뽑기로만 얻는다(서버 `character_prices.gacha_only = true`).
    package static let builtInGoldAing = CharacterManifest(
        id: goldAingID,
        displayName: "황금 아잉이",
        kind: .scene3D
    )

    /// 무지개 아잉이(v0.3.59)의 고정 id. 서버 CHECK·가격표·`gacha_pool` 의 id 와 같다.
    /// 매니페스트 파일로 못 싣는 이유는 금과 같다(밑줄 id · scene3D 는 초상을 못 가진다) — 그래서 코드에 박는다.
    package static let rainbowAingID = "aing_rainbow"

    /// 코드에 박힌 무지개 아잉이 — 아잉과 **같은 3D 메시**에 무지개 마감(`CharacterManifest.Finish.rainbow`)을 입힌 변형이다.
    /// 금처럼 상점에서 살 수 없고 뽑기 · 조각 교환으로만 얻는다(서버 `character_prices.gacha_only = true` · `min_protocol = 3`).
    package static let builtInRainbowAing = CharacterManifest(
        id: rainbowAingID,
        displayName: "무지개 아잉이",
        kind: .scene3D
    )

    /// 딸기 케이크 아잉이(v0.3.66)의 고정 id. 서버 CHECK·가격표(`gift_only = true`)·`character_gifts.options` 의 id 와 같다.
    /// 매니페스트 파일로 못 싣는 이유는 금 · 무지개와 같다(밑줄 id · scene3D 는 초상을 못 가진다) — 그래서 코드에 박는다.
    package static let cakeStrawberryAingID = "aing_cake_strawberry"

    /// 초코 케이크 아잉이(v0.3.66)의 고정 id. 딸기와 같은 규칙.
    package static let cakeChocoAingID = "aing_cake_choco"

    /// 코드에 박힌 딸기 케이크 아잉이 — 아잉과 **같은 3D 메시**에 케이크 마감(`CharacterManifest.Finish.cakeStrawberry`)을 입힌 변형이다.
    /// **생일 선물 전용**이다: 루비로도(서버 `gacha_only = true` 라 `buy_character` 가 `not_for_sale`), 뽑기로도(`gacha_pool` 에 없다),
    /// 조각 교환으로도 못 얻고, 운영자가 지급한 선물(`character_gifts`)에서 받는 사람이 둘 중 하나를 골라 받는다(사용자 결정 2026-10-26).
    package static let builtInCakeStrawberryAing = CharacterManifest(
        id: cakeStrawberryAingID,
        displayName: "딸기 케이크 아잉이",
        kind: .scene3D
    )

    /// 코드에 박힌 초코 케이크 아잉이 — 딸기와 같은 급(생일 선물 전용), 마감만 `.cakeChoco` 다.
    package static let builtInCakeChocoAing = CharacterManifest(
        id: cakeChocoAingID,
        displayName: "초코 케이크 아잉이",
        kind: .scene3D
    )

    /// 이슬 아잉이(v0.3.74 · '술 한잔' 선물 전용)의 고정 id. 서버 CHECK·가격표(`gift_only = true` · `gift_kind = 'drink'`)·
    /// `character_gifts.options` 의 id 와 같다. 매니페스트 파일로 못 싣는 이유는 케이크와 같다(밑줄 id · scene3D 는 초상을 못 가진다).
    package static let isulAingID = "aing_isul"

    /// 코드에 박힌 이슬 아잉이 — 아잉과 **같은 3D 메시**에 이슬 마감(`CharacterManifest.Finish.isul` — 초록 유리 몸 · 라벨 · 병뚜껑)을 입힌 변형이다.
    /// **'술 한잔' 선물 전용**이다(사용자 결정 2026-11-03 "선물 전용 (케이크처럼)" + "술한잔 하자고 초대보내는느낌으로 같이 선물할거야"):
    /// 루비로도 · 뽑기로도 · 조각 교환으로도 못 얻고, 운영자가 지급한 술 선물(`character_gifts.kind = 'drink'`)에서 고를 것 없이 받는다.
    package static let builtInIsulAing = CharacterManifest(
        id: isulAingID,
        displayName: "이슬 아잉이",
        kind: .scene3D
    )

    /// 빼빼로 아잉이(v0.3.77 · 빼빼로 데이 11-11 기간 선물 전용)의 고정 id. 서버 CHECK·가격표(`gift_only = true` · `gift_kind = 'pepero'`)·
    /// `character_gifts.options` 의 id 와 같다. 매니페스트 파일로 못 싣는 이유는 케이크 · 이슬과 같다(밑줄 id · scene3D 는 초상을 못 가진다).
    package static let peperoAingID = "aing_pepero"

    /// 빼빼로 아잉이의 **표시 이름 — 한 곳**. '빼빼로'는 남의 상표라 이름이 바뀔 수 있다(가안 2026-11-04). 카탈로그 이름 · 받는 창 본문
    /// (`PeperoGiftText.body`)이 이 값을 읽는다. 바꾸면 여기 하나와 `PeperoGiftText` 의 행사 이름 글자만 고친다.
    package static let peperoAingDisplayName = "빼빼로 아잉이"

    /// 코드에 박힌 빼빼로 아잉이 — 아잉과 **같은 3D 메시**에 빼빼로 마감(`CharacterManifest.Finish.pepero`)을 입힐 변형이다.
    /// **빼빼로 데이 기간 선물 전용**이다(사용자 결정 2026-11-04 "11-11 기간 선물 (이슬처럼)"): 루비로도 · 뽑기로도 · 조각 교환으로도 못 얻고,
    /// 운영자가 11-11 에 지급한 빼빼로 선물(`character_gifts.kind = 'pepero'`)에서 고를 것 없이 받는다(안 받은 선물은 며칠 뒤 서버가 거둔다).
    /// ★ 그림(3D 마감 · 초상)은 시안을 고르는 중이다 — 그림이 붙기 전엔 맥 · 폰 어느 쪽도 "그릴 수 있다"고 말하지 않는다
    ///   (`ShopWire.peperoProtocol` 6 을 안 보낸다 → 서버가 빼빼로 행 · 선물을 안 싣는다).
    package static let builtInPeperoAing = CharacterManifest(
        id: peperoAingID,
        displayName: peperoAingDisplayName,
        kind: .scene3D
    )

    /// 흑우 아잉이(v0.3.78 · **조각 20개로만** 바꾸는 캐릭터)의 고정 id. 서버 CHECK·가격표(`gacha_only = true` · `min_protocol = 7`)·
    /// `gacha_pool`(확률 **0** · 조각 20 · sort 0 — 추첨에 안 나온다)의 id 와 같다. 매니페스트 파일로 못 싣는 이유는 금 · 무지개와 같다.
    /// 대표 결정(2026-11-06): 제보 "뽑기말고 조각으로만 교환할 수 있는 흑우 아잉이" → "흑우 아잉이 좋음" · 조각 "20개 (황금·무지개와 같게)" ·
    /// 그림 "U9 네온"(짙은 남색 몸 + 왼쪽 하늘색 · 오른쪽 분홍 네온 테). 이름은 대표가 정한 그대로다(디자인에는 이름을 반영하지 않는다).
    package static let hwooAingID = "aing_hwoo"

    /// 코드에 박힌 흑우 아잉이 — 아잉과 **같은 3D 메시**에 네온 마감(`CharacterManifest.Finish.hwoo`)을 입힌 변형이다.
    /// 루비로도(서버 `gacha_only` → `not_for_sale`) · 뽑기로도(확률 0) 못 얻고 **조각 교환으로만** 얻는다.
    package static let builtInHwooAing = CharacterManifest(
        id: hwooAingID,
        displayName: "흑우 아잉이",
        kind: .scene3D
    )

    /// 코드에 박힌 항목 전부 — **표시 순서 그대로**(아잉, 황금 아잉이, 무지개 아잉이, 딸기 케이크 아잉이, 초코 케이크 아잉이, 이슬 아잉이,
    /// 빼빼로 아잉이, 흑우 아잉이). 번들이 비어도 이 여덟은 늘 있다.
    package static let builtIns: [CharacterManifest] = [
        builtInAing, builtInGoldAing, builtInRainbowAing, builtInCakeStrawberryAing, builtInCakeChocoAing, builtInIsulAing,
        builtInPeperoAing, builtInHwooAing,
    ]

    /// 이 id 가 황금 아잉이인가. 앞뒤 공백·대소문자를 봐주지 않는다(서버 값은 정확히 `aing_gold` 다).
    package static func isGoldAing(_ id: String?) -> Bool {
        id == goldAingID
    }

    /// 이 id 가 무지개 아잉이인가. 금과 같은 규칙(정확히 `aing_rainbow` 만).
    package static func isRainbowAing(_ id: String?) -> Bool {
        id == rainbowAingID
    }

    /// 루비로 **절대** 안 파는 내장 캐릭터(황금 · 무지개)인가 — 서버 `gacha_only` 표식이 빠지거나 false 로 와도 뽑기 · 조각으로만 얻는다
    /// (사용자 결정: 황금 2026-10-15 · 무지개 2026-10-20 "황금처럼 뽑기 전용"). 상점 구매 가능 · 확률표 상점가 칸 · 고르기 잠긴 카드의
    /// 안내가 전부 이 한 곳을 묻는다 — 새 희귀 캐릭터는 여기 하나만 더하면 된다.
    package static func isGachaOnlyBuiltIn(_ id: String?) -> Bool {
        isGoldAing(id) || isRainbowAing(id) || isHwooAing(id)
    }

    /// 이 id 가 흑우 아잉이인가. 금과 같은 규칙(정확히 `aing_hwoo` 만 — 공백 · 대소문자를 봐주지 않는다).
    package static func isHwooAing(_ id: String?) -> Bool {
        id == hwooAingID
    }

    /// **조각 교환으로만** 얻는 내장 캐릭터(흑우 아잉이 — v0.3.78)인가. 뽑기 전용(`isGachaOnlyBuiltIn` — 루비로 안 판다)의 부분집합이고,
    /// 화면의 얻는 길 문구가 "뽑기 또는 조각 N개"가 아니라 "조각 N개로 교환"이 된다(뽑기에는 안 나온다 — 서버 확률 0).
    package static func isShardOnlyBuiltIn(_ id: String?) -> Bool {
        isHwooAing(id)
    }

    /// 조각 교환 전용 내장 캐릭터 — 흑우 하나(v0.3.78). '흑우' 뜻 자리(능력 번호 7)는 이 목록이다.
    package static let shardOnlyBuiltInIDs: [String] = [hwooAingID]

    /// 희귀 내장 캐릭터의 표시 순서(교환 목록 맨 위 · 확률표가 순서를 안 줄 때) — 황금 먼저, 무지개 다음.
    package static let gachaOnlyBuiltInIDs: [String] = [goldAingID, rainbowAingID, hwooAingID]

    /// 이 id 가 케이크 아잉이(딸기 · 초코)인가. 금과 같은 규칙(정확히 그 두 id 만 — 공백 · 대소문자를 봐주지 않는다).
    package static func isCakeAing(_ id: String?) -> Bool {
        id == cakeStrawberryAingID || id == cakeChocoAingID
    }

    /// 이 id 가 이슬 아잉이인가. 금과 같은 규칙(정확히 `aing_isul` 만 — 공백 · 대소문자를 봐주지 않는다).
    package static func isIsulAing(_ id: String?) -> Bool {
        id == isulAingID
    }

    /// 이 id 가 빼빼로 아잉이인가. 금과 같은 규칙(정확히 `aing_pepero` 만 — 공백 · 대소문자를 봐주지 않는다).
    package static func isPeperoAing(_ id: String?) -> Bool {
        id == peperoAingID
    }

    /// **선물로만** 얻는 내장 캐릭터(생일 — 딸기 · 초코 케이크 아잉이, 술 한잔 — 이슬 아잉이, 빼빼로 데이 — 빼빼로 아잉이)인가 — 서버 `gift_only`
    /// 표식이 빠지거나 false 로 와도 루비 · 뽑기 · 조각으로는 못 얻는다(사용자 결정 2026-10-26 "뽑기로도 못뽑는걸로" · 2026-11-03 "선물 전용
    /// (케이크처럼)" · 2026-11-04 "11-11 기간 선물 (이슬처럼)").
    /// 상점 구매 가능(`ShopCharacterRow.isPurchasable`) · 잠긴 칸 · 조각 교환 금지 · 고르기의 '가진 사람만'이 이 한 곳을 묻는다.
    ///
    /// ★ (v0.3.74) 이 판정은 **'선물 전용 전부'** 뜻으로만 쓴다. '케이크(생일)' 뜻 — 생일 선물 선택지 · 능력 번호 4 · 케이크 순서 — 은
    ///   `birthdayGiftBuiltInIDs` 를, 종류별 문구는 `CharacterGiftKind(builtInID:)` 를 묻는다. 이슬을 케이크 뜻 자리에 섞으면
    ///   이슬 초상이 없는 빌드(폰 1.0.16 이하)가 능력 번호 3 으로 떨어져 케이크까지 잃는다(설계서 §2). 빼빼로(v0.3.77)도 같다 — 케이크 뜻 · 술 뜻 자리에
    ///   섞으면 빼빼로 그림이 없는 빌드(맥 0.3.76 이하 · 폰 전부)가 번호를 잃는다. 빼빼로 뜻 자리는 `peperoGiftBuiltInIDs` 다.
    ///
    /// ★ `isGachaOnlyBuiltIn` 과 **겹치지 않는다**(케이크는 뽑기 전용이 아니다 — 뽑기 화면 · 확률표 · 교환 목록에 서지 않는다).
    ///   서버는 not_for_sale 갈래를 타게 하려고 케이크 행에 `gacha_only = true` 도 싣지만, 클라의 '뽑기 전용' 판정은 그 표식을
    ///   `gift_only` 보다 뒤에 본다(화면이 "뽑기나 조각 교환으로 얻을 수 있어요"라고 거짓말하지 않게).
    package static func isGiftOnlyBuiltIn(_ id: String?) -> Bool {
        isCakeAing(id) || isIsulAing(id) || isPeperoAing(id)
    }

    /// 생일 선물 내장 캐릭터의 순서 — **딸기 먼저, 초코 다음**(표시 순서 · 생일 선물 선택지의 순서가 같다). '케이크' 뜻 자리는 이 목록이다.
    package static let birthdayGiftBuiltInIDs: [String] = [cakeStrawberryAingID, cakeChocoAingID]

    /// '술 한잔' 선물 내장 캐릭터 — 이슬 하나(v0.3.74). 술 선물의 선택지는 이 목록뿐이다.
    package static let drinkGiftBuiltInIDs: [String] = [isulAingID]

    /// 빼빼로 데이 선물 내장 캐릭터 — 빼빼로 아잉이 하나(v0.3.77). 빼빼로 선물의 선택지는 이 목록뿐이다. '빼빼로' 뜻 자리(능력 번호 6 ·
    /// 빼빼로 선물 선택지)는 이 목록이다.
    package static let peperoGiftBuiltInIDs: [String] = [peperoAingID]

    /// 선물 전용 내장 캐릭터 **전부**(생일 → 술 → 빼빼로, 표시 순서) — '루비로 못 산다 · 잠긴 칸' 뜻으로만 쓴다(`isGiftOnlyBuiltIn` 과 같은 집합).
    /// ★ 케이크 뜻(생일 선물 선택지 · `ShopWire.cakeCharacterIDs`)에 쓰지 마라 — `birthdayGiftBuiltInIDs` 다. 술 뜻 · 빼빼로 뜻도 각자 목록이다.
    package static let giftOnlyBuiltInIDs: [String] = birthdayGiftBuiltInIDs + drinkGiftBuiltInIDs + peperoGiftBuiltInIDs

    /// 이 내장 캐릭터를 주는 선물 종류(케이크 → 생일 · 이슬 → 술 한잔 · 빼빼로 → 빼빼로 데이). 선물 전용 내장이 아니면 nil.
    /// 잠긴 칸 · 잠긴 카드의 안내처럼 **종류마다 말이 다른** 자리가 이 한 곳을 묻는다(`CharacterGiftKind.copy`).
    package static func giftKind(ofBuiltIn id: String?) -> CharacterGiftKind? {
        CharacterGiftKind(builtInID: id)
    }

    /// 카탈로그 한 칸 — 매니페스트와 그 에셋이 있는 폴더. 내장 아잉은 폴더가 없다(씬 파일은 종전 경로).
    package struct Entry: Sendable, Equatable {
        package let manifest: CharacterManifest
        package let directory: URL?
    }

    private let entries: [String: Entry]

    /// 주어진 항목들로 카탈로그를 만든다. **아잉은 항상 들어가고 항상 이긴다** —
    /// 번들이 `aing` 매니페스트를 실어 보내도 3D 아잉을 덮어쓰지 못하게 한다(폴백 대상이 스프라이트가 되면
    /// "모르는 값 → 아잉" 안전망 자체가 스프라이트 파이프라인에 의존하게 된다).
    /// 황금 아잉이(v0.3.54)·무지개 아잉이(v0.3.59)·케이크 아잉이 둘(v0.3.66)도 같은 규칙이다 — 내장 항목이 늘 이긴다.
    package init(entries: [Entry]) {
        var map: [String: Entry] = [:]
        let builtInIDs = Set(Self.builtIns.map(\.id))
        for entry in entries where !builtInIDs.contains(entry.manifest.id) {
            map[entry.manifest.id] = entry
        }
        for builtIn in Self.builtIns {
            map[builtIn.id] = Entry(manifest: builtIn, directory: nil)
        }
        self.entries = map
    }

    /// 폴더 없는 매니페스트만으로 만드는 편의 생성자(테스트·메모리 카탈로그).
    package init(manifests: [CharacterManifest]) {
        self.init(entries: manifests.map { Entry(manifest: $0, directory: nil) })
    }

    package func manifest(id: String) -> CharacterManifest? {
        entries[id]?.manifest
    }

    package func entry(id: String) -> Entry? {
        entries[id]
    }

    /// 표시 순서: **아잉 먼저, 황금 아잉이 둘째, 무지개 아잉이 셋째, 딸기 · 초코 케이크 아잉이 넷째 · 다섯째, 나머지는 id 정렬**.
    /// 목록이 실행마다 흔들리지 않게 정렬을 여기 한 곳에 둔다.
    /// (`aing_gold`·`aing_rainbow` 는 정렬로도 그 자리지만 — `_` 는 소문자보다 앞이다 — 그 우연에 기대지 않고 내장 순서로 박는다.
    ///  케이크 둘은 정렬로는 금보다 **앞**(`aing_cake_*` < `aing_gold`)이라 내장 순서가 아니면 자리가 틀린다.)
    package var allIDs: [String] {
        let builtInIDs = Self.builtIns.map(\.id)
        return builtInIDs + entries.keys.filter { !builtInIDs.contains($0) }.sorted()
    }

    /// 아틀라스 PNG 의 절대 URL. 내장 아잉·3D 캐릭터는 nil.
    package func atlasURL(for id: String) -> URL? {
        guard let entry = entries[id], let directory = entry.directory,
              let file = entry.manifest.atlas?.file else { return nil }
        return directory.appendingPathComponent(file)
    }


    // MARK: - 로드

    private static let logger = Logger(subsystem: "kingcheck", category: "character")


    /// 디렉터리 하나를 훑어 카탈로그를 만든다(테스트가 임시 폴더를 그대로 넣는다).
    ///
    /// 규칙: 하위 폴더 이름 = 캐릭터 id. 폴더 이름과 매니페스트의 `id` 가 다르면 **건너뛴다** —
    /// 에셋은 폴더 이름으로 찾고 선택 값은 `id` 로 저장되므로, 둘이 갈리면 "목록엔 있는데 그림이 없는" 캐릭터가 된다.
    package static func load(charactersDirectory: URL?, fileManager: FileManager = .default) -> CharacterCatalog {
        guard let root = charactersDirectory else { return CharacterCatalog(entries: []) }
        let decoder = JSONDecoder()
        var loaded: [Entry] = []
        let names = (try? fileManager.contentsOfDirectory(atPath: root.path))?.sorted() ?? []
        for name in names {
            let directory = root.appendingPathComponent(name, isDirectory: true)
            guard isDirectory(directory, fileManager: fileManager) else { continue }
            let manifestURL = directory.appendingPathComponent("manifest.json")
            guard fileManager.fileExists(atPath: manifestURL.path) else { continue }
            do {
                let manifest = try decoder.decode(CharacterManifest.self, from: Data(contentsOf: manifestURL))
                guard manifest.id == name else {
                    logger.error("character manifest id mismatch folder=\(name, privacy: .public) id=\(manifest.id, privacy: .public)")
                    continue
                }
                loaded.append(Entry(manifest: manifest, directory: directory))
            } catch {
                // 한 캐릭터가 깨져도 나머지는 산다. 사용자에게는 "그 캐릭터만 목록에 없다"로 보인다.
                logger.error("character manifest unreadable folder=\(name, privacy: .public) error=\(String(describing: error), privacy: .public)")
            }
        }
        return CharacterCatalog(entries: loaded)
    }

    /// 번들 안 캐릭터 폴더 URL. `.copy` 리소스라 `url(forResource:)` 로 잡히지만, 못 잡으면 리소스 루트에서 직접 찾는다.
    package static func directoryURL(
        in bundle: Bundle,
        named subdirectory: String = charactersSubdirectory,
        fileManager: FileManager = .default
    ) -> URL? {
        if let url = bundle.url(forResource: subdirectory, withExtension: nil),
           isDirectory(url, fileManager: fileManager) {
            return url
        }
        if let url = bundle.resourceURL?.appendingPathComponent(subdirectory, isDirectory: true),
           isDirectory(url, fileManager: fileManager) {
            return url
        }
        return nil
    }

    private static func isDirectory(_ url: URL, fileManager: FileManager) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
    }
}
