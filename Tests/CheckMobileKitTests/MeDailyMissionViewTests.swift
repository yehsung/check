@testable import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

/// 나 탭 **「일일 미션」 절**(폰 1.0.13 — 서버 v0.3.64 `daily` · 맥 0.3.64 미션 화면 미러).
///
/// ── 무엇을 재는가: 모양이 아니라 **그려지는 것** ──
/// 폰 뷰는 `#if os(iOS)` 라 맥 `swift test` 가 한 줄도 그리지 못한다(저장소 메모 '폰 뷰는 맥 스위트가 못 본다').
/// 그래서 이 절의 **판단을 뷰 밖 순수 값**(`MeDailyMissionSection` · `MeDailyMissionRowContent`)으로 내보냈고,
/// 여기서는 그 값을 잰다 — "절이 있다"가 아니라 "이 줄에 [받기] 가 서는가 · 칩에 무슨 글자가 찍히는가 · 받을 보상이 몇 개인가".
/// 뷰가 그 값을 **정말로 읽는지**만 소스 계약(§6)으로 따로 못 박는다(그물 둘 — `MeAchievementViewTests` 와 같은 길).
///
/// 재는 자리:
///   §1 줄 · 절 — 6줄 sort 순 · 받을 수는 **줄에서** 센다 · 상태 셋의 그림 · 아이콘 · 실패 문장
///   §2 `daily` 없음 · null · 객체 아님 · 줄 깨짐 → **일일만** 숨고 누적 아홉 줄은 그대로 산다
///   §3 자정 넘김 → 진행 0 · [받기] 0 · 받을 보상 0(배지에서도 빠진다)
///   §4 스토어 다리 — 진짜 경로로 `daily_mission_claim` 한 번 · 연출은 그 줄 · **누적과 따로 센다**
///   §5 데모 픽스처 — 심사 데모에서 [받기] 가 서고(숨김 계정 함정) 받기 경로가 닿는다
///   §6 배선(소스 계약) — 자리 · 같은 버튼 · 서버 글자 · 💎 0
@MainActor
@Suite("나 탭 일일 미션 화면(폰 1.0.13)")
struct MeDailyMissionViewTests {
    // MARK: - §0 재료

    /// 서버 `daily_mission_defs()` 그대로(정본은 `supabase/migrations/20261023130000_daily_missions.sql`).
    /// 워크트리에는 `supabase/` 가 없어서(저장소 메모) 마이그레이션 파일을 읽지 못한다 — 그래서 로스터를 여기 한 번 적고
    /// 픽스처를 전부 이 표와 대조한다. 값이 바뀌는 날 이 표와 픽스처를 같이 고친다.
    nonisolated static let defs: [(key: String, game: String, title: String, reward: Int, target: Int, sort: Int)] = [
        ("daily_timing_bar", "timing_bar", "타이밍 바 한 판 하기", 5, 1, 10),
        ("daily_flappy", "flappy", "플래피 아잉 한 판 하기", 5, 1, 20),
        ("daily_tetris", "tetris", "테트리스 한 판 하기", 5, 1, 30),
        ("daily_gomoku", "gomoku", "1:1 오목 한 판 두기", 5, 1, 40),
        ("daily_chess", "chess", "1:1 체스 한 판 두기", 5, 1, 50),
        ("daily_tetris_duel", "tetris_duel", "1:1 테트리스 한 판 하기", 5, 1, 60),
    ]

    /// 고정 시계(`MobileClock.demoInstant`) = 2026-09-17 14:05 KST · 그날의 다음 자정(KST).
    nonisolated static let nowMs = 1_789_621_500_000
    nonisolated static let resetMs = 1_789_657_200_000
    nonisolated static let kstDay = "2026-09-17"

