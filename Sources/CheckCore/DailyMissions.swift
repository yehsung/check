import Foundation

// MARK: - 일일 미션(v0.3.64 맥 · 폰은 같은 타입을 쓴다)
//
// 사용자 결정(2026-10-22, 원문): "지금 미션을 일일미션, 주간미션, 누적미션 이렇게 3개로 나눠서 표시하는게 좋을듯. 이렇게 하고
// 일일미션에 미션들을 몇개 추가할려고 해. 미니게임 일반이랑 멀티 총 합쳐서 6개 있잖아. 그거 각각 하나마다 미션 넣어줘. 하루 1회
// 플레이 달성하면 루비 5개 주는걸로." 묻고 정한 것: **자정(KST)까지 [받기]를 안 누르면 사라진다**.
//
// 서버 정본은 `supabase/migrations/20261022140000_daily_missions.sql` 이다. 요점만:
//   · `achievements_status()` · `achievement_claim(p_key)` 응답에 최상위 `daily` 가 **더해진다**(기존 키는 그대로 — 옛 앱은 버린다).
//   · `daily_mission_claim(p_key)` — 같은 모양 전체를 돌려주고 `claimed_now` 에는 **이 호출이 넣은 일일 지급만** 싣는다.
//   · 하루 = Asia/Seoul 자정~자정. 달성은 매번 판정하고 **받은 것만** 행이 남는다 — 안 받은 달성은 자정에 저절로 사라진다.
//   · 제목 · 보상 · 순서는 응답이 말한다(이 파일에 5 · "타이밍 바 한 판 하기" 를 적지 않는다).
//
// ── 이 파일이 지키는 것 ──
// ① **디코드가 통째로 죽지 않는다**(누적 미션과 같은 관대한 규약). `daily` 가 없거나 객체가 아니면 nil(= 일일 6줄만 감춘다),
//    키나 제목이 없는 줄만 버린다. 같은 키가 둘이면 앞의 것만.
// ② **날짜를 넘긴 줄은 [받기]를 세우지 않는다.** 응답의 `reset_at_ms`(다음 KST 자정)를 서버 시각으로 넘겼으면 그 응답의 줄은
//    어제의 것이다 — 진행 0 · 안 채움 · 안 받음(새 날의 모양)으로 그린다. 다음 조회 박자가 새 날의 사실로 바꾼다.
// ③ "받음은 되돌아가지 않는다"(`merged(over:)`)는 **같은 `kst_day` 안에서만**이다 — 어제 받은 줄이 오늘 받음으로 남으면 안 된다.

