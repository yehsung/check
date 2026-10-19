#!/usr/bin/env swift
// 무지개 아잉이(aing_rainbow) 그림 생성기 (v0.3.59) — 앱이 쓰는 밝기 맵 · 후광(정면 1 + 각도 칸 35) · 초상 4장(맥 2 + 폰 사본 2)을 굽는다.
// 사용자가 고른 시안 E(스크래치 v0359-rainbow/rainbow-drafts.swift · out/E-sheet.png)를 그대로 옮겼다: 몸 = A 파스텔 무지개(OKLab,
// 높이 기준 빨 → 보, 라벤더 밝기 부피 유지, 무광), 얼굴(눈·하이라이트·볼·입·눈썹)은 원본 그대로, 후광 = 황금 아잉이와 같은 층 · 불투명도 ·
// 흐림 · 판 기하에 색만 실루엣 둘레로 도는 무지개(12시 빨강). 흐르는 애니메이션 없음.
//
// 사용법(저장소 루트에서):
//   swift -O scripts/make-rainbow-aing.swift               산출물 41개를 저장소에 쓴다(아래 '출력'). 같은 입력이면 같은 바이트.
//   swift -O scripts/make-rainbow-aing.swift --out <폴더>  같은 산출물을 <폴더>/Sources/… 아래에 쓴다(저장소는 안 건드린다 — 결정성 검사용).
//   (실측: -O 로 약 10초. -O 없이도 돌지만 느리다.)
//
// 입력(저장소, 읽기만): Sources/check/Resources/aing.scn(메시 · UV · 512² 라벤더 디퓨즈) · aing-neutral.png · aing-negative.png(192² 초상)
// 출력(저장소, 전부 커밋):
//   Sources/check/Resources/aing_rainbow-shade.png   512×512 불투명 **라벤더** 밝기 맵. aing.scn 디퓨즈와 같은 UV 배치. 텍셀마다 '그 자리
//                                                    피부의 다듬은 밝기'(OKLab L)를 라벤더 색으로 담는다 — 눈·볼·입 둘레 8텍셀 안은 밝은 피부만
//                                                    믿고(나머지는 메시 표면으로 번진 밝기), 1–2텍셀 밝은 티끌은 5×5 중앙값으로 걷었다(시안 E 의
//                                                    rbData 와 같은 밝기 장). 눈·볼·입·UV 틈 텍셀까지 채워 두었다. 두 눈 둘레(앵커에서 x·y 0.16
//                                                    안)는 칠한 눈두덩 테를 버리고 둘레 밖 밝기로 정면 격자에서 다시 채웠다(`refillEyeSockets` —
//                                                    감은 눈 커버가 그 자리를 피부로 덮어도 테 · 원반 없이 매끈하다). 색상은 라벤더라 **띠 색이
//                                                    구워져 있지 않다** — 아래 ★.
//   Sources/check/Resources/aing_rainbow-halo.png    512×512 알파. 후광만(몸 없음) = 각도 칸 0°. 금 후광(make-gold-aing.swift)과 같은 카메라 ·
//                                                    같은 층(넓게 σ40·α0.68 / 가운데 σ18·α0.8 ×2 / 안쪽 σ6·α0.8 ×2, σ × 0.8 × 몸높이/256) · 같은 판
//                                                    (2.0 × H 빌보드). 색만: 실루엣 중심에서 잰 둘레 각 θ(12시 0, 시계 방향) → 순환 8정지점의 색상,
//                                                    층별 OKLCh 넓게 (0.78, 0.15) · 가운데 (0.87, 0.10) · 안쪽 (0.96, 0.035).
//   Sources/check/Resources/aing_rainbow-halo-010.png … aing_rainbow-halo-350.png
//                                                    160×160 알파 35장 — 금 각도 칸과 같은 규약(몸 요 +10° … +350°, 512 로 구워 160² 로 줄임).
//   Sources/check/Resources/aing_rainbow-neutral.png 192×192 RGBA 초상(아잉 초상의 피부만 무지개로 + 몸 0.88배 + 무지개 후광).
//   Sources/check/Resources/aing_rainbow-negative.png 〃 (시무룩)
//   Sources/CheckMobileShared/Resources/Portraits/aing_rainbow-{neutral,negative}.png  위 두 장의 **바이트 그대로** 사본(폰·위젯).
//
// ★ 왜 몸을 금처럼 '띠 색 피부 맵'으로 굽지 않는가: aing.scn 의 삼각형 60개(표면의 0.03%)가 다른 UV 섬의 텍셀을 같이 쓴다. 라벤더·금은
//   섬마다 비슷한 색이라 안 보이지만, 높이로 색을 굽는 무지개 피부 맵에선 그 자리만 다른 띠 색 1–3픽셀 점이 된다(시안 speck-compare.png).
//   그래서 색상은 **앱의 셰이더**(RainbowAingFinish — 몸 재질 .constant 의 SCNShaderModifier)가 조각마다 자기 물체 좌표 높이로 정한다.
//   이 스크립트가 굽는 밝기 맵은 라벤더 그대로라 그 텍셀을 다른 섬이 같이 써도 밝기 점(지금 라벤더에도 있는 것)일 뿐이다.
//
// ── 앱이 할 일(맥 3D, RainbowAingFinish) ───────────────────────────────────────────────────────────────────────────
// 1) 합성(로드 때 한 번, 캐시): 디퓨즈 텍셀마다 isGoldSkin(원본) ? 밝기 맵[텍셀] : 원본 — 금과 **같은 합성 함수**(GoldAingFinish.composite).
//    감은 눈은 라벤더 원본에서 먼저 굽고 같은 합성을 한다(금과 같은 순서).
// 2) 셰이더(몸 재질): 지금 표본한 디퓨즈 텍셀이 isGoldSkin 이면 → 색 = A 공식(높이 t = (0.848950 − y) / 1.695736, 물체 좌표),
//    밝기 차 dL = OKLab L(표본) − 0.8327. 아니면 디퓨즈 그대로. 그래서 깜빡임 · 졸기 · 울트라 교체로 디퓨즈가 바뀌어도 마스크가 따라온다.
// 3) 후광 판: 금과 같은 판 36장 · 같은 칸 고르기(GoldAingFinish.haloCell) · 같은 창 합성 보정(GoldAingFinish.windowCompensated).
//
// A 공식(이 스크립트의 rainbowLinear 와 앱 셰이더가 같은 상수 — 바꾸면 둘 다): s = clamp(7t − 0.5, 0, 6), 정지점 k = min(⌊s⌋, 5) 와 k+1
//   사이 선형 보간(L · C · h 각각). k = clamp(1 − 3·dL, 0.72, 1.25), 그늘(dL < 0)에서 노랑·주황 창(75° · 25/45) · 청록 창(187.5° · 17.5/37.5)은
//   채도 배수 1.0 상한, 노랑·주황은 어둡힘 × (1 − 0.4·창). L = clamp(L_s + dL, 0.2, 0.975), C = C_s·k. 색역(선형 0.006…1.0001) 밖이면
//   C 만 이분(셰이더 13회 · 여기 12회 — 차이는 1/4096 배수 아래).
//
// 이 스크립트는 앱 모듈을 링크하지 않는다. isGoldSkin · isSkin · 디퓨즈 정규화 · 팔레트 상수를 여기 한 번 더 적는다 — 앱 쪽이 바뀌면 여기도
// 같이 바꿔야 한다(팔레트는 V0359RainbowArtTests 가 앱 상수와 이 파일의 글자를 맞댄다).

import AppKit
import CoreImage
import SceneKit
import simd

// MARK: - 상수

let resourceDir = "Sources/check/Resources"
let phonePortraitDir = "Sources/CheckMobileShared/Resources/Portraits"
let modelPath = "\(resourceDir)/aing.scn"
let characterID = "aing_rainbow"
let expressions = ["neutral", "negative"]
// 후광 각도 칸 — 이름 규칙은 앱 `RainbowAingArt.haloResourceName(cell:)` 와 같다(금 `GoldAingArt` 와 같은 꼴).
let haloYawStep = 10
let haloCellCount = 360 / haloYawStep
let haloCellSize = 160

