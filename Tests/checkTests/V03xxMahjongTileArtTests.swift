import AppKit
import CoreText
import Foundation
import Testing
@testable import check
@testable import CheckCore

// 아잉 마작 패 그림(SPEC §5.9 · §6.3 U 줄 V03xxMahjongTileArtTests — CC-15 · CC-16 · CC-29).
// 모델 결과(통 원 수 · 삭 막대 수 · 만 위 글자 · 자패 글자 · 적5 매핑 · 방위 회전)와 렌더 결과(잉크 덩어리 수 · 두 번 그린 픽셀 ·
// 배율 크기 · 글꼴 · 38면이 모두 다름 · 금색 점 · 테두리 · 팔레트 폴백)를 잰다. 그림은 `MahjongTileArt.rasterize` 로 직접 굽는다
// (실행 중 ImageRenderer 를 쓰지 않는 것이 이 그림의 약속이다). 네트워크는 타지 않는다.

@MainActor
@Suite("아잉 마작 패 그림 — 모델 · 렌더 · 글꼴 · 팔레트")
struct V03xxMahjongTileArtTests {
    // MARK: 모델

    @Test("통 n 의 원 수 = n · 삭 n 의 막대 수 = n(1삭은 새싹) · 만 위 글자(5 는 伍) + 萬 · 자패 글자")
    func layoutCountsMatchTheFace() {
        // 없으면: 통·삭 배치 표가 한 칸 밀려(예: 5통에 원 넷) 그려져도 초록이다.
        for n in 1...9 {
            let pin = MahjongTileArtModel.layout(face: .tile(kind: 8 + n, red: false))
            #expect(pin.pips.count == n, "\(n)통 원 \(pin.pips.count)개")
            let sou = MahjongTileArtModel.layout(face: .tile(kind: 17 + n, red: false))
            if n == 1 {
                #expect(sou.sprout && sou.sticks.isEmpty, "1삭은 막대가 아니라 새싹이어야 한다")
            } else {
                #expect(sou.sticks.count == n, "\(n)삭 막대 \(sou.sticks.count)개")
            }
            let man = MahjongTileArtModel.layout(face: .tile(kind: n - 1, red: false))
            #expect(man.glyphs.map(\.text) == [n == 5 ? "伍" : MahjongTileArtModel.manNumerals[n - 1], "萬"])
        }
        let honors = (27..<34).map { MahjongTileArtModel.layout(face: .tile(kind: $0, red: false)) }
        #expect(honors.map { $0.glyphs.first?.text ?? ($0.hakuFrame ? "白" : "?") } == ["東", "南", "西", "北", "白", "發", "中"])
        #expect(honors[4].glyphs.isEmpty && honors[4].hakuFrame, "白 은 글자 대신 라벤더 테두리")
    }

    @Test("패 id → 면: 적5 는 id 16·52·88 만 · 종류 = id/4")
    func redFivesAreExactlyTheThreeIDs() {
        // 없으면: 적5 판정을 종류(5만 전부)로 하면 5만 네 장이 모두 빨갛게 그려져도 초록이다.
        let reds = (0..<136).filter { id in MahjongTile(id: id).map { MahjongTileFace($0).isRed } == true }
        #expect(reds == [16, 52, 88])
        for id in [0, 15, 16, 17, 135] {
            #expect(MahjongTile(id: id).map { MahjongTileFace($0).kind } == id / 4)
        }
        #expect(MahjongTileFace.all.count == 38 && Set(MahjongTileFace.all).count == 38)
    }

    @Test("방위별 회전 = MahjongSeatCompass(그 사람 쪽이 패의 아래)")
    func rotationFollowsTheCompass() {
        // 없으면: 하가(오른쪽)의 강이 큐브 방위(하가 왼쪽)로 돌아가도 초록이다.
        let expected: [MahjongCompass: Int] = [.bottom: 0, .right: 3, .top: 2, .left: 1]
        for mySeat in 0..<4 {
            for seat in 0..<4 {
                let compass = MahjongSeatCompass.of(seat: seat, mySeat: mySeat)
                #expect(MahjongTileArtModel.rotation(for: compass) == expected[compass])
            }
        }
        // 하가(다음 차례)는 오른쪽 — 회전 3(위가 왼쪽 = 가운데를 본다).
        #expect(MahjongTileArtModel.rotation(for: MahjongSeatCompass.of(seat: 1, mySeat: 0)) == 3)
    }

