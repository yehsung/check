import AppKit
import CoreGraphics
import Foundation
import ImageIO
import SceneKit
import Testing
@testable import check
@testable import CheckCore

/// v0.3.59 무지개 아잉이 그림 계약 — `scripts/make-rainbow-aing.swift` 산출물 41장(밝기 맵 · 후광 정면 + 각도 칸 35 · 초상 2 + 폰 사본 2).
/// 모양(파일 · 크기 · 알파)만 재지 않고 결과(초상의 띠 색 순서 · 후광 둘레 색 · 밝기 맵이 무엇을 다듬었나)를 재고, 결과 단언마다 지금
/// 아잉(또는 황금)으로 같은 잣대를 돌린 기준선을 붙인다. 스크립트의 결정성(두 번 구워도 같은 바이트)과 팔레트 상수(앱 셰이더와 같은 글자)도 잰다.
@Suite struct V0359RainbowArtTests {
    static let macDir = V0354GoldAingArtTests.macDir
    static let phoneDir = V0354GoldAingArtTests.phoneDir
    static let expressions = ["neutral", "negative"]

    static func image(_ name: String) throws -> CGImage {
        try V0354GoldAingArtTests.image(macDir.appendingPathComponent("\(name).png"))
    }

    /// sRGB 바이트(0…255) → OKLab (L, C, h°).
    static func oklch(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> (L: Double, C: Double, h: Double) {
        func lin(_ v: UInt8) -> Double { let x = Double(v) / 255; return x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
        let c = SIMD3(lin(r), lin(g), lin(b))
        let l = cbrt(0.4122214708 * c.x + 0.5363325363 * c.y + 0.0514459929 * c.z)
        let m = cbrt(0.2119034982 * c.x + 0.6806995451 * c.y + 0.1073969566 * c.z)
        let s = cbrt(0.0883024619 * c.x + 0.2817188376 * c.y + 0.6299787005 * c.z)
        let L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
        let a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
        let bb = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
        var h = atan2(bb, a) * 180 / .pi
        if h < 0 { h += 360 }
        return (L, (a * a + bb * bb).squareRoot(), h)
    }

    static func hueDistance(_ a: Double, _ b: Double) -> Double {
        var d = (a - b).truncatingRemainder(dividingBy: 360)
        if d < 0 { d += 360 }
        return min(d, 360 - d)
    }

    /// 원형 평균 색상(°).
    static func meanHue(_ hues: [Double]) -> Double {
        let x = hues.reduce(0) { $0 + cos($1 * .pi / 180) }, y = hues.reduce(0) { $0 + sin($1 * .pi / 180) }
        var h = atan2(y, x) * 180 / .pi
        if h < 0 { h += 360 }
        return h
    }

    // MARK: - 파일

    @Test("산출물 41장: 밝기 맵 512² 불투명 · 후광 512² + 칸 35장 160² · 초상 192² — 맥 리소스 번들에서 이름으로 찾히고 폰 사본은 바이트 그대로")
    func filesExist() throws {
        let shade = try Self.image(RainbowAingArt.shadeResourceName)
        #expect(shade.width == 512 && shade.height == 512)
        #expect(V0354GoldAingArtTests.rgba(shade).enumerated().allSatisfy { $0.offset % 4 != 3 || $0.element == 255 }, "밝기 맵에 투명 텍셀")
        for (cell, name) in RainbowAingArt.haloCellResourceNames.enumerated() {
            let halo = try Self.image(name)
            let side = cell == 0 ? 512 : 160
            #expect(halo.width == side && halo.height == side, "\(name) \(halo.width)×\(halo.height)")
            #expect(V0354GoldAingArtTests.borderAlpha(halo) <= 0.04, "\(name) 테두리 알파 \(V0354GoldAingArtTests.borderAlpha(halo))")
            #expect(V0354GoldAingArtTests.maxAlpha(halo) > 0.9, "\(name) 이 비어 있다")
            #expect(CheckResources.bundle.url(forResource: name, withExtension: "png") != nil, "\(name).png 이 앱 리소스 번들에 없다")
        }
        for e in Self.expressions {
            let name = "aing_rainbow-\(e)"
            let portrait = try Self.image(name)
            #expect(portrait.width == 192 && portrait.height == 192)
            #expect(V0354GoldAingArtTests.borderAlpha(portrait) <= 0.04, "\(name) 테두리 알파")
            let mac = try Data(contentsOf: Self.macDir.appendingPathComponent("\(name).png"))
            let phone = try Data(contentsOf: Self.phoneDir.appendingPathComponent("\(name).png"))
            #expect(mac == phone, "폰 사본 \(name).png 이 맥 원본과 바이트가 다르다")
        }
        for name in RainbowAingArt.requiredResourceNames(for: .mac) {
            #expect(CheckResources.bundle.url(forResource: name, withExtension: "png") != nil, "\(name).png 이 앱 리소스 번들에 없다")
        }
        #expect(RainbowAingFinish.isDrawable())
    }

    // MARK: - 밝기 맵

    /// 밝기 맵은 **라벤더**다 — 모든 텍셀이 셰이더의 피부 판정(isGoldSkin)을 지나야 합성 뒤 무지개가 된다(눈·볼·입 자리까지: 감은 눈 커버).
    /// 다듬은 것: 눈·볼·입 둘레 8텍셀 안의 어두운 테(밝아진다) · 그 밖은 원본 밝기 그대로(티끌 1–2텍셀만). 기준선 = 원본 디퓨즈.
    @MainActor
    @Test("밝기 맵: 모든 텍셀이 피부 판정 · 장식 둘레의 어두운 테만 밝아지고 나머지 피부 밝기는 원본 그대로 — 원본은 같은 잣대에서 갈린다")
    func shadeMapIsCleanedLavender() throws {
        let shade = SleepEyeExplore.rgbaBuffer(try Self.image(RainbowAingArt.shadeResourceName))
        let scene = try #require(CheckCharacter3DScene.makeScene(animated: false, character: CharacterCatalog.builtInAing))
        let original = SleepEyeExplore.rgbaBuffer(try V0354GoldAing3DTests.faceImage(scene))
        // 메시가 실제로 쓰는 텍셀만 잰다(UV 틈은 팽창으로 채운 값이라 원본과 달라도 화면에 안 나온다).
        let covered = try V0359Rainbow3DTests.uvRaster(scene, size: 512).weight.map { $0 > 0 }
        #expect(original.count == shade.count)
        let n = original.count / 4, side = 512
        var notSkin = 0
        var feature = [Bool](repeating: false, count: n)
        for i in 0..<n {
            if !GoldAingFinish.isGoldSkin(Int(shade[i * 4]), Int(shade[i * 4 + 1]), Int(shade[i * 4 + 2])) { notSkin += 1 }
            feature[i] = !GoldAingFinish.isGoldSkin(Int(original[i * 4]), Int(original[i * 4 + 1]), Int(original[i * 4 + 2]))
        }
        #expect(notSkin == 0, "밝기 맵에 피부 판정 밖 텍셀 \(notSkin) — 셰이더가 그 자리를 라벤더로 남긴다")
        // 장식 둘레(1…8텍셀)와 먼 피부(16텍셀 밖)로 나눈다.
        var near = [Int](repeating: Int.max, count: n)
        for y in 0..<side { for x in 0..<side where feature[y * side + x] {
            for dy in -16...16 { for dx in -16...16 {
                let xx = x + dx, yy = y + dy
                guard xx >= 0, yy >= 0, xx < side, yy < side else { continue }
                near[yy * side + xx] = min(near[yy * side + xx], max(abs(dx), abs(dy)))
            } }
        } }
        func lightness(_ px: [UInt8], _ i: Int) -> Double { Self.oklch(px[i * 4], px[i * 4 + 1], px[i * 4 + 2]).L }
        var ringOriginal = 0.0, ringShade = 0.0, ringCount = 0.0
        var farChanged = 0, farCount = 0, farShift = 0.0
        for i in 0..<n where !feature[i] && covered[i] {
            if near[i] >= 1 && near[i] <= 3 {
                ringOriginal += lightness(original, i); ringShade += lightness(shade, i); ringCount += 1
            } else if near[i] > 16 {
                farCount += 1
                let d = lightness(shade, i) - lightness(original, i)
                farShift += d
                if abs(d) > 0.01 { farChanged += 1 }
            }
        }
        let lift = (ringShade - ringOriginal) / ringCount
        #expect(covered.filter { $0 }.count > 150_000, "UV 래스터가 메시를 못 덮었다")
        let farMean = farShift / Double(max(farCount, 1))
        print(String(format: "[v0359-art] 장식 둘레 1–3텍셀 L 원본 %.4f → 밝기 맵 %.4f (%+.4f, %.0f텍셀) · 먼 피부 평균 %+.4f · 바뀐 텍셀 %d/%d",
                     ringOriginal / ringCount, ringShade / ringCount, lift, ringCount, farMean, farChanged, farCount))
        // 기준선: 같은 잣대(평균 밝기 이동)를 먼 피부에 대면 0 이다 — 둘레만 밝아졌다.
        #expect(lift > 0.015 && lift > abs(farMean) * 10, "장식 둘레 어두운 테가 안 밝아졌다(\(lift) vs 먼 피부 \(farMean)) — 무지개 눈 둘레에 갈색 테가 남는다")
        #expect(abs(farMean) < 0.002, "먼 피부 밝기가 평균 \(farMean) 옮겨졌다")
        #expect(farChanged * 100 < farCount, "먼 피부 \(farChanged)/\(farCount) 텍셀의 밝기가 바뀌었다 — 부피(음영)가 원본과 갈린다")
        // 기준선: 원본은 피부 판정을 다 지나지 못하고(눈·볼·입), 같은 둘레 잣대에서 0 이다.
        let originalNotSkin = (0..<n).filter { feature[$0] }.count
        #expect(originalNotSkin > 1_000, "기준선이 안 갈린다(원본 장식 텍셀 \(originalNotSkin))")
    }

    // MARK: - 팔레트 상수 — 스크립트와 앱이 같은 글자

    /// 스크립트 글에 이 줄이 **살아 있는 선언**으로 있는가. 주석(`//` · `/* */`)을 걷어낸 뒤 줄 단위(앞뒤 공백 무시)로 통째로 같은 줄이 있어야 하고,
    /// `let 이름` 줄이면 그 이름의 `let` 선언이 그 하나뿐이어야 한다 — 옛 줄을 주석으로 남기고 아래에 다른 값을 선언하거나, 줄 일부만 같은
    /// 경우는 통과하지 못한다(검토: 주석 처리한 원래 줄이 계약을 채운 채 실제 상수가 갈렸다).
    static func scriptDeclares(_ script: String, _ line: String) -> Bool {
        let lines = V0351IfConfig.strippingComments(script).split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard lines.contains(line) else { return false }
        guard line.hasPrefix("let "),
              let name = line.dropFirst(4).split(whereSeparator: { $0 == " " || $0 == ":" || $0 == "=" }).first else { return true }
        return lines.filter { $0.hasPrefix("let \(name) ") || $0.hasPrefix("let \(name):") || $0.hasPrefix("let \(name)=") }.count == 1
    }

    @Test("팔레트·몸 좌표·그늘·눈 앵커 상수: 아트 스크립트의 살아 있는 선언(주석 걷음)과 앱 값이 같다 · 셰이더 글도 같은 값 · 주석 속 옛 줄은 계약을 못 채운다")
    func paletteMatchesTheScript() throws {
        let script = try String(contentsOf: CheckCoreSourceLayout.repoRoot.appendingPathComponent("scripts/make-rainbow-aing.swift"), encoding: .utf8)
        func lit(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : "\(v)" }
        let art = RainbowAingArt.self
        let anchors = CheckCharacter3DScene.closedEyeAnchors.map {
            "SIMD2(" + String(format: "%.3f", Double($0.position.x)) + ", " + String(format: "%.3f", Double($0.position.y)) + ")"
        }
        let expected = [
            "let stopLightness: [Double] = [" + art.stopLightness.map { String(format: "%.3f", $0) }.joined(separator: ", ") + "]",
            "let stopChroma: [Double] = [" + art.stopChroma.map { String(format: "%.3f", $0) }.joined(separator: ", ") + "]",
            "let stopHue: [Double] = [" + art.stopHue.map(lit).joined(separator: ", ") + "]",
            "let bodyTop = " + String(format: "%.6f", art.bodyTop),
            "let bodyHeight = " + String(format: "%.6f", art.bodyHeight),
            "let lReference = " + String(format: "%.4f", art.lightnessReference),
            "let chromaSlope = \(art.chromaSlope), chromaFloor = \(art.chromaFloor), chromaCeil = \(art.chromaCeil)",
            "let lightnessMin = \(art.lightnessMin), lightnessMax = \(art.lightnessMax)",
            "let gamutFloor = \(art.gamutFloor), gamutCeil = \(art.gamutCeil)",
            "let shadowWindows: [(centre: Double, inner: Double, outer: Double, lift: Double)] = ["
                + art.shadowWindows.map { "(\(lit($0.centre)), \(lit($0.inner)), \(lit($0.outer)), \(lit($0.lift)))" }.joined(separator: ", ") + "]",
            "return hue >= 215 && hue <= 300 && sat > 0.05 && sat < 0.75 && l > 0.10",
            // 감은 눈 둘레 다시 채우기의 두 눈 앵커 = 앱 감은 눈 앵커(x·y).
            "let eyeAnchors: [SIMD2<Double>] = [" + anchors.joined(separator: ", ") + "]",
        ]
        for line in expected {
            #expect(Self.scriptDeclares(script, line), "스크립트에 이 줄이 살아 있는 선언으로 없다(앱 상수와 갈렸다): \(line)")
            // 기준선: 주석 속에만 있는 줄은 계약을 못 채운다(줄 주석 · 블록 주석).
            #expect(!Self.scriptDeclares("// " + line + "\n", line) && !Self.scriptDeclares("/* " + line + " */\n", line),
                    "기준선: 주석 속 줄이 계약을 채운다 — \(line)")
        }
        // 기준선(검토가 실제로 해 본 표류): 원래 줄을 주석으로 남기고 다른 값을 선언하면 걸린다.
        let slope = "let chromaSlope = \(art.chromaSlope), chromaFloor = \(art.chromaFloor), chromaCeil = \(art.chromaCeil)"
        let hue = "let stopHue: [Double] = [" + art.stopHue.map(lit).joined(separator: ", ") + "]"
        #expect(script.contains(slope) && script.contains(hue))
        let drifted = script
            .replacingOccurrences(of: slope, with: "// " + slope + "\nlet chromaSlope = 3.6, chromaFloor = \(art.chromaFloor), chromaCeil = \(art.chromaCeil)")
            .replacingOccurrences(of: hue, with: "/* " + hue + " */\nlet stopHue: [Double] = [10, 58, 100, 145, 240, 272, 330]")
        #expect(!Self.scriptDeclares(drifted, slope), "기준선: 주석으로 남긴 chromaSlope 옛 줄이 계약을 채운다")
        #expect(!Self.scriptDeclares(drifted, hue), "기준선: 블록 주석으로 남긴 stopHue 옛 줄이 계약을 채운다")
        // 기준선: 같은 이름을 살아 있는 줄로 한 번 더 선언하면(옛 줄은 그대로) 걸린다.
        #expect(!Self.scriptDeclares(script + "\nlet chromaSlope = 3.6\n", slope), "기준선: 같은 이름의 두 번째 선언을 못 본다")
        // 셰이더 글이 같은 상수에서 나온다.
        let shader = RainbowAingFinish.fragmentShader
        #expect(shader.contains("{ " + art.stopLightness.map { String(format: "%.6f", $0) }.joined(separator: ", ") + " }"))
        #expect(shader.contains(String(format: "%.6f", art.lightnessReference)) && shader.contains(String(format: "%.6f", art.bodyTop)))
        #expect(shader.contains("rbHueDeg >= 215.0 && rbHueDeg <= 300.0 && rbSat > 0.05 && rbSat < 0.75 && rbLuma > 0.10"),
                "셰이더의 피부 판정이 GoldAingFinish.isGoldSkin 과 다르다")
        // 셰이더는 시간에 기대지 않는다(정적 — 흐르는 애니메이션 없음).
        #expect(!shader.contains("scn_frame") && !shader.contains("u_time"))
    }

