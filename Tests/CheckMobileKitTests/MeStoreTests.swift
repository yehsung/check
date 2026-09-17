import CheckCore
import CheckMobileShared
import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import CheckMobileKit

@MainActor
@Suite("나 탭 스토어(rankme)")
struct MeStoreTests {
    nonisolated static let me = RankMeFixture.userID

    nonisolated static let shopState = #"{"ruby_balance":40,"ultra_balance":5,"ultra_price":3,"characters":[{"id":"fox","price":30,"owned":true},{"id":"ghost","price":30,"owned":false},{"id":"squirrel","price":80,"owned":false}]}"#

    /// 지난주(9/7~9/13 KST) 월요일 10:00~18:00 한 판 + 이번 주 화요일 한 판.
    nonisolated static let sessions = #"""
    [
      {"id":"s1","user_id":"u-rankme-0001","started_at":"2026-09-07T01:00:00+00:00","ended_at":"2026-09-07T09:00:00+00:00","duration_seconds":28800},
      {"id":"s2","user_id":"u-rankme-0001","started_at":"2026-09-15T01:00:00.123456+00:00","ended_at":"2026-09-15T03:00:00+00:00","duration_seconds":7200}
    ]
    """#

    nonisolated static func report(_ id: String, user: String, status: String = "open", note: String? = nil, noteAt: String? = nil, created: String) -> String {
        let noteJSON = note.map { "\"\($0)\"" } ?? "null"
        let noteAtJSON = noteAt.map { "\"\($0)\"" } ?? "null"
        return #"{"id":"\#(id)","user_id":"\#(user)","kind":"bug","body":"본문 \#(id)","status":"\#(status)","admin_note":\#(noteJSON),"admin_note_at":\#(noteAtJSON),"app_version":"iOS 0.1.0 (1)","os_version":"iOS 18.0","created_at":"\#(created)","updated_at":null,"display_name":"나","avatar_url":null}"#
    }

    /// 루트 조회 응답기(머리 · 센터 · 착용 · 상점 · 기록 · 답장).
    nonisolated static func rootResponder(_ request: MobileStubRequest) -> MobileStubResponse? {
        if request.path == "/rest/v1/profiles", request.method == "GET" {
            if request.query.contains("display_name,avatar_url") { return .json(#"[{"display_name":"새벽","avatar_url":"https://example.invalid/a.jpg"}]"#) }
            if request.query.contains("select=center") { return .json(#"[{"center":"busan"}]"#) }
            if request.query.contains("select=character") { return .json(#"[{"character":"fox"}]"#) }
            if request.query.contains("token_usage_collect") { return .json(#"[{"token_usage_public":true,"token_usage_collect":true,"focus_mode":true}]"#) }
        }
        if request.path == "/rest/v1/work_sessions", request.method == "GET", request.query.contains("limit=5000") {
            return .json(sessions)
        }
        if request.path == "/rest/v1/token_usage_device_daily", request.method == "GET" {
            return .json(#"[{"day":"2026-09-16","device_id":"mac-1","claude_total":30000000,"codex_total":0,"codex_utc_total":0,"codex_account":null}]"#)
        }
        switch request.rpcName {
        case "shop_state": return .json(shopState)
        case "feedback_reply_latest": return .json(#""2026-09-16T08:00:00+00:00""#)
        default: return nil
        }
    }

    // MARK: 루트

    @Test("시나리오: 탭 표시 → 머리·센터·루비 미러·착용·기록(지난주 회고·잔디·리듬·토큰 잔디)·답장 배지 · 금지 호출 0")
    func rootScenario() async throws {
        let harness = await RankMeHarness(label: "me-root") { Self.rootResponder($0) }
        defer { harness.tearDown() }
        let store = harness.me

        store.appDidBecomeActive()
        try await Task.sleep(for: .milliseconds(50))
        #expect(harness.requests(rpc: "shop_state").isEmpty, "보이지 않는 나 탭이 서버를 두드렸다")

        store.tabDidAppear()
        #expect(await baseWaitUntil { store.headerState.hasLoaded && store.shopState.hasLoaded && store.equippedLoaded && store.recordsState.hasLoaded && store.feedbackReplyLatestAt != nil })
        #expect(store.displayName == "새벽")
        #expect(store.avatarURL?.absoluteString == "https://example.invalid/a.jpg")
        #expect(store.centerServerValue == "busan")
        #expect(store.teamName == "테스트팀")
        #expect(harness.model.gomokuHost.rubyBalance == 40, "상점 잔량이 오목 호스트 루비 미러로 가야 한다(게임 탭 공유)")
        #expect(store.rubyBalance == 40)
        #expect(store.equippedCharacterID == "fox")
        #expect(store.ownedCharacterIDs == ["aing", "fox"])

        // 기록 — 코어 계산 그대로, 목표는 멤버십(40시간).
        let retro = try #require(store.retro)
        #expect(retro.totalSeconds == 28_800)
        #expect(retro.goalSeconds == 40 * 3600)
        #expect(MeText.retroGoalLine(retro) == "목표 40시간 00분 중 20% · 32시간 00분 부족")
        #expect(store.heatmap.totalSeconds == 28_800)
        #expect(MeText.peakLine(store.heatmap) == "가장 활발한 시간: 월요일 10시")
        #expect(store.dailyGrid.totalSeconds == 36_000)
        #expect(store.tokenGrid.totalTokens == 30_000_000)
        #expect(store.showsTokenGrid)
        #expect(store.recordsPlaceholder == nil)
        let sessionQuery = try #require(harness.requests(path: "/rest/v1/work_sessions", method: "GET").first { $0.query.contains("limit=5000") })
        #expect(sessionQuery.query.contains("user_id=eq.\(Self.me)"))
        #expect(sessionQuery.query.contains("ended_at=gte.2026-06-21T15:00:00Z"), "조회 창 = 12주 전 월요일 00:00 KST: \(sessionQuery.query)")

        // 답장 배지: 본 적 없음 → 1
        #expect(store.hasUnseenFeedbackReply)
        #expect(store.badgeCount == 1)

        // 신선하면 다시 부르지 않는다.
        let before = harness.requests.count
        store.tabDidAppear()
        try await Task.sleep(for: .milliseconds(80))
        #expect(harness.requests.filter { $0.rpcName == "shop_state" }.count == 1)
        #expect(harness.requests.count - before <= 1, "신선한 루트를 다시 읽었다(답장 시각만 허용)")

        harness.expectNoForbiddenCalls()
        let profilePatches = harness.requests(path: "/rest/v1/profiles", method: "PATCH")
        #expect(profilePatches.isEmpty, "루트 조회가 프로필을 고쳤다(집중 모드 등)")
    }

    @Test("기록: 멤버십보다 먼저 불려도 목표는 팀 목표(40시간)다 — 기본값 60시간에 굳지 않는다")
    func recordsWaitForTeamGoal() async throws {
        let harness = await RankMeHarness(label: "me-goal", waitsForProfile: false) { request in
            if request.path == "/rest/v1/memberships" {
                return MobileStubResponse(status: 200, body: Data(#"[{"team_id":"team-rankme-1","role":"member","teams":{"name":"테스트팀","weekly_goal_hours":40}}]"#.utf8), delay: 0.3)
            }
            return Self.rootResponder(request)
        }
        defer { harness.tearDown() }
        #expect(harness.model.session.isSignedIn)
        #expect(harness.model.session.profile?.teamID == nil, "전제: 멤버십이 아직 안 왔다")
        await harness.me.loadRecords()
        let retro = try #require(harness.me.retroForDisplay)
        #expect(retro.goalSeconds == 40 * 3600, "목표가 \(retro.goalSeconds / 3600)시간으로 굳었다")
        #expect(harness.me.retro?.goalSeconds == 40 * 3600)
    }

    @Test("기록: 맥에서 근무 중(신호 신선)인 세션은 서버 시작 시각부터 오늘 칸에 얹고, 신호가 끊긴 세션은 얹지 않는다")
    func ongoingSessionUsesServerStartOnlyWhenFresh() async throws {
        for (label, lastSeenAgo, expectedToday) in [("fresh", 30.0, 7_200), ("stale", 1_200.0, 0)] {
            let now = RankMeFixture.now
            let started = RankMeFixture.iso(now.addingTimeInterval(-7_200))
            let seen = RankMeFixture.iso(now.addingTimeInterval(-lastSeenAgo))
            let harness = await RankMeHarness(label: "me-ongoing-\(label)") { request in
                guard request.method == "GET" else { return nil }
                switch request.path {
                case "/rest/v1/work_sessions":
                    if request.query.contains("limit=5000") { return .json("[]") }
                    if request.query.contains("ended_at=is.null") {
                        return .json(#"[{"id":"live","user_id":"\#(Self.me)","started_at":"\#(started)","ended_at":null,"duration_seconds":null}]"#)
                    }
                    return .json("[]")
                case "/rest/v1/work_statuses":
                    return .json(#"[{"user_id":"\#(Self.me)","status":"working","updated_at":"\#(seen)","last_seen_at":"\#(seen)","active_session_id":"live","profiles":{"display_name":"새벽","avatar_url":null}}]"#)
                case "/rest/v1/work_status_devices":
                    return .json("[]")
                default:
                    return nil
                }
            }
            await harness.me.loadRecords()
            let todayWeek = harness.me.dailyGrid.weeks - 1
            let todayIndex = WorkInsightsCalendar.weekdayIndex(for: now)
            #expect(harness.me.recordsState.hasLoaded, "\(label)")
            #expect(harness.me.dailyGrid.seconds[todayWeek][todayIndex] == expectedToday, "\(label): 오늘 칸 \(harness.me.dailyGrid.seconds[todayWeek][todayIndex])")
            // 팀 상태는 읽기만: 근무 세션·상태·기기 표 쓰기 0.
            harness.expectNoForbiddenCalls()
            harness.tearDown()
        }
    }

    // MARK: 상점

    @Test("상점: 카드는 고르기만 · 가진 것은 안내 · 모자라면 요청 없이 안내 · 확인에서만 buy_character · 잔량은 서버 값 · 울트라 경로 없음")
    func shopPurchaseOnlyThroughConfirm() async throws {
        let harness = await RankMeHarness(label: "me-shop") { request in
            if request.rpcName == "buy_character" {
                return .json(#"{"status":"ok","character":"ghost","price":30,"ruby_balance":10}"#)
            }
            return nil
        }
        defer { harness.tearDown() }
        let store = harness.me
        harness.enqueue("shop_state", .json(Self.shopState))
        // 구매 뒤 다시 읽는 상점: 서버가 유령을 보유로, 잔량 10 으로 말한다.
        harness.enqueue("shop_state", .json(#"{"ruby_balance":10,"characters":[{"id":"fox","price":30,"owned":true},{"id":"ghost","price":30,"owned":true},{"id":"squirrel","price":80,"owned":false}]}"#))
        await store.loadShop()
        #expect(store.shopRows.map(\.id) == ["fox", "ghost", "squirrel"])

        store.selectShopItem("fox")
        #expect(store.shopSelection == nil && store.shopNotice == MeText.alreadyOwned)

        store.selectShopItem("squirrel")
        #expect(store.shopSelection == "squirrel")
        #expect(!store.canConfirmPurchase, "40 루비로 80 짜리를 살 수 있다고 했다")
        #expect(store.shopBarDetail == "루비 40개 더 필요해요")
        store.confirmPurchase()
        #expect(store.shopNotice == "루비 40개 더 필요해요")
        try await Task.sleep(for: .milliseconds(50))
        #expect(harness.requests(rpc: "buy_character").isEmpty, "모자란데 요청을 냈다")

        store.selectShopItem("squirrel")
        #expect(store.shopSelection == nil, "같은 카드를 다시 누르면 선택을 푼다")
        store.selectShopItem("ghost")
        try await Task.sleep(for: .milliseconds(50))
        #expect(harness.requests(rpc: "buy_character").isEmpty, "고르기만 했는데 샀다")
        #expect(store.canConfirmPurchase)

        store.confirmPurchase()
        #expect(store.purchasingID == "ghost")
        #expect(await baseWaitUntil { store.purchasingID == nil })
        #expect(harness.requests(rpc: "buy_character").count == 1)
        #expect(harness.requests(rpc: "buy_character").first?.jsonBody["p_id"] as? String == "ghost")
        #expect(store.shopNotice == MeText.bought)
        #expect(store.shopSelection == nil)
        // 성공 뒤 상점을 다시 읽는다(서버가 진실).
        #expect(harness.requests(rpc: "shop_state").count == 2)
        #expect(store.ownedCharacterIDs.contains("ghost"))
        #expect(store.rubyBalance == 10 && harness.model.gomokuHost.rubyBalance == 10)
        harness.expectNoForbiddenCalls()
    }

    @Test("상점: insufficient 응답은 서버가 준 need/have 로 · 잔량을 모르면 사지 않고 다시 읽는다")
    func shopInsufficientAndUnknownBalance() async throws {
        let harness = await RankMeHarness(label: "me-shop-2") { request in
            if request.rpcName == "buy_character" { return .json(#"{"status":"insufficient","need":30,"have":12,"ruby_balance":12}"#) }
            return nil
        }
        defer { harness.tearDown() }
        let store = harness.me
        harness.enqueue("shop_state", .json(#"{"characters":[{"id":"ghost","price":30,"owned":false}]}"#))
        harness.enqueue("shop_state", .json(Self.shopState))
        await store.loadShop()
        store.selectShopItem("ghost")
        #expect(store.rubyBalance == nil)
        store.confirmPurchase()
        #expect(await baseWaitUntil { harness.requests(rpc: "shop_state").count == 2 })
        #expect(harness.requests(rpc: "buy_character").isEmpty, "잔량을 모르는데 샀다")
        #expect(await baseWaitUntil { store.rubyBalance == 40 })
        store.confirmPurchase()
        #expect(await baseWaitUntil { store.shopNotice == "루비 18개 더 필요해요" })
        #expect(store.rubyBalance == 12, "서버가 준 잔량")
    }

    // MARK: 고르기

    @Test("고르기: 안 가진 캐릭터는 요청 없이 상점 안내 · 가진 캐릭터는 set_character(p_id) · 아잉은 null · not_owned 는 소유 지우고 상점 다시 읽기")
    func chooseCharacter() async throws {
        let harness = await RankMeHarness(label: "me-pick") { request in
            if request.rpcName == "shop_state" { return .json(Self.shopState) }
            if request.path == "/rest/v1/profiles", request.query.contains("select=character") { return .json(#"[{"character":null}]"#) }
            return nil
        }
        defer { harness.tearDown() }
        let store = harness.me
        await store.loadShop()
        await store.loadEquippedCharacter()
        #expect(store.equippedCharacterID == "aing")

        store.chooseCharacter("ghost")
        #expect(store.characterNotice == "유령은 아직 없어요 — 상점에서 살 수 있어요")
        try await Task.sleep(for: .milliseconds(40))
        #expect(harness.requests(rpc: "set_character").isEmpty)

        harness.enqueue("set_character", .json(#"{"status":"ok","character":"fox"}"#))
        store.chooseCharacter("fox")
        #expect(await baseWaitUntil { store.savingCharacterID == nil && store.equippedCharacterID == "fox" })
        #expect(harness.requests(rpc: "set_character").last?.jsonBody["p_id"] as? String == "fox")
        #expect(store.characterNotice == MeText.characterSaved)

        harness.enqueue("set_character", .json(#"{"status":"ok","character":null}"#))
        store.chooseCharacter("aing")
        #expect(await baseWaitUntil { store.savingCharacterID == nil && store.equippedCharacterID == "aing" })
        let aingBody = try #require(harness.requests(rpc: "set_character").last)
        #expect(aingBody.bodyText.contains(#""p_id":null"#), "아잉은 null 로 되돌린다: \(aingBody.bodyText)")

        harness.enqueue("set_character", .json(#"{"status":"not_owned"}"#))
        store.chooseCharacter("fox")
        #expect(await baseWaitUntil { store.savingCharacterID == nil && store.characterNotice == MeText.characterNotOwned })
        #expect(!store.ownedCharacterIDs.contains("fox") || harness.requests(rpc: "shop_state").count == 2)
        #expect(await baseWaitUntil { harness.requests(rpc: "shop_state").count == 2 })
        #expect(store.equippedCharacterID == "aing")
        harness.expectNoForbiddenCalls()
    }

    // MARK: 프로필

    @Test("별명: 빈 값·13자는 요청 없이 안내 · ok 는 이름·잠금 · taken · cooldown(날짜 문구) · 네트워크")
    func displayName() async throws {
        let harness = await RankMeHarness(label: "me-name") { _ in nil }
        defer { harness.tearDown() }
        let store = harness.me

        store.displayNameDraft = "   "
        #expect(await store.saveDisplayName() == false)
        #expect(store.displayNameNotice == MeText.displayNameEmpty)
        store.displayNameDraft = "가나다라마바사아자차카타파"
        #expect(MeText.displayNameLength(store.displayNameDraft) == 13)
        #expect(!store.canSaveDisplayName)
        #expect(await store.saveDisplayName() == false)
        #expect(store.displayNameNotice == "별명은 12자까지 쓸 수 있어요")
        #expect(harness.requests(rpc: "set_display_name").isEmpty)

        harness.enqueue("set_display_name", .json(#"{"status":"taken"}"#))
        store.displayNameDraft = " 새벽  별 "
        #expect(await store.saveDisplayName() == false)
        #expect(store.displayNameNotice == MeText.displayNameTaken && store.isDisplayNameNoticeError)
        #expect(harness.requests(rpc: "set_display_name").last?.jsonBody["p_name"] as? String == "새벽 별", "정규화해서 보낸다")

        harness.enqueue("set_display_name", .json(#"{"status":"cooldown","retry_after_seconds":172800}"#))
        #expect(await store.saveDisplayName() == false)
        #expect(store.displayNameNotice == "일주일에 한 번만 바꿀 수 있어요 · 9월 19일부터")
        #expect(!store.isDisplayNameNoticeError && store.isDisplayNameLocked)

        harness.clock.advance(3 * 86_400)
        #expect(!store.isDisplayNameLocked)
        harness.enqueue("set_display_name", .json(#"{"status":"ok","display_name":"새벽 별"}"#))
        #expect(await store.saveDisplayName())
        #expect(store.displayName == "새벽 별")
        #expect(store.isDisplayNameLocked)
        #expect(store.displayNameAvailableAt == MeText.displayNameUnlockDate(changedAt: harness.clock.now))
        harness.expectNoForbiddenCalls()
    }

    @Test("프로필 편집을 머리보다 먼저 열면 이름이 도착할 때 빈 입력을 채운다 · 치던 글은 덮지 않는다")
    func profileDraftFillsWhenHeaderArrivesLate() async throws {
        let harness = await RankMeHarness(label: "me-draft") { Self.rootResponder($0) }
        defer { harness.tearDown() }
        let store = harness.me
        store.profileDidAppear()
        #expect(store.displayNameDraft.isEmpty)
        await store.loadHeader()
        #expect(store.displayNameDraft == "새벽")
        store.displayNameDraft = "치는중"
        await store.loadHeader()
        #expect(store.displayNameDraft == "치는중")
        store.profileDidDisappear()
        #expect(store.displayNameDraft.isEmpty)
        await store.loadHeader()
        #expect(store.displayNameDraft.isEmpty, "편집 화면이 닫혔는데 입력을 채웠다")
    }

    @Test("사진: 원본을 최장변 256px JPEG 로 줄여 storage 에 올리고 avatar_url 만 PATCH · 읽을 수 없는 바이트는 요청 없이 안내")
    func avatarUpload() async throws {
        let harness = await RankMeHarness(label: "me-avatar") { request in
            if request.path.hasPrefix("/storage/v1/object/avatars/") { return .json(#"{"Key":"avatars/x.jpg"}"#) }
            if request.path == "/rest/v1/profiles", request.method == "PATCH" { return MobileStubResponse(status: 204, body: Data()) }
            return nil
        }
        defer { harness.tearDown() }
        let store = harness.me

        await store.uploadAvatar(imageData: Data("not an image".utf8))
        #expect(store.avatarNotice == MeText.avatarUnreadable && store.isAvatarNoticeError)
        #expect(harness.requests.filter { $0.path.hasPrefix("/storage") }.isEmpty)

        await store.uploadAvatar(imageData: try Self.pngData(width: 1200, height: 800))
        #expect(store.avatarNotice == MeText.avatarSaved)
        let upload = try #require(harness.requests.first { $0.path == "/storage/v1/object/avatars/\(Self.me).jpg" })
        #expect(upload.headers["Content-Type"] == "image/jpeg")
        #expect(upload.headers["x-upsert"] == "true")
        let patch = try #require(harness.requests(path: "/rest/v1/profiles", method: "PATCH").first)
        #expect(Set(patch.jsonBody.keys) == ["avatar_url"], "사진 말고 다른 칸을 고쳤다: \(patch.bodyText)")
        #expect(store.avatarURL?.absoluteString.contains("/storage/v1/object/public/avatars/\(Self.me).jpg?v=") == true)
        harness.expectNoForbiddenCalls()
    }

    @Test("사진 줄이기(순수): 1200×800 → 256×171 JPEG · 작은 원본은 키우지 않는다 · 투명 PNG 는 흰 바탕")
    func avatarImageDownscale() throws {
        let big = try #require(MeAvatarImage.jpegData(from: try Self.pngData(width: 1200, height: 800)))
        let bigImage = try #require(Self.decode(big))
        #expect(max(bigImage.width, bigImage.height) == 256)
        #expect(abs(bigImage.height - 171) <= 1)
        #expect(Self.utType(big) == UTType.jpeg.identifier)
        let small = try #require(MeAvatarImage.jpegData(from: try Self.pngData(width: 100, height: 60)))
        let smallImage = try #require(Self.decode(small))
        #expect(smallImage.width == 100 && smallImage.height == 60)
    }

    // MARK: 제보

    @Test("제보: 앱 버전 'iOS 0.1.0 (1)'·OS 버전을 싣고 진단 줄 없음 · 성공은 초안 비우고 목록 다시 읽기(내 것만) · 레이트리밋·스키마 부재는 초안 유지")
    func feedbackSendAndList() async throws {
        let harness = await RankMeHarness(label: "me-feedback") { request in
            if request.rpcName == "feedback_list" {
                return .json("[\(Self.report("r-other", user: "someone-else", created: "2026-09-17T01:00:00Z")),\(Self.report("r-done", user: Self.me, status: "done", note: "고쳤어요", noteAt: "2026-09-16T08:00:00Z", created: "2026-09-16T01:00:00Z")),\(Self.report("r-open", user: Self.me, created: "2026-09-12T01:00:00Z")),\(Self.report("r-open-new", user: Self.me, status: "wontfix_later", created: "2026-09-14T01:00:00Z")),\(Self.report("r-open-newest", user: Self.me, created: "2026-09-15T01:00:00Z"))]")
            }
            if request.rpcName == "feedback_reply_latest" { return .json(#""2026-09-16T08:00:00Z""#) }
            return nil
        }
        defer { harness.tearDown() }
        let store = harness.me

        #expect(store.feedbackAutoAttachNotice == "iOS 0.1.0 (1) · iOS 18.0 정보가 함께 전송돼요")
        store.feedbackDraft = "   "
        #expect(!store.canSendFeedback)

        harness.enqueue("submit_feedback", .json(#"{"message":"FEEDBACK_RATE_LIMIT"}"#, status: 400))
        store.feedbackKind = .request
        store.feedbackDraft = "  위젯이 안 보여요  "
        await store.sendFeedback()
        #expect(store.feedbackNotice == FeedbackText.rateLimited)
        #expect(store.feedbackDraft == "  위젯이 안 보여요  ", "실패했는데 초안을 지웠다")

        harness.enqueue("submit_feedback", .missingFunction("submit_feedback"))
        await store.sendFeedback()
        #expect(store.feedbackNotice == FeedbackText.sendSchemaMissing)

        harness.enqueue("submit_feedback", .json(#""new-id""#))
        await store.sendFeedback()
        #expect(store.feedbackNotice == FeedbackText.sendSuccess)
        #expect(store.feedbackDraft.isEmpty)
        let sent = try #require(harness.requests(rpc: "submit_feedback").last)
        #expect(sent.jsonBody["p_kind"] as? String == "request")
        #expect(sent.jsonBody["p_body"] as? String == "위젯이 안 보여요", "본문에 진단 줄·공백이 섞였다: \(sent.bodyText)")
        #expect(sent.jsonBody["p_app_version"] as? String == "iOS 0.1.0 (1)")
        #expect(sent.jsonBody["p_os_version"] as? String == "iOS 18.0")
        #expect(harness.model.session.isSignedIn, "400 제보 거절로 로그아웃되면 안 된다")

        #expect(store.feedbackList.map(\.id) == ["r-open-newest", "r-open", "r-done", "r-open-new"], "내 것만 · 미해결 먼저 → 최신순(모르는 상태는 미해결이 아니다)")
        #expect(store.feedbackList.last?.status.label == "wontfix_later", "모르는 상태는 원문 그대로")
        #expect(store.feedbackList[2].reply == "고쳤어요")
        harness.expectNoForbiddenCalls()
    }

    @Test("답장 배지: 안 본 답장 → 1 · 제보 화면에 머무는 동안 행 점 유지 · 떠나면 서버 시각을 계정별 키로 적고 0 · 계정 바뀌면 새로 · 딥링크는 제보를 가리킨다")
    func feedbackReplyBadge() async throws {
        let harness = await RankMeHarness(label: "me-badge") { request in
            if request.rpcName == "feedback_reply_latest" { return .json(#""2026-09-16T08:00:00Z""#) }
            if request.rpcName == "feedback_list" {
                return .json("[\(Self.report("r1", user: Self.me, status: "doing", note: "보는 중", noteAt: "2026-09-16T08:00:00Z", created: "2026-09-15T01:00:00Z")),\(Self.report("r0", user: Self.me, status: "done", note: "예전 답장", noteAt: "2026-09-01T08:00:00Z", created: "2026-08-30T01:00:00Z"))]")
            }
            return nil
        }
        defer { harness.tearDown() }
        let store = harness.me
        await store.loadFeedbackReplyLatest()
        #expect(store.badgeCount == 1)

        store.open(.feedback(reportID: "r1"))
        #expect(store.focusedReportID == "r1")
        #expect(harness.model.router.path(for: .me).count == 1)
        store.feedbackDidAppear()
        #expect(await baseWaitUntil { store.feedbackState.hasLoaded })
        #expect(store.focusedReport?.id == "r1")
        #expect(store.isUnseenReply(store.feedbackList[0]), "읽는 동안 점이 먼저 사라졌다")
        #expect(store.feedbackList[1].id == "r0")
        #expect(!store.isUnseenReply(store.feedbackList[1]), "처음 본 폰에서 몇 주 전 답장까지 새 답장으로 칠했다")
        store.feedbackDidDisappear()
        #expect(store.badgeCount == 0)
        #expect(!store.isUnseenReply(store.feedbackList[0]))
        let key = "aing.me.feedbackReplySeenAt.\(Self.me)"
        let stored = try #require(harness.storage.defaults.object(forKey: key) as? Double)
        #expect(stored == ISO8601DateFormatter().date(from: "2026-09-16T08:00:00Z")!.timeIntervalSince1970, "기기 시계가 아니라 서버 답장 시각을 적는다")
        #expect(store.focusedReportID == nil)

        // 로그아웃하면 배지 상태가 사라진다(다음 계정에 물려주지 않는다).
        store.reset()
        #expect(store.badgeCount == 0 && store.feedbackReplyLatestAt == nil)
    }

    // MARK: 설정

    @Test("공개 설정: 낙관 반영 → 실패면 원복 · PATCH 본문은 그 칸 하나(focus_mode·app_build 없음) · 성공하면 순위 탭 칩도 맞춘다")
    func privacyToggles() async throws {
        let harness = await RankMeHarness(label: "me-privacy") { request in
            if request.path == "/rest/v1/profiles", request.method == "GET" {
                if request.query.contains("token_usage_collect") { return .json(#"[{"token_usage_public":true,"token_usage_collect":true,"focus_mode":true}]"#) }
                if request.query.contains("minigame_public") { return .json(#"[{"minigame_public":true}]"#) }
            }
            if request.rpcName == "my_team_invite_code" { return .json(#"[{"invite_code":"ABCD1234"}]"#) }
            if request.path == "/rest/v1/profiles", request.method == "PATCH" {
                if request.bodyText.contains("minigame_public") { return .json(#"{"message":"boom"}"#, status: 500) }
                return MobileStubResponse(status: 204, body: Data())
            }
            return nil
        }
        defer { harness.tearDown() }
        let store = harness.me
        await store.loadSettings()
        #expect(store.tokenUsagePublicLoaded && store.tokenUsagePublic)
        #expect(store.miniGamePublicLoaded && store.miniGamePublic)
        #expect(store.inviteCode == "ABCD1234")
        #expect(MeText.inviteShareMessage(teamName: store.teamName, code: "ABCD1234").contains("ABCD1234"))

        store.setTokenUsagePublic(false)
        #expect(!store.tokenUsagePublic, "낙관 반영")
        #expect(await baseWaitUntil { harness.requests(path: "/rest/v1/profiles", method: "PATCH").count == 1 })
        #expect(await baseWaitUntil { harness.rankings.myTokenUsagePublic == false })
        #expect(!store.tokenUsagePublic)

        store.setMiniGamePublic(false)
        #expect(!store.miniGamePublic)
        #expect(await baseWaitUntil { store.miniGamePublic && store.settingsNotice == MeText.privacySaveFailed }, "실패했는데 원복하지 않았다")

        for patch in harness.requests(path: "/rest/v1/profiles", method: "PATCH") {
            #expect(patch.jsonBody.count == 1, "PATCH 에 다른 칸이 섞였다: \(patch.bodyText)")
            #expect(!patch.bodyText.contains("focus_mode") && !patch.bodyText.contains("app_build"))
        }
        harness.expectNoForbiddenCalls()
    }

    @Test("알림 종류(나 탭 → 푸시 코디네이터 공개 API 하나): 알면 세 칸을 통째로 set_push_prefs · 저장 중 누른 값은 직렬로 한 번 더 · 실패면 코디네이터 문구 · 나가면 문구 지움")
    func pushPrefs() async throws {
        let harness = await RankMeHarness(label: "me-push") { _ in nil }
        defer { harness.tearDown() }
        let store = harness.me
        let push = try #require(store.push, "나 탭이 푸시 코디네이터를 못 본다")
        #expect(push === harness.model.push)
        // 기본 register_device 응답이 {message:true, gomoku_invite:false, feedback_reply:true} 를 준다.
        #expect(await baseWaitUntil { harness.model.session.pushPrefs != nil })
        #expect(push.knowsPrefs)
        #expect(push.prefs == PushPrefs(message: true, gomokuInvite: false, feedbackReply: true))

        harness.enqueue("set_push_prefs", .json(#"{"status":"ok","push_prefs":{"message":true,"gomoku_invite":true,"feedback_reply":true}}"#, delay: 0.2))
        harness.enqueue("set_push_prefs", .json(#"{"status":"ok","push_prefs":{"message":false,"gomoku_invite":true,"feedback_reply":true}}"#))
        let first = Task { await push.setPreference(.gomokuInvite, enabled: true) }
        #expect(await baseWaitUntil { harness.requests(rpc: "set_push_prefs").count == 1 })
        #expect(push.isSavingPrefs && push.isEnabled(.gomokuInvite))
        let second = Task { await push.setPreference(.message, enabled: false) }
        #expect(await baseWaitUntil { !push.isEnabled(.message) }, "저장 중에 누른 값이 보이지 않는다")
        let firstSaved = await first.value
        let secondSaved = await second.value
        #expect(firstSaved && secondSaved)
        #expect(!push.isSavingPrefs)
        let bodies = harness.requests(rpc: "set_push_prefs").compactMap { $0.jsonBody["p_prefs"] as? [String: Bool] }
        #expect(bodies == [
            ["message": true, "gomoku_invite": true, "feedback_reply": true],
            ["message": false, "gomoku_invite": true, "feedback_reply": true],
        ], "저장이 겹치거나 둘째 저장이 최신 값을 싣지 않았다: \(bodies)")
        #expect(harness.model.session.pushPrefs == PushPrefs(message: false, gomokuInvite: true, feedbackReply: true))

        harness.enqueue("set_push_prefs", .json(#"{"message":"boom"}"#, status: 500))
        #expect(await push.setPreference(.message, enabled: true) == false)
        #expect(push.prefsNotice == PushText.settingsSaveFailed)
        #expect(!push.isEnabled(.message), "실패했는데 켜진 채로 보인다")
        store.settingsDidDisappear()
        #expect(push.prefsNotice == nil, "설정 화면을 떠났는데 저장 실패 문구가 남았다")
        harness.expectNoForbiddenCalls()
    }

    @Test("알림 종류: register_device 가 종류 설정을 안 줬으면(모름) 코디네이터가 아무것도 보내지 않는다 · 토글 잠금 근거 knowsPrefs=false")
    func pushPrefsUnknownSendsNothing() async throws {
        let harness = await RankMeHarness(label: "me-push-unknown") { request in
            if request.rpcName == "register_device" { return .json(#"{"status":"ok","device_id":"dev-1"}"#) }
            return nil
        }
        defer { harness.tearDown() }
        let push = try #require(harness.me.push)
        #expect(await baseWaitUntil { !harness.requests(rpc: "register_device").isEmpty })
        try await Task.sleep(for: .milliseconds(50))
        #expect(harness.model.session.pushPrefs == nil)
        #expect(!push.knowsPrefs)
        #expect(await push.setPreference(.message, enabled: false) == false)
        #expect(await push.setPreference(.gomokuInvite, enabled: true) == false)
        try await Task.sleep(for: .milliseconds(80))
        #expect(harness.requests(rpc: "set_push_prefs").isEmpty, "모르는 칸을 기본값으로 채워 보냈다")
        #expect(!push.isSavingPrefs)
        #expect(push.prefsNotice == nil)
    }

    @Test("로그아웃: 세션 로그아웃을 부르고 · 떠 있던 머리 응답은 버리고 · 나 탭 값이 전부 비워진다")
    func signOutResets() async throws {
        let harness = await RankMeHarness(label: "me-signout") { request in
            if request.path == "/rest/v1/profiles", request.query.contains("display_name,avatar_url") {
                return MobileStubResponse(status: 200, body: Data(#"[{"display_name":"늦은이름","avatar_url":null}]"#.utf8), delay: 0.4)
            }
            if request.rpcName == "shop_state" { return .json(Self.shopState) }
            if request.rpcName == "unregister_device" { return .json(#"{"status":"ok","removed":true}"#) }
            if request.path == "/auth/v1/logout" { return .json("{}") }
            return nil
        }
        defer { harness.tearDown() }
        let store = harness.me
        await store.loadShop()
        store.feedbackDraft = "쓰던 글"
        // 당겨서 새로고침(refreshRoot)처럼 스토어 inflight 밖에서 부른 조회 — reset 의 취소가 닿지 않으므로 세대·순번 가드만이 막는다.
        let pull = Task { await store.loadHeader() }
        #expect(await baseWaitUntil { store.headerState.isLoading })
        await store.signOut()
        #expect(!harness.model.session.isSignedIn)
        #expect(harness.requests.contains { $0.path == "/auth/v1/logout" && $0.queryValue("scope") == "local" })
        await pull.value
        #expect(store.displayName == nil, "로그아웃 뒤 늦은 응답이 이름을 세웠다")
        #expect(store.shopCharacters.isEmpty && store.feedbackDraft.isEmpty && !store.isSigningOut)
        #expect(harness.model.gomokuHost.rubyBalance == nil)
        harness.expectNoForbiddenCalls()
    }

    @Test("딥링크: me 는 루트로 · me/shop · me/settings 는 한 칸 쌓기")
    func deepLinks() async {
        let harness = await RankMeHarness(label: "me-links") { _ in nil }
        defer { harness.tearDown() }
        let router = harness.model.router
        router.open(.shop)
        harness.me.open(router.consumePendingRoute(for: .me)!)
        #expect(router.path(for: .me).count == 1)
        router.open(.me)
        harness.me.open(router.consumePendingRoute(for: .me)!)
        #expect(router.path(for: .me).isEmpty)
        router.open(.settings)
        harness.me.open(router.consumePendingRoute(for: .me)!)
        #expect(router.path(for: .me).count == 1)
    }

    // MARK: 도우미

    static func pngData(width: Int, height: Int) throws -> Data {
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    static func decode(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    static func utType(_ data: Data) -> String? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceGetType(source) as String?
    }
}
