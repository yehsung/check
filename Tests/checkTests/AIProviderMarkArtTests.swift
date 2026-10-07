import AppKit
import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import SwiftUI
import Testing
@testable import CheckCore

// MARK: - 제공자 마크 — 문양 크기 · 실물 캡처 · 에셋 배달 (v0.3.46)
//
// 이 스위트가 지키는 것은 셋이다.
//  ① **문양이 작아지지 않는다.** 사용자 판정 *"가운데 문양이 원래 더 커"* 로 Claude 0.82 · Codex 0.74 로
//     올렸다. 전에는 제공자와 무관하게 0.6(= `padding(size * 0.2)`)이었다.
//  ② **안티그래비티는 그린 그림이 아니라 캡처다.** 초록 타일 + 흰 A 는 틀린 로고였다(그 초록은 CodexBar
//     메뉴의 악센트색이었다). 실물은 검은 바탕 + 무지개 아치라 코드로 재현하면 또 틀린다 — 그래서
//     **캡처 PNG 바이트가 번들까지 그대로 가는지**를 해시로 잰다.
//  ③ **에셋이 세 타깃에 배달된다.** 그림을 `CheckCore` 리소스로 실었는데(맥·폰·위젯이 다 링크하는 모듈은
//     그것뿐이다), 맥 패키징만은 스크립트가 손으로 복사해야 한다. 그 한 줄이 사라지면 **그림 없는 앱이
//     공증까지 통과**하므로 스크립트를 글자로 잰다.
//
// ⚠️ 소스 계약은 전부 **주석을 걷어낸 뒤** 잰다(안 그러면 설명을 지워야만 초록이 된다).

// MARK: 길잡이

private let apRepoRoot = CheckCoreSourceLayout.repoRoot

private var apAssetURL: URL {
    apRepoRoot.appendingPathComponent("Sources/CheckCore/Resources/ProviderMarks/antigravity.png")
}

private func apSource(_ relative: String) throws -> String {
    apStripComments(try String(contentsOf: apRepoRoot.appendingPathComponent(relative), encoding: .utf8))
}

/// `//` 줄 주석과 `/* */` 블록 주석을 걷어낸다. 문자열 리터럴 안의 `//` 는 남긴다.
private func apStripComments(_ source: String) -> String {
    var result = ""
    var inString = false
    var inLineComment = false
    var inBlockComment = false
    var previous: Character = " "
    let chars = Array(source)
    var index = 0
    while index < chars.count {
        let c = chars[index]
        let next: Character? = index + 1 < chars.count ? chars[index + 1] : nil
        if inLineComment {
            if c == "\n" { inLineComment = false; result.append(c) }
        } else if inBlockComment {
            if c == "*", next == "/" { inBlockComment = false; index += 1 }
        } else if inString {
            if c == "\"", previous != "\\" { inString = false }
            result.append(c)
        } else if c == "/", next == "/" {
            inLineComment = true; index += 1
        } else if c == "/", next == "*" {
            inBlockComment = true; index += 1
        } else if c == "\"" {
            inString = true
            result.append(c)
        } else {
            result.append(c)
        }
        previous = c
        index += 1
    }
    return result
}

/// PNG 머리(IHDR)를 바이트로 읽는다 — 그림 라이브러리를 거치지 않으므로 "진짜 PNG 인가"까지 같이 잰다.
private func apPNGSize(_ data: Data) -> (width: Int, height: Int)? {
    let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
    guard data.count > 24, Array(data.prefix(8)) == signature else { return nil }
    let bytes = [UInt8](data)
    guard bytes[12] == 0x49, bytes[13] == 0x48, bytes[14] == 0x44, bytes[15] == 0x52 else { return nil }   // "IHDR"
    func be32(_ offset: Int) -> Int {
        (Int(bytes[offset]) << 24) | (Int(bytes[offset + 1]) << 16) | (Int(bytes[offset + 2]) << 8) | Int(bytes[offset + 3])
    }
    return (be32(16), be32(20))
}

private func apSHA256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

