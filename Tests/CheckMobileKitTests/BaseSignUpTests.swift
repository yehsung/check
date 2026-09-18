import CheckCore
import CheckMobileShared
import Foundation
import Testing
@testable import CheckMobileKit

/// 폰 가입(w16 · SPEC 작업 B): 맥 가입 폼과 같은 가드(센터 미선택 · 코드 미확인 · 팀 이름 공백 · 입력 셋 공백) · 미리보기 경합 ·
/// 가입 성공이 로그인 성공과 **같은 길**을 탄다 · join_team 0행(센터 게이트) 문구 · 팀 만들기 → 참여코드 카드 → 시작 · 데모 라우트·픽스처 ·
/// 소스 계약(가입·재설정 화면이 맥 전용 API 를 부르지 않는다).
@MainActor
@Suite struct BaseSignUpTests {
    struct Harness {
        let host: String
        let storage: AingSharedStorage
        let vault: InMemoryTokenVault
        let clock: BaseTestClock
        let service: SupabaseWorkService
        let session: MobileSessionStore
        let store: MobileSignUpStore

        var requests: [MobileStubRequest] { baseRequests(host: host) }

        func paths() -> [String] {
            requests.map { $0.rpcName.map { "rpc/\($0)" } ?? $0.path }
        }

        func count(rpc: String) -> Int { requests.filter { $0.rpcName == rpc }.count }
        func count(path: String) -> Int { requests.filter { $0.path == path }.count }
        func body(path: String) -> String { requests.first { $0.path == path }?.bodyText ?? "" }

        func tearDown() { BaseStub.tearDown(host: host, storage: storage) }
    }

    nonisolated static let freshAccess = BaseStub.jwt(exp: MobileClock.demoInstant.addingTimeInterval(3600), subject: "user-new")
    nonisolated static let previewRow = #"[{"team_id":"team-1","name":"아잉팀","weekly_goal_hours":40,"member_count":3}]"#
    nonisolated static let joinRow = #"[{"team_id":"team-1","name":"아잉팀","weekly_goal_hours":40}]"#
    nonisolated static let createRow = #"[{"team_id":"team-9","name":"새로운 팀","invite_code":"X7K2M9Q4","weekly_goal_hours":50}]"#

    /// 흔한 서버 + 가입 넷(lookup · signup · join · create). 바꾸고 싶은 답만 넘긴다.
    static func server(
        signup: MobileStubResponse? = nil,
        join: MobileStubResponse? = nil,
        create: MobileStubResponse? = nil,
        lookup: MobileStubResponse? = nil
    ) -> MobileStubURLProtocol.Responder {
        let signupResponse = signup ?? BaseStub.authResponse(access: freshAccess, refresh: "refresh-new", userID: "user-new")
        return BaseSessionTests.happyServer(extra: { request in
            switch request.rpcName {
            case "lookup_team_by_code": return lookup ?? .json(previewRow)
            case "join_team": return join ?? .json(joinRow)
            case "create_team": return create ?? .json(createRow)
            default: break
            }
            if request.path == "/auth/v1/signup" { return signupResponse }
            return nil
        })
    }

    /// 로그아웃 상태까지 띄운 세션 + 가입 스토어.
    func makeHarness(createTeam: Bool = false, responder: @escaping MobileStubURLProtocol.Responder) async -> Harness {
        let host = BaseStub.makeHost("signup")
        MobileStubURLProtocol.register(host: host, responder: responder)
        let storage = BaseStub.makeStorage()
        let vault = InMemoryTokenVault()
        let clock = BaseTestClock()
        let service = BaseStub.makeService(host: host)
        let session = MobileSessionStore(
            service: service,
            vault: vault,
            storage: storage,
            appInfo: BaseStub.appInfo,
            installationID: "11111111-2222-4333-8444-555555555555",
            clock: clock.clock
        )
        session.clientReleaseTimeoutSeconds = 0
        await session.launch()
        MobileStubURLProtocol.clearRequests(host: host)
        let store = MobileSignUpStore(session: session, createTeam: createTeam)
        return Harness(host: host, storage: storage, vault: vault, clock: clock, service: service, session: session, store: store)
    }

    /// 맥 테스트(`signUpAutoJoinsWithTeamCodeAfterAccount`)와 같은 입력.
    func fillAccount(_ h: Harness, center: String? = CenterLabel.seoul) {
        h.store.displayName = "영식"
        h.store.email = "member@example.com"
        h.store.password = "team-password"
        h.store.center = center
    }

