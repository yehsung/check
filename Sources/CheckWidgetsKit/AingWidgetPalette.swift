import Foundation

/// 위젯 색 숫자(플랫폼 무관). 위젯 모듈은 앱 모듈(CheckMobileKit)을 링크하지 않으므로 앱 토큰(`MobileThemePalette`)의 **같은 값**을
/// 여기 적는다 — `NowWidgetTests` · `WidgetDesignTests` 가 두 표가 글자까지 같은지 잰다(한쪽만 바뀌면 빨강).
///
/// w15 기반: 방향 B 토큰으로 옮겼다. 위젯 바탕은 `widgetBackground`(흰색 / 남색 #232633), 반투명 토큰(글자 2·3단 · 채움 · 구분선)은
/// 그 바탕 위에 겹친 불투명 값이다. **원색(풀 컬러) 렌더링 전용이다** — 틴트·투명(`widgetRenderingMode == .accented`)에서는 시스템이
/// 색을 버리고 불투명도만 남기므로(불투명한 회색 트랙 = 꽉 찬 흰색, 실측 w11 today-small-tint) 화면이 `AingWidgetPalette.Accented`
/// 의 불투명도로 따로 그린다.
package enum AingWidgetPalette {
    package struct Pair: Equatable, Sendable {
        package let light: UInt32
        package let dark: UInt32
    }

    /// = `MobileThemePalette.widgetBackground`.
    package static let background = Pair(light: 0xFFFFFF, dark: 0x232633)
    /// = `fill` 을 위젯 바탕에 겹친 값(칩 바탕).
    package static let cardElevated = Pair(light: 0xEFEFF0, dark: 0x373A45)
    /// = `label` 을 위젯 바탕에 겹친 값.
    package static let primaryText = Pair(light: 0x0B0B10, dark: 0xF4F4F5)
    /// = `label2` 를 위젯 바탕에 겹친 값.
    package static let secondaryText = Pair(light: 0x6F6F74, dark: 0xA3A5AF)
    /// = `label3Text`(끝난 할 일 글자) 를 위젯 바탕에 겹친 값.
    package static let tertiaryText = Pair(light: 0x717176, dark: 0x9395A0)
    /// = `label3`(빈 체크 원 테두리 — 기호·선 전용) 을 위젯 바탕에 겹친 값.
    package static let tertiarySymbol = Pair(light: 0xBDBDBF, dark: 0x5F616D)
    /// = `separator` 를 위젯 바탕에 겹친 값.
    package static let separator = Pair(light: 0xDEDEDF, dark: 0x393C47)
    /// = `surface2`(빈 상태 초상 받침).
    package static let surface2 = Pair(light: 0xF4F4F8, dark: 0x353848)
    package static let working = Pair(light: 0x127A51, dark: 0x59E0A1)
    /// = `workingDot`(점 · 링 · 달성 막대).
    package static let workingDot = Pair(light: 0x2FC47E, dark: 0x59E0A1)
    package static let offWork = Pair(light: 0x666E7D, dark: 0x94ADCC)
    package static let offWorkDot = Pair(light: 0xA7B1C0, dark: 0x94ADCC)
    package static let pending = Pair(light: 0x9A5B00, dark: 0xFFB854)
    package static let pendingDot = Pair(light: 0xFFA826, dark: 0xFFB854)
    package static let accent = Pair(light: 0x1864CF, dark: 0x54ABFF)
    /// = `accentFill`(체크된 원 바탕 — 흰 체크).
    package static let accentFill = Pair(light: 0x1864CF, dark: 0x2A74DE)
    /// = `fill` 을 위젯 바탕에 겹친 값(막대 트랙).
    package static let track = Pair(light: 0xEFEFF0, dark: 0x373A45)

    /// 초상 받침 틴트 불투명도(= `workingTint` · `pendingTint` 의 알파). 근무 안 함 받침은 `cardElevated`.
    package static let workingTintOpacity = 0.14
    package static let pendingTintOpacity = 0.16

    /// 이니셜 원 글자 색(원 바탕은 이 색의 `avatarTintOpacity`) — `MobileThemePalette.avatarInks` 와 같은 순서·값.
    package static let avatarInks: [Pair] = [
        Pair(light: 0x365AC0, dark: 0xA0BAFF),
        Pair(light: 0x176C67, dark: 0x5DD3CB),
        Pair(light: 0x8E510C, dark: 0xF5B36A),
        Pair(light: 0xA73658, dark: 0xF6A0B5),
        Pair(light: 0x6F46C1, dark: 0xC5ABF4),
        Pair(light: 0x206D41, dark: 0x7ED9A2),
    ]
    package static let avatarTintOpacity = (light: 0.15, dark: 0.16)

    /// 틴트·투명 렌더링의 불투명도(시안 `.b-is-tint` · `.b-is-clear`). 색은 시스템이 정한다 — 여기는 위계만.
    ///
    /// **글자는 불투명도로 위계를 나누지 않는다**(w15 검증 낮음 1): 시안 62% → 86% 로 올리고도 옅은 배경화면 위 투명 모드에서
    /// 보조 글자가 1.84~1.91:1 이었다(실측 '우리 팀 3 / 다른 팀 3' 1.84 · '2분 전' 1.91 · '남은 4개 · 외 2개' 1.87).
    /// 투명·틴트에서 최종 색은 시스템이 정하므로 앱이 올릴 수 있는 것은 불투명도뿐이다 — 글자는 전부 1.0 으로 올리고
    /// 위계는 **글자 크기·굵기**가 말한다(원색 모드는 그대로 색으로 나눈다). 끝난 할 일처럼 흐림이 곧 뜻인 글자만 한 단계 낮춘다.
    /// 칩·받침(`fill`)은 글자 뒤를 받쳐 주도록 함께 올렸다.
    package enum Accented {
        package static let secondaryText = 1.0
        /// 끝난 할 일(취소선과 함께 흐림이 뜻) — 글자 중 유일하게 낮춘 값.
        package static let tertiaryText = 0.82
        package static let symbol = 0.62
        /// 막대 트랙(시안 "트랙 35%"). 채운 쪽(1.0)과 갈려야 하므로 올리지 않는다.
        package static let track = 0.35
        package static let fill = 0.32
        package static let separator = 0.3
    }

    /// 0xRRGGBB → (r, g, b) 0…1.
    package static func components(_ hex: UInt32) -> (r: Double, g: Double, b: Double) {
        (Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
    }
}
