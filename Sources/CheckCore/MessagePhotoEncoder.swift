import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// MARK: - 그림 줄이기 (아바타 · 메시지 사진이 같이 쓰는 몸통)
//
// 아바타(`CheckAvatarView.downscaledJPEGData` — 256px)가 쓰던 ImageIO 몸통을 **여기로 옮겨 일반화했다**(2026-11-11, 메시지 사진 1600px).
// 규칙은 그때 그대로다 — 그 주석(CheckAvatarView "왜 ImageIO 썸네일인가")의 실측이 근거다:
//  · 원본 해상도 비트맵을 거치지 않는다(`CGImageSourceCreateThumbnailAtIndex` 가 축소본을 직접 만든다 — 피크가 한 자릿수 MB).
//  · EXIF 방향을 적용한다(`kCGImageSourceCreateThumbnailWithTransform` — 세로 사진이 눕지 않게).
//  · 박힌 EXIF 썸네일(작고 거칠다)을 쓰지 않는다(`kCGImageSourceCreateThumbnailFromImageAlways`).
//  · 키우지 않는다(`kCGImageSourceThumbnailMaxPixelSize` 는 확대하지 않는다).
//  · 투명을 흰 바탕에 **명시해서** 깐다(JPEG 에는 알파가 없고, `CGImageDestination` 은 알파를 어떻게 버릴지 보장하지 않는다).
//  · **메타데이터를 옮기지 않는다** — 그린 그림(CGImage)만 넣고 원본 속성(GPS · 카메라 · 날짜)은 안 싣는다.
// 폰도 같은 처방이다(`MeAvatarImage`) — 같은 사진이 맥과 폰에서 다르게 올라가지 않게.

/// 그림 줄이기의 순수 몸통(아바타 · 메시지 사진 공용).
package enum ImageDownscale {
    /// 최장변 `maxPixelSize` 로 비율 유지 축소(키우지 않음) · EXIF 방향 적용 · 본 이미지에서 만든다. 그림이 없는 소스면 nil.
    package static func thumbnail(from source: CGImageSource, maxPixelSize: Int) -> CGImage? {
        guard CGImageSourceGetCount(source) > 0 else { return nil }
        let options: [CFString: Any] = [
            // 박혀 있는 EXIF 썸네일(작고 거칠다)을 쓰지 않고 본 이미지에서 만든다.
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixelSize),
            kCGImageSourceShouldCacheImmediately: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// 투명이 검게 올라가지 않게 흰 바탕에 한 번 그린다(알파 없는 sRGB 비트맵). 축소본 크기에서만 도는 그리기라 비용이 작다.
    package static func flattenedOnWhite(_ image: CGImage) -> CGImage? {
        guard let context = CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }

    /// 그린 그림 → JPEG(품질 `quality`). **속성은 품질 하나뿐이다** — 원본 메타데이터를 싣지 않는다.
    package static func jpegData(_ image: CGImage, quality: CGFloat) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    /// 한 번에: 축소 → 흰 바탕 → JPEG. 아바타 경로(`CheckAvatarView.downscaledJPEGData`)가 이것을 부른다.
    package static func downscaledJPEG(from source: CGImageSource, maxPixelSize: Int, quality: CGFloat) -> Data? {
        guard let thumbnail = thumbnail(from: source, maxPixelSize: maxPixelSize) else { return nil }
        return jpegData(flattenedOnWhite(thumbnail) ?? thumbnail, quality: quality)
    }
}

// MARK: - 메시지 사진 인코더

/// 올릴 준비가 된 사진(JPEG 바이트와 그 픽셀 크기). 서버 `p_width` · `p_height` 는 이 값이다.
package struct MessagePhotoEncoded: Equatable, Sendable {
    package let data: Data
    package let pixelWidth: Int
    package let pixelHeight: Int

    package init(data: Data, pixelWidth: Int, pixelHeight: Int) {
        self.data = data
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
    }
}

/// CGImage 를 액터 경계 너머로 나르는 상자(읽기 전용 — 만든 뒤 바뀌지 않는다).
package final class MessagePhotoImageBox: @unchecked Sendable {
    package let image: CGImage
    package init(_ image: CGImage) { self.image = image }
}

/// 사용자가 고른 그림 → 올릴 JPEG(계약: 긴 변 ≤ 1600px · 약 0.35MB 이하 · EXIF 적용 · 흰 바탕 · 메타데이터 없음).
///
/// 품질을 계단으로 내리며 목표 크기 안에 드는 첫 값을 쓴다. 가장 낮은 품질로도 넘치면(잡음 많은 큰 사진) 긴 변을 한 계단 줄여 다시 잰다.
/// **무거운 일이라 메인 액터에서 부르지 마라**(맥 스토어는 떼어 낸 작업에서 부른다).
package enum MessagePhotoEncoder {
    /// 긴 변 상한(px).
    package static let maxPixelSide = 1_600
    /// 목표 크기(바이트, 약 0.35MB).
    package static let targetBytes = 350_000
    /// 품질 계단(높은 것부터).
    package static let qualitySteps: [CGFloat] = [0.82, 0.74, 0.66, 0.58, 0.5, 0.42]
    /// 가장 낮은 품질로도 넘칠 때 긴 변을 줄이는 계단(px).
    package static let fallbackSides = [1_280, 1_024, 800]

    /// 파일에서(파일을 Data 로 통째로 읽지 않는다 — 필요한 만큼만 읽는다).
    package static func encode(fileURL: URL) -> (MessagePhotoEncoded, MessagePhotoImageBox)? {
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil) else { return nil }
        return encode(source: source)
    }

    /// 바이트에서(붙여넣기의 그림 자료).
    package static func encode(data: Data) -> (MessagePhotoEncoded, MessagePhotoImageBox)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return encode(source: source)
    }

    /// 몸통. 돌려주는 그림은 **올린 JPEG 와 같은 그림**(흰 바탕에 깐 축소본)이다 — 미리 보기와 보낸 쪽 캐시가 이것을 쓴다.
    package static func encode(source: CGImageSource) -> (MessagePhotoEncoded, MessagePhotoImageBox)? {
        for side in [maxPixelSide] + fallbackSides {
            guard let thumbnail = ImageDownscale.thumbnail(from: source, maxPixelSize: side) else { return nil }
            let flat = ImageDownscale.flattenedOnWhite(thumbnail) ?? thumbnail
            var smallest: Data?
            for quality in qualitySteps {
                guard let data = ImageDownscale.jpegData(flat, quality: quality) else { continue }
                smallest = data
                if data.count <= targetBytes {
                    return (MessagePhotoEncoded(data: data, pixelWidth: flat.width, pixelHeight: flat.height), MessagePhotoImageBox(flat))
                }
            }
            // 마지막 계단에서도 넘치면 그대로 보낸다(버킷 상한 5MB 안이다 — 사진을 못 보내는 것보다 낫다).
            if side == fallbackSides.last, let smallest {
                return (MessagePhotoEncoded(data: smallest, pixelWidth: flat.width, pixelHeight: flat.height), MessagePhotoImageBox(flat))
            }
        }
        return nil
    }

    /// 받은 바이트 → 화면용 그림(사진 칸의 메모리 캐시가 든다). 상한보다 큰 그림은 상한으로 줄여 든다.
    package static func decodeForDisplay(_ data: Data, maxPixelSize: Int = maxPixelSide) -> MessagePhotoImageBox? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = ImageDownscale.thumbnail(from: source, maxPixelSize: maxPixelSize)
        else { return nil }
        return MessagePhotoImageBox(image)
    }
}
