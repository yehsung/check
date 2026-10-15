import SwiftUI

/// 밝은 화면 · 어두운 화면 색. 기계 그림(라벤더 몸통 · 캡슐)은 둘 다에서 같고, 바탕 · 글자 · 칩 · 빛이 갈린다.
/// 황금 연출은 원래 어두운 무대라 둘이 같다.
struct GachaMachineTheme {
    var dark: Bool

    var bgTop: Color
    var bgBottom: Color
    var bgGlow: Color
    /// 안내 글자(손잡이를 돌려서 뽑기 · 두근두근 · 톡톡).
    var ink: Color
    /// 결과 이름.
    var title: Color
    /// 조각 "+1" 처럼 강조한 작은 글자.
    var accent: Color
    /// 칩 아래 "+1 조각" 처럼 작은 알약 속 글자(바탕 대비가 커야 한다).
    var accentStrong: Color
    var chipFill: Color
    var chipStroke: Color
    var chipText: Color
    /// 경고 줄(루비 부족 · 실패)의 바탕과 글자.
    var pillFill: Color
    var warn: Color
    /// 테두리만 있는 배지(이미 있는 친구예요).
    var badgeFill: Color
    var badgeText: Color
    /// [닫기].
    var closeFill: Color
    var closeStroke: Color
    var closeText: Color
    /// "-50".
    var spend: Color
    /// 바닥 그림자 진하기.
    var floorShadow: Double
    /// 유리 돔 뒷면(우윳빛)과 아래 틴트.
    var glassBack: (Color, Color)
    var glassTint: Color
    /// 일반 공개의 무대(가장자리가 가라앉아 빛이 보이게).
    var spotlight: [Gradient.Stop]
    /// 일반 공개 섬광 색과 세기.
    var flash: Color
    var flashPeak: Double
    /// 일반 공개 빛줄기가 어두운 바탕 기준인가.
    var raysOnDark: Bool
    /// 조각 비행(꼬리 · 빛무리 · 결정 테두리) — 밝은 바탕에서도 읽히게 진한 보라 심을 둔다.
    var shardTrail: Color
    var shardOrbEdge: Color
    var shardOutline: Color

    static let light = GachaMachineTheme(
        dark: false,
        bgTop: GPalette.hex(0xF8F5FF), bgBottom: GPalette.hex(0xECE4FF), bgGlow: Color.white.opacity(0.9),
        ink: GPalette.lavInk, title: GPalette.plum, accent: GPalette.lavDeep, accentStrong: GPalette.lavInk,
        chipFill: Color.white.opacity(0.92), chipStroke: GPalette.hex(0xD9CBFF), chipText: GPalette.plum,
        pillFill: Color.white.opacity(0.9), warn: GPalette.hex(0xB0477A),
        badgeFill: Color.white.opacity(0.92), badgeText: GPalette.lavInk,
        closeFill: Color.white.opacity(0.92), closeStroke: GPalette.hex(0xD9CBFF), closeText: GPalette.lavInk,
        spend: GPalette.hex(0xD9468F),
        floorShadow: 0.13,
        glassBack: (Color.white.opacity(0.55), GPalette.hex(0xE6DBFF, 0.55)), glassTint: GPalette.hex(0xB9A0F5, 0.18),
        spotlight: [
            .init(color: GPalette.hex(0xF4EEFF, 0.0), location: 0),
            .init(color: GPalette.hex(0xC2A9FF, 0.55), location: 0.36),
            .init(color: GPalette.hex(0x8A68E6, 0.85), location: 0.72),
            .init(color: GPalette.hex(0x6E4DD2, 0.95), location: 1),
        ],
        flash: Color.white, flashPeak: 0.8, raysOnDark: false,
        shardTrail: GPalette.hex(0x7B5CE6), shardOrbEdge: GPalette.hex(0x6A4FC8), shardOutline: GPalette.hex(0x3B2A78, 0.85)
    )

    static let night = GachaMachineTheme(
        dark: true,
        bgTop: GPalette.hex(0x221A3D), bgBottom: GPalette.hex(0x120C22), bgGlow: GPalette.hex(0x6F55C8, 0.38),
        ink: GPalette.hex(0xCDBDFF), title: GPalette.hex(0xF4EFFF), accent: GPalette.hex(0xC4B0FF), accentStrong: GPalette.hex(0xE4D8FF),
        chipFill: GPalette.hex(0x2B2148, 0.94), chipStroke: GPalette.hex(0x5C4A99), chipText: GPalette.hex(0xF0EAFF),
        pillFill: GPalette.hex(0x2B2148, 0.94), warn: GPalette.hex(0xFF97C2),
        badgeFill: GPalette.hex(0x2B2148, 0.94), badgeText: GPalette.hex(0xD9CCFF),
        closeFill: Color.white.opacity(0.12), closeStroke: Color.white.opacity(0.24), closeText: Color.white,
        spend: GPalette.hex(0xFF86BC),
        floorShadow: 0.42,
        glassBack: (Color.white.opacity(0.20), GPalette.hex(0xB9A0F5, 0.26)), glassTint: GPalette.hex(0x7B5CE6, 0.22),
        spotlight: [
            .init(color: GPalette.hex(0x2A1D55, 0.0), location: 0),
            .init(color: GPalette.hex(0x2A1D55, 0.55), location: 0.36),
            .init(color: GPalette.hex(0x160E30, 0.88), location: 0.72),
            .init(color: GPalette.hex(0x0B0717, 0.96), location: 1),
        ],
        flash: GPalette.hex(0xECE4FF), flashPeak: 0.5, raysOnDark: true,
        shardTrail: GPalette.hex(0xB49BFF), shardOrbEdge: GPalette.hex(0x8C6CF2), shardOutline: GPalette.hex(0x120A26, 0.6)
    )

    static func of(_ scheme: ColorScheme) -> GachaMachineTheme { scheme == .dark ? night : light }
}
