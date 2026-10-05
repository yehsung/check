import AppKit
import Foundation
import Testing
@testable import check
@testable import CheckCore

// MARK: - 걷기 프레임 사이에서 **캐릭터가 바뀌지 않는다** (2026-10-05 신설)
//
// 왜 새로 만드나: 로봇(일곱 번째 캐릭터)을 굽는 동안 **같은 결함이 세 번** 났고, 그때 있던 숫자 계약
// (초상 비·box 폭차·26pt 커버리지·earWidth·다리 띠 IoU·셀 크기)은 **매번 전부 초록**이었다.
//   ① 라운드1 — 접지A 가 몸통을 잃어 "녹아내린 불가사리"가 됐다.
//   ② 라운드2 — 접지B 만 머리 포드가 8배 작아(큰 크림 원반이 통째로 없고 단추만 남아) 초당 1.8회 깜빡였다.
//   ③ 라운드3 — 접지B 가 3/4 정면 카메라로 그려져 **부츠 주색이 틸에서 크림으로 뒤집혔다.**
// 세 번 다 **모양**(실루엣·IoU·비·크기)만 재고 **색 구성**과 **부품의 존재**를 아무도 안 쟀기 때문이다.
// `sideWalk` 는 0,1,2,1 × 140ms 로 돌아서(매니페스트 실측) 한 칸만 달라도 **초당 1.8회** 눈에 띈다.
//
// 여기서 재는 두 축(둘 다 **결과**를 잰다 — 부르는 자리가 아니라 픽셀이다):
//   ⓐ **발 대역**(아래 10%) 주색 비율의 프레임 간 진폭  → ①·③ 을 잡는다.
//   ⓑ **머리 대역**(위 25%) 주색 비율의 진폭 + **위 절반 가장 큰 회색 덩어리 지름**의 진폭  → ①·② 를 잡는다.
// 두 축이 서로 다른 결함을 잡는다는 것까지 실측했다(아래 표). 하나로 합치면 ② 가 다시 샌다.
//
// ---------------------------------------------------------------------------------------------
// 2026-10-05 실측 (스크래치패드 `chess/art/graft/footband.py` 와 **같은 산식**, 이 파일이 Swift 로 옮긴 것)
//
//                              ⓐ 발 대역 진폭   ⓑ-1 머리 위25% 진폭   ⓑ-2 위절반 회색덩어리 진폭
//   기존 5종 ─ squirrel            0.0003            0.0001                 0.0059
//              shiba               0.0007            0.0001                 0.0078
//              jellyfish           0.0019            0.0087                 0.0020
//              ghost               0.0030            0.0012                 0.0020
//              fox                 0.0055            0.00007                0.0020
//   → **기존 5종 띠**              0.0003~0.0055     0.00007~0.0087         0.0020~0.0078
//   robot (지금 번들에 든 것)       0.0417            0.0436                 0.0020
//   ─── 결함본(이식 전 사본) ───
//   라운드1 결함① (불가사리)       0.1755 ✗          0.0099                 0.0509 ✗
//   라운드2 결함② (포드 8배)       0.0334            0.0859 ✗               0.0586 ✗
//   라운드3 결함③ (부츠 뒤집힘)     0.4051 ✗          0.0439                 0.0039
//
// ✗ 는 **실제로 빨개진 것을 실증한 자리**다(2026-10-05). 결함본 아틀라스를
// `Sources/check/Characters/robot/atlas.png` 에 임시로 덮고 이 세 테스트를 돌려 확인한 뒤 바이트 동일로 원복했다
// (라운드1 은 아틀라스가 1416×516 이라 `manifest.json` 까지 같이 바꿔야 한다 — 매니페스트와 PNG 크기가 갈리면
// 로더가 로봇을 통째로 버려 "6종이 아니라 5종"으로 빨개지고, 그건 이 계약이 잡은 게 아니다).
// 결함본 보관처: 스크래치패드 `chess/art/out-final`(라운드1) · `chess/art/walk1/out-final`(라운드2) ·
// `chess/art/graft/base`(라운드3). 셋 다 **저장소 밖**이다.
//
// **임계를 어디서 끌어왔는가**
//  · ⓐ·ⓑ-1 = **0.05**. 기존 5종 상한(0.0055 · 0.0087)의 **9배·5.7배**이고, 결함본 최저값
//    (라운드1 0.1755 · 라운드2 0.0859)의 **3.5배·1.7배 아래**다. 로봇이 0.0417·0.0436 으로 띠 밖에
//    혼자 높은 것은 **그림의 성질**이다(부츠·머리가 틸+크림 두 색이라 자세에 따라 크림 하이라이트 화소가
//    조금씩 는다 — 기존 5종은 그 대역이 한 색이라 0.001 대로 떨어진다). 그래서 5종 띠로 조이면 로봇이
//    영원히 빨갛고, 결함본을 못 잡을 만큼 풀면 장식이 된다. 0.05 가 **둘 다 되는 유일한 자리**다.
//    ⚠️ 여유가 1.15배뿐이라 **로봇을 다시 구우면 이 숫자를 다시 재야 한다.** 자산은 정적이라
//    실행마다 흔들리지 않는다 — 좁은 여유는 깜빡임이 아니라 **민감도**다.
//  · ⓑ-2 = **0.020**. 기존 5종 상한(0.0078)의 2.6배이고 결함본 최저(라운드1 0.0509)의 2.9배 아래 —
//    두 쪽 여유가 거의 같은 자리(기하평균 0.020)다.
//
// **왜 ⓑ-2 가 따로 있는가**: 결함② 를 ⓑ-1 로도 잡기는 하지만(0.0859 > 0.05) 여유가 1.7배뿐이고,
// 라운드1 은 ⓑ-1 로 **안 잡힌다**(0.0099 — 5종 띠 안이다). 포드가 사라진 것은 '색 비율'이 아니라
// **덩어리의 존재**라서, 그걸 바로 재는 축이 있어야 ② 가 두 번 다시 안 샌다.
// ---------------------------------------------------------------------------------------------

