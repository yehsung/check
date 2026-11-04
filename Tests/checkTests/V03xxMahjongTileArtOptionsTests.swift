import AppKit
import CryptoKit
import Foundation
import SwiftUI
import Testing
@testable import check
@testable import CheckCore

// 아잉 마작 패 그림 **선택지**(SPEC §5.9 · §9.1 '렌더로 나중에 물을 것' — 갈래 M).
// 선택지마다 패가 그려지는가(잉크 감지) · 1차 시안(`.firstDraft`)이 U 그림과 같은 바이트인가 · 판 화면이 `chosen` 을 따르는가 ·
// 펠트가 중간 톤 규칙을 지키는가 · 팔레트 JSON 과 뒷면 짝의 우선순위를 잰다. 그림은 `MahjongTileArt.rasterize` 로 직접 굽는다.
//
// 대표에게 보일 비교 시트(PNG)는 **`MAHJONG_MOCKS_DIR` 를 줄 때만** 쓴다(기본 게이트에서 파일 쓰기 0):
//   MAHJONG_MOCKS_DIR=<폴더> swift test --filter 'V03xxMahjongTileArtOptionsTests'
// 시트 칸 글자는 각 축 enum 의 순서 그대로(A = 첫 case = 1차 시안 = 지금 그대로).

@MainActor
@Suite("아잉 마작 패 그림 선택지 — 그려짐 · 1차 시안 바이트 · 기본값 배선 · 펠트 중간 톤 · 시트")
struct V03xxMahjongTileArtOptionsTests {
    // MARK: ① 뒷면

    @Test("뒷면 짝 넷이 모두 제 색으로 그려진다(테두리 · 위쪽 몸 색) · 서로 다른 그림")
    func everyBackSchemeDrawsItsColors() throws {
        // 없으면: 그리는 쪽이 선택지를 무시하고 늘 남색 뒷면을 그려도(시트 B·C·D 가 A 와 같은 그림) 초록이다.
        var seen: Set<Data> = []
        for scheme in MahjongTileBackScheme.allCases {
            let style = mmStyle(back: scheme)
            let image = try #require(MahjongTileArt.rasterize(MahjongTileArt.image(.back, size: .hand, style: style), scale: 2))
            let pixels = mmPixels(image)
            let rim = try #require(MahjongTilePalette.rgb(hex: scheme.colors.rim))
            let rimHits = pixels.count { r, g, b in mmNear((r, g, b), rim, 10) }
            #expect(rimHits > 150, "\(scheme): 테두리 색 픽셀 \(rimHits)")
            let top = try #require(MahjongTilePalette.rgb(hex: scheme.colors.top))
            // 위쪽 가운데(테두리 안 · 고리 위) — 그라데이션 13% 지점이라 위 색에 가깝다.
            let sample = pixels.rgb(46, 16)
            #expect(mmNear(sample, top, 22), "\(scheme): 위쪽 몸 색 \(sample)")
            seen.insert(Data(pixels.bytes))
            // 뒷면 테두리는 펠트 위에서 잉크로 보인다(감지기 기준 — 중간 톤이 아니다).
            #expect(!MahjongFeltScheme.isMidTone(MahjongArtRGB(rim.r, rim.g, rim.b)))
        }
        #expect(seen.count == MahjongTileBackScheme.allCases.count, "뒷면 짝 그림이 겹친다")
    }

    // MARK: ② 1삭

