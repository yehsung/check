import CheckCore
import CoreGraphics
import Foundation

// MARK: - '폰·위젯에 보여줄 맥' 고르개의 예산 (v0.3.47 P2 — 순수 계산 · 테스트가 값으로 되묻는다)
//
// ## 왜 뷰 밖에 있나
// 이 고르개의 결함은 **말줄임**이다. 줄 높이는 고정이라(`rowHeight`) 글자가 넘쳐도 렌더 높이가 변하지 않고,
// 증상은 "두 줄이 똑같아 보인다" 하나다 — 숫자를 뷰 안에 적으면 그 어긋남을 되묻는 그물이 사람 눈뿐이 된다.
//
// ## 무엇이 고장났었나 (2026-10-08 실측)
// 초안은 칩 하나하나를 `HStack` 한 줄에 넣고 `frame(maxWidth: 160)` + tail 말줄임으로 뒀다. 줄바꿈도 가로
// 스크롤도 없다. 그러면 칩이 남는 폭을 **나눠 갖는다** — 카드 안쪽 328pt, 칩 사이 6pt, 칩 안쪽 여백 12×2:
//   2대 136pt · 3대 81.3 · **4대 53.5** · 5대 36.8 · 6대 26.3 (글자 자리)
// 12pt semibold 실측은 `Mac mini` 52.6 · `사무실 iMac` 62.2 · 꼬리까지 붙은 `Mac mini (A1B2)` **95.3** 이다.
// 그래서 **3대에서 이미 꼬리가 먼저 잘리고**(= 같은 이름 두 칩이 글자 그대로 같아진다 — 신고된 4대보다 한 대
// 이르다), 4대에서는 평범한 한글 이름조차 못 쓰고, 5대부터는 가장 짧은 이름도 안 든다.
// **고르개는 그 둘을 가르는 것이 존재 이유인 화면**이고, 이름 없는 옛 맥 둘(`이름 모를 맥 9F8E`/`2B1C`)도
// 같은 꼴이 된다.
//
// ## 그래서 **목록**이다 (칩 줄 → 한 줄에 한 대)
// 맥 설정 창은 세로로 자랄 수 있다(v0.3.47 이 본문을 `ViewThatFits` + `ScrollView` 로 바꿔 둔 덕이다 —
// `CheckSettingsView.body` 주석). 줄마다 폭을 통째로 주면 이름 자리가 **기기 수와 무관하게** 같고,
// 그게 이 수리의 전부다: 칩을 줄바꿈하는 길도 있었지만 그쪽은 "두 칩이 같은 줄에 몇 개 오느냐"에 따라
// 이름 자리가 다시 흔들린다(4대는 되고 6대는 안 되는 모양이 또 생긴다).
//
// ## 그래도 긴 이름은 잘린다 — 그래서 **꼬리를 따로** 세운다
// 이름 상한은 64 스칼라고 한글은 12pt 에서 한 자가 ~12pt라, 상한 길이 이름은 308pt 한 줄에 **절대 안 든다**.
// 폰 카드와 **같은 수리**를 쓴다(`AILimitDeviceNameParts`): 이름은 잘리고 꼬리는 `fixedSize` 로 제 폭을
// 먼저 가져간다. 잘리는 쪽은 겹쳐도 같은 글자이고, 남는 쪽은 **가르는** 글자다.
enum AILimitDevicePickerBudget {
    /// 설정 절(節) 카드의 **안쪽 폭**(pt). `CheckSettingsView.preferredWidth` 380 − 본문 여백 14×2 − 카드 여백 12×2.
    /// (v0.3.36 주석의 "실측 카드 안쪽 폭 328" 과 같은 숫자다 — 두 곳이 갈리면 둘 중 하나가 거짓이다.)
    static let sectionInnerWidth: CGFloat = 328

    /// 줄 하나의 높이(칩과 같은 눈금 — 설정 창의 다른 칩·버튼과 키가 맞아야 한 화면으로 읽힌다).
    static let rowHeight: CGFloat = 26
    /// 줄 사이.
    static let rowGap: CGFloat = 6
    /// 줄 안쪽 좌우 여백.
    static let rowHorizontalPadding: CGFloat = 10
    /// 줄 안 조각 사이(이름 ↔ 꼬리 ↔ 체크 표시).
    static let itemGap: CGFloat = 6
    /// 고른 줄의 체크 표시 자리. **고르지 않은 줄도 이만큼 비워 둔다** — 안 비우면 줄마다 이름 자리가 달라져
    /// 같은 이름 두 대가 **서로 다른 지점에서** 잘린다(그 차이는 가르는 단서처럼 보이지만 선택이 바뀌면 사라진다).
    static let checkWidth: CGFloat = 12
    /// 줄 글자 = `.caption`(12pt) semibold.
    static let fontSize: CGFloat = 12

    /// 실측(2026-10-08, 12pt semibold): **가장 넓은** 꼬리 글자 `(WWWW)` = 57.59pt(`(A1B2)` 는 39.56).
    /// 글자 수는 고정이고(`AILimitDevice.shortTail` — 4자) 폭만 글리프에 따라 다르므로, 이름 자리를 잴 때는
    /// **가장 넓은 쪽**을 뺀다. 평균을 빼면 꼬리가 넓은 식별자에서 이름 자리가 과대평가된다.
    static let worstTailWidth: CGFloat = 57.6

    /// 줄 안에서 조각들이 쓸 수 있는 폭.
    static var rowInnerWidth: CGFloat { sectionInnerWidth - rowHorizontalPadding * 2 }

    /// 이름 글자가 쓸 수 있는 폭. ★ **기기 수가 인자가 아니다** — 4대든 6대든 같다(이 수리의 요점).
    static func nameWidth(hasTail: Bool) -> CGFloat {
        var width = rowInnerWidth - itemGap - checkWidth
        if hasTail { width -= worstTailWidth + itemGap }
        return width
    }

    /// 꼬리가 **어떤 이름 앞에서도** 그려지는가(이름이 아무리 길어도 꼬리는 제 폭을 먼저 가져간다).
    static func tailAlwaysFits(_ measured: CGFloat) -> Bool {
        measured + itemGap * 2 + checkWidth <= rowInnerWidth
    }

    /// 목록이 쓰는 세로(pt). 창은 넘치면 스크롤한다(`CheckSettingsView.body` 의 `ViewThatFits`) —
    /// 그래서 이 값이 커지는 것은 잘림이 아니라 스크롤이다.
    static func listHeight(deviceCount: Int) -> CGFloat {
        guard deviceCount > 0 else { return 0 }
        return CGFloat(deviceCount) * rowHeight + CGFloat(deviceCount - 1) * rowGap
    }
}
