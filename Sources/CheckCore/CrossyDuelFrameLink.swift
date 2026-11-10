import Foundation

// 1:1 길건너 판 표시 프레임의 **순수 장부**(SPEC v1.3 §3.4 B0~B4 · §8.4 — `TetrisFrameLink` 틀). 소켓·스토어·화면을 모른다.
//
// 판 중 상대 점수 표시만 판 전용 비공개 채널(`crossy_duel:<match>`)의 Broadcast 로 받고, DB 보고는 "판정용 체크포인트(3초)
// + 100 도달·3분 즉시"로 둔다. **양쪽 프레임이 실제로 오가는 것이 확인될 때만** 체크포인트로 줄이고, 어긋나면 곧바로
// 대체 길(DB `report_ms` 1초)이다. 테트리스와 달리 관전 조건(`noWatchers`)이 없다(관전 없음, Q1).
//
// 불변식(TB §3): 프레임은 **표시 전용**이다 — 승패·루비·판정·재개 어느 것도 프레임 값을 근거로 삼지 않는다.
// 판정이 모자라면 언제나 **대체 길 쪽으로** 넘어진다.
//
// 본은 `TetrisFrameLink` 다(소켓 명령 · 재시도 · 멈춤 10초 · 받기 순서 · 3장 히스테리시스 — 같은 규칙). 다른 자리:
//  · 관전 조건 없음 · 공격 힌트 없음(길건너엔 ring 으로 오는 공격이 없다).
//  · 프레임 보내기는 "점수·죽음이 바뀌면 직전 프레임 뒤 0.5초 틈, 안 바뀌면 1초"(B3) — 0.5초 틈이 곧 초당 2장 상한이다.
//  · 표시 병합은 점수 하나: 끝나지 않은 판에서 `max(프레임 sc, DB opponent.score)`(B3 — DB 응답이 표시를 되감지 않는다).

// MARK: - 프레임 본문

/// 상대 반투명 그림자 한 점(11-10 대표 "부하 엄청 심하지 않다면 구현하자" — 제보 테트리스장인). 두 사람은 같은 씨앗의 같은 길을
/// 달리므로 이 위치를 **내 판에 그대로** 겹쳐 그린다. 프레임의 선택 칸이라 옛 앱은 모르는 키로 무시한다(받는 쪽 `decode` 도 없으면 nil).
package struct CrossyDuelGhost: Equatable, Sendable {
    /// 가로 자리(칸 단위, 통나무 위면 소수 — 0.01 칸으로 실어 보낸다).
    package var x: Double
    /// 몇째 줄(앞이 +).
    package var row: Int
    package var facing: CrossyGame.Direction
    /// 죽어 있는 동안(부활 전) — 그림자를 숨긴다.
    package var dead: Bool

    package init(x: Double, row: Int, facing: CrossyGame.Direction, dead: Bool) {
        self.x = x
        self.row = row
        self.facing = facing
        self.dead = dead
    }

    /// 판 값에서 지금 내 그림자(뛰는 중이면 그 순간의 자리).
    package init(game: CrossyGame) {
        let visual = game.playerVisual
        self.init(x: visual.x, row: Int(visual.row.rounded()), facing: game.player.facing, dead: game.death != nil)
    }

    /// 보낼 만큼 움직였는가(0.05 칸 · 줄 · 방향 · 생사).
    package func moved(from other: CrossyDuelGhost?) -> Bool {
        guard let other else { return true }
        return other.row != row || other.facing != facing || other.dead != dead || abs(other.x - x) >= 0.05
    }
}

