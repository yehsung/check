import AppKit
import SwiftUI
import CheckCore

// MARK: - 아잉 큐브 타일 그림 (설계서 §5)
//
// **우리 그림이다.** 상표 게임의 타일 모양·조커 그림(별·웃는 얼굴)·서체를 따라 하지 않는다.
//   · 몸체 = 밝은 크림-라벤더 그라데이션(#FBF9FF → #ECE7F7), 둥근 7pt, 아래 베벨(입체 '큐브').
//   · 숫자 = 굵은 둥근 서체. 색 A 보라 #7B61FF · B 분홍 #FF4F8B · C 민트 #12B886 · D 주황 #F59E0B.
//   · 숫자 아래 작은 모양 표식 A● B▲ C■ D◆ — 색약 보조(색만으로 가르지 않는다).
//   · 조커 = 아잉이 얼굴(기존 마스코트 자산 `aing-neutral`) + 네 색 점(어느 색이든 된다).
//   · 크기: 판 32×44 · 랙 38×52.

/// 타일 팔레트 — 순수 상수(시험이 같은 값을 되묻는다).
enum RummyTilePalette {
    typealias RGB = (r: Int, g: Int, b: Int)

    static let bodyTop: RGB = (0xFB, 0xF9, 0xFF)
    static let bodyBottom: RGB = (0xEC, 0xE7, 0xF7)
    /// 아래 베벨(몸체보다 한 단 진한 라벤더).
    static let bevel: RGB = (0xC9, 0xC0, 0xE3)
    /// A 보라 · B 분홍 · C 민트 · D 주황.
    static let inks: [RGB] = [(0x7B, 0x61, 0xFF), (0xFF, 0x4F, 0x8B), (0x12, 0xB8, 0x86), (0xF5, 0x9E, 0x0B)]
    /// 이번 차례에 낸 타일 강조 링.
    static let highlight: RGB = (0xFF, 0xD1, 0x4A)
    /// 무효 세트 테두리.
    static let invalid: RGB = (0xFF, 0x4D, 0x4F)

    static func color(_ rgb: RGB) -> Color {
        Color(red: Double(rgb.r) / 255, green: Double(rgb.g) / 255, blue: Double(rgb.b) / 255)
    }

    static func ink(for colorIndex: Int?) -> Color {
        guard let colorIndex, inks.indices.contains(colorIndex) else { return color((0x5A, 0x4E, 0x7A)) }
        return color(inks[colorIndex])
    }

    /// 접근성 이름(보라 7 · 조커).
    static let colorNames = ["보라", "분홍", "민트", "주황"]

    static func accessibilityName(_ face: RummyFace) -> String {
        guard let color = face.color, let number = face.number else { return "조커" }
        return "\(colorNames[color]) \(number)"
    }
}

/// 타일 크기 두 벌.
enum RummyTileSize: Equatable {
    case table
    case rack

    var size: CGSize {
        switch self {
        case .table: return CGSize(width: 32, height: 44)
        case .rack: return CGSize(width: 38, height: 52)
        }
    }

    var bevel: CGFloat { self == .rack ? 4 : 3 }
    var numberFont: CGFloat { self == .rack ? 22 : 18 }
    var markSize: CGFloat { self == .rack ? 7 : 6 }
}

/// 색약 보조 표식 — A● B▲ C■ D◆. 글리프가 아니라 도형으로 그린다(서체마다 굵기가 달라지지 않게).
struct RummyTileMark: View {
    let colorIndex: Int
    var size: CGFloat = 7

    var body: some View {
        let ink = RummyTilePalette.ink(for: colorIndex)
        Group {
            switch colorIndex {
            case 0: Circle().fill(ink)
            case 1: RummyTriangle().fill(ink)
            case 2: Rectangle().fill(ink).padding(size * 0.06)
            default: Rectangle().fill(ink).rotationEffect(.degrees(45)).padding(size * 0.16)
            }
        }
        .frame(width: size, height: size)
    }
}

struct RummyTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// 타일 한 장.
struct RummyTileView: View {
    let face: RummyFace
    var size: RummyTileSize = .rack
    /// 이번 차례에 낸 타일(노란 링).
    var highlighted: Bool = false
    /// 끌려 나간 자리(흐리게).
    var dimmed: Bool = false

    var body: some View {
        let frame = size.size
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(RummyTilePalette.color(RummyTilePalette.bevel))
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(LinearGradient(colors: [RummyTilePalette.color(RummyTilePalette.bodyTop),
                                              RummyTilePalette.color(RummyTilePalette.bodyBottom)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(height: frame.height - size.bevel)
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Color.white.opacity(0.9), lineWidth: 0.8)
                        .padding(0.4)
                )
            content
                .frame(width: frame.width, height: frame.height - size.bevel)
        }
        .frame(width: frame.width, height: frame.height)
        .shadow(color: Color.black.opacity(0.28), radius: 1.2, x: 0, y: 1)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(RummyTilePalette.color(RummyTilePalette.highlight), lineWidth: highlighted ? 2.5 : 0)
                .padding(-2)
        )
        .opacity(dimmed ? 0.28 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(RummyTilePalette.accessibilityName(face))
    }

    @ViewBuilder
    private var content: some View {
        if let color = face.color, let number = face.number {
            VStack(spacing: size == .rack ? 2 : 1) {
                Text("\(number)")
                    .font(.system(size: size.numberFont, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .foregroundStyle(RummyTilePalette.ink(for: color))
                RummyTileMark(colorIndex: color, size: size.markSize)
            }
            .padding(.top, size == .rack ? 3 : 2)
        } else {
            RummyJokerFace(size: size)
        }
    }
}

/// 조커 — 아잉이 얼굴 + 네 색 점. 자산을 못 읽으면 보라 원 안의 '아잉' 글자(상표 게임 조커 그림 금지).
struct RummyJokerFace: View {
    let size: RummyTileSize

    static var faceImage: NSImage? {
        CheckMascotAssets.image(for: .neutral, characterID: CharacterCatalog.builtInAingID)
    }

    var body: some View {
        let side = size.size.width - (size == .rack ? 8 : 7)
        VStack(spacing: size == .rack ? 3 : 2) {
            Group {
                if let image = Self.faceImage {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                } else {
                    Circle()
                        .fill(RummyTilePalette.ink(for: 0))
                        .overlay(Text("아잉").font(.system(size: side * 0.3, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white))
                }
            }
            .frame(width: side, height: side)
            HStack(spacing: 1.5) {
                ForEach(0..<4, id: \.self) { index in
                    Circle().fill(RummyTilePalette.ink(for: index))
                        .frame(width: size == .rack ? 4 : 3.2, height: size == .rack ? 4 : 3.2)
                }
            }
        }
        .padding(.top, size == .rack ? 3 : 2)
    }
}
