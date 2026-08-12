import AppKit
import Foundation
import SwiftUI
import Testing
@testable import check

// 할 일 보드 투명도 **설정 모델**의 계약.
//
// 여기서 지키는 것은 네 가지다:
// 1) 사용자가 무엇을 넣든(범위 밖·NaN·무한대) 화면이 계산 불가 값으로 넘어가지 않는다.
// 2) 디스크에 남은 쓰레기값(예전 버전·`defaults write`)에 앱이 이상한 극단에서 시작하지 않는다.
// 3) 파생값(틴트/블러/그림자/표시문구)이 **한 개의 손잡이**에서만 나온다 — 특히 블러는 낮은 구간에서
//    실제로 걷혀야 한다(안 걷히면 "투명"이 아니라 "뿌옇다"가 되고, 그게 이 기능이 생긴 이유다).
// 4) **대비가 무너지는 순간 여기서 죽는다.** 이 파일의 상수는 전부 WCAG 대비비에서 나왔는데, 근거가
//    주석에만 있으면 다음 사람이 상수를 옮길 때 아무 경보도 울리지 않는다. 그래서 대비를 계산하는
//    함수가 코드에 있고(`TodoBoardAppearance.textContrast`), 아래 테스트가 그 값을 상수와 묶는다.
//
// 스위트로 감싼 이유는 이름 충돌 방지다 — 같은 시기에 보드 관련 테스트 파일이 여러 개 자라는데
// 최상위 @Test 함수(와 파일 전역 헬퍼) 이름이 하나라도 겹치면 모듈이 통째로 컴파일되지 않는다.
@MainActor
@Suite struct CheckTodoBoardAppearanceTests {

    // MARK: - 헬퍼

