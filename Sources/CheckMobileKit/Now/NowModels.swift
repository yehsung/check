import CheckCore
import Foundation

// 지금 탭의 값·순수 계산·문구(SPEC-ios §3.2). 화면 없이 값으로 검증한다(`NowStoreTests`).
// 플랫폼 무관 — macOS `swift test` 가 이 파일을 그대로 돈다.

// MARK: - 문구

/// 지금 탭 문구. 맥과 뜻이 같은 문장은 맥 글자 그대로 옮겼다(할 일 보드 `TodoBoardStrings` · 목표 편집 `updateTeamGoal`).
package enum NowText {
    package static let title = "지금"

    // 내 상태
    package static let workingOnMac = "맥에서 근무 중"
    /// Windows 가 연 세션(서버 origin `'windows'` · 2026-10-31 사용자 결정 — 기기 종류대로 '맥' / 'PC').
    package static let workingOnPC = "PC에서 근무 중"
    /// 폰이 연 세션(0.3.51 — `work_phone_start`).
    package static let workingOnPhone = "폰에서 근무 중"
    /// 어디서 열었는지 아직 모른다(생존 신호 응답 전).
    package static let working = "근무 중"
    package static let notWorking = "근무 안 함"
    /// 상태 카드 부제(근무 중): "이번 세션 10:20부터"(KST 시각).
    package static func sessionSince(_ time: String) -> String { "이번 세션 \(time)부터" }
    /// 상태 카드 부제(근무 안 함) — 큰 숫자가 무엇인지 말한다.
    package static let offSubtitle = "오늘 누적"
    /// 상태 카드 부제(연결 끊김) — 시간이 마지막 신호에서 멈춘 까닭.
    package static let staleSubtitle = "연결 끊김 · 마지막 신호에서 멈췄어요"
    /// 이번 주 막대 줄 앞머리("이번 주 24시간 48분 / 40시간").
    package static let weekPrefix = "이번 주"
    package static func goalSuffix(hours: Int) -> String { "/ \(hours)시간" }
    /// 맥 팀 카드 `PresenceChip` 의 stale 문구와 같다.
    package static let connectionLost = "연결 끊김"
    package static let todayLabel = "오늘 누적"
    package static let noTeamTitle = "팀에 속해 있지 않아요"
    /// 예전엔 "맥 앱에서 팀에 참여하면 …"이었다. 폰에서 팀에 들어갈 길이 가입 화면 하나뿐이라, 인증 출구로 들어왔거나
    /// 가입 도중 앱을 껐던 사람은 **맥 없이는 영영 팀에 못 들어갔다**(w16 검증 high) — 이 카드가 그 자리를 받는다.
    package static let noTeamBody = "팀 코드로 합류하거나 새 팀을 만들면 근무 시간과 주간 목표가 여기에 보여요"
    package static let loadFailed = "지금 상태를 불러오지 못했어요. 아래로 당겨 다시 시도해 주세요"
    /// 네트워크 실패 띠 — 탭 공용 문장(`MobileLoadText.checkConnection`). 절마다 [다시 시도]가 곁에 있다.
    package static let networkFailed = MobileLoadText.checkConnection

    // 주간 목표(맥 `updateTeamGoal` 문구)
    package static let goalEdit = "주간 목표 수정"
    package static let goalSheetTitle = "주간 목표"
    package static let goalStepperLabel = "1인당 주간 목표"
    /// 개인 목표가 아니라 **팀 전체의 1인당 목표**다(ios-inventory §9-4). 권한은 맥과 같다 — 팀원 누구나.
    package static let goalExplain = "팀 전체의 1인당 목표가 함께 바뀌어요. 팀원 누구나 바꿀 수 있어요."
    package static let goalSave = "목표 저장"
    package static let goalSaved = "주간 목표 변경됨"
    package static let goalFailed = "목표 변경 실패"
    package static let close = "닫기"

    // 오늘 할 일(맥 `TodoBoardStrings` 와 같은 뜻은 같은 글자)
    package static let todoTitle = "오늘 할 일"
    package static let todoPlaceholder = "할 일 추가"
    package static let todoEditPlaceholder = "할 일 수정"
    package static let todoAdd = "추가"
    package static let todoEmptyTitle = "오늘 할 일이 비어 있어요"
    package static let todoEmptyHint = "위 칸에 적고 완료를 누르면 추가돼요"
    package static let todoDeleted = "삭제됨"
    package static let todoUndo = "되돌리기"
    package static let todoMarkDone = "완료로 표시"
    package static let todoMarkUndone = "완료 취소"
    package static let todoDelete = "삭제"
    package static let todoEdit = "수정"

    package static func todoOldSection(count: Int) -> String { "오래된 항목 (\(count))" }
    /// 오래된 항목 머리 줄 글자(개수는 오른쪽 끝에 따로).
    package static let todoOldTitle = "오래된 항목"
    package static func todoRemaining(count: Int) -> String { "남은 \(count)개" }
    package static func todoCounter(current: Int) -> String { "\(current)/\(TodoRules.maxTitleLength)" }

    /// 불러오기가 끝났는데 팀 상태를 모를 때(스피너 대신).
    package static let statusUnavailableTitle = "내 상태를 불러오지 못했어요"
    package static let workingUnavailable = "근무 중인 사람을 불러오지 못했어요"
    package static let retry = MobileLoadText.retry

    // 지금 근무 중
    /// 머리글. 모를 때(nil)는 숫자를 숨긴다 — 불러오지 못했는데 "0"이면 아무도 일하지 않는다는 말이 된다.
    package static func workingTitle(count: Int?) -> String {
        guard let count else { return "지금 근무 중" }
        return "지금 근무 중 \(count)"
    }
    package static let ourTeam = "우리 팀"
    package static let otherTeams = "다른 팀"
    package static let workingEmpty = "지금 근무 중인 사람이 없어요"
    /// 머리·묶음 오른쪽 사람 수("6명").
    package static func peopleCount(_ count: Int) -> String { "\(count)명" }
    /// 지금 근무 중 절 아래 한 줄. 0.3.51 부터 폰도 근무를 시작·종료한다(맨 위 상태 카드의 버튼).
    /// ★ 2026-10-31: '맥이나' → '맥·PC나'(사용자 결정). Windows 앱으로 근무하는 사람에게 자기 기기가 빠져 있었다.
    package static let workingFooter = "근무는 맥·PC나 이 탭 맨 위 버튼으로 시작하고 끝내요"
    /// 서버에 폰 근무 함수가 아직 없을 때(404 PGRST202 — 앱이 db push 보다 먼저 나간 창)만 쓰는 옛 문장.
    package static let workingFooterMacOnly = "근무 시작과 종료는 맥 앱에서 해요"
    /// 끊긴 팀원 부제: "연결 끊김 · 마지막 확인 13분 전".
    package static func staleLastSeen(_ relative: String?) -> String {
        guard let relative else { return connectionLost }
        return "\(connectionLost) · 마지막 확인 \(relative)"
    }
    /// 다른 팀 사람 줄 끝 말 걸기 버튼(VoiceOver).
    package static func talkTo(_ name: String) -> String { "\(name)에게 말 걸기" }

    // 머리(큰 제목 부제)
    /// 펼친 큰 제목 아래: "9월 17일 목요일 · 아잉 데모팀"(팀이 없으면 날짜만).
    package static func expandedSubtitle(date: String, teamName: String?) -> String {
        guard let teamName, !teamName.isEmpty else { return date }
        return "\(date) · \(teamName)"
    }
    /// 스크롤해 접힌 제목 아래: "5:10:00 · 이번 주 62%".
    package static func collapsedSubtitle(clock: String, percent: Int) -> String { "\(clock) · 이번 주 \(percent)%" }

    // 근무 시작 · 종료(0.3.51 — 폰도 근무를 연다)
    package static let workStart = "근무 시작"
    package static let workStop = "근무 종료"
    package static let workStopConfirmTitle = "근무를 끝낼까요?"
    /// 종료 확인 본문. 맥이 연 근무도 여기서 끝난다(사람당 열린 근무는 하나 — 서버 `work_phone_stop`).
    package static func workStopConfirmMessage(origin: NowWorkOrigin) -> String {
        switch origin {
        case .mac: return "맥에서 연 근무도 지금 끝나요. 지금까지의 시간은 그대로 기록돼요."
        case .windows: return "PC에서 연 근무도 지금 끝나요. 지금까지의 시간은 그대로 기록돼요."
        case .phone, .unknown: return "지금까지의 시간은 그대로 기록돼요."
        }
    }
    package static let workStarted = "근무를 시작했어요"
    package static let workStopped = "근무를 끝냈어요"
    package static let alreadyWorking = "이미 근무 중이에요"
    package static let alreadyWorkingOnMac = "이미 맥에서 근무 중이에요"
    package static let alreadyWorkingOnPC = "이미 PC에서 근무 중이에요"
    package static let alreadyStopped = "이미 근무가 끝나 있어요"
    package static let workChanged = "근무 상태가 바뀌었어요. 다시 확인해 주세요"
    package static let startFailed = "근무를 시작하지 못했어요. 잠시 후 다시 시도해 주세요"
    package static let stopFailed = "근무를 끝내지 못했어요. 잠시 후 다시 시도해 주세요"
    /// 서버에 폰 근무 함수가 없다(404 PGRST202).
    package static let workUnavailable = "지금은 폰에서 근무를 시작할 수 없어요"
    /// 소속이 없을 때 버튼 아래(버튼은 꺼진다).
    package static let workNeedsTeam = "팀에 들어가면 근무를 시작할 수 있어요"
    /// 폰이 연 근무의 버튼 아래 안내. 확인 임계는 서버가 준 값(없으면 2시간 30분 — 서버 기본값과 같다).
    package static func phoneWorkCaption(checkAfterSeconds: Int?) -> String {
        "폰을 잠가도 근무는 이어져요 · \(NowFormat.hoursMinutesText(checkAfterSeconds ?? 9_000)) 동안 앱을 안 열면 확인 알림을 보내요"
    }
    package static let macWorkCaption = "맥에서 연 근무예요 · 여기서 끝낼 수도 있어요"
    package static let pcWorkCaption = "PC에서 연 근무예요 · 여기서 끝낼 수도 있어요"
    /// 알림이 꺼진 사람이 폰으로 근무 중일 때 — 확인 알림 없이 같은 시각표로 끝난다(서버 결정).
    package static let pushOffWarning = "알림이 꺼져 있어 확인 알림 없이 근무가 끝날 수 있어요"
    /// 서버가 확인 알림 뒤 유예가 지나 소급 마감했다(`work_phone_touch` 의 last.reason = idle). "13:20"(KST).
    package static func idleClosed(at time: String?) -> String {
        guard let time else { return "앱을 오래 열지 않아 근무를 끝냈어요" }
        return "앱을 오래 열지 않아 \(time)에 근무를 끝냈어요"
    }
}

