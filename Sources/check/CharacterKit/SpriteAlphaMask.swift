import CoreGraphics
import Foundation
import os

/// 아틀라스 전체의 1비트 불투명 마스크. 클릭이 캐릭터 "몸"에 맞았는지 판정하는 데 쓴다.
///
/// 왜 필요한가: 스프라이트는 네모난 평면 한 장이라 `hitTest` 는 **투명한 여백에서도 히트**를 돌려준다. 3D 아잉은
/// 메시가 곧 몸이라 이 문제가 없었다 — 평면으로 갈아타는 순간 "캐릭터 옆 빈 공간을 클릭해도 캐릭터가 반응한다"가
/// 생긴다. 그래서 히트가 난 UV 의 알파를 마스크에서 한 번 더 확인한다.
///
/// ★ **UV 규약: `py = v × 높이`. 뒤집지 않는다.** 이건 추측이 아니라 비대칭 이미지(위 절반만 불투명)로 가른
/// 실측이다(scratchpad/planeprobe/uvprobe.swift — 뷰 위쪽 히트의 uv.y=0.172 가 이미지 **위쪽** 픽셀을 가리켰고,
/// 렌더 정답지와 일치했다). 대칭 이미지로는 두 규약이 영원히 구별되지 않으므로 테스트도 비대칭 픽스처로만 문다.
///
/// 메모리: 1픽셀 1비트라 1024² 아틀라스가 128KB. 캐릭터당 한 번 굽고 캐시한다(굽는 비용은 픽셀 1회 순회).
struct SpriteAlphaMask: Sendable, CustomStringConvertible {
    let width: Int
    let height: Int
    /// 행 우선 비트맵(행 0 = 이미지 **위쪽** 줄, CGImage 데이터 순서 그대로).
    private let bits: [UInt8]

    /// 테스트가 실패할 때 비트 배열 수만 바이트를 토해 내면 정작 어느 좌표가 틀렸는지가 묻힌다.
    var description: String { "SpriteAlphaMask(\(width)x\(height))" }

    private static let logger = Logger(subsystem: "kingcheck", category: "character")

    /// 아틀라스 CGImage 로부터 마스크를 굽는다. `alpha > threshold` 면 불투명.
    ///
    /// `states` 는 **교차 검증용**이다: 매니페스트가 말하는 프레임 rect 가 실제 PNG 밖이면 매니페스트와 에셋이
    /// 갈린 것이고(팩 스크립트를 다시 돌리다 한쪽만 커밋한 경우), 그대로 두면 프레임이 통째로 어긋난 채 조용히
    /// 돌아간다. 그 조합은 카탈로그 단계에서 걸러야 하므로 여기서 nil 을 돌려 호출부가 아잉으로 접게 한다.
    init?(atlas: CGImage, states: [String: CharacterManifest.State], threshold: UInt8 = 32) {
        let width = atlas.width
        let height = atlas.height
        guard width > 0, height > 0, width * height <= 64_000_000 else { return nil }
        for key in states.keys.sorted() {
            guard let state = states[key] else { continue }
            for rect in state.frames {
                guard rect.w > 0, rect.h > 0, rect.x >= 0, rect.y >= 0,
                      rect.x + rect.w <= width, rect.y + rect.h <= height else {
                    Self.logger.error("sprite atlas/manifest mismatch state=\(key, privacy: .public) atlas=\(width)x\(height)")
                    return nil
                }
            }
        }
        guard let bits = Self.bakeBits(from: atlas, threshold: threshold) else { return nil }
        self.width = width
        self.height = height
        self.bits = bits
    }

    /// UV(0..1, **아틀라스 전체** 기준)가 불투명 픽셀인가.
    ///
    /// 프레임 경계를 신경 쓰지 않는 이유: UV 는 이미 `contentsTransform` 과 같은 식으로 셀 안을 가리키고 들어온다
    /// (`SpriteCharacterNode.atlasUV(planeUV:frame:mirrored:atlasSize:)` 가 그 변환이다).
    /// 범위 밖 값은 가장자리로 물린다 — 재질이 `wrapS/T = .clamp` 라 화면에 그려진 것과 같은 픽셀을 보게.
    func isOpaque(u: CGFloat, v: CGFloat) -> Bool {
        guard u.isFinite, v.isFinite else { return false }
        let x = Self.clampIndex(Int((u * CGFloat(width)).rounded(.down)), limit: width)
        let y = Self.clampIndex(Int((v * CGFloat(height)).rounded(.down)), limit: height)
        return isOpaque(x: x, y: y)
    }

