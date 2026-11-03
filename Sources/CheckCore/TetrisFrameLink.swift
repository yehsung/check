import Foundation

// 테트리스 대결 Broadcast 전환 — 판 표시 프레임의 **순수 장부**(맥·폰 공용). 명세: docs/plan/tetris-broadcast/SPEC.md §4·§5·§6·§10·§11.
//
// 1초마다 나가던 상대 판 표시만 판 전용 비공개 채널(`tetris:<match>`)의 웹소켓 Broadcast 로 옮기고, DB 보고(`tetris_report`)는
// "3초 체크포인트 + 준비·공격·탑아웃 즉시"로 줄인다. **양쪽 다 프레임이 실제로 오가는 것을 확인했을 때만** 줄이고, 조금이라도
// 어긋나면 지금의 1초 보고로 돌아온다. 이 파일은 그 판정의 전부이고 소켓·스토어·화면을 모른다.
//
//   서버 state.frames ─ noteServerFrames ─┐
//   보고 실패 streak ─ noteReportFailureStreak ─┤
//   관전자 수 ─ noteWatchers ─────────────────┼→ conditions(at:) 조건 7개 → reportInterval(at:)  1초 | 3초
//   상대 프레임 ─ receive(_:at:) ──────────────┤   (상승은 프레임 3장 연속 · 하강은 즉시)
//   소켓 사건 ─ apply(_:at:jitter:) ───────────┘
//   판 루프 ─ socketCommand(at:matchStartedAt:jitter:) → 열기 · 닫기(멈춤 10초 · 재시도 1·2·4초 최대 3회)
//          ─ frameDue(at:live:attackSent:) → makeFrame(...)   1초 + 공격 즉시(0.25초) · 초당 4장
//          ─ shouldHintSync(at:opponentAttackTotal:)         ring 유실 복구 — 앞 힌트가 풀린 뒤에만 한 번
//   DB 응답 ─ mergedDisplay(dbSeq:db:)                         DB 가 표시를 되감지 않게
//
// ── 불변식(§3) ──
//  · 프레임은 **표시 전용**이다. 승패·루비·공격 대기열·재개 어느 것도 프레임 값을 근거로 삼지 않는다. 그래서 이 타입에는
//    `heldOpponentSeq`·`opponentAttackTotal` 을 올리는 길이 **없다**(§4 ★) — 공격 누계는 힌트 판정에 읽기만 한다(D4).
//  · 판정이 모자라면 언제나 **1초 쪽으로** 넘어진다. 프레임 경로가 통째로 죽으면 지금과 똑같이 돈다.
//
// ── 시계는 주입받는다 ──
// `at:` 인자는 전부 로컬 **단조** 시계의 초다(`TetrisDuelSession` 과 같은 눈금 — 스토어의 `uptime()`). 벽시계는 프레임 번호의
// 시작값(`frameBase`) 한 곳에만 들어오고 그것도 밖에서 준다. 재시도 지터도 주입한다(`RealtimeLink` 와 같은 `(Double) -> Double`).
// Kotlin(`core/rules/.../tetris/`)으로 1:1 옮기게 두었다 — 지터 함수 하나와 `[String: Any]` 해석 말고는 정수·실수·문자열·열거뿐이다.
// ★ Kotlin 으로 옮길 때 `f` 는 Long 이다(벽시계 ms 라 Int 32비트를 넘는다).

// MARK: - 프레임 본문

