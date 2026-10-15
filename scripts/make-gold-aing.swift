#!/usr/bin/env swift
// 황금 아잉이(aing_gold) 그림 생성기 (v0.3.54) — 앱이 쓰는 금 피부 맵 · 후광 · 초상 4장(맥 2 + 폰 사본 2)을 다시 굽는다.
//
// 사용법(저장소 루트에서):
//   swift -O scripts/make-gold-aing.swift                    산출물 6개를 저장소에 쓴다(아래 '출력'). 같은 입력이면 같은 픽셀.
//   swift -O scripts/make-gold-aing.swift --verify <폴더> <목표-후광.png> <목표-몸.png>
//                                                            산출물로 SceneKit 렌더(앱과 같은 unlit 합성 + 후광 판)를 그려
//                                                            목표와 나란히 놓은 PNG 와 수치(measure)를 <폴더>에 쓴다. 저장소는 안 건드린다.
//   swift -O scripts/make-gold-aing.swift --fit <목표-몸.png>  목표 그림에서 아래 상수(조명 계수·초상 램프·밝기 분위수·상자 비율)를
//                                                            다시 맞춰 Swift 리터럴로 찍는다. 상수를 바꾸려면 이 출력을 붙여 넣는다.
//   (실측: -O 로 약 10초. 두 번 돌려도 산출물 바이트가 같다. -O 없이도 돌지만 느리다.)
//   목표 그림은 저장소 밖(아키텍트 스크래치 v0354/ref/target-{halo,body}-512.png)에 있다 — 생성은 목표 없이 아래 상수만으로 돈다.
//
// 목표: 사용자가 고른 황금 아잉이(2026-10-15 확정 시안 target-halo-512.png) — 지금 아잉 음영 그대로에 '노란 금과 샴페인 금의
// 중간' 색, 표면 광택 없음, 몸 테두리에서 밝게 번지는 후광. 시안은 PBR(금속 일부 + 환경맵 + 방출 0.75) 렌더였지만 앱의 3D 경로는
// 전부 unlit(.constant)이고 조명이 없다. 그래서 시안의 음영을 **텍스처에 굽는다**: 앱은 아래 '합성' 한 줄만 하면 시안처럼 보인다.
//
// 입력(저장소): Sources/check/Resources/aing.scn (메시·UV·512² 디퓨즈) · aing-neutral.png · aing-negative.png (192² 초상)
// 출력(저장소, 전부 커밋):
//   Sources/check/Resources/aing_gold-skin.png      512×512 불투명. aing.scn 디퓨즈와 **같은 UV 배치**. 모든 텍셀에 '그 자리 피부가
//                                                   금이라면 보일 색'(시점과 무관한 조명 포함)을 담는다 — 눈·볼·입·UV 틈 텍셀까지 채워
//                                                   두었다(감은 눈 커버가 그 자리를 피부로 덮어도 금이 나온다).
//   Sources/check/Resources/aing_gold-halo.png      512×512 알파. 후광만(몸 없음). 정면 실루엣에서 ref halo.swift 층(k = 0.8,
//                                                   몸 높이 256px 기준 σ 32 / 14.4 / 4.8px)으로 만든다 — 몸 밖 픽셀은 시안 후광과 같다(실측).
//   Sources/check/Resources/aing_gold-neutral.png   192×192 RGBA 초상(아잉 초상의 피부만 금으로 + 몸 0.88배 + 후광).
//                                                   눈·볼·입·눈썹은 원래 색 그대로.
//   Sources/check/Resources/aing_gold-negative.png  〃 (시무룩)
//   Sources/CheckMobileShared/Resources/Portraits/aing_gold-{neutral,negative}.png  위 두 장의 **바이트 그대로** 사본(폰·위젯).
//
// ── 앱이 할 일(맥 3D) ─────────────────────────────────────────────────────────────────────────────────────────────
// 1) 합성(로드 때 한 번, 캐시): 디퓨즈 텍셀마다  isGoldSkin(원본 r,g,b) ? skin[텍셀] : 원본[텍셀].
//    원본 = applyUnlitMaterials 가 정규화한 512² 라벤더 디퓨즈(DeviceRGB · premultipliedLast 바이트), skin = aing_gold-skin.png.
//    재질은 그대로 .constant. 법선·조명·환경맵·HDR 아무것도 필요 없다(이 스크립트의 composite(original:skin:) 가 그 정의).
//    isGoldSkin = 시안을 만든 분류(ref render3d.swift isSkin: 색상 215–300° · 채도 0.05–0.75 · lum > 0.10, 아래 함수 그대로 옮길 것).
//    ⚠ SPEC 은 마스크를 SleepEyeTexture.isSkin 으로 적었지만 그 식(루마 > 120 · b > g+18)은 이보다 좁아 605 텍셀이 라벤더로 남는다
//      — 정수리 하이라이트(연보라 얼룩, 앱 카메라는 위에서 내려다봐 바로 보인다)와 날개 이음매 그늘(보라 줄). isSkin ⊂ isGoldSkin
//      (이 텍스처에서 isSkin 인데 isGoldSkin 아닌 텍셀 0개). SleepEyeTexture.isSkin 은 감은 눈 파이프라인용이니 건드리지 말고
//      합성에만 isGoldSkin 을 쓴다. --verify 가 두 마스크를 다 그려 수치·그림으로 보여 준다(gold-aing-mask.png).
//    감은 눈: 원본 라벤더로 SleepEyeTexture.closedEyesImage 를 먼저 굽고, 그 결과에 같은 합성을 한다(커버가 라벤더 피부라 금이 된다).
//    ⚠ 투명 창: SceneKit 은 반투명 픽셀을 '선형 공간 프리멀티'로 sRGB 에 적는다(실측 α 27/255 → (92,80,43,27)). 후광처럼 넓은
//      반투명은 합성기가 그 값을 sRGB 프리멀티로 읽으면 시안보다 훨씬 밝고 넓게 보일 수 있다 — 실제 오버레이 창을 밝은·어두운 바탕
//      위에서 캡처해 확인할 것(이 스크립트의 --verify 는 배경을 씬 안에 깔아 그 문제를 피해서 잰다).
// 2) 후광 판(정면 시안과 같은 크기·자리):
//    SCNPlane 가로 = 세로 = 2.0 × H  (H = aing.scn 바운딩박스 높이 = 1.695736 → 3.391472 모델 단위)
//    중심 = 바운딩박스 중심 (−0.001055, 0.001083, −0.000753) — 사실상 원점. 캐릭터 노드와 같은 좌표계(facing 아래)에 단다.
//    SCNBillboardConstraint · 재질 .constant · diffuse = aing_gold-halo.png · blendMode .alpha · isDoubleSided
//    writesToDepthBuffer = false · readsFromDepthBuffer = false · 노드 renderingOrder = −1 (몸보다 먼저 그려 몸이 덮는다).
//    근거: 시안 카메라(FOV 30, 거리 = H/2/tan15° × 2.0)에서 512px 프레임은 몸 중심 깊이에서 정확히 2.0H 를 덮고, 후광 PNG 의 중심은
//    바운딩박스 중심의 투영이다. --verify 가 이 판을 실제로 그려 시안과 맞댄다.
//
// ── 어떻게 굽나 ───────────────────────────────────────────────────────────────────────────────────────────────────
// 피부 맵: 메시 삼각형을 UV 공간(512²)에 래스터해 텍셀마다 '부드러운 법선'(ref render3d.swift smoothed() 와 같은 이웃 확산 40회,
//   이웃 순서만 정렬해 결정적으로)과 원본 라벤더 밝기(lum)를 얻고, 조명 함수 f(법선, lum) 로 금색을 정한다. f 는 시안 카메라 기준
//   법선(x 오른쪽 · y 위 · z 카메라 쪽)의 2차 단항식(10개) × (lum − 0.75) 의 2차식(3개) = 채널당 30계수의 선형식이고, 시안 몸 픽셀
//   46,076개(정면 G-버퍼로 법선·UV 를 찾은 피부 픽셀)에 최소제곱으로 맞췄다(--fit; 잔차 RMSE R 1.85 · G 2.12 · B 1.91 / 255).
//   시안 카메라는 render3d.swift 의 ZOOM=2.0 구도다(실루엣이 시안과 149px — 가장자리 AA — 만 다르다; 1.95/2.05 는 2,600px 대).
//   뒤쪽(시안에 안 보이는 면)은 |z| 로 접어 앞면 조명을 거울처럼 쓰고, |z| < 0.25(시안 표본 밖)는 0.25 고리로 밀어 외삽하지 않는다.
//   lum 은 [0.47, 0.90]으로 자른다(위쪽을 0.93 까지 열면 정수리 하이라이트 텍셀이 복숭아빛 흰색으로 튄다 — 실측).
//   어느 텍셀의 원본 밝기를 믿나: 얼굴 장식(눈·볼·입) 둘레 8텍셀 안에서는 밝은 피부만(감은 눈 커버가 그 자리를 밝은 라벤더로 덮는다),
//   그 밖은 (금) 피부 전부. 못 믿는 텍셀의 밝기는 **메시 표면**을 따라 번진 정점 밝기로 채우고, UV 틈은 색을 팽창해 채운다.
// 후광: 시안 카메라로 그린 정면 실루엣 알파에 halo.swift 층을 그대로(색 · 두 번 겹침 포함) 적용하고 몸은 합성하지 않는다.
// 초상: 라벤더 피부를 금으로 바꾼다. 피부색 S(눈·볼 아래는 둘레에서 번져 채움)의 밝기를 '시안 몸 밝기 분위수'로 옮기고 — 원천 분포는
//   시안 측정 상자가 시안 몸에서 덮는 것과 **같은 몸 비율** 자리에서 잰다(targetBoxInBody) — 그 밝기의 '시안 평균색' 램프로 칠한다.
//   픽셀마다 피부 비율 β 를 구해 out = P + β·(금 − S) — 볼터치처럼 피부와 섞인 픽셀은 섞인 비율만큼만 바뀐다(볼 테두리에 단단한
//   분홍 얼룩이 남지 않는다). 그 뒤 몸을 0.88배로 줄이고 같은 후광을 깐다: 흐림은 몸 높이에 비례(σ k = 0.8 × 몸높이/256),
//   불투명도는 시안 그대로(0.8). 후광 꼬리만 프레임 가장자리 10px 안에서 0 으로 접고, 테두리 2px 알파 ≤ 0.04 를 스스로 검사한다.
//   측정 정의는 ref measure.swift 와 같다(가운데 30–70% 상자, 알파 ≥ 250, r>g>b, (r−b)/r > 0.2): 평균 RGB ±8, lum p10/p50/p90 ±12.
//   실측(2026-10-15): neutral mean 236 198 104 · lum 176/211/233, negative 238 203 107 · 177/213/233 (시안 240 203 103 · 166/211/235).
//   측정 상자는 프레임 비율이라 초상(몸이 프레임의 70%)에선 몸 가운데 띠만, 시안(50%)에선 몸 거의 전부를 잰다 — 그래서 p10 이 +10
//   남짓 높게 나오고, 평균이 조금 낮은 건 초상의 눈이 상대적으로 커서(어두운 눈 픽셀 7.6% 대 시안 2.4%)다.
//
// 이 스크립트는 앱 모듈을 링크하지 않는다. isSkin 식(SleepEyeTexture.isSkin — --fit 표본 거르기와 비교용)과 디퓨즈 정규화
// (512 · DeviceRGB · premultipliedLast)를 여기 한 번 더 적는다 — 앱 쪽이 바뀌면 여기도 같이 바꿔야 한다.

