// swift-tools-version: 6.0
import PackageDescription

// aing-scan 과 같은 독립 패키지 패턴. 심볼릭 링크로 실제 게임 소스를 공유하되
// 로그인·서버·메뉴바 앱·다른 게임을 빌드하거나 실행하지 않는다.
let package = Package(
    name: "alkkagi",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "AlkkagiPlayground", targets: ["AlkkagiPlayground"])],
    targets: [
        .target(name: "AlkkagiCore"),
        .executableTarget(
            name: "AlkkagiPlayground", dependencies: ["AlkkagiCore"],
            swiftSettings: [.define("ALKKAGI_PLAYGROUND")]
        ),

    ]
)
