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

/// 수동 Codable(v0.2.36 — pendingItems 영속용). 합성에 맡기지 않는 이유: 합성 포맷은 케이스 구조가
/// 그대로 디스크 포맷이 되어, 케이스를 고치는 순간 이전 실행이 남긴 큐가 통째로 디코드 실패한다.
/// kind 문자열을 손으로 못 박아 디스크 계약을 코드 구조에서 분리한다(모르는 kind 는 throw —
/// 호출부가 빈 큐로 접는다).
extension PendingWorkOperation: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case durationSeconds
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .kind) {
        case "start":
            self = .start
        case "stop":
            self = .stop(durationSeconds: try container.decode(Int.self, forKey: .durationSeconds))
        case let kind:
            throw DecodingError.dataCorruptedError(
                forKey: .kind, in: container, debugDescription: "unknown operation kind: \(kind)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .start:
            try container.encode("start", forKey: .kind)
        case .stop(let durationSeconds):
            try container.encode("stop", forKey: .kind)
            try container.encode(durationSeconds, forKey: .durationSeconds)
        }
    }
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

    // ── Codex 집계 진단(codex_diag_*, 전부 Int · "<빌드>:<KST 날짜>" 도장당 1회만 값이 실린다) ──
    //
    // **옵셔널인 것이 이 설계의 전부다.** 합성 Encodable 은 Optional 프로퍼티를 encodeIfPresent 로 내보내므로
    // nil 이면 JSON 본문에 **키 자체가 없고**, PostgREST 의 upsert(INSERT … ON CONFLICT DO UPDATE)는
    // 본문에 온 컬럼만 갱신한다 — 즉 서버에 이미 쌓인 진단값이 그대로 보존된다.
    // 옵셔널이 아니면(Int 로 두면) 30초마다 도는 이 업로드가 매번 0 을 실어 보내 직전 진단값을 덮어써,
    // 기능 전체가 무의미해진다. 실측으로 확인했다 — diagnostics 가 nil 인 본문에는 codex_diag_ 로 시작하는
    // 키가 하나도 나오지 않는다(아래 init 주석의 인코딩 결과 참조).
    //
    // 중첩 객체가 아니라 19개를 **펼쳐** 담는 이유: 서버가 스칼라 컬럼 19개라 jsonb 하나로는 upsert 되지 않는다.
    // 전 필드가 Int 인 것은 프라이버시의 구조적 보증이다(CodexUsageDiagnostics 주석) — 문자열을 더하지 마라.
    var codexDiagFilesTotal: Int?
    var codexDiagFilesMonth: Int?
    var codexDiagEventsMonth: Int?
    var codexDiagMaxDelta: Int?
    var codexDiagCarryFiles: Int?
    var codexDiagCarryTotal: Int?
    var codexDiagDupEvents: Int?
    var codexDiagDupTokens: Int?
    var codexDiagFinalSum: Int?
    var codexDiagDedupTotal: Int?
    var codexDiagDrops: Int?
    var codexDiagTopFile: Int?
    var codexDiagBuild: Int?

    // ── 2차 진단(델타 분포): 단일 이벤트 델타 10.7억의 정체를 가르는 5개 ──
    //
    // 1차(위 13개)로 resume 카운터 이월은 확정됐지만 `codexDiagMaxDelta` 하나가 총합을 좌우하는 사례가 남았다.
    // 그 델타가 (a) 앱을 오래 꺼 둔 사이 쌓인 정상 누적인지 (b) 산식이 만든 유령인지는 **분포와 시간 간격**으로만
    // 갈린다 — 그래서 큰 델타의 개수·합(bigDelta*)과 그 앞뒤 공백(gap 초)을 함께 싣는다. legacyTotal 은
    // 이월 수정 **전** 옛 산식의 총합이라, 같은 행에서 신·구 산식을 나란히 놓고 차이를 빼 볼 수 있게 한다.
    //
    // 위 13개와 완전히 같은 규약이다 — **옵셔널이 핵심**(nil = 키 생략 = 서버 값 보존), 전부 Int(문자열 금지),
    // 새 필드는 마지막에. 이 5개도 "<빌드>:<KST 날짜>" 도장당 1회만 값이 실린다(도장이 월→일 단위가 되어 하루 1회).
    var codexDiagLegacyTotal: Int?
    var codexDiagBigDeltaCount: Int?
    var codexDiagBigDeltaTotal: Int?
    var codexDiagMaxDeltaGapS: Int?
    var codexDiagBigGapMedianS: Int?

    // ── 3차: 진단을 **잰 그 순간의 Codex 총합** 스냅샷(codex_diag_input_at_scan) ──
    //
    // 위 18개와 `codex_input` 은 **서로 다른 시각의 값**이었다. `codex_input` 은 업로드마다(30초) 갱신되는데
    // 진단은 도장당 1회만 계산되므로, 진단을 올린 뒤 Codex 를 더 쓴 사람은 codex_input 만 자라고 진단은 얼어 있다.
    // 그래서 `legacy_total − codex_input` 같은 뺄셈이 진단 이후의 사용량까지 섞어 **음수**를 낸다
    // (실사고: -4,297,774,877 — 진단 이후 43억을 더 쓴 것이 차이에 섞였다).
    // 이 한 필드가 그 뺄셈에 쓸 **같은 시각의 분모**를 준다: 진단이 실린 그 업로드의 Codex 총합.
    //
    // 규약은 위 18개와 완전히 같다 — **옵셔널이 핵심**이다. nil 이면 키가 빠져 PostgREST 가 이 컬럼을 건드리지 않으므로,
    // 진단이 안 실리는 평상시 업로드(30초마다)가 이 스냅샷을 덮지 않는다. 옵셔널이 아니면 매 업로드마다 갱신돼
    // codex_input 과 똑같아지고 이 필드의 존재 이유가 통째로 사라진다.
    //
    // 값의 출처는 아래 생성자다 — 인자로 받지 않고 **같은 본문에 실리는 codexInput+codexOutput 에서 파생**시킨다.
    // 호출측이 따로 넘기게 두면 행에 실린 Codex 합과 스냅샷이 어긋날 여지가 생기는데, 그 어긋남이 정확히
    // 이 필드가 없애려던 결함이다. 파생이면 구조적으로 불가능하다.
    var codexDiagInputAtScan: Int?
}