import AppKit
import CoreImage
import SceneKit
import simd

// MARK: - 상수

let resourceDir = "Sources/check/Resources"
let phonePortraitDir = "Sources/CheckMobileShared/Resources/Portraits"
let modelPath = "\(resourceDir)/aing.scn"
let skinOutput = "\(resourceDir)/aing_gold-skin.png"
let haloOutput = "\(resourceDir)/aing_gold-halo.png"
let expressions = ["neutral", "negative"]

let skinSize = 512
let haloSize = 512
let frontFOV: Float = 30          // 시안 카메라(ref render3d.swift): 세로 시야 30°
let frontZoom: Float = 2.0        // 거리 = H/2/tan15° × 2.0 → 몸 높이가 프레임의 절반(512px 중 256px). 시안 실루엣과 149px 차(가장자리 AA)
let frontRaise: Float = 0.05      // 카메라를 몸 중심보다 0.05H 위에 두고 중심을 본다
let normalIterations = 40
let haloK = 0.8                   // halo.swift 의 scale(256px 몸 기준)
let haloBodyPixels = 256.0
let portraitBodyScale = 0.88
let portraitFadePixels = 10.0
let portraitBorderAlphaLimit = 0.04
let nzFloor = 0.25
let featureRadius = 8           // 눈·볼·입 둘레(텍셀): 앱 감은 눈 커버(닫힘 7 + 팽창 4)를 덮는 폭
let lumLow = 0.47, lumHigh = 0.90, lumCenter = 0.75

// --fit 으로 맞춘 값(목표 target-body-512.png). 순서: 단항식 nx^i ny^j |nz|^k (차수 0…2, i 바깥 · j 안쪽) × (lum − 0.75)^0…2.
let lightingCoefficients: [[Double]] = [
    [178.591, 7.89349, 40.4691, 25.0171, 61.5682, -432.838, 13.7019, -45.6141, -194.389, -12.9764, 97.026, 103.362, 52.8428, -96.4946, 433.456, -12.2207, -106.92, 1211.22, 64.5325, 31.1198, -245.687, 15.9373, 3.53629, -1267.6, -1.23078, 98.8747, -654.813, 61.2248, 73.2679, -147.3],
    [154.279, 89.683, -187.022, 31.801, 171.632, 27.9254, 22.4725, 89.5522, -174.438, -26.6449, -57.9969, 329.447, 54.9518, -79.3672, -287.07, 21.2984, -311.439, -946.337, 52.5428, 57.8302, -4.01359, 5.98495, 178.279, -228.279, 2.35807, 179.381, 108.477, 46.7926, 111.22, 104.062],
    [88.8012, 115.925, 506.358, 2.70131, 256.438, 208.896, 11.7203, 42.5499, 198.834, -12.682, -26.1144, -26.8592, 36.064, -66.8034, 105.087, 19.5644, -39.3181, 76.2232, 31.8744, 85.8087, 177.404, -2.20951, 11.0359, -305.3, -4.12098, 39.5102, -191.502, 20.8692, 96.9204, 223.867],
]
// 시안 몸(측정 상자) 밝기 → 평균색 램프 (lum, r, g, b) 와 밝기 분위수(0%, 5%, …, 100%).
let targetRamp: [(Double, Double, Double, Double)] = [(163.8, 209.5, 158.0, 73.1), (172.3, 219.9, 166.4, 77.6), (179.9, 228.9, 174.0, 81.8), (187.7, 237.7, 182.0, 86.2), (195.8, 246.2, 190.5, 91.0), (204.4, 253.4, 200.3, 97.1), (212.2, 254.9, 211.4, 104.8), (220.1, 255.0, 223.0, 114.2), (228.1, 255.0, 234.8, 122.9), (235.9, 255.0, 246.0, 133.8), (241.0, 255.0, 252.9, 143.6)]
let targetLumQuantiles: [Double] = [140.4, 163.4, 169.4, 174.8, 179.7, 184.8, 190.2, 196.2, 202.6, 207.9, 211.8, 215.7, 218.7, 221.7, 224.6, 227.6, 230.5, 233.2, 236.0, 239.0, 248.4]
// 시안 측정 상자(프레임 30–70%)가 시안 몸 바운딩박스(알파 > 0.5)에서 차지하는 비율 (x0, x1, y0, y1).
let targetBoxInBody: (Double, Double, Double, Double) = (0.1419, 0.8512, 0.1012, 0.8988)

// MARK: - 공통

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(("make-gold-aing: " + message + "\n").data(using: .utf8)!)
    exit(1)
}

func loadImage(_ path: String) -> CGImage {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fail("그림을 못 읽었다: \(path)") }
    return image
}

/// RGBA8 premultipliedLast 바이트(원점 좌상단). 앱의 SleepEyeTexture 와 같은 DeviceRGB 로 읽는다.
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

func writePNG(_ image: CGImage, _ path: String) {
    guard let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil) else {
        fail("쓸 수 없다: \(path)")
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fail("PNG 저장 실패: \(path)") }
}

@inline(__always) func luma(_ r: Int, _ g: Int, _ b: Int) -> Int { (r * 299 + g * 587 + b * 114) / 1000 }
/// 앱 `SleepEyeTexture.isSkin` 과 같은 식(CheckCharacter3DView.swift). 감은 눈 파이프라인의 피부 — 금 합성에는 좁다(머리말 ⚠).
@inline(__always) func isSkin(_ r: Int, _ g: Int, _ b: Int) -> Bool { b >= r && r > g && b > g + 18 && luma(r, g, b) > 120 }
/// 금 합성 마스크 = 시안을 만든 피부 분류(ref render3d.swift isSkin). 원본 텍스처는 불투명이라 프리멀티 해제가 필요 없다.
@inline(__always) func isGoldSkin(_ r: Int, _ g: Int, _ b: Int) -> Bool {
    let (hue, sat, l) = hueSatLum(Double(r), Double(g), Double(b))
    return hue >= 215 && hue <= 300 && sat > 0.05 && sat < 0.75 && l > 0.10
}

