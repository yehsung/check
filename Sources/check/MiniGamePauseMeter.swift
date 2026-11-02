import CheckCore
import Foundation

// 시계를 읽는 자리는 이 파일뿐이다. 미니게임 창 콘텐츠(MiniGamePanel.swift)는 시계를 읽지 않는다는 계약이 있어서
// (V0246 · V0367 — 창이 매초 다시 그려지지 않게) 기본값으로 여기서 지금 시각을 넣는다.

/// 맥 정지 상한의 **시계**. 판이 얼어 있던 시간을 **벽시계로** 판 단위로 쌓는다 — 3-2-1 도 든다.
///
/// 폰(`GamesMiniGameHub.pausedSecondsUsed`)과 같은 규칙이다. 전에는 감시가 카드(`.paused`)가 떠 있는 동안만
/// 1초를 자고 나서 1을 더했다. 그래서 카드 → 3-2-1 → ESC(다시 카드) 왕복에서 3-2-1 시간이 안 쌓이고, 1초 안에
/// 넘긴 카드 구간은 0초로 버려져, 판을 얼린 채 몇 시간을 둬도 5분 상한이 안 찼다(토큰이 TTL 을 넘겨 점수를 잃는다).
/// 끊는 것은 여전히 카드가 떠 있을 때뿐이다(`armPauseWatchdog`) — 3-2-1 을 누른 사람의 판은 3초 안에 안 끊는다.
struct MiniGamePauseMeter: Equatable {
    private(set) var banked: TimeInterval = 0
    private(set) var frozenSince: Date?

    /// 지금 정지 상태를 알린다. 얼기 시작하면 시각을 적고, 풀리면 그 구간을 쌓는다. 같은 상태를 거듭 알려도 값이 같다.
    mutating func observe(_ state: MiniGamePauseState, at now: Date = Date()) {
        if state.isFrozen {
            if frozenSince == nil { frozenSince = now }
        } else if let since = frozenSince {
            banked += max(0, now.timeIntervalSince(since))
            frozenSince = nil
        }
    }

    /// 이 판에서 지금까지 얼어 있던 초(쌓인 것 + 지금 얼어 있는 구간).
    func used(at now: Date = Date()) -> TimeInterval {
        banked + (frozenSince.map { max(0, now.timeIntervalSince($0)) } ?? 0)
    }

    func isOver(at now: Date = Date()) -> Bool { used(at: now) >= TimeInterval(MiniGamePauseState.pauseLimitSeconds) }
}
