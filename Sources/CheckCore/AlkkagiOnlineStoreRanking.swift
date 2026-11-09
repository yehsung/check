import Foundation

// 1:1 알까기 순위(SPEC v1.1 §3.5 `alkkagi_ranking` · §3.7 RANKING · §4.5). 틀은 길건너 `CrossyDuelStoreRanking` 꼴 —
// 주 스위치(`rankingEnabled`) · 도는 중이면 버림(60초 목록이라 합치지 않는다) · PGRST202 → `rankingUnavailable` ·
// 실패는 안내 줄로 새지 않는다(판 상태 줄을 가린다) — 들고 있던 목록은 지우지 않는다.
// 와이어 디코딩은 `AlkkagiOnlineWire.swift`(키 도우미가 그 파일 안에만 있다).
//
// C1 뼈대: 표면만 길건너와 같게 섰다. 60초 주기 · 창 보일 때만 · 로비로 돌아올 때 다시는 C 다음 걸음.

/// 순위표 한 줄. 순위는 **서버가 매긴 값**이다(`rank() over (points desc, wins desc, draws desc)`).
package nonisolated struct AlkkagiRankEntry: Identifiable, Equatable, Sendable {
    package let rank: Int
    /// user id 소문자.
    package let id: String
    package let displayName: String
    package let avatarURL: String?
    package let characterID: String?
    package let wins: Int
    package let losses: Int
    package let draws: Int
    /// 승점 = 승 − 패(서버 값).
    package let points: Int

    package init(rank: Int, id: String, displayName: String, avatarURL: String? = nil, characterID: String? = nil,
                 wins: Int = 0, losses: Int = 0, draws: Int = 0, points: Int? = nil) {
        self.rank = rank
        self.id = id
        self.displayName = displayName
        self.avatarURL = avatarURL
        self.characterID = characterID
        self.wins = wins
        self.losses = losses
        self.draws = draws
        self.points = points ?? (wins - losses)
    }
}

/// 내 순위(0판이면 rank nil).
package nonisolated struct AlkkagiMyRank: Equatable, Sendable {
    package let rank: Int?
    package let wins: Int
    package let losses: Int
    package let draws: Int
    package let points: Int

    package init(rank: Int?, wins: Int = 0, losses: Int = 0, draws: Int = 0, points: Int? = nil) {
        self.rank = rank
        self.wins = wins
        self.losses = losses
        self.draws = draws
        self.points = points ?? (wins - losses)
    }

    /// 머리 캡슐의 'N위'는 순위 me 가 로비 record 와 같을 때만 쓴다(§4.5 — 길건너 CK/CrossyDuelPanel.swift:191-198 규칙).
    package func matches(_ record: AlkkagiRecord?) -> Bool {
        guard let record else { return false }
        return record.wins == wins && record.losses == losses && record.draws == draws
    }
}

/// 순위표 한 벌. `recordSince` 는 전적을 세기 시작한 시각(서버 epoch 가 −∞ 면 nil — 설계 결정 D6).
package nonisolated struct AlkkagiRankingBoard: Equatable, Sendable {
    package let entries: [AlkkagiRankEntry]
    package let me: AlkkagiMyRank?
    package let recordSince: Date?

    package init(entries: [AlkkagiRankEntry], me: AlkkagiMyRank?, recordSince: Date? = nil) {
        self.entries = entries
        self.me = me
        self.recordSince = recordSince
    }
}

extension AlkkagiOnlineStore {
    /// 순위표 한 번. `rankingEnabled` 가 꺼져 있거나 서비스가 없으면(미리보기 · 렌더 시험) 아무것도 안 한다.
    /// RANKING 봉투에는 `protocol` 키가 없을 수 있어(§3.7) 로비 길(`perform`)의 protocol 문을 지나지 않는다 — status 만 본다.
    package func refreshRanking() async {
        guard rankingEnabled, let service, !rankingInFlight else { return }
        rankingInFlight = true
        let generation = resetGeneration
        defer { if generation == resetGeneration { rankingInFlight = false } }
        do {
            let response = try await service.call(.ranking)
            guard generation == resetGeneration, !Task.isCancelled else { return }
            applyRanking(response)
        } catch let error as AlkkagiServiceError where error == .serverMissing {
            guard generation == resetGeneration else { return }
            if !rankingUnavailable { rankingUnavailable = true }
        } catch {
            // 실패는 안내 줄로 새지 않는다 — 들고 있던 순위는 그대로 둔다.
        }
    }

    /// 순위 응답을 옮긴다(ok 이고 순위가 실렸을 때만 — 값이 같으면 쓰지 않는다).
    func applyRanking(_ response: AlkkagiResponse) {
        guard response.status == .ok, let board = response.ranking else { return }
        if rankingUnavailable { rankingUnavailable = false }
        if ranking != board { ranking = board }
    }
}
