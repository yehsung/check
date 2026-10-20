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
    /// 조각 "+1" 처럼 강조한 글자(결과 글줄 · 24pt). 밝은 쪽은 진한 라벤더 — 옅은 라벤더(#9979E6)는 공개 바탕과 2.1:1 이었다(큰 글자 기준 3:1 미달).
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
        ink: GPalette.lavInk, title: GPalette.plum, accent: GPalette.lavInk, accentStrong: GPalette.lavInk,
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

/// 희귀 공개(황금 · 무지개 — v0.3.59)의 빛깔. 연출의 **모양**(늦게 떨어짐 · 반전 · 어두운 무대 · 모으기 · 빛줄기 18 · 고리 넷 · 반짝 제목)은
/// 둘이 같고 **색만** 갈린다 — 금은 따뜻한 한 색, 무지개는 빛줄기 · 고리 · 제목 글자가 일곱 빛(빨→보, 사용자 시안 E 의 파스텔 무지개)을 돌고
/// 한 색이 필요한 자리(새는 빛 · 그림자 · 섬광 심)는 옅은 분홍빛 흰색이다. 무지개도 정적이다(시간에 따라 흐르는 색 없음 — 시안 결정).
enum GRare: Equatable, Sendable {
    case gold
    case rainbow

    init?(_ kind: GachaRevealKind) {
        switch kind {
        case .gold: self = .gold
        case .rainbow: self = .rainbow
        case .new, .duplicate: return nil
        }
    }

    /// 무지개 일곱 빛(빨 · 주 · 노 · 초 · 파 · 남 · 보). 어두운 무대에 더하기 합성으로 얹어도 형광으로 안 튀는 밝은 파스텔.
    static let spectrum: [Color] = [
        GPalette.hex(0xFF7A90), GPalette.hex(0xFFAE5E), GPalette.hex(0xFFE35A), GPalette.hex(0x7EDF8C),
        GPalette.hex(0x6CB8FF), GPalette.hex(0x9C8CFF), GPalette.hex(0xE08CFF),
    ]

    /// 한 색이 필요한 자리의 주 색(새는 빛 · 결정 테 · 초상 그림자 · 빛 고리 기본).
    var primary: Color {
        switch self {
        case .gold: return GPalette.gold
        case .rainbow: return GPalette.hex(0xF2B6FF)
        }
    }

    /// 밝은 심(금 사이 밝은 선 · 반전 고리 · 부제 글자).
    var light: Color {
        switch self {
        case .gold: return GPalette.goldLight
        case .rainbow: return GPalette.hex(0xFFF0FB)
        }
    }

    /// 빛줄기 i(전체 n)의 색 — 금은 한 색, 무지개는 둘레를 따라 일곱 빛.
    func ray(_ i: Int, of n: Int) -> Color {
        switch self {
        case .gold: return GPalette.hex(0xFFE08A)
        case .rainbow: return Self.spectrum[(i * Self.spectrum.count / max(1, n)) % Self.spectrum.count]
        }
    }

    /// 퍼지는 빛 고리 k 번째의 색.
    func ring(_ k: Int) -> Color {
        switch self {
        case .gold: return GPalette.gold
        case .rainbow: return Self.spectrum[(k * 2) % Self.spectrum.count]
        }
    }

    /// 가운데 심 광채.
    var core: Color {
        switch self {
        case .gold: return GPalette.hex(0xFFE9A8)
        case .rainbow: return GPalette.hex(0xFFF3FC)
        }
    }

    /// 터지는 순간의 섬광(가운데 → 가장자리, 더하기 합성).
    var flash: [Color] {
        switch self {
        case .gold: return [GPalette.hex(0xFFE7A6), GPalette.hex(0xFFC94A, 0.85), GPalette.hex(0xB07A10, 0.5)]
        case .rainbow: return [GPalette.hex(0xFFF5FD), GPalette.hex(0xF0C4FF, 0.85), GPalette.hex(0x6F55D8, 0.5)]
        }
    }

    /// 어두운 무대 가운데에 도는 빛(금 = 갈색 온기 · 무지개 = 보랏빛).
    var dimGlow: Color {
        switch self {
        case .gold: return GPalette.hex(0x7A5212)
        case .rainbow: return GPalette.hex(0x5A3296)
        }
    }

    /// 반짝 제목의 글자 칠 — 금은 위 → 아래 금빛, 무지개는 왼쪽 → 오른쪽 일곱 빛.
    var titleFill: LinearGradient {
        switch self {
        case .gold:
            return LinearGradient(colors: [GPalette.hex(0xFFF0B0), GPalette.gold, GPalette.hex(0xF0A800)],
                                  startPoint: .top, endPoint: .bottom)
        case .rainbow:
            return LinearGradient(colors: Self.spectrum, startPoint: .leading, endPoint: .trailing)
        }
    }

    /// 제목 둘레 빛 · 글자 아래 테.
    var titleGlow: Color {
        switch self {
        case .gold: return GPalette.gold.opacity(0.65)
        case .rainbow: return GPalette.hex(0xE6A6FF, 0.65)
        }
    }

    var titleEdge: Color {
        switch self {
        case .gold: return GPalette.hex(0x7A4D00, 0.35)
        case .rainbow: return GPalette.hex(0x3B2370, 0.45)
        }
    }
}
