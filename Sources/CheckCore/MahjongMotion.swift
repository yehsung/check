import Foundation

// 아잉 마작 패 움직임(버림·울기·깡) — 순수 값(SPEC §4.5 '움직임'). 어떤 프레임이든 `now` 하나로 정해진다
// (`ChessMoveFlight` 규약). 응답이 온 **뒤** 시작하고(낙관적 그림 없음 ①), 다른 판·국이면 무시하며, 사건 꼬리가 여럿이면
// `catchUpWindow`(1.5초) 안에 따라잡는다(UX:149). 불투명도는 **이징 전 진행도로만** 정한다(메모리 easing-must-not-drive-opacity —
// 이징이 앞당긴 진행도로 투명도를 깎으면 밀려나기 전에 사라진다).

package nonisolated struct MahjongMotion: Equatable, Sendable {
    /// 움직임 종류.
    package enum Kind: String, Equatable, Hashable, Sendable {
        /// 손 → 강.
        case discard
        /// 남의 강 → 내 부로(치·퐁·대명깡).
        case call
        /// 손 → 부로(암깡·가깡).
        case kan
    }

    /// 탁자 위 자리 — 방위 + 그 자리의 구역.
    package struct Place: Equatable, Hashable, Sendable {
        package enum Area: String, Equatable, Hashable, Sendable { case hand, river, melds }

        package let compass: MahjongCompass
        package let area: Area

        package init(compass: MahjongCompass, area: Area) {
            self.compass = compass
            self.area = area
        }
    }

    /// 한 장 움직임의 기본 길이(초).
    package static let defaultDuration: TimeInterval = 0.24
    /// 사건 꼬리가 여럿일 때 모두 따라잡는 상한(초).
    package static let catchUpWindow: TimeInterval = 1.5

    package let matchID: String
    package let handIndex: Int
    /// 이 움직임을 낳은 사건 seq.
    package let seq: Int
    package let kind: Kind
    package let from: Place
    package let to: Place
    package let startedAt: Date
    package let duration: TimeInterval

    package init(
        matchID: String, handIndex: Int, seq: Int, kind: Kind, from: Place, to: Place, startedAt: Date,
        duration: TimeInterval = MahjongMotion.defaultDuration
    ) {
        self.matchID = matchID
        self.handIndex = handIndex
        self.seq = seq
        self.kind = kind
        self.from = from
        self.to = to
        self.startedAt = startedAt
        self.duration = max(0, duration)
    }

    /// 이징 전 진행도 0…1(시작 전 0 · 끝난 뒤 1). 길이 0 이면 시작 순간 1.
    package func progress(at now: Date) -> Double {
        let elapsed = now.timeIntervalSince(startedAt)
        guard elapsed > 0 else { return 0 }
        guard duration > 0 else { return 1 }
        return min(1, elapsed / duration)
    }

    /// 자리(위치)용 이징 진행도 — 끝에서 느려진다(3차 ease-out). 불투명도에는 쓰지 않는다.
    package func easedProgress(at now: Date) -> Double {
        let t = progress(at: now)
        let inv = 1 - t
        return 1 - inv * inv * inv
    }

    package func isFinished(at now: Date) -> Bool { progress(at: now) >= 1 }

    /// 이 움직임이 지금 그리는 판·국의 것인가(다른 판·국이면 무시).
    package func applies(matchID: String?, handIndex: Int?) -> Bool {
        matchID == self.matchID && handIndex == self.handIndex
    }

    /// 사건 꼬리 `count` 개를 차례로 그릴 때 한 장의 길이 — 모두 합쳐 `catchUpWindow` 를 넘지 않는다.
    package static func duration(forTailCount count: Int) -> TimeInterval {
        guard count > 1 else { return defaultDuration }
        return min(defaultDuration, catchUpWindow / Double(count))
    }
}