/// 프레임 한 장(이벤트 `frame`, 명세 §4 표). **누계 원칙**: 한 장이 그 순간의 전체 표시 상태다 — 차분이 없고 재생도 필요 없다.
/// 잃어버리면 다음 장이 같은 사실을 더 새로 싣는다(지금 보고와 같은 원칙 — `TetrisDuelSession.makeReport`).
package struct TetrisFrame: Equatable, Sendable {
    /// 브로드캐스트 이벤트 이름(안쪽 payload 의 `event`).
    package static let event = "frame"
    /// 형식 버전. 모르는 값이면 받는 쪽이 버린다.
    package static let formatVersion = 1

    /// `v` — 형식 버전.
    package var version: Int
    /// `u` — 보낸 사람(uuid 소문자). 받는 쪽은 내 판의 상대가 아니면 버린다.
    package var sender: String
    /// `s` — 보낸 쪽의 마지막 보고 번호(`duel.seq`). 순서 키 ①.
    package var seq: Int
    /// `f` — 프레임 번호. 시작값은 벽시계 ms(`TetrisFrameLink.init` 의 `frameBase`)이고 한 장마다 1씩 오른다. 순서 키 ②.
    package var frame: Int
    /// `b` — 보이는 판 200글자(`TetrisDuelBoard.encode`).
    package var board: String
    /// `l` — 지운 줄 누계(표시용).
    package var lines: Int
    /// `g` — 보낸 공격 누계. **힌트 전용**이다(§6) — 대기열에 넣지 않는다.
    package var attackSent: Int
    /// `p` — 대기 방해 줄(현재값, 표시용).
    package var pending: Int
    /// `h` — 보낸 쪽이 **내 프레임**을 마지막으로 받은 뒤 흐른 ms. 받은 적 없으면 -1. §5 조건 4(양방향 확인)의 재료다.
    package var heardAgoMs: Int

    package init(sender: String, seq: Int, frame: Int, board: String, lines: Int, attackSent: Int, pending: Int,
                 heardAgoMs: Int, version: Int = TetrisFrame.formatVersion) {
        self.version = version
        self.sender = sender
        self.seq = seq
        self.frame = frame
        self.board = board
        self.lines = lines
        self.attackSent = attackSent
        self.pending = pending
        self.heardAgoMs = heardAgoMs
    }

    /// 송신 본문(`RealtimeFrame.broadcast(…payload:)` 에 그대로 싣는다). **키 이름을 바꾸지 마라** — 받는 쪽 `decode` 와 한 짝이고,
    /// Kotlin 클라가 같은 글자를 읽는다.
    package var payload: [String: Any] {
        ["v": version, "u": sender, "s": seq, "f": frame, "b": board,
         "l": lines, "g": attackSent, "p": pending, "h": heardAgoMs]
    }

    /// 받은 본문 → 프레임. 모양만 본다(누가 보냈는지 · 순서는 `TetrisFrameLink.receive` 몫).
    ///
    /// 거부 순서: `v` 가 정수가 아니면 `.malformed`, 1 이 아니면 `.unknownVersion`(다음 형식은 칸이 다를 수 있어 먼저 본다) →
    /// 칸 누락·타입 오류·음수는 `.malformed` → 판 글자가 서버 CHECK 모양이 아니면 `.invalidBoard`.
    /// 모르는 키는 무시한다 — 운영 `realtime` 이 저장할 때 `id` 를 덧붙인 전례가 있다(메모리 realtime-send-adds-id).
    package static func decode(payload: [String: Any]) -> Result<TetrisFrame, TetrisFrameRejection> {
        guard let version = integer(payload["v"]) else { return .failure(.malformed) }
        guard version == formatVersion else { return .failure(.unknownVersion) }
        guard let sender = payload["u"] as? String, !sender.isEmpty,
              let seq = integer(payload["s"]), seq >= 0,
              let frame = integer(payload["f"]), frame >= 0,
              let board = payload["b"] as? String,
              let lines = integer(payload["l"]), lines >= 0,
              let attackSent = integer(payload["g"]), attackSent >= 0,
              let pending = integer(payload["p"]), pending >= 0,
              let heardAgoMs = integer(payload["h"]), heardAgoMs >= -1
        else { return .failure(.malformed) }
        guard TetrisDuelBoard.isValid(board) else { return .failure(.invalidBoard) }
        return .success(TetrisFrame(sender: sender, seq: seq, frame: frame, board: board, lines: lines,
                                    attackSent: attackSent, pending: pending, heardAgoMs: heardAgoMs, version: version))
    }

    /// JSON **정수**만 읽는다. 불리언(`true` 는 NSNumber 1 로도 읽힌다)·소수·문자열은 nil — 타입이 다른 프레임은 버린다.
    static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber else { return nil }
        if CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }
        if CFNumberIsFloatType(number) { return nil }
        return number.intValue
    }
}

/// 받은 프레임을 버린 까닭. 버린 프레임은 **아무것도 바꾸지 않는다**(표시·증거·힌트 장부 모두).
package enum TetrisFrameRejection: Error, Equatable, Sendable {
    /// 칸이 없다 · 타입이 다르다(정수 자리에 문자열·불리언·소수) · 음수(`h` 는 -1 까지).
    case malformed
    /// `v` 가 1 이 아니다.
    case unknownVersion
    /// `b` 가 서버 CHECK 모양이 아니다(정확히 200글자 · `.IJLOSTZG`).
    case invalidBoard
    /// `u` 가 내 판의 상대가 아니다.
    case notOpponent
    /// 순서 판정에서 졌다(중복 · 뒤집혀 늦게 온 옛 프레임).
    case stale
    /// 끝난 판에 늦게 닿았다(§4 — 끝난 판의 판·줄은 마지막으로 **받은** 프레임에서 멈춘다).
    case matchFinished
}

// MARK: - 판정 · 명령 어휘

