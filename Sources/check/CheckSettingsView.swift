import Observation
import SwiftUI
import CheckCore

// MARK: - Switch (커스텀 토글)
//
// 왜 macOS 기본 스위치를 쓰지 않는가.
// 기본 스위치는 시스템 강조색(대개 파랑) 알약 하나다 — 어느 앱에나 있는 얼굴이라, 설정 창만
// "다른 앱에서 오려 붙인 화면"처럼 보인다. 이 앱은 이미 진행 게이지·주간 목표 바에 초록→파랑
// 그라디언트(CheckTheme.gaugeGradient)를 쓴다. 켜짐 트랙에 **같은 그라디언트**를 깔면
// 설정 창이 앱의 일부로 읽히고, "켜짐 = 이 앱에서 초록→파랑으로 차오르는 것"이라는 기존 문법과도 붙는다.
//
// 색 근거(전부 CheckTheme 토큰):
//  - 꺼짐 트랙: trackFill(검정 28%) + border(흰색 14%) 미세 스트로크. 게이지의 '빈 트랙'과 같은 재질이라
//    화면 안에서 스위치가 처음 보는 물건이 아니다.
//  - 켜짐 트랙: gaugeGradient(초록 → 파랑, 가로). 손잡이가 도착하는 오른쪽 끝이 파랑(accent)이라
//    켜짐 상태의 글로우도 accent 로 맞춘다 — 그라디언트 자체엔 그림자 색을 줄 수 없으니 도착점 색을 쓴다.
//  - 손잡이: 흰색 계열(꺼짐 0.90→0.76, 켜짐 1.0→0.90 세로 그라디언트). 켜질 때 살짝 '불이 들어온다'.

/// 스위치의 **그림 전부**. ToggleStyle/ButtonStyle 안이 아니라 값만 받는 순수 뷰로 떼어 둔 이유가 있다:
/// 눌림 상태(`isPressed`)는 ButtonStyle 안에서만 알 수 있어서, 그림을 그 안에 묻으면 '눌린 스위치'를
/// ImageRenderer 로 그려 볼 방법이 사라진다. 꺼짐/켜짐/눌림 세 상태를 전부 픽셀로 검증하려면
/// 그림이 바깥에서 **값으로** 만들어져야 한다(이 저장소의 렌더 검증 관례).
struct CheckSwitchTrack: View {
    let isOn: Bool
    /// 마우스를 누르고 있는 동안 true. 손잡이가 진행 방향으로 살짝 늘어난다.
    var isPressed: Bool = false
    /// 시스템 '동작 줄이기'. true 면 스프링 없이 즉시 전환한다(호출부가 환경값을 읽어 넘긴다 —
    /// 스타일 구조체 안에서 @Environment 를 읽는 대신 값으로 받아야 렌더 스냅샷이 두 모드를 다 그릴 수 있다).
    var reduceMotion: Bool = false

    static let width: CGFloat = 44
    static let height: CGFloat = 26
    static let knobSize: CGFloat = 22
    static let inset: CGFloat = 2
    /// 손잡이가 실제로 미끄러지는 거리(pt). 렌더 검증이 "꺼짐/켜짐의 손잡이 위치가 다른가"를 이 값으로 잰다.
    static var travel: CGFloat { width - knobSize - inset * 2 }

    /// 0 = 꺼짐, 1 = 켜짐. 손잡이 위치와 트랙 색이 **같은 값**에서 나오는 것이 요점이다 —
    /// 둘을 따로 애니메이션하면 미끄러짐과 색 변화가 어긋나 싸구려로 보인다.
    private var progress: CGFloat { isOn ? 1 : 0 }

    var body: some View {
        ZStack(alignment: .leading) {
            // 꺼짐 트랙은 항상 깔려 있고, 켜짐 그라디언트가 그 위에서 페이드인한다.
            // (SwiftUI 는 Color → LinearGradient 를 보간하지 못한다. 두 겹 크로스페이드가 유일하게
            //  정직한 방법이고, 같은 트랜잭션 안이라 손잡이 이동과 정확히 같은 커브를 탄다.)
            Capsule()
                .fill(CheckTheme.trackFill)
                .overlay(Capsule().strokeBorder(CheckTheme.border, lineWidth: 1))
            Capsule()
                .fill(CheckTheme.gaugeGradient)
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
                // 켜짐 글로우. 근무 알약(WorkTogglePill)이 쓰는 것과 같은 문법 — 상태색 후광.
                .shadow(color: CheckTheme.accent.opacity(0.34), radius: 6, y: 1)
                .opacity(progress)
            knob
                .padding(.leading, Self.inset)
                .offset(x: progress * Self.travel)
        }
        .frame(width: Self.width, height: Self.height)
        // 트랙 색(opacity)과 손잡이 위치(offset)가 이 한 줄 아래에 함께 있어 같은 스프링을 탄다.
        .animation(reduceMotion ? nil : .spring(response: 0.30, dampingFraction: 0.70), value: isOn)
        // 눌림은 더 짧고 더 단단한 스프링 — 손끝에 붙는 반응이지 이동이 아니다.
        .animation(reduceMotion ? nil : .spring(response: 0.17, dampingFraction: 0.80), value: isPressed)
    }

