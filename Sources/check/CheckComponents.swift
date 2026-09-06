import AppKit
import SwiftUI

// MARK: - Start / Stop pill

struct WorkTogglePill: View {
    let isWorking: Bool
    let enabled: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: isWorking ? "stop.fill" : "play.fill")
                    .font(.system(size: 11, weight: .black))
                Text(isWorking ? "근무 종료" : "근무 시작")
                    .font(.subheadline.weight(.bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .frame(height: 40)
            .background(
                Capsule()
                    .fill(isWorking ? CheckTheme.stopGradient : CheckTheme.startGradient)
            )
            .overlay(
                Capsule().stroke(Color.white.opacity(0.22), lineWidth: 1)
            )
            .brightness(hovering ? 0.06 : 0)
            .shadow(color: (isWorking ? CheckTheme.pending : CheckTheme.working).opacity(0.30), radius: 8, y: 2)
        }
        .buttonStyle(.plain)
        // 팝오버가 열리면 이 버튼이 첫 포커스를 받아 macOS 가 파란 포커스 링을 그린다(실사용 신고:
        // "자꾸 근무 시작 종료 버튼에 파란색 테두리가 생기는데"). 알약 위에 사각 링이 겹쳐 그려져
        // 눌린 것처럼도, 고장난 것처럼도 보인다.
        //
        // **범위를 이 버튼 하나로 좁힌 것이 요점이다.** 팝오버 루트에 걸면 로그인 이메일·비밀번호,
        // 비밀번호 재설정 코드, 할 일 입력, 메시지 3글자 입력의 포커스 표시까지 함께 죽는다 —
        // 그것들은 지금 커서가 어디 있는지 보여야 쓸 수 있는 필드다.
        // `focusable(false)` 가 아니라 `focusEffectDisabled()` 인 이유도 같다: 키보드로 도달하는
        // 길은 남기고 **그리는 것만** 끈다.
        .focusEffectDisabled()
        .onHover { hovering = $0 }
        .opacity(enabled ? 1 : 0.45)
        .disabled(!enabled)
    }
}

// MARK: - Chips

struct StatusChip: View {
    let isWorking: Bool

    var body: some View {
        Text(isWorking ? "근무중" : "근무종료")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(isWorking ? .white : CheckTheme.secondaryText)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background {
                if isWorking {
                    Capsule().fill(CheckTheme.working.opacity(0.85))
                } else {
                    Capsule().stroke(CheckTheme.border, lineWidth: 1)
                }
            }
            .fixedSize()
    }
}

/// 팀원 3상태 칩. 라이브 근무(초록 "근무중"), 연결 끊김(앰버 "연결 끊김"), 근무종료(회색 테두리).
struct PresenceChip: View {
    let presence: MemberPresence

    private var label: String {
        switch presence {
        case .activeWorking: return "근무중"
        case .staleWorking: return "연결 끊김"
        case .offWork: return "근무종료"
        }
    }

    private var tint: Color {
        switch presence {
        case .activeWorking: return CheckTheme.working
        case .staleWorking: return CheckTheme.pending
        case .offWork: return CheckTheme.secondaryText
        }
    }

    private var isOff: Bool {
        if case .offWork = presence { return true }
        return false
    }

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(isOff ? CheckTheme.secondaryText : .white)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background {
                if isOff {
                    Capsule().stroke(CheckTheme.border, lineWidth: 1)
                } else {
                    Capsule().fill(tint.opacity(0.85))
                }
            }
            .fixedSize()
    }
}

struct CountChip: View {
    let count: Int

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(CheckTheme.working)
                .frame(width: 6, height: 6)
            Text("\(count)명 근무중")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(CheckTheme.working)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(Capsule().fill(CheckTheme.working.opacity(0.16)))
        .fixedSize()
    }
}

// MARK: - Weekly goal gauge

struct TeamGoalGauge: View {
    let goal: TeamWeeklyGoal
    /// 진행 시간 앞에 붙이는 접두어. 내 팀 카드의 "내 진행률" 게이지는 "내 " 를 붙여 총합이 아님을 드러낸다.
    var workedLabelPrefix: String = ""
    /// 목표 시간 앞에 붙이는 접두어. "각자 " 를 붙여 목표가 팀 총합이 아니라 1인당임을 드러낸다.
    var goalLabelPrefix: String = ""

    private var percent: Int {
        Int((goal.progress * 100).rounded())
    }

    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 6) {
                Text("주간 목표")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CheckTheme.primaryText)
                Text("\(workedLabelPrefix)\(MenuBarStatusFormatter.hoursMinutes(goal.workedSeconds)) / \(goalLabelPrefix)\(MenuBarStatusFormatter.hoursMinutes(goal.goalSeconds))")
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 4)
                if goal.isComplete {
                    Label("완료", systemImage: "checkmark.seal.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(CheckTheme.working)
                        .lineLimit(1)
                } else {
                    Text("\(percent)%")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(CheckTheme.primaryText)
                        .monospacedDigit()
                }
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(CheckTheme.trackFill)
                    Capsule()
                        .fill(CheckTheme.gaugeGradient)
                        .frame(width: max(8, proxy.size.width * goal.progress))
                        .shadow(color: CheckTheme.working.opacity(0.35), radius: 4, y: 1)
                }
            }
            .frame(height: 8)
        }
    }
}

// MARK: - Weekly goal percent

/// 주간 목표 진행 퍼센트(정수). 실제 비율 기반이라 100%를 넘을 수 있고(상한 999%), 음수는 0으로 둔다.
/// 헤더 목표 바 캡션과 단위 테스트가 같은 계산을 쓰도록 한곳에 둔다.
enum GoalPercentFormatter {
    static func percent(workedSeconds: Int, goalSeconds: Int) -> Int {
        let worked = max(0, workedSeconds)
        let goal = max(1, goalSeconds)
        let raw = Int((Double(worked) / Double(goal) * 100).rounded())
        return min(999, max(0, raw))
    }

    /// 목표 **미달**이라고 이미 판정된 곳에서 쓰는 표시 퍼센트. 반올림 때문에 99.5% 이상이 100 으로 올라가는데,
    /// 미달 문구는 같은 줄에 부족분("N분 부족")을 함께 쓰므로 그대로 두면 "100% · 18분 부족"으로 자기모순이 된다.
    /// (달성 판정은 totalSeconds >= goalSeconds 엄격 비교라 100 이어도 여전히 미달이다.)
    /// 그래서 미달 문맥에서만 99 로 묶는다 — 퍼센트를 단독 표기하는 헤더 게이지는 percent 를 그대로 쓴다.
    static func shortfallPercent(workedSeconds: Int, goalSeconds: Int) -> Int {
        min(99, percent(workedSeconds: workedSeconds, goalSeconds: goalSeconds))
    }
}

// MARK: - Team member row

struct TeamMemberRow: View {
    let name: String
    var avatarURL: URL? = nil
    let presence: MemberPresence
    let primaryDetail: String
    /// stale(연결 끊김) 상태의 "마지막 확인 N분 전" 보조줄. 그 외 상태에선 nil(한 줄만).
    var secondaryDetail: String? = nil
    /// 1인당 주간 목표 달성 여부. true면 주간 시간 옆에 은은한 ✓(working 그린)를 붙인다. 행 높이는 불변.
    var meetsWeeklyGoal: Bool = false
    /// 이 팀원의 1인당 주간 목표 진행 비율(0~1 클램프). non-nil 이면 텍스트 칼럼 밑에 슬림 바 + 우측 %를 그린다.
    /// nil(빈 팀 placeholder 등)이면 바를 그리지 않는다.
    var goalFraction: Double? = nil
    /// 내 행 여부. true면 아바타에 hover 카메라 배지 + 파일 선택을 붙인다.
    var isMe: Bool = false
    /// 내 행 아바타 교체 시 다운스케일된 JPEG Data를 전달받는 콜백.
    var onPickAvatar: ((Data) -> Void)? = nil
    /// 내 행 별명 편집 진입. non-nil 이면 이름 옆 18pt 자리를 **늘** 차지하고, hover 시에만 연필을 칠한다.
    /// 파라미터는 반드시 맨 끝이다 — 위치 인자로 이 뷰를 만드는 렌더 테스트가 그대로 컴파일되어야 한다.
    var onBeginEditName: (() -> Void)? = nil

