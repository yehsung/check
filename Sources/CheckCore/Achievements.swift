import Foundation

// MARK: - 도전 미션(일회성 업적) — v0.3.58 맥
//
// 사장님 확정(2026-10-19 — 값은 최종이다, 되묻지 말 것): 폰 로그인 50 · 할 일 3개 20 · 오목 한 판 10 · 체스 한 판 10 ·
// 미니게임 3종 10 · 팀 2명 50 / 3명 200 · 콕 10회 5 / 50회 20 / 100회 50 · 울트라 5회 50 · 연속 근무 14일 30 / 30일 200.
// 사람마다 **평생 한 번**이다. 팀 · 연속 근무 · 폰 로그인은 지금까지 한 것도 인정하고(소급), 할 일은 지금 상태로 센다.
// 남용 방지 조건은 없다(사장님 2026-10-19 "빼기" — 팀원 근무 시간 · 같은 사람 콕 횟수 상한 둘 다).
//
// ★ **받기 버튼으로 받는다**(사장님 2026-10-19, 원문): "미션에서 바로 받는게 아니라. 달성하면 받는 버튼이 생기고 그거 누르면
//   받아지게끔 해줘. 그래야 루비를 받는 재미가 더 올라갈거 같아. 기존의 주간 목표시간 달성하는것도 받는 버튼으로 받게 바꿔주고.
//   3시간마다 루비 3개씩 주는것만 따로 버튼 없이 자동으로 지급되는걸로 냅두면 돼"
//   → 달성(achieved)과 지급(claimed)이 갈린다. 달성은 서버가 1분마다 적고, 루비는 사람이 [받기]를 누를 때만 움직인다.
//   달성한 보상은 **사라지지 않는다**(받을 때까지 기다린다 — 버튼이 없는 옛 앱 사용자는 업데이트한 뒤에 받는다).
//
// 서버 정본은 `supabase/migrations/20261019120000_achievements.sql` 이다. 요점만:
//   · `achievements_status()` — 이 사람을 먼저 **기록만** 정산하고(돈은 안 움직인다) 13개 미션 전부를 돌려준다.
//   · `achievement_claim(p_key)` — 달성했고 아직 안 받은 키를 지급한다(null = 받을 것 전부). 두 번 지급은 DB 가 막는다
//     (`claimed_at is null` 검사 + 장부 부분 유니크 인덱스). 모르는 키 · 미달성 · 이미 받음은 오류 없이 `claimed_now: []`.
//   · 제목 · 보조 문장 · 보상 · 목표 · 순서는 **응답이 말한다** — 이 파일에 50/20/10 … 을 적지 않는다. 서버가 미션을 더해도
//     앱을 다시 낼 필요가 없게(모르는 키도 그대로 그린다) · 화면이 서버와 다른 숫자를 약속하지 않게.
//
// ── 이 파일이 지키는 것 ──
// ① **디코드가 통째로 죽지 않는다.** 칸 하나가 없거나 모양이 틀리면 그 칸만 기본값, 키나 제목이 없는 미션은 그 행만 버린다
//    (`WeeklyWorkStatus` 와 같은 규약 — 서버와 앱이 한 단계 어긋난 창에서 한 칸 때문에 화면 전체가 사라지면 안 된다).
// ② **"받았다"는 서버가 넣은 행으로만 말한다.** `claimed_now`(이 호출이 장부에 넣은 행)뿐이다 — 클라가 시간 · 횟수를 재서
//    "받았다"고 판단하지 않는다.
// ③ 한 줄은 **한 계열**이다(`seriesRows`) — 콕 10 · 50 · 100 처럼 단계가 있으면 [받기]가 있는 가장 낮은 단계, 없으면 아직 안 받은
//    가장 낮은 단계 하나만, 다 받았으면 가장 높은 단계를 받은 것으로 그린다. **받을 수 있는 단계를 위 단계가 가리지 않는다.**

