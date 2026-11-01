import Foundation

// MARK: - 제출 인편 (맥 v0.3.39 → 폰 1.0.16 에 코어로 옮겼다)
//
// 끝난 판의 점수는 어떤 경우에도 그 자리에서 사라지지 않는다 — 까닭과 사고 기록은 맥 `WorkTimerStoreMiniGame` 머리 주석에 있다.
// 여기 있는 것은 **두 플랫폼이 같아야 하는 규칙뿐**이다: 인편 한 건의 모양(영속 형식) · status 분류 · 백오프 · 다음에 할 일 판정.
// 왕복·영속·문구는 각자의 스토어(맥 `WorkTimerStore` · 폰 `GamesMiniGameHub`)가 맡는다.
//
// ★ 불변식: **그 게임의 인편이 살아 있는 동안 그 게임의 `start_round` 는 나가지 않는다.** 서버가 (사용자, 게임)당 미사용 토큰을
//   한 행만 두고 갈아 끼우므로, 순서가 뒤집히면 인편의 점수가 `no_token` 으로 죽는다. 토큰을 기다리는 인편(`token == nil`)에
//   받아 주는 요청만이 예외다 — 그 게임에 살아 있는 토큰이 없을 때만 나간다(`nextStep`).

/// 아직 서버가 받았다고 확인해 주지 않은 끝난 판 한 건 — **제출 인편**. 영속하므로 타입이다.
package struct MiniGamePendingSubmit: Codable, Equatable, Identifiable {
    package let id: UUID
    package let kind: MiniGameKind
    package let score: Int
    /// 이 판의 토큰. nil 이면 **토큰을 기다리는 인편**이다 — 판이 끝난 순간 토큰이 없었다(왕복이 늦었거나 못 받았다).
    /// 왕복 중이던 응답이나 새 요청이 채운다(`adopt(token:at:)`).
    package var token: String?
    /// 그 토큰을 받은 시각(서버 `started_at` 의 로컬 거울). 수명 판정에 쓴다.
    package var tokenIssuedAt: Date?
    /// 판이 끝난 시각. 토큰이 없는 인편의 수명은 여기서 센다.
    package let recordedAt: Date
    /// 지금까지 실패한 횟수(백오프 단계). 영속한다 — 재시작이 백오프를 0 으로 되돌리지 않게.
    package var attempts: Int
    /// 이 시각 전에는 다시 보내지 않는다(백오프). 영속하지 않는다 — 재시작은 그 자체가 재시도 방아쇠다.
    package var nextRetryAt: Date? = nil
    /// 모르는 status 를 받았다 — **방아쇠**(깨어남·재활성화·창 열기·판 시작·판 끝)가 올 때까지 붙든다. 타이머도 제출 꼬리의
    /// 밀기도 이 인편을 건드리지 않는다(이해 못 한 거절을 두드리지 않는다). 영속하지 않는다 — 재시작은 방아쇠다.
    package var heldUntilTrigger: Bool = false
    /// `no_token` 을 받아 **토큰을 기다리는 인편으로 한 번 되돌렸다.** 영속한다 — 재시작이 이 기회를 새로 주면 안 된다.
    ///
    /// 왜 한 번인가: `no_token` 은 우리가 든 토큰을 서버가 모른다는 뜻이고, 그 원인은 그 사이 `start_round` 가 그 행의 id 를
    /// 갈아 끼운 것이다(2026-09-27 실측: 제출과 `start_round` 가 같은 초에 날아가 `start_round` 가 먼저 닿은 여섯 판).
    /// 불변식이 그 경합을 막지만, 뚫렸을 때 점수를 버리지 않고 **새 토큰을 받아 다시** 올린다 — 서버의 시간 하한은
    /// 그대로 선다(새 토큰의 started_at 부터 다시 재므로 하한만큼 기다려야 통과한다 · 플래피 13점이면 11.63초).
    /// 두 번은 주지 않는다: 계속 `no_token` 이면 원인이 경합이 아니므로 두드려도 같은 답이고, 무한 왕복이 된다.
    package var recoveredFromDeadTokenOnce: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, kind, score, token, tokenIssuedAt, recordedAt, attempts, recoveredFromDeadTokenOnce
    }

    package init(id: UUID, kind: MiniGameKind, score: Int, token: String?, tokenIssuedAt: Date?, recordedAt: Date, attempts: Int,
                 nextRetryAt: Date? = nil, heldUntilTrigger: Bool = false, recoveredFromDeadTokenOnce: Bool = false) {
        self.id = id
        self.kind = kind
        self.score = score
        self.token = token
        self.tokenIssuedAt = tokenIssuedAt
        self.recordedAt = recordedAt
        self.attempts = attempts
        self.nextRetryAt = nextRetryAt
        self.heldUntilTrigger = heldUntilTrigger
        self.recoveredFromDeadTokenOnce = recoveredFromDeadTokenOnce
    }

    /// 이 인편이 죽는 시각. 토큰이 있으면 토큰 발급 시각, 없으면 판이 끝난 시각 — **둘 중 이른 쪽** + TTL. 토큰은 발급
    /// 시각부터 서버 TTL 만큼만 살고, 토큰 없는 인편도 30분이 지나면 다른 날 순위표에 올라갈 수 있어 같은 수명을 준다.
    package func deadline(ttl: TimeInterval) -> Date {
        min(recordedAt, tokenIssuedAt ?? recordedAt).addingTimeInterval(ttl)
    }

    package func isExpired(at now: Date, ttl: TimeInterval) -> Bool { now >= deadline(ttl: ttl) }

    /// 죽은 토큰(`no_token`)을 받은 인편을 **토큰을 기다리는 인편으로 되돌린다.** 점수는 그대로 두고 토큰만 버린다.
    /// 백오프는 0 으로 되돌린다 — 새 토큰을 받는 일은 앞의 실패와 다른 일이다. 표식을 세워 두 번은 오지 않는다.
    package mutating func demoteToTokenWait() {
        token = nil
        tokenIssuedAt = nil
        attempts = 0
        nextRetryAt = nil
        heldUntilTrigger = false
        recoveredFromDeadTokenOnce = true
    }

    /// 토큰을 기다리던 인편이 토큰을 받았다.
    package mutating func adopt(token: String, at now: Date) {
        self.token = token
        tokenIssuedAt = now
        nextRetryAt = nil
    }

    /// 실패 한 번 — 백오프를 한 단계 올린다(n번째 실패 → `delays[n-1]`, 끝은 반복). 얼마나 기다릴지는 **눈먼 고정 간격**뿐이다.
    package mutating func noteFailure(delays: [TimeInterval], at now: Date) {
        attempts += 1
        let step = min(max(attempts - 1, 0), max(delays.count - 1, 0))
        nextRetryAt = now.addingTimeInterval(delays.isEmpty ? 30 : delays[step])
    }
}

