import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

/// 일일 미션 — 폰 **스토어** 배선(서버 `20261023130000_daily_missions.sql` · 맥 0.3.64 · 폰 1.0.13).
/// `MeStore` 의 **진짜 경로**를 스텁 서버로 돈다: `achievements_status` 의 최상위 `daily` → 줄 · 받을 수 → `daily_mission_claim`
/// → 받음 · 잔량 · 연출, 그리고 날 넘김 · 판 끝난 뒤 조회 · 배지.
///
/// 단언은 **결과를 값으로** 못 박는다(모양이 아니라): 몇 건이 나갔는가 · 어떤 본문이 갔는가 · 화면이 읽는 수가 얼마인가.
/// 기대값은 손으로 적은 글자 · 숫자다(규칙 함수로 기대값을 다시 만들면 규칙이 틀려도 초록이다).
///
/// 이 스토어 파일들은 `#if os(iOS)` 밖이라 맥 `swift test` 가 진짜 경로를 돈다(뷰는 레인 B 의 `MeDailyMissionViewTests`).
@MainActor
@Suite("나 탭 일일 미션 · 스토어(v0.3.64 / 폰 1.0.13)")
struct MeDailyMissionStoreTests {
    // MARK: - 서버 계약 픽스처

    struct DailyDef: Sendable {
        let key: String
        let game: String
        let title: String
        let sort: Int
    }

    /// 서버 `daily_mission_defs()` 그대로(인수인계 §1) — 보상은 전부 5 · target 1.
    nonisolated static let dailyDefs: [DailyDef] = [
        .init(key: "daily_timing_bar", game: "timing_bar", title: "타이밍 바 한 판 하기", sort: 10),
        .init(key: "daily_flappy", game: "flappy", title: "플래피 아잉 한 판 하기", sort: 20),
        .init(key: "daily_tetris", game: "tetris", title: "테트리스 한 판 하기", sort: 30),
        .init(key: "daily_gomoku", game: "gomoku", title: "1:1 오목 한 판 두기", sort: 40),
        .init(key: "daily_chess", game: "chess", title: "1:1 체스 한 판 두기", sort: 50),
        .init(key: "daily_tetris_duel", game: "tetris_duel", title: "1:1 테트리스 한 판 하기", sort: 60),
    ]

    /// 시험 시계(`MobileClock.demoInstant`) = 2026-09-17 14:05 KST.
    nonisolated static let baseNowMs = 1_789_621_500_000
    /// 그 날의 다음 KST 자정(2026-09-18 00:00 KST) — 9시간 55분 뒤.
    nonisolated static let resetMs = 1_789_657_200_000
    /// 그 다음 자정.
    nonisolated static let nextResetMs = resetMs + 86_400_000

    /// 일일 줄 하나.
    nonisolated static func dailyRow(_ def: DailyDef, done: Bool, claimed: Bool) -> String {
        let filled = done || claimed
        return #"{"key":"\#(def.key)","game":"\#(def.game)","title":"\#(def.title)","detail":"","reward":5,"target":1,"progress":\#(filled ? 1 : 0),"achieved":\#(filled),"claimed":\#(claimed),"achieved_at_ms":\#(filled ? "1789600000000" : "null"),"claimed_at_ms":\#(claimed ? "1789600000000" : "null"),"sort":\#(def.sort)}"#
    }

    /// 최상위 `daily` 묶음. `claimableCount`/`claimableRuby` 를 일부러 틀리게 실을 수 있다(화면은 줄에서 세야 한다).
    nonisolated static func daily(day: String = "2026-09-17", resetAtMs: Int = resetMs,
                                  done: Set<String> = [], claimed: Set<String> = [],
                                  claimableCount: Int? = nil, claimableRuby: Int? = nil) -> String {
        let rows = dailyDefs.map { dailyRow($0, done: done.contains($0.key), claimed: claimed.contains($0.key)) }
        let pending = dailyDefs.filter { done.contains($0.key) && !claimed.contains($0.key) }
        let count = claimableCount ?? pending.count
        let ruby = claimableRuby ?? (pending.count * 5)
        return #"{"kst_day":"\#(day)","reset_at_ms":\#(resetAtMs),"missions":[\#(rows.joined(separator: ","))],"claimable_count":\#(count),"claimable_ruby":\#(ruby)}"#
    }

    /// 누적 미션 두 줄(일일이 사라져도 **이쪽은 산다**를 재는 대조군) — `gomoku1`(보상 10) · `todo3`(보상 20).
    nonisolated static func cumulativeRows(achieved: Set<String>, claimed: Set<String>) -> [String] {
        let table = [(key: "gomoku1", title: "오목 한 판 두기", reward: 10, target: 1, sort: 30),
                     (key: "todo3", title: "할 일 3개 이상 등록하기", reward: 20, target: 3, sort: 20)]
        return table.map { row in
            let done = achieved.contains(row.key) || claimed.contains(row.key)
            return #"{"key":"\#(row.key)","series":"\#(row.key)","tier":1,"title":"\#(row.title)","detail":"","reward":\#(row.reward),"target":\#(row.target),"progress":\#(done ? row.target : 0),"achieved":\#(done),"claimed":\#(claimed.contains(row.key)),"achieved_at_ms":\#(done ? "1789000000000" : "null"),"claimed_at_ms":\#(claimed.contains(row.key) ? "1789000000000" : "null"),"sort":\#(row.sort)}"#
        }
    }

