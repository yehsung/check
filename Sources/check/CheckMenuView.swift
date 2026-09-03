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
    // 스냅샷 전용: 배너에 얹을 패치노트 줄을 강제로 주입한다. 앱에서는 updateCheck?.latestNotes(릴리스 노트 파싱본)만 쓴다.
    var previewUpdateNotes: [String] = []
    // 스냅샷 전용: 콕찌르기 목록에서 이 사용자의 메시지 작성기가 펼쳐진 상태로 그린다. 앱은 nil(말풍선 버튼 토글).
    var previewMessageComposerUserID: String? = nil
    // 스냅샷 전용: 펼친 작성기 입력칸에 미리 들어가 있는 값(글자수 카운터 상태 재현). 앱은 ""(빈 칸에서 시작).
    var previewMessageDraft: String = ""

    // 실제 감지(updateCheck)든 미리보기 플래그든 하나라도 켜지면 최상단 배너 후보가 된다.
    private var showsUpdateBanner: Bool {
        previewUpdateBanner || (updateCheck?.isUpdateAvailable ?? false)
    }

    // 12시간 확인 배너 후보 여부. 실제 활성화(store)든 미리보기 플래그든 하나라도 켜지면 헤더 위 형제로 그린다.
    private var showsLongSessionBanner: Bool {
        store.isLongSessionPromptActive || previewLongSessionBanner
    }

    // MARK: - 창 높이 예산

    /// 팝오버에 **동시에 그리는 배너는 하나뿐**이다. 창은 위 모서리가 메뉴바 아래에 고정되고 아래로만 자라므로
    /// (CheckWindowAnchor) 배너가 겹쳐 쌓이면 총 높이가 상한(700pt)을 넘어 푸터(로그아웃/앱 종료)와 패널 하단이
    /// 화면 밖으로 잘린다. 그래서 급한 순서대로 하나만 고르고 나머지는 다음 팝오버로 미룬다 — 상태는 소비하지
    /// 않으므로(회고 주 키/업데이트 감지 모두 그대로) 밀린 배너는 사라지지 않고 다음에 뜬다.
    enum TopBanner {
        /// 12시간 확인 — 무응답 30분이면 자동 마감되므로 가장 급하다.
        case longSession
        /// 자리 비움 자동 마감 되돌리기(유예 10분).
        case undoAutoClose
        /// 자리 비움/잠자기로 자동 마감된 근무를 **서버 창(6시간) 안에** 이어 붙이기.
        /// undoAutoClose 보다 뒤인 이유는 순전히 유예 길이다(저쪽은 10분, 이쪽은 6시간).
        /// 회고·새 버전보다 앞인 이유는 이쪽만 **놓치면 시간이 영구 소실**되기 때문이다.
        case awayRestore
        /// 지난주 회고 안내(주 1회).
        case retro
        /// 새 버전 안내(상시라 가장 덜 급하다).
        case update
    }

    /// 배너 1개가 차지하는 대략 높이(pt, 바깥 VStack spacing 10 포함). 목록 행수 예산 계산 전용 상수로,
    /// ImageRenderer 실측(340pt 폭)에 맞춰 둔다 — 값이 어긋나면 상한 회귀 테스트가 먼저 잡는다.
    static let inlineBannerHeight: CGFloat = 54
    /// 새 버전 배너의 노트 없는 기본 높이(pt).
    static let updateBannerHeight: CGFloat = 81
    /// 패치노트 한 줄이 배너를 늘리는 높이(pt, 줄 간격 포함). 첫 줄은 블록 간격까지 더해 조금 더 든다.
    static let updateNoteLineHeight: CGFloat = 15
    static let updateNoteBlockPadding: CGFloat = 8
    static let longSessionBannerHeight: CGFloat = 92
    /// 자리 비움 복원 배너 높이(pt). 보조줄(되살릴 분량)이 한 줄 붙어 인라인 배너보다 높다 —
    /// 그 줄이 "얼마를 잃는지"를 말해 주는 유일한 자리라, 높이를 아끼자고 지우면 배너가 그냥 잔소리가 된다.
    static let awayRestoreBannerHeight: CGFloat = 56
    /// 토큰 소모량 행 높이(pt, spacing 포함).
    static let tokenUsageRowHeight: CGFloat = 53
    /// 헤더 주간 목표 편집 인라인 행 높이(pt). 배너는 아니지만 헤더를 그만큼 부풀리므로 같은 예산에 넣는다.
    static let goalEditorHeight: CGFloat = 92

    /// 로그인 + 소속 팀 확정 상태(헤더 카드/팀 카드가 그려지는 메인 화면). 배너 후보 판정에 쓴다.
    private var isMainScreen: Bool {
        store.isSignedIn && !store.isTeamless
    }

    /// 이번 렌더에서 실제로 그릴 배너 하나(없으면 nil). 위에서부터 급한 순서다.
    /// 유예형 배너는 store.timedBanner **상태**만 읽는다 — 여기서 canUndoAutoClose 를 직접 부르면 인자로 줄
    /// 시각이 매초 갱신되는 store.displayNow 뿐이라, body 최상단인 이 프로퍼티가 displayNow 를 관찰 등록해
    /// 팝오버 전체 서브트리가 매초 무효화된다(잎 뷰 격리 불변식 위반 — 회귀 지점).
    /// 만료 판정은 스토어의 티커/상태 전이가 refreshTimedBanner 로 밀어 넣는다.
    private var topBanner: TopBanner? {
        if isMainScreen, showsLongSessionBanner { return .longSession }
        if isMainScreen, store.timedBanner == .undoAutoClose { return .undoAutoClose }
        // 근무 중에도 뜬다(다른 배너와 다른 점). 복귀 → 자동 시작이 새 세션을 연 **바로 그 상태**가
        // 복원의 정상 경로이기 때문이다 — 여기서 '근무 중이면 감춘다'로 두면 돌아온 사람 대부분이
        // 배너를 영영 못 본다(서버 RPC 가 새 세션을 지우고 옛 세션을 되살리는 것이 설계다).
        if isMainScreen, AwayRestoreBannerCopy.isWindowOpen(store.restorableAwaySession) { return .awayRestore }
        if store.isSignedIn, store.showsRetroBanner { return .retro }
        if showsUpdateBanner { return .update }
        return nil
    }

    private var topBannerHeight: CGFloat {
        switch topBanner {
        case .longSession: return Self.longSessionBannerHeight
        case .undoAutoClose, .retro: return Self.inlineBannerHeight
        case .awayRestore: return Self.awayRestoreBannerHeight
        case .update:
            // 노트가 있으면 줄 수만큼 배너가 자란다(없으면 예전과 같은 높이 — 목록 행수 예산도 그대로).
            let notes = updateBannerNotes
            guard !notes.isEmpty else { return Self.updateBannerHeight }
            return Self.updateBannerHeight + Self.updateNoteBlockPadding + CGFloat(notes.count) * Self.updateNoteLineHeight
        case nil: return 0
        }
    }

    /// 하위 패널(리그/토큰/찌르기/개인 기록/울트라)이 열려 있는지. 열려 있으면 팀 카드 자리를 그 패널이 대신 쓴다.
    ///
    /// ★ 새 패널을 만들면 **여기 더하는 것을 잊지 마라.** 빠뜨리면 토큰 소모량 행이 패널과 함께 그려져
    ///   창이 700pt 상한을 넘고 푸터(로그아웃/앱 종료)가 화면 밖으로 잘린다 — 그 순간 사용자는
    ///   로그아웃할 방법을 잃는다. 이 목록의 원소 수는 스토어의 isXxxVisible 플래그 수와 같아야 한다.
    private var isSubPanelOpen: Bool {
        store.isLeaderboardVisible || store.isTokenBoardVisible || store.isPokePanelVisible
            || store.isInsightsPanelVisible || store.isUltraPanelVisible
    }

    /// 토큰 소모량 행은 홈(팀 목록) 화면의 구성요소다 — 하위 패널이 열리면 감춘다. 패널이 쓸 세로 공간을
    /// 되찾아 창 높이 상한을 지키고, 패널 안에서 이 행이 할 일도 없다(패널마다 뒤로 버튼이 있다).
    private var showsTokenUsageRow: Bool {
        !isSubPanelOpen
    }

    /// 목록 위쪽에서 선택적으로 자리를 먹는 높이(배너 1개 + 토큰 소모량 행). 목록 패널은 이만큼 무스크롤
    /// 표시 행수를 줄여, 어떤 조합에서도 창이 상한을 넘지 않게 한다(줄어든 행은 스크롤로 밀릴 뿐 사라지지 않는다).
    private var listExtraChromeHeight: CGFloat {
        // 소모량이 0이어도 같은 높이의 순위판 진입 행(CheckTokenUsageRow.boardEntryRow)이 그려지므로
        // 사용량 유무로 갈라 세지 않는다 — 예전 조건을 그대로 뒀다면 그 행이 예산에 안 잡혀 팀원이 많은
        // 계정에서 목록이 한 행 더 남고 창이 상한을 넘었다.
        let tokenRow = showsTokenUsageRow ? Self.tokenUsageRowHeight : 0
        let goalEditor = (store.isEditingWeeklyGoal || previewGoalEditing) ? Self.goalEditorHeight : 0
        return topBannerHeight + tokenRow + goalEditor
    }

    // 배너 표시용 버전 문자열("v" 접두 정규화). 실 감지가 없으면(미리보기) 폴백 버전으로 렌더한다.
    private var updateBannerVersionText: String {
        let raw = updateCheck?.latestVersion ?? "v0.3.0"
        return (raw.hasPrefix("v") || raw.hasPrefix("V")) ? raw : "v\(raw)"
    }

    // 배너에 얹을 패치노트 줄(최신 릴리스 노트 파싱본). 감지가 없거나 노트 없는 옛 릴리스면 빈 배열 →
    // 배너는 노트 줄 없이 예전 모습 그대로 그려진다(회귀 금지). 스냅샷은 previewUpdateNotes 로 주입한다.
    private var updateBannerNotes: [String] {
        let fetched = updateCheck?.latestNotes ?? []
        return fetched.isEmpty ? previewUpdateNotes : fetched
    }

    var body: some View {
        VStack(spacing: 10) {
            // 팝오버 최상단: 새 버전 안내 배너([지금 업데이트] 원클릭 + [명령 복사] 폴백). HeaderCard 위에 얹는다.
            // 더 급한 배너가 있으면 이번 팝오버에서는 양보한다(topBanner — 배너는 한 번에 하나만).
            if topBanner == .update {
                UpdateBanner(versionText: updateBannerVersionText, notes: updateBannerNotes)
            }
            // 그 아래: 지난주 회고 안내 배너(주당 1회, 월요일 첫 팝오버). [보기]로 개인 기록 패널을 열고,
            // X 로 닫으면 이번 주는 다시 뜨지 않는다(markRetroBannerSeen 이 주 키를 기록).
            if topBanner == .retro {
                InlineActionBanner(
                    icon: "calendar.badge.clock",
                    title: "지난주 근무 기록이 준비됐어요",
                    actionTitle: "보기",
                    tint: CheckTheme.accent,
                    // 토글이 아니라 '열기'다 — 이미 개인 기록을 보고 있는데 [보기]가 패널을 닫아 버리면 안 된다.
                    action: { store.openInsightsPanel() },
                    onDismiss: { store.markRetroBannerSeen() }
                )
                // 실제로 그려진 순간 이번 주 몫을 소비한다 — 판정 시점이 아니라 표시 시점이라, 더 급한 배너에
                // 밀려 뜨지도 못한 팝오버에서는 소비되지 않는다. 이걸로 회고 배너가 팝오버를 열 때마다 되살아나
                // 새 버전 안내 배너를 그 주 내내 가리던 문제가 사라진다.
                .onAppear { store.markRetroBannerDisplayed() }
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
                // 토큰 사용량 갱신 루프를 팝오버 표시 동안만 돌린다(즉시 1회 + 120초 주기 = TokenUsageStore.refreshPeriod, 뷰 사라지면 자동 취소).
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
                    // 12시간 확인 배너는 헤더 카드 **위쪽 형제**다. 예전엔 카드 overlay 라 '근무 종료' 버튼을 통째로
                    // 가려 배너가 뜬 동안 퇴근을 못 했다. 카드 높이 변화(창 튐)는 감수한다 — 배너는 드물게 뜬다.
                    if topBanner == .longSession {
                        LongSessionBanner(
                            onConfirm: { store.confirmStillWorking() },
                            onStopNow: { store.stop() }
                        )
                    }
                    HeaderCard(
                        store: store,
                        previewGoalEditing: previewGoalEditing
                    )
                    // 자리 비움 자동 마감 되돌리기 — 자동 마감 직후 유예(10분) 안이고 아직 비근무일 때만 뜬다.
                    // 근무를 다시 시작하면 즉시 사라지고(옛 세션으로 현 세션을 덮어쓸 수 없다), X 로 직접 닫을 수도 있다.
                    if topBanner == .undoAutoClose {
                        InlineActionBanner(
                            icon: "arrow.uturn.backward.circle.fill",
                            title: "자리 비움으로 근무를 종료했어요",
                            actionTitle: "되돌리기",
                            tint: CheckTheme.pending,
                            action: { _ = store.undoAutoClose() },
                            onDismiss: { store.clearAutoCloseUndo() }
                        )
                    }
                    // 자리 비움/잠자기로 끊긴 근무를 이어 붙이는 배너. **닫기(X)를 달지 않았다** — 이 배너를
                    // 놓치면 서버 창(6시간)이 닫히면서 그 시간이 영구 소실되는데, X 는 "실수로 눌러 영구
                    // 소실"이라는 경로를 하나 더 만들 뿐 되찾아 주는 것이 없다. 창이 닫히거나 복원이
                    // 끝나면 서버가 대상을 내려 주고(polling) 배너는 스스로 사라진다.
                    if topBanner == .awayRestore, let restorable = store.restorableAwaySession {
                        InlineActionBanner(
                            icon: AwayRestoreBannerCopy.icon,
                            title: AwayRestoreBannerCopy.title,
                            subtitle: AwayRestoreBannerCopy.subtitle(for: restorable),
                            actionTitle: AwayRestoreBannerCopy.actionTitle(isRestoring: store.isRestoringAwaySession),
                            tint: CheckTheme.pending,
                            // 원자 RPC 한 번. 연타 가드는 스토어가 갖고 있다(isRestoringAwaySession).
                            action: { _ = store.restoreAwaySession() }
                        )
                    }
                    // 토큰 소모량 행은 내 근무 박스와 팀원 현황 사이(사용자 지정 위치). 탭하면 순위 페이지.
                    // 하위 패널이 열려 있으면 감춘다 — 그 자리는 패널이 쓰고, 창 높이 상한도 그만큼 여유가 생긴다.
                    if showsTokenUsageRow {
                        CheckTokenUsageRow(store: store.tokenUsage, onOpenBoard: { store.toggleTokenBoard() })
                    }
                    if store.isLeaderboardVisible {
                        LeaderboardPanel(
                            // 원본 leaderboard 는 스토어에 보존하고, 표시 시점에 0시간 타팀만 숨긴다(내 팀은 0이어도 유지).
                            entries: store.leaderboard.filteredForDisplay(myTeamID: store.currentTeamID),
                            myTeamID: store.currentTeamID,
                            fallbackStatus: store.syncMessage,
                            unfilteredCount: store.leaderboard.count,
                            onBack: { store.isLeaderboardVisible = false },
                            extraChromeHeight: listExtraChromeHeight,
                            clipsOverflowInsteadOfScroll: previewClipsOverflowList
                        )
                    } else if store.isTokenBoardVisible {
                        // AI 토큰 순위 페이지(앱 사용자 전체 공개). 리그와 같은 뼈대(뒤로 + 제목 + 고정 행높이 리스트/스크롤).
                        // 제목 좌우 ‹ › 로 과거 달을 볼 수 있다(미래 불가). 공개/비공개 **전환**은 설정 창이 가져갔고,
                        // 여기 남는 것은 그 결과(내 행의 "비공개" 칩)뿐이다 — isMyUsagePublic 은 계속 넘긴다.
                        TokenBoardPanel(
                            entries: store.tokenBoard,
                            myUserID: store.session?.userID,
                            hasLoaded: store.tokenBoardLoaded,
                            isLoading: store.tokenBoardLoading,
                            // 실패는 '진행중'과 다른 문구 + [다시 시도] 로 갈라 준다 — 본문 자리에 동기화 문구 금지.
                            hasFailed: store.tokenBoardFailed,
                            onRetry: { store.loadTokenBoard() },
                            fallbackStatus: store.syncMessage,
                            month: store.tokenBoardMonth,
                            canStepForward: TokenBoardMonthNavigator.canStepForward(from: store.tokenBoardMonth),
                            onStepMonth: { store.stepTokenBoardMonth(by: $0) },
                            isMyUsagePublic: store.tokenUsagePublic,
                            // 뒤로도 토글과 같은 닫기 경로를 타야 보던 과거 달이 남지 않는다(다음에 열면 늘 이번 달).
                            onBack: { store.closeTokenBoard() },
                            extraChromeHeight: listExtraChromeHeight,
                            clipsOverflowInsteadOfScroll: previewClipsOverflowList
                        )
                    } else if store.isPokePanelVisible {
                        // 콕찌르기 페이지(앱 사용자 전체 목록). 리그/토큰 보드와 같은 뼈대. store 값을 값+클로저로만 넘겨
                        // PokePanel 을 렌더 테스트 친화적으로 유지한다.
                        //
                        // ★ 초 단위 시계(displayNow)는 **여기서 값으로 읽지 않는다.** 아래 네 클로저(clock/cooldownRemaining/
                        //   isPokeDisconnected/messageCooldownRemaining)가 store.menuClockNow 를 읽는데, 그 읽기는 클로저를
                        //   **부르는 뷰**의 body 에 관찰 등록된다 — 패널은 그것들을 MenuClockLeaf 안에서만 부르므로 매초
                        //   다시 그리는 것은 쿨타임 버튼·작성기 카운트다운·수신 시각·안내줄뿐이다.
                        //   v0.2.37 까지는 `now: store.displayNow` 한 줄과 행마다 값으로 푼 쿨타임 클로저가 팝오버 루트를
                        //   매초 무효화해, 찔림 패널을 마지막으로 보고 닫은 뒤 유휴 CPU 가 2.9%→4.5% 로 올랐다
                        //   (V0238MenuTests 가 루트·패널의 displayNow 무관찰을 못 박는다).
                        PokePanel(
                            entries: store.pokeDirectory,
                            isMyselfWorking: store.snapshot.isWorking,
                            hasLoaded: store.pokeDirectoryLoaded,
                            fallbackStatus: store.syncMessage,
                            notice: store.pokeNotice,
                            clock: { store.menuClockNow },
                            cooldownRemaining: { store.pokeCooldownRemaining(for: $0, now: store.menuClockNow) },
                            onPoke: { store.sendPoke(to: $0) },
                            onUltra: { store.sendUltraPoke(to: $0) },
                            // 울트라 **잔량**(재화). nil = 아직 모름 → 배지는 자리를 지킨 채 숫자만 비운다.
                            // 표시 전용이다 — 3초 홀드는 이 값과 무관하게 발사되고 판정은 서버가 한다.
                            ultraBalance: store.ultraBalance,
                            // 무제한(관리자)이면 배지가 숫자 대신 ∞ 를 그린다. **서버가 말해 준 사실**이고
                            // 클라는 role 을 보지 않는다 — 스토어가 응답의 깃발을 그대로 나른다.
                            ultraUnlimited: store.ultraUnlimited,
                            // 배지 탭 → 울트라 화면. **콕찌르기를 '봤다'로 소비하지 않는다**(openUltraPanel 주석).
                            onOpenUltraPanel: { store.openUltraPanel(from: .poke) },
                            // 수신 연결이 죽었다는 사실은 안내줄 최우선 가지다. 판정은 순수 함수 한 곳뿐이고
                            // 출시 기본값 .idle(.disabled) 에서는 언제나 false 다. 판정이 시계를 읽으므로(재연결 유예)
                            // 값이 아니라 클로저로 넘긴다 — 안내줄 잎이 부른다.
                            isPokeDisconnected: {
                                PokeConnectionNotice.shouldWarn(state: store.realtimeState, now: store.menuClockNow)
                            },
                            isFocusMode: store.focusMode,
                            onToggleFocusMode: { store.toggleFocusMode() },
                            // 3글자 메시지 — 찌르기와 같은 표·같은 폴링을 타지만 RPC·쿨타임·결과 문구는 각자의 것이다.
                            onSendMessage: { store.sendMessage(to: $0, body: $1) },
                            messageCooldownRemaining: { store.messageCooldownRemaining(for: $0, now: store.menuClockNow) },
                            isSendingMessage: store.isSendingMessage,
                            messageNotice: store.messageNotice,
                            // 큐의 맨 앞 = 아직 사용자에게 보여 주지 않은 가장 오래된 1건.
                            // ⚠︎ 말풍선(오버레이 담당)이 consumeCurrentMessage 로 큐를 밀면 이 자리도 함께 비워진다.
                            latestMessage: store.currentMessage,
                            waitingMessageCount: store.waitingMessageCount,
                            previewComposingUserID: previewMessageComposerUserID,
                            previewMessageDraft: previewMessageDraft,
                            onBack: { store.togglePokePanel() },
                            extraChromeHeight: listExtraChromeHeight,
                            clipsOverflowInsteadOfScroll: previewClipsOverflowList
                        )
                    } else if store.isUltraPanelVisible {
                        // 울트라 화면(잔량 + 충전 경로). 리그/토큰/찌르기/내 기록과 **같은 뼈대**다.
                        UltraPanel(
                            balance: store.ultraBalance,
                            isUnlimited: store.ultraUnlimited,
                            missions: store.missions,
                            hasLoaded: store.missionsLoaded,
                            hasFailed: store.ultraBalanceFailed,
                            notice: store.missionNotice,
                            onRetry: { store.syncUltraWallet(reason: .panelOpen) },
                            extraChromeHeight: listExtraChromeHeight,
                            clipsOverflowInsteadOfScroll: previewClipsOverflowList,
                            onBack: { store.closeUltraPanel() }
                        )
                    } else if store.isInsightsPanelVisible {
                        // 개인 기록 페이지(지난주 회고 + 근무 리듬 히트맵). 내 데이터만 쓰고, 계산은 전부
                        // CheckWorkInsights 순수 함수가 끝낸 뒤라 이 패널은 값만 그린다(렌더 테스트 친화적).
                        InsightsPanel(
                            heatmap: store.heatmap,
                            retro: store.retro,
                            dailyGrid: store.dailyGrid,
                            hasLoaded: store.insightsLoaded,
                            // 실패는 '진행중'과 다른 문구 + [다시 시도] 로 갈라 준다(패널 안에서 재시도 가능).
                            hasFailed: store.insightsFailed,
                            onRetry: { store.loadInsights() },
                            // 행 기반이 아니라 줄일 행이 없는 패널이라, 같은 예산을 받아 본문 높이를 잘라 스크롤로 넘긴다.
                            extraChromeHeight: listExtraChromeHeight,
                            clipsOverflowInsteadOfScroll: previewClipsOverflowList,
                            onBack: { store.toggleInsightsPanel() }
                        )
                    } else {
                        // store 를 통째로 내려보내 초단위(displayNow) 의존을 잎 뷰로 격리한다 — TeamPanel 본체는
                        // displayNow 를 읽지 않으므로 매초 재정렬/재계산이 사라진다.
                        TeamPanel(
                            store: store,
                            previewCodeRevealed: previewOwnerCodeRevealed,
                            extraChromeHeight: listExtraChromeHeight,
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
    // 아이콘 판정용 스냅샷(상태/대기/자리비움). 텍스트는 스토어가 계산해 둔 파생 저장값(menuBarTitle)을 쓴다.
    let snapshot: WorkStatusSnapshot
    // 상단바에 표시할 라벨 텍스트. 스토어가 == 가드와 함께 갱신하므로 여기선 그리기만 한다(매초 재계산 없음).
    let title: String

    var body: some View {
        HStack(spacing: 5) {
            // 자리 비움일 때는 **마스코트를 쓰지 않는다.** 마스코트 표정은 neutral/negative 둘뿐이라
            // (CheckMascotAssets.Mood) 비근무면 항상 같은 시무룩 얼굴이 나오고, 그 얼굴은 평범한 '오프'와
            // 픽셀 하나 다르지 않다 — 캐릭터를 켠 사람의 메뉴바에서는 자리 비움이 통째로 안 보이게 된다.
            // 이 자리에서만 심볼로 갈아 끼우면 글자(자리비움)와 그림이 함께 달라져, 마스코트 유무와 무관하게
            // "평소와 다르다"가 반드시 눈에 걸린다(새 이미지 에셋 없이).
            if let mascot = CheckMascotAssets.menuBarImage(for: snapshot), !snapshot.isAwayRestorable {
                // 이미 18×18pt로 크기를 지정한 이미지라 .resizable()/.frame() 불필요.
                // MenuBarExtra 라벨이 intrinsic size를 써도 바 높이 안에 온전히 들어간다.
                Image(nsImage: mascot)
            } else {
                Image(systemName: MenuBarStatusFormatter.symbolName(for: snapshot))
                    .symbolRenderingMode(.hierarchical)
                    .imageScale(.medium)
            }
            Text(MenuBarStatusFormatter.displayTitle(stored: title, snapshot: snapshot))
                .font(.system(.body, design: .rounded).weight(.medium))
                .monospacedDigit()
        }
    }
}

// MARK: - 자리 비움 복원 배너 문구 (순수 계산 — 결정적 검증 지점)

/// 자리 비움/잠자기 자동 마감을 이어 붙이는 배너의 문구와 표시 조건.
///
/// 뷰에서 분리한 이유는 둘이다: (1) 문구는 픽셀 없이 검증할 수 있어야 하고, (2) **표시 조건이 시계를
/// 읽지 않아야 한다.** 만료 판정을 여기서 `Date()` 로 하면 배너 조건이 매초 갱신되는 값에 묶여
/// 팝오버 서브트리 전체가 초당 한 번 무효화된다(잎 뷰 격리 불변식 위반). 창 판정은 서버가 하고
/// (docs/away-close.md 5절) 클라는 서버가 준 잔여 초만 본다.
enum AwayRestoreBannerCopy {
    static let icon = "moon.zzz.fill"
    /// 사유(away/sleep)를 문구로 가르지 않는다 — 사람에게는 둘 다 "자리를 비운 사이"이고,
    /// 가르는 순간 잠자기 마감이 '내 잘못'처럼 읽힌다.
    static let title = "자리 비운 사이 근무가 끝났어요"

    /// 서버가 아직 되살릴 수 있다고 말한 대상인가. `remainingSeconds <= 0` 은 이미 만료다.
    static func isWindowOpen(_ session: AwayRestorableSession?) -> Bool {
        guard let session else { return false }
        return session.remainingSeconds > 0
    }

    /// 되살릴 수 있는 **분량**. 잔여 창 시간이 아니라 잃은 근무 시간을 쓴다 — 사람을 움직이는 숫자는
    /// "언제까지"가 아니라 "얼마"이고, 잔여 창은 폴링마다 줄어들어 같은 배너가 30초마다 다른 글자가 된다.
    static func subtitle(for session: AwayRestorableSession) -> String? {
        guard let started = session.startedAt, let ended = session.endedAt else { return nil }
        let seconds = Int(ended.timeIntervalSince(started))
        guard seconds > 0 else { return nil }
        return "\(MenuBarStatusFormatter.hoursMinutes(seconds)) 되살릴 수 있어요"
    }

    /// 왕복 중에는 문구로 진행을 알린다(버튼을 지우지 않는다 — 사라지면 눌린 건지 알 수 없다).
    /// 연타는 스토어의 `isRestoringAwaySession` 가드가 막으므로 여기서 비활성으로 만들 필요가 없다.
    static func actionTitle(isRestoring: Bool) -> String {
        isRestoring ? "이어붙이는 중" : "이어붙이기"
    }
}

// MARK: - Update banner (새 버전 안내 + 원클릭/명령 복사)

/// 팝오버 최상단 슬림 배너(accent 톤). 새 버전을 안내하고 [지금 업데이트] 원클릭 + [명령 복사] 폴백을 제공한다.
/// 원클릭은 UpdateRunner 로 분리 프로세스를 띄우며, running 중엔 "업데이트 중…"으로 바뀌고 [지금 업데이트]가 비활성된다.
/// brew 미탐지(unavailable)/스폰 실패(failed) 시 명령 복사 폴백 안내 줄을 노출한다. 복사 문자열은 정확히 `brew upgrade aing-check`.
private struct UpdateBanner: View {
    /// 표시용 버전 문자열("v0.3.0" — 상위에서 "v" 정규화).
    let versionText: String
    /// 이번 버전 패치노트(평문 줄, 최대 4). 비어 있으면 노트 줄 없이 예전 모습 그대로 그린다.
    let notes: [String]
    // runner 는 이 배너가 소유한다(AppDelegate 배선 불요). 테스트는 상태/스폰을 주입한 runner 를 넘겨 검증한다.
    @State private var runner: UpdateRunner
    @State private var copied = false

    init(versionText: String, notes: [String] = [], runner: UpdateRunner = UpdateRunner()) {
        self.versionText = versionText
        self.notes = notes
        _runner = State(initialValue: runner)
    }

    // 실행 실패/미탐지 시에만 폴백 안내를 띄운다(정상 경로는 군더더기 없이 두 버튼만).
    private var fallbackHint: String? {
        switch runner.status {
        case .unavailable: return "brew를 찾지 못했어요 — 아래 명령을 복사해 실행하세요"
        // failed 는 두 경우다: 스폰 자체가 실패했거나, 명령은 떴는데 시한 안에 업데이트가 일어나지 않았거나.
        // 후자가 훨씬 흔하므로(낡은 탭·권한 등) 원인을 단정하지 않는 문구를 쓴다.
        case .failed: return "업데이트가 진행되지 않았어요 — 아래 명령을 복사해 실행하세요"
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
            // 이번 버전에서 뭐가 바뀌었는지 — 제목과 버튼 사이 작은 목록. 왜 업데이트하는지 알 수 있게 한다.
            // 한 줄씩 말줄임(lineLimit 1)이라 문구가 길어도 배너 높이는 줄 수에 비례해 예측 가능하다.
            if !notes.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    // 같은 문구가 두 줄일 수 있으므로 값이 아니라 순번으로 식별한다.
                    ForEach(Array(notes.enumerated()), id: \.offset) { _, note in
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text("·")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(CheckTheme.secondaryText)
                            Text(note)
                                .font(.caption2)
                                .foregroundStyle(CheckTheme.secondaryText)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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
    // 렌더 스냅샷 전용: 헤더 주간 목표 편집 행을 펼친 채로 그린다. 앱에서는 항상 false(연필 버튼 토글).
    var previewGoalEditing: Bool = false

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
                // 팝오버가 열리면 이 버튼이 첫 포커스를 받아 macOS 키보드 포커스 링(파란 테두리 + 후광)이
                // 주황 알약 둘레에 그려진다 — 사장님 신고. 알약은 자기 테두리·그림자를 이미 갖고 있어
                // 그 링이 디자인 결함처럼 읽힌다.
                //
                // **여기(호출 자리)에 거는 이유**: 이 수식어는 걸린 자리와 그 **하위 전체**의 포커스 표시를 끈다.
                // 팝오버 루트나 상위 컨테이너에 걸면 로그인 이메일/비밀번호·재설정 코드·할 일·3글자 메시지
                // 입력칸의 커서 표시까지 함께 죽어, 지금 어디에 타이핑되는지 알 수 없는 화면이 된다.
                // 이 한 줄이 딱 이 버튼 하나만 덮는다.
                //
                // focusable(false) 를 쓰지 않는 이유: 그건 표시가 아니라 **도달**을 막아 키보드만 쓰는 사람에게서
                // 근무 시작/종료 자체를 빼앗는다. 링만 지우고 조작은 남기는 쪽이 맞다.
                .focusEffectDisabled()
            }
            // 내 주간 목표 진행 바 — 목표는 개인 약속이므로 "내" 접두어 없이 위치(내 박스)가 의미를 말한다.
            // myLiveWeeklySeconds(displayNow 파생)를 읽으므로 잎 뷰로 격리해 헤더 본체가 매초 무효화되지 않게 한다.
            HeaderGoalSection(store: store, previewGoalEditing: previewGoalEditing)
        }
        .padding(12)
        .panelStyle()
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

    // 연필 버튼으로 토글하는 목표 편집 인라인 노출 상태. 스토어가 소유한다 — 이 행이 헤더를 90pt 넘게 부풀려
    // 창 높이 예산(CheckMenuView.listExtraChromeHeight)이 반드시 봐야 하기 때문이다. 스냅샷은 previewGoalEditing 로 강제한다.
    private var isEditingGoal: Bool { store.isEditingWeeklyGoal || previewGoalEditing }
    // 편집 중 스테퍼가 바인딩하는 목표시간(시간 단위). 편집을 여는 순간 현재 목표로 초기화한다.
    @State private var editingHours: Int

    init(store: WorkTimerStore, previewGoalEditing: Bool = false) {
        self.store = store
        self.previewGoalEditing = previewGoalEditing
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
                    // 설정 창 진입점. 팝오버에서 설정에 닿는 **유일하게 눈에 보이는 길**이다
                    // (⌘, 는 이미 있지만 아무 데도 적혀 있지 않다 — 앱 메뉴가 없는 LSUIElement 앱이라
                    //  단축키를 알려 줄 자리 자체가 없다). 이전 진입점이던 전원 버튼 롱프레스는
                    //  "설정을 보려고 누르면 앱이 꺼지는" 자리였고, 실제로 아무도 못 찾았다.
                    //
                    // 왜 여기인가(다른 두 후보를 재 보고 고른 자리다):
                    //  · 푸터 — 4버튼이 상한이다(FooterWidthBudget). 다섯 번째를 세우면 동기화 문구 슬롯이
                    //    125→90pt 로 줄어 "소속된 팀이 없어요…"(176pt)가 축소로도 안 들어가 말줄임된다.
                    //  · 팀 카드 헤더 — 네 번째 버튼이면 팀 이름 폭이 85→50pt(8자→5자)로 잘린다
                    //    (TeamHeaderWidthBudget — "아잉체크 개발팀"이 "아잉체…"가 된다).
                    // 남는 곳이 이 캡션 행이고, 그건 위 두 예산이 **스스로 지정한 넘침 자리**다.
                    // 마침 여기 있던 할 일 토글이 설정 창으로 옮겨 갔으므로 버튼 수는 3개 그대로다 —
                    // 캡션 여유(실측 122px)와 창 높이 예산(700pt 상한)이 1pt 도 움직이지 않는다.
                    //
                    // 자리는 그래프/연필의 **왼쪽**이다: 오른쪽 끝부터 세는 손버릇(끝=연필, 끝에서 둘째=내 기록)을
                    // 건드리지 않아야, 목표를 고치려다 설정 창을 여는 오클릭이 생기지 않는다.
                    //
                    // isActive 를 쓰지 않는다(기본값 false). 이 행의 accent 는 "지금 켜져 있다"는 뜻인데
                    // 설정 창은 팝오버 **밖**에 사는 별도 창이고, 그 창을 여는 순간 앱이 활성화되며
                    // MenuBarExtra 팝오버는 닫힌다 — 켜짐을 비출 관찰 대상도, 그걸 볼 화면도 없다.
                    // 여기서 컨트롤러의 isOpen(비관찰 값)을 읽으면 갱신되지 않는 색만 하나 늘어난다.
                    HeaderCaptionIconButton(
                        icon: "gearshape.fill",
                        help: "설정 — 자동 실행 · 할 일 · 별명 · 토큰 공개"
                    ) {
                        CheckSettingsWindowController.shared.show()
                    }
                    // 내 기록(지난주 회고 + 근무 리듬 히트맵). 팀 카드 헤더가 아니라 **내 근무 박스**에 둔다 —
                    // 본인 데이터만 보는 개인 화면이라 자리가 여기가 맞고, 팀 헤더에 네 번째 버튼을 세우면
                    // 팀 이름이 2~3자로 잘렸다(v0.2.11 감사 지적). 캡션 행이라 연필과 같은 소형(18pt) 버튼을 쓴다.
                    HeaderCaptionIconButton(
                        icon: "chart.xyaxis.line",
                        help: "내 기록",
                        isActive: store.isInsightsPanelVisible
                    ) {
                        store.toggleInsightsPanel()
                    }
                    // 주간 목표는 팀원 누구나 바꿀 수 있다 — 캡션 % 옆 작은 연필로 편집 행을 연다.
                    // 표준 IconButton(27pt)은 caption2 행 높이를 홀로 키워 캡션 줄 간격이 어색해지므로,
                    // 캡션 높이에 맞춘 소형(18pt) 버튼을 쓴다.
                    HeaderCaptionIconButton(icon: "pencil", help: "주간 목표 수정", isActive: isEditingGoal) {
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
        store.isEditingWeeklyGoal.toggle()
    }

    // 저장 성공 시에만 편집 행을 닫는다(실패 시 입력값을 유지해 바로 재시도할 수 있게 한다).
    private func saveGoal() {
        let hours = editingHours
        Task { @MainActor in
            if await store.updateTeamGoal(hours: hours) {
                store.isEditingWeeklyGoal = false
            }
        }
    }

    // 초 단위 목표를 스테퍼 범위(1~168시간)로 클램프한 시간값.
    private static func hours(from goalSeconds: Int) -> Int {
        max(1, min(168, goalSeconds / 3600))
    }
}

// 여기 있던 `TodoToggleControl`(할 일 on/off 버튼의 아이콘·문구·동작 계약)은 v0.2.32 에 사라졌다.
// 스위치가 설정 창(`CheckSettingsView` — "캐릭터를 눌러 할 일 열기")으로 이사하면서 팝오버 호출부가
// 0이 됐고, 그쪽은 토글이라 press(toggle) 가 아니라 `store.setTodoEnabled(_:)` 를 직접 쓴다.
// 그 문구가 지켜야 할 것(껐을 때 캐릭터가 어떻게 되는지를 말할 것 · 내부 용어 "아파하기"를 사용자
// 문구로 새어 보내지 말 것)은 사라지지 않았다 — 설정 창 소스를 읽는
// `todoSwitchWordingStillCoversBothStatesAtItsNewHome`(CheckMenuRenderTests) 이 이어받았다.

/// 헤더 목표 캡션 행 전용 소형 아이콘 버튼(18pt). 캡션(caption2) 행 높이를 키우지 않으면서 hover 배경과
/// 툴팁으로 버튼임을 드러낸다 — 표준 IconButton(27pt)을 쓰면 이 행만 세로로 부풀어 배치가 어색해진다.
/// 목표 수정(연필)과 내 기록(그래프)이 같은 행에 나란히 서므로 아이콘/툴팁만 갈아 끼우는 공용 버튼으로 둔다.
private struct HeaderCaptionIconButton: View {
    let icon: String
    let help: String
    /// accent 로 물들일지. 이 행에서 accent 는 **"지금 켜져 있다"**는 뜻이므로, 상태가 없는 단순 진입
    /// 버튼(설정 창 열기)은 기본값(false)을 그대로 쓴다 — 늘 켜진 색은 상태 신호를 죽인다.
    var isActive: Bool = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
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
        .help(help)
    }
}

// MARK: - Team card

/// 목록 패널의 '스크롤 없이 보여 주는 최대 행수'를, 목록 위쪽 선택 요소(배너 1개 + 토큰 소모량 행)가 먹은
/// 높이만큼 줄이는 공용 계산(순수 함수 — 결정적 검증 지점).
///
/// 팝오버 창은 위 모서리가 메뉴바 아래에 고정돼 아래로만 자란다(CheckWindowAnchor). 그래서 상한(700pt)을
/// 넘긴 만큼은 화면 아래로 잘려 푸터(로그아웃/앱 종료)와 패널 하단에 손이 닿지 않는다. 각 패널의 기본 상한
/// (maxVisibleRows)은 '배너도 토큰 행도 없는 상태'로 맞춰 둔 값이라, 그 위에 무언가 얹히면 얹힌 높이를
/// 행 단위로 환산해 그만큼 목록을 줄이는 것이 유일한 레버다 — 줄어든 행은 사라지지 않고 스크롤로 밀린다.
enum ListRowBudget {
    /// 아무리 좁아도 이 행수는 남긴다(목록이 목록으로 보이도록).
    static let minVisibleRows = 2

    static func visibleRows(
        maxVisibleRows: Int,
        rowHeight: CGFloat,
        rowSpacing: CGFloat,
        extraChromeHeight: CGFloat
    ) -> Int {
        guard extraChromeHeight > 0 else { return maxVisibleRows }
        let unit = rowHeight + rowSpacing
        guard unit > 0 else { return maxVisibleRows }
        // 올림: 한 행보다 작게 먹었어도 한 행은 양보해야 상한 안에 확실히 들어간다.
        let drop = Int((extraChromeHeight / unit).rounded(.up))
        return max(minVisibleRows, maxVisibleRows - drop)
    }
}

/// 팀 카드 헤더에서 팀 이름(Text)에 남는 유연 폭 예산(순수 계산 — 결정적 검증 지점).
///
/// 헤더는 `[팀 이름][Spacer][N명 근무중 칩][아이콘 버튼…]` 한 줄이고 팝오버 폭은 340 고정이다. 이름만 유연
/// 요소라, 오른쪽에 버튼을 하나 더할 때마다 이름이 27+8pt 씩 먼저 잘린다(lineLimit(1)). v0.2.11 초안이
/// 여기에 네 번째 버튼('내 기록')을 세워 "아잉체크 개발팀"이 "아잉…"으로 잘렸던 회귀를 상수로 못 박아 둔다.
enum TeamHeaderWidthBudget {
    /// 팝오버 340 - 바깥 padding 12*2 - 팀 카드 panelStyle padding 12*2.
    static let contentWidth: CGFloat = 340 - 12 * 2 - 12 * 2
    /// "N명 근무중" 칩의 대략 폭(두 자리 인원까지 여유 있게 본다).
    static let countChipWidth: CGFloat = 88
    /// IconButton 지름과 HStack 간격.
    static let iconButtonWidth: CGFloat = 27
    static let spacing: CGFloat = 8
    /// Spacer(minLength:).
    static let spacerMinWidth: CGFloat = 6
    /// subheadline(13pt) 볼드 한글 한 글자의 대략 폭.
    static let koreanGlyphWidth: CGFloat = 13
    /// minimumScaleFactor — 잘리기 전에 이 배율까지 줄여 본다.
    static let minimumScaleFactor: CGFloat = 0.75

    /// 아이콘 버튼 N개일 때 팀 이름에 남는 폭(pt).
    static func nameWidth(iconButtonCount: Int) -> CGFloat {
        let buttons = CGFloat(iconButtonCount) * iconButtonWidth
        // 간격 개수 = [이름][Spacer][칩][버튼…] 사이의 틈 = 버튼 수 + 1.
        let gaps = CGFloat(iconButtonCount + 1) * spacing
        return contentWidth - countChipWidth - buttons - gaps - spacerMinWidth
    }

    /// 그 폭에 말줄임 없이 들어가는 한글 글자 수(최소 축소 배율 반영).
    static func fittingKoreanGlyphs(iconButtonCount: Int) -> Int {
        let width = nameWidth(iconButtonCount: iconButtonCount)
        guard width > 0 else { return 0 }
        return Int(width / (koreanGlyphWidth * minimumScaleFactor))
    }
}

/// 팀원 행에서 이름(Text)에 남는 유연 폭 예산(순수 계산 — 결정적 검증 지점).
///
/// **실제 구조는 `[아바타][VStack{이름줄, 상세줄, 보조줄?}][Spacer][프레즌스 칩]` 이다**
/// (CheckComponents.swift TeamMemberRow). 이름은 상세줄과 같은 VStack 을 공유하므로 여기 계산하는 것은
/// 그 VStack 에 남는 폭이고, 이름줄은 그 안에서 편집 배지와 다시 나눠 쓴다. 별명 최대 길이(12자)를
/// 정한 근거가 바로 이 계산이므로, 배지를 더하거나 칩 문구를 늘리면 이 상수와 회귀 테스트를 함께 고친다.
enum MemberRowNameWidthBudget {
    /// 팝오버 340 - 바깥 padding 12*2 - 팀 카드 panelStyle padding 12*2 = 292.
    static let contentWidth: CGFloat = 340 - 12 * 2 - 12 * 2
    /// 아바타 지름. TeamMemberRow.textColumnInset 의 26 과 같은 값이다.
    static let avatarWidth: CGFloat = 26
    /// 같은 줄의 HStack(spacing: 10).
    static let hstackSpacing: CGFloat = 10
    /// Spacer(minLength: 6).
    static let spacerMinWidth: CGFloat = 6
    /// PresenceChip 최장 문구("연결 끊김") 기준 폭. **이 값을 바꿀 땐 PresenceChip 정의를 함께 본다.**
    static let presenceChipWidth: CGFloat = 73
    static let editBadgeWidth: CGFloat = 18
    static let editBadgeSpacing: CGFloat = 4
    /// subheadline(13pt) semibold 한글 한 글자의 대략 폭.
    static let koreanGlyphWidth: CGFloat = 13
    /// minimumScaleFactor — 말줄임보다 먼저 이 배율까지 줄여 본다(팀 헤더 0.75 와 같은 관례).
    static let minimumScaleFactor: CGFloat = 0.8

    static func nameWidth(hasEditBadge: Bool) -> CGFloat {
        let badge = hasEditBadge ? editBadgeWidth + editBadgeSpacing : 0
        return contentWidth - avatarWidth - hstackSpacing - badge - spacerMinWidth - presenceChipWidth
    }

    /// 그 폭에 말줄임 없이 들어가는 한글 글자 수(최소 축소 배율 반영).
    static func fittingKoreanGlyphs(hasEditBadge: Bool) -> Int {
        let width = nameWidth(hasEditBadge: hasEditBadge)
        guard width > 0 else { return 0 }
        return Int(width / (koreanGlyphWidth * minimumScaleFactor))
    }
}
// 실측 근거: 내 행(배지 있음) 292-26-10-22-6-73 = 155pt → 155/(13*0.8) = 14자 ≥ 12 ✓
//          남의 행(배지 없음) 292-26-10-6-73 = 177pt → 17자 ✓

private struct TeamPanel: View {
    // store 를 통째로 받아 대부분의 값을 파생 읽기한다. 초단위(displayNow) 의존은 잎 뷰로 격리하므로
    // 본체는 displayNow 를 읽지 않는다 — 매초 재정렬/재계산이 사라진다.
    // @Bindable 이 아니라 let 인 이유: 여기서 쓰던 유일한 쓰기 바인딩($store.displayNameDraft)이
    // 별명 편집과 함께 설정 창으로 옮겨 갔다. 읽기만 하는 지금은 @Bindable 이 붙을 자리가 없다.
    let store: WorkTimerStore
    // 스냅샷 전용: 참여코드 인라인 행이 펼쳐진 상태로 그린다(키 버튼 클릭을 대신). 앱은 false.
    var previewCodeRevealed: Bool = false
    // 목록 위쪽에서 배너/토큰 행이 먹은 높이(pt). 그만큼 무스크롤 표시 행수를 줄여 창 상한을 지킨다.
    var extraChromeHeight: CGFloat = 0
    // 스냅샷 전용: 초과 리스트를 ScrollView 대신 클립으로 그린다(ImageRenderer 육안 확인용). 앱은 false.
    var clipsOverflowInsteadOfScroll: Bool = false

    // 키 버튼으로 토글하는 참여코드 인라인 노출 상태. 스냅샷은 previewCodeRevealed 로 시드된다.
    @State private var showsInviteCode: Bool

    init(
        store: WorkTimerStore,
        previewCodeRevealed: Bool = false,
        extraChromeHeight: CGFloat = 0,
        clipsOverflowInsteadOfScroll: Bool = false
    ) {
        self.store = store
        self.previewCodeRevealed = previewCodeRevealed
        self.extraChromeHeight = extraChromeHeight
        self.clipsOverflowInsteadOfScroll = clipsOverflowInsteadOfScroll
        _showsInviteCode = State(initialValue: previewCodeRevealed)
    }

    // 참여코드를 보유(소속 팀원이면 로드됨)했을 때 키 버튼/인라인 행을 노출한다 — owner 뿐 아니라 팀원 누구나.
    private var canRevealCode: Bool {
        store.myTeamInviteCode != nil
    }

    var body: some View {
        VStack(spacing: 12) {
            // 헤더 폭 예산(TeamHeaderWidthBudget)의 실물이다. 버튼을 하나 더하거나 장식을 되살리면 팀 이름이
            // 먼저 잘리므로(4자 팀이 "아잉…"), 여기 구성을 바꿀 때는 그 순수 계산과 회귀 테스트도 함께 고쳐야 한다.
            // v0.2.11 정정: 장식용 person.2.fill 아이콘(25pt)을 걷어내고 개인용 '내 기록' 버튼은 헤더 카드(내 근무 박스)로
            // 옮겨, 팀 이름이 v0.2.10 보다 넓은 폭을 되찾았다. 남는 버튼은 전부 팀/전체 화면 전환용이다.
            HStack(spacing: 8) {
                Text(store.teamName)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(CheckTheme.primaryText)
                    .lineLimit(1)
                    // 그래도 긴 이름(공백 포함 8자 이상)은 잘리기 전에 먼저 줄여 본다 — 말줄임보다 식별이 우선.
                    .minimumScaleFactor(0.75)
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
                PokeEntryIconButton(store: store)
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

    // 배너/토큰 행이 먹은 높이를 반영한 실제 무스크롤 표시 행수(기본은 maxVisibleRows).
    private var visibleRows: Int {
        ListRowBudget.visibleRows(
            maxVisibleRows: Self.maxVisibleRows,
            rowHeight: CheckTheme.memberRowHeight,
            rowSpacing: Self.rowSpacing,
            extraChromeHeight: extraChromeHeight
        )
    }

    // 표시할 행 개수(빈 팀은 안내용 1행).
    private var rowCount: Int {
        sortedMembers.isEmpty ? 1 : sortedMembers.count
    }

    // 멤버 리스트 높이 = 팀원 수 비례. visibleRows까지는 rowHeight*count 그대로 자라고(스크롤 없음),
    // 초과하면 그 높이로 고정하고 ScrollView로 스크롤한다(창 높이 상한).
    @ViewBuilder
    private var memberList: some View {
        let visibleRows = visibleRows
        let capHeight = Self.listContentHeight(rowCount: visibleRows)
        if rowCount <= visibleRows {
            rows.frame(maxWidth: .infinity, alignment: .top)
        } else if clipsOverflowInsteadOfScroll {
            // 스냅샷 전용: 보이는 첫 visibleRows행만 클립해 그린다(ScrollView는 ImageRenderer가 못 그림).
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
                    // 별명 편집 진입(연필 배지 → 인라인 편집 행)이 여기 있었다. 설정 창의 "별명" 행이
                    // **별명의 단일 거처**가 되면서 통째로 걷어냈다 — 같은 값을 두 군데서 고칠 수 있으면
                    // 쿨타임(주 1회)·중복 검사 같은 서버 규칙 앞에서 두 화면의 안내가 언젠가 어긋난다.
                    // 이름 자체는 그대로 보인다(행이 없어진 게 아니라 편집 진입만 없어졌다).
                    TeamMemberLiveRow(
                        store: store,
                        member: member,
                        teamGoalSeconds: store.teamGoalSeconds,
                        isMe: isMe,
                        onPickAvatar: isMe ? { store.updateAvatar(imageData: $0) } : nil
                    )
                    // 행 높이는 계속 상수로 고정한다 — 목록 총 높이가 내용에 따라 흔들리면 창이 700pt 상한을 넘는다.
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
    // 별명 편집 진입(onBeginEditName) 통로가 여기 있었다. 설정 창이 별명의 단일 거처가 되면서 걷어냈다 —
    // TeamMemberRow 의 인자는 남아 있지만(그 파일은 이 작업의 소유가 아니다) 아무도 넘기지 않으므로
    // 연필 배지는 어느 행에도 그려지지 않는다.

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
    // 목록 위쪽에서 배너/토큰 행이 먹은 높이(pt). 그만큼 무스크롤 표시 행수를 줄여 창 상한을 지킨다.
    var extraChromeHeight: CGFloat = 0
    // 스냅샷 전용: 초과 리스트를 ScrollView 대신 클립으로 그린다(ImageRenderer 육안 확인용). 앱은 false.
    var clipsOverflowInsteadOfScroll: Bool = false

    // 팀 행 고정 높이·간격. 팀원 행보다 높다(아바타 + 이름/시간 + 게이지 + 캡션 3단).
    private static let rowHeight: CGFloat = 58
    private static let rowSpacing: CGFloat = 10
    // 스크롤 없이 그대로 보여 주는 최대 팀 수. 행이 팀원 행보다 높아 창 높이 상한(≤700pt)을 지키도록 6으로 둔다.
    static let maxVisibleRows = 6

    // 배너/토큰 행이 먹은 높이를 반영한 실제 무스크롤 표시 행수(기본은 maxVisibleRows).
    private var visibleRows: Int {
        ListRowBudget.visibleRows(
            maxVisibleRows: Self.maxVisibleRows,
            rowHeight: Self.rowHeight,
            rowSpacing: Self.rowSpacing,
            extraChromeHeight: extraChromeHeight
        )
    }

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
        let visibleRows = visibleRows
        let capHeight = Self.listContentHeight(rowCount: visibleRows)
        if rowCount <= visibleRows {
            rows.frame(maxWidth: .infinity, alignment: .top)
        } else if clipsOverflowInsteadOfScroll {
            // 스냅샷 전용: 보이는 첫 visibleRows행만 클립해 그린다(ScrollView는 ImageRenderer가 못 그림).
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
/// 과거 달을 보고 있을 때는 '아직 아무도 안 올림'이 아니라 '그 달엔 기록 자체가 없음'이므로 문구를 나눈다.
/// 월 이동(‹ ›)은 목록을 비우고 다시 로드하므로 이 '로드 전' 상태를 사용자가 반복해서 밟는다. 그동안 본문
/// 자리에 동기화 문구("동기화됨")가 뜨면 무슨 뜻인지 알 수 없어(개인 기록 패널에서 이미 금지한 패턴),
/// 로드가 진행 중이면 "불러오는 중…"을 쓴다. 조회가 실패로 끝났으면 실패 문구 + [다시 시도] 로 가른다 —
/// 이 구분이 없던 시절엔 월 이동 중 실패가 (로드 전 + 진행중 아님) 조합을 남겨, 본문 자리에 "동기화됨"·
/// "근무 재개됨" 같은 무관한 동기화 문구가 뜨고 재시도 수단도 없었다(개인 기록 패널에서 이미 금지한 패턴).
/// 셋 다 아닌데 비었으면(로그인 전 등 조회 자체가 시작되지 않은 상태) 기존대로 상태 문구를 쓴다.
enum TokenBoardEmptyMessage {
    static let loading = "불러오는 중…"
    static let noUploads = "아직 이번 달 소모량을 올린 사용자가 없어요"
    static let noPastRecords = "이 달에는 기록이 없어요"
    static let loadFailed = "순위를 불러오지 못했어요"
    static func text(
        hasLoaded: Bool,
        isLoading: Bool = false,
        hasFailed: Bool = false,
        fallbackStatus: String,
        isCurrentMonth: Bool = true
    ) -> String {
        guard hasLoaded else {
            if isLoading { return loading }
            return hasFailed ? loadFailed : fallbackStatus
        }
        return isCurrentMonth ? noUploads : noPastRecords
    }
}

/// 패널 본문 자리 문구 옆에 붙는 [다시 시도] 버튼(토큰 순위판·개인 기록 공용). 실패했을 때만 그린다 —
/// 없던 시절엔 팝오버를 닫았다 다시 여는 것 말고는 재시도 경로가 없었다.
private struct PanelRetryButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("다시 시도", systemImage: "arrow.clockwise")
                .font(.caption2.weight(.bold))
                .foregroundStyle(CheckTheme.accent)
                .padding(.horizontal, 9)
                .frame(height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(CheckTheme.accent.opacity(0.14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(CheckTheme.accent.opacity(0.35), lineWidth: 1)
                        )
                )
                .fixedSize()
        }
        .buttonStyle(.plain)
    }
}

/// 팀 카드 자리를 대체하는 "N월 AI 토큰" 순위 페이지(앱 사용자 전체 공개). 리그 페이지와 같은 뼈대다:
/// 뒤로 버튼 + ‹ 제목 › (월 이동) + 고정 행높이 리스트(maxVisibleRows 초과 시 스크롤). 등수 숫자/메달 배지는 없다 — 정렬 순서가 곧 순위.
/// 행은 아바타 + 이름(+내 행 "나" 칩) + 우측 전체 숫자(콤마 구분·monospacedDigit). 업로드한 사용자만 뜬다(행 없으면
/// 목록에 없음). 목록이 비면 로드 성공 여부에 따라 '아직 없음' 또는 fallbackStatus 를 보인다.
private struct TokenBoardPanel: View {
    // total 내림차순(동률 이름)으로 정렬된 엔트리(store 에서 이미 정렬됨). 뷰에서도 같은 규약으로 다시 정렬한다.
    let entries: [TokenBoardEntry]
    // 내 user_id(내 행 "나" 칩 판정용). nil 이면 어떤 행에도 칩이 붙지 않는다.
    var myUserID: String? = nil
    // 보드 첫 성공 로드 여부. 빈 목록 문구를 '아직 없음'(true) vs 로드 전/실패 fallbackStatus(false) 로 가른다.
    var hasLoaded: Bool = false
    // 지금 조회가 날아가 있는지(월 이동 직후 포함). 로드 전 빈 목록 자리에 "불러오는 중…"을 쓰기 위한 구분.
    var isLoading: Bool = false
    // 마지막 조회가 실패로 끝났는지. true 면 동기화 문구 대신 실패 문구 + [다시 시도] 를 그린다.
    var hasFailed: Bool = false
    // [다시 시도] 액션. nil 이면 버튼을 그리지 않는다(값+클로저 규약 — 렌더 테스트가 스토어 없이 재현 가능).
    var onRetry: (() -> Void)? = nil
    // 아직 로드 전/실패 시 빈 목록 자리에 표시할 안내 문구(동기화 상태 문구).
    var fallbackStatus: String = ""
    // 보고 있는 월(KST 'YYYY-MM'). 제목("N월 AI 토큰 소모량")과 빈 목록 문구 분기에 쓴다.
    var month: String = TokenUsageMonthKey.current()
    // 다음 달(미래 방향)로 갈 수 있는지 — 현재 월이면 false 라 › 버튼이 비활성된다.
    var canStepForward: Bool = false
    // 월 이동 액션(-1=과거, +1=미래). 값+클로저로만 받아 렌더 테스트가 스토어 없이도 상태를 재현할 수 있게 한다.
    var onStepMonth: (Int) -> Void = { _ in }
    // 내 토큰 사용량 공개 여부. 내 행에 "비공개" 미니 칩을 붙일지만 가른다 —
    // **전환은 여기서 하지 않는다**(설정 창의 "AI 토큰 사용량 공개" 스위치가 유일한 집이다).
    var isMyUsagePublic: Bool = true
    var onBack: () -> Void = {}
    // 현재 KST 날짜 'YYYY-MM-DD'. 행이 서버의 todayDate 와 비교해 "오늘 +N"(오늘분) 표시 여부를 가른다.
    // 기본은 실시간 계산 — 렌더 테스트는 픽스처와 같은 오늘 키를 쓰도록 주입한다(결정성). 렌더 시점에 1회 평가된다.
    var todayKey: String = TokenUsageDayKey.current()
    // 목록 위쪽에서 배너/토큰 행이 먹은 높이(pt). 그만큼 무스크롤 표시 행수를 줄여 창 상한을 지킨다.
    var extraChromeHeight: CGFloat = 0
    // 스냅샷 전용: 초과 리스트를 ScrollView 대신 클립으로 그린다(ImageRenderer 육안 확인용). 앱은 false.
    var clipsOverflowInsteadOfScroll: Bool = false

    // 토큰 행은 프로필 카드(RoundedRectangle 테두리 + 내부 패딩 + 좌측 악센트 바)라 밋밋한 한 줄보다 높다.
    // 우측이 "이번 달 총량 + 오늘 +N" 2줄로 커져(카드당 한 줄 추가) 아바타(30pt) 위아래 여백과 함께 수납하도록 62pt로 둔다.
    private static let rowHeight: CGFloat = 62
    private static let rowSpacing: CGFloat = 8
    // 스크롤 없이 보여 주는 최대 인원. 2줄 카드로 행이 62pt로 높아져 7행이면 창이 700pt 상한을 넘으므로 6으로 내린다
    // (리스트 높이 6*62 + 5*8 = 412pt — 창 높이 상한 ≤700pt 안).
    static let maxVisibleRows = 6

    // 배너/토큰 행이 먹은 높이를 반영한 실제 무스크롤 표시 행수(기본은 maxVisibleRows).
    private var visibleRows: Int {
        ListRowBudget.visibleRows(
            maxVisibleRows: Self.maxVisibleRows,
            rowHeight: Self.rowHeight,
            rowSpacing: Self.rowSpacing,
            extraChromeHeight: extraChromeHeight
        )
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                IconButton(icon: "chevron.left", help: "뒤로", action: onBack)
                // 뒤로(‹)와 월 이동 버튼을 세로 구분선으로 갈라 놓는다 — 같은 chevron 두 개가 4pt 간격으로
                // 붙어 있으면 뒤로를 누르려다 지난달이 열리는(반대로 월을 넘기려다 패널이 닫히는) 오조작이 난다.
                Capsule()
                    .fill(CheckTheme.border)
                    .frame(width: 1, height: 16)
                // 월 이동: ◂ 는 언제나 과거로, ▸ 는 현재 월이면 비활성(미래는 볼 수 없다).
                // 뒤로 버튼과 아이콘 모양(삼각 vs chevron)까지 달리해 툴팁 없이도 구분되게 한다.
                IconButton(icon: "arrowtriangle.left.fill", help: "이전 달") { onStepMonth(-1) }
                Text("\(TokenBoardMonthNavigator.displayTitle(month)) AI 토큰 소모량")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(CheckTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                IconButton(icon: "arrowtriangle.right.fill", help: "다음 달", enabled: canStepForward) { onStepMonth(1) }
                // 공개/비공개 눈 버튼이 있던 자리. 설정 창으로 옮겼다 — "한 번 정하고 잊는" 값이라
                // 순위판을 볼 때마다 손 닿는 곳에 있을 이유가 없고, 같은 스위치가 두 군데 있으면 언젠가 어긋난다.
                // Spacer 는 남긴다: 제목이 짧은 달에도 월 이동 버튼 묶음이 왼쪽에 붙어 있어야 한다.
                Spacer(minLength: 2)
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

    // 보고 있는 달이 이번 달인지. 네비게이터가 미래로 못 가게 클램프하므로 '› 비활성 == 이번 달'이 성립한다.
    // 빈 목록 문구와 행의 "오늘 +N" 줄이 같은 판정을 쓴다 — 6월 보드에 '오늘'이 붙는 모순을 막는다.
    private var isCurrentMonth: Bool { !canStepForward }

    private var rowCount: Int {
        sortedEntries.isEmpty ? 1 : sortedEntries.count
    }

    // 리스트 높이 = 인원 비례. maxVisibleRows까지는 그대로 자라고(스크롤 없음), 초과하면 그 높이로 고정 후 스크롤.
    @ViewBuilder
    private var entryList: some View {
        let visibleRows = visibleRows
        let capHeight = Self.listContentHeight(rowCount: visibleRows)
        if rowCount <= visibleRows {
            rows.frame(maxWidth: .infinity, alignment: .top)
        } else if clipsOverflowInsteadOfScroll {
            // 스냅샷 전용: 보이는 첫 visibleRows행만 클립해 그린다(ScrollView는 ImageRenderer가 못 그림).
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
                // 로드 성공했는데 비면 '아직 아무도 안 올림'(이번 달)/'기록 없음'(과거 달), 진행중이면 "불러오는 중…",
                // 실패면 실패 문구 + [다시 시도]. 결정적 판정은 TokenBoardEmptyMessage 로 격리한다.
                HStack(spacing: 8) {
                    Text(TokenBoardEmptyMessage.text(
                        hasLoaded: hasLoaded,
                        isLoading: isLoading,
                        hasFailed: hasFailed,
                        fallbackStatus: fallbackStatus,
                        isCurrentMonth: isCurrentMonth
                    ))
                        .font(.caption)
                        .foregroundStyle(CheckTheme.secondaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    // 실패했을 때만 재시도를 준다(월 이동 실패는 사용자가 반복해서 밟는 경로다).
                    if hasFailed, !hasLoaded, let onRetry {
                        PanelRetryButton(action: onRetry)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: Self.rowHeight, alignment: .leading)
            } else {
                ForEach(sortedEntries) { entry in
                    let isMe = myUserID != nil && entry.userID == myUserID
                    // 내 행이면서 비공개일 때만 "비공개" 미니 칩을 붙인다 — 남들 보드엔 내 행이 안 보인다는 표시.
                    TokenBoardRowView(
                        entry: entry,
                        isMe: isMe,
                        showsPrivateChip: isMe && !isMyUsagePublic,
                        showsToday: isCurrentMonth,
                        todayKey: todayKey
                    )
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
/// (렌더 테스트가 "오늘 +N" 줄 노출을 직접 검증할 수 있도록 internal 로 둔다 — 앱에서는 TokenBoardPanel 만 쓴다.)
struct TokenBoardRowView: View {
    let entry: TokenBoardEntry
    var isMe: Bool = false
    // 내 행이 비공개일 때만 "나" 칩 옆에 회색 "비공개" 미니 칩을 붙인다 — 남들 보드엔 내 행이 안 보인다는 표시.
    var showsPrivateChip: Bool = false
    // "오늘 +N 토큰" 줄 노출 여부. 이번 달 보드에서만 켠다 — 과거 달에는 '오늘'이 있을 수 없어(서버 today 합산이
    // 항상 0) 전 행에 "오늘 +0 토큰"이 붙는 모순이 생긴다.
    var showsToday: Bool = true
    // 현재 KST 날짜 'YYYY-MM-DD'. entry.todayDate 와 같을 때만 오늘 증가량을 노출한다(어제 이후 스테일이면 0).
    var todayKey: String = TokenUsageDayKey.current()

    // 좌측 악센트 바 색 — 아바타 이니셜과 동일한 이름 해시색(CheckTheme.avatarColor 공유). 유저별 컬러 포인트.
    private var accentColor: Color { CheckTheme.avatarColor(for: entry.name) }

    // 표시할 오늘 증가량. 날짜가 오늘이 아니면 0("오늘 +0 토큰"으로 균일 표시 — 어제 이후 안 연 사람도 행 형태 동일).
    private var todayValue: Int { entry.todayDelta(currentDate: todayKey) }

    // 칩이 둘 붙는 내 비공개 행에서만 숫자 열에 씌우는 상한(pt). nil 이면 제한 없음(보통 행은 예전 그대로).
    private var crowdedNumberColumnWidth: CGFloat? { showsPrivateChip ? 88 : nil }

    var body: some View {
        HStack(spacing: 10) {
            // 좌측 세로 악센트 바(3pt 캡슐): 유저 해시색. 카드 안에서 위아래 살짝 띄워 유저 구분 컬러 포인트를 준다.
            Capsule()
                .fill(accentColor)
                .frame(width: 3)
                .frame(maxHeight: .infinity)
                .padding(.vertical, 3)
            CheckAvatarView(name: entry.name, avatarURL: entry.avatarURL, size: 30)
            // 이름 + 칩은 한 덩어리로 6pt 간격에 묶는다 — 균일 10pt 는 칩이 둘 붙는 내 행에서 이름 몫을 먼저 갉아먹는다.
            HStack(spacing: 6) {
                Text(entry.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(CheckTheme.primaryText)
                    .lineLimit(1)
                    // 폭이 모자라면 말줄임보다 먼저 살짝 줄여 이름을 끝까지 보여 준다(칩 두 개가 붙는 내 행 대비).
                    .minimumScaleFactor(0.75)
                if isMe {
                    Text("나")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(CheckTheme.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(CheckTheme.accent.opacity(0.18)))
                        .fixedSize()
                }
                if showsPrivateChip {
                    // 회색 "비공개" 미니 칩 — 남들 보드엔 내 행이 안 보인다는 표시(내 행에만, 비공개일 때만).
                    Text("비공개")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(CheckTheme.secondaryText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.white.opacity(0.10)))
                        .fixedSize()
                }
            }
            // 남는 폭은 전부 이름 덩어리가 가진다(예전엔 Spacer 가 유연 폭을 반씩 나눠 가져, 칩이 붙은 행에서
            // 이름이 실제로 쓸 수 있는 폭이 절반으로 줄어 멀쩡히 들어갈 이름까지 말줄임됐다).
            .frame(maxWidth: .infinity, alignment: .leading)
            // 우측 2줄(오른쪽 정렬): 위 = 이번 달 총량("숫자 토큰"), 아래 = 오늘 증가량("오늘 +숫자 토큰").
            // layoutPriority(1): 숫자 블록이 먼저 필요한 폭을 가져간다. 내 행에 "나"+"비공개" 칩이 함께 붙으면
            // 남는 폭이 부족해져 10자리 총량이 '4,564,338,24…' 로 잘려 자릿수가 통째로 오독됐다(회귀 지점) —
            // 잘려도 되는 쪽은 이름이지 숫자가 아니다(아바타 이니셜·"나" 칩이 행 주인을 이미 알려 준다).
            VStack(alignment: .trailing, spacing: 1) {
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
                // 오늘(KST 자정 이후) 증가량 — 누가 오늘 열심히 작업 중인지 한눈에. 작게(caption2·secondary·monospacedDigit).
                // 과거 달 보드에서는 통째로 생략한다('6월을 보는데 오늘'이라는 모순 제거).
                if showsToday {
                    Text("오늘 +\(TokenNumberFormatter.grouped(todayValue)) 토큰")
                        .font(.caption2)
                        .foregroundStyle(CheckTheme.secondaryText)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .layoutPriority(1)
            // 칩 두 개가 붙는 내 비공개 행은 폭 예산 자체가 모자라다 — 숫자 열 상한을 낮춰 minimumScaleFactor 가
            // '전 자릿수 유지 + 균일 축소'로 처리하게 하고(0.78배, 말줄임 없음) 남는 폭은 이름에 돌려준다.
            .frame(maxWidth: crowdedNumberColumnWidth, alignment: .trailing)
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

// MARK: - Poke directory page

/// 콕 버튼 눌림 UX — isPressed 에서 살짝 축소(0.82) + 불투명도 다운으로 눌리는 느낌을 주고,
/// 스프링으로 탄성 있게 복귀시킨다. accent 원형 찌르기 버튼에 적용한다.
private struct PokePressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.82 : 1.0)
            .opacity(configuration.isPressed ? 0.82 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.55), value: configuration.isPressed)
    }
}

/// 울트라 충전 시각 규약(순수 함수 — ImageRenderer 없이 값으로 검증한다).
/// charge 0 = accent(파랑), 1 = 새빨강. **여기에 곡선을 넣지 마라** — withAnimation 은 body 를 프레임마다
/// 재평가하지 않고 modifier 의 animatable data 를 두 끝점 사이에서 보간하므로, 이 함수는 0 과 1 에서만
/// 호출된다. 곡선은 함수가 아니라 Animation 쪽(.easeOut)에 건다.
/// 색만 쓰지 않고 크기도 함께 키우는 이유는 색약/흑백 대비다.
enum UltraChargeStyle {
    static let base = (r: 0.33, g: 0.67, b: 1.0)   // CheckTheme.accent 와 같은 값
    static let full = (r: 1.0,  g: 0.18, b: 0.18)
    /// 울트라가 나가기까지 꾹 눌러야 하는 시간(초). 링이 꽉 차는 시각과 발사 시각이 같아야 하므로
    /// 애니메이션 길이와 Task.sleep 이 **같은 상수**를 봐야 한다 — 두 곳에 숫자를 흩뿌리면 언젠가 갈라진다.
    static let holdSeconds: Double = 3.0

    /// 화면 문구에 박히는 홀드 시간 표기("N초 꾹"의 그 N). 이 줄이 없으면 문구가 리터럴로 남아,
    /// holdSeconds 를 2초로 줄인 날 버튼은 2초에 나가는데 힌트와 툴팁만 "3초"라고 거짓말한다.
    /// 정수면 소수점을 뗀다 — 문자열 보간을 그냥 쓰면 "3.0초 꾹 = 울트라"가 된다.
    /// 정수가 아닌 값으로 바꿔도(2.5) 그대로 읽히게 남겨 둔다.
    static var holdSecondsText: String {
        holdSeconds == holdSeconds.rounded() ? String(Int(holdSeconds)) : String(holdSeconds)
    }

    static func components(charge: CGFloat) -> (r: Double, g: Double, b: Double) {
        let t = Double(min(max(charge, 0), 1))
        return (base.r + (full.r - base.r) * t,
                base.g + (full.g - base.g) * t,
                base.b + (full.b - base.b) * t)
    }

    static func fillColor(charge: CGFloat) -> Color {
        let c = components(charge: charge)
        return Color(red: c.r, green: c.g, blue: c.b)
    }

    /// 눌린 순간 0.86 으로 움츠렸다가 충전이 찰수록 1.18 까지 자란다(PokePressButtonStyle 의 눌림감 계승).
    static func scale(charge: CGFloat, isPressing: Bool) -> CGFloat {
        guard isPressing else { return 1.0 }
        return 0.86 + 0.32 * min(max(charge, 0), 1)
    }
}

/// 울트라 **잔량 문구** 규약(순수 — 값으로 검증한다). v0.2.33 의 `PokeUltraHint` 를 대체한다.
///
/// 옛 문구("오늘 N번 남음" / "울트라 소진")를 그대로 두면 안 되는 이유는 **두 번 틀리기 때문**이다:
///  · 잔량은 **오늘의 것이 아니다** — 재화라 이월된다. 잔량 3인 사람에게 "오늘 3번 남음"은
///    자정에 초기화된다는 거짓말이고, 실제로는 내일도 3이다.
///  · 잔량은 **남은 것이 아니다** — 가진 것이다. "소진"은 '기다리면 찬다'를 함의하는데,
///    이제는 **미션을 해야만** 찬다. 기다리는 사람은 영영 못 받는다.
///
/// 그래서 0일 때 사실만 말하고 끝내지 않고 **획득 경로를 말한다**. 이 앱에서 새 경제를 가르치는
/// 자리는 여기 하나뿐이다(콕찌르기를 여는 순간이 잔량을 궁금해하는 유일한 순간이다).
enum UltraBalanceText {
    /// 무제한(관리자)일 때 배지가 그리는 **한 글자**. 숫자가 아니라 기호인 것이 설계다 —
    /// 제목 행 폭 예산이 "배지 = 캡슐 + 번개 + 글리프 하나"를 전제로 계산돼 있고(PokeTitleRowWidthBudget),
    /// 여기에 "무제한"(3글자, 26pt 로 재면 26pt·caption2 로도 21pt)을 넣으면 그 예산이 통째로 뒤집힌다.
    /// 뜻은 배지 툴팁(badgeHelp)과 울트라 화면의 큰 글자("무제한")가 말로 풀어 준다.
    static let unlimitedBadge = "∞"

    /// 배지 안 글자. 음수는 서버 버그이거나 미래 규약이라 0으로 접는다.
    /// **무제한이면 숫자를 아예 만들지 않는다** — 관리자에게 잔량 숫자는 아무 뜻도 없다(줄지 않는다).
    static func badge(balance: Int, unlimited: Bool = false) -> String {
        unlimited ? unlimitedBadge : "\(max(0, balance))"
    }

    /// 0개일 때. **획득 경로를 말한다** — 사실만 말하고 길을 안 알려 주면 그 화면은 막다른 길이다.
    static let empty = "미션으로 충전"

    /// 1개 이상일 때 — 발견성 문구를 그대로 살린다(3초 꾹을 아직 모르는 사람이 다수다).
    /// 홀드 시간은 리터럴로 적지 않는다: UltraChargeStyle.holdSeconds 가 발사 시각의 유일한 권위이고,
    /// 그 숫자를 여기 베껴 두면 상수를 바꾼 날 화면만 옛 시간을 말한다.
    static var discover: String { "\(UltraChargeStyle.holdSecondsText)초 꾹 = 울트라" }

    /// 제목 행 힌트. **nil(아직 모름)이면 아무 숫자도 만들지 않고** 발견성 문구를 그대로 둔다
    /// (WorkTimerStorePoke 의 "정직한 일은 버리는 것" 규약 계승 — 틀린 숫자보다 침묵이 낫다).
    /// 무제한이면 **언제나 발견성 문구다.** 관리자의 잔량은 0일 수 있는데(쓰지 않으니 늘지도 않는다),
    /// 그 사람에게 "미션으로 충전"이라고 말하면 하지 않아도 되는 일을 시키는 거짓 안내가 된다.
    static func hint(balance: Int?, unlimited: Bool = false) -> String {
        if unlimited { return discover }
        guard let balance else { return discover }
        return balance <= 0 ? empty : discover
    }

    /// 행 툴팁의 괄호 안 문구. 잔량이 없어도 **3초 홀드는 그대로 발사된다**(판정은 서버다) —
    /// 그래서 "못 쏜다"가 아니라 "없다 + 채우는 법"을 말한다.
    static func rowTooltip(balance: Int?, unlimited: Bool = false) -> String {
        (unlimited || (balance ?? 1) > 0)
            ? "콕 찌르기 (\(UltraChargeStyle.holdSecondsText)초 꾹 누르면 울트라)"
            : "콕 찌르기 (울트라 없음 — 미션으로 충전)"
    }

    /// 배지 툴팁. 숫자 자체는 반드시 Text 로 그린다 — 툴팁은 픽셀을 만들지 않으므로
    /// 정보를 여기에만 두면 렌더 테스트가 통째로 눈이 먼다.
    /// 무제한일 때는 **기호의 뜻을 말로 푼다** — 배지가 그리는 것은 글리프 하나뿐이라,
    /// 그 자리에 잔량이 있던 것을 기억하는 사람은 ∞ 를 "못 읽었다"로 오해할 수 있다.
    /// "충전 방법"을 말하지 않는 것도 의도다: 충전할 것이 없는 사람에게 충전을 권하지 않는다.
    static func badgeHelp(balance: Int?, unlimited: Bool = false) -> String {
        if unlimited { return "울트라 무제한 — 눌러서 보기" }
        return balance.map { "울트라 \($0)개 — 눌러서 충전 방법 보기" } ?? "잔량을 아직 못 읽었어요 — 눌러서 보기"
    }
}

/// 콕찌르기 제목 행의 폭 예산(순수 계산 — 결정적 검증 지점).
/// 행 구성: `[뒤로 27][콕 찌르기][집중모드 27][Spacer ≥6][잔량 배지][힌트]` · spacing 8 × 5
///
/// TeamHeaderWidthBudget / FooterWidthBudget 과 같은 이유로 존재한다: 이 행에 무언가를 하나 더
/// 세우는 순간 **가장 유연한 요소(힌트 문구)가 먼저 말줄임된다.** 배지를 세운 것이 그 '하나 더'다.
/// 그리고 힌트는 `.fixedSize()` 라 넘쳐도 높이가 안 변한다 = **렌더 높이 테스트로는 안 잡힌다.**
/// 이 순수 계산이 그 사각지대의 유일한 방어망이다.
enum PokeTitleRowWidthBudget {
    /// 팝오버 340 - 바깥 padding 12*2 - 패널 padding 12*2.
    static let contentWidth: CGFloat = 340 - 12 * 2 - 12 * 2
    static let iconButtonWidth: CGFloat = 27
    static let spacing: CGFloat = 8
    static let spacerMinWidth: CGFloat = 6
    /// "콕 찌르기"(subheadline bold · 한글 4 + 공백 1) 실측 폭.
    static let titleWidth: CGFloat = 57
    /// caption2(10pt) 한글 1자 근사. 라틴/숫자/공백은 이보다 좁으므로 한글로 재면 보수적이다.
    static let koreanCaptionGlyphWidth: CGFloat = 10
    /// 실제로 쓰는 가장 긴 힌트("3초 꾹 = 울트라")의 실측 폭. 한글 3자 + 라틴/기호/공백 7이라
    /// 글자수(10)로 재면 과대평가된다.
    static let longestHintWidth: CGFloat = 71

    /// 배지가 그릴 수 있는 **최대 자릿수**. 잔량 상한이 5(사장님 확정 4)라 1자리로 고정된다.
    /// 서버가 상한을 두 자리로 올리면 이 값이 아니라 `hintWidth(digits: 2)` 단언이 먼저 답을 준다.
    static let maxBadgeDigits = 1

    /// 배지 폭: 캡슐 h-padding 6*2 + bolt 10 + 내부 간격 3 + 숫자(자릿수 × 7).
    static func badgeWidth(digits: Int) -> CGFloat { 12 + 10 + 3 + CGFloat(max(0, digits)) * 7 }

    /// 무제한 배지가 그리는 기호 "∞" 의 폭(pt). **숫자 한 자리보다 넓다** — 그래서 자릿수로 재지 않고
    /// 항을 따로 둔다(1자리인 척하면 예산이 조용히 2.3pt 씩 거짓말한다).
    ///
    /// **근거(실측, caption2 = 10pt bold · SF):** 숫자 6.83pt / "∞" 9.27pt.
    /// 보수적으로 10 을 쓴다. 그래도 **두 자리(14pt)보다는 좁다** — 그리고 이 파일에는
    /// `hintWidth(digits: 2) >= longestHintWidth` 를 못 박은 단언이 이미 있다(상한이 두 자리로
    /// 올라가는 날을 대비해 세워 둔 것). 즉 **무제한 배지의 여유는 그 단언이 이미 증명해 둔 여유의
    /// 부분집합이다** — 폭 예산을 늘릴 이유도, 기호를 더 좁은 것으로 바꿀 이유도 없다.
    /// (그래서 "무제한" 3글자를 배지에 넣는 선택은 기각했다: caption2 로 재도 21pt 라
    ///  3자리 숫자보다 넓어, 힌트가 말줄임되는 첫 번째 조합이 된다.)
    static let unlimitedGlyphWidth: CGFloat = 10

    /// 무제한 배지의 폭. 숫자 자리를 기호 하나로 바꾼 것 말고는 badgeWidth 와 같은 조립이다.
    static var unlimitedBadgeWidth: CGFloat { 12 + 10 + 3 + unlimitedGlyphWidth }

    /// 그 조합에서 힌트에 남는 폭(pt).
    static func hintWidth(digits: Int = maxBadgeDigits) -> CGFloat {
        contentWidth
            - iconButtonWidth * 2          // 뒤로 + 집중모드
            - titleWidth
            - spacerMinWidth
            - badgeWidth(digits: digits)
            - spacing * 5
    }

    /// 그 폭에 말줄임 없이 들어가는 한글 글자수.
    static func hintKoreanGlyphs(digits: Int = maxBadgeDigits) -> Int {
        max(0, Int(hintWidth(digits: digits) / koreanCaptionGlyphWidth))
    }

    /// 무제한 배지가 섰을 때 힌트에 남는 폭(pt). 관리자 화면에서만 성립하는 조합이라 따로 잰다.
    static var hintWidthWhenUnlimited: CGFloat {
        contentWidth
            - iconButtonWidth * 2
            - titleWidth
            - spacerMinWidth
            - unlimitedBadgeWidth
            - spacing * 5
    }

    static var hintKoreanGlyphsWhenUnlimited: Int {
        max(0, Int(hintWidthWhenUnlimited / koreanCaptionGlyphWidth))
    }
}

/// 제목 행 오른쪽 울트라 잔량 배지. **탭하면 울트라 화면**(잔량 + 충전 경로)이 열린다 —
/// "0개인데 어떻게 채우죠?"라는 질문이 실제로 생기는 자리가 여기뿐이라 답도 여기에 붙인다.
///
/// **Menu 를 쓰지 않는다.** ImageRenderer 가 Menu 를 노란 상자로 그려 그 자리 픽셀 커버리지가 0이 되고,
/// 그러면 "배지가 통째로 사라진 회귀"를 렌더 테스트가 영영 못 잡는다(푸터가 Menu 를 걷어낸 뒤에야
/// 비로소 픽셀로 검증됐다는 기록이 그 대가를 이미 적어 뒀다). Button + .buttonStyle(.plain) 은
/// IconButton/PanelRetryButton 과 같은 관용구이고 이미 픽셀로 검증된 길이다.
struct UltraBalanceBadge: View {
    /// nil = 아직 모름. 숫자를 만들지 않고 번개만 흐리게 그린다(자리는 유지).
    let balance: Int?
    /// **서버가 말해 준** 무제한(관리자). true 면 숫자 자리에 기호 하나(∞)를 그린다.
    /// 기본값 false 라 이 값을 안 넘기는 자리(기존 호출부·테스트)는 지금과 **완전히 같다**.
    var isUnlimited: Bool = false
    let action: () -> Void

    @State private var hovering = false

    /// 무제한은 **비어 있지 않다.** 이 한 줄을 빼면 잔량 0 인 관리자의 배지가 회색으로 죽는다
    /// (관리자는 재화를 안 쓰므로 잔량이 0 에 머무는 것이 정상이다 — 서버는 그래도 발사한다).
    private var isEmpty: Bool { !isUnlimited && (balance ?? 1) <= 0 }
    private var tint: Color { isEmpty ? CheckTheme.secondaryText : CheckTheme.accent }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 9, weight: .bold))
                // 무제한이면 잔량을 몰라도 그린다(∞ 는 잔량에서 파생되는 글자가 아니다).
                if isUnlimited || balance != nil {
                    Text(UltraBalanceText.badge(balance: balance ?? 0, unlimited: isUnlimited))
                        .font(.caption2.weight(.bold))
                        .monospacedDigit()
                }
            }
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            // 테두리를 남기는 이유는 미학이 아니라 **검증**이다: nil 일 때 아이콘만 흐리게 그리면
            // 패널 배경과의 픽셀 델타가 거의 0이라 배지 소실 회귀를 렌더가 못 잡는다.
            .background(Capsule().fill(tint.opacity(hovering ? 0.28 : 0.16)))
            .overlay(Capsule().stroke(tint.opacity(0.35), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        // 자리는 유지하고 숫자만 비운다 — 배지가 사라졌다 나타나면 제목 행 폭이 흔들린다
        // (IconButton.enabled 주석이 이미 "자리를 유지한 채 비활성만"으로 거부한 문제와 같은 것이다).
        .opacity(balance == nil && !isUnlimited ? 0.55 : 1)
        .fixedSize()
        .help(UltraBalanceText.badgeHelp(balance: balance, unlimited: isUnlimited))
    }
}

/// 콕찌르기 빈 목록 자리 문구 선택(순수 로직, 결정적 검증 지점). 리그/토큰 보드의 EmptyMessage 와 같은 패턴이다:
/// 로드 성공했는데 비면 '아직 아무도 없음'(true), 로드 전/실패면 fallbackStatus(동기화 상태 문구)(false).
/// 집중 모드가 켜져 있을 때 콕찌르기 패널이 알려 주는 사실(순수 값 — 문구를 값으로 검증한다).
/// 토글이 아이콘 하나뿐이라, 켜 둔 것을 잊고 "왜 아무도 안 찌르지?" 하는 경로를 이 한 줄이 막는다.
enum PokeFocusNotice {
    static let text = "집중 모드 — 콕찌르기를 받지 않아요"
}

enum PokeDirectoryEmptyMessage {
    static let noOthers = "아직 다른 사용자가 없어요"
    static func text(hasLoaded: Bool, fallbackStatus: String) -> String {
        hasLoaded ? noOthers : fallbackStatus
    }
}

// MARK: - 3글자 메시지 (콕 찌르기와 같은 폴링으로 도착한다)

/// 입력칸 옆 글자수 표시의 규약(순수 — 화면 문구 전용).
///
/// **글자 수는 세지 않고 MessageBody 에 물어본다.** 세는 규칙(NFC 정규화·제어문자 제거·확장 자소 클러스터)은
/// 전송 게이트와 서버 판정이 쓰는 그 함수 하나여야 한다 — 뷰가 String.count 로 따로 세면 붙여넣은 NFD 한글이
/// 화면엔 "2자"인데 서버는 too_long 으로 거절하는, 사용자가 원인을 알 수 없는 화면이 만들어진다.
///
/// **입력 중에는 텍스트를 건드리지 않는다(자르지 않는다).** 조합 중인 글자를 코드가 바인딩에 되쓰면
/// 마지막 글자가 씹히는 한글 IME 회귀를 부르는데, 그 동작은 오프스크린 렌더로 검증할 방법이 없다 —
/// 검증할 수 없는 것에 이 기능의 핵심 입력(한글)을 걸지 않는다. 대신 **초과를 눈에 보이게 막는다**:
/// 카운터가 danger 로 물들고, 테두리가 빨개지고, [보내기]와 Enter 가 잠긴다.
enum PokeMessageCounter {
    /// 사용자가 세는 글자 수(정규화 후) — MessageBody 가 유일한 권위.
    static func length(_ text: String) -> Int { MessageBody.characterCount(text) }
    static func remaining(_ text: String) -> Int { max(0, MessageBody.maxCharacters - length(text)) }
    static func isFull(_ text: String) -> Bool { length(text) == MessageBody.maxCharacters }
    static func isOverflowing(_ text: String) -> Bool { length(text) > MessageBody.maxCharacters }

    /// 보낼 수 있는가. 빈 입력·초과는 요청을 만들지 않는다(같은 판정을 MessageBody.validate 가 낸다).
    static func isSendable(_ text: String) -> Bool {
        if case .ok = MessageBody.validate(text) { return true }
        return false
    }

    /// 카운터 문구. **남은 수를 말한다** — "3/3"은 다 쓴 건지 세 글자가 남은 건지 읽는 사람마다 다르다.
    static func text(_ text: String) -> String {
        let over = length(text) - MessageBody.maxCharacters
        if over > 0 { return "\(over)자 초과" }
        let left = remaining(text)
        return left == 0 ? "꽉 참" : "\(left)자 남음"
    }
}

/// 3글자 메시지 입력칸의 **입력 시점 필터**(순수 — ASCIIInputFilter 와 같은 패턴, 허용 집합만 새로 정의한다).
/// 그쪽을 그대로 쓰면 한글이 통째로 죽으므로(비-ASCII 제거) 패턴만 빌린다.
///
/// **왜 종류를 입력 시점에 막는가 — 이모지를 허용하면 두 계산이 갈라진다(실측):**
/// Swift 는 확장 자소 클러스터로 세서 👨‍👩‍👧‍👦=1·🇰🇷=1·👍🏻=1 이지만 Postgres `char_length()` 는 코드포인트로 세서
/// 각각 7·2·2 다. 그러면 화면은 "1자"라고 말하는데 서버만 too_long 으로 거절하는, 사용자가 원인을 알 수 없는
/// 상태가 생긴다. **글자·숫자만 받으면 그 어긋남이 통째로 사라진다** — 허용 집합의 모든 문자는 NFC 정규화 뒤
/// 자소 1개 = 코드포인트 1개라 두 계산이 반드시 일치한다(테스트가 그 성질을 직접 잰다).
///
/// **허용 여부는 MessageBody.isTextOnly 가 정한다 — 이 뷰는 자기 표를 만들지 않는다.** 전송 게이트가 쓰는
/// 그 판정을 그대로 재사용해야, "입력은 됐는데 전송만 거부"나 그 반대가 원리적으로 불가능해진다.
/// 여기가 하는 일은 판정이 아니라 **적용 시점**뿐이다: 거부가 아니라 입력 순간 제거.
/// (허용 집합은 글자 L*·숫자 Nd·`  ? ! . , ~` 이고, 한글 자모 ㅇ(U+3147)이 otherLetter 로 통과하는 것이
///  이 기능의 생명줄이다 — 테스트가 실측으로 못 박는다.)
///
/// **길이는 여기서 자르지 않는다.** 종류 필터는 한글 조합 중에 발동할 일이 없지만(조합 중 글자는 항상 letter라
/// 필터가 손대지 않는다), 길이 자르기는 4번째 글자를 조합하는 순간 바인딩을 되써 마지막 글자가 씹히는
/// IME 회귀를 부른다. 초과는 카운터·테두리·잠긴 [보내기]로 **보이게** 막는다.
enum PokeMessageInputFilter {
    /// **조합 자모(U+1100~)는 이 필터가 통과시켜야 한다.** MessageBody.isTextOnly 는 완성 음절(가~힣)과
    /// 호환 자모(ㄱ~ㅣ)만 열어 두는데, 그건 그 판정이 **NFC 정규화를 끝낸 문자열**에 걸리기 때문이다
    /// (MessageBody.validate → sanitized → isTextOnly). 반면 여기는 **정규화 전 원문**을 본다:
    /// macOS 한글 입력기·파인더에서 온 글자는 분해형(ᄒ+ᅡ+ᆫ)으로 들어오므로, 원문에 그대로 isTextOnly 를
    /// 걸면 합쳐지기도 전에 한글이 통째로 지워진다("한"을 붙여넣으면 빈 칸이 된다 — 실측으로 걸린 회귀다).
    /// 그래서 조합 자모는 남기고, 합성은 전송 직전 MessageBody 가 한다. 합성되지 않는 옛한글은 거기서
    /// .unsupportedCharacters 로 거절되고 [보내기] 툴팁이 이유를 말한다.
    ///
    /// **정규화를 여기서 하지 않는 이유**: 조합 중인 글자를 NFC 로 되쓰면 그게 곧 IME 마지막 글자 씹힘이다.
    private static func isComposingHangulJamo(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x1100...0x11FF,     // 한글 자모(초·중·종성)
             0xA960...0xA97F,     // 한글 자모 확장 A
             0xD7B0...0xD7FF:     // 한글 자모 확장 B
            return true
        default:
            return false
        }
    }

    /// 허용되지 않은 스칼라를 **제거**한다(치는 것도 ⌘V 로 붙여넣는 것도 같은 이 바인딩을 지나므로
    /// 여기 한 곳이면 둘 다 막힌다). 스칼라 단위로 묻는 이유는 이모지가 여러 스칼라의 조합이라서다 —
    /// 자소 단위로 보면 그 안에 섞인 기호·ZWJ 를 못 본다(MessageBody.isTextOnly 와 같은 이유).
    static func filtered(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.filter { scalar in
            isComposingHangulJamo(scalar) || MessageBody.isTextOnly(String(scalar))
        }))
    }
}

/// 한 팀원 행 **바로 아래로** 펼쳐지는 3글자 메시지 작성기. 한 번에 한 행만 펼쳐진다(패널이 userID 하나로 소유).
///
/// 구성은 두 줄이 전부다: [누구에게 · 못 보내는 사유 · 닫기] + [입력칸 · 남은 글자 · 보내기].
/// 프리셋(빠른 말 칩)은 **일부러 없다** — 사장님 결정이고, 없어야 "무슨 말을 보낼지"를 앱이 대신 정하지 않는다.
///
/// 높이를 상수로 못 박는 이유는 700pt 창 예산이다. 펼침 높이가 상태마다 달라지면(안내 유무 등) 목록 상한
/// 계산이 근거를 잃는다 — 그래서 사유 문구도 새 줄이 아니라 머리줄의 남는 폭에 얹는다.
struct PokeMessageComposer: View {
    let targetName: String
    @Binding var text: String
    /// 이 대상 쿨타임 잔여 초(0이면 보낼 수 있다). 펼친 상태에서 **왜 안 되는지**를 여기서 말한다.
    var remainingCooldown: Int = 0
    /// 게이트 통과 여부(내가 근무중 + 대상이 근무중). 행의 찌르기 버튼과 **같은 판정**을 받는다.
    var canSend: Bool = true
    /// 전송 왕복 중. 연타로 두 번째 요청이 나가면 방금 자기가 만든 쿨타임에 확정으로 거절당한다.
    var isSending: Bool = false
    /// 스냅샷 전용: 필터 안내가 떠 있는 상태를 그대로 그린다(CredentialField.warnsInitially 선례). 앱은 false.
    var previewFilterWarning: Bool = false
    let onSend: (String) -> Void
    let onCancel: () -> Void

    /// 입력이 필터에 걸렸을 때의 안내. **이 문구의 자리는 응답 분기가 아니라 입력 단계다** —
    /// 서비스 계층이 .unsupportedCharacters 를 invalid 로 접으며 그 이유를 여기 맡겼다(SupabaseWorkService.sendMessage).
    /// 사용자 입장에서 벌어진 일은 "붙여넣은 게 사라졌다"이므로, 이 한 줄이 없으면 앱이 고장 난 것으로 읽힌다.
    static let filterWarningText = "이모지는 보낼 수 없어요"

    @State private var filterWarningActive = false
    @State private var filterWarningTask: Task<Void, Never>?

    private static let verticalPadding: CGFloat = 10
    private static let headerHeight: CGFloat = 15
    private static let blockSpacing: CGFloat = 7
    private static let inputRowHeight: CGFloat = 28

    /// 펼침 한 덩어리의 고정 높이(pt). 목록 높이 예산이 이 값을 그대로 쓴다.
    static let height: CGFloat = verticalPadding * 2 + headerHeight + blockSpacing + inputRowHeight

    /// 지금 보낼 수 있는가 — 게이트 + 쿨타임. 입력 내용(길이)은 [보내기]에서 따로 본다.
    private var isOpen: Bool { canSend && remainingCooldown <= 0 }

    /// 대상 이름 해시색. 위 행의 좌측 세로 바와 같은 색이라 "이 펼침은 그 사람 것"이 색으로 이어진다.
    private var accentColor: Color { CheckTheme.avatarColor(for: targetName) }

    var body: some View {
        VStack(alignment: .leading, spacing: Self.blockSpacing) {
            header
            inputRow
        }
        .padding(.horizontal, 10)
        .padding(.vertical, Self.verticalPadding)
        .frame(height: Self.height)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(CheckTheme.fieldFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(accentColor.opacity(0.55), lineWidth: 1)
                )
        )
    }

    // 누구에게 보내는지 + 지금 못 보내는 사유(쿨타임/게이트) + 닫기. 세 가지가 **같은 자리**를 쓴다.
    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.turn.down.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(accentColor)
            Text("\(targetName)님에게")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(CheckTheme.primaryText)
                .lineLimit(1)
            Spacer(minLength: 6)
            if let blockedText {
                Text(blockedText.text)
                    .font(.caption2)
                    .foregroundStyle(blockedText.isError ? CheckTheme.danger : CheckTheme.pending)
                    .lineLimit(1)
                    .fixedSize()
            }
            Button(action: onCancel) {
                Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(CheckTheme.secondaryText)
            .help("닫기")
            .accessibilityLabel("메시지 작성 닫기")
        }
        .frame(height: Self.headerHeight)
    }

    /// 머리줄 오른쪽 한 칸을 나눠 쓰는 사유들. 순서가 곧 우선순위다:
    /// ① 방금 필터에 걸린 입력(사용자가 **지금 한 행동**의 결과라 가장 급하다 — 안 그러면 글자가 그냥 사라진 것으로 읽힌다),
    /// ② 쿨타임 잔여(펼친 뒤에야 알 수 있어 여기서 말하지 않으면 알 방법이 없다),
    /// ③ 게이트(행 버튼도 흐리게 말해 주므로 마지막).
    /// 새 줄을 만들지 않고 한 칸을 나눠 쓰는 이유는 펼침 높이를 상수로 못 박아야 하기 때문이다(700pt 예산).
    private var blockedText: (text: String, isError: Bool)? {
        if filterWarningActive || previewFilterWarning { return (Self.filterWarningText, true) }
        if remainingCooldown > 0 { return ("\(remainingCooldown)초 뒤 가능", false) }
        if !canSend { return ("지금은 못 보내요", false) }
        return nil
    }

    /// 필터가 실제로 문자를 지웠을 때만 2.5초간 안내를 띄운다(CredentialField 의 ASCII 안내와 같은 수명).
    private func triggerFilterWarning() {
        filterWarningTask?.cancel()
        withAnimation(.easeInOut(duration: 0.15)) { filterWarningActive = true }
        filterWarningTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.15)) { filterWarningActive = false }
        }
    }

    private var inputRow: some View {
        HStack(spacing: 6) {
            // ⚠︎ CredentialField(enforcesASCII:) 를 쓰면 안 된다 — 그건 이메일·비밀번호용이라 포커스 시
            // 영문 자판으로 강제 전환하고 비-ASCII 를 걸러 낸다. 여기 핵심 용도가 바로 한글 3글자다.
            TextField("3글자", text: $text)
                .textFieldStyle(.plain)
                .font(.subheadline)
                .foregroundStyle(CheckTheme.primaryText)
                .tint(CheckTheme.accent)
                .lineLimit(1)
                .disabled(!isOpen)
                .accessibilityLabel("보낼 메시지")
                .onSubmit(sendTyped)
                // 입력 시점 필터. 타이핑도 ⌘V 붙여넣기도 결국 이 바인딩을 갱신하므로 여기 한 곳이면 둘 다 막힌다.
                // 같을 때 대입을 건너뛰는 것이 핵심이다 — 안 그러면 한글 조합 중간 상태에서 되쓰기가 반복된다
                // (CredentialField 의 ASCII 필터가 남긴 그 선례).
                .onChange(of: text) { _, newValue in
                    let cleaned = PokeMessageInputFilter.filtered(newValue)
                    guard cleaned != newValue else { return }
                    text = cleaned
                    triggerFilterWarning()
                }
                .onDisappear { filterWarningTask?.cancel() }
            Text(PokeMessageCounter.text(text))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(counterTint)
                .monospacedDigit()
                .fixedSize()
            Button(action: sendTyped) {
                Text("보내기")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .frame(height: 22)
                    .background(Capsule().fill(CheckTheme.accent.opacity(canSendTyped ? 1 : 0.35)))
            }
            .buttonStyle(.plain)
            .disabled(!canSendTyped)
            .help(sendHelp)
        }
        .padding(.horizontal, 9)
        .frame(height: Self.inputRowHeight)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(CheckTheme.fieldFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        // 초과는 테두리까지 빨갛게 — 카운터 글자만으로는 못 보고 지나친다.
                        .stroke(PokeMessageCounter.isOverflowing(text) ? CheckTheme.danger : CheckTheme.border, lineWidth: 1)
                )
        )
    }

    private var counterTint: Color {
        if PokeMessageCounter.isOverflowing(text) { return CheckTheme.danger }
        return PokeMessageCounter.isFull(text) ? CheckTheme.pending : CheckTheme.secondaryText
    }

    private var canSendTyped: Bool { isOpen && !isSending && PokeMessageCounter.isSendable(text) }

    /// 왜 못 보내는지를 사유별로 다르게 말한다. **.tooLong 과 .unsupportedCharacters 를 한 문구로 합치면 안 된다** —
    /// 이모지 하나에 대고 "3글자까지예요"라고 하면 사용자는 글자를 줄이고, 줄여도 계속 막힌다.
    private var sendHelp: String {
        if !isOpen { return blockedText?.text ?? "지금은 보낼 수 없어요" }
        switch MessageBody.validate(text) {
        case .ok: return "보내기"
        case .empty: return "보낼 말을 입력해 주세요"
        case .unsupportedCharacters: return Self.filterWarningText
        case .tooLong: return WorkTimerStore.messageTooLongNotice
        }
    }

    /// 전송. **원문을 그대로 넘긴다** — 정규화(NFC)와 길이·문자 판정은 네트워크 계층의 MessageBody 가
    /// 한 번만 한다(SupabaseWorkService.sendMessage). 여기서 미리 정규화해 넘기면 같은 일을 두 곳이 하게 되고,
    /// 규칙이 바뀌는 날 뷰만 옛 규칙으로 남는다. 치는 동안 길이를 자르지 않는 것도 같은 이유의 연장이다(IME 안전).
    private func sendTyped() {
        guard canSendTyped else { return }
        onSend(text)
    }
}

/// 팝오버 안의 '최근 받은 메시지 1건' 표시. 보낸이 별명 + 본문 + 언제 (+ 뒤에 더 있으면 "+N").
/// 캐릭터 말풍선(다른 담당)은 몇 초 뒤 사라지므로, 자리를 비운 사이 온 글자를 볼 수 있는 자리는 여기뿐이다.
struct PokeMessageReceiptStrip: View {
    let message: ReceivedMessage
    let now: Date
    /// 이 건 뒤에 대기 중인 건수(스토어 waitingMessageCount). 0이면 아무것도 그리지 않는다.
    var waitingCount: Int = 0

    static let height: CGFloat = 34

    /// "방금 / N분 전 / N시간 전"(순수 — 팀원 행의 "마지막 확인 N분 전"과 같은 눈금).
    static func ageText(receivedAt: Date, now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(receivedAt)))
        if seconds < 60 { return "방금" }
        if seconds < 3600 { return "\(seconds / 60)분 전" }
        return "\(seconds / 3600)시간 전"
    }

    var body: some View {
        HStack(spacing: 8) {
            CheckAvatarView(name: message.fromName, size: 22)
            Text("\(message.fromName)님")
                .font(.caption.weight(.semibold))
                .foregroundStyle(CheckTheme.primaryText)
                .lineLimit(1)
            // 본문 자체가 주인공이라 캡슐로 띄운다(이름·시각보다 한 급 크게).
            Text(message.body)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(CheckTheme.accent)
                .lineLimit(1)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Capsule().fill(CheckTheme.accent.opacity(0.16)))
                .fixedSize()
            if waitingCount > 0 {
                Text("+\(waitingCount)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(CheckTheme.secondaryText)
                    .fixedSize()
            }
            Spacer(minLength: 6)
            Text(Self.ageText(receivedAt: message.createdAt, now: now))
                .font(.caption2)
                .foregroundStyle(CheckTheme.secondaryText)
                .fixedSize()
        }
        .padding(.horizontal, 10)
        .frame(height: Self.height)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(CheckTheme.accent.opacity(0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(CheckTheme.accent.opacity(0.32), lineWidth: 1)
                )
        )
    }
}

// MARK: - 팝오버 시계 게이트 + 초단위 잎 (v0.2.38 α)

extension WorkTimerStore {
    /// 팝오버가 열려 있을 때만 초침을 따라가는 **잎 뷰용** 시계.
    ///
    /// 닫혀 있으면(isMenuPresented == false) displayNow 를 **아예 읽지 않고** 고정값을 돌려준다 — Observation 은
    /// "읽은 것"만 관찰 등록하므로, 닫힌 팝오버의 잎은 티커가 매초 displayNow 를 써도 무효화되지 않는다.
    /// isMenuPresented 자체는 관찰 대상이 아니라(@ObservationIgnored) 이 분기가 재평가를 만들지는 않는다:
    ///  · 열림→닫힘: 마지막으로 열린 채 평가된 잎은 displayNow 를 등록해 뒀으므로 **다음 한 틱**에 다시 평가되고,
    ///    그때 닫힌 가지로 옮겨 앉아 등록이 사라진다(그 뒤로는 조용하다).
    ///  · 닫힘→열림: 등록이 없어 setMenuPresented(true) 의 displayNow 갱신으로는 깨어나지 못한다 — 그래서
    ///    MenuClockLeaf 가 창의 키 상태(controlActiveState)에 의존해, 창이 다시 키를 얻는 순간 한 번 재평가된다.
    ///
    /// 고정값이 distantPast 인 이유: 닫힌 동안 시계가 "아직 시작 안 함"으로 읽히면 쿨타임은 전부 진행 중, 연결 경고는
    /// 꺼짐, 수신 시각은 "방금"이 된다 — 아무도 보지 않는 상태의 값이지만, 재오픈 첫 프레임에 혹시 한 번 보이더라도
    /// **찌를 수 있는 걸 못 찌르는 쪽**(안전한 쪽)으로 틀린다. distantFuture 면 반대로 쿨타임 중인 대상이 활성으로
    /// 보여 눌렀다가 서버 거절을 받는다. 게다가 pokeCooldownUntil 은 디렉토리를 받을 때마다 만료분이 지워지므로
    /// "진행 중"으로 읽히는 대상은 실제로 쿨타임 중인 사람뿐이다.
    var menuClockNow: Date {
        isMenuPresented ? displayNow : Self.menuClockFrozen
    }

    /// 닫힌 팝오버의 시계 값(위 주석). 테스트가 같은 값을 기대치로 쓴다.
    static let menuClockFrozen = Date.distantPast
}

/// 초 단위 값을 **이 뷰 안에서만** 읽게 하는 잎.
///
/// `read` 를 여기 body 에서 부르므로 그 안에서 읽은 store.displayNow(=menuClockNow) 의 관찰 등록은 이 잎에만 남고,
/// 부모(행·패널·팝오버 루트)는 매초 무효화되지 않는다. 팝오버 트리 안에서 초 단위 값이 필요한 자리는 **전부** 이 잎을
/// 거쳐야 한다 — 부모 body 에서 `read()` 를 한 번이라도 직접 부르면 그 부모부터 위로 초당 재평가가 되살아난다
/// (V0238MenuTests 가 루트/패널/행의 재평가 횟수를 잰다).
///
/// controlActiveState 를 읽는 이유는 값이 아니라 **재평가 시점**이다: 팝오버가 닫혀 있는 동안 menuClockNow 는
/// displayNow 를 읽지 않아 이 잎의 관찰 등록이 비는데, 그 상태로는 다시 열려도 스스로 깨어날 길이 없다.
/// 창이 키를 얻고 잃을 때 이 환경값이 바뀌므로(WindowAnchorAccessor 가 setMenuPresented 에 쓰는 것과 같은
/// 창 사건) 재오픈 순간 이 잎이 한 번 평가되고, 그 평가가 displayNow 를 다시 등록한다.
struct MenuClockLeaf<Value, Content: View>: View {
    /// 초 단위 값 읽기(쿨타임 잔여 초·현재 시각·연결 경고 여부). **이 body 밖에서 부르지 마라.**
    let read: () -> Value
    @ViewBuilder let content: (Value) -> Content
    @Environment(\.controlActiveState) private var controlActiveState

    var body: some View {
        // 재오픈 트리거(위 주석). 값은 판정에 쓰지 않는다 — 헤드리스 렌더(ImageRenderer)의 기본값(.key)에 기대지 않기 위해서다.
        let _ = controlActiveState
        #if DEBUG
        let _ = PokePanelRenderProbe.noteLeafBody()
        #endif
        content(read())
    }
}

#if DEBUG
/// 테스트 전용 계측(DEBUG 빌드에만 존재 — 릴리스 경로는 이 타입을 모른다).
/// "displayNow 를 60번 밀어도 패널 body·정렬·행 본체는 0번, 잎만 60번"을 V0238MenuTests 가 여기서 읽는다.
@MainActor
enum PokePanelRenderProbe {
    /// PokePanel.body 평가 횟수.
    static var panelBodies = 0
    /// PokePanel 이 목록을 정렬한 횟수(body 당 정확히 1회여야 한다 — panelBodies 와 같아야 한다).
    static var sortCalls = 0
    /// PokeDirectoryRowView.body 평가 횟수(행 본체 — 초를 몰라야 한다).
    static var rowBodies = 0
    /// MenuClockLeaf.body 평가 횟수(초 단위 잎 — 매초 도는 유일한 자리).
    static var leafBodies = 0

    static func reset() {
        panelBodies = 0
        sortCalls = 0
        rowBodies = 0
        leafBodies = 0
    }
    static func notePanelBody() { panelBodies += 1 }
    static func noteRowBody() { rowBodies += 1 }
    static func noteLeafBody() { leafBodies += 1 }
}
#endif

/// 팀 카드 자리를 대체하는 콕찌르기 페이지(앱 로그인 사용자 전체). 리그/토큰 보드와 같은 뼈대다:
/// 뒤로 버튼 + 제목 + (조건부 안내줄) + 고정 행높이 리스트(maxVisibleRows 초과 시 스크롤). 행은 아바타 + 이름 +
/// 상태 칩(근무중/자리비움) + 우측 찌르기 버튼(손가락 아이콘: 가능=accent 원형, 쿨타임/내 비근무/대상 자리비움=흐린 비활성).
/// 자리비움 대상은 찌를 수 없다(서버 강제, 클라 선게이트). store 값을 값+클로저로만 받아 렌더 테스트 친화적으로 유지한다.
///
/// **초 단위 시계는 이 패널 body 가 읽지 않는다.** 쿨타임 잔여·수신 시각·연결 경고는 읽기 클로저로 받아 MenuClockLeaf
/// 안에서만 푼다 — 그래서 티커가 매초 다시 그리는 것은 행 속 버튼 하나·작성기·수신 줄·안내줄이고, 목록 정렬과 26행
/// 레이아웃은 입력(entries 등)이 바뀔 때만 돈다.
private struct PokePanel: View {
    // 근무중 먼저·이름순으로 정렬된 사용자 목록(store 에서 이미 정렬됨). 뷰에서도 같은 규약으로 다시 정렬한다.
    let entries: [PokeDirectoryEntry]
    // 내가 근무중인지. 비근무면 어떤 대상도 찌를 수 없다(서버 강제) — 안내줄 + 버튼 비활성으로 반영한다.
    let isMyselfWorking: Bool
    // 디렉토리 첫 성공 로드 여부. 빈 목록 문구를 '아직 없음'(true) vs 로드 전/실패 fallbackStatus(false)로 가른다.
    let hasLoaded: Bool
    // 아직 로드 전/실패 시 빈 목록 자리에 표시할 안내 문구(동기화 상태 문구).
    let fallbackStatus: String
    // 상단 1줄 안내(찌르기 실패 사유 등). 있으면 우선 노출한다(주황 계열).
    let notice: String?
    // 현재 시각 읽기(수신 메시지의 "방금/N분 전"). **패널 body 는 부르지 않는다** — 수신 줄 잎(MenuClockLeaf)이 부른다.
    // v0.2.37 까지는 `now: Date` 값이었고, 그 한 줄이 팝오버 루트에 displayNow 관찰을 등록해 트리 전체를 매초 돌렸다.
    let clock: () -> Date
    // 대상별 쿨타임 잔여 초 읽기(0이면 찌르기 가능). 행마다 `{ cooldownRemaining(entry.userID) }` 로 **다시 감싸서** 내리고,
    // 실제 호출은 행 속 찌르기 버튼 잎만 한다 — 여기서 값으로 풀면 이 패널 body 가 초당 재평가로 돌아간다.
    let cooldownRemaining: (String) -> Int
    let onPoke: (String) -> Void
    // 울트라 발사(3초 꾹). 일반 찌르기와 **다른 RPC**라 콜백을 나눠 받는다.
    // 3초를 다 누르면 canUltra 와 **무관하게** 호출된다 — 하루 한도는 서버가 판정한다(PokeChargeButton 주석).
    let onUltra: (String) -> Void
    // 내 울트라 **잔량**(재화 — 이월된다). nil = 아직 모름.
    // **표시 전용이다. 발사 게이트로 쓰지 마라** — 판정은 서버 ultra_poke_user 한 곳이고,
    // 잔량은 미션으로 **그날 중에 늘어난다**. 0이라고 클라가 막으면 미션을 채워 잔량이 생긴 뒤에도
    // 그 화면은 다음 sync 까지 계속 잠겨 있다(구버전 v0.2.30 이 정확히 그 결함이었다).
    let ultraBalance: Int?
    // 내가 **잔량 제한을 받지 않는가**(관리자). 서버 ultra_wallet_sync 가 말해 준 값을 스토어가 나른다.
    // 클라가 role 로 추측하지 않는다 — 그 판정은 서버 한 곳이다(WorkTimerStore.ultraUnlimited 주석).
    // 기본값 false 라 관리자가 아닌 사람의 화면은 지금과 **글자 하나까지 같다**.
    var ultraUnlimited: Bool = false
    // 잔량 배지 탭 → 울트라 화면(잔량 + 충전 경로). "0개인데 어떻게 채우죠?"의 답이 있는 유일한 자리다.
    var onOpenUltraPanel: () -> Void = {}
    // 찌르기 **수신** 연결이 끊겼는가(PokeConnectionNotice.shouldWarn 결과) 읽기. 안내줄 최우선 가지가 된다.
    // 판정이 시계를 읽으므로(재연결 유예 경과) 값이 아니라 클로저다 — 안내줄 잎(PokePanelNoticeLine)이 부른다.
    var isPokeDisconnected: () -> Bool = { false }
    // 집중 모드(내 수신 거부) 상태와 토글. 값+클로저로만 받아 이 패널을 렌더 테스트 친화적으로 유지한다.
    var isFocusMode: Bool = false
    var onToggleFocusMode: () -> Void = {}
    // 3글자 메시지 전송(대상 userID, 정규화된 본문).
    var onSendMessage: (String, String) -> Void = { _, _ in }
    // 대상별 메시지 쿨타임 잔여 초(0이면 보낼 수 있다). 찌르기와 **다른 서버 규칙**이라 클로저를 따로 받는다.
    var messageCooldownRemaining: (String) -> Int = { _ in 0 }
    // 전송 왕복 중(연타 잠금).
    var isSendingMessage: Bool = false
    // 메시지 전송 결과 1줄 안내. 찌르기 notice 와 **다른 칸**이라 따로 받는다(스토어가 상태를 나눠 둔 이유와 같다).
    var messageNotice: String? = nil
    // 최근 받은 메시지 1건. nil 이면 그 자리를 아예 만들지 않는다(빈 상자는 예산만 먹는다).
    var latestMessage: ReceivedMessage? = nil
    // 그 뒤로 대기 중인 수신 건수("+N" 표시용).
    var waitingMessageCount: Int = 0
    // 스냅샷 전용: 이 사용자의 작성기가 펼쳐진 상태로 그린다(버튼 클릭을 대신). 앱은 nil.
    var previewComposingUserID: String? = nil
    // 스냅샷 전용: 펼친 작성기의 입력칸에 미리 들어가 있는 값(글자 수 카운터 상태 재현). 앱은 "".
    var previewMessageDraft: String = ""
    let onBack: () -> Void
    // 목록 위쪽에서 배너/토큰 행이 먹은 높이(pt). 그만큼 무스크롤 표시 행수를 줄여 창 상한을 지킨다.
    var extraChromeHeight: CGFloat = 0
    // 스냅샷 전용: 초과 리스트를 ScrollView 대신 클립으로 그린다(ImageRenderer 육안 확인용). 앱은 false.
    var clipsOverflowInsteadOfScroll: Bool = false

    // v0.2.34: `@State isChargingUltra` 를 지웠다. 잔량이 배지로 **상시** 보이므로 "꾹 누르는 동안에만
    // 숫자를 말하는" 분기가 필요 없어졌고, 그 한 비트가 3초 홀드마다 이 패널(목록 26행 포함)을
    // 두 번 재평가하던 경로였다. 부수 정리가 아니라 이득이다.

    // 지금 메시지 작성기가 펼쳐진 대상(nil = 전부 접힘). **Optional 하나가 곧 "한 번에 한 행만" 규칙**이다 —
    // 행마다 Bool 플래그를 두면 26행이 동시에 펼쳐질 수 있고, 그 순간 목록 높이가 700pt 예산을 넘긴다.
    @State private var composingUserID: String?
    // 직접 입력 초안. 대상을 바꾸면 비운다(앞사람에게 쓰던 말이 뒷사람 칸에 남아 오발송되지 않게).
    @State private var draft: String = ""

    // 스냅샷 미리보기가 켜져 있으면 그 값이 이긴다. 파생 프로퍼티 한 줄이라 @State 시드용 init 이 필요 없다
    // — 같은 문제를 init 으로 푼 쪽(TeamCard 의 previewCodeRevealed → _showsInviteCode 시드)과 대비된다.
    // 시드는 "처음 한 번"이라 이후 토글이 미리보기를 덮지만, 이쪽은 미리보기가 늘 이겨 렌더가 결정적이다.
    private var activeComposerUserID: String? { previewComposingUserID ?? composingUserID }

    private var draftBinding: Binding<String> {
        previewComposingUserID == nil ? $draft : .constant(previewMessageDraft)
    }

    /// 펼침 한 덩어리가 목록에서 차지하는 높이(행 간격 포함). 접혀 있으면 0.
    private var composerBlockHeight: CGFloat {
        activeComposerUserID == nil ? 0 : PokeMessageComposer.height + Self.rowSpacing
    }

    // 행 고정 높이·간격. 아바타(26pt) + 이름/상태 칩 한 줄이라 팀원 행보다 낮게 둔다.
    private static let rowHeight: CGFloat = 48
    private static let rowSpacing: CGFloat = 8
    // 스크롤 없이 그대로 보여 주는 최대 인원. 행이 낮아(48pt) 7행까지 창 높이 상한(≤700pt) 안에 든다
    // (리스트 높이 7*48 + 6*8 = 384pt).
    static let maxVisibleRows = 7

    // 배너/토큰 행이 먹은 높이를 반영한 실제 무스크롤 표시 행수(기본은 maxVisibleRows).
    // 받은 메시지 줄도 목록 **위에** 얹히므로 같은 예산에 넣는다 — 안 넣으면 그 줄이 뜬 날만 창이 상한을 넘는다.
    private var visibleRows: Int {
        ListRowBudget.visibleRows(
            maxVisibleRows: Self.maxVisibleRows,
            rowHeight: Self.rowHeight,
            rowSpacing: Self.rowSpacing,
            extraChromeHeight: extraChromeHeight + receiptStripHeight
        )
    }

    private var receiptStripHeight: CGFloat {
        latestMessage == nil ? 0 : PokeMessageReceiptStrip.height + 12   // 바깥 VStack(spacing: 12) 포함
    }

    var body: some View {
        #if DEBUG
        let _ = PokePanelRenderProbe.notePanelBody()
        #endif
        // 정렬은 body 당 **1회**. 아래 rowCount/entryList/rows 가 이 결과를 나눠 쓴다 — 예전엔 computed 프로퍼티라
        // 한 body 에 세 번 정렬했고, 그 body 가 매초 돌았다. 정렬 키는 근무중 여부·이름뿐이라(쿨타임은 안 들어간다)
        // 초침이 순서를 바꿀 일도 없다 — 순서는 entries 가 바뀔 때만 바뀐다.
        let sorted = Self.sortedForDisplay(entries)
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                IconButton(icon: "chevron.left", help: "뒤로", action: onBack)
                Text("콕 찌르기")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(CheckTheme.primaryText)
                    .lineLimit(1)
                // 집중 모드 토글(수신 거부). 보내는 화면에 두는 이유는 사람들이 '찌르기'를 떠올리는 자리가
                // 여기뿐이라서다 — 설정을 따로 파면 켠 사실을 잊고, 끄는 길도 못 찾는다.
                IconButton(
                    icon: isFocusMode ? "moon.fill" : "moon",
                    help: isFocusMode ? "집중 모드 켜짐 — 누르면 찌르기를 다시 받아요" : "집중 모드 — 누르면 찌르기를 안 받아요",
                    tint: isFocusMode ? CheckTheme.accent : CheckTheme.secondaryText,
                    action: onToggleFocusMode
                )
                Spacer(minLength: 6)
                // 잔량 **상시** 표시. 예전엔 3초 꾹 누르는 동안에만 보였는데(PokeUltraHint 의 isCharging 분기),
                // 재화가 된 지금 그건 "지갑을 열어야만 잔고를 볼 수 있는" 설계다.
                // 새 줄이 아니라 제목 행의 남는 폭에 얹는다 — 줄을 하나 더하면 패널 높이가 커져
                // 창 높이 상한(700pt) 예산을 갉아먹는다(PokeTitleRowWidthBudget 이 그 폭을 지킨다).
                UltraBalanceBadge(
                    balance: ultraBalance,
                    // 무제한이면 숫자 대신 ∞ 를 그린다 — 새 줄을 만들지 않고 **같은 자리**에서 바뀐다.
                    isUnlimited: ultraUnlimited,
                    action: onOpenUltraPanel
                )
                // 발견성 문구는 그대로 산다. 0일 때만 "미션으로 충전"으로 갈아 끼워 **획득 경로**를 말한다.
                // 무제한인 사람에겐 그 갈아 끼움이 없다(채울 것이 없다).
                Text(UltraBalanceText.hint(balance: ultraBalance, unlimited: ultraUnlimited))
                    .font(.caption2)
                    .foregroundStyle(
                        CheckTheme.secondaryText
                            .opacity(ultraUnlimited || (ultraBalance ?? 1) > 0 ? 1.0 : 0.65)
                    )
                    .fixedSize()
            }
            PanelDivider()
            // 최근 받은 메시지 1건. 목록 위·안내줄 위다 — 남이 나에게 한 말이 내가 하려던 일보다 먼저 눈에 든다.
            // "방금/N분 전"은 시계를 읽는다 — 잎으로 가둬 매초 다시 그리는 것이 이 한 줄이 되게 한다.
            if let latestMessage {
                MenuClockLeaf(read: clock) { now in
                    PokeMessageReceiptStrip(message: latestMessage, now: now, waitingCount: waitingMessageCount)
                }
            }
            // 안내줄: notice 우선(주황), 없고 내가 비근무면 안내(회색), 근무중+notice nil 이면 생략(상단 앵커 유지).
            // 연결 끊김 판정이 시계를 읽으므로 줄 전체가 잎이다 — 어느 문구가 뜨는지, 뜨는지 자체를 잎이 정한다.
            PokePanelNoticeLine(
                isPokeDisconnected: isPokeDisconnected,
                messageNotice: messageNotice,
                notice: notice,
                isMyselfWorking: isMyselfWorking,
                isFocusMode: isFocusMode
            )
            entryList(sorted)
        }
        .padding(12)
        .panelStyle()
    }

    // 서버 정렬을 신뢰하지 않고 뷰에서도 근무중 먼저·이름순으로 다시 정렬한다. body 맨 위에서 **한 번만** 부른다.
    private static func sortedForDisplay(_ entries: [PokeDirectoryEntry]) -> [PokeDirectoryEntry] {
        #if DEBUG
        PokePanelRenderProbe.sortCalls += 1
        #endif
        return entries.sortedForPokeDisplay()
    }

    private static func rowCount(of sorted: [PokeDirectoryEntry]) -> Int {
        sorted.isEmpty ? 1 : sorted.count
    }

    // 리스트 높이 = 인원 비례. maxVisibleRows까지는 그대로 자라고(스크롤 없음), 초과하면 그 높이로 고정 후 스크롤.
    // **펼친 작성기도 이 안에서 자란다** — 리스트 총 높이 상한(capHeight)은 펼침 여부와 무관하므로,
    // 어떤 조합에서도 창 높이는 '접힌 7행'을 넘지 않는다(펼치면 보이는 행수가 줄고 나머지는 스크롤로 밀린다).
    @ViewBuilder
    private func entryList(_ sorted: [PokeDirectoryEntry]) -> some View {
        let capHeight = Self.listContentHeight(rowCount: visibleRows)
        let contentHeight = Self.listContentHeight(rowCount: Self.rowCount(of: sorted)) + composerBlockHeight
        if contentHeight <= capHeight {
            rows(sorted).frame(maxWidth: .infinity, alignment: .top)
        } else if clipsOverflowInsteadOfScroll {
            // 스냅샷 전용: 보이는 첫 부분만 클립해 그린다(ScrollView는 ImageRenderer가 못 그림).
            rows(sorted).frame(maxWidth: .infinity, alignment: .top)
                .frame(height: capHeight, alignment: .top)
                .clipped()
        } else {
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: true) {
                    rows(sorted).frame(maxWidth: .infinity)
                }
                .frame(height: capHeight)
                // 26명 목록에서 아래쪽 행을 펼치면 작성기가 보이는 창 밖에 생긴다 — 방금 누른 사람에게는
                // '아무 일도 안 일어난 것'과 구별되지 않는다. 펼친 덩어리를 스스로 끌어올린다.
                .onChange(of: composingUserID) { _, newValue in
                    guard let newValue else { return }
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo(Self.composerAnchorID(newValue), anchor: .bottom)
                    }
                }
            }
        }
    }

    /// 펼친 작성기의 스크롤 앵커 id. 행 id 와 겹치지 않게 접두어를 붙인다.
    private static func composerAnchorID(_ userID: String) -> String { "composer-\(userID)" }

    @ViewBuilder
    private func rows(_ sorted: [PokeDirectoryEntry]) -> some View {
        VStack(spacing: Self.rowSpacing) {
            if sorted.isEmpty {
                // 로드 성공했는데 비면 '아직 아무도 없음', 로드 전/실패면 fallbackStatus(동기화 상태 문구).
                Text(PokeDirectoryEmptyMessage.text(hasLoaded: hasLoaded, fallbackStatus: fallbackStatus))
                    .font(.caption)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: Self.rowHeight, alignment: .leading)
            } else {
                ForEach(sorted) { entry in
                    PokeDirectoryRowView(
                        entry: entry,
                        // 쿨타임 잔여 초는 **읽기 클로저**로 내린다 — 행이 아니라 행 속 찌르기 버튼 잎(MenuClockLeaf)이 부른다.
                        // 여기서 `cooldownRemaining(entry.userID)` 를 값으로 풀면 그 읽기가 이 패널 body 에 등록돼
                        // 목록 전체가 초당 재평가로 돌아간다(v0.2.37 까지의 결함 지점).
                        cooldownRemaining: { cooldownRemaining(entry.userID) },
                        canPoke: isMyselfWorking,
                        ultraBalance: ultraBalance,
                        ultraUnlimited: ultraUnlimited,
                        isComposing: activeComposerUserID == entry.userID,
                        onPoke: { onPoke(entry.userID) },
                        onUltra: { onUltra(entry.userID) },
                        onToggleCompose: { toggleCompose(entry.userID) }
                    )
                    .frame(height: Self.rowHeight)
                    if activeComposerUserID == entry.userID {
                        // 작성기는 남은 초를 **숫자로** 말하는 자리라("N초 뒤 가능") 초마다 그려야 맞다 — 잎으로 가둔다.
                        MenuClockLeaf(read: { messageCooldownRemaining(entry.userID) }) { remaining in
                            PokeMessageComposer(
                                targetName: entry.name,
                                text: draftBinding,
                                remainingCooldown: remaining,
                                // 행의 **메시지 버튼과 같은 게이트**다(내 근무 + 대상 근무 + 대상이 받을 수 있는 버전).
                                // 규칙이 갈라지면 버튼은 흐린데 입력칸은 살아 있는 화면이 생기고, 그 차이를 설명할 방법이 없다.
                                //
                                // ★ 펼쳐 둔 사이 폴링으로 canReceiveMessage 가 false 로 바뀌면 **접지 않고 여기서 잠근다**:
                                // 접으면 사용자가 치던 글자가 이유 없이 사라져 앱이 고장 난 것으로 읽히고, 폴링이 사용자의
                                // 화면을 접었다 폈다 하는 규칙이 새로 생긴다. 자리비움이 같은 순간에 하는 일도 이것뿐이라
                                // (이미 그렇게 돈다) 여기만 한 항 늘리면 두 사유가 같은 모양으로 멈춘다 — 머리줄이 사유를
                                // 말하고, 닫는 길은 작성기의 [x] 로 남는다(행 버튼은 그 순간 흐린 라벨이라 토글이 안 된다).
                                canSend: isMyselfWorking && entry.isWorking && entry.canReceiveMessage,
                                isSending: isSendingMessage,
                                onSend: { text in
                                    onSendMessage(entry.userID, text)
                                    // 보낸 값은 비운다 — 남아 있으면 쿨타임이 풀리는 순간 같은 말이 또 나간다.
                                    draft = ""
                                },
                                onCancel: { closeCompose() }
                            )
                        }
                        .id(Self.composerAnchorID(entry.userID))
                    }
                }
            }
        }
    }

    /// 메시지 진입점 토글. 다른 사람을 펼치면 **앞사람 칸은 닫히고 초안도 비운다** —
    /// 3글자는 짧아서, 남아 있던 말이 엉뚱한 사람에게 나가면 그게 곧 사고다.
    private func toggleCompose(_ userID: String) {
        if composingUserID == userID {
            closeCompose()
        } else {
            composingUserID = userID
            draft = ""
        }
    }

    private func closeCompose() {
        composingUserID = nil
        draft = ""
    }

    static func listContentHeight(rowCount: Int) -> CGFloat {
        guard rowCount > 0 else { return 0 }
        return CGFloat(rowCount) * rowHeight + CGFloat(rowCount - 1) * rowSpacing
    }
}