/// 걷기 칸을 픽셀로 재는 도구. 스크래치패드 `chess/art/graft/footband.py` 와 **같은 산식**이다
/// (색상 히스토그램 봉우리 → 봉우리 ±90° 안 유채 화소의 비율). 파이썬 쪽 숫자와 맞춰 두었으니
/// 숫자가 갈리면 둘 중 하나가 바뀐 것이다.
@MainActor
enum V0343WalkFrames {
    /// 유채색으로 셀 기준. 이보다 무색한 화소(크로마 < 10)는 색상이 뜻을 잃어 주색 집계에서 뺀다.
    static let chromaFloor = 10.0
    /// 주색으로 셀 색상 창(도). ±90° — 조명으로 색상이 돌아도 같은 부품은 같은 반원에 남는다.
    static let hueWindow = 90.0

    /// 아틀라스 셀 하나. `pixels` 는 **프리멀티플라이 RGBA 그대로**이고, 색은 `rgb(_:_:)` 가
    /// 알파로 되나눠 PNG 원본 정수로 돌려준다(비프리멀티플라이 비트맵 컨텍스트는 CoreGraphics 가 안 만들어 준다).
    struct Cell {
        let width: Int
        let height: Int
        let pixels: [UInt8]

        func alpha(_ x: Int, _ y: Int) -> Int { Int(pixels[(y * width + x) * 4 + 3]) }

        /// 알파를 되나눈 RGB(0~255 정수). 로봇 아틀라스는 화소의 97% 가 알파 253 이라(warp 가 남긴 값)
        /// 되나누지 않으면 색이 통째로 어두워져 파이썬 계측과 갈린다.
        func rgb(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
            let i = (y * width + x) * 4
            let a = Double(pixels[i + 3])
            guard a > 0 else { return (0, 0, 0) }
            let k = 255.0 / a
            return (Int((Double(pixels[i]) * k).rounded()),
                    Int((Double(pixels[i + 1]) * k).rounded()),
                    Int((Double(pixels[i + 2]) * k).rounded()))
        }
    }