/// `achievements_status()` · `achievement_claim(p_key)` 응답(둘은 같은 모양이고 받기 응답에만 `claimed_now` 가 찬다).
///
/// ```json
/// { "launch_at_ms": 1781234567890,
///   "missions": [ {"key":"poke50","series":"poke","tier":2,"title":"콕 찌르기 50회","detail":"",
///                  "reward":20,"target":50,"progress":23,"achieved":false,"claimed":false,
///                  "achieved_at_ms":null,"claimed_at_ms":null,"sort":70}, … ],
///   "claimable_count": 3, "claimable_ruby": 300,
///   "claimed_now": [ {"key":"team2","title":"팀 2명 채우기","reward":50} ],
///   "ruby_balance": 1234, "server_now_ms": 1781234567890 }
/// ```
///
/// ★ **이 타입의 디코드는 칸 하나 때문에 throw 하지 않는다**(최상위가 객체가 아닐 때만 throw 한다 — 그건 응답이 아니다).
package struct AchievementStatus: Decodable, Equatable, Sendable {
    /// 줄 하나가 그리는 상태. 미달성 → [받기] → 받음, 이 순서로만 간다.
    package enum RowState: Equatable, Sendable {
        /// 아직 못 채웠다 — 진행 바 · "23/50".
        case inProgress
        /// 채웠고 아직 안 받았다 — [받기 +N] 버튼.
        case claimable
        /// 받았다 — "✓ 받음".
        case claimed
    }

    /// 미션 하나(한 단계). 화면 문구는 전부 서버 것이다.
    package struct Mission: Equatable, Sendable, Identifiable {
        package let key: String
        /// 단계를 묶는 이름(콕 10 · 50 · 100 → "poke"). 없으면 키 자신(단계 없는 한 줄).
        package let series: String
        /// 계열 안의 단계(1부터). 없으면 1.
        package let tier: Int
        package let title: String
        /// 작은 보조 문장(비어 있을 수 있다).
        package let detail: String
        /// 루비. 음수는 0 으로 접는다.
        package let reward: Int
        /// 목표(1 이상).
        package let target: Int
        /// 진행(0…target 으로 자른다 — 서버도 자르지만 클라가 한 번 더 막는다).
        package let progress: Int
        /// 채웠다(= 서버에 달성 행이 있다). **받았으면 언제나 참이다**(받은 것은 채운 것이다).
        package let achieved: Bool
        /// 받았다(= 장부에 지급 행이 있다).
        package let claimed: Bool
        /// 달성 · 지급 시각(epoch 밀리초). 화면은 안 쓴다(진단 · 테스트용).
        package let achievedAtMs: Int?
        package let claimedAtMs: Int?
        /// 화면 순서(작을수록 위). 없으면 맨 뒤.
        package let sort: Int

        package var id: String { key }

        package init(key: String, series: String? = nil, tier: Int = 1, title: String, detail: String = "",
                     reward: Int = 0, target: Int = 1, progress: Int = 0, achieved: Bool = false, claimed: Bool = false,
                     achievedAtMs: Int? = nil, claimedAtMs: Int? = nil, sort: Int = Int.max) {
            self.key = key
            self.series = (series?.isEmpty == false ? series : nil) ?? key
            self.tier = tier
            self.title = title
            self.detail = detail
            self.reward = max(0, reward)
            self.target = max(1, target)
            self.progress = min(max(0, progress), max(1, target))
            self.achieved = achieved || claimed
            self.claimed = claimed
            self.achievedAtMs = achievedAtMs
            self.claimedAtMs = claimedAtMs
            self.sort = sort
        }

        /// 채웠고 아직 안 받았다 — [받기] 버튼이 서는 줄.
        package var isClaimable: Bool { achieved && !claimed }

        package var state: RowState {
            if claimed { return .claimed }
            return achieved ? .claimable : .inProgress
        }

        /// 진행 막대 채움 0…1. 채웠으면 1(연속 근무는 채운 뒤 **지금** 연속이 다시 낮아질 수 있다 — 달성은 끈적하다).
        package var fraction: Double {
            achieved ? 1 : min(1, max(0, Double(progress) / Double(target)))
        }

        /// 받은 것으로 굳힌 사본(늦게 온 옛 응답이 받은 줄을 [받기]로 되돌리지 않게 — `merged(over:)`).
        fileprivate func markedClaimed(from previous: Mission) -> Mission {
            Mission(key: key, series: series, tier: tier, title: title, detail: detail, reward: reward, target: target,
                    progress: progress, achieved: true, claimed: true,
                    achievedAtMs: achievedAtMs ?? previous.achievedAtMs, claimedAtMs: claimedAtMs ?? previous.claimedAtMs,
                    sort: sort)
        }
    }

    /// 이 호출이 장부에 **실제로 넣은** 지급 한 건(`claimed_now`).
    package struct Claim: Equatable, Sendable {
        package let key: String
        package let title: String
        package let reward: Int

        package init(key: String, title: String, reward: Int) {
            self.key = key
            self.title = title
            self.reward = max(0, reward)
        }
    }

    /// 서버가 도전 미션을 연 시각(epoch 밀리초). 진단용 — 화면은 안 쓴다.
    package var launchAtMs: Int?
    /// 미션 전부(서버 순서 그대로 — 화면 순서는 `seriesRows` 가 `sort` 로 정한다). 같은 키가 둘이면 앞의 것만.
    package var missions: [Mission]
    /// 서버가 센 받을 것(진단용 — 화면 · 배지는 `claimableCount` 로 **줄에서** 센다: 줄과 배지가 다른 수를 말하지 않게).
    package var reportedClaimableCount: Int?
    package var reportedClaimableRuby: Int?
    /// 이 호출이 넣은 지급(받기 응답만 찬다 — 상태 조회는 언제나 비어 있다).
    package var claimedNow: [Claim]
    /// 정산 뒤 루비 잔량. nil = 안 알려 줬다(스토어는 nil 이면 잔량을 건드리지 않는다).
    package var rubyBalance: Int?
    package var serverNowMs: Int?

    package init(launchAtMs: Int? = nil, missions: [Mission] = [], reportedClaimableCount: Int? = nil,
                 reportedClaimableRuby: Int? = nil, claimedNow: [Claim] = [], rubyBalance: Int? = nil, serverNowMs: Int? = nil) {
        var seen = Set<String>()
        self.launchAtMs = launchAtMs
        self.missions = missions.filter { seen.insert($0.key).inserted }
        self.reportedClaimableCount = reportedClaimableCount
        self.reportedClaimableRuby = reportedClaimableRuby
        self.claimedNow = claimedNow
        self.rubyBalance = rubyBalance
        self.serverNowMs = serverNowMs
    }

    /// 키는 서비스 디코더의 `.convertFromSnakeCase` 를 거친 **카멜**이다(`claimed_at_ms` → `claimedAtMs`).
    package enum CodingKeys: String, CodingKey {
        case launchAtMs, missions, claimableCount, claimableRuby, claimedNow, rubyBalance, serverNowMs
    }

    package init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            launchAtMs: c.achievementLossyInt(forKey: .launchAtMs),
            missions: (c.achievementLossyList(AchievementLossyMission.self, forKey: .missions) ?? []).compactMap(\.mission),
            reportedClaimableCount: c.achievementLossyInt(forKey: .claimableCount),
            reportedClaimableRuby: c.achievementLossyInt(forKey: .claimableRuby),
            claimedNow: (c.achievementLossyList(AchievementLossyClaim.self, forKey: .claimedNow) ?? []).compactMap(\.claim),
            rubyBalance: c.achievementLossyInt(forKey: .rubyBalance),
            serverNowMs: c.achievementLossyInt(forKey: .serverNowMs)
        )
    }

    // MARK: 파생(순수)

    /// 받을 수 있는 미션(채웠고 아직 안 받은 것) — 계열로 접기 **전**이다(콕 10 · 50 을 둘 다 채웠으면 둘 다).
    package var claimable: [Mission] { missions.filter(\.isClaimable) }

    /// 레일 배지 · 절 머리의 "받을 보상 N개". 줄에서 센다(서버 숫자와 갈리면 줄이 이긴다 — 그리는 것이 줄이다).
    package var claimableCount: Int { claimable.count }

    package var claimableRuby: Int { claimable.reduce(0) { $0 + $1.reward } }

    /// 화면의 줄 — **계열마다 한 줄**. 단계는 ① [받기]가 있는 가장 낮은 단계 → ② 아직 안 받은 가장 낮은 단계 → ③ 다 받았으면
    /// 가장 높은 단계(받음). ①이 먼저인 이유(사장님 지시의 핵심): 받을 수 있는 보상이 화면에서 **가려지면 안 된다** — 콕 10 을
    /// 안 받은 채 50 까지 채웠으면 10 의 [받기]가 서고, 받으면 그 자리에 50 의 [받기]가 선다.
    /// 줄 순서는 계열의 가장 작은 `sort` 다(단계가 오를 때 줄이 자리를 옮기지 않는다) · 같으면 키 순서.
    package var seriesRows: [Mission] {
        var groups: [String: [Mission]] = [:]
        var order: [String] = []
        for mission in missions {
            if groups[mission.series] == nil { order.append(mission.series) }
            groups[mission.series, default: []].append(mission)
        }
        let rows: [(sort: Int, key: String, row: Mission)] = order.compactMap { series in
            guard let tiers = groups[series]?.sorted(by: { ($0.tier, $0.sort, $0.key) < ($1.tier, $1.sort, $1.key) }),
                  let shown = tiers.first(where: \.isClaimable) ?? tiers.first(where: { !$0.claimed }) ?? tiers.last
            else { return nil }
            return (tiers.map(\.sort).min() ?? shown.sort, shown.key, shown)
        }
        return rows.sorted { ($0.sort, $0.key) < ($1.sort, $1.key) }.map(\.row)
    }

    /// 키 → 계열(받기 연출이 어느 줄에 설지 고를 때). 모르는 키는 nil.
    package func series(ofKey key: String) -> String? {
        missions.first { $0.key == key }?.series
    }

    /// 이 호출이 넣은 지급의 루비 합.
    package var claimedNowRuby: Int { claimedNow.reduce(0) { $0 + $1.reward } }

    /// `previous`(같은 사람의 지난 응답) 위에 이 응답을 얹는다 — **받음은 되돌아가지 않는다.**
    /// 받기 두 건이 겹치면(줄 둘을 연달아 누름) 서버는 잠금으로 줄을 세우지만 답은 순서가 바뀌어 올 수 있다: 먼저 끝난 A 의 답이
    /// 나중에 오면 그 답엔 B 가 아직 안 받은 것으로 적혀 있다. 그대로 덮으면 방금 받은 B 의 줄에 [받기]가 다시 선다(누르면 서버는
    /// 아무것도 안 주고 `claimed_now: []` — 거짓 버튼이다). 서버에서 받음이 취소되는 길은 없다(계정 삭제는 세션째 바뀐다).
    package func merged(over previous: AchievementStatus?) -> AchievementStatus {
        guard let previous else { return self }
        let claimedBefore = Dictionary(previous.missions.filter(\.claimed).map { ($0.key, $0) },
                                       uniquingKeysWith: { first, _ in first })
        guard !claimedBefore.isEmpty else { return self }
        var copy = self
        copy.missions = missions.map { mission in
            guard !mission.claimed, let before = claimedBefore[mission.key] else { return mission }
            return mission.markedClaimed(from: before)
        }
        return copy
    }
}

