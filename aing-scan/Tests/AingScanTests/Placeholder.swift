import Testing
@testable import aing_scan

/// 판 번호 모양(설치 스크립트가 릴리스 이름으로 쓴다).
@Test
func versionLooksLikeSemver() {
    let parts = AingScanBuild.version.split(separator: ".")
    #expect(parts.count == 3 && parts.allSatisfy { Int($0) != nil })
    #expect(AingScanBuild.sharedCodeAppBuild >= 52)
}
