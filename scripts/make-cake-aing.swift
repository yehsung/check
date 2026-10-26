#!/usr/bin/env swift
// 케이크 아잉이(aing_cake_strawberry · aing_cake_choco) 그림 생성기 (v0.3.66) — 생일 선물 전용 캐릭터 둘의 초상 8장(맥 4 + 폰 사본 4)을 굽고,
// 앱 3D 마감(맥 CakeAingFinish)이 그대로 옮겨 쓸 **몸 셰이더 소스 · 장식 기하 생성 코드**를 함수로 담는다.
// 사용자가 고른 시안을 그대로 옮겼다(스크래치 v0366-cake): 딸기 = 시안 B '녹아내린 크림'(lane-a/render.swift 의 B · B-*.png),
// 초코 = 시안 D(lane-b/render.swift 의 D · D-*.png · D-decor.scn). 모양 · 색 · 장식 자리는 시안의 숫자 그대로이고 아래 '고친 것' 셋만 다르다.
//
// 사용법(저장소 루트에서):
//   swift -O scripts/make-cake-aing.swift                   산출물 8장을 저장소에 쓴다(아래 '출력'). 같은 입력이면 같은 바이트.
//   swift -O scripts/make-cake-aing.swift --out <폴더>      같은 산출물을 <폴더>/Sources/… 아래에 쓴다(저장소는 안 건드린다 — 결정성 검사용).
//   swift -O scripts/make-cake-aing.swift --preview <폴더>  산출물에 더해 앱 구도 3D 참고 렌더(정면 · 3/4 · 뒤 512² · 눈 확대 · 장식 .scn)를
//                                                           <폴더>에 쓴다 — 저장소 밖에 둔다(앱 CakeAingFinish 를 맞대 보는 기준 그림). 둘은 같이 쓸 수 있다.
//   (실측: -O 로 컴파일 포함 약 7초 · 미리보기까지 약 10초. 오프스크린 SCNRenderer(Metal)만 쓴다 — 화면에 창을 띄우지 않는다.)
//
// 입력(저장소, 읽기만): Sources/check/Resources/aing.scn(메시 · UV · 512² 라벤더 디퓨즈) · aing_rainbow-shade.png(**무지개 생성기 산출** —
//   라벤더 밝기 맵, 케이크도 같은 파일을 쓴다) · aing-neutral.png · aing-negative.png(192² 아잉 초상)
// 출력(저장소, 전부 커밋):
//   Sources/check/Resources/aing_cake_strawberry-neutral.png  192×192 RGBA 초상(아잉 초상의 피부만 딸기 크림 + 3D 장식 얹음, 후광 없음)
//   Sources/check/Resources/aing_cake_strawberry-negative.png 〃 (시무룩)
//   Sources/check/Resources/aing_cake_choco-neutral.png       〃 초코
//   Sources/check/Resources/aing_cake_choco-negative.png      〃
//   Sources/CheckMobileShared/Resources/Portraits/aing_cake_{strawberry,choco}-{neutral,negative}.png  위 네 장의 **바이트 그대로** 사본(폰 · 위젯).
//   ★ 3D 용 새 텍스처는 굽지 않는다: 몸은 무지개가 이미 번들한 aing_rainbow-shade.png 를 같이 쓰고(디퓨즈 합성 · 초코 셰이더 인자),
//     장식 텍스처(딸기 씨 · 꽃받침 · 초 줄무늬의 음영 구운 작은 판 · 빛 번짐 판)는 **코드가 만든다**(아래 StrawberryDecor.pieceNode ·
//     ChocoDecor.glowImage). 그래서 '그릴 수 있다'(맥 drawableCharacterIDs)의 자원 재료는 초상 두 장 + aing_rainbow-shade.png 다.
//
// 고친 것(시안 known_issues):
//  ① 초코 눈 둘레 라벤더 테 — 시안 D 셰이더는 피부 비율 β 를 '볼터치 선 위면 그 비율, 아니면 1 − |P − S|/80' 으로 쟀다. 눈꺼풀(검정에 가까운
//     갈색) · 흰자와 라벤더 피부가 섞인 안티에일리어스 텍셀은 |P − S| 가 커서 β ≈ 0 → 섞인 라벤더가 그대로 남아 어두운 몸 위에 얇은 보라 테가
//     섰고, 흰자는 반대로 β ≈ 0.3 이라 갈색이 묻었다. 고침(`skinFraction` · 셰이더 같은 식): P = (1 − a)·S + a·F 로 보고 F 를 S→P 방향으로
//     RGB 상자 끝까지 민 색이라 두면 a = 그 최소 덮임이다. F 가 검정에 가깝거나(루마 < 0.19…0.25) 흰색에 가까우면(최소 채널 > 0.88…0.95)
//     그 a 를 믿어 β = 1 − a(→ 출력 = (1 − a)·케이크 + a·F — 테 텍셀이 몸색과 섞인다), 아니면(입 안 · 혀 같은 가운데 색) 옛 식 그대로.
//     눈 자체(눈동자 · 흰자 · 속눈썹)는 F = P 라 a = 1 → β = 0 — 원본 그대로다. 3D 셰이더(ChocoBody.fragmentShader)와 초상이 같은 식이다.
//     딸기(시안 B)는 몸 셰이더가 다른 틀(피부 판정 + 볼 번짐)이고 밝은 분홍 위라 테가 안 보여 3D 는 그대로 두고, 초상만 같은 β 를 쓴다.
//     초상의 실루엣 가장자리 띠(`rimRadius` px)는 옛 식 그대로다 — 2D 테두리 빛을 흰 장식으로 알면 초코 테두리에 점선이 선다(`nearRim`).
//     초코 셰이더는 딸기와 같은 얼굴 상자(물체 좌표) 밖을 전부 케이크로 칠한다 — 원본 디퓨즈의 뒤통수 · 몸 아래에 피부 판정을 못 넘는 옅은
//     텍셀이 흩어져 있어 어두운 몸 위에서 분홍 · 보라 티끌이 됐다(시안 D 뒷모습 실측 22화소).
//  ② 초상에서 장식(3D) · 몸(2D) 질감 차 — 장식 층을 출력 화소에서 가우스(σ 0.55px) 초표본으로 읽어 2D 그림의 부드러운 가장자리와 맞추고,
//     장식 밑 몸에 부드러운 접촉 그늘(오른쪽 아래로 0.6 · 1.0px, σ 1.8px, 최대 25%)을 깔아 장식이 몸 위에 '붙어' 보이게 했다. 장식 반투명 화소는
//     SCNRenderer 스냅숏의 '선형 프리멀티를 sRGB 로 부호화한' 값을 바로 풀어(`straightened`) 가장자리 · 빛 번짐이 허옇게 뜨지 않는다.
//  ③ 장식 꼭대기 잘림 — 네 초상(딸기 · 초코 × 두 표정)을 **같은 몸 배율 · 같은 몸 자리**로 세우고(상점 · 선택 창에 나란히 놓여도 몸이 맞는다),
//     그 배율은 네 장 모두 장식(빛 번짐까지) 꼭대기가 위 가장자리에서 `portraitMargin` 이상 떨어지게 정한다(0.88 상한 — 금 · 무지개 초상 틀).
//     2px 테두리 최대 알파가 `borderAlphaLimit` 을 넘으면 멈춘다.
//
// ── 앱이 할 일(맥 3D, CakeAingFinish.swift) — 아래 이름을 그대로 옮긴다 ───────────────────────────────────────────────────────────
// 1) 디퓨즈 합성: 무지개와 같다 — 텍셀마다 isGoldSkin(원본) ? aing_rainbow-shade.png[텍셀] : 원본(`GoldAingFinish.compositeImage(original:skin:)`).
//    감은 눈은 라벤더 원본에서 먼저 굽고 같은 합성을 한다(무지개 `closedEyesImage` 순서). 두 케이크가 같은 합성을 쓴다.
// 2) 몸 셰이더(얼굴 재질 — 큰 CGImage 디퓨즈 재질, lightingModel .constant):
//    · 딸기: `StrawberryBody.shaderModifiers(albedoOnly: false)` — geometry(물체 좌표 varyings) + fragment(표본 디퓨즈의 피부 판정 → 크림 무늬,
//      밝기 = OKLab L 차 dL = L − lReference). 무늬 소스 = `StrawberryBody.pattern`(녹아내린 흰 크림 · 흘러내림 14줄). 셰이더 인자 없음.
//    · 초코: `ChocoBody.shaderModifiers` + 셰이더 인자 `material.setValue(SCNMaterialProperty(contents: <aing_rainbow-shade CGImage>),
//      forKey: ChocoBody.shadeMapKey)` — 그 자리 피부 S 를 읽어 β(①)를 잰다. 무늬 소스 = `ChocoBody.pattern`(가나슈 흘러내림 12줄 · 크림 · 분홍 띠).
//      상수 `chocoSkinYRef` · `chocoBlushSRGB` 는 이 스크립트가 다시 재서 맞댄다(합성 · 디퓨즈가 바뀌면 멈춘다).
//    둘 다 '표본한 디퓨즈'에서 마스크를 읽으므로 깜빡임 · 졸기 · 울트라 교체로 디퓨즈가 바뀌어도 따라온다(무지개와 같은 이유).
// 3) 장식: `StrawberryDecor.make(probe:)` · `ChocoDecor.make(probe:)` → 이름 `cakeDecorNodeName`("check.cakeDecor") 노드 하나. **캐릭터 노드
//    (aing.scn 의 메시 노드 — 변환이 단위라 물체 좌표 = 이 노드 좌표)의 자식**으로 붙인다 → 부유 · 살랑 · 요 회전을 그대로 따른다.
//    probe = 정수리 위 (x, z) 에서 몸 메시로 내리쏜 선분 hitTest(`meshSurfaceProbe(bodyNode)` 그대로). 자리 숫자는 시안 그대로다.
//    · 붙이는 순서: 프레이밍 카메라를 **몸만** 보고 세운 뒤(금 · 무지개 후광을 붙이는 자리와 같은 순서) — 그래야 몸 크기 계산이 장식에 안 흔들린다.
//    · 모든 장식 재질은 .constant(조명 없음). 딸기 장식은 음영을 작은 텍스처에 구워 넣었고(몸 공간 고정 빛 — 몸이 돌면 같이 돈다), 초코 장식은
//      재질 셰이더가 같은 뜻의 고정 빛으로 칠한다. 불꽃만 시선 각 셰이더, 빛 번짐은 SCNBillboardConstraint 판(깊이 안 씀 · renderingOrder 큼).
//    · 얼굴 탐색 · 몸 클릭 hitTest 에서 빼야 한다 — `cakeDecorNodeName` 노드 **아래 전부**(자식 이름은 두 케이크가 다르다: 딸기 check.cake.* 아래
//      berry · calyxN · candle · wick · flame · glow, 초코 cake.strawberry · cake.leaf · cake.cream · cake.candle · cake.wick · cake.flame · cake.glow0).
//      조상에 그 이름이 있는지로 가르거나 카테고리 비트를 후광처럼 준다.
//    · 장식 만들기 비용(실측 -O): 딸기 0.06–0.12초(작은 텍스처 17장을 코드로 굽는다) · 초코 약 0.01초 — 디버그 빌드는 몇 배 느리니 프로세스당
//      한 번 만들어 clone 하라.
// 4) 프레이밍: 장식 꼭대기(물체 좌표 y) — 딸기 불꽃 끝 `strawberryFlameTopY` · 초코 불꽃 끝 `chocoFlameTopY`(빛 번짐 판은 그보다 위까지 닿지만
//    가운데 밖은 알파가 0 에 가깝다). 앱 카메라가 이 높이 + 부유 0.07 까지 안 자르게 잡아야 한다. --preview 의 [frame] 줄이 지금 앱 카메라
//    (몸만 보고 잡은 40°) 화면에서 몸 + 장식(빛 번짐 알파 > 8/255 포함) 위 끝을 프레임 높이 비율로 보여 준다(실측: 딸기 0.044 · 부유 +0.07 이면
//    0.021 — 들어온다 / **초코 0.020 · 부유 +0.07 이면 −0.006 — 위로 잘린다**). 초코는 프레이밍을 넓혀야 한다.
// 5) 초상 · 폰: 초상 파일 이름은 `<id>-<neutral|negative>.png`(금 · 무지개 규약). 폰 `AingCharacterArt.knownIDs` 는 Portraits/ 사본으로 안다.
//
// 이 스크립트는 앱 모듈을 링크하지 않는다. isGoldSkin · 디퓨즈 정규화 · 합성 · 몸 좌표 상수를 여기 한 번 더 적는다 — 앱 쪽이 바뀌면 여기도 같이.

import AppKit
import SceneKit
import simd

// MARK: - 상수

let resourceDir = "Sources/check/Resources"
let phonePortraitDir = "Sources/CheckMobileShared/Resources/Portraits"
let modelPath = "\(resourceDir)/aing.scn"
let shadePath = "\(resourceDir)/aing_rainbow-shade.png"
let expressions = ["neutral", "negative"]
let strawberryID = "aing_cake_strawberry"
let chocoID = "aing_cake_choco"
let cakeDecorNodeName = "check.cakeDecor"

// 셰이더 몸 좌표 상수(무지개 `RainbowAingArt` 와 같은 값 — 메시가 바뀌면 멈춘다).
let bodyTop = 0.848950
let bodyHeight = 1.695736
let lReference = 0.8327
// 초코 셰이더 상수 — 합성 디퓨즈 피부 텍셀 선형 휘도의 중앙값 · 원본 디퓨즈 볼터치 평균(sRGB 0–255). 실행 때 다시 재서 맞댄다.
let chocoSkinYRef = 0.56530
let chocoBlushSRGB = SIMD3<Double>(245.62, 172.26, 200.68)
// 장식 꼭대기(물체 좌표 y) — 불꽃 끝. 실행 때 장식 노드에서 다시 재서 맞댄다(앱 프레이밍이 쓰는 값).
let strawberryFlameTopY = 1.1396
let chocoFlameTopY = 1.1839

let portraitSize = 192
let portraitBodyScale = 0.88      // 금 · 무지개 초상 틀(몸 0.88배) — 장식이 넘치면 그만큼 더 줄인다(네 장 같은 배율)
let portraitMargin = 8.0          // 장식(빛 번짐 알파 > 1/255 까지) 상자와 프레임 가장자리 사이 최소 여백(px)
let borderAlphaLimit = 0.04
let decorSoftSigma = 0.55         // ② 장식 층 가우스 초표본 σ(출력 px)
let contactShadowOffset = SIMD2<Double>(0.6, 1.0)
let contactShadowSigma = 1.8
let contactShadowStrength = 0.25
let mapSize = 768                 // 초상용 3D 지도(몸 무늬 · 장식) 한 변
let rimRadius = 5                 // ① 초상 실루엣 가장자리 띠(px) — 여기는 옛 β(테두리 빛을 흰 장식으로 오인하지 않게)

var outRoot = "."
var previewDir: String?

// MARK: - 공통 도구

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(("make-cake-aing: " + message + "\n").data(using: .utf8)!)
    exit(1)
}

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func loadImage(_ path: String) -> CGImage {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fail("그림을 못 읽었다: \(path)") }
    return image
}

/// RGBA8 premultipliedLast 바이트(원점 좌상단). 기본은 앱 GoldAingFinish 합성과 같은 DeviceRGB.
func bytes(_ image: CGImage, space: CGColorSpace = CGColorSpaceCreateDeviceRGB()) -> [UInt8] {
    let w = image.width, h = image.height
    var px = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    return px
}

func makeImage(_ px: [UInt8], _ w: Int, _ h: Int, space: CGColorSpace = sRGB) -> CGImage {
    var p = px
    let ctx = CGContext(data: &p, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, toPath path: String) {
    try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    guard let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil) else {
        fail("쓸 수 없다: \(path)")
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fail("PNG 저장 실패: \(path)") }
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

/// 앱 `GoldAingFinish.isGoldSkin` 과 같은 식(색상 215–300° · 채도 0.05–0.75 · 루마 > 0.10). 두 몸 셰이더도 같은 판정이다.
@inline(__always) func isGoldSkin(_ r: Int, _ g: Int, _ b: Int) -> Bool {
    let (hue, sat, l) = hueSatLum(Double(r), Double(g), Double(b))
    return hue >= 215 && hue <= 300 && sat > 0.05 && sat < 0.75 && l > 0.10
}

/// 4-이웃 평균으로 모르는 칸을 바깥에서 안으로 채운 뒤(파도), 채운 칸만 몇 번 더 고르게 편다(금 · 무지개 스크립트와 같다).
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

@inline(__always) func smoothstep(_ e0: Double, _ e1: Double, _ x: Double) -> Double {
    let t = min(max((x - e0) / (e1 - e0), 0), 1)
    return t * t * (3 - 2 * t)
}

// MARK: - 색(OKLab · sRGB)

@inline(__always) func srgbToLinear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
@inline(__always) func linearToSrgb(_ v: Double) -> Double { v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1 / 2.4) - 0.055 }
@inline(__always) func lumaLinear(_ c: SIMD3<Double>) -> Double { 0.2126 * c.x + 0.7152 * c.y + 0.0722 * c.z }

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

