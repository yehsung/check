// 원본: 없음(W1-c 골든 생성기 · 선물 · 뽑기 · 상점 번호 · 캐릭터 키트 · 미션 — Sources/CheckCore/{CharacterGift,Gacha,ShopProtocol,Achievements,DailyMissions}.swift · CharacterKit/* 를 잰다)
import CheckGoldenSupport
import Foundation
import Testing
@testable import CheckCore

// W1-c 앱 규칙 — 캐릭터 · 상점 · 뽑기 · 선물 · 미션 골든(C§5.1 E9 · K9 · G §8-7 · G §8-16 새 앱 규칙). Kotlin 은 core/rules/…/{character,gacha,achievements}.
//
//   · gift/catalog          내장 다섯(아잉 · 금 · 무지개 · 딸기 · 초코 — 표시 순서는 내장 순서) · id 판정(희귀 · 케이크 · 선물 전용 · 교환 불가) ·
//                           마감(Finish — isRare 는 열거, 케이크는 희귀 아님) · 카탈로그 allIDs · 금·무지개 그림 이름과 "그릴 수 있다"
//   · gift/claim            CharacterGiftClaimOutcome(status → 결과 · settlesGift) · CakeGiftText(문구 · 목적격 조사 · notice)
//   · gacha/shop-protocol   K9 상점 능력 번호: 그릴 수 있는 id 집합 → 번호(누적 — 0..4) · 문턱 둘 · 플랫폼별 그림 집합 → 번호(G §8-7 ③)
//   · gacha/odds            E9: GachaInfo 디코드(관대) · 합 · 완전성 · 표시 % · 뽑기·교환 가능 · 확률표·교환 줄 · 응답 → 결과 · 문구
//   · gacha/character-kit   매니페스트 검증(번들 실물 + 깨진 변형) · 프레임 시계 · 착용 동기화 판정
//   · missions/achievements 도전 미션 + 일일 미션(v0.3.64 daily) 디코드 · 계열 줄 · 받을 것 · 합치기(받음은 되돌아가지 않는다 — 일일은 같은 kst_day 만)
// 입력 JSON 은 골든에 글자 그대로 싣는다(데모 픽스처 원문 포함) — Kotlin 은 같은 바이트를 디코드한다.

@Suite("GoldenExport app-rules — 캐릭터 · 상점 · 뽑기 · 선물 · 미션")
struct GoldenExportAppRulesCharacter {
    // MARK: 공용

    static func n(_ value: Int?) -> GoldenJSON {
        guard let value else { return .null }
        if value >= -GoldenJSON.maxSafeInteger && value <= GoldenJSON.maxSafeInteger { return .int(value) }
        return .string("int:\(value)")
    }

