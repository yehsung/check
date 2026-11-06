import Foundation

// 1:1 길건너 판 구동기(순수 값 — 테트리스 `TetrisDuelSession` 틀, SPEC v1.3 §8.1 · §3.1 · §3.4 B4).
//
// 판 시계는 로컬 **단조** 시계의 초(스토어의 `uptime()`)다. 서버 `start_at_ms` 를 `syncStart` 로 옮겨 두고, 그 전엔 판을
// `.ready` 에 둔다 → `startAt` 에 `game.begin()` → 1/30초 조각으로 `step`(따라잡기 상한 1초) → `endAt` 에서 얼림.
// 보고 판단(`reportDue`)은 간격을 인자로 받는다 — 프레임 장부(`CrossyDuelFrameLink`)가 정한 간격을 스토어가 넘긴다(B4).
//
// ★ C1 뼈대: 서명과 안전한 기본값만 있다. `advance` · `reportDue` · `resume` 의 몸통은 C2 가 채운다(지금은 판을 움직이지
//   않고 보고를 내지 않는다 — 시험 프로세스가 죽지 않는 쪽).

/// 보고 한 건의 본문(전부 **누계**). `CrossyDuelReportRequest` 가 이 값을 싣는다.
package struct CrossyDuelReportBody: Equatable, Sendable {
    package var seq: Int
    package var score: Int
    package var deaths: Int

    package init(seq: Int, score: Int, deaths: Int) {
        self.seq = seq
        self.score = score
        self.deaths = deaths
    }
}