func srgbBytesToLinear(_ r: Double, _ g: Double, _ b: Double) -> SIMD3<Double> {
    SIMD3(srgbToLinear(r / 255), srgbToLinear(g / 255), srgbToLinear(b / 255))
}

func labOf(_ r: Double, _ g: Double, _ b: Double) -> SIMD3<Double> { linearToOklab(srgbBytesToLinear(r, g, b)) }

func linearToBytes(_ c: SIMD3<Double>) -> (UInt8, UInt8, UInt8) {
    func q(_ v: Double) -> UInt8 { UInt8(max(0, min(255, (linearToSrgb(min(max(v, 0), 1)) * 255).rounded()))) }
    return (q(c.x), q(c.y), q(c.z))
}

func toByte(_ v: Double) -> UInt8 { UInt8(max(0, min(255, (linearToSrgb(min(max(v, 0), 1)) * 255).rounded()))) }

/// 셰이더 글 숫자 — 딸기(시안 B) 쪽은 소수 6자리(`f6`), 초코(시안 D) 쪽은 5자리(`f5`). 시안 글자 그대로다.
func f6(_ v: Double) -> String { String(format: "%.6f", v) }
func f6v(_ v: SIMD3<Double>) -> String { "float3(\(f6(v.x)), \(f6(v.y)), \(f6(v.z)))" }
func f5(_ v: Double) -> String { String(format: "%.5f", v) }
func f5v(_ v: SIMD3<Double>) -> String { String(format: "float3(%.5f, %.5f, %.5f)", v.x, v.y, v.z) }
/// sRGB 16진 → 선형.
func linHex(_ hex: Int) -> SIMD3<Double> {
    SIMD3(srgbToLinear(Double((hex >> 16) & 255) / 255), srgbToLinear(Double((hex >> 8) & 255) / 255), srgbToLinear(Double(hex & 255) / 255))
}
func f5hex(_ hex: Int) -> String { f5v(linHex(hex)) }

// MARK: - 피부 비율 β(초상 · 초코 셰이더 같은 식 — 머리말 ①)

/// sRGB 0–255 의 텍셀 P · 그 자리 피부 S · 볼터치 대표색 K → 피부 비율 β(출력 = P + β·(케이크 − S)).
/// `unmix` = false 면 시안의 옛 식(볼터치 선 위면 그 비율, 아니면 1 − |P − S|/80) 그대로다.
func skinFraction(_ P: SIMD3<Double>, _ S: SIMD3<Double>, _ K: SIMD3<Double>, unmix: Bool) -> Double {
    let d = P - S, ks = K - S
    let a = simd_dot(d, ks) / max(1e-6, simd_length_squared(ks))
    let resid = simd_length(d - min(max(a, 0), 1) * ks)
    if resid <= 20, a > -0.1, a < 1.1 { return 1 - min(max(a, 0), 1) }
    let old = min(max(1 - simd_length(d) / 80, 0), 1)
    guard unmix else { return old }
    // P = (1 − a)·S + a·F, F = S→P 방향 RGB 상자 끝 → a = 채널마다 '그 끝까지 간 비율' 중 가장 큰 것.
    var cover = 0.0
    for c in 0..<3 {
        let v = d[c] < 0 ? d[c] / min(-S[c], -1e-3) : d[c] / max(255 - S[c], 1e-3)
        cover = max(cover, v)
    }
    cover = min(max(cover, 0), 1)
    let F = S + d / max(cover, 1e-3)
    let fy = (0.299 * F.x + 0.587 * F.y + 0.114 * F.z) / 255
    let fm = min(F.x, F.y, F.z) / 255
    let trust = max(1 - smoothstep(0.19, 0.25, fy), smoothstep(0.88, 0.95, fm))
    return old + (1 - cover - old) * trust
}

// MARK: - ① 몸 셰이더 — 딸기(시안 B '녹아내린 크림', lane-a 틀)

/// 몸 전체 연분홍 딸기 크림, 정수리에 흰 크림이 녹아 흘러내린 물결 테두리(앞은 짧게 — 눈을 덮지 않는다). 흘러내림 = 둘레 각마다 캡슐 + 끝 방울
/// (물체 좌표의 표면 거리로 잰 SDF), 캡과 매끈한 합집합(필렛). 밝기는 표본 디퓨즈의 OKLab L 차(dL)로 옮긴다(무지개와 같은 길).
enum StrawberryBody {
    /// 아잉 디퓨즈 실측(피부 텍셀 중앙값 · 볼터치 핵심 평균, sRGB 0–1) — 볼터치 번짐 판정의 두 끝.
    static let lavenderSRGB = SIMD3<Double>(207, 186, 254) / 255
    static let blushSRGB = SIMD3<Double>(245.6, 172.3, 200.7) / 255
    static let blushLinear = SIMD3(srgbToLinear(blushSRGB.x), srgbToLinear(blushSRGB.y), srgbToLinear(blushSRGB.z))
    /// 몸 밝기 옮기기(셰이더의 `ckK` · `ckO` 줄과 같은 식): L = 무늬 L + dL, 그늘(dL < 0)은 분홍 · 보라 쪽으로 살짝 물들이고 채도는 조금 진하게.
    static let shadeTintA = 0.05, shadeTintB = -0.025, chromaSlope = 1.5, chromaFloor = 0.85, chromaCeil = 1.2
    static let creamLab = labOf(254, 251, 247)        // 생크림(살짝 따뜻한 흰색)
    static let pinkCreamLab = labOf(252, 196, 212)    // 몸: 딸기 크림 연분홍
    /// (각도°, 길이, 반지름) — 앞(0°)은 짧게, 눈 기둥(±26°) 근처는 비운다.
    static let drips: [(Double, Double, Double)] = [
        (0, 0.030, 0.036), (54, 0.175, 0.043), (-57, 0.120, 0.040), (75, 0.050, 0.034), (-73, 0.075, 0.036),
        (96, 0.300, 0.050), (-98, 0.255, 0.047), (122, 0.095, 0.039), (-126, 0.205, 0.045), (146, 0.335, 0.052),
        (-150, 0.085, 0.037), (164, 0.055, 0.034), (-167, 0.150, 0.042), (181, 0.230, 0.047),
    ]

    static func lab3(_ v: SIMD3<Double>) -> String { f6v(v) }

    static func applyShade(_ lab: SIMD3<Double>, dL: Double) -> SIMD3<Double> {
        let sh = max(-dL, 0)
        let k = min(max(1 - chromaSlope * dL, chromaFloor), chromaCeil)
        let L = min(max(lab.x + dL, 0.25), 0.995)
        return oklabToLinear(SIMD3(L, lab.y * k + shadeTintA * sh, lab.z * k + shadeTintB * sh))
    }

    static let geometryShader = """
    #pragma varyings
    float3 ckP;
    #pragma body
    out.ckP = _geometry.position.xyz;
    """

    /// 무늬: 물체 좌표(ckPos · 높이 ckT · 둘레 각 ckTh)로 `ckLab`(dL = 0 일 때의 OKLab) · `ckShadeAdd` 를 정한다.
    static let pattern: String = {
        let list = drips.map { "float4(\(f6($0.0 * .pi / 180)), \(f6($0.1)), \(f6($0.2)), 0.0)" }.joined(separator: ", ")
        return """
        float3 ckPink = \(lab3(pinkCreamLab));
        float3 ckWhite = \(lab3(creamLab));
        float ckR = max(length(ckPos.xz), 0.05);
        float ckBase = 0.142 + 0.060 * (1.0 - cos(ckTh)) * 0.5 + 0.007 * sin(ckTh * 7.0 + 0.7) + 0.004 * sin(ckTh * 13.0 + 2.1);
        float ckY = (ckT - ckBase) * \(f6(bodyHeight));
        float ckDist = ckY;
        const float4 ckDrips[\(drips.count)] = { \(list) };
        for (int i = 0; i < \(drips.count); i++) {
            float ckDa = ckTh - ckDrips[i].x;
            ckDa = ckDa - 6.283185307 * floor((ckDa + 3.14159265) / 6.283185307);
            float ckX = ckDa * ckR;
            float ckCap = length(float2(ckX, ckY - clamp(ckY, 0.0, ckDrips[i].y))) - ckDrips[i].z;
            float ckBulb = length(float2(ckX, ckY - ckDrips[i].y)) - ckDrips[i].z * 1.16;
            float ckDd = min(ckCap, ckBulb);
            float ckHh = clamp(0.5 + 0.5 * (ckDd - ckDist) / 0.03, 0.0, 1.0);
            ckDist = mix(ckDd, ckDist, ckHh) - 0.03 * ckHh * (1.0 - ckHh);
        }
        float ckW = max(fwidth(ckDist), 0.0008);
        float ckCov = 1.0 - smoothstep(-ckW, ckW, ckDist);
        ckLab = mix(ckPink, ckWhite, ckCov);
        ckShadeAdd = -0.070 * (1.0 - smoothstep(0.0, 0.030, ckDist)) * (1.0 - ckCov)
                   - 0.040 * (1.0 - smoothstep(0.0, 0.016, -ckDist)) * ckCov;
        """
    }()

    /// 몸 fragment 수정자. `albedoOnly` = 초상용 무늬 지도: 피부 판정 없이 모든 조각에 dL = 0 의 무늬 색을 쓴다(앱은 false).
    static func fragmentShader(albedoOnly: Bool) -> String {
        let skinTest = albedoOnly ? "true" : "ckHue >= 215.0 && ckHue <= 300.0 && ckSat > 0.05 && ckSat < 0.75 && ckLuma > 0.10"
        let dl = albedoOnly ? "0.0" : "0.2104542553 * ckL1 + 0.7936177850 * ckM1 - 0.0040720468 * ckS1 - \(f6(lReference))"
        return """
        #pragma varyings
        float3 ckP;
        #pragma body
        float3 ckLin = clamp(_surface.diffuse.rgb, float3(0.0), float3(1.0));
        float3 ckE = select(1.055 * pow(ckLin, float3(1.0 / 2.4)) - 0.055, ckLin * 12.92, ckLin <= float3(0.0031308));
        float ckMx = max(ckE.r, max(ckE.g, ckE.b));
        float ckMn = min(ckE.r, min(ckE.g, ckE.b));
        float ckSat = ckMx > 0.0 ? (ckMx - ckMn) / ckMx : 0.0;
        float ckHue = 0.0;
        if (ckMx > ckMn) {
            float ckSpan = ckMx - ckMn;
            if (ckMx == ckE.r) { ckHue = 60.0 * ((ckE.g - ckE.b) / ckSpan); }
            else if (ckMx == ckE.g) { ckHue = 60.0 * ((ckE.b - ckE.r) / ckSpan + 2.0); }
            else { ckHue = 60.0 * ((ckE.r - ckE.g) / ckSpan + 4.0); }
            if (ckHue < 0.0) { ckHue += 360.0; }
        }
        float ckLuma = 0.299 * ckE.r + 0.587 * ckE.g + 0.114 * ckE.b;
        // 볼터치 번짐: 피부가 아닌 텍셀 중 '라벤더 피부 ↔ 볼터치' 선분 위에 있는 것(볼 가장자리 그러데이션). 그대로 두면 새 몸 위에
        // 라벤더 테가 남는다 → 케이크 색과 볼터치 색을 그 비율(ckBa)로 섞는다. 입 · 눈 · 하이라이트는 선분에서 멀어 걸리지 않는다.
        float3 ckDv = \(f6v(blushSRGB)) - \(f6v(lavenderSRGB));
        float ckBa = clamp(dot(ckE - \(f6v(lavenderSRGB)), ckDv) / dot(ckDv, ckDv), 0.0, 1.0);
        float ckRes = length(ckE - (\(f6v(lavenderSRGB)) + ckBa * ckDv));
        // 얼굴 상자(물체 좌표 — 눈 · 볼 · 입 텍셀 실측 x ±0.52 · y 0.16–0.53 · z > 0.4 에 여유) 밖은 전부 피부로 본다: 원본 디퓨즈의 뒤통수 ·
        // 아래쪽에 피부 판정을 못 넘는 옅은 텍셀 몇 개가 있어 라벤더 위에선 안 보이지만 크림 위에선 분홍 · 보라 티끌이 된다(실측: 정수리 뒤).
        float3 ckObj = in.ckP;
        bool ckInFace = ckObj.z > 0.30 && abs(ckObj.x) < 0.58 && ckObj.y > 0.08 && ckObj.y < 0.62;
        bool ckIsSkin = (\(skinTest)) || !ckInFace;
        float ckBw = (!ckIsSkin && ckLuma > 0.45 && ckBa > 0.02) ? 1.0 - smoothstep(0.05, 0.08, ckRes) : 0.0;
        if (ckIsSkin || ckBw > 0.0) {
            float ckL1 = pow(max(0.4122214708 * ckLin.r + 0.5363325363 * ckLin.g + 0.0514459929 * ckLin.b, 0.0), 1.0 / 3.0);
            float ckM1 = pow(max(0.2119034982 * ckLin.r + 0.6806995451 * ckLin.g + 0.1073969566 * ckLin.b, 0.0), 1.0 / 3.0);
            float ckS1 = pow(max(0.0883024619 * ckLin.r + 0.2817188376 * ckLin.g + 0.6299787005 * ckLin.b, 0.0), 1.0 / 3.0);
            float ckDL = \(dl);
            float3 ckPos = in.ckP;
            float ckT = (\(f6(bodyTop)) - ckPos.y) / \(f6(bodyHeight));
            float ckTh = atan2(ckPos.x, ckPos.z);
            float3 ckLab = \(lab3(creamLab));
            float ckShadeAdd = 0.0;
        \(pattern)
            ckLab.x += ckShadeAdd;
            float ckSh = max(-ckDL, 0.0);
            float ckK = clamp(1.0 - \(f6(chromaSlope)) * ckDL, \(f6(chromaFloor)), \(f6(chromaCeil)));
            float3 ckO = float3(clamp(ckLab.x + ckDL, 0.25, 0.995), ckLab.y * ckK + \(f6(shadeTintA)) * ckSh, ckLab.z * ckK + \(f6(shadeTintB)) * ckSh);
            float ckl = ckO.x + 0.3963377774 * ckO.y + 0.2158037573 * ckO.z;
            float ckm = ckO.x - 0.1055613458 * ckO.y - 0.0638541728 * ckO.z;
            float cks = ckO.x - 0.0894841775 * ckO.y - 1.2914855480 * ckO.z;
            ckl = ckl * ckl * ckl; ckm = ckm * ckm * ckm; cks = cks * cks * cks;
            float3 ckRGB = clamp(float3(4.0767416621 * ckl - 3.3077115913 * ckm + 0.2309699292 * cks,
                                        -1.2684380046 * ckl + 2.6097574011 * ckm - 0.3413193965 * cks,
                                        -0.0041960863 * ckl - 0.7034186147 * ckm + 1.7076147010 * cks), 0.0, 1.0);
            float3 ckBlushLin = \(f6v(blushLinear));
            ckRGB = mix(ckRGB, mix(ckRGB, ckBlushLin, ckBa), ckBw);
            float3 ckKeepOrig = ckLin;
            _output.color.rgb = mix(ckRGB, ckKeepOrig, ckIsSkin ? 0.0 : 1.0 - ckBw) * _output.color.a;
        }
        """
    }

    static func shaderModifiers(albedoOnly: Bool) -> [SCNShaderModifierEntryPoint: String] {
        [.geometry: geometryShader, .fragment: fragmentShader(albedoOnly: albedoOnly)]
    }
}

// MARK: - ① 몸 셰이더 — 초코(시안 D, lane-b 틀)

