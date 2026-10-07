import CheckCore
import SwiftUI

// MARK: - AI 리밋: 팝오버 카드 (v0.3.46 — 별도 창을 접고 팝오버 안으로)
//
// ## 왜 창을 없앴나 (2026-10-07 사용자 지시)
// v0.3.45 는 팝오버에 한 줄 요약(`AI 리밋 26% · 0% 자세히 ›`)만 두고 상세는 **별도 창**이 받았다.
// 사용자가 그 두 걸음을 싫어했다: *"메인 화면 자체에 다 뜨게끔. 세로로 길어지더라도. 다만 너무 길어지진 않게."*
// 그래서 창(`CheckAILimitsWindow.swift`)을 통째로 지우고, 그 창이 말하던 것을 팝오버 카드 하나가 말한다.
// 따라간 자리: `CheckApp` 배선 · `MiniGameSpaceKey.standaloneWindowIDs`(넷 → 셋) · 툴팁 레이어 자리 수(일곱 → 여섯).
//
// ## 승인된 문법 — 한 제공자 = 한 줄, 5시간과 주간이 **나란히**
// 세로로 쌓지 않는다. 쌓으면 제공자 셋에 줄이 여섯이 되어 팝오버가 상한(700pt)을 향해 자라고,
// 무엇보다 "지금 당장 막히나(5시간) · 이번 주가 위험한가(주간)"는 **나란히 놓고 견주는** 질문이다.
//
// 짝을 알려 주는 단서를 **셋** 둔다 — 열 머리 글자 · 색 · 좌우 자리. 하나로는 부족한 이유가 각각 있다:
//   · 색만으로 가르면 위젯 틴트 모드처럼 색을 버리는 표면에서 두 숫자가 구별되지 않는다
//     (`AIProviderLogo.swift` 머리말과 같은 근거 — 이 카드는 맥 전용이지만 규약을 갈라 두지 않는다).
//   · 자리만으로 가르면 열 머리를 한 번만 적는 이 레이아웃에서 스크롤·호버 중에 기준을 잃는다.
//   · 글자만으로 가르면(열마다 `5시간 88%`) 폭이 모자라 말줄임이 나고, 말줄임은 **숫자 자릿수 오독**이다.
//
// ## 이름 글자가 없다 — 마크만
// 카드 안쪽은 292pt 고정이다(본문 열 316 − 카드 좌우 여백 12×2). 여기에 제공자 이름을 넣으면 바가 각 60pt 로
// 줄어 8% 와 0% 가 눈으로 안 갈린다(실측). 그래서 왼쪽은 **마크 20pt 하나**고, 이름·요금제·리셋 시각·관측 나이는
// **호버 툴팁**으로 갚는다. 시스템 툴팁은 쓸 수 없다 — 이 저장소 실측으로 2/6 확률 · 1.7초 지연이다
// (`CheckTooltip.swift` 머리말 — v0.3.25 가 자체 말풍선을 만든 이유). 그래서 `.checkTooltip` 이다.
// 폰 카드(폭 ~361pt)와 위젯 미디움은 자리가 남아 이름을 쓴다 — 세 화면이 **같은 문법에 다른 예산**인 것이다.
//
// ## 숫자·캡션·표시여부를 뷰가 계산하지 않는다
// 전부 `AILimitFreshnessRule` 에서 받는다. 그 규칙 하나가 "27%" 와 "27% 이상" 과 "0%" 와 "—" 를 가르고,
// 캡션의 나이 문구도 거기서 나온다. 뷰가 반올림을 한 번만 더 하면 그 순간 규칙이 둘이 되고,
// 이 저장소는 **스토어만 고치고 뷰는 그대로여서 테스트가 초록인 채 화면이 안 바뀌는** 사고를 이미 겪었다
// (관례: '클라 게이트는 짝으로 있다').
//
// ## ★ `—` 와 `없음` 은 **다른 말**이다
// `—` 는 규칙이 "판정 불가(= 못 읽었다)"로 못 박은 글자다(`AILimitFreshnessRule.unknownValueText`).
// 5시간 창이 **아예 없는** 계정(주간만 오는 요금제 · 안티그래비티 그룹 구성)에 그 글자를 쓰면
// "이 계정엔 그 창이 없다"를 "읽기 실패"로 말하는 셈이고, 사용자는 고장으로 읽는다. 그 칸은 `없음` 이다.

// MARK: - 두 열의 팔레트