extension TokenUsageUpsertRequest {
    /// 진단 스냅샷을 19개 스칼라로 펼쳐 담는 생성자. **diagnostics 가 nil 이면 19개 필드가 전부 nil 로 남아**
    /// 인코딩 결과에서 codex_diag_* 키가 통째로 사라진다(= 서버의 기존 진단값 보존).
    ///
    /// 19번째(codexDiagInputAtScan)만 diagnostics 안이 아니라 **이 생성자가 받은 codexInput+codexOutput 에서 파생**된다
    /// (= 같은 본문의 codex_input+codex_output, 즉 usage.codexTotal). 진단 스캐너는 앱의 월간 집계를 모르므로 그쪽에
    /// 넣을 수 없고, 넣더라도 "행에 실린 값"과 "스냅샷"이 다른 경로로 오는 순간 어긋날 수 있다. 여기서 파생시키면
    /// 두 값이 같은 한 줄에서 나와 구조적으로 일치한다. diagnostics 가 nil 이면 이 필드도 nil 이다(키 생략).
    ///
    /// nil 로 인코딩한 실물(keyEncodingStrategy = .convertToSnakeCase):
    /// {"user_id":"…","month":"2026-08","device_id":"…","claude_input":11,"claude_output":22,
    ///  "claude_cache_read":33,"claude_cache_creation":44,"codex_input":55,"codex_output":66,
    ///  "total":231,"today_total":77,"today_date":"2026-08-16"}
    /// — codex_diag_ 키 0개. (본문 이전과 완전히 동일하므로 구서버·기존 테스트도 그대로 통과한다.)
    init(
        userId: String,
        month: String,
        deviceId: String,
        claudeInput: Int,
        claudeOutput: Int,
        claudeCacheRead: Int,
        claudeCacheCreation: Int,
        codexInput: Int,
        codexOutput: Int,
        total: Int,
        todayTotal: Int,
        todayDate: String,
        diagnostics: CodexUsageDiagnostics?
    ) {
        self.init(
            userId: userId,
            month: month,
            deviceId: deviceId,
            claudeInput: claudeInput,
            claudeOutput: claudeOutput,
            claudeCacheRead: claudeCacheRead,
            claudeCacheCreation: claudeCacheCreation,
            codexInput: codexInput,
            codexOutput: codexOutput,
            total: total,
            todayTotal: todayTotal,
            todayDate: todayDate,
            codexDiagFilesTotal: diagnostics?.filesTotal,
            codexDiagFilesMonth: diagnostics?.filesMonth,
            codexDiagEventsMonth: diagnostics?.eventsMonth,
            codexDiagMaxDelta: diagnostics?.maxDelta,
            codexDiagCarryFiles: diagnostics?.carryFiles,
            codexDiagCarryTotal: diagnostics?.carryTotal,
            codexDiagDupEvents: diagnostics?.dupEvents,
            codexDiagDupTokens: diagnostics?.dupTokens,
            codexDiagFinalSum: diagnostics?.finalSum,
            codexDiagDedupTotal: diagnostics?.dedupTotal,
            codexDiagDrops: diagnostics?.drops,
            codexDiagTopFile: diagnostics?.topFile,
            codexDiagBuild: diagnostics?.appBuild,
            codexDiagLegacyTotal: diagnostics?.legacyTotal,
            codexDiagBigDeltaCount: diagnostics?.bigDeltaCount,
            codexDiagBigDeltaTotal: diagnostics?.bigDeltaTotal,
            codexDiagMaxDeltaGapS: diagnostics?.maxDeltaGapSeconds,
            codexDiagBigGapMedianS: diagnostics?.bigGapMedianSeconds,
            // 진단이 실릴 때만 값이 생긴다(nil 이면 키 생략 → 서버 스냅샷 보존). 값은 이 본문의 Codex 총합 그 자체.
            // codexTotal 을 쓰는 이유: 앱은 Codex 델타를 입출력 구분 없이 전액 codexInput 에 담고 codexOutput 은 항상 0 이라
            // 오늘은 codexInput 과 같은 값이지만, 훗날 출력을 쪼개 담더라도 "그 업로드의 Codex 총합"이라는 뜻이 유지된다.
            codexDiagInputAtScan: diagnostics.map { _ in codexInput + codexOutput }
        )
    }
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
    /// `ultra_wallet_sync` 가 서버에 아직 없다(PGRST202). **`databaseSchemaMissing` 을 그대로 재던지지 않는 이유**는
    /// takePokes 가 세운 관용구와 같다 — 그 오류는 "어떤 RPC 인지"를 잃어버린 값이라, 스토어가 받으면
    /// "서버 전체가 낡았다"와 "지갑 RPC 하나만 없다"를 가를 수 없다. 여기서 접어 두면 지갑만 조용히
    /// 못 쓰고(잔량 표시가 '못 읽었어요'로 내려앉고) 찌르기·메시지·근무는 그대로 산다.
    /// 브루 배포라 앱이 db push 보다 먼저 나가는 창이 실제로 존재한다.
    case ultraWalletUnavailable
    case sessionAlreadyOpen
    /// 429 레이트리밋 일반. 원래는 GoTrue 재발송 제한 전용이었지만 v0.2.36 부터 공용 매핑
    /// (SupabaseWorkHTTP.serviceError)의 상태코드 게이트가 **모든 429** 를 이 케이스로 접는다 —
    /// classifyAuthError 가 transient 로 분류해 일시 제한이 강제 로그아웃으로 번지지 않게 하기 위해서다.
    /// GoTrue 재발송 제한의 실측 본문이 두 종류다 — 이메일 발송 간격 제한은
    /// `{"error_code":"over_email_send_rate_limit","msg":"For security purposes, you can only request this after N seconds."}`,
    /// IP 단위 요청 제한은 `{"error_code":"over_request_rate_limit","msg":"Request rate limit reached"}`(2026-08-13 실측, verify 40연타).
    /// 뒤쪽엔 초가 아예 없으므로 **남은 초는 옵셔널이다** — nil 을 "0초"로 취급하면 재시도 버튼이 곧바로 열려 429 를 다시 부른다.
    case rateLimited(retryAfterSeconds: Int?)
    /// 재설정 코드가 틀렸거나 만료됐다. **둘을 나눌 수 없다** — GoTrue 는 계정/코드 존재 여부를 흘리지 않으려고
    /// 두 경우 모두 같은 403 `{"error_code":"otp_expired","msg":"Token has expired or is invalid"}` 를 준다
    /// (2026-08-13 실서버 실측: 존재하는 계정+틀린 코드, 없는 계정+아무 코드, 잘못된 type 까지 전부 동일 응답).
    /// 그래서 화면 문구도 하나로 합쳐야 한다("코드가 맞지 않거나 만료됐어요 — 다시 받아 주세요").
    case otpInvalidOrExpired
    /// 새 비밀번호가 이전과 같다(GoTrue `same_password`). **아직 이 값으로 오지 않는다** — 공용 매핑
    /// (SupabaseWorkHTTP.serviceError)이 "password" 를 포함한 모든 메시지를 .weakPassword 로 뭉개는데
    /// 그 파일은 이 트랙 소유가 아니라 못 고쳤다. 매핑 한 줄이 들어오면 그때부터 살아난다(보고서 참조).
    case samePasswordReuse
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

// MARK: - 비밀번호 재설정 OTP (브라우저·URL 스킴 없이 앱 안에서 끝내는 경로)

/// POST /auth/v1/recover 본문. **계정이 없어도 200 이 온다** — GoTrue 가 계정 존재 여부를 흘리지 않는다.
struct PasswordResetRequest: Encodable {
    let email: String
}

/// POST /auth/v1/verify 본문. type 은 반드시 "recovery" 다 — 다른 값은 서버가 403 otp_expired 로 되돌려
/// 사용자에게 "코드가 틀렸다"고 거짓말하게 된다(실측: type 만 바꿔도 같은 403).
/// 필드명이 모두 한 단어라 convertToSnakeCase 로도 email/token/type 그대로 나간다.
struct VerifyOTPRequest: Encodable {
    let email: String
    let token: String
    let type: String
}

/// PUT /auth/v1/user 본문. Authorization 은 verify 로 받은 recovery accessToken 이다.
struct UpdatePasswordRequest: Encodable {
    let password: String
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
    /// v0.2.38 부터 work_statuses select 에 싣지 않는다(서버가 안 주면 nil). Optional 로 남기는 이유는
    /// 임베드 컬럼을 되살린 서버/옛 응답이 와도 디코드가 깨지지 않게 하기 위함이다 — 표시에는 쓰지 않는다.
    let email: String?
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
    /// 자동 마감일 때만 채운다(사용자가 누른 종료는 nil = 키 생략 → v0.2.34 와 같은 바이트).
    /// 이 두 값이 곧 복원 게이트의 입력이다 — 사유가 안 남으면 서버 RPC 가 not_restorable 로 거절한다.
    let autoClosedAt: String?
    let autoClosedReason: String?
}

/// 자동 마감 사유만 정정하는 PATCH 본문. **잠자기 경로의 유일한 구제 통로다**: 뚜껑을 닫으면 서버
/// 스캐빈저가 10분 뒤 그 세션을 'abandoned' 로 먼저 마감하는데, 그 사유는 복원 대상이 아니다.
/// 깨어난 클라가 'sleep' 으로 고쳐야 "뚜껑 닫고 나간 사람"이 처음으로 구제된다(docs/away-close.md 4절).
struct AutoCloseReasonPatchRequest: Encodable {
    let autoClosedAt: String
    let autoClosedReason: String
}

/// 사유 정정 + **ended_at 을 더 이르게만** 당기는 PATCH 본문(늦추는 것은 위조라 서버 필터로 막는다 —
/// 호출부가 `ended_at=gt.<새 값>` 을 걸어 이미 더 이른 행에는 이 요청이 닿지 않게 한다).
struct AutoCloseCorrectionRequest: Encodable {
    let endedAt: String
    let durationSeconds: Int
    let autoClosedAt: String
    let autoClosedReason: String
}

/// 자동 마감된 세션을 되돌릴 때 ended_at/duration_seconds 를 명시적으로 null 로 재개한다.
/// (기본 합성 인코더는 nil Optional 을 생략하므로 encodeNil 로 서버에 null 을 확실히 보낸다 —
///  PostgREST 는 키 부재와 null 을 구분한다: 키가 빠지면 그 컬럼은 그대로 남는다.)
struct ReopenSessionRequest: Encodable {
    enum CodingKeys: String, CodingKey {
        case endedAt
        case durationSeconds
        case autoClosedAt
        case autoClosedReason
    }

    /// 자동 마감 잔재(auto_closed_*)도 함께 null 로 되돌릴지. 사유 컬럼이 없는 서버로 떨어지는
    /// withoutNewColumns 재시도만 false 를 쓴다(그때의 본문은 v0.2.35 와 같은 바이트다).
    var resetAutoClose = true

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeNil(forKey: .endedAt)
        try container.encodeNil(forKey: .durationSeconds)
        guard resetAutoClose else { return }
        // 되살린 **열린** 세션에 'abandoned' 꼬리표가 남으면 이후 이 세션이 다시 닫힐 때의 사유 판정과
        // 복원 자격 판정(is_restorable/서버 RPC)이 죽은 마감의 잔재를 읽는다 — 재개는 마감의 흔적까지 지운다.
        try container.encodeNil(forKey: .autoClosedAt)
        try container.encodeNil(forKey: .autoClosedReason)
    }
}

struct CompletedSessionRequest: Encodable {
    let id: String
    let teamId: String
    let userId: String
    let startedAt: String
    let endedAt: String
    let durationSeconds: Int
    /// 폴백 INSERT 도 자동 마감이면 사유를 함께 남긴다(nil 이면 키 생략).
    let autoClosedAt: String?
    let autoClosedReason: String?
}

/// 비소유 맥이 **자기 기기 행에 last_input_at 만** 쓰는 본문(docs/away-close.md 1절의 비소유 맥 규약).
/// session_id·last_seen_at·opened_session 을 **일부러 담지 않는다** — 담는 순간 이 행이 소유권 판정
/// (releaseOwnershipIfAnotherDeviceClaims / updateAdoptedPresenceTracking)의 증거로 승격돼,
/// "아이맥 켜둔 채 노트북에서 작업"을 구제하려던 쓰기가 v0.2.16 의 이중 소유 사고를 되살린다.
/// PostgREST merge-duplicates 는 본문에 있는 컬럼만 갱신하므로 기존 행의 그 세 값은 그대로 보존된다.
struct StatusDeviceInputRequest: Encodable {
    let teamId: String
    let userId: String
    let deviceId: String
    let lastInputAt: String
}

struct StatusUpsertRequest: Encodable {
    let teamId: String
    let userId: String
    let status: String
    let activeSessionId: String?
    let lastSeenAt: String
    let updatedAt: String
    /// 마지막 의미 있는 입력 시각(v0.2.35). **Optional 인 것이 계약이다** — nil 이면 Swift 합성 Encodable 이
    /// 키를 생략하고 PostgREST merge-duplicates 는 본문에 없는 컬럼을 건드리지 않으므로, 이 값을 모르는
    /// 경로(start/stop/reopen)의 요청 바이트가 v0.2.34 와 완전히 같다. 기본값을 둬서 기존 호출부가
    /// 그대로 컴파일되게 하지 않는 것도 의도다: 새 호출부가 "이 요청이 입력을 보고하는가"를 반드시 한 번 판단한다.
    let lastInputAt: String?
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
    /// 마지막 의미 있는 입력 시각(v0.2.35). nil 이면 키가 생략된다(위 StatusUpsertRequest 와 같은 규약).
    let lastInputAt: String?
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

/// app_user_directory RPC 응답 행. 앱 사용자 전체(본인 제외) + 근무중 여부 + 메시지 수신 가능 여부.
///
/// **커스텀 init(from:) 을 쓰는 이유는 하나뿐이다** — 메시지 수신 가능 여부의 서버 컬럼 이름이
/// 클라/SQL 두 트랙에서 동시에 정해졌기 때문이다. 어느 쪽 이름이 오든 읽는다:
///   · `message_capable`     — RPC 인자(p_message_capable)와 같은 어휘
///   · `can_receive_message` — 질문 그대로의 어휘
/// 이름이 확정되면 안 쓰는 쪽 한 줄만 지우면 된다. **둘 다 없어도 디코드는 깨지지 않는다**(nil).
/// 이 관용구가 없으면 이름이 갈리는 순간 사전 게이트가 조용히 죽고, 사용자는 보낸 뒤에야 거절을 본다.
///
/// ⚠️ 커스텀 디코더의 함정은 PokeSendResponse 주석이 적어 둔 그대로다 — 키를 더하고 여기에 줄을
/// 안 더하면 값이 **영원히 nil** 이다. 그래서 아래 필드는 전부 명시적으로 읽는다.
struct PokeDirectoryRow: Decodable, Equatable {
    let userId: String
    let displayName: String
    let avatarUrl: String?
    let isWorking: Bool
    /// 이 사람이 3글자 메시지를 **받을 수 있는가**(서버가 대상의 app_build 로 판정한다).
    /// **Optional 이 핵심이다** — 이 컬럼이 없는 서버(마이그레이션 순서)에서 비옵셔널이면 디렉토리
    /// 디코드가 통째로 throw 되어 콕찌르기 목록이 전원 사라진다(찔림까지 같이 죽는다).
    /// nil 은 "못 받는다"가 아니라 **"모른다"** 이고, 모를 때의 해석은 toPokeDirectoryEntries 에 있다.
    let canReceiveMessage: Bool?