/// 밀크초콜릿 스펀지 몸에 흰 · 분홍 크림 띠, 정수리 가나슈(흘러내림 12줄 — 눈 자리는 짧게). 피부 = 표본 디퓨즈 P 와 그 자리 피부 S(셰이더 인자
/// `ckShadeMap` = aing_rainbow-shade.png)로 잰 비율 β(머리말 ①)만큼 케이크로 — 출력 = P + β·(케이크 − S). 밝기 = S 의 선형 휘도 ÷ `chocoSkinYRef`.
enum ChocoBody {
    static let shadeMapKey = "ckShadeMap"
    static let shadeGamma = 1.0
    /// (중심각°, 길이 t, 반폭 t) — 눈(정면 ±13…42°)과 볼 위는 짧게, 옆 · 뒤는 길게.
    static let drips: [(Double, Double, Double)] = [
        (0, 0.030, 0.019), (-27, 0.018, 0.020), (27, 0.022, 0.019), (-60, 0.150, 0.024), (63, 0.115, 0.023),
        (-95, 0.075, 0.022), (97, 0.170, 0.025), (-128, 0.125, 0.024), (131, 0.060, 0.021), (-160, 0.165, 0.025),
        (163, 0.095, 0.023), (180, 0.045, 0.020),
    ]
    static let ganacheEdge = 0.112

    /// 가로 띠(아래위 경계가 살짝 물결) 덮임. 이름 `name` 의 float 를 만든다.
    static func band(_ name: String, _ top: Double, _ bottom: Double, wave: Double = 0.004, freq: Double = 7, phase: Double = 0) -> String {
        """
        float \(name)A = \(f5(top)) + \(f5(wave)) * sin(ckTh * \(f5(freq)) + \(f5(phase)));
        float \(name)B = \(f5(bottom)) + \(f5(wave)) * sin(ckTh * \(f5(freq + 2)) + \(f5(phase + 1.7)));
        float \(name) = smoothstep(\(name)A - ckAAT, \(name)A + ckAAT, ckT) * (1.0 - smoothstep(\(name)B - ckAAT, \(name)B + ckAAT, ckT));
        """
    }

    /// 무늬 코드: ckBase(선형 바탕색 — 밝기 배율을 곱한다) · ckAdd(더할 광택) · ckKeep(1 이면 라벤더 그대로)를 정한다.
    static let pattern: String = {
        let edge = ganacheEdge
        var s = """
        float ckEdge = \(f5(edge)) + 0.005 * sin(ckTh * 5.0 + 0.7);
        float ckD = ckT - ckEdge;
        """
        for (i, d) in drips.enumerated() {
            s += """

            { float dth = ckTh - \(f5(d.0 * .pi / 180));
              dth -= 6.2831853 * floor((dth + 3.14159265) / 6.2831853);
              float sx = abs(dth) * ckR / \(f5(bodyHeight));
              float ty = ckT - clamp(ckT, \(f5(edge)), \(f5(edge + d.1)));
              float dd = sqrt(sx * sx + ty * ty) - \(f5(d.2));
              float hk = clamp(0.5 + 0.5 * (dd - ckD) / 0.022, 0.0, 1.0);
              ckD = mix(dd, ckD, hk) - 0.022 * hk * (1.0 - hk); } // drip \(i)
            """
        }
        s += """

        float ckAAD = max(fwidth(ckD), 1e-5);
        float ckGan = 1.0 - smoothstep(-ckAAD, ckAAD, ckD);
        \(band("ckCream", 0.430, 0.500, phase: 0.3))
        \(band("ckPink", 0.680, 0.740, phase: 2.1))
        float3 ckCake = \(f5hex(0x9A6444));
        ckCake = mix(ckCake, \(f5hex(0xFFF4EA)), ckCream);
        ckCake = mix(ckCake, \(f5hex(0xFFB3C6)), ckPink);
        // 가나슈: 짙은 초콜릿 + 윤기(물체 좌표에 고정된 반사 — 몸 텍스처의 빛 방향과 같다) + 가장자리 살짝 두꺼운 테.
        float3 ckH = normalize(float3(-0.38, 0.80, 0.46));
        float ckSpec = pow(max(dot(ckN, ckH), 0.0), 28.0) * 0.30 + pow(max(dot(ckN, ckH), 0.0), 5.0) * 0.02;
        float ckRim = smoothstep(-0.016, -0.002, ckD);
        float3 ckGanCol = mix(\(f5hex(0x5B3420)), \(f5hex(0x46281A)), ckRim * 0.8);
        ckBase = mix(ckCake, ckGanCol, ckGan);
        ckAdd = float3(ckSpec) * ckGan * (1.0 - ckRim * 0.5);
        """
        return s
    }()

    static let geometryShader = """
    #pragma varyings
    float3 ckVP;
    float2 ckUV;
    #pragma body
    out.ckVP = _geometry.position.xyz;
    out.ckUV = _geometry.texcoords[0];
    """

    /// 무늬는 **피부 판정 분기 밖**에서 계산한다(fwidth 는 갈라진 흐름 안에서 정의되지 않는다).
    static let fragmentShader: String = {
        let blush = String(format: "float3(%.2f, %.2f, %.2f)", chocoBlushSRGB.x, chocoBlushSRGB.y, chocoBlushSRGB.z)
        return """
        #pragma arguments
        texture2d<float> ckShadeMap;
        #pragma varyings
        float3 ckVP;
        float2 ckUV;
        #pragma body
        constexpr sampler ckSmp(coord::normalized, filter::linear, mip_filter::linear, address::repeat);
        float3 ckLin = clamp(_surface.diffuse.rgb, float3(0.0), float3(1.0));
        float3 ckSL = clamp(ckShadeMap.sample(ckSmp, in.ckUV).rgb, float3(0.0), float3(1.0));
        float3 ckPe = 255.0 * select(1.055 * pow(ckLin, float3(1.0 / 2.4)) - 0.055, ckLin * 12.92, ckLin <= float3(0.0031308));
        float3 ckSe = 255.0 * select(1.055 * pow(ckSL, float3(1.0 / 2.4)) - 0.055, ckSL * 12.92, ckSL <= float3(0.0031308));
        float3 ckDv = ckPe - ckSe;
        // 피부 비율 β(스크립트 `skinFraction` 과 같은 식): ① 볼터치 선(S→K) 위면 그 비율.
        float3 ckKs = \(blush) - ckSe;
        float ckAk = dot(ckDv, ckKs) / max(1e-6, dot(ckKs, ckKs));
        float ckRes = length(ckDv - clamp(ckAk, 0.0, 1.0) * ckKs);
        // ② 눈꺼풀 · 흰자 안티에일리어스 풀기: P = (1 − a)·S + a·F, F = S→P 방향 RGB 상자 끝 → a = 채널별 '끝까지 간 비율'의 최대.
        //    F 가 검정 쪽(루마 < 0.19…0.25)이거나 흰색 쪽(최소 채널 > 0.88…0.95)이면 β = 1 − a(테 텍셀이 몸색과 섞인다 · 눈 자체는 a = 1 → 원본),
        //    아니면(입 안 · 혀) 옛 식 1 − |P − S|/80.
        float3 ckAd = ckDv / min(-ckSe, float3(-1e-3));
        float3 ckAb = ckDv / max(float3(255.0) - ckSe, float3(1e-3));
        float3 ckAc = select(ckAb, ckAd, ckDv < float3(0.0));
        float ckCover = clamp(max(ckAc.r, max(ckAc.g, ckAc.b)), 0.0, 1.0);
        float3 ckF = ckSe + ckDv / max(ckCover, 1e-3);
        float ckFY = dot(ckF, float3(0.299, 0.587, 0.114)) / 255.0;
        float ckFm = min(ckF.r, min(ckF.g, ckF.b)) / 255.0;
        float ckTrust = max(1.0 - smoothstep(0.19, 0.25, ckFY), smoothstep(0.88, 0.95, ckFm));
        float ckOld = clamp(1.0 - length(ckDv) / 80.0, 0.0, 1.0);
        float ckBeta = (ckRes <= 20.0 && ckAk > -0.1 && ckAk < 1.1) ? 1.0 - clamp(ckAk, 0.0, 1.0) : mix(ckOld, 1.0 - ckCover, ckTrust);
        float ckShade = pow(clamp(dot(ckSL, float3(0.2126, 0.7152, 0.0722)) / \(f5(chocoSkinYRef)), 0.40, 1.45), \(f5(shadeGamma)));
        float3 ckP = in.ckVP;
        // aing.scn 에는 법선 소스가 없다(정점 · UV 뿐 — `_geometry.normal` 은 쓰레기). 윤기용 매끈한 법선은 몸을 감싼 타원체 기울기로 만든다.
        float3 ckN = normalize((ckP - float3(0.0, 0.001, 0.0)) / float3(0.6084, 0.7191, 0.5329));
        float ckT = (\(f5(bodyTop)) - ckP.y) / \(f5(bodyHeight));
        float ckTh = atan2(ckP.x, ckP.z);
        float ckR = length(ckP.xz);
        float ckAAT = max(fwidth(ckT), 1e-5);
        float3 ckBase = float3(1.0);
        float3 ckAdd = float3(0.0);
        float ckKeep = 0.0;
        \(pattern)
        float3 ckCol = mix(ckBase * ckShade + ckAdd, ckSL, ckKeep);
        // 얼굴 상자(물체 좌표 — 딸기 셰이더와 같은 상자) 밖은 전부 케이크: 원본 디퓨즈의 뒤통수 · 몸 아래에 피부 판정을 못 넘는 옅은 텍셀이
        // 흩어져 있어 라벤더 위에선 안 보이지만 어두운 몸 위에선 분홍 · 보라 티끌이 된다(시안 D 뒷모습 실측). 앞 몸 아래에 남는 1px 밝은 점은
        // 다른 UV 섬 텍셀을 같이 쓰는 삼각형의 밝기 점이다(무지개 머리말 ★ — 라벤더 · 무지개에도 있다).
        bool ckInFace = ckP.z > 0.30 && abs(ckP.x) < 0.58 && ckP.y > 0.08 && ckP.y < 0.62;
        float3 ckOut = ckInFace ? ckLin + ckBeta * (ckCol - ckSL) : ckCol;
        _output.color.rgb = clamp(ckOut, float3(0.0), float3(1.0)) * _output.color.a;
        """
    }()

    static let shaderModifiers: [SCNShaderModifierEntryPoint: String] = [.geometry: geometryShader, .fragment: fragmentShader]
}

// MARK: - ② 장식 공통

/// 정수리 위 (x, z) → 몸 표면 점 · 법선(물체 좌표). 앱도 같은 것을 쓴다(`meshSurfaceProbe`).
typealias SurfaceProbe = (Float, Float) -> (SIMD3<Float>, SIMD3<Float>)

/// 몸 메시 노드에 위(y 3)에서 아래(y −3)로 선분 hitTest — 가장 높은 맞은 점 · 그 법선(뒤집지 않은 그대로).
func meshSurfaceProbe(_ bodyNode: SCNNode) -> SurfaceProbe {
    { x, z in
        let hits = bodyNode.hitTestWithSegment(from: SCNVector3(x, 3, z), to: SCNVector3(x, -3, z),
                                               options: [SCNHitTestOption.backFaceCulling.rawValue: false])
        guard let top = hits.max(by: { $0.localCoordinates.y < $1.localCoordinates.y }) else { fail("정수리 hitTest 실패 (\(x), \(z))") }
        let p = top.localCoordinates, n = top.localNormal
        return (SIMD3(Float(p.x), Float(p.y), Float(p.z)), simd_normalize(SIMD3(Float(n.x), Float(n.y), Float(n.z))))
    }
}

// MARK: - ② 장식 — 딸기(시안 B: 초 하나 + 딸기 둘, lane-a 틀)

/// 장식 조각마다 매개 곡면 → SCNGeometry + 음영을 구운 작은 텍스처(몸 공간 고정 빛, 반 램버트 + 하이라이트). 전부 unlit.
enum StrawberryDecor {
    struct Look {
        var ambient = 0.62
        var spec = 0.25
        var gloss = 24.0
        var wrap = 0.4
    }

    /// 몸 공간에 고정한 빛(위 · 앞 · 살짝 왼쪽) — 아잉 디퓨즈에 구운 음영과 같은 쪽.
    static let keyLight = simd_normalize(SIMD3<Double>(-0.30, 0.85, 0.45))
    static let viewLight = simd_normalize(SIMD3<Double>(0, 0.30, 1))

    static func lit(_ albedo: SIMD3<Double>, _ n: SIMD3<Double>, _ look: Look) -> SIMD3<Double> {
        let ndl = simd_dot(n, keyLight)
        let diff = min(max((ndl + look.wrap) / (1 + look.wrap), 0), 1)
        let ao = 1 - 0.22 * max(-n.y, 0)
        var c = albedo * (look.ambient + (1 - look.ambient) * diff) * ao
        let h = simd_normalize(keyLight + viewLight)
        c += SIMD3(repeating: pow(max(simd_dot(n, h), 0), look.gloss) * look.spec)
        return simd_clamp(c, .zero, SIMD3(repeating: 1))
    }

    typealias SurfaceFn = (Float, Float) -> SIMD3<Float>

    static func surfaceNormal(_ pos: SurfaceFn, _ u: Float, _ v: Float, closedU: Bool) -> SIMD3<Float> {
        func at(_ vv: Float) -> SIMD3<Float> {
            let e: Float = 1e-3
            let u0 = closedU ? u - e : max(u - e, 0), u1 = closedU ? u + e : min(u + e, 1)
            let v0 = max(vv - e, 0), v1 = min(vv + e, 1)
            return simd_cross(pos(u1, vv) - pos(u0, vv), pos(u, v1) - pos(u, v0))
        }
        var n = at(v)
        var nudge: Float = 0.004
        while simd_length(n) < 1e-9 && nudge < 0.1 {
            n = at(v < 0.5 ? v + nudge : v - nudge)
            nudge *= 2
        }
        return simd_length(n) < 1e-12 ? SIMD3(0, 1, 0) : simd_normalize(n)
    }