    /// 종당 한 번만 디코드·자른다(셀 하나가 20만 화소라 세 테스트가 각자 읽으면 그만큼 느려진다).
    private static var cellCache: [String: [Cell]] = [:]

    /// `sideWalk` 의 **서로 다른** 칸들(재생 순서대로, 같은 rect 는 한 번만).
    /// 여우식 0,1,2,1 재생이라 네 번 중 하나는 중복이다 — 중복까지 재면 진폭이 저절로 작아진다.
    static func walkCells(_ id: String) -> [Cell]? {
        if let hit = cellCache[id] { return hit }
        guard let cells = decodeWalkCells(id) else { return nil }
        cellCache[id] = cells
        return cells
    }

    private static func decodeWalkCells(_ id: String) -> [Cell]? {
        guard let manifest = CheckCharacter3DScene.catalog.manifest(id: id),
              let state = manifest.atlas?.states[CharacterManifest.StateKey.sideWalk],
              let atlas = CheckCharacter3DScene.atlasImage(for: manifest) else { return nil }
        var seen: [(x: Int, y: Int)] = []
        var cells: [Cell] = []
        for rect in state.frames {
            if seen.contains(where: { $0.x == rect.x && $0.y == rect.y }) { continue }
            seen.append((rect.x, rect.y))
            // 매니페스트 `Rect` 과 `CGImage.cropping(to:)` 은 둘 다 **픽셀·좌상단 원점**이라 부호를 안 뒤집는다.
            guard let crop = atlas.cropping(to: CGRect(x: rect.x, y: rect.y, width: rect.w, height: rect.h)),
                  let cell = read(crop) else { return nil }
            cells.append(cell)
        }
        return cells
    }

    static func read(_ image: CGImage) -> Cell? {
        let w = image.width, h = image.height
        guard w > 0, h > 0 else { return nil }
        var pixels = [UInt8](repeating: 0, count: w * h * 4)
        let ok: Bool = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let ctx = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                      bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return ok ? Cell(width: w, height: h, pixels: pixels) : nil
    }

    // MARK: 띠 잡기

    enum Edge { case top, bottom }

    /// 걷기 칸 **전체의 합집합** 내용 행에서 띠를 자른다. 칸마다 자기 bbox 로 자르면 바운스(머리가 올라간
    /// passing 프레임)가 띠를 같이 밀어 올려 **깜빡임이 저절로 사라진다** — 세 칸은 같은 접지선을 쓰므로
    /// 합집합으로 한 번만 자르는 것이 맞다.
    static func bandRows(cells: [Cell], fraction: Double, edge: Edge) -> ClosedRange<Int>? {
        var top = Int.max, bottom = -1
        for cell in cells {
            for y in 0..<cell.height {
                var any = false
                for x in 0..<cell.width where cell.alpha(x, y) > 8 { any = true; break }
                if any {
                    if y < top { top = y }
                    if y > bottom { bottom = y }
                }
            }
        }
        guard bottom >= top, top != Int.max else { return nil }
        let height = bottom - top + 1
        let rows = max(1, Int((Double(height) * fraction).rounded()))
        switch edge {
        case .bottom: return (bottom - rows + 1)...bottom
        case .top: return top...(top + rows - 1)
        }
    }

    /// 내용 높이(합집합) — 지름을 정규화하는 분모다.
    static func contentHeight(cells: [Cell]) -> Int? {
        guard let rows = bandRows(cells: cells, fraction: 1.0, edge: .top) else { return nil }
        return rows.count
    }

    /// 띠 안의 불투명 화소 색 목록.
    static func bandPixels(cell: Cell, rows: ClosedRange<Int>) -> [(r: Int, g: Int, b: Int)] {
        var out: [(r: Int, g: Int, b: Int)] = []
        for y in rows where y >= 0 && y < cell.height {
            for x in 0..<cell.width where cell.alpha(x, y) > 8 {
                out.append(cell.rgb(x, y))
            }
        }
        return out
    }