    /// 키는 `.convertFromSnakeCase` 가 이미 카멜로 바꾼 뒤에 매칭되므로 **카멜로 적는다**
    /// (`message_capable` → `messageCapable`). 스네이크로 적으면 어떤 키도 안 잡혀 전부 nil 이 된다.
    enum CodingKeys: String, CodingKey {
        case userId, displayName, avatarUrl, isWorking
        case messageCapable, canReceiveMessage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userId = try container.decode(String.self, forKey: .userId)
        displayName = try container.decode(String.self, forKey: .displayName)
        avatarUrl = try container.decodeIfPresent(String.self, forKey: .avatarUrl)
        isWorking = try container.decode(Bool.self, forKey: .isWorking)
        canReceiveMessage = try container.decodeIfPresent(Bool.self, forKey: .messageCapable)
            ?? container.decodeIfPresent(Bool.self, forKey: .canReceiveMessage)
    }

    /// 테스트/변환 픽스처용 직접 생성자. 커스텀 init(from:) 을 만든 순간 멤버와이즈 init 이 사라지므로
    /// 명시한다(기본값은 '모름' — 서버가 말해 주지 않은 상태와 같은 뜻이다).
    init(userId: String, displayName: String, avatarUrl: String?, isWorking: Bool, canReceiveMessage: Bool? = nil) {
        self.userId = userId
        self.displayName = displayName
        self.avatarUrl = avatarUrl
        self.isWorking = isWorking
        self.canReceiveMessage = canReceiveMessage
    }
}

/// 콕찌르기 패널 표시용 엔트리.
struct PokeDirectoryEntry: Identifiable, Equatable {
    let userID: String
    var name: String
    var avatarURL: URL?
    var isWorking: Bool
    /// 이 사람에게 **3글자 메시지를 보낼 수 있는가**(화면이 메시지 버튼을 미리 끄는 근거).
    /// 찌르기는 이 값과 무관하다 — 구버전 앱도 찔림은 그대로 받는다.
    ///
    /// **모르면 true 인 이유**: 이 값은 판정이 아니라 예고다. 서버가 아직 이 컬럼을 안 보내는 구간에서
    /// false 로 접으면 클라가 서버에 없는 금지를 발명해 **전원에게** 메시지 버튼이 꺼진다(기능 전체 정지).
    /// 반대로 true 로 두면 최악이 "보낸 뒤 target_outdated 안내"이고, 그건 이 기능이 원래 감당하는 실패다.
    /// 최종 판정은 언제나 서버다(messageTargetOutdatedNotice 가 그 답을 옮긴다).
    var canReceiveMessage: Bool = true

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
                isWorking: row.isWorking,
                // '모름(nil)'은 허용으로 읽는다 — 근거는 위 프로퍼티 주석에 있다.
                canReceiveMessage: row.canReceiveMessage ?? true
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
    /// 3글자 메시지(같은 take_pokes 폴링으로 도착한다). **normal 로 접지 않고 케이스를 나눈 이유는 하나다** —
    /// 화면이 보여줄 것이 다르다(찔림은 보낸 사람만, 메시지는 본문까지). 반대로 이 종류를 모르는 옛 앱에서는
    /// 미지 값 규약대로 normal 로 접혀 **일반 찔림 말풍선이라도 뜬다** — 본문은 못 봐도 무음 소실보다는 낫다.
    case message

    init(rawServerValue: String?) {
        switch rawServerValue {
        case "ultra":   self = .ultra
        case "message": self = .message
        default:        self = .normal
        }
    }
}

/// poke_user RPC 요청. { p_to: 대상 user id } — ultra_poke_user 도 같은 본문을 재사용한다(인자가 동일).
struct PokeSendRequest: Encodable {
    let pTo: String
}

/// ultra_wallet_sync RPC 본문. { p_days_back: 소급 일수 }.
/// **본문을 비우지 않는 이유**: PostgREST 는 본문의 키 집합으로 오버로드를 고른다. 기본값이 있어도
/// 키를 명시해 두면 나중에 인자가 하나 더 생겨도 이 호출이 어느 함수로 갈지 흔들리지 않는다.
struct UltraWalletSyncRequest: Encodable {
    let pDaysBack: Int
}

/// take_pokes RPC 요청. { p_message_capable: 이 앱이 메시지를 표시할 수 있는가 }.
///
/// **이 인자가 존재하는 이유가 곧 이 릴리스의 사고다.** v0.2.28 이 pokes.kind 에 'message' 를 더했는데
/// 구버전 클라(≤0.2.27)는 모르는 kind 를 normal 로 접는 규약이라 3글자 메시지를 평범한 찔림으로 표시했고,
/// take_pokes 는 **서버 원자 소비**라 그 글자는 영영 사라졌다. 서버가 기본 false 로 메시지 행을 남겨 두고
/// 새 클라만 true 를 실어 가져간다 — 그래서 이 앱은 **반드시 true** 다(빼면 우리도 메시지를 못 받는다).
struct TakePokesRequest: Encodable {
    let pMessageCapable: Bool
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
    /// v0.2.34 의 **재화 잔량**(ultra_balance). ultraRemaining 과 값이 같게 오지만 의미가 다르다 —
    /// 저쪽은 "오늘 남은 횟수"라는 옛 어휘이고 이쪽은 이월되는 재화의 잔량이다(docs/ultra-economy.md §3).
    ///
    /// **반드시 Optional 이어야 한다.** 비옵셔널로 두면 이 키를 안 보내는 서버(= db push 전 창)에서
    /// 디코드가 통째로 throw 되고, 그러면 콕찌르기가 통째로 죽는다(PokeDirectoryRow.canReceiveMessage 주석의 그 사고).
    /// nil 은 "0개"가 아니라 **"모른다"** 이다.
    var ultraBalance: Int?
    /// 초인종(Realtime broadcast) 발사 결과. `"sent"` / `"failed"` / nil(= 키 없는 구버전 서버).
    /// **화면에 쓰지 않는다 — 진단용이다.** `"failed"` 는 찌르기가 실패했다는 뜻이 아니라
    /// 초인종만 삼켜졌다는 뜻이다(키스위치가 내려가 있으면 정상 진행). 이걸 실패로 읽으면
    /// v0.2.34 사용자 전원이 "찌르기 실패"를 본다 — 출시 시점의 기본값이 삼킴이기 때문이다.
    var ring: String?

    enum CodingKeys: String, CodingKey {
        case status
        case retryAfterSeconds
        case resetAfterSeconds
        case ultraRemaining
        case ultraBalance
        case ring
    }

    init(
        status: String,
        retryAfterSeconds: Int? = nil,
        resetAfterSeconds: Int? = nil,
        ultraRemaining: Int? = nil,
        ultraBalance: Int? = nil,
        ring: String? = nil
    ) {
        self.status = status
        self.retryAfterSeconds = retryAfterSeconds
        self.resetAfterSeconds = resetAfterSeconds
        self.ultraRemaining = ultraRemaining
        self.ultraBalance = ultraBalance
        self.ring = ring
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = try container.decode(String.self, forKey: .status)
        retryAfterSeconds = try container.decodeIfPresent(Int.self, forKey: .retryAfterSeconds)
        // ↓ 아래 네 줄이 이 타입의 함정 전부다. 직접 생성(PokeSendResponse(status:…)) 테스트로는
        //   커스텀 디코더의 누락을 원리적으로 못 잡으므로 JSON 을 실제로 통과시키는 테스트로 못 박는다.
        //   CodingKey 만 더하고 이 줄을 빼면 값은 **영원히 nil** 이다.
        resetAfterSeconds = try container.decodeIfPresent(Int.self, forKey: .resetAfterSeconds)
        ultraRemaining = try container.decodeIfPresent(Int.self, forKey: .ultraRemaining)
        ultraBalance = try container.decodeIfPresent(Int.self, forKey: .ultraBalance)
        ring = try container.decodeIfPresent(String.self, forKey: .ring)
    }

    /// 스토어가 `ultraRemainingToday` 에 **그대로 대입할** 값(음수 방어만 한다). 상한 클램프를 여기서 하지 않는 이유는
    /// 하루 한도(WorkTimerStore.ultraPokeDailyLimit)를 아는 쪽이 스토어이기 때문이다 — 모델이 그 상수를 알면
    /// 한도를 바꿀 때 고쳐야 할 곳이 둘로 늘어난다.
    /// nil 이면 **대입하지 마라**(모름 유지). 화면은 모를 때 아무 말도 하지 않는 쪽이 틀린 숫자보다 낫다.
    var ultraRemainingForDisplay: Int? { ultraRemaining.map { max(0, $0) } }