let skinSize = 512
let haloSize = 512
let frontFOV: Float = 30          // 금 시안 카메라: 세로 시야 30°
let frontZoom: Float = 2.0        // 거리 = H/2/tan15° × 2.0 → 몸 높이가 프레임의 절반
let frontRaise: Float = 0.05      // 카메라를 몸 중심보다 0.05H 위에 두고 중심을 본다
let haloK = 0.8
let haloBodyPixels = 256.0
let portraitBodyScale = 0.88
let portraitFadePixels = 10.0
let borderAlphaLimit = 0.04
let featureRadius = 8             // 눈·볼·입 둘레(텍셀): 금과 같은 '밝은 피부만 믿기' 폭
// 감은 눈 둘레 다시 채우기(아래 `refillEyeSockets`). 두 눈 앵커 = 앱 `CheckCharacter3DScene.closedEyeAnchors` 의 x·y(물체 좌표) — 시험이 글자를 맞댄다.
let eyeAnchors: [SIMD2<Double>] = [SIMD2(-0.277, 0.418), SIMD2(0.250, 0.434)]
let eyeSocketRadius = 0.16        // 앵커에서 x·y 거리: 눈(반지름 ≈ 0.125) + 칠해진 눈두덩 테
let eyeSocketGrid = 0.005         // 정면 격자 간격(물체 좌표 — 얼굴 앞면 텍셀 간격 ≈ 0.006 과 비슷하게)

// 셰이더가 쓰는 몸 좌표 상수(앱 `RainbowAingArt` 와 같은 값). 메시가 바뀌면 여기서 멈춘다.
let bodyTop = 0.848950
let bodyHeight = 1.695736
let lReference = 0.8327

// 팔레트 — A 파스텔 무지개 정지점(OKLCh). 앱 `RainbowAingArt.stopLightness/stopChroma/stopHue` 와 글자까지 같다(시험이 맞댄다).
let stopLightness: [Double] = [0.780, 0.835, 0.905, 0.870, 0.840, 0.800, 0.800]
let stopChroma: [Double] = [0.135, 0.120, 0.115, 0.105, 0.095, 0.100, 0.110]
let stopHue: [Double] = [25, 58, 100, 145, 240, 272, 305]
/// 후광 색상 순환(8정지점: 위 7개 + 자홍 345° — 보라에서 빨강으로 둘레를 닫는다).
let haloCycleHue: [Double] = stopHue + [345]

let chromaSlope = 3.0, chromaFloor = 0.72, chromaCeil = 1.25
let lightnessMin = 0.2, lightnessMax = 0.975
let gamutFloor = 0.006, gamutCeil = 1.0001
/// 그늘 창(중심 색상 · 안 · 밖 · 어둡힘 덜기).
let shadowWindows: [(centre: Double, inner: Double, outer: Double, lift: Double)] = [(75, 25, 45, 0.4), (187.5, 17.5, 37.5, 0)]

var outRoot = "."

// MARK: - 공통(금 스크립트와 같은 정의)

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(("make-rainbow-aing: " + message + "\n").data(using: .utf8)!)
    exit(1)
}

func loadImage(_ path: String) -> CGImage {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fail("그림을 못 읽었다: \(path)") }
    return image
}

/// RGBA8 premultipliedLast 바이트(원점 좌상단). 기본은 앱의 SleepEyeTexture · GoldAingFinish 와 같은 DeviceRGB.
func bytes(_ image: CGImage, space: CGColorSpace = CGColorSpaceCreateDeviceRGB()) -> [UInt8] {
    let w = image.width, h = image.height
    var px = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    return px
}

func makeImage(_ px: [UInt8], _ w: Int, _ h: Int) -> CGImage {
    var p = px
    let ctx = CGContext(data: &p, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, _ relativePath: String) {
    let path = outRoot + "/" + relativePath
    try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    guard let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil) else {
        fail("쓸 수 없다: \(path)")
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fail("PNG 저장 실패: \(path)") }
}

@inline(__always) func luma(_ r: Int, _ g: Int, _ b: Int) -> Int { (r * 299 + g * 587 + b * 114) / 1000 }
/// 앱 `SleepEyeTexture.isSkin` 과 같은 식 — 감은 눈 파이프라인의 피부(밝은 피부 판정에만 쓴다).
@inline(__always) func isSkin(_ r: Int, _ g: Int, _ b: Int) -> Bool { b >= r && r > g && b > g + 18 && luma(r, g, b) > 120 }
/// 합성 마스크 = 앱 `GoldAingFinish.isGoldSkin` 과 같은 식(색상 215–300° · 채도 0.05–0.75 · 루마 > 0.10). 셰이더도 같은 판정이다.
@inline(__always) func isGoldSkin(_ r: Int, _ g: Int, _ b: Int) -> Bool {
    let (hue, sat, l) = hueSatLum(Double(r), Double(g), Double(b))
    return hue >= 215 && hue <= 300 && sat > 0.05 && sat < 0.75 && l > 0.10
}

func hueSatLum(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
    let mx = max(r, g, b), mn = min(r, g, b), sat = mx == 0 ? 0 : (mx - mn) / mx
    var hue = 0.0
    if mx != mn {
        if mx == r { hue = 60 * ((g - b) / (mx - mn)) } else if mx == g { hue = 60 * ((b - r) / (mx - mn) + 2) } else { hue = 60 * ((r - g) / (mx - mn) + 4) }
        if hue < 0 { hue += 360 }
    }
    return (hue, sat, (0.299 * r + 0.587 * g + 0.114 * b) / 255)
}

/// 정사각 팽창(반경 r, 체비쇼프 거리).
func dilate(_ mask: [Bool], width w: Int, height h: Int, radius r: Int) -> [Bool] {
    var horizontal = [Bool](repeating: false, count: w * h)
    for y in 0..<h { for x in 0..<w where mask[y * w + x] { for xx in max(0, x - r)...min(w - 1, x + r) { horizontal[y * w + xx] = true } } }
    var out = [Bool](repeating: false, count: w * h)
    for y in 0..<h { for x in 0..<w where horizontal[y * w + x] { for yy in max(0, y - r)...min(h - 1, y + r) { out[yy * w + x] = true } } }
    return out
}

/// 4-이웃 평균으로 모르는 칸을 바깥에서 안으로 채운 뒤(파도), 채운 칸만 몇 번 더 고르게 편다(금 스크립트 `inpaint` 와 같다).
func inpaint(_ values: inout [Double], known: [Bool], width w: Int, height h: Int, relax: Int) {
    var have = known
    var frontier = true
    while frontier {
        frontier = false
        var next = values, nextHave = have
        for y in 0..<h { for x in 0..<w where !have[y * w + x] {
            var s = 0.0, c = 0.0
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let xx = x + dx, yy = y + dy
                if xx < 0 || yy < 0 || xx >= w || yy >= h { continue }
                let q = yy * w + xx
                if have[q] { s += values[q]; c += 1 }
            }
            if c > 0 { next[y * w + x] = s / c; nextHave[y * w + x] = true; frontier = true }
        } }
        values = next; have = nextHave
    }
    for _ in 0..<relax {
        var next = values
        for y in 0..<h { for x in 0..<w where !known[y * w + x] {
            var s = 0.0, c = 0.0
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let xx = x + dx, yy = y + dy
                if xx < 0 || yy < 0 || xx >= w || yy >= h { continue }
                s += values[yy * w + xx]; c += 1
            }
            next[y * w + x] = s / c
        } }
        values = next
    }
}

// MARK: - OKLab

@inline(__always) func srgbToLinear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
@inline(__always) func linearToSrgb(_ v: Double) -> Double { v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1 / 2.4) - 0.055 }