/// §5 의 "3초로 줄여도 되는 조건" 일곱 개. **하나라도 거짓이면 1초다.** 칸마다 따로 두는 까닭: 로그 · 시험이 어느 조건이
/// 떨어뜨렸는지 말할 수 있어야 한다(조건 하나를 지워도 다른 조건이 같은 결론을 내 시험이 초록인 일을 막는다).
package struct TetrisFrameConditions: Equatable, Sendable {
    /// 1. 서버가 이 판의 프레임을 켰다(`state.frames.on` — 서버 스위치 + 양쪽 자리 능력).
    package var serverOn: Bool
    /// 2. 프레임 소켓이 join 됐다.
    package var joined: Bool
    /// 3. 상대 프레임을 받은 지 2.5초 이내다.
    package var heardRecently: Bool
    /// 4. 그 프레임의 `h` 가 0~2500 이다(상대도 내 프레임을 듣고 있다 — 한쪽 방향만 살면 상대 표시가 3초로 벌어진다).
    package var opponentHearsMe: Bool
    /// 5. 보고 실패 streak 가 0 이다(실패·멎음 뒤에는 1초로 재시도한다 — 공격 보고 실패 복구의 핵심, §6).
    package var reportsHealthy: Bool
    /// 6. 관전자가 없다(D2 — 관전자가 있으면 그 판의 대국자는 DB 1초로 돌아간다).
    package var noWatchers: Bool
    /// 7. 위 조건이 프레임 3장 연속 참이었다(상승 쪽 히스테리시스).
    package var steady: Bool

    package var allHold: Bool {
        serverOn && joined && heardRecently && opponentHearsMe && reportsHealthy && noWatchers && steady
    }
}

/// 프레임 소켓의 상태(§10). 소켓 자체는 다음 갈래(`TetrisFrameChannel`)가 들고, 여기는 "지금 무엇을 해야 하나"만 판정한다.
package enum TetrisFrameSocketPhase: Equatable, Sendable {
    /// 열지 않았다(서버가 아직 안 켰다 · 서버가 껐다).
    case idle
    /// 열었고 join 답을 기다린다.
    case connecting
    /// join 됐다(조건 2).
    case joined
    /// 닫혔고 이 시각(로컬 단조 초)에 다시 연다.
    case retrying(at: TimeInterval)
    /// 이 판에서는 다시 열지 않는다. 남은 판은 DB 1초다.
    case stopped(TetrisFrameStopReason)
}

/// 이 판에서 프레임 소켓을 다시 열지 않는 까닭.
package enum TetrisFrameStopReason: Equatable, Sendable {
    /// RLS 가 토픽을 거절했다 — 재시도로 **절대** 안 낫는다(`RealtimeTransport.classifyJoinError` 주석). 돌리면 판 끝까지 인가 검사만 는다.
    case unauthorized
    /// "Too many messages per second" 류 — 프로젝트 전체 한도에 닿았다. 다시 이으면 초인종까지 같이 닫힌다(§15).
    case rateLimited
    /// 판당 재시도 3회를 다 썼다(만료 토큰 재시도 1회를 다 쓴 경우 포함).
    case exhausted
    /// 판이 끝났다.
    case finished
}

/// 프레임 소켓이 닫힌 까닭. 사유마다 재시도가 다르다(§10 — 검토에서 추가).
package enum TetrisFrameCloseCause: Equatable, Sendable {
    /// RLS 거절 → 재시도 없음.
    case unauthorized
    /// 토큰 만료 → 토큰을 새로 받아 **한 번만**.
    case expiredToken
    /// 한도 초과 → 그 판은 다시 잇지 않는다.
    case rateLimited
    /// 멈춤 조건(§5) — 시작 10초 동안 증거가 없거나 증거가 끊긴 지 10초. 재시도 규칙을 탄다.
    case noEvidence
    /// 그 밖의 끊김(네트워크 · `phx_close` · `phx_error` · 하트비트 무응답) → 재시도 규칙을 탄다.
    case lost

    /// 전송자 사건 → 닫힘 사유. 닫힘이 아닌 사건(`opened`·`joined`·`broadcast`·`heartbeatAck`)은 nil.
    /// `system` 오류는 `RealtimeFrame.decode` 가 `.joinRejected` 로 접어 오므로(그 계약은 그대로다) 문구로 한도 초과를 가른다.
    package static func classify(_ event: RealtimeTransportEvent) -> TetrisFrameCloseCause? {
        switch event {
        case .opened, .joined, .broadcast, .heartbeatAck:
            return nil
        case .joinRejected(.unauthorized):
            return .unauthorized
        case .joinRejected(.expiredToken):
            return .expiredToken
        case .joinRejected(.unknown(let reason)):
            // "Too many messages per second" · "Too many joins per second" 등 — 한도 문구는 전부 다시 잇지 않는다.
            let lowered = reason.lowercased()
            return lowered.contains("too many") || lowered.contains("toomany") ? .rateLimited : .lost
        case .closed, .heartbeatTimedOut:
            return .lost
        }
    }
}

