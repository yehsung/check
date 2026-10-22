// 생성된 이모티콘 원본(1024 PNG)을 말풍선에 쓸 512 로 다듬는다.
//
// 세 가지를 한다. 전부 **눈으로는 안 보이지만 화면에서 드러나는** 문제들이다.
//  ① **알파 잡티 제거**: 이미지 모델의 투명 배경에는 거의 투명한(α 1~15) 화소가 1%쯤 넓게 깔려 있다.
//     밝은 바탕에서는 안 보이지만 **어두운 바탕에서 네모 자국**으로 뜨고, 경계 상자를 통째로 망가뜨려
//     자동 정렬이 어긋난다(실측: 알파 그대로면 경계가 1024 폭 전체, 걷어내면 811).
//  ② **몸통 기준 정규화**: 장식이 넓게 퍼진 장(하트)과 좁은 장(기쁨)을 '내용 전체'로 맞추면 장마다
//     아잉이 크기가 달라 보인다. **가장 큰 덩어리(=몸통)**의 긴 변을 모든 장에서 같은 비율로 맞춘다.
//  ③ **몸통 중심 정렬**: 가운데 맞추는 기준도 내용이 아니라 몸통이다(장식은 한쪽으로 치우치기 마련이다).
//     장식이 칸을 넘치면 그만큼만 줄이고, 칸 안에 들어가면 삐져나가지 않게 민다.
//
// 사용법: swift scripts/fit-sticker.swift <입력.png> <출력.png> [한변=512] [몸통비율=0.62]
import AppKit
import CoreGraphics
import Foundation

let args = CommandLine.arguments
guard args.count >= 3 else {
    FileHandle.standardError.write("usage: fit-sticker.swift <in.png> <out.png> [side] [bodyFraction]\n".data(using: .utf8)!)
    exit(2)
}
let inURL = URL(fileURLWithPath: args[1])
let outURL = URL(fileURLWithPath: args[2])
let side = args.count > 3 ? Int(args[3]) ?? 512 : 512
let bodyFraction = args.count > 4 ? Double(args[4]) ?? 0.62 : 0.62

func fail(_ m: String) -> Never {
    FileHandle.standardError.write((m + "\n").data(using: .utf8)!)
    exit(1)
}

/// α 가 이보다 옅으면 완전 투명으로 친다(①).
let alphaNoise: UInt8 = 16
/// 몸통을 찾을 때 '불투명'으로 치는 기준(②).
let bodyAlpha: UInt8 = 128

guard let src = NSImage(contentsOf: inURL)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fail("못 읽었다: \(inURL.path)")
}
let w = src.width, h = src.height
guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                          space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
      let base = ctx.data else { fail("비트맵을 못 만들었다") }
ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))
ctx.draw(src, in: CGRect(x: 0, y: 0, width: w, height: h))
let px = base.assumingMemoryBound(to: UInt8.self)
let stride = ctx.bytesPerRow

// ① 잡티 제거. 프리멀티플라이드라 알파를 0 으로 만들 때 색도 같이 0 으로 둔다.
var noiseCount = 0
for y in 0..<h {
    for x in 0..<w {
        let o = y * stride + x * 4
        if px[o + 3] < alphaNoise {
            if px[o + 3] > 0 { noiseCount += 1 }
            px[o] = 0; px[o + 1] = 0; px[o + 2] = 0; px[o + 3] = 0
        }
    }
}

/// 내용(α>0) 경계 상자. 비었으면 nil.
func contentBox() -> (minX: Int, minY: Int, maxX: Int, maxY: Int)? {
    var minX = w, maxX = -1, minY = h, maxY = -1
    for y in 0..<h {
        for x in 0..<w where px[y * stride + x * 4 + 3] > 0 {
            if x < minX { minX = x }
            if x > maxX { maxX = x }
            if y < minY { minY = y }
            if y > maxY { maxY = y }
        }
    }
    return maxX >= minX ? (minX, minY, maxX, maxY) : nil
}

