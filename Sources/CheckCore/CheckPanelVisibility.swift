import Foundation
import MachO

// B3: `CheckOverlayWindow.swift` 에서 화면(AppKit·뷰)과 무관한 규칙·값 타입만 코어로 옮겼다.
// 설명 주석의 큰 줄기(왜 이 값인가)는 원래 파일 머리에 남아 있다.

/// 우리가 만드는 패널을 **테스트 실행 중에만** 사용자 눈에서 지우는 단 하나의 전환 지점.
///
/// 왜 이런 게 필요한가 — 이 코드베이스의 창 검증은 **진짜 NSPanel** 위에서만 성립한다. 프레임 클램프와
/// 화면 가장자리 뒤집힘은 실제 창 기하로 재고(멀티모니터 음수 좌표까지), 울트라는 실제 화면 프레임과
/// 같은지를 보며, 보드 블러는 `orderFrontRegardless` 로 창이 실제로 화면에 올라가야 서는
/// `CABackdropLayer` 를 본다. 즉 "창을 안 만든다 / 안 띄운다"는 선택지가 애초에 없다.
/// 그런데 그대로 두면 `swift test` 한 번마다 사용자 데스크톱이 캐릭터·할 일 보드·전체화면 울트라로
/// 도배된다(실사용 신고 — 전체 스위트를 하루에도 여러 번 돌린다).
///
/// 그래서 **기하는 한 톨도 건드리지 않고 알파만 0** 으로 만든다. 나머지 후보는 실측으로 배제했다:
/// · 화면 밖 좌표로 옮기기 → 클램프·뒤집힘 단언이 통째로 깨진다(그 단언이 이 코드베이스의 핵심 자산이다).
/// · `orderFrontRegardless` 를 테스트에서 건너뛰기 → 창이 화면에 안 올라가면 AppKit 이 백드롭 레이어를
///   세우지 않아 보드 블러 검증(`todoBoardBackdropLayerExistsOnScreen`)이 죽는다.
/// 알파 0 은 **합성 단계에서만** 지운다 — 뷰가 자기 백킹스토어에 그리는 일은 그대로라
/// `cacheDisplay` 픽셀 실측도 살아 있다. 같은 머신에서 알파 1 과 알파 0 을 나란히 재 봤을 때
/// 보드 호스팅 뷰의 중앙 픽셀 알파는 **양쪽 다 0.5686274509803921**, 모서리는 양쪽 다 0.000 이었고
/// 블러 뷰의 `CABackdropLayer` 도 양쪽 다 서 있었다(`panel.isVisible` 도 양쪽 다 true).
///
/// **프로덕션에서는 이 판정이 언제나 false 다.** XCTest 가 로드된 프로세스에서만 참이 되고, 앱 번들에는
/// XCTest 가 없다. 그래서 프로덕션 경로는 예전과 같은 `alphaValue = 1` 을 지난다.
package enum CheckPanelVisibility {
    /// 이 프로세스가 테스트 실행인가. **판정은 여기 한 곳뿐이다** — 프로덕션 코드에 `#if DEBUG` 를
    /// 흩뿌리면 어느 갈래가 배포되는지 아무도 추적하지 못한다.
    ///
    /// 묻는 것은 "테스트 번들이 이 프로세스에 로드되어 있는가" 하나다. 그게 정확히 우리가 알고 싶은
    /// 사실이고, 실행 방식(Xcode / `swift test`)이 바뀌어도 변하지 않는 유일한 표식이다.
    ///
    /// 처음에 쓴 판정 둘은 **실측으로 탈락했다**(같은 머신에서 `swift test` 로 확인):
    /// · `XCTestConfigurationFilePath`/`XCTestBundlePath` 환경변수 → **둘 다 비어 있다**.
    /// · `NSClassFromString("XCTestCase")` → **nil 이다**. SwiftPM 은 swift-testing 을 XCTest 없이
    ///   `swiftpm-testing-helper` 프로세스에서 돌리므로 XCTest 가 아예 안 실려 있다.
    /// 그때 실제로 로드된 이미지는 `…/checkPackageTests.xctest/Contents/MacOS/checkPackageTests` 였다.
    /// 그래서 dyld 이미지 목록에서 `.xctest` 번들을 찾는다. 환경변수 검사는 (Xcode 실행처럼) 값이 있는
    /// 경우의 지름길로만 남긴다 — 없다고 물러나지 않는다.
    ///
    /// 이 판정이 조용히 거짓이 되면 창이 다시 사용자 화면에 뜬다. 그래서 그 순간 빨개지는 테스트를
    /// 함께 두었다(`overlayPanelStaysInvisibleToTheUserWhileTesting` 등이 `isRunningTests` 자체를 단언한다).
    package static let isRunningTests: Bool = {
        let env = ProcessInfo.processInfo.environment
        if env["XCTestConfigurationFilePath"] != nil || env["XCTestBundlePath"] != nil { return true }
        for index in 0..<_dyld_image_count() {
            guard let raw = _dyld_get_image_name(index) else { continue }
            if String(cString: raw).contains(".xctest/") { return true }
        }
        return false
    }()

    /// 프로덕션 패널 알파. **창은 알파를 정하지 않는다** — 보드의 반투명은 블러 뷰가 정하고(형제 배치의
    /// 존재 이유), 창에 알파를 걸면 글자까지 유령이 된다. 그래서 프로덕션 값은 1 로 못 박는다.
    package static let productionAlpha: CGFloat = 1

    /// 이 프로세스가 새로 만드는 패널에 걸 알파.
    package static var panelAlpha: CGFloat { isRunningTests ? 0 : productionAlpha }

}