    // 아바타 칼럼(26) + 상단 HStack 간격(10). 목표 바를 텍스트 칼럼 시작점부터 그리도록 들여쓸 폭.
    private static let textColumnInset: CGFloat = 26 + 10

    // 별명 편집 배지 hover 상태. 평소엔 존재를 드러내지 않고, 마우스를 올렸을 때만 연필이 accent 로 떠오른다.
    @State private var isNameBadgeHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 10) {
                avatar
                VStack(alignment: .leading, spacing: 2) {
                    // 이름과 편집 배지는 **한 줄**이어야 한다. 예전엔 Text 하나가 VStack 직계 자식이었으므로,
                    // 배지를 그냥 붙이면 세로로 쌓여 58pt 고정 행 안에서 상세줄/보조줄을 밀어낸다.
                    HStack(spacing: MemberRowNameWidthBudget.editBadgeSpacing) {
                        Text(name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(CheckTheme.primaryText)
                            .lineLimit(1)
                            // 12자 별명이 배지와 공존해도 말줄임 대신 먼저 줄여 본다(팀 헤더와 같은 관례).
                            .minimumScaleFactor(MemberRowNameWidthBudget.minimumScaleFactor)
                        if onBeginEditName != nil {
                            editNameBadge
                                // hover 때만 자리를 만들면 마우스가 지날 때마다 이름 폭이 튀어 글자가 밀린다.
                                .frame(
                                    width: MemberRowNameWidthBudget.editBadgeWidth,
                                    height: MemberRowNameWidthBudget.editBadgeWidth
                                )
                        }
                    }
                    HStack(spacing: 4) {
                        Text(primaryDetail)
                            .font(.caption2)
                            .foregroundStyle(CheckTheme.secondaryText)
                            .lineLimit(1)
                        if meetsWeeklyGoal {
                            // 은은한 목표 달성 표식 — 주간 목표(1인당)를 채운 팀원. 과하지 않게 작은 체크만.
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(CheckTheme.working.opacity(0.9))
                                .accessibilityLabel("주간 목표 달성")
                        }
                    }
                    if let secondaryDetail {
                        Text(secondaryDetail)
                            .font(.caption2)
                            .foregroundStyle(CheckTheme.pending)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 6)
                PresenceChip(presence: presence)
            }
            if let goalFraction {
                // 바는 아바타가 아니라 텍스트 칼럼 시작점부터 행 우측 끝까지. 위치가 "이 팀원의 진행률"임을 말한다.
                goalBar(fraction: goalFraction)
                    .padding(.leading, Self.textColumnInset)
            }
        }
    }

    // 슬림 진행 바(높이 3pt) + 우측 끝 % 캡션. 달성 시 working, 미달 시 accent 로 채운다(트랙은 기존 게이지 관례).
    private func goalBar(fraction: Double) -> some View {
        let clamped = min(1, max(0, fraction))
        return HStack(spacing: 6) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(CheckTheme.trackFill)
                    Capsule()
                        .fill(fraction >= 1.0 ? CheckTheme.working : CheckTheme.accent)
                        .frame(width: max(0, proxy.size.width * clamped))
                }
            }
            .frame(height: 3)
            Text("\(Int((clamped * 100).rounded()))%")
                .font(.caption2)
                .foregroundStyle(CheckTheme.secondaryText)
                .monospacedDigit()
                .fixedSize()
        }
    }

    @ViewBuilder
    private var avatar: some View {
        if isMe, let onPickAvatar {
            EditableAvatarView(name: name, avatarURL: avatarURL, size: 26, onPick: onPickAvatar)
        } else {
            CheckAvatarView(name: name, avatarURL: avatarURL, size: 26)
        }
    }

    // 별명 편집 진입 배지. EditableAvatarView(CheckAvatarView.swift)의 hover 규약을 그대로 따른다 —
    // 평소엔 존재를 드러내지 않고, 마우스를 올리면 연필이 떠오르며 툴팁으로 무엇인지 말한다.
    // Button 이 아니라 onTapGesture 인 이유: 기본 버튼 스타일이 caption 행 높이를 키워 58pt 고정 행 안에서
    // 상세줄을 밀어낸다(헤더 캡션 소형 버튼과 같은 이유).
    @ViewBuilder
    private var editNameBadge: some View {
        Image(systemName: "pencil")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(isNameBadgeHovering ? CheckTheme.accent : CheckTheme.secondaryText.opacity(0.45))
            .contentShape(Rectangle())
            .onHover { isNameBadgeHovering = $0 }
            .onTapGesture { onBeginEditName?() }
            .help("별명 변경")
            .accessibilityLabel("별명 변경")
    }
}

// 여기 있던 `DisplayNameEditorRow`(내 행을 대체하던 별명 인라인 편집 행)는 v0.2.32 에 사라졌다.
// 별명 편집의 유일한 거처가 설정 창(CheckSettingsView 의 DisplayNameSettingsRow)이 되면서 소스
// 호출부가 0이 됐다. 그 뷰가 지고 있던 제약("58pt 고정 행 안에 수납해 목록 행수·스크롤 상한·창 높이
// 예산을 1pt 도 흔들지 않는다")은 함께 사라졌다 — 설정 창은 세로로 늘어나도 되는 창이다.
// 다만 **안내 한 줄의 색 분기**(도움말·쿨타임은 secondaryText, 실패 사유만 danger)는 그대로 살아
// 설정 창이 이어받았다. notice != nil 로 색을 추측하면 "일주일에 한 번" 안내가 빨갛게 떠 사용자가
// 실패로 읽는다는 그 사고가 여전히 가능해서다 — DisplayNameUITests 가 새 집에서 그걸 지킨다.

// MARK: - Team weekly totals (per-team list)

/// 팀 한 행: 이니셜 아바타 + 팀명(+우리 팀 칩) + 1인당 평균 근무시간 + 평균/목표 미니 게이지·% +
/// "각자 목표 G시간 · 총 X시간 · N명 · M명 근무중" 캡션. weekly_goal_hours 가 1인당 목표라 메인 숫자·게이지·%
/// 는 모두 총합이 아니라 평균 기준이다. 우리 팀에는 은은한 "우리 팀" 칩만 붙고 순위/경쟁 표기는 없다.
/// 높이는 LeaderboardPanel 이 고정으로 준다.
struct LeaderboardRow: View {
    let entry: TeamLeaderboardEntry
    var isMyTeam: Bool = false

    // 1인당 평균 대비 목표 진행률 게이지(entry.goal 이 평균 기준으로 계산됨).
    private var goal: TeamWeeklyGoal {
        entry.goal
    }

    private var percent: Int {
        Int((goal.progress * 100).rounded())
    }

    // "각자 목표 G시간 · 총 X시간 · N명 · M명 근무중" — 팀마다 목표가 다를 수 있어 각 행에 목표시간을 명시한다.
    private var caption: String {
        "각자 목표 \(entry.weeklyGoalHours)시간 · 총 \(MenuBarStatusFormatter.hoursMinutes(entry.totalSeconds)) · \(entry.memberCount)명 · \(entry.workingCount)명 근무중"
    }

    var body: some View {
        HStack(spacing: 11) {
            // 팀명 해시색 이니셜 아바타(팀원 행 아바타와 같은 톤). 순위 배지 대신 담백한 표식.
            CheckAvatarView(name: entry.name, size: 30)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(entry.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(CheckTheme.primaryText)
                        .lineLimit(1)
                    if isMyTeam {
                        Text("우리 팀")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(CheckTheme.accent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(CheckTheme.accent.opacity(0.18)))
                            .fixedSize()
                    }
                    Spacer(minLength: 6)
                    // 메인 숫자 = 1인당 평균("평균 X시간 Y분") — 총합이 아니라 팀원 한 명 기준임을 문구로 드러낸다.
                    Text("평균 \(MenuBarStatusFormatter.hoursMinutes(entry.averageSeconds))")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(CheckTheme.primaryText)
                        .monospacedDigit()
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    miniGauge
                    Text("\(percent)%")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(CheckTheme.secondaryText)
                        .monospacedDigit()
                        .fixedSize()
                }
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var miniGauge: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(CheckTheme.trackFill)
                Capsule()
                    .fill(CheckTheme.gaugeGradient)
                    .frame(width: max(6, proxy.size.width * goal.progress))
            }
        }
        .frame(height: 6)
    }
}

