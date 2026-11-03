#!/usr/bin/env swift
// 이슬 아잉이(aing_isul — '술 한잔' 선물 전용, 초록 소주병 스킨) 그림 생성기 — 맥 초상 둘 + 라벨 텍스처 폴백을 굽고,
// 앱 3D 마감(맥 IsulAingFinish)이 그대로 옮겨 쓸 **몸 셰이더 · 병뚜껑 장식 코드**를 표시 구획(BEGIN/END)으로 담는다.
// 대표가 고른 시안 R(3차 '초록 글씨 라벨': 초록 유리 몸 + 반사 + 흰 곡선 라벨 — 초록 붓글씨 '참이슬' · 파란 이슬방울 · '아잉 에디션' +
// 정수리에 비스듬한 초록 병뚜껑)을 그대로 옮겼다(시안 렌더러 isul-aing/render.swift 의 h3("R", …) 갈래 · drafts3/R-*.png).
// 모양 · 색 · 자리 숫자는 시안 그대로이고 아래 '고친 것' 둘만 다르다.
//
// 사용법(저장소 루트에서):
//   swift -O scripts/make-isul-aing.swift                    산출물 3장을 저장소 Sources/check/Resources 에 쓴다. 같은 입력이면 같은 바이트.
//   swift -O scripts/make-isul-aing.swift --out <폴더>       같은 3장을 <폴더> 바로 아래에 쓴다(저장소는 안 건드린다 — 결정성 검사용).
//   swift -O scripts/make-isul-aing.swift --preview <폴더>   산출물에 더해 앱 구도 3D 참고 렌더(정면 · 3/4 · 뒤 512², 눈가 4배 크롭 고침 전후,
//                                                            초상 4배)를 <폴더>에 쓴다 — 저장소 밖에 둔다. --out 과 같이 쓸 수 있다.
//   오프스크린 SCNRenderer(Metal) · CoreGraphics · CoreText 만 쓴다 — 화면에 창을 띄우지 않고 네트워크를 쓰지 않는다.
//   라벨 글꼴 '나눔손글씨 붓'(Nanum Brush Script, macOS 내려받기 글꼴)이 없으면 **멈춘다**(다른 글꼴로 바꾸지 않는다 — 바이트가 달라진다).
//
// 입력(저장소, 읽기만): Sources/check/Resources/aing.scn(메시 · UV · 512² 라벤더 디퓨즈) · aing_rainbow-shade.png(무지개 생성기 산출 —
//   라벤더 밝기 맵, 케이크 · 이슬이 같이 쓴다) · aing-neutral.png · aing-negative.png(192² 아잉 초상)
// 출력(전부 커밋, 폰 사본은 만들지 않는다 — 맥 먼저):
//   aing_isul-neutral.png    192×192 RGBA 초상(아잉 초상의 피부만 초록 유리 + 라벨로 재색 + 3D 병뚜껑 층, 후광 없음)
//   aing_isul-negative.png   〃 (시무룩 — aing-negative.png 원본에서). 두 장은 같은 몸 배율 · 같은 몸 자리(상점 · 선택 창에 나란히 놓여도 맞는다).
//   aing_isul-label.png      라벨 텍스처 폴백(1200×551, 프리멀티 아님 PNG). 가로 = 둘레각 θ ∈ [−labelHalfWidth, +labelHalfWidth](정면 0),
//                            세로 = 높이 t ∈ [labelT0, labelT1](정수리 0 → 바닥 1, 그림 위 = labelT0). 범위 밖은 투명(표본기 clamp_to_zero).
//
// 고친 것(시안 known_issues):
//  ① 눈썹(속눈썹) · 입꼬리 짙은 초록 잔티 1–2px — 시안 셰이더는 피부 비율 β 를 sRGB 0–255 에서 재고(케이크 초코 식 그대로) 섞기는 **선형**에서
//     했다(출력 = P_lin + β·(유리 − S_lin)). 눈꺼풀 · 입 테처럼 짙은 색과 라벤더가 섞인 텍셀은 sRGB 에서 잰 덮임 a 가 선형 덮임보다 작아
//     β = 1 − a 가 크다 → 라벤더 S 를 지나치게 빼서 빨강 · 파랑 채널이 0 밑으로 잘리고 초록만 남는다(짙은 순초록 테). 텍스처 확대(쌍선형 —
//     선형 공간 보간)가 그 텍셀을 화면 1–2px 로 넓힌다. 고침(`IsulBody.bodyOutput`): β 는 같은 식 그대로 두고 섞기를 β 를 잰 sRGB 공간에서 한다
//     (출력 = sRGB⁻¹(P_e + β·(유리_e − S_e))). 피부 텍셀(P = S)은 전과 같고, 섞인 텍셀은 (1 − a)·유리 + a·F — 2D 초상과 같은 식이다.
//     --preview 의 eyes-4x-before/after 가 같은 파이프라인에서 섞기만 바꾼 두 그림이다.
//  ② 초상의 눈 둘레 라벤더 테 — 시안 초상은 옛 β(볼터치 선 위면 그 비율, 아니면 1 − |P − S|/80)였다. 케이크 생성기 ①의 풀기 식(`skinFraction` —
//     셰이더 ckBeta 와 같은 식)으로 바꿨다. 실루엣 가장자리 띠(`rimRadius` px)는 옛 식 그대로(테두리 빛을 흰 장식으로 오인하지 않게).
//  ③ 초상 볼터치 가운데 흙빛 — 아잉 초상의 볼터치 한가운데는 평균 볼터치색 K 보다 진한 분홍이라(K 방향 덮임 a > 1.1) 시안 β 의 볼터치 판정(a < 1.1)을
//     벗어나 옛 식 β ≈ 0.4 로 유리 초록이 섞였다(도넛 모양 볼). 초상만 'K 방향 그대로 더 간 텍셀(잔차 ≤ 20, a ≥ 1.1) = 온전한 볼터치 → β 0' 으로 고쳤다.
//     3D 셰이더는 디퓨즈 볼터치가 그 범위에 들어 그대로 둔다(정면 렌더 볼은 고른 분홍).
//
// ── 앱이 할 일(맥 3D, IsulAingFinish.swift) — 아래 이름을 그대로 옮긴다 ─────────────────────────────────────────────────────────────
// 1) 디퓨즈 합성: 무지개 · 케이크와 같다 — 텍셀마다 isGoldSkin(원본) ? aing_rainbow-shade.png[텍셀] : 원본(`GoldAingFinish.compositeImage`).
//    감은 눈은 라벤더 원본에서 먼저 굽고 같은 합성을 한다(무지개 `closedEyesImage` 순서) — 셰이더는 '표본한 디퓨즈'를 읽으니 깜빡임 · 졸기 ·
//    울트라 교체로 디퓨즈가 바뀌어도 따라온다.
// 2) 몸 셰이더(얼굴 재질 — 큰 CGImage 디퓨즈 재질, lightingModel .constant): `IsulBody.shaderModifiers`(geometry + fragment) +
//    셰이더 인자 둘 — `material.setValue(SCNMaterialProperty(contents: <aing_rainbow-shade CGImage>), forKey: IsulBody.shadeMapKey)`,
//    `material.setValue(<라벨 CGImage 의 SCNMaterialProperty, mipFilter .linear>, forKey: IsulBody.labelMapKey)`.
//    ★ unlit 에서 `_surface.view` 는 0 이다 — 시선은 geometry 단계 varying(ckVE = modelView · position)으로 넘긴다(구획 그대로).
//    ★ 몸 색은 물체 좌표(ckVP)로 정한다 — 메시 UV 섬 경계에 점이 서는 함정(무지개)이 없다. 라벨도 (θ, t) 로 읽는다(UV 안 씀).
//    상수 `IsulBody.skinYRef` · `blushSRGB` 는 케이크 `chocoSkinYRef` · `chocoBlushSRGB` 와 같은 값(같은 합성 디퓨즈)이고 이 스크립트가 다시 잰다.
// 3) 라벨 그림: 디스크 캐시 → 번들 폴백(aing_isul-label.png) → 조건부 요청(설계서 §6 '굽지 않기'). 셰이더는 (θ, t) 범위 상수
//    `labelHalfWidth` · `labelT0` · `labelT1` 로 읽으니 그림 가로세로 비가 달라도 깨지지 않는다(늘어날 뿐). 빈 그림이면 라벨 없는 유리 병.
// 4) 장식: `IsulCap.make(probe:)` → 이름 `IsulCap.decorNodeName`("check.isulDecor") 노드 하나(자식 `check.isul.cap`). **캐릭터 노드
//    (aing.scn 메시 노드 — 변환이 단위라 물체 좌표 = 이 노드 좌표)의 자식**으로 붙인다 → 부유 · 살랑 · 요 회전을 따른다.
//    probe = 케이크 `meshSurfaceProbe(bodyNode)` 그대로(법선 방향은 make 가 위로 뒤집는다). 프레이밍 카메라를 **몸만** 보고 세운 뒤 붙인다.
//    재질은 .constant(음영을 작은 텍스처에 구웠다 — 몸 공간 고정 빛). 얼굴 탐색 · 몸 클릭 hitTest · 리액션 진폭(bodyBoundingBox)에서
//    `decorNodeName` 노드 **아래 전부**를 뺀다(케이크 isDecor 와 같은 자리). 만들기 비용은 --preview 의 [decor] 줄(프로세스당 한 번 만들어 clone).
// 5) 프레이밍: 뚜껑 꼭대기(물체 좌표 y) `IsulCap.capTopY`. 앱 카메라가 이 높이 + 부유 0.07 까지 안 자르게 — --preview 의 [frame] 줄이
//    지금 앱 카메라(몸만 보고 잡은 40°) 화면 위 여백을 프레임 높이 비율로 보여 준다(부유 0 · +0.07).
// 6) 초상 파일 이름은 `<id>-<neutral|negative>.png`(금 · 무지개 · 케이크 규약). 폰 `AingCharacterArt.knownIDs` 에는 이번에 넣지 않는다.
//
// 이 스크립트는 앱 모듈을 링크하지 않는다. isGoldSkin · 합성 · 몸 좌표 상수를 여기 한 번 더 적는다 — 앱 쪽이 바뀌면 여기도 같이.