/// 콕찌르기 패널의 안내줄(연결 끊김 / 메시지 결과 / 찌르기 결과 / 비근무 / 집중 모드 중 하나, 없으면 아무것도 안 그린다).
///
/// 왜 잎인가: 연결 끊김 판정(isPokeDisconnected)이 시계를 읽는다(재연결 유예 경과 여부). 그 판정을 패널 body 에 두면
/// 패널이 매초 무효화된다 — PokeEntryIconButton/FooterSyncStatus 가 같은 이유로 잎이다. 줄이 **뜨는지 자체**도
/// 그 판정에 달려 있으므로 `if let` 까지 이 안에 있다(없으면 빈 뷰라 VStack 간격을 먹지 않는다).
private struct PokePanelNoticeLine: View {
    let isPokeDisconnected: () -> Bool
    let messageNotice: String?
    let notice: String?
    let isMyselfWorking: Bool
    let isFocusMode: Bool

    var body: some View {
        MenuClockLeaf(read: isPokeDisconnected) { disconnected in
            if let line = Self.line(
                disconnected: disconnected,
                messageNotice: messageNotice,
                notice: notice,
                isMyselfWorking: isMyselfWorking,
                isFocusMode: isFocusMode
            ) {
                Text(line.text)
                    .font(.caption2)
                    .foregroundStyle(line.isWarning ? CheckTheme.pending : CheckTheme.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // 안내줄 내용/톤(순수). notice 가 있으면 그것을(주황), 없고 비근무면 근무 안내(회색), 그다음 집중 모드 상태,
    // 셋 다 아니면 nil(생략 — 상단 앵커 유지). 비근무 안내가 집중 모드보다 앞인 이유는 그것이 **지금 이 화면에서
    // 하려는 일**(찌르기)의 차단 사유이기 때문이다. 집중 모드는 내 수신 설정이라 정보에 가깝다.
    static func line(
        disconnected: Bool,
        messageNotice: String?,
        notice: String?,
        isMyselfWorking: Bool,
        isFocusMode: Bool
    ) -> (text: String, isWarning: Bool)? {
        // 연결이 끊겼으면 그게 **가장 먼저**다. 이 화면에서 하려는 일이 양방향 모두 막힌 상태이고,
        // 전송 실패 문구(messageNotice/pokeNotice)는 그 결과일 뿐이라 원인을 가리면 안 된다.
        // 받기의 차단 사유가 보내기의 차단 사유보다 앞이다 — 보낸 사람은 실패를 보지만,
        // 못 받은 사람은 아무 일도 안 일어난 것과 구별할 방법이 없다.
        if disconnected {
            return (PokeConnectionNotice.panelText, true)
        }
        // 메시지 결과가 찌르기 결과보다 앞이다 — 메시지는 사용자가 글자를 골라 넣은 **뒤**의 답이라
        // 그 답이 안 보이면 "보내진 건가?"가 남는다. 스토어가 두 문구를 다른 칸에 담아 둔 덕에
        // 여기서 순서만 정하면 되고, 어느 쪽도 상대를 지우지 않는다.
        if let messageNotice, !messageNotice.isEmpty {
            return (messageNotice, true)
        }
        if let notice, !notice.isEmpty {
            return (notice, true)
        }
        if !isMyselfWorking {
            return ("근무 중일 때만 콕 찌를 수 있어요", false)
        }
        if isFocusMode {
            return (PokeFocusNotice.text, false)
        }
        return nil
    }
}

/// 콕찌르기 한 행 = 좌측 세로 해시색 바(유저 컬러 포인트) + 아바타 + 이름 + 상태 칩(근무중/자리비움) + 우측 찌르기 버튼.
/// 상태 칩은 근무중이면 초록 점+"근무중", 아니면 회색 "자리비움". 찌르기 버튼은 손가락 아이콘: 가능(accent 원형·눌림 탄성),
/// 쿨타임 중/내가 비근무/대상이 자리비움(흐린 비활성 아이콘, 숫자 없음). 자리비움 대상은 찌를 수 없다(서버 강제).
private struct PokeDirectoryRowView: View {
    let entry: PokeDirectoryEntry
    // 이 대상 쿨타임 잔여 초 읽기(0이면 쿨타임 아님). **행 본체는 부르지 않는다** — 찌르기 버튼 잎(MenuClockLeaf)만 부른다.
    // 값(Int)으로 받던 시절엔 패널이 행마다 이 값을 풀어 넘겼고, 그게 패널 body 를 초당 재평가로 묶은 지점이었다.
    let cooldownRemaining: () -> Int
    // 내가 근무중이라 찌를 수 있는지. false면 버튼이 흐려지고 비활성된다.
    let canPoke: Bool
    // 내 울트라 잔량 — **툴팁 문구 분기 전용**이다. nil = 아직 모름(허용으로 읽는다).
    // 찌르기 자체의 활성 여부와도, 울트라 발사 여부와도 무관하다: 3초 홀드는 잔량과 **무관하게**
    // 무조건 발사되고 판정은 서버가 한다. 잔량 0 툴팁이 떠 있어도 누르면 요청은 나간다 —
    // 그 사이 미션으로 잔량이 늘었을 수 있고, 그걸 아는 것은 서버뿐이다.
    let ultraBalance: Int?
    // 무제한(관리자)이면 잔량 0 이어도 툴팁이 "없음"을 말하지 않는다 — 서버는 그래도 발사한다.
    var ultraUnlimited: Bool = false
    // 이 행 아래 메시지 작성기가 펼쳐져 있는지(버튼을 켜진 상태로 그린다).
    var isComposing: Bool = false
    let onPoke: () -> Void
    let onUltra: () -> Void
    // 메시지 작성기 펼침/접힘 토글. 펼침 자체는 아무것도 보내지 않는다(전송은 작성기 안에서만).
    var onToggleCompose: () -> Void = {}

    // 좌측 세로 바 색 — 아바타 이니셜과 동일한 이름 해시색(유저별 컬러 포인트).
    private var accentColor: Color { CheckTheme.avatarColor(for: entry.name) }

    var body: some View {
        #if DEBUG
        let _ = PokePanelRenderProbe.noteRowBody()
        #endif
        HStack(spacing: 10) {
            Capsule()
                .fill(accentColor)
                .frame(width: 3)
                .frame(maxHeight: .infinity)
                .padding(.vertical, 3)
            CheckAvatarView(name: entry.name, avatarURL: entry.avatarURL, size: 26)
            Text(entry.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(CheckTheme.primaryText)
                .lineLimit(1)
            statusChip
            Spacer(minLength: 6)
            // 메시지는 찌르기 **바로 왼쪽**, 같은 30pt 원형이다(같은 자리·같은 무게).
            // 다만 채움은 한 급 낮춘다 — 둘 다 accent 원형이면 어느 쪽이 이 화면의 주 동작인지 사라지고,
            // 손가락 아이콘의 '콕' 은 이 패널의 이름 그 자체다.
            messageButton
            pokeButton
        }
        .padding(.leading, 8)
        .padding(.trailing, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(CheckTheme.fieldFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(CheckTheme.border, lineWidth: 1)
        )
    }

    // 상태 칩: 근무중이면 초록 점+"근무중", 아니면 회색 "자리비움"(caption2).
    @ViewBuilder
    private var statusChip: some View {
        if entry.isWorking {
            HStack(spacing: 4) {
                Circle()
                    .fill(CheckTheme.working)
                    .frame(width: 6, height: 6)
                Text("근무중")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(CheckTheme.working)
            }
            .fixedSize()
        } else {
            Text("자리비움")
                .font(.caption2)
                .foregroundStyle(CheckTheme.secondaryText)
                .fixedSize()
        }
    }

    // 찌르기 버튼 — 손가락 아이콘. 여러 비활성 사유가 있지만 시각은 2가지: 가능(accent 원형·눌림 탄성)과 비활성(흐린 아이콘).
    // 쿨타임 잔여 초는 숫자로 그리지 않고, 쿨타임 중/내가 비근무/대상 자리비움 모두 흐린 비활성 아이콘으로 같은 계열로 표시한다.
    //
    // 쿨타임 잔여는 **이 잎 안에서만** 읽는다(MenuClockLeaf): 행 본체는 초를 모르고, 매초 다시 그리는 것은 이 30pt 원 하나다.
    // 만료 순간 활성으로 바뀌는 UX 는 그대로다 — 잎이 매초 `remaining > 0` 을 다시 판정한다.
    private var pokeButton: some View {
        MenuClockLeaf(read: cooldownRemaining) { remaining in
            pokeButton(remainingCooldown: remaining)
        }
    }

    @ViewBuilder
    private func pokeButton(remainingCooldown: Int) -> some View {
        if remainingCooldown > 0 {
            // 쿨타임 중 — 숫자 없이 흐린 비활성. 같은 대상 60초 쿨타임을 서버가 강제하고 여기선 미러링만 한다.
            pokeIconLabel(active: false)
                .help("잠시 후 다시 찌를 수 있어요")
        } else if !canPoke {
            // 내가 비근무 — 찌를 수 없다(서버 강제). 쿨타임과 같은 흐린 비활성 아이콘으로 표시.
            pokeIconLabel(active: false)
                .help("내가 근무 중일 때만 콕 찌를 수 있어요")
        } else if !entry.isWorking {
            // 대상이 자리비움 — 찌를 수 없다(서버 강제). 쿨타임/내 비근무와 같은 흐린 비활성 아이콘으로 표시.
            pokeIconLabel(active: false)
                .help("자리비움 상태에는 찌를 수 없어요")
        } else {
            // 가능 — 짧게 누르면 일반, 3초 꾹 누르면 울트라. 쿨타임 중·내가 비근무·대상 자리비움일 때는
            // 위 분기에서 Button 이 아니라 흐린 라벨(pokeIconLabel)로 그려지므로 **제스처 대상 자체가 없다** —
            // 그 상태의 꾹 누르기는 아무 일도 일어나지 않고 help 툴팁이 이유를 말한다(숨은 규칙을 만들지 않는다).
            PokeChargeButton(
                onPoke: onPoke,
                onUltra: onUltra
            )
            // 툴팁의 홀드 시간도 상수에서 만든다(힌트 문구와 같은 이유 — 두 곳에 숫자를 흩뿌리지 않는다).
            // 잔량이 없을 때의 문장은 "다 썼다"가 아니다: 그건 하루 몫 시절의 말이고, 지금은
            // 기다려도 안 찬다. **충전 경로를 말하는 문장**으로 갈아 끼웠다.
            .help(UltraBalanceText.rowTooltip(balance: ultraBalance, unlimited: ultraUnlimited))
        }
    }

    // 3글자 메시지 진입점 — 말풍선 아이콘. **찌르기와 같은 게이트**를 받는다(내 근무·대상 근무·쿨타임)
    // + 메시지에만 걸리는 게이트 하나(대상이 받을 수 있는 버전인가).
    // 비활성이어도 자리를 지키고 흐리게만 그린다: 버튼이 사라졌다 나타나면 행이 흔들리고,
    // 무엇보다 "여기서 메시지를 보낼 수 있다"는 사실 자체가 안 보이면 기능이 없는 것과 같다.
    // 펼쳐 두는 것 자체는 아무것도 보내지 않으므로 **쿨타임 중에도 펼칠 수 있다** — 그래야 작성기가
    // 남은 초를 말해 줄 수 있다(닫힌 채로는 왜 못 보내는지 알 길이 없다).
    @ViewBuilder
    private var messageButton: some View {
        if !canPoke {
            messageIconLabel(active: false)
                .help("내가 근무 중일 때만 메시지를 보낼 수 있어요")
        } else if !entry.isWorking {
            // 자리비움이 구버전보다 앞이다 — 이 사유는 **같은 행의 찌르기 버튼도 함께 막는** 사유라,
            // 뒤로 밀면 한 행에서 두 버튼이 서로 다른 이유를 말한다(찌르기는 "자리비움", 메시지는 "업데이트").
            // 자리비움이 풀리면 그때 구버전 사유가 드러난다 — 그 순서가 사용자가 겪는 순서와 같다.
            messageIconLabel(active: false)
                .help("자리비움 상태에는 메시지를 보낼 수 없어요")
        } else if !entry.canReceiveMessage {
            // 대상이 구버전이라 3글자를 **받을 수 없다**. 보낸 뒤에 알려 주면 늦다 — 구버전 클라는 모르는
            // kind 를 일반 찌르기로 접고, take_pokes 는 서버 원자 소비라 그 3글자가 영영 사라진다.
            // 그래서 이 게이트는 화면에서 미리 잠그고, 찌르기는 **건드리지 않는다**(구버전도 찔림은 받는다).
            // 문구는 스토어 상수를 그대로 쓴다 — 같은 사정을 설명하는 문장이 두 개가 되는 순간
            // 보내기 전(툴팁)과 보낸 뒤(안내줄)가 서로 다른 말을 하게 된다.
            messageIconLabel(active: false)
                .help(WorkTimerStore.messageTargetOutdatedNotice)
        } else {
            Button(action: onToggleCompose) {
                messageIconLabel(active: true)
            }
            .buttonStyle(PokePressButtonStyle())
            .help(isComposing ? "메시지 접기" : "\(MessageBody.maxCharacters)글자 메시지 보내기")
            .accessibilityLabel("\(MessageBody.maxCharacters)글자 메시지 보내기")
        }
    }

    // 말풍선 라벨. 활성은 accent 글자 + 옅은 accent 원형(찌르기의 꽉 찬 accent 보다 한 급 낮은 무게),
    // 펼친 동안은 채움을 올려 '지금 이 행이 열려 있다'를 행에서도 읽히게 한다.
    private func messageIconLabel(active: Bool) -> some View {
        Image(systemName: "text.bubble.fill")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(active ? CheckTheme.accent : CheckTheme.secondaryText.opacity(0.45))
            .frame(width: 30, height: 30)
            .background(
                Circle().fill(
                    active
                        ? CheckTheme.accent.opacity(isComposing ? 0.38 : 0.18)
                        : Color.white.opacity(0.06)
                )
            )
    }

    // 손가락 아이콘 라벨(활성/비활성 공유). 활성이면 accent 원형 배경·흰 아이콘, 비활성이면 흐린 아이콘만.
    // 원형 지름 30 — IconButton 감각(27)과 비슷하게, 행 높이 48 안에 자연스럽게 들어간다.
    private func pokeIconLabel(active: Bool) -> some View {
        Image(systemName: "hand.point.right.fill")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(active ? .white : CheckTheme.secondaryText.opacity(0.45))
            .frame(width: 30, height: 30)
            .background(
                Circle().fill(active ? CheckTheme.accent : Color.white.opacity(0.06))
            )
    }
}

/// 콕 찌르기 버튼 — 짧게 누르면 일반, 3초 꾹 누르면 울트라. 누르는 동안 원형이 파랑→빨강으로 물들고
/// 바깥 링이 시계방향으로 차오른다.
///
/// **진행도를 뷰 로컬 @State 에 가두는 이유**: store 는 @Observable 이라 값이 바뀔 때마다 그 값을 읽는
/// 팝오버 트리 전체(팀 목록·리그·배너·타이머)가 재평가된다. 3초짜리 진행값을 거기 두면 그 재평가가
/// 애니메이션 프레임마다 일어난다. 여기 State 에 두면 재평가 범위가 이 버튼 하나로 끝난다.
/// 패널로 올려보내는 것도 진행도가 아니라 **켜짐/꺼짐 한 비트**뿐이다(누름당 2~3회).
///
/// **타이머로 진행도를 올리지 않는 이유**: withAnimation 한 번이면 SwiftUI 가 보간하므로 상태 변경은
/// 시작 1회·종료 1회다. 타이머면 60Hz × 3초 = 180회다.
///
/// **LongPressGesture 를 쓰지 않는 이유**: 그건 최소 지속시간을 넘긴 '순간'만 알려 주고 경과 비율을 주지
/// 않아 "점점 빨개짐"을 만들 수 없다. DragGesture(minimumDistance: 0) 은 마우스 다운 즉시 onChanged 가
/// 한 번 오고 업에서 onEnded 가 온다. 대신 **커서가 뷰 밖으로 나가도 이벤트가 계속 오므로 취소는
/// 우리가 좌표로 판정해야 한다**.
private struct PokeChargeButton: View {
    let onPoke: () -> Void
    /// 3초 홀드 완료. **조건 없이** 호출된다 — 잔량 판정은 서버 몫이다(beginCharge 주석 참조).
    /// 그래서 이 버튼은 잔량도 하루 한도도 **아예 받지 않는다**: 안 가진 값으로는 게이트를 만들 수 없다.
    /// v0.2.34 에서 사실의 이름이 canUltra → ultraBalance 로 바뀌었지만 규칙은 그대로다.
    let onUltra: () -> Void

    @State private var charge: CGFloat = 0
    @State private var isPressing = false
    @State private var didFireUltra = false     // 발사 후 손을 뗄 때 일반 찌르기가 겹쳐 나가는 것을 막는 래치
    @State private var isCancelled = false      // 버튼 밖으로 나간 누름. 되돌아와도 되살아나지 않는다
    @State private var chargeTask: Task<Void, Never>?

    static let ultraHoldSeconds: Double = UltraChargeStyle.holdSeconds
    private static let diameter: CGFloat = 30
    /// 커서가 이만큼 벗어나야 취소한다. 0 이면 1pt 손떨림에도 3초 충전이 날아간다.
    private static let cancelSlop: CGFloat = 8

    var body: some View {
        Image(systemName: "hand.point.right.fill")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: Self.diameter, height: Self.diameter)
            .background(Circle().fill(UltraChargeStyle.fillColor(charge: charge)))
            .overlay(
                Circle().trim(from: 0, to: charge)
                    .stroke(.white.opacity(0.9), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(-3)          // overlay 라 레이아웃 높이에 영향 없음(행 48pt 예산 불변)
            )
            .scaleEffect(UltraChargeStyle.scale(charge: charge, isPressing: isPressing))
            .contentShape(Circle())
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("콕 찌르기")
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { handleChanged(at: $0.location) }
                .onEnded { _ in handleEnded() })
            // 팝오버가 닫히거나 목록이 갱신돼 이 행이 사라지면 onEnded 가 영영 안 온다.
            // 이 줄이 없으면 3초 Task 가 살아남아, 화면에 없는 버튼이 울트라를 발사한다(하루치 몫 소멸).
            .onDisappear {
                cancelCharge(animated: false)
                isPressing = false
            }
    }

    private func handleChanged(at location: CGPoint) {
        if !isPressing {
            // 눌림 dip 은 자기 트랜잭션으로 분리한다. 같은 업데이트에 섞으면 3초짜리 트랜잭션이
            // 1.0→0.86 까지 3초에 걸쳐 끌고 가 버튼이 죽은 것처럼 보인다.
            withAnimation(.spring(response: 0.22, dampingFraction: 0.55)) { isPressing = true }
            didFireUltra = false
            isCancelled = false
            beginCharge()
            return
        }
        guard !isCancelled else { return }
        let bounds = CGRect(x: 0, y: 0, width: Self.diameter, height: Self.diameter)
            .insetBy(dx: -Self.cancelSlop, dy: -Self.cancelSlop)
        if !bounds.contains(location) {
            // 한 번 나가면 이번 누름은 끝이다 — 되돌아왔을 때 '이어서 충전'과 '처음부터'는 어느 쪽도
            // 사용자가 예측할 수 없으므로 규칙을 하나로 못 박는다.
            isCancelled = true
            cancelCharge(animated: true)
        }
    }

    private func handleEnded() {
        let cancelled = isCancelled, fired = didFireUltra
        withAnimation(.spring(response: 0.22, dampingFraction: 0.55)) { isPressing = false }
        cancelCharge(animated: true)
        guard !cancelled, !fired else { return }
        onPoke()          // 3초 전에 뗐다 → 평소의 일반 찌르기
    }

    private func beginCharge() {
        chargeTask?.cancel()
        // easeOut 은 3.0s 정확히에 1 에 도달하므로 Task.sleep(3s) 발사 시각과 링이 꽉 차는 시각이
        // 일치하면서도 앞이 빠르다("점점 빨개짐"이 손에서 느껴진다).
        withAnimation(.easeOut(duration: Self.ultraHoldSeconds)) { charge = 1 }
        // 발사 시각의 권위는 이 Task 다. 애니메이션 완료 콜백에 기대면 창이 안 그려지는 동안 영영 안 온다.
        chargeTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.ultraHoldSeconds))
            guard !Task.isCancelled, isPressing, !isCancelled else { return }
            didFireUltra = true
            // 3초를 다 눌렀으면 **무조건** 발사한다. 하루 한도 판정은 서버 한 곳에만 있다.
            //
            // 예전에는 여기서 `if canUltra` 로 갈라 소진 상태면 안내만 띄웠다. 서버가 **같은 팀 대상에는
            // 하루 한도를 적용하지 않게** 된 순간(WorkTimerStore.ultraPokeDailyLimit 주석) 그 줄은 기능을
            // 통째로 무력화하는 접착식 잠금이 됐다: 팀 밖 대상에게 한 번 거절당해 미러가 서면, 서버가
            // 허락하는 팀원 울트라까지 **요청조차 나가지 않는다**(앱 재시작이나 KST 자정에나 풀린다).
            // 화면은 3초를 다 채워 빨갛게 물들었는데 아무 일도 없는, 사용자가 원인을 알 수 없는 고장이다.
            //
            // 팀 판정을 여기서 흉내 내는 길도 택하지 않았다(클라가 팀 목록을 이미 알더라도). 판정이 두 곳에
            // 있으면 언젠가 갈리고, 그때 화면은 서버가 허락한 발사를 막거나 막을 발사를 허락한다.
            // 대가는 정말 소진된 날의 헛요청 1회뿐이고, 그 경우 서버가 ultra_used_today 로 거절해
            // 스토어가 **예전과 같은 문구**(WorkTimerStore.ultraSpentNotice)를 안내줄에 세운다 — 사용자가
            // 보는 결과는 왕복 한 번 뒤에 오는 같은 문장이다(새 문구를 만들지 않은 이유).
            //
            // canUltra 는 이 버튼에 더 이상 오지 않는다 — 표시(제목 행 힌트·행 툴팁)는 부모가 그리고,
            // 여기 남겨 두면 다음 사람이 "버튼이 아는 값이니 게이트로 쓰자"고 이 줄을 되살린다.
            onUltra()
            withAnimation(.easeOut(duration: 0.2)) { charge = 0 }   // 손을 뗄 때까지 '다 참'이 남지 않게
        }
    }

    private func cancelCharge(animated: Bool) {
        chargeTask?.cancel(); chargeTask = nil
        if animated { withAnimation(.easeOut(duration: 0.15)) { charge = 0 } } else { charge = 0 }
    }
}

// MARK: - Personal insights page (지난주 회고 + 근무 리듬 히트맵)

/// 개인 기록 패널의 자리 문구 판정(순수 로직, 결정적 검증 지점). 로드 전에는 fallbackStatus(syncMessage) 를
/// 재사용하지 않고 "불러오는 중…"을 쓴다 — 본문 자리에 "동기화됨"이 떠 있으면 무슨 뜻인지 알 수 없다는
/// 전면 감사 지적을 반영한 것(리그/보드의 fallbackStatus 관례와 의도적으로 다르다).
/// 개인 기록 패널의 본문 표시 높이 예산(순수 계산 — 결정적 검증 지점).
///
/// 리그/토큰/찌르기/팀 목록은 배너·목표 편집 행이 먹은 높이를 ListRowBudget 으로 **행수**에서 깎는다. 이 패널은
/// 행 기반이 아니라(회고 카드 + 7×24 히트맵 + 13×7 잔디 고정 높이) 깎을 행이 없으므로, 대신 본문 표시 높이를 잘라
/// 스크롤로 넘긴다. 팝오버는 위가 고정돼 아래로만 자라므로(CheckWindowAnchor) 상한(700pt)을 넘긴 만큼은
/// 푸터(로그아웃/앱 종료)와 잔디 하단이 화면 밖으로 잘려 손이 닿지 않는다.
enum InsightsPanelChromeBudget {
    /// 본문(회고 카드 + 구분선 + 히트맵 + 구분선 + 12주 잔디)의 자연 높이(pt). 340pt 폭 ImageRenderer 실측값:
    /// 잔디 전 307pt(창 577pt) → 잔디(구분선 + 캡션 + 월 라벨 + 7행×16pt) 후 창 757pt, 차이 180pt 를 더한 487pt.
    static let contentNaturalHeight: CGFloat = 487
    /// 크롬이 하나도 없을 때 창 상한(700pt)까지 남는 여유(pt) = 700 − 기본 상태 실측 창 높이 − 5pt 안전 여유.
    /// 잔디가 붙으면서 본문 자연 높이만으로 상한을 넘겨 **음수**가 됐다(700 − 757 − 5): 크롬이 없어도 본문을
    /// 62pt 깎아 스크롤로 넘기고, 그 위에 얹히는 배너/목표 편집 행은 그만큼 더 깎는다(창은 늘 695pt 에 멈춘다).
    /// 회고 카드 + 히트맵(307pt)은 깎인 뒤에도 온전히 보이고, 잔디는 첫 몇 행이 보여 아래에 더 있음을 알린다.
    static let chromeSlack: CGFloat = -62
    /// 지난주가 비었을 때(회고 카드는 빈 줄 한 줄, 히트맵은 빈 격자에 피크 문구 없음)의 본문 자연 높이(pt).
    /// 340pt 폭 실측 창 660pt − 본문 밖 270pt. 이 상태는 잔디에만 기록이 있는 사용자(지난주 휴가)가 매주 만나는
    /// 화면이라 따로 잰다 — 큰 본문 기준 예산을 그대로 쓰면 스크롤 높이(425pt)가 본문(390pt)보다 커서
    /// 패널 바닥에 35pt 빈 띠가 늘 남는다.
    static let contentNaturalHeightWithoutLastWeek: CGFloat = 390
    /// 아무리 깎여도 본문에 남기는 최소 높이(회고 카드 한 장은 보이도록).
    static let minContentHeight: CGFloat = 190

    /// 본문 표시 높이(nil 이면 자연 높이 그대로 — 스크롤 없음). 여유(chromeSlack)는 가장 큰 본문 기준으로 잰 값이라,
    /// 본문이 그보다 짧은 만큼(naturalHeight 가 작은 만큼) 여유가 늘어난다 — 지난주가 빈 본문은 크롬이 없으면
    /// 여유가 양수(+35)로 돌아와 깎지 않고, 기본 본문은 여유가 음수라 크롬이 없어도 깎는다.
    static func capHeight(extraChromeHeight: CGFloat, naturalHeight: CGFloat = contentNaturalHeight) -> CGFloat? {
        let slack = chromeSlack + (contentNaturalHeight - naturalHeight)
        let overflow = extraChromeHeight - slack
        guard overflow > 0 else { return nil }
        return max(minContentHeight, naturalHeight - overflow)
    }
}

/// 개인 기록 패널 본문 자리 문구 선택(순수 로직, 결정적 검증 지점).
/// 세 상태를 명확히 가른다: (1) 아직 응답 전 → "불러오는 중…", (2) 조회 실패 → 실패 문구(+[다시 시도] 버튼),
/// (3) 로드 완료인데 지난주 누적 0 → "지난주 근무 기록이 없어요". 토큰 보드(TokenBoardEmptyMessage)와 같은 대칭이다 —
/// 실패에 상태를 세우지 않던 시절엔 실패해도 "불러오는 중…"이 팝오버를 닫을 때까지 남아, 기다림과 실패를
/// 구분할 수 없고 패널 안에서 재시도할 방법도 없었다(회귀 지점).
enum InsightsEmptyMessage {
    static let loading = "불러오는 중…"
    /// 회고 카드가 비었을 때의 한 줄.
    static let noRetro = "지난주 근무 기록이 없어요"
    /// 본문 전체를 대체하는 자리 문구. 패널 본문(회고 카드 + 히트맵)이 이제 **둘 다 지난주 기준**이라,
    /// 지난주가 비면 그릴 것이 하나도 없다 — 그래서 회고 카드의 빈 줄과 같은 문장을 쓴다(자리 문구는 본문을
    /// 통째로 대체하므로 두 문장이 함께 뜨는 일은 없다). 8주 합산 시절의 "아직 기록이 쌓이지 않았어요"는
    /// 이번 주에만 근무한 사용자(=가입 첫 주)에게 거짓이 된다 — 헤더는 이번 주 누적을 시간 단위로 세고 있다.
    static let noData = noRetro
    static let loadFailed = "기록을 불러오지 못했어요"

    /// 본문 대신 보여 줄 자리 문구. nil 이면 실제 내용(회고 카드 + 히트맵)을 그린다.
    static func text(hasLoaded: Bool, hasFailed: Bool = false, totalSeconds: Int) -> String? {
        if !hasLoaded { return hasFailed ? loadFailed : loading }
        // 한 번이라도 성공한 뒤 마지막 조회가 실패했고 보여 줄 기록이 하나도 없으면 "기록이 없다"고 단정하지 않는다 —
        // insightsLoaded 는 성공 후 false 로 되돌아가지 않으므로(로드 완료 + 실패 + 누적 0) 조합이 성립하는데,
        // 이건 대개 '가입 첫날 0건으로 로드해 둔 스냅샷 + 이후 조회 실패'다(서버엔 한 주치 기록이 있는데 못 읽은 상태).
        // 예전엔 이 조합에서 "기록이 없다"는 단정 옆에 [다시 시도]가 함께 떠 서로 모순된 화면이 됐다(회귀 지점).
        if totalSeconds == 0 { return hasFailed ? loadFailed : noData }
        return nil
    }
}

/// 팀 카드 자리를 대체하는 개인 기록 페이지. 리그/토큰/찌르기와 4자 상호 배타이며 본인 데이터만 쓴다.
/// 위에서부터 (a) 지난주 회고 카드, (b) 요일×시간대 근무 리듬 히트맵 — **둘 다 같은 주(지난주)**를 그린다 —
/// 그리고 (c) 최근 12주 일별 근무 잔디(이번 주까지). 값만 받아 그리므로(스토어 미참조)
/// 렌더 테스트가 픽스처만으로 모든 상태를 재현할 수 있다.
private struct InsightsPanel: View {
    let heatmap: WorkRhythmHeatmap
    let retro: WeeklyRetro?
    // 최근 12주 일별 잔디. heatmap/retro 와 같은 조회에서 함께 계산된다.
    let dailyGrid: WorkDailyGrid
    // 첫 성공 로드 여부. false 면 "불러오는 중…"(syncMessage 재사용 금지).
    let hasLoaded: Bool
    // 마지막 조회가 실패로 끝났는지. true 면 로딩 문구 대신 실패 문구 + [다시 시도] 를 그린다.
    var hasFailed: Bool = false
    // [다시 시도] 액션. nil 이면 버튼을 그리지 않는다(값+클로저 규약 — 렌더 테스트가 스토어 없이 재현 가능).
    var onRetry: (() -> Void)? = nil
    // 목록 위쪽에서 배너/목표 편집 행이 먹은 높이(pt). 다른 네 패널은 이 값으로 무스크롤 행수를 줄이지만
    // 이 패널은 행 기반이 아니므로(회고 카드 + 7×24 히트맵 고정 높이) 본문 표시 높이를 잘라 스크롤로 넘긴다.
    var extraChromeHeight: CGFloat = 0
    // 스냅샷 전용: 넘치는 본문을 ScrollView 대신 클립으로 그린다(ImageRenderer 육안 확인용). 앱은 false.
    var clipsOverflowInsteadOfScroll: Bool = false
    let onBack: () -> Void

    // 0=월 … 6=일. buckets 행 순서/회고 busiestDayIndex 와 같은 규약.
    private static let dayNames = ["월", "화", "수", "목", "금", "토", "일"]

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                IconButton(icon: "chevron.left", help: "뒤로", action: onBack)
                Text("내 기록")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(CheckTheme.primaryText)
                    .lineLimit(1)
                Spacer(minLength: 6)
            }
            PanelDivider()
            // 자리 문구의 '보여 줄 기록' 총량에 잔디 누적도 더한다 — 지난주가 비었어도(휴가) 최근 12주에 기록이
            // 있으면 본문을 그려야 잔디가 보인다(회고 카드는 자기 빈 줄로 "지난주 근무 기록이 없어요"를 말한다).
            if let placeholder = InsightsEmptyMessage.text(
                hasLoaded: hasLoaded,
                hasFailed: hasFailed,
                totalSeconds: heatmap.totalSeconds + dailyGrid.totalSeconds
            ) {
                HStack(spacing: 8) {
                    Text(placeholder)
                        .font(.caption)
                        .foregroundStyle(CheckTheme.secondaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    // 실패했을 때만 재시도를 준다 — 팝오버를 닫았다 다시 여는 것 말고는 재시도 경로가 없었다.
                    if hasFailed, let onRetry {
                        PanelRetryButton(action: onRetry)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            } else {
                insightsBody
            }
        }
        .padding(12)
        .panelStyle()
    }

    /// 회고 카드 + 히트맵 + 12주 잔디 본문. 자연 높이만으로 창 상한을 넘기므로 크롬이 없어도 예산이 정한 높이로
    /// 낮춰 스크롤로 넘긴다(InsightsPanelChromeBudget) — 팝오버는 위가 고정되고 아래로만 자라므로(CheckWindowAnchor)
    /// 상한을 넘긴 만큼 푸터가 화면 밖으로 잘린다. 배너/목표 편집 행이 얹히면 그만큼 더 낮춘다.
    @ViewBuilder
    private var insightsBody: some View {
        let content = VStack(spacing: 12) {
            retroCard
            PanelDivider()
            heatmapSection
            PanelDivider()
            dailyGridSection
        }
        // 지난주가 비면(회고 nil ⇔ 히트맵 0 — 같은 세션에서 나오므로 늘 함께 간다) 본문이 97pt 짧다 — 그 높이로 예산을 잰다.
        let naturalHeight = retro == nil
            ? InsightsPanelChromeBudget.contentNaturalHeightWithoutLastWeek
            : InsightsPanelChromeBudget.contentNaturalHeight
        if let cap = InsightsPanelChromeBudget.capHeight(extraChromeHeight: extraChromeHeight, naturalHeight: naturalHeight) {
            if clipsOverflowInsteadOfScroll {
                // 스냅샷 전용: 자연 높이로 그린 뒤 위에서부터 cap 만큼만 남기고 잘라 낸다(ScrollView 는 렌더 불가).
                content
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, maxHeight: cap, alignment: .top)
                    .clipped()
            } else {
                // 높이를 명시로 못 박는다(리그/토큰/찌르기 목록과 같은 관례) — ScrollView 의 ideal 높이 추론에
                // 창 크기를 맡기지 않아야 팝오버 총높이가 상한 안에 결정적으로 들어온다.
                ScrollView(.vertical, showsIndicators: true) {
                    content.frame(maxWidth: .infinity)
                }
                .frame(height: cap)
            }
        } else {
            content
        }
    }

    // (a) 지난주 회고 카드 — 총 근무시간(크게) + 목표 대비 진행 + 전주 대비 증감 + 세션 수/가장 많이 일한 요일.
    @ViewBuilder
    private var retroCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CheckTheme.secondaryText)
                Text("지난주 회고")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(CheckTheme.primaryText)
                Spacer(minLength: 4)
                if let retro, retro.metGoal {
                    Label("목표 달성", systemImage: "checkmark.seal.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(CheckTheme.working)
                        .fixedSize()
                }
            }
            if let retro {
                Text("지난주 \(MenuBarStatusFormatter.hoursMinutes(retro.totalSeconds))")
                    .font(.system(.title3, design: .rounded).weight(.heavy))
                    .foregroundStyle(CheckTheme.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                // 목표 대비 진행 바 — 달성이면 working, 미달이면 accent(헤더 목표 바와 같은 관례).
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(CheckTheme.trackFill)
                        Capsule()
                            .fill(retro.metGoal ? CheckTheme.working : CheckTheme.accent)
                            .frame(width: max(0, proxy.size.width * Self.progress(retro)))
                    }
                }
                .frame(height: 5)
                Text(Self.goalLine(retro))
                    .font(.caption2)
                    .foregroundStyle(retro.metGoal ? CheckTheme.working : CheckTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let deltaLine = Self.deltaLine(retro) {
                    Text(deltaLine)
                        .font(.caption2)
                        .foregroundStyle(CheckTheme.secondaryText)
                        .lineLimit(1)
                }
                Text(Self.detailLine(retro))
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else {
                Text(InsightsEmptyMessage.noRetro)
                    .font(.caption)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(CheckTheme.fieldFill)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(CheckTheme.border, lineWidth: 1))
        )
    }

    // (b) 근무 리듬 히트맵 — 지난주 요일×시간대 격자 + 가장 활발했던 시간.
    @ViewBuilder
    private var heatmapSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "square.grid.3x3.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CheckTheme.secondaryText)
                Text("근무 리듬")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(CheckTheme.primaryText)
                Spacer(minLength: 4)
                // 위 회고 카드와 **같은 주**를 그린다는 사실이 드러나야 한다(예전엔 "최근 8주" 합산이라
                // 두 칸이 서로 다른 기간을 말하면서도 나란히 놓여 있었다).
                Text("지난주")
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .fixedSize()
            }
            WorkRhythmHeatmapGrid(heatmap: heatmap)
            if let peakText {
                Text("가장 활발한 시간: \(peakText)")
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .lineLimit(1)
            }
        }
    }

    // (c) 최근 12주 근무 잔디 — 주(열) × 요일(행), 이번 주까지. 캡션 오른쪽에 옅음→진함 범례.
    @ViewBuilder
    private var dailyGridSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "leaf.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(CheckTheme.secondaryText)
                Text("최근 12주 근무")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(CheckTheme.primaryText)
                Spacer(minLength: 4)
                ContributionLegendView(levels: Self.dailyGridLevels, color: CheckTheme.accent)
            }
            ContributionGridView(
                weeks: dailyGrid.weeks,
                values: dailyGrid.seconds,
                weekStart: dailyGrid.weekStart,
                isFuture: dailyGrid.isFuture(week:weekday:),
                // 분모는 하루 8시간 고정 — 히트맵의 3600초 고정과 같은 철학(자기 최대값 기준이면 기준이 흔들린다).
                denominator: WorkDailyGrid.fullDaySeconds,
                levels: Self.dailyGridLevels,
                color: CheckTheme.accent,
                valueText: { $0 > 0 ? MenuBarStatusFormatter.hoursMinutes($0) : "근무 없음" }
            )
        }
    }

    /// 잔디 농도 단계 수(옅음→진함 4단계 + 빈 칸).
    private static let dailyGridLevels = 4

    // "화요일 15시" — peakSlot(가장 진한 칸)의 표시 문구. 데이터가 없으면 nil(줄 자체를 생략).
    private var peakText: String? {
        guard let peak = heatmap.peakSlot, peak.day >= 0, peak.day < Self.dayNames.count else { return nil }
        return "\(Self.dayNames[peak.day])요일 \(peak.hour)시"
    }

    // 목표 대비 진행 비율(0~1 클램프). 게이지 폭 계산 전용 — 표시 퍼센트는 GoalPercentFormatter 를 쓴다.
    private static func progress(_ retro: WeeklyRetro) -> Double {
        let goal = max(1, retro.goalSeconds)
        return min(1, max(0, Double(retro.totalSeconds) / Double(goal)))
    }

    // 목표 대비 한 줄. 달성이면 축하 톤, 미달이면 퍼센트와 부족분을 함께 알려 준다.
    private static func goalLine(_ retro: WeeklyRetro) -> String {
        let goalText = MenuBarStatusFormatter.hoursMinutes(retro.goalSeconds)
        if retro.metGoal {
            return "목표 \(goalText) 달성 — 잘하셨어요"
        }
        // 미달 문맥 전용 퍼센트(99 상한). 반올림 퍼센트를 그대로 쓰면 같은 줄의 부족분과 어긋나
        // "100% · 0시간 18분 부족"이라는 자기모순 문장이 된다.
        let percent = GoalPercentFormatter.shortfallPercent(workedSeconds: retro.totalSeconds, goalSeconds: retro.goalSeconds)
        let remain = max(0, retro.goalSeconds - retro.totalSeconds)
        return "목표 \(goalText) 중 \(percent)% · \(MenuBarStatusFormatter.hoursMinutes(remain)) 부족"
    }

    // 전주 대비 증감. 전주 기록이 아예 없으면(0) 비교가 의미 없어 줄을 생략한다.
    private static func deltaLine(_ retro: WeeklyRetro) -> String? {
        guard retro.previousWeekSeconds > 0 else { return nil }
        let delta = retro.deltaSeconds
        if delta == 0 {
            return "전주와 같아요"
        }
        let sign = delta > 0 ? "+" : "-"
        return "전주 대비 \(sign)\(MenuBarStatusFormatter.hoursMinutes(abs(delta)))"
    }

    // "세션 11회 · 가장 많이 일한 날 화요일 8시간 12분".
    private static func detailLine(_ retro: WeeklyRetro) -> String {
        var parts = ["세션 \(retro.sessionCount)회"]
        if let day = retro.busiestDayIndex, day >= 0, day < dayNames.count, retro.busiestDaySeconds > 0 {
            parts.append("가장 많이 일한 날 \(dayNames[day])요일 \(MenuBarStatusFormatter.hoursMinutes(retro.busiestDaySeconds))")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Footer utility bar

// MARK: - 울트라 화면 (잔량 + 충전 경로)

/// 미션 줄의 문구·아이콘 규약(순수 — 값으로 검증한다).
///
/// **이름이 "미션 목록"이 아니라 "울트라"인 이유**: v0.2.34 시점 실제 미션은 1개(오늘 3시간)뿐이다.
/// 1행짜리 목록은 목록으로 안 읽히고 미완성으로 읽힌다. 이 화면이 답하는 질문은 "미션이 뭐가 있나"가
/// 아니라 **"울트라가 몇 개고 어떻게 채우나"**이고, 그 답(잔량 + 충전 경로 3줄)은 지금도 한 화면을 채운다.
enum MissionCopy {
    /// 미션 줄의 제목. **3시간 줄이 "마다"인 이유**: 그건 하루 한 번 끝나는 퀘스트가 아니라
    /// 그날 누적 3시간마다 다시 열리는 랩이다. "오늘 3시간"으로 적으면 한 번 채운 사람은 그날
    /// 남은 근무에서 더 받을 게 없다고 읽고, 실제로 두 번째·세 번째로 들어오는 울트라를
    /// 설명할 말이 화면에서 사라진다.
    static func title(_ kind: MissionProgress.Kind) -> String {
        switch kind {
        case .todayThreeHours: return "근무 3시간마다"
        case .dailyFloor:      return "매일 첫 근무"
        case .arrivalStreak:   return "연속 출근"
        }
    }

    static func icon(_ kind: MissionProgress.Kind) -> String {
        switch kind {
        case .todayThreeHours: return "clock.badge.checkmark"   // macOS 13+ (배포 타깃 14 ✓)
        case .dailyFloor:      return "sunrise.fill"
        case .arrivalStreak:   return "flame.fill"
        }
    }

    /// 보상 칩 문구. **nil = 이 줄에는 보상이 없다** → 칩을 아예 그리지 않는다.
    ///
    /// ★ 연속 출근이 nil 인 것이 사장님 확정 3이다: **스트릭은 표시만 하고 보상이 없다.**
    ///   서버 ultra_wallet_sync 는 스트릭으로 장부를 단 한 줄도 쓰지 않으며(그쪽 사후 단언이
    ///   'insert into ultra_ledger 개수 == 1' 로 못 박았다), 여기에 "5일마다 ⚡︎ +1" 같은 칩을 그리면
    ///   **없는 걸 약속하는 거짓말**이 된다. 5일째 되는 날 아무 일도 안 일어나고, 그때 사용자가
    ///   잃는 것은 울트라 하나가 아니라 이 화면 전체에 대한 신뢰다.
    ///
    /// ★ 밑바닥 보정을 "+1"로 쓰지 않는 이유: 그건 수입이 아니라 **바닥을 메워 주는 규칙**이다.
    ///   "+1"로 적으면 열흘 잠수 후 10개를 기대하게 되는데 실제로는 1개다(도장이 하루 하나뿐이라
    ///   보정도 한 번이다).
    static func reward(_ kind: MissionProgress.Kind) -> String? {
        switch kind {
        case .todayThreeHours: return "⚡︎ +1"
        case .dailyFloor:      return "0개면 1개로"
        case .arrivalStreak:   return nil
        }
    }

    /// "받음" 칩. **이 칩이 남는 자리는 밑바닥 보정(`dailyFloor`) 한 줄뿐이다** — 3시간 줄이
    /// 반복 지급으로 바뀌면서 서버가 그 줄의 `claimed` 를 **언제나 false 로 보낸다**(랩이 또
    /// 열려 있으니 "오늘 치는 받았다"로 닫을 수가 없다). 죽은 문구처럼 보여도 지우면 안 된다.
    static let claimedChip = "받음"
    /// 잔량 상한(사장님 확정 4)에 걸려 **적립하지 않은** 날의 칩.
    static let cappedChip = "가득 참"
    /// 그 사실을 말하는 문장. 이 줄이 없으면 화면은 진행 바를 100%로 그린 채 "아직 못 받았다"처럼
    /// 보이고, 사용자는 자기가 뭘 잘못했는지 영영 알 수 없다.
    ///
    /// ★ `capped` 는 "랩을 놓쳤다"가 아니라 **"지금 잔량이 상한 이상이다"** 를 뜻한다
    ///   (서버 20260901140000). 그래서 문장이 **현재형 경고**다 — 아직 아무것도 안 놓친 사람에게도
    ///   참이 되므로 과거형("놓쳤어요")은 거짓말이 된다.
    ///
    /// ★ 왜 상태로 바꿨나: 예전 의미("이번 호출에서 랩이 소멸했다")는 **순간적**이라 사실상 아무도
    ///   못 봤다. 가득 찬 사람이 3시간을 채우는 그 한 번의 sync 에서만 참이고 5분 뒤엔 사라지니,
    ///   팝오버를 마침 그때 열고 있어야만 보였다. 정작 계속 잃는 사람이 왜 잃는지 모르는 것이
    ///   경고의 실패다. 이제는 가득 찬 동안 계속 떠 있고, 한 발 쓰면 사라진다.
    ///
    /// ★ 소멸은 영구다: 서버가 상한에 걸린 랩에 `delta 0` 행을 적어 못 박으므로 **한 발 쓰고
    ///   되받을 유예가 없다.** 그래서 "쓰지 않으면"이라는 조건절이 진짜 조건이다 — 지금 쓰면
    ///   다음 3시간부터 다시 들어오고, 안 쓰면 그 랩은 영영 없다.
    static let cappedNotice = "가득 찼어요 — 쓰지 않으면 놓쳐요"

    /// 그 줄 아래 보조 문장. 상한에 걸린 날은 진행 시간 대신 **그 사실**을 말한다
    /// (그날의 진행률은 이미 100%라 시간을 말해 봐야 새로 알려 주는 것이 없다).
    static func detail(_ mission: MissionProgress) -> String {
        mission.cappedToday ? cappedNotice : mission.detail
    }

    /// 그 줄 오른쪽에 무엇을 그리는가. **순수 값이라 뮤테이션이 여기서 죽는다.**
    ///
    /// ★ `.capped` → `.claimed` → `.reward` 순서를 건드리지 마라. `.claimed` 가 죽은 가지처럼
    ///   보이는 것은 3시간 줄 때문인데(반복 지급이라 서버가 `claimed` 를 언제나 false 로 보내
    ///   그 줄에는 "받음" 칩이 더 이상 뜨지 않는다), 밑바닥 보정 줄은 여전히 `claimedToday` 로
    ///   이 가지를 탄다. 지우면 그쪽이 보상 칩("0개면 1개로")을 이미 받은 뒤에도 계속 그린다.
    static func chip(_ mission: MissionProgress) -> MissionChip {
        guard let reward = reward(mission.kind) else { return .none }
        if mission.cappedToday { return .capped }
        if mission.claimedToday { return .claimed }
        return .reward(reward)
    }
}

/// 미션 줄 오른쪽 칩의 종류. `.none` 은 "칩이 없다"이지 "빈 칩"이 아니다.
enum MissionChip: Equatable {
    case none
    case reward(String)
    case claimed
    case capped
}

enum UltraPanelCopy {
    static let title = "울트라"
    /// 잔량을 모를 때 그리는 글자. **0 으로 접지 않는다** — 0 이라고 말하면 그건 만들어 낸 사실이다.
    static let unknownBalance = "—"
    static let loadingCaption = "불러오는 중…"
    static let failedCaption = "최신 잔량을 못 읽었어요"
    static let emptyMissions = "충전 경로가 아직 없어요"

    /// 무제한(관리자)일 때 큰 글자 자리에 들어가는 말. **여기서는 기호를 쓰지 않는다** —
    /// 이 화면은 폭이 넉넉하고(히어로 카드 한 줄을 통째로 쓴다), 뜻을 곧이곧대로 말할 수 있는
    /// 유일한 자리다. 배지의 ∞ 가 무엇이었는지도 여기서 답을 얻는다.
    static let unlimitedBalance = "무제한"
    /// 무제한일 때의 보조 문장. 획득 경로("미션을 채우면")를 말하지 않는 것이 요점이다 —
    /// 채울 필요가 없는 사람에게 할 일을 만들어 주지 않는다.
    static var unlimitedCaption: String {
        "\(UltraChargeStyle.holdSecondsText)초 꾹 누르면 발사 — 잔량을 쓰지 않아요"
    }

    static func heroCaption(balance: Int?, hasFailed: Bool, unlimited: Bool = false) -> String {
        // ★ 무제한이 실패보다 **앞이다**. failedCaption 은 "최신 **잔량**을 못 읽었어요"인데,
        //   잔량이 뜻을 갖지 않는 사람에게 그 문장은 아무 정보도 아니고 불안만 만든다.
        //   sync 실패 사실 자체는 사라지지 않는다 — 미션 목록의 실패 문구와 [다시 시도] 버튼이
        //   hasFailed 로 따로 그려진다(그쪽은 관리자에게도 그대로 뜻이 있다).
        if unlimited { return unlimitedCaption }
        // 실패가 먼저다: 잔량은 남아 있어도(스토어가 알던 값을 버리지 않는다) 최신이라는 보장이 없다.
        if hasFailed { return failedCaption }
        guard let balance else { return loadingCaption }
        return balance > 0
            ? "\(UltraChargeStyle.holdSecondsText)초 꾹 누르면 한 개 써요"
            : "근무 3시간마다 하나씩 생겨요"
    }

    static func balanceText(_ balance: Int?, unlimited: Bool = false) -> String {
        if unlimited { return unlimitedBalance }
        return balance.map { String(max(0, $0)) } ?? unknownBalance
    }
}

/// 울트라 화면. 리그/토큰/찌르기/내 기록과 **같은 뼈대**다(뒤로 + 제목 + PanelDivider + 본문,
/// store 값을 값 + 클로저로만 받아 렌더 테스트 친화적으로 유지).
private struct UltraPanel: View {
    let balance: Int?
    /// 서버가 말해 준 무제한(관리자). 기본값 false — 안 넘기면 지금과 완전히 같다.
    var isUnlimited: Bool = false
    let missions: [MissionProgress]
    /// 미션을 한 번이라도 성공적으로 받았는가(빈 목록과 로드 전을 가른다 — 토큰 보드와 같은 규약).
    let hasLoaded: Bool
    var hasFailed: Bool = false
    /// 방금 미션을 달성했다는 지속 안내(연출은 2초면 사라진다).
    var notice: String? = nil
    var onRetry: (() -> Void)? = nil
    var extraChromeHeight: CGFloat = 0
    var clipsOverflowInsteadOfScroll: Bool = false
    let onBack: () -> Void

    static let rowHeight: CGFloat = 56
    static let rowSpacing: CGFloat = 8
    /// 히어로 카드(72pt)를 **이미 반영한** 상한이다 — 히어로를 extraChromeHeight 에 다시 더해 넣지 마라
    /// (이중 차감으로 visibleRows 가 최소값까지 주저앉는다).
    static let maxVisibleRows = 4
    static let heroHeight: CGFloat = 72
    /// 안내줄 한 줄이 먹는 높이(바깥 VStack spacing 12 포함).
    static let noticeStripHeight: CGFloat = 14 + 12

    private var noticeHeight: CGFloat {
        (notice?.isEmpty == false) ? Self.noticeStripHeight : 0
    }

    /// 히어로 아이콘을 accent 로 그릴 조건. **무제한은 잔량이 0 이어도 켜진 상태다** —
    /// 관리자는 재화를 안 쓰므로 잔량이 0 에 머무는 것이 정상이고, 그 화면이 회색으로 죽으면
    /// "울트라를 못 쏜다"는 거짓말이 된다(서버는 그래도 발사한다).
    private var isCharged: Bool { isUnlimited || (balance ?? 0) > 0 }

    private var visibleRows: Int {
        ListRowBudget.visibleRows(
            maxVisibleRows: Self.maxVisibleRows,
            rowHeight: Self.rowHeight,
            rowSpacing: Self.rowSpacing,
            extraChromeHeight: extraChromeHeight + noticeHeight
        )
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                IconButton(icon: "chevron.left", help: "뒤로", action: onBack)
                Text(UltraPanelCopy.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(CheckTheme.primaryText)
                    .lineLimit(1)
                Spacer(minLength: 6)
            }
            PanelDivider()
            heroCard
            if let notice, !notice.isEmpty {
                Text(notice)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(CheckTheme.accent)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            missionList
        }
        .padding(12)
        .panelStyle()
    }

    @ViewBuilder
    private var heroCard: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(CheckTheme.accent.opacity(isCharged ? 0.18 : 0.08))
                Image(systemName: "bolt.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(isCharged ? CheckTheme.accent : CheckTheme.secondaryText)
            }
            .frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(UltraPanelCopy.balanceText(balance, unlimited: isUnlimited))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(CheckTheme.primaryText)
                    // 단위는 **셀 수 있을 때만** 붙인다. "무제한 개"는 말이 아니다.
                    if !isUnlimited {
                        Text("개")
                            .font(.caption)
                            .foregroundStyle(CheckTheme.secondaryText)
                    }
                }
                Text(UltraPanelCopy.heroCaption(balance: balance, hasFailed: hasFailed, unlimited: isUnlimited))
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            // 실패했을 때만 재시도를 준다(리그/토큰/내 기록과 같은 3분기 규약).
            if hasFailed, let onRetry { PanelRetryButton(action: onRetry) }
        }
        .frame(height: Self.heroHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(CheckTheme.fieldFill))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(CheckTheme.accent.opacity(0.28), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var missionList: some View {
        let capHeight = Self.listContentHeight(rowCount: visibleRows)
        let contentHeight = Self.listContentHeight(rowCount: max(1, missions.count))
        let rows = VStack(spacing: Self.rowSpacing) {
            if missions.isEmpty {
                Text(hasLoaded ? UltraPanelCopy.emptyMissions
                               : (hasFailed ? "미션을 불러오지 못했어요" : UltraPanelCopy.loadingCaption))
                    .font(.caption)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: Self.rowHeight, alignment: .leading)
            } else {
                ForEach(missions) { MissionRowView(mission: $0) }
            }
        }
        if contentHeight <= capHeight {
            rows.frame(maxWidth: .infinity, alignment: .top)
        } else if clipsOverflowInsteadOfScroll {
            // 스냅샷 전용: ImageRenderer 는 ScrollView 안쪽을 못 그린다(4개 패널이 모두 같은 우회를 쓴다).
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

    static func listContentHeight(rowCount: Int) -> CGFloat {
        guard rowCount > 0 else { return 0 }
        return CGFloat(rowCount) * rowHeight + CGFloat(rowCount - 1) * rowSpacing
    }
}

private struct MissionRowView: View {
    let mission: MissionProgress

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: MissionCopy.icon(mission.kind))
                .font(.system(size: 13, weight: .semibold))
                // 랩 수도 함께 본다: 3시간 줄은 `claimed` 가 언제나 false라, 오늘 세 개를 받고도
                // 아이콘이 영영 안 물들면 화면이 "아직 아무것도 안 줬다"고 거짓말한다.
                .foregroundStyle(mission.claimedToday || mission.lapsGrantedToday > 0
                                 ? CheckTheme.working : CheckTheme.accent)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(MissionCopy.title(mission.kind))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CheckTheme.primaryText)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    chip
                }
                if let progress = mission.progress {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(CheckTheme.trackFill)
                            Capsule()
                                .fill(progress >= 1 ? CheckTheme.working : CheckTheme.accent)
                                .frame(width: max(0, proxy.size.width * min(1, max(0, progress))))
                        }
                    }
                    .frame(height: 4)      // HeaderCard 진행 바와 같은 관용구 — 렌더 검증된 패턴이다
                }
                Text(MissionCopy.detail(mission))
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: UltraPanel.rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(CheckTheme.fieldFill))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(CheckTheme.border, lineWidth: 1))
    }

    @ViewBuilder
    private var chip: some View {
        switch MissionCopy.chip(mission) {
        case .none:
            // 보상이 없는 줄(연속 출근)에는 칩을 그리지 않는다 — 사장님 확정 3.
            EmptyView()
        case .claimed:
            HStack(spacing: 3) {
                Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                Text(MissionCopy.claimedChip).font(.caption2.weight(.bold))
            }
            .foregroundStyle(CheckTheme.working)
        case .capped:
            Text(MissionCopy.cappedChip)
                .font(.caption2.weight(.bold))
                .foregroundStyle(CheckTheme.pending)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(CheckTheme.pending.opacity(0.16)))
        case .reward(let text):
            Text(text)
                .font(.caption2.weight(.bold))
                .foregroundStyle(CheckTheme.accent)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(CheckTheme.accent.opacity(0.16)))
        }
    }
}

