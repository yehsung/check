import CoreGraphics
import Foundation
import SwiftUI

// 아잉 큐브 타일·그림의 순수 값 — 맥·폰 공용(0.3.71 맥 `RummyTileView`·`RummyArt` 에서 폰 1.0.17 을 위해 옮겼다. 값은 그대로다).
// 그림 자체(타일 뷰 · 받침대 · 펠트)는 플랫폼 몫이다 — 맥 `RummyTileView`·`RummyArt`(AppKit), 폰 `GamesRummyTile`·`GamesRummyArt`(UIKit).

/// 타일 팔레트 — 순수 상수(시험이 같은 값을 되묻는다).
package enum RummyTilePalette {
    package typealias RGB = (r: Int, g: Int, b: Int)

    package static let bodyTop: RGB = (0xFB, 0xF9, 0xFF)
    package static let bodyBottom: RGB = (0xEC, 0xE7, 0xF7)
    /// 아래 베벨(몸체보다 한 단 진한 라벤더).
    package static let bevel: RGB = (0xC9, 0xC0, 0xE3)
    /// A 빨강 · B 파랑 · C 검정 · D 주황(밝은 몸체 위 진한 잉크).
    package static let inks: [RGB] = [(0xDE, 0x2F, 0x45), (0x25, 0x63, 0xEB), (0x14, 0x13, 0x18), (0xEA, 0x7A, 0x0C)]
    /// 이번 차례에 낸 타일 강조 링.
    package static let highlight: RGB = (0xFF, 0xD1, 0x4A)
    /// 무효 세트 테두리.
    package static let invalid: RGB = (0xFF, 0x4D, 0x4F)

    package static func color(_ rgb: RGB) -> Color {
        Color(red: Double(rgb.r) / 255, green: Double(rgb.g) / 255, blue: Double(rgb.b) / 255)
    }

    package static func ink(for colorIndex: Int?) -> Color {
        guard let colorIndex, inks.indices.contains(colorIndex) else { return color((0x5A, 0x4E, 0x7A)) }
        return color(inks[colorIndex])
    }

    /// 접근성 이름(빨강 7 · 조커).
    package static let colorNames = ["빨강", "파랑", "검정", "주황"]

    package static func accessibilityName(_ face: RummyFace) -> String {
        guard let color = face.color, let number = face.number else { return "조커" }
        return "\(colorNames[color]) \(number)"
    }
}

/// 타일 크기. 이름 붙은 두 벌(받침대 · 결과/규칙) + 판 캔버스 배율로 만든 임의 크기.
/// 글자·표식·베벨·모서리는 전부 크기에서 나온다(배율이 바뀌어도 같은 타일로 보이게).
package struct RummyTileSize: Equatable, Sendable {
    package let size: CGSize

    package init(_ size: CGSize) { self.size = size }

    /// 결과 줄 · 규칙 예시 · 머리글.
    package static let table = RummyTileSize(CGSize(width: 32, height: 44))
    /// 받침대(2판 — 받침대 그림의 타일 높이 0.31H 에 맞춘 크기).
    package static let rack = RummyTileSize(CGSize(width: 36, height: 50))

    /// 판 캔버스 타일(논리 40×56) × 배율.
    package static func canvas(scale: CGFloat) -> RummyTileSize {
        RummyTileSize(CGSize(width: CGFloat(RummyTableLayout.tileWidth) * scale,
                             height: CGFloat(RummyTableLayout.tileHeight) * scale))
    }

    package var bevel: CGFloat { max(2, size.height * 0.075) }
    package var corner: CGFloat { max(3, size.width * 0.19) }
    package var numberFont: CGFloat { size.width * 0.6 }
    /// 색약 표식 — 숫자보다 한참 작게(2판: '작게 유지').
    package var markSize: CGFloat { max(3.5, size.width * 0.17) }
    package var topPadding: CGFloat { max(1, size.height * 0.055) }
    package var stackSpacing: CGFloat { max(0.5, size.height * 0.035) }
}

/// 그림 두 장.
package enum RummyArtKind: String, CaseIterable, Sendable {
    case rack
    case table

    /// 공개 버킷 `game-art` 안의 경로.
    package var remotePath: String { "rummy/\(rawValue).png" }
    /// 번들 폴백 사본 이름(`.process("Resources")` 는 폴더를 평탄화하므로 앞머리로 가른다).
    package var bundleName: String { "rummy-\(rawValue)" }
}

/// 받침대 그림의 기준선 — 원본(2400×478, 그림자 없는 판) 높이 H 대비. 설계서 §5 값 그대로.
package enum RummyRackArtMetrics {
    /// 뒷줄 타일 바닥 · 앞줄 타일 바닥(H 대비).
    package static let backRowBottom: CGFloat = 0.44
    package static let frontRowBottom: CGFloat = 0.76
    /// 타일 높이(H 대비).
    package static let tileHeight: CGFloat = 0.31
    /// 원본 가로/세로.
    package static let naturalAspect: CGFloat = 2400.0 / 478.0
    /// 타일이 놓이는 가로 구간(원본 폭 대비 7%~93%) → 높이 H 일 때 좌우 안쪽 여백(pt).
    package static let tileSpanStart: CGFloat = 0.07
    /// 3-슬라이스 끝캡(원본 2400 기준 좌우 약 150px).
    package static let capFraction: CGFloat = 150.0 / 2400.0

    /// 타일 높이 `tile` 에 맞는 받침대 높이.
    package static func height(forTileHeight tile: CGFloat) -> CGFloat { (tile / tileHeight).rounded() }
    /// 높이 H 받침대의 타일 구간 좌우 여백.
    package static func sideInset(height: CGFloat) -> CGFloat { tileSpanStart * naturalAspect * height }
    /// 높이 H 받침대의 끝캡 폭.
    package static func capWidth(height: CGFloat) -> CGFloat { capFraction * naturalAspect * height }
}