import AppKit
import SceneKit
import simd

// MARK: - 상수(생성기 전용)

let resourceDir = "Sources/check/Resources"
let modelPath = "\(resourceDir)/aing.scn"
let shadePath = "\(resourceDir)/aing_rainbow-shade.png"
let characterID = "aing_isul"
let expressions = ["neutral", "negative"]

let labelFontFamily = "Nanum Brush Script"
let labelText = "참이슬"
let labelSub = "아잉 에디션"
let labelInk = SIMD3<Double>(0.04, 0.33, 0.17)      // 글자색(sRGB 0–1) — 시안 R '초록 글씨'
let labelAccent = SIMD3<Double>(0.10, 0.56, 0.30)   // 위 두 줄 · 작은 글자
let labelWidth = 1200

let viewSize = 512
let renderScale = 2
let cropX0 = 0.14, cropY0 = 0.0, cropSide = 0.72
let threeQuarterYaw = 35.0
let floatLift: Float = 0.07                          // 앱 부유 최대 높이(프레이밍 점검)
let portraitSize = 192
let portraitBodyScale = 0.88
let portraitMargin = 5.0
let portraitMapSize = 384
let borderAlphaLimit = 0.04
let rimRadius = 5

var outDir = resourceDir
var previewDir: String?

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(("make-isul-aing: " + message + "\n").data(using: .utf8)!)
    exit(1)
}

// MARK: - 그림 도구

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func loadImage(_ path: String) -> CGImage {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fail("그림을 못 읽었다: \(path)") }
    return image
}

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
    print("썼다: \(path) \(image.width)x\(image.height)")
}

func resized(_ image: CGImage, _ w: Int, _ h: Int, nearest: Bool = false) -> CGImage {
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = nearest ? .none : .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    return ctx.makeImage()!
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

/// 앱 `GoldAingArt.isGoldSkin` 과 같은 피부 판정(라벤더).
@inline(__always) func isGoldSkin(_ r: Int, _ g: Int, _ b: Int) -> Bool {
    let (hue, sat, l) = hueSatLum(Double(r), Double(g), Double(b))
    return hue >= 215 && hue <= 300 && sat > 0.05 && sat < 0.75 && l > 0.10
}

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

@inline(__always) func srgbToLinear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
@inline(__always) func linearToSrgb(_ v: Double) -> Double { v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1 / 2.4) - 0.055 }
func linB(_ r: Double, _ g: Double, _ b: Double) -> SIMD3<Double> { SIMD3(srgbToLinear(r / 255), srgbToLinear(g / 255), srgbToLinear(b / 255)) }
func lumaLinear(_ c: SIMD3<Double>) -> Double { 0.2126 * c.x + 0.7152 * c.y + 0.0722 * c.z }
func linearToBytes(_ c: SIMD3<Double>) -> (UInt8, UInt8, UInt8) {
    func q(_ v: Double) -> UInt8 { UInt8(max(0, min(255, (linearToSrgb(min(max(v, 0), 1)) * 255).rounded()))) }
    return (q(c.x), q(c.y), q(c.z))
}
func smoothstep(_ e0: Double, _ e1: Double, _ x: Double) -> Double { let t = min(max((x - e0) / (e1 - e0), 0), 1); return t * t * (3 - 2 * t) }

// BEGIN isul-body-shader — 앱 IsulAingFinish 가 이 구획을 글자 그대로 옮긴다(시험이 주석 · 공백을 걷고 맞댄다). 여기를 고치면 앱도 같이.

/// 이슬 아잉이 몸 셰이더(시안 R). 틀은 케이크 초코(ChocoBody)와 같다: 디퓨즈 = 무지개 합성, 셰이더 인자 ckShadeMap(그 자리 피부 S),
/// 얼굴은 피부 비율 β(초코의 눈 테 풀기 식)로 원본을 지킨다. 몸 색 = 초록 유리(시선 의존 프레넬 · 굴절 초승달 · 바닥 코스틱) + 화면 공간
/// 반사 줄 + 흰 곡선 라벨(셰이더 인자 ckLabelMap 을 둘레각 θ · 높이 t 로 표본). 전부 물체 좌표 — 메시 UV 섬 점 함정이 없다.
/// aing.scn 에는 법선이 없어 몸을 감싼 타원체 기울기로 법선을 만들고, unlit 이라 시선은 geometry 단계 varying 으로 넘긴다.
enum IsulBody {
    // 몸 좌표(무지개 `RainbowAingArt` · 케이크와 같은 값 — 메시가 바뀌면 같이).
    static let bodyTop = 0.848950
    static let bodyHeight = 1.695736
    static let ellipsoid = SIMD3<Double>(0.6084, 0.7191, 0.5329)
    // 합성 디퓨즈 피부 텍셀 선형 휘도 중앙값 · 원본 디퓨즈 볼터치 평균(sRGB 0–255) — 케이크 chocoSkinYRef · chocoBlushSRGB 와 같다.
    static let skinYRef = 0.56530
    static let blushSRGB = SIMD3<Double>(245.62, 172.26, 200.68)
    static let shadeMapKey = "ckShadeMap"
    static let labelMapKey = "ckLabelMap"
    // 라벨 자리: 둘레각 θ ∈ [−halfWidth, +halfWidth](라디안, 정면 0) · 높이 t ∈ [t0, t1](정수리 0 → 바닥 1).
    static let labelHalfWidth = 1.00
    static let labelT0 = 0.475
    static let labelT1 = 0.800
    // 유리색(sRGB 16진): 가운데 · 중간 · 가장자리(두꺼운 유리) · 가장자리 밝은 테.
    static let glassCore = 0x5ED18C
    static let glassMid = 0x1E8E4E
    static let glassDeep = 0x094726
    static let glassRim = 0xB9F5CF
    static let glassEdgePow = 1.5
    static let glassShadeMix = 0.55

    static func f5(_ v: Double) -> String { String(format: "%.5f", v) }
    static func f5v(_ v: SIMD3<Double>) -> String { String(format: "float3(%.5f, %.5f, %.5f)", v.x, v.y, v.z) }
    static func toLinear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
    static func f5hex(_ hex: Int) -> String {
        f5v(SIMD3(toLinear(Double((hex >> 16) & 255) / 255), toLinear(Double((hex >> 8) & 255) / 255), toLinear(Double(hex & 255) / 255)))
    }

    static let geometry = """
    #pragma varyings
    float3 ckVP;
    float2 ckUV;
    float3 ckVN;
    float3 ckVE;
    #pragma body
    out.ckVP = _geometry.position.xyz;
    out.ckVE = (scn_node.modelViewTransform * float4(_geometry.position.xyz, 1.0)).xyz;
    out.ckUV = _geometry.texcoords[0];
    float3 ckG = (_geometry.position.xyz - float3(0.0, 0.001, 0.0)) / (\(f5v(ellipsoid)) * \(f5v(ellipsoid)));
    out.ckVN = (scn_node.normalTransform * float4(ckG, 0.0)).xyz;
    """

    /// 초록 유리 바탕: 가운데(시선과 마주한 면)는 밝은 초록, 가장자리로 갈수록 두꺼운 유리라 짙은 병 초록. 바닥은 짙고 그 위로 밝은 띠(코스틱).
    static let glass = """
    float ckFr = pow(1.0 - ckNV, \(f5(glassEdgePow)));
    float3 ckGlass = mix(\(f5hex(glassCore)), \(f5hex(glassMid)), smoothstep(0.0, 0.36, ckFr));
    ckGlass = mix(ckGlass, \(f5hex(glassDeep)), smoothstep(0.32, 0.95, ckFr));
    float ckCres = smoothstep(0.18, 0.40, ckNV) * (1.0 - smoothstep(0.45, 0.70, ckNV)) * smoothstep(-0.15, -0.65, ckVn.y + 0.35 * ckVn.x);
    ckGlass = mix(ckGlass, \(f5hex(glassCore)) * 1.15, ckCres * 0.55);
    float ckBottom = smoothstep(0.86, 0.985, ckT);
    ckGlass = mix(ckGlass, \(f5hex(glassDeep)), ckBottom * 0.55);
    float ckCaustic = (1.0 - smoothstep(0.0, 0.06, abs(ckT - 0.84))) * smoothstep(0.2, 0.7, ckNV);
    ckGlass += \(f5hex(glassCore)) * ckCaustic * 0.25;
    ckBase = ckGlass;
    ckShadeMix = \(f5(glassShadeMix));
    """

