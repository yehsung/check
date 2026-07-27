import AppKit
import Foundation
import Observation

@Observable
@MainActor
final class WorkTimerStore {
    // 연속 근무 확인/자동 마감 임계값. 12시간 도달 시 확인, 이후 30분 무응답이면 12시간 시점으로 마감.
    static let longSessionThresholdSeconds: TimeInterval = 12 * 60 * 60
    static let longSessionResponseWindowSeconds: TimeInterval = 30 * 60
    // 잠자기 유예. 이 시간 이하 잠자기는 근무 연속으로 인정, 초과하면 덮은 시각으로 마감.
    static let sleepGraceSeconds: TimeInterval = 5 * 60
    // 방치 세션 자동 마감 임계(초). 하트비트가 이 시간 넘게 끊긴 세션을 방치로 본다(서버 함수와 동일 10분).
    static let abandonedSessionThresholdSeconds: TimeInterval = 10 * 60
    // 클라 스캐빈저 스로틀(초). 폴링마다 정리 RPC 를 난사하지 않도록 마지막 발사 후 이 시간은 재발사하지 않는다.
    static let scavengeThrottleSeconds: TimeInterval = 5 * 60
    // 자리 비움 자동 마감 되돌리기 유예(초). 이 시간이 지나면 [되돌리기] 배너는 스스로 사라진다 —
    // 유효기간이 없으면 배너가 로그아웃 전까지 모든 팝오버에 상주하고, 그 사이 새로 시작한 근무를
    // 옛 세션으로 덮어쓰는 사고가 난다.
    static let autoCloseUndoWindowSeconds: TimeInterval = 10 * 60
    // 팝오버를 열 때 팀 메타(목표/이름/역할/참여코드)를 재조회하는 스로틀(초). 팀원이 바꾼 주간 목표가
    // 내 팝오버에 최대 이 시간 안에 반영되게 한다. 여닫이마다 멤버십을 난사하지 않도록 스로틀을 건다.
    static let teamMetaRefreshThrottleSeconds: TimeInterval = 60

    var startedAt: Date?
    var accumulatedSeconds: Int = 0
    /// accumulatedSeconds 가 귀속하는 KST 하루의 시작 시각. 대입/가산 지점마다 그 시점의 dayStart 로 스탬프해,
    /// 자정을 넘겨 어제 누적이 오늘 표시를 부풀리거나 새 날 마일스톤을 오발화시키지 않게 한다.
    @ObservationIgnored var accumulatedDayStart = TeamWeeklyGoal.koreanDayStart(for: Date())
    var tickerTask: Task<Void, Never>?
    var refreshTask: Task<Void, Never>?
    var syncTask: Task<Void, Never>?
    let service: SupabaseWorkService
    let hasAnonKey: Bool
    let defaults: UserDefaults
    /// 월간 AI 토큰 사용량 스토어. 프로덕션은 전역 공유(.shared)라 토큰 행/업로드 트랙이 같은 집계를 읽는다.
    /// 테스트(특히 ImageRenderer 렌더)는 격리 인스턴스를 주입해, 뷰 .task 가 도는 렌더 중에도 실홈 스캔이
    /// 테스트 러너의 .standard 를 오염시키지 않게 한다(감지 대신 의존성 주입으로 격리 — 구조적 결정성).
    let tokenUsage: TokenUsageStore
    var session: SupabaseSession?
    var sessionGeneration = 0
    var currentSessionID: String?

    /// 3D 캐릭터 오버레이 표시 여부 (사용자 토글, UserDefaults 유지).
    var isOverlayEnabled: Bool = true

    /// 팝오버(MenuBarExtra 창) 표시 여부. 표시 감지(onAppear/창 노티)가 setMenuPresented 로 알린다.
    /// 관찰 대상이 아니다 — 티커/폴링 게이팅 판정에만 쓴다.
    @ObservationIgnored var isMenuPresented = false
    /// 실행당 1회 전체 활성화(토큰 회전+멤버십 확정) 플래그. signOut/clearPersistedSession 에서 리셋.
    @ObservationIgnored var hasActivatedStoredSession = false
    /// 멤버십이 확정적으로 판정된 적 있는지(소속 확인 성공 또는 정상 0행 무소속 확정). 첫 활성화가 오프라인/취소로
    /// 실패하면 false 로 남아, 재오픈 시 activateStoredSession 이 멤버십을 재확정하게 한다. signOut/clearPersistedSession 에서 리셋.
    @ObservationIgnored var membershipConfirmed = false
    /// 메뉴바 라벨 텍스트. 문자열이 실제로 바뀔 때만 대입해 라벨 무효화를 최소화한다.
    var menuBarTitle = "오프"

    /// 팝오버 표시 상태를 반영한다(idempotent — 중복 신호 무해).
    /// 열림: 낡은 초를 즉시 갱신하고 티커/리그를 재개. 닫힘: 티커 게이팅만 재평가.
    func setMenuPresented(_ presented: Bool) {
        guard isMenuPresented != presented else { return }
        isMenuPresented = presented
        if presented {
            displayNow = Date()
            // 팝오버가 닫혀 있는 동안 티커가 멈춰 있었을 수 있으므로 유예형 배너 판정을 지금 시각으로 되맞춘다.
            refreshTimedBanner()
            stopTimerIfIdle()
            if isLeaderboardVisible { loadLeaderboard() }
            if isTokenBoardVisible { loadTokenBoard() }
            if isPokePanelVisible { loadPokeDirectory() }
            // 개인 기록: 패널이 열려 있으면 재조회하고, 닫혀 있어도 아직 한 번도 못 받았으면 조용히 받아 온다
            // — 월요일 첫 팝오버의 지난주 회고 배너는 retro 가 계산돼 있어야 뜨기 때문이다(실행당 1회 수준).
            // 주가 바뀌었으면(insightsWeekKey 불일치) 반드시 다시 계산한다 — needsInsightsReload 참고.
            if needsInsightsReload {
                loadInsights()
            } else {
                evaluateRetroBanner()
            }
            // 팀원이 바꾼 주간 목표/이름/역할/참여코드를 팝오버 열 때 60초 스로틀로 재조회해 반영한다.
            refreshTeamMetaIfStale()
            // 팝오버 열림 시점에 내 월간 토큰을 게이트/스로틀 하에 1회 올린다(대부분 즉시 반환 — Task 남발 아님).
            Task { @MainActor [weak self] in await self?.uploadTokenUsageIfNeeded() }
        } else {
            // 회고 배너는 '이번 팝오버의 안내'다 — 창이 닫히면 내린다. 표시 시점에 이번 주 몫을 이미 소비했으므로
            // (markRetroBannerDisplayed) 다음 오픈의 evaluateRetroBanner 는 이 배너를 다시 올리지 않고,
            // 그 자리를 새 버전 안내 같은 다음 순위 배너가 쓴다. 아직 그려지지 못한 배너(더 급한 배너에 밀린
            // 경우)는 키가 소비되지 않아 다음 오픈에서 다시 올라온다.
            if showsRetroBanner { showsRetroBanner = false }
            stopTimerIfIdle()
        }
    }

    /// 팝오버를 열 때 개인 기록(히트맵/회고)을 다시 계산해야 하는지(결정적 검증 지점).
    /// 1) 패널을 보고 있으면 늘 최신으로, 2) 아직 한 번도 못 받았으면 회고 배너 판정을 위해 조용히 한 번,
    /// 3) **주가 바뀌었으면 반드시** — WeeklyRetro 는 계산 시점의 now 로 '지난주'를 정하므로, 앱을 켜 둔 채
    ///    주가 넘어가면 store.retro 가 이전 주에 고정된다. 그 상태로는 월요일 첫 팝오버의 회고 배너가
    ///    (첫 로드 때 retro 가 nil 이었다면) 영영 뜨지 않고, 반대로 낡은 회고로 잘못 뜨기도 한다.
    ///    메뉴바 앱은 잠자기로 수 주 연속 살아 있는 것이 정상이라 재시작으로 자연 치유되지 않는다.
    var needsInsightsReload: Bool {
        isInsightsPanelVisible || !insightsLoaded || insightsWeekKey != RetroWeekKey.current()
    }