func linearToOklab(_ c: SIMD3<Double>) -> SIMD3<Double> {
    let l = cbrt(0.4122214708 * c.x + 0.5363325363 * c.y + 0.0514459929 * c.z)
    let m = cbrt(0.2119034982 * c.x + 0.6806995451 * c.y + 0.1073969566 * c.z)
    let s = cbrt(0.0883024619 * c.x + 0.2817188376 * c.y + 0.6299787005 * c.z)
    return SIMD3(0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
}

func oklabToLinear(_ lab: SIMD3<Double>) -> SIMD3<Double> {
    let l_ = lab.x + 0.3963377774 * lab.y + 0.2158037573 * lab.z
    let m_ = lab.x - 0.1055613458 * lab.y - 0.0638541728 * lab.z
    let s_ = lab.x - 0.0894841775 * lab.y - 1.2914855480 * lab.z
    let l = l_ * l_ * l_, m = m_ * m_ * m_, s = s_ * s_ * s_
    return SIMD3(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
                 -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
                 -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
}

func srgbBytesToOklab(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> SIMD3<Double> {
    linearToOklab(SIMD3(srgbToLinear(Double(r) / 255), srgbToLinear(Double(g) / 255), srgbToLinear(Double(b) / 255)))
}

@inline(__always) func inGamut(_ c: SIMD3<Double>) -> Bool {
    c.x >= gamutFloor && c.y >= gamutFloor && c.z >= gamutFloor && c.x <= gamutCeil && c.y <= gamutCeil && c.z <= gamutCeil
}

@inline(__always) func smoothstep(_ e0: Double, _ e1: Double, _ x: Double) -> Double {
    let t = min(max((x - e0) / (e1 - e0), 0), 1)
    return t * t * (3 - 2 * t)
}

@inline(__always) func hueDistance(_ a: Double, _ b: Double) -> Double {
    var d = (a - b).truncatingRemainder(dividingBy: 360)
    if d < 0 { d += 360 }
    return min(d, 360 - d)
}

/// OKLCh → 선형 sRGB. 색역 밖이면 L·h 를 두고 C 만 12번 이분해 줄인다.
func lchToLinear(_ L: Double, _ C: Double, _ hDeg: Double) -> SIMD3<Double> {
    let h = hDeg * .pi / 180
    let ca = cos(h), sa = sin(h)
    var c = oklabToLinear(SIMD3(L, C * ca, C * sa))
    if !inGamut(c) {
        var lo = 0.0, hi = 1.0
        for _ in 0..<12 {
            let mid = (lo + hi) / 2
            if inGamut(oklabToLinear(SIMD3(L, C * mid * ca, C * mid * sa))) { lo = mid } else { hi = mid }
        }
        c = oklabToLinear(SIMD3(L, C * lo * ca, C * lo * sa))
    }
    return simd_clamp(c, SIMD3(repeating: 0), SIMD3(repeating: 1))
}

func linearToBytes(_ c: SIMD3<Double>) -> (UInt8, UInt8, UInt8) {
    func q(_ v: Double) -> UInt8 { UInt8(max(0, min(255, (linearToSrgb(min(max(v, 0), 1)) * 255).rounded()))) }
    return (q(c.x), q(c.y), q(c.z))
}

// MARK: - A 공식(앱 셰이더와 같은 식)

/// 높이 t(정수리 0 → 바닥 1) · 밝기 차 dL → 선형 sRGB.
func rainbowLinear(t: Double, dL: Double) -> SIMD3<Double> {
    let s = min(max(7 * t - 0.5, 0), 6)
    let k = min(5, Int(floor(s)))
    let f = s - Double(k)
    let Ls = stopLightness[k] + (stopLightness[k + 1] - stopLightness[k]) * f
    let Cs = stopChroma[k] + (stopChroma[k + 1] - stopChroma[k]) * f
    let hs = stopHue[k] + (stopHue[k + 1] - stopHue[k]) * f
    var kc = min(max(1 - chromaSlope * dL, chromaFloor), chromaCeil)
    var dLs = dL
    if dL < 0 {
        var capW = 0.0, lift = 0.0
        for w in shadowWindows {
            let hw = 1 - smoothstep(w.inner, w.outer, hueDistance(hs, w.centre))
            capW = max(capW, hw); lift = max(lift, hw * w.lift)
        }
        kc -= (kc - min(kc, 1.0)) * capW * smoothstep(0, 0.06, -dL)
        dLs = dL * (1 - lift)
    }
    let L = min(max(Ls + dLs, lightnessMin), lightnessMax)
    return lchToLinear(L, Cs * kc, hs)
}

/// 후광 둘레 색상: 순환 8정지점(빨 → … → 보 → 자홍 → 빨) 위의 s ∈ [0, 8).
func haloHue(_ s: Double) -> Double {
    let n = Double(haloCycleHue.count)
    var u = s - n * floor(s / n)
    if u >= n { u -= n }
    let k = Int(floor(u)), f = u - Double(k)
    let a = haloCycleHue[k], b = k + 1 == haloCycleHue.count ? haloCycleHue[0] + 360 : haloCycleHue[k + 1]
    return a + (b - a) * f
}

// MARK: - 메시

struct Mesh {
    var pos: [SIMD3<Float>]
    var uv: [SIMD2<Float>]
    var idx: [Int]
    var key: [Int]
    var neighbors: [[Int]]
    var center: SIMD3<Float>
    var minB: SIMD3<Float>
    var maxB: SIMD3<Float>
    var height: Float { maxB.y - minB.y }
    var diffuse: CGImage
}

func decodedTexture(_ contents: Any?) -> CGImage? {
    guard let contents else { return nil }
    if CFGetTypeID(contents as CFTypeRef) == CGImage.typeID { return (contents as! CGImage) }
    if let data = contents as? Data, let s = CGImageSourceCreateWithData(data as CFData, nil) { return CGImageSourceCreateImageAtIndex(s, 0, nil) }
    if let image = contents as? NSImage { return image.cgImage(forProposedRect: nil, context: nil, hints: nil) }
    if let url = contents as? URL { return NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil) }
    return nil
}

/// 앱 `applyUnlitMaterials` 와 같은 정규화: 512 초과면 줄이고(DeviceRGB · premultipliedLast), 아니면 그대로.
func appDiffuse(_ cg: CGImage) -> CGImage {
    let maxSide = max(cg.width, cg.height)
    guard maxSide > skinSize else { return cg }
    let scale = CGFloat(skinSize) / CGFloat(maxSide)
    let w = max(1, Int((CGFloat(cg.width) * scale).rounded())), h = max(1, Int((CGFloat(cg.height) * scale).rounded()))
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    return ctx.makeImage()!
}

func loadMesh() -> Mesh {
    guard let scene = try? SCNScene(url: URL(fileURLWithPath: modelPath), options: nil) else { fail("모델을 못 읽었다: \(modelPath)") }
    var found: SCNNode?
    scene.rootNode.enumerateHierarchy { node, stop in if node.geometry != nil { found = node; stop.pointee = true } }
    guard let node = found, let g = node.geometry, let vs = g.sources(for: .vertex).first, let ts = g.sources(for: .texcoord).first,
          let el = g.elements.first, g.elements.count == 1, el.primitiveType == .triangles else { fail("메시 구조가 예상과 다르다") }
    // 셰이더의 `_geometry.position` 이 곧 이 물체 좌표여야 높이 상수가 맞는다.
    guard node.simdWorldTransform == matrix_identity_float4x4 else { fail("메시 노드 변환이 단위가 아니다 — 셰이더 높이와 물체 좌표가 갈린다") }
    let n = vs.vectorCount
    var pos = [SIMD3<Float>](repeating: .zero, count: n), uv = [SIMD2<Float>](repeating: .zero, count: n)
    vs.data.withUnsafeBytes { raw in
        for i in 0..<n {
            let b = vs.dataOffset + i * vs.dataStride
            pos[i] = SIMD3(raw.loadUnaligned(fromByteOffset: b, as: Float.self), raw.loadUnaligned(fromByteOffset: b + 4, as: Float.self),
                           raw.loadUnaligned(fromByteOffset: b + 8, as: Float.self))
        }
    }
    ts.data.withUnsafeBytes { raw in
        for i in 0..<n {
            let b = ts.dataOffset + i * ts.dataStride
            uv[i] = SIMD2(raw.loadUnaligned(fromByteOffset: b, as: Float.self), raw.loadUnaligned(fromByteOffset: b + 4, as: Float.self))
        }
    }
    var idx = [Int](); idx.reserveCapacity(el.primitiveCount * 3)
    el.data.withUnsafeBytes { raw in
        for k in 0..<(el.primitiveCount * 3) {
            idx.append(el.bytesPerIndex == 2 ? Int(raw.loadUnaligned(fromByteOffset: k * 2, as: UInt16.self))
                                             : Int(raw.loadUnaligned(fromByteOffset: k * 4, as: UInt32.self)))
        }
    }
    guard let material = g.materials.first, let tex = decodedTexture(material.diffuse.contents) else { fail("디퓨즈가 없다") }
    let (minV, maxV) = scene.rootNode.boundingBox
    let minB = SIMD3<Float>(Float(minV.x), Float(minV.y), Float(minV.z)), maxB = SIMD3<Float>(Float(maxV.x), Float(maxV.y), Float(maxV.z))
    // 같은 위치 정점 합침 + 이웃(정렬 배열 — 합 순서가 실행마다 같아 산출물이 결정적이다).
    var key = [Int](repeating: 0, count: n); var map: [SIMD3<Int32>: Int] = [:]
    for i in 0..<n {
        let q = SIMD3<Int32>(Int32((pos[i].x * 1e4).rounded()), Int32((pos[i].y * 1e4).rounded()), Int32((pos[i].z * 1e4).rounded()))
        if let k = map[q] { key[i] = k } else { map[q] = i; key[i] = i }
    }
    var nbSets = [Set<Int>](repeating: [], count: n)
    for t in stride(from: 0, to: idx.count, by: 3) {
        let ka = key[idx[t]], kb = key[idx[t + 1]], kc = key[idx[t + 2]]
        nbSets[ka].insert(kb); nbSets[ka].insert(kc); nbSets[kb].insert(ka); nbSets[kb].insert(kc); nbSets[kc].insert(ka); nbSets[kc].insert(kb)
    }
    return Mesh(pos: pos, uv: uv, idx: idx, key: key, neighbors: nbSets.map { $0.sorted() }, center: (minB + maxB) / 2,
                minB: minB, maxB: maxB, diffuse: appDiffuse(tex))
}

// MARK: - 밝기 장(시안 E 의 rbData 와 같은 정의)

struct ShadeField {
    var lightness: [Double]   // 텍셀의 다듬은 OKLab L(믿는 텍셀은 원본 — 티끌만 걷음, 나머지는 메시 표면으로 번진 값, 눈 둘레는 정면 격자로 다시 채운 값, UV 틈은 팽창)
    var reference: Double     // 믿는 텍셀 L 의 중앙값(셰이더 `lReference`)
    var despeckled: Int
    var socketRefilled: Int
}

func bakeShadeField(_ mesh: Mesh) -> ShadeField {
    let S = skinSize
    let original = bytes(mesh.diffuse)
    guard mesh.diffuse.width == S, mesh.diffuse.height == S else { fail("디퓨즈가 \(S)² 가 아니다") }
    var texL = [Double](repeating: 0, count: S * S)
    var feature = [Bool](repeating: false, count: S * S)
    var texLuma = [Int](repeating: 0, count: S * S)
    for i in 0..<(S * S) {
        let r = Int(original[i * 4]), g = Int(original[i * 4 + 1]), b = Int(original[i * 4 + 2])
        texLuma[i] = luma(r, g, b)
        feature[i] = !isGoldSkin(r, g, b)
        texL[i] = srgbBytesToOklab(original[i * 4], original[i * 4 + 1], original[i * 4 + 2]).x
    }
    // 금과 같은 '믿는 밝기' 규칙(눈·볼·입 둘레 8텍셀 안은 밝은 피부만).
    let near = dilate(feature, width: S, height: S, radius: featureRadius)
    var ringLumas = [Int]()
    for i in 0..<(S * S) where near[i] && !feature[i] {
        let o = i * 4
        if isSkin(Int(original[o]), Int(original[o + 1]), Int(original[o + 2])) { ringLumas.append(texLuma[i]) }
    }
    ringLumas.sort()
    let brightCut = ringLumas.isEmpty ? 0 : ringLumas[ringLumas.count / 2] - 12
    var knownLum = [Bool](repeating: false, count: S * S)
    for i in 0..<(S * S) {
        let o = i * 4, r = Int(original[o]), g = Int(original[o + 1]), b = Int(original[o + 2])
        knownLum[i] = near[i] ? (isSkin(r, g, b) && texLuma[i] >= brightCut) : isGoldSkin(r, g, b)
    }
    // 티끌 걷기: 라벤더 텍스처의 1–2텍셀 밝은 점은 무지개 위에서 흰 점으로 튄다 — 믿는 텍셀마다 5×5 믿는 이웃 L 중앙값과 0.02 넘게 다르면 중앙값.
    var despeckled = texL, replaced = 0
    for y in 0..<S { for x in 0..<S where knownLum[y * S + x] {
        var window = [Double]()
        for yy in max(0, y - 2)...min(S - 1, y + 2) { for xx in max(0, x - 2)...min(S - 1, x + 2) where knownLum[yy * S + xx] { window.append(texL[yy * S + xx]) } }
        if window.count < 9 { continue }
        window.sort()
        let med = window[window.count / 2]
        if abs(texL[y * S + x] - med) > 0.02 { despeckled[y * S + x] = med; replaced += 1 }
    } }
    texL = despeckled
    var knownLs = (0..<(S * S)).filter { knownLum[$0] }.map { texL[$0] }
    knownLs.sort()
    let reference = knownLs[knownLs.count / 2]
    // 못 믿는 텍셀: 정점 밝기(믿는 텍셀에서) → 메시 표면을 따라 번지기.
    let nv = mesh.pos.count
    var vSum = [Double](repeating: 0, count: nv), vCount = [Double](repeating: 0, count: nv)
    for i in 0..<nv {
        let tx = min(max(Int(mesh.uv[i].x * Float(S)), 0), S - 1), ty = min(max(Int(mesh.uv[i].y * Float(S)), 0), S - 1)
        if knownLum[ty * S + tx] { vSum[mesh.key[i]] += texL[ty * S + tx]; vCount[mesh.key[i]] += 1 }
    }
    let reps = (0..<nv).filter { mesh.key[$0] == $0 }
    let vKnown = (0..<nv).map { vCount[$0] > 0 }
    var vL = (0..<nv).map { vCount[$0] > 0 ? vSum[$0] / vCount[$0] : 0 }
    var vHave = vKnown
    var growing = true
    while growing {
        growing = false
        var next = vL, nextHave = vHave
        for i in reps where !vHave[i] {
            var s = 0.0, c = 0.0
            for j in mesh.neighbors[i] where vHave[j] { s += vL[j]; c += 1 }
            if c > 0 { next[i] = s / c; nextHave[i] = true; growing = true }
        }
        vL = next; vHave = nextHave
    }
    for _ in 0..<60 {
        var next = vL
        for i in reps where !vKnown[i] && !mesh.neighbors[i].isEmpty {
            next[i] = mesh.neighbors[i].reduce(0) { $0 + vL[$1] } / Double(mesh.neighbors[i].count)
        }
        vL = next
    }
    // UV 래스터: 텍셀 중심의 표면 밝기 · 물체 좌표.
    var surfL = [Double](repeating: 0, count: S * S), weight = [Double](repeating: 0, count: S * S)
    var surfPos = [SIMD3<Double>](repeating: .zero, count: S * S)
    for t in stride(from: 0, to: mesh.idx.count, by: 3) {
        let i0 = mesh.idx[t], i1 = mesh.idx[t + 1], i2 = mesh.idx[t + 2]
        let a = mesh.uv[i0] * Float(S), b = mesh.uv[i1] * Float(S), c = mesh.uv[i2] * Float(S)
        let area = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
        if abs(area) < 1e-12 { continue }
        let x0 = max(0, Int(floor(min(a.x, b.x, c.x) - 0.5))), x1 = min(S - 1, Int(ceil(max(a.x, b.x, c.x) - 0.5)))
        let y0 = max(0, Int(floor(min(a.y, b.y, c.y) - 0.5))), y1 = min(S - 1, Int(ceil(max(a.y, b.y, c.y) - 0.5)))
        if x0 > x1 || y0 > y1 { continue }
        for y in y0...y1 { for x in x0...x1 {
            let px = Float(x) + 0.5, py = Float(y) + 0.5
            let w0 = ((b.x - px) * (c.y - py) - (b.y - py) * (c.x - px)) / area
            let w1 = ((c.x - px) * (a.y - py) - (c.y - py) * (a.x - px)) / area
            let w2 = 1 - w0 - w1
            if w0 < -1e-4 || w1 < -1e-4 || w2 < -1e-4 { continue }
            let o = y * S + x
            surfL[o] += vL[mesh.key[i0]] * Double(w0) + vL[mesh.key[i1]] * Double(w1) + vL[mesh.key[i2]] * Double(w2)
            let p = mesh.pos[i0] * w0 + mesh.pos[i1] * w1 + mesh.pos[i2] * w2
            surfPos[o] += SIMD3<Double>(Double(p.x), Double(p.y), Double(p.z))
            weight[o] += 1
        } }
    }
    var lightness = [Double](repeating: 0, count: S * S)
    var filled = [Bool](repeating: false, count: S * S)
    for i in 0..<(S * S) where weight[i] > 0 {
        lightness[i] = knownLum[i] ? texL[i] : surfL[i] / weight[i]
        filled[i] = true
    }
    let refilled = refillEyeSockets(&lightness, positions: (0..<(S * S)).map { weight[$0] > 0 ? surfPos[$0] / weight[$0] : .zero },
                                    covered: filled, trusted: knownLum)
    var pending = true
    while pending {
        pending = false
        var nL = lightness, nFilled = filled
        for y in 0..<S { for x in 0..<S where !filled[y * S + x] {
            var sd = 0.0, c = 0.0
            for dy in -1...1 { for dx in -1...1 where dx != 0 || dy != 0 {
                let xx = x + dx, yy = y + dy
                if xx < 0 || yy < 0 || xx >= S || yy >= S { continue }
                let q = yy * S + xx
                if filled[q] { sd += lightness[q]; c += 1 }
            } }
            if c > 0 { let o = y * S + x; nL[o] = sd / c; nFilled[o] = true; pending = true }
        } }
        lightness = nL; filled = nFilled
    }
    return ShadeField(lightness: lightness, reference: reference, despeckled: replaced, socketRefilled: refilled)
}

/// 감은 눈 둘레 다시 채우기. 감은 눈은 눈 자리를 이 밝기 맵으로 덮는다(앱 `RainbowAingFinish.closedEyesImage` — 덮인 자리도 둘레도 이 맵).
/// 그런데 눈 안쪽(못 믿는 텍셀)은 성긴 메시 정점에서 번진 값이라 둘레보다 어둡고(≈ 0.86), 눈 바깥엔 '믿는 텍셀'이 될 만큼만 어두운 칠해진
/// 눈두덩 테가 남아(≈ 0.875 → 0.89) 눈 가장자리에 밝기 계단이 섰다 — 셰이더의 채도 규칙(k = 1 − 3·dL)이 그 계단을 주황 테로 키워 감은 눈이
/// '고글'처럼 보였다(검토 프로브: 560×680 감은 눈, 2px 바퀴 사이 최대 계단 1.40 — 황금 0.87 · 아잉 0.33). 눈 장식 팽창(8 → 12·14텍셀)은 그 테를
/// 못 걷는다(밝기 컷을 넘는 텍셀이라 그대로 믿는다 — 실측 계단 그대로 1.39).
/// 고침: 두 눈 앵커에서 x·y 거리 `eyeSocketRadius` 안의 앞면 텍셀을 칠한 값 대신, 그 밖 믿는 텍셀의 밝기를 경계로 **정면 격자**에서 라플라스
/// 방정식을 풀어(경계값은 그대로 · 안은 매끈) 그 자리 값으로 채운다. 메시 정점 · 텍셀 이웃 그래프로 풀면 UV 섬 사이 연결이 약한 곳에서 계단이
/// 그대로 남아(실측) 얼굴 앞면을 높이 장(x·y → 값)으로 본다 — 눈 둘레는 앞면(z > 0.2)이라 한 x·y 에 면이 하나다.
/// 볼 분홍 · 입 빨강 텍셀도 같이 채워지지만 보이지 않는다(합성이 피부 판정 밖 텍셀은 원본을 쓴다). 믿는 텍셀 집합(`lReference`)은 그대로다.
func refillEyeSockets(_ lightness: inout [Double], positions: [SIMD3<Double>], covered: [Bool], trusted: [Bool]) -> Int {
    let h = eyeSocketGrid, margin = 0.05
    func socketDistance(_ x: Double, _ y: Double) -> Double {
        eyeAnchors.map { ((x - $0.x) * (x - $0.x) + (y - $0.y) * (y - $0.y)).squareRoot() }.min()!
    }
    var refill = [Int]()
    var inSocket = [Bool](repeating: false, count: lightness.count)
    for i in lightness.indices where covered[i] && positions[i].z > 0.2 && socketDistance(positions[i].x, positions[i].y) < eyeSocketRadius {
        refill.append(i); inSocket[i] = true
    }
    // 정면 격자(두 눈 둘레 + 여유): 둘레 밖 칸 = 그 칸에 든 믿는 앞면 텍셀 밝기 평균(고정) · 둘레 안 칸 · 여유 띠의 빈 칸 = 풀 칸.
    let x0 = eyeAnchors.map(\.x).min()! - eyeSocketRadius - margin - h, y0 = eyeAnchors.map(\.y).min()! - eyeSocketRadius - margin - h
    let gw = Int(((eyeAnchors.map(\.x).max()! + eyeSocketRadius + margin + h - x0) / h).rounded(.up))
    let gh = Int(((eyeAnchors.map(\.y).max()! + eyeSocketRadius + margin + h - y0) / h).rounded(.up))
    var sum = [Double](repeating: 0, count: gw * gh), count = [Double](repeating: 0, count: gw * gh)
    for i in lightness.indices where covered[i] && trusted[i] && !inSocket[i] && positions[i].z > 0.2 {
        let cx = Int(floor((positions[i].x - x0) / h)), cy = Int(floor((positions[i].y - y0) / h))
        guard cx >= 0, cy >= 0, cx < gw, cy < gh else { continue }
        sum[cy * gw + cx] += lightness[i]; count[cy * gw + cx] += 1
    }
    var value = [Double](repeating: 0, count: gw * gh)
    var fixed = [Bool](repeating: false, count: gw * gh), solve = [Bool](repeating: false, count: gw * gh)
    var rimSum = 0.0, rimCount = 0.0
    for c in 0..<(gw * gh) {
        let d = socketDistance(x0 + (Double(c % gw) + 0.5) * h, y0 + (Double(c / gw) + 0.5) * h)
        if d >= eyeSocketRadius && count[c] > 0 {
            fixed[c] = true; value[c] = sum[c] / count[c]
            if d < eyeSocketRadius + margin { rimSum += value[c]; rimCount += 1 }
        } else if d < eyeSocketRadius + margin {
            solve[c] = true
        }
    }
    guard rimCount > 0 else { fail("눈 둘레 밖에 믿는 텍셀이 없다 — 앵커가 메시와 갈렸다") }
    for c in 0..<(gw * gh) where solve[c] { value[c] = rimSum / rimCount }
    // 과완화(SOR) — 풀 칸 수천 개라 4000번이면 수렴한다(순서 고정 → 결정적). 격자 밖 · 고정도 풀 칸도 아닌 이웃은 빼고 평균(닫힌 경계).
    for _ in 0..<4000 {
        for c in 0..<(gw * gh) where solve[c] {
            let x = c % gw, y = c / gw
            var s = 0.0, n = 0.0
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let xx = x + dx, yy = y + dy
                guard xx >= 0, yy >= 0, xx < gw, yy < gh else { continue }
                let q = yy * gw + xx
                if fixed[q] || solve[q] { s += value[q]; n += 1 }
            }
            if n > 0 { value[c] += 1.9 * (s / n - value[c]) }
        }
    }
    for i in refill {
        let fx = (positions[i].x - x0) / h - 0.5, fy = (positions[i].y - y0) / h - 0.5
        let ix = Int(floor(fx)), iy = Int(floor(fy)), ax = fx - Double(ix), ay = fy - Double(iy)
        var acc = 0.0, wsum = 0.0
        for (dx, dy, w) in [(0, 0, (1 - ax) * (1 - ay)), (1, 0, ax * (1 - ay)), (0, 1, (1 - ax) * ay), (1, 1, ax * ay)] {
            let xx = ix + dx, yy = iy + dy
            guard xx >= 0, yy >= 0, xx < gw, yy < gh, fixed[yy * gw + xx] || solve[yy * gw + xx] else { continue }
            acc += value[yy * gw + xx] * w; wsum += w
        }
        guard wsum > 0 else { fail("눈 둘레 텍셀 \(i) 가 격자 밖이다") }
        lightness[i] = acc / wsum
    }
    return refill.count
}

/// 밝기 맵: 피부 텍셀은 원본 색 방향(OKLab a·b) 그대로에 다듬은 밝기, 나머지(눈·볼·입·UV 틈)는 피부 a·b 중앙값에 그 자리 밝기 —
/// 모두 isGoldSkin 이어야 한다(앱 셰이더가 그 텍셀을 피부로 알아봐야 무지개가 된다). 못 맞추면 멈춘다.
func shadeMap(_ field: ShadeField, original: [UInt8]) -> CGImage {
    let S = skinSize
    var aSkin = [Double](), bSkin = [Double]()
    var labs = [SIMD3<Double>](repeating: .zero, count: S * S)
    var skin = [Bool](repeating: false, count: S * S)
    for i in 0..<(S * S) {
        labs[i] = srgbBytesToOklab(original[i * 4], original[i * 4 + 1], original[i * 4 + 2])
        skin[i] = isGoldSkin(Int(original[i * 4]), Int(original[i * 4 + 1]), Int(original[i * 4 + 2]))
        if skin[i] { aSkin.append(labs[i].y); bSkin.append(labs[i].z) }
    }
    aSkin.sort(); bSkin.sort()
    let aMed = aSkin[aSkin.count / 2], bMed = bSkin[bSkin.count / 2]
    var px = [UInt8](repeating: 255, count: S * S * 4)
    var rescued = 0
    for i in 0..<(S * S) {
        let L = min(max(field.lightness[i], 0.3), 0.99)
        var (r, g, b) = linearToBytes(oklabToLinear(SIMD3(L, skin[i] ? labs[i].y : aMed, skin[i] ? labs[i].z : bMed)))
        if !isGoldSkin(Int(r), Int(g), Int(b)) {
            // 원본 색 방향으로 밝기만 바꾸면 피부 판정 밖으로 나가는 텍셀(채도가 0.05 아래로 내려간 아주 옅은 텍셀) — 피부 중앙 색 방향으로.
            (r, g, b) = linearToBytes(oklabToLinear(SIMD3(L, aMed, bMed)))
            rescued += 1
            guard isGoldSkin(Int(r), Int(g), Int(b)) else { fail(String(format: "밝기 맵 텍셀 %d 이 피부 판정 밖이다(L %.3f)", i, L)) }
        }
        px[i * 4] = r; px[i * 4 + 1] = g; px[i * 4 + 2] = b
    }
    print(String(format: "[shade] 피부 a·b 중앙값 (%.4f, %.4f) · 피부 방향으로 옮긴 텍셀 %d", aMed, bMed, rescued))
    return makeImage(px, S, S)
}

// MARK: - 렌더(SceneKit 오프스크린 — 화면에 창 없음)

struct FrontCamera {
    let position: SIMD3<Float>, center: SIMD3<Float>
    /// `bodyYawDegrees`: 몸이 카메라에 대해 돈 각(후광 각도 칸) — 금 스크립트와 같은 카메라(몸 대신 카메라를 −ψ 돌린다).
    init(_ mesh: Mesh, bodyYawDegrees: Float = 0) {
        let h = mesh.height
        let dist = h / 2 / tan(frontFOV / 2 * .pi / 180) * frontZoom
        center = mesh.center
        let a = -bodyYawDegrees * .pi / 180
        position = SIMD3(center.x + dist * sin(a), center.y + h * frontRaise, center.z + dist * cos(a))
    }
    func node() -> SCNNode {
        let node = SCNNode(); node.camera = SCNCamera(); node.camera!.fieldOfView = CGFloat(frontFOV)
        node.simdPosition = position
        node.simdLook(at: center)
        return node
    }
}

/// 앱 카메라(CheckCharacter3DScene.addFramingCamera)의 방향.
func appCameraPose(_ mesh: Mesh) -> (SIMD3<Float>, SIMD3<Float>) {
    let extent = max(mesh.maxB.x - mesh.minB.x, mesh.maxB.y - mesh.minB.y)
    let distance = extent / (2 * tan(20 * Float.pi / 180)) * 1.4
    return (SIMD3(mesh.center.x, mesh.center.y + extent * 0.55, mesh.maxB.z + distance),
            SIMD3(mesh.center.x, mesh.center.y - extent * 0.16, mesh.center.z))
}

/// 초상 카메라: 앱 카메라 방향으로 몸 중심을 보고, 몸이 프레임의 `fill` 만큼 차는 거리.
func portraitCamera(_ mesh: Mesh, fill: Float) -> SCNNode {
    let (pos, target) = appCameraPose(mesh)
    let dir = simd_normalize(target - pos)
    let right = simd_normalize(simd_cross(dir, SIMD3<Float>(0, 1, 0))), up = simd_cross(right, dir)
    let tanHalf = tan(20 * Float.pi / 180)
    var d: Float = 3
    for _ in 0..<12 {
        let cpos = mesh.center - dir * d
        var x0: Float = .infinity, x1: Float = -.infinity, y0: Float = .infinity, y1: Float = -.infinity
        for p in mesh.pos {
            let v = p - cpos, z = simd_dot(v, dir)
            let x = simd_dot(v, right) / z / tanHalf, y = simd_dot(v, up) / z / tanHalf
            x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y)
        }
        d *= max(x1 - x0, y1 - y0) / 2 / fill
    }
    let n = SCNNode(); n.camera = SCNCamera(); n.camera!.fieldOfView = 40
    n.camera!.zNear = 0.01; n.camera!.zFar = 1_000
    n.simdPosition = mesh.center - dir * d; n.simdLook(at: mesh.center)
    return n
}