// MARK: - Long-session (12h) confirmation banner

/// 연속 12시간 근무 시 헤더 카드 **위쪽 형제 뷰**로 뜨는 앰버 확인 배너(UpdateBanner 와 같은 배치).
/// "12시간 넘게 근무 중이에요 — 아직 근무 중이신가요?" + [네, 근무 중이에요] / [지금 종료].
/// 예전에는 헤더 카드 overlay 로 얹혀 카드 높이를 지켰지만, 그 바람에 '근무 종료' 버튼을 통째로 가려
/// 배너가 떠 있는 동안 퇴근을 못 하는 결함이 있었다. 배너는 드물게 뜨므로 카드 높이 변화(창 튐)를 감수하고
/// 형제로 올리며, 그 자리에서 바로 퇴근할 수 있게 [지금 종료] 보조 버튼을 함께 둔다.
struct LongSessionBanner: View {
    let onConfirm: () -> Void
    /// [지금 종료] 액션(store.stop()). nil 이면 보조 버튼을 그리지 않는다(컴포넌트 단독 렌더 등).
    var onStopNow: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "hourglass")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(CheckTheme.pending)
                VStack(alignment: .leading, spacing: 2) {
                    Text("12시간 넘게 근무 중이에요")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(CheckTheme.primaryText)
                        .lineLimit(1)
                    Text("아직 근무 중이신가요?")
                        .font(.caption2)
                        .foregroundStyle(CheckTheme.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 6)
            }
            HStack(spacing: 8) {
                // 계속 근무 확인(주 액션) — 12시간 카운터 기준점을 지금으로 다시 잡는다.
                Button(action: onConfirm) {
                    Text("네, 근무 중이에요")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background(RoundedRectangle(cornerRadius: 8).fill(CheckTheme.pending))
                }
                .buttonStyle(.plain)
                if let onStopNow {
                    // 보조 액션 — 배너가 헤더를 밀어낸 상태에서도 여기서 바로 퇴근할 수 있게 한다.
                    Button(action: onStopNow) {
                        Text("지금 종료")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(CheckTheme.pending)
                            .frame(maxWidth: .infinity)
                            .frame(height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(CheckTheme.pending.opacity(0.14))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(CheckTheme.pending.opacity(0.45), lineWidth: 1))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(CheckTheme.pending.opacity(0.16))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(CheckTheme.pending.opacity(0.55), lineWidth: 1)
                )
        )
    }
}

// MARK: - Inline action banner (되돌리기 / 취소 / 회고 안내)

/// 한 줄짜리 인라인 안내 배너 — 아이콘 + 문구(+보조문구) + 액션 버튼 + 선택적 닫기(X).
/// 자리 비움 자동 마감 되돌리기, 넛지 자동 시작 취소, 지난주 회고 안내가 같은 계열을 공유한다.
/// 상단 앵커 원칙대로 자기 자리에서 아래로만 자라고, 다른 컨트롤을 덮지 않는다(12시간 배너의 교훈).
struct InlineActionBanner: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    let actionTitle: String
    var tint: Color = CheckTheme.accent
    let action: () -> Void
    /// 닫기(X) 액션. nil 이면 X 를 그리지 않는다(되돌리기/취소처럼 스스로 사라지는 배너).
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(CheckTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(CheckTheme.secondaryText)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            Button(action: action) {
                Text(actionTitle)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 11)
                    .frame(height: 26)
                    .background(Capsule().fill(tint))
                    .fixedSize()
            }
            .buttonStyle(.plain)
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(CheckTheme.secondaryText)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("닫기")
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tint.opacity(0.14))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(tint.opacity(0.38), lineWidth: 1)
                )
        )
    }
}

// MARK: - Work rhythm heatmap grid (개인 기록)

/// 개인 근무 리듬 히트맵 그리드 — 요일(월~일) 7행 × 시간(0~23) 24열(지난주 한 주).
/// 칸 색은 CheckTheme.accent 를 **한 시간(3600초) 고정 기준** 농도로 칠하고, 0인 칸은 아주 옅은 fieldFill 로 남긴다
/// — 진하기가 곧 "그 시간대를 얼마나 채웠는지"라, 사람마다·주마다 기준이 흔들리지 않는다.
/// 셀 10pt + 간격 1pt + 좌측 요일 라벨 20pt = 총 284pt 라 팝오버 폭(340 - 바깥 12*2 - 패널 12*2 = 292)에 들어간다.
/// 시간 라벨은 0/6/12/18 만 표기한다(24개를 다 쓰면 10pt 칸 위에서 뭉갠다).
struct WorkRhythmHeatmapGrid: View {
    let heatmap: WorkRhythmHeatmap