/// 푸터 동기화 문구(SyncStatusView)에 남는 텍스트 폭 예산(순수 계산 — 결정적 검증 지점).
///
/// 푸터는 `[동기화 문구][Spacer][아이콘 버튼…]` 한 줄이고 팝오버 폭은 340 고정이다. 문구만 유연 요소라
/// 버튼을 하나 더할 때마다 문구가 27+8pt 씩 먼저 잘린다. v0.2.11 초안이 여기에 다섯 번째 버튼을 세워
/// "자리 비움으로 자동 근무종료됨"(121pt)이 "자리 비움으로 자동…"으로 잘렸던(핵심어 '근무종료됨' 소실)
/// 회귀를 상수로 못 박아 둔다. 4버튼이 상한이고, 그래도 넘치는 긴 문구는 minimumScaleFactor 로 줄여 담는다.
enum FooterWidthBudget {
    /// 팝오버 340 - 바깥 padding 12*2 - 푸터 padding 12*2.
    static let contentWidth: CGFloat = 340 - 12 * 2 - 12 * 2
    static let iconButtonWidth: CGFloat = 27
    static let spacing: CGFloat = 8
    static let spacerMinWidth: CGFloat = 6
    /// 상태 원형 표시(7pt)와 그 옆 간격(6pt) — 문구가 쓸 수 없는 폭.
    static let statusDotWidth: CGFloat = 7
    static let statusDotSpacing: CGFloat = 6
    /// 말줄임 전에 이 배율까지 줄여 본다(caption2 10pt → 7pt). 문구가 통째로 잘리는 것보다 낫다.
    static let minimumScaleFactor: CGFloat = 0.7
    /// 이 폭 안에 들어와야 하는, 실제로 쓰는 가장 긴 문구(무소속 안내 175.9pt · 장시간 미확인 마감 138.3pt).
    static let longestMessageWidth: CGFloat = 176