/// aing.scn 을 unlit 으로 그린다(배경 투명). `modifiers` 가 있으면 몸 재질에 건다.
func renderModel(_ mesh: Mesh, size: CGSize, camera: SCNNode, modifiers: [SCNShaderModifierEntryPoint: String]? = nil,
                 antialiasing: SCNAntialiasingMode = .multisampling4X) -> CGImage {
    guard let scene = try? SCNScene(url: URL(fileURLWithPath: modelPath), options: nil) else { fail("모델을 못 읽었다") }
    scene.background.contents = NSColor.clear
    scene.rootNode.enumerateHierarchy { node, _ in
        node.geometry?.materials.forEach { m in
            m.lightingModel = .constant
            m.diffuse.contents = mesh.diffuse
            if let modifiers { m.shaderModifiers = modifiers }
        }
    }
    scene.rootNode.addChildNode(camera)
    let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
    renderer.scene = scene; renderer.pointOfView = camera; renderer.autoenablesDefaultLighting = false
    let shot = renderer.snapshot(atTime: 0, with: size, antialiasingMode: antialiasing)
    guard let tiff = shot.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let cg = rep.cgImage else { fail("렌더 실패") }
    return cg
}

// MARK: - 후광

let ciContext = CIContext(options: [.useSoftwareRenderer: true])