    static let cellSize: CGFloat = 10
    static let cellGap: CGFloat = 1
    static let labelWidth: CGFloat = 20
    /// 0=월 … 6=일. WorkRhythmHeatmap.buckets 의 행 순서와 같다.
    static let dayLabels = ["월", "화", "수", "목", "금", "토", "일"]
    private static let markedHours: Set<Int> = [0, 6, 12, 18]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            // 시간 라벨 행. 빈 슬롯은 폭만 차지하고, 표기 대상 라벨은 fixedSize 로 이상적 폭을 얻은 뒤
            // 10pt 슬롯 왼쪽에 걸어 둔다(옆 슬롯이 비어 있어 넘쳐도 겹치지 않는다).
            HStack(spacing: Self.cellGap) {
                Color.clear
                    .frame(width: Self.labelWidth, height: 9)
                ForEach(0..<WorkRhythmHeatmap.hourCount, id: \.self) { hour in
                    Text(Self.markedHours.contains(hour) ? "\(hour)" : "")
                        .font(.system(size: 8))
                        .foregroundStyle(CheckTheme.secondaryText)
                        .fixedSize()
                        .frame(width: Self.cellSize, alignment: .leading)
                }
            }
            ForEach(0..<WorkRhythmHeatmap.dayCount, id: \.self) { day in
                HStack(spacing: Self.cellGap) {
                    Text(Self.dayLabels[day])
                        .font(.system(size: 9))
                        .foregroundStyle(CheckTheme.secondaryText)
                        .frame(width: Self.labelWidth, alignment: .trailing)
                    ForEach(0..<WorkRhythmHeatmap.hourCount, id: \.self) { hour in
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(Self.color(seconds: seconds(day: day, hour: hour)))
                            .frame(width: Self.cellSize, height: Self.cellSize)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // 형이 어긋난 buckets(빈 배열 등)이 들어와도 인덱스 크래시 없이 0으로 읽는다.
    private func seconds(day: Int, hour: Int) -> Int {
        guard day < heatmap.buckets.count, hour < heatmap.buckets[day].count else { return 0 }
        return heatmap.buckets[day][hour]
    }

    /// 한 칸을 꽉 채운 근무(초). 지난주 한 주만 집계하므로 (요일, 시간) 한 칸의 최대는 정확히 이 값이다.
    /// 색 계산이 nonisolated 라 상수도 함께 떼어 둔다(View 타입이라 기본은 MainActor 격리).
    nonisolated static let fullCellSeconds = 3_600

    /// 칸 농도(0~1). 분모는 3600초 **고정**이라 값이 곧 "그 시간대를 얼마나 채웠는지"다.
    /// 예전에는 자기 최대 칸 기준 상대 농도라 같은 근무도 그 주 다른 칸에 따라 색이 달라졌다(회귀 지점).
    /// 0이면 그 시간대에 근무가 없었다는 뜻이다. 순수 함수라 nonisolated(단위 테스트 대상).
    nonisolated static func intensity(seconds: Int) -> Double {
        guard seconds > 0 else { return 0 }
        // 3600 을 넘는 입력(이론상 없지만 방어)이 와도 1.0 을 넘지 않게 클램프한다.
        return min(1, max(0, Double(seconds) / Double(fullCellSeconds)))
    }

    /// 칸 색: 0이면 아주 옅은 fieldFill, 그 외엔 한 시간 대비 농도로 accent 를 입힌다(최소 0.20 — 1초라도 보이게).
    nonisolated static func color(seconds: Int) -> Color {
        let value = intensity(seconds: seconds)
        guard value > 0 else { return CheckTheme.fieldFill }
        return CheckTheme.accent.opacity(0.20 + 0.80 * value)
    }
}

// MARK: - Contribution grid (잔디 — 근무·토큰 공용)

/// 깃허브 잔디 모양의 범용 기여 그리드: 주(열) × 요일(행). 값→농도 규칙(분모·단계 수)과 색, 툴팁 문구를
/// 매개변수로 받아 **근무 잔디와 토큰 잔디가 같은 뷰**를 쓴다 — 데이터 종류마다 그리드를 따로 만들면 칸 크기·월 라벨·
/// 미래 칸 규칙이 서서히 갈라진다(같은 패널에 두 잔디가 나란히 서는 순간 그 차이가 결함으로 보인다).
/// 레이아웃: 요일 라벨 열(월·수·금만 표기, 20pt) + 13열 × 16pt 칸 + 2pt 간격 = 20 + 2 + 13×16 + 12×2 = 254pt
/// ≤ 팝오버 콘텐츠 폭 292pt(340 − 바깥 12×2 − 패널 12×2). 위에는 그 달이 시작되는 열 위에 "N월" 라벨을 단다.
struct ContributionGridView: View {
    /// 열(주) 수. values 의 바깥 길이와 같아야 하며, 모자라면 0 으로 읽는다(인덱스 크래시 없음).
    let weeks: Int
    /// values[주][요일 0=월 … 6=일].
    let values: [[Int]]
    /// 가장 오래된 열의 월요일 00:00(KST) — 월 라벨과 툴팁 날짜의 원점.
    let weekStart: Date
    /// (주, 요일) 칸이 미래인지. 미래 칸은 투명하게 비워 "0 = 기록 없음"과 구분한다.
    let isFuture: (Int, Int) -> Bool
    /// 농도 분모. 이 값 이상이면 가장 진한 단계다(근무 = 8시간, 토큰은 호출부가 정한다).
    let denominator: Int
    /// 농도 단계 수(0 제외). 4 면 옅음 → 진함 네 단계.
    var levels: Int = 4
    /// 칸 색(단계에 따라 불투명도만 달라진다).
    var color: Color = CheckTheme.accent
    /// 말풍선·접근성 문구의 값 부분("4시간 12분" / "12,345,678 토큰"). 날짜는 그리드가 붙인다.
    var valueText: (Int) -> String = { "\($0)" }
    /// 커서가 올라가 있는 칸(v0.2.44 호버 말풍선). 격자 전체의 onContinuousHover 좌표를 `cell(at:)` 로 풀어 넣는다.
    /// 테스트가 초기값을 주입해 말풍선을 렌더할 수 있게 init 인자로 받는다(호버 이벤트는 ImageRenderer 가 못 낸다).
    @State private var hovered: Cell?

    /// (주, 요일) 칸 좌표. 튜플이 아닌 이유: `@State`·`==` 비교에 Equatable 이 필요하다.
    struct Cell: Equatable, Sendable {
        let week: Int
        let weekday: Int
    }

    init(
        weeks: Int, values: [[Int]], weekStart: Date, isFuture: @escaping (Int, Int) -> Bool, denominator: Int,
        levels: Int = 4, color: Color = CheckTheme.accent, valueText: @escaping (Int) -> String = { "\($0)" },
        initialHovered: Cell? = nil
    ) {
        self.weeks = weeks
        self.values = values
        self.weekStart = weekStart
        self.isFuture = isFuture
        self.denominator = denominator
        self.levels = levels
        self.color = color
        self.valueText = valueText
        _hovered = State(initialValue: initialHovered)
    }

    // 기하 상수는 nonisolated — 좌표→칸·말풍선 배치 순수 함수(nonisolated, 테스트 대상)가 읽는다. 리터럴 Sendable 이라 안전하다.
    nonisolated static let cellSize: CGFloat = 16
    nonisolated static let cellGap: CGFloat = 2
    nonisolated static let labelWidth: CGFloat = 20
    nonisolated static let cornerRadius: CGFloat = 3
    /// 말풍선과 칸 사이 간격(pt).
    nonisolated static let bubbleGap: CGFloat = 4
    /// 0=월 … 6=일. 월·수·금만 글자를 넣고 나머지는 빈 자리로 둔다(16pt 행에 7글자를 다 쓰면 빽빽하다).
    static let dayLabels = ["월", "", "수", "", "금", "", ""]
    /// 월 라벨 행 높이(pt). 라벨이 없어도 이 높이는 유지해 그리드 상단이 흔들리지 않게 한다.
    nonisolated static let monthLabelHeight: CGFloat = 10

    var body: some View {
        let months = Self.monthLabels(weekStart: weekStart, weeks: weeks)
        VStack(alignment: .leading, spacing: Self.cellGap) {
            // 월 라벨 행. 그 달이 시작되는 열 위에만 "N월"을 두고, 다른 열은 폭만 차지한다.
            HStack(spacing: Self.cellGap) {
                Color.clear
                    .frame(width: Self.labelWidth, height: Self.monthLabelHeight)
                ForEach(0..<max(0, weeks), id: \.self) { week in
                    Text(months.indices.contains(week) ? months[week].map { "\($0)월" } ?? "" : "")
                        .font(.system(size: 8))
                        .foregroundStyle(CheckTheme.secondaryText)
                        .fixedSize()
                        .frame(width: Self.cellSize, height: Self.monthLabelHeight, alignment: .leading)
                }
            }
            ForEach(0..<WorkRhythmHeatmap.dayCount, id: \.self) { weekday in
                HStack(spacing: Self.cellGap) {
                    Text(Self.dayLabels[weekday])
                        .font(.system(size: 9))
                        .foregroundStyle(CheckTheme.secondaryText)
                        .frame(width: Self.labelWidth, alignment: .trailing)
                    ForEach(0..<max(0, weeks), id: \.self) { week in
                        cell(week: week, weekday: weekday)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // ── 호버 말풍선(v0.2.44) ─────────────────────────────────────────────────────────────────
        // 셀마다 `.help` 를 달았던 v0.2.41~43 은 사용자 체감이 "간헐적으로만 뜨고 가독성이 없다"였다 — 시스템 툴팁은
        // 1초 뒤에 뜨고 미세 이동에 사라지며 작은 회색 글씨다. 그래서 **격자 전체**의 커서 좌표를 칸으로 풀어(cell(at:))
        // 자체 말풍선을 즉시 그린다. 칸 사이 2pt 틈은 앞 칸에 귀속되므로(피치 나눗셈) 틈을 지나도 깜빡이지 않는다.
        // 말풍선은 overlay 라 레이아웃(패널 높이 예산)에 참여하지 않고, allowsHitTesting(false) 라 자기 밑의 호버를 가로채지 않는다.
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active(let point):
                let next = Self.cell(at: point, weeks: weeks).flatMap { isFuture($0.week, $0.weekday) ? nil : $0 }
                if hovered != next { hovered = next }
            case .ended:
                if hovered != nil { hovered = nil }
            }
        }
        // 안전망: 연속 호버의 .ended 가 유실돼도(창 전환·팝오버 닫힘) 격자를 떠나면 말풍선을 거둔다.
        .onHover { inside in
            if !inside, hovered != nil { hovered = nil }
        }
        .overlay(alignment: .topLeading) {
            // 조건부(`if let`) 자식에 건 alignmentGuide 는 overlay 정렬에 반영되지 않았다(ImageRenderer 실측: 항상 (0,0)).
            // 그래서 말풍선을 **항상** 자식으로 두고 hovered 가 없으면 투명·빈 문구로 접는다. 가이드는 자식 자신에게 직접 건다.
            let target = hovered ?? Cell(week: 0, weekday: 0)
            let value = value(week: target.week, weekday: target.weekday)
            ContributionCellBubble(
                title: hovered == nil ? "" : Self.dateText(weekStart: weekStart, week: target.week, weekday: target.weekday),
                value: hovered == nil ? "" : valueText(value)
            )
            // 크기를 재지 않고 배치한다: alignmentGuide 가 말풍선 자신의 폭·높이(d)를 주므로 bubbleAnchor 가 그 크기로
            // 원점을 계산하고, 그 원점이 overlay 의 topLeading 에 오도록 가이드를 음수로 돌려준다. 첫 프레임 점프가 없다.
            .alignmentGuide(.leading) { d in
                -Self.bubbleAnchor(week: target.week, weekday: target.weekday, weeks: weeks,
                                   bubbleSize: CGSize(width: d.width, height: d.height)).origin.x
            }
            .alignmentGuide(.top) { d in
                -Self.bubbleAnchor(week: target.week, weekday: target.weekday, weeks: weeks,
                                   bubbleSize: CGSize(width: d.width, height: d.height)).origin.y
            }
            .opacity(hovered == nil ? 0 : 1)
            .allowsHitTesting(false)
            .zIndex(1)
        }
    }

    @ViewBuilder
    private func cell(week: Int, weekday: Int) -> some View {
        if isFuture(week, weekday) {
            // 미래는 투명 — 옅은 바탕(0 = 기록 없음)과 구분되어야 "아직 오지 않은 날"로 읽힌다.
            Color.clear
                .frame(width: Self.cellSize, height: Self.cellSize)
        } else {
            let value = value(week: week, weekday: weekday)
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .fill(Self.color(value: value, denominator: denominator, levels: levels, color: color))
                .frame(width: Self.cellSize, height: Self.cellSize)
                // 시스템 툴팁(.help)은 쓰지 않는다 — 자체 말풍선과 겹치면 1초 뒤 회색 툴팁이 또 뜬다. 접근성 문구만 남긴다.
                .accessibilityLabel(Self.tooltipText(weekStart: weekStart, week: week, weekday: weekday, valueText: valueText(value)))
        }
    }

    // 형이 어긋난 values(빈 배열 등)가 들어와도 인덱스 크래시 없이 0 으로 읽는다.
    private func value(week: Int, weekday: Int) -> Int {
        guard week < values.count, weekday < values[week].count else { return 0 }
        return values[week][weekday]
    }

    /// 격자 로컬 좌표 → 칸. x 에서 요일 라벨 폭+간격을, y 에서 월 라벨 높이+간격을 뺀 뒤 피치(칸+간격)로 나눈다 —
    /// 나눗셈이 간격을 **앞 칸**에 귀속시키므로 칸 사이를 지나는 동안 말풍선이 깜빡이지 않는다. 라벨 영역·격자 밖·음수는 nil.
    /// 격자는 maxWidth: .infinity 라 오른쪽 빈 영역의 좌표도 들어오는데, 열 인덱스가 weeks 를 넘어 nil 로 떨어진다.
    nonisolated static func cell(at point: CGPoint, weeks: Int) -> Cell? {
        guard weeks > 0 else { return nil }
        let pitch = cellSize + cellGap
        let x = point.x - (labelWidth + cellGap)
        let y = point.y - (monthLabelHeight + cellGap)
        guard x >= 0, y >= 0 else { return nil }
        let week = Int(x / pitch), weekday = Int(y / pitch)
        guard week < weeks, weekday < WorkRhythmHeatmap.dayCount else { return nil }
        return Cell(week: week, weekday: weekday)
    }

    /// 말풍선 원점(격자 좌표, 좌상단)과 위/아래 여부. 칸 가로 중앙 정렬, 칸 위 bubbleGap 띄움. 맨 위 두 줄(월·화)은 위에 두면
    /// 월 라벨과 섹션 제목을 덮으므로 칸 아래. 가로는 격자 전체 폭(요일 라벨 포함) 안으로 클램프하고, 말풍선이 격자보다 넓으면 0.
    nonisolated static func bubbleAnchor(week: Int, weekday: Int, weeks: Int, bubbleSize: CGSize) -> (origin: CGPoint, above: Bool) {
        let pitch = cellSize + cellGap
        let totalWidth = labelWidth + cellGap + CGFloat(max(0, weeks)) * cellSize + CGFloat(max(0, weeks - 1)) * cellGap
        let centerX = labelWidth + cellGap + CGFloat(week) * pitch + cellSize / 2
        let cellTop = monthLabelHeight + cellGap + CGFloat(weekday) * pitch
        let above = weekday >= 2
        let x = max(0, min(centerX - bubbleSize.width / 2, totalWidth - bubbleSize.width))
        let y = above ? cellTop - bubbleGap - bubbleSize.height : cellTop + cellSize + bubbleGap
        return (CGPoint(x: x, y: y), above)
    }

    nonisolated static let weekdayNames = ["월", "화", "수", "목", "금", "토", "일"]

    /// 말풍선 첫 줄 "9월 3일 (목)". 날짜 오프셋은 tooltipText 와 같은 식(주 × 7 + 요일)이다.
    nonisolated static func dateText(weekStart: Date, week: Int, weekday: Int) -> String {
        let calendar = TeamWeeklyGoal.kstCalendar
        guard let day = calendar.date(byAdding: .day, value: week * WorkRhythmHeatmap.dayCount + weekday, to: weekStart) else {
            return ""
        }
        let c = calendar.dateComponents([.month, .day], from: day)
        let name = weekdayNames.indices.contains(weekday) ? weekdayNames[weekday] : ""
        return "\(c.month ?? 0)월 \(c.day ?? 0)일 (\(name))"
    }

    /// 칸 접근성 문구 "9월 3일 · 4시간 12분"(v0.2.43 까지는 시스템 툴팁이었다). 날짜는 weekStart 에서 (주 × 7 + 요일)일 뒤의 KST 날짜다 — 이 오프셋이
    /// 하루라도 어긋나면 잔디 전체가 하루씩 밀려 보이는데 픽셀 테스트는 .help 를 못 보므로 순수 함수로 떼어 검증한다.
    /// valueText 는 호출부가 이미 만든 값 문구("근무 없음" / "1.2M 토큰")라 그리드는 데이터 종류를 모른다.
    nonisolated static func tooltipText(weekStart: Date, week: Int, weekday: Int, valueText: String) -> String {
        let calendar = TeamWeeklyGoal.kstCalendar
        guard let day = calendar.date(byAdding: .day, value: week * WorkRhythmHeatmap.dayCount + weekday, to: weekStart) else {
            return valueText
        }
        let c = calendar.dateComponents([.month, .day], from: day)
        return "\(c.month ?? 0)월 \(c.day ?? 0)일 · \(valueText)"
    }

    /// 농도 단계(0…levels). 0 은 기록 없음, levels 는 분모 이상. ceil 이라 1초라도 있으면 1단계 — 옅은 바탕과 구분된다.
    /// 순수 함수라 nonisolated(단위 테스트 대상). 정수 산술로 계산해 부동소수 경계(정확히 분모의 1/4 등)에서 흔들리지 않는다.
    nonisolated static func level(value: Int, denominator: Int, levels: Int) -> Int {
        guard value > 0, levels > 0 else { return 0 }
        guard denominator > 0 else { return levels }
        return min(levels, (value * levels + denominator - 1) / denominator)
    }

    /// 단계별 불투명도. 히트맵(0.20 + 0.80 × 농도)과 같은 사다리를 써서 두 격자의 '진함'이 같은 뜻이 되게 한다.
    nonisolated static func opacity(level: Int, levels: Int) -> Double {
        guard level > 0, levels > 0 else { return 0 }
        return 0.20 + 0.80 * Double(min(level, levels)) / Double(levels)
    }

    /// 칸 색: 0단계는 옅은 fieldFill(빈 칸), 그 외엔 단계 불투명도의 color.
    nonisolated static func color(value: Int, denominator: Int, levels: Int, color: Color) -> Color {
        let step = level(value: value, denominator: denominator, levels: levels)
        guard step > 0 else { return CheckTheme.fieldFill }
        return color.opacity(opacity(level: step, levels: levels))
    }

    /// 열마다 달 라벨(1…12) 또는 nil. 어떤 달의 1일이 그 주에 들어 있으면 그 열이 그 달의 시작 열이다
    /// (일요일이 속한 달이 그 전주 일요일의 달과 다르면 새 달이 시작됐다). 첫 열은 그 앞 주와 비교한다.
    nonisolated static func monthLabels(weekStart: Date, weeks: Int) -> [Int?] {
        let calendar = TeamWeeklyGoal.kstCalendar
        guard weeks > 0 else { return [] }
        func monthOfSunday(week: Int) -> Int? {
            calendar.date(byAdding: .day, value: week * WorkRhythmHeatmap.dayCount + WorkRhythmHeatmap.dayCount - 1, to: weekStart)
                .map { calendar.component(.month, from: $0) }
        }
        var previous = monthOfSunday(week: -1)
        return (0..<weeks).map { week in
            let current = monthOfSunday(week: week)
            defer { previous = current }
            return current != previous ? current : nil
        }
    }
}

/// 잔디 호버 말풍선(v0.2.44): 날짜·요일 한 줄 + 값 한 줄. 패널과 같은 어두운 카드에 밝은 글씨 — 시스템 툴팁의 작은 회색
/// 글씨가 "가독성이 없다"는 지적의 답이다. 크기는 내용에 맞춰 고정(fixedSize)되고 배치는 ContributionGridView.bubbleAnchor 가 한다.
struct ContributionCellBubble: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(CheckTheme.primaryText)
            Text(value)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(CheckTheme.primaryText)
        }
        .lineLimit(1)
        .fixedSize()
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(CheckTheme.panelElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(CheckTheme.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
    }
}

/// 잔디 범례: 옅음 → 진함 단계 칸을 작게 나열한다(캡션 행 오른쪽용, 8pt 칸).
struct ContributionLegendView: View {
    var levels: Int = 4
    var color: Color = CheckTheme.accent

    static let cellSize: CGFloat = 8

    var body: some View {
        HStack(spacing: 3) {
            Text("적게")
                .font(.system(size: 8))
                .foregroundStyle(CheckTheme.secondaryText)
            ForEach(0...max(1, levels), id: \.self) { step in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(step == 0 ? CheckTheme.fieldFill : color.opacity(ContributionGridView.opacity(level: step, levels: levels)))
                    .frame(width: Self.cellSize, height: Self.cellSize)
            }
            Text("많이")
                .font(.system(size: 8))
                .foregroundStyle(CheckTheme.secondaryText)
        }
        .fixedSize()
    }
}

// MARK: - Auth buttons + fields

struct AuthButton: View {
    let title: String
    let icon: String
    var prominent: Bool = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.caption.weight(.bold))
                .foregroundStyle(prominent ? .white : CheckTheme.primaryText)
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .background {
                    if prominent {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(CheckTheme.startGradient)
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.white.opacity(0.06))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(CheckTheme.border, lineWidth: 1))
                    }
                }
                .brightness(hovering ? 0.05 : 0)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

struct CredentialField: View {
    let title: String
    let icon: String
    @Binding var text: String
    var isSecure = false
    /// true면 포커스 시 영어 자판으로 자동 전환하고, 비-ASCII 입력을 걸러 낸 뒤 안내를 띄운다.
    var enforcesASCII = false
    /// 공백 허용 여부. 비밀번호는 허용, 이메일은 차단한다. `enforcesASCII`일 때만 의미가 있다.
    var allowsSpace = true
    /// true면 입력값을 대문자로 정규화해 표시한다(팀 코드 필드용). ASCII 필터와 함께 쓸 수 있다.
    var uppercases = false
    /// 외부(패널) 포커스 상태. Enter-키 체이닝을 위해 부모가 소유하고 각 필드가 자기 케이스로 바인딩한다.
    /// nil이면 내부 isFocused만 쓰는 독립 필드(단위 테스트 등)로 동작한다.
    var focus: FocusState<AuthFocusField?>.Binding?
    /// 이 필드가 대응하는 포커스 케이스. `focus`와 함께 주어져야 체이닝이 활성화된다.
    var fieldIdentifier: AuthFocusField?
    /// 리턴 키 라벨. 다음 필드로 넘기는 필드는 `.next`, 제출 필드는 `.go`.
    var submitLabel: SubmitLabel = .return
    /// Enter(제출) 시 실행할 동작 — 다음 필드로의 포커스 이동 또는 로그인/가입 제출.
    var onSubmit: (() -> Void)?

    @FocusState private var isFocused: Bool
    @State private var showWarning: Bool
    @State private var warningTask: Task<Void, Never>?

    init(
        title: String,
        icon: String,
        text: Binding<String>,
        isSecure: Bool = false,
        enforcesASCII: Bool = false,
        allowsSpace: Bool = true,
        uppercases: Bool = false,
        warnsInitially: Bool = false,
        focus: FocusState<AuthFocusField?>.Binding? = nil,
        fieldIdentifier: AuthFocusField? = nil,
        submitLabel: SubmitLabel = .return,
        onSubmit: (() -> Void)? = nil
    ) {
        self.title = title
        self.icon = icon
        self._text = text
        self.isSecure = isSecure
        self.enforcesASCII = enforcesASCII
        self.allowsSpace = allowsSpace
        self.uppercases = uppercases
        // warnsInitially는 렌더 스냅샷 등 미리보기에서 안내가 켜진 상태를 재현하기 위한 시드값이다.
        self._showWarning = State(initialValue: warnsInitially)
        self.focus = focus
        self.fieldIdentifier = fieldIdentifier
        self.submitLabel = submitLabel
        self.onSubmit = onSubmit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                    .foregroundStyle(CheckTheme.secondaryText)
                    .frame(width: 16)
                ZStack(alignment: .leading) {
                    // 플레이스홀더는 비었을 때만 깔고, 히트테스트 대상에서 제외한다.
                    if text.isEmpty {
                        Text(title)
                            .foregroundStyle(CheckTheme.secondaryText)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .allowsHitTesting(false)
                    }
                    styledField
                }
            }
            .font(.subheadline)
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(CheckTheme.fieldFill)
                    // 안내가 떠 있는 동안엔 테두리를 danger로 물들여 레이아웃 밀림 없이도 상태를 알린다.
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(showWarning ? CheckTheme.danger : CheckTheme.border, lineWidth: 1))
            )
            if enforcesASCII {
                // 안내 캡션은 항상 자리를 차지하고 보임/숨김만 opacity로 토글한다 — 등장/소멸로 인한
                // 높이 변화(창 튐)를 원천 제거한다. ASCII 필드(이메일·비밀번호)만 슬롯을 확보한다.
                Text("영어 문자만 입력할 수 있어요")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(CheckTheme.danger)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .opacity(showWarning ? 1 : 0)
                    .accessibilityHidden(!showWarning)
                    .accessibilityLabel("영어 문자만 입력할 수 있어요")
            }
        }
        .onChange(of: isFocused) { _, focused in
            // 외부 포커스를 안 쓰는 독립 필드 경로: 포커스를 얻는 순간 영어 자판으로 전환한다.
            guard focused, enforcesASCII else { return }
            EnglishInputSource.activate()
        }
        .onChange(of: focus?.wrappedValue) { _, newValue in
            // 외부 포커스 체이닝 경로: 이 필드로 포커스가 옮겨 오면 영어 자판으로 전환한다.
            guard let fieldIdentifier, newValue == fieldIdentifier, enforcesASCII else { return }
            EnglishInputSource.activate()
        }
        .onChange(of: text) { _, newValue in
            guard enforcesASCII || uppercases else { return }
            var cleaned = newValue
            var asciiRemoved = false
            if enforcesASCII {
                let filtered = ASCIIInputFilter.filtered(cleaned, allowsSpace: allowsSpace)
                asciiRemoved = filtered != cleaned
                cleaned = filtered
            }
            if uppercases {
                cleaned = cleaned.uppercased()
            }
            // cleaned == newValue면 대입을 건너뛰어 IME 조합 중간 상태에서의 무한루프를 막는다.
            if cleaned != newValue {
                text = cleaned
            }
            // 안내는 ASCII 필터가 실제로 문자를 제거했을 때만 띄운다(대문자화는 안내 대상이 아님).
            if asciiRemoved {
                triggerWarning()
            }
        }
        .onDisappear {
            warningTask?.cancel()
        }
    }

    // 안내 캡션을 띄우고 약 2.5초 뒤 자동으로 감춘다. 연속 트리거 시 이전 타이머를 리셋한다.
    private func triggerWarning() {
        warningTask?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) {
            showWarning = true
        }
        warningTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                showWarning = false
            }
        }
    }

    // 공통 스타일 + 제출/포커스 배선을 얹은 실제 입력 필드.
    // 외부 포커스가 주어지면 자기 케이스로 바인딩(체이닝), 없으면 내부 isFocused로 동작한다.
    @ViewBuilder
    private var styledField: some View {
        let base = field
            .textFieldStyle(.plain)
            .foregroundStyle(CheckTheme.primaryText)
            .tint(CheckTheme.accent)
            .accessibilityLabel(title)
            .submitLabel(submitLabel)
            .onSubmit { onSubmit?() }
        if let focus, let fieldIdentifier {
            base.focused(focus, equals: fieldIdentifier)
        } else {
            base.focused($isFocused)
        }
    }

    @ViewBuilder
    private var field: some View {
        // 플레이스홀더는 위 Text 오버레이가 담당하므로 라벨은 비운다.
        if isSecure {
            SecureField("", text: $text)
        } else {
            TextField("", text: $text)
        }
    }
}