/// 그림의 한 픽셀을 sRGB 8비트로 읽는다.
private func apPixel(_ url: URL, x: Int, y: Int) throws -> (r: Int, g: Int, b: Int) {
    let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    var buffer = [UInt8](repeating: 0, count: 4)
    let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
    let context = try #require(CGContext(
        data: &buffer, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.draw(image, in: CGRect(x: -x, y: -(image.height - 1 - y), width: image.width, height: image.height))
    return (Int(buffer[0]), Int(buffer[1]), Int(buffer[2]))
}

// MARK: ① 문양 크기 — 더 커졌고, 다시 작아지지 않는다

/// 사용자 판정으로 올린 값. **숫자를 글자로 못 박는다** — 64pt 타일에서 Claude 52.48pt · Codex 47.36pt 이고,
/// 이는 참고 구현본 `claude.svg`/`codex.svg` 의 `scale(0.52480)`/`scale(0.47360)` 과 같은 수다.
@Test func providerMarkScaleMatchesTheApprovedReference() {
    #expect(AIProviderLogoPath.markScale(for: .claude) == 0.82)
    #expect(AIProviderLogoPath.markScale(for: .codex) == 0.74)

    // 64pt 타일로 환산한 값(참고 SVG 의 scale × 100).
    #expect(abs(AIProviderLogoPath.markScale(for: .claude) * 64 - 52.48) < 0.001)
    #expect(abs(AIProviderLogoPath.markScale(for: .codex) * 64 - 47.36) < 0.001)
}

/// **기준선이 실제로 다르다**: 옛 값(제공자 무관 0.6)보다 셋 다 크다. 누군가 `padding(size * 0.2)` 로
/// 되돌리면 여기서 빨개진다 — 숫자만 맞춰 둔 테스트는 되돌림을 못 잡는다.
@Test func providerMarkScaleIsLargerThanTheUniformOldValue() {
    let old: CGFloat = 0.6
    for provider in AILimitProvider.allCases {
        #expect(AIProviderLogoPath.markScale(for: provider) > old,
                "\(provider) 문양이 옛 0.6 보다 작거나 같다 — 사용자가 '더 커야 한다'고 판정한 자리다")
        #expect(AIProviderLogoPath.markScale(for: provider) <= 1.0, "\(provider) 문양이 타일을 넘는다")
    }
    // 제공자마다 다르다 — 한 값으로 뭉치면 Claude 가 다시 작아진다.
    #expect(AIProviderLogoPath.markScale(for: .claude) > AIProviderLogoPath.markScale(for: .codex))
}

/// 타일 뷰가 **그 값을 실제로 쓴다**. 상수만 고치고 뷰가 `padding(size * 0.2)` 를 그대로 두면
/// 위 두 테스트는 초록인 채 화면만 안 바뀐다(모양을 재고 결과를 안 재는 자리).
@Test func providerTileUsesMarkScaleForItsPadding() throws {
    let code = try apSource("Sources/CheckCore/AIProviderLogo.swift")
    #expect(code.contains("AIProviderLogoPath.markScale(for: provider)"),
            "타일이 제공자별 문양 크기를 안 쓴다")
    #expect(!code.contains("padding(size * 0.2)"),
            "타일이 아직 제공자 무관 여백(0.2)을 준다 — 문양이 작아진 그 코드다")
}

// MARK: ② 안티그래비티 — 그린 것이 아니라 캡처다

/// 저장소에 실린 에셋 자체: 진짜 PNG · 256×256 · **원본보다 크게 늘리지 않았다**.
@Test func antigravityAssetIsTheCapturedPNGAtItsOriginalSize() throws {
    let data = try Data(contentsOf: apAssetURL)
    let size = try #require(apPNGSize(data), "PNG 가 아니다(머리 바이트가 안 맞는다)")
    #expect(size.width == 256 && size.height == 256, "캡처 원본 크기(256×256)가 아니다: \(size)")
    #expect(size.width <= 256 && size.height <= 256, "원본(256px)보다 크게 늘렸다")
}