    /// 리액션 트리거 싱크. 오버레이 컨트롤러가 연결해 마일스톤/팀원 인사를 엔진으로 흘린다(관찰 대상 아님).
    @ObservationIgnored var onReactionTrigger: ((ReactionKind) -> Void)?
    /// 마일스톤 1일 1회 기록기. init 에서 defaults 로 초기화한다.
    @ObservationIgnored var milestoneTracker: MilestoneTracker!
    /// 팀원 출근 인사(offWork→working) 전이 감지기. 로그아웃 시 reset.
    @ObservationIgnored var greetingDetector = TeammateGreetingDetector()
    /// 팀 주간 목표 완료 상태의 직전 관측값. nil=첫 로드(전이로 치지 않음). false→true 로 바뀌는 순간만 축하.
    @ObservationIgnored var teamGoalComplete: Bool?

    // 잠자기/깨어남 옵저버 토큰. 보관해 두어 필요 시 해제할 수 있게 한다(클로저는 [weak self] 라 수명 자체는 안전).
    @ObservationIgnored private var sleepObserverToken: NSObjectProtocol?
    @ObservationIgnored private var wakeObserverToken: NSObjectProtocol?
    @ObservationIgnored private var observedWorkspaceCenter: NotificationCenter?

    var snapshot = WorkStatusSnapshot(status: .offWork, elapsedSeconds: 0)
    var displayNow = Date()
    var displayName: String
    var email: String
    var password = ""
    var syncMessage: String
    var teamMembers: [TeamMemberStatus] = []
    // 멀티팀 상태.
    // teamName: 로그인 후 내 팀 이름(미확정 시 "팀"). currentTeamID: 확정된 내 팀 id(무소속이면 nil).
    // teamRole: 확정된 내 역할(owner/member, 무소속이면 nil).
    var teamName = "팀"
    var currentTeamID: String?
    var teamRole: String?

    // (레거시 호환) 초대코드 흐름 전의 가입 뷰/렌더 테스트가 아직 참조하는 팀 목록/선택 상태.
    // 새 가입 흐름은 팀 목록을 노출하지 않으므로 이 값들은 채우지 않는다(형만 유지).
    var teamDirectory: [TeamDirectoryEntry] = []
    var selectedSignupTeamID: String?

    // 초대코드 기반 가입/합류 상태.
    // signupTeamCode: 코드 입력 바인딩. joinPreview: 미리보기 결과(nil=미확인/불일치). joinPreviewMessage: 상태 문구.
    // isCreateTeamMode: 가입 화면 코드 입력 ↔ 팀 만들기 전환. createTeamName/createTeamGoalHours: 팀 만들기 폼.
    // createdTeamCode: 방금 만든 팀의 참여코드(공유 안내용). myTeamInviteCode: owner 일 때만 채워짐.
    var signupTeamCode = ""
    var joinPreview: TeamJoinPreview?
    var joinPreviewMessage = ""
    var isCreateTeamMode = false
    var createTeamName = ""
    var createTeamGoalHours = 60
    var createdTeamCode: String?
    var myTeamInviteCode: String?
    // 코드 미리보기 재입력 경합 방지용 세대 카운터(세션과 무관 — 비로그인에서도 쓰므로). 마지막 요청만 반영한다.
    var previewGeneration = 0
    // 헤더 주간 목표 편집 인라인 행이 펼쳐져 있는지. 뷰 로컬 @State 였으나, 이 행이 헤더를 90pt 넘게 부풀려
    // 창 높이 상한 계산에 반드시 필요하므로 스토어로 올렸다(CheckMenuView 의 목록 행수 예산이 이 값을 읽는다).
    var isEditingWeeklyGoal = false
    // 팀 주간 목표시간(초). 출처는 오직 teams.weekly_goal_hours(멤버십 조회 시 확정). 앱은 읽기 전용이다.
    // confirmMembership 성공 시 서버 값으로 갱신하고, signOut/무소속이면 기본값으로 되돌린다.
    var teamGoalSeconds = TeamWeeklyGoal.defaultGoalSeconds
    // 목표 write 세대 토큰. updateTeamGoal 성공 시 +1 한다. refreshTeamMeta/confirmMembership 은 fetch 발사 전
    // 이 값을 캡처하고, 응답 반영 시 값이 바뀌었으면(그 사이 새 목표를 write) teamGoalSeconds 대입만 건너뛴다 —
    // 이미 in-flight 였던 낡은 멤버십 응답이 방금 바꾼 목표를 되돌리는 스냅백(80h→40h)을 막는다. 관찰 대상 아님.
    @ObservationIgnored var teamGoalWriteGeneration = 0
    // 서버 미반영 근무 조작의 FIFO 큐. 단일 슬롯이 아니라 큐라, in-flight 중 들어온 반대 조작이나
    // 오프라인에서 쌓인 여러 세션이 유실되지 않고 순서대로 재생된다. 각 항목은 자체 세션 정보를 동봉해
    // currentSessionID 변화와 무관하게 정확히 재생된다.
    var pendingItems: [PendingWorkItem] = []
    /// 큐/진행 중 근무의 소유 계정(userID). 강제 로그아웃은 큐를 비우지 않고 이 값만 남기므로, 다음 로그인에서
    /// adoptWorkStateOwner 가 같은 계정이면 이어받고 다른 계정이면 버린다. 관찰 대상이 아니다(뷰가 읽지 않음).
    @ObservationIgnored var workStateOwnerUserID: String?

    // 팀 리그(이번 주 팀별 근무시간) 페이지 상태.
    // leaderboard: 1인당 평균 근무시간 내림차순(동률 시 이름)으로 정렬한 팀 목록. isLeaderboardVisible: 리그 페이지 노출 여부.
    // 페이지가 열려 있는 동안 30초 refresh 루프가 함께 갱신하고, signOut 시 둘 다 초기화한다.
    var leaderboard: [TeamLeaderboardEntry] = []
    var isLeaderboardVisible = false

    // 팀원 이번 달 AI 토큰 순위 페이지 상태. isLeaderboardVisible 과 상호 배타(하나 열면 다른 것 닫기).
    // tokenBoard: total 내림차순(동률 이름)으로 정렬한 팀원 엔트리. 페이지가 열려 있는 동안 30초 refresh 루프가 갱신하고,
    // signOut 시 함께 초기화한다. 업로드 게이트 상태(마지막 업로드 값/시각)는 관찰 대상이 아니다.
    var tokenBoard: [TokenBoardEntry] = []
    var isTokenBoardVisible = false
    // 보드 첫 성공 로드 여부. 빈 목록일 때 '아직 아무도 안 올림'(로드 완료) 과 '로드 전/실패'(fallbackStatus) 를 구분한다.
    var tokenBoardLoaded = false
    // 지금 보드 조회가 날아가 있는지. ‹ › 월 이동은 목록을 비우고 다시 로드하므로 그 사이 빈 목록 자리에
    // 동기화 문구("동기화됨")가 뜨지 않고 "불러오는 중…"이 뜨게 하는 구분값이다.
    var tokenBoardLoading = false
    /// 마지막 보드 조회가 (취소가 아닌) 실패로 끝났는지. 이 값이 없던 시절엔 월 이동 중 조회가 실패하면
    /// (로드 전 + 진행중 아님 + 빈 목록) 본문 자리에 syncMessage("동기화됨"·"근무 재개됨" 등 무관한 문구)가
    /// 그대로 떴고 재시도 수단도 없었다 — 개인 기록(insightsFailed)과 같은 대칭으로 갈라 준다.
    /// 재조회 시작(performLoadTokenBoard 진입)과 성공에 내려간다.
    var tokenBoardFailed = false
    /// 마지막으로 서버에 올린 월간 사용량. 변경 게이트 기준(같은 값이면 재업로드 안 함). 관찰 대상 아님.
    @ObservationIgnored var lastUploadedUsage: TokenUsageMonthly?
    /// 마지막 업로드 시도 시각. 60초 스로틀 기준(난사 방지). 관찰 대상 아님.
    @ObservationIgnored var lastTokenUploadAt: Date = .distantPast