    // MARK: - 초상

    /// 몸(알파 ≥ 250) 피부 픽셀의 OKLab 색상을 위 · 아래 띠로 나눠 잰다. 무지개: 위는 빨강–주황(25–58°), 아래는 남–보라(270–305°).
    static func bandHues(_ image: CGImage) -> (top: Double, bottom: Double, n: Int) {
        let w = image.width, h = image.height, px = V0354GoldAingArtTests.rgba(image)
        var y0 = h, y1 = -1
        for y in 0..<h { for x in 0..<w where px[(y * w + x) * 4 + 3] >= 250 { y0 = min(y0, y); y1 = max(y1, y) } }
        var top = [Double](), bottom = [Double]()
        for y in 0..<h { for x in 0..<w {
            let o = (y * w + x) * 4
            guard px[o + 3] >= 250 else { continue }
            let c = Self.oklch(px[o], px[o + 1], px[o + 2])
            guard c.C > 0.04, c.L > 0.45 else { continue }   // 눈 · 입 같은 어두운 장식은 뺀다
            let f = Double(y - y0) / Double(max(1, y1 - y0))
            if f < 0.12 { top.append(c.h) } else if f > 0.9 { bottom.append(c.h) }
        } }
        return (meanHue(top), meanHue(bottom), top.count + bottom.count)
    }

