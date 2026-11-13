import Foundation

// 1:1 길건너 순위(Q1 기본안 — `crossy_duel_ranking`, 테트리스 `TetrisDuelRank*` 꼴). SPEC v1.3 §8.3 · §6.3.
// 적재는 테트리스 `loadRanking` 꼴: 주 스위치(`rankingEnabled`) · 도는 중이면 버림(60초 목록이라 합치지 않는다) ·
// PGRST202 → `rankingUnavailable` · 실패는 안내줄로 새지 않는다(판 상태줄을 가린다) — 들고 있던 목록은 지우지 않는다.

/// 순위표 한 줄. 순위는 **서버가 매긴 값**이다.
package nonisolated struct CrossyDuelRankEntry: Identifiable, Equatable, Sendable {
    package let id: String
    package let rank: Int
    package let user: CrossyDuelUser
    package let wins: Int
    package let losses: Int
    package let draws: Int
    /// 승점 = 승 − 패(서버 값).
    package let points: Int

    package init(id: String, rank: Int, user: CrossyDuelUser, wins: Int, losses: Int, draws: Int, points: Int) {
        self.id = id
        self.rank = rank
        self.user = user
        self.wins = wins
        self.losses = losses
        self.draws = draws
        self.points = points
    }
}

/// 내 순위(0판이면 rank nil).
package nonisolated struct CrossyDuelMyRank: Equatable, Sendable {
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

/// 순위표 한 벌.
package nonisolated struct CrossyDuelRankingBoard: Equatable, Sendable {
    package let entries: [CrossyDuelRankEntry]
    package let me: CrossyDuelMyRank?
    package let recordSince: Date?

    package init(entries: [CrossyDuelRankEntry], me: CrossyDuelMyRank?, recordSince: Date?) {
        self.entries = entries
        self.me = me
        self.recordSince = recordSince
    }
}

extension CrossyDuelStore {
    /// 순위표 한 번(60초 주기 — `rankingPollSeconds`). `rankingEnabled` 가 꺼져 있으면 아무것도 안 한다.
    package func refreshRanking() async {
        guard rankingEnabled, host?.session != nil, !rankingInFlight else { return }
        rankingInFlight = true
        let generation = resetGeneration
        defer { if generation == resetGeneration { rankingInFlight = false } }
        lastRankingRequestAt = clock()
        guard let result = await perform({ try await $0.crossyDuelRanking(accessToken: $1) }) else { return }
        switch result {
        case .success(let response):
            applyRanking(response)
        case .failure(let error):
            if isSchemaMissing(error) {
                if !rankingUnavailable { rankingUnavailable = true }
            } else {
                Self.logger.notice("ranking request failed")
            }
        }
    }

    /// 순위 응답을 옮긴다(ok 만 — 값이 같으면 쓰지 않는다).
    package func applyRanking(_ response: CrossyDuelRankingResponse) {
        guard response.status == .ok else {
            Self.logger.notice("ranking refused status=\(response.status.rawValue, privacy: .public)")
            return
        }
        noteServerNow(response.serverNowMs)
        if rankingUnavailable { rankingUnavailable = false }
        let board = Self.rankingBoard(from: response)
        if ranking != board { ranking = board }
    }

    /// 내 판이 끝났다 — 전적이 바뀐 순간 순위도 다시 읽는다(창이 안 보여도 사건에 대한 한 번).
    func noteOwnMatchFinishedForRanking() {
        lastRankingRequestAt = .distantPast
        guard rankingEnabled, host?.session != nil else { return }
        Task { [weak self] in await self?.refreshRanking() }
    }

    /// 응답 → 순위표(순수). **행 순서는 입력 그대로**. id 나 rank 가 빠진 행은 싣지 않는다.
    package nonisolated static func rankingBoard(from response: CrossyDuelRankingResponse) -> CrossyDuelRankingBoard {
        let entries = (response.rows ?? []).compactMap { row -> CrossyDuelRankEntry? in
            guard let rank = row.rank,
                  let id = row.id?.lowercased(), !id.isEmpty else { return nil }
            let user = CrossyDuelUser(id: id, displayName: row.displayName ?? "", avatarURL: row.avatarUrl,
                                      characterID: row.character)
            let wins = row.wins ?? 0
            let losses = row.losses ?? 0
            return CrossyDuelRankEntry(id: id, rank: rank, user: user, wins: wins, losses: losses,
                                       draws: row.draws ?? 0, points: row.points ?? (wins - losses))
        }
        let mine = response.me.map { me -> CrossyDuelMyRank in
            let wins = me.wins ?? 0
            let losses = me.losses ?? 0
            return CrossyDuelMyRank(rank: me.rank, wins: wins, losses: losses, draws: me.draws ?? 0,
                                    points: me.points ?? (wins - losses))
        }
        let since = response.recordSinceMs.flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0 / 1000) : nil }
        return CrossyDuelRankingBoard(entries: entries, me: mine, recordSince: since)
    }
}
