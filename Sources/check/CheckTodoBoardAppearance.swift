import Foundation
import Observation
import SwiftUI

// MARK: - 재질 실측 상수(정본)

/// 보드 배경을 이루는 두 겹의 **물리량**. 이 값들이 이 파일에 있는 이유는 대비 계산 때문이다 —
/// 같은 숫자를 뷰가 그리는 데 쓰고 모델이 대비를 재는 데 쓰는데, 두 벌로 갈라지면 **대비 기준이 두 개**가 된다
/// (그린 그림은 A 로, "읽히는가" 판정은 B 로 하게 되어 어느 쪽도 사실이 아니게 된다). 그래서 정본은 여기 하나다.
///
/// ★ 측정 방법: **오프스크린 within-window 합성**. behind-window 블러(실제 데스크톱을 빨아들이는 경로)는
/// 윈도 서버가 있어야 해서 테스트에서 못 그린다. 대신 같은 재질을 창 안쪽 합성으로 렌더해 백킹스토어 픽셀을
/// 직접 읽었다. 패널이 `.darkAqua` 로 **고정**이라 이 값들은 시스템 테마와 무관하게 한 벌뿐이고,
/// 최악 케이스(순백 바탕화면)에서는 블러가 평평한 흰색을 평균내도 흰색이라 within-window 결과가 그대로 성립한다.
enum TodoBoardTint {
    /// 보드 틴트의 출고 세기. 사용자 조절값의 **기본값**과 같은 숫자여야 한다 — 리터럴을 따로 적으면
    /// 설정을 만지지 않은 사용자의 화면이 두 값 중 어느 것으로 그려지는지가 배선 순서에 달리게 된다.
    static let opacity: Double = TodoBoardAppearance.defaultOpacity

    /// hudWindow(다크) 재질이 자기 틴트를 얹는 알파. 실측 0.40.
    static let materialTintAlpha: Double = 0.40

    /// 그 틴트의 **색**(그레이스케일 레벨). 실측 0.283 — **순흑이 아니다.**
    /// 이 한 숫자가 이 파일의 이전 판을 통째로 틀리게 만들었다: 순흑(0.0)으로 가정하면 같은 계산이
    /// 틴트 0.55 에서 5.93:1 을 내놓지만, 실제로 렌더한 픽셀은 4.90:1 이었다. 재질은 생각보다 훨씬 밝다.
    static let materialTintWhite: Double = 0.283

    /// 순백 바탕화면이 재질을 통과한 뒤의 밝기. `materialTintAlpha * materialTintWhite + (1 - materialTintAlpha)`
    /// = 0.7132 이고 렌더 픽셀 실측도 0.713 이었다(둘이 어긋나지 않는지는 테스트가 지킨다).
    /// 대비 계산에서 이 한 겹을 빼먹으면 실제보다 훨씬 나쁜 숫자가 나와 틴트를 과하게 올리게 된다.
    static let hudOverWhiteLevel: Double = 0.713

    /// 위 값의 `Color` 판. 뷰·스냅샷 테스트가 "실제 화면에 가장 가까운 한 장"의 바탕으로 쓴다.
    static let hudOverWhite = Color(white: hudOverWhiteLevel)

    // CheckTheme 의 색을 숫자로 되비춘 것. SwiftUI `Color` 에서는 성분을 다시 꺼낼 수 없어 계산에 못 쓴다.
    // 리터럴 복제는 갈라질 위험이 있으므로, 테스트가 NSColor 변환으로 CheckTheme 원본과 대조해 못 박는다.

    /// `CheckTheme.panel` 의 sRGB 성분.
    static let panelRGB: (r: Double, g: Double, b: Double) = (0.17, 0.18, 0.24)
    /// `CheckTheme.primaryText` 의 흰색 알파. 글자가 **반투명**이라는 게 대비 계산의 핵심이다 —
    /// 배경이 밝아지면 글자도 같이 밝아져 대비가 양쪽에서 무너진다.
    static let primaryTextAlpha: Double = 0.94
    /// `CheckTheme.secondaryText` 의 흰색 알파.
    static let secondaryTextAlpha: Double = 0.68

    /// 재질을 임의의 바탕 위에 얹은 결과 밝기. `blurAlpha` 는 블러 뷰의 `alphaValue` 라,
    /// 블러가 걷히면 재질의 틴트 기여도 같이 줄어 **바탕이 그대로 드러난다**(= 대비가 더 나빠진다).
    /// 낮은 구간의 대비를 잴 때 이 항을 빼먹으면 실제보다 좋은 숫자가 나온다.
    static func materialLevel(over backdrop: Double, blurAlpha: Double = 1) -> Double {
        let alpha = materialTintAlpha * min(max(blurAlpha, 0), 1)
        return alpha * materialTintWhite + (1 - alpha) * backdrop
    }
}