    /// 유리 반사: 화면 공간에 고정된 세로 반사 줄 셋 + 정수리 반짝 + 가장자리 밝은 테. 얼굴 위에서는 약하게.
    static let highlights = """
    float ckS1 = (1.0 - smoothstep(0.045, 0.085, abs(ckVn.x + 0.56 - 0.10 * ckVn.y))) * smoothstep(-0.62, -0.18, ckVn.y) * (1.0 - smoothstep(0.50, 0.78, ckVn.y));
    float ckS2 = (1.0 - smoothstep(0.012, 0.028, abs(ckVn.x + 0.74 - 0.06 * ckVn.y))) * smoothstep(-0.45, -0.05, ckVn.y) * (1.0 - smoothstep(0.35, 0.60, ckVn.y));
    float ckS3 = (1.0 - smoothstep(0.015, 0.035, abs(ckVn.x - 0.66))) * smoothstep(-0.30, 0.0, ckVn.y) * (1.0 - smoothstep(0.30, 0.50, ckVn.y));
    float ckTop = pow(max(dot(ckVn, normalize(float3(-0.30, 0.62, 0.72))), 0.0), 70.0);
    float ckRimL = pow(1.0 - ckNV, 5.0);
    float ckHiFace = 1.0 - 0.75 * ckFace;
    ckAdd += float3(0.86, 1.0, 0.90) * ((ckS1 * 0.55 + ckS2 * 0.45 + ckS3 * 0.30) * ckHiFace + ckTop * 0.70);
    ckAdd += \(f5hex(glassRim)) * ckRimL * 0.22;
    """

    /// 라벨: 텍스처(프리멀티 — 표본 rgb 는 이미 알파를 곱했다)를 (θ, t) 로 읽어 유리 위에 얹는다. 라벨 위에서는 반사를 줄인다.
    static let label = """
    constexpr sampler ckLblSmp(coord::normalized, filter::linear, mip_filter::linear, address::clamp_to_zero);
    float2 ckLuv = float2((ckTh + \(f5(labelHalfWidth))) / \(f5(2 * labelHalfWidth)), (ckT - \(f5(labelT0))) / \(f5(labelT1 - labelT0)));
    float4 ckL4 = ckLabelMap.sample(ckLblSmp, ckLuv);
    ckBase = ckBase * (1.0 - ckL4.a) + ckL4.rgb;
    ckAdd *= 1.0 - 0.75 * ckL4.a;
    """

    static let pattern = glass + highlights + label

    /// 몸 출력: 무늬 색 × 구운 밝기 + 반사. 얼굴 상자 안은 β 로 원본(눈 · 입 · 볼터치)을 지킨다. ★ 섞기는 β 를 잰 sRGB 0–255 공간에서
    /// 한다(선형에서 섞으면 눈꺼풀 · 입 테 텍셀이 라벤더를 지나치게 빼서 짙은 순초록으로 잘린다 — 생성기 머리말 '고친 것' ①).
    static let bodyOutput = """
    float3 ckCol = ckBase * mix(1.0, ckShade, ckShadeMix) + ckAdd;
    bool ckInFace = ckP.z > 0.30 && abs(ckP.x) < 0.58 && ckP.y > 0.08 && ckP.y < 0.62;
    float ckB = ckInFace ? ckBeta : 1.0;
    float3 ckCc = clamp(ckCol, float3(0.0), float3(1.0));
    float3 ckCe = 255.0 * select(1.055 * pow(ckCc, float3(1.0 / 2.4)) - 0.055, ckCc * 12.92, ckCc <= float3(0.0031308));
    float3 ckOe = clamp((ckPe + ckB * (ckCe - ckSe)) / 255.0, float3(0.0), float3(1.0));
    float3 ckOut = select(pow((ckOe + 0.055) / 1.055, float3(2.4)), ckOe / 12.92, ckOe <= float3(0.04045));
    _output.color = float4(ckOut, 1.0);
    """

    /// fragment 수정자: 디퓨즈 P · 피부 S · 피부 비율 β(케이크 초코와 같은 식) · 물체 좌표 값들 → 무늬(`pattern`) → `output`.
    /// 무늬가 쓸 수 있는 값: ckP(물체 좌표) · ckT(정수리 0 → 바닥 1) · ckTh(둘레각, 정면 0) · ckVn(화면 공간 법선) · ckNV(시선 · 법선 코사인,
    /// 0 = 가장자리) · ckFace(얼굴 둘레 0…1). 정할 값: ckBase(선형 바탕색) · ckAdd(더할 반사광) · ckShadeMix(구운 밝기를 얼마나 쓸지).
    static func fragment(output: String) -> String {
        """
        #pragma arguments
        texture2d<float> ckShadeMap;
        texture2d<float> ckLabelMap;
        #pragma varyings
        float3 ckVP;
        float2 ckUV;
        float3 ckVN;
        float3 ckVE;
        #pragma body
        constexpr sampler ckSmp(coord::normalized, filter::linear, mip_filter::linear, address::repeat);
        float3 ckLin = clamp(_surface.diffuse.rgb, float3(0.0), float3(1.0));
        float3 ckSL = clamp(ckShadeMap.sample(ckSmp, in.ckUV).rgb, float3(0.0), float3(1.0));
        float3 ckPe = 255.0 * select(1.055 * pow(ckLin, float3(1.0 / 2.4)) - 0.055, ckLin * 12.92, ckLin <= float3(0.0031308));
        float3 ckSe = 255.0 * select(1.055 * pow(ckSL, float3(1.0 / 2.4)) - 0.055, ckSL * 12.92, ckSL <= float3(0.0031308));
        float3 ckDv = ckPe - ckSe;
        float3 ckKs = \(String(format: "float3(%.2f, %.2f, %.2f)", blushSRGB.x, blushSRGB.y, blushSRGB.z)) - ckSe;
        float ckAk = dot(ckDv, ckKs) / max(1e-6, dot(ckKs, ckKs));
        float ckRes = length(ckDv - clamp(ckAk, 0.0, 1.0) * ckKs);
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
        float ckShade = clamp(dot(ckSL, float3(0.2126, 0.7152, 0.0722)) / \(f5(skinYRef)), 0.40, 1.45);
        float3 ckP = in.ckVP;
        float3 ckVn = normalize(in.ckVN);
        float3 ckEye = normalize(-in.ckVE);
        float ckNV = min(abs(dot(ckVn, ckEye)), 1.0);
        float ckT = (\(f5(bodyTop)) - ckP.y) / \(f5(bodyHeight));
        float ckTh = atan2(ckP.x, ckP.z);
        float ckFx = ckP.x / 0.60;
        float ckFy = (ckP.y - 0.34) / 0.30;
        float ckFace = (1.0 - smoothstep(0.85, 1.15, ckFx * ckFx + ckFy * ckFy)) * smoothstep(0.05, 0.25, ckP.z);
        float3 ckBase = float3(1.0);
        float3 ckAdd = float3(0.0);
        float ckShadeMix = 1.0;
        \(pattern)
        \(output)
        """
    }

    static var shaderModifiers: [SCNShaderModifierEntryPoint: String] {
        [.geometry: geometry, .fragment: fragment(output: bodyOutput)]
    }
}

// END isul-body-shader

// BEGIN isul-cap-decor — 앱 IsulAingFinish 가 이 구획을 글자 그대로 옮긴다(시험이 주석 · 공백을 걷고 맞댄다). 여기를 고치면 앱도 같이.

/// 돌려 따는 초록 병뚜껑(시안 R): 옆면 세로 홈 36(널링) · 아래쪽 따개 고리 틈 · 둥근 윗모서리 · 윗면 가운데 살짝 오목. 정수리 (x 0.09, z 0.01)에
/// 몸 법선을 30% 따라 세우고 바깥으로 0.28 라디안 더 기울인다(비스듬히). 매개 곡면 → SCNGeometry + 음영을 구운 작은 텍스처(몸 공간 고정 빛), unlit.
enum IsulCap {
    static let decorNodeName = "check.isulDecor"
    static let capNodeName = "check.isul.cap"
    static let crownX: Float = 0.09
    static let crownZ: Float = 0.01
    static let follow: Float = 0.30
    static let tilt: Float = 0.28
    static let radius: Float = 0.185
    static let height: Float = 0.165
    /// 뚜껑 꼭대기(물체 좌표 y) — 앱 프레이밍이 쓴다. 생성기가 실행 때 다시 재서 맞댄다.
    static let capTopY = 1.0032
    static let metal = 0x1F7A45
    static let metalHi = 0x6CC892
    static let metalTop = 0x2E9058