    // MARK: 색상·주색 비율

    /// HSV 색상(0~360)과 크로마(max − min). **밝기를 안 쓴다** — 같은 부품이 조명 때문에 여러 밝기로
    /// 찍히더라도 색상은 안 갈리기 때문이다(그래서 "부츠가 어두워졌다"와 "부츠 색이 바뀌었다"를 가른다).
    static func hueAndChroma(_ p: (r: Int, g: Int, b: Int)) -> (hue: Double, chroma: Double) {
        let r = Double(p.r), g = Double(p.g), b = Double(p.b)
        let mx = max(r, max(g, b)), mn = min(r, min(g, b))
        let d = mx - mn
        guard d > 1e-9 else { return (0, 0) }
        var hue: Double
        if mx == b { hue = 60 * ((r - g) / d) + 240 } else if mx == g { hue = 60 * ((b - r) / d) + 120 } else {
            hue = (60 * ((g - b) / d)).truncatingRemainder(dividingBy: 360)
            if hue < 0 { hue += 360 }
        }
        return (hue, d)
    }

    /// 세 칸의 띠를 **합쳐** 만든 색상 히스토그램(가중치 = 크로마)의 봉우리. σ=12° 원형 가우시안으로 고르고 argmax.
    /// 칸별로 따로 구하면 "칸마다 제 주색을 고른다"가 돼서 깜빡임이 계측에서 사라진다 — 반드시 합쳐서 한 번만.
    static func peakHue(_ bands: [[(r: Int, g: Int, b: Int)]]) -> Double {
        var hist = [Double](repeating: 0, count: 360)
        for band in bands {
            for p in band {
                let (hue, chroma) = hueAndChroma(p)
                guard chroma >= chromaFloor else { continue }
                hist[min(359, max(0, Int(hue)))] += chroma
            }
        }
        var kernel = [Double]()
        for k in -60...60 { kernel.append(exp(-0.5 * pow(Double(k) / 12.0, 2))) }
        var best = 0, bestValue = -1.0
        for j in 0..<360 {
            var sum = 0.0
            for (index, k) in (-60...60).enumerated() { sum += hist[((j + k) % 360 + 360) % 360] * kernel[index] }
            if sum > bestValue { bestValue = sum; best = j }
        }
        return Double(best)
    }

    /// 띠의 **유채 화소 중** 주색상 ±90° 안에 드는 비율. 분모를 유채 화소로 두는 이유:
    /// 전체 화소로 나누면 무채색(차콜·크림) 몫이 조명·그림자에 흔들려 기존 5종이 0.08 까지 올라가
    /// **결함본과 겹친다**(실측: 전체 분모면 jellyfish 0.0834 · 결함② 0.2000 — 띠가 안 갈린다).
    static func dominantHueShare(_ band: [(r: Int, g: Int, b: Int)], peak: Double) -> Double {
        var chromatic = 0, inside = 0
        for p in band {
            let (hue, chroma) = hueAndChroma(p)
            guard chroma >= chromaFloor else { continue }
            chromatic += 1
            var delta = (hue - peak + 180).truncatingRemainder(dividingBy: 360)
            if delta < 0 { delta += 360 }
            if abs(delta - 180) <= hueWindow { inside += 1 }
        }
        return chromatic == 0 ? 0 : Double(inside) / Double(chromatic)
    }

    // MARK: 회색 덩어리(머리 포드)