    /// 매개 곡면 하나를 노드로: 정점 격자(nu × nv) · 법선 · UV, 텍스처 = 텍셀마다 albedo(2×2 표본 평균)에 몸 공간 법선으로 음영을 구운 것.
    /// `upFacing`: 열린 판(꽃받침)은 법선을 위쪽으로 맞춘다(양면).
    static func pieceNode(name: String, nu: Int, nv: Int, closedU: Bool, texW: Int, texH: Int, pos: @escaping SurfaceFn,
                          albedo: (Double, Double, SIMD3<Float>) -> SIMD3<Double>, look: Look, transform: simd_float4x4,
                          upFacing: Bool = false) -> SCNNode {
        let rot = simd_float3x3(simd_make_float3(transform.columns.0), simd_make_float3(transform.columns.1), simd_make_float3(transform.columns.2))
        func normal(_ u: Float, _ v: Float) -> SIMD3<Float> {
            var n = surfaceNormal(pos, u, v, closedU: closedU)
            if upFacing && simd_dot(rot * n, SIMD3(0, 1, 0)) < 0 { n = -n }
            return n
        }
        var verts = [SCNVector3](), norms = [SCNVector3](), uvs = [CGPoint]()
        for j in 0...nv {
            for i in 0...nu {
                let u = Float(i) / Float(nu), v = Float(j) / Float(nv)
                let p = pos(u, v), n = normal(u, v)
                verts.append(SCNVector3(p.x, p.y, p.z)); norms.append(SCNVector3(n.x, n.y, n.z)); uvs.append(CGPoint(x: CGFloat(u), y: CGFloat(v)))
            }
        }
        var idx = [UInt32]()
        let row = UInt32(nu + 1)
        for j in 0..<UInt32(nv) {
            for i in 0..<UInt32(nu) {
                let a = j * row + i, b = a + 1, c = a + row, d = c + 1
                idx += [a, b, c, b, d, c]
            }
        }
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: verts), SCNGeometrySource(normals: norms),
                                             SCNGeometrySource(textureCoordinates: uvs)],
                                   elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
        // 텍스처(행 0 = v 0 — SceneKit UV 원점은 그림 왼쪽 위).
        var px = [UInt8](repeating: 255, count: texW * texH * 4)
        for y in 0..<texH {
            for x in 0..<texW {
                var acc = SIMD3<Double>(0, 0, 0)
                for sy in 0..<2 { for sx in 0..<2 {
                    let u = (Double(x) + 0.25 + 0.5 * Double(sx)) / Double(texW), v = (Double(y) + 0.25 + 0.5 * Double(sy)) / Double(texH)
                    acc += albedo(u, v, pos(Float(u), Float(v)))
                } }
                let u = Float((Double(x) + 0.5) / Double(texW)), v = Float((Double(y) + 0.5) / Double(texH))
                let nw = rot * normal(u, v)
                let c = lit(acc / 4, simd_normalize(SIMD3<Double>(Double(nw.x), Double(nw.y), Double(nw.z))), look)
                let (r, g, b) = linearToBytes(c)
                let o = (y * texW + x) * 4
                px[o] = r; px[o + 1] = g; px[o + 2] = b
            }
        }
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = makeImage(px, texW, texH)
        material.diffuse.wrapS = closedU ? .repeat : .clamp
        material.diffuse.wrapT = .clamp
        material.diffuse.mipFilter = .linear
        material.isDoubleSided = upFacing
        geometry.materials = [material]
        let node = SCNNode(geometry: geometry)
        node.name = name
        node.simdTransform = transform
        return node
    }

    static func lathe(_ profile: @escaping (Float) -> (r: Float, y: Float), ridge: ((Float, Float) -> Float)? = nil,
                      lean: ((Float) -> SIMD2<Float>)? = nil) -> SurfaceFn {
        { u, v in
            let (r0, y) = profile(v)
            let a = 2 * Float.pi * u
            let r = r0 * (ridge?(u, v) ?? 1)
            let shift = lean?(v) ?? .zero
            return SIMD3(r * sin(a) + shift.x, y, r * cos(a) + shift.y)
        }
    }

    static func lin(_ r: Double, _ g: Double, _ b: Double) -> SIMD3<Double> { srgbBytesToLinear(r, g, b) }
    static func smooth(_ e0: Double, _ e1: Double, _ x: Double) -> Double { let t = min(max((x - e0) / (e1 - e0), 0), 1); return t * t * (3 - 2 * t) }
    static func wrapDiff(_ a: Double) -> Double { a - (a + 0.5).rounded(.down) }   // −0.5 … 0.5

    // 딸기

    struct StrawberrySpec { var radius: Float = 0.105; var height: Float = 0.235 }

    static func strawberryProfile(_ spec: StrawberrySpec) -> (Float) -> (r: Float, y: Float) {
        { s in
            let shoulder = sqrt(max(0, 1 - pow(1 - min(s / 0.2, 1), 2)))
            return (spec.radius * 1.12 * pow(max(1 - s, 0), 0.55) * shoulder, spec.height * s)
        }
    }

    /// 딸기 한 알(끝이 위) + 꽃받침 6장. `transform` = 몸(캐릭터) 공간.
    static func strawberryNode(_ spec: StrawberrySpec, transform: simd_float4x4, seed: Double) -> SCNNode {
        let group = SCNNode()
        group.name = "check.cake.strawberry"
        let profile = strawberryProfile(spec)
        let surface = lathe(profile)
        // 씨: 줄마다 둘레 길이에 맞춘 개수, 줄마다 반 칸 엇갈림. 표면 길이 단위로 잰 타원.
        let rows: [Double] = stride(from: 0.17, through: 0.86, by: 0.088).map { $0 }
        let rowCounts = rows.map { s -> Int in max(3, Int((2 * Double.pi * Double(profile(Float(s)).r) / 0.040).rounded())) }
        let berry = lin(236, 52, 76), berryTip = lin(250, 92, 104), seedColor = lin(255, 232, 150)
        func albedo(_ u: Double, _ v: Double, _ p: SIMD3<Float>) -> SIMD3<Double> {
            var c = berry + (berryTip - berry) * smooth(0.55, 1.0, v)
            let r = Double(profile(Float(v)).r)
            let dvLen = Double(spec.height) * 1.05
            var bestSeed = 1e9, bestPit = 1e9
            for (k, s) in rows.enumerated() where abs(s - v) < 0.09 {
                let n = Double(rowCounts[k])
                let offset = (k % 2 == 0 ? 0 : 0.5) + seed * 0.37
                let cell = (u * n - offset).rounded()
                for dc in -1...1 {
                    let su = (cell + Double(dc) + offset) / n
                    let dx = wrapDiff(u - su) * 2 * Double.pi * max(r, 0.01)
                    let dy = (v - s) * dvLen
                    let e = (dx / 0.0068) * (dx / 0.0068) + (dy / 0.0095) * (dy / 0.0095)
                    bestSeed = min(bestSeed, e)
                    bestPit = min(bestPit, (dx / 0.0125) * (dx / 0.0125) + (dy / 0.016) * (dy / 0.016))
                }
            }
            if bestPit < 1 { c *= 0.80 + 0.20 * smooth(0.55, 1.0, bestPit) }
            if bestSeed < 1.15 { c = c + (seedColor - c) * (1 - smooth(0.85, 1.15, bestSeed)) }
            return c
        }
        group.addChildNode(pieceNode(name: "berry", nu: 72, nv: 48, closedU: true, texW: 512, texH: 256, pos: surface,
                                     albedo: albedo, look: Look(ambient: 0.6, spec: 0.55, gloss: 36, wrap: 0.4), transform: transform))
        // 꽃받침: 몸통 아래쪽에서 바깥으로 뻗어 살짝 처지는 잎 6장.
        let leafGreen = lin(66, 150, 72), leafTip = lin(128, 196, 92), rib = lin(150, 210, 120)
        for i in 0..<6 {
            let psi = Float(i) * 2 * Float.pi / 6 + Float(seed) * 0.6
            let dir = SIMD3<Float>(sin(psi), 0, cos(psi)), side = SIMD3<Float>(cos(psi), 0, -sin(psi))
            let length: Float = 0.085 * (i % 2 == 0 ? 1.0 : 0.86), width: Float = 0.030
            let startR = spec.radius * 0.78, startY = spec.height * 0.13
            let leaf: SurfaceFn = { u, v in
                let hw = width * pow(max(sin(Float.pi * (0.12 + 0.88 * v)), 0), 0.9)
                let across = (u * 2 - 1) * hw
                let fold = 0.006 * (1 - (u * 2 - 1) * (u * 2 - 1))
                let centre = dir * (startR + length * v) + SIMD3<Float>(0, startY - 0.034 * v * v + 0.006 * v, 0)
                return centre + side * across + SIMD3<Float>(0, fold, 0)
            }
            func leafAlbedo(_ u: Double, _ v: Double, _ p: SIMD3<Float>) -> SIMD3<Double> {
                var c = leafGreen + (leafTip - leafGreen) * smooth(0.0, 1.0, v)
                let ribAmt = 1 - smooth(0.04, 0.10, abs(u * 2 - 1))
                c = c + (rib - c) * ribAmt * 0.6
                return c
            }
            group.addChildNode(pieceNode(name: "calyx\(i)", nu: 8, nv: 14, closedU: false, texW: 32, texH: 64, pos: leaf,
                                         albedo: leafAlbedo, look: Look(ambient: 0.62, spec: 0.12, gloss: 14, wrap: 0.5),
                                         transform: transform, upFacing: true))
        }
        return group
    }

    // 초 · 심지 · 불꽃 · 빛

    struct CandleSpec {
        var radius: Float = 0.037
        var height: Float = 0.20
        var stripe = lin(246, 112, 156)
        var base = lin(255, 251, 246)
    }

    /// 불꽃 끝의 초 공간 높이(꽂힌 깊이 0.04 를 뺀 바닥 기준) — `make` 가 몸 공간 꼭대기를 잴 때 쓴다.
    static func flameTipLocalY(_ spec: CandleSpec) -> Float { spec.height - 0.04 + 0.034 - 0.018 + 0.125 }

    static func candleNode(_ spec: CandleSpec, transform: simd_float4x4) -> SCNNode {
        let group = SCNNode()
        group.name = "check.cake.candle"
        let rc = spec.radius, hc = spec.height, e: Float = 0.009
        let side = hc - e, arc = Float.pi / 2 * e, cap = rc - e, total = side + arc + cap
        let profile: (Float) -> (r: Float, y: Float) = { s in
            let d = s * total
            if d < side { return (rc, d - 0.04) }
            if d < side + arc { let phi = (d - side) / e; return (rc - e + e * cos(phi), side - 0.04 + e * sin(phi)) }
            return (max(0, (rc - e) * (1 - (d - side - arc) / cap)), hc - 0.04)
        }
        // 꽂힌 깊이 0.04 — 모양은 y = −0.04 에서 시작한다(몸 표면 아래로 묻힌다).
        let stripe = spec.stripe, base = spec.base
        func albedo(_ u: Double, _ v: Double, _ p: SIMD3<Float>) -> SIMD3<Double> {
            let y = Double(p.y) + 0.04
            let onSide = Double(simd_length(SIMD2(p.x, p.z))) > Double(rc) - 0.0015 && y < Double(hc) - 0.004
            if !onSide { return base }
            let phase = u * 2 + y / 0.085
            let f = phase - phase.rounded(.down)
            let edge = 0.012
            let amt = smooth(-edge, edge, f - 0.08) * (1 - smooth(-edge, edge, f - 0.5))
            return base + (stripe - base) * amt
        }
        group.addChildNode(pieceNode(name: "candle", nu: 48, nv: 40, closedU: true, texW: 256, texH: 256, pos: lathe(profile),
                                     albedo: albedo, look: Look(ambient: 0.62, spec: 0.35, gloss: 30, wrap: 0.45), transform: transform))
        // 심지
        let wickTop = hc - 0.04 + 0.034
        let wick = lathe({ s in (0.0058 * (1 - 0.35 * s * s), hc - 0.045 + s * 0.079) })
        group.addChildNode(pieceNode(name: "wick", nu: 12, nv: 6, closedU: true, texW: 16, texH: 16, pos: wick,
                                     albedo: { _, v, _ in lin(70, 52, 46) + (lin(150, 90, 60) - lin(70, 52, 46)) * smooth(0.7, 1.0, v) },
                                     look: Look(ambient: 0.75, spec: 0.0, gloss: 8, wrap: 0.5), transform: transform))
        // 불꽃: 아래 둥글고 위가 뾰족한 물방울. 셰이더가 시선 · 법선 각으로 가운데 흰빛 → 가장자리 주황.
        let flameH: Float = 0.125, flameR: Float = 0.031
        let flameBase = wickTop - 0.018
        let flameProfile: (Float) -> (r: Float, y: Float) = { s in
            (flameR * 1.72 * sqrt(max(s, 0)) * pow(max(1 - s, 0), 1.05), flameBase + flameH * s)
        }
        var fVerts = [SCNVector3](), fNorms = [SCNVector3]()
        let fnu = 32, fnv = 24
        let flameSurface = lathe(flameProfile, lean: { s in SIMD2(0, 0) + SIMD2(0.004 * s * s, 0) })
        for j in 0...fnv { for i in 0...fnu {
            let u = Float(i) / Float(fnu), v = Float(j) / Float(fnv)
            let p = flameSurface(u, v), n = surfaceNormal(flameSurface, u, v, closedU: true)
            fVerts.append(SCNVector3(p.x, p.y, p.z)); fNorms.append(SCNVector3(n.x, n.y, n.z))
        } }
        var fIdx = [UInt32]()
        let fRow = UInt32(fnu + 1)
        for j in 0..<UInt32(fnv) { for i in 0..<UInt32(fnu) {
            let a = j * fRow + i, b = a + 1, c = a + fRow, d = c + 1
            fIdx += [a, b, c, b, d, c]
        } }
        let flameGeo = SCNGeometry(sources: [SCNGeometrySource(vertices: fVerts), SCNGeometrySource(normals: fNorms)],
                                   elements: [SCNGeometryElement(indices: fIdx, primitiveType: .triangles)])
        let flameMat = SCNMaterial()
        flameMat.lightingModel = .constant
        flameMat.shaderModifiers = [
            .geometry: "#pragma varyings\nfloat ckH;\n#pragma body\nout.ckH = _geometry.position.y;\n",
            .fragment: """
            #pragma varyings
            float ckH;
            #pragma body
            float ckF = clamp(dot(normalize(_surface.normal), normalize(_surface.view)), 0.0, 1.0);
            float ckS = clamp((in.ckH - \(f6(Double(flameBase)))) / \(f6(Double(flameH))), 0.0, 1.0);
            float3 ckEdge = float3(1.0, 0.36, 0.06);
            float3 ckMid = float3(1.0, 0.70, 0.16);
            float3 ckCore = float3(1.0, 0.96, 0.74);
            float3 ckC = mix(ckEdge, ckMid, smoothstep(0.05, 0.50, ckF));
            ckC = mix(ckC, ckCore, smoothstep(0.50, 0.90, ckF) * (1.0 - smoothstep(0.30, 0.85, ckS)));
            _output.color = float4(ckC, 1.0);
            """,
        ]
        flameGeo.materials = [flameMat]
        let flame = SCNNode(geometry: flameGeo)
        flame.name = "flame"
        flame.simdTransform = transform
        group.addChildNode(flame)
        // 빛 번짐: 불꽃 가운데의 빌보드 판(알파 · 깊이 안 씀).
        let glowSize = 64
        var gpx = [UInt8](repeating: 0, count: glowSize * glowSize * 4)
        for y in 0..<glowSize { for x in 0..<glowSize {
            let dx = (Double(x) + 0.5) / Double(glowSize) * 2 - 1, dy = (Double(y) + 0.5) / Double(glowSize) * 2 - 1
            let r2 = dx * dx + dy * dy
            let a = 0.42 * exp(-r2 * 5.0) * (1 - smooth(0.7, 1.0, sqrt(r2)))
            let o = (y * glowSize + x) * 4
            gpx[o] = UInt8((255 * a).rounded()); gpx[o + 1] = UInt8((214 * a).rounded()); gpx[o + 2] = UInt8((120 * a).rounded())
            gpx[o + 3] = UInt8((255 * a).rounded())
        } }
        let plane = SCNPlane(width: 0.26, height: 0.26)
        let glowMat = SCNMaterial()
        glowMat.lightingModel = .constant
        glowMat.diffuse.contents = makeImage(gpx, glowSize, glowSize)
        glowMat.blendMode = .alpha
        glowMat.writesToDepthBuffer = false
        glowMat.isDoubleSided = true
        plane.materials = [glowMat]
        let glow = SCNNode(geometry: plane)
        glow.name = "glow"
        glow.renderingOrder = 10
        let flameCenter = transform * SIMD4<Float>(0, flameBase + flameH * 0.42, 0, 1)
        glow.simdPosition = SIMD3(flameCenter.x, flameCenter.y, flameCenter.z)
        glow.constraints = [SCNBillboardConstraint()]
        group.addChildNode(glow)
        return group
    }

    // 자리 잡기

    /// 표면 점에 세우는 변환: 위(+y)를 (수직 ↔ 법선) 사이 `follow` 비율로 기울이고, `extraTilt`(라디안, 바깥쪽)만큼 더 눕히고, y 로 `spin` 돌리고,
    /// 법선 방향으로 `sink` 만큼 묻는다. 법선은 위를 보게 뒤집는다(시안 crownPoint).
    static func placement(_ probe: SurfaceProbe, x: Float, z: Float, follow: Float, sink: Float, spin: Float = 0, extraTilt: Float = 0,
                          scale: Float = 1) -> simd_float4x4 {
        var (p, n) = probe(x, z)
        if n.y < 0 { n = -n }
        var up = simd_normalize(simd_mix(SIMD3<Float>(0, 1, 0), n, SIMD3(repeating: follow)))
        if extraTilt != 0 {
            let outward = simd_normalize(SIMD3<Float>(x, 0, z) + SIMD3(1e-4, 0, 0))
            up = simd_normalize(up + outward * tan(extraTilt))
        }
        let q = simd_quatf(from: SIMD3(0, 1, 0), to: up) * simd_quatf(angle: spin, axis: SIMD3(0, 1, 0))
        var m = simd_float4x4(q)
        m.columns.0 *= scale; m.columns.1 *= scale; m.columns.2 *= scale
        let at = p - n * sink
        m.columns.3 = SIMD4(at.x, at.y, at.z, 1)
        return m
    }

    static let candle = CandleSpec()
    static let candleSeat: (x: Float, z: Float, follow: Float, sink: Float) = (0.0, -0.10, 0.1, 0.0)

    /// 시안 B 장식: 뒤쪽 가운데 초 하나 + 앞 양옆 딸기 둘(끝이 위). 반환 노드 이름 = `cakeDecorNodeName`.
    static func make(probe: SurfaceProbe) -> SCNNode {
        let d = SCNNode(); d.name = cakeDecorNodeName
        d.addChildNode(candleNode(candle, transform: placement(probe, x: candleSeat.x, z: candleSeat.z, follow: candleSeat.follow, sink: candleSeat.sink)))
        d.addChildNode(strawberryNode(StrawberrySpec(radius: 0.118, height: 0.262),
                                      transform: placement(probe, x: -0.21, z: 0.06, follow: 0.6, sink: 0.04, spin: 0.9, extraTilt: 0.14), seed: 0.7))
        d.addChildNode(strawberryNode(StrawberrySpec(radius: 0.118, height: 0.262),
                                      transform: placement(probe, x: 0.21, z: 0.08, follow: 0.6, sink: 0.04, spin: -0.5, extraTilt: 0.14), seed: 1.9))
        return d
    }

    /// 불꽃 끝의 몸 공간 y(앱 프레이밍 상수 `strawberryFlameTopY` 의 근거).
    static func flameTopY(probe: SurfaceProbe) -> Double {
        let m = placement(probe, x: candleSeat.x, z: candleSeat.z, follow: candleSeat.follow, sink: candleSeat.sink)
        return Double((m * SIMD4<Float>(0, flameTipLocalY(candle), 0, 1)).y)
    }
}

