import AppKit
import SwiftUI

struct CheckMenuView: View {
    @Bindable var store: WorkTimerStore
    // 업데이트 감지 스토어(주입, 옵셔널). 팝오버 열림 시 하루 1회 체크를 킥하고, 새 버전이면 최상단 배너를 띄운다.
    // nil 이면(기존 렌더 테스트 등) 체크도 배너도 없다 — 기존 스냅샷/높이는 그대로 유지된다.
    var updateCheck: UpdateCheckStore? = nil
    // 렌더 스냅샷/미리보기에서 초기 인증 모드를 주입할 수 있게 열어 둔다. 앱은 기본값(로그인)으로 진입.
    var initialAuthMode: AuthMode = .signIn
    // 렌더 스냅샷에서 비밀번호 필드의 "영어만" 안내가 떠 있는 상태를 재현하기 위한 미리보기 플래그.
    var previewASCIIWarning: Bool = false
    // 렌더 스냅샷에서 12시간 확인 배너가 떠 있는 상태를 재현하기 위한 미리보기 플래그. 앱에서는 항상 false.
    var previewLongSessionBanner: Bool = false
    // 스냅샷 전용: 초과(스크롤) 리스트를 ScrollView 대신 "보이는 첫 maxVisibleRows행 클립"으로 그린다.
    // ImageRenderer는 NSScrollView(=ScrollView) 내용을 못 그리므로, 육안 확인 스냅샷에서만 켠다. 앱은 항상 false(ScrollView).
    var previewClipsOverflowList: Bool = false
    // 스냅샷 전용: owner 팀 카드에서 참여코드 인라인 행이 펼쳐진 상태를 강제로 그린다. 앱에서는 항상 false(키 버튼 토글).
    var previewOwnerCodeRevealed: Bool = false
    // 스냅샷 전용: 헤더 주간 목표 편집 행이 펼쳐진 상태를 강제로 그린다. 앱에서는 항상 false(연필 버튼 토글).
    var previewGoalEditing: Bool = false
    // 스냅샷 전용: 새 버전 안내 배너가 떠 있는 상태를 강제로 그린다. 앱에서는 updateCheck?.isUpdateAvailable 로만 결정.
    var previewUpdateBanner: Bool = false

    // 실제 감지(updateCheck)든 미리보기 플래그든 하나라도 켜지면 최상단 배너를 노출한다.
    private var showsUpdateBanner: Bool {
        previewUpdateBanner || (updateCheck?.isUpdateAvailable ?? false)
    }

    // 배너 표시용 버전 문자열("v" 접두 정규화). 실 감지가 없으면(미리보기) 폴백 버전으로 렌더한다.
    private var updateBannerVersionText: String {
        let raw = updateCheck?.latestVersion ?? "v0.3.0"
        return (raw.hasPrefix("v") || raw.hasPrefix("V")) ? raw : "v\(raw)"
    }

    var body: some View {
        VStack(spacing: 10) {
            // 팝오버 최상단: 새 버전 안내 배너([지금 업데이트] 원클릭 + [명령 복사] 폴백). HeaderCard 위에 얹는다.
            if showsUpdateBanner {
                UpdateBanner(versionText: updateBannerVersionText)
            }
            content
        }
            .padding(12)
            // 폭만 고정(340). 높이는 상태별 콘텐츠에 맞춰 동적으로 잡는다(MenuBarExtra 창 크기 = 콘텐츠 크기).
            .frame(width: 340)
            .background(CheckTheme.background)
            .foregroundStyle(CheckTheme.primaryText)
            // 팝오버 표시/숨김을 스토어에 알려 티커/폴링 게이팅을 켠다(창 노티 콜백과 수렴 — 멱등이라 중복 무해).
            .onAppear { store.setMenuPresented(true) }
            .onDisappear { store.setMenuPresented(false) }
            .task {
                await store.activateStoredSession()
            }
            .task {
                // 토큰 사용량 갱신 루프를 팝오버 표시 동안만 돌린다(즉시 1회 + 30초 주기, 뷰 사라지면 자동 취소).
                // 첫 스캔 트리거를 여기로 일원화한다 — 토큰 스토어는 init 에서 스캔을 킥하지 않으므로(영속 스냅샷 복원만),
                // 표시 중 이 루프가 값을 채운다. 스캔 대상은 주입된 store.tokenUsage 다 — 프로덕션은 전역 .shared,
                // 렌더 테스트는 격리 인스턴스라, ImageRenderer 가 이 .task 를 돌려도 실홈 스캔이 테스트 .standard 를 오염시키지 않는다.
                await store.tokenUsage.runRefreshLoop()
            }
            .task {
                // 업데이트 감지의 유일한 네트워크 킥 지점(팝오버 열림 경로). 24h 스로틀이라 대부분 즉시 no-op 이고,
                // 하루 첫 오픈에서만 GitHub 최신 릴리스를 1회 조회한다(유휴 0% 불변 — 상시 타이머 없음). nil 이면 no-op.
                await updateCheck?.checkIfStale()
            }
    }

    @ViewBuilder
    private var content: some View {
        if store.isSignedIn {
            if store.isTeamless {
                // 로그인은 됐지만 소속 팀이 없다 — 메인 대신 팀 코드 입력/새 팀 만들기 패널을 보여 준다.
                VStack(spacing: 10) {
                    TeamlessPanel(store: store)
                    FooterBar(store: store)
                }
            } else {
                // 헤더 카드·팀 카드(헤더/게이지)·푸터는 콘텐츠 natural 높이. 팀 멤버 리스트만 팀원 수에 비례해 자라고,
                // maxVisibleRows를 넘으면 그 높이로 고정 후 스크롤한다. 팀별 현황 페이지도 같은 자리에서 동일 패턴.
                VStack(spacing: 10) {
                    HeaderCard(
                        store: store,
                        previewLongSessionBanner: previewLongSessionBanner,
                        previewGoalEditing: previewGoalEditing
                    )
                    // 토큰 소모량 행은 내 근무 박스와 팀원 현황 사이(사용자 지정 위치). 탭하면 순위 페이지.
                    CheckTokenUsageRow(store: store.tokenUsage, onOpenBoard: { store.toggleTokenBoard() })
                    if store.isLeaderboardVisible {
                        LeaderboardPanel(
                            // 원본 leaderboard 는 스토어에 보존하고, 표시 시점에 0시간 타팀만 숨긴다(내 팀은 0이어도 유지).
                            entries: store.leaderboard.filteredForDisplay(myTeamID: store.currentTeamID),
                            myTeamID: store.currentTeamID,
                            fallbackStatus: store.syncMessage,
                            unfilteredCount: store.leaderboard.count,
                            onBack: { store.isLeaderboardVisible = false },
                            clipsOverflowInsteadOfScroll: previewClipsOverflowList
                        )
                    } else if store.isTokenBoardVisible {
                        // 이번 달 AI 토큰 순위 페이지(앱 사용자 전체 공개). 리그와 같은 뼈대(뒤로 + 제목 + 고정 행높이 리스트/스크롤).
                        TokenBoardPanel(
                            entries: store.tokenBoard,
                            myUserID: store.session?.userID,
                            hasLoaded: store.tokenBoardLoaded,
                            fallbackStatus: store.syncMessage,
                            onBack: { store.isTokenBoardVisible = false },
                            clipsOverflowInsteadOfScroll: previewClipsOverflowList
                        )
                    } else {
                        // store 를 통째로 내려보내 초단위(displayNow) 의존을 잎 뷰로 격리한다 — TeamPanel 본체는
                        // displayNow 를 읽지 않으므로 매초 재정렬/재계산이 사라진다.
                        TeamPanel(
                            store: store,
                            previewCodeRevealed: previewOwnerCodeRevealed,
                            clipsOverflowInsteadOfScroll: previewClipsOverflowList
                        )
                    }
                    FooterBar(store: store)
                }
            }
        } else {
            // 로그인/가입 카드는 콘텐츠 natural 높이로만 그린다(세로 중앙정렬용 Spacer 제거 — 창을 짧게).
            LoginPanel(store: store, initialMode: initialAuthMode, previewWarning: previewASCIIWarning)
        }
    }
}

