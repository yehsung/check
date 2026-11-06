#!/usr/bin/env swift
// 흑우 아잉이(aing_hwoo) 초상 생성기 (v0.3.78) — 맥 초상 두 장(192², 기본 · 시무룩)을 굽는다. 3D 마감은 앱 셰이더(HwooAingFinish)가 한다.
// 시안 U9 '네온'(대표 결정 2026-11-06 #d_CtPxrfwWATBZ): 짙은 남색 몸 + 왼쪽 하늘색 · 오른쪽 분홍 네온 테. 색 값은 HwooAingArt(CheckCore)와 같다.
//
// 사용법(저장소 루트에서):
//   swift -O scripts/make-hwoo-aing.swift               Sources/check/Resources/aing_hwoo-{neutral,negative}.png 를 쓴다(같은 입력이면 같은 바이트).
//   swift -O scripts/make-hwoo-aing.swift --out <폴더>  같은 두 장을 <폴더>/ 에 쓴다(저장소는 안 건드린다 — 결정성 검사용).
//
// 입력(읽기만): Sources/check/Resources/aing-neutral.png · aing-negative.png(192² 아잉 초상).
// 방법: 피부 픽셀(isGoldSkin — 앱 GoldAingFinish 와 같은 식: 색상 215–300° · 채도 0.05–0.75 · 루마 > 0.10)만 짙은 남색으로 바꾸고 밝기는
//   원본 OKLab L 비율(기준 0.8327 — 무지개와 같은 값)로 옮긴다. 눈 · 입 · 볼터치는 원본 그대로. 그다음 실루엣 안쪽 가장자리(투명까지 거리
//   0…rimWidth 픽셀)에 네온 테를 더한다 — 색은 가로 위치로 하늘색(왼쪽) → 분홍(오른쪽). 알파는 원본 그대로다(몸 크기를 바꾸지 않는다).
import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let bodyColor = 0x1A1830, neonLeft = 0x2EE6FF, neonRight = 0xFF3FA8
let lightnessReference = 0.8327
let rimWidth = 7.0
let rimStrength = 1.05

func fail(_ m: String) -> Never { FileHandle.standardError.write((m + "\n").data(using: .utf8)!); exit(1) }
var args = Array(CommandLine.arguments.dropFirst())
var outDir = "Sources/check/Resources"
if let i = args.firstIndex(of: "--out"), i + 1 < args.count { outDir = args[i + 1]; args.removeSubrange(i...(i + 1)) }
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
func toLin(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
func toSRGB(_ v: Double) -> Double { let c = min(max(v, 0), 1); return c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055 }
func lin(_ hex: Int) -> SIMD3<Double> { SIMD3(toLin(Double((hex >> 16) & 255) / 255), toLin(Double((hex >> 8) & 255) / 255), toLin(Double(hex & 255) / 255)) }
func oklabL(_ c: SIMD3<Double>) -> Double {
    let l = pow(max(0.4122214708 * c.x + 0.5363325363 * c.y + 0.0514459929 * c.z, 0), 1 / 3)
    let m = pow(max(0.2119034982 * c.x + 0.6806995451 * c.y + 0.1073969566 * c.z, 0), 1 / 3)
    let s = pow(max(0.0883024619 * c.x + 0.2817188376 * c.y + 0.6299787005 * c.z, 0), 1 / 3)
    return 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
}
/// 앱 `GoldAingFinish.isGoldSkin` 과 같은 식(sRGB 0…1).
func isSkin(_ r: Double, _ g: Double, _ b: Double) -> Bool {
    let mx = max(r, g, b), mn = min(r, g, b)
    let sat = mx > 0 ? (mx - mn) / mx : 0
    var hue = 0.0
    if mx > mn {
        let span = mx - mn
        if mx == r { hue = 60 * ((g - b) / span) } else if mx == g { hue = 60 * ((b - r) / span + 2) } else { hue = 60 * ((r - g) / span + 4) }
        if hue < 0 { hue += 360 }
    }
    let luma = 0.299 * r + 0.587 * g + 0.114 * b
    return hue >= 215 && hue <= 300 && sat > 0.05 && sat < 0.75 && luma > 0.10
}
func smooth(_ e0: Double, _ e1: Double, _ x: Double) -> Double { let t = min(max((x - e0) / (e1 - e0), 0), 1); return t * t * (3 - 2 * t) }

func load(_ path: String) -> (px: [UInt8], w: Int, h: Int) {
    guard let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else { fail("못 읽음: \(path)") }
    let w = img.width, h = img.height
    var px = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: sRGB,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    return (px, w, h)
}

func write(_ px: [UInt8], _ w: Int, _ h: Int, _ path: String) {
    var data = px
    let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4, space: sRGB,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let img = ctx.makeImage()!
    let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, img, nil)
    guard CGImageDestinationFinalize(dest) else { fail("못 씀: \(path)") }
    print("썼다: \(path) \(w)x\(h)")
}