// MARK: - 폰 근무(0.3.51)

/// 내 열린 근무를 어디서 열었는가(서버 `work_phone_*` 응답의 origin). 팀 상태 GET 에는 이 칸이 없다 — 공유 select 에 칸을
/// 더하면 칸이 없는 서버에서 맥·폰 공용 폴링이 400 이 된다(지도 phonework-ios-client). 그래서 폰 RPC 응답으로만 안다.
package enum NowWorkOrigin: String, Equatable, Sendable {
    case phone
    case mac
    /// Windows 앱이 연 근무(서버 `phone_work__session_json` 이 `20261101120000` 부터 보낸다).
    /// ★ 이 값이 생기기 전에는 모르는 origin 을 `.mac` 으로 접었고, 그래서 **PC 에서 근무를 켠 사람의 폰이
    ///   "맥에서 근무 중"이라고 말했다.** 두 값일 때 안전했던 접기가 셋째 값에서 남의 이름을 적은 자리다.
    case windows
    /// 아직 모른다(생존 신호 응답 전) **또는 서버가 우리가 모르는 값을 보냈다** — "근무 중"으로만 말한다.
    /// 넷째 값(리눅스·웹…)이 와도 이 자리로 떨어져야 한다. 특정 기기 이름으로 접지 마라.
    case unknown
}

