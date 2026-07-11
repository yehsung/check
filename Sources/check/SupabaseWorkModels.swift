import Foundation

struct TeamMemberStatus: Equatable, Identifiable {
    let id: String
    var name: String
    var status: WorkStatus
    var updatedAt: Date?
    var currentSessionStartedAt: Date?
    var weeklyDurationSeconds: Int = 0
    var todayDurationSeconds: Int = 0

    func currentDurationSeconds(now: Date = Date()) -> Int {
        guard status == .working, let currentSessionStartedAt else {
            return 0
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

struct TeamWeeklyGoal: Equatable {
    static let defaultGoalSeconds = 60 * 60 * 60
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
}

struct WorkStatusRow: Decodable {
    let userId: String
    let status: String
    let updatedAt: String?
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

struct SupabaseErrorResponse: Decodable {
    let message: String?
    let msg: String?
    let error: String?
    let errorDescription: String?
    let errorCode: String?
}
