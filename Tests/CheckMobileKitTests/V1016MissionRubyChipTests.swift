import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

// MARK: - 미션 화면 제목 줄 루비 잔량 — 폰 1.0.16
//
// [받기]를 눌러도 그 화면에서 잔량이 오르는 것이 안 보였다. 뷰는 소스 계약으로, 칩이 읽는 값은 진짜 받기 경로로 잰다.
@MainActor
@Suite(.serialized) struct V1016MissionRubyChipTests {
    @Test("칩이 읽는 값: 받기 응답을 받으면 그 자리에서 오른다")
    func claimMovesTheValueTheChipReads() async {
        let harness = await RankMeHarness(label: "v1016-mission-ruby", responder: MeAchievementClaimTests.quietResponder)
        defer { harness.tearDown() }
        let store = harness.me
        harness.enqueue("achievements_status", .json(MeAchievementClaimTests.status(achieved: ["poke10"], ruby: 1_000)))
        await store.loadAchievements()
        #expect(store.rubyBalance == 1_000)
        harness.enqueue("achievement_claim", .json(MeAchievementClaimTests.status(claimed: ["poke10"], ruby: 1_005, claimedNow: ["poke10"])))
        store.claimAchievement(key: "poke10")
        await harness.quiesceMe()
        #expect(store.rubyBalance == 1_005)
    }

    @Test("화면 계약: 제목 줄 오른쪽에 상점과 같은 칩 · 받기 미러를 읽는다 · 누를 곳 없음 · 제목 줄 안이라 화면을 안 늘인다")
    func viewContract() throws {
        let view = try IntegrationContractTests.code("Sources/CheckMobileKit/Me/MeMissionsView.swift")
        let page = try #require(view.range(of: "struct MeMissionsView: View {"))
        let body = view[page.upperBound...]
        let toolbar = try #require(body.range(of: ".toolbar {"), "미션 화면에 도구 막대가 없다")
        let tail = body[toolbar.upperBound...]
        #expect(tail.contains("ToolbarItem(placement: .topBarTrailing)"))
        #expect(tail.contains("RubyBalanceChip(store.rubyBalance, style: .toolbar)"), "상점과 같은 칩 · 같은 값이 아니다")
        let shop = try IntegrationContractTests.code("Sources/CheckMobileKit/Me/MeCharacterViews.swift")
        #expect(shop.contains("RubyBalanceChip(store.rubyBalance, style: .toolbar)"), "상점이 다른 모양으로 갔다 — 두 화면이 갈린다")
    }
}