    @Test("1삭 세 그림이 제 모양으로 그려진다(새싹 빨간 점 · 아잉이 라벤더와 눈 · 대나무 초록만) · 작은 크기에서도 잉크")
    func everyOneSouMotifDrawsItsShape() throws {
        // 없으면: 1삭 선택지를 무시하고 늘 새싹을 그려도(시트 B·C 가 A 와 같은 그림) 초록이다.
        var seenHand: Set<Data> = []
        var seenSmall: Set<Data> = []
        for motif in MahjongOneSouMotif.allCases {
            let style = mmStyle(oneSou: motif)
            let hand = mmPixels(try #require(MahjongTileArt.rasterize(
                MahjongTileArt.image(mmOneSou, size: .hand, cornerLabels: false, style: style), scale: 2)))
            let red = hand.count { r, g, b in r > 200 && g < 90 && b < 110 }
            let lavender = hand.count { r, g, b in b > 220 && r >= 140 && b - r > 36 && b - g > 36 }
            let eyes = hand.count { r, g, b in max(r, g, b) < 80 }
            let green = hand.count { r, g, b in g > r + 60 && g > b + 15 }
            switch motif {
            case .sprout:
                #expect(red > 40 && green > 200 && lavender < 20, "새싹: 빨강 \(red) · 초록 \(green) · 라벤더 \(lavender)")
            case .aingFace:
                #expect(lavender > 1_200 && eyes > 60 && green == 0, "아잉이: 라벤더 \(lavender) · 눈 \(eyes) · 초록 \(green)")
            case .bambooNode:
                #expect(green > 600 && red == 0 && lavender < 20, "대나무: 초록 \(green) · 빨강 \(red) · 라벤더 \(lavender)")
            }
            seenHand.insert(Data(hand.bytes))
            let small = mmPixels(try #require(MahjongTileArt.rasterize(
                MahjongTileArt.image(mmOneSou, size: .smallMeld, style: style), scale: 2)))
            let ink = small.count { r, g, b in max(r, g, b) - min(r, g, b) >= 60 || max(r, g, b) < 120 }
            #expect(ink > 150, "\(motif) 24×32 잉크 \(ink)")
            seenSmall.insert(Data(small.bytes))
        }
        #expect(seenHand.count == 3 && seenSmall.count == 3, "1삭 그림이 겹친다(손 \(seenHand.count) · 작은 울음 \(seenSmall.count))")
    }

    // MARK: ③ 보조 글자

    @Test("보조 글자 셋: 지금 = 수패·자패 모두 · 숫자만 = 자패 빠짐 · 없음 = 보조 끔과 같은 그림")
    func cornerLabelStylesFilterTheCorner() throws {
        // 없으면: '숫자만'이 자패 글자(동·백)를 그대로 그리거나 '없음'이 글자를 남겨도 초록이다.
        for face in MahjongTileFace.all {
            let layout = MahjongTileArtModel.layout(face: face)
            let isHonor = (face.kind ?? 0) >= 27
            #expect(MahjongCornerLabelStyle.numbersAndHonors.label(layout, face: face) == layout.cornerLabel)
            #expect(MahjongCornerLabelStyle.numbersOnly.label(layout, face: face) == (isHonor ? nil : layout.cornerLabel))
            #expect(MahjongCornerLabelStyle.hidden.label(layout, face: face) == nil)
        }
        for face in [MahjongTileFace.tile(kind: 0, red: false), .tile(kind: 26, red: false), .tile(kind: 27, red: false),
                     .tile(kind: 31, red: false)] {
            let isHonor = (face.kind ?? 0) >= 27
            let off = mmPixels(try #require(MahjongTileArt.rasterize(
                MahjongTileArt.image(face, size: .hand, cornerLabels: false), scale: 2)))
            for corner in MahjongCornerLabelStyle.allCases {
                let on = mmPixels(try #require(MahjongTileArt.rasterize(
                    MahjongTileArt.image(face, size: .hand, cornerLabels: true, style: mmStyle(corner: corner)), scale: 2)))
                let changed = mmDiffCount(on, off)
                let expectLabel = corner == .numbersAndHonors || (corner == .numbersOnly && !isHonor)
                if expectLabel {
                    #expect(changed > 30, "\(face) \(corner): 모서리 글자가 안 그려졌다(바뀐 픽셀 \(changed))")
                } else {
                    #expect(on.bytes == off.bytes, "\(face) \(corner): 글자가 없어야 하는데 보조 끔과 다르다(\(changed) 픽셀)")
                }
            }
        }
    }

    // MARK: 1차 시안 = U 그림

    @Test("1차 시안(.firstDraft)의 글자 없는 22면 × 손·강 크기 그림이 U 그림과 같은 바이트(SHA256)")
    func firstDraftDrawsTheSameBytesAsU() throws {
        // 없으면: 선택지 손잡이를 달다가 1차 시안(시트 A 칸 = '지금 그대로')의 그림이 몰래 바뀌어도 초록이다.
        // 기준값은 고치기 전 U 그림(mj/u 87ef2ade)에서 뜬 값 — 고친 뒤 9,576 열쇠 전부 같은 바이트였다(MJ/reports/M.md).
        // 일부러 1차 시안 그림을 고쳤다면 이 값을 새로 뜬다. 글자 있는 면은 OS 글꼴 갱신에 흔들려 넣지 않았다.
        var hasher = SHA256()
        for size in [MahjongTileSize.hand, .river] {
            for face in mmShapeFaces {
                let image = try #require(MahjongTileArt.rasterize(
                    MahjongTileArt.image(face, size: size, cornerLabels: false, style: .firstDraft), scale: 2))
                hasher.update(data: Data(mmPixels(image).bytes))
            }
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        #expect(digest == mmFirstDraftDigest, "1차 시안 그림이 U 그림과 다르다: \(digest)")
        #expect(MahjongTilePalette.code(back: .navyPink) == MahjongTilePalette(
            bodyTop: "#FBF9FF", bodyBottom: "#ECE7F7", bevel: "#C9C0E3", backTop: "#2A3270", backBottom: "#1B2150",
            backRim: "#FF6FA5", ink: "#1F2A5A"), "A 칸 뒷면 짝이 U 코드 팔레트와 다르다")
    }

    // MARK: 기본값 배선

    @Test("판 화면은 chosen 을 그린다 — 환경 기본값 · 스타일 안 준 그림 · 코드 팔레트 · 맥 판 펠트 색(MahjongFeltStyle)")
    func panelsDrawTheChosenStyle() throws {
        // 없으면: 대표가 고른 값(chosen 한 줄)을 바꿔도 판 화면이 다른 값을 그려(환경 기본값이 firstDraft 에 묶이는 등) 초록이다.
        #expect(EnvironmentValues().mahjongTileArtStyle == MahjongTileArtStyle.chosen)
        #expect(MahjongTilePalette.standard == MahjongTilePalette.code(back: MahjongTileArtStyle.chosen.backScheme))
        for face in [mmOneSou, .back, .tile(kind: 27, red: false)] {
            let plain = try #require(MahjongTileArt.rasterize(MahjongTileArt.image(face, size: .hand), scale: 2))
            let chosen = try #require(MahjongTileArt.rasterize(MahjongTileArt.image(face, size: .hand, style: .chosen), scale: 2))
            #expect(mmPixels(plain).bytes == mmPixels(chosen).bytes, "\(face): 스타일 안 준 그림이 chosen 과 다르다")
        }
        // 펠트는 맥 판 화면이 `MahjongFeltStyle` 로 따로 쥔다 — 고른 펠트와 어긋나면 여기서 빨갛다
        // (그때는 CK/MahjongPanelTable.swift 의 MahjongFeltStyle 다섯 색을 `MahjongTileArtStyle.chosen.feltScheme` 에서 읽게 한다).
        let felt = MahjongTileArtStyle.chosen.feltScheme
        let pairs: [(Color, MahjongArtRGB, String)] = [
            (MahjongFeltStyle.felt, felt.felt, "felt"), (MahjongFeltStyle.rim, felt.rim, "rim"),
            (MahjongFeltStyle.board, felt.board, "board"), (MahjongFeltStyle.boardRim, felt.boardRim, "boardRim"),
            (MahjongFeltStyle.glyph, felt.glyph, "glyph"),
        ]
        for (color, rgb, name) in pairs {
            let ns = try #require(NSColor(color).usingColorSpace(.sRGB))
            let delta = max(abs(ns.redComponent - rgb.r), abs(ns.greenComponent - rgb.g), abs(ns.blueComponent - rgb.b))
            #expect(delta < 0.002, "판 펠트 \(name) 이 고른 펠트(\(felt))와 다르다 — Δ\(delta)")
        }
    }

    // MARK: 펠트 중간 톤

    @Test("펠트 넷의 칸(펠트 · 테두리 · 가운데 판 · 판 테두리)이 모두 중간 톤 · 판단 함수의 기준선")
    func feltSchemesStayMidTone() {
        // 없으면: 밝거나 채도 높은 펠트 선택지가 렌더 감지기의 '잉크'로 세져 '패가 섰다'가 늘 참이 되어도 초록이다.
        for scheme in MahjongFeltScheme.allCases {
            for (index, color) in scheme.midTones.enumerated() {
                #expect(MahjongFeltScheme.isMidTone(color), "\(scheme) 칸 \(index) \(color.channels)")
            }
            #expect(!MahjongFeltScheme.isMidTone(scheme.glyph), "판 글자는 밝은 잉크여야 한다")
        }
        // 기준선 — 판단 함수가 규칙 밖을 거짓으로 가른다.
        #expect(!MahjongFeltScheme.isMidTone(MahjongArtRGB(0.95, 0.95, 0.95)))   // 최대 > 234
        #expect(!MahjongFeltScheme.isMidTone(MahjongArtRGB(0.10, 0.12, 0.20)))   // 최소 < 56
        #expect(!MahjongFeltScheme.isMidTone(MahjongArtRGB(0.25, 0.30, 0.45)))   // 채널 폭 ≥ 40(유채 잉크)
        #expect(!MahjongFeltScheme.isMidTone(MahjongArtRGB(0.60, 0.62, 0.64)))   // 최대 ≥ 150(밝은 잉크)
        #expect(MahjongFeltScheme.isMidTone(MahjongArtRGB(0.24, 0.39, 0.36)))
    }

    // MARK: 팔레트 JSON 과 뒷면 짝

    @Test("팔레트: JSON 이 없거나 틀리면 그 스타일의 뒷면 짝 · 바른 JSON 은 일곱 색 모두 이긴다")
    func paletteJSONStandsOverTheBackPair() throws {
        // 없으면: 뒷면 선택지가 받은 팔레트 JSON 을 덮거나(Storage 로 다듬는 길이 막힘) JSON 이 틀릴 때 남색으로 굳어도 초록이다.
        #expect(MahjongTilePalette.delivered(from: nil) == nil)
        #expect(MahjongTilePalette.delivered(from: Data("not json".utf8)) == nil)
        var broken = MahjongTilePalette.standard
        broken.backRim = "#XYZ"
        #expect(MahjongTilePalette.delivered(from: try JSONEncoder().encode(broken)) == nil)
        for scheme in MahjongTileBackScheme.allCases {
            let code = MahjongTilePalette.effective(back: scheme, delivered: nil)
            #expect(code.backTop == scheme.colors.top && code.backBottom == scheme.colors.bottom && code.backRim == scheme.colors.rim)
            #expect(code.bodyTop == MahjongTilePalette.standard.bodyTop && code.ink == MahjongTilePalette.standard.ink)
        }
        var custom = MahjongTilePalette.standard
        custom.backRim = "#00FF00"
        let delivered = try #require(MahjongTilePalette.delivered(from: try JSONEncoder().encode(custom)))
        #expect(MahjongTilePalette.effective(back: .raspberryBlush, delivered: delivered) == custom)
        #expect(MahjongTileArt.deliveredPalette == nil, "시험 프로세스에 받은 팔레트가 남아 있다")
        #expect(MahjongTileArt.palette(for: mmStyle(back: .violetPink)).backRim == MahjongTileBackScheme.violetPink.colors.rim)
    }

    // MARK: 시트(대표에게 그림으로 묻기) — MAHJONG_MOCKS_DIR 줄 때만 파일을 쓴다

    @Test("선택지 비교 시트 · 판 전체 PNG(MAHJONG_MOCKS_DIR 줄 때만)")
    func writeMockSheets() throws {
        guard let path = ProcessInfo.processInfo.environment["MAHJONG_MOCKS_DIR"], !path.isEmpty else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let base = MahjongTileArtStyle.firstDraft

        let backColumns = MahjongTileBackScheme.allCases.enumerated().map { index, scheme in
            var style = base
            style.backScheme = scheme
            style.feltScheme = scheme.pairedFelt
            return MMColumn(letter: mmLetters[index], name: mmBackNames[index].name, note: mmBackNames[index].note, style: style,
                            zoom: [.init(.back, .hand, 1.6), .init(.back, .river, 1.6), .init(.tile(kind: 0, red: false), .hand, 1.6)])
        }
        try mmWrite(MMSheet(title: "① 패 뒷면과 판 색", subtitle: "상대 손패 · 닫힌 도라에 보이는 패 뒷면과 탁자 색을 한 짝으로 골라 주세요.",
                            columns: backColumns), name: "q1-back-felt.png", in: directory)

        let souColumns = MahjongOneSouMotif.allCases.enumerated().map { index, motif in
            var style = base
            style.oneSouMotif = motif
            return MMColumn(letter: mmLetters[index], name: mmSouNames[index].name, note: mmSouNames[index].note, style: style,
                            zoom: [.init(mmOneSou, .hand, 2.4), .init(mmOneSou, .hand, 1), .init(mmOneSou, .meld, 1),
                                   .init(mmOneSou, .river, 1), .init(mmOneSou, .smallMeld, 1)])
        }
        try mmWrite(MMSheet(title: "② 1삭 그림", subtitle: "대나무 1 패에만 들어가는 그림이에요. 크게 본 것 옆에 실제 크기(손 · 울음 · 강 · 상대 울음)를 같이 두었어요.",
                            columns: souColumns), name: "q2-one-sou.png", in: directory)

        let cornerFaces: [MahjongTileFace] = [.tile(kind: 0, red: false), .tile(kind: 13, red: true), .tile(kind: 24, red: false),
                                              .tile(kind: 27, red: false), .tile(kind: 31, red: false), .tile(kind: 33, red: false)]
        let cornerColumns = MahjongCornerLabelStyle.allCases.enumerated().map { index, corner in
            var style = base
            style.cornerLabel = corner
            return MMColumn(letter: mmLetters[index], name: mmCornerNames[index].name, note: mmCornerNames[index].note, style: style,
                            zoom: cornerFaces.map { .init($0, .hand, 1.4) })
        }
        try mmWrite(MMSheet(title: "③ 패 모서리 숫자", subtitle: "패 왼쪽 위의 작은 글자예요. 한자를 몰라도 무슨 패인지 읽히게 돕습니다.",
                            columns: cornerColumns), name: "q3-corner-label.png", in: directory)

        let store = try mmTableStore(mmActive())
        try mmWrite(MMBoard(title: "④ 판 화면 전체 — 지금 기본값(①A · ②A · ③A)", store: store, style: .chosen),
                    name: "q4-board-default.png", in: directory)
        var noCorner = MahjongTileArtStyle.chosen
        noCorner.cornerLabel = .hidden
        try mmWrite(MMBoard(title: "⑤ 판 화면 전체 — 모서리 숫자 없음(③의 C)", store: store, style: noCorner),
                    name: "q5-board-no-corner-label.png", in: directory)
    }
}