    /// `achievements_status()` · `achievement_claim()` · `daily_mission_claim()` 의 응답 한 벌.
    /// - dailyJSON: 최상위 `daily` 에 실을 글자. nil 이면 **칸 자체가 없다**(옛 서버).
    /// - claimedNow: 이 호출이 장부에 넣었다고 서버가 말한 (키, 제목, 보상).
    nonisolated static func status(dailyJSON: String? = nil,
                                   cumulativeAchieved: Set<String> = [], cumulativeClaimed: Set<String> = [],
                                   claimedNow: [(key: String, title: String, reward: Int)] = [],
                                   ruby: Int? = 1_000, serverNowMs: Int? = baseNowMs) -> String {
        let rows = cumulativeRows(achieved: cumulativeAchieved, claimed: cumulativeClaimed)
        let now = claimedNow.map { #"{"key":"\#($0.key)","title":"\#($0.title)","reward":\#($0.reward)}"# }
        let claimableCumulative = cumulativeAchieved.subtracting(cumulativeClaimed)
        let cumulativeRuby = claimableCumulative.reduce(0) { $0 + ($1 == "gomoku1" ? 10 : 20) }
        let balance = ruby.map { #","ruby_balance":\#($0)"# } ?? ""
        let clock = serverNowMs.map { #","server_now_ms":\#($0)"# } ?? ""
        let dailyKey = dailyJSON.map { #","daily":\#($0)"# } ?? ""
        return #"{"launch_at_ms":1781000000000,"missions":[\#(rows.joined(separator: ","))],"claimable_count":\#(claimableCumulative.count),"claimable_ruby":\#(cumulativeRuby),"claimed_now":[\#(now.joined(separator: ","))]\#(balance)\#(clock)\#(dailyKey)}"#
    }

    /// 나 탭이 띄우는 다른 조회(주간 · 상점 · 미니게임)를 조용히 성공시키는 응답기 — 미션 조회만 세기 위한 것.
    nonisolated static func quietResponder(_ request: MobileStubRequest) -> MobileStubResponse? {
        switch request.rpcName {
        case "weekly_work_status":
            return .json(#"{"week_start":"2026-09-14","next_week_start":"2026-09-21","worked_seconds":3600,"tiers":[],"granted_now":[],"ruby_balance":1000,"server_now_ms":1789621500000}"#)
        case "shop_state":
            return .json(#"{"ruby_balance":1000,"characters":[]}"#)
        case "minigame_board":
            return .json("[]")
        case "minigame_start_round":
            return .json(#"{"status":"ok","token":"tok-next"}"#)
        default:
            return nil
        }
    }

    // MARK: - ① `daily` 가 없다 · null 이다 · 깨졌다 → 일일만 숨고 나머지는 산다

    @Test("daily 가 없으면/null 이면/객체가 아니면 **일일만** 감춘다 — 누적 줄 · 누적 받을 수 · 배지는 그대로")
    func missingDailyHidesOnlyDailySection() async throws {
        // ★ 라벨은 ASCII 여야 한다 — `BaseStub.makeHost` 가 호스트 이름에 그대로 박아서 한글을 넣으면 URL 이 안 선다.
        let cases: [(label: String, json: String?, say: String)] = [
            ("absent", nil, "칸 없음"), ("null", "null", "null"),
            ("text", #""오늘""#, "문자열"), ("number", "7", "숫자"),
        ]
        for (label, dailyJSON, say) in cases {
            let harness = await RankMeHarness(label: "me-daily-\(label)") { Self.quietResponder($0) }
            let store = harness.me
            harness.enqueue("achievements_status", .json(Self.status(dailyJSON: dailyJSON, cumulativeAchieved: ["gomoku1"])))
            await store.loadAchievements()

            #expect(store.dailyMissionRows == nil, "[\(say)] 일일 줄을 그린다")
            #expect(store.dailyMissionClaimableCount == 0 && store.dailyMissionClaimableRuby == 0,
                    "[\(say)] 일일 받을 수가 \(store.dailyMissionClaimableCount)")
            // 대조: 누적은 산다(일일 한 칸 때문에 통째로 죽지 않는다).
            #expect(store.achievementRows.map(\.key) == ["todo3", "gomoku1"], "[\(say)] 누적 줄: \(store.achievementRows.map(\.key))")
            #expect(store.achievementClaimableCount == 1 && store.achievementClaimableRuby == 10, "[\(say)] 누적 받을 수")
            #expect(store.missionClaimableCount == 1, "[\(say)] 배지가 \(store.missionClaimableCount)")
            // 일일 받기를 눌러도 요청이 안 나간다(그릴 줄이 없다).
            store.claimDailyMission(key: "daily_flappy")
            await harness.quiesceMe()
            #expect(harness.requests(rpc: "daily_mission_claim").isEmpty, "[\(say)] 없는 일일을 받으러 갔다")
            harness.expectNoForbiddenCalls()
            harness.tearDown()
        }
    }

    @Test("줄 하나가 깨져도 그 줄만 버린다(키 없음 · 제목 빈칸) — 남은 줄은 서버 글자 그대로 선다")
    func brokenRowsAreDroppedOneByOne() async throws {
        let harness = await RankMeHarness(label: "me-daily-broken-row") { Self.quietResponder($0) }
        defer { harness.tearDown() }
        let store = harness.me
        let rows = [
            #"{"game":"flappy","title":"키가 없는 줄","reward":5,"target":1,"progress":1,"achieved":true,"claimed":false,"sort":5}"#,
            #"{"key":"daily_tetris","game":"tetris","title":"   ","reward":5,"target":1,"progress":1,"achieved":true,"claimed":false,"sort":15}"#,
            Self.dailyRow(Self.dailyDefs[1], done: true, claimed: false),
        ]
        let daily = #"{"kst_day":"2026-09-17","reset_at_ms":\#(Self.resetMs),"missions":[\#(rows.joined(separator: ","))],"claimable_count":3,"claimable_ruby":15}"#
        harness.enqueue("achievements_status", .json(Self.status(dailyJSON: daily)))
        await store.loadAchievements()

        let drawn = try #require(store.dailyMissionRows)
        #expect(drawn.map(\.key) == ["daily_flappy"], "깨진 줄까지 그렸거나 성한 줄을 버렸다: \(drawn.map(\.key))")
        #expect(drawn[0].row.title == "플래피 아잉 한 판 하기" && drawn[0].row.reward == 5 && drawn[0].game == "flappy")
        #expect(store.dailyMissionClaimableCount == 1 && store.dailyMissionClaimableRuby == 5,
                "서버가 센 3 · 15 를 그대로 믿었다: \(store.dailyMissionClaimableCount) · \(store.dailyMissionClaimableRuby)")
    }

    // MARK: - ② 줄 · 수 · 배지

    @Test("6줄이 sort 순으로 · 제목은 서버 글자 · 받을 수와 루비는 **줄에서** 센다 · 배지 = 일일 + 누적")
    func rowsCountAndBadge() async throws {
        let harness = await RankMeHarness(label: "me-daily-rows") { Self.quietResponder($0) }
        defer { harness.tearDown() }
        let store = harness.me
        // 서버가 센 수를 **일부러 틀리게** 싣는다.
        harness.enqueue("achievements_status", .json(Self.status(
            dailyJSON: Self.daily(done: ["daily_flappy", "daily_gomoku"], claimed: ["daily_timing_bar"],
                                  claimableCount: 99, claimableRuby: 9_999),
            cumulativeAchieved: ["todo3"])))
        await store.loadAchievements()

        let rows = try #require(store.dailyMissionRows)
        #expect(rows.map(\.key) == ["daily_timing_bar", "daily_flappy", "daily_tetris", "daily_gomoku", "daily_chess", "daily_tetris_duel"],
                "sort 순이 아니다: \(rows.map(\.key))")
        #expect(rows.map(\.game) == ["timing_bar", "flappy", "tetris", "gomoku", "chess", "tetris_duel"])
        #expect(rows[1].row.title == "플래피 아잉 한 판 하기" && rows[5].row.title == "1:1 테트리스 한 판 하기",
                "제목이 서버 글자가 아니다")
        #expect(rows[0].row.state == .claimed && rows[1].row.state == .claimable && rows[2].row.state == .inProgress)
        #expect(store.dailyMissionClaimableCount == 2 && store.dailyMissionClaimableRuby == 10,
                "서버가 센 99 · 9999 를 그대로 믿었다: \(store.dailyMissionClaimableCount) · \(store.dailyMissionClaimableRuby)")
        // 배지 = 일일 2 + 누적 1(todo3) + 주간 0.
        #expect(store.achievementClaimableCount == 1)
        #expect(store.missionClaimableCount == 3, "배지가 \(store.missionClaimableCount)")
        #expect(harness.model.badges.badge(for: .me) == 3, "탭 막대가 스토어와 다른 수를 말한다")
        harness.expectNoForbiddenCalls()
    }

    // MARK: - ③ 받기

    @Test("받기: 본문 {\"p_key\":\"daily_flappy\"} · claimed_now 만큼 그 줄 위에 연출 · 잔량 · 받을 수가 줄어든다")
    func claimOneDailyRow() async throws {
        let harness = await RankMeHarness(label: "me-daily-claim") { Self.quietResponder($0) }
        defer { harness.tearDown() }
        let store = harness.me
        harness.enqueue("achievements_status", .json(Self.status(
            dailyJSON: Self.daily(done: ["daily_flappy", "daily_gomoku"]), cumulativeAchieved: ["todo3"], ruby: 1_000)))
        await store.loadAchievements()
        #expect(store.dailyMissionClaimableCount == 2 && store.missionClaimableCount == 3)

        harness.enqueue("daily_mission_claim", .json(Self.status(
            dailyJSON: Self.daily(done: ["daily_gomoku"], claimed: ["daily_flappy"]),
            cumulativeAchieved: ["todo3"], claimedNow: [("daily_flappy", "플래피 아잉 한 판 하기", 5)], ruby: 1_005)))
        store.claimDailyMission(key: "daily_flappy")
        await harness.quiesceMe()

        let calls = harness.requests(rpc: "daily_mission_claim")
        #expect(calls.count == 1 && calls.first?.method == "POST")
        #expect(calls.first?.bodyText == #"{"p_key":"daily_flappy"}"#, "본문: \(calls.first?.bodyText ?? "")")
        #expect(store.rubyBalance == 1_005 && harness.model.gomokuHost.rubyBalance == 1_005)
        let flappy = try #require(store.dailyMissionRows?.first { $0.key == "daily_flappy" })
        #expect(flappy.row.state == .claimed, "받았는데 줄이 \(flappy.row.state)")
        #expect(store.dailyMissionClaimableCount == 1 && store.missionClaimableCount == 2)
        let burst = try #require(store.dailyClaimBurst(key: "daily_flappy"), "받기 연출이 안 섰다")
        #expect(burst.amount == 5 && burst.target == "daily:daily_flappy" && store.missionClaimBurstSerial == 1)
        #expect(store.claimBurst(series: "todo3") == nil, "일일 받기가 누적 줄 위에 연출을 세웠다")
        #expect(!store.isClaimingDailyMission("daily_flappy") && !store.dailyMissionClaimDidFail("daily_flappy"))

        // 이미 받은 것을 또 받으면 요청 0건(받을 수 있는 줄이 아니다 — 서버를 두드리지 않는다).
        store.claimDailyMission(key: "daily_flappy")
        await harness.quiesceMe()
        #expect(harness.requests(rpc: "daily_mission_claim").count == 1, "이미 받은 줄을 또 받으러 갔다")
        #expect(store.missionClaimBurstSerial == 1)
        harness.expectNoForbiddenCalls()
    }

    @Test("전부 받기: 본문 p_key null · 받을 것이 없으면 요청 0건 · 연출은 지급된 줄마다 하나")
    func claimAllDailyRows() async throws {
        let harness = await RankMeHarness(label: "me-daily-claim-all") { Self.quietResponder($0) }
        defer { harness.tearDown() }
        let store = harness.me
        harness.enqueue("achievements_status", .json(Self.status(dailyJSON: Self.daily(claimed: ["daily_tetris"]))))
        await store.loadAchievements()
        let quiet = harness.requests(rpc: "achievements_status").count
        store.claimAllDailyMissions()
        await harness.quiesceMe()
        #expect(harness.requests(rpc: "daily_mission_claim").isEmpty, "받을 것이 없는데 전부 받기를 보냈다")
        #expect(harness.requests(rpc: "achievements_status").count == quiet,
                "받을 것도 없고 날도 안 넘겼는데 조회를 냈다: \(harness.requests(rpc: "achievements_status").count - quiet)건")

        harness.enqueue("achievements_status", .json(Self.status(dailyJSON: Self.daily(done: ["daily_flappy", "daily_chess"],
                                                                                       claimed: ["daily_tetris"]))))
        harness.clock.advance(61)
        await store.loadAchievements()
        harness.enqueue("daily_mission_claim", .json(Self.status(
            dailyJSON: Self.daily(claimed: ["daily_tetris", "daily_flappy", "daily_chess"]),
            claimedNow: [("daily_flappy", "플래피 아잉 한 판 하기", 5), ("daily_chess", "1:1 체스 한 판 두기", 5)], ruby: 1_010)))
        store.claimAllDailyMissions()
        await harness.quiesceMe()

        let bodies = harness.requests(rpc: "daily_mission_claim").map(\.bodyText)
        #expect(bodies == [#"{"p_key":null}"#], "\(bodies)")
        #expect(store.dailyMissionClaimableCount == 0 && store.rubyBalance == 1_010)
        #expect(store.dailyClaimBurst(key: "daily_flappy")?.amount == 5 && store.dailyClaimBurst(key: "daily_chess")?.amount == 5)
        #expect(store.missionClaimBurstSerial == 2, "연출 순번: \(store.missionClaimBurstSerial)")
    }

    @Test("연타는 요청 하나 · 일일 전부 받기가 떠 있으면 일일 낱개도 기다린다 — 그런데 **누적 버튼은 그대로 살아 있다**")
    func inFlightIsCountedApartFromCumulative() async throws {
        let harness = await RankMeHarness(label: "me-daily-inflight") { Self.quietResponder($0) }
        defer { harness.tearDown() }
        let store = harness.me
        harness.enqueue("achievements_status", .json(Self.status(
            dailyJSON: Self.daily(done: ["daily_flappy", "daily_chess"]), cumulativeAchieved: ["todo3"])))
        await store.loadAchievements()

        // ① 연타.
        let hold = BaseHold.rpc("daily_mission_claim", host: harness.host)
        harness.enqueue("daily_mission_claim", .json(Self.status(
            dailyJSON: Self.daily(done: ["daily_chess"], claimed: ["daily_flappy"]), cumulativeAchieved: ["todo3"],
            claimedNow: [("daily_flappy", "플래피 아잉 한 판 하기", 5)], ruby: 1_005)))
        store.claimDailyMission(key: "daily_flappy")
        #expect(await hold.waitHeld())
        #expect(store.isClaimingDailyMission("daily_flappy"))
        // ★ 따로 센다 — 일일이 떠 있다고 누적 버튼이 흐려지면 안 된다.
        #expect(!store.isClaimingAchievement("todo3"), "일일 받기가 누적 버튼을 흐렸다")
        store.claimDailyMission(key: "daily_flappy")   // 연타
        #expect(await hold.releaseAndWaitDelivered())
        await harness.quiesceMe()
        #expect(harness.requests(rpc: "daily_mission_claim").count == 1, "연타로 요청이 두 번 나갔다(두 번 지급 시도)")

        // ② 일일 전부 받기가 떠 있는 동안 일일 낱개는 기다리고, 누적은 그대로 나간다.
        let all = BaseHold.rpc("daily_mission_claim", host: harness.host)
        harness.enqueue("daily_mission_claim", .json(Self.status(
            dailyJSON: Self.daily(claimed: ["daily_flappy", "daily_chess"]), cumulativeAchieved: ["todo3"],
            claimedNow: [("daily_chess", "1:1 체스 한 판 두기", 5)], ruby: 1_010)))
        harness.enqueue("achievement_claim", .json(Self.status(
            dailyJSON: Self.daily(done: ["daily_chess"], claimed: ["daily_flappy"]), cumulativeClaimed: ["todo3"],
            claimedNow: [("todo3", "할 일 3개 이상 등록하기", 20)], ruby: 1_030)))
        store.claimAllDailyMissions()
        #expect(await all.waitHeld())
        #expect(store.isClaimingDailyMission("daily_chess"), "일일 전부 받기가 떠 있는데 낱개 버튼이 살아 있다")
        #expect(!store.isClaimingAchievement("todo3"), "일일 전부 받기가 누적 버튼까지 흐렸다")
        store.claimDailyMission(key: "daily_chess")   // 막힌다
        store.claimAchievement(key: "todo3")          // 막히지 않는다
        #expect(await all.releaseAndWaitDelivered())
        await harness.quiesceMe()
        #expect(harness.requests(rpc: "daily_mission_claim").count == 2, "전부 받기 중에 낱개가 또 나갔다")
        #expect(harness.requests(rpc: "achievement_claim").count == 1, "일일 받기가 떠 있다고 누적 받기가 막혔다")
    }

    @Test("일일 받기 실패는 **일일 그 줄**에만 — 누적 줄엔 실패 문장이 안 선다(그 반대도) · 나 탭을 떠나면 걷힌다")
    func claimFailureStaysInDailyRow() async throws {
        let harness = await RankMeHarness(label: "me-daily-fail") { Self.quietResponder($0) }
        defer { harness.tearDown() }
        let store = harness.me
        harness.enqueue("achievements_status", .json(Self.status(
            dailyJSON: Self.daily(done: ["daily_flappy", "daily_chess"]), cumulativeAchieved: ["todo3"])))
        await store.loadAchievements()

        harness.enqueue("daily_mission_claim", .json(#"{"message":"boom"}"#, status: 503))
        store.claimDailyMission(key: "daily_flappy")
        await harness.quiesceMe()
        #expect(store.dailyMissionClaimDidFail("daily_flappy"), "일일 받기 실패를 그 줄이 말하지 않는다")
        #expect(!store.dailyMissionClaimDidFail("daily_chess"), "다른 일일 줄에도 실패가 번졌다")
        #expect(!store.achievementClaimDidFail("todo3"), "일일 실패가 누적 줄에 실패 문장을 세웠다")
        #expect(store.dailyMissionClaimableCount == 2 && !store.isClaimingDailyMission("daily_flappy"),
                "실패했는데 [받기]가 사라졌다(다시 누르는 것이 재시도다)")
        #expect(store.missionClaimBurstSerial == 0 && store.rubyBalance == 1_000)

        // 반대 방향: 누적 받기 실패가 일일 줄에 서지 않는다.
        harness.enqueue("achievement_claim", .json(#"{"message":"boom"}"#, status: 503))
        store.claimAchievement(key: "todo3")
        await harness.quiesceMe()
        #expect(store.achievementClaimDidFail("todo3"))
        #expect(!store.dailyMissionClaimDidFail("daily_chess"), "누적 실패가 일일 줄에 번졌다")

        // 다시 누르면 재시도 — 성공하면 그 줄의 실패만 걷힌다.
        harness.enqueue("daily_mission_claim", .json(Self.status(
            dailyJSON: Self.daily(done: ["daily_chess"], claimed: ["daily_flappy"]), cumulativeAchieved: ["todo3"],
            claimedNow: [("daily_flappy", "플래피 아잉 한 판 하기", 5)], ruby: 1_005)))
        store.claimDailyMission(key: "daily_flappy")
        await harness.quiesceMe()
        #expect(!store.dailyMissionClaimDidFail("daily_flappy") && store.missionClaimBurstSerial == 1)
        #expect(store.achievementClaimDidFail("todo3"), "일일 받기 성공이 누적 줄의 실패 문장을 지웠다")

        // 나 탭을 떠나면 둘 다 걷힌다.
        store.tabDidDisappear()
        #expect(store.dailyMissionClaimFailedKeys.isEmpty && store.achievementClaimFailedKeys.isEmpty)
        #expect(store.missionClaimBursts.isEmpty)
    }

    @Test("장부는 두 벌이다: **전부 받기**가 자기 쪽 실패 문장만 걷는다 — 일일→누적 · 누적→일일 **두 방향 다**")
    func ledgersAreKeptApart() async throws {
        let harness = await RankMeHarness(label: "me-daily-two-ledgers") { Self.quietResponder($0) }
        defer { harness.tearDown() }
        let store = harness.me
        harness.enqueue("achievements_status", .json(Self.status(
            dailyJSON: Self.daily(done: ["daily_flappy", "daily_chess"]),
            cumulativeAchieved: ["todo3", "gomoku1"])))
        await store.loadAchievements()

        // ① 양쪽 다 실패를 세운다.
        harness.enqueue("daily_mission_claim", .json(#"{"message":"boom"}"#, status: 503))
        store.claimDailyMission(key: "daily_chess")
        await harness.quiesceMe()
        harness.enqueue("achievement_claim", .json(#"{"message":"boom"}"#, status: 503))
        store.claimAchievement(key: "todo3")
        await harness.quiesceMe()
        #expect(store.dailyMissionClaimDidFail("daily_chess") && store.achievementClaimDidFail("todo3"), "전제가 안 섰다")

        // ② **일일** 전부 받기가 성공한다 — 제 장부는 통째로 비우지만 **누적** 줄의 실패 문장은 남아야 한다(← 이 방향).
        //    그 사이 1:1 오목 한 판이 끝나 `daily_gomoku` 가 새로 달성돼 왔다(④의 재료 — 서버가 같은 응답에 싣는다).
        harness.enqueue("daily_mission_claim", .json(Self.status(
            dailyJSON: Self.daily(done: ["daily_gomoku"], claimed: ["daily_flappy", "daily_chess"]),
            cumulativeAchieved: ["todo3", "gomoku1"],
            claimedNow: [("daily_flappy", "플래피 아잉 한 판 하기", 5), ("daily_chess", "1:1 체스 한 판 두기", 5)], ruby: 1_010)))
        store.claimAllDailyMissions()
        await harness.quiesceMe()
        #expect(store.dailyMissionClaimFailedKeys.isEmpty, "일일 전부 받기가 제 실패 문장을 안 걷었다")
        #expect(store.achievementClaimDidFail("todo3"),
                "일일 전부 받기가 **누적** 줄의 실패 문장까지 지웠다 — 장부가 한 벌이다: \(store.achievementClaimFailedKeys)")
        #expect(store.dailyMissionClaimableCount == 1, "대조: 새로 달성된 오목 줄이 받을 것으로 섰다")

        // ③ 이번엔 일일 쪽에 실패를 세워 둔다(방금 달성된 오목 줄).
        harness.enqueue("daily_mission_claim", .json(#"{"message":"boom"}"#, status: 503))
        store.claimDailyMission(key: "daily_gomoku")
        await harness.quiesceMe()
        #expect(store.dailyMissionClaimDidFail("daily_gomoku"), "전제가 안 섰다")

        // ④ **누적** 전부 받기가 성공한다 — 제 장부만 비우고 일일 줄의 실패 문장은 그대로다(→ 이 방향).
        harness.enqueue("achievement_claim", .json(Self.status(
            dailyJSON: Self.daily(done: ["daily_gomoku"], claimed: ["daily_flappy", "daily_chess"]),
            cumulativeClaimed: ["todo3", "gomoku1"],
            claimedNow: [("todo3", "할 일 3개 이상 등록하기", 20), ("gomoku1", "오목 한 판 두기", 10)], ruby: 1_040)))
        store.claimAllAchievements()
        await harness.quiesceMe()
        #expect(store.achievementClaimFailedKeys.isEmpty, "누적 전부 받기가 제 실패 문장을 안 걷었다")
        #expect(store.dailyMissionClaimDidFail("daily_gomoku"),
                "누적 전부 받기가 **일일** 줄의 실패 문장까지 지웠다 — 장부가 한 벌이다: \(store.dailyMissionClaimFailedKeys)")
    }

    @Test("떠 있음도 두 벌이다: **누적 전부 받기**(슬롯 `*`)가 떠 있어도 일일 [받기]는 안 흐려지고 요청이 나간다")
    func cumulativeClaimAllDoesNotBlockDaily() async throws {
        let harness = await RankMeHarness(label: "me-daily-slot-apart") { Self.quietResponder($0) }
        defer { harness.tearDown() }
        let store = harness.me
        harness.enqueue("achievements_status", .json(Self.status(
            dailyJSON: Self.daily(done: ["daily_gomoku"]), cumulativeAchieved: ["todo3", "gomoku1"])))
        await store.loadAchievements()
        #expect(store.achievementClaimableCount == 2 && store.dailyMissionClaimableCount == 1, "전제가 안 섰다")

        // 누적 전부 받기는 **키가 아닌 슬롯 `*`** 로 적힌다 — 한 장부를 쓰면 이 슬롯이 모든 일일 버튼까지 흐린다.
        let hold = BaseHold.rpc("achievement_claim", host: harness.host)
        harness.enqueue("achievement_claim", .json(Self.status(
            dailyJSON: Self.daily(done: ["daily_gomoku"]), cumulativeClaimed: ["todo3", "gomoku1"],
            claimedNow: [("todo3", "할 일 3개 이상 등록하기", 20), ("gomoku1", "오목 한 판 두기", 10)], ruby: 1_030)))
        harness.enqueue("daily_mission_claim", .json(Self.status(
            dailyJSON: Self.daily(claimed: ["daily_gomoku"]), cumulativeAchieved: ["todo3", "gomoku1"],
            claimedNow: [("daily_gomoku", "1:1 오목 한 판 두기", 5)], ruby: 1_005)))
        store.claimAllAchievements()
        #expect(await hold.waitHeld())
        #expect(store.isClaimingAchievement("todo3"), "전부 받기가 누적 버튼을 안 흐렸다(슬롯 규약이 깨졌다)")
        #expect(!store.isClaimingDailyMission("daily_gomoku"), "누적 전부 받기가 일일 버튼까지 흐렸다 — 떠 있음이 한 벌이다")

        store.claimDailyMission(key: "daily_gomoku")
        #expect(await hold.releaseAndWaitDelivered())
        await harness.quiesceMe()
        #expect(harness.requests(rpc: "daily_mission_claim").count == 1,
                "누적 전부 받기가 떠 있다고 일일 받기가 막혔다: \(harness.requests(rpc: "daily_mission_claim").count)건")
        #expect(store.dailyClaimBurst(key: "daily_gomoku")?.amount == 5, "막힌 받기는 연출도 없다")
    }

    @Test("받기 함수가 없는 서버(PGRST202): **일일만** 접는다(누적은 산다) · 접힌 뒤 받기 0건 · daily 가 다시 오면 되살아난다")
    func missingClaimFunctionFoldsOnlyDaily() async throws {
        let harness = await RankMeHarness(label: "me-daily-missing-fn") { Self.quietResponder($0) }
        defer { harness.tearDown() }
        let store = harness.me
        harness.enqueue("achievements_status", .json(Self.status(
            dailyJSON: Self.daily(done: ["daily_flappy"]), cumulativeAchieved: ["todo3"])))
        await store.loadAchievements()
        #expect(store.dailyMissionRows?.count == 6)

        harness.enqueue("daily_mission_claim", .missingFunction("/rest/v1/rpc/daily_mission_claim"))
        store.claimDailyMission(key: "daily_flappy")
        await harness.quiesceMe()
        #expect(!store.dailyMissionsAvailable && store.dailyMissionRows == nil, "일일이 안 접혔다")
        #expect(!store.dailyMissionClaimDidFail("daily_flappy"), "기능이 없는 것을 '받지 못했어요'로 말했다")
        // 대조: 누적 · 주간은 그대로다(일일 404 가 절 전체를 쓸어가지 않는다).
        #expect(store.achievementsAvailable && store.achievementRows.count == 2 && store.achievementClaimableCount == 1)
        if case .loaded = store.achievementSection {} else { Issue.record("일일 404 가 누적 절을 지웠다: \(store.achievementSection)") }
        #expect(store.missionClaimableCount == 1, "접힌 일일이 배지에 남았다: \(store.missionClaimableCount)")

        // 접혔으면 더 두드리지 않는다.
        store.claimDailyMission(key: "daily_flappy")
        await harness.quiesceMe()
        #expect(harness.requests(rpc: "daily_mission_claim").count == 1, "접힌 뒤에도 받기가 나갔다")

        // 다음 조회가 `daily` 를 싣고 오면 되살아난다(한 마이그레이션이라 조회만 있는 서버는 없다).
        harness.clock.advance(61)
        harness.enqueue("achievements_status", .json(Self.status(dailyJSON: Self.daily(done: ["daily_flappy"]),
                                                                 cumulativeAchieved: ["todo3"])))
        await store.loadAchievements()
        #expect(store.dailyMissionsAvailable && store.dailyMissionRows?.count == 6 && store.dailyMissionClaimableCount == 1)
    }

    // MARK: - ④ 날 넘김(폰은 백그라운드에서 0시를 넘겨 돌아온다)

    @Test("백그라운드에서 자정을 넘겨 돌아오면: 어제 [받기]가 내려가고 · 배지에서 빠지고 · **스로틀을 건너뛰어** 새 날을 묻는다")
    func rolloverOnForegroundReturn() async throws {
        let harness = await RankMeHarness(label: "me-daily-rollover") { Self.quietResponder($0) }
        defer { harness.tearDown() }
        let store = harness.me
        // 서버 시각이 자정 30초 전이다 — 이 폰 시계와 9시간 55분 어긋나 있다(시계 차로 판정한다는 뜻).
        harness.enqueue("achievements_status", .json(Self.status(
            dailyJSON: Self.daily(done: ["daily_flappy", "daily_chess"]), cumulativeAchieved: ["todo3"],
            serverNowMs: Self.resetMs - 30_000)))
        await store.loadAchievements()
        #expect(store.dailyMissionClaimableCount == 2 && store.missionClaimableCount == 3)
        #expect(harness.requests(rpc: "achievements_status").count == 1)

        // 폰 시계로는 **40초**만 지났다(스로틀 60초 안이다). 그런데 서버 시각으로는 자정을 10초 넘겼다.
        harness.clock.advance(40)
        harness.enqueue("achievements_status", .json(Self.status(
            dailyJSON: Self.daily(day: "2026-09-18", resetAtMs: Self.nextResetMs),
            cumulativeAchieved: ["todo3"], serverNowMs: Self.resetMs + 5_000)))
        store.appDidBecomeActive()
        await harness.quiesceMe()

        #expect(harness.requests(rpc: "achievements_status").count == 2,
                "자정을 넘겨 돌아왔는데 새 날을 안 물었다(스로틀 60초 안이라 `IfStale` 로는 안 나간다): \(harness.requests(rpc: "achievements_status").count)건")
        let rows = try #require(store.dailyMissionRows)
        #expect(rows.count == 6 && rows.allSatisfy { $0.row.progress == 0 && !$0.row.achieved && !$0.row.claimed },
                "새 날인데 어제 진행이 남았다: \(rows.map { "\($0.key)=\($0.row.progress)" })")
        #expect(store.dailyMissionClaimableCount == 0, "어제 [받기]가 남았다")
        #expect(store.missionClaimableCount == 1, "배지에서 어제 일일이 안 빠졌다: \(store.missionClaimableCount)")
        harness.expectNoForbiddenCalls()
    }

    @Test("대조군: 자정을 **안** 넘겼으면 복귀에서 아무것도 안 묻는다(스로틀 그대로) · 줄도 그대로")
    func noRolloverNoExtraFetch() async throws {
        let harness = await RankMeHarness(label: "me-daily-norollover") { Self.quietResponder($0) }
        defer { harness.tearDown() }
        let store = harness.me
        // 같은 시나리오인데 서버 시각이 **자정 2분 전**이다 — 40초 뒤에도 아직 오늘이다.
        harness.enqueue("achievements_status", .json(Self.status(
            dailyJSON: Self.daily(done: ["daily_flappy", "daily_chess"]), cumulativeAchieved: ["todo3"],
            serverNowMs: Self.resetMs - 120_000)))
        await store.loadAchievements()
        harness.clock.advance(40)
        store.appDidBecomeActive()
        await harness.quiesceMe()

        #expect(harness.requests(rpc: "achievements_status").count == 1,
                "안 넘겼는데 또 물었다: \(harness.requests(rpc: "achievements_status").count)건")
        #expect(store.dailyMissionRolloverNoted == nil, "안 넘겼는데 넘김을 적었다")
        #expect(store.dailyMissionClaimableCount == 2 && store.missionClaimableCount == 3, "오늘 [받기]가 사라졌다")
    }

    @Test("화면에 남은 어제 [받기]를 누르면: 받기는 **0건**이고 조회를 한 번 낸다(반응 없는 버튼 금지)")
    func pressingYesterdayClaimAsksForToday() async throws {
        let harness = await RankMeHarness(label: "me-daily-stale-button") { Self.quietResponder($0) }
        defer { harness.tearDown() }
        let store = harness.me
        harness.enqueue("achievements_status", .json(Self.status(
            dailyJSON: Self.daily(done: ["daily_flappy"]), serverNowMs: Self.resetMs - 30_000)))
        await store.loadAchievements()
        #expect(store.dailyMissionClaimableCount == 1)

        harness.clock.advance(40)
        harness.enqueue("achievements_status", .json(Self.status(
            dailyJSON: Self.daily(day: "2026-09-18", resetAtMs: Self.nextResetMs), serverNowMs: Self.resetMs + 5_000)))
        store.claimDailyMission(key: "daily_flappy")
        await harness.quiesceMe()

        #expect(harness.requests(rpc: "daily_mission_claim").isEmpty,
                "어제 줄을 받으러 갔다(서버는 claimed_now: [] 로 답한다 — 반응 없는 버튼)")
        #expect(harness.requests(rpc: "achievements_status").count == 2, "새 날의 사실을 안 물었다")
        #expect(store.dailyMissionRolloverNoted == Self.resetMs, "넘김을 안 적었다")
        #expect(store.dailyMissionClaimableCount == 0)
    }

    @Test("화면에 남은 어제 **[전부 받기]**도 낱개와 같은 길: 받기 0건 · 조회 1건 · 줄이 새 날 모양으로 내려간다")
    func pressingYesterdayClaimAllAsksForToday() async throws {
        let harness = await RankMeHarness(label: "me-daily-stale-all") { Self.quietResponder($0) }
        defer { harness.tearDown() }
        let store = harness.me
        // 서버 시각이 자정 30초 전 — 두 줄이 받기 대기다.
        harness.enqueue("achievements_status", .json(Self.status(
            dailyJSON: Self.daily(done: ["daily_flappy", "daily_chess"]), serverNowMs: Self.resetMs - 30_000)))
        await store.loadAchievements()
        #expect(store.dailyMissionClaimableCount == 2 && harness.requests(rpc: "achievements_status").count == 1)

        // 폰 시계로 40초(스로틀 60초 안) — 서버 시각으로는 자정을 10초 넘겼다. 화면엔 아직 어제 [전부 받기]가 떠 있다.
        harness.clock.advance(40)
        harness.enqueue("achievements_status", .json(Self.status(
            dailyJSON: Self.daily(day: "2026-09-18", resetAtMs: Self.nextResetMs), serverNowMs: Self.resetMs + 5_000)))
        store.claimAllDailyMissions()
        await harness.quiesceMe()

        #expect(harness.requests(rpc: "daily_mission_claim").isEmpty,
                "어제 줄을 전부 받으러 갔다(서버는 claimed_now: [] 로 답한다 — 반응 없는 버튼)")
        #expect(harness.requests(rpc: "achievements_status").count == 2,
                "[전부 받기]가 새 날을 안 물었다 — 받을 수를 먼저 세고 돌아섰다(낱개와 다른 길): \(harness.requests(rpc: "achievements_status").count)건")
        #expect(store.dailyMissionRolloverNoted == Self.resetMs, "넘김을 안 적었다 — 버튼이 그 자리에서 안 내려간다")
        let rows = try #require(store.dailyMissionRows)
        #expect(rows.count == 6 && rows.allSatisfy { $0.row.progress == 0 && !$0.row.achieved && !$0.row.claimed },
                "새 날 모양이 아니다: \(rows.map { "\($0.key)=\($0.row.progress)" })")
        #expect(store.dailyMissionClaimableCount == 0 && store.missionClaimableCount == 0)
        harness.expectNoForbiddenCalls()
    }

    @Test("어제 받은 줄이 오늘 받음으로 남지 않는다(merged 는 같은 kst_day 안에서만)")
    func claimedDoesNotCarryIntoNewDay() async throws {
        let harness = await RankMeHarness(label: "me-daily-newday-merge") { Self.quietResponder($0) }
        defer { harness.tearDown() }
        let store = harness.me
        harness.enqueue("achievements_status", .json(Self.status(dailyJSON: Self.daily(claimed: ["daily_flappy"]))))
        await store.loadAchievements()
        #expect(store.dailyMissionRows?.first { $0.key == "daily_flappy" }?.row.claimed == true)

        harness.clock.advance(61)
        harness.enqueue("achievements_status", .json(Self.status(
            dailyJSON: Self.daily(day: "2026-09-18", resetAtMs: Self.nextResetMs, done: ["daily_flappy"]),
            serverNowMs: Self.resetMs + 60_000)))
        await store.loadAchievements()
        let flappy = try #require(store.dailyMissionRows?.first { $0.key == "daily_flappy" })
        #expect(!flappy.row.claimed && flappy.row.isClaimable, "어제 받음이 오늘로 넘어와 [받기]를 먹었다: \(flappy.row.state)")
        #expect(store.dailyMissionClaimableCount == 1)
    }

    // MARK: - ⑤ 판 끝난 뒤 조회

    @Test("판이 끝나면 한 번 묻는다(스로틀 무시) · 오늘 그 줄이 이미 채워졌으면 0건")
    func gameResultAsksOnceAndOnlyWhenUseful() async throws {
        let harness = await RankMeHarness(label: "me-daily-after-game") { Self.quietResponder($0) }
        defer { harness.tearDown() }
        let store = harness.me
        harness.enqueue("achievements_status", .json(Self.status(
            dailyJSON: Self.daily(done: ["daily_gomoku"], claimed: ["daily_tetris"]))))
        await store.loadAchievements()
        #expect(harness.requests(rpc: "achievements_status").count == 1)

        // 스로틀 60초 안이다 — 그래도 판이 끝난 조회는 나간다.
        harness.enqueue("achievements_status", .json(Self.status(
            dailyJSON: Self.daily(done: ["daily_gomoku", "daily_flappy"], claimed: ["daily_tetris"]))))
        store.refreshAchievementsAfterGameResult(game: "flappy")
        await harness.quiesceMe()
        #expect(harness.requests(rpc: "achievements_status").count == 2, "판이 끝났는데 안 물었다(스로틀에 막혔다)")
        #expect(store.dailyMissionClaimableCount == 2)

        // 이미 받기 대기인 줄(gomoku) · 이미 받은 줄(tetris) — 둘 다 물을 것이 없다.
        store.refreshAchievementsAfterGameResult(game: "gomoku")
        store.refreshAchievementsAfterGameResult(game: "tetris")
        store.refreshAchievementsAfterGameResult(game: "flappy")
        await harness.quiesceMe()
        #expect(harness.requests(rpc: "achievements_status").count == 2,
                "이미 채운 줄 때문에 조회가 \(harness.requests(rpc: "achievements_status").count)건까지 늘었다")

        // 모르는 줄(서버가 나중에 더할 게임)은 묻는다.
        harness.enqueue("achievements_status", .json(Self.status(dailyJSON: Self.daily(done: ["daily_gomoku", "daily_flappy"],
                                                                                       claimed: ["daily_tetris"]))))
        store.refreshAchievementsAfterGameResult(game: "curling")
        await harness.quiesceMe()
        #expect(harness.requests(rpc: "achievements_status").count == 3)
    }