struct MenuBarStatusLabel: View {
    // 아이콘 판정용 스냅샷(상태/대기). 텍스트는 스토어가 계산해 둔 파생 저장값(menuBarTitle)을 그대로 쓴다.
    let snapshot: WorkStatusSnapshot
    // 상단바에 표시할 라벨 텍스트. 스토어가 == 가드와 함께 갱신하므로 여기선 그리기만 한다(매초 재계산 없음).
    let title: String

    var body: some View {
        HStack(spacing: 5) {
            if let mascot = CheckMascotAssets.menuBarImage(for: snapshot) {
                // 이미 18×18pt로 크기를 지정한 이미지라 .resizable()/.frame() 불필요.
                // MenuBarExtra 라벨이 intrinsic size를 써도 바 높이 안에 온전히 들어간다.
                Image(nsImage: mascot)
            } else {
                Image(systemName: MenuBarStatusFormatter.symbolName(for: snapshot))
                    .symbolRenderingMode(.hierarchical)
                    .imageScale(.medium)
            }
            Text(title)
                .font(.system(.body, design: .rounded).weight(.medium))
                .monospacedDigit()
        }
    }
}

// MARK: - Update banner (새 버전 안내 + 원클릭/명령 복사)

/// 팝오버 최상단 슬림 배너(accent 톤). 새 버전을 안내하고 [지금 업데이트] 원클릭 + [명령 복사] 폴백을 제공한다.
/// 원클릭은 UpdateRunner 로 분리 프로세스를 띄우며, running 중엔 "업데이트 중…"으로 바뀌고 [지금 업데이트]가 비활성된다.
/// brew 미탐지(unavailable)/스폰 실패(failed) 시 명령 복사 폴백 안내 줄을 노출한다. 복사 문자열은 정확히 `brew upgrade aing-check`.
private struct UpdateBanner: View {
    /// 표시용 버전 문자열("v0.3.0" — 상위에서 "v" 정규화).
    let versionText: String
    // runner 는 이 배너가 소유한다(AppDelegate 배선 불요). 테스트는 상태/스폰을 주입한 runner 를 넘겨 검증한다.
    @State private var runner: UpdateRunner
    @State private var copied = false

    init(versionText: String, runner: UpdateRunner = UpdateRunner()) {
        self.versionText = versionText
        _runner = State(initialValue: runner)
    }

    // 실행 실패/미탐지 시에만 폴백 안내를 띄운다(정상 경로는 군더더기 없이 두 버튼만).
    private var fallbackHint: String? {
        switch runner.status {
        case .unavailable: return "brew를 찾지 못했어요 — 아래 명령을 복사해 실행하세요"
        case .failed: return "자동 실행에 실패했어요 — 아래 명령을 복사해 실행하세요"
        case .idle, .running: return nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(CheckTheme.accent)
                Text(runner.status == .running ? "업데이트 중…" : "새 버전 \(versionText)가 나왔어요")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(CheckTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: 4)
            }
            HStack(spacing: 8) {
                // [지금 업데이트] — 원클릭(accent fill). running 중엔 "업데이트 중…"으로 바뀌고 비활성.
                Button {
                    copied = false
                    runner.runUpgrade()
                } label: {
                    Text(runner.status == .running ? "업데이트 중…" : "지금 업데이트")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background(RoundedRectangle(cornerRadius: 8).fill(CheckTheme.accent))
                        .opacity(runner.status == .running ? 0.7 : 1)
                }
                .buttonStyle(.plain)
                .disabled(runner.status == .running)

                // [명령 복사] — 폴백. 복사 후 "복사됨"으로 토글(CheckPasteboard 재사용).
                Button {
                    CheckPasteboard.copy(UpdateRunner.copyCommand)
                    copied = true
                } label: {
                    Label(copied ? "복사됨" : "명령 복사", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(CheckTheme.accent)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(CheckTheme.accent.opacity(0.14))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(CheckTheme.accent.opacity(0.35), lineWidth: 1))
                        )
                }
                .buttonStyle(.plain)
            }
            if let fallbackHint {
                Text(fallbackHint)
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(CheckTheme.accent.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(CheckTheme.accent.opacity(0.40), lineWidth: 1)
                )
        )
    }
}

// MARK: - Header card

private struct HeaderCard: View {
    @Bindable var store: WorkTimerStore
    // 렌더 스냅샷 전용: 12시간 배너를 켠 채로 그린다. 앱에서는 store.isLongSessionPromptActive만 사용.
    var previewLongSessionBanner: Bool = false
    // 렌더 스냅샷 전용: 헤더 주간 목표 편집 행을 펼친 채로 그린다. 앱에서는 항상 false(연필 버튼 토글).
    var previewGoalEditing: Bool = false

    // 실제 활성화(store)든 미리보기 플래그든 하나라도 켜지면 배너를 노출한다.
    private var showsLongSessionBanner: Bool {
        store.isLongSessionPromptActive || previewLongSessionBanner
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                CheckMascotView(snapshot: store.snapshot)
                    .frame(width: 46, height: 46)
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.snapshot.localizedStatus)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(statusTint)
                    // 큰 타이머는 매초 displayNow 에 의존하므로 잎 뷰로 격리한다 — 헤더 카드 본체가
                    // 매초 무효화되지 않게(무효화 반경을 이 텍스트로 한정).
                    TodayTimerText(store: store)
                }
                Spacer(minLength: 8)
                WorkTogglePill(
                    isWorking: store.snapshot.isWorking,
                    enabled: store.canSync,
                    action: { store.toggle() }
                )
            }
            // 내 주간 목표 진행 바 — 목표는 개인 약속이므로 "내" 접두어 없이 위치(내 박스)가 의미를 말한다.
            // myLiveWeeklySeconds(displayNow 파생)를 읽으므로 잎 뷰로 격리해 헤더 본체가 매초 무효화되지 않게 한다.
            HeaderGoalSection(store: store, previewGoalEditing: previewGoalEditing)
        }
        .padding(12)
        .panelStyle()
        // 배너는 헤더 카드 위 overlay로 얹어 카드 높이를 바꾸지 않는다(창 튐 방지).
        .overlay {
            if showsLongSessionBanner {
                LongSessionBanner(onConfirm: { store.confirmStillWorking() })
            }
        }
    }

    private var statusTint: Color {
        if store.snapshot.pendingSync {
            return CheckTheme.pending
        }
        return store.snapshot.isWorking ? CheckTheme.working : CheckTheme.offWork
    }
}

// MARK: - Header live leaves (초단위 격리)

/// 큰 타이머(오늘 누적). store.todayDuration(=displayNow 파생)만 읽어 매초 이 텍스트만 무효화된다.
private struct TodayTimerText: View {
    let store: WorkTimerStore

