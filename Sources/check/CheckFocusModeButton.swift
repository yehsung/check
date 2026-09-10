import SwiftUI

// MARK: - 집중 모드 2단 버튼 (v0.3.0 · 모양은 v0.3.01)
//
// v0.3.01(2026-09-11 실사용 지적 "버튼이 좀 이상하게 생겼어"): 처음 모양은 27pt 높이에 두 줄을 욱여넣었다 —
// 윗줄 달 + 눈금 두 칸, 아랫줄 9pt 글자. 실제 1x 화면에서 눈금 두 칸이 사슬 고리(∞)처럼 읽혔고 글자는 너무 작았다.
// 지금은 옆의 울트라 잔량 배지와 같은 **한 줄 캡슐**이다: [달][집중 / 1단 / 2단]. ★ 눈금·두 줄 배치를 다시 넣지 마라.
//
// 사용자 지시(2026-09-11): "버튼 상에서 UI 적으로 1단 2단 있는 걸 표시할 수 있으면 좋겠다. 버튼 1번 누르면 1단까지만,
// 2번 눌러야 2단." 콕 찌르기 패널 머리의 옛 달 아이콘(IconButton 27pt) 자리에 들어간다.
// 판정·요청은 전부 스토어(WorkTimerStorePoke 의 '집중 모드 2단' 절)가 하고, 이 파일은 값(FocusStageFace)을 그리기만 한다.

/// 집중 모드 버튼. **지금 몇 단인지를 버튼만 보고 안다** — 색 하나에 기대지 않고 세 갈래가 함께 바뀐다:
///  · 글자: 꺼짐 "집중" · "1단" · "2단" (사용자 지시 원문 "1단 2단 있는 걸 표시" 그대로)
///  · 달: 빈 달 ↔ 찬 달
///  · 바탕 농도: 옅은 회색 · 옅은 강조색 · 꽉 찬 강조색
/// 1단 남은 시간은 툴팁이 말한다(한 줄 50pt 에 "2시간 12분"을 넣으면 달이 밀려난다).
/// 색을 못 가르는 사람·흑백 캡처에서도 글자만으로 단계가 읽힌다(FocusModeButtonStyle 표를 테스트가 되묻는다).
///
/// ★ **시계는 클로저로 받는다**(`read`). 1단의 남은 시간은 초침을 읽고, 그 읽기는 **읽은 뷰의 body** 에 관찰 등록된다.
///   값으로 받으면 부르는 쪽(PokePanel)이 매초 재평가돼 26행 목록이 통째로 다시 돈다 — v0.2.37 까지의 결함이고,
///   CheckMenuView 의 `cooldownRemaining` 이 값이 아니라 클로저인 이유와 같다. 그래서 `read()` 는 아래
///   MenuClockLeaf 안에서만 부른다. 게다가 스토어의 `focusStageFace(now:)` 는 1단일 때만 시계를 평가하므로,
///   꺼짐·2단에서는 이 잎조차 초침에 돌지 않는다.
struct CheckFocusModeButton: View {
    /// 버튼 폭(pt). 옛 IconButton(27pt)보다 넓다 — 달 + "집중"(caption2 bold) 한 줄이 여백을 두고 들어가야 해서다.
    /// 단계마다 글자 폭이 달라도 캡슐 폭은 이 값으로 고정한다(누를 때마다 행이 흔들리지 않게).
    /// **이 값을 늘리기 전에 PokeTitleRowWidthBudget 을 봐라.** 제목 행 `[뒤로][콕 찌르기][이 버튼][Spacer][잔량 배지][힌트]`
    /// 에서 넘친 폭은 힌트("3초 꾹 = 울트라")가 말줄임으로 먼저 먹는다(`.fixedSize()` 라 높이 테스트로는 안 잡힌다).
    /// 50 은 잔량 두 자리 가정(`hintWidth(digits: 2)`)에서도 힌트 실측 폭 71pt 가 남는 상한(52) 안이다 —
    /// V0251FocusStageTests 가 그 산수와 글자 실측을 함께 되묻는다.
    /// `nonisolated` 인 이유: 배선 때 PokeTitleRowWidthBudget(격리 없는 enum)이 이 값을 직접 읽는다 — 테스트의 짝 게이트가
    /// 그걸 요구한다. View 는 MainActor 로 추론되므로 떼면 예산 두 줄에 "main actor-isolated static property 'width'
    /// can not be referenced from a nonisolated context" 경고가 붙는다(2026-09-11 사본 배선 빌드 실측). 상수라 격리가 지킬 것이 없다.
    nonisolated static let width: CGFloat = 50
    /// 높이(pt). 옛 IconButton 과 **같다** — 달라지면 제목 행 높이가 변해 패널 높이 예산(창 700pt 상한)이 흔들린다.
    static let height: CGFloat = 27

