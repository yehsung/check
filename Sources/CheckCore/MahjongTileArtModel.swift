import CoreGraphics
import Foundation

// 아잉 마작 패 그림 — **순수 값**(맥·폰 공용, SPEC §5.9 · UX §2.6). 화면(맥 `MahjongTileArt`)은 이 값만 읽어 CoreGraphics 로 그린다.
//
// ── 무엇을 정하나 ──
//  · 면(`MahjongTileFace`): 34 종류 + 적5 셋 + 뒷면 = 38. 패 id → 면은 `MahjongTileFace(_:)` 한 곳(적5 = id 16·52·88 만, SPEC §1).
//  · 배치(`layout(face:)`): 통 원 · 삭 막대(정규 좌표 0~1, 얼굴 칸 기준) · 만 위 글자(一~九, 5 는 전통대로 伍) + 萬 ·
//    자패 글자(東南西北白發中) · 1삭 = 우리 모양(새싹) · 白 = 라벤더 둥근 테두리 · 적5 = 잉크 전부 빨강 + 오른쪽 위 금색 점.
//  · 크기 6종(`MahjongTileSize`) · 상태(`MahjongTileState`) · 방위 회전(`rotation(for:)` — `MahjongSeatCompass` 방위 그대로).
//  · 팔레트(`MahjongTilePalette`) — 코드 기본값 + 선택 JSON(`game-art/mahjong/tiles.json`, 색 7개). 틀린 JSON 은 코드 팔레트.
//
// 전통 배치(통의 원 개수·자리, 萬·東 글자)는 보편 관례라 따르고, 선·색·1삭·뒷면은 우리가 정한다(DEC:26).
// 다른 마작 서비스의 패 그림·서체·뒷면을 베끼지 않는다.

/// 패 한 면. 그림의 캐시 열쇠이자 시험이 "모두 다른 그림"을 재는 단위.
package nonisolated enum MahjongTileFace: Hashable, Sendable {
    /// 앞면 — 종류(0~33)와 적도라 여부.
    case tile(kind: Int, red: Bool)
    /// 뒷면(상대 손 띠 · 닫힌 도라 · 암깡 양 끝).
    case back

    /// 물리 패 id → 면. 적5 는 id 16·52·88 만(`MahjongTile.isRed`).
    package init(_ tile: MahjongTile) {
        self = .tile(kind: tile.kind, red: tile.isRed)
    }

    /// 34 종류 + 적5 셋(5만·5통·5삭) + 뒷면 = 38면.
    package static let all: [MahjongTileFace] = (0..<34).map { MahjongTileFace.tile(kind: $0, red: false) }
        + [4, 13, 22].map { MahjongTileFace.tile(kind: $0, red: true) } + [.back]

    package var kind: Int? {
        if case .tile(let kind, _) = self { return kind }
        return nil
    }

    package var isRed: Bool {
        if case .tile(_, let red) = self { return red }
        return false
    }

    /// 접근성 이름("5만, 적도라" · "동").
    package var spokenName: String {
        guard case .tile(let kind, let red) = self else { return "뒷면" }
        return MahjongTileArtModel.koreanName(kind: kind) + (red ? ", 적도라" : "")
    }
}

/// 크기 6종(UX §1.4). 24×32 이하는 단순화(보조 글자 없음 · 8·9삭 막대 사이 넓힘), 18×24 는 뒷면만.
package nonisolated enum MahjongTileSize: String, CaseIterable, Hashable, Sendable {
    /// 내 손패 46×62.
    case hand
    /// 결과 화면 손 40×54.
    case result
    /// 내 울음 34×46.
    case meld
    /// 강 · 도라 표시 30×40.
    case river
    /// 상대 울음 24×32.
    case smallMeld
    /// 상대 손 뒷면 18×24.
    case back

    package var width: CGFloat {
        switch self {
        case .hand: 46
        case .result: 40
        case .meld: 34
        case .river: 30
        case .smallMeld: 24
        case .back: 18
        }
    }

    package var height: CGFloat {
        switch self {
        case .hand: 62
        case .result: 54
        case .meld: 46
        case .river: 40
        case .smallMeld: 32
        case .back: 24
        }
    }

    package var size: CGSize { CGSize(width: width, height: height) }

    /// 보조 글자를 빼고 막대 사이를 넓히는 작은 크기(24×32 이하).
    package var isSimplified: Bool { width <= 24 }
}