// MARK: - 선택지 이름(시트 칸 — 일상어)

private let mmLetters = ["A", "B", "C", "D"]
private let mmBackNames: [(name: String, note: String)] = [
    ("지금 그대로", "남색 뒷면 · 청록 판"), ("보라 뒷면", "보라 뒷면 · 남색 판"),
    ("분홍 뒷면", "분홍 뒷면 · 자두색 판"), ("라벤더 뒷면", "라벤더 뒷면 · 먹색 판"),
]
private let mmSouNames: [(name: String, note: String)] = [
    ("지금 그대로", "새싹"), ("아잉이 얼굴", "둥근 아잉이 얼굴"), ("대나무 한 마디", "굵은 대나무 하나 — 가장 단순"),
]
private let mmCornerNames: [(name: String, note: String)] = [
    ("지금 그대로", "숫자 + 동·남·서·북·백·발·중"), ("숫자만", "숫자 패만 1~9 · 글자 패는 없음"), ("없음", "모서리 글자 없음"),
]

// MARK: - 값

private let mmOneSou = MahjongTileFace.tile(kind: 18, red: false)

/// 글자 없는 면(통 1~9 · 삭 1~9 · 白 · 뒷면 · 적5통 · 적5삭) — 글꼴 갱신에 흔들리지 않는 1차 시안 기준.
private let mmShapeFaces: [MahjongTileFace] = (9..<27).map { MahjongTileFace.tile(kind: $0, red: false) }
    + [.tile(kind: 31, red: false), .back, .tile(kind: 13, red: true), .tile(kind: 22, red: true)]

