import Foundation

// MARK: - 리밋 **두 열**의 색·글자·채움 산식 (v0.3.46 — 폰 카드 + 위젯이 한 벌로 쓴다)
//
// ## 왜 여기인가
// 승인된 새 문법은 한 제공자를 **한 줄**에 세우고 5시간 창과 주간 창을 그 줄 안에 **나란히** 놓는다
// (2026-10-07 사용자 승인). 짝을 알려 주는 단서를 **셋** 둔다 — 열 머리 글자 · 색 · 좌우 자리. 그 색과
// 글자가 여기 있다.
//
// 리밋을 그리는 두 프로세스(폰 앱 `CheckMobileKit` · 위젯 확장 `CheckWidgetsKit`)는 **서로를 링크하지
// 않는다**(Package.swift). 둘이 공통으로 보는 모듈은 `CheckMobileShared` 뿐이고, 색 숫자를 모듈마다 적으면
// 한쪽만 고쳐지는 날 같은 데이터가 두 화면에서 다른 색으로 보인다(이 기능이 몇 번이고 밟은 함정 —
// '세 화면이 다른 말을 하는 자리'). `AILimitGhostRow`·`AILimitFloorFill` 과 **같은 이유로 같은 자리**다.
//
// 맥 앱 타깃은 이 모듈을 링크하지 않는다(맥·폰·위젯이 다 보는 모듈은 `CheckCore` 하나뿐이다). 그래서 맥은
// `AILimitMacPalette` 에 같은 16진수를 따로 적고, 두 표가 갈리지 않는지는 **소스 계약 테스트**가 되묻는다.
//
// ## 색이 뜻하는 것은 **창 종류**다 — 제공자가 아니다
// 제공자는 마크(그림)가 가르고, 색은 5시간 ↔ 주간을 가른다. 그래서 이름이 `fiveHourBar` 이지
// `claudeBar` 가 아니다.

/// 두 열을 가르는 색 숫자. **어두운 쪽이 승인본 16진수 그대로**이고(맥 팝오버는 어두운 한 벌뿐이다),
/// 밝은 쪽은 폰·위젯이 라이트 모드를 지원하므로 같은 색상(hue)에서 명도만 뒤집어 맞춘 값이다.
///
/// ★ 라이트 값을 승인본 그대로 쓰면 안 된다: `#30343B` 트랙은 흰 카드 위에서 **검은 막대**로 보이고
/// (= 100% 찬 바로 읽힌다), `#7FA8F5` 열 머리는 흰 바탕에서 3.2:1 로 읽히지 않는다(실측 계산).
/// 어느 쪽이 승인본인지를 주석이 아니라 **값 이름**으로 못 박아 둔다(`darkIsApproved`).
public enum AILimitColumnPalette {
    public struct Pair: Equatable, Sendable {
        /// 라이트 모드(흰 카드) 값.
        public let light: UInt32
        /// 다크 모드 값 — 5시간/주간/트랙/구분선/없음은 **승인본 16진수 그대로**다.
        public let dark: UInt32

        public init(light: UInt32, dark: UInt32) {
            self.light = light
            self.dark = dark
        }
    }