/// 그림 상태(UX:150 — 쯔모기리 한 단 어둡게 · 울려 간 패 흐리게 · 못 버리는 패 흐림 · 하이라이트).
package nonisolated enum MahjongTileState: String, CaseIterable, Hashable, Sendable {
    case normal
    /// 쯔모기리한 강 패 — 몸체를 한 단 어둡게.
    case tsumogiri
    /// 남이 울어 간 강 패 — 흐리게 남긴다(공개 정보).
    case taken
    /// 지금 못 버리는 손패(쿠이카에·리치 무장 밖) — 흐림.
    case disabled
    /// 방금 버린 패 테두리 강조.
    case highlighted
}

/// 정규 좌표(0~1, 얼굴 칸 기준 — 위가 0). `CGPoint` 를 쓰지 않는 것은 Sendable·Hashable 을 위해서다.
package nonisolated struct MahjongArtPoint: Hashable, Sendable {
    package let x: Double
    package let y: Double

    package init(_ x: Double, _ y: Double) {
        self.x = x
        self.y = y
    }
}

/// 잉크 이름 — 실제 색은 팔레트가 정한다.
package nonisolated enum MahjongTileInk: String, Hashable, Sendable, CaseIterable {
    case navy, red, green, blue, gold, lavender
}

/// 한 면의 배치 — 그리는 쪽은 이 값만 읽는다.
package nonisolated struct MahjongTileLayout: Equatable, Sendable {
    /// 통 원 하나(중심 · 반지름은 얼굴 폭 비율).
    package struct Pip: Equatable, Sendable {
        package let center: MahjongArtPoint
        package let radius: Double
        package let ink: MahjongTileInk
    }

    /// 삭 막대 하나(세로 — 중심 · 길이는 얼굴 높이 비율).
    package struct Stick: Equatable, Sendable {
        package let center: MahjongArtPoint
        package let length: Double
        package let ink: MahjongTileInk
    }

    /// 글자 하나(중심 · 크기는 얼굴 높이 비율).
    package struct Glyph: Equatable, Sendable {
        package let text: String
        package let center: MahjongArtPoint
        package let size: Double
        package let ink: MahjongTileInk
    }

    package var pips: [Pip] = []
    package var sticks: [Stick] = []
    package var glyphs: [Glyph] = []
    /// 1삭 — 우리 모양(대 한 마디 + 잎 둘 + 빨간 점).
    package var sprout = false
    /// 白 — 라벤더 둥근 사각 테두리.
    package var hakuFrame = false
    /// 적5 — 오른쪽 위 금색 점(색만으로 가르지 않는다).
    package var goldDot = false
    /// 뒷면.
    package var isBack = false
    /// 모서리 보조 글자(수패 1~9 · 자패 동남서북백발중). 단순화 크기·보조 끔이면 그리는 쪽이 뺀다.
    package var cornerLabel: String?
}

/// 팔레트 — 몸체 위·아래 · 베벨 · 뒷면 두 색 · 뒷면 테두리 · 글자 남색(JSON 7색) + 고정 잉크.
package nonisolated struct MahjongTilePalette: Equatable, Sendable, Codable {
    /// "#RRGGBB".
    package var bodyTop: String
    package var bodyBottom: String
    package var bevel: String
    package var backTop: String
    package var backBottom: String
    package var backRim: String
    package var ink: String

    /// 코드 팔레트(UX §2.6 — 큐브 타일 몸체 결 · 짙은 남색 뒷면 + 분홍 테두리).
    package static let standard = MahjongTilePalette(
        bodyTop: "#FBF9FF", bodyBottom: "#ECE7F7", bevel: "#C9C0E3", backTop: "#2A3270", backBottom: "#1B2150",
        backRim: "#FF6FA5", ink: "#1F2A5A")

    package init(bodyTop: String, bodyBottom: String, bevel: String, backTop: String, backBottom: String,
                 backRim: String, ink: String) {
        self.bodyTop = bodyTop
        self.bodyBottom = bodyBottom
        self.bevel = bevel
        self.backTop = backTop
        self.backBottom = backBottom
        self.backRim = backRim
        self.ink = ink
    }

    /// 받은 JSON → 팔레트. 못 받았거나(nil) 틀리면(키 빠짐·색 글자 틀림) **코드 팔레트**(네트워크는 이 함수 밖 일).
    package static func resolved(from json: Data?) -> MahjongTilePalette {
        guard let json, let decoded = try? JSONDecoder().decode(MahjongTilePalette.self, from: json),
              decoded.allColors.allSatisfy({ rgb(hex: $0) != nil })
        else { return .standard }
        return decoded
    }

    package var allColors: [String] { [bodyTop, bodyBottom, bevel, backTop, backBottom, backRim, ink] }

    /// 고정 잉크(팔레트 JSON 이 덮지 않는다 — 전통 색 구분).
    package func hex(_ ink: MahjongTileInk) -> String {
        switch ink {
        case .navy: self.ink
        case .red: "#DE2F45"
        case .green: "#12B886"
        case .blue: "#2563EB"
        case .gold: "#F5B700"
        case .lavender: "#9B8BD6"
        }
    }

    /// "#RRGGBB" → 0~1 세 채널. 틀리면 nil.
    package static func rgb(hex: String) -> (r: Double, g: Double, b: Double)? {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        return (Double((value >> 16) & 0xFF) / 255, Double((value >> 8) & 0xFF) / 255, Double(value & 0xFF) / 255)
    }
}