    private var knob: some View {
        ZStack {
            Circle().fill(
                LinearGradient(
                    colors: [Color(white: 0.90), Color(white: 0.76)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            Circle().fill(
                LinearGradient(
                    colors: [Color(white: 1.0), Color(white: 0.90)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            .opacity(progress)
        }
        .frame(width: Self.knobSize, height: Self.knobSize)
        .shadow(color: .black.opacity(0.38), radius: 2.5, y: 1)
        // 누르면 진행 방향으로만 늘어난다(꺼짐이면 왼쪽 고정→오른쪽으로, 켜짐이면 반대).
        // 앵커를 고정하지 않으면 손잡이가 트랙 밖으로 삐져나온다.
        // 배율은 4배 확대 렌더로 눈금을 맞췄다: 1.10 은 확대해서 보면 계란처럼 읽히고, 1.08/0.95 는
        // 실제 크기(22pt)에서 '눌렸다'만 전하고 지나간다.
        .scaleEffect(
            x: isPressed ? 1.08 : 1.0,
            y: isPressed ? 0.95 : 1.0,
            anchor: isOn ? .trailing : .leading
        )
    }
}

/// 스위치의 버튼 껍데기. 그림은 `CheckSwitchTrack` 이 다 그리고, 여기서는 눌림/호버만 얹는다.
/// hover 를 위해 @State 가 필요한데 ButtonStyle 자체는 상태를 못 가지므로 한 겹 뷰로 감싼다.
private struct CheckSwitchButtonStyle: ButtonStyle {
    let isOn: Bool
    let reduceMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        Face(isOn: isOn, isPressed: configuration.isPressed, reduceMotion: reduceMotion)
    }

    private struct Face: View {
        let isOn: Bool
        let isPressed: Bool
        let reduceMotion: Bool
        @State private var hovering = false

        var body: some View {
            CheckSwitchTrack(isOn: isOn, isPressed: isPressed, reduceMotion: reduceMotion)
                .brightness(hovering ? 0.05 : 0)
                // 알약 모양이 아니라 사각형으로 잡는다 — 모서리 근처 클릭이 빗나가지 않게.
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
        }
    }
}

/// 설정 행 전용 ToggleStyle: `[라벨(+설명)]  ······  [스위치]`.
/// 라벨은 호출부가 넘긴 Toggle 라벨을 그대로 쓴다 — 행이 라벨을, 스타일이 스위치를 각자 그리면
/// 접근성에서 둘이 따로 놀아 "무엇의 스위치인지" 읽히지 않는다.
struct CheckSettingsToggleStyle: ToggleStyle {
    /// 환경값을 스타일 안에서 읽지 않고 값으로 받는다(CheckSwitchTrack 주석과 같은 이유).
    var reduceMotion: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .center, spacing: 12) {
            configuration.label
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                configuration.isOn.toggle()
            } label: {
                EmptyView()
            }
            .buttonStyle(CheckSwitchButtonStyle(isOn: configuration.isOn, reduceMotion: reduceMotion))
            // 이 저장소의 실사고 재발 방지: macOS 는 창이 열릴 때 첫 포커스를 받은 컨트롤에 파란 포커스 링을
            // 그린다(v0.2.29 근무 버튼 신고). 알약/스위치처럼 자기 테두리를 가진 컨트롤 위에 사각 링이
            // 겹치면 고장난 것처럼 보인다. **범위를 이 버튼 하나로 좁힌 것이 요점** — 창 루트나 컨테이너에
            // 걸면 아래 별명 입력칸의 커서 표시까지 함께 죽는다(어디에 타이핑되는지 모르는 화면이 된다).
            // focusable(false) 가 아닌 이유도 같다: 키보드 도달은 남기고 **그리는 것만** 끈다.
            .focusEffectDisabled()
        }
        .contentShape(Rectangle())
        // 커스텀 ToggleStyle 은 기본 스위치의 접근성을 물려받지 않는다 — 라벨+값+동작을 직접 세워 준다.
        .accessibilityElement(children: .combine)
        // isToggle 만 주면 VoiceOver 에서 활성화 방법이 흐려진다 — isButton 을 함께 준다.
        .accessibilityAddTraits([.isButton, .isToggle])
        .accessibilityValue(configuration.isOn ? "켜짐" : "꺼짐")
        .accessibilityAction { configuration.isOn.toggle() }
    }
}

// MARK: - Rows

/// 설정 한 행: 굵은 제목 + 한 줄 설명 + 오른쪽 스위치.
/// 설명이 **필수 인자**인 것이 의도다 — "AI 토큰 사용량 공개" 같은 라벨은 제목만으로 무슨 일이
/// 벌어지는지 알 수 없고, 그걸 모르는 채 켜고 끄는 것이 이 창을 만든 이유(숨은 설정)와 같은 실패다.
struct CheckSettingsToggleRow: View {
    let title: String
    let detail: String
    @Binding var isOn: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CheckTheme.primaryText)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                    // 창을 좁혀도 말줄임 대신 줄바꿈한다 — 설명은 잘리면 존재 의의가 없다.
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(CheckSettingsToggleStyle(reduceMotion: reduceMotion))
    }
}

/// 별명 행. **토글이 아니다** — 주 1회 쿨타임과 중복 금지가 걸린 서버 검증 값이라 스위치로 만들 수 없다.
///
/// 예전 팝오버 인라인 편집기(v0.2.32 에 삭제)와 달리 **스토어 편집 상태를 공유하지 않는다**:
/// `store.isEditingDisplayName` / `store.displayNameDraft` 는 팀 목록 행이 폴링 재구성에도 살아남게
/// 하려고 스토어에 둔 값이라, 설정 창이 그걸 같이 쓰면 설정 창을 여는 것만으로 팝오버의 내 행이
/// 편집 모드로 바뀐다. 여기서는 로컬 초안을 쓰고, 스토어에는 **규칙(잠금·저장)만** 물어본다.
private struct DisplayNameSettingsRow: View {
    let store: WorkTimerStore

    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text("별명")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CheckTheme.primaryText)
                Text("팀 목록과 순위판에 보이는 이름이에요. 한 번 바꾸면 일주일 동안 다시 못 바꿔요.")
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                TextField("별명", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                    .foregroundStyle(CheckTheme.primaryText)
                    .tint(CheckTheme.accent)
                    .lineLimit(1)
                    .disabled(isFieldDisabled)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(CheckTheme.fieldFill)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(CheckTheme.border, lineWidth: 1)
                    )
                    // 여기엔 focusEffectDisabled 를 걸지 않는다 — 입력칸은 커서가 어디 있는지 보여야 쓴다.
                    // 이 칸이 선 창을 조합 확정 문에 알려 준다(`save()` 첫 줄이 이 창의 조합을 확정한다).
                    .background(FeedbackReplyWindowAnchor(slot: .settingsDisplayName).frame(width: 0, height: 0))
                    .onSubmit(save)
                    .accessibilityLabel("별명")
                saveButton
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(notice)
                    .font(.caption2)
                    // 쿨타임/도움말까지 빨갛게 칠하지 않는다 — 스토어가 "실패 사유인가"를 따로 들고 있다.
                    .foregroundStyle(isNoticeError ? CheckTheme.danger : CheckTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 6)
                // 서버는 코드포인트로 센다(char_length). 그래핌으로 세면 클라가 통과시킨 이름을 서버가 거절한다.
                Text("\(normalizedDraft.unicodeScalars.count)/\(WorkTimerStore.displayNameMaxLength)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(isOverLength ? CheckTheme.danger : CheckTheme.secondaryText)
                    .fixedSize()
            }
        }
        .onAppear {
            draft = store.displayName
            // 잠금은 '주 단위' 경계라 티커에 붙이지 않는다 — 창을 여는 이 순간에만 재평가한다(스토어 규약).
            store.refreshDisplayNameLock()
        }
        .onChange(of: store.displayName) { old, new in
            // 서버가 정규화해 돌려준 값(또는 다른 맥에서 바꾼 값)으로 되맞춘다. 사용자가 이미 고쳐 쓰고
            // 있는 중이면 건드리지 않는다 — 타이핑 중인 글자를 빼앗지 않기 위한 가드다.
            if normalizedDraft == WorkTimerStore.normalizedDisplayName(old) { draft = new }
        }
    }

    @ViewBuilder
    private var saveButton: some View {
        Button(action: save) {
            Text("저장")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(height: 28)
                .background {
                    // 저장 가능할 때만 스위치와 같은 그라디언트로 물든다 — 창 안에서 색이 곧 '가능'의 신호다.
                    if canSave {
                        Capsule().fill(CheckTheme.gaugeGradient)
                    } else {
                        Capsule().fill(CheckTheme.trackFill)
                            .overlay(Capsule().strokeBorder(CheckTheme.border, lineWidth: 1))
                    }
                }
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .disabled(!canSave)
        .opacity(canSave ? 1 : 0.55)
        .checkTooltip(store.isDisplayNameLocked ? "일주일에 한 번만 바꿀 수 있어요" : "별명 저장")
    }

    private var normalizedDraft: String {
        WorkTimerStore.normalizedDisplayName(draft)
    }

    private var isOverLength: Bool {
        normalizedDraft.unicodeScalars.count > WorkTimerStore.displayNameMaxLength
    }

    private var isFieldDisabled: Bool {
        store.isDisplayNameLocked || store.isUpdatingDisplayName
    }

    /// 저장 왕복 중에도 잠근다 — 연타로 두 번째 요청이 나가면 쿨타임을 태운 채 실패한다(스토어 주석의 사고).
    private var canSave: Bool {
        guard !isFieldDisabled, !normalizedDraft.isEmpty, !isOverLength else { return false }
        return normalizedDraft != WorkTimerStore.normalizedDisplayName(store.displayName)
    }

    /// 다시 바꿀 수 있는 시각. 서버가 준 값을 우선하고, 없으면 마지막 변경 + 쿨타임으로 계산한다.
    private var unlockDate: Date? {
        store.displayNameAvailableAt
            ?? store.displayNameChangedAt.map { WorkTimerStore.displayNameUnlockDate(changedAt: $0) }
    }

    /// 안내 한 줄 우선순위: 스토어가 세운 사유(중복/길이/쿨타임) > 잠금 안내 > 기본 도움말.
    private var notice: String {
        if let stored = store.displayNameNotice { return stored }
        if store.isDisplayNameLocked, let unlockDate {
            return WorkTimerStore.displayNameCooldownMessage(availableAt: unlockDate)
        }
        return "\(WorkTimerStore.displayNameMaxLength)자까지 · 다른 사람과 겹칠 수 없어요"
    }

    private var isNoticeError: Bool {
        if store.displayNameNotice != nil { return store.isDisplayNameNoticeError }
        return isOverLength
    }

    private func save() {
        // ★ **조합을 먼저 확정한다**(`FeedbackReplySend` — 제보 답장 칸과 같은 문). 별명은 한글이라 마지막 음절이
        //   조합 중인 채로 [저장]·Enter 가 오면 그 음절이 `draft` 에 아직 없다(사용자 신고 2026-09-14: "닉네임
        //   변경할때 … 마지막 글자 입력 반영 안되는 버그"). 확정은 동기라 바로 아래 `canSave`·`draft` 가 화면에
        //   보이던 이름 전체를 읽는다. 두 줄의 순서를 바꾸지 마라.
        FeedbackReplySend.commitActiveComposition(slot: .settingsDisplayName)
        guard canSave else { return }
        Task { @MainActor in
            // 최종 판정자는 서버다. 성공하면 서버가 실제로 저장한 값으로 입력칸을 되맞춘다
            // (클라 정규화와 한 글자라도 다르면 다음 폴링에서 이름이 눈앞에서 바뀌는 깜빡임이 된다).
            if await store.updateDisplayName(draft) {
                draft = store.displayName
            }
        }
    }
}