    /// 띠 안에서 가장 큰 **중간 회색 연결 덩어리**의 지름(bbox 장변) ÷ 내용 높이.
    /// 중간 회색 = 크로마 < 26 · 최대채널 70~165 — 로봇 머리 옆면의 회색 포드가 그 띠다
    /// (앞쪽 차콜 바이저는 최대채널 70 아래라 안 들어온다 — 포드 탐지가 바이저를 집으면 0.100 을 0.370 으로 읽는다).
    /// 회색 부품이 없는 종은 작은 잡티만 잡혀 지름이 0.002~0.008 로 **움직이지 않는다** — 그래서 6종 공통으로 쓸 수 있다.
    static func largestGrayBlobDiameter(cell: Cell, rows: ClosedRange<Int>, contentHeight: Int) -> Double {
        let w = cell.width
        let lo = max(0, rows.lowerBound), hi = min(cell.height - 1, rows.upperBound)
        guard hi >= lo, contentHeight > 0 else { return 0 }
        let bandHeight = hi - lo + 1
        var mask = [Bool](repeating: false, count: w * bandHeight)
        for y in lo...hi {
            for x in 0..<w where cell.alpha(x, y) > 8 {
                let p = cell.rgb(x, y)
                let mx = max(p.r, max(p.g, p.b)), mn = min(p.r, min(p.g, p.b))
                if mx - mn < 26, mx > 70, mx < 165 { mask[(y - lo) * w + x] = true }
            }
        }
        // 4-이웃 연결 성분(scipy.ndimage.label 의 기본 구조와 같다). 큐로 훑어 가장 넓은 덩어리의 bbox 장변을 센다.
        var seen = [Bool](repeating: false, count: w * bandHeight)
        var bestDiameter = 0
        var bestArea = 0
        var queue = [Int]()
        for start in 0..<(w * bandHeight) where mask[start] && !seen[start] {
            queue.removeAll(keepingCapacity: true)
            queue.append(start)
            seen[start] = true
            var area = 0
            var minX = w, maxX = -1, minY = bandHeight, maxY = -1
            var head = 0
            while head < queue.count {
                let index = queue[head]; head += 1
                let x = index % w, y = index / w
                area += 1
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
                if x > 0, mask[index - 1], !seen[index - 1] { seen[index - 1] = true; queue.append(index - 1) }
                if x + 1 < w, mask[index + 1], !seen[index + 1] { seen[index + 1] = true; queue.append(index + 1) }
                if y > 0, mask[index - w], !seen[index - w] { seen[index - w] = true; queue.append(index - w) }
                if y + 1 < bandHeight, mask[index + w], !seen[index + w] {
                    seen[index + w] = true; queue.append(index + w)
                }
            }
            if area > bestArea {
                bestArea = area
                bestDiameter = max(maxX - minX + 1, maxY - minY + 1)
            }
        }
        return Double(bestDiameter) / Double(contentHeight)
    }

    // MARK: 종 목록 · 한 종의 계측

    /// `sideWalk` 가 있는 스프라이트 종 전부(아잉은 3D 라 빠진다). id 정렬.
    static var walkingSpecies: [String] {
        let catalog = CheckCharacter3DScene.catalog
        return catalog.allIDs.filter { id in
            guard let manifest = catalog.manifest(id: id), manifest.kind == .sprite else { return false }
            return manifest.atlas?.states[CharacterManifest.StateKey.sideWalk] != nil
        }.sorted()
    }

    /// 기준선으로 쓰는 **기존 5종**. 로봇이 들어오기 전부터 배포돼 있던 종이고, 임계는 이들의 실측 띠에서 나왔다.
    static let legacySpecies = ["fox", "ghost", "jellyfish", "shiba", "squirrel"]

    struct BandReading {
        var perFrame: [Double]
        var amplitude: Double { (perFrame.max() ?? 0) - (perFrame.min() ?? 0) }
        /// 띠에 든 불투명 화소 수(칸별). 띠를 잘못 잡으면 여기가 0 에 가까워진다.
        var pixelCounts: [Int]
    }

    /// 한 종의 띠 주색 비율. `edge` 가 `.bottom` 이면 발 대역, `.top` 이면 머리 대역이다.
    static func hueShareReading(_ id: String, fraction: Double, edge: Edge) -> BandReading? {
        guard let cells = walkCells(id), cells.count >= 2,
              let rows = bandRows(cells: cells, fraction: fraction, edge: edge) else { return nil }
        let bands = cells.map { bandPixels(cell: $0, rows: rows) }
        let peak = peakHue(bands)
        return BandReading(perFrame: bands.map { dominantHueShare($0, peak: peak) },
                           pixelCounts: bands.map(\.count))
    }