/// 프레임 한 장(이벤트 `frame`, 형식 버전 1 — B2 표 그대로). 한 장이 그 순간의 전체 표시 상태다(누계).
package struct CrossyDuelFrame: Equatable, Sendable {
    /// Broadcast 이벤트 이름.
    package static let event = "frame"
    package static let formatVersion = 1
    /// 점수 상한(넘으면 버림 — B2).
    package static let maxScore = 100

    /// `v`.
    package var version: Int
    /// `u` — 보낸 사람 uuid.
    package var sender: String
    /// `s` — 보낸 쪽 마지막 DB 보고 seq(순서 키 ①).
    package var seq: Int
    /// `f` — 프레임 번호(순서 키 ②). 시작값 = 프로세스 시작 벽시계 ms, 이후 +1.
    package var frame: Int
    /// `sc` — 점수(0…100, 로컬 엔진 값).
    package var score: Int
    /// `d` — 죽은 횟수.
    package var deaths: Int
    /// `h` — 상대 프레임을 마지막으로 받은 뒤 ms, 없으면 −1(양방향 확인).
    package var heardAgoMs: Int
    /// `gx` · `gr` · `gf` · `gd` — 반투명 그림자 위치(선택 칸, 없으면 nil — 0.3.80 이하 앱).
    package var ghost: CrossyDuelGhost?

    package init(sender: String, seq: Int, frame: Int, score: Int, deaths: Int, heardAgoMs: Int,
                 version: Int = CrossyDuelFrame.formatVersion, ghost: CrossyDuelGhost? = nil) {
        self.version = version
        self.sender = sender
        self.seq = seq
        self.frame = frame
        self.score = score
        self.deaths = deaths
        self.heardAgoMs = heardAgoMs
        self.ghost = ghost
    }

    /// 송신 본문. **키 이름을 바꾸지 마라** — 받는 쪽 `decode` 와 한 짝이다.
    package var payload: [String: Any] {
        var body: [String: Any] = ["v": version, "u": sender, "s": seq, "f": frame, "sc": score, "d": deaths, "h": heardAgoMs]
        if let ghost {
            body["gx"] = Int((ghost.x * 100).rounded())
            body["gr"] = ghost.row
            body["gf"] = ghost.facing.rawValue
            body["gd"] = ghost.dead ? 1 : 0
        }
        return body
    }

    /// 받은 본문 → 프레임. 모양만 본다(누가 보냈는지 · 순서는 `CrossyDuelFrameLink.receive` 몫).
    /// 모르는 키는 무시한다(운영 realtime 이 `id` 를 덧붙인다 — 메모리 realtime-send-adds-id).
    package static func decode(payload: [String: Any]) -> Result<CrossyDuelFrame, CrossyDuelFrameRejection> {
        guard let version = integer(payload["v"]) else { return .failure(.malformed) }
        guard version == formatVersion else { return .failure(.unknownVersion) }
        guard let sender = payload["u"] as? String, !sender.isEmpty,
              let seq = integer(payload["s"]), seq >= 0,
              let frame = integer(payload["f"]), frame >= 0,
              let score = integer(payload["sc"]),
              let deaths = integer(payload["d"]),
              let heardAgoMs = integer(payload["h"]), heardAgoMs >= -1
        else { return .failure(.malformed) }
        guard (0...maxScore).contains(score), deaths >= 0 else { return .failure(.outOfRange) }
        // 그림자는 선택 칸 — 모양이 어긋나면 그림자만 버리고 프레임(점수 표시)은 받는다.
        var ghost: CrossyDuelGhost?
        if let gx = integer(payload["gx"]), let gr = integer(payload["gr"]), abs(gx) <= 100_000, abs(gr) <= 100_000,
           let gf = (payload["gf"] as? String).flatMap(CrossyGame.Direction.init(rawValue:)) {
            ghost = CrossyDuelGhost(x: Double(gx) / 100, row: gr, facing: gf, dead: integer(payload["gd"]) == 1)
        }
        return .success(CrossyDuelFrame(sender: sender, seq: seq, frame: frame, score: score, deaths: deaths,
                                        heardAgoMs: heardAgoMs, version: version, ghost: ghost))
    }

    /// JSON **정수**만 읽는다(불리언 · 소수 · 문자열은 nil).
    static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber else { return nil }
        if CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }
        if CFNumberIsFloatType(number) { return nil }
        return number.intValue
    }
}

/// 받은 프레임을 버린 까닭. 버린 프레임은 아무것도 바꾸지 않는다.
package enum CrossyDuelFrameRejection: Error, Equatable, Sendable {
    /// 칸이 없다 · 타입이 다르다 · 음수(`h` 는 −1 까지).
    case malformed
    /// `v` 가 1 이 아니다.
    case unknownVersion
    /// `sc` 가 0…100 밖 · `d` 가 음수(B2).
    case outOfRange
    /// `u` 가 내 판의 상대가 아니다.
    case notOpponent
    /// 순서 판정에서 졌다(`f`·`s` 둘 다 마지막 이하).
    case stale
    /// 끝난 판에 늦게 닿았다.
    case matchFinished
}