    /// 아이콘 버튼 N개일 때 문구에 남는 폭(pt).
    static func messageWidth(iconButtonCount: Int) -> CGFloat {
        let buttons = CGFloat(iconButtonCount) * iconButtonWidth
        // 간격 개수 = [상태뷰][Spacer][버튼…] 사이의 틈 = 버튼 수 + 1.
        let gaps = CGFloat(iconButtonCount + 1) * spacing
        return contentWidth - buttons - gaps - spacerMinWidth - statusDotWidth - statusDotSpacing
    }

    /// 축소(minimumScaleFactor)까지 감안해 말줄임 없이 담을 수 있는 문구 폭 상한(pt).
    static func fittingMessageWidth(iconButtonCount: Int) -> CGFloat {
        max(0, messageWidth(iconButtonCount: iconButtonCount) / minimumScaleFactor)
    }
}

/// 메인 메뉴 헤더의 찌르기 진입 버튼. **높이 0pt 로 리얼타임 고장을 표면화하는 유일한 자리다.**
///
/// 왜 잎 뷰인가: 판정이 `store.displayNow` 를 읽으므로, 이 계산을 팀 카드 본체에 두면 그 카드가
/// 매초 무효화된다(TeamWorkingCountChip 이 같은 이유로 잎 뷰다). 잎으로 가두면 매초 다시 그리는 것은
/// 27×27 아이콘 하나뿐이다.
///
/// 왜 메뉴바가 아닌가: 메뉴바 타이틀은 MM:SS(근무 경과)를 담는 자리이고 이 앱에서 가장 많이 읽히는
/// 숫자다. 고장 하나를 알리려고 정상 기능을 가릴 수 없고, 아이콘으로 대신할 수도 없다 —
/// `exclamationmark.icloud.fill` 은 pendingSync 가 이미 쓰고 있어서 겹치면 **다른 두 고장이 같은
/// 얼굴**이 된다(구버전에 미지 열거값을 접어 오배달을 만든 것과 같은 종류의 사고다).
///
/// 왜 PokePanel 안이 아닌가: 그 패널은 팝오버를 열고 이 손가락 아이콘을 눌러야 나오는 하위 화면이라,
/// 거기에만 두면 topicDenied(REST 는 멀쩡하고 소켓만 죽은 상태)가 완전한 침묵이 된다.
private struct PokeEntryIconButton: View {
    @Bindable var store: WorkTimerStore