    typealias SurfaceProbe = (Float, Float) -> (SIMD3<Float>, SIMD3<Float>)
    typealias SurfaceFn = (Float, Float) -> SIMD3<Float>

    struct Look {
        var ambient = 0.62
        var spec = 0.25
        var gloss = 24.0
        var wrap = 0.4
    }

    /// 몸 공간에 고정한 빛(위 · 앞 · 살짝 왼쪽) — 아잉 디퓨즈에 구운 음영과 같은 쪽.
    static let keyLight = simd_normalize(SIMD3<Double>(-0.30, 0.85, 0.45))
    static let viewLight = simd_normalize(SIMD3<Double>(0, 0.30, 1))

    static func smooth(_ e0: Double, _ e1: Double, _ x: Double) -> Double {
        let t = min(max((x - e0) / (e1 - e0), 0), 1)
        return t * t * (3 - 2 * t)
    }

    static func lin(_ hex: Int) -> SIMD3<Double> {
        func l(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return SIMD3(l(Double((hex >> 16) & 255) / 255), l(Double((hex >> 8) & 255) / 255), l(Double(hex & 255) / 255))
    }

    static func srgbByte(_ v: Double) -> UInt8 {
        let c = min(max(v, 0), 1)
        let s = c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055
        return UInt8(max(0, min(255, (s * 255).rounded())))
    }

    static func lit(_ albedo: SIMD3<Double>, _ n: SIMD3<Double>, _ look: Look) -> SIMD3<Double> {
        let ndl = simd_dot(n, keyLight)
        let diff = min(max((ndl + look.wrap) / (1 + look.wrap), 0), 1)
        let ao = 1 - 0.22 * max(-n.y, 0)
        var c = albedo * (look.ambient + (1 - look.ambient) * diff) * ao
        let h = simd_normalize(keyLight + viewLight)
        c += SIMD3(repeating: pow(max(simd_dot(n, h), 0), look.gloss) * look.spec)
        return simd_clamp(c, .zero, SIMD3(repeating: 1))
    }

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

    static func pieceNode(name: String, nu: Int, nv: Int, closedU: Bool, texW: Int, texH: Int, pos: @escaping SurfaceFn,
                          albedo: (Double, Double, SIMD3<Float>) -> SIMD3<Double>, look: Look, transform: simd_float4x4) -> SCNNode {
        let rot = simd_float3x3(simd_make_float3(transform.columns.0), simd_make_float3(transform.columns.1), simd_make_float3(transform.columns.2))
        var verts = [SCNVector3](), norms = [SCNVector3](), uvs = [CGPoint]()
        for j in 0...nv { for i in 0...nu {
            let u = Float(i) / Float(nu), v = Float(j) / Float(nv)
            let p = pos(u, v), n = surfaceNormal(pos, u, v, closedU: closedU)
            verts.append(SCNVector3(p.x, p.y, p.z)); norms.append(SCNVector3(n.x, n.y, n.z)); uvs.append(CGPoint(x: CGFloat(u), y: CGFloat(v)))
        } }
        var idx = [UInt32]()
        let row = UInt32(nu + 1)
        for j in 0..<UInt32(nv) { for i in 0..<UInt32(nu) {
            let a = j * row + i, b = a + 1, c = a + row, d = c + 1
            idx += [a, b, c, b, d, c]
        } }
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: verts), SCNGeometrySource(normals: norms),
                                             SCNGeometrySource(textureCoordinates: uvs)],
                                   elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
        var px = [UInt8](repeating: 255, count: texW * texH * 4)
        for y in 0..<texH { for x in 0..<texW {
            var acc = SIMD3<Double>(0, 0, 0)
            for sy in 0..<2 { for sx in 0..<2 {
                let u = (Double(x) + 0.25 + 0.5 * Double(sx)) / Double(texW), v = (Double(y) + 0.25 + 0.5 * Double(sy)) / Double(texH)
                acc += albedo(u, v, pos(Float(u), Float(v)))
            } }
            let u = Float((Double(x) + 0.5) / Double(texW)), v = Float((Double(y) + 0.5) / Double(texH))
            let nw = rot * surfaceNormal(pos, u, v, closedU: closedU)
            let c = lit(acc / 4, simd_normalize(SIMD3<Double>(Double(nw.x), Double(nw.y), Double(nw.z))), look)
            let o = (y * texW + x) * 4
            px[o] = srgbByte(c.x); px[o + 1] = srgbByte(c.y); px[o + 2] = srgbByte(c.z)
        } }
        let ctx = CGContext(data: &px, width: texW, height: texH, bitsPerComponent: 8, bytesPerRow: texW * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = ctx.makeImage()!
        material.diffuse.wrapS = closedU ? .repeat : .clamp
        material.diffuse.wrapT = .clamp
        material.diffuse.mipFilter = .linear
        geometry.materials = [material]
        let node = SCNNode(geometry: geometry)
        node.name = name
        node.simdTransform = transform
        return node
    }

    static func lathe(_ profile: @escaping (Float) -> (r: Float, y: Float), ridge: ((Float, Float) -> Float)? = nil) -> SurfaceFn {
        { u, v in
            let (r0, y) = profile(v)
            let a = 2 * Float.pi * u
            let r = r0 * (ridge?(u, v) ?? 1)
            return SIMD3(r * sin(a), y, r * cos(a))
        }
    }

    /// 정수리 (crownX, crownZ) 의 몸 표면 점에 세운 변환: 위 방향 = 세로축과 몸 법선 사이(follow) + 바깥으로 tilt 라디안.
    static func placement(probe: SurfaceProbe) -> simd_float4x4 {
        let (p, n0) = probe(crownX, crownZ)
        var n = simd_normalize(n0)
        if n.y < 0 { n = -n }
        var up = simd_normalize(simd_mix(SIMD3<Float>(0, 1, 0), n, SIMD3(repeating: follow)))
        let outward = simd_normalize(SIMD3<Float>(crownX, 0, crownZ) + SIMD3(1e-4, 0, 0))
        up = simd_normalize(up + outward * tan(tilt))
        var m = simd_float4x4(simd_quatf(from: SIMD3(0, 1, 0), to: up))
        m.columns.3 = SIMD4(p.x, p.y, p.z, 1)
        return m
    }

    static func capNode(transform: simd_float4x4) -> SCNNode {
        let rc = radius, hc = height
        let e: Float = 0.022, sink: Float = 0.045
        let side = hc - e, arc = Float.pi / 2 * e, cap = rc - e, total = side + arc + cap
        let profile: (Float) -> (r: Float, y: Float) = { s in
            let d = s * total
            if d < side {
                let y = d - sink
                let notch = Float(1 - 0.07 * smooth(0.0, 1.0, 1 - abs(Double(y + sink) - 0.068) / 0.008))
                return (rc * notch, y)
            }
            if d < side + arc {
                let phi = (d - side) / e
                return (rc - e + e * cos(phi), side - sink + e * sin(phi))
            }
            let t = (d - side - arc) / cap
            return (max(0, (rc - e) * (1 - t)), hc - sink - 0.004 * Float(sin(Double(t) * .pi)))
        }
        let ridge: (Float, Float) -> Float = { u, v in
            let d = v * total
            guard d < side - 0.004, d > 0.082 else { return 1 }
            return 1 + 0.030 * Float(pow(abs(cos(Double(u) * 2 * .pi * 36)), 2) - 0.5)
        }
        let base = lin(metal), hi = lin(metalHi), top = lin(metalTop)
        func albedo(_ u: Double, _ v: Double, _ p: SIMD3<Float>) -> SIMD3<Double> {
            let d = v * Double(total)
            if d >= Double(side + arc) { return top }
            let groove = pow(abs(cos(u * 2 * .pi * 36)), 2)
            var c = base + (hi - base) * groove * 0.6
            if d < 0.082 { c = base * 0.95 + (hi - base) * 0.25 }
            return c
        }
        return pieceNode(name: capNodeName, nu: 240, nv: 40, closedU: true, texW: 512, texH: 128, pos: lathe(profile, ridge: ridge),
                         albedo: albedo, look: Look(ambient: 0.55, spec: 0.55, gloss: 42, wrap: 0.35), transform: transform)
    }

    /// 장식 루트(이름 `decorNodeName`) — 캐릭터 노드의 자식으로 붙인다.
    static func make(probe: SurfaceProbe) -> SCNNode {
        let root = SCNNode()
        root.name = decorNodeName
        root.addChildNode(capNode(transform: placement(probe: probe)))
        return root
    }