/// 번들까지 **같은 바이트**로 간다. 누가 중간에 다시 그리거나 다시 구우면 해시가 갈린다 —
/// "캡처를 그대로 쓴다"는 지시를 글자가 아니라 바이트로 잰다.
@Test func antigravityArtworkReachesTheBundleByteForByte() throws {
    let bundled = try #require(AIProviderArtwork.antigravityURL,
                               "번들에서 안티그래비티 그림을 못 찾는다 — CheckCore 리소스 배달이 끊겼다")
    let repoBytes = try Data(contentsOf: apAssetURL)
    let bundledBytes = try Data(contentsOf: bundled)
    #expect(apSHA256(bundledBytes) == apSHA256(repoBytes), "번들의 그림이 저장소 캡처와 다른 바이트다")
    #expect(AIProviderArtwork.antigravityImage != nil, "그림을 못 읽었다 — 타일이 벡터로 접힌다")
}

/// 타일이 그 그림을 **실제로 건다**. 그리고 네모 캡처를 둥근 모서리로 자른다(안 자르면 타일 모서리에
/// 검은 직각이 삐져나온다 — 캡처에 알파가 없다).
@Test func providerTileDrawsTheAntigravityCaptureClippedToTheTile() throws {
    let code = try apSource("Sources/CheckCore/AIProviderLogo.swift")
    #expect(code.contains("AIProviderArtwork.antigravityImage"), "타일이 캡처를 안 쓴다")
    #expect(code.contains("clipShape(tileShape)"), "네모 캡처를 둥근 타일로 자르지 않는다")
    // 그라데이션을 코드로 재현하지 않는다 — 한 번 틀렸던 자리다.
    #expect(!code.contains("LinearGradient"), "그라데이션을 코드로 다시 그리고 있다 — 캡처를 써라")
    #expect(!code.contains("googleGreen"), "초록 타일이 돌아왔다 — 그 초록은 로고 색이 아니었다")
}

/// 타일 바탕색이 **캡처의 바탕 픽셀과 같다**. 벡터로 접히는 순간에도 색이 안 튀고, 초록 타일 회귀를 막는다.
///
/// ⚠️ **1 단위 오차를 허용한다.** 캡처는 화면 캡처라 모니터 프로파일(`LG FULL HD`)이 `iCCP` 로 박혀 있어,
/// 파일 바이트는 `#121315`(18,19,21) 인데 ColorSync 가 sRGB 로 옮기면 (17,18,21) 이 된다 — 눈으로는
/// 같은 검정이다. 느슨해진 것이 아니다: 옛 초록(`#34A853`)은 이 허용치의 100배 밖이다.
@Test func antigravityTileColorMatchesTheCaptureBackdrop() throws {
    let corner = try apPixel(apAssetURL, x: 0, y: 0)
    #expect(corner.r < 32 && corner.g < 32 && corner.b < 32, "캡처 바탕이 검정이 아니다: \(corner)")

    let tile = try #require(NSColor(AIProviderPalette.antigravityTile).usingColorSpace(.sRGB))
    let rgb = (r: Int((tile.redComponent * 255).rounded()),
               g: Int((tile.greenComponent * 255).rounded()),
               b: Int((tile.blueComponent * 255).rounded()))
    let drift = abs(rgb.r - corner.r) + abs(rgb.g - corner.g) + abs(rgb.b - corner.b)
    #expect(drift <= 3, "타일 바탕색 \(rgb) 이 캡처 바탕색 \(corner) 과 다르다(차이 \(drift))")

    // 기준선이 실제로 다르다: 옛 구글 초록이었다면 위 단언이 무너진다.
    let green = (r: 0x34, g: 0xA8, b: 0x53)
    #expect(abs(green.r - corner.r) + abs(green.g - corner.g) + abs(green.b - corner.b) > 3,
            "이 검사가 아무 색이나 통과시킨다")
}

// MARK: ③ 에셋 배달 — 세 타깃이 다 본다