    /// 화면이 읽는 **잔량**. 새 키(ultraBalance)를 먼저 보고 없으면 옛 키(ultraRemaining)로 폴백한다.
    /// 폴백이 안전한 근거: 서버가 둘을 같은 값으로 실어 준다(docs/ultra-economy.md §3 — 의미만 바뀌었고
    /// 숫자는 그대로다). 둘 다 없으면 nil = **모름**이고, 모를 때 화면은 0 이 아니라 "—" 를 그린다.
    var ultraBalanceForDisplay: Int? { (ultraBalance ?? ultraRemaining).map { max(0, $0) } }
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
    /// 3글자 메시지 본문. **kind 와 정확히 같은 이유로 Optional 이고 var 다** — take_pokes 에 이 반환 컬럼을
    /// 더하는 마이그레이션이 늦게 적용된 서버는 이 키를 안 보내는데, 비옵셔널이면 [TakenPokeRow] 디코드가
    /// 통째로 throw 되어 그 사이 도착한 **모든** 찔림이(일반 찌르기까지) 조용히 소멸한다.
    /// nil 은 "빈 본문"이 아니라 "본문이 없거나 모른다"이다 — 일반/울트라 찌르기는 애초에 본문이 없어 늘 nil 로 온다.
    var body: String?
}

/// 오버레이로 전달되는 수신 찔림 한 건.
struct ReceivedPoke: Equatable {
    let id: String
    let fromName: String
    let createdAt: Date
    let kind: PokeKind
    /// 메시지 본문(kind == .message 일 때만 값이 있다). 서버가 이미 정규화·검증한 문자열이지만
    /// 표시 쪽은 이 값을 신뢰 대상이 아니라 **표시 대상**으로만 다뤄야 한다(길이 가정 금지 — 서버 상한이 바뀌면 늘어난다).
    let body: String?

    /// kind·body 기본값은 하위호환용이다 — 이 인자들을 모르는 기존 호출부가 그대로 컴파일된다.
    init(id: String, fromName: String, createdAt: Date, kind: PokeKind = .normal, body: String? = nil) {
        self.id = id
        self.fromName = fromName
        self.createdAt = createdAt
        self.kind = kind
        self.body = body
    }
}

// MARK: - 울트라 재화 지갑 / 미션 (v0.2.34 계약 타입)
//
// 정본은 docs/ultra-economy.md 다. 여기 타입은 그 문서의 응답 스키마를 **그대로** 옮긴 것이고,
// 문서에 없는 키에 의존하지 않는다(ring 페이로드의 `id` 처럼 계약이 아닌 키가 실제로 있다).
//
// 경제 규칙의 단일 출처는 **서버**다. 하루 밑바닥(1 또는 2)도 잔량 상한(5)도 클라에 상수로 두지 않는다 —
// 밑바닥은 서버가 profiles.app_build 로 갈라 주고(구버전 유예), 상한은 응답의 balanceCap 이 말한다.
// 이 규칙을 클라가 한 벌 더 갖는 순간 서버가 값을 바꿔도 화면만 옛 숫자를 말한다(v0.2.33 의
// ultraPokeDailyLimit 이 정확히 그 실패였다 — 그래서 이번에 통째로 지웠다).

/// `ultra_wallet_sync(p_days_back int default 1) → jsonb` 응답.
///
/// **status 를 먼저 읽고 분기하는 디코더다.** `status == "invalid"`(비로그인·프로필 없음)이면
/// 서버는 status 외의 키를 **하나도 보내지 않는다**. 그걸 모르고 balance 를 decode 하면 통째로 throw 되고,
/// 스토어는 '서버 오류'로 오진해 "못 읽었어요"를 띄운다 — 실제 원인은 '로그인이 안 됐다'인데.
struct UltraWalletResponse: Decodable, Equatable, Sendable {
    /// `"ok"` | `"invalid"`. 미지 값은 invalid 와 같게 취급된다(isOK 가 == "ok" 로만 참이다).
    let status: String
    /// 이 호출 **직후**의 잔량(밑바닥 보정·미션 적립이 이미 반영된 값).
    let balance: Int
    /// 잔량 상한. **nil = 서버가 말해 주지 않았다.** UI 는 리터럴 5 를 박지 말고 이 값을 읽는다.
    let balanceCap: Int?
    /// 이 사용자가 **잔량 제한을 받지 않는가**(관리자). 서버 `ultra_wallet_sync` 의 `unlimited` 키다.
    ///
    /// **반드시 Optional 이다.** 이 키를 모르는 서버(20260820040000 이전)가 실재하고, 비옵셔널로 받으면
    /// 그 서버의 응답에서 디코드가 **통째로 throw** 되어 지갑 동기화가 죽는다 — 잔량도 미션도 스트릭도
    /// 함께 사라진다. 곁가지 하나 때문에 본체가 죽는 그 실패가 이 타입이 balanceCap 이하를 전부
    /// `decodeIfPresent` 로 읽는 이유이고, 이 필드도 같은 규약을 따른다.
    ///
    /// **`nil` 은 "모른다"이고, 모를 때의 해석은 "무제한이 아니다"** 다(= 숫자를 그린다).
    /// 반대로 접으면 구버전 서버에 붙은 모든 사용자의 화면이 "무제한"이라고 거짓말한다.
    /// 그 해석은 `isUnlimited` 한 곳에만 둔다 — 뷰가 `unlimited == true` 를 각자 쓰면 언젠가
    /// `?? true` 를 쓰는 자리가 생긴다.
    ///
    /// **클라가 role 을 추측해 만들지 않는다.** 같은 판정(profiles.role = 'admin')을 서버 두 곳
    /// (ultra_poke_user · ultra_wallet_sync)이 이미 쓰고 있고, 클라가 한 벌 더 가지면 위조와 불일치가
    /// 동시에 가능해진다("화면은 무제한인데 서버는 잔량을 태운다").
    let unlimited: Bool?
    /// 이 사용자의 하루 밑바닥(1 또는 2). 진단용 — 구버전 유예가 실제로 걸렸는지 여기서 보인다.
    let dailyFloor: Int?
    /// `YYYY-MM-DD` (KST). 서버가 판정한 '오늘'.
    let day: String
    /// 이번 호출에서 밑바닥 보정이 **실제로 잔량을 올렸는가**.
    let floorApplied: Bool
    /// 최신 날짜 우선. 기본 p_days_back=1 이면 오늘과 어제 두 행이 온다.
    let missions: [MissionRow]
    let workedSecondsClosed: Int
    let workedSecondsOpen: Int
    /// 연속 출근 일수. **표시 전용 — 보상 없음**(사장님 확정 3).
    let streakDays: Int
    let streakIncludesToday: Bool
    /// 서버 측정 시각(epoch 초).
    let measuredAt: Int

    var isOK: Bool { status == "ok" }

    /// 무제한인가. **`nil`(모름)은 무제한이 아니다** — 이 한 줄이 그 해석의 유일한 자리다.
    var isUnlimited: Bool { unlimited == true }

    /// 오늘 서버가 잰 누적 근무초(닫힌 + 열린). 미션 진행 바가 아니라 진단 줄이 읽는다.
    var workedSecondsToday: Int { workedSecondsClosed + workedSecondsOpen }

    /// `missions[]` 원소. 모르는 `key` 는 **무시**한다(서버가 미션을 늘려도 옛 앱이 안 깨지게).
    struct MissionRow: Decodable, Equatable, Sendable {
        let key: String
        /// `YYYY-MM-DD`. 이 행이 평가한 날. 오늘 행과 어제 행을 가르는 유일한 근거다.
        let kstDay: String
        let targetSeconds: Int
        let progressSeconds: Int
        /// 그날 몫을 **이미 받았다**.
        let claimed: Bool
        /// **이번 호출에서** 받았다 → 연출(`.ultraCharged`)의 유일한 트리거.
        let grantedNow: Bool
        /// 달성했지만 **잔량이 가득 차서 적립하지 않았다**. 이때 `claimed` 는 **false 로 남는다**
        /// (서버가 장부를 안 쓰기 때문 — docs/ultra-economy.md §2). 그래서 claimed 만 보면
        /// "아직 못 받았다"로 보이고 화면은 진행 바를 100% 로 그린 채 아무 말도 안 하게 된다.
        let capped: Bool

        enum CodingKeys: String, CodingKey {
            case key, kstDay, targetSeconds, progressSeconds, claimed, grantedNow, capped
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            key = try c.decode(String.self, forKey: .key)
            kstDay = try c.decode(String.self, forKey: .kstDay)
            targetSeconds = try c.decode(Int.self, forKey: .targetSeconds)
            progressSeconds = try c.decode(Int.self, forKey: .progressSeconds)
            claimed = try c.decode(Bool.self, forKey: .claimed)
            grantedNow = try c.decode(Bool.self, forKey: .grantedNow)
            // capped 만 관대한 이유: 이 키는 상한(사장님 확정 4)과 함께 태어난 신참이라,
            // 서버가 한 단계 뒤처진 창에서 없을 수 있다. 없으면 '가득 차지 않았다'가 안전한 쪽이다.
            capped = try c.decodeIfPresent(Bool.self, forKey: .capped) ?? false
        }

        init(
            key: String,
            kstDay: String,
            targetSeconds: Int,
            progressSeconds: Int,
            claimed: Bool,
            grantedNow: Bool,
            capped: Bool = false
        ) {
            self.key = key
            self.kstDay = kstDay
            self.targetSeconds = targetSeconds
            self.progressSeconds = progressSeconds
            self.claimed = claimed
            self.grantedNow = grantedNow
            self.capped = capped
        }
    }