    // MARK: - 가드(맥 signUp() 순서 그대로 · 버튼 비활성과 제출 가드 둘 다)

    @Test("센터 미선택: 버튼은 비활성이고, 키보드 제출로 새도 스토어가 막고 이유를 말한다(요청 0)")
    func rejectsWithoutCenter() async {
        let h = await makeHarness(responder: Self.server())
        defer { h.tearDown() }
        fillAccount(h, center: nil)
        h.store.teamCode = "AINGTEAM"
        h.store.joinPreview = TeamJoinPreview(teamID: "team-1", name: "아잉팀", weeklyGoalHours: 40, memberCount: 3)

        #expect(!h.store.canSubmit, "센터를 고르기 전엔 채운 버튼이 비활성이어야 한다")
        #expect(h.store.submit() == nil)
        #expect(h.store.notice == MobileSignUpText.centerRequired)
        #expect(h.session.phase == .signedOut)
        await baseBarrier(h.service)
        #expect(h.count(path: "/auth/v1/signup") == 0, "센터 없이 계정을 만들면 영영 미지정인 사람이 생긴다")

        h.store.center = CenterLabel.busan
        #expect(h.store.canSubmit)
    }

    @Test("코드 미확인: 미리보기가 팀을 찾기 전엔 가입이 시작되지 않는다 · 만들기 모드는 팀 이름 공백을 막는다")
    func rejectsUnverifiedCodeAndBlankTeamName() async {
        let h = await makeHarness(responder: Self.server())
        defer { h.tearDown() }
        fillAccount(h)
        h.store.teamCode = "AINGTEAM"
        h.store.joinPreview = nil
        #expect(h.store.submit() == nil)
        #expect(h.store.notice == MobileSignUpText.codeUnverified)

        h.store.toggleCreateTeamMode()
        #expect(h.store.isCreateTeamMode)
        #expect(h.store.notice == nil, "모드 전환은 이전 안내를 지운다")
        h.store.createTeamName = "   "
        #expect(h.store.submit() == nil)
        #expect(h.store.notice == MobileSignUpText.teamNameRequired)

        await baseBarrier(h.service)
        #expect(h.count(path: "/auth/v1/signup") == 0)
        #expect(h.session.phase == .signedOut)
    }

    @Test("입력 셋 공백: 별명·이메일·비밀번호 중 하나라도 비면 팀·센터보다 먼저 막는다(맥과 같은 순서)")
    func rejectsMissingCredentials() async {
        let h = await makeHarness(responder: Self.server())
        defer { h.tearDown() }
        // 셋 다 비고 센터도 없다 — 첫 문구는 입력 셋이다.
        #expect(h.store.submit() == nil)
        #expect(h.store.notice == MobileSignUpText.missingFields)
        fillAccount(h)
        h.store.joinPreview = TeamJoinPreview(teamID: "team-1", name: "아잉팀", weeklyGoalHours: 40, memberCount: 3)
        for blank in ["displayName", "email", "password"] {
            let saved = (h.store.displayName, h.store.email, h.store.password)
            switch blank {
            case "displayName": h.store.displayName = "  "
            case "email": h.store.email = " "
            default: h.store.password = ""
            }
            #expect(h.store.submit() == nil, "\(blank) 이 비었는데 가입이 시작됐다")
            #expect(h.store.notice == MobileSignUpText.missingFields)
            (h.store.displayName, h.store.email, h.store.password) = saved
        }
        await baseBarrier(h.service)
        #expect(h.requests.isEmpty)
    }

    // MARK: - 코드 미리보기

