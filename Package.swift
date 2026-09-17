// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "check",
    platforms: [
        .macOS(.v14),
        // B3: 코어는 폰 앱(iOS 18+)과 나눠 쓴다. 맥 앱 타깃은 macOS 에서만 빌드한다.
        .iOS(.v18)
    ],
    products: [
        .executable(name: "check", targets: ["check"]),
        .library(name: "CheckCore", targets: ["CheckCore"]),
        // D1: 폰 앱·위젯 확장이 링크하는 자리 모듈(SPEC-ios §1). 화면 코드는 #if os(iOS) — 맥 빌드에서는 빈 모듈이다.
        .library(name: "CheckMobileShared", targets: ["CheckMobileShared"]),
        .library(name: "CheckMobileKit", targets: ["CheckMobileKit"]),
        .library(name: "CheckWidgetsKit", targets: ["CheckWidgetsKit"])
    ],
    targets: [
        // B3: 맥·폰 공유 코어 — 서버 통신 · 모델 · 실시간 · 세션·키체인 · 오목 · 근무 통계 · 캐릭터 킷 · 토큰 모델 · 할 일 · 게임 규칙.
        // 화면(AppKit·맥 뷰)은 없다. 모듈 사이 접근은 package.
        .target(
            name: "CheckCore"
        ),
        // D1: 폰 앱·위젯 공용(App Group 경로 · 키체인 설정 · 위젯 스냅샷 모델 · 할 일 파일 위치 · 기기 식별자). 플랫폼 무관.
        .target(
            name: "CheckMobileShared"
        ),
        // D1: 폰 스토어(플랫폼 무관 — macOS swift test 로 검증)와 화면(#if os(iOS)). Xcode 앱 타깃(ios/project.yml)은 이 모듈의 public 만 본다.
        .target(
            name: "CheckMobileKit",
            dependencies: ["CheckCore", "CheckMobileShared"],
            // D-base: 데모 모드 픽스처(서버 계약 모양 그대로의 고정 JSON). 읽는 코드(Demo/*.swift)는 #if DEBUG 라 Release 에서
            // 컴파일되지 않는다 — 번들에는 JSON 만 남고 그걸 여는 길이 없다. 탭 작업자는 Demo/Fixtures/<탭>/ 에 더한다.
            resources: [.copy("Demo/Fixtures")]
        ),
        // D1: 위젯 화면 · 타임라인 · AppIntent(#if os(iOS)).
        .target(
            name: "CheckWidgetsKit",
            dependencies: ["CheckCore", "CheckMobileShared"]
        ),
        .executableTarget(
            name: "check",
            dependencies: ["CheckCore"],
            resources: [
                .process("Resources"),
                // 캐릭터는 `.copy` 다: `.process` 는 하위 폴더를 평탄화해서 동명 파일(캐릭터마다 atlas.png)이면 빌드가 죽는다.
                .copy("Characters")
            ]
        ),
        // D-base: 폰 스토어·세션·라우터·실시간 러너 테스트(macOS `swift test --filter CheckMobileKitTests`). 스텁 서버는
        // CheckMobileKit 의 DEBUG 전용 `MobileStubURLProtocol`(호스트별 응답기 · 요청 기록 · 금지 호출 판정)을 쓴다.
        .testTarget(
            name: "CheckMobileKitTests",
            dependencies: ["CheckMobileKit", "CheckMobileShared", "CheckWidgetsKit", "CheckCore"]
        ),
        .testTarget(
            name: "checkTests",
            dependencies: ["check", "CheckCore"],
            // 렌주 판정 코퍼스(JSON)는 테스트가 #filePath 로 직접 읽는다 — 리소스로 묶지 않는다.
            exclude: ["Fixtures"]
        )
    ]
)