    /// 한 종의 위 절반 회색 덩어리 지름.
    static func grayBlobReading(_ id: String, fraction: Double = 0.50) -> BandReading? {
        guard let cells = walkCells(id), cells.count >= 2,
              let rows = bandRows(cells: cells, fraction: fraction, edge: .top),
              let height = contentHeight(cells: cells) else { return nil }
        return BandReading(
            perFrame: cells.map { largestGrayBlobDiameter(cell: $0, rows: rows, contentHeight: height) },
            pixelCounts: cells.map { bandPixels(cell: $0, rows: rows).count })
    }
}

// MARK: - ⓐ 발 대역 색 안정성

@MainActor
@Suite("v0.3.43 스프라이트 걷기 — 발 대역 색 안정성")
struct V0343SpriteWalkFootBandTests {
    /// 아래 10% 띠의 주색 비율이 프레임마다 거의 같아야 한다.
    ///
    /// **임계 0.05 의 근거**(2026-10-05 실측 · 위 머리글 표):
    /// 기존 5종 **0.0003~0.0055**(squirrel 0.0003 · shiba 0.0007 · jellyfish 0.0019 · ghost 0.0030 · fox 0.0055),
    /// 로봇 0.0417, 결함본 **라운드1 0.1755 · 라운드3 0.4051**(둘 다 실제로 빨개지는 것을 확인했다).
    /// 0.05 는 5종 상한의 9배이고 결함본 최저의 3.5배 아래다.
    @Test func 발_대역_주색_비율이_걷기_프레임_사이에서_흔들리지_않는다() throws {
        let species = V0343WalkFrames.walkingSpecies
        #expect(species.count == 6, "걷는 스프라이트가 \(species.count) 종이다(기대 6) — \(species)")
        #expect(species.contains("robot"), "로봇이 빠졌다 — 이 계약은 로봇 때문에 생겼다")

        var amplitudes: [(String, Double)] = []
        for id in species {
            let reading = try #require(V0343WalkFrames.hueShareReading(id, fraction: 0.10, edge: .bottom),
                                       "\(id) 발 대역을 못 쟀다 — sideWalk 칸이나 아틀라스가 없다")
            // 띠가 실제로 몸을 담고 있어야 한다. 비어 있으면 진폭이 0 이 되어 이 테스트가 장식이 된다.
            #expect(reading.perFrame.count >= 3, "\(id) 서로 다른 걷기 칸이 \(reading.perFrame.count) 개뿐이다")
            // 띠가 비어 있으면 진폭이 0 이 되어 이 계약이 장식이 된다. 하한 200 은 실측에서 끌어왔다 —
            // 가장 가는 발이 해파리 촉수(439·885·5624)이고, 나머지는 3,360~14,095 다.
            for count in reading.pixelCounts {
                #expect(count > 200, "\(id) 발 대역 화소 \(count) — 띠를 잘못 잡았다")
            }
            amplitudes.append((id, reading.amplitude))
            let note = "\(id) 발 대역 주색 비율이 프레임 사이에서 \(reading.amplitude) 흔들린다 "
                + "(칸별 \(reading.perFrame)) — 걷다가 발 색이 바뀐다. 기존 5종은 0.0003~0.0055 다"
            #expect(reading.amplitude <= 0.05, "\(note)")
        }

        // ★ 기준선을 **같은 테스트가 같이 잰다** — 임계가 어디서 왔는지 보이지 않으면 아무도 못 고친다.
        let legacy = amplitudes.filter { V0343WalkFrames.legacySpecies.contains($0.0) }
        #expect(legacy.count == 5, "기존 5종 중 \(legacy.count) 종만 쟀다 — \(amplitudes)")
        let legacyHigh = try #require(legacy.map(\.1).max())
        let legacyNote = "기존 5종 띠가 \(legacyHigh) 까지 올라갔다 — 임계 0.05 의 근거(0.0003~0.0055)가 "
            + "더 이상 맞지 않는다. 결함본(0.1755·0.4051)과의 거리를 다시 재고 임계를 다시 끌어내라. \(legacy)"
        #expect(legacyHigh <= 0.010, "\(legacyNote)")

