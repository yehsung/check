// `package` 타입(AchievementStatus·WeeklyWorkStatus·MobileDemoFixtures·MobileStubRequest·MobileDemoMissionsRoute)의
// 멤버와이즈·내부 멤버를 쓰므로 `@testable` 로 받는다 — 같은 폴더 `GamesChessFixtureContractTests` 와 같은 길이다.
@testable import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

// 폰 **도전 미션 · 주간 근무 받기**(v0.3.58 맥 / 폰 1.0.9) 데모 픽스처의 계약.
//
// ── 왜 화면보다 이 파일이 먼저인가 ──
// 직전 폰 관전 화면은 **검증 수단이 0 이었다**: 폰 뷰는 `#if os(iOS)` 라 맥 스위트가 컴파일조차 못 하고(저장소 메모
// '폰 뷰는 맥 스위트가 못 본다'), 데모 데이터도 없어서 띄울 길이 아예 없었다. 그래서 "관전자에게 이기면 +10" 같은 거짓
// 문구를 전부 소스를 읽어서 잡았다 — 한 번 띄울 수 있었으면 10초에 보일 것들이었다. 이번엔 **데이터를 먼저** 두고,
// 그 데이터가 거짓을 그리지 못하게 여기서 못을 박는다(체스 때와 같은 순서 — `GamesChessFixtureContractTests`).
//
// ── 무엇을 재는가: 모양이 아니라 **결과** ──
// "키가 있다"로 끝내지 않는다. 그 값이 **규칙상 맞는가**를 재고, 그 위에 **칸 이름 못**을 하나 더 박는다:
//   §1 열세 줄이 `achievement_defs()` 그대로인가(제목 · 보조 문장 · 보상 · 목표 · 계열 · 단계 · 순서) · 칸 이름이 정확히 그 집합인가.
//      ★ 칸 이름 집합을 단언하는 까닭: 모델 디코드가 **관대하다**(칸 하나가 없으면 그 칸만 기본값). 그래서 서버가 칸 이름을
//        바꾸거나 빠뜨리면 값이 **조용히 기본값으로 접히고** 화면은 멀쩡해 보인다 — detail="" · achieved(시각으로 유추) ·
//        granted_now=[] · pending=[] 처럼 **기본값이 픽스처 값과 같은 칸**은 값 단언만으로는 절대 안 잡힌다.
//   §2 `claimable_count` · `claimable_ruby`(서버가 센 값)가 **줄에서 센 값**과 같은가 — 갈리면 배지와 줄이 다른 수를 말한다.
//   §3 `seriesRows` 가 계열마다 한 줄이고, **받을 수 있는 단계를 위 단계가 가리지 않는가**(사장님 지시의 핵심).
//   §4 받기 응답의 `claimed_now` 가 값으로 맞는가(빈 배열 갈래 포함) · `merged(over:)` 가 **받음을 되돌리지 않는가**.
//   §5 주간 `pending` · `claimable_ruby` · `supportsClaim` · `hasClaimable` · 게이지 · 옛 서버 갈래.
//   §6 데모 라우트 여덟이 **서로 다른 픽스처**에 닿는가(기준선이 같은 입력이면 그 테스트는 영원히 초록이다) ·
//      그 데모 값이 `#if DEBUG` 안에만 있는가(출시 게이트 `ios/scripts/check-release-app.sh` 의 짝).
//
// ── 닿는 길(데모 라우트) ──
//   me                       나 탭 — 받을 것 넷 + 주간 받기 둘(장면 `_me`)
//   me/                      나 탭 — 기록 없는 계정(장면 `_me-`)
//   me/missions              `me` 와 같은 장면(이름만 또렷한 별칭) · `me/weekly` 도 같다
//   me/missions/claimable    같다
//   me/missions/progress     중간 진행(받을 것 0)
//   me/missions/claimed      열셋 전부 받음
//   me/missions/fresh        갓 가입(장면 `_me-`)
//   me/weekly/done           주간 완료(62시간 · 전부 받음)
//   me/weekly/legacy         옛 서버(받기 칸 없음)
// 변형은 **장면 폴더가 아니라 바늘**이다 — 까닭은 `MobileDemoMissionsRoute` 머리말에 있다.
// 스토어 배선과 화면은 이 파일의 소유가 아니다(미션 절 작업자가 위 글자를 받아 가면 된다).
@Suite struct MeAchievementsFixtureContractTests {

    // MARK: - §0 재료