/// 앱이 할 합성: 원본이 (금) 피부면 금 피부 맵, 아니면 원본 그대로. `mask` 는 비교용(기본 = isGoldSkin).
func composite(original: [UInt8], skin: [UInt8], mask: (Int, Int, Int) -> Bool = isGoldSkin) -> [UInt8] {
    var out = original
    for o in stride(from: 0, to: original.count, by: 4) where mask(Int(original[o]), Int(original[o + 1]), Int(original[o + 2])) {
        out[o] = skin[o]; out[o + 1] = skin[o + 1]; out[o + 2] = skin[o + 2]; out[o + 3] = 255
    }
    return out
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

// MARK: - 메시

struct Mesh {
    var pos: [SIMD3<Float>]
    var uv: [SIMD2<Float>]
    var idx: [Int]
    var normals: [SIMD3<Float>]
    /// 같은 위치(UV 이음매로 갈린) 정점의 대표 번호와, 대표끼리의 이웃(정렬) — 표면 위에서 값을 번질 때 쓴다.
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

/// 앱 `CheckCharacter3DScene.resampled` 와 같은 512 다운스케일(이미 512 면 그대로).
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
    let world = node.simdWorldTransform
    let n = vs.vectorCount
    var pos = [SIMD3<Float>](repeating: .zero, count: n), uv = [SIMD2<Float>](repeating: .zero, count: n)
    vs.data.withUnsafeBytes { raw in
        for i in 0..<n {
            let b = vs.dataOffset + i * vs.dataStride
            let p = SIMD4<Float>(raw.loadUnaligned(fromByteOffset: b, as: Float.self), raw.loadUnaligned(fromByteOffset: b + 4, as: Float.self),
                                 raw.loadUnaligned(fromByteOffset: b + 8, as: Float.self), 1)
            let q = world * p
            pos[i] = SIMD3(q.x, q.y, q.z)
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
    let (normals, key, neighbors) = smoothedNormals(pos: pos, idx: idx)
    return Mesh(pos: pos, uv: uv, idx: idx, normals: normals, key: key, neighbors: neighbors, center: (minB + maxB) / 2,
                minB: minB, maxB: maxB, diffuse: appDiffuse(tex))
}

/// ref render3d.swift `smoothed()` 와 같은 법선: 면 법선 누적(같은 위치 정점 합침) → 이웃 평균 확산 40회.
/// 다른 점은 이웃을 Set 대신 정렬 배열로 돈다는 것뿐(합 순서가 실행마다 같아 산출물이 결정적이다).
func smoothedNormals(pos: [SIMD3<Float>], idx: [Int]) -> ([SIMD3<Float>], [Int], [[Int]]) {
    let n = pos.count
    var key = [Int](repeating: 0, count: n); var map: [SIMD3<Int32>: Int] = [:]
    for i in 0..<n {
        let q = SIMD3<Int32>(Int32((pos[i].x * 1e4).rounded()), Int32((pos[i].y * 1e4).rounded()), Int32((pos[i].z * 1e4).rounded()))
        if let k = map[q] { key[i] = k } else { map[q] = i; key[i] = i }
    }
    var acc = [SIMD3<Float>](repeating: .zero, count: n)
    var nbSets = [Set<Int>](repeating: [], count: n)
    for t in stride(from: 0, to: idx.count, by: 3) {
        let a = idx[t], b = idx[t + 1], c = idx[t + 2]
        let fn = simd_cross(pos[b] - pos[a], pos[c] - pos[a])
        acc[key[a]] += fn; acc[key[b]] += fn; acc[key[c]] += fn
        let ka = key[a], kb = key[b], kc = key[c]
        nbSets[ka].insert(kb); nbSets[ka].insert(kc); nbSets[kb].insert(ka); nbSets[kb].insert(kc); nbSets[kc].insert(ka); nbSets[kc].insert(kb)
    }
    let nb = nbSets.map { $0.sorted() }
    var cur = acc.map { simd_length($0) > 0 ? simd_normalize($0) : $0 }
    for _ in 0..<normalIterations {
        var next = cur
        for i in 0..<n where key[i] == i && !nb[i].isEmpty {
            var s = cur[i]
            for j in nb[i] { s += cur[j] }
            next[i] = simd_normalize(s)
        }
        cur = next
    }
    return ((0..<n).map { cur[key[$0]] }, key, nb)
}

// MARK: - 시안 카메라(정면)

struct FrontCamera {
    let position: SIMD3<Float>, center: SIMD3<Float>, right: SIMD3<Float>, up: SIMD3<Float>, forward: SIMD3<Float>
    let tanHalf: Float
    init(_ mesh: Mesh) {
        let h = mesh.height
        tanHalf = tan(frontFOV / 2 * .pi / 180)
        let dist = h / 2 / tanHalf * frontZoom
        center = mesh.center
        position = SIMD3(center.x, center.y + h * frontRaise, center.z + dist)
        forward = simd_normalize(center - position)
        right = simd_normalize(simd_cross(forward, SIMD3<Float>(0, 1, 0)))
        up = simd_cross(right, forward)
    }
    /// 모델 좌표 법선 → 시안 카메라 좌표(x 오른쪽 · y 위 · z 카메라 쪽).
    func toCamera(_ n: SIMD3<Float>) -> SIMD3<Double> {
        SIMD3(Double(simd_dot(n, right)), Double(simd_dot(n, up)), Double(-simd_dot(n, forward)))
    }
    /// 화면 픽셀 좌표(원점 좌상단) + 깊이.
    func project(_ p: SIMD3<Float>, size: Int) -> SIMD3<Float> {
        let d = p - position
        let x = simd_dot(d, right), y = simd_dot(d, up), z = simd_dot(d, forward)
        return SIMD3((x / z / tanHalf + 1) / 2 * Float(size), (1 - y / z / tanHalf) / 2 * Float(size), z)
    }
    func node() -> SCNNode {
        let node = SCNNode(); node.camera = SCNCamera(); node.camera!.fieldOfView = CGFloat(frontFOV)
        node.simdPosition = position
        node.simdLook(at: center)
        return node
    }
}

// MARK: - 조명 함수

let monomials: [(Int, Int, Int)] = {
    var out = [(Int, Int, Int)]()
    for d in 0...2 { for i in 0...d { for j in 0...(d - i) { out.append((i, j, d - i - j)) } } }
    return out
}()

func ipow(_ x: Double, _ e: Int) -> Double { e == 0 ? 1 : (e == 1 ? x : x * x) }

/// 시안 카메라 좌표 법선 + 원본 lum → 기저 30개. 뒤쪽은 |z| 로 접고, |z| < nzFloor 는 그 고리로 민다(표본 밖 외삽 금지).
func lightingBasis(_ n: SIMD3<Double>, _ lum: Double) -> [Double] {
    var nx = n.x, ny = n.y, nz = abs(n.z)
    if nz < nzFloor {
        let s = sqrt(1 - nzFloor * nzFloor) / max(1e-9, sqrt(nx * nx + ny * ny))
        nx *= s; ny *= s; nz = nzFloor
    }
    let t = min(max(lum, lumLow), lumHigh) - lumCenter
    var out = [Double](); out.reserveCapacity(monomials.count * 3)
    for m in monomials {
        let v = ipow(nx, m.0) * ipow(ny, m.1) * ipow(nz, m.2)
        out.append(v); out.append(v * t); out.append(v * t * t)
    }
    return out
}

func shade(_ n: SIMD3<Double>, _ lum: Double, _ coefficients: [[Double]]) -> SIMD3<Double> {
    let b = lightingBasis(n, lum)
    var c = SIMD3<Double>(0, 0, 0)
    for k in 0..<b.count { c.x += coefficients[0][k] * b[k]; c.y += coefficients[1][k] * b[k]; c.z += coefficients[2][k] * b[k] }
    return simd_clamp(c, SIMD3(repeating: 0), SIMD3(repeating: 255))
}

// MARK: - 피부 맵 굽기

/// 4-이웃 평균으로 모르는 칸을 바깥에서 안으로 채운 뒤(파도), 채운 칸만 몇 번 더 고르게 편다.
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

/// 정사각 팽창(반경 r, 체비쇼프 거리) — 가로 · 세로 두 번의 1차원 최대값.
func dilate(_ mask: [Bool], width w: Int, height h: Int, radius r: Int) -> [Bool] {
    var horizontal = [Bool](repeating: false, count: w * h)
    for y in 0..<h { for x in 0..<w where mask[y * w + x] { for xx in max(0, x - r)...min(w - 1, x + r) { horizontal[y * w + xx] = true } } }
    var out = [Bool](repeating: false, count: w * h)
    for y in 0..<h { for x in 0..<w where horizontal[y * w + x] { for yy in max(0, y - r)...min(h - 1, y + r) { out[yy * w + x] = true } } }
    return out
}

func bakeSkin(_ mesh: Mesh, _ camera: FrontCamera) -> CGImage {
    let S = skinSize
    let original = bytes(mesh.diffuse)
    guard mesh.diffuse.width == S, mesh.diffuse.height == S else { fail("디퓨즈가 \(S)² 가 아니다") }
    // 0) 어느 텍셀의 밝기를 믿나(knownLum):
    //    · 얼굴 장식(눈·볼·입 — 라벤더가 아닌 텍셀, !isGoldSkin) 둘레 `featureRadius` 텍셀 안에서는 '밝은 피부'만 믿는다
    //      (isSkin 이고 루마 ≥ 그 둘레 피부 루마 중앙값 − 12 — 앱 eyeRegionBrightSkin 과 같은 잣대). 눈두덩·속눈썹 음영 텍셀은
    //      isSkin 을 통과하지만(루마 121–190) 감은 눈 커버가 밝은 라벤더로 덮는 자리라, 그 어두운 밝기로 금을 구우면 감은 눈에
    //      어두운 초승달이 남는다.
    //    · 그 밖에서는 (금) 피부 전부 — 날개 이음매 그늘·정수리 하이라이트처럼 isSkin 이 놓치는 텍셀도 자기 밝기를 쓴다(시안과 같다).
    //    믿지 못하는 텍셀은 **메시 표면**을 따라 번진 정점 밝기로 채운다. UV 공간에서 번지면 눈 조각이 아틀라스 여러 섬에 흩어져
    //    있어 남의 섬 밝기가 섞여 얼룩진다(실측).
    var feature = [Bool](repeating: false, count: S * S)
    var texLuma = [Int](repeating: 0, count: S * S)
    for i in 0..<(S * S) {
        let r = Int(original[i * 4]), g = Int(original[i * 4 + 1]), b = Int(original[i * 4 + 2])
        texLuma[i] = luma(r, g, b)
        feature[i] = !isGoldSkin(r, g, b)
    }
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
    let nv = mesh.pos.count
    var vSum = [Double](repeating: 0, count: nv), vCount = [Double](repeating: 0, count: nv)
    for i in 0..<nv {
        let tx = min(max(Int(mesh.uv[i].x * Float(S)), 0), S - 1), ty = min(max(Int(mesh.uv[i].y * Float(S)), 0), S - 1)
        let o = (ty * S + tx) * 4
        if knownLum[ty * S + tx] {
            vSum[mesh.key[i]] += (0.299 * Double(original[o]) + 0.587 * Double(original[o + 1]) + 0.114 * Double(original[o + 2])) / 255
            vCount[mesh.key[i]] += 1
        }
    }
    let reps = (0..<nv).filter { mesh.key[$0] == $0 }
    let vKnown = (0..<nv).map { vCount[$0] > 0 }
    var vLum = (0..<nv).map { vCount[$0] > 0 ? vSum[$0] / vCount[$0] : 0 }
    var vHave = vKnown
    var growing = true
    while growing {
        growing = false
        var next = vLum, nextHave = vHave
        for i in reps where !vHave[i] {
            var s = 0.0, c = 0.0
            for j in mesh.neighbors[i] where vHave[j] { s += vLum[j]; c += 1 }
            if c > 0 { next[i] = s / c; nextHave[i] = true; growing = true }
        }
        vLum = next; vHave = nextHave
    }
    for _ in 0..<60 {
        var next = vLum
        for i in reps where !vKnown[i] && !mesh.neighbors[i].isEmpty {
            next[i] = mesh.neighbors[i].reduce(0) { $0 + vLum[$1] } / Double(mesh.neighbors[i].count)
        }
        vLum = next
    }
    // 1) 텍셀 법선·표면 lum: UV 공간 래스터(텍셀 중심), 겹치면 합.
    var normalSum = [SIMD3<Float>](repeating: .zero, count: S * S)
    var surfaceLum = [Double](repeating: 0, count: S * S), surfaceWeight = [Double](repeating: 0, count: S * S)
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
            normalSum[y * S + x] += mesh.normals[i0] * w0 + mesh.normals[i1] * w1 + mesh.normals[i2] * w2
            surfaceLum[y * S + x] += vLum[mesh.key[i0]] * Double(w0) + vLum[mesh.key[i1]] * Double(w1) + vLum[mesh.key[i2]] * Double(w2)
            surfaceWeight[y * S + x] += 1
        } }
    }
    // 2) 텍셀 lum: 믿는 텍셀은 원본 밝기, 그 밖은 메시 표면으로 번진 정점 밝기의 보간.
    var lum = [Double](repeating: 0, count: S * S)
    for i in 0..<(S * S) {
        if knownLum[i] {
            lum[i] = (0.299 * Double(original[i * 4]) + 0.587 * Double(original[i * 4 + 1]) + 0.114 * Double(original[i * 4 + 2])) / 255
        } else if surfaceWeight[i] > 0 { lum[i] = surfaceLum[i] / surfaceWeight[i] }
    }
    print("[skin] 얼굴 장식 둘레 밝은 피부 잣대 루마 ≥ \(brightCut), 원본 밝기를 믿은 텍셀 \(knownLum.filter { $0 }.count)/\(S * S)")
    // 3) 덮인 텍셀을 칠하고, UV 틈은 색을 팽창해 채운다.
    var color = [SIMD3<Double>](repeating: .zero, count: S * S), filled = [Bool](repeating: false, count: S * S)
    var covered = 0
    for i in 0..<(S * S) where simd_length(normalSum[i]) > 1e-8 {
        color[i] = shade(camera.toCamera(simd_normalize(normalSum[i])), lum[i], lightingCoefficients); filled[i] = true; covered += 1
    }
    var pending = true
    while pending {
        pending = false
        var next = color, nextFilled = filled
        for y in 0..<S { for x in 0..<S where !filled[y * S + x] {
            var s = SIMD3<Double>(0, 0, 0), c = 0.0
            for dy in -1...1 { for dx in -1...1 where dx != 0 || dy != 0 {
                let xx = x + dx, yy = y + dy
                if xx < 0 || yy < 0 || xx >= S || yy >= S { continue }
                if filled[yy * S + xx] { s += color[yy * S + xx]; c += 1 }
            } }
            if c > 0 { next[y * S + x] = s / c; nextFilled[y * S + x] = true; pending = true }
        } }
        color = next; filled = nextFilled
    }
    var px = [UInt8](repeating: 255, count: S * S * 4)
    for i in 0..<(S * S) {
        px[i * 4] = UInt8(color[i].x.rounded()); px[i * 4 + 1] = UInt8(color[i].y.rounded()); px[i * 4 + 2] = UInt8(color[i].z.rounded())
    }
    print("[skin] 메시가 덮은 텍셀 \(covered)/\(S * S), 나머지는 팽창으로 채움")
    return makeImage(px, S, S)
}