/// 폰 RPC 가 알려 준 내 열린 세션(시작 · touch 응답).
package struct NowPhoneSession: Equatable, Sendable {
    /// 열린 행 id(소문자 — `OpenSessionFact.id` 와 같은 축).
    package var id: String
    package var origin: NowWorkOrigin
    /// 다음 확인 알림 예정 시각(touch 응답 `check_at` — 맥 입력이 있으면 서버가 더 미룬다).
    package var checkAt: Date?
    /// 확인 임계(초 — 시작 응답 `check_after_seconds`).
    package var checkAfterSeconds: Int?

    package init(id: String, origin: NowWorkOrigin, checkAt: Date? = nil, checkAfterSeconds: Int? = nil) {
        self.id = id
        self.origin = origin
        self.checkAt = checkAt
        self.checkAfterSeconds = checkAfterSeconds
    }
}

// MARK: - 팀 소속

/// `fetchOwnMembership` 의 결과(주 팀 하나).
package struct NowMembership: Equatable, Sendable {
    package var teamID: String
    package var teamName: String
    package var goalHours: Int
    package var role: String

    package init(teamID: String, teamName: String, goalHours: Int, role: String) {
        self.teamID = teamID
        self.teamName = teamName
        self.goalHours = goalHours
        self.role = role
    }
}

