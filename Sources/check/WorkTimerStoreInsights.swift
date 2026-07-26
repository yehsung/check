import Foundation

// 개인 기록(히트맵·주간 회고) + 토큰 순위 월 이동 + 넛지 자동시작 취소의 스토어 계층.
// 데이터 출처는 서버 work_sessions 의 내 완료 세션뿐이고(타인 데이터 미조회), 요일/주 계산은 전부
// CheckWorkInsights 의 순수 함수가 담당한다(스토어는 로딩·상태 반영만).
@MainActor
extension WorkTimerStore {
    /// 히트맵 집계 기간(주). 이 기간의 완료 세션만 서버에서 받아 온다.
    static let insightsWeeks = 8
    /// 넛지 자동 시작을 취소할 수 있는 유예(초). 이 시간 안에는 헤더에 [취소] 가 뜬다.
    static let nudgeAutoStartCancelWindow: TimeInterval = 60
    /// 이 주의 회고 배너를 이미 보여줬는지 기록하는 UserDefaults 키.
    static let retroBannerShownWeekKey = "check.retro.shownForWeek"
    /// 넛지 자동시작 토글의 UserDefaults 키.
    static let nudgeAutoStartEnabledKey = "check.nudgeAutoStartEnabled"
    /// 이 맥의 기기 식별자 UserDefaults 키(토큰 원장 분리용).
    static let deviceIDKey = "check.deviceID"

    /// 개인 기록 패널 로드 래퍼(Task 발사). (구현: wave-T)
    func loadInsights() {
        // TODO(wave-T): Task { await performLoadInsights() }
    }

    /// 내 최근 완료 세션을 받아 히트맵/회고를 계산해 반영한다. (구현: wave-T)
    func performLoadInsights() async {
        // TODO(wave-T): session 가드 → generation 캡처 → service.fetchMySessions(since: 8주 전)
        //   → WorkRhythmHeatmap.build / WeeklyRetro.build → 등호 가드 대입 → insightsLoaded
    }

    /// 팝오버 열림 시 회고 배너 노출 여부를 판정한다(주당 1회, 지난주 근무가 있을 때만). (구현: wave-T)
    func evaluateRetroBanner() {
        // TODO(wave-T): 이번 주 키가 defaults 기록과 다르고 retro != nil 이면 showsRetroBanner = true
    }

    /// 회고 배너를 이번 주에 본 것으로 기록하고 감춘다. (구현: wave-T)
    func markRetroBannerSeen() {
        // TODO(wave-T): defaults.set(RetroWeekKey.current(), forKey: retroBannerShownWeekKey); showsRetroBanner = false
    }

    /// 토큰 순위판 월 이동(-1=과거, +1=미래). 이동 후 그 달 보드를 다시 로드한다. (구현: wave-T)
    func stepTokenBoardMonth(by delta: Int) {
        // TODO(wave-T): TokenBoardMonthNavigator.step 적용 → 값이 바뀌었으면 tokenBoard 비우고 loadTokenBoard()
    }

    /// 넛지 자동 시작 사용 여부 저장. (구현: wave-T)
    func setNudgeAutoStartEnabled(_ enabled: Bool) {
        // TODO(wave-T): 값 반영 + defaults 저장
    }

    /// 자동 시작 취소 가능 여부(자동 시작 직후 유예 안, 아직 근무중).
    func canCancelNudgeAutoStart(now: Date = Date()) -> Bool {
        guard let startedAt = nudgeAutoStartedAt, startedAt != Date.distantPast else { return false }
        guard self.startedAt != nil else { return false }
        return now.timeIntervalSince(startedAt) <= Self.nudgeAutoStartCancelWindow
    }

    /// 넛지가 자동 시작한 근무를 취소한다(= 근무 종료 + 안내). (구현: wave-T)
    func cancelNudgeAutoStart() {
        // TODO(wave-T): guard canCancelNudgeAutoStart() → stop() → nudgeAutoStartedAt = nil → 안내 문구
    }
}