/// 그림이 `CheckCore` 리소스로 선언돼 있다. 여기가 **맥·폰·위젯이 다 링크하는 유일한 모듈**이다
/// (`CheckMobileShared` 는 맥이 링크하지 않고 `ios/App/Assets.xcassets` 는 위젯 확장이 못 본다).
/// `.process` 가 아니라 `.copy` 여야 한다 — `.process` 는 하위 폴더를 평탄화한다.
@Test func checkCoreDeclaresTheProviderMarkResources() throws {
    let manifest = try apSource("Package.swift")
    #expect(manifest.contains("name: \"CheckCore\""))
    #expect(manifest.contains(".copy(\"Resources/ProviderMarks\")"),
            "CheckCore 가 제공자 마크 리소스를 선언하지 않는다 — 폰·위젯이 그림을 못 본다")
}

/// 맥 패키징이 그 번들을 앱 안으로 **손으로** 넣는다. 이 한 줄이 사라지면 폰·위젯은 멀쩡한데 맥만
/// 그림이 없고, 버전·심볼·공증 검사는 전부 통과한다(그래서 눈으로는 안 잡힌다).
@Test func macPackagingCopiesTheCheckCoreResourceBundle() throws {
    let script = try String(contentsOf: apRepoRoot.appendingPathComponent("scripts/build-local.sh"), encoding: .utf8)
    let code = script.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }.joined(separator: "\n")
    #expect(code.contains("check_CheckCore.bundle"),
            "scripts/build-local.sh 가 check_CheckCore.bundle 을 앱에 복사하지 않는다")
    #expect(code.contains("check_check.bundle"), "캐릭터 번들 복사가 사라졌다")
    #expect(code.contains("$RES_DIR/"), "번들을 Contents/Resources 가 아닌 곳에 넣는다")
}

/// 번들을 못 찾아도 **죽지 않는다**. `Bundle.module` 의 `fatalError` 를 쓰면 복사 한 줄을 빠뜨린
/// 배포본이 리밋 카드를 여는 순간 앱째로 죽는다.
@Test func artworkLookupNeverCrashesWhenTheBundleIsMissing() throws {
    let code = try apSource("Sources/CheckCore/AIProviderLogo.swift")
    #expect(!code.contains("Bundle.module"), "Bundle.module 은 못 찾으면 fatalError 다 — 직접 훑어라")
    #expect(!code.contains("fatalError"), "그림이 없다고 앱을 죽이지 않는다")
    // 그림이 없을 때 벡터로 접는 갈래가 실제로 있다.
    #expect(code.contains("if provider == .antigravity, let artwork = AIProviderArtwork.antigravityImage"),
            "그림이 없을 때 벡터로 접는 갈래가 없다")
}

// MARK: ④ 틴트 모드 — 색을 버려도 셋이 갈린다

/// 위젯 틴트는 색을 통째로 버리고 `AIProviderMark` **벡터**만 그린다. 안티그래비티가 캡처로 바뀐 뒤에도
/// 벡터 셋이 남아 있어야 하고, 셋의 실루엣이 **서로 달라야** 한다(같으면 틴트에서 세 줄이 똑같아진다).
@Test func tintSilhouettesStayDistinctAfterTheCaptureSwap() {
    let box = CGRect(x: 0, y: 0, width: 100, height: 100)
    var shapes: [AILimitProvider: String] = [:]
    for provider in AILimitProvider.allCases {
        let path = AIProviderLogoPath.path(for: provider, in: box)
        #expect(!path.isEmpty, "\(provider) 틴트 실루엣이 비었다")
        shapes[provider] = path.description
    }
    #expect(Set(shapes.values).count == AILimitProvider.allCases.count, "틴트 실루엣이 서로 같다")

    // 잉크가 타일을 적당히 덮는다 — 한 점으로 쪼그라들면 '구분된다'가 공허해진다.
    for (provider, _) in shapes {
        let bounds = AIProviderLogoPath.path(for: provider, in: box).boundingRect
        #expect(bounds.width > 50 && bounds.height > 50, "\(provider) 실루엣이 너무 작다: \(bounds)")
    }
}