    // 토큰 순위판이 보고 있는 월(KST 'YYYY-MM'). 기본은 이번 달이고 ‹ › 로 과거 달을 볼 수 있다(미래로는 불가).
    // 패널을 닫으면 이번 달로 되돌린다 — 다음에 열 때 늘 현재 달부터 보이게.
    var tokenBoardMonth: String = TokenUsageMonthKey.current()

    // 개인 기록(내 근무 리듬 히트맵 + 지난주 회고) 페이지 상태. 다른 패널들과 상호 배타.
    // heatmap/retro 는 서버 원본 세션에서 순수 계산으로 파생한다(CheckWorkInsights).
    var isInsightsPanelVisible = false
    var insightsLoaded = false
    /// 마지막 조회가 (취소가 아닌) 실패로 끝났는지. '조회 진행중'과 '조회 실패'가 같은 문구("불러오는 중…")를
    /// 쓰면 사용자는 기다려야 할지 재시도해야 할지 알 수 없다 — 토큰 보드(tokenBoardLoading)와 같은 대칭이다.
    /// 재시도 시작(performLoadInsights 진입)에 내려가고 성공에도 내려간다.
    var insightsFailed = false
    /// 지금 들고 있는 heatmap/retro 가 어느 주(RetroWeekKey)를 기준으로 계산된 것인지. 회고는 계산 시점의
    /// '지난주'에 고정되므로, 앱을 켜 둔 채 주가 바뀌면 이 값이 어긋난다 — 팝오버 오픈 훅이 그때 재계산을 건다.
    /// (메뉴바 앱은 잠자기로 수 주 연속 살아 있는 것이 정상 사용 형태라 재시작으로 자연 치유되지 않는다.)
    @ObservationIgnored var insightsWeekKey: String?
    var heatmap: WorkRhythmHeatmap = .empty
    var retro: WeeklyRetro?
    // 월요일 첫 팝오버에 지난주 회고를 한 번 안내하는 배너의 노출 여부(주당 1회, UserDefaults 로 기록).
    var showsRetroBanner = false

    // 근무 상태 write 세대 토큰. start/stop/autoStop/undo 성공 시 +1 한다. refreshTeamStatus 는 fetch 발사 전
    // 이 값을 캡처하고, 응답 반영(applyRemoteOwnStatus) 시 값이 바뀌었으면 내 상태 흡수를 건너뛴다 —
    // in-flight 였던 낡은 팀 상태 응답이 방금 누른 시작/종료를 되돌리는 스냅백을 막는다(팀 목표의 동일 패턴).
    @ObservationIgnored var workStateWriteGeneration = 0

    /// 유예가 끝나면 스스로 사라지는 인라인 배너(자리 비움 되돌리기) 중 지금 그릴 것.
    /// 판정은 canUndoAutoClose 가 하되 **결과만** 이 상태로 밀어 넣는다 — 뷰가 그 판정을 직접 부르려면
    /// body 에서 매초 갱신되는 displayNow 를 읽어야 하고, 그러면 배너가 뜨지 않는 평소 화면까지 팝오버
    /// 전체 서브트리가 매초 무효화돼 "초단위 의존은 잎 뷰로 격리한다"는 이 앱의 불변식이 깨진다(회귀 지점).
    /// == 가드 대입이라 값이 실제로 바뀔 때만 뷰가 무효화된다.
    var timedBanner: TimedBanner?

    /// 유예형 인라인 배너 종류.
    enum TimedBanner: Equatable {
        case undoAutoClose
    }

    /// 유예형 배너 상태를 주어진 시각 기준으로 재평가한다. 티커(tick)와 상태 전이 지점(시작/종료/자동 마감/
    /// 되돌리기/원격 흡수/팝오버 열림)에서만 부르면 되고, 그 사이에는 값이 변할 이유가 없다.
    func refreshTimedBanner(now: Date = Date()) {
        let next: TimedBanner? = canUndoAutoClose(now: now) ? .undoAutoClose : nil
        if timedBanner != next { timedBanner = next }
    }

    // 이 맥의 기기 식별자(UserDefaults 영속, 최초 1회 생성). 토큰 사용량 원장이 (user_id, month, device_id)
    // 단위라 여러 맥을 써도 서로 덮어쓰지 않고 서버에서 합산된다.
    @ObservationIgnored var deviceID: String = ""

    // 콕찌르기 페이지 상태. 리그/토큰 보드와 3자 상호 배타(하나 열면 나머지 닫기).
    // pokeDirectory: 앱 사용자 전체(본인 제외), 근무중 먼저·이름순. 페이지가 열려 있는 동안 refresh 루프가 갱신.
    var pokeDirectory: [PokeDirectoryEntry] = []
    var isPokePanelVisible = false
    // 디렉토리 첫 성공 로드 여부('아직 아무도 없음' vs '로드 전/실패' 구분 — tokenBoardLoaded 와 동일 규약).
    var pokeDirectoryLoaded = false
    // 대상별 쿨타임 만료 시각. 성공/서버 cooldown 응답 시 갱신. 표시 카운트다운은 displayNow 기준.
    var pokeCooldownUntil: [String: Date] = [:]
    // 패널 상단 1줄 안내(찌르기 실패 사유 등). 패널 닫기/성공 시 nil.
    var pokeNotice: String?
    // 내 토큰 사용량 공개 여부(profiles.token_usage_public 미러). 로그인 후 서버값 1회 로드, 토글은 낙관 반영.
    var tokenUsagePublic = true
    @ObservationIgnored var tokenUsagePublicLoaded = false
    // 수신 찔림 폴링 태스크(로그인 중 상시 15초). refresh 루프와 별도 — 유휴 300초로는 전달이 너무 늦다.
    var pokePollTask: Task<Void, Never>?
    /// 수신 찔림 싱크. 오버레이 컨트롤러가 연결해 움찔+말풍선(숨김 시 peek)으로 표시한다(관찰 대상 아님).
    @ObservationIgnored var onPokesReceived: (([ReceivedPoke]) -> Void)?

    // 잠자기 정책: willSleep 시각을 기록해 didWake 에서 잠든 시간을 판정한다.
    var sleepBeganAt: Date?
    // 12시간 확인: 카운터 기준점(근무 시작 또는 마지막 "네, 근무 중이에요" 확인 시점).
    var longSessionAnchor: Date?
    var isLongSessionPromptActive = false
    var promptShownAt: Date?
    // 자리 비움 자동 마감 되돌리기용: 마지막으로 자동 마감한 세션.
    var lastAutoClosedSessionID: String?
    var lastAutoClosedStartedAt: Date?
    /// 자동 마감이 일어난 시각. 되돌리기 배너의 유효기간 판정 기준이다(없으면 되돌릴 수 없다).
    var lastAutoClosedAt: Date?
    /// 자동 마감이 accumulatedSeconds 에 더한 그 세션의 '오늘 몫'(초). 되돌리기가 이 값을 도로 빼서
    /// 재개된 세션 구간이 누적과 진행분에 이중 계상되는 것을 막는다.
    var lastAutoClosedSeconds: Int = 0
    // 클라 스캐빈저(방치 세션 서버 자동 마감 폴백) 마지막 발사 시각. 5분 스로틀 판정에 쓴다(관찰 대상 아님).
    @ObservationIgnored var lastScavengeAt: Date = .distantPast
    /// 팀 메타(목표/이름/역할/참여코드) 마지막 재조회 시각. 팝오버 열 때 60초 스로틀 판정에 쓴다(관찰 대상 아님).
    @ObservationIgnored var lastTeamMetaRefreshAt: Date = .distantPast
    /// 팀 목표 변경 중복 호출 방지 플래그(관찰 대상 아님). 저장 버튼 연타/재진입을 막는다.
    @ObservationIgnored var isUpdatingTeamGoal = false


