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
        weeklyDurationSeconds + currentDurationSeconds(now: now)
    }

    func liveTodayDurationSeconds(now: Date = Date()) -> Int {
        todayDurationSeconds + currentDurationSeconds(now: now)
    }
}

enum PendingWorkOperation: Equatable {
    case start
    case stop(durationSeconds: Int)
}

/// 가입 화면 팀 목록의 한 항목. team_directory() RPC 로 받아 온다(invite_code 는 노출되지 않음).
struct TeamDirectoryEntry: Identifiable, Equatable {
    let id: String
    let name: String
}

/// 팀 리그(이번 주 팀별 총 근무시간 경쟁)의 한 행. team_weekly_leaderboard() RPC 로 받아 온다.
/// id 는 팀 id(내 팀 하이라이트 판정에 쓴다). invite_code 는 RPC 가 반환하지 않으므로 노출되지 않는다.
struct TeamLeaderboardEntry: Identifiable, Equatable {
    let id: String
    let name: String
    let weeklyGoalHours: Int
    let totalSeconds: Int
    let workingCount: Int

    /// 목표 대비 진행률 게이지(주간 목표 게이지와 같은 규약: 0~1 클램프, 목표=weeklyGoalHours 시간).
    var goal: TeamWeeklyGoal {
        TeamWeeklyGoal(workedSeconds: totalSeconds, goalSeconds: weeklyGoalHours * 3600)
    }
}

struct TeamWeeklyGoal: Equatable {
    static let defaultGoalSeconds = 60 * 60 * 60
    // 목표시간 기본값(시간 단위). teams.weekly_goal_hours 누락/null 시 폴백에 쓴다.
    static let defaultGoalHours = defaultGoalSeconds / 3600
    static let koreanTimeZone = TimeZone(identifier: "Asia/Seoul")!

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
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = koreanTimeZone
        calendar.firstWeekday = 2
        return calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
    }

    static func koreanDayStart(for date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = koreanTimeZone
        return calendar.startOfDay(for: date)
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

/// team_directory() RPC 응답 행. 계약상 TeamDirectoryEntry 선언은 고정이므로 파싱은 별도 행으로 한다.
struct TeamDirectoryRow: Decodable {
    let id: String
    let name: String
}

/// team_weekly_leaderboard() RPC 응답 행. total_seconds 는 bigint(초)라 Int(64비트)로 받는다.
struct TeamLeaderboardRow: Decodable {
    let teamId: String
    let teamName: String
    let weeklyGoalHours: Int
    let totalSeconds: Int
    let workingCount: Int
}

/// memberships?select=team_id,teams(name,weekly_goal_hours) 응답 행. teams 는 임베드 조인.
struct MembershipRow: Decodable {
    let teamId: String
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