// MARK: ⑤ 실제로 구운 픽셀 — 문양이 커졌고, 아치가 무지개다
//
// 상수와 소스 계약만으로는 **화면**을 증명하지 못한다(모양을 재고 결과를 안 재는 자리). 여기서는 타일을
// 진짜로 구워서 잉크를 잰다. PNG 는 `CHECK_SNAPSHOT_DIR/provider-marks/` 에 남는다 — 사람이 직접 연다.
//
// ★ 굽기는 `CheckRenderSettle` 을 거친다. `ImageRenderer` 는 **첫 두 장을 다르게** 굽는다(채널당 ≤2).

/// 밝은 잉크(흰 마크) 픽셀의 경계 상자 비율 — 타일 한 변 대비.
///
/// ⚠️ **거의 투명한 픽셀을 버린다.** 타일은 둥근 사각이라 모서리 바깥이 투명한데, 그 가장자리의
/// alpha≈0 픽셀을 되돌려 곱하면 `(255,255,0)` 같은 **노란 쓰레기 색**이 나온다(실측: 44pt 타일의
/// 잉크 상자가 0.66 대신 0.89 로 잡혔다). 알파를 안 보면 둥근 모서리를 "흰 문양"으로 센다.
private func apInkBoxRatio(_ bitmap: NSBitmapImageRep, threshold: Int = 200) -> (w: Double, h: Double) {
    var minX = bitmap.pixelsWide, maxX = -1, minY = bitmap.pixelsHigh, maxY = -1
    for y in 0..<bitmap.pixelsHigh {
        for x in 0..<bitmap.pixelsWide {
            guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
            guard color.alphaComponent > 0.9 else { continue }
            let lum = Int((0.299 * color.redComponent + 0.587 * color.greenComponent + 0.114 * color.blueComponent) * 255)
            guard lum >= threshold else { continue }
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        }
    }
    guard maxX >= minX, maxY >= minY else { return (0, 0) }
    return (Double(maxX - minX + 1) / Double(bitmap.pixelsWide), Double(maxY - minY + 1) / Double(bitmap.pixelsHigh))
}

/// 8×8 칸마다 "잉크가 있었나" — 실루엣 지문. 색을 버려도 모양이 갈리는지 재는 데 쓴다.
private func apInkSignature(_ bitmap: NSBitmapImageRep, threshold: Int = 128) -> [Bool] {
    var cells = [Bool](repeating: false, count: 64)
    for y in 0..<bitmap.pixelsHigh {
        for x in 0..<bitmap.pixelsWide {
            guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
            guard color.alphaComponent > 0.9 else { continue }
            let lum = Int((0.299 * color.redComponent + 0.587 * color.greenComponent + 0.114 * color.blueComponent) * 255)
            guard lum >= threshold else { continue }
            let cx = min(7, x * 8 / bitmap.pixelsWide)
            let cy = min(7, y * 8 / bitmap.pixelsHigh)
            cells[cy * 8 + cx] = true
        }
    }
    return cells
}

@MainActor
private func apRenderTile(_ provider: AILimitProvider, size: CGFloat) throws -> NSBitmapImageRep {
    try #require(CheckRenderSettle.bitmap(AIProviderTile(provider: provider, size: size).fixedSize(), scale: 3))
}

