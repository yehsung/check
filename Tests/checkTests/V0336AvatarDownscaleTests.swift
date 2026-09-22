import AppKit
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import check

// MARK: - 아바타 업로드 축소 경로 (v0.3.35 — 메모리 피크 수리)
//
// 2026-09-21 다른 세션의 램 스윕이 넘긴 건: 옛 구현은 `NSImage.tiffRepresentation`(원본 해상도 무압축 TIFF) + 같은 해상도
// `NSBitmapImageRep` 를 동시에 들고 있어서 **피크가 원본 픽셀 수에 비례**했다. ImageIO 썸네일로 바꾼 뒤의 실측(스크래치 벤치,
// 릴리스 빌드, 프로세스당 한 번 · `ru_maxrss`):
//
//   8064×6048 JPEG(28.1MB)   옛 705.1MB → 새 42.3MB   (결과 5,992B → 5,749B · 둘 다 256×192)
//   4000×3000 JPEG(EXIF 6)   옛 235.9MB → 새 19.1MB   (결과 8,436B → 8,325B · 둘 다 192×256 = 회전 적용)
//   300×300 반투명 PNG        옛  22.3MB → 새 13.1MB   (둘 다 256×256 · 투명 자리 흰색)
//   120×90 투명 PNG           옛  19.1MB → 새 12.3MB   (둘 다 120×90 = 확대 없음 · 바이트 동일 2,070B)
//
// 여기서는 **결과 계약**(크기·확대 금지·회전·알파·실패)을 잡고, 피크는 테스트로 직접 재는 대신 "옛 경로가 돌아오면 빨개지는"
// 소스 계약으로 지킨다 — 피크는 프로세스 전체 최대치라 한 스위트 안에서 재면 이웃 테스트의 메모리가 섞인다.

/// 테스트별 임시 폴더. 이름을 UUID 가 아니라 **테스트 신원**에서 뽑는다 — UUID 면 실행마다 $TMPDIR 에
/// 새 폴더가 쌓인다(`CheckTestScratch` 머리 주석). 한 테스트가 폴더를 둘 이상 쓰면 `label` 로 갈라라.
private func v0336TempDirectory(_ label: String = "", function: String = #function) throws -> URL {
    CheckTestScratch.directory(label, function: function)
}

/// 테스트용 이미지 한 장을 파일로 굽는다. `orientation` 을 주면 EXIF 방향을 함께 쓴다(세로 사진 재현).
@discardableResult
private func v0336WriteImage(
    width: Int, height: Int, at url: URL, type: UTType = .png,
    orientation: Int? = nil, alpha: Bool = false
) throws -> URL {
    let info: CGBitmapInfo = alpha
        ? CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        : CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue)
    let context = try #require(CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info.rawValue
    ))
    if !alpha {
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
    }
    // 위쪽 절반에 표식 — 회전이 적용됐는지 색으로 가른다(투명 이미지는 이 표식만 불투명하다).
    context.setFillColor(CGColor(red: 1, green: 0.9, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: CGFloat(height) / 2, width: CGFloat(width), height: CGFloat(height) / 2))
    let image = try #require(context.makeImage())

    let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil))
    var properties: [CFString: Any] = [:]
    if let orientation { properties[kCGImagePropertyOrientation] = orientation }
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    #expect(CGImageDestinationFinalize(destination))
    return url
}

/// 결과 JPEG 의 픽셀 크기.
private func v0336Pixels(_ data: Data) throws -> (width: Int, height: Int) {
    let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    return (image.width, image.height)
}

/// 결과의 위 또는 아래 가장자리 픽셀 색(회전·알파 확인용). `atBottom` 이면 맨 아랫줄을 본다.
private func v0336Color(_ data: Data, atBottom: Bool) throws -> (r: Int, g: Int, b: Int) {
    let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    let context = try #require(CGContext(
        data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ))
    context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height)))
    let pixels = try #require(context.data?.assumingMemoryBound(to: UInt8.self))
    let row = atBottom ? image.height - 1 : 0
    let offset = row * image.width * 4
    return (Int(pixels[offset]), Int(pixels[offset + 1]), Int(pixels[offset + 2]))
}

/// 결과의 왼쪽 위 픽셀 색(회전·알파 확인용).
private func v0336TopLeft(_ data: Data) throws -> (r: Int, g: Int, b: Int) {
    let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    let context = try #require(CGContext(
        data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ))
    context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height)))
    let pixels = try #require(context.data?.assumingMemoryBound(to: UInt8.self))
    return (Int(pixels[0]), Int(pixels[1]), Int(pixels[2]))
}

@Test
func 업로드_사진은_최장변_256으로_줄고_비율을_지킨다() async throws {
    let directory = try v0336TempDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = try v0336WriteImage(width: 2_000, height: 1_000, at: directory.appendingPathComponent("wide.png"))

    let data = try #require(await CheckAvatarView.decodeDownscaledJPEGData(from: url))
    let pixels = try v0336Pixels(data)
    // 순수 계산이 정본이다 — 실제 결과가 그 계약과 같은지 픽셀로 되묻는다.
    let expected = CheckAvatarView.downscaledPixelSize(for: CGSize(width: 2_000, height: 1_000))
    #expect(pixels.width == Int(expected.width) && pixels.height == Int(expected.height),
            "결과 \(pixels) 가 downscaledPixelSize \(expected) 와 다르다")
    #expect(pixels.width == 256 && pixels.height == 128)
}