// MARK: - 판정 · 명령 어휘

/// 프레임 확인 조건(B4 ①~⑤ + 3장 연속). **하나라도 거짓이면 대체 길이다.**
package struct CrossyDuelFrameConditions: Equatable, Sendable {
    /// ① state `frames.on`.
    package var serverOn: Bool
    /// ② 채널 join.
    package var joined: Bool
    /// ③ 상대 프레임을 받은 지 2.5초 이내.
    package var heardRecently: Bool
    /// ④ 그 프레임 `h` ∈ [0, 2500].
    package var opponentHearsMe: Bool
    /// ⑤ 보고 연속 실패 0.
    package var reportsHealthy: Bool
    /// 위 다섯이 3장 연속(올라갈 때만 히스테리시스 — 내려갈 땐 즉시).
    package var steady: Bool

    package init(serverOn: Bool = false, joined: Bool = false, heardRecently: Bool = false,
                 opponentHearsMe: Bool = false, reportsHealthy: Bool = false, steady: Bool = false) {
        self.serverOn = serverOn
        self.joined = joined
        self.heardRecently = heardRecently
        self.opponentHearsMe = opponentHearsMe
        self.reportsHealthy = reportsHealthy
        self.steady = steady
    }

    package var allHold: Bool {
        serverOn && joined && heardRecently && opponentHearsMe && reportsHealthy && steady
    }
}

/// 프레임 소켓의 상태.
package enum CrossyDuelFrameSocketPhase: Equatable, Sendable {
    case idle
    case connecting
    case joined
    /// 닫혔고 이 시각(로컬 단조 초)에 다시 연다.
    case retrying(at: TimeInterval)
    /// 이 판에서는 다시 열지 않는다(남은 판은 대체 길).
    case stopped(CrossyDuelFrameStopReason)
}

/// 이 판에서 프레임 소켓을 다시 열지 않는 까닭.
package enum CrossyDuelFrameStopReason: Equatable, Sendable {
    /// RLS 거절 — 재시도 없음.
    case unauthorized
    /// 한도 초과 — 다시 잇지 않는다.
    case rateLimited
    /// 재시도 3회를 다 썼다.
    case exhausted
    /// 판이 끝났다.
    case finished
}

/// 프레임 소켓이 닫힌 까닭(사유마다 재시도가 다르다).
package enum CrossyDuelFrameCloseCause: Equatable, Sendable {
    case unauthorized
    case expiredToken
    case rateLimited
    /// 판 시작 뒤 10초 증거 0 또는 끊긴 지 10초.
    case noEvidence
    case lost

    /// 전송자 사건 → 닫힘 사유(테트리스 `TetrisFrameCloseCause.classify` 와 같은 판정). 닫힘이 아닌 사건은 nil.
    package static func classify(_ event: RealtimeTransportEvent) -> CrossyDuelFrameCloseCause? {
        switch event {
        case .opened, .joined, .broadcast, .heartbeatAck:
            return nil
        case .joinRejected(.unauthorized):
            return .unauthorized
        case .joinRejected(.expiredToken):
            return .expiredToken
        case .joinRejected(.unknown(let reason)):
            let lowered = reason.lowercased()
            return lowered.contains("too many") || lowered.contains("toomany") ? .rateLimited : .lost
        case .closed, .heartbeatTimedOut:
            return .lost
        }
    }
}

/// 판 루프가 소켓에게 시킬 일. 장부는 스스로 아무것도 하지 않는다.
package enum CrossyDuelFrameSocketCommand: Equatable, Sendable {
    case none
    /// 이 토픽(`state.frames.topic` 글자 그대로)으로 private join 을 연다. `refreshToken` 이면 토큰을 새로 받은 뒤.
    case connect(topic: String, refreshToken: Bool)
    case disconnect
}

// MARK: - 장부