    /// 서버 `daily` 묶음 한 벌(줄 칸 이름 · 순서까지 서버 그대로). `met`/`claimed` 로 상태를 고른다.
    nonisolated static func dailyJSON(met: Set<String> = [], claimed: Set<String> = [],
                                      kstDay: String? = kstDay, resetAtMs: Int? = resetMs,
                                      only: [String]? = nil, extraRows: [String] = []) -> String {
        let rows = defs.filter { only?.contains($0.key) ?? true }.map { def -> String in
            let got = claimed.contains(def.key)
            let done = got || met.contains(def.key)
            return #"{"key":"\#(def.key)","game":"\#(def.game)","title":"\#(def.title)","detail":"","reward":\#(def.reward),"target":\#(def.target),"progress":\#(done ? def.target : 0),"achieved":\#(done),"claimed":\#(got),"claimed_at_ms":\#(got ? "1789603200000" : "null"),"sort":\#(def.sort)}"#
        } + extraRows
        let pending = defs.filter { met.contains($0.key) && !claimed.contains($0.key) }
        let day = kstDay.map { #""\#($0)""# } ?? "null"
        let reset = resetAtMs.map(String.init) ?? "null"
        return #"{"kst_day":\#(day),"reset_at_ms":\#(reset),"missions":[\#(rows.joined(separator: ","))],"claimable_count":\#(pending.count),"claimable_ruby":\#(pending.reduce(0) { $0 + $1.reward })}"#
    }

    /// `achievements_status()` 한 벌 = 누적 13줄(`MeAchievementClaimTests.status` 그대로) + 최상위 `daily`(날것 그대로 끼운다 —
    /// null · 숫자 · 깨진 줄도 그대로 보내려면 문자열이어야 한다).
    nonisolated static func response(daily: String?, achieved: Set<String> = ["todo3"], claimed: Set<String> = ["gomoku1"],
                                     claimedNow: [String] = [], ruby: Int? = 1_000) -> String {
        let base = MeAchievementClaimTests.status(achieved: achieved, claimed: claimed, ruby: ruby, claimedNow: claimedNow)
        guard let daily else { return base }
        return String(base.dropLast()) + #","daily":\#(daily)}"#
    }

    nonisolated static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    nonisolated static func decode(_ json: String) throws -> AchievementStatus {
        try decoder.decode(AchievementStatus.self, from: Data(json.utf8))
    }

    /// 화면이 그릴 절(서버 시각은 기본이 고정 시계 — 날을 안 넘긴 상태).
    nonisolated static func section(_ json: String, serverNowMs: Int? = nowMs) throws -> MeDailyMissionSection {
        .make(daily: try decode(json).daily, serverNowMs: serverNowMs)
    }

    nonisolated static func content(_ section: MeDailyMissionSection, _ key: String,
                                    failed: Bool = false) throws -> MeDailyMissionRowContent {
        let mission = try #require(section.rows.first { $0.key == key }, "줄 \(key) 가 없다")
        return .make(mission: mission, failed: failed)
    }

    // MARK: - §1 무엇이 그려지는가

    @Test("절: 서버가 준 6줄을 sort 순으로 그린다 · 제목은 서버 글자 · 받을 수와 루비는 **줄에서** 센다")
    func sectionDrawsTheSixServerRowsInOrder() throws {
        // 서버가 센 수를 일부러 믿지 않게 한다: 줄 둘이 받을 수 있는데 묶음의 claimable_count 는 99 라고 적혀 온다.
        let liar = Self.dailyJSON(met: ["daily_timing_bar", "daily_gomoku"], claimed: ["daily_flappy"])
            .replacingOccurrences(of: #""claimable_count":2"#, with: #""claimable_count":99"#)
            .replacingOccurrences(of: #""claimable_ruby":10"#, with: #""claimable_ruby":999"#)
        let section = try Self.section(Self.response(daily: liar))

        #expect(section.rows.map(\.key) == Self.defs.map(\.key), "줄 순서(sort): \(section.rows.map(\.key))")
        #expect(section.rows.map(\.row.title) == Self.defs.map(\.title), "제목이 서버 글자가 아니다")
        #expect(section.rows.map(\.game) == Self.defs.map(\.game), "게임 칸(아이콘을 고르는 값)")
        #expect(section.rows.map(\.row.reward) == Self.defs.map(\.reward), "보상이 서버 값이 아니다")
        #expect(section.claimableCount == 2 && section.claimableRuby == 10,
                "서버가 센 99 · 999 를 그대로 믿었다: \(section.claimableCount) · \(section.claimableRuby)")
        // 상태 셋이 한 절 안에 다 있다(기준선이 갈린다).
        #expect(section.rows.map(\.row.state) == [.claimable, .claimed, .inProgress, .claimable, .inProgress, .inProgress],
                "줄 상태: \(section.rows.map(\.row.state))")

        // 줄이 0개면 카드째 없다(머리만 뜬 빈 카드를 세우지 않는다).
        #expect(try Self.section(Self.response(daily: #"{"kst_day":"2026-09-17","reset_at_ms":1789657200000,"missions":[],"claimable_count":0,"claimable_ruby":0}"#)) == .hidden,
                "줄 0개인데 절이 선다")
    }

    @Test("줄 셋의 그림: 진행 중(칩 +5 · '0/1') · [받기] 캡슐(칩 없음) · '✓ 받음'(진행 숫자 없음)")
    func rowContentDrawsTheThreeStates() throws {
        let section = try Self.section(Self.response(daily: Self.dailyJSON(met: ["daily_timing_bar"], claimed: ["daily_flappy"])))

        // ① 받을 수 있는 줄 — 버튼이 금액을 말하므로 **칩은 감춘다**(칩 "+5" 옆 버튼 "+5" 는 어느 것이 지금 받는 루비인지 헷갈린다).
        let claimable = try Self.content(section, "daily_timing_bar")
        #expect(claimable.claimAmount == 5, "[받기] 가 안 서거나 금액이 다르다: \(String(describing: claimable.claimAmount))")
        #expect(claimable.rewardChip == nil, "[받기] 줄에 보상 칩이 같이 선다")
        #expect(claimable.progress == nil && claimable.claimedMark == nil, "[받기] 줄에 진행 숫자나 '받음'이 같이 선다")
        #expect(claimable.fraction == 1 && !claimable.isClaimed)

        // ② 받은 줄 — 칩 + "✓ 받음", 버튼 없음.
        let claimed = try Self.content(section, "daily_flappy")
        #expect(claimed.claimAmount == nil, "받은 줄에 [받기] 가 또 선다(눌러도 아무것도 안 주는 거짓 버튼)")
        #expect(claimed.rewardChip == "+5" && claimed.claimedMark == "받음" && claimed.isClaimed)
        #expect(claimed.progress == nil, "받은 줄에 진행 숫자가 남았다")

        // ③ 진행 중 — 칩 + "0/1", 버튼 없음.
        let progress = try Self.content(section, "daily_tetris")
        #expect(progress.claimAmount == nil, "미달성 줄에 [받기] 가 선다")
        #expect(progress.rewardChip == "+5" && progress.progress == "0/1" && progress.claimedMark == nil)
        #expect(progress.fraction == 0 && !progress.isClaimed)

        // 제목 · 보조 문장은 서버 글자 그대로(폰 상수가 아니다) · 보이스오버도 그 제목을 읽는다.
        #expect(progress.title == "테트리스 한 판 하기" && progress.caption == "")
        #expect(claimable.accessibilityLabel == "타이밍 바 한 판 하기, 달성했어요")
        #expect(claimed.accessibilityLabel == "플래피 아잉 한 판 하기, 루비 5개 받았어요")
        #expect(progress.accessibilityLabel == "테트리스 한 판 하기, 0/1, 달성하면 루비 5개")
        // 💎 는 한 글자도 없다(루비는 `RubyIcon` 이 그린다 — 폰 규약).
        for text in [claimable.rewardChip, claimed.rewardChip, progress.rewardChip, progress.progress,
                     claimed.claimedMark, progress.accessibilityLabel] {
            #expect(!(text ?? "").contains("💎"), "글자 루비가 섞였다: \(text ?? "")")
        }
    }