    var body: some View {
        // 큰 타이머 = 오늘 누적. 쉬었다 재개해도 0이 아니라 오늘 총합에서 이어 흐른다.
        Text(MenuBarStatusFormatter.duration(store.todayDuration))
            .font(.system(.title2, design: .monospaced).weight(.semibold))
            .foregroundStyle(CheckTheme.primaryText)
            .monospacedDigit()
    }
}

/// 헤더 하단 내 주간 목표 진행 섹션(슬림 바 + 캡션). store.myLiveWeeklySeconds(=displayNow 파생)만 읽어
/// 이 섹션만 매초 무효화된다. 위치(내 박스) 자체가 "내 진행률"임을 말하므로 "내/각자" 접두어를 쓰지 않는다.
private struct HeaderGoalSection: View {
    let store: WorkTimerStore
    // 렌더 스냅샷 전용: 목표 편집 행이 펼쳐진 상태로 그린다(연필 버튼 클릭 대신). 앱에서는 항상 false.
    var previewGoalEditing: Bool = false

    // 연필 버튼으로 토글하는 목표 편집 인라인 노출 상태. 스냅샷은 previewGoalEditing 로 시드된다.
    @State private var isEditingGoal: Bool
    // 편집 중 스테퍼가 바인딩하는 목표시간(시간 단위). 편집을 여는 순간 현재 목표로 초기화한다.
    @State private var editingHours: Int

    init(store: WorkTimerStore, previewGoalEditing: Bool = false) {
        self.store = store
        self.previewGoalEditing = previewGoalEditing
        _isEditingGoal = State(initialValue: previewGoalEditing)
        _editingHours = State(initialValue: Self.hours(from: store.teamGoalSeconds))
    }

    var body: some View {
        let worked = store.myLiveWeeklySeconds
        let goalSeconds = store.teamGoalSeconds
        let goal = TeamWeeklyGoal(workedSeconds: worked, goalSeconds: goalSeconds)
        // 편집 행은 캡션 아래로만 자란다(상단 앵커 원칙 — 위 콘텐츠를 밀지 않는다).
        VStack(spacing: 8) {
            VStack(spacing: 4) {
                // 슬림 진행 바(카드 폭 전체). 달성 시 working, 미달 시 accent 로 채운다(트랙은 기존 게이지 관례).
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(CheckTheme.trackFill)
                        Capsule()
                            .fill(goal.isComplete ? CheckTheme.working : CheckTheme.accent)
                            .frame(width: max(0, proxy.size.width * goal.progress))
                    }
                }
                .frame(height: 5)
                HStack(spacing: 4) {
                    // 좌측: 이번 주 누적 / 목표(시간 단위 정수). 우측: 실제 진행 퍼센트(100% 초과 가능, 상한 999%).
                    Text("이번 주 \(MenuBarStatusFormatter.hoursMinutes(worked)) / \(goalSeconds / 3600)시간")
                        .font(.caption2)
                        .foregroundStyle(CheckTheme.secondaryText)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text("\(GoalPercentFormatter.percent(workedSeconds: worked, goalSeconds: goalSeconds))%")
                        .font(.caption2)
                        .foregroundStyle(CheckTheme.secondaryText)
                        .monospacedDigit()
                    // 주간 목표는 팀원 누구나 바꿀 수 있다 — 캡션 % 옆 작은 연필로 편집 행을 연다.
                    // 표준 IconButton(27pt)은 caption2 행 높이를 홀로 키워 캡션 줄 간격이 어색해지므로,
                    // 캡션 높이에 맞춘 소형(18pt) 버튼을 쓴다.
                    GoalEditPencilButton(isActive: isEditingGoal) {
                        toggleEditing()
                    }
                }
            }
            if isEditingGoal {
                goalEditor
            }
        }
    }

    // 스테퍼(1~168) + 저장 버튼. 저장은 스토어 RPC 로 위임하고, 성공했을 때만 편집 행을 닫는다.
    @ViewBuilder
    private var goalEditor: some View {
        VStack(spacing: 8) {
            WeeklyGoalStepper(hours: $editingHours)
            AuthButton(title: "목표 저장", icon: "checkmark.circle.fill", prominent: true) {
                saveGoal()
            }
            .disabled(!store.canSync)
        }
    }

    // 편집을 여는 순간 현재 목표(시간)로 스테퍼를 맞춰, 팀원이 방금 바꾼 최신 목표에서 이어 편집하게 한다.
    private func toggleEditing() {
        if !isEditingGoal {
            editingHours = Self.hours(from: store.teamGoalSeconds)
        }
        isEditingGoal.toggle()
    }

    // 저장 성공 시에만 편집 행을 닫는다(실패 시 입력값을 유지해 바로 재시도할 수 있게 한다).
    private func saveGoal() {
        let hours = editingHours
        Task { @MainActor in
            if await store.updateTeamGoal(hours: hours) {
                isEditingGoal = false
            }
        }
    }

    // 초 단위 목표를 스테퍼 범위(1~168시간)로 클램프한 시간값.
    private static func hours(from goalSeconds: Int) -> Int {
        max(1, min(168, goalSeconds / 3600))
    }
}

/// 헤더 목표 캡션 행 전용 소형 연필 버튼(18pt). 캡션(caption2) 행 높이를 키우지 않으면서 hover 배경과
/// 툴팁으로 버튼임을 드러낸다 — 표준 IconButton(27pt)을 쓰면 이 행만 세로로 부풀어 배치가 어색해진다.
private struct GoalEditPencilButton: View {
    let isActive: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "pencil")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(isActive || hovering ? CheckTheme.accent : CheckTheme.secondaryText)
                .frame(width: 18, height: 18)
                .background(
                    Circle().fill(Color.white.opacity(hovering ? 0.14 : 0.06))
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("주간 목표 수정")
    }
}

// MARK: - Team card

private struct TeamPanel: View {
    // store 를 통째로 받아 대부분의 값을 파생 읽기한다. 초단위(displayNow) 의존은 잎 뷰로 격리하므로
    // 본체는 displayNow 를 읽지 않는다 — 매초 재정렬/재계산이 사라진다.
    let store: WorkTimerStore
    // 스냅샷 전용: 참여코드 인라인 행이 펼쳐진 상태로 그린다(키 버튼 클릭을 대신). 앱은 false.
    var previewCodeRevealed: Bool = false
    // 스냅샷 전용: 초과 리스트를 ScrollView 대신 클립으로 그린다(ImageRenderer 육안 확인용). 앱은 false.
    var clipsOverflowInsteadOfScroll: Bool = false

    // 키 버튼으로 토글하는 참여코드 인라인 노출 상태. 스냅샷은 previewCodeRevealed 로 시드된다.
    @State private var showsInviteCode: Bool

    init(
        store: WorkTimerStore,
        previewCodeRevealed: Bool = false,
        clipsOverflowInsteadOfScroll: Bool = false
    ) {
        self.store = store
        self.previewCodeRevealed = previewCodeRevealed
        self.clipsOverflowInsteadOfScroll = clipsOverflowInsteadOfScroll
        _showsInviteCode = State(initialValue: previewCodeRevealed)
    }