// MARK: - 프로필 사진 삭제 행 (v0.3.36)

/// 사진 삭제 자리의 문구 한 벌. **순수 값이라 테스트가 글자 그대로 되묻는다** — 스토어가 세우는 두 문구
/// (성공·실패)도 여기서 가져간다. 문구가 뷰와 스토어 두 곳에 흩어지면 한쪽만 고쳐도 아무 테스트가 안 빨개진다.
enum AvatarRemovalText {
    static let title = "프로필 사진"
    /// 평소 설명. **"사진이 있으면"이라고 말하지 않는다** — 이 행은 사진 유무와 무관하게 늘 같은 자리에 있다.
    static let detail = "지우면 내 자리에 착용한 캐릭터가 대신 보여요."
    /// 확인 단계의 설명. 되돌릴 수 없다는 사실만 말한다(겁주는 문장이 아니라 사실 한 줄).
    static let confirmDetail = "지운 사진은 되돌릴 수 없어요. 다시 쓰려면 새로 올려야 해요."
    static let action = "기본 캐릭터로 되돌리기"
    static let confirm = "되돌리기"
    static let cancel = "취소"
    static let inFlight = "지우는 중…"
    static let successMessage = "기본 캐릭터로 되돌렸어요"
    static let failureMessage = "사진을 지우지 못했어요"
}

/// 프로필 사진을 지워 기본(착용 캐릭터)으로 되돌리는 행.
///
/// **왜 여기인가**(팝오버의 내 아바타 hover 가 아니라): 사진을 올리는 자리는 팀 목록의 내 행이지만, 그 행은
/// **팀에 속한 사람에게만** 있다. 무소속 사용자도 사진을 올릴 수 있고(설정·가입 경로) 그러면 지울 자리가 없어진다.
/// 설정 창은 누구에게나 같은 자리에 있다.
///
/// **왜 alert/sheet/Menu 가 아닌가**: 이 앱의 맥 화면에는 그 관례가 없다(오목 기권·차단 해제 전부 같은 줄에서
/// 확인한다). 그래서 `BlockedPersonRow` 의 2단 확인을 그대로 따른다 — 평소 [기본 캐릭터로 되돌리기] →
/// 누르면 같은 줄이 [취소]+[되돌리기] 로 바뀌고 설명이 확인 문구로 갈린다. 창 높이는 두 상태에서 같다.
///
/// **사진 유무를 묻지 않는다**: 행은 늘 보이고 늘 눌린다. 사진이 없으면 스토리지가 404 를 내고 코어가 그걸 삼킨
/// 뒤 표를 null 로 덮는다(`SupabaseWorkService.removeAvatar`) — "없는 걸 지웠다"도 성공이다. 유무로 잠그면
/// 서버 사진과 화면 사진이 어긋난 사람(캐시·폴링 지연)이 **탈출구를 잃는다**.
///
/// **높이 계약 때문에 internal 이다**(private 이 아니다): 두 상태의 높이가 같은지 테스트가 직접 그려서 재야 한다.
/// 확인 단계가 한 줄 더 자라면 설정 창 맨 아래 행이 누르는 순간 잘리는데, 그건 전체 렌더로는 안 잡힌다
/// (`confirming` 이 뷰 로컬이라 전체 렌더는 언제나 평소 상태다).
struct AvatarRemovalSettingsRow: View {
    let store: WorkTimerStore
    /// 테스트가 확인 단계를 그리게 하는 씨앗. 앱 경로는 기본값(false)만 쓴다.
    /// **`onAppear` 로 @State 를 밀지 않는다** — ImageRenderer 는 onAppear 를 부르지 않아서 그 방식은
    /// 렌더 테스트에서 조용히 평소 상태를 그린다(= 확인 단계를 한 번도 안 재고 초록).
    var confirmingSeed = false

    @State private var pressed = false

    /// 확인 단계인가. 씨앗이 켜져 있으면 눌린 적 없어도 확인 단계다(위 주석).
    private var confirming: Bool { confirmingSeed || pressed }

    var body: some View {
        let isRemoving = store.isRemovingAvatar
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(AvatarRemovalText.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CheckTheme.primaryText)
                Text(confirming ? AvatarRemovalText.confirmDetail : AvatarRemovalText.detail)
                    .font(.caption2)
                    .foregroundStyle(confirming ? CheckTheme.pending : CheckTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if confirming {
                FeedbackSegmentChip(label: AvatarRemovalText.cancel, tint: CheckTheme.accent, isSelected: false) {
                    pressed = false
                }
                FeedbackPrimaryButton(
                    label: AvatarRemovalText.confirm,
                    enabled: !isRemoving,
                    // 되돌릴 수 없는 동작이라 danger 로 칠한다(차단 확인과 같은 규약).
                    tint: CheckTheme.danger
                ) {
                    pressed = false
                    store.removeAvatar()
                }
            } else {
                FeedbackPrimaryButton(
                    label: isRemoving ? AvatarRemovalText.inFlight : AvatarRemovalText.action,
                    enabled: !isRemoving
                ) {
                    pressed = true
                }
                .checkTooltip(AvatarRemovalText.detail)
            }
        }
    }
}

// MARK: - 근무 시작·종료 단축키 기록 행 (v0.3.23)

/// 기록 행 아래 **상태 한 줄**. 순수 값이라 테스트가 상태마다 문구를 글자 그대로 되묻는다.
/// 할 말이 없는 상태(등록됨·꺼짐)에는 줄 자체가 없다 — 창 높이 계약은 줄이 있는 가장 높은 상태로 잰다
/// (`CheckSettingsWindowController.defaultContentSize` 주석).
enum WorkShortcutRecorderNotice: Equatable {
    case recording
    /// 기록 중 거절: ⌃⌥⌘ 중 두 개 이상이 아니다.
    case rejected
    /// 기록 중 거절: 모양은 되지만 켜진 macOS 단축키와 겹친다.
    case rejectedSystem
    /// 저장된 조합이 켜진 macOS 단축키와 겹쳐 걸지 않았다(`WorkShortcutStatus.conflict`). 다른 **앱**과의 겹침은
    /// 감지할 수 없어서 이 문구가 그것을 약속하지 않는다.
    case conflict
    case failed

