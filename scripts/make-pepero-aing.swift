#!/usr/bin/env swift
// 빼빼로 아잉이(aing_pepero — 11-11 기간 선물, 빨간 빼빼로 상자에서 빼꼼) 그림 생성기 — 맥 초상 둘 + 상자 인쇄 판(텍스처 한 장)을 굽고,
// 앱 3D 마감(다음 단계)이 옮겨 쓸 **상자 · 막대 장식 코드**를 표시 구획(BEGIN/END pepero-decor)으로 담는다.
// 대표가 고른 2차 시안 P '상자에서 빼꼼'(결재 #d_Hx2nBIQIyBf3 — 시안 렌더러 pepero-aing/r2-box/render-pepero.swift 의 `peekBox` 갈래 ·
// out/P-*.png, 이름 없는 판 P2)을 옮겼다. 상자 · 막대 · 인쇄의 모양 · 색 · 자리 숫자는 시안 그대로이고 아래 '시안과 다른 것'만 다르다.
//
// 사용법(저장소 루트에서):
//   swift -O scripts/make-pepero-aing.swift                    산출물 3장을 저장소 Sources/check/Resources 에 쓴다. 같은 입력이면 같은 바이트.
//   swift -O scripts/make-pepero-aing.swift --out <폴더>       같은 3장을 <폴더> 바로 아래에 쓴다(저장소는 안 건드린다 — 결정성 검사용).
//   swift -O scripts/make-pepero-aing.swift --alt <폴더>       이름 없는 판('11.11') 3장을 <폴더>에 **같은 파일 이름**으로 더 쓴다 — 저장소에 넣지 않는다
//                                                             (정본 자리 ~/.claude/projects/-Users-yesung-check/pepero-aing/art-alt/ — 상표 문제가 생기면
//                                                             Storage 에 이 셋을 올려 앱 업데이트 없이 갈아 끼운다 · 폰 판도 여기서 가져간다).
//   swift -O scripts/make-pepero-aing.swift --preview <폴더>   앱 구도 3D 참고 렌더(정면 · 3/4 · 뒤 512², 3/4 팔 구멍 3배 크롭, --alt 면 이름 없는 판
//                                                             정면도)와 초상 4배를 <폴더>에 쓴다 — 저장소 밖. 세 인자는 같이 쓸 수 있다.
//   오프스크린 SCNRenderer(Metal) · CoreGraphics · CoreText 만 쓴다 — 화면에 창을 띄우지 않고 네트워크를 쓰지 않는다.
//   인쇄 글꼴 'BM 주아'(BMJUAOTF, macOS 내려받기 글꼴)가 없으면 **멈춘다**(다른 글꼴로 바꾸지 않는다 — 바이트가 달라진다).
//
// 입력(저장소, 읽기만): Sources/check/Resources/aing.scn(메시) · aing-neutral.png · aing-negative.png(192² 아잉 초상).
//   **몸은 원래 아잉이 그대로다** — 몸 재질 · 디퓨즈 · 셰이더를 바꾸지 않는다(시안의 보라 몸 셰이더 `purpleBody` 는 근사라 버렸다).
//   초상도 원래 아잉 초상 위에 장식 층(상자 + 막대)만 얹는다(이슬 makePortrait 의 장식 층과 같은 길 — 재색 없음).
// 출력(번들에는 이름 있는 판만, 폰 사본은 만들지 않는다 — 맥 먼저):
//   aing_pepero-neutral.png    192×192 RGBA 초상(아잉 초상 + 상자 · 막대 층, 후광 없음)
//   aing_pepero-negative.png   〃 (시무룩 — aing-negative.png 원본에서). 두 장은 같은 몸 배율 · 같은 몸 자리 · **같은 장식 자리**.
//   aing_pepero-box.png        상자 인쇄 판 1024×1024 불투명 RGB(A=255). 세 띠(위 → 아래): 앞면 · 뒷면 · 옆면 — 규약은 `PeperoDecor` 의
//                              `frontRows` · `backRows` · `sideRows` · `printCoord`. 띠 사이 16줄은 위아래 띠의 끝 줄을 되풀이한 여백(밉맵 번짐 막이).
//   (--alt) 같은 세 이름 — 앞면 '11.11' + 양옆 작은 빼빼로 그림 · 뒷면 '11.11' · 초상은 그 판으로 다시 굽는다. 판 규격 · 띠 자리는 같다.
//
// 시안과 다른 것:
//  ① 몸: 시안은 보라 몸 셰이더(lavender 근사 + 윤)였다 → 원래 아잉이 그대로(앱 기본 재질 · 초상 원본). 몸 재질을 안 건드리니 깜빡임 ·
//     졸기 · 울트라 교체 · 반응이 기본 아잉과 같은 길로 돈다.
//  ② 인쇄: 시안은 앞(1600×619) · 뒤(1200×464) · 옆(400×240) 세 그림이었다 → 한 장의 판(띠 셋). 글자 크기 · 테 · 그림자 · 띠 비율은 판 높이 비로
//     같으니 그림은 같다. 이름 없는 판은 이 한 장만 바꿔 끼우면 된다(앱 3D · 초상 둘 다 이 판을 읽는다).
//  ③ 팔 구멍(옆면 손잡이 구멍): 시안 3/4 에서 '흰 · 보라 물방울'로 읽혔다 — 원인 셋: (가) 구멍 타원(y −0.31 ± 0.335 · z −0.017 ± 0.205)이 팔 단면
//     (바깥 벽 |x| = 0.84 에서 y −0.616…−0.055 · z −0.161…0.126)보다 커 팔과 구멍 테 사이에 검은 틈이 남고, (나) 그 둘레에 크림색 '자른 면' 테
//     (e 0.86–0.97, 두께 약 0.03)를 칠해 흰 고리가 됐고, (다) 팔 아래 끝(−0.616)이 상자 바닥(−0.62)과 같은 높이라 구멍이 아래 둥근 모서리까지
//     먹어 들어가 물방울 꼬리처럼 열렸다. 고침(`paint` 의 팔 구멍): 구멍을 팔 단면을 담는 가장 작은 타원(y −0.336 ± 0.301 · z −0.016 ± 0.178 —
//     꼭대기 −0.035 로 위 노랑 띠 아래)으로 줄이고(생성기가 메시로 다시 재서 단면이 반지름 비 0.955 안에 드는지 맞댄다 — 지금 0.949),
//     자른 면 테를 짙은 판지색 가는 선(e 0.975–0.995)으로, 바깥 그늘을 얕게. (다)는 형상 문제라 인쇄로 못 고친다 — 앱 3D 가 고를 길은
//     아래 '앱이 할 일' 5 에 적었다.
//
// ── 앱이 할 일(맥 3D, 다음 단계) — 아래 이름을 그대로 옮긴다 ─────────────────────────────────────────────────────────────────────────
// 1) 몸: 아무것도 안 한다(기본 아잉 재질 그대로). 장식만 붙인다.
// 2) 인쇄 판: 디스크 캐시 → 번들 폴백(aing_pepero-box.png) → 조건부 요청(Storage game-art/pepero/box.png — 이슬 IsulArt 와 같은 길).
//    판 검사: 정사각 `sheetWidth` × `sheetHeight`(크기가 다르면 띠 자리가 어긋난다 — 받지 않는다). 초상 둘도 같은 길(neutral · negative).
// 3) 장식: `PeperoDecor.make(sheet:)` → 이름 `PeperoDecor.decorNodeName`("check.peperoDecor") 노드 하나(자식 상자 `check.pepero.box` +
//    막대 셋 `check.pepero.stick{L,R1,R2}`). **캐릭터 노드(aing.scn 메시 노드 — 변환이 단위라 물체 좌표 = 이 노드 좌표)의 자식**으로 붙인다 →
//    부유 · 살랑 · 요 회전을 따른다. 자리는 고정 상수라 몸 hitTest 가 필요 없다. 재질은 .constant(음영을 텍스처에 구웠다 — 몸 공간 고정 빛).
//    만들기 비용은 실행 로그 [decor] 줄(상자 굽기 2048×768 이 대부분 — 프로세스당 한 번 만들어 clone, 판이 바뀌면 다시).
//    얼굴 탐색 · 몸 클릭 hitTest · 리액션 진폭(bodyBoundingBox)에서 `decorNodeName` 노드 **아래 전부**를 뺀다(케이크 · 이슬 isDecor 자리).
// 4) 프레이밍: 장식 꼭대기(물체 좌표 y) `PeperoDecor.topY`. --preview 의 [frame] 줄이 지금 앱 카메라(몸만 보고 잡은 40°)의 위 여백을 보여 준다.
// 5) 팔: 아잉 팔(|x| 최대 0.962)이 상자(±0.84)보다 넓어 옆 벽을 뚫고 나온다. 인쇄로 그린 구멍은 정면 · 초상엔 안 보이고 3/4 · 옆에서만 보인다.
//    남은 형상 문제(팔 아래 끝이 상자 바닥과 같은 높이 — 3/4 에서 팔 끝이 상자 아래 선 밖으로 늘어진다) — 앱이 고를 길 셋:
//    (가) 지금 그대로(구멍이 아래 모서리까지 열린 손잡이 홈처럼 읽힘 — 시안 P 의 정면 비례를 지킨다, 이 생성기의 선택),
//    (나) 상자를 아래로 늘림(y0 −0.62 → −0.74 면 아래 둥근 모서리(r 0.10)가 팔 밑 −0.616 보다 아래로 — 구멍이 벽 안에 닫힌다. 대신 정면 상자가
//         0.12 커지고, 앞 · 뒤 면 비가 1.68 : 0.77 = 2.18 로 바뀌어 인쇄 판 띠 규약(frontRows · backRows)과 초상을 다시 굽는다),
//    (다) 벽에 진짜 구멍(형상에서 벽을 잘라냄 — 3/4 에서 팔이 구멍을 지나는 깊이가 보인다, 일이 큼).
//    반응이 배율(squash)을 **캐릭터 노드**에 걸면 장식도 같이 찌그러져 구멍 자리가 맞는다. **몸 메시 노드에만** 걸면 팔이 구멍 밖 벽을 뚫는다 — 확인할 것.
// 6) 초상 파일 이름은 `<id>-<neutral|negative>.png`(금 · 무지개 · 케이크 · 이슬 규약). 폰 `AingCharacterArt.knownIDs` 에는 이번에 넣지 않는다.
//
// 이 스크립트는 앱 모듈을 링크하지 않는다.

