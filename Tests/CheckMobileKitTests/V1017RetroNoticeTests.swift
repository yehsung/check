import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

// MARK: - 지난주 회고 안내 줄 — 폰 1.0.17
//
// 기준 시각은 2026-09-17(목) KST, 지난주는 09-07(월) ~ 09-13(일). 스토어는 `#if os(iOS)` 밖이라 진짜 경로를 스텁 서버로 돈다.
// 뷰는 소스 계약으로만 잰다(줄이 실제로 그려지는 것은 맥 스위트가 못 본다).
@MainActor
@Suite(.serialized) struct V1017RetroNoticeTests {
    private nonisolated static let lastWeekSession =
        #"[{"id":"s1","user_id":"\#(RankMeFixture.userID)","started_at":"2026-09-08T01:00:00Z","ended_at":"2026-09-08T03:00:00Z","duration_seconds":7200}]"#
    /// 이번 주 근무뿐 — 지난주 회고가 없다.
    private nonisolated static let thisWeekOnly =
        #"[{"id":"s2","user_id":"\#(RankMeFixture.userID)","started_at":"2026-09-15T01:00:00Z","ended_at":"2026-09-15T03:00:00Z","duration_seconds":7200}]"#

    private nonisolated static func isRetroGET(_ request: MobileStubRequest) -> Bool {
        request.path == "/rest/v1/work_sessions" && request.method == "GET" && request.query.contains("limit=5000")
    }

    private static func harness(_ label: String, sessions: BaseLockedBox<MobileStubResponse>) async -> RankMeHarness {
        await RankMeHarness(label: label) { request in
            isRetroGET(request) ? sessions.get() : nil
        }
    }

    private static func checks(_ harness: RankMeHarness) -> Int {
        harness.requests.filter(isRetroGET).count
    }

    private static func settle(_ harness: RankMeHarness, checks expected: Int) async {
        #expect(await baseWaitUntil { checks(harness) >= expected && !harness.model.now.isCheckingRetroNotice })
    }

    @Test("지난주 근무가 있으면 선다 · 조회는 2주 창의 GET 하나 · 나 탭 조회를 덤으로 부르지 않는다")
    func showsOnce() async throws {
        let harness = await Self.harness("v1017-retro-show", sessions: BaseLockedBox(.json(Self.lastWeekSession)))
        defer { harness.tearDown() }
        let now = harness.model.now
        #expect(!now.showsRetroNotice)
        now.appDidBecomeActive()
        await Self.settle(harness, checks: 1)
        #expect(now.showsRetroNotice)
        let query = try #require(harness.requests.first(where: Self.isRetroGET))
        #expect(query.query.contains("user_id=eq.\(RankMeFixture.userID)"))
        #expect(query.query.contains("ended_at=gte.2026-08-30T15:00:00Z"), "조회 창 = 그 전주 월요일 00:00 KST: \(query.query)")
        #expect(harness.requests(rpc: "shop_state").isEmpty, "보이지 않는 나 탭이 서버를 두드렸다")
        #expect(harness.requests.filter { $0.path == "/rest/v1/token_usage_device_daily" }.isEmpty, "판정에 토큰 조회가 딸려 나갔다")
        harness.expectNoForbiddenCalls()
    }

    @Test("그려지면 소비: 앱을 떠나면 내려가고 · 이번 주에는 다시 안 묻고 안 뜬다 · 다음 주에 다시 뜬다")
    func displayedConsumesTheWeek() async {
        // 두 주에 걸쳐 근무한 사람(다음 주가 되면 09-15 근무가 '지난주'가 된다).
        let both = #"[\#(Self.thisWeekOnly.dropFirst().dropLast()),\#(Self.lastWeekSession.dropFirst().dropLast())]"#
        let harness = await Self.harness("v1017-retro-week", sessions: BaseLockedBox(.json(both)))
        defer { harness.tearDown() }
        let now = harness.model.now
        now.appDidBecomeActive()
        await Self.settle(harness, checks: 1)
        #expect(now.showsRetroNotice)
        now.markRetroNoticeDisplayed()
        #expect(now.showsRetroNotice, "소비했다고 보고 있는 줄을 걷었다")

        // 잠깐 비활성(알림 센터)으로 다시 active 가 와도 보고 있던 줄은 그대로다.
        now.appDidBecomeActive()
        #expect(now.showsRetroNotice)

        now.appDidEnterBackground()
        #expect(!now.showsRetroNotice, "앱을 떠났는데 줄이 남아 새 버전 줄을 가린다")
        now.appDidBecomeActive()
        await harness.barrier()
        #expect(!now.showsRetroNotice, "같은 주에 또 떴다")
        #expect(Self.checks(harness) == 1, "이번 주 몫을 썼는데 또 물었다")

        now.appDidEnterBackground()
        harness.clock.advance(7 * 86_400)
        now.appDidBecomeActive()
        await Self.settle(harness, checks: 2)
        #expect(now.showsRetroNotice, "다음 주인데 안 떴다")
    }