/// 한 판의 프레임 장부(판마다 새로 만든다). 값 타입 · 동기 · 순수 — I/O 0, 시계 읽기 0, 난수 0.
/// `at:` 인자는 전부 로컬 **단조** 시계의 초(`CrossyDuelSession` 과 같은 눈금).
package struct CrossyDuelFrameLink: Equatable, Sendable {
    // MARK: 상수(B3 · B4)

    /// 상대 프레임 "최근" 문턱.
    package static let heardWithinSeconds: TimeInterval = 2.5
    package static let heardWithinMs = 2_500
    /// 상승 히스테리시스(장).
    package static let steadyFrameCount = 3
    /// 변화 없을 때 프레임 간격.
    package static let frameIntervalSeconds: TimeInterval = 1.0
    /// 변화가 있을 때 직전 프레임과의 최소 틈(초당 2장 상한).
    package static let minFrameGapSeconds: TimeInterval = 0.5
    /// 내 그림자가 움직였을 때 직전 프레임과의 최소 틈(초당 5장 상한 — 반투명 상대, 11-10).
    package static let ghostFrameGapSeconds: TimeInterval = 0.2
    /// 멈춤 문턱(판 시작 뒤 증거 0 · 끊긴 지).
    package static let evidenceTimeoutSeconds: TimeInterval = 10
    /// 재시도 1·2·4초 최대 3회.
    package static let retryDelays: [TimeInterval] = [1, 2, 4]
    package static let maxRetries = 3
    /// 체크포인트 자르기 [2000, 5000] ms.
    package static let checkpointRangeMs = 2_000...5_000
    /// 키가 없을 때의 대체 길 · 체크포인트(ms — §3.1 · B5).
    package static let defaultReportMs = 2_000
    package static let defaultCheckpointMs = 3_000

    // MARK: 상태

    /// 내 uuid(소문자).
    package let me: String
    /// 상대 uuid(소문자) — 이 사람이 보낸 프레임만 받는다.
    package let opponent: String
    /// 서버가 켠 토픽(꺼졌으면 nil).
    package private(set) var topic: String?
    /// 대체 길 보고 간격(ms — state `report_ms`, 스토어가 자른 값).
    package private(set) var reportMs: Int
    /// 확인됨 체크포인트(ms — state `checkpoint_ms` 를 [2000, 5000] 으로 자른 값).
    package private(set) var checkpointMs: Int
    package private(set) var reportFailureStreak: Int
    package private(set) var finished: Bool
    package private(set) var socket: CrossyDuelFrameSocketPhase
    package private(set) var retriesUsed: Int
    /// 만료 토큰 재시도를 이미 썼다(판당 1회) · 다음 연결은 토큰을 새로 받은 뒤 연다.
    package private(set) var expiredRetryUsed: Bool
    package private(set) var needsFreshToken: Bool
    /// 지금 연결 시도를 시작한 시각(멈춤 조건의 기준 하나).
    package private(set) var attemptStartedAt: TimeInterval?
    /// 조건 ③④ 를 함께 만족한 마지막 프레임을 받은 시각(멈춤 조건의 증거).
    package private(set) var lastEvidenceAt: TimeInterval?
    /// 마지막으로 받은 상대 프레임.
    package private(set) var lastFrame: CrossyDuelFrame?
    /// 상대 프레임을 받은 단조 시각(`opponentQuiet` 재료 — §8.4).
    package private(set) var opponentHeardAt: TimeInterval?
    package private(set) var steadyStreak: Int
    /// 다음에 보낼 프레임 번호(`f`).
    package private(set) var nextFrameNumber: Int
    package private(set) var lastSentAt: TimeInterval?
    /// 직전 프레임에 실은 점수·죽음(변화 판정).
    package private(set) var lastSentScore: Int?
    package private(set) var lastSentDeaths: Int?
    /// 직전 프레임에 실은 내 그림자(움직임 판정).
    package private(set) var lastSentGhost: CrossyDuelGhost?

    /// - Parameter frameBase: `f` 시작값 — 프로세스 시작 벽시계 ms(프로세스당 한 번 정한 값, 스토어가 넘긴다).
    package init(me: String, opponent: String, frameBase: Int) {
        self.me = me.lowercased()
        self.opponent = opponent.lowercased()
        self.topic = nil
        self.reportMs = Self.defaultReportMs
        self.checkpointMs = Self.defaultCheckpointMs
        self.reportFailureStreak = 0
        self.finished = false
        self.socket = .idle
        self.retriesUsed = 0
        self.expiredRetryUsed = false
        self.needsFreshToken = false
        self.attemptStartedAt = nil
        self.lastEvidenceAt = nil
        self.lastFrame = nil
        self.opponentHeardAt = nil
        self.steadyStreak = 0
        self.nextFrameNumber = max(0, frameBase)
        self.lastSentAt = nil
        self.lastSentScore = nil
        self.lastSentDeaths = nil
    }

    // MARK: 입력

    /// 재시도 지연 — full jitter, 천장 1·2·4초, 바닥 0.25초(테트리스 · 초인종 링과 같은 모양 — `retryDelays` 가 그 천장이다).
    package static let retryPolicy = BackoffPolicy(base: 1.0, factor: 2.0, cap: 4.0, floor: 0.25)

    /// 서버 state 의 `frames` · `report_ms` · `checkpoint_ms` 를 응답마다 넣는다. 꺼지면(null · on 거짓 · 토픽 이상 — **1차 서버처럼 키가
    /// 없어도**) 조건 ① 이 곧바로 거짓이고 다음 `socketCommand` 가 닫는다. `checkpoint_ms` 는 [2000, 5000] 으로 자르고 없으면 3000.
    package mutating func noteServerFrames(_ frames: CrossyDuelFramesRow?, reportMs: Int? = nil, checkpointMs: Int? = nil) {
        let next = frames?.activeTopic
        if next == nil { steadyStreak = 0 }
        topic = next
        if let reportMs { self.reportMs = reportMs }
        let checkpoint = checkpointMs ?? Self.defaultCheckpointMs
        self.checkpointMs = min(max(checkpoint, Self.checkpointRangeMs.lowerBound), Self.checkpointRangeMs.upperBound)
    }

    /// 보고 실패 streak 가 바뀔 때마다 넣는다. 0 이 아니면 곧바로 대체 길이고, 0 으로 돌아와도 프레임 3장을 다시 모아야 확인이다.
    package mutating func noteReportFailureStreak(_ streak: Int) {
        reportFailureStreak = max(0, streak)
        if reportFailureStreak > 0 { steadyStreak = 0 }
    }

    /// 판이 끝났다 — 소켓을 닫고 다시 열지 않는다(끝난 판 가지에서 **이 자리에서** 닫아라 — 닫기 누락 = 연결 누수).
    package mutating func finish() -> CrossyDuelFrameSocketCommand {
        let wasOpen = isOpen
        finished = true
        steadyStreak = 0
        socket = .stopped(.finished)
        return wasOpen ? .disconnect : .none
    }

    /// 판 루프가 걸음마다 묻는다: 지금 소켓을 열까 · 닫을까.
    /// - Parameter matchStartedAt: 판 시작의 로컬 단조 시각(`duel.startAt`). nil(카운트다운 전)이면 멈춤 시계가 돌지 않는다.
    package mutating func socketCommand(at now: TimeInterval, matchStartedAt: TimeInterval?,
                                       jitter: (Double) -> Double) -> CrossyDuelFrameSocketCommand {
        if finished { return finish() }
        guard let topic else {
            // 서버가 껐다(되돌리기 1단계 스위치 · 1차 서버). 재시도 예산은 그대로 둔다 — 다시 켜지면 새로 연다.
            let wasOpen = isOpen
            switch socket {
            case .connecting, .joined, .retrying: socket = .idle
            case .idle, .stopped: break
            }
            steadyStreak = 0
            return wasOpen ? .disconnect : .none
        }
        switch socket {
        case .idle:
            return startAttempt(topic: topic, at: now)
        case .retrying(let at):
            guard now >= at else { return .none }
            return startAttempt(topic: topic, at: now)
        case .connecting, .joined:
            guard evidenceTimedOut(at: now, matchStartedAt: matchStartedAt) else { return .none }
            close(.noEvidence, at: now, jitter: jitter)
            return .disconnect
        case .stopped:
            return .none
        }
    }

    /// 소켓 사건. 닫힘이면 사유별로 재시도를 정하고 `.disconnect` 를 돌려준다(이미 처리한 닫힘은 두 번 세지 않는다).
    package mutating func apply(_ event: RealtimeTransportEvent, at now: TimeInterval,
                                jitter: (Double) -> Double) -> CrossyDuelFrameSocketCommand {
        if event == .joined {
            if socket == .connecting { socket = .joined }
            return .none
        }
        guard let cause = CrossyDuelFrameCloseCause.classify(event), isOpen else { return .none }
        close(cause, at: now, jitter: jitter)
        return .disconnect
    }

    private var isOpen: Bool { socket == .connecting || socket == .joined }

    private mutating func startAttempt(topic: String, at now: TimeInterval) -> CrossyDuelFrameSocketCommand {
        socket = .connecting
        attemptStartedAt = now
        steadyStreak = 0
        let refresh = needsFreshToken
        needsFreshToken = false
        return .connect(topic: topic, refreshToken: refresh)
    }

    /// 멈춤 조건(B4): 기준 = max(판 시작, 이 연결 시도 시작, 마지막 증거). 기준에서 10초 동안 증거(③④)가 없으면 닫는다.
    private func evidenceTimedOut(at now: TimeInterval, matchStartedAt: TimeInterval?) -> Bool {
        guard let start = matchStartedAt, start.isFinite else { return false }
        var reference = start
        if let attempt = attemptStartedAt { reference = max(reference, attempt) }
        if let evidence = lastEvidenceAt { reference = max(reference, evidence) }
        return now - reference >= Self.evidenceTimeoutSeconds
    }

    private mutating func close(_ cause: CrossyDuelFrameCloseCause, at now: TimeInterval, jitter: (Double) -> Double) {
        steadyStreak = 0
        switch cause {
        case .unauthorized:
            socket = .stopped(.unauthorized)
            return
        case .rateLimited:
            socket = .stopped(.rateLimited)
            return
        case .expiredToken:
            guard !expiredRetryUsed else {
                socket = .stopped(.exhausted)
                return
            }
            expiredRetryUsed = true
            needsFreshToken = true
        case .noEvidence, .lost:
            break
        }
        guard retriesUsed < Self.maxRetries else {
            socket = .stopped(.exhausted)
            return
        }
        retriesUsed += 1
        socket = .retrying(at: now + Self.retryPolicy.delay(attempt: retriesUsed, jitter: jitter))
    }

    /// 상대 프레임 한 장. nil = 받아들였다(표시 · 증거 · 히스테리시스가 바뀐다). 버린 프레임은 아무것도 바꾸지 않는다.
    /// 순서(B2): `f` 가 마지막보다 크거나 **`s` 가 더 크면** 받는다(재개한 프로세스의 `f` 는 벽시계에서 시작해 옛 장보다 크다).
    @discardableResult
    package mutating func receive(_ frame: CrossyDuelFrame, at now: TimeInterval) -> CrossyDuelFrameRejection? {
        guard !finished else { return .matchFinished }
        guard frame.sender.lowercased() == opponent else { return .notOpponent }
        guard (0...CrossyDuelFrame.maxScore).contains(frame.score), frame.deaths >= 0 else { return .outOfRange }
        if let last = lastFrame, !(frame.frame > last.frame || frame.seq > last.seq) { return .stale }

        let continuous = opponentHeardAt.map { now - $0 <= Self.heardWithinSeconds } ?? false
        lastFrame = frame
        opponentHeardAt = now

        let hearsMe = (0...Self.heardWithinMs).contains(frame.heardAgoMs)
        if hearsMe { lastEvidenceAt = now }
        if hearsMe, topic != nil, socket == .joined, reportFailureStreak == 0 {
            // 앞 프레임과 2.5초 넘게 벌어졌으면 그 사이 조건 ③ 이 거짓이었다 — 1장부터 다시 센다.
            steadyStreak = continuous ? steadyStreak + 1 : 1
        } else {
            steadyStreak = 0
        }
        return nil
    }

    // MARK: 판정

    /// 지금 조건(B4 ①~⑤ + 3장). 순수 판정 — 상태를 바꾸지 않는다.
    package func conditions(at now: TimeInterval) -> CrossyDuelFrameConditions {
        CrossyDuelFrameConditions(
            serverOn: topic != nil && !finished,
            joined: socket == .joined,
            heardRecently: opponentHeardAt.map { now - $0 <= Self.heardWithinSeconds } ?? false,
            opponentHearsMe: lastFrame.map { (0...Self.heardWithinMs).contains($0.heardAgoMs) } ?? false,
            reportsHealthy: reportFailureStreak == 0,
            steady: steadyStreak >= Self.steadyFrameCount)
    }

    /// 보고 간격(초) — 확인됨 = `checkpointMs`(체크포인트), 아니면 `reportMs`(대체 길의 변화 보고 간격, B4).
    package func reportInterval(at now: TimeInterval) -> TimeInterval {
        TimeInterval(conditions(at: now).allHold ? checkpointMs : reportMs) / 1000
    }

    /// 확인됨이면 점수·죽음 변화 보고를 내지 않는다(체크포인트가 싣는다 — B4).
    package func changeReportsSuppressed(at now: TimeInterval) -> Bool {
        conditions(at: now).allHold
    }

    /// 지금 프레임을 보낼 때인가(B3) — 판이 흐르고(`live`) 채널이 join 됐을 때만. 점수·죽음이 바뀌었으면 직전 프레임 뒤 0.5초 틈,
    /// 안 바뀌었으면 1초.
    /// 그림자가 움직였으면(`moved`) 0.2초 틈(초당 5장 상한 — 11-10).
    package func frameDue(at now: TimeInterval, live: Bool, changed: Bool, moved: Bool = false) -> Bool {
        guard live, !finished, topic != nil, socket == .joined else { return false }
        guard let last = lastSentAt else { return true }
        let since = now - last
        if changed, since >= Self.minFrameGapSeconds { return true }
        if moved, since >= Self.ghostFrameGapSeconds { return true }
        return since >= Self.frameIntervalSeconds
    }

    /// 내 그림자가 직전 프레임 뒤로 움직였는가(처음이면 참).
    package func movedSinceLastFrame(_ ghost: CrossyDuelGhost) -> Bool { ghost.moved(from: lastSentGhost) }

    /// 지금 그릴 상대 그림자 — 끝나지 않은 판에서 최근(2.5초 안) 받은 프레임에 실렸을 때만. 죽어 있으면 nil.
    package func opponentGhost(at now: TimeInterval) -> CrossyDuelGhost? {
        guard !finished, let ghost = lastFrame?.ghost, !ghost.dead, let heard = opponentHeardAt,
              now - heard <= Self.heardWithinSeconds else { return nil }
        return ghost
    }

    /// 이 점수·죽음이 직전 프레임과 다른가(처음이면 참).
    package func changedSinceLastFrame(score: Int, deaths: Int) -> Bool {
        lastSentScore != score || lastSentDeaths != deaths
    }

    /// 보낼 프레임을 만든다(`f` +1 · 보낸 시각 · 값 기록). `h` 는 상대 프레임을 받은 뒤 ms(없으면 −1).
    package mutating func makeFrame(at now: TimeInterval, seq: Int, score: Int, deaths: Int,
                                    ghost: CrossyDuelGhost? = nil) -> CrossyDuelFrame {
        let frame = CrossyDuelFrame(sender: me, seq: max(0, seq), frame: nextFrameNumber,
                                    score: min(max(0, score), CrossyDuelFrame.maxScore), deaths: max(0, deaths),
                                    heardAgoMs: heardAgoMs(at: now), ghost: ghost)
        nextFrameNumber += 1
        lastSentAt = now
        lastSentScore = score
        lastSentDeaths = deaths
        if let ghost { lastSentGhost = ghost }
        return frame
    }

    /// 상대 프레임을 마지막으로 받은 뒤 흐른 ms(받은 적 없으면 −1). 32비트 안으로 자른다.
    private func heardAgoMs(at now: TimeInterval) -> Int {
        guard let at = opponentHeardAt else { return -1 }
        let ms = (now - at) * 1000
        guard ms.isFinite else { return -1 }
        return Int(min(max(0, ms.rounded()), Double(Int32.max)))
    }

    /// 상대 트랙 점수 — **끝나지 않은 판에서** `max(프레임 sc, DB opponent.score)`(DB 응답이 표시를 되감지 않는다, B3).
    /// 끝난 판은 DB 값(굳힌 값은 스토어가 `final` 로 넣는다).
    package func mergedOpponentScore(db: Int) -> Int {
        guard !finished, let lastFrame else { return db }
        return max(lastFrame.score, db)
    }
}