/// 5시간 열 ↔ 주간 열을 가르는 색. **승인된 디자인의 16진수를 그대로 옮긴다**(2026-10-07).
///
/// 맥 전용이다 — 폰·위젯은 각자의 모듈에 같은 숫자를 둔다(맥 앱 타깃은 `CheckMobileShared` 를 링크하지 않고
/// 셋이 공통으로 보는 모듈은 `CheckCore` 뿐이다. `AILimitFloorFill` 이 겪는 것과 같은 제약이고,
/// 그래서 숫자가 갈리지 않는지는 소스 계약 테스트가 되묻는다).
///
/// 이름이 '열 색'이지 '제공자 색'이 아니다 — 제공자는 마크가 가르고, 색은 **창 종류**를 가른다.
enum AILimitMacPalette {
    /// 5시간 바 `#5B8DEF`.
    static let fiveHourBar = Color(aiLimitHex: 0x5B_8D_EF)
    /// 5시간 열 머리 글자 `#7FA8F5`(바보다 밝다 — 작은 글자가 바와 같은 명도면 배경에 묻힌다).
    static let fiveHourHeader = Color(aiLimitHex: 0x7F_A8_F5)
    /// 주간 바 `#8A76E0`.
    static let weeklyBar = Color(aiLimitHex: 0x8A_76_E0)
    /// 주간 열 머리 글자 `#A796E8`.
    static let weeklyHeader = Color(aiLimitHex: 0xA7_96_E8)
    /// 값이 **있는** 칸의 빈 트랙 `#30343B`.
    static let emptyTrack = Color(aiLimitHex: 0x30_34_3B)
    /// 제공자 사이 구분선 `#2C3037`.
    static let separator = Color(aiLimitHex: 0x2C_30_37)
    /// 그 창이 **없는** 칸의 글자 `#595E67`(값이 아니라 '없다'는 사실이라 가장 조용하다).
    static let absentText = Color(aiLimitHex: 0x59_5E_67)
    /// 그 창이 **없는** 칸의 트랙 `#22262C` — 빈 트랙보다 어둡다. 같은 밝기면 "0% 라 비었다"로 읽힌다.
    static let absentTrack = Color(aiLimitHex: 0x22_26_2C)

    /// 그 열의 바 색.
    static func barColor(_ window: AILimitWindow) -> Color {
        switch window {
        case .fiveHour: return fiveHourBar
        case .weekly: return weeklyBar
        }
    }

    /// 그 열의 **머리 글자** 색. 바와 같은 계열이어야 짝이 보인다 — 머리와 바의 색을 따로 고르지 마라.
    static func headerColor(_ window: AILimitWindow) -> Color {
        switch window {
        case .fiveHour: return fiveHourHeader
        case .weekly: return weeklyHeader
        }
    }
}