    @Test("초상: 정수리는 빨강–주황 · 바닥은 남–보라(높이로 무지개) — 라벤더 아잉 초상은 같은 잣대에서 위아래가 같은 보라")
    func portraitsAreRainbowTopToBottom() throws {
        for e in Self.expressions {
            let rainbow = Self.bandHues(try Self.image("aing_rainbow-\(e)"))
            print(String(format: "[v0359-art] 초상 %@: 위 색상 %.0f° · 아래 %.0f° (n %d)", e, rainbow.top, rainbow.bottom, rainbow.n))
            #expect(Self.hueDistance(rainbow.top, 40) < 30, "\(e) 정수리 색상 \(rainbow.top)° — 빨강·주황이 아니다")
            #expect(Self.hueDistance(rainbow.bottom, 285) < 35, "\(e) 바닥 색상 \(rainbow.bottom)° — 남·보라가 아니다")
            let lavender = Self.bandHues(try Self.image("aing-\(e)"))
            #expect(Self.hueDistance(lavender.top, 40) > 60, "기준선이 안 갈린다: 라벤더 정수리 \(lavender.top)°")
        }
    }

    @Test("초상: 눈 · 입(어두운 장식)은 원래 그대로 — 같은 2D 원본 · 같은 0.88배인 황금 초상과 어두운 픽셀 수가 같다")
    func portraitsKeepTheFace() throws {
        func dark(_ image: CGImage) -> Int {
            let px = V0354GoldAingArtTests.rgba(image)
            var count = 0
            for o in stride(from: 0, to: px.count, by: 4) where px[o + 3] >= 250 {
                let sum: Int = Int(px[o]) + Int(px[o + 1]) + Int(px[o + 2])
                if sum < 150 { count += 1 }
            }
            return count
        }
        for e in Self.expressions {
            let rainbow = dark(try Self.image("aing_rainbow-\(e)")), gold = dark(try Self.image("aing_gold-\(e)"))
            let lavender = dark(try Self.image("aing-\(e)"))
            #expect(gold > 50 && abs(rainbow - gold) * 10 <= gold, "\(e): 무지개 \(rainbow) vs 황금 \(gold) — 얼굴이 바뀌었다")
            // 기준선: 줄이지 않은 라벤더 원본은 같은 잣대에서 눈에 띄게 많다(0.88² ≈ 0.77).
            #expect(Double(lavender) > Double(gold) * 1.15, "기준선이 안 갈린다(라벤더 \(lavender) · 황금 \(gold))")
        }
    }