    enum Tone: Equatable {
        /// 안내(회색).
        case hint
        /// 다시 해 보라(주황) — 실패가 아니라 고른 조합을 못 받는 것이라 빨강으로 겁주지 않는다.
        case retry
        /// 등록이 안 됐다(빨강). 누르면 근무가 안 바뀐다는 뜻이라 눈에 띄어야 한다.
        case danger
    }

    static func of(
        isRecording: Bool,
        lastRejection: WorkShortcutRecorder.Rejection?,
        isEnabled: Bool,
        status: WorkShortcutStatus
    ) -> WorkShortcutRecorderNotice? {
        if isRecording {
            switch lastRejection {
            case nil: return .recording
            case .shape: return .rejected
            case .system: return .rejectedSystem
            }
        }
        // 스위치를 끈 사람에게 옛 겹침을 계속 빨갛게 보이면 "꺼도 뭔가 고장"으로 읽힌다.
        guard isEnabled else { return nil }
        switch status {
        case .conflict: return .conflict
        case .failed: return .failed
        case .active, .off, .paused: return nil
        }
    }

    var text: String {
        switch self {
        case .recording: return "⌃ ⌥ ⌘ 중 두 개 이상과 함께 눌러요 · esc 취소"
        case .rejected: return "⌃ ⌥ ⌘ 중 두 개 이상을 함께 눌러 주세요"
        case .rejectedSystem: return "macOS 단축키와 겹쳐요. 다른 조합을 눌러 주세요"
        case .conflict: return "macOS 단축키와 겹쳐요. 다른 키로 바꿔 주세요."
        case .failed: return "단축키를 등록하지 못했어요."
        }
    }

    var tone: Tone {
        switch self {
        case .recording: return .hint
        case .rejected, .rejectedSystem: return .retry
        case .conflict, .failed: return .danger
        }
    }
}

/// 키캡 그림. 값만 받는 순수 뷰로 떼어 둔 이유는 스위치(`CheckSwitchTrack`)와 같다 — 눌림 상태는 ButtonStyle 안에서만
/// 알 수 있어서, 그림을 그 안에 묻으면 '눌린 키캡'을 렌더로 그려 볼 방법이 사라진다.
struct WorkShortcutKeycapFace: View {
    let isRecording: Bool
    var isPressed: Bool = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        shape
            .fill(
                LinearGradient(
                    colors: [Color.white.opacity(isPressed ? 0.07 : 0.13), Color.white.opacity(0.05)],
                    startPoint: .top, endPoint: .bottom
                )
            )
            // 기록 중 테두리·후광은 켜짐 스위치의 도착점 색(accent)과 같은 문법 — "지금 이 칸이 듣고 있다".
            .overlay(shape.strokeBorder(isRecording ? CheckTheme.accent : CheckTheme.border, lineWidth: isRecording ? 1.5 : 1))
            // 키캡의 아랫면. 눌리면 사라져 손끝에 '들어갔다'가 붙는다.
            .shadow(color: .black.opacity(isPressed ? 0 : 0.40), radius: 0, x: 0, y: 1.5)
            .shadow(color: CheckTheme.accent.opacity(isRecording ? 0.34 : 0), radius: 6)
    }
}

private struct WorkShortcutKeycapButtonStyle: ButtonStyle {
    let isRecording: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background { WorkShortcutKeycapFace(isRecording: isRecording, isPressed: configuration.isPressed) }
            .contentShape(Rectangle())
    }
}

/// 단축키 기록 행: `[키캡: 지금 조합] [기본값으로]` + 상태 한 줄. 설정 창의 '근무 시작·종료 단축키' 스위치 바로 아래에 붙는다.
///
/// ★ **TextField·Picker·Menu 를 쓰지 않는다.** 이 저장소의 렌더 검증(ImageRenderer)은 그 셋을 노란 상자(255,204,0)로
///   그려, 그 자리는 픽셀 커버리지가 0이 된다 — 키캡이 잘리거나 겹쳐도 스냅샷이 영영 못 본다. 버튼 + 도형 + Text 만 쓴다.
///   입력도 TextField 로 받지 않는다: 조합 키는 글자가 아니고, 한글 입력 상태에서는 TextField 가 조합 중 글자를 삼킨다.
///   받는 쪽은 로컬 키 모니터다(`WorkShortcutRecordingSession`).
///
/// ★ 기록을 끝내는 문이 **전부** 있어야 한다. 기록 중에는 전역 등록이 내려가 있어서 하나라도 빠지면 전역 단축키가
///   앱을 다시 켤 때까지 멈춘다: 수락·esc(세션) · 키캡 다시 누름(여기) · 15초 시간 초과 · 앱 비활성(세션) ·
///   스위치 끄기·사라짐(여기) · 설정 창 닫기(`CheckSettingsWindowController.close()`·`windowWillClose`).
struct WorkShortcutRecorderRow: View {
    let store: WorkTimerStore
    let session: WorkShortcutRecordingSession

    init(store: WorkTimerStore, session: WorkShortcutRecordingSession = .shared) {
        self.store = store
        self.session = session
    }

    private var isRecording: Bool { store.isRecordingWorkShortcut }
    private var isEnabled: Bool { store.workShortcutEnabled }

    private var notice: WorkShortcutRecorderNotice? {
        WorkShortcutRecorderNotice.of(
            isRecording: isRecording,
            lastRejection: session.lastRejection,
            isEnabled: isEnabled,
            status: store.workShortcutStatus
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                keycap
                if store.workShortcut != .default {
                    resetButton
                }
                Spacer(minLength: 0)
            }
            if let notice {
                Text(notice.text)
                    .font(.caption2)
                    .foregroundStyle(color(for: notice.tone))
                    // 좁혀도 말줄임 대신 줄바꿈(이 창의 설명 줄 규약).
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        // 기록이 뷰 밖의 문(창 닫기·시간 초과)으로 끝났으면 모니터도 걷는다(세션의 end 는 멱등).
        .onChange(of: store.isRecordingWorkShortcut) { _, recording in
            if !recording { session.end() }
        }
        // 기록 중에 스위치를 끄면 키캡이 비활성이 되어 '다시 눌러 끝내기'가 막힌다 — 그 순간 여기서 끝낸다.
        .onChange(of: store.workShortcutEnabled) { _, enabled in
            if !enabled { session.end() }
        }
        .onDisappear { session.end() }
        // 행이 처음 나타날 때 전역 등록을 다시 판정한다. 겹침(.conflict)은 등록 결과가 아니라 그 순간의 시스템 목록으로만 알 수
        // 있어서, 시스템 설정에서 겹치는 단축키를 끄고 온 사람에게는 누가 다시 물어야 풀린다. 창을 닫았다 다시 열 때는 이 뷰가
        // 창에 붙은 채라 onAppear 가 다시 오지 않으므로 그 문은 `CheckSettingsWindowController.show()` 가 맡는다(두 곳에서 부르는 이유).
        .onAppear { store.requestWorkShortcutReapply() }
    }

    private var keycap: some View {
        Button {
            if isRecording {
                session.end()
            } else {
                session.begin(store: store)
            }
        } label: {
            Text(isRecording ? "새 조합을 누르세요" : store.workShortcut.displayString)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isRecording ? CheckTheme.accent : CheckTheme.primaryText)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 12)
                .frame(minWidth: 92)
                .frame(height: 28)
        }
        .buttonStyle(WorkShortcutKeycapButtonStyle(isRecording: isRecording))
        // 창이 열릴 때 첫 포커스 링이 키캡 위에 사각으로 겹치는 것을 막는다(이 창의 기존 규약 — 스위치 주석).
        .focusEffectDisabled()
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        // 기호(⌃⌥⌘)는 VoiceOver 가 제대로 못 읽는다 — 낭독용 문장을 준다.
        .accessibilityLabel(isRecording ? "새 조합을 누르세요" : store.workShortcut.spokenDescription)
        .accessibilityHint(isRecording ? "esc 로 취소해요" : "눌러서 새 조합을 기록해요")
    }

    private var resetButton: some View {
        Button {
            // 기록 중에 누르면 기록부터 끝낸다 — 안 그러면 기본값이 저장된 뒤에도 전역 등록이 내려가 있다.
            session.end()
            store.resetWorkShortcut()
        } label: {
            Text("기본값으로")
                .font(.caption.weight(.semibold))
                .foregroundStyle(CheckTheme.primaryText)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 12)
                .frame(height: 26)
                .background {
                    // 캐릭터 칩의 '안 고른' 모양과 같은 문법(trackFill + border).
                    Capsule().fill(CheckTheme.trackFill)
                        .overlay(Capsule().strokeBorder(CheckTheme.border, lineWidth: 1))
                }
        }
        .buttonStyle(.plain)
        .focusEffectDisabled()
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .checkTooltip("\(WorkShortcut.default.displayString) 로 되돌려요")
        .accessibilityLabel("기본값으로 되돌리기")
        .accessibilityValue(WorkShortcut.default.spokenDescription)
    }

    private func color(for tone: WorkShortcutRecorderNotice.Tone) -> Color {
        switch tone {
        case .hint: return CheckTheme.secondaryText
        case .retry: return CheckTheme.pending
        case .danger: return CheckTheme.danger
        }
    }
}