    enum CodingKeys: String, CodingKey {
        case status, balance, balanceCap, dailyFloor, day, floorApplied, missions
        case workedSecondsClosed, workedSecondsOpen, streakDays, streakIncludesToday, measuredAt
        case unlimited
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = try c.decode(String.self, forKey: .status)
        guard status == "ok" else {
            // ★ 여기서 바로 끝낸다. 아래 decode 를 한 줄이라도 시도하면 invalid 응답이 throw 로 변한다.
            balance = 0
            balanceCap = nil
            unlimited = nil
            dailyFloor = nil
            day = ""
            floorApplied = false
            missions = []
            workedSecondsClosed = 0
            workedSecondsOpen = 0
            streakDays = 0
            streakIncludesToday = false
            measuredAt = 0
            return
        }
        balance = try c.decode(Int.self, forKey: .balance)
        day = try c.decode(String.self, forKey: .day)
        // 아래는 전부 관대하게 읽는다. 근거: 이 응답의 **본체는 잔량과 미션**이고, 진단용 곁가지
        // (스트릭·측정초·밑바닥) 하나가 빠졌다고 잔량 표시가 통째로 "못 읽었어요"가 되면 안 된다.
        // 반대로 balance/day 를 관대하게 읽으면 서버 결함이 화면에서 '잔량 0' 이라는 **거짓말**로 나타난다.
        balanceCap = try c.decodeIfPresent(Int.self, forKey: .balanceCap)
        // ★ decodeIfPresent 다. 이 키를 모르는 서버가 실재하고, 거기서 throw 하면 잔량·미션·스트릭이
        //   한꺼번에 사라진다(위 필드 주석의 그 실패). 없으면 nil = "모른다" = 무제한 아님.
        unlimited = try c.decodeIfPresent(Bool.self, forKey: .unlimited)
        dailyFloor = try c.decodeIfPresent(Int.self, forKey: .dailyFloor)
        floorApplied = try c.decodeIfPresent(Bool.self, forKey: .floorApplied) ?? false
        missions = try c.decodeIfPresent([MissionRow].self, forKey: .missions) ?? []
        workedSecondsClosed = try c.decodeIfPresent(Int.self, forKey: .workedSecondsClosed) ?? 0
        workedSecondsOpen = try c.decodeIfPresent(Int.self, forKey: .workedSecondsOpen) ?? 0
        streakDays = try c.decodeIfPresent(Int.self, forKey: .streakDays) ?? 0
        streakIncludesToday = try c.decodeIfPresent(Bool.self, forKey: .streakIncludesToday) ?? false
        measuredAt = try c.decodeIfPresent(Int.self, forKey: .measuredAt) ?? 0
    }

    init(
        status: String,
        balance: Int = 0,
        balanceCap: Int? = nil,
        dailyFloor: Int? = nil,
        day: String = "",
        floorApplied: Bool = false,
        missions: [MissionRow] = [],
        workedSecondsClosed: Int = 0,
        workedSecondsOpen: Int = 0,
        streakDays: Int = 0,
        streakIncludesToday: Bool = false,
        measuredAt: Int = 0,
        // 맨 뒤인 이유는 순전히 소스 호환이다 — 중간에 끼우면 인자를 순서대로 넘기던 기존 호출부가
        // 전부 컴파일 오류가 난다. 기본값 nil = "서버가 말 안 해 줬다" = 무제한 아님.
        unlimited: Bool? = nil
    ) {
        self.status = status
        self.balance = balance
        self.balanceCap = balanceCap
        self.dailyFloor = dailyFloor
        self.day = day
        self.floorApplied = floorApplied
        self.missions = missions
        self.workedSecondsClosed = workedSecondsClosed
        self.workedSecondsOpen = workedSecondsOpen
        self.streakDays = streakDays
        self.streakIncludesToday = streakIncludesToday
        self.measuredAt = measuredAt
        self.unlimited = unlimited
    }
}

/// 미션 목록 한 줄의 **표시용** 값. 서버 응답(UltraWalletResponse)에서 순수 변환으로 만들고,
/// 화면은 이 타입만 읽는다 — 뷰가 서버 스키마를 직접 읽으면 키 하나 바뀔 때 고칠 곳이 뷰까지 번진다.
struct MissionProgress: Identifiable, Equatable, Sendable {
    /// rawValue 는 **서버의 `missions[].key` 와 문자 그대로 같다**(work3h). 서버 키가 없는 줄
    /// (dailyFloor / arrivalStreak)은 클라가 응답의 다른 필드로 만들어 내는 표시 전용 행이다.
    enum Kind: String, CaseIterable, Sendable {
        case todayThreeHours = "work3h"
        case dailyFloor
        case arrivalStreak
    }

    /// 미션 1호 목표의 **폴백**(3시간). 서버가 그 행을 안 줬을 때만 쓴다 — 판정의 출처가 아니다.
    /// 서버 `mission_work_seconds()` 와 같은 값이지만, 어긋나도 손해는 진행 바가 잠깐 틀리는 것뿐이고
    /// 다음 sync 가 진짜 목표로 교정한다(적립 여부는 언제나 서버가 정한다).
    static let defaultTargetSeconds = 3 * 3_600

    var id: String { kind.rawValue }
    let kind: Kind
    /// 0…1. **진행 개념이 없는 줄은 nil** 이고 그때 화면은 바를 그리지 않는다.
    let progress: Double?
    /// 오늘 몫을 이미 받았다(또는 오늘 이미 적용됐다).
    let claimedToday: Bool
    /// 달성했지만 **잔량이 가득 차서 못 받았다**(사장님 확정 4). claimedToday 와 **동시에 참일 수 없다** —
    /// 서버가 상한에서는 장부를 안 쓰기 때문이다. 화면은 이 줄에 "가득 차서 오늘은 못 받아요"를 그린다.
    let cappedToday: Bool
    /// 그 줄의 오른쪽 보조 문장(진행 시간·연속 일수 등). 문장은 여기서 한 번만 만든다.
    let detail: String

    /// 서버 응답 → 미션 목록. **순수 함수라 테스트가 이 한 함수로 화면 전체의 규칙을 고정한다.**
    ///
    /// 순서가 곧 화면 순서다: 오늘 3시간(유일한 실제 보상) → 매일 밑바닥 → 연속 출근(표시만).
    /// **모르는 key 는 무시한다** — 서버가 미션을 늘려도 옛 앱이 빈 줄을 그리지 않는다.
    static func rows(from response: UltraWalletResponse) -> [MissionProgress] {
        guard response.isOK else { return [] }
        // 오늘 행만 본다. 어제 행(p_days_back=1 이 함께 주는 소급분)은 **적립을 위해** 존재하는 것이고
        // 화면의 '오늘 미션'이 아니다 — 섞으면 어제 이미 받은 몫 때문에 오늘 줄이 완료로 보인다.
        let today = response.missions.first { $0.key == Kind.todayThreeHours.rawValue && $0.kstDay == response.day }
        var rows: [MissionProgress] = []

        // 목표는 **오늘 행 → 다른 날 행 → 폴백** 순으로 찾는다. 오늘 행이 없을 때(서버가 아직 그날을
        // 평가하지 않았거나 근무가 0초인 아침) 목표를 0 으로 두면 진행률이 0/0 이 되어 바가 100% 로 튄다 —
        // 아무것도 안 했는데 "다 했다"고 그리는 것이라 가장 나쁜 종류의 거짓말이다(실측: 첫 판이 그랬다).
        let target = max(
            1,
            today?.targetSeconds
                ?? response.missions.first { $0.key == Kind.todayThreeHours.rawValue }?.targetSeconds
                ?? defaultTargetSeconds
        )
        let done = today?.progressSeconds ?? response.workedSecondsToday
        rows.append(
            MissionProgress(
                kind: .todayThreeHours,
                progress: min(1, Double(done) / Double(target)),
                claimedToday: today?.claimed ?? false,
                cappedToday: today?.capped ?? false,
                detail: "\(hoursText(done)) / \(hoursText(target))"
            )
        )

        rows.append(
            MissionProgress(
                kind: .dailyFloor,
                progress: nil,
                // '오늘 보정이 실제로 일어났다'가 이 줄의 완료 조건이다. 밑바닥은 적립이 아니라 보정이라
                // (잔량 3인 사람은 보정이 안 걸린다) floorApplied 가 false 여도 정상이다.
                claimedToday: response.floorApplied,
                cappedToday: false,
                detail: response.dailyFloor.map { "매일 \($0)개까지" } ?? "매일 자동 충전"
            )
        )

        rows.append(
            MissionProgress(
                kind: .arrivalStreak,
                progress: nil,
                claimedToday: response.streakIncludesToday,
                cappedToday: false,
                detail: "\(response.streakDays)일 연속"
            )
        )
        return rows
    }

    /// 초 → "3시간" / "2시간 30분" / "45분". 미션 줄의 보조 문장 전용이라 여기 둔다.
    static func hoursText(_ seconds: Int) -> String {
        let total = max(0, seconds) / 60
        let hours = total / 60
        let minutes = total % 60
        if hours == 0 { return "\(minutes)분" }
        if minutes == 0 { return "\(hours)시간" }
        return "\(hours)시간 \(minutes)분"
    }
}

/// `drainReceivedPokes()` 의 결과. **Void 였던 것을 이 타입으로 바꾼 이유는 캐치업이다** —
/// 리얼타임 구독 직후의 따라잡기는 "실패했으면 다시"가 필요한데, 예전 함수는 오류를 안에서 삼키고
/// Void 를 돌려줘 호출부가 성공/실패를 원리적으로 알 수 없었다(WorkTimerStorePoke.swift 의 그 catch 주석).
///
/// 기존 호출부 2곳(폴링 tick·근무 종료 꼬리 회수)은 결과를 **무시**한다 — @discardableResult 라 동작 변화가 0이다.
enum DrainOutcome: Equatable, Sendable {
    /// take_pokes 가 실제로 돌았다. `count` 는 **소비된 행 전체 수**(찔림 + 메시지)로, 초인종 페이로드의
    /// `pending` 과 견주면 소비 경로가 새는지 보인다. 0 도 성공이다(가져올 게 없었을 뿐).
    case ok(count: Int)
    /// 요청이 실패했거나(네트워크·인증) 세션이 없어 아예 못 보냈다. 문자열은 **진단용**이고 화면에 쓰지 않는다.
    /// 세션 없음도 여기로 온다 — 캐치업이 재시도해 봐야 성공할 수 없는 상태라 '성공'으로 접으면
    /// 따라잡기 실패가 조용히 감춰진다.
    case failed(String)

