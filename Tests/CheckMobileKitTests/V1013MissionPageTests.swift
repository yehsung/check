import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

// iOS 1.0.13 — 「미션」 화면 분리(레인 B 의 그물).
//
// 사용자 지시(2026-10-23): "폰에서 나 탭에 미션들 쭈루룩 다 나열하니까 칸이 너무 길어져. 미션 창 버튼 두고 그거 누르면
// 미션 페이지 따로 있게 해줘." 「이번 주 근무」 카드와 「도전 미션」 절(9줄 ≈ 672pt)이 루트에서 나가고 [미션] 줄 하나가
// 남았다. 둘을 **같이** 옮기는 것이 설계의 핵심이다 — 탭 막대 배지가 이미 둘을 합친 수(`missionClaimableCount`)라
// 하나만 남기면 배지 "1" 이 가리키는 곳이 루트와 미션 화면으로 갈린다.
//
// 이 스위트가 재는 것은 넷이다.
//
//  ① **배선**(소스 계약 — 주석은 걷어내고 본다). 화면은 전부 `#if os(iOS)` 안이라 맥 `swift test` 가 한 줄도 그리지
//     못한다(저장소 메모 '폰 뷰는 맥 스위트가 못 본다'). 재는 자리는 **그 선언 블록 안**이다
//     (`GamesChessSpectateTests.block` — 파일 어디든 한 번 나오면 초록인 단언은 커버리지 구멍이 된다).
//  ② **옮겨졌는가**(지웠는가가 아니라). 두 카드의 호출부가 저장소에서 **정확히 미션 화면 한 곳**이어야 한다 —
//     루트에 남아 있으면 길어짐이 안 고쳐지고, 둘 다 있으면 같은 카드가 두 곳에서 그려진다.
//  ③ **줄이 서는 조건 · 배지 · 새로고침은 값으로**. 스텁 서버로 실제 상태를 만들어 스토어 값과 나간 요청 수로 잰다
//     (부르는 자리가 있다를 재면 기본값이 틀려도 초록이다 — 저장소 메모 '테스트가 모양을 재고 결과를 안 잰다').
//  ④ **문구는 글자로**. 맥 레일 [미션]·폰 [미션] 줄이 같은 낱말을 쓰는지 맥 소스와 맞댄다.
//
// ⚠️ 햅틱 **한 곳**은 되돌아오기 쉬운 결함이다(한 번 받고 두 번 운다 — `MeAchievementViews.swift:30` 의 주석).
//    루트에서 걷고 미션 화면에 단 것을 저장소 전체 셈으로 못 박는다.

@MainActor
@Suite("폰 1.0.13 「미션」 화면")
struct V1013MissionPageTests {
    // MARK: - 도우미

    static let storePath = "Sources/CheckMobileKit/Me/MeStore.swift"
    static let tabPath = "Sources/CheckMobileKit/Me/MeTab.swift"
    static let pagePath = "Sources/CheckMobileKit/Me/MeMissionsView.swift"
    static let textPath = "Sources/CheckMobileKit/Me/MeText.swift"
    static let demoRoutePath = "Sources/CheckMobileKit/Demo/MobileDemoMissionsRoute.swift"
    /// 맥 [미션] 화면의 문구가 사는 자리(같은 낱말인지 맞댄다 — 폰 테스트가 맥 소스를 읽는 저장소 관례다).
    static let macPanelPath = "Sources/check/CheckMenuView.swift"

    static func code(_ path: String) throws -> String { try IntegrationContractTests.code(path) }

    /// [미션] 줄의 소스 — 버튼 껍데기(`MeMissionsRow`)와 내용(`MeMissionsRowContent`)을 **합쳐서** 본다.
    ///
    /// 줄은 메뉴 그룹(`MeMenuGroup` + `MeMenuRowContent`)의 관용구를 그대로 써서 **두 struct 로 갈려** 있다.
    /// 껍데기만 재면 내용을 다른 struct 로 옮기기만 해도 꺾쇠·보조 글자·큰 글자 분기 단언이 조용히 빠진다
    /// (통합 때 실제로 그렇게 빨개졌다 — 레인 B 프로브는 한 struct 였다). 줄의 계약은 **두 블록의 합**이다.
    static func rowSource() throws -> String {
        let page = try code(pagePath)
        let shell = try GamesChessSpectateTests.block(of: "struct MeMissionsRow", in: page)
        let content = try GamesChessSpectateTests.block(of: "struct MeMissionsRowContent", in: page)
        return shell + "\n" + content
    }