    @Test("일일을 **모르는** 서버에서는 판이 끝나도 요청 0건(판마다 한 건씩 늘지 않는다) — 아는 서버에서는 반드시 1건")
    func gameResultIsSilentWhenTheServerHasNoDaily() async throws {
        let harness = await RankMeHarness(label: "me-daily-no-daily-server") { Self.quietResponder($0) }
        defer { harness.tearDown() }
        let store = harness.me
        // ① 옛 서버(db push 전) — 응답에 `daily` 칸이 아예 없다. 누적은 그대로 산다.
        harness.enqueue("achievements_status", .json(Self.status(dailyJSON: nil, cumulativeAchieved: ["todo3"])))
        await store.loadAchievements()
        #expect(store.dailyMissionRows == nil && store.achievementRows.count == 2, "전제가 안 섰다")
        let old = harness.requests(rpc: "achievements_status").count

        for game in ["flappy", "timing_bar", "tetris", "gomoku", "chess", "tetris_duel"] {
            store.refreshAchievementsAfterGameResult(game: game)
        }
        await harness.quiesceMe()
        #expect(harness.requests(rpc: "achievements_status").count == old,
                "일일이 없는 서버에서 판마다 조회가 늘었다: \(harness.requests(rpc: "achievements_status").count - old)건")
        #expect(!store.achievementsRefetchAfterGame, "물을 곳도 없는데 '끝난 뒤 한 번 더' 깃발이 섰다")