    var isOK: Bool { if case .ok = self { return true }; return false }
}

// MARK: - 3글자 메시지 (계약 타입)

/// send_message RPC 요청. { p_to: 대상 user id, p_body: 보낼 본문 }.
/// PokeSendRequest 를 재사용하지 못하는 이유는 인자가 하나 더 있다는 것뿐이다 — **응답 규약은 그대로 공유한다**
/// (아래 sendMessage 주석 참고).
struct SendMessageRequest: Encodable {
    let pTo: String
    let pBody: String
}

/// 보내기 전 클라 판정 결과. status 어휘를 서버와 맞춘 이유는 하나다 — 같은 실패를 두 어휘로 부르면
/// 화면 문구가 두 벌이 되고, 그중 한 벌은 반드시 낡는다.
enum MessageBodyValidation: Equatable {
    /// 실제로 보낼 문자열(정규화 완료). 원문이 아니라 **이 값**을 서버로 보내야 한다.
    case ok(String)
    case empty
    /// 글자·숫자·허용 문장부호가 아닌 것이 섞였다(이모지·기호·개행·탭·제어문자).
    /// **`.empty`/`.tooLong` 에 접지 않고 케이스를 나눈 이유**: 화면이 "왜 안 되는지"를 말할 수 있어야 한다.
    /// "3글자까지예요"를 이모지 하나에 대고 띄우면 사용자는 글자 수를 줄이려 들고, 줄여도 계속 거부당한다.
    case unsupportedCharacters
    case tooLong(maxCharacters: Int)
}

/// 3글자 메시지 본문의 정규화·글자수 판정. **모델에 둔 이유**: 입력 카운터(UI)·전송 게이트(스토어)·
/// 네트워크 계층이 같은 답을 내야 하는데, 세 곳이 각자 세면 "3/3 인데 전송이 거부되는" 화면이 만들어진다.
/// 판정의 최종 권위는 서버이고 여기 있는 것은 헛왕복을 줄이는 사전 게이트다(무료 플랜).
enum MessageBody {
    /// 사용자가 세는 글자 수 기준 상한. 서버 too_long 판정과 **같은 값이어야 한다**.
    static let maxCharacters = 3

    /// 공백 + 허용 ASCII 문장부호 20자. **서버(20260814015000)가 확정한 집합과 1:1이다** — 이 목록이 서버보다
    /// 좁으면 사용자가 서버는 받아 줄 `^^` 를 못 치고, 넓으면 클라를 통과한 글자가 서버에서 not_text 로 거부된다.
    /// 어느 쪽이든 "화면에선 쳐지는데 안 나가는" 증상이라, 두 집합은 갈리는 순간이 곧 버그다.
    ///
    /// **카테고리 판정으로는 이 집합을 만들 수 없다**(실측): `~` 는 구두점이 아니라 수학기호(Sm), `^` 는
    /// 수식기호(Sk)라 "Symbol 거부" 규칙에 걸린다. 그래서 명시 목록이어야 한다.
    ///
    /// 빠진 12자는 `< > & \ $ % ` { } [ ] |` — 마크업·이스케이프·템플릿 의미가 있는 것만 골라 뺐다.
    /// 반대로 `^^`(웃음)·`-_-`·`:)`·`...` 는 3글자 짧은 말에서 실제로 쓰이는 표현이라 **일부러 살렸다**.
    static let allowedPunctuation: Set<Unicode.Scalar> = [
        " ", "!", "\"", "#", "'", "(", ")", "*", "+", ",", "-", ".", "/",
        ":", ";", "=", "?", "@", "^", "_", "~"
    ]

    /// 사용자 입력 → 실제로 보낼 문자열. 두 단계뿐이다:
    /// 1) NFC 정규화. macOS 한글 입력기·파인더에서 붙여넣은 글자는 자모 분해(NFD)로 들어온다. Swift 는 이걸
    ///    2글자로 세지만 Postgres char_length 는 6으로 세서, **클라가 통과시킨 "한글"이 서버에서 거부된다**
    ///    (실측: NFD "한글" = count 2 / scalars 6, NFC 후 = count 2 / scalars 2).
    /// 2) 앞뒤 공백·개행 trim. 붙여넣기에 딸려 온 여백으로 거부하면 불친절하다. 반면 **가운데** 개행·탭은
    ///    지우지 않는다 — 지우면 "가\n나"가 조용히 "가나"로 바뀌어 사용자가 안 쓴 말이 나간다. 거부가 맞다.
    ///
    /// 예전에 여기 있던 제어문자·ZWJ·방향오버라이드 필터는 **통째로 지웠다**. 텍스트 전용 게이트(isTextOnly)가
    /// 허용 목록으로 판정하면서, 그 문자들은 "지워야 할 것"이 아니라 "애초에 통과 못 하는 것"이 됐기 때문이다.
    /// 지우는 방식이 필요했던 이유(ZWJ 를 지우면 이모지가 쪼개진다)도 이모지를 안 받는 순간 함께 사라졌다.
    static func sanitized(_ raw: String) -> String {
        raw.precomposedStringWithCanonicalMapping.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 텍스트 전용 게이트. **서버(20260814015000)의 허용 집합과 1:1인 코드포인트 범위**로 판정한다.
    ///
    /// **일반 카테고리(otherLetter 등)로 열면 안 된다** — 그러면 한자(中)·가나(あ)·전각(Ａ)·태국어까지
    /// 통과해서 클라가 서버보다 넓어지고, 사용자는 화면에선 멀쩡히 쳐지는 글자가 전송에서만 거부되는
    /// (서버 not_text) 경험을 한다. 좁아도 같은 크기의 버그다(서버는 받아 줄 `^^` 를 못 침). 그래서 범위를 못 박는다.
    ///
    /// **이 게이트가 이모지를 막는 것은 부작용이 아니라 목적이다.** 이모지를 받으면 Swift 의 자소 수와
    /// Postgres 의 코드포인트 수가 갈리고(👨‍👩‍👧‍👦 = 1자소 / 7코드포인트), 그 간극은 "되는 이모지와 안 되는
    /// 이모지"라는 설명 불가능한 증상으로 나타난다. 이 집합만 받으면 두 수가 **항상 일치**한다(실측).
    ///
    /// 자소가 아니라 **유니코드 스칼라 단위**로 검사한다: 이모지는 여러 스칼라의 조합이라 자소 단위로 보면
    /// 그 안에 섞인 기호·ZWJ 를 못 본다.
    static func isTextOnly(_ text: String) -> Bool {
        text.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            // 한글 음절 가~힣. 조합 자모(U+1100~)는 여기 없지만, sanitized 의 NFC 합성이 정상 입력을 이 범위로
            // 옮겨 놓는다(옛한글처럼 합성되지 않는 것은 서버와 똑같이 거부된다).
            case 0xAC00...0xD7A3: return true
            // 한글 호환 자모 ㄱ~ㅣ. ★ 상한이 U+3163 인 것이 핵심이다 — 바로 다음 U+3164(한글 채움)는
            //   **폭 0인데 글자 취급**이라, 열어 두면 빈 말풍선을 3개까지 보낼 수 있다. 같은 이유로 옛한글
            //   조합 자모(U+115F 초성 채움·U+1160 중성 채움 포함)도 통째로 밖이다.
            //   이 저장소는 바로 그 문자들로 **별명 사칭에 실제로 뚫린 적이 있다**
            //   (20260804010000_display_name_change.sql:54-57 이 그 사고의 기록이다).
            case 0x3131...0x3163: return true
            // A-Z / a-z / 0-9. **아라비아-인도 숫자(٣ U+0663)는 여기 없다** — 카테고리로 열면 그것도
            //   '숫자'라 통과하는데 서버는 거부한다.
            case 0x41...0x5A, 0x61...0x7A, 0x30...0x39: return true
            default: return allowedPunctuation.contains(scalar)
            }
        }
    }

    /// 사용자가 세는 글자 수(정규화 후). Character = 확장 자소 클러스터 단위라 이모지 가족·국기·스킨톤·결합 문자를
    /// 전부 1로 센다(실측: 👨‍👩‍👧‍👦 = 1, 🇰🇷 = 1, 👍🏻 = 1). utf16/유니코드 스칼라로 세면 같은 것들이 2~11로 세어져
    /// 사용자가 이모지 하나를 못 보낸다. 입력 카운터("N/3")도 이 값을 써야 화면과 게이트가 어긋나지 않는다.
    static func characterCount(_ raw: String) -> Int { sanitized(raw).count }

    /// **검사 순서가 문구를 정한다.** "👍👍👍👍" 는 길이도 문자도 둘 다 위반인데, 여기서 길이를 먼저 보면
    /// 화면이 "3글자까지예요"라고 말하고 사용자는 이모지를 세 개로 줄인 뒤 또 거부당한다. 문자 검사가 먼저다.
    static func validate(_ raw: String) -> MessageBodyValidation {
        let normalized = sanitized(raw)
        if normalized.isEmpty { return .empty }
        if !isTextOnly(normalized) { return .unsupportedCharacters }
        if normalized.count > maxCharacters { return .tooLong(maxCharacters: maxCharacters) }
        return .ok(normalized)
    }
}

/// 메시지 전송 결과의 도메인 표현(스토어/UI 공유). 미지 status 가 .invalid 로 접히는 규약은 PokeSendOutcome 과 같다.
///
/// **PokeSendOutcome 에 케이스를 더하지 않고 따로 만든 이유**: 두 RPC 의 status 어휘가 양방향으로 갈린다 —
/// send_message 에만 too_long 이 있고, poke 에만 target_not_working·ultra_used_today 가 있다. 하나로 합치면
/// 메시지 처리부는 절대 오지 않을 두 케이스를, 찌르기 처리부는 절대 오지 않을 too_long 을 각각 떠안는다.
/// 이미 sendPoke 경로에 도달 불가 ultraUsedToday 분기가 하나 있고(WorkTimerStorePoke), 그건 본받을 전례가 아니라
/// 갚아야 할 빚이다. 반대로 **전선 위 응답(PokeSendResponse)은 공유한다** — jsonb 규약이 {status, retry_after_seconds?}로
/// 문자 그대로 같아서, DTO 를 복제하면 커스텀 디코더의 함정(옵셔널 키 누락)만 두 벌로 늘어난다.
enum MessageSendOutcome: Equatable {
    case ok
    // ↓ 아래 거절 케이스들은 **서버 게이트가 판정하는 순서대로** 늘어놓았다. 세 함수(poke_user·ultra_poke_user·
    //   send_message)가 같은 순서를 공유하므로, 이 목록과 SQL 을 나란히 놓고 대조할 수 있게 유지해라.
    //   invalid → not_working(보낸이) → 본문검증 → target_not_working(대상) → target_focused →
    //   target_outdated → cooldown
    //   (target_outdated 의 정확한 자리는 SQL 이 확정한다. 쿨타임보다 **앞**이라는 것만이 계약이다 —
    //    받을 수 없는 사람에게 보낸 실패가 60초를 태우면 그건 벌이다.)
    case invalid
    /// 보낸이가 근무중이 아니다.
    case notWorking
    /// 3글자를 넘었다. 서버 판정과 **클라 사전 게이트(MessageBody.validate)** 가 같은 이 status 를 쓴다.
    case tooLong
    /// 대상이 자리비움이다(v0.2.20 에서 빠졌다가 복원된 게이트). **`.invalid` 로 접으면 안 되는 이유**는
    /// 빈도다 — 자리 비운 사람은 흔해서, 두루뭉술한 "지금은 보낼 수 없어요"를 가장 자주 보게 되는 경로가 이것이다.
    /// 화면은 이걸 받으면 디렉토리의 근무중 배지가 낡았다는 뜻으로 읽고 재조회하는 편이 좋다(sendPoke 와 같은 규약).
    case targetNotWorking
    /// 대상이 집중 모드다. 쿨타임도 소모되지 않는다 — 서버가 행을 안 남긴다.
    case targetFocused
    /// 대상의 앱이 메시지를 표시하지 못하는 버전이다(서버가 profiles.app_build 로 판정한다).
    /// **`.invalid` 로 접으면 안 되는 이유**는 targetNotWorking 과 같지만 더 무겁다 — 사용자가 할 수 있는
    /// 일이 "기다리기"가 아니라 **"상대에게 업데이트를 알리기"** 라, 두루뭉술한 문구는 그 행동을 통째로 지운다.
    /// 쿨타임도 소모되지 않는다(서버가 행을 안 남긴다).
    case targetOutdated
    case cooldown(retryAfterSeconds: Int)