    @Test("아이콘: 게임마다 폰이 이미 쓰는 기호(미니게임 셋 · 1:1 셋) · 모르는 게임은 별 · 여섯이 서로 다르다")
    func iconsReuseTheGameSymbols() throws {
        let section = try Self.section(Self.response(daily: Self.dailyJSON()))
        let icons = try Self.defs.map { try Self.content(section, $0.key).icon }
        #expect(icons == ["metronome.fill", "bird.fill", "square.grid.2x2.fill",
                          "circle.grid.3x3.fill", "checkerboard.rectangle", "rectangle.split.2x1.fill"],
                "아이콘: \(icons)")
        #expect(Set(icons).count == 6, "같은 기호를 쓰는 줄이 있다(줄을 눈으로 못 가른다): \(icons)")
        #expect(MeText.dailyMissionIcon(game: "timing_bar") == MiniGameKind.timingBar.icon,
                "미니게임 기호가 코어(게임 화면 · 순위표가 쓰는 그 기호)와 갈렸다")
        // 서버가 게임을 더해도 줄은 그려지고 아이콘만 기본값이 된다.
        #expect(MeText.dailyMissionIcon(game: "snake") == MeText.missionFallbackIcon)
        #expect(MeText.dailyMissionIcon(game: "") == MeText.missionFallbackIcon)
    }

    @Test("받기 실패는 **[받기] 가 선 줄 안**에서만 말한다(받은 줄 · 진행 줄엔 안 남는다)")
    func failureSpeaksOnlyInTheClaimableRow() throws {
        let section = try Self.section(Self.response(daily: Self.dailyJSON(met: ["daily_timing_bar"], claimed: ["daily_flappy"])))
        let failed = try Self.content(section, "daily_timing_bar", failed: true)
        #expect(failed.caption == MeText.claimFailed && failed.showsFailure, "받기 실패를 그 줄이 말하지 않는다")
        #expect(failed.claimAmount == 5, "실패했다고 [받기] 가 사라졌다 — 다시 누르는 것이 재시도다")
        // 그 사이 다른 기기에서 받았다 · 아직 미달성이다 → 실패 문장은 뜻이 없다(버튼이 없어 다시 누를 수도 없다).
        #expect(try !Self.content(section, "daily_flappy", failed: true).showsFailure, "받은 줄에 실패 문장이 남았다")
        #expect(try !Self.content(section, "daily_tetris", failed: true).showsFailure, "진행 줄에 실패 문장이 섰다")
        #expect(try Self.content(section, "daily_tetris", failed: true).caption == "", "진행 줄의 보조 문장이 실패로 덮였다")
    }

    // MARK: - §2 `daily` 가 없다 · null 이다 · 깨졌다 → 일일만 숨는다

    @Test("daily 없음 · null · 객체 아님 · 줄 깨짐: 일일 절만 숨고 **누적 아홉 줄은 그대로 산다**")
    func brokenDailyHidesOnlyTheDailySection() throws {
        for (label, raw) in [("칸 없음", String?.none), ("null", "null"), ("숫자", "5"), ("배열", "[]"),
                             ("빈 객체", "{}"), ("줄만 깨짐", #"{"kst_day":"2026-09-17","missions":[{"game":"flappy"}]}"#)] {
            let status = try Self.decode(Self.response(daily: raw))
            let section = MeDailyMissionSection.make(daily: status.daily, serverNowMs: Self.nowMs)
            #expect(section == .hidden, "\(label): 일일 절이 섰다")
            #expect(section.rows.isEmpty && section.claimableCount == 0 && section.claimableRuby == 0, "\(label): 배지가 섰다")
            // ★ 누적 미션은 한 줄도 잃지 않는다(일일 때문에 전체 응답이 죽으면 안 된다).
            #expect(status.missions.count == 13 && status.seriesRows.count == 9, "\(label): 누적 줄이 죽었다")
            #expect(status.claimableCount == 1 && status.rubyBalance == 1_000, "\(label): 누적 받을 것 · 잔량이 죽었다")
        }

        // 한 줄만 깨졌으면 **그 줄만** 버린다(나머지는 그린다) — 키 · 제목이 없는 줄이 그 줄이다.
        let partial = Self.dailyJSON(met: ["daily_gomoku"], only: ["daily_gomoku", "daily_chess"],
                                     extraRows: [#"{"game":"flappy","title":"제목만 있고 키가 없다","sort":5}"#,
                                                 #"{"key":"daily_tetris","title":"","sort":7}"#])
        let section = try Self.section(Self.response(daily: partial))
        #expect(section.rows.map(\.key) == ["daily_gomoku", "daily_chess"], "깨진 줄이 통째로 절을 죽였거나 살아남았다: \(section.rows.map(\.key))")
        #expect(section.claimableCount == 1 && section.claimableRuby == 5)
    }

    // MARK: - §3 자정 넘김

    @Test("자정을 넘긴 응답: 진행 0 · [받기] 0 · 받을 보상 0 — 넘기기 **전과 다르다**(기준선이 갈린다)")
    func rolledOverRowsLoseTheClaimButton() throws {
        let json = Self.response(daily: Self.dailyJSON(met: ["daily_timing_bar", "daily_gomoku"], claimed: ["daily_flappy"]))

        // 넘기기 전(자정 1초 전): 받을 것 둘 · 받은 줄 하나.
        let before = try Self.section(json, serverNowMs: Self.resetMs - 1_000)
        #expect(before.claimableCount == 2 && before.claimableRuby == 10, "대조: 넘기기 전에 이미 0 이면 이 시험은 공허하다")
        #expect(try Self.content(before, "daily_timing_bar").claimAmount == 5)
        #expect(try Self.content(before, "daily_flappy").claimedMark == "받음")

        // 자정을 지난 순간: 어제 [받기] 는 서지 않는다(누르면 서버가 빈 `claimed_now` 를 주는 반응 없는 버튼이 된다).
        let after = try Self.section(json, serverNowMs: Self.resetMs)
        #expect(after.rows.count == 6, "넘겼다고 줄이 사라졌다(절은 새 날의 모양으로 남는다)")
        #expect(after.claimableCount == 0 && after.claimableRuby == 0,
                "자정을 넘겼는데 받을 보상이 \(after.claimableCount)개 남았다 — 배지도 같이 거짓이 된다")
        for def in Self.defs {
            let row = try Self.content(after, def.key)
            #expect(row.claimAmount == nil, "\(def.key): 어제 [받기] 가 남았다")
            #expect(row.progress == "0/1" && row.fraction == 0, "\(def.key): 어제 진행이 남았다")
            #expect(row.claimedMark == nil && !row.isClaimed, "\(def.key): 어제 '받음'이 오늘로 넘어왔다")
            #expect(row.rewardChip == "+5", "\(def.key): 보상 칩까지 사라졌다")
        }
        // 리셋 시각을 모르면(옛 응답 · 깨진 칸) 끝났다고 단정하지 않는다 — 줄은 그대로다.
        let noReset = try Self.section(Self.response(daily: Self.dailyJSON(met: ["daily_timing_bar"], resetAtMs: nil)),
                                       serverNowMs: Self.resetMs + 86_400_000)
        #expect(noReset.claimableCount == 1, "리셋 시각을 모르는 응답을 어제 것으로 단정했다")
    }

    // MARK: - §4 스토어 다리(진짜 경로 — 뷰가 부르는 이름들)

    @Test("미션 조회가 오면 일일 절이 서고 [받기] 를 누르면 daily_mission_claim 한 번 · 연출은 그 줄 · 잔량이 는다")
    func claimingADailyRowGoesThroughTheDailyRPC() async throws {
        let harness = await RankMeHarness(label: "me-daily-claim") { MeAchievementClaimTests.quietResponder($0) }
        defer { harness.tearDown() }
        let store = harness.me
        harness.enqueue("achievements_status", .json(Self.response(
            daily: Self.dailyJSON(met: ["daily_timing_bar", "daily_gomoku"], claimed: ["daily_flappy"]), ruby: 100)))
        await store.loadAchievements()

        #expect(store.dailyMissionSection.rows.map(\.key) == Self.defs.map(\.key), "일일 절이 안 섰다")
        #expect(store.dailyMissionClaimableCount == 2, "받을 일일 미션 수")
        #expect(MeText.claimPendingHint(store.dailyMissionClaimableCount) == "받을 보상 2개", "머리 글자")
        #expect(harness.requests(rpc: "daily_mission_claim").isEmpty, "조회만 했는데 받기가 나갔다")

        // 그 줄의 [받기] — 일일 함수로 간다(누적 함수가 아니다).
        harness.enqueue("daily_mission_claim", .json(Self.response(
            daily: Self.dailyJSON(met: ["daily_gomoku"], claimed: ["daily_flappy", "daily_timing_bar"]),
            claimedNow: [], ruby: 105)
            .replacingOccurrences(of: #""claimed_now":[]"#,
                                  with: #""claimed_now":[{"key":"daily_timing_bar","title":"타이밍 바 한 판 하기","reward":5}]"#)))
        store.claimDailyMission(key: "daily_timing_bar")
        await harness.quiesceMe()

        let calls = harness.requests(rpc: "daily_mission_claim")
        #expect(calls.count == 1, "받기가 \(calls.count)번 나갔다")
        #expect(calls.first?.path == SupabaseWorkService.dailyMissionClaimPath, "누적 받기 함수로 갔다: \(calls.first?.path ?? "")")
        #expect(calls.first?.jsonBody["p_key"] as? String == "daily_timing_bar",
                "본문에 그 줄의 키가 없다(키 집합이 흔들리면 PostgREST 가 다른 서명을 찾는다): \(calls.first?.bodyText ?? "")")
        #expect(harness.requests(rpc: "achievement_claim").isEmpty, "일일 받기가 누적 받기 함수도 불렀다")

        // 받은 뒤: 그 줄은 '받음' · 받을 것은 하나 남고 · 연출은 **그 줄 자리**에 선다 · 잔량이 늘었다.
        #expect(try Self.content(store.dailyMissionSection, "daily_timing_bar").claimedMark == "받음")
        #expect(store.dailyMissionClaimableCount == 1, "받았는데 받을 수가 그대로다")
        let burst = try #require(store.dailyClaimBurst(key: "daily_timing_bar"), "받기 연출이 그 줄에 안 섰다")
        #expect(burst.amount == 5 && store.missionClaimBurstSerial == 1)
        #expect(store.dailyClaimBurst(key: "daily_gomoku") == nil, "안 받은 줄에서도 연출이 운다")
        #expect(store.claimBurst(series: "todo3") == nil, "일일 받기가 누적 줄에서 울었다")
        #expect(store.rubyBalance == 105, "잔량 미러가 안 늘었다: \(String(describing: store.rubyBalance))")
        #expect(!store.dailyMissionClaimDidFail("daily_timing_bar"))
        harness.expectNoForbiddenCalls()
    }

    @Test("같은 턴에 두 번 눌러도 요청 1건 · 받기 실패는 **그 일일 줄만**(누적 줄엔 실패 문장도 스피너도 없다)")
    func doublePressFiresOnceAndFailureStaysInTheDailyLedger() async throws {
        let harness = await RankMeHarness(label: "me-daily-fail") { MeAchievementClaimTests.quietResponder($0) }
        defer { harness.tearDown() }
        let store = harness.me
        harness.enqueue("achievements_status", .json(Self.response(
            daily: Self.dailyJSON(met: ["daily_timing_bar", "daily_gomoku"]), achieved: ["todo3", "poke10"])))
        await store.loadAchievements()
        #expect(store.achievementClaimableCount == 2 && store.dailyMissionClaimableCount == 2, "대조: 양쪽에 받을 것이 있다")

        // 받기가 실패한다(500) — 같은 턴에 두 번 눌렀다.
        harness.enqueue("daily_mission_claim", MobileStubResponse(status: 500, body: Data(#"{"message":"nope"}"#.utf8)))
        store.claimDailyMission(key: "daily_timing_bar")
        store.claimDailyMission(key: "daily_timing_bar")
        await harness.quiesceMe()

        #expect(harness.requests(rpc: "daily_mission_claim").count == 1,
                "두 번 눌러 \(harness.requests(rpc: "daily_mission_claim").count)건 나갔다(같은 줄을 두 요청이 함께 잡는다)")
        #expect(store.dailyMissionClaimDidFail("daily_timing_bar"), "실패를 그 줄이 모른다")
        #expect(!store.isClaimingDailyMission("daily_timing_bar"), "실패 뒤에도 버튼이 흐려진 채다")
        #expect(try Self.content(store.dailyMissionSection, "daily_timing_bar", failed: true).caption == MeText.claimFailed)

        // ★ 누적 쪽 장부는 한 글자도 안 움직인다(인수인계 §5-8 — 한쪽 실패가 다른 쪽 줄에 실패 문장을 세우면 안 된다).
        #expect(!store.achievementClaimDidFail("todo3") && !store.achievementClaimDidFail("daily_timing_bar"),
                "일일 실패가 누적 줄에 실패 문장을 세웠다: \(store.achievementClaimFailedKeys)")
        #expect(!store.isClaimingAchievement("todo3") && !store.isClaimingAchievement("poke10"),
                "일일 받기가 누적 [받기] 를 흐리게 했다")
        #expect(store.dailyMissionClaimableCount == 2, "실패했는데 받을 수가 줄었다")

        // 다시 누르는 것이 재시도 — 성공하면 그 줄의 실패 표시만 걷힌다.
        harness.enqueue("daily_mission_claim", .json(Self.response(
            daily: Self.dailyJSON(met: ["daily_gomoku"], claimed: ["daily_timing_bar"]), achieved: ["todo3", "poke10"])))
        store.claimDailyMission(key: "daily_timing_bar")
        await harness.quiesceMe()
        #expect(harness.requests(rpc: "daily_mission_claim").count == 2, "재시도가 안 나갔다")
        #expect(!store.dailyMissionClaimDidFail("daily_timing_bar"), "성공했는데 실패 문장이 남았다")
        #expect(store.dailyMissionClaimableCount == 1)
        harness.expectNoForbiddenCalls()
    }

    @Test("앱이 켜진 채 자정을 넘기면 스토어가 그린 [받기] 도 사라진다(서버 시각 + 흐른 시간으로 판정)")
    func theStoreDropsYesterdaysClaimButtonAfterMidnight() async throws {
        let harness = await RankMeHarness(label: "me-daily-rollover") { MeAchievementClaimTests.quietResponder($0) }
        defer { harness.tearDown() }
        let store = harness.me
        harness.enqueue("achievements_status", .json(Self.response(daily: Self.dailyJSON(met: ["daily_timing_bar"]))))
        await store.loadAchievements()
        #expect(store.dailyMissionClaimableCount == 1, "대조: 넘기기 전에 받을 것이 있다")
        #expect(store.estimatedServerNowMs() == Self.nowMs, "서버 시각 추정이 응답 값과 다르다")

        // 자정 1분 전 → 아직 받을 수 있다. 자정 1분 뒤 → 사라진다(새 조회 없이 화면 값만으로).
        harness.clock.advance(Double(Self.resetMs - Self.nowMs) / 1000 - 60)
        #expect(store.dailyMissionClaimableCount == 1, "자정 전인데 [받기] 가 먼저 사라졌다")
        harness.clock.advance(120)
        #expect(store.dailyMissionClaimableCount == 0, "자정을 넘겼는데 어제 [받기] 가 남았다")
        #expect(store.dailyMissionSection.rows.count == 6, "넘기면서 절이 통째로 사라졌다")
        #expect(store.achievementClaimableCount == 1, "일일 날 넘김이 누적 받을 것까지 지웠다")
    }

    // MARK: - §5 데모 픽스처(심사 데모 계정 — 숨김 계정이라 실서버에선 [받기] 가 안 선다)

    @Test("데모 픽스처 넷: daily 6줄이 서버 정의표 그대로 · 칸 이름이 정확히 그 집합 · 하루 경계가 고정 시계와 맞는다")
    func demoFixturesCarryTheServerDailyRoster() throws {
        let dailyKeys: Set<String> = ["kst_day", "reset_at_ms", "missions", "claimable_count", "claimable_ruby"]
        let rowKeys: Set<String> = ["key", "game", "title", "detail", "reward", "target", "progress", "achieved",
                                    "claimed", "claimed_at_ms", "sort"]
        let paths = MeAchievementsFixtureContractTests.missionPaths + Self.claimPaths
        for path in paths {
            let object = try MeAchievementsFixtureContractTests.raw(path)
            let daily = try #require(object["daily"] as? [String: Any], "\(path): daily 가 없다 — 데모에 일일 미션이 안 뜬다")
            #expect(MeAchievementsFixtureContractTests.keys(daily) == dailyKeys,
                    "\(path): daily 칸 이름 — \(MeAchievementsFixtureContractTests.keys(daily).symmetricDifference(dailyKeys))")
            #expect(daily["kst_day"] as? String == Self.kstDay, "\(path): kst_day")
            #expect(daily["reset_at_ms"] as? Int == Self.resetMs,
                    "\(path): reset_at_ms 가 다음 KST 자정이 아니다 — 데모가 날을 넘긴 것으로 보여 [받기] 가 사라진다")

            let rows = MeAchievementsFixtureContractTests.rows(daily, "missions")
            #expect(rows.count == Self.defs.count, "\(path): 일일 줄이 \(rows.count)개다(서버는 6개)")
            for (row, def) in zip(rows, Self.defs) {
                #expect(MeAchievementsFixtureContractTests.keys(row) == rowKeys,
                        "\(path) \(def.key): 줄 칸 이름 — \(MeAchievementsFixtureContractTests.keys(row).symmetricDifference(rowKeys))")
            }

            // 값: 정의표 그대로 · 달성/받음이 규칙과 맞는가 · 받은 시각이 **오늘 안**인가.
            let status = try MeAchievementsFixtureContractTests.status(path)
            let section = MeDailyMissionSection.make(daily: status.daily, serverNowMs: status.serverNowMs)
            #expect(section.rows.count == Self.defs.count, "\(path): 디코드 뒤 줄이 버려졌다")
            for (mission, def) in zip(section.rows, Self.defs) {
                #expect(mission.key == def.key && mission.game == def.game, "\(path): 순서 · 게임 — \(mission.key)")
                #expect(mission.row.title == def.title, "\(path) \(def.key): 제목")
                #expect(mission.row.reward == def.reward && mission.row.target == def.target, "\(path) \(def.key): 보상 · 목표")
                #expect(mission.row.sort == def.sort, "\(path) \(def.key): 순서")
                #expect(mission.row.claimed == (mission.row.claimedAtMs != nil), "\(path) \(def.key): 받음 ↔ 받은 시각")
                #expect(mission.row.progress == (mission.row.achieved ? def.target : 0), "\(path) \(def.key): 진행")
                if let claimedAt = mission.row.claimedAtMs {
                    #expect(claimedAt >= Self.resetMs - 86_400_000 && claimedAt <= Self.nowMs,
                            "\(path) \(def.key): 받은 시각이 오늘(KST) 밖이다")
                }
            }
            // 묶음이 센 값 ↔ 줄에서 센 값(갈리면 머리의 '받을 보상 N개'와 줄이 다른 말을 한다).
            #expect(daily["claimable_count"] as? Int == section.claimableCount, "\(path): claimable_count")
            #expect(daily["claimable_ruby"] as? Int == section.claimableRuby, "\(path): claimable_ruby")
        }
    }

    @Test("★ 심사 데모에서 [받기] 가 선다 — 상태 셋이 한 화면에 · 다른 장면은 기준선이 갈린다")
    func theDemoAccountActuallyShowsAClaimButton() throws {
        /// 장면 · 바늘 → (받을 수, 받을 루비, 받은 줄 수)
        let table: [(path: String, claimable: Int, ruby: Int, claimed: Int)] = [
            ("me/_me/rpc.achievements_status.json", 2, 10, 1),
            ("me/_me/rpc.achievements_status@demo-progress.json", 0, 0, 0),
            ("me/_me/rpc.achievements_status@demo-all-claimed.json", 0, 0, 6),
            ("me/_me-/rpc.achievements_status.json", 0, 0, 0),
        ]
        for row in table {
            let status = try MeAchievementsFixtureContractTests.status(row.path)
            let section = MeDailyMissionSection.make(daily: status.daily, serverNowMs: status.serverNowMs)
            #expect(section.claimableCount == row.claimable && section.claimableRuby == row.ruby, "\(row.path): 받을 것")
            #expect(section.rows.filter { $0.row.claimed }.count == row.claimed, "\(row.path): 받은 줄 수")
        }
        // ★ 기본 장면에 **세 상태가 다 있다** — 심사원이 한 화면에서 [받기] 를 누를 수 있다(숨김 계정이면 achieved=false 라
        // 버튼이 안 서고, 그러면 이 기능을 아무도 못 본다 — 인수인계 §5-5).
        let demo = try MeAchievementsFixtureContractTests.status("me/_me/rpc.achievements_status.json")
        let section = MeDailyMissionSection.make(daily: demo.daily, serverNowMs: demo.serverNowMs)
        let states = section.rows.map(\.row.state)
        #expect(states.contains(.claimable) && states.contains(.claimed) && states.contains(.inProgress),
                "데모 기본 장면에 상태 셋이 다 있지 않다: \(states)")
        #expect(try Self.content(section, "daily_timing_bar").claimAmount == 5, "데모에서 [받기] 가 안 선다")
    }

    @Test("데모 받기 경로: p_key 로 픽스처가 갈리고 claimed_now · 잔량 · 남은 받을 것이 값으로 맞다 · 나 탭 장면 밖으로 안 샌다")
    func theDemoClaimRouteReachesTheDailyFixtures() throws {
        let plan = try #require(MobileDemoMissionsRoute(demoRoute: "me/missions"))
        /// 본문 → (픽스처, 지급한 키, 잔량, 받은 뒤 남은 받을 수)
        let table: [(body: String, path: String, claimed: [String], balance: Int, left: Int)] = [
            (#"{"p_key":"daily_timing_bar"}"#, "me/_me/rpc.daily_mission_claim@daily_timing_bar.json",
             ["daily_timing_bar"], 125, 1),
            (#"{"p_key":"daily_gomoku"}"#, "me/_me/rpc.daily_mission_claim@daily_gomoku.json",
             ["daily_gomoku"], 125, 1),
            (#"{"p_key":null}"#, "me/_me/rpc.daily_mission_claim.json",
             ["daily_timing_bar", "daily_gomoku"], 130, 0),
        ]
        var seen: Set<String> = []
        for row in table {
            let request = MeAchievementsFixtureContractTests.request(rpc: "daily_mission_claim", body: row.body)
            let entry = MeAchievementsFixtureContractTests.index.entry(for: plan.rewrite(request), scenario: plan.scene)
            #expect(entry?.relativePath == row.path, "\(row.body) → \(entry?.relativePath ?? "없음")")
            seen.insert(entry?.relativePath ?? "-")

            let status = try MeAchievementsFixtureContractTests.status(row.path)
            #expect(status.claimedNow.map(\.key) == row.claimed, "\(row.path): claimed_now \(status.claimedNow.map(\.key))")
            #expect(status.claimedNowRuby == row.claimed.count * 5, "\(row.path): 지급 루비 합")
            #expect(status.rubyBalance == row.balance, "\(row.path): 잔량(받기 전 120 + 지급)")
            let section = MeDailyMissionSection.make(daily: status.daily, serverNowMs: status.serverNowMs)
            #expect(section.claimableCount == row.left, "\(row.path): 받은 뒤 남은 받을 것")
            for claim in status.claimedNow {
                #expect(section.rows.first { $0.key == claim.key }?.row.claimed == true,
                        "\(row.path) \(claim.key): 지급했다면서 그 줄은 안 받았다 — [받기] 가 다시 서는 거짓 버튼")
                #expect(claim.reward == 5 && !claim.title.isEmpty, "\(row.path) \(claim.key): 지급 줄의 보상 · 제목")
            }
            // 누적 13줄은 일일 받기로 하나도 안 움직인다(받을 것 넷 75루비 그대로).
            #expect(status.claimableCount == 4 && status.claimableRuby == 75, "\(row.path): 일일 받기가 누적을 건드렸다")
        }
        #expect(seen.count == 3, "바늘이 버려져 \(seen.count) 가지 픽스처만 고른다: \(seen)")

        // 상태 조회에는 claimed_now 가 없다(상태가 '방금 받았다'를 말하면 안 된다).
        for path in MeAchievementsFixtureContractTests.missionPaths
        where !MeAchievementsFixtureContractTests.claimResponsePaths.contains(path) {
            #expect(try MeAchievementsFixtureContractTests.status(path).claimedNow.isEmpty, "\(path): claimed_now")
        }
        // 폰 금지 목록에 없다 · 나 탭 장면에서만 닿는다(다른 장면에서 잔량을 덮으면 그 스크린샷의 루비 알약이 바뀐다).
        let plain = MeAchievementsFixtureContractTests.request(rpc: "daily_mission_claim")
        #expect(MobileForbiddenCalls.violation(plain) == nil, "daily_mission_claim 이 금지 호출로 걸린다")
        #expect(MeAchievementsFixtureContractTests.index.entry(for: plain, scenario: "me") != nil, "장면 _me 에 없다")
        for scenario in ["games", "now", "messages", "me-shop", "me-settings"] {
            #expect(MeAchievementsFixtureContractTests.index.entry(for: plain, scenario: scenario) == nil,
                    "daily_mission_claim 픽스처가 장면 \(scenario) 에도 닿는다")
        }
        #expect(MeAchievementsFixtureContractTests.index.duplicateKeys.isEmpty,
                "\(MeAchievementsFixtureContractTests.index.duplicateKeys)")
    }

    // MARK: - §6 배선(소스 계약 — 뷰가 위 값을 정말로 읽는가)

    /// ★ 일일 미션 절은 **나 탭 루트에 있으면 안 된다.**
    ///
    /// 한때 주간 카드 위에 뒀다가 뺐다. 같은 날 사용자가 정반대를 지시했기 때문이다 —
    /// *"폰에서 나 탭에 미션들 쭈루룩 다 나열하니까 칸이 너무 길어져. 미션 창 버튼 두고 그거 누르면
    /// 미션 페이지 따로 있게 해줘."* 루트에 미션 블록을 하나 **더** 세우는 것은 그 지시를 더 나쁘게 만든다.
    /// 자리는 [미션] 화면 안이고 순서는 맥 0.3.64 와 같은 일일 → 주간 → 누적이다(두 기계가 같아야 한다).
    ///
    /// 이 시험이 재는 것은 "루트에 없다" **하나**다. [미션] 화면 안의 순서는 그 화면을 소유한 쪽이 잰다 —
    /// 여기서 같이 재면 두 파일의 시험이 한 자리를 두고 싸운다.
    @Test("자리: 일일 미션 절은 나 탭 **루트에 없다**(미션 화면 안이다) · 받기 햅틱은 여전히 루트 한 곳")
    func theDailySectionIsNotOnTheRootTab() throws {
        let home = try IntegrationContractTests.code(Self.tabPath)
        #expect(!home.contains("MeDailyMissionsSection(store: store)"),
                "일일 미션 절이 나 탭 루트에 다시 섰다 — 사용자가 빼라고 한 바로 그것이다")
        // 기준선: 루트에 남아야 하는 둘은 그대로 있고 순서도 그대로다(절을 빼면서 옆 것을 건드리지 않았는가).
        let stage = try #require(home.range(of: "MeStageCard(store: store)"))
        let weekly = try #require(home.range(of: "MeWeeklyWorkCard(store: store)"))
        #expect(stage.upperBound < weekly.lowerBound, "무대 → 이번 주 근무 순서가 깨졌다")
        // 햅틱이 두 곳이면 한 번 받고 두 번 운다 — 일일 절이 자기 것을 달지 않았는지 저장소 전체에서 센다.
        let haptic = try IntegrationContractTests.files(
            containing: [".sensoryFeedback(.success, trigger: store.missionClaimBurstSerial)"], under: "Sources/CheckMobileKit")
        #expect(haptic == [Self.tabPath], "받기 햅틱이 한 곳이 아니다: \(haptic)")
    }

    @Test("줄 · 절: 순수 값을 그리고 버튼 · 연출은 누적과 **같은 부품** · 제목 · 보상 숫자 · 💎 를 박지 않는다")
    func theViewDrawsThePureValuesAndReusesTheClaimParts() throws {
        let views = try IntegrationContractTests.code(Self.viewsPath)

        // 절: 스토어가 고른 갈래만 그린다(뷰가 따로 판정하면 줄과 배지가 다른 말을 한다).
        let section = try GamesChessSpectateTests.block(of: "struct MeDailyMissionsSection: View", in: views)
        #expect(section.contains("store.dailyMissionSection"), "절이 스토어 값을 안 읽는다")
        #expect(!section.contains("store.achievements?."), "절이 응답을 직접 뜯어 본다(판정은 한 곳이다)")
        #expect(section.contains("MeText.dailyMissionsTitle") && section.contains("MeText.dailyMissionsResetNote"),
                "소제목이나 '자정에 초기화 · 안 받으면 사라져요' 안내가 없다")
        #expect(section.contains("MeText.claimPendingHint(claimableCount)"), "머리가 '받을 보상 N개'를 말하지 않는다")

        // 줄: 그리는 값은 전부 순수 값에서 온다.
        let row = try GamesChessSpectateTests.block(of: "struct MeDailyMissionRow: View", in: views)
        #expect(row.contains("MeDailyMissionRowContent.make(mission: mission,"), "줄이 순수 값을 안 쓴다(맥 스위트가 못 재는 판단이 뷰로 샜다)")
        #expect(row.contains("Text(content.title)"), "줄 제목이 서버 글자가 아니다")
        #expect(row.contains("content.caption") && row.contains("content.progress") && row.contains("content.claimedMark"),
                "보조 문장 · 진행 숫자 · '받음'을 값에서 안 읽는다")
        #expect(row.contains("ProgressBar(content.fraction"), "진행 막대가 코어 fraction 을 안 그린다")
        #expect(row.contains("if let amount = content.claimAmount {"), "[받기] 가 받을 수 있는 줄에만 서지 않는다")
        #expect(row.contains("store.claimDailyMission(key: mission.key)"), "[받기] 가 그 줄의 키로 **일일** 받기를 부르지 않는다")
        #expect(row.contains("store.isClaimingDailyMission(mission.key)"), "떠 있는 받기를 그 줄이 모른다(두 번 눌린다)")
        #expect(row.contains("store.dailyMissionClaimDidFail(mission.key)"), "실패 판정을 스토어(일일 장부)에서 안 읽는다")
        #expect(row.contains("store.dailyClaimBurst(key: mission.key)") && row.contains(".id(burst.serial)"),
                "연출이 그 줄 자리에 서지 않거나 두 번째 받기에서 안 뜬다")

        // ★ 버튼 · 연출은 **새로 만들지 않는다**(만들면 한 번 받을 때 두 번 운다 — `MeAchievementViews.swift` 머리말의 사고).
        #expect(row.contains("MeClaimButton(amount: amount,") && row.contains("MeClaimBurstView(amount: burst.amount,"),
                "일일 줄이 누적과 같은 받기 부품을 안 쓴다")
        for declaration in ["struct MeClaimButton", "struct MeClaimBurstView"] {
            let owners = try IntegrationContractTests.files(containing: [declaration], under: "Sources/CheckMobileKit")
            #expect(owners == ["Sources/CheckMobileKit/Me/MeAchievementViews.swift"],
                    "\(declaration) 가 두 벌이다(받을 때 두 번 운다): \(owners)")
        }

        // 폰 규약 · 서버 값 규약: 💎 금지 · 미션 제목 · 보상 숫자를 화면 소스에 박지 않는다.
        #expect(!views.contains("💎") && !views.contains("diamond"), "진홍 마름모 · 이모지 루비(폰 규약 위반)")
        #expect(views.contains("RubyIcon("), "루비를 실제 보석으로 안 그린다")
        for word in ["한 판 하기", "한 판 두기", "타이밍 바", "플래피", "테트리스", "오목", "체스", "+5"] {
            #expect(!views.contains(word), "화면 소스에 서버 글자 '\(word)' 가 박혔다 — 서버가 미션을 바꾸면 화면이 거짓말한다")
        }
        // 실패는 그 줄 안에서 말한다(토스트 · 알림창 · 절 위 안내줄은 맥이 검토에서 버린 방식이다).
        for banned in [".alert(", ".confirmationDialog(", "InlineNotice(", "toast"] {
            #expect(!views.contains(banned), "받기 실패를 \(banned) 로 말한다(규약 위반)")
        }
    }

    // MARK: - 도우미

    nonisolated static let tabPath = "Sources/CheckMobileKit/Me/MeTab.swift"
    nonisolated static let viewsPath = "Sources/CheckMobileKit/Me/MeDailyMissionViews.swift"

    /// 일일 받기 픽스처 셋(상태 넷은 `MeAchievementsFixtureContractTests.missionPaths` 가 센다).
    nonisolated static let claimPaths = [
        "me/_me/rpc.daily_mission_claim.json",
        "me/_me/rpc.daily_mission_claim@daily_gomoku.json",
        "me/_me/rpc.daily_mission_claim@daily_timing_bar.json",
    ]
}