    /// 5시간 열 **바** — 승인본 `#5B8DEF`.
    public static let fiveHourBar = Pair(light: 0x3B_7B_E8, dark: 0x5B_8D_EF)
    /// 5시간 열 **머리 글자** — 승인본 `#7FA8F5`. 바와 같은 계열이어야 짝이 보인다(머리와 바의 색을 따로 고르지 마라).
    /// 다크에서는 바보다 **밝고**, 라이트에서는 바보다 **어둡다** — 작은 글자가 바와 같은 명도면 배경에 묻힌다.
    public static let fiveHourHeader = Pair(light: 0x1F_62_C9, dark: 0x7F_A8_F5)
    /// 주간 열 **바** — 승인본 `#8A76E0`.
    public static let weeklyBar = Pair(light: 0x7A_5F_D6, dark: 0x8A_76_E0)
    /// 주간 열 **머리 글자** — 승인본 `#A796E8`.
    public static let weeklyHeader = Pair(light: 0x5A_42_B8, dark: 0xA7_96_E8)
    /// 값이 **있는** 칸의 빈 트랙 — 승인본 `#30343B`.
    public static let emptyTrack = Pair(light: 0xE3_E5_EA, dark: 0x30_34_3B)
    /// 그 창이 **없는** 칸의 트랙 — 승인본 `#22262C`. 빈 트랙보다 **바탕에 더 가깝다**(= 더 조용하다).
    /// 빈 트랙과 같은 밝기면 "0% 라 비었다"로 읽힌다.
    ///
    /// ★ 승인본은 **어두운 한 벌**(맥 팝오버 · 위젯 바탕 `#232633`)을 전제로 고른 값이다. 폰 카드 바탕
    /// (`MobileTheme.surface` 다크 `#2B2E3D`)은 그보다 한 단 밝아 같은 값이 '조금 어두운 홈'으로 보인다 —
    /// 그래도 **채움으로는 읽히지 않고**(바보다 훨씬 조용하다) 같은 칸의 `없음` 글자가 사실을 말한다.
    /// 세 화면이 한 표를 쓰는 편이 바탕마다 값을 갈라 두는 것보다 안전하다(테스트가 두 성질을 다 잰다).
    public static let absentTrack = Pair(light: 0xF1_F2_F5, dark: 0x22_26_2C)
    /// 제공자 사이 구분선 — 승인본 `#2C3037`.
    public static let separator = Pair(light: 0xE2_E3_E7, dark: 0x2C_30_37)
    /// 그 창이 **없는** 칸의 글자 — 승인본 `#595E67`.
    ///
    /// ★ 이 칸은 줄에서 **가장 조용하다**(실측 대비 2.1:1 수준). 승인된 선택이고 근거가 있다: `없음` 은 값이
    /// 아니라 '값이 없다는 사실'이라 숫자보다 눈에 먼저 들어오면 안 된다. 그리고 그 사실은 글자 하나로만
    /// 말하지 않는다 — 같은 칸의 **트랙이 더 어둡고**(`absentTrack`) 바에 채움이 **아예 없다**.
    /// 글자를 올리고 싶으면 승인본을 먼저 고쳐라(`AILimitMacPalette.absentText` 와 짝이다).
    public static let absentText = Pair(light: 0x9B_A1_AC, dark: 0x59_5E_67)

    /// 그 열의 바 색.
    public static func bar(_ window: AILimitColumnWindow) -> Pair {
        switch window {
        case .fiveHour: return fiveHourBar
        case .weekly: return weeklyBar
        }
    }

    /// 그 열의 **머리 글자** 색.
    public static func header(_ window: AILimitColumnWindow) -> Pair {
        switch window {
        case .fiveHour: return fiveHourHeader
        case .weekly: return weeklyHeader
        }
    }

    /// 0xRRGGBB → (r, g, b) 0…1.
    public static func components(_ hex: UInt32) -> (r: Double, g: Double, b: Double) {
        (Double((hex >> 16) & 0xFF) / 255, Double((hex >> 8) & 0xFF) / 255, Double(hex & 0xFF) / 255)
    }

    /// 코어 열거값(`AILimitWindow`)의 **rawValue** 로 열을 고른다.
    ///
    /// 왜 문자열로 받나: 이 모듈은 `CheckCore` 를 링크하지 않는다(`CheckMobileShared` 는 폰·위젯의 *자리*
    /// 모듈이고, 의존을 더하면 위젯 확장의 링크 그래프가 커진다). 그렇다고 모듈마다 `switch window` 를 적으면
    /// **한쪽에서 파랑과 보라가 뒤집힌** 채 컴파일이 통과한다(두 벌로 적은 표가 갈리는 바로 그 함정).
    /// rawValue 는 서버 컬럼 값이라 두 모듈이 같은 글자를 들고 있고, 옮기는 자리가 **여기 한 곳**이다.
    public static func column(windowRawValue raw: String) -> AILimitColumnWindow {
        raw == AILimitColumnWindow.weekly.rawValue ? .weekly : .fiveHour
    }
}

/// 두 열이 어느 창인가. rawValue 는 **`AILimitWindow` 와 같은 글자**(= 서버 컬럼 값)다 — 그래야
/// `column(windowRawValue:)` 가 코어 열거값을 글자로 받아 옮길 수 있다.
///
/// ★ 창이 **셋**이 되는 날: 이 열거값을 늘리지 않으면 새 창이 조용히 5시간 열(파랑)로 떨어진다.
/// 두 열거값의 칸 수가 같은지는 테스트가 되묻는다(`AILimitWindow.allCases.count`).
public enum AILimitColumnWindow: String, CaseIterable, Sendable {
    case fiveHour = "five_hour"
    case weekly
}

/// 창이 **없는** 칸의 글자.
///
/// ★ `—` 를 쓰지 않는다. 그 글자는 코어 규칙이 '판정 불가(= 못 읽었다)'로 못 박았다
/// (`AILimitFreshnessRule.unknownValueText`). 5시간 창이 **아예 없는** 계정(주간만 오는 요금제 ·
/// 안티그래비티 실측)에 그 글자를 쓰면 "이 계정엔 그 창이 없다"를 "읽기 실패"로 말하는 셈이고,
/// 사용자는 고장으로 읽는다. 맥 `AILimitCardModel.absentValueText` 와 **같은 글자여야 한다**(소스 계약).
public enum AILimitColumnText {
    public static let absentValueText = "없음"
}