// MARK: - ② 장식 — 초코(시안 D: 크림 장미 위 딸기 하나 + 줄무늬 초 하나, lane-b 틀)

/// 정점을 캐릭터 물체 좌표로 미리 옮긴 SCNGeometry 몇 개(같은 재질끼리 합침)를 단위 변환 노드 하나 아래 둔다. 음영은 재질 셰이더가
/// **캐릭터 좌표에 고정된 가상 빛**(왼쪽 위 앞)으로 계산한다. 촛불만 화면 공간 발광 + 빌보드 빛무리 판 하나.
enum ChocoDecor {
    struct DMesh {
        var p: [SIMD3<Float>] = []
        var n: [SIMD3<Float>] = []
        var uv: [SIMD2<Float>] = []
        var idx: [UInt32] = []

        mutating func append(_ o: DMesh) {
            let base = UInt32(p.count)
            p += o.p; n += o.n; uv += o.uv; idx += o.idx.map { $0 + base }
        }

        func transformed(_ m: simd_float4x4) -> DMesh {
            let m3 = simd_float3x3(SIMD3(m.columns.0.x, m.columns.0.y, m.columns.0.z), SIMD3(m.columns.1.x, m.columns.1.y, m.columns.1.z),
                                   SIMD3(m.columns.2.x, m.columns.2.y, m.columns.2.z))
            let nm = m3.inverse.transpose
            var o = self
            o.p = p.map { q in let v = m * SIMD4(q, 1); return SIMD3(v.x, v.y, v.z) }
            o.n = n.map { simd_normalize(nm * $0) }
            return o
        }
    }

    /// 회전체: profile(s) → (반지름, 높이), s 는 0(아래) → 1(위). radial(θ, s) 는 반지름 배수. uv = (θ/2π, s).
    static func lathe(rings: Int, segments: Int, profile: (Float) -> (Float, Float), radial: ((Float, Float) -> Float)? = nil) -> DMesh {
        var m = DMesh()
        let cols = segments + 1
        for i in 0..<rings {
            let s = Float(i) / Float(rings - 1)
            let (r, y) = profile(s)
            for j in 0...segments {
                let u = Float(j) / Float(segments), th = u * 2 * .pi
                let rr = max(r * (radial?(th, s) ?? 1), 1e-5)
                m.p.append(SIMD3(rr * sin(th), y, rr * cos(th)))
                m.uv.append(SIMD2(u, s))
            }
        }
        for i in 0..<rings {
            for j in 0...segments {
                let jj = j % segments
                let jp = (jj + 1) % segments, jm = (jj - 1 + segments) % segments
                let dth = m.p[i * cols + jp] - m.p[i * cols + jm]
                let ds = m.p[min(i + 1, rings - 1) * cols + jj] - m.p[max(i - 1, 0) * cols + jj]
                var nn = simd_cross(dth, ds)
                if simd_length(nn) < 1e-12 { nn = SIMD3(0, i == 0 ? -1 : 1, 0) }
                m.n.append(simd_normalize(nn))
            }
        }
        for i in 0..<(rings - 1) {
            for j in 0..<segments {
                let a = UInt32(i * cols + j), b = a + 1, c = a + UInt32(cols), d = c + 1
                m.idx += [a, b, d, a, d, c]
            }
        }
        return m
    }

    /// 점 사이 Catmull-Rom 보간(s 오름차순 점들).
    static func curve(_ pts: [(Float, Float)]) -> (Float) -> Float {
        return { s in
            guard let k = pts.indices.dropLast().first(where: { s <= pts[$0 + 1].0 }) else { return pts.last!.1 }
            let p0 = pts[max(k - 1, 0)].1, p1 = pts[k].1, p2 = pts[k + 1].1, p3 = pts[min(k + 2, pts.count - 1)].1
            let t = (s - pts[k].0) / max(pts[k + 1].0 - pts[k].0, 1e-6)
            let t2 = t * t, t3 = t2 * t
            return 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
        }
    }

    static func translation(_ v: SIMD3<Float>) -> simd_float4x4 {
        var m = matrix_identity_float4x4; m.columns.3 = SIMD4(v, 1); return m
    }
    static func scaling(_ v: SIMD3<Float>) -> simd_float4x4 { simd_float4x4(diagonal: SIMD4(v, 1)) }
    static func rotation(_ angle: Float, _ axis: SIMD3<Float>) -> simd_float4x4 { simd_float4x4(simd_quatf(angle: angle, axis: simd_normalize(axis))) }
    /// +y 를 `axis` 로 돌리는 회전.
    static func aligning(_ axis: SIMD3<Float>) -> simd_float4x4 { simd_float4x4(simd_quatf(from: SIMD3(0, 1, 0), to: simd_normalize(axis))) }

    /// 장식 재질 셰이더: 캐릭터 좌표 고정 가상 빛(왼쪽 위 앞) + 둘레 감싸기 + 반사. `code` 가 base(선형) · specK · emit 를 정한다.
    static func decorMaterial(_ code: String, amb: Double = 0.58, dif: Double = 0.52, wrap: Double = 0.35, spec: Double = 0.25, shin: Double = 24,
                              name: String) -> SCNMaterial {
        let geometry = """
        #pragma varyings
        float3 ckP;
        float3 ckN;
        float2 ckUV;
        #pragma body
        out.ckP = _geometry.position.xyz;
        out.ckN = _geometry.normal;
        out.ckUV = _geometry.texcoords[0];
        """
        let fragment = """
        #pragma varyings
        float3 ckP;
        float3 ckN;
        float2 ckUV;
        #pragma body
        float3 n = normalize(in.ckN);
        float2 uv = in.ckUV;
        float3 p = in.ckP;
        float3 base = float3(1.0);
        float specK = \(f5(spec));
        float emit = 0.0;
        \(code)
        float3 Ld = normalize(float3(-0.35, 0.80, 0.50));
        float ndl = clamp((dot(n, Ld) + \(f5(wrap))) / \(f5(1 + wrap)), 0.0, 1.0);
        float3 Hh = normalize(Ld + normalize(float3(0.0, 0.35, 1.0)));
        float sp = pow(max(dot(n, Hh), 0.0), \(f5(shin))) * specK;
        float3 col = base * (\(f5(amb)) + \(f5(dif)) * ndl) + float3(sp);
        col = mix(col, base, emit);
        _output.color = float4(clamp(col, float3(0.0), float3(1.0)), 1.0);
        """
        let m = SCNMaterial()
        m.name = name
        m.lightingModel = .constant
        m.diffuse.contents = NSColor.white
        m.isDoubleSided = true
        m.shaderModifiers = [.geometry: geometry, .fragment: fragment]
        return m
    }

    enum Mat {
        static func strawberry() -> SCNMaterial {
            decorMaterial("""
            float3 red = \(f5hex(0xE8293B));
            base = mix(red * 0.86, red, smoothstep(0.0, 0.30, uv.y));
            base = mix(base, \(f5hex(0xFF8A86)), smoothstep(0.80, 0.97, uv.y));
            // 씨: 엇갈린 줄(16칸 × 8줄) — 노란 씨 + 둘레 움푹한 어두운 자리.
            float vS = (uv.y - 0.08) / 0.80;
            float inRows = step(0.0, vS) * step(vS, 1.0);
            float rowF = vS * 8.0;
            float row = floor(rowF);
            float fu = uv.x * 16.0 + 0.5 * fmod(row, 2.0);
            float2 cell = float2(fract(fu) - 0.5, fract(rowF) - 0.5);
            float d = length(cell * float2(0.039 / 0.0046, 0.024 / 0.0068));
            float aa = max(fwidth(d), 1e-4);
            float seed = (1.0 - smoothstep(1.0 - aa, 1.0 + aa, d)) * inRows;
            float pit = (1.0 - smoothstep(1.6 - aa, 1.9 + aa, d)) * inRows;
            base = mix(base, base * 0.70, pit * 0.55);
            base = mix(base, \(f5hex(0xFFE07A)), seed);
            specK = 0.42 * (1.0 - seed);
            """, amb: 0.55, dif: 0.55, spec: 0.42, shin: 46, name: "cake.strawberry")
        }
        static func leaf() -> SCNMaterial {
            decorMaterial("base = mix(\(f5hex(0x2E9E48)), \(f5hex(0x7BD65A)), clamp(n.y * 0.5 + 0.5, 0.0, 1.0));",
                          amb: 0.55, dif: 0.5, spec: 0.15, shin: 14, name: "cake.leaf")
        }
        static func cream(_ hex: Int = 0xFFF9F2) -> SCNMaterial {
            decorMaterial("base = \(f5hex(hex));", amb: 0.70, dif: 0.36, wrap: 0.5, spec: 0.10, shin: 10, name: "cake.cream")
        }
        static func candle(_ c1: Int, _ c2: Int, turns: Double = 2.4) -> SCNMaterial {
            decorMaterial("""
            float st = fract(uv.x * 2.0 + uv.y * \(f5(turns)));
            float sd = abs(st - 0.5) - 0.25;
            float aa = max(fwidth(st), 1e-4);
            float k = smoothstep(-aa, aa, sd);
            base = mix(\(f5hex(c1)), \(f5hex(c2)), k);
            base = mix(base, \(f5hex(c1)), step(1.001, uv.y));
            """, amb: 0.62, dif: 0.45, spec: 0.28, shin: 30, name: "cake.candle")
        }
        static func wick() -> SCNMaterial {
            decorMaterial("base = \(f5hex(0x3A2A22));", amb: 0.8, dif: 0.3, spec: 0.0, shin: 8, name: "cake.wick")
        }
        static func flame() -> SCNMaterial {
            decorMaterial("""
            float f = clamp(abs(normalize(_surface.normal).z), 0.0, 1.0);
            float3 c = mix(\(f5hex(0xFF9A2E)), \(f5hex(0xFFD54A)), smoothstep(0.05, 0.55, f));
            c = mix(c, \(f5hex(0xFFF8D8)), smoothstep(0.60, 0.95, f) * (1.0 - smoothstep(0.45, 0.85, uv.y)));
            base = c;
            emit = 1.0;
            """, spec: 0.0, name: "cake.flame")
        }
    }

    /// 빛무리(따뜻한 노랑, 가운데 알파 0.40 → 0, 가우스 × (1 − r²)² — 판 가장자리 훨씬 안에서 0 이 된다).
    static let glowImage: CGImage = {
        let s = 128
        var px = [UInt8](repeating: 0, count: s * s * 4)
        for y in 0..<s { for x in 0..<s {
            let dx = (Double(x) + 0.5) / Double(s) * 2 - 1, dy = (Double(y) + 0.5) / Double(s) * 2 - 1
            let r2 = dx * dx + dy * dy
            let a = 0.40 * exp(-r2 / 0.09) * max(0, 1 - r2) * max(0, 1 - r2)
            let o = (y * s + x) * 4
            px[o] = UInt8((255 * a).rounded()); px[o + 1] = UInt8((222 * a).rounded()); px[o + 2] = UInt8((130 * a).rounded()); px[o + 3] = UInt8((255 * a).rounded())
        } }
        return makeImage(px, s, s)
    }()

    /// 장식 한 덩어리(같은 재질끼리 합친 메시).
    final class Builder {
        var parts: [(String, DMesh, SCNMaterial)] = []
        var glows: [SIMD3<Float>] = []
        var flameTips: [SIMD3<Float>] = []

        func add(_ key: String, _ mesh: DMesh, _ material: @autoclosure () -> SCNMaterial) {
            if let i = parts.firstIndex(where: { $0.0 == key }) { parts[i].1.append(mesh) } else { parts.append((key, mesh, material())) }
        }

        /// 짜 올린 크림(별깍지 로제트): 바닥 중심 `base`, 축 `axis`. 반환: 꼭대기 근처(딸기를 얹을 자리).
        @discardableResult
        func rosette(at base: SIMD3<Float>, axis: SIMD3<Float>, radius: Float = 0.17, height: Float = 0.15, color: Int = 0xFFF9F2, key: String = "cream") -> SIMD3<Float> {
            let m = lathe(rings: 44, segments: 128, profile: { s in
                let r = radius * pow(max(1 - s, 0), 0.62) * (0.80 + 0.20 * min(s / 0.18, 1))
                return (r, height * s)
            }, radial: { th, s in 1 + 0.15 * cos(8 * th + 7.5 * s) * (1 - 0.7 * s) })
            add(key, m.transformed(translation(base) * aligning(axis)), Mat.cream(color))
            return base + simd_normalize(axis) * height * 0.78
        }

        /// 딸기(끝이 아래, 꼭지 잎이 위). `tip` 에 끝이 닿는다.
        func strawberry(tip: SIMD3<Float>, axis: SIMD3<Float>, height: Float = 0.29, radius: Float = 0.118, spin: Float = 0.3) {
            let shape = curve([(0, 0), (0.06, 0.30), (0.18, 0.62), (0.35, 0.86), (0.55, 0.99), (0.72, 1.0), (0.85, 0.90), (0.94, 0.66), (0.985, 0.32), (1.0, 0.0)])
            let body = lathe(rings: 72, segments: 96, profile: { s in (radius * max(shape(s), 0), height * s - (s > 0.9 ? (s - 0.9) * height * 0.25 : 0)) },
                             radial: { th, s in 1 + 0.035 * cos(3 * th + 0.4) * sin(.pi * s) })
            let frame = translation(tip) * aligning(axis) * rotation(spin, SIMD3(0, 1, 0))
            add("strawberry", body.transformed(frame), Mat.strawberry())
            // 꼭지 잎 6장 + 줄기.
            let topY = height * 0.975 + 0.004
            for k in 0..<6 {
                let ang = Float(k) / 6 * 2 * .pi + (k % 2 == 0 ? 0 : 0.15)
                let len: Float = k % 2 == 0 ? 0.072 : 0.060
                let leaf = lathe(rings: 14, segments: 20, profile: { s in (sin(.pi * s), -cos(.pi * s)) })
                // 꼭지 잎은 어깨를 따라 살짝만 처진다(0.22 rad) — 더 처지면 딸기 어깨 속에 묻힌다(실측).
                let local = rotation(ang, SIMD3(0, 1, 0)) * rotation(0.22, SIMD3(1, 0, 0)) * translation(SIMD3(0, 0, len * 0.80))
                    * scaling(SIMD3(0.030, 0.0080, len))
                add("leaf", leaf.transformed(frame * translation(SIMD3(0, topY, 0)) * local), Mat.leaf())
            }
            let stem = lathe(rings: 8, segments: 16, profile: { s in (0.009 - 0.003 * s, 0.045 * s) })
            add("leaf", stem.transformed(frame * translation(SIMD3(0, topY - 0.006, 0)) * rotation(0.35, SIMD3(0, 0, 1))), Mat.leaf())
        }