/// 제출 응답을 어떻게 읽는가 — 두 플랫폼 공통.
package enum MiniGameSubmitRules {
    /// 인편의 수명(초) = 서버 토큰 TTL(`minigame_round_ttl()` 30분). 넘긴 인편은 토큰이 죽었으므로 읽을 때 버린다.
    package static let pendingTTL: TimeInterval = 30 * 60

    /// 백오프 간격(초). 값 자체는 서버가 준 숫자로 계산하지 않는다(그걸 쓰는 순간 위조 보조 도구다).
    package static let retryDelays: [TimeInterval] = [2, 8, 30]

    /// 서버가 **명시적으로 거절**한 status. 이걸 받으면 그 토큰으로는 영영 못 올리므로 제출 인편을 지운다.
    /// (`token_used` 는 여기 없다 — 그건 **성공**이다. `too_fast` 도 없다 — **재시도 대상**이다.)
    ///
    /// ⚠️ `unauthorized`·`no_profile` 도 여기다. 둘은 **토큰이 아니라 호출자 쪽 거절**이라
    /// `minigame_submit_score` 가 uid·프로필 검사에서 곧장 돌아오고 30분 TTL 판정까지 가지도 않는다 —
    /// 즉 스스로 `token_expired` 로 바뀌지 않는다. 지우지 않으면 인편이 남아 **앱을 켤 때마다 영원히**
    /// 같은 토큰을 다시 보낸다(그 사이 선발급은 인편 가드에 막혀 그 게임의 새 토큰도 못 받는다).
    /// 다만 `deadTokenStatuses` 에는 넣지 않는다 — 그 판이 아니라 호출자가 거절당했다.
    package static let terminalStatuses: Set<String> =
        ["invalid", "no_token", "token_expired", "unauthorized", "no_profile"]

    /// 시간이 흐르면 **같은 토큰으로 통과하는** 거절. `too_fast` 는 토큰을 소모하기 전에 돌아오고(토큰이 살아 있다) 서버가
    /// 재는 경과는 자라기만 한다 — 그래서 인편을 남기고 **백오프 타이머**를 건다.
    /// 모르는 status 는 여기 없다: 남기되 타이머 없이 방아쇠에서만 다시 보낸다 — 이해 못 한 거절을 두드리지는 않되
    /// 점수를 버리지도 않는다(TTL 이 끝을 낸다).
    package static let retryableStatuses: Set<String> = ["too_fast"]

    /// 토큰이 죽어 **그 판은 영영 못 올리는** 거절. terminal 의 부분집합이어야 한다.
    package static let deadTokenStatuses: Set<String> = ["no_token", "token_expired"]
}