// MARK: - 소속 센터 행 (v0.3.13) — 읽기 전용

/// 설정 창 '내 정보' 의 소속 센터 행이 그릴 세 가지 상태. **순수 값이라 테스트가 직접 되묻는다.**
///
/// ★ 이 타입의 존재 이유는 `loading` 과 `unset` 을 **가르는 것 하나다.** 둘 다 `myCenter == nil` 이지만
///   뜻이 정반대다: 전자는 "서버가 아직 말 안 했다", 후자는 "서버가 없다고 말했다". 플래그 없이 nil 을
///   '미지정'으로 읽으면 로그인 직후 창이 미지정으로 한 번 그려졌다가 GET 이 도착하며 값으로 바뀐다 —
///   사용자 눈에는 깜빡임이다.
///
/// ★ **여기엔 바꾸는 길이 없다**(사장님 지시 2026-09-12). 센터는 가입 때 한 번 고르고 그 뒤로는 본인이
///   못 바꾼다. 강제 수단은 서버 쪽이다 — `profiles.center` 에 `grant update` 를 주지 않았으므로 이 계정의
///   PATCH 는 거절된다. 그래서 피커를 여기 남겨 두는 것이 '있어도 그만'이 아니라 **최악**이다: 낙관 반영이
///   화면만 바꿨다가 실패 원복이 조용히 되돌리고, 사용자는 자기가 바꿨다고 믿은 채 아무 안내도 못 받는다.
///   잘못 고른 사람은 운영자가 SQL 로 고친다. 되살리려면 SPEC 의 'DB' 절부터 다시 읽어라 — 서버 권한이 먼저다.
enum CenterSettingsRowState: Equatable {
    /// 서버값을 아직 못 받았다.
    case loading
    /// 서버가 '미지정'이라고 말해 줬다(가입 때 안 고른 계정).
    case unset
    /// 화면 글자("서울"/"부산"). 모르는 서버값은 여기 도달하지 못한다 — CenterLabel 이 걸러 unset 으로 접는다.
    case chosen(String)

    static func of(loaded: Bool, center: String?) -> CenterSettingsRowState {
        guard loaded else { return .loading }
        guard let display = CenterLabel.display(center) else { return .unset }
        return .chosen(display)
    }

    /// 행 우측에 그릴 **값 한 마디**. 이 행이 전하는 사실의 본체다.
    var value: String {
        switch self {
        case .loading:          return "…"
        case .unset:            return "미지정"
        case .chosen(let name): return name
        }
    }

    /// 값 아래 한 줄. 상태마다 **다른 문장**이어야 한다 — 셋이 같은 글자면 이 행은 아무것도 말하지 않는다.
    /// 배지 자리를 '이름 옆'이라고 적지 마라: 확정된 자리는 **아바타 모서리**다(SPEC 확정 1 · CheckAvatarView).
    var caption: String {
        switch self {
        case .loading: return "불러오는 중…"
        case .unset:   return "가입할 때 안 골랐어요. 운영자에게 말해 주세요."
        case .chosen:  return "아바타 모서리에 배지로 보여요. 바꾸려면 운영자에게."
        }
    }
}

/// 소속 센터 행. **읽기 전용이다** — 피커도 버튼도 PATCH 도 없다(위 열거형 주석에 근거).
/// 토글 행과 같은 좌우 구조(제목·설명 열 + 우측 값)라 '내 정보' 카드 안에서 층이 맞는다.
private struct CenterSettingsRow: View {
    let store: WorkTimerStore

    private var state: CenterSettingsRowState {
        CenterSettingsRowState.of(loaded: store.myCenterLoaded, center: store.myCenter)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("소속 센터")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CheckTheme.primaryText)
                Text(state.caption)
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                    // 창을 좁혀도 말줄임 대신 줄바꿈한다(토글 행과 같은 규약).
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            // 값은 절대 줄이지 않는다 — 좁힐 때 접혀야 하는 것은 설명이고 이 두 글자가 아니다.
            Text(state.value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CheckTheme.primaryText)
                .lineLimit(1)
                .fixedSize()
                .accessibilityLabel("소속 센터 \(state.value)")
        }
        // 창을 열 때 아직 모르면 여기서 묻는다. 로그인 직후 설정 로드가 blip 으로 실패하면 그 함수는
        // 래치에 걸려 다시 안 돌아 이 행이 그 세션 내내 '불러오는 중'에 멈춘다 — 여기가 그 복구 경로다.
        // 이미 알고 있으면 스토어가 즉시 반환하므로 여닫아도 왕복은 늘지 않는다.
        .task { await store.loadMyCenterIfNeeded() }
    }
}

// MARK: - 착용 캐릭터 (v0.3.15) — 관리자 전용

/// 착용 캐릭터가 **바뀌었다**는 사실 하나만 들고 있는 관찰 대상.
///
/// 선택값의 주인은 여전히 `CharacterSelection`(UserDefaults)이다. 이 타입이 그 위에 얹는 것은 **화면 갱신**
/// 하나뿐이다. 이유가 있다: 메뉴바 아이콘(`CheckMenuView` 의 `MenuBarStatusLabel`)은 그림을 정적 함수
/// (`CheckMascotAssets.menuBarImage(for:)`)에서 얻는다. 저장값이 바뀌어도 SwiftUI 입장에서는 **아무 일도
/// 일어나지 않았다** — 의존성으로 등록된 값이 하나도 안 바뀌었으니 body 를 다시 부를 이유가 없다.
/// 캐시는 캐릭터 id 로 갈라 놨으니 옛 이미지가 끼지는 않지만(2-C), body 가 다시 안 불리면 화면은 그대로다.
///
/// 그래서 선택기는 저장에 성공한 직후 여기에 한 번 알리고, **그림을 그리는 body 가 `revision` 을 읽으면**
/// 그 body 만 다시 평가된다. 읽지 않는 body 는 아무 영향도 받지 않는다(관찰은 읽은 쪽에만 걸린다) —
/// 그래서 이 타입을 더해도 지금 화면들의 재평가 횟수는 1도 늘지 않는다.
///
/// ⚠️ **아직 아무도 읽지 않는다.** 메뉴바 아이콘을 되그리려면 `MenuBarStatusLabel.body` 가
/// `CharacterSelectionBroadcast.shared.revision` 을 한 번 읽어야 하는데 그 파일은 이 갈래의 소유가 아니다
/// (배선 한 줄은 오케스트레이터 몫). 여기까지가 이 갈래가 할 수 있는 전부다.
@MainActor
@Observable
final class CharacterSelectionBroadcast {
    /// 앱이 쓰는 하나. **테스트는 자기 인스턴스를 만들어라** — 전역을 흔들면 같은 순간 아잉 픽셀을 재는
    /// 병렬 스위트가 간헐적으로 빨개진다(`CheckMascotAssets.characterIDOverride` 가 TaskLocal 인 것과 같은 이유).
    static let shared = CharacterSelectionBroadcast()

