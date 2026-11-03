@testable import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

/// 우리 팀 전체 명단(지금 탭 [전체 보기] → push): 전원 · 맥과 같은 순서 · 주간 누적 · 이름 없는 팀원 · 차단 · 불러오기 상태 · 데모 라우트 · 부르는 자리.
@MainActor
@Suite(.serialized) struct NowTeamRosterTests {
    nonisolated static let now = MobileClock.demoInstant

    private func member(
        _ id: String, _ name: String, working: Bool = false, week: Int = 0, seenAgo: TimeInterval = 10, startedAgo: TimeInterval? = nil
    ) -> TeamMemberStatus {
        let seen = Self.now.addingTimeInterval(-seenAgo)
        return TeamMemberStatus(
            id: id,
            name: name,
            status: working ? .working : .offWork,
            updatedAt: seen,
            currentSessionStartedAt: working ? Self.now.addingTimeInterval(-(startedAgo ?? 3600)) : nil,
            weeklyDurationSeconds: week,
            lastSeenAt: seen
        )
    }

    private func roster(
        _ members: [TeamMemberStatus], directory: [PokeDirectoryRow] = [], hidden: Set<String> = [], me: String? = "me", goalHours: Int = 40
    ) -> NowTeamRoster {
        NowTeamRosterRules.build(
            members: members, directory: directory, hiddenPeerIDs: hidden, me: me, goalHours: goalHours,
            fetchedAt: Self.now, now: Self.now, presenceAt: Self.now
        )
    }

    private func directoryRow(_ id: String, status: String?, center: String? = "seoul") throws -> PokeDirectoryRow {
        let json: [String: Any?] = [
            "user_id": id, "display_name": "이름", "avatar_url": nil, "is_working": false, "message_capable": true,
            "center": center, "status_message": status,
        ]
        let data = try JSONSerialization.data(withJSONObject: json.mapValues { $0 ?? NSNull() })
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(PokeDirectoryRow.self, from: data)
    }

    // MARK: - 순수 규칙

    @Test("순서는 맥 sortedMembers 와 같다: 끊긴 사람도 근무 중 쪽 · 그 안은 숫자를 아는 이름순 · 나도 이름순 자리에 · 쉬는 사람까지 전원")
    func orderMatchesMac() {
        let result = roster([
            member("c", "하늘"),
            member("a", "팀10", working: true),
            member("me", "민트", working: true),
            member("b", "팀2", working: true, seenAgo: 600),
            member("d", "가을"),
        ])
        #expect(result.working.map(\.name) == ["민트", "팀2", "팀10"])
        #expect(result.resting.map(\.name) == ["가을", "하늘"])
        #expect(result.count == 5)
        #expect(result.working.first?.isMe == true, "나는 맨 위 고정이 아니라 이름순 자리다 — 맥과 같다")
        #expect(result.working[1].isStale && result.working[1].isWorking)
    }

    @Test("같은 이름은 id 로 고정 — 새로고침마다 두 줄이 자리를 바꾸지 않는다")
    func tieBreakIsStable() {
        let forward = roster([member("b", "민트"), member("a", "민트")])
        let backward = roster([member("a", "민트"), member("b", "민트")])
        #expect(forward.resting.map(\.id) == ["a", "b"])
        #expect(backward.resting.map(\.id) == ["a", "b"])
    }

    @Test("주간 누적: 쉬는 사람도 값이 있고 · 근무 중이면 진행 세션을 더하고 · 끊기면 마지막 신호에서 멈춘다")
    func weekSeconds() throws {
        let result = roster([
            member("off", "쉬는", week: 7_200),
            member("live", "도는", working: true, week: 7_200, startedAgo: 1_800),
            member("lost", "끊긴", working: true, week: 7_200, seenAgo: 600, startedAgo: 1_800),
        ])
        let off = try #require(result.resting.first)
        #expect(off.weekSeconds == 7_200 && off.elapsedSeconds == nil && !off.isStale)
        let live = try #require(result.working.first { $0.id == "live" })
        #expect(live.weekSeconds == 9_000 && live.elapsedSeconds == 1_800 && !live.isStale)
        let lost = try #require(result.working.first { $0.id == "lost" })
        #expect(lost.isStale && lost.weekSeconds == 7_200 + 1_200 && lost.elapsedSeconds == 1_200, "끊긴 세션이 숫자를 부풀리지 않는다")
        #expect(lost.lastSeenAt == Self.now.addingTimeInterval(-600))
    }

