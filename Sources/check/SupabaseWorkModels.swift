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

    /// 서버 하트비트를 기준으로 팀원의 생존 상태를 판정한다.
    /// seen = lastSeenAt ?? updatedAt. seen이 없으면(신호 미상) 살아있다고 본다.
    func presence(now: Date = Date()) -> MemberPresence {
        guard status == .working else {
            return .offWork
        }
        guard let seen = lastSeenAt ?? updatedAt else {
            return .activeWorking
        }
        guard now.timeIntervalSince(seen) > 90 else {
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

/// my_team_invite_code() RPC 응답 행(owner 전용). 아니면 0행.
struct InviteCodeRow: Decodable {
    let inviteCode: String
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