// MARK: - Team code preview slot (signup / teamless)

/// 팀 코드 필드 아래 고정 높이 슬롯. 코드 미리보기 결과를 한 줄로 보여 준다.
/// - 성공(joinPreview 있음): 그린 "✓ 팀 브라보 · 3명 · 주 60시간"
/// - 실패/안내(joinPreviewMessage 있음): danger 문구
/// - 미확인(둘 다 없음): 비어 있지만 높이는 항상 확보해 입력 중 점프를 없앤다.
struct TeamCodePreviewSlot: View {
    let preview: TeamJoinPreview?
    let message: String

    var body: some View {
        HStack(spacing: 6) {
            if let preview {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text("팀 \(preview.name) · \(preview.memberCount)명 · 주 \(preview.weeklyGoalHours)시간")
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
            } else if !message.isEmpty {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text(message)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(preview != nil ? CheckTheme.working : CheckTheme.danger)
        // 결과 유무와 무관하게 슬롯 높이를 고정해 코드 입력 중 카드 높이가 튀지 않게 한다.
        .frame(maxWidth: .infinity, minHeight: 18, alignment: .leading)
    }
}

// MARK: - Team code field (signup / teamless)

/// 팀 코드 입력 필드 + 미리보기 슬롯 묶음. CredentialField(대문자·ASCII) + TeamCodePreviewSlot.
/// 입력이 바뀌면 ~0.5초 디바운스 후 onDebouncedChange 로 미리보기 갱신을 요청한다(디바운스는 UI 몫).
struct TeamCodeField: View {
    @Binding var code: String
    let preview: TeamJoinPreview?
    let message: String
    /// 디바운스가 끝난 뒤 호출된다(store.previewTeamCode() 배선용).
    var onDebouncedChange: () -> Void = {}

    @State private var debounceTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            CredentialField(
                title: "팀 코드",
                icon: "key.fill",
                text: $code,
                enforcesASCII: true,
                allowsSpace: false,
                uppercases: true
            )
            TeamCodePreviewSlot(preview: preview, message: message)
        }
        .onChange(of: code) { _, _ in
            debounceTask?.cancel()
            debounceTask = Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.5))
                guard !Task.isCancelled else { return }
                onDebouncedChange()
            }
        }
        .onDisappear { debounceTask?.cancel() }
    }
}