/// 고치기 전 U 그림에서 뜬 값(위 22면 × 손·강, 배율 2, RGBA8 sRGB 프리멀티플라이드).
private let mmFirstDraftDigest = "3769640aa1dc882ec907304e459f6947a13328ee1477a6e47c564a23363281b1"

private func mmStyle(back: MahjongTileBackScheme? = nil, oneSou: MahjongOneSouMotif? = nil,
                     corner: MahjongCornerLabelStyle? = nil) -> MahjongTileArtStyle {
    var style = MahjongTileArtStyle.firstDraft
    if let back { style.backScheme = back }
    if let oneSou { style.oneSouMotif = oneSou }
    if let corner { style.cornerLabel = corner }
    return style
}

// MARK: - 픽셀 도우미(이 파일 전용)

private struct MMPixels {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    /// (x, y) px — 위가 0.
    func rgb(_ x: Int, _ y: Int) -> (Int, Int, Int) {
        let o = (y * width + x) * 4
        return (Int(bytes[o]), Int(bytes[o + 1]), Int(bytes[o + 2]))
    }

    /// 불투명(알파 > 200) 픽셀 가운데 조건에 맞는 수.
    func count(where predicate: (Int, Int, Int) -> Bool) -> Int {
        var hits = 0
        for i in stride(from: 0, to: bytes.count, by: 4) where bytes[i + 3] > 200 {
            if predicate(Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2])) { hits += 1 }
        }
        return hits
    }
}