    @Test("지난주에 받은 값은 쉬는 사람 줄에서도 버린다(내 카드와 같은 경계)")
    func weekBoundary() throws {
        let fetchedLastWeek = Self.now.addingTimeInterval(-7 * 86_400)
        let result = NowTeamRosterRules.build(
            members: [member("off", "쉬는", week: 7_200)], directory: [], hiddenPeerIDs: [], me: nil, goalHours: 40,
            fetchedAt: fetchedLastWeek, now: Self.now, presenceAt: fetchedLastWeek
        )
        #expect(result.resting.first?.weekSeconds == 0)
    }

    @Test("목표: 진행 비율 · 달성 경계 · 목표 0 이어도 나누기가 터지지 않는다")
    func goal() {
        let result = roster([member("half", "반", week: 72_000), member("done", "끝", week: 144_000), member("short", "모", week: 143_999)])
        let rows = Dictionary(uniqueKeysWithValues: result.resting.map { ($0.id, $0) })
        #expect(rows["half"]?.goalProgress == 0.5 && rows["half"]?.isGoalMet == false)
        #expect(rows["done"]?.goalProgress == 1 && rows["done"]?.isGoalMet == true)
        #expect(rows["short"]?.isGoalMet == false, "내림 — 1초 모자라면 달성이 아니다")
        #expect(roster([member("x", "엑스", week: 3_600)], goalHours: 0).resting.first?.isGoalMet == true)
    }

    @Test("이름 없는 팀원: 빈 문자열 · 공백뿐이면 '팀원' — 이름순 자리도 그 글자로")
    func nameFallback() {
        #expect(NowTeamRosterRules.displayName("") == "팀원")
        #expect(NowTeamRosterRules.displayName("  \n") == "팀원")
        #expect(NowTeamRosterRules.displayName(" 민트 ") == "민트")
        let result = roster([member("x", ""), member("y", "하늘"), member("z", "가을")])
        #expect(result.resting.map(\.name) == ["가을", "팀원", "하늘"])
    }

    @Test("차단: 명단에 이름과 주간은 남고(확인 시트의 약속) · 그 사람이 쓴 상태메시지만 사라진다")
    func blockedKeepsNameDropsStatus() throws {
        #expect(BlockReportText.blockConfirmScopeNote.contains("팀 현황의 이름은 그대로"), "이 약속이 바뀌면 명단 규칙도 다시 봐라")
        let result = roster(
            [member("blocked", "자두", week: 3_600), member("other", "민트", week: 3_600)],
            directory: [try directoryRow("blocked", status: "차단한 사람의 문장"), try directoryRow("other", status: "다른 사람의 문장")],
            hidden: ["blocked"]
        )
        let blocked = try #require(result.resting.first { $0.id == "blocked" })
        #expect(blocked.name == "자두" && blocked.weekSeconds == 3_600)
        #expect(blocked.statusMessage == nil)
        #expect(!blocked.spokenSummary(now: Self.now).contains("차단한 사람의 문장"))
        #expect(result.resting.first { $0.id == "other" }?.statusMessage == "다른 사람의 문장")
    }

    @Test("사람 목록에 없는 팀원(서버가 서로 차단한 사람을 뺀다): 줄은 서고 센터·상태메시지가 없다")
    func missingFromDirectory() throws {
        let row = try #require(roster([member("x", "구슬", week: 60)]).resting.first)
        #expect(row.center == nil && row.statusMessage == nil && row.name == "구슬")
    }