    @Test("미리보기 경합: 먼저 보낸 요청의 늦은 응답이 최신 결과를 덮지 않는다(마지막 요청 우선)")
    func previewRaceKeepsLatest() async {
        let h = await makeHarness(responder: Self.server(lookup: nil))
        defer { h.tearDown() }
        MobileStubURLProtocol.register(host: h.host, responder: BaseSessionTests.happyServer(extra: { request in
            guard request.rpcName == "lookup_team_by_code" else { return nil }
            if request.bodyText.contains("AAAA1111") {
                return .json(#"[{"team_id":"team-a","name":"A팀","weekly_goal_hours":40,"member_count":2}]"#)
            }
            return .json(#"[{"team_id":"team-b","name":"B팀","weekly_goal_hours":50,"member_count":4}]"#)
        }))
        let hold = BaseHold.install(host: h.host) { $0.rpcName == "lookup_team_by_code" && $0.bodyText.contains("AAAA1111") }

        h.store.teamCode = "AAAA1111"
        let first = h.store.previewTeamCode()
        #expect(await hold.waitHeld())
        #expect(h.store.joinPreviewMessage == MobileSignUpText.previewChecking)

        h.store.teamCode = "BBBB2222"
        let second = h.store.previewTeamCode()
        await second.value
        #expect(h.store.joinPreview?.name == "B팀")
        #expect(h.store.joinPreviewMessage == "")

        #expect(await hold.releaseAndWaitDelivered())
        await first.value
        await baseBarrier(h.service)
        #expect(h.store.joinPreview?.name == "B팀", "늦게 온 A 응답이 최신 B 를 덮었다")
    }

    @Test("미리보기: 못 찾으면(0행·오류) '코드를 확인해 주세요' · 빈 코드는 요청 없이 비운다 · 코드는 정규화해 보낸다")
    func previewMissAndEmpty() async {
        let h = await makeHarness(responder: Self.server(lookup: .json("[]")))
        defer { h.tearDown() }
        h.store.teamCode = "nosuch-xx"
        await h.store.previewTeamCode().value
        #expect(h.store.joinPreview == nil)
        #expect(h.store.joinPreviewMessage == MobileSignUpText.previewMiss)
        #expect(h.body(path: "/rest/v1/rpc/lookup_team_by_code").contains(#""code":"NOSUCHXX""#))
        let bearer = h.requests.first { $0.rpcName == "lookup_team_by_code" }.map(BaseStub.bearer) ?? ""
        #expect(bearer == "Bearer stub-anon-key", "미리보기는 anon 으로 부른다(가입 전이라 로그인 토큰이 없다)")

        MobileStubURLProtocol.register(host: h.host, responder: Self.server(lookup: .networkFailure()))
        await h.store.previewTeamCode().value
        #expect(h.store.joinPreviewMessage == MobileSignUpText.previewMiss)

        h.store.teamCode = " - "
        await h.store.previewTeamCode().value
        #expect(h.store.joinPreview == nil && h.store.joinPreviewMessage == "")
        #expect(h.count(rpc: "lookup_team_by_code") == 2, "빈 코드로 왕복하지 않는다")
    }

    // MARK: - 성공 경로

    @Test("코드 가입 성공: signup → join_team → 로그인 성공과 같은 길(키체인 · 이메일 · 기기 등록 · 소속) · 금지 호출 0")
    func signUpWithCodeEntersLikeSignIn() async throws {
        let h = await makeHarness(responder: Self.server())
        defer { h.tearDown() }
        fillAccount(h)
        h.store.teamCode = "aing-team"
        await h.store.previewTeamCode().value
        #expect(h.store.joinPreview?.name == "아잉팀")
        #expect(h.store.canSubmit)

        let task = try #require(h.store.submit())
        #expect(h.store.isSubmitting)
        await task.value
        #expect(!h.store.isSubmitting)
        #expect(h.session.phase == .signedIn)
        #expect(h.session.session?.userID == "user-new")
        #expect(h.session.session?.accessToken == Self.freshAccess)
        #expect(h.vault.read(AingKeychain.accessTokenKey) == Self.freshAccess, "키체인에 저장됐다(로그인과 같은 길)")
        #expect(h.session.storedEmail == "member@example.com")
        #expect(h.session.signedInViaForm, "폼 제출로 들어온 로그인이다(암호 저장 창 대기 규칙이 같다)")
        #expect(h.store.createdSession == nil)
        #expect(h.store.password == "", "비밀번호는 비운다(맥과 같다)")
        await h.session.pendingDeviceRegistration?.value
        #expect(await baseWaitUntil { h.session.profile?.teamName == "테스트팀" })
        #expect(h.count(rpc: "register_device") == 1)

        // 요청 순서: 계정 가입(/auth/v1/signup) 이 먼저, 그 다음 자동 합류(/rest/v1/rpc/join_team). 가입 본문엔 team_id 가 없다.
        let paths = h.paths()
        let signupIndex = try #require(paths.firstIndex(of: "/auth/v1/signup"))
        let joinIndex = try #require(paths.firstIndex(of: "rpc/join_team"))
        #expect(signupIndex < joinIndex)
        let signupBody = h.body(path: "/auth/v1/signup")
        #expect(!signupBody.contains("\"team_id\""))
        #expect(signupBody.contains(#""display_name":"영식""#))
        #expect(signupBody.contains(#""center":"seoul""#), "센터는 가입 메타데이터에 실린다(왕복이 늘지 않는다)")
        #expect(h.body(path: "/rest/v1/rpc/join_team").contains(#""code":"AINGTEAM""#), "합류 본문에 정규화된 코드")
        let joinBearer = h.requests.first { $0.rpcName == "join_team" }.map(BaseStub.bearer) ?? ""
        #expect(joinBearer == "Bearer \(Self.freshAccess)", "합류는 방금 받은 세션 토큰으로")
        #expect(MobileForbiddenCalls.violations(in: h.requests).isEmpty)

        // 대조: 비밀번호 로그인이 세션을 얻은 **뒤** 내는 요청 꼬리가 가입과 글자 그대로 같다.
        let s = await makeHarness(responder: BaseSessionTests.happyServer(extra: { request in
            request.path == "/auth/v1/token" ? BaseStub.authResponse(access: Self.freshAccess, refresh: "refresh-new", userID: "user-new") : nil
        }))
        defer { s.tearDown() }
        await s.session.signIn(email: "member@example.com", password: "team-password")
        await s.session.pendingDeviceRegistration?.value
        #expect(await baseWaitUntil { s.session.profile?.teamName == "테스트팀" })
        // 세션을 얻은 요청(token / join_team) **뒤**의 경로만 견준다.
        let signInTail = Array(s.paths().drop { $0 != "/auth/v1/token" }.dropFirst())
        let signUpTail = Array(paths.drop { $0 != "rpc/join_team" }.dropFirst())
        #expect(!signInTail.isEmpty && signInTail == signUpTail, "가입 뒤 경로 \(signUpTail) ≠ 로그인 뒤 경로 \(signInTail)")
    }

    @Test("join_team 0행(코드는 맞는데): '다른 센터 팀' 문구로 남고 세션은 잇지 않는다 → 팀 만들기로 이어 가면 계정은 다시 만들지 않는다")
    func joinZeroRowsSaysOtherCenter() async throws {
        let h = await makeHarness(responder: Self.server(join: .json("[]")))
        defer { h.tearDown() }
        fillAccount(h)
        h.store.teamCode = "AINGTEAM"
        await h.store.previewTeamCode().value
        await h.store.submit()?.value

        #expect(h.store.stage == .teamless)
        #expect(h.store.joinPreviewMessage == MobileSignUpText.teamlessJoinBlocked)
        // 화면이 읽는 줄은 previewLine 하나다(MobileSignUpView 의 미리보기 InlineNotice) — 스토어 필드가 아니라 **이 줄**에 문구가 서야 한다.
        // 미리보기 요약("팀 아잉팀 · 3명 · 주 40시간")이 남아 있으면 그 줄이 덮어 '다른 센터' 는 어디에도 안 그려진다(검증자 실측).
        let line = try #require(h.store.previewLine, "코드 칸 아래 줄이 비었다")
        #expect(line.text == MobileSignUpText.teamlessJoinBlocked, "화면 줄이 '\(line.text)' — 다른 센터 안내가 아니다")
        #expect(!line.isSuccess, "다른 센터 안내가 안내색(성공)으로 그려진다")
        #expect(h.store.joinPreview == nil, "서버가 부정한 미리보기는 더 이상 '합류 가능' 이 아니다")
        #expect(h.store.notice == nil)
        #expect(h.store.createdSession?.userID == "user-new", "계정은 만들어졌다 — 세션은 스토어가 쥔다")
        #expect(h.session.phase == .signedOut, "팀이 없는 채로 탭에 들어가지 않는다(폰엔 무소속 합류 칸이 없다)")
        #expect(h.count(rpc: "register_device") == 0)
        #expect(h.store.canSubmit)

        // 같은 코드로 [참여하기] 를 다시 눌러도 헛왕복(같은 0행)을 돌지 않고 가드가 이유를 말한다 — 다른 센터 안내는 그대로 남는다.
        #expect(h.store.submit() == nil)
        #expect(h.store.notice == MobileSignUpText.codeUnverified)
        await baseBarrier(h.service)
        #expect(h.count(rpc: "join_team") == 1, "같은 코드로 join_team 이 또 나갔다")
        #expect(h.store.previewLine?.text == MobileSignUpText.teamlessJoinBlocked)

        // 같은 화면에서 팀 만들기로 — signup 은 다시 나가지 않는다.
        h.store.toggleCreateTeamMode()
        #expect(h.store.joinPreviewMessage == "")
        h.store.createTeamName = "새로운 팀"
        h.store.createTeamGoalHours = 50
        await h.store.submit()?.value
        #expect(h.store.stage == .createdTeam(code: "X7K2M9Q4"))
        #expect(h.count(path: "/auth/v1/signup") == 1)
        #expect(h.count(rpc: "create_team") == 1)
        #expect(h.session.phase == .signedOut, "참여코드 카드 단계 — [시작하기] 전")

        await h.store.submit()?.value
        #expect(h.session.phase == .signedIn)
        #expect(h.session.storedEmail == "member@example.com")
        #expect(MobileForbiddenCalls.violations(in: h.requests).isEmpty)
    }

    @Test("join_team 0행 뒤 같은 센터 코드를 다시 치면 미리보기 → join_team 성공 → 로그인과 같은 길 · 화면 줄은 문구가 요약보다 먼저다")
    func joinZeroRowsThenOtherCodeSucceeds() async throws {
        let h = await makeHarness(responder: Self.server(join: .json("[]")))
        defer { h.tearDown() }
        fillAccount(h)
        h.store.teamCode = "AINGTEAM"
        await h.store.previewTeamCode().value
        #expect(h.store.previewLine?.isSuccess == true)
        await h.store.submit()?.value
        #expect(h.store.stage == .teamless)
        #expect(h.store.previewLine?.text == MobileSignUpText.teamlessJoinBlocked)

        // 화면 줄 계약: 문구가 있으면 문구가 먼저다 — 새 코드를 확인하는 동안 옛 팀 요약이 아니라 '확인 중' 이 보여야 한다
        // (요약이 먼저면 문구를 세우고 요약을 안 지운 모든 곳이 화면에서 사라진다 — 위 0행이 그 첫 사례였다).
        h.store.joinPreview = TeamJoinPreview(teamID: "team-1", name: "아잉팀", weeklyGoalHours: 40, memberCount: 3)
        h.store.joinPreviewMessage = MobileSignUpText.previewChecking
        #expect(h.store.previewLine?.text == MobileSignUpText.previewChecking)
        #expect(h.store.previewLine?.isSuccess == false)
        h.store.joinPreviewMessage = ""
        #expect(h.store.previewLine?.isSuccess == true, "문구가 없으면 요약이다")
        h.store.joinPreview = nil

        // 같은 센터 팀 코드로 다시 — 미리보기가 서고, join_team 이 행을 주면 로그인과 같은 길로 들어간다(signup 은 한 번뿐).
        MobileStubURLProtocol.register(host: h.host, responder: Self.server())
        h.store.teamCode = "SEOUL123"
        await h.store.previewTeamCode().value
        #expect(h.store.previewLine?.isSuccess == true)
        #expect(h.store.joinPreviewMessage == "")
        await h.store.submit()?.value
        #expect(h.session.phase == .signedIn)
        #expect(h.session.session?.userID == "user-new")
        #expect(h.count(path: "/auth/v1/signup") == 1)
        #expect(h.count(rpc: "join_team") == 2)
        #expect(h.body(path: "/rest/v1/rpc/join_team").contains(#""code":"AINGTEAM""#), "첫 합류는 첫 코드")
        #expect(h.requests.last { $0.rpcName == "join_team" }?.bodyText.contains(#""code":"SEOUL123""#) == true, "둘째 합류는 새 코드")
        #expect(MobileForbiddenCalls.violations(in: h.requests).isEmpty)
    }

    @Test("팀 만들기 가입: signup → create_team(이름·목표) → 참여코드 카드 → 시작하기. join_team 은 부르지 않는다")
    func createTeamShowsCodeThenStarts() async throws {
        let h = await makeHarness(createTeam: true, responder: Self.server())
        defer { h.tearDown() }
        #expect(h.store.isCreateTeamMode)
        #expect(h.store.primaryTitle == MobileSignUpText.createAndStart)
        fillAccount(h, center: CenterLabel.busan)
        h.store.createTeamName = " 새로운 팀 "
        h.store.createTeamGoalHours = 50
        await h.store.submit()?.value

        #expect(h.store.stage == .createdTeam(code: "X7K2M9Q4"))
        #expect(h.store.primaryTitle == MobileSignUpText.start)
        let createBody = h.body(path: "/rest/v1/rpc/create_team")
        #expect(createBody.contains(#""team_name":"새로운 팀""#), "팀 이름은 앞뒤 공백을 떼고 보낸다")
        #expect(createBody.contains(#""goal_hours":50"#))
        #expect(h.count(rpc: "join_team") == 0)
        #expect(h.body(path: "/auth/v1/signup").contains(#""center":"busan""#))
        #expect(h.session.phase == .signedOut)

        await h.store.submit()?.value
        #expect(h.session.phase == .signedIn)
        #expect(h.session.session?.userID == "user-new")
        #expect(h.store.createdSession == nil)
    }

    /// 세션 없는 200 = 가입 확인을 켠 서버. 여기서는 **팀 단계로 새지 않는다**는 것만 본다 —
    /// 코드 화면의 규칙(두 서버 모드 · 재전송 · 출구)은 `BaseSignUpConfirmTests` 가 통째로 덮는다.
    /// 본문에 `identities` 키가 아예 없는 옛 GoTrue 응답도 같은 갈래다(빈 배열만 "이미 가입된 이메일"이다).
    @Test("세션 없는 200(가입 확인을 켠 서버): 코드 화면으로 가고 팀 호출·세션은 없다 · 비밀번호는 비운다")
    func confirmEmailRequired() async {
        let h = await makeHarness(responder: Self.server(signup: .json(#"{"user":{"id":"user-new"}}"#)))
        defer { h.store.cancelPendingWork(); h.tearDown() }
        fillAccount(h)
        h.store.teamCode = "AINGTEAM"
        await h.store.previewTeamCode().value
        await h.store.submit()?.value
        #expect(h.store.stage == .confirmCode)
        #expect(h.store.notice == MobileSignUpText.confirmSent)
        #expect(!h.store.noticeIsError)
        #expect(h.store.password == "")
        #expect(h.session.phase == .signedOut)
        #expect(h.count(rpc: "join_team") == 0)
    }

    @Test("실패 문구: 중복 가입은 맥과 같은 매핑 · 네트워크는 연결 안내 · 합류/생성 실패는 teamless 로 남아 다시 시도한다")
    func failureMessages() async {
        let duplicate = await makeHarness(responder: Self.server(
            signup: .json(#"{"code":422,"msg":"User already registered"}"#, status: 422)
        ))
        defer { duplicate.tearDown() }
        fillAccount(duplicate)
        duplicate.store.teamCode = "AINGTEAM"
        await duplicate.store.previewTeamCode().value
        await duplicate.store.submit()?.value
        #expect(duplicate.store.notice == AuthErrorRules.message(for: SupabaseWorkServiceError.emailAlreadyRegistered, fallback: ""))
        #expect(duplicate.store.stage == .account)
        #expect(duplicate.session.phase == .signedOut)

        let offline = await makeHarness(responder: Self.server(signup: .networkFailure()))
        defer { offline.tearDown() }
        fillAccount(offline)
        offline.store.teamCode = "AINGTEAM"
        await offline.store.previewTeamCode().value
        await offline.store.submit()?.value
        #expect(offline.store.notice == MobileSessionText.network)
        #expect(offline.store.stage == .account)

        let joinFails = await makeHarness(responder: Self.server(join: .json(#"{"message":"boom"}"#, status: 500)))
        defer { joinFails.tearDown() }
        fillAccount(joinFails)
        joinFails.store.teamCode = "AINGTEAM"
        await joinFails.store.previewTeamCode().value
        await joinFails.store.submit()?.value
        #expect(joinFails.store.stage == .teamless)
        #expect(joinFails.store.notice == MobileSessionText.network)
        #expect(joinFails.store.createdSession != nil)
        // 서버가 살아나면 같은 코드로 다시 — signup 없이 join_team 만 한 번 더.
        MobileStubURLProtocol.register(host: joinFails.host, responder: Self.server())
        await joinFails.store.submit()?.value
        #expect(joinFails.session.phase == .signedIn)
        #expect(joinFails.count(path: "/auth/v1/signup") == 1)
        #expect(joinFails.count(rpc: "join_team") == 2)

        let createFails = await makeHarness(createTeam: true, responder: Self.server(
            create: .json(#"{"message":"팀 이름이 이미 있어요"}"#, status: 400)
        ))
        defer { createFails.tearDown() }
        fillAccount(createFails)
        createFails.store.createTeamName = "새로운 팀"
        await createFails.store.submit()?.value
        #expect(createFails.store.stage == .teamless)
        #expect(createFails.store.notice == "팀 이름이 이미 있어요")
    }

    // MARK: - 데모 라우트 · 픽스처

    /// 전역 데모 호스트로 실제 조립을 띄우는 검사는 `BaseAppModelTests.demoEnvironments` 에 있다(그 호스트를 두 스위트가 병렬로 쓰면 서로의
    /// 응답기를 내린다 — 실측). 여기서는 라우트 해석만 본다.
    @Test("데모 라우트 해석: signup · signup/create · reset 은 로그아웃으로 시작해 로그인 아래 화면을 연다 · 그 밖은 아니다")
    func demoRoutes() throws {
        #expect(MobileAuthRoute.demo("signup") == .signUp(createTeam: false))
        #expect(MobileAuthRoute.demo("signup/create") == .signUp(createTeam: true))
        #expect(MobileAuthRoute.demo("Signup/Create") == .signUp(createTeam: true))
        #expect(MobileAuthRoute.demo("reset") == .passwordReset)
        #expect(MobileAuthRoute.demo("reset/code") == nil)
        #expect(MobileAuthRoute.demo("login") == nil)
        #expect(MobileAuthRoute.demo("now") == nil)
        #expect(MobileAuthRoute.demo(nil) == nil)
        for signedOut in ["login", "signup", "signup/create", "reset"] {
            #expect(MobileAuthRoute.startsSignedOut(demoRoute: signedOut), "\(signedOut)")
        }
        for signedIn in ["now", "me/settings", "update", "rankings/tokens"] {
            #expect(!MobileAuthRoute.startsSignedOut(demoRoute: signedIn), "\(signedIn)")
        }
        // 실행 인자 → 라우트 문자열은 그대로 지난다(기본 now 는 로그인 장면이 아니다).
        #expect(MobileDemo.launchRoute(arguments: ["app", "-AingCheckDemo", "YES", "-AingCheckDemoRoute", "signup/create"]) == "signup/create")
        #expect(MobileAuthRoute.demo(MobileDemo.launchRoute(arguments: ["app", "-AingCheckDemo", "YES"])) == nil)
    }

    @Test("데모 픽스처(session/): 실제 서비스 디코드를 지나 가입 → 합류 → 로그인 상태가 된다(고유 호스트)")
    func demoFixturesDriveSignUp() async throws {
        let host = BaseStub.makeHost("signup-demo")
        let index = MobileDemoFixtures.load()
        #expect(index.duplicateKeys.isEmpty, "\(index.duplicateKeys)")
        MobileStubURLProtocol.register(host: host) { index.response(for: $0, scenario: "signup") }
        let storage = BaseStub.makeStorage()
        defer { BaseStub.tearDown(host: host, storage: storage) }
        let session = MobileSessionStore(
            service: BaseStub.makeService(host: host),
            vault: InMemoryTokenVault(),
            storage: storage,
            appInfo: BaseStub.appInfo,
            installationID: MobileDemo.installationID,
            clock: .fixed(MobileClock.demoInstant)
        )
        session.clientReleaseTimeoutSeconds = 0
        await session.launch()
        #expect(session.phase == .signedOut)

        let store = MobileSignUpStore(session: session)
        store.displayName = "민트"
        store.email = MobileDemo.email
        store.password = "demo-password"
        store.center = CenterLabel.seoul
        store.teamCode = "AING7K2Q"
        await store.previewTeamCode().value
        #expect(store.joinPreview?.name == "아잉 데모팀")
        #expect(store.joinPreview?.memberCount == 6)
        await store.submit()?.value
        #expect(session.phase == .signedIn)
        #expect(session.session?.userID == MobileDemo.userID)
        await session.pendingDeviceRegistration?.value
        #expect(await baseWaitUntil { session.profile?.teamName == "아잉 데모팀" })
        #expect(MobileForbiddenCalls.violations(in: MobileStubURLProtocol.requests(host: host)).isEmpty)

        // 만들기 픽스처도 디코드된다.
        let creator = MobileSignUpStore(session: MobileSessionStore(
            service: BaseStub.makeService(host: host),
            vault: InMemoryTokenVault(),
            storage: BaseStub.makeStorage(),
            appInfo: BaseStub.appInfo,
            installationID: MobileDemo.installationID,
            clock: .fixed(MobileClock.demoInstant)
        ), createTeam: true)
        creator.displayName = "민트"
        creator.email = MobileDemo.email
        creator.password = "demo-password"
        creator.center = CenterLabel.seoul
        creator.createTeamName = "새벽 러너스"
        await creator.submit()?.value
        #expect(creator.stage == .createdTeam(code: "AING7K2Q"))
    }

    // MARK: - 소스 계약

    @Test("소스 계약: 가입·재설정 화면과 스토어는 맥 전용 API 를 부르지 않고, 세션은 adoptSignedInSession 한 길로만 잇는다")
    func sourceContract() throws {
        let files = [
            "Sources/CheckMobileKit/Session/MobileSignUpStore.swift",
            "Sources/CheckMobileKit/Session/MobileSignUpView.swift",
            "Sources/CheckMobileKit/Session/MobilePasswordResetStore.swift",
            "Sources/CheckMobileKit/Session/MobilePasswordResetView.swift",
            "Sources/CheckMobileKit/Session/MobileSessionViews.swift",
        ]
        let banned = ["WorkTimerStore", "takePokes", "workTick", "work_tick", "closeAbandonedSessions", "syncUltraWallet", "buyUltra",
                      "updateAppVersion", "updateFocusMode", "heartbeat(", "startWork(", "stopWork(", "sendPoke", "upsertTokenUsage",
                      "reportDeviceInput", "upsertStatusDevice", "reopenSession", "MacOnly"]
        for file in files {
            let code = stripComments(try IntegrationContractTests.code(file))
            #expect(!code.isEmpty, "\(file) 이 비었다")
            for word in banned {
                #expect(!code.contains(word), "\(file) 이 \(word) 를 참조한다")
            }
        }
        // 세션을 잇는 길은 세션 스토어의 adoptSignedInSession 하나 — 스토어 둘이 키체인·기기 등록을 따로 하지 않는다.
        for store in ["Sources/CheckMobileKit/Session/MobileSignUpStore.swift", "Sources/CheckMobileKit/Session/MobilePasswordResetStore.swift"] {
            let code = stripComments(try IntegrationContractTests.code(store))
            #expect(code.contains("adoptSignedInSession("), "\(store) 가 로그인 성공과 같은 길을 타지 않는다")
            for direct in ["vault.write(", "AingSharedKeys.userID", "registerDevice(", "requestDeviceRegistration("] {
                #expect(!code.contains(direct), "\(store) 가 \(direct) 를 직접 한다(길이 갈린다)")
            }
        }
        let session = stripComments(try IntegrationContractTests.code("Sources/CheckMobileKit/Session/MobileSessionStore.swift"))
        #expect(session.components(separatedBy: "enterSignedIn(registrationReason: .signIn)").count == 2, "폼 로그인 마무리는 adoptSignedInSession 한 곳")
        // 화면: 재디자인 B 부품만 · 채운 버튼은 화면당 하나 · 새 색을 만들지 않는다.
        for view in ["Sources/CheckMobileKit/Session/MobileSignUpView.swift", "Sources/CheckMobileKit/Session/MobilePasswordResetView.swift"] {
            let code = stripComments(try IntegrationContractTests.code(view))
            #expect(code.components(separatedBy: "kind: .filled").count - 1 == 1, "\(view) 에 채운 버튼이 하나가 아니다")
            for part in ["MobileCenteredScreen", "MobileBrandHeader", "InsetGroup", "GroupRow", "AingButton", "InlineNotice"] {
                #expect(code.contains(part), "\(view) 가 \(part) 를 쓰지 않는다")
            }
            #expect(!code.contains("Color(red:") && !code.contains("Color(hex") && !code.contains(".shadow("), "\(view) 가 새 색·그림자를 만든다")
        }
        let login = stripComments(try IntegrationContractTests.code("Sources/CheckMobileKit/Session/MobileSessionViews.swift"))
        #expect(!login.contains("맥 앱에서"), "로그인 화면이 아직 맥 앱 안내를 한다")
        #expect(login.contains(".signUp(createTeam: false)") && login.contains(".passwordReset"), "로그인 화면에서 가입·재설정으로 가는 길이 없다")
    }
}