    var todayDuration: Int {
        let dayStart = TeamWeeklyGoal.koreanDayStart(for: displayNow)
        // 누적 기여는 그 값이 '오늘' 것일 때만 센다: 스탬프(accumulatedDayStart)가 오늘 자정 이후면 유효,
        // 아니면 0. 자정을 넘겨 어제 누적이 오늘 표시를 부풀리거나 새 날 마일스톤을 오발화시키지 않게 한다.
        let accumulatedContribution = accumulatedDayStart >= dayStart ? accumulatedSeconds : 0
        guard let startedAt else { return accumulatedContribution }
        // 진행 세션 기여를 KST 자정으로 클리핑한다: 자정을 넘긴 세션이 오늘 표시를 부풀리거나 자정 직후
        // 마일스톤이 오발화하지 않게 하고, 시계 되돌림으로 음수가 되면 0으로 클램프한다.
        let effectiveStart = max(startedAt, dayStart)
        return accumulatedContribution + max(0, Int(displayNow.timeIntervalSince(effectiveStart)))
    }

    /// 내 이번 주 누적(초). 팀 목록에서 내 행의 라이브 주간값을 쓰고, 아직 못 받았으면 오늘 누적으로 대체한다.
    /// 헤더 보조 문구와 내 팀 카드의 "내 주간 목표 진행률" 게이지가 같은 값을 쓰도록 한곳에서 계산한다.
    var myLiveWeeklySeconds: Int {
        guard let userID = session?.userID,
              let mine = teamMembers.first(where: { $0.id == userID })
        else {
            return todayDuration
        }
        return mine.liveWeeklyDurationSeconds(now: displayNow)
    }

    var canSync: Bool {
        hasAnonKey
    }

    var isSignedIn: Bool {
        session != nil
    }

    /// 로그인은 되어 있으나 소속 팀이 없는 상태. 무소속 계정에 팀 코드 입력 패널을 띄우는 판정에 쓴다.
    var isTeamless: Bool {
        isSignedIn && currentTeamID == nil
    }

    /// 내가 현재 팀의 owner 인지. owner 여야 팀 카드에서 참여코드 보기/복사를 노출한다.
    var isTeamOwner: Bool {
        teamRole == "owner"
    }

    init(
        service: SupabaseWorkService = SupabaseWorkService(),
        environment: [String: String] = ProcessInfo.processInfo.environment,
        defaults: UserDefaults = .standard,
        workspaceNotifications: NotificationCenter? = NSWorkspace.shared.notificationCenter,
        tokenUsage: TokenUsageStore = .shared
    ) {
        self.service = service
        self.defaults = defaults
        self.tokenUsage = tokenUsage
        milestoneTracker = MilestoneTracker(defaults: defaults)
        hasAnonKey = SupabaseConfig.anonKey(environment: environment) != nil
        email = defaults.string(forKey: Self.emailKey) ?? ""
        displayName = defaults.string(forKey: Self.displayNameKey) ?? ""
        isOverlayEnabled = defaults.object(forKey: Self.overlayEnabledKey) as? Bool ?? true
        // 기기 식별자는 최초 1회 생성 후 영속한다 — 맥 2대가 서로의 월 토큰 원장을 덮어쓰지 않게 하는 키(결함1).
        deviceID = Self.resolveDeviceID(defaults: defaults)
        let restoredSession = Self.restoredSession(from: defaults)
        session = restoredSession
        // 이번 실행에서 쌓일 큐/진행 중 근무의 주인은 복구된 세션의 계정이다(비로그인 시작이면 첫 로그인이 정한다).
        workStateOwnerUserID = restoredSession?.userID
        syncMessage = hasAnonKey ? (restoredSession == nil ? "로그인 필요" : "동기화됨") : "Supabase 키 필요"
        observeSleepWake(workspaceNotifications)
        refreshMenuBarTitle()
    }