// MARK: - 렌더(SceneKit)

let ciContext = CIContext(options: [.useSoftwareRenderer: true])

/// ref halo.swift 의 층 쌓기 그대로(몸은 합성하지 않는다). halo.swift 는 k 하나로 흐림 반경과 불투명도를 함께 키우는데,
/// 여기서는 둘을 가른다: 흐림은 몸 크기에 비례(`sigmaK`), 불투명도는 시안 그대로(`alphaK` = 0.8). 그래야 192px 초상의 후광이
/// 시안과 같은 진하기로 보인다(k 를 같이 줄이면 바깥 층 불투명도가 0.68 → 0.36 으로 떨어져 흐릿해진다).
func haloImage(silhouette: CGImage, sigmaK: Double, alphaK: Double = haloK) -> CGImage {
    let input = CIImage(cgImage: silhouette)
    let ext = input.extent
    func layer(_ r: Double, _ g: Double, _ b: Double, _ alpha: Double, _ sigma: Double) -> CIImage {
        input.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0, y: 0, z: 0, w: r), "inputGVector": CIVector(x: 0, y: 0, z: 0, w: g),
            "inputBVector": CIVector(x: 0, y: 0, z: 0, w: b), "inputAVector": CIVector(x: 0, y: 0, z: 0, w: alpha),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0)])
            .clampedToExtent().applyingGaussianBlur(sigma: sigma).cropped(to: ext)
    }
    let wide = layer(1.00, 0.76, 0.22, min(1, 0.85 * alphaK), 40 * sigmaK)
    let mid = layer(1.00, 0.84, 0.38, min(1, 1.00 * alphaK), 18 * sigmaK)
    let inner = layer(1.00, 0.97, 0.80, min(1, 1.00 * alphaK), 6 * sigmaK)
    let halo = inner.composited(over: inner.composited(over: mid.composited(over: mid.composited(over: wide))))
    return ciContext.createCGImage(halo, from: ext, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)!
}