    /// 마지막으로 **저장에 성공한** 캐릭터 id. 저장이 거절되면(모르는 id) 바뀌지 않는다.
    private(set) var selectedID: String

    /// 바뀐 횟수. 되그릴 쪽은 id 가 아니라 **이 값**을 읽어라 — 같은 캐릭터를 다시 고르거나 에셋만 갈린
    /// 경우에도 화면은 다시 그려야 하는데, id 비교로는 그 두 경우가 "안 바뀜"으로 접힌다.
    private(set) var revision = 0

    init(selectedID: String = CharacterCatalog.builtInAingID) {
        self.selectedID = selectedID
    }

    /// 저장이 끝난 뒤에만 부른다.
    func announce(_ id: String) {
        selectedID = id
        revision += 1
    }
}

/// 캐릭터 고르기의 **행동 한 줄**. 뷰 버튼 안에 인라인으로 쓰지 않고 값으로 떼어 둔 이유는,
/// 이걸 부르지 않는 회귀(= 눌러도 아무것도 저장되지 않는 먹통 선택기)를 테스트가 **직접** 물을 수 있게 하기
/// 위해서다. 뷰 클로저 안에 묻으면 픽셀로만 보이고, 픽셀은 "눌린 뒤"를 못 본다.
@MainActor
enum CheckCharacterPicker {
    /// 고른 캐릭터를 저장하고 화면에 알린다. 카탈로그에 없는 id 면 **아무것도 하지 않고** false
    /// (`CharacterSelection.select` 의 규약을 그대로 따른다 — 옛 저장값을 모르는 값으로 덮지 않는다).
    @discardableResult
    static func choose(
        _ id: String,
        selection: CharacterSelection,
        broadcast: CharacterSelectionBroadcast = .shared
    ) -> Bool {
        guard selection.select(id) else { return false }
        broadcast.announce(id)
        return true
    }
}

/// 착용 캐릭터 선택 행. **관리자에게만 보인다** — 호출부(`CheckSettingsView`)가 `store.ultraUnlimited` 로 가린다.
///
/// ★ 왜 `Picker`/`Menu` 가 아니라 버튼 줄인가. 이 저장소의 렌더 검증은 `ImageRenderer` 로 잘림·겹침을
///   픽셀로 보는데, `Menu`·`TextField` 는 그 렌더러에서 **노란 상자**로 그려진다(실측 — 그 자리는 픽셀
///   커버리지가 0이라 색 결함이 8일간 안 잡혔다). 피커로 만들면 이 행은 스냅샷에서 보이지 않는 것과 같다.
///   칩(캡슐) 버튼 줄은 순수 도형+Text 라 그대로 찍힌다. 모양은 별명 행의 [저장] 버튼과 같은 문법이다
///   (고른 것 = gaugeGradient, 나머지 = trackFill + border).
///
/// ★ 로컬 저장이 이기면 `onChosen` 으로 **서버에도 민다**(definer RPC `set_character`).
///   `ultraUnlimited` 는 표시 깃발이지 권한이 아니다 — 무엇이 보이는지는 정해도 무엇이 바뀌는지는 서버가 정한다.
struct CheckCharacterSettingsRow: View {
    let catalog: CharacterCatalog
    let selection: CharacterSelection
    /// 되그릴 쪽에 알리는 통로. 테스트가 자기 인스턴스를 넣어 전역을 안 건드린다.
    var broadcast: CharacterSelectionBroadcast = .shared
    /// 저장이 이긴 뒤 한 번. 서버에 밀어 넣는 자리다(`CheckCharacterPanel.onChosen` 과 같은 규약).
    var onChosen: (String) -> Void = { _ in }

    /// 눌린 칩을 즉시 옮기기 위한 로컬 거울. 진짜 값은 `selection` 에 있다 —
    /// 저장이 **거절되면 여기도 안 움직인다**(화면만 바뀌었다가 조용히 되돌아가는 거짓말을 만들지 않는다).
    @State private var selectedID: String

