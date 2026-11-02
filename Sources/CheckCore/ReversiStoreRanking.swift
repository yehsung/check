import Foundation

// 아잉 뒤집기 승점 순위(승 − 패) — 스토어 확장과 값 타입. 계약은 설계서 FLIP/SPEC.md §3.4(reversi_ranking) · §4.4.
// 틀은 체스 `ChessStoreRanking`: 60초 주기 · 창 보일 때 한 번 · 내 판 끝난 순간 한 번 · `myRankConsistentWithRecord`.
// 이 파일은 **C1 뼈대**다 — 조회 몸통은 C2 가 채운다.

/// 순위표 한 줄. 순위·순서는 **서버 값 그대로**(재정렬 금지).
package nonisolated struct ReversiRankEntry: Identifiable, Equatable, Sendable {
    package let id: String
    /// 서버가 매긴 순위(동률은 같은 숫자, 다음은 건너뛴다 — rank()).
    package let rank: Int
    package let user: ReversiUser
    package let wins: Int
    package let losses: Int
    package let draws: Int
    /// 승점 = 승 − 패. 서버 값 그대로.
    package let points: Int

    package init(id: String, rank: Int, user: ReversiUser, wins: Int, losses: Int, draws: Int, points: Int) {
        self.id = id
        self.rank = rank
        self.user = user
        self.wins = wins
        self.losses = losses
        self.draws = draws
        self.points = points
    }
}

/// 내 순위 한 줄. `rank` 는 **0판이면 nil**(순위 밖) — 전적은 그래도 있다.
package nonisolated struct ReversiMyRank: Equatable, Sendable {
    package let rank: Int?
    package let wins: Int
    package let losses: Int
    package let draws: Int
    package let points: Int

    package init(rank: Int?, wins: Int, losses: Int, draws: Int, points: Int) {
        self.rank = rank
        self.wins = wins
        self.losses = losses
        self.draws = draws
        self.points = points
    }
}

/// 순위표 전체. **`entries` 는 서버 순서 그대로**. `recordSince` 는 전적 컷(없으면 nil — 캡션을 안 단다).
package nonisolated struct ReversiRanking: Equatable, Sendable {
    package let entries: [ReversiRankEntry]
    package let me: ReversiMyRank?
    package let recordSince: Date?

    package init(entries: [ReversiRankEntry], me: ReversiMyRank?, recordSince: Date?) {
        self.entries = entries
        self.me = me
        self.recordSince = recordSince
    }
}

extension ReversiStore {
    /// 순위표 한 번(`rankingEnabled` 이 꺼져 있으면 나가지 않는다). — C2 가 채운다.
    package func refreshRanking() async {}
}
