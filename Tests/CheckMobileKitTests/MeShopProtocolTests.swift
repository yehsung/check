import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

/// 폰이 상점 RPC 에 싣는 능력 번호(v0.3.43 로봇).
///
/// ★ **이 스위트의 존재 이유**: `fetchShopState`·`buyCharacter` 는 맥과 폰이 **공유한다**(CheckCore).
///   코어에 1 을 박으면 그림이 없는 폰도 1 을 보내고, 서버는 robot 카드를 내려 보낸다 — 폰은 모르는 id 를
///   아잉으로 접으므로 **"아잉을 또 파는" 카드**가 뜨고, 사면 루비만 빠진다(mapC §7 ③ 실측).
///   그래서 번호는 "이 번들에 그림이 있는가"에서 파생되고, 여기서 그 동치를 **양방향으로** 못 박는다.
///
/// ★★ **순수 함수 반환값만 재면 전선을 안 잰다.** 그 모양이던 동안, 폰 호출부에
///   `protocolVersion: ShopWire.robotProtocol` 을 더해도(= 초상 없이 1 을 보내는, B16 과 mapC §7 ③④ 가 막으려는
///   바로 그 상태) 스위트가 **완전 초록**이었다(실측 33건). 그래서 아래 §전선 절은 `MeStore` 의 진짜 경로
///   (`loadShop()`·`confirmPurchase()`)를 스텁 세션으로 돌려 **나간 본문을 JSON 으로 연다**.
@Suite struct MeShopProtocolTests {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// 기준선은 `knownIDs` 가 아니라 **번들에 실릴 초상 파일**이다(같은 목록으로 기대값을 만들면 영원히 초록이다).
    /// 파일은 `Package.swift` 의 `.copy("Resources/Portraits")` 로 폰·위젯 번들에 그대로 간다.
    static var robotPortraitExists: Bool {
        FileManager.default.fileExists(atPath: root
            .appendingPathComponent("Sources/CheckMobileShared/Resources/Portraits/robot-neutral.png").path)
    }

    static let shopState = #"{"ruby_balance":400,"characters":[{"id":"fox","price":30,"owned":false}]}"#

