import Foundation

// 오목 스토어의 **순위표** 갈래(0.3.41) — 승점(승 − 패) 순위와 그 안의 내 자리.
//
// ── 정렬은 서버가 한다 ──
// 행 순서는 서버 `gomoku_ranking` 의 order by(points desc → wins desc → draws desc → user_id asc) 그대로 옮긴다. **여기서 다시 정렬하지 않는다** —
// 재정렬하면 서버·앱 두 규칙이 갈려 같은 목록이 화면마다 다른 순서가 된다. `GomokuRankingOrder` 는 그 규칙을 Swift 로 옮긴 **판정**이지
// 정렬기가 아니다(계약 테스트가 실서버 픽스처를 이 판정에 넣어 서버 order by 가 바뀐 날을 잡는다).
//
// ── 실패는 조용하다 ──
// 순위 조회 실패는 **안내줄(notice)로 새지 않는다** — 대국 상태줄을 가리고, 기존 계약 테스트 다수가 notice == nil 을 단언한다.
// `rankingLoadFailed` 깃발만 세우고 들고 있던 목록은 지우지 않는다(로비 규약: 빈 목록을 사실로 그리지 않는다).
// PGRST202(서버에 함수가 아직 없다 = 앱이 db push 보다 먼저 나간 창)는 실패가 아니라 `rankingUnavailable` 이다 — 화면은 "순위는 곧 열려요".
//
// ── 내 순위는 한 출처(C16) ──
// 머리글 캡슐이 읽을 순위·승점·전적은 전부 `ranking.me` 다. 로비 `record` 와 섞으면 한쪽이 늦을 때 "8승 3패 · 승점 +4" 같은 자기모순 문장이 뜬다.
// `myRankConsistentWithRecord` 가 그 가드다: 순위 응답의 전적이 로비 전적과 같을 때만 순위를 내주고, 다르면 nil(화면은 전적만 그린다).
//
// ── 주 스위치(C11) ──
// `spectatorFeaturesEnabled` 가 꺼져 있으면 `loadRanking` 은 요청을 내지 않는다 — 폰이 그리지도 않는 순위표를 1분마다 당기지 않게.

extension GomokuStore {
    // MARK: 조회

    /// 순위표 한 번. 도는 중이면 **합치지 않고 버린다**(60초 주기 목록이라 뒤따르는 한 번이 필요 없다 — 로비 목록과 같은 규약).
    package func loadRanking() async {
        guard spectatorFeaturesEnabled, host?.session != nil else { return }
        let runtime = watchRuntime
        guard !runtime.rankingInFlight else { return }
        runtime.rankingInFlight = true
        let generation = resetGeneration
        defer { if generation == resetGeneration { runtime.rankingInFlight = false } }
        runtime.lastRankingRequestAt = clock()
        guard let result = await perform({ try await $0.gomokuRanking(accessToken: $1) }) else { return }
        switch result {
        case .success(let response):
            applyRanking(response)
        case .failure(let error):
            if let known = error as? SupabaseWorkServiceError, known == .databaseSchemaMissing {
                Self.logger.notice("ranking unavailable — function missing on server")
                if !rankingUnavailable { rankingUnavailable = true }
                if rankingLoadFailed { rankingLoadFailed = false }
                // "받은 것"으로 센다 — 안 그러면 화면이 로딩 문구를 영영 든다. 60초 폴링은 그대로라 서버가 올라오면 저절로 회복한다.
                if !hasLoadedRanking { hasLoadedRanking = true }
            } else {
                Self.logger.notice("ranking request failed")
                if !rankingLoadFailed { rankingLoadFailed = true }
            }
        }
    }

    /// 순위 응답을 화면 값으로 옮긴다. status ok 만 — 거절은 실패 깃발이고 안내줄은 만들지 않는다(파일 머리말).
    package func applyRanking(_ response: GomokuRankingResponse) {
        guard response.status == .ok else {
            Self.logger.notice("ranking refused status=\(response.status.rawValue, privacy: .public)")
            // unsupported_client 도 여기서는 말하지 않는다 — 같은 순간 나가는 로비 조회가 같은 status 로 이미 말한다.
            if !rankingLoadFailed { rankingLoadFailed = true }
            return
        }
        noteServerNow(response.serverNowMs)
        if rankingLoadFailed { rankingLoadFailed = false }
        if rankingUnavailable { rankingUnavailable = false }
        if !hasLoadedRanking { hasLoadedRanking = true }
        let board = Self.rankingBoard(from: response)
        if ranking != board { ranking = board }
    }

    /// 머리글 캡슐용 내 순위(C16). 순위 응답의 전적이 로비 전적(`record`)과 같을 때만 — 다르면 한쪽이 늦은 것이라 nil(전적만 그린다).
    /// 로비를 아직 못 받았으면(record nil) 순위 응답이 유일한 출처라 그대로 낸다.
    package var myRankConsistentWithRecord: GomokuMyRank? {
        guard let mine = ranking?.me else { return nil }
        if let record, record != GomokuRecord(wins: mine.wins, losses: mine.losses, draws: mine.draws) { return nil }
        return mine
    }

    /// 내 판이 끝났다(applyState 의 justFinished) — 전적이 바뀐 순간 순위도 다시 읽는다(바로 옆 로비 재조회와 같은 결).
    /// 창이 안 보여도 한 번은 낸다: 폴링이 아니라 사건에 대한 한 번이다(로비 재조회도 그렇다). 주 스위치가 꺼진 폰은 안 낸다.
    package func noteOwnMatchFinishedForRanking() {
        watchRuntime.lastRankingRequestAt = .distantPast     // 지금 못 나가도(도는 중) 다음 틱이 바로 읽게
        guard spectatorFeaturesEnabled, host?.session != nil else { return }
        Task { [weak self] in await self?.loadRanking() }
    }