/// **얼마나 찼는가**(사용량 단계). 바가 열 색을 쥐었으므로 이 단계는 **숫자 글자**가 말한다.
///
/// ## 왜 바가 아니라 글자인가 (v0.3.46)
/// v0.3.45 는 바 채움을 사용량 단계로 칠했다. 승인된 새 문법은 바 색을 **열 구분**에 쓴다(5시간 파랑 ·
/// 주간 보라) — 거기에 단계 색까지 얹으면 "파란 바"가 두 뜻을 갖는다. 그렇다고 90% 경고를 통째로 버릴 수는
/// 없어서(그게 이 카드를 보는 이유다) 단계는 숫자 글자로 옮겼다. 평온 단계가 강조색이 아니라 **본문색**인
/// 까닭이 이것이다 — 파란 글자는 5시간 열 색과 겹쳐 읽힌다.
///
/// ## ★ 글자가 쓰는 수로 가른다
/// 입력이 **반올림한 정수 퍼센트**인 까닭: 89.5% 는 규칙이 `90%` 라고 **적는다**
/// (`AILimitFreshnessRule.wholePercent`). 날것 double 로 90 을 가르면 그 값에서 글자는 `90%` 인데 색은
/// 평온해, 같은 자리에서 글자와 색이 다른 단계를 말한다(맥이 2026-10-07 에 밟은 결함).
/// 반올림 자체는 `CheckCore` 에 있고 이 모듈은 코어를 링크하지 않으므로(머리말), 호출부가 반올림한 수를 준다.
public enum AILimitUsageStage: String, Equatable, Sendable {
    /// 70% 미만 — 본문색.
    case calm
    /// 70% 이상 — 주의색.
    case warn
    /// 90% 이상 — 위험색.
    case danger

    /// 색이 갈리는 경계. 이 저장소의 주간 목표 게이지 관례(working/pending/danger)를 그대로 쓴다.
    /// 맥 `AILimitUsageTint` 가 같은 수를 따로 적는다(맥은 이 모듈을 링크하지 않는다 — 소스 계약이 대조한다).
    public static let warnPercent = 70
    public static let dangerPercent = 90

    /// 단계. nil(판정 불가 · 창 없음)은 `calm` 이다 — **모르는 값에 경고를 붙이지 않는다**.
    /// 그 칸의 글자는 이미 `—` 나 `없음` 이라 숫자로 읽히지 않고, 거기에 빨강을 칠하면 "못 읽었다"가
    /// "위험하다"로 읽힌다.
    public static func stage(wholePercent: Int?) -> AILimitUsageStage {
        guard let wholePercent else { return .calm }
        if wholePercent >= dangerPercent { return .danger }
        if wholePercent >= warnPercent { return .warn }
        return .calm
    }
}

/// 바 채움 폭 — **폰·위젯·맥이 같은 산식을 쓴다**(순수 함수 · 테스트가 직접 부른다).
public enum AILimitBarFill {
    /// 0 보다 큰 사용량이 **보이는 길이**를 갖도록 하는 최소 채움. 바 폭에 비례한다.
    ///
    /// 왜 비례인가: 맥 팝오버의 바는 69pt 고 폰 카드의 바는 32pt 다(이름 칸을 두느라 좁다). 최소 채움을
    /// 고정 pt 로 두면 좁은 바에서 1% 와 18% 가 같은 길이가 된다 — 바가 거짓말을 한다. 8% 는 맥의
    /// 69pt × 8% ≈ 5.5pt(= 맥이 손으로 고른 6pt)와 같은 눈금이고, 어느 폭에서나 "조금 썼다"로 읽힌다.
    public static func minimumFill(barWidth: Double) -> Double {
        max(2, barWidth * 0.08)
    }

    /// 채움 폭. 0% 는 **0**(채움 없음), 0 보다 크면 최소 채움 이상, 100% 는 바 전체.
    /// `percent` 가 nil(판정 불가 · 창 없음)이면 0 — 트랙만 남는다(0% 로 "안 썼다"고 말하지 않는다).
    public static func width(barWidth: Double, percent: Double?) -> Double {
        guard barWidth > 0, let percent else { return 0 }
        let clamped = min(100, max(0, percent))
        guard clamped > 0 else { return 0 }
        return min(barWidth, max(minimumFill(barWidth: barWidth), barWidth * clamped / 100))
    }
}