    // 참여코드를 보유(소속 팀원이면 로드됨)했을 때 키 버튼/인라인 행을 노출한다 — owner 뿐 아니라 팀원 누구나.
    private var canRevealCode: Bool {
        store.myTeamInviteCode != nil
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(CheckTheme.secondaryText)
                Text(store.teamName)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(CheckTheme.primaryText)
                    .lineLimit(1)
                Spacer(minLength: 6)
                // "N명 근무중" 카운트는 presence(now:) 파생이라 잎 뷰로 격리(본체가 매초 무효화되지 않게).
                TeamWorkingCountChip(store: store)
                if canRevealCode {
                    IconButton(
                        icon: showsInviteCode ? "key.fill" : "key",
                        help: showsInviteCode ? "참여코드 숨기기" : "참여코드 보기",
                        tint: showsInviteCode ? CheckTheme.accent : CheckTheme.secondaryText
                    ) {
                        showsInviteCode.toggle()
                    }
                }
                IconButton(icon: "chart.bar.xaxis", help: "팀별 현황") { store.toggleLeaderboard() }
            }
            // 참여코드 인라인 행은 헤더 아래에만 나타나 상단 앵커 원칙(아래로만 성장)을 지킨다.
            if canRevealCode, showsInviteCode, let inviteCode = store.myTeamInviteCode {
                InviteCodeInlineRow(code: inviteCode)
            }
            // 내 진행률은 헤더(내 박스)로 옮겼고, 팀원 각자의 진행률 바는 각 팀원 행 밑에 붙는다 — 단독 게이지 없음.
            PanelDivider()
            memberList
        }
        .padding(12)
        // 팀 카드 높이는 콘텐츠(멤버 리스트 포함)에 맞춘다 — 남는 공간 채우기(maxHeight:.infinity) 없음.
        .panelStyle()
    }

    // 행 사이 간격. 리스트 총 높이(팀원 수 비례) 계산에도 쓴다.
    private static let rowSpacing: CGFloat = 10
    // 스크롤 없이 그대로 보여 주는 최대 행 수. 이 수까지는 팀원 수에 비례해 자라고, 초과하면 이 높이로 고정 후 스크롤.
    // 행 높이가 48→58(행마다 목표 바 수납)으로 커져 7행이면 창이 700pt 상한을 넘으므로(731pt) 6으로 내린다.
    static let maxVisibleRows = 6

    // 표시할 행 개수(빈 팀은 안내용 1행).
    private var rowCount: Int {
        sortedMembers.isEmpty ? 1 : sortedMembers.count
    }

    // 멤버 리스트 높이 = 팀원 수 비례. maxVisibleRows까지는 rowHeight*count 그대로 자라고(스크롤 없음),
    // 초과하면 maxVisibleRows 높이로 고정하고 ScrollView로 스크롤한다(창 높이 상한).
    @ViewBuilder
    private var memberList: some View {
        let capHeight = Self.listContentHeight(rowCount: Self.maxVisibleRows)
        if rowCount <= Self.maxVisibleRows {
            rows.frame(maxWidth: .infinity, alignment: .top)
        } else if clipsOverflowInsteadOfScroll {
            // 스냅샷 전용: 보이는 첫 maxVisibleRows행만 클립해 그린다(ScrollView는 ImageRenderer가 못 그림).
            rows.frame(maxWidth: .infinity, alignment: .top)
                .frame(height: capHeight, alignment: .top)
                .clipped()
        } else {
            ScrollView(.vertical, showsIndicators: true) {
                rows.frame(maxWidth: .infinity)
            }
            .frame(height: capHeight)
        }
    }

    // 각 행은 memberRowHeight 상수로 고정 — 보조줄("마지막 확인 N분 전") 유무와 무관하게 동일 높이.
    // 행 내부의 시간/프레즌스는 displayNow 파생이라 TeamMemberLiveRow 잎 뷰가 읽는다(본체는 정렬만 담당).
    @ViewBuilder
    private var rows: some View {
        let myUserID = store.session?.userID
        VStack(spacing: Self.rowSpacing) {
            if sortedMembers.isEmpty {
                TeamMemberRow(name: "팀원", presence: .offWork, primaryDetail: store.syncMessage)
                    .frame(height: CheckTheme.memberRowHeight)
            } else {
                ForEach(sortedMembers) { member in
                    let isMe = myUserID != nil && member.id == myUserID
                    TeamMemberLiveRow(
                        store: store,
                        member: member,
                        teamGoalSeconds: store.teamGoalSeconds,
                        isMe: isMe,
                        onPickAvatar: isMe ? { store.updateAvatar(imageData: $0) } : nil
                    )
                    .frame(height: CheckTheme.memberRowHeight)
                }
            }
        }
    }

    // 고정 행 높이·간격으로 계산한 리스트 총 높이(팀원 수 비례). 스크롤 상한(maxVisibleRows) 높이 산정에도 쓴다.
    static func listContentHeight(rowCount: Int) -> CGFloat {
        guard rowCount > 0 else { return 0 }
        return CGFloat(rowCount) * CheckTheme.memberRowHeight + CGFloat(rowCount - 1) * rowSpacing
    }

    private var sortedMembers: [TeamMemberStatus] {
        store.teamMembers.sorted { lhs, rhs in
            let lhsWorking = lhs.status == .working
            let rhsWorking = rhs.status == .working
            if lhsWorking != rhsWorking {
                return lhsWorking
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}

// MARK: - Team card live leaves (초단위 격리)

/// "N명 근무중" 카운트 칩. presence(now:) 파생이라 잎 뷰로 분리해 이 칩만 매초 무효화되게 한다.
private struct TeamWorkingCountChip: View {
    let store: WorkTimerStore

    var body: some View {
        let now = store.displayNow
        // 라이브 근무(activeWorking)만 집계한다. 연결 끊김은 제외.
        CountChip(count: store.teamMembers.filter { $0.presence(now: now) == .activeWorking }.count)
    }
}

/// 내 주간 진행률 게이지. myLiveWeeklySeconds(=displayNow 파생)만 읽어 게이지만 무효화되게 한다.
private struct MyWeeklyGauge: View {
    let store: WorkTimerStore
    // 1인당 주간 목표시간(초). teams.weekly_goal_hours(store.teamGoalSeconds) — 팀 총합이 아니라 "각자 X시간".
    let teamGoalSeconds: Int

    var body: some View {
        TeamGoalGauge(
            goal: TeamWeeklyGoal(workedSeconds: store.myLiveWeeklySeconds, goalSeconds: teamGoalSeconds),
            workedLabelPrefix: "내 ",
            goalLabelPrefix: "각자 "
        )
    }
}

/// 팀원 한 행의 라이브 래퍼. store.displayNow 를 읽어 시간/프레즌스를 계산하고
/// TeamMemberRow 에 값으로 넘긴다 — presence(now:)를 행당 1회만 계산해 하위 파생에 재사용한다.
private struct TeamMemberLiveRow: View {
    let store: WorkTimerStore
    let member: TeamMemberStatus
    let teamGoalSeconds: Int
    let isMe: Bool
    var onPickAvatar: ((Data) -> Void)? = nil

    var body: some View {
        let now = store.displayNow
        let presence = member.presence(now: now)
        // 이 팀원의 1인당 목표 진행 비율(0~1 클램프). 라이브 주간 누적/목표 — displayNow 파생이라 이 잎 뷰가 읽는다.
        let goalFraction = TeamWeeklyGoal(
            workedSeconds: member.liveWeeklyDurationSeconds(now: now),
            goalSeconds: teamGoalSeconds
        ).progress
        TeamMemberRow(
            name: member.name,
            avatarURL: member.avatarURL,
            presence: presence,
            primaryDetail: Self.primaryDetail(member, presence: presence, now: now),
            secondaryDetail: Self.secondaryDetail(member, presence: presence, now: now),
            meetsWeeklyGoal: member.hasMetWeeklyGoal(goalSeconds: teamGoalSeconds, now: now),
            goalFraction: goalFraction,
            isMe: isMe,
            onPickAvatar: isMe ? onPickAvatar : nil
        )
    }

    // 상태별 표시용 현재 세션 시간. active는 라이브 틱, stale은 마지막 신호에서 동결, off는 0.
    private static func displayCurrentSeconds(_ member: TeamMemberStatus, presence: MemberPresence, now: Date) -> Int {
        switch presence {
        case .activeWorking:
            return member.currentDurationSeconds(now: now)
        case .staleWorking(let frozen):
            return frozen
        case .offWork:
            return 0
        }
    }

    // 상태별 표시용 주간 누적. 항상 모델의 liveWeeklyDurationSeconds 를 쓴다 — stale 동결(마지막 신호 시각
    // 클램프)과 주 시작 클리핑을 모델이 모두 처리하므로, 뷰에서 weeklyDurationSeconds+frozen 을 다시 조립하면
    // 주 경계에서 모델 공식과 어긋난다(주 시작 이전 구간을 이중 계상해 2h 어긋남).
    private static func displayWeeklySeconds(_ member: TeamMemberStatus, presence: MemberPresence, now: Date) -> Int {
        member.liveWeeklyDurationSeconds(now: now)
    }

    private static func primaryDetail(_ member: TeamMemberStatus, presence: MemberPresence, now: Date) -> String {
        let weekly = "주 \(MenuBarStatusFormatter.hoursMinutes(displayWeeklySeconds(member, presence: presence, now: now)))"
        switch presence {
        case .offWork:
            return weekly
        case .activeWorking, .staleWorking:
            return "현재 \(MenuBarStatusFormatter.duration(displayCurrentSeconds(member, presence: presence, now: now))) · \(weekly)"
        }
    }

    // stale 상태에만 "마지막 확인 N분 전" 보조줄을 붙인다. 그 외엔 nil.
    private static func secondaryDetail(_ member: TeamMemberStatus, presence: MemberPresence, now: Date) -> String? {
        guard case .staleWorking = presence, let seen = member.lastSeenAt else {
            return nil
        }
        let minutes = max(1, Int(now.timeIntervalSince(seen) / 60))
        return "마지막 확인 \(minutes)분 전"
    }
}

// MARK: - Team league page

/// 팀 카드 자리를 대체하는 팀별 현황 페이지. 헤더/푸터는 CheckMenuView 가 유지하고, 이 카드만 교체된다.
/// 제목 + 뒤로 버튼 + 1인당 평균 내림차순 팀 목록(우리 팀 칩). 팀이 많으면 memberList 패턴으로 스크롤.
/// 리그 빈 목록 자리 문구 선택(순수 로직, 결정적 검증 지점). 필터 전 원본에 팀이 있었는데(unfilteredCount>0)
/// 표시 목록이 비면 '0시간 필터로 전부 숨겨진' 것이므로 중립 문구를 쓴다. 원본도 비면(0) 로드 전/실패로 보고
/// fallbackStatus(동기화 상태 문구)를 그대로 노출한다 — 성공 동기화("동기화됨")가 본문에 뜨는 어색함과 구분.
enum LeaderboardEmptyMessage {
    static let filteredOut = "아직 이번 주 근무한 팀이 없어요"
    static func text(unfilteredCount: Int, fallbackStatus: String) -> String {
        unfilteredCount > 0 ? filteredOut : fallbackStatus
    }
}

private struct LeaderboardPanel: View {
    // 1인당 평균 내림차순으로 정렬된 팀 목록(store 에서 이미 정렬됨). 서버 정렬을 신뢰하지 않고 뷰에서도 다시 정렬한다.
    let entries: [TeamLeaderboardEntry]
    // 우리 팀 id(칩 표시 판정용). 무소속이면 nil 이라 어떤 행에도 칩이 붙지 않는다.
    var myTeamID: String? = nil
    // 아직 로드 전/실패 시 빈 목록 자리에 표시할 안내 문구.
    let fallbackStatus: String
    // 필터 전(원본) 팀 수. >0 인데 표시 목록이 비면 '0시간 필터로 전부 숨겨진' 것이므로 중립 문구를 쓴다(아래).
    // 0 이면 로드 전/실패로 보고 fallbackStatus 를 쓴다 — 둘을 구분해 성공 동기화("동기화됨")가 본문에 뜨지 않게.
    var unfilteredCount: Int = 0
    var onBack: () -> Void = {}
    // 스냅샷 전용: 초과 리스트를 ScrollView 대신 클립으로 그린다(ImageRenderer 육안 확인용). 앱은 false.
    var clipsOverflowInsteadOfScroll: Bool = false

    // 팀 행 고정 높이·간격. 팀원 행보다 높다(아바타 + 이름/시간 + 게이지 + 캡션 3단).
    private static let rowHeight: CGFloat = 58
    private static let rowSpacing: CGFloat = 10
    // 스크롤 없이 그대로 보여 주는 최대 팀 수. 행이 팀원 행보다 높아 창 높이 상한(≤700pt)을 지키도록 6으로 둔다.
    static let maxVisibleRows = 6

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                IconButton(icon: "chevron.left", help: "뒤로", action: onBack)
                Text("팀별 이번 주")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(CheckTheme.primaryText)
                    .lineLimit(1)
                Spacer(minLength: 6)
            }
            PanelDivider()
            entryList
        }
        .padding(12)
        .panelStyle()
    }

    private var sortedEntries: [TeamLeaderboardEntry] {
        entries.sortedByAverageDescending()
    }

    private var rowCount: Int {
        sortedEntries.isEmpty ? 1 : sortedEntries.count
    }

    // 리스트 높이 = 팀 수 비례. maxVisibleRows까지는 그대로 자라고(스크롤 없음), 초과하면 그 높이로 고정 후 스크롤.
    @ViewBuilder
    private var entryList: some View {
        let capHeight = Self.listContentHeight(rowCount: Self.maxVisibleRows)
        if rowCount <= Self.maxVisibleRows {
            rows.frame(maxWidth: .infinity, alignment: .top)
        } else if clipsOverflowInsteadOfScroll {
            // 스냅샷 전용: 보이는 첫 maxVisibleRows행만 클립해 그린다(ScrollView는 ImageRenderer가 못 그림).
            rows.frame(maxWidth: .infinity, alignment: .top)
                .frame(height: capHeight, alignment: .top)
                .clipped()
        } else {
            ScrollView(.vertical, showsIndicators: true) {
                rows.frame(maxWidth: .infinity)
            }
            .frame(height: capHeight)
        }
    }

    @ViewBuilder
    private var rows: some View {
        VStack(spacing: Self.rowSpacing) {
            if sortedEntries.isEmpty {
                // 원본에 팀이 있었는데 표시 목록이 비면 필터로 전부 숨겨진 것 — 중립 문구. 원본도 비면 로드 전/실패로
                // 보고 fallbackStatus(동기화 상태 문구)를 쓴다(결정적 판정은 LeaderboardEmptyMessage 로 격리).
                Text(LeaderboardEmptyMessage.text(unfilteredCount: unfilteredCount, fallbackStatus: fallbackStatus))
                    .font(.caption)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: Self.rowHeight, alignment: .leading)
            } else {
                ForEach(sortedEntries, id: \.id) { entry in
                    LeaderboardRow(entry: entry, isMyTeam: entry.id == myTeamID)
                        .frame(height: Self.rowHeight)
                }
            }
        }
    }

    static func listContentHeight(rowCount: Int) -> CGFloat {
        guard rowCount > 0 else { return 0 }
        return CGFloat(rowCount) * rowHeight + CGFloat(rowCount - 1) * rowSpacing
    }
}