    @Test("그려지기 전에 떠나면 소비하지 않는다(이번 주 안내를 잃지 않는다)")
    func notDisplayedIsNotConsumed() async {
        let harness = await Self.harness("v1017-retro-undrawn", sessions: BaseLockedBox(.json(Self.lastWeekSession)))
        defer { harness.tearDown() }
        let now = harness.model.now
        now.appDidBecomeActive()
        await Self.settle(harness, checks: 1)
        now.appDidEnterBackground()
        now.appDidBecomeActive()
        await Self.settle(harness, checks: 2)
        #expect(now.showsRetroNotice, "안 그려진 줄의 이번 주 몫이 사라졌다")
    }

    @Test("X: 내려가고 이번 주에는 다시 안 뜬다")
    func dismiss() async {
        let harness = await Self.harness("v1017-retro-x", sessions: BaseLockedBox(.json(Self.lastWeekSession)))
        defer { harness.tearDown() }
        let now = harness.model.now
        now.appDidBecomeActive()
        await Self.settle(harness, checks: 1)
        now.dismissRetroNotice()
        #expect(!now.showsRetroNotice)
        now.appDidBecomeActive()
        await harness.barrier()
        #expect(!now.showsRetroNotice && Self.checks(harness) == 1)
    }

    @Test("[보기]: 나 탭으로 가고 · 쌓인 화면을 비우고 · 기록까지 내려갈 것을 적어 두고 · 줄은 소비된다")
    func openGoesToRecords() async {
        let harness = await Self.harness("v1017-retro-open", sessions: BaseLockedBox(.json(Self.lastWeekSession)))
        defer { harness.tearDown() }
        let now = harness.model.now
        let router = harness.model.context.router
        router.push(MeDestination.settings, on: .me)
        now.appDidBecomeActive()
        await Self.settle(harness, checks: 1)

        now.openRetroNotice()

        #expect(!now.showsRetroNotice)
        #expect(router.selectedTab == .me)
        #expect(router.path(for: .me).isEmpty, "하위 화면 위에 기록을 찾으라고 했다")
        #expect(harness.me.pendingRecordsScroll)
        #expect(harness.me.takeRecordsScroll())
        #expect(!harness.me.takeRecordsScroll(), "스크롤이 두 번 꺼내진다")
        now.appDidEnterBackground()
        now.appDidBecomeActive()
        await harness.barrier()
        #expect(!now.showsRetroNotice && Self.checks(harness) == 1)
    }

    @Test("지난주 근무가 없으면 안 뜨고 · 그 답을 적어 앞에 올 때마다 다시 묻지 않는다")
    func noRetro() async {
        let harness = await Self.harness("v1017-retro-none", sessions: BaseLockedBox(.json(Self.thisWeekOnly)))
        defer { harness.tearDown() }
        let now = harness.model.now
        now.appDidBecomeActive()
        await Self.settle(harness, checks: 1)
        #expect(!now.showsRetroNotice)
        now.appDidEnterBackground()
        now.appDidBecomeActive()
        await harness.barrier()
        #expect(Self.checks(harness) == 1, "회고가 없는 사람에게 앞에 올 때마다 물었다")
    }

    @Test("조회 실패는 소비하지 않는다 — 다음에 앞에 올 때 다시 묻고 선다")
    func failureRetries() async {
        let sessions = BaseLockedBox(MobileStubResponse.networkFailure())
        let harness = await Self.harness("v1017-retro-fail", sessions: sessions)
        defer { harness.tearDown() }
        let now = harness.model.now
        now.appDidBecomeActive()
        await Self.settle(harness, checks: 1)
        #expect(!now.showsRetroNotice)
        sessions.mutate { $0 = .json(Self.lastWeekSession) }
        now.appDidEnterBackground()
        now.appDidBecomeActive()
        await Self.settle(harness, checks: 2)
        #expect(now.showsRetroNotice, "실패 뒤 이번 주 안내를 잃었다")
    }