    @Test("문구: 경과 0분이라 하지 않는다 · 주 표기 · 요약 · 보이스오버")
    func copy() throws {
        #expect(NowText.teamRosterElapsed(59) == "방금 시작했어요")
        #expect(NowText.teamRosterElapsed(12_000) == "지금 3시간 20분째")
        #expect(NowText.teamRosterWeek(89_280) == "주 24시간 48분")
        #expect(NowText.teamRosterSummary(teamName: "아잉 데모팀", goalHours: 40) == "아잉 데모팀 · 1인당 주 40시간")
        #expect(NowText.teamRosterSummary(teamName: nil, goalHours: 40) == "1인당 주 40시간")
        let result = roster([member("me", "민트", working: true, week: 3_600, startedAgo: 1_800), member("o", "자두", week: 0)])
        #expect(result.working.first?.spokenSummary(now: Self.now) == "민트, 나, 근무 중, 30분째, 이번 주 1시간 30분")
        #expect(result.resting.first?.spokenSummary(now: Self.now) == "자두, 쉬는 중, 이번 주 0분")
    }

    @Test("근무 중인데 시작 시각을 모르면 경과가 없다 — '방금 시작했어요'라고 지어내지 않는다")
    func workingWithoutStart() throws {
        let seen = Self.now.addingTimeInterval(-10)
        let unknown = TeamMemberStatus(id: "u", name: "모름", status: .working, updatedAt: seen, currentSessionStartedAt: nil, weeklyDurationSeconds: 7_200, lastSeenAt: seen)
        let row = try #require(roster([unknown]).working.first)
        #expect(row.elapsedSeconds == nil)
        #expect(row.weekSeconds == 7_200)
        #expect(row.spokenSummary(now: Self.now) == "모름, 근무 중, 이번 주 2시간 0분")
    }

    @Test("보이스오버는 화면과 같은 사실: 1분 미만은 '방금 시작했어요' · 끊긴 줄은 마지막 확인")
    func spokenMatchesScreen() throws {
        let fresh = try #require(roster([member("f", "새싹", working: true, startedAgo: 20)]).working.first)
        #expect(fresh.spokenSummary(now: Self.now) == "새싹, 근무 중, 방금 시작했어요, 이번 주 0분")
        let lost = try #require(roster([member("l", "끊긴", working: true, seenAgo: 600, startedAgo: 1_800)]).working.first)
        #expect(lost.spokenSummary(now: Self.now) == "끊긴, 연결 끊김 · 마지막 확인 10분 전, 이번 주 20분")
    }

    // MARK: - 스토어

    @Test("스토어: 쉬는 사람까지 전원 · 내 줄 주간 = 내 카드 주간 · 서버를 더 부르지 않는다")
    func storeReadsWhatItHas() async throws {
        let h = NowHarness()
        defer { h.tearDown() }
        await h.launch()
        await h.activate()
        let before = h.requests.count
        #expect(h.store.showsTeamRosterEntry)
        let result = try #require(h.store.teamRoster(now: Self.now))
        #expect(result.working.map(\.name) == ["나", "라임", "민트", "보리"])
        #expect(result.resting.map(\.name) == ["자두"])
        let mine = try #require(result.working.first { $0.isMe })
        let card = try #require(h.store.myCard(now: Self.now))
        #expect(mine.weekSeconds == card.weekSeconds, "같은 사람의 주간이 두 화면에서 달라지면 안 된다")
        #expect(mine.id == NowStubServer.me)
        #expect(result.working.first { $0.id == NowStubServer.mint }?.center == "seoul")
        #expect(result.working.first { $0.id == NowStubServer.bori }?.isStale == true)
        #expect(h.requests.count == before, "명단은 받아 둔 값만 읽는다")
        #expect(h.violations.isEmpty, "\(h.violations)")
    }