    /// 요청을 `METHOD 경로` 로 센 표(쿼리·본문은 세지 않는다 — 어느 덩어리가 다시 읽혔는지만 본다).
    func requestCounts(_ harness: RankMeHarness) -> [String: Int] {
        var counts: [String: Int] = [:]
        for request in harness.requests {
            counts["\(request.method.uppercased()) \(request.path)", default: 0] += 1
        }
        return counts
    }

    /// 주간 · 도전 미션 · 상점을 성공시키는 응답기(둘 중 하나를 nil 로 주면 그 함수는 **없는 서버**가 된다 — 기본 404 PGRST202).
    nonisolated static func responder(weekly: String?, achievements: String?) -> @Sendable (MobileStubRequest) -> MobileStubResponse? {
        { request in
            switch request.rpcName {
            case "weekly_work_status": return weekly.map { .json($0) }
            case "achievements_status": return achievements.map { .json($0) }
            case "shop_state": return .json(#"{"ruby_balance":1000,"characters":[]}"#)
            default: return nil
            }
        }
    }

    /// 받을 단계 둘(20h · 40h)이 있는 주간 응답. 루비 잔량은 싣지 않는다 — 미러에 쓰면 상점을 다시 읽는 갈래가 열려
    /// 요청 수 단언이 흔들린다.
    nonisolated static func weeklyWithTwoPending() -> String {
        MeAchievementClaimTests.weekly(worked: 45 * 3_600, achieved: [20, 40], ruby: nil)
    }

    /// 받을 도전 미션 셋이 있는 응답(계열 셋 — 접은 뒤에도 셋이다).
    nonisolated static func achievementsWithThreePending() -> String {
        MeAchievementClaimTests.status(achieved: ["todo3", "poke10", "team2"], ruby: nil)
    }

    // MARK: - ① 라우팅

    @Test("라우팅: `MeDestination.missions` 가 있고 나 탭이 그 갈래에서 미션 화면을 띄운다 · 줄은 그 자리로 push 한다")
    func routingReachesTheMissionsPage() throws {
        let store = try Self.code(Self.storePath)
        let destinations = try GamesChessSpectateTests.block(of: "package enum MeDestination", in: store)
        #expect(destinations.contains("case missions"),
                "MeDestination 에 missions 갈래가 없다 — [미션] 줄을 눌러도 쌓을 화면이 없다")

        // 열거에 더하고 `navigationDestination` 에 안 더하면 SwiftUI 가 빈 화면을 쌓는다(컴파일은 통과한다).
        let tab = try Self.code(Self.tabPath)
        let navigation = try GamesChessSpectateTests.block(of: "switch destination", in: tab)
        #expect(navigation.contains("case .missions: MeMissionsView(store: store)"),
                "나 탭이 .missions 갈래에서 미션 화면을 띄우지 않는다 — 줄을 누르면 빈 화면이 쌓인다")

