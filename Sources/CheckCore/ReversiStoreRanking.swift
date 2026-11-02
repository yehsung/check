import Foundation

// 아잉 뒤집기 승점 순위(승 − 패) — 스토어 확장과 값 타입. 계약은 설계서 FLIP/SPEC.md §3.4(reversi_ranking) · §4.4.
// 틀은 체스 `ChessStoreRanking`: 60초 주기 · 창 보일 때 한 번 · 내 판 끝난 순간 한 번 · `myRankConsistentWithRecord`.

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
    // MARK: 조회

    /// 순위표 한 번(`rankingEnabled` 이 꺼져 있으면 나가지 않는다). 도는 중이면 **합치지 않고 버린다**
    /// (60초 주기 목록이라 뒤따르는 한 번이 필요 없다). 실패는 안내줄을 만들지 않는다 — 대국 안내를 가리지 않게.
    package func refreshRanking() async {
        guard rankingEnabled, host?.session != nil else { return }
        let runtime = watchRuntime
        guard !runtime.rankingInFlight else { return }
        runtime.rankingInFlight = true
        let generation = resetGeneration
        defer { if generation == resetGeneration { runtime.rankingInFlight = false } }
        runtime.lastRankingRequestAt = clock()
        guard let result = await perform({ try await $0.reversiRanking(accessToken: $1) }) else { return }
        switch result {
        case .success(let response):
            applyRanking(response)
        case .failure(let error):
            if isSchemaMissing(error) {
                // 서버에 reversi_ranking 이 아직 없다. 60초 폴링은 그대로라 서버가 올라오면 저절로 회복한다.
                Self.logger.notice("ranking unavailable — function missing on server")
                if !rankingUnavailable { rankingUnavailable = true }
            } else {
                Self.logger.notice("ranking request failed")
            }
        }
    }

    /// 순위 응답을 화면 값으로 옮긴다. status ok 만 — 거절은 로그만 남긴다(같은 순간 나가는 로비가 같은 status 로 말한다).
    package func applyRanking(_ response: ReversiRankingResponse) {
        guard response.status == .ok else {
            Self.logger.notice("ranking refused status=\(response.status.rawValue, privacy: .public)")
            return
        }
        noteServerNow(response.serverNowMs)
        if rankingUnavailable { rankingUnavailable = false }
        let board = Self.rankingBoard(from: response)
        if ranking != board { ranking = board }
    }

    /// 머리글용 내 순위. 순위 응답의 전적이 로비 전적(`record`)과 같을 때만 — 다르면 한쪽이 늦은 것이라 nil.
    /// 로비를 아직 못 받았으면(record nil) 순위 응답이 유일한 출처라 그대로 낸다.
    package var myRankConsistentWithRecord: ReversiMyRank? {
        guard let mine = ranking?.me else { return nil }
        if let record, record != ReversiRecord(wins: mine.wins, losses: mine.losses, draws: mine.draws) {
            return nil
        }
        return mine
    }

    /// 내 판이 끝났다(`applyState` 의 justFinished) — 전적이 바뀐 순간 순위도 다시 읽는다.
    /// 창이 안 보여도 한 번은 낸다: 폴링이 아니라 **사건에 대한 한 번**이다. 스위치가 꺼진 기기는 안 낸다.
    package func noteOwnMatchFinishedForRanking() {
        watchRuntime.lastRankingRequestAt = .distantPast     // 지금 못 나가도(도는 중) 다음 틱이 바로 읽게
        guard rankingEnabled, host?.session != nil else { return }
        Task { [weak self] in await self?.refreshRanking() }
    }

    // MARK: 순수 매퍼

    /// 응답 → 순위표(순수). **행 순서는 입력 그대로**. user_id 나 rank 가 빠진 행은 싣지 않는다.
    package nonisolated static func rankingBoard(from response: ReversiRankingResponse) -> ReversiRanking {
        let entries = (response.rows ?? []).compactMap { row -> ReversiRankEntry? in
            guard let rank = row.rank, let id = row.userId?.lowercased(), !id.isEmpty else { return nil }
            let user = ReversiUser(
                id: id, displayName: row.displayName ?? "", avatarURL: row.avatarUrl, characterID: row.character,
                center: CenterLabel.display(row.center), isWorking: false, isCapable: false, inMatch: false)
            let wins = row.wins ?? 0
            let losses = row.losses ?? 0
            return ReversiRankEntry(
                id: id, rank: rank, user: user, wins: wins, losses: losses, draws: row.draws ?? 0,
                points: row.points ?? (wins - losses))
        }
        let mine = response.me.map { me -> ReversiMyRank in
            let wins = me.wins ?? 0
            let losses = me.losses ?? 0
            return ReversiMyRank(rank: me.rank, wins: wins, losses: losses, draws: me.draws ?? 0,
                                 points: me.points ?? (wins - losses))
        }
        let since = response.recordSinceMs.flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0 / 1000) : nil }
        return ReversiRanking(entries: entries, me: mine, recordSince: since)
    }
}
