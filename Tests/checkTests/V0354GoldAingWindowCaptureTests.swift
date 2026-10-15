import AppKit
import ImageIO
import SceneKit
import Testing
@testable import check
@testable import CheckCore

// v0.3.54 — 황금 아잉이 후광을 **실제 투명 창**에서 잰다(아트 위험 1: SceneKit 은 반투명 픽셀을 선형 프리멀티로 적는데,
// 창 합성기가 그것을 sRGB 프리멀티로 읽으면 후광이 시안보다 밝고 넓게 보일 수 있다). 오프스크린 렌더는 바탕을 씬 안에 깔고 그리므로
// 이 문제를 못 본다 — 그래서 우리 프로세스 안에서 테두리 없는 투명 창 하나(+ 그 밑의 불투명 바탕 창)를 띄워 창 서버가 합성한 그림을
// `CGWindowListCreateImage` 로 받아 비교한다.
//
// 규칙: 전역 이벤트·커서·`NSApp.activate` 를 쓰지 않는다. 창은 `ignoresMouseEvents = true` 라 그 사이 사용자의 클릭을 먹지 않고
// (테스트 패널이 클릭을 훔친 사고 — 메모리), 재고 나면 바로 닫는다. 화면을 깜빡이게 하므로 **기본 실행에서는 꺼져 있다** —
// `CHECK_V0354_WINDOW_CAPTURE=1` 일 때만 돈다(미리보기 PNG 는 `CHECK_V0354_MAC_PREVIEW_DIR`).

@MainActor
@Suite struct V0354GoldAingWindowCaptureTests {
    nonisolated static let enabled = ProcessInfo.processInfo.environment["CHECK_V0354_WINDOW_CAPTURE"] != nil
    static let size = CGSize(width: 280, height: 340)