extension Color {
    /// `0xRRGGBB` 를 그대로 읽는다. 디자인 승인본이 16진수로 적혀 있어, 사람이 0…1 실수로 옮겨 적는 걸음을 없앤다
    /// (그 걸음에서 틀리면 테스트도 같은 틀린 수를 되묻게 된다 — 승인본의 글자와 같은 꼴로 두는 편이 안전하다).
    init(aiLimitHex hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

// MARK: - 사용량 단계 색 (숫자 글자에 붙는다)

/// **얼마나 찼는가**를 말하는 색. 바가 열 색을 쥐었으므로 이 단계는 **숫자 글자**가 말한다.
///
/// ## 왜 바가 아니라 글자인가 (v0.3.46)
/// v0.3.45 는 바 채움을 사용량 단계로 칠했다(평온 파랑 → 70% 주황 → 90% 빨강). 승인된 새 문법은 바 색을
/// **열 구분**에 쓴다(5시간 파랑 · 주간 보라) — 거기에 단계 색까지 얹으면 "파란 바"가 두 뜻을 갖는다.
/// 그렇다고 90% 경고를 통째로 버릴 수는 없어서(그게 이 카드를 보는 이유다) 단계는 숫자 글자로 옮겼다.
/// 평온 단계가 강조색(파랑)이 아니라 **본문색**인 까닭이 이것이다 — 파란 글자는 5시간 열 색과 겹쳐 읽힌다.
///
/// ★ **글자가 쓰는 수로 가른다**(2026-10-07 실증): 초안은 클램프도 안 된 날것 double 로 90 을 갈랐다.
///   89.5% 는 규칙이 `90%` 라고 **적는데**(`wholePercent` 가 반올림한다) 색은 평온했다 — 같은 자리에서
///   글자와 색이 다른 단계를 말한 것이다. 규칙의 반올림을 거쳐야 둘이 영원히 같은 편이 된다
///   (NaN·범위 밖도 그 함수가 접어 준다).
enum AILimitUsageTint {
    /// 색이 갈리는 경계. **글자와 같은 눈금**(반올림한 정수 퍼센트)으로 잰다.
    /// 경계(70/90)는 이 저장소의 주간 목표 게이지 관례(working/pending/danger)를 그대로 쓴다.
    static let warnPercent = 70
    static let dangerPercent = 90

    static func color(for percent: Double?) -> Color {
        guard let percent else { return CheckTheme.secondaryText }
        let whole = AILimitFreshnessRule.wholePercent(percent)
        if whole >= dangerPercent { return CheckTheme.danger }
        if whole >= warnPercent { return CheckTheme.pending }
        return CheckTheme.primaryText
    }
}

// MARK: - 진행바

/// 리밋 진행바. 트랙 + 채움 두 장, 폭·높이는 호출부가 정한다.
///
/// `percent` 가 nil 이면(판정 불가 · 창 없음) **트랙만** 그린다. 0% 로 그리면 "하나도 안 썼다"는 거짓이다 —
/// 모르는 것과 안 쓴 것은 다르고, 사용자는 빈 바를 "여유 있다"로 읽는다.
///
/// ## 왜 공용 진행바를 새로 만들었나 — 그리고 기존 다섯 자리는 왜 안 옮기나
/// 맥에는 진행바 공용 부품이 **없다**. `CheckComponents.swift` 의 다섯 자리가 각자 `GeometryReader` +
/// `Capsule` 두 장을 다시 그린다(트랙 + 채움). 리밋은 한 줄에 바가 **둘**(5시간 · 주간)이고 제공자가 셋이면
/// 여섯 개라, 같은 복제를 여섯 번 더 하면 그때부터는 손으로 못 지킨다. 그래서 부품 하나를 만들어
/// **새 자리에서만** 쓴다. 기존 다섯 자리는 건드리지 않는다 — 그 이동은 이 작업과 무관한 회귀 위험이다
/// (픽셀 실측 테스트가 걸린 자리가 있다).
struct AILimitBar: View {
    /// 0…100. nil = 모른다 / 그 창이 없다(채움 없음).
    let percent: Double?
    /// 하한인가(= 숫자에 "이상"이 붙었는가). 하한이면 채움을 **흐리게** 그린다 — 같은 길이의 바가
    /// 등호일 때와 하한일 때 똑같이 보이면, 숫자의 "이상"만 읽지 못한 사람에게 바는 거짓말이 된다.
    /// ★ 수단은 색이 아니라 **불투명도**다(폰 `ProgressBar` · 위젯 `AingWidgetBar` 와 같은 수 —
    ///   틴트·투명 모드는 색을 통째로 버리고 알파만 남긴다. 숫자가 갈리지 않는지는 교차 모듈 계약 테스트가 잰다).
    let floorOnly: Bool
    let height: CGFloat
    /// 채움 색 = **그 열의 색**(5시간 파랑 · 주간 보라). 제공자 브랜드색도, 사용량 단계색도 아니다.
    let tint: Color
    /// 빈 트랙 색. 창이 **없는** 칸은 더 어두운 트랙을 받는다(`AILimitMacPalette.absentTrack`).
    var track: Color = AILimitMacPalette.emptyTrack

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                if let percent {
                    Capsule()
                        .fill(tint.opacity(floorOnly ? 0.55 : 1))
                        // 0 보다 큰 사용량은 **보이는 길이**를 갖는다 — 1% 가 폭 0 이면 "안 썼다"로 보인다.
                        .frame(width: fillWidth(total: proxy.size.width, percent: percent))
                }
            }
        }
        .frame(height: height)
    }

    /// 채움 폭(순수 — 테스트가 직접 부른다). 0% 는 0pt, 0 보다 크면 최소 `height`(= 캡슐 하나가 보이는 폭).
    static func fillWidth(total: CGFloat, percent: Double, minimum: CGFloat) -> CGFloat {
        guard total > 0 else { return 0 }
        let clamped = min(100, max(0, percent))
        guard clamped > 0 else { return 0 }
        return min(total, max(minimum, total * CGFloat(clamped) / 100))
    }

    private func fillWidth(total: CGFloat, percent: Double) -> CGFloat {
        Self.fillWidth(total: total, percent: percent, minimum: height)
    }
}

// MARK: - 카드의 폭·높이 예산 (실측 상수)