// MARK: - Team monthly token board page

/// 토큰 보드 빈 목록 자리 문구 선택(순수 로직, 결정적 검증 지점). 전체 공개라 '행 없는 사용자 0 채움'은 폐기됐고,
/// 목록이 비면 두 경우다: (1) 로드가 성공했는데 아직 아무도 이번 달 소모량을 올리지 않음(hasLoaded=true) → 안내 문구,
/// (2) 아직 로드 전이거나 실패(hasLoaded=false) → fallbackStatus(동기화 상태 문구). 리그의 LeaderboardEmptyMessage 와 같은 패턴.
enum TokenBoardEmptyMessage {
    static let noUploads = "아직 이번 달 소모량을 올린 사용자가 없어요"
    static func text(hasLoaded: Bool, fallbackStatus: String) -> String {
        hasLoaded ? noUploads : fallbackStatus
    }
}

/// 팀 카드 자리를 대체하는 "이번 달 AI 토큰" 순위 페이지(앱 사용자 전체 공개). 리그 페이지와 같은 뼈대다:
/// 뒤로 버튼 + 제목 + 고정 행높이 리스트(maxVisibleRows 초과 시 스크롤). 등수 숫자/메달 배지는 없다 — 정렬 순서가 곧 순위.
/// 행은 아바타 + 이름(+내 행 "나" 칩) + 우측 전체 숫자(콤마 구분·monospacedDigit). 업로드한 사용자만 뜬다(행 없으면
/// 목록에 없음). 목록이 비면 로드 성공 여부에 따라 '아직 없음' 또는 fallbackStatus 를 보인다.
private struct TokenBoardPanel: View {
    // total 내림차순(동률 이름)으로 정렬된 엔트리(store 에서 이미 정렬됨). 뷰에서도 같은 규약으로 다시 정렬한다.
    let entries: [TokenBoardEntry]
    // 내 user_id(내 행 "나" 칩 판정용). nil 이면 어떤 행에도 칩이 붙지 않는다.
    var myUserID: String? = nil
    // 보드 첫 성공 로드 여부. 빈 목록 문구를 '아직 없음'(true) vs 로드 전/실패 fallbackStatus(false) 로 가른다.
    var hasLoaded: Bool = false
    // 아직 로드 전/실패 시 빈 목록 자리에 표시할 안내 문구(동기화 상태 문구).
    var fallbackStatus: String = ""
    var onBack: () -> Void = {}
    // 스냅샷 전용: 초과 리스트를 ScrollView 대신 클립으로 그린다(ImageRenderer 육안 확인용). 앱은 false.
    var clipsOverflowInsteadOfScroll: Bool = false

