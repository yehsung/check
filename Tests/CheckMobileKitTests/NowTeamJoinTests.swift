@testable import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

/// 무소속 계정이 **폰만으로** 팀에 들어가는 길(w16 검증 high). 팀 합류·만들기가 가입 화면에만 있어, 로그인 화면의
/// "이메일 확인 필요" 출구로 들어온 사람 · 가입 도중 앱을 껐던 사람 · 맥에서 가입만 해 둔 사람은 무소속으로 떨어진 채
/// 맥 없이는 영영 팀에 못 들어갔다.
///
/// 규칙은 가입 화면과 한 벌(`MobileTeamJoinForm`)이다 — 여기서 재는 것은 **지금 탭이 그 결과로 무엇이 되는가**다.
@MainActor
@Suite(.serialized) struct NowTeamJoinTests {
    nonisolated static let now = MobileClock.demoInstant
    nonisolated static let previewRow = #"[{"team_id":"team-now","name":"지금팀","weekly_goal_hours":40,"member_count":3}]"#
    nonisolated static let joinRow = #"[{"team_id":"team-now","name":"지금팀","weekly_goal_hours":40}]"#
    nonisolated static let createRow = #"[{"team_id":"team-new","name":"새벽 러너스","invite_code":"X7K2M9Q4","weekly_goal_hours":50}]"#
    nonisolated static let createdMembership = #"[{"team_id":"team-new","role":"owner","teams":{"name":"새벽 러너스","weekly_goal_hours":50}}]"#

    /// 무소속으로 선 지금 탭 + 가입 넷(미리보기 · 합류 · 생성).
    private func teamlessHarness(
        lookup: MobileStubResponse? = nil,
        join: MobileStubResponse? = nil,
        create: MobileStubResponse? = nil
    ) async -> NowHarness {
        let h = NowHarness()
        h.server.override("memberships", .json("[]"))
        h.server.override("rpc.lookup_team_by_code", lookup ?? .json(Self.previewRow))
        h.server.override("rpc.join_team", join ?? .json(Self.joinRow))
        h.server.override("rpc.create_team", create ?? .json(Self.createRow))
        await h.launch()
        await h.activate()
        return h
    }

    // MARK: - 문구

    @Test("무소속 안내가 맥 앱으로 떠넘기지 않는다(폰만 가진 앱스토어 사용자의 막다른 길)")
    func teamlessCopyOffersAPathOnThePhone() {
        #expect(!NowText.noTeamBody.contains("맥 앱에서"), "무소속 카드가 아직 맥 앱에 가라고 한다 — 맥이 없는 사람은 앱을 못 쓴다")
    }

    // MARK: - 합류

