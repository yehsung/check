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
        .library(name: "CheckCore", targets: ["CheckCore"])
    ],
    targets: [
        // B3: 맥·폰 공유 코어 — 서버 통신 · 모델 · 실시간 · 세션·키체인 · 오목 · 근무 통계 · 캐릭터 킷 · 토큰 모델 · 할 일 · 게임 규칙.
        // 화면(AppKit·맥 뷰)은 없다. 모듈 사이 접근은 package.
        .target(
            name: "CheckCore"
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
        .testTarget(
            name: "checkTests",
            dependencies: ["check", "CheckCore"],
            // 렌주 판정 코퍼스(JSON)는 테스트가 #filePath 로 직접 읽는다 — 리소스로 묶지 않는다.
            exclude: ["Fixtures"]
        )
    ]
)
