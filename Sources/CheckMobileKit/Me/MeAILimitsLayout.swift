import CheckCore
import CheckMobileShared
import CoreGraphics
import Foundation

// MARK: - 폰 「AI 리밋」 카드의 가로 예산 (v0.3.46 — 순수 계산 · macOS swift test 가 값으로 검증한다)
//
// ## 왜 뷰 밖에 있나
// 카드 뷰는 `#if os(iOS)` 라 맥 스위트가 **한 줄도 컴파일하지 않는다**(관례: '폰 뷰는 맥 스위트가 못 본다').
// 그래서 숫자가 맞는지를 잴 수 있는 자리는 여기뿐이다. 그리고 숫자 칸은 `lineLimit(1)` 이라 넘쳐도
// **높이가 변하지 않는다** = 렌더 높이로는 안 잡히고, 넘친 순간의 증상은 말줄임이다. 이 자리에서 말줄임은
// **숫자 자릿수 오독**이다("100% 이상" → "100% 이…").
//
// ## 승인된 문법에서 온 값들 (2026-10-07)
// 한 제공자 = 한 줄, 5시간과 주간이 그 줄 안에 **나란히**. 왼쪽은 **108pt 고정 칸**이고 그 안에
// [마크 26pt][이름 / 요금제 2줄] 이 들어간다 — 세 줄의 **바 시작점이 가지런히** 맞는 이유가 이 고정 폭이다.
// (맥 팝오버는 292pt 안쪽에 이름을 넣을 자리가 없어 마크만 두고 이름을 호버 툴팁으로 갚는다. 폰은 자리가
//  남으므로 이름과 요금제를 **둘 다** 쓴다 — 세 화면이 같은 문법에 다른 예산이다.)
//
// ## 한 줄의 가로 배치(왼쪽부터)
// ```
//  [이름 칸 108] 10 [5시간 바(남는 폭) 6 숫자 62] 10 [주간 바(남는 폭) 6 숫자 62]
// ```
// ★ 바 폭은 **상수가 아니다** — 기기 폭이 다르면(SE 375 · 기본 393 · Max 440) 남는 폭이 다르다.
// 두 바는 `maxWidth: .infinity` 로 **같은 몫**을 받으므로 두 칸의 폭이 언제나 같고, 그래서 열 머리 글자의
// 오른쪽 끝이 자기 열 숫자 칸의 오른쪽 끝과 **구조적으로** 맞는다(측정 상수가 아니라 항등식이다 —
// 맥은 폭이 316pt 고정이라 간격을 상수로 적을 수 있었지만 폰은 그럴 수 없다).
//
// ## 실측 (2026-10-07 이 맥, `(s as NSString).size(withAttributes:)`)
// 글자수로 재면 안 된다 — 한글 13pt · 라틴 소문자 ~7pt · 숫자 7.3pt 로 배 이상 차이가 난다.
// 아래 `worst…` 값이 그 실측이고, 테스트가 같은 방법으로 다시 재서 되묻는다.
enum MeAILimitCardBudget {
    // MARK: 기기 폭 → 카드 안쪽 폭

    /// 화면 좌우 여백(`MobileTheme.sideMargin`).
    static let sideMargin: CGFloat = 16
    /// 카드 안쪽 여백(`MobileTheme.cardPadding`).
    static let cardPadding: CGFloat = 16

    /// 그 기기에서 카드가 쓰는 바깥 폭.
    static func cardOuterWidth(screenWidth: CGFloat) -> CGFloat { screenWidth - sideMargin * 2 }
    /// 마크·이름·바·숫자가 설 수 있는 폭.
    static func innerWidth(screenWidth: CGFloat) -> CGFloat { cardOuterWidth(screenWidth: screenWidth) - cardPadding * 2 }

    /// 이 앱이 받는 가장 좁은 기기(iPhone SE 3세대 · 375pt)와 기본 기기(393pt).
    static let narrowestScreenWidth: CGFloat = 375
    static let referenceScreenWidth: CGFloat = 393

    // MARK: 가로 칸

    /// 왼쪽 고정 칸(승인된 값) — [마크][이름/요금제].
    static let nameColumnWidth: CGFloat = 108
    /// 제공자 마크 한 변(승인된 값).
    static let markSide: CGFloat = 26
    /// 마크 ↔ 이름 사이.
    static let markGap: CGFloat = 6
    /// 이름 칸 ↔ 첫 바 사이.
    static let nameGap: CGFloat = 10
    /// 바 ↔ 그 바의 숫자 사이.
    static let barValueGap: CGFloat = 6
    /// 5시간 묶음 ↔ 주간 묶음 사이(열 경계 — 바-숫자 간격보다 넓어야 두 묶음이 갈린다).
    static let columnGap: CGFloat = 10
    /// 숫자 칸의 **고정** 폭(오른쪽 정렬 · tabular-nums — 칸이 고정이어야 세 줄의 숫자가 자리를 맞춘다).
    static let valueWidth: CGFloat = 62
    /// 바 높이(두 열이 **같다** — 높이로 가르면 주간이 덜 중요해 보이고 짝 단서는 이미 셋이다).
    static let barHeight: CGFloat = 6
    /// 제공자 사이 구분선 두께.
    static let separatorHeight: CGFloat = 1

    /// 이름 글자가 쓸 수 있는 폭.
    static var nameTextWidth: CGFloat { nameColumnWidth - markSide - markGap }

    /// 바를 뺀 고정분 합.
    static var fixedWidth: CGFloat {
        nameColumnWidth + nameGap + barValueGap * 2 + valueWidth * 2 + columnGap
    }

    /// 바 하나의 폭 = 남는 것을 둘로 나눈다(**산식**이다 — 숫자 칸이나 간격을 고치면 바가 따라 줄어야 한다).
    static func barWidth(innerWidth: CGFloat) -> CGFloat { (innerWidth - fixedWidth) / 2 }

    /// 한 칸(바 + 간격 + 숫자)의 폭. 두 칸은 **언제나 같다**.
    static func cellWidth(innerWidth: CGFloat) -> CGFloat { barWidth(innerWidth: innerWidth) + barValueGap + valueWidth }

    /// 바가 이보다 좁아지면 "조금 썼다"가 "안 썼다"로 보인다(= 이 설계의 하한).
    static let minimumBarWidth: CGFloat = 20

    // MARK: 글자 크기(기본 글자 크기에서의 pt — 뷰는 텍스트 스타일을 써서 글자 크기를 따라간다)

    /// 숫자 = `.caption`(iOS 기본 12pt) bold monospacedDigit.
    static let valueFontSize: CGFloat = 12
    /// 열 머리 = `.caption2`(11pt) semibold.
    static let headerFontSize: CGFloat = 11
    /// 이름 = `.footnote`(13pt) semibold · 요금제 = `.caption2`(11pt).
    static let nameFontSize: CGFloat = 13
    static let planFontSize: CGFloat = 11

    /// 가장 넓은 숫자 문구("100% 이상")의 실측 폭 — 12pt bold monospacedDigit.
    static let worstValueWidth: CGFloat = 60.45
    /// 가장 긴 제공자 이름("안티그래비티")의 실측 폭 — 13pt semibold.
    static let worstNameWidth: CGFloat = 67.47
    /// 가장 넓은 열 머리("5시간")의 실측 폭 — 11pt semibold.
    static let worstHeaderWidth: CGFloat = 26.21

    /// 그 문구가 숫자 칸에 말줄임 없이 들어가는가.
    static func valueFits(_ measured: CGFloat) -> Bool { measured <= valueWidth }
}
