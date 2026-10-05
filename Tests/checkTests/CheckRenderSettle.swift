import AppKit
import SwiftUI

/// **같은 입력이면 같은 바이트** — 렌더 테스트 전부가 기대는 그 전제를 참으로 만드는 한 자리.
///
/// ## 왜 필요한가 (2026-10-05 실측)
/// `ImageRenderer` 는 **한 내용의 첫 두 장**을 세 번째 장부터와 **다른 경로로** 굽는다. 1·2장은 서로
/// 바이트까지 같고, 3장째에 화면 **전체**가 채널당 ≤2 로 한 번 바뀐 뒤 그대로 굳는다(828×1034 팝오버에서
/// 10,017 픽셀, maxΔ=2 — 눈에는 안 보이지만 해시는 갈린다). 재현에 앱 코드가 필요 없다:
///
/// ```swift
/// Capsule().fill(LinearGradient(...)).frame(width: 160, height: 44)
///     .shadow(color: .orange.opacity(0.6), radius: 10, y: 2)
/// // 다섯 장: [A, A, B, B, B]
/// ```
///
/// 그림자(블러)를 떼면 이 현상이 사라진다. 비동기가 아니라 **굽는 횟수**가 가르는 것이라 런루프를 1.5초
/// 돌려도 경계가 안 옮겨지고, 내용이 바뀌면 그 내용이 자기 몫의 두 장을 다시 요구한다(메인 화면을 여섯 장
/// 구운 뒤에도 로그인 화면은 자기 1·2장이 따로 달랐다). scale 을 낮춰 싸게 덥히는 것은 **더 나쁘다**
/// (0.25 로 두 장 덥히면 그 뒤 1·2장이 서로도 달라졌다).
///
/// ## 이게 왜 테스트를 거짓말시키는가
/// 비교하는 두 장이 그 경계를 **가로지르면** 아무 의미 없는 ≤2 잡음이 통째로 "차이"가 된다. 대조군
/// (`같은 입력 → 같은 해시`)은 그때 빨개지고, 반대로 부등식(`A ≠ B`)은 **잡음만으로도 초록이 된다** —
/// 뜻이 양쪽으로 다 무너진다. 실제로 팝오버를 한 장 먼저 굽는 테스트를 앞에 세우면
/// `CheckMenuRenderTests.swift:5144` 의 대조군이 **결정적으로** 빨개진다.
///
/// ## 고치는 방향
/// 허용오차를 키워 단언을 낮추지 않는다. **재는 그림 자체를 굳은 상태로 만든다** — 같은 내용을
/// 연속 두 장이 바이트까지 같아질 때까지(최소 세 장) 굽고 그 장을 쓴다. 굳은 뒤에는 몇 장을 더 구워도
/// 같은 바이트라, 이 헬퍼를 통과한 그림끼리는 "같은 입력이면 같은 바이트"가 실제로 참이다.
enum CheckRenderSettle {
    /// 굳었다고 보기 전에 반드시 굽는 최소 장수. 1·2장이 서로 같아 **그 둘만으로는 식은 상태를 못 가른다** —
    /// 세 장째가 있어야 "1·2가 같은 게 식어서인지 굳어서인지"를 가른다.
    static let minimumPasses = 3
    /// 그래도 안 굳으면 멈추는 상한. 여기 걸리면 마지막 장을 그대로 돌려준다 — 조용히 통과시키지 않고
    /// 바이트 단언이 빨개지게 두는 쪽이 맞다(새 비결정성은 숨길 게 아니라 드러낼 일이다).
    static let maximumPasses = 6

    /// 굳은 `NSImage`. 못 구우면 nil.
    @MainActor
    static func nsImage(_ content: some View, scale: CGFloat) -> NSImage? {
        var last: NSImage?
        var lastBytes: Data?
        var passes = 0
        while passes < maximumPasses {
            let renderer = ImageRenderer(content: content)
            renderer.scale = scale
            guard let image = renderer.nsImage else { return nil }
            passes += 1
            let bytes = image.tiffRepresentation
            // 연속 두 장이 같고 최소 장수를 넘겼으면 굳은 것이다.
            if passes >= minimumPasses, let bytes, bytes == lastBytes { return image }
            last = image
            lastBytes = bytes
        }
        return last
    }

    /// 굳은 비트맵(픽셀 비교용). 못 구우면 nil.
    @MainActor
    static func bitmap(_ content: some View, scale: CGFloat) -> NSBitmapImageRep? {
        guard let image = nsImage(content, scale: scale),
              let tiff = image.tiffRepresentation
        else { return nil }
        return NSBitmapImageRep(data: tiff)
    }
}