        /// 생일 초(나선 줄무늬) + 심지 + 불꽃 + 빛무리. `base` 는 몸 속으로 묻힐 바닥.
        func candle(at base: SIMD3<Float>, axis: SIMD3<Float>, height: Float, radius: Float = 0.030, colors: (Int, Int), key: String) {
            let frame = translation(base) * aligning(axis)
            let body = lathe(rings: 40, segments: 48, profile: { s in
                if s < 0.03 { return (radius * s / 0.03, 0) }
                if s < 0.94 { return (radius, height * (s - 0.03) / 0.91) }
                let q = (s - 0.94) / 0.06
                return (radius * (1 - q * q * 0.96), height + 0.008 * sin(q * .pi / 2))
            })
            // uv.y 를 높이 비율로(위 뚜껑은 1 넘게 — 셰이더가 단색으로 칠한다).
            var b = body
            b.uv = b.p.map { SIMD2(0, $0.y / height) }
            for i in b.uv.indices { b.uv[i].x = body.uv[i].x; if body.uv[i].y >= 0.94 { b.uv[i].y = 1.002 } }
            add(key, b.transformed(frame), Mat.candle(colors.0, colors.1))
            let wick = lathe(rings: 6, segments: 12, profile: { s in (0.0048, height - 0.004 + 0.040 * s) })
            add("wick", wick.transformed(frame), Mat.wick())
            let fh: Float = 0.105, fr: Float = 0.029
            let flame = lathe(rings: 40, segments: 40, profile: { s in (fr * pow(sin(.pi * pow(s, 0.62)), 0.85), fh * s) })
            let flameBase = height + 0.016
            add("flame", flame.transformed(frame * translation(SIMD3(0, flameBase, 0))), Mat.flame())
            let c = frame * SIMD4(0, flameBase + fh * 0.38, 0, 1)
            glows.append(SIMD3(c.x, c.y, c.z))
            let tip = frame * SIMD4(0, flameBase + fh, 0, 1)
            flameTips.append(SIMD3(tip.x, tip.y, tip.z))
        }

        func node() -> SCNNode {
            let root = SCNNode()
            root.name = cakeDecorNodeName
            for (key, m, material) in parts {
                let vs = SCNGeometrySource(vertices: m.p.map { SCNVector3($0.x, $0.y, $0.z) })
                let ns = SCNGeometrySource(normals: m.n.map { SCNVector3($0.x, $0.y, $0.z) })
                let ts = SCNGeometrySource(textureCoordinates: m.uv.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) })
                let el = SCNGeometryElement(indices: m.idx, primitiveType: .triangles)
                let g = SCNGeometry(sources: [vs, ns, ts], elements: [el])
                g.materials = [material]
                let child = SCNNode(geometry: g)
                child.name = "cake.\(key)"
                root.addChildNode(child)
            }
            for (i, c) in glows.enumerated() {
                let plane = SCNPlane(width: 0.30, height: 0.30)
                let m = SCNMaterial()
                m.lightingModel = .constant
                m.diffuse.contents = ChocoDecor.glowImage
                m.blendMode = .alpha
                m.writesToDepthBuffer = false
                m.isDoubleSided = true
                plane.materials = [m]
                let g = SCNNode(geometry: plane)
                g.name = "cake.glow\(i)"
                g.simdPosition = c
                g.constraints = [SCNBillboardConstraint()]
                g.renderingOrder = 50
                root.addChildNode(g)
            }
            return root
        }
    }

    /// 머리 위 자리: 표면 점에서 `sink` 만큼 묻고, 축은 위와 법선 사이(`tilt`).
    static func seat(_ probe: SurfaceProbe, _ x: Float, _ z: Float, sink: Float, tilt: Float) -> (SIMD3<Float>, SIMD3<Float>) {
        let (p, n) = probe(x, z)
        let axis = simd_normalize(simd_mix(SIMD3<Float>(0, 1, 0), n, SIMD3(repeating: tilt)))
        return (p - axis * sink, axis)
    }

    static func build(probe: SurfaceProbe) -> Builder {
        let b = Builder()
        let (rb, ra) = seat(probe, 0.07, 0.08, sink: 0.03, tilt: 0.6)
        let top = b.rosette(at: rb, axis: ra)
        b.strawberry(tip: top - ra * 0.02, axis: simd_normalize(ra + SIMD3(0.10, 0, 0.06)), spin: 0.4)
        let (cb, ca) = seat(probe, -0.20, -0.10, sink: 0.05, tilt: 0.25)
        b.candle(at: cb, axis: ca, height: 0.31, colors: (0xFFFFFF, 0xFF7FA6), key: "candle")
        return b
    }

    /// 시안 D 장식: 앞 오른쪽 크림 장미 위 딸기 하나 + 뒤 왼쪽 흰 · 분홍 줄무늬 초 하나. 반환 노드 이름 = `cakeDecorNodeName`.
    static func make(probe: SurfaceProbe) -> SCNNode { build(probe: probe).node() }

    /// 불꽃 끝의 몸 공간 y(앱 프레이밍 상수 `chocoFlameTopY` 의 근거).
    static func flameTopY(probe: SurfaceProbe) -> Double { Double(build(probe: probe).flameTips.map(\.y).max() ?? 0) }
}

// MARK: - 케이크 종류

enum CakeKind: CaseIterable {
    case strawberry, choco
    var id: String { self == .strawberry ? strawberryID : chocoID }
    var label: String { self == .strawberry ? "딸기" : "초코" }
    func decor(_ probe: SurfaceProbe) -> SCNNode { self == .strawberry ? StrawberryDecor.make(probe: probe) : ChocoDecor.make(probe: probe) }
    /// 초상 카메라 채움(시안 그대로 — 딸기 0.84 · 초코 0.62). 같은 자리 · 같은 원근으로 몸 무늬 지도와 장식 지도를 굽는다.
    var portraitFill: Float { self == .strawberry ? 0.84 : 0.62 }
}

// MARK: - 몸 디퓨즈 · 씬(생성기 전용)

func decodedTexture(_ contents: Any?) -> CGImage? {
    guard let contents else { return nil }
    if CFGetTypeID(contents as CFTypeRef) == CGImage.typeID { return (contents as! CGImage) }
    if let data = contents as? Data, let s = CGImageSourceCreateWithData(data as CFData, nil) { return CGImageSourceCreateImageAtIndex(s, 0, nil) }
    if let image = contents as? NSImage { return image.cgImage(forProposedRect: nil, context: nil, hints: nil) }
    if let url = contents as? URL { return NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil) }
    return nil
}

/// 앱 `applyUnlitMaterials` 정규화(512 초과면 줄임, DeviceRGB premultipliedLast).
func appDiffuse(_ cg: CGImage) -> CGImage {
    let maxSide = max(cg.width, cg.height)
    guard maxSide > 512 else { return cg }
    let scale = 512 / CGFloat(maxSide)
    let w = max(1, Int((CGFloat(cg.width) * scale).rounded())), h = max(1, Int((CGFloat(cg.height) * scale).rounded()))
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    return ctx.makeImage()!
}

struct BodyAssets {
    let original: CGImage     // 라벤더 디퓨즈(정규화)
    let composite: CGImage    // isGoldSkin(원본) ? 밝기 맵 : 원본
    let shade: CGImage        // aing_rainbow-shade.png
    let refColor: CGImage     // 초코 무늬 지도용: 피부 기준색(밝기 배율 1) 16² 한 장
    let skinYRef: Double
    let blush: SIMD3<Double>
}

func loadBodyAssets() -> BodyAssets {
    guard let scene = try? SCNScene(url: URL(fileURLWithPath: modelPath), options: nil) else { fail("모델을 못 읽었다: \(modelPath)") }
    var found: SCNNode?
    scene.rootNode.enumerateHierarchy { node, stop in if node.geometry != nil { found = node; stop.pointee = true } }
    guard let node = found, node.simdWorldTransform == matrix_identity_float4x4,
          let original = decodedTexture(node.geometry?.materials.first?.diffuse.contents).map(appDiffuse) else {
        fail("메시 구조가 예상과 다르다(노드 변환이 단위여야 셰이더 물체 좌표가 맞는다)")
    }
    let (a, b) = scene.rootNode.boundingBox
    guard abs(Double(b.y) - bodyTop) < 1e-5, abs(Double(b.y - a.y) - bodyHeight) < 1e-5 else {
        fail(String(format: "메시 높이가 셰이더 상수와 다르다: 정수리 %.6f · 높이 %.6f", Double(b.y), Double(b.y - a.y)))
    }
    let shade = loadImage(shadePath)
    guard shade.width == original.width, shade.height == original.height else { fail("밝기 맵 크기가 디퓨즈와 다르다") }
    let o = bytes(original), s = bytes(shade)
    var out = o
    for i in 0..<(original.width * original.height) where isGoldSkin(Int(o[i * 4]), Int(o[i * 4 + 1]), Int(o[i * 4 + 2])) {
        out[i * 4] = s[i * 4]; out[i * 4 + 1] = s[i * 4 + 1]; out[i * 4 + 2] = s[i * 4 + 2]; out[i * 4 + 3] = 255
    }
    let composite = makeImage(out, original.width, original.height, space: CGColorSpaceCreateDeviceRGB())
    // 초코 기준 휘도 = 합성 피부 텍셀 선형 휘도 중앙값 · 기준색 = 그 휘도에 가장 가까운 피부 텍셀.
    var ys = [Double]()
    var skinTexels = [(Double, (UInt8, UInt8, UInt8))]()
    for i in 0..<(out.count / 4) where isGoldSkin(Int(out[i * 4]), Int(out[i * 4 + 1]), Int(out[i * 4 + 2])) {
        let y = lumaLinear(srgbBytesToLinear(Double(out[i * 4]), Double(out[i * 4 + 1]), Double(out[i * 4 + 2])))
        ys.append(y); skinTexels.append((y, (out[i * 4], out[i * 4 + 1], out[i * 4 + 2])))
    }
    ys.sort()
    let yRef = ys[ys.count / 2]
    var best = (UInt8(0), UInt8(0), UInt8(0)), bestD = Double.infinity
    for (y, c) in skinTexels where abs(y - yRef) < bestD { bestD = abs(y - yRef); best = c }
    var rpx = [UInt8](repeating: 255, count: 16 * 16 * 4)
    for i in 0..<(16 * 16) { rpx[i * 4] = best.0; rpx[i * 4 + 1] = best.1; rpx[i * 4 + 2] = best.2 }
    let refColor = makeImage(rpx, 16, 16, space: CGColorSpaceCreateDeviceRGB())
    // 볼터치 대표색 K(원본 디퓨즈 — 색상 ≥330° 또는 ≤8° · 채도 0.2–0.7 · 루마 > 0.55 평균).
    var sum = SIMD3<Double>(0, 0, 0), count = 0.0
    for i in 0..<(o.count / 4) {
        let r = Double(o[i * 4]), g = Double(o[i * 4 + 1]), bb = Double(o[i * 4 + 2])
        let (hue, sat, l) = hueSatLum(r, g, bb)
        if (hue >= 330 || hue <= 8), sat >= 0.2, sat <= 0.7, l > 0.55 { sum += SIMD3(r, g, bb); count += 1 }
    }
    guard count > 0 else { fail("디퓨즈에서 볼터치를 못 찾았다") }
    return BodyAssets(original: original, composite: composite, shade: shade, refColor: refColor, skinYRef: yRef, blush: sum / count)
}

enum BodyLook { case cake(CakeKind), patternMap(CakeKind), depthOnly }

struct Rig {
    let scene: SCNScene
    let facing: SCNNode
    let character: SCNNode
    let bodyNode: SCNNode
    let bodyMin: SIMD3<Float>
    let bodyMax: SIMD3<Float>
}

/// 앱 makeAingScene 과 같은 짜임: root → wrapper → facing(요 회전) → character(aing.scn 루트 자식, 메시 노드). 장식은 character 의 자식.
func makeRig(_ look: BodyLook, decor kind: CakeKind?, assets: BodyAssets) -> Rig {
    guard let scene = try? SCNScene(url: URL(fileURLWithPath: modelPath), options: nil) else { fail("모델을 못 읽었다") }
    scene.background.contents = NSColor.clear
    guard let character = scene.rootNode.childNodes.first else { fail("캐릭터 노드 없음") }
    var bodyNode: SCNNode?
    scene.rootNode.enumerateHierarchy { node, stop in if node.geometry != nil { bodyNode = node; stop.pointee = true } }
    guard let bodyNode, let material = bodyNode.geometry?.materials.first else { fail("몸 재질 없음") }
    material.lightingModel = .constant
    switch look {
    case .cake(.strawberry):
        material.diffuse.contents = assets.composite
        material.shaderModifiers = StrawberryBody.shaderModifiers(albedoOnly: false)
    case .patternMap(.strawberry):
        material.diffuse.contents = assets.composite
        material.shaderModifiers = StrawberryBody.shaderModifiers(albedoOnly: true)
    case .cake(.choco):
        material.diffuse.contents = assets.composite
        material.shaderModifiers = ChocoBody.shaderModifiers
        material.setValue(SCNMaterialProperty(contents: assets.shade), forKey: ChocoBody.shadeMapKey)
    case .patternMap(.choco):
        material.diffuse.contents = assets.refColor
        material.shaderModifiers = ChocoBody.shaderModifiers
        material.setValue(SCNMaterialProperty(contents: assets.refColor), forKey: ChocoBody.shadeMapKey)
    case .depthOnly:
        material.diffuse.contents = assets.composite
        material.colorBufferWriteMask = []
        bodyNode.renderingOrder = -100
    }
    let (a, b) = scene.rootNode.boundingBox   // 몸만(장식 붙이기 전)
    if let kind {
        let decor = kind.decor(meshSurfaceProbe(bodyNode))
        // 생성기 전용: 장식 조각마다 그리기 순서를 고정한다. 딸기 꽃받침처럼 같은 깊이로 겹치는 조각은 먼저 그린 쪽이 이기는데, 같은 순서 값이면
        // SceneKit 이 실행마다 다른 순서로 그려 1–2 화소가 1 단계씩 갈렸다(실측 — 같은 입력 같은 바이트가 깨진다). 앱에선 1–2 화소 1 단계 차라 따로 고칠 것이 없다.
        var order = 0
        decor.enumerateHierarchy { node, _ in
            guard node.geometry != nil else { return }
            order += 1
            node.renderingOrder = node.renderingOrder != 0 ? node.renderingOrder + 1_000 : order
        }
        character.addChildNode(decor)
    }
    let wrapper = SCNNode(), facing = SCNNode()
    character.removeFromParentNode()
    facing.addChildNode(character)
    wrapper.addChildNode(facing)
    scene.rootNode.addChildNode(wrapper)
    return Rig(scene: scene, facing: facing, character: character, bodyNode: bodyNode,
               bodyMin: SIMD3(Float(a.x), Float(a.y), Float(a.z)), bodyMax: SIMD3(Float(b.x), Float(b.y), Float(b.z)))
}

/// 앱 카메라(CheckCharacter3DScene.addFramingCamera)의 자리 · 방향 — **몸만** 본 상자로 잡는다. `fov` 만 넓혀 같은 원근의 더 큰 판을 굽는다.
func appCamera(_ rig: Rig, fov: CGFloat = 40) -> SCNNode {
    let center = (rig.bodyMin + rig.bodyMax) / 2
    let extent = max(rig.bodyMax.x - rig.bodyMin.x, rig.bodyMax.y - rig.bodyMin.y)
    let distance = extent / (2 * tan(20 * Float.pi / 180)) * 1.4
    let node = SCNNode()
    let camera = SCNCamera()
    camera.fieldOfView = fov
    camera.zNear = 0.01
    camera.zFar = 1_000
    node.camera = camera
    node.simdPosition = SIMD3(center.x, center.y + extent * 0.55, rig.bodyMax.z + distance)
    node.simdLook(at: SIMD3(center.x, center.y - extent * 0.16, center.z))
    return node
}

func meshPositions(_ bodyNode: SCNNode) -> [SIMD3<Float>] {
    guard let vs = bodyNode.geometry?.sources(for: .vertex).first else { fail("정점 없음") }
    var pos = [SIMD3<Float>](repeating: .zero, count: vs.vectorCount)
    vs.data.withUnsafeBytes { raw in
        for i in 0..<vs.vectorCount {
            let b = vs.dataOffset + i * vs.dataStride
            pos[i] = SIMD3(raw.loadUnaligned(fromByteOffset: b, as: Float.self), raw.loadUnaligned(fromByteOffset: b + 4, as: Float.self),
                           raw.loadUnaligned(fromByteOffset: b + 8, as: Float.self))
        }
    }
    return pos
}

