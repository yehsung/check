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
// ★ C1 뼈대: 본문 해석(`CrossyDuelFrame.decode`/`payload`)과 판정 어휘는 있고, 장부 판정은 전부 "확인 안 됨"(대체 길)을 낸다
//   — 소켓을 열지 않고(`socketCommand` = `.none`) 프레임을 받지 않는다. 몸통은 C 의 프레임 걸음이 채운다.

// MARK: - 프레임 본문

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

    package init(sender: String, seq: Int, frame: Int, score: Int, deaths: Int, heardAgoMs: Int,
                 version: Int = CrossyDuelFrame.formatVersion) {
        self.version = version
        self.sender = sender
        self.seq = seq
        self.frame = frame
        self.score = score
        self.deaths = deaths
        self.heardAgoMs = heardAgoMs
    }

    /// 송신 본문. **키 이름을 바꾸지 마라** — 받는 쪽 `decode` 와 한 짝이다.
    package var payload: [String: Any] {
        ["v": version, "u": sender, "s": seq, "f": frame, "sc": score, "d": deaths, "h": heardAgoMs]
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
        return .success(CrossyDuelFrame(sender: sender, seq: seq, frame: frame, score: score, deaths: deaths,
                                        heardAgoMs: heardAgoMs, version: version))
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
        self.lastFrame = nil
        self.opponentHeardAt = nil
        self.steadyStreak = 0
        self.nextFrameNumber = max(0, frameBase)
        self.lastSentAt = nil
        self.lastSentScore = nil
        self.lastSentDeaths = nil
    }

    // MARK: 입력

    /// 서버 state 의 `frames` · `report_ms` · `checkpoint_ms`. C1: 값만 적는다(판정은 C 의 프레임 걸음).
    package mutating func noteServerFrames(_ frames: CrossyDuelFramesRow?, reportMs: Int? = nil, checkpointMs: Int? = nil) {
        topic = frames?.activeTopic
        if let reportMs { self.reportMs = reportMs }
        if let checkpointMs {
            self.checkpointMs = min(max(checkpointMs, Self.checkpointRangeMs.lowerBound), Self.checkpointRangeMs.upperBound)
        }
    }

    package mutating func noteReportFailureStreak(_ streak: Int) {
        reportFailureStreak = max(0, streak)
    }

    /// 판이 끝났다 — 소켓을 닫고 다시 열지 않는다.
    package mutating func finish() -> CrossyDuelFrameSocketCommand {
        finished = true
        socket = .stopped(.finished)
        return .disconnect
    }

    /// 판 루프가 묻는 소켓 명령(열기 · 닫기 · 재시도). C1: 언제나 `.none`(소켓을 열지 않는다 — 대체 길).
    package mutating func socketCommand(at now: TimeInterval, matchStartedAt: TimeInterval?,
                                       jitter: (Double) -> Double) -> CrossyDuelFrameSocketCommand {
        _ = (now, matchStartedAt, jitter)
        return .none
    }

    /// 소켓 사건. C1: 아무것도 바꾸지 않는다.
    package mutating func apply(_ event: RealtimeTransportEvent, at now: TimeInterval,
                                jitter: (Double) -> Double) -> CrossyDuelFrameSocketCommand {
        _ = (event, now, jitter)
        return .none
    }

    /// 상대 프레임 한 장. C1: 모든 프레임을 버린다(표시 전용이라 안전 — 표시는 DB 값 그대로).
    @discardableResult
    package mutating func receive(_ frame: CrossyDuelFrame, at now: TimeInterval) -> CrossyDuelFrameRejection? {
        _ = (frame, now)
        return finished ? .matchFinished : .stale
    }

    // MARK: 판정

    /// 지금 조건(B4). C1: 소켓을 안 여니 언제나 확인 안 됨.
    package func conditions(at now: TimeInterval) -> CrossyDuelFrameConditions {
        _ = now
        return CrossyDuelFrameConditions(serverOn: topic != nil, reportsHealthy: reportFailureStreak == 0)
    }

    /// 보고 간격(초) — 확인됨 = `checkpointMs`, 아니면 `reportMs`(B4).
    package func reportInterval(at now: TimeInterval) -> TimeInterval {
        TimeInterval(conditions(at: now).allHold ? checkpointMs : reportMs) / 1000
    }

    /// 확인됨이면 점수·죽음 변화 보고를 내지 않는다(체크포인트가 싣는다 — B4).
    package func changeReportsSuppressed(at now: TimeInterval) -> Bool {
        conditions(at: now).allHold
    }

    /// 지금 프레임을 보낼 때인가(바뀌면 직전 프레임 뒤 0.5초 틈, 안 바뀌면 1초 — B3). C1: 언제나 false.
    package func frameDue(at now: TimeInterval, live: Bool, changed: Bool) -> Bool {
        _ = (now, live, changed)
        return false
    }

    /// 보낼 프레임을 만든다(`f` +1 · 보낸 시각 · 값 기록). `h` 는 상대 프레임을 받은 뒤 ms(없으면 −1).
    package mutating func makeFrame(at now: TimeInterval, seq: Int, score: Int, deaths: Int) -> CrossyDuelFrame {
        let heard = opponentHeardAt.map { Int(((now - $0) * 1000).rounded()) } ?? -1
        let frame = CrossyDuelFrame(sender: me, seq: seq, frame: nextFrameNumber, score: score, deaths: deaths,
                                    heardAgoMs: max(-1, heard))
        nextFrameNumber += 1
        lastSentAt = now
        lastSentScore = score
        lastSentDeaths = deaths
        return frame
    }

    /// 상대 트랙 점수 — **끝나지 않은 판에서** `max(프레임 sc, DB opponent.score)`(DB 응답이 표시를 되감지 않는다, B3).
    /// 끝난 판은 DB 값(굳힌 값은 스토어가 `final` 로 넣는다).
    package func mergedOpponentScore(db: Int) -> Int {
        guard !finished, let lastFrame else { return db }
        return max(lastFrame.score, db)
    }
}
