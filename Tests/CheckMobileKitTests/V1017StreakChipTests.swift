import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

// MARK: - 연속 근무 칩 '연속 N일 근무!' — 폰 1.0.17
//
// 값은 `achievements_status` 응답의 새 최상위 키 `streak_days`(서버 초안 — 저장소 밖, 적용 전). 키가 있을 때만 칩을 그려서 서버와 폰의 출시 순서가 자유롭다.
// 미션 줄의 `progress` 로 대신하면 안 된다: target 에서 잘리고 달성 뒤 target 에 고정이라 30일을 넘긴 사람은 2일째여도 30 이다.
@MainActor
@Suite(.serialized) struct V1017StreakChipTests {
    private nonisolated static func withStreak(_ value: String, achieved: Set<String> = [], claimed: Set<String> = []) -> String {
        let body = MeAchievementClaimTests.status(achieved: achieved, claimed: claimed)
        return String(body.dropLast()) + #","streak_days":\#(value)}"#
    }

    private static func decode(_ json: String) throws -> AchievementStatus {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(AchievementStatus.self, from: Data(json.utf8))
    }

    @Test("디코드: 있으면 값 · 없거나 null 이거나 모양이 틀리면 nil · 그래도 나머지 응답은 산다")
    func decoding() throws {
        #expect(try Self.decode(Self.withStreak("3")).streakDays == 3)
        #expect(try Self.decode(Self.withStreak("0")).streakDays == 0, "0일은 값이다(칩을 그린다)")
        let missing = try Self.decode(MeAchievementClaimTests.status())
        #expect(missing.streakDays == nil, "키가 없는 서버에서 값을 지어냈다")
        #expect(!missing.missions.isEmpty)
        #expect(try Self.decode(Self.withStreak("null")).streakDays == nil)
        let garbage = try Self.decode(Self.withStreak(#"{"a":1}"#))
        #expect(garbage.streakDays == nil)
        #expect(!garbage.missions.isEmpty, "칸 하나 때문에 응답을 잃었다")
    }

    @Test("잘린 progress 와 무관하다: 30일을 넘긴 사람의 지금 2일은 2 다")
    func notFromCappedProgress() throws {
        let status = try Self.decode(Self.withStreak("2", claimed: ["streak14", "streak30"]))
        #expect(status.missions.first { $0.key == "streak30" }?.progress == 30, "대조: 줄의 값은 target 고정이다")
        #expect(status.streakDays == 2)
    }

    @Test("합치기: 새 응답의 값을 따른다 · 받은 줄 되돌림 방지와 무관 · 새 응답에 키가 없으면 숨는다")
    func merging() throws {
        let previous = try Self.decode(Self.withStreak("5", claimed: ["team2"]))
        #expect(try Self.decode(Self.withStreak("6")).merged(over: previous).streakDays == 6)
        #expect(try Self.decode(MeAchievementClaimTests.status()).merged(over: previous).streakDays == nil, "옛 값을 붙들고 있다")
    }

    @Test("문구: 맥과 같은 문장 · 0일도 말한다 · 음수는 0 · 보이스오버는 느낌표 없이")
    func copy() {
        #expect(HeaderStreakCopy.text(3) == "연속 3일 근무!")
        #expect(HeaderStreakCopy.text(0) == "연속 0일 근무!")
        #expect(HeaderStreakCopy.text(-2) == "연속 0일 근무!")
        #expect(HeaderStreakCopy.accessibilityLabel(3) == "연속 3일 근무")
        #expect(HeaderStreakCopy.icon == "flame.fill")
    }

    @Test("배선: 나 탭 미션 조회 값이 탭과 무관하게 지금 탭까지 온다 · 받기 응답도 갱신 · 추가 호출 없음 · 금지 호출 0")
    func wiring() async {
        let harness = await RankMeHarness(label: "v1017-streak", responder: MeAchievementClaimTests.quietResponder)
        defer { harness.tearDown() }
        let now = harness.model.now
        #expect(now.myStreakDays == nil, "받기 전에 값을 그렸다")

        harness.enqueue("achievements_status", .json(Self.withStreak("4", achieved: ["team2"])))
        harness.me.appDidBecomeActive()
        await harness.quiesceMe()
        #expect(!harness.me.isTabVisible)
        #expect(now.myStreakDays == 4, "나 탭을 안 열면 칩이 안 선다")
        #expect(harness.requests(rpc: "achievements_status").count == 1, "칩 때문에 조회가 늘었다")

        harness.enqueue("achievement_claim", .json(Self.withStreak("5", claimed: ["team2"])))
        harness.me.claimAchievement(key: "team2")
        await harness.quiesceMe()
        #expect(now.myStreakDays == 5)
        harness.expectNoForbiddenCalls()
    }

    @Test("키가 없는 서버(초안 적용 전): 칩이 없고 미션은 그대로다")
    func oldServerHides() async {
        let harness = await RankMeHarness(label: "v1017-streak-old", responder: MeAchievementClaimTests.quietResponder)
        defer { harness.tearDown() }
        harness.enqueue("achievements_status", .json(MeAchievementClaimTests.status(claimed: ["streak14", "streak30"])))
        await harness.me.loadAchievements()
        #expect(harness.me.achievements != nil)
        #expect(harness.model.now.myStreakDays == nil, "키가 없는데 값을 지어냈다(잘린 progress 를 읽었나)")
        #expect(!harness.me.achievementRows.isEmpty)
    }

    @Test("함수 없는 서버 · 로그아웃: 칩이 내려간다")
    func goneServerAndResetHide() async {
        let harness = await RankMeHarness(label: "v1017-streak-gone", responder: MeAchievementClaimTests.quietResponder)
        defer { harness.tearDown() }
        harness.enqueue("achievements_status", .json(Self.withStreak("4")))
        await harness.me.loadAchievements()
        #expect(harness.me.streakDays == 4)
        harness.me.reset()
        #expect(harness.me.streakDays == nil, "앞 계정의 연속 일수가 남았다")

        harness.enqueue("achievements_status", .json(Self.withStreak("4")))
        await harness.me.loadAchievements()
        harness.enqueue("achievements_status", .missingFunction("achievements_status"))
        await harness.me.loadAchievements()
        #expect(harness.me.streakDays == nil, "이 서버엔 기능이 없는데 칩이 남았다")
    }

    @Test("데모 장면 streak: 지금 탭이 읽는 값이 선다 · 떠 있는 조회가 끝난 뒤에 넣어 404 가 지우지 못한다")
    func demoStage() async {
        #expect(NowDemoStage.stages(arguments: ["app", NowDemoStage.argument, "streak"]) == ["streak"])
        let harness = await RankMeHarness(label: "v1017-streak-demo", responder: MeAchievementClaimTests.quietResponder)
        defer { harness.tearDown() }
        let now = harness.model.now
        await NowDemoStage.applyStreak(store: now, stages: [])
        #expect(now.myStreakDays == nil)

        let hold = BaseHold.install(host: harness.host) { $0.path == "/rest/v1/rpc/achievements_status" }
        harness.enqueue("achievements_status", .missingFunction("achievements_status"))
        harness.me.refreshAchievementsIfStale()
        #expect(await hold.waitHeld())
        let stage = Task { await NowDemoStage.applyStreak(store: now, stages: ["streak"]) }
        #expect(await hold.releaseAndWaitDelivered())
        await harness.quiesceMe()
        await stage.value
        #expect(now.myStreakDays == NowDemoStage.demoStreakDays, "조회가 칩 값을 지웠다")
        #expect(HeaderStreakCopy.text(NowDemoStage.demoStreakDays) == "연속 12일 근무!")
    }

    @Test("화면 계약: 큰 타이머 줄에 선다(새 줄 · 새 절 없음) · nil 이면 없다 · 시계를 안 읽는다 · 줄 progress 를 안 읽는다")
    func viewContract() throws {
        let tab = try IntegrationContractTests.code("Sources/CheckMobileKit/Now/NowTab.swift")
        #expect(tab.contains("streakDays: store.myStreakDays"), "지금 탭이 값을 안 넘긴다")
        let line = try #require(tab.range(of: "private var timerLine: some View {"))
        let end = try #require(tab.range(of: "private var timer: some View {", range: line.upperBound..<tab.endIndex))
        let body = tab[line.upperBound..<end.lowerBound]
        #expect(body.contains("if let streakDays {"), "nil 에도 칩을 그린다")
        let row = try #require(body.range(of: "HStack(alignment: .center, spacing: 8)"))
        let fallback = try #require(body.range(of: "VStack(alignment: .leading, spacing: 6)"))
        #expect(row.lowerBound < fallback.lowerBound, "한 줄이 먼저여야 카드가 안 늘어난다")
        let chip = try #require(tab.range(of: "private struct NowStreakChip: View {"))
        let chipEnd = try #require(tab.range(of: "struct ", range: chip.upperBound..<tab.endIndex))
        let chipBody = tab[chip.upperBound..<chipEnd.lowerBound]
        #expect(chipBody.contains("Text(HeaderStreakCopy.text(days))"))
        #expect(chipBody.contains(".accessibilityLabel(Text(HeaderStreakCopy.accessibilityLabel(days)))"))
        #expect(chipBody.contains("Image(systemName: HeaderStreakCopy.icon)"))
        #expect(!chipBody.contains("clock"), "칩이 시계를 읽는다")
        let store = try IntegrationContractTests.code("Sources/CheckMobileKit/Me/MeStoreAchievements.swift")
        #expect(store.contains("achievements?.streakDays"))
        #expect(!tab.contains("streak30") && !tab.contains("streak14"), "미션 줄 값으로 연속 일수를 만들었다")
    }
}