    /// 지금 단계와 1단 남은 초 읽기. **이 뷰의 MenuClockLeaf 밖에서 부르지 마라.**
    let read: () -> FocusStageFace
    let action: () -> Void
    /// 전환 애니메이션 끄기 강제값. nil 이면 시스템 '동작 줄이기'를 따른다 — 환경값(accessibilityReduceMotion)은
    /// 읽기 전용이라 스냅샷·테스트가 주입할 길이 이것뿐이다.
    var reduceMotion: Bool? = nil

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    var body: some View {
        let reduces = reduceMotion ?? systemReduceMotion
        MenuClockLeaf(read: read) { face in
            CheckFocusModeFace(face: face, reduceMotion: reduces, action: action)
        }
    }
}

/// 버튼 겉모습(값 → 픽셀). 시계를 모른다 — 스냅샷이 이 뷰를 그대로 그린다.
///
/// **Menu 를 쓰지 않는다**(ImageRenderer 가 노란 상자로 그려 그 자리 픽셀 검증이 통째로 눈이 먼다 —
/// UltraBalanceBadge 주석). Button + `.plain` 은 IconButton 과 같은, 이미 픽셀로 검증된 관용구다.
struct CheckFocusModeFace: View {
    let face: FocusStageFace
    let reduceMotion: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        let style = FocusModeButtonStyle(stage: face.stage)
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: style.icon)
                    .font(.system(size: 9, weight: .bold))
                Text(FocusModeButtonText.label(face))
                    .font(.caption2.weight(.bold))
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(style.tint)
            // 캡슐 크기는 울트라 잔량 배지와 맞춘다 — 같은 행에 모양이 다른 알약 둘이 서면 그게 곧 '이상해 보임'이다.
            .frame(width: CheckFocusModeButton.width, height: FocusModeButtonStyle.capsuleHeight)
            .background(Capsule().fill(style.fill(hovering: hovering)))
            .overlay(Capsule().stroke(style.stroke, lineWidth: 1))
            // 바깥 틀은 옛 IconButton 높이(27)를 지킨다 — 제목 행 높이·패널 높이 예산이 이 값에 묶여 있다.
            .frame(height: CheckFocusModeButton.height)
            .contentShape(Rectangle())
            // 동작 줄이기면 전환을 즉시 바꾼다(장식 애니메이션 끔 — 공통 규칙 8).
            .animation(FocusModeButtonStyle.transition(reduceMotion: reduceMotion), value: face.stage)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .fixedSize()
        // 툴팁 = 지금 상태(1단이면 남은 시간) — 다음 누름.
        .help(FocusModeButtonText.tooltip(face))
        .accessibilityLabel("집중 모드")
        .accessibilityValue(FocusModeButtonText.accessibilityValue(face))
    }
}

/// 단계별 겉모습 표(순수 값). "색만으로 알리지 않는다"를 테스트가 이 표로 검증한다 —
/// 어느 두 단계 사이에도 바탕 농도·달·글자 중 **최소 두 갈래**가 달라야 한다.
struct FocusModeButtonStyle {
    let stage: FocusStage

    /// 캡슐 높이(pt). 울트라 잔량 배지(caption2 + 세로 여백 2×2 + 테두리)와 같은 줄에 서는 알약이라 거의 같은 키로 둔다.
    static let capsuleHeight: CGFloat = 20

    /// 바탕 농도 단계. 꺼짐 0 · 1단 1 · 2단 2 — **단 번호 그대로**다. `tint`·`fill`·`stroke` 가 이 값에서만 나온다.
    var fillLevel: Int {
        switch stage {
        case .off: 0
        case .timed: 1
        case .always: 2
        }
    }

