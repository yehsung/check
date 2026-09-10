import SwiftUI

// MARK: - 집중 모드 2단 버튼 (v0.2.51)
//
// 사용자 지시(2026-09-11): "버튼 상에서 UI 적으로 1단 2단 있는 걸 표시할 수 있으면 좋겠다. 버튼 1번 누르면 1단까지만,
// 2번 눌러야 2단." 콕 찌르기 패널 머리의 옛 달 아이콘(IconButton 27pt) 자리에 들어간다.
// 판정·요청은 전부 스토어(WorkTimerStorePoke 의 '집중 모드 2단' 절)가 하고, 이 파일은 값(FocusStageFace)을 그리기만 한다.

/// 집중 모드 버튼. **지금 몇 단인지를 버튼만 보고 안다** — 색 하나에 기대지 않고 세 갈래가 함께 바뀐다:
///  · 모양: 눈금 두 칸(꺼짐 빈칸 둘 · 1단 한 칸 채움 · 2단 두 칸 채움)
///  · 채움: 달(빈 달 ↔ 찬 달)과 캡슐 바탕의 농도
///  · 글자: 꺼짐 "집중" · 1단 남은 시간("2시간 12분"/"42분"/"곧 해제") · 2단 "계속"
/// 색을 못 가르는 사람·흑백 캡처에서도 눈금과 글자만으로 단계가 읽힌다(FocusModeButtonStyle 표를 테스트가 되묻는다).
///
/// ★ **시계는 클로저로 받는다**(`read`). 1단의 남은 시간은 초침을 읽고, 그 읽기는 **읽은 뷰의 body** 에 관찰 등록된다.
///   값으로 받으면 부르는 쪽(PokePanel)이 매초 재평가돼 26행 목록이 통째로 다시 돈다 — v0.2.37 까지의 결함이고,
///   CheckMenuView 의 `cooldownRemaining` 이 값이 아니라 클로저인 이유와 같다. 그래서 `read()` 는 아래
///   MenuClockLeaf 안에서만 부른다. 게다가 스토어의 `focusStageFace(now:)` 는 1단일 때만 시계를 평가하므로,
///   꺼짐·2단에서는 이 잎조차 초침에 돌지 않는다.
struct CheckFocusModeButton: View {
    /// 버튼 폭(pt). 옛 IconButton(27pt)보다 넓다 — 남은 시간 글자("2시간 59분" 9pt 실측 44.1pt)가 들어가야 해서다.
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
            VStack(spacing: 1) {
                HStack(spacing: 3) {
                    Image(systemName: style.icon)
                        .font(.system(size: 10, weight: .semibold))
                    HStack(spacing: 2) {
                        FocusStagePip(filled: style.filledPips >= 1, tint: style.tint)
                        FocusStagePip(filled: style.filledPips >= 2, tint: style.tint)
                    }
                }
                Text(FocusModeButtonText.label(face))
                    .font(.system(size: 9, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    // 안전망일 뿐이다: 폭 산수는 테스트가 실측으로 지킨다. 여기서 크게 줄여 맞추면 9pt 가 읽을 수 없게 된다.
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(style.tint)
            .frame(width: CheckFocusModeButton.width, height: CheckFocusModeButton.height)
            // 캡슐이 아니라 모서리 9pt 사각형이다: 두 줄짜리 버튼이라 캡슐(반경 13.5)이면 아랫줄 글자 높이에서 좌우가 깎여
            // "2시간 12분"이 테두리에 닿는다(2026-09-11 스냅샷 실측). 폭을 늘리는 대신 모서리를 줄였다 — 폭은 제목 행 예산이 막는다.
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(style.fill(hovering: hovering)))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(style.stroke, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            // 동작 줄이기면 전환을 즉시 바꾼다(장식 애니메이션 끔 — 공통 규칙 8).
            .animation(FocusModeButtonStyle.transition(reduceMotion: reduceMotion), value: face.stage)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .fixedSize()
        // 툴팁은 **다음 누름이 무엇인지** 말한다(지금 상태는 버튼이 이미 그린다).
        .help(FocusModeButtonText.help(face.stage))
        .accessibilityLabel("집중 모드")
        .accessibilityValue(FocusModeButtonText.accessibilityValue(face))
    }
}

/// 눈금 한 칸. 채움은 색이 아니라 **칠해졌는가**로 읽힌다(빈칸은 테두리만 남는다).
private struct FocusStagePip: View {
    let filled: Bool
    let tint: Color

    var body: some View {
        Capsule()
            .fill(filled ? tint : Color.clear)
            .overlay(Capsule().stroke(tint.opacity(filled ? 0 : 0.6), lineWidth: 1))
            .frame(width: 6, height: 4)
    }
}

/// 단계별 겉모습 표(순수 값). "색만으로 알리지 않는다"를 테스트가 이 표로 검증한다 —
/// 어느 두 단계 사이에도 눈금·달·글자 중 **최소 두 갈래**가 달라야 한다.
struct FocusModeButtonStyle {
    let stage: FocusStage

    /// 채워진 눈금 수. 꺼짐 0 · 1단 1 · 2단 2 — **단 번호 그대로**라 설명 없이 읽힌다.
    var filledPips: Int {
        switch stage {
        case .off: 0
        case .timed: 1
        case .always: 2
        }
    }

    /// 달 아이콘. 꺼짐은 빈 달, 켜짐은 찬 달(옛 버튼의 은유를 이어받는다 — 쓰던 사람이 새로 배울 것이 없다).
    var icon: String { stage == .off ? "moon" : "moon.fill" }

    var tint: Color {
        switch stage {
        case .off: CheckTheme.secondaryText
        case .timed: CheckTheme.accent
        // 2단은 바탕을 진하게 칠하고 글자를 흰색으로 올린다 — accent 글자를 진한 accent 바탕에 두면 대비가 무너진다.
        case .always: CheckTheme.primaryText
        }
    }

    func fill(hovering: Bool) -> Color {
        switch stage {
        case .off: Color.white.opacity(hovering ? 0.14 : 0.06)   // 옛 IconButton 과 같은 바탕
        case .timed: CheckTheme.accent.opacity(hovering ? 0.26 : 0.16)
        case .always: CheckTheme.accent.opacity(hovering ? 0.48 : 0.38)
        }
    }

    var stroke: Color {
        switch stage {
        case .off: Color.clear
        case .timed: CheckTheme.accent.opacity(0.35)
        case .always: CheckTheme.accent.opacity(0.8)
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

    /// 버튼 안 글자.
    static func label(_ face: FocusStageFace) -> String {
        switch face.stage {
        case .off: "집중"
        case .timed: remaining(seconds: face.remainingSeconds ?? 0)
        case .always: "계속"
        }
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
