// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "check",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "check", targets: ["check"])
    ],
    targets: [
        .executableTarget(
            name: "check",
            resources: [
                .process("Resources"),
                // 캐릭터는 `.copy` 다: `.process` 는 하위 폴더를 평탄화해서 동명 파일(캐릭터마다 atlas.png)이면 빌드가 죽는다.
                .copy("Characters")
            ]
        ),
        .testTarget(
            name: "checkTests",
            dependencies: ["check"],
            // 렌주 판정 코퍼스(JSON)는 테스트가 #filePath 로 직접 읽는다 — 리소스로 묶지 않는다.
            exclude: ["Fixtures"]
        )
    ]
)