    @Test("무소속 카드에서 팀 코드로 합류하면 **재로그인 없이** 지금 탭이 팀 화면이 된다")
    func joinFromTeamlessCardShowsTeamScreen() async throws {
        let h = await teamlessHarness()
        defer { h.tearDown() }
        #expect(h.store.hasNoTeam, "대조: 무소속으로 서지 않았다")
        #expect(h.store.myCard(now: Self.now) == nil)

        let join = h.store.teamJoin
        #expect(!join.canSubmit, "코드를 확인하기 전엔 채운 버튼이 비활성이어야 한다")
        #expect(join.primaryTitle == MobileSignUpText.join)

        join.form.teamCode = "aing-team"
        await join.form.previewTeamCode().value
        let preview = try #require(join.form.joinPreview)
        #expect(preview.name == "지금팀" && preview.memberCount == 3)
        #expect(join.previewLine?.text == MobileSignUpText.previewLine(preview))
        #expect(join.previewLine?.isSuccess == true)
        #expect(join.canSubmit)

        // 합류 뒤 소속은 **서버에서 다시 읽는다**(역할을 지어내지 않는다 — 맥 confirmMembership 과 같은 규칙).
        h.server.override("memberships", nil)
        let task = try #require(join.submit())
        #expect(join.isSubmitting)
        await task.value
        #expect(!h.store.hasNoTeam, "합류했는데 무소속 카드가 그대로 남았다")
        #expect(h.store.isSettlingTeam && h.store.teamLoadState == .loading, "소속을 읽는 동안은 스피너다")
        await h.settle()

        #expect(h.store.membership == NowMembership(teamID: NowStubServer.teamID, teamName: "지금팀", goalHours: 40, role: "member"))
        #expect(!h.store.isSettlingTeam && h.store.teamLoadState == .loaded)
        #expect(h.store.myCard(now: Self.now) != nil, "팀 화면(내 상태 카드)이 서지 않았다")
        #expect(h.store.workingPeople(now: Self.now).contains { $0.isTeammate }, "우리 팀이 보이지 않는다")
        #expect(h.model.session.phase == .signedIn, "재로그인을 요구했다")
        #expect(await baseWaitUntil { h.model.session.profile?.teamName == "지금팀" }, "다른 탭이 읽는 팀 이름이 안 채워졌다")

        let joins = h.requests("rpc.join_team")
        #expect(joins.count == 1)
        #expect(joins.first?.bodyText.contains(#""code":"AINGTEAM""#) == true, "합류 본문에 정규화된 코드")
        #expect(join.notice == nil)
        #expect(h.violations.isEmpty, "\(h.violations)")
    }

    @Test("join_team 0행(코드는 맞는데): '다른 센터 팀' 문구가 그대로 서고, 같은 코드 재제출은 왕복 없이 막힌다")
    func joinZeroRowsKeepsCenterGateMessage() async throws {
        let h = await teamlessHarness(join: .json("[]"))
        defer { h.tearDown() }
        let join = h.store.teamJoin
        join.form.teamCode = "AINGTEAM"
        await join.form.previewTeamCode().value
        #expect(join.previewLine?.isSuccess == true)
        await join.submit()?.value

        #expect(h.store.hasNoTeam && !h.store.isSettlingTeam, "0행인데 팀 화면으로 넘어갔다")
        let line = try #require(join.previewLine, "코드 칸 아래 줄이 비었다")
        #expect(line.text == MobileSignUpText.teamlessJoinBlocked, "화면 줄이 '\(line.text)' — 다른 센터 안내가 아니다")
        #expect(!line.isSuccess, "다른 센터 안내가 안내색(성공)으로 그려진다")
        #expect(join.form.joinPreview == nil, "서버가 부정한 미리보기는 더 이상 '합류 가능' 이 아니다")
        #expect(join.notice == nil)
        #expect(!join.canSubmit)

        // 같은 코드로 또 눌러도 헛왕복(같은 0행)을 돌지 않고 가드가 이유를 말한다.
        #expect(join.submit() == nil)
        #expect(join.notice == MobileSignUpText.codeUnverified)
        await h.barrier()
        #expect(h.requests("rpc.join_team").count == 1, "같은 코드로 join_team 이 또 나갔다")
        #expect(join.previewLine?.text == MobileSignUpText.teamlessJoinBlocked, "가드 문구가 센터 안내를 덮었다")
    }