// MARK: - 문구(순수 — 맥 · 폰이 같은 문장을 쓴다)

package enum AchievementNoticeText {
    /// 받기가 실패했다(네트워크 · 5xx · 해석 실패) — 줄 **밖**에 한 줄로 말할 때의 문장. 뽑기 실패("뽑지 못했어요. 잠시 후 다시 시도해
    /// 주세요")와 같은 꼴이다. 맥은 v0.3.58 검토 뒤 이 문장을 안내줄에 띄우지 않는다(아래 `claimFailedRow`).
    package static let claimFailed = "받지 못했어요. 잠시 후 다시 시도해 주세요"
    /// 받기가 실패한 **그 줄** 안의 문장 — 남아 있는 [받기] 옆 보조 문장 자리. 버튼이 그대로 남으니(안 받았으니) 다시 누르는 것이
    /// 재시도다. 맥 미션 화면이 안내줄을 버린 이유(검토 지적 2026-10-19): 안내줄은 도전 미션 절 **위**에 26pt 로 끼어 줄을 밀고,
    /// 아래쪽 줄을 누른 사람에겐 스크롤 밖이라 안 보였다. 짧게 쓴 이유: 버튼 옆 글자 열이 140pt 남짓이다.
    package static let claimFailedRow = "받지 못했어요 · 다시 눌러 주세요"
}

