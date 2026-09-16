import Foundation

// B3: `CheckOverlayReactions.swift` 에서 화면(AppKit·뷰)과 무관한 규칙·값 타입만 코어로 옮겼다.
// 설명 주석의 큰 줄기(왜 이 값인가)는 원래 파일 머리에 남아 있다.

/// 졸기 스케줄 파라미터(순수 함수). 시간대 제한 없이, 한동안 아무 리액션이 없으면 존다.
package enum DrowsyWindow {
    package static let timeZone = TimeZone(identifier: "Asia/Seoul")!

    /// 졸기 진입 간격 하한/상한(초). 60±20분 — 마지막 리액션 이후 이만큼 조용하면 꾸벅 잠든다.
    ///
    /// 예전엔 10±4분이었는데, 졸기가 **스스로 깨지 않던 시절**(napSeconds 도입 전)과 겹쳐
    /// "평소에 맨날 눈 감은 상태만 본다"가 됐다(실사용 신고). 자는 시간이 유한해진 지금도 간격이 짧으면
    /// 캐릭터가 자는 모습이 기본값처럼 보이므로, 졸기는 **가끔 마주치는 사건**이어야 한다.
    package static let minInterval: TimeInterval = 40 * 60
    package static let maxInterval: TimeInterval = 80 * 60

    /// 한 번 졸 때 자는 시간 하한/상한(초). 5~10분 — 이 시간이 지나면 조용히 눈을 뜬다.
    ///
    /// **이 값이 없던 시절 졸기는 만료가 없어**, 한 번 잠들면 클릭·찔림·마일스톤·근무종료 전까지
    /// 영원히 눈을 감고 있었다. 조용히 일하는 사람에게는 그게 곧 상시 상태였다.
    /// 깨어남은 '화들짝'이 아니라 무음 복귀다 — 아무도 안 건드렸는데 놀라는 건 이상하다.
    ///
    /// 간격(40~80분)과 합치면 자는 시간은 전체의 약 10%다 — 졸긴 조는데 그게 기본 모습은 아닌 비율.
    /// 수십 초로 두면 "졸았나?" 싶게 스쳐 지나가 졸기라는 연출 자체가 안 읽힌다(사용자 판단).
    package static let minNapSeconds: TimeInterval = 5 * 60
    package static let maxNapSeconds: TimeInterval = 10 * 60

    /// 주어진 시각(기본 KST)이 밤샘 시간창(23:00~05:00) 안이면 true. 23,0,1,2,3,4시가 해당된다.
    package static func contains(_ date: Date, timeZone: TimeZone = DrowsyWindow.timeZone) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let hour = calendar.component(.hour, from: date)
        return hour >= 23 || hour < 5
    }

    /// 다음 졸기까지의 간격을 뽑는다(난수 주입 가능).
    package static func nextInterval(using rng: inout some RandomNumberGenerator) -> TimeInterval {
        TimeInterval.random(in: minInterval...maxInterval, using: &rng)
    }

    /// 이번 잠의 길이를 뽑는다(난수 주입 가능). 매번 달라야 '타이머'가 아니라 '졸음'으로 보인다.
    package static func nextNapDuration(using rng: inout some RandomNumberGenerator) -> TimeInterval {
        TimeInterval.random(in: minNapSeconds...maxNapSeconds, using: &rng)
    }
}

/// 마일스톤 1일 1회 기록기. UserDefaults 에 "check.milestone.<키>.<yyyyMMdd(KST)>" 로 기록해
/// 같은 날 같은 키의 축하가 두 번 터지지 않게 한다. 세션 내 중복 조회를 줄이려 인메모리 캐시도 둔다.
package struct MilestoneTracker {
    package static let hourOneKey = "hour1"
    package static let hourFourKey = "hour4"
    package static let teamGoalKey = "teamGoal"
    /// 오늘 팀에서 내가 첫 출근일 때의 인사(하루 1회). 같은 날 껐다 켜도 다시 뜨지 않게 이 기록으로 묶는다.
    package static let firstArrivalKey = "firstArrival"

    /// KST(Asia/Seoul) 그레고리력. 매 호출마다 Calendar 를 새로 만들지 않도록 1회 생성해 공유한다.
    package static let kstCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = DrowsyWindow.timeZone
        return calendar
    }()

    package let defaults: UserDefaults
    private var firedThisSession: Set<String> = []
    /// 오늘 하루(KST)의 [시작, 다음날 시작) 구간과 그 dayKey. now 가 이 구간 안이면 재계산을 건너뛴다.
    private var cachedDay: (start: Date, next: Date, key: String)?

    package init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    package static func dayKey(_ date: Date, timeZone: TimeZone = DrowsyWindow.timeZone) -> String {
        let calendar: Calendar
        if timeZone == DrowsyWindow.timeZone {
            calendar = kstCalendar
        } else {
            var c = Calendar(identifier: .gregorian)
            c.timeZone = timeZone
            calendar = c
        }
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d%02d%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    private static func defaultsKey(_ key: String, day: String) -> String {
        "check.milestone.\(key).\(day)"
    }

    /// 자정 롤오버 전까지 dayKey 를 메모해, 근무 1h 후 매초 호출에서도 Calendar 계산을 반복하지 않는다.
    /// now 가 캐시 구간을 벗어나면(하루가 지나면) 재계산해 자정 귀속 정확성을 유지한다.
    private mutating func cachedDayKey(for now: Date) -> String {
        if let cached = cachedDay, now >= cached.start, now < cached.next {
            return cached.key
        }
        let calendar = Self.kstCalendar
        let start = calendar.startOfDay(for: now)
        let next = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        let key = Self.dayKey(now)
        cachedDay = (start, next, key)
        return key
    }

    /// 오늘(KST) 아직 안 터진 키면 기록하고 true, 이미 터졌으면 false. 하루가 지나면 다시 true 가 된다.
    package mutating func fireIfNeeded(_ key: String, now: Date) -> Bool {
        let dkey = Self.defaultsKey(key, day: cachedDayKey(for: now))
        if firedThisSession.contains(dkey) {
            return false
        }
        if defaults.bool(forKey: dkey) {
            firedThisSession.insert(dkey)
            return false
        }
        defaults.set(true, forKey: dkey)
        firedThisSession.insert(dkey)
        return true
    }
}