// MARK: - Weekly goal stepper (create team)

/// 팀 만들기 폼의 주간 목표 스테퍼. 필드 톤 + 순수 SwiftUI -/+ 버튼(ImageRenderer 렌더 가능).
/// 범위 1~168시간, "N시간" 표기.
struct WeeklyGoalStepper: View {
    @Binding var hours: Int
    let range: ClosedRange<Int> = 1...168

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "target")
                .font(.system(size: 12))
                .foregroundStyle(CheckTheme.secondaryText)
                .frame(width: 16)
            Text("주간 목표")
                .font(.subheadline)
                .foregroundStyle(CheckTheme.primaryText)
            Spacer(minLength: 6)
            Text("\(hours)시간")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CheckTheme.primaryText)
                .monospacedDigit()
            HStack(spacing: 0) {
                stepButton(icon: "minus", enabled: hours > range.lowerBound) {
                    hours = max(range.lowerBound, hours - 1)
                }
                Rectangle()
                    .fill(CheckTheme.border)
                    .frame(width: 1, height: 18)
                stepButton(icon: "plus", enabled: hours < range.upperBound) {
                    hours = min(range.upperBound, hours + 1)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.white.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(CheckTheme.border, lineWidth: 1))
            )
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(CheckTheme.fieldFill)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(CheckTheme.border, lineWidth: 1))
        )
    }

    private func stepButton(icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(enabled ? CheckTheme.primaryText : CheckTheme.secondaryText.opacity(0.4))
                .frame(width: 28, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

// MARK: - Created-team invite code share card

/// 팀 생성 직후 참여코드 공유 카드. 큰 모노스페이스 코드 + [복사] + 안내 + [확인].
/// 로그인/무소속 패널이 createdTeamCode 존재 시 폼 대신 이 카드를 보여 준다.
struct CreatedTeamCodeCard: View {
    let code: String
    var onConfirm: () -> Void = {}

    @State private var copied = false

    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 4) {
                Image(systemName: "party.popper.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(CheckTheme.working)
                Text("팀이 만들어졌어요")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(CheckTheme.primaryText)
            }
            Text(code)
                .font(.system(size: 30, weight: .heavy, design: .monospaced))
                .foregroundStyle(CheckTheme.primaryText)
                .tracking(4)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(CheckTheme.fieldFill)
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(CheckTheme.border, lineWidth: 1))
                )
            Text("팀원에게 이 코드를 전달하세요")
                .font(.caption)
                .foregroundStyle(CheckTheme.secondaryText)
                .lineLimit(1)
            HStack(spacing: 8) {
                Button {
                    CheckPasteboard.copy(code)
                    copied = true
                } label: {
                    Label(copied ? "복사됨" : "복사", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(CheckTheme.primaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.white.opacity(0.06))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(CheckTheme.border, lineWidth: 1))
                        )
                }
                .buttonStyle(.plain)
                AuthButton(title: "확인", icon: "checkmark.circle.fill", prominent: true, action: onConfirm)
            }
        }
    }
}