package struct CrossyDuelSession: Equatable, Sendable {
    // MARK: 상수

    /// 서버 state 의 `goal` 기대값. 다르면 스토어가 `availability = .updateRequired`(SPEC §8.1).
    package static let expectedGoal = 100
    /// 서버 state 의 `max_duration_seconds` 기대값.
    package static let expectedMaxDurationSeconds = 180
    /// `endAt` 뒤 서버 시간 끝 판정까지(초) — `graceEndAt = endAt + 2초`.
    package static let graceSeconds: TimeInterval = 2
    /// 한 걸음 상한(엔진이 dt 를 1/30 으로 자른다 — 안 나누면 시간을 잃는다).
    package static let stepSeconds: TimeInterval = CrossyGame.maxStep
    /// 따라잡기 상한(초) — 넘는 간격(잠자기 등)은 버린다(설계 결정 — 테트리스 30초와 다름).
    package static let maxCatchUpSeconds: TimeInterval = 1
    /// 보고 사이 최소 틈(초).
    package static let minReportGapSeconds: TimeInterval = 0.25
    /// 준비 뒤 시작 모름 동안의 하트비트(초, v1.1 CC-18).
    package static let unstartedHeartbeatSeconds: TimeInterval = 1

    /// 서버 시각을 로컬 단조 시계로 옮긴 판 시작 시각(테트리스 `TetrisDuelSession.localStart` 와 같다).
    package static func localStart(startAtMs: Double, serverNowMs: Double, localNow: TimeInterval) -> TimeInterval {
        localNow + (startAtMs - serverNowMs) / 1000
    }

    // MARK: 보고 종류

    /// `reportDue` 가 말하는 "지금 낼 보고"(SPEC §3.1 표).
    package enum ReportKind: Equatable, Sendable {
        /// 창이 보일 때 첫 보고(seq 1, score 0).
        case ready
        /// 100 도달 — 비행 중 보고를 기다리지 않는다(v1.1 CC-3).
        case goal
        /// 3분(로컬 추정) 도달 — 얼림 뒤 마지막 보고.
        case cap
        /// `graceEndAt` + 0.25초 — 결과 받기.
        case postGrace
        /// 점수·죽음 변화.
        case change
        /// 변화 없음(준비 뒤 시작 모름이면 1초).
        case heartbeat
    }

    /// 직전에 보낸 보고의 값과 시각.
    package struct LastSent: Equatable, Sendable {
        package var score: Int
        package var deaths: Int
        package var at: TimeInterval

        package init(score: Int, deaths: Int, at: TimeInterval) {
            self.score = score
            self.deaths = deaths
            self.at = at
        }
    }

    // MARK: 상태

    /// 서버가 수락 때 뽑은 판 씨앗. 두 사람이 같은 값으로 엔진을 만든다 → 같은 맵.
    package let seed: Int
    package private(set) var game: CrossyGame
    /// 판 상한(초) — state 의 `max_duration_seconds`.
    package let maxDuration: TimeInterval
    /// 판 시작(로컬 단조 초). 서버가 아직 안 정했으면 nil.
    package private(set) var startAt: TimeInterval?
    /// 마지막으로 보낸(만든) 보고 번호.
    package private(set) var seq: Int
    package private(set) var lastSent: LastSent?
    package private(set) var inFlight: Bool
    /// `game.begin()` 을 불렀다(또는 `resume` 으로 이어 섰다).
    package private(set) var started: Bool
    /// `endAt` 에서 얼었다(입력·걸음 정지).
    package private(set) var finished: Bool
    package private(set) var goalReported: Bool
    package private(set) var capReported: Bool
    package private(set) var postGraceReported: Bool

    /// - Parameters:
    ///   - seed: state 의 `seed`(0…2147483647).
    ///   - goal / maxDurationSeconds: state 의 `goal`·`max_duration_seconds`(엔진·세션·서버가 두 출처를 갖지 않게 — §8.1).
    ///   - startingSeq: 서버가 아는 내 seq(재개).
    package init(seed: Int, goal: Int = CrossyDuelSession.expectedGoal,
                 maxDurationSeconds: Int = CrossyDuelSession.expectedMaxDurationSeconds, startingSeq: Int = 0) {
        var rules = CrossyGame.Rules.duel
        rules.goalScore = goal
        self.seed = seed
        self.game = CrossyGame(seed: UInt64(clamping: max(0, seed)), rules: rules)
        self.maxDuration = TimeInterval(maxDurationSeconds)
        self.startAt = nil
        self.seq = max(0, startingSeq)
        self.lastSent = nil
        self.inFlight = false
        self.started = false
        self.finished = false
        self.goalReported = false
        self.capReported = false
        self.postGraceReported = false
    }

    /// 이미 연 판으로 세운다(렌더 시험 · 미리보기용 — 테트리스 `init(seed:startedGame:startAt:simulated:)` 꼴).
    package init(seed: Int, startedGame game: CrossyGame, startAt: TimeInterval,
                 maxDurationSeconds: Int = CrossyDuelSession.expectedMaxDurationSeconds, seq: Int = 0) {
        self.seed = seed
        self.game = game
        self.maxDuration = TimeInterval(maxDurationSeconds)
        self.startAt = startAt
        self.seq = max(0, seq)
        self.lastSent = nil
        self.inFlight = false
        self.started = true
        self.finished = false
        self.goalReported = false
        self.capReported = false
        self.postGraceReported = false
    }

    // MARK: 시계

    /// 판이 얼 시각(`startAt + maxDuration`). 저장 칸이 아니다 — `syncStart` 가 `startAt` 을 당겨도 따라온다(v1.1 CC-17).
    package var endAt: TimeInterval? { startAt.map { $0 + maxDuration } }
    /// 서버 시간 끝 판정 시각(`endAt + 2초`).
    package var graceEndAt: TimeInterval? { endAt.map { $0 + Self.graceSeconds } }

    /// 서버가 정한 판 시작을 로컬 단조 시계로 옮겨 둔다. 응답마다 불러도 된다 — **가장 이른 추정**을 남긴다.
    package mutating func syncStart(startAtMs: Double, serverNowMs: Double, localNow: TimeInterval) {
        guard startAtMs.isFinite, serverNowMs.isFinite, localNow.isFinite else { return }
        let estimate = Self.localStart(startAtMs: startAtMs, serverNowMs: serverNowMs, localNow: localNow)
        startAt = min(startAt ?? estimate, estimate)
    }

    /// 카운트다운 남은 초(시작 시각을 모르면 nil, 시작했으면 0).
    package func countdownRemaining(at now: TimeInterval) -> TimeInterval? {
        startAt.map { max(0, $0 - now) }
    }

    /// 판 남은 초(시작 시각을 모르면 nil, 얼었으면 0).
    package func remaining(at now: TimeInterval) -> TimeInterval? {
        endAt.map { max(0, $0 - max(now, startAt ?? now)) }
    }

    // MARK: 판

    /// 판 시계를 `now` 까지 민다. **C1 뼈대 — C2 가 채운다**(begin · 1/30초 조각 · 따라잡기 1초 · endAt 얼림).
    package mutating func advance(to now: TimeInterval) {
        _ = now
    }

    /// 방향 입력. 얼었거나 시작 전이면 무시.
    package mutating func input(_ direction: CrossyGame.Direction) {
        guard started, !finished else { return }
        game.input(direction)
    }

    /// 앞으로 한 칸(스페이스·클릭). 얼었거나 시작 전이면 무시.
    package mutating func forward() {
        input(.forward)
    }

    // MARK: 보고

    /// 지금 낼 보고(없으면 nil). **C1 뼈대 — C2 가 §3.1 표 · B4 를 채운다**(지금은 언제나 nil).
    /// - Parameters:
    ///   - reportMs: 변화 보고 간격(ms) — 프레임 장부의 `reportInterval` 을 스토어가 넘긴다.
    ///   - heartbeatMs: 변화 없음 간격(ms).
    ///   - windowVisible: 창이 보인다(준비 문).
    ///   - changeReportsSuppressed: 프레임 확인됨 — 점수·죽음 변화 보고를 내지 않는다(B4, v1.3 덧붙임).
    package func reportDue(now: TimeInterval, reportMs: Int, heartbeatMs: Int, windowVisible: Bool,
                           changeReportsSuppressed: Bool = false) -> ReportKind? {
        _ = (now, reportMs, heartbeatMs, windowVisible, changeReportsSuppressed)
        return nil
    }

    /// 다음 보고 본문(seq + 1). 값은 로컬 엔진 누계.
    package mutating func makeReport() -> CrossyDuelReportBody {
        seq += 1
        return CrossyDuelReportBody(seq: seq, score: game.score, deaths: game.deaths)
    }

    /// 앱을 다시 켰을 때 서버 me 값으로 이어 선다. **C1 뼈대 — C2 가 채운다**(`game.restore` + `started = true`, v1.1 CC-2).
    package mutating func resume(score: Int, deaths: Int, seq: Int) {
        _ = (score, deaths, seq)
    }
}