// MARK: - 서비스

/// `achievement_claim(p_key)` 본문. **키를 언제나 싣는다**(null = 받을 것 전부) — 키 집합이 흔들리면 PostgREST 가 다른 함수를 찾는다
/// (`GachaPullRequest` 와 같은 규약). 인코더가 `.convertToSnakeCase` 라 `pKey` → `p_key`.
package struct AchievementClaimRequest: Encodable, Equatable, Sendable {
    package let pKey: String?

    package init(key: String?) { pKey = key }

    private enum CodingKeys: String, CodingKey { case pKey }

    package func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if let pKey { try c.encode(pKey, forKey: .pKey) } else { try c.encodeNil(forKey: .pKey) }
    }
}

extension SupabaseWorkService {
    package nonisolated static let achievementsStatusPath = "/rest/v1/rpc/achievements_status"
    package nonisolated static let achievementClaimPath = "/rest/v1/rpc/achievement_claim"

    /// 도전 미션 상태. `achievements_status()` — 인자 없음(서버가 `auth.uid()` 를 쓴다).
    ///
    /// 서버가 이 사람을 먼저 **기록만** 정산하고(넘긴 미션의 달성 행 — 루비는 안 움직인다) 그 결과를 돌려준다. 그래서 폰에서 불러도
    /// 된다 — 본인 계정에만 작용하고 cron 이 어차피 1분마다 같은 정산을 한다.
    ///
    /// 함수가 없는 서버(PGRST202 — db push 전 창)는 `.databaseSchemaMissing`(본문 없는 404 는 `.invalidResponse(404)`)으로 throw 한다.
    /// 호출부(스토어)는 그 둘을 "이 서버엔 도전 미션이 없다"로 접어 화면에서 절을 조용히 감춘다(`BlockReportRules.isMissingFunction`).
    package func achievementsStatus(accessToken: String) async throws -> AchievementStatus {
        let data = try await send(
            path: Self.achievementsStatusPath,
            method: "POST",
            body: EmptyBody(),
            accessToken: accessToken,
            prefer: nil
        )
        return try decoder.decode(AchievementStatus.self, from: data)
    }

