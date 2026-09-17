import Foundation

/// 폰 색 토큰의 **숫자**(플랫폼 무관 — macOS `swift test` 가 대비를 잰다). 색 객체는 iOS 층 `MobileTheme` 이 이 값으로 만든다.
///
/// 원본은 재디자인 방향 B 토큰 표(`b2.html` 의 `:root --b-*` 와 다크 `.b-dark`) — **한 줄 = 토큰 하나(라이트/다크 쌍)**.
/// 다크는 맥 `CheckTheme` 남색 가족(바탕 #1A1C26 · 카드 #2B2E3D)이고 뜻 색은 맥 원색 숫자 그대로다(`BaseThemeTests` 가 소스 대조).
///
/// 시안과 다른 값(전부 "모든 글자 4.5:1" 규칙 때문 — 시안 라이트는 흰 카드에서만 쟀고 #F2F2F7 바탕·틴트 칩 위에서 4.0~4.4 였다):
/// - 라이트 뜻 색 한 단계 진하게: accent #1A6BDB→#1864CF · working #15875A→#127A51 · pending #A15F00→#9A5B00 ·
///   danger #D33A3F→#C83238 · offWork #6E7787→#666E7D (바탕 위·틴트 칩 위 4.5:1).
/// - 라이트 label2 68%→74%(바탕 위 4.7:1). 3단 글자는 두 토큰으로 가른다: `label3`(34% — 선·기호·빈 체크 원 전용, 글자 금지)과
///   `label3Text`(라이트 73% · 다크 56% — 자리표시·끝난 할 일·모자란 가격 글자). 다크 56% 는 시안의 다크 보정값 그대로다.
///   라이트에서는 4.5:1 을 지키느라 label2(74%)와 거의 같다 — 끝남·모자람은 색이 아니라 취소선·흐린 보석이 말한다.
/// - 다크 dangerTint 14%→8%(틴트 위 빨강 글자 4.5:1). 라이트 이니셜 원 글자는 틴트 위 4.5:1 이 되게 한 단계 진하게.
package enum MobileThemePalette {
    /// 한 색(0…1) + 불투명도. 불투명도가 1 이 아니면 색 객체도 같은 불투명도로 만들어 **아래 면에 겹쳐** 그린다(CSS rgba 와 같다).
    package struct RGB: Equatable, Sendable {
        package let r: Double
        package let g: Double
        package let b: Double
        package let alpha: Double

        package init(_ r: Double, _ g: Double, _ b: Double, alpha: Double = 1) {
            self.r = r
            self.g = g
            self.b = b
            self.alpha = alpha
        }

        package init(hex: UInt32, alpha: Double = 1) {
            self.init(Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255, alpha: alpha)
        }

        /// 0…255 정수 채널(시안 rgba(60,60,67,.74) 를 그대로 옮기기 위한 모양).
        package init(r255 r: Int, g255 g: Int, b255 b: Int, alpha: Double = 1) {
            self.init(Double(r) / 255, Double(g) / 255, Double(b) / 255, alpha: alpha)
        }

        /// 불투명한 `backdrop` 위에 겹친 결과(불투명).
        package func composited(over backdrop: RGB) -> RGB {
            let a = alpha
            return RGB(r * a + backdrop.r * (1 - a), g * a + backdrop.g * (1 - a), b * a + backdrop.b * (1 - a))
        }

        /// 같은 색, 다른 불투명도.
        package func opacity(_ value: Double) -> RGB {
            RGB(r, g, b, alpha: value)
        }

        /// WCAG 상대 휘도(불투명 색 기준 — 반투명이면 먼저 `composited(over:)`).
        package var relativeLuminance: Double {
            func channel(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
            return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
        }

        /// WCAG 대비(1…21). 반투명 색은 상대 면 위에 겹친 뒤 잰다.
        package func contrast(against other: RGB) -> Double {
            let fg = alpha < 1 ? composited(over: other) : self
            let a = fg.relativeLuminance, b = other.relativeLuminance
            return (max(a, b) + 0.05) / (min(a, b) + 0.05)
        }

        /// 0xRRGGBB(반올림). 위젯 표 대조용.
        package var hex: UInt32 {
            func byte(_ v: Double) -> UInt32 { UInt32(max(0, min(255, (v * 255).rounded()))) }
            return (byte(r) << 16) | (byte(g) << 8) | byte(b)
        }
    }

    /// 한 토큰의 라이트·다크 값.
    package struct Pair: Equatable, Sendable {
        package let light: RGB
        package let dark: RGB

        package init(light: RGB, dark: RGB) {
            self.light = light
            self.dark = dark
        }

        /// 같은 값(라이트·다크 구분 없음 — 메달·나무판 같은 재질).
        package init(both: RGB) {
            self.init(light: both, dark: both)
        }
    }

    // MARK: 바탕·표면 (--b-bg · surface · surface-2 · fill · fill-2 · sep · glass · glass-line · bubble-in)

    /// 화면 바탕(systemGroupedBackground / 맥 background).
    package static let background = Pair(light: RGB(hex: 0xF2F2F7), dark: RGB(hex: 0x1A1C26))
    /// 인셋 그룹 카드(맥 panel #2B2E3D).
    package static let surface = Pair(light: RGB(hex: 0xFFFFFF), dark: RGB(hex: 0x2B2E3D))
    /// 카드 안 2차 상자(캐릭터 그림 받침 · 오목 판 둘레).
    package static let surface2 = Pair(light: RGB(hex: 0xF4F4F8), dark: RGB(hex: 0x353848))
    /// 칩·세그먼트·회색 버튼·막대 트랙·입력칸 채움.
    package static let fill = Pair(light: RGB(r255: 118, g255: 118, b255: 128, alpha: 0.12), dark: RGB(hex: 0xFFFFFF, alpha: 0.09))
    /// 더 옅은 채움(다크 비활성 버튼 바탕 · 내 행 안 센터 칩).
    package static let fill2 = Pair(light: RGB(r255: 118, g255: 118, b255: 128, alpha: 0.07), dark: RGB(hex: 0xFFFFFF, alpha: 0.05))
    /// 0.5pt 구분선.
    package static let separator = Pair(light: RGB(r255: 60, g255: 60, b255: 67, alpha: 0.17), dark: RGB(hex: 0xFFFFFF, alpha: 0.10))
    /// 유리(원형 도구 버튼 · 알약 · 하단 막대 · 대화 시트). 다크는 카드보다 한 단계 밝게(목록 위에서 사라지지 않게).
    package static let glass = Pair(light: RGB(hex: 0xFFFFFF, alpha: 0.74), dark: RGB(r255: 51, g255: 54, b255: 74, alpha: 0.82))
    package static let glassLine = Pair(light: RGB(hex: 0x000000, alpha: 0.07), dark: RGB(hex: 0xFFFFFF, alpha: 0.14))
    /// 받은 말풍선.
    package static let bubbleIn = Pair(light: RGB(hex: 0xE9E9EE), dark: RGB(hex: 0x343747))

    // MARK: 글자 (--b-label · -2 · -3)

    package static let label = Pair(light: RGB(hex: 0x0B0B10), dark: RGB(hex: 0xFFFFFF, alpha: 0.95))
    package static let label2 = Pair(light: RGB(r255: 60, g255: 60, b255: 67, alpha: 0.74), dark: RGB(r255: 235, g255: 236, b255: 245, alpha: 0.64))
    /// 3단 **기호·선**(빈 체크 원 테두리 · 줄 끝 화살표 · 끌개). 글자에는 쓰지 않는다(라이트 1.9:1).
    package static let label3 = Pair(light: RGB(r255: 60, g255: 60, b255: 67, alpha: 0.34), dark: RGB(r255: 235, g255: 236, b255: 245, alpha: 0.30))
    /// 3단 **글자**(자리표시 · 끝난 할 일 · 모자란 가격). 카드·바탕 위 4.5:1.
    package static let label3Text = Pair(light: RGB(r255: 60, g255: 60, b255: 67, alpha: 0.73), dark: RGB(r255: 235, g255: 236, b255: 245, alpha: 0.56))

    // MARK: 뜻 색 — 이 뜻으로만 쓴다

    /// 선택 · 진행(미달) · 링크 · 주요 동작의 글자와 기호.
    package static let accent = Pair(light: RGB(hex: 0x1864CF), dark: RGB(0.33, 0.67, 1.0))
    /// 채운 버튼 · 보낸 말풍선 · 체크된 원 바탕(위 글자는 흰색 `onAccentFill`).
    package static let accentFill = Pair(light: RGB(hex: 0x1864CF), dark: RGB(hex: 0x2A74DE))
    /// 틴트 버튼 · 칩 · 내 행 바탕.
    package static let accentTint = Pair(light: RGB(hex: 0x1864CF, alpha: 0.10), dark: RGB(0.33, 0.67, 1.0, alpha: 0.11))
    /// 루비 잔량 칩 테두리 · 테두리형 칩.
    package static let accentLine = Pair(light: RGB(hex: 0x1864CF, alpha: 0.30), dark: RGB(0.33, 0.67, 1.0, alpha: 0.38))
    /// accentFill 위 글자.
    package static let onAccentFill = Pair(both: RGB(hex: 0xFFFFFF))
    /// 다크 탭 막대에서 선택된 탭 글자(알약 위 accent 는 3.9:1 — 같은 가족 한 단계 밝게). 라이트는 accent.
    package static let tabSelected = Pair(light: RGB(hex: 0x1864CF), dark: RGB(hex: 0x7DC0FF))

    /// 근무 중 · 달성 **글자**.
    package static let working = Pair(light: RGB(hex: 0x127A51), dark: RGB(0.35, 0.88, 0.63))
    /// 근무 중 점 · 링 · 발광 · 잔디 가장 진한 칸.
    package static let workingDot = Pair(light: RGB(hex: 0x2FC47E), dark: RGB(0.35, 0.88, 0.63))
    package static let workingTint = Pair(light: RGB(hex: 0x2FC47E, alpha: 0.14), dark: RGB(0.35, 0.88, 0.63, alpha: 0.14))
    /// 근무 안 함 글자.
    package static let offWork = Pair(light: RGB(hex: 0x666E7D), dark: RGB(0.58, 0.68, 0.80))
    package static let offWorkDot = Pair(light: RGB(hex: 0xA7B1C0), dark: RGB(0.58, 0.68, 0.80))
    /// 연결 끊김 · 대기 글자.
    package static let pending = Pair(light: RGB(hex: 0x9A5B00), dark: RGB(1.0, 0.72, 0.33))
    package static let pendingDot = Pair(light: RGB(hex: 0xFFA826), dark: RGB(1.0, 0.72, 0.33))
    package static let pendingTint = Pair(light: RGB(hex: 0xFFA826, alpha: 0.16), dark: RGB(1.0, 0.72, 0.33, alpha: 0.16))
    /// 위험 · 기권 · 삭제.
    package static let danger = Pair(light: RGB(hex: 0xC83238), dark: RGB(1.0, 0.45, 0.46))
    package static let dangerTint = Pair(light: RGB(hex: 0xC83238, alpha: 0.10), dark: RGB(1.0, 0.45, 0.46, alpha: 0.08))
    /// AI 토큰 전용.
    package static let aiToken = Pair(light: RGB(hex: 0x7A4FE0), dark: RGB(0.72, 0.55, 1.0))
    /// 시스템 알림 배지(흰 글자 — 대비 예외, 시스템과 같은 빨강).
    package static let badge = Pair(both: RGB(hex: 0xFF3B30))

    // MARK: 순위 메달(원 바탕 + 짙은 글자 — 원 안 숫자는 늘 짙다)

    package static let gold = Pair(light: RGB(hex: 0xF5B700), dark: RGB(hex: 0xFFD24A))
    package static let silver = Pair(light: RGB(hex: 0xAAB3C0), dark: RGB(hex: 0xD6DCE6))
    package static let bronze = Pair(light: RGB(hex: 0xD38445), dark: RGB(hex: 0xE0955A))
    package static let goldInk = Pair(both: RGB(hex: 0x4A3500))
    package static let silverInk = Pair(both: RGB(hex: 0x2B313A))
    package static let bronzeInk = Pair(both: RGB(hex: 0x3F1E05))
    /// 왕관 원(어제 1등) 기호 색.
    package static let crownInk = Pair(both: RGB(hex: 0x5A4100))

    // MARK: 그라디언트 — 두 곳(+ 나무판 재질)만

    /// '우리 팀' 게이지 전용(맥 gaugeGradient).
    package static let gaugeStops = [RGB(hex: 0x59E0A1), RGB(hex: 0x54ABFF)]
    /// 로그인 버튼 전용(맥 startGradient).
    package static let startStops = [RGB(hex: 0x52D994), RGB(hex: 0x2EAD9E)]
    /// 오목 나무판(외관과 무관).
    package static let woodStops = [RGB(hex: 0xE0BA7D), RGB(hex: 0xC99E61)]
    package static let brandNavy = RGB(hex: 0x1A1A2E)
    package static let brandLavender = RGB(hex: 0x9979E6)

    // MARK: 이니셜 원 — 맥 해시 팔레트 6색의 틴트형(틴트 원 + 진한 글자)

    /// 글자 색(원 바탕은 이 색의 `avatarTintOpacity`). 순서는 맥 `CheckTheme.avatarPalette` 와 같다(파랑 · 청록 · 주황 · 분홍 · 보라 · 초록).
    package static let avatarInks: [Pair] = [
        Pair(light: RGB(hex: 0x365AC0), dark: RGB(hex: 0xA0BAFF)),
        Pair(light: RGB(hex: 0x176C67), dark: RGB(hex: 0x5DD3CB)),
        Pair(light: RGB(hex: 0x8E510C), dark: RGB(hex: 0xF5B36A)),
        Pair(light: RGB(hex: 0xA73658), dark: RGB(hex: 0xF6A0B5)),
        Pair(light: RGB(hex: 0x6F46C1), dark: RGB(hex: 0xC5ABF4)),
        Pair(light: RGB(hex: 0x206D41), dark: RGB(hex: 0x7ED9A2)),
    ]
    package static let avatarTintOpacity = (light: 0.15, dark: 0.16)

    /// 이름 → 팔레트 칸(맥 `CheckTheme.avatarColor(for:)` 와 같은 해시: 유니코드 스칼라 합 mod 6).
    package static func avatarIndex(for seed: String) -> Int {
        let sum = seed.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return abs(sum) % avatarInks.count
    }

    // MARK: 위젯

    /// 위젯 바탕(흰색 / 남색 #232633 — 앱 다크와 같은 가족).
    package static let widgetBackground = Pair(light: RGB(hex: 0xFFFFFF), dark: RGB(hex: 0x232633))

    // MARK: 대비 검사 대상

    /// 글자로 쓰이는 토큰 — 라이트·다크 모두 **카드와 바탕 위** 4.5:1(`BaseThemeTests`).
    package static let textTokens: [(name: String, pair: Pair)] = [
        ("label", label), ("label2", label2), ("label3Text", label3Text),
        ("accent", accent), ("working", working), ("offWork", offWork), ("pending", pending),
        ("danger", danger), ("aiToken", aiToken),
    ]

    /// 틴트 바탕 위 같은 가족 글자(칩 · 틴트 버튼) — 카드 위에 겹친 틴트에서 4.5:1.
    package static let tintedTextPairs: [(name: String, text: Pair, tint: Pair)] = [
        ("accent/accentTint", accent, accentTint),
        ("working/workingTint", working, workingTint),
        ("pending/pendingTint", pending, pendingTint),
        ("danger/dangerTint", danger, dangerTint),
    ]
}