    /// 실제 사용자 설정(.standard)을 절대 건드리지 않는 일회용 저장소. 실패로 빠져나가도 반드시 지운다.
    private func withTestDefaults(_ body: @MainActor (UserDefaults) throws -> Void) rethrows {
        let suiteName = "check-todo-board-appearance-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            UserDefaults.standard.removeSuite(named: suiteName)
        }
        try body(defaults)
    }

    private func appearance(_ opacity: Double) -> TodoBoardAppearance {
        TodoBoardAppearance(opacity: opacity)
    }

    /// 순백 바탕화면 위, **블러 온전** 조건의 본문 대비. 뷰 담당이 렌더 픽셀에서 잰 표와 같은 조건이라
    /// 이 헬퍼로만 그 표와 대조할 수 있다(실제 곡선은 무릎 아래에서 블러가 걷혀 더 나쁘다).
    private func contrastWithBlurIntact(_ opacity: Double, textAlpha: Double) -> Double {
        TodoBoardAppearance.textContrast(tintAlpha: opacity, blurAlpha: 1, textAlpha: textAlpha)
    }

    /// 본문이 AA 4.5:1 을 처음 넘어서는 틴트 값(블러 온전). **리터럴이 아니라 대비 함수에서 찾는다** —
    /// 이래야 대비 계산을 상수로 바꿔치기하는 변형이 이 탐색까지 함께 무너뜨린다.
    private var aaBodyCrossing: Double {
        var low = TodoBoardAppearance.minOpacity
        var high = TodoBoardAppearance.maxOpacity
        for _ in 0..<60 {
            let mid = (low + high) / 2
            if contrastWithBlurIntact(mid, textAlpha: TodoBoardTint.primaryTextAlpha)
                < TodoBoardContrast.aaBodyText {
                low = mid
            } else {
                high = mid
            }
        }
        return high
    }

    private func srgb(_ color: Color) -> (r: Double, g: Double, b: Double, a: Double)? {
        guard let converted = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        return (
            Double(converted.redComponent),
            Double(converted.greenComponent),
            Double(converted.blueComponent),
            Double(converted.alphaComponent)
        )
    }

    // MARK: - 실측 상수(정본)

    /// 같은 물리량이 두 벌로 갈라지면 **대비 기준이 두 개**가 된다(그린 그림은 A, 판정은 B).
    /// hudWindow 재질의 합성 결과는 (틴트 알파·틴트 색)에서 유도되는 값이면서 동시에 렌더 픽셀 실측값이라,
    /// 그 두 표현이 어긋나는 순간 어느 쪽도 사실이 아니게 된다.
    @Test func materialConstantsStayOneNumber() {
        let composed = TodoBoardTint.materialTintAlpha * TodoBoardTint.materialTintWhite
            + (1 - TodoBoardTint.materialTintAlpha) * 1.0
        // 유도값(0.7132) vs 실측 리터럴(0.713). 실측 정밀도(소수 셋째 자리) 안에서 같아야 한다.
        #expect(abs(composed - TodoBoardTint.hudOverWhiteLevel) < 0.001)
        // 재질 틴트는 **순흑이 아니다**. 이 사실 하나가 이전 판의 대비 계산을 통째로 틀리게 만들었다.
        #expect(TodoBoardTint.materialTintWhite > 0.25)
        // `materialLevel` 도 같은 숫자를 내야 한다(블러 온전, 순백 바탕).
        #expect(abs(TodoBoardTint.materialLevel(over: 1.0) - TodoBoardTint.hudOverWhiteLevel) < 0.001)
        // 블러가 완전히 걷히면 재질이 사라져 바탕이 그대로 드러난다 — 낮은 구간 대비가 나빠지는 이유다.
        #expect(TodoBoardTint.materialLevel(over: 1.0, blurAlpha: 0) == 1.0)
        // Color 판과 스칼라 판도 한 숫자에서 나온다.
        #expect(srgb(TodoBoardTint.hudOverWhite).map { abs($0.r - TodoBoardTint.hudOverWhiteLevel) < 0.002 } == true)
        // 뷰가 그리는 출고 틴트와 모델의 기본값도 한 숫자다.
        #expect(TodoBoardTint.opacity == TodoBoardAppearance.defaultOpacity)
    }

    /// 대비 계산은 CheckTheme 의 색을 숫자로 되비춘 상수를 쓴다(SwiftUI Color 는 성분을 못 꺼낸다).
    /// 테마 쪽 색이 바뀌면 이 복제본이 조용히 낡아 **대비 판정만 옛 색으로 남는다** — 여기서 잡는다.
    @Test func themeMirrorsMatchCheckTheme() throws {
        let panel = try #require(srgb(CheckTheme.panel))
        #expect(abs(panel.r - TodoBoardTint.panelRGB.r) < 0.002)
        #expect(abs(panel.g - TodoBoardTint.panelRGB.g) < 0.002)
        #expect(abs(panel.b - TodoBoardTint.panelRGB.b) < 0.002)

        let primary = try #require(srgb(CheckTheme.primaryText))
        #expect(abs(primary.a - TodoBoardTint.primaryTextAlpha) < 0.002)
        let secondary = try #require(srgb(CheckTheme.secondaryText))
        #expect(abs(secondary.a - TodoBoardTint.secondaryTextAlpha) < 0.002)
    }

    // MARK: - 대비

    /// 모델이 **렌더 픽셀과 같은 답**을 내는지가 먼저다. 이게 어긋나면 아래 모든 판정이 상상 위에 선다.
    /// 표는 뷰 담당이 오프스크린 합성(순백 바탕 + hud 블러 포함)으로 잰 정본이다.
    @Test func contrastModelReproducesTheRenderedMeasurements() {
        let measured: [(opacity: Double, body: Double, secondary: Double)] = [
            (0.45, 4.05, 2.93),
            (0.55, 4.90, 3.43),
            (0.62, 5.61, 3.82),
            (0.72, 6.90, 4.51)
        ]
        for row in measured {
            let body = contrastWithBlurIntact(row.opacity, textAlpha: TodoBoardTint.primaryTextAlpha)
            let secondary = contrastWithBlurIntact(row.opacity, textAlpha: TodoBoardTint.secondaryTextAlpha)
            #expect(abs(body - row.body) < 0.05, "본문 \(row.opacity): 모델 \(body) vs 실측 \(row.body)")
            #expect(
                abs(secondary - row.secondary) < 0.05,
                "보조 \(row.opacity): 모델 \(secondary) vs 실측 \(row.secondary)"
            )
        }
        // 흰 글자를 **불투명**으로 계산하면 실제보다 좋은 숫자가 나온다(글자가 알파 0.94 라 배경과 함께 밝아진다).
        // 그 실수를 저지르면 아래 값이 같아진다.
        #expect(
            contrastWithBlurIntact(0.55, textAlpha: 1.0)
                > contrastWithBlurIntact(0.55, textAlpha: TodoBoardTint.primaryTextAlpha) + 0.05
        )
    }

    /// 출고 기본값에서의 본문 대비는 실측 4.90:1 이다. **AA 를 아슬아슬하게 넘는다** —
    /// 기본값을 한 칸이라도 내리면 그림자 없이는 AA 가 깨진다는 뜻이라, 이 숫자 자체가 계약이다.
    @Test func defaultOpacityLandsJustAboveAABodyContrast() {
        let shipped = appearance(TodoBoardAppearance.defaultOpacity)
        #expect(abs(shipped.textContrast() - 4.90) < 0.05)
        #expect(shipped.textContrast() >= TodoBoardContrast.aaBodyText)
        // 여유가 크지 않다는 것도 계약이다(크면 무릎점을 더 내릴 수 있다는 뜻이 된다).
        #expect(shipped.textContrast() < 5.2)
        // 기본값에서는 블러가 온전하므로 실제 곡선과 '블러 온전' 표가 같은 값이어야 한다.
        #expect(shipped.blurAlpha == 1.0)
        #expect(
            abs(shipped.textContrast()
                - contrastWithBlurIntact(TodoBoardAppearance.defaultOpacity,
                                         textAlpha: TodoBoardTint.primaryTextAlpha)) < 1e-9
        )

        // 보조 텍스트는 출고값에서도 본문 AA 미달(3.43)이다. 이건 이 기능이 만든 문제가 아니라
        // CheckTheme 이 원래 갖고 있던 값이라 하한을 그 기준까지 끌어올리지 않는다 —
        // 대신 큰 글자 기준 3:1 은 지켜져야 하고, 그 선이 무너지면 여기서 죽는다.
        let secondary = shipped.textContrast(textAlpha: TodoBoardTint.secondaryTextAlpha)
        #expect(secondary >= TodoBoardContrast.aaLargeText)
        #expect(secondary < TodoBoardContrast.aaBodyText)
    }

    /// **이 파일의 핵심 불변식.** 그림자를 켜지 않는 구간은 전부 배경만으로 AA 본문 대비를 만족해야 한다.
    /// 하나라도 어긋나면 "밝은 바탕화면에서 글자가 안 읽히는데 아무 보정도 안 하는 설정값"이 존재한다는 뜻이다.
    @Test func everyShadowFreeOpacityMeetsAABodyContrast() {
        var worst = (opacity: Double.nan, ratio: Double.infinity)
        var failure: Double?
        var value = TodoBoardAppearance.minOpacity
        while value <= TodoBoardAppearance.maxOpacity + 1e-9 {
            let board = appearance(value)
            if !board.needsTextShadow {
                let ratio = board.textContrast()
                if ratio < worst.ratio { worst = (value, ratio) }
                if ratio < TodoBoardContrast.aaBodyText, failure == nil { failure = value }
            }
            value = ((value + 0.001) * 1000).rounded() / 1000
        }
        let text = failure.map { "\($0)" } ?? "-"
        #expect(failure == nil, "그림자 없이 AA 미달인 값: \(text)")
        // 가장 빠듯한 지점은 무릎점 자신이어야 한다(그보다 아래는 그림자가 켜진다).
        #expect(abs(worst.opacity - TodoBoardAppearance.blurKnee) < 0.002)
    }

    /// 무릎점이 **실측 AA 돌파선 바로 위**에 앉아 있는지. 위아래 양쪽으로 못 박는다:
    /// · 돌파선보다 아래면 → 그림자 없는 AA 미달 구간이 생긴다(위 테스트가 죽는다).
    /// · 돌파선보다 한 스텝 넘게 위면 → AA 를 넉넉히 넘긴 자리에서 그림자를 켜는 것이라 이유 없는 시각적 잡음이고,
    ///   블러가 온전한 구간을 필요 이상으로 넓혀 "투명하게"가 늦게 시작한다.
    @Test func kneeSitsJustAboveTheMeasuredAACrossing() {
        let crossing = aaBodyCrossing
        // 재보정의 알맹이: 돌파선은 이전 판이 적어 둔 0.38 이 아니라 0.50 근처다.
        #expect(abs(crossing - 0.505) < 0.01, "AA 돌파선: \(crossing)")
        #expect(TodoBoardAppearance.blurKnee >= crossing)
        #expect(TodoBoardAppearance.blurKnee - crossing <= TodoBoardAppearance.step)
        // 실측 오차(모델이 렌더 픽셀을 ±0.02 로 재현한다) 대비 여유가 있어야 한다.
        #expect(appearance(TodoBoardAppearance.blurKnee).textContrast() >= TodoBoardContrast.aaBodyText + 0.1)
    }

    /// 무릎점 위에서 블러를 걷으면 AA 가 무너진다 — 그게 "무릎점 위에서는 블러를 손대지 않는다"의 근거다.
    /// (재질 틴트가 AA 를 떠받치는 유일한 근거라, 절반만 걷어도 4.5 아래로 내려간다.)
    @Test func blurIsWhatHoldsUpContrastAboveTheKnee() {
        let knee = TodoBoardAppearance.blurKnee
        #expect(contrastWithBlurIntact(knee, textAlpha: TodoBoardTint.primaryTextAlpha) >= TodoBoardContrast.aaBodyText)
        let halfBlur = TodoBoardAppearance.textContrast(tintAlpha: knee, blurAlpha: 0.5)
        #expect(halfBlur < TodoBoardContrast.aaBodyText)
        let noBlur = TodoBoardAppearance.textContrast(tintAlpha: knee, blurAlpha: 0)
        #expect(noBlur < halfBlur)
    }

    // MARK: - 범위 계약

    /// 상수들의 **순서**가 계약이다. 특히 `blurKnee < defaultOpacity` 가 깨지면 설정을 한 번도 만지지 않은
    /// 사용자의 보드가 이 기능 도입만으로 달라진다(블러가 기본 상태에서 걷히기 시작한다).
    @Test func rangeConstantsKeepTheShippedLookIntact() {
        #expect(TodoBoardAppearance.minOpacity < TodoBoardAppearance.blurKnee)
        #expect(TodoBoardAppearance.blurKnee < TodoBoardAppearance.defaultOpacity)
        #expect(TodoBoardAppearance.defaultOpacity <= TodoBoardAppearance.maxOpacity)
        // 지금 CheckTodoBoardView.boardBackground 에 하드코딩된 값. 바뀌면 기존 화면이 조용히 달라진다.
        #expect(TodoBoardAppearance.defaultOpacity == 0.55)
        // 끝에서 끝까지 정확히 15스텝(스크롤 한 번 반). 이보다 많아지면 "안 움직인다", 적으면 "지나친다".
        let steps = (TodoBoardAppearance.maxOpacity - TodoBoardAppearance.minOpacity) / TodoBoardAppearance.step
        #expect(abs(steps - 15) < 1e-9)
        // 블러가 걷힐 활주로가 최소 4스텝은 있어야 한다. 하한을 무릎점 쪽으로 끌어올리면 곡선 전체가
        // 한두 스텝에 압축돼 "한 칸 눌렀더니 블러가 통째로 사라진다"가 된다.
        #expect(TodoBoardAppearance.blurKnee - TodoBoardAppearance.minOpacity >= 4 * TodoBoardAppearance.step)
    }

    /// 하한의 존재 이유는 대비가 아니라 **"뒤가 진짜로 보이는가"** 다. 그림자가 가독을 넘겨받은 구간이라
    /// 글자 대비로는 하한을 정할 수 없고(그러면 하한이 0.50 이 되어 조절이 무의미해진다), 대신 하한에서
    /// 뒤 화면이 실제로 **선명하게** 통과하는지가 계약이다.
    @Test func theFloorActuallyDeliversTransparency() {
        let floor = appearance(TodoBoardAppearance.minOpacity)
        // 블러가 완전히 걷혀야 뒤가 '뿌옇게'가 아니라 '선명하게' 보인다.
        #expect(floor.blurAlpha == 0)
        // 뒤 화면 중 흐림 없이 통과하는 몫. 하한의 의미가 여기 있다.
        let sharpShare = (1 - TodoBoardAppearance.minOpacity) * (1 - floor.blurAlpha)
        #expect(sharpShare >= 0.75)
        // 그래도 '판'으로는 남아야 한다 — 보드 내부가 맨 바탕화면과 구별되지 않으면 어느 글자가 내 것인지
        // 알 수 없다. 순백 바탕 대비 최소한의 워시(1.4:1 이상)는 남긴다.
        let edge = TodoBoardContrast.ratio(floor.backgroundLevel, (r: 1.0, g: 1.0, b: 1.0))
        #expect(edge >= 1.4)
        // 이 구간은 배경으로 대비를 만들 수 없다(1.43:1). 그래서 반드시 그림자가 켜져 있어야 한다.
        #expect(floor.textContrast() < 2.0)
        #expect(floor.needsTextShadow)
    }

    // MARK: - clamp

    @Test func clampKeepsEveryInputOnTheRails() {
        #expect(TodoBoardAppearance.clamped(-1) == TodoBoardAppearance.minOpacity)
        #expect(TodoBoardAppearance.clamped(0) == TodoBoardAppearance.minOpacity)
        #expect(TodoBoardAppearance.clamped(2) == TodoBoardAppearance.maxOpacity)
        // ±무한대는 '방향이 분명한 값'이라 그쪽 끝에 붙는다.
        #expect(TodoBoardAppearance.clamped(.infinity) == TodoBoardAppearance.maxOpacity)
        #expect(TodoBoardAppearance.clamped(-.infinity) == TodoBoardAppearance.minOpacity)
        // NaN 은 방향 정보가 없다 — 어느 끝에 붙여도 근거가 없으므로 기본값.
        #expect(TodoBoardAppearance.clamped(.nan) == TodoBoardAppearance.defaultOpacity)
        // 레일 안의 값은 손대지 않는다.
        #expect(TodoBoardAppearance.clamped(0.55) == 0.55)
        #expect(TodoBoardAppearance.clamped(0.334) == 0.334)
        // 0.1% 격자로 정규화한다(슬라이더가 흘리는 부동소수 먼지 제거).
        #expect(TodoBoardAppearance.clamped(0.5554) == 0.555)
        #expect(TodoBoardAppearance.clamped(0.5556) == 0.556)
    }

    /// 구조체는 `var opacity` 라 스토어를 거치지 않고도 만들어진다. 그런 값이 그대로 화면 수치로 나가면
    /// 알파 9.0(=완전 불투명) 이나 NaN(=AppKit 에서 그리기 자체가 미정의)이 된다 — 파생값은 전부
    /// 스스로 clamp 해야 한다.
    @Test func derivedValuesSurviveAnOutOfRangeStruct() {
        let tooHigh = appearance(9)
        #expect(tooHigh.tintAlpha == TodoBoardAppearance.maxOpacity)
        #expect(tooHigh.blurAlpha == 1.0)
        #expect(tooHigh.needsTextShadow == false)
        #expect(tooHigh.percentLabel == "95%")
        #expect(tooHigh.textContrast().isFinite)

        let tooLow = appearance(-5)
        #expect(tooLow.tintAlpha == TodoBoardAppearance.minOpacity)
        #expect(tooLow.blurAlpha == 0)
        #expect(tooLow.needsTextShadow)
        #expect(tooLow.percentLabel == "20%")

        let broken = appearance(.nan)
        #expect(broken.tintAlpha == TodoBoardAppearance.defaultOpacity)
        #expect(broken.blurAlpha == 1.0)
        #expect(broken.blurAlpha.isNaN == false)
        #expect(broken.percentLabel == "55%")
        #expect(broken.textContrast().isNaN == false)
    }

    // MARK: - 파생값

    @Test func tintAlphaIsTheUserValueAndLabelReadsAsPercent() {
        #expect(appearance(0.55).tintAlpha == 0.55)
        #expect(appearance(0.334).tintAlpha == 0.334)
        #expect(appearance(TodoBoardAppearance.minOpacity).percentLabel == "20%")
        #expect(appearance(TodoBoardAppearance.defaultOpacity).percentLabel == "55%")
        #expect(appearance(TodoBoardAppearance.maxOpacity).percentLabel == "95%")
        // 반올림 경계. 소수점이 새어 나오거나("33.4%") 방향이 뒤집히면 여기서 죽는다.
        #expect(appearance(0.334).percentLabel == "33%")
        #expect(appearance(0.336).percentLabel == "34%")
    }

    /// 무릎점 위에서는 블러가 온전하고(= AA 대비를 떠받친다), 아래에서만 걷힌다.
    ///
    /// 스텝별 값은 `blurAlpha` 주석의 표가 정본이다. 위아래로 좁게 가둔 이유: 한쪽만 두면
    /// 곡선을 선형으로 바꾸거나 무릎점을 옮기는 변형이 통과해 버린다(둘 다 같은 방향으로 값이 커진다).
    @Test func blurLiftsOnlyBelowTheKnee() {
        #expect(appearance(TodoBoardAppearance.maxOpacity).blurAlpha == 1.0)
        #expect(appearance(TodoBoardAppearance.defaultOpacity).blurAlpha == 1.0)
        #expect(appearance(TodoBoardAppearance.blurKnee).blurAlpha == 1.0)
        // 하한에서는 완전히 걷힌다 — 여기가 "뒤가 선명하게 보인다"를 만드는 유일한 지점이다.
        #expect(appearance(TodoBoardAppearance.minOpacity).blurAlpha == 0)

        let expected: [(opacity: Double, blur: Double)] = [
            (0.50, 0.908), (0.45, 0.691), (0.40, 0.494),
            (0.35, 0.321), (0.30, 0.175), (0.25, 0.062)
        ]
        for row in expected {
            let blur = appearance(row.opacity).blurAlpha
            #expect(abs(blur - row.blur) < 0.05, "블러 \(row.opacity): \(blur) (기대 \(row.blur))")
        }
    }

    // MARK: - 표면 배율

    /// **출고 기본값에서 정확히 1.0.** 이 프로젝트의 '픽셀 동일' 보증이 걸린 한 줄이다 —
    /// 0.999 여도 설정을 한 번도 만지지 않은 사용자의 입력창·배지 색이 도입 전과 달라진다.
    @Test func surfaceAlphaIsExactlyOneAtTheShippedDefault() {
        #expect(appearance(TodoBoardAppearance.defaultOpacity).surfaceAlpha == 1.0)
        // 위쪽은 잘린다. 불투명하게 미는 조작이 표면을 출고보다 **더 진하게** 만들 이유가 없다
        // (그러면 "불투명하게 했더니 입력창만 시커메진다"는 반대 방향의 같은 신고가 생긴다).
        #expect(appearance(TodoBoardAppearance.maxOpacity).surfaceAlpha == 1.0)
        #expect(appearance(0.60).surfaceAlpha == 1.0)
        // 기본값 바로 아래부터는 1 보다 작아진다(경계가 열려 있어야 조절이 즉시 반응한다).
        #expect(appearance(TodoBoardAppearance.defaultOpacity - 0.001).surfaceAlpha < 1.0)
    }

    /// 배율은 **바탕 틴트와 같은 비율**이어야 한다. 리터럴 표가 아니라 `tintAlpha` 와의 관계로 못 박는다 —
    /// 그래야 기본값이 바뀌어도 "표면은 바탕과 같은 비율로 옅어진다"는 뜻이 살아 있다.
    @Test func surfaceAlphaTracksTheTintRelativeToTheShippedTint() {
        var value = TodoBoardAppearance.minOpacity
        while value <= TodoBoardAppearance.maxOpacity + 1e-9 {
            let board = appearance(value)
            let expected = min(board.tintAlpha / TodoBoardAppearance.defaultOpacity, 1.0)
            #expect(abs(board.surfaceAlpha - expected) < 1e-12, "투명도 \(value)")
            value = ((value + 0.001) * 1000).rounded() / 1000
        }
        // 실측 대조표(주석에 적힌 값이 실제로 나오는지).
        #expect(abs(appearance(TodoBoardAppearance.minOpacity).surfaceAlpha - 0.364) < 0.001)
        #expect(abs(appearance(0.50).surfaceAlpha - 0.909) < 0.001)
        #expect(abs(appearance(TodoBoardAppearance.blurKnee).surfaceAlpha - 0.945) < 0.001)
    }

    /// 하한에서도 표면이 완전히 사라지지는 않는다. 0 이 되면 입력창이 '면 없는 테두리'가 되어
    /// 어디를 눌러야 하는지가 테두리 한 줄에만 남는다 — 그건 이 수정이 노린 결과가 아니다.
    @Test func surfaceAlphaStaysVisibleAtTheFloorAndNeverGoesBackwards() {
        #expect(appearance(TodoBoardAppearance.minOpacity).surfaceAlpha > 0.3)
        var previous = -1.0
        var brokenAt: Double?
        var value = TodoBoardAppearance.minOpacity
        while value <= TodoBoardAppearance.maxOpacity + 1e-9 {
            let alpha = appearance(value).surfaceAlpha
            if alpha < previous - 1e-12, brokenAt == nil { brokenAt = value }
            previous = alpha
            value = ((value + 0.001) * 1000).rounded() / 1000
        }
        let text = brokenAt.map { "\($0)" } ?? "-"
        #expect(brokenAt == nil, "단조성이 깨진 지점: \(text)")
    }

    /// 범위 밖 구조체에서도 화면 수치로 나갈 값이다(다른 파생값과 같은 방어).
    @Test func surfaceAlphaSurvivesAnOutOfRangeStruct() {
        #expect(appearance(9).surfaceAlpha == 1.0)
        #expect(abs(appearance(-5).surfaceAlpha - 0.364) < 0.001)
        #expect(appearance(.nan).surfaceAlpha == 1.0)
        #expect(appearance(.nan).surfaceAlpha.isNaN == false)
    }

    /// 무릎점 경계에서 값이 튀지 않는다(연속). 튀면 스텝 하나에 창이 번쩍한다.
    @Test func blurMappingIsContinuousAtTheKneeAndMonotonic() {
        let knee = TodoBoardAppearance.blurKnee
        // clamp 가 0.1% 격자로 정규화하므로 그보다 잘게 재는 것은 의미가 없다.
        let justBelow = appearance(knee - 0.001).blurAlpha
        #expect(justBelow < 1.0)          // 무릎 아래면 분명히 걷히기 시작했다
        #expect(1.0 - justBelow < 0.01)   // 그런데 경계에서 튀지는 않는다
        #expect(1.0 - appearance(knee - 0.002).blurAlpha < 0.02)

        // 전 구간 단조 증가. 어딘가에서 되돌아가면 슬라이더를 한 방향으로 끄는데 블러가 왕복한다.
        var previous = -1.0
        var brokenAt: Double?
        var value = TodoBoardAppearance.minOpacity
        while value <= TodoBoardAppearance.maxOpacity + 1e-9 {
            let blur = appearance(value).blurAlpha
            if blur < previous - 1e-12, brokenAt == nil { brokenAt = value }
            previous = blur
            value = ((value + 0.001) * 1000).rounded() / 1000
        }
        let brokenText = brokenAt.map { "\($0)" } ?? "-"
        #expect(brokenAt == nil, "단조성이 깨진 지점: \(brokenText)")
    }

    /// 그림자 임계와 블러 무릎점은 **같은 숫자**여야 한다. 둘이 갈라지면 "블러는 걷혔는데 그림자는 아직"인
    /// 구간이 생겨, 밝은 바탕화면에서 글자만 통째로 사라지는 창이 만들어진다.
    @Test func textShadowTurnsOnExactlyWhereTheBlurStartsLifting() {
        #expect(appearance(TodoBoardAppearance.maxOpacity).needsTextShadow == false)
        #expect(appearance(TodoBoardAppearance.defaultOpacity).needsTextShadow == false)
        #expect(appearance(TodoBoardAppearance.blurKnee).needsTextShadow == false)
        #expect(appearance(TodoBoardAppearance.blurKnee - 0.001).needsTextShadow)
        #expect(appearance(TodoBoardAppearance.minOpacity).needsTextShadow)
        // 같은 지점에서 블러도 걷히기 시작한다.
        #expect(appearance(TodoBoardAppearance.blurKnee - 0.001).blurAlpha < 1.0)

        // 전 구간에서 "블러가 걷혔다 ⟹ 그림자가 켜져 있다". 위험한 방향은 이쪽 하나뿐이다
        // (반대 — 그림자는 켜졌는데 블러는 온전 — 은 안전하다).
        var value = TodoBoardAppearance.minOpacity
        var unguarded: Double?
        while value <= TodoBoardAppearance.maxOpacity + 1e-9 {
            let board = appearance(value)
            if board.blurAlpha < 1.0, !board.needsTextShadow, unguarded == nil { unguarded = value }
            value = ((value + 0.001) * 1000).rounded() / 1000
        }
        let text = unguarded.map { "\($0)" } ?? "-"
        #expect(unguarded == nil, "블러는 걷혔는데 그림자가 없는 값: \(text)")
    }

    // MARK: - 스토어: 복원

    /// 키가 없으면 지금 출고되는 화면과 **정확히 같은** 값이어야 한다.
    @Test func missingKeyRestoresTheShippedLook() {
        withTestDefaults { defaults in
            let store = TodoBoardAppearanceStore(defaults: defaults)
            #expect(store.appearance.opacity == 0.55)
            #expect(store.appearance.tintAlpha == 0.55)
            #expect(store.appearance.blurAlpha == 1.0)
            #expect(store.appearance.needsTextShadow == false)
            #expect(store.appearance.percentLabel == "55%")
        }
    }

    /// 예전 버전이 남긴 쓰레기, 다른 단위(0~100), `defaults write` 로 들어간 엉뚱한 타입.
    /// 전부 **기본값**으로 복구한다 — 끝값으로 접어 넣으면 사용자가 고른 적 없는 극단
    /// (거의 안 보이는 보드 / 꽉 막힌 보드)에서 앱이 시작하고, 그 두 끝이 하필 "고장 났다"로 보인다.
    @Test func corruptedStoredValuesFallBackToTheDefault() {
        let garbage: [Any] = [0, 0.0, -0.3, 1.0, 1.5, 55, "안녕", "", true, [0.3], ["opacity": 0.3]]
        for value in garbage {
            withTestDefaults { defaults in
                defaults.set(value, forKey: TodoBoardAppearanceStore.defaultsKey)
                let store = TodoBoardAppearanceStore(defaults: defaults)
                #expect(
                    store.appearance.opacity == TodoBoardAppearance.defaultOpacity,
                    "저장값 \(value) 에서 복구 실패"
                )
            }
        }
    }

    /// `defaults write <domain> check.todoBoardOpacity 0.3` 은 타입을 안 주면 **문자열**을 쓴다.
    /// 숫자로 읽히는 문자열까지 거절하면 안내대로 따라 한 사용자가 "안 먹는다"를 겪는다.
    @Test func numericStringFromDefaultsWriteIsHonoured() {
        withTestDefaults { defaults in
            defaults.set("0.3", forKey: TodoBoardAppearanceStore.defaultsKey)
            #expect(TodoBoardAppearanceStore(defaults: defaults).appearance.opacity == 0.3)
        }
    }

    // MARK: - 스토어: 왕복

    @Test func opacitySurvivesANewStoreInstance() {
        withTestDefaults { defaults in
            let first = TodoBoardAppearanceStore(defaults: defaults)
            first.setOpacity(0.30)
            #expect(first.appearance.opacity == 0.30)

            let second = TodoBoardAppearanceStore(defaults: defaults)
            #expect(second.appearance.opacity == 0.30)
            // 파생값까지 같아야 한다 — 다음 실행의 창이 같은 그림으로 뜨는지가 실제 계약이다.
            #expect(second.appearance.blurAlpha == first.appearance.blurAlpha)
            #expect(second.appearance.needsTextShadow == first.appearance.needsTextShadow)
        }
    }

    /// 쓰기는 clamp, 읽기는 검증 — 이 둘이 어긋나면 "끝까지 밀었더니 다음 실행에 기본값으로 돌아온다"가 된다.
    /// (범위 밖 값을 그대로 저장하면 복원 검증이 그걸 거절하고 0.55 로 되돌리기 때문이다.)
    @Test func setOpacityPersistsAValueThatRestoreWillAccept() {
        withTestDefaults { defaults in
            let store = TodoBoardAppearanceStore(defaults: defaults)
            store.setOpacity(9)
            #expect(store.appearance.opacity == TodoBoardAppearance.maxOpacity)
            #expect(
                defaults.double(forKey: TodoBoardAppearanceStore.defaultsKey)
                    == TodoBoardAppearance.maxOpacity
            )
            #expect(
                TodoBoardAppearanceStore(defaults: defaults).appearance.opacity
                    == TodoBoardAppearance.maxOpacity
            )
        }
    }

    // MARK: - 스토어: 통지

    /// 창(블러 알파)과 뷰가 여기에 매달린다. 같은 값 재통지는 슬라이더 드래그 한 번에 수십 번의
    /// 창 다시 그리기가 된다.
    @Test func onChangeFiresOnlyWhenTheValueActuallyMoves() {
        withTestDefaults { defaults in
            let store = TodoBoardAppearanceStore(defaults: defaults)
            var seen: [Double] = []
            store.onChange = { seen.append($0.opacity) }

            store.setOpacity(0.30)    // 바뀜
            store.setOpacity(0.30)    // 같은 값 — 통지 없음
            store.setOpacity(0.3004)  // 0.1% 격자에서 같은 값 — 통지 없음
            store.setOpacity(.nan)    // 조작이 아님 — 통지도 변경도 없음
            store.setOpacity(5)       // 상한으로 이동 — 바뀜
            store.setOpacity(9)       // 이미 상한 — 통지 없음

            #expect(seen == [0.30, TodoBoardAppearance.maxOpacity])
            #expect(store.appearance.opacity == TodoBoardAppearance.maxOpacity)
        }
    }

    /// NaN 한 번에 사용자가 맞춰 둔 값이 기본값으로 리셋되면 원인 모를 설정 초기화로 보인다.
    @Test func nanIsIgnoredRatherThanResettingTheUserValue() {
        withTestDefaults { defaults in
            let store = TodoBoardAppearanceStore(defaults: defaults)
            store.setOpacity(0.25)
            store.setOpacity(.nan)
            #expect(store.appearance.opacity == 0.25)
        }
    }

    // MARK: - 스토어: nudge

    @Test func nudgeStopsAtTheRails() {
        withTestDefaults { defaults in
            let store = TodoBoardAppearanceStore(defaults: defaults)
            var fires = 0
            store.onChange = { _ in fires += 1 }

            for _ in 0..<40 { store.nudge(by: TodoBoardAppearance.step) }
            #expect(store.appearance.opacity == TodoBoardAppearance.maxOpacity)
            // 0.55 → 0.95 는 정확히 8스텝. 그 뒤로는 값도 통지도 멎는다.
            #expect(fires == 8)
            store.nudge(by: TodoBoardAppearance.step)
            #expect(fires == 8)

            for _ in 0..<40 { store.nudge(by: -TodoBoardAppearance.step) }
            #expect(store.appearance.opacity == TodoBoardAppearance.minOpacity)
            // 0.95 → 0.20 은 15스텝(= 범위 전체).
            #expect(fires == 8 + 15)

            // 스크롤 델타는 드라이버·제스처에 따라 실제로 튄다. 살짝 굴린 한 번에 끝값으로 순간이동하면 안 된다.
            store.nudge(by: .nan)
            store.nudge(by: .infinity)
            #expect(store.appearance.opacity == TodoBoardAppearance.minOpacity)
            #expect(fires == 8 + 15)
        }
    }

    /// 누적 오차 방어. 스텝을 수십 번 올렸다 내렸다 해도 값이 격자에서 벗어나면 안 된다
    /// (벗어나면 끝값이 `maxOpacity` 와 `==` 로 같지 않아 조절이 끝에서 미세하게 계속 움직인다).
    @Test func repeatedNudgesStayOnTheStepGrid() {
        withTestDefaults { defaults in
            let store = TodoBoardAppearanceStore(defaults: defaults)
            for _ in 0..<7 { store.nudge(by: TodoBoardAppearance.step) }
            for _ in 0..<7 { store.nudge(by: -TodoBoardAppearance.step) }
            #expect(store.appearance.opacity == TodoBoardAppearance.defaultOpacity)
            #expect(store.appearance.percentLabel == "55%")
        }
    }
}