    @Test("팀 만들기: 이름 공백은 왕복 없이 막고, 이름·주간 목표로 create_team 한 번 → 팀 화면(join_team 은 부르지 않는다)")
    func createTeamFromTeamlessCard() async throws {
        let h = await teamlessHarness()
        defer { h.tearDown() }
        let join = h.store.teamJoin
        join.toggleCreateTeamMode()
        #expect(join.form.isCreateTeamMode)
        #expect(join.primaryTitle == MobileSignUpText.switchToCreate)
        #expect(join.form.createTeamGoalHours == MobileTeamJoinForm.defaultGoalHours)

        join.form.createTeamName = "   "
        #expect(join.submit() == nil)
        #expect(join.notice == MobileSignUpText.teamNameRequired)
        await h.barrier()
        #expect(h.requests("rpc.create_team").isEmpty)

        join.form.createTeamName = " 새벽 러너스 "
        join.form.createTeamGoalHours = 50
        h.server.override("memberships", .json(Self.createdMembership))
        await join.submit()?.value
        #expect(!h.store.hasNoTeam)
        await h.settle()

        #expect(h.store.membership == NowMembership(teamID: "team-new", teamName: "새벽 러너스", goalHours: 50, role: "owner"))
        #expect(h.store.goalHours == 50)
        let body = try #require(h.requests("rpc.create_team").first?.bodyText)
        #expect(body.contains(#""team_name":"새벽 러너스""#), "팀 이름은 앞뒤 공백을 떼고 보낸다")
        #expect(body.contains(#""goal_hours":50"#))
        #expect(h.requests("rpc.join_team").isEmpty)
        #expect(h.requests("rpc.create_team").count == 1)
        #expect(h.violations.isEmpty, "\(h.violations)")
    }

    // MARK: - 늦은 응답 · 세대 가드 · 중복 탭

    @Test("합류 전에 떠난 소속 조회가 '소속 없음'을 싣고 늦게 와도 무소속 카드로 되돌리지 않는다")
    func staleMembershipDoesNotRevertJoinedTeam() async throws {
        let h = await teamlessHarness()
        defer { h.tearDown() }
        let join = h.store.teamJoin
        join.form.teamCode = "AINGTEAM"
        await join.form.previewTeamCode().value

        // ① 주기 새로고침이 먼저 떠난다(그때는 무소속이라 소속 조회가 [] 를 싣고 온다).
        let staleHold = BaseHold.install(host: h.host) { NowStubServer.key(for: $0) == "memberships" }
        h.store.refresh()
        #expect(await staleHold.waitHeld())
        let refreshesBefore = h.store.refreshCount

        // ② 합류 **뒤에** 나가는 소속 조회는 전부 붙잡아 둔다(합류가 거는 새로고침 · 프로필 다시 읽기).
        //    앞 조회의 [] 만 먼저 도착하는 순간을 만들려는 것이다.
        let afterJoinHold = BaseHold.install(host: h.host, limit: 4) { NowStubServer.key(for: $0) == "memberships" }
        await join.submit()?.value
        #expect(!h.store.hasNoTeam && h.store.isSettlingTeam)

        // ③ 앞 조회가 이제야 도착한다 — 그 [] 는 이미 지난 사실이다.
        #expect(await staleHold.releaseAndWaitDelivered())
        #expect(await baseWaitUntil { h.store.refreshCount > refreshesBefore }, "합류 뒤 소속을 다시 읽지 않았다")
        #expect(!h.store.hasNoTeam, "합류 전에 떠난 조회가 무소속 카드를 되살렸다")
        #expect(h.store.isSettlingTeam && h.store.teamLoadState == .loading)

        // ④ 붙잡아 둔 조회를 놓는다(이제 서버는 팀을 준다).
        h.server.override("memberships", nil)
        #expect(await afterJoinHold.releaseAndWaitDelivered())
        await h.settle()
        #expect(h.store.membership?.teamName == "지금팀" && !h.store.isSettlingTeam)
        #expect(h.store.teamLoadState == .loaded)
    }