@Test
func 작은_사진은_키우지_않는다() async throws {
    let directory = try v0336TempDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = try v0336WriteImage(width: 120, height: 90, at: directory.appendingPathComponent("small.png"))

    let data = try #require(await CheckAvatarView.decodeDownscaledJPEGData(from: url))
    let pixels = try v0336Pixels(data)
    #expect(pixels.width == 120 && pixels.height == 90, "작은 사진을 \(pixels) 로 키웠다")
}

@Test
func 세로로_찍은_사진은_누운_채_올라가지_않는다() async throws {
    let directory = try v0336TempDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    // 가로 1000×500 로 저장하되 EXIF 방향 6(오른쪽으로 90°) — 카메라가 세로 사진을 이렇게 쓴다.
    let url = try v0336WriteImage(
        width: 1_000, height: 500, at: directory.appendingPathComponent("portrait.jpg"),
        type: .jpeg, orientation: 6
    )

    let data = try #require(await CheckAvatarView.decodeDownscaledJPEGData(from: url))
    let pixels = try v0336Pixels(data)
    #expect(pixels.height > pixels.width,
            "EXIF 방향을 안 쓰면 \(pixels) 처럼 누운 채로 올라간다(kCGImageSourceCreateThumbnailWithTransform)")
    #expect(pixels.width == 128 && pixels.height == 256)
}

@Test
func 투명한_그림은_검은_바탕이_아니라_흰_바탕으로_굽는다() async throws {
    let directory = try v0336TempDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    // 위쪽 절반만 불투명(노랑), 아래쪽 절반은 완전 투명 — 결과의 왼쪽 위(= 원본 위쪽)가 흰색이어야 한다.
    let url = try v0336WriteImage(
        width: 400, height: 400, at: directory.appendingPathComponent("alpha.png"), alpha: true
    )

    let data = try #require(await CheckAvatarView.decodeDownscaledJPEGData(from: url))
    // 표식(노랑)은 위쪽 절반이므로 **아래쪽**을 본다 — 거기가 완전 투명이었다.
    let transparentArea = try v0336Color(data, atBottom: true)
    let markerArea = try v0336TopLeft(data)
    #expect(transparentArea.r > 200 && transparentArea.g > 200 && transparentArea.b > 200,
            "투명 자리가 \(transparentArea) 로 나왔다 — 얼굴 자리에 검은 바탕이 깔린다")
    #expect(markerArea.b < 120, "표식(노랑)이 사라졌다 — 픽스처가 의도대로 안 구워졌다: \(markerArea)")
}

@Test
func 이미지가_아닌_파일은_조용히_nil_이다() async throws {
    let directory = try v0336TempDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("not-an-image.jpg")
    try Data("사진이 아니다".utf8).write(to: url)

    #expect(await CheckAvatarView.decodeDownscaledJPEGData(from: url) == nil)
    #expect(CheckAvatarView.downscaledJPEGData(from: Data("사진이 아니다".utf8)) == nil)
}

@Test
func 바이트_진입로와_파일_진입로가_같은_결과를_낸다() async throws {
    let directory = try v0336TempDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = try v0336WriteImage(width: 900, height: 600, at: directory.appendingPathComponent("both.png"))

    let fromFile = try #require(await CheckAvatarView.decodeDownscaledJPEGData(from: url))
    let fromData = try #require(CheckAvatarView.downscaledJPEGData(from: try Data(contentsOf: url)))
    #expect(try v0336Pixels(fromFile) == v0336Pixels(fromData))
    #expect(fromFile.count == fromData.count, "같은 그림인데 두 진입로의 결과 크기가 다르다")
}

/// 소스 계약 — 피크는 스위트 안에서 못 재므로(프로세스 최대치라 이웃과 섞인다) **옛 경로가 돌아오면 빨개지게** 못 박는다.
/// 옛 구현의 정체는 `tiffRepresentation`(원본 해상도 무압축) + 같은 해상도 `NSBitmapImageRep` 재드로였다.
@Test
func 축소는_원본_해상도_비트맵을_거치지_않는다() throws {
    let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent()
    let source = try String(contentsOf: root.appendingPathComponent("Sources/check/CheckAvatarView.swift"), encoding: .utf8)
    let code = source.split(separator: "\n", omittingEmptySubsequences: false).map { line -> Substring in
        guard let comment = line.range(of: "//") else { return line }
        return line[..<comment.lowerBound]
    }.joined(separator: "\n")

    #expect(code.contains("CGImageSourceCreateWithURL"), "파일을 Data 로 통째로 읽으면 20MB 사진이 그대로 메모리에 올라온다")
    #expect(code.contains("kCGImageSourceThumbnailMaxPixelSize"), "축소를 ImageIO 에 맡기지 않으면 원본 해상도가 먼저 펼쳐진다")
    #expect(code.contains("kCGImageSourceCreateThumbnailWithTransform"), "EXIF 방향이 빠지면 세로 사진이 눕는다")
    #expect(!code.contains("tiffRepresentation"), "옛 경로가 돌아왔다 — 피크가 원본 픽셀 수에 비례한다(실측 705MB)")
    #expect(!code.contains("NSGraphicsContext(bitmapImageRep:"), "원본 해상도 비트맵 재드로가 돌아왔다")
}
