@testable import CheckCore
import Foundation
import Testing
@testable import CheckMobileKit

// 폰 1.0.19 — 일일 미션 [모두 받기](맥 0.3.87 · 제보 11-17 서울 "미션 루비 모두 수령" · 대표 #d_xygj8oZRFlfH).
// 받는 길(`claimAllDailyMissions` → `daily_mission_claim(null)`)은 1.0.13 부터 스토어에 있었다(MeDailyMissionStoreTests 가 잰다).
// 1.0.18 까지 없던 것은 **머리의 버튼** 하나다 — 여기서는 문턱(값)과 배선(소스)을 잰다.
@Suite("폰 1.0.19 — 미션 모두 받기")
struct V1019MissionClaimAllTests {
    @Test("문턱: 받을 것이 둘 이상일 때만 [모두 받기] — 하나 · 없음 · 숨김에는 없다(도전 미션 머리와 같은 규칙)")
    func threshold() {
        #expect(MeDailyMissionSection.loaded(rows: [], claimableCount: 2, claimableRuby: 10).showsClaimAll)
        #expect(MeDailyMissionSection.loaded(rows: [], claimableCount: 6, claimableRuby: 30).showsClaimAll)
        #expect(!MeDailyMissionSection.loaded(rows: [], claimableCount: 1, claimableRuby: 5).showsClaimAll)
        #expect(!MeDailyMissionSection.loaded(rows: [], claimableCount: 0, claimableRuby: 0).showsClaimAll)
        #expect(!MeDailyMissionSection.hidden.showsClaimAll)
    }

    @Test("낱말: 맥 0.3.87 과 같은 '모두 받기' — 일일 · 도전 두 머리가 같은 버튼 글자")
    func copy() {
        #expect(MeText.claimAllButton == "모두 받기")
        #expect(MeText.claimAllAccessibility(15) == "모두 받기, 루비 15개")
    }

    @Test("배선: 일일 머리가 문턱 값으로 버튼을 세우고, 누르면 일일 모두 받기 · 떠 있음은 모두 받기 자리 · 보이스오버는 일일 루비 합 — 주석을 걷고 본다")
    @MainActor
    func wiring() throws {
        let views = try IntegrationContractTests.code("Sources/CheckMobileKit/Me/MeDailyMissionViews.swift").filter { !$0.isWhitespace }
        #expect(views.contains("header(claimableCount:claimableCount,showsClaimAll:section.showsClaimAll)"))
        #expect(views.contains("ifshowsClaimAll{claimAllButton}"))
        #expect(views.contains("store.claimAllDailyMissions()"), "일일 머리 버튼이 일일 모두 받기를 부르지 않는다")
        #expect(views.contains("isBusy:store.isClaimingDailyMission(MeStore.achievementClaimAllSlot)"))
        #expect(views.contains("MeText.claimAllAccessibility(store.dailyMissionClaimableRuby)"))
        #expect(!views.contains("store.claimAllAchievements()"), "일일 머리가 도전 미션 모두 받기를 부른다")
    }
}
