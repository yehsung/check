import SwiftUI

// 「AI 리밋」 위젯의 **머리 줄**(v0.3.47 P2). 플랫폼 무관 — 위젯(iOS)이 그리고, 맥 스위트가 `ImageRenderer` 로
// **같은 코드를** 굽는다. 위젯 화면(`Widgets/`)은 `#if os(iOS)` 라 맥 스위트가 한 줄도 컴파일하지 않는데,
// 이 줄의 결함(상한 길이 쌍둥이의 꼬리가 말줄임에 먹힌다)은 **그림으로만** 보인다 — 그래서 이 줄만 밖으로 뺐다.
// 색은 렌더링 모드를 아는 쪽(위젯의 `AingWidgetInk`)이 넘긴다.

/// 머리 줄: 제목 + **메인 맥 이름**(맥 두 대 이상) + **리밋 관측 나이**.
///
/// ```
/// [AI 리밋] 6 [· 이름(말줄임)] 4 [(A1B2) fixedSize] [Spacer ≥6] [3분 전 fixedSize]
/// ```
package struct AingWidgetLimitsHeaderLine: View {
    package let title: String
    /// nil = 맥이 한 대뿐이다(= 적지 않는다 — 그 판정은 `AingWidgetLimits.headerDevice` 가 값으로 했다).
    package let device: AingWidgetLimitsHeaderDevice?
    /// nil = 관측 시각을 모른다(= 적지 않는다).
    package let age: String?
    package let primary: Color
    package let secondary: Color

    package init(title: String, device: AingWidgetLimitsHeaderDevice?, age: String?, primary: Color, secondary: Color) {
        self.title = title
        self.device = device
        self.age = age
        self.primary = primary
        self.secondary = secondary
    }

    package var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: AingWidgetLimitsMediumBudget.headerItemGap) {
            Text(title)
                .aingFont(15, .bold, relativeTo: .subheadline)
                .foregroundStyle(primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityAddTraits(.isHeader)
            // ★ 메인 맥 이름(맥이 **두 대 이상일 때만** 들어온다 — 한 대면 nil 이라 0.3.46 과 똑같이 보인다).
            //   자리는 머리 줄 안이고 세로를 하나도 더 쓰지 않는다. 그 선택의 실측 근거는
            //   `AingWidgetLimitsMediumBudget` §머리 줄의 기기 이름(좁은 기기에서 이름 자리 194.4pt).
            if let device {
                deviceName(device)
            }
            Spacer(minLength: AingWidgetLimitsMediumBudget.headerMinGap)
            if let age {
                Text(age)
                    .monospacedDigit()
                    .aingFont(11, relativeTo: .caption2)
                    .foregroundStyle(secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        // ★ **최소** 높이다. 기본 글자 크기에서는 예산(18pt)과 정확히 같고, 글자를 키운 사람에게는 머리가
        //   조금 자라고 줄들이 그만큼 줄어든다 — 고정 높이로 못 박으면 그 사람의 머리 글자가 아래 줄을 덮는다.
        .frame(minHeight: AingWidgetLimitsMediumBudget.headerHeight, alignment: .leading)
    }

    /// 이름과 겹침 꼬리를 **따로** 그린다(폰 카드 `deviceNameRow` 와 같은 수리).
    ///
    /// 0.3.47 초안은 합친 글자(`· 이름 (A1B2)`) 하나를 tail 말줄임으로 그렸다. 상한 길이(64 스칼라) 이름이면 말줄임이
    /// **뒤**를 먹는데 거기가 바로 꼬리 자리라, 같은 이름의 맥 두 대의 위젯 머리가 **글자 그대로 같았다** — 위젯은
    /// 맥 한 대만 그리므로 "이 숫자가 어느 쌍둥이 것인지"를 말할 글자가 꼬리뿐인데, 그 글자가 사라졌다.
    /// 그래서 잘리는 쪽은 **겹쳐도 같은** 글자(이름), 남는 쪽은 **가르는** 글자(꼬리)다.
    ///
    /// ★ 나이 글자도 `fixedSize()` 라 머리 줄에서 줄어드는 것은 이름뿐이다(제목은 짧아서 버틴다).
    /// ★ 보이스오버는 둘을 **한 이름으로** 읽는다(가운뎃점 없이 꼬리까지 — `spoken`). 나뉜 것은 그리기 사정이다.
    private func deviceName(_ device: AingWidgetLimitsHeaderDevice) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: AingWidgetLimitsMediumBudget.deviceTailGap) {
            Text(device.name)
                .lineLimit(1)
                .truncationMode(.tail)
            if let tail = device.tail {
                Text(tail)
                    .lineLimit(1)
                    // ★ 이 둘이 꼬리를 지킨다: `fixedSize` 는 "줄이지 마라", `layoutPriority` 는 "먼저 가져가라".
                    //   하나만 두면 이름이 긴 날 꼬리가 0pt 로 눌리거나 `…` 로 바뀐다.
                    .fixedSize()
                    .layoutPriority(1)
            }
        }
        .aingFont(11, relativeTo: .caption2)
        .foregroundStyle(secondary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(device.spoken))
    }
}

// MARK: - 글꼴

/// 시안 px 크기를 텍스트 스타일 배율로 키운다(위젯 칸 상한 xxLarge 까지 — `AingWidgetContainer`).
/// 플랫폼 무관 자리에 둔 까닭: 머리 줄(`AingWidgetLimitsHeaderLine`)을 맥 스위트가 **같은 글꼴로** 굽게 하려고.
/// 맥에는 다이내믹 타입이 없어 `ScaledMetric` 이 기준 크기를 그대로 돌려준다.
private struct AingScaledFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight

    init(size: CGFloat, weight: Font.Weight, relativeTo style: Font.TextStyle) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: style)
        self.weight = weight
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight))
    }
}

extension View {
    func aingFont(_ size: CGFloat, _ weight: Font.Weight = .regular, relativeTo style: Font.TextStyle) -> some View {
        modifier(AingScaledFont(size: size, weight: weight, relativeTo: style))
    }
}