    /// 아틀라스 픽셀 좌표(좌상단 원점) 직접 조회.
    func isOpaque(x: Int, y: Int) -> Bool {
        guard x >= 0, y >= 0, x < width, y < height else { return false }
        let index = y * width + x
        return bits[index >> 3] & (1 << UInt8(index & 7)) != 0
    }

    private static func clampIndex(_ value: Int, limit: Int) -> Int {
        min(max(value, 0), limit - 1)
    }

    // MARK: - 굽기

    /// 알파 바이트를 뽑아 비트로 접는다.
    ///
    /// 픽셀 접근은 **`CGDataProvider` 사본**이 1순위다(`CGContext` 를 만들어 `data` 를 들여다보는 길은 포맷 가정이
    /// 깨질 때 조용히 쓰레기를 읽는다). 다만 데이터 사본도 포맷을 알아야 읽히므로, 우리가 확실히 아는 조합
    /// (8bpc·32bpp·정수)만 그 길로 가고 나머지(16bpc PNG·float·인덱스 컬러)는 RGBA8 컨텍스트로 한 번 다시 그려
    /// 포맷을 **우리가 만든 것**으로 고정한 뒤 읽는다.
    private static func bakeBits(from image: CGImage, threshold: UInt8) -> [UInt8]? {
        let width = image.width
        let height = image.height
        var bits = [UInt8](repeating: 0, count: (width * height + 7) / 8)

        // 알파 채널이 아예 없는 이미지는 전부 불투명이다 — 픽셀을 한 번도 안 읽고 끝낸다.
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            for index in bits.indices { bits[index] = 0xFF }
            return bits
        default:
            break
        }

        if let fast = providerAlphaLayout(of: image) {
            guard let data = image.dataProvider?.data else { return nil }
            let length = CFDataGetLength(data)
            guard let base = CFDataGetBytePtr(data), length >= (height - 1) * fast.bytesPerRow + width * 4 else {
                return nil
            }
            for y in 0..<height {
                let row = y * fast.bytesPerRow
                for x in 0..<width where base[row + x * 4 + fast.alphaOffset] > threshold {
                    let index = y * width + x
                    bits[index >> 3] |= 1 << UInt8(index & 7)
                }
            }
            return bits
        }

        // 폴백: 우리가 만든 RGBA8(premultipliedLast) 버퍼에 다시 그린다. 이 버퍼의 행 0 은 이미지 위쪽이다
        // (SleepEyeTexture 의 PixelBuffer 와 같은 규약).
        let bytesPerRow = width * 4
        var buffer = [UInt8](repeating: 0, count: height * bytesPerRow)
        let drawn = buffer.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(
                data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: bytesPerRow, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }
        for y in 0..<height {
            let row = y * bytesPerRow
            for x in 0..<width where buffer[row + x * 4 + 3] > threshold {
                let index = y * width + x
                bits[index >> 3] |= 1 << UInt8(index & 7)
            }
        }
        return bits
    }

    /// 데이터 사본을 그대로 읽어도 되는 포맷이면 (행 간격, 알파 바이트 위치)를 돌려준다. 아니면 nil(폴백으로).
    private static func providerAlphaLayout(of image: CGImage) -> (bytesPerRow: Int, alphaOffset: Int)? {
        guard image.bitsPerComponent == 8, image.bitsPerPixel == 32 else { return nil }
        let info = image.bitmapInfo
        guard info.contains(.floatComponents) == false else { return nil }
        let alphaFirst = image.alphaInfo == .first || image.alphaInfo == .premultipliedFirst
        let byteOrder = info.intersection(.byteOrderMask)
        let littleEndian = byteOrder == .byteOrder32Little
        guard byteOrder == .byteOrder32Little || byteOrder == .byteOrder32Big || byteOrder == CGBitmapInfo(rawValue: 0) else {
            return nil
        }
        // 논리 순서(알파 앞/뒤)와 바이트 순서(리틀이면 32비트 워드 안이 뒤집힌다)를 곱해 실제 바이트 위치를 낸다.
        // ARGB+빅 → 0, ARGB+리틀(=메모리 BGRA) → 3, RGBA+빅 → 3, RGBA+리틀(=메모리 ABGR) → 0.
        let alphaOffset = (alphaFirst != littleEndian) ? 0 : 3
        guard image.bytesPerRow >= image.width * 4 else { return nil }
        return (image.bytesPerRow, alphaOffset)
    }
}