/// `daily` 묶음(조회 · 받기 응답 공통).
///
/// ```json
/// "daily": { "kst_day": "2026-10-22", "reset_at_ms": 1792681200000,
///            "missions": [ {"key":"daily_timing_bar","game":"timing_bar","title":"타이밍 바 한 판 하기","detail":"",
///                           "reward":5,"target":1,"progress":1,"achieved":true,"claimed":false,"claimed_at_ms":null,"sort":10} ],
///            "claimable_count": 1, "claimable_ruby": 5 }
/// ```
package struct DailyMissionStatus: Equatable, Sendable {
    /// 일일 미션 한 줄. 화면 부품은 누적 미션 줄과 같다(`row` — 진행 · 받기 · 받음 상태와 문구가 같은 규칙이다).
    package struct Mission: Equatable, Sendable, Identifiable {
        /// 세는 게임(`timing_bar` · `flappy` · `tetris` · `gomoku` · `chess` · `tetris_duel`). 화면은 아이콘을 여기서 고른다.
        /// 모르는 값이면 화면이 기본 아이콘을 쓴다(서버가 게임을 더해도 앱을 다시 낼 필요가 없게).
        package let game: String
        package let row: AchievementStatus.Mission

        package var id: String { row.key }
        package var key: String { row.key }

        package init(game: String, row: AchievementStatus.Mission) {
            self.game = game
            self.row = row
        }

        /// 새 날의 모양 — 진행 0 · 안 채움 · 안 받음. 날짜를 넘긴 응답의 줄을 이 모양으로 그린다(어제 [받기]를 세우지 않는다).
        package var freshForNewDay: Mission {
            Mission(game: game, row: AchievementStatus.Mission(
                key: row.key, series: row.series, tier: row.tier, title: row.title, detail: row.detail, reward: row.reward,
                target: row.target, progress: 0, achieved: false, claimed: false, achievedAtMs: nil, claimedAtMs: nil,
                sort: row.sort))
        }

        /// 받은 것으로 굳힌 사본(같은 날 늦게 온 옛 응답이 받은 줄을 [받기]로 되돌리지 않게).
        fileprivate func markedClaimed(from previous: Mission) -> Mission {
            Mission(game: game, row: AchievementStatus.Mission(
                key: row.key, series: row.series, tier: row.tier, title: row.title, detail: row.detail, reward: row.reward,
                target: row.target, progress: row.target, achieved: true, claimed: true,
                achievedAtMs: row.achievedAtMs ?? previous.row.achievedAtMs,
                claimedAtMs: row.claimedAtMs ?? previous.row.claimedAtMs, sort: row.sort))
        }
    }

    /// 이 응답의 하루(KST, "2026-10-22"). 없으면 nil — 그때는 같은 날인지 모르므로 받음을 이어 붙이지 않는다.
    package var kstDay: String?
    /// 다음 KST 자정(epoch 밀리초). 서버 시각이 이 값에 닿으면 이 응답의 줄은 어제의 것이다.
    package var resetAtMs: Int?
    /// 줄들 — `sort` 순(같으면 키 순). 같은 키는 앞의 것만.
    package var missions: [Mission]
    /// 서버가 센 받을 것(진단용 — 화면 · 배지는 줄에서 센다).
    package var reportedClaimableCount: Int?
    package var reportedClaimableRuby: Int?

    package init(kstDay: String? = nil, resetAtMs: Int? = nil, missions: [Mission] = [],
                 reportedClaimableCount: Int? = nil, reportedClaimableRuby: Int? = nil) {
        var seen = Set<String>()
        self.kstDay = (kstDay?.isEmpty == false) ? kstDay : nil
        self.resetAtMs = resetAtMs
        self.missions = missions.filter { seen.insert($0.key).inserted }
            .sorted { ($0.row.sort, $0.key) < ($1.row.sort, $1.key) }
        self.reportedClaimableCount = reportedClaimableCount
        self.reportedClaimableRuby = reportedClaimableRuby
    }

    // MARK: 파생(순수)

    /// 서버 시각 `serverNowMs` 에서 이 응답의 하루가 이미 끝났는가. 리셋 시각이나 지금을 모르면 **아니다**(끝났다고 단정하지 않는다).
    package func hasRolledOver(serverNowMs: Int?) -> Bool {
        guard let resetAtMs, let serverNowMs else { return false }
        return serverNowMs >= resetAtMs
    }

    /// 화면의 줄 — 하루가 끝났으면 새 날의 모양(진행 0 · [받기] 없음 · 받음 없음).
    package func rows(serverNowMs: Int?) -> [Mission] {
        hasRolledOver(serverNowMs: serverNowMs) ? missions.map(\.freshForNewDay) : missions
    }

    /// 지금 받을 수 있는 줄(채웠고 안 받았고 하루가 안 끝났다).
    package func claimable(serverNowMs: Int?) -> [Mission] {
        rows(serverNowMs: serverNowMs).filter(\.row.isClaimable)
    }

    package func claimableCount(serverNowMs: Int?) -> Int { claimable(serverNowMs: serverNowMs).count }

    package func claimableRuby(serverNowMs: Int?) -> Int {
        claimable(serverNowMs: serverNowMs).reduce(0) { $0 + $1.row.reward }
    }

    /// 키 → 줄(받기 연출 · 배선이 그 줄을 찾을 때). 모르는 키는 nil.
    package func mission(_ key: String) -> Mission? { missions.first { $0.key == key } }

    /// 게임 → 일일 미션 키(`daily_<게임>` — 서버 `daily_mission_defs()` 의 규칙). 판이 끝난 쪽은 게임 이름만 안다.
    package static func key(game: String) -> String { keyPrefix + game }

    /// 일일 미션 키의 머리(`daily_`). 디코드가 게임 칸 없는 줄의 게임을 키에서 읽을 때도 이 글자를 쓴다.
    package static let keyPrefix = "daily_"

    /// `previous`(같은 사람의 지난 응답) 위에 이 응답을 얹는다 — **같은 `kst_day` 안에서만** 받음은 되돌아가지 않는다.
    /// 날이 바뀌었거나(어제 받은 줄) 어느 쪽이든 날을 모르면 이 응답 그대로다.
    package func merged(over previous: DailyMissionStatus?) -> DailyMissionStatus {
        guard let previous, let day = kstDay, previous.kstDay == day else { return self }
        let claimedBefore = Dictionary(previous.missions.filter(\.row.claimed).map { ($0.key, $0) },
                                       uniquingKeysWith: { first, _ in first })
        guard !claimedBefore.isEmpty else { return self }
        var copy = self
        copy.missions = missions.map { mission in
            guard !mission.row.claimed, let before = claimedBefore[mission.key] else { return mission }
            return mission.markedClaimed(from: before)
        }
        return copy
    }
}