/// 팝오버 리밋 카드의 **레이아웃 예산**(순수 계산).
///
/// `TokenToolMixWidthBudget` 과 같은 이유로 존재한다: 숫자 칸은 `lineLimit(1)` 이라 넘쳐도 **높이가 변하지
/// 않는다** = 렌더 높이 테스트로는 안 잡히고, 넘친 순간의 증상은 말줄임이다. 그리고 이 자리에서
/// 말줄임은 **숫자 자릿수 오독**이다 — "100% 이상"이 "100% 이…"로 잘리면 뜻이 반대로 읽힐 수도 있다
/// (v0.2.41 의 회귀 지점이 정확히 그 모양이었다: "Codex 254만" → "Codex 25…").
///
/// ## 폭의 유래
/// 본문 열은 **316pt** 고정이다(창이 414 로 넓어져도 본문 열은 그대로 — `CheckMenuView.contentColumnWidth`).
/// 카드가 그 폭을 다 쓰고, 안쪽 좌우 여백 12×2 를 빼면 **292** 가 마크·바·숫자가 설 폭이다.
///
/// ## 한 줄의 가로 배치 (왼쪽부터, 전부 이 열거값의 상수다)
/// ```
///  마크 20 | 8 | 5시간 바 69 | 6 | 5시간 숫자 52 | 10 | 주간 바 69 | 6 | 주간 숫자 52   = 292
/// ```
/// 바 폭은 **상수가 아니라 산식**이다(`barWidth`) — 숫자 칸이나 간격을 고치면 바가 따라 줄어야 하고,
/// 둘을 각각 상수로 두면 합이 292 를 넘긴 채 컴파일이 통과한다.
///
/// ## 실측 (2026-10-07 이 맥, `(s as NSString).size(withAttributes:)`)
/// macOS 에서 `.caption` 과 `.caption2` 는 **둘 다 10pt** 다(`NSFont.preferredFont(forTextStyle:)` 로 확인).
/// 글자수로 재면 안 된다 — 한글 10pt · 라틴 소문자 ~5.5pt · 숫자 6.07pt 로 배 이상 차이가 난다.
/// 아래 값은 전부 그 방법으로 잰 것이고, 테스트가 같은 방법으로 다시 재서 되묻는다.
enum AILimitRowWidthBudget {
    /// 카드가 쓰는 바깥 폭 = 팝오버 본문 열(`CheckMenuView.contentColumnWidth`).
    static let cardOuterWidth: CGFloat = 316
    /// 카드 안쪽 좌우 여백(뷰의 `.padding(.horizontal, 12)` 와 같은 값이어야 한다).
    static let rowInsetX: CGFloat = 12
    /// 마크·바·숫자가 설 수 있는 폭 = **292**.
    static var innerWidth: CGFloat { cardOuterWidth - rowInsetX * 2 }

    /// 제공자 마크 한 변.
    static let markSide: CGFloat = 20
    /// 마크 ↔ 첫 바 사이.
    static let markGap: CGFloat = 8
    /// 바 ↔ 그 바의 숫자 사이.
    static let barValueGap: CGFloat = 6
    /// 5시간 묶음 ↔ 주간 묶음 사이(열 경계 — 바-숫자 간격보다 넓어야 두 묶음이 갈린다).
    static let columnGap: CGFloat = 10

    /// 숫자 칸의 **고정** 폭. 오른쪽 정렬 · tabular-nums 라 칸이 고정이어야 세 줄의 숫자가 자리를 맞춘다.
    ///
    /// 값의 근거: 규칙이 내는 문구는 `N%` · `N% 이상` · `0%` · `—` 넷뿐이고(`AILimitFreshnessRule.valueText`)
    /// 거기에 이 카드의 `없음` 이 더해진다. 자릿수 상한은 3(100)이고, 가장 넓은 것은
    /// **"100% 이상"(10pt bold monospacedDigit 실측 50.96)** 이다. `wholePercent` 가 100 보다 작은 값을 절대
    /// `100%` 로 적지 않으므로 세 자리는 정확히 100.0 일 때만 나오지만, 그 조합이 실제로 가능하므로 예산은 거기서 잡는다.
    static let valueWidth: CGFloat = 52
    /// 가장 넓은 숫자 문구("100% 이상")의 실측 폭.
    static let worstValueWidth: CGFloat = 50.96

    /// 바 하나의 폭 = 남는 것을 둘로 나눈다. **산식이다**(위 머리말).
    static var barWidth: CGFloat {
        let fixed = markSide + markGap + barValueGap * 2 + valueWidth * 2 + columnGap
        return (innerWidth - fixed) / 2
    }

    /// 열 머리 글자의 오른쪽 끝을 **그 열 숫자 칸의 오른쪽 끝**에 맞추기 위한 간격.
    /// (5시간 숫자 칸 오른쪽 끝 ↔ 주간 숫자 칸 왼쪽 끝 사이에 있는 것 = 주간 바 + 그 간격 + 열 간격)
    static var headerCellGap: CGFloat { barWidth + barValueGap + columnGap }

    /// 숫자 문구가 칸 안에 말줄임 없이 들어가는가.
    static func fits(valueWidth measured: CGFloat) -> Bool { measured <= valueWidth }

    // MARK: 높이

    /// 바 높이(두 열이 **같다** — 높이로 가르면 주간이 덜 중요해 보이고, 짝 단서는 이미 셋이다).
    static let barHeight: CGFloat = 6
    /// 제공자 한 줄의 **고정** 높이. 마크(20)가 가장 높고 위아래로 2pt 숨을 둔다.
    static let providerRowHeight: CGFloat = 24
    /// 카드 머리 줄(제목 + 열 머리) 높이.
    static let titleRowHeight: CGFloat = 14
    /// 머리 줄 ↔ 첫 제공자 줄 사이.
    static let titleRowGap: CGFloat = 7
    /// 제공자 사이 구분선 두께.
    static let separatorHeight: CGFloat = 1
    /// 카드 안쪽 상하 여백.
    static let rowInsetY: CGFloat = 10
    /// 팝오버 VStack 간격(`CheckMenuView` 본문의 `VStack(spacing: 10)`).
    static let stackSpacing: CGFloat = 10

