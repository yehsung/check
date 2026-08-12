import Foundation

/// 팀원 표시 3상태. 진실은 서버 원장(하트비트 last_seen_at)이고 초침은 클라 파생 표시다.
/// - activeWorking: 마지막 생존신호가 신선함(≤90초). 라이브로 틱.
/// - staleWorking: 신호가 끊김(>90초). 마지막 신호 시각으로 동결된 카운트(프론트 "연결 끊김").
/// - offWork: 근무종료.
enum MemberPresence: Equatable {
    case activeWorking
    case staleWorking(frozenDurationSeconds: Int)
    case offWork
}

/// 한 대의 맥이 남긴 '이 세션은 지금 내가 쓰고 있다'는 주장(work_status_devices 한 행).
///
/// 왜 work_statuses 의 셀이 아니라 기기별 행인가: 앱은 폴링마다 하트비트를 **먼저** 쓰고 그 다음 읽으므로
/// 공유 셀에서 읽히는 값은 언제나 방금 내가 쓴 내 값이다(실측 seen−mine ≈ -0.9초). 그 셀에 기기를 넣어도
/// "기기 == 나"가 항상 참이라 정보량이 0 이다. 기기마다 자기 행을 가지면 내 upsert 가 남의 행을 건드릴 수
/// 없어 증거가 지워지지 않는다 — 이것이 소유권을 시각 비교(추측)가 아닌 사실로 판정하는 유일한 축이다.
struct StatusDeviceClaim: Equatable {
    /// 주장한 맥의 식별자(UserDefaults 'check.deviceID'). 내 값과 같으면 이 행은 내가 쓴 것이다.
    let deviceID: String
    /// 그 맥이 소유를 주장하는 세션 ID. 이게 없으면 '다른 맥이 살아 있다'와 '다른 맥이 **내 세션에**
    /// 살아 있다'를 못 가려, 정상적인 맥 간 인수인계에서 방금 연 내 세션을 남의 것으로 오인한다.
    let sessionID: String?
    /// 그 맥이 **자기 시계로** 찍은 마지막 신호. 신선도(절대값)가 아니라 폴링 간 전진 여부로만 쓴다 —
    /// 두 맥의 시계 어긋남이 판정에 들어오지 않게 하기 위함이다.
    let lastSeenAt: Date?
    /// 그 맥이 이 세션을 **직접 열었는가**(강한 소유). true = start()/되돌리기 재개가 서버 왕복으로 확정한
    /// 사실, false = 백스톱이 세운 추측. 반납 규칙의 유일한 결정자가 device_id 사전식 비교이던 시절,
    /// device_id 는 랜덤 UUID 라 **정확히 절반의 배치에서 진짜 소유자가 물러났다**(= 살아 있는 세션이 마감되고
    /// 그 뒤 근무가 통째로 유실). 기본값 false 는 판정 방향과 같다 — **모르면 약하다**(컬럼 없는 서버,
    /// 이 필드를 안 싣는 옛 행, 파싱 실패가 전부 '추측'으로 떨어져야 진짜 소유자를 밀어내지 않는다).
    /// 새 필드는 반드시 마지막에 둔다(위치 인자로 만드는 호출부가 그대로 컴파일되게).
    var openedSession: Bool = false
}

struct TeamMemberStatus: Equatable, Identifiable {
    let id: String
    var name: String
    var status: WorkStatus
    var updatedAt: Date?
    var currentSessionStartedAt: Date?
    var weeklyDurationSeconds: Int = 0
    var todayDurationSeconds: Int = 0
    var avatarURL: URL? = nil
    var lastSeenAt: Date? = nil
    var activeSessionID: String? = nil
    /// 이 사람의 계정으로 지금 소유를 주장하고 있는 맥들(work_status_devices). 서버에 표가 없거나
    /// 구버전 맥만 쓰고 있으면 빈 배열이다 — **빈 배열은 '다른 맥 없음'이 아니라 '판정 불가'다**
    /// (그 경우 소유권 판정은 기존 백스톱 7분으로 되돌아간다). 새 필드는 반드시 마지막에 둔다:
    /// 위치 인자로 이 타입을 만드는 테스트/호출부가 그대로 컴파일되게 하기 위함이다.
    var deviceClaims: [StatusDeviceClaim] = []

    /// 생존신호가 끊겼다고 보는 임계(초). 하트비트 주기(30초)의 3배라 한두 번 실패해도 오판하지 않는다.
    /// 상수로 뽑아 둔 이유: 흡수 세션 소유권 되찾기(WorkTimerStore.updateAdoptedPresenceTracking)가 같은
    /// 기준으로 판정해야 하기 때문이다. 두 곳이 서로 다른 숫자를 들면 화면은 '연결 끊김'인데 소유권은
    /// 아무도 되찾지 않는(또는 그 반대의) 상태가 생긴다.
    static let stalePresenceSeconds: TimeInterval = 90

    /// 서버 하트비트를 기준으로 팀원의 생존 상태를 판정한다.
    /// seen = lastSeenAt ?? updatedAt. seen이 없으면(신호 미상) 살아있다고 본다.
    func presence(now: Date = Date()) -> MemberPresence {
        guard status == .working else {
            return .offWork
        }
        guard let seen = lastSeenAt ?? updatedAt else {
            return .activeWorking
        }
        guard now.timeIntervalSince(seen) > Self.stalePresenceSeconds else {
            return .activeWorking
        }
        let frozen = max(0, Int(seen.timeIntervalSince(currentSessionStartedAt ?? seen)))
        return .staleWorking(frozenDurationSeconds: frozen)
    }

