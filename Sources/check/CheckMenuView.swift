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
    // 스냅샷 전용: 팀 목록 내 행이 별명 편집 행으로 바뀐 상태를 강제로 그린다. 앱에서는 항상 false(연필 토글).
    var previewEditingDisplayName: Bool = false

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
        if store.isSignedIn, store.showsRetroBanner { return .retro }
        if showsUpdateBanner { return .update }
        return nil
    }

    private var topBannerHeight: CGFloat {
        switch topBanner {
        case .longSession: return Self.longSessionBannerHeight
        case .undoAutoClose, .retro: return Self.inlineBannerHeight
        case .update:
            // 노트가 있으면 줄 수만큼 배너가 자란다(없으면 예전과 같은 높이 — 목록 행수 예산도 그대로).
            let notes = updateBannerNotes
            guard !notes.isEmpty else { return Self.updateBannerHeight }
            return Self.updateBannerHeight + Self.updateNoteBlockPadding + CGFloat(notes.count) * Self.updateNoteLineHeight
        case nil: return 0
        }
    }

    /// 하위 패널(리그/토큰/찌르기/개인 기록)이 열려 있는지. 열려 있으면 팀 카드 자리를 그 패널이 대신 쓴다.
    private var isSubPanelOpen: Bool {
        store.isLeaderboardVisible || store.isTokenBoardVisible || store.isPokePanelVisible || store.isInsightsPanelVisible
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
                        // 제목 좌우 ‹ › 로 과거 달을 볼 수 있고(미래 불가), 헤더 끝 눈 버튼은 내 사용량 공개/비공개 토글이다.
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
                            onToggleMyUsagePublic: { store.setTokenUsagePublic(!store.tokenUsagePublic) },
                            // 뒤로도 토글과 같은 닫기 경로를 타야 보던 과거 달이 남지 않는다(다음에 열면 늘 이번 달).
                            onBack: { store.closeTokenBoard() },
                            extraChromeHeight: listExtraChromeHeight,
                            clipsOverflowInsteadOfScroll: previewClipsOverflowList
                        )
                    } else if store.isPokePanelVisible {
                        // 콕찌르기 페이지(앱 사용자 전체 목록). 리그/토큰 보드와 같은 뼈대. store 값을 값+클로저로만 넘겨
                        // PokePanel 을 렌더 테스트 친화적으로 유지한다(쿨타임 잔여는 displayNow 기준 클로저로 매초 갱신).
                        PokePanel(
                            entries: store.pokeDirectory,
                            isMyselfWorking: store.snapshot.isWorking,
                            hasLoaded: store.pokeDirectoryLoaded,
                            fallbackStatus: store.syncMessage,
                            notice: store.pokeNotice,
                            now: store.displayNow,
                            cooldownRemaining: { store.pokeCooldownRemaining(for: $0, now: store.displayNow) },
                            onPoke: { store.sendPoke(to: $0) },
                            onUltra: { store.sendUltraPoke(to: $0) },
                            // 오늘 몫이 남았는가. 하루 한도는 서버가 최종 판정하고 여기선 로컬 미러만 읽는다.
                            canUltra: !store.isUltraPokeSpent(now: store.displayNow),
                            // 남은 횟수는 **울트라 응답으로만** 갱신된다(nil = 아직 모름). 시작 시점을 알기 위한
                            // 추가 GET/RPC 를 만들지 않는다 — 모를 때는 아무 숫자도 보여 주지 않는 쪽을 택했다.
                            // ultraRemainingToday 를 직접 읽지 않고 ultraRemaining(now:)를 거치는 이유:
                            // 그 함수만 KST 하루 스탬프를 대조해, 자정을 넘긴 어제의 "0번 남음"이 남지 않게 한다.
                            ultraRemainingText: WorkTimerStore.ultraRemainingText(remaining: store.ultraRemaining(now: store.displayNow)),
                            onUltraBlocked: { store.pokeNotice = WorkTimerStore.ultraSpentNotice },
                            onBack: { store.togglePokePanel() },
                            extraChromeHeight: listExtraChromeHeight,
                            clipsOverflowInsteadOfScroll: previewClipsOverflowList
                        )
                    } else if store.isInsightsPanelVisible {
                        // 개인 기록 페이지(지난주 회고 + 근무 리듬 히트맵). 내 데이터만 쓰고, 계산은 전부
                        // CheckWorkInsights 순수 함수가 끝낸 뒤라 이 패널은 값만 그린다(렌더 테스트 친화적).
                        InsightsPanel(
                            heatmap: store.heatmap,
                            retro: store.retro,
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
                            previewEditingDisplayName: previewEditingDisplayName,
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

/// 헤더 목표 캡션 행 전용 소형 아이콘 버튼(18pt). 캡션(caption2) 행 높이를 키우지 않으면서 hover 배경과
/// 툴팁으로 버튼임을 드러낸다 — 표준 IconButton(27pt)을 쓰면 이 행만 세로로 부풀어 배치가 어색해진다.
/// 목표 수정(연필)과 내 기록(그래프)이 같은 행에 나란히 서므로 아이콘/툴팁만 갈아 끼우는 공용 버튼으로 둔다.
private struct HeaderCaptionIconButton: View {
    let icon: String
    let help: String
    let isActive: Bool
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
    // @Bindable 인 이유: 별명 편집 입력이 $store.displayNameDraft 로 바인딩된다(HeaderCard 선례).
    @Bindable var store: WorkTimerStore
    // 스냅샷 전용: 참여코드 인라인 행이 펼쳐진 상태로 그린다(키 버튼 클릭을 대신). 앱은 false.
    var previewCodeRevealed: Bool = false
    // 스냅샷 전용: 내 행이 별명 편집 행으로 바뀐 상태로 그린다(연필 배지 클릭을 대신). 앱은 false.
    var previewEditingDisplayName: Bool = false
    // 목록 위쪽에서 배너/토큰 행이 먹은 높이(pt). 그만큼 무스크롤 표시 행수를 줄여 창 상한을 지킨다.
    var extraChromeHeight: CGFloat = 0
    // 스냅샷 전용: 초과 리스트를 ScrollView 대신 클립으로 그린다(ImageRenderer 육안 확인용). 앱은 false.
    var clipsOverflowInsteadOfScroll: Bool = false

    // 키 버튼으로 토글하는 참여코드 인라인 노출 상태. 스냅샷은 previewCodeRevealed 로 시드된다.
    @State private var showsInviteCode: Bool

    init(
        store: WorkTimerStore,
        previewCodeRevealed: Bool = false,
        previewEditingDisplayName: Bool = false,
        extraChromeHeight: CGFloat = 0,
        clipsOverflowInsteadOfScroll: Bool = false
    ) {
        self.store = store
        self.previewCodeRevealed = previewCodeRevealed
        self.previewEditingDisplayName = previewEditingDisplayName
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
                IconButton(icon: "hand.point.right.fill", help: "콕 찌르기") { store.togglePokePanel() }
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
                    Group {
                        if isMe, isEditingName {
                            DisplayNameEditorRow(
                                avatarName: member.name,
                                avatarURL: member.avatarURL,
                                text: $store.displayNameDraft,
                                // displayNow 를 읽지 않는다 — 스토어가 refreshDisplayNameLock 으로 밀어 넣은
                                // 결과만 본다. 여기서 store.displayNow 를 읽으면 팀 카드 서브트리 전체가
                                // 매초 무효화된다(이 파일이 세 곳에 주석까지 남기며 금지한 회귀).
                                isLocked: store.isDisplayNameLocked,
                                isSaving: store.isUpdatingDisplayName,
                                notice: noticeText(),
                                isNoticeError: store.isDisplayNameNoticeError,
                                onSave: { saveName() },
                                onCancel: { store.cancelEditingDisplayName() }
                            )
                        } else {
                            TeamMemberLiveRow(
                                store: store,
                                member: member,
                                teamGoalSeconds: store.teamGoalSeconds,
                                isMe: isMe,
                                onPickAvatar: isMe ? { store.updateAvatar(imageData: $0) } : nil,
                                // 내 행에만 편집 진입을 붙인다(아바타 편집이 이미 같은 조건으로 붙는다).
                                // 별명 편집 진입점은 앱 전체에서 **여기 하나뿐**이다 — 헤더에 하나 더 세우면
                                // listExtraChromeHeight 예산과 700pt 상한 테스트를 다시 맞춰야 한다.
                                onBeginEditName: isMe ? { store.beginEditingDisplayName(currentName: member.name) } : nil
                            )
                        }
                    }
                    // 두 분기가 같은 58pt 를 쓰게 하는 것이 이 배선의 전부다. 높이를 분기 안으로 옮기면
                    // 목록 총 높이가 편집 여부에 따라 달라져 창이 700pt 상한을 넘는다.
                    .frame(height: CheckTheme.memberRowHeight)
                }
            }
        }
    }

    private var isEditingName: Bool { store.isEditingDisplayName || previewEditingDisplayName }

    /// 안내 줄 우선순위: 스토어가 세운 notice(실패 사유 또는 쿨타임) > 기본 도움말.
    /// 색은 store.isDisplayNameNoticeError 가 정한다 — notice != nil 로 추측하면 쿨타임 안내까지 빨갛게 뜬다.
    private func noticeText() -> String {
        store.displayNameNotice
            ?? "\(WorkTimerStore.displayNameMaxLength)자까지 · 다른 사람과 겹칠 수 없어요"
    }

    /// 성공했을 때만 편집 행을 닫는다(실패 시 입력값을 유지해 바로 고쳐 재시도) — 헤더 목표 편집기와 같은 규약.
    private func saveName() {
        Task { @MainActor in
            if await store.updateDisplayName(store.displayNameDraft) {
                store.isEditingDisplayName = false
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
    /// 내 행 별명 편집 진입(팀 목록의 유일한 진입점). 남의 행에서는 nil 이라 연필 자리조차 만들지 않는다.
    var onBeginEditName: (() -> Void)? = nil

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
            onPickAvatar: isMe ? onPickAvatar : nil,
            onBeginEditName: isMe ? onBeginEditName : nil
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
    // 내 토큰 사용량 공개 여부. 헤더 눈 버튼 아이콘/툴팁과 내 행 "비공개" 미니 칩 노출을 가른다.
    var isMyUsagePublic: Bool = true
    // 공개/비공개 토글 액션. nil 이면 헤더에 눈 버튼을 그리지 않는다(렌더 테스트에서 토글 없는 상태 재현).
    var onToggleMyUsagePublic: (() -> Void)? = nil
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
                Spacer(minLength: 2)
                // 내 사용량 공개/비공개 토글 — 토글 액션이 있을 때만 노출한다. 비공개면 남들 보드에서 내 행이 숨겨진다.
                if let onToggleMyUsagePublic {
                    IconButton(
                        icon: isMyUsagePublic ? "eye" : "eye.slash",
                        help: isMyUsagePublic ? "내 사용량 공개 중 — 누르면 나만 보기" : "내 사용량 비공개 중 — 누르면 공개",
                        tint: isMyUsagePublic ? CheckTheme.secondaryText : CheckTheme.accent,
                        action: onToggleMyUsagePublic
                    )
                }
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

/// 콕찌르기 패널 제목 행의 울트라 힌트 문구(순수 로직 — 값으로 검증한다).
///
/// 울트라는 하루 **2회**라 "남은 횟수"가 비로소 뜻을 갖는다. 다만 그 숫자는 울트라 응답으로만 채워지므로
/// (시작 시점을 알기 위한 추가 요청을 만들지 않는다는 결정) 앱을 켜자마자는 **모른다**.
/// 모를 때는 아무 숫자도 만들지 않는다 — 틀린 숫자를 보여 주느니 발견성 문구를 그대로 둔다.
enum PokeUltraHint {
    /// 홀드 시간은 리터럴로 적지 않는다 — UltraChargeStyle.holdSeconds 가 발사 시각의 유일한 권위이고,
    /// 그 숫자를 여기 베껴 두면 상수를 바꾼 날 화면만 옛 시간을 말한다(사용자는 문구대로 눌렀는데 안 나간다).
    static let discover = "\(UltraChargeStyle.holdSecondsText)초 꾹 = 울트라"
    static let spent = "울트라 소진"

    static func text(canUltra: Bool, isCharging: Bool, remainingText: String?) -> String {
        if isCharging, let remainingText { return remainingText }
        return canUltra ? discover : spent
    }
}

/// 콕찌르기 빈 목록 자리 문구 선택(순수 로직, 결정적 검증 지점). 리그/토큰 보드의 EmptyMessage 와 같은 패턴이다:
/// 로드 성공했는데 비면 '아직 아무도 없음'(true), 로드 전/실패면 fallbackStatus(동기화 상태 문구)(false).
enum PokeDirectoryEmptyMessage {
    static let noOthers = "아직 다른 사용자가 없어요"
    static func text(hasLoaded: Bool, fallbackStatus: String) -> String {
        hasLoaded ? noOthers : fallbackStatus
    }
}

/// 팀 카드 자리를 대체하는 콕찌르기 페이지(앱 로그인 사용자 전체). 리그/토큰 보드와 같은 뼈대다:
/// 뒤로 버튼 + 제목 + (조건부 안내줄) + 고정 행높이 리스트(maxVisibleRows 초과 시 스크롤). 행은 아바타 + 이름 +
/// 상태 칩(근무중/자리비움) + 우측 찌르기 버튼(손가락 아이콘: 가능=accent 원형, 쿨타임/내 비근무/대상 자리비움=흐린 비활성).
/// 자리비움 대상은 찌를 수 없다(서버 강제, 클라 선게이트). store 값을 값+클로저로만 받아 렌더 테스트 친화적으로 유지한다 —
/// 쿨타임 잔여는 displayNow 기준 클로저로 매초 갱신된다.
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
    // 렌더 기준 시각(결정성). 카운트다운은 cooldownRemaining 클로저가 displayNow 로 계산하므로 참조용이다.
    let now: Date
    // 대상별 쿨타임 잔여 초(0이면 찌르기 가능). displayNow 기준으로 매초 줄어든다.
    let cooldownRemaining: (String) -> Int
    let onPoke: (String) -> Void
    // 울트라 발사(3초 꾹). 일반 찌르기와 **다른 RPC**라 콜백을 나눠 받는다.
    let onUltra: (String) -> Void
    // 오늘 울트라 몫이 남았는가. 남지 않았으면 3초를 다 눌러도 발사 대신 안내만 뜬다(숨은 규칙 금지).
    let canUltra: Bool
    // 남은 울트라 횟수 문구("오늘 N번 남음"). nil = 아직 모름 → 충전 중에도 아무 숫자를 말하지 않는다.
    let ultraRemainingText: String?
    // 오늘 몫이 없는데 3초를 다 눌렀을 때의 안내. 조용히 아무 일도 안 일어나면 고장으로 읽힌다.
    let onUltraBlocked: () -> Void
    let onBack: () -> Void
    // 목록 위쪽에서 배너/토큰 행이 먹은 높이(pt). 그만큼 무스크롤 표시 행수를 줄여 창 상한을 지킨다.
    var extraChromeHeight: CGFloat = 0
    // 스냅샷 전용: 초과 리스트를 ScrollView 대신 클립으로 그린다(ImageRenderer 육안 확인용). 앱은 false.
    var clipsOverflowInsteadOfScroll: Bool = false

    // 지금 누군가를 꾹 누르는 중인지. **진행도(0~1)가 아니라 켜짐/꺼짐 한 비트만** 올라온다 —
    // 진행도를 여기 두면 3초 동안 매 프레임 이 패널(목록 전체)이 재평가된다.
    @State private var isChargingUltra = false

    // 행 고정 높이·간격. 아바타(26pt) + 이름/상태 칩 한 줄이라 팀원 행보다 낮게 둔다.
    private static let rowHeight: CGFloat = 48
    private static let rowSpacing: CGFloat = 8
    // 스크롤 없이 그대로 보여 주는 최대 인원. 행이 낮아(48pt) 7행까지 창 높이 상한(≤700pt) 안에 든다
    // (리스트 높이 7*48 + 6*8 = 384pt).
    static let maxVisibleRows = 7

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
                Text("콕 찌르기")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(CheckTheme.primaryText)
                    .lineLimit(1)
                Spacer(minLength: 6)
                // 발견성(+ 꾹 누르는 동안엔 남은 횟수). 새 줄이 아니라 제목 행의 남는 폭에 얹는다 —
                // 줄을 하나 더하면 패널 높이가 커져 창 높이 상한(700pt) 예산을 갉아먹는다.
                Text(PokeUltraHint.text(canUltra: canUltra, isCharging: isChargingUltra, remainingText: ultraRemainingText))
                    .font(.caption2)
                    .foregroundStyle(CheckTheme.secondaryText.opacity(canUltra ? 1.0 : 0.5))
                    .fixedSize()
            }
            PanelDivider()
            // 안내줄: notice 우선(주황), 없고 내가 비근무면 안내(회색), 근무중+notice nil 이면 생략(상단 앵커 유지).
            if let noticeLine {
                Text(noticeLine.text)
                    .font(.caption2)
                    .foregroundStyle(noticeLine.isWarning ? CheckTheme.pending : CheckTheme.secondaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            entryList
        }
        .padding(12)
        .panelStyle()
    }

    // 안내줄 내용/톤. notice 가 있으면 그것을(주황), 없고 비근무면 근무 안내(회색), 근무중+notice nil 이면 nil(생략).
    private var noticeLine: (text: String, isWarning: Bool)? {
        if let notice, !notice.isEmpty {
            return (notice, true)
        }
        if !isMyselfWorking {
            return ("근무 중일 때만 콕 찌를 수 있어요", false)
        }
        return nil
    }

    // 서버 정렬을 신뢰하지 않고 뷰에서도 근무중 먼저·이름순으로 다시 정렬한다.
    private var sortedEntries: [PokeDirectoryEntry] {
        entries.sortedForPokeDisplay()
    }

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
                // 로드 성공했는데 비면 '아직 아무도 없음', 로드 전/실패면 fallbackStatus(동기화 상태 문구).
                Text(PokeDirectoryEmptyMessage.text(hasLoaded: hasLoaded, fallbackStatus: fallbackStatus))
                    .font(.caption)
                    .foregroundStyle(CheckTheme.secondaryText)
                    .frame(maxWidth: .infinity, minHeight: Self.rowHeight, alignment: .leading)
            } else {
                ForEach(sortedEntries) { entry in
                    PokeDirectoryRowView(
                        entry: entry,
                        remainingCooldown: cooldownRemaining(entry.userID),
                        canPoke: isMyselfWorking,
                        canUltra: canUltra,
                        onPoke: { onPoke(entry.userID) },
                        onUltra: { onUltra(entry.userID) },
                        onUltraBlocked: onUltraBlocked,
                        onChargingChanged: { isChargingUltra = $0 }
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

/// 콕찌르기 한 행 = 좌측 세로 해시색 바(유저 컬러 포인트) + 아바타 + 이름 + 상태 칩(근무중/자리비움) + 우측 찌르기 버튼.
/// 상태 칩은 근무중이면 초록 점+"근무중", 아니면 회색 "자리비움". 찌르기 버튼은 손가락 아이콘: 가능(accent 원형·눌림 탄성),
/// 쿨타임 중/내가 비근무/대상이 자리비움(흐린 비활성 아이콘, 숫자 없음). 자리비움 대상은 찌를 수 없다(서버 강제).
private struct PokeDirectoryRowView: View {
    let entry: PokeDirectoryEntry
    // 이 대상 쿨타임 잔여 초(0이면 쿨타임 아님). 패널이 displayNow 기준으로 계산해 넘긴다.
    let remainingCooldown: Int
    // 내가 근무중이라 찌를 수 있는지. false면 버튼이 흐려지고 비활성된다.
    let canPoke: Bool
    // 오늘 울트라 몫이 남았는지(툴팁/안내 분기용). 찌르기 자체의 활성 여부와는 무관하다.
    let canUltra: Bool
    let onPoke: () -> Void
    let onUltra: () -> Void
    let onUltraBlocked: () -> Void
    // 충전 시작/끝만 패널에 알린다(진행도는 버튼 안에 갇혀 있다).
    var onChargingChanged: (Bool) -> Void = { _ in }

    // 좌측 세로 바 색 — 아바타 이니셜과 동일한 이름 해시색(유저별 컬러 포인트).
    private var accentColor: Color { CheckTheme.avatarColor(for: entry.name) }

    var body: some View {
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
    @ViewBuilder
    private var pokeButton: some View {
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
                canUltra: canUltra,
                onPoke: onPoke,
                onUltra: onUltra,
                onUltraBlocked: onUltraBlocked,
                onChargingChanged: onChargingChanged
            )
            // 툴팁의 홀드 시간도 상수에서 만든다(힌트 문구와 같은 이유 — 두 곳에 숫자를 흩뿌리지 않는다).
            .help(canUltra ? "콕 찌르기 (\(UltraChargeStyle.holdSecondsText)초 꾹 누르면 울트라)" : "콕 찌르기 (울트라는 오늘 다 썼어요)")
        }
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
    let canUltra: Bool                 // 오늘 울트라가 남았는가(툴팁/안내 분기용)
    let onPoke: () -> Void
    let onUltra: () -> Void
    let onUltraBlocked: () -> Void
    /// 충전 시작/끝 알림. 패널 제목 행이 이 동안에만 "오늘 N번 남음"을 말한다.
    var onChargingChanged: (Bool) -> Void = { _ in }

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
                onChargingChanged(false)
            }
    }

    private func handleChanged(at location: CGPoint) {
        if !isPressing {
            // 눌림 dip 은 자기 트랜잭션으로 분리한다. 같은 업데이트에 섞으면 3초짜리 트랜잭션이
            // 1.0→0.86 까지 3초에 걸쳐 끌고 가 버튼이 죽은 것처럼 보인다.
            withAnimation(.spring(response: 0.22, dampingFraction: 0.55)) { isPressing = true }
            didFireUltra = false
            isCancelled = false
            onChargingChanged(true)
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
            onChargingChanged(false)
        }
    }

    private func handleEnded() {
        let cancelled = isCancelled, fired = didFireUltra
        withAnimation(.spring(response: 0.22, dampingFraction: 0.55)) { isPressing = false }
        cancelCharge(animated: true)
        onChargingChanged(false)
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
            if canUltra { onUltra() } else { onUltraBlocked() }
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
/// 행 기반이 아니라(회고 카드 + 7×24 히트맵 고정 높이) 깎을 행이 없으므로, 대신 본문 표시 높이를 잘라
/// 스크롤로 넘긴다. 팝오버는 위가 고정돼 아래로만 자라므로(CheckWindowAnchor) 상한(700pt)을 넘긴 만큼은
/// 푸터(로그아웃/앱 종료)와 히트맵 하단이 화면 밖으로 잘려 손이 닿지 않는다.
enum InsightsPanelChromeBudget {
    /// 본문(회고 카드 + 구분선 + 히트맵)의 자연 높이(pt). 340pt 폭 ImageRenderer 실측값.
    static let contentNaturalHeight: CGFloat = 307
    /// 크롬이 하나도 없을 때 창 상한(700pt)까지 남는 여유(pt). 기본 상태 실측 577pt 기준 + 5pt 안전 여유.
    /// 이 여유를 넘겨 먹은 만큼만 본문을 깎는다 — 배너 하나(≤92pt)만으로는 아무것도 줄이지 않는다.
    static let chromeSlack: CGFloat = 118
    /// 아무리 깎여도 본문에 남기는 최소 높이(회고 카드 한 장은 보이도록).
    static let minContentHeight: CGFloat = 190

    /// 크롬이 여유를 넘겨 먹었을 때만 본문 표시 높이를 돌려준다(nil 이면 자연 높이 그대로 — 스크롤 없음).
    static func capHeight(extraChromeHeight: CGFloat) -> CGFloat? {
        let overflow = extraChromeHeight - chromeSlack
        guard overflow > 0 else { return nil }
        return max(minContentHeight, contentNaturalHeight - overflow)
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
/// 위에서부터 (a) 지난주 회고 카드, (b) 요일×시간대 근무 리듬 히트맵 — **둘 다 같은 주(지난주)**를 그린다.
/// 값만 받아 그리므로(스토어 미참조)
/// 렌더 테스트가 픽스처만으로 모든 상태를 재현할 수 있다.
private struct InsightsPanel: View {
    let heatmap: WorkRhythmHeatmap
    let retro: WeeklyRetro?
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
            if let placeholder = InsightsEmptyMessage.text(
                hasLoaded: hasLoaded,
                hasFailed: hasFailed,
                totalSeconds: heatmap.totalSeconds
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

    /// 회고 카드 + 히트맵 본문. 배너/목표 편집 행이 창 여유를 다 먹었으면 그만큼 낮춰 스크롤로 넘긴다 —
    /// 팝오버는 위가 고정되고 아래로만 자라므로(CheckWindowAnchor) 상한을 넘긴 만큼 푸터가 화면 밖으로 잘린다.
    @ViewBuilder
    private var insightsBody: some View {
        let content = VStack(spacing: 12) {
            retroCard
            PanelDivider()
            heatmapSection
        }
        if let cap = InsightsPanelChromeBudget.capHeight(extraChromeHeight: extraChromeHeight) {
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

private struct FooterBar: View {
    @Bindable var store: WorkTimerStore

    var body: some View {
        HStack(spacing: 8) {
            SyncStatusView(message: store.syncMessage)
            Spacer(minLength: 6)
            // 버튼은 4개까지다(FooterWidthBudget). 하나 더 세우면 동기화 문구가 곧바로 말줄임된다 —
            // 새 버튼이 필요하면 푸터가 아니라 관련 카드(예: 내 근무 박스 캡션 행)로 보낸다.
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
            // 전원 버튼: 클릭은 그대로 즉시 종료(primaryAction — 기존 근육기억 보존), 꾹 누르거나
            // 화살표를 열면 '로그인 시 자동 실행' 토글이 나온다. 푸터는 4버튼이 상한이라(FooterWidthBudget)
            // 다섯 번째 버튼 대신 기존 자리에 메뉴를 겹친다. "껐는데 다시 켜진다"는 불만의 해소 지점 —
            // 자동 실행을 끄는 수단이 시스템 설정 밖으로 나와야 한다.
            PowerMenuButton()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .panelStyle()
    }
}

/// 푸터의 전원 메뉴. IconButton 과 같은 시각 언어(12pt 세미볼드 아이콘, 27pt 원형 배경)를 유지한다.
private struct PowerMenuButton: View {
    @State private var hovering = false
    @State private var launchAtLogin = true

    var body: some View {
        Menu {
            Toggle("로그인 시 자동 실행", isOn: Binding(
                get: { launchAtLogin },
                set: { wanted in
                    // 쓰기 실패(권한 등)면 실상태를 되읽어 UI 가 거짓말하지 않게 한다.
                    launchAtLogin = LoginItemRegistrar.setLaunchAtLoginEnabled(wanted)
                        ? wanted
                        : LoginItemRegistrar.isLaunchAtLoginEnabled()
                }
            ))
            Button("앱 종료") { NSApplication.shared.terminate(nil) }
        } label: {
            Image(systemName: "power")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(hovering ? CheckTheme.primaryText : CheckTheme.danger)
                .frame(width: 27, height: 27)
                .background(Circle().fill(Color.white.opacity(hovering ? 0.14 : 0.06)))
        } primaryAction: {
            NSApplication.shared.terminate(nil)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovering = $0 }
        .help("클릭: 앱 종료 · 길게 누르기: 자동 실행 설정")
        .onAppear { launchAtLogin = LoginItemRegistrar.isLaunchAtLoginEnabled() }
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
