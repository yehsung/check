import Foundation

/// 이 설치의 앱 정보(빌드 번호 · 버전 · OS · 푸시 환경). 번들에서 한 번 읽고, 테스트·데모는 값을 주입한다.
package struct MobileAppInfo: Sendable, Equatable {
    /// CFBundleVersion(정수, 1부터). `client_release('ios').min_build` 와 비교한다.
    package var build: Int
    /// CFBundleShortVersionString("0.1.0").
    package var version: String
    /// "iOS 18.2" 같은 표시값(제보에 싣는다).
    package var osVersion: String
    /// APNs 환경: Debug 빌드 "sandbox" · Release "production"(Info.plist `AingAPNsEnvironment`). 모르면 nil(토큰을 싣지 않는다).
    package var apnsEnvironment: String?

    package init(build: Int, version: String, osVersion: String, apnsEnvironment: String?) {
        self.build = build
        self.version = version
        self.osVersion = osVersion
        self.apnsEnvironment = apnsEnvironment
    }

    /// Info.plist 키 이름(ios/project.yml 이 빌드 설정 `AING_APNS_ENVIRONMENT` 로 채운다).
    package static let apnsEnvironmentInfoKey = "AingAPNsEnvironment"

    /// 번들 → 정보. 빌드 번호를 못 읽으면 1(개발 빌드) — 폰 최소 빌드 판정은 1 이상에서만 막히므로 개발 중에 갇히지 않는다.
    package static func fromBundle(_ bundle: Bundle = .main, processInfo: ProcessInfo = .processInfo) -> MobileAppInfo {
        let info = bundle.infoDictionary ?? [:]
        let build: Int
        switch info["CFBundleVersion"] {
        case let text as String: build = Int(text.trimmingCharacters(in: .whitespaces)) ?? 1
        case let number as NSNumber: build = number.intValue
        default: build = 1
        }
        let version = (info["CFBundleShortVersionString"] as? String)?.trimmingCharacters(in: .whitespaces) ?? "0.0.0"
        let os = processInfo.operatingSystemVersion
        let osText = "iOS \(os.majorVersion).\(os.minorVersion)" + (os.patchVersion > 0 ? ".\(os.patchVersion)" : "")
        let env = (info[apnsEnvironmentInfoKey] as? String).flatMap { value -> String? in
            let trimmed = value.trimmingCharacters(in: .whitespaces)
            return ["sandbox", "production"].contains(trimmed) ? trimmed : nil
        }
        return MobileAppInfo(build: max(1, build), version: version, osVersion: osText, apnsEnvironment: env)
    }

    /// 제보에 싣는 앱 버전 문자열 "iOS 0.1.0 (1)"(SPEC-ios §3.6).
    package var feedbackAppVersion: String { "iOS \(version) (\(build))" }
}

/// 폰 스토어가 시각을 읽는 **유일한 문**. 데모는 고정 시계(2026-09-17 14:05 KST), 테스트는 조작 가능한 시계를 준다.
package struct MobileClock: Sendable {
    private let provider: @Sendable () -> Date

    package init(_ provider: @escaping @Sendable () -> Date) {
        self.provider = provider
    }

    package func now() -> Date { provider() }

    package static let system = MobileClock { Date() }

    /// 한 순간에 멈춘 시계.
    package static func fixed(_ date: Date) -> MobileClock {
        MobileClock { date }
    }

    /// 데모 기준 시각: 2026-09-17 14:05:00 KST = 05:05:00 UTC.
    package static let demoInstant = Date(timeIntervalSince1970: 1_789_621_500)
}