    var body: some View {
        let warns = PokeConnectionNotice.shouldWarn(state: store.realtimeState, now: store.displayNow)
        IconButton(
            icon: "hand.point.right.fill",
            help: warns ? PokeConnectionNotice.iconHelp : "콕 찌르기",
            // 착색만 바꾼다 — 아이콘을 바꾸면 사용자가 이 버튼을 찾던 모양이 사라진다.
            tint: warns ? CheckTheme.pending : CheckTheme.secondaryText
        ) {
            store.togglePokePanel()
        }
    }
}

/// 푸터 동기화 상태. `PokeEntryIconButton` 과 같은 이유로 잎 뷰다(displayNow 를 읽는다).
private struct FooterSyncStatus: View {
    @Bindable var store: WorkTimerStore

    var body: some View {
        SyncStatusView(
            message: store.syncMessage,
            pokeDisconnected: PokeConnectionNotice.shouldWarn(state: store.realtimeState, now: store.displayNow)
        )
    }
}

private struct FooterBar: View {
    @Bindable var store: WorkTimerStore

    var body: some View {
        HStack(spacing: 8) {
            FooterSyncStatus(store: store)
            Spacer(minLength: 6)
            // 버튼은 4개까지다(FooterWidthBudget). 하나 더 세우면 동기화 문구가 곧바로 말줄임된다 —
            // 새 버튼이 필요하면 푸터가 아니라 관련 카드(예: 내 근무 박스 캡션 행)로 보낸다.
            // 캐릭터 표시 on/off. **메뉴가 아니라 그냥 버튼**이다 — 여기에 Menu 를 씌워 '할 일' 스위치를
            // 숨겨 봤지만, 전원 버튼 메뉴와 똑같이 아무도 못 여는 자리였다(보조 화살표는 hover 전엔 보이지도
            // 않는다). 할 일 스위치는 설정 창(CheckSettingsView)이 가져갔고, 이 버튼은 아이콘 하나가
            // 현재 상태를 그대로 말하는 원래의 단순한 토글로 되돌린다.
            // 덤: Menu 는 ImageRenderer 가 그리지 못해(자리에 노란 경고 상자가 박힌다) 렌더 회귀 테스트의
            // 사각지대였다 — 푸터에 Menu 가 하나도 남지 않은 지금, 푸터 전체가 픽셀로 검증된다.
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
            // 전원 버튼: **그냥 버튼이다.** v0.2.17 이 '로그인 시 자동 실행' 토글을 숨길 자리를 찾다가 이 자리를
            // Menu 로 바꿨는데, 딸려온 대가가 셋이었다:
            //  · 색 — Menu 의 label 에는 AppKit 이 자기 틴트를 입혀 `.foregroundStyle(CheckTheme.danger)` 가
            //    무시된다. 위험을 알리는 빨강이 화면에서 흰색으로 그려졌다("왜 하얀색이 됐냐" 실사용 신고).
            //  · 오작동 — primaryAction 이 종료라, 설정을 보려고 눌러 본 클릭이 확인 없이 앱을 껐다.
            //  · 발견 불가 — 토글은 꾹 누르거나 hover 때만 보이는 화살표를 열어야 나왔다(아무도 못 찾았다).
            // 자동 실행 토글은 설정 창(CheckSettingsView)으로 옮겼으므로 여기 남을 이유가 없다.
            // 시각 언어도 이 한 줄로 다시 IconButton(12pt semibold · 27pt 원형)에 수렴한다.
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
    // 비밀번호 재설정 화면 전용 필드. CredentialField.focus 의 타입이 이 열거형으로 고정돼 있어서
    // (FocusState<AuthFocusField?>.Binding) 재설정 화면도 같은 컴포넌트를 쓰려면 케이스를 여기 둬야 한다.
    case resetEmail
    case resetCode
    case resetNewPassword

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
        // 재설정 화면은 로그인 폼과 다른 체인(코드 → 새 비밀번호 → 제출)을 쓰므로 여기 체인에 끼지 않는다.
        case (_, .resetEmail), (_, .resetCode), (_, .resetNewPassword):
            return nil
        }
    }
}

