import Foundation

// 1:1 길건너 판 구동기(순수 값 — 테트리스 `TetrisDuelSession` 틀, SPEC v1.3 §8.1 · §3.1 · §3.4 B4).
//
// 판 시계는 로컬 **단조** 시계의 초(스토어의 `uptime()`)다. 서버 `start_at_ms` 를 `syncStart` 로 옮겨 두고, 그 전엔 판을
// `.ready` 에 둔다 → `startAt` 에 `game.begin()` → 1/30초 조각으로 `step`(따라잡기 상한 1초) → `endAt` 에서 얼림.
// 보고 판단(`reportDue`)은 간격을 인자로 받는다 — 프레임 장부(`CrossyDuelFrameLink`)가 정한 간격을 스토어가 넘긴다(B4).
//
// 보고 한 건의 수명: `reportDue` 가 종류를 말한다 → 스토어가 `makeReport(_:at:)` 로 본문을 만든다(seq +1 · 직전 값 · 비행 중) →
// 응답이 오면 `reportSettled()`(또는 3초 멎음이면 같은 자리에서 버린다). **goal · cap 은 비행 중이어도 낸다**(v1.1 CC-3) — 값이 누계이고
// seq 가 커서 늦게 닿은 옛 보고는 서버가 stale 로 끝낸다.

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
    /// 엔진에 흘려 준 판 시계의 끝(로컬 단조 초). 시작 전이면 nil, 재개 직후도 nil(다음 `advance` 가 그 시각부터 흘린다).
    package private(set) var advancedTo: TimeInterval?
    /// 따라잡기 상한을 넘어 버린 판 시간 합(진단용).
    package private(set) var droppedSeconds: TimeInterval
    /// 서버가 판을 닫았다(`freeze`) — 이후로는 시계·입력·보고가 전부 멎는다.
    package private(set) var serverClosed: Bool
    /// 실패해 **다음 걸음에** 다시 낼 보고(최소 틈 0.25초만 — goal · cap 은 비행 중이어도). `reportNeedsRetry` 가 세운다.
    package private(set) var retryPending: ReportKind?

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
        self.advancedTo = nil
        self.droppedSeconds = 0
        self.serverClosed = false
        self.retryPending = nil
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
        self.advancedTo = startAt
        self.droppedSeconds = 0
        self.serverClosed = false
        self.retryPending = nil
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

    /// 판 시계를 `now` 까지 민다(같은 시각이면 멱등). 시작 전엔 판을 `.ready` 에 둔다 → `startAt` 에 `game.begin()` →
    /// 1/30초 조각으로 `step`(엔진이 dt 를 1/30 으로 자르므로 안 나누면 시간을 잃는다) → `endAt` 에서 얼림.
    /// **따라잡기 상한 1초** — 넘는 간격(잠자기 · 앱 멈춤)은 버린다(교통 위상은 어차피 사람마다 다르고 경주 시계는 서버다).
    package mutating func advance(to now: TimeInterval) {
        guard now.isFinite, !finished, !serverClosed, let startAt, let end = endAt, now >= startAt else { return }
        if !started {
            game.begin()
            started = true
            advancedTo = startAt
        }
        let target = min(now, end)
        let from = advancedTo ?? target
        if target > from {
            var span = target - from
            if span > Self.maxCatchUpSeconds {
                droppedSeconds += span - Self.maxCatchUpSeconds
                span = Self.maxCatchUpSeconds
            }
            while span > 1e-9 {
                let dt = min(Self.stepSeconds, span)
                game.step(dt: dt)
                span -= dt
            }
        }
        advancedTo = max(from, target)
        if now >= end { finished = true }
    }

    /// 서버가 판을 닫았다(끝난 응답). 시계·입력·보고가 멎는다 — 엔진 값(내 점수)은 그대로 둔다(결과 카드 Q3 재료).
    package mutating func freeze() {
        serverClosed = true
        finished = true
        inFlight = false
    }

    /// 지금 판이 흐르는 중인가(시작했고 · 안 얼었고 · 서버가 안 닫았다).
    package var isLive: Bool { started && !finished && !serverClosed }

    /// 목표 점수(엔진 규칙 값 — state `goal` 에서 왔다).
    package var goal: Int { game.rules.goalScore ?? Self.expectedGoal }

    /// 방향 입력. 얼었거나 시작 전이면 무시.
    package mutating func input(_ direction: CrossyGame.Direction) {
        guard started, !finished, !serverClosed else { return }
        game.input(direction)
    }

    /// 앞으로 한 칸(스페이스·클릭). 얼었거나 시작 전이면 무시.
    package mutating func forward() {
        input(.forward)
    }

    // MARK: 보고

    /// 보고 간격 자르기(§3.1): `report_ms ∈ [1000, 5000]` · `heartbeat_ms ∈ [report_ms, 5000]` · 키가 없으면 2000/3000.
    package static func clampedIntervals(reportMs: Int?, heartbeatMs: Int?) -> (reportMs: Int, heartbeatMs: Int) {
        let report = min(max(reportMs ?? defaultReportMs, 1_000), 5_000)
        let heartbeat = min(max(heartbeatMs ?? defaultHeartbeatMs, report), 5_000)
        return (report, heartbeat)
    }

    /// 키가 없을 때의 보고 간격(ms — §3.1 · B4 대체 길의 옛 기본).
    package static let defaultReportMs = 2_000
    package static let defaultHeartbeatMs = 3_000
    /// 나가 있는 보고가 이만큼(단조 초) 답이 없으면 버리고 새로(테트리스 `reportStallSeconds` 3).
    package static let reportStallSeconds: TimeInterval = 3

    /// 지금 낼 보고(없으면 nil) — §3.1 표 · B4. 순서: 준비 → (0.25초 틈) → goal → cap → (비행 중이면 여기서 멈춤) → postGrace →
    /// 시작 모름 1초 하트비트 → 변화 → 하트비트.
    /// - Parameters:
    ///   - reportMs: 변화 보고 간격(ms — state `report_ms`, [1000, 5000] 으로 자른다).
    ///   - heartbeatMs: 변화 없음 간격(ms — 대체 길이면 `heartbeat_ms`, 프레임 확인됨이면 `checkpoint_ms`. [reportMs, 5000]).
    ///   - windowVisible: 창이 보인다(준비 문 — 서버가 이미 준비를 받았으면 스토어가 참으로 넘긴다).
    ///   - changeReportsSuppressed: 프레임 확인됨 — 점수·죽음 변화 보고를 내지 않는다(체크포인트가 싣는다, B4).
    package func reportDue(now: TimeInterval, reportMs: Int, heartbeatMs: Int, windowVisible: Bool,
                           changeReportsSuppressed: Bool = false) -> ReportKind? {
        guard now.isFinite, !serverClosed else { return nil }
        guard let last = lastSent else { return windowVisible ? .ready : nil }
        let gap = now - last.at
        guard gap >= Self.minReportGapSeconds else { return nil }
        if !goalReported, started, game.score >= goal { return .goal }
        if !capReported, let endAt, now >= endAt { return .cap }
        if inFlight { return nil }
        if let retry = retryPending { return retry }
        if !postGraceReported, let graceEndAt, now >= graceEndAt + Self.minReportGapSeconds { return .postGrace }
        guard startAt != nil else { return gap >= Self.unstartedHeartbeatSeconds ? .heartbeat : nil }
        let (report, heartbeat) = Self.clampedIntervals(reportMs: reportMs, heartbeatMs: heartbeatMs)
        if !changeReportsSuppressed, game.score != last.score || game.deaths != last.deaths,
           gap >= TimeInterval(report) / 1000 {
            return .change
        }
        if gap >= TimeInterval(heartbeat) / 1000 { return .heartbeat }
        return nil
    }

    /// 보고 한 벌을 만들고 장부(seq · 직전 값 · 비행 중 · goal/cap/postGrace 깃발)를 넘긴다.
    package mutating func makeReport(_ kind: ReportKind, at now: TimeInterval) -> CrossyDuelReportBody {
        let body = makeReport()
        lastSent = LastSent(score: body.score, deaths: body.deaths, at: now)
        inFlight = true
        retryPending = nil
        switch kind {
        case .goal: goalReported = true
        case .cap: capReported = true
        case .postGrace: postGraceReported = true
        case .ready, .change, .heartbeat: break
        }
        return body
    }

    /// 낸 보고가 닿지 못했다 — 다음 걸음에(최소 틈 0.25초 뒤) 다시 낸다. goal · cap · postGrace 는 깃발을 되돌려 같은 종류로
    /// 다시 나가게 한다(그대로 두면 다음 하트비트 3초까지 결승 보고가 늦다). 값은 누계라 다시 보내도 안전하다.
    package mutating func reportNeedsRetry(_ kind: ReportKind) {
        guard !serverClosed else { return }
        switch kind {
        case .goal: goalReported = false
        case .cap: capReported = false
        case .postGrace: postGraceReported = false
        case .ready, .change, .heartbeat: break
        }
        if lastSent == nil { return }
        retryPending = kind
    }

    /// 마지막으로 낸 보고의 답이 왔다(또는 멎어서 버렸다) — 다음 보고를 낼 수 있다.
    package mutating func reportSettled() {
        inFlight = false
    }

    /// 나가 있는 보고가 `reportStallSeconds` 넘게 답이 없다.
    package func reportStalled(at now: TimeInterval) -> Bool {
        guard inFlight, let at = lastSent?.at else { return false }
        return now - at >= Self.reportStallSeconds
    }

    /// 서버가 `stale` 등으로 알려 준 저장 seq 를 따라잡는다(다음 보고가 그보다 크게).
    package mutating func adoptServerSeq(_ serverSeq: Int) {
        seq = max(seq, serverSeq)
    }

    /// 응답의 `me.score` 가 로컬 엔진 점수보다 크면 엔진을 그 줄로 다시 세운다(v1.1 CC-22 — 같은 계정 재개 · 엔진 되감김).
    /// 판이 흐르는 중일 때만(시작 전 · 얼음 · 100 도달 뒤엔 그대로). 다시 세웠으면 true.
    @discardableResult
    package mutating func catchUp(serverScore: Int, serverDeaths: Int) -> Bool {
        guard isLive, serverScore > game.score, serverScore < goal, game.phase != .result else { return false }
        game.restore(row: serverScore, score: serverScore, deaths: max(serverDeaths, game.deaths))
        return true
    }

    /// 다음 보고 본문(seq + 1). 값은 로컬 엔진 누계.
    package mutating func makeReport() -> CrossyDuelReportBody {
        seq += 1
        return CrossyDuelReportBody(seq: seq, score: game.score, deaths: game.deaths)
    }

    /// 앱을 다시 켰을 때 서버 me 값으로 이어 선다 — 같은 씨앗 엔진을 부활 자리 규칙으로 줄 `score` 에 세우고(`game.restore`)
    /// `started = true` 를 박는다(v1.1 CC-2 — `advance` 의 첫 `game.begin()` 을 건너뛰게). 판 시계는 다음 `advance` 시각부터 흐른다
    /// (그 사이 흐른 판 시간은 따라잡지 않는다 — 경주 시계는 서버다). 이미 연 판이면 아무것도 안 한다.
    package mutating func resume(score: Int, deaths: Int, seq: Int) {
        guard !started, !serverClosed else { return }
        let clamped = min(max(0, score), max(0, goal - 1))
        game.restore(row: clamped, score: clamped, deaths: max(0, deaths))
        started = true
        advancedTo = nil
        self.seq = max(self.seq, seq)
    }
}
