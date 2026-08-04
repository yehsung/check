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
    /// 하트비트/폴링 기본 주기(초). refreshLoopSliceSeconds 의 기본값이자 아래 백스톱 임계의 여유분 단위다.
    /// (TeamMemberStatus.stalePresenceSeconds = 90 도 "이 주기의 3배"로 정의돼 있다.)
    static let heartbeatIntervalSeconds: TimeInterval = 30
    /// 흡수 세션 소유권 되찾기(백스톱)가 '전진 없음'을 방치로 단정하는 임계(초) = 7분.
    ///
    /// **이 앱 자신의 계약상 6분까지의 무신호는 정상 근무다.** sleepGraceSeconds(5분) 이하 잠자기는 근무
    /// 연속으로 인정하고, 그 앞뒤로 하트비트 주기가 한 번씩 더 붙기 때문이다 —
    /// 20260712120000_auto_close_stale_sessions.sql 의 근거 주석과 같은 계산이다:
    /// "임계 10분 근거: 잠자기 5분 유예 + 하트비트 30초 주기 → 정상 복귀 시 최대 신호 공백 ~6분 < 10분."
    /// 옛 임계(stalePresenceSeconds 90초)는 이 계약 한가운데를 잘랐다 — 맥 A 가 뚜껑을 3분만 닫아도
    /// (A 자신은 유예 안이라 그대로 근무를 이어간다) 맥 B 가 +100초에 소유권을 뺏고, 그 뒤 B 의 잠자기가
    /// A 의 **살아 있는** 세션을 B 의 덮은 시각으로 마감해 그 뒤 근무가 통째로 사라졌다.
    /// 그래서 반드시 sleepGraceSeconds 에서 파생시킨다(한쪽만 바뀌어 어긋나는 일이 없게).
    /// 여유분 4주기 = 잠들기 직전 1 + 깨어난 뒤 1 + 지터/재시도 2.
    ///
    /// 상한: 클라 스캐빈저/서버 cron 이 10분(abandonedSessionThresholdSeconds)이라 **반드시 그보다 앞서야**
    /// 한다. 7분 + 관측 1주기(30초) = 최악 ~7.5분이라 스캐빈저까지 2.5분 여유가 남는다
    /// (= 되찾은 뒤 하트비트를 두 번 보낼 시간). 이 상하한은 reclaimThreshold… 테스트가 고정한다.
    static let adoptedReclaimStaleSeconds: TimeInterval = WorkTimerStore.sleepGraceSeconds
        + 4 * WorkTimerStore.heartbeatIntervalSeconds
    /// 백스톱이 소유권을 주장하기 전에 요구하는 **연속 '전진 없음' 관측 횟수**. 시간만 보면 안 되는 이유는
    /// last_seen_at 을 상대가 **자기 시계로** 쓰기 때문이다(SupabaseWorkService.upsertStatus) — 두 맥의 시계가
    /// 어긋나면 나이는 관측 즉시 임계를 넘은 것처럼 보인다. 내 시계로 잰 '정체 지속'과 관측 횟수를 함께
    /// 요구하면, 값이 실제로 전진하는 한(= 상대가 살아 있는 한) 몇 번이고 장부가 초기화돼 주장이 성립하지 않는다.
    static let adoptedReclaimMinObservations = 3
    // 클라 스캐빈저 스로틀(초). 폴링마다 정리 RPC 를 난사하지 않도록 마지막 발사 후 이 시간은 재발사하지 않는다.
    static let scavengeThrottleSeconds: TimeInterval = 5 * 60
    // 자리 비움 자동 마감 되돌리기 유예(초). 이 시간이 지나면 [되돌리기] 배너는 스스로 사라진다 —
    // 유효기간이 없으면 배너가 로그아웃 전까지 모든 팝오버에 상주하고, 그 사이 새로 시작한 근무를
    // 옛 세션으로 덮어쓰는 사고가 난다.
    static let autoCloseUndoWindowSeconds: TimeInterval = 10 * 60
    // 팝오버를 열 때 팀 메타(목표/이름/역할/참여코드)를 재조회하는 스로틀(초). 팀원이 바꾼 주간 목표가
    // 내 팝오버에 최대 이 시간 안에 반영되게 한다. 여닫이마다 멤버십을 난사하지 않도록 스로틀을 건다.
    static let teamMetaRefreshThrottleSeconds: TimeInterval = 60
    /// 별명 최대 길이. 서버 set_display_name 의 max_len(12)과 **반드시 같은 값**이다 — 어긋나면 클라가
    /// 통과시킨 이름을 서버가 invalid_long 으로 거절하거나(사용자에겐 원인 불명), 반대로 화면 폭 예산을
    /// 넘는 이름이 팀 목록에서 잘려 보인다. 12 인 근거는 팀 목록 내 행의 실측 폭 예산이다.
    /// `nonisolated` 인 이유: 이 상수를 읽는 곳에 **메인 액터 밖**이 있다(순수 폭 예산 테스트의 `#expect`
    /// 자동클로저는 nonisolated 로 합성된다). 액터에 묶어 두면 그 자리에서 컴파일이 깨지고, 그러면 상한의
    /// 유일한 근거인 폭 예산 단언을 못 세운다. 값은 불변 상수라 액터 격리로 지킬 상태가 애초에 없다.
    nonisolated static let displayNameMaxLength = 12
    /// 별명 변경 쿨타임(초) = 1주일. 서버가 강제하고 클라는 버튼을 미리 잠그기 위한 거울만 갖는다
    /// (콕찌르기 쿨타임과 같은 규약 — 최종 판정자는 언제나 서버다). `nonisolated` 근거는 위와 같다.
    nonisolated static let displayNameCooldownSeconds: TimeInterval = 7 * 24 * 3600

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
    /// 진행 중 세션의 ID. **불변식: 항상 정규화된(소문자) 형태다** — 대입하는 모든 경로가
    /// canonicalSessionID 를 지난다(start / 서버 흡수 / 강제 로그아웃 복구 / 되돌리기 재개).
    /// 새 대입 지점을 추가한다면 반드시 같은 규약을 지켜라: 대문자로 들어오는 순간 서버가 돌려주는
    /// 소문자 값과의 비교가 전부 어긋나 내 세션이 내 앱에서 '남의 세션'이 된다.
    var currentSessionID: String?

    /// 지금 진행 중인 세션(startedAt/currentSessionID)을 **이 앱 인스턴스가 열었는가**의 반대말.
    /// true = 서버 스냅샷에서 흡수한 세션 — 다른 맥(또는 이 맥의 이전 실행)이 열었다.
    /// 그래서 이 맥의 **자동** 마감 경로(잠자기·12시간·종료 동기화)와 **하트비트**는 이 세션을 건드리지 않는다.
    /// 사용자가 직접 누른 종료(stop)는 그대로 허용한다 — 같은 사람의 명시적 의사이기 때문이다.
    ///
    /// 수명: startedAt 을 세우는 전이가 함께 확정하고, 내리는 전이가 false 로 되돌린다. 값 자체는 영속하지
    /// 않지만, **판정 근거는 영속한다** — start() 가 만든 세션 ID 를 ownedWorkSessionIDKey 에 남겨 두므로
    /// 재시작 후 서버가 든 세션이 그 ID 와 같으면 '내가 이전 실행에서 연 내 세션'으로 되찾는다
    /// (isOwnedByThisMac / claimSessionOwnership). 이 근거가 없던 v0.2.15 이전 트리에서는 근무 중 재시작이
    /// **반드시** 흡수로 판정돼 하트비트가 영구 정지했고, 10분 뒤 내 앱 자신의 스캐빈저가 내 살아 있는
    /// 세션을 마감했다(되돌리기도 사유 문구도 없이). 관찰 대상 아님(뷰가 읽지 않는다).
    ///
    /// **남은 이중 소유 노출(정직하게)**: 소유권을 세우는 쪽(1차 판정 + 백스톱 7분)은 오판할 수 있고,
    /// 그것을 되돌리는 쪽은 releaseOwnershipIfAnotherDeviceClaims 하나뿐이다. 그 규칙은 상대 맥이
    /// work_status_devices 에 **행을 쓰고 있을 때만** 발화하므로, 상대가 v0.2.10~v0.2.16(이 표를 모르는
    /// 버전)이면 침묵한다 — 혼합 함대 기간의 이중 소유 위험은 v0.2.14 와 정확히 같은 수준이고, 노출은
    /// 백스톱 7분(살아 있는 맥은 last_seen_at 이 전진하므로 오판 자체가 성립하지 않는다)과 10분 스캐빈저가
    /// 좁힌다. 두 맥이 모두 이 버전 이상으로 올라오면 서버 스위치 없이 그 순간부터 결정적 반납이 켜진다.
    @ObservationIgnored var adoptedRemoteSession = false

    /// 흡수 상태에서 마지막으로 관측한 서버의 생존신호(lastSeenAt ?? updatedAt).
    /// 소유권 되찾기의 백스톱이 '신선도'가 아니라 **'전진 여부'**로 판정하기 위한 직전 관측값이다:
    /// 살아 있는 소유 인스턴스가 있으면 30초마다 하트비트로 이 값이 전진하고, 없으면 굳는다.
    /// 신선도만 보면 빠른 재시작(신호가 아직 신선함)과 진짜 남의 근무를 가를 수 없다. 관찰 대상 아님.
    @ObservationIgnored var adoptedLastSeenAt: Date?
    /// 위 관측값이 어느 세션의 것인지. 세션이 바뀌면 관측을 처음부터 다시 시작해야 한다 —
    /// 남기면 이전 세션의 신호를 새 세션의 '전진 없음' 근거로 잘못 써서 남의 근무를 가로챈다. 관찰 대상 아님.
    @ObservationIgnored var adoptedLastSeenSessionID: String?
    /// '전진 없음'을 처음 관측한 시각 — **관측자(내) 시계**다. 나이(now - lastSeenAt)는 상대가 자기 시계로 쓴
    /// 값과 내 시계를 빼는 것이라 시계 어긋남만큼 통째로 부풀지만, 이 값은 내가 직접 잰 '정체 지속'이라
    /// 어긋남의 영향을 받지 않는다. 전진이 한 번이라도 관측되면 nil 로 되돌려 처음부터 다시 잰다. 관찰 대상 아님.
    @ObservationIgnored var adoptedStallBeganAt: Date?
    /// 연속으로 '전진 없음'을 본 횟수. 시간 조건과 **함께** 요구한다 — 폴링 한두 번의 관측만으로 소유권을
    /// 넘기면 하트비트 재시도 실패 한 번이 곧 남의 근무 가로채기가 된다. 전진 관측에 0으로 되돌린다. 관찰 대상 아님.
    @ObservationIgnored var adoptedStallObservations = 0

    /// 릴리스 규칙(오판 자가정정)의 관측 장부: **남의 기기 행**을 직전 폴링에서 어떤 last_seen_at 으로
    /// 봤는지(키 = device_id). 판정을 신선도가 아니라 **전진 여부**로 하기 위한 값이라, 두 맥의 시계
    /// 어긋남이 판정에 들어오지 않는다(백스톱 updateAdoptedPresenceTracking 과 같은 규약).
    ///
    /// 이 자리에 예전엔 `lastHeartbeatSentAt`(내 마지막 하트비트 시각)이 있었고, 규칙은 "서버의
    /// last_seen_at 이 내 하트비트보다 60초 앞서면 남이 쓰는 것"이었다. 그 규칙은 **구조적으로 죽어 있었다**:
    /// 폴링 루프가 하트비트 → 상태 읽기 순서라 내가 읽는 값은 언제나 1초 전 내가 쓴 내 값이고
    /// (실측 seen−mine = [-0.89, -0.89, -0.90]), 발화하려면 상대 시계가 내 앞에 있어야 했다
    /// (= 시계가 맞을수록 규칙이 죽는다 — 방향이 거꾸로다). 관찰 대상 아님.
    @ObservationIgnored var foreignDeviceLastSeenAt: [String: Date] = [:]
    /// 위 장부가 어느 세션의 것인지. 세션이 바뀌면 통째로 비운다 — 남기면 이전 세션에서 본 남의 신호를
    /// 새 세션의 '전진' 근거로 재활용해, 방금 내가 연 세션을 첫 폴링에 곧바로 반납한다. 관찰 대상 아님.
    @ObservationIgnored var foreignDeviceTrackingSessionID: String?

    /// 앱 종료 시퀀스 진입 플래그(finishWorkBeforeQuit 이 세운다). 종료 경로의 stop() 은 이 값을 보고
    /// 찔림 꼬리 회수(flushPokesOnWorkEnd)를 건너뛴다 — take_pokes 는 서버에서 원자 소비라, 응답을 받기 전에
    /// 프로세스가 죽으면 그 찔림이 영구 소실된다(다음 실행이 1시간 신선도 안에서 보여줄 수 있었던 것).
    /// 종료 시점은 말풍선을 볼 사람이 없어 이득도 0이다. 되돌리지 않는다(프로세스가 끝나는 일방향 표식).
    @ObservationIgnored var isTerminating = false

    /// 3D 캐릭터 오버레이 표시 여부 (사용자 토글, UserDefaults 유지).
    var isOverlayEnabled: Bool = true

    /// 팝오버(MenuBarExtra 창) 표시 여부. 표시 감지(onAppear/창 노티)가 setMenuPresented 로 알린다.
    /// 관찰 대상이 아니다 — 티커/폴링 게이팅 판정에만 쓴다.
    @ObservationIgnored var isMenuPresented = false
    /// 실행당 1회 전체 활성화(토큰 회전+멤버십 확정) 플래그. signOut/clearPersistedSession 에서 리셋.
    @ObservationIgnored var hasActivatedStoredSession = false
    /// 실행 킥(activateStoredSessionOnLaunch)의 Task 핸들. 팝오버 `.task` 가 이 Task 를 먼저 기다리는 이유는
    /// '활성화가 둘로 갈라져서'가 아니다 — hasActivatedStoredSession 이 첫 await 이전에 동기 래치되므로
    /// 두 번째 진입자는 항상 fast path 다. 진짜 이유는 fast path 의 confirmMembership 이 **아직 회전 전인
    /// 낡은 access token** 으로 나갔다가 401 을 만나면, withSessionRetry 가 킥과 **같은 낡은 refresh token 으로**
    /// 두 번째 grant 를 치기 때문이다. GoTrue 의 reuse-detection 창을 벗어나면 그 순간 근무 중 강제 로그아웃이 된다.
    /// 킥이 끝나면 스스로 nil 로 돌아간다(팝오버가 이미 끝난 Task 를 붙잡고 있을 이유가 없다).
    @ObservationIgnored var launchActivationTask: Task<Void, Never>?
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

    /// 이 스토어의 '지금'. 프로덕션은 항상 `Date()` 라 동작이 바이트 하나 달라지지 않고, 테스트만 갈아 끼운다.
    ///
    /// 왜 필요한가(이 주입점의 전부다): 자리 비움 자동 마감과 되돌리기의 계약은 **KST 자정 클리핑**을 지난다
    /// (마감분의 '오늘 몫' = seen − max(sessionStart, koreanDayStart)). 그래서 그 계약을 검증하는 테스트가
    /// 벽시계 그대로 돌면 **하루 중 언제 실행되는가**에 따라 기대값이 무너진다: KST 00시대에는 2시간 전 시작이
    /// 자정으로 잘려 '오늘 몫'이 0 근처로 붕괴하고, 픽스처를 만든 시각(URLProtocol 워커 스레드)과 스토어가
    /// 판정한 시각 사이의 지연이 그대로 오차가 된다. 실제로 매일 밤 00:00~02:00 사이에 이 테스트가 빨갛게
    /// 떴다(정오에 돌리면 통과 — 그게 시각 의존의 증거다).
    /// 시계를 주입하면 픽스처와 스토어가 **같은 '지금'** 을 쓰게 되어 그 축이 통째로 사라진다.
    /// 주입 범위는 이 계약이 지나는 경로(자동 마감 · 되돌리기 · 흡수 · 배너 유예 · 틱)로 한정한다.
    @ObservationIgnored var clock: () -> Date = { Date() }

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
    /// now 를 Optional 로 두는 것은 Swift 제약 때문이다 — 인스턴스 메서드의 기본 인자는 self(clock)를 참조할 수
    /// 없다. nil 이면 주입 시계로 채운다(호출부는 그대로 `refreshTimedBanner()` 로 쓴다).
    func refreshTimedBanner(now: Date? = nil) {
        let now = now ?? clock()
        let next: TimedBanner? = canUndoAutoClose(now: now) ? .undoAutoClose : nil
        if timedBanner != next { timedBanner = next }
    }

    /// 지금 별명을 바꿀 수 있는지. 최종 판정자는 서버다(다른 맥에서 방금 바꿨으면 서버가 cooldown 을 준다).
    /// 서버가 준 만료 시각(displayNameAvailableAt)을 우선하고, 없으면 변경 시각 + 쿨타임으로 판정한다.
    func canChangeDisplayName(now: Date) -> Bool {
        guard let availableAt = displayNameAvailableAt
            ?? displayNameChangedAt?.addingTimeInterval(Self.displayNameCooldownSeconds) else { return true }
        return now >= availableAt
    }

    /// 별명 편집 잠금 상태를 주어진 시각 기준으로 재평가한다. 잠금은 '주 단위' 경계라 매초 재평가할 이유가
    /// 없으므로 티커에는 붙이지 않는다 — 편집을 여는 순간·서버 응답 반영 지점·폴링 1회 로드 직후 세 곳에서만
    /// 부른다. now 를 Optional 로 두는 이유는 refreshTimedBanner 와 같다(인스턴스 메서드 기본 인자가 self 를
    /// 참조할 수 없어 nil 이면 주입 시계로 채운다).
    func refreshDisplayNameLock(now: Date? = nil) {
        let now = now ?? clock()
        let next = !canChangeDisplayName(now: now)
        if isDisplayNameLocked != next { isDisplayNameLocked = next }
    }

    /// 서버 normalize_display_name() 의 거울. **서버가 최종 권한**이고 이건 헛왕복을 줄이는 사전 검증이다.
    /// NFC 합성 → 제어·보이지 않는 서식문자 제거 → 연속 공백 1칸 → 앞뒤 공백 제거.
    /// 길이를 그래핌이 아니라 unicodeScalars 로 세는 이유: 서버가 char_length(코드포인트)로 세므로,
    /// 그래핌으로 세면 클라가 통과시킨 이름을 서버가 거절하는 어긋남이 생긴다(NFC 합성이 그 눈금을 맞춘다).
    /// ZWJ(U+200D)는 **남긴다** — 서버와 같은 규칙이다(지우면 "👨‍👩‍👧" 같은 결합 이모지 이름이 조각난다).
    /// 공백 판정은 서버(POSIX [[:space:]])보다 넓다 — Swift 의 isWhitespace 는 U+00A0·U+3000 도 접는다.
    /// 클라가 **먼저** 접어 보내므로 서버가 더 지울 일이 없어 방향은 안전하다. 다만 가입 경로는 이 함수를
    /// 거치지 않고 원문이 그대로 나간다 — 거긴 서버 규칙만 적용된다(가입에는 12자 상한도 없다).
    nonisolated static func normalizedDisplayName(_ raw: String) -> String {
        let composed = raw.precomposedStringWithCanonicalMapping
        let kept = composed.unicodeScalars.filter { scalar in
            if scalar == "\u{200D}" { return true }          // ZWJ 는 이모지 결합용이라 보존
            let category = scalar.properties.generalCategory
            return category != .control && category != .format
        }
        return String(String.UnicodeScalarView(kept))
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }

    /// 쿨타임 안내 문구 — **화면에 나가는 문장 그대로**다. 날짜는 KST 기준이라 자정 근처에서 흔들리지 않는다.
    nonisolated static func displayNameCooldownMessage(availableAt: Date) -> String {
        let c = TeamWeeklyGoal.kstCalendar.dateComponents([.month, .day], from: availableAt)
        return "일주일에 한 번만 바꿀 수 있어요 · \(c.month ?? 1)월 \(c.day ?? 1)일부터"
    }

    /// 편집을 연다. 지금 화면의 내 이름으로 입력을 채워, 다른 맥에서 방금 바꾼 이름 위에서 이어 고치게 한다
    /// (헤더 목표 편집기가 여는 순간 현재 목표로 스테퍼를 맞추는 것과 같은 규약).
    func beginEditingDisplayName(currentName: String) {
        displayNameDraft = currentName
        refreshDisplayNameLock()
        if isDisplayNameLocked, let availableAt = displayNameAvailableAt
            ?? displayNameChangedAt?.addingTimeInterval(Self.displayNameCooldownSeconds) {
            // 잠겨 있으면 여는 그 자리에서 언제 가능한지 말해 준다. 버튼만 비활성화하면 왜 못 누르는지 모른다.
            displayNameNotice = Self.displayNameCooldownMessage(availableAt: availableAt)
            isDisplayNameNoticeError = false
        } else {
            displayNameNotice = nil
            isDisplayNameNoticeError = false
        }
        isEditingDisplayName = true
    }

    func cancelEditingDisplayName() {
        isEditingDisplayName = false
        displayNameNotice = nil
        isDisplayNameNoticeError = false
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
    // 오늘(KST) 울트라 몫을 **다 썼는지**의 로컬 미러(dayKey 문자열, 없으면 아직 여유 있음).
    // 뷰가 버튼 활성/툴팁으로 읽으므로 관찰 대상이다. UserDefaults 에 남기지 않는 이유: 영속이 사 주는 건
    // '실행당 헛요청 1회 절약'뿐인데(26명·무료플랜 기준 무의미), 대신 계정 전환·기기 간 불일치라는 버그 종을
    // 통째로 들여온다. 서버가 유일한 권위이고 이 값은 같은 세션에서의 헛시도를 막는 장치일 뿐이다.
    var ultraPokeSpentDay: String?
    /// 오늘(KST) **남은** 울트라 횟수. nil = 아직 모름(한 번도 응답을 못 받았거나 자정을 넘겼다).
    /// 이 값을 위해 새 GET/RPC 를 만들지 않는다 — 울트라 응답이 실어 주는 값으로만 채운다. 그래서 모르는
    /// 구간이 정상적으로 존재하고, 그때 UI 는 **아무 숫자도 말하지 않는다**(틀린 숫자보다 침묵이 낫다).
    /// 관찰 대상에서 뺀 이유: 이 값이 바뀌는 순간은 항상 pokeNotice 대입과 같은 지점이고, 패널이 열려 있는
    /// 동안엔 displayNow 티커가 매초 트리를 재평가하므로 화면이 낡은 숫자에 머무를 창이 없다.
    @ObservationIgnored var ultraRemainingToday: Int?
    /// ultraRemainingToday 가 귀속하는 KST 하루 키(accumulatedDayStart 와 같은 스탬프 규약).
    /// 이 스탬프가 없으면 자정을 넘긴 뒤에도 어제의 '0번 남음'이 살아남아, 새 날인데 못 쓴다고 안내한다.
    @ObservationIgnored var ultraRemainingDay: String?
    // 내 토큰 사용량 공개 여부(profiles.token_usage_public 미러). 로그인 후 서버값 1회 로드, 토글은 낙관 반영.
    var tokenUsagePublic = true
    @ObservationIgnored var tokenUsagePublicLoaded = false
    // 내 토큰 사용량 **수집** 여부(profiles.token_usage_collect 미러). 공개 여부와 독립이다 —
    // 공개는 '남의 순위판에 뜨는가', 수집은 '서버에 쌓이는가'. 앱에서 바꾸는 값이 아니라 서버가 정한다.
    // 실효는 서버 트리거가 내고(구버전 클라도 함께 막힌다), 이 플래그는 헛업로드를 줄이는 부수 장치다.
    // 뷰가 읽지 않으므로 관찰 대상에서 뺀다.
    @ObservationIgnored var tokenUsageCollect = true
    // 수신 찔림 폴링 태스크(로그인 중 15초 타이머. 실제 take_pokes 는 근무중에만 나간다 — O1/takePokesIfWorking).
    // refresh 루프와 별도인 이유는 유휴 주기(수백 초)로는 말풍선 전달이 너무 늦기 때문이다.
    var pokePollTask: Task<Void, Never>?
    /// 수신 찔림 싱크. 오버레이 컨트롤러가 연결해 움찔+말풍선(숨김 시 peek)으로 표시한다(관찰 대상 아님).
    @ObservationIgnored var onPokesReceived: (([ReceivedPoke]) -> Void)?

    // ── 별명(표시명) 변경 ──
    /// 팀 목록 내 행의 별명 인라인 편집이 열려 있는지. 뷰 로컬 @State 가 아닌 이유: 30초 폴링이 teamMembers 를
    /// 통째로 갈아 끼우면(WorkTimerStoreSync.refreshTeamStatus) ForEach 가 행을 재구성해 편집 상태가 날아간다.
    var isEditingDisplayName = false
    /// 편집 중 입력값. 스토어가 들고 있어야 렌더 스냅샷이 편집 상태를 주입할 수 있고, 폴링 재구성에도 살아남는다.
    var displayNameDraft = ""
    /// 편집 행 안 1줄 안내(중복/쿨타임/길이). 열기·성공·취소 시 nil.
    var displayNameNotice: String?
    /// displayNameNotice 가 실패 사유인지(true=danger). 쿨타임/도움말은 false —
    /// 뷰가 notice != nil 로 추측하면 "일주일에 한 번" 안내가 빨갛게 뜬다.
    var isDisplayNameNoticeError = false
    /// 서버 profiles.display_name_changed_at 미러. **nil = 한 번도 안 바꿨다 = 지금 바로 가능**
    /// (가입 시 자동 생성된 이름은 '변경'이 아니다).
    var displayNameChangedAt: Date?
    /// 서버가 알려 준 '다시 바꿀 수 있는 시각'. changedAt 로 역산했다가 다시 더하는 왕복을 하지 않는다 —
    /// 그 왕복은 경계에서 화면의 월·일을 하루 밀어 버릴 여지만 키운다.
    var displayNameAvailableAt: Date?
    /// 지금은 바꿀 수 없는가(표시용). **뷰는 이 값만 읽는다** — canChangeDisplayName(now:)를 뷰가 직접 부르면
    /// 그 인자로 줄 값이 매초 갱신되는 displayNow 뿐이라, 팀 카드 본체가 초당 1회 무효화되고 sortedMembers
    /// 정렬이 초당 1회 다시 돈다(CheckMenuView 의 TeamPanel 이 금지한 바로 그 회귀).
    var isDisplayNameLocked = false
    /// 저장 왕복 중인지. isUpdatingTeamGoal 과 달리 **관찰 대상**이다 — 저장 버튼을 누른 동안 비활성으로
    /// 잠가야 연타로 두 번째 요청이 나가지 않는다.
    var isUpdatingDisplayName = false

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
    /// 마감 **직전에** 이 맥이 그 세션에 대해 들고 있던 소유 주장의 강도. 되돌리기가 그대로 물려받는다.
    /// 기본이 .weak 인 이유는 규칙 전체와 같다 — 모르면 약하다. 관찰 대상 아님(뷰가 읽지 않는다).
    @ObservationIgnored var lastAutoClosedClaimStrength: SessionClaimStrength = .weak
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
    /// 흡수 세션(다른 맥이 연 세션)은 종료 동기화 대상이 아니다 — 이 맥을 끄는 것이 저쪽 근무를 끝내지는
    /// 않는데, 여기서 마감하면 상대가 지금도 일하는 세션이 내 종료 시각으로 잘린다(그 뒤 근무는 통째로 소실).
    func finishWorkBeforeQuit(timeout: Double = 3) async {
        // 아래 stop() 이 종료 경로에서 온 것임을 알린다(가드보다 앞이다 — 이 함수에 들어온 시점이
        // 곧 종료 시퀀스 진입이고, 가드 순서가 바뀌어도 표식이 빠지지 않게).
        isTerminating = true
        guard session != nil, startedAt != nil, !adoptedRemoteSession else { return }
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
        // 되돌릴 대상이 사라졌으면 그 대상의 강도도 함께 잊는다 — 남기면 다음 자동 마감이 강도를 못 채운
        // 경로에서 앞 세션의 strong 을 물려받아, 남이 연 세션에 대고 '내가 열었다'고 주장하게 된다.
        if lastAutoClosedClaimStrength != .weak { lastAutoClosedClaimStrength = .weak }
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
        // 세션 ID 는 **만드는 순간 정규화**한다. Swift 의 UUID().uuidString 은 대문자인데 서버의
        // work_sessions.id / work_statuses.active_session_id 는 Postgres uuid 네이티브 타입이라 소문자로
        // 되돌아온다(입력은 대소문자 무관하게 받는다). 대문자로 들고 있으면 서버가 돌려준 **내 세션 ID** 와
        // 원시 == 비교가 전부 실패해, 근무 시작 후 첫 폴링(≈30초)마다 내 세션이 '남의 세션'으로 재흡수되고
        // 하트비트가 죽는다 — 그 창에서 뚜껑을 5분 넘게 닫거나 앱을 끄면 마감이 나가지 못해 스캐빈저가
        // 시작 시각으로 마감, 그 근무가 0초로 기록된다.
        currentSessionID = Self.canonicalSessionID(UUID().uuidString)
        // 이 세션은 내가 열었다. startedAt == nil 가드를 지나 여기 왔으니 앞선 경로가 이미 표식을 내렸어야 하지만,
        // 한 경로라도 리셋을 빠뜨리면 방금 만든 **내** 세션이 잠자기·12시간 마감과 하트비트에서 영구 제외돼
        // 아무도 닫지 못하는 세션이 된다. 소유권을 확정하는 이 지점에서 무조건 내린다.
        // 세션 ID 를 함께 영속하는 것이 핵심이다 — 이 값이 없으면 근무 중 앱이 재시작될 때(자동 업데이트·크래시·
        // 사용자가 껐다 켬·재부팅) 서버에 열려 있는 **내** 세션이 남의 것으로 판정돼 하트비트가 끊긴다.
        // **강한 소유**: 이 세션은 방금 이 맥이 만들었다. 부분 유니크 인덱스상 열린 세션은 사용자당 하나뿐이라
        // 이 사실을 주장할 수 있는 맥은 최대 한 대다 — 반납 규칙이 동전 던지기(사전식 device_id)에서
        // 결정적 판정으로 바뀌는 근거가 정확히 이 한 줄이다.
        claimSessionOwnership(currentSessionID, strength: .strong)
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
        // 사용자가 직접 누른 종료는 흡수 세션이어도 서버에 쓴다(아래 syncCurrentStatus) — 같은 사람의 명시적
        // 의사이기 때문이다. 그리고 그 세션은 여기서 끝나므로 표식도 영속된 소유 ID 도 함께 내린다.
        // 남겨 두면 (1) 다음에 이 맥에서 시작하는 근무가 '남의 세션'으로 오인돼 자동 마감·하트비트에서
        // 통째로 빠지고, (2) 이미 닫힌 ID 가 소유 표식으로 남아 다음 실행의 재시작 판정을 오염시킨다.
        releaseSessionOwnership()
        longSessionAnchor = nil
        clearLongSessionPrompt()
        sleepBeganAt = nil
        snapshot = WorkStatusSnapshot(status: .offWork, elapsedSeconds: accumulatedSeconds)
        stopTimerIfIdle()
        refreshMenuBarTitle()
        // 근무를 마치면 되돌리기 배너의 성립 조건이 다시 열린다(비근무 전용).
        refreshTimedBanner(now: now)
        syncCurrentStatus(durationSeconds: duration, sessionStartedAt: sessionStart, endedAt: now)
        // 수신 찔림 폴링이 '근무 중'으로 제한되므로(O1), 근무가 끝나는 이 순간 꼬리를 한 번 회수하지 않으면
        // 마지막 폴링 이후 도착한 찔림이 다음 근무 시작 때까지 전달되지 못한다(신선도 1시간을 넘기면 영구 소실).
        // 단, 종료 경로의 stop() 에서는 부르지 않는다 — take_pokes 는 서버에서 **원자 소비**라 응답 전에
        // 프로세스가 죽으면 그 찔림은 영구 소실되고(다음 실행이 보여줄 수 있었던 것), 종료 시점엔 말풍선을
        // 볼 사람도 없어 이득이 0이다.
        if !isTerminating {
            flushPokesOnWorkEnd()
        }
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
        // 흡수 세션은 이 맥의 것이 아니다 — 내 덮개를 닫은 시각으로 남의 근무를 마감하지 않고 **아무 것도 하지 않는다**.
        // 로컬 표시만 내리는 것도 무의미하다: 다음 폴링(≤30초)이 (.working, nil) 로 즉시 재흡수해 되돌려 놓는다.
        // 소유 맥이 진짜로 사라지면 스캐빈저가 마지막 신호 시각으로 마감하고, 그때 (.offWork,.some) 가지가
        // 로컬을 정확히 내린다 — 화면이 영원히 '근무중'으로 남는 경로는 그 연쇄가 닫는다.
        guard !adoptedRemoteSession else {
            self.sleepBeganAt = nil
            return
        }
        autoStop(endedAt: sleepBeganAt, message: "잠자기로 자동 근무종료됨")
    }

    // MARK: - 12시간 확인 (30분 무응답 자동 마감)

    /// 근무 틱에서 호출. 12시간 도달 시 확인 배너를 띄우고, 배너 노출 후 30분 무응답이면 12시간 시점으로 마감한다.
    func evaluateLongSession(now: Date) {
        // 흡수 세션의 '12시간'은 남의 맥이 잰 시간이다. autoStop 이 이미 막지만 여기서도 선두에서 끊는 이유는
        // **배너** 때문이다 — 마감만 막으면 확인 배너가 뜨고, 사용자가 [네, 근무 중이에요] 를 눌러 앵커를
        // 지금으로 되돌려도 그 세션은 여전히 남의 것이라 30분마다 되풀이되는 유령 배너가 된다.
        guard !adoptedRemoteSession else { return }
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
        // 흡수 세션(다른 맥이 연 세션)은 이 맥이 **자동으로** 마감하지 않는다. 상대는 지금도 일하고 있는데
        // 내 잠자기·12시간 판정으로 과거 시각 마감을 써 버리면 그 뒤 근무가 통째로 사라진다.
        // 호출자마다 가드를 흩뿌리지 않고 이 한 곳에서 막는 이유: 앞으로 추가될 자동 마감 경로도 자동으로
        // 안전해지기 때문이다(호출자 쪽 가드는 새 경로가 생기면 조용히 빠진다).
        // 로컬 표시를 여기서 내리지 않는 것도 의도다 — 다음 폴링(≤30초)이 즉시 재흡수해 되돌려 놓으므로
        // 무의미하고, 소유 맥이 사라지면 스캐빈저 마감 → (.offWork,.some) 가지가 로컬을 정확히 내린다.
        // 사용자가 직접 누른 종료는 이 경로가 아니라 stop() 이므로 영향받지 않는다.
        guard !adoptedRemoteSession else { return }
        // 잠자기/장시간 미확인 자동 마감도 로컬이 확정한 근무 상태 변경이라 세대를 올린다(낡은 응답의 재개 금지).
        workStateWriteGeneration &+= 1
        // 사유가 다른 이번 마감이 확정됐으므로 직전 자리 비움 되돌리기 대상은 무효다.
        clearAutoCloseUndo()
        // 서버 전송 duration 은 세션 전체(서버가 클리핑). 로컬 누적 가산만 종료일 자정으로 클리핑해 표시 점프를 막는다.
        let duration = max(0, Int(endedAt.timeIntervalSince(sessionStart)))
        accumulatedSeconds += max(0, Int(endedAt.timeIntervalSince(max(sessionStart, TeamWeeklyGoal.koreanDayStart(for: endedAt)))))
        accumulatedDayStart = TeamWeeklyGoal.koreanDayStart(for: endedAt)
        startedAt = nil
        // 이 세션은 여기서 실제로 마감된다 — 영속된 소유 ID 를 남기면 다음 실행이 이미 닫힌 세션을
        // '내 것'으로 되찾으려 들어(서버엔 없는 세션에) 하트비트를 쏘게 된다. 위 가드 덕에 흡수 세션은
        // 이 지점에 오지 못하므로 남의 소유 표식을 지울 위험은 없다.
        releaseSessionOwnership()
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
    /// (기본값을 상수에서 파생시킨다 — 이 주기가 곧 하트비트 주기이고, 백스톱 임계가 그 주기를 근거로
    /// 계산되므로 둘이 따로 놀면 임계의 여유분 계산이 조용히 어긋난다.)
    @ObservationIgnored var refreshLoopSliceSeconds: Double = WorkTimerStore.heartbeatIntervalSeconds

    /// 멤버십이 한 번도 확정된 적 없으면 1회 재확정한다(확정됐으면 요청 0건이라 유휴 비용 불변).
    /// 실행 킥(activateStoredSessionOnLaunch)이 오프라인 부팅으로 실패하면 currentTeamID 가 nil 로 남는데,
    /// 그 상태에서는 큐 드레인(performPendingOperation)이 throw 하고 하트비트·넛지도 전부 죽는다.
    /// 팝오버를 한 번도 열지 않는 사용자에게는 refresh 루프가 유일한 회복 경로다.
    func confirmMembershipIfNeeded() async {
        guard session != nil, !membershipConfirmed else { return }
        await confirmMembership()
    }

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
                        // 멤버십 미확정(= 실행 킥이 Wi-Fi 결합 전에 실패)은 유휴 1주기를 기다리지 않는다.
                        // 그동안 팀이 nil 이라 넛지·하트비트·큐 드레인이 전부 죽어 있기 때문이다.
                        // 확정돼 있으면 요청 0건이라 유휴 비용은 그대로고, 회복 상한만 1슬라이스로 내려간다.
                        await self?.confirmMembershipIfNeeded()
                        if self?.refreshLoopIsFast ?? false { break }
                    }
                }
                // 본문 맨 앞이어야 한다: performPendingOperation 은 teamID 가 없으면 throw 하므로,
                // 팀 확정이 큐 드레인보다 앞서야 오프라인에서 쌓인 근무가 **같은 주기에** 재생된다.
                await self?.confirmMembershipIfNeeded()
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
        let now = clock()
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
    /// 이 맥이 **직접 연** 진행 중 근무 세션의 ID. start() 가 클라에서 만든 그 값(= work_sessions 행 id 이자
    /// work_statuses.active_session_id)을 그대로 남긴다. 이 키가 재시작과 '남의 맥'을 가르는 유일한 결정적 근거다.
    static let ownedWorkSessionIDKey = "check.session.ownedWorkSessionID"
    /// 위 소유 ID 가 **사실**인지 **추측**인지(SessionClaimStrength.rawValue). ID 와 함께 영속하지 않으면
    /// 백스톱이 추측으로 세운 소유가 재시작 한 번으로 '내가 연 세션'으로 세탁된다 — 그 순간 진짜 소유자가
    /// 이 맥 앞에서 물러나므로, 고치려던 사고가 재시작을 통해 그대로 되살아난다.
    static let ownedWorkSessionStrengthKey = "check.session.ownedWorkSessionStrength"

    /// 세션 ID 정규화의 **유일한 지점**. 세션 ID 비교는 전부 이 함수를 거친다.
    ///
    /// 왜 필요한가: 앱은 UUID().uuidString(대문자)으로 세션 ID 를 만들고, 서버는 그 값을 Postgres uuid
    /// 네이티브 컬럼에 넣었다가 **소문자**로 돌려준다(work_sessions.id / work_statuses.active_session_id,
    /// 20260701000000_create_check_schema.sql). 같은 세션인데 문자열은 다르다. 원시 == 로 비교하면
    ///   (1) 재시작 복구의 1차 판정(isOwnedByThisMac)이 항상 실패해 내 세션이 흡수로 떨어지고,
    ///   (2) 재흡수 분기(applyRemoteOwnStatus)의 '서버 ID != 내 ID' 가 **항상 참**이 되어 근무 시작 직후
    ///       첫 폴링에서 내 세션이 남의 것으로 뒤집힌다 → 하트비트 정지 → 그 근무가 0초로 기록된다.
    /// LiveE2ETests 는 이 사실을 알고 이미 .lowercased() 비교를 했지만 Sources 쪽엔 정규화가 한 곳도 없었다.
    /// 앞으로 갈라지지 않게 **여기 한 곳**에만 규칙을 둔다(대소문자 무시 == 를 곳곳에 흩뿌리지 않는다).
    nonisolated static func canonicalSessionID(_ sessionID: String?) -> String? {
        guard let sessionID else { return nil }
        return sessionID.lowercased()
    }

    /// 이 맥이 연 진행 중 세션의 ID(없으면 nil). startedAt 은 영속되지 않으므로 재시작 직후의 소유권 판정은
    /// 오직 이 값으로만 할 수 있다. 읽을 때도 정규화한다 — v0.2.15 이하가 **대문자로 영속해 둔 값**이
    /// 그대로 남아 있는 맥(업그레이드 사용자)의 재시작 판정을 구제하는 지점이다.
    var ownedWorkSessionID: String? {
        Self.canonicalSessionID(defaults.string(forKey: Self.ownedWorkSessionIDKey))
    }

    /// 서버가 들고 있는 세션 ID 가 이 맥이 연 그 세션인지. 둘 중 하나라도 없으면 '모른다'이므로 거짓이다
    /// (모를 때 소유를 주장하면 살아 있는 다른 맥의 근무를 가로챈다 — 그건 D2 가 막으려던 바로 그 사고다).
    /// 비교는 반드시 정규화 경유다(대문자 로컬 ID vs 소문자 서버 ID 는 같은 세션이다).
    func isOwnedByThisMac(_ sessionID: String?) -> Bool {
        guard let sessionID = Self.canonicalSessionID(sessionID), let owned = ownedWorkSessionID else {
            return false
        }
        return sessionID == owned
    }

    /// 이 맥의 소유 주장이 어디서 왔는가. **반납 규칙의 유일한 결정자**다.
    /// - strong: 이 맥이 그 세션을 **실제로 열었다** — start() 가 만들었거나, 되돌리기 재개(reopen)를
    ///   이 맥이 서버에 보내 성공했다. 부분 유니크 인덱스(work_sessions_one_open_per_user)상 사용자당 열린
    ///   세션은 하나뿐이므로 **강한 소유자는 최대 한 명**이다(두 번째 start 는 23505 로 거절된다).
    /// - weak: 백스톱(updateAdoptedPresenceTracking)이 '7분째 아무도 안 돌보는 것 같다'고 세운 **추측**이다.
    ///   추측은 틀릴 수 있다(맥 A 의 네트워크가 잠깐 끊겼을 뿐일 수 있다).
    ///
    /// 모르는 값은 언제나 weak 로 읽는다 — 모를 때 '내가 열었다'고 우기면 진짜 소유자가 그 앞에서 물러난다.
    enum SessionClaimStrength: String {
        case strong
        case weak
    }

    /// 영속된 소유 주장의 강도(없거나 해석 불가면 weak). 이 값은 ownedWorkSessionID 가 가리키는 **그 세션**에
    /// 대한 것이다 — 다른 세션을 들고 있을 때 이 값을 그대로 쓰면 안 된다(ownsCurrentSessionStrongly 참조).
    var ownedSessionClaimStrength: SessionClaimStrength {
        SessionClaimStrength(rawValue: defaults.string(forKey: Self.ownedWorkSessionStrengthKey) ?? "") ?? .weak
    }

    /// 지금 들고 있는 세션(currentSessionID)에 대해 이 맥이 **강한 소유자**인가.
    /// 소유 ID 일치까지 함께 요구하는 이유: 강제 로그아웃 재로그인 복구 분기는 소유 표식을 건드리지 않은 채
    /// currentSessionID 만 서버 값으로 갈아 끼운다. 그때 옛 세션의 strong 을 새 세션에 그대로 적용하면
    /// 남이 연 세션에 대고 '내가 열었다'고 방송해, 진짜 소유자가 내 앞에서 물러난다.
    var ownsCurrentSessionStrongly: Bool {
        isOwnedByThisMac(currentSessionID) && ownedSessionClaimStrength == .strong
    }

    /// 이 세션의 소유권이 이 앱 인스턴스에 있다고 확정한다(표식 내림 + 소유 ID·강도 영속 + 흡수 관측 초기화).
    /// 소유권을 세우는 모든 경로(start / 되돌리기 재개 / 재시작 복구 / 백스톱 되찾기)가 여기를 지나야
    /// 한 경로라도 영속을 빠뜨려 다음 재시작이 자기 세션을 남의 것으로 오인하는 일이 없다.
    /// strength 에 기본값을 두지 않는 것은 의도다 — 새 경로가 생길 때 '이 소유는 사실인가 추측인가'를
    /// 반드시 한 번 판단하게 강제한다(기본값이 있으면 조용히 잘못된 쪽으로 굳는다).
    func claimSessionOwnership(_ sessionID: String?, strength: SessionClaimStrength) {
        adoptedRemoteSession = false
        resetAdoptedPresenceTracking()
        // 소유를 새로 확정하는 순간, 릴리스 규칙의 관측 장부도 '아직 아무것도 못 봤음'이다. 앞 세션에서
        // 본 남의 신호를 남기면 방금 되찾은(또는 방금 시작한) 세션을 첫 폴링에서 곧바로 도로 내려놓는다.
        resetForeignDeviceTracking()
        setOwnedWorkSessionID(sessionID, strength: strength)
    }

    /// 진행 중 세션이 끝났다(또는 이 맥의 것이 아니게 됐다). 표식과 영속된 소유 ID 를 함께 비운다.
    func releaseSessionOwnership() {
        adoptedRemoteSession = false
        resetAdoptedPresenceTracking()
        resetForeignDeviceTracking()
        setOwnedWorkSessionID(nil)
    }

    /// 소유 세션 ID 와 그 주장의 강도를 영속한다(nil 이면 둘 다 제거). 값이 같으면 쓰지 않는다 — 30초 폴링이
    /// 도는 경로라 매 주기 같은 값을 디스크에 쓰게 두지 않는다. **정규화해서 쓴다** — 저장 형태가 소문자로
    /// 통일돼야 서버가 돌려주는 값과 그대로 == 비교된다(읽기 쪽 정규화는 옛 대문자 잔존 값 구제용이다).
    ///
    /// strength 기본값이 .weak 인 이유: 이 함수를 강도 없이 부르는 자리(테스트 픽스처, 옛 호출부)는 출처를
    /// 밝히지 않은 주장이다. 모르는 주장을 strong 으로 두면 진짜 소유자가 그 앞에서 물러난다 — 기본값은
    /// 반드시 안전한 쪽(약함)이어야 한다.
    func setOwnedWorkSessionID(_ sessionID: String?, strength: SessionClaimStrength = .weak) {
        let canonical = Self.canonicalSessionID(sessionID)
        // 세션 ID 가 같아도 **강도는 바뀔 수 있다**(같은 세션을 백스톱으로 약하게 들고 있다가 되돌리기 재개로
        // 강해지는 경로가 실재한다). 그래서 ID 조기 반환 안에 강도 쓰기를 가두지 않고 먼저 맞춘다.
        let storedStrength = sessionID == nil ? nil : strength.rawValue
        if defaults.string(forKey: Self.ownedWorkSessionStrengthKey) != storedStrength {
            if let storedStrength {
                defaults.set(storedStrength, forKey: Self.ownedWorkSessionStrengthKey)
            } else {
                defaults.removeObject(forKey: Self.ownedWorkSessionStrengthKey)
            }
        }
        // 비교는 **저장된 원문**과 한다(정규화한 getter 가 아니라). 옛 버전이 대문자로 남긴 값은 getter 를
        // 통과하면 이미 같은 값으로 보여 영영 갈아 끼워지지 않고, 그 맥은 계속 읽기 쪽 정규화에만 의존하게 된다.
        // 여기서 한 번 이관해 두면 디스크 표현이 서버 표현과 같아진다(평상시엔 값이 같아 쓰기 0건 그대로).
        guard defaults.string(forKey: Self.ownedWorkSessionIDKey) != canonical else { return }
        if let canonical {
            defaults.set(canonical, forKey: Self.ownedWorkSessionIDKey)
        } else {
            defaults.removeObject(forKey: Self.ownedWorkSessionIDKey)
        }
    }

    /// 흡수 세션 생존신호 관측을 초기화한다. 흡수가 아니게 되는 모든 지점에서 부른다 —
    /// 남겨 두면 다음 흡수가 **직전 세션의** 신호를 '전진 없음'의 근거로 삼아 첫 폴링에 곧장 소유권을
    /// 주장해 버린다(살아 있는 다른 맥의 근무 가로채기).
    func resetAdoptedPresenceTracking() {
        adoptedLastSeenAt = nil
        adoptedLastSeenSessionID = nil
        // 정체 장부도 함께 비운다 — 남기면 새 세션의 첫 관측이 앞 세션에서 세어 둔 정체 시간/횟수를
        // 물려받아 곧바로 임계를 통과한다(= 방금 다른 맥이 연 멀쩡한 세션을 첫 폴링에 가로챈다).
        adoptedStallBeganAt = nil
        adoptedStallObservations = 0
    }

    /// 릴리스 규칙의 '남의 기기 행' 관측 장부를 비운다(소유권이 바뀌는 모든 지점에서 부른다).
    /// **resetAdoptedPresenceTracking 과 합치면 안 된다**: 그 함수는 흡수가 아닐 때 매 폴링 호출되는데
    /// (updateAdoptedPresenceTracking 의 첫 가드), 릴리스 규칙이 살아 있어야 하는 상태가 바로 그 '흡수 아님'
    /// 상태다. 합치면 장부가 매 폴링 비워져 '전진'을 영원히 관측하지 못한다 = 규칙이 다시 죽는다.
    func resetForeignDeviceTracking() {
        foreignDeviceLastSeenAt = [:]
        foreignDeviceTrackingSessionID = nil
    }

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
        // 소유 세션 ID(ownedWorkSessionIDKey)는 **일부러 남긴다**. 이 함수는 토큰 만료 강제 로그아웃도 타는데,
        // 그 경로는 진행 중 근무(startedAt)와 큐를 일부러 보존한다(아래 주석) — 그 근무의 소유권 증거만 지우면
        // 재로그인 후 재시작이 자기 세션을 남의 것으로 오인해 하트비트가 끊기고, 10분 뒤 스캐빈저가 마감한다.
        // 세션 ID 는 UUID 라 다른 계정과 겹칠 수 없고, 계정이 실제로 바뀌면 adoptWorkStateOwner 가,
        // 사용자가 직접 로그아웃하면 signOut 이 그 자리에서 지운다.
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
        // 계정이 바뀌면 남의 쿨타임/남의 하루 몫을 물려받지 않게 반드시 비운다. 남기면 새 계정이 자기 울트라를
        // 못 쓰거나(소진 미러 상속), 이미 다 쓴 사람이 "1번 남음"을 보고 눌러 서버 거절만 받는다.
        ultraPokeSpentDay = nil
        ultraRemainingToday = nil
        ultraRemainingDay = nil
        // 별명 편집/쿨타임도 계정에 묶인 상태다. 남기면 새 계정 화면에 앞 사람의 '언제부터 가능' 안내가 뜬다.
        isEditingDisplayName = false
        displayNameDraft = ""
        displayNameNotice = nil
        isDisplayNameNoticeError = false
        displayNameChangedAt = nil
        displayNameAvailableAt = nil
        isDisplayNameLocked = false
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
        // 진행 중 세션을 끊었으니 그 세션을 서술하던 흡수 표식과 영속된 소유 ID 도 함께 내린다. 남기면
        // (1) 새 계정으로 시작하는 첫 근무가 (start() 가 다시 내리기 전까지) 남의 세션으로 취급돼 자동 마감·
        // 하트비트에서 빠지고, (2) 앞 계정의 소유 ID 가 남아 새 계정 화면에서 소유권 판정에 쓰인다.
        releaseSessionOwnership()
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