    init(
        catalog: CharacterCatalog,
        selection: CharacterSelection,
        broadcast: CharacterSelectionBroadcast = .shared,
        onChosen: @escaping (String) -> Void = { _ in }
    ) {
        self.catalog = catalog
        self.selection = selection
        self.broadcast = broadcast
        self.onChosen = onChosen
        _selectedID = State(initialValue: selection.selectedID)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text("캐릭터")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CheckTheme.primaryText)
                Text("오버레이와 메뉴바에 나오는 내 캐릭터예요.")
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                    // 좁혀도 말줄임 대신 줄바꿈(이 창의 설명 줄 규약).
                    .fixedSize(horizontal: false, vertical: true)
            }
            // 목록 순서의 주인은 카탈로그다(`allIDs` 가 **아잉 먼저**, 나머지는 id 정렬).
            // 여기서 다시 정렬하면 폴백 대상이 첫 칸이라는 사실이 두 곳에 적히고, 갈리는 날 조용히 어긋난다.
            HStack(spacing: 6) {
                ForEach(catalog.allIDs, id: \.self) { id in
                    chip(id)
                }
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private func chip(_ id: String) -> some View {
        let isOn = id == selectedID
        Button {
            // 저장이 이긴 경우에만 칩을 옮긴다.
            if CheckCharacterPicker.choose(id, selection: selection, broadcast: broadcast) {
                selectedID = id
                onChosen(id)
            }
        } label: {
            Text(catalog.manifest(id: id)?.displayName ?? id)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isOn ? Color.white : CheckTheme.primaryText)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(height: 26)
                .background {
                    if isOn {
                        Capsule().fill(CheckTheme.gaugeGradient)
                    } else {
                        Capsule().fill(CheckTheme.trackFill)
                            .overlay(Capsule().strokeBorder(CheckTheme.border, lineWidth: 1))
                    }
                }
        }
        .buttonStyle(.plain)
        // 창이 열릴 때 첫 포커스 링이 캡슐 위에 사각으로 겹치는 것을 막는다(이 창의 기존 규약).
        .focusEffectDisabled()
        .accessibilityLabel(catalog.manifest(id: id)?.displayName ?? id)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Settings window body

/// 설정 창 본문. **"한 번 정하고 잊는" 것만** 담는다.
///
/// 배경: 설정이 팝오버 본문·토큰 순위판·할 일 보드 창·전원 버튼 롱프레스 메뉴 네 군데로 흩어져,
/// 만든 사람조차 못 찾는 항목이 생겼다(실사용 신고). 여기 모으는 기준은 **빈도**다 —
/// 집중 모드처럼 하루에도 몇 번 켜고 끄는 것, 보드 배경 진하기처럼 대상을 보면서 조절해야 하는 것은
/// 일부러 뺐다. 그건 쓰던 자리에 있어야 쓸 수 있다.
struct CheckSettingsView: View {
    let store: WorkTimerStore

    /// 렌더 스냅샷 전용 시드. nil 이면 화면에 뜰 때 실제 로그인 항목 상태를 읽는다(앱 경로).
    /// 값을 주면 SMAppService 를 **한 번도** 건드리지 않는다 — ImageRenderer 검증이 시스템 상태에
    /// 의존하지 않게 하는 유일한 방법이다(onAppear 는 렌더러에서 도는 보장이 없다).
    private let launchAtLoginSeed: Bool?

    /// 캐릭터 선택을 읽고 쓰는 도메인. 기본값 `.standard` 라 앱 전체(오버레이·메뉴바·미니게임)가 같은
    /// 선택을 보고, 테스트는 자기 suite 를 넣어 **표준 도메인을 오염시키지 않는다** — 병렬로 도는 다른
    /// 스위트가 아잉 픽셀을 재고 있어서, 여기서 표준에 쓰면 그쪽이 간헐적으로 빨개진다.
    private let characterDefaults: UserDefaults

    @State private var launchAtLogin: Bool

    init(
        store: WorkTimerStore,
        launchAtLoginSeed: Bool? = nil,
        characterDefaults: UserDefaults = .standard
    ) {
        self.store = store
        self.launchAtLoginSeed = launchAtLoginSeed
        self.characterDefaults = characterDefaults
        _launchAtLogin = State(initialValue: launchAtLoginSeed ?? false)
    }

    /// 창을 붙일 쪽(창 배선 담당)이 참고할 기본 폭. 설명 한 줄이 두 줄로 접히지 않는 최소치 근처다.
    static let preferredWidth: CGFloat = 380

    /// **관리자 화면**(캐릭터 선택기가 붙은 상태)의 실측 콘텐츠 높이(pt, preferredWidth 에서) — **가장 높은 상태**로 잰다.
    ///
    /// 일반 사용자 화면은 단축키 등록이 정상일 때 624pt, 단축키 안내 한 줄(macOS 단축키 겹침 · 등록 실패 · 기록 중 · 기록 거절)이 보이면 643pt 다
    /// (v0.3.23 '근무 시작·종료 단축키' 묶음 포함) — 선택기는 `store.ultraUnlimited` 뒤에 있어 한 픽셀도 안 쓴다.
    /// 관리자에게만 캐릭터 행(칩 한 줄 + 설명 한 줄 + 구분선)이 붙어 **89pt** 가 더 붙는다: 713 / 732(실측 2026-09-15).
    ///
    /// 왜 713 이 아니라 732 인가: 설정 창은 관리자에게 열 때 창을 **이 값까지** 키운다(`growForAdminContentIfNeeded`).
    /// 안내 한 줄이 없는 쪽으로 잡으면 겹침·실패 안내가 뜨는 순간 맨 아래 캐릭터 칩 줄이 19pt 잘린다.
    ///
    /// ⚠️ **창 높이 계약(`CheckSettingsWindowController.defaultContentSize.height`)보다 크다.** 그래서 창 쪽이
    ///    관리자일 때만 열면서 이 값까지 키운다. `V0316CharacterPickerTests` 가 가장 높은 상태를 그려 이 숫자를 되묻는다.
    ///
    /// v0.3.34: '내 정보'에 [차단한 사람] 행이 붙어 일반 698 / 관리자 787(둘 다 +55, 실측 2026-09-20). 창 계약은 703 이었다.
    ///
    /// v0.3.36: '내 정보'에 [프로필 사진] 행(기본 캐릭터로 되돌리기)이 붙어 일반 753 / 관리자 **842**(둘 다 +55, 실측 2026-09-21
    /// 폭 380). 창 계약은 758 이다. 이 행의 2단 확인은 **높이를 안 바꾼다** — 확인 단계에서도 제목 한 줄 + 설명 한 줄이라
    /// 같은 높이다(`V0336AvatarRemovalTests.되돌리기_행은_확인_단계에서도_같은_높이다` 가 두 상태를 직접 그려 잰다).
    /// 확인 단계는 뷰 로컬 상태라 이 전체 렌더로는 절대 안 그려지므로, 그 테스트가 없으면 "누르는 순간 잘리는 창"이
    /// 여기서는 초록으로 통과한다.
    static let adminContentHeight: CGFloat = 842

    var body: some View {
        Group {
            if store.showsBlockedPeopleInSettings {
                // 설정 → 차단한 사람(v0.3.34). 설정 본문과 **자리를 바꾼다** — 사람 수만큼 자라는 목록을 본문에 펼치면
                // 이 창의 높이 계약(맨 아래 항목이 안 잘린다)이 사람 수에 묶인다.
                CheckBlockedPeopleSettingsPage(store: store)
            } else {
                settingsSections
            }
        }
        .padding(14)
        // 창이 늘어나면 같이 늘고, 좁혀도 설명이 뭉개지지 않는 하한을 준다(창 크기는 배선 쪽 소관).
        // maxHeight 를 열어 두는 것이 핵심이다: 창(648pt)이 콘텐츠보다 높은데 프레임을 콘텐츠 높이로
        // 두면 배경이 그만큼만 칠해지고 창 아래에 시스템 흰 띠가 남는다. 진단 두 줄이 제보로 옮겨 간
        // 뒤(2026-09-10) 그 여백은 더 커졌다 — 그래서 이 한 줄은 더 중요해졌다.
        // 위 정렬(topLeading)은 이 앱의 상단 앵커 규약이기도 하다 — 늘어난 만큼 아래로만 빈다.
        // ★ 폭 하한이 곧 **높이 계약**이다(v0.3.13 에 배운 것). 예전 하한은 320 이었는데, 그 폭에서는
        //   설명 줄 여러 개가 두 줄로 접혀 콘텐츠가 폭에 따라 들쭉날쭉했다 —
        //   실측(2026-09-12, 세 상태 × 별명 안내 세 종류 전부 같은 값):
        //     320 → 517pt · 360 → 504 · 370 → 491 · 375 → 478 · **380 이상 → 465(고정)**.
        //   창 높이 계약은 470 하나인데 콘텐츠가 517 까지 자라면 맨 아래 '소속 센터' 행이 통째로 잘린다.
        //   그래서 하한을 preferredWidth 로 올렸다: 이 폭 위에서는 **어떤 폭에서도 465pt** 라, 높이가
        //   사용자의 드래그에 따라 달라지지 않는다. 하한을 다시 낮추려면 창 높이부터 다시 재라.
        //   v0.3.22: '자동 근무 시작' 행이 붙어 폭 380 에서 **533pt**, 창은 538 이었다. 이 행의 설명은 넓은 폭에서
        //   한 줄로 펴질 수 있어 폭이 커지면 콘텐츠가 같거나 작아진다 — 계약은 여전히 폭 하한에서 잰 값이다.
        //   v0.3.23: '근무 시작·종료 단축키' 묶음이 붙어 폭 380 에서 624pt, 안내 한 줄이 보이면 **643pt**, 창은 648 이다.
        .frame(
            minWidth: Self.preferredWidth, idealWidth: Self.preferredWidth, maxWidth: 520,
            maxHeight: .infinity, alignment: .topLeading
        )
        .background(CheckTheme.background)
        // 툴팁 말풍선 레이어(v0.3.25) — 설정 창 루트. 창을 채우는 프레임·배경 뒤라 말풍선 자리가 창 전체다.
        .checkTooltipLayer()
        // 사람 아바타의 캐릭터 한 표(2026-09-20) — 설정 창 루트(차단한 사람 목록의 아바타가 이 아래다).
        .appUserAvatarCharacters(from: store)
        .onAppear {
            // 시드가 있으면 시스템에 묻지 않는다(렌더/테스트 경로).
            if launchAtLoginSeed == nil {
                launchAtLogin = LoginItemRegistrar.isLaunchAtLoginEnabled()
            }
        }
    }

    /// 설정 본문 두 묶음(일반 · 내 정보). `body` 가 [차단한 사람] 쪽과 자리를 바꾼다(v0.3.34).
    private var settingsSections: some View {
        VStack(alignment: .leading, spacing: 14) {
            section("일반") {
                CheckSettingsToggleRow(
                    title: "로그인 시 자동 실행",
                    detail: "맥에 로그인하면 메뉴바에 자동으로 올라와요.",
                    isOn: launchAtLoginBinding
                )
                PanelDivider()
                // 자동 **종료** 스위치는 일부러 없다(사장님 결정 2026-09-15) — WorkTimerStore.autoWorkStartEnabled 주석.
                CheckSettingsToggleRow(
                    title: "자동 근무 시작",
                    detail: "컴퓨터를 5분쯤 쓰면 알아서 근무를 시작해요. 끄면 직접 눌러야 해요.",
                    isOn: autoWorkStartBinding
                )
                PanelDivider()
                // 근무 시작·종료 전역 단축키(v0.3.23). 스위치와 기록 행을 한 묶음(간격 8)으로 둔다 — 카드의 행 간격(12)으로
                // 떨어뜨리면 키캡이 무엇의 키인지 안 읽힌다.
                VStack(alignment: .leading, spacing: 8) {
                    CheckSettingsToggleRow(
                        title: "근무 시작·종료 단축키",
                        detail: "메뉴바를 열지 않아도 이 키로 근무를 시작하거나 끝내요.",
                        isOn: workShortcutEnabledBinding
                    )
                    WorkShortcutRecorderRow(store: store)
                }
                PanelDivider()
                CheckSettingsToggleRow(
                    title: "캐릭터를 눌러 할 일 열기",
                    detail: "켜면 캐릭터 클릭이 할 일 보드를 열고, 끄면 캐릭터가 콕 반응만 해요.",
                    isOn: todoBinding
                )
            }
            section("내 정보") {
                DisplayNameSettingsRow(store: store)
                PanelDivider()
                // 사진을 **지우는** 자리(v0.3.36). 올리는 자리는 팝오버 팀 목록의 내 행이지만 그 행은 팀에 속한
                // 사람에게만 있다 — 지우기는 무소속 사용자에게도 있어야 해서 설정에 둔다(행 주석 참고).
                AvatarRemovalSettingsRow(store: store)
                PanelDivider()
                CheckSettingsToggleRow(
                    title: "AI 토큰 사용량 공개",
                    detail: "끄면 AI 토큰 순위판에서 내 사용량이 다른 사람에게 보이지 않아요.",
                    isOn: tokenUsagePublicBinding
                )
                PanelDivider()
                CheckSettingsToggleRow(
                    title: "미니게임 순위 공개",
                    detail: "끄면 내 최고기록이 순위표에 안 보이고 올라가지도 않아요.",
                    isOn: miniGamePublicBinding
                )
                PanelDivider()
                CenterSettingsRow(store: store)
                PanelDivider()
                // 설정 → 차단한 사람(v0.3.34). 누르면 이 창의 본문 자리에 목록이 선다(`CheckBlockedPeopleSettingsPage`).
                // 차단을 **거는** 자리는 대화 화면·오목 채팅의 ··· 이고, 여기는 푸는 자리다(폰: 나 → 설정 → 차단한 사람).
                BlockedPeopleSettingsEntryRow(store: store)
                // ★ 관리자에게만 연다(SPEC 2-D). 캐릭터를 파는 **상점이 아직 없다** — 일반 사용자에게
                //   열면 "가진 적 없는 것을 고를 수 있는" 화면이 되고, 그 순간 이 창이 재화 설계보다
                //   앞서 나간다. `ultraUnlimited` 는 서버(`profiles.role = 'admin'`)가 말해 준 사실의
                //   **표시용 사본**이라 판정에는 못 쓰지만, '무엇이 보이는가'를 정하는 데는 이것이 맞다
                //   (무엇이 바뀌는가는 나중에 서버 definer RPC 가 정한다 — 지금은 로컬 선택뿐이다).
                if store.ultraUnlimited {
                    PanelDivider()
                    CheckCharacterSettingsRow(
                        catalog: CheckCharacter3DScene.catalog,
                        selection: CharacterSelection(
                            defaults: characterDefaults,
                            catalog: CheckCharacter3DScene.catalog
                        ),
                        onChosen: { _ in store.pushSelectedCharacter(announcesFailure: true) }
                    )
                }
            }
            // ★ 진단 두 줄(초인종·근무 틱)이 **여기 있었다.** 없어진 게 아니라 제보로 **옮겼다**
            //   (2026-09-10, 사용자 지적: "이건 뭐야? 왜 넣은 거야? 빼는 게 맞지 않아?").
            //   다시 만들지 마라 — 진단이 틀렸던 게 아니라 자리가 틀렸다.
            //
            //   설정은 팀원 전원이 여는 화면이고, 그들에게 `idle(disabled) · 재연결 0회` 는 읽을 수 없는
            //   암호문이다. 정작 볼 사람은 운영자인데 신고가 올 때마다 "설정 열어서 하단 두 줄 찍어
            //   보내주세요"를 부탁해야 했다. 지금은 제보를 보내면 그 두 줄이 본문 뒤에 자동으로 붙어
            //   운영자 받은함에 **이미 붙어서** 도착한다(FeedbackDiagnostics — WorkTimerStoreFeedback.swift).
            //   팀원은 "찌르기가 안 와요" 한 줄만 쓰면 되고, 화면은 깨끗해지고 진단은 오히려 잘 된다.
            //
            //   되돌리려는 사람이 알아야 할 사실: 이 창은 648pt 이고 콘텐츠는 가장 높은 상태에서 643pt 다(v0.3.23) — 이제는 자리도
            //   없으니 창 높이부터 다시 재야 한다. 그보다 먼저 없는 것은 이유다.
        }
    }

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(CheckTheme.secondaryText)
                .padding(.leading, 2)
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .panelStyle()
        }
    }

    /// applyUserToggle 이 **사용자 의도까지** 남긴다. setLaunchAtLoginEnabled 만 부르면 끈 사실이
    /// 어디에도 안 남아 다음 실행의 자동 등록이 그대로 되켠다(기본값이 켜짐이 된 뒤로 이 경로가 탈출구다).
    /// 반환값(실상태)을 그대로 대입하는 것도 규약이다 — 권한 등으로 쓰기가 실패하면 스위치가 거짓말한다.
    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin },
            set: { wanted in launchAtLogin = LoginItemRegistrar.applyUserToggle(wanted) }
        )
    }

    private var autoWorkStartBinding: Binding<Bool> {
        Binding(
            get: { store.autoWorkStartEnabled },
            set: { store.setAutoWorkStartEnabled($0) }
        )
    }

    /// 끄는 순간의 기록 종료는 기록 행이 스스로 한다(`WorkShortcutRecorderRow` 의 onChange) — 여기서 세션을 또 만지면
    /// 기록을 끝내는 집이 둘이 된다.
    private var workShortcutEnabledBinding: Binding<Bool> {
        Binding(
            get: { store.workShortcutEnabled },
            set: { store.setWorkShortcutEnabled($0) }
        )
    }

    private var todoBinding: Binding<Bool> {
        Binding(
            get: { store.isTodoEnabled },
            set: { store.setTodoEnabled($0) }
        )
    }

    private var tokenUsagePublicBinding: Binding<Bool> {
        Binding(
            get: { store.tokenUsagePublic },
            set: { store.setTokenUsagePublic($0) }
        )
    }

    private var miniGamePublicBinding: Binding<Bool> {
        Binding(
            get: { store.miniGamePublic },
            set: { store.setMiniGamePublic($0) }
        )
    }
}