func over(_ top: CGImage, _ bottom: CGImage) -> CGImage {
    let out = CIImage(cgImage: top).composited(over: CIImage(cgImage: bottom))
    return ciContext.createCGImage(out, from: CIImage(cgImage: bottom).extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)!
}

/// aing.scn 을 unlit + 주어진 디퓨즈로 그린다. halo 가 있으면 헤더에 적은 판을 단다. view: 시안 정면 · 앱 구도 · 궤도.
/// background nil = 투명. 반투명 픽셀은 SceneKit 이 **선형 공간에서 프리멀티플라이**한 값을 sRGB 로 적어 돌려주므로(실측:
/// 후광 α 27/255 자리가 (92,80,43,27) — 보통 sRGB 프리멀티 해석이면 R>α 라 깨진다) 후광을 볼 때는 배경을 씬 안에 깐다.
enum View { case front, app, orbit(yaw: Float, pitch: Float) }

func renderModel(diffuse: CGImage, halo: CGImage?, mesh: Mesh, size: CGSize, view: View, background: NSColor? = nil) -> CGImage {
    guard let scene = try? SCNScene(url: URL(fileURLWithPath: modelPath), options: nil) else { fail("모델을 못 읽었다") }
    scene.background.contents = background ?? NSColor.clear
    scene.rootNode.enumerateHierarchy { node, _ in
        node.geometry?.materials.forEach { m in m.lightingModel = .constant; m.diffuse.contents = diffuse }
    }
    if let halo {
        let plane = SCNPlane(width: CGFloat(2 * mesh.height), height: CGFloat(2 * mesh.height))
        let m = SCNMaterial()
        m.lightingModel = .constant
        m.diffuse.contents = halo
        m.blendMode = .alpha
        m.isDoubleSided = true
        m.writesToDepthBuffer = false
        m.readsFromDepthBuffer = false
        plane.materials = [m]
        let node = SCNNode(geometry: plane)
        node.simdPosition = mesh.center
        node.renderingOrder = -1
        node.constraints = [SCNBillboardConstraint()]
        scene.rootNode.addChildNode(node)
    }
    var cameraNode = FrontCamera(mesh).node()
    switch view {
    case .front: break
    case .app:
        // 앱 CheckCharacter3DScene.addFramingCamera 와 같은 구도(FOV 40, 위에서 내려다봄).
        let extent = max(mesh.maxB.x - mesh.minB.x, mesh.maxB.y - mesh.minB.y)
        let distance = extent / (2 * tan(20 * Float.pi / 180)) * 1.4
        cameraNode = SCNNode(); cameraNode.camera = SCNCamera(); cameraNode.camera!.fieldOfView = 40
        cameraNode.camera!.zNear = 0.01; cameraNode.camera!.zFar = 1_000
        cameraNode.simdPosition = SIMD3(mesh.center.x, mesh.center.y + extent * 0.55, mesh.maxB.z + distance)
        cameraNode.simdLook(at: SIMD3(mesh.center.x, mesh.center.y - extent * 0.16, mesh.center.z))
    case let .orbit(yaw, pitch):
        let d = mesh.height / 2 / tan(frontFOV / 2 * .pi / 180) * 1.5
        cameraNode.simdPosition = mesh.center + d * SIMD3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
        cameraNode.simdLook(at: mesh.center)
    }
    scene.rootNode.addChildNode(cameraNode)
    let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
    renderer.scene = scene; renderer.pointOfView = cameraNode; renderer.autoenablesDefaultLighting = false
    let shot = renderer.snapshot(atTime: 0, with: size, antialiasingMode: .multisampling4X)
    guard let tiff = shot.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let cg = rep.cgImage else { fail("렌더 실패") }
    return cg
}

// MARK: - 측정(ref measure.swift 와 같은 정의)

struct Stats: CustomStringConvertible {
    var mean: SIMD3<Double>; var p10: Int; var p50: Int; var p90: Int; var n: Int
    var description: String { "mean \(Int(mean.x)) \(Int(mean.y)) \(Int(mean.z))  lum p10/p50/p90 \(p10) \(p50) \(p90)  n \(n)" }
}

func bodyPixels(_ image: CGImage) -> [(SIMD3<Double>, Double)] {
    let w = image.width, h = image.height, px = bytes(image, space: CGColorSpace(name: CGColorSpace.sRGB)!)
    var out = [(SIMD3<Double>, Double)]()
    for y in (h * 3 / 10)..<(h * 7 / 10) { for x in (w * 3 / 10)..<(w * 7 / 10) {
        let i = (y * w + x) * 4; if px[i + 3] < 250 { continue }
        let r = Double(px[i]), g = Double(px[i + 1]), b = Double(px[i + 2])
        guard r > g, g > b, (r - b) / r > 0.2 else { continue }
        out.append((SIMD3(r, g, b), 0.299 * r + 0.587 * g + 0.114 * b))
    } }
    return out
}

func measure(_ image: CGImage) -> Stats {
    let pixels = bodyPixels(image)
    guard !pixels.isEmpty else { return Stats(mean: .zero, p10: 0, p50: 0, p90: 0, n: 0) }
    let mean = pixels.reduce(SIMD3<Double>(0, 0, 0)) { $0 + $1.0 } / Double(pixels.count)
    let lums = pixels.map(\.1).sorted()
    func q(_ f: Double) -> Int { Int(lums[Int(Double(lums.count - 1) * f)]) }
    return Stats(mean: SIMD3(mean.x.rounded(.towardZero), mean.y.rounded(.towardZero), mean.z.rounded(.towardZero)),
                 p10: q(0.1), p50: q(0.5), p90: q(0.9), n: pixels.count)
}

// MARK: - 초상

func rampColor(_ lum: Double) -> SIMD3<Double> {
    let r = targetRamp
    if lum <= r[0].0 { return SIMD3(r[0].1, r[0].2, r[0].3) }
    for i in 1..<r.count where lum <= r[i].0 {
        let a = r[i - 1], b = r[i], f = (lum - a.0) / (b.0 - a.0)
        return SIMD3(a.1 + (b.1 - a.1) * f, a.2 + (b.2 - a.2) * f, a.3 + (b.3 - a.3) * f)
    }
    let l = r[r.count - 1]
    return SIMD3(l.1, l.2, l.3)
}

func targetQuantile(_ p: Double) -> Double {
    let q = targetLumQuantiles, f = min(max(p, 0), 1) * Double(q.count - 1)
    let i = min(q.count - 2, Int(f))
    return q[i] + (q[i + 1] - q[i]) * (f - Double(i))
}