    static func b(_ value: Bool?) -> GoldenJSON { value.map(GoldenJSON.bool) ?? .null }
    static func s(_ value: String?) -> GoldenJSON { value.map(GoldenJSON.string) ?? .null }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase   // SupabaseWorkService.swift:89 와 같다
        return decoder
    }

    static func fixture(_ path: String) -> String {
        (try? String(contentsOf: GoldenRepo.url(path), encoding: .utf8)) ?? ""
    }

    static let knownIDs: [String?] = [
        "aing", "aing_gold", "aing_rainbow", "aing_cake_strawberry", "aing_cake_choco", "robot", "fox", "", " aing_gold",
        "AING_GOLD", "aing_cake", "aing_cake_strawberry ", nil,
    ]

    // MARK: gift/catalog

    static func finishName(_ finish: CharacterManifest.Finish) -> String {
        switch finish {
        case .standard: return "standard"
        case .gold: return "gold"
        case .rainbow: return "rainbow"
        case .cakeStrawberry: return "cakeStrawberry"
        case .cakeChoco: return "cakeChoco"
        }
    }

    @Test("gift/catalog — 내장 다섯 · id 판정 · 마감 · allIDs · 금·무지개 그림 이름과 그릴 수 있다")
    func giftCatalog() {
        var cases: [GoldenJSON] = []
        cases.append([
            "id": "builtins",
            "builtIns": .array(CharacterCatalog.builtIns.map { manifest in
                ["id": .string(manifest.id), "displayName": .string(manifest.displayName), "kind": .string(manifest.kind.rawValue),
                 "finish": .string(Self.finishName(manifest.finish))]
            }),
            "builtInAingID": .string(CharacterCatalog.builtInAingID),
            "goldAingID": .string(CharacterCatalog.goldAingID),
            "rainbowAingID": .string(CharacterCatalog.rainbowAingID),
            "cakeStrawberryAingID": .string(CharacterCatalog.cakeStrawberryAingID),
            "cakeChocoAingID": .string(CharacterCatalog.cakeChocoAingID),
            "gachaOnlyBuiltInIDs": .array(CharacterCatalog.gachaOnlyBuiltInIDs.map(GoldenJSON.string)),
            "giftOnlyBuiltInIDs": .array(CharacterCatalog.giftOnlyBuiltInIDs.map(GoldenJSON.string)),
            "charactersSubdirectory": .string(CharacterCatalog.charactersSubdirectory),
        ])
        for (index, id) in Self.knownIDs.enumerated() {
            let finish = CharacterManifest.Finish(characterID: id)
            cases.append([
                "id": .string("id-\(index)"),
                "characterID": Self.s(id),
                "isGoldAing": .bool(CharacterCatalog.isGoldAing(id)),
                "isRainbowAing": .bool(CharacterCatalog.isRainbowAing(id)),
                "isGachaOnlyBuiltIn": .bool(CharacterCatalog.isGachaOnlyBuiltIn(id)),
                "isCakeAing": .bool(CharacterCatalog.isCakeAing(id)),
                "isGiftOnlyBuiltIn": .bool(CharacterCatalog.isGiftOnlyBuiltIn(id)),
                "isNeverExchangeable": id.map { .bool(GachaRules.isNeverExchangeable($0)) } ?? .null,
                "finish": .string(Self.finishName(finish)),
                "isRare": .bool(finish.isRare),
                "isCake": .bool(finish.isCake),
            ])
        }
        // 카탈로그: 번들 항목이 내장 id 를 덮으려 해도 내장이 이긴다 · 표시 순서 = 내장 다섯 + 나머지 id 정렬.
        let bundled: [[CharacterManifest]] = [
            [],
            [CharacterManifest(id: "fox", displayName: "여우", kind: .scene3D), CharacterManifest(id: "robot", displayName: "로봇", kind: .scene3D)],
            [CharacterManifest(id: "zeta", displayName: "제타", kind: .scene3D), CharacterManifest(id: "aing", displayName: "가짜 아잉", kind: .scene3D),
             CharacterManifest(id: "aing_gold", displayName: "가짜 금", kind: .scene3D), CharacterManifest(id: "alpha", displayName: "알파", kind: .scene3D),
             CharacterManifest(id: "aing_cake_choco", displayName: "가짜 초코", kind: .scene3D)],
        ]
        for (index, manifests) in bundled.enumerated() {
            let catalog = CharacterCatalog(manifests: manifests)
            cases.append([
                "id": .string("catalog-\(index)"),
                "bundled": .array(manifests.map { ["id": .string($0.id), "displayName": .string($0.displayName)] }),
                "allIDs": .array(catalog.allIDs.map(GoldenJSON.string)),
                "displayNames": .array(catalog.allIDs.map { .string(catalog.manifest(id: $0)?.displayName ?? "") }),
            ])
        }
        // 금 · 무지개 그림 이름과 "그릴 수 있다"(플랫폼마다 요구 파일).
        for (name, required, halo) in [
            ("gold", { (p: GoldAingArt.Platform) in GoldAingArt.requiredResourceNames(for: p) }, GoldAingArt.haloCellResourceNames),
            ("rainbow", { (p: GoldAingArt.Platform) in RainbowAingArt.requiredResourceNames(for: p) }, RainbowAingArt.haloCellResourceNames),
        ] {
            cases.append([
                "id": .string("art-\(name)"),
                "mac": .array(required(.mac).map(GoldenJSON.string)),
                "phone": .array(required(.phone).map(GoldenJSON.string)),
                "haloCells": .array(halo.map(GoldenJSON.string)),
            ])
        }
        // isDrawable: 요구 파일 중 하나씩 빼 본다(전부 있으면 참 · 하나라도 없으면 거짓).
        var drawable: [GoldenJSON] = []
        for platform in [GoldAingArt.Platform.mac, .phone] {
            let names = GoldAingArt.requiredResourceNames(for: platform)
            for missing in [nil] + names.map(Optional.some) {
                let present = Set(names.filter { $0 != missing })
                drawable.append([
                    "platform": .string(platform == .mac ? "mac" : "phone"),
                    "missing": Self.s(missing),
                    "gold": .bool(GoldAingArt.isDrawable(on: platform, resourceExists: present.contains)),
                ])
            }
        }
        cases.append(["id": "art-drawable", "rows": .array(drawable)])
        goldenEmit(GoldenFile(
            golden: "gift/catalog",
            equivalence: .bit,
            swiftSources: ["Sources/CheckCore/CharacterKit/CharacterCatalog.swift", "Sources/CheckCore/CharacterKit/GoldAing.swift",
                           "Sources/CheckCore/CharacterKit/RainbowAing.swift", "Sources/CheckCore/Gacha.swift"],
            platformSensitive: false,
            spec: [
                "builtins": "코드에 박힌 다섯 — 표시 순서는 내장 순서(정렬에 기대지 않는다 — aing_cake_* 는 정렬로는 aing_gold 앞이다)",
                "ids": "id 판정은 공백 · 대소문자를 봐주지 않는다. 케이크는 선물 전용이고 뽑기 전용이 아니다(겹치지 않는다). isNeverExchangeable = 아잉 · 선물 전용",
                "finish": "id → 마감. isRare 는 금 · 무지개만(케이크는 희귀가 아니다 — 열거로 판정)",
                "catalog": "번들 항목이 내장 id 를 덮으려 해도 내장이 이긴다. allIDs = 내장 다섯 + 나머지 id 사전순",
                "art": "금 · 무지개 그림 이름과 플랫폼별 요구 파일(폰 = 초상 두 장, 맥 = 초상 + 3D 마감 두 장). 후광 칸 36장은 그릴 수 있다에 넣지 않는다",
            ],
            cases: cases
        ))
    }

    // MARK: gift/claim

    @Test("gift/claim — 수령 status → 결과 · settlesGift · 문구 · 목적격 조사")
    func giftClaim() {
        var cases: [GoldenJSON] = []
        let statuses: [(String, String?, Bool?)] = [
            ("ok", "aing_cake_choco", false), ("ok", "aing_cake_strawberry", true), ("ok", nil, nil), ("ok", "", nil),
            ("already_claimed", "aing_cake_strawberry", nil), ("already_claimed", nil, nil), ("already_claimed", "", nil),
            ("needs_update", nil, nil), ("not_found", nil, nil), ("invalid_choice", "fox", nil), ("unauthorized", nil, nil),
            ("weird_new_status", nil, nil), ("", nil, nil), ("OK", "aing_cake_choco", nil),
        ]
        let names: [String: String] = ["aing_cake_strawberry": "딸기 케이크 아잉이", "aing_cake_choco": "초코 케이크 아잉이"]
        for (index, (status, characterID, replayed)) in statuses.enumerated() {
            let response = CharacterGiftClaimResponse(status: status, characterId: characterID, replayed: replayed)
            let outcome = CharacterGiftClaimOutcome(response: response, requestedID: "aing_cake_choco")
            let kind: GoldenJSON
            switch outcome {
            case .received(let id, let replayed): kind = ["kind": "received", "characterID": .string(id), "replayed": .bool(replayed)]
            case .alreadyClaimed(let id): kind = ["kind": "alreadyClaimed", "characterID": Self.s(id)]
            case .needsUpdate: kind = ["kind": "needsUpdate"]
            case .notFound: kind = ["kind": "notFound"]
            case .invalidChoice: kind = ["kind": "invalidChoice"]
            case .notSignedIn: kind = ["kind": "notSignedIn"]
            case .unavailable: kind = ["kind": "unavailable"]
            case .failed(let raw): kind = ["kind": "failed", "status": .string(raw)]
            }
            cases.append([
                "id": .string("claim-\(index)"),
                "status": .string(status), "characterId": Self.s(characterID), "replayed": Self.b(replayed),
                "requestedID": "aing_cake_choco",
                "outcome": kind,
                "settlesGift": .bool(outcome.settlesGift),
                "notice": Self.s(CakeGiftText.notice(for: outcome, name: { names[$0] ?? $0 })),
            ])
        }
        cases.append([
            "id": "texts",
            "title": .string(CakeGiftText.title), "body": .string(CakeGiftText.body), "confirmButton": .string(CakeGiftText.confirmButton),
            "wearNowButton": .string(CakeGiftText.wearNowButton), "closeButton": .string(CakeGiftText.closeButton),
            "lockedCaption": .string(CakeGiftText.lockedCaption), "lockedHint": .string(CakeGiftText.lockedHint),
            "reopenTitle": .string(CakeGiftText.reopenTitle), "reopenButton": .string(CakeGiftText.reopenButton),
            "claimFailed": .string(CakeGiftText.claimFailed), "needsUpdate": .string(CakeGiftText.needsUpdate),
            "unavailable": .string(CakeGiftText.unavailable), "notSignedIn": .string(CakeGiftText.notSignedIn),
            "notFound": .string(CakeGiftText.notFound), "invalidChoice": .string(CakeGiftText.invalidChoice),
            "alreadyClaimed": .string(CakeGiftText.alreadyClaimed),
        ])
        let words = ["딸기 케이크 아잉이", "초코 케이크 아잉이", "황금 아잉이", "곰", "각", "가", "힣", "aing", "", "  ", "아잉이 ", "케이크\n",
                     "여우😀", "닭", "ㄱ", "123", "Kim", "뷁",
                     // 받침 있는 글자 + 꼬리 공백 · 줄바꿈(앞뒤를 걷어야 '을' — 걷지 않으면 마지막 스칼라가 공백이라 '를').
                     "곰 ", "닭\n", "\t각\r\n", "곰\u{3000}", "  힣  ", "곰\u{2028}"]
        cases.append([
            "id": "particles",
            "rows": .array(words.map { word in
                ["word": .string(word), "particle": .string(CakeGiftText.objectParticle(after: word)),
                 "received": .string(CakeGiftText.received(name: word))]
            }),
        ])
        goldenEmit(GoldenFile(
            golden: "gift/claim",
            equivalence: .bit,
            swiftSources: ["Sources/CheckCore/CharacterGift.swift"],
            platformSensitive: false,
            spec: [
                "lines": "CharacterGift.swift 의 W1-c 몫(164–217 수령 결과 · 269–326 문구). 전선 모양(요청 · 응답 · choosable)은 W1-d wire",
                "outcome": "ok → received(서버 id 가 비면 보낸 id) · already_claimed → 받은 id(비면 null) · 대소문자 정확히 · 모르는 status → failed(원문)",
                "settlesGift": "받음 · 이미 받음 · 없음 → 선물 카드를 거둔다. 그 밖은 열린 채",
                "particle": "마지막 스칼라(앞뒤 whitespacesAndNewlines trim 뒤)가 받침 있는 한글 음절이면 '을', 그 밖은 '를'",
            ],
            cases: cases
        ))
    }

    // MARK: gacha/shop-protocol

    @Test("gacha/shop-protocol — 그릴 수 있는 id 집합 → 능력 번호(누적) · 문턱 · 플랫폼 그림 집합 → 번호")
    func shopProtocol() {
        let pool = ["robot", "aing_gold", "aing_rainbow", "aing_cake_strawberry", "aing_cake_choco", "fox"]
        var cases: [GoldenJSON] = []
        var rows: [GoldenJSON] = []
        for mask in 0..<(1 << pool.count) {
            let drawable = pool.enumerated().filter { mask & (1 << $0.offset) != 0 }.map(\.element)
            rows.append(["drawable": .array(drawable.map(GoldenJSON.string)),
                         "protocol": .int(ShopWire.protocolVersion(drawableCharacterIDs: drawable))])
        }
        cases.append(["id": "subsets", "rows": .array(rows)])
        cases.append([
            "id": "constants",
            "legacyProtocol": .int(ShopWire.legacyProtocol), "robotProtocol": .int(ShopWire.robotProtocol),
            "goldProtocol": .int(ShopWire.goldProtocol), "rainbowProtocol": .int(ShopWire.rainbowProtocol),
            "cakeProtocol": .int(ShopWire.cakeProtocol), "robotCharacterID": .string(ShopWire.robotCharacterID),
            "goldCharacterID": .string(ShopWire.goldCharacterID), "rainbowCharacterID": .string(ShopWire.rainbowCharacterID),
            "cakeCharacterIDs": .array(ShopWire.cakeCharacterIDs.map(GoldenJSON.string)),
            "thresholds": .array((-1...6).map { version in
                ["protocol": .int(version), "supportsGacha": .bool(ShopWire.supportsGacha(protocolVersion: version)),
                 "supportsCakeGift": .bool(ShopWire.supportsCakeGift(protocolVersion: version))]
            }),
        ])
        // 플랫폼 그림 집합 → 번호(G §8-7 ③ "플랫폼별 drawable 집합 → 번호"). 폰(= Android · Windows 첫 판) 은 초상 두 장이 있는 id 가
        // 그릴 수 있는 id 다. 스프라이트 캐릭터는 매니페스트의 초상, 금 · 무지개 · 케이크는 `<id>-neutral` · `<id>-negative`.
        let portraitSets: [(String, [String])] = [
            ("none", []),
            ("sprites-only", ["fox", "robot"]),
            ("no-robot", ["fox", "aing_gold", "aing_rainbow", "aing_cake_strawberry", "aing_cake_choco"]),
            ("gold", ["robot", "aing_gold"]),
            ("rainbow", ["robot", "aing_gold", "aing_rainbow"]),
            ("one-cake", ["robot", "aing_gold", "aing_rainbow", "aing_cake_strawberry"]),
            ("all", ["robot", "aing_gold", "aing_rainbow", "aing_cake_strawberry", "aing_cake_choco", "fox", "squirrel"]),
        ]
        for (name, ids) in portraitSets {
            var files: [String] = []
            for id in ids { files += ["\(id)-neutral", "\(id)-negative"] }
            cases.append(["id": .string("portraits-\(name)"), "portraitFiles": .array(files.map(GoldenJSON.string)),
                          "protocol": .int(ShopWire.protocolVersion(drawableCharacterIDs: ids))])
        }
        // 초상이 **한 장만** 있는 id 는 그릴 수 없다(두 장 다 있어야 — 폰 `AingCharacterArt` 는 표정 둘을 다 그린다). ids 가 그릴 수 있는 집합,
        // strays 는 짝 없이 한 장만 실린 그림이다 — 번호는 ids 로만 정한다(한 장짜리를 세면 그 캐릭터 카드가 아잉 그림으로 팔린다).
        let strayPortraitSets: [(String, [String], [String])] = [
            ("cake-choco-neutral-only", ["robot", "aing_gold", "aing_rainbow", "aing_cake_strawberry"], ["aing_cake_choco-neutral"]),
            ("cake-strawberry-negative-only", ["robot", "aing_gold", "aing_rainbow", "aing_cake_choco"], ["aing_cake_strawberry-negative"]),
            ("rainbow-neutral-only", ["robot", "aing_gold", "aing_cake_strawberry", "aing_cake_choco"], ["aing_rainbow-neutral"]),
            ("gold-neutral-only", ["robot"], ["aing_gold-neutral"]),
            ("robot-negative-only", ["fox", "aing_gold", "aing_rainbow", "aing_cake_strawberry", "aing_cake_choco"], ["robot-negative"]),
            ("robot-neutral-only", ["fox", "aing_gold", "aing_rainbow", "aing_cake_strawberry", "aing_cake_choco"], ["robot-neutral"]),
        ]
        for (name, ids, strays) in strayPortraitSets {
            var files: [String] = []
            for id in ids { files += ["\(id)-neutral", "\(id)-negative"] }
            files += strays
            cases.append(["id": .string("portraits-\(name)"), "portraitFiles": .array(files.map(GoldenJSON.string)),
                          "protocol": .int(ShopWire.protocolVersion(drawableCharacterIDs: ids))])
        }
        goldenEmit(GoldenFile(
            golden: "gacha/shop-protocol",
            equivalence: .bit,
            swiftSources: ["Sources/CheckCore/ShopProtocol.swift", "Sources/CheckCore/CharacterKit/CharacterCatalog.swift"],
            platformSensitive: false,
            spec: [
                "protocol": "K9 — 번호는 그릴 수 있는 id 에서 파생한다(상수로 박지 않는다). 누적: robot 없으면 0, 금 없으면 1, 무지개 없으면 2, 케이크 둘이 다 있으면 4 아니면 3",
                "thresholds": "supportsGacha = 번호 ≥ 2 · supportsCakeGift = 번호 ≥ 4",
                "portraits": "G §8-7 ③ — 폰 · Android · Windows 첫 판의 '그릴 수 있다' = 그 id 의 초상 두 장(<id>-neutral · <id>-negative)이 번들에 있다. 그림 자산을 지운 빌드는 번호가 내려간다",
            ],
            cases: cases
        ))
    }

    // MARK: gacha/odds

    struct GachaHolder: Decodable { let gacha: GachaInfo? }

    static func gachaInfoJSON(_ info: GachaInfo?) -> GoldenJSON {
        guard let info else { return .null }
        let costs: GoldenJSON = info.shardCosts.map { costs in
            .object(Dictionary(uniqueKeysWithValues: costs.map { ($0.key, Self.n($0.value)) }))
        } ?? .null
        return [
            "price": Self.n(info.price), "shards": Self.n(info.shards),
            "odds": info.odds.map { .array($0.map { ["characterID": .string($0.characterID), "percentBits": .bits($0.percent)] }) } ?? .null,
            "shardCosts": costs,
            "totalPercentBits": .bits(info.totalPercent),
            "hasCompleteOdds": .bool(info.hasCompleteOdds),
            "isUsable": .bool(info.isUsable),
        ]
    }

    static let gachaValues: [String] = [
        #"{"price":50,"shards":3,"odds":[{"character_id":"fox","percent":60},{"character_id":"aing_gold","percent":40}],"shard_costs":{"fox":2,"aing_gold":20}}"#,
        #"{"price":50,"shards":3,"odds":[{"character_id":"fox","percent":60},{"character_id":"aing_gold","percent":39.995}],"shard_costs":{"fox":2}}"#,
        #"{"price":50,"odds":[{"character_id":"fox","percent":60},{"character_id":"aing_gold","percent":39.98}]}"#,
        #"{"price":50,"odds":[{"character_id":"fox","percent":"60"},{"character_id":"aing_gold","percent":40}]}"#,
        #"{"price":50,"odds":[{"character_id":"fox","percent":60},{"percent":40}, 7, null, {"character_id":"robot","percent":40}]}"#,
        #"{"price":"50","shards":"3","odds":[{"character_id":"fox","percent":100}],"shard_costs":{"fox":"2","robot":4,"aing_gold":3.5,"x":null}}"#,
        #"{"price":50.0,"shards":3.0,"odds":[{"character_id":"fox","percent":2.5},{"character_id":"robot","percent":97.5}],"shard_costs":{"robot":4.0}}"#,
        #"{"odds":[{"character_id":"fox","percent":100}]}"#,
        #"{"price":50,"odds":[]}"#,
        #"{"price":50,"odds":{}}"#,
        #"{"price":50}"#,
        #""gacha off""#,
        #"[1,2]"#,
        #"null"#,
        #"{"price":null,"shards":null,"odds":null,"shard_costs":null}"#,
        #"{"price":50,"shards":-2,"odds":[{"character_id":"aing_rainbow","percent":1.0204081632653061},{"character_id":"fox","percent":98.9795918367347}],"shard_costs":{"aing_rainbow":0,"fox":-1,"aing":3,"aing_cake_choco":5}}"#,
        #"{"price":9223372036854775807,"shards":9007199254740993,"odds":[{"character_id":"fox","percent":1e2}]}"#,
    ]

    static let shopRowsJSON = #"[{"id":"fox","price":60,"owned":true,"gacha_only":false},{"id":"robot","price":200,"gacha_only":null},{"id":"aing_gold","price":1000,"gacha_only":true},{"id":"aing_rainbow","price":1000},{"id":"aing_cake_choco","price":2001,"gacha_only":true,"gift_only":true},{"id":"squirrel"},{"id":"fox","price":1}]"#

    static func pullOutcomeJSON(_ outcome: GachaPullOutcome) -> GoldenJSON {
        switch outcome {
        case .pulled(let result):
            let kind: String
            switch result.kind {
            case .gold: kind = "gold"
            case .rainbow: kind = "rainbow"
            case .newCharacter: kind = "newCharacter"
            case .duplicate: kind = "duplicate"
            }
            return ["kind": "pulled", "characterID": .string(result.characterID), "isDuplicate": .bool(result.isDuplicate),
                    "shardsGained": Self.n(result.shardsGained), "shards": Self.n(result.shards), "rubyBalance": Self.n(result.rubyBalance),
                    "replayed": .bool(result.replayed), "resultKind": .string(kind), "newlyOwnedID": Self.s(result.newlyOwnedID),
                    "headline": .string(GachaText.headline(for: result, name: "이름")),
                    "detail": Self.s(GachaText.detail(for: result, name: "이름"))]
        case .insufficient(let need, let have): return ["kind": "insufficient", "need": Self.n(need), "have": Self.n(have)]
        case .needsUpdate: return ["kind": "needsUpdate"]
        case .notSignedIn: return ["kind": "notSignedIn"]
        case .invalid: return ["kind": "invalid"]
        case .unavailable: return ["kind": "unavailable"]
        case .failed(let status): return ["kind": "failed", "status": .string(status)]
        }
    }

    static func exchangeOutcomeJSON(_ outcome: GachaExchangeOutcome) -> GoldenJSON {
        switch outcome {
        case .exchanged(let id, let shards, let cost, let replayed):
            return ["kind": "exchanged", "characterID": .string(id), "shards": Self.n(shards), "cost": Self.n(cost), "replayed": .bool(replayed)]
        case .alreadyOwned: return ["kind": "alreadyOwned"]
        case .notExchangeable: return ["kind": "notExchangeable"]
        case .insufficientShards(let need, let have): return ["kind": "insufficientShards", "need": Self.n(need), "have": Self.n(have)]
        case .needsUpdate: return ["kind": "needsUpdate"]
        case .notSignedIn: return ["kind": "notSignedIn"]
        case .unavailable: return ["kind": "unavailable"]
        case .failed(let status): return ["kind": "failed", "status": .string(status)]
        }
    }

    static func pullAvailabilityJSON(_ value: GachaPullAvailability) -> GoldenJSON {
        switch value {
        case .ready(let price): return ["kind": "ready", "price": Self.n(price), "canPull": .bool(value.canPull)]
        case .short(let price, let missing): return ["kind": "short", "price": Self.n(price), "missing": Self.n(missing), "canPull": .bool(value.canPull)]
        case .unknownBalance(let price): return ["kind": "unknownBalance", "price": Self.n(price), "canPull": .bool(value.canPull)]
        case .unavailable: return ["kind": "unavailable", "canPull": .bool(value.canPull)]
        }
    }

    static func exchangeAvailabilityJSON(_ value: GachaExchangeAvailability) -> GoldenJSON {
        let base: [String: GoldenJSON]
        switch value {
        case .owned: base = ["kind": "owned"]
        case .available(let cost): base = ["kind": "available", "cost": Self.n(cost)]
        case .short(let cost, let missing): base = ["kind": "short", "cost": Self.n(cost), "missing": Self.n(missing)]
        case .unknownShards(let cost): base = ["kind": "unknownShards", "cost": Self.n(cost)]
        case .notExchangeable: base = ["kind": "notExchangeable"]
        }
        var members = base
        members["canExchange"] = .bool(value.canExchange)
        members["costValue"] = Self.n(value.cost)
        return .object(members)
    }

    @Test("gacha/odds — E9: 뽑기 표 디코드 · 판정 · 줄 · 응답 → 결과 · 문구")
    func gachaOdds() throws {
        var cases: [GoldenJSON] = []
        let decoder = Self.decoder()
        // ① GachaInfo 디코드(shop_state.gacha 자리에 값 하나씩 — 데모 픽스처 원문 + 합성 변형).
        var values = Self.gachaValues
        for path in ["Sources/CheckMobileKit/Demo/Fixtures/me/_me/rpc.shop_state.json",
                     "Sources/CheckMobileKit/Demo/Fixtures/me/_me-/rpc.shop_state.json",
                     "Sources/CheckMobileKit/Demo/Fixtures/me/_me-shop/rpc.shop_state.json"] {
            let data = Data(Self.fixture(path).utf8)
            if let object = try JSONSerialization.jsonObject(with: data) as? [String: Any], let gacha = object["gacha"] {
                let text = String(data: try JSONSerialization.data(withJSONObject: gacha, options: [.sortedKeys, .fragmentsAllowed]), encoding: .utf8)!
                values.append(text)
            }
        }
        var infos: [GachaInfo?] = []
        for (index, value) in values.enumerated() {
            let holder = try decoder.decode(GachaHolder.self, from: Data("{\"gacha\":\(value)}".utf8))
            infos.append(holder.gacha)
            cases.append(["id": .string("info-\(index)"), "json": .string(value), "info": Self.gachaInfoJSON(holder.gacha)])
        }
        // ② 표시 %(정수면 소수점 없이 · 아니면 한 자리 — 반올림은 0.5 에서 0 에서 먼 쪽).
        let percents: [Double] = [0, 1, 2, 2.5, 3, 0.05, 0.04999, 0.15, 0.25, 0.35, 1.0204081632653061, 98.9795918367347, 99.95, 100, 33.333,
                                  12.25, 12.35, 0.95, -0.05, -2.5, 50.05]
        cases.append(["id": "percent-text", "rows": .array(percents.map { ["valueBits": .bits($0), "text": .string(GachaText.percent($0))] })])
        // ③ 뽑기 가능(값 × 잔량).
        var pull: [GoldenJSON] = []
        for (index, info) in infos.enumerated() {
            for balance in [nil, 0, 49, 50, 51, 1000] as [Int?] {
                pull.append(["info": .int(index), "rubyBalance": Self.n(balance),
                             "availability": Self.pullAvailabilityJSON(GachaRules.pullAvailability(info: info, rubyBalance: balance)),
                             "blockedReason": Self.s(GachaText.blockedReason(GachaRules.pullAvailability(info: info, rubyBalance: balance)))])
            }
        }
        cases.append(["id": "pull-availability", "rows": .array(pull)])
        // ④ 교환 가능(캐릭터 × 보유 × 조각 × 교환표).
        let costTables: [[String: Int]?] = [nil, [:], ["fox": 2, "aing_gold": 20, "aing": 1, "aing_cake_choco": 5, "robot": 0, "shiba": -3]]
        var exchange: [GoldenJSON] = []
        for (tableIndex, costs) in costTables.enumerated() {
            for id in ["fox", "aing_gold", "aing", "aing_cake_choco", "robot", "shiba", "ghost"] {
                for owned in [false, true] {
                    for shards in [nil, 0, 1, 2, 20, 25] as [Int?] {
                        let value = GachaRules.exchangeAvailability(characterID: id, isOwned: owned, shards: shards, shardCosts: costs)
                        exchange.append(["table": .int(tableIndex), "characterID": .string(id), "owned": .bool(owned), "shards": Self.n(shards),
                                         "availability": Self.exchangeAvailabilityJSON(value)])
                    }
                }
            }
        }
        cases.append(["id": "exchange-availability", "costTables": .array(costTables.map { table in
            table.map { .object(Dictionary(uniqueKeysWithValues: $0.map { ($0.key, Self.n($0.value)) })) } ?? .null
        }), "rows": .array(exchange)])
        // ⑤ 확률표 줄 · 교환 줄(이름은 호출부 표 → 내장 이름 → id).
        let shopRows = try decoder.decode([ShopCharacterRow].self, from: Data(Self.shopRowsJSON.utf8))
        let names: [String: String] = ["fox": "여우", "robot": " 로봇 ", "squirrel": "  ", "aing_gold": ""]
        var oddsRows: [GoldenJSON] = []
        var exchangeRows: [GoldenJSON] = []
        for (index, info) in infos.enumerated() {
            guard let info else { continue }
            let rows = GachaRules.oddsRows(info: info, shopRows: shopRows, displayName: { names[$0] })
            oddsRows.append(["info": .int(index), "rows": .array(rows.map { row in
                ["characterID": .string(row.characterID), "name": .string(row.name), "percentBits": .bits(row.percent),
                 "percentText": .string(row.percentText), "shopPrice": Self.n(row.shopPrice), "priceText": .string(row.priceText),
                 "isGachaOnly": .bool(row.isGachaOnly), "shardCost": Self.n(row.shardCost), "isGold": .bool(row.isGold),
                 "isRainbow": .bool(row.isRainbow), "finish": .string(Self.finishName(row.finish))]
            })])
            for owned in [Set<String>(), ["fox", "aing_gold"]] {
                let rows = GachaRules.exchangeRows(info: info, ownedIDs: owned, displayName: { names[$0] })
                exchangeRows.append(["info": .int(index), "owned": .array(owned.sorted().map(GoldenJSON.string)), "rows": .array(rows.map { row in
                    ["characterID": .string(row.characterID), "name": .string(row.name), "availability": Self.exchangeAvailabilityJSON(row.availability)]
                })])
            }
        }
        cases.append(["id": "odds-rows", "shopRowsJSON": .string(Self.shopRowsJSON),
                      "shopRows": .array(shopRows.map { ["id": .string($0.id), "price": Self.n($0.price), "gachaOnly": Self.b($0.gachaOnly)] }),
                      "names": .object(names.mapValues(GoldenJSON.string)), "rows": .array(oddsRows)])
        cases.append(["id": "exchange-rows", "rows": .array(exchangeRows)])
        // ⑥ 응답 → 결과(뽑기 · 교환). status 만 필수 — 없으면 throw(결과를 모르는 응답 → 같은 request_id 로 다시 묻는다).
        let pullResponses: [String] = [
            Self.fixture("Sources/CheckMobileKit/Demo/Fixtures/me/rpc.gacha_pull.json"),
            #"{"status":"ok","character_id":"fox","duplicate":true,"shards":4,"ruby_balance":10}"#,
            #"{"status":"ok","character_id":"fox","duplicate":false}"#,
            #"{"status":"ok","character_id":"aing_gold","duplicate":true,"shards_gained":1,"replayed":true}"#,
            #"{"status":"ok","character_id":"aing_rainbow"}"#,
            #"{"status":"ok","character_id":""}"#,
            #"{"status":"ok"}"#,
            #"{"status":"ok","character_id":"fox","duplicate":"yes","shards_gained":"1","shards":2.5,"ruby_balance":"7"}"#,
            #"{"status":"insufficient","need":50,"have":12}"#,
            #"{"status":"insufficient"}"#,
            #"{"status":"needs_update"}"#, #"{"status":"not_signed_in"}"#, #"{"status":"invalid"}"#, #"{"status":"new_thing"}"#,
            #"{"status":7}"#, #"{"character_id":"fox"}"#, #"[]"#,
        ]
        var pulls: [GoldenJSON] = []
        for text in pullResponses {
            do {
                let response = try decoder.decode(GachaPullResponse.self, from: Data(text.utf8))
                let outcome = GachaPullOutcome(response: response)
                pulls.append(["json": .string(text), "status": .string(response.status.raw), "outcome": Self.pullOutcomeJSON(outcome),
                              "notice": Self.s(GachaText.notice(for: outcome))])
            } catch {
                pulls.append(["json": .string(text), "throws": true])
            }
        }
        cases.append(["id": "pull-responses", "rows": .array(pulls)])
        let exchangeResponses: [String] = [
            Self.fixture("Sources/CheckMobileKit/Demo/Fixtures/me/rpc.gacha_exchange.json"),
            Self.fixture("Sources/CheckMobileKit/Demo/Fixtures/me/rpc.gacha_exchange@aing_rainbow.json"),
            #"{"status":"ok","shards":1,"cost":2}"#, #"{"status":"ok","character_id":"robot","replayed":true}"#,
            #"{"status":"already_owned"}"#, #"{"status":"not_exchangeable"}"#, #"{"status":"insufficient_shards","need":20,"have":3}"#,
            #"{"status":"insufficient_shards","need":3,"have":20}"#, #"{"status":"insufficient_shards"}"#,
            #"{"status":"needs_update"}"#, #"{"status":"not_signed_in"}"#, #"{"status":"invalid"}"#, #"{}"#,
        ]
        var exchanges: [GoldenJSON] = []
        for text in exchangeResponses {
            do {
                let response = try decoder.decode(GachaExchangeResponse.self, from: Data(text.utf8))
                let outcome = GachaExchangeOutcome(response: response, requestedID: "fox")
                exchanges.append(["json": .string(text), "status": .string(response.status.raw), "outcome": Self.exchangeOutcomeJSON(outcome),
                                  "notice": .string(GachaText.notice(for: outcome, name: "여우"))])
            } catch {
                exchanges.append(["json": .string(text), "throws": true])
            }
        }
        cases.append(["id": "exchange-responses", "rows": .array(exchanges)])
        // ⑦ 요청 본문(키를 언제나 싣는다 — request_id 는 소문자 uuid).
        let requestID = UUID(uuidString: "D0000000-0000-4000-8000-00000000A001")!
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys]
        cases.append([
            "id": "requests",
            "pull": .string(String(data: try encoder.encode(GachaPullRequest(protocolVersion: 4, requestID: requestID)), encoding: .utf8)!),
            "exchange": .string(String(data: try encoder.encode(GachaExchangeRequest(characterID: "fox", protocolVersion: 3, requestID: requestID)), encoding: .utf8)!),
        ])
        // ⑧ request_id 수명(동작 한 번 = id 하나, 결과를 모르는 실패면 쥔 채).
        var ids = GachaRequestIDs()
        var counter = 0
        func make() -> UUID { counter += 1; return UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", counter))! }
        var steps: [GoldenJSON] = []
        func record(_ label: String, _ id: UUID?) {
            steps.append(["step": .string(label), "id": Self.s(id?.uuidString.lowercased()), "pull": Self.s(ids.pull?.uuidString.lowercased()),
                          "exchange": .object(Dictionary(uniqueKeysWithValues: ids.exchange.map { ($0.key, GoldenJSON.string($0.value.uuidString.lowercased())) }))])
        }
        let first = ids.pullID(make: make); record("pullID", first)
        let again = ids.pullID(make: make); record("pullID-held", again)
        let fox = ids.exchangeID(for: "fox", make: make); record("exchangeID fox", fox)
        let robot = ids.exchangeID(for: "robot", make: make); record("exchangeID robot", robot)
        ids.settlePull(make()); record("settlePull other", nil)
        ids.settlePull(first); record("settlePull first", nil)
        let second = ids.pullID(make: make); record("pullID new", second)
        ids.settleExchange(fox, for: "robot"); record("settleExchange fox-id for robot", nil)
        ids.settleExchange(fox, for: "fox"); record("settleExchange fox", nil)
        ids.reset(); record("reset", nil)
        cases.append(["id": "request-ids", "steps": .array(steps)])
        // ⑨ 문구.
        cases.append([
            "id": "texts",
            "title": .string(GachaText.title), "pullButton": .string(GachaText.pullButton), "pullButton50": .string(GachaText.pullButton(price: 50)),
            "oddsButton": .string(GachaText.oddsButton), "oddsTitle": .string(GachaText.oddsTitle), "oddsFootnote": .string(GachaText.oddsFootnote),
            "gachaOnly": .string(GachaText.gachaOnly), "gachaOnlyPrice20": .string(GachaText.gachaOnlyPrice(shardCost: 20)),
            "gachaOnlyPriceNil": .string(GachaText.gachaOnlyPrice(shardCost: nil)), "gachaOnlyPrice0": .string(GachaText.gachaOnlyPrice(shardCost: 0)),
            "gachaOnlyHint": .string(GachaText.gachaOnlyHint), "unknownValue": .string(GachaText.unknownValue), "owned": .string(GachaText.owned),
            "exchangeButton": .string(GachaText.exchangeButton), "exchangeTitle": .string(GachaText.exchangeTitle),
            "shards3": .string(GachaText.shards(3)), "goldHeadline": .string(GachaText.goldHeadline), "rainbowHeadline": .string(GachaText.rainbowHeadline),
            "shardShortfall2": .string(GachaText.shardShortfall(missing: 2)), "needsUpdate": .string(GachaText.needsUpdate),
            "unavailable": .string(GachaText.unavailable), "notSignedIn": .string(GachaText.notSignedIn), "connection": .string(GachaText.connection),
            "pullFailed": .string(GachaText.pullFailed), "exchangeFailed": .string(GachaText.exchangeFailed),
            "alreadyOwned": .string(GachaText.alreadyOwned), "notExchangeable": .string(GachaText.notExchangeable),
            "exchanged": .string(GachaText.exchanged(name: "여우")),
            "shortfall": .array([(nil, nil), (50, 12), (50, nil), (nil, 3), (10, 10)].map { pair in
                ["need": Self.n(pair.0), "have": Self.n(pair.1), "text": .string(GachaText.shortfall(need: pair.0, have: pair.1))]
            }),
        ])
        goldenEmit(GoldenFile(
            golden: "gacha/odds",
            equivalence: .bit,
            swiftSources: ["Sources/CheckCore/Gacha.swift", "Sources/CheckCore/CheckCoreShared.swift",
                           "Sources/CheckCore/CharacterKit/CharacterCatalog.swift", "Sources/CheckCore/CharacterKit/GoldAing.swift"],
            platformSensitive: false,
            spec: [
                "info": "GachaInfo 디코드는 throw 하지 않는다 — 객체가 아니면 빈 정보, 칸이 틀리면 null, 깨진 확률 행 · 교환값만 버린다. totalPercent 비트 · hasCompleteOdds(|합-100| < 0.01) · isUsable(값 + 완전한 표)",
                "percent": "정수면 소수점 없이 '5%', 아니면 한 자리 '2.5%' — (v*10).rounded()/10 은 0.5 에서 0 에서 먼 쪽(Swift .rounded())",
                "rows": "확률표 줄은 서버 순서 그대로. 금 · 무지개는 표식과 무관하게 뽑기 전용. 교환 목록은 금 → 무지개 → 확률표 순 → 나머지 id 순. 아잉 · 선물 전용은 교환 불가",
                "responses": "status 만 필수(없거나 글자가 아니면 throw — 같은 request_id 로 다시 묻는다). 나머지 칸은 모양이 틀리면 null",
                "requestIds": "동작 한 번 = id 하나 — 서버가 답했거나 함수가 없을 때만 버린다(settle). 교환은 캐릭터마다 칸이 따로",
            ],
            cases: cases
        ))
    }

    // MARK: gacha/character-kit

    static func manifestJSON(_ manifest: CharacterManifest) -> GoldenJSON {
        var members: [String: GoldenJSON] = [
            "id": .string(manifest.id), "displayName": .string(manifest.displayName), "kind": .string(manifest.kind.rawValue),
            "pixelArt": Self.b(manifest.pixelArt), "finish": .string(Self.finishName(manifest.finish)),
        ]
        if let atlas = manifest.atlas {
            members["atlas"] = [
                "file": .string(atlas.file), "width": .int(atlas.width), "height": .int(atlas.height),
                "states": .object(Dictionary(uniqueKeysWithValues: atlas.states.map { key, state in
                    (key, ["frames": .array(state.frames.map { [.int($0.x), .int($0.y), .int($0.w), .int($0.h)] }),
                           "durationsMs": .array(state.durationsMs.map(GoldenJSON.int)), "loop": .bool(state.loop)] as GoldenJSON)
                })),
            ]
        } else {
            members["atlas"] = .null
        }
        members["portrait"] = manifest.portrait.map { ["neutral": .string($0.neutral), "negative": .string($0.negative)] } ?? .null
        return .object(members)
    }

    static func manifestErrorName(_ error: Error) -> String {
        if let known = error as? CharacterManifestError {
            switch known {
            case .invalidID: return "invalidID"
            case .emptyDisplayName: return "emptyDisplayName"
            case .unexpectedAtlas: return "unexpectedAtlas"
            case .unexpectedPortrait: return "unexpectedPortrait"
            case .missingAtlas: return "missingAtlas"
            case .missingPortrait: return "missingPortrait"
            case .invalidAtlasSize: return "invalidAtlasSize"
            case .invalidAssetFileName: return "invalidAssetFileName"
            case .missingRequiredState: return "missingRequiredState"
            case .emptyFrames: return "emptyFrames"
            case .frameDurationMismatch: return "frameDurationMismatch"
            case .negativeDuration: return "negativeDuration"
            case .zeroTotalDuration: return "zeroTotalDuration"
            case .rectOutsideAtlas: return "rectOutsideAtlas"
            }
        }
        return "decoding"
    }

    static let spriteBase = #"{"id":"fox","displayName":"여우","kind":"sprite","atlas":{"file":"atlas.png","width":64,"height":32,"states":{"frontIdle":{"frames":[{"x":0,"y":0,"w":32,"h":32}],"durationsMs":[100],"loop":true},"sideWalk":{"frames":[{"x":0,"y":0,"w":32,"h":32},{"x":32,"y":0,"w":32,"h":32}],"durationsMs":[120,80],"loop":true}}},"portrait":{"neutral":"fox-neutral.png","negative":"fox-negative.png"}}"#

    static let manifestVariants: [(String, String)] = [
        ("sprite-ok", spriteBase),
        ("scene3d-ok", #"{"id":"aing-3d","displayName":"아잉 3D","kind":"scene3D"}"#),
        ("pixel-art", spriteBase.replacingOccurrences(of: #""kind":"sprite""#, with: #""kind":"sprite","pixelArt":true"#)),
        ("bad-id-underscore", spriteBase.replacingOccurrences(of: #""id":"fox""#, with: #""id":"fox_1""#)),
        ("bad-id-upper", spriteBase.replacingOccurrences(of: #""id":"fox""#, with: #""id":"Fox""#)),
        ("bad-id-long", spriteBase.replacingOccurrences(of: #""id":"fox""#, with: #""id":"abcdefghijklmnopqrstuvwxyz0123456""#)),
        ("bad-id-empty", spriteBase.replacingOccurrences(of: #""id":"fox""#, with: #""id":"""#)),
        ("bad-id-hangul", spriteBase.replacingOccurrences(of: #""id":"fox""#, with: #""id":"여우""#)),
        ("empty-name", spriteBase.replacingOccurrences(of: #""displayName":"여우""#, with: #""displayName":" \n ""#)),
        ("unknown-kind", spriteBase.replacingOccurrences(of: #""kind":"sprite""#, with: #""kind":"video""#)),
        ("scene3d-with-atlas", spriteBase.replacingOccurrences(of: #""kind":"sprite""#, with: #""kind":"scene3D""#)),
        ("scene3d-with-portrait", #"{"id":"x","displayName":"엑스","kind":"scene3D","portrait":{"neutral":"a.png","negative":"b.png"}}"#),
        ("sprite-no-atlas", #"{"id":"x","displayName":"엑스","kind":"sprite","portrait":{"neutral":"a.png","negative":"b.png"}}"#),
        ("sprite-no-portrait", spriteBase.replacingOccurrences(of: #","portrait":{"neutral":"fox-neutral.png","negative":"fox-negative.png"}"#, with: "")),
        ("asset-slash", spriteBase.replacingOccurrences(of: #""file":"atlas.png""#, with: #""file":"../atlas.png""#)),
        ("asset-dot", spriteBase.replacingOccurrences(of: #""neutral":"fox-neutral.png""#, with: #""neutral":".hidden.png""#)),
        ("asset-backslash", spriteBase.replacingOccurrences(of: #""negative":"fox-negative.png""#, with: #""negative":"a\\b.png""#)),
        ("asset-empty", spriteBase.replacingOccurrences(of: #""file":"atlas.png""#, with: #""file":"""#)),
        ("atlas-zero", spriteBase.replacingOccurrences(of: #""width":64"#, with: #""width":0"#)),
        ("no-front", spriteBase.replacingOccurrences(of: #""frontIdle""#, with: #""frontIdleX""#)),
        ("front-empty", spriteBase.replacingOccurrences(of: #""frames":[{"x":0,"y":0,"w":32,"h":32}],"durationsMs":[100]"#, with: #""frames":[],"durationsMs":[]"#)),
        ("duration-mismatch", spriteBase.replacingOccurrences(of: #""durationsMs":[120,80]"#, with: #""durationsMs":[120]"#)),
        ("negative-duration", spriteBase.replacingOccurrences(of: #""durationsMs":[120,80]"#, with: #""durationsMs":[120,-1]"#)),
        ("zero-total", spriteBase.replacingOccurrences(of: #""durationsMs":[120,80]"#, with: #""durationsMs":[0,0]"#)),
        ("rect-outside", spriteBase.replacingOccurrences(of: #"{"x":32,"y":0,"w":32,"h":32}"#, with: #"{"x":33,"y":0,"w":32,"h":32}"#)),
        ("rect-negative", spriteBase.replacingOccurrences(of: #"{"x":32,"y":0,"w":32,"h":32}"#, with: #"{"x":-1,"y":0,"w":32,"h":32}"#)),
        ("rect-zero-w", spriteBase.replacingOccurrences(of: #"{"x":32,"y":0,"w":32,"h":32}"#, with: #"{"x":32,"y":0,"w":0,"h":32}"#)),
        ("missing-loop", spriteBase.replacingOccurrences(of: #","loop":true}}}"#, with: "}}}")),
        ("unknown-state-ok", spriteBase.replacingOccurrences(of: #""sideWalk""#, with: #""dance""#)),
        ("extra-key-ok", spriteBase.replacingOccurrences(of: #""kind":"sprite""#, with: #""kind":"sprite","note":"무시""#)),
        ("pixel-art-string", spriteBase.replacingOccurrences(of: #""kind":"sprite""#, with: #""kind":"sprite","pixelArt":"yes""#)),
        ("width-float", spriteBase.replacingOccurrences(of: #""width":64"#, with: #""width":64.0"#)),
        ("not-object", #"[1]"#),
    ]

    @Test("gacha/character-kit — 매니페스트 검증(번들 실물 + 깨진 변형) · 프레임 시계 · 착용 동기화 판정")
    @MainActor
    func characterKit() throws {
        var cases: [GoldenJSON] = []
        let decoder = JSONDecoder()   // 매니페스트는 키 변환 없는 기본 디코더다(CharacterCatalog.load)
        var bundled: [(String, String)] = []
        let root = GoldenRepo.url("Sources/check/Characters")
        for name in ((try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []).sorted() {
            let path = "Sources/check/Characters/\(name)/manifest.json"
            let text = Self.fixture(path)
            if !text.isEmpty { bundled.append(("bundle-\(name)", text)) }
        }
        #expect(bundled.count >= 6, "번들 캐릭터 매니페스트가 \(bundled.count) 개뿐이다")
        for (id, text) in bundled + Self.manifestVariants {
            do {
                let manifest = try decoder.decode(CharacterManifest.self, from: Data(text.utf8))
                cases.append(["id": .string("manifest-\(id)"), "json": .string(text), "manifest": Self.manifestJSON(manifest)])
            } catch {
                cases.append(["id": .string("manifest-\(id)"), "json": .string(text), "error": .string(Self.manifestErrorName(error))])
            }
        }
        // isValidID 표(그래핌 수 1…32 · ASCII 소문자 · 숫자 · 하이픈).
        let ids = ["a", "fox", "fox-2", "a-", "-", "0", "", "Fox", "fox_1", "fox 1", "여우", "é", String(repeating: "a", count: 32), String(repeating: "a", count: 33), "a\u{301}"]
        cases.append(["id": "valid-ids", "rows": .array(ids.map { ["text": .string($0), "valid": .bool(CharacterManifest.isValidID($0))] })])
        // 프레임 시계.
        let states: [(String, CharacterManifest.State)] = [
            ("walk-loop", .init(frames: [.init(x: 0, y: 0, w: 1, h: 1), .init(x: 1, y: 0, w: 1, h: 1), .init(x: 2, y: 0, w: 1, h: 1), .init(x: 1, y: 0, w: 1, h: 1)],
                                durationsMs: [100, 100, 100, 100], loop: true)),
            ("uneven-once", .init(frames: [.init(x: 0, y: 0, w: 1, h: 1), .init(x: 1, y: 0, w: 1, h: 1), .init(x: 2, y: 0, w: 1, h: 1)],
                                  durationsMs: [120, 80, 300], loop: false)),
            ("single", .init(frames: [.init(x: 0, y: 0, w: 1, h: 1)], durationsMs: [0], loop: true)),
            ("zero-tail", .init(frames: [.init(x: 0, y: 0, w: 1, h: 1), .init(x: 1, y: 0, w: 1, h: 1)], durationsMs: [100, 0], loop: true)),
            ("short-durations", .init(frames: [.init(x: 0, y: 0, w: 1, h: 1), .init(x: 1, y: 0, w: 1, h: 1)], durationsMs: [50], loop: true)),
            ("tenths", .init(frames: [.init(x: 0, y: 0, w: 1, h: 1), .init(x: 1, y: 0, w: 1, h: 1), .init(x: 2, y: 0, w: 1, h: 1)],
                             durationsMs: [100, 100, 100], loop: true)),
        ]
        let elapsed: [Double] = [-1, 0, 0.05, 0.0999, 0.1, 0.10000000000000001, 0.12, 0.2, 0.3, 0.30000000000000004, 0.35, 0.4, 0.5, 0.8,
                                 1.0, 12.345, .infinity, -.infinity, .nan, 1e9]
        for (name, state) in states {
            let player = SpriteFramePlayer(state: state)
            cases.append(["id": .string("frames-\(name)"), "totalDurationBits": .bits(player.totalDuration),
                          "frames": .int(state.frames.count), "durationsMs": .array(state.durationsMs.map(GoldenJSON.int)), "loop": .bool(state.loop),
                          "samples": .array(elapsed.map { ["elapsedBits": .bits($0), "index": .int(player.frameIndex(elapsed: $0))] })])
        }
        // 착용 동기화 판정.
        var sync: [GoldenJSON] = []
        let known: Set<String> = ["aing", "fox", "robot", "aing_gold"]
        let unlocked: Set<String> = ["aing", "fox", "aing_gold"]
        for server in [nil, "", "  ", "fox", " fox ", "robot", "ghost", "aing", "aing_gold"] as [String?] {
            for local in ["aing", "fox", "aing_gold"] {
                for migrated in [false, true] {
                    let decision = CharacterSyncDecision.decide(serverID: server, localID: local, migrated: migrated,
                                                                isKnown: known.contains, isUnlocked: unlocked.contains)
                    let value: GoldenJSON
                    switch decision {
                    case .keep: value = ["kind": "keep"]
                    case .adopt(let id): value = ["kind": "adopt", "id": .string(id)]
                    case .migrate(let id): value = ["kind": "migrate", "id": .string(id)]
                    }
                    sync.append(["serverID": Self.s(server), "localID": .string(local), "migrated": .bool(migrated), "decision": value])
                }
            }
        }
        cases.append(["id": "sync-decide", "known": .array(known.sorted().map(GoldenJSON.string)),
                      "unlocked": .array(unlocked.sorted().map(GoldenJSON.string)), "rows": .array(sync)])
        cases.append(["id": "sync-settled", "migrationDefaultsKey": .string(CharacterSyncDecision.migrationDefaultsKey),
                      "selectionDefaultsKey": .string(CharacterSelection.defaultsKey),
                      "rows": .array(([nil, "ok", "not_owned", "unknown_character", "no_profile", "unauthorized", "", "OK"] as [String?]).map {
                          ["status": Self.s($0), "settled": .bool(CharacterSyncDecision.migrationSettled(byStatus: $0))]
                      })])
        goldenEmit(GoldenFile(
            golden: "gacha/character-kit",
            equivalence: .bit,
            swiftSources: ["Sources/CheckCore/CharacterKit/CharacterManifest.swift", "Sources/CheckCore/CharacterKit/SpriteFramePlayer.swift",
                           "Sources/CheckCore/CharacterKit/CharacterSync.swift", "Sources/CheckCore/CharacterKit/CharacterSelection.swift"],
            platformSensitive: false,
            spec: [
                "manifest": "디코드 = 검증. 실패면 그 캐릭터만 건너뛴다(error = CharacterManifestError 갈래 이름, 'decoding' = JSON 모양 오류). 키 변환 없는 기본 디코더",
                "validIds": "isValidID — 글자(그래핌) 1…32, 각 글자가 ASCII 소문자 · 숫자 · 하이픈",
                "frames": "끝 시각은 정수 ms 로 누적해 마지막에 나눈다. 반열린 구간 — 경계면 다음 프레임. 루프면 접고, 아니면 마지막에서 멈춘다. 음수 · 무한 · NaN → 0",
                "sync": "서버 기준 — null/공백 = 기본(아잉). 처음 한 번만 로컬의 비기본 선택을 민다(migrate). 모르거나 안 가진 id 는 아잉으로 접는다",
            ],
            cases: cases
        ))
    }

    // MARK: missions/achievements

    static func missionJSON(_ mission: AchievementStatus.Mission) -> GoldenJSON {
        let state: String
        switch mission.state {
        case .inProgress: state = "inProgress"
        case .claimable: state = "claimable"
        case .claimed: state = "claimed"
        }
        return ["key": .string(mission.key), "series": .string(mission.series), "tier": Self.n(mission.tier), "title": .string(mission.title),
                "detail": .string(mission.detail), "reward": Self.n(mission.reward), "target": Self.n(mission.target),
                "progress": Self.n(mission.progress), "achieved": .bool(mission.achieved), "claimed": .bool(mission.claimed),
                "achievedAtMs": Self.n(mission.achievedAtMs), "claimedAtMs": Self.n(mission.claimedAtMs), "sort": Self.n(mission.sort),
                "isClaimable": .bool(mission.isClaimable), "state": .string(state), "fractionBits": .bits(mission.fraction)]
    }

    static func dailyJSON(_ daily: DailyMissionStatus?, nows: [Int?]) -> GoldenJSON {
        guard let daily else { return .null }
        return [
            "kstDay": Self.s(daily.kstDay), "resetAtMs": Self.n(daily.resetAtMs),
            "missions": .array(daily.missions.map { ["game": .string($0.game), "row": Self.missionJSON($0.row)] }),
            "reportedClaimableCount": Self.n(daily.reportedClaimableCount), "reportedClaimableRuby": Self.n(daily.reportedClaimableRuby),
            "byNow": .array(nows.map { now in
                ["serverNowMs": Self.n(now), "hasRolledOver": .bool(daily.hasRolledOver(serverNowMs: now)),
                 "rows": .array(daily.rows(serverNowMs: now).map { Self.missionJSON($0.row) }),
                 "claimable": .array(daily.claimable(serverNowMs: now).map { .string($0.key) }),
                 "claimableCount": Self.n(daily.claimableCount(serverNowMs: now)),
                 "claimableRuby": Self.n(daily.claimableRuby(serverNowMs: now))]
            }),
        ]
    }

    static func statusJSON(_ status: AchievementStatus) -> GoldenJSON {
        let resetAt = status.daily?.resetAtMs
        let nows: [Int?] = [nil, status.serverNowMs, resetAt.map { $0 - 1 }, resetAt, resetAt.map { $0 + 1 }]
        return [
            "launchAtMs": Self.n(status.launchAtMs),
            "missions": .array(status.missions.map(Self.missionJSON)),
            "reportedClaimableCount": Self.n(status.reportedClaimableCount), "reportedClaimableRuby": Self.n(status.reportedClaimableRuby),
            "claimedNow": .array(status.claimedNow.map { ["key": .string($0.key), "title": .string($0.title), "reward": Self.n($0.reward)] }),
            "rubyBalance": Self.n(status.rubyBalance), "serverNowMs": Self.n(status.serverNowMs),
            "daily": Self.dailyJSON(status.daily, nows: nows),
            "claimable": .array(status.claimable.map { .string($0.key) }),
            "claimableCount": Self.n(status.claimableCount), "claimableRuby": Self.n(status.claimableRuby),
            "seriesRows": .array(status.seriesRows.map { .string($0.key) }),
            "claimedNowRuby": Self.n(status.claimedNowRuby),
        ]
    }

    static let missionFixtures: [String] = [
        "_me/rpc.achievements_status.json", "_me/rpc.achievements_status@demo-all-claimed.json", "_me/rpc.achievements_status@demo-progress.json",
        "_me/rpc.achievement_claim.json", "_me/rpc.achievement_claim@poke10.json", "_me/rpc.achievement_claim@streak14.json",
        "_me/rpc.achievement_claim@todo3.json", "_me/rpc.daily_mission_claim.json", "_me/rpc.daily_mission_claim@daily_gomoku.json",
        "_me/rpc.daily_mission_claim@daily_timing_bar.json", "_me-/rpc.achievements_status.json",
    ]

    static let missionVariants: [(String, String)] = [
        ("empty", #"{}"#),
        ("missions-not-array", #"{"missions":{"key":"a"}}"#),
        ("bad-rows", #"{"missions":[{"key":"a","title":"에이"},{"title":"키 없음"},{"key":"","title":"빈 키"},{"key":"b"},{"key":"c","title":"  "},7,null,{"key":"a","title":"겹침"}]}"#),
        ("lossy-numbers", #"{"missions":[{"key":"n","title":"숫자","tier":"2","reward":"20","target":3.7,"progress":" 5 ","sort":"x","achieved_at_ms":"1789602000000"}],"claimable_count":"1","ruby_balance":12.9,"server_now_ms":"17"}"#),
        ("claimed-by-time", #"{"missions":[{"key":"t","title":"시각","claimed_at_ms":5},{"key":"u","title":"달성 시각","achieved_at_ms":5},{"key":"v","title":"불 깨짐","achieved":"yes","claimed":1}]}"#),
        ("clamps", #"{"missions":[{"key":"c","title":"자르기","reward":-5,"target":0,"progress":99},{"key":"d","title":"음수 진행","target":4,"progress":-2,"claimed":true,"achieved":false}]}"#),
        ("series", #"{"missions":[{"key":"poke100","series":"poke","tier":3,"title":"콕 100","reward":50,"target":100,"progress":60,"sort":70},{"key":"poke10","series":"poke","tier":1,"title":"콕 10","reward":5,"target":10,"progress":60,"achieved":true,"claimed":true,"sort":70},{"key":"poke50","series":"poke","tier":2,"title":"콕 50","reward":20,"target":50,"progress":60,"achieved":true,"sort":70},{"key":"team3","series":"team","tier":2,"title":"팀 3명","reward":200,"target":3,"progress":3,"achieved":true,"claimed":true,"sort":50},{"key":"team2","series":"team","tier":1,"title":"팀 2명","reward":50,"target":2,"progress":3,"achieved":true,"claimed":true,"sort":50},{"key":"solo","series":"","title":"혼자","sort":50}]}"#),
        ("big-ints", #"{"launch_at_ms":9223372036854775807,"ruby_balance":9007199254740993,"missions":[{"key":"b","title":"큰 수","reward":1e3,"sort":1e20}]}"#),
        ("claimed-now", #"{"claimed_now":[{"key":"a","title":"에이","reward":5},{"key":"","title":"빈"},{"title":"키 없음","reward":3},{"key":"b","reward":"7"},{"key":"c","title":"음수","reward":-9}],"missions":[]}"#),
        ("daily-only", #"{"daily":{"kst_day":" 2026-10-22 ","reset_at_ms":1792681200000,"missions":[{"key":"daily_flappy","title":"플래피 한 판","reward":5,"progress":1,"achieved":true,"sort":20},{"key":"daily_timing_bar","game":"","title":"타이밍 바 한 판","reward":5,"sort":10},{"key":"other","title":"게임 없음","claimed":true,"sort":10},{"key":"daily_flappy","title":"겹침","sort":1},{"key":"x"}],"claimable_count":"1"}}"#),
        ("daily-not-object", #"{"daily":"오늘","missions":[{"key":"a","title":"에이"}]}"#),
        ("daily-null", #"{"daily":null}"#),
        ("daily-empty-day", #"{"daily":{"kst_day":"","missions":[]}}"#),
        ("not-object", #"[]"#),
    ]

    @Test("missions/achievements — 도전 · 일일 미션 디코드(관대) · 계열 줄 · 받을 것 · 합치기 · 일일 날 넘김")
    func missionsAchievements() throws {
        var cases: [GoldenJSON] = []
        let decoder = Self.decoder()
        var decoded: [String: AchievementStatus] = [:]
        let inputs = Self.missionFixtures.map { ("fixture-" + $0, Self.fixture("Sources/CheckMobileKit/Demo/Fixtures/me/" + $0)) } + Self.missionVariants
        for (id, text) in inputs {
            do {
                let status = try decoder.decode(AchievementStatus.self, from: Data(text.utf8))
                decoded[id] = status
                cases.append(["id": .string(id), "json": .string(text), "status": Self.statusJSON(status)])
            } catch {
                cases.append(["id": .string(id), "json": .string(text), "throws": true])
            }
        }
        // 합치기: (지난 응답, 이 응답) → 받음이 되돌아가지 않는다. 일일은 같은 kst_day 안에서만.
        let mergePairs: [(String, String, String)] = [
            ("claimed-then-stale",
             #"{"missions":[{"key":"a","title":"에이","achieved":true,"claimed":true,"claimed_at_ms":9,"achieved_at_ms":8},{"key":"b","title":"비","achieved":true}],"daily":{"kst_day":"2026-10-22","missions":[{"key":"daily_chess","title":"체스","achieved":true,"claimed":true,"claimed_at_ms":5,"sort":10}]}}"#,
             #"{"missions":[{"key":"a","title":"에이","achieved":true},{"key":"b","title":"비","achieved":true}],"daily":{"kst_day":"2026-10-22","missions":[{"key":"daily_chess","title":"체스","achieved":true,"sort":10}]}}"#),
            ("new-day",
             #"{"daily":{"kst_day":"2026-10-21","missions":[{"key":"daily_chess","title":"체스","achieved":true,"claimed":true,"sort":10}]}}"#,
             #"{"daily":{"kst_day":"2026-10-22","missions":[{"key":"daily_chess","title":"체스","achieved":true,"sort":10}]}}"#),
            ("unknown-day",
             #"{"daily":{"missions":[{"key":"daily_chess","title":"체스","claimed":true,"sort":10}]}}"#,
             #"{"daily":{"missions":[{"key":"daily_chess","title":"체스","achieved":true,"sort":10}]}}"#),
            ("previous-no-daily",
             #"{"missions":[{"key":"a","title":"에이","claimed":true}]}"#,
             #"{"missions":[{"key":"a","title":"에이"}],"daily":{"kst_day":"2026-10-22","missions":[{"key":"daily_chess","title":"체스","sort":10}]}}"#),
            ("no-previous-claims",
             #"{"missions":[{"key":"a","title":"에이"}]}"#,
             #"{"missions":[{"key":"a","title":"에이","achieved":true}]}"#),
        ]
        for (name, previousText, currentText) in mergePairs {
            let previous = try decoder.decode(AchievementStatus.self, from: Data(previousText.utf8))
            let current = try decoder.decode(AchievementStatus.self, from: Data(currentText.utf8))
            cases.append(["id": .string("merge-\(name)"), "previousJSON": .string(previousText), "currentJSON": .string(currentText),
                          "merged": Self.statusJSON(current.merged(over: previous)),
                          "mergedOverNil": Self.statusJSON(current.merged(over: nil))])
        }
        cases.append(["id": "constants", "keyPrefix": .string(DailyMissionStatus.keyPrefix),
                      "keys": .array(["timing_bar", "flappy", "tetris", "gomoku", "chess", "tetris_duel", "crossy", ""].map {
                          ["game": .string($0), "key": .string(DailyMissionStatus.key(game: $0))]
                      }),
                      "claimFailed": .string(AchievementNoticeText.claimFailed), "claimFailedRow": .string(AchievementNoticeText.claimFailedRow)])
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys]
        cases.append(["id": "requests",
                      "claimKey": .string(String(data: try encoder.encode(AchievementClaimRequest(key: "poke10")), encoding: .utf8)!),
                      "claimAll": .string(String(data: try encoder.encode(AchievementClaimRequest(key: nil)), encoding: .utf8)!)])
        goldenEmit(GoldenFile(
            golden: "missions/achievements",
            equivalence: .bit,
            swiftSources: ["Sources/CheckCore/Achievements.swift", "Sources/CheckCore/DailyMissions.swift"],
            platformSensitive: false,
            spec: [
                "decode": "관대한 디코드 — 최상위가 객체가 아닐 때만 throw. 키나 제목 없는 줄만 버리고 같은 키는 앞의 것만. 숫자 칸은 정수 · 소수(버림, |v| < 9e15) · 글자 숫자(앞뒤 공백 trim)를 받는다. daily 가 객체가 아니면 null(일일 없음)",
                "derived": "claimable · claimableCount · claimableRuby 는 줄에서 센다. seriesRows = 계열마다 한 줄([받기] 있는 가장 낮은 단계 → 안 받은 가장 낮은 단계 → 가장 높은 단계) · 줄 순서는 계열의 가장 작은 sort, 같으면 키",
                "daily": "hasRolledOver = serverNowMs ≥ resetAtMs(둘 중 하나라도 모르면 거짓). 날을 넘긴 응답의 줄은 새 날의 모양(진행 0 · 안 채움 · 안 받음). 줄은 sort 순 · 같으면 키",
                "merge": "받음은 되돌아가지 않는다 — 일일은 같은 kst_day 안에서만(날을 모르면 이 응답 그대로)",
                "ints": "2^53 밖 정수는 \"int:<십진>\" 글자로 싣는다(Int.max = 정렬 꼬리)",
            ],
            cases: cases
        ))
    }
}