/// 세 마크를 20·26·44pt 로 구워 남기고, **Claude·Codex 의 흰 문양이 실제로 커졌는지** 픽셀로 잰다.
///
/// 문턱은 손으로 적은 숫자가 아니라 **옛값과 새값 사이**에서 나온다. 잉크 상자는 `markScale × 패스 자체의
/// 잉크 비율`이므로, 옛 여백(제공자 무관 0.6)으로 구운 잉크와 지금 값으로 구운 잉크는 제공자마다 다른 두
/// 숫자가 된다(실측 — Claude 0.48 → 0.66, Codex 0.49 → 0.58). 그 사이 40% 지점을 문턱으로 삼는다:
/// 되돌리면 반드시 빨개지고, 자잘한 반올림으로는 안 흔들린다.
@MainActor
@Test func renderedTilesShowTheEnlargedMarks() throws {
    let designBox = CGRect(x: 0, y: 0, width: 100, height: 100)
    for size in [CGFloat(20), 26, 44] {
        for provider in AILimitProvider.allCases {
            let bitmap = try apRenderTile(provider, size: size)
            MiniGameSnapshots.save(bitmap, name: "tile-\(provider)-\(Int(size))pt.png", sub: "provider-marks")
            #expect(bitmap.pixelsWide == Int(size * 3), "\(provider) \(size)pt 타일 크기가 틀리다")

            guard provider != .antigravity else { continue }   // 캡처는 흰 실루엣이 아니다 — 아래에서 따로 잰다.
            let ink = apInkBoxRatio(bitmap)
            let pathInk = AIProviderLogoPath.path(for: provider, in: designBox).boundingRect.width / 100
            let now = AIProviderLogoPath.markScale(for: provider) * pathInk
            let old = 0.6 * pathInk                                   // 제공자 무관 `padding(size * 0.2)` 시절
            let floor = old + (now - old) * 0.4
            #expect(Double(floor) > Double(old) + 0.02, "기준선이 같다 — 이 문턱은 아무것도 안 가른다")
            #expect(ink.w > Double(floor) && ink.h > Double(floor),
                    "\(provider) \(size)pt 문양이 작다(가로 \(ink.w) 세로 \(ink.h), 문턱 \(floor)) — 옛 0.6 여백으로 되돌아갔다")
            #expect(ink.w < Double(now) + 0.04 && ink.h < Double(now) + 0.04,
                    "\(provider) \(size)pt 문양이 설계값(\(now))보다 크다 — 실측 가로 \(ink.w) 세로 \(ink.h)")
        }
    }
}

/// 안티그래비티 타일이 **검은 바탕 + 무지개 아치**다. 옛 초록 타일 + 흰 A 는 파랑도 주황도 없어 빨개진다.
@MainActor
@Test func renderedAntigravityTileIsTheBlackRainbowCapture() throws {
    let bitmap = try apRenderTile(.antigravity, size: 44)
    MiniGameSnapshots.save(bitmap, name: "tile-antigravity-44pt-probe.png", sub: "provider-marks")

    let corner = try #require(bitmap.colorAt(x: bitmap.pixelsWide / 2, y: 2)?.usingColorSpace(.sRGB))
    #expect(corner.brightnessComponent < 0.2, "위쪽 바탕이 검정이 아니다 — 초록 타일이 돌아왔다")

    var blueish = 0
    var warm = 0
    for y in 0..<bitmap.pixelsHigh {
        for x in 0..<bitmap.pixelsWide {
            guard let c = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), c.alphaComponent > 0.9 else { continue }
            let r = Int(c.redComponent * 255), b = Int(c.blueComponent * 255)
            if b - r > 60 { blueish += 1 }
            if r - b > 60 { warm += 1 }
        }
    }
    #expect(blueish > 200, "파란 아치 다리가 없다(\(blueish)픽셀)")
    #expect(warm > 100, "주황·빨강 꼭대기가 없다(\(warm)픽셀) — 그라데이션이 아니다")
}

/// 틴트 모드가 그리는 **벡터 실루엣** 셋이 구워 놓고 봐도 서로 다르다(색을 버려도 갈린다).
@MainActor
@Test func renderedTintSilhouettesAreDistinguishable() throws {
    var signatures: [AILimitProvider: [Bool]] = [:]
    for provider in AILimitProvider.allCases {
        let silhouette = AIProviderMark(provider)
            .fill(Color.white)
            .frame(width: 44, height: 44)
            .background(Color.black)
        let bitmap = try #require(CheckRenderSettle.bitmap(silhouette.fixedSize(), scale: 3))
        MiniGameSnapshots.save(bitmap, name: "tint-\(provider)-44pt.png", sub: "provider-marks")
        let signature = apInkSignature(bitmap)
        #expect(signature.filter { $0 }.count >= 8, "\(provider) 실루엣 잉크가 거의 없다")
        signatures[provider] = signature
    }
    let distinct = Set(signatures.values.map { $0.map { $0 ? "1" : "0" }.joined() })
    #expect(distinct.count == AILimitProvider.allCases.count,
            "틴트 실루엣 지문이 겹친다 — 색을 버리는 모드에서 세 줄이 똑같아진다")
}