    @Test("도는 중에 또 누르면 왕복이 겹치지 않고, 세대가 바뀐 뒤 도착한 **성공** 응답도 화면을 바꾸지 않는다")
    func doubleTapAndLateJoinAfterReset() async throws {
        let h = await teamlessHarness()
        defer { h.tearDown() }
        let join = h.store.teamJoin
        join.form.teamCode = "AINGTEAM"
        await join.form.previewTeamCode().value

        let joinHold = BaseHold.rpc("join_team", host: h.host)
        let task = try #require(join.submit())
        #expect(await joinHold.waitHeld())
        #expect(join.submit() == nil, "도는 중에 또 눌러 왕복이 겹쳤다(둘째 join_team 은 이미 팀원이라 0행이다)")
        #expect(join.isSubmitting)

        // 그 사이 세대가 바뀐다(로그아웃 정리 — 앱 모델이 `now.reset()` 을 부르는 그 자리).
        // 세션은 아직 살아 있어 붙잡힌 합류는 **200 으로 성공해 돌아온다** — 세대 가드가 없으면 그대로 팀 화면이 된다.
        h.store.reset()
        #expect(!join.isSubmitting)
        #expect(join.form.teamCode == "" && join.form.joinPreview == nil, "앞 사람이 친 코드가 다음 사람 화면에 남았다")
        let refreshesBefore = h.store.refreshCount

        #expect(await joinHold.releaseAndWaitDelivered())
        await task.value
        #expect(h.requests("rpc.join_team").count == 1, "겹쳐 나간 합류가 있다")
        #expect(!h.store.isSettlingTeam, "정리 전에 떠난 합류의 늦은 성공이 지금 화면을 팀 화면으로 바꿨다")
        #expect(h.store.membership == nil && join.notice == nil)
        await h.barrier()
        #expect(h.store.refreshCount == refreshesBefore, "늦은 합류가 새로고침까지 걸었다")
    }

    // MARK: - 실패