package nonisolated enum MahjongTileArtModel {
    /// 만 위 글자(1~9). 5 는 전통대로 伍.
    package static let manNumerals = ["一", "二", "三", "四", "伍", "六", "七", "八", "九"]
    package static let manSuffix = "萬"
    /// 자패 글자(종류 27~33 = 동남서북백발중). 白 은 글자 대신 테두리로 그린다.
    package static let honorGlyphs = ["東", "南", "西", "北", "白", "發", "中"]
    package static let honorCornerLabels = ["동", "남", "서", "북", "백", "발", "중"]
    /// 글꼴이 빠짐없이 가져야 하는 글자(조용한 대체 방지 — CC-29, 伍 포함).
    package static var requiredGlyphs: String { manNumerals.joined() + manSuffix + "東南西北中發" }
    /// 요청 글꼴 PostScript 이름(UX §2.3 실측 — 이 맥의 기본 글꼴). 없으면 두 번째.
    package static let preferredFontNames = ["HiraMinProN-W6", "PingFangSC-Semibold"]

    /// 한글 이름("5만" · "동").
    package static func koreanName(kind: Int) -> String {
        switch kind {
        case 0..<9: "\(kind + 1)만"
        case 9..<18: "\(kind - 8)통"
        case 18..<27: "\(kind - 17)삭"
        case 27..<34: honorCornerLabels[kind - 27]
        default: "?"
        }
    }

    /// 방위 → 시계 방향 90° 회전 수(그 사람 쪽이 패의 아래). 나 0 · 하가(오른쪽) 3 · 대면 2 · 상가(왼쪽) 1.
    package static func rotation(for compass: MahjongCompass) -> Int {
        switch compass {
        case .bottom: 0
        case .right: 3
        case .top: 2
        case .left: 1
        }
    }

    /// 한 면의 배치.
    package static func layout(face: MahjongTileFace) -> MahjongTileLayout {
        guard case .tile(let kind, let red) = face else {
            var back = MahjongTileLayout()
            back.isBack = true
            return back
        }
        var layout: MahjongTileLayout
        switch kind {
        case 0..<9: layout = man(kind + 1)
        case 9..<18: layout = pin(kind - 8)
        case 18..<27: layout = sou(kind - 17)
        default: layout = honor(kind - 27)
        }
        if red {
            layout.pips = layout.pips.map { .init(center: $0.center, radius: $0.radius, ink: .red) }
            layout.sticks = layout.sticks.map { .init(center: $0.center, length: $0.length, ink: .red) }
            layout.glyphs = layout.glyphs.map { .init(text: $0.text, center: $0.center, size: $0.size, ink: .red) }
            layout.goldDot = true
        }
        return layout
    }

    // MARK: 만

    private static func man(_ n: Int) -> MahjongTileLayout {
        var layout = MahjongTileLayout()
        layout.glyphs = [
            .init(text: manNumerals[n - 1], center: .init(0.5, 0.30), size: 0.36, ink: .navy),
            .init(text: manSuffix, center: .init(0.5, 0.71), size: 0.40, ink: .red),
        ]
        layout.cornerLabel = "\(n)"
        return layout
    }

    // MARK: 통 — 전통 자리, 우리 색

    private static func pin(_ n: Int) -> MahjongTileLayout {
        var layout = MahjongTileLayout()
        layout.cornerLabel = "\(n)"
        let l = 0.28, c = 0.5, r = 0.72
        func p(_ x: Double, _ y: Double, _ radius: Double, _ ink: MahjongTileInk) -> MahjongTileLayout.Pip {
            .init(center: .init(x, y), radius: radius, ink: ink)
        }
        switch n {
        case 1: layout.pips = [p(c, 0.5, 0.36, .red)]
        case 2: layout.pips = [p(c, 0.27, 0.19, .blue), p(c, 0.73, 0.19, .green)]
        case 3: layout.pips = [p(0.26, 0.2, 0.15, .blue), p(c, 0.5, 0.15, .red), p(0.74, 0.8, 0.15, .green)]
        case 4: layout.pips = [p(l, 0.28, 0.17, .blue), p(r, 0.28, 0.17, .green),
                               p(l, 0.72, 0.17, .green), p(r, 0.72, 0.17, .blue)]
        case 5: layout.pips = [p(0.26, 0.22, 0.14, .blue), p(0.74, 0.22, 0.14, .green), p(c, 0.5, 0.14, .red),
                               p(0.26, 0.78, 0.14, .green), p(0.74, 0.78, 0.14, .blue)]
        case 6: layout.pips = [p(l, 0.18, 0.13, .green), p(r, 0.18, 0.13, .green),
                               p(l, 0.52, 0.13, .red), p(r, 0.52, 0.13, .red),
                               p(l, 0.82, 0.13, .red), p(r, 0.82, 0.13, .red)]
        case 7: layout.pips = [p(0.24, 0.13, 0.11, .green), p(c, 0.24, 0.11, .green), p(0.76, 0.35, 0.11, .green),
                               p(l, 0.6, 0.11, .red), p(r, 0.6, 0.11, .red),
                               p(l, 0.86, 0.11, .red), p(r, 0.86, 0.11, .red)]
        case 8: layout.pips = [0.12, 0.37, 0.63, 0.88].flatMap { y in [p(l, y, 0.115, .blue), p(r, y, 0.115, .blue)] }
        default:
            layout.pips = [(0.18, MahjongTileInk.blue), (0.5, .red), (0.82, .green)].flatMap { y, ink in
                [p(0.2, y, 0.12, ink), p(c, y, 0.12, ink), p(0.8, y, 0.12, ink)]
            }
        }
        return layout
    }

    // MARK: 삭 — 전통 자리(5삭 가운데 · 7삭 맨 위 · 9삭 가운데 세로줄만 빨강)

    private static func sou(_ n: Int) -> MahjongTileLayout {
        var layout = MahjongTileLayout()
        layout.cornerLabel = "\(n)"
        func s(_ x: Double, _ y: Double, _ length: Double, _ ink: MahjongTileInk = .green) -> MahjongTileLayout.Stick {
            .init(center: .init(x, y), length: length, ink: ink)
        }
        switch n {
        case 1: layout.sprout = true
        case 2: layout.sticks = [s(0.5, 0.27, 0.36), s(0.5, 0.73, 0.36)]
        case 3: layout.sticks = [s(0.5, 0.27, 0.36), s(0.3, 0.73, 0.36), s(0.7, 0.73, 0.36)]
        case 4: layout.sticks = [s(0.3, 0.27, 0.36), s(0.7, 0.27, 0.36), s(0.3, 0.73, 0.36), s(0.7, 0.73, 0.36)]
        case 5: layout.sticks = [s(0.24, 0.27, 0.36), s(0.76, 0.27, 0.36), s(0.5, 0.5, 0.36, .red),
                                 s(0.24, 0.73, 0.36), s(0.76, 0.73, 0.36)]
        case 6: layout.sticks = [0.27, 0.73].flatMap { y in [0.22, 0.5, 0.78].map { s($0, y, 0.36) } }
        case 7: layout.sticks = [s(0.5, 0.15, 0.24, .red)]
            + [0.47, 0.8].flatMap { y in [0.22, 0.5, 0.78].map { s($0, y, 0.28) } }
        case 8: layout.sticks = [0.27, 0.73].flatMap { y in [0.16, 0.39, 0.61, 0.84].map { s($0, y, 0.36) } }
        default:
            layout.sticks = [0.17, 0.5, 0.83].flatMap { y in
                [s(0.2, y, 0.26), s(0.5, y, 0.26, .red), s(0.8, y, 0.26)]
            }
        }
        return layout
    }

    // MARK: 자패

    private static func honor(_ index: Int) -> MahjongTileLayout {
        var layout = MahjongTileLayout()
        layout.cornerLabel = honorCornerLabels[index]
        switch index {
        case 4: layout.hakuFrame = true
        case 5: layout.glyphs = [.init(text: honorGlyphs[index], center: .init(0.5, 0.52), size: 0.56, ink: .green)]
        case 6: layout.glyphs = [.init(text: honorGlyphs[index], center: .init(0.5, 0.52), size: 0.56, ink: .red)]
        default: layout.glyphs = [.init(text: honorGlyphs[index], center: .init(0.5, 0.52), size: 0.56, ink: .navy)]
        }
        return layout
    }
}
