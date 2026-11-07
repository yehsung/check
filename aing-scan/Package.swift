// swift-tools-version: 6.0

// 아잉체크 스캐너(aing-scan) — 원격 기계(집 맥 · 리눅스 서버)에 까는 명령줄 집계기.
//
// ★ 토큰을 읽는 코드는 **맥 앱과 같은 파일**이다. Sources/CheckTokenScan 의 .swift 는 전부 ../Sources/CheckCore 로
//   가는 심볼릭 링크이고, AING_SCAN 정의로 앱 전용 부분(화면 스토어 · 계정 프로브)만 빠진다. 그래서 같은 기록이면
//   앱과 숫자가 같다. 이 패키지는 저장소 루트 패키지(맥 앱)와 따로 빌드된다 — 앱 빌드에 의존성을 더하지 않는다.
import PackageDescription

let package = Package(
    name: "aing-scan",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "aing-scan", targets: ["aing-scan"])
    ],
    dependencies: [
        // 리눅스에는 CryptoKit 이 없다 — 같은 API 의 swift-crypto(SHA256 하나만 쓴다). 맥 빌드는 링크하지 않는다.
        .package(url: "https://github.com/apple/swift-crypto.git", "3.0.0"..<"5.0.0")
    ],
    targets: [
        .target(
            name: "CheckTokenScan",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto", condition: .when(platforms: [.linux]))
            ],
            swiftSettings: [.define("AING_SCAN")]
        ),
        .executableTarget(
            name: "aing-scan",
            dependencies: ["CheckTokenScan"]
        ),
        .testTarget(
            name: "AingScanTests",
            dependencies: ["aing-scan", "CheckTokenScan"]
        )
    ]
)