/// 한 게임의 인편을 두고 **지금 할 일**.
package enum MiniGamePendingStep: Equatable {
    /// 이 인편을 보낸다(토큰을 실었다).
    case submit(MiniGamePendingSubmit)
    /// 맨 앞 인편에 토큰을 받아 준다(이 게임에 살아 있는 토큰이 없다). 왕복 중이면 그 응답이 오니 부르는 쪽이 건너뛴다.
    case requestToken
    /// 지금은 할 일이 없다(인편이 없거나 · 붙들렸거나 · 백오프 중이다).
    case wait
}

extension Array where Element == MiniGamePendingSubmit {
    /// 이 게임의 인편을 어떻게 밀까. 토큰을 실은 인편은 게임당 하나뿐이다(서버가 미사용 토큰을 한 행만 두므로 둘일 수 없다).
    /// 그 인편이 붙들렸거나 백오프 중이면 이 게임은 통째로 건너뛴다 — 그 인편의 토큰이 살아 있으니 **새 토큰도 청하지 않는다**(불변식).
    package func nextStep(for kind: MiniGameKind, at now: Date) -> MiniGamePendingStep {
        let entries = filter { $0.kind == kind }
        if let ready = entries.first(where: { $0.token != nil }) {
            if ready.heldUntilTrigger { return .wait }
            if let at = ready.nextRetryAt, at > now { return .wait }
            return .submit(ready)
        }
        guard let head = entries.first else { return .wait }
        if head.heldUntilTrigger { return .wait }
        if let at = head.nextRetryAt, at > now { return .wait }
        return .requestToken
    }

    /// 백오프 타이머가 돌아올 시각 — 가장 먼저 돌아오는 인편. TTL 을 넘겨서 돌아오는 재시도는 잡지 않는다(그때는 어차피 읽으면서 버린다).
    package func nextRetryDate(after now: Date, ttl: TimeInterval) -> Date? {
        compactMap { entry -> Date? in
            guard let at = entry.nextRetryAt, at > now, at < entry.deadline(ttl: ttl) else { return nil }
            return at
        }.min()
    }
}