    @Test("합류 실패는 카드에 남아 다시 시도한다(세션·소속은 그대로) · 서버 문구는 그대로 보여 준다")
    func failureKeepsCardAndRetries() async throws {
        let h = await teamlessHarness(join: .json(#"{"message":"boom"}"#, status: 500))
        defer { h.tearDown() }
        let join = h.store.teamJoin
        join.form.teamCode = "AINGTEAM"
        await join.form.previewTeamCode().value
        await join.submit()?.value

        #expect(join.notice == MobileSessionText.network)
        #expect(h.store.hasNoTeam && !h.store.isSettlingTeam, "실패했는데 무소속 카드를 내렸다")
        #expect(h.model.session.phase == .signedIn, "합류 실패가 사람을 로그아웃시켰다")
        #expect(join.form.joinPreview != nil, "실패는 미리보기를 지우지 않는다(같은 코드로 바로 다시)")
        #expect(join.canSubmit)

        // 서버가 살아나면 같은 코드로 한 번 더 — 새 계정을 만들거나 다시 로그인하지 않는다.
        h.server.override("rpc.join_team", .json(Self.joinRow))
        h.server.override("memberships", nil)
        await join.submit()?.value
        await h.settle()
        #expect(h.store.membership?.teamName == "지금팀")
        #expect(join.notice == nil)
        #expect(h.requests("rpc.join_team").count == 2)

        // 팀 만들기 실패는 서버 문구를 그대로 쓴다(가입 화면과 같은 매핑).
        let creator = await teamlessHarness(create: .json(#"{"message":"팀 이름이 이미 있어요"}"#, status: 400))
        defer { creator.tearDown() }
        creator.store.teamJoin.toggleCreateTeamMode()
        creator.store.teamJoin.form.createTeamName = "새벽 러너스"
        await creator.store.teamJoin.submit()?.value
        #expect(creator.store.teamJoin.notice == "팀 이름이 이미 있어요")
        #expect(creator.store.hasNoTeam)
    }

    // MARK: - 뽑아 쓴 팀 칸이 가입 화면에서 그대로 동작한다

    @Test("팀 칸을 한 벌로 뽑아도 가입 화면 관찰이 끊기지 않는다(값은 바뀌는데 화면이 안 그려지는 죽은 칸이 되지 않게)")
    func signUpTeamFieldsStayObservable() {
        let host = BaseStub.makeHost("signup-observe")
        let storage = BaseStub.makeStorage()
        defer { BaseStub.tearDown(host: host, storage: storage) }
        let session = MobileSessionStore(
            service: BaseStub.makeService(host: host),
            vault: InMemoryTokenVault(),
            storage: storage,
            appInfo: BaseStub.appInfo,
            installationID: "11111111-2222-4333-8444-555555555555",
            clock: .fixed(MobileClock.demoInstant)
        )
        let store = MobileSignUpStore(session: session)

        // 화면이 읽는 이름 그대로 읽고, **폼 쪽을** 바꾼다 — 사이에 전달만 있고 관찰이 없으면 여기서 잡힌다.
        let mutations: [(String, () -> Void)] = [
            ("teamCode", { store.teamForm.teamCode = "AINGTEAM" }),
            ("isCreateTeamMode", { store.teamForm.isCreateTeamMode = true }),
            ("createTeamName", { store.teamForm.createTeamName = "새벽 러너스" }),
            ("createTeamGoalHours", { store.teamForm.createTeamGoalHours = 50 }),
            ("joinPreviewMessage", { store.teamForm.joinPreviewMessage = MobileSignUpText.previewChecking }),
            ("joinPreview", { store.teamForm.joinPreview = TeamJoinPreview(teamID: "t", name: "팀", weeklyGoalHours: 40, memberCount: 2) }),
        ]
        for (name, mutate) in mutations {
            let fired = BaseLockedBox(false)
            withObservationTracking {
                _ = store.teamCode
                _ = store.isCreateTeamMode
                _ = store.createTeamName
                _ = store.createTeamGoalHours
                _ = store.joinPreviewMessage
                _ = store.joinPreview
            } onChange: {
                fired.mutate { $0 = true }
            }
            mutate()
            #expect(fired.get(), "\(name) 이 바뀌었는데 가입 화면이 다시 그려지지 않는다")
        }

        // 값도 양쪽에서 같은 것을 가리킨다(화면이 쓰면 폼이 받고, 폼이 받으면 화면이 읽는다).
        store.teamCode = "SEOUL123"
        #expect(store.teamForm.teamCode == "SEOUL123")
        store.teamForm.createTeamGoalHours = 7
        #expect(store.createTeamGoalHours == 7)
        #expect(MobileSignUpStore.defaultGoalHours == MobileTeamJoinForm.defaultGoalHours)
        #expect(MobileSignUpStore.goalHoursRange == MobileTeamJoinForm.goalHoursRange)
    }

    // MARK: - 모양 · 주인 계약

    @Test("모양 계약: 무소속 카드는 재디자인 B 토큰만 · 채운 버튼 하나 · 팀 왕복은 가입 화면과 한 벌(두 벌이면 한쪽만 고쳐진다)")
    func teamJoinShapeAndOwnerContracts() throws {
        let card = try IntegrationContractTests.code("Sources/CheckMobileKit/Now/NowTeamJoinCard.swift")
        for part in ["InsetGroup", "GroupRow", "AingButton", "InlineNotice", "MobileTheme."] {
            #expect(card.contains(part), "무소속 카드가 \(part) 를 쓰지 않는다")
        }
        #expect(card.components(separatedBy: "kind: .filled").count - 1 == 1, "무소속 카드에 채운 버튼이 하나가 아니다")
        #expect(!card.contains("Color(red:") && !card.contains("Color(hex") && !card.contains(".shadow("), "무소속 카드가 새 색·그림자를 만든다")
        #expect(!card.contains(".fixedSize()"), "가로까지 고정하면 큰 글자에서 설명이 화면 밖으로 잘린다(AX3 실측)")

        let tab = try IntegrationContractTests.code("Sources/CheckMobileKit/Now/NowTab.swift")
        #expect(tab.contains("NowTeamJoinSection(store: store.teamJoin)"), "무소속 자리가 여전히 안내만 하고 끝난다")

        // 폰에서 팀을 정하는 왕복의 주인은 한 곳이다.
        let owners = try IntegrationContractTests.files(
            containing: ["service.joinTeam(", "service.createTeam(", "lookupTeamByCode("],
            under: "Sources/CheckMobileKit"
        )
        #expect(owners == ["Sources/CheckMobileKit/Session/MobileTeamJoinForm.swift"], "팀 왕복 구현이 두 벌이다: \(owners)")

        // 센터 게이트 문구는 서버가 0행을 낸 그 자리에서만 선다(맥 전용 서버 함수가 아니다 — 폰도 그 0행을 받는다).
        let gate = try IntegrationContractTests.files(containing: ["teamlessJoinBlocked"], under: "Sources/CheckMobileKit")
        #expect(gate == [
            "Sources/CheckMobileKit/Session/MobileSignUpStore.swift",
            "Sources/CheckMobileKit/Session/MobileTeamJoinForm.swift",
        ], "센터 게이트 문구의 자리가 바뀌었다: \(gate)")

        // 무소속 카드도 맥 전용 API 를 부르지 않는다(가입 화면과 같은 금지 목록).
        let banned = ["WorkTimerStore", "takePokes", "workTick", "work_tick", "startWork(", "stopWork(", "sendPoke", "MacOnly"]
        for file in ["Sources/CheckMobileKit/Now/NowTeamJoin.swift", "Sources/CheckMobileKit/Now/NowTeamJoinCard.swift",
                     "Sources/CheckMobileKit/Session/MobileTeamJoinForm.swift"] {
            let code = try IntegrationContractTests.code(file)
            #expect(!code.isEmpty, "\(file) 이 비었다")
            for word in banned {
                #expect(!code.contains(word), "\(file) 이 \(word) 를 참조한다")
            }
        }
    }

    // MARK: - 데모(앱스토어 스크린샷)

    @Test("데모 라우트 now/teamless: 로그인된 무소속 계정으로 서고, 미리보기·합류 픽스처가 실제 디코드를 지난다")
    func demoTeamlessRoute() async throws {
        #expect(MobileDemo.launchRoute(arguments: ["app", "-AingCheckDemo", "YES", "-AingCheckDemoRoute", "now/teamless"]) == "now/teamless")
        #expect(!MobileAuthRoute.startsSignedOut(demoRoute: "now/teamless"), "무소속 장면은 로그인된 계정으로 시작한다")
        #expect(NowDemoStage.stages(arguments: ["app", NowDemoStage.argument, "teamcreate"]).contains("teamcreate"))

        let index = MobileDemoFixtures.load()
        #expect(index.duplicateKeys.isEmpty, "\(index.duplicateKeys)")
        #expect(
            index.entries.contains { $0.key == "rest.memberships.get" && $0.scenario == "now-teamless" },
            "무소속 장면에 빈 소속 픽스처가 없다 — 데모가 팀 있는 계정으로 뜬다"
        )

        let host = BaseStub.makeHost("now-teamless-demo")
        MobileStubURLProtocol.register(host: host) { index.response(for: $0, scenario: "now-teamless") }
        defer { MobileStubURLProtocol.unregister(host: host) }
        let service = BaseStub.makeService(host: host)

        let membership = try await service.fetchOwnMembership(accessToken: MobileDemo.accessToken, userID: MobileDemo.userID)
        #expect(membership == nil, "무소속 장면인데 소속이 있다")

        let form = MobileTeamJoinForm(service: service)
        form.teamCode = "AING7K2Q"
        await form.previewTeamCode().value
        #expect(form.joinPreview?.name == "아잉 데모팀", "미리보기 픽스처가 디코드되지 않았다")
        guard case .joined(_, let name, _) = try await form.runTeamStep(accessToken: MobileDemo.accessToken) else {
            Issue.record("데모 픽스처로 합류가 되지 않았다")
            return
        }
        #expect(name == "아잉 데모팀")
        #expect(MobileForbiddenCalls.violations(in: MobileStubURLProtocol.requests(host: host)).isEmpty)
    }
}
