@testable import CheckCore
import Foundation
import Testing
@testable import CheckMobileKit

// 폰 1.0.18 — 오목알 스킨(주사위 · 고양이 · 픽셀 — 운영 11-10). 맥 0.3.81 과 같은 서버 · 같은 규약.
@MainActor
@Suite(.serialized) struct V1018OmokSkinTests {
    nonisolated static let state = #"{"status":"ok","ruby_balance":150,"equipped":"cat","skins":[{"id":"dice","name":"주사위","price":100,"owned":false,"equipped":false},{"id":"cat","name":"고양이","price":100,"owned":true,"equipped":true},{"id":"pixel","name":"픽셀","price":100,"owned":false,"equipped":false}]}"#

    @Test("읽기: 번호 1 로 묻고 · 줄 셋 · 낀 스킨이 AI 판 내 돌(gomoku.aiStoneSkin)로 · 절이 선다")
    func loadAppliesToAIGame() async throws {
        let harness = await RankMeHarness(label: "v1018-skins-load") { request in
            request.rpcName == "omok_skins_state" ? .json(Self.state) : nil
        }
        defer { harness.tearDown() }
        let store = harness.me
        await store.loadOmokSkins()
        let body = try #require(harness.requests(rpc: "omok_skins_state").last?.jsonBody)
        #expect(body["p_protocol"] as? Int == OmokStoneSkin.protocolVersion && OmokStoneSkin.protocolVersion == 1)
        #expect(store.omokSkins?.rows.map(\.skin) == [.dice, .cat, .pixel])
        #expect(store.showsOmokSkins && store.equippedOmokSkin == .cat && store.isOmokSkinOwned(.cat) && !store.isOmokSkinOwned(.dice))
        #expect(store.context.gomoku.aiStoneSkin == .cat, "낀 스킨이 AI 판 내 돌로 안 갔다")
    }

    @Test("사기: buy_omok_skin 에 스킨 · 번호 · 잔량 반영 · 사면 낀다 · 모자라면 모자란 만큼 · 떠 있는 동안 다시 눌러도 하나")
    func buyAndInsufficient() async throws {
        let reply = BaseLockedBox(#"{"status":"ok","skin":"dice","price":100,"ruby_balance":50,"equipped":"dice"}"#)
        let harness = await RankMeHarness(label: "v1018-skins-buy") { request in
            switch request.rpcName {
            case "omok_skins_state": return .json(Self.state)
            case "buy_omok_skin": return .json(reply.get())
            default: return nil
            }
        }
        defer { harness.tearDown() }
        let store = harness.me
        await store.loadOmokSkins()
        store.buyOmokSkin(.dice)
        store.buyOmokSkin(.dice)
        await harness.quiesceMe()
        let sent = harness.requests(rpc: "buy_omok_skin")
        #expect(sent.count == 1)
        let body = try #require(sent.first?.jsonBody)
        #expect(body["p_skin"] as? String == "dice" && body["p_protocol"] as? Int == 1, "\(body)")
        #expect(store.rubyBalance == 50 && store.isOmokSkinOwned(.dice) && store.equippedOmokSkin == .dice)
        #expect(store.context.gomoku.aiStoneSkin == .dice)
        #expect(store.omokSkinNotice == OmokSkinPhoneText.bought(.dice))
        reply.mutate { $0 = #"{"status":"insufficient","need":100,"have":50}"# }
        store.buyOmokSkin(.pixel)
        await harness.quiesceMe()
        #expect(store.omokSkinNotice == CheckCoreShared.shortfallNotice(need: 100, have: 50))
    }

    @Test("끼기: 가진 스킨 · '일반 돌'(null) 은 set_omok_skin · 이미 낀 것은 요청 없이 안내")
    func equip() async throws {
        let harness = await RankMeHarness(label: "v1018-skins-equip") { request in
            switch request.rpcName {
            case "omok_skins_state": return .json(Self.state)
            case "set_omok_skin": return .json(#"{"status":"ok","equipped":null}"#)
            default: return nil
            }
        }
        defer { harness.tearDown() }
        let store = harness.me
        await store.loadOmokSkins()
        store.equipOmokSkin(.cat)
        #expect(harness.requests(rpc: "set_omok_skin").isEmpty && store.omokSkinNotice == OmokSkinPhoneText.alreadyEquipped(.cat))
        store.equipOmokSkin(nil)
        await harness.quiesceMe()
        let body = try #require(harness.requests(rpc: "set_omok_skin").first?.jsonBody)
        #expect(body.keys.contains("p_skin") && body["p_skin"] is NSNull, "일반 돌은 p_skin null 로 보낸다: \(body)")
        #expect(store.equippedOmokSkin == nil && store.context.gomoku.aiStoneSkin == nil)
        #expect(store.omokSkinNotice == "내 돌을 일반 돌로 바꿨어요")
    }

    @Test("판 그림 배선: 대국 · 결과 · 관전 판이 그 판의 스킨을 받는다 · 돌 그리기는 코어 식 — 주석을 걷고 본다")
    func boardWiring() throws {
        let canvas = try IntegrationContractTests.code("Sources/CheckMobileKit/Games/GamesGomokuBoardCanvas.swift").filter { !$0.isWhitespace }
        #expect(canvas.contains("skin.draw(in:cg,center:c,radius:r,black:color==.black,seed:seed)"))
        #expect(canvas.contains("stoneSkins:match.stoneSkins"))
        let match = try IntegrationContractTests.code("Sources/CheckMobileKit/Games/GamesGomokuMatch.swift").filter { !$0.isWhitespace }
        #expect(match.contains("stoneSkins:match.stoneSkins"))
        let watch = try IntegrationContractTests.code("Sources/CheckMobileKit/Games/GamesGomokuWatch.swift").filter { !$0.isWhitespace }
        #expect(watch.contains("stoneSkins:watch.stoneSkins"))
    }
}