    init(response: PokeSendResponse) {
        switch response.status {
        case "ok":                  self = .ok
        case "not_working":         self = .notWorking
        case "too_long":            self = .tooLong
        case "target_not_working":  self = .targetNotWorking
        case "target_focused":      self = .targetFocused
        case "target_outdated":     self = .targetOutdated
        case "cooldown":            self = .cooldown(retryAfterSeconds: max(1, response.retryAfterSeconds ?? 60))
        default:                    self = .invalid
        }
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

/// 이 맥이 돌고 있는 앱 버전. 서버가 **남이 나에게 메시지를 보낼 수 있는지**를 이 값으로 판정하므로
/// (send_message 의 target_outdated), 이건 통계가 아니라 기능의 일부다.
///
/// build 가 정수인 것이 요점이다 — 판정은 크기 비교(app_build >= 37)이고, "0.2.29" 같은 문자열은
/// 사전순 비교가 버전 순서와 어긋난다("0.2.9" > "0.2.29"). version 은 사람이 읽는 표시용이다.
struct AppVersionReport: Equatable {
    /// CFBundleVersion(정수). scripts/build-local.sh 가 빌드 때 심는다.
    let build: Int
    /// CFBundleShortVersionString("0.2.29").
    let version: String

    /// Info.plist 딕셔너리 → 보고값. **Bundle 을 인자로 받지 않고 딕셔너리를 받는 이유**는 테스트다 —
    /// Bundle.main 은 프로세스마다 다르고(테스트 러너에는 이 키가 아예 없을 수 있다) 주입할 수도 없어서,
    /// 순수 함수로 갈라 두지 않으면 파싱 규칙을 실증할 방법이 없다.
    ///
    /// **못 읽으면 nil 이고, nil 이면 아무것도 보내지 않는다.** 개발 빌드에는 이 키가 없거나 이상한 값이
    /// 들어 있는데, 그때 0 이나 폴백 숫자를 올리면 서버가 나를 **구버전으로 보고** 남이 나에게 메시지를
    /// 못 보내게 만든다 — 모르면 침묵하는 쪽이 틀린 숫자를 쓰는 쪽보다 언제나 낫다.
    /// (CheckUpdateCheck.bundleShortVersion 의 "0.0.0" 폴백과 방향이 반대인 이유가 이것이다: 저건
    ///  '업데이트 배너를 안 띄운다'로 수렴하지만, 여기서 폴백은 '남의 기능을 막는다'로 수렴한다.)
    static func fromInfoDictionary(_ info: [String: Any]?) -> AppVersionReport? {
        guard let info else { return nil }
        // CFBundleVersion 은 plist 상 문자열이지만, 손으로 만든 plist 나 도구에 따라 숫자로 들어오기도 한다.
        // 두 모양 다 받는다 — 못 읽는 것과 모양이 다른 것은 다른 사정이다.
        let rawBuild: Int?
        switch info["CFBundleVersion"] {
        case let text as String: rawBuild = Int(text.trimmingCharacters(in: .whitespaces))
        case let number as Int:  rawBuild = number
        case let number as NSNumber: rawBuild = number.intValue
        default: rawBuild = nil
        }
        // 0·음수는 '심지 않은 값'이다. 그대로 올리면 위 문단의 사고가 그대로 난다.
        guard let build = rawBuild, build > 0 else { return nil }
        let version = (info["CFBundleShortVersionString"] as? String)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        // 표시 문자열이 비어도 **보고는 한다** — 게이트를 여는 것은 build 하나이고, 그걸 아는데
        // 침묵하면 멀쩡한 앱이 구버전 취급을 받는다.
        return AppVersionReport(build: build, version: version)
    }
}

/// profiles.app_build / app_version 자기 행 갱신 요청(PATCH).
/// **두 컬럼을 한 요청에 싣는다** — 집중 모드를 따로 보낸 이유(권한이 한쪽에만 있는 서버)가 여기엔 없다:
/// 두 컬럼은 같은 마이그레이션이 함께 만들고 함께 grant 하므로 한쪽만 쓸 수 있는 서버가 존재하지 않는다.
/// 나누면 같은 사실을 알리는 데 왕복이 두 배가 될 뿐이다(무료 플랜).
struct ProfileAppVersionUpdateRequest: Encodable {
    let appBuild: Int
    let appVersion: String
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

// MARK: - 자리 비움 자동 마감 (v0.2.35 / docs/away-close.md)

/// 자동 마감 사유. **서버 check 제약(work_sessions_auto_closed_reason_check)과 같은 어휘다** —
/// 다른 값을 보내면 PATCH 가 23514 로 거절돼 마감이 통째로 서버에 도달하지 못한다(= 세션이 영영 안 닫힌다).
/// 복원 대상은 `away`/`sleep` 둘뿐이고, 그 판정은 서버가 한다(restore_auto_closed_session 의 사유 게이트).
// Codable 은 pendingItems 영속(v0.2.36) 때문이다 — rawValue(서버 어휘) 그대로 디스크에 남는다.
enum AutoCloseReason: String, Equatable, Sendable, Codable {
    case away
    case sleep
    case longSession = "long_session"
    case abandoned

    /// 서버 복원 RPC 가 받아 주는 사유인가. 클라의 화면 판단용 거울일 뿐이고 최종 판정자는 서버다.
    var isRestorable: Bool { self == .away || self == .sleep }
}

/// `away_sync()` 응답 원문. 타임스탬프는 **문자열로 받아** 서비스의 parseDate(소수초 유무 양쪽)로 해석한다 —
/// 이 저장소의 다른 응답 행(WorkSessionRow/WorkStatusRow)과 같은 규약이다.
///
/// 모든 필드가 옵셔널인 이유는 하나다: **모르는 값이 있으면 마감하지 않는 것이 안전한 실패**이고,
/// non-optional 로 두면 서버가 키 하나를 빼는 순간 디코드가 통째로 throw 되어 복원 배너까지 함께 죽는다.
/// (브루 배포라 앱이 db push 보다 먼저 나가는 창이 실재한다.)
struct AwaySyncResponse: Decodable, Equatable, Sendable {
    let status: String?
    let serverNow: String?
    let closeThresholdSeconds: Int?
    let backstopSeconds: Int?
    let freezeSeconds: Int?
    let restoreWindowSeconds: Int?
    let dailyRestoreLimit: Int?
    let restorableReasons: [String]?
    let restoresUsedToday: Int?
    let restoresLeftToday: Int?
    let openSession: OpenSessionPayload?
    let restorable: RestorablePayload?

    struct OpenSessionPayload: Decodable, Equatable, Sendable {
        let id: String?
        let teamId: String?
        let startedAt: String?
        let lastInputAt: String?
        /// **nil 은 false 로 읽는다**(모르면 마감하지 않는다). 서버와 클라가 같은 함수
        /// (away_input_observable)의 결과를 보게 하는 유일한 통로다.
        let closeEligible: Bool?
        let closeDueAt: String?
    }

    struct RestorablePayload: Decodable, Equatable, Sendable {
        let sessionId: String?
        let teamId: String?
        let startedAt: String?
        let endedAt: String?
        let durationSeconds: Int?
        let autoClosedAt: String?
        let autoClosedReason: String?
        let expiresAt: String?
        let remainingSeconds: Int?
    }
}

/// 서버가 소유하는 자리 비움 정책. **클라에 임계 리터럴을 두지 않는다**(사장님 확정 사항) —
/// 계측 후 SQL 한 줄로 값이 바뀌는데 브루 지연으로 절반이 옛 값을 쓰면 안 되기 때문이다.
/// 이 값이 nil 이면(=서버가 안 줬다) 클라는 **마감하지 않는다**.
struct AwayPolicy: Equatable, Sendable {
    /// 클라 마감 임계(초). 서버 백스톱은 여기에 유예(freeze)를 더한 시점에 발화한다.
    let closeThresholdSeconds: TimeInterval
    let restoreWindowSeconds: TimeInterval?
    let dailyRestoreLimit: Int?
    let restoresLeftToday: Int?
    /// 서버가 잰 '지금'. 시계 어긋남 진단용(판정에는 쓰지 않는다 — 로컬 시계로 판정해야 오프라인에서도 일관된다).
    let serverNow: Date?
}

/// 서버가 본 내 열린 세션. 판정의 두 재료(lastInputAt, closeEligible)가 여기서 온다.
struct AwayOpenSession: Equatable, Sendable {
    let sessionID: String
    let startedAt: Date?
    /// greatest(work_statuses.last_input_at, max(work_status_devices.last_input_at)) — 서버가 계산한 max.
    /// 클라는 여기에 **로컬 관측을 한 번 더 max** 한다(내 맥의 입력이 아직 서버에 안 올라간 창을 메운다).
    let lastInputAt: Date?
    /// 이 사용자의 무입력을 관측할 수 있는가. 거짓이면 클라는 마감하지 않는다(혼합 함대 면제).
    let closeEligible: Bool
}

/// 복원 가능한 자동 마감 세션(창 판정은 서버가 한다 — 클라 시계를 되돌려 창을 늘릴 수 없다).
struct AwayRestorableSession: Equatable, Sendable {
    let sessionID: String
    let startedAt: Date?
    let endedAt: Date?
    let autoClosedAt: Date?
    let reason: AutoCloseReason?
    let expiresAt: Date?
    /// 서버가 계산한 잔여 초. 0 이면 이미 만료다.
    let remainingSeconds: Int
}

/// `away_sync()` 한 번의 결과(도메인 형). 정책이 nil 이면 이 폴링에서 away 마감은 **금지**다.
struct AwaySync: Equatable, Sendable {
    let isOK: Bool
    let policy: AwayPolicy?
    let openSession: AwayOpenSession?
    let restorable: AwayRestorableSession?
}

/// `restore_auto_closed_session()` 응답 원문. status 어휘는 docs/away-close.md 5절이 정본이다.
struct AwayRestoreResponse: Decodable, Equatable, Sendable {
    let status: String?
    let sessionId: String?
    let startedAt: String?
    let reason: String?
    let restoredAt: String?
    let usedToday: Int?
    let limit: Int?
    let deletedOpenSessions: Int?
    let endedAt: String?
    let windowSeconds: Int?
    let ageSeconds: Int?
}

/// 복원 결과(도메인 형). 모르는 status 는 `.failed` 로 접는다 — 성공으로 접으면 열리지도 않은 세션을
/// 로컬이 근무중으로 그린다(팀원 화면과 갈린다).
enum AwayRestoreOutcome: Equatable, Sendable {
    /// 복원됨(또는 이미 열려 있음 — 재시도·두 번째 맥. 서버가 멱등하게 성공으로 답한다).
    case restored(sessionID: String, startedAt: Date?)
    /// 창이 닫혔다.
    case expired
    /// 하루 상한.
    case limitReached(usedToday: Int, limit: Int)
    /// 이 마감은 복원 대상이 아니다(사유/이미 복원/내 것 아님/팀 탈퇴) — 배너를 내린다.
    case notRestorable(status: String)
    /// 그 밖의 실패(conflict/invalid/미지 status). 재시도하지 않는다.
    case failed(status: String)
}

/// away_sync 를 못 받은 서버/오프라인. 스토어는 이 값을 받으면 정책을 비워 **마감을 멈춘다**.
/// (ultraWalletUnavailable 과 같은 관용구 — "서버 미배포"와 "네트워크 실패"를 뭉개면 진단이 죽는다.)
struct AwaySyncUnavailable: Error, Equatable {}

/// away_sync() 호출 본문(인자 없음). EmptyBody 를 그대로 쓰면 되지만, 호출부에서 어떤 RPC 인지 읽히도록 별칭만 둔다.
typealias AwaySyncRequest = EmptyBody

/// restore_auto_closed_session(p_session_id uuid) 본문.
struct AwayRestoreRequest: Encodable {
    let pSessionId: String
}

// MARK: - 근무 틱 통합 RPC `work_tick` (v0.2.38 S3 / docs/work-tick.md)

/// `POST /rest/v1/rpc/work_tick` 본문. **9개 키를 언제나 전부 싣는다**(nil 은 `null`).
///
/// PostgREST 는 **보낸 키 집합**으로 함수를 고른다. 합성 Encodable 은 nil Optional 의 키를 생략하는데, 그러면 상태에
/// 따라 키 집합이 달라져(비근무 6개 / 소유 맥 9개 …) 어느 조합 하나만 서버 시그니처와 어긋나도 그 상태의 틱만
/// PGRST202(404)로 조용히 폴백한다 — 스텁 테스트는 초록인 채로. 키 집합을 하나로 고정하면 실패 모양도 하나다
/// (실서버 확인 1건이 전 상태를 대표한다). `null` 은 서버 기본값과 등가라 의미 차이는 없다(2.1 표).
/// 키 이름은 서버 마이그레이션의 인자 이름과 글자 단위로 같아야 하며, 그 일치는 V0238TickTests 의 소스 계약이 못 박는다.
struct WorkTickRequest: Encodable, Equatable, Sendable {
    /// ③~⑥ 의 `team_id=eq.` = `currentTeamID`. 무소속이면 null(팀 조각 4개는 `[]`).
    let pTeamId: String?
    /// `startedAt != nil && session != nil && teamID != nil`. false 면 서버 쓰기 0건(조회만).
    let pHeartbeat: Bool
    /// non-null = 소유 맥 모드(상태+기기 upsert) / null = 흡수 맥 모드(입력만).
    let pSessionId: String?
    let pDeviceId: String?
    /// `ownsCurrentSessionStrongly` — 매 하트비트 덮어쓴다(기존 계약).
    let pOpenedSession: Bool
    /// `advanceMeaningfulInput()` 관측. null 이면 컬럼을 건드리지 않는다(본문 키 생략과 등가).
    let pLastInputAt: String?
    /// ①② 의 `last_seen_at`/`updated_at` — 지금처럼 **클라 자기 시계** 스탬프다(의미 불변).
    let pSeenAt: String
    /// ⑤ 의 `ended_at=gte.` = `koreanWeekStart(now)` — 클라 값을 보내야 ⑤ 와 글자 단위로 같다.
    let pSince: String
    /// 팝오버 열림 && 60초 스로틀 통과 — true 면 ⑧a+⑧b 를 `meta` 에 싣는다.
    let pIncludeMeta: Bool

    enum CodingKeys: String, CodingKey {
        case pTeamId, pHeartbeat, pSessionId, pDeviceId, pOpenedSession, pLastInputAt, pSeenAt, pSince, pIncludeMeta
    }

    /// 인코더의 convertToSnakeCase 가 위 키를 `p_team_id …` 로 바꾼다. nil 은 **encodeNil** 로 키를 남긴다.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        func put(_ value: String?, _ key: CodingKeys) throws {
            if let value { try container.encode(value, forKey: key) } else { try container.encodeNil(forKey: key) }
        }
        try put(pTeamId, .pTeamId)
        try container.encode(pHeartbeat, forKey: .pHeartbeat)
        try put(pSessionId, .pSessionId)
        try put(pDeviceId, .pDeviceId)
        try container.encode(pOpenedSession, forKey: .pOpenedSession)
        try put(pLastInputAt, .pLastInputAt)
        try container.encode(pSeenAt, forKey: .pSeenAt)
        try container.encode(pSince, forKey: .pSince)
        try container.encode(pIncludeMeta, forKey: .pIncludeMeta)
    }
}

/// `work_tick` 응답(단일 jsonb). **각 조각은 기존 GET/RPC 가 주던 행과 같은 모양**이라 디코더를 그대로 재사용한다 —
/// `statuses → [WorkStatusRow]`, `sessions_* → [WorkSessionRow]`, `devices → [WorkStatusDeviceRow]`,
/// `away → AwaySyncResponse`, `meta.memberships → [MembershipRow]`, `meta.invite_code → [InviteCodeRow]`.
/// 전 필드 Optional 인 이유는 하나다: 서버가 키를 **더하거나** 한 조각을 빼도 응답 전체가 throw 되어 하트비트가
/// 폴백으로 두 번 나가는 일이 없어야 한다. `v` 만은 호출부가 1 이 아니면 계약 협상 실패로 폴백한다(2.4).
struct WorkTickResponse: Decodable, Sendable {
    let v: Int?
    /// 트랜잭션 시각. **진단·시계 차 계측에만** 쓴다(판정에 쓰지 않는다 — 의미 불변).
    let serverNow: String?
    let teamId: String?
    let heartbeat: Heartbeat?
    let statuses: [WorkStatusRow]?
    let sessionsActive: [WorkSessionRow]?
    let sessionsWeekly: [WorkSessionRow]?
    let sessionsSince: String?
    let devices: [WorkStatusDeviceRow]?
    let away: AwaySyncResponse?
    let meta: Meta?