func makePortrait(_ source: CGImage, label: String) -> CGImage {
    let w = source.width, h = source.height
    guard w == 192, h == 192 else { fail("초상이 192² 가 아니다: \(label)") }
    let px = bytes(source, space: CGColorSpace(name: CGColorSpace.sRGB)!)
    let n = w * h
    var P = [SIMD3<Double>](repeating: .zero, count: n), A = [Double](repeating: 0, count: n)
    for i in 0..<n {
        let a = Double(px[i * 4 + 3]) / 255; A[i] = a
        if a > 0 { P[i] = SIMD3(Double(px[i * 4]), Double(px[i * 4 + 1]), Double(px[i * 4 + 2])) / a }
    }
    // 피부 핵심(확실한 라벤더)과 볼터치 대표색.
    var core = [Bool](repeating: false, count: n)
    var blushSum = SIMD3<Double>(0, 0, 0), blushCount = 0.0
    for i in 0..<n where A[i] >= 0.98 {
        let (hue, sat, l) = hueSatLum(P[i].x, P[i].y, P[i].z)
        // 눈썹·눈꺼풀 선(시무룩 초상의 진보라, 색상 270° 안팎 · 채도 0.4–0.6 · 어두움)은 피부가 아니다 — 가장 어두운 피부
        // (아래쪽 그늘)는 색상 246–262° 라 색상으로 가른다. 이들은 입처럼 원래 색을 지킨다.
        let browOrLid = hue > 265 && sat > 0.33 && l < 0.65
        if hue >= 232, hue <= 292, sat >= 0.05, sat <= 0.65, l > 0.25, !browOrLid { core[i] = true }
        if (hue >= 330 || hue <= 8), sat >= 0.2, sat <= 0.7, l > 0.55 { blushSum += P[i]; blushCount += 1 }
    }
    guard blushCount > 0 else { fail("볼터치를 못 찾았다: \(label)") }
    let K = blushSum / blushCount
    // S: 그 자리 피부색(핵심은 자기 자신, 나머지는 둘레에서 번져 채움).
    var S = P
    for ch in 0..<3 {
        var v = (0..<n).map { P[$0][ch] }
        inpaint(&v, known: core, width: w, height: h, relax: 30)
        for i in 0..<n { S[i][ch] = v[i] }
    }
    // 밝기 옮기기: 시안 측정 상자가 시안 몸에서 덮는 '같은 몸 비율' 자리의 피부 분포 → 시안 분위수.
    // (프레임 비율로 자르면 초상은 몸 가운데 띠만, 시안은 몸 거의 전부를 재서 초상이 아래로 갈수록 탁해진다.)
    var bx0 = w, bx1 = -1, by0 = h, by1 = -1
    for y in 0..<h { for x in 0..<w where A[y * w + x] > 0.5 { bx0 = min(bx0, x); bx1 = max(bx1, x); by0 = min(by0, y); by1 = max(by1, y) } }
    let bw = Double(bx1 - bx0 + 1), bh = Double(by1 - by0 + 1)
    let rx0 = Double(bx0) + targetBoxInBody.0 * bw, rx1 = Double(bx0) + targetBoxInBody.1 * bw
    let ry0 = Double(by0) + targetBoxInBody.2 * bh, ry1 = Double(by0) + targetBoxInBody.3 * bh
    var boxLums = [Double]()
    for y in 0..<h { for x in 0..<w where core[y * w + x] && Double(x) >= rx0 && Double(x) < rx1 && Double(y) >= ry0 && Double(y) < ry1 {
        let s = S[y * w + x]; boxLums.append(0.299 * s.x + 0.587 * s.y + 0.114 * s.z)
    } }
    boxLums.sort()
    func sourceRank(_ l: Double) -> Double {
        var lo = 0, hi = boxLums.count
        while lo < hi { let m = (lo + hi) / 2; if boxLums[m] < l { lo = m + 1 } else { hi = m } }
        return Double(lo) / Double(max(1, boxLums.count - 1))
    }
    // 칠하기: out = P + β·(금 − S).
    var out = [UInt8](repeating: 0, count: n * 4)
    for i in 0..<n where A[i] > 0 {
        let s = S[i]
        let sl = 0.299 * s.x + 0.587 * s.y + 0.114 * s.z
        let G = rampColor(targetQuantile(sourceRank(sl)))
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
    }
    let recolored = makeImage(out, w, h)
    // 몸을 0.88배로(가운데 기준) 줄여 후광이 프레임 안에서 사라질 자리를 만든다.
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    let sw = Double(w) * portraitBodyScale, sh = Double(h) * portraitBodyScale
    ctx.draw(recolored, in: CGRect(x: (Double(w) - sw) / 2, y: (Double(h) - sh) / 2, width: sw, height: sh))
    let body = ctx.makeImage()!
    let bodyPx = bytes(body, space: CGColorSpace(name: CGColorSpace.sRGB)!)
    var y0 = h, y1 = -1
    for y in 0..<h { for x in 0..<w where bodyPx[(y * w + x) * 4 + 3] > 128 { y0 = min(y0, y); y1 = max(y1, y) } }
    let bodyHeight = Double(y1 - y0 + 1)
    let k = haloK * bodyHeight / haloBodyPixels
    let result = over(body, fadedAtFrame(haloImage(silhouette: body, sigmaK: k)))
    let border = borderAlpha(result)
    print("[portrait] \(label): 볼터치 \(Int(K.x)),\(Int(K.y)),\(Int(K.z)) · 몸 높이 \(Int(bodyHeight))px · 후광 k \(String(format: "%.4f", k)) · 테두리 2px 최대 알파 \(String(format: "%.4f", border))")
    guard border <= portraitBorderAlphaLimit else { fail("\(label) 테두리 알파 \(border) > \(portraitBorderAlphaLimit)") }
    return result
}

/// 후광만 프레임 가장자리 `portraitFadePixels`(10px) 안에서 0 으로 부드럽게 접는다(smoothstep). 192px 에 몸 0.88배면 바깥 층이
/// 테두리에서 알파 0.039 로 한계(0.04)에 붙어 있어, 그 꼬리만 걷는다 — 날개 끝(테두리에서 약 25px)보다 바깥의 옅은 빛만 줄어든다.
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

func borderAlpha(_ image: CGImage) -> Double {
    let w = image.width, h = image.height, px = bytes(image)
    var m = 0
    for y in 0..<h { for x in 0..<w where x < 2 || y < 2 || x >= w - 2 || y >= h - 2 { m = max(m, Int(px[(y * w + x) * 4 + 3])) } }
    return Double(m) / 255
}

// MARK: - 후광(3D 판용)

func makeHalo(_ mesh: Mesh) -> CGImage {
    let silhouette = renderModel(diffuse: mesh.diffuse, halo: nil, mesh: mesh, size: CGSize(width: haloSize, height: haloSize), view: .front)
    let halo = haloImage(silhouette: silhouette, sigmaK: haloK * (Double(haloSize) / 2) / haloBodyPixels)
    let border = borderAlpha(halo)
    print("[halo] 테두리 2px 최대 알파 \(String(format: "%.4f", border))")
    guard border <= portraitBorderAlphaLimit else { fail("후광 테두리 알파 \(border)") }
    return halo
}

// MARK: - --fit

