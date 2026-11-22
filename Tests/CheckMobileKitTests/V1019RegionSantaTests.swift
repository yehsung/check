@testable import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

// 폰 1.0.19 — 지역 아잉이(부산 갈매기 · 서울의 밤 — 우리 센터 선물, 맥 0.3.85) · 산타 아잉이(크리스마스 선물, 맥 0.3.87).
// 대표 #d_xygj8oZRFlfH "추천안대로 한 판(1.0.19)에 전부"(2번 지역 아잉이 · 8번 산타). 초상 셋을 번들에 실어 능력 번호가 **11** 이 된다.
@MainActor
@Suite("폰 1.0.19 — 지역 · 산타 아잉이(능력 번호 11)", .serialized)
struct V1019RegionSantaTests {
    @Test("번호: 번들 그대로 11 · 산타가 빠지면 10 · 지역 하나만 빠져도 9(산타가 있어도) — 초상 파일 ⟺ 목록 ⟺ 번호")
    func protocolIsEleven() {
        let known = AingCharacterArt.knownIDs
        for id in [CharacterCatalog.busanAingID, CharacterCatalog.seoulAingID, CharacterCatalog.santaAingID] {
            #expect(known.contains(id), Comment(rawValue: "\(id) 가 없다"))
            #expect(AingCharacterArt.portraitURL(id: id, expression: .neutral) != nil && AingCharacterArt.portraitURL(id: id, expression: .negative) != nil,
                    Comment(rawValue: "\(id) 초상이 번들에 없다"))
        }
        let derived = ShopWire.protocolVersion(drawableCharacterIDs: known)
        #expect(derived == ShopWire.santaProtocol)
        #expect(ShopWire.protocolVersion(drawableCharacterIDs: known.filter { $0 != CharacterCatalog.santaAingID }) == ShopWire.regionProtocol)
        #expect(ShopWire.protocolVersion(drawableCharacterIDs: known.filter { $0 != CharacterCatalog.busanAingID }) == ShopWire.devProtocol)
        #expect(ShopWire.protocolVersion(drawableCharacterIDs: known.filter { $0 != CharacterCatalog.seoulAingID }) == ShopWire.devProtocol)
        #expect(ShopWire.supportsRegionGift(protocolVersion: derived))
        #expect(CharacterGiftKind.region.isSupported(protocolVersion: derived) && CharacterGiftKind.santa.isSupported(protocolVersion: derived))
        // 선물 전용(상점 '못 산다')은 코어 한 벌 — 셋 다 선물 전용이다.
        for id in [CharacterCatalog.busanAingID, CharacterCatalog.seoulAingID, CharacterCatalog.santaAingID] {
            #expect(CharacterCatalog.isGiftOnlyBuiltIn(id), Comment(rawValue: "\(id) 가 선물 전용이 아니다"))
        }
    }

    @Test("받는 창 글자: 우리 센터 선물은 그 아잉이의 센터 이름 — \"부산센터 선물 도착!\" · 산타는 맥과 같은 글자")
    func giftCopy() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let busan = #"{"status":"ok","gift":{"id":"g1","kind":"region","options":["aing_busan"],"note":null}}"#
        let busanOffer = try #require(try decoder.decode(CharacterGiftPendingResponse.self, from: Data(busan.utf8)).offer)
        #expect(busanOffer.kind == .region && busanOffer.copy.title == "부산센터 선물 도착!")
        let seoul = #"{"status":"ok","gift":{"id":"g2","kind":"region","options":["aing_seoul"],"note":null}}"#
        let seoulOffer = try #require(try decoder.decode(CharacterGiftPendingResponse.self, from: Data(seoul.utf8)).offer)
        #expect(seoulOffer.copy.title == "서울센터 선물 도착!")
        let santa = #"{"status":"ok","gift":{"id":"g3","kind":"santa","options":["aing_santa"],"note":null}}"#
        let santaOffer = try #require(try decoder.decode(CharacterGiftPendingResponse.self, from: Data(santa.utf8)).offer)
        #expect(santaOffer.kind == .santa && santaOffer.copy == CharacterGiftCopy.santa)
        // 폰 시트는 선물 한 장의 글자(`CharacterGiftOffer.copy`)를 쓴다 — 종류 글자(`kind.copy`)면 "우리 센터"로 나온다.
        let sheet = try IntegrationContractTests.code("Sources/CheckMobileKit/Me/MeStoreCakeGift.swift").filter { !$0.isWhitespace }
        #expect(sheet.contains("packagevarcopy:CharacterGiftCopy{gift.copy}"))
    }

    /// 선물 조회 · 센터 선물 마련을 상자에서 꺼내는 하네스.
    final class RegionServer: @unchecked Sendable {
        let ensure = BaseLockedBox(MobileStubResponse.json(#"{"status":"ok"}"#))
        func respond(_ request: MobileStubRequest) -> MobileStubResponse? {
            switch request.rpcName {
            case "region_gift_ensure": return ensure.get()
            case "character_gift_pending": return .json(#"{"status":"ok","gift":null}"#)
            default: return nil
            }
        }
    }

    @Test("센터 선물 마련: 선물 조회 **전에** region_gift_ensure(p_protocol 11) 한 번 · 같은 세대엔 다시 안 말한다 · 실패하면 다음 조회에 다시")
    func ensureBeforePending() async throws {
        let server = RegionServer()
        let h = await RankMeHarness(label: "v1019-region-ensure") { server.respond($0) }
        defer { h.tearDown() }
        server.ensure.mutate { $0 = .json(#"{"message":"boom"}"#, status: 500) }
        await h.me.loadCakeGift()
        await h.quiesceMe()
        #expect(h.requests(rpc: "region_gift_ensure").count == 1)
        #expect(h.requests(rpc: "character_gift_pending").count == 1, "마련이 실패해도 조회는 그대로 한다")
        // 실패했으니 다음 조회에 다시 말한다.
        server.ensure.mutate { $0 = .json(#"{"status":"ok"}"#) }
        await h.me.loadCakeGift()
        await h.quiesceMe()
        let ensures = h.requests(rpc: "region_gift_ensure")
        #expect(ensures.count == 2)
        #expect(Set(ensures.last?.jsonBody.keys.map { $0 } ?? []) == ["p_protocol"] && ensures.last?.jsonBody["p_protocol"] as? Int == ShopWire.santaProtocol)
        // 순서: 매 조회에서 마련이 먼저다.
        let order = h.requests.compactMap(\.rpcName).filter { $0 == "region_gift_ensure" || $0 == "character_gift_pending" }
        #expect(order == ["region_gift_ensure", "character_gift_pending", "region_gift_ensure", "character_gift_pending"], "\(order)")
        // 성공한 세대에는 다시 말하지 않는다.
        await h.me.loadCakeGift()
        await h.quiesceMe()
        #expect(h.requests(rpc: "region_gift_ensure").count == 2, "같은 세대에 또 말했다")
        #expect(h.requests(rpc: "character_gift_pending").count == 3)
        h.expectNoForbiddenCalls()
    }
}
