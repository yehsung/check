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

    // MARK: 기기 묶음 머리글 (v0.3.47 — 맥 두 대 이상)
    //
    // 맥이 둘 이상이면 카드가 **기기 이름으로 묶어 전부** 그린다(2026-10-08 사용자 결정). 머리글은 묶음마다
    // 한 줄이고, **열 머리는 카드당 한 번 그대로**다 — 왜 그렇게 골랐는지는 `MeAILimitsCard` 머리말 §기기 묶음.
    //
    // 머리글은 데이터가 아니라 **구획 표시**라 제공자 이름(13pt semibold `label`)보다 조용하다(12pt semibold
    // `label2`). 같은 굵기·같은 색으로 두면 네 번째 제공자 줄처럼 읽힌다.

    /// 묶음 머리글 글자 = `.caption`(12pt) semibold.
    static let deviceNameFontSize: CGFloat = 12
    /// 머리글 ↔ 그 묶음의 첫 줄 사이.
    static let deviceNameBottomGap: CGFloat = 4
    /// 앞 묶음 ↔ 머리글 사이(구분선 위아래로 숨을 둔다 — 없으면 머리글이 앞 묶음의 꼬리처럼 붙는다).
    static let deviceNameTopGap: CGFloat = 8

    /// 실측(2026-10-08, `(s as NSString).size(withAttributes:)` 12pt semibold):
    /// 이름이 겹쳐 꼬리까지 붙은 가장 넓은 현실 문구 `예성의 MacBook Pro (A1B2)` = 154.64pt.
    /// 테스트가 같은 방법으로 다시 재서 되묻는다.
    static let worstDeviceNameWidth: CGFloat = 154.65

    /// 그 이름이 **한 줄에** 들어가는가. 넘으면 **두 줄로 접힌다**(말줄임이 아니다) — 폰 카드에는 세로 자리가
    /// 있고, 머리글이 잘리면 맥 미니 두 대를 가르려고 붙인 꼬리가 바로 그 잘리는 자리에 있다.
    /// (위젯 머리는 반대다: 세로 자리가 없어 거기서는 자른다 — `AingWidgetLimitsMediumBudget.deviceNameWidth`.)
    static func deviceNameFitsOneLine(_ measured: CGFloat, screenWidth: CGFloat) -> Bool {
        measured <= innerWidth(screenWidth: screenWidth)
    }

    // MARK: 겹침 꼬리는 **잘리지 않는 자리**에 있다 (v0.3.47 P2)
    //
    // ## 두 줄로 접는 것으로는 안 된다 — 두 줄에도 안 드는 이름이 있다
    // `device_label` 상한은 **64 스칼라**이고(`AILimitDeviceLabelContract`) 한글은 12pt semibold 에서 한 자가
    // ~12pt 다. 가장 좁은 기기의 카드 안쪽은 311pt 라 두 줄이 622pt 인데, 64자 한글 이름은 그보다 넓다.
    // 그러면 `lineLimit(2)` + tail 말줄임이 **뒤를 먹고**, 거기가 바로 겹침을 가르는 꼬리 `(A1B2)` 자리다 —
    // 같은 이름의 맥 두 대가 글자 그대로 똑같은 머리글로 선다(이름을 가르려고 만든 장치가 가를 수 없는 짝을 만든다).
    //
    // ## 그래서 꼬리를 따로 세운다
    // 머리글은 `[이름(두 줄까지 · 넘치면 말줄임)] [꼬리(fixedSize)]` 다. 잘리는 쪽은 **겹쳐도 같은** 글자이고
    // 남는 쪽은 **가르는** 글자다. 아래 두 함수가 "꼬리는 어떤 이름 앞에서도 제 폭을 가진다"를 값으로 못 박는다.

    /// 이름 ↔ 꼬리 사이.
    static let deviceTailGap: CGFloat = 4

    /// 실측(2026-10-08, 12pt semibold): **가장 넓은** 꼬리 글자 `(WWWW)` = 57.59pt.
    /// 꼬리는 식별자 뒤 4자를 대문자로 적은 것이라 글자 수가 고정이고(`AILimitDevice.shortTail`), 폭은 글리프에
    /// 따라 `(A1B2)` 39.56 ~ `(WWWW)` 57.59 사이다. **가장 넓은 쪽**을 상수로 든다 — 평균을 들면 UUID 가 아닌
    /// 식별자(사람이 읽을 수 있는 기기 이름 기반)에서 꼬리가 눌릴 수 있고, 눌리는 순간 두 맥을 가를 글자가 없다.
    static let worstDeviceTailWidth: CGFloat = 57.6

    /// 꼬리가 그 기기에서 **반드시** 들어갈 자리가 있는가. 이름이 아무리 길어도 꼬리는 `fixedSize` 로 제 폭을
    /// 먼저 가져가므로, 이 부등식이 참이면 꼬리는 **어떤 이름 앞에서도** 그려진다.
    static func deviceTailAlwaysFits(_ measured: CGFloat, screenWidth: CGFloat) -> Bool {
        measured + deviceTailGap <= innerWidth(screenWidth: screenWidth)
    }

    /// 이름이 **두 줄에도 안 드는** 길이인가 = 말줄임이 나는 조건(= 꼬리를 합쳐 적었다면 잘렸을 조건).
    /// 두 줄 폭은 `innerWidth × 2` 로 **넉넉히** 잡는다 — 실제로는 줄바꿈 때문에 이보다 일찍 잘리므로,
    /// 이 부등식이 참이면 말줄임은 확실하다(거짓이어도 안 잘린다는 보장은 아니다).
    static func deviceNameOverflowsTwoLines(_ measured: CGFloat, screenWidth: CGFloat) -> Bool {
        measured > innerWidth(screenWidth: screenWidth) * 2
    }
}