/// 판 루프가 소켓에게 시킬 일. 링크는 스스로 아무것도 하지 않는다(`RealtimeEffect` 와 같은 규칙).
package enum TetrisFrameSocketCommand: Equatable, Sendable {
    case none
    /// 이 토픽(`state.frames.topic` 글자 그대로, 접두사 `realtime:` 없음)으로 private join 을 연다.
    /// `refreshToken` 이 참이면 토큰을 **새로 받은 뒤** 연다(만료 토큰 재시도 — §10).
    case connect(topic: String, refreshToken: Bool)
    /// 소켓을 닫는다(이미 닫힌 소켓이어도 부른다 — 세대를 넘겨 늦은 콜백을 막는다).
    case disconnect
}

/// 상대 판 표시 한 벌(§4 병합의 입출력). 준비·탑아웃·승패·`end_reason` 은 여기 없다 — **언제나 DB** 다.
package struct TetrisOpponentDisplay: Equatable, Sendable {
    package var board: String?
    package var lines: Int
    package var pending: Int
    /// 표시용 보낸 공격 누계. 프레임이 이기면 두 값의 max 다. **공격 흡수의 입력이 아니다**(그건 DB 누계 `opponentAttackTotal`).
    package var attackSent: Int

    package init(board: String?, lines: Int, pending: Int, attackSent: Int) {
        self.board = board
        self.lines = lines
        self.pending = pending
        self.attackSent = attackSent
    }
}

// MARK: - 링크