    /// 하트비트 ack. **클라는 이 값으로 상태를 바꾸지 않는다**(지금도 upsert 의 204 로 아무것도 안 한다) — 진단 전용.
    /// `mode` 의 모르는 값은 "쓰기 여부 불명" 으로 접고 아무것도 추론하지 않는다(2.4).
    struct Heartbeat: Decodable, Sendable {
        let mode: String?
        let status: String?
        let activeSessionId: String?
        let lastSeenAt: String?
        let device: Bool?
    }

    struct Meta: Decodable, Sendable {
        let memberships: [MembershipRow]?
        let inviteCode: [InviteCodeRow]?
    }
}

/// `work_tick` 이 실패한 **이유**. 폴백 규칙(docs/work-tick.md 2.5/4.5)은 이 구분 위에 선다 —
/// 함수 없음·실행권 회수·계약 불일치는 "이 실행 동안 끈다", 5xx·그 밖은 "연속 3회면 1시간 끈다".
/// 401 은 여기 없다: 서비스가 `SupabaseWorkServiceError.sessionExpired` 로 던져 기존 `withSessionRetry` 의
/// 토큰 갱신 경로를 그대로 탄다. URLError(네트워크·취소)도 그대로 전파한다(취소는 실패로 세지 않기 위해).
enum WorkTickFailure: Error, Equatable, Sendable {
    /// 404 / PGRST202 — 함수가 없거나(db push 전) **모르는 인자 키**를 보냈다.
    case functionMissing(code: String?)
    /// 403 / 42501 — anon 호출·EXECUTE 회수(서버측 킬스위치)·RLS 위반.
    case forbidden(code: String?)
    /// 응답 `v` 가 1 이 아니다(계약 협상 실패 — 열거값 확장엔 능력 협상).
    case contractMismatch(version: Int?)
    /// 2xx 인데 `WorkTickResponse` 로 읽히지 않는다.
    case undecodable
    /// 5xx / 무료플랜 일시정지.
    case serverError(status: Int)
    /// 그 밖의 비 2xx(400 22023 클라 버그, 23514 제약 위반 등). `code` 는 PostgREST 본문의 SQLSTATE/PGRST 코드.
    case rejected(status: Int, code: String?)
}
