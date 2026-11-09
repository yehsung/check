// swift-tools-version: 6.0
import PackageDescription

// aing-scan 과 같은 독립 패키지 패턴. 심볼릭 링크로 실제 게임 소스를 공유하되
// 로그인·서버·메뉴바 앱·다른 게임을 빌드하거나 실행하지 않는다.
//
// 1:1 알까기 v2(SPEC v1.1 §5.10 · 설계 결정 D15): **로컬 연습만** 남긴다. 온라인 스토어 · 와이어 · 창 루트 패널 · 미리보기 서비스 ·
// 온라인 시험은 `exclude:` 로 뺀다(파일 · 심링크는 지우지 않는다 — 온라인 판은 본앱이 판돈 · 순위 · 관전과 함께 그린다).
let package = Package(
    name: "alkkagi",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "AlkkagiPlayground", targets: ["AlkkagiPlayground"])],
    targets: [
        .target(name: "AlkkagiCore", exclude: ["AlkkagiOnlineStore.swift", "AlkkagiOnlineWire.swift"]),
        .executableTarget(
            name: "AlkkagiPlayground", dependencies: ["AlkkagiCore"],
            exclude: ["AlkkagiOnlinePanel.swift", "AlkkagiPreviewService.swift"],
            swiftSettings: [.define("ALKKAGI_PLAYGROUND")]
        ),
        .testTarget(
            name: "AlkkagiTests", dependencies: ["AlkkagiCore", "AlkkagiPlayground"], path: "Tests/AlkkagiTests",
            exclude: ["AlkkagiOnlineTests.swift"],
            swiftSettings: [.define("ALKKAGI_PLAYGROUND")]
        )
    ]
)