    // MARK: 순수 매퍼

    /// 응답 → 순위표(순수). **행 순서는 입력 그대로**. user_id 나 rank 가 빠진 행은 싣지 않는다(순위 없는 줄은 순위표에 아무 정보도 안 준다).
    /// `recordSince` 는 기기 시계 보정 없이 서버 순간 그대로다 — 마감 카운트다운이 아니라 "M월 d일부터" 캡션의 달력 값이다.
    package nonisolated static func rankingBoard(from response: GomokuRankingResponse) -> GomokuRankingBoard {
        let entries = (response.rows ?? []).compactMap { row -> GomokuRankEntry? in
            // CenterLabel 변환점은 `user(from:)` 하나다 — 행 모양이 GomokuUserRow 와 같아 그대로 태운다(근무·가능·대국 중은 이 표에 없다 → false).
            let userRow = GomokuUserRow(
                userId: row.userId, displayName: row.displayName, avatarUrl: row.avatarUrl, character: row.character,
                center: row.center, isWorking: nil, capable: nil, inMatch: nil
            )
            guard let rank = row.rank, let user = user(from: userRow) else { return nil }
            let wins = row.wins ?? 0
            let losses = row.losses ?? 0
            let draws = row.draws ?? 0
            return GomokuRankEntry(
                id: user.id, rank: rank, user: user, wins: wins, losses: losses, draws: draws,
                points: row.points ?? (wins - losses)
            )
        }
        let mine = response.me.map { me -> GomokuMyRank in
            let wins = me.wins ?? 0
            let losses = me.losses ?? 0
            return GomokuMyRank(rank: me.rank, wins: wins, losses: losses, draws: me.draws ?? 0, points: me.points ?? (wins - losses))
        }
        let since = response.recordSinceMs.flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0 / 1000) : nil }
        return GomokuRankingBoard(entries: entries, me: mine, recordSince: since)
    }
}

/// 서버 `gomoku_ranking` 의 정렬 규칙을 Swift 로 옮긴 **판정**(정렬기가 아니다 — 스토어는 재정렬하지 않는다).
/// `order by points desc, wins desc, draws desc, user_id asc` · `rank()` 는 앞 세 축만 본다(동률은 같은 숫자, 다음은 건너뛴다: 3,3,5).
package nonisolated enum GomokuRankingOrder {
    /// 한 줄의 정렬 키.
    package struct Key: Equatable, Sendable {
        package let points: Int
        package let wins: Int
        package let draws: Int
        package let userID: String

        package init(points: Int, wins: Int, draws: Int, userID: String) {
            self.points = points
            self.wins = wins
            self.draws = draws
            self.userID = userID.lowercased()
        }

        package init(_ entry: GomokuRankEntry) {
            self.init(points: entry.points, wins: entry.wins, draws: entry.draws, userID: entry.id)
        }

        /// user_id 가 없는 행은 키가 없다(순서를 말할 수 없다).
        package init?(_ row: GomokuRankRow) {
            guard let id = row.userId, !id.isEmpty else { return nil }
            let wins = row.wins ?? 0
            let losses = row.losses ?? 0
            self.init(points: row.points ?? (wins - losses), wins: wins, draws: row.draws ?? 0, userID: id)
        }
    }

    /// lhs 가 rhs 보다 **엄격히** 앞서는가. 승점 desc → 승 desc → 무 desc → user_id asc.
    /// `draws desc` 의 뜻: 같은 승점·같은 승수면 **더 많이 둔 쪽이 위**다 — (1승 1패 1무) 가 (1승 1패 0무) 앞에 선다(서버 실측).
    package static func precedes(_ lhs: Key, _ rhs: Key) -> Bool {
        if lhs.points != rhs.points { return lhs.points > rhs.points }
        if lhs.wins != rhs.wins { return lhs.wins > rhs.wins }
        if lhs.draws != rhs.draws { return lhs.draws > rhs.draws }
        return lhs.userID < rhs.userID
    }

    /// 앞 세 축이 같은가 = `rank()` 가 같은 순위를 주는 쌍.
    package static func ties(_ lhs: Key, _ rhs: Key) -> Bool {
        lhs.points == rhs.points && lhs.wins == rhs.wins && lhs.draws == rhs.draws
    }

    /// 배열이 서버 규칙대로 서 있는가(엄격 — user_id 까지 같은 두 줄은 있을 수 없다).
    package static func isSorted(_ keys: [Key]) -> Bool {
        zip(keys, keys.dropFirst()).allSatisfy { precedes($0, $1) }
    }

    package static func isSorted(_ entries: [GomokuRankEntry]) -> Bool {
        isSorted(entries.map(Key.init))
    }

    /// 응답 행 그대로. 키를 못 만드는 행(user_id 없음)이 하나라도 있으면 false — 그 목록은 순서를 말할 수 없다.
    package static func isSorted(_ rows: [GomokuRankRow]) -> Bool {
        let keys = rows.compactMap(Key.init)
        guard keys.count == rows.count else { return false }
        return isSorted(keys)
    }

    /// 서버가 매긴 `rank` 가 `rank()` 의 모양인가: 순위 = 1 + 자기보다 (앞 세 축에서) 엄격히 앞선 줄 수. **정렬된 배열에서만** 뜻이 있다.
    package static func ranksMatchServerRule(_ entries: [GomokuRankEntry]) -> Bool {
        let keys = entries.map(Key.init)
        for (index, entry) in entries.enumerated() {
            let better = keys.prefix(index).filter { !ties($0, keys[index]) }.count
            if entry.rank != better + 1 { return false }
        }
        return true
    }
}