/// CI `render(toBitmap:)` 의 첫 행이 그림의 위인가(실측 판정 — 시안 스크립트와 같다).
let ciBitmapTopFirst: Bool = {
    var p = [UInt8](repeating: 0, count: 4 * 4 * 4)
    for x in 0..<4 { p[x * 4 + 3] = 255; p[x * 4] = 255 }
    let img = makeImage(p, 4, 4)
    var f = [Float](repeating: 0, count: 4 * 4 * 4)
    ciContext.render(CIImage(cgImage: img), toBitmap: &f, rowBytes: 4 * 16, bounds: CGRect(x: 0, y: 0, width: 4, height: 4), format: .RGBAf, colorSpace: nil)
    let top = f[3] > 0.5, bottom = f[(3 * 4) * 4 + 3] > 0.5
    guard top != bottom else { fail("CI 비트맵 방향 판정 실패") }
    return top
}()

/// 금 후광과 같은 층의 알파(넓게 σ40·α0.68 / 가운데 σ18·α0.8 ×2 / 안쪽 σ6·α0.8 ×2, σ × sigmaK)에, 색만 둘레 각(12시 빨강 → 시계 방향)의
/// 순환 무지개. 넓은 층은 진한 색, 안쪽은 흰빛에 가깝게(금의 진한 금 → 크림 구조). 선형 프리멀티로 겹친 뒤 sRGB 로 적는다.
/// `center` 는 화면 좌표(위가 0).
func rainbowHaloImage(silhouette: CGImage, sigmaK: Double, center: SIMD2<Double>) -> CGImage {
    let input = CIImage(cgImage: silhouette)
    let ext = input.extent
    let w = Int(ext.width), h = Int(ext.height)
    func alphaLayer(_ alpha: Double, _ sigma: Double) -> [Float] {
        let img = input.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: 1), "inputGVector": CIVector(x: 0, y: 0, z: 0, w: 1),
            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: 1), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: alpha),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)])
            .clampedToExtent().applyingGaussianBlur(sigma: sigma).cropped(to: ext)
        var f = [Float](repeating: 0, count: w * h * 4)
        ciContext.render(img, toBitmap: &f, rowBytes: w * 16, bounds: ext, format: .RGBAf, colorSpace: nil)
        return (0..<(w * h)).map { f[$0 * 4 + 3] }
    }
    let wide = alphaLayer(min(1, 0.85 * haloK), 40 * sigmaK)
    let mid = alphaLayer(min(1, 1.00 * haloK), 18 * sigmaK)
    let inner = alphaLayer(min(1, 1.00 * haloK), 6 * sigmaK)
    var px = [UInt8](repeating: 0, count: w * h * 4)
    for y in 0..<h { for x in 0..<w {
        let i = y * w + x
        let screenY = ciBitmapTopFirst ? y : h - 1 - y
        let sx = Double(x) + 0.5 - center.x, sy = Double(screenY) + 0.5 - center.y
        var theta = atan2(sx, -sy) / (2 * .pi)      // 12시 0 → 시계 방향 증가
        if theta < 0 { theta += 1 }
        let hue = haloHue(theta * Double(haloCycleHue.count))
        let cw = lchToLinear(0.78, 0.15, hue), cm = lchToLinear(0.87, 0.10, hue), cin = lchToLinear(0.96, 0.035, hue)
        var acc = SIMD3<Double>(0, 0, 0), a = 0.0
        for (c, al) in [(cw, Double(wide[i])), (cm, Double(mid[i])), (cm, Double(mid[i])), (cin, Double(inner[i])), (cin, Double(inner[i]))] {
            acc = c * al + acc * (1 - al); a = al + a * (1 - al)
        }
        let o = (screenY * w + x) * 4
        if a > 1e-6 {
            let (r, g, b) = linearToBytes(acc / a)
            px[o] = UInt8((Double(r) * a).rounded()); px[o + 1] = UInt8((Double(g) * a).rounded()); px[o + 2] = UInt8((Double(b) * a).rounded())
            px[o + 3] = UInt8((a * 255).rounded())
        }
    } }
    return makeImage(px, w, h)
}