    /// 제공자 `n` 명인 카드의 **고정** 높이. 뷰가 이 값을 `.frame(height:)` 로 못 박으므로 거짓이 될 수 없다.
    /// 제공자가 없으면 카드를 아예 그리지 않는다(0) — 빈 카드를 0% 로 지어내지 않는다.
    static func cardHeight(providers: Int) -> CGFloat {
        guard providers > 0 else { return 0 }
        return rowInsetY * 2 + titleRowHeight + titleRowGap
            + CGFloat(providers) * providerRowHeight
            + CGFloat(providers - 1) * separatorHeight
    }

    /// 팝오버 높이 예산이 쓰는 값(카드 + VStack 간격). 제공자가 없으면 **0**(간격도 안 먹는다).
    static func budgetHeight(providers: Int) -> CGFloat {
        guard providers > 0 else { return 0 }
        return cardHeight(providers: providers) + stackSpacing
    }
}

// MARK: - 카드가 그릴 것 (순수)

/// 제공자 한 줄이 그릴 것. **값·캡션·"이상" 깃발은 전부 `AILimitFreshnessRule` 이 만들고**, 이 타입이 하는 일은
/// 그것들을 **창별로 꺼내 쓸 수 있게** 묶는 것과, 툴팁 문장을 조립하는 것 둘이다.
///
/// ## ★ 창 하나에 칸 하나 — '대표 창 고르기'가 없다 (v0.3.46)
/// v0.3.45 카드는 머리 숫자 하나를 크게 쓰고 나머지를 얇은 줄로 내렸다. 그래서 "어느 창을 머리로 세우나"라는
/// 선택이 필요했고, 그 선택이 틀리면(초안은 `.fiveHour` 를 무조건 세웠다) 5시간 창이 **없는** 계정에서
/// 큰 글자가 `—` 가 되고 주간 60% 는 얇은 줄로만 남았다 — 같은 데이터로 폰은 머리 줄을 안 그리고 위젯은
/// 주간을 대표로 올려, 세 화면이 같은 숫자를 **다르게** 말했다.
/// 두 창을 나란히 세우는 새 문법에는 그 선택이 **아예 없다**. 없는 창은 `없음` 으로 비고(지어내지 않고),
/// 있는 창은 자기 칸에서 자기 값을 말한다.
struct AILimitCardModel: Equatable, Identifiable {
    let provider: AILimitProvider
    /// **보이는** 창들, 5시간 → 주간 순서. 없는 창은 담지 않는다(0% 로 지어내지 않는다).
    let windows: [AILimitDisplay]
    /// 만료·429·플랜 없음의 한 줄(없으면 nil). 네트워크 실패에는 **문구가 없다** — 숫자를 그대로 두고
    /// 나이 캡션만 낡게 하는 것이 그때의 정직한 표시다(`AILimitReadFailure.noticeText` 주석).
    let notice: String?
    /// 플랜 라벨("plus"/"max"). 없으면 안 그린다.
    let planLabel: String?
    /// 창별로 툴팁에 **덧붙일** 리셋 시각(`오후 6:59 리셋`).
    ///
    /// `make` 가 `now` 를 알 때 만든다. 저장하는 까닭 둘:
    ///  · **이미 지난 리셋은 안 적는다.** 유예(120초) 안쪽에서 리셋이 막 지난 동안 값은 아직 90% 가 맞는데
    ///    (`AILimitFreshnessRule` 함정 ②) 캡션이 `오후 2:04 리셋` 이라고 **지난 시각**을 미래처럼 말했다
    ///    (2026-10-07 실측: 지금이 2:05). 그 판정에는 `now` 가 필요하다.
    ///  · 리셋을 **이미 주장한** 창(0% · 초기화됨)에서는 규칙의 문구가 그 사실을 말하므로 덧붙이지 않는다.
    let resetTexts: [AILimitWindow: String]

    var id: AILimitProvider { provider }

    /// 그 창의 표시(없으면 nil = 그 칸은 `없음`).
    func display(_ window: AILimitWindow) -> AILimitDisplay? {
        windows.first { $0.window == window }
    }

    /// 읽은 창이 하나도 없다 = 숫자를 말할 수 없다. 그 줄은 두 칸 대신 **안내 한 줄**을 말한다.
    var saysNothingButNotice: Bool { windows.isEmpty && notice != nil }

    /// 그 창이 **없다**(= 이 계정엔 그 창 자체가 없다). 읽기 실패와 다른 사실이라 글자도 다르다.
    func isAbsent(_ window: AILimitWindow) -> Bool { display(window) == nil }

    /// 창이 없는 칸의 글자. **`—` 를 쓰지 않는다** — 그 글자는 규칙이 '판정 불가(못 읽었다)'로 못 박았다.
    static let absentValueText = "없음"

    /// '판정 불가' 캡션은 **규칙에서 가져온다**. 여기에 "알 수 없음"을 다시 적으면 문구가 두 벌이 되고,
    /// 한쪽만 고쳐지는 날 화면과 규칙이 다른 말을 한다.
    static let unknownCaption = AILimitFreshnessRule.captionText(
        freshness: .unknown, reference: .distantPast, now: .distantPast
    )