/// CGImage → RGBA8(sRGB, 위가 0).
private func mmPixels(_ image: CGImage) -> MMPixels {
    let width = image.width, height = image.height
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    bytes.withUnsafeMutableBytes { buffer in
        let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: width * 4, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    }
    return MMPixels(width: width, height: height, bytes: bytes)
}

/// 채널 차가 24 를 넘는 픽셀 수.
private func mmDiffCount(_ lhs: MMPixels, _ rhs: MMPixels) -> Int {
    guard lhs.bytes.count == rhs.bytes.count else { return Int.max }
    var hits = 0
    lhs.bytes.withUnsafeBufferPointer { a in
        rhs.bytes.withUnsafeBufferPointer { b in
            for i in stride(from: 0, to: a.count, by: 4) {
                let d0 = abs(Int(a[i]) - Int(b[i])), d1 = abs(Int(a[i + 1]) - Int(b[i + 1]))
                let d2 = abs(Int(a[i + 2]) - Int(b[i + 2])), d3 = abs(Int(a[i + 3]) - Int(b[i + 3]))
                if max(max(d0, d1), max(d2, d3)) > 24 { hits += 1 }
            }
        }
    }
    return hits
}

private func mmNear(_ pixel: (Int, Int, Int), _ target: (r: Double, g: Double, b: Double), _ tolerance: Int) -> Bool {
    abs(pixel.0 - Int((target.r * 255).rounded())) <= tolerance && abs(pixel.1 - Int((target.g * 255).rounded())) <= tolerance
        && abs(pixel.2 - Int((target.b * 255).rounded())) <= tolerance
}

