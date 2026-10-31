import CheckCore
import Foundation
import Testing
@testable import CheckMobileKit

// MARK: - 설정의 이용약관 링크 — 폰 1.0.17
//
// 가입 화면에만 있어 가입 뒤에는 약관을 다시 볼 길이 없었다. 주소는 `CheckAppLinks` 한 곳이다.
@MainActor
@Suite struct V1017TermsLinkTests {
    @Test("주소는 코어 한 곳 · 값은 그대로")
    func address() {
        #expect(CheckAppLinks.termsOfService.absoluteString == "https://yehsung.github.io/check/terms")
        #expect(MeText.termsOfServiceURL == CheckAppLinks.termsOfService)
        #expect(MobileSignUpText.termsURL == CheckAppLinks.termsOfService, "가입 화면과 설정의 약관 주소가 갈렸다")
        #expect(MeText.termsOfService == "이용약관")
    }

    @Test("Sources 전체에서 약관 주소 글자는 CheckAppLinks 에만 있다")
    func literalLivesInOnePlace() throws {
        let hits = try IntegrationContractTests.files(containing: ["yehsung.github.io/check/terms"], under: "Sources")
        #expect(hits == ["Sources/CheckCore/CheckAppLinks.swift"], "약관 주소가 다시 흩어졌다: \(hits)")
    }

    @Test("화면 계약: 설정 끝 묶음에 이용약관 · 처리방침 두 행, 각자 자기 주소를 연다")
    func viewContract() throws {
        let view = try IntegrationContractTests.code("Sources/CheckMobileKit/Me/MeSettingsView.swift")
        #expect(view.contains("legalRow(MeText.termsOfService, url: MeText.termsOfServiceURL"), "이용약관 행이 없다")
        #expect(view.contains("legalRow(MeText.privacyPolicy, url: MeText.privacyPolicyURL"), "처리방침 행이 사라졌다")
        #expect(view.contains("openURL(url)"))
    }
}