/// 투명(알파 < 0.5)까지의 거리(픽셀, 체스판 3-4 근사 두 번 쓸기). 실루엣 밖은 0.
func distanceToOutside(_ px: [UInt8], _ w: Int, _ h: Int) -> [Double] {
    let big = 1e9
    var d = [Double](repeating: big, count: w * h)
    for y in 0..<h { for x in 0..<w where px[(y * w + x) * 4 + 3] < 128 { d[y * w + x] = 0 } }
    let a = 1.0, b = 1.4142
    for y in 0..<h { for x in 0..<w {
        var v = d[y * w + x]
        if x > 0 { v = min(v, d[y * w + x - 1] + a) }
        if y > 0 { v = min(v, d[(y - 1) * w + x] + a) }
        if x > 0 && y > 0 { v = min(v, d[(y - 1) * w + x - 1] + b) }
        if x < w - 1 && y > 0 { v = min(v, d[(y - 1) * w + x + 1] + b) }
        d[y * w + x] = v
    } }
    for y in stride(from: h - 1, through: 0, by: -1) { for x in stride(from: w - 1, through: 0, by: -1) {
        var v = d[y * w + x]
        if x < w - 1 { v = min(v, d[y * w + x + 1] + a) }
        if y < h - 1 { v = min(v, d[(y + 1) * w + x] + a) }
        if x < w - 1 && y < h - 1 { v = min(v, d[(y + 1) * w + x + 1] + b) }
        if x > 0 && y < h - 1 { v = min(v, d[(y + 1) * w + x - 1] + b) }
        d[y * w + x] = v
    } }
    // 그림 가장자리(캔버스 끝)도 바깥으로 본다.
    for y in 0..<h { for x in 0..<w { d[y * w + x] = min(d[y * w + x], Double(min(x, y, w - 1 - x, h - 1 - y)) + 1) } }
    return d
}

func make(_ input: String, _ output: String) {
    var (px, w, h) = load(input)
    let dist = distanceToOutside(px, w, h)
    // 실루엣 가로 범위(테 색 섞기 기준).
    var minX = w, maxX = 0
    for y in 0..<h { for x in 0..<w where px[(y * w + x) * 4 + 3] >= 128 { minX = min(minX, x); maxX = max(maxX, x) } }
    let cx = Double(minX + maxX) / 2, half = max(1, Double(maxX - minX) / 2)
    let body = lin(bodyColor), left = lin(neonLeft), right = lin(neonRight)
    for y in 0..<h { for x in 0..<w {
        let o = (y * w + x) * 4
        let a = Double(px[o + 3]) / 255
        guard a > 0 else { continue }
        // 프리멀티 → 곧은 sRGB.
        let r = Double(px[o]) / 255 / a, g = Double(px[o + 1]) / 255 / a, bl = Double(px[o + 2]) / 255 / a
        var c = SIMD3(toLin(r), toLin(g), toLin(bl))
        let skin = isSkin(r, g, bl)
        if skin {
            let k = min(max(oklabL(c) / lightnessReference, 0.55), 1.35)
            c = body * k
        }
        // 네온 테: 가장자리 안쪽 rimWidth 픽셀 — 피부 · 반투명 가장자리에만(눈 · 입 · 볼은 안쪽이라 닿지 않는다).
        if skin || a < 0.99 {
            let rim = pow(1 - min(dist[y * w + x] / rimWidth, 1), 2) * rimStrength
            let side = smooth(-0.4, 0.4, (Double(x) - cx) / half)
            let neon = left + (right - left) * side
            c += neon * rim
        }
        let rgb = SIMD3(toSRGB(c.x), toSRGB(c.y), toSRGB(c.z))
        px[o] = UInt8((rgb.x * a * 255).rounded())
        px[o + 1] = UInt8((rgb.y * a * 255).rounded())
        px[o + 2] = UInt8((rgb.z * a * 255).rounded())
    } }
    write(px, w, h, output)
}

let res = "Sources/check/Resources"
make("\(res)/aing-neutral.png", "\(outDir)/aing_hwoo-neutral.png")
make("\(res)/aing-negative.png", "\(outDir)/aing_hwoo-negative.png")