// MARK: - Owner invite code reveal (team card header)

/// 팀 카드 헤더에서 키 버튼을 눌렀을 때 인라인으로 펼쳐지는 참여코드 행.
/// 모노스페이스 코드 + [복사] 버튼. 상단 앵커 원칙상 헤더 아래로만 자란다.
struct InviteCodeInlineRow: View {
    let code: String

    @State private var copied = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "key.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(CheckTheme.accent)
            Text("참여코드")
                .font(.caption2)
                .foregroundStyle(CheckTheme.secondaryText)
            Text(code)
                .font(.system(.subheadline, design: .monospaced).weight(.bold))
                .foregroundStyle(CheckTheme.primaryText)
                .tracking(2)
                .lineLimit(1)
            Spacer(minLength: 6)
            Button {
                CheckPasteboard.copy(code)
                copied = true
            } label: {
                Label(copied ? "복사됨" : "복사", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(CheckTheme.accent)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(Capsule().fill(CheckTheme.accent.opacity(0.16)))
                    .fixedSize()
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(CheckTheme.accent.opacity(0.10))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(CheckTheme.accent.opacity(0.35), lineWidth: 1))
        )
    }
}

// MARK: - Pasteboard helper

/// NSPasteboard 복사 래퍼. 참여코드 공유(복사 버튼)에 쓴다.
enum CheckPasteboard {
    static func copy(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }
}