    func currentDurationSeconds(now: Date = Date()) -> Int {
        guard status == .working, let currentSessionStartedAt else {
            return 0
        }
        // 생존신호가 끊긴(stale) 세션은 now가 아니라 마지막 신호 시각으로 클램프해 죽은 세션이
        // 카운트를 부풀리지 않게 한다. 본인은 하트비트로 신호가 신선해 자연히 클램프 대상이 아니다.
        if case .staleWorking(let frozen) = presence(now: now) {
            return frozen
        }
        return max(0, Int(now.timeIntervalSince(currentSessionStartedAt)))
    }

    func liveWeeklyDurationSeconds(now: Date = Date()) -> Int {
        weeklyDurationSeconds + currentWeeklyContributionSeconds(now: now)
    }

    func liveTodayDurationSeconds(now: Date = Date()) -> Int {
        todayDurationSeconds + currentDurationSeconds(now: now)
    }

    /// 진행 세션의 이번 주 기여(초). 주 시작(KST 월요일 00:00) 이전 구간은 이번 주에 귀속하지 않는다
    /// — 월요일 경계에서 지난 주 근무가 새 주로 새던 버그 수정(서버 clippedContribution 과 동일 규약).
    /// stale 세션은 now 가 아니라 마지막 신호 시각으로 클램프해 죽은 세션이 카운트를 부풀리지 않는다.
    private func currentWeeklyContributionSeconds(now: Date) -> Int {
        guard status == .working, let started = currentSessionStartedAt else {
            return 0
        }
        let clippedStart = max(started, TeamWeeklyGoal.koreanWeekStart(for: now))
        let end: Date
        if case .staleWorking = presence(now: now) {
            end = lastSeenAt ?? updatedAt ?? started
        } else {
            end = now
        }
        return max(0, Int(end.timeIntervalSince(clippedStart)))
    }

    /// 1인당 주간 목표(goalSeconds) 달성 여부. 팀 카드 멤버 행의 ✓ 노출 조건과 동일 식이다.
    /// weekly_goal_hours 는 팀 총합이 아니라 "각자 이번 주 X시간 이상" 이라, 이 사람의 라이브 주간
    /// 누적이 목표 이상이면 참이다. 목표가 0(비정상)이면 항상 거짓으로 둔다.
    func hasMetWeeklyGoal(goalSeconds: Int, now: Date = Date()) -> Bool {
        goalSeconds > 0 && liveWeeklyDurationSeconds(now: now) >= goalSeconds
    }
}

enum PendingWorkOperation: Equatable {
    case start
    case stop(durationSeconds: Int)
}

/// 팀 코드 미리보기 결과. lookup_team_by_code(code) RPC 로 받아 온다(가입 전에도 anon 으로 호출 가능).
/// invite_code 는 담지 않는다(코드는 입력자가 이미 알고 있으므로 되돌려줄 이유가 없다).
struct TeamJoinPreview: Equatable {
    let teamID: String
    let name: String
    let weeklyGoalHours: Int
    let memberCount: Int
}

/// (레거시 호환) 가입 화면 팀 선택 항목. 초대코드 흐름 전의 뷰/렌더 테스트가 아직 참조하므로 형만 유지한다.
/// 새 가입 흐름은 팀 목록을 노출하지 않으며 이 타입을 채우지 않는다.
struct TeamDirectoryEntry: Identifiable, Equatable {
    let id: String
    let name: String
}

/// 팀 리그(이번 주 팀별 근무시간)의 한 행. team_weekly_leaderboard() RPC 로 받아 온다.
/// id 는 팀 id(내 팀 하이라이트 판정에 쓴다). invite_code 는 RPC 가 반환하지 않으므로 노출되지 않는다.
/// weeklyGoalHours 는 팀 총합 목표가 아니라 팀원 1인당 주간 목표라, 게이지/정렬 기준은 총합이 아니라
/// 평균(averageSeconds = 총합 ÷ 인원)이다.
struct TeamLeaderboardEntry: Identifiable, Equatable {
    let id: String
    let name: String
    let weeklyGoalHours: Int
    let totalSeconds: Int
    let workingCount: Int
    let memberCount: Int

    /// 팀원 1인당 평균 근무시간(초). 인원 0(가드)이면 0. 정렬·게이지·%의 단일 기준이다.
    var averageSeconds: Int {
        guard memberCount > 0 else { return 0 }
        return totalSeconds / memberCount
    }

    /// 1인당 목표 대비 진행률 게이지(주간 목표 게이지와 같은 규약: 0~1 클램프, 목표=weeklyGoalHours 시간).
    /// 분자는 총합이 아니라 평균이다(목표가 1인당이므로).
    var goal: TeamWeeklyGoal {
        TeamWeeklyGoal(workedSeconds: averageSeconds, goalSeconds: weeklyGoalHours * 3600)
    }
}