        // ★ 비교 기준선이 **실제로 달라야** 뜻이 있다: 이 계측이 프레임 차이에 반응하는지부터 본다.
        //   모든 종이 정확히 0 이면 띠·주색을 잘못 골라 "언제나 초록"인 숫자를 재고 있는 것이다.
        let overall = try #require(amplitudes.map(\.1).max())
        #expect(overall > 0.0002,
                "여섯 종 진폭이 전부 \(overall) 이하다 — 계측이 프레임 차이에 반응하지 않는다. \(amplitudes)")
    }
}

// MARK: - ⓑ 머리 대역 안정성

@MainActor
@Suite("v0.3.43 스프라이트 걷기 — 머리 대역 안정성")
struct V0343SpriteWalkHeadBandTests {
    /// 위 25% 띠의 주색 비율. 기존 5종 **0.00007~0.0087**, 로봇 0.0436, 결함② (포드 8배) **0.0859**.
    /// 임계 0.05 는 5종 상한의 5.7배이고 결함② 의 1.7배 아래다.
    ///
    /// 이 축만으로는 **부족하다**: 라운드1(몸통 잃은 접지A)은 여기서 0.0099 — 5종 띠 안이다.
    /// 그래서 아래 `머리_회색_포드가_...` 가 같은 결함을 **덩어리의 존재**로 따로 잰다.
    @Test func 머리_대역_주색_비율이_걷기_프레임_사이에서_흔들리지_않는다() throws {
        let species = V0343WalkFrames.walkingSpecies
        #expect(species.count == 6, "걷는 스프라이트가 \(species.count) 종이다(기대 6)")

        var amplitudes: [(String, Double)] = []
        for id in species {
            let reading = try #require(V0343WalkFrames.hueShareReading(id, fraction: 0.25, edge: .top),
                                       "\(id) 머리 대역을 못 쟀다")
            #expect(reading.perFrame.count >= 3, "\(id) 서로 다른 걷기 칸이 \(reading.perFrame.count) 개뿐이다")
            // 하한 2000: 실측 머리 띠 화소는 9,276(시바 접지A)~34,820(해파리) 이다.
            for count in reading.pixelCounts {
                #expect(count > 2000, "\(id) 머리 대역 화소 \(count) — 띠를 잘못 잡았다")
            }
            amplitudes.append((id, reading.amplitude))
            let note = "\(id) 머리 대역 주색 비율이 프레임 사이에서 \(reading.amplitude) 흔들린다 "
                + "(칸별 \(reading.perFrame)) — 걷다가 머리 색 구성이 바뀐다. 기존 5종은 0.00007~0.0087 다"
            #expect(reading.amplitude <= 0.05, "\(note)")
        }

