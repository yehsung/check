import AppKit
import SwiftUI
import CheckCore

// MARK: - 아잉 큐브 타일 그림 (설계서 §5 · 2판 §3 "실제 4색")
//
// **우리 그림이다.** 상표 게임의 타일 모양·조커 그림(별·웃는 얼굴)·서체를 따라 하지 않는다.
//   · 몸체 = 밝은 크림-라벤더 그라데이션(#FBF9FF → #ECE7F7), 둥근 모서리, 아래 베벨(입체 '큐브').
//   · 숫자 = 굵은 둥근 서체, **밝은 타일 위 진한 4색**: A 빨강 #DE2F45 · B 파랑 #2563EB · C 검정 #141318 · D 주황 #EA7A0C.
//     (2판: 보라·분홍·민트 파스텔은 판에서 서로 안 갈렸다 — 실물 4색으로.)
//   · 숫자 아래 **작은** 모양 표식 A● B▲ C■ D◆ — 색약 보조(색만으로 가르지 않는다). 숫자보다 눈에 띄지 않게 작게.
//   · 조커 = 아잉이 얼굴(기존 마스코트 자산 `aing-neutral`) + 네 색 점(어느 색이든 된다).
//   · 크기: 모든 치수가 타일 폭·높이에서 나온다 — 받침대 36×50 · 결과/규칙 32×44 · 판은 캔버스 배율(40×56 × 배율).

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
        let corner = size.corner
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(RummyTilePalette.color(RummyTilePalette.bevel))
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(LinearGradient(colors: [RummyTilePalette.color(RummyTilePalette.bodyTop),
                                              RummyTilePalette.color(RummyTilePalette.bodyBottom)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(height: frame.height - size.bevel)
                .overlay(
                    RoundedRectangle(cornerRadius: corner, style: .continuous)
                        .stroke(Color.white.opacity(0.9), lineWidth: 0.8)
                        .padding(0.4)
                )
            content
                .frame(width: frame.width, height: frame.height - size.bevel)
        }
        .frame(width: frame.width, height: frame.height)
        .compositingGroup()
        .shadow(color: Color.black.opacity(0.30), radius: 1.2, x: 0, y: 1)
        .overlay(
            RoundedRectangle(cornerRadius: corner + 1, style: .continuous)
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
            VStack(spacing: size.stackSpacing) {
                Text("\(number)")
                    .font(.system(size: size.numberFont, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .foregroundStyle(RummyTilePalette.ink(for: color))
                RummyTileMark(colorIndex: color, size: size.markSize)
            }
            .padding(.top, size.topPadding)
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
        let side = size.size.width * 0.8
        let dot = max(2.4, size.size.width * 0.11)
        VStack(spacing: size.stackSpacing * 1.4) {
            Group {
                if let image = Self.faceImage {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                } else {
                    Circle()
                        .fill(RummyTilePalette.color((0x7B, 0x61, 0xFF)))
                        .overlay(Text("아잉").font(.system(size: side * 0.3, weight: .heavy, design: .rounded))
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
        .padding(.top, size.topPadding)
    }
}

/// 엎어 놓은 타일 뒷면(상대 받침대 장수 표시용) — 라벤더 몸체 위 작은 분홍 점. 우리 그림.
struct RummyTileBack: View {
    var size: CGSize = CGSize(width: 12, height: 17)

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