    // MARK: 렌더

    @Test("46×62 통 n 의 잉크 덩어리 = 원 n 개(고리 + 가운데 점 = 2n 조각)")
    func pinInkBlobsMatchCount() throws {
        // 없으면: 배치 값은 맞는데 그리는 쪽이 원을 빠뜨리거나 겹쳐 그려도 초록이다.
        for n in 1...9 {
            let image = try #require(MahjongTileArt.rasterize(
                MahjongTileArt.image(.tile(kind: 8 + n, red: false), size: .hand, cornerLabels: false), scale: 2))
            let blobs = mjSaturatedBlobs(image, minimumSize: 4)
            #expect(blobs == 2 * n, "\(n)통: 채색 조각 \(blobs)개(원 \(n)개 × 고리·점 2)")
        }
    }

    @Test("같은 면을 두 번 그린 픽셀이 같다 · 캐시는 같은 그림을 돌려준다")
    func sameFaceDrawsSameBytes() throws {
        // 없으면: 그릴 때마다 흔들리는 그림(첫 장이 캐시에 박히면 세션 내내 틀린 패 — CC-15)이 초록이다.
        for face in [MahjongTileFace.tile(kind: 4, red: true), .tile(kind: 33, red: false), .back, .tile(kind: 18, red: false)] {
            let first = try #require(MahjongTileArt.rasterize(MahjongTileArt.image(face, size: .river), scale: 2))
            let second = try #require(MahjongTileArt.rasterize(MahjongTileArt.image(face, size: .river), scale: 2))
            #expect(mjBytes(first) == mjBytes(second), "\(face) 두 장이 다르다")
        }
        let a = MahjongTileArt.cgImage(.tile(kind: 9, red: false), size: .hand, scale: 2)
        let b = MahjongTileArt.cgImage(.tile(kind: 9, red: false), size: .hand, scale: 2)
        #expect(a != nil && a === b, "같은 열쇠·같은 배율인데 캐시가 새로 구웠다")
    }

    @Test("배율 1·2 에서 그린 크기 = 칸 × 배율 · 회전하면 가로세로가 바뀐다")
    func scaledSizesMatchTheSlot() throws {
        // 없으면: 레티나에서 1배로 구운 흐린 패(또는 칸보다 큰 패)가 초록이다.
        for size in MahjongTileSize.allCases {
            for scale in [1, 2] {
                let image = try #require(MahjongTileArt.cgImage(.tile(kind: 0, red: false), size: size, scale: CGFloat(scale)))
                #expect(image.width == Int(size.width) * scale && image.height == Int(size.height) * scale)
            }
            let turned = try #require(MahjongTileArt.cgImage(.tile(kind: 0, red: false), size: size, rotation: 1, scale: 2))
            #expect(turned.width == Int(size.height) * 2 && turned.height == Int(size.width) * 2)
        }
    }

    @Test("글꼴 PostScript 이름이 요청과 같고 伍 를 포함한 모든 글자를 가진다(기준선: 한자 없는 글꼴은 거짓)")
    func glyphFontIsTheRequestedOne() {
        // 없으면: 요청 글꼴이 없을 때 시스템이 조용히 다른 글꼴로 바꿔 萬·伍 가 두부(□)로 그려져도 초록이다.
        let name = MahjongTileArt.resolvedFontName
        #expect(name.map(MahjongTileArtModel.preferredFontNames.contains) == true, "요청한 글꼴이 이 맥에 없다: \(String(describing: name))")
        #expect(CTFontCopyPostScriptName(MahjongTileArt.glyphFont) as String == name)
        #expect(MahjongTileArt.covers(MahjongTileArtModel.requiredGlyphs))
        #expect(MahjongTileArtModel.requiredGlyphs.contains("伍"))
        // 기준선: 한자가 없는 글꼴은 같은 판정에서 거짓이어야 판정이 뜻이 있다.
        #expect(!MahjongTileArt.covers(MahjongTileArtModel.requiredGlyphs, font: CTFontCreateWithName("Courier" as CFString, 12, nil)))
    }

    @Test("34면 + 적5 3 + 뒷면이 모두 다른 그림")
    func everyFaceIsDistinct() throws {
        // 없으면: 두 면이 같은 그림(예: 白 이 뒷면처럼 비거나 발·중이 같은 글자)이어도 초록이다.
        var seen: [Data: MahjongTileFace] = [:]
        for face in MahjongTileFace.all {
            let image = try #require(MahjongTileArt.cgImage(face, size: .hand, scale: 2))
            let bytes = mjBytes(image)
            #expect(seen[bytes] == nil, "\(face) 와 \(String(describing: seen[bytes])) 가 같은 그림")
            seen[bytes] = face
        }
        #expect(seen.count == 38)
    }

    @Test("적5 와 보통 5 의 차이가 빨강 말고 금색 점 자리에서도 남는다")
    func redFiveHasAGoldDot() throws {
        // 없으면: 적5 를 색만 바꿔 그려(색약이면 못 가른다) 초록이다.
        for kind in [4, 13, 22] {
            let plain = try #require(MahjongTileArt.cgImage(.tile(kind: kind, red: false), size: .hand, cornerLabels: false, scale: 2))
            let red = try #require(MahjongTileArt.cgImage(.tile(kind: kind, red: true), size: .hand, cornerLabels: false, scale: 2))
            // 오른쪽 위 금색 점 자리(얼굴 칸 오른쪽 위 모서리) — 금색은 파랑 채널이 0 이라 크림(파랑 247+)과 크게 갈린다.
            let dot = CGRect(x: 32, y: 3, width: 12, height: 12)
            let gold = mjCount(red, rect: dot) { r, g, b in r > 200 && g > 140 && b < 90 }
            let goldPlain = mjCount(plain, rect: dot) { r, g, b in r > 200 && g > 140 && b < 90 }
            #expect(gold > 20 && goldPlain == 0, "종류 \(kind): 금색 점 픽셀 적5 \(gold) · 보통 \(goldPlain)")
        }
    }

    @Test("크기 6종 · 네 방향 모두 그림이 칸 안에 머문다")
    func drawingStaysInsideTheSlot() throws {
        // 없으면: 테두리·리치 가로패가 옆 패 칸으로 번져도 초록이다.
        for size in MahjongTileSize.allCases {
            for rotation in 0..<4 {
                let image = MahjongTileArt.image(.tile(kind: 31, red: false), size: size, state: .highlighted, rotation: rotation)
                let margin: CGFloat = 4
                let canvas = CGSize(width: image.size.width + margin * 2, height: image.size.height + margin * 2)
                let bitmap = try #require(mjPadded(image, canvas: canvas, margin: margin))
                var outside = 0
                for y in 0..<bitmap.height {
                    for x in 0..<bitmap.width {
                        let inside = CGFloat(x) >= margin * 2 && CGFloat(x) < (margin + image.size.width) * 2
                            && CGFloat(y) >= margin * 2 && CGFloat(y) < (margin + image.size.height) * 2
                        if !inside, bitmap.alpha(x, y) > 0 { outside += 1 }
                    }
                }
                #expect(outside == 0, "\(size) 회전 \(rotation): 칸 밖 픽셀 \(outside)")
            }
        }
    }

    @Test("팔레트 JSON 실패 → 코드 팔레트 · 바른 JSON 은 그 색")
    func paletteFallsBackToCode() throws {
        // 없으면: 받은 JSON 이 틀리면(키 빠짐·색 글자 틀림) 패가 검게 그려져도 초록이다.
        #expect(MahjongTilePalette.resolved(from: nil) == .standard)
        #expect(MahjongTilePalette.resolved(from: Data("not json".utf8)) == .standard)
        #expect(MahjongTilePalette.resolved(from: Data(##"{"bodyTop":"#FFFFFF"}"##.utf8)) == .standard)
        var broken = MahjongTilePalette.standard
        broken.ink = "#GGGGGG"
        #expect(MahjongTilePalette.resolved(from: try JSONEncoder().encode(broken)) == .standard)
        var custom = MahjongTilePalette.standard
        custom.backRim = "#00FF00"
        #expect(MahjongTilePalette.resolved(from: try JSONEncoder().encode(custom)) == custom)
    }
}