func borderAlpha(_ image: CGImage) -> Double {
    let w = image.width, h = image.height, px = bytes(image)
    var m = 0
    for y in 0..<h { for x in 0..<w where x < 2 || y < 2 || x >= w - 2 || y >= h - 2 { m = max(m, Int(px[(y * w + x) * 4 + 3])) } }
    return Double(m) / 255
}

/// 후광 한 칸(512²): 몸 요 `cell × 10°` 의 실루엣 → 무지개 층. 중심 = 프레임 중심(= 바운딩박스 중심의 투영 — 금 판 규약).
func makeHalo(_ mesh: Mesh, cell: Int) -> CGImage {
    let silhouette = renderModel(mesh, size: CGSize(width: haloSize, height: haloSize),
                                 camera: FrontCamera(mesh, bodyYawDegrees: Float(cell * haloYawStep)).node())
    let halo = rainbowHaloImage(silhouette: silhouette, sigmaK: haloK * (Double(haloSize) / 2) / haloBodyPixels,
                                center: SIMD2(Double(haloSize) / 2, Double(haloSize) / 2))
    let border = borderAlpha(halo)
    guard border <= borderAlphaLimit else { fail("후광 \(cell * haloYawStep)° 테두리 알파 \(border)") }
    return halo
}

/// 각도 칸(1…35)의 저장본: 512² → 160²(sRGB 프리멀티 문맥 · 고품질 보간). 줄인 뒤 테두리도 다시 잰다.
func makeHaloCell(_ mesh: Mesh, cell: Int) -> CGImage {
    let full = makeHalo(mesh, cell: cell)
    let ctx = CGContext(data: nil, width: haloCellSize, height: haloCellSize, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.draw(full, in: CGRect(x: 0, y: 0, width: haloCellSize, height: haloCellSize))
    let small = ctx.makeImage()!
    let border = borderAlpha(small)
    guard border <= borderAlphaLimit else { fail("후광 \(cell * haloYawStep)° (\(haloCellSize)²) 테두리 알파 \(border)") }
    return small
}

func haloCellOutput(_ cell: Int) -> String {
    cell == 0 ? "\(resourceDir)/\(characterID)-halo.png" : "\(resourceDir)/\(characterID)-halo-\(String(format: "%03d", cell * haloYawStep)).png"
}

// MARK: - 초상

/// 몸 높이 지도(192²): 초상 카메라로 메시를 그려 픽셀마다 물체 좌표 높이 t(정수리 0 → 바닥 1)를 읽는다. 8비트 두 채널
/// (R = t, G = fract(16t))로 적어 1/4096 정밀도로 되읽는다(sRGB 부호화를 되돌린 뒤). 몸 밖은 이웃에서 번져 채운다.
/// 반환: (t 지도, 몸 덮임, 몸 상자 x0 x1 y0 y1).
func heightMap(_ mesh: Mesh, camera: SCNNode, size: Int) -> ([Double], [Bool], (Int, Int, Int, Int)) {
    let modifiers: [SCNShaderModifierEntryPoint: String] = [
        .geometry: "#pragma varyings\nfloat3 rbP;\n#pragma body\nout.rbP = _geometry.position.xyz;\n",
        .fragment: "#pragma varyings\nfloat3 rbP;\n#pragma body\n"
            + String(format: "float rbT = clamp((%.6f - in.rbP.y) / %.6f, 0.0, 1.0);\n", bodyTop, bodyHeight)
            + "_output.color = float4(rbT, fract(rbT * 16.0), 0.0, 1.0);\n",
    ]
    let image = renderModel(mesh, size: CGSize(width: size, height: size), camera: camera, modifiers: modifiers, antialiasing: .none)
    let px = bytes(image, space: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!)
    var t = [Double](repeating: 0, count: size * size), body = [Bool](repeating: false, count: size * size)
    var x0 = size, x1 = -1, y0 = size, y1 = -1
    for y in 0..<size { for x in 0..<size {
        let i = y * size + x
        guard px[i * 4 + 3] == 255 else { continue }
        let coarse = srgbToLinear(Double(px[i * 4]) / 255), fine = srgbToLinear(Double(px[i * 4 + 1]) / 255)
        t[i] = (( coarse * 16 - fine).rounded() + fine) / 16
        body[i] = true
        x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y)
    } }
    guard x1 > x0, y1 > y0 else { fail("높이 지도가 비었다") }
    inpaint(&t, known: body, width: size, height: size, relax: 0)
    return (t, body, (x0, x1, y0, y1))
}