extension Array where Element == TeamLeaderboardEntry {
    /// 팀별 리그 정렬 단일 규약: 1인당 평균 근무시간 내림차순, 동률이면 팀 이름 오름차순.
    /// 스토어(반영)와 뷰(재정렬)가 같은 결과를 내도록 공유한다.
    func sortedByAverageDescending() -> [TeamLeaderboardEntry] {
        sorted { lhs, rhs in
            if lhs.averageSeconds != rhs.averageSeconds {
                return lhs.averageSeconds > rhs.averageSeconds
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    /// 리그 표시용 필터. 이번 주 총합이 0인 팀은 리그에서 숨긴다(아직 아무도 근무하지 않은 팀이 목록을
    /// 채워 어수선해지지 않게). 단, 내 팀(id==myTeamID)은 0이어도 유지한다 — 내 팀이 리그에서 사라지면
    /// "왜 우리 팀이 안 보이지?" 하는 혼란을 준다. 정렬은 기존 sortedByAverageDescending 규약 그대로다.
    /// 원본 leaderboard 는 스토어에 보존하고, 이 필터는 표시 시점에서만 적용한다.
    func filteredForDisplay(myTeamID: String?) -> [TeamLeaderboardEntry] {
        filter { $0.totalSeconds != 0 || $0.id == myTeamID }
            .sortedByAverageDescending()
    }
}

// MARK: - 팀원 이번 달 AI 토큰 보드

/// 이번 달 AI 토큰 사용량 조회월 키(KST 'YYYY-MM'). D1 의 TokenUsageMonthly.month 와 같은 Asia/Seoul 규약이라
/// 업로드한 행과 같은 월로 조회된다(월이 바뀌면 새 키 → 자연히 매달 초기화). 순수 함수라 테스트로 고정 검증한다.
enum TokenUsageMonthKey {
    static func current(_ now: Date = Date()) -> String {
        let c = TeamWeeklyGoal.kstCalendar.dateComponents([.year, .month], from: now)
        return String(format: "%04d-%02d", c.year ?? 1970, c.month ?? 1)
    }
}

/// 오늘(KST) 날짜 키 'YYYY-MM-DD'. 순위판이 서버 행의 todayDate 와 이 값을 비교해 "오늘 +N" 표시 여부를 가른다
/// (스캐너의 dayBounds date 와 같은 Asia/Seoul 규약 — 둘 다 DST 없는 +9 라 항상 일치). 순수 함수라 테스트로 고정한다.
enum TokenUsageDayKey {
    static func current(_ now: Date = Date()) -> String {
        let c = TeamWeeklyGoal.kstCalendar.dateComponents([.year, .month, .day], from: now)
        return String(format: "%04d-%02d-%02d", c.year ?? 1970, c.month ?? 1, c.day ?? 1)
    }
}

/// token_usage_board RPC 응답 행(snake_case 디코드용). 전체 공개 전환으로 행이 자체 완결이라
/// display_name/avatar_url 을 함께 담는다(더는 팀원 목록과 결합하지 않는다). month 는 RPC 인자로 고정하므로 담지 않는다.
/// display_name 은 RPC 가 coalesce(…, '사용자')로 이미 폴백하므로 non-null, avatar_url 은 nullable.
struct TokenBoardRow: Decodable, Equatable {
    let userId: String
    let displayName: String
    let avatarUrl: String?
    let claudeInput: Int
    let claudeOutput: Int
    let claudeCacheRead: Int
    let claudeCacheCreation: Int
    let codexInput: Int
    let codexOutput: Int
    let total: Int
    /// 오늘(KST) 증가량과 그 귀속 날짜 'YYYY-MM-DD'. var + 기본값이라 마이그레이션 전 옛 RPC(컬럼 누락)와 호환된다.
    var todayTotal: Int = 0
    var todayDate: String = ""
}

// TokenBoardRow 커스텀 디코드: 서버가 아직 옛 token_usage_board RPC(today_total/today_date 컬럼 없음)여도
// decodeIfPresent 로 0/"" 폴백해 마이그레이션 전 클라가 안전히 디코드한다(합성 디코더는 기본값을 무시하고 required 로 요구함).
// 키는 프로퍼티명(camelCase) — 서비스 디코더의 convertFromSnakeCase 가 today_total → todayTotal 로 맞춘다.
extension TokenBoardRow {
    enum CodingKeys: String, CodingKey {
        case userId, displayName, avatarUrl
        case claudeInput, claudeOutput, claudeCacheRead, claudeCacheCreation
        case codexInput, codexOutput, total
        case todayTotal, todayDate
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId = try c.decode(String.self, forKey: .userId)
        displayName = try c.decode(String.self, forKey: .displayName)
        avatarUrl = try c.decodeIfPresent(String.self, forKey: .avatarUrl)
        claudeInput = try c.decode(Int.self, forKey: .claudeInput)
        claudeOutput = try c.decode(Int.self, forKey: .claudeOutput)
        claudeCacheRead = try c.decode(Int.self, forKey: .claudeCacheRead)
        claudeCacheCreation = try c.decode(Int.self, forKey: .claudeCacheCreation)
        codexInput = try c.decode(Int.self, forKey: .codexInput)
        codexOutput = try c.decode(Int.self, forKey: .codexOutput)
        total = try c.decode(Int.self, forKey: .total)
        // 마이그레이션 전 호환: 옛 RPC 는 이 컬럼을 안 내려주므로 없으면 0/"".
        todayTotal = try c.decodeIfPresent(Int.self, forKey: .todayTotal) ?? 0
        todayDate = try c.decodeIfPresent(String.self, forKey: .todayDate) ?? ""
    }
}

/// 토큰 보드 한 행(표시용). 전체 공개 전환으로 숫자·이름·아바타가 모두 서버 행(RPC)에서 온다 — 행 자체가 완결이다
/// (팀원 목록과의 결합 불필요). 등수 배지 없이 정렬 순서가 곧 순위다.
struct TokenBoardEntry: Identifiable, Equatable {
    let userID: String
    var name: String
    var avatarURL: URL?
    let total: Int
    let claudeInput: Int
    let claudeOutput: Int
    let claudeCacheRead: Int
    let claudeCacheCreation: Int
    let codexInput: Int
    let codexOutput: Int
    /// 오늘(KST) 증가량과 그 귀속 날짜 'YYYY-MM-DD'. 서버 행에서 온다(마이그레이션 전엔 0/"").
    var todayTotal: Int = 0
    var todayDate: String = ""

    var id: String { userID }

    /// 표시할 오늘 증가량. todayDate 가 현재 KST 날짜(currentDate)와 같을 때만 todayTotal 을, 어제 이후로 스테일이면
    /// 0 을 돌려준다 — 어제 이후 안 연 사람도 "오늘 +0"으로 균일하게 표시되도록(행 높이/레이아웃 일관). 순수 함수라 테스트로 고정한다.
    func todayDelta(currentDate: String) -> Int {
        todayDate == currentDate ? todayTotal : 0
    }
}

extension Array where Element == TokenBoardRow {
    /// 전체 공개 RPC 행(이미 이름/아바타 포함)을 표시 엔트리로 변환한다. 결합 불필요 — 행 자체가 완결이다.
    /// 정렬은 여기서 하지 않는다(sortedByTotalDescending 별도). 순수 함수라 결정적으로 검증한다.
    func toTokenBoardEntries() -> [TokenBoardEntry] {
        map { row in
            TokenBoardEntry(
                userID: row.userId,
                name: row.displayName,
                avatarURL: row.avatarUrl.flatMap { URL(string: $0) },
                total: row.total,
                claudeInput: row.claudeInput,
                claudeOutput: row.claudeOutput,
                claudeCacheRead: row.claudeCacheRead,
                claudeCacheCreation: row.claudeCacheCreation,
                codexInput: row.codexInput,
                codexOutput: row.codexOutput,
                todayTotal: row.todayTotal,
                todayDate: row.todayDate
            )
        }
    }
}

extension Array where Element == TokenBoardEntry {
    /// 토큰 보드 정렬 단일 규약: 이번 달 총합 내림차순, 동률이면 이름 오름차순. 스토어(반영)와 뷰(재정렬)가 공유한다.
    func sortedByTotalDescending() -> [TokenBoardEntry] {
        sorted { lhs, rhs in
            if lhs.total != rhs.total {
                return lhs.total > rhs.total
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}

/// token_usage_board(p_month) RPC 본문(snake_case 인코딩 → p_month). 앱이 계산한 KST 'YYYY-MM' 를 보낸다.
struct TokenBoardRequest: Encodable {
    let pMonth: String
}

/// token_usage_device_monthly upsert 본문(snake_case 인코딩). D1 의 TokenUsageMonthly 에서 서비스가 값을 옮겨 담는다.
struct TokenUsageUpsertRequest: Encodable {
    let userId: String
    let month: String
    /// 이 기기의 안정 식별자. 원장 키가 (user_id, month, device_id) 라 맥 2대가 서로의 값을 덮어쓰지 않고
    /// 각자 행을 유지하며, 월 총량 합산은 서버 보드(token_usage_board)가 user_id 로 묶어 수행한다.
    let deviceId: String
    let claudeInput: Int
    let claudeOutput: Int
    let claudeCacheRead: Int
    let claudeCacheCreation: Int
    let codexInput: Int
    let codexOutput: Int
    let total: Int
    // 오늘(KST) 증가량과 귀속 날짜 — 서버 행에 함께 저장돼 순위판 "오늘 +N" 에 쓰인다.
    let todayTotal: Int
    let todayDate: String
}

/// 옛 표 token_usage_monthly upsert 본문(= v0.2.10 이 쓰던 그 모양, device_id 없음).
/// v0.2.11 도 이 표를 계속 갱신한다 — 이유는 SupabaseWorkService.upsertLegacyTokenUsage 주석 참조.
struct TokenUsageLegacyUpsertRequest: Encodable {
    let userId: String
    let month: String
    let claudeInput: Int
    let claudeOutput: Int
    let claudeCacheRead: Int
    let claudeCacheCreation: Int
    let codexInput: Int
    let codexOutput: Int
    let total: Int
    let todayTotal: Int
    let todayDate: String
}

/// 옛 표 token_usage_monthly 의 '지금 값' 조회 응답 한 줄(select=total 만). 덮어쓰기 전에 읽어,
/// 그 행이 아직 v0.2.10 인 다른 맥의 더 큰 누적치일 때 내 값으로 깎아내리지 않기 위해 쓴다.
struct TokenUsageLegacyTotalRow: Decodable {
    let total: Int
}

struct TeamWeeklyGoal: Equatable {
    static let defaultGoalSeconds = 60 * 60 * 60
    // 목표시간 기본값(시간 단위). teams.weekly_goal_hours 누락/null 시 폴백에 쓴다.
    static let defaultGoalHours = defaultGoalSeconds / 3600
    static let koreanTimeZone = TimeZone(identifier: "Asia/Seoul")!
    /// KST(월요일 주 시작) 그레고리력 1회 생성 재사용. todayDuration 이 매초 koreanDayStart/koreanWeekStart 를
    /// 호출하므로 호출마다 Calendar 를 새로 만들지 않는다. startOfDay 는 firstWeekday 와 무관해 안전히 공유된다.
    static let kstCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = koreanTimeZone
        calendar.firstWeekday = 2
        return calendar
    }()

    let workedSeconds: Int
    let goalSeconds: Int

    init(workedSeconds: Int, goalSeconds: Int = Self.defaultGoalSeconds) {
        self.workedSeconds = max(0, workedSeconds)
        self.goalSeconds = max(1, goalSeconds)
    }

    var progress: Double {
        min(1, Double(workedSeconds) / Double(goalSeconds))
    }

    var isComplete: Bool {
        workedSeconds >= goalSeconds
    }

    var remainingSeconds: Int {
        max(0, goalSeconds - workedSeconds)
    }

    static func koreanWeekStart(for date: Date) -> Date {
        kstCalendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
    }

    static func koreanDayStart(for date: Date) -> Date {
        kstCalendar.startOfDay(for: date)
    }
}

struct SupabaseSession: Equatable {
    let accessToken: String
    let refreshToken: String?
    let userID: String
}

enum SupabaseWorkServiceError: Error, Equatable {
    case missingAnonKey
    case invalidAPIKey
    case sessionExpired
    case invalidLoginCredentials
    case emailNotConfirmed
    case emailAlreadyRegistered
    case signupDisabled
    case weakPassword
    case databaseSchemaMissing
    case sessionAlreadyOpen
    case authMessage(String)
    case invalidResponse(Int)
}

struct EmptyBody: Encodable {}

struct SignInRequest: Encodable {
    let email: String
    let password: String
}

struct SignUpRequest: Encodable {
    let email: String
    let password: String
    let data: [String: String]
}

/// lookup_team_by_code / join_team RPC 본문. code 는 클라에서 정규화(대문자·공백/하이픈 제거)한 값을 보낸다.
struct InviteCodeRequest: Encodable {
    let code: String
}

/// create_team RPC 본문. snake_case 인코딩으로 team_name, goal_hours 로 나간다.
struct CreateTeamRequest: Encodable {
    let teamName: String
    let goalHours: Int
}

/// set_team_weekly_goal RPC 본문. snake_case 인코딩으로 goal_hours 로 나간다.
struct SetTeamGoalRequest: Encodable {
    let goalHours: Int
}

struct SignInResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let user: AuthUser
}

struct SignUpResponse: Decodable {
    let accessToken: String?
    let refreshToken: String?
    let user: AuthUser
}

struct RefreshSessionRequest: Encodable {
    let refreshToken: String
}

struct AuthUser: Decodable {
    let id: String
}

struct ProfileRow: Decodable {
    let displayName: String
    let email: String
    let avatarUrl: String?
}

struct WorkStatusRow: Decodable {
    let userId: String
    let status: String
    let updatedAt: String?
    let lastSeenAt: String?
    let activeSessionId: String?
    let profiles: ProfileRow?
}

struct WorkSessionRow: Decodable {
    let id: String?
    let userId: String
    let startedAt: String
    let endedAt: String?
    let durationSeconds: Int?
}

/// lookup_team_by_code(code) RPC 응답 행. security definer 함수라 team_id 는 uuid → 문자열로 받는다.
struct TeamJoinPreviewRow: Decodable {
    let teamId: String
    let name: String
    let weeklyGoalHours: Int
    let memberCount: Int
}

/// join_team(code) RPC 응답 행. 합류 성공 시 팀 정보를 돌려준다(불일치/비로그인은 0행).
struct JoinTeamRow: Decodable {
    let teamId: String
    let name: String
    let weeklyGoalHours: Int
}

/// create_team(team_name, goal_hours) RPC 응답 행. 새로 만든 팀의 참여코드를 함께 돌려준다.
struct CreateTeamRow: Decodable {
    let teamId: String
    let name: String
    let inviteCode: String
    let weeklyGoalHours: Int
}

/// my_team_invite_code() RPC 응답 행(소속 팀원 전체 공개). 무소속이면 0행.
struct InviteCodeRow: Decodable {
    let inviteCode: String
}

/// set_team_weekly_goal RPC 응답 행. 서버가 반영한 새 주간 목표시간(시간 단위)을 돌려준다.
struct SetTeamGoalRow: Decodable {
    let weeklyGoalHours: Int
}

/// team_weekly_leaderboard() RPC 응답 행. total_seconds 는 bigint(초)라 Int(64비트)로 받는다.
/// memberCount 는 member_count 를 아직 안 내려주는 구버전 RPC(마이그레이션 미적용)와도 호환되게
/// optional 로 두고, 디코드 시 누락되면 0 으로 폴백한다(평균 계산은 0명 가드로 안전하다).
struct TeamLeaderboardRow: Decodable {
    let teamId: String
    let teamName: String
    let weeklyGoalHours: Int
    let totalSeconds: Int
    let workingCount: Int
    let memberCount: Int?
}

/// memberships?select=team_id,role,teams(name,weekly_goal_hours) 응답 행. teams 는 임베드 조인.
/// role 은 owner/member. 누락 시 member 로 폴백한다.
struct MembershipRow: Decodable {
    let teamId: String
    let role: String?
    let teams: MembershipTeamRow?
}

/// 임베드된 teams 행. weeklyGoalHours 는 목표시간(시간 단위). 누락/null 이면 기본값으로 폴백한다.
struct MembershipTeamRow: Decodable {
    let name: String
    let weeklyGoalHours: Int?
}

struct StartSessionRequest: Encodable {
    let id: String
    let teamId: String
    let userId: String
    let startedAt: String
}

struct StopSessionRequest: Encodable {
    let endedAt: String
    let durationSeconds: Int
}

/// 자동 마감된 세션을 되돌릴 때 ended_at/duration_seconds 를 명시적으로 null 로 재개한다.
/// (기본 합성 인코더는 nil Optional 을 생략하므로 encodeNil 로 서버에 null 을 확실히 보낸다.)
struct ReopenSessionRequest: Encodable {
    enum CodingKeys: String, CodingKey {
        case endedAt
        case durationSeconds
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeNil(forKey: .endedAt)
        try container.encodeNil(forKey: .durationSeconds)
    }
}

struct CompletedSessionRequest: Encodable {
    let id: String
    let teamId: String
    let userId: String
    let startedAt: String
    let endedAt: String
    let durationSeconds: Int
}

struct StatusUpsertRequest: Encodable {
    let teamId: String
    let userId: String
    let status: String
    let activeSessionId: String?
    let lastSeenAt: String
    let updatedAt: String
}

/// work_status_devices upsert 본문(on_conflict=team_id,user_id,device_id). 하트비트가 상태 upsert **뒤에**
/// 한 번 더 보낸다 — 이 요청은 별도 경로라 위 StatusUpsertRequest 는 바이트 하나 달라지지 않는다
/// (v0.2.10 이 계속 정상 upsert 해야 한다는 제1원칙).
/// sessionId 를 Optional 로 두지 않는 이유: Swift 합성 Encodable 은 nil Optional 을 **생략**하고,
/// PostgREST 의 merge-duplicates 는 본문에 없는 컬럼을 건드리지 않는다 → 옛 세션 ID 가 행에 그대로 남아
/// "이 맥이 지금 그 세션을 쓰고 있다"는 거짓 주장이 된다. 호출부(sendHeartbeatIfWorking)가 세션 ID 가드를
/// 이미 통과한 뒤라 non-optional 로 두는 것이 그 함정을 구조적으로 없앤다.
struct StatusDeviceUpsertRequest: Encodable {
    let teamId: String
    let userId: String
    let deviceId: String
    let sessionId: String
    let lastSeenAt: String
    let updatedAt: String
    /// 이 맥이 그 세션을 **직접 열었는가**. sessionId 와 같은 이유로 Optional 이 아니다 — nil 이면 Swift 합성
    /// Encodable 이 키를 **생략**하고 PostgREST merge-duplicates 는 본문에 없는 컬럼을 건드리지 않아,
    /// 백스톱으로 약하게 주장하는 맥의 행에 예전 true 가 그대로 눌러앉는다(= 추측이 사실로 승격되어
    /// 진짜 소유자를 밀어낸다). 매 하트비트마다 지금의 강/약을 **덮어쓴다**.
    let openedSession: Bool
}

/// work_status_devices 조회 응답 한 행. team_id 는 조회 필터로 이미 고정돼 있어 담지 않는다.
/// lastSeenAt 은 문자열로 받아 서비스의 parseDate(소수초 있는/없는 timestamptz 양쪽) 로 해석한다.
struct WorkStatusDeviceRow: Decodable, Equatable {
    let userId: String
    let deviceId: String
    let sessionId: String?
    let lastSeenAt: String?
    /// Optional 로 받는 이유: 이 컬럼이 아직 없는 서버(마이그레이션 순서)에서 select 가 이 키를 빼고 오면
    /// non-optional Bool 은 **행 전체의 디코드를 throw** 시키고, 그러면 기기 주장이 통째로 사라져 반납
    /// 규칙이 조용히 죽는다. 없으면 nil → 호출부가 false(약함)로 읽는다 = 모르면 약하다.
    let openedSession: Bool?
}

struct AvatarUpdateRequest: Encodable {
    let avatarUrl: String
}

struct SupabaseErrorResponse: Decodable {
    let message: String?
    let msg: String?
    let error: String?
    let errorDescription: String?
    let errorCode: String?
}

// MARK: - 콕찌르기 / 토큰 사용량 공개 설정 (계약 타입)

/// app_user_directory RPC 응답 행. 앱 사용자 전체(본인 제외) + 근무중 여부.
struct PokeDirectoryRow: Decodable, Equatable {
    let userId: String
    let displayName: String
    let avatarUrl: String?
    let isWorking: Bool
}

/// 콕찌르기 패널 표시용 엔트리.
struct PokeDirectoryEntry: Identifiable, Equatable {
    let userID: String
    var name: String
    var avatarURL: URL?
    var isWorking: Bool

    var id: String { userID }
}

extension [PokeDirectoryRow] {
    /// RPC 행 → 표시 엔트리. 스토어(반영)와 테스트가 공유하는 순수 변환.
    func toPokeDirectoryEntries() -> [PokeDirectoryEntry] {
        map { row in
            PokeDirectoryEntry(
                userID: row.userId,
                name: row.displayName,
                avatarURL: row.avatarUrl.flatMap(URL.init(string:)),
                isWorking: row.isWorking
            )
        }
    }
}

extension [PokeDirectoryEntry] {
    /// 근무중 먼저, 그 안에서 이름 오름차순. 서버 정렬과 동일 규약(클라 재정렬로 안정 표시).
    func sortedForPokeDisplay() -> [PokeDirectoryEntry] {
        sorted { lhs, rhs in
            if lhs.isWorking != rhs.isWorking { return lhs.isWorking }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}

/// 찌르기 종류. 서버 pokes.kind 문자열과 1:1. 미지 값·nil 은 전부 normal 로 접는다 —
/// 마이그레이션 미적용 서버(kind 키 없음)와 미래에 추가될 종류 양쪽에서 말풍선은 뜨게 하기 위해서다.
enum PokeKind: String, Equatable {
    case normal, ultra

    init(rawServerValue: String?) { self = (rawServerValue == "ultra") ? .ultra : .normal }
}

/// poke_user RPC 요청. { p_to: 대상 user id } — ultra_poke_user 도 같은 본문을 재사용한다(인자가 동일).
struct PokeSendRequest: Encodable {
    let pTo: String
}

/// poke_user / ultra_poke_user RPC 응답:
/// { status: "ok"|"cooldown"|"not_working"|"target_not_working"|"ultra_used_today"|"invalid",
///   retry_after_seconds?, reset_after_seconds?, ultra_remaining? }
struct PokeSendResponse: Decodable, Equatable {
    let status: String
    var retryAfterSeconds: Int?
    /// ultra_used_today 의 KST 자정까지 남은 초. **이 타입은 커스텀 init(from:) 를 갖고 있어**
    /// CodingKey 만 더하면 값이 영원히 nil 이고, 그러면 안내 문구가 항상 폴백으로 굳는다.
    var resetAfterSeconds: Int?
    /// 오늘(KST) 울트라를 몇 번 더 쓸 수 있는가. 서버가 ok/ultra_used_today 응답에 실어 준다.
    /// **nil 은 0 이 아니라 '모른다'** 이다 — 일반 poke_user 응답과 이 키를 안 보내는 구버전 서버가 여기로 온다.
    /// 이 구분이 없으면 일반 찌르기 한 번에 화면이 "오늘 0번 남음"이라고 거짓말한다.
    var ultraRemaining: Int?

    enum CodingKeys: String, CodingKey {
        case status
        case retryAfterSeconds
        case resetAfterSeconds
        case ultraRemaining
    }

    init(status: String, retryAfterSeconds: Int? = nil, resetAfterSeconds: Int? = nil, ultraRemaining: Int? = nil) {
        self.status = status
        self.retryAfterSeconds = retryAfterSeconds
        self.resetAfterSeconds = resetAfterSeconds
        self.ultraRemaining = ultraRemaining
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(String.self, forKey: .status)
        retryAfterSeconds = try container.decodeIfPresent(Int.self, forKey: .retryAfterSeconds)
        // ↓ 아래 두 줄이 이 타입의 함정 전부다. 직접 생성(PokeSendResponse(status:…)) 테스트로는
        //   커스텀 디코더의 누락을 원리적으로 못 잡으므로 JSON 을 실제로 통과시키는 테스트로 못 박는다.
        resetAfterSeconds = try container.decodeIfPresent(Int.self, forKey: .resetAfterSeconds)
        ultraRemaining = try container.decodeIfPresent(Int.self, forKey: .ultraRemaining)
    }

    /// 스토어가 `ultraRemainingToday` 에 **그대로 대입할** 값(음수 방어만 한다). 상한 클램프를 여기서 하지 않는 이유는
    /// 하루 한도(WorkTimerStore.ultraPokeDailyLimit)를 아는 쪽이 스토어이기 때문이다 — 모델이 그 상수를 알면
    /// 한도를 바꿀 때 고쳐야 할 곳이 둘로 늘어난다.
    /// nil 이면 **대입하지 마라**(모름 유지). 화면은 모를 때 아무 말도 하지 않는 쪽이 틀린 숫자보다 낫다.
    var ultraRemainingForDisplay: Int? { ultraRemaining.map { max(0, $0) } }
}

/// 찌르기 결과의 도메인 표현(스토어/UI 공유). **미지 status 는 반드시 .invalid 로 떨어진다** —
/// 서버가 나중에 상태를 하나 더 늘려도(예: target_saturated) 옛 앱이 크래시하지 않고 안전한 문구로 수렴한다.
enum PokeSendOutcome: Equatable {
    case ok
    case cooldown(retryAfterSeconds: Int)
    case notWorking
    case targetNotWorking
    /// 오늘(KST) 울트라 몫을 다 썼다. **poke_user 는 이 status 를 절대 내지 않는다** —
    /// 두 RPC 가 status 어휘를 공유하는 대신 enum 하나로 통일한 결과다(sendPoke 쪽은 도달 불가 분기로 남는다).
    case ultraUsedToday(resetAfterSeconds: Int)
    /// 대상이 집중 모드다(20260812090000). 몫도 쿨타임도 소모되지 않는다 — 서버가 행을 안 남긴다.
    case targetFocused
    case invalid

    init(response: PokeSendResponse) {
        switch response.status {
        case "ok": self = .ok
        case "cooldown": self = .cooldown(retryAfterSeconds: max(1, response.retryAfterSeconds ?? 60))
        case "not_working": self = .notWorking
        case "target_not_working": self = .targetNotWorking
        case "ultra_used_today": self = .ultraUsedToday(resetAfterSeconds: max(1, response.resetAfterSeconds ?? 3600))
        case "target_focused": self = .targetFocused
        default: self = .invalid
        }
    }
}

/// take_pokes RPC 응답 행(수신 즉시 서버에서 소비 완료된 찔림).
struct TakenPokeRow: Decodable, Equatable {
    let id: String
    let fromUser: String
    let fromDisplayName: String
    let fromAvatarUrl: String?
    /// 찔린 시각의 epoch 초(서버가 extract(epoch ...)::bigint 로 내려줌 — ISO 소수초 파싱 함정 회피).
    let createdEpoch: Int
    /// 찌르기 종류(20260804030000). **Optional 인 것이 핵심이다** — 앱을 먼저 배포하고 db push 가 늦은 창에서는
    /// 서버가 이 키를 안 보내는데, 비옵셔널이면 [TakenPokeRow] 디코드가 통째로 throw 되어 그 사이 도착한
    /// 모든 찔림이(일반 찌르기까지) 조용히 소멸한다. 합성 Decodable 은 Optional 에 decodeIfPresent 를 쓴다.
    /// `let` 이 아니라 `var` 인 이유도 하나뿐이다: Optional `var` 만 멤버와이즈 init 에서 기본값 nil 을 받아
    /// kind 를 모르던 기존 호출부(테스트 픽스처 포함)가 무수정으로 컴파일된다.
    var kind: String?
}

/// 오버레이로 전달되는 수신 찔림 한 건.
struct ReceivedPoke: Equatable {
    let id: String
    let fromName: String
    let createdAt: Date
    let kind: PokeKind

    /// kind 기본값 .normal 은 하위호환용이다 — 이 인자를 모르는 기존 호출부가 그대로 컴파일된다.
    init(id: String, fromName: String, createdAt: Date, kind: PokeKind = .normal) {
        self.id = id
        self.fromName = fromName
        self.createdAt = createdAt
        self.kind = kind
    }
}

/// profiles.token_usage_public 자기 행 조회 응답.
struct ProfilePrivacyRow: Decodable, Equatable {
    let tokenUsagePublic: Bool?
    /// 토큰 사용량 수집 여부(20260803010000). 서버가 쓰기를 조용히 버리므로 앱 게이트는 통신 낭비를 줄이는
    /// 부수적 장치다 — 컬럼/행이 없으면 수집(true)으로 본다(마이그레이션 미적용 서버에서 기존 동작 유지).
    let tokenUsageCollect: Bool?
    /// 집중 모드(20260812090000). **Optional 이 핵심이다** — 앱을 먼저 배포하고 db push 가 늦은 창에서는
    /// 서버가 이 키를 안 보내는데, 비옵셔널이면 행 디코드가 통째로 throw 되어 토큰 공개 설정까지 못 읽는다.
    /// 컬럼이 없으면 꺼짐(false)으로 본다 = 기존 동작 유지.
    let focusMode: Bool?
}

/// profiles.token_usage_public 자기 행 갱신 요청(PATCH).
struct ProfilePrivacyUpdateRequest: Encodable {
    let tokenUsagePublic: Bool
}

/// profiles.focus_mode 자기 행 갱신 요청(PATCH). 토큰 공개와 **따로** 보내는 이유는 하나다 —
/// 한 요청에 두 컬럼을 실으면 둘 중 하나만 컬럼 권한이 있는 서버에서 요청 전체가 403 이 된다.
struct ProfileFocusModeUpdateRequest: Encodable {
    let focusMode: Bool
}

// MARK: - 별명(표시명) 변경 (계약 타입)

/// set_display_name RPC 요청. { p_name: 사용자가 입력한 원문 } — 정규화의 최종 권한은 서버다.
struct SetDisplayNameRequest: Encodable {
    let pName: String
}

/// set_display_name RPC 응답(jsonb 단일 객체). PokeSendResponse 와 같은 이유로 커스텀 디코드를 쓴다 —
/// 합성 디코더는 옵셔널 키가 빠진 응답에서도 안전하지만, 여기서는 키 집합이 status 별로 달라
/// 명시 decodeIfPresent 로 의도를 못 박는 편이 다음 사람에게 정확하다.
struct DisplayNameChangeResponse: Decodable, Equatable {
    let status: String
    var displayName: String?
    var retryAfterSeconds: Int?
    var maxLength: Int?

    enum CodingKeys: String, CodingKey {
        case status, displayName, retryAfterSeconds, maxLength
    }

    init(status: String, displayName: String? = nil, retryAfterSeconds: Int? = nil, maxLength: Int? = nil) {
        self.status = status
        self.displayName = displayName
        self.retryAfterSeconds = retryAfterSeconds
        self.maxLength = maxLength
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = try c.decode(String.self, forKey: .status)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        retryAfterSeconds = try c.decodeIfPresent(Int.self, forKey: .retryAfterSeconds)
        maxLength = try c.decodeIfPresent(Int.self, forKey: .maxLength)
    }
}

/// 별명 변경 결과의 도메인 표현(스토어/UI 공유). **모르는 status 는 반드시 .invalid 로 떨어진다** —
/// 서버가 나중에 상태를 하나 더 늘려도 옛 앱이 크래시하지 않고 안전한 문구로 수렴한다(PokeSendOutcome 규약).
/// unauthorized·no_profile 도 여기로 접힌다.
enum DisplayNameChangeOutcome: Equatable {
    case ok(name: String)
    case unchanged
    case taken
    case cooldown(retryAfterSeconds: Int)
    case tooLong(maxLength: Int)
    case empty
    case invalid

    init(response: DisplayNameChangeResponse) {
        switch response.status {
        case "ok":            self = .ok(name: response.displayName ?? "")
        case "unchanged":     self = .unchanged
        case "taken":         self = .taken
        case "cooldown":      self = .cooldown(retryAfterSeconds: max(1, response.retryAfterSeconds ?? 604_800))
        // max_length 를 안 실어 준 응답(옛 서버/잘린 JSON)에서만 쓰이는 폴백이다. 숫자를 여기 박아 두면
        // 상한을 바꿀 때 **이 한 줄만 옛 값으로 남아**, 사용자는 "12자까지"라고 배운 화면을 보다가 거절 문구에서만
        // 다른 숫자를 듣게 된다. 상한의 유일한 근거(WorkTimerStore.displayNameMaxLength)를 그대로 읽는다 —
        // 그 상수는 nonisolated 라 모델의 비격리 init 에서 읽어도 액터 경계에 걸리지 않는다.
        case "invalid_long":  self = .tooLong(maxLength: max(1, response.maxLength ?? WorkTimerStore.displayNameMaxLength))
        case "invalid_empty": self = .empty
        default:              self = .invalid
        }
    }
}

/// display_name_changed_at 전용 1컬럼 응답. 컬럼이 없는 서버에서는 이 GET 자체가 400 이 되고
/// 호출부가 삼키므로, 옵셔널 폴백이 아니라 **요청 단위 격리**로 하위호환을 얻는다.
struct DisplayNameChangedAtRow: Decodable, Equatable {
    let displayNameChangedAt: String?
}