    /// 후광 둘레 색: 몸 중심에서 12 · 3 · 6 · 9시 방향, 몸 밖 반투명 띠(알파 0.15–0.85)의 원형 평균 색상.
    static func haloClockHues(_ image: CGImage) -> [Double] {
        let w = image.width, h = image.height, px = V0354GoldAingArtTests.rgba(image)
        var cx = 0.0, cy = 0.0, cw = 0.0
        for y in 0..<h { for x in 0..<w where px[(y * w + x) * 4 + 3] >= 250 { cx += Double(x); cy += Double(y); cw += 1 } }
        if cw == 0 { cx = Double(w) / 2; cy = Double(h) / 2 } else { cx /= cw; cy /= cw }
        return [0.0, 90, 180, 270].map { clock in
            var hues = [Double]()
            for y in 0..<h { for x in 0..<w {
                let o = (y * w + x) * 4
                let a = Double(px[o + 3]) / 255
                guard a > 0.15, a < 0.85 else { continue }
                let dx = Double(x) - cx, dy = Double(y) - cy
                var theta = atan2(dx, -dy) * 180 / .pi
                if theta < 0 { theta += 360 }
                guard Self.hueDistance(theta, clock) < 12 else { continue }
                let un = { (v: UInt8) in UInt8(min(255, (Double(v) / a).rounded())) }
                let c = Self.oklch(un(px[o]), un(px[o + 1]), un(px[o + 2]))
                if c.C > 0.015 { hues.append(c.h) }
            } }
            return hues.isEmpty ? -1 : Self.meanHue(hues)
        }
    }

