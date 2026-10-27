import AppKit
import CoreGraphics
import Foundation
import Testing
@testable import CheckCore

// v0.3.63 — 아잉이 이모티콘 **그림을 갈았다**(사용자 지시 2026-10-22).
//
// 0.3.62 의 그림은 3D 렌더 위에 눈·입을 Core Graphics 로 덧칠한 것이었고 거부됐다("ㅈㄴ 못생겼어").
// 지금 그림은 이미지 모델이 그린다(`scripts/bake-aing-stickers.sh`). **전선·화면·서버는 한 줄도 안 바뀐다** —
// 토큰(`[아잉:기쁨]`)도, 파일 이름(`sticker-<id>.png`)도, 고르는 자리도 0.3.62 그대로다.
// 그래서 그 계약을 재는 것은 여전히 `V0362AingStickerTests.swift` 이고, 여기는 **그림 자체의 성질**만 잰다.
//
// ⚠️ **픽셀 색·모양은 재지 않는다**(0.3.62 때와 같은 이유 — 그림을 고치는 커밋이 빨개진다).
//    재는 것은 **그림이 바뀌어도 그대로 참이어야 하는 성질** 넷이고, 넷 다 실제로 밟은 사고다:
//     ① 512×512 — 굽는 자리가 바뀌어도 말풍선 레이아웃(`MessagePanelLayout.stickerSide`)이 추정하는 틀이다.
//     ② **네 귀퉁이가 완전 투명** — 모델이 투명 배경을 무시하고 **흰 네모**를 그려 보내는 일이 있다.
//        그러면 말풍선 안에 흰 상자가 뜬다. 밝은 테마에서는 눈에 안 띄고 어두운 테마에서만 드러난다.
//     ③ **거의 투명한 잡티가 1% 미만** — 생성물 원본에는 α 1~15 짜리 화소가 1.4%쯤 넓게 깔려 있다(실측).
//        `scripts/fit-sticker.swift` 가 그걸 걷는데, 안 걷힌 장을 넣으면 **어두운 바탕에서 네모 자국**이 뜬다.
//        이 단언이 곧 "후처리를 거쳤는가"다.
//     ④ **몸통 크기가 장마다 비슷하다** — 장식이 넓게 퍼진 장과 좁은 장을 내용 전체로 맞추면 아잉이가
//        장마다 커졌다 작아졌다 한다. 대화창에서 그게 제일 먼저 보인다(사용자 지시: "너무 과해").
//     ⑤ **바닥이 둥글다** — 이미지 모델이 가끔 몸통 아래를 **직선으로 잘라** 그린다(하트 1장 실측).
//        캔버스 밖으로 나간 게 아니라 **그림 자체가 평평해서** 알파·크기 단언은 전부 통과한다.
//        한 장만 그러면 대화창에서 그 장만 "잘린 것처럼" 보인다.

// MARK: - 길잡이

/// 이모티콘 한 장을 화소로 읽는다. (가로, 세로, RGBA 바이트, 한 줄 바이트 수)
private func asArtPixels(_ sticker: AingSticker) throws -> (w: Int, h: Int, px: [UInt8], stride: Int) {
    let url = try #require(AingStickerArt.url(sticker), "\(sticker.resourceName).png 이 번들에 없다")
    let image = try #require(NSImage(contentsOf: url), "\(sticker.resourceName).png 을 못 읽는다")
    let cg = try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
    let w = cg.width, h = cg.height
    var buffer = [UInt8](repeating: 0, count: w * h * 4)
    try buffer.withUnsafeMutableBytes { raw in
        let ctx = try #require(CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                         bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                         bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
    }
    return (w, h, buffer, w * 4)
}