/// 초상 카메라(무지개 스크립트 portraitCamera 와 같다): 앱 카메라 방향으로 몸 중심을 보고, 몸이 프레임의 `fill` 만큼 차는 거리.
/// `widen` 배로 시야(tan 반각)만 넓힌다 — 같은 자리 · 같은 원근이라 넓힌 그림 = 원래 프레임 둘레에 덧댄 것.
func portraitCamera(_ rig: Rig, fill: Float, widen: Double = 1) -> SCNNode {
    let pos = meshPositions(rig.bodyNode)
    let center = (rig.bodyMin + rig.bodyMax) / 2
    let extent = max(rig.bodyMax.x - rig.bodyMin.x, rig.bodyMax.y - rig.bodyMin.y)
    let distance = extent / (2 * tan(20 * Float.pi / 180)) * 1.4
    let camPos = SIMD3<Float>(center.x, center.y + extent * 0.55, rig.bodyMax.z + distance)
    let target = SIMD3<Float>(center.x, center.y - extent * 0.16, center.z)
    let dir = simd_normalize(target - camPos)
    let right = simd_normalize(simd_cross(dir, SIMD3<Float>(0, 1, 0))), up = simd_cross(right, dir)
    let tanHalf = tan(20 * Float.pi / 180)
    var d: Float = 3
    for _ in 0..<12 {
        let cpos = center - dir * d
        var x0: Float = .infinity, x1: Float = -.infinity, y0: Float = .infinity, y1: Float = -.infinity
        for p in pos {
            let v = p - cpos, z = simd_dot(v, dir)
            let x = simd_dot(v, right) / z / tanHalf, y = simd_dot(v, up) / z / tanHalf
            x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y)
        }
        d *= max(x1 - x0, y1 - y0) / 2 / fill
    }
    let n = SCNNode(); n.camera = SCNCamera()
    n.camera!.fieldOfView = CGFloat(2 * atan(widen * tan(20 * Double.pi / 180)) * 180 / Double.pi)
    n.camera!.zNear = 0.01; n.camera!.zFar = 1_000
    n.simdPosition = center - dir * d; n.simdLook(at: center)
    return n
}

/// SCNRenderer 스냅숏의 반투명 화소는 '선형에서 프리멀티한 값을 sRGB 로 부호화'한 값이다(실측: 알파 0.5 노랑 → 188,149,35,128 —
/// rgb 가 알파를 넘는다). 바른 sRGB 프리멀티로 고친다(불투명 화소는 그대로).
func straightened(_ image: NSImage) -> CGImage {
    guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let cg = rep.cgImage else { fail("렌더 실패") }
    let w = cg.width, h = cg.height
    var px = bytes(cg, space: sRGB)
    for i in 0..<(w * h) {
        let a = Double(px[i * 4 + 3]) / 255
        if a >= 1 { continue }
        if a <= 0 { px[i * 4] = 0; px[i * 4 + 1] = 0; px[i * 4 + 2] = 0; continue }
        for c in 0..<3 {
            let lin = min(srgbToLinear(Double(px[i * 4 + c]) / 255) / a, 1)
            px[i * 4 + c] = UInt8(min(255, (linearToSrgb(lin) * a * 255).rounded()))
        }
    }
    return makeImage(px, w, h)
}

let metalDevice = MTLCreateSystemDefaultDevice()

func snapshot(_ rig: Rig, camera: SCNNode, size: Int, yawDegrees: Double = 0) -> CGImage {
    rig.facing.eulerAngles = SCNVector3(0, CGFloat(yawDegrees * .pi / 180), 0)
    if camera.parent == nil { rig.scene.rootNode.addChildNode(camera) }
    let renderer = SCNRenderer(device: metalDevice, options: nil)
    renderer.scene = rig.scene
    renderer.pointOfView = camera
    renderer.autoenablesDefaultLighting = false
    return straightened(renderer.snapshot(atTime: 0, with: CGSize(width: size, height: size), antialiasingMode: .multisampling4X))
}

func alphaBox(_ px: [UInt8], _ w: Int, _ h: Int, threshold: UInt8) -> (Int, Int, Int, Int)? {
    var x0 = w, x1 = -1, y0 = h, y1 = -1
    for y in 0..<h { for x in 0..<w where px[(y * w + x) * 4 + 3] > threshold { x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y) } }
    return x1 >= x0 ? (x0, x1, y0, y1) : nil
}

// MARK: - 초상(192²)

/// 2D 아잉 초상 분석(금 · 무지개 초상과 같은 틀): 피부 핵심 · 볼터치 대표색 K · 그 자리 피부색 S(인페인트) · 피부 밝기 기준 · 몸 상자.
struct PortraitSource {
    let label: String
    let w: Int, h: Int
    let px: [UInt8]
    let P: [SIMD3<Double>], A: [Double], core: [Bool], S: [SIMD3<Double>], K: SIMD3<Double>
    let lRef: Double   // 피부 핵심 OKLab L 중앙값(딸기 밝기 차 기준)
    let yRef: Double   // 피부 핵심 선형 휘도 중앙값(초코 밝기 배율 기준)
    let box: (Int, Int, Int, Int)   // 알파 > 0.5 상자(x0 x1 y0 y1)
    /// 실루엣 가장자리(알파 < 0.5 에서 `rimRadius` px 안). 2D 초상의 테두리 빛(흰빛에 가까운 밝은 띠)은 무늬가 아니라 몸 음영이다 —
    /// 여기서 흰색 풀기(①)를 쓰면 그 띠를 흰 장식으로 알아 살려 어두운 초코 몸 테두리에 점선 같은 밝은 줄이 선다(시무룩 초상 실측). 그래서
    /// 이 띠는 시안의 옛 식(금 · 무지개 초상과 같은 β)으로 둔다. 눈 · 입 · 눈썹은 실루엣에서 멀어 걸리지 않는다.
    let nearRim: [Bool]
}

func analyzePortrait(_ path: String, label: String) -> PortraitSource {
    let source = loadImage(path)
    let w = source.width, h = source.height
    guard w == portraitSize, h == portraitSize else { fail("초상이 192² 가 아니다: \(path)") }
    let px = bytes(source, space: sRGB)
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
    var S = P
    for ch in 0..<3 {
        var v = (0..<n).map { P[$0][ch] }
        inpaint(&v, known: core, width: w, height: h, relax: 30)
        for i in 0..<n { S[i][ch] = v[i] }
    }
    func clamped(_ c: SIMD3<Double>) -> SIMD3<Double> { simd_clamp(c, SIMD3(repeating: 0), SIMD3(repeating: 255)) }
    var coreL = (0..<n).filter { core[$0] }.map { i -> Double in let c = clamped(P[i]); return labOf(c.x, c.y, c.z).x }
    var coreY = (0..<n).filter { core[$0] }.map { i -> Double in let c = clamped(P[i]); return lumaLinear(srgbBytesToLinear(c.x, c.y, c.z)) }
    coreL.sort(); coreY.sort()
    var bx0 = w, bx1 = -1, by0 = h, by1 = -1
    for y in 0..<h { for x in 0..<w where A[y * w + x] > 0.5 { bx0 = min(bx0, x); bx1 = max(bx1, x); by0 = min(by0, y); by1 = max(by1, y) } }
    var nearRim = [Bool](repeating: false, count: n)
    for y in 0..<h { for x in 0..<w where A[y * w + x] < 0.5 {
        for yy in max(0, y - rimRadius)...min(h - 1, y + rimRadius) { for xx in max(0, x - rimRadius)...min(w - 1, x + rimRadius) { nearRim[yy * w + xx] = true } }
    } }
    return PortraitSource(label: label, w: w, h: h, px: px, P: P, A: A, core: core, S: S, K: blushSum / blushCount,
                          lRef: coreL[coreL.count / 2], yRef: coreY[coreY.count / 2], box: (bx0, bx1, by0, by1), nearRim: nearRim)
}

/// 선형 프리멀티 RGBA 장(Float — 큰 지도용).
struct PremulField {
    let w: Int, h: Int
    var v: [SIMD4<Float>]
    init(_ image: CGImage) {
        w = image.width; h = image.height
        let px = bytes(image, space: sRGB)
        v = (0..<(w * h)).map { i in
            let a = Double(px[i * 4 + 3]) / 255
            guard a > 0 else { return .zero }
            let c = srgbBytesToLinear(Double(px[i * 4]) / a, Double(px[i * 4 + 1]) / a, Double(px[i * 4 + 2]) / a) * a
            return SIMD4(Float(c.x), Float(c.y), Float(c.z), Float(a))
        }
    }
    /// 이중선형(밖은 0).
    func sample(_ x: Double, _ y: Double) -> SIMD4<Float> {
        let fx = x - 0.5, fy = y - 0.5
        let ix = Int(floor(fx)), iy = Int(floor(fy))
        let ax = Float(fx - Double(ix)), ay = Float(fy - Double(iy))
        var out = SIMD4<Float>.zero
        for (dx, dy, wgt) in [(0, 0, (1 - ax) * (1 - ay)), (1, 0, ax * (1 - ay)), (0, 1, (1 - ax) * ay), (1, 1, ax * ay)] {
            let xx = ix + dx, yy = iy + dy
            guard xx >= 0, yy >= 0, xx < w, yy < h else { continue }
            out += v[yy * w + xx] * wgt
        }
        return out
    }
}

/// 초상용 3D 지도 한 벌(같은 초상 카메라 자리): 몸 무늬 지도(몸 밖은 안에서 번져 채움) · 장식 지도(시야 2배 · 2배 크기 — 화소 크기가 같아
/// 장식 좌표 = 넓힌 좌표 − pad). 몸 상자 = 무늬 지도의 알파 > 127 상자.
struct PortraitMaps {
    let pattern: [SIMD3<Double>]   // 딸기: OKLab(dL = 0 무늬) · 초코: 선형 rgb(밝기 배율 1 의 케이크 색)
    let box: (Double, Double, Double, Double)   // gx0, gw, gy0, gh
    let decor: PremulField
    let pad: Int
    let decorBox: (Int, Int, Int, Int)          // 장식 지도 알파 > 0 상자(넓힌 좌표)

    func samplePattern(_ x: Double, _ y: Double) -> SIMD3<Double> {
        let fx = min(max(x - 0.5, 0), Double(mapSize - 1)), fy = min(max(y - 0.5, 0), Double(mapSize - 1))
        let ix = min(Int(fx), mapSize - 2), iy = min(Int(fy), mapSize - 2)
        let ax = fx - Double(ix), ay = fy - Double(iy)
        let a = pattern[iy * mapSize + ix], b = pattern[iy * mapSize + ix + 1], c = pattern[(iy + 1) * mapSize + ix], d = pattern[(iy + 1) * mapSize + ix + 1]
        return (a * (1 - ax) + b * ax) * (1 - ay) + (c * (1 - ax) + d * ax) * ay
    }
}

func renderPortraitMaps(_ kind: CakeKind, assets: BodyAssets) -> PortraitMaps {
    let patternRig = makeRig(.patternMap(kind), decor: nil, assets: assets)
    let image = snapshot(patternRig, camera: portraitCamera(patternRig, fill: kind.portraitFill), size: mapSize)
    let px = bytes(image, space: sRGB)
    let n = mapSize * mapSize
    var ch = [[Double]](repeating: [Double](repeating: 0, count: n), count: 3)
    var known = [Bool](repeating: false, count: n)
    for i in 0..<n where px[i * 4 + 3] == 255 {
        let r = Double(px[i * 4]), g = Double(px[i * 4 + 1]), b = Double(px[i * 4 + 2])
        let v = kind == .strawberry ? labOf(r, g, b) : srgbBytesToLinear(r, g, b)
        ch[0][i] = v.x; ch[1][i] = v.y; ch[2][i] = v.z; known[i] = true
    }
    for c in 0..<3 { inpaint(&ch[c], known: known, width: mapSize, height: mapSize, relax: 0) }
    guard let g = alphaBox(px, mapSize, mapSize, threshold: 127) else { fail("무늬 지도가 비었다") }
    let decorRig = makeRig(.depthOnly, decor: kind, assets: assets)
    let pad = mapSize / 2, wide = mapSize + pad * 2
    let decorImage = snapshot(decorRig, camera: portraitCamera(decorRig, fill: kind.portraitFill, widen: 2), size: wide)
    let dpx = bytes(decorImage, space: sRGB)
    guard let dbox = alphaBox(dpx, wide, wide, threshold: 0) else { fail("장식 지도가 비었다") }
    guard dbox.0 > 2, dbox.2 > 2, dbox.1 < wide - 3, dbox.3 < wide - 3 else { fail("\(kind.label) 장식이 넓힌 지도에서도 잘린다") }
    return PortraitMaps(pattern: (0..<n).map { SIMD3(ch[0][$0], ch[1][$0], ch[2][$0]) },
                        box: (Double(g.0), Double(g.1 - g.0 + 1), Double(g.2), Double(g.3 - g.2 + 1)),
                        decor: PremulField(decorImage), pad: pad, decorBox: dbox)
}

/// 2D 좌표 ↔ 지도 좌표(몸 상자끼리 맞춤).
struct BoxMap {
    let bx0: Double, bw: Double, by0: Double, bh: Double   // 2D 몸 상자
    let gx0: Double, gw: Double, gy0: Double, gh: Double   // 지도 몸 상자
    func toMap(_ x: Double, _ y: Double) -> (Double, Double) { (gx0 + (x - bx0) / bw * gw, gy0 + (y - by0) / bh * gh) }
    func toPortrait(_ x: Double, _ y: Double) -> (Double, Double) { (bx0 + (x - gx0) / gw * bw, by0 + (y - gy0) / gh * bh) }
}

struct PreparedPortrait {
    let kind: CakeKind
    let expression: String
    let body: CGImage             // 192² 다시 칠한 2D 몸(0.88 축소 전)
    let map: BoxMap
    let maps: PortraitMaps
    let union: (Double, Double, Double, Double)   // 2D 좌표의 몸 ∪ 장식 상자(x0 x1 y0 y1)
    let bodyCenter: (Double, Double)
}

/// 2D 몸의 피부만 케이크로(금 · 무지개 초상과 같은 β 틀): out = P + β·(케이크 − S). 케이크 색 = 무늬 지도를 몸 상자끼리 맞춰 읽고,
/// 밝기는 그 자리 2D 피부 S 의 밝기 차(딸기: OKLab L 차 → StrawberryBody.applyShade · 초코: 선형 휘도 비).
func preparePortrait(_ kind: CakeKind, expression: String, source src: PortraitSource, maps: PortraitMaps) -> PreparedPortrait {
    let w = src.w, h = src.h, n = w * h
    let b = src.box
    let map = BoxMap(bx0: Double(b.0), bw: Double(b.1 - b.0 + 1), by0: Double(b.2), bh: Double(b.3 - b.2 + 1),
                     gx0: maps.box.0, gw: maps.box.1, gy0: maps.box.2, gh: maps.box.3)
    var out = [UInt8](repeating: 0, count: n * 4)
    for y in 0..<h { for x in 0..<w where src.A[y * w + x] > 0 {
        let i = y * w + x
        let s = src.S[i]
        let (mx, my) = map.toMap(Double(x) + 0.5, Double(y) + 0.5)
        let v = maps.samplePattern(mx, my)
        let sc = simd_clamp(s, SIMD3(repeating: 0), SIMD3(repeating: 255))
        let G: SIMD3<Double>
        switch kind {
        case .strawberry:
            let (r, g, bb) = linearToBytes(StrawberryBody.applyShade(v, dL: labOf(sc.x, sc.y, sc.z).x - src.lRef))
            G = SIMD3(Double(r), Double(g), Double(bb))
        case .choco:
            let shade = pow(min(max(lumaLinear(srgbBytesToLinear(sc.x, sc.y, sc.z)) / src.yRef, 0.40), 1.45), ChocoBody.shadeGamma)
            let gl = simd_clamp(v * shade, SIMD3(repeating: 0), SIMD3(repeating: 1))
            G = SIMD3(Double(toByte(gl.x)), Double(toByte(gl.y)), Double(toByte(gl.z)))
        }
        let beta = (src.core[i] || src.A[i] < 0.98) ? 1 : skinFraction(src.P[i], s, src.K, unmix: !src.nearRim[i])
        let o = simd_clamp(src.P[i] + beta * (G - s), SIMD3(repeating: 0), SIMD3(repeating: 255))
        out[i * 4] = UInt8((o.x * src.A[i]).rounded()); out[i * 4 + 1] = UInt8((o.y * src.A[i]).rounded())
        out[i * 4 + 2] = UInt8((o.z * src.A[i]).rounded()); out[i * 4 + 3] = src.px[i * 4 + 3]
    } }
    let d = maps.decorBox
    let (dx0, dy0) = map.toPortrait(Double(d.0 - maps.pad), Double(d.2 - maps.pad))
    let (dx1, dy1) = map.toPortrait(Double(d.1 + 1 - maps.pad), Double(d.3 + 1 - maps.pad))
    let union = (min(Double(b.0), dx0), max(Double(b.1 + 1), dx1), min(Double(b.2), dy0), max(Double(b.3 + 1), dy1))
    return PreparedPortrait(kind: kind, expression: expression, body: makeImage(out, w, h), map: map, maps: maps, union: union,
                            bodyCenter: ((Double(b.0) + Double(b.1 + 1)) / 2, (Double(b.2) + Double(b.3 + 1)) / 2))
}