    @Test("폰이 보내는 번호는 번들 초상이 있을 때만 1 이다 — 양방향")
    func phoneProtocolTracksBundledPortraits() {
        let known = AingCharacterArt.knownIDs
        let derived = ShopWire.protocolVersion(drawableCharacterIDs: known)

        // 필요충분: 초상 파일이 있다 ⟺ 1 을 보낸다. (둘 중 하나만 고치면 빨개진다 — 그게 이 단언의 일이다.)
        #expect((derived == ShopWire.robotProtocol) == Self.robotPortraitExists,
                Comment(rawValue: "초상 \(Self.robotPortraitExists) · 목록 \(known) → \(derived)"))
        #expect(known.contains(ShopWire.robotCharacterID) == Self.robotPortraitExists,
                "번들 초상과 knownIDs 가 갈렸다 — 목록에만 있으면 아잉이 그려지고, 파일만 있으면 아무도 못 본다")
    }

    /// ★ **지금 폰 값은 0 이어야 한다.** 그림이 아직 없다 — 0 이 아니면 폰 상점에 "아잉 그림 + robot 이름" 카드가
    ///   뜨고 그걸 살 수 있다. 그림이 들어오는 날 이 한 줄이 빨개지고, 그게 "폰도 1 을 보내도록 배선하라"는 신호다.
    @Test("그림이 없는 지금, 폰은 0 을 보낸다")
    func phoneStillSendsLegacyProtocol() {
        guard !Self.robotPortraitExists else {
            // 그림이 들어왔다 = 모바일 세션이 배선할 차례다. 조용히 통과시키지 않고 사실을 적는다.
            #expect(ShopWire.protocolVersion(drawableCharacterIDs: AingCharacterArt.knownIDs)
                    == ShopWire.robotProtocol,
                    "robot 초상이 번들에 들어왔는데 폰이 아직 0 을 보낸다 — knownIDs 에 robot 을 더해라")
            return
        }
        #expect(ShopWire.protocolVersion(drawableCharacterIDs: AingCharacterArt.knownIDs)
                == ShopWire.legacyProtocol)
        #expect(AingCharacterArt.knownIDs.contains("robot") == false)
    }

    // MARK: - 전선 — 폰의 진짜 경로가 실제로 내보내는 본문

    /// ★ **P0 그물.** 호출부가 무엇을 넘기든 재던 스위트가 모르던 자리다. 여기서는 번들 상태에 기대지 않고
    ///   `drawableCharacterIDs` 에 가짜 명단을 꽂아 `loadShop()`·`confirmPurchase()` 를 **양쪽 분기로** 돌린다.
    ///
    ///   물리는 변형(실측): 두 호출부에 `protocolVersion: ShopWire.robotProtocol` 을 박기(변형 F) ·
    ///   호출부에서 `protocolVersion:` 을 지우기(= 그림이 들어온 뒤에도 아무도 robot 을 못 본다) ·
    ///   목록만 1, 구매는 0(= 목록엔 뜨는데 누르면 "앱을 업데이트하면 살 수 있어요" — B12 의 '게이트가 장식').
    @MainActor
    @Test("폰도 목록·구매 두 호출부가 같은 번호를 전선에 싣는다 — 명단에 robot 이 있는 쪽·없는 쪽 둘 다")
    func bothPhoneCallSitesCarryTheSameProtocol() async throws {
        for (label, drawable, expected) in [
            ("draws", ["aing", "fox", "robot"], ShopWire.robotProtocol),
            ("blind", ["aing", "fox"], ShopWire.legacyProtocol)
        ] {
            let harness = await RankMeHarness(label: "me-shop-protocol-\(label)") { request in
                switch request.rpcName {
                case "shop_state": return .json(Self.shopState)
                case "buy_character": return .json(#"{"status":"ok","character":"fox","price":30,"ruby_balance":370}"#)
                default: return nil
                }
            }
            defer { harness.tearDown() }
            let store = harness.me
            store.drawableCharacterIDs = drawable
            #expect(store.shopProtocolVersion == expected,
                    Comment(rawValue: "\(label): 명단 \(drawable) → \(store.shopProtocolVersion)"))

            await store.loadShop()
            let list = try #require(harness.requests(rpc: "shop_state").last?.jsonBody)
            if expected == ShopWire.robotProtocol {
                #expect(Set(list.keys) == ["p_protocol"], Comment(rawValue: "목록 본문 \(list)"))
                #expect(list["p_protocol"] as? Int == 1, Comment(rawValue: "목록 본문 \(list)"))
            } else {
                // 0 은 키를 **아예 싣지 않는다** — 아직 안 올라간 서버에서 공짜로 404 를 맞지 않으려고.
                #expect(list.isEmpty, Comment(rawValue: "목록 본문 \(list)"))
            }

            store.selectShopItem("fox")
            #expect(store.canConfirmPurchase, "고르고도 살 수 없다 — 픽스처 잔량·가격을 확인해라")
            store.confirmPurchase()
            #expect(await baseWaitUntil { store.purchasingID == nil }, "구매가 안 끝났다")
            let buy = try #require(harness.requests(rpc: "buy_character").last?.jsonBody)
            #expect(buy["p_id"] as? String == "fox", Comment(rawValue: "구매 본문 \(buy)"))
            if expected == ShopWire.robotProtocol {
                #expect(Set(buy.keys) == ["p_id", "p_protocol"], Comment(rawValue: "구매 본문 \(buy)"))
                #expect(buy["p_protocol"] as? Int == 1,
                        Comment(rawValue: "구매 본문 \(buy) — 목록 1·구매 0 이면 게이트가 장식이다"))
            } else {
                #expect(Set(buy.keys) == ["p_id"], Comment(rawValue: "구매 본문 \(buy)"))
            }
        }
    }

    /// ★ **지금 출하되는 폰이 전선에 내보내는 본문**. 위 테스트는 가짜 명단이고, 이쪽은 **번들 그대로**다 —
    ///   그림이 없는 동안은 `{}`, 초상이 폰 번들에 들어오면 `{"p_protocol":1}` 로 **저절로 뒤집힌다**
    ///   (뒤집히지 않으면 `knownIDs` 가 안 갱신됐다는 뜻이고, 위 §양방향 단언이 그걸 말해 준다).
    @MainActor
    @Test("번들 그대로의 폰이 보내는 본문 — 초상이 없으면 `{}`")
    func shippedPhoneBodyFollowsTheBundle() async throws {
        let harness = await RankMeHarness(label: "me-shop-protocol-bundle") { request in
            request.rpcName == "shop_state" ? .json(Self.shopState) : nil
        }
        defer { harness.tearDown() }
        await harness.me.loadShop()
        let list = try #require(harness.requests(rpc: "shop_state").last?.jsonBody)
        #expect(list.isEmpty == !Self.robotPortraitExists, Comment(rawValue: "본문 \(list)"))
        #expect((list["p_protocol"] as? Int == ShopWire.robotProtocol) == Self.robotPortraitExists,
                Comment(rawValue: "본문 \(list) · 초상 \(Self.robotPortraitExists)"))
    }
}