    /// 잠자기/깨어남 노티를 구독한다. 클로저는 [weak self]로 스토어 수명을 넘겨 자동 무력화되므로
    /// 별도 해제가 필요 없다(테스트는 handleSleep/handleWake 를 직접 호출한다).
    private func observeSleepWake(_ center: NotificationCenter?) {
        guard let center else { return }
        observedWorkspaceCenter = center
        sleepObserverToken = center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: nil) { [weak self] _ in
            let now = Date()
            Task { @MainActor in self?.handleSleep(at: now) }
        }
        wakeObserverToken = center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: nil) { [weak self] _ in
            let now = Date()
            Task { @MainActor in self?.handleWake(at: now) }
        }
    }

    func toggle() {
        if snapshot.isWorking {
            stop()
        } else {
            start()
        }
    }

    /// 앱 종료 직전 근무를 마무리한다. 로그인 상태가 아니거나 근무중이 아니면 즉시 리턴(요청 0건).
    /// 근무중이면 기존 stop()/enqueueSync 직렬 경로로 퇴근 upsert를 큐에 넣고, 그 sync 체인이
    /// 끝나거나 timeout(초)이 지날 때까지만 기다린다. 타임아웃 시 서버에 열린 세션이 남을 수 있으나
    /// 다음 실행의 refreshTeamStatus/applyRemoteOwnStatus 복구 경로가 이를 정리하므로 종료를 막지 않는다.
    func finishWorkBeforeQuit(timeout: Double = 3) async {
        guard session != nil, startedAt != nil else { return }
        stop()
        guard let syncTask else { return }
        await Self.awaitFirst(of: syncTask, orTimeout: timeout)
    }

    /// task 완료 또는 timeout 중 먼저 오는 시점에 리턴한다. 진 쪽(타임아웃/미완료 sync)은 취소하지 않고
    /// 백그라운드에 남겨 두어 종료 지연이 timeout을 넘지 않도록 한다.
    private static func awaitFirst(of task: Task<Void, Never>, orTimeout timeout: Double) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let barrier = QuitBarrier(continuation)
            Task { @MainActor in
                await task.value
                barrier.resume()
            }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(timeout))
                barrier.resume()
            }
        }
    }

    /// 자리 비움 자동 마감 되돌리기 대상을 지운다(되돌리기 성공/배너 닫기/새 근무 시작/로그아웃 공통 경로).
    /// 새 근무를 시작한 뒤에도 남아 있으면 [되돌리기]가 진행 중 세션을 옛 세션으로 갈아치우므로 반드시 여기서 끊는다.
    func clearAutoCloseUndo() {
        if lastAutoClosedSessionID != nil { lastAutoClosedSessionID = nil }
        if lastAutoClosedStartedAt != nil { lastAutoClosedStartedAt = nil }
        if lastAutoClosedAt != nil { lastAutoClosedAt = nil }
        if lastAutoClosedSeconds != 0 { lastAutoClosedSeconds = 0 }
        // 배너 상태는 판정값의 캐시라 판정 근거가 사라지면 즉시 따라 내려가야 한다(X 로 닫기/되돌리기 성공 경로).
        // start/stop/autoStop 은 이 함수를 먼저 부르고 근무 상태를 마저 바꾸므로, 그쪽에서 끝에 한 번 더 되맞춘다.
        refreshTimedBanner()
    }

    func start(now: Date = Date()) {
        guard startedAt == nil else { return }
        // 근무 상태를 내가 바꿨음을 세대 토큰으로 알린다 — in-flight 였던 낡은 팀 상태 응답이 이 시작을 되돌리지 못하게.
        workStateWriteGeneration &+= 1
        // 새 근무를 시작하면 직전 자동 마감 되돌리기는 무효다(옛 세션으로 현 세션을 덮어쓰지 못하게 즉시 끊는다).
        clearAutoCloseUndo()
        displayNow = now
        startedAt = now
        currentSessionID = UUID().uuidString
        longSessionAnchor = now
        clearLongSessionPrompt()
        sleepBeganAt = nil
        snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 0)
        startTimer()
        refreshMenuBarTitle()
        // 근무 상태가 바뀌면 유예형 배너의 성립 조건도 뒤집힌다(되돌리기는 비근무 전용).
        refreshTimedBanner(now: now)
        syncCurrentStatus()
    }

    func stop(now: Date = Date()) {
        guard let startedAt else { return }
        // 종료도 내 write 다 — 세대를 올려 in-flight 낡은 응답의 '근무중' 흡수를 무력화한다.
        workStateWriteGeneration &+= 1
        // 서버 복구 경로(applyRemoteOwnStatus)로 시작된 세션이라 start() 를 안 탔을 수 있으므로 여기서도 끊는다.
        clearAutoCloseUndo()
        displayNow = now
        // 서버 전송 duration 은 세션 전체를 유지한다(서버가 타임스탬프로 클리핑). 로컬 누적 가산만 오늘 자정으로
        // 클리핑해, 자정을 넘긴 세션이 '오늘 누적'에 통째로 더해져 표시가 점프하는 것을 막는다.
        let duration = max(0, Int(now.timeIntervalSince(startedAt)))
        let sessionStart = startedAt
        accumulatedSeconds += max(0, Int(now.timeIntervalSince(max(sessionStart, TeamWeeklyGoal.koreanDayStart(for: now)))))
        accumulatedDayStart = TeamWeeklyGoal.koreanDayStart(for: now)
        self.startedAt = nil
        longSessionAnchor = nil
        clearLongSessionPrompt()
        sleepBeganAt = nil
        snapshot = WorkStatusSnapshot(status: .offWork, elapsedSeconds: accumulatedSeconds)
        stopTimerIfIdle()
        refreshMenuBarTitle()
        // 근무를 마치면 되돌리기 배너의 성립 조건이 다시 열린다(비근무 전용).
        refreshTimedBanner(now: now)
        syncCurrentStatus(durationSeconds: duration, sessionStartedAt: sessionStart, endedAt: now)
    }

    // MARK: - 잠자기 정책 (5분 유예)

    /// willSleep. 근무중이면 덮은 시각을 기록한다(깨어날 때 잠든 시간을 재기 위함).
    func handleSleep(at date: Date = Date()) {
        guard startedAt != nil else { return }
        sleepBeganAt = date
    }

    /// didWake. 잠든 시간이 5분 이하면 근무 연속으로 인정, 초과하면 덮은 시각으로 자동 마감한다.
    func handleWake(at date: Date = Date()) {
        guard let sleepBeganAt, startedAt != nil else {
            self.sleepBeganAt = nil
            return
        }
        let asleep = date.timeIntervalSince(sleepBeganAt)
        guard asleep > Self.sleepGraceSeconds else {
            self.sleepBeganAt = nil
            return
        }
        autoStop(endedAt: sleepBeganAt, message: "잠자기로 자동 근무종료됨")
    }

    // MARK: - 12시간 확인 (30분 무응답 자동 마감)

    /// 근무 틱에서 호출. 12시간 도달 시 확인 배너를 띄우고, 배너 노출 후 30분 무응답이면 12시간 시점으로 마감한다.
    func evaluateLongSession(now: Date) {
        guard startedAt != nil, let anchor = longSessionAnchor else { return }

        if isLongSessionPromptActive {
            guard let promptShownAt, now.timeIntervalSince(promptShownAt) > Self.longSessionResponseWindowSeconds else {
                return
            }
            autoStop(
                endedAt: anchor.addingTimeInterval(Self.longSessionThresholdSeconds),
                message: "장시간 미확인으로 자동 근무종료됨"
            )
            return
        }

        if now.timeIntervalSince(anchor) > Self.longSessionThresholdSeconds {
            isLongSessionPromptActive = true
            promptShownAt = now
        }
    }

    /// 배너의 "네, 근무 중이에요" 액션. 배너를 닫고 12시간 카운터를 지금부터 다시 시작한다.
    func confirmStillWorking() {
        guard isLongSessionPromptActive else { return }
        clearLongSessionPrompt()
        longSessionAnchor = Date()
    }

    func clearLongSessionPrompt() {
        isLongSessionPromptActive = false
        promptShownAt = nil
    }

    /// 지정한 종료 시각으로 로컬 상태를 즉시 마감하고, 기존 직렬 sync 경로(enqueueSync)로 서버에 반영한다.
    /// syncMessage 는 사유 문구로 세팅한다(이후 refresh 가 "동기화됨"으로 정규화할 수 있음 — 즉시 피드백 목적).
    private func autoStop(endedAt: Date, message: String) {
        guard let sessionStart = startedAt else { return }
        // 잠자기/장시간 미확인 자동 마감도 로컬이 확정한 근무 상태 변경이라 세대를 올린다(낡은 응답의 재개 금지).
        workStateWriteGeneration &+= 1
        // 사유가 다른 이번 마감이 확정됐으므로 직전 자리 비움 되돌리기 대상은 무효다.
        clearAutoCloseUndo()
        // 서버 전송 duration 은 세션 전체(서버가 클리핑). 로컬 누적 가산만 종료일 자정으로 클리핑해 표시 점프를 막는다.
        let duration = max(0, Int(endedAt.timeIntervalSince(sessionStart)))
        accumulatedSeconds += max(0, Int(endedAt.timeIntervalSince(max(sessionStart, TeamWeeklyGoal.koreanDayStart(for: endedAt)))))
        accumulatedDayStart = TeamWeeklyGoal.koreanDayStart(for: endedAt)
        startedAt = nil
        longSessionAnchor = nil
        clearLongSessionPrompt()
        sleepBeganAt = nil
        snapshot = WorkStatusSnapshot(status: .offWork, elapsedSeconds: accumulatedSeconds)
        stopTimerIfIdle()
        refreshMenuBarTitle()
        // 자동 마감도 근무 상태 확정이라 배너 판정을 되맞춘다(자동시작 [취소] 는 여기서 사라진다).
        refreshTimedBanner()
        syncCurrentStatus(durationSeconds: duration, sessionStartedAt: sessionStart, endedAt: endedAt)
        syncMessage = message
    }

    @discardableResult
    func signIn() -> Task<Void, Never>? {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty, !password.isEmpty else {
            syncMessage = "이메일과 비밀번호 필요"
            return nil
        }

        let task = Task {
            await signIn(email: trimmedEmail, password: password)
        }
        return task
    }

    @discardableResult
    func signUp() -> Task<Void, Never>? {
        let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDisplayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedEmail.isEmpty, !password.isEmpty, !trimmedDisplayName.isEmpty else {
            syncMessage = "이메일, 비밀번호, 별명 필요"
            return nil
        }
        // 코드 모드: 미리보기가 확인되어야(joinPreview != nil) 가입 가능. 만들기 모드: 팀 이름 필수.
        if isCreateTeamMode {
            guard !createTeamName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                syncMessage = "팀 이름을 입력해 주세요"
                return nil
            }
        } else {
            guard joinPreview != nil else {
                syncMessage = "팀 코드를 확인해 주세요"
                return nil
            }
        }

        let task = Task {
            await signUp(email: trimmedEmail, password: password, displayName: trimmedDisplayName)
        }
        return task
    }

    /// 팀 코드 미리보기(가입 화면). signupTeamCode 를 검증해 joinPreview/joinPreviewMessage 를 갱신한다.
    /// 디바운스는 UI 몫이고, 여기선 재입력 경합만 막는다(마지막 요청 우선). 비로그인에서도 호출 가능.
    func previewTeamCode() {
        previewGeneration &+= 1
        Task { @MainActor in await performPreviewTeamCode() }
    }

    /// 무소속 계정 패널의 합류 액션. 로그인 상태에서 signupTeamCode 로 join_team 을 실행한다.
    func joinTeamWithCode() {
        Task { @MainActor in await performJoinTeamWithCode() }
    }

    /// 방금 만든 팀의 참여코드 안내를 닫는다.
    func dismissCreatedTeamCode() {
        createdTeamCode = nil
    }

    func refreshTeamStatus() {
        Task {
            await refreshTeamStatus()
        }
    }

    /// (레거시 호환) 초대코드 흐름 전의 가입 뷰가 호출하던 팀 목록 로드. 팀 목록 공개를 폐기했으므로 no-op 이다.
    /// 새 가입 흐름은 previewTeamCode()/createTeam 으로 대체됐다.
    func loadTeamDirectory() {}

    /// 트로피 버튼 액션. 리그 페이지를 토글하고, 여는 순간 순위를 로드한다. 토큰 보드/콕찌르기/개인 기록과 상호 배타.
    func toggleLeaderboard() {
        isLeaderboardVisible.toggle()
        if isLeaderboardVisible {
            closeTokenBoard()
            closePokePanel()
            isInsightsPanelVisible = false
            loadLeaderboard()
        }
    }

    /// 토큰 순위판을 닫는 **유일한** 경로. 뒤로 버튼·토글·다른 패널 열기가 모두 여기를 지나야
    /// 보고 있던 달이 이번 달로 되돌아간다(다음에 열 때 늘 현재 달부터 — 과거 달에 갇히지 않게).
    func closeTokenBoard() {
        if isTokenBoardVisible { isTokenBoardVisible = false }
        syncTokenBoardMonthToCurrent()
    }

    /// 보고 있던 달이 현재 달과 다르면 현재 달로 되돌리고 그 달의 캐시를 비운다(닫기·열기 공용).
    /// 닫기만으로는 부족하다 — 6월에 열었다 닫으면 이 함수가 조기 반환해 아무것도 정리하지 않으므로
    /// (그 시점엔 6월이 곧 현재 달) 앱을 켜 둔 채 7월이 되면 tokenBoardMonth 가 6월에 굳는다.
    /// 그래서 여는 경로도 반드시 여기를 지나야 월 롤오버 후 첫 오픈이 지난달 캐시를 그리지 않는다.
    private func syncTokenBoardMonthToCurrent() {
        guard tokenBoardMonth != TokenUsageMonthKey.current() else { return }
        tokenBoardMonth = TokenUsageMonthKey.current()
        tokenBoard = []
        tokenBoardLoaded = false
        // 날아가 있던 조회는 달이 바뀌어 어차피 버려진다 — 진행중 표시도 함께 내린다.
        tokenBoardLoading = false
    }

    /// 토큰 사용량 행 액션. AI 토큰 순위 페이지를 토글하고, 여는 순간 보드를 로드한다. 다른 패널과 상호 배타.
    func toggleTokenBoard() {
        guard !isTokenBoardVisible else {
            closeTokenBoard()
            return
        }
        isTokenBoardVisible = true
        isLeaderboardVisible = false
        closePokePanel()
        isInsightsPanelVisible = false
        // 앱을 켜 둔 채 달이 바뀐 경우(6월에 보고 닫은 뒤 7월 1일) 지난달 캐시가 그대로 그려지고
        // 재조회마저 지난달로 나가지 않도록, 여는 순간 현재 달로 맞춘다.
        syncTokenBoardMonthToCurrent()
        // 첫 프레임부터 빈 목록 자리에 "불러오는 중…"이 뜨게 한다(월 이동과 같은 규약 — 본문 자리에 동기화 문구 금지).
        if !tokenBoardLoaded { tokenBoardLoading = true }
        loadTokenBoard()
    }

    /// 콕찌르기 페이지를 닫는 **유일한** 경로. 뒤로 버튼·토글·다른 패널 열기가 모두 여기를 지나야
    /// 실패 안내(pokeNotice)가 함께 사라진다. 예전엔 자기 토글의 else 가지에서만 안내를 비워서,
    /// [내 기록]·리그·토큰 보드로 빠져나갔다가 콕찌르기로 되돌아오면 아무 것도 누르지 않은 새 화면에
    /// 낡은 주황 경고줄이 그대로 떴다(회귀 지점).
    func closePokePanel() {
        isPokePanelVisible = false
        pokeNotice = nil
    }

    /// 콕찌르기 버튼 액션. 사용자 목록 페이지를 토글하고, 여는 순간 디렉토리를 로드한다. 다른 패널과 상호 배타.
    func togglePokePanel() {
        if isPokePanelVisible {
            closePokePanel()
        } else {
            isPokePanelVisible = true
            isLeaderboardVisible = false
            closeTokenBoard()
            isInsightsPanelVisible = false
            loadPokeDirectory()
        }
    }

    /// 개인 기록 버튼 액션. 내 근무 리듬/지난주 회고 페이지를 토글하고, 여는 순간 세션을 로드한다. 다른 패널과 상호 배타.
    func toggleInsightsPanel() {
        isInsightsPanelVisible.toggle()
        if isInsightsPanelVisible {
            isLeaderboardVisible = false
            closeTokenBoard()
            closePokePanel()
            // 배너 소비 판정은 evaluateRetroBanner 한 곳에만 둔다 — 예전엔 여기서 markRetroBannerSeen() 을
            // 무조건 불러, 아직 회고를 못 받은 상태(첫 조회 실패·오프라인)에서 패널을 열기만 해도 이번 주 키가
            // 소진돼 뒤늦게 회고가 도착해도 그 주 내내 배너가 뜨지 않았다(회귀 지점). 패널이 열려 있으므로
            // evaluateRetroBanner 는 '회고가 있을 때만 소비, 없으면 배너만 내림' 규약을 그대로 적용한다.
            evaluateRetroBanner()
            loadInsights()
        }
    }

    /// 회고 배너 [보기] 전용 진입점. 토글이 아니라 **열기**다 — 이미 개인 기록 패널을 보고 있는데 배너를 누르면
    /// 토글이 패널을 닫아 버려(팀 목록으로 되돌아감) 배너가 약속한 동작과 정반대가 된다.
    func openInsightsPanel() {
        guard !isInsightsPanelVisible else {
            markRetroBannerSeen()
            return
        }
        toggleInsightsPanel()
    }

    func startTimer() {
        guard tickerTask == nil else { return }
        tickerTask?.cancel()
        tickerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                // 표시값은 wall-clock 파생이라 누적 오차가 없어 tolerance 로 웨이크업을 병합해도 안전하다.
                try? await Task.sleep(for: .seconds(1), tolerance: .milliseconds(200))
                // 스토어가 해제됐으면 루프를 빠져나간다 — weak self 라 tick 는 no-op 이 되지만 루프 자체는 계속
                // 돌아 좀비가 되므로 self 소멸 시 명시적으로 탈출한다.
                guard let self else { return }
                self.tick()
            }
        }
    }

    func stopTimerIfIdle() {
        // 내가 근무중이면 티커를 항상 유지한다(12h 확인/마일스톤/라벨 갱신). 팀원 초침만 필요한 경우는
        // 팝오버가 열려 있을 때만 티커를 돌린다 — 숨김 상태에선 매초 재평가가 낭비이므로 정지한다.
        guard startedAt == nil, !(isMenuPresented && teamMembers.contains(where: { $0.status == .working })) else {
            startTimer()
            return
        }
        tickerTask?.cancel()
        tickerTask = nil
    }

    /// 30초 refresh 루프의 적응형 주기 판정. 근무중/팝오버 열림/미반영 큐가 있으면 빠른 주기(30s)로,
    /// 그 외 유휴에선 느린 주기(300s)로 돈다. 팝오버를 여는 순간의 즉시 refresh(.task)가 감속 지연을 메운다.
    var refreshLoopIsFast: Bool {
        startedAt != nil || isMenuPresented || !pendingItems.isEmpty
    }

    /// refresh 루프의 슬라이스 주기(초). fast 모드는 이 값 1회(기본 30s)를 자고, slow 유휴 모드는 이 값의
    /// 10슬라이스(기본 300s)로 나눠 자며 매 슬라이스마다 fast 전이를 재확인한다. 테스트에서 짧게 줄여 검증한다.
    @ObservationIgnored var refreshLoopSliceSeconds: Double = 30

    func startStatusRefreshLoop() {
        // 수신 찔림 폴링은 refresh 루프와 수명을 같이한다(로그인/활성화 지점에서 함께 시작, 자체 idempotent 가드).
        startPokePolling()
        guard refreshTask == nil else { return }
        refreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                let slice = self?.refreshLoopSliceSeconds ?? 30
                let tolerance = Duration.seconds(slice / 6)
                if self?.refreshLoopIsFast ?? false {
                    // 빠른 주기: 슬라이스 1회(기본 30s)를 잔다.
                    try? await Task.sleep(for: .seconds(slice), tolerance: tolerance)
                } else {
                    // 느린 유휴 주기(기본 300s=슬라이스×10)를 10슬라이스로 쪼갠다. 유휴→근무 전이가 다음 본문까지
                    // 최대 5분 넘게 지연돼 하트비트 신선도(90초)를 어기던 결함을 막는다: 매 슬라이스 후 fast 로
                    // 바뀌었으면 즉시 본문으로 넘어간다(슬라이스 wakeup 은 플래그 확인뿐이라 유휴 비용은 무시 가능).
                    for _ in 0..<10 {
                        try? await Task.sleep(for: .seconds(slice), tolerance: tolerance)
                        if Task.isCancelled { return }
                        if self?.refreshLoopIsFast ?? false { break }
                    }
                }
                await self?.retryPendingSync()
                await self?.sendHeartbeatIfWorking()
                await self?.refreshTeamStatus()
                await self?.refreshLeaderboardIfVisible()
                await self?.refreshTokenBoardIfVisible()
                await self?.refreshPokeDirectoryIfVisible()
                // 내 월간 토큰 사용량을 변경 게이트+60초 스로틀로 서버에 올린다(팀원 보드 최신화). 대부분 게이트에서 즉시 반환.
                // 팝오버가 열려 있을 때만 부른다 — 토큰 스캔은 행이 처음 그려질 때(팝오버 열림) 지연 시작되므로(D1 규약),
                // 닫힌 상태에서 TokenUsageStore.shared 를 건드려 앱 시작부터 스캔이 도는 것을 막는다.
                if self?.isMenuPresented == true {
                    await self?.uploadTokenUsageIfNeeded()
                }
            }
        }
    }

    private func tick() {
        let now = Date()
        displayNow = now
        // 자정을 넘겼으면 어제 스탬프의 누적을 0으로 리셋하고 스탬프를 오늘로 갱신한다(하우스키핑). 표시/마일스톤은
        // todayDuration 의 자정 클리핑이 이미 막지만, 누적 원장 자체도 새 날에 맞춘다(이후 refresh 가 서버값 복원).
        let dayStart = TeamWeeklyGoal.koreanDayStart(for: now)
        if accumulatedDayStart < dayStart {
            accumulatedSeconds = 0
            accumulatedDayStart = dayStart
        }
        // 유예형 배너의 '만료'는 시간이 지나야만 일어난다 — 뷰가 매초 displayNow 를 읽는 대신 여기서 밀어 넣는다.
        // == 가드라 유예가 끝나는 그 한 틱에서만 뷰가 무효화된다(평소엔 대입조차 없다).
        refreshTimedBanner(now: now)
        // snapshot 은 재대입하지 않는다 — 라벨/오버레이/헤더 전체 무효화를 막는다. 라이브 초는 todayDuration
        // (잎 뷰)과 menuBarTitle 파생값으로 흐르고, 여기선 정책 평가와 라벨 문자열만 갱신한다.
        if startedAt != nil {
            evaluateLongSession(now: now)
            evaluateTimeMilestones(now: now)
            refreshMenuBarTitle()
        }
    }

    /// 메뉴바 라벨 문자열을 현재 상태에서 다시 계산해, 문자열이 실제로 바뀔 때만 대입한다.
    /// (@Observable 은 동일 값 대입도 관찰자를 발화시키므로 != 가드가 무효화 최소화의 핵심이다.)
    func refreshMenuBarTitle() {
        var derived = snapshot
        if derived.isWorking {
            derived.elapsedSeconds = todayDuration
        }
        let new = MenuBarStatusFormatter.title(for: derived)
        if menuBarTitle != new {
            menuBarTitle = new
        }
    }

    /// 근무 중 오늘 누적이 1시간/4시간을 넘는 순간 마일스톤 축하를 트리거한다(마일스톤별 1일 1회).
    /// 4시간을 이미 넘긴 채 관측되면 1시간 키는 조용히 소비해 뒤늦게 축하가 터지지 않게 한다.
    func evaluateTimeMilestones(now: Date) {
        guard startedAt != nil else { return }
        let today = todayDuration
        if today >= 4 * 3_600 {
            if milestoneTracker.fireIfNeeded(MilestoneTracker.hourFourKey, now: now) {
                onReactionTrigger?(.milestone)
            }
            _ = milestoneTracker.fireIfNeeded(MilestoneTracker.hourOneKey, now: now)
        } else if today >= 3_600 {
            if milestoneTracker.fireIfNeeded(MilestoneTracker.hourOneKey, now: now) {
                onReactionTrigger?(.milestone)
            }
        }
    }
}