    @Test("후광 둘레 색: 12시 빨강 → 3시 노랑 → 6시 파랑 → 9시 보라(시계 방향 무지개) — 정면 · 초상 둘 다, 황금 후광은 같은 잣대에서 걸린다")
    func haloCyclesAroundTheBody() throws {
        let targets = [25.0, 100, 240, 305]
        for name in [RainbowAingArt.haloResourceName, "aing_rainbow-neutral"] {
            let hues = Self.haloClockHues(try Self.image(name))
            print("[v0359-art] 후광 \(name) 12·3·6·9시 색상 \(hues.map { Int($0) })")
            for (hue, target) in zip(hues, targets) {
                #expect(hue >= 0 && Self.hueDistance(hue, target) < 35, "\(name): 색상 \(hue)° — 기대 \(target)° 근처")
            }
        }
        let gold = Self.haloClockHues(try Self.image("aing_gold-halo"))
        #expect(zip(gold, targets).filter { $0.0 >= 0 && Self.hueDistance($0.0, $0.1) < 35 }.count <= 1,
                "기준선이 안 갈린다: 황금 후광 \(gold.map { Int($0) })")
    }

    // MARK: - 스크립트 결정성

    /// 같은 입력이면 같은 바이트 — 스크립트를 임시 폴더로 한 번 더 돌려(--out) 저장소 41장과 맞댄다. 저장소는 안 건드린다.
    @Test("아트 스크립트는 결정적이다: 임시 폴더로 다시 구운 41장이 저장소 파일과 바이트까지 같다", .timeLimit(.minutes(5)))
    func scriptIsDeterministic() throws {
        let root = CheckCoreSourceLayout.repoRoot
        let out = FileManager.default.temporaryDirectory.appendingPathComponent("v0359-rainbow-art-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: out) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["swift", "-O", "scripts/make-rainbow-aing.swift", "--out", out.path]
        process.currentDirectoryURL = root
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let log = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        process.waitUntilExit()
        #expect(process.terminationStatus == 0, "스크립트 실패: \(log.suffix(800))")
        var names = RainbowAingArt.haloCellResourceNames + RainbowAingArt.portraitResourceNames + [RainbowAingArt.shadeResourceName]
        names = names.map { "Sources/check/Resources/\($0).png" }
            + RainbowAingArt.portraitResourceNames.map { "Sources/CheckMobileShared/Resources/Portraits/\($0).png" }
        #expect(names.count == 41)
        for name in names {
            let fresh = try Data(contentsOf: out.appendingPathComponent(name))
            let committed = try Data(contentsOf: root.appendingPathComponent(name))
            #expect(fresh == committed, "\(name): 다시 구운 그림이 저장소와 다르다")
        }
    }
}
