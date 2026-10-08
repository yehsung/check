import CoreGraphics

/// 두 렌더를 **눈에 보이는 차이**로 견준다 — 렌더 테스트의 "같다"·"다르다"는 이 헬퍼 하나로만 잰다.
///
/// ## 왜 바이트 동치를 버렸나 (2026-10-08 실측)
/// `CheckRenderSettle` 은 **연속 두 장**이 바이트까지 같아질 때까지 굽는다 — 한 호출 **안에서는** 참이다.
/// 그런데 **호출 사이에는** 채널당 Δ1 디더가 남는다: 고르개 쌍둥이 줄 하나를 `CheckRenderSettle` 로 30번 구우면
/// 재검증자 실측으로 30/30 이 서로 다른 바이트(최대 Δ1)였고, 이 수리 중 다시 재 보니 **첫 호출과 뒤 호출이**
/// Δ1 로 갈리는 회차가 6회 중 2회였다(Δ>8 픽셀은 언제나 0). 그래서 `#expect(imageA == imageAgain)` 이
/// `swift test --no-parallel --filter V0347AILimit` 14회 중 2~4회 빨갰다(고르개 스위트 단독으로는 6/6 초록이라
/// "혼자 돌리면 초록"에 속는다 — `ImageRenderer` 첫 두 장이 다른 것과 같은 가족이다).
///
/// 바이트 동치는 양쪽으로 무너진다: "같다"는 그 Δ1 에 빨개지고, "다르다"(`a != b`)는 **Δ1 잡음만으로 초록**이
/// 된다 — 꼬리가 잘려 두 줄이 글자까지 같아져도 디더가 바이트를 갈라 주면 통과한다. 그래서 둘 다 문턱으로 잰다.
///
/// ## 두 문턱은 **떨어져 있다** (회색 지대에서는 둘 다 빨갛다)
///  · **같다** = 크기가 같고 모든 픽셀·채널 차가 `sameMaxDelta`(2) 이하. 디더(실측 Δ1)와 첫 두 장 잡음(실측 Δ≤2)만 넘긴다.
///  · **다르다** = 크기가 다르거나, 채널 차가 `visibleDelta`(8)를 넘는 픽셀이 `minimumVisiblePixels`(40) 이상.
///    실측(2026-10-08, 2배율): 상한 길이 쌍둥이의 꼬리 `(A1B2)`/`(C3D4)` 차이는 맥 고르개 줄에서 **최대 Δ218 ·
///    Δ>8 픽셀 782**, 위젯 머리 줄에서 **Δ166 · 1,078** 이다 — 하한(40)의 스무 배 안팎. 가장 작은 "다르다"는
///    이름 끝 숫자 하나만 다른 두 줄(`맥 스튜디오 3`/`5`)의 **92** 픽셀이다.
/// 둘은 서로의 부정이 아니다. Δ3~8 이 퍼져 있거나 Δ>8 이 몇 픽셀뿐이면 **어느 쪽도 참이 아니다** —
/// 그런 그림은 새 비결정성이거나 너무 작은 차이라, 조용히 한쪽으로 접지 않고 빨갛게 드러낸다.
public struct CheckRenderDiff: Sendable, CustomStringConvertible {
    /// "같다"가 허용하는 채널 차의 상한(디더 Δ1 · 첫 두 장 잡음 Δ≤2).
    public static let sameMaxDelta = 2
    /// 이 값을 **넘는** 채널 차가 있는 픽셀만 "보이는 차이"로 센다.
    public static let visibleDelta = 8
    /// "다르다"가 요구하는 보이는 차이 픽셀 수의 하한. 글자 한 자(2배율 11~12pt)가 바뀌면 수십~수백 픽셀이다.
    public static let minimumVisiblePixels = 40

    public let widthA: Int
    public let heightA: Int
    public let widthB: Int
    public let heightB: Int
    /// 모든 픽셀·채널(RGBA) 차의 최댓값. 크기가 다르면 0(견주지 않았다).
    public let maxDelta: Int
    /// 채널 차가 `visibleDelta` 를 넘는 픽셀 수. 크기가 다르면 0.
    public let visiblePixels: Int

    public var sizesMatch: Bool { widthA == widthB && heightA == heightB }

    /// 눈으로 같은 그림이다.
    public var looksSame: Bool { sizesMatch && maxDelta <= Self.sameMaxDelta }

    /// 눈으로 다른 그림이다.
    public var looksDifferent: Bool { !sizesMatch || visiblePixels >= Self.minimumVisiblePixels }

    public var description: String {
        guard sizesMatch else { return "크기가 다르다 \(widthA)×\(heightA) vs \(widthB)×\(heightB)" }
        return "\(widthA)×\(heightA) · 최대 Δ\(maxDelta) · Δ>\(Self.visibleDelta) 픽셀 \(visiblePixels)"
    }

    /// 두 그림을 **같은 판(sRGB · RGBA8 · premultiplied)**에 다시 그려 견준다 — 원본의 픽셀 형식이 달라도
    /// 바이트 배치 차이가 "차이"로 세어지지 않는다. 판을 못 만들면 nil.
    public init?(_ a: CGImage, _ b: CGImage) {
        widthA = a.width
        heightA = a.height
        widthB = b.width
        heightB = b.height
        guard widthA == widthB, heightA == heightB else {
            maxDelta = 0
            visiblePixels = 0
            return
        }
        guard let pa = Self.rgba(a), let pb = Self.rgba(b) else { return nil }
        var maxDelta = 0
        var visible = 0
        var index = 0
        while index < pa.count {
            var pixelMax = 0
            for channel in 0..<4 {
                let delta = abs(Int(pa[index + channel]) - Int(pb[index + channel]))
                if delta > pixelMax { pixelMax = delta }
            }
            if pixelMax > maxDelta { maxDelta = pixelMax }
            if pixelMax > Self.visibleDelta { visible += 1 }
            index += 4
        }
        self.maxDelta = maxDelta
        visiblePixels = visible
    }

    private static func rgba(_ image: CGImage) -> [UInt8]? {
        let width = image.width, height = image.height
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let drawn: Bool = bytes.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn ? bytes : nil
    }
}