    @Test("실제 투명 창: 금 아잉 후광이 밝은·어두운 바탕 위에서 시안(후광 PNG 를 바탕에 얹은 것)과 같게 보인다 — 보정 없는 후광은 벗어난다",
          .enabled(if: enabled))
    func haloInARealTransparentWindow() throws {
        let front = CGSize(width: 512, height: 512)
        let rawHalo = try #require(GoldAingFinish.resourceURL(GoldAingArt.haloResourceName)
            .flatMap { CGImageSourceCreateWithURL($0 as CFURL, nil) }
            .flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) })
        // 몸 가리개(후광 숨긴 정면 렌더).
        let hidden = try #require(CheckCharacter3DScene.makeScene(animated: false, character: CharacterCatalog.builtInGoldAing))
        hidden.rootNode.childNode(withName: GoldAingFinish.haloNodeName, recursively: true)?.isHidden = true
        let body = try V0354GoldAing3DTests.render(hidden, pointOfView: V0354GoldAing3DTests.frontCamera(for: hidden), size: front)
        for (name, gray) in [("light", 0.95), ("dark", 0.11)] {
            let bg = NSColor(srgbRed: gray, green: gray, blue: gray, alpha: 1)
            let target = try #require(V0354GoldAing3DTests.composite(rawHalo, over: gray))
            let app = try Self.capture(background: bg, size: front, frontCamera: true, rawHalo: nil)
            let raw = try Self.capture(background: bg, size: front, frontCamera: true, rawHalo: rawHalo)
            let appDiff = V0354GoldAing3DTests.meanDiffOutsideBody(app, target, body: body)
            let rawDiff = V0354GoldAing3DTests.meanDiffOutsideBody(raw, target, body: body)
            print(String(format: "[v0354-window] %@ 바탕(실제 창 · 정면 512): 시안과 몸 밖 평균 |ΔRGB| 보정 %.2f · 보정 없음 %.2f", name,
                         appDiff.mean, rawDiff.mean) + " · 최대 \(appDiff.peak) / \(rawDiff.peak)")
            #expect(appDiff.mean < 3, "\(name): 실제 창의 후광이 시안과 평균 \(appDiff.mean) 다르다")
            #expect(rawDiff.mean > appDiff.mean * 2, "\(name): 기준선이 안 갈린다(보정 없음 \(rawDiff.mean))")
            let appCamera = try Self.capture(background: bg, size: Self.size, frontCamera: false, rawHalo: nil)
            if let dir = ProcessInfo.processInfo.environment["CHECK_V0354_MAC_PREVIEW_DIR"] {
                let url = URL(fileURLWithPath: dir)
                Self.writeSideBySide([("시안(후광 PNG 를 바탕에)", target), ("실제 투명 창 · 보정", app), ("실제 투명 창 · 보정 없음", raw)],
                                     background: gray, to: url.appendingPathComponent("gold-window-capture-front-\(name).png"))
                Self.writeSideBySide([("실제 투명 창 · 앱 구도(280×340)", appCamera)],
                                     background: gray, to: url.appendingPathComponent("gold-window-capture-app-\(name).png"))
            }
        }
    }

    // MARK: 창 띄우기 · 캡처

    /// `frontCamera` 면 아트 시안 카메라(정면 · 512 프레임 = 몸 중심 깊이에서 2.0H). `rawHalo` 를 주면 후광 판에 보정 안 한 그림을 붙인다(기준선).
    static func capture(background: NSColor, size: CGSize, frontCamera: Bool, rawHalo: CGImage?) throws -> CGImage {
        let screen = try #require(NSScreen.main)
        // 화면 왼쪽 아래 구석(독·메뉴바와 겹치지 않게 visibleFrame 안).
        let origin = NSPoint(x: screen.visibleFrame.minX + 24, y: screen.visibleFrame.minY + 24)
        let frame = NSRect(origin: origin, size: size)

        let backdrop = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        backdrop.isReleasedWhenClosed = false
        backdrop.backgroundColor = background
        backdrop.isOpaque = true
        backdrop.hasShadow = false
        backdrop.ignoresMouseEvents = true
        backdrop.level = .floating

        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .floating

        // 앱과 같은 SCNView 설정(CheckCharacter3DView.makeNSView): 투명 배경 · 기본 조명 끔 · 2X MSAA.
        let view = SCNView(frame: NSRect(origin: .zero, size: size))
        let scene = try #require(CheckCharacter3DScene.makeScene(animated: false, character: CharacterCatalog.builtInGoldAing))
        if let rawHalo {
            scene.rootNode.childNode(withName: GoldAingFinish.haloNodeName, recursively: true)?.geometry?.firstMaterial?
                .diffuse.contents = rawHalo
        }
        view.scene = scene
        if frontCamera {
            let camera = V0354GoldAing3DTests.frontCamera(for: scene)
            scene.rootNode.addChildNode(camera)
            view.pointOfView = camera
        }
        view.backgroundColor = .clear
        view.allowsCameraControl = false
        view.autoenablesDefaultLighting = false
        view.antialiasingMode = .multisampling2X
        view.rendersContinuously = true
        window.contentView = view

        defer {
            view.rendersContinuously = false
            window.orderOut(nil)
            backdrop.orderOut(nil)
            window.close()
            backdrop.close()
        }
        backdrop.orderFrontRegardless()
        window.order(.above, relativeTo: backdrop.windowNumber)
        // 몇 프레임 그려지고 창 서버에 실릴 때까지 메인 런루프를 돌린다(전역 이벤트 없음).
        let deadline = Date().addingTimeInterval(1.2)
        while Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }

        let windowID = CGWindowID(window.windowNumber)
        // 이 창과 그 아래(= 바로 밑의 불투명 바탕 창)만 — 그 위의 다른 앱 창은 안 들어온다. 바탕 창이 불투명이라 그 아래도 안 비친다.
        // 창 서버 좌표(왼쪽 위 원점 · 주 화면 기준)로 이 창의 자리만 자른다. `.null` 이면 화면 전체가 온다(실측 3840×2160).
        let primaryHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        let rect = CGRect(x: frame.minX, y: primaryHeight - frame.maxY, width: frame.width, height: frame.height)
        let image = CGWindowListCreateImage(rect, [.optionIncludingWindow, .optionOnScreenBelowWindow], windowID,
                                            [.boundsIgnoreFraming, .bestResolution])
        let captured = try #require(image, "창 캡처 실패(CGWindowListCreateImage nil)")
        // 레티나면 2배 — 창 포인트 크기로 맞춘다.
        return try #require(Self.resized(captured, to: size))
    }

    static func resized(_ image: CGImage, to size: CGSize) -> CGImage? {
        let w = Int(size.width), h = Int(size.height)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.interpolationQuality = .high
        // 캡처는 창 크기(포인트 × 배율)다 — 가운데 창 크기 부분만 쓴다(.boundsIgnoreFraming 이라 테두리가 없다).
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    static func writeSideBySide(_ items: [(String, CGImage)], background gray: Double, to url: URL) {
        let pad: CGFloat = 12, label: CGFloat = 26
        let w = items.reduce(pad) { $0 + CGFloat($1.1.width) + pad }
        let h = (items.map { CGFloat($0.1.height) }.max() ?? 0) + label + 2 * pad
        let out = NSImage(size: NSSize(width: w, height: h))
        out.lockFocus()
        NSColor(srgbRed: gray, green: gray, blue: gray, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: w, height: h).fill()
        var x = pad
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 12),
                                                    .foregroundColor: gray < 0.5 ? NSColor.white : NSColor.black]
        for (title, image) in items {
            NSImage(cgImage: image, size: .zero).draw(in: NSRect(x: x, y: pad + label, width: CGFloat(image.width),
                                                                 height: CGFloat(image.height)))
            NSAttributedString(string: title, attributes: attrs).draw(at: NSPoint(x: x, y: pad))
            x += CGFloat(image.width) + pad
        }
        out.unlockFocus()
        guard let tiff = out.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? png.write(to: url)
    }
}