    @Test("나 탭이 보이면 소비: 떠 있던 줄이 내려가고 · 나 탭을 보는 중에 온 답은 줄을 안 세운다")
    func meTabConsumes() async {
        let harness = await Self.harness("v1017-retro-me", sessions: BaseLockedBox(.json(Self.lastWeekSession)))
        defer { harness.tearDown() }
        let now = harness.model.now
        now.appDidBecomeActive()
        await Self.settle(harness, checks: 1)
        #expect(now.showsRetroNotice)
        harness.me.tabDidAppear()
        #expect(!now.showsRetroNotice, "기록을 보는데 줄이 남았다")
        await harness.quiesceMe()

        let second = await Self.harness("v1017-retro-me2", sessions: BaseLockedBox(.json(Self.lastWeekSession)))
        defer { second.tearDown() }
        second.me.tabDidAppear()
        await second.quiesceMe()
        let before = Self.checks(second)
        second.model.now.appDidBecomeActive()
        await Self.settle(second, checks: before + 1)
        #expect(!second.model.now.showsRetroNotice, "나 탭을 보는 중인데 줄을 세웠다")
    }

    @Test("로그아웃: 줄이 내려가고 · 떠 있던 조회의 답은 다음 계정에 줄을 세우지 않는다")
    func resetDropsLateAnswer() async {
        let harness = await Self.harness("v1017-retro-reset", sessions: BaseLockedBox(.json(Self.lastWeekSession)))
        defer { harness.tearDown() }
        let now = harness.model.now
        let hold = BaseHold.install(host: harness.host, Self.isRetroGET)
        now.appDidBecomeActive()
        #expect(await hold.waitHeld())
        now.reset()
        #expect(await hold.releaseAndWaitDelivered())
        await harness.barrier()
        #expect(!now.showsRetroNotice, "앞 계정의 답이 줄을 세웠다")
    }

    @Test("봤음 키는 계정별이다")
    func keyIsPerAccount() async throws {
        let harness = await Self.harness("v1017-retro-key", sessions: BaseLockedBox(.json(Self.lastWeekSession)))
        defer { harness.tearDown() }
        let key = try #require(harness.model.now.retroNoticeWeekKey)
        #expect(key.hasSuffix(".\(RankMeFixture.userID)"))
        harness.storage.defaults.set(RetroWeekKey.current(harness.clock.now), forKey: key)
        harness.model.now.appDidBecomeActive()
        await harness.barrier()
        #expect(!harness.model.now.showsRetroNotice && Self.checks(harness) == 0, "소비한 주에 물었다")
    }

    @Test("문구: 맥 배너와 같은 문장")
    func copy() {
        #expect(NowText.retroNoticeTitle == "지난주 근무 기록이 준비됐어요")
        #expect(NowText.retroNoticeAction == "보기")
        #expect(NowText.retroNoticeDismiss == "지난주 근무 기록 안내 닫기")
    }

    @Test("화면 계약: 안내 줄은 한 번에 하나 · 그려질 때 소비 · [보기]·X 가 스토어로 간다 · 나 탭 루트가 스크롤을 꺼낸다")
    func viewContract() throws {
        let tab = try IntegrationContractTests.code("Sources/CheckMobileKit/Now/NowTab.swift")
        let retroBranch = try #require(tab.range(of: "if store.showsRetroNotice {"))
        let updateBranch = try #require(tab.range(of: "} else if store.showsUpdateNotice {"), "두 줄이 동시에 설 수 있다")
        let section = tab[retroBranch.upperBound..<updateBranch.lowerBound]
        #expect(section.contains("NowRetroNoticeRow(store: store)"))
        #expect(section.contains(".onAppear { store.markRetroNoticeDisplayed() }"), "그려질 때 소비하지 않는다")
        #expect(section.components(separatedBy: "Section {").count == 2, "회고 안내가 한 줄을 넘는다")
        let row = try #require(tab.range(of: "private struct NowRetroNoticeRow: View {"))
        let body = tab[row.upperBound...]
        #expect(body.contains("store.openRetroNotice()"))
        #expect(body.contains("store.dismissRetroNotice()"))
        #expect(body.contains(".accessibilityLabel(Text(NowText.retroNoticeDismiss))"))
        let me = try IntegrationContractTests.code("Sources/CheckMobileKit/Me/MeTab.swift")
        #expect(me.contains("store.takeRecordsScroll()"), "나 탭이 스크롤을 안 꺼낸다")
        #expect(me.contains(".onChange(of: store.pendingRecordsScroll)"), "이미 그려진 나 탭이 스크롤 요청을 못 본다")
        #expect(me.contains("proxy.scrollTo(MeAnchor.records, anchor: .top)"))
    }
}