    /// 달 아이콘. 꺼짐은 빈 달, 켜짐은 찬 달(옛 버튼의 은유를 이어받는다 — 쓰던 사람이 새로 배울 것이 없다).
    var icon: String { stage == .off ? "moon" : "moon.fill" }

    var tint: Color {
        switch fillLevel {
        case 0: CheckTheme.secondaryText
        case 1: CheckTheme.accent
        // 2단은 바탕을 꽉 칠하고 글자를 흰색으로 올린다 — accent 글자를 진한 accent 바탕에 두면 대비가 무너진다.
        default: Color.white
        }
    }

    func fill(hovering: Bool) -> Color {
        switch fillLevel {
        case 0: Color.white.opacity(hovering ? 0.14 : 0.06)
        case 1: CheckTheme.accent.opacity(hovering ? 0.28 : 0.16)   // 울트라 잔량 배지와 같은 농도
        default: CheckTheme.accent.opacity(hovering ? 1.0 : 0.85)
        }
    }

    var stroke: Color {
        switch fillLevel {
        // 꺼짐에도 옅은 테두리를 둔다: 바탕 0.06 만으로는 어두운 패널에서 '누를 수 있는 알약'으로 안 읽힌다.
        case 0: Color.white.opacity(0.14)
        case 1: CheckTheme.accent.opacity(0.35)
        default: CheckTheme.accent
        }
    }

    /// 단계 전환 애니메이션. 동작 줄이기면 nil(즉시).
    static func transition(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.18)
    }
}

/// 버튼 문구(순수 값 — 문구를 값으로 검증한다).
enum FocusModeButtonText {
    /// 1단 남은 시간. "2시간 12분" / 정각이면 "3시간" / 1시간 미만 "42분" / 1분 미만 "곧 해제".
    /// 분은 **내림**이다 — 누른 직후 "3시간", 1초 뒤 "2시간 59분"(초시계와 같은 읽기). 올림이면 0분이 남았는데 "1분"이라 말한다.
    static func remaining(seconds: Int) -> String {
        guard seconds >= 60 else { return "곧 해제" }
        let totalMinutes = seconds / 60
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours == 0 { return "\(minutes)분" }
        return minutes == 0 ? "\(hours)시간" : "\(hours)시간 \(minutes)분"
    }

    /// 1단 길이를 말로("3시간"). 상수에서 파생한다 — 문구에 숫자를 베껴 두지 않는다.
    static var timedDurationText: String {
        remaining(seconds: Int(WorkTimerStore.focusTimedDuration))
    }

    /// 버튼 안 글자. 단계 이름 그대로다(사용자 지시 "1단 2단 있는 걸 표시").
    static func label(_ face: FocusStageFace) -> String {
        switch face.stage {
        case .off: "집중"
        case .timed: "1단"
        case .always: "2단"
        }
    }

    /// 마우스를 올렸을 때의 말: 지금 상태(1단이면 남은 시간) — 다음 누름.
    static func tooltip(_ face: FocusStageFace) -> String {
        let now: String
        switch face.stage {
        case .off: now = "집중 모드 꺼짐"
        case .timed: now = "1단 · \(remaining(seconds: face.remainingSeconds ?? 0)) 남음"
        case .always: now = "2단 · 끌 때까지 계속"
        }
        return "\(now) — \(help(face.stage))"
    }

    /// 툴팁 — **다음 누름**이 무엇인지(사용자 지시 2026-09-11 스펙 문구 그대로).
    static func help(_ stage: FocusStage) -> String {
        switch stage {
        case .off: "누르면 \(timedDurationText) 집중"
        case .timed: "한 번 더 누르면 끌 때까지 계속"
        case .always: "누르면 집중 모드 해제"
        }
    }

    /// 보이스오버가 읽는 현재 상태(툴팁은 다음 동작, 이것은 지금 상태 — 둘이 겹치지 않는다).
    static func accessibilityValue(_ face: FocusStageFace) -> String {
        switch face.stage {
        case .off: "꺼짐"
        case .timed: "1단, \(remaining(seconds: face.remainingSeconds ?? 0)) 남음"
        case .always: "2단, 끌 때까지 계속"
        }
    }
}
