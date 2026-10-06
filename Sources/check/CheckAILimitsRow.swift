import CheckCore
import SwiftUI

// MARK: - AI 리밋: 팝오버 한 줄 요약 + 공용 진행바 (v0.3.45)
//
// 이 파일에 있는 것은 **두 개**다: 팝오버 한 줄과, 리밋 카드·한 줄이 함께 쓰는 작은 진행바 부품.
//
// ## 숫자·캡션·표시여부를 뷰가 계산하지 않는다
// 전부 `AILimitFreshnessRule` 에서 받는다. 그 규칙 하나가 "27%" 와 "27% 이상" 과 "0%" 와 "—" 를 가르고,
// 캡션의 나이 문구도 거기서 나온다. 뷰가 반올림을 한 번만 더 하면 그 순간 규칙이 둘이 되고,
// 이 저장소는 **스토어만 고치고 뷰는 그대로여서 테스트가 초록인 채 화면이 안 바뀌는** 사고를 이미 겪었다
// (관례: '클라 게이트는 짝으로 있다').
//
// ## 왜 공용 진행바를 새로 만들었나 — 그리고 기존 다섯 자리는 왜 안 옮기나
// 맥에는 진행바 공용 부품이 **없다**. `CheckComponents.swift` 의 다섯 자리가 각자 `GeometryReader` +
// `Capsule` 두 장을 다시 그린다(트랙 + 채움). 리밋은 카드마다 바가 **둘**(5시간 굵게 · 주간 얇게)이고
// 제공자가 셋이면 여섯 개라, 같은 복제를 여섯 번 더 하면 그때부터는 손으로 못 지킨다.
// 그래서 부품 하나를 만들어 **새 자리에서만** 쓴다. 기존 다섯 자리는 건드리지 않는다 — 그 이동은 이 작업과
// 무관한 회귀 위험(픽셀 실측 테스트가 걸린 자리가 있다)이고, 별건으로 다뤄야 한다.

/// 리밋 진행바. 트랙 + 채움 두 장, 높이는 호출부가 정한다(5시간 6pt · 주간 3pt).
///
/// `percent` 가 nil 이면(판정 불가) **트랙만** 그린다. 0% 로 그리면 "하나도 안 썼다"는 거짓이다 —
/// 모르는 것과 안 쓴 것은 다르고, 사용자는 빈 바를 "여유 있다"로 읽는다.
struct AILimitBar: View {
    /// 0…100. nil = 모른다(채움 없음).
    let percent: Double?
    /// 하한인가(= 숫자에 "이상"이 붙었는가). 하한이면 채움을 **흐리게** 그린다 — 같은 길이의 바가
    /// 등호일 때와 하한일 때 똑같이 보이면, 숫자의 "이상"만 읽지 못한 사람에게 바는 거짓말이 된다.
    let floorOnly: Bool
    let height: CGFloat
    /// 채움 색. 제공자 브랜드색이 아니라 **사용량 단계 색**이다(아래 `tint(for:)`).
    let tint: Color