    /// 받기. `achievement_claim(p_key)` — `key` 가 nil 이면 받을 것 전부. 서버가 먼저 정산하므로 방금 채운 미션도 한 번에 받는다.
    /// 응답은 상태와 같은 모양 + `claimed_now`(이 호출이 실제로 넣은 지급). 이미 받았거나 미달성이면 오류 없이 `claimed_now: []` 다.
    package func achievementClaim(accessToken: String, key: String?) async throws -> AchievementStatus {
        let data = try await send(
            path: Self.achievementClaimPath,
            method: "POST",
            body: AchievementClaimRequest(key: key),
            accessToken: accessToken,
            prefer: nil
        )
        return try decoder.decode(AchievementStatus.self, from: data)
    }
}

// MARK: - 관대한 디코드 부품(이 파일 전용)

/// 키나 제목이 없는(또는 빈) 미션은 nil — 목록 디코드는 그 행만 버리고 나머지를 산다. 날것의 키("poke10")를 사람에게 보이느니
/// 그 줄을 안 그린다. 나머지 칸은 없으면 기본값이다.
private struct AchievementLossyMission: Decodable {
    let mission: AchievementStatus.Mission?

    enum CodingKeys: String, CodingKey {
        case key, series, tier, title, detail, reward, target, progress, achieved, claimed, achievedAtMs, claimedAtMs, sort
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
        // 받음/달성 칸이 없거나 모양이 틀리면 시각으로 판단한다(시각이 있으면 행이 있다는 뜻이다). 둘 다 없으면 **아니다** —
        // 받았다고 그리면 아직 안 준 루비를 준 것처럼 말하고, 채웠다고 그리면 서버가 안 줄 [받기]를 세운다.
        let claimed = c.achievementLossy(Bool.self, forKey: .claimed) ?? (claimedAtMs != nil)
        mission = AchievementStatus.Mission(
            key: key,
            series: c.achievementLossy(String.self, forKey: .series),
            tier: c.achievementLossyInt(forKey: .tier) ?? 1,
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
        )
    }
}