extension WorkTimerStore {
    static let emailKey = "check.userEmail"
    static let displayNameKey = "check.displayName"
    static let overlayEnabledKey = "check.overlayEnabled"

    /// 캐릭터 오버레이 표시 여부를 지정하고 설정을 저장한다.
    func setOverlayEnabled(_ enabled: Bool) {
        isOverlayEnabled = enabled
        defaults.set(enabled, forKey: Self.overlayEnabledKey)
    }

    /// 캐릭터 오버레이 표시를 토글하고 설정을 저장한다.
    func toggleOverlayEnabled() {
        setOverlayEnabled(!isOverlayEnabled)
    }
    static let accessTokenKey = "check.session.accessToken"
    static let refreshTokenKey = "check.session.refreshToken"
    static let userIDKey = "check.session.userID"

    static func restoredSession(from defaults: UserDefaults) -> SupabaseSession? {
        guard let accessToken = defaults.string(forKey: accessTokenKey),
              let userID = defaults.string(forKey: userIDKey)
        else {
            return nil
        }
        return SupabaseSession(
            accessToken: accessToken,
            refreshToken: defaults.string(forKey: refreshTokenKey),
            userID: userID
        )
    }

    func persistSession(_ session: SupabaseSession, email: String? = nil, displayName: String? = nil) {
        defaults.set(session.accessToken, forKey: Self.accessTokenKey)
        defaults.set(session.userID, forKey: Self.userIDKey)
        if let refreshToken = session.refreshToken {
            defaults.set(refreshToken, forKey: Self.refreshTokenKey)
        } else {
            defaults.removeObject(forKey: Self.refreshTokenKey)
        }
        if let email {
            defaults.set(email, forKey: Self.emailKey)
        }
        if let displayName {
            defaults.set(displayName, forKey: Self.displayNameKey)
        }
    }