// MARK: - 대비 계산(순수)

/// WCAG 2.x 상대휘도·대비비. **보고서가 아니라 코드에 있어야 하는 이유**는, 이 파일의 상수 전부가
/// 대비비에서 나왔기 때문이다. 숫자가 주석에만 있으면 다음 사람이 상수를 옮길 때 대비가 조용히 무너진다 —
/// 함수로 있어야 테스트가 "이 상수 조합에서 본문이 4.5:1 이상"을 계속 검사할 수 있다.
enum TodoBoardContrast {
    /// sRGB 성분(0~1) → 상대휘도. 감마 역보정 계수는 WCAG 정의 그대로다.
    static func relativeLuminance(_ color: (r: Double, g: Double, b: Double)) -> Double {
        func linear(_ channel: Double) -> Double {
            let c = min(max(channel, 0), 1)
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(color.r) + 0.7152 * linear(color.g) + 0.0722 * linear(color.b)
    }

    /// 두 색의 대비비(항상 1 이상).
    static func ratio(
        _ first: (r: Double, g: Double, b: Double),
        _ second: (r: Double, g: Double, b: Double)
    ) -> Double {
        let a = relativeLuminance(first)
        let b = relativeLuminance(second)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// WCAG AA 본문 기준. 이 파일의 무릎점이 서 있는 자리다.
    static let aaBodyText: Double = 4.5
    /// WCAG AA 큰 글자 기준. 보조 텍스트는 이쪽으로만 판정한다(아래 `secondaryText` 주석 참고).
    static let aaLargeText: Double = 3.0
}

// MARK: - 값 모델

/// 할 일 보드 배경의 투명도. 사용자가 직접 조절한다.
///
/// ★ **조절 대상은 배경 두 겹뿐이다. 글자는 언제나 100% 로 그린다.**
///   패널이나 그 contentView 의 `alphaValue` 를 낮추는 방식은 **금지**한다 — 그러면 제목·항목·체크박스·
///   버튼까지 같이 유령이 되어 "투명하게 했더니 아무것도 안 보인다"가 된다. 투명도는
///   (1) SwiftUI 가 얹는 틴트의 알파(`tintAlpha`)와 (2) 블러 뷰의 알파(`blurAlpha`), 이 두 겹으로만
///   표현하고 그 위의 콘텐츠는 한 톨도 건드리지 않는다.
///
///   ☠︎ 배선 함정: 계층이 `panel.contentView = effect` → `effect.addSubview(hosting)` 이면
///   **`effect.alphaValue` 가 하위 뷰(=글자)까지 그대로 먹는다**. `blurAlpha` 를 쓰려면 블러 뷰와
///   호스팅 뷰를 형제로 재배치해야 한다(자세한 건 `blurAlpha` 주석).
///
/// 왜 값이 하나뿐인가: 사용자가 아는 개념은 "이 창 얼마나 투명하게" 하나다. 틴트와 블러를 따로 노출하면
/// 둘의 조합 중 대부분이 못 쓰는 상태(블러만 남아 뿌옇고 글자는 안 읽히는 등)라, 조절기 두 개를 주는 순간
/// 사용자가 스스로 망가진 조합에 도달한다. 그래서 손잡이는 `opacity` 하나로 두고 나머지는 전부 파생한다.
struct TodoBoardAppearance: Equatable, Sendable {
    /// 사용자가 만지는 유일한 값. 의미는 "보드가 뒤를 얼마나 가리는가"(1에 가까울수록 불투명).
    ///
    /// 범위 밖 값이 들어와도 파생 프로퍼티는 전부 `clamped(opacity)` 를 거치므로 화면이 깨지지 않는다.
    /// (직접 대입이 가능한 `var` 라서 그렇다 — 스토어를 거치지 않는 경로가 있는 한 방어는 여기 있어야 한다.)
    var opacity: Double

    init(opacity: Double = TodoBoardAppearance.defaultOpacity) {
        self.opacity = opacity
    }

    // MARK: - 범위

    // 아래 숫자들은 전부 **대비비**에서 나왔고, 그 대비비는 `textContrast` 가 실제로 계산한다(주석 전용 숫자 아님).
    // 최악 케이스는 "뒤가 순백 바탕화면"이다(보드는 어두운 테마 고정 + 반투명 흰 글자라, 뒤가 밝을수록
    // 글자가 배경에 잠긴다).
    //
    // ☠︎ 이 표는 **재보정된 값이다.** 이전 판은 hudWindow 다크 재질의 틴트 색을 순흑으로 가정해
    // 0.55 에서 5.93:1 이 나온다고 적었지만, 오프스크린 합성으로 렌더 픽셀을 직접 재 보니 재질 틴트 색은
    // 0.283(순백 위 합성 0.713)이었고 실제 대비는 **4.90:1** 이었다. 아래 `textContrast` 는 그 실측 상수로
    // 계산하며, 뷰 담당이 렌더 픽셀에서 잰 표(0.45→4.05 / 0.55→4.90 / 0.62→5.61 / 0.72→6.90)를
    // ±0.02 안으로 재현한다. 순흑 가정 시절의 숫자는 전부 폐기됐다.
    //
    // 블러 온전(blurAlpha=1) · 순백 바탕화면에서의 primaryText 대비비:
    //   0.45 → 4.06   0.50 → 4.46   0.52 → 4.63   0.55 → 4.91   0.62 → 5.63   0.95 → 10.98
    // 즉 **AA(4.5:1) 돌파선은 0.5047** 이다(이전 판이 적어 둔 0.38 이 아니다).
    //
    // 그리고 블러가 걷히는 구간에서는 재질의 틴트 기여도 같이 사라지므로 실제 대비는 위 표보다 더 나쁘다.
    // 이 파일의 최종 곡선(무릎점 0.52 기준, 순백 바탕):
    //   op    blur    본문   보조   뒤 통과(그중 선명)
    //   0.55  1.000   4.91   3.43    27% ( 0%)   ← 출고 기본값
    //   0.52  1.000   4.63   3.27    29% ( 0%)   ← 무릎점 = 그림자 임계
    //   0.50  0.908   4.26   3.05    32% ( 5%)
    //   0.45  0.691   3.45   2.58    40% (17%)
    //   0.40  0.494   2.80   2.19    48% (30%)
    //   0.35  0.321   2.31   1.88    57% (44%)
    //   0.30  0.175   1.92   1.63    65% (58%)
    //   0.25  0.062   1.63   1.44    73% (70%)
    //   0.20  0.000   1.43   1.30    80% (80%)   ← 하한
    //
    // 참고로 secondaryText(흰색 알파 0.68)는 출고값 0.55 에서 3.43:1 로 본문 AA 미달이고, 4.5:1 에 닿으려면
    // 0.72 까지 올려야 한다(= 사실상 조절 불가). 이건 이 기능이 만든 문제가 아니라 CheckTheme 이 원래 갖고
    // 있던 값이라, 여기서 하한을 그 기준까지 끌어올리지 않는다(그러면 "조절해봤자 그대로"가 된다).
    // 대신 큰 글자 기준 3:1 은 출고값에서 지켜지고, 그 선은 테스트가 지킨다.

    /// 가장 투명. 틴트 0.20 + 블러 0 이면 뒤 화면이 **80% 그대로(전부 선명하게)** 통과한다.
    ///
    /// **하한을 정하는 기준이 무엇인가**가 재보정에서 갈렸다. 서로 다른 두 하한을 구분해야 한다:
    /// · **그림자 없이 읽히는 최저선 = 0.5047**(위 표의 AA 돌파선). 이걸 하한으로 쓰면 조절 범위가
    ///   0.50~0.95 가 되어 "투명하게"가 한 번도 투명해지지 않는다 — 기능 자체가 무의미해진다.
    /// · **그림자를 전제한 하한.** 그림자는 글자 뒤에 깔리는 **어두운 헤일로**라, 배경이 아무리 밝아도
    ///   글리프 가장자리에서 국소 대비를 만든다(macOS 바탕화면 아이콘 이름표가 흰 벽지 위에서도 읽히는 원리).
    ///   즉 글자 가독은 이 구간에서 배경 대비의 함수가 아니다.
    ///   ⚠︎ 헤일로가 실제로 몇 :1 을 회복시키는지는 **아직 실측 없음**(뷰 담당 측정 대기). 확인되면 이 자리에 적는다.
    ///
    /// 그래서 실제로 하한을 묶는 건 글자가 아니라 **"이게 아직 판으로 보이는가"** 다. 0.20 에서 보드 내부는
    /// 맨 바탕화면 대비 1.46:1 로 남고, 경계는 세 가지가 함께 세운다 — 창 그림자(`panel.hasShadow = true`,
    /// CheckTodoBoardWindow), 1px 흰색 0.18 테두리, 그리고 이 틴트 워시. 0.15 로 내리면 워시가 1.32:1 로
    /// 주저앉아 사실상 테두리 한 줄만 남고, 그 순간 뒤 창의 글자와 내 보드의 글자가 같은 평면에 섞인다.
    static let minOpacity: Double = 0.20

    /// 가장 불투명. 1.0 을 주지 않는 이유는 읽기가 아니라 **정체성**이다 — 0.95 와 1.00 의 대비비 차이는
    /// 10.98 vs 12.07 로 둘 다 AA 를 두 배 이상 넘겨 읽기에는 아무 차이가 없는데, 완전 불투명해지는 순간
    /// 보드는 어두운 편집기 위에 얹힌 '그 편집기의 일부'처럼 보인다(경계가 사라진다). 3% 만 남겨 두면
    /// 뒤가 미세하게 비쳐 "내 화면 위에 떠 있는 쪽지"라는 단서가 유지된다.
    static let maxOpacity: Double = 0.95

    /// 기본값. **지금 하드코딩되어 있는 값과 같은 0.55** 다. 이 값에서 `blurAlpha` 는 정확히 1.0 이고
    /// `needsTextShadow` 는 false 이므로(무릎점 0.52 위) 설정을 한 번도 만지지 않은 사용자의 화면은
    /// 이 기능 도입 전과 **픽셀 단위로 동일**하다. 새 설정이 조용히 기존 화면을 바꾸는 것만큼 나쁜 회귀는 없다.
    static let defaultOpacity: Double = 0.55

    /// 키보드 1회·스크롤 1틱의 이동량. 범위(0.75)를 **15스텝**에 훑는다 —
    /// 끝에서 끝까지 스크롤 한 번 반, 방향키로도 15번이면 닿는 거리다. 스텝을 더 잘게(0.02) 두면
    /// 한 번 눌러서는 변화가 안 보여 "안 먹네" 하고 연타하게 되고, 더 굵게(0.10) 두면 원하는 지점을 지나친다.
    /// 0.05 는 `percentLabel` 이 5% 눈금(20%, 25% …)에 정확히 떨어져 표시가 흔들리지 않는 값이기도 하다.
    static let step: Double = 0.05

    /// 블러가 걷히기 시작하는 지점이자 `needsTextShadow` 임계. **같은 숫자인 것이 설계다**(따로 두면 갈라진다).
    ///
    /// ☠︎ **재보정: 0.45 → 0.52.** 이전 판은 "무릎점 위에서는 블러가 대비를 떠받치므로 걷지 않는다"였는데,
    /// 실측으로는 0.45 자체가 이미 4.06:1 로 **AA 미달**이었다 — 떠받칠 것이 없는 자리에 무릎을 놓고 있었다.
    /// 실제 AA 돌파선은 0.5047 이므로 무릎점은 그 위여야 한다.
    ///
    /// 그러면 두 보증이 정면으로 부딪힌다:
    /// · "무릎점 위는 AA 안전" → 무릎점 ≥ 0.5047
    /// · "기본값 0.55 의 화면은 픽셀 동일" → 무릎점 < 0.55 (같아도 성립하지만, 부동소수 경계에 기본 화면을
    ///   올려 두면 반올림 하나로 출고 그림이 바뀔 수 있어 **엄격히 아래**로 둔다)
    /// 다행히 둘 다 만족하는 창이 있다: **[0.505, 0.549]**. 그 안에서 0.52 를 골랐다 —
    /// 무릎점에서의 대비가 4.63:1 이라 실측 오차(모델이 렌더 픽셀을 ±0.02 로 재현한다) 대비 여유가 있고,
    /// 기본값과는 0.03 떨어져 있어 경계가 기본 화면에 닿지 않는다. 0.51 은 4.55:1 로 여유가 거의 없고,
    /// 0.54 는 4.81:1 로 이미 AA 를 넉넉히 넘긴 구간에서 그림자를 켜게 된다(이유 없는 시각적 잡음).
    ///
    /// 여기를 경계로 성격이 갈린다:
    /// · 무릎점 **위**: 블러가 온전해야 대비가 성립한다(0.52 에서 블러를 절반만 걷어도 4.63 → 4.0 아래로 내려간다).
    ///   AA 를 보증하는 유일한 근거가 재질 틴트이므로 여기서는 손대지 않는다.
    /// · 무릎점 **아래**: 블러를 온전히 둬도 이미 AA 미달이다. 가독은 그림자에게 넘어갔고 블러가 지키는 것은
    ///   뿌연 안개뿐이다 — 그래서 여기서만 걷어낸다.
    ///
    /// ⚠︎ 부작용 하나는 정직하게 적어 둔다: 무릎점이 0.05 스텝 격자(0.55·0.50·0.45…) 위에 있지 않다.
    /// 기본값에서 한 칸 내린 0.50 은 무릎점 바로 아래(0.02)라 블러가 1.000 → 0.908 로 거의 안 움직인다.
    /// 그 스텝의 눈에 보이는 응답은 틴트가 옅어지는 것과 그림자가 켜지는 것이고, 블러의 체감 변화는
    /// 그다음 칸(0.45, 0.691)부터다. 격자에 맞추려면 무릎을 0.50 으로 내려야 하는데 그 자리는 4.46:1 로
    /// AA 미달이라, **AA 를 스텝 감각보다 우선했다.**
    static let blurKnee: Double = 0.52

    // MARK: - 정규화

    /// 사용자 입력을 레일 안으로 넣는다. **슬라이더/스크롤이 끝을 넘어가도 끝에 붙어 있으라는 뜻**이다.
    ///
    /// NaN 만 기본값으로 되돌린다 — NaN 은 방향 정보가 아예 없는 '고장난 값'이라 어느 끝으로 붙여도 근거가 없다.
    /// 반대로 ±무한대는 방향이 분명하므로 그쪽 끝으로 붙인다(`min`/`max` 가 그대로 처리한다).
    ///
    /// 마지막에 0.1% 격자로 반올림하는 이유: 슬라이더가 주는 Double 에는 눈으로도 UI 로도 표현 못 하는
    /// 부동소수 먼지가 붙는다. 그대로 두면 `!=` 비교가 아무도 못 알아채는 변화에 반응해 매 프레임
    /// UserDefaults 쓰기와 창 다시 그리기가 돌고, `nudge` 를 반복하면 오차가 쌓여 끝값이 `maxOpacity` 와
    /// 같지 않게 된다. 750단계면 어떤 조절기보다도 촘촘하다.
    static func clamped(_ value: Double) -> Double {
        guard !value.isNaN else { return defaultOpacity }
        let bounded = min(max(value, minOpacity), maxOpacity)
        return (bounded * 1000).rounded() / 1000
    }

    // MARK: - 파생값(화면이 실제로 쓰는 것)

    /// SwiftUI 가 얹는 틴트(`CheckTheme.panel`)의 알파. 사용자 값을 그대로 쓴다 —
    /// `opacity` 라는 이름이 가리키는 대상이 원래 이 틴트이고, 그래야 기본값 0.55 가 기존 코드와 1:1 로 맞는다.
    var tintAlpha: Double { Self.clamped(opacity) }

    /// 블러 뷰(`NSVisualEffectView`)의 `alphaValue`.
    ///
    /// **이 값이 이 파일의 존재 이유다.** 틴트만 낮추면 블러가 그대로 남아 결과가 "뒤가 보인다"가 아니라
    /// **"뿌옇다"**가 된다 — 뒤 화면의 글자·아이콘은 여전히 못 알아보는데 보드만 허옇게 뜬, 아무도 원하지 않는
    /// 상태다. 진짜 투명해지려면 낮은 구간에서 블러도 같이 걷혀야 한다.
    ///
    /// 수식(op = clamped(opacity)):
    ///   op ≥ blurKnee(0.52) → 1.0
    ///   op < blurKnee       → t = (op - minOpacity) / (blurKnee - minOpacity),  blurAlpha = t^1.5
    /// t 는 무릎점에서 1, 하한에서 0 이라 무릎점에서 값이 정확히 1.0 으로 이어진다(경계에서 안 튄다:
    /// op = 0.519 에서 0.995).
    ///
    /// 왜 선형이 아니라 t^1.5 인가 — **알파 1.0 → 0.8 구간은 눈에 보이지 않기 때문**이다. 흐린 사본이 8할이나
    /// 섞여 있으면 뒤 화면의 고주파(글자)는 여전히 뭉개져 '서리 낀 유리'로 읽힌다. 서리 인상이 실제로 풀리는
    /// 곳은 알파 0.4~0.7 언저리다. t^1.5 는 무릎점 근처에서 선형보다 빠르게 떨어져(기울기 1.5배) 그 구간을
    /// 빨리 통과하고, 대신 하한 근처에서는 완만해져(0.25 에서 0.062) 마지막 한 스텝에 블러가 툭 사라지는
    /// 계단이 없다.
    /// 스텝별 값: 0.52→1.000, 0.50→0.908, 0.45→0.691, 0.40→0.494, 0.35→0.321, 0.30→0.175, 0.25→0.062, 0.20→0.000.
    /// (뒤 화면 통과율로는 29% → 32% → 40% → 48% → 57% → 65% → 73% → 80%,
    ///  그중 **선명한** 몫이 0% → 5% → 17% → 30% → 44% → 58% → 70% → 80%.)
    ///
    /// ☠︎ 배선: `effect.alphaValue = CGFloat(blurAlpha)` 를 호스팅 뷰가 블러 뷰의 하위 뷰인 계층에서 하면
    /// **글자까지 흐려진다**. 투명한 컨테이너를 contentView 로 두고 블러 뷰와 호스팅 뷰를 형제로 얹은 뒤,
    /// 블러 뷰에만 알파를 걸어야 이 파일 맨 위의 원칙("글자는 항상 100%")이 지켜진다.
    var blurAlpha: Double {
        let op = Self.clamped(opacity)
        guard op < Self.blurKnee else { return 1.0 }
        let t = (op - Self.minOpacity) / (Self.blurKnee - Self.minOpacity)
        return min(max(pow(t, 1.5), 0), 1)
    }

    /// 보드 **위에 얹힌 표면**(입력창·배지·캡슐·버튼 원·완료 원 채움)의 알파 배율.
    ///
    /// ☠︎ 이 값이 없으면 어떤 일이 벌어지는지가 실사용 신고로 확인됐다 — "투명도를 올리면 대부분을 차지하는
    /// 컬러는 투명해지는데 **할 일 추가하는 박스는 오히려 더 진해진다**". 원인은 층 구조다:
    /// 바탕 틴트만 `tintAlpha` 에 연동돼 있고 그 위 표면들은 전부 고정 알파였다. 특히
    /// `CheckTheme.fieldFill` 은 **검정**(0.20)이라, 바탕이 걷혀 뒤의 밝은 화면이 올라올수록
    /// 그 검정만 그대로 남아 대비가 커진다 — 사용자 눈에는 박스가 "더 진해지는" 것으로 보인다.
    ///
    /// 수식(op = clamped(opacity)): `min(op / defaultOpacity, 1)`.
    /// 왜 기준이 기본값인가 — 바탕 틴트가 화면에 **더하는 어두움**은 `op` 에 비례하므로, 표면이 바탕과
    /// 같은 비율로 옅어지려면 배율이 `op / (출고 op)` 여야 한다. 출고값에서 정확히 1.0 이 되는 것이 핵심이다:
    /// 이 프로젝트에는 "설정을 안 만진 사용자 화면은 도입 전과 픽셀 동일"이라는 보증이 있고, 배율이
    /// 1.0 이 아니면 그 보증이 이 값 하나 때문에 깨진다. 위쪽은 1.0 에서 자른다 — 불투명하게 미는 조작이
    /// 표면을 출고보다 **더 진하게** 만들 이유는 없다(그러면 반대 방향의 같은 신고가 생긴다).
    /// 값: 0.20→0.364, 0.50→0.909, 0.52→0.945, 0.55→1.000, 0.95→1.000.
    ///
    /// ★ **곱하지 않는 것**(의도적 제외):
    /// · 글자 — 가독이 전부다. 글자 알파를 건드리는 순간 이 파일 맨 위의 원칙이 무너진다.
    /// · 선(테두리)과 글리프 — 면과 달리 면적이 거의 없어 밝기 기여가 무시할 만한 대신, 낮은 투명도에서
    ///   "여기 무언가 있다"를 남기는 유일한 단서다. 특히 체크 원의 테두리와 포커스 입력창의 accent 테두리는
    ///   채움이 옅어질수록 오히려 **더 중요해진다**(면이 사라져도 어포던스가 남는다).
    var surfaceAlpha: Double {
        min(Self.clamped(opacity) / Self.defaultOpacity, 1.0)
    }

    /// 투명도가 낮아 흰 글자가 밝은 바탕에 묻힐 구간인가.
    ///
    /// 무릎점(0.52) 미만이면 최악 케이스(순백 바탕화면)에서 primaryText 대비가 AA 4.5:1 아래로 내려간다
    /// (실측 돌파선 0.5047, 무릎점은 그 위에 여유를 두고 놓았다 — `blurKnee` 주석 참고).
    /// 그 아래는 배경으로 대비를 만들 수 없는 구간이므로 **글자 쪽에 그림자를 깔아** 글리프 가장자리에서
    /// 국소 대비를 만든다(macOS 바탕화면 아이콘 이름표가 임의의 배경 위에서 읽히는 것과 같은 수법).
    /// 그림자는 글자의 **불투명도를 건드리지 않는다** — 어디까지나 글자 뒤에 깔리는 어두운 헤일로다.
    ///
    /// 출고 기본값 0.55 는 4.91:1 로 AA 를 넘으므로 여기서 false 다. 그게 "설정을 안 만진 사용자의 화면은
    /// 도입 전과 픽셀 동일"의 절반이다(나머지 절반은 `blurAlpha == 1.0`).
    var needsTextShadow: Bool { Self.clamped(opacity) < Self.blurKnee }

    /// UI 표시용 문자열("55%"). 격자가 0.1% 라 반올림 오차로 55%/56% 를 오가지 않는다.
    var percentLabel: String { "\(Int((Self.clamped(opacity) * 100).rounded()))%" }

    // MARK: - 대비(이 설정이 실제로 만드는 화면의 숫자)

    /// 이 설정으로 그린 보드 배경의 sRGB 성분. 합성 순서는 화면과 같다:
    /// 바탕 → (블러 알파만큼의) hudWindow 재질 → `CheckTheme.panel` 을 `tintAlpha` 로 한 겹.
    var backgroundLevel: (r: Double, g: Double, b: Double) {
        let behind = TodoBoardTint.materialLevel(over: 1.0, blurAlpha: blurAlpha)
        return Self.blend(TodoBoardTint.panelRGB, over: Self.gray(behind), alpha: tintAlpha)
    }

    /// 이 설정의 보드 위에 얹힌 **반투명 흰 글자**의 WCAG 대비비.
    ///
    /// 글자를 배경 위에 먼저 합성한 뒤 재는 것이 핵심이다 — `CheckTheme.primaryText` 는 알파 0.94 라
    /// 배경이 밝아지면 글자도 같이 밝아진다. 불투명 흰색으로 계산하면 실제보다 좋은 숫자가 나온다.
    ///
    /// - Parameters:
    ///   - textAlpha: 글자 색의 흰색 알파(기본은 본문).
    ///   - backdrop: 보드 뒤 화면의 밝기. 기본 1.0 = 순백 바탕화면 = **최악 케이스**.
    func textContrast(
        textAlpha: Double = TodoBoardTint.primaryTextAlpha,
        backdrop: Double = 1.0
    ) -> Double {
        Self.textContrast(
            tintAlpha: tintAlpha,
            blurAlpha: blurAlpha,
            textAlpha: textAlpha,
            backdrop: backdrop
        )
    }

    /// 위와 같은 계산이지만 두 겹의 알파를 직접 준다. 뷰 담당이 렌더 픽셀에서 잰 표는 "블러 온전"
    /// 조건이라, 그 표와 대조하려면 `blurAlpha` 를 1 로 고정해 부를 수 있어야 한다.
    static func textContrast(
        tintAlpha: Double,
        blurAlpha: Double,
        textAlpha: Double = TodoBoardTint.primaryTextAlpha,
        backdrop: Double = 1.0
    ) -> Double {
        let behind = TodoBoardTint.materialLevel(over: backdrop, blurAlpha: blurAlpha)
        let background = blend(TodoBoardTint.panelRGB, over: gray(behind), alpha: tintAlpha)
        let text = blend(gray(1.0), over: background, alpha: textAlpha)
        return TodoBoardContrast.ratio(text, background)
    }

    /// 알파 합성 한 겹(sRGB **성분** 공간). CoreGraphics 가 sRGB 컨텍스트에서 하는 것과 같은 연산이라
    /// 렌더 픽셀 실측과 값이 맞는다 — 선형광 공간에서 섞으면 같은 재질이 다른 숫자로 나와 실측과 어긋난다.
    private static func blend(
        _ color: (r: Double, g: Double, b: Double),
        over backdrop: (r: Double, g: Double, b: Double),
        alpha: Double
    ) -> (r: Double, g: Double, b: Double) {
        let a = min(max(alpha, 0), 1)
        return (
            r: a * color.r + (1 - a) * backdrop.r,
            g: a * color.g + (1 - a) * backdrop.g,
            b: a * color.b + (1 - a) * backdrop.b
        )
    }

    private static func gray(_ level: Double) -> (r: Double, g: Double, b: Double) {
        (r: level, g: level, b: level)
    }
}

// MARK: - 영속 스토어

/// 보드 투명도의 주인. 값 하나를 UserDefaults 에 남기고, 바뀔 때만 알린다.
///
/// `@Observable` 을 붙인 이유는 설정 UI(슬라이더) 때문이다. 콜백(`onChange`)은 SwiftUI 바깥에서 사는
/// AppKit 쪽(블러 뷰 알파)이 쓰고, 관찰은 SwiftUI 쪽이 쓴다 — 두 소비자의 갱신 방식이 달라서 둘 다 둔다.
@MainActor
@Observable
final class TodoBoardAppearanceStore {
    /// 저장 키. 값 하나(Double)만 담는다 — 구조체를 JSON 으로 말아 넣으면 나중에 필드가 늘 때
    /// 디코드 실패 = 설정 통째 소실이 되지만, 숫자 하나는 어떤 버전이 읽어도 숫자 하나다.
    static let defaultsKey = "check.todoBoardOpacity"

    private let defaults: UserDefaults

    private(set) var appearance: TodoBoardAppearance

    /// 값이 **실제로 바뀌었을 때만** 불린다. 창(블러 알파)·뷰가 여기에 매달리므로 같은 값 재통지는
    /// 드래그 한 번에 수십 번의 창 다시 그리기가 된다.
    var onChange: ((TodoBoardAppearance) -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.appearance = TodoBoardAppearance(opacity: Self.restoredOpacity(from: defaults))
    }

    // MARK: - 복원

    /// 저장된 값을 읽는다. **읽기는 clamp 가 아니라 검증이다** — 살아 있는 조작(clamp: 끝을 넘으면 끝에 붙임)과
    /// 일부러 다르게 만들었다.
    ///
    /// 이유: 범위 밖 숫자가 디스크에 있다는 건 그 값을 쓴 쪽이 **다른 단위/다른 범위**를 썼다는 뜻이다
    /// (예전 버전이 0~100 퍼센트로 썼거나, `defaults write` 로 0 을 넣었거나). 그걸 끝값으로 접어 넣으면
    /// 사용자가 고른 적 없는 극단(거의 안 보이는 보드 / 꽉 막힌 보드)에서 앱이 시작한다 —
    /// 하필 그 두 끝이 "앱이 고장 났다"로 보이는 상태다. 신뢰할 수 없는 값이면 **기본값으로 돌아간다.**
    ///
    /// 문자열도 받아 준다: `defaults write <domain> check.todoBoardOpacity 0.3` 은 타입을 안 주면
    /// **문자열**을 쓴다. 숫자로 읽히는 문자열까지 거절하면 안내대로 따라 한 사용자가 "안 먹는다"를 겪는다.
    private static func restoredOpacity(from defaults: UserDefaults) -> Double {
        guard let stored = storedNumber(in: defaults),
              stored.isFinite,
              stored >= TodoBoardAppearance.minOpacity,
              stored <= TodoBoardAppearance.maxOpacity
        else {
            return TodoBoardAppearance.defaultOpacity
        }
        return TodoBoardAppearance.clamped(stored)
    }

    /// 저장소에 실제로 들어 있는 것을 숫자로 해석한다(해석 불가면 nil).
    ///
    /// `double(forKey:)` 를 쓰지 않는 이유: 그 API 는 **키가 없을 때와 0 이 저장됐을 때 똑같이 0** 을 준다.
    /// 우리는 "설정한 적 없음(→기본값)"과 "0 이라는 쓰레기가 저장됨(→기본값)"을 구분해서 다루지는 않지만,
    /// 문자열/불리언 같은 다른 타입을 걸러내려면 어차피 원본 객체를 봐야 한다.
    private static func storedNumber(in defaults: UserDefaults) -> Double? {
        switch defaults.object(forKey: defaultsKey) {
        case let number as NSNumber: return number.doubleValue
        case let text as String: return Double(text)
        default: return nil
        }
    }

    // MARK: - 조작

    /// 사용자 조작 진입점. clamp → 저장 → **값이 실제로 바뀐 경우에만** 통지.
    ///
    /// NaN 은 통째로 무시한다(clamp 처럼 기본값으로 되돌리지 않는다) — 바인딩이 잠깐 NaN 을 흘렸다고
    /// 사용자가 맞춰 둔 값이 0.55 로 리셋되면, 원인 모를 설정 초기화로 보인다. 조작이 아니면 아무 일도 없어야 한다.
    func setOpacity(_ value: Double) {
        guard !value.isNaN else { return }
        let next = TodoBoardAppearance.clamped(value)
        guard next != appearance.opacity else { return }
        appearance.opacity = next
        defaults.set(next, forKey: Self.defaultsKey)
        onChange?(appearance)
    }

    /// 스크롤/키보드용 상대 조절(양수 = 더 불투명). 호출자가 `TodoBoardAppearance.step` 에 방향(과 스크롤이면
    /// 틱 수)을 곱해 넘긴다.
    ///
    /// 유한하지 않은 델타는 버린다. 스크롤 이벤트의 델타는 드라이버·제스처에 따라 튀는 값이 실제로 나오는데,
    /// 무한대를 그대로 더하면 사용자가 살짝 굴린 한 번에 끝값으로 순간이동한다.
    func nudge(by delta: Double) {
        guard delta.isFinite else { return }
        setOpacity(appearance.opacity + delta)
    }
}