/// syncMessage 배너의 성격 분류. AuthStatusLine 색/아이콘과 모드 전환 시 오류 리셋 판정에 공유한다.
enum AuthMessageKind {
    case progress, info, success, error

    init(_ message: String) {
        switch message {
        case "로그인 중", "계정 생성 중":
            self = .progress
        case "확인 메일 필요", "이메일 확인 필요":
            self = .info
        // 비밀번호 재설정을 마치면 재설정 화면이 통째로 사라지므로, "바꿨다 · 이제 로그인하라"는 안내는
        // 로그인 화면의 상태줄로 넘어온다. 이 표에 없으면 default 로 떨어져 **성공을 빨간 경고로** 그린다 —
        // 스토어 상수를 그대로 참조해 문구가 바뀌어도 분류가 어긋나지 않게 못 박는다.
        case WorkTimerStore.passwordResetChangedSignInMessage:
            self = .success
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
        // 재설정 화면은 로그인 폼을 **대체**한다(같이 띄우지 않는다) — 팝오버는 폭 340·높이 상한 700pt 예산이라
        // 두 폼을 동시에 세우면 푸터까지 밀려 잘린다. 되돌아오는 길은 재설정 패널 안의 "로그인으로 돌아가기"다.
        if store.passwordResetPhase != .idle {
            PasswordResetPanel(
                phase: store.passwordResetPhase,
                message: store.passwordResetMessage,
                sentToEmail: store.passwordResetEmail,
                resendSeconds: store.passwordResetResendSeconds,
                previewASCIIWarning: previewWarning,
                perform: dispatchReset
            )
        } else {
            loginCard
        }
    }

    // 재설정 화면 버튼이 낸 동작을 스토어 호출로 옮기는 유일한 자리. 화면은 어떤 스토어 API 를 부를지 모른 채
    // 값(PasswordResetAction)만 내보내므로, "무엇을 누르면 무엇이 나가는가"는 순수 값으로 단언할 수 있다.
    private func dispatchReset(_ action: PasswordResetAction) {
        switch action {
        case .requestCode(let email):
            Task { await store.requestPasswordResetCode(email: email) }
        case .verifyCode(let code):
            Task { await store.verifyPasswordResetCode(code: code) }
        case .submitNewPassword(let newPassword):
            Task { await store.submitNewPassword(newPassword) }
        case .cancel:
            store.cancelPasswordReset()
        }
    }

    @ViewBuilder
    private var loginCard: some View {
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
            // 비밀번호를 잊었을 때의 **유일한 출구**. 가입 폼엔 둘 이유가 없으므로 로그인 모드에만 붙인다.
            // 지금 입력해 둔 이메일을 그대로 들고 넘어간다 — 재설정 화면에서 다시 타이핑시키지 않는다.
            if mode == .signIn {
                PasswordResetEntryLink(email: store.email) { store.beginPasswordReset(email: $0) }
            }
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

// MARK: - Password reset (OTP) panel

/// 재설정 화면의 버튼이 "눌리면 무슨 일이 나는가". 오프스크린 렌더에서는 버튼을 실제로 누를 수 없으므로
/// (합성 NSEvent·accessibilityPerformPress 둘 다 이 코드베이스에서 안 먹는 게 실측됐다) 배선을 값으로 뺐다.
/// 화면은 이 값을 만들어 내보내기만 하고, 스토어 호출은 LoginPanel.dispatchReset 한 곳에서만 한다.
enum PasswordResetAction: Equatable {
    case requestCode(email: String)
    /// 코드만 보내 **검증까지만** 한다. 비밀번호를 같이 싣지 않는 게 핵심이다 — 코드가 틀렸을 때
    /// 애써 정한 비밀번호까지 함께 튕겨 나오면 사용자는 무엇이 틀렸는지 알 수 없다.
    case verifyCode(code: String)
    /// 검증이 끝난 뒤 새 비밀번호만 보낸다(코드는 이미 소모됐다).
    case submitNewPassword(newPassword: String)
    case cancel
}

/// 재설정 화면이 지금 어느 칸에 서 있는가. 단계(phase)는 7가지지만 **화면은 3개**다 —
/// 왕복 중(sending/verifying/submitting)은 직전 입력 화면을 그대로 유지해야 하기 때문에
/// phase 를 그대로 분기 조건으로 쓰면 화면이 깜빡이며 사라진다.
enum PasswordResetStep: Equatable {
    case email
    case code
    case newPassword

    /// 이 화면에 들어왔을 때 커서가 놓일 자리. 화면이 바뀌었는데 포커스가 그대로면 사용자는
    /// 클릭부터 해야 한다 — 그래서 "어디로 옮기는가"를 순수 값으로 못 박아 두고 테스트가 단언한다.
    var focusField: AuthFocusField {
        switch self {
        case .email: return .resetEmail
        case .code: return .resetCode
        case .newPassword: return .resetNewPassword
        }
    }
}

/// 재설정 안내 문구의 성격. 로그인 폼의 AuthMessageKind 와 판정 근거가 다르다 — 저쪽은 문구 전체
/// 일치표를 쓰고, 이쪽은 단계(진행 중인가)를 먼저 보고 그다음에 **안내 상수 목록**으로 info 를 가린다.
enum PasswordResetNoticeKind: Equatable {
    case progress, info, error
}

/// 재설정 화면의 "지금 무엇을 보여 주고 무엇을 누를 수 있는가"를 뷰 밖에서 계산하는 순수 값.
/// 쿨다운·검증·문구 결정이 전부 여기 있으므로 단위 테스트가 화면을 그리지 않고도 직접 단언한다.
struct PasswordResetFormModel: Equatable {
    let phase: PasswordResetPhase
    let email: String
    let code: String
    let newPassword: String
    let resendSeconds: Int
    let message: String?

    /// 메일로 오는 OTP 자릿수. Supabase 기본값이 6자리다.
    static let codeLength = 6
    /// Supabase 계정 비밀번호 최소 길이(그보다 짧으면 서버가 422 로 거절한다 — 왕복 전에 여기서 막는다).
    static let minimumPasswordLength = 6

    /// 지금 서 있는 화면. 왕복 중인 단계는 **직전 입력 화면에 머무른다**(sending→이메일, verifying→코드,
    /// submitting→새 비밀번호). 그래야 진행 문구가 뜨는 동안 방금 친 값이 눈앞에 남는다.
    var step: PasswordResetStep {
        switch phase {
        case .enterCode, .verifying:
            return .code
        case .enterNewPassword, .submitting:
            return .newPassword
        case .idle, .enterEmail, .sending:
            return .email
        }
    }

    /// 네트워크 왕복 중인가. 이때는 모든 버튼을 잠그고 진행 문구를 띄운다.
    var isBusy: Bool { phase == .sending || phase == .verifying || phase == .submitting }

    var trimmedEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }

    var primaryTitle: String {
        switch step {
        case .email: return "코드 받기"
        case .code: return "코드 확인"
        case .newPassword: return "비밀번호 바꾸기"
        }
    }

    var primaryIcon: String {
        switch step {
        case .email: return "envelope.badge.fill"
        case .code: return "checkmark.shield.fill"
        case .newPassword: return "lock.rotation"
        }
    }

    /// 기본 버튼을 눌렀을 때 나갈 동작. 화면마다 정확히 **그 화면에서 친 값 하나만** 실어 보낸다.
    var primaryAction: PasswordResetAction {
        switch step {
        case .email: return .requestCode(email: trimmedEmail)
        case .code: return .verifyCode(code: code)
        case .newPassword: return .submitNewPassword(newPassword: newPassword)
        }
    }

    /// 왕복 중이면 잠그고, 그 밖에는 서버에 보낼 값이 갖춰졌을 때만 연다(빈 요청으로 레이트리밋을 태우지 않는다).
    var isPrimaryEnabled: Bool {
        guard !isBusy else { return false }
        switch step {
        case .email: return Self.looksLikeEmail(trimmedEmail)
        case .code: return code.count == Self.codeLength
        case .newPassword: return newPassword.count >= Self.minimumPasswordLength
        }
    }

    /// 재발송은 **코드 화면에만** 있다. 3단계에서는 코드가 이미 소모돼 다시 받아 봐야 쓸 곳이 없고,
    /// 새로 받은 코드로 검증 상태를 갈아엎으면 지금 화면이 근거를 잃는다.
    var showsResend: Bool { step == .code }
    /// 재발송은 쿨다운이 끝나야 열린다 — 남은 초를 버튼 글자에 그대로 적어 "왜 안 눌리는지"를 보이게 한다.
    var isResendEnabled: Bool { !isBusy && resendSeconds <= 0 }
    var resendTitle: String { resendSeconds > 0 ? "다시 받기 (\(resendSeconds)초)" : "다시 받기" }

    /// 헤더 부제. 3단계는 "재설정" 이 아니라 **이미 통과했다**는 사실을 먼저 알린다 —
    /// 코드 화면과 같은 부제를 달아 두면 "왜 또 입력하지?"로 읽힌다.
    var headerSubtitle: String {
        switch step {
        case .email, .code: return "비밀번호 재설정"
        case .newPassword: return "코드 확인 완료"
        }
    }

    /// 안내/오류 슬롯에 쓸 문구. 스토어 문구가 우선이고, 없을 때만 진행 상태를 대신 적는다
    /// (sending/submitting 인데 문구가 비면 화면이 멈춘 것처럼 보인다).
    var noticeText: String? {
        if let message, !message.isEmpty { return message }
        switch phase {
        case .sending: return "코드 보내는 중"
        case .verifying: return "코드 확인 중"
        case .submitting: return "비밀번호 바꾸는 중"
        default: return nil
        }
    }

    var noticeKind: PasswordResetNoticeKind {
        if isBusy { return .progress }
        guard let text = noticeText else { return .info }
        return Self.isInformational(text) ? .info : .error
    }

    /// 스토어는 안내와 오류를 문자열 하나로만 준다(구분 플래그가 계약에 없다). 낱말로 실패를 **추정**하지
    /// 않고, 실패가 **아닌** 문구를 스토어 상수로 열거해 그 밖을 전부 오류로 본다.
    ///
    /// 방향이 중요하다: 낱말 추정("실패", "만료"…)은 새 거절 문구가 생길 때마다 조용히 회색 안내로 새 나갔다
    /// — 실제로 "비밀번호 조건 확인 · 6자 이상…" 이 봉투 아이콘 달린 안내로 그려졌다. 반대로 짜 두면
    /// 빠뜨렸을 때 안내가 빨갛게 나올 뿐이라, 사용자가 다음 행동을 놓치는 쪽으로는 틀리지 않는다.
    /// (저장 프로퍼티가 아니라 함수인 이유: 스토어 상수는 @MainActor 타입의 멤버라 nonisolated 한
    /// static 기본값 식에서 못 읽는다 — 함수 본문에서 읽는 건 된다.)
    static func isInformational(_ text: String) -> Bool {
        switch text {
        case WorkTimerStore.passwordResetSentMessage,
             WorkTimerStore.passwordResetAlreadySentMessage,
             WorkTimerStore.passwordResetCooldownMessage:
            return true
        default:
            return false
        }
    }

    /// 서버에 던지기 전 최소 형태 검사. 엄밀한 RFC 검증이 아니라 "@ 앞뒤가 비지 않았는가"만 본다 —
    /// 진짜 판정은 서버가 하고, 여기선 확실한 오타로 레이트리밋을 태우는 것만 막는다.
    static func looksLikeEmail(_ text: String) -> Bool {
        let parts = text.split(separator: "@", omittingEmptySubsequences: false)
        return parts.count == 2 && !parts[0].isEmpty && parts[1].contains(".")
    }
}

/// 로그인 폼의 "비밀번호를 잊으셨나요?" 진입점. 이 컨트롤의 존재 이유는 **지금 입력돼 있는 이메일을
/// 그대로 넘기는 것**이다(재설정 화면에서 다시 타이핑시키지 않는다). 그 전달을 press() 순수 함수로 빼
/// 버튼을 누르지 않고도 단언할 수 있게 했다 — 오프스크린에서 버튼 action 은 증명 불가다.
struct PasswordResetEntryLink: View {
    static let title = "비밀번호를 잊으셨나요?"

    let email: String
    let begin: (String) -> Void

    @State private var hovering = false

    /// 앞뒤 공백은 떼고 넘긴다 — 메일 앱에서 주소를 복사하면 공백이 붙어 오는 일이 흔하다.
    static func emailToCarry(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 눌린 그 순간의 동작. 버튼 action 은 오프스크린 렌더에서 증명할 수 없으므로, 누르면 벌어지는 일을
    /// 이렇게 순수 함수 하나로 빼 두는 것이 이 저장소의 관례다(예전 선례 `TodoToggleControl.press` 는
    /// 그 컨트롤이 설정 창으로 이사하며 사라졌고, 관례만 남았다).
    func press() {
        begin(Self.emailToCarry(email))
    }

    var body: some View {
        Button(action: press) {
            // AuthLinkButton 과 같은 글자 톤(caption·accent·hover 밑줄)을 쓰되, 필드 바로 아래 달리는
            // 보조 링크라 오른쪽 정렬로 둔다 — 가운데 정렬은 아래쪽 "가입하기" 링크와 한 덩어리로 보인다.
            Text(Self.title)
                .font(.caption.weight(.medium))
                .foregroundStyle(CheckTheme.accent)
                .underline(hovering)
                .brightness(hovering ? 0.12 : 0)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// 재설정 화면의 안내/오류 한 줄. AuthStatusLine 과 같은 형태(아이콘 + 문구 + 톤 배경)지만 성격을
/// 문구 매칭이 아니라 바깥에서 받은 kind 로 정한다 — 재설정 문구는 AuthMessageKind 표에 없어 전부 빨강이 된다.
private struct PasswordResetNoticeLine: View {
    let text: String
    let kind: PasswordResetNoticeKind

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
            Text(text)
                .font(.caption.weight(.medium))
                // 서버 오류 문구는 한 줄을 넘길 수 있다. 로그인 배너와 달리 2줄까지 풀어 준다 —
                // "코드가 만료됐어요. 다시 받아 주세요" 를 …으로 잘라 버리면 다음 행동을 알 수 없다.
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
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

/// 비밀번호 재설정(OTP) 화면. 브라우저를 열지 않고 앱 안에서 끝낸다 —
/// 1단계: 이메일 → [코드 받기], 2단계: 6자리 코드 → [코드 확인], 3단계: 새 비밀번호 → [비밀번호 바꾸기].
///
/// 코드와 새 비밀번호를 **한 화면에 같이 두지 않는다**: 한 번에 제출하면 서버가 둘 중 무엇을 거절했는지
/// 화면이 구분할 수 없어(코드 만료? 비밀번호 규칙?) 사용자가 애먼 값을 고치게 된다. 검증을 먼저 끝내면
/// 3단계에서 나오는 실패는 반드시 비밀번호 문제다.
///
/// 스토어를 통째로 받지 않고 **값 + 클로저**로만 받는다(PokePanel/LeaderboardPanel 선례) —
/// 렌더 테스트가 어떤 단계든 스토어 없이 그대로 그릴 수 있어야 하기 때문이다.
struct PasswordResetPanel: View {
    let phase: PasswordResetPhase
    let message: String?
    /// 스토어가 기억하는 "코드를 보낸 주소". 2단계 안내와 재발송 대상에 쓴다.
    let sentToEmail: String
    /// >0 이면 재발송 잠금 + 남은 초 표시.
    let resendSeconds: Int
    /// 렌더 스냅샷 전용: ASCII 안내 캡션이 떠 있는 상태를 재현한다. 앱에서는 항상 false.
    var previewASCIIWarning: Bool = false
    let perform: (PasswordResetAction) -> Void

    // 코드·새 비밀번호는 스토어에 남기지 않는다(계약도 인자로만 받는다) — 화면을 벗어나면 사라지는 게 맞다.
    @State private var email: String
    @State private var code = ""
    @State private var newPassword = ""
    @FocusState private var focus: AuthFocusField?

    init(
        phase: PasswordResetPhase,
        message: String?,
        sentToEmail: String,
        resendSeconds: Int,
        previewASCIIWarning: Bool = false,
        perform: @escaping (PasswordResetAction) -> Void
    ) {
        self.phase = phase
        self.message = message
        self.sentToEmail = sentToEmail
        self.resendSeconds = resendSeconds
        self.previewASCIIWarning = previewASCIIWarning
        self.perform = perform
        // 로그인 폼에서 들고 온 이메일을 그대로 채워 둔다 — 진입점이 beginPasswordReset(email:) 로 넘긴 값이다.
        _email = State(initialValue: sentToEmail)
    }

    private var model: PasswordResetFormModel {
        PasswordResetFormModel(
            phase: phase,
            email: email,
            code: code,
            newPassword: newPassword,
            resendSeconds: resendSeconds,
            message: message
        )
    }

    var body: some View {
        VStack(spacing: 12) {
            BrandHeader(subtitle: model.headerSubtitle)
            PanelDivider()
            fields
            AuthButton(title: model.primaryTitle, icon: model.primaryIcon, prominent: true) {
                perform(model.primaryAction)
            }
            .disabled(!model.isPrimaryEnabled)
            .opacity(model.isPrimaryEnabled ? 1 : 0.5)
            // 안내 슬롯은 항상 자리를 잡고 문구 유무는 opacity 로만 토글한다(로그인 폼과 같은 관용구) — 창 튐 제거.
            PasswordResetNoticeLine(text: model.noticeText ?? " ", kind: model.noticeKind)
                .opacity(model.noticeText == nil ? 0 : 1)
                .accessibilityHidden(model.noticeText == nil)
            links
        }
        .padding(14)
        .panelStyle()
        .animation(.easeInOut(duration: 0.22), value: model.step)
        // 화면에 처음 들어올 때와 단계가 넘어갈 때, 커서를 그 화면의 입력칸으로 옮긴다.
        // 이게 없으면 코드 확인 직후 3단계가 떠도 커서가 사라진 코드 필드에 남아, 사용자가 클릭부터 해야 한다.
        .onAppear { focus = model.step.focusField }
        .onChange(of: model.step) { _, step in
            focus = step.focusField
        }
    }

    @ViewBuilder
    private var fields: some View {
        VStack(spacing: 8) {
            switch model.step {
            case .email:
                Text("가입할 때 쓴 이메일로 6자리 코드를 보내 드려요.")
                    .font(.caption)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                CredentialField(
                    title: "이메일",
                    icon: "envelope.fill",
                    text: $email,
                    enforcesASCII: true,
                    allowsSpace: false,
                    warnsInitially: previewASCIIWarning,
                    focus: $focus,
                    fieldIdentifier: .resetEmail,
                    submitLabel: .go,
                    onSubmit: { submitIfReady() }
                )
            case .code:
                // 어디로 보냈는지 먼저 알린다 — 주소를 잘못 적었을 때 사용자가 스스로 알아챌 유일한 단서다.
                //
                // 주소를 문장 **안에** 끼워 넣지 않는다("…com 로/으로"). 조사는 앞 글자의 종성으로 갈리는데
                // 이메일 도메인 끝은 매번 다르고(com·net → 으로, co·io·me → 로) 영문 철자의 한국어 발음
                // 종성까지 판정하는 코드는 이 화면에 과하다. 안내 문장과 주소를 줄로 갈라 조사를 없앤다.
                VStack(alignment: .leading, spacing: 3) {
                    Text("이 주소로 코드를 보냈어요")
                        .font(.caption)
                        .foregroundStyle(CheckTheme.secondaryText)
                    // 긴 주소는 가운데를 줄인다 — 뒤를 자르면 도메인이 사라져 "어느 주소인지" 확인이 안 된다.
                    Text(sentToEmail)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(CheckTheme.primaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // 코드는 숫자 6자리다. 한글 입력원에서 치면 조합 문자가 섞여 들어가므로 ASCII 강제가 필수다
                // (enforcesASCII 는 포커스 시 영문 입력원 전환 + 비-ASCII 필터를 함께 건다).
                CredentialField(
                    title: "인증 코드 6자리",
                    icon: "number",
                    text: $code,
                    enforcesASCII: true,
                    allowsSpace: false,
                    warnsInitially: previewASCIIWarning,
                    focus: $focus,
                    fieldIdentifier: .resetCode,
                    submitLabel: .go,
                    onSubmit: { submitIfReady() }
                )
            case .newPassword:
                verifiedBanner
                // 새 비밀번호만 남는다. 코드 필드는 여기 없다 — 이미 소모된 코드를 다시 보여 주면
                // "또 쳐야 하나?"로 읽히고, 실제로 다시 보내 봐야 서버가 무조건 거절한다.
                CredentialField(
                    title: "새 비밀번호",
                    icon: "lock.rotation",
                    text: $newPassword,
                    isSecure: true,
                    enforcesASCII: true,
                    allowsSpace: true,
                    warnsInitially: previewASCIIWarning,
                    focus: $focus,
                    fieldIdentifier: .resetNewPassword,
                    submitLabel: .go,
                    onSubmit: { submitIfReady() }
                )
            }
        }
    }

    /// 3단계 머리글. 화면이 또 바뀐 이유를 **먼저** 설명한다 — 초록 체크 + "코드 확인됐어요" 로
    /// 방금 한 일이 성공했음을 못 박고, 그다음에 남은 할 일 하나를 알린다.
    private var verifiedBanner: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(CheckTheme.working)
                Text("코드 확인됐어요")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(CheckTheme.working)
                Spacer(minLength: 0)
            }
            Text("새 비밀번호를 정해주세요 · 영문/숫자 6자 이상")
                .font(.caption)
                .foregroundStyle(CheckTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var links: some View {
        VStack(spacing: 8) {
            if model.showsResend {
                // 재발송 대상은 사용자가 지금 보는 필드가 아니라 **실제로 보낸 주소**다 — 2단계에서 주소를
                // 바꾸고 싶으면 취소하고 1단계로 돌아가야 한다(엉뚱한 주소로 조용히 재발송되는 걸 막는다).
                AuthLinkButton(prompt: "코드가 안 왔나요?", action: model.resendTitle) {
                    perform(.requestCode(email: sentToEmail))
                }
                .disabled(!model.isResendEnabled)
                .opacity(model.isResendEnabled ? 1 : 0.45)
            }
            // 어느 단계에서든 로그인으로 돌아가는 길은 항상 보여야 한다(재설정 화면이 로그인 폼을 대체하므로
            // 이 링크가 없으면 앱을 껐다 켜는 것 말고는 빠져나갈 방법이 없다).
            AuthLinkButton(prompt: "", action: "로그인으로 돌아가기") {
                perform(.cancel)
            }
        }
    }

    // Enter 제출은 버튼과 같은 게이트를 통과해야 한다 — 비활성 조건을 우회하는 뒷문을 만들지 않는다.
    private func submitIfReady() {
        guard model.isPrimaryEnabled else { return }
        perform(model.primaryAction)
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
        case .success: return CheckTheme.working
        case .error: return CheckTheme.danger
        }
    }

    private var icon: String {
        switch kind {
        case .progress: return "arrow.triangle.2.circlepath"
        case .info: return "envelope.badge.fill"
        case .success: return "checkmark.seal.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(message)
                .font(.caption.weight(.medium))
                // 재설정 성공 안내("비밀번호를 바꿨어요 · 새 비밀번호로 로그인해주세요")는 340pt 폭에서 한 줄을
                // 넘긴다. 로그인/가입 오류는 전부 짧아 그대로 한 줄이고, 넘치는 문구만 둘째 줄로 풀린다.
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
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