// MARK: - 내 상태 카드

/// 내 상태 카드 한 장의 값(시각 `now` 기준 — 뷰가 1초마다 다시 만든다).
package struct NowMyCard: Equatable, Sendable {
    /// 근무 중인가(서버 `work_statuses.status` — 맥이 열었든 폰이 열었든).
    package var isWorking: Bool
    /// 근무 중인데 생존신호가 끊겼다(맥 팀 카드의 "연결 끊김"). 시간은 마지막 신호에서 멈춘다.
    package var isStale: Bool
    /// 진행 중 세션의 서버 시작 시각(근무 중일 때만).
    package var sessionStartedAt: Date?
    package var todaySeconds: Int
    package var weekSeconds: Int
    package var goalHours: Int
    /// 열린 근무를 어디서 열었는가(근무 중일 때만 뜻이 있다). 새 칸은 마지막 — 기본값이 있어 기존 호출부가 그대로 컴파일된다.
    package var origin: NowWorkOrigin = .unknown

    package var goalSeconds: Int { max(1, goalHours) * 3600 }

    /// 상태 글자: 근무 안 함 · 폰에서 근무 중 · 맥에서 근무 중 · (모르면) 근무 중.
    package var stateText: String {
        guard isWorking else { return NowText.notWorking }
        switch origin {
        case .phone: return NowText.workingOnPhone
        case .mac: return NowText.workingOnMac
        case .windows: return NowText.workingOnPC
        case .unknown: return NowText.working
        }
    }
    package var progress: Double { TeamWeeklyGoal(workedSeconds: weekSeconds, goalSeconds: goalSeconds).progress }
    package var isGoalComplete: Bool { weekSeconds >= goalSeconds }
    package var percent: Int { NowFormat.percent(workedSeconds: weekSeconds, goalSeconds: goalSeconds) }

    /// "이번 주 24.8시간 · 목표 40시간 · 62%"(SPEC-ios §3.2).
    package var weekLine: String {
        "이번 주 \(NowFormat.hoursOneDecimal(weekSeconds))시간 · 목표 \(goalHours)시간 · \(percent)%"
    }
}

// MARK: - 지금 근무 중 한 사람

/// "지금 근무 중" 한 줄. 우리 팀은 경과 시간이 있고, 다른 팀은 근무 여부만 있다(서버가 시간을 주지 않는다 — ios-inventory §9-1).
package struct NowWorkingPerson: Identifiable, Equatable, Sendable {
    package var id: String
    package var name: String
    package var avatarURL: URL?
    /// 센터 서버값(표시는 `CenterLabel` 한 곳).
    package var center: String?
    package var isTeammate: Bool
    /// 우리 팀만: 서버 세션 시작 시각.
    package var startedAt: Date?
    /// 우리 팀만: 이 시각의 경과(초). stale 이면 마지막 신호에서 멈춘 값.
    package var elapsedSeconds: Int?
    package var isStale: Bool
    /// 우리 팀만: 마지막 생존신호 시각(끊긴 줄 부제 "마지막 확인 N분 전").
    package var lastSeenAt: Date?
    /// 상태메시지(v0.3.51) — 사람 목록(`app_user_directory`)에서 온다. 우리 팀원도 같은 목록에서 찾는다(팀 상태 조회는 싣지 않는다).
    /// 이미 `StatusMessage.display` 를 지난 값이다(nil = 줄을 그리지 않는다).
    package var statusMessage: String?

    package init(
        id: String, name: String, avatarURL: URL?, center: String?, isTeammate: Bool,
        startedAt: Date?, elapsedSeconds: Int?, isStale: Bool, lastSeenAt: Date? = nil, statusMessage: String? = nil
    ) {
        self.id = id
        self.name = name
        self.avatarURL = avatarURL
        self.center = center
        self.isTeammate = isTeammate
        self.startedAt = startedAt
        self.elapsedSeconds = elapsedSeconds
        self.isStale = isStale
        self.lastSeenAt = lastSeenAt
        self.statusMessage = statusMessage
    }
}

// MARK: - 시간 계산(순수)