    /// 사용량 단계 색. 제공자를 색으로 구분하지 않는 것과 **반대 방향의 규약**이다 —
    /// 여기서 색이 말하는 것은 "누구의 리밋인가"가 아니라 "얼마나 찼는가"다.
    /// 경계(70/90)는 이 저장소의 주간 목표 게이지 관례(working/pending/danger)를 그대로 쓴다.
    static func tint(for percent: Double?) -> Color {
        guard let percent else { return CheckTheme.secondaryText }
        if percent >= 90 { return CheckTheme.danger }
        if percent >= 70 { return CheckTheme.pending }
        return CheckTheme.accent
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(CheckTheme.trackFill)
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

// MARK: - 팝오버 한 줄의 폭 예산

/// 팝오버 한 줄 요약의 **폭 예산**(순수 계산).
///
/// `TokenToolMixWidthBudget` 과 같은 이유로 존재한다: 이 줄은 `lineLimit(1)` 이라 넘쳐도 **높이가 변하지
/// 않는다** = 렌더 높이 테스트로는 안 잡히고, 넘친 순간의 증상은 말줄임이다. 그리고 이 자리에서
/// 말줄임은 **숫자 자릿수 오독**이다 — "100% 이상"이 "100% 이…"로 잘리면 뜻이 반대로 읽힐 수도 있다
/// (v0.2.41 의 회귀 지점이 정확히 그 모양이었다: "Codex 254만" → "Codex 25…").
///
/// ## 폭의 유래
/// 본문 열 316 − 팝오버 padding 12×2 = **292**(창이 414 로 넓어져도 본문 열은 316 그대로다 —
/// `CheckMenuView.contentColumnWidth` 주석). 행 안쪽 좌우 여백 12×2 를 빼면 **268** 이 글자가 설 폭이다.
///
/// ## 실측 (2026-10-07 이 맥, `(s as NSString).size(withAttributes:)`)
/// macOS 에서 `.caption` 과 `.caption2` 는 **둘 다 10pt** 다(`NSFont.preferredFont(forTextStyle:)` 로 확인).
/// 글자수로 재면 안 된다 — 한글 10pt · 라틴 소문자 ~5.5pt · 숫자 6.07pt 로 배 이상 차이가 난다.
/// 아래 값은 전부 그 방법으로 잰 것이고, 테스트가 같은 방법으로 다시 재서 되묻는다.
enum AILimitRowWidthBudget {
    /// 팝오버 본문 열에서 카드 안쪽 폭.
    static let contentWidth: CGFloat = 316 - 12 * 2
    /// 행 안쪽 좌우 여백(뷰의 `.padding(.horizontal, 12)` 와 같은 값이어야 한다).
    static let rowInsetX: CGFloat = 12
    /// 글자가 설 수 있는 폭.
    static var innerWidth: CGFloat { contentWidth - rowInsetX * 2 }

    /// HStack 간격(뷰와 같은 값).
    static let spacing: CGFloat = 8
    /// 왼쪽 아이콘(gauge.with.needle) 칸 폭.
    static let iconWidth: CGFloat = 12
    /// `Spacer(minLength:)` 하한(뷰와 같은 값).
    static let spacerMinWidth: CGFloat = 6

    /// "AI 리밋"(caption2 10pt) 실측 폭.
    static let labelWidth: CGFloat = 29.88
    /// "자세히 ›"(caption2 10pt) 실측 폭.
    static let detailWidth: CGFloat = 33.45

    /// 숫자 자리에 남는 폭 = 268 − 12 − 29.88 − 33.45 − 간격 8×2 − Spacer 하한 6.
    static var valueBudget: CGFloat {
        innerWidth - iconWidth - labelWidth - detailWidth - spacing * 2 - spacerMinWidth
    }

    /// 이 줄이 그릴 수 있는 **가장 넓은 문구**의 실측 폭 — "100% 이상 · 100% 이상"(caption bold monospacedDigit 10pt).
    ///
    /// 왜 이게 최악인가: 규칙이 내는 문구는 `N%` · `N% 이상` · `0%` · `—` 넷뿐이고(`AILimitFreshnessRule.valueText`),
    /// 자릿수 상한은 3(100)이다. `wholePercent` 가 100 보다 작은 값을 절대 `100%` 로 적지 않으므로
    /// 세 자리는 **정확히 100.0 일 때만** 나오지만, 그 조합이 실제로 가능하므로 예산은 거기서 잡는다.
    static let worstValueWidth: CGFloat = 110.91

    /// 그 문구가 말줄임 없이 들어가는가.
    static func fits(valueWidth: CGFloat) -> Bool { valueWidth <= valueBudget }

    /// 행 내용의 **고정** 높이(pt). 글꼴이 바뀌어도 팝오버 높이 예산(`CheckMenuView.aiLimitRowHeight`)이
    /// 안 흔들리게 못 박는다 — 이 값 + 상하 패딩 8×2 + VStack 간격 10 이 그 상수다.
    static let contentHeight: CGFloat = 20
    /// 상하 패딩(뷰와 같은 값).
    static let rowInsetY: CGFloat = 8
    /// 팝오버 VStack 간격(`CheckMenuView` 본문의 `VStack(spacing: 10)`).
    static let stackSpacing: CGFloat = 10
    /// 팝오버 높이 예산이 쓰는 값 = 20 + 8×2 + 10 = 46.
    static var budgetHeight: CGFloat { contentHeight + rowInsetY * 2 + stackSpacing }
}

// MARK: - 팝오버 한 줄

/// 팝오버의 AI 리밋 한 줄. `AI 리밋   26% · 0%   자세히 ›` 꼴이고 누르면 별도 창이 열린다.
///
/// **자격증명이 하나도 없으면 아무것도 그리지 않는다**(`EmptyView` — 빈 자리도 간격도 없다).
/// 설정 토글이 없는 이유가 이것이다: 쓰는 사람에게만 저절로 생기고, 안 쓰는 사람은 이 줄을 본 적이 없다
/// (2026-10-07 사용자 결정 — 자동 감지).
struct CheckAILimitsRow: View {
    let store: AILimitStore
    /// 표시 기준 시각을 **읽는 클로저**(값이 아니다).
    ///
    /// ★ 값으로 받으면 팝오버 본문이 `store.displayNow` 를 읽게 되고, 그 값은 매초 바뀌므로 팝오버 전체
    ///   서브트리가 매초 무효화된다(`CheckMenuView` 의 잎 뷰 격리 불변식 — 실제 회귀 지점이었다).
    ///   클로저면 읽는 자리가 이 행의 body 안이라 관찰 등록이 이 잎에만 붙는다.
    let clock: () -> Date
    let onOpenWindow: () -> Void

    var body: some View {
        if store.isAvailable {
            let now = clock()
            row(store.summary(now: now), now: now)
        } else {
            EmptyView()
        }
    }

    private func row(_ summary: AILimitDisplay, now: Date) -> some View {
        Button(action: onOpenWindow) {
            HStack(spacing: AILimitRowWidthBudget.spacing) {
                Image(systemName: "gauge.with.needle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CheckTheme.secondaryText)
                    .frame(width: AILimitRowWidthBudget.iconWidth)
                Text("AI 리밋")
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .lineLimit(1)
                Spacer(minLength: AILimitRowWidthBudget.spacerMinWidth)
                // 숫자는 규칙이 이미 조립해 둔 문구다 — 여기서 다시 반올림하지 않는다.
                Text(Self.valueText(store: store, now: now))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(CheckTheme.primaryText)
                    .monospacedDigit()
                    .lineLimit(1)
                Text("자세히 ›")
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.accent)
                    .lineLimit(1)
            }
            .frame(height: AILimitRowWidthBudget.contentHeight)
            .padding(.horizontal, AILimitRowWidthBudget.rowInsetX)
            .padding(.vertical, AILimitRowWidthBudget.rowInsetY)
            .frame(maxWidth: .infinity)
            .panelStyle()
        }
        .buttonStyle(.plain)
        // 툴팁은 **캡션 값만** 말한다(나이). 로컬/서버/포크/축 같은 진단 어휘를 사용자에게 쓰지 않는다
        // (2026-09-22 결정 · `AILimitSource` 주석과 같은 규약).
        .checkTooltip(tooltip(summary))
    }

    /// 한 줄에 적는 두 숫자 = "5시간 · 주간". `summary` 는 둘을 이미 합친 값이라 창별로 다시 묶는다.
    ///
    /// 왜 둘인가: 제공자가 셋이어도 숫자는 **둘**이다(창 종류별 최악). 제공자마다 두 개씩 적으면
    /// 여섯 숫자가 되어 이 폭에 절대 안 들어가고, 무엇보다 한 줄 요약이 답할 질문은
    /// "지금 당장 막히나(5시간) · 이번 주가 위험한가(주간)" 둘뿐이다. 나머지는 창이 말한다.
    static func valueText(store: AILimitStore, now: Date) -> String {
        let fiveHour = AILimitFreshnessRule.combine(windowDisplays(store: store, window: .fiveHour, now: now))
        let weekly = AILimitFreshnessRule.combine(windowDisplays(store: store, window: .weekly, now: now))
        return "\(fiveHour.valueText) · \(weekly.valueText)"
    }

    static func windowDisplays(store: AILimitStore, window: AILimitWindow, now: Date) -> [AILimitDisplay] {
        store.visibleProviders.map { AILimitFreshnessRule.display(provider: $0, window: window, now: now) }
    }

    private func tooltip(_ summary: AILimitDisplay) -> String {
        "5시간 · 주간 사용률 — \(summary.captionText)"
    }
}