func fit(targetBodyPath: String, mesh: Mesh) {
    let camera = FrontCamera(mesh)
    let target = bytes(loadImage(targetBodyPath), space: CGColorSpace(name: CGColorSpace.sRGB)!)
    let W = haloSize, H = haloSize
    // 정면 G-버퍼(소프트웨어 래스터, 픽셀 중심 표본, 원근 보정).
    let sp = mesh.pos.map { camera.project($0, size: W) }
    var zbuf = [Float](repeating: .infinity, count: W * H)
    var gN = [SIMD3<Float>](repeating: .zero, count: W * H), gUV = [SIMD2<Float>](repeating: .zero, count: W * H)
    for t in stride(from: 0, to: mesh.idx.count, by: 3) {
        let i0 = mesh.idx[t], i1 = mesh.idx[t + 1], i2 = mesh.idx[t + 2]
        let a = sp[i0], b = sp[i1], c = sp[i2]
        let area = (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
        if abs(area) < 1e-12 { continue }
        let x0 = max(0, Int(floor(min(a.x, b.x, c.x)))), x1 = min(W - 1, Int(ceil(max(a.x, b.x, c.x))))
        let y0 = max(0, Int(floor(min(a.y, b.y, c.y)))), y1 = min(H - 1, Int(ceil(max(a.y, b.y, c.y))))
        if x0 > x1 || y0 > y1 { continue }
        for y in y0...y1 { for x in x0...x1 {
            let px = Float(x) + 0.5, py = Float(y) + 0.5
            let w0 = ((b.x - px) * (c.y - py) - (b.y - py) * (c.x - px)) / area
            let w1 = ((c.x - px) * (a.y - py) - (c.y - py) * (a.x - px)) / area
            let w2 = 1 - w0 - w1
            if w0 < 0 || w1 < 0 || w2 < 0 { continue }
            let z = 1 / (w0 / a.z + w1 / b.z + w2 / c.z)
            let o = y * W + x
            if z >= zbuf[o] { continue }
            zbuf[o] = z
            let p0 = w0 / a.z * z, p1 = w1 / b.z * z, p2 = w2 / c.z * z
            gN[o] = simd_normalize(mesh.normals[i0] * p0 + mesh.normals[i1] * p1 + mesh.normals[i2] * p2)
            gUV[o] = mesh.uv[i0] * p0 + mesh.uv[i1] * p1 + mesh.uv[i2] * p2
        } }
    }
    let tex = bytes(mesh.diffuse), TW = mesh.diffuse.width, TH = mesh.diffuse.height
    func texel(_ x: Int, _ y: Int) -> Int { (min(max(y, 0), TH - 1) * TW + min(max(x, 0), TW - 1)) * 4 }
    // 표본: 시안이 불투명하고 4-이웃까지 메시가 덮었으며, 쌍선형 네 텍셀이 모두 피부인 픽셀.
    var rows = [[Double]](), values = [SIMD3<Double>]()
    for y in 1..<(H - 1) { for x in 1..<(W - 1) {
        let o = y * W + x
        guard target[o * 4 + 3] == 255,
              [(0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)].allSatisfy({ zbuf[(y + $0.1) * W + x + $0.0].isFinite }) else { continue }
        let u = gUV[o].x * Float(TW) - 0.5, v = gUV[o].y * Float(TH) - 0.5
        let tx = Int(floor(u)), ty = Int(floor(v)), fx = Double(u - floor(u)), fy = Double(v - floor(v))
        let corners = [texel(tx, ty), texel(tx + 1, ty), texel(tx, ty + 1), texel(tx + 1, ty + 1)]
        guard corners.allSatisfy({ isSkin(Int(tex[$0]), Int(tex[$0 + 1]), Int(tex[$0 + 2])) }) else { continue }
        let wts = [(1 - fx) * (1 - fy), fx * (1 - fy), (1 - fx) * fy, fx * fy]
        var s = SIMD3<Double>(0, 0, 0)
        for (k, q) in corners.enumerated() { s += SIMD3(Double(tex[q]), Double(tex[q + 1]), Double(tex[q + 2])) * wts[k] }
        rows.append(lightingBasis(camera.toCamera(gN[o]), (0.299 * s.x + 0.587 * s.y + 0.114 * s.z) / 255))
        values.append(SIMD3(Double(target[o * 4]), Double(target[o * 4 + 1]), Double(target[o * 4 + 2])))
    } }
    // 능선 최소제곱(정규방정식 + 촐레스키).
    let P = rows[0].count, N = rows.count
    var ata = [Double](repeating: 0, count: P * P), atb = [[Double]](repeating: [Double](repeating: 0, count: P), count: 3)
    for (r, v) in zip(rows, values) {
        for i in 0..<P { for j in i..<P { ata[i * P + j] += r[i] * r[j] }; atb[0][i] += r[i] * v.x; atb[1][i] += r[i] * v.y; atb[2][i] += r[i] * v.z }
    }
    for i in 0..<P { for j in 0..<i { ata[i * P + j] = ata[j * P + i] }; ata[i * P + i] += 1e-7 * Double(N) }
    var L = [Double](repeating: 0, count: P * P)
    for i in 0..<P { for j in 0...i {
        var s = ata[i * P + j]; for k in 0..<j { s -= L[i * P + k] * L[j * P + k] }
        if i == j { L[i * P + i] = sqrt(max(s, 1e-18)) } else { L[i * P + j] = s / L[j * P + j] }
    } }
    func solve(_ b: [Double]) -> [Double] {
        var y = b
        for i in 0..<P { var s = y[i]; for k in 0..<i { s -= L[i * P + k] * y[k] }; y[i] = s / L[i * P + i] }
        for i in stride(from: P - 1, through: 0, by: -1) { var s = y[i]; for k in (i + 1)..<P { s -= L[k * P + i] * y[k] }; y[i] = s / L[i * P + i] }
        return y
    }
    let coefficients = (0..<3).map { solve(atb[$0]) }
    var se = SIMD3<Double>(0, 0, 0)
    for (r, v) in zip(rows, values) {
        var c = SIMD3<Double>(0, 0, 0)
        for k in 0..<P { c.x += coefficients[0][k] * r[k]; c.y += coefficients[1][k] * r[k]; c.z += coefficients[2][k] * r[k] }
        let e = simd_clamp(c, SIMD3(repeating: 0), SIMD3(repeating: 255)) - v; se += e * e
    }
    let rmse = (se / Double(N)).squareRoot()
    print("// 표본 \(N)개, RMSE R \(String(format: "%.2f", rmse.x)) G \(String(format: "%.2f", rmse.y)) B \(String(format: "%.2f", rmse.z))")
    print("let lightingCoefficients: [[Double]] = [")
    for ch in 0..<3 { print("    [" + coefficients[ch].map { String(format: "%.6g", $0) }.joined(separator: ", ") + "],") }
    print("]")
    // 초상 램프·분위수(측정 상자 픽셀). 눈동자(어두운 갈색)도 측정 필터를 통과하므로 피부만 남기려고 lum ≥ 140 으로 자른다.
    let pixels = bodyPixels(loadImage(targetBodyPath)).filter { $0.1 >= 140 }
    let lums = pixels.map(\.1).sorted()
    print("let targetLumQuantiles: [Double] = [" + (0...20).map { String(format: "%.1f", lums[Int(Double(lums.count - 1) * Double($0) / 20)]) }.joined(separator: ", ") + "]")
    var bins = [Int: (SIMD3<Double>, Double, Double)]()
    for (c, l) in pixels { let b = Int(l / 8); let e = bins[b] ?? (.zero, 0, 0); bins[b] = (e.0 + c, e.1 + l, e.2 + 1) }
    let ramp = bins.keys.sorted().compactMap { b -> String? in
        let e = bins[b]!; guard e.2 >= 20 else { return nil }
        let c = e.0 / e.2
        return String(format: "(%.1f, %.1f, %.1f, %.1f)", e.1 / e.2, c.x, c.y, c.z)
    }
    print("let targetRamp: [(Double, Double, Double, Double)] = [" + ramp.joined(separator: ", ") + "]")
    let tpx = bytes(loadImage(targetBodyPath), space: CGColorSpace(name: CGColorSpace.sRGB)!)
    var bx0 = W, bx1 = -1, by0 = H, by1 = -1
    for y in 0..<H { for x in 0..<W where tpx[(y * W + x) * 4 + 3] > 127 { bx0 = min(bx0, x); bx1 = max(bx1, x); by0 = min(by0, y); by1 = max(by1, y) } }
    let bw = Double(bx1 - bx0 + 1), bh = Double(by1 - by0 + 1)
    let box = [(Double(W * 3 / 10) - Double(bx0)) / bw, (Double(W * 7 / 10) - Double(bx0)) / bw, (Double(H * 3 / 10) - Double(by0)) / bh, (Double(H * 7 / 10) - Double(by0)) / bh]
    print("let targetBoxInBody: (Double, Double, Double, Double) = (" + box.map { String(format: "%.4f", $0) }.joined(separator: ", ") + ")")
}

// MARK: - --verify

func label(_ image: CGImage, _ text: String, background: (CGFloat, CGFloat, CGFloat), scale: CGFloat = 1) -> NSImage {
    let pad: CGFloat = 16, labelHeight: CGFloat = 40
    let size = NSSize(width: CGFloat(image.width) * scale + 2 * pad, height: CGFloat(image.height) * scale + 2 * pad + labelHeight)
    let out = NSImage(size: size)
    out.lockFocus()
    NSColor(srgbRed: background.0, green: background.1, blue: background.2, alpha: 1).setFill()
    NSRect(origin: .zero, size: size).fill()
    NSGraphicsContext.current?.imageInterpolation = .high
    NSImage(cgImage: image, size: .zero).draw(in: NSRect(x: pad, y: pad + labelHeight, width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale))
    let dark = background.0 < 0.5
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 20), .foregroundColor: dark ? NSColor.white : NSColor.black]
    let t = NSAttributedString(string: text, attributes: attrs)
    t.draw(at: NSPoint(x: (size.width - t.size().width) / 2, y: pad))
    out.unlockFocus()
    return out
}

func row(_ images: [NSImage], background: (CGFloat, CGFloat, CGFloat)) -> CGImage {
    let w = images.reduce(0) { $0 + $1.size.width }, h = images.map(\.size.height).max()!
    let out = NSImage(size: NSSize(width: w, height: h))
    out.lockFocus()
    NSColor(srgbRed: background.0, green: background.1, blue: background.2, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: w, height: h).fill()
    var x: CGFloat = 0
    for i in images { i.draw(at: NSPoint(x: x, y: h - i.size.height), from: .zero, operation: .sourceOver, fraction: 1); x += i.size.width }
    out.unlockFocus()
    let rep = NSBitmapImageRep(data: out.tiffRepresentation!)!
    return rep.cgImage!
}

/// 둘 다 불투명(α 255)인 픽셀의 평균 |ΔRGB|.
func bodyDiff(_ a: CGImage, _ b: CGImage) -> Double {
    let pa = bytes(a, space: CGColorSpace(name: CGColorSpace.sRGB)!), pb = bytes(b, space: CGColorSpace(name: CGColorSpace.sRGB)!)
    var sum = 0.0, count = 0.0
    for o in stride(from: 0, to: pa.count, by: 4) where pa[o + 3] == 255 && pb[o + 3] == 255 {
        sum += (0..<3).map { abs(Double(pa[o + $0]) - Double(pb[o + $0])) }.reduce(0, +) / 3; count += 1
    }
    return sum / max(1, count)
}