    /// 호버 툴팁. **이름 글자가 없는 카드가 이름·요금제·리셋 시각·관측 나이를 갚는 자리다.**
    ///
    /// ```
    /// Claude max
    /// 5시간 88% 이상 · 3시간 전 · 오후 6:59 리셋
    /// 주간 60% · 3시간 전
    /// ```
    /// 진단 어휘는 쓰지 않는다 — 로컬/서버/포크/축 같은 말은 사용자 툴팁의 것이 아니다
    /// (2026-09-22 결정 · `AILimitSource` 주석과 같은 규약).
    var tooltipText: String {
        var lines = [[provider.displayName, planLabel].compactMap { $0 }.joined(separator: " ")]
        for window in AILimitWindow.allCases.sorted(by: { $0.sortOrder < $1.sortOrder }) {
            if let display = display(window) {
                var parts = ["\(window.displayName) \(display.valueText)", display.captionText]
                if let reset = resetTexts[window] { parts.append(reset) }
                lines.append(parts.joined(separator: " · "))
            } else if !windows.isEmpty {
                // 읽은 창이 하나라도 있으면 **없는 칸도 말해 준다** — 화면의 `없음` 과 같은 글자로.
                lines.append("\(window.displayName) \(Self.absentValueText)")
            }
        }
        if windows.isEmpty { lines.append(Self.unknownCaption) }
        if let notice { lines.append(notice) }
        return lines.joined(separator: "\n")
    }

    /// 목록에 세울 줄 전부(순수 — 테스트가 직접 부른다). 순서·숨김은 스토어가 이미 정했다.
    @MainActor
    static func all(store: AILimitStore, now: Date) -> [AILimitCardModel] {
        store.listedProviders.map { make(store: store, provider: $0, now: now) }
    }

    /// 줄 하나. 창은 **규칙에 물어** 만들고 `isVisible` 이 거짓인 창은 담지 않는다.
    @MainActor
    static func make(store: AILimitStore, provider: AILimitProvider, now: Date) -> AILimitCardModel {
        let windows = AILimitWindow.allCases
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { store.display(provider: provider, window: $0, now: now) }
            .filter(\.isVisible)
        var resets: [AILimitWindow: String] = [:]
        for display in windows {
            guard let window = display.window, let text = resetText(for: display, now: now) else { continue }
            resets[window] = text
        }
        return AILimitCardModel(
            provider: provider,
            windows: windows,
            notice: store.noticeText(provider: provider),
            planLabel: store.bundle?.provider(provider)?.planLabel,
            resetTexts: resets
        )
    }

    /// 툴팁에 덧붙일 리셋 시각. **지난 시각은 nil** 이고, 리셋을 이미 주장한 창도 nil 이다.
    static func resetText(for display: AILimitDisplay, now: Date) -> String? {
        guard !display.freshness.isResetClaim, let resetsAt = display.resetsAt else { return nil }
        // 유예 안쪽에서 리셋이 막 지난 동안(값은 아직 하한이 맞다) **지난 시각을 미래처럼 적지 않는다.**
        guard resetsAt > now else { return nil }
        return "\(AILimitResetTimeText.text(resetsAt)) 리셋"
    }
}

/// 리셋 시각을 `오후 6:59` 로 적는다(KST 기준 기기 시간대).
///
/// 초 이하를 쓰지 않는 이유: Claude 의 `resets_at` 에는 요청 시각의 잔여 분수(`…00.434051`)가 섞여 온다 —
/// 초를 적으면 같은 경계가 호출마다 다르게 보인다.
enum AILimitResetTimeText {
    static func text(_ date: Date, locale: Locale = Locale(identifier: "ko_KR"), timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateFormat = "a h:mm"
        return formatter.string(from: date)
    }
}

// MARK: - 카드

/// 팝오버의 AI 리밋 카드. 머리 줄(제목 + 열 머리) + 제공자마다 한 줄.
///
/// **자격증명이 하나도 없으면 아무것도 그리지 않는다**(`EmptyView` — 빈 자리도 간격도 없다).
/// 설정 토글이 없는 이유가 이것이다: 쓰는 사람에게만 저절로 생기고, 안 쓰는 사람은 이 카드를 본 적이 없다
/// (2026-10-07 사용자 결정 — 자동 감지).
struct CheckAILimitsCard: View {
    let store: AILimitStore
    /// 표시 기준 시각을 **읽는 클로저**(값이 아니다).
    ///
    /// ★ 값으로 받으면 팝오버 본문이 `store.displayNow` 를 읽게 되고, 그 값은 매초 바뀌므로 팝오버 전체
    ///   서브트리가 매초 무효화된다(`CheckMenuView` 의 잎 뷰 격리 불변식 — 실제 회귀 지점이었다).
    ///   클로저면 읽는 자리가 이 잎의 body 안이라 관찰 등록이 여기에만 붙는다.
    ///
    /// ★ 그리고 **값을 저장하지 마라.** v0.3.45 의 별도 창이 `var now: Date = Date()` 를 들고 있었고,
    ///   기본 인자는 딱 한 번 평가되므로 그 `now` 가 앱 수명 내내 얼어붙었다(리셋이 한 시간 전에 지났는데
    ///   화면은 `88% · 방금` — `AILimitFreshnessRule` 머리말 ⓐ 의 가장 비싼 거짓). 팝오버는 열 때마다
    ///   body 가 다시 돌고 `leagueClockNow` 가 마지막 실제 시각을 들고 있어 같은 함정이 없다.
    let clock: () -> Date

