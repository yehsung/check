import AppKit
import Foundation
import Network
import Observation

/// 비밀번호 재설정(메일 OTP) 진행 단계. **화면 선택의 유일한 근거**라 별도 Bool 플래그를 두지 않는다 —
/// "보내는 중"과 "입력 대기"를 각각의 Bool 로 표현하면 둘 다 true 인 불가능한 조합이 언제든 만들어진다.
enum PasswordResetPhase: Equatable, Sendable {
    /// 재설정 화면을 띄우지 않음(기본).
    case idle
    /// 이메일 입력 대기.
    case enterEmail
    /// 코드 발송 왕복 중(취소 가능).
    case sending
    /// 코드**만** 입력 대기. 새 비밀번호는 여기서 받지 않는다 — 한 화면에 둘 다 두면 코드가 틀렸을 때
    /// 애써 입력한 새 비밀번호까지 같이 날아간다(사장님 실기에서 나온 요청의 실질 이유).
    case enterCode
    /// 코드 검증 왕복 중(취소 가능).
    case verifying
    /// 코드가 통과했다 — 새 비밀번호**만** 입력 대기. 이 단계에 있다는 것은 recovery 세션을 손에 쥐고 있다는 뜻이다.
    case enterNewPassword
    /// 비밀번호 설정 왕복 중(취소 가능).
    case submitting
}

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
    /// 비근무 상태에서 away_sync() 를 다시 부르기까지의 스로틀(초). 근무 중에는 매 폴링 부른다 —
    /// 마감 판정의 두 재료(임계·closeEligible)가 그 응답에만 있기 때문이다. 비근무일 때 이 값이 필요한 이유는
    /// 복원 창(6시간)뿐이라 2분 지연은 아무것도 바꾸지 않고, 38명 × 30초 폴링에 요청 하나를 더 얹지 않는다.
    static let awaySyncIdleThrottleSeconds: TimeInterval = 120
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
    /// 세션 갱신의 단일 주체(SessionRefreshCoordinator 주석 참조). withSessionRetry 와 리얼타임 선제 갱신이
    /// 반드시 이 문 하나를 지나야 refresh token 회전 경합이 생기지 않는다.
    @ObservationIgnored let sessionRefreshCoordinator = SessionRefreshCoordinator()
    let hasAnonKey: Bool
    let defaults: UserDefaults
    /// access/refresh 토큰 금고(TokenVault.swift). 비밀값은 defaults 가 아니라 **여기로만** 드나든다 —
    /// v0.2.36 까지 토큰이 defaults 평문(kingcheck.plist)에 남아 refresh token 탈취로 영구 계정 탈취가
    /// 가능했다(전면 감사 P0). userID/email 같은 비밀 아닌 값은 여전히 defaults 다.
    @ObservationIgnored let tokenVault: TokenVault
    /// 월간 AI 토큰 사용량 스토어. 프로덕션은 전역 공유(.shared)라 토큰 행/업로드 트랙이 같은 집계를 읽는다.
    /// 테스트(특히 ImageRenderer 렌더)는 격리 인스턴스를 주입해, 뷰 .task 가 도는 렌더 중에도 실홈 스캔이
    /// 테스트 러너의 .standard 를 오염시키지 않게 한다(감지 대신 의존성 주입으로 격리 — 구조적 결정성).
    let tokenUsage: TokenUsageStore
    /// Codex 계정 사용량 스토어(v0.2.41). 프로덕션은 CheckApp 이 `.live()` 를 넘기고, **기본값은 무해 인스턴스**(`inert()`)다 —
    /// 주입을 잊은 테스트가 실제 `codex app-server` 를 띄우는 일이 구조적으로 없다(realtimeTransport 의 fail-closed 와 같은 결).
    /// 업로드 래퍼(uploadTokenUsageIfNeeded(now:))가 스캔 뒤 refreshIfDue 를 부르고, 스냅샷은 업로드 본문과 내 행 툴팁에 실린다.
    let codexAccount: CodexAccountUsageStore
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

    /// 수동 [근무 종료] 후 자동 시작(넛지) 억제 중인가. 계약: **퇴근을 눌렀으면, 1시간 이상 완전히 자리를
    /// 비웠다 돌아오기 전까지는 다시 자동 출근시키지 않는다.** 이 표식이 없던 시절, 종료 후 컴퓨터를 계속
    /// 쓰면 5분 만에 근무가 저절로 재시작됐다(쿨다운은 '발동 후 1시간'뿐이라 저녁엔 이미 만료 — 프로브 실증).
    /// 영속한다 — 업데이트 재실행·재부팅으로 억제가 사라지면 같은 유령 출근이 그대로 재현된다.
    /// 뷰가 그리는 값이 아니므로 관찰 제외(자격 판정 클로저가 tick 마다 읽는다).
    @ObservationIgnored private(set) var autoStartSuppressed = false

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
    /// 할 일 기능이 켜져 있는가(기본 켬). 캐릭터 클릭의 뜻을 가르는 유일한 값이다 —
    /// 켜면 보드 여닫기, 끄면 아파하기. 한 클릭에 두 뜻을 담지 않기 위한 설정이다.
    var isTodoEnabled: Bool = true

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
            // 닫힌 동안 얼어 있던 팝오버 시계를 여는 순간 되맞춘다(티커는 닫힌 팝오버에 이 값을 쓰지 않는다 — M1).
            displayNow = clock()
            // 팝오버가 닫혀 있는 동안 티커가 멈춰 있었을 수 있으므로 유예형 배너 판정을 지금 시각으로 되맞춘다.
            refreshTimedBanner()
            // 감속(60초) 중이던 티커를 1초 주기로 되돌린다 — 안 그러면 최대 60초 동안 초침이 멈춘 팝오버가 보인다.
            restoreTickerCadenceIfSlowed()
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

    // ── 깨움 결합 게이트 (v0.2.38 M7) ──
    /// 네트워크 경로 관측자(주입점). **nil 이면 게이트가 없다** = 깨움 즉시 예전 순서. 테스트 프로세스의 기본값이 nil 이고
    /// 프로덕션은 defaultNetworkPath 가 NWPathMonitor 관측자를 채운다 — 리얼타임 전송자의 nil 규약과 같은 모양이다
    /// (주입을 잊은 테스트가 실제 경로 모니터를 띄우지도, 그 비동기 순서에 흔들리지도 않는다).
    @ObservationIgnored var networkPath: NetworkPathObserving? = WorkTimerStore.defaultNetworkPath()
    /// 결합 대기 상한(초). 넘기면 결합 여부와 무관하게 진행한다 — **영구 대기 금지**(관측자가 무엇이든 스토어가 상한을 건다).
    @ObservationIgnored var wakeGateTimeoutSeconds: TimeInterval = 10
    /// 상한 타이머의 잠(주입). passwordResetSleep 과 같은 규약 — 테스트가 짧게 줄인다.
    @ObservationIgnored var wakeGateSleep: @Sendable (TimeInterval) async -> Void = {
        try? await Task.sleep(for: .seconds($0))
    }
    /// 서 있는 게이트. 열리면(결합 또는 상한) 스스로 nil 이 되고 붙잡아 둔 루프를 되살린다(releaseWakeGate).
    @ObservationIgnored var wakeGateTask: Task<Void, Never>?
    /// 게이트가 내려 둔 루프들. 열릴 때 refresh 루프는 **본문 먼저**로, 찔림 폴링은 평소대로 다시 세운다.
    @ObservationIgnored var refreshLoopHeldByWakeGate = false
    @ObservationIgnored var pokePollHeldByWakeGate = false
    /// 게이트 뒤 첫 폴링 본문의 되맞춤 자리에서 넣을 리얼타임 `.didWake` 가 남아 있는가.
    @ObservationIgnored var wakeRejoinPending = false

    /// 마지막으로 팀 상태(work_statuses 4 GET)를 **성공적으로** 받은 시각 — 팝오버 재오픈 15초 스로틀(Q10)의 근거.
    /// v0.2.38 δ 가 이 파일을 못 고쳐 Sync 확장의 약참조 측면 표로 심었던 값을 저장 프로퍼티로 이관했다. 관찰 대상 아님.
    @ObservationIgnored var lastTeamStatusAt: Date = .distantPast

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

    /// **팝오버 시계.** CheckMenuView 의 초 단위 잎(큰 타이머·주간 게이지·팀원 행·쿨타임)이 읽는 '지금'이다.
    /// v0.2.38(M1)부터 티커는 **팝오버가 열려 있을 때만** 이 값을 매초 대입한다 — 닫혀 있어도 뷰 트리는 상주하므로
    /// 그 상태의 대입은 보이지 않는 화면을 매초 재평가·재레이아웃시킬 뿐이었다(계측: 유휴 main 스레드 1.06%,
    /// 15초 샘플 NSHostingView.layout 22~115회). 닫힌 동안 얼어 있다가 setMenuPresented(true) 가 여는 순간
    /// 즉시 되맞추므로 사용자에게는 보이지 않는다.
    /// 그래서 이 값은 **표시 전용**이다: 메뉴바 라벨·마일스톤·자동 마감·복원/흡수 경로는 이 값이 아니라 `clock()` 을
    /// 쓴다(todayDuration(at:)). 얼어 있는 시계로 정책을 판정하면 닫힌 팝오버가 곧 멈춘 근무 기록이 된다.
    var displayNow = Date()
    /// **오버레이 시계.** 캐릭터 패널의 타이머 라벨이 읽을 '지금'(팝오버 시계와 분리 — 둘이 한 값이면 한쪽만 보일 때도
    /// 두 표면이 함께 무효화된다). 티커는 **패널이 보일 때**(overlayClockIsShowing = 오버레이 켜짐 && 근무 중)만
    /// 매초 대입한다. 라벨은 overlayTodayDuration 을 읽는다(CheckCharacter3DView 전환은 β2 완료 후).
    var overlayNow = Date()
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
    //
    // **didSet 으로 defaults 에 영속한다(v0.2.36).** 메모리 전용이던 시절엔 오프라인 중 앱 종료/크래시가
    // 미반영 근무를 통째로 지웠다 — 큐가 곧 서버 쓰기이므로 그 소실은 근무 기록의 영구 소실이다.
    // 대입·append·removeFirst·removeAll(소유자 필터) 전부가 이 관찰자를 지나므로 변이 지점마다
    // 저장 호출을 흩뿌리지 않는다(한 곳이라 새 변이 경로도 자동으로 안전하다).
    // 재생 안전: 크래시 시점에 따라(서버 실행 뒤, removeFirst 영속 전) 같은 항목이 이중 재생될 수 있으나
    // start POST 는 ignore-duplicates, stop PATCH 는 세션 id 필터라 서버 멱등으로 무해하다.
    var pendingItems: [PendingWorkItem] = [] {
        didSet { persistPendingWorkQueue() }
    }
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
    /// 마지막으로 서버에 올린 계정 집계 키("월합|누적|상태"). usage 가 그대로여도 이 키가 바뀌면 올린다 —
    /// 계정 버킷은 로컬 로그와 무관하게 자라므로(다른 기기·클라우드) 변경 게이트가 usage 만 보면 계정값이 서버에 영영 안 간다.
    @ObservationIgnored var lastUploadedAccountKey: String?
    /// 마지막으로 일별 표(token_usage_device_daily)에 올린 날짜별 값(v0.2.41 토큰 잔디). 월간 upsert 가 성공한 직후 이 맵과
    /// 현재 값을 비교해 **바뀐 날만** 배열로 올린다(처음엔 전부). 성공에만 갱신 — 실패한 날은 다음 주기에 그대로 재시도된다.
    /// 로그아웃에 비운다(다음 계정은 처음부터). 관찰 대상 아님.
    @ObservationIgnored var lastUploadedDaily: [String: TokenUsageDailyValue] = [:]
    /// 마지막 업로드 시도 시각. 60초 스로틀 기준(난사 방지). 관찰 대상 아님.
    @ObservationIgnored var lastTokenUploadAt: Date = .distantPast
    /// 마지막 **배경** 토큰 스캔 시각(팝오버가 닫힌 근무 중에 도는 저빈도 경로, refreshTokenUsageInBackgroundIfDue).
    /// 업로드 스로틀과 따로 두는 이유: 저쪽이 재는 것은 '서버 왕복'이고 이쪽이 재는 것은 **전량 파일 순회**다 —
    /// 비싼 쪽이 이 스탬프고, 60/600초 주기의 유일한 근거다. 앱 재시작마다 초기화돼도 무해하다
    /// (첫 틱에 한 번 더 도는 것뿐). 관찰 대상 아님.
    @ObservationIgnored var lastBackgroundTokenScanAt: Date = .distantPast
    /// 마지막으로 하트비트로 보고한 스캔 시각. 같은 스캔을 두 번 보고하지 않게 하는 변경 게이트다
    /// (lastUploadedUsage 와 같은 규약 — 성공에만 갱신해 실패는 다음 주기가 그대로 재시도한다). 관찰 대상 아님.
    @ObservationIgnored var lastTokenScanHeartbeatAt: Date?

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
    /// 최근 12주 일별 근무 잔디(이슈 #3). heatmap/retro 와 같은 조회·같은 파싱에서 함께 계산되고 함께 비워진다.
    var dailyGrid: WorkDailyGrid = .empty
    /// 최근 12주 일별 AI 토큰 잔디(이슈 #3 의 토큰 절반). 같은 조회 안에서 서버 일별 표 + 로컬 일별 맵 + 계정 버킷을 합쳐 계산하고
    /// (WorkTimerStoreInsights), 주가 바뀌거나 로그아웃하면 근무 잔디와 함께 비워진다. 토큰 조회는 **독립 실패**다 — 못 받아도
    /// 근무 잔디·회고·히트맵은 그대로 그려진다. 수집 거부(tokenUsageCollect == false)면 항상 empty(패널도 섹션을 숨긴다).
    var tokenDailyGrid: TokenDailyGrid = .empty
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
            ?? displayNameChangedAt.map({ Self.displayNameUnlockDate(changedAt: $0) }) else { return true }
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

    /// 별명 변경이 다시 가능해지는 시각. 규칙은 **KST 자정 기준**이다 —
    /// '마지막 변경 + 7일'이 속한 날짜의 00:00 이며, 그 날이 되는 순간 전원이 함께 풀린다.
    ///
    /// 시각 단위(정확히 7×24시간)이던 시절엔 해제 순간이 하루 중 임의의 시각이라(8/5 17:52 → 8/12 17:52)
    /// "8월 12일부터"라는 안내가 그날 아침엔 거짓이었다(실사용 신고). 문구에 시각을 더하는 대신
    /// **규칙을 문구에 맞췄다** — 서버(20260812110000)와 같은 계산이다.
    nonisolated static func displayNameUnlockDate(changedAt: Date) -> Date {
        TeamWeeklyGoal.koreanDayStart(for: changedAt.addingTimeInterval(displayNameCooldownSeconds))
    }

    /// 쿨타임 안내 문구 — **화면에 나가는 문장 그대로**다. 날짜는 KST 기준이라 자정 근처에서 흔들리지 않고,
    /// 해제가 자정이므로 "N월 N일부터"는 그날 0시부터 문자 그대로 참이다.
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
            ?? displayNameChangedAt.map({ Self.displayNameUnlockDate(changedAt: $0) }) {
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

    // ── 울트라 패널(잔량 + 미션) ──
    /// 울트라 패널이 떠 있는가. **리그·토큰보드·콕찌르기·개인기록과 상호 배타이고, 그 배타는 양방향이다** —
    /// 한쪽만 걸면 다른 패널을 열어도 이 화면이 위에 남아 굳는다(closeUltraPanel 호출부를 세어 확인할 것).
    var isUltraPanelVisible = false
    /// 어디서 이 패널로 들어왔는가. [뒤로]가 돌아갈 곳을 정하는 유일한 근거다.
    private(set) var ultraPanelOrigin: UltraPanelOrigin = .home

    /// 초인종 링의 현재 상태. **W1 은 이 값을 읽기만 하고, 쓰는 것은 agent-realtime(W2)이다.**
    /// 출시 기본값 `.idle(.disabled)` 이 곧 "리얼타임 없음"이고, 그 상태에서 폴링이 예전 그대로 돈다.
    var realtimeState: RealtimeState = .idle(.disabled)
    /// 구독 직후 따라잡기가 **실패한** 시각(성공하면 nil 로 되돌린다). 화면 경고의 근거.
    var realtimeCatchUpFailedAt: Date?

    /// 리얼타임 한 벌(전송자·링·타이머·진단)의 수명 소유자. **저장 프로퍼티를 일곱 개 흩뿌리지 않는 이유**는
    /// 로그아웃/잠자기에서 "타이머 하나를 안 껐다"가 이 계층의 대표 누수이기 때문이다 — 한 덩어리면 셀 수 있다.
    /// 전송자가 nil 이면 링은 `.idle(.disabled)` 로 태어나 한 발짝도 움직이지 않는다(fail-closed).
    @ObservationIgnored let realtime: RealtimeRuntime

    /// 미션 보상 연출 싱크. onReactionTrigger 와 **따로 둔 이유**: 그쪽은 `shouldBeVisible` 게이트를 지나므로
    /// 캐릭터를 숨긴 사용자에게는 아무것도 안 뜬다. 보상은 서버가 재화를 이미 올렸고 되돌릴 수 없으므로
    /// 그 게이트를 우회해 peek 으로라도 알려야 한다(배선은 agent-overlay/W2 몫이다).
    @ObservationIgnored var onRewardTrigger: ((ReactionKind) -> Void)?

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
    // ── 울트라 재화 지갑 (v0.2.34) ──
    //
    // v0.2.33 의 세 미러(ultraPokeSpentDay / ultraRemainingToday / ultraRemainingDay)는 **통째로 지웠다.**
    // 그 셋은 "오늘 남은 횟수"라는 하루 귀속 개념을 표현하던 값인데, 이번 릴리스에서 울트라는
    // **이월되는 재화**가 됐다. 하루 스탬프를 그대로 두면 자정에 잔량을 버려, 패널 상단 잔량이
    // 다음 sync 까지 조용히 빈칸이 된다 — 재화는 자정에 사라지지 않는데.
    /// 내 울트라 **잔량**. nil = 아직 모름(한 번도 sync 를 못 했거나 실패). **날짜 스탬프가 없는 것이 설계다.**
    /// 화면은 nil 을 0 이 아니라 "—" 로 그린다 — 0 이라고 말하면 그건 거짓말이 될 수 있다.
    var ultraBalance: Int?
    /// 서버가 말해 준 잔량 상한(nil = 모름). **클라에 리터럴 5 를 박지 않는 이유가 이 프로퍼티다** —
    /// 상한은 서버 `ultra_balance_cap()` 하나가 정하고, 클라가 한 벌 더 가지면 서버가 바꿔도 화면만 옛 숫자를 말한다.
    var ultraBalanceCap: Int?
    /// **서버가 말해 준** 무제한 여부(관리자). 클라가 role 로 추측하지 않는다 — 판정은
    /// profiles.role='admin' 하나이고 그것을 아는 쪽은 서버뿐이다(UltraWalletResponse.unlimited 주석).
    /// 기본값 false = "아직 모른다"의 안전한 쪽(숫자를 그린다). 서버가 말해 준 적 없는 사용자에게
    /// 무제한이라고 말하는 것이 그 반대보다 훨씬 나쁘다.
    var ultraUnlimited = false
    /// 마지막 sync 가 **실패**했는가. 잔량 표시의 3분기(불러오는 중 / 못 읽었어요 / 정상)를 가른다.
    /// nil 잔량 하나로는 '아직 안 물어봤다'와 '물어봤는데 못 읽었다'를 가를 수 없다.
    var ultraBalanceFailed = false
    /// 미션 목록(표시용). 서버 응답에서 순수 변환(MissionProgress.rows)으로 만든다.
    var missions: [MissionProgress] = []
    /// 미션을 한 번이라도 성공적으로 받았는가(pokeDirectoryLoaded 와 같은 규약 — 빈 목록과 로드 전을 가른다).
    var missionsLoaded = false
    /// 연속 출근 일수. **표시 전용이고 보상이 없다**(사장님 확정 3). 화면에 보상 칩을 그리지 마라 —
    /// 없는 걸 약속하는 것은 거짓말이고, 서버는 스트릭으로 어떤 적립도 하지 않는다.
    var streakDays = 0
    var streakIncludesToday = false
    /// 미션을 **방금 달성해 울트라가 늘었다**는 지속 안내. 연출(.ultraCharged)은 2초면 사라지므로,
    /// 그것만으로는 자리를 비운 사용자에게 아무 증거도 남지 않는다.
    var missionNotice: String?
    /// 서버가 말해 준 미션 1호 목표 초(nil = 아직 모름). **판정용이 아니라 발화 시점 계산용이다** —
    /// 클라가 3시간을 넘겼다고 판단해도 받는지 여부는 서버가 정한다.
    @ObservationIgnored var ultraMissionTargetSeconds: Int?
    /// 마지막 지갑 sync 시각. `.periodic` 스로틀(5분)의 유일한 근거다.
    @ObservationIgnored var lastUltraWalletSyncAt: Date?
    // 내 토큰 사용량 공개 여부(profiles.token_usage_public 미러). 로그인 후 서버값 1회 로드, 토글은 낙관 반영.
    var tokenUsagePublic = true
    /// 공개 여부가 **확정**됐는가 — 서버 응답이 왔거나 **사용자가 직접 골랐거나**(setTokenUsagePublic 이 GET 전에 세운다:
    /// 폴링 첫 tick 이 그 선택을 덮지 않게). 그래서 이것은 '서버에서 받았다'의 증거가 아니다 — 그 용도는 아래 플래그다.
    @ObservationIgnored var tokenUsagePublicLoaded = false
    /// 수집 설정(token_usage_collect)이 **서버에서 실제로 도착**했는가. loadTokenUsagePrivacyIfNeeded 가 응답을 받았을 때만
    /// true, 로그아웃 리셋에서 false. Codex 계정 프로브(외부 프로세스)의 게이트가 이것이다(리뷰 2차 P2): tokenUsagePublicLoaded 를
    /// 게이트로 쓰면 로그인 직후 공개 토글 한 번이 '설정 도착'으로 읽혀 거부자의 맥에서 `codex app-server` 가 뜬다.
    @ObservationIgnored var tokenUsageCollectLoaded = false
    /// 집중 모드(콕찌르기 수신 거부, profiles.focus_mode 미러). 켜면 남이 나를 못 찌른다 — 판정은 서버가 한다.
    /// 뷰가 토글 상태를 그리므로 관찰 대상이다. 로그인 후 1회 로드(토큰 설정과 같은 GET)하고 토글은 낙관 반영.
    var focusMode = false
    // 내 토큰 사용량 **수집** 여부(profiles.token_usage_collect 미러). 공개 여부와 독립이다 —
    // 공개는 '남의 순위판에 뜨는가', 수집은 '서버에 쌓이는가'. 앱에서 바꾸는 값이 아니라 서버가 정한다.
    // 실효는 서버 트리거가 내고(구버전 클라도 함께 막힌다), 이 플래그는 헛업로드를 줄이는 부수 장치다.
    // 뷰가 읽지 않으므로 관찰 대상에서 뺀다.
    @ObservationIgnored var tokenUsageCollect = true
    // 수신 찔림 폴링 태스크(로그인 중 15초 타이머. 실제 take_pokes 는 근무중에만 나간다 — O1/takePokesIfWorking).
    // refresh 루프와 별도인 이유는 유휴 주기(수백 초)로는 말풍선 전달이 너무 늦기 때문이다.
    var pokePollTask: Task<Void, Never>?
    /// 진행 중인 drain. 있으면 새 요청을 만들지 않고 **트레일링 한 번**으로 접는다(requestDrain 주석).
    @ObservationIgnored var drainInFlight: Task<Void, Never>?
    /// drain 이 도는 동안 새 신호가 왔는가. 끝난 뒤 정확히 1회 더 돈다.
    @ObservationIgnored var drainPendingTrailing = false
    /// 수신 찔림 싱크. 오버레이 컨트롤러가 연결해 움찔+말풍선(숨김 시 peek)으로 표시한다(관찰 대상 아님).
    @ObservationIgnored var onPokesReceived: (([ReceivedPoke]) -> Void)?

    // ── 짧은 메시지(최대 3글자). 찔림과 **같은 표·같은 폴링**으로 도착한다(take_pokes 의 kind="message" 행). ──
    /// 아직 사용자에게 보여주지 않은 수신 메시지 **큐**(도착 순 FIFO). 마지막 1건만 남기지 않는 이유는
    /// 찔림과 메시지의 값이 다르기 때문이다 — 찔림은 "누가 불렀다"가 전부라 배치를 한 문장으로 합쳐도 손실이 없지만
    /// (CheckOverlayWindow.pokeBubbleText), 메시지는 보낸 사람이 3글자를 골라 담은 내용이고 take_pokes 는 서버에서
    /// **원자 소비**라 여기서 덮어쓰면 그 글자는 영영 복구할 수 없다. 15초 폴링이라 두 명이 동시에 보내면 한 틱에
    /// 여러 건이 오는데, 표시 수단인 말풍선은 한 번에 하나뿐이므로 큐로 세워 두고 한 건씩 흘린다.
    /// 찔림 싱크(onPokesReceived)처럼 콜백으로 흘리지 않는 이유도 같다 — 콜백은 배치를 통째로 던져
    /// 이 순서 규약을 우회한다. 표시 권한은 이 큐 하나에만 둔다.
    var receivedMessages: [ReceivedMessage] = []
    /// **말풍선으로 이미 뜬** 마지막 메시지 1건(팝오버의 "놓친 것 확인"용). 큐에서 소비될 때 여기로 옮겨 담기므로
    /// 큐가 비어도 남는다 — 이 칸이 없으면 자리를 비운 사이 온 "밥?"이 6초 뜨고 사라져, 서버가 이미 원자 소비한
    /// 그 글자를 확인할 방법이 앱 어디에도 없다.
    ///
    /// **왜 1건인가**(N건 이력이 아니라): 큐 단계의 손실과 성격이 다르다. 큐에서 덮어쓰면 '한 번도 안 뜬 것'이
    /// 사라지지만, 여기서 밀리는 것은 '떴는데 못 본 것'이다 — 앱은 찔림에 대해 이미 후자를 기록 없이 흘려보내고
    /// 있고, 메시지만 대화 이력을 갖는 것은 다른 제품이다. 팝오버 높이 예산(26명 목록에서 이미 654/700pt)도
    /// 목록을 감당하지 못한다. 한계는 분명하다: 한 틱에 여러 건이 와서 전부 표시되면 마지막 1건만 남는다.
    /// 그게 실제 문제로 확인되면 링 버퍼로 늘리면 되고, 그때 이 이름은 그 목록의 첫 원소로 남는다.
    ///
    /// **영속하지 않는다.** 3글자 메시지는 휘발성이 성격에 맞고, 디스크에 남기면 계정 전환·기기 간 불일치라는
    /// 버그 종을 통째로 들여온다(ultraPokeSpentDay 와 같은 판단).
    var lastShownMessage: ReceivedMessage?
    /// 메시지 전송 결과 1줄 안내. **pokeNotice 와 따로 둔다** — 두 동작이 같은 패널에 살아도 결과는 각자의 것이고,
    /// 한 칸을 나눠 쓰면 찌르기 실패 문구가 메시지 성공 위에 남는다(displayNameNotice 를 따로 둔 것과 같은 규약).
    var messageNotice: String?
    /// 대상별 메시지 쿨타임 만료 시각(pokeCooldownUntil 과 같은 규약 — 서버가 강제하고 클라는 미러링만 한다).
    var messageCooldownUntil: [String: Date] = [:]
    /// 전송 왕복이 떠 있는지. **관찰 대상**이다 — 보내는 동안 버튼을 잠그지 않으면 연타가 두 번째 요청을 내고
    /// 그 요청은 방금 자기가 만든 60초 쿨타임에 확정으로 거절당한다(isUpdatingDisplayName 과 같은 규약).
    var isSendingMessage = false

    // ── 내 앱 버전 보고(profiles.app_build / app_version) ──
    /// 이 프로세스가 읽어 올 버전. 기본은 번들이고 테스트가 갈아 끼운다 — Bundle.main 은 프로세스가 정하는
    /// 값이라 주입하지 않으면 "심어지지 않은 빌드"와 "심어진 빌드"를 같은 러너에서 둘 다 실증할 수 없다.
    @ObservationIgnored var appVersionProvider: () -> AppVersionReport? = {
        AppVersionReport.fromInfoDictionary(Bundle.main.infoDictionary)
    }
    /// 이번 실행에서 **이미 보고한** (계정 + 버전) 도장. 같으면 다시 보내지 않는다(lastUploadedUsage 와 같은 변경 게이트).
    ///
    /// **UserDefaults 에 영속하지 않는 이유**는 ultraPokeSpentDay 가 적어 둔 그대로다: 영속이 사 주는 건
    /// '실행당 헛요청 1회 절약'뿐인데(26명·무료 플랜에선 무의미), 대신 계정 전환·기기 간 불일치라는 버그 종을
    /// 통째로 들여온다. 게다가 여기선 방향이 더 나쁘다 — 서버 값이 어떤 이유로든 비면(복구·수동 조치)
    /// 영속 도장을 든 클라는 **영영 다시 안 보내고**, 그 사람은 아무에게도 메시지를 못 받는 상태로 굳는다.
    /// 실행마다 한 번 다시 말하는 쪽이 자가치유한다.
    ///
    /// 계정 ID 를 도장에 섞는 이유: 로그아웃 없이 세션만 갈리는 경로가 있어도 도장이 달라져 새 계정으로 다시 보고한다.
    @ObservationIgnored var reportedAppVersionStamp: String?

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

    // ── 비밀번호 재설정(메일 OTP) ──
    // 왜 앱 안에서 끝내는가: 재설정 메일의 링크는 `check://auth` 로 가는데 그 스킴을 등록한 앱이 없어
    // 실사용자에게는 빈 화면만 떴다(운영자가 Admin API 로 직접 풀어 주는 것이 유일한 복구였다).
    // 6자리 코드를 메일로 받아 앱에서 입력하면 브라우저·딥링크가 통째로 경로에서 빠진다.
    /// 재설정 진행 단계. UI 는 이 값 하나로 화면을 고른다(idle = 재설정 화면을 아예 띄우지 않음).
    var passwordResetPhase: PasswordResetPhase = .idle
    /// 사용자에게 보일 한국어 안내/오류 한 줄. 단계 전이·사전 검증 실패·서버 응답 지점에서만 대입한다.
    var passwordResetMessage: String?
    /// 코드를 보낸 주소(코드 입력 화면의 "어디로 보냈는지" 표시). **정규화된 값**이다 —
    /// 발송과 검증이 같은 문자열을 써야 GoTrue 가 같은 사용자로 본다(대소문자/앞뒤 공백이 갈리면 검증이 튕긴다).
    var passwordResetEmail = ""
    /// 재발송까지 남은 초. >0 이면 UI 가 [다시 받기]를 잠그고 이 숫자를 보여 준다. 0 이 곧 "지금 다시 받을 수 있다".
    var passwordResetResendSeconds = 0

    /// 지금 날아가 있는 재설정 왕복(발송 또는 검증·설정)의 Task. cancelPasswordReset 이 이걸 취소해
    /// **URLSession 요청 자체**를 끊는다(세대 토큰만으로는 요청이 끝까지 살아 서버에 헛부하를 남긴다).
    /// 관찰 대상 아님(뷰가 읽지 않는다 — 진행 표시는 phase 가 한다).
    @ObservationIgnored var passwordResetTask: Task<Void, Never>?
    /// 재발송 카운트다운 Task. 새 쿨다운을 걸 때/취소·성공으로 흐름이 끝날 때 교체·취소한다. 관찰 대상 아님.
    @ObservationIgnored var passwordResetCooldownTask: Task<Void, Never>?
    /// 재설정 흐름의 세대 토큰. 취소/새 시작마다 +1 한다. 모든 await 뒤에서 이 값을 다시 확인하므로
    /// **늦게 도착한 응답이 이미 닫힌 흐름의 상태를 되살리지 못한다** — 이 코드베이스가 sessionGeneration/
    /// previewGeneration 으로 반복해 쓰는 방어와 같은 규약이다(취소된 흐름이 사용자를 로그인시키는 사고 차단).
    /// 관찰 대상 아님.
    @ObservationIgnored var passwordResetGeneration = 0
    /// 코드 검증에 성공해 손에 쥔 recovery 세션. `enterNewPassword` 단계의 **실체**이자, 비밀번호가 거절돼도
    /// (6자 미만·이전과 동일) 버리지 않고 붙잡아 두는 값이다 — OTP 는 **1회용**이라 여기서 버리면 사용자는
    /// 멀쩡한 코드를 다시 받아야 하고 재발송 쿨다운에 갇힌다. 재시도는 이 세션으로 곧장 설정만 다시 친다.
    ///
    /// **절대 영속하지 않는다**(persistSession 을 태우지 않는다). 재설정은 로그인이 아니라 비밀번호 교체이고,
    /// 디스크에 남기면 다음 실행이 그 토큰으로 되살아나 "로그인한 적 없는데 로그인돼 있다"가 된다.
    /// 흐름이 끝나면(성공/취소) 반드시 비운다. 관찰 대상 아님.
    @ObservationIgnored var passwordResetVerifiedSession: SupabaseSession?
    /// 이번 재설정 흐름에서 코드를 **몇 번 보냈는가**. 쿨다운 길이가 발송 차수에 따라 다르기 때문에 필요하다:
    /// 첫 발송 뒤는 5초(맨 처음 메일이 실제로 안 갈 수 있어 바로 다시 눌러 볼 수 있어야 한다),
    /// 그 뒤 재전송부터는 60초. 취소/재시작(clearPasswordResetState)에서 0 으로 되돌린다. 관찰 대상 아님.
    @ObservationIgnored var passwordResetSendCount = 0
    /// 카운트다운 대기(주입 가능). 프로덕션은 실제 1초 수면이고, 테스트만 갈아 끼워 60초를 실제로 자지 않게 한다
    /// (CheckUpdateCheck.watchdogSleep 과 같은 주입 규약). 시각 판정은 주입 clock 이 하므로 이 둘을 함께
    /// 바꾸면 카운트다운 전체가 결정적으로 돈다. 관찰 대상 아님.
    @ObservationIgnored var passwordResetSleep: @Sendable (Double) async -> Void = {
        try? await Task.sleep(for: .seconds($0))
    }

    // 잠자기 정책: willSleep 시각을 기록해 didWake 에서 잠든 시간을 판정한다.
    var sleepBeganAt: Date?

    // MARK: - 자리 비움 자동 마감 (v0.2.35 / docs/away-close.md)

    /// 이 맥이 관측한 **마지막 의미 있는 입력** 시각(키·클릭·스크롤 — 마우스 이동 제외, v0.2.17 계약).
    /// 새 타이머를 만들지 않는다: 근무 중 하트비트(30초)가 advanceMeaningfulInput 으로 전진시킨다.
    /// **단조 증가만** 허용하고, 화면 잠금·비콘솔이면 전진하지 않는다 — 잠그고 자러 간 사람은 잠근 시각부터
    /// 카운트되고, 잠금 화면에서 남이 비밀번호를 두드려도 내 근무가 연장되지 않는다. 관찰 대상 아님.
    @ObservationIgnored var lastMeaningfulInputAt: Date?
    /// 마지막 의미 있는 입력 후 경과 초(주입). 기본은 NudgeScheduler 의 그 함수 **그대로** — 신호원이 두 벌이
    /// 되는 순간 "무엇이 사용 중인가"의 정의가 갈린다(넛지는 마우스 이동을 빼는데 여기선 포함, 같은 사고 재발).
    @ObservationIgnored var meaningfulIdleSeconds: () -> TimeInterval = NudgeScheduler.meaningfulIdleSeconds
    /// 지금 이 세션이 사람 앞에 있는가(주입). 기본은 화면 잠금 아님 + 콘솔 세션.
    @ObservationIgnored var inputSessionUsable: () -> Bool = NudgeScheduler.consoleSessionUsable
    /// 서버가 소유하는 자리 비움 정책. **nil 이면 away 마감을 하지 않는다** — 임계를 모르는 채 리터럴로
    /// 마감하는 것이 이 기능에서 가장 나쁜 실패 모드다(구버전 서버·오프라인·RPC 실패 전부 여기로 떨어진다).
    @ObservationIgnored var awayPolicy: AwayPolicy?
    /// 서버가 본 내 열린 세션(lastInputAt/closeEligible). 판정은 이 값과 로컬 관측의 **max** 로 한다.
    @ObservationIgnored var awayOpenSession: AwayOpenSession?
    /// 복원 가능한 자동 마감 세션(서버가 창을 소유한다). 뷰가 배너로 그리므로 관찰 대상이다.
    var awayRestorable: AwayRestorableSession?
    /// 위 두 값이 **어느 계정의 것인가**. 로그아웃/계정 전환 경로가 이 파일 밖(WorkTimerStoreAuth)에 있어
    /// 그쪽을 건드리지 않고도 남의 배너가 새 계정 화면에 남지 않게 하는 잠금이다(restorableAwaySession 참조).
    @ObservationIgnored var awayStateOwnerUserID: String?
    /// 복귀(자동 시작) 순간에 "이어 붙일까요?"를 물어야 하는가. UI 는 W2 가 그린다 — 스토어는 상태만 세운다.
    var awayRestorePromptPending = false
    /// 복원 RPC 왕복 중. 버튼 연타로 두 번 나가지 않게 하는 게이트(관찰 대상 — 버튼이 비활성을 그린다).
    var isRestoringAwaySession = false
    /// away_sync() 를 마지막으로 부른 시각(스로틀 판정). 관찰 대상 아님.
    @ObservationIgnored var lastAwaySyncAt: Date = .distantPast
    /// 이 서버가 자리 비움 스키마를 갖고 있는가(= away_sync() 가 실제로 응답했는가).
    /// **새 컬럼을 보내는 유일한 게이트다.** 브루 배포는 앱이 db push 보다 먼저 나가는 창을 만드는데,
    /// 그때 last_input_at 을 실으면 하트비트가 통째로 400 이 되고 10분 뒤 서버가 살아 있는 세션을 마감한다.
    /// away_sync 는 같은 마이그레이션 묶음에 있으므로 그 응답이 곧 "새 컬럼이 있다"는 증거다. 관찰 대상 아님.
    @ObservationIgnored var awayServerSupported = false

    /// 뷰가 읽는 유일한 복원 배너 출처. 계정이 바뀌었으면 **스스로 침묵한다** — 로그아웃은 이 스토어의 다른
    /// 파일에서 일어나고, 그 경로가 away 상태를 지우는 것을 잊어도 남의 마감이 새 계정 화면에 뜨지 않는다.
    var restorableAwaySession: AwayRestorableSession? {
        guard let session, awayStateOwnerUserID == session.userID else { return nil }
        return awayRestorable
    }
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


    /// 오늘 누적(초) — **팝오버 시계 기준**(뷰 전용 접근자). 닫힌 팝오버에서는 그 시계가 얼어 있으므로 정책·라벨·복원
    /// 경로는 이 값을 읽지 말고 `todayDuration(at: clock())` 을 써라(M1 — 시계 3종 분리).
    var todayDuration: Int { todayDuration(at: displayNow) }

    /// 오버레이 타이머 라벨용 오늘 누적(초) — 오버레이 시계 기준. 패널이 보일 때만 매초 바뀐다.
    var overlayTodayDuration: Int { todayDuration(at: overlayNow) }

    /// 주어진 시각 기준 오늘 누적(초). **근무 기록의 유일한 산식**이고 어떤 티커·표시 시계에도 매달리지 않는다 —
    /// 메뉴바 라벨(refreshMenuBarTitle)·마일스톤(evaluateTimeMilestones)·복원/흡수 경로가 `clock()` 을 넣어 부른다.
    func todayDuration(at now: Date) -> Int {
        let dayStart = TeamWeeklyGoal.koreanDayStart(for: now)
        // 누적 기여는 그 값이 '오늘' 것일 때만 센다: 스탬프(accumulatedDayStart)가 오늘 자정 이후면 유효,
        // 아니면 0. 자정을 넘겨 어제 누적이 오늘 표시를 부풀리거나 새 날 마일스톤을 오발화시키지 않게 한다.
        let accumulatedContribution = accumulatedDayStart >= dayStart ? accumulatedSeconds : 0
        guard let startedAt else { return accumulatedContribution }
        // 진행 세션 기여를 KST 자정으로 클리핑한다: 자정을 넘긴 세션이 오늘 표시를 부풀리거나 자정 직후
        // 마일스톤이 오발화하지 않게 하고, 시계 되돌림으로 음수가 되면 0으로 클램프한다.
        let effectiveStart = max(startedAt, dayStart)
        return accumulatedContribution + max(0, Int(now.timeIntervalSince(effectiveStart)))
    }

    /// 상태 전이 지점(근무 시작·종료·복원·흡수·되돌리기)에서 표시 시계 둘을 그 시각으로 맞춘다. 전이는 어차피
    /// snapshot 재대입으로 두 표면을 다시 그리므로 여기서의 대입은 "닫힌 팝오버를 매초 건드리지 않는다"(M1)와
    /// 무관하다 — 그 규약은 **티커**의 것이다. 전이 직후 첫 그림이 낡은 시계로 그려지지 않게 하는 것이 목적이다.
    func stampDisplayClocks(_ now: Date) {
        displayNow = now
        overlayNow = now
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
        // ★ 기본값이 **nil** 이다(KeychainTokenVault() 가 아니라). 기본 인자는 호출 지점에서 평가되므로
        //   금고를 여기서 만들면 주입을 잊은 테스트가 서명 안 된 러너로 실제 로그인 키체인을 오염시킨다.
        //   nil 은 아래에서 defaultTokenVault 로 풀리고, 그 분기가 테스트 프로세스를 걸러 낸다.
        tokenVault: TokenVault? = nil,
        workspaceNotifications: NotificationCenter? = NSWorkspace.shared.notificationCenter,
        tokenUsage: TokenUsageStore = .shared,
        // ★ 기본값이 **nil** 이다(라이브 프로브가 아니라). nil 은 아래에서 무해 인스턴스로 풀린다 — 주입을 잊은 테스트가
        //   실제 `codex` 프로세스를 띄우지 않는다. 프로덕션 조립은 CheckApp 한 곳뿐이고 소스 계약 테스트가 되묻는다.
        codexAccount: CodexAccountUsageStore? = nil,
        // ★ 기본값이 **nil** 이다(라이브 전송자가 아니라). 이 저장소는 기본값이 라이브라서 스텁 주입을
        //   잊은 테스트가 실네트워크로 새어 나간 188초짜리 플레이키를 겪었다 — 그 종을 구조적으로 봉한다.
        //   여기서는 주입을 잊으면 소켓이 **아예 안 열린다**(fail-closed). 프로덕션 조립은 CheckApp 한 곳뿐이고,
        //   그 사실은 소스 계약 테스트가 되묻는다(`LiveRealtimeTransport(` 가 프로덕션에 정확히 1회).
        realtimeTransport: RealtimeTransport? = nil
    ) {
        self.realtime = RealtimeRuntime(transport: realtimeTransport)
        self.service = service
        self.defaults = defaults
        let resolvedVault = tokenVault ?? Self.defaultTokenVault(defaults: defaults)
        self.tokenVault = resolvedVault
        self.tokenUsage = tokenUsage
        self.codexAccount = codexAccount ?? CodexAccountUsageStore.inert()
        milestoneTracker = MilestoneTracker(defaults: defaults)
        hasAnonKey = SupabaseConfig.anonKey(environment: environment) != nil
        email = defaults.string(forKey: Self.emailKey) ?? ""
        displayName = defaults.string(forKey: Self.displayNameKey) ?? ""
        isOverlayEnabled = defaults.object(forKey: Self.overlayEnabledKey) as? Bool ?? true
        isTodoEnabled = defaults.object(forKey: Self.todoEnabledKey) as? Bool ?? true
        // 수동 [근무 종료]의 자동 시작 억제를 복구한다. 단, 앱이 1시간 넘게 죽어 있었다면(밤새 꺼짐·재부팅)
        // 그 공백 자체가 '부재'이므로 여기서 푼다 — 살아 있는 동안의 공백 관측(onAbsenceGap)은 스케줄러가
        // 하지만, 앱이 꺼져 있던 시간은 마지막 생존 스탬프와의 차이로만 잴 수 있다.
        autoStartSuppressed = defaults.bool(forKey: Self.autoStartSuppressedKey)
        if autoStartSuppressed,
           let lastAlive = defaults.object(forKey: Self.nudgeLastAliveAtKey) as? Date,
           Date().timeIntervalSince(lastAlive) >= NudgeScheduler.rearmGapSeconds {
            autoStartSuppressed = false
            defaults.removeObject(forKey: Self.autoStartSuppressedKey)
        }
        // 기기 식별자는 최초 1회 생성 후 영속한다 — 맥 2대가 서로의 월 토큰 원장을 덮어쓰지 않게 하는 키(결함1).
        deviceID = Self.resolveDeviceID(defaults: defaults)
        let restoredSession = Self.restoredSession(from: defaults, vault: resolvedVault)
        session = restoredSession
        // 이번 실행에서 쌓일 큐/진행 중 근무의 주인은 복구된 세션의 계정이다(비로그인 시작이면 첫 로그인이 정한다).
        workStateOwnerUserID = restoredSession?.userID
        // 이전 실행이 못 보낸 근무 큐를 복원한다(오프라인 중 종료/크래시 생존 — didSet 영속의 반대편).
        // 소유자 필터는 여기서 하지 않는다 — 항목마다 소유자가 붙어 있고, 로그인 확정 시점의
        // adoptWorkStateOwner 가 남의 것만 골라 버린다(강제 로그아웃 보존 계약과 같은 자리).
        pendingItems = Self.restoredPendingWorkQueue(from: defaults)
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
        // 어떤 경로로든 근무가 시작되면 억제는 끝이다 — 수동 시작은 명시적 의사이고, 넛지 시작은
        // 억제 중엔 자격 미달이라 여기 오지 못하므로 이 한 줄이 억제를 세탁하는 일은 없다.
        clearAutoStartSuppression()
        // 근무 상태를 내가 바꿨음을 세대 토큰으로 알린다 — in-flight 였던 낡은 팀 상태 응답이 이 시작을 되돌리지 못하게.
        workStateWriteGeneration &+= 1
        // 새 근무를 시작하면 직전 자동 마감 되돌리기는 무효다(옛 세션으로 현 세션을 덮어쓰지 못하게 즉시 끊는다).
        clearAutoCloseUndo()
        stampDisplayClocks(now)
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
        // 새 세션이 시작됐다 — 이전 세션의 잠자기 마감 정정 마커는 이 시점부터 낡은 관측이다.
        // 남기면 이 세션과 무관한 옛 sleepBeganAt 이 다음 정정의 재료로 오용될 수 있어 여기서 끊는다.
        clearPendingSleepClose()
        // 근무 시작은 그 자체가 입력이다(수동은 클릭, 넛지 시작은 그 앞 5분의 실제 사용이 근거다).
        // 이 한 줄이 없으면 오전에 자리 비움으로 마감된 사람의 **옛 관측**(예: 10:30)이 그대로 남아,
        // 16:05 에 새로 연 세션의 판정 재료가 된다 — 세션 시작 가드가 막긴 하지만 그 가드 하나에
        // 기대는 대신 여기서 정확한 값을 세운다.
        lastMeaningfulInputAt = now
        snapshot = WorkStatusSnapshot(status: .working, elapsedSeconds: 0)
        startTimer()
        refreshMenuBarTitle()
        // 근무 상태가 바뀌면 유예형 배너의 성립 조건도 뒤집힌다(되돌리기는 비근무 전용).
        refreshTimedBanner(now: now)
        syncCurrentStatus()
        // 근무 시작 직후의 창을 닫는다: takePokesIfWorking 은 `startedAt != nil` 을 요구하는데,
        // 그 값이 방금 섰으므로 다음 폴링 tick(최대 15초) 전까지 도착한 찔림이 붕 뜬다.
        // 리얼타임이 켜진 뒤에도 이 1회는 남는다 — 구독 전이보다 근무 시작이 먼저인 순서가 존재한다.
        requestDrain()
        // ★ 초인종은 **근무 중에만** 붙는다(v0.2.34). 서버의 poke_user / ultra_poke_user / send_message 가
        //   전부 target_not_working 게이트를 갖기 때문에 비근무 소켓은 받을 것이 원리적으로 없다.
        //   그래서 로그인 지점(startStatusRefreshLoop)이 아니라 **여기**가 링이 출발하는 자리다 —
        //   위 requestDrain 바로 뒤인 이유는 근무 게이트(realtimeMayConsumePokes)가 startedAt 을 보는데
        //   그 값이 이 함수 앞부분에서 이미 섰기 때문이다.
        startRealtimeIfPossible()
    }

    func stop(now: Date = Date()) {
        guard let startedAt else { return }
        // stop() 의 호출자는 전부 사용자의 명시적 의사다(팝오버 토글·12시간 배너 [지금 종료]·앱 종료 시퀀스).
        // 자동 마감은 autoStop/서버 경유라 이 함수를 타지 않는다. 그러므로 여기서 자동 시작을 억제한다 —
        // "원치 않으면 근무 종료를 누르면 된다"(v0.2.12 계약)가 실제로 성립하려면 종료가 붙어 있어야 한다.
        //
        // 단, **종료 시퀀스의 stop() 은 예외다.** finishWorkBeforeQuit 의 startedAt != nil 가드를 지나
        // 여기 왔다는 것 자체가 사용자가 [근무 종료]를 누르지 **않은** 채 앱이 끝나는 상황이라는 뜻이므로
        // (⌘Q·재부팅·brew 업그레이드 — 눌렀다면 그 stop 이 먼저 startedAt 을 내렸다), 수동 종료용 억제를
        // 심으면 안 된다 — 심으면 1시간 안에 재실행될 때 init 재무장 판정이 억제를 유지해, 계속 일하는
        // 사용자의 자동 근무시작이 무기한 죽는다(8/20 업그레이드가 함대 전체에 심은 그 결함).
        if !isTerminating {
            suppressAutoStart(now: now)
        }
        // 종료도 내 write 다 — 세대를 올려 in-flight 낡은 응답의 '근무중' 흡수를 무력화한다.
        workStateWriteGeneration &+= 1
        // 서버 복구 경로(applyRemoteOwnStatus)로 시작된 세션이라 start() 를 안 탔을 수 있으므로 여기서도 끊는다.
        clearAutoCloseUndo()
        stampDisplayClocks(now)
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
        // 이 세션은 정상 경로로 닫힌다 — 잠자기 마감 정정 마커가 남아 있으면(덮은 채 들고 이동해 와서
        // 여기서 직접 종료한 경우) 낡은 관측이 다음 실행의 정정 재료로 오용되므로 함께 지운다.
        clearPendingSleepClose()
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
        // ★ 링은 **꼬리 회수 뒤에** 내린다. 회수는 폴링 경로이고 `pollingIsPausedByRealtime` 하나를
        //   보는데, 순서를 뒤집으면 그 판정이 "이미 안 붙어 있다"로 바뀌어 의미가 조용히 달라진다.
        //   지금은 상수가 억제를 꺼 두어 둘 다 같은 결과지만, v0.2.35 에서 상수를 지우는 날 이 순서가
        //   회수를 살릴지 죽일지를 결정한다 — 그때 판단할 근거를 여기 순서로 남긴다.
        //   `.signedOut` 이 아니라 `.workEnded` 인 것이 핵심이다: 로그아웃이 아니므로 accessToken 을
        //   지우지 않고, 다시 근무를 시작하면 그 토큰으로 곧바로 붙는다.
        realtimeApply(.workEnded, at: now)
    }

    // MARK: - 첫 출근 인사 (오늘 팀에서 내가 1등)

    /// 오늘 팀에서 내가 첫 출근인가. **이미 받아 둔 팀 상태만으로 판정한다**(새 요청 0).
    ///
    /// 네 조건을 모두 만족해야 한다:
    ///  1. 팀원이 나 말고도 있다 — 나뿐인 팀에서 매일 "1등"은 축하가 아니라 소음이다.
    ///  2. 남들은 오늘 근무 기록이 없고 지금 일하지도 않는다. (남이 밤샘 중이면 `.working` 으로,
    ///     새벽에 끊었으면 자정~종료 몫이 그 사람의 todayDurationSeconds 에 잡혀 여기서 걸린다.)
    ///  3. **나도 오늘 마친 근무가 없다.** 이 줄이 없으면 밤샘하다 새벽 3시에 끊고 3시 반에 다시 켠 사람에게
    ///     "1등 출근"이 뜬다 — 그 사람은 도착한 적이 없고 밤새 앉아 있었다.
    ///  4. **지금 세션이 오늘 시작됐다.** 어제 시작한 세션을 이어받은 것(자정 통과·밤샘 중 앱 재시작으로
    ///     서버 세션 흡수)은 '출근'이 아니라 '이어서 일하는 중'이다. 3번만으로는 이 경로를 못 막는다 —
    ///     진행 중 세션은 아직 누적에 들어가지 않아 '오늘 마친 근무'가 0으로 보이기 때문이다.
    var isFirstArrivalToday: Bool {
        guard let session else { return false }
        let dayStart = TeamWeeklyGoal.koreanDayStart(for: clock())
        // (4) 어제부터 이어지는 세션이면 출근이 아니다.
        if let startedAt, startedAt < dayStart { return false }
        // (3) 오늘 이미 마친 근무가 있으면 첫 출근이 아니다(누적 스탬프가 오늘 것일 때만 센다 — todayDuration 규약).
        if accumulatedDayStart >= dayStart, accumulatedSeconds > 0 { return false }
        let others = teamMembers.filter { $0.id != session.userID }
        guard !others.isEmpty else { return false }
        return others.allSatisfy { $0.todayDurationSeconds == 0 && $0.status != .working }
    }

    /// 오늘 첫 출근 인사를 아직 안 띄웠고 지금 내가 1등이면 true 를 돌려주며 하루치를 소비한다.
    /// 기록은 마일스톤과 같은 KST dayKey 장부라, 같은 날 앱을 껐다 켜도 다시 뜨지 않는다.
    func consumeFirstArrivalGreeting(now: Date? = nil) -> Bool {
        guard isFirstArrivalToday else { return false }
        return milestoneTracker.fireIfNeeded(MilestoneTracker.firstArrivalKey, now: now ?? clock())
    }

    // MARK: - 수동 종료의 자동 시작 억제 (1시간 부재로 재무장)

    /// 수동 [근무 종료]가 부른다. 자동 시작을 억제하고 그 사실을 영속한다.
    /// 자동 마감(잠자기·12시간·자리 비움)은 부르지 않는다 — 그쪽은 사용자 의사 표현이 아니므로
    /// 다음 사용 5분에 정상적으로 자동 시작되는 것이 맞다(이 기능의 존재 이유).
    func suppressAutoStart(now: Date? = nil) {
        autoStartSuppressed = true
        defaults.set(true, forKey: Self.autoStartSuppressedKey)
        // 생존 스탬프도 지금으로 찍는다 — 종료 직후 앱을 껐다 켜도(업데이트 재실행) '죽어 있던 1시간'이
        // 아직 차지 않았음을 다음 실행의 init 재무장 판정이 알 수 있게.
        defaults.set(now ?? clock(), forKey: Self.nudgeLastAliveAtKey)
    }

    /// 억제 해제(멱등). 수동 [근무 시작], 1시간+ 공백 관측(스케줄러 onAbsenceGap), 실행 시 재무장 판정이 부른다.
    func clearAutoStartSuppression() {
        guard autoStartSuppressed else { return }
        autoStartSuppressed = false
        defaults.removeObject(forKey: Self.autoStartSuppressedKey)
    }

    /// 스케줄러의 매 tick 생존 스탬프. 억제 중일 때만 영속한다(그 외엔 쓸 일도 읽을 일도 없다).
    /// 다음 실행의 init 이 이 값과의 차이로 "앱이 죽어 있던 시간"을 재무장 공백으로 잰다.
    func recordNudgeAlive(_ now: Date) {
        guard autoStartSuppressed else { return }
        defaults.set(now, forKey: Self.nudgeLastAliveAtKey)
    }

    // MARK: - 잠자기 정책 (5분 유예)

    /// willSleep. 근무중이면 덮은 시각을 기록한다(깨어날 때 잠든 시간을 재기 위함).
    func handleSleep(at date: Date = Date()) {
        // ⚠️ 아래 가드보다 **앞이다.** 기존 handleSleep 은 비근무 중 잠자기를 통째로 no-op 으로 만드는데,
        //    소켓은 근무 여부와 무관하게 떠 있다. 뒤로 내리면 "로그인만 하고 근무 안 하는 사람"의 소켓이
        //    뚜껑을 닫아도 안 내려가고, 그 죽은 소켓 위에서 깨어나 캐치업이 통째로 안 돈다.
        realtimeApply(.willSleep, at: date)
        guard let sessionStart = startedAt else { return }
        sleepBeganAt = date
        // 이 관측을 defaults 에 영속한다(v0.2.36). 뚜껑을 10분+ 닫으면 서버 스캐빈저가 이 세션을
        // abandoned(복원 불가)로 먼저 마감하는데, 깨어난 뒤의 handleWake 는 폴링이 로컬을 먼저 내리면
        // startedAt 가드에서 조기 반환하고, 잠자는 사이 앱이 죽으면(업그레이드) 아예 불리지 않는다 —
        // 메모리의 sleepBeganAt 만으로는 sleep 정정이 영영 못 나간다. 소비는 Sync 의 서버 정정 수용
        // 지점(applyRemoteOwnStatus 쪽)과 다음 실행이 맡고, 여기는 심는 쪽이다.
        // 흡수 세션은 심지 않는다 — 내 덮개 시각은 남의 세션의 마감 근거가 될 수 없다(autoStop 과 같은 계약).
        if !adoptedRemoteSession, let sessionID = Self.canonicalSessionID(currentSessionID) {
            persistPendingSleepClose(PendingSleepClose(
                sessionID: sessionID,
                sessionStartedAt: sessionStart,
                sleepBeganAt: date,
                lastInputAt: lastMeaningfulInputAt
            ))
        }
    }

    /// didWake. 잠든 시간이 5분 이하면 근무 연속으로 인정, 초과하면 덮은 시각으로 자동 마감한다.
    func handleWake(at date: Date = Date()) {
        // ⚠️ **맨 앞이다.** 아래로는 조기 리턴 가지가 셋(sleepBeganAt nil / 유예 이내 / 흡수 세션)이라
        //    뒤에 붙이면 실제 경로 대부분에서 재연결이 안 돈다 = 뚜껑을 열어도 찌르기가 영영 안 온다.
        // v0.2.38 M7 — 네트워크 관측자가 있으면(프로덕션) 재연결을 **결합 게이트 뒤**로 미룬다. 깨움 직후에는 모든
        // 루프의 Task.sleep 이 동시에 만료돼 Wi-Fi 가 붙기도 전에 요청이 폭주하고 소켓이 즉시 재연결을 시도했다.
        // 게이트가 열리면(satisfied 또는 상한 10초) 폴링 본문 1회 → 리얼타임 didWake 순서로 발사한다(beginWakeGate).
        // 관측자가 없으면(테스트 기본값·주입 안 함) 예전 그대로 즉시 재연결한다.
        // 아래 로컬 판정(잠자기 정정 마감)은 네트워크와 무관하므로 게이트를 기다리지 않는다 — 그 결과(정정 큐)만
        // 게이트 뒤에서 나간다(enqueueSync 가 게이트를 기다린다). 정정은 늦춰질 뿐 잃지 않는다.
        if networkPath != nil {
            beginWakeGate()
        } else {
            realtimeApply(.didWake, at: date)
        }
        guard let sleepBeganAt, startedAt != nil else {
            self.sleepBeganAt = nil
            return
        }
        let asleep = date.timeIntervalSince(sleepBeganAt)
        guard asleep > Self.sleepGraceSeconds else {
            self.sleepBeganAt = nil
            // 유예 안 잠자기 = 세션 계속. 스캐빈저 임계(10분)보다 짧아 서버가 먼저 마감했을 수 없으므로
            // 정정 마커는 여기서 소용을 다했다(남기면 다음 잠자기까지 낡은 관측이 산다).
            clearPendingSleepClose()
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
        // ★ 마감 시각 = min(뚜껑 닫은 시각, 마지막 의미 있는 입력). 맥은 **항상 무입력 뒤에 잠들기 때문에**
        //   (절전 설정만큼 기다렸다 잠든다) 지금까지는 매번 그 설정 길이만큼 덤이 붙었다.
        //   시작 시각보다 이르게 내려가지 않게 클램프한다 — 안 하면 duration 이 0이 되어 그 근무가 통째로 사라진다.
        //   (lastMeaningfulInputAt 은 근무 중 하트비트만 전진시키므로 이 세션의 관측이다.)
        let sleepEndedAt = max(
            startedAt ?? sleepBeganAt,
            min(sleepBeganAt, lastMeaningfulInputAt ?? sleepBeganAt)
        )
        autoStop(endedAt: sleepEndedAt, message: "잠자기로 자동 근무종료됨", reason: .sleep)
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
                message: "장시간 미확인으로 자동 근무종료됨",
                reason: .longSession
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

    // MARK: - 자리 비움 자동 마감 (v0.2.35 / docs/away-close.md)

    /// 마지막 의미 있는 입력 시각을 전진시킨다(단조 증가). 근무 중 하트비트가 30초마다 부르고,
    /// 반환값은 그 요청에 그대로 실린다. **새 타이머를 만들지 않는 것이 이 함수의 존재 이유다.**
    ///
    /// 전진하지 않는 두 경우:
    ///  · 화면 잠금/비콘솔(inputSessionUsable 거짓) — 잠그고 자러 간 사람은 잠근 시각에서 멈추고,
    ///    잠금 화면에서 남이 비밀번호를 두드려도 그 입력이 내 근무를 연장하지 않는다.
    ///  · 관측이 없거나(무한대) 값이 뒤로 가는 경우 — 시계 되돌림·이벤트 소스 리셋이 과거를 만들어도
    ///    이미 관측한 입력을 무효로 만들지 않는다.
    @discardableResult
    func advanceMeaningfulInput(now: Date) -> Date? {
        guard inputSessionUsable() else { return lastMeaningfulInputAt }
        let idle = meaningfulIdleSeconds()
        guard idle.isFinite, idle >= 0 else { return lastMeaningfulInputAt }
        // 미래 시각을 서버에 보내지 않는다(서버도 least(last_input_at, now()) 로 한 번 더 누른다).
        let observed = min(now.addingTimeInterval(-idle), now)
        guard let current = lastMeaningfulInputAt else {
            lastMeaningfulInputAt = observed
            return observed
        }
        if observed > current { lastMeaningfulInputAt = observed }
        return lastMeaningfulInputAt
    }

    /// 판정 기준 시각 = **max(로컬 관측, 서버가 계산한 내 모든 기기 행의 max)**.
    /// 로컬 단독으로 판정하면 "아이맥 켜둔 채 노트북에서 작업"이 결정론적으로 매일 오마감된다(공격이 잡았다).
    /// 서버 단독으로도 안 된다 — 내 맥의 방금 입력은 다음 하트비트까지 서버에 없다.
    func awayLastInputAt() -> Date? {
        [lastMeaningfulInputAt, awayOpenSession?.lastInputAt].compactMap { $0 }.max()
    }

    /// 근무 틱에서 호출(evaluateLongSession 과 같은 자리). 임계를 넘도록 입력이 없으면 **마지막 입력 시각으로**
    /// 소급 마감한다. away 는 long_session 보다 **먼저** 평가한다 — 더 이른 시각이고 복원 가능한 사유다.
    ///
    /// 마감하지 않는 조건(하나라도 걸리면 그대로 통과한다. 모를 때의 안전한 기본값은 "안 끊는다"다):
    ///  1. 흡수 세션(다른 맥이 연 세션) — 남의 근무를 내 무입력으로 마감하지 않는다.
    ///  2. **서버가 임계를 안 줬다**(구버전 서버·오프라인·RPC 실패). 임계는 서버가 소유한다(사장님 확정).
    ///  3. `closeEligible == false` — 혼합 함대(구버전 맥이 섞인 사용자)는 통째로 면제다. 클라가 서버보다
    ///     30분 먼저 발화하므로, 이 게이트를 클라가 무시하면 서버 쪽 완화는 도달조차 못 한다.
    ///  4. 서버가 든 열린 세션이 내 세션이 아니다(찢어진 읽기·다른 맥의 세션) — 남의 판정 근거로 마감 금지.
    ///  5. 기준 시각이 세션 시작보다 이르다 — 서버 백스톱의 `started_at <= last_input` 가드와 같은 조건이다.
    ///     이게 없으면 0초 세션이 만들어져 그 근무가 통째로 사라진다.
    ///  6. 경계는 **배타적**이다(정확히 임계면 마감하지 않는다 — 서버 부등호와 같게 맞춘다).
    func evaluateAwaySession(now: Date) {
        guard !adoptedRemoteSession else { return }
        guard startedAt != nil else { return }
        guard let policy = awayPolicy else { return }
        guard let open = awayOpenSession, open.closeEligible else { return }
        guard let localSessionID = Self.canonicalSessionID(currentSessionID),
              Self.canonicalSessionID(open.sessionID) == localSessionID
        else {
            return
        }
        guard let lastInput = awayLastInputAt() else { return }
        guard let sessionStart = startedAt, sessionStart <= lastInput else { return }
        guard now.timeIntervalSince(lastInput) > policy.closeThresholdSeconds else { return }
        autoStop(endedAt: lastInput, message: "자리 비움으로 자동 근무종료됨", reason: .away)
    }

    /// 자동 시작(넛지)이 발화하는 **바로 그 순간** — 이 앱에서 "돌아왔다"가 확실한 유일한 사건이다.
    /// 복원 가능한 마감이 있으면 새 세션을 조용히 열지 말고 물어야 한다(true 를 돌려준다).
    /// 컨트롤러(CheckOverlayWindow.nudgeAutoStart)가 이 값을 보고 말풍선/배너로 잇는다 — UI 는 W2 소유다.
    ///
    /// 여기서 묻지 않으면 그 사람은 영영 모른다: 자동 시작은 끌 수 없는 기본 동작이고, 팝오버를 그 창 안에
    /// 열지 않으면 6시간 뒤 창이 닫혀 그날 오전이 영구 소실된다(PICK 이 억울함의 근원으로 지목한 경로).
    @discardableResult
    func offerAwayRestoreOnAutoStart(now: Date? = nil) -> Bool {
        let now = now ?? clock()
        guard startedAt == nil else { return false }
        guard let restorable = restorableAwaySession else { return false }
        // 만료 판정은 서버가 준 값으로만 한다(클라 시계를 되돌려 창을 늘릴 수 없다).
        if let expiresAt = restorable.expiresAt, now >= expiresAt { return false }
        if restorable.remainingSeconds <= 0 { return false }
        if !awayRestorePromptPending { awayRestorePromptPending = true }
        return true
    }

    /// 복원 제안을 닫는다(사용자가 "아니요"를 눌렀거나 복원이 끝났다). 배너 자체(awayRestorable)는
    /// 서버가 소유하므로 여기서 지우지 않는다 — 다음 폴링이 여전히 복원 가능하다고 하면 팝오버에 남아 있어야 한다.
    func dismissAwayRestorePrompt() {
        if awayRestorePromptPending { awayRestorePromptPending = false }
    }

    /// 자리 비움 상태를 통째로 비운다(계정 전환 등 이 스토어가 아는 초기화 지점).
    func clearAwayState() {
        lastMeaningfulInputAt = nil
        awayServerSupported = false
        awayPolicy = nil
        awayOpenSession = nil
        if awayRestorable != nil { awayRestorable = nil }
        awayStateOwnerUserID = nil
        if awayRestorePromptPending { awayRestorePromptPending = false }
        lastAwaySyncAt = .distantPast
    }

    // MARK: - 잠자기 마감 정정 마커 (v0.2.36 계약 스텁 — 의미 구현·배선·테스트는 웨이브 소유자가 완성)

    /// 미결 잠자기 마감 마커의 영속 키. 잠자는 사이 앱이 죽어도(업그레이드·크래시) 다음 실행이
    /// 서버의 abandoned 마감을 sleep 으로 정정할 수 있어야 하므로 defaults 에 남긴다.
    static let pendingSleepCloseKey = "check.sleepClose.pending"

    func persistPendingSleepClose(_ marker: PendingSleepClose) {
        guard let data = try? JSONEncoder().encode(marker) else { return }
        defaults.set(data, forKey: Self.pendingSleepCloseKey)
    }

    func pendingSleepCloseMarker() -> PendingSleepClose? {
        guard let data = defaults.data(forKey: Self.pendingSleepCloseKey) else { return nil }
        return try? JSONDecoder().decode(PendingSleepClose.self, from: data)
    }

    func clearPendingSleepClose() {
        defaults.removeObject(forKey: Self.pendingSleepCloseKey)
    }

    /// 자동 마감을 파일 밖(WorkTimerStoreSync 의 서버 정정 수용 지점)에서도 부를 수 있게 하는 내부 관문.
    /// autoStop 자체는 파일-private 을 유지한다(호출자 가드를 한 곳에 모으는 기존 계약 보존).
    func closeOwnedSessionLocally(endedAt: Date, message: String, reason: AutoCloseReason) {
        autoStop(endedAt: endedAt, message: message, reason: reason)
    }

    /// 지정한 종료 시각으로 로컬 상태를 즉시 마감하고, 기존 직렬 sync 경로(enqueueSync)로 서버에 반영한다.
    /// syncMessage 는 사유 문구로 세팅한다(이후 refresh 가 "동기화됨"으로 정규화할 수 있음 — 즉시 피드백 목적).
    ///
    /// reason 은 **서버 어휘 그대로**(work_sessions.auto_closed_reason)다. 기본값을 두지 않는 것은 의도다 —
    /// 새 자동 마감 경로가 생길 때 "이 마감은 복원 대상인가"를 반드시 한 번 판단하게 강제한다.
    /// 사유가 안 남으면 복원 RPC 가 not_restorable 로 거절해 그 사람은 시간을 되찾을 방법이 없다.
    private func autoStop(endedAt: Date, message: String, reason: AutoCloseReason) {
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
        // 자동 마감(모든 사유)이 확정됐다 — 이 세션의 잠자기 마감 정정 마커도 소용을 다했다.
        // handleWake 가 sleep 사유로 여기 온 경우가 대표다: 정정할 마감을 지금 이 자리에서 직접 내보내므로
        // (아래 syncCurrentStatus 가 사유를 실어 나른다) 마커가 더 살아 있으면 이중 정정의 재료만 된다.
        clearPendingSleepClose()
        snapshot = WorkStatusSnapshot(status: .offWork, elapsedSeconds: accumulatedSeconds)
        stopTimerIfIdle()
        refreshMenuBarTitle()
        // 자동 마감도 근무 상태 확정이라 배너 판정을 되맞춘다(자동시작 [취소] 는 여기서 사라진다).
        refreshTimedBanner()
        syncCurrentStatus(
            durationSeconds: duration,
            sessionStartedAt: sessionStart,
            endedAt: endedAt,
            autoCloseReason: reason
        )
        syncMessage = message
        // 자동 마감(잠자기·12시간 미확인·자리비움)도 근무 종료다. 여기 한 줄이 없으면 뚜껑을 열어
        // `.didWake` 로 막 다시 붙은 소켓이 곧바로 이어지는 자동 마감 뒤에도 그대로 떠 있다 —
        // 받을 것이 없는 연결이 하루 종일 하트비트만 태우는 정확히 그 모양이다.
        realtimeApply(.workEnded, at: endedAt)
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
            closeUltraPanel()
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
        closeUltraPanel()
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
        // 메시지 결과 문구도 같은 이유로 여기서 죽인다(pokeNotice 주석의 그 회귀 — 나갔다 돌아오면 낡은 줄이 남는다).
        // 수신 큐(receivedMessages)는 **건드리지 않는다**: 그건 패널이 아니라 말풍선의 것이고,
        // 패널을 닫았다고 아직 한 번도 안 뜬 글자를 버리면 take_pokes 가 이미 소비한 그 글자는 영영 사라진다.
        messageNotice = nil
        // 반면 '이미 뜬' 마지막 메시지는 여기서 **소비**한다. 이 패널이 그걸 보여주는 유일한 화면이라
        // 닫았다는 것이 곧 "봤다"의 증거다 — 안 지우면 5분 뒤 다시 열었을 때 같은 말이 새 메시지처럼 또 뜬다.
        // (한 번도 안 열어 본 경우는 여기로 오지 않으므로, 나이 만료는 폴링이 따로 맡는다 — expireLastShownMessage.)
        lastShownMessage = nil
    }

    /// 콕찌르기 버튼 액션. 사용자 목록 페이지를 토글하고, 여는 순간 디렉토리를 로드한다. 다른 패널과 상호 배타.
    func togglePokePanel() {
        if isPokePanelVisible {
            closePokePanel()
        } else {
            isPokePanelVisible = true
            isLeaderboardVisible = false
            closeTokenBoard()
            closeUltraPanel()
            isInsightsPanelVisible = false
            loadPokeDirectory()
            // 패널을 여는 순간 지갑을 한 번 맞춘다. 잔량 배지가 제목 행에 상시 떠 있으므로
            // 낡은 숫자를 그리면 그게 곧 거짓말이다(미션 적립도 이 호출 안에서 일어난다).
            syncUltraWallet(reason: .panelOpen)
        }
    }

    /// 울트라 패널을 **연다**(토글이 아니다 — 진입점이 둘이라 토글은 배지 두 번 탭에서 엉킨다).
    ///
    /// ★ blocker UI-2: origin 이 `.poke` 여도 **closePokePanel() 을 부르지 않는다.** 그 함수는
    ///   lastShownMessage / pokeNotice / messageNotice 를 죽이는데(그쪽 주석: "닫았다는 것이 곧 봤다의 증거다"),
    ///   **배지를 탭한 것은 '봤다'가 아니다.** take_pokes 는 서버 원자 소비라 그렇게 지운 3글자는 복구 불가다.
    ///   그래서 여기서는 `isPokePanelVisible = false` 한 줄만 내린다.
    func openUltraPanel(from origin: UltraPanelOrigin) {
        ultraPanelOrigin = origin
        if origin == .poke {
            isPokePanelVisible = false
        }
        isUltraPanelVisible = true
        isLeaderboardVisible = false
        closeTokenBoard()
        isInsightsPanelVisible = false
        syncUltraWallet(reason: .panelOpen)
    }

    /// 울트라 패널을 닫는 **유일한** 경로. 다른 패널을 여는 네 곳도 전부 여기를 지난다(상호 배타 양방향).
    func closeUltraPanel() {
        guard isUltraPanelVisible else {
            // 이미 닫혀 있으면 origin 도 건드리지 않는다 — 다른 패널 토글이 부를 때 진입 맥락을 지우면
            // 콕찌르기에서 들어와 있던 사용자의 [뒤로]가 엉뚱한 곳으로 간다.
            return
        }
        isUltraPanelVisible = false
        missionNotice = nil
        if ultraPanelOrigin == .poke {
            // togglePokePanel 이 아니라 직접 세운다 — 그 토글은 열려 있으면 closePokePanel 을 타서
            // 위 blocker UI-2 의 부작용(안 본 메시지 소비)을 **두 번째로** 일으킨다.
            isPokePanelVisible = true
            loadPokeDirectory()
        }
        ultraPanelOrigin = .home
    }

    /// 개인 기록 버튼 액션. 내 근무 리듬/지난주 회고 페이지를 토글하고, 여는 순간 세션을 로드한다. 다른 패널과 상호 배타.
    func toggleInsightsPanel() {
        isInsightsPanelVisible.toggle()
        if isInsightsPanelVisible {
            isLeaderboardVisible = false
            closeTokenBoard()
            closePokePanel()
            closeUltraPanel()
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
                // 주기는 매 반복 앞에서 다시 정한다: 평소 1초, 표시 없는 근무가 1시간 넘게 이어지면 60초(분 경계 정렬).
                // 표시값은 wall-clock(clock()) 파생이라 주기가 얼마든 누적 오차가 없다 — tolerance 로 웨이크업을 병합해도 안전하다.
                guard let delay = self?.armNextTickDelay() else { return }
                try? await Task.sleep(for: .seconds(delay), tolerance: .milliseconds(200))
                // 스토어가 해제됐으면 루프를 빠져나간다 — weak self 라 tick 는 no-op 이 되지만 루프 자체는 계속
                // 돌아 좀비가 되므로 self 소멸 시 명시적으로 탈출한다. 취소(감속 해제의 재시작)도 여기서 끝낸다 —
                // 옛 루프가 마지막 틱을 한 번 더 쏘면 새 루프와 겹친다.
                guard let self, !Task.isCancelled else { return }
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
        // 티커가 서면 감속 장부도 접는다 — 다음 근무의 '표시 없는 1시간'은 처음부터 다시 센다.
        displayIdleSince = nil
        currentTickDelay = 1
    }

    // MARK: - 티커 감속 (v0.2.38 M1 덤)

    /// 표시 없는 근무(오버레이 시계 안 보임 + 팝오버 닫힘)가 이 시간(초) 넘게 이어지면 티커를 감속한다.
    static let tickerSlowdownAfterSeconds: TimeInterval = 3600
    /// 감속 주기(초). 메뉴바 라벨이 분 단위(HH:MM)인 동안만 쓰이므로 사용자가 보는 것은 바뀌지 않는다.
    static let slowTickIntervalSeconds: TimeInterval = 60

    /// 표시 없는 상태(팝오버 닫힘 && 오버레이 시계 안 보임)가 시작된 시각. 티커가 매 틱 갱신하고, 표시가 생기면 nil.
    @ObservationIgnored var displayIdleSince: Date?
    /// 티커가 마지막으로 정한 주기(초). 1 = 평소, 그 밖 = 감속 중(분 경계 정렬로 1…60). 관찰 대상 아님.
    @ObservationIgnored var currentTickDelay: TimeInterval = 1

    /// 오버레이 시계가 보이는가(= overlayNow 를 매초 대입할 이유가 있는가). 패널 자체의 표시 판정(CheckOverlayWindow)은
    /// 여기서 모른다 — 스토어가 아는 두 사실(토글·근무 중)만으로 판정한다. 그 둘이 참인데 패널이 다른 이유로 숨어 있는
    /// 창(전체화면 등)은 짧고, 그동안의 비용은 예전과 같다.
    var overlayClockIsShowing: Bool { isOverlayEnabled && startedAt != nil }

    /// 다음 틱까지 잘 시간(초). 티커 루프가 매 반복 앞에서 부른다(currentTickDelay 장부 갱신 포함).
    func armNextTickDelay() -> TimeInterval {
        let delay = nextTickDelay(now: clock())
        currentTickDelay = delay
        return delay
    }

    /// 감속 판정 + 분 경계 정렬. 순수 함수(장부는 건드리지 않는다) — 테스트가 직접 부른다.
    ///
    /// 감속 조건 셋(전부 참일 때만 60초):
    ///  1. 근무 중(티커가 도는 이유가 근무일 때만 — 팀원 초침 때문에 도는 티커는 팝오버가 열려 있어 애초에 제외),
    ///  2. 팝오버 닫힘 && 오버레이 시계 안 보임이 **1시간 넘게** 이어졌다(displayIdleSince),
    ///  3. 메뉴바 라벨이 분 단위다 — MenuBarStatusFormatter.duration 은 1시간 미만을 MM:SS 로 그리므로 그동안은
    ///     초침이 라벨에 보인다. 임계를 여기서 다시 선언하지 않고 포맷터 결과로 판정한다(출처 하나).
    /// 근무 기록 정확성은 주기와 무관하다: 시각은 항상 clock() 이고 todayDuration(at:)·자동 마감 시각은 관측 시각이
    /// 아니라 사건 시각(마지막 입력·12시간 앵커)에서 계산된다. 감속이 늦추는 것은 **판정 시점**뿐이다(≤60초).
    func nextTickDelay(now: Date) -> TimeInterval {
        guard startedAt != nil, !isMenuPresented, !overlayClockIsShowing,
              let since = displayIdleSince,
              now.timeIntervalSince(since) >= Self.tickerSlowdownAfterSeconds
        else { return 1 }
        let today = todayDuration(at: now)
        guard Self.menuBarLabelIsMinuteGranular(seconds: today) else { return 1 }
        // 분 경계에 맞춰 깨운다 — HH:MM 이 실제 분 넘김보다 늦게 바뀌지 않게(정렬 뒤로는 정확히 60초 간격).
        return Self.slowTickIntervalSeconds - TimeInterval(today % 60)
    }

    /// 메뉴바 라벨이 이 누적값의 분 안에서 초를 보이지 않는가. 같은 분의 두 시각(정각·+30초)이 같은 문자열이면 분 단위다.
    static func menuBarLabelIsMinuteGranular(seconds: Int) -> Bool {
        let minuteStart = seconds - seconds % 60
        return MenuBarStatusFormatter.duration(minuteStart) == MenuBarStatusFormatter.duration(minuteStart + 30)
    }

    /// 표시 조건이 다시 생겼다(팝오버 열림·오버레이 켜짐). 감속 중이던 티커를 즉시 1초 주기로 되돌린다.
    /// 감속 중이 아니면 티커를 건드리지 않는다 — 재시작은 첫 틱을 1초 미루므로 헛재시작은 초침을 한 번 멈칫하게 한다.
    func restoreTickerCadenceIfSlowed() {
        displayIdleSince = nil
        guard currentTickDelay != 1, tickerTask != nil else { return }
        currentTickDelay = 1
        tickerTask?.cancel()
        tickerTask = nil
        stopTimerIfIdle()
    }

    /// 30초 refresh 루프의 적응형 주기 판정. 근무중/팝오버 열림/미반영 큐가 있으면 빠른 주기(30s)로,
    /// 그 외 유휴에선 느린 주기(300s)로 돈다. 팝오버를 여는 순간의 즉시 refresh(.task)가 감속 지연을 메운다.
    var refreshLoopIsFast: Bool {
        startedAt != nil || isMenuPresented || !pendingItems.isEmpty
    }

    /// 미션 1호(그날 누적 3시간) 목표의 **클라 힌트**. 서버 `mission_work_seconds()` = 10800 과 같은 값이지만
    /// **판정의 출처가 아니다** — 이 숫자는 "이제 서버에 물어볼 만하다"를 정할 뿐이고, 받았는지는 서버가 답한다.
    /// 서버가 목표를 바꾸면 첫 sync 응답의 target_seconds 가 ultraMissionTargetSeconds 를 채워 자가 교정되고,
    /// 그 전에도 5분 주기 `.periodic` sync 가 어차피 잡는다(그래서 이 값이 틀려도 코인이 소실되지 않는다).
    /// 값의 출처는 **하나**다 — 미션 줄의 진행 바 폴백과 같은 상수를 쓴다(둘로 갈리면 화면과 발화가 어긋난다).
    static let missionWorkSecondsHint: Int = MissionProgress.defaultTargetSeconds
    /// 발화 임계. 서버가 말해 준 값이 있으면 그걸 쓰고, 모르면 힌트를 쓴다.
    var missionWorkSeconds: Int { ultraMissionTargetSeconds ?? Self.missionWorkSecondsHint }

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
        // 초인종도 같은 자리에서 시도한다. 다만 **로그인만으로는 붙지 않는다**(v0.2.34) — 이 호출은
        // 이미 근무 중인 맥(저장 세션으로 재실행한 경우)만 통과시키고, 그 밖에는 근무 게이트에서
        // 조용히 되돌아온다. 근무가 시작되는 자리는 start() 이고, 서버 동기화로 근무가 복원되는 자리는
        // 위 루프의 reconcileRealtimeWithWorkState() 다.
        // 전송자가 없으면(킬스위치 off·테스트) 이 호출은 아무 일도 하지 않고, 폴링은 위 한 줄 그대로
        // 돈다 — 리얼타임을 통째로 빼도 나머지가 온전히 동작해야 한다는 계약이 이것이다.
        startRealtimeIfPossible()
        guard refreshTask == nil else { return }
        startRefreshLoopTask(runBodyFirst: false)
    }

    /// refresh 루프 Task 본체. `runBodyFirst` 는 깨움 결합 게이트가 열린 직후 전용이다(v0.2.38 M7) — 첫 반복의 잠을
    /// 건너뛰고 본문부터 돈다(게이트가 미뤄 둔 그 1회 = 단일 tick). 평소 시작은 예전처럼 한 슬라이스를 자고 시작한다.
    /// 본문은 이 안에 그대로 둔다(메서드로 뽑지 않는다) — `self?.reconcileRealtimeWithWorkState()` 배선을 소스 계약
    /// 테스트가 이 모양 그대로 읽는다.
    func startRefreshLoopTask(runBodyFirst: Bool) {
        refreshTask?.cancel()
        refreshTask = Task { @MainActor [weak self] in
            var skipSleep = runBodyFirst
            while !Task.isCancelled {
                let slice = self?.refreshLoopSliceSeconds ?? 30
                let tolerance = Duration.seconds(slice / 6)
                if skipSleep {
                    // 게이트가 열린 직후: 미뤄 둔 본문을 지금 돈다(잠 없이 1회).
                    skipSleep = false
                } else if self?.refreshLoopIsFast ?? false {
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
                // 잠에서 깬 반복이 취소된 루프의 것이면 본문을 쏘지 않는다 — 깨움 게이트가 루프를 내리는 순간 만료된
                // 잠이 그대로 본문으로 이어지면 게이트가 막으려던 바로 그 폭주가 된다(M7).
                if Task.isCancelled { return }
                // 본문 맨 앞이어야 한다: performPendingOperation 은 teamID 가 없으면 throw 하므로,
                // 팀 확정이 큐 드레인보다 앞서야 오프라인에서 쌓인 근무가 **같은 주기에** 재생된다.
                await self?.confirmMembershipIfNeeded()
                await self?.retryPendingSync()
                // v0.2.38 S3: `sendHeartbeatIfWorking → refreshTeamStatus → (되맞춤) → refreshAwayStateIfNeeded` 를
                // work_tick RPC 1건으로 합친다(docs/work-tick.md). 전송만 합치고 의미는 그대로다 — 응답 조각은 그 세
                // 함수가 소비하던 경로로 흘러가고, RPC 를 못 쓰면(함수 없음·실행권 회수·5xx 연속) 같은 틱 안에서 그
                // 세 함수를 같은 순서로 부른다. 되맞춤은 팀 상태와 away 사이 그 자리 그대로라 틱을 둘로 나눠 넘긴다.
                let tick = await self?.workTickIfPossible()
                // 팀 상태가 반영된 **직후**에 링을 근무 게이트에 되맞춘다. 근무 상태는 start()/stop() 말고도
                // 여기서 뒤집힌다: 앱 재시작 복구·다른 맥이 연 세션 흡수·서버가 세션을 닫음.
                // 이 한 줄이 없으면 근무 중 앱을 재시작한 맥은 (start() 를 타지 않으므로) 초인종이 영영
                // 안 붙고, 서버가 세션을 닫아 준 맥은 비근무인 채로 소켓을 계속 들고 있는다.
                self?.reconcileRealtimeWithWorkState()
                // 자리 비움 정책·복원 창(away 조각 반영 또는 폴백 refreshAwayStateIfNeeded). **팀 상태 반영 뒤**여야 한다 —
                // 방금 큐에서 나간 마감 PATCH 가 이미 서버에 반영된 상태로 복원 대상을 묻게 된다.
                // 실패는 삼킨다(정책이 비워져 마감이 멈출 뿐, 팀 폴링은 그대로 산다).
                if let tick { await self?.finishWorkTick(tick) }
                await self?.refreshLeaderboardIfVisible()
                await self?.refreshTokenBoardIfVisible()
                await self?.refreshPokeDirectoryIfVisible()
                // 내 월간 토큰 사용량을 변경 게이트+60초 스로틀로 서버에 올린다(팀원 보드 최신화). 대부분 게이트에서 즉시 반환.
                // 팝오버가 **열려 있으면** 스캔의 소유자는 뷰 루프(CheckMenuView 의 runRefreshLoop)이므로 여기서는
                // 업로드만 한다. **닫혀 있으면** 그 뷰 루프가 없어 스캔 자체가 돌지 않는다 — 메뉴바를 안 여는 사람은
                // Claude/Codex 를 아무리 써도 서버에 0 으로 남았다(실측: 활동 중인데 이번 달 행이 없는 사람 8명).
                // 그래서 닫힌 동안에는 이쪽이 **근무 중일 때만** 저빈도로 직접 스캔한다.
                // 앱 시작부터 스캔이 돌지 않게 하던 원래 의도는 그 `startedAt != nil` 게이트가 승계한다.
                if self?.isMenuPresented == true {
                    await self?.uploadTokenUsageIfNeeded()
                } else {
                    await self?.refreshTokenUsageInBackgroundIfDue()
                }
                // 깨움 게이트가 미뤄 둔 리얼타임 `.didWake` 는 **본문이 끝난 여기**서 넣는다(M7) — 팀 상태 반영·되맞춤 뒤라야
                // 잠자기 정정으로 방금 닫힌 세션에 대고 조인했다가 곧바로 끊는 헛왕복이 없고, 본문의 마지막 요청 뒤라야
                // "폴링 본문 1회 → 조인 1회"가 순서 그대로다. 게이트가 없던 반복에선 no-op.
                self?.flushWakeRejoinIfPending()
            }
        }
    }

    /// 티커 1회분. 루프와 분리해 테스트가 벽시계 없이 직접 부른다(시각은 주입 clock 이 정한다).
    func tick() {
        let now = clock()
        // ★ 시계 3종 분리(M1). 팝오버 시계는 **열려 있을 때만**, 오버레이 시계는 **패널이 보일 때만** 대입한다 —
        //   @Observable 은 대입 자체가 관찰자를 깨우므로, 보이지 않는 표면의 시계를 건드리는 것이 곧 그 표면의
        //   매초 재평가다(닫힌 팝오버의 CheckMenuView 트리는 상주한다). 아래 정책·라벨은 전부 `now`(clock) 로 판정한다.
        if isMenuPresented { displayNow = now }
        if overlayClockIsShowing { overlayNow = now }
        // 감속 장부: 표시 없는 상태의 시작 시각(nextTickDelay 가 1시간 경과를 이 값으로 잰다).
        if !isMenuPresented, !overlayClockIsShowing {
            if displayIdleSince == nil { displayIdleSince = now }
        } else if displayIdleSince != nil {
            displayIdleSince = nil
        }
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
            // away 를 **먼저** 본다: 더 이른 시각으로 마감하고(사람이 마지막으로 있었던 시각) 복원 가능한
            // 사유를 남기기 때문이다. 순서를 뒤집으면 12시간 미확인 마감이 먼저 발화해 같은 부재가
            // long_session 으로 기록되고, 그 사유는 복원 대상이 아니라 그 시간이 영구 소실된다.
            evaluateAwaySession(now: now)
            evaluateLongSession(now: now)
            evaluateTimeMilestones(now: now)
            refreshMenuBarTitle(now: now)
        }
    }

    /// 메뉴바 라벨 문자열을 현재 상태에서 다시 계산해, 문자열이 실제로 바뀔 때만 대입한다.
    /// (@Observable 은 동일 값 대입도 관찰자를 발화시키므로 != 가드가 무효화 최소화의 핵심이다.)
    /// **팝오버 시계(displayNow)를 읽지 않는다** — 닫힌 팝오버에서 그 시계는 얼어 있고, 이 라벨은 닫혀 있어도 매초
    /// 살아야 한다(M1). now 가 Optional 인 이유는 refreshTimedBanner 와 같다(기본 인자가 self.clock 을 못 읽는다).
    func refreshMenuBarTitle(now: Date? = nil) {
        var derived = snapshot
        if derived.isWorking {
            derived.elapsedSeconds = todayDuration(at: now ?? clock())
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
        // 인자 시각 기준이다(팝오버 시계가 아니라) — 닫힌 팝오버에서도 1h/3h/4h 가 제시각에 발화해야 한다(M1).
        let today = todayDuration(at: now)
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
        // ★ 3시간 = 미션 1호의 목표다. 이 분기가 **이번 릴리스에 새로 생기는 발화 지점**이고,
        //   이게 없으면 근무만 하고 패널을 한 번도 안 연 사용자는 그날 sync 가 0회라 코인이 영구 소실된다.
        //   축하(onReactionTrigger)를 쏘지 않는 이유: 여기서는 아직 **받았는지 모른다**. 판정은 서버다.
        //   상한에 걸렸을 수도, 이미 받았을 수도 있으므로 연출은 서버가 granted_now 를 준 뒤에만 나간다.
        //   마일스톤 키를 쓰는 것은 **랩당 1회** 스로틀 목적이다(멱등한 RPC 라 두 번 불려도 해는 없지만
        //   무료 플랜에서 15초마다 왕복을 내지 않기 위해).
        //   ★ 미션이 "그날 3시간 1회"에서 "3시간마다 반복 지급(랩)"으로 바뀌었으므로 스로틀 키도
        //     랩 번호를 탄다. 하루 1회 키로는 첫 랩만 즉시 발화하고 랩 2·3·4는 근무 중 5분 주기 sync 가
        //     올 때까지 밀린다 — 받은 순간과 알려 주는 순간이 최대 5분 어긋난다.
        //   missionWorkSeconds 가 0 이하이면 랩을 0으로 접는다. 이 값은 서버가 준 target 에서 오므로
        //   0/음수가 올 여지가 있고, 그대로 나누면 0 나눗셈으로 앱이 죽는다.
        let lap = missionWorkSeconds > 0 ? today / missionWorkSeconds : 0
        if lap >= 1,
           milestoneTracker.fireIfNeeded(MilestoneTracker.ultraLapKey(lap), now: now) {
            syncUltraWallet(reason: .missionCandidate)
        }
    }
}

/// 울트라 패널에 **어디서 들어왔는가**. [뒤로]가 돌아갈 곳을 정하는 유일한 근거다.
/// 홈(메인 목록)에서 들어오면 홈으로, 콕찌르기 제목 행의 잔량 배지에서 들어오면 콕찌르기로 돌아간다.
enum UltraPanelOrigin: Equatable, Sendable {
    case home
    case poke
}

extension MilestoneTracker {
    /// 오늘 누적 **3시간** = 미션 1호의 목표. 기존 키(hour1/hour4/teamGoal/firstArrival)에는 이 자리가 없었다 —
    /// 이 키가 곧 blocker(서버 #3)이 지적한 "존재하지 않는 클라 호출 지점"이다.
    ///
    /// **여기서 축하가 터지지 않는다.** 이 키는 랩당 1회 스로틀일 뿐이고, 실제로 받았는지는 서버가 답한다.
    /// (MilestoneTracker 본체는 agent-reactions 소유라 확장으로만 더한다 — 파일 경계를 넘지 않기 위해서다.)
    static let hourThreeKey = "hour3"

    /// 랩 n(누적 3시간·6시간·9시간…)의 스로틀 키.
    ///
    /// **랩 1은 기존 `hourThreeKey`("hour3") 를 그대로 쓴다.** 새 키로 갈아 끼우면 오늘 이미 3시간
    /// 지점에서 발화한 사용자가 같은 랩을 한 번 더 발화한다 — 멱등한 RPC 라 결과는 무해하지만
    /// 무료 플랜에서 불필요한 왕복이고, 무엇보다 마일스톤 장부의 연속성이 끊긴다(어제까지 "hour3" 로
    /// 남은 기록과 오늘부터의 기록이 다른 키가 되어 같은 사건을 두 이름으로 세게 된다).
    static func ultraLapKey(_ lap: Int) -> String {
        lap <= 1 ? hourThreeKey : "hour3.lap\(lap)"
    }
}

extension WorkTimerStore {
    static let emailKey = "check.userEmail"
    static let displayNameKey = "check.displayName"
    static let overlayEnabledKey = "check.overlayEnabled"
    /// 할 일 기능 사용 여부. 켜면 캐릭터 클릭이 보드를 여닫고, 끄면 예전처럼 아파하기가 나온다.
    static let todoEnabledKey = "check.todoEnabled"
    /// 수동 [근무 종료]의 자동 시작 억제 표식(Bool). 1시간 부재 재무장 판정과 함께 쓴다.
    static let autoStartSuppressedKey = "check.nudge.autoStartSuppressed"
    /// 억제 중 스케줄러의 마지막 생존 스탬프(Date). 실행 간 공백(앱이 죽어 있던 시간)을 재는 유일한 근거.
    static let nudgeLastAliveAtKey = "check.nudge.lastAliveAt"
    /// 미반영 근무 큐(pendingItems)의 영속 키(JSON). 오프라인 중 앱 종료/크래시가 미반영 근무를 지우지
    /// 않게 하는 장부다 — didSet 이 쓰고 init 이 복원한다.
    static let pendingWorkQueueKey = "check.workQueue.pending"

    /// pendingItems 의 didSet 전용 영속. 빈 큐는 키 자체를 지운다 — "드레인 완료"가 디스크에도 그대로
    /// 보이게 하고, 낡은 JSON 이 다음 실행에 유령 항목으로 되살아날 여지를 없앤다.
    func persistPendingWorkQueue() {
        guard !pendingItems.isEmpty else {
            defaults.removeObject(forKey: Self.pendingWorkQueueKey)
            return
        }
        guard let data = try? JSONEncoder().encode(pendingItems) else { return }
        defaults.set(data, forKey: Self.pendingWorkQueueKey)
    }

    /// 이전 실행이 남긴 미반영 근무 큐. 깨진 데이터는 빈 큐로 접는다 — 복원 실패로 앱이 죽으면
    /// 그 크래시가 큐보다 더 큰 것을 잃게 한다(다음 didSet 영속이 깨진 원본도 자연히 갈아 끼운다).
    static func restoredPendingWorkQueue(from defaults: UserDefaults) -> [PendingWorkItem] {
        guard let data = defaults.data(forKey: pendingWorkQueueKey) else { return [] }
        return (try? JSONDecoder().decode([PendingWorkItem].self, from: data)) ?? []
    }

    /// 캐릭터 오버레이 표시 여부를 지정하고 설정을 저장한다.
    func setOverlayEnabled(_ enabled: Bool) {
        isOverlayEnabled = enabled
        defaults.set(enabled, forKey: Self.overlayEnabledKey)
        // 켜는 순간 오버레이 시계를 지금으로 맞추고(첫 그림이 낡은 시계로 그려지지 않게), 감속 중이던 티커를 되돌린다(M1).
        if enabled {
            if startedAt != nil { overlayNow = clock() }
            restoreTickerCadenceIfSlowed()
        }
    }

    /// 캐릭터 오버레이 표시를 토글하고 설정을 저장한다.
    func toggleOverlayEnabled() {
        setOverlayEnabled(!isOverlayEnabled)
    }

    /// 할 일 기능을 켜고 끈다(영속). 끄면 캐릭터 클릭이 예전처럼 아파하기로 돌아간다.
    func setTodoEnabled(_ enabled: Bool) {
        if isTodoEnabled != enabled { isTodoEnabled = enabled }
        defaults.set(enabled, forKey: Self.todoEnabledKey)
    }

    // toggleTodoEnabled() 는 v0.2.32 에 지웠다. 유일한 호출자이던 팝오버의 TodoToggleControl 이
    // 설정 창으로 이사하면서, 설정 토글은 원하는 값을 아는 상태에서 setTodoEnabled(_:) 를 직접 부른다.
    // 뒤집기 헬퍼가 남아 있으면 "지금 값을 읽고 뒤집는" 경로가 되살아나 바인딩과 경합할 수 있다.

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

    /// 금고 미주입 시의 기본 금고. **분기는 여기 한 곳뿐이다.**
    /// - 프로덕션: KeychainTokenVault — 토큰이 디스크 평문(kingcheck.plist)에서 로그인 키체인으로 옮겨진다.
    /// - 테스트 프로세스: UserDefaultsTokenVault — 서명 안 된 테스트 러너가 실제 키체인을 오염시키지 않고,
    ///   defaults 에 토큰을 시딩/단언하는 기존 스위트의 계약이 바이트 단위로 보존된다(TokenVault.swift 주석).
    /// 판정은 CheckPanelVisibility.isRunningTests 재사용이다 — 그 주석이 "판정은 여기 한 곳뿐"이라 못 박았고
    /// (dyld 의 .xctest 번들 실측, 프로덕션 상시 false), RealtimeTransport 도 같은 이유로 재사용했다.
    static func defaultTokenVault(defaults: UserDefaults) -> TokenVault {
        CheckPanelVisibility.isRunningTests
            ? UserDefaultsTokenVault(defaults: defaults)
            : KeychainTokenVault()
    }

    static func restoredSession(from defaults: UserDefaults, vault: TokenVault) -> SupabaseSession? {
        migrateLegacyTokens(from: defaults, into: vault)
        // 금고 우선, defaults 는 최후 폴백이다. 폴백이 실제로 잡히는 경우는 키체인 write 가 고장 난 맥
        // (위 이행이 옮기지 못해 defaults 사본을 남긴 경우)뿐이다 — 그 맥에서 폴백이 없으면 brew 업그레이드
        // 직후 첫 실행이 곧바로 로그아웃 화면이 된다. 정상 맥은 이행이 defaults 를 비우므로 폴백이 죽어 있다.
        guard let accessToken = vault.read(accessTokenKey) ?? defaults.string(forKey: accessTokenKey),
              let userID = defaults.string(forKey: userIDKey)
        else {
            return nil
        }
        return SupabaseSession(
            accessToken: accessToken,
            refreshToken: vault.read(refreshTokenKey) ?? defaults.string(forKey: refreshTokenKey),
            userID: userID
        )
    }

    /// v0.2.36 이하가 defaults 평문에 남긴 토큰의 1회 자동 이행: 금고에 없고 defaults 에 있으면 금고로
    /// 옮기고 defaults 에서 지운다. **brew 업그레이드 사용자 38명의 로그인 유지가 이 경로 하나에 달렸다** —
    /// 없으면 업그레이드 첫 실행이 전원 로그아웃이다.
    ///
    /// 삭제는 **써진 것을 읽어 확인한 뒤에만** 한다. 금고 계약(write 실패 ⇒ read nil)상 읽어서 같으면
    /// 정말 저장된 것이다. 키체인이 고장 난 맥에서 확인 없이 지우면 마지막 남은 토큰 사본을 태우는 셈이라,
    /// 그 맥은 실패 시 defaults 사본을 남겨 다음 실행이 재시도한다(위 restoredSession 폴백의 짝).
    /// 키별 독립 이행인 이유: refresh 없는 세션(access 만)도 합법이라(persistSession) 묶어 처리하면
    /// 한쪽 부재가 다른 쪽 이행까지 막는다.
    static func migrateLegacyTokens(from defaults: UserDefaults, into vault: TokenVault) {
        for key in [accessTokenKey, refreshTokenKey] {
            guard vault.read(key) == nil, let legacy = defaults.string(forKey: key) else { continue }
            vault.write(legacy, key: key)
            if vault.read(key) == legacy {
                defaults.removeObject(forKey: key)
            }
        }
    }

    func persistSession(_ session: SupabaseSession, email: String? = nil, displayName: String? = nil) {
        // 비밀값(access/refresh)은 금고로만, 비밀 아닌 값(userID/email/별명)은 defaults 로 — 이 함수가
        // 그 경계선이다. 여기서 defaults.set(토큰) 을 한 줄이라도 되살리면 평문 유출(P0)이 그대로 재발한다.
        tokenVault.write(session.accessToken, key: Self.accessTokenKey)
        defaults.set(session.userID, forKey: Self.userIDKey)
        if let refreshToken = session.refreshToken {
            tokenVault.write(refreshToken, key: Self.refreshTokenKey)
        } else {
            // 옛 defaults 경로의 removeObject 와 같은 규약: refresh 없는 세션을 저장하면 앞 세션의
            // refresh 가 지워져야 한다 — 남기면 다음 실행이 남의(앞 세션의) 회전 토큰으로 grant 를 친다.
            tokenVault.delete(Self.refreshTokenKey)
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
        // 금고와 defaults **둘 다** 지운다. defaults 쪽 토큰 키는 평상시엔 이행이 이미 비워 빈 삭제지만,
        // 키체인 고장 맥이 남긴 평문 사본(migrateLegacyTokens 의 보존 분기)이 로그아웃 후에도 살아남으면
        // 이 수정이 막으려던 유출이 '로그아웃했는데도' 계속되는 셈이라 반드시 함께 지운다.
        [Self.accessTokenKey, Self.refreshTokenKey].forEach(tokenVault.delete)
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
        lastUploadedAccountKey = nil
        // 일별 업로드 장부도 계정에 묶인다(user_id 행) — 남기면 다음 계정의 첫 업로드가 "이미 올린 날"로 읽혀 그 날들이 통째로 빠진다.
        lastUploadedDaily = [:]
        lastTokenUploadAt = .distantPast
        // 하트비트 도장도 계정에 묶인 사실이다(user_id 로 들어간다). 남기면 새 계정의 첫 스캔이 앞 계정의
        // 스캔 시각과 같아 보여 보고가 한 주기 밀린다. 배경 스캔 주기 스탬프는 **일부러 남긴다** —
        // 그건 계정이 아니라 이 맥의 순회 비용을 재는 값이라, 로그아웃/재로그인이 전량 순회를 다시 열 이유가 없다.
        lastTokenScanHeartbeatAt = nil
        // 콕찌르기/공개 설정 상태도 함께 비운다(리그·토큰 보드와 동일 규약).
        pokeDirectory = []
        isPokePanelVisible = false
        pokeDirectoryLoaded = false
        pokeCooldownUntil = [:]
        pokeNotice = nil
        // 메시지도 계정에 묶인 상태다. 큐를 남기면 새 계정 화면에 앞 사람에게 온 말이 뜨고,
        // 쿨타임을 남기면 새 계정이 자기 첫 메시지를 못 보낸다(찔림과 같은 규약).
        receivedMessages = []
        lastShownMessage = nil
        messageNotice = nil
        messageCooldownUntil = [:]
        isSendingMessage = false
        // 버전 보고 도장도 계정에 묶인다. 남기면 다음 계정이 자기 프로필에 버전을 못 남겨,
        // 그 사람은 근무 중인데도 아무에게서 메시지를 못 받는다(서버가 app_build 를 null 로 본다).
        reportedAppVersionStamp = nil
        tokenUsagePublic = true
        tokenUsagePublicLoaded = false
        // 수집 설정 수신 플래그도 계정에 묶인다 — 남기면 다음 계정은 서버 설정을 받기 전에 프로브(외부 프로세스)가 뜬다.
        tokenUsageCollectLoaded = false
        // 계정이 바뀌면 남의 재화를 물려받지 않게 반드시 비운다. 이 블록이 없으면 로그아웃 후 재로그인 시
        // **남의 잔량 화면이 그대로 떠 있고**, 거기서 [뒤로]를 누르면 ultraPanelOrigin 이 .poke 로 남아
        // 앞 계정 맥락의 콕찌르기가 열린다(blocker UI-1 이 지적한 그 경로다).
        isUltraPanelVisible = false
        ultraPanelOrigin = .home
        ultraBalance = nil
        ultraBalanceCap = nil
        // 남의 무제한을 물려받으면 새 계정 화면이 잔량 대신 ∞ 를 그린다(위 블록이 막으려던 그것).
        ultraUnlimited = false
        ultraBalanceFailed = false
        missions = []
        missionsLoaded = false
        missionNotice = nil
        streakDays = 0
        streakIncludesToday = false
        lastUltraWalletSyncAt = nil
        // 갱신 조정자도 계정에 묶인다. 진행 중이던 갱신 결과가 새 세션에 적용되면 남의 토큰으로 근무를 기록한다.
        sessionRefreshCoordinator.invalidate()
        // 리얼타임 링도 함께 내린다. realtimeApply 가 소켓을 끊고 예약 타이머를 취소하며 realtimeState 를
        // 쓴다 — 여기서 realtimeState 를 직접 대입하면 링과 화면이 갈리고, 갈린 순간 폴링 억제가 거짓말한다.
        realtimeApply(.signedOut)
        realtime.cancelTimers()
        realtimeCatchUpFailedAt = nil
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
        dailyGrid = .empty
        // 토큰 잔디도 계정의 것이다(서버 일별 행 + 이 계정으로 올린 로컬 맵) — 다음 계정에 물려주지 않는다.
        tokenDailyGrid = .empty
        showsRetroBanner = false
        // 미반영 근무 큐(pendingItems)와 진행 중 근무(startedAt/accumulatedSeconds)는 여기서 비우지 않는다.
        // 이 함수는 토큰 만료 강제 로그아웃(refresh token 부재/무효, 저장 세션 재활성 실패)에서도 불리는데,
        // 여기서 비우면 didSet 영속(v0.2.36, check.workQueue.pending)까지 함께 지워져
        // 오프라인에서 쌓인 근무가 영구 소실된다.
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
        // 잠자기 마감 정정 마커도 계정에 묶인 관측이다. 남기면 앞 계정 세션의 sleep 정정이 새 계정의
        // 폴링 수용 지점에서 소비를 시도하게 된다(세션 UUID 가 달라 실해는 없지만 관측 자체가 남의 것이다).
        clearPendingSleepClose()
        // 자리 비움 상태도 계정에 묶인 값이다(복원 대상 세션 ID·서버 정책·입력 관측).
        clearAwayState()
        snapshot = WorkStatusSnapshot(status: .offWork, elapsedSeconds: 0)
        tickerTask?.cancel()
        tickerTask = nil
        refreshTimedBanner()
        refreshMenuBarTitle()
    }
}

// MARK: - 깨움 결합 게이트 (v0.2.38 M7)

extension WorkTimerStore {
    /// 프로덕션의 네트워크 경로 관측자. 테스트 프로세스에서는 **nil** 이다(defaultTokenVault·LiveRealtimeTransport 와
    /// 같은 판정) — 게이트가 없으면 handleWake 는 예전 순서(즉시 재연결)로 돌고, 게이트 동작은 관측자를 주입한
    /// V0238ClockTests 가 결정적으로 검증한다.
    static func defaultNetworkPath() -> NetworkPathObserving? {
        CheckPanelVisibility.isRunningTests ? nil : LiveNetworkPathObserver()
    }

    /// handleWake 가 세운다. 게이트가 서 있는 동안 **어떤 루프도 서버를 두드리지 않는다**: 만료된 Task.sleep 이 곧바로
    /// 본문을 쏘지 못하게 refresh 루프와 찔림 폴링을 내려 두고, 결합(또는 상한)이 오면 refresh 루프를 **본문 먼저**로
    /// 다시 세운다(단일 tick). 그 본문의 되맞춤 자리에서 리얼타임 `.didWake` 가 나간다(flushWakeRejoinIfPending).
    /// sync 큐(enqueueSync)도 게이트를 기다리므로 잠자기 정정 PATCH 역시 결합 뒤에 나간다.
    func beginWakeGate() {
        // 앞선 게이트가 아직 열리지 않았다면(연속 깨움·다크웨이크) 그것을 버리고 새로 센다 — 두 게이트가 각자
        // 루프를 재시작하면 본문이 두 번 돈다. 붙잡아 둔 루프 표식은 그대로 남아 새 게이트가 되살린다.
        wakeGateTask?.cancel()
        if refreshTask != nil {
            refreshTask?.cancel()
            refreshTask = nil
            refreshLoopHeldByWakeGate = true
        }
        if pokePollTask != nil {
            pokePollTask?.cancel()
            pokePollTask = nil
            pokePollHeldByWakeGate = true
        }
        wakeGateTask = Task { @MainActor [weak self] in
            guard let self else { return }
            // 결합 확인 또는 상한 초과 — 어느 쪽이든 진행한다(영구 대기 금지).
            _ = await self.awaitWakeNetwork()
            guard !Task.isCancelled else { return }
            self.wakeGateTask = nil
            self.releaseWakeGate()
        }
    }

    /// 관측자의 결합 대기와 상한 타이머를 경주시킨다. true = 결합 확인, false = 상한 초과. 관측자가 없으면 즉시 true.
    /// 진 쪽은 취소한다 — 관측자 구현은 취소에 응답해야 한다(LiveNetworkPathObserver 는 onCancel 에서 걸쇠를 푼다).
    func awaitWakeNetwork() async -> Bool {
        guard let networkPath else { return true }
        let timeout = wakeGateTimeoutSeconds
        let sleep = wakeGateSleep
        return await withTaskGroup(of: Bool.self) { group in
            group.addTask { await networkPath.waitUntilSatisfied(); return true }
            group.addTask { await sleep(timeout); return false }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
    }

    /// 게이트가 열렸다. 내려 둔 루프를 되살리고, 미뤄 둔 재연결을 본문 뒤에 배치한다.
    func releaseWakeGate() {
        let resumeRefresh = refreshLoopHeldByWakeGate
        let resumePoke = pokePollHeldByWakeGate
        refreshLoopHeldByWakeGate = false
        pokePollHeldByWakeGate = false
        guard session != nil else {
            // 게이트 도중 로그아웃 — 루프를 되살리지 않는다(다음 로그인이 새로 세운다). 링도 로그아웃 상태라 no-op.
            wakeRejoinPending = false
            realtimeApply(.didWake, at: clock())
            return
        }
        if resumePoke { startPokePolling() }
        if resumeRefresh {
            // 폴링 본문 1회 → 조인 순서: 본문의 되맞춤 자리에서 flushWakeRejoinIfPending 이 `.didWake` 를 넣는다.
            wakeRejoinPending = true
            startRefreshLoopTask(runBodyFirst: true)
        } else {
            // 루프가 없던 프로세스(로그인 직후 루프 시작 전 등) — 본문이 없으니 바로 재연결한다.
            realtimeApply(.didWake, at: clock())
        }
    }

    /// 서 있는 게이트가 열릴 때까지 기다린다(없으면 즉시). 네트워크로 나가는 큐(enqueueSync)가 부른다.
    func awaitWakeGate() async {
        guard let gate = wakeGateTask else { return }
        await gate.value
    }

    /// 게이트가 미뤄 둔 리얼타임 `.didWake` 를 넣는다(refresh 루프 본문의 되맞춤 직후에서 1회). 남은 것이 없으면 no-op.
    func flushWakeRejoinIfPending() {
        guard wakeRejoinPending else { return }
        wakeRejoinPending = false
        realtimeApply(.didWake, at: clock())
    }
}

/// 네트워크 경로 관측자(주입점). 프로덕션은 NWPathMonitor(LiveNetworkPathObserver), 테스트는 스크립트.
protocol NetworkPathObserving: Sendable {
    /// 경로가 satisfied 가 될 때까지 기다린다. 이미 satisfied 면 즉시 돌아온다. **상한은 호출자(스토어)가 건다** —
    /// 구현이 무엇이든 영구 대기가 될 수 없게. 취소되면 satisfied 와 무관하게 돌아와야 한다(상한이 이겼을 때).
    func waitUntilSatisfied() async
}

/// 프로덕션 네트워크 경로 관측자. **호출마다 새 NWPathMonitor** 를 띄워 첫 보고를 진실로 삼는다 — 잠들기 전에 받아 둔
/// satisfied 를 믿지 않기 위해서다(깨움 직후 오래 산 모니터의 currentPath 는 잠들기 전 값을 들고 있을 수 있고, 그 값으로
/// 즉시 진행하면 게이트가 있으나 마나다). 첫 보고는 보통 수 ms 안에 오므로 이미 결합돼 있을 때의 비용은 사실상 0이다.
final class LiveNetworkPathObserver: NetworkPathObserving {
    private let queue = DispatchQueue(label: "check.network-path", qos: .utility)

    func waitUntilSatisfied() async {
        let monitor = NWPathMonitor()
        let latch = ResumeLatch()
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                latch.arm(continuation)
                monitor.pathUpdateHandler = { path in
                    guard path.status == .satisfied else { return }
                    latch.fire()
                }
                monitor.start(queue: queue)
            }
            monitor.cancel()
        } onCancel: {
            // 상한이 이겼다(스토어의 task group 이 취소). 매달린 continuation 을 풀어 자식 Task 가 끝나게 한다 —
            // 안 풀면 group 이 자식을 기다리느라 게이트가 영영 안 열린다(영구 대기 금지의 실체).
            latch.fire()
        }
    }
}

/// continuation 을 **정확히 한 번** 재개하는 걸쇠. 재개 요청이 arm 보다 먼저 와도(이미 취소된 Task) 잃지 않는다.
private final class ResumeLatch: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    private var fired = false

    func arm(_ continuation: CheckedContinuation<Void, Never>) {
        lock.lock()
        if fired {
            lock.unlock()
            continuation.resume()
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    func fire() {
        lock.lock()
        guard !fired else {
            lock.unlock()
            return
        }
        fired = true
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume()
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
/// Codable 인 이유: 큐는 defaults 에 영속한다(pendingWorkQueueKey) — 오프라인 중 앱 종료/크래시 생존.
struct PendingWorkItem: Equatable, Codable {
    let id: UUID
    let operation: PendingWorkOperation
    let sessionID: String
    let sessionStartedAt: Date?
    let endedAt: Date?
    /// 이 항목을 만든 계정의 userID. 강제 로그아웃은 큐를 남기므로(오프라인 근무 보존), 다음 로그인 때
    /// 소유자가 다른 항목만 골라 버리는 데 쓴다(앞 계정 근무가 새 계정 이름으로 기록되는 오염 금지).
    let ownerUserID: String?
    /// 자동 마감이면 그 사유(서버 어휘). 사용자가 누른 종료는 nil 이고, 그때 서버로 나가는 요청은
    /// v0.2.34 와 바이트가 같다. 큐에 실어 나르는 이유는 오프라인 재생 때문이다 — 재생 시점에는
    /// 스토어의 근무 상태가 이미 다음 세션으로 넘어가 있어 사유를 되살릴 방법이 없다.
    let autoCloseReason: AutoCloseReason?

    init(
        id: UUID,
        operation: PendingWorkOperation,
        sessionID: String,
        sessionStartedAt: Date?,
        endedAt: Date?,
        ownerUserID: String? = nil,
        autoCloseReason: AutoCloseReason? = nil
    ) {
        self.id = id
        self.operation = operation
        self.sessionID = sessionID
        self.sessionStartedAt = sessionStartedAt
        self.endedAt = endedAt
        self.ownerUserID = ownerUserID
        self.autoCloseReason = autoCloseReason
    }
}

/// 근무 중 잠자기에 들어간 순간의 관측 스냅샷(v0.2.36). willSleep 에서 영속하고, 서버가 그 세션을
/// abandoned 로 먼저 마감해 둔 것을 발견한 쪽(깨어남 순서 불문 — 폴링 수용 지점·다음 실행)이
/// 이 값으로 sleep 정정을 큐에 실은 뒤 지운다. 세션이 정상 경로로 닫히면 그 자리에서 지운다.
struct PendingSleepClose: Codable, Equatable {
    let sessionID: String
    let sessionStartedAt: Date
    let sleepBeganAt: Date
    let lastInputAt: Date?
}
