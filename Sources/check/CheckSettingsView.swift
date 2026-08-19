import SwiftUI

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
        .help(store.isDisplayNameLocked ? "일주일에 한 번만 바꿀 수 있어요" : "별명 저장")
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

    @State private var launchAtLogin: Bool

    init(store: WorkTimerStore, launchAtLoginSeed: Bool? = nil) {
        self.store = store
        self.launchAtLoginSeed = launchAtLoginSeed
        _launchAtLogin = State(initialValue: launchAtLoginSeed ?? false)
    }

    /// 창을 붙일 쪽(창 배선 담당)이 참고할 기본 폭. 설명 한 줄이 두 줄로 접히지 않는 최소치 근처다.
    static let preferredWidth: CGFloat = 380

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            section("일반") {
                CheckSettingsToggleRow(
                    title: "로그인 시 자동 실행",
                    detail: "맥에 로그인하면 메뉴바에 자동으로 올라와요.",
                    isOn: launchAtLoginBinding
                )
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
                CheckSettingsToggleRow(
                    title: "AI 토큰 사용량 공개",
                    detail: "끄면 AI 토큰 순위판에서 내 사용량이 다른 사람에게 보이지 않아요.",
                    isOn: tokenUsagePublicBinding
                )
            }
            // 진단은 **카드가 아니라 한 줄 각주**다. 설정 창은 400pt 이고 콘텐츠가 이미 355pt 라
            // 섹션 카드(제목+패딩)를 하나 더 얹으면 445pt 가 되어 맨 아래 — 즉 이 줄 자체가 잘린다.
            RealtimeDiagnosticsRow(store: store)
        }
        .padding(14)
        // 창이 늘어나면 같이 늘고, 좁혀도 설명이 뭉개지지 않는 하한을 준다(창 크기는 배선 쪽 소관).
        // maxHeight 를 열어 두는 것이 핵심이다: 창(400pt)이 콘텐츠(약 355pt)보다 높은데 프레임을
        // 콘텐츠 높이로 두면 배경이 그만큼만 칠해지고 창 아래에 시스템 흰 띠가 남는다.
        // 위 정렬(topLeading)은 이 앱의 상단 앵커 규약이기도 하다 — 늘어난 만큼 아래로만 빈다.
        .frame(
            minWidth: 320, idealWidth: Self.preferredWidth, maxWidth: 520,
            maxHeight: .infinity, alignment: .topLeading
        )
        .background(CheckTheme.background)
        .onAppear {
            // 시드가 있으면 시스템에 묻지 않는다(렌더/테스트 경로).
            if launchAtLoginSeed == nil {
                launchAtLogin = LoginItemRegistrar.isLaunchAtLoginEnabled()
            }
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
}

/// 초인종(리얼타임) 한 줄 진단. **"찌르기가 안 와요" 신고에서 소켓/따라잡기/토큰 중 어디인지를 가른다.**
///
/// 이 줄이 없으면 `.idle(.disabled)`(전송자 nil — 킬스위치 off 또는 조립 실패)가 **완전한 침묵**이 된다:
/// REST 는 멀쩡하고 syncMessage 는 "동기화됨"을 유지하므로 앱 어디에도 신호가 없다.
///
/// 표면은 Text 한 줄뿐이다 — Menu/TextField 를 쓰지 않는다(ImageRenderer 가 그 자리를 노란 상자로 그려
/// 픽셀 커버리지가 0이 되고, 그러면 이 줄이 사라져도 렌더 테스트가 초록으로 남는다).
private struct RealtimeDiagnosticsRow: View {
    let store: WorkTimerStore

    var body: some View {
        Text("초인종 " + store.realtimeDiagnosticsLine)
            .font(.system(size: 10).monospacedDigit())
            .foregroundStyle(CheckTheme.secondaryText)
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.leading, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