    // 토큰 행은 프로필 카드(RoundedRectangle 테두리 + 내부 패딩 + 좌측 악센트 바)라 밋밋한 한 줄보다 높다.
    // 카드가 아바타(30pt)를 위아래 여백과 함께 수납하도록 50pt로 둔다. 카드 간 간격은 사양대로 8.
    private static let rowHeight: CGFloat = 50
    private static let rowSpacing: CGFloat = 8
    // 스크롤 없이 보여 주는 최대 인원. 카드화로 행이 높아졌지만(50pt·7행) 리스트 높이 398pt로 창 높이 상한(≤700pt) 안이다.
    static let maxVisibleRows = 7

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                IconButton(icon: "chevron.left", help: "뒤로", action: onBack)
                Text("이번 달 AI 토큰 소모량")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(CheckTheme.primaryText)
                    .lineLimit(1)
                Spacer(minLength: 6)
            }
            PanelDivider()
            entryList
        }
        .padding(12)
        .panelStyle()
    }

    // 서버 정렬을 신뢰하지 않고 뷰에서도 total 내림차순(동률 이름)으로 다시 정렬한다.
    private var sortedEntries: [TokenBoardEntry] {
        entries.sortedByTotalDescending()
    }

    private var rowCount: Int {
        sortedEntries.isEmpty ? 1 : sortedEntries.count
    }

    // 리스트 높이 = 인원 비례. maxVisibleRows까지는 그대로 자라고(스크롤 없음), 초과하면 그 높이로 고정 후 스크롤.
    @ViewBuilder
    private var entryList: some View {
        let capHeight = Self.listContentHeight(rowCount: Self.maxVisibleRows)
        if rowCount <= Self.maxVisibleRows {
            rows.frame(maxWidth: .infinity, alignment: .top)
        } else if clipsOverflowInsteadOfScroll {
            // 스냅샷 전용: 보이는 첫 maxVisibleRows행만 클립해 그린다(ScrollView는 ImageRenderer가 못 그림).
            rows.frame(maxWidth: .infinity, alignment: .top)
                .frame(height: capHeight, alignment: .top)
                .clipped()
        } else {
            ScrollView(.vertical, showsIndicators: true) {
                rows.frame(maxWidth: .infinity)
            }
            .frame(height: capHeight)
        }
    }

    @ViewBuilder
    private var rows: some View {
        VStack(spacing: Self.rowSpacing) {
            if sortedEntries.isEmpty {
                // 로드 성공했는데 비면 '아직 아무도 안 올림', 로드 전/실패면 fallbackStatus(동기화 상태 문구).
                // 결정적 판정은 TokenBoardEmptyMessage 로 격리한다.
                Text(TokenBoardEmptyMessage.text(hasLoaded: hasLoaded, fallbackStatus: fallbackStatus))
                    .font(.caption)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: Self.rowHeight, alignment: .leading)
            } else {
                ForEach(sortedEntries) { entry in
                    TokenBoardRowView(entry: entry, isMe: myUserID != nil && entry.userID == myUserID)
                        .frame(height: Self.rowHeight)
                }
            }
        }
    }

    static func listContentHeight(rowCount: Int) -> CGFloat {
        guard rowCount > 0 else { return 0 }
        return CGFloat(rowCount) * rowHeight + CGFloat(rowCount - 1) * rowSpacing
    }
}

/// 토큰 보드 한 행 = 유저 프로필 카드: 좌측 세로 악센트 바(유저 해시색) + 이니셜/원격 아바타 + 이름(+내 행 "나" 칩)
/// + 우측 이번 달 총합("숫자 토큰"). 등수 배지 없이 담백하게 — 정렬 순서가 곧 순위다. 카드는 fieldFill 채움 + 1px 테두리
/// (내 카드는 테두리를 accent 은은하게)로 유저 간 분리를 준다. 악센트 바 색은 CheckTheme.avatarColor 로 아바타 이니셜과
/// 같은 이름 해시색을 공유해 유저마다 자연스러운 컬러 포인트를 만든다(등수 뉘앙스 아님). 높이는 패널이 고정으로 준다.
private struct TokenBoardRowView: View {
    let entry: TokenBoardEntry
    var isMe: Bool = false

    // 좌측 악센트 바 색 — 아바타 이니셜과 동일한 이름 해시색(CheckTheme.avatarColor 공유). 유저별 컬러 포인트.
    private var accentColor: Color { CheckTheme.avatarColor(for: entry.name) }