    static let index = MobileDemoFixtures.load()
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase   // 서비스 디코더와 같은 설정
        return decoder
    }()

    /// 고정 시계(`MobileClock.demoInstant`) · 서버가 도전 미션을 연 시각.
    static let nowMs = 1_789_621_500_000
    static let launchMs = 1_789_398_000_000
    static let week = "2026-09-14"
    static let previousWeek = "2026-09-07"

    /// `achievement_defs()`(20261019120000_achievements.sql §1) **그대로**. 픽스처가 서버 정의표에서 한 칸이라도
    /// 어긋나면 화면이 서버와 다른 숫자를 약속한다 — 그래서 로스터를 여기 한 번 적고 픽스처 넷을 전부 대조한다.
    /// (정본은 서버다. 값이 바뀌는 날 이 표와 픽스처를 같이 고친다 — 둘 중 하나만 고치면 빨개진다.)
    static let defs: [(key: String, series: String, tier: Int, title: String, detail: String,
                       reward: Int, target: Int, sort: Int)] = [
        ("phone_login", "phone_login", 1, "폰 앱에서 로그인하기", "아이폰 앱에 같은 계정으로 로그인", 50, 1, 10),
        ("todo3", "todo3", 1, "할 일 3개 이상 등록하기", "", 20, 3, 20),
        ("gomoku1", "gomoku1", 1, "오목 한 판 두기", "", 10, 1, 30),
        ("chess1", "chess1", 1, "체스 한 판 두기", "", 10, 1, 40),
        ("minigame3", "minigame3", 1, "미니게임 3종 한 판씩 해보기", "타이밍 바 · 플래피 아잉 · 테트리스", 10, 3, 50),
        ("poke10", "poke", 1, "콕 찌르기 10회", "", 5, 10, 60),
        ("poke50", "poke", 2, "콕 찌르기 50회", "", 20, 50, 70),
        ("poke100", "poke", 3, "콕 찌르기 100회", "", 50, 100, 80),
        ("ultra5", "ultra5", 1, "울트라 찌르기 5회", "", 50, 5, 90),
        ("team2", "team", 1, "팀 2명 채우기", "", 50, 2, 100),
        ("team3", "team", 2, "팀 3명 채우기", "", 200, 3, 110),
        ("streak14", "streak", 1, "14일 연속 근무", "", 30, 14, 120),
        ("streak30", "streak", 2, "30일 연속 근무", "", 200, 30, 130),
    ]

    /// 서버 칸 이름 — `achievements__status` · `achievement_claim` · `weekly_work__status` · `weekly_work_claim` 의 jsonb 그대로.
    enum Keys {
        /// ★ `daily`(v0.3.64 — 일일 미션)는 **최상위 칸이 하나 더해진 것**이다(기존 칸과 그 뜻은 한 글자도 안 바뀐다).
        /// 여기 더한 까닭: 이 집합은 **정확히 같아야** 하므로 픽스처에 `daily` 를 넣으면 여덟 장 전부가 빨개진다 —
        /// 그래서 픽스처와 이 줄을 **같이** 고친다(관전자 수 때는 이 못을 피해 가느라 데모에서 수가 늘 0 이었다).
        /// `daily` 안의 칸 · 값은 `MeDailyMissionViewTests` 가 잰다(그 절의 소유다).
        static let status: Set<String> = ["launch_at_ms", "missions", "claimable_count", "claimable_ruby",
                                          "ruby_balance", "server_now_ms", "daily"]
        static let mission: Set<String> = ["key", "series", "tier", "title", "detail", "reward", "target", "progress",
                                          "achieved", "claimed", "achieved_at_ms", "claimed_at_ms", "sort"]
        static let claim: Set<String> = ["key", "title", "reward"]
        static let weekly: Set<String> = ["week_start", "next_week_start", "worked_seconds", "tiers", "granted_now",
                                          "ruby_balance", "server_now_ms", "pending", "claimable_ruby"]
        /// 0.3.55~0.3.57 옛 서버 — 새 칸(`pending` · `claimable_ruby`)이 아예 없다.
        static let weeklyLegacy: Set<String> = ["week_start", "next_week_start", "worked_seconds", "tiers",
                                                "granted_now", "ruby_balance", "server_now_ms"]
        static let tier: Set<String> = ["hours", "ruby", "claimed", "achieved", "claimable"]
        static let tierLegacy: Set<String> = ["hours", "ruby", "claimed"]
        static let grant: Set<String> = ["week_start", "hours", "ruby"]
        static let grantLegacy: Set<String> = ["hours", "ruby"]
    }

    /// 미션 픽스처 넷 + 받기 응답 넷. **정확히 이 여덟 장**이다(늘리거나 줄이는 것은 결정이므로 여기를 고쳐야 한다).
    static let missionPaths = [
        "me/_me/rpc.achievements_status.json",
        "me/_me/rpc.achievements_status@demo-progress.json",
        "me/_me/rpc.achievements_status@demo-all-claimed.json",
        "me/_me-/rpc.achievements_status.json",
        "me/_me/rpc.achievement_claim.json",
        "me/_me/rpc.achievement_claim@todo3.json",
        "me/_me/rpc.achievement_claim@poke10.json",
        "me/_me/rpc.achievement_claim@streak14.json",
    ]
    /// 주간 픽스처 다섯(상태 넷 + 받기 응답 하나).
    static let weeklyPaths = [
        "me/_me/rpc.weekly_work_status.json",
        "me/_me-/rpc.weekly_work_status.json",
        "me/_me/rpc.weekly_work_status@demo-week-done.json",
        "me/_me/rpc.weekly_work_status@demo-week-legacy.json",
        "me/_me/rpc.weekly_work_claim.json",
    ]
    /// 받기 응답(= `claimed_now` 를 싣는 응답)의 경로.
    static let claimResponsePaths: Set<String> = [
        "me/_me/rpc.achievement_claim.json",
        "me/_me/rpc.achievement_claim@todo3.json",
        "me/_me/rpc.achievement_claim@poke10.json",
        "me/_me/rpc.achievement_claim@streak14.json",
        "me/_me/rpc.weekly_work_claim.json",
    ]
    static let legacyWeeklyPath = "me/_me/rpc.weekly_work_status@demo-week-legacy.json"

    static func entry(_ path: String) throws -> MobileDemoFixtures.Entry {
        try #require(index.entries.first { $0.relativePath == path }, "픽스처 없음: \(path)")
    }

    static func raw(_ path: String) throws -> [String: Any] {
        let object = try JSONSerialization.jsonObject(with: try entry(path).data)
        return try #require(object as? [String: Any], "\(path): JSON 객체가 아니다")
    }

    /// 설명용 `__` 키는 계약이 아니다(걷어낸다 — 안 걷으면 주석을 지워야 초록이 되는 거꾸로 된 테스트가 된다).
    static func keys(_ object: Any?) -> Set<String> {
        guard let dictionary = object as? [String: Any] else { return [] }
        return Set(dictionary.keys.filter { !$0.hasPrefix("__") })
    }

    static func rows(_ object: Any?, _ key: String) -> [[String: Any]] {
        ((object as? [String: Any])?[key] as? [[String: Any]]) ?? []
    }

    static func status(_ path: String) throws -> AchievementStatus {
        try decoder.decode(AchievementStatus.self, from: try entry(path).data)
    }

    static func weekly(_ path: String) throws -> WeeklyWorkStatus {
        try decoder.decode(WeeklyWorkStatus.self, from: try entry(path).data)
    }

    static func request(rpc: String, body: String = "{}") -> MobileStubRequest {
        MobileStubRequest(method: "POST", host: MobileDemo.host, path: "/rest/v1/rpc/\(rpc)",
                          query: "", headers: [:], bodyText: body)
    }

    // MARK: - §1 열세 줄이 서버 정의표 그대로인가 · 칸 이름이 정확히 그 집합인가

    @Test("미션 픽스처 여덟 장: 열세 줄이 achievement_defs() 그대로 · 칸 이름이 정확히 그 집합이다(칸을 지우면 빨개진다)")
    func missionRosterMatchesTheServerDefinitions() throws {
        // 픽스처 로스터부터 — 조용히 빠지거나 늘면 아래 단언들이 **덜 재고도** 초록이 된다.
        let found = Set(Self.index.entries.filter {
            $0.key == "rpc.achievements_status" || $0.key == "rpc.achievement_claim"
        }.map(\.relativePath))
        #expect(found == Set(Self.missionPaths), "미션 픽스처 목록이 바뀌었다: \(found.symmetricDifference(Set(Self.missionPaths)))")

        for path in Self.missionPaths {
            let object = try Self.raw(path)
            let wantTop = Self.claimResponsePaths.contains(path) ? Self.Keys.status.union(["claimed_now"]) : Self.Keys.status
            #expect(Self.keys(object) == wantTop, "\(path): 최상위 칸 이름이 서버와 다르다 — \(Self.keys(object).symmetricDifference(wantTop))")

            let missions = Self.rows(object, "missions")
            #expect(missions.count == Self.defs.count, "\(path): 미션이 \(missions.count)개다(서버는 13개)")
            for (row, def) in zip(missions, Self.defs) {
                #expect(Self.keys(row) == Self.Keys.mission,
                        "\(path) \(def.key): 미션 칸 이름이 다르다 — \(Self.keys(row).symmetricDifference(Self.Keys.mission))")
            }
            for row in Self.rows(object, "claimed_now") {
                let want = path.contains("weekly") ? Self.Keys.grant : Self.Keys.claim
                #expect(Self.keys(row) == want, "\(path): claimed_now 칸 이름이 다르다")
            }

            // 값: 제목 · 보조 문장 · 보상 · 목표 · 계열 · 단계 · 순서는 **서버가 말한다**(앱에 숫자를 적지 않는다).
            let status = try Self.status(path)
            #expect(status.missions.count == Self.defs.count, "\(path): 디코드 뒤 미션 \(status.missions.count)개(행이 버려졌다)")
            #expect(status.launchAtMs == Self.launchMs, "\(path): launch_at_ms")
            #expect(status.serverNowMs == Self.nowMs, "\(path): server_now_ms(고정 시계와 달라 시간 표시가 흔들린다)")
            for (mission, def) in zip(status.missions, Self.defs) {
                #expect(mission.key == def.key, "\(path): 서버 순서(sort, key)가 아니다 — \(mission.key) ≠ \(def.key)")
                #expect(mission.series == def.series, "\(path) \(def.key): 계열")
                #expect(mission.tier == def.tier, "\(path) \(def.key): 단계")
                #expect(mission.title == def.title, "\(path) \(def.key): 제목")
                #expect(mission.detail == def.detail, "\(path) \(def.key): 보조 문장")
                #expect(mission.reward == def.reward, "\(path) \(def.key): 보상")
                #expect(mission.target == def.target, "\(path) \(def.key): 목표")
                #expect(mission.sort == def.sort, "\(path) \(def.key): 순서")

                // 달성·지급은 **행이 있다는 뜻**이다 — 시각과 깃발이 짝이어야 한다(한쪽만 있으면 관대한 디코더가 유추한다).
                #expect((mission.achievedAtMs != nil) == mission.achieved,
                        "\(path) \(def.key): achieved=\(mission.achieved) 인데 achieved_at_ms=\(String(describing: mission.achievedAtMs))")
                #expect((mission.claimedAtMs != nil) == mission.claimed,
                        "\(path) \(def.key): claimed=\(mission.claimed) 인데 claimed_at_ms=\(String(describing: mission.claimedAtMs))")
                if let achievedAt = mission.achievedAtMs {
                    #expect(achievedAt > Self.launchMs && achievedAt <= Self.nowMs, "\(path) \(def.key): 달성 시각이 창 밖이다")
                }
                if let claimedAt = mission.claimedAtMs {
                    #expect(claimedAt >= (mission.achievedAtMs ?? 0) && claimedAt <= Self.nowMs,
                            "\(path) \(def.key): 받은 시각이 달성 전이거나 미래다")
                }
                // 달성은 **끈적하다**: 서버는 달성한 키의 progress 를 target 으로 적는다(지금 값이 줄었어도).
                if mission.achieved {
                    #expect(mission.progress == def.target, "\(path) \(def.key): 달성인데 진행 \(mission.progress)/\(def.target)")
                    #expect(mission.fraction == 1, "\(path) \(def.key): 달성인데 막대가 안 찼다")
                } else {
                    #expect(mission.progress < def.target, "\(path) \(def.key): 미달성인데 진행이 목표에 닿았다")
                    #expect(!mission.claimed, "\(path) \(def.key): 미달성인데 받았다고 적혀 있다")
                }
                #expect(mission.claimed == (mission.state == .claimed), "\(path) \(def.key): 줄 상태")
                #expect(mission.isClaimable == (mission.state == .claimable), "\(path) \(def.key): [받기] 줄 상태")
            }
            // 같은 키가 둘이면 앞의 것만 산다 — 픽스처에 중복이 없다는 것까지 못 박는다(중복이면 count 가 13 이 안 된다).
            #expect(Set(status.missions.map(\.key)).count == Self.defs.count, "\(path): 키가 중복이다")
        }
    }

    // MARK: - §2 받을 것: 서버가 센 값 ↔ 줄에서 센 값

    @Test("claimable_count · claimable_ruby 가 줄에서 센 값과 같다 — 받을 것 넷 75루비 · 중간 진행 0 · 전부 받음 0 · 갓 가입 0")
    func claimableCountsMatchTheRows() throws {
        /// path → (받을 키, 받을 루비, 잔량)
        let table: [(path: String, claimable: [String], ruby: Int, balance: Int)] = [
            ("me/_me/rpc.achievements_status.json", ["todo3", "poke10", "poke50", "streak14"], 75, 120),
            ("me/_me/rpc.achievements_status@demo-progress.json", [], 0, 120),
            ("me/_me/rpc.achievements_status@demo-all-claimed.json", [], 0, 825),
            ("me/_me-/rpc.achievements_status.json", [], 0, 12),
            ("me/_me/rpc.achievement_claim.json", [], 0, 195),
            ("me/_me/rpc.achievement_claim@todo3.json", ["poke10", "poke50", "streak14"], 55, 140),
            ("me/_me/rpc.achievement_claim@poke10.json", ["todo3", "poke50", "streak14"], 70, 125),
            ("me/_me/rpc.achievement_claim@streak14.json", ["todo3", "poke10", "poke50"], 45, 150),
        ]
        for row in table {
            let status = try Self.status(row.path)
            #expect(status.claimable.map(\.key) == row.claimable, "\(row.path): 받을 줄 \(status.claimable.map(\.key))")
            #expect(status.claimableCount == row.claimable.count, "\(row.path): 받을 것 수")
            #expect(status.claimableRuby == row.ruby, "\(row.path): 받을 루비")
            #expect(status.rubyBalance == row.balance, "\(row.path): 잔량(스크린샷 알약 값)")
            // ★ 서버가 센 값과 **같아야** 한다. 갈리면 레일 배지(서버 값)와 줄(센 값)이 다른 수를 말한다.
            let reportedCount = try #require(status.reportedClaimableCount, "\(row.path): claimable_count 가 없다")
            let reportedRuby = try #require(status.reportedClaimableRuby, "\(row.path): claimable_ruby 가 없다")
            #expect(reportedCount == status.claimableCount,
                    "\(row.path): claimable_count \(reportedCount) ≠ 줄에서 센 \(status.claimableCount)")
            #expect(reportedRuby == status.claimableRuby,
                    "\(row.path): claimable_ruby \(reportedRuby) ≠ 줄에서 센 \(status.claimableRuby)")
        }
        // ★ 기준선이 갈리는가: 넷 가운데 받을 것이 있는 상태가 **있고** 없는 상태가 **있다**(전부 0 이면 §2·§3 이 공허해진다).
        let counts = try Self.missionPaths.map { try Self.status($0).claimableCount }
        #expect(counts.contains(0) && counts.contains(where: { $0 > 0 }), "받을 것이 있는 픽스처와 없는 픽스처가 둘 다 있어야 한다")
    }

    // MARK: - §3 계열 줄 — 받을 수 있는 단계를 위 단계가 가리지 않는다

    @Test("seriesRows: 계열마다 한 줄 · 받을 수 있는 가장 낮은 단계가 선다(콕 50 을 채웠어도 안 받은 10 이 보인다)")
    func seriesRowsNeverHideAClaimableTier() throws {
        /// path → 줄에 서는 키(계열 순서 = 계열의 가장 작은 sort).
        let table: [(path: String, rows: [String])] = [
            // 받을 것 넷: 콕은 50 까지 채웠지만 **10 의 [받기]** 가 선다 · 팀은 받을 게 없어 team3(진행)이 선다.
            ("me/_me/rpc.achievements_status.json",
             ["phone_login", "todo3", "gomoku1", "chess1", "minigame3", "poke10", "ultra5", "team3", "streak14"]),
            // 중간 진행: 아직 안 받은 가장 낮은 단계(콕 10 · 팀 2).
            ("me/_me/rpc.achievements_status@demo-progress.json",
             ["phone_login", "todo3", "gomoku1", "chess1", "minigame3", "poke10", "ultra5", "team2", "streak14"]),
            // 전부 받음: 가장 높은 단계를 받은 것으로 그린다.
            ("me/_me/rpc.achievements_status@demo-all-claimed.json",
             ["phone_login", "todo3", "gomoku1", "chess1", "minigame3", "poke100", "ultra5", "team3", "streak30"]),
            ("me/_me-/rpc.achievements_status.json",
             ["phone_login", "todo3", "gomoku1", "chess1", "minigame3", "poke10", "ultra5", "team2", "streak14"]),
            // 전부 받기 응답: 콕 10 · 50 을 받았으니 그 자리에 **poke100**(안 받은 가장 낮은 단계)이 선다.
            ("me/_me/rpc.achievement_claim.json",
             ["phone_login", "todo3", "gomoku1", "chess1", "minigame3", "poke100", "ultra5", "team3", "streak30"]),
            ("me/_me/rpc.achievement_claim@todo3.json",
             ["phone_login", "todo3", "gomoku1", "chess1", "minigame3", "poke10", "ultra5", "team3", "streak14"]),
            // ★ 콕 10 을 받은 뒤: 그 자리에 **poke50 의 [받기]** 가 선다(가려졌던 보상이 올라온다).
            ("me/_me/rpc.achievement_claim@poke10.json",
             ["phone_login", "todo3", "gomoku1", "chess1", "minigame3", "poke50", "ultra5", "team3", "streak14"]),
            ("me/_me/rpc.achievement_claim@streak14.json",
             ["phone_login", "todo3", "gomoku1", "chess1", "minigame3", "poke10", "ultra5", "team3", "streak30"]),
        ]
        for row in table {
            let status = try Self.status(row.path)
            #expect(status.seriesRows.map(\.key) == row.rows, "\(row.path): 줄 \(status.seriesRows.map(\.key))")
            // 계열마다 **한 줄**이고 계열 수(아홉)만큼이다.
            #expect(Set(status.seriesRows.map(\.series)).count == status.seriesRows.count, "\(row.path): 같은 계열이 두 줄이다")
            #expect(status.seriesRows.count == Set(Self.defs.map(\.series)).count, "\(row.path): 줄 수가 계열 수와 다르다")
            // ★ 받을 수 있는 단계가 **가려지지 않는다**: 받을 것이 있는 계열의 줄은 반드시 [받기] 줄이다.
            let claimableSeries = Set(status.claimable.map(\.series))
            for shown in status.seriesRows where claimableSeries.contains(shown.series) {
                #expect(shown.isClaimable, "\(row.path): 계열 \(shown.series) 에 받을 것이 있는데 줄은 \(shown.key)(\(shown.state))")
                // 그리고 그 계열에서 **가장 낮은** 받을 수 있는 단계다.
                let lowest = status.missions.filter { $0.series == shown.series && $0.isClaimable }.map(\.tier).min()
                #expect(shown.tier == lowest, "\(row.path): 계열 \(shown.series) 의 낮은 단계가 가려졌다")
            }
            // 키 → 계열 되묻기(받기 연출이 어느 줄에 설지 고르는 자리).
            #expect(status.series(ofKey: "poke50") == "poke" && status.series(ofKey: "없는키") == nil, "\(row.path): 키→계열")
        }
    }

    // MARK: - §4 받기 응답 · 받음은 되돌아가지 않는다

    @Test("받기 응답: claimed_now 가 장부에 들어간 행 그대로(빈 배열 갈래 포함) · 받은 줄은 claimed 다")
    func claimResponsesCarryWhatTheServerWrote() throws {
        /// path → (claimed_now 키, 루비 합)
        let table: [(path: String, keys: [String], ruby: Int)] = [
            ("me/_me/rpc.achievement_claim.json", ["todo3", "poke10", "poke50", "streak14"], 75),
            ("me/_me/rpc.achievement_claim@todo3.json", ["todo3"], 20),
            ("me/_me/rpc.achievement_claim@poke10.json", ["poke10"], 5),
            // 다른 기기가 1분 전에 먼저 받았다 — 오류가 아니라 **빈 배열**이고, 그 줄은 claimed 로 돌아온다.
            ("me/_me/rpc.achievement_claim@streak14.json", [], 0),
        ]
        let rewards = Dictionary(uniqueKeysWithValues: Self.defs.map { ($0.key, $0.reward) })
        let titles = Dictionary(uniqueKeysWithValues: Self.defs.map { ($0.key, $0.title) })
        for row in table {
            let status = try Self.status(row.path)
            #expect(status.claimedNow.map(\.key) == row.keys, "\(row.path): claimed_now \(status.claimedNow.map(\.key))")
            #expect(status.claimedNowRuby == row.ruby, "\(row.path): 받은 루비 합")
            for claim in status.claimedNow {
                #expect(claim.reward == rewards[claim.key], "\(row.path) \(claim.key): 보상이 정의표와 다르다")
                #expect(claim.title == titles[claim.key], "\(row.path) \(claim.key): 제목이 정의표와 다르다")
                // 받았다고 말한 줄은 응답 안에서도 받은 것이어야 한다(안 그러면 [받기]가 그대로 남아 거짓 버튼이 된다).
                #expect(status.missions.first { $0.key == claim.key }?.claimed == true,
                        "\(row.path) \(claim.key): claimed_now 에 있는데 줄은 안 받았다")
            }
        }
        // 빈 배열 갈래에서도 그 줄은 받은 것이다(화면은 claimed_now 가 비면 '받았어요' 연출만 하지 않는다).
        let race = try Self.status("me/_me/rpc.achievement_claim@streak14.json")
        #expect(race.claimedNow.isEmpty && race.missions.first { $0.key == "streak14" }?.claimed == true,
                "경합 응답에서 그 줄이 안 받은 채로 남았다 — [받기]가 다시 서서 거짓 버튼이 된다")
        // 상태 조회는 claimed_now 가 **언제나 비어 있다**(상태가 '방금 받았다'를 말하면 안 된다).
        for path in Self.missionPaths where !Self.claimResponsePaths.contains(path) {
            #expect(try Self.status(path).claimedNow.isEmpty, "\(path): 상태 조회에 claimed_now 가 있다")
        }
    }

    @Test("merged(over:): 늦게 온 옛 응답이 받음을 되돌리지 않는다(되돌리면 거짓 [받기]가 다시 선다)")
    func mergedOverNeverUndoesAClaim() throws {
        let fresh = try Self.status("me/_me/rpc.achievements_status.json")          // todo3 가 아직 [받기]
        let claimed = try Self.status("me/_me/rpc.achievement_claim@todo3.json")    // todo3 를 받았다
        #expect(fresh.missions.first { $0.key == "todo3" }?.isClaimable == true, "대조: 기준선이 안 갈린다")
        #expect(claimed.missions.first { $0.key == "todo3" }?.claimed == true, "대조: 받기 응답이 받음을 안 적었다")

        // ★ 늦게 도착한 옛 상태를 받은 응답 **위에** 얹는다 — todo3 는 받은 채로 남아야 한다.
        let merged = fresh.merged(over: claimed)
        let todo = try #require(merged.missions.first { $0.key == "todo3" })
        #expect(todo.claimed && todo.achieved && todo.state == .claimed, "받음이 되돌아갔다 — 누르면 아무것도 안 주는 [받기]가 선다")
        #expect(todo.claimedAtMs == claimed.missions.first { $0.key == "todo3" }?.claimedAtMs, "받은 시각을 잃었다")
        #expect(merged.claimable.map(\.key) == ["poke10", "poke50", "streak14"], "받은 줄이 받을 것에 남아 있다")
        #expect(merged.claimableRuby == 55, "받은 줄의 루비가 받을 합에 남아 있다")
        // 다른 줄은 손대지 않는다(받지 않은 것을 받았다고 적지 않는다).
        #expect(merged.missions.filter(\.claimed).map(\.key) == ["phone_login", "todo3", "gomoku1", "chess1", "team2"],
                "받은 줄 집합이 달라졌다: \(merged.missions.filter(\.claimed).map(\.key))")
        // 거꾸로(새 응답이 늦은 것이 아니라 최신일 때)는 그대로다 — 되돌릴 것이 없다.
        #expect(claimed.merged(over: fresh) == claimed, "최신 응답이 옛 응답 때문에 바뀌었다")
        #expect(fresh.merged(over: nil) == fresh, "지난 응답이 없으면 그대로여야 한다")
        // 전부 받은 상태 위에 옛 상태를 얹어도 하나도 되돌아가지 않는다.
        let all = try Self.status("me/_me/rpc.achievements_status@demo-all-claimed.json")
        #expect(fresh.merged(over: all).claimableCount == 0, "전부 받았는데 [받기]가 넷 다시 섰다")
    }

    // MARK: - §5 주간 근무 받기

    @Test("주간 픽스처 다섯: pending · claimable_ruby · supportsClaim · hasClaimable · 게이지가 서버 값과 맞는다")
    func weeklyFixturesCarryThePendingTiers() throws {
        let found = Set(Self.index.entries.filter {
            $0.key == "rpc.weekly_work_status" || $0.key == "rpc.weekly_work_claim"
        }.map(\.relativePath))
        #expect(found == Set(Self.weeklyPaths), "주간 픽스처 목록이 바뀌었다: \(found.symmetricDifference(Set(Self.weeklyPaths)))")

        /// path → (누적초, 받을 단계 수, 받을 루비, 받기 서버인가, 지금 퀘스트, 완료인가, 받은 합, 방금 받은 루비, 잔량)
        /// 잔량(`ruby_balance`)까지 값으로 재는 까닭: 같은 장면의 상점 픽스처와 **같은 값**이어야 스크린샷의 루비 알약이
        /// 깜박이지 않는다(나 탭은 주간 응답의 잔량으로 미러를 덮는다 — `MeStoreWeeklyWork.applyWeeklyWorkStatus`).
        let table: [(path: String, worked: Int, pending: Int, ruby: Int, supports: Bool,
                     quest: Int, complete: Bool, claimedTotal: Int, claimedNow: Int, balance: Int)] = [
            ("me/_me/rpc.weekly_work_status.json", 83_520, 2, 70, true, 40, false, 0, 0, 120),
            ("me/_me-/rpc.weekly_work_status.json", 0, 0, 0, true, 20, false, 0, 0, 12),
            ("me/_me/rpc.weekly_work_status@demo-week-done.json", 223_200, 0, 0, true, 60, true, 270, 0, 390),
            // 옛 서버: 받기 칸이 아예 없다 → 버튼도 받을 것도 0 이다(그 서버에서 버튼을 세우면 누를 때 404 다).
            (Self.legacyWeeklyPath, 151_200, 0, 0, false, 60, false, 70, 0, 190),
            ("me/_me/rpc.weekly_work_claim.json", 83_520, 0, 0, true, 40, false, 20, 70, 190),
        ]
        for row in table {
            let object = try Self.raw(row.path)
            let isLegacy = row.path == Self.legacyWeeklyPath
            var wantTop = isLegacy ? Self.Keys.weeklyLegacy : Self.Keys.weekly
            if Self.claimResponsePaths.contains(row.path) { wantTop.insert("claimed_now") }
            #expect(Self.keys(object) == wantTop, "\(row.path): 최상위 칸 이름 — \(Self.keys(object).symmetricDifference(wantTop))")
            for tier in Self.rows(object, "tiers") {
                #expect(Self.keys(tier) == (isLegacy ? Self.Keys.tierLegacy : Self.Keys.tier), "\(row.path): 단계 칸 이름")
            }
            for pending in Self.rows(object, "pending") {
                #expect(Self.keys(pending) == Self.Keys.grant, "\(row.path): pending 칸 이름")
            }
            for grant in Self.rows(object, "claimed_now") {
                #expect(Self.keys(grant) == Self.Keys.grant, "\(row.path): claimed_now 칸 이름")
            }
            for grant in Self.rows(object, "granted_now") {
                #expect(Self.keys(grant) == Self.Keys.grantLegacy, "\(row.path): granted_now 칸 이름")
            }

            let status = try Self.weekly(row.path)
            #expect(status.isUsable, "\(row.path): 줄을 그릴 만큼 모른다(누적초 · 단계 표)")
            #expect(status.weekStart == Self.week && status.nextWeekStart == "2026-09-21", "\(row.path): 주")
            #expect(status.workedSeconds == row.worked, "\(row.path): 누적초")
            #expect(status.rubyBalance == row.balance, "\(row.path): 잔량(스크린샷 알약 값)")
            #expect(status.serverNowMs == Self.nowMs, "\(row.path): server_now_ms")
            #expect(status.tiers.map(\.hours) == [20, 40, 60] && status.tiers.map(\.ruby) == [20, 50, 200],
                    "\(row.path): 단계 표(시간 오름차순)")
            #expect(status.totalRuby == 270, "\(row.path): 단계 표 합")
            #expect(status.supportsClaim == row.supports, "\(row.path): 받기 서버 판정")
            #expect(status.pendingCount == row.pending, "\(row.path): 받을 단계 수")
            #expect(status.pendingRuby == row.ruby, "\(row.path): 받을 루비")
            #expect(status.hasClaimable == (row.ruby > 0), "\(row.path): [받기] 버튼")
            #expect(status.claimedNowRuby == row.claimedNow, "\(row.path): 방금 받은 루비")
            let gauge = try #require(status.gauge, "\(row.path): 게이지")
            #expect(gauge.questHours == row.quest, "\(row.path): 지금 퀘스트")
            #expect(gauge.isComplete == row.complete, "\(row.path): 완료")
            #expect(gauge.claimedTotal == row.claimedTotal, "\(row.path): 장부가 말하는 받은 합")
            // 받기 서버는 **자동 지급이 없다** — granted_now 는 늘 비어 있다. 옛 서버만 싣는다.
            #expect(status.grantedNow.isEmpty == !isLegacy, "\(row.path): granted_now")
            // 단계마다 achieved · claimable: 받기 서버는 둘을 싣고, 옛 서버는 **둘 다 nil**(모른다)이다.
            for tier in status.tiers {
                #expect((tier.achieved == nil) == isLegacy, "\(row.path) \(tier.hours)h: achieved")
                #expect((tier.claimable == nil) == isLegacy, "\(row.path) \(tier.hours)h: claimable")
                if let achieved = tier.achieved, let claimable = tier.claimable {
                    #expect(claimable == (achieved && !tier.claimed), "\(row.path) \(tier.hours)h: 받을 수 있음 = 채웠고 안 받았다")
                    #expect(!(tier.claimed && !achieved), "\(row.path) \(tier.hours)h: 받았는데 안 채웠다고 적혀 있다")
                }
            }
        }

        // ★ pending 은 **어느 주든**이다 — 이번 주 단계 표에서 유도할 수 없다(지난주에 채우고 안 받은 것이 남는다).
        let me = try Self.weekly("me/_me/rpc.weekly_work_status.json")
        #expect(me.pending?.map(\.weekStart) == [Self.previousWeek, Self.week], "지난주 소급분이 pending 에 없다")
        #expect(me.pending?.map(\.hours) == [40, 20] && me.pending?.map(\.ruby) == [50, 20], "pending 단계")
        #expect(me.claimableRuby == 70, "서버가 센 받을 루비")
        #expect(me.tiers.map(\.claimed) == [false, false, false] && me.tiers.first?.claimable == true,
                "이번 주 표: 20시간을 채웠고 아직 안 받았다")
        // 받을 것 없음(빈 배열)과 옛 서버(칸 없음)는 **다른 상태**다 — 접으면 옛 서버에 버튼이 선다.
        let empty = try Self.weekly("me/_me-/rpc.weekly_work_status.json")
        #expect(empty.pending == [] && empty.supportsClaim, "빈 배열이 nil 로 접혔다")
        #expect(try Self.weekly(Self.legacyWeeklyPath).pending == nil, "옛 서버 응답에 pending 이 있다")

        // 주간 받기 응답: 두 주를 한 번에 받는다(order by week_start, hours).
        let claim = try Self.weekly("me/_me/rpc.weekly_work_claim.json")
        #expect(claim.claimedNow.map(\.hours) == [40, 20] && claim.claimedNow.map(\.ruby) == [50, 20], "주간 claimed_now")
        #expect(claim.claimedNow.map(\.weekStart) == [Self.previousWeek, Self.week], "주간 claimed_now 의 주")
        #expect(claim.pending == [] && claim.claimableRuby == 0 && !claim.hasClaimable, "받은 뒤에도 [받기]가 남았다")
        #expect(claim.rubyBalance == 190 && me.rubyBalance == 120, "받기 전후 잔량(120 + 70)")

        // ★ 받기 서버에서는 '방금 받았어요' 알림을 **단계 깃발로 유추하지 않는다**(사람이 누른 것이고 화면이 이미 말했다).
        #expect(claim.newlyGranted(since: me).isEmpty,
                "받기 서버인데 claimed 가 거짓→참이 된 것을 '방금 받았어요'로 또 알린다")
        // 대조(기준선이 갈리는가): **옛 서버**에서는 같은 변화가 알림이 된다 — granted_now + 깃발 뒤집힘 둘 다.
        let legacy = try Self.weekly(Self.legacyWeeklyPath)
        let previous = WeeklyWorkStatus(weekStart: Self.week, nextWeekStart: "2026-09-21", workedSeconds: 0,
                                        tiers: [.init(hours: 20, ruby: 20, claimed: false),
                                                .init(hours: 40, ruby: 50, claimed: false),
                                                .init(hours: 60, ruby: 200, claimed: false)])
        let grants = legacy.newlyGranted(since: previous)
        #expect(grants.map(\.hours).sorted() == [20, 40] && grants.reduce(0) { $0 + $1.ruby } == 70,
                "옛 서버 알림 경로가 죽었다: \(grants)")
    }

    // MARK: - §6 데모 경로 — 라우트 여덟이 **서로 다른 픽스처**에 닿는가 · Release 에서 사라졌는가

    @Test("데모 라우트가 기존 장면 + 바늘로 풀려 **서로 다른** 미션·주간 픽스처에 닿는다(남의 라우트는 안 가로챈다)")
    func theDemoRoutesReachDifferentFixtures() throws {
        /// 라우트 → (장면, 바늘, 미션 픽스처, 주간 픽스처)
        let table: [(route: String, scene: String, needle: String?, missions: String, weekly: String)] = [
            ("me/missions", "me", nil,
             "me/_me/rpc.achievements_status.json", "me/_me/rpc.weekly_work_status.json"),
            ("me/missions/claimable", "me", nil,
             "me/_me/rpc.achievements_status.json", "me/_me/rpc.weekly_work_status.json"),
            ("me/missions/progress", "me", "demo-progress",
             "me/_me/rpc.achievements_status@demo-progress.json", "me/_me/rpc.weekly_work_status.json"),
            ("me/missions/claimed", "me", "demo-all-claimed",
             "me/_me/rpc.achievements_status@demo-all-claimed.json", "me/_me/rpc.weekly_work_status.json"),
            ("me/missions/fresh", "me-", nil,
             "me/_me-/rpc.achievements_status.json", "me/_me-/rpc.weekly_work_status.json"),
            ("me/weekly", "me", nil,
             "me/_me/rpc.achievements_status.json", "me/_me/rpc.weekly_work_status.json"),
            ("me/weekly/done", "me", "demo-week-done",
             "me/_me/rpc.achievements_status.json", "me/_me/rpc.weekly_work_status@demo-week-done.json"),
            ("me/weekly/legacy", "me", "demo-week-legacy",
             "me/_me/rpc.achievements_status.json", Self.legacyWeeklyPath),
        ]
        var fingerprints: Set<String> = []
        for row in table {
            let plan = try #require(MobileDemoMissionsRoute(demoRoute: row.route), "\(row.route): 라우트가 안 풀렸다")
            #expect(plan.scene == row.scene && plan.needle == row.needle, "\(row.route): \(plan)")
            // ★ 여는 라우트는 `AingRoute` 가 아는 글자여야 한다 — 아니면 앱이 기본 탭에 머물고 미션 절이 화면에 없다.
            #expect(AingRoute(path: plan.openRoute) == .me, "\(row.route): 나 탭이 안 열린다")
            // 데모와 **같은 함수**로 고른다(`MobileDemo.environment` 가 하는 일 그대로).
            let missions = Self.index.entry(for: plan.rewrite(Self.request(rpc: "achievements_status")), scenario: plan.scene)
            let weekly = Self.index.entry(for: plan.rewrite(Self.request(rpc: "weekly_work_status")), scenario: plan.scene)
            #expect(missions?.relativePath == row.missions, "\(row.route): 미션 → \(missions?.relativePath ?? "없음")")
            #expect(weekly?.relativePath == row.weekly, "\(row.route): 주간 → \(weekly?.relativePath ?? "없음")")
            fingerprints.insert("\(missions?.relativePath ?? "-")|\(weekly?.relativePath ?? "-")")
        }
        // ★ **지문이 몇 가지인가** — 기준선이 같은 입력이면 그 테스트는 영원히 초록이다(저장소 메모).
        // 같은 지문인 짝 셋은 일부러다: `me/missions` ≡ `me/missions/claimable` ≡ `me/weekly`.
        #expect(fingerprints.count == 6, "라우트 여덟이 \(fingerprints.count) 가지 픽스처만 고른다 — 바늘이 버려지고 있다: \(fingerprints)")

        // 받기 응답은 **본문의 p_key** 로 갈린다(변형이 없는 키는 바늘 없는 기본 파일 = 전부 받기).
        let plan = try #require(MobileDemoMissionsRoute(demoRoute: "me/missions"))
        let claims: [(body: String, path: String)] = [
            (#"{"p_key":"todo3"}"#, "me/_me/rpc.achievement_claim@todo3.json"),
            (#"{"p_key":"poke10"}"#, "me/_me/rpc.achievement_claim@poke10.json"),
            (#"{"p_key":"streak14"}"#, "me/_me/rpc.achievement_claim@streak14.json"),
            (#"{"p_key":null}"#, "me/_me/rpc.achievement_claim.json"),
            (#"{"p_key":"poke50"}"#, "me/_me/rpc.achievement_claim.json"),
        ]
        for claim in claims {
            let entry = Self.index.entry(for: plan.rewrite(Self.request(rpc: "achievement_claim", body: claim.body)),
                                         scenario: plan.scene)
            #expect(entry?.relativePath == claim.path, "받기 \(claim.body) → \(entry?.relativePath ?? "없음")")
        }
        let weeklyClaim = Self.index.entry(
            for: plan.rewrite(Self.request(rpc: "weekly_work_claim", body: #"{"p_week_start":null,"p_hours":null}"#)),
            scenario: plan.scene)
        #expect(weeklyClaim?.relativePath == "me/_me/rpc.weekly_work_claim.json", "주간 받기 픽스처에 못 닿는다")

        // 남의 데모 라우트는 **가로채지 않는다** — 가로채면 그 장면이 미션 장면으로 오배달된다.
        // 특히 `me` · `me/`(이미 도는 두 장면)와 `me/shop` 은 nil 이어야 한다.
        for raw in ["me", "me/", "me/shop", "me/settings", "me/feedback", "now", "games/chess/lobby", "messages"] {
            #expect(MobileDemoMissionsRoute(demoRoute: raw) == nil, "남의 데모 라우트를 미션으로 읽었다: \(raw)")
        }
        // 모르는 꼬리·공백·대문자는 받을 것 여럿 장면으로 접는다(라우트를 조용히 버리지 않는다).
        #expect(MobileDemoMissionsRoute(demoRoute: " /ME/Missions/Nope/ ") == MobileDemoMissionsRoute(scene: "me"))
        // 바늘이 없으면 본문을 건드리지 않는다(기록·금지 호출 판정이 그대로여야 한다).
        let plain = Self.request(rpc: "achievements_status")
        #expect(plan.rewrite(plain) == plain, "바늘이 없는데 요청을 고쳤다")
    }

    @Test("미션·주간 RPC 는 폰 금지 목록에 없다 · 미션 픽스처는 나 탭 장면 밖으로 새지 않는다(잔량을 덮지 않게)")
    func theRPCsAreAllowedAndScopedToTheMeTab() {
        for rpc in ["achievements_status", "achievement_claim", "weekly_work_status", "weekly_work_claim"] {
            #expect(!MobileForbiddenCalls.forbiddenRPCs.contains(rpc), "\(rpc) 가 폰 금지 목록에 있다")
            #expect(MobileForbiddenCalls.violation(Self.request(rpc: rpc)) == nil, "\(rpc) 가 금지 호출로 걸린다")
        }
        // 나 탭 두 장면에서는 닿고, 다른 탭 장면에서는 **안 닿는다**(404 로 접혀 절이 숨는다) — 주간 픽스처와 같은 규약:
        // 다른 장면에서 잔량(ruby_balance)을 덮으면 그 스크린샷의 루비 알약 값이 바뀐다.
        for rpc in ["achievements_status", "achievement_claim"] {
            #expect(Self.index.entry(for: Self.request(rpc: rpc), scenario: "me") != nil, "\(rpc): 장면 _me 에 없다")
            for scenario in ["games", "now", "messages", "rankings-league", "me-shop", "me-settings"] {
                #expect(Self.index.entry(for: Self.request(rpc: rpc), scenario: scenario) == nil,
                        "\(rpc) 픽스처가 장면 \(scenario) 에도 닿는다")
            }
        }
        #expect(Self.index.entry(for: Self.request(rpc: "achievements_status"), scenario: "me-") != nil,
                "갓 가입 장면(_me-)에 미션 픽스처가 없다")
        // 데모 스텁이 실제로 돌려주는 응답까지(상태 200 · 본문이 그 파일) — `response(for:scenario:)` 는 데모와 같은 함수다.
        let response = Self.index.response(for: Self.request(rpc: "achievements_status"), scenario: "me")
        #expect(response.status == 200 && !response.body.isEmpty, "데모 스텁이 미션 응답을 안 돌려준다")
        #expect(Self.index.duplicateKeys.isEmpty, "\(Self.index.duplicateKeys)")
    }

    /// 데모 값(`MobileDemoMissionsRoute`)과 그 배선 전부가 **`#if DEBUG` 안**이다 — Release 바이너리에 이름이 남지 않는다.
    ///
    /// ── 이 테스트가 생긴 까닭(1.0.6 build 16) ──
    /// 데모용 타입이 구성 분기 없이 선언돼 있어 Swift 가 타입 이름(nominal type descriptor)을 Release 바이너리에 넣었고,
    /// 출시 게이트 `ios/scripts/check-release-app.sh` 의 금지 심볼 `MobileDemo` 가 그것을 물어 아카이브가 막혔다
    /// (SPEC-ios §0-2 — "0 이 아니면 올리지 않는다"). 테스트 281건과 코드 검토는 그것을 한 건도 보지 못했다 —
    /// `swift test` 는 Debug 다. 그래서 소스 글자로 못을 박는다: 한 자리만 게이트 밖으로 나가도 이름이 다시 남는다.
    @Test("데모 미션 라우트 값과 배선은 #if DEBUG 안에만 있다 — Release 바이너리에 이름이 남지 않는다(출시 게이트)")
    func theDemoRouteValueIsDebugOnly() throws {
        for relative in ["Sources/CheckMobileKit/Demo/MobileDemoMissionsRoute.swift",
                         "Sources/CheckMobileKit/Demo/MobileDemo.swift"] {
            let source = try Self.strippedSource(relative)
            let lines = source.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            #expect(lines.first == "#if DEBUG", "\(relative): 파일이 #if DEBUG 로 시작하지 않는다")
            #expect(lines.last == "#endif", "\(relative): 파일이 #endif 로 끝나지 않는다")
            // 플랫폼 분기는 **금지**다: 더하는 순간 맥 스위트가 이 판정을 못 보고 §6 이 통째로 공허해진다
            // (저장소 메모 '폰 뷰는 맥 스위트가 못 본다' — 미션 화면은 전부 `#if os(iOS)` 안이다).
            #expect(!source.contains("#if os("), "\(relative): 플랫폼 분기가 들어왔다 — 맥 스위트가 데모 판정을 못 본다")
        }
        let value = try Self.strippedSource("Sources/CheckMobileKit/Demo/MobileDemoMissionsRoute.swift")
        #expect(value.contains("package struct MobileDemoMissionsRoute"), "값 타입이 그 파일에 없다 — 경로가 틀렸다")

        // ★ 그리고 **쓰는 자리가 Demo/ 밖에 없다**(Demo/ 의 파일은 통째로 DEBUG 다 — 위에서 쟀다).
        // 한 자리라도 밖으로 나가면 Release 바이너리에 `MobileDemoMissionsRoute` 가 남아 출시 게이트가 막는다.
        let users = try Self.files(containing: "MobileDemoMissionsRoute", under: "Sources")
        #expect(users == ["Sources/CheckMobileKit/Demo/MobileDemo.swift",
                          "Sources/CheckMobileKit/Demo/MobileDemoMissionsRoute.swift"],
                "데모 미션 값을 Demo/ 밖에서 쓴다(Release 에 이름이 남는다): \(users)")
        // 배선 두 줄(장면·바늘을 스텁에 넘기는 자리 · 여는 라우트를 바꿔치기하는 자리)이 실제로 있는가 —
        // 없으면 위 §6 의 라우트 표는 **아무것도 안 하는 값**을 재고 있는 것이다.
        let demo = try Self.strippedSource("Sources/CheckMobileKit/Demo/MobileDemo.swift")
        #expect(demo.contains("MobileDemoMissionsRoute(demoRoute: route)"), "데모 조립이 미션 라우트를 안 푼다")
        #expect(demo.contains("index.response(for: missions?.rewrite(request) ?? request, scenario: missions?.scene ?? scenario)"),
                "스텁이 미션 장면·바늘을 안 받는다 — 라우트가 픽스처를 못 고른다")
        #expect(demo.contains("demoRoute: missions?.openRoute ?? route"),
                "여는 라우트를 나 탭으로 바꾸지 않는다 — 앱이 기본 탭에 머물고 미션 절이 화면에 없다")
    }

    // MARK: - 도우미

    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    /// 저장소 파일 한 벌을 **주석을 걷어내고** 돌려준다. 안 걷으면 설명을 지워야만 초록이 되는 테스트가 된다
    /// (저장소 메모 '소스 계약 테스트는 주석을 걷어내야 한다').
    static func strippedSource(_ relativePath: String) throws -> String {
        let raw = try String(contentsOf: root.appendingPathComponent(relativePath), encoding: .utf8)
        return raw.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                guard let hit = line.range(of: "//") else { return String(line) }
                return String(line[line.startIndex..<hit.lowerBound])
            }
            .joined(separator: "\n")
    }

    /// `under` 아래 .swift 중 주석을 걷어낸 코드에 `needle` 이 든 파일(저장소 상대 경로, 정렬).
    static func files(containing needle: String, under relative: String) throws -> [String] {
        let base = root.appendingPathComponent(relative)
        guard let enumerator = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil) else { return [] }
        var hits: [String] = []
        let rootPath = root.standardizedFileURL.path
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            if try strippedSource(String(url.standardizedFileURL.path.dropFirst(rootPath.count + 1))).contains(needle) {
                hits.append(String(url.standardizedFileURL.path.dropFirst(rootPath.count + 1)))
            }
        }
        return hits.sorted()
    }
}