/// 한 판의 프레임 장부(판마다 새로 만든다). 값 타입이고 동기이며 순수하다 — I/O 0, 시계 읽기 0, 난수 0.
package struct TetrisFrameLink: Equatable, Sendable {

    // MARK: 확정 상수

    /// 평상시 체크포인트 주기(D1). 정본은 보고 쪽 상수 하나다(`TetrisDuelSession.checkpointSeconds`).
    package static let checkpointSeconds = TetrisDuelSession.checkpointSeconds
    /// 조건이 하나라도 거짓일 때의 주기 = 지금의 1초 하트비트.
    package static let fallbackSeconds = TetrisDuelSession.heartbeatSeconds
    /// 조건 3 — 상대 프레임을 받은 지 이 초 이내.
    package static let heardWithinSeconds: TimeInterval = 2.5
    /// 조건 4 — 상대가 보낸 `h` 의 상한(ms, 포함).
    package static let heardWithinMs = 2_500
    /// 조건 7 — 연속으로 참이어야 하는 프레임 수.
    package static let steadyFrameCount = 3
    /// 평상시 프레임 간격.
    package static let frameIntervalSeconds: TimeInterval = 1.0
    /// 공격으로 곧바로 보내는 프레임의 최소 간격(보고와 같은 바닥).
    package static let defaultMinFrameGapSeconds = TetrisDuelSession.minReportGapSeconds
    /// 어떤 1초 창에도 이보다 많이 보내지 않는다(§15 — 초당 이벤트 한도는 **프로젝트 전체**에 걸린다).
    package static let maxFramesPerSecond = 4
    /// ring 유실 힌트 — 프레임 `g` 가 DB 누계보다 큰 상태가 이만큼 이어져야 조회한다(§6).
    package static let hintDelaySeconds: TimeInterval = 1.0
    /// 멈춤 조건 — 판 시작(또는 이 연결 시도) 뒤 · 마지막 증거 뒤 이만큼 증거가 없으면 소켓을 닫는다(§5).
    package static let evidenceTimeoutSeconds: TimeInterval = 10
    /// 판당 재시도 상한(§10). 시도마다 서버 인가 검사 1회이고 인가 풀이 2다.
    package static let maxRetries = 3
    /// 재시도 지연 — full jitter, 천장 1·2·4초, 바닥 0.25초(`BackoffPolicy` 를 그대로 쓴다. 초인종 링과 같은 모양).
    package static let retryPolicy = BackoffPolicy(base: 1.0, factor: 2.0, cap: 4.0, floor: 0.25)

    // MARK: 신원

    /// 나(보내는 사람 `u`). 소문자로 접어 둔다 — Swift `UUID().uuidString` 은 대문자라 그대로 비교하면 늘 어긋난다.
    package let me: String
    /// 내 판의 상대(받는 프레임의 `u` 와 견준다).
    package let opponent: String

    // MARK: 입력(스토어가 바뀔 때마다 넣는다)

    /// 서버가 내려 준 토픽(`state.frames` 가 켜졌을 때만). nil = 꺼짐(조건 1 거짓).
    package private(set) var topic: String?
    /// 보고 실패 streak(조건 5 의 재료). 스토어의 `reportFailureStreak` 와 같은 값이어야 한다.
    package private(set) var reportFailureStreak: Int
    /// 내 판의 관전자 수(조건 6 의 재료, `state.watchers`).
    package private(set) var watchers: Int
    /// 서버가 판을 닫았다. 이후로는 프레임을 보내지도 받지도 않고 소켓을 다시 열지 않는다.
    package private(set) var finished: Bool

    // MARK: 소켓

    package private(set) var socket: TetrisFrameSocketPhase
    /// 이 판에서 쓴 재시도 횟수(최대 `maxRetries`). 연결에 성공해도 되돌리지 않는다 — **판당** 상한이다.
    package private(set) var retriesUsed: Int
    /// 만료 토큰 재시도를 이미 썼다(판당 1회).
    package private(set) var expiredRetryUsed: Bool
    /// 다음 연결은 토큰을 새로 받은 뒤 연다.
    package private(set) var needsFreshToken: Bool
    /// 지금 연결 시도를 시작한 시각(멈춤 조건의 기준 하나).
    package private(set) var attemptStartedAt: TimeInterval?

    // MARK: 받는 쪽 장부

    /// 마지막으로 **받아들인** 상대 프레임. `heldOpponentSeq` 와 섞지 마라(§4 ★) — 이 값은 표시 병합과 판정에만 쓴다.
    package private(set) var lastFrame: TetrisFrame?
    /// 그 프레임을 받은 로컬 **단조** 시각. "상대 연결 확인 중"(5초)의 재료이기도 하다 — 스토어가 DB 침묵과 `uptime − 이 값` 중 작은 쪽을
    /// 보인다(`opponentSilenceSeconds`). 벽시계로 들면 기기 시계가 뒤로 갈 때 옛 수신 시각이 앞날에 남아 끊긴 상대를 가린다(11-03 검토 F2).
    package private(set) var lastFrameAt: TimeInterval?
    /// 조건 3·4 를 함께 만족한 마지막 프레임을 받은 시각(멈춤 조건의 증거).
    package private(set) var lastEvidenceAt: TimeInterval?
    /// 조건 1~6 이 참인 채로 받은 연속 프레임 수(조건 7).
    package private(set) var steadyStreak: Int

    // MARK: 힌트 장부(§6)

    /// 지금 재고 있는 상대 `g` 값과 그 값을 처음 본 시각.
    package private(set) var hintCandidate: Int?
    package private(set) var hintCandidateSince: TimeInterval?
    /// 마지막으로 힌트 조회를 낸 `g` 값. DB 누계가 이 값에 닿기 전(힌트가 안 풀렸다)에는 새 `g` 로도 다시 묻지 않는다.
    package private(set) var hintedAttack: Int?

    // MARK: 보내는 쪽 장부

    /// 다음 프레임 번호(`f`).
    package private(set) var nextFrameNumber: Int
    package private(set) var lastSentAt: TimeInterval?
    /// 마지막 프레임에 실은 공격 누계(공격 즉시 판정의 기준).
    package private(set) var lastSentAttack: Int
    /// 최근 보낸 시각(최대 `maxFramesPerSecond` 개, 오래된 것부터) — 초당 상한의 장부.
    package private(set) var recentSends: [TimeInterval]
    /// 공격 즉시 프레임의 최소 간격. 기본 0.25초. **상한(초당 4장)은 이 값과 따로 선다** — D9(하드드롭마다 프레임)를 고르는 날
    /// 이 값을 줄여도 프로젝트 전체 한도를 지키는 쪽은 상한이다.
    package var minFrameGapSeconds: TimeInterval = TetrisFrameLink.defaultMinFrameGapSeconds

    /// - Parameters:
    ///   - me: 내 uuid. 프레임 `u` 로 나간다(소문자로 접는다).
    ///   - opponent: 이 판의 상대 uuid.
    ///   - frameBase: 첫 프레임 번호 = **이 링크를 만들 때의 벽시계 ms**. 그래야 다시 연 프로세스(재개)나 같은 프로세스에서
    ///     다시 만든 링크의 첫 프레임이 옛 프레임보다 크다(§4 순서 판정 — `s` 는 재개에서 옛 값 이하일 수 있다).
    ///     프레임은 초당 4장 이하라 벽시계(초당 1000)를 따라잡지 못한다.
    package init(me: String, opponent: String, frameBase: Int) {
        self.me = me.lowercased()
        self.opponent = opponent.lowercased()
        topic = nil
        reportFailureStreak = 0
        watchers = 0
        finished = false
        socket = .idle
        retriesUsed = 0
        expiredRetryUsed = false
        needsFreshToken = false
        attemptStartedAt = nil
        lastFrame = nil
        lastFrameAt = nil
        lastEvidenceAt = nil
        steadyStreak = 0
        hintCandidate = nil
        hintCandidateSince = nil
        hintedAttack = nil
        nextFrameNumber = max(0, frameBase)
        lastSentAt = nil
        lastSentAttack = 0
        recentSends = []
    }

    // MARK: - 입력

    /// 응답마다 `state.frames` 를 넣는다. 꺼지면(null · on 거짓 · 토픽 이상) 조건 1 이 곧바로 거짓이고, 다음 `socketCommand` 가 닫는다.
    package mutating func noteServerFrames(_ frames: TetrisFramesRow?) {
        let next = frames?.activeTopic
        if next == nil { steadyStreak = 0 }
        topic = next
    }

    /// 보고 실패 streak 가 바뀔 때마다 넣는다. 0 이 아니면 곧바로 1초이고, 0 으로 돌아와도 프레임 3장을 다시 모아야 3초다.
    package mutating func noteReportFailureStreak(_ streak: Int) {
        reportFailureStreak = max(0, streak)
        if reportFailureStreak > 0 { steadyStreak = 0 }
    }

    /// 관전자 수(`state.watchers`)가 바뀔 때마다 넣는다. 관전자가 붙으면 곧바로 1초다(D2).
    package mutating func noteWatchers(_ count: Int) {
        watchers = max(0, count)
        if watchers > 0 { steadyStreak = 0 }
    }

    /// 서버가 판을 닫았다(`applyState` 의 끝난 판 가지). **이 자리에서 닫아라** — 끝난 판은 `discardDuel` 을 안 거치고,
    /// `clearMatch` 는 사용자가 결과를 접을 때나 돈다(§10, 닫기 누락 = 연결 누수).
    package mutating func finish() -> TetrisFrameSocketCommand {
        let wasOpen = isOpen
        finished = true
        steadyStreak = 0
        socket = .stopped(.finished)
        return wasOpen ? .disconnect : .none
    }

    // MARK: - 소켓

    /// 판 루프가 걸음마다 묻는다: 지금 소켓을 열까 · 닫을까.
    /// - Parameter matchStartedAt: 판 시작의 로컬 단조 시각(`duel.startAt`). nil(카운트다운 전)이면 멈춤 시계가 돌지 않는다.
    package mutating func socketCommand(at now: TimeInterval, matchStartedAt: TimeInterval?,
                                        jitter: (Double) -> Double) -> TetrisFrameSocketCommand {
        if finished {
            return finish()
        }
        guard let topic else {
            // 서버가 껐다(롤백 1단계 스위치). 재시도 예산은 그대로 둔다 — 다시 켜지면 새로 연다.
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

    /// 전송자 사건을 넣는다. 닫힘이면 사유별로 재시도를 정하고 `.disconnect` 를 돌려준다.
    /// 이미 처리한 닫힘(예: `system` 오류 뒤 따라오는 `phx_close`)은 두 번 세지 않는다.
    package mutating func apply(_ event: RealtimeTransportEvent, at now: TimeInterval,
                                jitter: (Double) -> Double) -> TetrisFrameSocketCommand {
        if event == .joined {
            if socket == .connecting { socket = .joined }
            return .none
        }
        guard let cause = TetrisFrameCloseCause.classify(event) else { return .none }
        guard isOpen else { return .none }
        close(cause, at: now, jitter: jitter)
        return .disconnect
    }

    private var isOpen: Bool { socket == .connecting || socket == .joined }

    private mutating func startAttempt(topic: String, at now: TimeInterval) -> TetrisFrameSocketCommand {
        socket = .connecting
        attemptStartedAt = now
        steadyStreak = 0
        let refresh = needsFreshToken
        needsFreshToken = false
        return .connect(topic: topic, refreshToken: refresh)
    }

    /// 멈춤 조건(§5): 기준 = max(판 시작, 이 연결 시도 시작, 마지막 증거). 기준에서 10초 동안 증거가 없으면 닫는다.
    /// 이 규칙이 없으면 쓰기가 거절됐거나(`ack:false` 라 보내는 쪽은 모른다) 상대가 듣지 않는 소켓에 판 끝까지 쓴다.
    private func evidenceTimedOut(at now: TimeInterval, matchStartedAt: TimeInterval?) -> Bool {
        guard let start = matchStartedAt, start.isFinite else { return false }
        var reference = start
        if let attempt = attemptStartedAt { reference = max(reference, attempt) }
        if let evidence = lastEvidenceAt { reference = max(reference, evidence) }
        return now - reference >= Self.evidenceTimeoutSeconds
    }

    private mutating func close(_ cause: TetrisFrameCloseCause, at now: TimeInterval, jitter: (Double) -> Double) {
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

    // MARK: - 받기

    /// 상대 프레임 한 장. nil = 받아들였다(표시·증거·힌트 장부가 바뀐다). 버린 프레임은 아무것도 바꾸지 않는다.
    ///
    /// 순서 판정(§4): `f` 가 마지막으로 받은 값보다 크거나 **`s` 가 더 크면** 받는다. `(s, f)` 사전식이 아닌 까닭 — 재개한 프로세스의
    /// `s` 는 DB 값에서 잇는데 앞 프로세스의 보고가 저장되지 못했으면 옛 프레임의 `s` 이하다. `f` 는 벽시계에서 시작해 첫 프레임부터
    /// 통과하고, 시계를 뒤로 돌린 경우는 `s` 쪽이 살린다.
    @discardableResult
    package mutating func receive(_ frame: TetrisFrame, at now: TimeInterval) -> TetrisFrameRejection? {
        guard !finished else { return .matchFinished }
        guard frame.sender.lowercased() == opponent else { return .notOpponent }
        if let last = lastFrame, !(frame.frame > last.frame || frame.seq > last.seq) { return .stale }

        let continuous = lastFrameAt.map { now - $0 <= Self.heardWithinSeconds } ?? false
        lastFrame = frame
        lastFrameAt = now

        let hearsMe = (0...Self.heardWithinMs).contains(frame.heardAgoMs)
        if hearsMe { lastEvidenceAt = now }
        if hearsMe, topic != nil, socket == .joined, reportFailureStreak == 0, watchers == 0 {
            // 앞 프레임과 2.5초 넘게 벌어졌으면 그 사이 조건 3 이 거짓이었다 — 1장부터 다시 센다.
            steadyStreak = continuous ? steadyStreak + 1 : 1
        } else {
            steadyStreak = 0
        }

        if frame.attackSent != hintCandidate {
            hintCandidate = frame.attackSent
            hintCandidateSince = now
        }
        return nil
    }

    // MARK: - 보고 주기

    /// 조건 7개(§5). 순수 판정 — 상태를 바꾸지 않는다.
    package func conditions(at now: TimeInterval) -> TetrisFrameConditions {
        TetrisFrameConditions(
            serverOn: topic != nil && !finished,
            joined: socket == .joined,
            heardRecently: lastFrameAt.map { now - $0 <= Self.heardWithinSeconds } ?? false,
            opponentHearsMe: lastFrame.map { (0...Self.heardWithinMs).contains($0.heardAgoMs) } ?? false,
            reportsHealthy: reportFailureStreak == 0,
            noWatchers: watchers == 0,
            steady: steadyStreak >= Self.steadyFrameCount)
    }

    /// 지금 보고 주기. 조건 7개가 모두 참이면 3초 체크포인트, 하나라도 거짓이면 **즉시** 1초.
    /// 한 줄 요약: "상대가 내 프레임을 듣는다는 증거가 2.5초 넘게 없으면 DB 1초". `TetrisDuelSession.reportReason(at:heartbeat:)` 에 넣는다.
    package func reportInterval(at now: TimeInterval) -> TimeInterval {
        conditions(at: now).allHold ? Self.checkpointSeconds : Self.fallbackSeconds
    }

    // MARK: - 보내기

    /// 지금 프레임을 보낼 때인가(§5 프레임 보내기 조건).
    /// - Parameters:
    ///   - live: 구동기가 이 판의 것이고 `duel.isLive`(시작했고 · 안 끝났고 · 탑아웃 전). 카운트다운 · 탑아웃 뒤에는 보내지 않는다 —
    ///     탑아웃은 RPC 로 곧바로 간다.
    ///   - attackSent: 지금 내 보낸 공격 누계(`duel.game.attackSentTotal`). 늘었으면 1초를 안 기다린다(최소 간격만 지킨다).
    package func frameDue(at now: TimeInterval, live: Bool, attackSent: Int) -> Bool {
        guard live, !finished, topic != nil, socket == .joined else { return false }
        if recentSends.count >= Self.maxFramesPerSecond, let oldest = recentSends.first,
           now - oldest < 1.0 { return false }
        guard let last = lastSentAt else { return true }
        let since = now - last
        if since >= minFrameGapSeconds, attackSent > lastSentAttack { return true }
        return since >= Self.frameIntervalSeconds
    }

    /// 프레임 한 장을 만들고 보내는 쪽 장부(번호 · 시각 · 실은 공격 · 초당 창)를 넘긴다. `h` 는 여기서 잰다.
    /// - Parameters: 전부 지금 내 판의 값이다(`seq` = `duel.seq`, `board` = `TetrisDuelBoard.encode(duel.game)`).
    package mutating func makeFrame(at now: TimeInterval, seq: Int, board: String, lines: Int, attackSent: Int,
                                    pending: Int) -> TetrisFrame {
        let frame = TetrisFrame(sender: me, seq: max(0, seq), frame: nextFrameNumber, board: board,
                                lines: max(0, lines), attackSent: max(0, attackSent), pending: max(0, pending),
                                heardAgoMs: heardAgoMs(at: now))
        nextFrameNumber += 1
        lastSentAt = now
        lastSentAttack = attackSent
        recentSends.append(now)
        if recentSends.count > Self.maxFramesPerSecond { recentSends.removeFirst(recentSends.count - Self.maxFramesPerSecond) }
        return frame
    }

    /// 상대 프레임을 마지막으로 받은 뒤 흐른 ms(받은 적 없으면 -1). 32비트 안으로 자른다(Kotlin Int).
    private func heardAgoMs(at now: TimeInterval) -> Int {
        guard let at = lastFrameAt else { return -1 }
        let ms = (now - at) * 1000
        guard ms.isFinite else { return -1 }
        return Int(min(max(0, ms.rounded()), Double(Int32.max)))
    }

    // MARK: - 공격 힌트(§6)

    /// ring 유실 복구: 상대 프레임의 `g` 가 DB 누계(`opponentAttackTotal`)보다 큰 상태가 1초 이어지면 `tetris_state` 를 한 번 부른다.
    /// **참을 돌려준 순간 그 값을 썼다고 적는다**(묻는 것이 곧 쓰는 것). 그 힌트가 **풀리기 전**(DB 누계가 그 값에 닿기 전)에는 같은 `g`
    /// 는 물론 새 `g` 로도 다시 참이 없다 — 안 풀리면 체크포인트(내 다음 보고 응답, ≤3초)에 맡긴다.
    ///
    /// 1초를 기다리는 까닭: 프레임이 공격 보고 커밋보다 먼저 닿으면 바로 조회해도 옛값이 오고, 뒤이은 ring 이 또 조회를 부른다.
    /// 풀린 뒤에만 다시 묻는 까닭: 서버가 공격 누계를 상한으로 자르므로 조작한 클라는 `g > DB` 를 영구히 만들 수 있다. "1초에 1회"면
    /// 그동안 매초, "같은 g 에 한 번"이면 `g` 를 프레임마다 1씩 올리는 위조에 거의 매초(15초에 13번 — 11-03 검토 F1) `tetris_state` 가
    /// 나간다. 정직한 판에서는 힌트로 읽은 응답이 곧 그 값을 싣고 오므로 다음 공격의 힌트를 막지 않는다. 위조는 판당 한 번이다.
    package mutating func shouldHintSync(at now: TimeInterval, opponentAttackTotal: Int) -> Bool {
        guard !finished, let candidate = hintCandidate, let since = hintCandidateSince,
              candidate > opponentAttackTotal,
              hintedAttack.map({ opponentAttackTotal >= $0 }) ?? true,
              now - since >= Self.hintDelaySeconds
        else { return false }
        hintedAttack = candidate
        return true
    }

    // MARK: - 표시 병합(§4)

    /// DB 응답이 표시를 **되감지 않게**. 체크포인트 응답의 DB 판은 프레임보다 최대 3초 옛것이다.
    ///
    /// 규칙: 마지막으로 받은 프레임의 `s` ≥ DB `seq` 면 판·줄·대기 줄은 프레임 값, 보낸 공격은 두 값의 max. DB seq 가 더 크면 DB 가
    /// 이긴다. **끝난 판도 판·줄은 같은 규칙이다** — 승자는 끝난 뒤 보고를 안 내 DB 판·줄이 최대 3초 옛값으로 남고, 끝나면 DB 로 덮는
    /// 규칙이면 결과 화면의 숫자가 줄어든다(끝난 뒤 닿은 프레임은 `receive` 가 버리므로 마지막으로 받은 프레임에서 멈춘다).
    /// 다만 **끝난 장부의 보낸 공격 수는 DB 다** — 공격은 정산의 정본이 DB 누계이고, 위조 프레임의 `g` 가 결과 화면에 남지 않게 한다
    /// (11-03 검토 F5 — 스토어는 끝난 판 응답에서 DB 행 값으로 한 번 더 못 박는다: `mergedOpponentBoard(settledAttack:)`).
    /// 판 중에는 표시뿐이라 max 그대로 둔다(명세 §9 — 표시 위조는 받아들인 전제). 준비·탑아웃·승패·`end_reason` 은 이 함수에 없다.
    package func mergedDisplay(dbSeq: Int, db: TetrisOpponentDisplay) -> TetrisOpponentDisplay {
        guard let frame = lastFrame, frame.seq >= dbSeq else { return db }
        return TetrisOpponentDisplay(board: frame.board, lines: frame.lines, pending: frame.pending,
                                     attackSent: finished ? db.attackSent : max(db.attackSent, frame.attackSent))
    }
}