/// 폰이 세는 오늘·이번 주(서버 세션 시각 기준). 맥 `TeamMemberStatus` 의 live 계산을 쓰되, **오늘은 KST 자정으로 자른다** —
/// 코어 `liveTodayDurationSeconds` 는 진행 세션을 시작 시각부터 통째로 더해 자정을 넘긴 세션이 어제 몫까지 오늘로 센다.
///
/// **신호 끊김(stale) 판정 시각 `presenceAt`** 은 화면 시각 `now` 와 따로 받는다. 맥은 30초마다 자기 팀 상태를 다시 읽어
/// "지금 − 마지막 신호 > 90초"를 now 로 재도 되지만, 폰은 60초마다(또 background 에서 돌아와서야) 받는다 — now 로 재면
/// 받을 때 29초 묵은 신호가 다음 응답 직전 몇 초 동안, background 에서 돌아온 직후에는 응답이 올 때까지 "연결 끊김"으로
/// 뒤집히고 오늘 누적이 마지막 신호 지점으로 뒤로 뛴다(now-verify R1·R2). 스토어가 판정 시각을 고른다(`NowStore.presenceJudgedAt`).
package enum NowTimeMath {
    /// 오늘 누적(초). `fetchedAt` = 그 행을 받은 시각 — 받은 뒤 자정이 지났으면 서버가 준 "오늘 끝난 세션 합"은 어제 몫이라 버린다.
    package static func todaySeconds(_ member: TeamMemberStatus, fetchedAt: Date, now: Date, presenceAt: Date? = nil) -> Int {
        let dayStart = TeamWeeklyGoal.koreanDayStart(for: now)
        let closed = TeamWeeklyGoal.koreanDayStart(for: fetchedAt) == dayStart ? member.todayDurationSeconds : 0
        return max(0, closed) + currentContribution(member, windowStart: dayStart, now: now, presenceAt: presenceAt)
    }

    /// 이번 주 누적(초). 받은 뒤 주가 바뀌었으면 지난 주 합은 버린다.
    package static func weekSeconds(_ member: TeamMemberStatus, fetchedAt: Date, now: Date, presenceAt: Date? = nil) -> Int {
        let weekStart = TeamWeeklyGoal.koreanWeekStart(for: now)
        let closed = TeamWeeklyGoal.koreanWeekStart(for: fetchedAt) == weekStart ? member.weeklyDurationSeconds : 0
        return max(0, closed) + currentContribution(member, windowStart: weekStart, now: now, presenceAt: presenceAt)
    }

    /// 진행 세션의 [windowStart, 끝] 기여. 끝은 살아 있으면 now, 신호가 끊겼으면 마지막 신호(맥 규칙과 같다).
    /// 끊김 판정은 `presenceAt`(없으면 now) 에서 한다.
    package static func currentContribution(_ member: TeamMemberStatus, windowStart: Date, now: Date, presenceAt: Date? = nil) -> Int {
        guard member.status == .working, let started = member.currentSessionStartedAt else { return 0 }
        let end: Date
        if isStale(member, now: presenceAt ?? now) {
            end = member.lastSeenAt ?? member.updatedAt ?? started
        } else {
            end = now
        }
        return max(0, Int(min(end, now).timeIntervalSince(max(started, windowStart))))
    }

    /// 진행 세션 경과(초 — 우리 팀 "지금 근무 중" 줄). 끊겼으면 마지막 신호에서 멈춘 값, 아니면 now 까지.
    package static func elapsedSeconds(_ member: TeamMemberStatus, now: Date, presenceAt: Date? = nil) -> Int {
        guard member.status == .working, let started = member.currentSessionStartedAt else { return 0 }
        if case .staleWorking(let frozen) = member.presence(now: presenceAt ?? now) { return frozen }
        return max(0, Int(now.timeIntervalSince(started)))
    }

    package static func isStale(_ member: TeamMemberStatus, now: Date) -> Bool {
        if case .staleWorking = member.presence(now: now) { return true }
        return false
    }
}

// MARK: - 불러오기 상태

/// 우리 팀 상태(내 카드 · 지금 근무 중)를 화면이 어떻게 그릴지.
/// - loading: 이 세대에서 새로고침이 아직 한 번도 끝나지 않았다(스피너).
/// - failed: 시도는 끝났는데 팀 상태를 모른다(오프라인 · 5xx) — 스피너를 남기지 않고 "불러오지 못했어요"를 보인다.
///   다시 시도하는 동안에도 failed 를 유지한다(60초 주기마다 스피너 ↔ 실패 줄이 깜빡이지 않게 — 당겨서 새로고침 표시가 진행을 말한다).
/// - loaded: 팀 상태를 받았거나 소속 없음이 확정됐다.
package enum NowLoadState: Equatable, Sendable {
    case loading
    case failed
    case loaded
}