    func clearPersistedSession() {
        // 이 경로는 사용자가 누른 로그아웃(signOut)만이 아니라 토큰 만료 강제 로그아웃도 함께 탄다. 그래서
        // 세션을 지우기 전에 '지금까지의 소유 계정'을 남겨 둔다 — 미반영 근무 큐/진행 중 근무는 여기서 버리지
        // 않고(재로그인하면 그대로 재생돼야 한다), 다음 로그인이 다른 계정일 때 adoptWorkStateOwner 가 버린다.
        workStateOwnerUserID = session?.userID ?? defaults.string(forKey: Self.userIDKey) ?? workStateOwnerUserID
        // 세대를 올려 이 시점 이후 완료되는 낡은 Task 의 부수효과를 차단한다(토큰 만료 로그아웃 공통 경로).
        sessionGeneration += 1
        currentSessionID = nil
        hasActivatedStoredSession = false
        membershipConfirmed = false
        session = nil
        [Self.accessTokenKey, Self.refreshTokenKey, Self.userIDKey].forEach(defaults.removeObject)
        // 세션이 사라지면 리그 페이지 상태도 함께 초기화한다(signOut·토큰 만료 로그아웃 공통 경로).
        leaderboard = []
        isLeaderboardVisible = false
        // 토큰 보드 상태와 업로드 게이트도 함께 비운다(리그와 동일 규약). 다음 로그인은 처음부터 다시 올린다.
        tokenBoard = []
        isTokenBoardVisible = false
        tokenBoardLoaded = false
        tokenBoardLoading = false
        tokenBoardFailed = false
        lastUploadedUsage = nil
        lastTokenUploadAt = .distantPast
        // 콕찌르기/공개 설정 상태도 함께 비운다(리그·토큰 보드와 동일 규약).
        pokeDirectory = []
        isPokePanelVisible = false
        pokeDirectoryLoaded = false
        pokeCooldownUntil = [:]
        pokeNotice = nil
        tokenUsagePublic = true
        tokenUsagePublicLoaded = false
        pokePollTask?.cancel()
        pokePollTask = nil
        // 개인 기록(히트맵/회고)과 토큰 순위 월 위치도 함께 비운다(리그·토큰 보드와 동일 규약).
        // 기기 식별자는 계정이 아니라 이 맥의 설정이므로 남긴다. 회고 배너의 '이번 주 봤음'
        // 기록은 계정별 키(retroBannerShownWeekKeyForCurrentUser)라 지울 필요가 없다 — 다음 계정은 자기 키가
        // 비어 있어 그 주 회고를 정상적으로 받고, 원래 계정으로 돌아와도 같은 주에 두 번 뜨지 않는다.
        isInsightsPanelVisible = false
        insightsLoaded = false
        insightsFailed = false
        insightsWeekKey = nil
        heatmap = .empty
        retro = nil
        showsRetroBanner = false
        // 미반영 근무 큐(pendingItems)와 진행 중 근무(startedAt/accumulatedSeconds)는 여기서 비우지 않는다.
        // 이 함수는 토큰 만료 강제 로그아웃(refresh token 부재/무효, 저장 세션 재활성 실패)에서도 불리는데,
        // 큐는 UserDefaults 에 남지 않는 메모리 장부라 한 번 비우면 오프라인에서 쌓인 근무가 영구 소실된다.
        // 대신 위에서 소유 계정(workStateOwnerUserID)을 남겨, 다음 로그인이 다른 계정이면 그때
        // adoptWorkStateOwner 가 큐와 진행 중 근무를 버린다(계정 오염 방지와 재로그인 재생을 양립시킨다).
        // 자리 비움 되돌리기 대상은 계정에 묶인 sessionID 라 함께 끊는다 — 남기면 재로그인한 다른 계정 화면에
        // 남의 [되돌리기] 배너가 뜨고, 눌러도 새 계정 자격으로 앞 계정 세션을 재개하려다 RLS 에서 거부된다.
        clearAutoCloseUndo()
        // 되돌리기 대상을 끊었으니 유예형 배너 상태도 함께 내린다(로그아웃 후 재로그인에 낡은 배너가 남지 않게).
        refreshTimedBanner()
        tokenBoardMonth = TokenUsageMonthKey.current()
        // 팀원 인사/팀 목표 축하의 세션 상태도 비운다(다음 로그인의 첫 로드에서 인사 폭탄 금지).
        greetingDetector.reset()
        teamGoalComplete = nil
        refreshTask?.cancel()
        refreshTask = nil
        refreshMenuBarTitle()
    }