        // ② 받기가 404 로 접힌 서버도 같다 — `daily` 는 응답에 있지만 줄을 안 그리니 물을 까닭이 없다.
        harness.clock.advance(61)
        harness.enqueue("achievements_status", .json(Self.status(dailyJSON: Self.daily(done: ["daily_flappy"]),
                                                                 cumulativeAchieved: ["todo3"])))
        await store.loadAchievements()
        harness.enqueue("daily_mission_claim", .missingFunction("/rest/v1/rpc/daily_mission_claim"))
        store.claimDailyMission(key: "daily_flappy")
        await harness.quiesceMe()
        #expect(!store.dailyMissionsAvailable && store.achievements?.daily != nil, "전제가 안 섰다(접힌 서버)")
        let folded = harness.requests(rpc: "achievements_status").count
        store.refreshAchievementsAfterGameResult(game: "gomoku")
        await harness.quiesceMe()
        #expect(harness.requests(rpc: "achievements_status").count == folded,
                "접힌 서버에서 판이 끝났다고 물었다: \(harness.requests(rpc: "achievements_status").count - folded)건")

        // ③ ★ 대조: `daily` 가 실려 와 되살아나면 **안 채운 줄은 반드시 1건**이 나간다(이게 이 기능의 요점 — 과하게 막으면
        //    "판을 했는데 [받기]가 안 뜬다"로 되돌아간다).
        harness.clock.advance(61)
        harness.enqueue("achievements_status", .json(Self.status(dailyJSON: Self.daily(), cumulativeAchieved: ["todo3"])))
        await store.loadAchievements()
        #expect(store.dailyMissionsAvailable && store.dailyMissionRows?.count == 6, "되살아나지 않았다")
        let live = harness.requests(rpc: "achievements_status").count

        harness.enqueue("achievements_status", .json(Self.status(dailyJSON: Self.daily(done: ["daily_gomoku"]),
                                                                 cumulativeAchieved: ["todo3"])))
        store.refreshAchievementsAfterGameResult(game: "gomoku")
        await harness.quiesceMe()
        #expect(harness.requests(rpc: "achievements_status").count == live + 1,
                "일일을 아는 서버인데 판이 끝나도 안 물었다: \(harness.requests(rpc: "achievements_status").count - live)건")
        #expect(store.dailyMissionClaimableCount == 1, "판을 했는데 [받기]가 안 떴다")
        harness.expectNoForbiddenCalls()
    }

    @Test("판 **전에** 떠난 조회에 합류하지 않는다 — 그 조회가 끝난 **뒤** 한 번 더 묻고, 그 답이 화면을 정한다")
    func gameResultDoesNotJoinInFlightFetch() async throws {
        let harness = await RankMeHarness(label: "me-daily-refetch") { Self.quietResponder($0) }
        defer { harness.tearDown() }
        let store = harness.me
        harness.enqueue("achievements_status", .json(Self.status(dailyJSON: Self.daily())))
        await store.loadAchievements()
        #expect(store.dailyMissionClaimableCount == 0)

        let hold = BaseHold.rpc("achievements_status", host: harness.host)
        // ① 판 **전**에 떠난 조회의 답 — 아직 아무것도 안 했다.
        harness.enqueue("achievements_status", .json(Self.status(dailyJSON: Self.daily())))
        // ② 판이 끝난 **뒤**의 답 — 플래피 한 판이 서버에 남았다.
        harness.enqueue("achievements_status", .json(Self.status(dailyJSON: Self.daily(done: ["daily_flappy"]))))
        harness.clock.advance(61)
        store.refreshAchievementsIfStale()
        #expect(await hold.waitHeld())

        // 그 사이 판이 끝났다 — 떠 있는 조회에 합류하면 ①의 답(미달성)이 화면이 된다.
        store.refreshAchievementsAfterGameResult(game: "flappy")
        // 붙잡힌 요청은 놓아줄 때까지 스텁 기록에 안 남는다 — 그래서 여기 1건은 **맨 처음 조회**뿐이다.
        // 떠 있는 조회와 겹쳐 또 나갔다면 그 두 번째는 붙잡기 상한(1)을 넘어 곧바로 스텁에 닿아 2건이 된다.
        #expect(harness.requests(rpc: "achievements_status").count == 1, "떠 있는 조회와 겹쳐 또 나갔다")
        #expect(store.achievementsRefetchAfterGame, "합류도 안 하고 다시 묻지도 않는다 — 이 판은 영영 안 보인다")
        #expect(await hold.releaseAndWaitDelivered())
        await harness.quiesceMe()

        #expect(harness.requests(rpc: "achievements_status").count == 3,
                "끝난 뒤 한 번 더 묻지 않았다(판을 했는데 [받기]가 안 뜬다): \(harness.requests(rpc: "achievements_status").count)건")
        #expect(store.dailyMissionClaimableCount == 1, "①의 옛 답이 화면을 정했다")
        #expect(!store.achievementsState.isLoading && !store.achievementsRefetchAfterGame, "깃발이 남았다")
    }

    @Test("배선: 미니게임 제출이 성공하면 그 **게임 이름으로** 묻는다(이미 채운 게임은 0건)")
    func miniGameSubmitAsksForItsOwnGame() async throws {
        let harness = await RankMeHarness(label: "me-daily-wire-minigame") { request in
            if request.rpcName == "minigame_submit_score" { return .json(#"{"status":"ok","best_score":42,"plays":1}"#) }
            return Self.quietResponder(request)
        }
        defer { harness.tearDown() }
        let store = harness.me
        // 타이밍 바는 오늘 이미 했고, 플래피는 아직이다.
        harness.enqueue("achievements_status", .json(Self.status(dailyJSON: Self.daily(done: ["daily_timing_bar"]))))
        await store.loadAchievements()
        let before = harness.requests(rpc: "achievements_status").count

        // ① 이미 채운 게임 — 제출은 성공하지만 미션 조회는 0건.
        await harness.model.games.miniGames.performSubmit(kind: .timingBar, score: 10, token: "tok-1")
        await harness.quiesceMe()
        #expect(harness.requests(rpc: "minigame_submit_score").count == 1, "제출 경로를 안 돌았다")
        #expect(harness.requests(rpc: "achievements_status").count == before,
                "오늘 이미 채운 게임인데 또 물었다: \(harness.requests(rpc: "achievements_status").count - before)건")

        // ② 아직 안 한 게임 — 정확히 한 건.
        harness.enqueue("achievements_status", .json(Self.status(dailyJSON: Self.daily(done: ["daily_timing_bar", "daily_flappy"]))))
        await harness.model.games.miniGames.performSubmit(kind: .flappy, score: 10, token: "tok-2")
        await harness.quiesceMe()
        #expect(harness.requests(rpc: "achievements_status").count == before + 1,
                "제출이 미션 조회를 안 냈다 — 판을 했는데 [받기]가 안 뜬다")
        #expect(store.dailyMissionClaimableCount == 2)
    }

    @Test("배선: 1:1 판 종료 콜백 셋(오목 · 체스 · **테트리스는 tetris_duel**)이 걸려 있다")
    func duelMatchFinishedIsWired() async throws {
        let harness = await RankMeHarness(label: "me-daily-wire-duel") { Self.quietResponder($0) }
        defer { harness.tearDown() }
        let store = harness.me
        // 1:1 테트리스는 오늘 이미 했고, **솔로** 테트리스 줄은 아직이다 — 이름을 `tetris` 로 적으면 여기서 빨개진다.
        harness.enqueue("achievements_status", .json(Self.status(dailyJSON: Self.daily(done: ["daily_tetris_duel"]))))
        await store.loadAchievements()
        let before = harness.requests(rpc: "achievements_status").count

        #expect(harness.model.gomoku.onMatchFinished != nil && harness.model.chess.onMatchFinished != nil
                && harness.model.tetris.onMatchFinished != nil, "1:1 판 종료 콜백이 안 걸렸다")

        harness.model.tetris.onMatchFinished?()
        await harness.quiesceMe()
        #expect(harness.requests(rpc: "achievements_status").count == before,
                "1:1 테트리스를 `tetris`(솔로) 줄로 보고 또 물었다 — 서버 game 값은 `tetris_duel` 이다")

        harness.enqueue("achievements_status", .json(Self.status(dailyJSON: Self.daily(done: ["daily_tetris_duel", "daily_gomoku"]))))
        harness.model.gomoku.onMatchFinished?()
        await harness.quiesceMe()
        #expect(harness.requests(rpc: "achievements_status").count == before + 1, "오목 판 종료가 미션 조회를 안 냈다")

        harness.enqueue("achievements_status", .json(Self.status(dailyJSON: Self.daily(done: ["daily_tetris_duel", "daily_gomoku", "daily_chess"]))))
        harness.model.chess.onMatchFinished?()
        await harness.quiesceMe()
        #expect(harness.requests(rpc: "achievements_status").count == before + 2, "체스 판 종료가 미션 조회를 안 냈다")
        #expect(store.dailyMissionClaimableCount == 3)
    }

    // MARK: - ⑥ 늦은 응답 · 로그아웃

    @Test("받기 뒤에 도착한 '받기 전' 조회는 버린다 — 방금 받은 일일 줄에 [받기]가 다시 서지 않는다")
    func staleFetchAfterDailyClaimIsDropped() async throws {
        let harness = await RankMeHarness(label: "me-daily-stale-fetch") { Self.quietResponder($0) }
        defer { harness.tearDown() }
        let store = harness.me
        harness.enqueue("achievements_status", .json(Self.status(dailyJSON: Self.daily(done: ["daily_flappy"]))))
        await store.loadAchievements()

        let hold = BaseHold.rpc("achievements_status", host: harness.host)
        harness.enqueue("achievements_status", .json(Self.status(dailyJSON: Self.daily(done: ["daily_flappy"]), ruby: 1_000)))
        harness.enqueue("daily_mission_claim", .json(Self.status(
            dailyJSON: Self.daily(done: ["daily_chess"], claimed: ["daily_flappy"]),
            claimedNow: [("daily_flappy", "플래피 아잉 한 판 하기", 5)], ruby: 1_005)))
        harness.clock.advance(61)
        let fetch = Task { await store.loadAchievements() }
        #expect(await hold.waitHeld())
        store.claimDailyMission(key: "daily_flappy")
        await harness.quiesceMe()
        #expect(store.dailyMissionClaimableCount == 1 && store.rubyBalance == 1_005)

        #expect(await hold.releaseAndWaitDelivered())
        await fetch.value
        await harness.quiesceMe()
        let flappy = try #require(store.dailyMissionRows?.first { $0.key == "daily_flappy" })
        #expect(flappy.row.claimed, "받기 전 조회가 받은 일일 줄을 [받기]로 되돌렸다")
        #expect(store.dailyMissionClaimableCount == 1 && store.rubyBalance == 1_005,
                "받기 전 조회가 방금 열린 [받기] · 잔액을 되돌렸다")
    }

    @Test("로그아웃: reset 이 일일 값을 다 비우고 앞 계정의 늦은 받기는 서지 않는다")
    func signOutClearsDailyState() async throws {
        let harness = await RankMeHarness(label: "me-daily-signout") { Self.quietResponder($0) }
        defer { harness.tearDown() }
        let store = harness.me
        // 서버 시각이 자정 30초 전 — 시계 차가 0 이 아니게 만든다(reset 이 그 차까지 비우는지 재려고).
        harness.enqueue("achievements_status", .json(Self.status(
            dailyJSON: Self.daily(done: ["daily_flappy", "daily_chess"]), serverNowMs: Self.resetMs - 30_000)))
        await store.loadAchievements()
        harness.enqueue("daily_mission_claim", .json(#"{"message":"boom"}"#, status: 503))
        store.claimDailyMission(key: "daily_chess")
        await harness.quiesceMe()
        #expect(store.dailyMissionClaimDidFail("daily_chess"))

        // 받기 하나를 떠 있는 채로 둔 뒤 자정을 넘기고(넘김 표시) 로그아웃한다.
        let hold = BaseHold.rpc("daily_mission_claim", host: harness.host)
        harness.enqueue("daily_mission_claim", .json(Self.status(
            dailyJSON: Self.daily(claimed: ["daily_flappy"]),
            claimedNow: [("daily_flappy", "플래피 아잉 한 판 하기", 5)], ruby: 9_999)))
        store.claimDailyMission(key: "daily_flappy")
        #expect(await hold.waitHeld())
        harness.clock.advance(40)
        #expect(store.noteDailyMissionRollover(), "서버 시각으로 자정을 넘겼는데 안 적었다")
        #expect(store.dailyMissionRolloverNoted == Self.resetMs && store.achievementsServerClockOffsetMs != 0
                && !store.dailyMissionClaimsInFlight.isEmpty, "전제가 안 섰다")

        await harness.model.session.signOut()
        #expect(store.achievements == nil && store.dailyMissionRows == nil && store.dailyMissionsAvailable)
        #expect(store.dailyMissionClaimFailedKeys.isEmpty && store.dailyMissionClaimsInFlight.isEmpty)
        #expect(store.dailyMissionRolloverNoted == nil && store.achievementsServerClockOffsetMs == 0)
        #expect(store.missionClaimableCount == 0)

        #expect(await hold.releaseAndWaitDelivered())
        await harness.quiesceMe()
        #expect(store.dailyMissionRows == nil && store.missionClaimBurstSerial == 0, "로그아웃 뒤 앞 계정의 일일 받기가 섰다")
        #expect(harness.model.gomokuHost.rubyBalance == nil, "로그아웃 뒤 앞 계정의 잔량이 미러에 섰다")
    }
}