// MARK: - 시트 그림

private struct MMZoom: Hashable {
    let face: MahjongTileFace
    let size: MahjongTileSize
    let zoom: CGFloat

    init(_ face: MahjongTileFace, _ size: MahjongTileSize, _ zoom: CGFloat) {
        self.face = face
        self.size = size
        self.zoom = zoom
    }
}

private struct MMColumn: Identifiable {
    let letter: String
    let name: String
    let note: String
    let style: MahjongTileArtStyle
    let zoom: [MMZoom]
    var id: String { letter }
}

private let mmSheetWidth: CGFloat = 1600
private let mmSheetBackground = Color(red: 0.10, green: 0.11, blue: 0.15)
private let mmColumnFill = Color(red: 0.17, green: 0.18, blue: 0.24)
private let mmLetterColor = Color(red: 1.0, green: 0.55, blue: 0.78)

/// 질문 하나 = 한 장. 가로로 A·B·C(·D) 칸.
private struct MMSheet: View {
    let title: String
    let subtitle: String
    let columns: [MMColumn]

    var body: some View {
        let gutter: CGFloat = 16, padding: CGFloat = 24
        let columnWidth = (mmSheetWidth - padding * 2 - gutter * CGFloat(columns.count - 1)) / CGFloat(columns.count)
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 30, weight: .heavy)).foregroundStyle(Color.white)
                Text(subtitle).font(.system(size: 17, weight: .medium)).foregroundStyle(Color.white.opacity(0.72))
            }
            HStack(alignment: .top, spacing: gutter) {
                ForEach(columns) { column in
                    MMColumnView(column: column, width: columnWidth)
                }
            }
        }
        .padding(padding)
        .frame(width: mmSheetWidth, alignment: .topLeading)
        .background(mmSheetBackground)
    }
}

private struct MMColumnView: View {
    let column: MMColumn
    let width: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                Text(column.letter).font(.system(size: 60, weight: .black)).foregroundStyle(mmLetterColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text(column.name).font(.system(size: 24, weight: .bold)).foregroundStyle(Color.white)
                    Text(column.note).font(.system(size: 15, weight: .medium)).foregroundStyle(Color.white.opacity(0.7))
                }
            }
            MMBoardSlice(style: column.style, zoom: column.zoom, width: width - 28)
        }
        .padding(14)
        .frame(width: width, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(mmColumnFill))
        .environment(\.mahjongTileArtStyle, column.style)
    }
}

/// 판 일부 — 펠트 위에 크게 본 패 · 상대 뒷면 띠 · 도라 판 · 강 두 줄 · 손패 14장(7장씩 두 줄).
private struct MMBoardSlice: View {
    let style: MahjongTileArtStyle
    let zoom: [MMZoom]
    let width: CGFloat

    var body: some View {
        let felt = style.feltScheme
        VStack(spacing: 14) {
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(zoom, id: \.self) { item in MMZoomTile(item: item, style: style) }
            }
            MahjongTileStrip(tiles: (0..<13).map { i in
                MahjongStripTile(face: .back, size: .back, rotation: 2, origin: CGPoint(x: CGFloat(i) * 20, y: 0))
            }, size: CGSize(width: 13 * 20 - 2, height: 24), cornerLabels: false)
            VStack(spacing: 6) {
                Text("동 3국 · 남은 패 48").font(.system(size: 13, weight: .semibold)).foregroundStyle(felt.glyph.color)
                MahjongTileStrip(tiles: [MahjongStripTile(face: .tile(kind: 25, red: false), size: .river, origin: .zero)]
                    + (1..<5).map { i in MahjongStripTile(face: .back, size: .river, origin: CGPoint(x: CGFloat(i) * 32, y: 0)) },
                    size: CGSize(width: 5 * 32 - 2, height: 40), cornerLabels: false)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 12).fill(felt.board.color))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(felt.boardRim.color, lineWidth: 2))
            MahjongTileStrip(tiles: mmRiver.enumerated().map { index, item in
                MahjongStripTile(face: item.face, size: .river, state: item.state,
                                 origin: CGPoint(x: CGFloat(index % 6) * 31, y: CGFloat(index / 6) * 41))
            }, size: CGSize(width: 6 * 31 - 1, height: 81))
            VStack(spacing: 6) {
                ForEach(0..<2, id: \.self) { row in
                    HStack(spacing: 3) {
                        ForEach(0..<7, id: \.self) { index in
                            MahjongTileView(face: mmHand[row * 7 + index], size: .hand)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 16)
        .frame(width: width)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(felt.felt.color))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(felt.rim.color, lineWidth: 3))
    }
}