func bilinear(_ v: [Double], _ size: Int, _ x: Double, _ y: Double) -> Double {
    let fx = min(max(x - 0.5, 0), Double(size - 1)), fy = min(max(y - 0.5, 0), Double(size - 1))
    let ix = min(Int(fx), size - 2), iy = min(Int(fy), size - 2)
    let ax = fx - Double(ix), ay = fy - Double(iy)
    let a = v[iy * size + ix], b = v[iy * size + ix + 1], c = v[(iy + 1) * size + ix], d = v[(iy + 1) * size + ix + 1]
    return (a * (1 - ax) + b * ax) * (1 - ay) + (c * (1 - ax) + d * ax) * ay
}

func over(_ top: CGImage, _ bottom: CGImage) -> CGImage {
    let out = CIImage(cgImage: top).composited(over: CIImage(cgImage: bottom))
    return ciContext.createCGImage(out, from: CIImage(cgImage: bottom).extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)!
}

/// 후광만 프레임 가장자리 10px 안에서 0 으로 부드럽게 접는다(금 초상과 같다).
func fadedAtFrame(_ image: CGImage) -> CGImage {
    let w = image.width, h = image.height
    var px = bytes(image, space: CGColorSpace(name: CGColorSpace.sRGB)!)
    for y in 0..<h { for x in 0..<w {
        let d = min(Double(x) + 0.5, Double(y) + 0.5, Double(w - x) - 0.5, Double(h - y) - 0.5)
        let t = min(max((d - 1) / (portraitFadePixels - 1), 0), 1), f = t * t * (3 - 2 * t)
        let o = (y * w + x) * 4
        for c in 0..<4 { px[o + c] = UInt8((Double(px[o + c]) * f).rounded()) }
    } }
    return makeImage(px, w, h)
}