    /// 장식 루트 좌표(= 물체 좌표)에서 정점의 가장 높은 y.
    static func topY(_ decor: SCNNode) -> Float {
        var top = -Float.infinity
        func walk(_ node: SCNNode, _ parent: simd_float4x4) {
            let m = parent * node.simdTransform
            if let source = node.geometry?.sources(for: .vertex).first {
                source.data.withUnsafeBytes { raw in
                    for i in 0..<source.vectorCount {
                        let b = source.dataOffset + i * source.dataStride
                        let p: SIMD3<Float>
                        if source.bytesPerComponent == 8 {
                            p = SIMD3(Float(raw.loadUnaligned(fromByteOffset: b, as: Double.self)), Float(raw.loadUnaligned(fromByteOffset: b + 8, as: Double.self)),
                                      Float(raw.loadUnaligned(fromByteOffset: b + 16, as: Double.self)))
                        } else {
                            p = SIMD3(raw.loadUnaligned(fromByteOffset: b, as: Float.self), raw.loadUnaligned(fromByteOffset: b + 4, as: Float.self),
                                      raw.loadUnaligned(fromByteOffset: b + 8, as: Float.self))
                        }
                        top = max(top, (m * SIMD4(p.x, p.y, p.z, 1)).y)
                    }
                }
            }
            for child in node.childNodes { walk(child, m) }
        }
        for child in decor.childNodes { walk(child, matrix_identity_float4x4) }
        return top
    }
}

// END isul-cap-decor

// MARK: - 생성기 전용 셰이더 출력(초상 지도 · 고침 전 비교)

/// 초상용 무늬 지도: 얼굴 무시 · 밝기 1 의 유리색(ckBase + ckAdd).
let colorMapOutput = "_output.color = float4(clamp(ckBase + ckAdd, float3(0.0), float3(1.0)), 1.0);"
/// 시안 그대로의 선형 섞기(고침 전) — --preview 의 eyes-4x-before 에만 쓴다.
let legacyLinearOutput = """
float3 ckCol = ckBase * mix(1.0, ckShade, ckShadeMix) + ckAdd;
bool ckInFace = ckP.z > 0.30 && abs(ckP.x) < 0.58 && ckP.y > 0.08 && ckP.y < 0.62;
float ckB = ckInFace ? ckBeta : 1.0;
float3 ckOut = ckLin + ckB * (ckCol - ckSL);
_output.color = float4(clamp(ckOut, float3(0.0), float3(1.0)), 1.0);
"""

// MARK: - 라벨 그림(CoreGraphics + CoreText — 결정적)

func brushFont(size: CGFloat) -> NSFont {
    guard let font = NSFontManager.shared.font(withFamily: labelFontFamily, traits: [], weight: 5, size: size),
          font.familyName == labelFontFamily else {
        fail("라벨 글꼴 '\(labelFontFamily)'(나눔손글씨 붓)이 없다 — 서체 관리자에서 내려받아라(다른 글꼴로 바꾸지 않는다)")
    }
    return font
}

func dropPath(cx: CGFloat, cy: CGFloat, r: CGFloat) -> CGPath {
    // 아래가 둥글고 위가 뾰족한 물방울(CG 좌표 — y 위로).
    let p = CGMutablePath()
    p.move(to: CGPoint(x: cx, y: cy + r * 2.15))
    p.addCurve(to: CGPoint(x: cx + r, y: cy), control1: CGPoint(x: cx + r * 0.25, y: cy + r * 1.55), control2: CGPoint(x: cx + r, y: cy + r * 0.85))
    p.addArc(center: CGPoint(x: cx, y: cy), radius: r, startAngle: 0, endAngle: .pi, clockwise: true)
    p.addCurve(to: CGPoint(x: cx, y: cy + r * 2.15), control1: CGPoint(x: cx - r, y: cy + r * 0.85), control2: CGPoint(x: cx - r * 0.25, y: cy + r * 1.55))
    p.closeSubpath()
    return p
}