    /// 로그인이 성립한 직후, 이 맥에 남아 있던 '계정에 묶인 로컬 근무 상태'(미반영 큐·진행 중 근무)의 주인을
    /// 새 세션 소유자로 확정한다. 같은 계정이면 그대로 이어받아 큐가 순서대로 재생되고(오프라인 근무 보존 —
    /// 토큰 만료로 강제 로그아웃된 뒤 다시 로그인한 흔한 경로), 다른 계정이면 여기서 버린다(앞 계정의 근무가
    /// 새 계정 이름으로 서버에 기록되는 오염 금지).
    func adoptWorkStateOwner(_ userID: String) {
        // 큐 항목은 각자 소유자를 달고 있으므로 남의 것만 정확히 골라 버린다.
        pendingItems.removeAll { $0.ownerUserID != userID }
        let previousOwner = workStateOwnerUserID
        workStateOwnerUserID = userID
        guard let previousOwner, previousOwner != userID else { return }
        // 계정이 바뀌었다 — 진행 중 근무와 그에 딸린 로컬 상태를 모두 끊는다.
        startedAt = nil
        accumulatedSeconds = 0
        accumulatedDayStart = TeamWeeklyGoal.koreanDayStart(for: Date())
        currentSessionID = nil
        longSessionAnchor = nil
        clearLongSessionPrompt()
        sleepBeganAt = nil
        clearAutoCloseUndo()
        snapshot = WorkStatusSnapshot(status: .offWork, elapsedSeconds: 0)
        tickerTask?.cancel()
        tickerTask = nil
        refreshTimedBanner()
        refreshMenuBarTitle()
    }
}

/// 종료 대기용 단일-resume 장벽. sync 완료와 타임아웃 두 경로가 경쟁하되 continuation은 정확히
/// 한 번만 resume되도록 메인 액터에서 직렬화한다(nil로 만들어 재-resume을 무시).
@MainActor
private final class QuitBarrier {
    private var continuation: CheckedContinuation<Void, Never>?

    init(_ continuation: CheckedContinuation<Void, Never>) {
        self.continuation = continuation
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

/// 서버 미반영 근무 조작 한 건. 조작 종류와 그 조작이 속한 세션 정보를 함께 담아, 큐가 나중에 드레인할 때
/// currentSessionID/startedAt 의 이후 변화와 무관하게 정확히 재생되도록 한다(오프라인 복구 정합성).
struct PendingWorkItem: Equatable {
    let id: UUID
    let operation: PendingWorkOperation
    let sessionID: String
    let sessionStartedAt: Date?
    let endedAt: Date?
    /// 이 항목을 만든 계정의 userID. 강제 로그아웃은 큐를 남기므로(오프라인 근무 보존), 다음 로그인 때
    /// 소유자가 다른 항목만 골라 버리는 데 쓴다(앞 계정 근무가 새 계정 이름으로 기록되는 오염 금지).
    let ownerUserID: String?

    init(
        id: UUID,
        operation: PendingWorkOperation,
        sessionID: String,
        sessionStartedAt: Date?,
        endedAt: Date?,
        ownerUserID: String? = nil
    ) {
        self.id = id
        self.operation = operation
        self.sessionID = sessionID
        self.sessionStartedAt = sessionStartedAt
        self.endedAt = endedAt
        self.ownerUserID = ownerUserID
    }
}