/// 아잉 초상(2D, 192²)의 피부만 무지개로 바꾼다 — 금 초상과 같은 틀(피부 핵심 · 볼터치 대표색 · 그 자리 피부색 S · 픽셀마다 피부 비율 β,
/// out = P + β·(무지개 − S)). 무지개 색 = A 공식(t = 몸 높이 지도를 몸 상자끼리 맞춰 읽은 값, dL = OKLab L(S) − 피부 핵심 L 중앙값).
/// 그 뒤 몸을 0.88배로 줄이고 무지개 후광(같은 층 · σ ∝ 몸 높이 · 중심 = 몸 알파 무게중심)을 깐다.
func makePortrait(_ source: CGImage, label: String, heights: ([Double], [Bool], (Int, Int, Int, Int)), heightSize: Int) -> CGImage {
    let w = source.width, h = source.height
    guard w == 192, h == 192 else { fail("초상이 192² 가 아니다: \(label)") }
    let px = bytes(source, space: CGColorSpace(name: CGColorSpace.sRGB)!)
    let n = w * h
    var P = [SIMD3<Double>](repeating: .zero, count: n), A = [Double](repeating: 0, count: n)
    for i in 0..<n {
        let a = Double(px[i * 4 + 3]) / 255; A[i] = a
        if a > 0 { P[i] = SIMD3(Double(px[i * 4]), Double(px[i * 4 + 1]), Double(px[i * 4 + 2])) / a }
    }
    var core = [Bool](repeating: false, count: n)
    var blushSum = SIMD3<Double>(0, 0, 0), blushCount = 0.0
    for i in 0..<n where A[i] >= 0.98 {
        let (hue, sat, l) = hueSatLum(P[i].x, P[i].y, P[i].z)
        let browOrLid = hue > 265 && sat > 0.33 && l < 0.65
        if hue >= 232, hue <= 292, sat >= 0.05, sat <= 0.65, l > 0.25, !browOrLid { core[i] = true }
        if (hue >= 330 || hue <= 8), sat >= 0.2, sat <= 0.7, l > 0.55 { blushSum += P[i]; blushCount += 1 }
    }
    guard blushCount > 0 else { fail("볼터치를 못 찾았다: \(label)") }
    let K = blushSum / blushCount
    var S = P
    for ch in 0..<3 {
        var v = (0..<n).map { P[$0][ch] }
        inpaint(&v, known: core, width: w, height: h, relax: 30)
        for i in 0..<n { S[i][ch] = v[i] }
    }
    // 밝기 기준: 피부 핵심의 OKLab L 중앙값.
    func oklabL(_ c: SIMD3<Double>) -> Double {
        linearToOklab(SIMD3(srgbToLinear(min(max(c.x / 255, 0), 1)), srgbToLinear(min(max(c.y / 255, 0), 1)), srgbToLinear(min(max(c.z / 255, 0), 1)))).x
    }
    var coreL = (0..<n).filter { core[$0] }.map { oklabL(P[$0]) }
    coreL.sort()
    let lRef2D = coreL[coreL.count / 2]
    // 몸 상자끼리 맞춰 높이를 읽는다.
    var bx0 = w, bx1 = -1, by0 = h, by1 = -1
    for y in 0..<h { for x in 0..<w where A[y * w + x] > 0.5 { bx0 = min(bx0, x); bx1 = max(bx1, x); by0 = min(by0, y); by1 = max(by1, y) } }
    let (tMap, _, box) = heights
    let gx0 = Double(box.0), gw = Double(box.1 - box.0 + 1), gy0 = Double(box.2), gh = Double(box.3 - box.2 + 1)
    let bw = Double(bx1 - bx0 + 1), bh = Double(by1 - by0 + 1)
    var out = [UInt8](repeating: 0, count: n * 4)
    for y in 0..<h { for x in 0..<w where A[y * w + x] > 0 {
        let i = y * w + x
        let s = S[i]
        let gx = gx0 + (Double(x) + 0.5 - Double(bx0)) / bw * gw, gy = gy0 + (Double(y) + 0.5 - Double(by0)) / bh * gh
        let t = bilinear(tMap, heightSize, gx, gy)
        let (r, g, b) = linearToBytes(rainbowLinear(t: t, dL: oklabL(s) - lRef2D))
        let G = SIMD3(Double(r), Double(g), Double(b))
        var beta: Double
        if core[i] || A[i] < 0.98 {
            beta = 1
        } else {
            let d = P[i] - s, ks = K - s
            let a = simd_dot(d, ks) / max(1e-6, simd_length_squared(ks))
            let resid = simd_length(d - min(max(a, 0), 1) * ks)
            if resid <= 20, a > -0.1, a < 1.1 { beta = 1 - min(max(a, 0), 1) }
            else { beta = min(max(1 - simd_length(d) / 80, 0), 1) }
        }
        let o = simd_clamp(P[i] + beta * (G - s), SIMD3(repeating: 0), SIMD3(repeating: 255))
        out[i * 4] = UInt8((o.x * A[i]).rounded()); out[i * 4 + 1] = UInt8((o.y * A[i]).rounded())
        out[i * 4 + 2] = UInt8((o.z * A[i]).rounded()); out[i * 4 + 3] = px[i * 4 + 3]
    } }
    let recolored = makeImage(out, w, h)
    // 몸 0.88배(가운데 기준).
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    let sw = Double(w) * portraitBodyScale, sh = Double(h) * portraitBodyScale
    ctx.draw(recolored, in: CGRect(x: (Double(w) - sw) / 2, y: (Double(h) - sh) / 2, width: sw, height: sh))
    let body = ctx.makeImage()!
    let bodyPx = bytes(body, space: CGColorSpace(name: CGColorSpace.sRGB)!)
    var y0 = h, y1 = -1, cx = 0.0, cy = 0.0, cw = 0.0
    for y in 0..<h { for x in 0..<w {
        let a = Double(bodyPx[(y * w + x) * 4 + 3]) / 255
        if a > 0.5 { y0 = min(y0, y); y1 = max(y1, y) }
        cx += a * (Double(x) + 0.5); cy += a * (Double(y) + 0.5); cw += a
    } }
    let bodyPixels = Double(y1 - y0 + 1)
    let k = haloK * bodyPixels / haloBodyPixels
    let result = over(body, fadedAtFrame(rainbowHaloImage(silhouette: body, sigmaK: k, center: SIMD2(cx / cw, cy / cw))))
    let border = borderAlpha(result)
    print(String(format: "[portrait] %@: 볼터치 %d,%d,%d · 피부 L 기준 %.4f · 몸 높이 %.0fpx · 후광 k %.4f · 테두리 2px 최대 알파 %.4f",
                 label, Int(K.x), Int(K.y), Int(K.z), lRef2D, bodyPixels, k, border))
    guard border <= borderAlphaLimit else { fail("\(label) 테두리 알파 \(border) > \(borderAlphaLimit)") }
    return result
}

// MARK: - 실행

var args = Array(CommandLine.arguments.dropFirst())
if args.first == "--out" {
    guard args.count == 2 else { fail("사용: --out <폴더>") }
    outRoot = args[1]
    args.removeAll()
}
guard args.isEmpty else { fail("모르는 인자: \(args)") }
guard FileManager.default.fileExists(atPath: modelPath) else { fail("저장소 루트에서 실행하라(\(modelPath) 없음)") }

let started = Date()
let mesh = loadMesh()
guard abs(Double(mesh.maxB.y) - bodyTop) < 1e-5, abs(Double(mesh.height) - bodyHeight) < 1e-5 else {
    fail(String(format: "메시 높이가 셰이더 상수와 다르다: 정수리 %.6f · 높이 %.6f", Double(mesh.maxB.y), Double(mesh.height)))
}

let field = bakeShadeField(mesh)
print(String(format: "[shade] 티끌 걷기 %d텍셀 · 눈 둘레 다시 채움 %d텍셀 · 믿는 텍셀 L 중앙값 %.4f(셰이더 상수 %.4f)",
             field.despeckled, field.socketRefilled, field.reference, lReference))
guard abs(field.reference - lReference) < 5e-5 else { fail("밝기 기준이 셰이더 상수와 다르다 — 앱 RainbowAingArt.lightnessReference 를 고쳐라") }
writePNG(shadeMap(field, original: bytes(mesh.diffuse)), "\(resourceDir)/\(characterID)-shade.png")

// 후광 — 간격을 바꿨다면 옛 칸 파일이 남지 않게 지금 규칙에 없는 aing_rainbow-halo-NNN.png 를 먼저 지운다.
let cellFiles = Set((1..<haloCellCount).map { URL(fileURLWithPath: haloCellOutput($0)).lastPathComponent })
for name in (try? FileManager.default.contentsOfDirectory(atPath: outRoot + "/" + resourceDir)) ?? []
where name.hasPrefix("\(characterID)-halo-") && name.hasSuffix(".png") && !cellFiles.contains(name) {
    try? FileManager.default.removeItem(atPath: "\(outRoot)/\(resourceDir)/\(name)")
    print("[halo] 옛 칸 지움: \(name)")
}
writePNG(makeHalo(mesh, cell: 0), haloCellOutput(0))
for cell in 1..<haloCellCount { writePNG(makeHaloCell(mesh, cell: cell), haloCellOutput(cell)) }
print("[halo] 정면 512² + 각도 칸 \(haloCellCount - 1)장(\(haloYawStep)° 간격 · \(haloCellSize)²)")

let heightSize = 192
let heights = heightMap(mesh, camera: portraitCamera(mesh, fill: 0.84), size: heightSize)
for e in expressions {
    let portrait = makePortrait(loadImage("\(resourceDir)/aing-\(e).png"), label: e, heights: heights, heightSize: heightSize)
    let mac = "\(resourceDir)/\(characterID)-\(e).png"
    writePNG(portrait, mac)
    let phone = "\(outRoot)/\(phonePortraitDir)/\(characterID)-\(e).png"
    try? FileManager.default.createDirectory(atPath: "\(outRoot)/\(phonePortraitDir)", withIntermediateDirectories: true)
    try? FileManager.default.removeItem(atPath: phone)
    do { try FileManager.default.copyItem(atPath: "\(outRoot)/\(mac)", toPath: phone) } catch { fail("폰 사본 실패: \(error)") }
}
print(String(format: "[done] 밝기 맵 1 · 후광 %d · 초상 %d장 — %.1f초", haloCellCount, expressions.count * 2, Date().timeIntervalSince(started)))
