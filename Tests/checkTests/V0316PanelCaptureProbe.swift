import AppKit
import SceneKit
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

/// **실제 오버레이 패널**을 화면에 올려 스프라이트 캐릭터를 캡처한다.
///
/// 게이트는 **파일 스코프**에 둔다 — `@MainActor` 스위트의 static 은 액터 격리라 `@Test` trait 의
/// Sendable 클로저에서 못 읽는다(컴파일 에러).
private let v0316PanelCaptureEnabled =
    ProcessInfo.processInfo.environment["CHECK_V0316_PANEL_CAPTURE"] == "1"

/// 왜 게이트 뒤에 두는가: 이건 검증이 아니라 **눈으로 볼 그림을 굽는 도구**다. 상시 스위트에서 돌면
/// 스위트 한 번마다 사용자 화면에 패널이 뜬다(그 이유로 `CheckPanelVisibility` 가 테스트 중 알파를 0 으로 만든다).
/// ★ **`cacheDisplay` 로는 못 찍는다(실측).** SceneKit 은 Metal 레이어에 그리고 `cacheDisplay` 는 그
/// 레이어를 안 읽는다 — 140×170 그림이 **알파 0.0%** 로 나온다. 처음에 그 길로 갔다가 "파일은 만들어졌다"를
/// 초록으로 착각했다(단언이 `nil` 여부만 봤다). 그래서 지금은 **뷰 계층에서 진짜 `SCNView` 를 찾아
/// `snapshot()`** 을 부르고, **알파 커버리지가 0 이 아님을 단언한다.**
///
///     CHECK_V0316_PANEL_CAPTURE=1 swift test --filter V0316PanelCapture
@MainActor
@Suite("v0.3.15 패널 캡처(게이트)")
struct V0316PanelCaptureProbe {

    /// 뷰 계층에서 첫 `SCNView` 를 찾는다(NSHostingView 안쪽 어디든).
    private func findSCNView(_ view: NSView) -> SCNView? {
        if let scn = view as? SCNView { return scn }
        for sub in view.subviews {
            if let found = findSCNView(sub) { return found }
        }
        return nil
    }

    /// 알파 커버리지 %. 0 이면 아무것도 안 그려진 것이다 — 빈 그림을 초록으로 착각하지 않게 값으로 돌려준다.
    private func alphaCoverage(_ rep: NSBitmapImageRep) -> Double {
        var opaque = 0, total = 0
        for y in stride(from: 0, to: rep.pixelsHigh, by: 3) {
            for x in stride(from: 0, to: rep.pixelsWide, by: 3) {
                total += 1
                if (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05 { opaque += 1 }
            }
        }
        return 100.0 * Double(opaque) / Double(max(total, 1))
    }

    private func capture(_ view: NSView, to path: String) -> (line: String, coverage: Double)? {
        guard let scn = findSCNView(view) else { return nil }
        // SCNView.snapshot() 은 Metal 렌더 결과를 실제로 읽는다(cacheDisplay 와 달리).
        let image = scn.snapshot()
        guard let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return nil }
        try? png.write(to: URL(fileURLWithPath: path))
        let coverage = alphaCoverage(rep)
        return (String(format: "%@ %dx%d 알파 %.1f%%", path, rep.pixelsWide, rep.pixelsHigh, coverage), coverage)
    }

    @Test("스프라이트 캐릭터가 실제 패널에 선다", .enabled(if: v0316PanelCaptureEnabled))
    func spriteStandsInARealPanel() throws {
        let out = "/private/tmp/claude-501/-Users-yesung-check/8963d0f8-fdcd-471a-8c55-8502cb15766e/scratchpad/v0316/panel"
        try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

        var shots: [String: NSBitmapImageRep] = [:]
        for id in ["aing", "shiba", "squirrel"] {
            let catalog = CheckCharacter3DScene.catalog
            let manifest = try #require(catalog.manifest(id: id), "\(id) 가 카탈로그에 없다")
            let engine = ReactionEngine()
            engine.renderActive = true

            // 한 테스트가 캐릭터마다 스위트를 하나씩 만든다 — `id` 가 label 이라 서로 안 겹친다.
            // 이름은 UUID 가 아니라 테스트 신원 + id 에서, 자리는 $TMPDIR(`CheckTestScratch` 머리 주석).
            let defaults = CheckTestScratch.defaults(id)
            defaults.set(id, forKey: CharacterSelection.defaultsKey)

            // 실제 패널 크기 그대로(140×170pt).
            let size = CheckOverlayController.panelSize
            let host = NSHostingView(rootView:
                CheckOverlayCharacterView(elapsedSeconds: 3_600, isActive: true, showsTimer: false,
                                          engine: engine, characterDefaults: defaults)
                    .frame(width: size.width, height: size.height)
            )
            host.frame = NSRect(origin: .zero, size: size)
            let window = NSWindow(contentRect: host.frame, styleMask: [.borderless],
                                  backing: .buffered, defer: false)
            window.isOpaque = false
            window.backgroundColor = .clear
            window.contentView = host
            window.orderFrontRegardless()
            defer { window.orderOut(nil) }

            // SceneKit 이 첫 프레임을 그릴 시간을 준다(렌더 루프가 붙는 데 몇 턴이 필요하다).
            for _ in 0..<40 {
                RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            }
            host.layoutSubtreeIfNeeded()
            let shot = capture(host, to: "\(out)/panel-\(id).png")
            print("[v0316-capture] \(shot?.line ?? "캡처 실패") kind=\(manifest.kind)")
            let result = try #require(shot, "\(id): 패널에서 SCNView 를 못 찾았거나 스냅샷이 실패했다")
            // ★ **여기가 핵심 단언이다.** 파일이 만들어졌다는 것으로는 아무것도 증명되지 않는다 —
            //   처음 판(cacheDisplay)이 정확히 그렇게 빈 그림을 초록으로 통과시켰다.
            #expect(result.coverage > 5.0,
                    "\(id): 패널에 아무것도 안 그려졌다(알파 \(String(format: "%.1f", result.coverage))%)")
            shots[id] = try #require(NSBitmapImageRep(data: Data(contentsOf: URL(
                fileURLWithPath: "\(out)/panel-\(id).png"))))
        }

        // ★ **세 그림이 서로 달라야 한다.** 처음 판은 임시 도메인을 만들어 놓고 뷰에 안 넘겨서
        //   셋 다 아잉을 그렸는데 알파 커버리지가 우연히 똑같아(24.9%) 초록이었다.
        //   "뭔가 그려졌다"가 아니라 "**고른 캐릭터가** 그려졌다"를 재야 한다.
        func centerColumn(_ rep: NSBitmapImageRep) -> [Double] {
            (0..<rep.pixelsHigh).map { rep.colorAt(x: rep.pixelsWide / 2, y: $0)?.alphaComponent ?? 0 }
        }
        let aing = try #require(shots["aing"].map(centerColumn))
        for id in ["shiba", "squirrel"] {
            let other = try #require(shots[id].map(centerColumn))
            let diff = zip(aing, other).map { abs($0 - $1) }.reduce(0, +) / Double(aing.count)
            print("[v0316-capture] \(id) vs aing 중앙열 알파 평균차 \(String(format: "%.4f", diff))")
            #expect(diff > 0.01, "\(id) 가 아잉과 같은 그림이다 — 선택이 뷰까지 안 닿았다")
        }
    }
}