// MARK: - 도우미(이 파일 전용)

private struct MJPixels {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    func rgb(_ x: Int, _ y: Int) -> (Int, Int, Int) {
        let o = (y * width + x) * 4
        return (Int(bytes[o]), Int(bytes[o + 1]), Int(bytes[o + 2]))
    }

    func alpha(_ x: Int, _ y: Int) -> Int { Int(bytes[(y * width + x) * 4 + 3]) }
}

/// CGImage → RGBA8(sRGB, 위가 0). 프리멀티플라이드라 투명 픽셀은 0.
private func mjPixels(_ image: CGImage) -> MJPixels {
    let width = image.width, height = image.height
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    bytes.withUnsafeMutableBytes { buffer in
        let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: width * 4, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }
    return MJPixels(width: width, height: height, bytes: bytes)
}

private func mjBytes(_ image: CGImage) -> Data { Data(mjPixels(image).bytes) }

/// 사각형(pt, 배율 2) 안에서 조건에 맞는 픽셀 수.
private func mjCount(_ image: CGImage, rect: CGRect, where predicate: (Int, Int, Int) -> Bool) -> Int {
    let pixels = mjPixels(image)
    var hits = 0
    for y in max(0, Int(rect.minY * 2))..<min(pixels.height, Int(rect.maxY * 2)) {
        for x in max(0, Int(rect.minX * 2))..<min(pixels.width, Int(rect.maxX * 2)) {
            let (r, g, b) = pixels.rgb(x, y)
            if predicate(r, g, b) { hits += 1 }
        }
    }
    return hits
}