/// 가장 큰 연결 덩어리(= 몸통)의 긴 변. 4-이웃, 스택으로 돈다(`scripts/fit-sticker.swift` 와 같은 규칙).
private func asBodyLongSide(_ p: (w: Int, h: Int, px: [UInt8], stride: Int)) -> Int {
    var seen = [Bool](repeating: false, count: p.w * p.h)
    var best = 0
    var stack: [Int] = []
    for start in 0..<(p.w * p.h) where !seen[start] && p.px[(start / p.w) * p.stride + (start % p.w) * 4 + 3] >= 128 {
        seen[start] = true
        stack.removeAll(keepingCapacity: true)
        stack.append(start)
        var minX = p.w, maxX = -1, minY = p.h, maxY = -1
        while let idx = stack.popLast() {
            let x = idx % p.w, y = idx / p.w
            if x < minX { minX = x }
            if x > maxX { maxX = x }
            if y < minY { minY = y }
            if y > maxY { maxY = y }
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let nx = x + dx, ny = y + dy
                guard nx >= 0, nx < p.w, ny >= 0, ny < p.h else { continue }
                let n = ny * p.w + nx
                guard !seen[n], p.px[ny * p.stride + nx * 4 + 3] >= 128 else { continue }
                seen[n] = true
                stack.append(n)
            }
        }
        best = max(best, max(maxX - minX + 1, maxY - minY + 1))
    }
    return best
}

// MARK: - 그림의 성질

@Test("이모티콘 여섯 장은 512×512 이고 네 귀퉁이가 완전 투명하다")
func v0363StickerArtIsSquareAndCutOut() throws {
    for sticker in AingSticker.allCases {
        let p = try asArtPixels(sticker)
        #expect(p.w == 512 && p.h == 512, "\(sticker.resourceName): \(p.w)×\(p.h) — 512 가 아니다")
        // 귀퉁이에서 8화소 안쪽을 본다(가장자리 한 줄은 리샘플 찌꺼기가 낄 수 있다).
        for (x, y) in [(8, 8), (p.w - 9, 8), (8, p.h - 9), (p.w - 9, p.h - 9)] {
            let alpha = p.px[y * p.stride + x * 4 + 3]
            #expect(alpha == 0, "\(sticker.resourceName): 귀퉁이(\(x),\(y)) 가 안 비었다(α=\(alpha)) — 말풍선에 네모가 뜬다")
        }
    }
}

@Test("이모티콘에 거의 투명한 잡티가 남아 있지 않다(후처리를 거쳤는가)")
func v0363StickerArtHasNoAlphaHaze() throws {
    for sticker in AingSticker.allCases {
        let p = try asArtPixels(sticker)
        var haze = 0
        for y in 0..<p.h {
            for x in 0..<p.w {
                let alpha = p.px[y * p.stride + x * 4 + 3]
                if alpha > 0 && alpha < 16 { haze += 1 }
            }
        }
        let share = Double(haze) / Double(p.w * p.h)
        #expect(share < 0.01,
                "\(sticker.resourceName): 거의 투명한 화소가 \(String(format: "%.2f", share * 100))% — 어두운 바탕에서 네모 자국이 뜬다")
    }
}

@Test("아잉이 몸통 크기가 여섯 장에서 비슷하다")
func v0363StickerBodiesAreSameSize() throws {
    var sides: [(String, Int)] = []
    for sticker in AingSticker.allCases {
        sides.append((sticker.rawValue, asBodyLongSide(try asArtPixels(sticker))))
    }
    for (name, side) in sides {
        #expect(side > 0, "\(name): 몸통을 못 찾았다(불투명한 데가 없다)")
        #expect(side >= 250 && side <= 400,
                "\(name): 몸통 긴 변 \(side)pt — 512 칸에서 너무 작거나 크다(다른 장과 다르게 보인다)")
    }
    let longest = sides.map(\.1).max() ?? 0
    let shortest = sides.map(\.1).min() ?? 0
    #expect(longest - shortest <= 60,
            "장마다 아잉이 크기가 다르다(가장 큰 \(longest) · 가장 작은 \(shortest)): \(sides)")
}

