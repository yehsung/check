#if os(iOS)
import CheckCore
import CheckMobileShared
import SwiftUI

// 폰 아잉 큐브 타일 그림(맥 `RummyTileView` 견본 — 값은 코어 `RummyTilePalette`·`RummyTileSize` 한 곳이다).
// **우리 그림이다.** 상표 게임의 타일 모양·조커 그림·서체를 따라 하지 않는다. 몸체는 밝은 크림-라벤더 + 아래 베벨, 숫자는 실제 4색, 숫자 아래 작은 색 표식 ●▲■◆(색약 보조),
// 조커는 아잉이 얼굴 + 네 색 점. 모든 치수가 타일 크기에서 나온다 — 크기는 값으로 받는다(받침대 34×47 · 판은 배율).

/// 색약 보조 표식 — ●▲■◆. 글리프가 아니라 도형으로 그린다(서체마다 굵기가 달라지지 않게).
struct GamesRummyTileMark: View {
    let colorIndex: Int
    var size: CGFloat = 7

    var body: some View {
        let ink = RummyTilePalette.ink(for: colorIndex)
        Group {
            switch colorIndex {
            case 0: Circle().fill(ink)
            case 1: GamesRummyTriangle().fill(ink)
            case 2: Rectangle().fill(ink).padding(size * 0.06)
            default: Rectangle().fill(ink).rotationEffect(.degrees(45)).padding(size * 0.16)
            }
        }
        .frame(width: size, height: size)
    }
}

private struct GamesRummyTriangle: Shape {
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
struct GamesRummyTile: View {
    let face: RummyFace
    let size: CGSize
    /// 이번 차례에 낸 타일(노란 링).
    var highlighted = false
    /// 끌려 나간 자리(흐리게).
    var dimmed = false

    private var metrics: RummyTileSize { RummyTileSize(size) }

    var body: some View {
        let metrics = self.metrics
        let corner = metrics.corner
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(RummyTilePalette.color(RummyTilePalette.bevel))
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(LinearGradient(colors: [RummyTilePalette.color(RummyTilePalette.bodyTop),
                                              RummyTilePalette.color(RummyTilePalette.bodyBottom)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(height: size.height - metrics.bevel)
                .overlay(RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .stroke(Color.white.opacity(0.9), lineWidth: 0.8)
                    .padding(0.4))
            content(metrics)
                .frame(width: size.width, height: size.height - metrics.bevel)
        }
        .frame(width: size.width, height: size.height)
        .compositingGroup()
        .shadow(color: Color.black.opacity(0.30), radius: 1.2, x: 0, y: 1)
        .overlay(RoundedRectangle(cornerRadius: corner + 1, style: .continuous)
            .stroke(RummyTilePalette.color(RummyTilePalette.highlight), lineWidth: highlighted ? 2.5 : 0)
            .padding(-2))
        .opacity(dimmed ? 0.28 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(RummyTilePalette.accessibilityName(face))
    }

    @ViewBuilder
    private func content(_ metrics: RummyTileSize) -> some View {
        if let color = face.color, let number = face.number {
            VStack(spacing: metrics.stackSpacing) {
                Text("\(number)")
                    .font(.system(size: metrics.numberFont, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .foregroundStyle(RummyTilePalette.ink(for: color))
                GamesRummyTileMark(colorIndex: color, size: metrics.markSize)
            }
            .padding(.top, metrics.topPadding)
        } else {
            GamesRummyJokerFace(metrics: metrics)
        }
    }
}

/// 조커 — 아잉이 얼굴 + 네 색 점. 그림을 못 읽으면 보라 원 안의 '아잉' 글자(상표 게임 조커 그림 금지).
struct GamesRummyJokerFace: View {
    let metrics: RummyTileSize

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let side = metrics.size.width * 0.8
        let dot = max(2.4, metrics.size.width * 0.11)
        VStack(spacing: metrics.stackSpacing * 1.4) {
            Group {
                if let image = MobileArt.character(id: AingCharacterArt.defaultID, expression: .neutral,
                                                   pointSize: side, displayScale: displayScale) {
                    Image(uiImage: image).resizable().interpolation(.high).scaledToFit()
                } else {
                    Circle()
                        .fill(RummyTilePalette.color((0x7B, 0x61, 0xFF)))
                        .overlay(Text(verbatim: "아잉").font(.system(size: side * 0.3, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white))
                }
            }
            .frame(width: side, height: side)
            HStack(spacing: max(1, dot * 0.38)) {
                ForEach(0..<4, id: \.self) { index in
                    Circle().fill(RummyTilePalette.ink(for: index)).frame(width: dot, height: dot)
                }
            }
        }
        .padding(.top, metrics.topPadding)
    }
}

/// 엎어 놓은 타일 뒷면(상대 장수 표시용) — 라벤더 몸체 위 작은 분홍 점. 남의 패는 **장수만**이다.
struct GamesRummyTileBack: View {
    var size = CGSize(width: 12, height: 17)

    var body: some View {
        RoundedRectangle(cornerRadius: size.width * 0.25, style: .continuous)
            .fill(LinearGradient(colors: [Color(red: 0.62, green: 0.56, blue: 0.98), Color(red: 0.42, green: 0.35, blue: 0.86)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(RoundedRectangle(cornerRadius: size.width * 0.25, style: .continuous)
                .stroke(Color.white.opacity(0.55), lineWidth: 0.7))
            .overlay(Circle().fill(Color(red: 1.0, green: 0.55, blue: 0.80)).frame(width: size.width * 0.32))
            .frame(width: size.width, height: size.height)
            .shadow(color: .black.opacity(0.35), radius: 0.8, y: 0.6)
    }
}

/// 게임 탭 카드 썸네일 60pt — 남보라 펠트 위 `cube.fill`(맥 입구·미션 줄과 같은 기호).
struct GamesRummyTabThumbnail: View {
    var side: CGFloat = 60

    var body: some View {
        ZStack {
            GamesRummyFeltFallback()
            Image(systemName: MeText.dailyMissionIcon(game: "rummy"))
                .font(.system(size: side * 0.42, weight: .semibold))
                .foregroundStyle(LinearGradient(colors: [Color(red: 1.0, green: 0.62, blue: 0.85), Color(red: 0.72, green: 0.58, blue: 1.0)],
                                                startPoint: .top, endPoint: .bottom))
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityHidden(true)
    }
}
#endif
