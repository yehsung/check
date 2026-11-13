import CoreGraphics
import Testing
@testable import CheckMobileKit

// 폰 1.0.18 — 긴 확성기는 4줄로 접고 [더 보기](대표 결정 2026-11-10 "…뒤에 내용들 볼 수 있는 버튼을 둬서 그거 누르면 전체 내용으로 뜨게끔").
// 맥 0.3.81 과 같은 글자 · 같은 규칙: 넘칠 때만 단추가 서고, 누르면 같은 자리에서 전체 글로 펼친다. 배너가 바뀌면 다시 접힌다.
@Suite("폰 1.0.18 — 확성기 [더 보기]")
struct V1018MegaphoneMoreTests {
    @Test("넘침 판정: 전체 높이가 접힌 높이보다 크면 단추 · 같거나 작으면 없음 · 아직 못 쟀으면(0) 없음")
    func needsMore() {
        #expect(MegaphoneBannerPhoneRules.needsMore(fullHeight: 120, foldedHeight: 88))
        #expect(!MegaphoneBannerPhoneRules.needsMore(fullHeight: 88, foldedHeight: 88))
        #expect(!MegaphoneBannerPhoneRules.needsMore(fullHeight: 88.3, foldedHeight: 88), "반 pt 미만 차이는 반올림 흔들림이다")
        #expect(!MegaphoneBannerPhoneRules.needsMore(fullHeight: 120, foldedHeight: 0), "접힌 높이를 아직 모르면 단추를 세우지 않는다")
        #expect(MegaphoneBannerPhoneRules.bodyLineLimit == 4)
        #expect(MegaphoneBannerPhoneText.more == "더 보기")
    }

    @Test("배선: 카드가 판정 함수로 단추를 세우고 · 펼치면 줄 제한을 푼다 · 배너마다 새 카드(다시 접힘) — 주석을 걷고 본다")
    @MainActor
    func wiring() throws {
        let overlay = try IntegrationContractTests.code("Sources/CheckMobileKit/Messages/MegaphoneBannerOverlay.swift")
        #expect(overlay.contains("MegaphoneBannerPhoneRules.needsMore(fullHeight: fullHeight, foldedHeight: foldedHeight)"))
        #expect(overlay.contains("AingButton(MegaphoneBannerPhoneText.more"))
        #expect(overlay.contains(".lineLimit(isExpanded ? nil : MegaphoneBannerPhoneRules.bodyLineLimit)"))
        let squashed = overlay.filter { !$0.isWhitespace }
        #expect(squashed.contains("MegaphoneBannerCard(banner:banner,onClose:onClose).id(banner.id)"), "배너가 바뀌어도 펼침이 남는다")
    }
}