    @Test("스토어: 메시지 스토어가 방금 차단한 사람 — 옛 사람 목록을 쥔 창에도 상태메시지가 안 보인다")
    func storeHidesJustBlockedStatus() async throws {
        let h = NowHarness()
        defer { h.tearDown() }
        h.server.override("rpc.app_user_directory", .json(#"[{"user_id":"u-jadu","display_name":"자두","avatar_url":null,"is_working":false,"message_capable":true,"center":"seoul","status_message":"휴가 중"}]"#))
        await h.launch()
        await h.activate()
        #expect(h.store.teamRoster(now: Self.now)?.resting.first?.statusMessage == "휴가 중")
        let messages = try #require(h.store.context.links.messages)
        messages.hiddenBlockedPeerIDs.insert(NowStubServer.jadu)
        let row = try #require(h.store.teamRoster(now: Self.now)?.resting.first)
        #expect(row.name == "자두" && row.statusMessage == nil)
    }

    @Test("이름이 안 오는 행(profiles null): 명단에 '팀원'으로 선다")
    func storeNullProfile() async throws {
        let h = NowHarness()
        defer { h.tearDown() }
        h.server.override("work_statuses", .json(#"[{"user_id":"u-x","status":"off_work","updated_at":"2026-09-17T02:10:00Z","last_seen_at":"2026-09-17T02:10:00Z","profiles":null}]"#))
        await h.launch()
        await h.activate()
        #expect(h.store.teamRoster(now: Self.now)?.resting.map(\.name) == ["팀원"])
    }

    @Test("팀 없음: 입구도 명단도 없다")
    func storeNoTeam() async {
        let h = NowHarness()
        defer { h.tearDown() }
        h.server.override("memberships", .json("[]"))
        await h.launch()
        await h.activate()
        #expect(h.store.hasNoTeam)
        #expect(!h.store.showsTeamRosterEntry)
        #expect(h.store.teamRoster(now: Self.now) == nil)
    }

    @Test("로딩 → 실패: 받기 전엔 입구가 없고 teamLoadState 가 스피너에 머물지 않는다 · 받아 둔 뒤 실패하면 값을 두고 안내한다")
    func storeLoadStates() async throws {
        let h = NowHarness()
        defer { h.tearDown() }
        #expect(h.store.teamLoadState == .loading)
        #expect(!h.store.showsTeamRosterEntry)
        h.server.override("work_statuses", .networkFailure())
        await h.launch()
        await h.activate()
        #expect(h.store.teamLoadState == .failed)
        #expect(!h.store.showsTeamRosterEntry)
        #expect(h.store.teamRoster(now: Self.now) == nil)

        h.server.override("work_statuses", nil)
        await h.store.refreshNow()
        #expect(h.store.showsTeamRosterEntry)
        let count = try #require(h.store.teamRoster(now: Self.now)?.count)
        #expect(count == 5)

        h.server.override("work_statuses", .networkFailure())
        await h.store.refreshNow()
        #expect(h.store.notice == NowText.networkFailed)
        #expect(h.store.teamLoadState == .loaded)
        #expect(h.store.teamRoster(now: Self.now)?.count == count, "받아 둔 명단을 지우지 않는다")
    }

    @Test("로그아웃(세대 교체): 앞 계정의 명단이 남지 않는다")
    func storeResetClears() async {
        let h = NowHarness()
        defer { h.tearDown() }
        await h.launch()
        await h.activate()
        #expect(h.store.teamRoster(now: Self.now) != nil)
        h.store.reset()
        #expect(h.store.teamRoster(now: Self.now) == nil)
        #expect(!h.store.showsTeamRosterEntry)
    }

    @Test("[전체 보기]: 지금 탭 경로에 한 장만 쌓인다 · 두 번 눌러도 한 장 · 위젯 링크가 비운다 · 로그아웃이 비운다")
    func openPushesOnce() async {
        let h = NowHarness()
        defer { h.tearDown() }
        let router = h.store.context.router
        #expect(router.path(for: .now).isEmpty)
        h.store.openTeamRoster()
        h.store.openTeamRoster()
        #expect(router.path(for: .now).count == 1)
        #expect(router.path(for: .messages).isEmpty, "다른 탭 경로에 쌓이면 안 된다")
        router.open(.now)
        #expect(router.path(for: .now).isEmpty)
        h.store.openTeamRoster()
        #expect(router.path(for: .now).count == 1, "비운 뒤에는 다시 열린다")
        router.reset()
        #expect(router.path(for: .now).isEmpty, "다음 계정이 앞 계정의 명단 화면 위에서 시작하면 안 된다")
    }

    // MARK: - 데모 라우트 · 픽스처

    @Test("라우트 풀이: 꼬리마다 장면·바늘 · now/teamless 와 now 는 걸리지 않는다 · 여는 탭은 AingRoute 가 안다")
    func routeParsing() throws {
        #expect(MobileDemoTeamRosterRoute(demoRoute: "now") == nil)
        #expect(MobileDemoTeamRosterRoute(demoRoute: "now/teamless") == nil, "무소속 카드 장면을 가로채면 안 된다")
        let plain = try #require(MobileDemoTeamRosterRoute(demoRoute: " /now/Team/ "))
        #expect(plain.scene == "now" && plain.needle == "demo-team-roster" && plain.opensRoster && !plain.holdsTeamStatus)
        #expect(AingRoute(path: plain.openRoute) == .now)
        #expect(MobileDemoTeamRosterRoute(demoRoute: "now/team/empty")?.needle == "demo-team-empty")
        #expect(MobileDemoTeamRosterRoute(demoRoute: "now/team/failed")?.needle == "demo-team-failed")
        #expect(MobileDemoTeamRosterRoute(demoRoute: "now/team/loading")?.holdsTeamStatus == true)
        #expect(MobileDemoTeamRosterRoute(demoRoute: "now/team/noteam")?.scene == "now-teamless")
        let entry = try #require(MobileDemoTeamRosterRoute(demoRoute: "now/team/entry-off"))
        #expect(!entry.opensRoster, "첫 화면의 입구를 찍는 장면이다")
    }

    /// 이 라우트의 값으로 픽스처를 **실제 서비스에 태워** 받는다(바늘이 안 닿거나 칸이 안 맞으면 여기서 드러난다).
    private func fixtureStatuses(route raw: String) async throws -> [TeamMemberStatus] {
        let route = try #require(MobileDemoTeamRosterRoute(demoRoute: raw))
        let index = MobileDemoFixtures.load()
        let host = BaseStub.makeHost("roster")
        MobileStubURLProtocol.register(host: host) { request in
            index.response(for: route.rewrite(request), scenario: route.scene)
        }
        return try await BaseStub.makeService(host: host).fetchTeamStatuses(
            accessToken: "x", teamID: "d0000000-0000-4000-8000-000000007ea1", now: Self.now
        )
    }

    @Test("픽스처 now/team: 근무 넷(끊김 하나) · 쉬는 다섯(이름 없음 · 사람 목록 밖 · 목표 달성)")
    func fixtureRoster() async throws {
        let result = roster(try await fixtureStatuses(route: "now/team"), me: MobileDemo.userID)
        #expect(result.working.count == 4)
        #expect(result.working.filter(\.isStale).map(\.name) == ["보리"])
        #expect(result.working.filter(\.isMe).map(\.name) == ["새벽"])
        #expect(Set(result.resting.map(\.name)) == ["자두", "도토리", "팀원", "구슬", "별명이아주아주긴팀원"])
        #expect(result.resting.first { $0.name == "도토리" }?.isGoalMet == true)
        #expect(result.resting.first { $0.name == "팀원" }?.weekSeconds == 0)
        #expect(result.resting.first { $0.name == "구슬" }?.weekSeconds == 28_800)
    }

    @Test("픽스처 변형: 빈 명단 · 503 · 전원 쉼 · 기존 now 장면은 그대로 다섯 줄")
    func fixtureVariants() async throws {
        #expect(try await fixtureStatuses(route: "now/team/empty").isEmpty)
        await #expect(throws: (any Error).self) { _ = try await fixtureStatuses(route: "now/team/failed") }
        let off = try await fixtureStatuses(route: "now/team/entry-off")
        #expect(!off.isEmpty && off.allSatisfy { $0.status == .offWork })

        let index = MobileDemoFixtures.load()
        let request = MobileStubRequest(method: "GET", host: MobileDemo.host, path: "/rest/v1/work_statuses", query: "team_id=eq.x", headers: [:], bodyText: "")
        let entry = try #require(index.entry(for: request, scenario: "now"))
        #expect(entry.needle == nil, "앱스토어 스크린샷 장면 now 가 바늘 변형을 집으면 안 된다")
        let rows = try #require(try JSONSerialization.jsonObject(with: entry.data) as? [[String: Any]])
        #expect(rows.count == 5)
    }

    @Test("로딩 장면은 팀 상태 응답만 붙잡는다")
    func loadingHoldsOnlyStatus() throws {
        let route = try #require(MobileDemoTeamRosterRoute(demoRoute: "now/team/loading"))
        func request(_ path: String) -> MobileStubRequest {
            MobileStubRequest(method: "GET", host: MobileDemo.host, path: path, query: "", headers: [:], bodyText: "")
        }
        #expect(route.responseDelay(for: request("/rest/v1/work_statuses")) > 0)
        #expect(route.responseDelay(for: request("/rest/v1/memberships")) == 0)
        #expect(try #require(MobileDemoTeamRosterRoute(demoRoute: "now/team")).responseDelay(for: request("/rest/v1/work_statuses")) == 0)
    }

    // MARK: - 부르는 자리(폰 뷰는 맥 스위트가 컴파일하지 않는다 — 글자로 잰다)

    @Test("지금 탭이 명단을 실제로 연다: 목적지 등록 · 우리 팀 줄 · 근무 0명일 때 절 머리 · 팀 없으면 입구 없음")
    func tabOpensRoster() throws {
        let tab = try IntegrationContractTests.code("Sources/CheckMobileKit/Now/NowTab.swift")
        #expect(tab.contains(".navigationDestination(for: NowDestination.self)"))
        #expect(tab.contains("case .teamRoster: NowTeamRosterScreen(store: store)"))
        #expect(tab.contains("store.openTeamRoster()"))
        #expect(tab.contains("store.showsTeamRosterEntry"), "입구가 store 판정을 안 본다")
        #expect(tab.contains("onShowTeamRoster: teammates.isEmpty ? showRoster : nil"), "근무 중인 팀원이 없을 때 입구가 사라졌다")
        // 1.0.17: 그룹이 집중 집합도 받는다(`focused: focused` — 대표 답 #d_6A32rmcoJZZd). 이 단언이 재는 것(우리 팀 묶음에 [전체 보기])은 그대로다.
        #expect(tab.contains("label: NowText.ourTeam, people: teammates, focused: focused, anchorID: NowTab.workingSectionID, onShowRoster: showRoster"))
        #expect(tab.contains("onShowRoster: teammates.isEmpty ? nil : showRoster"), "다른 팀 묶음에 [전체 보기]가 붙으면 안 된다")
    }

    @Test("첫 화면 길이: 링크가 44pt 칸을 음수 여백으로 상쇄하고, 명단 줄을 첫 화면에 그리지 않는다")
    func tabStaysShort() throws {
        let tab = try IntegrationContractTests.code("Sources/CheckMobileKit/Now/NowTab.swift")
        let start = try #require(tab.range(of: "struct NowTeamRosterLink"))
        let link = tab[start.lowerBound...]
        #expect(link.contains(".frame(minHeight: 44)") && link.contains(".padding(.vertical, typeSize.isAccessibilitySize ? 0 : -14)"))
        #expect(!tab.contains("NowTeamRosterRowView"))
        #expect(!tab.contains("teamRoster(now:"))
    }

    @Test("명단 화면: 쓰는 일 · 말 거는 입구 · 주기 조회가 없다")
    func screenIsReadOnly() throws {
        let screen = try IntegrationContractTests.code("Sources/CheckMobileKit/Now/NowTeamRosterScreen.swift")
        #expect(screen.contains("store.teamRoster(now: now)"))
        #expect(screen.contains("store.hasNoTeam"))
        #expect(screen.contains("store.teamLoadState"))
        #expect(screen.contains("NowText.teamRosterEmpty"))
        #expect(screen.contains("NowText.teamRosterUnavailable"))
        #expect(!screen.contains(".message(peerID"), "차단한 사람에게 말 거는 길이 생긴다")
        #expect(!screen.contains("router.open"))
        #expect(!screen.contains(".task"), "화면이 조회를 더 띄우면 폴링이 는다")
        #expect(!screen.contains("Timer"))
        #expect(!screen.contains("context.service"))
        let model = try IntegrationContractTests.code("Sources/CheckMobileKit/Now/NowTeamRoster.swift")
        #expect(!model.contains("context.service"))
    }

    @Test("데모 라우트는 DEBUG 안에 있고 앱 모델·장면이 그 값을 쓴다(Release 금지 심볼 그물)")
    func demoWiring() throws {
        let raw = try String(contentsOf: IntegrationContractTests.root.appendingPathComponent("Sources/CheckMobileKit/Demo/MobileDemoTeamRosterRoute.swift"), encoding: .utf8)
        #expect(raw.hasPrefix("#if DEBUG"))
        let demo = try IntegrationContractTests.code("Sources/CheckMobileKit/Demo/MobileDemo.swift")
        #expect(demo.contains("teamRoster?.rewrite(raw)"))
        #expect(demo.contains("teamRoster?.scene"))
        #expect(demo.contains("teamRoster?.openRoute"))
        let stage = try IntegrationContractTests.code("Sources/CheckMobileKit/Now/NowDemoStage.swift")
        #expect(stage.contains("store.openTeamRoster()"))
    }

    @Test("데모 라우트가 앱 모델까지 닿는다: 지금 탭을 열고 · 바늘·장면이 스토어 값으로 나온다 · 금지 호출 0")
    func demoRouteReachesStore() async throws {
        try await baseWithDemoHost {
            for (route, working, resting) in [("now/team", 4, 5), ("now/team/empty", 0, 0), ("now/team/entry-off", 0, 5)] {
                let model = try await demoModel(route: route)
                #expect(model.router.lastOpenedRoute == .now, "\(route)")
                #expect(model.now.showsTeamRosterEntry, "\(route)")
                let result = try #require(model.now.teamRoster(now: MobileClock.demoInstant), "\(route)")
                #expect(result.working.count == working && result.resting.count == resting, "\(route): \(result.working.count) · \(result.resting.count)")
                #expect(MobileForbiddenCalls.violations(in: MobileStubURLProtocol.requests(host: MobileDemo.host)).isEmpty, "\(route)")
            }
            let failed = try await demoModel(route: "now/team/failed")
            #expect(failed.now.teamLoadState == .failed)
            #expect(!failed.now.showsTeamRosterEntry)
            let noTeam = try await demoModel(route: "now/team/noteam")
            #expect(noTeam.now.hasNoTeam)
            #expect(!noTeam.now.showsTeamRosterEntry)
            #expect(noTeam.now.teamRoster(now: MobileClock.demoInstant) == nil)
            BaseStub.tearDown(host: MobileDemo.host, storage: .temporary(name: "demo"))
        }
    }

    private func demoModel(route: String) async throws -> MobileAppModel {
        MobileStubURLProtocol.clearRequests(host: MobileDemo.host)
        let environment = try #require(MobileDemo.environment(arguments: ["app", "-AingCheckDemo", "YES", "-AingCheckDemoRoute", route]))
        let model = MobileAppModel(environment: environment)
        model.session.clientReleaseTimeoutSeconds = 0
        model.start()
        #expect(await baseWaitUntil { model.session.phase == .signedIn }, "\(route): \(model.session.phase)")
        model.now.appDidBecomeActive()
        #expect(await baseWaitUntil { model.now.teamLoadState != .loading }, "\(route)")
        return model
    }
}