import AppKit
import SceneKit
import simd

// MARK: - 상수(생성기 전용)

let resourceDir = "Sources/check/Resources"
let modelPath = "\(resourceDir)/aing.scn"
let characterID = "aing_pepero"
let expressions = ["neutral", "negative"]

let printFontName = "BMJUAOTF"                       // BM 주아(macOS 내려받기 글꼴 — 시안과 같다)
let printSubFontName = "AppleSDGothicNeo-ExtraBold"  // '아잉 에디션'

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

var outDir = resourceDir
var altDir: String?
var previewDir: String?

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(("make-pepero-aing: " + message + "\n").data(using: .utf8)!)
    exit(1)
}

// MARK: - 그림 도구

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

func loadImage(_ path: String) -> CGImage {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fail("그림을 못 읽었다: \(path)") }
    return image
}

func bytes(_ image: CGImage, space: CGColorSpace = sRGB) -> [UInt8] {
    let w = image.width, h = image.height
    var px = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    return px
}

func makeImage(_ px: [UInt8], _ w: Int, _ h: Int) -> CGImage {
    var p = px
    let ctx = CGContext(data: &p, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: sRGB,
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

@inline(__always) func srgbToLinear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
@inline(__always) func linearToSrgb(_ v: Double) -> Double { v <= 0.0031308 ? v * 12.92 : 1.055 * pow(v, 1 / 2.4) - 0.055 }
func cg(_ c: SIMD3<Double>, _ a: Double = 1) -> CGColor { CGColor(srgbRed: c.x, green: c.y, blue: c.z, alpha: a) }
func ns(_ c: SIMD3<Double>, _ a: Double = 1) -> NSColor { NSColor(srgbRed: c.x, green: c.y, blue: c.z, alpha: a) }

// BEGIN pepero-decor — 다음 단계(맥 3D 마감)가 이 구획을 글자 그대로 옮긴다(이슬 IsulCap 과 같은 길). 여기를 고치면 앱도 같이.

/// 빼빼로 상자 + 굵은 빼빼로 셋(시안 P '상자에서 빼꼼'). 전부 캐릭터 노드(= aing.scn 메시 노드, 변환 단위 — 물체 좌표, +z 앞 · +y 위) 기준 고정 자리.
/// 매개 곡면 → SCNGeometry + 음영을 구운 텍스처(몸 공간 고정 빛), unlit. 상자 바깥 벽의 인쇄는 인쇄 판(aing_pepero-box.png)에서 읽는다.
enum PeperoDecor {
    static let decorNodeName = "check.peperoDecor"
    static let boxNodeName = "check.pepero.box"

    // MARK: 상자 — 위가 열린 둥근 모서리 상자(직육면체의 민코프스키 둥글림)
    /// 가로 ±a(x) · 깊이 ±b(z, +z = 앞면) · 높이 y0…y1(위 테 꼭대기) · 모서리 반지름 r · 벽 두께 wall. 몸(aing.scn)은 y −0.847…0.849 ·
    /// 깊이 ±0.73 · 팔 포함 가로 ±0.962 — 상자 위 테(0.03)부터 위가 얼굴이다. 바닥은 몸 아래 끝보다 0.23 높다(앱 카메라는 위에서 내려다봐
    /// 앞 벽이 가린다 — 아래에서 보는 구도가 생기면 몸이 바닥을 뚫고 보인다).
    static let a: Float = 0.84
    static let b: Float = 0.765
    static let y0: Float = -0.62
    static let y1: Float = 0.03
    static let r: Float = 0.10
    static let wall: Float = 0.034
    /// 굽기 텍스처의 둘레(u) 해상도를 앞면에 몰아 준다(둘레 길이 가중 — 앞 3.2 : 뒤 1.4 : 옆 1.0 : 모서리 2.5).
    static let frontWeight: Float = 3.2
    static let backWeight: Float = 1.4
    static let sideWeight: Float = 1.0
    static let cornerWeight: Float = 2.5
    static let bakeWidth = 2048
    static let bakeHeight = 768
    static let meshU = 220
    static let meshV = 140

    // MARK: 인쇄 판 규약(aing_pepero-box.png)
    /// 판은 sheetWidth × sheetHeight 불투명 그림. 위(행 0)부터 앞면 · 뒷면 · 옆면 띠, 띠 사이 16줄은 이웃 띠 끝 줄을 되풀이한 여백.
    /// 앞 · 뒤 띠의 가로세로 비(1024 : 396 = 2.586)는 상자 앞면 2a : (y1 − y0) = 1.68 : 0.65 와 같다. 옆 띠(1024 : 200)는 옆면(1.53 : 0.65)보다
    /// 가로로 2.2배 늘어난 자리라 글자를 넣지 않는다(가로 띠 무늬만).
    static let sheetWidth = 1024
    static let sheetHeight = 1024
    static let frontRows = 0..<396
    static let backRows = 412..<808
    static let sideRows = 824..<1024

    enum Face { case front, back, side }

    /// 바깥 벽 점(상자 자기 좌표 = 물체 좌표) → (면, s, t). s = 그 면을 **바깥에서 볼 때** 왼 0 → 오른 1, t = 위 테 y1 에서 0 → 바닥 y0 에서 1.
    /// 면 고르기: 둥근 모서리에서는 앞 · 뒤 평면과 옆 평면 중 더 가까운 쪽(dz ≥ dx 면 앞 · 뒤). 앞 · 뒤 s 는 x 를 ±a 전체로, 옆 s 는 z 를 ±b 전체로 편다.
    static func printCoord(_ p: SIMD3<Float>) -> (face: Face, s: Double, t: Double) {
        let t = Double((y1 - p.y) / (y1 - y0))
        let dz = abs(p.z) - (b - r), dx = abs(p.x) - (a - r)
        if dz >= dx {
            let s = Double((p.x + a) / (2 * a))
            return p.z >= 0 ? (.front, s, t) : (.back, 1 - s, t)
        }
        let s = Double((p.z + b) / (2 * b))
        return (.side, p.x > 0 ? 1 - s : s, t)
    }

    /// (면, s, t) → 판 화소 좌표(가로 0…sheetWidth, 세로 0…sheetHeight, 위가 0). 띠 안 반 화소로 묶는다(여백까지 안 나간다).
    static func sheetPixel(_ face: Face, _ s: Double, _ t: Double) -> (x: Double, y: Double) {
        let rows: Range<Int>
        switch face {
        case .front: rows = frontRows
        case .back: rows = backRows
        case .side: rows = sideRows
        }
        let x = min(max(s, 0), 1) * Double(sheetWidth)
        let y = Double(rows.lowerBound) + min(max(t, 0), 1) * Double(rows.count)
        return (min(max(x, 0.5), Double(sheetWidth) - 0.5), min(max(y, Double(rows.lowerBound) + 0.5), Double(rows.upperBound) - 0.5))
    }

    // MARK: 팔 구멍(옆면 ±x — 몸 팔이 벽을 뚫고 나오는 자리)
    /// 옆 벽 위 (y, z) 타원: 가운데 (holeY, holeZ) · 반지름 (holeHY, holeHZ). 바깥 벽(|x| = a)에서 팔 단면은 y −0.616…−0.055 · z −0.161…0.126
    /// — 그것을 담는 가장 작은 타원(꼭대기 −0.035 는 위 노랑 띠 아래). 생성기가 메시로 다시 재서 단면 전체가 반지름 비 holeFit 안에 드는지 맞댄다.
    static let holeY: Float = -0.336
    static let holeZ: Float = -0.016
    static let holeHY: Float = 0.301
    static let holeHZ: Float = 0.178
    static let holeFit: Float = 0.955

    // MARK: 색(sRGB 16진)
    static let red = 0xD7182A
    static let redDeep = 0x9E0E1C
    static let board = 0xEFE6D6
    static let boardDeep = 0x8C7F6E
    static let holeInk = 0x1E0A08
    static let cutEdge = 0xB08A62

    // MARK: 막대 — 상자 안 바닥 가까이에서 솟아 머리 옆으로(왼쪽 하나, 오른쪽 둘). 코팅(밀크 초코) 끝이 상자 테 위로 보인다.
    struct Stick {
        let name: String
        let base: SIMD3<Float>      // 아래 끝(물체 좌표)
        let dir: SIMD3<Float>       // 축 방향(정규화 전)
        let length: Float
        let spin: Float             // 자기 축 돌림(라디안 — 코팅 끝 물결 자리)
    }
    static let sticks: [Stick] = [
        Stick(name: "check.pepero.stickL", base: SIMD3(-0.60, -0.50, -0.50), dir: SIMD3(-0.11, 1, -0.02), length: 1.56, spin: 0.0),
        Stick(name: "check.pepero.stickR1", base: SIMD3(0.62, -0.50, -0.48), dir: SIMD3(0.10, 1, -0.02), length: 1.60, spin: 1.1),
        Stick(name: "check.pepero.stickR2", base: SIMD3(0.36, -0.50, -0.64), dir: SIMD3(0.03, 1, -0.06), length: 1.50, spin: 2.3),
    ]
    static let stickRadius: Float = 0.058       // 비스킷 심
    static let stickCoatThick: Float = 0.024    // 코팅 두께(코팅 반지름 0.082)
    static let stickCoatFrac: Float = 0.76      // 아래 끝부터 코팅이 덮는 비율(나머지 = 비스킷 손잡이)
    static let stickWave: Float = 0.014         // 코팅 끝 물결 높이
    static let coatBase = 0x7A4423
    static let coatDeep = 0x3B1B0B
    static let coatHi = 0xFFE4CC
    static let biscuit = 0xE7AE62
    static let biscuitDeep = 0xC48543
    static let biscuitEnd = 0xF0C98E
    /// 장식 꼭대기(물체 좌표 y) — 앱 프레이밍이 쓴다. 생성기가 실행 때 다시 재서 맞댄다.
    static let topY: Float = 1.0951

    // MARK: 구운 조명
    /// ambient(바탕 밝기) · spec(반짝 세기) · gloss(날카로움) · wrap(감싸는 빛) · rim(가장자리 밝은 테) · axis(원기둥 축 — 길이 방향 곧은 반짝) · tint(반짝 색).
    struct Look {
        var ambient = 0.62, spec = 0.25, gloss = 24.0, wrap = 0.4, rim = 0.0
        var axis: SIMD3<Double>? = nil
        var tint = SIMD3<Double>(1, 1, 1)
    }
    static let keyLight = simd_normalize(SIMD3<Double>(-0.30, 0.85, 0.45))
    static let viewLight = simd_normalize(SIMD3<Double>(0, 0.30, 1))
    static let fillLight = simd_normalize(SIMD3<Double>(0.70, 0.25, 0.65))
    static let paper = Look(ambient: 0.60, spec: 0.34, gloss: 34, wrap: 0.40, rim: 0.12, tint: SIMD3(1, 0.95, 0.92))
    static let cardboard = Look(ambient: 0.78, spec: 0.04, gloss: 8, wrap: 0.6, rim: 0.0)

    static func toLinear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
    static func lin(_ hex: Int) -> SIMD3<Double> {
        SIMD3(toLinear(Double((hex >> 16) & 255) / 255), toLinear(Double((hex >> 8) & 255) / 255), toLinear(Double(hex & 255) / 255))
    }
    static func srgbByte(_ v: Double) -> UInt8 {
        let c = min(max(v, 0), 1)
        let e = c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055
        return UInt8(max(0, min(255, (e * 255).rounded())))
    }
    static func smooth(_ e0: Double, _ e1: Double, _ x: Double) -> Double { let t = min(max((x - e0) / (e1 - e0), 0), 1); return t * t * (3 - 2 * t) }
    static func smoothF(_ e0: Float, _ e1: Float, _ x: Float) -> Float { let t = min(max((x - e0) / (e1 - e0), 0), 1); return t * t * (3 - 2 * t) }
    /// 결정적 해시(0…1) — 비스킷 고운 점.
    static func hash2(_ p: Int, _ q: Int, _ salt: Int = 0) -> Double {
        var h = UInt64(bitPattern: Int64(p &* 73_856_093 ^ q &* 19_349_663 ^ salt &* 83_492_791))
        h ^= h >> 33; h = h &* 0xff51afd7ed558ccd; h ^= h >> 33; h = h &* 0xc4ceb9fe1a85ec53; h ^= h >> 33
        return Double(h % 1_000_003) / 1_000_003
    }

    static func lit(_ albedo: SIMD3<Double>, _ n: SIMD3<Double>, _ look: Look) -> SIMD3<Double> {
        let ndl = simd_dot(n, keyLight)
        let diff = min(max((ndl + look.wrap) / (1 + look.wrap), 0), 1)
        let ao = 1 - 0.22 * max(-n.y, 0)
        var c = albedo * (look.ambient + (1 - look.ambient) * diff) * ao
        func flat(_ v: SIMD3<Double>) -> SIMD3<Double> {
            guard let ax = look.axis else { return v }
            let p = v - ax * simd_dot(v, ax)
            return simd_length(p) < 1e-6 ? v : simd_normalize(p)
        }
        c += look.tint * (pow(max(simd_dot(n, flat(simd_normalize(keyLight + viewLight))), 0), look.gloss) * look.spec)
        c += look.tint * (pow(max(simd_dot(n, flat(simd_normalize(fillLight + viewLight))), 0), look.gloss * 1.4) * look.spec * 0.35)
        if look.rim > 0 { c += (albedo * 1.8 + look.tint * 0.15) * (pow(1 - max(simd_dot(n, viewLight), 0), 3) * look.rim) }
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
        while simd_length(n) < 1e-9 && nudge < 0.1 { n = at(v < 0.5 ? v + nudge : v - nudge); nudge *= 2 }
        return simd_length(n) < 1e-12 ? SIMD3(0, 1, 0) : simd_normalize(n)
    }

    /// 매개 곡면 노드: 격자 nu × nv 메시 + texW × texH 구운 텍스처(텍셀마다 albedo 2×2 표본 평균 → 그 자리 법선 · look 으로 조명).
    static func pieceNode(name: String, nu: Int, nv: Int, closedU: Bool, texW: Int, texH: Int, pos: SurfaceFn,
                          albedo: (Double, Double, SIMD3<Float>) -> SIMD3<Double>, lookAt: (Double, Double, SIMD3<Float>) -> Look,
                          transform: simd_float4x4) -> SCNNode {
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
            let p = j * row + i, q = p + 1, s = p + row, t = s + 1
            idx += [p, q, s, q, t, s]
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
            let uD = (Double(x) + 0.5) / Double(texW), vD = (Double(y) + 0.5) / Double(texH)
            let nw = rot * surfaceNormal(pos, Float(uD), Float(vD), closedU: closedU)
            let c = lit(acc / 4, simd_normalize(SIMD3<Double>(Double(nw.x), Double(nw.y), Double(nw.z))), lookAt(uD, vD, pos(Float(uD), Float(vD))))
            let o = (y * texW + x) * 4
            px[o] = srgbByte(c.x); px[o + 1] = srgbByte(c.y); px[o + 2] = srgbByte(c.z)
        } }
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let ctx = CGContext(data: &px, width: texW, height: texH, bitsPerComponent: 8, bytesPerRow: texW * 4, space: space,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
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

    // MARK: 상자 곡면
    enum Region { case outer, bottom, lip, inner, innerBottom }

    /// 둘레(u: 앞 가운데 → 오른쪽 → 뒤 → 왼쪽 → 앞 가운데) × 단면(v: 바닥 가운데 → 아래 둥근 모서리 → 바깥 벽 → 위 테(반원 입술) → 안쪽 벽 → 안쪽 바닥 가운데).
    struct Surface {
        let segs: [(len: Float, p0: SIMD2<Float>, p1: SIMD2<Float>, ang0: Float, ang1: Float)]
        let total: Float
        static let vCuts: [Float] = [0.05, 0.10, 0.62, 0.70, 0.94, 1.0]
        static let regions: [Region] = [.bottom, .outer, .outer, .lip, .inner, .innerBottom]
        init() {
            let ca = a - r, cb = b - r, ql = Float.pi / 2 * r
            var list: [(Float, SIMD2<Float>, SIMD2<Float>, Float, Float)] = []
            list.append((ca * frontWeight, SIMD2(0, cb), SIMD2(ca, cb), .pi / 2, .pi / 2))
            list.append((ql * cornerWeight, SIMD2(ca, cb), SIMD2(ca, cb), .pi / 2, 0))
            list.append((2 * cb * sideWeight, SIMD2(ca, cb), SIMD2(ca, -cb), 0, 0))
            list.append((ql * cornerWeight, SIMD2(ca, -cb), SIMD2(ca, -cb), 0, -.pi / 2))
            list.append((2 * ca * backWeight, SIMD2(ca, -cb), SIMD2(-ca, -cb), -.pi / 2, -.pi / 2))
            list.append((ql * cornerWeight, SIMD2(-ca, -cb), SIMD2(-ca, -cb), -.pi / 2, -.pi))
            list.append((2 * cb * sideWeight, SIMD2(-ca, -cb), SIMD2(-ca, cb), -.pi, -.pi))
            list.append((ql * cornerWeight, SIMD2(-ca, cb), SIMD2(-ca, cb), -.pi, -1.5 * .pi))
            list.append((ca * frontWeight, SIMD2(-ca, cb), SIMD2(0, cb), .pi / 2, .pi / 2))
            segs = list.map { (len: $0.0, p0: $0.1, p1: $0.2, ang0: $0.3, ang1: $0.4) }
            total = segs.reduce(0) { $0 + $1.len }
        }
        /// 둘레 u → (가운데 사각형 위 점, 바깥 법선(x, z)).
        func perimeter(_ u: Float) -> (SIMD2<Float>, SIMD2<Float>) {
            var x = (u - floor(u)) * total
            for sg in segs {
                if x <= sg.len {
                    let t = sg.len > 0 ? min(max(x / sg.len, 0), 1) : 0
                    let ang = sg.ang0 + (sg.ang1 - sg.ang0) * t
                    return (sg.p0 + (sg.p1 - sg.p0) * t, SIMD2(cos(ang), sin(ang)))
                }
                x -= sg.len
            }
            let sg = segs[segs.count - 1]
            return (sg.p1, SIMD2(cos(sg.ang1), sin(sg.ang1)))
        }
        func region(_ v: Float) -> Region {
            for (i, c) in Surface.vCuts.enumerated() where v <= c { return Surface.regions[i] }
            return Surface.regions[Surface.regions.count - 1]
        }
        func pos(_ u: Float, _ v: Float) -> SIMD3<Float> {
            let (c, n) = perimeter(u)
            func at(_ d: Float, _ y: Float, scale: Float = 1) -> SIMD3<Float> { let q = (c + n * d) * scale; return SIMD3(q.x, y, q.y) }
            func k(_ lo: Float, _ hi: Float) -> Float { min(max((v - lo) / (hi - lo), 0), 1) }
            let cuts = Surface.vCuts
            let rl = wall / 2, ri = r - wall
            if v <= cuts[0] { return at(0, y0, scale: k(0, cuts[0])) }
            if v <= cuts[1] { let ph = -Float.pi / 2 + k(cuts[0], cuts[1]) * Float.pi / 2; return at(r * cos(ph), y0 + r + r * sin(ph)) }
            if v <= cuts[2] { return at(r, y0 + r + k(cuts[1], cuts[2]) * (y1 - rl - y0 - r)) }
            if v <= cuts[3] { let ps = k(cuts[2], cuts[3]) * Float.pi; return at(r - rl + rl * cos(ps), y1 - rl + rl * sin(ps)) }
            if v <= cuts[4] { return at(ri, (y1 - rl) + k(cuts[3], cuts[4]) * ((y0 + wall) - (y1 - rl))) }
            return at(ri, y0 + wall, scale: 1 - k(cuts[4], 1))
        }
    }

    /// 인쇄 판 표본기(sRGB 바이트 → 선형, 쌍선형). 판 크기가 규약과 다르면 nil.
    struct SheetSampler {
        let px: [UInt8]
        init?(_ image: CGImage) {
            guard image.width == sheetWidth, image.height == sheetHeight else { return nil }
            var p = [UInt8](repeating: 0, count: sheetWidth * sheetHeight * 4)
            let ctx = CGContext(data: &p, width: sheetWidth, height: sheetHeight, bitsPerComponent: 8, bytesPerRow: sheetWidth * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: sheetWidth, height: sheetHeight))
            px = p
        }
        func sample(_ face: Face, _ s: Double, _ t: Double) -> SIMD3<Double> {
            let (x, y) = sheetPixel(face, s, t)
            let fx = x - 0.5, fy = y - 0.5
            let ix = min(Int(fx), sheetWidth - 2), iy = min(Int(fy), sheetHeight - 2)
            let ax = fx - Double(ix), ay = fy - Double(iy)
            func at(_ cx: Int, _ cy: Int) -> SIMD3<Double> {
                let o = (cy * sheetWidth + cx) * 4
                return SIMD3(toLinear(Double(px[o]) / 255), toLinear(Double(px[o + 1]) / 255), toLinear(Double(px[o + 2]) / 255))
            }
            let top = at(ix, iy) * (1 - ax) + at(ix + 1, iy) * ax
            let bot = at(ix, iy + 1) * (1 - ax) + at(ix + 1, iy + 1) * ax
            return top * (1 - ay) + bot * ay
        }
    }

    /// 상자 구역별 바탕색(선형): 바깥 벽 = 인쇄 판(옆면은 한 단 어둡게 + 팔 구멍) · 바닥 짙은 빨강 · 위 테 흰 판지 · 안쪽 판지(깊을수록 그늘).
    static func paint(_ sheet: SheetSampler) -> (Region, SIMD3<Float>) -> SIMD3<Double> {
        let redDeepL = lin(redDeep), boardL = lin(board), boardDeepL = lin(boardDeep)
        let holeL = lin(holeInk), cutL = lin(cutEdge)
        return { region, p in
            switch region {
            case .outer:
                let (face, s, t) = printCoord(p)
                guard face == .side else { return sheet.sample(face, s, t) }
                var c = sheet.sample(face, s, t) * 0.92
                // 팔 구멍: 바깥 얕은 그늘 → 짙은 판지색 가는 자른 면 → 어두운 속(팔이 이 안을 채운다).
                let ey = Double((p.y - holeY) / holeHY), ez = Double((p.z - holeZ) / holeHZ)
                let e = (ey * ey + ez * ez).squareRoot()
                c = c * (1 - 0.22 * (1 - smooth(1.0, 1.10, e)))
                c = c + (cutL - c) * (1 - smooth(0.975, 0.995, e))
                c = c + (holeL - c) * (1 - smooth(Double(holeFit), Double(holeFit) + 0.02, e))
                return c
            case .bottom: return redDeepL
            case .lip: return boardL
            case .inner:
                let depth = Double((y1 - p.y) / (y1 - y0))
                return boardL + (boardDeepL - boardL) * min(1, depth * 1.25)
            case .innerBottom: return boardDeepL * 0.8
            }
        }
    }

    static func boxNode(_ sheet: SheetSampler) -> SCNNode {
        let surf = Surface()
        let albedo = paint(sheet)
        return pieceNode(name: boxNodeName, nu: meshU, nv: meshV, closedU: true, texW: bakeWidth, texH: bakeHeight,
                         pos: { u, v in surf.pos(u, v) },
                         albedo: { _, v, p in albedo(surf.region(Float(v)), p) },
                         lookAt: { _, v, _ in
                             switch surf.region(Float(v)) { case .inner, .innerBottom, .lip: return cardboard
                             default: return paper }
                         }, transform: matrix_identity_float4x4)
    }

    // MARK: 막대 곡면
    /// 막대 한 개: 자기 축 +y, 원점 = 아래 끝. 아래부터 stickCoatFrac 만큼 밀크 초코 코팅(끝 물결), 나머지 위쪽이 비스킷 손잡이(둥근 끝).
    static func stickNode(_ st: Stick) -> SCNNode {
        let q = simd_quatf(from: SIMD3(0, 1, 0), to: simd_normalize(st.dir)) * simd_quatf(angle: st.spin, axis: SIMD3(0, 1, 0))
        var transform = simd_float4x4(q)
        transform.columns.3 = SIMD4(st.base.x, st.base.y, st.base.z, 1)
        let rb = stickRadius, rc = stickRadius + stickCoatThick
        let sy0: Float = 0, sy1 = st.length
        let eTop = rb * 0.45
        let vA: Float = 0.05, vB: Float = 0.955, vC: Float = 0.978
        let edgeMean = sy0 + stickCoatFrac * st.length
        func edge(_ u: Float) -> Float { edgeMean + stickWave * (0.65 * sin(2 * .pi * u * 3 + 0.6) + 0.35 * sin(2 * .pi * u * 5 + 2.0)) }
        let pos: SurfaceFn = { u, v in
            var rr: Float, y: Float
            if v < vA {
                let phi = -Float.pi / 2 + (v / vA) * (Float.pi / 2)
                rr = rc * cos(phi); y = sy0 + rc + rc * sin(phi)
            } else if v < vB {
                y = (sy0 + rc) + (v - vA) / (vB - vA) * ((sy1 - eTop) - (sy0 + rc))
                let e = edge(u)
                let k = smoothF(e - 0.0035, e + 0.0035, y)
                let lip = 0.0022 * (1 - smoothF(0, 0.012, abs(y - (e - 0.006))))
                rr = rc + (rb - rc) * k + lip * (1 - k)
            } else if v < vC {
                let phi = (v - vB) / (vC - vB) * (Float.pi / 2)
                rr = rb - eTop + eTop * cos(phi); y = sy1 - eTop + eTop * sin(phi)
            } else {
                rr = (rb - eTop) * (1 - (v - vC) / (1 - vC)); y = sy1
            }
            let ang = 2 * Float.pi * u
            return SIMD3(rr * sin(ang), y, rr * cos(ang))
        }
        let coatC = lin(coatBase), coatD = lin(coatDeep)
        let bisc = lin(biscuit), biscD = lin(biscuitDeep), biscE = lin(biscuitEnd)
        func coated(_ u: Double, _ p: SIMD3<Float>) -> Double { 1 - smooth(-0.002, 0.002, Double(p.y - edge(Float(u)))) }
        let ax = simd_normalize(SIMD3<Double>(Double(transform.columns.1.x), Double(transform.columns.1.y), Double(transform.columns.1.z)))
        let coatLook = Look(ambient: 0.52, spec: 0.80, gloss: 48, wrap: 0.30, rim: 0.35, axis: ax, tint: lin(coatHi))
        let biscLook = Look(ambient: 0.66, spec: 0.06, gloss: 10, wrap: 0.50, rim: 0.0, axis: ax)
        return pieceNode(name: st.name, nu: 64, nv: 300, closedU: true, texW: 256, texH: 1024, pos: pos,
                         albedo: { u, v, p in
                             let k = coated(u, p)
                             let ridge = pow(abs(cos(u * 2 * .pi * 9)), 8)
                             let iu = Int(u * 220), iy = Int(Double(p.y) * 600)
                             var bc = bisc + (biscD - bisc) * (0.25 * ridge + 0.35 * hash2(iu, iy, 5) * (hash2(iu, iy, 6) > 0.85 ? 1 : 0))
                             if v > Double(vB) { bc = bc + (biscE - bc) * smooth(Double(vB), Double(vC) + 0.01, v) }
                             let cc = coatC + (coatD - coatC) * 0.12 * smooth(Double(edgeMean), Double(sy0), Double(p.y))
                             return bc + (cc - bc) * k
                         },
                         lookAt: { u, _, p in coated(u, p) > 0.5 ? coatLook : biscLook }, transform: transform)
    }

    /// 장식 한 벌(상자 + 막대 셋). 판 크기가 규약과 다르면 nil(앱은 번들 판으로 되돌린다).
    static func make(sheet: CGImage) -> SCNNode? {
        guard let sampler = SheetSampler(sheet) else { return nil }
        let root = SCNNode()
        root.name = decorNodeName
        root.addChildNode(boxNode(sampler))
        for st in sticks { root.addChildNode(stickNode(st)) }
        return root
    }

    /// 장식 꼭대기(물체 좌표 y) — 정점을 자기 변환으로 옮겨 잰다.
    static func measuredTopY(_ decor: SCNNode) -> Float {
        var top: Float = -.infinity
        decor.enumerateHierarchy { node, _ in
            guard let src = node.geometry?.sources(for: .vertex).first else { return }
            let m = decor.simdConvertTransform(node.simdTransform, from: node.parent)
            src.data.withUnsafeBytes { raw in
                for i in 0..<src.vectorCount {
                    let o = src.dataOffset + i * src.dataStride
                    let p = SIMD4<Float>(raw.loadUnaligned(fromByteOffset: o, as: Float.self), raw.loadUnaligned(fromByteOffset: o + 4, as: Float.self),
                                         raw.loadUnaligned(fromByteOffset: o + 8, as: Float.self), 1)
                    top = max(top, (m * p).y)
                }
            }
        }
        return top
    }
}

// END pepero-decor

// MARK: - 상자 인쇄 판(생성기 전용 — 앱은 PNG 를 읽는다)

/// 인쇄 한 면(글자는 일반 굵은 한글 글꼴 — 롯데 로고 모양을 베끼지 않는다). 시안 `BoxPrint` 그대로.
struct BoxPrint {
    var text = "빼빼로"
    var sub = ""
    var bg = SIMD3<Double>(0.843, 0.094, 0.165)            // #D7182A
    var ink = SIMD3<Double>(1, 1, 1)
    var outline = SIMD3<Double>(1.0, 0.84, 0.25)            // 노랑 테
    var outlineWidth = 0.045
    var shadow = SIMD3<Double>(0.45, 0.02, 0.07)
    var band = SIMD3<Double>(1.0, 0.82, 0.22)               // 위 · 아래 노랑 띠
    var bandTop = 0.085, bandBottom = 0.060                 // 띠 두께(면 높이 비)
    var textScale = 0.56                                    // 글자 높이(면 높이 비)
    var maxWidth = 0.86                                     // 글자 폭 상한(면 폭 비)
    var textCY = 0.50                                       // 글자 가운데 높이(아래 0 → 위 1)
    var icons = false                                       // 글자 양옆 작은 빼빼로 그림
    var kern = 0.02
}

func printFont(_ name: String, _ size: CGFloat) -> NSFont {
    guard let f = NSFont(name: name, size: size) else { fail("인쇄 글꼴 \(name) 이 없다 — 글꼴 책에서 내려받고 다시(다른 글꼴로 바꾸지 않는다)") }
    return f
}

/// 작은 빼빼로 그림(이름 없는 판 앞면 양옆): 비스킷 막대 + 코팅 + 반짝 줄. a → b, a 쪽이 코팅.
func drawStickIcon(_ ctx: CGContext, from a: CGPoint, to b: CGPoint, width: CGFloat, coatFrac: CGFloat = 0.72) {
    ctx.saveGState()
    ctx.setLineCap(.round)
    ctx.setStrokeColor(CGColor(srgbRed: 0.93, green: 0.74, blue: 0.45, alpha: 1)); ctx.setLineWidth(width)
    ctx.move(to: a); ctx.addLine(to: b); ctx.strokePath()
    let m = CGPoint(x: a.x + (b.x - a.x) * coatFrac, y: a.y + (b.y - a.y) * coatFrac)
    ctx.setStrokeColor(cg(SIMD3(0.42, 0.21, 0.10))); ctx.setLineWidth(width * 1.32)
    ctx.move(to: a); ctx.addLine(to: m); ctx.strokePath()
    let dx = b.x - a.x, dy = b.y - a.y, len = (dx * dx + dy * dy).squareRoot()
    let nx = -dy / len * width * 0.28, ny = dx / len * width * 0.28
    ctx.setStrokeColor(CGColor(srgbRed: 1, green: 0.92, blue: 0.84, alpha: 0.75)); ctx.setLineWidth(width * 0.22)
    ctx.move(to: CGPoint(x: a.x + nx + dx * 0.08, y: a.y + ny + dy * 0.08)); ctx.addLine(to: CGPoint(x: m.x + nx - dx * 0.05, y: m.y + ny - dy * 0.05))
    ctx.strokePath()
    ctx.restoreGState()
}

func boxPrintImage(_ p: BoxPrint, w W: Int, h H: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.setLineJoin(.round); ctx.setMiterLimit(1.5)   // 글자 테 · 그림자 획의 뾰족 모서리 가시 막기
    let w = CGFloat(W), h = CGFloat(H)
    ctx.setFillColor(cg(p.bg)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    let gr = CGGradient(colorsSpace: sRGB, colors: [cg(p.bg * 1.08 + 0.02), cg(p.bg * 0.86)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gr, start: CGPoint(x: 0, y: h), end: CGPoint(x: 0, y: 0), options: [])
    if p.bandTop > 0 {
        let bh = h * CGFloat(p.bandTop)
        ctx.setFillColor(cg(p.band)); ctx.fill(CGRect(x: 0, y: h - bh, width: w, height: bh))
        ctx.setFillColor(cg(SIMD3(1, 1, 1))); ctx.fill(CGRect(x: 0, y: h - bh - h * 0.022, width: w, height: h * 0.012))
    }
    if p.bandBottom > 0 {
        let bh = h * CGFloat(p.bandBottom)
        ctx.setFillColor(cg(p.band)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: bh))
        ctx.setFillColor(cg(SIMD3(1, 1, 1))); ctx.fill(CGRect(x: 0, y: bh + h * 0.010, width: w, height: h * 0.012))
    }
    if p.icons {
        drawStickIcon(ctx, from: CGPoint(x: w * 0.060, y: h * 0.24), to: CGPoint(x: w * 0.150, y: h * 0.78), width: h * 0.075)
        drawStickIcon(ctx, from: CGPoint(x: w * 0.940, y: h * 0.24), to: CGPoint(x: w * 0.850, y: h * 0.78), width: h * 0.075)
    }
    guard !p.text.isEmpty else { return ctx.makeImage()! }
    let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = nsCtx
    var size = h * CGFloat(p.textScale) * 1.18
    var font = printFont(printFontName, size)
    func attrs(_ extra: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
        var at: [NSAttributedString.Key: Any] = [.font: font, .kern: size * CGFloat(p.kern)]
        for (k, v) in extra { at[k] = v }
        return at
    }
    func glyphBox(_ s: NSAttributedString) -> CGRect {
        s.boundingRect(with: NSSize(width: 100_000, height: 100_000), options: [.usesLineFragmentOrigin, .usesDeviceMetrics])
    }
    // 글리프 실제 높이가 textScale·h, 폭이 maxWidth·w 를 넘지 않게 맞춘다.
    for _ in 0..<2 {
        let gb = glyphBox(NSAttributedString(string: p.text, attributes: attrs([:])))
        let k = min(h * CGFloat(p.textScale) / max(gb.height, 1), w * CGFloat(p.maxWidth) / max(gb.width, 1))
        size *= k; font = printFont(printFontName, size)
    }
    let gb = glyphBox(NSAttributedString(string: p.text, attributes: attrs([:])))
    let hasSub = !p.sub.isEmpty
    let cy = h * CGFloat(p.textCY) + (hasSub ? h * 0.06 : 0)
    let origin = NSPoint(x: w * 0.5 - gb.midX, y: cy - gb.midY)
    let sw = CGFloat(p.outlineWidth) * 100 * 2.8
    NSAttributedString(string: p.text, attributes: attrs([.foregroundColor: ns(p.shadow), .strokeColor: ns(p.shadow), .strokeWidth: -sw]))
        .draw(at: NSPoint(x: origin.x + size * 0.030, y: origin.y - size * 0.050))
    let ow = CGFloat(p.outlineWidth) * 100 * 2
    NSAttributedString(string: p.text, attributes: attrs([.foregroundColor: ns(p.outline), .strokeColor: ns(p.outline), .strokeWidth: -ow]))
        .draw(at: origin)
    NSAttributedString(string: p.text, attributes: attrs([.foregroundColor: ns(p.ink)])).draw(at: origin)
    if hasSub {
        let subSize = h * 0.085
        let sub = NSAttributedString(string: p.sub, attributes: [.font: printFont(printSubFontName, subSize),
                                                                  .foregroundColor: ns(SIMD3(1.0, 0.93, 0.72)), .kern: subSize * 0.25])
        let sb = glyphBox(sub)
        sub.draw(at: NSPoint(x: w * 0.5 - sb.midX, y: cy - gb.height * 0.5 - h * 0.075 - sb.midY))
    }
    NSGraphicsContext.restoreGraphicsState()
    return ctx.makeImage()!
}

/// 인쇄 판 한 장: 앞(시안 fp — 글자 0.56 · 폭 0.80 · 가운데 0.46) · 뒤(같은 글자, 0.40, 아래 글자 없음) · 옆(글자 없음 — 바탕 + 띠).
/// alt = 이름 없는 판(앞 '11.11' + 양옆 작은 빼빼로 그림 · 뒤 '11.11' — 시안 P2).
func printSheet(alt: Bool) -> CGImage {
    var front = BoxPrint()
    front.text = alt ? "11.11" : "빼빼로"
    front.sub = alt ? "" : "아잉 에디션"
    front.icons = alt
    front.textScale = 0.56; front.maxWidth = 0.80; front.textCY = 0.46
    var back = front
    back.sub = ""; back.icons = false; back.textScale = 0.40
    var side = BoxPrint()
    side.text = ""
    let W = PeperoDecor.sheetWidth, H = PeperoDecor.sheetHeight
    var sheet = [UInt8](repeating: 0, count: W * H * 4)
    let bands: [(BoxPrint, Range<Int>)] = [(front, PeperoDecor.frontRows), (back, PeperoDecor.backRows), (side, PeperoDecor.sideRows)]
    for (spec, rows) in bands {
        let px = bytes(boxPrintImage(spec, w: W, h: rows.count))
        for y in 0..<rows.count {
            sheet.replaceSubrange(((rows.lowerBound + y) * W * 4)..<((rows.lowerBound + y + 1) * W * 4), with: px[(y * W * 4)..<((y + 1) * W * 4)])
        }
    }
    // 띠 사이 여백: 위 절반은 위 띠 끝 줄, 아래 절반은 아래 띠 첫 줄을 되풀이(밉맵 · 쌍선형이 이웃 띠를 섞지 않게).
    for i in 0..<(bands.count - 1) {
        let upper = bands[i].1, lower = bands[i + 1].1
        let gap = upper.upperBound..<lower.lowerBound
        for y in gap {
            let src = y < gap.lowerBound + gap.count / 2 ? upper.upperBound - 1 : lower.lowerBound
            sheet.replaceSubrange((y * W * 4)..<((y + 1) * W * 4), with: Array(sheet[(src * W * 4)..<((src + 1) * W * 4)]))
        }
    }
    for i in 0..<(W * H) where sheet[i * 4 + 3] != 255 { fail("인쇄 판에 투명 화소가 있다(\(i % W), \(i / W))") }
    return makeImage(sheet, W, H)
}

// MARK: - 씬

func decodedTexture(_ contents: Any?) -> CGImage? {
    guard let contents else { return nil }
    if CFGetTypeID(contents as CFTypeRef) == CGImage.typeID { return (contents as! CGImage) }
    if let data = contents as? Data, let s = CGImageSourceCreateWithData(data as CFData, nil) { return CGImageSourceCreateImageAtIndex(s, 0, nil) }
    if let image = contents as? NSImage { return image.cgImage(forProposedRect: nil, context: nil, hints: nil) }
    if let url = contents as? URL { return NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil) }
    return nil
}

struct Rig {
    let scene: SCNScene
    let facing: SCNNode
    let character: SCNNode
    let bodyNode: SCNNode
    let bodyMin: SIMD3<Float>
    let bodyMax: SIMD3<Float>
}

/// 몸 = 원래 아잉이(앱 `applyUnlitMaterials` 처럼 .constant + 원본 디퓨즈 — 셰이더 없음). depthOnly 면 깊이만 쓰는 가림막(장식 층 굽기).
func makeRig(depthOnly: Bool) -> Rig {
    guard let scene = try? SCNScene(url: URL(fileURLWithPath: modelPath), options: nil) else { fail("모델을 못 읽었다") }
    scene.background.contents = NSColor.clear
    guard let character = scene.rootNode.childNodes.first else { fail("캐릭터 노드 없음") }
    var bodyNode: SCNNode?
    scene.rootNode.enumerateHierarchy { node, stop in if node.geometry != nil { bodyNode = node; stop.pointee = true } }
    guard let bodyNode, let material = bodyNode.geometry?.materials.first,
          let original = decodedTexture(material.diffuse.contents) else { fail("몸 재질 없음") }
    guard bodyNode.simdWorldTransform == matrix_identity_float4x4 else { fail("메시 노드 변환이 단위가 아니다") }
    material.lightingModel = .constant
    material.diffuse.contents = original
    if depthOnly { material.colorBufferWriteMask = [] }
    let wrapper = SCNNode(), facing = SCNNode()
    character.removeFromParentNode()
    facing.addChildNode(character)
    wrapper.addChildNode(facing)
    scene.rootNode.addChildNode(wrapper)
    let (lo, hi) = scene.rootNode.boundingBox
    return Rig(scene: scene, facing: facing, character: character, bodyNode: bodyNode,
               bodyMin: SIMD3(Float(lo.x), Float(lo.y), Float(lo.z)), bodyMax: SIMD3(Float(hi.x), Float(hi.y), Float(hi.z)))
}

/// 앱 카메라(몸만 보고 잡은 40° — 금 · 무지개 · 케이크 · 이슬 프레이밍과 같은 식).
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

func meshPositions(_ node: SCNNode) -> [SIMD3<Float>] {
    guard let vs = node.geometry?.sources(for: .vertex).first else { fail("정점 없음") }
    var pos = [SIMD3<Float>](repeating: .zero, count: vs.vectorCount)
    vs.data.withUnsafeBytes { raw in
        for i in 0..<vs.vectorCount {
            let o = vs.dataOffset + i * vs.dataStride
            pos[i] = SIMD3(raw.loadUnaligned(fromByteOffset: o, as: Float.self), raw.loadUnaligned(fromByteOffset: o + 4, as: Float.self),
                           raw.loadUnaligned(fromByteOffset: o + 8, as: Float.self))
        }
    }
    return pos
}

/// 초상 카메라: 앱 카메라 방향으로 몸 정점이 프레임의 `fill` 만큼 차게 거리를 맞춘다(이슬 생성기와 같다).
func portraitCamera(_ rig: Rig, fill: Float) -> SCNNode {
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
    let n = SCNNode(); n.camera = SCNCamera(); n.camera!.fieldOfView = 40
    n.camera!.zNear = 0.01; n.camera!.zFar = 1_000
    n.simdPosition = center - dir * d; n.simdLook(at: center)
    return n
}

/// 스냅숏의 '선형 프리멀티를 sRGB 로 부호화한' 반투명 픽셀을 바른 sRGB 프리멀티로 고친다(케이크 · 이슬 생성기와 같다).
func straightened(_ image: NSImage) -> CGImage {
    guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff), let cgImage = rep.cgImage else { fail("렌더 실패") }
    let w = cgImage.width, h = cgImage.height
    var px = bytes(cgImage)
    for i in 0..<(w * h) {
        let al = Double(px[i * 4 + 3]) / 255
        if al >= 1 { continue }
        if al <= 0 { px[i * 4] = 0; px[i * 4 + 1] = 0; px[i * 4 + 2] = 0; continue }
        for c in 0..<3 {
            let l = min(srgbToLinear(Double(px[i * 4 + c]) / 255) / al, 1)
            px[i * 4 + c] = UInt8(min(255, (linearToSrgb(l) * al * 255).rounded()))
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

/// 아잉 초상 원본 + 몸 알파 상자(알파 > 0.5).
func loadPortrait(_ expression: String) -> (image: CGImage, box: (Int, Int, Int, Int)) {
    let path = "\(resourceDir)/aing-\(expression).png"
    let image = loadImage(path)
    guard image.width == portraitSize, image.height == portraitSize else { fail("초상이 192² 가 아니다: \(path)") }
    return (image, alphaBox(bytes(image), portraitSize, portraitSize, threshold: 127))
}

/// 3D 몸 상자(초상 카메라, 지도 px) · 장식 층(같은 카메라 · 몸은 깊이만 쓰는 가림막 · 시야 두 배로 넓혀 굽는다).
struct PortraitLayer {
    let body: (Int, Int, Int, Int)
    let decor: CGImage
    let decorBox: (Int, Int, Int, Int)
    let decorSize: Int, pad: Int
}

func renderPortraitLayer(decorTemplate: SCNNode) -> PortraitLayer {
    let size = portraitMapSize
    let rig = makeRig(depthOnly: false)
    let image = snapshot(rig, camera: portraitCamera(rig, fill: 0.84), size: size)
    let frameSize = size * 2, pad = frameSize / 2, decorSize = frameSize + pad * 2
    let decorRig = makeRig(depthOnly: true)
    decorRig.character.addChildNode(decorTemplate.clone())
    let wideCam = portraitCamera(decorRig, fill: 0.84)
    wideCam.camera!.fieldOfView = CGFloat(2 * atan(2 * tan(20 * Double.pi / 180)) * 180 / Double.pi)
    let dimg = snapshot(decorRig, camera: wideCam, size: decorSize)
    let dbox = alphaBox(bytes(dimg), decorSize, decorSize, threshold: 6)
    guard dbox.0 > 1, dbox.2 > 1, dbox.1 < decorSize - 2, dbox.3 < decorSize - 2 else { fail("장식이 넓은 시야 밖으로 나간다") }
    return PortraitLayer(body: alphaBox(bytes(image), size, size, threshold: 127), decor: dimg, decorBox: dbox, decorSize: decorSize, pad: pad)
}

/// 장식 층 자리(원본 px 좌표, 위가 0): 3D 몸 상자 ↔ 2D 몸 상자 맞춤(장식 층은 시야 두 배 + 여백 pad). 두 표정이 같은 자리를 쓰게
/// **neutral 몸 상자 하나**로 정한다(두 원본의 몸 상자가 달라도 상자 · 막대가 움직이지 않는다).
func decorRect(_ layer: PortraitLayer, bodyBox b: (Int, Int, Int, Int)) -> CGRect {
    let g = layer.body
    let gx0 = Double(g.0), gw = Double(g.1 - g.0 + 1), gy0 = Double(g.2), gh = Double(g.3 - g.2 + 1)
    let bx0 = Double(b.0), bw = Double(b.1 - b.0 + 1), by0 = Double(b.2), bh = Double(b.3 - b.2 + 1)
    let sx = bw / (gw * 2), sy = bh / (gh * 2)
    let ox = bx0 - (gx0 * 2 + Double(layer.pad)) * sx, oy = by0 - (gy0 * 2 + Double(layer.pad)) * sy
    return CGRect(x: ox, y: oy, width: Double(layer.decorSize) * sx, height: Double(layer.decorSize) * sy)
}

/// 몸 상자들 ∪ 장식 상자 → 몸 배율 k(0.88 상한) · 가운데. 두 표정이 같은 k · 같은 자리.
func commonLayout(bodyBoxes: [(Int, Int, Int, Int)], layer: PortraitLayer, rect: CGRect) -> (k: Double, cx: Double, cy: Double) {
    let sx = rect.width / Double(layer.decorSize), sy = rect.height / Double(layer.decorSize)
    let d = layer.decorBox
    var x0 = rect.minX + Double(d.0) * sx, x1 = rect.minX + Double(d.1 + 1) * sx
    var y0 = rect.minY + Double(d.2) * sy, y1 = rect.minY + Double(d.3 + 1) * sy
    for b in bodyBoxes { x0 = min(x0, Double(b.0)); x1 = max(x1, Double(b.1 + 1)); y0 = min(y0, Double(b.2)); y1 = max(y1, Double(b.3 + 1)) }
    let avail = Double(portraitSize) - 2 * portraitMargin
    return (min(portraitBodyScale, avail / (x1 - x0), avail / (y1 - y0)), (x0 + x1) / 2, (y0 + y1) / 2)
}

func composePortrait(_ expression: String, body: CGImage, decor: CGImage, rect: CGRect, layout: (k: Double, cx: Double, cy: Double)) -> CGImage {
    let side = Double(portraitSize), k = layout.k
    func place(_ x: Double, _ y: Double, _ rw: Double, _ rh: Double) -> CGRect {
        let X = side / 2 + (x - layout.cx) * k, Y = side / 2 + (y - layout.cy) * k
        return CGRect(x: X, y: side - (Y + rh * k), width: rw * k, height: rh * k)
    }
    let ctx = CGContext(data: nil, width: portraitSize, height: portraitSize, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.draw(body, in: place(0, 0, Double(body.width), Double(body.height)))
    ctx.draw(decor, in: place(rect.minX, rect.minY, rect.width, rect.height))
    let image = ctx.makeImage()!
    let px = bytes(image)
    var border = 0
    for y in 0..<portraitSize { for x in 0..<portraitSize where x < 2 || y < 2 || x >= portraitSize - 2 || y >= portraitSize - 2 {
        border = max(border, Int(px[(y * portraitSize + x) * 4 + 3]))
    } }
    guard Double(border) / 255 <= borderAlphaLimit else { fail("\(expression) 초상 테두리 알파 \(Double(border) / 255) > \(borderAlphaLimit) — 막대가 잘린다") }
    let box = alphaBox(px, portraitSize, portraitSize, threshold: 0)
    print(String(format: "[portrait] %@: 몸 배율 %.3f(0.88 상한) · 알파 상자 x %d–%d y %d–%d · 테두리 2px 최대 알파 %.3f",
                 expression, k, box.0, box.1, box.2, box.3, Double(border) / 255))
    return image
}

/// 한 판(이름 있는 · 없는)의 초상 둘.
func makePortraits(decorTemplate: SCNNode) -> [(String, CGImage)] {
    let sources = expressions.map { ($0, loadPortrait($0)) }
    let layer = renderPortraitLayer(decorTemplate: decorTemplate)
    let rect = decorRect(layer, bodyBox: sources[0].1.box)
    for (e, s) in sources where s.box != sources[0].1.box {
        print("[portrait] 참고: \(e) 몸 상자 \(s.box) ≠ neutral \(sources[0].1.box) — 장식 자리는 neutral 기준 하나")
    }
    let layout = commonLayout(bodyBoxes: sources.map { $0.1.box }, layer: layer, rect: rect)
    return sources.map { ($0.0, composePortrait($0.0, body: $0.1.image, decor: layer.decor, rect: rect, layout: layout)) }
}

// MARK: - 팔 단면 맞대기

/// 바깥 벽(|x| = a ± 0.006) 근처 몸 정점의 (y, z) → 구멍 타원 반지름 비의 최대(팔 단면이 어두운 속 holeFit 안에 드는지).
func armSectionCheck() {
    let rig = makeRig(depthOnly: true)
    let a = PeperoDecor.a
    let near = meshPositions(rig.bodyNode).filter { abs(abs($0.x) - a) < 0.006 && $0.y < PeperoDecor.y1 }
    guard !near.isEmpty else { fail("팔 단면 정점이 없다") }
    var ey0: Float = .infinity, ey1: Float = -.infinity, ez0: Float = .infinity, ez1: Float = -.infinity, worst: Float = 0
    for p in near {
        ey0 = min(ey0, p.y); ey1 = max(ey1, p.y); ez0 = min(ez0, p.z); ez1 = max(ez1, p.z)
        let ey = (p.y - PeperoDecor.holeY) / PeperoDecor.holeHY, ez = (p.z - PeperoDecor.holeZ) / PeperoDecor.holeHZ
        worst = max(worst, (ey * ey + ez * ez).squareRoot())
    }
    print(String(format: "[arm] 바깥 벽 |x| = %.3f 팔 단면 y %.3f…%.3f · z %.3f…%.3f · 구멍 타원 반지름 비 최대 %.3f(어두운 속 %.3f 안) · 상자 바닥 %.3f",
                 a, ey0, ey1, ez0, ez1, worst, PeperoDecor.holeFit, PeperoDecor.y0))
    guard worst <= PeperoDecor.holeFit else { fail("팔 단면이 구멍 어두운 속 밖으로 나간다 — hole* 상수를 고치고 앱도 같이") }
}

// MARK: - 미리보기(--preview, 저장소 밖)

/// 앱 구도 3D 한 장(512², 시안 시트와 같은 자르기). lift = 부유 높이.
func appView(decor: SCNNode, yaw: Double, lift: Float = 0, uncropped: Bool = false) -> CGImage {
    let rig = makeRig(depthOnly: false)
    let camera = appCamera(rig)        // 몸만 보고 잡는다(장식 붙이기 전) — 앱 순서와 같다
    rig.character.addChildNode(decor.clone())
    rig.facing.simdPosition = SIMD3(0, lift, 0)
    let full = Int((Double(viewSize * renderScale) / cropSide).rounded())
    let big = snapshot(rig, camera: camera, size: full, yawDegrees: yaw)
    if uncropped { return big }
    let side = Double(full) * cropSide
    guard let cropped = big.cropping(to: CGRect(x: (Double(full) * cropX0).rounded(), y: (Double(full) * cropY0).rounded(),
                                                width: side.rounded(), height: side.rounded())) else { fail("자르기 실패") }
    return resized(cropped, viewSize, viewSize)
}

func writePreview(into dir: String, decor: SCNNode, altDecor: SCNNode?, portraits: [(String, CGImage)]) {
    var threeQuarter: CGImage?
    for (name, yaw) in [("front", 0.0), ("three-quarter", threeQuarterYaw), ("back", 180.0)] {
        let image = appView(decor: decor, yaw: yaw)
        if name == "three-quarter" { threeQuarter = image }
        writePNG(image, toPath: "\(dir)/\(name).png")
    }
    // 3/4 왼쪽 팔 구멍 둘레(512² 의 x 30–190 · y 290–480)를 3배(가장 가까운 화소)로.
    if let tq = threeQuarter, let c = tq.cropping(to: CGRect(x: 30, y: 290, width: 160, height: 190)) {
        writePNG(resized(c, 160 * 3, 190 * 3, nearest: true), toPath: "\(dir)/arm-hole-3x.png")
    }
    if let altDecor { writePNG(appView(decor: altDecor, yaw: 0), toPath: "\(dir)/alt-front.png") }
    for (e, p) in portraits {
        writePNG(resized(p, portraitSize * 4, portraitSize * 4, nearest: true), toPath: "\(dir)/portrait-\(e)-4x.png")
    }
    for lift in [Float(0), floatLift] {
        let full = appView(decor: decor, yaw: 0, lift: lift, uncropped: true)
        let box = alphaBox(bytes(full), full.width, full.height, threshold: 8)
        print(String(format: "[frame] 부유 %+.2f: 장식 포함 위 끝 여백 %.3f(프레임 높이 비율, 0 미만이면 잘림)", lift, Double(box.2) / Double(full.height)))
    }
    print("[preview] \(dir)")
}

// MARK: - 실행

var args = Array(CommandLine.arguments.dropFirst())
while !args.isEmpty {
    let flag = args.removeFirst()
    guard let value = args.first else { fail("사용: [--out <폴더>] [--alt <폴더>] [--preview <폴더>]") }
    args.removeFirst()
    switch flag {
    case "--out": outDir = value
    case "--alt": altDir = value
    case "--preview": previewDir = value
    default: fail("모르는 인자: \(flag)")
    }
}
guard FileManager.default.fileExists(atPath: modelPath) else { fail("저장소 루트에서 실행하라(\(modelPath) 없음)") }
_ = printFont(printFontName, 12)
_ = printFont(printSubFontName, 12)

let started = Date()
armSectionCheck()

/// 한 판: 인쇄 판을 굽고 → 쓴 PNG 를 다시 읽어(앱이 번들 · 캐시에서 읽는 길과 같은 바이트) 장식을 만들고 → 초상 둘.
func makeEdition(alt: Bool, into dir: String) -> (decor: SCNNode, portraits: [(String, CGImage)]) {
    let sheetPath = "\(dir)/\(characterID)-box.png"
    writePNG(printSheet(alt: alt), toPath: sheetPath)
    let t0 = Date()
    guard let decor = PeperoDecor.make(sheet: loadImage(sheetPath)) else { fail("인쇄 판 크기가 규약과 다르다") }
    let cost = Date().timeIntervalSince(t0)
    let top = PeperoDecor.measuredTopY(decor)
    print(String(format: "[decor] %@: 장식 꼭대기 y %.4f(상수 %.4f) · 만들기 %.2f초", alt ? "이름 없는 판" : "이름 있는 판", top, PeperoDecor.topY, cost))
    guard abs(top - PeperoDecor.topY) < 5e-4 else { fail("장식 꼭대기 높이가 상수와 다르다 — PeperoDecor.topY 를 고치고 앱 프레이밍도 같이") }
    let portraits = makePortraits(decorTemplate: decor)
    for (e, image) in portraits { writePNG(image, toPath: "\(dir)/\(characterID)-\(e).png") }
    return (decor, portraits)
}

let named = makeEdition(alt: false, into: outDir)
let unnamed = altDir.map { makeEdition(alt: true, into: $0) }
if let previewDir { writePreview(into: previewDir, decor: named.decor, altDecor: unnamed?.decor, portraits: named.portraits) }
print(String(format: "[done] 초상 %d장 + 인쇄 판 %d장 — %.1f초", named.portraits.count + (unnamed?.portraits.count ?? 0), unnamed == nil ? 1 : 2,
             Date().timeIntervalSince(started)))