@Test("아잉이 바닥이 직선으로 잘려 있지 않다")
func v0363StickerBottomsAreRound() throws {
    for sticker in AingSticker.allCases {
        let p = try asArtPixels(sticker)
        // 불투명한 화소의 가장 아래 줄을 찾고, 그 줄의 폭을 몸통 폭과 견준다.
        var bottomRow = -1
        var minX = p.w, maxX = -1
        for y in 0..<p.h {
            for x in 0..<p.w where p.px[y * p.stride + x * 4 + 3] >= 128 {
                if y > bottomRow { bottomRow = y }
                if x < minX { minX = x }
                if x > maxX { maxX = x }
            }
        }
        #expect(bottomRow >= 0 && maxX >= minX, "\(sticker.resourceName): 불투명한 데가 없다")
        var widthAtBottom = 0
        for x in 0..<p.w where p.px[bottomRow * p.stride + x * 4 + 3] >= 128 { widthAtBottom += 1 }
        let flatness = Double(widthAtBottom) / Double(maxX - minX + 1)
        // 실측: 둥근 장 0.02~0.09 · 바닥이 잘린 장 0.23. 0.15 면 둘을 가른다.
        #expect(flatness < 0.15,
                "\(sticker.resourceName): 바닥이 평평하다(맨 아랫줄 폭이 몸통 폭의 \(Int(flatness * 100))%) — 잘려 보인다")
    }
}

// MARK: - 0.3.63 체인지로그 (내용만)
//
// **관행**: 버전 고정과 "맨 위 섹션" 단언은 *그 릴리스의 시험 파일*이 든다(0.3.60 → 0.3.61 → 0.3.62 → 0.3.63 → …).
// 0.3.64 가 올라가며 그 둘은 `V0364MissionGroupsTests.swift` 의 `v0364VersionAndChangelog` 로 넘겼다 —
// 안 옮기면 버전을 올리는 그 커밋에서 전체 스위트가 빨개진다. 여기는 0.3.63 섹션의 **내용**만 지킨다(이미 배포된 역사다).
@Test("CHANGELOG 0.3.63 은 두 줄(사용자 말투) · 0.3.62 보다 위")
func v0363VersionAndChangelog() throws {
    let root = CheckCoreSourceLayout.repoRoot

    let changelog = try String(contentsOf: root.appendingPathComponent("CHANGELOG.md"), encoding: .utf8)
    let section = try #require(changelog.components(separatedBy: "\n## ").first { $0.hasPrefix("0.3.63\n") })
    let items = section.components(separatedBy: "\n").filter { $0.hasPrefix("- ") }
    #expect(items.count == 2, "항목 \(items)")
    // 배너는 한 줄씩 **말줄임**이다(`CheckMenuView` 의 노트 `lineLimit(1)`). 본문 폭 316 − 글머리표·간격 ≈ 306pt 이고,
    // caption2(10pt) 실측으로 이 두 줄은 215.5pt · 75.2pt 다. 한 문장으로 붙이면 293.6pt 라 여유가 12pt 뿐이라 쪼갰다.
    #expect(items.allSatisfy { $0.count <= 40 }, "배너 폭에서 잘릴 만큼 긴 줄이 있다: \(items)")
    // 사용자 문구에 내부 어휘를 쓰지 않는다. `스티커` 도 막는다 — 한국어 화면에서는 **이모티콘** 한 낱말로 간다.
    for banned in ["스티커", "토큰", "번들", "포커스", "PNG", "서버", "테스트", "CheckCore"] {
        #expect(!section.contains(banned), "사용자 문구에 내부 어휘('\(banned)')가 있다")
    }
    #expect(changelog.range(of: "## 0.3.63")!.lowerBound < changelog.range(of: "## 0.3.62")!.lowerBound,
            "0.3.63 섹션이 0.3.62 보다 아래에 있다")
}