// MARK: - 서식(순수)

package enum NowFormat {
    /// 시·분·초 "3:25:07"(오늘 누적 큰 숫자).
    package static func clock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }

    /// 시:분 "2:05"(우리 팀 경과).
    package static func hoursMinutes(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return String(format: "%d:%02d", s / 3600, (s % 3600) / 60)
    }

    /// 소수 한 자리 시간 "24.8". **내림**이다 — 39.96시간을 "40.0"으로 올려 목표를 채운 것처럼 보이지 않게.
    package static func hoursOneDecimal(_ seconds: Int) -> String {
        let tenths = max(0, seconds) * 10 / 3600
        return "\(tenths / 10).\(tenths % 10)"
    }

    /// 목표 퍼센트(맥 `GoalPercentFormatter.percent` 와 같은 식 — 반올림 · 0~999).
    package static func percent(workedSeconds: Int, goalSeconds: Int) -> Int {
        let worked = max(0, workedSeconds)
        let goal = max(1, goalSeconds)
        let raw = Int((Double(worked) / Double(goal) * 100).rounded())
        return min(999, max(0, raw))
    }

    /// "24시간 48분" · "48분" · "3시간"(이번 주 막대 줄 · 우리 팀 경과). 내림 — 올려서 목표를 채운 것처럼 보이지 않게.
    package static func hoursMinutesText(_ seconds: Int) -> String {
        let s = max(0, seconds)
        let hours = s / 3600, minutes = (s % 3600) / 60
        if hours == 0 { return "\(minutes)분" }
        if minutes == 0 { return "\(hours)시간" }
        return "\(hours)시간 \(minutes)분"
    }

    /// 시각 "10:20"(KST 24시간 — 상태 카드 "이번 세션 10:20부터").
    package static func clockTime(_ date: Date) -> String {
        let parts = NowFormat.kst.dateComponents([.hour, .minute], from: date)
        return String(format: "%d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    /// 머리 날짜 "9월 17일 목요일"(KST).
    package static func longDate(_ date: Date) -> String {
        let parts = NowFormat.kst.dateComponents([.month, .day, .weekday], from: date)
        let weekdays = ["일", "월", "화", "수", "목", "금", "토"]
        let weekday = parts.weekday.map { weekdays[($0 - 1 + 7) % 7] + "요일" } ?? ""
        return "\(parts.month ?? 0)월 \(parts.day ?? 0)일 \(weekday)"
    }

    static let kst: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul") ?? .current
        calendar.locale = Locale(identifier: "ko_KR")
        return calendar
    }()

    /// VoiceOver 용 "3시간 25분".
    package static func spokenDuration(_ seconds: Int) -> String {
        let s = max(0, seconds)
        let hours = s / 3600, minutes = (s % 3600) / 60
        if hours == 0 { return "\(minutes)분" }
        return "\(hours)시간 \(minutes)분"
    }
}

// MARK: - 할 일 입력(순수 — 맥 `TodoDraftInput` 과 같은 규칙)

package enum NowTodoDraft {
    /// 새 입력을 반영할지. 지우는 방향은 늘 통과, 늘리는 방향은 100자(코드 포인트 1000)까지 — 넘으면 **변경을 되돌린다**
    /// (잘라 넣지 않는다: 붙여넣은 문장 끝이 소리 없이 사라지면 "분명 적었는데 없어졌다"가 된다).
    package static func accepted(current: String, proposed: String) -> String {
        if proposed.count <= current.count, proposed.unicodeScalars.count <= current.unicodeScalars.count { return proposed }
        return TodoRules.titleFitsLimits(proposed) ? proposed : current
    }

    /// 카운터 "92/100". 90자 전에는 nil(숫자가 아예 안 뜬다).
    package static func counterText(_ text: String) -> String? {
        guard text.count >= TodoRules.counterVisibleFrom else { return nil }
        return NowText.todoCounter(current: text.count)
    }
}

/// 할 일 한 줄의 화면 값.
package struct NowTodoRow: Identifiable, Equatable, Sendable {
    package var id: UUID
    package var title: String
    package var isDone: Bool
    /// "어제" · "3일 전"(오늘 만든 것은 nil).
    package var carryBadge: String?
    package var carryOverDays: Int
}