        let legacy = amplitudes.filter { V0343WalkFrames.legacySpecies.contains($0.0) }
        #expect(legacy.count == 5, "기존 5종 중 \(legacy.count) 종만 쟀다 — \(amplitudes)")
        let legacyHigh = try #require(legacy.map(\.1).max())
        #expect(legacyHigh <= 0.015,
                "기존 5종 띠가 \(legacyHigh) 까지 올라갔다 — 임계 0.05 의 근거(0.00007~0.0087)가 안 맞는다. \(legacy)")

        let overall = try #require(amplitudes.map(\.1).max())
        #expect(overall > 0.0002,
                "여섯 종 진폭이 전부 \(overall) 이하다 — 계측이 프레임 차이에 반응하지 않는다. \(amplitudes)")
    }

    /// ★ **결함② 를 바로 잡는 축.** 위 절반에서 가장 큰 중간 회색 덩어리의 지름(÷내용 높이)이
    /// 프레임마다 같아야 한다. 로봇 머리 옆면의 **회색 포드**가 그 덩어리다.
    ///
    /// 2026-10-05 실측: 기존 5종 **0.0020~0.0078**(fox·ghost·jellyfish 0.0020 · squirrel 0.0059 · shiba 0.0078),
    /// 로봇 0.0020, 결함본 **라운드1 0.0509 · 라운드2 0.0586**(라운드3 은 0.0039 — 그건 발 대역이 잡는다).
    /// 임계 **0.020** = 5종 상한의 2.6배 · 결함본 최저의 2.9배 아래(두 쪽 여유가 같은 자리, 기하평균 0.020).
    ///
    /// 회색 부품이 없는 종(유령·해파리)은 작은 잡티만 잡혀 지름이 0.004~0.008 에 머문다 — 그래서
    /// 6종 공통 계약으로 쓸 수 있다. 그 성질 자체를 아래에서 같이 단언한다.
    @Test func 머리_회색_포드가_걷기_프레임마다_같은_크기다() throws {
        let species = V0343WalkFrames.walkingSpecies
        #expect(species.count == 6, "걷는 스프라이트가 \(species.count) 종이다(기대 6)")

        var amplitudes: [(String, Double)] = []
        var robotDiameters: [Double] = []
        for id in species {
            let reading = try #require(V0343WalkFrames.grayBlobReading(id), "\(id) 위 절반을 못 쟀다")
            #expect(reading.perFrame.count >= 3, "\(id) 서로 다른 걷기 칸이 \(reading.perFrame.count) 개뿐이다")
            amplitudes.append((id, reading.amplitude))
            if id == "robot" { robotDiameters = reading.perFrame }
            let note = "\(id) 위 절반 회색 덩어리 지름이 프레임 사이에서 \(reading.amplitude) 흔들린다 "
                + "(칸별 \(reading.perFrame)) — 머리 부품이 한 칸에서 사라졌거나 크기가 갈렸다. "
                + "기존 5종은 0.0020~0.0078 다"
            #expect(reading.amplitude <= 0.020, "\(note)")
        }

        let legacy = amplitudes.filter { V0343WalkFrames.legacySpecies.contains($0.0) }
        #expect(legacy.count == 5, "기존 5종 중 \(legacy.count) 종만 쟀다 — \(amplitudes)")
        let legacyHigh = try #require(legacy.map(\.1).max())
        #expect(legacyHigh <= 0.012,
                "기존 5종 띠가 \(legacyHigh) 까지 올라갔다 — 임계 0.020 의 근거(0.0020~0.0078)가 안 맞는다. \(legacy)")

        // ★ 이 숫자가 **진짜 포드를 보고 있다**는 증거. 로봇만 지름이 0.15 대(내용 높이 512 에서 약 81px)이고,
        //   회색 부품이 없는 종은 0.05 를 못 넘는다. 로봇 지름이 잡티 수준으로 떨어지면 마스크가
        //   포드를 놓친 것이므로, 진폭이 0 이어도 이 테스트는 아무것도 안 보는 상태가 된다.
        #expect(robotDiameters.count >= 3, "로봇 칸을 못 쟀다")
        let robotLow = try #require(robotDiameters.min())
        let podNote = "로봇 회색 포드 지름이 \(robotDiameters) 로 잡혔다 — 마스크(크로마<26 · 최대채널 70~165)가 "
            + "포드를 놓쳤다. 이 상태면 진폭이 0 이라도 계약이 아무것도 안 본다"
        #expect(robotLow > 0.10, "\(podNote)")
        for (id, _) in legacy {
            let reading = try #require(V0343WalkFrames.grayBlobReading(id))
            let high = try #require(reading.perFrame.max())
            let note = "\(id) 위 절반 회색 덩어리 지름이 \(high) — 회색 부품이 없던 종에서 큰 덩어리가 잡혔다. "
                + "마스크가 넓어졌으면 로봇 포드와 구분이 안 된다"
            #expect(high < 0.10, "\(note)")
        }
    }
}
