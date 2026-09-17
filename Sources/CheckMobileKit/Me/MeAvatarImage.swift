import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// 아바타 업로드용 이미지 줄이기(플랫폼 무관 — ImageIO 만 쓴다). 맥 `CheckAvatarView.downscaledJPEGData` 와 같은 규칙:
/// **최장변 256px 로 비율 유지 축소 → JPEG 압축 0.85**(원본이 더 작으면 키우지 않는다). PhotosPicker 가 주는 HEIC·PNG·JPEG 를 모두 받고,
/// 사진의 EXIF 방향을 적용해 옆으로 누운 사진이 누운 채 올라가지 않게 한다.
package enum MeAvatarImage {
    package static let maxDimension = 256
    package static let compression = 0.85

    /// 원본 바이트 → 업로드할 JPEG. 읽을 수 없는 바이트면 nil.
    package static func jpegData(from source: Data, maxDimension: Int = maxDimension, compression: Double = compression) -> Data? {
        guard let imageSource = CGImageSourceCreateWithData(source as CFData, nil),
              CGImageSourceGetCount(imageSource) > 0
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else { return nil }
        let flattened = flattenedOnWhite(thumbnail) ?? thumbnail
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, flattened, [kCGImageDestinationLossyCompressionQuality: compression] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    /// JPEG 는 알파가 없다 — 투명 PNG 가 검게 올라가지 않게 흰 바탕에 한 번 그린다.
    private static func flattenedOnWhite(_ image: CGImage) -> CGImage? {
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
}