/// 흰 곡선 라벨: 위 가장자리 곧게 · 아래는 완만한 이슬 곡선, 위쪽 초록 두 줄, 왼쪽 파란 이슬방울, 초록 붓글씨 '참이슬' + 작은 '아잉 에디션'.
/// 그림 크기 = 라벨이 몸에서 차지하는 호 길이(θ 범위 × 반지름 0.60) : 높이(t 범위 × 몸 높이) 비율.
func labelImage() -> CGImage {
    let arcW = 2 * IsulBody.labelHalfWidth * 0.60, arcH = (IsulBody.labelT1 - IsulBody.labelT0) * IsulBody.bodyHeight
    let W = labelWidth, H = Int((Double(W) * arcH / arcW).rounded())
    let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let w = CGFloat(W), h = CGFloat(H)
    let shape = CGMutablePath()
    shape.move(to: CGPoint(x: 0, y: h))
    shape.addLine(to: CGPoint(x: w, y: h))
    shape.addLine(to: CGPoint(x: w, y: h * 0.30))
    shape.addCurve(to: CGPoint(x: 0, y: h * 0.06), control1: CGPoint(x: w * 0.62, y: -h * 0.10), control2: CGPoint(x: w * 0.30, y: h * 0.32))
    shape.closeSubpath()
    ctx.addPath(shape)
    ctx.setFillColor(CGColor(srgbRed: 0.985, green: 0.985, blue: 0.975, alpha: 1))
    ctx.fillPath()
    ctx.saveGState(); ctx.addPath(shape); ctx.clip()
    let accent = CGColor(srgbRed: labelAccent.x, green: labelAccent.y, blue: labelAccent.z, alpha: 1)
    let ink = NSColor(srgbRed: labelInk.x, green: labelInk.y, blue: labelInk.z, alpha: 1)
    // 위 가장자리 가는 두 줄.
    ctx.setFillColor(accent)
    ctx.fill(CGRect(x: 0, y: h * 0.93, width: w, height: h * 0.025))
    ctx.fill(CGRect(x: 0, y: h * 0.885, width: w, height: h * 0.010))
    // 이슬방울(맑은 파랑 그라데이션 + 흰 반짝).
    let dropR = h * 0.13
    let dropC = CGPoint(x: w * 0.205, y: h * 0.47)
    ctx.saveGState(); ctx.addPath(dropPath(cx: dropC.x, cy: dropC.y, r: dropR)); ctx.clip()
    let g = CGGradient(colorsSpace: sRGB, colors: [CGColor(srgbRed: 0.55, green: 0.86, blue: 0.98, alpha: 1),
                                                   CGColor(srgbRed: 0.09, green: 0.48, blue: 0.84, alpha: 1)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(g, start: CGPoint(x: dropC.x - dropR, y: dropC.y + dropR * 2), end: CGPoint(x: dropC.x + dropR, y: dropC.y - dropR), options: [])
    ctx.setFillColor(CGColor(gray: 1, alpha: 0.9))
    ctx.fillEllipse(in: CGRect(x: dropC.x - dropR * 0.55, y: dropC.y + dropR * 0.05, width: dropR * 0.32, height: dropR * 0.55))
    ctx.restoreGState()
    // 글자.
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    let mainSize = h * 0.50
    let main = NSAttributedString(string: labelText, attributes: [.font: brushFont(size: mainSize), .foregroundColor: ink, .strokeColor: ink,
                                                                  .strokeWidth: -4.0, .kern: mainSize * 0.02])
    let ms = main.size()
    let mainX = w * 0.60 - ms.width / 2, mainY = h * 0.43 - ms.height * 0.40
    main.draw(at: NSPoint(x: mainX, y: mainY))
    let subSize = h * 0.095
    let sub = NSAttributedString(string: labelSub, attributes: [.font: NSFont.systemFont(ofSize: subSize, weight: .bold),
                                                                .foregroundColor: NSColor(cgColor: accent)!, .kern: subSize * 0.25])
    let ss = sub.size()
    sub.draw(at: NSPoint(x: w * 0.60 - ss.width / 2, y: mainY - ss.height * 0.55))
    NSGraphicsContext.restoreGraphicsState()
    ctx.restoreGState()
    return ctx.makeImage()!
}

// MARK: - 몸 디퓨즈 · 씬

func decodedTexture(_ contents: Any?) -> CGImage? {
    guard let contents else { return nil }
    if CFGetTypeID(contents as CFTypeRef) == CGImage.typeID { return (contents as! CGImage) }
    if let data = contents as? Data, let s = CGImageSourceCreateWithData(data as CFData, nil) { return CGImageSourceCreateImageAtIndex(s, 0, nil) }
    if let image = contents as? NSImage { return image.cgImage(forProposedRect: nil, context: nil, hints: nil) }
    if let url = contents as? URL { return NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil) }
    return nil
}

let shadeMapImage = loadImage(shadePath)
var compositeCache: CGImage?

/// 무지개 · 케이크와 같은 합성: 텍셀마다 isGoldSkin(원본) ? 밝기 맵 : 원본.
func compositeDiffuse(original: CGImage) -> CGImage {
    if let compositeCache { return compositeCache }
    guard original.width == shadeMapImage.width, original.height == shadeMapImage.height else { fail("밝기 맵 크기가 디퓨즈와 다르다") }
    let o = bytes(original), s = bytes(shadeMapImage)
    var out = o
    for i in 0..<(original.width * original.height) where isGoldSkin(Int(o[i * 4]), Int(o[i * 4 + 1]), Int(o[i * 4 + 2])) {
        out[i * 4] = s[i * 4]; out[i * 4 + 1] = s[i * 4 + 1]; out[i * 4 + 2] = s[i * 4 + 2]; out[i * 4 + 3] = 255
    }
    let made = makeImage(out, original.width, original.height, space: CGColorSpaceCreateDeviceRGB())
    compositeCache = made
    return made
}

/// 기준 휘도 = 합성 디퓨즈 피부 텍셀 선형 휘도의 중앙값(IsulBody.skinYRef 와 맞댄다).
func measuredSkinYRef(_ diffuse: CGImage) -> Double {
    let px = bytes(diffuse)
    var ys = [Double]()
    for i in 0..<(px.count / 4) where isGoldSkin(Int(px[i * 4]), Int(px[i * 4 + 1]), Int(px[i * 4 + 2])) {
        ys.append(lumaLinear(linB(Double(px[i * 4]), Double(px[i * 4 + 1]), Double(px[i * 4 + 2]))))
    }
    ys.sort()
    return ys[ys.count / 2]
}

struct Rig {
    let scene: SCNScene
    let facing: SCNNode
    let character: SCNNode
    let bodyNode: SCNNode
    let bodyMin: SIMD3<Float>
    let bodyMax: SIMD3<Float>
}

var labelForRender: CGImage?

/// fragment = nil 이면 몸은 깊이만 쓰는 가림막(장식 층 굽기).
func makeRig(fragment: String?) -> Rig {
    guard let scene = try? SCNScene(url: URL(fileURLWithPath: modelPath), options: nil) else { fail("모델을 못 읽었다") }
    scene.background.contents = NSColor.clear
    guard let character = scene.rootNode.childNodes.first else { fail("캐릭터 노드 없음") }
    var bodyNode: SCNNode?
    scene.rootNode.enumerateHierarchy { node, stop in if node.geometry != nil { bodyNode = node; stop.pointee = true } }
    guard let bodyNode, let material = bodyNode.geometry?.materials.first,
          let original = decodedTexture(material.diffuse.contents) else { fail("몸 재질 없음") }
    guard bodyNode.simdWorldTransform == matrix_identity_float4x4 else { fail("메시 노드 변환이 단위가 아니다") }
    material.lightingModel = .constant
    material.diffuse.contents = compositeDiffuse(original: original)
    if let fragment {
        material.shaderModifiers = [.geometry: IsulBody.geometry, .fragment: fragment]
        material.setValue(SCNMaterialProperty(contents: shadeMapImage), forKey: IsulBody.shadeMapKey)
        let label = SCNMaterialProperty(contents: labelForRender!)
        label.mipFilter = .linear
        material.setValue(label, forKey: IsulBody.labelMapKey)
    } else {
        material.colorBufferWriteMask = []
    }
    let wrapper = SCNNode(), facing = SCNNode()
    character.removeFromParentNode()
    facing.addChildNode(character)
    wrapper.addChildNode(facing)
    scene.rootNode.addChildNode(wrapper)
    let (a, b) = scene.rootNode.boundingBox
    return Rig(scene: scene, facing: facing, character: character, bodyNode: bodyNode,
               bodyMin: SIMD3(Float(a.x), Float(a.y), Float(a.z)), bodyMax: SIMD3(Float(b.x), Float(b.y), Float(b.z)))
}

/// 케이크 생성기 `meshSurfaceProbe` 와 같다 — 정수리 위 (x, z) 에서 내리쏜 선분 hitTest 의 가장 높은 점 · 그 법선.
func meshSurfaceProbe(_ bodyNode: SCNNode) -> IsulCap.SurfaceProbe {
    { x, z in
        let hits = bodyNode.hitTestWithSegment(from: SCNVector3(x, 3, z), to: SCNVector3(x, -3, z),
                                               options: [SCNHitTestOption.backFaceCulling.rawValue: false])
        guard let top = hits.max(by: { $0.localCoordinates.y < $1.localCoordinates.y }) else { fail("정수리 hitTest 실패 (\(x), \(z))") }
        let p = top.localCoordinates, n = top.localNormal
        return (SIMD3(Float(p.x), Float(p.y), Float(p.z)), simd_normalize(SIMD3(Float(n.x), Float(n.y), Float(n.z))))
    }
}

func attachDecor(_ rig: Rig) { rig.character.addChildNode(IsulCap.make(probe: meshSurfaceProbe(rig.bodyNode))) }

/// 앱 카메라(몸만 보고 잡은 40° — 금 · 무지개 · 케이크 프레이밍과 같은 식).
func appCamera(_ rig: Rig) -> SCNNode {
    let center = (rig.bodyMin + rig.bodyMax) / 2
    let extent = max(rig.bodyMax.x - rig.bodyMin.x, rig.bodyMax.y - rig.bodyMin.y)
    let distance = extent / (2 * tan(20 * Float.pi / 180)) * 1.4
    let node = SCNNode()
    let camera = SCNCamera()
    camera.fieldOfView = 40
    camera.zNear = 0.01
    camera.zFar = 1_000
    node.camera = camera
    node.simdPosition = SIMD3(center.x, center.y + extent * 0.55, rig.bodyMax.z + distance)
    node.simdLook(at: SIMD3(center.x, center.y - extent * 0.16, center.z))
    return node
}

func meshPositions(_ rig: Rig) -> [SIMD3<Float>] {
    guard let vs = rig.bodyNode.geometry?.sources(for: .vertex).first else { fail("정점 없음") }
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

/// 초상 카메라: 앱 카메라 방향으로 몸 정점이 프레임의 `fill` 만큼 차게 거리를 맞춘다.
func portraitCamera(_ rig: Rig, fill: Float) -> SCNNode {
    let pos = meshPositions(rig)
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
    let n = SCNNode(); n.camera = SCNCamera(); n.camera!.fieldOfView = 40
    n.camera!.zNear = 0.01; n.camera!.zFar = 1_000
    n.simdPosition = center - dir * d; n.simdLook(at: center)
    return n
}

/// 스냅숏의 '선형 프리멀티를 sRGB 로 부호화한' 반투명 픽셀을 바른 sRGB 프리멀티로 고친다(케이크 생성기와 같다).
func straightened(_ image: NSImage) -> CGImage {
    guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let cg = rep.cgImage else { fail("렌더 실패") }
    let w = cg.width, h = cg.height
    var px = bytes(cg, space: sRGB)
    for i in 0..<(w * h) {
        let a = Double(px[i * 4 + 3]) / 255
        if a >= 1 { continue }
        if a <= 0 { px[i * 4] = 0; px[i * 4 + 1] = 0; px[i * 4 + 2] = 0; continue }
        for c in 0..<3 {
            let l = min(srgbToLinear(Double(px[i * 4 + c]) / 255) / a, 1)
            px[i * 4 + c] = UInt8(min(255, (linearToSrgb(l) * a * 255).rounded()))
        }
    }
    return makeImage(px, w, h)
}

func snapshot(_ rig: Rig, camera: SCNNode, size: Int, yawDegrees: Double = 0) -> CGImage {
    rig.facing.eulerAngles = SCNVector3(0, CGFloat(yawDegrees * .pi / 180), 0)
    if camera.parent == nil { rig.scene.rootNode.addChildNode(camera) }
    let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
    renderer.scene = rig.scene
    renderer.pointOfView = camera
    renderer.autoenablesDefaultLighting = false
    let shot = renderer.snapshot(atTime: 0, with: CGSize(width: size, height: size), antialiasingMode: .multisampling4X)
    return straightened(shot)
}

func alphaBox(_ px: [UInt8], _ w: Int, _ h: Int, threshold: UInt8) -> (Int, Int, Int, Int) {
    var x0 = w, x1 = -1, y0 = h, y1 = -1
    for y in 0..<h { for x in 0..<w where px[(y * w + x) * 4 + 3] > threshold { x0 = min(x0, x); x1 = max(x1, x); y0 = min(y0, y); y1 = max(y1, y) } }
    return (x0, x1, y0, y1)
}

// MARK: - 초상(192²)

struct PortraitSource {
    let expression: String
    let w: Int, h: Int
    let P: [SIMD3<Double>], A: [Double], core: [Bool], S: [SIMD3<Double>], K: SIMD3<Double>, yRef2D: Double
    let box: (Int, Int, Int, Int)
    let nearRim: [Bool]
}

func analyzePortrait(_ expression: String) -> PortraitSource {
    let path = "\(resourceDir)/aing-\(expression).png"
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
    guard blushCount > 0 else { fail("볼터치를 못 찾았다: \(path)") }
    var S = P
    for ch in 0..<3 {
        var v = (0..<n).map { P[$0][ch] }
        inpaint(&v, known: core, width: w, height: h, relax: 30)
        for i in 0..<n { S[i][ch] = v[i] }
    }
    var ys = (0..<n).filter { core[$0] }.map { lumaLinear(linB(P[$0].x, P[$0].y, P[$0].z)) }
    ys.sort()
    var bx0 = w, bx1 = -1, by0 = h, by1 = -1
    for y in 0..<h { for x in 0..<w where A[y * w + x] > 0.5 { bx0 = min(bx0, x); bx1 = max(bx1, x); by0 = min(by0, y); by1 = max(by1, y) } }
    var nearRim = [Bool](repeating: false, count: n)
    for y in 0..<h { for x in 0..<w where A[y * w + x] < 0.5 {
        for yy in max(0, y - rimRadius)...min(h - 1, y + rimRadius) { for xx in max(0, x - rimRadius)...min(w - 1, x + rimRadius) { nearRim[yy * w + xx] = true } }
    } }
    return PortraitSource(expression: expression, w: w, h: h, P: P, A: A, core: core, S: S, K: blushSum / blushCount, yRef2D: ys[ys.count / 2],
                          box: (bx0, bx1, by0, by1), nearRim: nearRim)
}

/// 피부 비율 β — 셰이더 ckBeta 와 같은 식(케이크 생성기 `skinFraction`). unmix = false 면 시안의 옛 식.
func skinFraction(_ P: SIMD3<Double>, _ S: SIMD3<Double>, _ K: SIMD3<Double>, unmix: Bool) -> Double {
    let d = P - S, ks = K - S
    let a = simd_dot(d, ks) / max(1e-6, simd_length_squared(ks))
    let resid = simd_length(d - min(max(a, 0), 1) * ks)
    if resid <= 20, a > -0.1, a < 1.1 { return 1 - min(max(a, 0), 1) }
    // ③ 볼터치 한가운데: 평균 K 보다 더 진한 분홍(K 방향으로 1.1 배 넘게 간 텍셀)도 온전한 볼터치다 → 원본 그대로(옛 식이면 β ≈ 0.4 로 유리색이 섞여 흙빛 가운데가 섰다).
    if resid <= 20, a >= 1.1 { return 0 }
    let old = min(max(1 - simd_length(d) / 80, 0), 1)
    guard unmix else { return old }
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

/// 3D 지도 둘(초상 카메라): 유리 무늬 색(선형, 몸 밖은 안에서 번져 채움) · 장식 층(넓은 시야로 굽는다).
struct PortraitMaps {
    let color: [[Double]]
    let body: (Int, Int, Int, Int)       // 3D 몸 알파 상자(지도 px)
    let decor: CGImage
    let decorBox: (Int, Int, Int, Int)
    let decorSize: Int, pad: Int
}

func renderPortraitMaps() -> PortraitMaps {
    let size = portraitMapSize
    let rig = makeRig(fragment: IsulBody.fragment(output: colorMapOutput))
    let image = snapshot(rig, camera: portraitCamera(rig, fill: 0.84), size: size)
    let mpx = bytes(image, space: sRGB)
    var ch = [[Double]](repeating: [Double](repeating: 0, count: size * size), count: 3)
    var known = [Bool](repeating: false, count: size * size)
    for i in 0..<(size * size) where mpx[i * 4 + 3] == 255 {
        let l = linB(Double(mpx[i * 4]), Double(mpx[i * 4 + 1]), Double(mpx[i * 4 + 2]))
        ch[0][i] = l.x; ch[1][i] = l.y; ch[2][i] = l.z; known[i] = true
    }
    for c in 0..<3 { inpaint(&ch[c], known: known, width: size, height: size, relax: 0) }
    // 장식 층: 같은 초상 카메라 · 몸은 깊이만 쓰는 가림막. 시야를 두 배로 넓혀(뚜껑이 몸 상자 밖으로 나간다) 굽는다.
    let frameSize = size * 2, pad = frameSize / 2, decorSize = frameSize + pad * 2
    let decorRig = makeRig(fragment: nil)
    attachDecor(decorRig)
    let wideCam = portraitCamera(decorRig, fill: 0.84)
    wideCam.camera!.fieldOfView = CGFloat(2 * atan(2 * tan(20 * Double.pi / 180)) * 180 / Double.pi)
    let dimg = snapshot(decorRig, camera: wideCam, size: decorSize)
    return PortraitMaps(color: ch, body: alphaBox(mpx, size, size, threshold: 127), decor: dimg,
                        decorBox: alphaBox(bytes(dimg, space: sRGB), decorSize, decorSize, threshold: 6), decorSize: decorSize, pad: pad)
}

/// 한 표정의 재색 몸(192² 원본 틀) + 장식 층 자리(원본 px 좌표) + 몸 · 장식 합친 상자.
struct PreparedPortrait {
    let expression: String
    let body: CGImage
    let decorRect: CGRect               // 원본 px 좌표(위가 0)
    let union: (Double, Double, Double, Double)
    let rimBetaTexels: Int
}

func preparePortrait(_ src: PortraitSource, maps: PortraitMaps) -> PreparedPortrait {
    let w = src.w, h = src.h, n = w * h, m = portraitMapSize
    let g = maps.body
    let gx0 = Double(g.0), gw = Double(g.1 - g.0 + 1), gy0 = Double(g.2), gh = Double(g.3 - g.2 + 1)
    let b = src.box
    let bx0 = Double(b.0), bw = Double(b.1 - b.0 + 1), by0 = Double(b.2), bh = Double(b.3 - b.2 + 1)
    func sample(_ v: [Double], _ x: Double, _ y: Double) -> Double {
        let fx = min(max(x - 0.5, 0), Double(m - 1)), fy = min(max(y - 0.5, 0), Double(m - 1))
        let ix = min(Int(fx), m - 2), iy = min(Int(fy), m - 2)
        let ax = fx - Double(ix), ay = fy - Double(iy)
        let p00 = v[iy * m + ix], p01 = v[iy * m + ix + 1], p10 = v[(iy + 1) * m + ix], p11 = v[(iy + 1) * m + ix + 1]
        return (p00 * (1 - ax) + p01 * ax) * (1 - ay) + (p10 * (1 - ax) + p11 * ax) * ay
    }
    var out = [UInt8](repeating: 0, count: n * 4)
    var rimTexels = 0
    for y in 0..<h { for x in 0..<w where src.A[y * w + x] > 0 {
        let i = y * w + x
        let s = src.S[i]
        let mx = gx0 + (Double(x) + 0.5 - bx0) / bw * gw, my = gy0 + (Double(y) + 0.5 - by0) / bh * gh
        let base = SIMD3(sample(maps.color[0], mx, my), sample(maps.color[1], mx, my), sample(maps.color[2], mx, my))
        let ratio = min(max(lumaLinear(linB(s.x, s.y, s.z)) / src.yRef2D, 0.4), 1.45)
        let (r, gg, bb) = linearToBytes(base * (1 + IsulBody.glassShadeMix * (ratio - 1)))
        let G = SIMD3(Double(r), Double(gg), Double(bb))
        let beta: Double
        if src.core[i] || src.A[i] < 0.98 {
            beta = 1
        } else {
            beta = skinFraction(src.P[i], s, src.K, unmix: !src.nearRim[i])
            if src.nearRim[i] { rimTexels += 1 }
        }
        let o = simd_clamp(src.P[i] + beta * (G - s), SIMD3(repeating: 0), SIMD3(repeating: 255))
        let alpha = src.A[i]
        out[i * 4] = UInt8((o.x * alpha).rounded()); out[i * 4 + 1] = UInt8((o.y * alpha).rounded())
        out[i * 4 + 2] = UInt8((o.z * alpha).rounded()); out[i * 4 + 3] = UInt8((alpha * 255).rounded())
    } }
    // 장식 층 자리: 지도 몸 상자 ↔ 원본 몸 상자 맞춤(장식 지도는 시야 두 배 + 여백 pad).
    let sx = bw / (gw * 2), sy = bh / (gh * 2)
    let ox = bx0 - (gx0 * 2 + Double(maps.pad)) * sx, oy = by0 - (gy0 * 2 + Double(maps.pad)) * sy
    let d = maps.decorBox
    let union = (min(bx0, ox + Double(d.0) * sx), max(bx0 + bw, ox + Double(d.1 + 1) * sx),
                 min(by0, oy + Double(d.2) * sy), max(by0 + bh, oy + Double(d.3 + 1) * sy))
    return PreparedPortrait(expression: src.expression, body: makeImage(out, w, h),
                            decorRect: CGRect(x: ox, y: oy, width: Double(maps.decorSize) * sx, height: Double(maps.decorSize) * sy),
                            union: union, rimBetaTexels: rimTexels)
}

/// 두 표정이 같은 몸 배율 · 같은 자리: 합친 상자 전체가 여백 안에 들게(0.88 상한).
func commonLayout(_ all: [PreparedPortrait]) -> (k: Double, cx: Double, cy: Double) {
    var x0 = Double.infinity, x1 = -Double.infinity, y0 = Double.infinity, y1 = -Double.infinity
    for p in all { x0 = min(x0, p.union.0); x1 = max(x1, p.union.1); y0 = min(y0, p.union.2); y1 = max(y1, p.union.3) }
    let avail = Double(portraitSize) - 2 * portraitMargin
    return (min(portraitBodyScale, avail / (x1 - x0), avail / (y1 - y0)), (x0 + x1) / 2, (y0 + y1) / 2)
}

func composePortrait(_ p: PreparedPortrait, decor: CGImage, layout: (k: Double, cx: Double, cy: Double)) -> CGImage {
    let side = Double(portraitSize), k = layout.k
    func rect(_ x: Double, _ y: Double, _ rw: Double, _ rh: Double) -> CGRect {
        let X = side / 2 + (x - layout.cx) * k, Y = side / 2 + (y - layout.cy) * k
        return CGRect(x: X, y: side - (Y + rh * k), width: rw * k, height: rh * k)
    }
    let ctx = CGContext(data: nil, width: portraitSize, height: portraitSize, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.draw(p.body, in: rect(0, 0, Double(p.body.width), Double(p.body.height)))
    ctx.draw(decor, in: rect(p.decorRect.minX, p.decorRect.minY, p.decorRect.width, p.decorRect.height))
    let image = ctx.makeImage()!
    let px = bytes(image, space: sRGB)
    var border = 0
    for y in 0..<portraitSize { for x in 0..<portraitSize where x < 2 || y < 2 || x >= portraitSize - 2 || y >= portraitSize - 2 {
        border = max(border, Int(px[(y * portraitSize + x) * 4 + 3]))
    } }
    guard Double(border) / 255 <= borderAlphaLimit else { fail("\(p.expression) 초상 테두리 알파 \(Double(border) / 255) > \(borderAlphaLimit) — 뚜껑이 잘린다") }
    let box = alphaBox(px, portraitSize, portraitSize, threshold: 0)
    print(String(format: "[portrait] %@: 몸 배율 %.3f(0.88 상한) · 알파 상자 x %d–%d y %d–%d · 테두리 2px 최대 알파 %.3f · 가장자리 띠 옛 β 텍셀 %d",
                 p.expression, k, box.0, box.1, box.2, box.3, Double(border) / 255, p.rimBetaTexels))
    return image
}

// MARK: - 미리보기(--preview, 저장소 밖)

/// 앱 구도 3D 한 장(512², 시안 시트와 같은 자르기). lift = 부유 높이(캐릭터를 위로).
func appView(fragment: String, yaw: Double, lift: Float = 0, uncropped: Bool = false) -> CGImage {
    let rig = makeRig(fragment: fragment)
    let camera = appCamera(rig)        // 몸만 보고 잡는다(장식 붙이기 전) — 앱 순서와 같다
    attachDecor(rig)
    rig.facing.simdPosition = SIMD3(0, lift, 0)
    let full = Int((Double(viewSize * renderScale) / cropSide).rounded())
    let big = snapshot(rig, camera: camera, size: full, yawDegrees: yaw)
    if uncropped { return big }
    let side = Double(full) * cropSide
    guard let cropped = big.cropping(to: CGRect(x: (Double(full) * cropX0).rounded(), y: (Double(full) * cropY0).rounded(),
                                                width: side.rounded(), height: side.rounded())) else { fail("자르기 실패") }
    return resized(cropped, viewSize, viewSize)
}

/// 512² 정면에서 눈 · 입 둘레(x 140–371, y 175–294)를 잘라 4배(가장 가까운 화소)로.
func eyeCrop(_ front: CGImage) -> CGImage {
    guard let c = front.cropping(to: CGRect(x: 140, y: 175, width: 232, height: 120)) else { fail("눈가 자르기 실패") }
    return resized(c, 232 * 4, 120 * 4, nearest: true)
}

/// 정면 512² 의 얼굴 상자 안에서 '짙은 순초록' 화소 수(R, B < 40 이고 G > R + 45 — 잘린 라벤더가 남긴 테).
func darkGreenFringeCount(_ front: CGImage) -> Int {
    let px = bytes(front, space: sRGB)
    var count = 0
    for y in 175..<295 { for x in 140..<372 {
        let o = (y * front.width + x) * 4
        let r = Int(px[o]), g = Int(px[o + 1]), b = Int(px[o + 2])
        if px[o + 3] == 255, r < 40, b < 40, g > r + 45, g < 150 { count += 1 }
    } }
    return count
}

func writePreview(into dir: String, label: CGImage, portraits: [(String, CGImage)]) {
    let fixed = IsulBody.fragment(output: IsulBody.bodyOutput)
    var front: CGImage?
    for (name, yaw) in [("front", 0.0), ("three-quarter", threeQuarterYaw), ("back", 180.0)] {
        let image = appView(fragment: fixed, yaw: yaw)
        if yaw == 0 { front = image }
        writePNG(image, toPath: "\(dir)/\(name).png")
    }
    let before = appView(fragment: IsulBody.fragment(output: legacyLinearOutput), yaw: 0)
    writePNG(before, toPath: "\(dir)/front-before.png")
    writePNG(eyeCrop(before), toPath: "\(dir)/eyes-4x-before.png")
    writePNG(eyeCrop(front!), toPath: "\(dir)/eyes-4x-after.png")
    print("[fringe] 얼굴 둘레 짙은 순초록 화소: 고침 전 \(darkGreenFringeCount(before)) · 고침 뒤 \(darkGreenFringeCount(front!))")
    writePNG(label, toPath: "\(dir)/label.png")
    for (e, p) in portraits {
        writePNG(p, toPath: "\(dir)/portrait-\(e).png")
        writePNG(resized(p, portraitSize * 4, portraitSize * 4, nearest: true), toPath: "\(dir)/portrait-\(e)-4x.png")
    }
    // 프레이밍: 지금 앱 카메라 화면(자르기 전 전체)에서 뚜껑 포함 위 끝 여백 — 부유 0 · +0.07.
    for lift in [Float(0), floatLift] {
        let full = appView(fragment: fixed, yaw: 0, lift: lift, uncropped: true)
        let box = alphaBox(bytes(full, space: sRGB), full.width, full.height, threshold: 8)
        print(String(format: "[frame] 부유 %+.2f: 장식 포함 위 끝 여백 %.3f(프레임 높이 비율, 0 미만이면 잘림)", lift, Double(box.2) / Double(full.height)))
    }
    print("[preview] \(dir)")
}

// MARK: - 실행

var args = Array(CommandLine.arguments.dropFirst())
while !args.isEmpty {
    let flag = args.removeFirst()
    guard let value = args.first else { fail("사용: [--out <폴더>] [--preview <폴더>]") }
    args.removeFirst()
    switch flag {
    case "--out": outDir = value
    case "--preview": previewDir = value
    default: fail("모르는 인자: \(flag)")
    }
}
guard FileManager.default.fileExists(atPath: modelPath) else { fail("저장소 루트에서 실행하라(\(modelPath) 없음)") }
_ = brushFont(size: 12)

let started = Date()
// 몸 상수 맞대기.
do {
    guard let scene = try? SCNScene(url: URL(fileURLWithPath: modelPath), options: nil) else { fail("모델을 못 읽었다") }
    var body: SCNNode?
    scene.rootNode.enumerateHierarchy { node, stop in if node.geometry != nil { body = node; stop.pointee = true } }
    guard let original = decodedTexture(body?.geometry?.materials.first?.diffuse.contents) else { fail("몸 디퓨즈 없음") }
    let measured = measuredSkinYRef(compositeDiffuse(original: original))
    print(String(format: "[body] 피부 기준 휘도 %.5f(상수 %.5f)", measured, IsulBody.skinYRef))
    guard abs(measured - IsulBody.skinYRef) < 5e-6 else { fail("피부 기준 휘도가 상수와 다르다 — IsulBody.skinYRef 를 고치고 앱도 같이") }
}

// 라벨: 굽고, 렌더는 쓴 PNG 를 다시 읽어 쓴다(앱이 번들 · 캐시에서 읽는 길과 같은 바이트).
let labelPath = "\(outDir)/\(characterID)-label.png"
writePNG(labelImage(), toPath: labelPath)
labelForRender = loadImage(labelPath)

// 장식 꼭대기 · 만들기 비용(앱 프레이밍 · 캐시 판단 근거).
do {
    let rig = makeRig(fragment: nil)
    let t0 = Date()
    let decor = IsulCap.make(probe: meshSurfaceProbe(rig.bodyNode))
    let cost = Date().timeIntervalSince(t0)
    let top = IsulCap.topY(decor)
    print(String(format: "[decor] 뚜껑 꼭대기 y %.4f(상수 %.4f) · 만들기 %.3f초", top, IsulCap.capTopY, cost))
    guard abs(Double(top) - IsulCap.capTopY) < 5e-4 else { fail("뚜껑 꼭대기 높이가 상수와 다르다 — IsulCap.capTopY 를 고치고 앱 프레이밍도 같이") }
}

let maps = renderPortraitMaps()
let prepared = expressions.map { preparePortrait(analyzePortrait($0), maps: maps) }
let layout = commonLayout(prepared)
var portraits: [(String, CGImage)] = []
for p in prepared {
    let image = composePortrait(p, decor: maps.decor, layout: layout)
    writePNG(image, toPath: "\(outDir)/\(characterID)-\(p.expression).png")
    portraits.append((p.expression, image))
}
if let previewDir { writePreview(into: previewDir, label: labelForRender!, portraits: portraits) }
print(String(format: "[done] 초상 %d장 + 라벨 — %.1f초", portraits.count, Date().timeIntervalSince(started)))