/// 가장 큰 연결 덩어리(= 몸통)의 경계 상자. 4-이웃 너비 우선, 재귀 없이 스택으로 돈다.
func bodyBox() -> (minX: Int, minY: Int, maxX: Int, maxY: Int)? {
    var seen = [Bool](repeating: false, count: w * h)
    var best: (count: Int, minX: Int, minY: Int, maxX: Int, maxY: Int)? = nil
    var stack = [Int]()
    stack.reserveCapacity(1024)
    for start in 0..<(w * h) where !seen[start] && px[(start / w) * stride + (start % w) * 4 + 3] >= bodyAlpha {
        seen[start] = true
        stack.removeAll(keepingCapacity: true)
        stack.append(start)
        var count = 0
        var minX = w, maxX = -1, minY = h, maxY = -1
        while let idx = stack.popLast() {
            let x = idx % w, y = idx / w
            count += 1
            if x < minX { minX = x }
            if x > maxX { maxX = x }
            if y < minY { minY = y }
            if y > maxY { maxY = y }
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let nx = x + dx, ny = y + dy
                guard nx >= 0, nx < w, ny >= 0, ny < h else { continue }
                let n = ny * w + nx
                guard !seen[n], px[ny * stride + nx * 4 + 3] >= bodyAlpha else { continue }
                seen[n] = true
                stack.append(n)
            }
        }
        if best == nil || count > best!.count { best = (count, minX, minY, maxX, maxY) }
    }
    guard let b = best else { return nil }
    return (b.minX, b.minY, b.maxX, b.maxY)
}

guard let content = contentBox() else { fail("빈 그림이다") }
guard let body = bodyBox() else { fail("몸통을 못 찾았다(불투명한 데가 없다)") }

guard let cleaned = ctx.makeImage() else { fail("잡티 제거 뒤 이미지를 못 만들었다") }

let bodyLong = Double(max(body.maxX - body.minX + 1, body.maxY - body.minY + 1))
let contentW = Double(content.maxX - content.minX + 1)
let contentH = Double(content.maxY - content.minY + 1)
// ② 몸통 기준 배율. ③ 장식이 넘치면 그만큼만 줄인다(몸통을 키우지는 않는다).
let scale = min(Double(side) * bodyFraction / bodyLong, Double(side) * 0.98 / max(contentW, contentH))

let drawW = max(1.0, (contentW * scale).rounded())
let drawH = max(1.0, (contentH * scale).rounded())
// 몸통 중심이 칸 한가운데에 오게. 좌표계는 좌하단 원점이다.
let bodyCX = Double(body.minX + body.maxX) / 2 - Double(content.minX)
let bodyCY = Double(body.minY + body.maxY) / 2 - Double(content.minY)
var ox = Double(side) / 2 - bodyCX * scale
var oy = Double(side) / 2 - bodyCY * scale
ox = drawW <= Double(side) ? min(max(ox, 0), Double(side) - drawW) : min(max(ox, Double(side) - drawW), 0)
oy = drawH <= Double(side) ? min(max(oy, 0), Double(side) - drawH) : min(max(oy, Double(side) - drawH), 0)

guard let outCtx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                             space: CGColorSpaceCreateDeviceRGB(),
                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fail("출력 비트맵 실패") }
outCtx.clear(CGRect(x: 0, y: 0, width: side, height: side))
outCtx.interpolationQuality = .high
guard let cropped = cleaned.cropping(to: CGRect(x: content.minX, y: h - 1 - content.maxY,
                                                width: Int(contentW), height: Int(contentH))) else { fail("자르기 실패") }
outCtx.draw(cropped, in: CGRect(x: ox, y: oy, width: drawW, height: drawH))

guard let out = outCtx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(outURL as CFURL, "public.png" as CFString, 1, nil) else { fail("저장 준비 실패") }
CGImageDestinationAddImage(dest, out, nil)
guard CGImageDestinationFinalize(dest) else { fail("저장 실패") }

let pct = bodyLong * scale / Double(side) * 100
print(String(format: "%@ → 몸통 %d×%d(%.0f%%) · 내용 %.0f×%.0f · 잡티 %d화소 제거",
             outURL.lastPathComponent, body.maxX - body.minX + 1, body.maxY - body.minY + 1,
             pct, contentW, contentH, noiseCount))