/// 크게 본 패 — 벡터 그림을 배율 × 확대로 다시 굽는다(늘려서 흐려지지 않게).
private struct MMZoomTile: View {
    let item: MMZoom
    let style: MahjongTileArtStyle

    var body: some View {
        let image = MahjongTileArt.image(item.face, size: item.size, style: style)
        let scale: CGFloat = 2
        if let bitmap = MahjongTileArt.rasterize(image, scale: scale * item.zoom) {
            Image(decorative: bitmap, scale: scale).resizable().interpolation(.high)
                .frame(width: image.size.width * item.zoom, height: image.size.height * item.zoom)
        }
    }
}

/// 손패 14장(만 · 통 · 삭 · 글자 패 고루 — 적5만 · 1삭 포함).
private let mmHand: [MahjongTileFace] = [0, 4, 8, 11, 13, 16, 18, 21, 24, 26, 27, 31, 32, 33].map { kind in
    MahjongTileFace.tile(kind: kind, red: kind == 4)
}

/// 강 11장(쯔모기리 한 장 · 방금 버린 패 강조 · 1삭 포함).
private let mmRiver: [(face: MahjongTileFace, state: MahjongTileState)] = [
    (.tile(kind: 30, red: false), .normal), (.tile(kind: 18, red: false), .normal), (.tile(kind: 1, red: false), .normal),
    (.tile(kind: 17, red: false), .tsumogiri), (.tile(kind: 28, red: false), .normal), (.tile(kind: 23, red: false), .normal),
    (.tile(kind: 9, red: false), .normal), (.tile(kind: 29, red: false), .normal), (.tile(kind: 2, red: false), .normal),
    (.tile(kind: 25, red: false), .normal), (.tile(kind: 10, red: false), .highlighted),
]

/// 판 전체(내 차례 장면) + 위 제목 띠.
private struct MMBoard: View {
    let title: String
    let store: MahjongStore
    let style: MahjongTileArtStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.system(size: 26, weight: .heavy)).foregroundStyle(Color.white)
                .padding(.horizontal, 24)
                .frame(width: 1240, height: 56, alignment: .leading)
                .background(mmSheetBackground)
            MahjongPanel(store: store, me: { ChessPlayerFace(name: "영식", avatarURL: nil, characterID: "shiba") },
                         clipsOverflowInsteadOfScroll: true)
                .environment(\.mahjongTileArtStyle, style)
        }
        .fixedSize()
    }
}

private enum MMRenderError: Error { case failed }

/// 배율 2 로 굳혀 구운 뒤 가로 1600px 이하로 줄여 PNG 로 쓴다(1MB 넘으면 실패).
@MainActor
private func mmWrite(_ view: some View, name: String, in directory: URL) throws {
    guard let bitmap = CheckRenderSettle.bitmap(view.fixedSize(), scale: 2), let source = bitmap.cgImage
    else { throw MMRenderError.failed }
    let width = min(source.width, Int(mmSheetWidth))
    let height = Int((Double(source.height) * Double(width) / Double(source.width)).rounded())
    guard let space = CGColorSpace(name: CGColorSpace.sRGB),
          let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
    else { throw MMRenderError.failed }
    context.interpolationQuality = .high
    context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
    guard let small = context.makeImage(),
          let png = NSBitmapImageRep(cgImage: small).representation(using: .png, properties: [:])
    else { throw MMRenderError.failed }
    try png.write(to: directory.appendingPathComponent(name))
    #expect(png.count <= 1_000_000, "\(name) \(png.count) 바이트 — 1MB 를 넘는다")
    #expect(width <= 1600, "\(name) 가로 \(width)px")
}

// MARK: - 판 전체 장면(내 차례 — V03xxMahjongPanelRenderTests 의 my-turn 손 픽스처와 같은 모양)

private let mmNowMs: Double = 1_793_660_908_000
private let mmNow = Date(timeIntervalSince1970: mmNowMs / 1_000)
private let mmMe = "aaaaaaaa-0000-4000-8000-000000000001"
private let mmPeople: [(id: String, name: String, character: String)] = [
    (mmMe, "영식", "shiba"), ("aaaaaaaa-0000-4000-8000-000000000002", "민수", "fox"),
    ("aaaaaaaa-0000-4000-8000-000000000003", "준호", "squirrel"), ("aaaaaaaa-0000-4000-8000-000000000004", "서연", "cat"),
]

private func mmID(_ kind: Int, _ copy: Int) -> Int { kind * 4 + copy }