// MARK: - 디코드(관대한 규약 — `AchievementStatus` 와 같은 부품)

extension DailyMissionStatus: Decodable {
    package enum CodingKeys: String, CodingKey {
        case kstDay, resetAtMs, missions, claimableCount, claimableRuby
    }

    /// 최상위가 객체가 아니면 throw — 부르는 쪽(`AchievementStatus`)이 그 throw 를 "일일 없음(nil)"으로 접는다.
    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            kstDay: c.achievementLossy(String.self, forKey: .kstDay)?.trimmingCharacters(in: .whitespaces),
            resetAtMs: c.achievementLossyInt(forKey: .resetAtMs),
            missions: (c.achievementLossyList(DailyLossyMission.self, forKey: .missions) ?? []).compactMap(\.mission),
            reportedClaimableCount: c.achievementLossyInt(forKey: .claimableCount),
            reportedClaimableRuby: c.achievementLossyInt(forKey: .claimableRuby)
        )
    }
}

/// 키나 제목이 없는(또는 빈) 줄은 nil — 목록 디코드는 그 줄만 버린다. 게임 칸이 없으면 키에서 읽는다(`daily_<게임>`).
private struct DailyLossyMission: Decodable {
    let mission: DailyMissionStatus.Mission?

    enum CodingKeys: String, CodingKey {
        case key, game, title, detail, reward, target, progress, achieved, claimed, achievedAtMs, claimedAtMs, sort
    }

    init(from decoder: Decoder) throws {
        guard let c = try? decoder.container(keyedBy: CodingKeys.self),
              let key = c.achievementLossy(String.self, forKey: .key), !key.isEmpty,
              let title = c.achievementLossy(String.self, forKey: .title)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty
        else {
            mission = nil
            return
        }
        let achievedAtMs = c.achievementLossyInt(forKey: .achievedAtMs)
        let claimedAtMs = c.achievementLossyInt(forKey: .claimedAtMs)
        // 누적 미션과 같은 판단: 칸이 없거나 모양이 틀리면 시각으로(시각이 있으면 행이 있다), 둘 다 없으면 **아니다**.
        let claimed = c.achievementLossy(Bool.self, forKey: .claimed) ?? (claimedAtMs != nil)
        let prefix = DailyMissionStatus.keyPrefix
        let game = c.achievementLossy(String.self, forKey: .game).flatMap { $0.isEmpty ? nil : $0 }
            ?? (key.hasPrefix(prefix) ? String(key.dropFirst(prefix.count)) : "")
        mission = DailyMissionStatus.Mission(game: game, row: AchievementStatus.Mission(
            key: key,
            title: title,
            detail: c.achievementLossy(String.self, forKey: .detail) ?? "",
            reward: c.achievementLossyInt(forKey: .reward) ?? 0,
            target: c.achievementLossyInt(forKey: .target) ?? 1,
            progress: c.achievementLossyInt(forKey: .progress) ?? 0,
            achieved: c.achievementLossy(Bool.self, forKey: .achieved) ?? (achievedAtMs != nil),
            claimed: claimed,
            achievedAtMs: achievedAtMs,
            claimedAtMs: claimedAtMs,
            sort: c.achievementLossyInt(forKey: .sort) ?? Int.max
        ))
    }
}

// MARK: - 서비스

extension SupabaseWorkService {
    package nonisolated static let dailyMissionClaimPath = "/rest/v1/rpc/daily_mission_claim"

    /// 일일 미션 받기. `daily_mission_claim(p_key)` — `key` 가 nil 이면 오늘 받을 것 전부. **본문에 키를 언제나 싣는다**
    /// (`AchievementClaimRequest` 그대로 — 키 집합이 흔들리면 PostgREST 가 다른 함수를 찾는다).
    /// 응답은 `achievements_status()` 와 같은 모양 전체 + `claimed_now`(이 호출이 넣은 **일일** 지급만). 모르는 키 · 미달성 ·
    /// 이미 받음 · 어제 것은 오류 없이 빈 `claimed_now` 다.
    package func dailyMissionClaim(accessToken: String, key: String?) async throws -> AchievementStatus {
        let data = try await send(
            path: Self.dailyMissionClaimPath,
            method: "POST",
            body: AchievementClaimRequest(key: key),
            accessToken: accessToken,
            prefer: nil
        )
        return try decoder.decode(AchievementStatus.self, from: data)
    }
}