/// 채도 높은(통의 파랑·초록·빨강) 픽셀의 연결 성분 수(크기 `minimumSize` 이상).
private func mjSaturatedBlobs(_ image: CGImage, minimumSize: Int) -> Int {
    let pixels = mjPixels(image)
    let w = pixels.width, h = pixels.height
    var mask = [Bool](repeating: false, count: w * h)
    for y in 0..<h {
        for x in 0..<w where pixels.alpha(x, y) > 200 {
            let (r, g, b) = pixels.rgb(x, y)
            mask[y * w + x] = max(r, g, b) - min(r, g, b) >= 90
        }
    }
    var seen = [Bool](repeating: false, count: w * h)
    var count = 0
    for start in 0..<(w * h) where mask[start] && !seen[start] {
        var stack = [start]
        seen[start] = true
        var size = 0
        while let p = stack.popLast() {
            size += 1
            let px = p % w, py = p / w
            for (nx, ny) in [(px - 1, py), (px + 1, py), (px, py - 1), (px, py + 1)] where nx >= 0 && ny >= 0 && nx < w && ny < h {
                let n = ny * w + nx
                if mask[n] && !seen[n] { seen[n] = true; stack.append(n) }
            }
        }
        if size >= minimumSize { count += 1 }
    }
    return count
}

/// 여백을 둔 캔버스(배율 2)에 그림을 놓은 픽셀.
@MainActor
private func mjPadded(_ image: NSImage, canvas: CGSize, margin: CGFloat) -> MJPixels? {
    let width = Int(canvas.width * 2), height = Int(canvas.height * 2)
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    context.scaleBy(x: 2, y: 2)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    image.draw(in: NSRect(x: margin, y: margin, width: image.size.width, height: image.size.height))
    NSGraphicsContext.restoreGraphicsState()
    guard let made = context.makeImage() else { return nil }
    return mjPixels(made)
}