private let mmMyHand = [mmID(0, 0), mmID(1, 0), mmID(2, 0), mmID(12, 0), mmID(13, 0), mmID(14, 0), mmID(24, 0), mmID(25, 0),
                        mmID(26, 0), mmID(27, 0), mmID(27, 1), mmID(28, 0), mmID(28, 1)]
private let mmDrawn = 16

private func mmDisc(_ kind: Int, _ copy: Int, tsumogiri: Bool = false, riichi: Bool = false, taken: Bool = false) -> [String: Any] {
    ["tile": mmID(kind, copy), "tsumogiri": tsumogiri, "riichi": riichi, "taken": taken]
}

private func mmSeats() -> [[String: Any]] {
    let discards: [[[String: Any]]] = [
        [mmDisc(33, 2), mmDisc(32, 2), mmDisc(0, 2, tsumogiri: true), mmDisc(8, 2), mmDisc(17, 2), mmDisc(30, 2), mmDisc(9, 2)],
        [mmDisc(29, 2), mmDisc(31, 3), mmDisc(18, 2), mmDisc(7, 2), mmDisc(16, 2), mmDisc(3, 2, riichi: true),
         mmDisc(20, 2, tsumogiri: true), mmDisc(11, 2)],
        (0..<13).map { mmDisc([5, 6, 15, 19, 21, 23, 10, 22, 30, 32, 33, 6, 15][$0], 3) },
        [mmDisc(29, 3), mmDisc(31, 2, taken: true), mmDisc(5, 2), mmDisc(19, 2), mmDisc(10, 3), mmDisc(21, 3)],
    ]
    return (0..<4).map { seat in
        var row: [String: Any] = [
            "seat_no": seat, "user": ["user_id": mmPeople[seat].id, "display_name": mmPeople[seat].name,
                                      "character": mmPeople[seat].character],
            "wind": ["E", "S", "W", "N"][seat], "is_dealer": seat == 0, "score": [25_000, 24_000, 26_000, 25_000][seat],
            "hand_count": seat == 1 ? 10 : 13, "melds": [] as [Any], "discards": discards[seat], "riichi": seat == 1,
            "away": false, "deleted": false,
        ]
        if seat == 1 {
            row["melds"] = [["type": "pon", "tiles": [mmID(31, 0), mmID(31, 1), mmID(31, 3)], "called": mmID(31, 3), "from_seat": 0]]
        }
        return row
    }
}

private func mmActive() -> [String: Any] {
    [
        "match": [
            "id": "11111111-2222-4333-8444-555555555555", "status": "active", "stake": 5, "format": "tonpuu", "is_public": false,
            "seq": 40, "phase": "turn", "hand_index": 2, "round": 0, "hand_no": 2, "honba": 1, "kyotaku": 1, "dealer_seat": 0,
            "extension": false, "wall_remaining": 48, "dora_indicators": [mmID(23, 1)], "kan_count": 0, "turn_seat": 0,
            "wake_at_ms": mmNowMs + 3_500, "wake_seat": 2, "backup_at_ms": mmNowMs + 8_500, "base_ms": 5_000,
            "bank_full_ms": 20_000, "grace_ms": 1_000, "started_ms": mmNowMs - 600_000,
            "host": ["id": mmMe, "display_name": "영식"],
        ] as [String: Any],
        "members": [] as [Any], "seats": mmSeats(), "my_seat": 0, "my_hand": mmMyHand, "my_drawn": mmDrawn,
        "my_waits": [] as [Any], "my_furiten": [] as [Any],
        "my_decision": [
            "kind": "turn", "seq": 40, "decision_seq": 12, "started_ms": mmNowMs - 1_500, "deadline_ms": mmNowMs + 23_500,
            "bank_ms": 20_000, "discard": mmMyHand + [mmDrawn], "riichi": [mmID(27, 0), mmID(27, 1)], "tsumo": false,
            "ankan": [] as [Any], "kakan": [] as [Any], "kyuushu": false,
        ] as [String: Any],
        "my_away": NSNull(),
        "events": [["seq": 39, "kind": "discard", "seat": 3, "at_ms": mmNowMs - 4_000, "tile": mmID(21, 3), "tsumogiri": false,
                    "riichi": false]],
        "last_hand": NSNull(), "reactions": [] as [Any], "ruby_balance": 115, "server_now_ms": mmNowMs,
    ]
}

@MainActor
private func mmTableStore(_ state: [String: Any]) throws -> MahjongStore {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    let payload = try decoder.decode(MahjongStatePayload.self, from: JSONSerialization.data(withJSONObject: state))
    let store = MahjongStore(clock: { mmNow })
    #expect(store.applyState(payload) == .applied)
    return store
}