// MARK: - Brand header (login)

struct BrandHeader: View {
    // 부제는 화면(로그인/가입)에 따라 달라진다. 기본값은 로그인 화면 문구.
    var subtitle: String = "팀 근무 타이머"

    var body: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(CheckTheme.startGradient)
                    .frame(width: 38, height: 38)
                Image(systemName: "checkmark")
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("aing-check")
                    .font(.system(.title3, design: .rounded).weight(.heavy))
                    .foregroundStyle(CheckTheme.primaryText)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Auth mode switch link

/// 로그인 ↔ 가입 화면을 전환하는 텍스트 링크 버튼.
/// 안내 문구는 secondary, 실제 링크 단어는 accent + hover 시 밑줄/밝기로 버튼임을 드러낸다.
struct AuthLinkButton: View {
    let prompt: String
    let action: String
    let perform: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: perform) {
            HStack(spacing: 5) {
                // 안내 문구가 비어 있으면(예: "코드로 참여하기" 단독) 링크 단어만 보인다.
                if !prompt.isEmpty {
                    Text(prompt)
                        .foregroundStyle(CheckTheme.secondaryText)
                }
                Text(action)
                    .foregroundStyle(CheckTheme.accent)
                    .underline(hovering)
                    .brightness(hovering ? 0.12 : 0)
            }
            .font(.caption.weight(.medium))
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Footer utility bar pieces

/// 찌르기 **수신 채널**(초인종 리얼타임)이 죽었다는 사실을 화면에 띄울지 결정하는 **유일한 판정**.
///
/// 순수 함수인 것이 요점이다: 세 표면(푸터 점·메인 메뉴 찌르기 아이콘·콕찌르기 안내줄)이 이 한 함수를
/// 부르므로, 한 곳만 고쳐 세 얼굴이 서로 다른 말을 하는 일이 원리적으로 없다("게이트는 짝으로 있다").
///
/// ★ **출시 기본값 `.idle(.disabled)` 에서는 절대 뜨지 않는다.** 리얼타임을 빼고 배포하는 경우
///   (사장님 확정 2) 전 사용자가 이 상태이고, 그때 경고가 뜨면 38명 전원이 멀쩡한 폴링을 두고
///   "찌르기가 고장났다"고 읽는다. 이 한 줄이 이 릴리스에서 가장 위험한 자리다.
///
/// ★ **연결 시도 중(`.connecting`)에는 뜨지 않는다.** 앱을 막 켠 사람에게 경고부터 던지지 않는다.
///
/// ★ **재연결 중에는 유예(45초) 안에서는 뜨지 않는다.** 맥 뚜껑을 닫았다 열면 소켓은 반드시 끊기고,
///   그때마다 경고가 뜨면 경고는 곧 배경이 되어 진짜 고장을 가린다. 유예를 **넘긴** 재연결은
///   실패가 확정된 것과 같다 — 3분째 재시도 중인 사람은 실제로 찌르기를 못 받고 있고,
///   "아직 재연결 중"은 그 사실을 가리는 변명일 뿐이다. 기준은 시도 **횟수**가 아니라
///   `Backoff.failingSince` 이후 경과 시간 하나다(백오프가 1·2·4초라 3회는 7초 만에 채워지는데,
///   절전 해제 직후 네트워크가 아직 안 올라온 그 7초가 정확히 오탐 구간이다).
enum PokeConnectionNotice {
    /// 실패가 이만큼 이어지면 확정으로 본다. **RealtimeLinkConstants 의 단일 출처를 그대로 쓴다** —
    /// 여기 45 를 리터럴로 베끼면 링이 임계를 바꾼 날 화면만 옛 시간을 본다.
    static var graceSeconds: TimeInterval { RealtimeLinkConstants.failedAfterSeconds }

    /// 콕찌르기 패널 안내줄(넓다 — 2줄까지 허용). 사용자가 갈 곳을 정확히 하나 가리킨다(푸터 새로고침).
    static let panelText = "찌르기 연결이 끊겼어요 — 새로고침을 눌러 보세요"
    /// 푸터 한 줄(짧게). caption2 8자 ≈ 80pt ≤ FooterWidthBudget 문구 예산.
    static let footerText = "찌르기 연결 끊김"
    /// 메인 메뉴 찌르기 아이콘의 툴팁. **높이 0pt 로 얹는 유일한 표면**이라 문구는 여기 하나뿐이다.
    static let iconHelp = "콕 찌르기 (수신 연결이 끊겼어요)"

    static func shouldWarn(state: RealtimeState, now: Date) -> Bool {
        switch state {
        case .idle, .connecting, .subscribed:
            return false
        case .failed:
            return true
        case .reconnecting(let backoff):
            return now.timeIntervalSince(backoff.failingSince) >= graceSeconds
        }
    }
}

struct SyncStatusView: View {
    let message: String
    /// 찌르기 수신 연결이 끊겼는가(PokeConnectionNotice.shouldWarn 의 결과). true 면 점이 danger 로 바뀌고,
    /// **동기화 문구가 정상일 때만** 문구를 이 사실로 교체한다 — 로그인/동기화 실패가 더 급하고,
    /// 그때 찌르기가 안 오는 건 원인이 아니라 결과다.
    ///
    /// 점은 화이트리스트와 무관하게 danger 로 바꾼다: 문구 자리를 다른 고장에 내준 상태에서도
    /// 신호 하나는 남아야 하고, 그 하나가 없으면 이 표면은 "가장 흔한 날에만 보이는 경고"가 된다.
    var pokeDisconnected: Bool = false

    private var isSynced: Bool {
        message == "동기화됨"
    }

    /// 문구까지 바꾸는가. 점만 바꾸는 경우와 구별된다.
    private var showsDisconnectText: Bool { pokeDisconnected && isSynced }

    private var dotColor: Color {
        if pokeDisconnected { return CheckTheme.danger }
        return isSynced ? CheckTheme.working : CheckTheme.pending
    }

    private var text: String { showsDisconnectText ? PokeConnectionNotice.footerText : message }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(dotColor)
                .frame(width: 7, height: 7)
                .shadow(color: dotColor.opacity(0.5), radius: 3)
            Text(text)
                .font(.caption2)
                .foregroundStyle(CheckTheme.secondaryText)
                .lineLimit(1)
                // 말줄임 전에 먼저 줄여 본다 — 잘리면 "자리 비움으로 자동…"처럼 핵심어('근무종료됨')가
                // 사라져 무슨 일이 일어났는지 알 수 없다. 배율 상한은 FooterWidthBudget 이 지킨다.
                .minimumScaleFactor(0.7)
                .allowsTightening(true)
        }
    }
}

struct IconButton: View {
    let icon: String
    let help: String
    var tint: Color = CheckTheme.secondaryText
    /// false 면 흐리게 그리고 눌리지 않는다(예: 토큰 순위판에서 현재 월보다 미래로는 갈 수 없음).
    /// 자리를 유지한 채 비활성만 표시해, 버튼이 사라졌다 나타나며 헤더가 흔들리는 일을 막는다.
    var enabled: Bool = true
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(hovering ? CheckTheme.primaryText : tint)
                .frame(width: 27, height: 27)
                .background(
                    Circle().fill(Color.white.opacity(hovering ? 0.14 : 0.06))
                )
        }
        .buttonStyle(.plain)
        .onHover { hovering = enabled && $0 }
        .opacity(enabled ? 1 : 0.32)
        .disabled(!enabled)
        .help(help)
    }
}

// MARK: - Shared bits

struct PanelDivider: View {
    var body: some View {
        Rectangle()
            .fill(CheckTheme.border)
            .frame(height: 1)
    }
}

extension View {
    func panelStyle() -> some View {
        background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(CheckTheme.panel)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(CheckTheme.border, lineWidth: 1)
                )
        )
    }
}
