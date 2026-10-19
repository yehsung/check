import Foundation

// MARK: - 무지개 아잉이 (v0.3.59) — 식별 · "그릴 수 있다"의 정의 · 몸 색 공식의 상수
//
// 무지개 아잉이는 아잉과 **같은 메시**(aing.scn)에 무지개 마감을 입힌 변형이다(사용자 시안 E — 파스텔 무지개 몸 + 몸 테두리를 따라
// 무지개로 도는 후광, 흐르는 애니메이션 없음, 볼은 지금처럼 동그란 분홍 볼). 금처럼 뽑기 · 조각 교환으로만 얻는다.
// 이 파일이 한 곳에 두는 것:
//  ① 그림 파일 이름과 "이 빌드가 무지개 아잉이를 그릴 수 있다"의 정의(`RainbowAingArt`) — 상점 능력 번호 3(`ShopWire.rainbowProtocol`)의 재료.
//  ② 몸 색 공식(A 파스텔 무지개)의 상수 — 맥 셰이더(`RainbowAingFinish`)가 이 값으로 글을 만들고, 아트 스크립트
//     (`scripts/make-rainbow-aing.swift`)가 같은 글자를 옮겨 적는다(시험이 맞댄다).
//
// ★ 금과 다른 점 하나: 몸을 '띠 색 피부 맵'으로 굽지 않는다. aing.scn 의 삼각형 60개가 다른 UV 섬 텍셀을 같이 써서, 높이로 색을 구운 맵은
//   그 자리에 엉뚱한 띠 색 점을 만든다(시안 speck-compare.png). 그래서 색상은 맥 셰이더가 조각마다 **물체 좌표 높이**로 정하고, 구운 맵
//   (`shadeResourceName`)은 라벤더 그대로 밝기만 다듬은 것이다.