func verify(outDir: String, targetHaloPath: String, targetBodyPath: String, mesh: Mesh) {
    try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
    let skin = loadImage(skinOutput), halo = loadImage(haloOutput)
    let diffuse = makeImage(composite(original: bytes(mesh.diffuse), skin: bytes(skin)), skinSize, skinSize)
    let size = CGSize(width: haloSize, height: haloSize), appSize = CGSize(width: 280, height: 340)
    let targetHalo = loadImage(targetHaloPath), targetBody = loadImage(targetBodyPath)
    // 1) 몸만(투명 배경): measure 와 몸 픽셀 차이.
    let body = renderModel(diffuse: diffuse, halo: nil, mesh: mesh, size: size, view: .front)
    writePNG(body, "\(outDir)/result-body-512.png")
    writePNG(diffuse, "\(outDir)/composite-diffuse-512.png")
    print("[measure] 목표 몸      \(measure(targetBody))")
    print("[measure] 결과 몸      \(measure(body))")
    for e in expressions { print("[measure] 초상 \(e)  \(measure(loadImage("\(resourceDir)/aing_gold-\(e).png")))") }
    print(String(format: "[diff] 몸 픽셀 평균 |ΔRGB| %.2f (둘 다 불투명인 픽셀)", bodyDiff(body, targetBody)))
    // SPEC 글자 그대로의 마스크(SleepEyeTexture.isSkin)와 비교.
    let originalPx = bytes(mesh.diffuse)
    var narrower = 0
    for o in stride(from: 0, to: originalPx.count, by: 4) {
        let r = Int(originalPx[o]), g = Int(originalPx[o + 1]), b = Int(originalPx[o + 2])
        if isGoldSkin(r, g, b) && !isSkin(r, g, b) { narrower += 1 }
    }
    let specDiffuse = makeImage(composite(original: originalPx, skin: bytes(skin), mask: isSkin), skinSize, skinSize)
    let specBody = renderModel(diffuse: specDiffuse, halo: nil, mesh: mesh, size: size, view: .front)
    print(String(format: "[diff] SPEC 마스크(SleepEyeTexture.isSkin)로 합성하면: 몸 |ΔRGB| %.2f · 라벤더로 남는 텍셀 %d개", bodyDiff(specBody, targetBody), narrower))
    let gray = NSColor(srgbRed: 0.5, green: 0.5, blue: 0.5, alpha: 1), cgray = (CGFloat(0.5), CGFloat(0.5), CGFloat(0.5))
    let views: [(String, View)] = [("앱 카메라", .app), ("옆(90°)", .orbit(yaw: 1.57, pitch: 0)), ("뒤", .orbit(yaw: 3.14, pitch: 0)),
                                   ("뒤 왼쪽 아래", .orbit(yaw: -2.2, pitch: -0.4))]
    var rows = [CGImage]()
    for (title, d) in [("SPEC isSkin", specDiffuse), ("isGoldSkin(권장)", diffuse)] {
        rows.append(row(views.map { label(renderModel(diffuse: d, halo: nil, mesh: mesh, size: CGSize(width: 280, height: 300), view: $0.1, background: gray),
                                          "\(title) · \($0.0)", background: cgray) }, background: cgray))
    }
    let mw = rows.map(\.width).max()!, mh = rows.reduce(0) { $0 + $1.height }
    let mctx = CGContext(data: nil, width: mw, height: mh, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    var my = mh
    for r in rows { my -= r.height; mctx.draw(r, in: CGRect(x: 0, y: my, width: r.width, height: r.height)) }
    writePNG(mctx.makeImage()!, "\(outDir)/gold-aing-mask.png")
    // 2) 후광 포함: 밝은·어두운 배경을 씬 안에 깔고 그린 결과 vs 같은 배경 위 목표(CI 선형 합성 — SceneKit 과 같은 공간).
    let targetMask = bytes(targetBody, space: CGColorSpace(name: CGColorSpace.sRGB)!)
    let portraits = expressions.map { loadImage("\(resourceDir)/aing_gold-\($0).png") }
    let original = loadImage("\(resourceDir)/aing-neutral.png")
    for (name, gray) in [("light", 0.95), ("dark", 0.11)] {
        let bg = NSColor(srgbRed: gray, green: gray, blue: gray, alpha: 1)
        let result = renderModel(diffuse: diffuse, halo: halo, mesh: mesh, size: size, view: .front, background: bg)
        let backdrop = CIImage(color: CIColor(red: gray, green: gray, blue: gray, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)!)
            .cropped(to: CGRect(origin: .zero, size: size))
        let target = ciContext.createCGImage(CIImage(cgImage: targetHalo).composited(over: backdrop), from: backdrop.extent,
                                             format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)!
        let pr = bytes(result, space: CGColorSpace(name: CGColorSpace.sRGB)!), pt = bytes(target, space: CGColorSpace(name: CGColorSpace.sRGB)!)
        var sum = 0.0, count = 0.0, peak = 0.0
        for o in stride(from: 0, to: pr.count, by: 4) where targetMask[o + 3] == 0 {
            let e = (0..<3).map { abs(Double(pr[o + $0]) - Double(pt[o + $0])) }.reduce(0, +) / 3
            sum += e; count += 1; peak = max(peak, e)
        }
        print(String(format: "[diff] 후광(%@ 배경, 몸 밖 %d픽셀) 평균 |ΔRGB| %.2f · 최대 %.0f", name, Int(count), sum / count, peak))
        writePNG(result, "\(outDir)/result-halo-\(name).png")
        let app = renderModel(diffuse: diffuse, halo: halo, mesh: mesh, size: appSize, view: .app, background: bg)
        let plain = renderModel(diffuse: mesh.diffuse, halo: nil, mesh: mesh, size: appSize, view: .app, background: bg)
        let cbg = (CGFloat(gray), CGFloat(gray), CGFloat(gray))
        let frame = CGRect(x: 40, y: 56, width: 432, height: 400)   // 몸 + 후광이 다 들어가는 가운데 부분만
        let top = row([label(target.cropping(to: frame)!, "목표(확정 시안)", background: cbg, scale: 0.8),
                       label(result.cropping(to: frame)!, "결과: unlit 합성 + 후광 판", background: cbg, scale: 0.8)], background: cbg)
        let bottom = row([label(app, "앱 카메라 구도", background: cbg),
                          label(plain, "지금 아잉(같은 구도)", background: cbg),
                          label(portraits[0], "초상 neutral", background: cbg),
                          label(portraits[1], "초상 negative", background: cbg),
                          label(original, "지금 아잉 초상", background: cbg)], background: cbg)
        let w = max(top.width, bottom.width), h = top.height + bottom.height
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(srgbRed: cbg.0, green: cbg.1, blue: cbg.2, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.draw(top, in: CGRect(x: (w - top.width) / 2, y: bottom.height, width: top.width, height: top.height))
        ctx.draw(bottom, in: CGRect(x: (w - bottom.width) / 2, y: 0, width: bottom.width, height: bottom.height))
        writePNG(ctx.makeImage()!, "\(outDir)/gold-aing-\(name).png")
    }
    print("[verify] \(outDir) 에 썼다")
}

// MARK: - 실행

let args = Array(CommandLine.arguments.dropFirst())
guard FileManager.default.fileExists(atPath: modelPath) else { fail("저장소 루트에서 실행하라(\(modelPath) 없음)") }
let mesh = loadMesh()

switch args.first {
case "--fit":
    guard args.count == 2 else { fail("사용: --fit <목표-몸.png>") }
    fit(targetBodyPath: args[1], mesh: mesh)
case "--verify":
    guard args.count == 4 else { fail("사용: --verify <폴더> <목표-후광.png> <목표-몸.png>") }
    verify(outDir: args[1], targetHaloPath: args[2], targetBodyPath: args[3], mesh: mesh)
case nil:
    guard lightingCoefficients.allSatisfy({ $0.count == monomials.count * 3 }), !targetRamp.isEmpty, targetLumQuantiles.count == 21 else {
        fail("상수가 비었다 — --fit 출력을 붙여 넣어라")
    }
    let camera = FrontCamera(mesh)
    writePNG(bakeSkin(mesh, camera), skinOutput)
    writePNG(makeHalo(mesh), haloOutput)
    for e in expressions {
        let portrait = makePortrait(loadImage("\(resourceDir)/aing-\(e).png"), label: e)
        let mac = "\(resourceDir)/aing_gold-\(e).png"
        writePNG(portrait, mac)
        let phone = "\(phonePortraitDir)/aing_gold-\(e).png"
        try? FileManager.default.removeItem(atPath: phone)
        do { try FileManager.default.copyItem(atPath: mac, toPath: phone) } catch { fail("폰 사본 실패: \(error)") }
        print("[portrait] \(e): 측정 \(measure(portrait))")
    }
    print("[done] \(skinOutput) · \(haloOutput) · 초상 \(expressions.count * 2)장")
default:
    fail("모르는 인자: \(args)")
}