    var body: some View {
        if store.isAvailable {
            let now = clock()
            card(models: AILimitCardModel.all(store: store, now: now),
                 summaryCaption: store.summary(now: now).captionText,
                 combined: Self.combinedWindows(store: store, now: now))
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    private func card(models: [AILimitCardModel], summaryCaption: String, combined: [AILimitDisplay]) -> some View {
        VStack(spacing: 0) {
            titleRow(summaryCaption: summaryCaption, combined: combined)
                .padding(.horizontal, AILimitRowWidthBudget.rowInsetX)
            Spacer(minLength: 0).frame(height: AILimitRowWidthBudget.titleRowGap)
            ForEach(Array(models.enumerated()), id: \.element.id) { index, model in
                if index > 0 {
                    // ★ 구분선은 카드 안쪽 여백 **바깥까지** 긋는다(좌우 패딩을 안 받는다) — 안쪽에서 끊으면
                    //   줄이 '카드 안의 또 다른 카드'처럼 보이고, 세 줄이 한 표라는 사실이 흐려진다.
                    Rectangle()
                        .fill(AILimitMacPalette.separator)
                        .frame(height: AILimitRowWidthBudget.separatorHeight)
                }
                AILimitProviderRow(model: model)
                    .padding(.horizontal, AILimitRowWidthBudget.rowInsetX)
            }
        }
        .padding(.vertical, AILimitRowWidthBudget.rowInsetY)
        .frame(maxWidth: .infinity)
        // ★ 높이를 **뷰가 못 박는다**. 팝오버 높이 예산(`CheckMenuView.aiLimitCardHeight`)이 같은 산식을
        //   쓰는데, 뷰가 자연 높이로 자라면 그 예산이 조용히 거짓이 되고 창이 700pt 상한을 넘는다.
        .frame(height: AILimitRowWidthBudget.cardHeight(providers: models.count))
        .panelStyle()
    }

    /// 머리 줄: 왼쪽에 제목, 오른쪽에 **열 머리 둘**. 열 머리는 자기 열 숫자 칸의 오른쪽 끝에 맞춰 선다 —
    /// 그 정렬이 "이 글자가 저 숫자를 설명한다"를 말하는 세 번째 단서(좌우 자리)다.
    private func titleRow(summaryCaption: String, combined: [AILimitDisplay]) -> some View {
        HStack(spacing: 0) {
            Image(systemName: "gauge.with.needle")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(CheckTheme.secondaryText)
            Text("AI 리밋")
                .font(.caption2)
                .foregroundStyle(CheckTheme.secondaryText)
                .lineLimit(1)
                .padding(.leading, 4)
            Spacer(minLength: 4)
            columnHeader(.fiveHour)
            Spacer(minLength: 0).frame(width: AILimitRowWidthBudget.headerCellGap)
            columnHeader(.weekly)
        }
        .frame(height: AILimitRowWidthBudget.titleRowHeight)
        // 카드 전체의 나이·조합값은 제목 호버가 말한다(줄마다의 상세는 그 줄의 툴팁이 말한다).
        .checkTooltip(Self.summaryTooltip(windows: combined, caption: summaryCaption))
    }

    private func columnHeader(_ window: AILimitWindow) -> some View {
        Text(window.displayName)
            .font(.system(size: 10, weight: .semibold))
            // ★ 열 머리 글자를 **그 열의 색으로 물들인다**. 색만으로 가르지 않는 것과 모순이 아니다 —
            //   글자(이름) · 색 · 자리 셋이 같은 짝을 말하게 하는 것이 요점이다.
            .foregroundStyle(AILimitMacPalette.headerColor(window))
            .lineLimit(1)
            .frame(width: AILimitRowWidthBudget.valueWidth, alignment: .trailing)
    }

    // MARK: 조합값(툴팁 전용)

    /// 창 종류별 조합값(5시간 → 주간 순서). **안 보이는 창은 여기서 빠진다.**
    ///
    /// 전제가 좁다는 점에 주의: 조합값은 **연동된 제공자 중 하나라도** 그 창을 가지면 보인다. 그래서 빈 갈래는
    /// 모든 제공자에 그 창이 없을 때만 나온다 — 드물지만 실재한다(주간만 오는 요금제 하나만 연동한 사람).
    static func combinedWindows(store: AILimitStore, now: Date) -> [AILimitDisplay] {
        AILimitWindow.allCases
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { AILimitFreshnessRule.combine(windowDisplays(store: store, window: $0, now: now)) }
            .filter(\.isVisible)
    }

    static func windowDisplays(store: AILimitStore, window: AILimitWindow, now: Date) -> [AILimitDisplay] {
        store.visibleProviders.map { AILimitFreshnessRule.display(provider: $0, window: window, now: now) }
    }

    /// 제목 툴팁 = 창 종류별 최악 + 나이. 제공자가 셋이어도 숫자는 **둘**이다(창 종류별 최악).
    ///
    /// ★ 창 라벨을 **언제나** 붙인다(`5시간 88% · 주간 60%`). 화면의 칸은 자리가 라벨이지만 툴팁은 한 줄
    ///   글자라 자리 단서가 없다 — 라벨이 없으면 주간 42% 가 5시간으로 읽힌다.
    ///
    /// 보이는 창이 하나도 없으면 숫자를 지어내지 않고 나이만 말한다. 이 갈래는 창이 아예 안 읽힌 경우
    /// (만료·429 뿐인 제공자 — 그래도 카드는 선다: `store.isAvailable`)이고, 그때 '판정 불가'는 맞는 말이다.
    /// ★ 줄바꿈으로 잇는다 — 잇는 글자에 `—` 를 쓰면 **규칙의 '판정 불가' 글자와 같은 문자**가 되어
    ///   "이 숫자는 못 읽은 값이다"로 읽힌다(2026-10-07 테스트가 바로 그걸 잡았다).
    static func summaryTooltip(windows: [AILimitDisplay], caption: String) -> String {
        guard !windows.isEmpty else { return "AI 사용률\n\(caption)" }
        let body = windows
            .map { "\($0.window?.displayName ?? "") \($0.valueText)" }
            .joined(separator: " · ")
        return "\(body)\n\(caption)"
    }
}

// MARK: - 제공자 한 줄

/// 제공자 한 줄: `[마크][5시간 바][5시간 %][주간 바][주간 %]`. **이름 글자가 없다**(툴팁이 갚는다 — 파일 머리말).
struct AILimitProviderRow: View {
    let model: AILimitCardModel

    var body: some View {
        HStack(spacing: 0) {
            AIProviderTile(provider: model.provider, size: AILimitRowWidthBudget.markSide)
            Spacer(minLength: 0).frame(width: AILimitRowWidthBudget.markGap)
            if model.saysNothingButNotice, let notice = model.notice {
                // 읽은 창이 하나도 없는 제공자(만료·429·구독 리밋 없음)는 두 칸을 `없음` 으로 비우지 않는다 —
                // 그건 "그 창이 없다"는 뜻이고, 여기서 사실은 "지금 못 읽었다"다. 할 일을 한 줄로 말한다.
                Text(notice)
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.pending)
                    .lineLimit(1)
                Spacer(minLength: 0)
            } else {
                cell(.fiveHour)
                Spacer(minLength: 0).frame(width: AILimitRowWidthBudget.columnGap)
                cell(.weekly)
            }
        }
        .frame(height: AILimitRowWidthBudget.providerRowHeight)
        .checkTooltip(model.tooltipText)
    }

    /// 한 칸 = 바 + 숫자. 세 모양이 있다:
    ///  ① 값이 있다 → 트랙 + 채움(열 색, 하한이면 흐리게) + `27%` / `27% 이상` / `0%`
    ///  ② 창은 있는데 판정 불가(기기 시계 어긋남) → 트랙만 + `—`
    ///  ③ **그 창이 없다** → 더 어두운 트랙만 + `없음`
    /// ②와 ③을 같은 글자로 그리지 않는 이유는 파일 머리말에 있다.
    private func cell(_ window: AILimitWindow) -> some View {
        let display = model.display(window)
        return HStack(spacing: AILimitRowWidthBudget.barValueGap) {
            AILimitBar(
                percent: display?.percent,
                floorOnly: display?.floorOnly ?? false,
                height: AILimitRowWidthBudget.barHeight,
                tint: AILimitMacPalette.barColor(window),
                track: display == nil ? AILimitMacPalette.absentTrack : AILimitMacPalette.emptyTrack
            )
            .frame(width: AILimitRowWidthBudget.barWidth)
            Text(display?.valueText ?? AILimitCardModel.absentValueText)
                .font(.caption.weight(.bold))
                // tabular-nums. 숫자 폭이 글리프마다 다르면 세 줄의 `%` 가 들쭉날쭉해 자릿수를 오독한다.
                .monospacedDigit()
                .foregroundStyle(display == nil
                                 ? AILimitMacPalette.absentText
                                 : AILimitUsageTint.color(for: display?.percent))
                .lineLimit(1)
                // 오른쪽 정렬 · 고정 칸(승인된 문법 ⑥).
                .frame(width: AILimitRowWidthBudget.valueWidth, alignment: .trailing)
        }
    }
}