private struct AchievementLossyClaim: Decodable {
    let claim: AchievementStatus.Claim?

    enum CodingKeys: String, CodingKey { case key, title, reward }

    init(from decoder: Decoder) throws {
        guard let c = try? decoder.container(keyedBy: CodingKeys.self),
              let key = c.achievementLossy(String.self, forKey: .key), !key.isEmpty
        else {
            claim = nil
            return
        }
        claim = AchievementStatus.Claim(key: key,
                                        title: c.achievementLossy(String.self, forKey: .title) ?? "",
                                        reward: c.achievementLossyInt(forKey: .reward) ?? 0)
    }
}

/// 숫자면 정수로(소수는 버림). 문자열 숫자("23")도 받는다 — bigint 를 문자열로 내는 서버 설정이 있다.
private struct AchievementLossyNumber: Decodable {
    let value: Int?

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let int = try? c.decode(Int.self) {
            value = int
        } else if let double = try? c.decode(Double.self), double.isFinite, abs(double) < 9.0e15 {
            value = Int(double)
        } else if let text = try? c.decode(String.self), let int = Int(text.trimmingCharacters(in: .whitespaces)) {
            value = int
        } else {
            value = nil
        }
    }
}

/// 어떤 값이든 받아 버리는 자리(목록에서 깨진 원소를 건너뛸 때 커서를 한 칸 옮기는 용도).
private struct AchievementDiscard: Decodable {
    init(from decoder: Decoder) throws {}
}

private extension KeyedDecodingContainer {
    /// 키가 없거나 · null 이거나 · 모양이 틀리면 nil. **throw 하지 않는다.**
    func achievementLossy<T: Decodable>(_ type: T.Type, forKey key: Key) -> T? {
        (try? decodeIfPresent(type, forKey: key)) ?? nil
    }

    func achievementLossyInt(forKey key: Key) -> Int? {
        achievementLossy(AchievementLossyNumber.self, forKey: key)?.value
    }

    /// 배열이 아니면 nil, 배열이면 원소마다 따로 읽는다(원소 하나가 깨져도 나머지는 산다).
    func achievementLossyList<T: Decodable>(_ type: T.Type, forKey key: Key) -> [T]? {
        guard contains(key), var list = try? nestedUnkeyedContainer(forKey: key) else { return nil }
        var items: [T] = []
        while !list.isAtEnd {
            if let item = try? list.decode(T.self) {
                items.append(item)
            } else if (try? list.decode(AchievementDiscard.self)) == nil {
                break
            }
        }
        return items
    }
}