    var body: some View {
        HStack(spacing: 10) {
            // 좌측 세로 악센트 바(3pt 캡슐): 유저 해시색. 카드 안에서 위아래 살짝 띄워 유저 구분 컬러 포인트를 준다.
            Capsule()
                .fill(accentColor)
                .frame(width: 3)
                .frame(maxHeight: .infinity)
                .padding(.vertical, 3)
            CheckAvatarView(name: entry.name, avatarURL: entry.avatarURL, size: 30)
            Text(entry.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CheckTheme.primaryText)
                .lineLimit(1)
            if isMe {
                Text("나")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(CheckTheme.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(CheckTheme.accent.opacity(0.18)))
                    .fixedSize()
            }
            Spacer(minLength: 6)
            // 총합 + 단위: 축약(B/M/K) 없이 전체 숫자를 콤마로 끊고(굵게·monospacedDigit) 오른쪽에 " 토큰"(caption2·secondary)을 붙인다.
            // 숫자+단위를 한 Text 로 이어(concat) minimumScaleFactor 가 단위째로 균일 축소되게 해 좁을 때도 한 줄을 지킨다.
            (
                Text(TokenNumberFormatter.grouped(entry.total))
                    .font(.caption.weight(.bold))
                    .foregroundColor(CheckTheme.primaryText)
                    .monospacedDigit()
                + Text(" 토큰")
                    .font(.caption2)
                    .foregroundColor(CheckTheme.secondaryText)
            )
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .padding(.leading, 8)
        .padding(.trailing, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 유저별 프로필 카드: fieldFill 채움 + 1px 테두리. 내 카드는 테두리를 accent(은은한 0.45)로 바꿔 한눈에 띄운다.
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(CheckTheme.fieldFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(isMe ? CheckTheme.accent.opacity(0.45) : CheckTheme.border, lineWidth: 1)
        )
    }
}

// MARK: - Footer utility bar

private struct FooterBar: View {
    @Bindable var store: WorkTimerStore

    var body: some View {
        HStack(spacing: 8) {
            SyncStatusView(message: store.syncMessage)
            Spacer(minLength: 6)
            IconButton(
                icon: store.isOverlayEnabled ? "person.fill" : "person.fill.xmark",
                help: store.isOverlayEnabled ? "캐릭터 표시 중 — 누르면 숨김" : "캐릭터 숨김 — 누르면 표시"
            ) {
                store.toggleOverlayEnabled()
            }
            IconButton(icon: "arrow.clockwise", help: "새로고침") {
                store.refreshTeamStatus()
            }
            IconButton(icon: "rectangle.portrait.and.arrow.right", help: "로그아웃") {
                store.signOut()
            }
            IconButton(icon: "power", help: "앱 종료", tint: CheckTheme.danger) {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .panelStyle()
    }
}

// MARK: - Login panel

/// 로그인/가입을 오가는 뷰 로컬 UI 상태. store가 아니라 뷰에서만 관리한다.
enum AuthMode {
    case signIn
    case signUp
}

/// 로그인/가입 패널의 Enter-키 포커스 체이닝 대상 필드.
enum AuthFocusField: Hashable {
    case displayName
    case email
    case password

    /// 이 필드에서 Enter를 눌렀을 때 옮겨 갈 다음 포커스 필드. nil이면 마지막 필드이므로 제출한다.
    /// 로그인 모드엔 별명 필드가 없으므로 로그인 모드의 displayName은 제출로 취급한다.
    func nextField(mode: AuthMode) -> AuthFocusField? {
        switch (mode, self) {
        case (.signUp, .displayName):
            return .email
        case (_, .email):
            return .password
        case (.signIn, .displayName), (_, .password):
            return nil
        }
    }
}

/// syncMessage 배너의 성격 분류. AuthStatusLine 색/아이콘과 모드 전환 시 오류 리셋 판정에 공유한다.
enum AuthMessageKind {
    case progress, info, error

    init(_ message: String) {
        switch message {
        case "로그인 중", "계정 생성 중":
            self = .progress
        case "확인 메일 필요", "이메일 확인 필요":
            self = .info
        default:
            self = .error
        }
    }
}

private struct LoginPanel: View {
    @Bindable var store: WorkTimerStore
    @State private var mode: AuthMode
    // 렌더 스냅샷 전용: 비밀번호 필드의 안내 캡션을 켠 채로 그린다. 앱에서는 항상 false.
    private let previewWarning: Bool
    @FocusState private var focus: AuthFocusField?

    init(store: WorkTimerStore, initialMode: AuthMode = .signIn, previewWarning: Bool = false) {
        self.store = store
        _mode = State(initialValue: initialMode)
        self.previewWarning = previewWarning
    }

    // 가입(create 모드)에 성공하면 참여코드 공유 카드로 화면을 대체한다.
    private var showsCreatedCode: Bool {
        mode == .signUp && store.createdTeamCode != nil
    }

    var body: some View {
        VStack(spacing: 12) {
            if showsCreatedCode, let code = store.createdTeamCode {
                BrandHeader(subtitle: "팀 생성 완료")
                PanelDivider()
                CreatedTeamCodeCard(code: code) { store.dismissCreatedTeamCode() }
            } else {
                BrandHeader(subtitle: subtitle)
                PanelDivider()
                credentialFields
                primaryButton
                    .disabled(!store.canSync)
                // 상태 배너 슬롯은 항상 확보하고 메시지 유무는 opacity로만 토글한다 — 오류 배너 등장 시 창 튐 제거.
                AuthStatusLine(message: store.syncMessage)
                    .opacity(store.syncMessage == "로그인 필요" ? 0 : 1)
                    .accessibilityHidden(store.syncMessage == "로그인 필요")
                links
            }
        }
        .padding(14)
        .panelStyle()
        .animation(.easeInOut(duration: 0.22), value: mode)
        .animation(.easeInOut(duration: 0.22), value: store.isCreateTeamMode)
    }

    private var subtitle: String {
        switch mode {
        case .signIn:
            return "팀 근무 타이머"
        case .signUp:
            return store.isCreateTeamMode ? "새 팀을 만들어요" : "팀 코드로 합류해요"
        }
    }

    // 별명(가입만) / 이메일 / 비밀번호 + 가입 모드의 팀 코드 또는 팀 만들기 폼.
    @ViewBuilder
    private var credentialFields: some View {
        VStack(spacing: 8) {
            if mode == .signUp {
                CredentialField(
                    title: "별명",
                    icon: "person.text.rectangle.fill",
                    text: $store.displayName,
                    focus: $focus,
                    fieldIdentifier: .displayName,
                    submitLabel: .next,
                    onSubmit: { advance(from: .displayName) }
                )
            }
            CredentialField(
                title: "이메일",
                icon: "envelope.fill",
                text: $store.email,
                enforcesASCII: true,
                allowsSpace: false,
                focus: $focus,
                fieldIdentifier: .email,
                submitLabel: .next,
                onSubmit: { advance(from: .email) }
            )
            CredentialField(
                title: "비밀번호",
                icon: "lock.fill",
                text: $store.password,
                isSecure: true,
                enforcesASCII: true,
                warnsInitially: previewWarning,
                focus: $focus,
                fieldIdentifier: .password,
                submitLabel: .go,
                onSubmit: { advance(from: .password) }
            )
            if mode == .signUp {
                if store.isCreateTeamMode {
                    // 팀 이름은 한글 허용(ASCII 강제 없음). 주간 목표는 스테퍼(1~168시간).
                    CredentialField(
                        title: "팀 이름",
                        icon: "person.3.fill",
                        text: $store.createTeamName
                    )
                    WeeklyGoalStepper(hours: $store.createTeamGoalHours)
                } else {
                    TeamCodeField(
                        code: $store.signupTeamCode,
                        preview: store.joinPreview,
                        message: store.joinPreviewMessage,
                        onDebouncedChange: { store.previewTeamCode() }
                    )
                }
            }
        }
    }

    // 필드에서 Enter를 눌렀을 때: 다음 필드가 있으면 포커스를 옮기고, 없으면(마지막 필드) 제출한다.
    private func advance(from field: AuthFocusField) {
        if let next = field.nextField(mode: mode) {
            focus = next
        } else {
            submitPrimary()
        }
    }

    // Enter(제출) 시 로그인/가입 버튼과 동일하게 동작한다. canSync 가드로 키 없음 상태에선 무시한다.
    private func submitPrimary() {
        guard store.canSync else { return }
        switch mode {
        case .signIn:
            store.signIn()
        case .signUp:
            store.signUp()
        }
    }

    // 하나의 prominent 전체폭 버튼만 노출한다. 모드/서브모드에 따라 로그인/가입/팀 만들기로 바뀐다.
    @ViewBuilder
    private var primaryButton: some View {
        switch mode {
        case .signIn:
            AuthButton(title: "로그인", icon: "person.crop.circle.badge.checkmark", prominent: true) {
                store.signIn()
            }
        case .signUp:
            if store.isCreateTeamMode {
                AuthButton(title: "팀 만들고 시작하기", icon: "flag.fill", prominent: true) {
                    store.signUp()
                }
            } else {
                AuthButton(title: "가입", icon: "person.badge.plus", prominent: true) {
                    store.signUp()
                }
            }
        }
    }

    // 가입 모드엔 두 개의 링크: (1) 코드↔팀 만들기 전환, (2) 로그인 복귀. 로그인 모드엔 가입 전환 하나.
    @ViewBuilder
    private var links: some View {
        VStack(spacing: 8) {
            if mode == .signUp {
                AuthLinkButton(
                    prompt: store.isCreateTeamMode ? "" : "팀 코드가 없나요?",
                    action: store.isCreateTeamMode ? "코드로 참여하기" : "새 팀 만들기"
                ) {
                    toggleCreateTeamMode()
                }
            }
            switchLink
        }
    }

    @ViewBuilder
    private var switchLink: some View {
        switch mode {
        case .signIn:
            AuthLinkButton(prompt: "계정이 없나요?", action: "가입하기") {
                switchMode(to: .signUp)
            }
        case .signUp:
            AuthLinkButton(prompt: "이미 계정이 있나요?", action: "로그인") {
                switchMode(to: .signIn)
            }
        }
    }

    // 코드 입력 ↔ 팀 만들기 폼 전환. 이전 코드 미리보기 잔상을 지워 혼동을 막는다.
    private func toggleCreateTeamMode() {
        store.isCreateTeamMode.toggle()
        store.joinPreview = nil
        store.joinPreviewMessage = ""
    }

    // 입력값은 유지하되, 이전 모드의 오류 배너가 새 모드에서 혼동을 주지 않도록 리셋한다.
    private func switchMode(to newMode: AuthMode) {
        if AuthMessageKind(store.syncMessage) == .error {
            store.syncMessage = "로그인 필요"
        }
        mode = newMode
        // 가입은 항상 코드 입력으로 시작한다(팀 만들기는 하단 링크로 전환).
        if newMode == .signUp {
            store.isCreateTeamMode = false
        }
    }
}

// MARK: - Teamless panel (signed in, no team)

/// 로그인은 됐지만 소속 팀이 없을 때(무소속) 메인 대신 보여 주는 간단 패널.
/// 코드로 참여(참여하기) ↔ 새 팀 만들기 폼을 오간다. 코드 미리보기 UX는 가입 화면과 동일하다.
private struct TeamlessPanel: View {
    @Bindable var store: WorkTimerStore

    var body: some View {
        VStack(spacing: 12) {
            if let code = store.createdTeamCode {
                // 팀을 막 만든 직후 — 참여코드 공유 카드로 대체한다.
                BrandHeader(subtitle: "팀 생성 완료")
                PanelDivider()
                CreatedTeamCodeCard(code: code) { store.dismissCreatedTeamCode() }
            } else {
                BrandHeader(subtitle: store.isCreateTeamMode ? "새 팀을 만들어요" : "합류할 팀을 찾아요")
                PanelDivider()
                if store.isCreateTeamMode {
                    createForm
                } else {
                    joinForm
                }
                AuthStatusLine(message: store.syncMessage)
                    .opacity(store.syncMessage == "동기화됨" || store.syncMessage == "로그인 필요" ? 0 : 1)
                    .accessibilityHidden(store.syncMessage == "동기화됨" || store.syncMessage == "로그인 필요")
                modeLink
            }
        }
        .padding(14)
        .panelStyle()
        .animation(.easeInOut(duration: 0.22), value: store.isCreateTeamMode)
    }

    // 코드로 참여: 안내 문구 + 팀 코드 필드(미리보기) + [참여하기].
    @ViewBuilder
    private var joinForm: some View {
        VStack(spacing: 10) {
            Text("소속된 팀이 없어요. 팀 코드를 입력해 합류하세요.")
                .font(.caption)
                .foregroundStyle(CheckTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            TeamCodeField(
                code: $store.signupTeamCode,
                preview: store.joinPreview,
                message: store.joinPreviewMessage,
                onDebouncedChange: { store.previewTeamCode() }
            )
            AuthButton(title: "참여하기", icon: "person.badge.plus", prominent: true) {
                store.joinTeamWithCode()
            }
            .disabled(!store.canSync)
        }
    }

    // 새 팀 만들기: 팀 이름 + 주간 목표 스테퍼 + [팀 만들고 시작하기]. 가입 화면 폼과 같은 컨트롤을 재사용한다.
    @ViewBuilder
    private var createForm: some View {
        VStack(spacing: 8) {
            CredentialField(
                title: "팀 이름",
                icon: "person.3.fill",
                text: $store.createTeamName
            )
            WeeklyGoalStepper(hours: $store.createTeamGoalHours)
            AuthButton(title: "팀 만들고 시작하기", icon: "flag.fill", prominent: true) {
                // 팀 생성은 가입 화면과 동일한 진입점(signUp)을 쓴다 — create 모드면 create_team 을 실행한다.
                store.signUp()
            }
            .disabled(!store.canSync)
        }
    }

    // 코드 참여 ↔ 새 팀 만들기 전환 링크. 전환 시 이전 코드 미리보기 잔상을 지운다.
    @ViewBuilder
    private var modeLink: some View {
        AuthLinkButton(
            prompt: store.isCreateTeamMode ? "" : "팀 코드가 없나요?",
            action: store.isCreateTeamMode ? "코드로 참여하기" : "새 팀 만들기"
        ) {
            store.isCreateTeamMode.toggle()
            store.joinPreview = nil
            store.joinPreviewMessage = ""
        }
    }
}

private struct AuthStatusLine: View {
    let message: String

    private var kind: AuthMessageKind { AuthMessageKind(message) }

    private var tint: Color {
        switch kind {
        case .progress: return CheckTheme.accent
        case .info: return CheckTheme.pending
        case .error: return CheckTheme.danger
        }
    }

    private var icon: String {
        switch kind {
        case .progress: return "arrow.triangle.2.circlepath"
        case .info: return "envelope.badge.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(message)
                .font(.caption.weight(.medium))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(tint.opacity(0.12))
        )
    }
}