/// 네 장 같은 배치: 몸 상자 가운데를 (96, centerY) 에, 배율 k. 네 장 모두의 몸 ∪ 장식이 여백 안에 들게 k(0.88 상한)와 centerY 를 정한다.
func commonLayout(_ all: [PreparedPortrait]) -> (k: Double, centerY: Double) {
    let side = Double(portraitSize), avail = side - 2 * portraitMargin
    var up = 0.0, down = 0.0, half = 0.0   // 몸 가운데에서 잰 2D 거리(위 · 아래 · 좌우 최대)
    for p in all {
        up = max(up, p.bodyCenter.1 - p.union.2); down = max(down, p.union.3 - p.bodyCenter.1)
        half = max(half, p.bodyCenter.0 - p.union.0, p.union.1 - p.bodyCenter.0)
    }
    let k = min(portraitBodyScale, avail / (up + down), avail / (2 * half))
    let centerY = portraitMargin + up * k + (avail - (up + down) * k) / 2
    return (k, centerY)
}

/// 가우스 흐림(분리형, 가장자리 0 — 결정적 CPU).
func gaussianBlur(_ v: [Double], _ w: Int, _ h: Int, sigma: Double) -> [Double] {
    let r = max(1, Int(ceil(sigma * 3)))
    let kernel = (-r...r).map { exp(-Double($0 * $0) / (2 * sigma * sigma)) }
    let total = kernel.reduce(0, +)
    var tmp = [Double](repeating: 0, count: w * h), out = tmp
    for y in 0..<h { for x in 0..<w {
        var s = 0.0
        for k in -r...r where x + k >= 0 && x + k < w { s += v[y * w + x + k] * kernel[k + r] }
        tmp[y * w + x] = s / total
    } }
    for y in 0..<h { for x in 0..<w {
        var s = 0.0
        for k in -r...r where y + k >= 0 && y + k < h { s += tmp[(y + k) * w + x] * kernel[k + r] }
        out[y * w + x] = s / total
    } }
    return out
}

/// 최종 192²: 몸(2D, CG 고품질 축소 — 금 · 무지개와 같은 그리기) + 접촉 그늘 + 장식 층(가우스 초표본) — 선형 프리멀티로 겹친다.
func composePortrait(_ p: PreparedPortrait, layout: (k: Double, centerY: Double)) -> CGImage {
    let side = portraitSize, n = side * side
    let k = layout.k
    // 2D → 출력: X = 96 + (x − cx)·k, Y = centerY + (y − cy)·k (위가 0).
    let ox = Double(side) / 2 - p.bodyCenter.0 * k, oy = layout.centerY - p.bodyCenter.1 * k
    let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.draw(p.body, in: CGRect(x: ox, y: Double(side) - (oy + Double(p.body.height) * k), width: Double(p.body.width) * k, height: Double(p.body.height) * k))
    let bodyPx = bytes(ctx.makeImage()!, space: sRGB)
    // 장식 층: 출력 화소마다 6×6 표본(±1.5σ 안, 가우스 무게)으로 장식 지도를 읽는다.
    var decor = [SIMD4<Double>](repeating: .zero, count: n)
    let grid = 6, reach = 1.5 * decorSoftSigma + 0.5
    var taps = [(Double, Double, Double)]()
    for j in 0..<grid { for i in 0..<grid {
        let dx = (Double(i) + 0.5) / Double(grid) * 2 * reach - reach, dy = (Double(j) + 0.5) / Double(grid) * 2 * reach - reach
        taps.append((dx, dy, exp(-(dx * dx + dy * dy) / (2 * decorSoftSigma * decorSoftSigma))))
    } }
    let tapTotal = taps.reduce(0) { $0 + $1.2 }
    for y in 0..<side { for x in 0..<side {
        var acc = SIMD4<Double>.zero
        for (dx, dy, wgt) in taps {
            let px2 = (Double(x) + 0.5 + dx - ox) / k, py2 = (Double(y) + 0.5 + dy - oy) / k
            let (mx, my) = p.map.toMap(px2, py2)
            let s = p.maps.decor.sample(mx + Double(p.maps.pad), my + Double(p.maps.pad))
            acc += SIMD4(Double(s.x), Double(s.y), Double(s.z), Double(s.w)) * wgt
        }
        decor[y * side + x] = acc / tapTotal
    } }
    // 접촉 그늘: 장식 알파를 오른쪽 아래로 밀어 흐린 것 × 몸(장식이 덮지 않은 자리).
    var shifted = [Double](repeating: 0, count: n)
    for y in 0..<side { for x in 0..<side {
        let sx = Double(x) - contactShadowOffset.x, sy = Double(y) - contactShadowOffset.y
        let ix = Int(floor(sx)), iy = Int(floor(sy)), ax = sx - Double(ix), ay = sy - Double(iy)
        var a = 0.0
        for (dx, dy, wgt) in [(0, 0, (1 - ax) * (1 - ay)), (1, 0, ax * (1 - ay)), (0, 1, (1 - ax) * ay), (1, 1, ax * ay)] {
            let xx = ix + dx, yy = iy + dy
            guard xx >= 0, yy >= 0, xx < side, yy < side else { continue }
            a += decor[yy * side + xx].w * wgt
        }
        shifted[y * side + x] = a
    } }
    let shadow = gaussianBlur(shifted, side, side, sigma: contactShadowSigma)
    var out = [UInt8](repeating: 0, count: n * 4)
    for i in 0..<n {
        let ba = Double(bodyPx[i * 4 + 3]) / 255
        var body = SIMD4<Double>.zero
        if ba > 0 {
            let c = srgbBytesToLinear(Double(bodyPx[i * 4]) / ba, Double(bodyPx[i * 4 + 1]) / ba, Double(bodyPx[i * 4 + 2]) / ba)
            let dim = 1 - contactShadowStrength * min(shadow[i], 1)
            body = SIMD4(c.x * dim * ba, c.y * dim * ba, c.z * dim * ba, ba)
        }
        let d = decor[i]
        let c = SIMD4(d.x, d.y, d.z, d.w) + body * (1 - d.w)
        guard c.w > 1e-6 else { continue }
        let un = SIMD3(c.x, c.y, c.z) / c.w
        let a = min(c.w, 1)
        out[i * 4] = UInt8((Double(toByte(un.x)) * a).rounded()); out[i * 4 + 1] = UInt8((Double(toByte(un.y)) * a).rounded())
        out[i * 4 + 2] = UInt8((Double(toByte(un.z)) * a).rounded()); out[i * 4 + 3] = UInt8((a * 255).rounded())
    }
    let image = makeImage(out, side, side)
    var border = 0
    for y in 0..<side { for x in 0..<side where x < 2 || y < 2 || x >= side - 2 || y >= side - 2 { border = max(border, Int(out[(y * side + x) * 4 + 3])) } }
    guard Double(border) / 255 <= borderAlphaLimit else { fail("\(p.kind.label) \(p.expression) 테두리 알파 \(Double(border) / 255) > \(borderAlphaLimit)") }
    guard let box = alphaBox(out, side, side, threshold: 0) else { fail("빈 초상") }
    print(String(format: "[portrait] %@ %@: 몸 배율 %.3f(0.88 상한) · 알파 상자 x %d–%d y %d–%d · 테두리 2px 최대 알파 %.3f",
                 p.kind.label, p.expression, k, box.0, box.1, box.2, box.3, Double(border) / 255))
    return image
}

// MARK: - 미리보기(--preview, 저장소 밖)

func writePreview(_ kind: CakeKind, assets: BodyAssets, into dir: String) {
    let rig = makeRig(.cake(kind), decor: kind, assets: assets)
    // 앱과 같은 자리 · 방향에 시야만 50° 로 넓혀 굽고(장식이 앱 40° 화면 밖으로 나가는지 잰다), 몸 + 장식 상자 둘레로 잘라 512².
    let renderFOV: CGFloat = 50, side = 1280
    let frameFraction = Double(tan(20 * Double.pi / 180) / tan(Double(renderFOV) / 2 * .pi / 180))
    var shots: [(String, CGImage)] = []
    var union: (Int, Int, Int, Int)?
    for (name, yaw) in [("front", 0.0), ("three-quarter", 35.0), ("back", 180.0)] {
        let shot = snapshot(rig, camera: appCamera(rig, fov: renderFOV), size: side, yawDegrees: yaw)
        guard let b = alphaBox(bytes(shot, space: sRGB), side, side, threshold: 8) else { fail("빈 미리보기") }
        let half = Double(side) / 2
        let appTop = ((Double(b.2) - half) / frameFraction + half) / Double(side)
        print(String(format: "[frame] %@ %@: 앱 40° 화면에서 몸 + 장식 위 끝 %.3f(프레임 높이 비율, 0 = 위 가장자리)", kind.label, name, appTop))
        union = union.map { (min($0.0, b.0), max($0.1, b.1), min($0.2, b.2), max($0.3, b.3)) } ?? b
        shots.append((name, shot))
    }
    // 부유 애니메이션 꼭대기(+0.07, 앱 CheckCharacter3DScene 의 부유 진폭)에서 같은 잼.
    rig.facing.parent?.simdPosition = SIMD3(0, 0.07, 0)
    let floated = snapshot(rig, camera: appCamera(rig, fov: renderFOV), size: side)
    rig.facing.parent?.simdPosition = .zero
    if let b = alphaBox(bytes(floated, space: sRGB), side, side, threshold: 8) {
        let half = Double(side) / 2
        print(String(format: "[frame] %@ front 부유 +0.07: 앱 40° 화면에서 몸 + 장식 위 끝 %.3f(음수면 위로 잘린다)", kind.label,
                     ((Double(b.2) - half) / frameFraction + half) / Double(side)))
    }
    guard let u = union else { return }
    let crop = Double(max(u.1 - u.0, u.3 - u.2)) * 1.08
    let cx = Double(u.0 + u.1) / 2, cy = Double(u.2 + u.3) / 2
    for (name, shot) in shots {
        let ctx = CGContext(data: nil, width: 512, height: 512, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.interpolationQuality = .high
        let k = 512 / crop
        ctx.draw(shot, in: CGRect(x: -(cx - crop / 2) * k, y: -(Double(side) - (cy + crop / 2)) * k, width: Double(side) * k, height: Double(side) * k))
        writePNG(ctx.makeImage()!, toPath: "\(dir)/\(kind.id)-\(name).png")
    }
    // 눈 확대: 같은 정면을 크게 굽고 두 눈 둘레만 잘라(테 확인용).
    let big = snapshot(rig, camera: appCamera(rig, fov: 40), size: 2048)
    if let eyes = big.cropping(to: CGRect(x: 560, y: 560, width: 930, height: 330)) { writePNG(eyes, toPath: "\(dir)/\(kind.id)-eyes.png") }
    let archive = SCNScene()
    archive.rootNode.addChildNode(kind.decor(meshSurfaceProbe(rig.bodyNode)))
    _ = archive.write(to: URL(fileURLWithPath: "\(dir)/\(kind.id)-decor.scn"), options: nil, delegate: nil, progressHandler: nil)
}

// MARK: - 실행

var args = Array(CommandLine.arguments.dropFirst())
while !args.isEmpty {
    let flag = args.removeFirst()
    guard args.first != nil else { fail("사용: [--out <폴더>] [--preview <폴더>]") }
    switch flag {
    case "--out": outRoot = args.removeFirst()
    case "--preview": previewDir = args.removeFirst()
    default: fail("모르는 인자: \(flag)")
    }
}
guard FileManager.default.fileExists(atPath: modelPath) else { fail("저장소 루트에서 실행하라(\(modelPath) 없음)") }

let started = Date()
let assets = loadBodyAssets()
print(String(format: "[body] 초코 기준 휘도 %.5f(상수 %.5f) · 볼터치 K %.2f,%.2f,%.2f(상수 %.2f,%.2f,%.2f)", assets.skinYRef, chocoSkinYRef,
             assets.blush.x, assets.blush.y, assets.blush.z, chocoBlushSRGB.x, chocoBlushSRGB.y, chocoBlushSRGB.z))
guard abs(assets.skinYRef - chocoSkinYRef) < 5e-6 else { fail("초코 기준 휘도가 상수와 다르다 — chocoSkinYRef 를 고치고 앱 상수도 같이") }
guard simd_reduce_max(simd_abs(assets.blush - chocoBlushSRGB)) < 5e-3 else { fail("초코 볼터치 K 가 상수와 다르다 — chocoBlushSRGB 를 고치고 앱 상수도 같이") }

// 장식 꼭대기 · 만들기 비용(앱 프레이밍 · 캐시 판단 근거).
do {
    let rig = makeRig(.depthOnly, decor: nil, assets: assets)
    let probe = meshSurfaceProbe(rig.bodyNode)
    let tops = [(CakeKind.strawberry, StrawberryDecor.flameTopY(probe: probe), strawberryFlameTopY),
                (CakeKind.choco, ChocoDecor.flameTopY(probe: probe), chocoFlameTopY)]
    for (kind, measured, constant) in tops {
        let t0 = Date()
        let node = kind.decor(probe)
        let cost = Date().timeIntervalSince(t0)
        let (lo, hi) = node.boundingBox
        print(String(format: "[decor] %@: 불꽃 끝 y %.4f(상수 %.4f) · 장식 상자 y %.3f–%.3f(빛 번짐 판 포함) · 만들기 %.3f초",
                     kind.label, measured, constant, Double(lo.y), Double(hi.y), cost))
    }
    for (kind, measured, constant) in tops where abs(measured - constant) >= 5e-4 {
        fail("\(kind.label) 불꽃 끝 높이가 상수와 다르다 — 상수를 고치고 앱 프레이밍도 같이")
    }
}

let sources = Dictionary(uniqueKeysWithValues: expressions.map { ($0, analyzePortrait("\(resourceDir)/aing-\($0).png", label: $0)) })
var prepared: [PreparedPortrait] = []
for kind in CakeKind.allCases {
    let maps = renderPortraitMaps(kind, assets: assets)
    for e in expressions { prepared.append(preparePortrait(kind, expression: e, source: sources[e]!, maps: maps)) }
}
let layout = commonLayout(prepared)
for p in prepared {
    let mac = "\(resourceDir)/\(p.kind.id)-\(p.expression).png"
    writePNG(composePortrait(p, layout: layout), toPath: "\(outRoot)/\(mac)")
    let phone = "\(outRoot)/\(phonePortraitDir)/\(p.kind.id)-\(p.expression).png"
    try? FileManager.default.createDirectory(atPath: "\(outRoot)/\(phonePortraitDir)", withIntermediateDirectories: true)
    try? FileManager.default.removeItem(atPath: phone)
    do { try FileManager.default.copyItem(atPath: "\(outRoot)/\(mac)", toPath: phone) } catch { fail("폰 사본 실패: \(error)") }
}
if let previewDir {
    for kind in CakeKind.allCases { writePreview(kind, assets: assets, into: previewDir) }
    print("[preview] \(previewDir)")
}
print(String(format: "[done] 초상 %d장(맥 %d + 폰 사본 %d) — %.1f초", prepared.count * 2, prepared.count, prepared.count, Date().timeIntervalSince(started)))