/// 무지개 아잉이 그림 파일의 이름과 "그릴 수 있다"의 판정. **파일 이름을 적는 곳은 여기 하나다** — 맥 번들 조회 · 폰 초상 ·
/// 아트 스크립트 · 시험이 이 이름을 같이 쓴다. 파일 자리는 금(`GoldAingArt`)과 같다(맥 `Sources/check/Resources/` 평탄화 ·
/// 폰 `Sources/CheckMobileShared/Resources/Portraits/` 초상 두 장 사본).
package nonisolated enum RainbowAingArt {
    package static let characterID = CharacterCatalog.rainbowAingID
    package static let resourceExtension = GoldAingArt.resourceExtension

    /// 초상(192×192). 이름 규칙은 폰 `AingCharacterArt.portraitName` 의 `<id>-<표정>` 과 같다.
    package static let neutralPortraitResourceName = "\(characterID)-neutral"
    package static let negativePortraitResourceName = "\(characterID)-negative"
    package static var portraitResourceNames: [String] { [neutralPortraitResourceName, negativePortraitResourceName] }

    /// 맥 3D 마감 — 다듬은 라벤더 밝기 맵(512², aing.scn 디퓨즈와 같은 UV)과 몸 뒤에 세우는 후광 판(0 칸 = 정면 512²).
    package static let shadeResourceName = "\(characterID)-shade"
    package static let haloResourceName = "\(characterID)-halo"
    package static var finishResourceNames: [String] { [shadeResourceName, haloResourceName] }

    /// 후광 각도 칸 — 금과 **같은 규약**(10° 간격 · 36칸 · 0 칸은 정면 512², 나머지 `<id>-halo-010` … `-350` 160²).
    /// 금처럼 "그릴 수 있다"에는 넣지 않는다(빠진 칸은 정면으로 접는다 — 패키징 대본이 칸 수를 센다).
    package static var haloYawStepDegrees: Int { GoldAingArt.haloYawStepDegrees }
    package static var haloCellCount: Int { GoldAingArt.haloCellCount }

    package static func haloResourceName(cell: Int) -> String {
        cell == 0 ? haloResourceName : "\(haloResourceName)-\(String(format: "%03d", cell * haloYawStepDegrees))"
    }

    package static var haloCellResourceNames: [String] { (0..<haloCellCount).map(haloResourceName(cell:)) }

    package typealias Platform = GoldAingArt.Platform

    /// 플랫폼별 요구 파일. 폰은 3D 를 그리지 않으므로 초상이 전부다.
    package static func requiredResourceNames(for platform: Platform) -> [String] {
        switch platform {
        case .mac: return portraitResourceNames + finishResourceNames
        case .phone: return portraitResourceNames
        }
    }

    /// 이 빌드가 무지개 아잉이를 **그릴 수 있는가** — 요구 파일이 전부 실재할 때만 참이다(`resourceExists` 는 주입 — 금과 같다).
    /// 초상만 있고 마감이 없는 맥은 무지개 착용자의 오버레이에 보라 아잉을 세우고, 마감만 있고 초상이 없으면 메뉴바 · 카드가 아잉으로 접힌다.
    package static func isDrawable(on platform: Platform, resourceExists: (String) -> Bool) -> Bool {
        requiredResourceNames(for: platform).allSatisfy(resourceExists)
    }

    // MARK: 몸 색 공식(A 파스텔 무지개) — 셰이더와 아트 스크립트가 같은 값을 쓴다

    /// 몸 높이 좌표 t = (bodyTop − y) / bodyHeight — 정수리 0 → 바닥 1(aing.scn 물체 좌표, 바운딩박스 위 끝 · 높이).
    package static let bodyTop = 0.848950
    package static let bodyHeight = 1.695736
    /// 라벤더 피부 밝기 기준(밝기 맵의 믿는 텍셀 OKLab L 중앙값 — 아트 스크립트가 다시 재서 다르면 멈춘다).
    package static let lightnessReference = 0.8327

    /// 정지점(OKLCh): 빨 · 주 · 노 · 초 · 파 · 남 · 보. 색상은 정지점 순서대로 늘어나기만 한다(무지개 = 색상환 한 바퀴의 일부).
    /// ★ 아트 스크립트의 같은 이름 배열과 **글자까지** 같아야 한다(V0359RainbowArtTests).
    package static let stopLightness: [Double] = [0.780, 0.835, 0.905, 0.870, 0.840, 0.800, 0.800]
    package static let stopChroma: [Double] = [0.135, 0.120, 0.115, 0.105, 0.095, 0.100, 0.110]
    package static let stopHue: [Double] = [25, 58, 100, 145, 240, 272, 305]

    /// 채도 배수 k = clamp(1 − chromaSlope·dL, chromaFloor, chromaCeil) — 라벤더처럼 밝은 곳은 우유빛, 그늘은 진하게.
    package static let chromaSlope = 3.0
    package static let chromaFloor = 0.72
    package static let chromaCeil = 1.25
    package static let lightnessMin = 0.2
    package static let lightnessMax = 0.975
    /// 색역 바닥(선형 0.006 ≈ sRGB 18/255) — 채널이 0 에 닿은 색은 파스텔이 아니라 형광 얼룩으로 읽힌다(시안 검토 실측).
    package static let gamutFloor = 0.006
    package static let gamutCeil = 1.0001
    /// 그늘 창(중심 색상 · 안 · 밖 · 어둡힘 덜기): 노랑·주황 · 청록은 그늘에서 채도 배수를 1.0 으로 묶는다(겨자색 · 짙은 청록 얼룩 방지).
    package static let shadowWindows: [(centre: Double, inner: Double, outer: Double, lift: Double)] = [(75, 25, 45, 0.4), (187.5, 17.5, 37.5, 0)]

    // MARK: 기준 구현(CPU) — 셰이더와 같은 식. 시험이 GPU 결과와 맞대고, 아트 스크립트가 같은 식을 옮겨 적는다.

    /// 높이 t(정수리 0 → 바닥 1) · 밝기 차 dL(OKLab L − `lightnessReference`) → 선형 sRGB(0…1).
    package static func bodyColorLinear(heightT t: Double, dL: Double) -> SIMD3<Double> {
        let s = min(max(7 * t - 0.5, 0), 6)
        let k = min(5, Int(s.rounded(.down)))
        let f = s - Double(k)
        let ls = stopLightness[k] + (stopLightness[k + 1] - stopLightness[k]) * f
        let cs = stopChroma[k] + (stopChroma[k + 1] - stopChroma[k]) * f
        let hs = stopHue[k] + (stopHue[k + 1] - stopHue[k]) * f
        var kc = min(max(1 - chromaSlope * dL, chromaFloor), chromaCeil)
        var dLs = dL
        if dL < 0 {
            var capWeight = 0.0, lift = 0.0
            for window in shadowWindows {
                var d = (hs - window.centre).truncatingRemainder(dividingBy: 360)
                if d < 0 { d += 360 }
                d = min(d, 360 - d)
                let w = 1 - smoothstep(window.inner, window.outer, d)
                capWeight = max(capWeight, w)
                lift = max(lift, w * window.lift)
            }
            kc -= (kc - min(kc, 1)) * capWeight * smoothstep(0, 0.06, -dL)
            dLs = dL * (1 - lift)
        }
        let lightness = min(max(ls + dLs, lightnessMin), lightnessMax)
        let chroma = cs * kc
        let hue = hs * .pi / 180
        let ca = cos(hue), sa = sin(hue)
        func linear(_ scale: Double) -> SIMD3<Double> {
            oklabToLinear(lightness, chroma * scale * ca, chroma * scale * sa)
        }
        func inGamut(_ c: SIMD3<Double>) -> Bool {
            c.x >= gamutFloor && c.y >= gamutFloor && c.z >= gamutFloor && c.x <= gamutCeil && c.y <= gamutCeil && c.z <= gamutCeil
        }
        var scale = 1.0
        if !inGamut(linear(1)) {
            var lo = 0.0, hi = 1.0
            for _ in 0..<12 {
                let mid = (lo + hi) / 2
                if inGamut(linear(mid)) { lo = mid } else { hi = mid }
            }
            scale = lo
        }
        let c = linear(scale)
        return SIMD3(min(max(c.x, 0), 1), min(max(c.y, 0), 1), min(max(c.z, 0), 1))
    }

    /// 선형 sRGB → OKLab L.
    package static func oklabLightness(linear c: SIMD3<Double>) -> Double {
        let l = cbrt(0.4122214708 * c.x + 0.5363325363 * c.y + 0.0514459929 * c.z)
        let m = cbrt(0.2119034982 * c.x + 0.6806995451 * c.y + 0.1073969566 * c.z)
        let s = cbrt(0.0883024619 * c.x + 0.2817188376 * c.y + 0.6299787005 * c.z)
        return 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
    }

    private static func oklabToLinear(_ lightness: Double, _ a: Double, _ b: Double) -> SIMD3<Double> {
        let l_ = lightness + 0.3963377774 * a + 0.2158037573 * b
        let m_ = lightness - 0.1055613458 * a - 0.0638541728 * b
        let s_ = lightness - 0.0894841775 * a - 1.2914855480 * b
        let l = l_ * l_ * l_, m = m_ * m_ * m_, s = s_ * s_ * s_
        return SIMD3(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
                     -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
                     -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
    }

    private static func smoothstep(_ e0: Double, _ e1: Double, _ x: Double) -> Double {
        let t = min(max((x - e0) / (e1 - e0), 0), 1)
        return t * t * (3 - 2 * t)
    }
}