        // 줄은 **나 탭 위에** 쌓는다(다른 탭에 쌓으면 누른 사람이 있는 화면이 안 바뀐다).
        let row = try Self.rowSource()
        #expect(row.contains("store.context.router.push(MeDestination.missions, on: .me)"),
                "[미션] 줄을 눌러도 미션 화면을 나 탭에 쌓지 않는다")
        #expect(row.contains("store.showsMissionsRow"),
                "줄이 설 조건을 스토어에서 묻지 않는다 — 둘 다 없는 서버에 빈 줄이 남는다")
        #expect(row.contains("\"chevron.right\""), "줄 오른쪽 꺾쇠가 없다 — 눌러서 들어가는 줄로 안 보인다")

        // 줄은 앵커 `missions` 를 그대로 물려받는다 — 저장소 밖 스크린샷 명령(`-AingCheckDemoMeAnchor missions`)이 안 깨진다.
        let home = try GamesChessSpectateTests.block(of: "struct MeHomeView", in: tab)
        #expect(home.range(of: #"MeMissionsRow\(store: store\)\s*\.id\(MeAnchor\.missions\)"#,
                           options: .regularExpression) != nil,
                "[미션] 줄에 .id(MeAnchor.missions) 가 안 붙었다 — 데모 스크린샷이 그 자리로 못 내려간다")
    }

    // MARK: - ② 옮겨졌다(지워진 것이 아니다)

    @Test("두 카드는 루트에서 **미션 화면으로 옮겨졌다**: 저장소에서 호출부가 그 화면 한 곳 · 각각 한 번씩")
    func bothCardsMovedExactlyOnce() throws {
        // 1.0.13 통합: 묶음은 **셋**이다(일일 미션이 같은 판에 생겼다 — 다른 세션 작업). 일일 절도 한때 나 탭
        // 루트의 주간 카드 위에 서 있었고, 그건 사용자가 고치라고 한 "쭈루룩 나열"을 하나 더 늘리는 일이었다.
        let sections = ["MeDailyMissionsSection(store: store)",
                        "MeWeeklyWorkCard(store: store)",
                        "MeAchievementsSection(store: store)"]
        for needle in sections {
            let users = try IntegrationContractTests.files(containing: [needle], under: "Sources/CheckMobileKit")
            #expect(users == [Self.pagePath],
                    "\(needle) 를 그리는 곳이 미션 화면 하나가 아니다: \(users) — 루트에 남았거나 두 곳에서 그린다")
        }

        // 순서: **일일 → 이번 주 → 누적**(맥 0.3.64 미션 화면과 같다 — 범위가 좁은 쪽부터 넓어진다).
        // 이 순서를 재는 자리는 **여기 하나**다(일일 쪽 시험은 "루트에 없다"만 잰다 — 한 자리를 두 파일이 재면 싸운다).
        let pageSource = try Self.code(Self.pagePath)
        let spots = try sections.map { try #require(pageSource.range(of: $0), "미션 화면에 \($0) 가 없다") }
        #expect(spots[0].lowerBound < spots[1].lowerBound && spots[1].lowerBound < spots[2].lowerBound,
                "미션 화면 순서가 일일 → 이번 주 → 누적이 아니다 — 맥과 다른 순서를 보게 된다")

        // 한 화면 안에서 두 번 그려도 위 단언은 초록이다(파일 목록은 같다) — 그래서 **셈**으로 다시 막는다.
        let page = pageSource
        for needle in sections {
            let count = page.components(separatedBy: needle).count - 1
            #expect(count == 1, "미션 화면이 \(needle) 를 \(count)번 그린다(한 번이어야 한다)")
        }

        // 화면은 두 카드의 상태 분기(불러오는 중 · 실패 · 숨김)를 **다시 쓰지 않는다** — 카드가 자기 안에서 다 그린다.
        #expect(!page.contains("store.achievementSection"),
                "미션 화면이 절의 네 갈래를 또 판정한다 — 카드와 화면이 다른 말을 한다")
        #expect(!page.contains("store.achievementsState") && !page.contains("store.weeklyWorkState"),
                "미션 화면이 불러오기 상태를 직접 뜯어 본다(그 분기는 카드 안이다)")

        // 화면 뼈대: 당겨서 새로 고치기는 **미션 둘만** · 제목은 미션 · 빈 화면 한 줄.
        let body = try GamesChessSpectateTests.block(of: "struct MeMissionsView", in: page)
        #expect(body.contains(".refreshable { await store.refreshMissions() }"),
                "미션 화면을 당기면 루트 전체를 다시 읽거나(머리·상점·기록) 아무것도 안 읽는다")
        #expect(body.contains(".navigationTitle(MeText.missionsPageTitle)"), "미션 화면에 제목이 없다")
        #expect(body.contains("store.missionsPageIsEmpty") && body.contains("MeText.missionsEmpty"),
                "들어온 뒤 서버가 둘 다 잃으면 화면이 아무 말도 안 한다")
        // 짧은 화면이라 하위 화면 스크롤 깃발은 쓰지 않는다(쓰면 데모가 엉뚱한 곳으로 내려간다).
        #expect(!page.contains("MeDemoHooks.scrollTarget()"), "짧은 미션 화면에 스크롤 깃발을 붙였다")
        // 파일 통째가 iOS 전용이다(맥 빌드에 들어가면 SwiftUI 폰 관용구가 깨진다).
        let lines = page.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        #expect(lines.first == "#if os(iOS)" && lines.last == "#endif",
                "\(Self.pagePath): 파일이 #if os(iOS) … #endif 로 감싸이지 않았다")
    }

    // MARK: - ③ 햅틱은 한 곳

    @Test("받기 햅틱은 **미션 화면 한 곳**이다 — 루트에 0회 · 미션 화면에 1회(두 곳이면 한 번 받고 두 번 운다)")
    func claimHapticLivesInExactlyOnePlace() throws {
        let needle = ".sensoryFeedback(.success, trigger: store.missionClaimBurstSerial)"
        let files = try IntegrationContractTests.files(containing: [needle], under: "Sources/CheckMobileKit")
        #expect(files == [Self.pagePath], "받기 햅틱이 미션 화면 한 곳이 아니다: \(files)")

        let tab = try Self.code(Self.tabPath)
        #expect(tab.components(separatedBy: "missionClaimBurstSerial").count - 1 == 0,
                "나 탭 루트가 아직 받기 순번을 읽는다 — 루트엔 [받기] 버튼이 하나도 없다(울 일이 없다)")
        let page = try Self.code(Self.pagePath)
        #expect(page.components(separatedBy: "missionClaimBurstSerial").count - 1 == 1,
                "미션 화면이 받기 순번을 \(page.components(separatedBy: "missionClaimBurstSerial").count - 1)번 읽는다(한 번이어야 한다)")
    }

    // MARK: - ④ 줄이 서는 조건(스텁 응답으로 실제 상태를 만들어 값으로)

    @Test("줄이 서는 조건: 주간만 · 도전 미션만 · 둘 다 있으면 선다 · **둘 다 없는 서버엔 안 선다**(그리고 화면은 비었다)")
    func theRowStandsWheneverEitherHalfExists() async throws {
        // (가) 주간만 있는 서버 — 도전 미션 함수가 없다(옛 서버).
        let weeklyOnly = await RankMeHarness(label: "v1013-row-weekly",
                                            responder: Self.responder(weekly: Self.weeklyWithTwoPending(), achievements: nil))
        defer { weeklyOnly.tearDown() }
        weeklyOnly.me.tabDidAppear()
        await weeklyOnly.quiesceMe()
        #expect(weeklyOnly.me.showsWeeklyWork && weeklyOnly.me.achievementSection == .hidden,
                "전제가 안 만들어졌다: 주간 \(weeklyOnly.me.showsWeeklyWork) · 절 \(weeklyOnly.me.achievementSection)")
        #expect(weeklyOnly.me.showsMissionsRow, "주간 보상만 있는 서버에서 [미션] 줄이 사라졌다 — 받을 70루비로 가는 문이 없다")
        #expect(!weeklyOnly.me.missionsPageIsEmpty, "그릴 카드가 있는데 미션 화면이 비었다고 말한다")

        // (나) 도전 미션만 있는 서버 — 주간 함수가 없다.
        let missionsOnly = await RankMeHarness(label: "v1013-row-missions",
                                              responder: Self.responder(weekly: nil, achievements: Self.achievementsWithThreePending()))
        defer { missionsOnly.tearDown() }
        missionsOnly.me.tabDidAppear()
        await missionsOnly.quiesceMe()
        #expect(!missionsOnly.me.showsWeeklyWork && missionsOnly.me.achievementRows.count == 9,
                "전제가 안 만들어졌다: 주간 \(missionsOnly.me.showsWeeklyWork) · 줄 \(missionsOnly.me.achievementRows.count)")
        #expect(missionsOnly.me.showsMissionsRow, "도전 미션만 있는 서버에서 [미션] 줄이 사라졌다")
        #expect(!missionsOnly.me.missionsPageIsEmpty)

        // (다) 둘 다 있는 서버.
        let both = await RankMeHarness(label: "v1013-row-both",
                                       responder: Self.responder(weekly: Self.weeklyWithTwoPending(),
                                                                 achievements: Self.achievementsWithThreePending()))
        defer { both.tearDown() }
        both.me.tabDidAppear()
        await both.quiesceMe()
        #expect(both.me.showsMissionsRow && !both.me.missionsPageIsEmpty)

        // (라) 둘 다 없는 서버(옛 서버 · db push 전) — 줄이 아예 없다. 1.0.12 까지 카드 둘이 통째로 빠지던 것과 같은 규약이라
        // **빈 줄만 남지 않는다**. 그래도 들어간 뒤 서버가 기능을 잃을 수 있어 화면은 할 말을 갖는다.
        let neither = await RankMeHarness(label: "v1013-row-neither",
                                         responder: Self.responder(weekly: nil, achievements: nil))
        defer { neither.tearDown() }
        neither.me.tabDidAppear()
        await neither.quiesceMe()
        #expect(!neither.me.showsWeeklyWork && neither.me.achievementSection == .hidden,
                "전제가 안 만들어졌다: 주간 \(neither.me.showsWeeklyWork) · 절 \(neither.me.achievementSection)")
        #expect(!neither.me.showsMissionsRow,
                "둘 다 없는 서버에 눌러도 아무것도 없는 [미션] 줄이 선다")
        #expect(neither.me.missionsPageIsEmpty, "미션 화면이 둘 다 못 그리는데 할 말이 없다")
    }

    // MARK: - ⑤ 줄의 배지 = 탭 막대 배지(반쪽 값이면 빨개진다)

    @Test("줄의 배지는 탭 막대와 **같은 수**(도전 미션 + 주간)다 — 반쪽 값(도전 미션만)을 쓰면 빨개진다")
    func theRowBadgeSaysTheSameNumberAsTheTabBar() async throws {
        let harness = await RankMeHarness(label: "v1013-badge",
                                         responder: Self.responder(weekly: Self.weeklyWithTwoPending(),
                                                                   achievements: Self.achievementsWithThreePending()))
        defer { harness.tearDown() }
        let store = harness.me
        store.tabDidAppear()
        await harness.quiesceMe()

        // 두 수가 **달라야** 이 테스트가 반쪽 값을 가른다(기준선이 같으면 영원히 초록이다 — 저장소 메모).
        #expect(store.achievementClaimableCount == 3 && store.weeklyWork?.pendingCount == 2,
                "재료: 도전 \(store.achievementClaimableCount) · 주간 \(String(describing: store.weeklyWork?.pendingCount))")
        #expect(store.missionClaimableCount == 5, "스토어가 센 받을 보상 수: \(store.missionClaimableCount)")
        #expect(harness.model.badges.badge(for: .me) == 5,
                "탭 막대 배지가 줄과 다른 수를 말한다: \(String(describing: harness.model.badges.badge(for: .me)))")
        // 줄이 그릴 글자 — 전체 수와 반쪽 수가 **다른 문장**이 되는 것이 이 단언의 쓸모다.
        #expect(MeText.claimPendingHint(store.missionClaimableCount) == "받을 보상 5개")
        #expect(MeText.claimPendingHint(store.achievementClaimableCount) == "받을 보상 3개")
        #expect(MeText.claimPendingHint(0) == nil, "받을 것이 없는데 배지 글자가 선다")
        harness.expectNoForbiddenCalls()

        // 줄 소스가 **그 전체 수**를 지나는가 — 반쪽 값(도전 미션만 · 주간 루비만)을 읽으면 빨개진다.
        let row = try Self.rowSource()
        #expect(row.contains("MeText.claimPendingHint(store.missionClaimableCount)"),
                "줄이 탭 막대 배지와 같은 수를 말하지 않는다 — 배지 \"5\" 를 보고 들어온 사람이 줄에서 다른 수를 본다")
        for half in ["achievementClaimableCount", "achievementClaimableRuby", "weeklyClaimableRuby", "showsWeeklyClaim"] {
            #expect(!row.contains(half), "[미션] 줄이 반쪽 값 store.\(half) 을 읽는다 — 배지와 줄의 수가 갈린다")
        }
        // 받을 것이 없을 때 그 자리에 서는 보조 글자.
        #expect(row.contains("MeText.missionsRowDetail"), "받을 것이 없을 때 줄에 보조 글자가 없다")
        // 큰 글자에서 버리는 것은 보조 글자다 — 배지는 버리지 않는다(메뉴 줄과 같은 관용구).
        #expect(row.contains("ViewThatFits"), "접근성 글자 크기에서 줄이 접히지 않는다")
    }

    // MARK: - ⑥ refreshMissions() 는 둘만 다시 읽는다

    @Test("미션 화면 당겨서 새로 고치기: `weekly_work_status` · `achievements_status` 가 **각각 한 번** · 머리·상점·기록은 0")
    func refreshMissionsReloadsOnlyTheTwoHalves() async throws {
        let harness = await RankMeHarness(label: "v1013-refresh",
                                          responder: Self.responder(weekly: Self.weeklyWithTwoPending(),
                                                                    achievements: Self.achievementsWithThreePending()))
        defer { harness.tearDown() }
        let store = harness.me
        store.tabDidAppear()
        await harness.quiesceMe()
        #expect(store.showsMissionsRow, "전제: 줄이 서는 서버다")

        let before = requestCounts(harness)
        await store.refreshMissions()
        await harness.quiesceMe()
        let after = requestCounts(harness)

        var grew: [String: Int] = [:]
        for (key, value) in after where value - (before[key] ?? 0) != 0 {
            grew[key] = value - (before[key] ?? 0)
        }
        let expected = ["POST \(SupabaseWorkService.weeklyWorkStatusPath)": 1,
                        "POST \(SupabaseWorkService.achievementsStatusPath)": 1]
        #expect(grew == expected,
                "미션 화면을 당겼을 때 늘어난 요청: \(grew) — 둘만 늘어야 한다(루트 새로고침이 아니다: 머리·상점·기록·AI 리밋은 이 화면에 없다)")
        harness.expectNoForbiddenCalls()

        // 로그아웃한 사람이 당기면 한 건도 안 나간다(스로틀이 아니라 **세션**으로 막는다).
        await harness.model.session.signOut()
        await harness.quiesceMe()
        let signedOut = requestCounts(harness)
        await store.refreshMissions()
        await harness.quiesceMe()
        let afterSignOut = requestCounts(harness)
        #expect(afterSignOut == signedOut,
                "로그아웃한 사람이 미션 화면을 당겼는데 요청이 나갔다: \(afterSignOut.filter { $0.value != (signedOut[$0.key] ?? 0) })")
    }

    // MARK: - ⑦ 데모 라우트

    @Test("데모 라우트: `me/missions…` · `me/weekly…` 는 미션 화면을 연다 · 남의 라우트는 안 연다 · 배선이 그 판정을 지난다")
    func demoRoutesOpenTheMissionsPage() throws {
        for route in ["me/missions", "me/missions/claimable", "me/missions/progress", "me/missions/claimed",
                      "me/missions/fresh", "me/weekly", "me/weekly/done", "me/weekly/legacy", "/me/missions"] {
            #expect(MobileDemoMissionsRoute.opensMissionsPage(route: route),
                    "데모 라우트 \(route) 가 미션 화면을 안 연다 — 저장소 밖 스크린샷 명령이 루트만 찍는다")
            // 장면 해석과 화면 열기가 **같은 글자 집합**을 봐야 한다(한쪽만 알면 라우트가 픽스처 없는 화면을 연다).
            #expect(MobileDemoMissionsRoute(demoRoute: route) != nil,
                    "같은 라우트를 장면 해석이 모른다: \(route)")
        }
        for route in ["me", "me/", "me/shop", "me/settings", "me/missionsfoo", "me/weeklyfoo", "now", "games"] {
            #expect(!MobileDemoMissionsRoute.opensMissionsPage(route: route),
                    "남의 데모 라우트 \(route) 가 미션 화면을 연다 — 엉뚱한 화면이 찍힌다")
        }

        // 여는 탭은 여전히 나 탭이다(그 위에 화면이 쌓인다) — 바꾸면 픽스처 장면이 `me-missions` 가 되어 전부 404 다.
        #expect(MobileDemoMissionsRoute.openRoute == "me")

        // 배선: 깃발(`-AingCheckDemoMeScreen missions`)과 라우트 글자 **둘 다** 그 화면으로 와야 한다.
        let initial = try GamesChessSpectateTests.block(of: "static func initialDestination",
                                                       in: try Self.code(Self.tabPath))
        #expect(initial.contains("case \"missions\": return .missions"),
                "깃발 `-AingCheckDemoMeScreen missions` 가 미션 화면을 안 연다")
        #expect(initial.contains("MobileDemoMissionsRoute.opensMissionsPage(route: route)"),
                "라우트만 넘긴 데모가 미션 화면을 안 연다 — 저장소 밖 스크린샷 명령은 깃발을 따로 주지 않는다")
        // 깃발이 먼저다(둘을 같이 주면 깃발이 이긴다 — 상점 시트 라우트와 같은 순서 규약).
        let flag = try #require(initial.range(of: "case \"missions\": return .missions"))
        let route = try #require(initial.range(of: "MobileDemoMissionsRoute.opensMissionsPage(route: route)"))
        #expect(flag.lowerBound < route.lowerBound, "라우트를 깃발보다 먼저 읽는다 — 깃발이 이겨야 한다")
    }

    // MARK: - ⑧ 문구

    @Test("문구: 제목 '미션'(맥 레일과 같은 낱말) · 보조 글자 '이번 주 근무 · 도전 미션' · 빈 화면 문장(맥과 같은 문장)")
    func theCopyIsPinned() throws {
        #expect(MeText.missionsPageTitle == "미션")
        #expect(MeText.missionsRowDetail == "일일 · 이번 주 · 누적 미션")
        #expect(MeText.missionsEmpty == "받을 수 있는 미션이 아직 없어요")
        // 보조 글자는 **그 화면에 있는 세 묶음**을 가리킨다 — 묶음 이름을 다듬으면 줄이 거짓말을 하게 된다.
        // 제목을 그대로 이어 붙이면 줄에 안 들어가 `ViewThatFits` 가 통째로 버리므로(그러면 아무 안내도 안 보인다)
        // 줄여 쓴다. 그래서 **세 제목의 머리 낱말이 다 있는지**로 잰다 — 1.0.13 의 「도전 미션」 → 「누적 미션」
        // 개명이 여기서 물렸다(옛 글자는 "도전"이었다).
        for head in [MeText.dailyMissionsTitle, MeText.weeklyTitle, MeText.missionsTitle].map({ String($0.prefix(2)) }) {
            #expect(MeText.missionsRowDetail.contains(head),
                    "[미션] 줄 보조 글자가 '\(head)' 묶음을 가리키지 않는다 — 묶음 이름이 바뀌었는데 줄이 안 따라왔다")
        }

        // 맥 [미션] 화면과 **같은 낱말**인가 — 레일 [미션]·폰 [미션] 줄이 같은 곳을 가리킨다는 약속이다.
        // (맥 타입은 이 테스트 타깃에서 import 할 수 없어 소스를 맞댄다 — 저장소 관례.)
        let macPanel = try GamesChessSpectateTests.block(of: "enum MissionPanelCopy",
                                                        in: try Self.code(Self.macPanelPath))
        #expect(macPanel.contains("let title = \"\(MeText.missionsPageTitle)\""),
                "맥 [미션] 화면 제목과 폰 미션 화면 제목이 다른 낱말이다")
        #expect(macPanel.contains("let emptyCaption = \"\(MeText.missionsEmpty)\""),
                "빈 미션 화면 문장이 맥과 다르다")

        // 문구는 `MeText` 한 곳에 산다 — 화면이 글자를 박으면 맥과 갈린다.
        let page = try Self.code(Self.pagePath)
        for literal in ["\"미션\"", "\"이번 주 근무 · 도전 미션\"", "\"받을 수 있는 미션이 아직 없어요\""] {
            #expect(!page.contains(literal), "미션 화면 소스에 문구 \(literal) 가 박혔다(MeText 를 지나야 한다)")
        }
        #expect(!page.contains("💎") && !page.contains("diamond"), "진홍 마름모·이모지 루비(폰 규약 위반)")

        // 미션 문구 셋은 `MeText` 의 미션 절 안이다(파일 어딘가가 아니라).
        let text = try Self.code(Self.textPath)
        for name in ["missionsPageTitle", "missionsRowDetail", "missionsEmpty"] {
            #expect(text.contains("package static let \(name) = "), "MeText.\(name) 이 없다")
        }
    }
}
